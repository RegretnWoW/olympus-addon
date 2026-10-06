-- The lists scripts/council-sign.py wrote with a throwaway key (tests/sign-roundtrip.sh runs
-- this): each loads as the addon loads it, its signature holds with that key, each is newer
-- than the one before, and any change to one is refused. The councils (0.9.9: names, and the
-- departments and titles) are also taken by the addon's own code, as a client takes them.
-- Councils 3 and 4 (1.0.0) are council 1 with the King's Steward marked ("steward"), then with
-- him removed ("steward --remove"): the addon's own code makes him the Steward, then no longer.
-- Councils 5 and 6 (1.1) are the council with an approved guild ("guild"), then without it
-- ("guild --remove"): the addon's own code makes it an Olympus guild, then no longer.
-- Councils 7 and 8 (1.2) are the council with a signed arena arbiter and auditor ("arbiter --audit"),
-- then without him ("arbiter --remove"): the addon's own code makes him one, then no longer.
-- Council 1 and 3-8 carry a separate signed leadership set; council 9 is its empty, higher-epoch
-- tombstone, council 10 omits it to prove the sticky boundary, council 11 is a realistic 92-guild
-- multipart set, and council 12 is the 128-guild/512-person parser and signing bound.
--   luajit tests/sign-roundtrip.lua <repo root> <key file> <future> <list.lua> x3 <council.lua> x12
local root, keyPath, future = arg[1], arg[2], tonumber(arg[3])

-- The addon's files that read the lists, with the few game functions they touch while loading
-- (no frame is ever shown, nothing is sent: Comm is left out). Our guild: none, until council 5.
local function stub() end
CreateFrame = function() return setmetatable({}, { __index = function() return stub end }) end
StaticPopupDialogs, SlashCmdList = {}, {}
local ourGuild
IsInGuild = function() return ourGuild ~= nil end
GetGuildInfo = function() return ourGuild end
GetLocale = function() return "enUS" end
time, date = os.time, os.date
local ns = {}
for _, file in ipairs({ "Locales", "Core", "Codec", "Sign", "Authority", "Workshop" }) do
	if file == "Workshop" then ns.Comm = { Handle = stub } end
	assert(loadfile(root .. "/Olympus/" .. file .. ".lua"))("Olympus", ns)
end
local Sign, W = ns.Sign, ns.Workshop

local failed = 0
local function check(cond, what)
	if cond then print("ok: " .. what) else print("FAIL: " .. what); failed = failed + 1 end
end

-- The public half of the test key (the private half stays in the file).
local f = assert(io.open(keyPath, "r"))
local keyText = f:read("*a")
f:close()
local n, mu = keyText:match('"n"%s*:%s*"0x(%x+)"'), keyText:match('"mu"%s*:%s*"0x(%x+)"')
local k = tonumber(keyText:match('"k"%s*:%s*(%d+)'))
assert(n and mu and k, "the key file has n, mu and k")

