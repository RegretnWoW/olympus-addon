-- The lists scripts/council-sign.py wrote with a throwaway key (tests/sign-roundtrip.sh runs
-- this): each loads as the addon loads it, its signature holds with that key, each is newer
-- than the one before, and any change to one is refused. The councils (0.9.9: names, and the
-- departments and titles) are also taken by the addon's own code, as a client takes them.
-- Councils 3 and 4 (1.0.0) are council 1 with the King's Steward marked ("steward"), then with
-- him removed ("steward --remove"): the addon's own code makes him the Steward, then no longer.
-- Councils 5 and 6 (1.1) are the council with an approved guild ("guild"), then without it
-- ("guild --remove"): the addon's own code makes it an Olympus guild, then no longer.
--   luajit tests/sign-roundtrip.lua <repo root> <key file> <a time ahead of the clock> <list.lua> x3 <council.lua> x6
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
for _, file in ipairs({ "Locales", "Core", "Codec", "Sign", "Workshop" }) do
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
		councils[#councils + 1] = { names = lns.COUNCIL_SIGNED, titles = lns.COUNCIL_TITLES }
	end
end
assert(#lists == 3 and #councils == 6, "three lists and six councils")
local function Parts(blob)
	local text, at, realm, names, sig = blob:match("^(HS1~(%d+)~([^~]*)~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, names, sig
end
local function TitleParts(blob)
	local text, at, realm, public, depts, sig = blob:match("^(HT1~(%d+)~([^~]*)~([01])~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, public, depts, sig
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

	-- The councils: two lists each, the titles one second newer than the names, both newer than
	-- anything the key signed before.
	for i, c in ipairs(councils) do
		local _, at, realm = Parts(c.names or "")
		local text, tat, trealm, _, _, sig = TitleParts(c.titles or "")
		check(at and at > last, "council " .. i .. ": its names are newer than the lists before")
		check(text ~= nil and #sig == 512 and Sign.Verify(text, sig), "council " .. i .. ": its titles have the form the addon reads, and verify")
		check(tat == (at or 0) + 1 and trealm == realm, "council " .. i .. ": its titles one second newer, for the same realm group")
		last = tat or last
	end

	-- Taken by the addon, as a client on Forever's realm group takes them from the channel.
	ns.realm, ns.me, ns.rdb = "ClassicBetaPvP", "Tester-ClassicBetaPvP", {}
	local c1 = councils[1]
	check(W.TakeCouncil(c1.names, "Relay-ClassicBetaPvP"), "council 1: its names are taken")
	check(W.TakeTitles(c1.titles, "Relay-ClassicBetaPvP"), "council 1: its titles are taken")
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
	check(c3.titles:find(";^steward^Alliance^Test Steward-ClassicBetaPvP2~", 1, true) ~= nil, "the Steward's entry, trimmed, last")
	-- Changed (another name for the Steward): refused by its signature (a client holding none).
	check(not W.TakeTitles((c3.titles:gsub("Test Steward", "Fake Steward", 1))), "a changed Steward is refused")
	check(not ns.IsSteward("Fake Steward-ClassicBetaPvP2") and ns.rdb.councilTitles == nil, "nobody is the Steward")
	check(W.TakeCouncil(c3.names) and W.TakeTitles(c3.titles, "Relay3-ClassicBetaPvP"), "council 3: taken")
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
	check(not ns.IsSteward("Test Steward-ClassicBetaPvP2"), "removed in a newer list: no longer the Steward")

	-- The approved guilds (1.1): council 5 approves "Test Guild" for the Alliance, council 6 no longer.
	local c5, c6 = councils[5], councils[6]
	check(c5.titles:find(";^guilds^Alliance^Test Guild~", 1, true) ~= nil, "the guild's entry, trimmed, last")
	check(not ns.IsFederation("Test Guild"), "no Olympus guild by its name")
	ourGuild = "Test Guild"
	check(not ns.IsMember(), "its members: no Olympus members")
	check(not W.TakeTitles((c5.titles:gsub("Test Guild", "Fake Guild", 1))), "a changed guild is refused")
	check(W.TakeCouncil(c5.names) and W.TakeTitles(c5.titles, "Relay5-ClassicBetaPvP"), "council 5: taken")
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
	check(not ns.IsFederation("Test Guild") and not ns.IsMember(), "removed in a newer list: no longer an Olympus guild")
	ourGuild = nil
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

if failed > 0 then
	print(("%d signing round trip check(s) failed"):format(failed))
	os.exit(1)
end
print("signing round trip passed")
