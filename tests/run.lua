-- Offline tests for the addon: codec, election, roster scan, aggregation, and the windows
-- (guild window button, docking, layout) on stand-in frames.
-- Run: luajit tests/run.lua   (from the repo root)

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"
local ADDON_DIR = ROOT .. "Olympus/"

---------------------------------------------------------------------------
-- Minimal WoW API stubs
---------------------------------------------------------------------------
local stub = setmetatable({}, { __index = function() return function() end end })
EVENT_SCRIPTS = {}
function CreateFrame()
	return setmetatable({ SetScript = function(_, kind, fn) if kind == "OnEvent" then EVENT_SCRIPTS[#EVENT_SCRIPTS + 1] = fn end end },
		{ __index = function() return function() end end })
end
C_Timer = { After = function() end, NewTicker = function() end }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetLocale() return "enUS" end
function UnitFullName() return "Tester", "Realm" end
function IsInGuild() return true end
function GetBuildInfo() return "1.15.8", "99999", "", 11508 end
function geterrorhandler() return function() end end
C_AddOns = { LoadAddOn = function() end }
WorldMapFrame = {}
function GetTime() return os.clock() end
function GetRealmName() return "Realm" end
function seterrorhandler() end
function debugprofilestop() return os.clock() * 1000 end
time, date = os.time, os.date
SlashCmdList = {}
StaticPopupDialogs = {}
function GetTime() return os.clock() end
function GetRealmName() return "Realm" end
function LibStub() return nil end
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
	return unpack(out)
end
function IsInInstance() return false end
function GuildControlGetNumRanks() return 4 end
function GuildControlGetRankName(i) return ({ "Zeus", "Titan", "Hero", "Recruit" })[i] end
function GetGuildRosterLastOnline(i) if i > 900 then return 0, 1, 2, 0 end return 0, 0, 0, 5 end
Enum = { UIMapType = { Continent = 2, Zone = 3 } }

local MAPS = {
	[947] = { "Azeroth", 1 }, [1415] = { "Eastern Kingdoms", 2 }, [1429] = { "Elwynn Forest", 3 },
	[1453] = { "Stormwind City", 3 }, [1436] = { "Westfall", 3 },
}
local CHILDREN = { [947] = { 1415 }, [1415] = { 1429, 1453, 1436 } }
C_Map = {
	GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m[1], mapType = m[2] } end,
	GetMapChildrenInfo = function(id)
		local out = {}
		for _, c in ipairs(CHILDREN[id] or {}) do out[#out + 1] = C_Map.GetMapInfo(c) end
		return out
	end,
}

local MY_GUILD = "Olympus II"
function GetGuildInfo() return MY_GUILD end
local ZONES = { "Stormwind City", "Elwynn Forest", "Westfall", "The Stockade" }
local CLASSES = { "WARRIOR", "PALADIN", "MAGE", "PRIEST" }
function GetNumGuildMembers() return 1000, 300 end
function GetGuildRosterInfo(i)
	local online = i <= 300
	local rank = i == 1 and 0 or (i <= 6 and 1 or 3)
	return "Member" .. i .. "-Realm", "rank", rank, (i % 30) + 1, "class",
		online and ZONES[(i % #ZONES) + 1] or nil, "", "", online, 0, CLASSES[(i % #CLASSES) + 1]
end

---------------------------------------------------------------------------
-- Load addon files like WoW does: each gets (addonName, sharedTable)
---------------------------------------------------------------------------
local ns = {}
for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Dialog", "Codec", "Zones", "Who", "Data", "Roster", "Comm", "Map", "Layers", "Hop", "Positions", "Decree", "Channels", "Inspect", "King", "Vox", "Court", "Treasury", "Bank", "Acts", "Workshop", "Recruit", "Views" }) do
	local chunk = assert(loadfile(ADDON_DIR .. file .. ".lua"))
	chunk("Olympus", ns)
end
ns.db = { guilds = {}, log = {}, errors = {}, blocked = {}, demo = false, showMap = true,
	chatWarned = { A = true, C = true, L = true }, -- (0.9.1: the channel warnings already accepted; their own tests ask)
	treasurerShares = true } -- (0.9.3: the Treasurer said yes; the question has its own test)
ns.me = "Tester-Realm"
ns.realm = "Realm"
-- (0.9.2: the King and the Treasurer are theirs on their realm group; here that is "Realm".)
ns.KING_REALM, ns.TREASURER_REALM = "Realm", "Realm"
ns.rdb = { guilds = {} }
local CoreFire = ns.Fire -- the real one, for the tests that need INIT
function ns.Fire() end

---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- A stored report as if `...` (other senders) had each just reported the same ranks: ranks
-- from other guilds count only when someone else's recent report names them (Data.KnownRank).
local function Vouched(g, ...)
	local home, ranks = g.realm or "Realm", {}
	local function full(name) return name:find("-", 1, true) and name or (name .. "-" .. home) end
	for _, o in ipairs(g.officers or {}) do ranks[full(o.name)] = 1 end
	if g.leader then ranks[full(g.leader)] = 0 end
	g.vouch = {}
	for _, src in ipairs({ ... }) do g.vouch[src] = { t = g.t, sig = "fixture", ranks = ranks } end
	return g
end

local Codec = ns.Codec

test("federation filter matches any guild with 'olympus' in the name", function()
	eq(ns.IsFederation("Olympus"), true)
	eq(ns.IsFederation("OLYMPUS IV"), true)
	eq(ns.IsFederation("Sons of olympus"), true)
	eq(ns.IsFederation("Olympia"), false)
	eq(ns.IsFederation(nil), false)
end)

test("federation filter against 250 misspellings and 400 look-alike guild names (tests/fixtures)", function()
	local function Read(file)
		local out = {}
		for line in io.lines("tests/fixtures/" .. file) do if line ~= "" then out[#out + 1] = line end end
		return out
	end
	-- Known and accepted: a P for the O plus another slip; Olympe is French for Olympus;
	-- Oympia is Olympia misspelled.
	local expected = { ["Plympys III"] = false, ["Olympe"] = true, ["Oympia"] = true }
	local wrong = {}
	for _, name in ipairs(Read("olympus-yes.txt")) do
		local want = expected[name]
		if want == nil then want = true end
		if ns.IsFederation(name) ~= want then wrong[#wrong + 1] = name end
	end
	for _, name in ipairs(Read("olympus-no.txt")) do
		local want = expected[name]
		if want == nil then want = false end
		if ns.IsFederation(name) ~= want then wrong[#wrong + 1] = name end
	end
	eq(table.concat(wrong, ", "), "")
end)

test("WoW: Forever names: first name and surname, never taken for a realm", function()
	local saved = { UnitFullName = UnitFullName, GetUnitName = GetUnitName, realm = ns.realm, split = ns.splitNames, CurrentRealm = ns.CurrentRealm }
	local ok, err = pcall(function()
		ns.realm = "ClassicBetaPvP"
		ns.CurrentRealm = function() return "ClassicBetaPvP" end
		-- Forever hands back "Faladoriel", "Skylance": the surname where the realm goes.
		UnitFullName = function(unit)
			if unit == "player" then return "Faladoriel", "Skylance" end
			if unit == "target" then return "Pyralis", "Ashandar" end
			if unit == "party1" then return "Mate", nil end
		end
		ns.splitNames = nil
		eq(ns.PlayerName(), "Faladoriel Skylance-ClassicBetaPvP", "as the server stamps our messages")
		eq(ns.splitNames, true)
		eq(ns.UnitFullName("target"), "Pyralis Ashandar-ClassicBetaPvP")
		eq(ns.UnitFullName("party1"), "Mate-ClassicBetaPvP")
		eq(ns.Normal("Pyralis-Ashandar"), "Pyralis Ashandar")
		eq(ns.Normal("Pyralis-Ashandar-ClassicBetaPvP2"), "Pyralis Ashandar-ClassicBetaPvP2")
		eq(ns.Normal("Bob-ClassicBetaPvP2"), "Bob-ClassicBetaPvP2", "a realm stays a realm")
		eq(ns.Normal("Pyralis Ashandar-ClassicBetaPvP"), "Pyralis Ashandar-ClassicBetaPvP")
		-- A Classic realm: the realm is a realm, whatever it is called.
		ns.realm = "Nightslayer"
		ns.CurrentRealm = function() return "Nightslayer" end
		UnitFullName = function(unit)
			if unit == "player" then return "Peepyn", "Nightslayer" end
			return "Bob", "Dreamscythe"
		end
		ns.splitNames = nil
		eq(ns.PlayerName(), "Peepyn-Nightslayer")
		eq(ns.splitNames, nil)
		eq(ns.UnitFullName("target"), "Bob-Dreamscythe")
		eq(ns.Normal("Bob-Dreamscythe"), "Bob-Dreamscythe")
	end)
	UnitFullName, GetUnitName, ns.realm, ns.splitNames, ns.CurrentRealm = saved.UnitFullName, saved.GetUnitName, saved.realm, saved.split, saved.CurrentRealm
	if not ok then error(err, 0) end
end)

test("federation filter: Olympus however it was spelled, but not other words", function()
	for _, name in ipairs({ "OLYMPVS", "Olympvs II", "Olimpus", "Olmpus", "Olympos", "Olypmus", "Olyympus", "0lympus",
		"Lympus", "OlimpusII", "Knights of Olmpus", "Olimpo", "Olympo Brasil", "Ólympus",
		"Olimpvs", "OLMPVS", "Olmps", "Olympuz", "OLIMPUZ", "Olymppus", "Olymp", "Olympia Olympus",
		"Olypmvs", "Olmypus", "Oympus", "Olumpus", "Olympe", "Oylmpus", "Olyompus" }) do
		eq(ns.IsFederation(name), true, name)
	end
	for _, name in ipairs({ "Olympia", "Olympic Heroes", "Olympians", "Olympiad", "Olimpia", "Olimpico", "Polymath",
		"Holy Light", "Oly", "Olmo", "The Pumpkins", "Glyphs R Us", "Lumps", "Oblivion", "Polymer", "Lymph" }) do
		eq(ns.IsFederation(name), false, name)
	end
	-- Guilds against Olympus are not Olympus.
	for _, name in ipairs({ "ANTI OLYMPUS", "Anti-Olympus", "AntiOlympus", "Anti Olimpvs", "Against Olympus", "No Olympus",
		"Down with Olympus", "Death to Olympus", "Olympus Haters", "Olympus Sucks", "Kill Olympus" }) do
		eq(ns.IsFederation(name), false, name)
	end
	for _, name in ipairs({ "Knights of Olympus", "Sons of Olympus", "Olympus No Mercy", "OLYMPUS NULLA", "Order of the Olympus",
		"Olympus Killers", "Anti Horde Olympus" }) do
		eq(ns.IsFederation(name), true, name)
	end
	eq(ns.Slips("olmps", "olympus", 2), 2); eq(ns.Slips("olympia", "olympus", 2), 2); eq(ns.Slips("abcdefg", "olympus", 2), 3)
	eq(ns.Slips("olypmus", "olympus", 2), 1, "two neighbours swapped: one slip")
	-- The main guild is still the exact name: the King and the Crown's officers.
	eq(ns.IsCrownRank("OLYMPVS", 1), false, "an officer of a look-alike guild is no Crown officer")
	eq(ns.IsCrownRank("Olympus", 1), true)
end)

test("number formatting", function()
	eq(ns.FormatNumber(0), "0")
	eq(ns.FormatNumber(999), "999")
	eq(ns.FormatNumber(18420), "18,420")
	eq(ns.FormatNumber(1234567), "1,234,567")
end)

test("roster scan of 1000 members", function()
	local r = ns.Roster.Scan()
	eq(r.guild, MY_GUILD)
	eq(r.total, 1000)
	eq(r.online, 300)
	eq(r.leader, "Member1")
	eq(r.zones["m1453"], 75, "stormwind")
	eq(r.zones["tThe Stockade"], 75, "unresolved zone kept as text")
	local sum = 0
	for _, n in pairs(r.levels) do sum = sum + n end
	eq(sum, 300, "level bands")
end)

test("report encode/decode round trip", function()
	local r = ns.Roster.Scan()
	r.users = 4
	local d = Codec.DecodeReport(Codec.EncodeReport(r))
	eq(d.guild, r.guild); eq(d.total, 1000); eq(d.online, 300); eq(d.leader, "Member1")
	eq(d.users, 4); eq(d.zones["m1429"], r.zones["m1429"]); eq(d.classes.WA, r.classes.WA)
	eq(d.levels[1], r.levels[1])
end)

test("chunks fit in 255 bytes and reassemble out of order", function()
	local r = { guild = "Olympus Poseidon", total = 1000, online = 900, leader = "Somebody", users = 1,
		zones = {}, classes = {}, levels = {} }
	for i = 1, 90 do r.zones["m" .. (1400 + i)] = i end
	local payload = Codec.EncodeReport(r)
	local chunks = Codec.Chunk(payload, "7")
	assert(#chunks > 1, "expected several chunks")
	for _, c in ipairs(chunks) do assert(#c <= 255, "chunk too long: " .. #c) end
	local asm = Codec.NewAssembler()
	local full
	for i = #chunks, 1, -1 do full = Codec.Feed(asm, "A-Realm", chunks[i], 0) or full end
	eq(full, payload)
end)

test("decoder rejects garbage and clamps numbers", function()
	eq(Codec.DecodeReport("hello"), nil)
	eq(Codec.DecodeReport("R1~~1~1~~0~0~~~"), nil, "empty guild")
	eq(Codec.DecodeReport(("R1~%s~1~1~~0~0~~~"):format(("x"):rep(30))), nil, "long guild name")
	eq(Codec.DecodeReport("R1~Olympus~99999999~5~Boss~1~2~m1453=99999999~~1,2"), nil, "a guild bigger than the game allows: forged")
	eq(Codec.DecodeReport("R1~Olympus~1001~5~Boss~1~2~~~1,2"), nil)
	local d = Codec.DecodeReport("R1~Olympus~1000~5000~Boss~1~2~m1453=99999999~~1,2")
	eq(d.total, 1000); eq(d.online, 1000, "online no more than the members"); eq(d.zones.m1453, 10000); eq(d.levels[3], 0)
end)

test("one reporter per guild, same answer for everyone", function()
	local now = 1000
	local peers = { ["Bob-Realm"] = now, ["Alice-Realm"] = now - 500, ["Carl-Realm"] = now }
	eq(Codec.PickReporter("Dave-Realm", peers, now, 180), "Bob-Realm", "Alice is stale")
	eq(Codec.PickReporter("Aaron-Realm", peers, now, 180), "Aaron-Realm")
end)

test("summary keeps a stale guild's size, counts online and zones only while fresh", function()
	local now = os.time()
	ns.rdb.guilds = {
		["Olympus"] = { total = 1000, online = 200, zones = { m1453 = 150, m1429 = 50 }, t = now },
		["Olympus II"] = { total = 800, online = 100, zones = { m1453 = 100 }, t = now - 60 },
		["Olympus Old"] = { total = 500, online = 50, zones = { m1436 = 50 }, t = now - 3600 },
		["Olympus Gone"] = { total = 300, online = 30, zones = {}, t = now - ns.Data.KEEP - 1 },
		["Horde Pals"] = { total = 999, online = 999, zones = {}, t = now },
	}
	local s = ns.Data.Summary()
	eq(s.total, 2300, "the last report's size stays when its reporters log off")
	eq(s.online, 300, "online only from fresh reports"); eq(s.fresh, 2)
	eq(#s.guilds, 3, "older than KEEP is gone, non-Olympus never counts")
	eq(s.zoneList[1].key, "m1453"); eq(s.zoneList[1].count, 250)
	eq(#s.zoneList, 2, "a stale guild's zones are not on the map")
	eq(s.guilds[3].name, "Olympus Old", "stale sorted last")
	assert(ns.Data.DiscordText():find("2,300 soldiers"), "discord text")
end)

test("receive refuses reports about our own guild", function()
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = MY_GUILD, total = 1, online = 1, zones = {} }, "Liar-Realm"), false)
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 1, online = 1, zones = {} }, "Zed-Realm"), true)
	eq(ns.rdb.guilds["Olympus Zeus"].reporter, "Zed")
end)

test("demo data is gone and old installs forget the setting", function()
	eq(ns.Data.BuildDemo, nil); eq(ns.Data.SetDemo, nil); eq(ns.Inspect.BuildDemo, nil); eq(ns.Layers.BuildDemo, nil)
	local savedDB, savedR, savedRealm = ns.db, ns.rdb, ns.realm
	for _, old in ipairs({ { demo = true }, { demo = true, configVersion = 2 }, { demo = true, configVersion = 3 } }) do
		OlympusDB = old
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(OlympusDB.demo, nil, "demo setting cleared (configVersion " .. tostring(old.configVersion) .. ")")
		eq(OlympusDB.configVersion, 3)
	end
	ns.db, ns.rdb, ns.realm = savedDB, savedR, savedRealm
end)

test("upgrade from account-wide data: block list, old census and key, inspections", function()
	local savedDB, savedR, savedRealm = ns.db, ns.rdb, ns.realm
	local blocked = {}
	for i = 1, 40 do blocked["troll" .. i] = true end
	blocked["far-other"] = true
	OlympusDB = { configVersion = 3, blocked = blocked, realmKey = "old-secret",
		guilds = { ["Olympus Far"] = { total = 5, t = os.time() } },
		inspect = { players = { Naked = { status = "NONE" } }, guildMarks = {} } }
	local errors = 0
	local savedCapture = ns.CaptureError
	ns.CaptureError = function() errors = errors + 1 end
	for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
	ns.CaptureError = savedCapture
	eq(errors, 0, "no error while migrating")
	local short, full = 0, 0
	for k in pairs(OlympusDB.blocked) do if k:find("-", 1, true) then full = full + 1 else short = short + 1 end end
	eq(short, 0, "every short name converted"); eq(full, 41)
	eq(OlympusDB.blocked["troll7-realm"], true)
	eq(OlympusDB.realmKey, nil, "old key dropped, officers resend it")
	eq(OlympusDB.guilds, nil, "old census dropped")
	eq(OlympusDB.realms.Realm.realmKey, nil)
	eq(OlympusDB.realms.Realm.guilds["Olympus Far"], nil, "not moved into this realm")
	eq(OlympusDB.inspect, nil)
	eq(OlympusDB.realms.Realm.inspect.players.Naked.status, "NONE", "inspections kept on this realm")
	ns.db, ns.rdb, ns.realm = savedDB, savedR, savedRealm
end)

test("an old saved report does not grant rank", function()
	ns.rdb.guilds = { ["Olympus Zeus"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time() - 3600, leader = "Zed", realm = "Realm" }, "W1-Realm", "W2-Realm") }
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), nil, "report from an hour ago")
	Vouched(ns.rdb.guilds["Olympus Zeus"], "W1-Realm", "W2-Realm").t = os.time()
	for _, v in pairs(ns.rdb.guilds["Olympus Zeus"].vouch) do v.t = os.time() end
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), 0, "fresh report")
	ns.rdb.guilds = {}
end)

test("errors are captured with dedupe", function()
	ns.db.errors = {}
	ns.CaptureError("test", "boom")
	ns.CaptureError("test", "boom")
	eq(#ns.db.errors, 1); eq(ns.db.errors[1].count, 2)
	assert(ns.BuildBugReport():find("boom"))
end)

test("Throne: only the King sees it and his commands are checked; Lords answer him alone", function()
	local K = ns.King
	local savedGuild, savedPopup, savedSend, savedWhisper, savedDev = GetGuildInfo, StaticPopup_Show, ns.Comm.Send, ns.Comm.Whisper, ns.devThrone
	local savedMe = ns.me
	local sent, whispered, popups = {}, {}, {}
	local ok, err = pcall(function()
		K.Reset()
		StaticPopup_Show = function(name, arg, _, data) popups[#popups + 1] = { name = name, arg = arg, data = data } end
		ns.Comm.Send = function(dist, msg) sent[#sent + 1] = dist .. " " .. msg end
		ns.Comm.Whisper = function(to, msg) whispered[#whispered + 1] = to .. " " .. msg end
		-- Not the King: no tab, no command.
		ns.devThrone = nil
		eq(K.Visible(), false)
		-- The author's test build: the tab, but nothing leaves.
		ns.devThrone = true
		eq(K.Visible(), true); eq(K.Preview(), true)
		K.Summon()
		eq(#sent, 0, "a preview sends nothing")
		ns.devThrone = nil
		-- The King: guild master of <Olympus>, the character the addon knows as him (ns.KING_CHARACTER).
		GetGuildInfo = function() return "Olympus", "King", 0 end
		ns.me = "Asmongold Asmongler-Realm"
		eq(K.IsKing(), true); eq(K.Visible(), true)
		K.Reset() -- the Throne opens on the letter until the King has read it
		local savedRead = ns.db.throneLetterRead
		ns.db.throneLetterRead = nil
		local lines = K.Build(ns.Data.Summary())
		eq(lines[1].text, "< " .. ns.L.THRONE_ROOM, "the letter, leading to the Throne Room")
		eq(lines[2].text, "September 24, 2026", "the letter, dated")
		assert(lines[4].text:find("To His Majesty"), lines[4].text)
		assert(lines[#lines].text:find(ns.L.THRONE_ENTER, 1, true) and lines[#lines].onClick, "and at its end")
		lines[#lines].onClick()
		eq(ns.db.throneLetterRead, true, "read")
		eq(K.Build(ns.Data.Summary())[1].text, ns.L.THRONE_ROOM, "entered: the Throne Room")
		K.Reset()
		eq(K.Build(ns.Data.Summary())[1].text, "< " .. ns.L.THRONE_ROOM, "the next session opens on the letter again: the Throne's cover")
		ns.db.throneLetterRead = savedRead
		K.Summon()
		eq(#sent, 1); assert(sent[1]:find("^CHANNEL T1~S~%d+~Olympus$"), sent[1])
		local id = tonumber(sent[1]:match("T1~S~(%d+)"))
		-- An officer of another guild gets the summons, and answers the King alone.
		GetGuildInfo = function() return "Olympus II", "Officer", 1 end
		ns.me = savedMe
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 90, zones = {}, t = os.time(), leader = "Asmongold Asmongler", realm = "Realm" }, "W1-Realm", "W2-Realm"),
			["Olympus Zeus"] = Vouched({ total = 100, online = 9, zones = {}, t = os.time(), leader = "Zed", realm = "Realm" }, "W3-Realm", "W4-Realm") }
		K.HandleCommand("CHANNEL", "Faker-Realm", "T1~S~7~Olympus")
		eq(#popups, 0, "not the King: ignored")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~S~7~Olympus")
		eq(#popups, 1, "our officer rank gets the summons"); eq(popups[1].name, "OLYMPUS_KING_SUMMON")
		-- Back on the King's side: answers counted, checked against the census.
		GetGuildInfo = function() return "Olympus", "King", 0 end
		ns.me = "Asmongold Asmongler-Realm"
		K.HandleAnswer("WHISPER", "Zed-Realm", ("T2~%d~P~Olympus Zeus"):format(id))
		K.HandleAnswer("WHISPER", "Nobody-Realm", ("T2~%d~B~Olympus Zeus"):format(id))
		K.HandleAnswer("WHISPER", "Late-Realm", "T2~1~P~Olympus Zeus")
		local st = K.State()
		eq(st.summon.answers["Zed-Realm"].verified, true, "a Lord from the census")
		eq(st.summon.answers["Nobody-Realm"], nil, "not a confirmed Lord: not listed by name...")
		eq(st.summon.others["Nobody-Realm"], "B", "...only counted (the answer kept for the mark in the tree)")
		K.HandleAnswer("WHISPER", "Troll-Realm", ("T2~%d~P~Asmongold|cffff0000 smells"):format(id))
		eq(st.summon.answers["Troll-Realm"], nil, "no free text on the King's screen")
		eq(st.summon.answers["Late-Realm"], nil, "another roll call's answer")
		-- Royal Inspection reports.
		K.Reset()
		GetGuildInfo = function() return "Olympus", "King", 0 end
		local savedAfter = ns.After
		ns.After = function() end
		K.Inspect()
		ns.After = savedAfter
		assert(sent[#sent]:find("^CHANNEL T1~I~"), sent[#sent])
		local iid = tonumber(sent[#sent]:match("T1~I~(%d+)"))
		-- A confirmed Lord's report lists names; a stranger's counts for nothing (not even numbers).
		K.HandleReport("WHISPER", "Zed-Realm", ("T3~%d~Olympus Zeus~8~1~1~Naked:Olympus Zeus:N,Pirate:Olympus Zeus:O"):format(iid))
		K.HandleReport("WHISPER", "Scout2-Realm", ("T3~%d~Olympus IV~5~0~0~Innocent:Olympus IV:N"):format(iid))
		K.HandleReport("WHISPER", "Troll2-Realm", ("T3~%d~Not a guild~200~0~0~"):format(iid))
		-- On top of the Tabards tab (the King's): what the patrols reported.
		local text = {}
		for _, l in ipairs(K.InspectionLines()) do text[#text + 1] = l.text end
		text = table.concat(text, "\n")
		assert(text:find("1 patrols, 10 checks, 80%% wearing"), text)
		assert(text:find("Naked  |cff9d9d9d<Olympus Zeus>", 1, true), text)
		assert(not text:find("Innocent"), "a stranger can't put names on the King's page")
		-- The Agenda.
		eq(K.ParseAgenda("30 Raid on Crossroads"), 30)
		eq(K.ParseAgenda("Raid"), nil)
		GetGuildInfo = savedGuild
		ns.me = savedMe
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~A~9~Olympus~45~Stormwind City~Raid on Crossroads")
		local a = K.Agenda()
		eq(a.title, "Raid on Crossroads"); eq(a.zone, "Stormwind City")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~X~9~Olympus")
		eq(K.Agenda(), nil, "cancelled")
	end)
	GetGuildInfo, StaticPopup_Show, ns.Comm.Send, ns.Comm.Whisper, ns.devThrone = savedGuild, savedPopup, savedSend, savedWhisper, savedDev
	ns.me = savedMe
	K.Reset()
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("tabard rule: level 15 and up, younger players are never flagged", function()
	ns.rdb.inspect = nil
	local I = ns.Inspect
	eq(I.MIN_LEVEL, 15)
	eq(I.Record("Kiddo-Realm", "Olympus", "MAGE", 12, nil, true).status, "YOUNG", "no tabard at 12: not flagged")
	eq(I.Record("Kiddo2-Realm", "Olympus", "MAGE", 14, 23192, true).status, "YOUNG", "wrong tabard at 14: not flagged")
	eq(I.Record("Grown-Realm", "Olympus", "MAGE", 15, nil, true).status, "NONE", "at 15 the rule applies")
	eq(I.Record("Proud-Realm", "Olympus", "MAGE", 13, 5976, true).status, "GUILD", "a young player in the tabard still counts as wearing it")
	local s = I.Summary()
	eq(s.counts.NONE, 1)
	eq(#I.ShameList(), 1, "only the level 15+ player is on the Wall of Shame")
	eq(I.TooltipLine("Kiddo-Realm"), nil, "no tooltip verdict for young players")
	ns.rdb.inspect = nil
end)

test("tabard classification", function()
	local I = ns.Inspect
	eq(I.Classify(5976, true), "GUILD")
	eq(I.Classify(23192, true), "OTHER")
	eq(I.Classify(nil, true), "NONE")
	eq(I.Classify(nil, false), "UNKNOWN", "no gear visible is not an accusation")
end)

test("inspection summary, marks and discord text", function()
	ns.rdb.inspect = nil
	local I = ns.Inspect
	I.Record("Good-Realm", "Olympus", "WARRIOR", 20, 5976, true)
	I.Record("Naked-Realm", "Olympus II", "MAGE", 18, nil, true)
	I.Record("Pirate-Realm", "Olympus II", "ROGUE", 19, 23192, true)
	I.ToggleMark("Good-Realm")
	I.ToggleGuildMark("Olympus Hermes")
	local s = I.Summary()
	eq(s.total, 3); eq(s.counts.NONE, 1); eq(s.counts.OTHER, 1); eq(s.counts.GUILD, 1)
	eq(s.players[1].name, "Good", "marked first (our realm: the short name)")
	eq(s.players[2].name, "Naked", "then no tabard")
	eq(s.guilds[1].name, "Olympus Hermes", "marked guild first")
	eq(s.guilds[2].name, "Olympus II"); eq(s.guilds[2].bad, 2)
	local text = I.DiscordText()
	assert(text:find("NO TABARD") and text:find("Naked"), text)
	assert(I.TooltipLine("Naked-Realm"):find("NO TABARD"))
end)

test("roster reads ranks, officers, inactivity and top levels", function()
	ns.db.officerRank = 1
	local r = ns.Roster.Scan()
	eq(#r.ranks, 4); eq(r.ranks[1].name, "Zeus"); eq(r.ranks[1].count, 1); eq(r.ranks[2].count, 5)
	eq(#r.officers, 5, "ranks 1 are officers")
	eq(r.inactive30, 100, "members 901-1000 offline 32 days")
	eq(r.top[1].level, 30)
	assert(r.avgLevel > 1)
end)

test("R2 report round trip keeps the hierarchy", function()
	local r = ns.Roster.Scan()
	local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(r))
	eq(d.ranks[2].name, "Titan"); eq(d.ranks[4].count, r.ranks[4].count)
	eq(#d.officers, 5); eq(d.officers[1].name, r.officers[1].name)
	eq(d.inactive30, 100); eq(d.top[1].level, 30)
	eq(math.floor(d.avgLevel), math.floor(r.avgLevel))
	local chunks = ns.Codec.Chunk(ns.Codec.EncodeReport(r), "9")
	for _, c in ipairs(chunks) do assert(#c <= 255) end
end)

test("old R1 reports still decode", function()
	local d = ns.Codec.DecodeReport("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0")
	eq(d.total, 10); eq(#d.officers, 0); eq(#d.ranks, 0)
end)

test("position, layer and decree messages", function()
	local C = ns.Codec
	local p = C.DecodePosition(C.EncodePosition(1453, 0.4567, 0.1234, "WA"))
	eq(p.mapID, 1453); eq(p.class, "WA"); assert(math.abs(p.x - 0.457) < 0.001)
	eq(C.DecodePosition("P1~1~2000~3~WA"), nil, "x out of range")
	local l = C.DecodeLayer(C.EncodeLayer(1453, 4102, 0, "Olympus II"))
	eq(l.zoneUID, 4102); eq(l.rank, 0); eq(l.guild, "Olympus II")
	local m = C.EncodeDecree("ARMS", 1436, 0.5, 0.5, "Olympus", 1, ("Horde~at the farm "):rep(20))
	assert(#m <= 255, "decree too long " .. #m)
	local d = C.DecodeDecree(m)
	eq(d.kind, "ARMS"); eq(d.mapID, 1436); eq(d.rank, 1)
	eq(C.DecodeDecree("D1~NUKE~1~1~1~x~0~boom"), nil, "unknown kind")
end)

test("layer named after the highest rank present", function()
	C_Map.GetBestMapForUnit = function() return 1453 end
	ns.Data.Summary = ns.Data.Summary
	ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 1, zones = {}, t = os.time(), leader = "Kingy" }, "W1-Realm", "W2-Realm"),
		["Olympus II"] = Vouched({ total = 500, online = 1, zones = {}, t = os.time(), leader = "Lordy" }, "W1-Realm", "W2-Realm") }
	ns.Layers.Receive("Grunt-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus" })
	-- Claims rank 0 but is nobody's Lord: counted, but cannot name the layer.
	ns.Layers.Receive("Aaron-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus" })
	ns.Layers.Receive("Lordy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus II" })
	ns.Layers.Receive("Kingy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus" })
	ns.Layers.Receive("Solo-Realm", { mapID = 1453, zoneUID = 8, rank = 3, guild = "Olympus" })
	local layers = ns.Layers.ForMap(1453)
	eq(#layers, 2); eq(layers[1].count, 4)
	eq(ns.Layers.Name(layers[1]), "Kingy's layer", "rank 0 of the bigger guild wins")
	-- A sender who moves counts on the new layer only.
	ns.Layers.Receive("Grunt-Realm", { mapID = 1453, zoneUID = 8, rank = 4, guild = "Olympus" })
	eq(ns.Layers.ForMap(1453)[1].count, 3, "moved sender left the old layer")
	eq(#ns.Layers.ForMap(1437), 0, "no made-up layers in other zones")
	eq(ns.Layers.Name(layers[2]), "Solo's layer")
end)

test("names carry the realm, so namesakes on other realms stay apart", function()
	eq(ns.FullName("Zed"), "Zed-Realm")
	eq(ns.FullName("Zed-Other"), "Zed-Other")
	eq(ns.DisplayName("Zed-Realm"), "Zed", "own realm shows short")
	eq(ns.DisplayName("Zed-Other"), "Zed-Other", "other realm keeps the suffix")
	ns.rdb.guilds = { ["Olympus Zeus"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time(), leader = "Zed", realm = "Realm",
		officers = { { name = "Capt", online = true, days = 0 } } }, "W1-Realm", "W2-Realm") }
	eq(ns.Data.KnownRank("Zed", "Olympus Zeus"), 0, "short name from our realm")
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), 0)
	eq(ns.Data.KnownRank("Zed-Other", "Olympus Zeus"), nil, "namesake on another realm is not the Lord")
	eq(ns.Data.KnownRank("Capt-Other", "Olympus Zeus"), nil, "namesake officer rejected")
	eq(ns.Data.KnownRank("Capt-Realm", "Olympus Zeus"), 1)
	-- A guild reported from another realm: its short names belong to that realm.
	ns.rdb.guilds["Olympus Far"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time(), leader = "Kay", realm = "Other" }, "W1-Other", "W2-Other")
	eq(ns.Data.KnownRank("Kay-Other", "Olympus Far"), 0)
	eq(ns.Data.KnownRank("Kay-Realm", "Olympus Far"), nil)
	ns.rdb.guilds = {}
end)

test("reporter election compares full names", function()
	local now = os.time()
	eq(ns.Codec.PickReporter("Tester-Realm", { ["Abe-Realm"] = now }, now, 180), "Abe-Realm")
	eq(ns.Codec.PickReporter("Tester-Realm", { ["Abe-Realm"] = now - 999 }, now, 180), "Tester-Realm", "stale peer ignored")
	eq(ns.Roster.RankOf("Member1"), 0, "our roster answers short names")
	eq(ns.Roster.RankOf("Member1-Realm"), 0)
	eq(ns.Roster.RankOf("Member1-Other"), nil, "namesake from another realm is not in our guild")
end)

test("crown permissions", function()
	eq(ns.IsCrownRank("Olympus II", 0), true, "any guild master")
	eq(ns.IsCrownRank("Olympus", 1), true, "officers of the main guild")
	eq(ns.IsCrownRank("Olympus II", 1), false, "officers of other guilds")
	eq(ns.IsCrownRank("Olympus", 3), false)
end)

test("wall of shame round trip", function()
	local list = {}
	for i = 1, 50 do list[i] = { name = "Naked" .. i, guild = "Olympus II" } end
	local payload = ns.Codec.EncodeShame("Olympus", 0, list)
	local d = ns.Codec.DecodeShame(payload)
	eq(d.guild, "Olympus"); eq(d.rank, 0); eq(#d.list, 40, "capped"); eq(d.list[3].name, "Naked3")
	for _, c in ipairs(ns.Codec.Chunk(payload, "4")) do assert(#c <= 255) end
end)

test("person details travel in the report", function()
	local r = ns.Roster.Scan()
	local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(r))
	eq(d.leaderClass, "PA"); assert(d.leaderLevel and d.leaderLevel > 0)
	eq(d.officers[1].class ~= nil, true, "officer class")
	eq(d.top[1].class ~= nil, true, "top class")
	local old = ns.Codec.DecodeReport("R2~Olympus~10~2~Boss~1~2~~~0,0,0,0,0,0,0~~Cap:1:0~0~0~0~0~Top:20")
	eq(old.officers[1].name, "Cap"); eq(old.top[1].level, 20); eq(old.leaderClass, nil)
end)

test("only Olympus guilds count, the filter cannot be changed", function()
	eq(ns.IsFederation("House of Guedes"), false)
	eq(ns.IsMember(), true, "tests run as a member of Olympus II")
	local saved = GetGuildInfo
	GetGuildInfo = function() return "House of Guedes" end
	eq(ns.IsMember(), false)
	GetGuildInfo = saved
end)

test("ranks are verified, not taken from the message", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {
		["Olympus"] = Vouched({ guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() }, "W1-Realm", "W2-Realm"),
		["Olympus Bad"] = { guild = "Olympus Bad", leader = "X", conflict = true, total = 1, online = 1, zones = {}, t = os.time() },
	}
	eq(ns.Data.KnownRank("Asmongold-Realm", "Olympus"), 0)
	eq(ns.Data.KnownRank("Capt-Realm", "Olympus"), 1)
	eq(ns.Data.KnownRank("Random-Realm", "Olympus"), nil, "claims mean nothing")
	eq(ns.Data.KnownRank("X-Realm", "Olympus Bad"), nil, "conflicting guild is not trusted")
	eq(ns.Data.KnownRank("Member1-Realm", "Olympus II"), 0, "own guild from our roster")
end)

test("a sender can only report one guild", function()
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 5, online = 1, zones = {} }, "Liar2-Realm"), true)
	eq(ns.Data.Receive({ guild = "Olympus Fake", total = 900, online = 1, zones = {} }, "Liar2-Realm"), false)
end)

test("sealed channel name comes from the key", function()
	local a, b = ns.Comm.Hash36("secret-one"), ns.Comm.Hash36("secret-one")
	eq(a, b); eq(#a, 8)
	assert(ns.Comm.Hash36("secret-two") ~= a)
	ns.rdb.realmKey = "secret-one"
	local name, password = ns.Comm.ChannelSpec()
	eq(name, "Oly" .. a); eq(password, "secret-one")
	ns.rdb.realmKey = nil
	eq((ns.Comm.ChannelSpec()), "OlympusNet")
end)

test("join flow groups online Olympus players and never asks twice", function()
	local R = ns.Recruit
	R.found = {
		{ name = "A", guild = "Olympus II" }, { name = "B", guild = "Olympus II" }, { name = "C", guild = "Olympus" },
	}
	local g = R.Guilds()
	eq(g[1].name, "Olympus II"); eq(#g[1].members, 2)
	eq(R.NextContact("Olympus II").name, "A")
	R.asked.A = 1
	eq(R.NextContact("Olympus II").name, "B")
	R.asked.B = 1
	eq(R.NextContact("Olympus II"), nil)
	function UnitLevel() return 12 end
	function UnitClass() return "Mage", "MAGE" end
	assert(R.Message({ guild = "Olympus II" }):find("Olympus II"))
	assert(#ns.Views.RecruitLines() > 3)
	eq((R.Roast()), "<Olympus II>? Disband immediately.")
	local saved = GetGuildInfo
	GetGuildInfo = function() return nil end
	eq((R.Roast()), "No guild? What are you doing?")
	GetGuildInfo = saved
end)

test("worst case report still fits the message limits", function()
	local C = ns.Codec
	local r = { guild = "Olympus Longest NameHer", total = 1000, online = 1000, leader = "Averylongname", leaderOnline = true,
		users = 999, zones = {}, classes = {}, levels = { 1, 2, 3, 4, 5, 6, 7 }, ranks = {}, officers = {}, top = {},
		leaderClass = "WARRIOR", leaderLevel = 60, leaderZone = "tThe Temple of Atal'Hakkar",
		from = ("F"):rep(40), home = ("H"):rep(40) }
	for i = 1, 120 do r.zones["tSome Long Zone Name " .. i] = 999 end
	for _, c in ipairs({ "WA", "PA", "HU", "RO", "PR", "SH", "MA", "WL", "DR", "DK" }) do r.classes[c] = 999 end
	for i = 1, 10 do r.ranks[i] = { name = "Rank Name Number " .. i, count = 999 } end
	for i = 1, 30 do r.officers[i] = { name = "Officername" .. i, online = true, days = 99, class = "WARLOCK", level = 60, zone = "tSome Long Zone Name " .. i } end
	for i = 1, 5 do r.top[i] = { name = "Topplayer" .. i, level = 60, class = "PRIEST" } end
	local payload = C.EncodeReport(r)
	local chunks = C.Chunk(payload, "999")
	assert(#chunks <= C.MAX_CHUNKS, "too many chunks: " .. #chunks)
	for _, c in ipairs(chunks) do assert(#c <= 255) end
	local d = C.DecodeReport(payload)
	eq(#d.officers, 30); eq(#d.ranks, 10)
	eq(d.from, r.from, "the longest realm fits"); eq(d.home, r.home)
end)

local function SampleGuilds()
	local now = os.time()
	return {
		-- Two other senders name its leader, so the census knows its King (Data.KnownRank).
		["Olympus"] = Vouched({ total = 990, online = 210, zones = { m1453 = 120, m1429 = 40 }, t = now, leader = "Asmongold",
			leaderOnline = true, leaderLevel = 24, leaderClass = "WA", ranks = { { name = "King", count = 1 }, { name = "Knight", count = 989 } },
			officers = { { name = "Capt", online = true, days = 0, class = "PA", level = 22 } },
			top = { { name = "Racer", level = 25, class = "MA" } }, inactive7 = 10, inactive30 = 2, avgLevel = 14 }, "W1-Realm", "W2-Realm"),
		["Olympus II"] = { total = 500, online = 80, zones = { m1453 = 30 }, t = now, leader = "Lordy", leaderOnline = false, leaderDays = 4,
			officers = {}, top = { { name = "Other", level = 20, class = "RO" } } },
	}
end

test("every tab builds", function()
	ns.rdb.guilds = SampleGuilds()
	-- Guilds seen with /who too, one of them also reported.
	ns.rdb.seen = { ["OLYMPUS VII"] = { online = 12, capped = true, t = os.time() }, ["Olympus"] = { online = 3, t = os.time() } }
	ns.UI = { StatusLine = function() return "status" end }
	for _, tab in ipairs({ "census", "realm", "decrees", "heraldry" }) do
		local lines, title = ns.Views.Build(tab)
		assert(#lines > 0 and title, tab)
	end
	ns.rdb.guilds, ns.rdb.seen = {}, nil
end)

test("the Realm lists every member online: our roster for our guild, /who for the others", function()
	local savedGuild, savedOnline, savedSweep = GetGuildInfo, ns.Roster.online, ns.Who.sweep
	GetGuildInfo = function() return "Olympus II", "Member", 3 end
	ns.rdb.guilds = SampleGuilds()
	ns.Roster.online = {
		{ name = "Lordy", level = 30, class = "WA", rank = "Lord", rankIndex = 0 },
		{ name = "Mate", level = 22, class = "MA", rank = "Knight", rankIndex = 3 },
		{ name = "Pal", level = 12, class = "PR", rank = "Squire", rankIndex = 4 },
	}
	ns.Who.sweep = { list = {
		{ name = "Scout-Realm", guild = "Olympus", level = 18, class = "ROGUE", zone = "Elwynn Forest" },
		{ name = "Capt", guild = "Olympus", level = 22, class = "PALADIN" },
		{ name = "Other", guild = "Olympus II", level = 9, class = "MAGE" },
	} }
	local ok, err = pcall(function()
		local own = ns.Views.MembersOf("Olympus II", ns.rdb.guilds["Olympus II"])
		eq(#own, 2, "our roster, without the Lord")
		eq(own[1].name, "Mate"); eq(own[1].rank, "Knight")
		local other, fromWho = ns.Views.MembersOf("Olympus", ns.rdb.guilds["Olympus"])
		eq(fromWho, true)
		eq(#other, 1, "seen with /who, without its Captain")
		eq(other[1].name, "Scout"); eq(other[1].class, "RO")
		ns.Views.ExpandAll(true)
		local text = {}
		for _, l in ipairs(ns.Views.RealmLines()) do text[#text + 1] = l.text or "" end
		text = table.concat(text, "\n")
		assert(text:find(ns.L.MEMBERS_ONLINE:format(2), 1, true), text)
		assert(text:find(ns.L.MEMBERS_SEEN:format(1), 1, true), text)
		assert(text:find("Scout", 1, true) and text:find("Mate", 1, true), text)
		-- A long list: the first MAX_MEMBERS, the rest on a click, and back.
		for k = 1, 40 do ns.Roster.online[#ns.Roster.online + 1] = { name = "Member" .. k, level = 10, class = "WA", rank = "Recruit", rankIndex = 5 } end
		local function Find(pattern)
			for _, l in ipairs(ns.Views.RealmLines()) do
				if l.text and l.text:find(pattern, 1, true) then return l end
			end
		end
		local UIsaved = ns.UI
		ns.UI = setmetatable({ Refresh = function() end }, { __index = UIsaved })
		local more = Find(ns.L.MEMBERS_MORE:format(42 - ns.Views.MAX_MEMBERS))
		assert(more and more.onClick, "the rest, on a click")
		more.onClick()
		assert(Find("Member40"), "everyone shown")
		local fewer = Find(ns.L.MEMBERS_FEWER)
		assert(fewer and fewer.onClick)
		fewer.onClick()
		assert(not Find("Member40"), "back to the first ones")
		ns.UI = UIsaved
		ns.Views.ExpandAll(false)
	end)
	GetGuildInfo, ns.Roster.online, ns.Who.sweep = savedGuild, savedOnline, savedSweep
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("layer sample is stable and about 1 in 8", function()
	local saved, hits = ns.me, 0
	for i = 1, 800 do
		ns.me = "Player" .. i .. "-Realm"
		local a, b = ns.Layers.InSample(), ns.Layers.InSample()
		eq(a, b, "same answer every time")
		if a then hits = hits + 1 end
	end
	ns.me = saved
	assert(hits > 50 and hits < 150, "sample size " .. hits)
end)

test("realm view lists king, lords, captains and level race", function()
	ns.rdb.guilds = SampleGuilds()
	local lines = ns.Views.RealmLines()
	assert(lines[1].text:find("Asmond Layer", 1, true), "the King is online: his layer line comes first")
	assert(lines[2].text:find("King") and lines[2].text:find("Asmongold"), lines[2].text)
	local sawRace = false
	for _, l in ipairs(lines) do if l.text == "Level race" then sawRace = true end end
	assert(sawRace)
	ns.rdb.guilds = {}
end)

test("captains in the report are rank 1 whatever /oly officer says", function()
	local saved = ns.db.officerRank
	ns.db.officerRank = 9
	local r = ns.Roster.Scan()
	eq(#r.officers, 5, "only the rank 1 members")
	ns.db.officerRank = saved
end)

test("a city's count also shows on the map of the zone around it (Stormwind on Elwynn)", function()
	local savedLibStub, savedInfo, savedChildren = LibStub, C_Map.GetMapInfo, C_Map.GetMapChildrenInfo
	local ok, err = pcall(function()
		-- World rectangles (left, top, width, height): Stormwind sits inside Elwynn Forest.
		local RECT = { [1429] = { 0, 0, 100, 100 }, [1453] = { 40, 40, 20, 20 }, [1436] = { 100, 0, 100, 100 } }
		local HBD = {
			GetWorldCoordinatesFromZone = function(_, x, y, id) local r = RECT[id]; return r[1] + r[3] * x, r[2] + r[4] * y, 0 end,
			GetZoneCoordinatesFromWorld = function(_, wx, wy, id)
				local r = RECT[id]; if not r then return nil end
				local x, y = (wx - r[1]) / r[3], (wy - r[2]) / r[4]
				if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
				return x, y
			end,
			GetZoneSize = function(_, id) local r = RECT[id]; if not r then return 0, 0 end return r[3], r[4] end,
		}
		LibStub = function(name) if name == "HereBeDragons-2.0" then return HBD end end
		C_Map.GetMapInfo = function(id) return { mapID = id, parentMapID = 1415 } end
		C_Map.GetMapChildrenInfo = function() return { { mapID = 1429 }, { mapID = 1453 }, { mapID = 1436 } } end
		local c = ns.Map.ContainerOf(1453)
		assert(c, "Stormwind has a zone around it")
		eq(c.zone, 1429, "Elwynn Forest")
		eq(c.x, 0.5); eq(c.y, 0.5)
		eq(ns.Map.ContainerOf(1429), false, "Elwynn is inside no bigger zone")
		eq(ns.Map.ContainerOf(1436), false, "nor is Westfall")
	end)
	LibStub, C_Map.GetMapInfo, C_Map.GetMapChildrenInfo = savedLibStub, savedInfo, savedChildren
	if not ok then error(err, 0) end
end)

test("map refresh runs end to end with a map library (continent totals included)", function()
	-- A stub where every method returns another stub, so frame building code can run.
	local function deep()
		return setmetatable({}, { __index = function() return function() return deep() end end })
	end
	local calls = { world = 0 }
	local fakePins = setmetatable({
		AddWorldMapIconMap = function() calls.world = calls.world + 1 end,
		RemoveAllWorldMapIcons = function() end,
		AddMinimapIconMap = function() end,
		RemoveWorldMapIcon = function() end,
		RemoveMinimapIcon = function() end,
	}, { __index = function() return function() end end })
	local savedLibStub, savedCreateFrame, savedWMF = LibStub, CreateFrame, WorldMapFrame
	LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return fakePins end end
	CreateFrame = function() return deep() end
	WorldMapFrame = deep()
	C_Map.GetMapRectOnMap = function() return 0.1, 0.3, 0.2, 0.8 end
	MAPS[947] = { "Azeroth", 1 }; MAPS[1415] = { "Eastern Kingdoms", 2, 947 }
	local oldInfo = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(id)
		local m = MAPS[id]
		if not m then return nil end
		local parent = ({ [1429] = 1415, [1453] = 1415, [1436] = 1415, [1415] = 947 })[id]
		return { mapID = id, name = m[1], mapType = m[2], parentMapID = parent }
	end
	local mapChunk = assert(loadfile(ADDON_DIR .. "Map.lua"))
	local captured
	local savedCapture = ns.CaptureError
	ns.CaptureError = function(where, err) captured = where .. ": " .. tostring(err) end
	mapChunk("Olympus", ns)
	ns.db.showMap = true
	ns.rdb.guilds = { ["Olympus"] = { total = 100, online = 10, zones = { m1453 = 7, m1429 = 3 }, t = os.time() } }
	ns.Map.Refresh()
	ns.CaptureError = savedCapture
	LibStub, CreateFrame, WorldMapFrame, C_Map.GetMapInfo = savedLibStub, savedCreateFrame, savedWMF, oldInfo
	eq(captured, nil, "map refresh raised an error")
	assert(calls.world >= 2, "zone pins were not added")
	local totals = ns.Map.ContinentTotals(ns.Data.Summary())
	eq(totals[1415], 10, "continent total")
end)

---------------------------------------------------------------------------
-- Guild window button (GuildFrame.lua): old Guild tab, new Communities window, or both
---------------------------------------------------------------------------

-- A frame with just what GuildFrame.lua uses. Scripts hooked on it can be run.
local function FakeFrame(name, parent, w, h)
	local f = { name = name, parent = parent, w = w, h = h, shown = false, hooks = {} }
	function f:GetName() return self.name end
	function f:GetParent() return self.parent end
	function f:GetWidth() return self.w end
	function f:GetHeight() return self.h end
	function f:GetFrameLevel() return self.level or 5 end
	function f:GetEffectiveScale() return 1 end
	function f:GetAlpha() return self.alpha or 1 end
	function f:GetRect() if self.rect then return unpack(self.rect) end end -- where a test put it
	function f:IsShown() return self.shown end
	function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
	function f:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
	function f:Run(kind) for _, fn in ipairs(self.hooks[kind] or {}) do fn(self) end end
	function f:Show() self.shown = true; self:Run("OnShow") end
	function f:Hide() self.shown = false; self:Run("OnHide") end
	return f
end

-- Loads GuildFrame.lua with fresh state into a namespace of its own. Its events and LOGIN
-- are fired by hand; the Olympus window is a stand-in that remembers where it is docked,
-- or with realUI the real UI.lua (which needs the widget toolkit further below).
local function LoadGuildFrame(realUI)
	local world = { events = {}, login = {}, buttons = {}, dock = { shown = false } }
	local dock = world.dock
	local gns = setmetatable({}, { __index = ns })
	world.ns = gns
	gns.RegisterEvent = function(event, fn) world.events[event] = world.events[event] or {}; table.insert(world.events[event], fn) end
	gns.On = function() end -- UI.lua's own callbacks (minimap button at LOGIN, refreshes) stay out
	if realUI then assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", gns) end
	gns.On = function(name, fn) if name == "LOGIN" then table.insert(world.login, fn) end end
	gns.MakeRoundButton = function(name, parent, size)
		local b = setmetatable({ name = name, parent = parent, size = size, scripts = {} }, { __index = function() return function() end end })
		function b:SetScript(kind, fn) self.scripts[kind] = fn end
		function b:SetPoint(...) self.point = { ... } end
		function b:SetFrameLevel(level) self.level = level end
		function b:Click() self.scripts.OnClick(self) end
		world.buttons[#world.buttons + 1] = b
		return b
	end
	gns.UI = realUI and gns.UI or {
		IsShown = function() return dock.shown end,
		DockedTo = function() return dock.host end,
		OpenDocked = function(host, tab, heightOnly, style)
			dock.shown, dock.host, dock.tab, dock.heightOnly, dock.style = true, host, tab, heightOnly, style
		end,
		CloseIfDocked = function(host) if dock.shown and (host == nil or dock.host == host) then dock.shown = false end end,
		FollowHost = function(host) dock.followed = host end,
	}
	assert(loadfile(ADDON_DIR .. "GuildFrame.lua"))("Olympus", gns)
	world.hook = gns.GuildFrameHook
	function world.Fire(event, ...) for _, fn in ipairs(world.events[event] or {}) do fn(...) end end
	function world.Login() for _, fn in ipairs(world.login) do fn() end end
	return world
end

-- Runs fn with fake Blizzard windows as globals (cleared afterwards), failing on any error
-- the addon caught along the way.
local GUILD_GLOBALS = { "UIParent", "FriendsFrame", "GuildFrame", "CommunitiesFrame", "ClassicUIForeverGuildPanel" }
local function WithGuildWindows(fn)
	local captured
	local savedCapture = ns.CaptureError
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	UIParent = FakeFrame("UIParent")
	UIParent.shown = true
	local ok, err = pcall(fn)
	ns.CaptureError = savedCapture
	for _, name in ipairs(GUILD_GLOBALS) do _G[name] = nil end
	PanelTemplates_AnchorTabs = nil -- the Mainline tab code, set by the Forever tests
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

test("guild button: old UI only (Guild tab), same spot and docking as before", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "old")
		local b = w.buttons[1]
		eq(b.name, "OlympusGuildFrameButton"); eq(b.parent, GuildFrame); eq(b.size, 26)
		eq(b.point[1], "TOPLEFT"); eq(b.point[2], FriendsFrame); eq(b.point[3], "TOPLEFT"); eq(b.point[4], 62); eq(b.point[5], -26)
		FriendsFrame:Show(); GuildFrame:Show()
		b:Click()
		eq(w.dock.host, FriendsFrame, "docks to the Social window"); eq(w.dock.tab, "census"); eq(w.dock.heightOnly, false)
		b:Click()
		eq(w.dock.shown, false, "a second click closes it")
		b:Click(); FriendsFrame:Hide()
		eq(w.dock.shown, false, "closing the Social window closes it")
		b:Click(); GuildFrame:Hide()
		eq(w.dock.shown, false, "leaving the Guild tab closes it")
		-- Nothing else to hook, and scanning again (the Social window opening) hooks nothing twice.
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		FriendsFrame:Show()
		eq(#w.hook.Hosts(), 1); eq(#w.buttons, 1); eq(#GuildFrame.hooks.OnHide, 1, "OnHide hooks")
	end)
end)

test("guild button: new UI loaded at login (Forever: Communities window only)", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
		PanelTemplates_AnchorTabs = function() end -- Forever's (Mainline) tab code
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "communities")
		local b = w.buttons[1]
		eq(b.parent, CommunitiesFrame); eq(b.point[1], "RIGHT"); eq(b.point[2], CommunitiesFrame.MaximizeMinimizeFrame, "title bar")
		CommunitiesFrame:Show()
		eq(w.hook.ActiveHost(), hosts[1], "in use")
		b:Click()
		eq(w.dock.host, CommunitiesFrame, "docks to the Communities window"); eq(w.dock.heightOnly, true)
		eq(w.dock.style, "hd", "in the new window's look")
		-- No Guild tab in the Social window, so nothing of ours listens to it closing (the
		-- other way round is covered in the "both windows" and real-window tests).
		eq(FriendsFrame.hooks.OnHide, nil, "no Social window hook without a Guild tab")
		CommunitiesFrame:Run("OnSizeChanged")
		eq(w.dock.followed, CommunitiesFrame, "follows minimize and maximize")
		CommunitiesFrame:Hide()
		eq(w.dock.shown, false, "closing the Communities window closes it")
		local status = w.hook.StatusLine()
		assert(status:find("communities=CommunitiesFrame", 1, true), status)
	end)
end)

test("guild button: new UI loaded later (ADDON_LOADED), next to the unused old tab", function()
	WithGuildWindows(function()
		-- Classic Era with the classic guild UI off: the old tab exists but never shows.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		local w = LoadGuildFrame()
		w.Login()
		eq(#w.hook.Hosts(), 1, "only the old tab at login")
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 322, 406)
		CommunitiesFrame.CloseButton = FakeFrame(nil, CommunitiesFrame, 24, 24)
		w.Fire("ADDON_LOADED", "SomeOtherAddon")
		eq(#w.hook.Hosts(), 1, "other addons change nothing")
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[2].kind, "communities")
		local b = w.buttons[2]
		eq(b.parent, CommunitiesFrame); eq(b.point[2], CommunitiesFrame.CloseButton, "no minimize button: next to close")
		eq(w.hook.ActiveHost(), nil, "nothing opened yet")
		CommunitiesFrame:Show()
		eq(w.hook.ActiveHost(), hosts[2], "in use")
		b:Click()
		eq(w.dock.host, CommunitiesFrame)
		CommunitiesFrame:Hide()
		eq(w.hook.ActiveHost(), hosts[2], "last opened")
	end)
end)

test("guild button: both windows present, switching between them without /reload", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		local old, new = w.buttons[1], w.buttons[2]
		eq(old.parent, GuildFrame); eq(new.parent, CommunitiesFrame)
		assert(old.name ~= new.name, "one button name per window")
		-- New UI in use.
		CommunitiesFrame:Show(); new:Click()
		eq(w.dock.host, CommunitiesFrame)
		-- The player switches to the old UI: the Communities window closes, the Guild tab opens.
		CommunitiesFrame:Hide()
		eq(w.dock.shown, false, "closed with the Communities window")
		FriendsFrame:Show(); GuildFrame:Show()
		eq(w.hook.ActiveHost().kind, "old")
		old:Click()
		eq(w.dock.host, FriendsFrame); eq(w.dock.heightOnly, false)
		-- Clicked in the other window while docked: it moves there instead of closing.
		CommunitiesFrame:Show(); new:Click()
		eq(w.dock.shown, true); eq(w.dock.host, CommunitiesFrame)
		eq(w.hook.ActiveHost().kind, "old", "both on screen: the Social window's first")
		eq(#FriendsFrame.hooks.OnHide, 1, "the Social window is watched (for the Guild tab)")
		FriendsFrame:Hide()
		eq(w.dock.shown, true, "still docked to the Communities window")
	end)
end)

test("guild button: standalone GuildFrame (Blizzard_GuildUI) is not taken for the old tab", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		local oldTab = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		GuildFrame = oldTab
		local w = LoadGuildFrame()
		w.Login()
		-- Blizzard_GuildUI loads and takes over the name GuildFrame.
		GuildFrame = FakeFrame("GuildFrame", UIParent, 646, 468)
		GuildFrame.CloseButton = FakeFrame(nil, GuildFrame, 24, 24)
		w.Fire("ADDON_LOADED", "Blizzard_GuildUI")
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[1].frame, oldTab); eq(hosts[1].kind, "old")
		eq(hosts[2].frame, GuildFrame); eq(hosts[2].kind, "guildui"); eq(hosts[2].dock, GuildFrame)
		GuildFrame:Show(); w.buttons[2]:Click()
		eq(w.dock.host, GuildFrame); eq(w.dock.heightOnly, true)
	end)
end)

test("guild button: ClassicUI Forever's Guild tab is found when the Social window opens", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		local w = LoadGuildFrame()
		w.Login()
		eq(#w.hook.Hosts(), 1, "only the Communities window at login")
		-- Built after login, inside the Social window.
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[2].kind, "classicui")
		local b = w.buttons[2]
		eq(b.parent, ClassicUIForeverGuildPanel); eq(b.point[2], FriendsFrame); eq(b.point[4], 62); eq(b.point[5], -26)
		b:Click()
		eq(w.dock.host, FriendsFrame)
		ClassicUIForeverGuildPanel:Hide()
		eq(w.dock.shown, false, "closing the Guild tab closes it")
	end)
end)

test("guild button: ClassicUI Forever's panel outside the Social window is a window of its own", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", UIParent, 338, 440)
		ClassicUIForeverGuildPanel.CloseButton = FakeFrame(nil, ClassicUIForeverGuildPanel, 24, 24)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "classicuiwindow"); eq(hosts[1].social, nil); eq(hosts[1].dock, ClassicUIForeverGuildPanel)
		local b = w.buttons[1]
		eq(b.name, "OlympusClassicGuildWindowButton"); eq(b.size, 22)
		eq(b.point[1], "RIGHT"); eq(b.point[2], ClassicUIForeverGuildPanel.CloseButton, "title bar, like the new windows")
		ClassicUIForeverGuildPanel:Show(); b:Click()
		eq(w.dock.host, ClassicUIForeverGuildPanel, "docks to itself"); eq(w.dock.heightOnly, true)
		eq(FriendsFrame.hooks.OnHide, nil, "the Social window is not watched for it")
		ClassicUIForeverGuildPanel:Run("OnSizeChanged")
		eq(w.dock.followed, ClassicUIForeverGuildPanel, "follows its size")
		ClassicUIForeverGuildPanel:Hide()
		eq(w.dock.shown, false, "closing it closes ours")
	end)
end)

test("docked size: the old Guild tab is copied, the new windows lend only their height", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local DockSize = uns.UI.DockSize
	local function size(...) local w, h = DockSize(...); return w .. "x" .. h end
	eq(size(338, 424, false, 338, 424), "338x424", "old Guild tab")
	eq(size(385, 424, false, 385, 424), "385x424", "Forever's Social window")
	eq(size(814, 426, true, 385, 424), "385x426", "Communities window, maximized")
	eq(size(322, 406, true, 338, 424), "338x406", "Communities window, minimized")
	eq(size(0, 0, false, 338, 424), "338x424", "host not laid out yet")
	eq(size(nil, nil, true), "338x424", "nothing known")
end)

test("HD look: Forever's new guild window gets it, the old Guild tabs never do", function()
	WithGuildWindows(function()
		-- Forever: no Guild tab in the Social window, and the Mainline tab code.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), true)
		eq(w.hook.IsHD(), true, "nothing opened yet: the client decides")
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		eq(w.dock.host, CommunitiesFrame); eq(w.dock.style, "hd")
		local status = w.hook.StatusLine()
		assert(status:find("hd client=true", 1, true), status)
		-- ClassicUI Forever's old Guild tab: the old look there, and while it is on screen.
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		eq(w.hook.Hosts()[2].kind, "classicui")
		w.buttons[2]:Click()
		eq(w.dock.host, FriendsFrame); eq(w.dock.style, "old")
		eq(w.hook.IsHD(), false, "the old tab in use")
		-- Only the Communities window left, then not even that: the last one shown decides.
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		eq(w.hook.IsHD(), true, "the new window on screen")
		CommunitiesFrame:Hide(); CommunitiesFrame:Show(); CommunitiesFrame:Hide()
		eq(w.hook.IsHD(), true, "the new window was the last one shown")
		-- ClassicUI Forever's roster opens the Communities window unseen (alpha 0, off the
		-- screen) for its notes and closes it with the Social window: not a window in use.
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		CommunitiesFrame.alpha = 0
		CommunitiesFrame:Show()
		eq(w.hook.IsHD(), false, "the old tab on screen")
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Hide(); CommunitiesFrame.alpha = 1
		eq(w.hook.IsHD(), false, "the old tab was the last one the player saw")
	end)
	WithGuildWindows(function()
		-- ClassicUI Forever's tab built after the scan at login (a login in combat): the old
		-- look, before the Social window is ever opened.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHD(), true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		eq(#w.hook.Hosts(), 1, "not hooked yet"); eq(w.hook.IsHD(), false)
	end)
	WithGuildWindows(function()
		-- ClassicUI Forever's tab already there, nothing opened yet: the old look.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), true); eq(w.hook.IsHD(), false)
	end)
	WithGuildWindows(function()
		-- Classic Era: its Guild tab is always there (hidden when the new window is used).
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 322, 406)
		PanelTemplates_AnchorTabs = function() end -- even with the Mainline tab code
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), false)
		CommunitiesFrame:Show(); w.buttons[2]:Click()
		eq(w.dock.host, CommunitiesFrame); eq(w.dock.style, "old")
		assert(w.hook.StatusLine():find("hd client=false", 1, true))
	end)
end)

test("guild button: over Forever's metal title bar, where it always was on Classic", function()
	for _, forever in ipairs({ true, false }) do
		WithGuildWindows(function()
			FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
			if not forever then GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424) end
			CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
			CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
			CommunitiesFrame.MaximizeMinimizeFrame.level = 515 -- frameLevel 510, over the NineSlice's 500
			PanelTemplates_AnchorTabs = forever and function() end or nil
			local w = LoadGuildFrame()
			w.Login()
			local b = w.buttons[#w.buttons]
			eq(b.parent, CommunitiesFrame)
			eq(b.level, forever and 515 or 15, forever and "Forever" or "Classic")
		end)
	end
end)

---------------------------------------------------------------------------
-- The Olympus window itself (UI.lua), on a small widget toolkit: frames keep their size,
-- anchors and shown state, scripts can be fired, rects are worked out from the anchors
-- and text is measured at a fixed width per letter.
---------------------------------------------------------------------------

local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
local CHAR_W = { GameFontNormalLarge = 9, GameFontNormal = 7, GameFontHighlight = 7, GameFontWhiteTiny = 5 } -- small fonts: 6
-- The client's font objects UI.lua fits text with (FitText skips the ones a client lacks).
local FONT_GLOBALS = { "GameFontNormalLarge", "GameFontNormal", "GameFontHighlightSmall", "GameFontWhiteTiny" }

local Widget = {}
local NOOP_VERBS = { "^Set", "^Enable", "^Disable", "^Register", "^Unregister", "^Lock", "^Unlock", "^Raise", "^Lower", "^Highlight", "^Play", "^ClearFocus$" }
local widgetNames = {}
local widgetMeta = { __index = function(_, key)
	local method = Widget[key]
	if method then return method end
	-- Setters and the like a test does not look at do nothing; anything else is nil, as a
	-- missing child key (CloseButton, TitleText, Left...) would be.
	if type(key) == "string" then
		for _, verb in ipairs(NOOP_VERBS) do if key:find(verb) then return function() end end end
	end
end }

local function NewWidget(kind, name, parent)
	local w = setmetatable({ kind = kind, name = name, parent = parent, points = {}, shown = true, scripts = {}, hooks = {} }, widgetMeta)
	if name then _G[name] = w; widgetNames[#widgetNames + 1] = name end
	return w
end

function Widget:GetName() return self.name end
function Widget:GetParent() return self.parent end
function Widget:GetObjectType() return self.kind end
function Widget:Fire(kind, ...)
	if self.scripts[kind] then self.scripts[kind](self, ...) end
	for _, fn in ipairs(self.hooks[kind] or {}) do fn(self, ...) end
end
function Widget:SetScript(kind, fn) self.scripts[kind] = fn end
function Widget:GetScript(kind) return self.scripts[kind] end
function Widget:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
function Widget:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Widget:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:GetEffectiveScale() return self.scale or (self.parent and self.parent:GetEffectiveScale()) or 1 end
function Widget:GetFrameLevel() return self.level or 1 end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:SetChecked(checked) self.checked = checked and true or false end
function Widget:GetChecked() return self.checked or false end
function Widget:LockHighlight() self.locked = true end
function Widget:UnlockHighlight() self.locked = false end
function Widget:SetHighlightTexture(texture) self.highlightTexture = texture end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:SetFrameStrata(strata) self.strata = strata end
function Widget:GetFrameStrata() return self.strata end
function Widget:SetTexCoord(...) self.texCoord = table.concat({ ... }, " ") end
function Widget:GetDrawLayer() return self.layer end
function Widget:GetRegions() return unpack(self.textures or {}) end
function Widget:SetClampRectInsets(...) self.clampInsets = { ... } end

function Widget:SetSize(w, h)
	local changed = self.w ~= w or self.h ~= h
	self.w, self.h = w, h
	if changed then self:Fire("OnSizeChanged", w, h) end
end
function Widget:SetWidth(w) self:SetSize(w, self.h) end
function Widget:SetHeight(h) self:SetSize(self.w, h) end
function Widget:GetWidth()
	if self.kind == "FontString" and (self.w or 0) == 0 then return self:GetStringWidth() end
	if self.w then return self.w end
	local _, _, w = self:GetRect()
	return w or 0
end
function Widget:GetHeight()
	if self.h then return self.h end
	local _, _, _, h = self:GetRect()
	return h or 0
end

-- SetPoint in all its WoW forms, kept as { point, relativeTo, relativePoint, x, y }.
function Widget:SetPoint(point, a, b, c, d)
	local rel, relPoint, x, y
	if type(a) == "number" then
		rel, relPoint, x, y = nil, point, a, b
	elseif type(b) == "string" then
		rel, relPoint, x, y = a, b, c, d
	else
		rel, relPoint, x, y = a, point, b, c
	end
	if type(rel) == "string" then rel = _G[rel] end
	local anchor = { point, rel or self.parent, relPoint, x or 0, y or 0 }
	for i, p in ipairs(self.points) do
		if p[1] == point then self.points[i] = anchor return end
	end
	self.points[#self.points + 1] = anchor
end
function Widget:SetAllPoints(rel)
	rel = rel or self.parent
	self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetNumPoints() return #self.points end
function Widget:GetPoint(i) return unpack(self.points[i or 1]) end
-- Anchor with this point name, or nil.
function Widget:Anchor(point) for _, p in ipairs(self.points) do if p[1] == point then return p end end end

-- left, bottom, width, height in the widget's own units, from a fixed rect or its anchors.
function Widget:GetRect()
	if self.rect then return unpack(self.rect) end
	if #self.points == 0 then return nil end
	local l, r, cx, b, t, cy
	for _, p in ipairs(self.points) do
		local rl, rb, rw, rh = p[2]:GetRect()
		if not rl then return nil end
		local ax, ay = rl + rw * POINT_X[p[3]] + p[4], rb + rh * POINT_Y[p[3]] + p[5]
		local fx, fy = POINT_X[p[1]], POINT_Y[p[1]]
		if fx == 0 then l = ax elseif fx == 1 then r = ax else cx = ax end
		if fy == 0 then b = ay elseif fy == 1 then t = ay else cy = ay end
	end
	local w, h = self.w or 0, self.h or 0
	if l and r then w = r - l elseif r then l = r - w elseif cx and not l then l = cx - w / 2 end
	if b and t then h = t - b elseif t then b = t - h elseif cy and not b then b = cy - h / 2 end
	if not l or not b then return nil end
	return l, b, w, h
end
function Widget:GetLeft() return (self:GetRect()) end
function Widget:GetBottom() return select(2, self:GetRect()) end
function Widget:GetTop() local _, b, _, h = self:GetRect(); return b and b + h end
function Widget:GetRight() local l, _, w = self:GetRect(); return l and l + w end

function Widget:StartMoving() self.moving = true end
function Widget:StopMovingOrSizing()
	-- Like the client: wherever it was dropped, now held by one absolute anchor.
	local l, b = self:GetRect()
	self.moving = nil
	self.points = { { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b } }
end

function Widget:CreateFontString(name, _, font) local fs = NewWidget("FontString", name, self); fs.font = font; return fs end
function Widget:CreateTexture(name, layer)
	local t = NewWidget("Texture", name, self)
	t.layer = layer
	self.textures = self.textures or {}
	table.insert(self.textures, t)
	return t
end
function Widget:SetText(text)
	if self.kind == "FontString" then self.text = text return end
	self.fontString = self.fontString or self:CreateFontString(nil, "OVERLAY", self.normalFont or "GameFontNormal")
	self.fontString:SetText(text)
end
function Widget:GetText() if self.kind == "FontString" then return self.text end return self.fontString and self.fontString.text end
function Widget:GetFontString() return self.fontString end
function Widget:SetNormalFontObject(font) self.normalFont = font; if self.fontString then self.fontString.font = font end end
function Widget:SetFontObject(font) self.font = font end
function Widget:GetFontObject() return self.font end
function Widget:SetWordWrap(wrap) self.wrap = wrap end
function Widget:SetJustifyH(justify) self.justifyH = justify end
-- As the client draws it: an inline texture (|T...|t) is about two letters wide, colour codes
-- take no room.
function Widget:GetUnboundedStringWidth()
	local shown = (self.text or ""):gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return #shown * (CHAR_W[self.font] or 6)
end
function Widget:GetStringWidth()
	local full = self:GetUnboundedStringWidth()
	return (self.w or 0) > 0 and math.min(full, self.w) or full
end
function Widget:IsTruncated() return self.wrap == false and (self.w or 0) > 0 and self:GetUnboundedStringWidth() > self.w end
function Widget:Click() self:Fire("OnClick") end
-- GameTooltip: who owns it and the lines it shows.
function Widget:SetOwner(owner, anchor) self.owner, self.ownerAnchor, self.lines = owner, anchor, {} end
function Widget:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function Widget:IsOwned(owner) return self.owner == owner end

local TEMPLATES = {
	PortraitFrameTemplate = function(w)
		w.CloseButton = NewWidget("Button", nil, w)
		w.w, w.h = 338, 424
	end,
	BasicFrameTemplateWithInset = function(w)
		w.CloseButton = NewWidget("Button", nil, w)
		w.TitleText = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	end,
	-- The same atlas template on every client (see UI.TabStyle); the Lua sizing it differs.
	PanelTabButtonTemplate = function(w)
		w.h = 32
		for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do w[key] = NewWidget("Texture", nil, w) end
		w.Text = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		w.fontString = w.Text
		w.parent.Tabs = w.parent.Tabs or {}
		table.insert(w.parent.Tabs, w)
	end,
	-- The Guild & Communities window's parts (Blizzard_SharedXML, loaded on every client
	-- family but not all of them on every client).
	RightSideTabTemplate = function(w)
		w.w, w.h = 32, 32
		-- Its art (no key), then its icon.
		local art = w:CreateTexture(nil, "BORDER")
		art:SetSize(64, 64); art:SetPoint("TOPLEFT", -3, 11)
		w.Icon = NewWidget("Texture", nil, w)
		-- RightSideTabMixin:OnClick: its sound, and the check.
		w.scripts.OnClick = function(self) self.clickSound = true; self:SetChecked(true) end
	end,
	ColumnDisplayButtonNoScriptsTemplate = function(w)
		w.h = 24
		for _, key in ipairs({ "Left", "Middle", "Right" }) do w[key] = NewWidget("Texture", nil, w) end
	end,
	ScrollFrameTemplate = function(w)
		w.ScrollBar = NewWidget("EventFrame", nil, w)
		w.ScrollBar.w = 8
	end,
	DialogBorderDarkTemplate = function(w)
		w.Bg = NewWidget("Texture", nil, w)
	end,
}

local createdWidgets = {} -- everything FakeCreateFrame made in the current WithUI
local function FakeCreateFrame(kind, name, parent, template)
	local w = NewWidget(kind, name, parent)
	w.template = template
	if TEMPLATES[template] then TEMPLATES[template](w) end
	createdWidgets[#createdWidgets + 1] = w
	return w
end

-- Blizzard's tab code, as far as it matters here (Blizzard_SharedXML, see UI.TabStyle):
-- Mainline sizes a tab to its text + 20 and has PanelTemplates_AnchorTabs, Classic sizes
-- it to its text + both end caps and does not.
local TAB_GLOBALS = { "PanelTemplates_TabResize", "PanelTemplates_AnchorTabs", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }
local function TabCode(family)
	local capW = 20
	PanelTemplates_SelectTab = function(tab) tab.selected = true end
	PanelTemplates_DeselectTab = function(tab) tab.selected = false end
	if family == "mainline" then
		PanelTemplates_AnchorTabs = function() end
		PanelTemplates_TabResize = function(tab, padding) tab:SetWidth(math.max(tab.Text:GetStringWidth() + 20 + (padding or 0), 2 * capW)) end
	else
		PanelTemplates_TabResize = function(tab, padding) tab:SetWidth(tab.Text:GetStringWidth() + (padding or 24) + 2 * capW) end
	end
end

-- Runs fn with the widget toolkit as the client (the screen is 1366 x 768), failing on
-- any error the addon caught. Everything it made global is cleared afterwards.
local function WithUI(fn)
	local captured
	local saved = { CreateFrame = CreateFrame, CaptureError = ns.CaptureError, UI = ns.UI, GetGuildInfo = GetGuildInfo }
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	CreateFrame = FakeCreateFrame
	UIParent = NewWidget("Frame", "UIParent")
	UIParent.rect = { 0, 0, 1366, 768 }
	UISpecialFrames, tinsert = {}, table.insert
	GameTooltip = NewWidget("GameTooltip", "GameTooltip", UIParent)
	for _, font in ipairs(FONT_GLOBALS) do _G[font] = { font = font } end
	ns.rdb.guilds = SampleGuilds()
	local ok, err = pcall(fn)
	CreateFrame, ns.CaptureError, ns.UI, GetGuildInfo = saved.CreateFrame, saved.CaptureError, saved.UI, saved.GetGuildInfo
	for _, name in ipairs(widgetNames) do _G[name] = nil end
	widgetNames, createdWidgets = {}, {}
	for _, name in ipairs(GUILD_GLOBALS) do _G[name] = nil end
	for _, name in ipairs(TAB_GLOBALS) do _G[name] = nil end
	for _, font in ipairs(FONT_GLOBALS) do _G[font] = nil end
	PTR_IssueReporter, UISpecialFrames, tinsert = nil, nil, nil
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

-- UI.lua with fresh state in a namespace of its own (Views and friends read ns.UI).
local function LoadUI()
	local uns = setmetatable({}, { __index = ns })
	uns.On = function() end
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	ns.UI = uns.UI
	return uns.UI
end

local function Anchor(frame, i)
	local p = frame.points[i or 1]
	return p and table.concat({ p[1], tostring(p[2] and p[2].name), p[3], p[4], p[5] }, " ")
end

test("tab spacing: Blizzard's on Forever (Mainline tab code), the old overlap on Classic", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local UI = uns.UI
	local atlasTab, plainButton = { LeftActive = {} }, {}
	eq(UI.TabStyle(atlasTab), "classic", "same atlas template, Classic code")
	PanelTemplates_AnchorTabs = function() end
	eq(UI.TabStyle(atlasTab), "mainline")
	eq(UI.TabStyle(plainButton), "classic", "fallback buttons keep the old spacing")
	PanelTemplates_AnchorTabs = nil
	local f, prev = {}, {}
	eq(select(5, UI.TabAnchor("mainline", 1, f)), 2)
	eq(table.concat({ select(3, UI.TabAnchor("mainline", 1, f)) }, " "), "BOTTOMLEFT 5 2", "first tab where FriendsFrame has it")
	eq(table.concat({ UI.TabAnchor("mainline", 2, f, prev) }, " ", 3), "TOPRIGHT 3 0", "3 apart, like PanelTemplates_AnchorTabs")
	eq(select(2, UI.TabAnchor("mainline", 2, f, prev)), prev)
	eq(table.concat({ UI.TabAnchor("classic", 1, f) }, " ", 3), "BOTTOMLEFT 10 2")
	eq(table.concat({ UI.TabAnchor("classic", 3, f, prev) }, " ", 3), "RIGHT -15 0")
end)

test("tabs of the old window: four or five of Classic's wide tabs shrink to fit it", function()
	WithUI(function()
		GetGuildInfo = function() return "Olympus II" end
		local savedResize, savedVisible = PanelTemplates_TabResize, ns.King.Visible
		-- Classic's sizing: about 115 wide whatever the text, or the width asked for.
		PanelTemplates_TabResize = function(tab, _, absolute) tab:SetWidth(absolute or 115) end
		ns.King.Visible = function() return true end
		local ok, err = pcall(function()
			local UI = LoadUI()
			UI.Toggle()
			local main = OlympusFrame
			local function Span()
				local n, total = 0, 0
				for _, tab in ipairs(main.tabs) do
					if tab:IsShown() then n = n + 1; total = total + tab:GetWidth() end
				end
				return n, total - 15 * (n - 1)
			end
			local n, span = Span()
			eq(n, 6, "the Throne and Vox Populi too")
			assert(span <= main:GetWidth() - 10, ("six tabs inside the window: %d of %d"):format(span, main:GetWidth()))
			for _, tab in ipairs(main.tabs) do assert(tab:GetWidth() >= 44, "still a tab") end
			-- Room enough: Blizzard's own size.
			main:SetWidth(900)
			UI.Refresh()
			eq(main.tabs[1]:GetWidth(), 115)
		end)
		PanelTemplates_TabResize, ns.King.Visible = savedResize, savedVisible
		if not ok then error(err, 0) end
	end)
end)

test("tabs look like the Friends window's: the older tab on the Classic clients", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local UI = uns.UI
	local saved = FriendsFrameTab1
	FriendsFrameTab1 = {}
	eq(UI.OldTabs(), true, "Anniversary / Era: Friends has the older tab")
	FriendsFrameTab1 = { LeftActive = {} }
	eq(UI.OldTabs(), false, "Forever: the atlas tab")
	FriendsFrameTab1 = nil
	eq(UI.OldTabs(), PanelTemplates_AnchorTabs == nil)
	FriendsFrameTab1 = saved
end)

test("HD docking gap and side tabs: Blizzard's own numbers", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local UI = uns.UI
	eq(UI.DockOffset("old", true), -2, "the old window overlaps the border, as always")
	eq(UI.DockOffset("old", false), -2)
	eq(UI.DockOffset("hd", true), 64, "past the Communities side tabs (32), then Blizzard's gap (32)")
	eq(UI.DockOffset("hd", false), 32, "no side tabs: Blizzard's gap between two windows")
	local f, prev = {}, {}
	eq(table.concat({ UI.TabAnchor("side", 1, f) }, " ", 3), "TOPRIGHT 0 -36", "like the Communities ChatTab")
	eq(select(2, UI.TabAnchor("side", 1, f)), f)
	eq(table.concat({ UI.TabAnchor("side", 2, f, prev) }, " ", 3), "BOTTOMLEFT 0 -20")
	eq(select(2, UI.TabAnchor("side", 2, f, prev)), prev)
	eq(UI.Style(), "old", "without GuildFrame.lua: the old look")
end)

test("tabs on the real window: side by side on Forever, unchanged on Classic", function()
	for _, family in ipairs({ "mainline", "classic" }) do
		WithUI(function()
			TabCode(family)
			local UI = LoadUI()
			UI.SelectTab("census")
			local main = OlympusFrame
			eq(UI.tabTemplate, "PanelTabButtonTemplate"); eq(UI.tabStyle, family)
			local tabs = main.tabs
			if family == "mainline" then
				eq(Anchor(tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 5 2")
				eq(Anchor(tabs[2]), "TOPLEFT " .. tabs[1].name .. " TOPRIGHT 3 0")
				for i = 2, #tabs do
					local gap = tabs[i]:GetLeft() - tabs[i - 1]:GetRight()
					eq(gap, 3, "gap before tab " .. i)
					assert(tabs[i].Text:GetStringWidth() + 20 <= tabs[i]:GetWidth(), "text fits tab " .. i)
				end
				local last
				for _, tab in ipairs(tabs) do if tab:IsShown() then last = tab end end
				assert(last:GetRight() <= main:GetRight(), "last tab inside the window")
			else
				eq(Anchor(tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 10 2")
				eq(Anchor(tabs[3]), "LEFT " .. tabs[2].name .. " RIGHT -15 0")
			end
			eq(tabs[1].selected, true); eq(tabs[2].selected, false)
		end)
	end
end)

test("Join screen: no column titles, the list starts higher, and it follows joining", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		local function listTop() return main.scroll:Anchor("TOPLEFT")[5] end
		eq(main.colHeader:IsShown(), false, "Join screen: no column titles")
		eq(listTop(), -64)
		eq(main.tabs[1]:IsShown(), false)
		-- The player joins an Olympus guild with the window open (DATA_CHANGED, or the
		-- 5 second refresh).
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.colHeader:IsShown(), true, "census column titles once a member")
		eq(listTop(), -80)
		eq(main.tabs[1]:IsShown(), true)
		-- And leaves it.
		GetGuildInfo = function() return "House of Guedes" end
		UI.Refresh()
		eq(main.colHeader:IsShown(), false); eq(listTop(), -64)
		-- Other tabs never had column titles.
		GetGuildInfo = function() return "Olympus II" end
		UI.SelectTab("realm")
		eq(main.colHeader:IsShown(), false); eq(listTop(), -64)
	end)
end)

test("header lines stay inside the window: smaller font first, then cut", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		local w = main:GetWidth()
		eq(w, 338, "the narrow window")
		-- "No guild? What are you doing?" is too wide in the large font, fits in the normal one.
		eq(main.total:GetText(), ns.L.ROAST_NOGUILD)
		eq(main.total.font, "GameFontNormal", "dropped to the smaller font")
		eq(main.total.w, w - 62 - 26); eq(main.total:IsTruncated(), false)
		-- The long line drops to the tiny font, and is cut ("...") at the window's edge
		-- instead of running past it when even that does not fit.
		eq(main.sub:GetText(), ns.L.ROAST_NOGUILD_SUB)
		eq(main.sub.w, w - 62 - 8); eq(main.sub.wrap, false); eq(main.sub.justifyH, "LEFT")
		eq(main.sub.font, "GameFontWhiteTiny")
		eq(main.sub:IsTruncated(), true)
		assert(62 + main.sub:GetStringWidth() <= w, "inside the window")
		-- Forever's window is wider: the Join line fits whole in the tiny font.
		main:SetSize(385, 424)
		eq(main.sub.w, 385 - 62 - 8)
		eq(main.sub.font, "GameFontWhiteTiny"); eq(main.sub:IsTruncated(), false)
		-- A client without the tiny font keeps the small one, cut.
		GameFontWhiteTiny = nil
		UI.Refresh()
		eq(main.sub.font, "GameFontHighlightSmall"); eq(main.sub:IsTruncated(), true)
		-- A member's header fits in the large font and is not cut.
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.total.font, "GameFontNormalLarge"); eq(main.total:IsTruncated(), false)
	end)
end)

test("docking with the real window: follows the guild window it was clicked in", function()
	WithUI(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		FriendsFrame.rect = { 20, 200, 338, 424 }
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 20, 180, 814, 426 }
		local w = LoadGuildFrame(true)
		ns.UI = w.ns.UI
		w.Login()
		local UI = w.ns.UI
		local old, new = w.buttons[1], w.buttons[2]
		local function size() return OlympusFrame:GetWidth() .. "x" .. OlympusFrame:GetHeight() end
		-- Clicked in the Guild tab: next to the Social window, its size.
		FriendsFrame:Show(); GuildFrame:Show(); old:Click()
		local main = OlympusFrame
		eq(main:IsShown(), true); eq(UI.DockedTo(), FriendsFrame)
		eq(Anchor(main), "TOPLEFT FriendsFrame TOPRIGHT -2 0"); eq(main:GetNumPoints(), 1)
		eq(size(), "338x424")
		-- Clicked in the Communities window: moves there, its height, the Social width.
		CommunitiesFrame:Show(); new:Click()
		eq(main:IsShown(), true, "moved, not closed"); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0"); eq(main:GetNumPoints(), 1)
		eq(size(), "338x426")
		-- The Social window closing (it is watched) leaves it docked where it is.
		GuildFrame:Hide(); FriendsFrame:Hide()
		eq(main:IsShown(), true, "the Social window closing leaves it open"); eq(UI.DockedTo(), CommunitiesFrame)
		-- The Communities window is minimized: the new height is taken.
		CommunitiesFrame.w, CommunitiesFrame.h = 322, 406
		CommunitiesFrame:Run("OnSizeChanged")
		eq(size(), "338x406", "follows minimize")
		-- Dragged away: no longer docked, keeps its size and stays open when the guild window
		-- changes or closes.
		main.scripts.OnDragStart(main); main.scripts.OnDragStop(main)
		eq(UI.DockedTo(), nil, "dragged: not docked")
		eq(Anchor(main), "BOTTOMLEFT UIParent BOTTOMLEFT 832 200", "where it was dropped")
		CommunitiesFrame.w, CommunitiesFrame.h = 814, 500
		CommunitiesFrame:Run("OnSizeChanged")
		eq(size(), "338x406", "no longer follows")
		CommunitiesFrame:Hide()
		eq(main:IsShown(), true, "no longer closes with it")
		-- Clicked again: docks again, then a second click closes it.
		CommunitiesFrame:Show(); new:Click()
		eq(main:IsShown(), true); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0"); eq(size(), "338x500")
		new:Click()
		eq(main:IsShown(), false, "second click closes it")
		-- Opened from the Guild tab and closed with it.
		FriendsFrame:Show(); GuildFrame:Show(); old:Click()
		eq(UI.DockedTo(), FriendsFrame); eq(size(), "338x424")
		GuildFrame:Hide()
		eq(main:IsShown(), false, "leaving the Guild tab closes it")
		-- Classic Era: its Communities window gets the old window too.
		eq(rawget(_G, "OlympusFrameHD"), nil, "no HD window on Classic")
	end)
end)

-- Forever with the new guild window (in WithUI): the Social window without a Guild tab, the
-- Communities window with its side tabs shown or not (a guild member or not), the Mainline
-- tab code, and GuildFrame.lua with the real UI.lua.
local function ForeverWorld(sideTabs)
	TabCode("mainline")
	FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
	FriendsFrame.rect = { 20, 200, 385, 424 }
	CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
	CommunitiesFrame.rect = { 16, 180, 814, 426 }
	CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
	CommunitiesFrame.ChatTab = FakeFrame(nil, CommunitiesFrame, 32, 32)
	CommunitiesFrame.ChatTab.shown = sideTabs
	local w = LoadGuildFrame(true)
	ns.UI = w.ns.UI
	w.Login()
	return w, w.ns.UI
end

test("HD window: docked past the Communities window's side tabs, with icon tabs of its own", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		eq(main:IsShown(), true); eq(UI.WindowStyle(), "hd")
		eq(rawget(_G, "OlympusFrame"), nil, "the old window is not even built")
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0"); eq(main:GetNumPoints(), 1)
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x426", "the Social window's width, the host's height")
		eq(main.clampInsets[2], 40, "its side tabs stay on the screen too")
		-- Blizzard's icon tabs down the right side, one per TABS entry, the first one checked.
		local tabs = main.tabs
		eq(#tabs, #UI.TABS); eq(UI.tabTemplate, "RightSideTabTemplate"); eq(UI.tabStyle, "side")
		for i, tab in ipairs(tabs) do
			eq(tab.template, "RightSideTabTemplate")
			if i == 1 then
				eq(Anchor(tab), "TOPLEFT OlympusFrameHD TOPRIGHT 0 -36")
			else
				eq(tab.points[1][2], tabs[i - 1]); eq(Anchor(tab), "TOPLEFT nil BOTTOMLEFT 0 -20")
			end
			assert(tab.Icon.texture and tab.Icon.texture:find("Interface\\Icons\\", 1, true), "icon of tab " .. i)
			eq(tab.tooltip, ns.L[UI.TABS[i].label])
			eq(tab:GetChecked(), i == 1, "checked: tab " .. i)
			assert(tab.level > main:GetFrameLevel(), "over the frame's border")
		end
		eq(tabs[2].Icon.texture, "Interface\\Icons\\INV_BannerPVP_02", "the Alliance banner")
		tabs[3]:Click()
		eq(main.tab, "decrees"); eq(tabs[3].clickSound, true, "Blizzard's own click ran too")
		for i, tab in ipairs(tabs) do eq(tab:GetChecked(), i == 3, "after the click: tab " .. i) end
		for _, wdg in ipairs(createdWidgets) do
			assert(wdg.template ~= "PanelTabButtonTemplate", "no bottom tabs in the HD window")
		end
		-- The Communities window's buttons: 20 tall, 5 from the corner.
		for _, b in ipairs(main.buttons) do eq(b.h, 20); eq(b.w, 123) end
		eq(Anchor(main.buttons[1]), "BOTTOMLEFT OlympusFrameHD BOTTOMLEFT 5 5")
		eq(Anchor(main.detail), "BOTTOMLEFT OlympusFrameHD BOTTOMLEFT 4 28")
		-- The roster's column headers over the census, sorting on click, its thin scroll bar.
		tabs[1]:Click()
		eq(main.colHeader:IsShown(), true)
		eq(Anchor(main.colHeader), "TOPLEFT OlympusFrameHD TOPLEFT 6 -59"); eq(main.colHeader.h, 24)
		eq(main.listBox:Anchor("TOPLEFT")[5], -81); eq(main.scroll:Anchor("TOPLEFT")[5], -84)
		eq(main.scroll.template, "ScrollFrameTemplate"); eq(main.scroll:Anchor("BOTTOMRIGHT")[4], -24)
		eq(main.views.census:GetWidth(), 385 - 33)
		local header = main.colHeader.buttons[1]
		eq(header.template, "ColumnDisplayButtonNoScriptsTemplate"); eq(header.h, 24); eq(header:GetName(), nil)
		eq(header:GetText(), ns.L.COL_GUILD)
		local sort = ns.Views.sort
		header:Click()
		eq(ns.Views.sort.key, "name", "sorted by guild")
		ns.Views.sort = sort
		eq(main.views.census.rows[1].h, 20, "the roster's rows")
		-- The Communities side tabs go (minimized, Guild Finder) and come back.
		CommunitiesFrame.ChatTab:Hide()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "Blizzard's gap only")
		CommunitiesFrame.ChatTab:Show()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		-- Minimized: its height.
		CommunitiesFrame.w, CommunitiesFrame.h = 322, 406
		CommunitiesFrame:Run("OnSizeChanged")
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x406")
		eq(main.buttons[1].w, 123)
		local status = ns.StatusText()
		assert(status:find("tabs: RightSideTabTemplate (side spacing), window hd", 1, true), status)
	end)
end)

test("HD and old windows: each guild window gets its look, switched without /reload", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show() -- found when the Social window opens
		FriendsFrame:Hide()
		local new, classic = w.buttons[1], w.buttons[2]
		eq(w.hook.Hosts()[2].kind, "classicui")
		-- The new window in use, on the Realm tab.
		CommunitiesFrame:Show(); new:Click()
		local hd = OlympusFrameHD
		UI.SelectTab("realm")
		eq(hd.tab, "realm")
		-- Clicked in ClassicUI Forever's Guild tab: the old window, exactly as always.
		FriendsFrame:Show(); classic:Click()
		local old = OlympusFrame
		eq(hd:IsShown(), false, "the HD window closes"); eq(old:IsShown(), true)
		eq(UI.WindowStyle(), "old"); eq(UI.DockedTo(), FriendsFrame)
		eq(Anchor(old), "TOPLEFT FriendsFrame TOPRIGHT -2 0")
		eq(old:GetWidth() .. "x" .. old:GetHeight(), "385x424")
		eq(UI.tabTemplate, "PanelTabButtonTemplate"); eq(UI.tabStyle, "mainline")
		eq(Anchor(old.tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 5 2")
		eq(old.tab, "census", "a guild window's button opens the Census, as always")
		eq(Anchor(old.buttons[1]), "BOTTOMLEFT OlympusFrame BOTTOMLEFT 8 8"); eq(old.buttons[1].h, 22)
		eq(Anchor(old.scroll), "TOPLEFT OlympusFrame TOPLEFT 10 -80"); eq(old.views.census:GetWidth(), 385 - 42)
		eq(old.views.census.rows[1].h, 16)
		-- Back in the Communities window: the HD one again.
		new:Click()
		eq(hd:IsShown(), true); eq(old:IsShown(), false); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(hd), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0"); eq(UI.tabTemplate, "RightSideTabTemplate")
		-- /oly with the old tab the guild window in use: the old window, on the HD one's tab.
		UI.SelectTab("heraldry")
		CommunitiesFrame:Hide()
		eq(hd:IsShown(), false, "closed with the Communities window")
		UI.Toggle()
		eq(old:IsShown(), true); eq(hd:IsShown(), false); eq(old.tab, "heraldry")
		UI.Toggle()
		-- Only the Communities window used since: the HD one.
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Show(); CommunitiesFrame:Hide()
		UI.Toggle()
		eq(hd:IsShown(), true); eq(old:IsShown(), false); eq(hd.tab, "heraldry")
		-- Docked with no tab asked for: the tab in use carries over to the other window.
		UI.SelectTab("decrees")
		FriendsFrame:Show(); UI.OpenDocked(FriendsFrame, nil, false, "old")
		eq(old:IsShown(), true); eq(hd:IsShown(), false); eq(old.tab, "decrees")
	end)
end)

test("ClassicUI Forever's unseen Communities window: /oly keeps the old window", function()
	WithUI(function()
		local _, UI = ForeverWorld(true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		-- Its roster open: the Communities window comes up unseen (alpha 0, off the screen)
		-- for the notes, and goes when the Social window closes.
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		CommunitiesFrame.alpha = 0
		CommunitiesFrame:Show()
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Hide(); CommunitiesFrame.alpha = 1
		UI.Toggle()
		eq(UI.WindowStyle(), "old"); eq(OlympusFrame:IsShown(), true)
		eq(rawget(_G, "OlympusFrameHD"), nil, "the HD window is not even built")
	end)
end)

test("HD window from /oly before the Communities window has loaded, docked once it has", function()
	WithUI(function()
		TabCode("mainline")
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		FriendsFrame.rect = { 20, 200, 385, 424 }
		local w = LoadGuildFrame(true)
		ns.UI = w.ns.UI
		w.Login()
		local UI = w.ns.UI
		UI.Toggle()
		local main = OlympusFrameHD
		eq(UI.WindowStyle(), "hd"); eq(main:IsShown(), true); eq(UI.DockedTo(), nil)
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x426", "the Social window's width, the Communities window's height")
		eq(Anchor(main), "CENTER UIParent CENTER 0 40")
		UI.Toggle()
		-- Blizzard_Communities loads: its window gets the button, which docks the HD window
		-- and keeps it clear of the side tabs.
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 16, 180, 814, 426 }
		CommunitiesFrame.ChatTab = FakeFrame(nil, CommunitiesFrame, 32, 32)
		CommunitiesFrame.ChatTab.shown = true
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		eq(#w.hook.Hosts(), 1); eq(w.hook.Hosts()[1].kind, "communities")
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		eq(main:IsShown(), true); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		CommunitiesFrame.ChatTab:Hide()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "its side tabs are followed")
	end)
end)

test("rows: the HD window's like the Communities roster's, the old window's unchanged", function()
	WithUI(function()
		local Views = ns.Views
		local function Content(style)
			local c = NewWidget("Frame", nil, UIParent)
			c.w, c.style = 300, style
			return c
		end
		local clicked
		local lines = {
			{ header = true, text = "Header" },
			{ text = "Plain" },
			{ text = "Lord", key = "Lordy", onClick = function() clicked = "Lordy" end },
			{ cols = { "a", "b", "c", "d" } },
			{ text = "Racer", key = "Racer", onClick = function() clicked = "Racer" end },
		}
		local hd = Content("hd")
		hd.selectedKey = "Racer"
		Views.Render(hd, lines, Views.COLUMNS.census)
		local rows = hd.rows
		eq(rows[1].h, 20, "20 tall, like the roster")
		eq(rows[2].points[1][5], -2 - 24, "a header line takes 4 more")
		eq(rows[3].points[1][5], -2 - 24 - 20)
		assert(rows[1].highlightTexture:find("UI-FriendsFrame-HighlightBar", 1, true), "the roster's gold bar")
		eq(rows[3].stripe.texture, "Interface\\GuildFrame\\GuildFrame")
		eq(rows[1].stripe:IsShown(), false, "no row background on a header")
		eq(rows[2].stripe:IsShown(), false, "nor on a line that cannot be clicked")
		eq(rows[3].stripe:IsShown(), true); eq(rows[4].stripe:IsShown(), true, "a table row")
		eq(rows[5].locked, true, "the person open stays lit"); eq(rows[3].locked, false)
		rows[3]:Click()
		eq(clicked, "Lordy"); eq(hd.selectedKey, "Lordy")
		eq(rows[3].locked, true); eq(rows[5].locked, false)
		Views.ClearSelection(hd)
		eq(rows[3].locked, false); eq(hd.selectedKey, nil)
		-- The old window's rows, as always: 16 tall, their own highlight, never kept lit.
		local old = Content("old")
		old.selectedKey = "Racer"
		Views.Render(old, lines, Views.COLUMNS.census)
		rows = old.rows
		eq(rows[1].h, 16); eq(rows[2].points[1][5], -2 - 20)
		eq(rows[1].stripe, nil); eq(rows[1].highlightTexture, nil)
		eq(rows[1].textures[1].texture, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
		rows[3]:Click()
		eq(clicked, "Lordy"); eq(old.selectedKey, "Racer")
		for i = 1, #lines do eq(rows[i].locked, nil, "never lit: row " .. i) end
	end)
end)

test("HD person panel: the roster's member card, hanging off the HD window", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		ns.Views.ExpandAll(true)
		UI.SelectTab("realm")
		-- The Lord of Olympus: his line opens his card and stays lit while it is open.
		local row
		for _, r in ipairs(main.views.realm.rows) do
			if r:IsShown() and r.line and r.line.key == "Asmongold" and r.line.indent == 1 then row = r break end
		end
		assert(row, "the Lord's line")
		row:Click()
		local person = OlympusPersonFrameHD
		eq(person:IsShown(), true); eq(person.parent, main)
		-- Docked to the maximized Communities window on the 1366 wide screen, the card would
		-- run past the edge onto our list: it hangs off the window's left side instead.
		eq(Anchor(person), "TOPRIGHT OlympusFrameHD TOPLEFT 4 -76")
		eq(person.w .. "x" .. person.h, "214x226")
		eq(person.Border.template, "DialogBorderDarkTemplate")
		assert(person.level >= main:GetFrameLevel() + 1000, "over the window and its tabs")
		eq(person.name.font, "GameFontNormal"); eq(person.guild:GetText(), "<Olympus>")
		eq(person.whisper.w .. "x" .. person.whisper.h, "96x22"); eq(person.whisper.small, true)
		-- (its `name` is the name line, as on the old panel: anchors are read by hand)
		local p = person.whisper.points[1]
		eq(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "BOTTOMLEFT BOTTOMLEFT 12 36"); eq(p[2], person)
		p = person.mark.points[1]
		eq(p[2], person.who); eq(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "LEFT RIGHT 1 0")
		eq(row.locked, true, "its line stays lit")
		eq(rawget(_G, "OlympusPersonFrame"), nil, "the old panel is not built")
		-- Its buttons: Who through Who.lua, Mark (Heraldry players) runs and closes it.
		local sent, savedSend = nil, ns.Who.SendPlain
		ns.Who.SendPlain = function(query) sent = query end
		person.who:Click()
		ns.Who.SendPlain = savedSend
		eq(sent, 'n-"Asmongold"')
		eq(person.mark:IsShown(), false, "no Mark outside the Heraldry tab")
		person:Hide()
		eq(row.locked, false, "closing the card lets the line go")
		-- Its close button and Escape close it too.
		row:Click()
		person.CloseButton:Click()
		eq(person:IsShown(), false, "closed by its button"); eq(row.locked, false)
		local escape
		for _, name in ipairs(UISpecialFrames) do if name == "OlympusPersonFrameHD" then escape = true end end
		eq(escape, true, "closed by Escape")
		local marked
		row:Click()
		UI.ShowPerson({ name = "Asmongold", guild = "Olympus", onMark = function() marked = true end })
		person.mark:Click()
		eq(marked, true); eq(person:IsShown(), false, "Mark closes it"); eq(row.locked, false)
		-- With room on the right (the Communities window minimized), it hangs off the right side
		-- like Blizzard's.
		CommunitiesFrame.w, CommunitiesFrame.h, CommunitiesFrame.rect = 322, 406, { 16, 200, 322, 406 }
		CommunitiesFrame:Run("OnSizeChanged")
		row:Click()
		eq(Anchor(person), "TOPLEFT OlympusFrameHD TOPRIGHT -4 -76")
		main:Hide()
		eq(person:IsShown(), false, "closed with the window"); eq(row.locked, false)
		ns.Views.ExpandAll(false)
	end)
end)

test("HD Join screen: no tabs or column titles, next to a Communities window without side tabs", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local w, UI = ForeverWorld(false)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "no side tabs there: Blizzard's gap")
		for _, tab in ipairs(main.tabs) do eq(tab:IsShown(), false) end
		eq(main.colHeader:IsShown(), false)
		eq(main.listBox:Anchor("TOPLEFT")[5], -60); eq(main.scroll:Anchor("TOPLEFT")[5], -63)
		local shown = {}
		for _, b in ipairs(main.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
		eq(#shown, 2); eq(shown[1].w, 186); eq(shown[2].w, 186); eq(shown[1].h, 20)
		-- Joins an Olympus guild with both windows open: the Communities side tabs appear too.
		GetGuildInfo = function() return "Olympus II" end
		CommunitiesFrame.ChatTab:Show()
		UI.Refresh()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		-- Every tab but the Throne and Vox Populi (the King's) and the Workshop (the author's).
		for _, tab in ipairs(main.tabs) do eq(tab:IsShown(), tab.key ~= "throne" and tab.key ~= "vox" and tab.key ~= "treasury" and tab.key ~= "workshop", tab.key) end
		eq(main.colHeader:IsShown(), true)
		eq(main.listBox:Anchor("TOPLEFT")[5], -81); eq(main.scroll:Anchor("TOPLEFT")[5], -84)
	end)
end)

test("HD window: eight side tabs are one too many, the Workshop hangs from the left edge", function()
	local K, V, T, W = ns.King, ns.Vox, ns.Treasury, ns.Workshop
	local saved = { K.Visible, V.Visible, T.Visible, W.Visible }
	local function Yes() return true end
	local ok, err = pcall(WithUI, function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		local function Tab(key) for _, tab in ipairs(main.tabs) do if tab.key == key then return tab end end end
		local ws = Tab("workshop")
		eq(UI.SideTabsFit(7, 32, 426), true); eq(UI.SideTabsFit(8, 32, 426), false)
		-- The author alone: his Workshop under the four everyone has, down the right.
		W.Visible = Yes
		UI.Refresh()
		eq(ws:IsShown(), true); eq(ws.points[1][2], Tab("heraldry")); eq(Anchor(ws), "TOPLEFT nil BOTTOMLEFT 0 -20")
		eq(ws.onLeft or false, false); eq(main.clampInsets[1], 0)
		-- Asmond view: the Throne, Vox Populi and the Treasury make eight.
		K.Visible, V.Visible, T.Visible = Yes, Yes, Yes
		UI.Refresh()
		eq(Anchor(ws), "BOTTOMRIGHT OlympusFrameHD BOTTOMLEFT 0 46"); eq(ws:GetNumPoints(), 1)
		eq(ws.onLeft, true); eq(Anchor(ws.Art), "TOPRIGHT nil TOPRIGHT 3 11"); eq(ws.Art.texCoord, "1 0 0 1", "its art turned round")
		eq(main.clampInsets[1], -40, "on the screen too"); eq(main.clampInsets[2], 40)
		-- The other seven still down the right, the Treasury last.
		local right = {}
		for _, tab in ipairs(main.tabs) do if tab:IsShown() and tab ~= ws then right[#right + 1] = tab end end
		eq(#right, 7); eq(right[7].key, "treasury")
		eq(Anchor(right[1]), "TOPLEFT OlympusFrameHD TOPRIGHT 0 -36"); eq(right[7].points[1][2], right[6])
		-- Its tooltip to the left, clear of the window; the others' to the right.
		ws:Fire("OnEnter"); eq(GameTooltip.owner, ws); eq(GameTooltip.ownerAnchor, "ANCHOR_LEFT")
		right[1]:Fire("OnEnter"); eq(GameTooltip.ownerAnchor, "ANCHOR_RIGHT")
		ws:Click(); eq(main.tab, "workshop"); eq(ws:GetChecked(), true)
		-- Asmond view off: back under the others, its art as it was.
		K.Visible, V.Visible, T.Visible = saved[1], saved[2], saved[3]
		UI.Refresh()
		eq(ws.onLeft, false); eq(Anchor(ws), "TOPLEFT nil BOTTOMLEFT 0 -20"); eq(ws.points[1][2], Tab("heraldry"))
		eq(Anchor(ws.Art), "TOPLEFT nil TOPLEFT -3 11"); eq(ws.Art.texCoord, "0 1 0 1"); eq(main.clampInsets[1], 0)
	end)
	K.Visible, V.Visible, T.Visible, W.Visible = saved[1], saved[2], saved[3], saved[4]
	assert(ok, err)
end)

test("HD window on a client without Blizzard's new parts: built from what is there", function()
	local missing, saved = { "RightSideTabTemplate", "ColumnDisplayButtonNoScriptsTemplate", "ScrollFrameTemplate", "DialogBorderDarkTemplate" }, {}
	for _, name in ipairs(missing) do saved[name], TEMPLATES[name] = TEMPLATES[name], nil end
	local ok, err = pcall(WithUI, function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		-- Side tabs made here, like RightSideTab.xml.
		eq(UI.tabTemplate, "fallback"); eq(UI.tabStyle, "side")
		local tab = main.tabs[1]
		eq(tab.w .. "x" .. tab.h, "32x32"); eq(tab.Icon.texture, UI.TABS[1].icon)
		eq(tab.highlightTexture, "Interface\\Buttons\\ButtonHilight-Square"); eq(tab:GetChecked(), true)
		main.tabs[2]:Click()
		eq(main.tab, "realm"); eq(main.tabs[2]:GetChecked(), true); eq(main.tabs[1]:GetChecked(), false)
		-- The old scroll bar, with the room it needs.
		eq(main.scroll:GetName(), "OlympusScrollHDOld"); eq(main.scroll:Anchor("BOTTOMRIGHT")[4], -30)
		eq(main.views.census:GetWidth(), 385 - 39)
		eq(OlympusScrollHD:IsShown(), false, "the one without a scroll bar is hidden")
		-- Plain column titles, the rejected ones hidden.
		main.tabs[1]:Click()
		local header = main.colHeader.buttons[1]
		eq(header.template, nil); eq(header:IsShown(), true); eq(header:GetText(), ns.L.COL_GUILD)
		eq(OlympusColumnHeaderHD1:IsShown(), false)
		-- The old person panel, next to the HD window: the row it was opened from is let go
		-- when it closes, as with the HD one.
		ns.Views.ExpandAll(true)
		UI.SelectTab("realm")
		local row
		for _, r in ipairs(main.views.realm.rows) do
			if r:IsShown() and r.line and r.line.key == "Asmongold" and r.line.indent == 1 then row = r break end
		end
		assert(row, "the Lord's line")
		row:Click()
		eq(OlympusPersonFrame:IsShown(), true); eq(OlympusPersonFrameHD:IsShown(), false)
		eq(Anchor(OlympusPersonFrame), "TOPLEFT OlympusFrameHD TOPRIGHT -2 -28")
		eq(row.locked, true)
		OlympusPersonFrame:Hide()
		eq(row.locked, false, "let go"); UI.Refresh(); eq(row.locked, false, "and stays so")
		row:Click()
		main:Hide()
		eq(OlympusPersonFrame:IsShown(), false, "closed with the window"); eq(row.locked, false)
		ns.Views.ExpandAll(false)
	end)
	for _, name in ipairs(missing) do TEMPLATES[name] = saved[name] end
	if not ok then error(err, 0) end
end)

test("a new tab is one entry in UI.TABS: an icon tab in the HD window, a bottom tab in the old", function()
	local channels = { key = "channels", label = "TAB_CHANNELS", icon = "Interface\\Icons\\INV_Misc_Note_02" }
	for _, hdLook in ipairs({ true, false }) do
		WithUI(function()
			local UI, main
			if hdLook then
				local w
				w, UI = ForeverWorld(true)
				table.insert(UI.TABS, channels)
				CommunitiesFrame:Show(); w.buttons[1]:Click()
				main = OlympusFrameHD
			else
				TabCode("mainline")
				UI = LoadUI()
				table.insert(UI.TABS, channels)
				UI.Toggle()
				main = OlympusFrame
			end
			local n = #UI.TABS
			eq(#main.tabs, n)
			local last = main.tabs[n]
			if hdLook then
				-- Under the last shown tab: the Throne and the Workshop before it are hidden.
				local above
				for i = n - 1, 1, -1 do if main.tabs[i]:IsShown() then above = main.tabs[i] break end end
				eq(last.points[1][2], above); eq(Anchor(last), "TOPLEFT " .. tostring(above.name) .. " BOTTOMLEFT 0 -20")
				eq(last.Icon.texture, channels.icon); eq(last.tooltip, "TAB_CHANNELS")
			else
				eq(last.template, "PanelTabButtonTemplate"); eq(last:GetText(), "TAB_CHANNELS")
			end
			UI.SelectTab("channels")
			eq(main.tab, "channels"); eq(#(main.views.channels.rows or {}), 0, "an empty list")
			for _, b in ipairs(main.buttons) do eq(b:IsShown(), false, "no buttons") end
		end)
	end
end)

test("clearing a rect: up just enough, never off the screen", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local ClearUp = uns.UI.ClearUp
	local function R(l, b, r, t) return { left = l, bottom = b, right = r, top = t } end
	local win = R(500, 182, 840, 636)
	eq(ClearUp(win, R(640, 142, 728, 228), 768, 4), 50, "overlapping: up past its top plus the gap")
	eq(ClearUp(win, R(10, 142, 90, 228), 768, 4), nil, "beside it")
	eq(ClearUp(win, R(640, 100, 728, 182), 768, 4), nil, "just touching below")
	eq(ClearUp(win, R(640, 600, 728, 700), 768, 4), nil, "cannot clear without leaving the screen")
	eq(ClearUp(win, R(640, 142, 728, 228), 690, 4), 50, "room enough")
	eq(ClearUp(win, R(640, 142, 728, 228), 680, 4), nil, "not quite")
	eq(ClearUp(nil, R(640, 142, 728, 228), 768, 4), nil)
end)

-- Blizzard's Issue Reporter (Blizzard_PTRFeedback): a 80 x 32 box, its bug button in a
-- body below it and a border around it, at `x, y` (screen pixels, bottom left) and `scale`.
local function IssueReporter(x, y, scale)
	local s = scale or 1
	local r = NewWidget("Frame", nil, UIParent)
	r.scale = s
	r.rect = { x / s, y / s, 80 / s, 32 / s }
	r.Border = NewWidget("Frame", nil, r); r.Border.rect = { (x - 4) / s, (y - 4) / s, 88 / s, 40 / s }
	r.Body = NewWidget("Frame", nil, r); r.Body.rect = { x / s, (y - 50) / s, 80 / s, 50 / s }
	r.ReportBug = NewWidget("Button", nil, r); r.ReportBug.rect = { (x + 13) / s, (y - 46) / s, 54 / s, 40 / s }
	PTR_IssueReporter = r
	return r
end

test("Issue Reporter: the window steps above it when it opens, never over a player's choice", function()
	WithUI(function()
		-- Where Blizzard puts it by default: bottom centre, a quarter up the screen.
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- The window (bottom 212) and its tabs (down to 182) cover it (142 to 228): up 50.
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "moved up just enough")
		eq(main:GetBottom() - 30, 232, "tabs 4 above the reporter")
		UI.Toggle(); UI.Toggle()
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "clear now: not moved again")
		-- Dragged onto it by the player: stays there, now and when opened again.
		main.scripts.OnDragStart(main)
		main:ClearAllPoints(); main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 500, 200)
		main.scripts.OnDragStop(main)
		UI.Toggle(); UI.Toggle()
		eq(Anchor(main), "BOTTOMLEFT UIParent BOTTOMLEFT 500 200", "the player's place is kept")
	end)
	WithUI(function()
		-- Join screen (no tabs), reporter drawn at a smaller scale, our window at 0.8.
		GetGuildInfo = function() return nil end
		UIParent.scale = 0.8
		UIParent.rect = { 0, 0, 1366 / 0.8, 768 / 0.8 }
		IssueReporter(643, 192, 0.5)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- Bottom at (480 + 40 - 212) * 0.8 = 246.4 px, the reporter's top 228 + 4: already clear.
		eq(Anchor(main), "CENTER UIParent CENTER 0 40", "no tabs on the Join screen, nothing to clear")
		GetGuildInfo = function() return "Olympus II" end
		UI.Toggle(); UI.Toggle()
		-- With the tabs: bottom (308 - 30) * 0.8 = 222.4 px, needs 9.6 px = 12 of ours.
		local y = main.points[1][5]
		assert(math.abs(y - 52) < 0.001, "moved up 12 in its own scale, got " .. y)
	end)
	WithUI(function()
		-- Too high to step above, or off to the side, or hidden: left alone.
		local UI = LoadUI()
		IssueReporter(643, 620)
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "cannot clear it: stays")
		UI.Toggle()
		IssueReporter(20, 192)
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "not in the way")
		UI.Toggle()
		IssueReporter(643, 192).shown = false
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "hidden")
	end)
	WithUI(function()
		-- Shown the moment it was made, before the client laid it out: looked at once more
		-- on the next frame, and only once.
		IssueReporter(643, 192)
		local savedAfter, later = C_Timer.After, {}
		C_Timer.After = function(_, fn) later[#later + 1] = fn end
		local rect = UIParent.rect
		UIParent.rect = nil
		local UI = LoadUI()
		UI.Toggle()
		UIParent.rect = rect
		C_Timer.After = savedAfter
		eq(#later, 1, "one retry")
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "nothing to measure yet")
		later[1]()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 90", "moved on the next frame")
	end)
	WithUI(function()
		-- Docked: stays glued to the guild window, whatever covers it.
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 0, 150, 500, 426 }
		CommunitiesFrame.shown = true
		IssueReporter(560, 192)
		local UI = LoadUI()
		UI.OpenDocked(CommunitiesFrame, "census", true)
		eq(Anchor(OlympusFrame), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0")
	end)
end)

test("Issue Reporter: tabs appearing with the window open (joined a guild) step it up again", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- Join screen, no tabs: the window (bottom 212) steps 4 above the reporter (228).
		eq(Anchor(main), "CENTER UIParent CENTER 0 60")
		-- Joined with the window open: the tabs now hang down to 202, over the reporter.
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.tabs[1]:IsShown(), true)
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "tabs 4 above the reporter")
		eq(main:GetBottom() - 30, 232)
		UI.Refresh()
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "only when they appear")
	end)
end)

test("Issue Reporter: the copy box steps above it too, unless the player moved it", function()
	WithUI(function()
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.ShowCopy(ns.L.REPORT_BUG, "text")
		local box = OlympusCopyFrame
		-- 520 x 340 at the centre: its bottom (214) and hint are over the reporter (228).
		eq(Anchor(box), "CENTER UIParent CENTER 0 18", "4 above the reporter")
		box:Hide(); UI.ShowCopy(ns.L.REPORT_BUG, "text")
		eq(Anchor(box), "CENTER UIParent CENTER 0 18", "clear now: not moved again")
		box.scripts.OnDragStart(box)
		box:ClearAllPoints(); box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 400, 150)
		box.scripts.OnDragStop(box)
		box:Hide(); UI.ShowCopy(ns.L.REPORT_BUG, "text")
		eq(Anchor(box), "BOTTOMLEFT UIParent BOTTOMLEFT 400 150", "the player's place is kept")
	end)
end)

test("person panel: whisper and invite reach the whole name (a report's names are short for its realm)", function()
	WithUI(function()
		local UI = LoadUI()
		local savedTell, savedInvite, savedParty, savedSplit = ChatFrame_SendTell, InviteUnit, C_PartyInfo, ns.splitNames
		local told, invited
		ChatFrame_SendTell = function(n) told = n end
		C_PartyInfo, InviteUnit = nil, function(n) invited = n end
		local ok, err = pcall(function()
			ns.splitNames = nil
			UI.Toggle()
			-- A Captain from a guild report sent from another realm: "Capt" there is Capt-Other.
			UI.ShowPerson({ name = "Capt", realm = "Other", guild = "Olympus II" })
			OlympusPersonFrame.whisper:Click(); OlympusPersonFrame.invite:Click()
			eq(told, "Capt-Other"); eq(invited, "Capt-Other")
			-- One of our realm: the short name, as the server wants it.
			UI.ShowPerson({ name = "Bob", realm = ns.realm, guild = "Olympus II" })
			OlympusPersonFrame.whisper:Click()
			eq(told, "Bob")
			-- Forever: First Surname, whatever realm of the group the report came from.
			ns.splitNames = true
			UI.ShowPerson({ name = "Faladoriel Skylance", realm = ns.realm, guild = "Olympus II" })
			OlympusPersonFrame.whisper:Click()
			eq(told, "Faladoriel Skylance")
		end)
		ChatFrame_SendTell, InviteUnit, C_PartyInfo, ns.splitNames = savedTell, savedInvite, savedParty, savedSplit
		if not ok then error(err, 0) end
	end)
end)

test("Issue Reporter: the person panel steps above it too", function()
	WithUI(function()
		local UI = LoadUI()
		UI.Toggle()
		-- Window at 514..852 x 212..636; the panel hangs off its right, 850..1080 x 398..608.
		-- The reporter with its border: 376..416.
		IssueReporter(900, 380)
		UI.ShowPerson({ name = "Asmongold-Realm", class = "WARRIOR", level = 25, online = true })
		local person = OlympusPersonFrame
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "the window is not in the way: not moved")
		eq(Anchor(person), "TOPLEFT OlympusFrame TOPRIGHT -2 -6", "panel up 22: 4 above the reporter")
		eq(person.name.wrap, false, "long names are not wrapped over the lines below")
		eq(person.name.font, "GameFontNormalLarge", "a short name keeps the large font")
		UI.ShowPerson({ name = "Bellattrixxlestrange-ClassicBetaPvP" })
		eq(person.name.font, "GameFontNormal", "a long one drops to the normal font")
		PTR_IssueReporter = nil
		UI.ShowPerson({ name = "Asmongold-Realm" })
		eq(Anchor(person), "TOPLEFT OlympusFrame TOPRIGHT -2 -28", "back in its place without it")
	end)
end)

---------------------------------------------------------------------------
-- /who (Who.lua): quiet searches, the 50 cap, and the guilds it sees for the census
---------------------------------------------------------------------------

local WHO = "WHO_LIST_UPDATE"

-- A frame that listens to WHO_LIST_UPDATE (or not) and remembers every change to that.
local function ListenerFrame(name, listening)
	local f = { name = name, events = { [WHO] = listening or nil }, calls = {}, shown = false }
	function f:IsEventRegistered(event) return self.events[event] == true end
	function f:RegisterEvent(event) self.events[event] = true; self.calls[#self.calls + 1] = "register" end
	function f:UnregisterEvent(event) self.events[event] = nil; self.calls[#self.calls + 1] = "unregister" end
	function f:IsVisible() return self.shown end
	return f
end
local function Listening(f) return f:IsEventRegistered(WHO) end

-- Runs fn(server) against a stand-in of the game's /who: C_FriendList answers with the
-- rows the test gives Answer() (and announces them like the client), timers wait until
-- Run() and the clock only moves when the test says. Everything is put back afterwards.
local WHO_GLOBALS = { "C_FriendList", "hooksecurefunc", "GetMaxPlayerLevel", "FriendsFrame", "LFGWhoListFrame", "WhoFrame", "ClassicUIForeverWhoPanel" }
local function WithWho(fn)
	local server = { sent = {}, toUi = {}, rows = {}, timers = {}, printed = {}, clock = 5000 }
	local saved = { After = C_Timer.After, GetTime = GetTime, Print = ns.Print, CaptureError = ns.CaptureError,
		guilds = ns.rdb.guilds, seen = ns.rdb.seen, found = ns.Recruit.found }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.Print = function(msg) server.printed[#server.printed + 1] = msg end
	GetTime = function() return server.clock end
	C_Timer.After = function(seconds, f) server.timers[#server.timers + 1] = { seconds = seconds, fn = f } end
	C_FriendList = {
		SendWho = function(query) server.sent[#server.sent + 1] = query end,
		SetWhoToUi = function(on) server.toUi[#server.toUi + 1] = on end,
		GetNumWhoResults = function() return #server.rows, server.total or #server.rows end,
		GetWhoInfo = function(i)
			local r = server.rows[i]
			return r and { fullName = r[1], fullGuildName = r[2], level = r[3], filename = r[4], area = "Elwynn Forest" }
		end,
	}
	hooksecurefunc = function(t, key, post)
		local original = t[key]
		t[key] = function(...) original(...); post(...) end
	end
	GetMaxPlayerLevel = function() return 60 end
	-- The client announcing an answer (rows = { name, guild, level, class }); no rows: the
	-- same answer again.
	function server.Answer(rows, total)
		if rows then server.rows, server.total = rows, total end
		for _, f in ipairs(EVENT_SCRIPTS) do f(nil, WHO) end
	end
	-- Runs the waiting timers of that many seconds (every one when nil), oldest first.
	function server.Run(seconds)
		local keep, due = {}, {}
		for _, t in ipairs(server.timers) do
			if seconds == nil or t.seconds == seconds then due[#due + 1] = t else keep[#keep + 1] = t end
		end
		server.timers = keep
		for _, t in ipairs(due) do t.fn() end
	end
	-- A click on the search button once the cooldown is over.
	function server.Click()
		server.clock = server.clock + ns.Who.COOLDOWN + 1
		return ns.Who.Search()
	end
	ns.rdb.guilds, ns.rdb.seen, ns.Recruit.found = {}, {}, {}
	ns.Who.Reset()
	ns.Who.lastSend, ns.Who.lastPlain = 0, 0
	-- (These tests click faster than 0.9.2's once a minute: theirs is the old pace; the minute
	-- has its own test.)
	local autoGap = ns.Who.AUTO_GAP
	ns.Who.lastAuto, ns.Who.AUTO_GAP = -math.huge, ns.Who.COOLDOWN
	local ok, err = pcall(fn, server)
	ns.Who.Reset()
	ns.Who.lastSend, ns.Who.lastPlain = 0, 0
	ns.Who.lastAuto, ns.Who.AUTO_GAP = -math.huge, autoGap
	C_Timer.After, GetTime, ns.Print, ns.CaptureError = saved.After, saved.GetTime, saved.Print, saved.CaptureError
	ns.rdb.guilds, ns.rdb.seen, ns.Recruit.found = saved.guilds, saved.seen, saved.found
	for _, name in ipairs(WHO_GLOBALS) do _G[name] = nil end
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

-- Olympus players P<from>..P<to>, odd ones in OLYMPUS VII, even ones in OLYMPUS I, levels 7-20.
local function Players(from, to)
	local rows = {}
	for i = from, to do rows[#rows + 1] = { "P" .. i, i % 2 == 0 and "OLYMPUS I" or "OLYMPUS VII", 7 + i % 14, "MAGE" } end
	return rows
end

test("who on Forever: only the frames that listen are silenced, and get the event back with the answer", function()
	WithWho(function(server)
		-- Forever's Social window does not listen, the group finder's who list does, and so
		-- does ClassicUI Forever's list when that addon is on.
		FriendsFrame = ListenerFrame("FriendsFrame", false)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ClassicUIForeverWhoPanel = { driver = ListenerFrame("driver", true) }
		local cui = ClassicUIForeverWhoPanel.driver
		eq(ns.Recruit.Search(), true)
		eq(table.concat(server.sent, "|"), 'g-"Olympus"')
		eq(Listening(LFGWhoListFrame), false, "the group finder's list is silenced")
		eq(Listening(cui), false, "ClassicUI Forever's list is silenced")
		eq(#FriendsFrame.calls, 0, "the Social window, which does not listen, is left alone")
		eq(server.toUi[#server.toUi], true, "results to the UI (the event), not to chat")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" }, { "Bb", "OLYMPUS VII", 14, "ROGUE" },
			{ "Aa", "OLYMPUS VII", 12, "MAGE" }, { "Cc", "Horde Pals", 10, "MAGE" } })
		eq(#ns.Recruit.found, 2, "Olympus players, each once (the server lists some twice)")
		-- The same answer announced again (another addon sorting the list does that): still
		-- ours, read again, nobody twice, and Blizzard's list stays quiet.
		server.Answer()
		eq(#ns.Recruit.found, 2)
		eq(Listening(LFGWhoListFrame), false, "still quiet while the answer settles")
		server.Run(ns.Who.SETTLE)
		eq(Listening(LFGWhoListFrame), true, "event given back")
		eq(Listening(cui), true)
		eq(table.concat(LFGWhoListFrame.calls, " "), "unregister register", "once each")
		eq(#FriendsFrame.calls, 0, "never given an event it did not have")
		eq(server.toUi[#server.toUi], false, "back to Blizzard's default")
		server.Run()
		eq(table.concat(LFGWhoListFrame.calls, " "), "unregister register", "the timeout changes nothing more")
		-- The next answer is not ours: not read.
		server.Answer({ { "Dd", "OLYMPUS II", 5, "MAGE" } })
		eq(#ns.Recruit.found, 2, "someone else's answer")
		eq(ns.Who.StatusLines(), nil, "everyone fit in one answer: nothing to add")
	end)
end)

test("who on its own: a click in the window searches quietly, range by range, not again for a while", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		eq(ns.Who.Auto(), true, "the first click searches")
		eq(ns.Who.Auto(), false, "not while its answer is coming")
		server.Answer(Players(1, 50), 50)
		server.Run(ns.Who.SETTLE)
		eq(ns.Who.Auto(), false, "nor within the cooldown")
		for k = 1, #ns.Who.sweep.brackets do
			server.clock = server.clock + ns.Who.COOLDOWN + 1
			eq(ns.Who.Auto(), true, "the next level range")
			server.Answer(Players(50 + k * 10, 55 + k * 10))
			server.Run(ns.Who.SETTLE)
		end
		eq(ns.Who.sweep.done, true)
		-- Then the misspelled names, one per click: a player of <OLYMPVS> counts.
		for k, variant in ipairs(ns.Who.VARIANTS) do
			server.clock = server.clock + ns.Who.COOLDOWN + 1
			eq(ns.Who.Auto(), true, "the spelling " .. variant)
			eq(server.sent[#server.sent], ('g-"%s"'):format(variant))
			server.Answer(k == 1 and { { "Romanus", "OLYMPVS", 12, "MAGE" }, { "Olaf", "Olympiad Fans", 12, "MAGE" } } or {})
			server.Run(ns.Who.SETTLE)
		end
		assert(ns.Who.sweep.byName.Romanus, "a player of <OLYMPVS> joins the round")
		eq(ns.Who.sweep.byName.Olaf, nil, "a guild that is not Olympus does not")
		eq(ns.Who.sweep.done, true, "still complete")
		server.clock = server.clock + ns.Who.COOLDOWN + 1
		eq(ns.Who.Auto(), false, "a complete round is not searched again at once")
		server.clock = server.clock + ns.Who.AUTO_AGAIN
		LFGWhoListFrame.shown = true
		eq(ns.Who.Auto(), false, "the player's own who list is open: left alone")
		LFGWhoListFrame.shown = false
		eq(ns.Who.Auto(), true)
		eq(server.sent[#server.sent], 'g-"Olympus"', "a new round")
		eq(#server.printed, 0, "never a word in chat")
	end)
end)

test("Wall of Shame: closed with a countdown until midnight in Texas, then open", function()
	local I, from, show = ns.Inspect, ns.Inspect.SHAME_FROM, ns.Inspect.ShowShame
	eq(from, 1790312400, "2026-09-25 00:00 CDT")
	I.SHAME_FROM = time() + 3600
	eq(I.ShameOpen(), false)
	assert(I.ShameOpensIn() > 3500)
	I.SHAME_FROM = time() - 1
	eq(I.ShameOpen(), true)
	I.SHAME_FROM, I.ShowShame = from, show
end)

test("who for one guild: opening its row lists its players, kept apart from the round", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		-- A round under way (capped: the next click searches a level range).
		eq(ns.Who.Auto(), true)
		server.Answer(Players(1, 50), 50)
		server.Run(ns.Who.SETTLE)
		local step = ns.Who.sweep.step
		server.clock = server.clock + ns.Who.COOLDOWN + 1
		eq(ns.Who.SearchGuild('Bad"Name'), false, "no quotes in a guild name")
		eq(ns.Who.SearchGuild("OLYMPUS I"), true)
		eq(server.sent[#server.sent], 'g-"OLYMPUS I"')
		-- The server lists every guild with those letters: only that guild's players are kept.
		server.Answer({ { "Gq1", "OLYMPUS I", 20, "MAGE" }, { "Gq2", "OLYMPUS I", 18, "PRIEST" }, { "Other", "OLYMPUS II", 9, "ROGUE" } })
		server.Run(ns.Who.SETTLE)
		local list = ns.Who.GuildSeen("OLYMPUS I")
		eq(#list, 2)
		eq(ns.Who.sweep.step, step, "the round goes on where it was")
		local members = ns.Views.MembersOf("OLYMPUS I", { officers = {} })
		local names = {}
		for _, m in ipairs(members) do names[m.name] = true end
		assert(names.Gq1 and names.Gq2, "its own search and the round's, each once")
		server.clock = server.clock + ns.Who.COOLDOWN + 1
		eq(ns.Who.SearchGuild("OLYMPUS I"), false, "once a minute per guild")
		eq(#server.printed, 0, "quiet")
	end)
end)

test("who on the old UI: no answer, the Social window gets the event back on the timeout", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		eq(ns.Who.Search(), true)
		eq(Listening(FriendsFrame), false, "the Social window's Who tab is silenced")
		server.Run(ns.Who.SETTLE)
		eq(Listening(FriendsFrame), false, "nothing settles without an answer")
		server.Run(ns.Who.TIMEOUT)
		eq(Listening(FriendsFrame), true, "given back on the timeout")
		-- Its answer may still come. Blizzard's default would open the Who tab for a long
		-- one (ShowWhoPanel), so results go to the UI, where the event only updates the list.
		eq(server.toUi[#server.toUi], true, "still to the UI while the answer may come")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" } })
		eq(#ns.Recruit.found, 0, "a late answer is not taken")
		eq(server.toUi[#server.toUi], false, "it came: back to Blizzard's default")
		local toUi = #server.toUi
		server.Run(ns.Who.LATE)
		eq(#server.toUi, toUi, "nothing more to do after it")
		-- 10 seconds between two searches, whichever button sends them.
		server.clock = server.clock + 5
		eq(ns.Who.Search(), false)
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(5))
		eq(#server.sent, 1)
		-- Unanswered: the next click asks the same again.
		eq(server.Click(), true)
		eq(server.sent[2], 'g-"Olympus"')
		-- A search still waiting when the next one goes (cannot happen with a timeout shorter
		-- than the cooldown, but): the old timeout leaves the new search alone.
		eq(server.Click(), true)
		eq(Listening(FriendsFrame), false)
		eq(table.concat(FriendsFrame.calls, " "), "unregister register unregister register unregister")
		server.timers[1].fn()
		eq(Listening(FriendsFrame), false, "an old timeout does not end a newer search")
		server.Run()
		eq(Listening(FriendsFrame), true)
	end)
end)

test("who: with the player's own Who window open nothing is sent or silenced", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		LFGWhoListFrame.shown = true
		eq(ns.Who.Search(), false)
		eq(#server.sent, 0); eq(#LFGWhoListFrame.calls, 0); eq(#server.toUi, 0)
		eq(server.printed[1], ns.L.WHO_WINDOW_OPEN)
		-- The old UI's Who tab counts too.
		LFGWhoListFrame.shown = false
		WhoFrame = ListenerFrame("WhoFrame")
		WhoFrame.shown = true
		eq(ns.Who.Search(), false)
		WhoFrame.shown = false
		eq(ns.Who.Search(), true, "a skipped search spends no cooldown")
	end)
end)

test("who: someone else's search while ours waits gives the event back at once", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		eq(Listening(LFGWhoListFrame), false)
		local toUi = #server.toUi
		C_FriendList.SendWho('n-"Bob"') -- the player's own /who
		eq(Listening(LFGWhoListFrame), true, "given back at once")
		eq(#server.toUi, toUi, "results still to the UI: our answer may come first")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" } })
		eq(#ns.Recruit.found, 0, "that answer may be theirs: not read")
		eq(server.toUi[#server.toUi], false, "then Blizzard's default, for theirs")
		-- The player opened their Who window meanwhile: it keeps the results.
		server.Click()
		LFGWhoListFrame.shown = true
		toUi = #server.toUi
		C_FriendList.SendWho('n-"Bob"')
		server.Answer()
		server.Run()
		eq(#server.toUi, toUi, "results stay with the open Who window")
		eq(server.sent[#server.sent - 1], 'g-"Olympus"', "unanswered: the click repeated the broad search")
	end)
end)

test("who: a search given up goes back to Blizzard's default once it can no longer be answered", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		-- Never answered: LATE seconds on.
		ns.Who.Search()
		server.Run(ns.Who.TIMEOUT)
		eq(server.toUi[#server.toUi], true)
		server.Run(ns.Who.LATE)
		eq(server.toUi[#server.toUi], false, "never answered")
		-- Given up, then the player searches: that answer gets Blizzard's default at once.
		server.Click()
		server.Run(ns.Who.TIMEOUT)
		eq(server.toUi[#server.toUi], true)
		C_FriendList.SendWho('n-"Bob"')
		eq(server.toUi[#server.toUi], false, "the player's own search, ours given up")
		-- A new search of ours: the old wait ends, and its timer leaves the new one alone.
		server.Click()
		server.Run(ns.Who.TIMEOUT)
		server.Click()
		eq(server.toUi[#server.toUi], true); eq(Listening(FriendsFrame), false)
		server.Run(ns.Who.LATE)
		eq(server.toUi[#server.toUi], true, "the old search's timer changes nothing")
		eq(Listening(FriendsFrame), false)
	end)
end)

test("who: the person panel's Who keeps its distance from our searches", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		server.clock = server.clock + 2
		eq(ns.Who.SendPlain('n-"Bob"'), false, "ours may still be answered")
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(8))
		eq(#server.sent, 1); eq(Listening(LFGWhoListFrame), false, "ours still waits, quiet")
		server.Answer(Players(1, 3))
		server.Run()
		server.clock = server.clock + ns.Who.COOLDOWN
		local toUi = #server.toUi
		eq(ns.Who.SendPlain('n-"Bob"'), true)
		eq(server.sent[#server.sent], 'n-"Bob"')
		eq(Listening(LFGWhoListFrame), true, "nothing silenced"); eq(#server.toUi, toUi, "Blizzard's default")
		eq(ns.Who.SendPlain('n-"Ann"'), true, "one after another, as before")
		-- Ours waits after it: its answer is not ours.
		server.clock = server.clock + 3
		eq(ns.Who.Search(), false)
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(7))
		server.Answer(Players(1, 1))
		eq(#ns.Recruit.found, 3, "their answer is not read")
	end)
end)

test("who: a round left unfinished starts over later, its old players dropped", function()
	WithWho(function(server)
		ns.Who.Search()
		server.Answer(Players(1, 50), 312)
		server.Run()
		eq(#ns.Recruit.found, 50); eq(ns.rdb.seen["OLYMPUS VII"].online, 25)
		-- Soon after: the round goes on with the first level range.
		server.Click()
		eq(server.sent[#server.sent], ('g-"Olympus" %d-%d'):format(unpack(ns.Who.sweep.brackets[1])))
		server.Answer(Players(51, 60), 10)
		server.Run()
		eq(#ns.Recruit.found, 60)
		-- An hour later: the broad search again, and only the players seen now count.
		server.clock = server.clock + 3600
		server.Click()
		eq(server.sent[#server.sent], 'g-"Olympus"')
		server.Answer(Players(101, 110), 10)
		server.Run()
		eq(#ns.Recruit.found, 10, "only the players seen now")
		eq(ns.rdb.seen["OLYMPUS VII"].online, 5); eq(ns.rdb.seen["OLYMPUS VII"].capped, nil)
		eq(ns.Who.StatusLines(), nil)
	end)
end)

test("who: a search that fails to send gives every event back", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		ClassicUIForeverWhoPanel = { driver = ListenerFrame("driver", true) }
		C_FriendList.SendWho = function() error("who throttled") end
		local caught
		local capture = ns.CaptureError
		ns.CaptureError = function(_, err) caught = tostring(err) end
		eq(ns.SafeCall("button RECRUIT_FIND", ns.Who.Search), false)
		ns.CaptureError = capture
		assert(caught and caught:find("who throttled", 1, true), "error captured: " .. tostring(caught))
		eq(Listening(FriendsFrame), true); eq(Listening(ClassicUIForeverWhoPanel.driver), true)
		eq(server.toUi[#server.toUi], false)
		eq(ns.Who.IsPending(), false)
		server.Run()
		eq(table.concat(FriendsFrame.calls, " "), "unregister register", "the timeout changes nothing more")
	end)
end)

test("who: /oly reset while a search waits gives the event back", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		eq(Listening(LFGWhoListFrame), false)
		SlashCmdList.OLYMPUS("reset")
		eq(Listening(LFGWhoListFrame), true); eq(server.toUi[#server.toUi], false)
		eq(ns.Who.IsPending(), false)
	end)
end)

test("who: level ranges follow the levels seen", function()
	local function S(list)
		local out = {}
		for _, b in ipairs(list) do out[#out + 1] = b[1] .. "-" .. b[2] end
		return table.concat(out, " ")
	end
	local young = {}
	for i = 1, 50 do young[i] = 7 + i % 14 end
	eq(S(ns.Who.Brackets(young, 60, 5)), "1-9 10-12 13-14 15-17 18-60", "a young realm: ranges where the players are")
	eq(S(ns.Who.Brackets({}, 60, 5)), "1-12 13-24 25-36 37-48 49-60", "no levels seen: even ranges")
	local top = {}
	for i = 1, 50 do top[i] = 60 end
	eq(S(ns.Who.Brackets(top, 60, 5)), "1-59 60-60", "everyone at the top level: it gets a range of its own")
	eq(S(ns.Who.Brackets({}, 3, 5)), "1-1 2-2 3-3")
	eq(S(ns.Who.Brackets(young, 70, 5)), "1-9 10-12 13-14 15-17 18-70", "up to the client's top level")
end)

test("who: a capped answer (50 of 312) is dug through by level, merging, then a click starts over", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		server.Answer(Players(1, 50), 312)
		server.Run()
		eq(#ns.Recruit.found, 50)
		local brackets = ns.Who.sweep.brackets
		eq(#brackets, 5); eq(brackets[1][1], 1); eq(brackets[5][2], 60)
		local status = ns.Who.StatusLines()
		eq(status[1], "Showing 50 of 312 online.")
		eq(status[2], ("Next search: levels %d-%d (1 of 5)."):format(brackets[1][1], brackets[1][2]))
		-- The Join screen says so under its title.
		local lines = ns.Views.RecruitLines()
		eq(lines[2].text, ns.Views.Grey(status[1])); eq(lines[3].text, ns.Views.Grey(status[2]))
		eq(ns.rdb.seen["OLYMPUS VII"].capped, true, "the census knows more may be online")
		eq(ns.rdb.seen["OLYMPUS VII"].online, 25)
		-- Each click searches the next range and adds to what was found (P41-70, P61-90, ...).
		for k = 1, #brackets do
			eq(server.Click(), true)
			eq(server.sent[#server.sent], ('g-"Olympus" %d-%d'):format(brackets[k][1], brackets[k][2]))
			eq(Listening(LFGWhoListFrame), false, "quiet for the level searches too")
			server.Answer(Players(20 * k + 21, 20 * k + 50), 30)
			server.Run()
			eq(Listening(LFGWhoListFrame), true)
			eq(#ns.Recruit.found, 20 * k + 50, "merged, nobody twice")
			if k == 1 then eq(ns.Who.StatusLines()[1], "70 of 312 found so far.") end
		end
		eq(ns.Who.StatusLines()[1], "150 found, every level searched.")
		eq(#ns.Who.StatusLines(), 1)
		eq(ns.rdb.seen["OLYMPUS VII"].online, 75); eq(ns.rdb.seen["OLYMPUS I"].online, 75)
		eq(ns.rdb.seen["OLYMPUS VII"].capped, nil, "every range fit: exact")
		-- Every range searched once: the misspelled names, then the next click starts over.
		for _, variant in ipairs(ns.Who.VARIANTS) do
			server.Click()
			eq(server.sent[#server.sent], ('g-"%s"'):format(variant))
			server.Answer({})
			server.Run()
		end
		eq(ns.Who.StatusLines()[1], "150 found, every level searched.", "unchanged by them")
		server.Click()
		eq(server.sent[#server.sent], 'g-"Olympus"')
		eq(#ns.Recruit.found, 150, "kept until the new answer comes")
		server.Answer(Players(1, 10), 10)
		server.Run()
		eq(#ns.Recruit.found, 10, "a new round")
		eq(ns.Who.StatusLines(), nil)
	end)
end)

test("who: Forever reports no total past 50, and a crowded level range stays capped", function()
	WithWho(function(server)
		ns.Who.Search()
		server.Answer(Players(1, 50), 50) -- the "50 People Found" of the Forever screenshot
		server.Run()
		eq(ns.Who.StatusLines()[1], "Showing 50: the game lists no more per search.")
		for k = 1, #ns.Who.sweep.brackets do
			server.Click()
			-- The first range is as full as the broad search.
			server.Answer(k == 1 and Players(101, 150) or {}, k == 1 and 50 or 0)
			server.Run()
			if k == 1 then eq(ns.Who.StatusLines()[1], "100 found so far.") end
		end
		eq(ns.Who.StatusLines()[1], "100 found: some levels still had over 50.")
		eq(ns.rdb.seen["OLYMPUS VII"].capped, true, "a range was capped: still a floor")
	end)
end)

test("census: /who sightings for every Olympus guild we can see, never a report", function()
	WithWho(function(server)
		ns.rdb.guilds = SampleGuilds()
		ns.UI = { StatusLine = function() return "status" end }
		local before = ns.Data.Summary()
		ns.Who.Search()
		server.Answer({
			{ "Aa", "OLYMPUS VII", 12 }, { "Bb", "OLYMPUS VII", 14 }, { "Far-Other", "OLYMPUS VII", 14 },
			{ "Cc-Realm", "OLYMPUS XXL", 9 }, { "Dd", "Olympus", 20 }, { "Ee", "House of Guedes", 20 },
			{ "Ff-Other", "OLYMPUS LXIX", 3 },
		})
		server.Run()
		local seen = ns.rdb.seen
		eq(seen["OLYMPUS VII"].online, 3, "players from the other realm (PvP 2) count too")
		eq(seen["OLYMPUS XXL"].online, 1, "Name-OurRealm is ours")
		eq(seen["OLYMPUS LXIX"].online, 1, "a guild only seen on the other realm is listed")
		eq(seen["House of Guedes"], nil, "not an Olympus guild")
		eq(seen["OLYMPUS VII"].capped, nil, "everyone fit in one answer")
		eq(seen["Olympus"].online, 1, "a reported guild can be seen too...")
		eq(ns.rdb.guilds["Olympus"].total, 990, "...and its report is untouched")
		eq(ns.rdb.guilds["OLYMPUS VII"], nil, "a sighting is never a report")
		eq(ns.Data.KnownRank("Aa-Realm", "OLYMPUS VII"), nil, "and grants no rank")
		local s = ns.Data.Summary()
		eq(s.total, before.total); eq(s.online, before.online); eq(s.fresh, before.fresh)
		eq(#s.guilds, #before.guilds, "not among the reported guilds")
		eq(#s.zoneList, #before.zoneList, "nothing on the map")
		eq(#s.seen, 3, "seen and not reported"); eq(s.seen[1].name, "OLYMPUS VII")
		eq(s.seen[2].name, "OLYMPUS LXIX"); eq(s.seen[3].name, "OLYMPUS XXL")
		local realm = ns.Views.RealmLines()
		eq(realm[1].text:find("Asmond Layer", 1, true) ~= nil, true, "the King's layer line comes first")
		eq(realm[2].text:find("Asmongold", 1, true) ~= nil, true, "the King is a reported guild's")
		for _, l in ipairs(realm) do
			assert(not (l.text or ""):find("OLYMPUS", 1, true), "in the Realm tree: " .. tostring(l.text))
		end
		-- A report arriving later takes the guild's row; the sighting stays out of sight.
		eq(ns.Data.Receive({ guild = "OLYMPUS XXL", total = 40, online = 9, zones = {} }, "Reporter-Realm"), true)
		s = ns.Data.Summary()
		eq(#s.seen, 2); eq(s.total, before.total + 40)
		-- Forgotten like reports, and by /oly reset.
		seen["OLYMPUS VII"].t = os.time() - ns.Data.KEEP - 1
		seen["OLYMPUS LXIX"].t = os.time() - ns.Data.KEEP - 1
		eq(#ns.Data.Summary().seen, 0, "older than a day")
		SlashCmdList.OLYMPUS("reset")
		eq(next(ns.rdb.seen), nil, "/oly reset forgets sightings")
	end)
end)

test("census: sightings older than a day are forgotten at login", function()
	local savedR, savedCapture = ns.rdb, ns.CaptureError
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.rdb = { guilds = {}, seen = { ["OLYMPUS VII"] = { online = 5, t = os.time() - ns.Data.KEEP - 1 },
		["OLYMPUS XXL"] = { online = 3, t = os.time() - 60 }, ["OLYMPUS X"] = "broken" } }
	CoreFire("INIT")
	local seen = ns.rdb.seen
	ns.rdb, ns.CaptureError = savedR, savedCapture
	eq(captured, nil, "error caught")
	eq(seen["OLYMPUS VII"], nil, "older than a day"); eq(seen["OLYMPUS X"], nil, "not a sighting")
	eq(seen["OLYMPUS XXL"].online, 3, "a recent one is kept")
end)

test("census: guilds only seen with /who are grey rows after the reported ones", function()
	WithWho(function()
		local L, Grey = ns.L, ns.Views.Grey
		ns.rdb.guilds = SampleGuilds()
		ns.rdb.seen = { ["OLYMPUS VII"] = { online = 12, capped = true, t = os.time() },
			["OLYMPUS XXL"] = { online = 30, t = os.time() }, ["Olympus"] = { online = 3, t = os.time() } }
		ns.UI = { StatusLine = function() return "status" end }
		ns.Views.sort = { key = "members", desc = false } -- sorting moves reported guilds only
		local lines = ns.Views.Build("census")
		assert(lines[1].onClick and not lines[1].cols, "the King is online: his layer line comes first")
		table.remove(lines, 1)
		eq(lines[1].cols[1], "Olympus II"); eq(lines[2].cols[1], "Olympus")
		eq(lines[3].cols[1], Grey("OLYMPUS XXL"), "most online first")
		eq(lines[3].cols[3], Grey("30")); eq(lines[3].dim, nil)
		eq(lines[4].cols[1], Grey("OLYMPUS VII")); eq(lines[4].cols[2], Grey("?"))
		eq(lines[4].cols[3], Grey("12+"), "capped: at least")
		eq(lines[4].cols[4], Grey(L.NO_ADDON))
		eq(lines[5].text, Grey(L.SEEN_HINT)); eq(#lines, 5)
		local tip = {}
		local tt = { AddLine = function(_, text) tip[#tip + 1] = text end,
			AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end }
		lines[4].tooltip(tt)
		local text = table.concat(tip, "\n")
		assert(text:find(L.SEEN_TIP, 1, true) and text:find(L.SEEN_CAPPED_TIP, 1, true) and text:find("12+", 1, true), text)
		-- Nothing seen: no grey rows and no hint.
		ns.rdb.seen = {}
		eq(#ns.Views.Build("census"), 3, "the King's layer line and 2 guilds")
		ns.Views.sort = { key = "members", desc = true }
	end)
end)

test("census Refresh: the roster, and one /who per click for the grey guilds", function()
	WithWho(function(server)
		WithUI(function()
			local scans = 0
			C_GuildInfo = { GuildRoster = function() scans = scans + 1 end }
			local UI = LoadUI()
			UI.SelectTab("census")
			local refresh = OlympusFrame.buttons[2]
			eq(refresh:GetText(), ns.L.REFRESH)
			refresh:Click()
			eq(scans, 1); eq(table.concat(server.sent, "|"), 'g-"Olympus"')
			refresh:Click()
			eq(scans, 2, "the roster every click"); eq(#server.sent, 1, "/who at most every 10 seconds")
			server.Answer({ { "Aa", "OLYMPUS VII", 12 } })
			UI.Refresh()
			local row = OlympusFrame.views.census.rows[4] -- after the King's layer line and 2 guilds
			eq(row.cols[1]:GetText(), ns.Views.Grey("OLYMPUS VII"), "the grey row is drawn")
			-- The person panel's Who goes through Who.lua: not right after our search.
			UI.ShowPerson({ name = "Aa-Realm", guild = "OLYMPUS VII" })
			OlympusPersonFrame.who:Click()
			eq(#server.sent, 1, "the person panel's Who waits for ours")
			server.clock = server.clock + ns.Who.COOLDOWN
			OlympusPersonFrame.who:Click()
			eq(server.sent[#server.sent], 'n-"Aa"', "our realm left out, as the server wants it")
			C_GuildInfo = nil
		end)
	end)
end)

---------------------------------------------------------------------------
-- Channels (Channels.lua): [Olympus] / [Captains] / [Lords] over the hidden channel
---------------------------------------------------------------------------

CHAT_LINES = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) CHAT_LINES[#CHAT_LINES + 1] = t end }
UnitClass = function() return "Paladin", "PALADIN" end
local Chan = ns.Channels
local ITEM = "|cff0070dd|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"
local ITEM_Q = "|cnIQ4:|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"

-- Runs fn(printed) with guild rank R in Olympus II (or in `guild`); ns.Print goes to `printed`.
local function AsRank(R, fn, guild)
	local savedInfo, savedPrint = GetGuildInfo, ns.Print
	local printed = {}
	GetGuildInfo = function() return guild or MY_GUILD, "rankname", R end
	ns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
	local ok, err = pcall(fn, printed)
	GetGuildInfo, ns.Print = savedInfo, savedPrint
	if not ok then error(err, 0) end
end

-- Runs fn(sent) with the chat lane stubbed: SendChat records the message and reports it sent.
local function WithLane(fn, ready)
	local C = ns.Comm
	local savedReady, savedSend = C.ChannelReady, C.SendChat
	local sent = {}
	C.ChannelReady = function() return ready ~= false end
	C.SendChat = function(msg, done) sent[#sent + 1] = msg; done(true); return true end
	local ok, err = pcall(fn, sent)
	C.ChannelReady, C.SendChat = savedReady, savedSend
	if not ok then error(err, 0) end
end

local function Msg(tier, guild, id, text)
	return Codec.EncodeChat(tier, guild, id, "PA", text or "hi")
end

test("chat message round trip: separators, escapes and unicode", function()
	local text = "ataque em ~Tarren:Mill, já! a=b " .. ITEM .. " e " .. ITEM_Q
	eq(Codec.SanitizeChat(text), text, "nothing to neutralise")
	local d = Codec.DecodeChat(Codec.EncodeChat("C", "Olympus II", 42, "PA", text))
	eq(d.tier, "C"); eq(d.guild, "Olympus II"); eq(d.id, 42); eq(d.class, "PA"); eq(d.text, text)
	eq(Codec.DecodeChat(Codec.EncodeChat("A", "Olympus", 7, "", "oi")).class, nil, "no class")
	eq(Codec.DecodeChat(Codec.EncodeChat("A", "Olympus", 12345, "", "oi")).id, 2345, "id wraps at 10000")
	eq(Codec.DecodeChat("M1~X~Olympus~1~~hi"), nil, "unknown tier")
	eq(Codec.DecodeChat("M1~A~Oly|mpus~1~~hi"), nil, "| in the guild")
	eq(Codec.DecodeChat("M1~A~Olympus~12345~~hi"), nil, "5 digit id")
	eq(Codec.DecodeChat("M1~A~Olympus~1~~   "), nil, "whitespace only")
	eq(Codec.DecodeChat("M1~A~Olympus~1~~" .. ("x"):rep(240)), nil, "over 255 bytes")
	eq(Codec.DecodeChat("M1~A~" .. ("Olympus"):rep(4) .. "~1~~hi"), nil, "guild over 24 characters")
	-- WoW counts characters: 24 of them with an accent are 25 bytes.
	local accents = "Olympus Irmãos de Sangue"
	eq(#accents, 25)
	eq(Codec.DecodeChat(Codec.EncodeChat("A", accents, 1, "", "oi")).guild, accents, "chat")
	eq(Codec.DecodeReport(Codec.EncodeReport({ guild = accents, total = 1, online = 1 })).guild, accents, "report")
	eq(Codec.DecodeChat("M1~A~" .. ("\128"):rep(80) .. "~1~~hi"), nil, "bytes are limited too")
end)

test("chat sanitizer keeps item and spell links and neutralises every other escape", function()
	local S = Codec.SanitizeChat
	local spell = "|cff71d5ff|Hspell:8690|h[Hearthstone]|h|r"
	eq(S("hi " .. ITEM .. " ok"), "hi " .. ITEM .. " ok")
	eq(S(ITEM_Q), ITEM_Q); eq(S(spell), spell)
	eq(S("|TInterface\\Icons\\x:99|t"), "||TInterface\\Icons\\x:99||t", "texture")
	eq(S("|cffff0000fake|r"), "||cffff0000fake||r", "bare colour")
	eq(S("|HurlIndex:24|h[x]|h"), "||HurlIndex:24||h[x]||h", "other link types")
	eq(S("|A:atlas:16:16|a"), "||A:atlas:16:16||a", "atlas")
	eq(S("|Kq1|k"), "||Kq1||k", "protected name")
	eq(S("a|nb"), "a||nb", "raw |n")
	eq(S("a\nb\0c"), "abc", "control bytes")
	-- A newline inside a link's name would fake a second chat line: not a link we keep.
	eq(S("ok |Hitem:1|h[x\n[Olympus]|h [Zeus] <Olympus>: gold"), "ok ||Hitem:1||h[x[Olympus]||h [Zeus] <Olympus>: gold", "newline in a link")
	eq(S("|Hitem:1|h[a\0b]|h"), "||Hitem:1||h[ab]||h", "NUL in a link")
	eq(S("a||b"), "a||b", "escaped pipe kept")
	for _, x in ipairs({ "hi " .. ITEM, "|T x |t", "a||b|", "ção ~ : , = |", ITEM_Q .. "|" }) do
		local once = S(x)
		eq(S(once), once, "idempotent: " .. x)
	end
end)

test("long chat splits at safe points and every part fits one message", function()
	local guild = "Olympus Poseidon Real"
	eq(#guild, 21)
	local text = Codec.SanitizeChat(("ação "):rep(50) .. ITEM .. (" é"):rep(40))
	eq(#text, 530)
	local parts, cut = Codec.SplitChat(text, Codec.ChatBudget(guild, "PA"), Codec.CHAT_PARTS)
	eq(#parts, 3); eq(cut, false)
	local whole = false
	for _, p in ipairs(parts) do
		local b = p:byte(1)
		assert(not (b >= 128 and b < 192), "part starts inside a character")
		local msg = Codec.EncodeChat("A", guild, 9999, "PA", p)
		assert(msg and #msg <= 250, "message too long")
		eq(Codec.DecodeChat(msg).text, p)
		if p:find(ITEM, 1, true) then whole = true end
	end
	assert(whole, "the link stayed whole")
	eq((table.concat(parts, " "):gsub("%s+", " ")), (text:gsub("%s+", " ")), "nothing lost")
	local q = Codec.SplitChat(("x"):rep(90) .. ITEM .. ("y"):rep(20), 120, 3)
	eq(#q, 2); eq(q[1], ("x"):rep(90)); eq(q[2], ITEM .. ("y"):rep(20))
	for _, p in ipairs(Codec.SplitChat(("ç"):rep(150), 101, 3)) do eq(#p % 2, 0, "cut inside a character") end
	local long, lost = Codec.SplitChat(("x"):rep(1000), 200, 3)
	eq(#long, 3); eq(lost, true)
	-- The space in a link's name is not a place to cut.
	local named = "|cff0070dd|Hitem:19019::::::::60:::::::::|h[Thunderfury Blessed Blade]|h|r"
	local w = Codec.SplitChat(("y"):rep(40) .. named .. ("y"):rep(100), 120, 3)
	assert(w[1]:find(named, 1, true), "link cut at its space: " .. w[1])
end)

test("channel levels follow the realm hierarchy", function()
	eq(Chan.LevelOf("Olympus", 0), 3); eq(Chan.LevelOf("Olympus", 1), 3); eq(Chan.LevelOf("Olympus", 2), 1)
	eq(Chan.LevelOf("Olympus II", 0), 3); eq(Chan.LevelOf("Olympus II", 1), 2); eq(Chan.LevelOf("Olympus II", 3), 1)
	eq(Chan.LevelOf("Horde Pals", 0), 0)
	local function uses()
		local s = ""
		for _, t in ipairs(Chan.ORDER) do if Chan.CanUse(t) then s = s .. t end end
		return s
	end
	AsRank(0, function() eq(uses(), "ACL", "guild master") end)
	AsRank(1, function() eq(uses(), "AC", "officer") end)
	AsRank(3, function() eq(uses(), "A", "member") end)
	AsRank(0, function() eq(uses(), "", "outside Olympus") end, "House of Guedes")
end)

test("sending is gated with a clear answer", function()
	CHAT_LINES = {}
	WithLane(function(sent)
		AsRank(0, function(printed)
			local ok, why = Chan.Send("A", "hi", 100)
			eq(ok, false); eq(why, "member"); eq(printed[1], ns.L.MEMBERS_ONLY)
		end, "House of Guedes")
		AsRank(3, function()
			eq(select(2, Chan.Send("C", "hi", 100)), "rank")
			eq(select(2, Chan.Send("L", "hi", 100)), "rank")
		end)
		AsRank(1, function(printed)
			eq(select(2, Chan.Send("L", "hi", 100)), "rank")
			eq(printed[1], ns.L.CHAN_ONLY_LORDS:format("Lords"))
			eq(select(2, Chan.Send("C", " \n ", 100)), "empty")
			eq(printed[2], ns.L.CHAN_USAGE:format("/olc", "Captains"))
			C_ChatInfo = { InChatMessagingLockdown = function() return true end }
			eq(select(2, Chan.Send("C", "hi", 100)), "lockdown")
			C_ChatInfo = nil
			local savedRoom = ns.Comm.ChatRoom
			ns.Comm.ChatRoom = function() return 0 end
			eq(select(2, Chan.Send("C", "hi", 100)), "busy")
			ns.Comm.ChatRoom = savedRoom
		end)
		eq(#sent, 0, "nothing sent")
	end)
	WithLane(function(sent)
		AsRank(1, function() eq(select(2, Chan.Send("C", "hi", 100)), "ready") end)
		eq(#sent, 0)
	end, false)
	WithLane(function(sent)
		AsRank(1, function(printed)
			local ok, why = Chan.Send("C", "reunir em " .. ITEM, 100)
			eq(ok, true); eq(why, "ok")
			eq(#printed, 0, "no notice after the line: the warning comes before the first one (0.9.1)")
		end)
		eq(#sent, 1)
		eq(sent[1]:sub(1, 16), "M1~C~Olympus II~")
		assert(sent[1]:find("~PA~reunir em " .. ITEM, 1, true), sent[1])
		eq(#CHAT_LINES, 1, "local echo")
		assert(CHAT_LINES[1]:find("[Captains]", 1, true) and CHAT_LINES[1]:find(ITEM, 1, true), CHAT_LINES[1])
	end)
end)

test("sender ranks are verified on receipt, never taken from the message", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {
		["Olympus"] = Vouched({ guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() }, "W1-Realm", "W2-Realm"),
		["Olympus Bad"] = { guild = "Olympus Bad", leader = "X", conflict = true, total = 1, online = 1, zones = {}, t = os.time() },
	}
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 5, online = 1, zones = {} }, "Liar2-Realm"), true)
	CHAT_LINES = {}
	AsRank(0, function()
		local n = 0
		local function R(sender, tier, guild, dist)
			n = n + 1
			return select(2, Chan.Receive(dist or "CHANNEL", sender, Msg(tier, guild, n), 1000 + n))
		end
		eq(R("Member2", "C", MY_GUILD), "ok", "our officer on [Captains]")
		eq(R("Member2", "L", MY_GUILD), "rank", "our officer is not a Lord")
		eq(R("Member1", "L", MY_GUILD), "ok", "our guild master")
		eq(R("Member500", "A", MY_GUILD), "ok", "our member on [Olympus]")
		eq(R("Member500", "C", MY_GUILD), "rank", "our member on [Captains]")
		eq(R("Stranger-Realm", "A", MY_GUILD), "forged", "not in our roster")
		eq(R("Member3", "A", "Olympus"), "forged", "a guildmate speaking for another guild")
		eq(R("Asmongold", "L", "Olympus"), "ok", "the King, from the report")
		eq(R("Capt", "L", "Olympus"), "ok", "officer of <Olympus>, from the report")
		eq(R("Random", "A", "Olympus"), "ok", "unverified members can use [Olympus]")
		eq(R("Random", "C", "Olympus"), "unverified")
		eq(R("X", "C", "Olympus Bad"), "unverified", "conflicting report")
		eq(R("Hordie", "A", "Horde Pals"), "bad", "not an Olympus guild")
		eq(R("Liar2", "A", "Olympus Fake"), "forged", "already reported another guild")
		eq(R("Member2", "A", MY_GUILD, "GUILD"), "dist")
	end)
	eq(#CHAT_LINES, 6)
	assert(CHAT_LINES[4]:find("[Lords]", 1, true) and CHAT_LINES[4]:find("<Olympus>", 1, true), CHAT_LINES[4])
	ns.rdb.guilds = {}
end)

test("players below a tier never see it", function()
	ns.rdb.chat = nil
	CHAT_LINES = {}
	local m = Msg("L", MY_GUILD, 777, "only for lords")
	AsRank(3, function()
		local shown, why = Chan.Receive("CHANNEL", "Member1", m, 2000)
		eq(shown, false); eq(why, "tier")
		eq(#Chan.History("L"), 0)
	end)
	eq(#CHAT_LINES, 0, "no line")
	eq(ns.rdb.chat, nil, "nothing stored")
	AsRank(0, function()
		eq((Chan.Receive("CHANNEL", "Member1", m, 2001)), true)
		eq(#Chan.History("L"), 1)
	end)
	eq(#CHAT_LINES, 1)
	-- A member doesn't read [Captains], and a Captain outside <Olympus> doesn't read [Lords].
	AsRank(3, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 778, "only for captains"), 2002)), "tier")
	end)
	AsRank(1, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member1", Msg("L", MY_GUILD, 779, "lords again"), 2003)), "tier")
	end)
	eq(ns.rdb.chat.C, nil, "nothing stored")
	eq(#ns.rdb.chat.L, 1)
	-- Before our roster is read, even a real officer claiming our guild gets [Olympus] only.
	local byName = ns.Roster.byName
	ns.Roster.byName = nil
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member3", Msg("C", MY_GUILD, 780), 2004)), "unverified")
		eq((Chan.Receive("CHANNEL", "Member3", Msg("A", MY_GUILD, 781), 2005)), true)
	end)
	ns.Roster.byName = byName
	C_FriendList = { IsIgnored = function() return true end }
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member4", Msg("A", MY_GUILD, 782), 2006)), "ignored")
	end)
	C_FriendList = nil
	eq(#CHAT_LINES, 2)
end)

test("duplicate ids are shown once", function()
	AsRank(1, function()
		local m = Msg("A", MY_GUILD, 4242)
		eq((Chan.Receive("CHANNEL", "Member7", m, 3000)), true)
		eq(select(2, Chan.Receive("CHANNEL", "Member7", m, 3001)), "dup")
		eq((Chan.Receive("CHANNEL", "Member8", m, 3002)), true, "same id from another sender")
		eq((Chan.Receive("CHANNEL", "Member7", Msg("A", MY_GUILD, 4242, "after a /reload"), 3003)), true, "same id, new text")
		Chan.Prune(3000 + 121)
		eq((Chan.Receive("CHANNEL", "Member7", m, 3000 + 121)), true, "forgotten after the window")
	end)
end)

test("rate limits: sender cooldown and receiver burst guard", function()
	WithLane(function()
		AsRank(3, function(printed)
			eq((Chan.Send("A", "one", 4000)), true)
			local ok, why = Chan.Send("A", "two", 4001)
			eq(ok, false); eq(why, "fast"); eq(printed[#printed], ns.L.CHAN_TOO_FAST)
			eq((Chan.Send("A", "three", 4001.5)), true)
		end)
	end)
	AsRank(3, function()
		for i = 1, 6 do eq((Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 100 + i), 5000)), true, "burst " .. i) end
		eq(select(2, Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 107), 5000)), "rate")
		eq((Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 108), 5000 + 1.2)), true, "one more after 1.2 s")
		for i = 1, 60 do
			eq((Chan.Receive("CHANNEL", "Member" .. (200 + i), Msg("A", MY_GUILD, 1), 6000 + i * 0.5)), true, "sender " .. i)
		end
		eq(select(2, Chan.Receive("CHANNEL", "Member261", Msg("A", MY_GUILD, 1), 6030.5)), "flood")
	end)
end)

test("muted tiers stay out of chat but keep history", function()
	ns.db.chatMute, ns.rdb.chat = nil, nil
	AsRank(1, function(printed)
		Chan.ToggleMute("captains")
		eq(ns.db.chatMute.C, true)
		eq(printed[1], ns.L.CHAN_MUTED:format("Captains", "captains"))
		CHAT_LINES = {}
		local shown, why = Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 5150), 7000)
		eq(shown, false); eq(why, "muted")
		eq(#CHAT_LINES, 0, "no line"); eq(#Chan.History("C"), 1, "kept in history")
		eq(Chan.Stats().muted[1], "C")
		Chan.ToggleMute("capitães")
		eq(ns.db.chatMute.C, nil)
		Chan.ToggleMute("nonsense")
		eq(printed[#printed], ns.L.CHAN_MUTE_USAGE)
		-- "all" would read as every channel: [Olympus] is muted with its own name.
		Chan.ToggleMute("olympus")
		eq(printed[#printed], ns.L.CHAN_MUTED:format("Olympus", "olympus"))
		Chan.ToggleMute("all")
		eq(ns.db.chatMute.A, nil, "'all' still works")
		Chan.ToggleMute("captains")
		WithLane(function() eq((Chan.Send("C", "back", 7001)), true) end)
		eq(ns.db.chatMute.C, nil, "sending unmutes")
		eq(#CHAT_LINES, 1, "own line shown")
	end)
end)

test("chat history is per tier and capped", function()
	ns.rdb.chat = nil
	AsRank(0, function()
		for i = 1, 150 do
			Chan.Receive("CHANNEL", "Member" .. (300 + i), Msg("A", MY_GUILD, i, "line " .. i), 8000 + i * 1.1)
		end
		local h = Chan.History("A")
		eq(#h, 100); eq(h[1].text, "line 51", "oldest gone"); eq(h[100].text, "line 150")
		eq(h[100].sender, "Member450-Realm"); eq(h[100].guild, MY_GUILD); eq(h[100].class, "PA")
		eq((Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 1, "captains only"), 8200)), true)
		eq(#Chan.History("C"), 1); eq(#Chan.History("A"), 100, "separate lists")
		eq(ns.rdb.chat.A, h, "stored per realm")
	end)
	AsRank(3, function()
		eq(#Chan.History("C"), 0)
		eq(next(Chan.History("L")), nil)
	end)
end)

test("a report never vouches for its own sender", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~50~5~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local n = 0
	local function Line(sender, tier, guild)
		n = n + 1
		return select(2, Chan.Receive("CHANNEL", sender, Msg(tier, guild, n), 9000 + n))
	end
	CHAT_LINES = {}
	AsRank(0, function()
		-- A made-up guild naming its sender as leader: one /run, no guild needed.
		eq(Report("Olympus Lords", "Evil", "", "Evil-Realm"), true)
		eq(D.KnownRank("Evil-Realm", "Olympus Lords"), nil, "its own report")
		eq(Line("Evil", "L", "Olympus Lords"), "unverified")
		-- A member sends his guild's report again, same leader and size, and adds himself.
		eq(Report("Olympus Zeus", "Zeus", "Capt2:1:0", "Scribe-Realm"), true)
		eq(D.KnownRank("Capt2-Realm", "Olympus Zeus"), 1, "named by someone else")
		eq(Report("Olympus Zeus", "Zeus", "Capt2:1:0,Grunt:1:0", "Grunt-Realm"), true)
		eq(ns.rdb.guilds["Olympus Zeus"].conflict, true, "an added officer is a conflict")
		eq(Line("Grunt", "C", "Olympus Zeus"), "unverified")
		-- The same on <Olympus>, whose officers are Lords.
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Herald-Realm"), true)
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Peon:1:0", "Peon-Realm"), true)
		eq(Line("Peon", "L", "Olympus"), "unverified")
		-- An elected reporter who leads the guild: proven by the report someone else sent before.
		eq(Report("Olympus Ares", "Ares", "", "Squire-Realm"), true)
		eq(Report("Olympus Ares", "Ares", "", "Ares-Realm"), true)
		eq(D.KnownRank("Ares-Realm", "Olympus Ares"), 0, "named by the report before")
		eq(Report("Olympus Ares", "Ares", "", "Ares-Realm"), true)
		eq(D.KnownRank("Ares-Realm", "Olympus Ares"), 0, "kept while the reporter stays")
		eq(Line("Ares", "L", "Olympus Ares"), "ok")
	end)
	eq(#CHAT_LINES, 1)
	ns.rdb.guilds = {}
end)

test("ranks come from the picture most senders agree on; forgers can't move it", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	local ok, err = pcall(function()
		-- <Olympus> as its reporter and runner-up send it.
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Crier-Realm"), true)
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Clerk-Realm"), true)
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "two senders name the officer")
		eq(D.KnownRank("Asmongold Asmongler-Realm", "Olympus"), 0, "and the King")
		-- One outsider copies the report (fine), then adds an accomplice: one vote against two.
		-- The row everyone sees stays the majority's (the forged report is a vote, not the row).
		clock = clock + 60
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Aaa-Realm"), true)
		clock = clock + 1
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Bbb:1:0", "Aaa-Realm"), false, "against the majority: not the row")
		eq(D.KnownRank("Bbb-Realm", "Olympus"), nil, "the copy-then-add trick gives nothing")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "and costs the real officers nothing")
		eq(ns.rdb.guilds.Olympus.outvoted, true, "the minority report is noted"); eq(ns.rdb.guilds.Olympus.conflict, nil)
		eq(#ns.rdb.guilds.Olympus.officers, 1, "the row shows the majority's picture")
		-- Its own report never makes a sender anything.
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Aaa:1:0", "Aaa-Realm"), false)
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil)
		-- Two forgers against two reporters: contested, nobody's rank counts until it is settled.
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Aaa:1:0", "Ccc-Realm"), true, "a tie: no majority to hold the row")
		eq(ns.rdb.guilds.Olympus.conflict, true, "split senders show as a conflict")
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil, "a tie is no majority")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "contested: what both pictures agree on still counts")
		-- Their votes expire when they stop; the real reporters' stay fresh.
		clock = clock + 20 * 60
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Crier-Realm"), true)
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Clerk-Realm"), true)
		clock = clock + 11 * 60
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0", "Crier-Realm"), true)
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "the forgers' votes are over 30 minutes old")
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil)
		-- A real promotion: split while only one of the two has reported it, then agreed.
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Earl:1:0", "Clerk-Realm"), true)
		eq(D.KnownRank("Earl-Realm", "Olympus"), nil, "one sender so far")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "the others keep their ranks meanwhile")
		eq(D.KnownRank("Asmongold Asmongler-Realm", "Olympus"), 0)
		eq(Report("Olympus", "Asmongold Asmongler", "Duke:1:0,Earl:1:0", "Crier-Realm"), true)
		eq(D.KnownRank("Earl-Realm", "Olympus"), 1, "both reporters name him")
		-- Another guild: an outsider swapping the leader for an accomplice gets no Lord.
		eq(Report("Olympus Zeus", "Zeus", "", "Zclerk-Realm"), true)
		eq(Report("Olympus Zeus", "Zeus", "", "Zcrier-Realm"), true)
		eq(Report("Olympus Zeus", "Bbb2", "", "Aaa2-Realm"), false, "leader swap: one vote against two, not the row")
		eq(ns.rdb.guilds["Olympus Zeus"].leader, "Zeus", "the row keeps the real Lord")
		eq(D.KnownRank("Bbb2-Realm", "Olympus Zeus"), nil, "leader swap: one vote against two")
		eq(D.KnownRank("Zeus-Realm", "Olympus Zeus"), 0)
	end)
	ns.Now = savedNow
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("cut officer lists, channel changes and the first minutes after login", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Officers(extra)
		local t = {}
		for i = 1, 30 do t[#t + 1] = "Off" .. i .. ":1:0" end
		if extra then t[#t] = extra .. ":1:0" end
		return table.concat(t, ",")
	end
	local function Report(guild, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~Boss~1~1~~" .. LEVELS .. officers), sender)
	end
	-- 30 officers: the list is cut, the picture is the leader only.
	eq(Report("Olympus Ares", Officers(), "Rep-Realm"), true)
	eq(Report("Olympus Ares", Officers(), "Run-Realm"), true)
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), 1, "named by both senders")
	eq(Report("Olympus Ares", Officers("Mallory"), "Pad-Realm"), true)
	eq(D.KnownRank("Mallory-Realm", "Olympus Ares"), nil, "a padded list gives nobody a rank")
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), 1, "the real officers keep theirs")
	-- Moving to another channel forgets every vote.
	D.ForgetVotes()
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), nil)
	eq(ns.rdb.guilds["Olympus Ares"].total, 900, "the census numbers stay")
	-- No Crown in the first minutes after login.
	local savedLogin = ns.Comm.loginAt
	eq(Report("Olympus Zeus2", "", "Zr-Realm"), true)
	eq(Report("Olympus Zeus2", "", "Zs-Realm"), true)
	ns.Comm.loginAt = ns.Now() - 30
	eq(D.KnownRank("Boss-Realm", "Olympus Zeus2"), nil, "30 s after login: not yet")
	ns.Comm.loginAt = ns.Now() - D.CROWN_AFTER - 1
	eq(D.KnownRank("Boss-Realm", "Olympus Zeus2"), 0, "after a reporting cycle")
	ns.Comm.loginAt = savedLogin
	ns.rdb.guilds = {}
end)

test("reporter and runner-up on two realms of the group picture the guild the same way", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	-- Boss plays on our realm. Our reporter names him bare; the runner-up plays on PvP 2, where
	-- Boss carries his realm, and reaches us with its own.
	eq(D.Receive(Codec.DecodeReport("R2~Olympus Span2~50~5~Boss~1~1~~" .. LEVELS .. "Capt:1:0"), "Here"), true)
	eq(D.Receive(Codec.DecodeReport("R2~Olympus Span2~50~5~Boss-Realm~1~1~~" .. LEVELS .. "Capt-Realm:1:0"), "There-Other"), true)
	eq(ns.rdb.guilds["Olympus Span2"].conflict, nil, "the same people, not a conflict")
	eq(D.KnownRank("Boss-Realm", "Olympus Span2"), 0, "a Lord on two senders' word")
	eq(D.KnownRank("Capt", "Olympus Span2"), 1)
	ns.rdb.guilds = {}
end)

test("ranks of other guilds: never your own word, the Crown on two, and only while recent", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~40~9~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	local ok, err = pcall(function()
		-- A guild master who is his guild's only reporter: his own report proves nothing.
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Hermes-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), nil, "own report")
		eq(D.KnownRank("Aide-Realm", "Olympus Hermes"), 1, "his officer, named by someone else")
		-- The runner-up reports too (Comm): now two senders, and one of them names Hermes.
		clock = clock + 30
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Runner-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), 0, "a guild master on two senders' word")
		-- One sender only never makes anyone the Crown.
		eq(Report("Olympus Iris", "Iris", "", "Lone-Realm"), true)
		eq(D.KnownRank("Iris-Realm", "Olympus Iris"), nil, "the Crown needs two senders")
		-- Vouches expire: 40 minutes later only a fresh report counts.
		clock = clock + 40 * 60
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Hermes-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), nil, "the runner-up's word is 40 minutes old")
		eq(D.KnownRank("Aide-Realm", "Olympus Hermes"), 1, "Hermes still vouches for his officer")
	end)
	ns.Now = savedNow
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("a player who changed guilds can speak for the new one after a quiet while", function()
	local D = ns.Data
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), true)
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), false, "not right away")
	clock = clock + D.CLAIM_TTL + 1
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), true, "after CLAIM_TTL quiet")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), false, "and now bound to the new one")
	ns.Now = savedNow
end)

test("guild names ignore case, so another spelling can't pass for a guild", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local function Report(guild, officers, sender)
		return ns.Data.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~Asmongold Asmongler~1~9~~~0,0,0,0,0,0,0~~" .. officers), sender)
	end
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Mimic", Msg("A", "olympus ii", 1), 9500)), "forged", "our guild, other capitals")
		eq(select(2, Chan.Receive("CHANNEL", "Member5", Msg("A", "olympus ii", 3), 9500)), "forged", "even from a guildmate")
		eq(Report("OLYMPUS II", "", "Mimic2-Realm"), false, "no report about our guild in any spelling")
		eq(Report("Olympus", "Duke:1:0", "Herald2-Realm"), true)
		eq(Report("OLYMPUS", "Evil2:1:0", "Scribe2-Realm"), true)
		eq(ns.rdb.guilds.OLYMPUS, nil, "one guild whatever the case: the second spelling is a vote on the first")
		eq(ns.rdb.guilds.Olympus.conflict, true, "one against one: split"); eq(ns.rdb.guilds.Olympus.vouch["Scribe2-Realm"] ~= nil, true)
		eq(select(2, Chan.Receive("CHANNEL", "Evil2", Msg("L", "OLYMPUS", 2), 9501)), "unverified")
		-- The same trick against the King's guild with two real senders: nothing moves.
		ns.rdb.guilds = {}
		eq(Report("Olympus", "Duke:1:0", "Herald2-Realm"), true)
		eq(Report("Olympus", "Duke:1:0", "Herald3-Realm"), true)
		eq(Report("OLYMPUS", "", "Forger2-Realm"), false, "outvoted")
		eq(ns.rdb.guilds.OLYMPUS, nil); eq(ns.rdb.guilds.Olympus.conflict, nil)
		eq(ns.Data.KnownRank("Asmongold Asmongler-Realm", "Olympus"), 0, "the King keeps his crown"); eq(ns.Data.KnownRank("Asmongold Asmongler-Realm", "OLYMPUS"), 0, "in any spelling")
	end)
	ns.rdb.guilds = {}
end)

test("two spammers can't silence the other channels, nor everyone else", function()
	ns.db.chatMute = nil
	AsRank(0, function()
		-- Two unmodified clients at full speed in [Olympus] for most of a minute.
		local t
		for i = 1, 50 do
			t = 20000 + i * 1.2
			Chan.Receive("CHANNEL", "Member600", Msg("A", MY_GUILD, i, "spam " .. i), t)
			Chan.Receive("CHANNEL", "Member601", Msg("A", MY_GUILD, i, "spam " .. i), t + 0.1)
		end
		eq((Chan.Receive("CHANNEL", "Member1", Msg("L", MY_GUILD, 1, "lords"), t + 0.2)), true, "[Lords]")
		eq((Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 1, "captains"), t + 0.3)), true, "[Captains]")
		eq((Chan.Receive("CHANNEL", "Member602", Msg("A", MY_GUILD, 1, "hello"), t + 0.4)), true, "a third member in [Olympus]")
		eq(select(2, Chan.Receive("CHANNEL", "Member600", Msg("A", MY_GUILD, 51, "spam 51"), t + 0.5)), "flood", "the spammer waits")
		-- A muted channel takes no room from the flood guard.
		ns.db.chatMute = { A = true }
		for i = 1, 70 do Chan.Receive("CHANNEL", "Member" .. (700 + i), Msg("A", MY_GUILD, 1, "muted"), 30000 + i * 0.1) end
		ns.db.chatMute = nil
		eq((Chan.Receive("CHANNEL", "Member800", Msg("A", MY_GUILD, 1, "after"), 30008)), true)
	end)
end)

test("chat lane goes first but never starves or evicts reports", function()
	local C = ns.Comm
	local out = {}
	local savedGuild = GetGuildInfo
	C_ChatInfo = {
		SendAddonMessage = function(_, msg) out[#out + 1] = msg end,
		SendAddonMessageLogged = function(_, msg) out[#out + 1] = "logged " .. msg end,
	}
	GetChannelName = function() return 5 end
	local ok, err = pcall(function()
		C.JoinChannel()
		eq(C.ChannelReady(), true)
		for _ = 1, 200 do
			if C.Stats().queue == 0 and C.Stats().chatQueue == 0 then break end
			C.Pump() -- whatever earlier tests queued
		end
		wipe(out)
		local results = {}
		for i = 1, 3 do C.Send("CHANNEL", "X" .. i .. "~r") end
		for i = 1, 2 do eq(C.SendChat("M1~A~Olympus II~" .. i .. "~~hi", function(sent) results[i] = sent end), true) end
		for _ = 1, 5 do C.Pump() end
		eq(table.concat(out, ","), "logged M1~A~Olympus II~1~~hi,X1~r,logged M1~A~Olympus II~2~~hi,X2~r,X3~r")
		eq(results[1], true); eq(results[2], true)
		for i = 1, 70 do C.Send("CHANNEL", "R" .. i) end
		eq(C.ChatRoom(), 6, "reports never take the chat lane's room")
		local dropped
		for i = 1, 6 do eq(C.SendChat("M1~A~Olympus II~9~~x", i == 6 and function(sent) dropped = sent end or nil), true) end
		eq(C.SendChat("M1~A~Olympus II~9~~x"), false, "lane full")
		eq(C.Stats().queue, 60); eq(C.Stats().chatQueue, 6)
		assert(ns.StatusText():find("lane=6", 1, true), "chat line in /oly status")
		-- Out of Olympus: both lanes are dropped and the sender hears about it.
		GetGuildInfo = function() return "House of Guedes" end
		C.Pump()
		GetGuildInfo = savedGuild
		eq(C.Stats().queue, 0); eq(C.Stats().chatQueue, 0); eq(dropped, false)
	end)
	GetGuildInfo, C_ChatInfo, GetChannelName = savedGuild, nil, nil
	if not ok then error(err, 0) end
end)

test("chat line shows tier, clickable name, guild and neutralised escapes", function()
	local line = Chan.FormatLine("C", "Bob-Other", "Olympus II", "PA", "hi |Tx|t")
	assert(line:find("[Captains]", 1, true), line)
	assert(line:find("|Hplayer:Bob-Other|h[", 1, true), line)
	assert(line:find("<Olympus II>", 1, true), line)
	assert(line:find("||Tx||t", 1, true), line)
	RAID_CLASS_COLORS = { PALADIN = { colorStr = "fff58cba" } }
	line = Chan.FormatLine("A", "Bob-Realm", "Olympus", "PA", "x")
	RAID_CLASS_COLORS = nil
	assert(line:find("[Olympus] |Hplayer:Bob|h[|cfff58cbaBob|r]|h <Olympus>: x", 1, true), line)
end)

test("whispers, invites and /who go to the name the server finds (Forever: never First Surname-Realm)", function()
	local savedInfo = C_ChatInfo
	C_ChatInfo = setmetatable({}, { __index = savedInfo })
	local saved = { split = ns.splitNames, realm = ns.realm, guild = GetGuildInfo }
	local ok, err = pcall(function()
		ns.realm = "Realm"
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		-- Classic: our realm left out, another realm kept (Blizzard's own form).
		ns.splitNames = nil
		eq(ns.TellName("Bob-Realm"), "Bob"); eq(ns.TellName("Bob-Other"), "Bob-Other"); eq(ns.TellName("Bob"), "Bob")
		-- Forever: "No player named 'Faladoriel Skylance-ClassicBetaPvP' is currently playing",
		-- while "Faladoriel Skylance" is found. However the name came.
		ns.splitNames = true
		eq(ns.TellName("Faladoriel Skylance-Realm"), "Faladoriel Skylance")
		eq(ns.TellName("Faladoriel-Skylance-Realm"), "Faladoriel Skylance")
		eq(ns.TellName("Faladoriel-Skylance"), "Faladoriel Skylance")
		eq(ns.TellName("Faladoriel Skylance"), "Faladoriel Skylance")
		eq(ns.TellName(nil), nil)
		-- The chat line's link, the one a player clicked.
		local line = Chan.FormatLine("A", "Faladoriel Skylance-Realm", "Olympus", nil, "hi")
		assert(line:find("|Hplayer:Faladoriel Skylance|h[", 1, true), line)
		-- The addon's own whispers (votes, audiences, layer invites...).
		local to
		C_ChatInfo.SendAddonMessage = function(_, _, dist, target) if dist == "WHISPER" then to = target end return true end
		ns.Comm.Whisper("Faladoriel Skylance-Realm", "T4~1~Olympus", "test tell")
		for _ = 1, 20 do if to then break end ns.Comm.Pump() end
		eq(to, "Faladoriel Skylance")
	end)
	ns.splitNames, ns.realm, GetGuildInfo, C_ChatInfo = saved.split, saved.realm, saved.guild, savedInfo
	if not ok then error(err, 0) end
end)

test("slash commands reach the right channel", function()
	eq(SLASH_OLYMPUSALL1, "/ol"); eq(SLASH_OLYMPUSCAPTAINS1, "/olc"); eq(SLASH_OLYMPUSLORDS1, "/oll")
	local savedTime, clock = GetTime, 50000
	GetTime = function() return clock end
	local ok, err = pcall(function()
		WithLane(function(sent)
			AsRank(0, function()
				local function Run(fn, arg, prefix)
					clock = clock + 10 -- past the 1.5 s gap
					local before = #sent
					fn(arg)
					eq(#sent, before + 1, arg)
					eq(sent[#sent]:sub(1, #prefix), prefix, arg)
				end
				Run(SlashCmdList.OLYMPUSALL, "hi", "M1~A~")
				Run(SlashCmdList.OLYMPUSCAPTAINS, "hi", "M1~C~")
				Run(SlashCmdList.OLYMPUSLORDS, "hi", "M1~L~")
				Run(SlashCmdList.OLYMPUS, "all hi", "M1~A~")
				Run(SlashCmdList.OLYMPUS, "captains hi", "M1~C~")
				Run(SlashCmdList.OLYMPUS, "lords hi", "M1~L~")
			end)
		end)
		ns.db.chatMute = nil
		AsRank(0, function()
			SlashCmdList.OLYMPUS("mute lords")
			eq(ns.db.chatMute.L, true)
			SlashCmdList.OLYMPUS("mute lords")
			eq(ns.db.chatMute.L, nil)
			SlashCmdList.OLYMPUS("mute olympus")
			eq(ns.db.chatMute.A, true)
			SlashCmdList.OLYMPUS("mute olympus")
			eq(ns.db.chatMute.A, nil)
		end)
	end)
	GetTime = savedTime
	if not ok then error(err, 0) end
end)

-- Comm.lua and Channels.lua loaded into a namespace of their own, like GuildFrame.lua above:
-- lines go through the real event, the M1 handler and Receive.
test("chat lines arrive through CHAT_MSG_ADDON_LOGGED, without our echo or blocked players", function()
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = ns })
	cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
	cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
	cns.After, cns.Every = function() end, function() end
	local slash = { SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS, StaticPopupDialogs.OLYMPUS_CHAT_PRIVACY }
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
	ns.db.chatMute = nil
	local ok, err = pcall(function()
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		assert(loadfile(ADDON_DIR .. "Channels.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		eq(events.CHAT_MSG_ADDON_LOGGED and #events.CHAT_MSG_ADDON_LOGGED, 1, "listens to logged addon messages")
		local function Deliver(sender, id)
			for _, fn in ipairs(events.CHAT_MSG_ADDON_LOGGED) do fn(ns.PREFIX, Msg("A", MY_GUILD, id, "via event " .. id), "CHANNEL", sender) end
		end
		CHAT_LINES = {}
		AsRank(3, function()
			Deliver("Member40", 1)
			eq(#CHAT_LINES, 1, "one line")
			assert(CHAT_LINES[1]:find("via event 1", 1, true), CHAT_LINES[1])
			ns.Roster.byName["Tester-Realm"] = 3 -- we are in our own roster
			Deliver("Tester", 2)
			ns.Roster.byName["Tester-Realm"] = nil
			eq(#CHAT_LINES, 1, "our own echo is not shown twice")
			ns.db.blocked["member41-realm"] = true
			Deliver("Member41", 3)
			ns.db.blocked["member41-realm"] = nil
			eq(#CHAT_LINES, 1, "blocked player")
		end)
	end)
	SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS = slash[1], slash[2], slash[3]
	StaticPopupDialogs.OLYMPUS_CHAT_PRIVACY = slash[4] -- (0.9.1: Channels.lua's warning, bound to the real module)
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Realm groups: PvP and PvP 2 share one census (Core.lua), and what tells realms apart
-- (names as the server sent them, the realm a report was sent from, guild peers by realm).
---------------------------------------------------------------------------

local BETA = "ClassicBetaPvP+ClassicBetaPvP2"

-- A table as text, keys sorted: two runs of the migration can be compared.
local function Dump(v)
	if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
	local keys, out = {}, {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Dump(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

-- ADDON_LOADED on the saved variables `saved`, played on the realm named `realmName`.
-- Returns OlympusDB, the store it opened and its group; ns is put back afterwards.
local function LoadAs(realmName, saved)
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, name = GetRealmName, capture = ns.CaptureError }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	GetRealmName = function() return realmName end
	OlympusDB = saved
	for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
	local rdb, group = ns.rdb, ns.group
	ns.db, ns.rdb, ns.realm, ns.group, GetRealmName, ns.CaptureError = keep.db, keep.rdb, keep.realm, keep.group, keep.name, keep.capture
	eq(captured, nil, "error caught")
	return OlympusDB, rdb, group
end

test("realm groups: the beta PvP realms start as one, learned links override, other realms stay alone", function()
	local savedDB = ns.db
	ns.db = { log = {} }
	eq(ns.GroupOf("ClassicBetaPvP"), BETA); eq(ns.GroupOf("ClassicBetaPvP2"), BETA)
	eq(ns.GroupOf("Realm"), "Realm", "any other realm is a group of its own")
	eq(ns.GroupSource("ClassicBetaPvP2"), "seed"); eq(ns.GroupSource("Realm"), "own")
	local realms = ns.GroupRealms(BETA)
	eq(#realms, 2); eq(realms[1], "ClassicBetaPvP"); eq(realms[2], "ClassicBetaPvP2")
	ns.db.links = { ClassicBetaPvP = BETA .. "+Other" }
	eq(ns.GroupOf("ClassicBetaPvP"), BETA .. "+Other", "a learned link overrides the seed")
	eq(ns.GroupSource("ClassicBetaPvP"), "learned")
	ns.db = savedDB
end)

test("realm groups: the PvP and PvP 2 stores merge into one, newest wins, nothing of ours lost", function()
	local now = os.time()
	local chatA, chatB = {}, {}
	for i = 1, 60 do chatA[i] = { t = now - 1000 + i * 2, sender = "A" .. i, text = "a" } end
	for i = 1, 60 do chatB[i] = { t = now - 999 + i * 2, sender = "B" .. i, text = "b" } end
	chatB[61] = chatA[60] -- one line in both stores
	local saved = { configVersion = 3, blocked = { troll = true }, realms = {
		ClassicBetaPvP = {
			guilds = { ["OLYMPUS I"] = { total = 500, t = now - 50, mine = true }, ["OLYMPUS VII"] = { total = 40, t = now - 3000 },
				["OLYMPUS XXL"] = { total = 90, t = now - 10 } },
			seen = { ["OLYMPUS LXIX"] = { online = 3, t = now - 100 } },
			inspect = { players = { ["Naked-ClassicBetaPvP"] = { status = "NONE", t = now - 100 }, ["Both-X"] = { status = "OTHER", t = now - 500 },
				["Bob Smith"] = { status = "GUILD", t = now - 900, marked = true, note = "ganker" }, ["Cy Jones"] = { status = "GUILD", t = now - 5 },
				["Undone"] = { status = "GUILD", t = now - 900, marked = true, note = "old" } },
				guildMarks = { ["OLYMPUS II"] = true } },
			chat = { A = chatA },
			realmKey = "same-secret",
		},
		ClassicBetaPvP2 = {
			guilds = { ["OLYMPUS I"] = { total = 480, t = now - 5000 }, ["OLYMPUS VII"] = { total = 45, t = now - 20 },
				["OLYMPUS XIV"] = { total = 60, t = now - 30, mine = true } },
			seen = { ["OLYMPUS LXIX"] = { online = 7, t = now - 5 }, ["OLYMPUS X"] = { online = 1, t = now - 9 } },
			inspect = { players = { ["Both-X"] = { status = "GUILD", t = now - 5 }, ["Bob Smith"] = { status = "NONE", t = now - 5 },
				["Cy Jones"] = { status = "GUILD", t = now - 900, marked = true, note = "spy" }, ["Undone"] = { status = "GUILD", t = now - 5, marked = false } },
				guildMarks = { ["OLYMPUS III"] = true } },
			chat = { A = chatB, C = { { t = now, sender = "Cap", text = "c" } } },
			realmKey = "same-secret",
			shared = { realm = "ClassicBetaPvP", to = "ClassicBetaPvP2", t = now - 60 },
		},
		Faraway = { guilds = { ["Olympus Far"] = { total = 5, t = now } } },
	} }
	local db, R, group = LoadAs("Classic Beta PvP", saved)
	eq(group, BETA); eq(db.realms[BETA], R, "one store for both realms")
	eq(db.realms.ClassicBetaPvP, nil, "the per-realm stores are gone"); eq(db.realms.ClassicBetaPvP2, nil)
	eq(db.realms.Faraway.guilds["Olympus Far"].total, 5, "another realm's store is untouched")
	eq(R.guilds["OLYMPUS I"].total, 500, "our own guild's newer report stays"); eq(R.guilds["OLYMPUS I"].mine, true)
	eq(R.guilds["OLYMPUS VII"].total, 45, "the newer report wins"); eq(R.guilds["OLYMPUS XXL"].total, 90)
	eq(R.guilds["OLYMPUS XIV"].total, 60, "an alt's own guild is kept"); eq(R.guilds["OLYMPUS XIV"].mine, true)
	eq(R.seen["OLYMPUS LXIX"].online, 7, "the newer sighting wins"); eq(R.seen["OLYMPUS X"].online, 1)
	eq(R.inspect.players["Naked-ClassicBetaPvP"].status, "NONE"); eq(R.inspect.players["Both-X"].status, "GUILD", "newest inspection")
	eq(R.inspect.guildMarks["OLYMPUS II"], true); eq(R.inspect.guildMarks["OLYMPUS III"], true, "the marks of both")
	local bob, cy = R.inspect.players["Bob Smith"], R.inspect.players["Cy Jones"]
	eq(bob.status, "NONE", "the newer inspection..."); eq(bob.marked, true, "...keeps the older one's mark"); eq(bob.note, "ganker")
	eq(cy.t, now - 5, "the newer entry stays..."); eq(cy.marked, true, "...and takes the mark merged in"); eq(cy.note, "spy")
	eq(R.inspect.players["Undone"].marked, false, "an explicit unmark stays"); eq(R.inspect.players["Undone"].note, "old")
	eq(R.guilds["OLYMPUS VII"].heardOn, "ClassicBetaPvP2", "a realm's store: its reports were heard there")
	eq(R.guilds["OLYMPUS XXL"].heardOn, "ClassicBetaPvP")
	-- 121 lines, one of them twice: 120, of which the oldest 20 go.
	eq(#R.chat.A, 100, "capped"); eq(R.chat.A[1].sender, "A11", "oldest dropped"); eq(R.chat.A[100].sender, "B60", "newest last")
	for i = 2, #R.chat.A do assert(R.chat.A[i - 1].t < R.chat.A[i].t, "chat in time order, each line once") end
	eq(#R.chat.C, 1)
	eq(R.realmKey, "same-secret", "the same key on both realms is kept")
	eq(R.shared.realm, "ClassicBetaPvP", "anything else is carried over")
	eq(db.blocked["troll-classicbetapvp"], true, "block list keys take the character's own realm")
	-- Running it again changes nothing, and PvP 2 opens the same store.
	local before = Dump(db.realms) .. Dump(db.links) .. Dump(db.blocked)
	local db2, R2 = LoadAs("Classic Beta PvP", db)
	eq(Dump(db2.realms) .. Dump(db2.links) .. Dump(db2.blocked), before, "second run")
	eq(R2, R)
	local _, R3, group3 = LoadAs("Classic Beta PvP 2", db)
	eq(group3, BETA); eq(R3, R, "PvP 2 reads the same census")
	eq(Dump(db.realms), Dump(db2.realms))
end)

test("realm groups: sightings kept with a realm of the group on the guild's name go under its plain name", function()
	local now = os.time()
	local _, R = LoadAs("Classic Beta PvP", { configVersion = 3, realms = {
		ClassicBetaPvP = { seen = { ["OLYMPUS XIV"] = { online = 2, t = now - 500 }, ["OLYMPUS V-ClassicBetaPvP"] = { online = 1, t = now - 10 } } },
		ClassicBetaPvP2 = { seen = { ["OLYMPUS XIV-ClassicBetaPvP2"] = { online = 4, t = now - 50 }, ["OLYMPUS X-Faraway"] = { online = 3, t = now - 9 },
			["OLYMPUS X"] = { online = 6, t = now - 20 }, ["OLYMPUS X-ClassicBetaPvP"] = { online = 5, t = now - 400 } } },
	} })
	local keep = { rdb = ns.rdb, group = ns.group, capture = ns.CaptureError }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.rdb, ns.group = R, BETA
	CoreFire("INIT") -- as ADDON_LOADED does, with the group's store open
	ns.rdb, ns.group, ns.CaptureError = keep.rdb, keep.group, keep.capture
	eq(captured, nil, "error caught")
	eq(R.seen["OLYMPUS XIV"].online, 4, "the newer one, whatever its name"); eq(R.seen["OLYMPUS XIV-ClassicBetaPvP2"], nil)
	eq(R.seen["OLYMPUS V"].online, 1); eq(R.seen["OLYMPUS V-ClassicBetaPvP"], nil)
	eq(R.seen["OLYMPUS X"].online, 6, "an older one does not replace it"); eq(R.seen["OLYMPUS X-ClassicBetaPvP"], nil)
	eq(R.seen["OLYMPUS X-Faraway"].online, 3, "a realm outside the group keeps its name")
end)

test("realm groups: realm keys, one is taken, the same is kept, different ones are dropped", function()
	local function Key(a, b, group)
		local realms = { ClassicBetaPvP = { realmKey = a }, ClassicBetaPvP2 = { realmKey = b } }
		if group then realms[BETA] = { realmKey = group } end
		local db, R = LoadAs("Classic Beta PvP 2", { configVersion = 3, realms = realms })
		eq(db.realms.ClassicBetaPvP, nil); eq(db.realms.ClassicBetaPvP2, nil)
		return R.realmKey
	end
	eq(Key("one-secret", nil), "one-secret", "only one realm had a key: taken")
	eq(Key(nil, "two-secret"), "two-secret")
	eq(Key("same-secret", "same-secret"), "same-secret")
	eq(Key("one-secret", "two-secret"), nil, "two keys: dropped, our officers send ours again")
	eq(Key(nil, nil), nil)
	eq(Key("one-secret", nil, "one-secret"), "one-secret", "the group's own key counts too")
	eq(Key(nil, "two-secret", "one-secret"), nil)
end)

test("realm groups: a link learned mid-session moves the census over at once", function()
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, Fire = ns.Fire, print = print,
		Join = ns.Comm.JoinChannel, Name = ns.Comm.ChannelName, Ask = ns.Comm.RequestKey }
	local fired, joins, asks, channel = {}, 0, 0, "OlympusNet"
	local ok, err = pcall(function()
		print = function() end
		ns.Fire = function(name) fired[#fired + 1] = name end
		ns.Comm.JoinChannel = function() joins = joins + 1 end
		ns.Comm.ChannelName = function() return channel end
		ns.Comm.RequestKey = function() asks = asks + 1 end
		local now = os.time()
		local R0 = { guilds = { ["Olympus Here"] = { total = 10, t = now } }, seen = {} }
		ns.db = { log = {}, realms = { Realm = R0, Other = { guilds = { ["Olympus There"] = { total = 20, t = now } } } } }
		ns.realm, ns.group, ns.rdb = "Realm", "Realm", R0
		eq(ns.LinkRealms("Realm", nil), false); eq(ns.LinkRealms("Realm", "?"), false); eq(ns.LinkRealms("Realm", "Realm"), false)
		eq(ns.LinkRealms("Realm", "Other"), true)
		eq(ns.group, "Other+Realm"); eq(ns.db.links.Realm, "Other+Realm"); eq(ns.db.links.Other, "Other+Realm")
		eq(ns.rdb, ns.db.realms["Other+Realm"], "the census now lives in the group's store")
		eq(ns.rdb.guilds["Olympus Here"].total, 10, "what we had is carried over")
		eq(ns.rdb.guilds["Olympus There"].total, 20, "and the other realm's census joins it")
		eq(ns.db.realms.Realm, nil); eq(ns.db.realms.Other, nil)
		eq(fired[#fired], "DATA_CHANGED"); eq(joins, 0, "no key changed: same channel")
		eq(ns.LinkRealms("Other", "Realm"), false, "nothing new")
		-- A realm with another key: both keys go, and we move to the channel without one.
		ns.rdb.realmKey = "our-secret"
		ns.db.realms.Third = { realmKey = "their-secret" }
		eq(ns.LinkRealms("Realm", "Third"), true)
		eq(ns.group, "Other+Realm+Third", "the whole group grows"); eq(ns.db.links.Other, "Other+Realm+Third")
		eq(ns.rdb.guilds["Olympus Here"].total, 10, "the old group's store is merged too")
		eq(ns.db.realms["Other+Realm"], nil)
		eq(ns.rdb.realmKey, nil); eq(joins, 1, "the key changed: so does the channel")
		eq(asks, 1, "ours was dropped: our officers are asked for it again")
		ns.rdb.realmKey = "our-secret"
		ns.db.realms.Fourth = { realmKey = "our-secret" }
		eq(ns.LinkRealms("Realm", "Fourth"), true); eq(ns.rdb.realmKey, "our-secret"); eq(joins, 1, "same key"); eq(asks, 1)
		channel = nil
		ns.db.realms.Fifth = { realmKey = "their-secret" }
		eq(ns.LinkRealms("Fifth", "Realm"), true); eq(ns.rdb.realmKey, nil)
		eq(joins, 1, "not joined yet: the first join takes the new key"); eq(asks, 1, "and the login's request asks")
	end)
	ns.db, ns.rdb, ns.realm, ns.group, ns.Fire, print = keep.db, keep.rdb, keep.realm, keep.group, keep.Fire, keep.print
	ns.Comm.JoinChannel, ns.Comm.ChannelName, ns.Comm.RequestKey = keep.Join, keep.Name, keep.Ask
	if not ok then error(err, 0) end
end)

test("realm groups: our guild homed on another realm links it; roster names are counted as sent", function()
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, print = print,
		info = GetGuildInfo, roster = GetGuildRosterInfo }
	local ok, err = pcall(function()
		print = function() end
		ns.db = { log = {}, blocked = {}, realms = { Realm = { guilds = {}, seen = {} } } }
		ns.realm, ns.group, ns.rdb = "Realm", "Realm", ns.db.realms.Realm
		GetGuildInfo = function() return MY_GUILD, "Hero", 3, "Other" end
		GetGuildRosterInfo = function(i)
			local far = i % 3 == 0
			return far and ("Far" .. i .. "-Other") or ("Near" .. i), "rank", i == 1 and 0 or 3, 10, "class", "Elwynn Forest",
				"", "", true, 0, "MAGE", nil, nil, nil, nil, nil, ("Player-%d-%08X"):format(far and 4620 or 4619, i)
		end
		ns.Roster.RequestScan(true)
		ns.Roster.TryScan()
		eq(ns.db.links.Realm, "Other+Realm", "learned from our own guild's home")
		eq(ns.group, "Other+Realm")
		local mine = ns.rdb.guilds[MY_GUILD]
		eq(mine.home, "Other"); eq(mine.from, "Realm")
		local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(mine))
		eq(d.home, "Other"); eq(d.from, "Realm")
		eq(ns.Roster.rawRealms.bare, 667); eq(ns.Roster.rawRealms.Other, 333)
		eq(ns.Roster.servers["4619"], 667); eq(ns.Roster.servers["4620"], 333)
		eq(ns.Roster.rawSample, "Far3-Other", "an example with its realm, when there is one")
		-- Guild on our own realm: 4th return nil, home is ours, nothing to link.
		GetGuildInfo = function() return MY_GUILD, "Hero", 3 end
		eq(ns.Roster.Scan().home, "Realm")
	end)
	ns.db, ns.rdb, ns.realm, ns.group, print = keep.db, keep.rdb, keep.realm, keep.group, keep.print
	GetGuildInfo, GetGuildRosterInfo = keep.info, keep.roster
	ns.Roster.Scan() -- the roster of the other tests back
	if not ok then error(err, 0) end
end)

test("Horde: its own channel, its own census, and the other faction's reports are ignored", function()
	local C, D = ns.Codec, ns.Data
	local savedFaction, savedUFG, savedKey = ns.faction, UnitFactionGroup, ns.rdb.realmKey
	local ok, err = pcall(function()
		-- Reports carry the faction; older versions send none and count as Alliance.
		local horde = C.DecodeReport(C.EncodeReport({ guild = "Olympus Orda", total = 50, online = 5, zones = {}, faction = "Horde" }))
		eq(horde.faction, "Horde")
		local old = C.DecodeReport(table.concat(C.Split(C.EncodeReport({ guild = "Olympus Old", total = 9, online = 1, zones = {} }), "~"), "~", 1, 22))
		eq(old.faction, "Alliance", "no faction field: Alliance")
		-- An Alliance client ignores Horde guilds, and the other way around.
		ns.faction = "Alliance"
		ns.rdb.guilds = {}
		eq(D.Receive(horde, "Grunt-Realm"), false, "a Horde report on an Alliance client")
		eq(ns.rdb.guilds["Olympus Orda"], nil)
		ns.faction = "Horde"
		eq(D.Receive(old, "Footman-Realm"), false, "an Alliance (or old) report on a Horde client")
		eq(D.Receive(C.DecodeReport(C.EncodeReport({ guild = "Olympus Orda", total = 50, online = 5, zones = {}, faction = "Horde" })), "Grunt2-Realm"), true)
		-- Its own channel, public and sealed.
		ns.rdb.realmKey = nil
		eq(ns.Comm.ChannelSpec(), "OlympusNetH")
		ns.rdb.realmKey = "secret-one"
		local name, password = ns.Comm.ChannelSpec()
		eq(name, "OlyH" .. ns.Comm.Hash36("secret-one")); eq(password, "secret-one")
		ns.faction = "Alliance"
		eq(ns.Comm.ChannelSpec(), "Oly" .. ns.Comm.Hash36("secret-one"), "the Alliance keeps its names")
		ns.rdb.realmKey = nil
		eq(ns.Comm.ChannelSpec(), "OlympusNet")
		-- Faction from the game.
		UnitFactionGroup = function() return "Horde" end
		eq(ns.Faction(), "Horde")
		UnitFactionGroup = function() return nil end
		eq(ns.Faction(), "Alliance", "unknown yet: Alliance")
	end)
	ns.faction, UnitFactionGroup, ns.rdb.realmKey = savedFaction, savedUFG, savedKey
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("Horde and Alliance characters of one account keep separate stores", function()
	local savedDB, savedR, savedRealm, savedGroup, savedFaction, savedUFG = ns.db, ns.rdb, ns.realm, ns.group, ns.faction, UnitFactionGroup
	local ok, err = pcall(function()
		OlympusDB = { configVersion = 3, realms = { Realm = { guilds = { ["Olympus Ally"] = { total = 5, t = os.time() } } } } }
		UnitFactionGroup = function() return "Horde" end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(ns.faction, "Horde")
		eq(ns.rdb.guilds["Olympus Ally"], nil, "the Horde doesn't see the Alliance census")
		ns.rdb.guilds["Olympus Orda"] = { total = 7, t = os.time() }
		eq(OlympusDB.realms.Realm.guilds["Olympus Ally"].total, 5, "Alliance data untouched")
		assert(OlympusDB.horde and OlympusDB.horde.realms, "the Horde has its own store")
		-- Next login on an Alliance character of the same account.
		UnitFactionGroup = function() return "Alliance" end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(ns.faction, "Alliance")
		eq(ns.rdb.guilds["Olympus Ally"].total, 5)
		eq(ns.rdb.guilds["Olympus Orda"], nil)
		-- Old account-wide inspections (Alliance only) never move into the Horde store.
		OlympusDB.inspect = { players = { Oldie = { status = "NONE" } }, guildMarks = {} }
		UnitFactionGroup = function() return "Horde" end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(ns.rdb.inspect and ns.rdb.inspect.players and ns.rdb.inspect.players.Oldie, nil, "not on the Horde")
		assert(OlympusDB.inspect, "kept for the next Alliance login")
		UnitFactionGroup = function() return "Alliance" end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(ns.rdb.inspect.players.Oldie.status, "NONE", "moved into the Alliance store")
		eq(OlympusDB.inspect, nil)
		-- Faction unknown at load, Horde at login: the store switches.
		UnitFactionGroup = function() return nil end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(ns.faction, "Alliance")
		UnitFactionGroup = function() return "Horde" end
		eq(ns.CheckFaction(), true)
		eq(ns.rdb.guilds["Olympus Orda"].total, 7, "back on the Horde census")
	end)
	ns.db, ns.rdb, ns.realm, ns.group, ns.faction, UnitFactionGroup = savedDB, savedR, savedRealm, savedGroup, savedFaction, savedUFG
	if not ok then error(err, 0) end
end)

test("reports: fields 21 and 22 (reporter's realm, guild's home) are optional both ways", function()
	local C = ns.Codec
	local r = { guild = "Olympus Span", total = 9, online = 1, zones = {}, from = "ClassicBetaPvP2", home = "ClassicBetaPvP" }
	local payload = C.EncodeReport(r)
	local d = C.DecodeReport(payload)
	eq(d.from, "ClassicBetaPvP2"); eq(d.home, "ClassicBetaPvP")
	local f = C.Split(payload, "~")
	eq(#f, 24, "22 fields, the faction (23) and the versions (24)")
	local withVersions = C.DecodeReport(C.EncodeReport({ guild = "Olympus V", total = 9, online = 1, zones = {},
		versions = { ["0.8.2"] = 3, ["0.8.1"] = 1, ["?"] = 1 } }))
	eq(withVersions.versions["0.8.2"], 3); eq(withVersions.versions["0.8.1"], 1)
	local old = C.DecodeReport(table.concat(f, "~", 1, 20))
	eq(old.total, 9); eq(old.from, nil, "a 20-field report (older versions)"); eq(old.home, nil)
	local newer = C.DecodeReport(payload .. "~some field of a later version")
	eq(newer.from, "ClassicBetaPvP2", "a 25-field report still decodes")
	f[21], f[22] = "Bad|cffRealm", ("x"):rep(41)
	d = C.DecodeReport(table.concat(f, "~"))
	eq(d.from, nil, "no escape codes"); eq(d.home, nil, "no more than 40 characters")
	eq(C.RealmField("Two words"), nil); eq(C.RealmField(""), nil); eq(C.RealmField(("x"):rep(40)), ("x"):rep(40))
end)

test("a bare officer of a report sent from another realm keeps its rank (names as the sender sent them)", function()
	local saved = ns.rdb.guilds
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = "Olympus Span", total = 9, online = 1, zones = {}, leader = "Spanboss", from = "Other",
		officers = { { name = "Spancapt", online = true, days = 0 } } }, "Spanboss"), true)
	eq(ns.rdb.guilds["Olympus Span"].realm, "Realm", "the realm of the sender's name, not the report's")
	eq(ns.Data.KnownRank("Spancapt", "Olympus Span"), 1, "a bare guildmate of the reporter matches")
	eq(ns.Data.KnownRank("Spancapt-Other", "Olympus Span"), nil)
	ns.rdb.guilds = saved
end)

test("a report heard by a character on another realm of the group is no previous report here", function()
	local saved = ns.rdb.guilds
	local ok, err = pcall(function()
		ns.rdb.guilds = {}
		local function Rep() return { guild = "Olympus Span", total = 9, online = 1, zones = {}, leader = "Spanboss",
			officers = { { name = "Spancapt", online = true, days = 0 } } } end
		-- Heard by our alt on Other: every bare name took Other.
		local keep = ns.realm
		ns.realm = "Other"
		eq(ns.Data.Receive(Rep(), "Spanboss"), true)
		ns.realm = keep
		local there = ns.rdb.guilds["Olympus Span"]
		eq(there.heardOn, "Other"); eq(there.reporterFull, "Spanboss-Other")
		eq(ns.Data.Receive(Rep(), "Spanboss"), true)
		local here = ns.rdb.guilds["Olympus Span"]
		eq(here.heardOn, "Realm"); eq(here.conflict, nil, "the same reporter and officers, not added ones")
		eq(here.vouch["Spanboss-Other"], nil, "nor a voucher in another form")
		-- Heard here: compared as always.
		eq(ns.Data.Receive(Rep(), "Otherguy"), true)
		eq(ns.rdb.guilds["Olympus Span"].conflict, nil); eq(ns.rdb.guilds["Olympus Span"].vouch["Otherguy-Realm"].ranks["Spancapt-Realm"], 1)
		local r = Rep()
		r.leader = "Usurper"
		eq(ns.Data.Receive(r, "Thirdguy"), false, "one against two: not the row")
		eq(ns.rdb.guilds["Olympus Span"].outvoted, true, "but noted"); eq(ns.rdb.guilds["Olympus Span"].leader, "Spanboss")
	end)
	ns.rdb.guilds = saved
	if not ok then error(err, 0) end
end)

-- Comm.lua loaded into a namespace of its own (fresh peers, stats and guard) with a clock the
-- test moves. Deliver(dist, sender, text) goes through the real CHAT_MSG_ADDON handler.
local function FreshComm()
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = ns })
	cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
	cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
	cns.After, cns.Every = function() end, function() end
	cns.clock = 100000
	cns.Now = function() return cns.clock end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
	assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
	for _, fn in ipairs(login) do fn() end
	local function Deliver(dist, sender, text)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, text, dist, sender) end
	end
	local id = 0
	local function Report(sender, r)
		id = id + 1
		for _, c in ipairs(ns.Codec.Chunk(ns.Codec.EncodeReport(r), tostring(id))) do Deliver("CHANNEL", sender, c) end
	end
	return cns, Deliver, Report
end

test("runner-up: only a 0.7.11+ peer on the reporter's channel", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		C.JoinChannel()
		-- Aaa reports; Bob (before us in the election) runs 0.7.10 and never backs anyone.
		Deliver("GUILD", "Aaa", "H1~0.7.11~Realm~p")
		Deliver("GUILD", "Bob", "H1~0.7.10")
		Report("Aaa", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true, "the old peer is skipped: we back the reporter")
		-- Bcc (before us) is on the sealed channel, the reporter on the public one: skipped too.
		Deliver("GUILD", "Bcc", "H1~0.7.11~Realm~s")
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true, "a peer on the other channel can't back this reporter")
		Deliver("GUILD", "Bdd", "H1~0.7.11~Realm~p")
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, false, "a 0.7.11 peer on the same channel comes first")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("runner-up backs an active reporter; census on request, bounded", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		GetChannelName = function() return 5 end
		C.JoinChannel()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		local function Flush() for _ = 1, 40 do C.Pump() end end
		local function Chunks() local n = 0 for _, m in ipairs(sent) do if m:find("^CHANNEL C") then n = n + 1 end end return n end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {}, leader = "Member1" }
		-- Abe (first in the election) is elected; we are the runner-up. Abe is not heard yet.
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		C.MaybeBroadcast(ours)
		eq(C.isReporter, false); eq(C.isRunnerUp, false, "reporter not heard: nothing to back")
		Flush(); eq(Chunks(), 0)
		-- Abe reports on the channel: now we back him, once every 10 minutes.
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true)
		Flush(); local first = Chunks(); assert(first > 0, "runner-up report sent")
		cns.clock = cns.clock + 300
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		Flush(); eq(Chunks(), first, "not before 10 minutes")
		cns.clock = cns.clock + 301
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		Flush(); eq(Chunks(), first * 2, "again after 10 minutes")
		-- Census requests: only the elected reporter answers, at most every 2 minutes.
		cns.After = function(_, _, fn) fn() end
		local before = Chunks()
		Deliver("CHANNEL", "Newbie", "Q1~")
		Flush(); eq(Chunks(), before, "the runner-up does not answer")
		cns.clock = cns.clock + 200
		C.MaybeBroadcast(ours) -- Abe was not heard for 200 s but is still elected
		local cns2, Deliver2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		cns2.After = function(_, _, fn) fn() end
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		C2.MaybeBroadcast(ours) -- alone: we are the reporter, and report now
		eq(C2.isReporter, true)
		sent = {}
		Flush()
		for _ = 1, 40 do C2.Pump() end
		local afterOwn = Chunks()
		cns2.clock = cns2.clock + 60
		Deliver2("CHANNEL", "Newbie", "Q1~")
		for _ = 1, 40 do C2.Pump() end
		assert(Chunks() > afterOwn, "the reporter answers a request")
		local afterAnswer = Chunks()
		cns2.clock = cns2.clock + 50
		Deliver2("CHANNEL", "Other", "Q1~")
		for _ = 1, 40 do C2.Pump() end
		eq(Chunks(), afterAnswer, "not twice within 2 minutes")
		eq(C2.Stats().answered, 1)
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("census requests: nobody answers in their first minute, the runner-up answers too", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		-- Just logged in: alone so far, so we think we are the reporter, but must not answer.
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock
		C.JoinChannel()
		local fired = 0
		cns.After = function(_, _, fn) fired = fired + 1; fn() end
		C.MaybeBroadcast(ours)
		cns.clock = cns.clock + 30
		Deliver("CHANNEL", "Newbie", "Q1~")
		eq(C.Stats().answered, 0, "not in the first minute after login")
		-- Settled, and the runner-up of an active reporter: answers.
		local cns2, Deliver2, Report2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		cns2.After = function(_, _, fn) fn() end
		Deliver2("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report2("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C2.MaybeBroadcast(ours)
		eq(C2.isRunnerUp, true)
		cns2.clock = cns2.clock + 60
		Deliver2("CHANNEL", "Newbie", "Q1~")
		eq(C2.Stats().answered, 1, "the runner-up answers")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("only our channel counts, and chat only through the logged API", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		GetChannelName = function() return 5 end
		C.JoinChannel()
		-- Deliver with the channel number the client gives (7th argument of CHAT_MSG_ADDON).
		local handlers = {}
		local seen = 0
		C.Handle("Z9", function() seen = seen + 1 end)
		Deliver("CHANNEL", "Outsider", "Z9~x")
		eq(seen, 1, "no channel number given: accepted, as before")
		local events = {}
		-- The real handler with all arguments: another channel's number is dropped.
		local cns3 = setmetatable({}, { __index = ns })
		local login = {}
		cns3.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns3.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
		cns3.After, cns3.Every = function() end, function() end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessageLogged = function() end }
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns3)
		for _, fn in ipairs(login) do fn() end
		cns3.Comm.JoinChannel()
		local got = 0
		cns3.Comm.Handle("Z9", function() got = got + 1 end)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, "Z9~x", "CHANNEL", "Outsider", "", 0, 9, "SomeoneElsesChannel") end
		eq(got, 0, "a message on channel #9 is not ours (#5)")
		eq(cns3.Comm.Stats().otherChannel, 1)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, "Z9~x", "CHANNEL", "Friend", "", 0, 5, "OlympusNet") end
		eq(got, 1, "ours (#5) is")
		assert(cns3.Comm.Stats().chanArgs:find("localID=9", 1, true), "the first channel's arguments are kept for /oly status")
		eq(cns3.Comm.DeliveredLogged(), false)
		local inside
		cns3.Comm.Handle("Z8", function() inside = cns3.Comm.DeliveredLogged() end)
		for _, fn in ipairs(events.CHAT_MSG_ADDON_LOGGED) do fn(ns.PREFIX, "Z8~x", "CHANNEL", "Friend", "", 0, 5, "OlympusNet") end
		eq(inside, true, "handlers know a message came through the logged API")
		eq(cns3.Comm.DeliveredLogged(), false, "and only while it is handled")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("a channel number that changed under us holds channel messages", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns = FreshComm()
		local C = cns.Comm
		local id = 5
		GetChannelName = function() return id end
		C.JoinChannel()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = dist .. "#" .. tostring(target) .. " " .. msg end
		C.Send("CHANNEL", "Z9~one")
		id = 0 -- the player left the channel (Chat Channels panel)
		C.Pump()
		eq(#sent, 0, "nothing goes to a number that is no longer ours")
		id = 5
		C.JoinChannel()
		C.Pump()
		eq(sent[1], "CHANNEL#5 Z9~one", "sent once we are back")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("hello: guild peers say their realm, older versions count as old", function()
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		Deliver("GUILD", "Abe-ClassicBetaPvP2", "H1~0.7.11~ClassicBetaPvP2")
		Deliver("GUILD", "Bob", "H1~0.7.10")
		Deliver("GUILD", "Cy", "H1~0.7.11~Bad Realm!") -- (0.9.2: a "|" never gets this far, see Comm)
		local st = cns.Comm.Stats()
		eq(st.peers, 3); eq(st.peerRealms.ClassicBetaPvP2, 1); eq(st.peerRealms.old, 2, "no realm, or not a realm")
		eq(st.raw.g.bare, 2, "counted as sent, before our realm is added"); eq(st.raw.g.ClassicBetaPvP2, 1)
		eq(st.rawSample.g, "Abe-ClassicBetaPvP2")
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		cns.Comm.Hello()
		cns.Comm.Pump()
		eq(sent[1], "GUILD H1~" .. ns.VERSION .. "~Realm~p", "ours names our realm and channel (public)")
		local savedKey = ns.rdb.realmKey
		ns.rdb.realmKey = "secret"
		cns.clock = cns.clock + 600
		cns.Comm.Hello()
		cns.Comm.Pump()
		ns.rdb.realmKey = savedKey
		eq(sent[2], "GUILD H1~" .. ns.VERSION .. "~Realm~s", "sealed")
	end)
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("a report sent from another realm proves the channel is shared", function()
	local saved = { guilds = ns.rdb.guilds, shared = ns.rdb.shared }
	local ok, err = pcall(function()
		local cns, _, Report = FreshComm()
		ns.rdb.guilds, ns.rdb.shared = {}, nil
		Report("Nearby", { guild = "Olympus Near", total = 5, online = 1, zones = {}, from = "Realm" })
		eq(ns.rdb.shared, nil, "a report from our own realm proves nothing")
		Report("Faraway-Other", { guild = "Olympus Far", total = 7, online = 2, zones = {}, from = "Other" })
		eq(ns.rdb.shared.realm, "Other"); eq(ns.rdb.shared.to, "Realm")
		Report("Oldtimer-Realm", { guild = "Olympus Old", total = 3, online = 1, zones = {} })
		local st = cns.Comm.Stats()
		eq(st.reportRealms.Realm, 1); eq(st.reportRealms.Other, 1); eq(st.reportRealms.old, 1, "older versions send no realm")
		eq(st.raw.ch.bare, 1, "Nearby came without a realm..."); eq(ns.rdb.guilds["Olympus Near"].reporterFull, "Nearby-Realm", "...and got ours")
		eq(st.raw.ch.Other, 1); eq(st.raw.ch.Realm, 1)
		eq(ns.rdb.guilds["Olympus Far"].from, "Other")
		assert(ns.StatusText():find("channel SHARED (Other -> Realm", 1, true), "in /oly status")
	end)
	ns.rdb.guilds, ns.rdb.shared = saved.guilds, saved.shared
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("election guard: a reporter never heard on the channel is left out a while, one that is heard stays", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local function Tick(seconds, hellos, heard)
			cns.clock = cns.clock + seconds
			for _, name in ipairs(hellos) do Deliver("GUILD", name, "H1~0.7.11~Realm") end
			for _, name in ipairs(heard or {}) do Report(name, ours) end
			C.MaybeBroadcast(ours)
		end
		Tick(0, { "Abe" })
		eq(C.reporterName, "Abe", "Abe sorts first")
		for _ = 1, 10 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Abe", "we are not on the channel: we could not have heard it")
		GetChannelName = function() return 5 end
		C.JoinChannel()
		Tick(0, { "Abe" })
		for _ = 1, 6 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Abe", "on the channel 360 s: not yet")
		Tick(60, { "Abe" })
		eq(C.reporterName, "Tester", "never heard in 400 s: left out, we report"); eq(C.isReporter, true)
		eq(C.Stats().benched[1], "Abe")
		eq(C.Stats().queue > 0, true, "and our report goes out")
		-- Aaron sorts first and is heard every 180 s: elected and kept.
		for _ = 1, 8 do Tick(180, { "Abe", "Aaron" }, { "Aaron" }) end
		eq(C.reporterName, "Aaron", "heard: stays elected")
		eq(C.Stats().heardOwn, "Aaron")
		-- Aaron logs off; 30 minutes after it was left out, Abe may be elected again.
		Tick(1800 - 8 * 180, { "Abe" })
		eq(#C.Stats().benched, 0); eq(C.reporterName, "Abe")
		-- A peer left out is back as soon as it is heard.
		for _ = 1, 7 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Tester")
		Report("Abe", ours)
		Tick(0, { "Abe" })
		eq(C.reporterName, "Abe", "heard: in again")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("election guard: a reporter named with its realm over GUILD and without it on the channel is heard", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		GetChannelName = function() return 5 end
		C.JoinChannel()
		local function Tick(seconds, heard)
			cns.clock = cns.clock + seconds
			Deliver("GUILD", "Abe-ClassicBetaPvP2", "H1~0.7.11~ClassicBetaPvP2~p")
			if heard then Report("Abe", ours) end
			C.MaybeBroadcast(ours)
		end
		Tick(0)
		for _ = 1, 8 do Tick(180, true) end
		eq(C.reporterName, "Abe-ClassicBetaPvP2", "heard as Abe: stays elected"); eq(#C.Stats().benched, 0)
		for _ = 1, 3 do Tick(180) end
		eq(C.reporterName, "Tester", "silent: left out"); eq(C.Stats().benched[1], "Abe-ClassicBetaPvP2")
		Tick(0, true)
		eq(C.reporterName, "Abe-ClassicBetaPvP2", "heard as Abe: in again")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("election guard: a sealed reporter is not judged without the key, and another channel starts the watch again", function()
	local savedChannel, savedKey, savedLeave = GetChannelName, ns.rdb.realmKey, LeaveChannelByName
	local ok, err = pcall(function()
		LeaveChannelByName = function() end
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		ns.rdb.realmKey = nil
		GetChannelName = function() return 5 end
		C.JoinChannel()
		eq(C.ChannelName(), "OlympusNet")
		local function Tick(seconds, flag)
			cns.clock = cns.clock + seconds
			Deliver("GUILD", "Abe", "H1~0.7.11~Realm" .. (flag and ("~" .. flag) or ""))
			C.MaybeBroadcast(ours)
		end
		for _ = 1, 12 do Tick(60, "s") end
		eq(C.reporterName, "Abe", "on the sealed channel: we can't hear it, so we don't judge it"); eq(#C.Stats().benched, 0)
		eq(C.Stats().queue, 1, "we ask for the key instead...")
		C.Pump()
		eq(sent[1], "GUILD K0~")
		for _ = 1, 5 do Tick(60, "s") end
		eq(C.Stats().queue, 0, "...not every minute")
		-- An older version says nothing about its channel: judged as before, watched from now.
		for _ = 1, 5 do Tick(60) end
		eq(C.reporterName, "Abe")
		-- The key arrives: another channel, and what we did not hear on the public one says nothing.
		ns.rdb.realmKey = "secret"
		C.JoinChannel()
		assert(C.ChannelName() ~= "OlympusNet", "sealed channel")
		Tick(0)
		for _ = 1, 6 do Tick(60) end
		eq(C.reporterName, "Abe", "360 s on the sealed channel: not yet")
		Tick(60)
		eq(C.reporterName, "Tester", "400 s there: left out")
		-- We have the key: a peer on the public channel is judged like any other.
		local cns2, Deliver2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		for _ = 1, 8 do
			cns2.clock = cns2.clock + 60
			Deliver2("GUILD", "Abe", "H1~0.7.11~Realm~p")
			C2.MaybeBroadcast(ours)
		end
		eq(C2.reporterName, "Tester", "public reporter, never heard on our sealed channel: left out")
	end)
	GetChannelName, C_ChatInfo, ns.rdb.realmKey, LeaveChannelByName = savedChannel, nil, savedKey, savedLeave
	if not ok then error(err, 0) end
end)

test("who: a guild named with a realm of our census group is the same guild", function()
	local savedGroup = ns.group
	local ok, err = pcall(WithWho, function(server)
		ns.group = "Other+Realm"
		ns.Who.Search()
		server.Answer({
			{ "Aa", "OLYMPUS VII-Other", 12 }, { "Bb", "OLYMPUS VII", 14 }, { "Cc-Far", "OLYMPUS VII-Faraway", 9 },
			{ "Dd", "OLYMPUS I-Realm", 20 },
		})
		server.Run()
		local seen = ns.rdb.seen
		eq(seen["OLYMPUS VII"].online, 2, "OLYMPUS VII-Other is OLYMPUS VII"); eq(seen["OLYMPUS VII-Other"], nil)
		eq(seen["OLYMPUS I"].online, 1, "so is a guild named with our own realm")
		eq(seen["OLYMPUS VII-Faraway"].online, 1, "a realm outside the group keeps its name")
		local names, suffixed, sample = ns.Who.RawCounts()
		eq(names.bare, 3); eq(names.Far, 1); eq(suffixed, 3); eq(sample, "Cc-Far")
	end)
	ns.group = savedGroup
	if not ok then error(err, 0) end
end)

test("/oly status: realm, census, raw names and topology, short, and without the newer realm APIs", function()
	local keep = { group = ns.group, realm = ns.realm, shared = ns.rdb.shared, info = GetGuildInfo, Stats = ns.Comm.Stats, RawCounts = ns.Who.RawCounts }
	local ok, err = pcall(function()
		eq(C_AutoComplete, nil); eq(GetNativeRealmID, nil); eq(RegionalUniqueNamesEnabled, nil); eq(GetRealmID, nil)
		local text = ns.StatusText()
		for _, want in ipairs({ "id=nil native=nil guid=nil", "unique names=?", "connected=n/a", "shared: not seen yet" }) do
			assert(text:find(want, 1, true), want .. "\n" .. text)
		end
		ns.realm, ns.group = "ClassicBetaPvP", BETA
		C_AutoComplete = { GetAutoCompleteRealms = function() return {} end }
		GetRealmID = function() return 4619 end
		GetNativeRealmID = function() error("not on this client") end
		RegionalUniqueNamesEnabled = function() return true end
		UnitGUID = function() return "Player-4619-0A1B2C3D" end
		GetRealmName = function() return "Classic Beta PvP" end
		ns.rdb.shared = { realm = "ClassicBetaPvP2", to = "ClassicBetaPvP", t = os.time() - 250 }
		text = ns.StatusText()
		for _, want in ipairs({ "realm: Classic Beta PvP = ClassicBetaPvP  id=4619 native=nil guid=4619  guild home=ours",
			"census: " .. BETA .. " (seed)  unique names=true  connected=none", "names raw: roster Realm=1000  e.g. [Member1-Realm]",
			"names raw: roster by server (GUID) ?=1000", "topology: channel SHARED (ClassicBetaPvP2 -> ClassicBetaPvP, 4m ago)",
			"topology: guild peers by realm" }) do
			assert(text:find(want, 1, true), want .. "\n" .. text)
		end
		-- The longest these lines get on the beta: still short.
		local long = "Bellattrixx Lesstrange-ClassicBetaPvP2"
		GetGuildInfo = function() return MY_GUILD, "Hero", 3, "ClassicBetaPvP2" end
		GetNativeRealmID = function() return 4620 end
		C_AutoComplete.GetAutoCompleteRealms = function() return { "Classic Beta PvP", "Classic Beta PvP 2", "Classic Beta PvE", "Classic Beta RP" } end
		local R = ns.Roster
		local raw = { bare = 300, ClassicBetaPvP2 = 263 } -- names as sent: bare, or with PvP 2
		local realms = { ClassicBetaPvP = 300, ClassicBetaPvP2 = 263, old = 12 }
		R.rawRealms, R.servers, R.rawSample = raw, { ["4619"] = 300, ["4620"] = 263 }, long
		ns.Comm.Stats = function()
			local c = keep.Stats()
			c.raw, c.rawSample = { ch = raw, g = raw }, { ch = long, g = long }
			c.reportRealms, c.peerRealms, c.heardOwn, c.heardOwnAt, c.benched = realms, realms, long, os.time() - 100, { long }
			return c
		end
		ns.Who.RawCounts = function() return raw, 30, long end
		text = ns.StatusText()
		local checked = 0
		for line in text:gmatch("[^\n]+") do
			if line:find("^realm:") or line:find("^census:") or line:find("^names raw:") or line:find("^topology:") then
				checked = checked + 1
				assert(#line <= 110, ("too long for the /oly bug window (%d): %s"):format(#line, line))
			end
		end
		eq(checked, 12)
		assert(text:find("connected=ClassicBetaPvP2,ClassicBetaPvE,+1", 1, true), "ours left out, two named\n" .. text)
	end)
	C_AutoComplete, GetRealmID, GetNativeRealmID, RegionalUniqueNamesEnabled, UnitGUID = nil, nil, nil, nil, nil
	GetRealmName = function() return "Realm" end
	GetGuildInfo, ns.Comm.Stats, ns.Who.RawCounts = keep.info, keep.Stats, keep.RawCounts
	ns.group, ns.realm, ns.rdb.shared = keep.group, keep.realm, keep.shared
	ns.Roster.Scan() -- the roster counts of the other tests back
	if not ok then error(err, 0) end
end)

test("census subtitle names the realms sharing it", function()
	local savedGroup = ns.group
	local uns = setmetatable({}, { __index = ns })
	uns.On = function() end
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	ns.group = BETA
	eq(uns.UI.CensusName(), "ClassicBetaPvP + ClassicBetaPvP2")
	ns.group = "Realm"
	eq(uns.UI.CensusName(), "Realm", "one realm: its name")
	ns.group = savedGroup
end)

---------------------------------------------------------------------------
-- After an update adds files, /reload keeps the old file list until the game restarts.
---------------------------------------------------------------------------

test("files added by an update and not loaded yet: stand-ins keep everything else working", function()
	local savedSlash, savedEvents, savedPrint = {}, #EVENT_SCRIPTS, print
	for k, v in pairs(SlashCmdList) do savedSlash[k] = v end
	local printed = {}
	print = function(msg) printed[#printed + 1] = tostring(msg) end
	local ok, err = pcall(function()
		local fresh = {}
		for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Dialog", "Codec", "Zones", "Data", "Roster", "Comm", "Recruit", "Views" }) do
			assert(loadfile(ADDON_DIR .. file .. ".lua"))("Olympus", fresh)
		end
		eq(fresh.Who.missing, true, "Who.lua stood in for")
		eq(fresh.Channels.missing, true, "Channels.lua stood in for")
		eq(fresh.Who.StatusLines(), nil, "any other call is a quiet no-op")
		fresh.Who.Search()
		eq(printed[#printed]:find("reopen the game", 1, true) ~= nil, true, "a search says to restart the game")
		fresh.Channels.Send("A", "hi")
		eq(printed[#printed]:find("reopen the game", 1, true) ~= nil, true, "so does a channel message")
	end)
	print = savedPrint
	for k in pairs(SlashCmdList) do SlashCmdList[k] = savedSlash[k] end
	for i = #EVENT_SCRIPTS, savedEvents + 1, -1 do EVENT_SCRIPTS[i] = nil end
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Layer hop (Hop.lua): ask the players on a layer for an invite instead of begging in chat
---------------------------------------------------------------------------

-- Runs fn with the group, combat, invite and popup APIs stubbed, a clock, and every
-- whisper/send/popup/invite recorded. Restores everything afterwards.
local function WithHop(fn)
	local H = ns.Hop
	local names = { "IsInGroup", "GetNumGroupMembers", "IsInRaid", "UnitIsGroupLeader", "UnitIsGroupAssistant",
		"InCombatLockdown", "UnitGUID", "C_PartyInfo", "AcceptGroup", "StaticPopup_Show", "StaticPopup_Hide",
		"StaticPopup_FindVisible", "GetGuildInfo", "UnitName", "UnitFullName" }
	local saved = {}
	for _, n in ipairs(names) do saved[n] = _G[n] end
	local savedSend, savedWhisper, savedReady, savedNow = ns.Comm.Send, ns.Comm.Whisper, ns.Comm.ChannelReady, ns.Now
	local savedRandom, savedAfter, savedMap, savedGap = H.random, H.after, C_Map.GetBestMapForUnit, H.OFFER_GAP
	local savedTrusted = H.Trusted
	local w = { sent = {}, whispered = {}, popups = {}, invited = {}, accepted = 0, left = 0, hidden = {}, clock = 1000000,
		group = 0, lead = false, npc = 7, map = 1453, party = {} }
	local ok, err = pcall(function()
		H.Reset()
		ns.db.layerHelp, ns.db.layerAutoInvite = nil, nil
		ns.Now = function() return w.clock end
		ns.Comm.ChannelReady = function() return true end
		ns.Comm.Send = function(dist, msg) w.sent[#w.sent + 1] = dist .. " " .. msg end
		ns.Comm.Whisper = function(to, msg) w.whispered[#w.whispered + 1] = to .. " " .. msg end
		H.after = function(_, _, f) f() end
		H.random = function(a) return a or 0 end -- ids come out as 1, draws as 0 (always answer, first in line)
		H.OFFER_GAP = 0 -- one offer every 10 s: the tests that look at it set it back
		H.Trusted = function() return true end -- helpers the addon can vouch for: the test of trust sets it back
		IsInGroup = function() return w.group > 0 end
		GetNumGroupMembers = function() return w.group end
		IsInRaid = function() return w.group > 5 end
		UnitIsGroupLeader = function() return w.lead end
		UnitIsGroupAssistant = function() return false end
		InCombatLockdown = function() return w.combat end
		UnitGUID = function() return ("Creature-0-4619-0-%d-68-0000AAA%d"):format(w.npc, w.spawn or 0) end
		C_Map.GetBestMapForUnit = function() return w.map end
		C_PartyInfo = {
			InviteUnit = function(name) w.invited[#w.invited + 1] = name end,
			LeaveParty = function() w.left = w.left + 1 end,
		}
		AcceptGroup = function() w.accepted = w.accepted + 1 end
		StaticPopup_Show = function(name, arg, _, data) w.popups[#w.popups + 1] = { name = name, arg = arg, data = data } end
		StaticPopup_Hide = function(name) w.hidden[#w.hidden + 1] = name end
		StaticPopup_FindVisible = function() return nil end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		UnitName = function(unit) return w.party[unit] end
		UnitFullName = function(unit) if unit == "player" then return "Tester", "Realm" end return w.party[unit] end
		-- We see NPCs: our layer is map 1453, zone UID w.npc (two creatures of it, as a new layer
		-- needs: Layers.Observe; the hold between layers is the stickiness test's).
		ns.Layers.HOLD = 0
		ns.Layers.Reset() -- (each test's clock starts over)
		w.see = function(zoneUID)
			w.npc = zoneUID or w.npc
			for k = 1, 2 do w.spawn = k; ns.Layers.Observe("target") end
		end
		-- (0.9.2: helpers are players who share their layer; the private ones have their own test.)
		if ns.db.shareLocation == nil then ns.db.shareLocation = true end
		fn(w, H)
	end)
	ns.db.shareLocation = nil
	for _, n in ipairs(names) do _G[n] = saved[n] end
	ns.Comm.Send, ns.Comm.Whisper, ns.Comm.ChannelReady, ns.Now = savedSend, savedWhisper, savedReady, savedNow
	H.random, H.after, C_Map.GetBestMapForUnit, H.OFFER_GAP = savedRandom, savedAfter, savedMap, savedGap
	H.Trusted = savedTrusted
	ns.db.layerHelp, ns.db.layerAutoInvite, ns.db.hopKingChoice = nil, nil, nil
	ns.Layers.HOLD = 6
	H.Reset()
	if not ok then error(err, 0) end
end

test("layer hop, helper side: only players on the layer who can invite offer, then invite on request", function()
	WithHop(function(w, H)
		w.see(7)
		-- An ask for our layer: we offer, by whisper to the asker alone.
		H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
		eq(w.whispered[1], "Asker-Realm LO~42~0~0", "alone, no recent invites")
		-- Another layer, another zone, a whisper instead of the channel: nothing.
		H.HandleAsk("CHANNEL", "Other-Realm", "LQ~43~1453~8")
		H.HandleAsk("CHANNEL", "Other-Realm", "LQ~44~1429~7")
		H.HandleAsk("WHISPER", "Other-Realm", "LQ~45~1453~7")
		eq(#w.whispered, 1, "only asks for the layer we are on, from the channel")
		-- The same asker again within a minute: no second offer.
		H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~46~1453~7")
		eq(#w.whispered, 1, "one offer a minute to the same asker")
		-- A crowded layer: most players stay quiet (the draw is above the chance).
		H.random = function(a) return a or 0.99 end
		ns.Layers.Receive("Crowd1-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus" })
		ns.Layers.Receive("Crowd2-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus" })
		assert(H.Chance(1453, 7) < 0.99, "a crowd lowers the chance to answer")
		H.HandleAsk("CHANNEL", "Busy-Realm", "LQ~47~1453~7")
		eq(#w.whispered, 1, "not drawn this time")
		H.random = function(a) return a or 0 end
		-- In a full party, or not its leader: can't invite.
		w.group, w.lead = 5, true
		H.HandleAsk("CHANNEL", "Full-Realm", "LQ~48~1453~7")
		w.group, w.lead = 3, false
		H.HandleAsk("CHANNEL", "Member-Realm", "LQ~49~1453~7")
		eq(#w.whispered, 1, "a full party or a non-leader can't invite")
		w.group, w.lead = 3, true
		H.HandleAsk("CHANNEL", "Leader-Realm", "LQ~50~1453~7")
		eq(w.whispered[2], "Leader-Realm LO~50~3~0", "a leader with a free seat offers, with the group size")
		w.group = 0
		-- Turned off: never asked.
		ns.db.layerHelp = false
		H.HandleAsk("CHANNEL", "Nope-Realm", "LQ~51~1453~7")
		eq(#w.whispered, 2, "/oly layerhelp off")
		ns.db.layerHelp = nil
		-- A request that matches no offer of ours is ignored.
		H.HandleRequest("WHISPER", "Stranger-Realm", "LR~42")
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~999")
		eq(#w.popups, 0, "no offer, no popup")
		-- The asker we offered to: a window with Invite / Not now / Always invite.
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
		eq(#w.popups, 1); eq(w.popups[1].name, "OLYMPUS_HOP_REQUEST"); eq(w.popups[1].arg, "Asker")
		local d = StaticPopupDialogs.OLYMPUS_HOP_REQUEST
		assert(d.button1 and d.button2 and d.button3 and d.OnAlt, "Invite, Not now and Always invite")
		-- While that window is up, another request gets a no at once.
		H.HandleAsk("CHANNEL", "Second-Realm", "LQ~52~1453~7")
		eq(#w.whispered, 2, "busy with a request on screen: no new offers")
		d.OnAccept(nil, w.popups[1].data)
		eq(w.invited[1], "Asker", "Invite sends the invite")
		d.OnAccept(nil, w.popups[1].data)
		eq(#w.invited, 1, "one click, one invite")
		-- Always invite: from then on requests are invited without the window.
		w.clock = w.clock + 61
		H.HandleAsk("CHANNEL", "Leader-Realm", "LQ~53~1453~7")
		H.HandleRequest("WHISPER", "Leader-Realm", "LR~53")
		d.OnAlt(nil, w.popups[2].data)
		eq(ns.db.layerAutoInvite, true); eq(w.invited[2], "Leader")
		w.clock = w.clock + 61
		H.HandleAsk("CHANNEL", "Auto-Realm", "LQ~54~1453~7")
		assert(w.whispered[#w.whispered]:find("^Auto%-Realm LO~54~0~2$"), "the load counts our 2 recent invites: " .. w.whispered[#w.whispered])
		H.HandleRequest("WHISPER", "Auto-Realm", "LR~54")
		eq(w.invited[3], "Auto", "invited without a window"); eq(#w.popups, 2)
		-- Not now: the asker hears no and moves on.
		ns.db.layerAutoInvite = nil
		w.clock = w.clock + 61
		H.HandleAsk("CHANNEL", "Later-Realm", "LQ~55~1453~7")
		H.HandleRequest("WHISPER", "Later-Realm", "LR~55")
		d.OnCancel(nil, w.popups[3].data, "clicked")
		eq(w.whispered[#w.whispered], "Later-Realm LN~55")
		-- A second Not now in a row: five minutes without requests.
		w.clock = w.clock + 61
		H.HandleAsk("CHANNEL", "Again-Realm", "LQ~56~1453~7")
		H.HandleRequest("WHISPER", "Again-Realm", "LR~56")
		d.OnCancel(nil, w.popups[4].data, "timeout")
		eq(H.CanHelp(1453, 7), false, "a break after two no's")
		w.clock = w.clock + H.PAUSE
		eq(H.CanHelp(1453, 7), true, "back after five minutes")
		-- One offer every 10 seconds, whoever asks.
		H.OFFER_GAP = 10
		local n = #w.whispered
		H.HandleAsk("CHANNEL", "One-Realm", "LQ~57~1453~7")
		H.HandleAsk("CHANNEL", "Two-Realm", "LQ~58~1453~7")
		eq(#w.whispered, n + 1, "the second waits")
		w.clock = w.clock + 10
		H.HandleAsk("CHANNEL", "Two-Realm", "LQ~59~1453~7")
		eq(#w.whispered, n + 2)
		-- The request may come without the realm the ask had: it still matches.
		H.HandleRequest("WHISPER", "Two", "LR~59")
		eq(w.popups[5].name, "OLYMPUS_HOP_REQUEST")
	end)
end)

test("layer hop, asker side: draw an offer, move on after a no, accept only that invite, leave after the move", function()
	WithHop(function(w, H)
		w.see(7)
		-- Already on that layer, or in a group: nothing is sent.
		H.Ask(1453, 7, "here")
		w.group = 2
		H.Ask(1453, 8, "Kingy's layer")
		eq(#w.sent, 0, "already there / in a group")
		w.group = 0
		H.Ask(1453, 8, "Kingy's layer")
		eq(w.sent[1], "CHANNEL LQ~1~1453~8")
		H.Ask(1453, 8, "Kingy's layer")
		eq(#w.sent, 1, "one ask at a time")
		-- Offers come in; a wrong id is ignored.
		H.HandleOffer("WHISPER", "Bbb-Realm", "LO~1~3~5")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Ccc-Realm", "LO~9~0~0")
		eq(H.State().count, 2)
		-- Before the window closes nobody is asked; after, one is drawn.
		H.Tick()
		eq(#w.whispered, 0)
		w.clock = w.clock + H.WINDOW
		H.Tick()
		eq(w.whispered[1], "Aaa-Realm LR~1", "the draw picks one helper")
		-- A no from someone else is ignored; from the helper, the next one is asked.
		H.HandleNo("WHISPER", "Ccc-Realm", "LN~1")
		eq(#w.whispered, 1)
		H.HandleNo("WHISPER", "Aaa-Realm", "LN~1")
		eq(w.whispered[2], "Bbb-Realm LR~1")
		-- Someone else's invite is left alone; the helper's is accepted for us.
		H.OnInvite("Zed")
		eq(w.accepted, 0)
		H.OnInvite("Bbb")
		eq(w.accepted, 1); eq(w.hidden[1], "PARTY_INVITE")
		w.group = 2
		H.OnRoster()
		eq(H.State().phase, "joined")
		-- The move shows as the new zone UID: the addon leaves the group on its own.
		w.see(8)
		H.OnLayer()
		eq(w.left, 1); eq(H.State().phase, "done"); eq(#w.popups, 0, "no window: it is done")
		-- Nobody answers: the ask ends after two windows, and the next one waits.
		w.group = 0
		w.clock = w.clock + H.ASK_GAP
		H.Ask(1453, 9, "far")
		w.clock = w.clock + H.WINDOW * 2
		H.Tick()
		eq(H.State().phase, "asking", "offers can take a few seconds: still waiting")
		w.clock = w.clock + H.NOBODY
		H.Tick()
		eq(H.State().phase, "done")
		-- In the group but no NPC seen: offer to leave anyway after a while.
		w.clock = w.clock + H.ASK_GAP
		H.Ask(1453, 7, "back")
		H.HandleOffer("WHISPER", "Ddd-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		H.OnInvite("Ddd")
		w.group = 2
		H.OnRoster()
		w.clock = w.clock + H.JOIN_WAIT
		H.Tick()
		eq(w.popups[1].name, "OLYMPUS_HOP_LEAVE"); eq(w.popups[1].arg, ns.L.HOP_MAYBE_MOVED)
		-- The helper's addon lets us go: only the helper, only our ask.
		H.HandleRelease("WHISPER", "Eee-Realm", "LX~1")
		H.HandleRelease("WHISPER", "Ddd-Realm", "LX~2")
		eq(w.left, 1, "someone else, another ask: ignored")
		H.HandleRelease("WHISPER", "Ddd-Realm", "LX~1")
		eq(w.left, 2); eq(H.State().phase, "done"); eq(w.hidden[#w.hidden], "OLYMPUS_HOP_LEAVE")
		StaticPopupDialogs.OLYMPUS_HOP_LEAVE.OnAccept()
		-- In another zone: a zone UID means nothing there, nothing is asked.
		w.group, w.map = 0, 1429
		w.clock = w.clock + H.ASK_GAP
		local before = #w.sent
		H.Ask(1453, 8, "far away")
		eq(#w.sent, before, "not in that zone: nothing sent")
	end)
end)

test("layer hop: the target layer is taken on its first creature, whatever the hold", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.HOLD = 6
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		w.group, w.party.party1 = 2, "Aaa"
		H.OnInvite("Aaa")
		H.OnRoster()
		eq(H.State().phase, "joined")
		-- One creature of the King's layer, a second after one of ours: that is the move.
		w.npc, w.spawn = 8, 5
		ns.Layers.Observe("target")
		eq(ns.Layers.Mine().zoneUID, 8, "the hop's target at once")
	end)
end)

test("layer hop, asker side: a friend's group is never left, a late helper still counts, an old window ends nothing", function()
	WithHop(function(w, H)
		w.see(7)
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Bbb-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		eq(H.State().helper, "Aaa-Realm")
		-- A friend invites us and we accept by hand: the hop is off, and we stay with the friend.
		w.group, w.party.party1 = 2, "Friend"
		H.OnRoster()
		eq(H.State().phase, "done")
		w.see(8)
		H.OnLayer()
		eq(w.left, 0, "the addon never leaves a friend's group")
		-- The first helper was slow: their late invite still counts after we moved on.
		w.group, w.party = 0, {}
		w.clock = w.clock + H.ASK_GAP
		w.see(7)
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Bbb-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		w.clock = w.clock + H.WAIT
		H.Tick()
		eq(H.State().helper, "Bbb-Realm", "moved on")
		H.OnInvite("Aaa")
		eq(w.accepted, 1); eq(H.State().helper, "Aaa-Realm")
		w.group, w.party.party1 = 2, "Aaa"
		H.OnRoster()
		eq(H.State().phase, "joined")
		-- No move seen: the leave window, for this ask only.
		w.clock = w.clock + H.JOIN_WAIT
		H.Tick()
		local old = w.popups[#w.popups]
		eq(old.name, "OLYMPUS_HOP_LEAVE"); eq(old.data, H.State())
		-- We leave by hand: that window goes with the ask.
		w.group, w.party = 0, {}
		H.OnRoster()
		eq(H.State().phase, "done"); eq(w.hidden[#w.hidden], "OLYMPUS_HOP_LEAVE")
		-- Had it stayed, clicking it later ends nothing new.
		w.clock = w.clock + H.ASK_GAP
		H.Ask(1453, 8, "Kingy's layer")
		StaticPopupDialogs.OLYMPUS_HOP_LEAVE.OnAccept(nil, old.data)
		StaticPopupDialogs.OLYMPUS_HOP_LEAVE.OnCancel(nil, old.data)
		eq(H.State().phase, "asking", "an old window ends nothing")
	end)
end)

test("layer hop: the draw spreads askers, favouring players alone and with fewer invites", function()
	local offers = {
		["A-Realm"] = { name = "A-Realm", group = 0, load = 0 }, -- weight 2
		["B-Realm"] = { name = "B-Realm", group = 3, load = 0 }, -- weight 1
		["C-Realm"] = { name = "C-Realm", group = 0, load = 3 }, -- weight 0.5
	}
	math.randomseed(7)
	local got = { ["A-Realm"] = 0, ["B-Realm"] = 0, ["C-Realm"] = 0 }
	for _ = 1, 3500 do
		local o = ns.Hop.Pick(offers, {})
		got[o.name] = got[o.name] + 1
	end
	assert(got["A-Realm"] > 1700 and got["A-Realm"] < 2300, "A " .. got["A-Realm"])
	assert(got["B-Realm"] > 800 and got["B-Realm"] < 1200, "B " .. got["B-Realm"])
	assert(got["C-Realm"] > 350 and got["C-Realm"] < 650, "C " .. got["C-Realm"])
	eq(ns.Hop.Pick(offers, { ["A-Realm"] = true, ["B-Realm"] = true, ["C-Realm"] = true }), nil, "all tried")
end)

local RealTrusted = ns.Hop.Trusted
test("layer hop: only a helper the addon can vouch for gets their invite accepted for us", function()
	WithHop(function(w, H)
		local real = RealTrusted
		-- Who counts: a guildmate, a Lord or Captain the census names, a player seen on that layer.
		local savedRank, savedGuilds = ns.Roster.RankOf, ns.rdb.guilds
		ns.Roster.RankOf = function(name) if ns.ShortName(name) == "Mate" then return 5 end end
		ns.rdb.guilds = SampleGuilds()
		eq(real("Mate-Realm", 1453, 8), true, "a guildmate")
		eq(real("Capt-Realm", 1453, 8), true, "a Captain the census names")
		eq(real("Stranger-Realm", 1453, 8), false, "anyone else")
		ns.Layers.Receive("Seen-Realm", { mapID = 1453, zoneUID = 8, rank = 9, guild = "Olympus IV" })
		eq(real("Seen-Realm", 1453, 8), false, "a layer announcement is only its sender's word")
		ns.Roster.RankOf, ns.rdb.guilds = savedRank, savedGuilds
		-- A stranger's offer can be drawn, but their invite is left to the game's window.
		H.Trusted = function(name) return ns.ShortName(name) == "Tru" end
		w.see(7)
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		eq(H.State().helper, "Aaa-Realm")
		w.clock = w.clock + H.WAIT - 5
		H.OnInvite("Aaa")
		eq(w.accepted, 0, "not accepted for us: the player clicks")
		eq(H.State().phase, "requested")
		-- The wait starts over from the invite: nobody else is asked while it is on screen.
		w.clock = w.clock + 10
		H.Tick()
		eq(H.State().helper, "Aaa-Realm"); eq(#w.whispered, 1, "no second helper asked")
		-- The player accepts by hand; the game has not named the group's members yet.
		w.group, w.party.party1 = 2, nil
		H.OnRoster()
		eq(H.State().phase, "joined", "the helper's group, members not named yet")
		-- A friend's group while the helper's invite is out is not the hop's.
		w.group, w.party = 0, {}
		H.Reset()
		w.clock = w.clock + H.ASK_GAP
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW
		H.Tick()
		H.OnInvite("Aaa")
		w.group, w.party.party1 = 2, "Friend"
		H.OnRoster()
		eq(H.State().phase, "done", "a friend's group: the hop is off")
		w.see(8)
		H.OnLayer()
		eq(w.left, 0, "and never left")
		-- A helper the addon can vouch for is drawn first, and accepted for us.
		w.group, w.party = 0, {}
		w.see(7)
		H.Reset()
		w.clock = w.clock + H.ASK_GAP
		H.Ask(1453, 8, "Kingy's layer")
		H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Tru-Realm", "LO~1~1~0")
		-- Mid draw: alone counts double (Aaa 2, Tru 1), vouched for three times (Tru 3).
		H.random = function(a) return a or 0.5 end
		w.clock = w.clock + H.WINDOW
		H.Tick()
		eq(H.State().helper, "Tru-Realm", "vouched for: weighs more")
		H.OnInvite("Tru")
		eq(w.accepted, 1)
	end)
end)

test("layer hop: 'For Olympus!' shows a line to stop it, and /oly layerauto off stops it too", function()
	WithHop(function(w, H)
		ns.rdb.guilds = SampleGuilds()
		ns.Layers.Receive("Asmongold-Realm", { mapID = 1453, zoneUID = 9, rank = 0, guild = "Olympus" })
		w.see(9)
		eq(#H.KingLines(), 1, "on his layer, nothing on its own: one line")
		H.ChooseKing("auto")
		local lines = H.KingLines()
		eq(#lines, 2)
		assert(lines[2].text:find(ns.L.HOP_AUTO_LINE:format("Asmond"), 1, true), lines[2].text)
		lines[2].onClick()
		eq(#H.KingLines(), 1, "stopped")
		ns.db.hopKingChoice = "auto"
		H.ChooseKing("auto")
		eq(#H.KingLines(), 2)
		H.SetAuto(false)
		eq(#H.KingLines(), 1, "/oly layerauto off")
		eq(ns.db.hopKingChoice, "manual", "and the kept answer too")
		-- "Always invite" everywhere.
		ns.db.layerAutoInvite = true
		eq(#H.KingLines(), 2)
		ns.rdb.guilds = {}
		ns.Layers.Reset()
	end)
end)

test("layer hop: the King's line needs a report nobody disputes, and never one right after login", function()
	WithHop(function(w, H)
		ns.rdb.guilds = { ["Olympus"] = { total = 1, online = 1, zones = {}, t = os.time(), leader = "Evil", leaderOnline = true } }
		ns.Now = function() return os.time() end
		eq(H.King(), nil, "nobody else names him")
		local said
		local savedPrint = ns.Print
		ns.Print = function(m) said = m end
		H.AskKing()
		ns.Print = savedPrint
		eq(said, ns.L.HOP_KING_CHECKING:format("Asmond"), "not 'offline': still being confirmed")
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1, online = 1, zones = {}, t = os.time(), leader = "Asmongold Asmongler", leaderOnline = true }, "W1-Realm", "W2-Realm") }
		eq(H.King().name, "Asmond")
		-- One report is enough for the line while nobody disagrees (the Crown's powers need two).
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1, online = 1, zones = {}, t = os.time(), leader = "Asmongold Asmongler", leaderOnline = true }, "W1-Realm") }
		eq(H.King().name, "Asmond", "one reporter")
		eq(H.King(true), nil, "not strictly: 'For Olympus!' does not invite on its own for him")
		eq(ns.Data.KnownRank("Asmongold Asmongler-Realm", "Olympus"), nil, "but no Crown powers from one")
		-- Right after login a lone report proves nothing: the real ones have not come yet.
		local loginAt = ns.Comm.loginAt
		ns.Comm.loginAt = ns.Now() - 10
		eq(H.King(), nil, "just logged in")
		ns.Comm.loginAt = loginAt
		-- An attacker's report naming himself: alone right after login, nothing. (0.9.1: against
		-- the real reporter it no longer even ties: a report naming anyone but the King the addon
		-- knows by name counts for nothing, GitHub issue #18.)
		ns.rdb.guilds = {}
		local r = { guild = "Olympus", total = 900, online = 90, leader = "Atk", leaderOnline = true, users = 1, zones = {}, officers = {},
			ranks = {}, top = {}, faction = "Alliance" }
		ns.Comm.loginAt = ns.Now() - 10
		ns.Data.Receive(r, "Atk-Realm")
		eq(H.King(), nil, "a lone forged report at login")
		ns.Comm.loginAt = loginAt
		local real = { guild = "Olympus", total = 1000, online = 200, leader = "Asmongold Asmongler", leaderOnline = true, users = 5, zones = {}, officers = {},
			ranks = {}, top = {}, faction = "Alliance" }
		ns.Data.Receive(real, "Honest-Realm")
		eq(H.King() and H.King().name, "Asmond", "forged against real: the forged report counted for nothing")
		-- A same-named character on another realm can't vouch for itself.
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1, online = 1, zones = {}, t = os.time(), leader = "Atk", leaderOnline = true }, "Atk-Elsewhere") }
		eq(H.King(), nil, "its own vote from another realm")
		-- Two reports disagree about the leader: no line.
		local g = ns.rdb.guilds["Olympus"]
		g.vouch["W2-Realm"] = { t = g.t, sig = "other", ranks = { ["Evil-Realm"] = 0 } }
		eq(H.King(), nil, "a disagreement: nobody")
		ns.rdb.guilds = {}
	end)
end)

test("layer hop: the King's layer line tops the Census and the Realm only while he is online", function()
	WithHop(function(w, H)
		ns.rdb.guilds = SampleGuilds()
		-- Online, layer not announced yet: the line explains.
		local line = H.KingLine()
		assert(line and line.onClick, "shown while the King is online")
		line.onClick()
		eq(#w.sent, 0, "his layer is not known yet: nothing asked")
		-- His addon announces his layer: one click asks for it.
		ns.Layers.Receive("Asmongold-Realm", { mapID = 1453, zoneUID = 9, rank = 0, guild = "Olympus" })
		local k = H.King()
		eq(k.name, "Asmond", "the name the army calls him, whatever his character's"); eq(k.zoneUID, 9)
		-- In another zone: the button says where he is, and asks nothing.
		w.see(7)
		w.map = 1429
		local lines = H.KingLines()
		eq(#lines, 2); assert(lines[2].text:find(ns.L.HOP_KING_GO:format(H.ZoneName(1453)), 1, true), lines[2].text)
		lines[1].onClick()
		eq(#w.sent, 0, "not in his zone: nothing asked")
		w.map = 1453
		eq(#H.KingLines(), 1, "in his zone: the button alone")
		assert(H.KingLine().text:find("Ask invite for Asmond Layer", 1, true), H.KingLine().text)
		H.KingLine().onClick()
		eq(w.sent[1], "CHANNEL LQ~1~1453~9", "asks for the King's layer")
		assert(ns.Views.Build("census")[1].text:find("Asmond", 1, true), "tops the Census")
		assert(ns.Views.RealmLines()[1].text:find("Asmond", 1, true), "tops the Realm")
		-- On his layer: says so, nothing to click.
		H.Reset()
		w.see(9)
		line = H.KingLine()
		assert(line.text:find(ns.L.HOP_KING_HERE:format("Asmond"), 1, true) and not line.onClick, line.text)
		-- Offline: no line at all.
		ns.rdb.guilds["Olympus"].leaderOnline = false
		eq(H.KingLine(), nil, "not online: no line")
		assert(not ns.Views.Build("census")[1].onClick or ns.Views.Build("census")[1].cols, "the Census starts with the guilds")
		-- The King himself never gets the line, nor requests.
		ns.rdb.guilds["Olympus"].leaderOnline = true
		GetGuildInfo = function() return "Olympus", "King", 0 end
		local savedMe = ns.me
		ns.me = "Asmongold Asmongler-Realm" -- (the character the addon knows as the King)
		local line, help = H.KingLine(), H.CanHelp(1453, 9)
		ns.me = savedMe
		eq(line, nil, "the King's own window")
		eq(help, false, "the King is never asked")
		ns.rdb.guilds = {}
	end)
end)

test("layer hop: /oly hop, layerhelp and layerauto, and the status line", function()
	WithHop(function(w, H)
		SlashCmdList.OLYMPUS("layerhelp off")
		eq(ns.db.layerHelp, false)
		SlashCmdList.OLYMPUS("layerhelp on")
		eq(ns.db.layerHelp, true)
		SlashCmdList.OLYMPUS("layerauto on")
		eq(ns.db.layerAutoInvite, true)
		SlashCmdList.OLYMPUS("layerauto off")
		eq(ns.db.layerAutoInvite, false)
		SlashCmdList.OLYMPUS("hop") -- no King in the census: just a message
		eq(#w.sent, 0)
		assert(H.StatusLine():find("help=true auto=false", 1, true), H.StatusLine())
	end)
end)

test("layer hop: alone on the King's layer, a window asks whether the addon may invite and let go", function()
	WithUI(function()
		WithHop(function(w, H)
			H.prompt = nil
			-- The King is on 1453 / 9 (SampleGuilds: online); we stand there too.
			ns.Layers.Receive("Asmongold-Realm", { mapID = 1453, zoneUID = 9, rank = 0, guild = "Olympus" })
			w.see(9)
			w.group = 2
			H.CheckKingPrompt()
			eq(H.prompt, nil, "in a group: not asked")
			w.group = 0
			H.CheckKingPrompt()
			local f = H.prompt
			assert(f and f:IsShown(), "alone on his layer: the window")
			assert(f.text:GetText():find("Asmond is online and you are on his layer", 1, true), f.text:GetText())
			-- Left to right: the way out (grey), by hand, and For Olympus! (lit), all one size.
			eq(f.buttons[1]:GetText(), "Can't right now"); eq(f.buttons[2]:GetText(), "Invite manually")
			eq(f.buttons[3]:GetText(), "For Olympus!"); eq(f.checkLabel:GetText(), "Don't ask me again")
			eq(f.buttons[3]:GetHeight(), f.buttons[1]:GetHeight(), "the same size as the others")
			local total = 0
			for _, b in ipairs(f.buttons) do
				assert(b:GetWidth() >= b:GetFontString():GetUnboundedStringWidth() + 20, "fits: " .. b:GetText())
				total = total + b:GetWidth()
			end
			assert(total + 16 <= f:GetWidth() - 40, "three buttons inside the window")
			eq(f.check:GetChecked(), false, "not ticked to start")
			-- For Olympus!, and don't ask again.
			f.check:SetChecked(true)
			f.buttons[3]:Click()
			eq(f:IsShown(), false); eq(ns.db.hopKingChoice, "auto", "the answer is kept")
			-- Requests are invited on their own, no window.
			H.HandleAsk("CHANNEL", "Fan-Realm", "LQ~42~1453~9")
			H.HandleRequest("WHISPER", "Fan-Realm", "LR~42")
			eq(w.invited[1], "Fan"); eq(#w.popups, 0)
			-- The next one while the first is in our party: guests only, invited too.
			w.group, w.lead, w.party.party1 = 2, true, "Fan"
			w.clock = w.clock + 5
			H.HandleAsk("CHANNEL", "Fan2-Realm", "LQ~43~1453~9")
			H.HandleRequest("WHISPER", "Fan2-Realm", "LR~43")
			eq(w.invited[2], "Fan2"); eq(#w.popups, 0)
			w.group, w.party.party2 = 3, "Fan2"
			-- Their time is up: their addon is asked to leave (only a click may remove someone),
			-- and only those still with us.
			w.clock = w.clock + H.GUEST_TIME
			w.group, w.party.party2 = 2, nil
			H.Tick(); H.Tick()
			local lx = {}
			for _, m in ipairs(w.whispered) do if m:find(" LX~", 1, true) then lx[#lx + 1] = m end end
			eq(#lx, 1, "once, to the one still here"); eq(lx[1], "Fan-Realm LX~42")
			-- A friend in our party: never an invite into it, the window instead.
			w.group, w.party.party2 = 3, "Friend"
			H.HandleAsk("CHANNEL", "Fan3-Realm", "LQ~44~1453~9")
			H.HandleRequest("WHISPER", "Fan3-Realm", "LR~44")
			eq(#w.invited, 2); eq(w.popups[1].name, "OLYMPUS_HOP_REQUEST")
			-- Kept: never asked again, even next login.
			H.Reset(); w.group, w.party = 0, {}
			H.CheckKingPrompt()
			eq(f:IsShown(), false, "Don't ask me again")
			-- Can't right now, this login only: no window again, and no requests for his layer.
			ns.db.hopKingChoice = nil
			H.Reset()
			H.CheckKingPrompt()
			eq(f:IsShown(), true, "asked again: the box was reset")
			eq(f.check:GetChecked(), false)
			f.buttons[1]:Click()
			eq(ns.db.hopKingChoice, nil, "box not ticked: this login only")
			eq(H.CanHelp(1453, 9), false, "can't right now")
			H.CheckKingPrompt()
			eq(f:IsShown(), false, "once a login")
			-- Invite manually: the window per request.
			H.Reset()
			H.CheckKingPrompt()
			f.buttons[2]:Click()
			eq(H.CanHelp(1453, 9), true)
			assert(H.StatusLine():find("king=manual", 1, true), H.StatusLine())
			-- Escape: the usual window, this login.
			H.Reset()
			H.CheckKingPrompt()
			f:Hide()
			assert(H.StatusLine():find("king=manual", 1, true), H.StatusLine())
			-- /oly layerhelp on forgets a kept "no".
			ns.db.hopKingChoice = "no"
			SlashCmdList.OLYMPUS("layerhelp on")
			eq(ns.db.hopKingChoice, nil)
			-- The King himself is never asked; nor players on another layer.
			H.Reset()
			w.see(7)
			H.CheckKingPrompt()
			eq(f:IsShown(), false, "another layer")
			w.see(9)
			GetGuildInfo = function() return "Olympus", "King", 0 end
			local savedMe = ns.me
			ns.me = "Asmongold Asmongler-Realm" -- (the character the addon knows as the King)
			H.CheckKingPrompt()
			ns.me = savedMe
			eq(f:IsShown(), false, "the King")
			H.prompt = nil
		end)
	end)
end)

test("Throne: the King's map button fits its label, says whether he is shown, and changes at once", function()
	WithUI(function()
		local savedGuild, savedSend, savedPos, savedMe = GetGuildInfo, ns.Comm.Send, C_Map.GetPlayerMapPosition, ns.me
		local ok, err = pcall(function()
			ns.db.throneLocation = nil
			GetGuildInfo = function() return "Olympus", "King", 0 end
			ns.me = "Asmongold Asmongler-Realm"
			ns.Comm.Send = function() end
			C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.51 end } end
			local w, UI = ForeverWorld(true)
			CommunitiesFrame:Show(); w.buttons[1]:Click()
			UI.SelectTab("throne")
			local main = OlympusFrameHD
			-- His buttons: the court and his crown (no agenda to cancel).
			local b
			for _, d in ipairs(main.detailButtons) do
				if d:IsShown() and d:GetText():find(ns.L.THRONE_LOCATION_ON, 1, true) then b = d end
			end
			assert(b, "the map button")
			eq(b:IsShown(), true)
			assert(b:GetText():find(ns.L.THRONE_LOCATION_ON, 1, true) and b:GetText():find(ns.CROWN_ICON, 1, true), b:GetText())
			-- Every button as wide as its label, the three inside the box.
			local right = 6
			for _, d in ipairs(main.detailButtons) do
				if d:IsShown() then
					eq(d:GetFontString():IsTruncated(), false, d:GetText())
					right = right + d:GetWidth() + 3
				end
			end
			assert(right - 3 <= main.detail:GetWidth() - 6, "inside the box: " .. right .. " of " .. main.detail:GetWidth())
			-- The tooltip: what it does, and that he is hidden now.
			b:Fire("OnEnter")
			eq(GameTooltip.owner, b)
			eq(GameTooltip.lines[1], ns.L.THRONE_LOCATION); eq(GameTooltip.lines[2], ns.L.THRONE_LOCATION_TIP)
			eq(GameTooltip.lines[3], ns.L.THRONE_LOCATION_NOW_OFF)
			-- A click: shown, the label and the tooltip change at once, the page says so on top.
			b:Click()
			eq(ns.db.throneLocation, true)
			assert(b:GetText():find(ns.L.THRONE_LOCATION_OFF, 1, true), b:GetText())
			eq(GameTooltip.lines[3], ns.L.THRONE_LOCATION_NOW_ON)
			assert(ns.King.Build()[1].text:find(ns.L.THRONE_LOCATION_LIVE, 1, true), "on top of the page")
			for _, d in ipairs(main.detailButtons) do
				if d:IsShown() then eq(d:GetFontString():IsTruncated(), false, "longer label, still fits: " .. d:GetText()) end
			end
			b:Click()
			eq(ns.db.throneLocation, false)
		end)
		GetGuildInfo, ns.Comm.Send, C_Map.GetPlayerMapPosition, ns.me = savedGuild, savedSend, savedPos, savedMe
		ns.db.throneLocation = nil
		ns.King.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("Treasury: the King's three switches say on hover who sees each part (hidden: only he and the Treasurer)", function()
	WithUI(function()
		local savedGuild, savedSend, savedSplit, savedMe = GetGuildInfo, ns.Comm.Send, ns.splitNames, ns.me
		local ok, err = pcall(function()
			ns.rdb.treasuryFlags = nil
			ns.splitNames = true -- Forever: a Treasurer's name (first and surname) can be there
			GetGuildInfo = function() return "Olympus", "King", 0 end
			ns.me = "Asmongold Asmongler-Realm"
			ns.Comm.Send = function() end
			local w, UI = ForeverWorld(true)
			CommunitiesFrame:Show(); w.buttons[1]:Click()
			UI.SelectTab("treasury")
			local main = OlympusFrameHD
			local L = ns.L
			local switches = {}
			for _, d in ipairs(main.detailButtons) do if d:IsShown() then switches[#switches + 1] = d end end
			eq(#switches, 3)
			for i, part in ipairs({ "BALANCE", "RANKING", "BOOK" }) do
				local b = switches[i]
				eq(b:GetText(), L["TREASURY_FLAG_" .. part .. "_HIDDEN"]); eq(b:GetFontString():IsTruncated(), false, b:GetText())
				b:Fire("OnEnter")
				eq(GameTooltip.lines[1], L["TREASURY_FLAG_" .. part .. "_HIDDEN"]); eq(GameTooltip.lines[2], L["TREASURY_FLAG_" .. part .. "_TIP"])
				eq(GameTooltip.lines[3], L.TREASURY_FLAG_HIDDEN_TIP:format(L["TREASURY_PART_" .. part]), "only he and the Treasurer")
				-- A click: the army sees it, the label and the tooltip change at once.
				b:Click()
				eq(switches[i]:GetText(), L["TREASURY_FLAG_" .. part .. "_SHOWN"])
				eq(GameTooltip.lines[3], L.TREASURY_FLAG_SHOWN_TIP:format(L["TREASURY_PART_" .. part]))
				eq(switches[i]:GetFontString():IsTruncated(), false, switches[i]:GetText())
			end
		end)
		GetGuildInfo, ns.Comm.Send, ns.splitNames, ns.me = savedGuild, savedSend, savedSplit, savedMe
		ns.rdb.treasuryFlags = nil
		ns.Treasury.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("Throne: the King shows himself on the map with a button, everyone checks it is him", function()
	local K = ns.King
	local savedGuild, savedSend, savedNow, savedPos, savedMap = GetGuildInfo, ns.Comm.Send, ns.Now, C_Map.GetPlayerMapPosition, C_Map.GetBestMapForUnit
	local savedMe = ns.me
	local sent, clock = {}, 2000000
	local ok, err = pcall(function()
		K.Reset()
		ns.db.throneLocation = nil
		ns.Now = function() return clock end
		ns.Comm.Send = function(dist, msg) sent[#sent + 1] = dist .. " " .. msg end
		C_Map.GetBestMapForUnit = function() return 1453 end
		C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.51 end } end
		-- Not the King: the button does nothing.
		GetGuildInfo = function() return "Olympus II", "Officer", 1 end
		K.ToggleLocation()
		eq(#sent, 0); eq(K.SharingLocation(), false, "off by default")
		-- The King turns it on: his position goes out on the channel.
		GetGuildInfo = function() return "Olympus", "King", 0 end
		ns.me = "Asmongold Asmongler-Realm"
		K.ToggleLocation()
		eq(K.SharingLocation(), true)
		assert(sent[1]:find("^CHANNEL T1~P~%d+~Olympus~1453~420~510$"), sent[1])
		local id = sent[1]:match("T1~P~(%d+)")
		-- Everyone else: only the King's own message draws the crown.
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.me = savedMe
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 90, zones = {}, t = os.time(), leader = "Asmongold Asmongler", realm = "Realm" }, "W1-Realm", "W2-Realm") }
		K.HandleCommand("CHANNEL", "Faker-Realm", ("T1~P~%s~Olympus~100~100~100"):format(id))
		eq(K.Location(), nil, "not the King: no crown")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~P~%s~Olympus~1453~420~510"):format(id))
		local at = K.Location()
		eq(at.mapID, 1453); eq(at.x, 0.42); eq(at.y, 0.51); eq(at.name, "Asmond")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~P~%s~Olympus~1453~2000~5"):format(id))
		eq(K.Location().x, 0.42, "off the map: ignored")
		-- No news for a while: the crown goes away on its own.
		clock = clock + K.LOCATION_EXPIRE + 1
		eq(K.Location(), nil, "expired")
		-- He hides it again: gone at once.
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~P~%s~Olympus~1453~420~510"):format(id))
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~Q~%s~Olympus"):format(id))
		eq(K.Location(), nil, "hidden")
		GetGuildInfo = function() return "Olympus", "King", 0 end
		ns.me = "Asmongold Asmongler-Realm"
		K.ToggleLocation()
		eq(K.SharingLocation(), false)
		assert(sent[#sent]:find("^CHANNEL T1~Q~%d+~Olympus$"), sent[#sent])
	end)
	GetGuildInfo, ns.Comm.Send, ns.Now, C_Map.GetPlayerMapPosition, C_Map.GetBestMapForUnit = savedGuild, savedSend, savedNow, savedPos, savedMap
	ns.me = savedMe
	ns.db.throneLocation = nil
	ns.rdb.guilds = {}
	K.Reset()
	if not ok then error(err, 0) end
end)


---------------------------------------------------------------------------
-- Workshop (Workshop.lua): the author's tab, roll call, "please update", bug reports
---------------------------------------------------------------------------

local AUTHOR_FULL = "Faladoriel Skylance-ClassicBetaPvP"

-- Runs fn(w, W) with sends, whispers, popups and time recorded; `me` is who we are.
local function WithWorkshop(me, fn)
	local W = ns.Workshop
	local saved = { me = ns.me, Send = ns.Comm.Send, Whisper = ns.Comm.Whisper, Now = ns.Now, after = W.after, random = W.random,
		Show = StaticPopup_Show, Guild = GetGuildInfo, Build = GetBuildInfo, Level = UnitLevel, Class = UnitClass, Ready = ns.Comm.ChannelReady,
		errors = ns.allErrors, guilds = ns.rdb.guilds, Print = ns.Print }
	local w = { sent = {}, whispered = {}, popups = {}, clock = 5000000, printed = {} }
	local ok, err = pcall(function()
		W.Reset()
		ns.me = me
		ns.Now = function() return w.clock end
		ns.Comm.Send = function(dist, msg, key) w.sent[#w.sent + 1] = { dist = dist, msg = msg, key = key } end
		ns.Comm.Whisper = function(to, msg, key) w.whispered[#w.whispered + 1] = { to = to, msg = msg, key = key } end
		ns.Comm.ChannelReady = function() return true end
		ns.Print = function(m) w.printed[#w.printed + 1] = m end
		W.after = function(_, _, f) f() end
		W.random = function(a, b) if a then return b or a end return 0.5 end
		StaticPopup_Show = function(name, a, b, data) w.popups[#w.popups + 1] = { name = name, a = a, b = b, data = data } end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		GetBuildInfo = function() return "1.60.1", "1", "x", 16001 end
		UnitLevel = function() return 17 end
		UnitClass = function() return "Mage", "MAGE" end
		ns.allErrors = {}
		ns.rdb.guilds = {}
		fn(w, W)
	end)
	ns.me, ns.Comm.Send, ns.Comm.Whisper, ns.Now, W.after, W.random = saved.me, saved.Send, saved.Whisper, saved.Now, saved.after, saved.random
	StaticPopup_Show, GetGuildInfo, GetBuildInfo, UnitLevel, UnitClass = saved.Show, saved.Guild, saved.Build, saved.Level, saved.Class
	ns.Comm.ChannelReady, ns.allErrors, ns.rdb.guilds, ns.Print = saved.Ready, saved.errors, saved.guilds, saved.Print
	W.Reset()
	if not ok then error(err, 0) end
end

test("Workshop: the author's alone, and his test characters' (Dev.lua)", function()
	WithWorkshop("Tester-Realm", function(w, W)
		eq(W.Visible(), false, "anyone else: no tab")
		local savedDev, savedName = ns.devWorkshop, UnitName
		UnitName = function() return "Peepyn" end
		ns.devWorkshop = { Peepyn = true }
		eq(W.Visible(), true, "the author's test character"); eq(W.Preview(), true)
		ns.devWorkshop, UnitName = savedDev, savedName
		ns.me = AUTHOR_FULL
		eq(W.IsAuthor(), true); eq(W.Visible(), true); eq(W.Preview(), false)
		ns.me = "Faladoriel-Realm"
		eq(W.IsAuthor(), false, "his first name alone is someone else's")
	end)
end)

test("Workshop roll call: only the author asks, each addon answers once with what works", function()
	WithWorkshop(AUTHOR_FULL, function(w, W)
		ns.rdb.guilds = { ["Olympus II"] = { t = w.clock, users = 40, online = 90, versions = { ["0.8.2"] = 30, ["0.8.1"] = 10 } } }
		W.RollCall()
		eq(w.sent[1].msg, ("V1~99999~100"), "the whole army while small")
		W.RollCall()
		eq(#w.sent, 1, "once every 5 minutes")
		-- Answers: stored once each, only for this roll call.
		W.HandleAnswer("WHISPER", "Ann-Realm", "V2~99999~0.8.1~Olympus IV~Forever~hd~cm~2~12~MA")
		W.HandleAnswer("WHISPER", "Ann-Realm", "V2~99999~0.8.2~Olympus IV~Forever~hd~cm~0~12~MA")
		W.HandleAnswer("WHISPER", "Bob-Realm", "V2~12~0.8.2~Olympus IV~Forever~hd~cm~0~12~MA")
		W.HandleAnswer("CHANNEL", "Cid-Realm", "V2~99999~0.8.2~Olympus IV~Era~old~m~0~12~MA")
		eq(W.State().count, 1, "one answer each, this roll call's, by whisper")
		local a = W.State().answers["Ann-Realm"]
		eq(a.version, "0.8.1"); eq(a.errors, 2); eq(a.client, "Forever"); eq(a.flags, "cm")
		-- The tab: installs from the reports, the roll call, who needs attention.
		local lines = W.Build()
		local text = {}
		for _, l in ipairs(lines) do text[#text + 1] = (l.text or "") .. " " .. (l.right or "") end
		text = table.concat(text, "\n")
		assert(text:find(ns.L.WORKSHOP_USERS:format(40, 1), 1, true), text)
		assert(text:find("Ann", 1, true) and text:find(ns.L.WORKSHOP_ERRORS:format(2), 1, true), text)
		local report = W.ReportText()
		assert(not report:find("|c", 1, true), "no colour codes in the Discord text")
		-- Too late: no longer counted.
		w.clock = w.clock + W.ROLL_OPEN + 1
		W.HandleAnswer("WHISPER", "Dan-Realm", "V2~99999~0.8.2~Olympus IV~Forever~hd~cm~0~12~MA")
		eq(W.State().count, 1)
	end)
	WithWorkshop("Tester-Realm", function(w, W)
		-- A player's addon: answers the author, once per ROLL_GAP; ignores anyone else.
		W.HandleRoll("CHANNEL", "Faladoriel-Realm", "V1~7~100")
		eq(#w.whispered, 0, "not the author")
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~7~100")
		eq(w.whispered[1].to, AUTHOR_FULL)
		local msg = w.whispered[1].msg
		-- (0.9.2: version, client and channel state only; the character's guild, level and class,
		-- the window style and the error count no longer go out.)
		assert(msg:find(("^V2~7~%s~~Forever~~c[crk]*~0~0~$"):format(ns.VERSION:gsub("%.", "%%."))), msg)
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~8~100")
		eq(#w.whispered, 1, "once per ROLL_GAP")
		eq(W.AuthorOnline(), true, "a roll call says the author is online")
		-- A share: only some answer.
		W.Reset()
		W.random = function(a, b) if a then return b or a end return 0.5 end
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~9~10")
		eq(#w.whispered, 1, "drew 100 > 10: no answer")
		eq(W.Share(3000), 10); eq(W.Share(200), 100); eq(W.Share(100000), 5)
		-- /oly rollcall off: no answer, no update notice (0.9.2).
		W.Reset()
		W.random = function(a, b) if a then return a end return 0 end
		local before = #w.whispered
		W.SetAnswers(false)
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~11~100")
		eq(#w.whispered, before, "refused")
		local shown = ns.ShowDialog
		local popups = 0
		ns.ShowDialog = function() popups = popups + 1 end
		W.HandleUpdate("WHISPER", AUTHOR_FULL, "V3~99.0.0")
		ns.ShowDialog = shown
		eq(popups, 0, "no update notice either")
		W.SetAnswers(true)
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~12~100")
		eq(#w.whispered, before + 1, "answered again")
	end)
end)

test("Workshop: 'please update' only from the author, only when really behind, once in a while", function()
	WithWorkshop(AUTHOR_FULL, function(w, W)
		W.AskUpdate("Ann-Realm"); W.AskUpdate("Bob-Realm"); W.AskUpdate("Ann-Realm")
		eq(#w.whispered, 2, "once per player per UPDATE_GAP")
		assert(w.whispered[1].key ~= w.whispered[2].key, "each queued apart (the queue replaces equal keys)")
		eq(w.whispered[1].msg, "V3~" .. ns.VERSION)
	end)
	WithWorkshop("Tester-Realm", function(w, W)
		local v = ns.VERSION
		ns.VERSION = "0.8.0"
		W.HandleUpdate("WHISPER", "Somebody-Realm", "V3~0.9.0")
		eq(#w.popups, 0, "not the author")
		W.HandleUpdate("WHISPER", AUTHOR_FULL, "V3~0.8.0")
		eq(#w.popups, 0, "not behind")
		W.HandleUpdate("WHISPER", AUTHOR_FULL, "V3~0.8.2")
		eq(w.popups[1].name, "OLYMPUS_AUTHOR_UPDATE"); eq(w.popups[1].a, "0.8.0"); eq(w.popups[1].b, "0.8.2")
		W.HandleUpdate("WHISPER", AUTHOR_FULL, "V3~0.8.2")
		eq(#w.popups, 1, "once per UPDATE_GAP")
		W.HandleUpdate("WHISPER", AUTHOR_FULL, "V3~Update at evil.example")
		eq(#w.popups, 1, "a version number and nothing else")
		ns.VERSION = v
		eq(W.Newer("0.10.0", "0.9.9"), true); eq(W.Newer("0.8.1", "0.8.1"), false); eq(W.Newer("x", "0.1.0"), false)
	end)
end)

test("Workshop: a bug report reaches the author once he answers its first piece", function()
	local text = "```\nline one | pipe\n" .. ("x"):rep(700) .. "\nend\n```"
	WithWorkshop("Ann-Realm", function(w, W)
		local timers = {}
		W.after = function(_, _, f) timers[#timers + 1] = f end
		eq(W.BugAction(text), nil, "author not seen: no button")
		W.HandlePresence("CHANNEL", "Faladoriel-Realm", "V4~0.8.2")
		W.HandlePresence("CHANNEL", "Faladoriel Skylance-SomeEraRealm", "V4~0.8.2")
		eq(W.AuthorOnline(), false, "his first name, or his name on another realm group: not him")
		W.HandlePresence("CHANNEL", AUTHOR_FULL, "V4~0.8.2")
		eq(W.AuthorOnline(), true)
		local action = W.BugAction(text)
		assert(action and action.label:find("Faladoriel Skylance", 1, true), action and action.label)
		eq(action.fn(), true)
		eq(#w.whispered, 1, "the first piece alone")
		-- The author answers it: the rest follows.
		ns.me = AUTHOR_FULL
		W.HandleBug("WHISPER", "Ann-Realm", w.whispered[1].msg)
		local go = w.whispered[#w.whispered]
		eq(go.to, "Ann-Realm"); assert(go.msg:find("^V6~%d+~1$"), go.msg)
		ns.me = "Ann-Realm"
		W.HandleAck("WHISPER", "Faladoriel-Realm", go.msg)
		eq(#w.whispered, 2, "not the author: nothing more")
		W.HandleAck("WHISPER", AUTHOR_FULL, go.msg)
		local rest = {}
		for i = 3, #w.whispered do rest[#rest + 1] = w.whispered[i] end
		assert(#rest >= 3, #rest)
		for _, piece in ipairs(rest) do
			eq(piece.to, AUTHOR_FULL)
			assert(#piece.msg <= 255 and not piece.msg:find("\n", 1, true), "one addon message, no newline")
		end
		-- He gets them all (in any order), keeps the report, and says so.
		ns.me = AUTHOR_FULL
		for i = #rest, 1, -1 do W.HandleBug("WHISPER", "Ann-Realm", rest[i].msg) end
		eq(#W.Reports(), 1)
		assert(W.Reports()[1].text:find("line one ! pipe\n", 1, true), W.Reports()[1].text)
		local done = w.whispered[#w.whispered]
		assert(done.msg:find("^V6~%d+~2$"), done.msg)
		ns.me = "Ann-Realm"
		W.HandleAck("WHISPER", AUTHOR_FULL, done.msg)
		eq(w.printed[#w.printed], ns.L.WORKSHOP_BUG_SENT:format(ns.DisplayName(AUTHOR_FULL)))
		for _, f in ipairs(timers) do f() end
		eq(w.printed[#w.printed], ns.L.WORKSHOP_BUG_SENT:format(ns.DisplayName(AUTHOR_FULL)), "answered in time: no 'no answer'")
		eq(action.fn(), false, "one report per BUG_GAP")
		-- Nobody answers the first piece: nothing more goes out, and the player is told.
		W.Reset()
		timers = {}
		W.HandlePresence("CHANNEL", AUTHOR_FULL, "V4~0.8.2")
		local before = #w.whispered
		eq(W.SendBug("short report"), true)
		eq(#w.whispered, before + 1)
		for _, f in ipairs(timers) do f() end
		eq(w.printed[#w.printed], ns.L.WORKSHOP_BUG_NO_AUTHOR)
		eq(#w.whispered, before + 1, "nothing more")
		w.clock = w.clock + W.PRESENCE_FRESH + 1
		eq(W.AuthorOnline(), false, "gone quiet: offline")
	end)
end)

test("Workshop: the author's inbox can't be blocked or flooded", function()
	WithWorkshop(AUTHOR_FULL, function(w, W)
		W.HandleBug("CHANNEL", "Bob-Realm", "V5~1~1~1~channel")
		W.HandleBug("WHISPER", "Bob-Realm", "V5~1~1~99~too many pieces")
		W.HandleBug("WHISPER", "Bob-Realm", "V5~1~2~2~not the first piece")
		eq(#W.Reports(), 0, "channel, oversize and headless reports are dropped")
		-- A griefer opens report after report: one open at a time, three started an hour.
		for id = 1, 10 do W.HandleBug("WHISPER", "Grief-Realm", ("V5~%d~1~25~x"):format(id)) end
		-- Everyone else still gets through.
		for k = 1, 10 do W.HandleBug("WHISPER", ("P%d-Realm"):format(k), ("V5~%d~1~1~hello %d"):format(k, k)) end
		eq(#W.Reports(), 10, "ten honest reports")
		-- Three an hour per player.
		for id = 21, 24 do W.HandleBug("WHISPER", "Ann-Realm", ("V5~%d~1~1~report %d"):format(id, id)) end
		eq(#W.Reports(), 13)
		eq(W.Reports()[13].text, "report 23")
	end)
	WithWorkshop("Tester-Realm", function(w, W)
		W.HandleBug("WHISPER", "Ann-Realm", "V5~1~1~1~hello")
		eq(#W.Reports(), 0, "only the author collects reports")
	end)
end)

test("Workshop: what others claim never names the latest version, and roll calls add up", function()
	WithWorkshop(AUTHOR_FULL, function(w, W)
		local ids = 0
		W.random = function(a, b) if a then ids = ids + 1; return ids end return 0.5 end
		-- Before the census is in: no roll call (every addon would answer).
		W.RollCall()
		eq(#w.sent, 0); eq(w.printed[#w.printed], ns.L.WORKSHOP_ROLL_EARLY)
		ns.rdb.guilds = { ["Olympus II"] = { t = w.clock, users = 40, online = 90, versions = { ["9.9.9"] = 1, ["0.8.1"] = 3 } } }
		W.RollCall()
		local first = W.State().id
		-- A forged answer and a forged report claim 9.9.9: the latest is still ours.
		W.HandleAnswer("WHISPER", "Liar-Realm", ("V2~%d~9.9.9~Olympus II~Forever~hd~c~0~1~MA"):format(first))
		W.HandleAnswer("WHISPER", "Ann-Realm", ("V2~%d~%s~Olympus II~Forever~hd~c~0~1~MA"):format(first, ns.VERSION))
		W.HandleAnswer("WHISPER", "Bob-Realm", ("V2~%d~0.8.1~Olympus II~Forever~hd~c~0~1~MA"):format(first))
		W.HandleAnswer("WHISPER", "Eve-Realm", ("V2~%d~0.8.1~`@everyone~Mac|cffff~evil~c~0~1~MA"):format(first))
		eq(W.Latest(), ns.VERSION)
		local eve = W.State().answers["Eve-Realm"]
		eq(eve.guild, "everyone"); eq(eve.client, "?"); eq(eve.window, "?")
		W.AskOutdated()
		local asked = {}
		for _, x in ipairs(w.whispered) do asked[x.to] = x.msg end
		eq(asked["Ann-Realm"], nil, "up to date: not asked")
		eq(asked["Bob-Realm"], "V3~" .. ns.VERSION)
		eq(asked["Liar-Realm"], nil, "'newer' than the author: not asked either")
		-- A second roll call later: the first one's answers stay, a newer one replaces.
		w.clock = w.clock + W.ROLL_EVERY + 1
		W.RollCall()
		local second = W.State().id
		eq(W.State().count, 4, "the answers so far stay")
		W.HandleAnswer("WHISPER", "Bob-Realm", ("V2~%d~%s~Olympus II~Forever~hd~c~0~1~MA"):format(second, ns.VERSION))
		eq(W.State().count, 4); eq(W.State().answers["Bob-Realm"].version, ns.VERSION, "updated since")
		W.HandleAnswer("WHISPER", "Bob-Realm", ("V2~%d~0.8.0~Olympus II~Forever~hd~c~0~1~MA"):format(second))
		eq(W.State().answers["Bob-Realm"].version, ns.VERSION, "one answer per roll call")
	end)
	WithWorkshop("Tester-Realm", function(w, W)
		-- A player answers each roll call once, a new one five minutes later too.
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~7~100")
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~7~100")
		eq(#w.whispered, 1)
		w.clock = w.clock + W.ROLL_EVERY
		W.HandleRoll("CHANNEL", AUTHOR_FULL, "V1~8~100")
		eq(#w.whispered, 2, "the next roll call is answered")
	end)
	-- Field 24 keeps version numbers only.
	local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport({ guild = "Olympus V", total = 9, online = 1, zones = {},
		versions = { ["0.8.2"] = 3, ["|TInterface\\Icons\\X:400|t"] = 1, ["?"] = 2 } }))
	eq(d.versions["0.8.2"], 3); eq(d.versions["?"], 2)
	local n = 0
	for _ in pairs(d.versions) do n = n + 1 end
	eq(n, 2, "nothing else")
end)

test("tabard store: one key per player, whatever the name came from", function()
	local I = ns.Inspect
	local K = I.Key
	eq(K("Violator"), "Violator"); eq(K("Violator-" .. ns.realm), "Violator", "our realm: the short name, as 0.8.1 saved it")
	eq(K("Far-Elsewhere"), "Far-Elsewhere")
	-- The King's own patrol and a report of the same player: one entry, not two.
	local saved = I.Players()
	local before = {}
	for k, v in pairs(saved) do before[k] = v end
	I.Record("Dupe-" .. ns.realm, "Olympus", "MAGE", 20, nil, true)
	I.AddReported("Dupe", "Olympus", "NONE")
	local n = 0
	for _, e in ipairs(I.ShameList()) do if e.name == "Dupe" then n = n + 1 end end
	eq(n, 1, "listed once")
	for k in pairs(saved) do if not before[k] then saved[k] = nil end end
end)

test("Treasurer: exactly Pyralis Ashandar of OLYMPUS, under the King and beside his name", function()
	local realm, treasurerRealm = ns.realm, ns.TREASURER_REALM
	ns.realm, ns.TREASURER_REALM = "ClassicBetaPvP", "ClassicBetaPvP"
	local ok, err = pcall(function()
	eq(ns.IsTreasurer("Pyralis Ashandar-ClassicBetaPvP", "OLYMPUS"), true)
	eq(ns.IsTreasurer("Pyralis Ashandar", "Olympus"), true)
	eq(ns.IsTreasurer("Pyrelis Ashandar", "OLYMPUS"), false, "a look-alike name")
	eq(ns.IsTreasurer("Pyralis Ashandar", "LXIX"), false, "another guild")
	eq(ns.IsTreasurer("Pyralis Ashandar", "OLYMPUS II"), false, "another Olympus guild")
	local saved = ns.rdb.guilds
	ns.rdb.guilds = { ["OLYMPUS"] = Vouched({ total = 1000, online = 110, zones = {}, t = os.time(), leader = "Asmongold Asmongler", leaderOnline = true,
		officers = { { name = "Pyralis Ashandar", online = true, days = 0, class = "PR", level = 20 } } }, "W1-Realm", "W2-Realm") }
	local ok, err = pcall(function()
		local lines = ns.Views.RealmLines()
		local found
		for _, l in ipairs(lines) do
			if l.text and l.text:find(ns.L.TREASURER .. ": ", 1, true) then found = l end
		end
		assert(found and found.text:find("Pyralis Ashandar", 1, true) and found.onClick, "the Treasurer's line")
		-- Not in the report (the Horde's <Olympus>, another realm's): no line.
		local officers = ns.rdb.guilds["OLYMPUS"].officers
		ns.rdb.guilds["OLYMPUS"].officers = {}
		for _, l in ipairs(ns.Views.RealmLines()) do
			assert(not (l.text and l.text:find(ns.L.TREASURER .. ": ", 1, true)), "no Treasurer line without him")
		end
		ns.rdb.guilds["OLYMPUS"].officers = officers
		ns.Views.ExpandAll(true)
		local tagged = false
		for _, l in ipairs(ns.Views.RealmLines()) do
			if l.key == "Pyralis Ashandar" and l.text:find(ns.L.TREASURER, 1, true) and l.indent == 2 then tagged = true end
		end
		eq(tagged, true, "tagged among the Captains")
		ns.Views.ExpandAll(false)
	end)
	ns.rdb.guilds = saved
	if not ok then error(err, 0) end
	end)
	ns.realm, ns.TREASURER_REALM = realm, treasurerRealm
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- The Throne of 0.8.3: the Hands of the King, Vox Populi, the court, the treasury, royal
-- writs, the gates, pardons, and the chats in the Realm.
---------------------------------------------------------------------------

local function WithThrone(fn)
	local K = ns.King
	local saved = { me = ns.me, Now = ns.Now, Send = ns.Comm.Send, Whisper = ns.Comm.Whisper, Show = StaticPopup_Show,
		Guild = GetGuildInfo, Print = ns.Print, guilds = ns.rdb.guilds, after = ns.Vox.after, voxOff = ns.db.voxOff,
		Notice = RaidNotice_AddMessage, Zone = GetRealZoneText, Map = C_Map.GetBestMapForUnit, Info = C_Map.GetMapInfo,
		dev = ns.devThrone, chat = ns.rdb.chat, shame = ns.Inspect.shame }
	local w = { sent = {}, whispered = {}, popups = {}, printed = {}, clock = os.time(), timers = {} }
	local function Clean()
		K.Reset(); ns.Vox.Reset(); ns.Court.Reset(); ns.Acts.Reset(); ns.Treasury.Reset(); ns.Bank.Reset()
		ns.rdb.writs, ns.rdb.writsSent, ns.rdb.pardons, ns.rdb.treasury, ns.rdb.treasurySeen = nil, nil, nil, nil, nil
		ns.rdb.kingHands, ns.rdb.gates, ns.rdb.pardonsGiven = nil, nil, nil
		ns.rdb.treasurySums, ns.rdb.treasuryReport, ns.rdb.treasuryFlags, ns.rdb.treasuryOpening = nil, nil, nil, nil
		ns.rdb.treasuryToldWho, ns.db.previewTreasuryFlags, ns.db.myCharacters = nil, nil, nil
	end
	local ok, err = pcall(function()
		Clean()
		ns.devThrone = nil
		ns.Now = function() return w.clock end
		ns.Comm.Send = function(dist, msg, key, urgent) w.sent[#w.sent + 1] = { dist = dist, msg = msg, key = key, urgent = urgent } end
		ns.Comm.Whisper = function(to, msg, key, urgent) w.whispered[#w.whispered + 1] = { to = to, msg = msg, key = key, urgent = urgent } end
		StaticPopup_Show = function(name, a, b, data) w.popups[#w.popups + 1] = { name = name, a = a, b = b, data = data } end
		ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		ns.Vox.after = function(seconds, _, f) w.timers[#w.timers + 1] = { at = w.clock + seconds, fn = f } end
		RaidNotice_AddMessage = nil
		ns.db.voxOff = nil
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 90, zones = {}, t = w.clock, leader = "Asmongold Asmongler", realm = "Realm",
				officers = { { name = "Pyralis Ashandar", online = true, days = 0 } } }, "W1-Realm", "W2-Realm"),
			["Olympus Zeus"] = Vouched({ total = 100, online = 9, zones = {}, t = w.clock, leader = "Zed", realm = "Realm" }, "W3-Realm", "W4-Realm"),
			["Olympus II"] = Vouched({ total = 300, online = 3, zones = {}, t = w.clock, leader = "Ceo", realm = "Realm" }, "W5-Realm", "W6-Realm") }
		fn(w, K)
	end)
	ns.me, ns.Now, ns.Comm.Send, ns.Comm.Whisper, StaticPopup_Show = saved.me, saved.Now, saved.Send, saved.Whisper, saved.Show
	GetGuildInfo, ns.Print, ns.rdb.guilds, ns.Vox.after, ns.db.voxOff = saved.Guild, saved.Print, saved.guilds, saved.after, saved.voxOff
	RaidNotice_AddMessage, GetRealZoneText, C_Map.GetBestMapForUnit, C_Map.GetMapInfo = saved.Notice, saved.Zone, saved.Map, saved.Info
	ns.devThrone, ns.rdb.chat, ns.Inspect.shame = saved.dev, saved.chat, saved.shame
	Clean()
	if not ok then error(err, 0) end
end
local function RunTimers(w)
	local due = w.timers
	w.timers = {}
	for _, t in ipairs(due) do if t.at <= w.clock then t.fn() else w.timers[#w.timers + 1] = t end end
end
local function AsKing() GetGuildInfo = function() return "Olympus", "King", 0 end; ns.me = "Asmongold Asmongler-Realm" end
local function AsLord() GetGuildInfo = function() return "Olympus Zeus", "Lord", 0 end; ns.me = "Zed-Realm" end
local function AsCaptain() GetGuildInfo = function() return "Olympus II", "Officer", 1 end; ns.me = "Cap-Realm" end
local function AsSoldier(name) GetGuildInfo = function() return "Olympus II", "Member", 3 end; ns.me = (name or "Soldier") .. "-Realm" end
local function AsTreasurer() GetGuildInfo = function() return "Olympus", "Treasurer", 1 end; ns.me = "Pyralis Ashandar-Realm" end
local function Printed(w, text)
	for _, p in ipairs(w.printed) do if p:find(text, 1, true) then return true end end
	return false
end
local function Texts(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) .. " | " .. tostring(l.right or "") end
	return table.concat(out, "\n")
end
local function LastSent(w) return w.sent[#w.sent] and w.sent[#w.sent].msg end

test("Hands of the King: he names them, they use the tools he lends them, nothing of his own", function()
	WithThrone(function(w, K)
		AsKing()
		K.AddHand("Helper")
		eq(K.Hands()[1], "Helper-Realm")
		eq(ns.rdb.kingHands[1], "Helper-Realm", "kept for the next session")
		K.SendHands(true) -- (a few seconds after the last change, in game)
		assert(LastSent(w):find("^T1~H~%d+~Olympus~Helper%-Realm$"), LastSent(w))
		local list = LastSent(w)
		K.AddHand("Bad|cffff0000Name")
		eq(#K.Hands(), 1, "no free text for a name")
		-- The Hand's client: the Throne opens, his tools work.
		AsSoldier("Helper")
		eq(K.Visible(), false)
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
		eq(K.IsHand(), true); eq(K.Visible(), true); eq(K.CanCommand(), true)
		assert(Printed(w, "named you a Hand"), "told")
		local lines, _, detail = K.Build()
		eq(lines[1].text, ns.L.THRONE_ROOM_HAND:format("Asmond"), "the King's own pages (his Hands) are not a Hand's")
		K.Show("home")
		lines, _, detail = K.Build()
		eq(lines[1].text, ns.L.THRONE_ROOM_HAND:format("Asmond"))
		eq(detail, ns.L.THRONE_YOU_ARE_HAND:format("Asmond"))
		assert(not Texts(lines):find("Hands of the King", 1, true), "the Hands are the King's page alone")
		assert(not Texts(lines):find("Treasury", 1, true) and not Texts(lines):find("Court", 1, true), "so are the court and the treasury")
		-- Anyone else's client: a forged list does nothing; the King's is trusted.
		AsSoldier("Other")
		K.HandleCommand("CHANNEL", "Faker-Realm", "T1~H~1~Olympus~Faker-Realm")
		eq(K.Authorized("A", "Faker-Realm", "Olympus II"), false, "not named by the King")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~A~4~Olympus II~600~Stormwind City~Raid at dawn")
		eq(K.Agenda() and K.Agenda().title, "Raid at dawn", "a Hand sets the agenda")
		-- Never what is the King's alone: naming Hands, writs, pardons, the court.
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~H~5~Olympus II~Other-Realm")
		eq(K.IsHand(), false, "a Hand names nobody")
		for _, kind in ipairs({ "W", "F", "C", "P" }) do eq(K.Authorized(kind, "Helper-Realm", "Olympus II"), false, kind) end
		-- The King stopped repeating his list (offline): it ends.
		w.clock = w.clock + K.HANDS_FRESH + 1
		eq(K.Authorized("A", "Helper-Realm", "Olympus II"), false, "an old list ends")
		-- He takes the title back: the list goes out without the name.
		AsKing()
		K.RemoveHand("Helper-Realm")
		eq(#K.Hands(), 0)
		K.SendHands(true)
		assert(LastSent(w):find("^T1~H~%d+~Olympus~$"), LastSent(w))
	end)
end)

test("Vox Populi: pick one or several, a chart of the results, the winner worked out", function()
	WithUI(function()
		WithThrone(function(w, K)
			local V = ns.Vox
			local s, q, a = V.Parse("60 Raid tonight? Yes / No / Later")
			eq(s, 60); eq(q, "Raid tonight?"); eq(table.concat(a, ","), "Yes,No,Later")
			s, q, a = V.Parse("Ready?")
			eq(s, V.DEFAULT); eq(table.concat(a, ","), "Yes,No", "no answers: yes or no")
			-- The results: shares of the votes (pick one) or of the voters (pick several).
			local rows, winners = V.Tally({ "A", "B", "C" }, { 30, 60, 10 }, 100, false)
			eq(rows[2].pct, 60); eq(rows[2].lead, true); eq(#winners, 1)
			rows = V.Tally({ "A", "B", "C" }, { 80, 50, 10 }, 100, true)
			eq(rows[1].pct, 80); eq(rows[2].pct, 50, "several each: out of the 100 voters")
			eq(V.Verdict({ "A", "B" }, { 5, 5 }, 10, false), ns.L.VOX_TIE:format("A / B"))
			eq(V.Verdict({ "A", "B" }, { 0, 0 }, 0, false), ns.L.VOX_NO_VOTES)
			eq(V.Verdict({ "A", "B" }, { 7, 3 }, 10, false), ns.L.VOX_WINNER:format("A", 70))
			-- Not the King nor a Hand: nothing.
			AsSoldier()
			V.Ask("Raid tonight?")
			eq(#w.sent, 0)
			-- The composer: the question, the answers typed (empty ones left out), several each.
			AsKing()
			V.Prompt()
			local c = V.Composer()
			assert(c and c:IsShown(), "the composer")
			eq(c.a[1]:GetText(), ns.L.VOX_YES); eq(c.a[2]:GetText(), ns.L.VOX_NO)
			c.q:SetText("Which raids this week?")
			c.a[1]:SetText("Onyxia"); c.a[2]:SetText("Molten Core"); c.a[3]:SetText(""); c.a[4]:SetText("Zul'Gurub")
			c.kinds[2]:Click() -- pick several
			c.times[2]:Click() -- 60 s
			c.ask:Click()
			local msg = LastSent(w)
			assert(msg:find("^T1~V~%d+~Olympus~60~M~Which raids this week%?~Onyxia~Molten Core~Zul'Gurub$"), msg)
			eq(w.sent[#w.sent].urgent, true, "ahead of the census")
			eq(c:IsShown(), false, "the composer closes")
			local id = tonumber(msg:match("T1~V~(%d+)"))
			V.Ask("Another?")
			assert(Printed(w, ns.L.VOX_BUSY), "one question at a time")
			-- A soldier: the window with check boxes, several picks, one vote.
			AsSoldier("Voter")
			K.HandleCommand("CHANNEL", "Faker-Realm", "T1~V~9~Olympus~60~M~Fake?~A~B")
			eq(select(3, V.State()), nil, "not the King: no window")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", msg)
			local f = V.Frame()
			assert(f and f:IsShown(), "the window")
			eq(f.title:GetText(), ns.L.VOX_ASKS:format("Asmond"))
			eq(f.kind:GetText(), ns.L.VOX_PICK_MANY)
			eq(f.rows[3]:IsShown(), true); eq(f.rows[4]:IsShown(), false)
			eq(f.vote:IsShown(), true)
			f.rows[1].check:Click(); f.rows[3].check:Click()
			eq(f.rows[1].check:GetChecked(), true); eq(f.rows[3].check:GetChecked(), true)
			f.vote:Click()
			f.vote:Click()
			eq(#w.whispered, 1, "one vote")
			eq(w.whispered[1].to, "Asmongold Asmongler-Realm"); eq(w.whispered[1].msg, ("Y1~%d~13~Olympus II"):format(id)); eq(w.whispered[1].urgent, true)
			eq(f.vote:IsShown(), false, "voted")
			-- The King counts: one vote each, answers that exist, Olympus only.
			AsKing()
			V.HandleVote("WHISPER", "Voter-Realm", w.whispered[1].msg)
			V.HandleVote("WHISPER", "Voter-Realm", w.whispered[1].msg)
			V.HandleVote("WHISPER", "Other-Realm", ("Y1~%d~2~Olympus Zeus"):format(id))
			V.HandleVote("WHISPER", "Twice-Realm", ("Y1~%d~11~Olympus Zeus"):format(id))
			V.HandleVote("WHISPER", "Liar-Realm", ("Y1~%d~9~Olympus II"):format(id))
			V.HandleVote("WHISPER", "Horde-Realm", ("Y1~%d~2~Horde Heroes"):format(id))
			V.HandleVote("WHISPER", "Stranger-Realm", ("Y1~%d~1~Olympus Nowhere"):format(id))
			local poll = V.State()
			eq(poll.voters, 2); eq(poll.counts[1], 1); eq(poll.counts[2], 1); eq(poll.counts[3], 1)
			eq(poll.others, 1, "a vote nobody can place")
			local page = Texts((V.Build()))
			assert(page:find("Which raids this week?", 1, true) and page:find(ns.L.VOX_TOTAL:format(2), 1, true), page)
			assert(page:find("50%", 1, true), "each answer: half of the 2 voters")
			-- The chart on his screen, live.
			V.ShowLive()
			eq(f.live, true); eq(f.rows[1].bar:IsShown(), true); eq(f.rows[1].check:IsShown(), false)
			assert(f.status:GetText():find(ns.L.VOX_LIVE, 1, true), f.status:GetText())
			-- Time is up (and the grace for votes on their way): the results go to everyone.
			w.clock = w.clock + 60 + V.GRACE
			RunTimers(w)
			assert(LastSent(w):find(("^T1~E~%d~Olympus~2~1~1~1$"):format(id)), LastSent(w))
			assert(f.status:GetText():find(ns.L.VOX_FINAL, 1, true), "the final chart")
			local _, history = V.State()
			eq(#history, 1); eq(history[1].voters, 2)
			assert(V.DiscordText():find("**Which raids this week?**", 1, true), V.DiscordText())
			-- The soldier's window: the chart, the verdict, his picks still checked.
			AsSoldier("Voter")
			f.live = nil
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~E~%d~Olympus~4~3~1~2"):format(id))
			local shown = select(3, V.State())
			eq(shown.voters, 4); eq(shown.counts[1], 3)
			eq(f.rows[1].bar:IsShown(), true); eq(f.rows[1].check:GetChecked(), true)
			assert(f.verdict:GetText():find("Onyxia", 1, true), f.verdict:GetText())
			eq(f.rows[1].pct:GetText(), "75%  (3)", "3 of the 4 voters")
			-- Pick one: a second click moves the pick.
			V.Reset(); AsKing(); K.AddHand("Helper"); K.SendHands(true); local list = LastSent(w)
			AsSoldier("Voter")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~88~Olympus II~30~1~Pizza?~Yes~No")
			eq(f.title:GetText(), ns.L.VOX_ASKS_HAND:format("Helper"))
			f.rows[1].check:Click(); f.rows[2].check:Click()
			eq(f.rows[1].check:GetChecked(), false); eq(f.rows[2].check:GetChecked(), true)
			-- Chat only, for whoever turned the window off.
			V.Reset(); ns.db.voxOff = true
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~89~Olympus II~30~1~Tacos?~Yes~No")
			eq(f:IsShown(), false); assert(Printed(w, "Tacos?"), "in chat")
		end)
	end)
end)

test("Hold Court: the King opens it, players in his zone ask, he calls them one by one", function()
	WithThrone(function(w, K)
		local C = ns.Court
		local map = 1453
		C_Map.GetBestMapForUnit = function() return map end
		C_Map.GetMapInfo = function(id) return { mapType = 3, parentMapID = 1415 } end
		GetRealZoneText = function() return "Stormwind City" end
		AsSoldier(); C.Toggle()
		eq(#w.sent, 0, "the King's alone")
		AsKing()
		C.Toggle()
		local open = LastSent(w)
		assert(open:find("^T1~C~%d+~Olympus~1453~Stormwind City$"), open)
		local id = tonumber(open:match("T1~C~(%d+)"))
		eq(K.mode, "home", "the queue shows on the Throne Room")
		-- A soldier there: the line on top of the Census, one click asks.
		AsSoldier()
		K.HandleCommand("CHANNEL", "Faker-Realm", "T1~C~5~Olympus~1453~Stormwind City")
		eq(C.Current(), nil, "only the King holds court")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", open)
		assert(Printed(w, "holds court in Stormwind City"), "told once")
		local census = ns.Views.Build("census")
		assert(census[1].text:find("holds court in Stormwind City", 1, true), census[1].text)
		map = 1429
		eq(C.Line(), nil, "another zone: no line")
		map = 1453
		C.Line().onClick()
		eq(w.whispered[1].to, "Asmongold Asmongler-Realm"); eq(w.whispered[1].msg, ("T4~%d~Olympus II"):format(id))
		C.Seek()
		eq(#w.whispered, 1, "one request"); eq(C.Line().right:find(ns.L.COURT_STATE_ASKED, 1, true) ~= nil, true)
		-- The King's queue: Olympus names only, once each.
		AsKing()
		C.HandleRequest("WHISPER", "Soldier-Realm", ("T4~%d~Olympus II"):format(id))
		C.HandleRequest("WHISPER", "Soldier-Realm", ("T4~%d~Olympus II"):format(id))
		C.HandleRequest("WHISPER", "Troll-Realm", ("T4~%d~Asmongold smells"):format(id))
		C.HandleRequest("WHISPER", "Old-Realm", "T4~1~Olympus II")
		eq(#C.Holding().queue, 1)
		-- A Lord the census confirms shows with his guild; anyone else is a name alone (what
		-- they say of their guild is not shown on stream).
		C.HandleRequest("WHISPER", "Zed-Realm", ("T4~%d~Olympus Zeus"):format(id))
		C.HandleRequest("WHISPER", "Liar-Realm", ("T4~%d~Olympus kys lol"):format(id))
		eq(#C.Holding().queue, 3)
		assert(not table.concat(w.printed, "\n"):find("kys", 1, true), "nothing they typed in chat")
		local page = K.Build()
		local row, rows = nil, {}
		for _, l in ipairs(page) do if l.key then rows[l.key] = l.text end; if l.key == "Soldier-Realm" then row = l end end
		eq(rows["Zed-Realm"], "Zed <Olympus Zeus>"); eq(rows["Liar-Realm"], "Liar")
		assert(row and row.text == "Soldier", Texts(page))
		row.onClick()
		eq(w.whispered[#w.whispered].to, "Soldier-Realm"); eq(w.whispered[#w.whispered].msg, ("T5~%d"):format(id))
		-- Sent off: no new request from the Liar for a while.
		C.Call("Liar-Realm"); w.clock = w.clock + C.CALL_GAP; C.Call("Liar-Realm")
		C.HandleRequest("WHISPER", "Liar-Realm", ("T4~%d~Olympus II"):format(id))
		eq(C.Holding().by["Liar-Realm"], nil, "dismissed")
		-- Called: only the King's call counts.
		AsSoldier()
		C.HandleCall("WHISPER", "Faker-Realm", ("T5~%d"):format(id))
		eq(#w.popups, 0)
		C.HandleCall("WHISPER", "Asmongold Asmongler-Realm", ("T5~%d"):format(id))
		eq(w.popups[1].name, "OLYMPUS_COURT_CALLED")
		assert(C.Line().right:find(ns.L.COURT_STATE_CALLED, 1, true), "called")
		-- Closed: the line goes.
		AsKing(); C.Toggle()
		assert(LastSent(w):find(("^T1~Z~%d~Olympus$"):format(id)), LastSent(w))
		AsSoldier()
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", LastSent(w))
		eq(C.Current(), nil)
		-- Not repeated for a while (he logged off): over.
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", open)
		w.clock = w.clock + C.EXPIRE + 1
		eq(C.Current(), nil)
	end)
end)

test("The Treasury: the Treasurer's book (not his gold), the King's three switches for the army", function()
	WithThrone(function(w, K)
		local T = ns.Treasury
		local saved = { GetInboxHeaderInfo, GetInboxInvoiceInfo, GetTargetTradeMoney, GetPlayerTradeMoney, GetTradePlayerItemInfo,
			GetTradeTargetItemInfo, UnitFullName, ERR_TRADE_COMPLETE, GetSendMailMoney, AUCTION_OUTBID_MAIL_SUBJECT, ns.splitNames, GetMoney }
		local ok, err = pcall(function()
			ERR_TRADE_COMPLETE, AUCTION_OUTBID_MAIL_SUBJECT = "Trade complete.", "Outbid on %s"
			ns.rdb.treasuryFlags, ns.rdb.treasuryOpening = nil, nil
			local inbox = {
				{ "Giver", "For the treasury", 50000 }, { "Friend", "gift", 1000 }, { "Friend", "gift", 1000 },
				{ "Stormwind Auction House", "Outbid on Linen Cloth", 90000 }, { "Mystery", "hi", 3000, false },
			}
			GetInboxHeaderInfo = function(i)
				local m = inbox[i]
				return nil, nil, m[1], m[2], m[3], 0, 29.5, nil, nil, nil, nil, m[4] == nil and true or m[4]
			end
			GetInboxInvoiceInfo = function() return nil end
			-- Who sees the tab.
			AsKing()
			ns.splitNames = nil
			eq(T.Visible(), false, "no Treasurer where names have no surname (Classic)")
			ns.splitNames = true
			eq(T.Visible(), true, "the King on Forever")
			T.MailTaking(1); eq(ns.rdb.treasury, nil, "the King keeps no book")
			AsSoldier(); eq(T.Visible(), false, "a soldier: nothing shown by the King yet")
			-- The Treasurer's book: mail gold once it arrives; the auction house and a no-reply mail are no donation.
			AsTreasurer()
			local gold = 0
			GetMoney = function() return gold end
			for i = 1, #inbox do T.MailTaking(i); gold = gold + inbox[i][3]; T.MoneyChanged() end
			eq(#ns.rdb.treasury, 3); T.MailTaking(1); eq(#ns.rdb.treasury, 3, "asked again, no gold came: nothing")
			-- Trades: a donation, a sale (his items for gold) and a purchase (his gold for items).
			UnitFullName = function(unit) if unit == "NPC" then return "Trader", "Realm" end return "Pyralis Ashandar", "Realm" end
			local got, gave, myItems, theirItems = 0, 0, false, false
			GetTargetTradeMoney = function() return got end
			GetPlayerTradeMoney = function() return gave end
			GetTradePlayerItemInfo = function(i) if myItems and i == 1 then return "Linen Cloth" end end
			GetTradeTargetItemInfo = function(i) if theirItems and i == 1 then return "Copper Ore" end end
			local function Trade(g, v, mine, theirs)
				got, gave, myItems, theirItems = g, v, mine, theirs
				T.TradeShow(); T.TradeMoney(); got, gave = 0, 0
				T.Info(0, "Trade complete.")
			end
			Trade(123456, 0, false, false)                         -- a donation
			Trade(40000, 0, true, false)                           -- a sale: his
			Trade(0, 7000, false, true)                            -- a purchase: his
			GetSendMailMoney = function() return 5000 end
			T.MailSending("Crafter"); T.MailSent()                -- a payment by mail
			local book = ns.rdb.treasury
			eq(#book, 7)
			eq(book[5].excluded, true); eq(book[5].kind, "sale")
			eq(book[6].excluded, true); eq(book[6].kind, "purchase"); eq(book[6].out, true)
			assert(Printed(w, "Sale to Trader"), "the sale is told as his")
			-- The treasury is the book: opening + in - out, never his character's gold.
			T.SetOpening("100g")
			eq(T.Balance(), 1000000 + 50000 + 2000 + 123456 - 5000)
			-- He says the sale was a donation after all: counted; and back.
			T.Toggle(book[5]); eq(T.Balance(), 1000000 + 50000 + 2000 + 123456 + 40000 - 5000)
			T.Toggle(book[5]); eq(T.Balance(), 1000000 + 50000 + 2000 + 123456 - 5000)
			local t = T.Totals()
			eq(t.ranking[1].name, "Trader"); eq(t.ranking[2].name, "Giver"); eq(t.ranking[3].name, "Friend"); eq(#t.ranking, 3)
			-- His addon sends the treasury by itself (no button): balance, totals, ranking, counted lines.
			T.Share(true)
			local msg = LastSent(w)
			assert(msg:find("^T8~Olympus~1170456~175456~5000~175456~3~%-~Trader:123456,Giver:50000,Friend:2000~o:5000:Crafter:m:"), msg)
			assert(not msg:find("Linen", 1, true) and not msg:find(":40000:", 1, true), "sales and purchases are not sent")
			-- The King's copy: from the Treasurer himself only.
			AsKing()
			local savedRank = ns.Roster.RankOf
			ns.Roster.RankOf = function(n) if ns.FullName(n) == "Pyralis Ashandar-Realm" then return 1 end return savedRank(n) end
			T.HandleReport("CHANNEL", "Fake-Realm", msg); eq(T.Report(), nil, "not the Treasurer")
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", "T7~Olympus~123~1~1~1~"); eq(T.Report(), nil, "0.8.3's (his own gold): not read")
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", (msg:gsub("^T8", "T7"))); eq(T.Report(), nil, "T7 is 0.8.3's")
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", msg)
			local r = T.Report()
			eq(r.balance, 1170456); eq(r.rank[1].name, "Trader"); eq(#r.book, 5); eq(r.book[1].out, true)
			assert(T.HeaderText():find("117g", 1, true), "next to the soldiers: " .. T.HeaderText())
			local page = Texts((T.Build()))
			assert(page:find(ns.L.TREASURY_ARMY_SEES_NOTHING, 1, true), page)
			-- The King's switches: the balance for everyone; ranking and book stay his.
			T.SetFlag("balance", true)
			assert(LastSent(w):find("^T1~T~%d+~Olympus~100~" .. w.clock .. "$"), LastSent(w))
			local flags = LastSent(w)
			ns.Roster.RankOf = savedRank
			-- A soldier: the King's word (a Hand's is ignored), then the tab with the balance only.
			AsKing(); K.AddHand("Helper"); K.SendHands(true); local list = LastSent(w)
			ns.rdb.treasuryFlags = nil
			AsSoldier()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~T~9~Olympus II~111~" .. (w.clock + 5))
			eq(T.Shows("balance"), false, "not a Hand's switch")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", flags)
			eq(T.Shows("balance"), true); eq(T.Shows("ranking"), false); eq(T.Shows("book"), false)
			eq(T.Visible(), true, "the tab appears")
			page = Texts((T.Build()))
			assert(page:find(ns.L.TREASURY_BALANCE, 1, true), page)
			assert(not page:find(ns.L.TREASURY_RANKING, 1, true) and not page:find(ns.L.TREASURY_BOOK, 1, true), "ranking and book not shown")
			T.Show("book"); page = Texts((T.Build()))
			assert(not page:find("Crafter", 1, true), "the book stays closed")
			assert(T.RealmText():find("117g", 1, true), "under the Treasurer in the Realm")
			-- The King shows the ranking and the book too.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~T~10~Olympus~111~" .. (w.clock + 10))
			T.Show("book"); page = Texts((T.Build()))
			assert(page:find("Crafter", 1, true), "the book: " .. page)
			T.Show("summary"); page = Texts((T.Build()))
			assert(page:find("1. Trader", 1, true), page)
			-- He hides it all: the tab goes.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~T~11~Olympus~000~" .. (w.clock + 20))
			eq(T.Visible(), false)
			-- An older word of his (repeated late) does not undo it.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~T~12~Olympus~111~" .. (w.clock + 15))
			eq(T.Visible(), false)
		end)
		GetInboxHeaderInfo, GetInboxInvoiceInfo, GetTargetTradeMoney, GetPlayerTradeMoney, GetTradePlayerItemInfo,
			GetTradeTargetItemInfo, UnitFullName, ERR_TRADE_COMPLETE, GetSendMailMoney, AUCTION_OUTBID_MAIL_SUBJECT, ns.splitNames, GetMoney = unpack(saved, 1, 12)
		ns.rdb.treasuryFlags, ns.rdb.treasuryOpening = nil, nil
		if not ok then error(err, 0) end
	end)
end)

test("Treasury review fixes: the week survives the update, the King's word reaches everyone, every line within reach", function()
	WithThrone(function(w, K)
		local T = ns.Treasury
		local saved = { GetInboxHeaderInfo, GetInboxInvoiceInfo, GetTargetTradeMoney, GetPlayerTradeMoney, GetTradePlayerItemInfo,
			GetTradeTargetItemInfo, UnitFullName, ERR_TRADE_COMPLETE, GetSendMailMoney, ns.splitNames, K.Preview, GetMoney }
		local ok, err = pcall(function()
			ERR_TRADE_COMPLETE = "Trade complete."
			ns.splitNames = true
			-- Amounts as people type them: thousands, and a decimal part is silver.
			eq(T.ParseGold("1500.50"), 15005000); eq(T.ParseGold("1500,5"), 15005000); eq(T.ParseGold("1.500"), 15000000)
			eq(T.ParseGold("12,345"), 123450000); eq(T.ParseGold("1,500g 50s"), 15005000); eq(T.ParseGold("1500"), 15000000)
			eq(T.ParseGold("1.5.5"), nil); eq(T.ParseGold("lots"), nil)
			-- Under a gold piece, the silver shows (no "-0g").
			assert(not T.GoldText(-5000):find("0g", 1, true), T.GoldText(-5000)); eq(T.GoldText(123450000), "12,345g")
			-- The Treasurer is told who sees his treasury: he and the King, until the King shows it.
			AsTreasurer()
			local page = Texts((T.Build()))
			assert(page:find(ns.L.TREASURY_YOU_AND_KING:sub(1, 30), 1, true), page)
			eq(T.WhoSees(), ns.L.TREASURY_YOU_AND_KING)
			-- 0.8.3's sums (no donors, no version): rebuilt, this week's days too.
			T.Record("Giver", 30000, "mail", nil, { quiet = true })
			T.Record("Friend", 20000, "mail", nil, { quiet = true })
			ns.rdb.treasurySums = { allIn = 50000, allOut = 0, days = {} }
			local t = T.Totals()
			eq(t.allIn, 50000); eq(t.weekIn, 50000); eq(#t.givers, 2)
			-- A line of it uncounted: out of its day, never below nothing.
			T.Toggle(ns.rdb.treasury[1]); t = T.Totals()
			eq(t.weekIn, 20000); eq(t.allIn, 20000)
			T.Toggle(ns.rdb.treasury[1]); eq(T.Totals().weekIn, 50000)
			-- A report with a negative week (an older client's) is still read, the week as 0.
			AsKing()
			local savedRank = ns.Roster.RankOf
			ns.Roster.RankOf = function(n) if ns.FullName(n) == "Pyralis Ashandar-Realm" then return 1 end return savedRank(n) end
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", "T8~Olympus~500~100~0~-5~1~-~Giver:100~")
			eq(T.Report().week, 0); eq(T.Report().balance, 500)
			ns.Roster.RankOf = savedRank
			-- Mail: counted when its gold arrives. Two clicks before then count once; a take the
			-- server refuses counts nothing (the retry does); the mail that moves up into its place
			-- once it is gone is another; gold from anywhere else is not a donation.
			AsTreasurer()
			ns.rdb.treasury, ns.rdb.treasurySums = nil, nil
			local inbox = { { "Friend", "gift", 1000 } }
			GetInboxHeaderInfo = function(i)
				local m = inbox[i]
				return nil, nil, m[1], m[2], m[3], 0, 29.5, nil, nil, m[4], nil, true
			end
			GetInboxInvoiceInfo = function() return nil end
			local gold = 500000
			GetMoney = function() return gold end
			local function Arrive(c) gold = gold + c; T.MoneyChanged() end
			T.MailTaking(1); T.MailTaking(1)
			eq(#(ns.rdb.treasury or {}), 0, "not before its gold")
			Arrive(1000)
			eq(#ns.rdb.treasury, 1)
			T.MailTaking(1); Arrive(1000)
			eq(#ns.rdb.treasury, 2, "the same donor's second mail, moved up into its place")
			T.MailTaking(1); T.MailFailed(); T.MailTaking(1)
			eq(#ns.rdb.treasury, 2, "refused, then asked again")
			Arrive(1000)
			eq(#ns.rdb.treasury, 3, "counted once")
			Arrive(700); eq(#ns.rdb.treasury, 3, "loot, not a donation")
			-- A payment by mail that comes back: no longer counted (the latest of that amount, the
			-- name however it was typed).
			GetSendMailMoney = function() return 70000 end
			T.MailSending("crafter"); T.MailSent()
			T.MailSending("crafter"); T.MailSent()
			eq(T.Balance(), 3000 - 140000)
			inbox[1] = { "Crafter", "Returned: gold", 70000, true }
			T.MailTaking(1); Arrive(70000)
			eq(#ns.rdb.treasury, 5, "no new line"); eq(ns.rdb.treasury[5].excluded, true); eq(ns.rdb.treasury[5].returned, true)
			eq(ns.rdb.treasury[4].excluded, nil, "the other payment stays")
			eq(T.Balance(), 3000 - 70000)
			assert(Printed(w, "came back"), "told")
			-- His own characters: gold with them is his.
			ns.db.myCharacters = { ["pyralis alt-realm"] = true }
			T.Record("Pyralis Alt", 20000000, "mail")
			eq(ns.rdb.treasury[6].excluded, true); eq(ns.rdb.treasury[6].kind, "own"); eq(T.Balance(), 3000 - 70000)
			eq(T.Totals().ranking[1].name, "Friend", "not in the ranking")
			-- Trades: the gold both ways netted into one line; slot 7 (an enchant) is work, not a gift.
			UnitFullName = function(unit) if unit == "NPC" then return "Seller", "Realm" end return "Pyralis Ashandar", "Realm" end
			local got, gave, mine, theirs = 0, 0, {}, {}
			GetTargetTradeMoney = function() return got end
			GetPlayerTradeMoney = function() return gave end
			GetTradePlayerItemInfo = function(i) return mine[i] end
			GetTradeTargetItemInfo = function(i) return theirs[i] end
			local function Trade(g, v, m, th)
				got, gave, mine, theirs = g, v, m, th
				T.TradeShow(); T.TradeMoney(); T.Info(0, "Trade complete.")
			end
			local n = #ns.rdb.treasury
			Trade(5000, 100000, {}, { [1] = "Black Lotus" })   -- he pays 10g, gets the item and 50s back
			eq(#ns.rdb.treasury, n + 1); local e = ns.rdb.treasury[n + 1]
			eq(e.money, 95000); eq(e.out, true); eq(e.kind, "purchase"); eq(e.excluded, true)
			Trade(50000, 0, {}, { [7] = "Their Sword" })        -- he enchants their sword for 5g
			e = ns.rdb.treasury[n + 2]; eq(e.kind, "sale"); eq(e.excluded, true)
			Trade(0, 30000, { [7] = "My Chest" }, {})           -- they open his lockbox for 3g
			e = ns.rdb.treasury[n + 3]; eq(e.kind, "purchase"); eq(e.out, true)
			-- The note comes first on its row (the row is cut at the end), and in its tooltip.
			T.Show("book")
			local lines = T.Build()
			local found
			for _, l in ipairs(lines) do if tostring(l.text):find("(" .. ns.L.TREASURY_KIND_SALE .. ", ", 1, true) then found = l end end
			assert(found, Texts(lines))
			-- Every line within reach: 40, then 40 more a click.
			for i = 1, 45 do T.Record("Fan" .. i, 100, "mail", nil, { quiet = true }) end
			T.Show("book")
			lines = T.Build()
			local older = lines[#lines]
			assert(tostring(older.text):find(ns.L.TREASURY_OLDER:format(#ns.rdb.treasury - 40), 1, true), tostring(older.text))
			older.onClick()
			lines = T.Build()
			local rows = 0
			for _, l in ipairs(lines) do if l.onClick and l.indent then rows = rows + 1 end end
			eq(rows, #ns.rdb.treasury)
			-- The King's word, dated, reaches a soldier through the Treasurer's treasury.
			AsKing(); T.SetFlag("balance", true)
			local at = w.clock
			AsTreasurer(); K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", LastSent(w))
			local savedChunked = ns.Comm.SendChunked
			ns.Comm.SendChunked = function(msg) w.sent[#w.sent + 1] = { dist = "CHANNEL", msg = msg, chunked = true } end
			T.Share(true)
			ns.Comm.SendChunked = savedChunked
			eq(w.sent[#w.sent].chunked, true, "a long treasury goes in pieces")
			local report = LastSent(w)
			assert(report:find("~100@" .. at .. "~", 1, true), report)
			AsSoldier(); ns.rdb.treasuryFlags = nil
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", report)
			eq(T.Shows("balance"), true, "never met the King, has his word")
			-- A newer word of his is not undone by the Treasurer repeating the older one.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~T~5~Olympus~000~" .. (at + 60))
			T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", report)
			eq(T.Shows("balance"), false)
			-- Two clicks of his in one second: the second word still reaches the army.
			AsKing(); ns.rdb.treasuryFlags = nil
			T.SetFlag("ranking", true); local first = LastSent(w)
			T.SetFlag("ranking", false); local second = LastSent(w)
			AsSoldier(); ns.rdb.treasuryFlags = nil
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", first); eq(T.Shows("ranking"), true)
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", second); eq(T.Shows("ranking"), false, "the newer word, same second")
			-- The Treasurer is told what the King shows, and told again when it changes.
			AsTreasurer(); ns.rdb.treasuryFlags = { balance = true, at = at }
			assert(T.WhoSees():find(ns.L.TREASURY_PART_BALANCE, 1, true), T.WhoSees())
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~T~6~Olympus~101~" .. (at + 900 - 300))
			assert(Printed(w, ns.L.TREASURY_PART_BOOK), "told the King now shows the book")
			-- The way back from the book names what the viewer finds there.
			AsSoldier(); ns.rdb.treasuryFlags = { book = true, at = at }
			eq(T.SummaryTip(), ns.L.TREASURY_SUMMARY_BTN_TIP_PLAIN)
			ns.rdb.treasuryFlags = { book = true, balance = true, at = at }
			eq(T.SummaryTip(), ns.L.TREASURY_SUMMARY_BTN_TIP:format(ns.L.TREASURY_PART_BALANCE))
			-- Asmond's view keeps its own switches: the King's word stays, and goes with the view.
			AsSoldier(); ns.rdb.treasuryFlags = { balance = true, at = at }
			K.Preview = function() return true end
			local sent = #w.sent
			T.SetFlag("book", true)
			eq(#w.sent, sent, "nothing sent"); eq(ns.db.previewTreasuryFlags.book, true); eq(ns.rdb.treasuryFlags.book, nil)
			eq(T.Shows("book"), true)
			K.Preview = saved[11]
			eq(T.Shows("book"), false, "the King's word, not the preview's")
			K.SetDevView(false); eq(ns.db.previewTreasuryFlags, nil)
		end)
		GetInboxHeaderInfo, GetInboxInvoiceInfo, GetTargetTradeMoney, GetPlayerTradeMoney, GetTradePlayerItemInfo,
			GetTradeTargetItemInfo, UnitFullName, ERR_TRADE_COMPLETE, GetSendMailMoney, ns.splitNames, K.Preview, GetMoney = unpack(saved, 1, 12)
		if not ok then error(err, 0) end
	end)
end)

-- Blizzard's gamepad UI (Forever): the game's popups break when an addon opens one, so there
-- Olympus shows its own dialog (Dialog.lua); with mouse and keyboard nothing changes.
local function WithGamepadUI(on, fn)
	local savedStyle, savedType = C_InputInterfaceStyle, Enum.InputDeviceInterfaceType
	local savedShow, savedHide, savedFind = StaticPopup_Show, StaticPopup_Hide, StaticPopup_FindVisible
	local game = { shown = {}, hidden = {} }
	Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
	C_InputInterfaceStyle = { GetCurrentStyle = function() return on and 1 or 0 end }
	StaticPopup_Show = function(which, a, b, data) game.shown[#game.shown + 1] = { which = which, a = a, b = b, data = data } return "blizzard" end
	StaticPopup_Hide = function(which, data) game.hidden[#game.hidden + 1] = which end
	StaticPopup_FindVisible = function() game.found = true return nil end
	local ok, err = pcall(fn, game)
	ns.Dialog.Reset()
	C_InputInterfaceStyle, Enum.InputDeviceInterfaceType = savedStyle, savedType
	StaticPopup_Show, StaticPopup_Hide, StaticPopup_FindVisible = savedShow, savedHide, savedFind
	if not ok then error(err, 0) end
end

test("gamepad UI: Olympus's own dialogs, never the game's popups; mouse and keyboard as before", function()
	WithUI(function()
		local D = ns.Dialog
		local log = {}
		StaticPopupDialogs.OLYMPUS_TEST_A = {
			text = "Hello %s and %s", button1 = "Yes", button2 = "No", button3 = "Always",
			OnShow = function(self, data) log[#log + 1] = "show " .. tostring(data) end,
			OnAccept = function(self, data) log[#log + 1] = "accept " .. tostring(data) end,
			OnCancel = function(self, data, reason) log[#log + 1] = "cancel " .. tostring(data) .. " " .. tostring(reason) end,
			OnAlt = function(self, data) log[#log + 1] = "alt " .. tostring(data) end,
			OnHide = function(self, data) log[#log + 1] = "hide " .. tostring(data) end,
			timeout = 0, hideOnEscape = true,
		}
		-- Mouse and keyboard: the game's popup, with the very same arguments.
		WithGamepadUI(false, function(game)
			eq(ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 7), "blizzard")
			eq(game.shown[1].which, "OLYMPUS_TEST_A"); eq(game.shown[1].a, "x"); eq(game.shown[1].b, "y"); eq(game.shown[1].data, 7)
			ns.HideDialog("OLYMPUS_TEST_A", 7)
			eq(game.hidden[1], "OLYMPUS_TEST_A")
			eq(D.Find("OLYMPUS_TEST_A"), nil, "none of ours")
		end)
		WithGamepadUI(true, function(game)
			-- Shown in our window, text formatted, the game's popups untouched.
			local f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 7)
			eq(#game.shown, 0); eq(D.Find("OLYMPUS_TEST_A"), f); eq(f:IsShown(), true)
			eq(f.text:GetText(), "Hello x and y"); eq(f.buttons[1]:GetText(), "Yes"); eq(f.buttons[3]:GetText(), "Always")
			eq(f:GetFrameStrata(), "DIALOG"); eq(f.editBox:IsShown(), false)
			eq(log[1], "show 7")
			-- Yes: OnAccept, closed.
			f.buttons[1]:Click()
			eq(log[2], "accept 7"); eq(log[3], "hide 7"); eq(f:IsShown(), false)
			-- No: OnCancel "clicked". Always: OnAlt.
			log = {}
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 8)
			f.buttons[2]:Click()
			eq(log[2], "cancel 8 clicked"); eq(log[3], "hide 8")
			log = {}
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 9)
			f.buttons[3]:Click()
			eq(log[2], "alt 9"); eq(log[3], "hide 9")
			-- Closed by anything but a click (the game's window sweeps on death, loading screens,
			-- Alt+Z): no answer. And they are not in those sweeps, as the game's popups aren't.
			log = {}
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 10)
			f:Hide()
			eq(log[2], "hide 10"); eq(#log, 2, "no answer given for the player")
			for _, name in ipairs(UISpecialFrames or {}) do assert(not name:find("^OlympusDialog"), "not swept: " .. name) end
			-- Hidden by the addon: no answer, OnHide only (the game's StaticPopup_Hide).
			log = {}
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 11)
			ns.HideDialog("OLYMPUS_TEST_A", 11)
			eq(log[2], "hide 11"); eq(#log, 2); eq(#game.hidden, 0, "the game's popups untouched")
			-- A handler returning true keeps it open.
			StaticPopupDialogs.OLYMPUS_TEST_A.OnAccept = function() return true end
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 12)
			f.buttons[1]:Click()
			eq(f:IsShown(), true, "kept open")
			ns.HideDialog("OLYMPUS_TEST_A")
			-- The timeout: hidden, then OnCancel "timeout".
			log = {}
			StaticPopupDialogs.OLYMPUS_TEST_A.timeout = 30
			f = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 13)
			f:Fire("OnUpdate", 29)
			eq(f:IsShown(), true)
			f:Fire("OnUpdate", 2)
			eq(f:IsShown(), false); eq(log[2], "hide 13"); eq(log[3], "cancel 13 timeout")
			StaticPopupDialogs.OLYMPUS_TEST_A.timeout = 0
			-- The same dialog again takes the old one's place; different ones stack, a fourth
			-- replaces the oldest.
			local a1 = ns.ShowDialog("OLYMPUS_TEST_A", "1", "1", 1)
			local a2 = ns.ShowDialog("OLYMPUS_TEST_A", "2", "2", 2)
			eq(a1, a2); eq(a2.data, 2)
			StaticPopupDialogs.OLYMPUS_TEST_B = { text = "B", button1 = "OK", timeout = 0 }
			local b1 = ns.ShowDialog("OLYMPUS_TEST_B")
			assert(b1 ~= a2, "another window")
			eq(b1.points[1][2], a2, "under the first"); eq(#b1.buttons, 3); eq(b1.buttons[2]:IsShown(), false)
			ns.HideDialog("OLYMPUS_TEST_A")
			eq(Anchor(b1), "TOP UIParent TOP 0 -135", "moves up when the first closes")
			-- Three up, a fourth takes the oldest's place: that one is cancelled "override".
			log = {}
			StaticPopupDialogs.OLYMPUS_TEST_C = { text = "C", button1 = "OK", timeout = 0 }
			StaticPopupDialogs.OLYMPUS_TEST_D = { text = "D", button1 = "OK", timeout = 0 }
			ns.ShowDialog("OLYMPUS_TEST_A", "o", "o", 20)
			ns.ShowDialog("OLYMPUS_TEST_C")
			ns.ShowDialog("OLYMPUS_TEST_D")
			eq(D.Find("OLYMPUS_TEST_B"), nil, "b1 was the oldest: gone")
			ns.ShowDialog("OLYMPUS_TEST_B")
			eq(D.Find("OLYMPUS_TEST_A"), nil); eq(log[#log], "cancel 20 override")
			for _, w in ipairs({ "OLYMPUS_TEST_B", "OLYMPUS_TEST_C", "OLYMPUS_TEST_D" }) do ns.HideDialog(w) end
			StaticPopupDialogs.OLYMPUS_TEST_C, StaticPopupDialogs.OLYMPUS_TEST_D = nil, nil
			-- The edit box: the dialog is its parent (the game's), Enter and Escape handlers.
			local entered
			StaticPopupDialogs.OLYMPUS_TEST_B = { text = "Name?", button1 = "OK", button2 = "Cancel", hasEditBox = true, editBoxWidth = 260, maxLetters = 40,
				OnShow = function(self) self.editBox:SetText("typed") end,
				EditBoxOnEnterPressed = function(eb) entered = eb:GetParent().data .. ":" .. eb:GetText(); eb:GetParent():Hide() end,
				timeout = 0, hideOnEscape = true }
			local e = ns.ShowDialog("OLYMPUS_TEST_B", nil, nil, "d")
			eq(e.editBox:IsShown(), true); eq(e.editBox:GetParent(), e); eq(e.EditBox, e.editBox)
			eq(e.editBox.scripts.OnEditFocusGained, nil, "no select-all on focus, as the game's popup box")
			assert(e:GetWidth() >= 320, "wide enough for the box")
			e.editBox:Fire("OnEnterPressed")
			eq(entered, "d:typed"); eq(e:IsShown(), false)
			-- Without EditBoxOnEnterPressed, Enter does nothing (as the game's: no writ sent by it).
			local accepted
			StaticPopupDialogs.OLYMPUS_TEST_B = { text = "Writ", button1 = "Lords", button2 = "Cancel", button3 = "All", hasEditBox = true,
				OnAccept = function() accepted = true end, timeout = 0 }
			e = ns.ShowDialog("OLYMPUS_TEST_B")
			e.editBox:Fire("OnEnterPressed")
			eq(accepted, nil); eq(e:IsShown(), true)
			ns.HideDialog("OLYMPUS_TEST_B")
			-- The keyboard is never taken from another box (the chat's): the player clicks ours.
			local focus = { name = "ChatFrame1EditBox" }
			local savedFocus = GetCurrentKeyBoardFocus
			GetCurrentKeyBoardFocus = function() return focus end
			local took
			StaticPopupDialogs.OLYMPUS_TEST_B = { text = "Name?", button1 = "OK", hasEditBox = true, timeout = 0,
				OnShow = function(self) self.editBox:SetFocus() end }
			local box = ns.ShowDialog("OLYMPUS_TEST_B").editBox
			eq(ns.Focus(box, function() took = true end), false); eq(took, nil)
			focus = nil
			eq(ns.Focus(box, function() took = true end), true); eq(took, true)
			focus = { olympusBox = true }
			took = nil
			eq(ns.Focus(box, function() took = true end), true, "from another Olympus box: fine")
			GetCurrentKeyBoardFocus = savedFocus
			ns.HideDialog("OLYMPUS_TEST_B")
		end)
		-- Mouse and keyboard: focus as always, whatever holds it.
		WithGamepadUI(false, function()
			local took
			local savedFocus = GetCurrentKeyBoardFocus
			GetCurrentKeyBoardFocus = function() return { name = "ChatFrame1EditBox" } end
			eq(ns.Focus({}, function() took = true end), true); eq(took, true)
			GetCurrentKeyBoardFocus = savedFocus
		end)
		-- Updated without a restart (Dialog.lua not loaded): with the gamepad UI never the
		-- game's popup, the player is told to restart.
		WithGamepadUI(true, function(game)
			local savedDialog, printed = ns.Dialog, {}
			local savedPrint = ns.Print
			ns.Dialog = setmetatable({ missing = true }, { __index = function() return function() end end })
			ns.Print = function(m) printed[#printed + 1] = m end
			local shown = ns.ShowDialog("OLYMPUS_TEST_A", "x", "y", 1)
			ns.Dialog, ns.Print = savedDialog, savedPrint
			eq(shown, nil); eq(#game.shown, 0); eq(printed[1], ns.L.RESTART_NEEDED)
		end)
		StaticPopupDialogs.OLYMPUS_TEST_A, StaticPopupDialogs.OLYMPUS_TEST_B = nil, nil
	end)
end)

test("gamepad UI: the King's summons in our dialog; a layer invite is the player's to accept", function()
	WithUI(function()
		LoadUI()
		WithGamepadUI(true, function(game)
			WithThrone(function(w, K)
				AsKing(); K.Summon()
				local id = tonumber(LastSent(w):match("T1~S~(%d+)"))
				AsLord()
				K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", ("T1~S~%d~Olympus"):format(id))
				eq(#w.popups, 0, "not the game's popup"); eq(#game.shown, 0)
				local f = ns.Dialog.Find("OLYMPUS_KING_SUMMON")
				assert(f and f:IsShown(), "our dialog")
				f.buttons[1]:Click()
				local answer = w.whispered[#w.whispered]
				assert(answer and answer.msg:find(("^T2~%d~P~"):format(id)), "present, to the King")
			end)
		end)
	end)
	-- The asker's side: a trusted helper's invite is not accepted for the player (the game's
	-- invite window, which the controller answers, is left alone).
	WithGamepadUI(true, function(game)
		WithHop(function(w, H)
			w.see(7)
			H.Ask(1453, 8, "Kingy's layer")
			H.HandleOffer("WHISPER", "Bbb-Realm", "LO~1~3~5")
			w.clock = w.clock + H.WINDOW
			H.Tick()
			H.OnInvite("Bbb")
			eq(w.accepted, 0, "the player accepts"); eq(#w.hidden, 0); eq(game.found, nil, "the game's invite popup untouched")
			eq(H.State().phase, "requested")
		end)
	end)
end)

test("gamepad UI: whispers and chat lines written in an Olympus window, never the game's chat box", function()
	WithUI(function()
		local UI = LoadUI()
		local saved = { tell = ChatFrame_SendTell, open = ChatFrame_OpenChat, say = SendChatMessage, send = ns.Channels.Send, split = ns.splitNames }
		local told, opened, said, sent = {}, {}, {}, {}
		ChatFrame_SendTell = function(n) told[#told + 1] = n end
		ChatFrame_OpenChat = function(t) opened[#opened + 1] = t end
		SendChatMessage = function(text, kind, _, to) said[#said + 1] = kind .. " " .. tostring(to) .. " " .. text end
		ns.Channels.Send = function(tier, text) sent[#sent + 1] = tier .. " " .. text end
		local ok, err = pcall(function()
			ns.splitNames = true
			UI.Toggle()
			-- Mouse and keyboard: the game's chat box, as always.
			WithGamepadUI(false, function()
				UI.ShowPerson({ name = "Faladoriel Skylance", realm = ns.realm, guild = "Olympus II" })
				OlympusPersonFrame.whisper:Click()
				eq(told[1], "Faladoriel Skylance")
			end)
			WithGamepadUI(true, function(game)
				-- The member card's Whisper: our window, sent to the name the server finds.
				UI.ShowPerson({ name = "Faladoriel Skylance", realm = ns.realm, guild = "Olympus II" })
				OlympusPersonFrame.whisper:Click()
				eq(#told, 1, "not the game's chat box"); eq(#game.shown, 0)
				local w = ns.Dialog.Find("OLYMPUS_WHISPER")
				assert(w, "the whisper window")
				eq(w.text:GetText(), ns.L.WHISPER_TO:format("Faladoriel Skylance"))
				w.editBox:SetText("  hi there  ")
				w.editBox:Fire("OnEnterPressed")
				eq(said[1], "WHISPER Faladoriel Skylance hi there"); eq(w:IsShown(), false)
				-- Empty: nothing sent.
				UI.WhisperWindow("Faladoriel Skylance").buttons[1]:Click()
				eq(#said, 1)
				-- A line for [Olympus].
				local c = UI.ChatWindow("A", "Olympus")
				c.editBox:SetText("for olympus")
				c.buttons[1]:Click()
				eq(sent[1], "A for olympus"); eq(#opened, 0)
			end)
		end)
		ChatFrame_SendTell, ChatFrame_OpenChat, SendChatMessage, ns.Channels.Send, ns.splitNames = saved.tell, saved.open, saved.say, saved.send, saved.split
		if not ok then error(err, 0) end
	end)
end)

test("no Olympus file opens or closes the game's popups itself (ns.ShowDialog / ns.HideDialog)", function()
	local allowed = { ["Core.lua"] = { StaticPopup_Show = 1, StaticPopup_Hide = 1 }, ["Hop.lua"] = { StaticPopup_Hide = 1, StaticPopup_FindVisible = 1 } }
	local p = io.popen('ls "' .. ADDON_DIR .. '"')
	for file in p:lines() do
		if file:match("%.lua$") and file ~= "DevTest.lua" and file ~= "Dev.lua" then
			local src = assert(io.open(ADDON_DIR .. file)):read("*a")
			for _, fn in ipairs({ "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_FindVisible", "StaticPopupSpecial_Show" }) do
				local n = 0
				for _ in src:gmatch(fn .. "%(") do n = n + 1 end
				local ok = (allowed[file] and allowed[file][fn] or 0)
				eq(n, ok, file .. " calls " .. fn)
			end
		end
	end
	p:close()
end)

test("the King's guild in one place: <Olympus> on the Alliance, the Horde's once it is set", function()
	local savedFaction, savedHorde = ns.faction, ns.KING_GUILD.Horde
	local ok, err = pcall(function()
		ns.faction = "Alliance"
		eq(ns.IsKingGuild("Olympus"), true); eq(ns.IsKingGuild("OLYMPUS"), true); eq(ns.IsKingGuild("Olympus II"), false); eq(ns.IsKingGuild(nil), false)
		eq(ns.IsCrownRank("Olympus", 1), true); eq(ns.IsCrownRank("Olympus II", 1), false); eq(ns.IsCrownRank("Olympus II", 0), true)
		ns.faction = "Horde"
		eq(ns.IsKingGuild("Mudhutters"), true, "the Horde's: <Mudhutters> (0.9.4)"); eq(ns.IsKingGuild("Olympus"), false)
		ns.KING_GUILD.Horde = nil
		eq(ns.IsKingGuild("Olympus"), false, "no Horde King with no guild set")
		ns.KING_GUILD.Horde = "olympus horde"
		eq(ns.IsKingGuild("Olympus Horde"), true); eq(ns.IsKingGuild("Olympus"), false); eq(ns.IsCrownRank("Olympus Horde", 1), true)
	end)
	ns.faction, ns.KING_GUILD.Horde = savedFaction, savedHorde
	if not ok then error(err, 0) end
end)

test("Royal Writs to the whole army: every member gets the parchment, nobody acknowledges; the two-step prompt", function()
	WithUI(function()
		LoadUI()
		WithThrone(function(w, K)
			local A = ns.Acts
			eq(A.WritFor("E"), true, "a soldier reads a writ to all")
			AsKing()
			A.SendWrit("E", "Soldiers, march!")
			local msg = LastSent(w)
			assert(msg:find("^T1~W~%d+~Olympus~E~Soldiers, march!$"), msg)
			local id = tonumber(msg:match("T1~W~(%d+)"))
			-- A soldier gets it, on parchment, without the acknowledge button.
			AsSoldier()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", msg)
			local got = ns.Acts.WritLines()
			assert(Texts(got):find(ns.L.WRIT_TO_EVERYONE, 1, true), Texts(got))
			eq(OlympusWritFrame:IsShown(), true); eq(OlympusWritFrame.ack.shown, false, "no 'As you command' for the army")
			eq(OlympusWritFrame.to.text, ns.L.WRIT_TO_EVERYONE)
			-- An acknowledgement for it counts for nothing on the King's side.
			AsKing()
			A.HandleAck("WHISPER", "Zed-Realm", ("T6~%d~Olympus Zeus"):format(id))
			local mine = ns.rdb.writsSent[#ns.rdb.writsSent]
			eq(mine.to, "E"); eq(mine.acks or 0, 0)
			assert(not Texts(A.WritLines()):find(ns.L.WRIT_ACKS:format(0), 1, true), "no count shown for it")
			-- The prompt: the words first (Cancel there), then who receives them.
			w.clock = w.clock + 600
			local box = { editBox = { GetText = function() return "Hold the bridge" end } }
			StaticPopupDialogs.OLYMPUS_WRIT.OnAccept(box)
			local p = w.popups[#w.popups]
			eq(p.name, "OLYMPUS_WRIT_TO"); eq(p.data, "Hold the bridge")
			local before = #w.sent
			StaticPopupDialogs.OLYMPUS_WRIT_TO.OnCancel(nil, "Hold the bridge", "timeout")
			eq(#w.sent, before, "a timeout sends nothing")
			StaticPopupDialogs.OLYMPUS_WRIT_TO.OnCancel(nil, "Hold the bridge", "clicked")
			assert(LastSent(w):find("~C~Hold the bridge$"), "the middle button: Lords and Captains")
			w.clock = w.clock + 600
			StaticPopupDialogs.OLYMPUS_WRIT_TO.OnAlt(nil, "Hold the bridge")
			assert(LastSent(w):find("~E~Hold the bridge$"), "the third: the whole army")
			w.clock = w.clock + 600
			StaticPopupDialogs.OLYMPUS_WRIT_TO.OnAccept(nil, "Hold the bridge")
			assert(LastSent(w):find("~L~Hold the bridge$"), "the first: the Lords")
			eq(StaticPopupDialogs.OLYMPUS_WRIT_TO.noCancelOnEscape, true, "Escape sends nothing")
			StaticPopupDialogs.OLYMPUS_WRIT.OnAccept({ editBox = { GetText = function() return "x" end } })
			eq(w.popups[#w.popups].name, "OLYMPUS_WRIT_TO", "too short: no second step"); eq(w.popups[#w.popups].data, "Hold the bridge")
		end)
	end)
end)

test("the King's Agenda arrives as a popup with the appointment, once per agenda", function()
	WithThrone(function(w, K)
		AsSoldier()
		K.Reset()
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~A~77~Olympus~1800~The Crossroads~Raid on the Crossroads")
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_AGENDA_CALL")
		eq(p.a, ns.L.THRONE_AGENDA_POPUP:format(ns.KING_NAME, "Raid on the Crossroads", 30, "The Crossroads"))
		local n = #w.popups
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~A~77~Olympus~1790~The Crossroads~Raid on the Crossroads")
		eq(#w.popups, n, "a resend: no second popup")
		eq(StaticPopupDialogs.OLYMPUS_AGENDA_CALL.timeout, 120)
	end)
end)

test("the guild bank of <Olympus>: a snapshot when it is opened, the Treasurer's copy for everyone, the tab shows it", function()
	WithThrone(function(w, K)
		local B, T = ns.Bank, ns.Treasury
		local saved = { GetNumGuildBankTabs, GetGuildBankTabInfo, GetGuildBankItemInfo, GetGuildBankItemLink, GetGuildBankMoney, ns.splitNames, ns.Comm.SendChunked, ns.Roster.RankOf }
		local ok, err = pcall(function()
			ns.splitNames = true
			B.Reset()
			AsTreasurer()
			GetNumGuildBankTabs = function() return 3 end
			GetGuildBankTabInfo = function(tab) return ({ "Consumables", "Mate;rials~x", "Officers" })[tab], "icon" .. tab, tab ~= 3 end
			local slots = { [1] = { [1] = { "tex1", 20, 929 }, [5] = { "tex2", 3, 6948 } }, [2] = { [1] = { "tex3", 200, 2589 } } }
			GetGuildBankItemInfo = function(tab, slot) local s = slots[tab] and slots[tab][slot]; if s then return s[1], s[2] end end
			GetGuildBankItemLink = function(tab, slot) local s = slots[tab] and slots[tab][slot]; return s and ("|Hitem:" .. s[3] .. ":0|h[x]|h") end
			GetGuildBankMoney = function() return 1234567 end
			-- Read: the tabs we may see and asked for, item and count, the bank's gold.
			B.SetOpenForTest(true, { 1, 2 })
			local snap, total = B.Read()
			eq(#snap.tabs, 2); eq(total, 3); eq(snap.tabs[1].items[1].id, 929); eq(snap.tabs[1].items[2].n, 3); eq(snap.tabs[1].items[2].s, 5)
			eq(snap.tabs[1].items[1].icon, "tex1"); eq(snap.money, 1234567); eq(snap.guild, "Olympus")
			eq(snap.tabs[2].name, "Mate rials x", "the message's separators taken out of a tab's name, its letters kept")
			ns.rdb.bank = snap
			local msg = B.Message()
			eq(msg, ("T9~Olympus~%d~1234567~Consumables;929x20,.3,6948x3~Mate rials x;2589x200"):format(snap.t), "the empty slots between as a gap")
			-- Shared by the Treasurer's client alone, once per gap unless it changed.
			ns.Comm.SendChunked = function(m) w.sent[#w.sent + 1] = { dist = "CHANNEL", msg = m, chunked = true } end
			eq(B.Share(), true); eq(LastSent(w), msg)
			eq(B.Share(), false, "unchanged, within the gap")
			AsSoldier()
			eq(B.Share(true), false, "not the Treasurer")
			-- The King's copy: from the Treasurer alone, of the King's guild's bank.
			AsKing(); ns.rdb.bank = nil
			local savedRank = ns.Roster.RankOf
			ns.Roster.RankOf = function(n) if ns.FullName(n) == "Pyralis Ashandar-Realm" then return 1 end return savedRank(n) end
			B.HandleReport("CHANNEL", "Fake-Realm", msg); eq(B.Report(), nil, "not the Treasurer")
			B.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", (msg:gsub("^T9~Olympus~", "T9~Olympus II~"))); eq(B.Report(), nil, "not the King's guild")
			B.HandleReport("WHISPER", "Pyralis Ashandar-Realm", msg); eq(B.Report(), nil, "the channel alone")
			B.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", msg)
			local r = B.Report()
			eq(#r.tabs, 2); eq(r.tabs[2].items[1].id, 2589); eq(r.tabs[2].items[1].n, 200); eq(r.money, 1234567); eq(r.by, "Pyralis Ashandar-Realm")
			eq(r.tabs[1].items[2].s, 5, "the slot it sits in")
			eq(r.tabs[1].name, "Consumables")
			ns.Roster.RankOf = savedRank
			-- What the tab shows: the newest of our own snapshot (the King's guild's) and his.
			eq(B.Current(), r)
			ns.rdb.bank = { t = r.t + 10, guild = "Olympus", by = ns.me, tabs = {} }; eq(B.Current(), ns.rdb.bank, "ours, newer")
			ns.rdb.bank = { t = r.t + 10, guild = "Olympus II", by = ns.me, tabs = {} }; eq(B.Current(), r, "another guild's bank stays on its own screen")
			ns.rdb.bank = nil
			-- The King with nothing from the Treasurer's book yet: the sections waiting, the bank there.
			local lines = T.Build()
			local page = Texts(lines)
			assert(page:find(ns.L.TREASURY_RANKING, 1, true), "the ranking, empty for now: " .. page)
			assert(page:find(ns.L.TREASURY_BANK, 1, true) and page:find("Consumables", 1, true), page)
			local grids = {}
			for _, l in ipairs(lines) do if l.items then grids[#grids + 1] = l end end
			eq(#grids, 1, "one tab open at a time, as the bank's"); eq(#grids[1].items, 2); eq(grids[1].items[1].id, 929)
			eq(grids[1].slots, 98); eq(grids[1].columns, 7)
			-- A click on another tab opens it.
			for _, l in ipairs(lines) do if l.key == "banktab2" then l.onClick() end end
			lines = T.Build(); grids = {}
			for _, l in ipairs(lines) do if l.items then grids[#grids + 1] = l end end
			eq(grids[1].items[1].id, 2589)
			T.bankTab = nil
			-- A soldier: with the King's book switch only.
			AsSoldier()
			ns.rdb.treasuryFlags = nil
			assert(not Texts(T.Build()):find(ns.L.TREASURY_BANK, 1, true), "hidden from the army")
			ns.rdb.treasuryFlags = { book = true, at = 1 }
			assert(Texts(T.Build()):find("Consumables", 1, true), "shown with the book")
			-- Too old: gone.
			r.t = r.t - B.REPORT_KEPT - 1
			eq(B.Report(), nil)
		end)
		GetNumGuildBankTabs, GetGuildBankTabInfo, GetGuildBankItemInfo, GetGuildBankItemLink, GetGuildBankMoney, ns.splitNames, ns.Comm.SendChunked, ns.Roster.RankOf = unpack(saved, 1, 8)
		ns.rdb.treasuryFlags = nil
		if not ok then error(err, 0) end
	end)
end)

test("an items row: icons in a grid, the row as tall as it needs, a text row after it back to one line", function()
	WithUI(function()
		LoadUI()
		local content = CreateFrame("Frame")
		content.w, content.style = 300, "hd"
		local items = {}
		for i = 1, 20 do items[i] = { id = 900 + i, n = i, icon = "tex" .. i } end
		ns.Views.Render(content, { { text = "a" }, { items = items }, { text = "b" }, { items = { { id = 1, n = 1 } } } })
		local r = content.rows[2]
		eq(#r.items, 20); eq(r.items[1].icon.texture, "tex1"); eq(r.items[1].count.text, "", "one: no count"); eq(r.items[2].count.text, "2")
		eq(r.h, 3 * 32 + 4, "nine per row at 300 wide: three rows")
		eq(r.items[10]:Anchor("TOPLEFT")[4], 4); eq(r.items[10]:Anchor("TOPLEFT")[5], -2 - 32, "the tenth starts the second row")
		eq(content.rows[3].h, 20, "a text row again"); eq(content.rows[4].h, 32 + 4)
		eq(content.rows[4].items[1].icon.texture, "Interface\\Icons\\INV_Misc_QuestionMark", "no icon known: a question mark")
		-- A bank tab: every slot drawn, the items where they sit, seven a row.
		ns.Views.Render(content, { { items = { { id = 5, n = 2, s = 9 } }, slots = 14, columns = 7 } })
		local tab = content.rows[1]
		eq(tab.h, 2 * 32 + 4); eq(tab.items[9].item.id, 5); eq(tab.items[1].item, nil); eq(tab.items[1].icon.shown, false, "an empty slot")
		eq(tab.items[14]:IsShown(), true); eq(tab.items[15] and tab.items[15]:IsShown() or false, false)
		eq(tab.items[8]:Anchor("TOPLEFT")[4], 4); eq(tab.items[8]:Anchor("TOPLEFT")[5], -2 - 32, "the eighth starts the second row")
		-- Rendered again as text: the icons go.
		ns.Views.Render(content, { { text = "a" }, { text = "c" } })
		eq(content.rows[2].items[1]:IsShown(), false); eq(content.rows[2].h, 20)
	end)
end)

test("the soldier count explains the census on hover; the minimap logo sits on its disc", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		assert(main.headerHover, "a hover region over the count")
		main.headerHover:Fire("OnEnter")
		eq(GameTooltip.owner, main.headerHover)
		eq(GameTooltip.lines[1], ns.L.HEADER_TIP_TITLE); eq(GameTooltip.lines[2], ns.L.HEADER_TIP); eq(GameTooltip.lines[4], ns.L.HEADER_TIP_DIFFER)
		assert(main.headerHover.w > 100, "as wide as the header")
		local b = ns.MakeRoundButton("OlympusTestRound", UIParent, 31)
		eq(b.icon.w, 18)
		local a = b.icon:Anchor("TOPLEFT")
		eq(a[4] .. " " .. a[5], "8 -6", "the logo's centre on the disc's (17, -15)")
	end)
end)

test("Royal Writs: the King writes to his Lords, each can acknowledge, nobody else reads it", function()
	WithUI(function()
		LoadUI()
		WithThrone(function(w, K)
			local A = ns.Acts
			AsCaptain(); A.SendWrit("L", "Hello there")
			eq(#w.sent, 0, "the King's alone")
			AsKing()
			A.SendWrit("L", "Muster at dawn|cffff0000 in Goldshire")
			local msg = LastSent(w)
			assert(msg:find("^T1~W~%d+~Olympus~L~Muster at dawn cffff0000 in Goldshire$"), msg)
			local id = tonumber(msg:match("T1~W~(%d+)"))
			-- A Lord: on parchment, one click acknowledges.
			AsLord()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", msg)
			eq(#ns.rdb.writs, 1)
			local f = OlympusWritFrame
			assert(f:IsShown(), "the writ")
			eq(f.body:GetText(), "Muster at dawn cffff0000 in Goldshire")
			eq(f.sign:GetText(), ns.L.WRIT_SIGNED:format("Asmond"))
			f.ack:Click()
			eq(w.whispered[1].to, "Asmongold Asmongler-Realm"); eq(w.whispered[1].msg, ("T6~%d~Olympus Zeus"):format(id))
			local decrees = Texts(ns.Views.Build("decrees"))
			assert(decrees:find(ns.L.WRITS, 1, true) and decrees:find("Muster at dawn", 1, true), decrees)
			-- A Captain reads the writs to Lords and Captains only; a soldier none.
			ns.rdb.writs = nil; A.Reset()
			AsCaptain()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", msg)
			eq(ns.rdb.writs, nil, "for the Lords")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~W~12~Olympus~C~Hold the bridge")
			eq(#ns.rdb.writs, 1, "for Lords and Captains")
			A.Reset(); ns.rdb.writs = nil
			AsSoldier()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~W~13~Olympus~C~Hold the bridge")
			eq(ns.rdb.writs, nil)
			assert(not Texts(ns.Views.Build("decrees")):find(ns.L.WRITS, 1, true), "no section for a soldier")
			-- A Hand's writ is no writ.
			AsKing(); K.AddHand("Helper"); K.SendHands(true); local list = LastSent(w)
			AsLord(); A.Reset()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~W~14~Olympus II~L~Obey me")
			eq(ns.rdb.writs, nil, "a Hand writes no writ")
			-- The King counts who acknowledged: once each.
			AsKing()
			A.HandleAck("WHISPER", "Zed-Realm", ("T6~%d~Olympus Zeus"):format(id))
			A.HandleAck("WHISPER", "Zed-Realm", ("T6~%d~Olympus Zeus"):format(id))
			A.HandleAck("WHISPER", "Troll-Realm", ("T6~%d~Trolls"):format(id))
			eq(ns.rdb.writsSent[1].acks, 1)
			assert(Texts(ns.Views.Build("decrees")):find(ns.L.WRIT_ACKS:format(1), 1, true))
		end)
	end)
end)

test("Open the Gates and the Royal Pardon: the King's word in the Realm and on the Wall", function()
	WithThrone(function(w, K)
		local A = ns.Acts
		AsKing()
		A.OpenGates("Olympus Zeus")
		local msg = LastSent(w)
		assert(msg:find("^T1~G~%d+~Olympus~7200~Olympus Zeus$"), msg)
		-- Everyone: on top of Recruiting.
		A.Reset()
		AsSoldier()
		K.HandleCommand("CHANNEL", "Faker-Realm", "T1~G~3~Olympus~7200~Olympus Faker")
		eq(A.Gates(), nil, "not the King nor a Hand")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~G~3~Olympus~7200~Horde Heroes")
		eq(A.Gates(), nil, "an Olympus guild only")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", msg)
		eq(A.Gates().guild, "Olympus Zeus")
		assert(Printed(w, "Asmond opened the gates of <Olympus Zeus>"), "told")
		local realm = Texts(ns.Views.RealmLines())
		assert(realm:find(ns.L.GATES_LINE:format("Olympus Zeus"), 1, true), realm)
		-- A Hand may open them; only the opener or the King closes them.
		AsKing(); K.AddHand("Helper"); K.AddHand("Other"); K.SendHands(true); local list = LastSent(w)
		AsSoldier()
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~G~4~Olympus II~7200~Olympus II")
		eq(A.Gates().guild, "Olympus II")
		K.HandleCommand("CHANNEL", "Other-Realm", "T1~G~4~Olympus II~0~")
		eq(A.Gates().guild, "Olympus II", "another Hand can't close them")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~G~4~Olympus~0~")
		eq(A.Gates(), nil, "the King can")
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~G~5~Olympus II~7200~Olympus II")
		w.clock = w.clock + A.GATES_TIME + 1
		eq(A.Gates(), nil, "two hours at most")
		-- (A census as fresh as the clock: two hours on, the old one no longer names the King.)
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 90, zones = {}, t = w.clock, leader = "Asmongold Asmongler", realm = "Realm" }, "W1-Realm", "W2-Realm") }
		-- The pardon: off the Wall for everyone, the King's alone.
		ns.Inspect.shame = { by = "Asmon", list = { { name = "Naked", guild = "Olympus II" }, { name = "Pirate", guild = "Olympus II" } }, t = w.clock }
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~F~6~Olympus II~Naked")
		eq(#ns.Inspect.shame.list, 2, "not a Hand's to give")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~F~6~Olympus~Naked")
		eq(#ns.Inspect.shame.list, 1); eq(ns.Inspect.shame.list[1].name, "Pirate")
		assert(Printed(w, "By royal pardon of Asmond, Naked leaves the Wall of Shame"), "told")
		-- A list published later does not bring the name back (for a week).
		ns.Inspect.ShowShame({ by = "Zed", list = { { name = "Naked", guild = "Olympus II" }, { name = "Pirate", guild = "Olympus II" } }, t = w.clock })
		eq(#ns.Inspect.shame.list, 1)
		w.clock = w.clock + A.PARDON_DAYS * 86400 + 1
		eq(A.Pardoned("Naked"), false, "a week")
	end)
end)

test("Throne review fixes: the King sees his Hands' acts, one question at a time", function()
	WithUI(function()
		WithThrone(function(w, K)
			local A, V, C = ns.Acts, ns.Vox, ns.Court
			-- The King's own client trusts his list: a Hand's gates show for him, he closes them.
			AsKing(); K.AddHand("Helper"); K.SendHands(true)
			local list = LastSent(w)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~G~31~Olympus II~7200~Olympus Zeus")
			eq(A.Gates() and A.Gates().guild, "Olympus Zeus", "the King sees his Hand's gates")
			eq(A.CanClose(), true)
			A.CloseGates()
			assert(LastSent(w):find("^T1~G~31~Olympus~0~$"), LastSent(w))
			-- ...and is not summoned by his own Hand.
			local popups = #w.popups
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~S~32~Olympus II")
			eq(#w.popups, popups, "no roll call popup for the King")
			-- Another Hand can't close gates a Hand opened: told so, nothing sent.
			AsSoldier("Other2"); A.Reset()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~G~33~Olympus II~7200~Olympus Zeus")
			local sent = #w.sent
			A.CloseGates()
			eq(#w.sent, sent); assert(Printed(w, ns.L.GATES_ONLY_OPENER), "told")
			-- Vox: a Hand's question does not replace the King's; the King's replaces a Hand's.
			V.Reset(); AsSoldier("Voter")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~41~Olympus II~60~1~Pizza?~Yes~No")
			eq(select(3, V.State()).id, 41)
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~V~42~Olympus~60~1~Raid?~Yes~No")
			eq(select(3, V.State()).id, 42, "the King's question comes first")
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~43~Olympus II~60~1~Tacos?~Yes~No")
			eq(select(3, V.State()).id, 42, "a Hand's waits for the King's")
			-- The window comes back when questions are turned on again.
			V.Reset(); ns.db.voxOff = true
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~V~44~Olympus~60~1~Raid again?~Yes~No")
			eq(V.Frame() and V.Frame():IsShown() or false, false)
			V.SetOff(false)
			assert(V.Frame():IsShown(), "the window to vote")
			-- The asker is told when someone else's question is still open.
			AsKing(); K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~45~Olympus II~60~1~Soup?~Yes~No")
			-- (not shown on the King's client: he asks freely)
			eq(select(3, V.State()).id, 44)
			-- Pardons: the week's pardons go out together, and again for late logins.
			AsKing()
			A.Pardon("Naked"); A.Pardon("Pirate")
			assert(LastSent(w):find("^T1~F~%d+~Olympus~Naked,Pirate$"), LastSent(w))
			A.Pardon("Bad|cffname")
			assert(Printed(w, ns.L.PARDON_BAD_NAME), "a name that is no name is refused")
			AsSoldier()
			ns.rdb.pardons = nil
			ns.Inspect.shame = { by = "Asmon", list = { { name = "Naked" }, { name = "Pirate" }, { name = "Honest" } }, t = w.clock }
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~F~9~Olympus~Naked,Pirate")
			eq(#ns.Inspect.shame.list, 1); eq(ns.Inspect.shame.list[1].name, "Honest")
			-- A Wall of Shame name carries no codes.
			local decoded = ns.Codec.DecodeShame("S1~Olympus~0~Bad|cffff0000Guy:Olympus II,Good:Olympus II")
			eq(decoded.list[1].name, "Badcffff0000Guy"); eq(decoded.list[2].name, "Good")
			-- The court: called after a /reload (the request made in an earlier session).
			local map = 1453
			C_Map.GetBestMapForUnit = function() return map end
			C_Map.GetMapInfo = function() return { mapType = 3 } end
			GetRealZoneText = function() return "Stormwind City" end
			C.Reset()
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~C~51~Olympus~1453~Stormwind City")
			C.HandleCall("WHISPER", "Asmongold Asmongler-Realm", "T5~51")
			assert(C.Current().calledAt, "called")
		end)
	end)
end)

test("Round 2 fixes: shares add up to 100, the King is never shut out, a trade is counted", function()
	WithUI(function()
		WithThrone(function(w, K)
			local V, T = ns.Vox, ns.Treasury
			-- One pick each: whole percents that add up to exactly 100.
			local rows = V.Tally({ "A", "B", "C" }, { 1, 1, 1 }, 3, false)
			eq(rows[1].pct + rows[2].pct + rows[3].pct, 100); eq(rows[1].pct, 34)
			rows = V.Tally({ "A", "B", "C" }, { 1, 1, 2 }, 4, false)
			eq(rows[1].pct + rows[2].pct + rows[3].pct, 100)
			-- A Hand's short question just over: the King's, 10 s later, still reaches everyone.
			AsKing(); K.AddHand("Helper"); K.SendHands(true); local list = LastSent(w)
			AsSoldier("Voter")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~V~51~Olympus II~30~1~Pizza?~Yes~No")
			w.clock = w.clock + 31
			K.HandleCommand("CHANNEL", "Helper-Realm", "T1~E~51~Olympus II~2~1~1")
			w.clock = w.clock + 10
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~V~52~Olympus~60~1~Raid?~Yes~No")
			eq(select(3, V.State()).id, 52, "the King's question")
			-- The same asker again within SHOW_GAP: not shown.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~V~53~Olympus~60~1~Again?~Yes~No")
			eq(select(3, V.State()).id, 52)
			-- A trade opened right after another closed is still counted.
			local saved = { GetTargetTradeMoney, UnitFullName, ERR_TRADE_COMPLETE, ns.After }
			local ok, err = pcall(function()
				ERR_TRADE_COMPLETE = "Trade complete."
				local timers = {}
				ns.After = function(_, _, fn) timers[#timers + 1] = fn end
				UnitFullName = function(unit) if unit == "NPC" then return "Second", "Realm" end return "Pyralis Ashandar", "Realm" end
				AsTreasurer()
				T.TradeShow()
				local money = 5000
				GetTargetTradeMoney = function() return money end
				T.TradeMoney()
				T.Info(0, "Trade complete.")
				eq(ns.rdb.treasury and #ns.rdb.treasury, 1)
			end)
			GetTargetTradeMoney, UnitFullName, ERR_TRADE_COMPLETE, ns.After = unpack(saved, 1, 4)
			if not ok then error(err, 0) end
		end)
	end)
end)

test("The Realm links the Olympus chats: the channels our rank reads, newest first", function()
	WithThrone(function(w)
		ns.rdb.chat = {
			A = { { t = w.clock - 120, sender = "Aa-Realm", guild = "Olympus II", text = "first" },
				{ t = w.clock - 60, sender = "Bb-Realm", guild = "Olympus Zeus", text = "second |cffff0000red" } },
			C = { { t = w.clock - 30, sender = "Cc-Realm", guild = "Olympus II", text = "captains only" } },
		}
		AsSoldier()
		local lines = ns.Views.RealmLines()
		local link
		for _, l in ipairs(lines) do if l.text and l.text:find(ns.L.CHATS_LINK, 1, true) then link = l end end
		assert(link and link.onClick, Texts(lines))
		link.onClick()
		eq(ns.Views.ChatShown(), true)
		local chat = ns.Views.RealmLines()
		eq(chat[1].text:find(ns.L.CHATS_BACK, 1, true) ~= nil, true, "leads back")
		local text = Texts(chat)
		assert(not text:find("captains only", 1, true), "a soldier does not read [Captains]")
		local a, b = text:find("second", 1, true), text:find("first", 1, true)
		assert(a and b and a < b, "newest first: " .. text)
		assert(text:find("second ||cffff0000red", 1, true), "sanitized: " .. text)
		chat[1].onClick()
		eq(ns.Views.ChatShown(), false)
		-- A Captain reads both.
		AsCaptain()
		ns.Views.ShowChat("C")
		assert(Texts(ns.Views.RealmLines()):find("captains only", 1, true))
		ns.Views.ShowChat(nil)
	end)
end)

test("Comm: urgent messages (a layer ask, a vote) go ahead of the census, never dropped first", function()
	local C = ns.Comm
	local savedSend, savedMember, savedReady = C_ChatInfo and C_ChatInfo.SendAddonMessage, ns.IsMember, nil
	local out = {}
	C_ChatInfo = C_ChatInfo or {}
	local savedCI = C_ChatInfo.SendAddonMessage
	C_ChatInfo.SendAddonMessage = function(_, msg, dist) out[#out + 1] = msg; return true end
	ns.IsMember = function() return true end
	local ok, err = pcall(function()
		for _ = 1, 200 do C.Pump() end -- what earlier tests left waiting
		wipe(out)
		for i = 1, 3 do C.Send("GUILD", "R" .. i) end
		C.Whisper("Aa-Realm", "VOTE", nil, true)
		C.Send("GUILD", "R4")
		C.Whisper("Bb-Realm", "ASK", nil, true)
		for _ = 1, 6 do C.Pump() end
		eq(table.concat(out, ","), "VOTE,ASK,R1,R2,R3,R4")
	end)
	C_ChatInfo.SendAddonMessage, ns.IsMember = savedCI, savedMember
	for _ = 1, 10 do C.Pump() end
	if not ok then error(err, 0) end
end)

test("A player's report: no false King, our layer holds against stray creatures, our channel after the game's", function()
	-- 1. Only another guild reports (a Horde guild of its own): its Lord is not crowned.
	local savedGuilds = ns.rdb.guilds
	ns.rdb.guilds = { ["OLYMPUS DUSTMONKEYS"] = { total = 802, online = 88, zones = {}, t = os.time(), leader = "Paladeath Graveborn", leaderOnline = true, realm = "Realm" } }
	local ok, err = pcall(function()
		for _, l in ipairs(ns.Views.RealmLines()) do
			assert(not (l.text or ""):find(ns.L.KING .. ": ", 1, true), "no King line: " .. tostring(l.text))
		end
	end)
	ns.rdb.guilds = savedGuilds
	if not ok then error(err, 0) end
	-- 2. Two zone UIDs around us: ours holds; a new one takes over only when two creatures show
	-- it and ours is gone; a continent map is no zone.
	local L_ = ns.Layers
	local saved = { UnitGUID, C_Map.GetBestMapForUnit, C_Map.GetMapInfo, ns.Now, IsInInstance }
	ok, err = pcall(function()
		local clock, guid, map = 5000, nil, 1413
		ns.Now = function() return clock end
		IsInInstance = function() return false end
		UnitGUID = function() return guid end
		C_Map.GetBestMapForUnit = function() return map end
		C_Map.GetMapInfo = function(id) return { mapType = id == 1414 and 2 or 3 } end
		L_.Reset()
		local function see(uid, spawn) guid = ("Creature-0-4620-1-%d-3000-000%d"):format(uid, spawn or 1); L_.Observe("target") end
		see(361)
		eq(L_.Mine().zoneUID, 361)
		clock = clock + 1; see(2672, 1)
		eq(L_.Mine().zoneUID, 361, "one stray creature")
		clock = clock + 1; see(361); see(2672, 2)
		eq(L_.Mine().zoneUID, 361, "ours still seen")
		clock = clock + L_.HOLD + 1; see(2672, 3)
		eq(L_.Mine().zoneUID, 2672, "ours gone, the new one on two creatures: moved")
		map = 1414
		clock = clock + 30; see(999, 1); see(999, 2)
		eq(L_.Mine().zoneUID, 2672, "the continent map is no zone")
	end)
	UnitGUID, C_Map.GetBestMapForUnit, C_Map.GetMapInfo, ns.Now, IsInInstance = unpack(saved, 1, 5)
	L_.Reset()
	if not ok then error(err, 0) end
	-- 3. Our channel took /1 before General: moved past General and Trade, in their order.
	local savedCI, savedList, savedName = C_ChatInfo.SwapChatChannelsByChannelIndex, GetChannelList, GetChannelName
	ok, err = pcall(function()
		local slots = { [1] = "OlympusNetH", [2] = "General - Durotar", [3] = "Trade - City" }
		GetChannelList = function()
			local out = {}
			for id = 1, 10 do if slots[id] then out[#out + 1] = id; out[#out + 1] = slots[id]; out[#out + 1] = false end end
			return unpack(out)
		end
		GetChannelName = function(x)
			if type(x) == "number" then return x, slots[x] end
			for id, n in pairs(slots) do if n == x then return id, n end end
			return 0
		end
		C_ChatInfo.SwapChatChannelsByChannelIndex = function(a, b) slots[a], slots[b] = slots[b], slots[a] end
		-- The game's channels are zone channels; a custom one ("world") is not.
		C_ChatInfo.GetChannelInfoFromIdentifier = function(n) return { name = n, zoneChannelID = (n == "world" or n == "OlympusNetH") and 0 or 2 } end
		slots[4] = "world"
		local savedJoined = ns.Comm.JoinedName and ns.Comm.JoinedName()
		ns.Comm.SetJoinedForTest("OlympusNetH")
		ns.Comm.KeepLast()
		eq(slots[1], "General - Durotar"); eq(slots[2], "Trade - City"); eq(slots[3], "OlympusNetH")
		eq(slots[4], "world", "the player's own channel keeps its number")
		ns.Comm.SetJoinedForTest(savedJoined)
	end)
	C_ChatInfo.SwapChatChannelsByChannelIndex, GetChannelList, GetChannelName = savedCI, savedList, savedName
	C_ChatInfo.GetChannelInfoFromIdentifier = nil
	if not ok then error(err, 0) end
end)

test("chat: our own line comes back from the channel once, whatever form the server gives our name", function()
	local C = ns.Channels
	local saved = { me = ns.me, split = ns.splitNames, ready = ns.Comm.ChannelReady, room = ns.Comm.ChatRoom, send = ns.Comm.SendChat,
		guild = GetGuildInfo, realm = ns.realm }
	local ok, err = pcall(function()
		ns.me, ns.splitNames, ns.realm = "Tester Surname-Realm", true, "Realm"
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.Comm.ChannelReady = function() return true end
		ns.Comm.ChatRoom = function() return 3 end
		local sent
		ns.Comm.SendChat = function(msg, done) sent = msg; done(true); return true end
		local t = 1000000
		assert(C.Send("A", "for olympus", t))
		assert(sent, "sent")
		-- Forever writes our own name "Tester-Surname" here: still ours, not shown again.
		local shown, why = C.Receive("CHANNEL", "Tester-Surname", sent, t + 1)
		eq(shown, false); eq(why, "own")
		eq(C.IsMe("Tester Surname"), true); eq(C.IsMe("Tester-Surname-Realm"), true)
		eq(C.IsMe("Testers Urname-OtherRealm"), false, "someone else")
		eq(C.IsMe("Testers Urname"), false, "the same letters split elsewhere: another player")
		eq(C.IsMe("Testers-Urname-Realm"), false)
		eq(C.IsMe("Tester Surname-OtherRealm"), false, "a namesake on another realm")
		eq(C.IsMe("Other Player"), false)
	end)
	ns.me, ns.splitNames, ns.Comm.ChannelReady, ns.Comm.ChatRoom, ns.Comm.SendChat = saved.me, saved.split, saved.ready, saved.room, saved.send
	GetGuildInfo, ns.realm = saved.guild, saved.realm
	if not ok then error(err, 0) end
end)

-- 0.9.1: king-trust (GitHub issue #18: a majority vote could make an outsider the King)
test("#18: outsiders on the channel can't crown one of their own, and the King's commands always count", function()
	WithThrone(function(w, K)
		local D, savedLogin = ns.Data, ns.Comm.loginAt
		local ok, err = pcall(function()
			ns.Comm.loginAt = w.clock - 3600 -- long after login: the old census rules let two senders crown
			local KING = "Asmongold Asmongler-Realm"
			local function Report(leader, officers, sender)
				return D.Receive(Codec.DecodeReport("R2~Olympus~900~90~" .. leader .. "~1~1~~~0,0,0,0,0,0,0~~" .. officers), sender)
			end
			local KINDS = { "S", "I", "A", "X", "H", "W", "G", "F", "C", "Z", "V", "E", "T" }
			local function Obeyed(sender)
				for _, kind in ipairs(KINDS) do
					if K.Authorized(kind, sender, "Olympus") then return kind end
				end
				return nil
			end
			AsSoldier()
			-- Two, then three characters outside <Olympus> report it with the first as its leader,
			-- and nobody of <Olympus> has reported for 15 minutes (the issue's case).
			ns.rdb.guilds = {}
			eq(Report("Atk", "", "Atk-Realm"), false, "a report naming another leader of <Olympus>: nothing")
			eq(Report("Atk", "", "Accomplice-Realm"), false)
			eq(Report("Atk", "Accomplice:1:0", "Third-Realm"), false)
			eq(ns.rdb.guilds.Olympus, nil, "no row: nobody else heads <Olympus> on anyone's screen")
			eq(D.KnownRank("Atk-Realm", "Olympus"), nil, "no rank from the census")
			eq(Obeyed("Atk-Realm"), nil, "none of the King's commands")
			K.HandleCommand("CHANNEL", "Atk-Realm", "T1~A~5~Olympus~600~Stormwind City~Forged raid")
			eq(K.Agenda(), nil, "his agenda goes nowhere")
			K.HandleCommand("CHANNEL", "Atk-Realm", "T1~H~6~Olympus~Accomplice-Realm")
			eq(K.Authorized("A", "Accomplice-Realm", "Olympus II"), false, "nor do his Hands")
			-- The King himself, with no report of his guild at all: obeyed, for his guild only.
			for _, kind in ipairs(KINDS) do eq(K.Authorized(kind, KING, "Olympus"), true, kind) end
			eq(K.Authorized("S", KING, "Olympus II"), false, "speaking for another guild")
			-- The real reporter and runner-up, then three outsiders against them: the forged
			-- reports count for nothing, not even as votes.
			eq(Report("Asmongold Asmongler", "Duke:1:0", "Crier-Realm"), true)
			eq(Report("Asmongold Asmongler", "Duke:1:0", "Clerk-Realm"), true)
			for _, atk in ipairs({ "Atk-Realm", "Accomplice-Realm", "Third-Realm" }) do
				eq(Report("Atk", "Accomplice:1:0", atk), false, atk)
			end
			eq(ns.rdb.guilds.Olympus.leader, "Asmongold Asmongler", "the row keeps the King")
			eq(ns.rdb.guilds.Olympus.vouch["Atk-Realm"], nil, "no vote")
			eq(D.KnownRank(KING, "Olympus"), 0); eq(D.KnownRank("Atk-Realm", "Olympus"), nil)
			eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "the real officers keep theirs")
			eq(Obeyed("Atk-Realm"), nil)
			K.HandleCommand("CHANNEL", KING, "T1~A~7~Olympus~600~Stormwind City~Raid at dawn")
			eq(K.Agenda() and K.Agenda().title, "Raid at dawn", "the King's agenda")
			-- Even a census the forgers had won (kept from an older version, or heard by a copy
			-- of the addon without the check) makes nobody King: his name does.
			ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 900, online = 90, zones = {}, t = w.clock, leader = "Atk", realm = "Realm" },
				"Accomplice-Realm", "Third-Realm", "Fourth-Realm") }
			eq(D.KnownRank("Atk-Realm", "Olympus"), 0, "the census says Atk")
			eq(Obeyed("Atk-Realm"), nil, "his commands still count for nothing")
			K.HandleCommand("CHANNEL", KING, "T1~X~7~Olympus")
			eq(K.Agenda(), nil, "the King's cancel counts")
			-- His Hands are his alone to name.
			K.HandleCommand("CHANNEL", KING, "T1~H~8~Olympus~Helper-Realm")
			eq(K.Authorized("A", "Helper-Realm", "Olympus II"), true, "the King's Hand")
			eq(K.Authorized("A", "Accomplice-Realm", "Olympus II"), false)
		end)
		ns.Comm.loginAt = savedLogin
		if not ok then error(err, 0) end
	end)
end)

test("#18: an officer of <Olympus> the census names is of the Crown like any Lord, never the King", function()
	WithThrone(function(w, K)
		local D, savedLogin = ns.Data, ns.Comm.loginAt
		local ok, err = pcall(function()
			ns.Comm.loginAt = w.clock - 3600
			local function Report(officers, sender)
				return D.Receive(Codec.DecodeReport("R2~Olympus~900~90~Asmongold Asmongler~1~1~~~0,0,0,0,0,0,0~~" .. officers), sender)
			end
			AsSoldier()
			ns.rdb.guilds = {}
			eq(Report("Duke:1:0", "Crier-Realm"), true)
			eq(Report("Duke:1:0", "Clerk-Realm"), true)
			-- Three outsiders keep the King at its head and add one of their own as an officer.
			for _, s in ipairs({ "Atk-Realm", "Accomplice-Realm", "Third-Realm" }) do Report("Atk:1:0", s) end
			eq(D.KnownRank("Asmongold Asmongler-Realm", "Olympus"), 0, "every picture names the King")
			-- The officers of <Olympus> are of the Crown: [Lords] and the Crown's decrees, what every
			-- guild master of an Olympus guild has. Nothing of the King's.
			eq(ns.Channels.LevelOf("Olympus", 1), ns.Channels.LevelOf("Olympus Zeus", 0))
			for _, kind in ipairs({ "S", "I", "A", "X", "H", "W", "G", "F", "C", "Z", "V", "E", "T", "P", "Q" }) do
				eq(K.Authorized(kind, "Atk-Realm", "Olympus"), false, kind)
			end
		end)
		ns.Comm.loginAt = savedLogin
		if not ok then error(err, 0) end
	end)
end)

test("#18: the Horde, with no King named yet: the census King commands nothing, his crown still shows", function()
	WithThrone(function(w, K)
		local savedFaction, savedLogin, savedPin, savedGuild = ns.faction, ns.Comm.loginAt, ns.KING_CHARACTER.Horde, ns.KING_GUILD.Horde
		local ok, err = pcall(function()
			-- (0.9.4 names the Horde's King: this checks the rule for a side where none is named.)
			ns.KING_CHARACTER.Horde, ns.KING_GUILD.Horde = nil, "olympus"
			ns.faction = "Horde"
			ns.Comm.loginAt = w.clock - 3600
			ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 300, online = 30, zones = {}, t = w.clock, leader = "Hordeking", realm = "Realm" },
				"W1-Realm", "W2-Realm") }
			eq(ns.Data.KnownRank("Hordeking-Realm", "Olympus"), 0, "the census knows him")
			AsSoldier()
			for _, kind in ipairs({ "S", "I", "A", "X", "H", "W", "G", "F", "C", "Z", "V", "E", "T" }) do
				eq(K.Authorized(kind, "Hordeking-Realm", "Olympus"), false, kind)
			end
			K.HandleCommand("CHANNEL", "Hordeking-Realm", "T1~A~5~Olympus~600~Orgrimmar~Raid")
			eq(K.Agenda(), nil, "no agenda")
			K.HandleCommand("CHANNEL", "Hordeking-Realm", "T1~H~6~Olympus~Helper-Realm")
			eq(K.Authorized("A", "Helper-Realm", "Olympus II"), false, "no Hands")
			-- What only shows: his crown on the map, and his name on the lines.
			eq(K.FromKing("Hordeking-Realm", "Olympus"), true)
			K.HandleCommand("CHANNEL", "Hordeking-Realm", "T1~P~3~Olympus~1453~420~510")
			eq(K.Location() and K.Location().mapID, 1453, "his crown")
			eq(K.Authorized("P", "Other-Realm", "Olympus"), false, "nobody else's")
			eq(K.Authorized("S", "Asmongold Asmongler-Realm", "Olympus"), false, "the Alliance's King is none here")
			eq(ns.KingCharacter(), nil)
			eq(ns.Data.OtherKing("Olympus", "Anyone"), false, "no King named to check the reports against")
			-- His own client still has the Throne (his crown on the map works).
			GetGuildInfo = function() return "Olympus", "King", 0 end
			ns.me = "Hordeking-Realm"
			eq(K.IsKing(), true)
		end)
		ns.KING_CHARACTER.Horde, ns.KING_GUILD.Horde = savedPin, savedGuild
		ns.faction, ns.Comm.loginAt = savedFaction, savedLogin
		if not ok then error(err, 0) end
	end)
end)

test("#18: the Treasurer by his name alone: forged votes can't silence his treasury or his bank", function()
	WithThrone(function(w, K)
		local T, B = ns.Treasury, ns.Bank
		ns.rdb.bankReport = nil
		AsSoldier()
		-- A census the forgers won: nobody names him an officer of <Olympus> now.
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 900, online = 90, zones = {}, t = w.clock, leader = "Asmongold Asmongler", realm = "Realm" },
			"Atk-Realm", "Accomplice-Realm", "Third-Realm") }
		eq(ns.Data.KnownRank("Pyralis Ashandar-Realm", "Olympus", true), nil, "the census doesn't name him")
		T.HandleReport("CHANNEL", "Faker-Realm", "T8~Olympus~500~100~0~5~1~-~Giver:100~")
		eq(T.Report(), nil, "not the Treasurer")
		T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", "T8~Olympus II~500~100~0~5~1~-~Giver:100~")
		eq(T.Report(), nil, "not for the King's guild")
		T.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", "T8~Olympus~500~100~0~5~1~-~Giver:100~")
		eq(T.Report() and T.Report().balance, 500, "his treasury")
		local bank = ("T9~Olympus~%d~1234~Main;2589x200"):format(w.clock)
		B.HandleReport("CHANNEL", "Faker-Realm", bank)
		eq(B.Report(), nil, "not the Treasurer")
		B.HandleReport("CHANNEL", "Pyralis Ashandar-Realm", bank)
		eq(B.Report() and B.Report().money, 1234, "his bank")
		ns.rdb.bankReport = nil
	end)
end)

test("#18: the King's own client: guild master of <Olympus> and the character the addon knows", function()
	WithThrone(function(w, K)
		AsKing()
		eq(K.IsKing(), true); eq(K.Visible(), true)
		-- Another guild master of <Olympus> (the guild changed hands): no Throne, nothing sent.
		ns.me = "Usurper-Realm"
		eq(K.IsKing(), false); eq(K.Visible(), false)
		K.Summon(); K.AddHand("Helper")
		eq(#w.sent, 0, "nothing sent")
		eq(#K.Hands(), 0)
		-- His name without the guild master's rank: not the King either.
		GetGuildInfo = function() return "Olympus", "Knight", 1 end
		ns.me = "Asmongold Asmongler-Realm"
		eq(K.IsKing(), false)
		-- His name, whatever realm of the group it carries; nobody else's.
		local realm, kingRealm = ns.realm, ns.KING_REALM
		ns.realm, ns.KING_REALM = "ClassicBetaPvP", "ClassicBetaPvP"
		local both = ns.IsKingCharacter("Asmongold Asmongler-ClassicBetaPvP2") and ns.IsKingCharacter("Asmongold Asmongler")
		local other = ns.IsKingCharacter("Asmongold Asmongler-ClassicBetaPvE")
		ns.realm, ns.KING_REALM = realm, kingRealm
		eq(both, true, "PvP and PvP 2 are one group"); eq(other, false, "a namesake on another realm group is not him")
		eq(ns.IsKingCharacter("Asmongold-Realm"), false); eq(ns.IsKingCharacter("Asmongold Asmongler2"), false)
		eq(ns.IsKingCharacter(nil), false)
	end)
end)

test("#18: rows of <Olympus> naming another leader go at login; refused reports are logged readably", function()
	local D = ns.Data
	local saved = { rdb = ns.rdb, log = ns.db.log, Now = ns.Now, capture = ns.CaptureError }
	local captured
	local ok, err = pcall(function()
		local clock = os.time()
		ns.Now = function() return clock end
		ns.CaptureError = function(where, e) captured = captured or (where .. ": " .. tostring(e)) end
		ns.db.log = {}
		local function Logged(text)
			for _, l in ipairs(ns.db.log) do if l:find(text, 1, true) then return true end end
			return false
		end
		ns.rdb = { guilds = {}, seen = {} }
		-- A sender tied to one guild claims another: the log says which (it was the bare format).
		eq(D.ClaimGuild("Drifter-Realm", "Olympus Zeus"), true)
		eq(D.Receive(Codec.DecodeReport("R2~Olympus Ares~50~5~Ares~1~1~~~0,0,0,0,0,0,0~~"), "Drifter-Realm"), false)
		assert(Logged("ignored Drifter-Realm: already reported Olympus Zeus, now claims Olympus Ares"), table.concat(ns.db.log, "\n"))
		-- A report of <Olympus> (any spelling) naming someone else: refused, and said why.
		eq(D.Receive(Codec.DecodeReport("R2~OLYMPUS~50~5~Atk~1~1~~~0,0,0,0,0,0,0~~"), "Atk-Realm"), false)
		assert(Logged("ignored OLYMPUS from Atk-Realm: names Atk its leader, not the King"), table.concat(ns.db.log, "\n"))
		-- Rows kept from before this version: <Olympus> naming someone else goes at login...
		ns.rdb = { seen = {}, guilds = {
			["Olympus"] = { total = 900, online = 90, zones = {}, t = clock - 60, leader = "Atk" },
			["Olympus Zeus"] = { total = 100, online = 9, zones = {}, t = clock - 60, leader = "Zed" } } }
		CoreFire("INIT")
		eq(ns.rdb.guilds.Olympus, nil, "a forged King's row")
		eq(ns.rdb.guilds["Olympus Zeus"].leader, "Zed", "other guilds stay")
		assert(Logged("dropped guild Olympus: names Atk its leader, not the King"), table.concat(ns.db.log, "\n"))
		-- ...the King's stays, and so does ours, from our own roster (the server's word).
		ns.rdb = { seen = {}, guilds = { ["Olympus"] = { total = 900, online = 90, zones = {}, t = clock - 60, leader = "Asmongold Asmongler" } } }
		CoreFire("INIT")
		eq(ns.rdb.guilds.Olympus and ns.rdb.guilds.Olympus.leader, "Asmongold Asmongler")
		ns.rdb = { seen = {}, guilds = { ["Olympus"] = { total = 900, online = 90, zones = {}, t = clock - 60, leader = "Other", mine = true } } }
		CoreFire("INIT")
		eq(ns.rdb.guilds.Olympus and ns.rdb.guilds.Olympus.leader, "Other", "our own roster's")
	end)
	ns.rdb, ns.db.log, ns.Now, ns.CaptureError = saved.rdb, saved.log, saved.Now, saved.capture
	if not ok then error(err, 0) end
	eq(captured, nil, "no error at login")
end)

-- 0.9.1: scale
test("0.9.1 census requests at scale: the reporter's answer is its next report sent early, never one more", function()
	local savedChannel, savedGuilds = GetChannelName, ns.rdb.guilds
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		C.JoinChannel()
		cns.After = function(_, _, fn) fn() end
		local sent, broadcast = {}, C.Broadcast
		C.Broadcast = function(r) sent[#sent + 1] = cns.clock; broadcast(r) end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local start = cns.clock
		-- Someone logs in every 10 seconds and asks the channel; our roster scan runs every minute.
		for t = 0, 1790, 10 do
			cns.clock = start + t
			if t % 60 == 0 then C.MaybeBroadcast(ours) end
			Deliver("CHANNEL", "Newbie" .. t, "Q1~")
		end
		eq(C.isReporter, true)
		assert(#sent <= math.floor(1800 / 170) + 2, "one report per 170 s, answers included: " .. #sent)
		assert(#sent >= 9, "the requests are still answered: " .. #sent)
		for i = 2, #sent do assert(sent[i] - sent[i - 1] >= 45, "two reports within 45 s") end
		eq(C.Stats().answered >= 8, true, "answered")
	end)
	GetChannelName, C_ChatInfo, ns.rdb.guilds = savedChannel, nil, savedGuilds
	if not ok then error(err, 0) end
end)

test("0.9.1 census requests at scale: the runner-up still reports once every 10 minutes", function()
	local savedChannel, savedGuilds = GetChannelName, ns.rdb.guilds
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		C.JoinChannel()
		cns.After = function(_, _, fn) fn() end
		local sent, broadcast = {}, C.Broadcast
		C.Broadcast = function(r) sent[#sent + 1] = cns.clock; broadcast(r) end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local start = cns.clock
		for t = 0, 1790, 10 do
			cns.clock = start + t
			if t % 60 == 0 then
				-- Abe, first in the election, says hello and reports: we back him.
				Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
				Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
				C.MaybeBroadcast(ours)
			end
			Deliver("CHANNEL", "Newbie" .. t, "Q1~")
		end
		eq(C.isRunnerUp, true)
		assert(#sent <= math.floor(1800 / 600) + 1, "one report per 600 s, answers included: " .. #sent)
		assert(#sent >= 2, "a request is still answered: " .. #sent)
	end)
	GetChannelName, C_ChatInfo, ns.rdb.guilds = savedChannel, nil, savedGuilds
	if not ok then error(err, 0) end
end)

test("0.9.1 census requests: no second ask once a report came", function()
	local savedChannel, savedGuilds = GetChannelName, ns.rdb.guilds
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		for _, heard in ipairs({ true, false }) do
			local cns, _, Report = FreshComm()
			local C = cns.Comm
			C.JoinChannel()
			local timers = {}
			cns.After = function(_, _, fn) timers[#timers + 1] = fn end
			C.AskCensus()
			eq(C.Stats().asked, 1)
			if heard then Report("Farguy", { guild = "Olympus IV", total = 50, online = 5, zones = {} }) end
			cns.clock = cns.clock + 65
			for _, fn in ipairs(timers) do fn() end
			eq(C.Stats().asked, heard and 1 or 2, heard and "a report came: not asked again" or "nothing heard: asked again")
		end
	end)
	GetChannelName, C_ChatInfo, ns.rdb.guilds = savedChannel, nil, savedGuilds
	if not ok then error(err, 0) end
end)

test("0.9.1 layer hop: an ask that finds nobody waits longer each time (20, 60, 180 s), the usual wait again after a hop", function()
	WithHop(function(w, H)
		local printed, savedPrint = {}, ns.Print
		ns.Print = function(m) printed[#printed + 1] = tostring(m) end
		local ok, err = pcall(function()
			w.see(7)
			local function Nobody(wait)
				local before = #w.sent
				H.Ask(1453, 8, "far")
				eq(#w.sent, before + 1, "asked")
				w.clock = w.clock + H.NOBODY
				H.Tick()
				eq(H.State().phase, "done")
				eq(printed[#printed], ns.L.HOP_NOBODY_WAIT:format(wait))
				eq(H.WaitLeft(), wait)
				-- A click before the wait is over: nothing sent, the seconds left.
				w.clock = w.clock + wait - 1
				H.Ask(1453, 8, "far")
				eq(#w.sent, before + 1, "not yet"); eq(printed[#printed], ns.L.HOP_WAIT:format(1))
				w.clock = w.clock + 1
			end
			Nobody(20)
			Nobody(60)
			Nobody(180)
			Nobody(180) -- (at most)
			-- Forgotten after a quiet while.
			w.clock = w.clock + H.BACKOFF_RESET + 1
			eq(H.WaitLeft(), 0)
			-- Someone offered and said no: no invite came, the same wait.
			H.Ask(1453, 8, "far")
			H.HandleOffer("WHISPER", "Aaa-Realm", "LO~1~0~0")
			w.clock = w.clock + H.WINDOW
			H.Tick()
			H.HandleNo("WHISPER", "Aaa-Realm", "LN~1")
			eq(H.State().phase, "done"); eq(printed[#printed], ns.L.HOP_GAVE_UP_WAIT:format(20))
			-- The next ask gets us in a group: the count starts over.
			w.clock = w.clock + 20
			H.Ask(1453, 8, "far")
			H.HandleOffer("WHISPER", "Bbb-Realm", "LO~1~0~0")
			w.clock = w.clock + H.WINDOW
			H.Tick()
			w.group, w.party.party1 = 2, "Bbb"
			H.OnInvite("Bbb")
			H.OnRoster()
			eq(H.State().phase, "joined")
			w.group, w.party.party1 = 0, nil
			H.OnRoster()
			w.clock = w.clock + H.ASK_GAP
			Nobody(20)
		end)
		ns.Print = savedPrint
		if not ok then error(err, 0) end
	end)
end)

test("0.9.1 layer hop: when a crowd asks for one layer at once, our ask goes out a few seconds later", function()
	WithHop(function(w, H)
		local printed, savedPrint = {}, ns.Print
		ns.Print = function(m) printed[#printed + 1] = tostring(m) end
		local ok, err = pcall(function()
			w.see(7)
			-- Eleven askers for layer 8 (one of them twice: counted once), one for layer 9.
			for i = 1, 11 do H.HandleAsk("CHANNEL", "Crowd" .. i .. "-Realm", ("LQ~%d~1453~8"):format(100 + i)) end
			H.HandleAsk("CHANNEL", "Crowd1-Realm", "LQ~200~1453~8")
			H.HandleAsk("CHANNEL", "Lone-Realm", "LQ~201~1453~9")
			eq(H.Crowd(1453, 8, w.clock), 11); eq(H.Crowd(1453, 9, w.clock), 1)
			local before = #w.sent
			H.Ask(1453, 8, "busy")
			eq(#w.sent, before, "a crowd: not at once"); eq(H.State().phase, "queued")
			eq(printed[#printed], ns.L.HOP_CROWDED:format(5))
			H.Ask(1453, 8, "busy")
			eq(printed[#printed], ns.L.HOP_BUSY, "one ask at a time, waiting or not")
			w.clock = w.clock + 4
			H.Tick()
			eq(#w.sent, before)
			w.clock = w.clock + 1
			H.Tick()
			eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~8"); eq(H.State().phase, "asking")
			eq(printed[#printed], ns.L.HOP_ASKING:format("busy"))
			-- The crowd's asks are forgotten after BRAKE_WINDOW.
			w.clock = w.clock + H.BRAKE_WINDOW + 1
			H.Tick()
			eq(H.Crowd(1453, 8, w.clock), 0)
			-- Ten askers are no crowd: sent at once (once that ask found nobody and its wait is over).
			w.clock = w.clock + H.NOBODY
			H.Tick()
			eq(H.State().phase, "done")
			w.clock = w.clock + H.BACKOFF[1]
			for i = 1, 10 do H.HandleAsk("CHANNEL", "Few" .. i .. "-Realm", ("LQ~%d~1453~9"):format(300 + i)) end
			before = #w.sent
			H.Ask(1453, 9, "few")
			eq(#w.sent, before + 1, "not a crowd")
		end)
		ns.Print = savedPrint
		if not ok then error(err, 0) end
	end)
end)

test("0.9.1 layers: our zone's and the King's announcements redraw at once, the rest at most every 5 s", function()
	local saved = { Fire = ns.Fire, After = ns.After, Now = ns.Now, map = C_Map.GetBestMapForUnit, guilds = ns.rdb.guilds }
	local fired, timers, clock = 0, {}, 5000000
	local ok, err = pcall(function()
		ns.Layers.Reset()
		ns.Fire = function(name) if name == "LAYERS_CHANGED" then fired = fired + 1 end end
		ns.After = function(sec, _, fn) timers[#timers + 1] = { at = clock + sec, fn = fn } end
		ns.Now = function() return clock end
		C_Map.GetBestMapForUnit = function() return 1453 end
		ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 1, zones = {}, t = clock, leader = "Kingy" }, "W1-Realm", "W2-Realm") }
		local function Run()
			local due = timers
			timers = {}
			for _, t in ipairs(due) do if t.at <= clock then t.fn() else timers[#timers + 1] = t end end
		end
		ns.Layers.Receive("Here-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus II" })
		eq(fired, 1, "our zone: at once")
		ns.Layers.Receive("Far1-Realm", { mapID = 1429, zoneUID = 3, rank = 4, guild = "Olympus II" })
		ns.Layers.Receive("Far2-Realm", { mapID = 1436, zoneUID = 4, rank = 4, guild = "Olympus II" })
		ns.Layers.Receive("Far3-Realm", { mapID = 1436, zoneUID = 4, rank = 4, guild = "Olympus II" })
		eq(fired, 1, "other zones: not at once"); eq(#timers, 1, "one redraw waits for all of them")
		clock = clock + ns.Layers.FIRE_GAP
		Run()
		eq(fired, 2, "one redraw for the three")
		-- A player leaving our zone changes its list: at once.
		ns.Layers.Receive("Here-Realm", { mapID = 1429, zoneUID = 3, rank = 4, guild = "Olympus II" })
		eq(fired, 3)
		-- The King's own announcement, from anywhere: at once (his line tops the Census).
		clock = clock + 1
		ns.Layers.Receive("Kingy-Realm", { mapID = 1436, zoneUID = 4, rank = 0, guild = "Olympus" })
		eq(fired, 4)
		-- Anyone else of his guild, far away: waits.
		ns.Layers.Receive("Far4-Realm", { mapID = 1436, zoneUID = 4, rank = 4, guild = "Olympus" })
		eq(fired, 4); eq(#timers, 1)
		-- A redraw at once meanwhile showed it already: the waiting one is not needed.
		clock = clock + 1
		ns.Layers.Receive("Here2-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus II" })
		eq(fired, 5)
		clock = clock + ns.Layers.FIRE_GAP
		Run()
		eq(fired, 5, "nothing new to show")
	end)
	ns.Fire, ns.After, ns.Now, C_Map.GetBestMapForUnit, ns.rdb.guilds = saved.Fire, saved.After, saved.Now, saved.map, saved.guilds
	ns.Layers.Reset()
	if not ok then error(err, 0) end
end)

test("0.9.1 tabards: two weeks and 2000 players kept, marked and caught ones first; the page lists 200", function()
	local I = ns.Inspect
	local saved = { rdb = ns.rdb, inspect = ns.rdb.inspect, Now = ns.Now, Print = ns.Print, alert = ns.PlayAlert, capture = ns.CaptureError }
	local ok, err = pcall(function()
		local now, day = 7000000, 86400
		ns.Now = function() return now end
		ns.Print, ns.PlayAlert = function() end, function() end
		local players = {}
		ns.rdb.inspect = { players = players, guildMarks = {} }
		players["Stale"] = { name = "Stale", status = "NONE", t = now - 15 * day }
		players["OldMark"] = { name = "OldMark", status = "GUILD", t = now - 30 * day, marked = true }
		players["Fresh"] = { name = "Fresh", status = "GUILD", t = now - 13 * day }
		players["Broken"] = "not a player"
		I.Prune()
		eq(players["Stale"], nil, "older than two weeks: gone"); eq(players["Broken"], nil)
		eq(players["OldMark"].marked, true, "a mark by hand stays"); eq(players["Fresh"].status, "GUILD")
		-- More than MAX_PLAYERS: a new player recorded trims the store, the ones that matter first.
		for i = 1, 2050 do players["G" .. i] = { name = "G" .. i, status = "GUILD", t = now - i } end
		for i = 1, 60 do players["N" .. i] = { name = "N" .. i, status = i % 2 == 0 and "NONE" or "OTHER", t = now - 10 * day } end
		I.Record("Newcomer", "Olympus II", "MAGE", 60, 5976, true)
		local n = 0
		for _ in pairs(players) do n = n + 1 end
		eq(n, I.MAX_PLAYERS)
		eq(players["N60"].status, "NONE", "caught without the colors: kept"); eq(players["N59"].status, "OTHER")
		eq(players["OldMark"].marked, true); eq(players["Newcomer"].status, "GUILD", "the newest kept")
		eq(players["G1"].status, "GUILD"); eq(players["G2050"], nil, "the oldest checks went"); eq(players["Fresh"], nil)
		-- The Tabards page: the first 200, marked and caught ones on top, the rest counted.
		local rows, more, first = 0, false, nil
		for _, l in ipairs(ns.Views.Build("heraldry")) do
			if l.cols then rows = rows + 1; first = first or l end
			if l.text and l.text:find(ns.L.AND_MORE:format(I.MAX_PLAYERS - ns.Views.INSPECT_ROWS), 1, true) then more = true end
		end
		eq(rows, ns.Views.INSPECT_ROWS); eq(more, true); eq(first.key, "OldMark")
		-- At login too (INIT).
		local captured
		ns.CaptureError = function(where, e) captured = captured or (where .. ": " .. tostring(e)) end
		ns.rdb = { guilds = {}, inspect = { players = { Stale = { name = "Stale", status = "NONE", t = now - 15 * day },
			Kept = { name = "Kept", status = "NONE", t = now - day } }, guildMarks = {} } }
		local R = ns.rdb
		CoreFire("INIT")
		ns.rdb = saved.rdb
		eq(captured, nil, "error caught")
		eq(R.inspect.players.Stale, nil); eq(R.inspect.players.Kept.status, "NONE")
	end)
	ns.rdb = saved.rdb
	ns.rdb.inspect, ns.Now, ns.Print, ns.PlayAlert, ns.CaptureError = saved.inspect, saved.Now, saved.Print, saved.alert, saved.capture
	if not ok then error(err, 0) end
end)

test("0.9.2 untabarded: the King's list, the army sees it only while he lets it, quietly; nobody else publishes", function()
	WithThrone(function(w, K)
		local I = ns.Inspect
		local saved = { from = I.SHAME_FROM, alert = ns.PlayAlert, raid = RaidNotice_AddMessage, share = ns.db.kingUntabarded, me = ns.me, guild = GetGuildInfo }
		local ok, err = pcall(function()
			I.SHAME_FROM = 0
			I.ResetShame()
			local alerts = 0
			ns.PlayAlert = function() alerts = alerts + 1 end
			RaidNotice_AddMessage = function() alerts = alerts + 1 end
			AsSoldier("Other")
			-- A wall from a 0.9.1 Lord (S1): ignored, whoever sends it.
			I.HandleShame("CHANNEL", "Lord1-Realm", ns.Codec.EncodeShame("Olympus II", 0, { { name = "Naked", guild = "Olympus II" } }))
			eq(I.Shame(), nil, "no more walls from Lords")
			-- Hostile: someone else sends the King's kind, with a guild name that says Olympus.
			K.HandleCommand("CHANNEL", "Faker Guy-Realm", "T1~U~5~Olympus~1~Victim:Olympus II")
			eq(I.Shame(), nil, "not the King: nothing shown")
			-- The King's list: shown in the Tabards tab only, no alert, no sound, no line.
			local printed = #w.printed
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~U~6~Olympus~1~Naked:Olympus II,Pirate:Olympus II")
			eq(#I.Shame().list, 2); eq(alerts, 0, "no alert, no sound"); eq(#w.printed, printed, "no chat line")
			K.HandleCommand("CHANNEL", "Faker Guy-Realm", "T1~U~7~Olympus~0")
			eq(#I.Shame().list, 2, "only the King takes it off")
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~U~8~Olympus~0")
			eq(I.Shame(), nil, "off: it leaves the screen")
			-- A list he stopped repeating leaves too.
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~U~9~Olympus~1~Naked:Olympus II")
			w.clock = w.clock + I.SHARED_FRESH + 1
			eq(I.Shame(), nil, "not repeated: gone")
			-- The King's switch: off until he turns it on; on sends the list, off takes it back.
			AsKing()
			ns.db.kingUntabarded = nil
			eq(K.SharingUntabarded(), false)
			local before = #w.sent
			K.ToggleUntabarded()
			eq(K.SharingUntabarded(), true); eq(#w.sent, before + 1)
			assert(LastSent(w):find("^T1~U~%d+~Olympus~1~"), LastSent(w))
			K.ToggleUntabarded()
			eq(K.SharingUntabarded(), false)
			assert(LastSent(w):find("^T1~U~%d+~Olympus~0$"), LastSent(w))
			eq(alerts, 0)
		end)
		I.SHAME_FROM, ns.PlayAlert, RaidNotice_AddMessage, ns.db.kingUntabarded, ns.me, GetGuildInfo = saved.from, saved.alert, saved.raid, saved.share, saved.me, saved.guild
		I.ResetShame()
		if not ok then error(err, 0) end
	end)
end)

test("0.9.1 guild bank: read once the slots settle, a tab that never arrived keeps its items, a change within the gap is sent later", function()
	WithThrone(function(w, K)
		local B = ns.Bank
		local saved = { GetNumGuildBankTabs, GetGuildBankTabInfo, GetGuildBankItemInfo, GetGuildBankItemLink, GetGuildBankMoney,
			QueryGuildBankTab, GetCurrentGuildBankTab, GetTime, ns.After }
		local ok, err = pcall(function()
			B.Reset()
			AsTreasurer()
			local gt, timers = 100, {}
			GetTime = function() return gt end
			ns.After = function(sec, _, fn) timers[#timers + 1] = { at = gt + sec, fn = fn } end
			local function Run()
				local due = timers
				timers = {}
				for _, t in ipairs(due) do if t.at <= gt + 1e-6 then t.fn() else timers[#timers + 1] = t end end
			end
			local function Sent()
				local n = 0
				for _, s in ipairs(w.sent) do if s.msg:find("^T9~") then n = n + 1 end end
				return n
			end
			GetNumGuildBankTabs = function() return 2 end
			GetGuildBankTabInfo = function(tab) return ({ "Consumables", "Materials" })[tab], "icon" .. tab, true end
			local slots = { [1] = { [1] = { "tex1", 20, 929 } }, [2] = {} }
			GetGuildBankItemInfo = function(tab, slot) local s = slots[tab] and slots[tab][slot]; if s then return s[1], s[2] end end
			GetGuildBankItemLink = function(tab, slot) local s = slots[tab] and slots[tab][slot]; return s and ("|Hitem:" .. s[3] .. ":0|h[x]|h") end
			GetGuildBankMoney = function() return 500 end
			QueryGuildBankTab = function() end
			GetCurrentGuildBankTab = function() return 1 end
			-- Opened: tab 1 (on screen) is there, tab 2 still on its way.
			B.Opened()
			gt = gt + 1; B.Changed()
			gt = gt + 0.5; Run()
			eq(ns.rdb.bank, nil, "not read 1.5 s after the first change: another came since")
			slots[2] = { [3] = { "tex3", 200, 2589 } }
			gt = gt + 0.5; B.Changed()
			gt = gt + 1; Run()
			eq(ns.rdb.bank, nil)
			gt = gt + 0.5; Run()
			local snap = ns.rdb.bank
			eq(#snap.tabs, 2); eq(snap.tabs[2].items[1].id, 2589, "read once the last change settled: tab 2 is in")
			eq(Sent(), 1, "the Treasurer's client sends it")
			-- A bank that keeps changing is still read, SETTLE_MAX after the first change.
			for _ = 1, 20 do gt = gt + 0.5; B.Changed(); Run() end
			assert(ns.rdb.bank ~= snap, "read while it kept changing")
			gt = gt + 10; Run(); Run()
			-- Opened again: tab 2's slots never arrive (it reads empty), tab 1 is on screen.
			slots[2] = {}
			B.Opened(); gt = gt + B.SETTLE; Run()
			eq(ns.rdb.bank.tabs[2].items[1].id, 2589, "a tab that never arrived keeps its last items"); assert(ns.rdb.bank.tabs[2].kept)
			-- Read again in the same visit (a deposit): still kept (0.9.2).
			B.Changed(); gt = gt + B.SETTLE; Run()
			eq(ns.rdb.bank.tabs[2].items[1].id, 2589, "the same visit keeps it again")
			B.Closed(); gt = gt + B.SETTLE; Run()
			eq(ns.rdb.bank.tabs[2].items[1].id, 2589, "and on closing")
			-- Empty the next visit too: then it is.
			B.Opened(); gt = gt + B.SETTLE; Run()
			eq(#ns.rdb.bank.tabs[2].items, 0, "empty twice in a row: empty")
			-- The tab on screen reads empty: the player sees it empty.
			slots[1] = {}
			B.Opened(); gt = gt + B.SETTLE; Run()
			eq(#ns.rdb.bank.tabs[1].items, 0)
			-- Another guild's bank says nothing about ours; a 0.9.0 snapshot (no tab numbers) by the tab's name.
			local other = { guild = "Olympus II", tabs = { { i = 2, name = "Materials", items = { { id = 1, n = 1, s = 1 } } } } }
			eq(#B.Keep({ guild = "Olympus", tabs = { { i = 2, name = "Materials", items = {} } } }, other).tabs[1].items, 0)
			local old = { guild = "Olympus", tabs = { { name = "Materials", items = { { id = 7, n = 1, s = 1 } } } } }
			eq(B.Keep({ guild = "Olympus", tabs = { { i = 2, name = "Materials", items = {} } } }, old).tabs[1].items[1].id, 7)
			-- Every read since the first came within SHARE_GAP: the latest goes out once it is over.
			eq(Sent(), 1)
			w.clock = w.clock + B.SHARE_GAP + 1
			gt = gt + B.SHARE_GAP + 1
			Run()
			eq(Sent(), 2, "sent once the gap is over"); eq(LastSent(w), B.Message(ns.rdb.bank), "the bank as it is then")
		end)
		GetNumGuildBankTabs, GetGuildBankTabInfo, GetGuildBankItemInfo, GetGuildBankItemLink, GetGuildBankMoney = saved[1], saved[2], saved[3], saved[4], saved[5]
		QueryGuildBankTab, GetCurrentGuildBankTab, GetTime, ns.After = saved[6], saved[7], saved[8], saved[9]
		B.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("0.9.1 the agenda popup names a Hand as the Hand, the King by the army's name for him", function()
	WithThrone(function(w, K)
		AsKing()
		K.AddHand("Helper")
		K.SendHands(true)
		local list = LastSent(w)
		AsSoldier("Other")
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", list)
		K.HandleCommand("CHANNEL", "Helper-Realm", "T1~A~4~Olympus II~600~Stormwind City~Raid at dawn")
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_AGENDA_CALL")
		eq(p.a, ns.L.THRONE_AGENDA_POPUP_HAND:format("Helper", "Raid at dawn", 10, "Stormwind City"))
		w.clock = w.clock + K.AGENDA_GAP
		K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~A~5~Olympus~1800~The Crossroads~Raid on the Crossroads")
		eq(w.popups[#w.popups].a, ns.L.THRONE_AGENDA_POPUP:format(ns.KING_NAME, "Raid on the Crossroads", 30, "The Crossroads"))
	end)
end)

-- 0.9.1: channel-owner
-- Comm.lua in a namespace of its own, with a clock the test moves and timers that wait for it.
-- The channel's notices come through the real events, in the client's argument order:
-- CHAT_MSG_CHANNEL_NOTICE(_USER)(notice, player, language, "5. OlympusNet", second player,
-- flags, zone channel id, channel number, "OlympusNet", ...).
do
	local NOTICE, USER = "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER"

	local function OwnerComm()
		local events, login, timers, printed = {}, {}, {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
		cns.clock = 100000
		cns.Now = function() return cns.clock end
		cns.After = function(delay, _, fn) timers[#timers + 1] = { at = cns.clock + (delay or 0), fn = fn } end
		cns.Every = function() end
		cns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		local w = { cns = cns, C = cns.Comm, events = events, printed = printed }
		-- A notice about `channel` (default: the one we joined), through the event it comes by.
		function w.Notice(event, notice, player, player2, channel)
			channel = channel or w.C.ChannelName()
			for _, fn in ipairs(events[event] or {}) do
				fn(notice, player or "", "", "5. " .. channel, player2 or "", "", 0, 5, channel, 0, 0, "", 0, false, false, false, false)
			end
		end
		-- Moves the clock, then runs the timers due (and those they set that are due too).
		function w.Wait(seconds)
			cns.clock = cns.clock + seconds
			for _ = 1, 100 do
				local due
				for i, t in ipairs(timers) do if t.at <= cns.clock then due = i break end end
				if not due then return end
				table.remove(timers, due).fn()
			end
			error("timers keep setting timers")
		end
		return w
	end

	-- The channel functions an owner has, recorded ("password OlympusNet,"); all restored after.
	local function WithMocks(fn)
		local saved = { GetChannelName, JoinChannelByName, LeaveChannelByName, SetChannelPassword, ChannelUnban, ChannelModerate,
			ChannelUnmute, GetGuildInfo, ns.rdb.realmKey, ns.Roster.byName, issecretvalue, C_ChatInfo }
		local calls = {}
		local function Rec(what) return function(...) calls[#calls + 1] = what .. " " .. table.concat({ ... }, ",") end end
		local ok, err = pcall(function()
			C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
			GetChannelName = function() return 5 end
			JoinChannelByName, LeaveChannelByName = Rec("join"), Rec("leave")
			SetChannelPassword, ChannelUnban, ChannelModerate, ChannelUnmute = Rec("password"), Rec("unban"), Rec("moderate"), Rec("unmute")
			fn(calls)
		end)
		GetChannelName, JoinChannelByName, LeaveChannelByName, SetChannelPassword, ChannelUnban, ChannelModerate,
			ChannelUnmute, GetGuildInfo, ns.rdb.realmKey, ns.Roster.byName, issecretvalue, C_ChatInfo = unpack(saved, 1, 12)
		if not ok then error(err, 0) end
	end

	local function Sorted(calls, from)
		local out = {}
		for i = from or 1, #calls do out[#out + 1] = calls[i] end
		table.sort(out)
		return table.concat(out, "; ")
	end

	test("channel owner: our channel's notices are followed, logged and in /oly status; another channel's are not", function()
		WithMocks(function(calls)
			local w = OwnerComm()
			w.C.JoinChannel()
			eq(w.C.ChannelName(), "OlympusNet")
			w.Notice(NOTICE, "YOU_JOINED")
			w.Notice(USER, "OWNER_CHANGED", "Bob", nil, "General - Elwynn Forest")
			w.Notice(USER, "OWNER_CHANGED", "Bob", nil, "OlympusNetH")
			w.Notice(NOTICE, "WRONG_PASSWORD", nil, nil, "MyOwnChannel")
			eq(w.C.GuardStats().owner, nil, "another channel's owner is not ours")
			eq(w.C.GuardStats().locked, nil, "nor its password")
			w.Notice(USER, "OWNER_CHANGED", "Bob")
			local st = w.C.GuardStats()
			eq(st.owner, "Bob"); eq(st.role, "member"); eq(st.watched, true)
			w.Notice(USER, "PASSWORD_CHANGED", "Bob")
			w.Notice(USER, "PLAYER_BANNED", "Pyralis Ashandar", "Bob")
			w.Notice(USER, "PLAYER_KICKED", "Carl", "Bob")
			w.Notice(USER, "MODERATION_ON", "Bob")
			w.Notice(USER, "ANNOUNCEMENTS_ON", "Bob")
			w.Notice(USER, "UNSET_VOICE", "Dan")
			w.Notice(USER, "SET_MODERATOR", "Bobsfriend")
			st = w.C.GuardStats()
			eq(st.seen.owner, 1); eq(st.seen.password, 1); eq(st.seen.ban, 1); eq(st.seen.kick, 1); eq(st.seen.mute, 1); eq(st.seen.moderator, 1)
			eq(st.moderation, "on"); eq(st.announce, "on"); eq(st.password, true); eq(st.banned, 1); eq(st.muted, 1)
			-- The name in whatever case the server keeps it.
			w.Notice(USER, "OWNER_CHANGED", "Eve", nil, "olympusnet")
			eq(w.C.GuardStats().owner, "Eve")
			-- Forever's secret values (chat lockdown): nothing is read from them.
			issecretvalue = function(v) return v == "Secret" end
			w.Notice(USER, "OWNER_CHANGED", "Secret")
			eq(w.C.GuardStats().owner, "Eve")
			issecretvalue = nil
			assert(table.concat(ns.db.log, "\n"):find("channel OlympusNet: PLAYER_BANNED Pyralis Ashandar by Bob", 1, true), "logged")
			-- Not ours to fix: nothing is done, nothing is printed.
			w.Wait(1000)
			eq(#calls, 0, table.concat(calls, "; ")); eq(#w.printed, 0)
			local savedComm = ns.Comm
			ns.Comm = w.C
			local ok, text = pcall(ns.StatusText)
			ns.Comm = savedComm
			assert(ok, text)
			for _, want in ipairs({ "channel owner: Eve (", "|  me: member  |  watched: true",
				"channel seen: ban=1 kick=1 moderation=1 moderator=1 mute=1 owner=2 password=1  |  moderation=on announce=on",
				"channel undo: password=true banned=1 muted=1  |  locked: no" }) do
				assert(text:find(want, 1, true), want .. "\n" .. text)
			end
		end)
	end)

	test("channel owner: handed the channel, the player is told once a session, in one line", function()
		WithMocks(function()
			local w = OwnerComm()
			w.C.JoinChannel()
			w.Notice(NOTICE, "YOU_JOINED")
			-- An owner's two notices: the moderator's seat, then the channel.
			w.Notice(USER, "SET_MODERATOR", "Tester")
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			eq(w.C.GuardStats().role, "owner")
			w.Wait(2)
			eq(#w.printed, 1, "one line")
			assert(w.printed[1]:find(ns.L.CHANNEL_OWNER_YOU:format("OlympusNet"), 1, true), w.printed[1])
			for _, want in ipairs({ "never uses", "/password", "/ban", "/owner" }) do assert(ns.L.CHANNEL_OWNER_YOU:find(want, 1, true), want) end
			-- Given away and handed back: not told again this session.
			w.Notice(USER, "OWNER_CHANGED", "Bob")
			w.Notice(USER, "UNSET_MODERATOR", "Tester")
			eq(w.C.GuardStats().role, "member")
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			eq(#w.printed, 1, "once a session")
			-- A moderator's seat alone: its own line, once.
			local m = OwnerComm()
			m.C.JoinChannel()
			m.Notice(USER, "SET_MODERATOR", "Tester")
			m.Wait(2)
			eq(#m.printed, 1)
			assert(m.printed[1]:find(ns.L.CHANNEL_MODERATOR_YOU:format("OlympusNet"), 1, true), m.printed[1])
			m.Notice(USER, "UNSET_MODERATOR", "Tester")
			m.Notice(USER, "SET_MODERATOR", "Tester")
			m.Wait(2)
			eq(#m.printed, 1)
			-- Someone else handed the channel: nothing for us.
			local o = OwnerComm()
			o.C.JoinChannel()
			o.Notice(USER, "OWNER_CHANGED", "Bob")
			o.Notice(USER, "SET_MODERATOR", "Bob")
			o.Wait(2)
			eq(#o.printed, 0)
		end)
	end)

	test("channel owner: once the channel is ours it undoes the harm seen, rate-limited; never while it is not", function()
		WithMocks(function(calls)
			local w = OwnerComm()
			w.C.JoinChannel()
			w.Notice(NOTICE, "YOU_JOINED")
			w.Notice(USER, "OWNER_CHANGED", "Troll")
			w.Notice(USER, "SET_MODERATOR", "Troll")
			-- Troll locks the channel while he holds it: not ours, nothing is done.
			w.Notice(USER, "PASSWORD_CHANGED", "Troll")
			w.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			w.Notice(USER, "MODERATION_ON", "Troll")
			w.Notice(USER, "UNSET_SPEAK", "Mutey")
			w.Wait(2)
			eq(#calls, 0, table.concat(calls, "; "))
			-- He logs off and WoW hands the channel to us: what he did is undone, once.
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			eq(Sorted(calls), "moderate OlympusNet; password OlympusNet,; unban OlympusNet,Asmongold Asmongler; unban OlympusNet,Kingchar; unban OlympusNet,Pyralis Ashandar; unmute OlympusNet,Mutey")
			-- Troll (still a moderator) does it again at once: undone again, not before a minute.
			wipe(calls)
			w.Notice(USER, "PASSWORD_CHANGED", "Troll")
			w.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			w.Wait(2)
			eq(#calls, 0, "the same call not twice within a minute")
			w.Wait(60)
			eq(Sorted(calls), "password OlympusNet,; unban OlympusNet,Kingchar")
			-- Our own heal's notices, and what is done from our own client, are not undone by us.
			wipe(calls)
			w.Notice(USER, "PASSWORD_CHANGED", "Tester")
			w.Notice(USER, "PLAYER_UNBANNED", "Kingchar", "Tester")
			w.Notice(USER, "MODERATION_OFF", "Tester")
			w.Notice(USER, "PLAYER_BANNED", "Someone", "Tester")
			w.Wait(120)
			eq(#calls, 0, table.concat(calls, "; "))
			-- Moderation is switched over: once for each time it was seen turned on, never back on.
			w.Notice(USER, "MODERATION_ON", "Troll")
			w.Wait(2)
			eq(Sorted(calls), "moderate OlympusNet")
			w.Notice(USER, "PLAYER_KICKED", "Carl", "Troll")
			w.Wait(120)
			eq(#calls, 1, "not switched again without seeing it on again")
			-- The channel goes to someone else: nothing more from us.
			w.Notice(USER, "OWNER_CHANGED", "Troll")
			w.Notice(USER, "PASSWORD_CHANGED", "Troll")
			w.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			w.Wait(120)
			eq(#calls, 1, table.concat(calls, "; "))
			-- Nor after we left the channel.
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Notice(NOTICE, "YOU_LEFT")
			w.Wait(120)
			eq(w.C.GuardStats().role, "member")
			eq(#calls, 1, table.concat(calls, "; "))
		end)
	end)

	test("channel owner: the Treasurer and the King (our roster in his guild, or a pinned character) are always let back in", function()
		WithMocks(function(calls)
			-- In the King's guild: his character from our own roster.
			GetGuildInfo = function() return "Olympus", "Knight", 3 end
			ns.Roster.byName = { ["Knight1-Realm"] = 3, ["Asmon-Realm"] = 0 }
			local w = OwnerComm()
			w.C.JoinChannel()
			w.Notice(NOTICE, "YOU_JOINED")
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			eq(Sorted(calls), "unban OlympusNet,Asmon; unban OlympusNet,Asmongold Asmongler; unban OlympusNet,Pyralis Ashandar", "watched since joining: no password call")
			-- Another guild: the character pinned in Core.lua when there is one, else the Treasurer alone.
			GetGuildInfo = function() return MY_GUILD, "Hero", 3 end
			wipe(calls)
			local p = OwnerComm()
			p.cns.KING_CHARACTER = "Kingchar"
			p.C.JoinChannel()
			p.Notice(NOTICE, "YOU_JOINED")
			p.Notice(USER, "SET_MODERATOR", "Tester")
			p.Wait(2)
			eq(Sorted(calls), "unban OlympusNet,Kingchar; unban OlympusNet,Pyralis Ashandar")
			wipe(calls)
			local n = OwnerComm()
			n.C.JoinChannel()
			n.Notice(NOTICE, "YOU_JOINED")
			n.Notice(USER, "OWNER_CHANGED", "Tester")
			n.Wait(2)
			eq(Sorted(calls), "unban OlympusNet,Asmongold Asmongler; unban OlympusNet,Pyralis Ashandar", "the pinned King is always known")
		end)
	end)

	test("channel owner: handed the public channel without having watched it since joining, its password is cleared", function()
		WithMocks(function(calls)
			-- After a /reload we are still on the channel, but saw nothing that came before it.
			local w = OwnerComm()
			w.C.JoinChannel()
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			assert(Sorted(calls):find("password OlympusNet,", 1, true), Sorted(calls))
			-- Watched since we joined: every change would have reached us, none was made.
			wipe(calls)
			local v = OwnerComm()
			v.C.JoinChannel()
			v.Notice(NOTICE, "YOU_JOINED")
			v.Notice(USER, "OWNER_CHANGED", "Tester")
			v.Wait(2)
			assert(not Sorted(calls):find("password", 1, true), Sorted(calls))
		end)
	end)

	test("channel owner: the sealed channel gets its key back, never cleared; nothing on a keyless-vs-sealed mismatch", function()
		WithMocks(function(calls)
			ns.rdb.realmKey = "sekrit-key"
			local w = OwnerComm()
			local sealed = w.C.ChannelSpec()
			assert(sealed:find("^Oly") and sealed ~= "OlympusNet", sealed)
			w.C.JoinChannel()
			eq(w.C.ChannelName(), sealed)
			w.Notice(NOTICE, "YOU_JOINED")
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			assert(not Sorted(calls):find("password", 1, true), "watched: its password is the key already")
			w.Notice(USER, "PASSWORD_CHANGED", "Troll")
			w.Wait(2)
			eq(calls[#calls], "password " .. sealed .. ",sekrit-key", "set back to the key")
			-- The public channel's notices mean nothing while we are on the sealed one.
			local n = #calls
			w.Notice(USER, "OWNER_CHANGED", "Tester", nil, "OlympusNet")
			w.Notice(USER, "PASSWORD_CHANGED", "Troll", nil, "OlympusNet")
			w.Wait(120)
			eq(#calls, n, Sorted(calls, n + 1))
			-- Owner of the public channel when the key arrives (not moved over yet): no call on either.
			ns.rdb.realmKey = nil
			local p = OwnerComm()
			p.C.JoinChannel()
			eq(p.C.ChannelName(), "OlympusNet")
			p.Notice(USER, "OWNER_CHANGED", "Tester")
			p.Notice(USER, "PASSWORD_CHANGED", "Troll")
			p.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			ns.rdb.realmKey = "sekrit-key"
			p.Wait(2)
			eq(#calls, n, "the public channel's record is not the sealed channel's: " .. Sorted(calls, n + 1))
		end)
	end)

	test("channel owner: should the game refuse one of these calls to addons, healing stops for the session", function()
		WithMocks(function(calls)
			local w = OwnerComm()
			w.C.JoinChannel()
			-- Refused inside the first call, as the game does: the rest of that pass is not made.
			SetChannelPassword = function()
				calls[#calls + 1] = "password"
				for _, fn in ipairs(w.events.ADDON_ACTION_FORBIDDEN) do fn("Olympus", "SetChannelPassword()") end
			end
			w.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			w.Notice(USER, "OWNER_CHANGED", "Tester")
			w.Wait(2)
			eq(Sorted(calls), "password")
			w.Notice(USER, "PLAYER_BANNED", "Kingchar", "Troll")
			w.Wait(120)
			eq(Sorted(calls), "password", "nothing more this session")
			-- Another addon's refusal changes nothing here.
			local o = OwnerComm()
			o.C.JoinChannel()
			for _, fn in ipairs(o.events.ADDON_ACTION_BLOCKED) do fn("OtherAddon", "SetChannelPassword()") end
			o.Notice(NOTICE, "YOU_JOINED")
			o.Notice(USER, "OWNER_CHANGED", "Tester")
			o.Wait(2)
			eq(Sorted(calls), "password; unban OlympusNet,Asmongold Asmongler; unban OlympusNet,Pyralis Ashandar")
		end)
	end)

	test("channel owner: locked out (password or ban), tried again after 1, 2, 5, then every 10 minutes; told once", function()
		WithMocks(function(calls)
			local id = 0
			GetChannelName = function() return id end
			local w = OwnerComm()
			local C = w.C
			local function Joins()
				local n = 0
				for _, c in ipairs(calls) do
					if c:find("^join") then
						n = n + 1
						eq(c, "join OlympusNet", "always the same channel: no other name to flee to")
					end
				end
				return n
			end
			C.JoinChannel()
			eq(Joins(), 1)
			-- The server's answer: a wrong password, and Blizzard's password prompt for the same try.
			w.Notice(NOTICE, "WRONG_PASSWORD")
			for _, fn in ipairs(w.events.CHANNEL_PASSWORD_REQUEST) do fn("OlympusNet") end
			eq(#w.printed, 1, "told once")
			assert(w.printed[1]:find(ns.L.CHANNEL_LOCKED:format("OlympusNet"), 1, true), w.printed[1])
			eq(C.GuardStats().locked.tries, 1, "one failed join, however many notices")
			local joins = 1
			for i, gap in ipairs({ 60, 120, 300, 600, 600 }) do
				w.cns.clock = w.cns.clock + gap - 1
				C.JoinChannel() -- the housekeeping ticker, every minute
				eq(Joins(), joins, "not before " .. gap .. "s")
				w.cns.clock = w.cns.clock + 1
				C.JoinChannel()
				joins = joins + 1
				eq(Joins(), joins, "again after " .. gap .. "s")
				w.Notice(NOTICE, i % 2 == 0 and "WRONG_PASSWORD" or "BANNED")
			end
			eq(#w.printed, 1, "still told once")
			local lock = C.GuardStats().locked
			eq(lock.tries, 6); eq(lock.nextIn, 600)
			-- An honest owner opens it: in at the next try, and the census is asked for again.
			id = 5
			w.Wait(600)
			eq(C.GuardStats().locked, nil, "open again")
			eq(C.ChannelReady(), true)
			w.Wait(4)
			eq(C.Stats().asked, 1, "census asked for once back in")
		end)
	end)
end

-- 0.9.1: privacy
-- Issues #13 and #16: where a player is goes out only with their yes, and the channel's
-- warning comes before the first line in each of its channels.

-- Runs fn(w) reading our layer from NPCs in Stormwind (map 1453), every Comm.Send kept in
-- w.sent; w.observe() reads a new layer, far enough in time to be announced at once.
local function WithLayerWatch(fn)
	local saved = { send = ns.Comm.Send, hello = ns.Comm.Hello, now = ns.Now, print = ns.Print, guid = UnitGUID,
		map = C_Map.GetBestMapForUnit, guild = GetGuildInfo, me = ns.me, share = ns.db.shareLocation, crown = ns.db.throneLocation }
	local w = { sent = {}, printed = {}, hellos = 0, clock = 3000000000, npc = 100 }
	local ok, err = pcall(function()
		ns.Comm.Send = function(dist, msg) w.sent[#w.sent + 1] = dist .. " " .. msg end
		ns.Comm.Hello = function(force) if force then w.hellos = w.hellos + 1 end end
		ns.Now = function() return w.clock end
		ns.Print = function(m) w.printed[#w.printed + 1] = m end
		C_Map.GetBestMapForUnit = function() return 1453 end
		UnitGUID = function() return ("Creature-0-4619-0-%d-68-0000AAA1"):format(w.npc) end
		w.observe = function()
			w.clock, w.npc = w.clock + 1000, w.npc + 1
			ns.Layers.Reset()
			ns.Layers.Observe("target")
		end
		w.layers = function()
			local n = 0
			for _, m in ipairs(w.sent) do if m:find("^CHANNEL L1~") then n = n + 1 end end
			return n
		end
		fn(w)
	end)
	ns.Comm.Send, ns.Comm.Hello, ns.Now, ns.Print, UnitGUID = saved.send, saved.hello, saved.now, saved.print, saved.guid
	C_Map.GetBestMapForUnit, GetGuildInfo, ns.me = saved.map, saved.guild, saved.me
	ns.db.shareLocation, ns.db.throneLocation = saved.share, saved.crown
	ns.Layers.Reset()
	if not ok then error(err, 0) end
end

test("0.9.1 privacy: a player who keeps it private still asks for hops and helps, told once what an ask says (#13)", function()
	local savedShare, savedPrint = ns.db.shareLocation, ns.Print
	local printed = {}
	local function Hints()
		local n = 0
		for _, m in ipairs(printed) do if m == ns.L.HOP_PRIVATE_HINT then n = n + 1 end end
		return n
	end
	local ok, err = pcall(function()
		ns.Print = function(m) printed[#printed + 1] = m end
		WithHop(function(w, H)
			ns.db.shareLocation = nil -- never answered: private
			GetGuildInfo = function() return "Olympus II", "Officer", 1 end
			w.see(7)
			for _, m in ipairs(w.sent) do assert(not m:find("L1~", 1, true), "no layer announced: " .. m) end
			-- A player who shares nothing does not help either (0.9.2): an offer would tell the
			-- asker, anyone on the channel, where they are.
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			eq(w.whispered[1], nil, "private: no offer")
			-- Asking still works: the ask names this zone and the layer wanted, and says so once.
			H.Ask(1453, 8, "Kingy's layer")
			eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~8")
			eq(Hints(), 1)
			w.clock = w.clock + 30
			H.Tick() -- nobody answered: done
			H.Ask(1453, 8, "Kingy's layer")
			eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~8", "asked again")
			eq(Hints(), 1, "once a session")
		end)
		WithHop(function(w, H)
			ns.db.shareLocation = true
			w.see(7)
			H.Ask(1453, 8, "Kingy's layer")
			eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~8")
			eq(Hints(), 1, "sharing: nothing to tell")
		end)
	end)
	ns.db.shareLocation, ns.Print = savedShare, savedPrint
	if not ok then error(err, 0) end
end)

test("0.9.1 privacy: no layer announcement without the player's yes, officers and the sample included (#13)", function()
	WithLayerWatch(function(w)
		-- An officer, never asked yet and after Keep private: the layer is read, and stays home.
		GetGuildInfo = function() return "Olympus II", "Officer", 1 end
		for _, answer in ipairs({ "unanswered", "private" }) do
			ns.db.shareLocation = answer == "private" and false or nil
			w.observe()
			eq(ns.Layers.Mine().zoneUID, w.npc, "read, for this client alone")
			eq(w.layers(), 0, "an officer, " .. answer)
		end
		-- A member of the 1 in 8 sample: the same.
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		for i = 1, 400 do
			ns.me = "Sample" .. i .. "-Realm"
			if ns.Layers.InSample() then break end
		end
		assert(ns.Layers.InSample(), "a sampled name")
		w.observe()
		eq(w.layers(), 0, "a sampled member")
		-- Share: at once, and each new layer; the hello tells our reporter too.
		GetGuildInfo = function() return "Olympus II", "Officer", 1 end
		ns.Layers.SetSharing(true)
		eq(ns.db.shareLocation, true); eq(w.printed[#w.printed], ns.L.LOCATION_ON); eq(w.hellos, 1)
		eq(w.layers(), 1); eq(w.sent[#w.sent], ("CHANNEL L1~1453~%d~1~Olympus II"):format(w.npc))
		w.observe()
		eq(w.layers(), 2)
		-- Off again: nothing more.
		ns.Layers.SetSharing(false)
		eq(ns.db.shareLocation, false); eq(w.printed[#w.printed], ns.L.LOCATION_OFF); eq(w.hellos, 2)
		w.observe()
		eq(w.layers(), 2)
		-- The King: his crown on the map (the Throne) is his yes for his layer; without it, his
		-- own answer like anyone's.
		GetGuildInfo = function() return "Olympus", "King", 0 end
		local me = ns.me
		ns.me = "Asmongold Asmongler-Realm"
		ns.db.throneLocation = true
		w.observe()
		ns.me = me
		eq(w.layers(), 3); eq(w.sent[#w.sent], ("CHANNEL L1~1453~%d~0~Olympus"):format(w.npc))
		ns.db.throneLocation = nil
		w.observe()
		eq(w.layers(), 3)
	end)
end)

test("0.9.1 privacy: a report kept private names no zone at all, and 0.9.0's decoder reads it (#13)", function()
	local r = ns.Roster.Scan()
	assert(r.leaderZone and r.officers[1].zone and r.zones.m1453, "the roster knows where everyone is")
	-- (Codec.DecodeReport is the decoder 0.9.0 ships, unchanged.)
	local d = Codec.DecodeReport(Codec.EncodeReport(Codec.Shareable(r, false, nil)))
	eq(next(d.zones), nil, "no members per zone"); eq(d.leaderZone, nil)
	eq(#d.officers, #r.officers)
	for i, o in ipairs(d.officers) do
		eq(o.zone, nil, o.name); eq(o.name, r.officers[i].name); eq(o.level, r.officers[i].level)
		eq(o.online, r.officers[i].online); eq(o.class, r.officers[i].class)
	end
	eq(d.total, 1000); eq(d.online, 300); eq(d.leader, "Member1"); eq(d.leaderLevel, r.leaderLevel)
	eq(d.classes.WA, r.classes.WA); eq(d.levels[1], r.levels[1]); eq(d.top[1].name, r.top[1].name)
	-- Our own window keeps the whole report.
	eq(r.zones.m1453, 75); assert(r.leaderZone and r.officers[1].zone, "the local report untouched")
	-- Shared: the counts, and the zones of those who share theirs (Member2), nobody else's.
	local s = Codec.DecodeReport(Codec.EncodeReport(Codec.Shareable(r, true, function(name) return name == "Member2" end)))
	eq(s.zones.m1453, 75); eq(s.leaderZone, nil, "the leader did not say yes")
	for _, o in ipairs(s.officers) do eq(o.zone ~= nil, o.name == "Member2", o.name) end
end)

test("0.9.1 privacy: what our census sends follows our answer and our guildmates' hellos (#13)", function()
	local savedChannel, savedShare = GetChannelName, ns.db.shareLocation
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		GetChannelName = function() return 5 end
		C.JoinChannel()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = { dist = dist, msg = msg } end
		-- The report that went out on the channel, put back together and decoded.
		local function Sent()
			for _ = 1, 40 do C.Pump() end
			local asm, out = Codec.NewAssembler(), nil
			for _, m in ipairs(sent) do
				if m.dist == "CHANNEL" then out = Codec.Feed(asm, "Tester-Realm", m.msg, 0) or out end
			end
			sent = {}
			return assert(out and Codec.DecodeReport(out), "a report went out")
		end
		local r = ns.Roster.Scan()
		-- Member2 shares (their hello ends in z), Member3 does not, Member1 (the leader) has no addon.
		Deliver("GUILD", "Member2", "H1~0.9.1~Realm~p~z")
		Deliver("GUILD", "Member3", "H1~0.9.1~Realm~p")
		eq(C.SharesZone("Member2"), true); eq(C.SharesZone("Member3"), false); eq(C.SharesZone("Member1"), false)
		ns.db.shareLocation = nil
		C.Broadcast(r)
		local d = Sent()
		eq(d.guild, MY_GUILD); eq(d.total, 1000); eq(d.leader, "Member1")
		eq(next(d.zones), nil, "private: no members per zone"); eq(d.leaderZone, nil)
		for _, o in ipairs(d.officers) do eq(o.zone, nil, o.name .. ": we keep ours, we name nobody's") end
		ns.db.shareLocation = true
		C.Broadcast(r)
		d = Sent()
		eq(d.zones.m1453, 75, "shared: the counts per zone")
		eq(d.leaderZone, nil)
		for _, o in ipairs(d.officers) do eq(o.zone ~= nil, o.name == "Member2", o.name) end
		-- Our hello says we share; a hello without it (0.9.0, or a no since) reads as no.
		C.Hello(true)
		for _ = 1, 5 do C.Pump() end
		eq(sent[#sent].msg, "H1~" .. ns.VERSION .. "~Realm~p~z")
		Deliver("GUILD", "Member2", "H1~0.9.0~Realm~p")
		eq(C.SharesZone("Member2"), false)
		Deliver("GUILD", "Member3", "H1~0.9.1~Realm~p~z")
		eq(C.SharesZone("Member3"), true)
		cns.clock = cns.clock + 721
		eq(C.SharesZone("Member3"), false, "not heard for 12 minutes: not counted")
	end)
	GetChannelName, C_ChatInfo, ns.db.shareLocation = savedChannel, nil, savedShare
	if not ok then error(err, 0) end
end)

test("0.9.1 privacy: the zone and layer question is asked once, when it can be, and its answer kept (#13)", function()
	local saved = { share = ns.db.shareLocation, combat = InCombatLockdown, instance = IsInInstance, key = ns.rdb.realmKey,
		print = ns.Print, hello = ns.Comm.Hello, send = ns.Comm.Send, guild = GetGuildInfo }
	local ok, err = pcall(function()
		local printed = {}
		ns.Print = function(m) printed[#printed + 1] = m end
		ns.Comm.Hello, ns.Comm.Send = function() end, function() end
		local d = StaticPopupDialogs.OLYMPUS_LOCATION_CHOICE
		eq(d.text, ns.L.LOCATION_ASK); eq(d.button1, ns.L.LOCATION_SHARE); eq(d.button2, ns.L.LOCATION_KEEP)
		-- It says what goes out, with whose name, to whom, and how to change it.
		for _, words in ipairs({ "your zone", "your layer", "guild rank", "your guild", "your name", "Olympus channel",
			"members per zone", "hop", "/oly location on", "/oly location off" }) do
			assert(d.text:find(words, 1, true), words)
		end
		WithGamepadUI(false, function(game)
			ns.db.shareLocation, ns.rdb.realmKey = nil, nil
			ns.Layers.Reset()
			InCombatLockdown = function() return true end
			eq(ns.Layers.AskChoice(), false, "not in combat")
			InCombatLockdown, IsInInstance = function() return false end, function() return true end
			eq(ns.Layers.AskChoice(), false, "not in an instance")
			IsInInstance = function() return false end
			GetGuildInfo = function() return "House of Guedes", "Member", 3 end
			eq(ns.Layers.AskChoice(), false, "outside Olympus the addon asks nothing")
			GetGuildInfo = saved.guild
			eq(#game.shown, 0)
			eq(ns.Layers.AskChoice(), true)
			eq(game.shown[1].which, "OLYMPUS_LOCATION_CHOICE"); eq(game.shown[1].a, ns.L.CHANNEL_PUBLIC, "no key: public, and it says so")
			eq(ns.Layers.AskChoice(), false, "once a session"); eq(#game.shown, 1)
			-- Pushed out by another window: no answer, asked again next session.
			d.OnCancel(nil, nil, "override")
			eq(ns.db.shareLocation, nil)
			ns.Layers.Reset()
			ns.rdb.realmKey = "secret"
			eq(ns.Layers.AskChoice(), true)
			eq(game.shown[2].a, ns.L.CHANNEL_SEALED, "sealed: the key's holders")
			-- Keep private (or Escape): kept, never asked again.
			d.OnCancel(nil, nil, "clicked")
			eq(ns.db.shareLocation, false); eq(printed[#printed], ns.L.LOCATION_OFF)
			ns.Layers.Reset()
			eq(ns.Layers.AskChoice(), false, "answered: never again"); eq(#game.shown, 2)
			-- Share: kept too.
			ns.db.shareLocation = nil
			d.OnAccept()
			eq(ns.db.shareLocation, true); eq(printed[#printed], ns.L.LOCATION_ON)
			ns.Layers.Reset()
			eq(ns.Layers.AskChoice(), false)
		end)
		-- The gamepad UI: our own window, its buttons answer.
		WithUI(function()
			WithGamepadUI(true, function(game)
				ns.db.shareLocation = nil
				ns.Layers.Reset()
				eq(ns.Layers.AskChoice(), true)
				eq(#game.shown, 0, "never the game's popup")
				local f = ns.Dialog.Find("OLYMPUS_LOCATION_CHOICE")
				assert(f and f:IsShown(), "our window")
				assert(f.text:GetText():find(ns.L.CHANNEL_SEALED, 1, true), f.text:GetText())
				f.buttons[2]:Click()
				eq(ns.db.shareLocation, false)
			end)
		end)
		-- /oly location on | off, alone it says which; /oly status shows it.
		SlashCmdList.OLYMPUS("location on"); eq(ns.db.shareLocation, true)
		SlashCmdList.OLYMPUS("location off"); eq(ns.db.shareLocation, false)
		SlashCmdList.OLYMPUS("location"); eq(printed[#printed], ns.L.LOCATION_OFF)
		assert(ns.StatusText():find("privacy: zone and layer off  |  channel sealed", 1, true), "in /oly status")
		ns.db.shareLocation = nil
		assert(ns.StatusText():find("privacy: zone and layer not chosen (off)", 1, true))
	end)
	ns.db.shareLocation, InCombatLockdown, IsInInstance, ns.rdb.realmKey = saved.share, saved.combat, saved.instance, saved.key
	ns.Print, ns.Comm.Hello, ns.Comm.Send, GetGuildInfo = saved.print, saved.hello, saved.send, saved.guild
	ns.Layers.Reset()
	if not ok then error(err, 0) end
end)

test("0.9.1 privacy: the first line in each channel waits for the player's OK (#16)", function()
	local savedWarned, savedChat, savedTime, clock = ns.db.chatWarned, ns.rdb.chat, GetTime, 20000000
	GetTime = function() return clock end
	local ok, err = pcall(function()
		ns.db.chatWarned = nil
		local d = StaticPopupDialogs.OLYMPUS_CHAT_PRIVACY
		eq(d.text, ns.L.CHAN_WARN_ASK); eq(d.button1, SEND_LABEL or "Send"); eq(d.button2, CANCEL or "Cancel")
		WithGamepadUI(false, function(game)
			WithLane(function(sent)
				AsRank(3, function()
					eq(select(2, Chan.Send("C", "hi")), "rank", "a line refused anyway never asks")
				end)
				AsRank(0, function(printed)
					-- /olc: the line is held, the warning shown, nothing sent.
					local okSend, why = Chan.Send("C", "the raid is at eight")
					eq(okSend, false); eq(why, "confirm"); eq(#sent, 0)
					eq(#game.shown, 1); eq(game.shown[1].which, "OLYMPUS_CHAT_PRIVACY"); eq(game.shown[1].a, "Captains")
					eq(game.shown[1].b, ns.L.CHANNEL_PUBLIC, "who can join the channel")
					eq(game.shown[1].data.text, "the raid is at eight")
					-- Cancel: not sent, still to be asked; an answered window answers once.
					d.OnCancel(nil, game.shown[1].data, "clicked")
					eq(#sent, 0); eq(printed[#printed], ns.L.CHAN_WARN_NOT_SENT); eq(ns.db.chatWarned.C, nil)
					d.OnAccept(nil, game.shown[1].data)
					eq(#sent, 0)
					-- Asked again; Send: the held line goes out, and [Captains] is warned for good.
					clock = clock + 10
					Chan.Send("C", "the raid is at eight")
					eq(#game.shown, 2)
					d.OnAccept(nil, game.shown[2].data)
					eq(#sent, 1); assert(sent[1]:find("^M1~C~Olympus II~%d+~PA~the raid is at eight$"), sent[1])
					eq(ns.db.chatWarned.C, true)
					clock = clock + 10
					eq((Chan.Send("C", "bring potions")), true, "not asked again")
					eq(#sent, 2); eq(#game.shown, 2)
					-- Each channel once: [Lords] and [Olympus] ask too.
					clock = clock + 10
					eq(select(2, Chan.Send("L", "lords only")), "confirm"); eq(game.shown[3].a, "Lords")
					clock = clock + 10
					eq(select(2, Chan.Send("A", "hello army")), "confirm"); eq(game.shown[4].a, "Olympus")
					eq(#sent, 2)
					for _, line in ipairs(printed) do assert(line ~= "CHAN_NOTICE", "no notice after a line any more") end
				end)
			end)
		end)
		-- The gamepad UI: our own window holds the line, and its Send sends it.
		ns.db.chatWarned = nil
		WithUI(function()
			WithGamepadUI(true, function(game)
				WithLane(function(sent)
					AsRank(3, function()
						clock = clock + 10
						eq(select(2, Chan.Send("A", "for olympus")), "confirm")
						eq(#game.shown, 0)
						local f = ns.Dialog.Find("OLYMPUS_CHAT_PRIVACY")
						assert(f and f:IsShown(), "our window")
						assert(f.text:GetText():find("[Olympus] is not private", 1, true), f.text:GetText())
						eq(f.data.text, "for olympus", "the line rides in the window")
						f.buttons[1]:Click()
						eq(#sent, 1); assert(sent[1]:find("~for olympus$"), sent[1])
						eq(ns.db.chatWarned.A, true)
					end)
				end)
			end)
		end)
	end)
	GetTime, ns.db.chatWarned, ns.rdb.chat = savedTime, savedWarned, savedChat
	if not ok then error(err, 0) end
end)

-- 0.9.1: chat
do
	-- The game's chat windows as GetChatWindowInfo tells them: 1 the main one, 2 the combat log
	-- (docked), 3 unused, 4 "Olympus" docked behind another tab (hidden, so "not shown"), 5
	-- "Officers" floating, 6-10 unused. fn(w, printed) runs with them, as a Lord of Olympus II.
	local function WithWindows(fn)
		local saved = { info = GetChatWindowInfo, fcf = FCF_GetChatWindowInfo, combat = IsCombatLog, num = NUM_CHAT_WINDOWS,
			default = DEFAULT_CHAT_FRAME, lines = CHAT_LINES, windows = ns.db.chatWindows, chat = ns.rdb.chat, mute = ns.db.chatMute,
			me = ns.me, frames = {} }
		local w = {}
		for i = 1, 10 do
			saved.frames[i] = _G["ChatFrame" .. i]
			w[i] = { name = "", shown = false, lines = {} }
			w[i].AddMessage = function(self, text) self.lines[#self.lines + 1] = text end
			_G["ChatFrame" .. i] = w[i]
		end
		w[1].name, w[1].shown = "General", true
		w[2].name, w[2].isDocked = "Combat Log", true
		w[3].name = "Voice"
		w[4].name, w[4].isDocked = "Olympus", true
		w[5].name, w[5].shown = "Officers", true
		NUM_CHAT_WINDOWS = 10
		GetChatWindowInfo = function(i)
			local f = w[i]
			return f.name, 14, 0, 0, 0, 1, f.shown, false, f.isDocked and 1 or nil, false
		end
		FCF_GetChatWindowInfo = nil
		IsCombatLog = function(f) return f == w[2] end
		DEFAULT_CHAT_FRAME = w[1]
		ns.db.chatWindows, ns.rdb.chat, ns.db.chatMute, ns.me = nil, nil, nil, "Tester-Realm"
		local ok, err = pcall(AsRank, 0, function(printed) fn(w, printed) end)
		GetChatWindowInfo, FCF_GetChatWindowInfo, IsCombatLog, NUM_CHAT_WINDOWS = saved.info, saved.fcf, saved.combat, saved.num
		DEFAULT_CHAT_FRAME, CHAT_LINES, ns.db.chatWindows, ns.rdb.chat, ns.db.chatMute = saved.default, saved.lines, saved.windows, saved.chat, saved.mute
		ns.me = saved.me
		for i = 1, 10 do _G["ChatFrame" .. i] = saved.frames[i] end
		if not ok then error(err, 0) end
	end
	local function Count(list, what)
		local n = 0
		for _, l in ipairs(list) do if tostring(l):find(what, 1, true) then n = n + 1 end end
		return n
	end
	local id = 5000

	test("chat window: each channel's lines and our own echo go to the window chosen by its name (#14)", function()
		WithWindows(function(w, printed)
			eq(Chan.ChooseWindow("olympus"), true, "any case")
			eq(ns.db.chatWindows["Tester-Realm"].A, "Olympus", "stored as the game names it")
			eq(ns.db.chatWindows["Tester-Realm"].C, "Olympus"); eq(ns.db.chatWindows["Tester-Realm"].L, "Olympus")
			eq(printed[#printed], ns.L.CHATWIN_SET:format("[Olympus], [Captains], [Lords]", '"Olympus"'))
			eq(Count(w[4].lines, "[Lords]"), 1, "the choice is said in that window too")
			eq(Chan.ChooseWindow("5 captains"), true, "by number, one channel")
			eq(ns.db.chatWindows["Tester-Realm"].C, "Officers"); eq(ns.db.chatWindows["Tester-Realm"].A, "Olympus")
			w[1].lines, w[4].lines, w[5].lines = {}, {}, {}
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member500", Msg("A", MY_GUILD, id, "to the olympus tab"), 3000000)), true)
			eq((Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, id, "to the officers window"), 3000001)), true)
			eq((Chan.Receive("CHANNEL", "Member1", Msg("L", MY_GUILD, id, "lords to the olympus tab"), 3000002)), true)
			eq(Count(w[4].lines, "to the olympus tab"), 2); eq(Count(w[5].lines, "to the officers window"), 1)
			eq(#w[1].lines, 0, "nothing in the main window")
			-- Our own line, shown when sent, lands with the others.
			WithLane(function() ns.db.chatWarned = { A = true, C = true, L = true }; local ok, why = Chan.Send("A", "my own line", 1e12); eq(ok, true, tostring(why)) end)
			eq(Count(w[4].lines, "my own line"), 1); eq(#w[1].lines, 0)
			-- Through the slash command, and in /oly status.
			SlashCmdList.OLYMPUS("chatwindow Officers lords")
			eq(ns.db.chatWindows["Tester-Realm"].L, "Officers")
			eq(Chan.WindowStatus(), '[Olympus] "Olympus", [Captains] "Officers", [Lords] "Officers"')
			assert(ns.StatusText():find('chat windows: [Olympus] "Olympus"', 1, true), "in /oly status")
			-- Per character, like the game's chat windows: another character's lines stay in the main window.
			ns.me = "Other-Realm"
			w[1].lines = {}
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member501", Msg("A", MY_GUILD, id, "other character"), 3000020)), true)
			eq(Count(w[1].lines, "other character"), 1)
		end)
	end)

	test("chat window: a window closed or renamed sends its lines to the main window, with one notice", function()
		WithWindows(function(w, printed)
			Chan.ChooseWindow("Olympus")
			w[4].name = "Olympus 2" -- renamed
			local n = #printed
			for k = 1, 3 do
				id = id + 1
				eq((Chan.Receive("CHANNEL", "Member" .. (510 + k), Msg("A", MY_GUILD, id, "renamed " .. k), 3001000 + k * 2)), true)
			end
			eq(Count(w[1].lines, "renamed"), 3, "nothing lost: the main window has them")
			eq(#printed, n + 1, "one notice"); eq(printed[#printed], ns.L.CHATWIN_GONE:format('"Olympus"'))
			eq(ns.db.chatWindows["Tester-Realm"].A, "Olympus", "the choice is kept")
			assert(Chan.WindowStatus():find('[Olympus] "Olympus" ' .. ns.L.CHATWIN_GONE_TAG, 1, true), Chan.WindowStatus())
			w[4].name = "Olympus" -- back
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member520", Msg("A", MY_GUILD, id, "back again"), 3001020)), true)
			eq(Count(w[4].lines, "back again"), 1); eq(#printed, n + 1)
			w[4].isDocked, w[4].shown = nil, false -- closed
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member521", Msg("A", MY_GUILD, id, "closed now"), 3001030)), true)
			eq(Count(w[1].lines, "closed now"), 1)
			eq(#printed, n + 2, "gone again after it came back: one more notice")
			-- An open window called the same (a tab made again) takes the lines back.
			w[6].name, w[6].isDocked = "OLYMPUS", true
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member522", Msg("A", MY_GUILD, id, "new tab"), 3001040)), true)
			eq(Count(w[6].lines, "new tab"), 1)
			-- Our echo too, with the window closed.
			w[6].isDocked = nil
			w[1].lines = {}
			WithLane(function() ns.db.chatWarned = { A = true, C = true, L = true }; local ok, why = Chan.Send("A", "echo to main", 1e12 + 100); eq(ok, true, tostring(why)) end)
			eq(Count(w[1].lines, "echo to main"), 1)
		end)
	end)

	test("chat window: main puts the lines back, unknown windows and the combat log are refused", function()
		WithWindows(function(w, printed)
			eq(Chan.ChooseWindow("Nope"), false)
			eq(printed[#printed], ns.L.CHATWIN_NOT_FOUND:format('"Nope"', '1 "General", 4 "Olympus", 5 "Officers"', ns.L.CHATWIN_NEW))
			eq(ns.db.chatWindows, nil, "nothing stored")
			eq(Chan.ChooseWindow("6"), false, "a closed window"); eq(Chan.ChooseWindow("11"), false); eq(Chan.ChooseWindow("0"), false)
			eq(Chan.ChooseWindow("2"), false); eq(printed[#printed], ns.L.CHATWIN_COMBATLOG)
			eq(Chan.ChooseWindow("combat log"), false); eq(printed[#printed], ns.L.CHATWIN_COMBATLOG)
			eq(Chan.ChooseWindow("1"), true, "the main window itself"); eq(ns.db.chatWindows, nil, "nothing to remember")
			eq(Chan.ChooseWindow(""), false)
			eq(printed[#printed - 1], ns.L.CHATWIN_NOW:format("[Olympus] " .. ns.L.CHATWIN_MAIN_NAME .. ", [Captains] "
				.. ns.L.CHATWIN_MAIN_NAME .. ", [Lords] " .. ns.L.CHATWIN_MAIN_NAME))
			eq(printed[#printed], ns.L.CHATWIN_USAGE)
			-- The whole name first: a window may end with a channel's name.
			w[5].name = "Olympus Lords"
			eq(Chan.ChooseWindow("olympus lords"), true)
			eq(ns.db.chatWindows["Tester-Realm"].A, "Olympus Lords"); eq(ns.db.chatWindows["Tester-Realm"].L, "Olympus Lords")
			eq(Chan.ChooseWindow("Olympus all"), true); eq(ns.db.chatWindows["Tester-Realm"].C, "Olympus")
			eq(Chan.ChooseWindow("main captains"), true)
			eq(printed[#printed], ns.L.CHATWIN_MAIN:format("[Captains]"))
			eq(ns.db.chatWindows["Tester-Realm"].C, nil); eq(ns.db.chatWindows["Tester-Realm"].A, "Olympus")
			eq(Chan.ChooseWindow("main"), true)
			eq(ns.db.chatWindows, nil, "nothing left")
			-- The game without the chat window API, or with a broken one: the frame's own name and
			-- dock (what FCF_SetWindowName and the dock set), else the main window, never an error.
			eq(Chan.ChooseWindow("Olympus Lords"), true)
			GetChatWindowInfo = nil
			eq(select(3, Chan.FindWindow("Olympus")), "Olympus", "the frame's own name")
			GetChatWindowInfo = function() error("broken") end
			eq(select(2, Chan.FindWindow("Olympus")), 4, "docked")
			-- Window 5 floats (shown, not docked): with nothing to say it is shown, the main window.
			id = id + 1
			eq((Chan.Receive("CHANNEL", "Member530", Msg("A", MY_GUILD, id, "no api"), 3002000)), true)
			eq(Count(w[1].lines, "no api"), 1, "the main window")
		end)
	end)

	test("flood guard: lines held back are told in one notice a minute, counted, and kept (#15)", function()
		WithWindows(function(w, printed)
			local stats0 = Chan.Stats().flood
			local T = 4000000
			Chan.FloodNotice(T - 1000) -- (whatever earlier tests held back)
			local n = #printed
			for i = 1, 70 do
				local shown, why = Chan.Receive("CHANNEL", "Member" .. (600 + i), Msg("A", MY_GUILD, i, "busy " .. i), T + i * 0.5)
				if i <= 60 then eq(shown, true, "line " .. i) else eq(why, "flood", "line " .. i) end
			end
			eq(#printed, n, "a few seconds to count the burst")
			eq(Chan.FloodNotice(T + 40), false)
			eq(Chan.FloodNotice(T + 40.5), true)
			eq(#printed, n + 1, "one notice"); eq(printed[#printed], ns.L.CHAN_FLOOD_NOTICE:format("[Olympus] 10", Chan.HISTORY))
			eq(Chan.FloodNotice(T + 200), false, "nothing more to tell")
			-- Nothing held back is lost: the Realm tab's history has every line.
			local h = Chan.History("A")
			eq(#h, 70); eq(h[70].text, "busy 70")
			-- More lines held within the minute wait for the next notice, in the window the channel shows in.
			Chan.ChooseWindow("Olympus")
			n = #printed
			for i = 71, 75 do
				eq(select(2, Chan.Receive("CHANNEL", "Member" .. (600 + i), Msg("A", MY_GUILD, i, "busy " .. i), T + 40 + i * 0.1)), "flood")
			end
			eq(Chan.FloodNotice(T + 100), false, "a minute after the last one")
			Chan.Prune(T + 100.5) -- the housekeeping tells it when the timer did not
			eq(Count(w[4].lines, ns.L.CHAN_FLOOD_NOTICE:format("[Olympus] 5", Chan.HISTORY)), 1)
			eq(#printed, n, "not in the main window")
			eq(Chan.Stats().flood - stats0, 15, "every line held is counted in a notice")
			eq(#Chan.History("A"), 75)
		end)
	end)

	test("the Realm tab shows every chat line the history keeps (#15)", function()
		WithWindows(function()
			for i = 1, 100 do
				Chan.Receive("CHANNEL", "Member" .. (700 + i), Msg("A", MY_GUILD, i, "kept " .. i), 5000000 + i * 1.1)
			end
			eq(#Chan.History("A"), 100, "the history keeps 100 lines")
			ns.Views.ShowChat("A")
			local ok, lines = pcall(ns.Views.RealmLines)
			ns.Views.ShowChat(nil)
			assert(ok, lines)
			local n = 0
			for _, l in ipairs(lines) do if (l.text or ""):find("kept ", 1, true) then n = n + 1 end end
			eq(n, 100, "lines kept but not shown were lost all the same")
		end)
	end)
end

-- 0.9.2: inspection load
test("0.9.2 Royal Inspection: a realm-wide budget, once every 30 minutes, a paced sample of the army", function()
	WithThrone(function(w, K)
		local saved = { random = K.random, summary = ns.Data.Summary }
		local ok, err = pcall(function()
			eq(K.INSPECT_GAP, 1800); eq(K.INSPECT_BUDGET * K.INSPECT_PACE, 100, "100 clients at once, 20 requests a second")
			local users = 3000
			ns.Data.Summary = function() return { guilds = { { fresh = true, g = { users = users } }, { fresh = false, g = { users = 9999 } } } } end
			eq(K.AddonsOnline(), 3000, "fresh reports only")
			eq(K.InspectShare(), 100 / 3000)
			users = 40
			eq(K.InspectShare(), 1, "a small army: everyone")
			users = 3000
			-- Not in the sample: the call is heard, no patrol.
			AsSoldier("Other")
			if ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
			K.random = function() return 0.5 end
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~I~11~Olympus")
			eq(ns.Inspect.IsPatrolling(), false, "not in this sample")
			-- A second call within 30 minutes (King or Hand): nothing, even for the sample.
			K.random = function() return 0 end
			w.clock = w.clock + 600
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~I~12~Olympus")
			eq(ns.Inspect.IsPatrolling(), false, "within 30 minutes")
			w.clock = w.clock + 1201
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~I~13~Olympus")
			eq(ns.Inspect.IsPatrolling(), true, "in the sample, 30 minutes later")
		end)
		K.random, ns.Data.Summary = saved.random, saved.summary
		if ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
		ns.Inspect.SetPace(nil)
		if not ok then error(err, 0) end
	end)
end)

test("0.9.2 who: the quiet search on a click goes once a minute at most", function()
	eq(ns.Who.AUTO_GAP, 60)
end)

-- 0.9.2: hostile layer payloads (a community reviewer's list: spoofed, relayed, guest offer)
test("0.9.2 hostile: a spoofed share, a relayed share and a guest offer are all rejected", function()
	WithHop(function(w, H)
		local L = ns.Layers
		local function OnLayer(zoneUID)
			for _, layer in ipairs(L.ForMap(1453)) do if layer.zoneUID == zoneUID then return layer.count end end
			return 0
		end
		-- Spoofed: an announcement that says "Olympus" from someone who is not the King's
		-- character does not become the King's layer.
		local king = H.King()
		L.Receive("Faker Guy-Realm", { mapID = 1453, zoneUID = 99, rank = 0, guild = "Olympus" })
		local after = H.King()
		assert(not (after and after.zoneUID == 99), "a spoofed share is not the King's layer")
		eq(after and after.zoneUID, king and king.zoneUID, "the King's layer did not move")
		-- A namesake on another realm group is not him either.
		eq(ns.IsKingCharacter("Asmongold Asmongler-ClassicBetaPvE"), false)
		-- Relayed: a share counts for its sender alone, and nobody can withdraw someone else's.
		L.Receive("Real Guy-Realm", { mapID = 1453, zoneUID = 5, rank = 9, guild = "Olympus II" })
		eq(OnLayer(5), 1)
		L.Forget("Relay Guy-Realm") -- an L0 from another sender
		eq(OnLayer(5), 1, "a withdrawal from someone else changes nothing")
		L.Forget("Real Guy-Realm") -- his own
		eq(OnLayer(5), 0, "his own withdrawal: gone at once")
		-- Guest offers: no ask of ours, an offer for another ask, an offer on the channel.
		H.HandleOffer("WHISPER", "Guest-Realm", "LO~42~0~0")
		eq(H.State(), nil, "no ask: nothing")
		w.see(7)
		H.Ask(1453, 8, "busy")
		local id = H.State().id
		H.HandleOffer("WHISPER", "Guest-Realm", ("LO~%d~0~0"):format(id + 1))
		H.HandleOffer("CHANNEL", "Guest-Realm", ("LO~%d~0~0"):format(id))
		eq(H.State().count, 0, "only whispers for our live ask")
		for i = 1, H.MAX_OFFERS + 5 do H.HandleOffer("WHISPER", "Guest" .. i .. "-Realm", ("LO~%d~0~0"):format(id)) end
		eq(H.State().count, H.MAX_OFFERS, "capped per ask")
		-- A request from someone we never offered to: no window on our screen.
		local popups = #w.popups
		H.HandleRequest("WHISPER", "Stranger-Realm", "LR~42")
		eq(#w.popups, popups, "no unsolicited invite window")
		eq(#w.whispered, 0, "and no answer to them")
	end)
end)

-- 0.9.2: sanitize
test("0.9.2 hostile: no escape code from another player gets past the door, chat keeps safe links only, no Discord pings", function()
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		local got = {}
		cns.Comm.Handle("ZZ", function(dist, sender, text) got[#got + 1] = text end)
		local evil = "ZZ~Olympus|TInterface\\Icons\\INV_Misc_QuestionMark:64|t~|cffff0000Red|r~|Hitem:19019|h[Fake]|h~line\nbreak"
		Deliver("GUILD", "Evil Guy-Realm", evil)
		eq(#got, 1)
		assert(not got[1]:find("[|%c]"), got[1])
		-- A forged census report: nothing it names carries a code into the census.
		local r = ns.Codec.DecodeReport(ns.Codec.Plain(ns.Codec.EncodeReport({ guild = "Olympus|cffff0000X|r", total = 10, online = 1,
			leader = "Bad|TInterface\\x:0|tGuy", zones = { ["m1453"] = 1 } })))
		assert(r and not r.guild:find("|", 1, true) and not r.leader:find("|", 1, true), "report stripped")
	end)
	if not ok then error(err, 0) end
	-- Chat: an item link the game makes passes; a malformed or foreign one is plain text.
	local C = ns.Codec
	local good = "|cff1eff00|Hitem:19019::::::::60::|h[Thunderfury]|h|r"
	eq(C.SanitizeChat("look " .. good), "look " .. good)
	-- (A "|" shown as text is written "||": only an unescaped one is a code.)
	local function Live(x) return (x:gsub("||", "")):find("|", 1, true) ~= nil end
	eq(Live(C.SanitizeChat("|Hitem:abc|h[x]|h")), false, "bad item data")
	eq(Live(C.SanitizeChat("|Hurl:evil|h[click]|h")), false, "foreign link type")
	eq(Live(C.SanitizeChat("|TInterface\\x:0|t hi")), false, "texture")
	-- Copy text for Discord pings nobody.
	local text = C.NoMentions("@everyone look <@123> <#456> @here")
	assert(not text:find("@everyone", 1, true) and not text:find("@here", 1, true) and not text:find("<@1", 1, true)
		and not text:find("<#4", 1, true), text)
	eq(C.NoMentions(text), text, "idempotent")
	-- Only Olympus's own errors are kept (the capture filter).
	eq(ns.OwnError("Interface/AddOns/OtherAddon/Main.lua:3: boom", "Interface/AddOns/OtherAddon/Main.lua:3"), false)
	eq(ns.OwnError("Interface/AddOns/Olympus/UI.lua:9: boom", ""), true)
end)

-- 0.9.3: the King's layer is his own share, never inferred from others on it
test("0.9.3 hostile: the King's layer comes from his own announcement alone, not from the members on it", function()
	WithUI(function() WithHop(function(w, H)
		-- Olympus officers and members share their layer; the King shares nothing.
		ns.Layers.Receive("Captain One-Realm", { mapID = 1453, zoneUID = 9, rank = 1, guild = "Olympus" })
		ns.Layers.Receive("Member Two-Realm", { mapID = 1453, zoneUID = 9, rank = 5, guild = "Olympus" })
		local k = H.King()
		assert(k, "the King is online (the census says so)")
		eq(k.zoneUID, nil, "his layer is not inferred from the others on it")
		-- A share in his name from anyone else is not his.
		ns.Layers.Receive("Asmongold-OtherRealm", { mapID = 1453, zoneUID = 9, rank = 0, guild = "Olympus" })
		eq(H.King().zoneUID, nil, "a namesake's share is not his")
		-- His own announcement (crown on) and its withdrawal.
		ns.Layers.Receive("Asmongold-Realm", { mapID = 1453, zoneUID = 9, rank = 0, guild = "Olympus" })
		eq(H.King().zoneUID, 9)
		ns.Layers.Forget("Asmongold-Realm")
		eq(H.King().zoneUID, nil, "withdrawn: gone at once")
	end) end)
end)

-- 0.9.3: the Treasurer's yes
test("0.9.3 the Treasurer shares his book and the bank only with his yes, and withdraws them at once", function()
	local T = ns.Treasury
	local saved = { me = ns.me, guild = GetGuildInfo, send = ns.Comm.Send, chunked = ns.Comm.SendChunked, show = ns.ShowDialog,
		consent = ns.db.treasurerShares, report = ns.rdb.treasuryReport, bank = ns.rdb.bankReport, combat = InCombatLockdown, inst = IsInInstance }
	local sent, dialogs = {}, {}
	local ok, err = pcall(function()
		T.Reset()
		ns.me = "Pyralis Ashandar-Realm"
		GetGuildInfo = function() return "OLYMPUS", "Treasurer", 2 end
		InCombatLockdown, IsInInstance = function() return false end, function() return false end
		ns.Comm.Send = function(dist, msg) sent[#sent + 1] = msg end
		ns.Comm.SendChunked = function(msg) sent[#sent + 1] = msg end
		ns.ShowDialog = function(which) dialogs[#dialogs + 1] = which end
		ns.db.treasurerShares = nil
		T.Share(true)
		eq(#sent, 0, "no answer yet: nothing goes out")
		eq(T.AskConsent(), true); eq(dialogs[1], "OLYMPUS_TREASURER_SHARE")
		eq(T.AskConsent(), false, "once a session")
		StaticPopupDialogs.OLYMPUS_TREASURER_SHARE.OnCancel(nil, nil, "override")
		eq(ns.db.treasurerShares, nil, "pushed out or Escape: no answer")
		StaticPopupDialogs.OLYMPUS_TREASURER_SHARE.OnAccept()
		eq(ns.db.treasurerShares, true)
		assert(sent[#sent] and sent[#sent]:find("^T8~OLYMPUS~"), tostring(sent[#sent]))
		T.SetConsent(false)
		eq(sent[#sent], "TX~OLYMPUS", "withdrawn at once")
		local before = #sent
		T.Share(true)
		eq(#sent, before, "private: nothing more")
		-- Receivers: his withdrawal clears his book and the bank; anyone else's is ignored.
		ns.rdb.treasuryReport, ns.rdb.bankReport = { rank = {}, t = 1 }, { t = 1, tabs = {} }
		T.HandleWithdraw("CHANNEL", "Faker Guy-Realm", "TX~OLYMPUS")
		assert(ns.rdb.treasuryReport and ns.rdb.bankReport, "not the Treasurer: nothing")
		T.HandleWithdraw("CHANNEL", "Pyralis Ashandar-Realm", "TX~OLYMPUS")
		eq(ns.rdb.treasuryReport, nil); eq(ns.rdb.bankReport, nil)
		-- Not the Treasurer: no question, no switch.
		ns.me = "Someone Else-Realm"
		T.Reset()
		eq(T.AskConsent(), false)
	end)
	ns.me, GetGuildInfo, ns.Comm.Send, ns.Comm.SendChunked, ns.ShowDialog = saved.me, saved.guild, saved.send, saved.chunked, saved.show
	ns.db.treasurerShares, ns.rdb.treasuryReport, ns.rdb.bankReport = saved.consent, saved.report, saved.bank
	InCombatLockdown, IsInInstance = saved.combat, saved.inst
	T.Reset()
	if not ok then error(err, 0) end
end)

-- 0.9.3: admission and limits (issue #23)
test("0.9.3 hostile: one sender's flood is dropped at the door, and unfinished pieces can't fill memory", function()
	local C, Codec = ns.Comm, ns.Codec
	C.ResetAdmission()
	local now, passed = 1000, 0
	for _ = 1, 200 do if C.Admit("Flood Guy-Realm", now) then passed = passed + 1 end end
	eq(passed, C.ADMIT_BURST, "a burst, then nothing")
	eq(C.Admit("Other Guy-Realm", now), true, "others are not affected")
	eq(C.Admit("Flood Guy-Realm", now + 1), true, "the rate comes back")
	C.ResetAdmission()
	-- Pieces: a few open messages per sender, a ceiling in all.
	local asm = Codec.NewAssembler()
	for i = 1, 10 do Codec.Feed(asm, "Evil-Realm", ("C%d:1:30:x"):format(i), now) end
	eq(asm.open, Codec.OPEN_PER_SENDER); eq(asm.refused, 10 - Codec.OPEN_PER_SENDER)
	for k = 1, Codec.OPEN_MAX + 50 do Codec.Feed(asm, "S" .. k .. "-Realm", "C1:1:30:x", now) end
	eq(asm.open, Codec.OPEN_MAX, "a ceiling in all")
	-- Completed and expired pieces free their room.
	local asm2 = Codec.NewAssembler()
	eq(Codec.Feed(asm2, "Good-Realm", "C7:1:2:ab", now), nil)
	eq(Codec.Feed(asm2, "Good-Realm", "C7:2:2:cd", now), "abcd"); eq(asm2.open, 0)
	Codec.Feed(asm2, "Good-Realm", "C8:1:2:ab", now)
	Codec.Gc(asm2, now + 61); eq(asm2.open, 0); eq(asm2.bySender["Good-Realm"], nil)
end)

test("0.9.3 a player can say no to Royal Inspections: the call is heard, nothing is inspected", function()
	WithThrone(function(w, K)
		local saved = { random = K.random, opt = ns.db.royalInspection }
		local ok, err = pcall(function()
			AsSoldier("Other")
			if ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
			K.random = function() return 0 end -- in the sample
			ns.db.royalInspection = false
			K.HandleCommand("CHANNEL", "Asmongold Asmongler-Realm", "T1~I~21~Olympus")
			eq(ns.Inspect.IsPatrolling(), false, "said no: no patrol")
		end)
		K.random, ns.db.royalInspection = saved.random, saved.opt
		if ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
		ns.Inspect.SetPace(nil)
		if not ok then error(err, 0) end
	end)
end)

-- 0.9.4: the Horde's King
test("0.9.4 the Horde's King: Duskmonkey Boneback of <Mudhutters>, a guild of the federation on the Horde side", function()
	WithThrone(function(w, K)
		local saved = { faction = ns.faction, guild = GetGuildInfo, me = ns.me }
		local ok, err = pcall(function()
			ns.faction = "Horde"
			eq(ns.IsKingGuild("Mudhutters"), true); eq(ns.IsFederation("Mudhutters"), true, "his guild is Olympus's")
			local ourRealm = ns.realm
			ns.realm = "ClassicBetaPvP" -- (a client of his realm group: a learned realm elsewhere is not ours)
			ns.rdb.kingRealmHorde = nil
			eq(ns.IsKingCharacter("Duskmonkey Boneback-ClassicBetaPvE"), true, "realm unknown yet: his name anywhere")
			eq(ns.rdb.kingRealmHorde, nil, "a name in a report teaches nothing")
			ns.LearnKingRealm("Duskmonkey Boneback-ClassicBetaPvP2") -- a message he sent
			eq(ns.rdb.kingRealmHorde, "ClassicBetaPvP2", "his realm, learned")
			eq(ns.IsKingCharacter("Duskmonkey Boneback-ClassicBetaPvP"), true, "the same realm group")
			eq(ns.IsKingCharacter("Duskmonkey Boneback-ClassicBetaPvE"), false, "then only there")
			ns.rdb.kingRealmHorde, ns.realm = nil, ourRealm
			eq(ns.IsKingCharacter("Duskmonkey Boneback"), true)
			eq(ns.IsKingCharacter("Asmongold Asmongler"), false, "the Alliance's King is not the Horde's")
			-- His own client: guild master of <Mudhutters>, the addon on.
			GetGuildInfo = function() return "Mudhutters", "Chief", 0 end
			ns.me = "Duskmonkey Boneback-Realm"
			eq(ns.IsMember(), true); eq(K.IsKing(), true)
			-- The army obeys him, and nobody else speaking for his guild.
			AsSoldier()
			GetGuildInfo = function() return "Olympus Horde", "Grunt", 3 end
			eq(K.Authorized("A", "Duskmonkey Boneback-Realm", "Mudhutters"), true)
			eq(K.Authorized("A", "Faker Guy-Realm", "Mudhutters"), false)
			-- The Alliance: <Mudhutters> is nobody's, and the Horde's King is no King there.
			ns.faction = "Alliance"
			eq(ns.IsKingGuild("Mudhutters"), false); eq(ns.IsFederation("Mudhutters"), false)
			eq(ns.IsKingCharacter("Duskmonkey Boneback"), false)
		end)
		ns.faction, GetGuildInfo, ns.me = saved.faction, saved.guild, saved.me
		ns.rdb.kingRealmHorde = nil
		if not ok then error(err, 0) end
	end)
end)

-- 0.9.5: Blizzard's Issue Reporter, hidden only if the player chooses
test("0.9.5 the Issue Reporter: shown until the player hides it, then hidden at every show; back on request", function()
	WithUI(function()
		local uns = setmetatable({}, { __index = ns })
		assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
		local UI = uns.UI
		local saved = { r = PTR_IssueReporter, hide = ns.db.hideIssueReporter, combat = InCombatLockdown }
		local ok, err = pcall(function()
			local r = { shown = true, hooks = {} }
			function r:IsShown() return self.shown end
			function r:Hide() self.shown = false end
			function r:Show() self.shown = true; for _, f in ipairs(self.hooks) do f(self) end end
			function r:IsProtected() return false end
			function r:HookScript(what, f) if what == "OnShow" then self.hooks[#self.hooks + 1] = f end end
			PTR_IssueReporter = r
			UI.ResetIssueReporter()
			ns.db.hideIssueReporter = nil
			eq(UI.ApplyIssueReporter(), true)
			eq(r.shown, true, "not chosen: Blizzard's as always")
			eq(#r.hooks, 1, "hooked, not replaced")
			UI.SetIssueReporterHidden(true)
			eq(r.shown, false, "hidden")
			r:Show()
			eq(r.shown, false, "and hidden again whenever the game shows it")
			UI.SetIssueReporterHidden(false)
			eq(r.shown, true, "back on request")
			-- A protected frame in combat is never touched.
			r.shown = true
			ns.db.hideIssueReporter = true
			function r:IsProtected() return true end
			InCombatLockdown = function() return true end
			UI.ApplyIssueReporter()
			eq(r.shown, true, "combat: left alone")
		end)
		PTR_IssueReporter, ns.db.hideIssueReporter, InCombatLockdown = saved.r, saved.hide, saved.combat
		UI.ResetIssueReporter()
		if not ok then error(err, 0) end
	end)
end)

-- 0.9.6: the High Council and the gamepad escape list
test("0.9.6 the High Council: a skull and a colour in the Olympus chats, on their realm group only", function()
	local realm, list = ns.HIGH_COUNCIL_REALM, ns.HIGH_COUNCIL
	ns.HIGH_COUNCIL_REALM, ns.HIGH_COUNCIL = "Realm", { ns.CouncilHash("Test Councillor") }
	local ok, err = pcall(function()
		eq(ns.IsHighCouncillor("Test Councillor-Realm"), true); eq(ns.IsHighCouncillor("test councillor"), true, "any case")
		eq(ns.IsHighCouncillor("Test Councillor-OtherRealm"), false, "a namesake elsewhere")
		eq(ns.IsHighCouncillor("Random Guy-Realm"), false)
		local line = ns.Channels.FormatLine("A", "Test Councillor-Realm", "Olympus", nil, "hello")
		assert(line:find(ns.HIGH_COUNCIL_ICON, 1, true) and line:find(ns.HIGH_COUNCIL_COLOR, 1, true), line)
		assert(not ns.Channels.FormatLine("A", "Random Guy-Realm", "Olympus", nil, "hi"):find(ns.HIGH_COUNCIL_ICON, 1, true))
	end)
	ns.HIGH_COUNCIL_REALM, ns.HIGH_COUNCIL = realm, list
	if not ok then error(err, 0) end
end)

test("0.9.6 gamepad UI: our windows are not on the escape list Blizzard's gamepad menus sweep", function()
	local saved, gp = UISpecialFrames, ns.GamepadUI
	local ok, err = pcall(function()
		UISpecialFrames = {}
		ns.GamepadUI = function() return false end
		ns.EscapeCloses("OlympusTestFrame"); ns.EscapeCloses("OlympusTestFrame")
		eq(#UISpecialFrames, 1, "mouse and keyboard: Escape closes it, listed once")
		ns.GamepadUI = function() return true end
		ns.EscapeCloses("OlympusTestFrame")
		eq(#UISpecialFrames, 0, "gamepad UI: taken off")
		ns.EscapeCloses("OlympusOther")
		eq(#UISpecialFrames, 0, "and never added")
	end)
	UISpecialFrames, ns.GamepadUI = saved, gp
	if not ok then error(err, 0) end
end)

test("0.9.6 a donation says what the donor gave in all", function()
	local T = ns.Treasury
	local saved = { print = ns.Print, book = ns.rdb.treasury, alert = ns.PlayAlert, share = T.Share }
	local printed = {}
	local ok, err = pcall(function()
		ns.Print = function(m) printed[#printed + 1] = m end
		ns.PlayAlert, T.Share = function() end, function() end
		T.Record("Romani Chudmeister", 100000, "trade")
		T.Record("Romani Chudmeister", 50000, "mail")
		local last = printed[#printed]
		assert(last:find(ns.L.TREASURY_IN_ALL:format(T.Coins(150000)), 1, true), last)
	end)
	ns.Print, ns.rdb.treasury, ns.PlayAlert, T.Share = saved.print, saved.book, saved.alert, saved.share
	T.Reset()
	if not ok then error(err, 0) end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
