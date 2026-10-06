local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaTest.lua. A stub the arena's core created for the screens (UI and test) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Rehearsal (ER, EH), stand-in roles, chips, the copper-mode gold record (db.arenaCopper) and
-- refunds, checklist data, the test-build store rules. Registers ER EH. ER is checked with
-- Arena.MayDirect (a test build: a signed arbiter or his named co-director; copper mode: the bank
-- and fee stand-ins are never the director himself).
-- API (the design): Start(lane, money, chips), Stop(), Running() -> the rehearsal { rid, lane =
--   "group"|"army", money, chips, roles } or nil (Arena.Lane reads its lane), Director(),
--   RoleOf(name), Participant(name), Money(), Report(), Clear() (refused while copper lines are
--   open), CopperOpen(), CHECKLIST, Mark(id, s, note)
-- Hooks it fills: ArenaRoles.standIn(name, letter, mode), ArenaRoles.standIns(letter, mode).
local ArenaTest = {}
ns.ArenaTest = ArenaTest

local L = ns.L

-- A rehearsal is the real code path with the mode letter T (the design): nothing in it
-- counts, and its state lives in the rehearsal store (Arena.Store("T"), ns.rdb.arenaTest), never
-- in the live one. What this file keeps:
-- - The director's word, ER, on the lane it names (the raid or party for a group rehearsal, the
--   channel for an army one): ER~T1~rid~time~g|a~c|p~chips~part/parts~roles, or ER~T1~rid~time~0
--   to close (numbers in base 36; roles "letter:Name-Realm,...", a name of the sender's realm
--   without it). Taken only from a director (Arena.MayDirect), the newest time winning, never more
--   than a minute ahead; while one director's rehearsal is open another's is ignored. Repeated
--   every 120 s for late joiners; parts of one word (the same rid and time) are merged.
-- - The testers' hello, EH~T1~build~base~flags (flags: g gamepad UI, r rules accepted, k the
--   King's view, o the arena off), on the group lane only: the Director tab's roster (memory only,
--   60 names, gone after 10 minutes without one).
-- - The roles of the rehearsal (T only, never the live lists): d co-director, b bank, a arbiter,
--   p public arbiter, k the King's stand-in, t the fee receiver's stand-in, s spectator, through
--   ArenaRoles.standIn.
-- - Copper mode's gold record (the design): every gold movement of a copper rehearsal is a line of
--   the account-wide ns.db.arenaCopper (counterparty, copper, trade or mail, direction, time,
--   state). It is backed up, never dropped by itself: a line clears only on the recipient's
--   refund receipt or an auditor's write-off. While a line is open, `test clear`, the rehearsal
--   store's own drop (7 days, another build) and a build change are refused, and the list printed.
-- - The Director's checklist (the design, with its changes): ns.db.arenaChecklist, on this
--   client only.
-- The director away 10 minutes: every client says so; 60 minutes: they close it here.

ArenaTest.RID_MAX = 99999
ArenaTest.CHIPS = 1000
ArenaTest.CHIPS_MAX = 100000
ArenaTest.REPEAT = 120        -- the director's word, again for late joiners
ArenaTest.HELLO_EVERY = 300   -- a tester's hello while a rehearsal is open
ArenaTest.AWAY = 600          -- the director not heard: "director away"
ArenaTest.GIVE_UP = 3600      -- ...closed here
ArenaTest.ROSTER_MAX = 60
ArenaTest.ROSTER_GONE = 600
ArenaTest.ROLES_MAX = 16
ArenaTest.PARTS_MAX = 3
ArenaTest.KEEP_DAYS = 7
ArenaTest.COPPER_MAX = 500
ArenaTest.NOTE_MAX = 80
ArenaTest.CHECKLIST_MAX = 200
ArenaTest.LETTERS = { d = true, b = true, a = true, p = true, k = true, t = true, s = true }

local function Now() return ns.Arena.Now() end
local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or "" end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Lower(a) == Lower(b) end
local function B36(n) return ns.Arena.B36(n) end