-- Each list file as the game loads it: (addon name, the addon's table).
local lists, councils = {}, {}
for i = 4, #arg do
	local lns = {}
	assert(loadfile(arg[i]))("Olympus", lns)
	if i <= 6 then
		check(lns.COUNCIL_TITLES == nil, "list " .. (i - 3) .. ": the names alone, as before 0.9.9")
		lists[#lists + 1] = lns.COUNCIL_SIGNED
	else
		councils[#councils + 1] = { names = lns.COUNCIL_SIGNED, titles = lns.COUNCIL_TITLES,
			authority = lns.COUNCIL_AUTHORITY }
	end
end
assert(#lists == 3 and #councils == 12, "three lists and twelve councils")
local function Parts(blob)
	local text, at, realm, names, sig = blob:match("^(HS1~(%d+)~([^~]*)~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, names, sig
end
local function TitleParts(blob)
	local text, at, realm, public, depts, sig = blob:match("^(HT1~(%d+)~([^~]*)~([01])~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, public, depts, sig
end
local function AuthorityParts(blob)
	local text, at, realm, faction, epoch, issued, expires, rootHash, index, count, body, sig = (blob or ""):match(
		"^(HA1~(%d+)~([^~]*)~(%a+)~enforce~(%d+)~(%d+)~(%d+)~(%x+)~(%d+)~(%d+)~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, faction, tonumber(epoch), tonumber(issued), tonumber(expires),
		rootHash, tonumber(index), tonumber(count), body, sig
end

Sign.WithKey(n, mu, k, function()
	local last = 0
	for i, blob in ipairs(lists) do
		local text, at, _, _, sig = Parts(blob)
		check(text ~= nil and #sig == 512, "list " .. i .. " has the form the addon reads")
		check(text ~= nil and Sign.Verify(text, sig), "list " .. i .. " verifies with the test key")
		check(at and at > last, "list " .. i .. " is newer than the one before")
		last = at or last
	end
	local text1, at1, realm1, names1, sig1 = Parts(lists[1])
	local text2, _, _, _, sig2 = Parts(lists[2])
	local _, at3, realm3 = Parts(lists[3])
	check(names1 == "Test Councillor,Other Mod,F\195\160ladoriel Test", "names trimmed, an accented one byte for byte: " .. names1)
	check(realm1 == "Realm" and realm3 == "ClassicBetaPvP+ClassicBetaPvP2", "the realm group given, or Forever's")
	check(at3 > future, "newer than the last list the key signed, even ahead of the clock")
	-- Any change is refused.
	check(not Sign.Verify((text1:gsub("Other Mod", "Other Mad")), sig1), "a changed name is refused")
	check(not Sign.Verify(text1 .. ",Faker Guy", sig1), "an added name is refused")
	check(not Sign.Verify((text1:gsub("^HS1~%d+", "HS1~" .. (at1 + 1))), sig1), "a changed time is refused")
	check(not Sign.Verify((text1:gsub("~" .. realm1 .. "~", "~Other~")), sig1), "a changed realm group is refused")
	local digit = sig1:sub(-1)
	check(not Sign.Verify(text1, sig1:sub(1, -2) .. (digit == "0" and "1" or "0")), "a changed signature is refused")
	check(not Sign.Verify(text1, sig2), "another list's signature is refused")
	check(not Sign.Verify(text1, sig1:sub(2)) and not Sign.Verify(text1, "0" .. sig1), "a signature of another length is refused")

	-- The councils: two public lists each, plus zero or more separately signed authority parts.
	-- Titles are one second newer than names; every authority set is another second newer.
	for i, c in ipairs(councils) do
		local _, at, realm = Parts(c.names or "")
		local text, tat, trealm, _, _, sig = TitleParts(c.titles or "")
		check(at and at > last, "council " .. i .. ": its names are newer than the lists before")
		check(text ~= nil and #sig == 512 and Sign.Verify(text, sig), "council " .. i .. ": its titles have the form the addon reads, and verify")
		check(tat == (at or 0) + 1 and trealm == realm, "council " .. i .. ": its titles one second newer, for the same realm group")
		local newest = tat or last
		for j, blob in ipairs(c.authority or {}) do
			local atext, aat, arealm, _, _, _, _, _, index, count, _, asig = AuthorityParts(blob)
			check(atext ~= nil and #asig == 512 and Sign.Verify(atext, asig),
				("council %d: authority part %d has the form the addon reads, and verifies"):format(i, j))
			check(aat == (at or 0) + 2 and arealm == realm and index == j and count == #c.authority,
				("council %d: authority part %d names the same generation and complete set"):format(i, j))
			newest = math.max(newest, aat or 0)
		end
		last = newest
	end

	-- Taken by the addon, as a client on Forever's realm group takes them from the channel.
	ns.realm, ns.group, ns.me, ns.rdb, ns.db = "ClassicBetaPvP", "ClassicBetaPvP+ClassicBetaPvP2", "Tester-ClassicBetaPvP", {}, { log = {} }
	local c1 = councils[1]
	check(W.TakeCouncil(c1.names, "Relay-ClassicBetaPvP"), "council 1: its names are taken")
	check(W.TakeTitles(c1.titles, "Relay-ClassicBetaPvP"), "council 1: its titles are taken")
	check(not ns.Authority.Enforced(), "ordinary HT1 does not silently activate cross-guild authority")
	check(ns.Authority.LoadLocal(c1.authority), "council 1: its separate signed authority set is taken")
	check(ns.Authority.Enforced(), "council 1: its explicit signed leadership activates enforcement")
	check(ns.Authority.Rank("Test Lord-ClassicBetaPvP", "Olympus Zeus") == 0
		and ns.Authority.Rank("Test Captain-ClassicBetaPvP2", "Olympus Zeus") == 1,
		"council 1: exact-realm Lord and Captain ranks come from the signed extension")
	local _, _, realm, names = Parts(c1.names)
	check(realm == "ClassicBetaPvP+ClassicBetaPvP2", "Forever's realm group by default")
	check(names == "Test Councillor,Other Mod,F\195\160ladoriel Test,Third Mod", "every name, outside any department first: " .. names)
	check(ns.rdb.councilTitles.public == false, "not public")
	local loose, depts = W.CouncilTree()
	check(#loose == 1 and loose[1].name == "Test Councillor" and loose[1].title == "Council Speaker", "outside any department, trimmed")
	check(#depts == 2 and depts[1].name == "Department of War" and depts[1].icon == "INV_Sword_04" and depts[2].icon == 133784,
		"the departments in order, with their icons")
	local war = depts[1] and depts[1].members or {}
	check(#war == 2 and war[1].title == "Operations Director" and war[2].name == "F\195\160ladoriel Test" and war[2].title == nil,
		"their councillors in order, an accented name byte for byte, a title left out")
	local oldNs = setmetatable({ rdb = {}, Comm = { Handle = stub } }, { __index = ns })
	local W99 = assert(loadfile(root .. "/tests/fixtures/titles-0.9.9.lua"))(oldNs, W)
	check(W99.TakeTitles(c1.titles) and oldNs.rdb.councilTitles.blob == c1.titles,
		"the 0.9.9 reader takes the compatible HT1 while ignoring the separate new authority file")
	local oldDepts = oldNs.rdb.councilTitles.depts
	check(#oldDepts == 3 and oldDepts[2].name == "Department of War" and oldDepts[3].name == "Department of Coin",
		"the 0.9.9 ReadDepartments keeps the same council")
	local title = ns.CouncilTitle("Third Mod-ClassicBetaPvP2")
	check(title and title.title == "Keeper of Coin" and title.dept == "Department of Coin", "a title, on the other realm of the group")
	-- Any change to the titles is refused (a client holding none).
	local text, _, _, _, _, sig = TitleParts(c1.titles)
	for _, change in ipairs({
		{ "a changed title", "Operations Director", "Grand Admiral" },
		{ "a changed department", "Department of War", "Department of Fun" },
		{ "a changed public flag", "PvP2~0~", "PvP2~1~" },
		{ "a changed time", "^HT1~%d+", "HT1~9999999999" },
		{ "a changed realm group", "~ClassicBetaPvP%+ClassicBetaPvP2~", "~Realm~" },
	}) do
		local changed, count = text:gsub(change[2], change[3], 1)
		ns.rdb.councilTitles = nil
		check(count == 1 and not W.TakeTitles(changed .. "~" .. sig), change[1] .. " is refused")
	end
	check(not Sign.Verify(text, (TitleParts(councils[2].titles))), "another list's signature is refused")
	local authorityText, _, _, _, _, _, _, _, _, _, _, authoritySig = AuthorityParts(c1.authority[1])
	local alteredLeadership, altered = authorityText:gsub("Test Lord", "Fake Lord", 1)
	check(altered == 1 and not ns.Authority.TakePart(alteredLeadership .. "~" .. authoritySig, nil, "LOCAL"),
		"a changed separate leadership manifest is refused by the author's signature")

	-- The limits: everything the signing script lets through, the addon keeps whole.
	ns.realm, ns.me, ns.rdb = "Realm", "Tester-Realm", {}
	local c2 = councils[2]
	check(#c2.titles <= W.TITLES_BLOB and #c2.names <= 2000, "both lists within what the addon takes (" .. #c2.titles .. " bytes of titles)")
	check(W.TakeCouncil(c2.names) and W.TakeTitles(c2.titles), "council 2: taken")
	local t, kept, named = ns.rdb.councilTitles, 0, 0
	for _, d in ipairs(t.depts) do
		if d.name ~= "" then named = named + 1 end
		for _, m in ipairs(d.members) do
			if m.title and #m.title == W.TITLE_MAX and ns.IsHighCouncillor(m.name) then kept = kept + 1 end
		end
	end
	check(t.public == true, "public")
	check(kept == W.COUNCIL_MAX, "30 councillors, each with a title of 48 bytes, on the name list: " .. kept)
	check(named == W.DEPTS_MAX and #t.depts[2].name == W.DEPT_NAME and t.depts[2].icon == 2147483647,
		"8 departments, names of 40 bytes, an icon's highest file number")
	loose, depts = W.CouncilTree()
	check(#loose == 2 and #depts == W.DEPTS_MAX, "all of it in the census")

	-- The King's Steward (1.0.0): council 1 again with him marked, then without him, each newer.
	ns.realm, ns.me, ns.rdb, ns.faction = "ClassicBetaPvP", "Tester-ClassicBetaPvP", {}, "Alliance"
	local c3, c4 = councils[3], councils[4]
	local _, at3t = TitleParts(c3.titles)
	local _, at4t = TitleParts(c4.titles)
	check(at4t > at3t, "council 4 newer than council 3")
	check(c3.titles:find(";^steward^Alliance^Test Steward-ClassicBetaPvP2", 1, true) ~= nil
		and not c3.titles:find("^leaders^", 1, true), "the Steward's entry is trimmed and HT1 remains compatible")
	-- Changed (another name for the Steward): refused by its signature (a client holding none).
	check(not W.TakeTitles((c3.titles:gsub("Test Steward", "Fake Steward", 1))), "a changed Steward is refused")
	check(not ns.IsSteward("Fake Steward-ClassicBetaPvP2") and ns.rdb.councilTitles == nil, "nobody is the Steward")
	check(W.TakeCouncil(c3.names) and W.TakeTitles(c3.titles, "Relay3-ClassicBetaPvP"), "council 3: taken")
	check(ns.Authority.LoadLocal(c3.authority), "council 3: its authority set is taken")
	check(ns.IsSteward("Test Steward-ClassicBetaPvP2"), "the Steward, on his realm")
	check(ns.IsSteward("Test Steward-ClassicBetaPvP") and ns.IsSteward("test steward"), "and on the other realm of the group, whatever the case")
	check(not ns.IsSteward("Test Steward-Elsewhere"), "a namesake on another realm group is nobody")
	check(not ns.IsSteward("Test Councillor-ClassicBetaPvP"), "a councillor is not the Steward")
	ns.faction = "Horde"
	check(not ns.IsSteward("Test Steward-ClassicBetaPvP2"), "the Horde's King: none, the list names none for him")
	ns.faction = "Alliance"
	loose, depts = W.CouncilTree()
	check(#loose == 1 and #depts == 2, "the census shows the same departments, no entry for the Steward")
	check(W.TakeTitles(c4.titles, "Relay4-ClassicBetaPvP"), "council 4: taken")
	check(ns.Authority.LoadLocal(c4.authority), "council 4: its authority set is taken")
	check(not ns.IsSteward("Test Steward-ClassicBetaPvP2"), "removed in a newer list: no longer the Steward")

	-- The approved guilds (1.1): council 5 approves "Test Guild" for the Alliance, council 6 no longer.
	local c5, c6 = councils[5], councils[6]
	check(c5.titles:find(";^guilds^Alliance^Test Guild", 1, true) ~= nil
		and not c5.titles:find("^leaders^", 1, true), "the approved guild entry is trimmed and HT1 remains compatible")
	check(not ns.IsFederation("Test Guild"), "no Olympus guild by its name")
	ourGuild = "Test Guild"
	check(not ns.IsMember(), "its members: no Olympus members")
	check(not W.TakeTitles((c5.titles:gsub("Test Guild", "Fake Guild", 1))), "a changed guild is refused")
	check(W.TakeCouncil(c5.names) and W.TakeTitles(c5.titles, "Relay5-ClassicBetaPvP"), "council 5: taken")
	check(ns.Authority.LoadLocal(c5.authority), "council 5: its authority set is taken")
	check(ns.IsFederation("Test Guild") and ns.IsFederation("TEST GUILD"), "an Olympus guild now, whatever the case")
	check(ns.IsMember(), "and its members Olympus members")
	ns.faction = "Horde"
	check(not ns.IsFederation("Test Guild"), "the Alliance's alone")
	ns.faction = "Alliance"
	ns.realm, ns.me = "Elsewhere", "Tester-Elsewhere"
	check(not ns.IsFederation("Test Guild"), "on the list's realm group alone")
	ns.realm, ns.me = "ClassicBetaPvP", "Tester-ClassicBetaPvP"
	loose, depts = W.CouncilTree()
	check(#loose == 1 and #depts == 2, "the census shows the same departments, no entry for the guilds")
	check(W.TakeTitles(c6.titles, "Relay6-ClassicBetaPvP"), "council 6: taken")
	check(ns.Authority.LoadLocal(c6.authority), "council 6: its authority set is taken")
	check(not ns.IsFederation("Test Guild") and not ns.IsMember(), "removed in a newer list: no longer an Olympus guild")
	ourGuild = nil

	-- The Blood Arena's signed arbiters (1.2): council 7 names "Test Arbiter" an arbiter and an
	-- auditor for the Alliance, council 8 no longer.
	local c7, c8 = councils[7], councils[8]
	check(c7.titles:find(";^arbiter^Alliance^Test Arbiter-ClassicBetaPvP2+a", 1, true) ~= nil
		and not c7.titles:find("^leaders^", 1, true), "the arbiter entry is trimmed and HT1 remains compatible")
	check(not W.TakeTitles((c7.titles:gsub("Test Arbiter", "Fake Arbiter", 1))), "a changed arbiter is refused")
	check(not ns.IsSignedArbiter("Fake Arbiter-ClassicBetaPvP2"), "nobody is that arbiter")
	-- (Taken as the author's own client takes his file: the relays' check budget went to the councils before.)
	check(W.TakeCouncil(c7.names) and W.TakeTitles(c7.titles), "council 7: taken")
	check(ns.Authority.LoadLocal(c7.authority), "council 7: its authority set is taken")
	check(ns.IsSignedArbiter("Test Arbiter-ClassicBetaPvP2") and ns.IsSignedArbiter("test arbiter-ClassicBetaPvP"), "the arbiter, on the realm group, whatever the case")
	check(ns.IsSignedAuditor("Test Arbiter-ClassicBetaPvP2"), "and an auditor")
	check(not ns.IsSignedArbiter("Test Arbiter-Elsewhere"), "a namesake on another realm group is nobody")
	loose, depts = W.CouncilTree()
	check(#loose == 1 and #depts == 2, "the census shows the same departments, no entry for the arbiters")
	check(W.TakeTitles(c8.titles), "council 8: taken")
	check(ns.Authority.LoadLocal(c8.authority), "council 8: its authority set is taken")
	check(not ns.IsSignedArbiter("Test Arbiter-ClassicBetaPvP2"), "removed in a newer list: no longer an arbiter")

	-- The signed-leadership migration: an empty higher epoch revokes everybody. Once accepted,
	-- the still newer old-format HT1 cannot reopen census authority, and an older signed manifest
	-- cannot replay because Workshop accepts newer HT1 only.
	local c9, c10 = councils[9], councils[10]
	check(W.TakeTitles(c9.titles) and ns.Authority.LoadLocal(c9.authority),
		"council 9: the separate explicit empty leadership tombstone is taken")
	check(ns.Authority.Enforced() and ns.Authority.Rank("Test Lord-ClassicBetaPvP", "Olympus Zeus") == nil,
		"the tombstone keeps enforcement and revokes the old Lord")
	check(W.TakeTitles(c10.titles), "council 10: a newer legacy HT1 is taken")
	check(ns.Authority.Enforced() and ns.Authority.Rank("Test Lord-ClassicBetaPvP", "Olympus Zeus") == nil,
		"newer absence cannot reopen authority after activation")
	check(not W.TakeTitles(c8.titles), "an older leadership manifest cannot replay")
	check(not ns.Authority.LoadLocal(c8.authority), "nor can its separate authority set replay")

	-- The signer and client agree for the real 92-guild scale and the exact configured bounds.
	ns.realm, ns.group, ns.me, ns.rdb, ns.faction = "R", "R", "Tester-R", {}, "Alliance"
	local c11, c12 = councils[11], councils[12]
	check(#c11.authority > 1 and W.TakeTitles(c11.titles) and ns.Authority.LoadLocal(c11.authority),
		"council 11: the realistic 92-guild multipart authority set is taken atomically")
	local manifest, count = ns.Authority.Manifest(), 0
	for _ in pairs(manifest and manifest.guilds or {}) do count = count + 1 end
	check(count == 92, "the realistic manifest keeps all 92 guilds: " .. count)
	check(#c12.authority > 1 and W.TakeTitles(c12.titles) and ns.Authority.LoadLocal(c12.authority),
		"council 12: the maximum multipart authority set is taken atomically")
	manifest, count = ns.Authority.Manifest(), 0
	local people = 0
	for _ in pairs(manifest and manifest.guilds or {}) do count = count + 1 end
	for _ in pairs(manifest and manifest.people or {}) do people = people + 1 end
	check(count == ns.Authority.MAX_GUILDS and people == ns.Authority.MAX_TOTAL,
		("the maximum manifest keeps all %d guilds and %d people"):format(count, people))
end)
-- Back to the author's key: the test key's lists are nobody's.
local text1, _, _, _, sig1 = Parts(lists[1])
check(not Sign.Verify(text1, sig1), "the author's key refuses a list of the test key")
local text, _, _, _, _, sig = TitleParts(councils[1].titles)
check(not Sign.Verify(text, sig), "the author's key refuses a titles list of the test key")
text, _, _, _, _, sig = TitleParts(councils[3].titles)
check(not Sign.Verify(text, sig), "the author's key refuses a Steward marked with the test key")
text, _, _, _, _, sig = TitleParts(councils[5].titles)
check(not Sign.Verify(text, sig), "the author's key refuses a guild approved with the test key")
text, _, _, _, _, sig = TitleParts(councils[7].titles)
check(not Sign.Verify(text, sig), "the author's key refuses an arbiter signed with the test key")
text, _, _, _, _, sig = TitleParts(councils[9].titles)
check(not Sign.Verify(text, sig), "the author's key refuses the tombstone council titles signed with the test key")
for _, i in ipairs({ 1, 3, 5, 7, 9, 11, 12 }) do
	local atext, _, _, _, _, _, _, _, _, _, _, asig = AuthorityParts(councils[i].authority[1])
	check(not Sign.Verify(atext, asig), "the author's key refuses council " .. i .. "'s authority signature from the test key")
end

if failed > 0 then
	print(("%d signing round trip check(s) failed"):format(failed))
	os.exit(1)
end
print("signing round trip passed")