-- The rehearsal store (the sim's own in memory while it runs).
local function Store() return ns.Arena.Store("T") end

-- A read must not create the rehearsal store. The money watcher asks Running() for every
-- observed movement, including on an otherwise idle live client; making arenaTest there would
-- add saved state merely by observing normal play. The simulator's stores are memory-only, so
-- its read can still go through Arena.Store.
local function Peek()
	if ns.Arena.Sim() then return ns.Arena.Store("T") end
	return type(ns.rdb) == "table" and type(ns.rdb.arenaTest) == "table" and ns.rdb.arenaTest or nil
end

-- The word this client holds, or nil (closed or none).
local function Word()
	local s = Peek()
	if type(s) ~= "table" or not s.rid or s.closedAt then return nil end
	return s
end

function ArenaTest.Running()
	local s = Word()
	if not s then return nil end
	return { rid = s.rid, lane = s.lane == "a" and "army" or "group", money = s.money, chips = s.chips, roles = s.roles, director = s.director }
end
function ArenaTest.Director()
	local s = Word()
	return s and s.director or nil
end
function ArenaTest.IsDirector(name)
	local s = Word()
	name = name or ns.me
	if not s then return false end
	if Same(s.director, name) then return true end
	return (s.roles or {})[Lower(name)] == "d"
end
function ArenaTest.Money()
	local s = Word()
	return s and s.money or nil
end
function ArenaTest.Chips()
	local s = Word()
	return s and s.chips or nil
end
function ArenaTest.RoleOf(name)
	local s = Word()
	if not s or type(s.roles) ~= "table" then return nil end
	return s.roles[Lower(name)]
end
function ArenaTest.Roles()
	local s = Word()
	local out = {}
	if not s then return out end
	for name, letter in pairs(s.roles or {}) do out[#out + 1] = { name = ns.Arena.Name(name) or name, role = letter } end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- The group this client is in, by name.
local function InMyGroup(name)
	if not (IsInGroup and IsInGroup()) then return false end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local raid = IsInRaid and IsInRaid()
	for i = 1, math.max(n, 4) do
		local unit = raid and ("raid" .. i) or ("party" .. i)
		local who = ns.UnitFullName and ns.UnitFullName(unit)
		if who and Same(who, name) then return true end
	end
	return false
end

local roster = {} -- [lower name] = { name, build, base, flags, at }

-- Whether `name` takes part in the rehearsal: its director, a role of it, in a group rehearsal
-- the group, in an army one the roster (its testers' hellos).
function ArenaTest.Participant(name)
	local s = Word()
	if not s then return false end
	name = name or ns.me
	if Same(name, ns.me) then return true end
	if Same(s.director, name) or (s.roles or {})[Lower(name)] then return true end
	if s.lane == "g" then return InMyGroup(name) end
	local r = roster[Lower(name)]
	return r ~= nil and Now() - r.at < ArenaTest.ROSTER_GONE
end

-- The hooks ArenaRoles asks (T only): a rehearsal's stand-ins.
local R = ns.ArenaRoles
if type(R) == "table" then
	R.standIn = function(name, letter, mode)
		if mode ~= "T" then return false end
		return ArenaTest.RoleOf(name) == letter
	end
	R.standIns = function(letter, mode)
		local out = {}
		if mode ~= "T" then return out end
		local s = Word()
		for name, l in pairs(s and s.roles or {}) do
			if l == letter then out[#out + 1] = ns.Arena.Name(name) or name end
		end
		table.sort(out)
		return out
	end
end

---------------------------------------------------------------------------
-- The director's word (ER)
---------------------------------------------------------------------------

local function GroupDist()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end
local function DistOf(lane) if lane == "a" then return "CHANNEL" end return GroupDist() end

-- A role list as the wire writes it: "b:Coffrey Vault,a:Oswin Marrow-Realm2" (a name of the
-- sender's realm without it), cut in parts that each fit 255 bytes.
local function RoleParts(roles, head)
	local list = {}
	for name, letter in pairs(roles or {}) do
		local full = ns.Arena.Name(name) or name
		local realm = ns.RealmOf(full)
		local shown = (realm and realm == ns.realm) and ns.ShortName(full) or full
		list[#list + 1] = letter .. ":" .. shown
	end
	table.sort(list)
	local parts, cur = {}, {}
	local room = 255 - #head - 8
	local size = 0
	for _, item in ipairs(list) do
		if size + #item + 1 > room and cur[1] then
			parts[#parts + 1] = table.concat(cur, ",")
			cur, size = {}, 0
		end
		cur[#cur + 1] = item
		size = size + #item + 1
	end
	parts[#parts + 1] = table.concat(cur, ",")
	return parts
end

local function Body(s, i, n, roles)
	return ("%s~%s~%s~%s~%s~%d/%d~%s"):format(B36(s.rid), B36(s.time), s.lane, s.money, B36(s.chips), i, n, roles)
end
local function SendWord(s)
	local dist = DistOf(s.lane)
	if not dist then
		ns.Print(L.ARENA_TEST_NEED_GROUP)
		return false, "group"
	end
	local head = "ER~T1~" .. Body(s, 1, 1, "")
	local parts = RoleParts(s.roles, head)
	if #parts > ArenaTest.PARTS_MAX then return false, "roles" end
	local ok, why = true, nil
	for i, roles in ipairs(parts) do
		local sent, w = ns.Arena.Send("ER", "T", Body(s, i, #parts, roles), { dist = dist })
		if not sent then ok, why = false, w end
	end
	return ok, why
end
local function SendClose(s)
	local dist = DistOf(s.lane)
	if not dist then return false, "group" end
	return ns.Arena.Send("ER", "T", ("%s~%s~0"):format(B36(s.rid), B36(s.time)), { dist = dist })
end

local Hello -- (below)
local Watch -- (below)

-- Starts a rehearsal on this client, which directs it: lane "group" (default) or "army", money
-- "chips" (default) or "copper", chips each (1,000 by default, 100,000 at most). Returns true, or
-- false and why (said to the player).
function ArenaTest.Start(lane, money, chips, roles)
	lane = (lane == "army" or lane == "a") and "a" or "g"
	money = (money == "copper" or money == "p") and "p" or "c"
	chips = math.floor(tonumber(chips) or ArenaTest.CHIPS)
	if chips < 1 or chips > ArenaTest.CHIPS_MAX then
		ns.Print(L.ARENA_TEST_CHIPS)
		return false, "chips"
	end
	local A = ns.Arena
	if A.Sim() then return false, "sim" end
	if A.TestBuild() and lane == "a" then
		ns.Print(L.ARENA_TEST_GROUP_ONLY)
		return false, "lane"
	end
	local held = Word()
	if held and not Same(held.director, ns.me) then
		ns.Print(L.ARENA_TEST_HELD:format(ns.DisplayName(held.director) or "?"))
		return false, "held"
	end
	local list = {}
	for name, letter in pairs(type(roles) == "table" and roles or (held and held.roles) or {}) do
		if ArenaTest.LETTERS[letter] then list[Lower(name)] = letter end
	end
	local word = { lane = lane, money = money, roles = list }
	local ok, why = A.MayDirect(ns.me, word, held)
	if not ok then
		ns.Print(L.ARENA_TEST_NOT_DIRECTOR)
		return false, why
	end
	if lane == "g" and not GroupDist() then
		ns.Print(L.ARENA_TEST_NEED_GROUP)
		return false, "group"
	end
	local s = Store()
	if type(s) ~= "table" then return false, "store" end
	if not (held and Same(held.director, ns.me)) then
		-- A new rehearsal: the store starts again (never while copper lines of it are open).
		local open = ArenaTest.CopperOpen(s.rid)
		if s.rid and #open > 0 then
			ArenaTest.PrintCopper(open)
			return false, "copper"
		end
		for k in pairs(s) do s[k] = nil end
		s.v = 1
		s.rid = math.random and math.random(1, ArenaTest.RID_MAX) or 1
		s.openedAt = Now()
	end
	s.director, s.lane, s.money, s.chips, s.roles = ns.me, lane, money, chips, list
	s.time, s.closedAt, s.heardAt = Now(), nil, Now()
	s.build = A.TestBuild() and A.TestBuild().n or nil
	local sent, w = SendWord(s)
	if not sent and w == "group" then return false, w end
	A.Involve("rehearsal", true)
	A.Every(ArenaTest.REPEAT, "rehearsal:word", function()
		local cur = Word()
		if cur and Same(cur.director, ns.me) then SendWord(cur) end
	end)
	Watch()
	ns.Print(L.ARENA_TEST_STARTED:format(lane == "a" and L.ARENA_TEST_ARMY or L.ARENA_TEST_GROUP,
		money == "p" and L.ARENA_TEST_COPPER or L.ARENA_TEST_CHIPS_WORD))
	if ns.Chronicle and ns.Chronicle.Add and not A.Sim() then ns.Chronicle.Add("arena", ns.me, "[TEST] " .. L.ARENA_TEST_CHRONICLE_START:format(s.rid)) end
	ns.Fire("ARENA_REHEARSAL", "start", s.rid)
	A.Changed()
	Hello()
	return true
end

-- Gives a tester a role (the Director tab's buttons): the word goes again with it.
function ArenaTest.SetRole(name, letter)
	local s = Word()
	if not s or not ArenaTest.IsDirector(ns.me) then return false, "director" end
	name = ns.Arena.Name(name)
	if not name then return false, "name" end
	if letter ~= nil and not ArenaTest.LETTERS[letter] then return false, "letter" end
	local roles = {}
	for k, v in pairs(s.roles or {}) do roles[k] = v end
	roles[Lower(name)] = letter
	local n = 0
	for _ in pairs(roles) do n = n + 1 end
	if n > ArenaTest.ROLES_MAX then return false, "count" end
	local ok, why = ns.Arena.MayDirect(ns.me, { lane = s.lane, money = s.money, roles = roles }, s)
	if not ok then return false, why end
	s.roles, s.time = roles, Now()
	SendWord(s)
	ns.Arena.Changed()
	return true
end

-- The copper lines of a rehearsal that closes: each open one stays, as a refund due (the design).
local function Closed(s, why)
	s.closedAt = Now()
	ns.Arena.Involve("rehearsal", false)
	ns.Arena.Every(0, "rehearsal:word", nil)
	ns.Arena.Every(0, "rehearsal:hello", nil)
	ns.Arena.Every(0, "rehearsal:watch", nil)
	local open = ArenaTest.CopperOpen(s.rid)
	if #open > 0 then ArenaTest.PrintCopper(open) end
	ns.Fire("ARENA_REHEARSAL", "stop", s.rid, why)
	ns.Arena.Changed()
end

-- The director closes it: ER with 0, then every client closes its events (their owners void the
-- open bets and refund them as chips; copper bets stay in the refund list).
function ArenaTest.Stop()
	local s = Word()
	if not s then
		ns.Print(L.ARENA_TEST_NONE)
		return false, "none"
	end
	if not ArenaTest.IsDirector(ns.me) then
		ns.Print(L.ARENA_TEST_NOT_DIRECTOR)
		return false, "director"
	end
	s.time = math.max(Now(), (s.time or 0) + 1)
	SendClose(s)
	Closed(s, "stop")
	ns.Print(L.ARENA_TEST_STOPPED)
	if ns.Chronicle and ns.Chronicle.Add and not ns.Arena.Sim() then ns.Chronicle.Add("arena", ns.me, "[TEST] " .. L.ARENA_TEST_CHRONICLE_STOP:format(s.rid)) end
	return true
end

-- The director away: said after 10 minutes; closed here after 60.
Watch = function()
	ns.Arena.Every(60, "rehearsal:watch", function()
		local s = Word()
		if not s then return end
		if Same(s.director, ns.me) then return end
		local quiet = Now() - (s.heardAt or s.time or 0)
		if quiet >= ArenaTest.GIVE_UP then
			Closed(s, "away")
			ns.Print(L.ARENA_TEST_CLOSED_AWAY)
		elseif quiet >= ArenaTest.AWAY and not s.awaySaid then
			s.awaySaid = true
			ns.Print(L.ARENA_TEST_AWAY:format(ns.DisplayName(s.director) or "?"))
			ns.Arena.Changed()
		end
	end)
end
function ArenaTest.DirectorAway()
	local s = Word()
	return s ~= nil and not Same(s.director, ns.me) and Now() - (s.heardAt or s.time or 0) >= ArenaTest.AWAY
end

-- ER: a director's word. Returns true when taken, else false and why (the tests read it).
local function Roles(text, sender)
	local out, n = {}, 0
	if text == nil or text == "" then return out, 0 end
	for item in text:gmatch("[^,]+") do
		local letter, name = item:match("^(%l):(.+)$")
		if not letter or not ArenaTest.LETTERS[letter] then return nil end
		if not name:find("-", 1, true) then name = ns.FullName(name, ns.RealmOf(ns.FullName(sender))) end
		name = ns.Arena.Name(name)
		if not name then return nil end
		out[Lower(name)] = letter
		n = n + 1
	end
	return out, n
end
local function OnWord(dist, sender, mode, body)
	if mode ~= "T" then return false, "mode" end
	sender = ns.FullName(sender)
	local rid, time, rest = ns.Arena.Fields(body, 3)
	rid, time = ns.Arena.N(rid, 1, ArenaTest.RID_MAX), ns.Arena.N(time, 1)
	if not rid or not time then return false, "shape" end
	local K = ns.King
	if time > Now() + (K and K.DATE_AHEAD or 60) then return false, "ahead" end
	local s = Store()
	if type(s) ~= "table" then return false, "store" end
	local held = Word()
	if rest == "0" then
		-- The close: from the director of that rehearsal (or a co-director of it).
		if not held or held.rid ~= rid then return false, "unknown" end
		if not (Same(held.director, sender) or (held.roles or {})[Lower(sender)] == "d") then return false, "director" end
		if time < (held.time or 0) then return false, "old" end
		held.time = time
		Closed(held, "stop")
		ns.Print(L.ARENA_TEST_STOPPED)
		return true
	end
	local lane, money, chips, part, roles = ns.Arena.Fields(rest, 5)
	if (lane ~= "g" and lane ~= "a") or (money ~= "c" and money ~= "p") then return false, "shape" end
	chips = ns.Arena.N(chips, 1, ArenaTest.CHIPS_MAX)
	local i, n = tostring(part or ""):match("^(%d)/(%d)$")
	i, n = tonumber(i), tonumber(n)
	if not chips or not i or not n or i < 1 or i > n or n > ArenaTest.PARTS_MAX then return false, "shape" end
	-- Only on the lane it names.
	if lane == "g" and dist ~= "RAID" and dist ~= "PARTY" then return false, "lane" end
	if lane == "a" and dist ~= "CHANNEL" then return false, "lane" end
	local list, count = Roles(roles, sender)
	if not list or count > ArenaTest.ROLES_MAX then return false, "roles" end
	-- Another director's rehearsal while one is open: ignored until it closes.
	if held and held.rid ~= rid and not Same(held.director, sender) then return false, "held" end
	local same = held and held.rid == rid
	if same and time < (held.time or 0) then return false, "old" end
	-- The parts of one word (the same rid and time): their roles are merged.
	local merged = {}
	if same and time == held.time then
		for k, v in pairs(held.roles or {}) do merged[k] = v end
	end
	for k, v in pairs(list) do merged[k] = v end
	local ok, why = ns.Arena.MayDirect(sender, { lane = lane, money = money, roles = merged }, held)
	if not ok then return false, why end
	if not same then
		-- Another rehearsal replaces the store: never while copper lines of the last one are open
		-- (the list is printed; the tester joins once his gold came back).
		local open = s.rid and ArenaTest.CopperOpen(s.rid) or {}
		if #open > 0 then
			ArenaTest.PrintCopper(open)
			return false, "copper"
		end
		for k in pairs(s) do s[k] = nil end
		s.v, s.rid, s.openedAt = 1, rid, Now()
	end
	s.director, s.lane, s.money, s.chips, s.roles, s.time = sender, lane, money, chips, merged, time
	s.heardAt, s.closedAt, s.awaySaid = Now(), nil, nil
	s.build = ns.Arena.TestBuild() and ns.Arena.TestBuild().n or nil
	ns.Arena.Involve("rehearsal", true)
	Watch()
	if not same then
		ns.Print(L.ARENA_TEST_JOINED:format(ns.DisplayName(sender) or "?"))
		ns.Fire("ARENA_REHEARSAL", "start", rid)
	end
	ns.Arena.Changed()
	if not same or i == n then Hello() end
	return true
end
ArenaTest.OnWord = OnWord

---------------------------------------------------------------------------
-- The testers' hello (EH) and the Director's roster
---------------------------------------------------------------------------

function ArenaTest.Flags()
	local f = {}
	if ns.GamepadUI and ns.GamepadUI() then f[#f + 1] = "g" end
	if ns.Arena.RulesAccepted() then f[#f + 1] = "r" end
	if ns.KingsScreen and ns.KingsScreen() then f[#f + 1] = "k" end
	if ns.Arena.Off() then f[#f + 1] = "o" end
	return table.concat(f)
end
Hello = function()
	local dist = GroupDist()
	if not dist then return false end
	local t = ns.Arena.TestBuild()
	local body = ("%s~%s~%s"):format(B36(t and t.n or 0), t and t.base or ns.VERSION, ArenaTest.Flags())
	local ok = ns.Arena.Send("EH", "T", body, { dist = dist })
	if Word() then
		ns.Arena.Every(ArenaTest.HELLO_EVERY, "rehearsal:hello", function() if Word() then Hello() end end)
	end
	return ok
end
ArenaTest.Hello = function() return Hello() end

local function OnHello(dist, sender, mode, body)
	if mode ~= "T" or (dist ~= "RAID" and dist ~= "PARTY") then return false, "lane" end
	local build, base, flags = ns.Arena.Fields(body, 3)
	build = ns.Arena.N(build, 0, 999)
	if not build or type(base) ~= "string" or not base:match("^%d+%.%d+%.%d+$") or not tostring(flags):match("^[grko]*$") then return false, "shape" end
	sender = ns.FullName(sender)
	local now = Now()
	for k, r in pairs(roster) do if now - r.at >= ArenaTest.ROSTER_GONE * 6 then roster[k] = nil end end
	local key = Lower(sender)
	if not roster[key] then
		local n = 0
		for _ in pairs(roster) do n = n + 1 end
		if n >= ArenaTest.ROSTER_MAX then return false, "full" end
	end
	roster[key] = { name = sender, build = build, base = base, flags = flags, at = now }
	ns.Arena.Changed()
	return true
end
ArenaTest.OnHello = OnHello

-- The roster the Director tab shows: { name, build, base, flags, at, gone, role }, by name.
function ArenaTest.Roster()
	local out, now = {}, Now()
	for key, r in pairs(roster) do
		out[#out + 1] = { name = r.name, build = r.build, base = r.base, flags = r.flags, at = r.at,
			gone = now - r.at >= ArenaTest.ROSTER_GONE, role = ArenaTest.RoleOf(r.name) }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

ns.Comm.Handle("ER", ns.Arena.Handle("ER", OnWord))
ns.Comm.Handle("EH", ns.Arena.Handle("EH", OnHello))

---------------------------------------------------------------------------
-- Copper mode's gold record (ns.db.arenaCopper, the design)
---------------------------------------------------------------------------

local function Copper()
	if not ns.db then return nil end
	if type(ns.db.arenaCopper) ~= "table" then ns.db.arenaCopper = {} end
	return ns.db.arenaCopper
end

-- A gold movement of a copper rehearsal (the trade and mail hooks call it, the money part): { from, to,
-- copper, how = "t"|"m", dir = "in"|"out", ref }. Returns its id, or nil and why ("full": the
-- record is never dropped by itself, so at 500 lines a new one is refused and said).
function ArenaTest.CopperAdd(line)
	local list = Copper()
	if not list or type(line) ~= "table" then return nil, "shape" end
	local copper = tonumber(line.copper)
	if not copper or copper <= 0 or copper ~= math.floor(copper) then return nil, "copper" end
	if line.dir ~= "in" and line.dir ~= "out" then return nil, "dir" end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	if n >= ArenaTest.COPPER_MAX then
		ns.Print(L.ARENA_COPPER_FULL)
		return nil, "full"
	end
	local s = Word()
	local id = ("c%s%s"):format(B36(Now()), B36(n + 1))
	while list[id] do id = id .. "x" end
	list[id] = { rid = line.rid or (s and s.rid) or 0, from = line.from and ns.FullName(line.from) or nil, to = line.to and ns.FullName(line.to) or nil,
		copper = copper, how = line.how == "m" and "m" or "t", dir = line.dir, at = Now(), state = "open", ref = line.ref }
	return id
end
-- A line clears: "refunded" (the recipient's receipt) or "written" (an auditor's write-off, by).
function ArenaTest.CopperClear(id, state, by)
	local list = Copper()
	local e = list and list[id]
	if not e or e.state ~= "open" then return false end
	e.state = state == "written" and "written" or "refunded"
	e.by = by and ns.FullName(by) or nil
	e.clearedAt = Now()
	return true
end
-- The open lines (of one rehearsal, or all), oldest first: { id, line }.
function ArenaTest.CopperOpen(rid)
	local out = {}
	for id, e in pairs(Copper() or {}) do
		if type(e) == "table" and e.state == "open" and (rid == nil or e.rid == rid) then out[#out + 1] = { id = id, line = e } end
	end
	table.sort(out, function(a, b) return (a.line.at or 0) < (b.line.at or 0) or ((a.line.at or 0) == (b.line.at or 0) and a.id < b.id) end)
	return out
end
function ArenaTest.PrintCopper(open)
	ns.Print(L.ARENA_COPPER_OPEN:format(#open))
	for i, o in ipairs(open) do
		if i > 10 then
			ns.Print(L.ARENA_COPPER_MORE:format(#open - 10))
			break
		end
		local e = o.line
		local who = e.dir == "in" and e.from or e.to
		local H = ns.ArenaHome
		ns.Print("  " .. L.ARENA_COPPER_LINE:format(e.dir == "in" and L.ARENA_COPPER_IN or L.ARENA_COPPER_OUT, ns.Arena.Mask(ns.DisplayName(who) or "?"),
			H and H.Money and H.Money(e.copper) or tostring(e.copper), e.how == "m" and L.ARENA_COPPER_MAIL or L.ARENA_COPPER_TRADE))
	end
end
-- What each counterparty is owed back at the close (the Bank tab's refunds): the gold that came
-- in from him less what went back out to him, over the open lines of that rehearsal.
function ArenaTest.Refunds(rid)
	local net, order = {}, {}
	for _, o in ipairs(ArenaTest.CopperOpen(rid)) do
		local e = o.line
		local who = e.dir == "in" and e.from or e.to
		if who then
			local key = Lower(who)
			if not net[key] then net[key] = { name = who, copper = 0 } order[#order + 1] = key end
			net[key].copper = net[key].copper + (e.dir == "in" and e.copper or -e.copper)
		end
	end
	local out = {}
	for _, key in ipairs(order) do if net[key].copper ~= 0 then out[#out + 1] = net[key] end end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

---------------------------------------------------------------------------
-- The rehearsal store's own rules (the design): dropped 7 days after it closed, or
-- when written by another test build (a release drops any a test build wrote), never while copper
-- lines of it are open (the list is printed instead). `test clear` drops it now, the same way.
---------------------------------------------------------------------------

local function Drop(s, why)
	local open = s.rid and ArenaTest.CopperOpen(s.rid) or {}
	if #open > 0 then
		ArenaTest.PrintCopper(open)
		return false, "copper"
	end
	for k in pairs(s) do s[k] = nil end
	s.v = 1
	ns.Arena.Involve("rehearsal", false)
	ns.Arena.Changed()
	return true, why
end
function ArenaTest.CheckStore()
	if ns.Arena.Sim() then return false end
	local s = type(ns.rdb) == "table" and ns.rdb.arenaTest or nil
	if type(s) ~= "table" or not s.rid then return false end
	local t = ns.Arena.TestBuild()
	if (t and s.build ~= t.n) or (not t and s.build ~= nil) then return Drop(s, "build") end
	local closed = s.closedAt or s.time or s.openedAt
	if s.closedAt and Now() - closed > ArenaTest.KEEP_DAYS * 86400 then return Drop(s, "old") end
	-- Open after a relog: the director's word comes again (or the absence rule closes it).
	if not s.closedAt then
		ns.Arena.Involve("rehearsal", true)
		Watch()
	end
	return false
end
function ArenaTest.Clear()
	local s = Store()
	if type(s) ~= "table" then return false, "store" end
	if Word() then
		ns.Print(L.ARENA_TEST_CLEAR_OPEN)
		return false, "open"
	end
	-- Every rehearsal's copper lines: a line of an older one keeps its gold owed too.
	local open = ArenaTest.CopperOpen()
	if #open > 0 then
		ArenaTest.PrintCopper(open)
		return false, "copper"
	end
	for k in pairs(s) do s[k] = nil end
	s.v = 1
	ns.Print(L.ARENA_TEST_CLEARED)
	ns.Arena.Changed()
	return true
end
ns.On("INIT", function() ns.SafeCall("arena test store", ArenaTest.CheckStore) end)

---------------------------------------------------------------------------
-- The checklist (the design, with its changes): ticked by the Director in the addon.
-- The task force's own words, in English (the report goes to the testers' Discord as is).
---------------------------------------------------------------------------

local function Item(id, stage, what, expect) return { id = id, stage = stage, what = what, expect = expect } end
ArenaTest.CHECKLIST = {
	Item("V01", "S1", "Install the test zip", "Login line; window title \"(test N)\"; /oly arena status \"test build N, lane: group\""),
	Item("V02", "S1", "A guildmate on release 1.1, outside the raid, watches during an event", "No arena line, alert or chat; no rise in \"bad\" reports"),
	Item("V03", "S1", "A 1.1 client inside the raid", "Nothing shown; no Lua error"),
	Item("V04", "S1", "A tester leaves the raid", "\"Join the task force raid\" in the Arena window; the roster marks him gone"),
	Item("V05", "S1", "/oly arena off, then on", "Off: no EH, no alerts, nothing sent; on: back"),
	Item("V06", "S3", "Back to release 1.1, log in, then back to the test build", "No error either way; settings kept"),
	Item("C01", "S1", "Open the Arena window the first time", "The rules pop-up; Not now leaves it viewable, Bet disabled with \"Rules not accepted\""),
	Item("C02", "S1", "I agree", "Bet and deposit enabled; flag r in the roster"),
	Item("C03", "S1", "/oly privacy", "\"Your arena fight history\", private until answered"),
	Item("R01", "S1", "Director: Start rehearsal (group, chips)", "Everyone in the raid: the red banner; the roster lists each tester"),
	Item("R02", "S1", "A non-director tries /oly arena test start", "Refused with the reason; nothing changes for others"),
	Item("R03", "S1", "Director assigns b, a, p roles", "Bank tab on the bank; Arbiter tab on a and p"),
	Item("R04", "S1", "Director: Stop rehearsal", "Banner goes; open bets voided and chips refunded; report available"),
	Item("R05", "S1", "/oly arena test clear", "Test store empty"),
	Item("W01", "S1", "First bet in chips", "1,000 chips credited, bet validated toast"),
	Item("W02", "S2", "Copper: deposit 50s by trade", "Credited only after the trade completes; the receipt in the tester's own list"),
	Item("W03", "S2", "Start a trade and cancel it", "Nothing credited"),
	Item("W04", "S2", "Copper: deposit 50s by mail", "Nothing on Send; credited when the bank takes the mail"),
	Item("W05", "S2", "Copper: deposit 2g (over the cap)", "The Bank tab flags it; a refund line"),
	Item("W06", "S2", "Withdraw 30s", "Fill next fills the mail; mailed; confirmed on taking it"),
	Item("W07", "S2", "The bank logs off during betting", "Slip: \"Bank offline\"; mailed deposits wait; back: queue processed"),
	Item("W08", "S2", "A gamepad tester deposits", "\"Tell me what to send\" prints the line; no game window touched"),
	Item("W09", "S2", "Fill trade on Forever", "Filled, or once \"type N\" then the amount only"),
	Item("F01", "S2", "Public arbiter creates a fight with Winner + Duration", "The card appears for the raid, bets open"),
	Item("F02", "S2", "Open bets", "Raid warning, sound, alert window once; a tester in an instance gets it on leaving"),
	Item("F03", "S2", "5 spectators bet on both sides", "Pools, odds and counts move on every client"),
	Item("F04", "S3", "20 spectators bet within 60 s", "Record Place bet to the validated toast: median and maximum"),
	Item("F05", "S2", "Close bets, then try to bet", "Refused \"Bets closed\"; odds fixed"),
	Item("F06", "S2", "A fighter bets on his fight; the arbiter on the one he judges", "Both refused"),
	Item("F07", "S2", "Fighters duel; spectators at 5, 20, 50, 100 yd and in another zone", "Record who heard the duel's line"),
	Item("F08", "S2", "Arbiter declares, then corrects within grace", "Payouts wait; the correction replaces the result everywhere"),
	Item("F09", "S2", "A duel ends while bets are open", "The fight voids, bets refunded"),
	Item("F10", "S2", "Payouts", "Chips credited; copper payouts mailed and confirmed"),
	Item("F11", "S2", "The fee lines", "6% as 4% guild + 2% arbiter; in chips \"not owed\""),
	Item("F12", "S3", "Duration over/under and KO vs fled (trial)", "Settle as the core says"),
	Item("F13", "S3", "Best-of-3 exact score", "Settles after the third fight"),
	Item("F14", "S3", "First blood and biggest hit (trial)", "Against the fighters' own screens"),
	Item("O01", "S1", "Challenge: Use target, stake 5 chips, with an arbiter", "The opponent's window; Accept"),
	Item("O02", "S1", "Find an arbiter", "Only name, online, zone (if shared), free or busy"),
	Item("O03", "S1", "Ask one arbiter", "His window; Accept; the match shows only to the three"),
	Item("O04", "S2", "Copper stakes to the arbiter by trade", "Both credited on trade complete"),
	Item("O05", "S2", "Arbiter settles", "Winner paid by mail; the 2% and 4% lines"),
	Item("O06", "S2", "Direct mode: the loser trades, the winner mails 6% with \"Arena fee TEST\"", "Both recorded; nothing in any treasury"),
	Item("O07", "S3", "A welsher loses a direct bet and doesn't pay", "\"Has an open bet\" mark; amount for leadership; his betting blocked; paying clears"),
	Item("O08", "S3", "The welsher's alt of the same account", "The alt is flagged too"),
	Item("T01", "S3", "An 8-fighter tournament; 8 register", "Entrants grid; outrights and how far open"),
	Item("T02", "S3", "The draw: one Roll click per slot in the drawer's raid", "Every member sees the same slot; a roll with another maximum ignored"),
	Item("T03", "S3", "The bracket near and far", "Near: live portraits; far: emblems or class icons; tier medallions"),
	Item("T04", "S3", "The arbiter advances winners", "Slots and gold paths update everywhere; how far settles per stage"),
	Item("T05", "S3", "Final", "Champion banner; the belt frame for viewers once verified (T only, gone after close)"),
	Item("T06", "S3", "The King stand-in shows the bracket on the overlay", "Readable at 1080p"),
	Item("K01", "S1", "A Bones table; opponent not in the group", "\"Invite\" offered; the board on both once grouped"),
	Item("K02", "S1", "Roll", "One /roll 1-46656; the same six dice on both"),
	Item("K03", "S1", "The wrong player rolls, or rolls twice", "Ignored with a line; the turn unchanged"),
	Item("K04", "S1", "Bank points, farkle, win", "Scores and result match on both; moves by whisper"),
	Item("K05", "S2", "Stakes direct and via an arbiter", "As O04-O06"),
	Item("K06", "S2", "A gamepad player rolls", "Works, or \"Type /roll 46656\" (record which)"),
	Item("P01", "S1", "Pick an emblem", "The far viewer's card shows it"),
	Item("P02", "S1", "History private, then public", "Others see the record only, then the list"),
	Item("P03", "S3", "Ranking categories", "Tier medallions and belts in TEST; live ranking unchanged after close"),
	Item("X01", "S1", "Public room: spectators chat", "Lines only in the panel (in chat only with \"also in chat\")"),
	Item("X02", "S1", "1v1 room: an outsider in the raid says a line", "Shown to nobody"),
	Item("X03", "S3", "One tester pastes 10 lines fast", "Slowed down; others see a flood notice"),
	Item("X04", "S1", "A block term", "Hidden for the one who set it"),
	Item("X05", "S3", "Moderator net-offs a tester", "His lines, bets and cards vanish; he cannot bet"),
	Item("X06", "S2", "The King stand-in's client", "Chat panel closed by default; overlay without chat or bettor names"),
	Item("S01", "S2", "The King's view: announce, open, close bets, overlay", "The delay line on each; not on a spectator's screen"),
	Item("S02", "S2", "Delay 120 s; open bets with 60 s", "Window raised to 195 s with a line"),
	Item("S03", "S4", "Overlay on a private stream at 1080p", "Readable; REHEARSAL watermark"),
	Item("S04", "S2", "Overlay modes Card, Closed, Result, Payouts", "Each switches on the state"),
	Item("G01", "S2", "Gamepad spectator: open, rules, deposit, bet, chat, result", "No \"blocked\" message, windows close with X, no typing"),
	Item("G02", "S3", "Gamepad on and off mid-event", "Fill buttons change wording at once"),
	Item("H01", "S3", "A far viewer and a belt holder's picked frame", "The frame and its nameplate mark"),
	Item("H02", "S3", "The same pick on a non-holder", "Falls back to the rank frame"),
	Item("H03", "S3", "A Treasurer stand-in's ID", "A donor frame pickable"),
	Item("H04", "S3", "A level-up to a multiple of 10", "IL sent, vouched after the next census report"),
	Item("H05", "S3", "The title on the person card", "\"Rank · Title\""),
	Item("H06", "S3", "A newly earned honour", "Switches on by itself; the King's letter"),
	Item("H07", "S3", "A category's 2nd and 3rd", "Silver and bronze podium frames pickable"),
	Item("H08", "S3", "The Oracle after a month of T markets", "Its frames (a bank stand-in's IO)"),
	Item("H09", "S3", "A chat mark (after check 13)", "Before the name in guild, whisper, party, say and Olympus lines"),
	Item("H10", "S3", "The donor frame with the ranking private", "Shown"),
	Item("L01", "S1", "Memory and saved data, 1.1 against 1.2 idle", "Within the budget"),
	Item("L02", "S1", "A public event's alert to a spectator who never opened the arena", "Reaches him; the companion stays unloaded"),
	Item("L03", "S1", "The Bones board in combat", "Closes and comes back; the clock paused"),
	Item("Z01", "S1", "/reload a spectator, the arbiter and the bank mid-event", "Back within a minute; no bet lost"),
	Item("Z02", "S3", "Kill the bank's client mid-betting", "Replay from two auditors' copies; record the gap"),
	Item("Z03", "S3", "A late joiner mid-card", "Card, pools and his bets within a minute"),
	Item("Z04", "S3", "The other realm's spectator", "The \"(PvP 2)\" tag and the reason"),
	Item("Z05", "S3", "30-40 players, 10 minutes of chat and betting", "No disconnects; record the send queues"),
	Item("Z06", "S4", "Army rehearsal on release 1.2", "The army sees nothing without rehearsals on"),
	Item("Z07", "S4", "\"Arena fee TEST\" to a Treasurer stand-in", "Not counted by the real Treasurer's book"),
	Item("Z08", "S2", "Copper mode's record", "Every copper deposit and bet in db.arenaCopper; test clear refused until refunded"),
}
local BY_ID = {}
for _, item in ipairs(ArenaTest.CHECKLIST) do BY_ID[item.id] = item end
ArenaTest.CheckItem = function(id) return BY_ID[id] end

local function Marks()
	if not ns.db then return nil end
	if type(ns.db.arenaChecklist) ~= "table" then ns.db.arenaChecklist = {} end
	return ns.db.arenaChecklist
end
-- Ticks an item: s "p" pass, "f" fail, "k" skip, nil clears; note: 80 bytes at most (cut on a
-- character). Kept on this client only (never backed up).
function ArenaTest.Mark(id, s, note)
	if not BY_ID[id] then return false, "id" end
	if s ~= nil and s ~= "p" and s ~= "f" and s ~= "k" then return false, "state" end
	local marks = Marks()
	if not marks then return false, "db" end
	if s == nil then marks[id] = nil return true end
	note = tostring(note or ""):gsub("[|%c]", "")
	if #note > ArenaTest.NOTE_MAX then
		local cut = ArenaTest.NOTE_MAX
		while cut > 1 and (note:byte(cut + 1) or 0) >= 128 and (note:byte(cut + 1) or 0) < 192 do cut = cut - 1 end
		note = note:sub(1, cut)
	end
	if not marks[id] then
		local n = 0
		for _ in pairs(marks) do n = n + 1 end
		if n >= ArenaTest.CHECKLIST_MAX then return false, "full" end
	end
	marks[id] = { s = s, at = Now(), note = note ~= "" and note or nil }
	ns.Arena.Changed()
	return true
end
function ArenaTest.MarkOf(id)
	local marks = Marks()
	return marks and marks[id] or nil
end

-- The test report (the Director's Copy): build, commit and roster, then every item; plain text.
local WORDS = { p = "pass", f = "FAIL", k = "skip" }
function ArenaTest.Report()
	local lines = {}
	local A = ns.Arena
	lines[#lines + 1] = "Olympus arena test report"
	lines[#lines + 1] = A.TestBuildLine and A.TestBuildLine() or ("release " .. tostring(ns.VERSION))
	local s = Store()
	if type(s) == "table" and s.rid then
		lines[#lines + 1] = ("rehearsal %d: %s lane, %s, director %s%s"):format(s.rid, s.lane == "a" and "army" or "group",
			s.money == "p" and "copper" or ("chips " .. tostring(s.chips or ArenaTest.CHIPS)), ns.DisplayName(s.director) or "?", s.closedAt and " (closed)" or "")
	end
	local r = ArenaTest.Roster()
	lines[#lines + 1] = ("roster: %d"):format(#r)
	for _, t in ipairs(r) do
		lines[#lines + 1] = ("  %s: build %d of %s, flags %s%s%s"):format(ns.DisplayName(t.name) or t.name, t.build, t.base, t.flags ~= "" and t.flags or "-",
			t.role and (", role " .. t.role) or "", t.gone and " (gone)" or "")
	end
	local counts = { p = 0, f = 0, k = 0 }
	for _, item in ipairs(ArenaTest.CHECKLIST) do
		local m = ArenaTest.MarkOf(item.id)
		if m and counts[m.s] then counts[m.s] = counts[m.s] + 1 end
	end
	lines[#lines + 1] = ("checklist: %d pass, %d fail, %d skip, %d open"):format(counts.p, counts.f, counts.k, #ArenaTest.CHECKLIST - counts.p - counts.f - counts.k)
	for _, item in ipairs(ArenaTest.CHECKLIST) do
		local m = ArenaTest.MarkOf(item.id)
		lines[#lines + 1] = ("%s %s  %s%s"):format(item.id, m and WORDS[m.s] or "open", item.what, m and m.note and (" - " .. m.note) or "")
	end
	local text = table.concat(lines, "\n"):gsub("|", "")
	return text
end

---------------------------------------------------------------------------
-- /oly arena test ..., /oly arena checklist, /oly arena rehearsals on|off
---------------------------------------------------------------------------

local function OpenDirector(what)
	if not ns.Arena.LoadUI() then return end
	local ui = ns.Arena.ui
	if type(ui) == "table" and type(ui.Open) == "function" then ns.SafeCall("arena director", ui.Open, "director", what) end
end
ns.Arena.Slash("test", function(args)
	local words = {}
	for w in tostring(args or ""):lower():gmatch("%S+") do words[#words + 1] = w end
	local verb = words[1] or "status"
	if verb == "start" then
		local lane, money, chips = "group", "chips", nil
		for i = 2, #words do
			local w = words[i]
			if w == "group" or w == "army" then lane = w
			elseif w == "chips" or w == "copper" then money = w
			elseif tonumber(w) then chips = tonumber(w) end
		end
		return ArenaTest.Start(lane, money, chips)
	elseif verb == "stop" then
		return ArenaTest.Stop()
	elseif verb == "clear" then
		return ArenaTest.Clear()
	elseif verb == "report" then
		local ui = ns.UI
		if ui and ui.ShowCopy then ui.ShowCopy(L.ARENA_TEST_REPORT, ArenaTest.Report()) else print(ArenaTest.Report()) end
		return
	end
	local r = ArenaTest.Running()
	if r then
		ns.Print(L.ARENA_TEST_STATUS:format(r.rid, r.lane == "army" and L.ARENA_TEST_ARMY or L.ARENA_TEST_GROUP,
			r.money == "p" and L.ARENA_TEST_COPPER or L.ARENA_TEST_CHIPS_WORD, ns.DisplayName(r.director) or "?"))
	else
		ns.Print(L.ARENA_TEST_NONE)
	end
	local open = ArenaTest.CopperOpen()
	if #open > 0 then ArenaTest.PrintCopper(open) end
end, L.ARENA_HELP_TEST)
ns.Arena.Slash("checklist", function() OpenDirector("checklist") end, L.ARENA_HELP_CHECKLIST)
ns.Arena.Slash("rehearsals", function(args)
	local on = tostring(args or ""):lower():match("^%s*(%a+)")
	if on ~= "on" and on ~= "off" then ns.Print(L.ARENA_HELP_REHEARSALS) return end
	ns.db.arenaUI = type(ns.db.arenaUI) == "table" and ns.db.arenaUI or {}
	ns.db.arenaUI.rehearsals = on == "on" or nil
	ns.Print(on == "on" and L.ARENA_REHEARSALS_ON or L.ARENA_REHEARSALS_OFF)
	ns.Arena.Changed()
end, L.ARENA_HELP_REHEARSALS)

function ArenaTest.Reset() roster = {} end -- (tests)
