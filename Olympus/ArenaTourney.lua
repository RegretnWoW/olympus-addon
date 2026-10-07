local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaTourney.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Tournaments (AT), registration and check-in, the /roll draw (AD) through ArenaBracket, Reached.
-- Registers AT AD and Arena.Events for T (entrants beside slots: markets key on entrants).
-- API (the design): New, Sign, CloseRegistration (freezes the entrant list 1..n, waitlist included),
--   CheckIn, DrawStep, Advance, Reached(tid, gk), StageOf(tid, entrant), Winner(tid), View(tid)
--   (the fights part's review) the bouts' arbiters: New's opts.arbiters, SetArbiter(tid, key|"*", name),
--   ArbiterFor(t, key, A, B); Count(t) (the entrants not withdrawn)
local ArenaTourney = {}
ns.ArenaTourney = ArenaTourney

-- A knockout of 4 to 32 (the design): registration (R) by whisper to the
-- promoter (AS~J), a waitlist of 8; closing it freezes the entrant list (numbers 1..n, the
-- waitlist included), the outright markets key on those numbers and open then; check-in (K) from
-- 30 minutes before the start (AS~K), a no-show dropped and the waitlist filling in; the draw (D)
-- by the drawer's /roll in his raid, one roll per slot, the first valid roll of each step counting
-- (farkle W1's rule), every step sent (AD) and checked by the raid against its own roll lines; the
-- bracket live (L) over ArenaBracket, each match a fight (a bout) with its arbiter; finished (F), or
-- cancelled (X).
--
-- The record: { tid, mode, st, fl, cat, size, tReg, tCheck, tStart, bo (digits, counted back from
--   the final), third, entrants = { { n, gk, name, chk, wait, level, class, race } } (n: the
--   entrant's number once closed), seeds (the drawn list: gks in seed order), bouts = { [key] =
--   fid }, lines (the drawer's own roll lines), words (the AD steps heard), title, promoter, drawer,
--   heardAt }

local L = ns.L
local T = ArenaTourney
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

T.ENTRANTS_MAX = 32
T.WAITLIST = 8
T.CHECK_BEFORE = 1800      -- check-in opens this long before the start
T.REPEAT_OPEN = 300        -- AT every 5 minutes in R and K...
T.REPEAT_LIVE = 120        -- ...2 minutes in D and L
T.TAKE_OVER = 1800         -- another public arbiter may take over after the promoter's this long silence
T.TITLE_MAX = 40
local STATES = { R = true, K = true, D = true, L = true, F = true, X = true }
local ENDED = { F = true, X = true }

local stats = { refused = {} }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function T.Stats() return stats end

local function Now() return Arena.Now() end
local function F() return ns.ArenaFights end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Me(name) return Same(name, ns.me) end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end

---------------------------------------------------------------------------
-- Stores (core while this client promotes or entered; else heavy, else memory)
---------------------------------------------------------------------------

local mem = { L = {}, T = {} }
local function Core(mode, make)
	if mode == "T" and not make and not Arena.Sim() and not (type(ns.rdb) == "table" and type(ns.rdb.arenaTest) == "table") then return nil end
	local s = Arena.Store(mode)
	if not s then return nil end
	if type(s.tourneys) ~= "table" then
		if not make then return nil end
		s.tourneys = {}
	end
	return s.tourneys
end
local function Heavy(mode)
	local h = Arena.Heavy(mode)
	if not h then return nil end
	if type(h.tourneys) ~= "table" then h.tourneys = {} end
	return h.tourneys
end
local function Find(tid)
	if type(tid) ~= "string" then return nil end
	for _, mode in ipairs({ "L", "T" }) do
		local places = { Core(mode), Heavy(mode), mem[mode] }
		for i = 1, 3 do
			if places[i] and type(places[i][tid]) == "table" then return places[i][tid] end
		end
	end
	return nil
end
T.Find = Find
function T.All()
	local out, seen = {}, {}
	for _, mode in ipairs({ "L", "T" }) do
		local places = { Core(mode) or {}, Heavy(mode) or {}, mem[mode] }
		for i = 1, 3 do
			for id, r in pairs(places[i]) do if type(r) == "table" and not seen[id] then seen[id] = true out[#out + 1] = r end end
		end
	end
	return out
end
local function Entered(t)
	for _, e in ipairs(t.entrants or {}) do if Me(e.name) then return e end end
	return nil
end
local function Put(t)
	local mode = t.mode == "T" and "T" or "L"
	local core, heavy = Core(mode, true), Heavy(mode)
	local home = (Me(t.promoter) or Me(t.drawer) or Entered(t)) and core or heavy or mem[mode]
	local places = { core, heavy, mem[mode] }
	for i = 1, 3 do if places[i] and places[i] ~= home then places[i][t.tid] = nil end end
	home[t.tid] = t
	local n, list = 0, {}
	for id, x in pairs(home) do n = n + 1 if x.st == "F" or x.st == "X" then list[#list + 1] = { id = id, t = x.heardAt or 0 } end end
	if n > 10 then
		table.sort(list, function(a, b) return a.t < b.t end)
		for i = 1, math.min(#list, n - 10) do home[list[i].id] = nil end
	end
end

---------------------------------------------------------------------------
-- The wire: AT
---------------------------------------------------------------------------

local CHK = { [true] = "1", [false] = "0" }
local function Encode(t)
	local ents = {}
	for _, e in ipairs(t.entrants) do
		local state = e.out and "x" or (e.wait and "w" or CHK[e.chk == true])
		ents[#ents + 1] = table.concat({ B36(e.n or 0), e.gk or "-", F().Wire(e.name), state }, ":")
	end
	local slots = {}
	for i, gk in ipairs(t.seeds or {}) do slots[#slots + 1] = "s" .. B36(i) .. ":" .. gk end
	local keys = {}
	for key in pairs(t.bouts or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do slots[#slots + 1] = "m" .. key .. "=" .. t.bouts[key] end
	return table.concat({ t.tid, t.st, t.fl ~= "" and t.fl or "-", t.cat, B36(t.size or 0), B36(t.tReg), B36(t.tCheck), B36(t.tStart), t.bo,
		t.third and "1" or "0", #ents > 0 and table.concat(ents, ",") or "-", #slots > 0 and table.concat(slots, ",") or "-",
		t.title ~= "" and t.title or "-" }, "~")
end
T.Encode = Encode

local function Send(t, urgent)
	t.sentAt = Now()
	-- (The promoter's own word is heard here too: another promoter never takes over on his client.)
	if Me(t.promoter) then t.heardAt = Now() end
	Arena.Send("AT", t.mode, Encode(t), { key = "at " .. t.tid, urgent = urgent })
end

local function OnTourney(dist, sender, mode, body)
	local tid, st, fl, cat, size, tReg, tCheck, tStart, bo, third, ents, slots, title = Arena.Fields(body, 13)
	if not title then return Count("shape") end
	if not tid:find("^T[0-9a-z]+$") or #tid > 20 or not STATES[st] then return Count("shape") end
	if not ns.ArenaRoles.MayPromote(sender, mode) then return Count("promoter") end
	local t = Find(tid)
	if t and not Same(sender, t.promoter) then
		-- Another promoter may take a tournament over after the promoter's long silence (the design),
		-- never on the promoter's own client while he promotes it.
		if Me(t.promoter) then return Count("promoter") end
		if not (ns.ArenaRoles.IsPublicArbiter(sender, mode) and Now() - (t.heardAt or 0) >= T.TAKE_OVER) then return Count("promoter") end
		local C = ns.Chronicle
		if C and not C.missing and C.Add then C.Add("arena", sender, L.ARENA_CHRONICLE_TAKEOVER:format(tid)) end
	elseif not t and not F().MadeBy(tid, sender) then
		return Count("hash")
	end
	t = t or { tid = tid, mode = mode }
	local was = t.st
	t.promoter, t.st, t.fl, t.cat = ns.FullName(sender), st, fl ~= "-" and fl or "", cat
	t.size, t.tReg, t.tCheck, t.tStart = N(size, 0, 32) or 0, N(tReg, 0, 4294967295) or 0, N(tCheck, 0, 4294967295) or 0, N(tStart, 0, 4294967295) or 0
	t.bo = tostring(bo):match("^[135]+$") and bo or "1"
	t.third = third == "1"
	t.title = title ~= "-" and title:gsub("[%c|~]", ""):sub(1, T.TITLE_MAX) or ""
	local list = {}
	if ents ~= "-" then
		for part in ents:gmatch("[^,]+") do
			local n, gk, name, state = part:match("^([0-9a-z]+):([^:]+):([^:]+):([01wx])$")
			if n and #list < T.ENTRANTS_MAX + T.WAITLIST then
				list[#list + 1] = { n = N(n, 0, 99) ~= 0 and N(n, 0, 99) or nil, gk = Gk(gk), name = F().Unwire(name, sender), chk = state == "1",
					wait = state == "w", out = state == "x" }
			end
		end
	end
	t.entrants = list
	t.seeds, t.bouts = {}, {}
	if slots ~= "-" then
		for part in slots:gmatch("[^,]+") do
			local i, gk = part:match("^s([0-9a-z]+):(.+)$")
			local key, fid = part:match("^m(%d+%.%d+)=(F[0-9a-z]+)$")
			if i and Gk(gk) then t.seeds[N(i, 1, 32) or 0] = gk end
			if key then t.bouts[key] = fid end
		end
	end
	t.heardAt = Now()
	if ENDED[st] then t.endedAt = t.endedAt or t.heardAt else t.endedAt = nil end
	Put(t)
	if was ~= st then ns.Fire("ARENA_TOURNEY", tid, st) end
	Arena.Changed()
end
ns.Comm.Handle("AT", ns.Arena.Handle("AT", OnTourney))

---------------------------------------------------------------------------
-- The promoter's side
---------------------------------------------------------------------------

local function Mine(tid)
	local t = Find(tid)
	if not t then return nil, "tourney" end
	if not Me(t.promoter) then return nil, "promoter" end
	return t
end

-- opts: { title, cat (default "A"), size (the places: 4, 8, 16 or 32; default 32), tReg, tStart
--   (server times), bo (digits: "1135"), third, titleFight (flag t), rehearsal, drawer (an arbiter the
--   promoter names for the draw), arbiters (the public arbiters who judge its bouts, in turn: a
--   promoter who is not one, a Steward or a Hand, the design, names them; T.SetArbiter later),
--   markets (false disables; a list overrides the deterministic outright/reached defaults) }
function T.New(opts)
	opts = opts or {}
	local mode = Arena.NewMode(opts.rehearsal)
	if not ns.ArenaRoles.MayPromote(ns.me, mode) then return nil, "promoter" end
	local arbiters = {}
	for _, name in ipairs(type(opts.arbiters) == "table" and opts.arbiters or {}) do
		local n = Arena.Name(name)
		if not n or not ns.ArenaRoles.IsPublicArbiter(n, mode) then return nil, "arbiter" end
		arbiters[#arbiters + 1] = n
	end
	local now = Now()
	local tStart = tonumber(opts.tStart) or (now + 3 * 3600)
	local tReg = tonumber(opts.tReg) or (tStart - T.CHECK_BEFORE)
	if tReg > tStart or tStart < now then return nil, "time" end
	local bo = tostring(opts.bo or "1")
	if not bo:match("^[135]+$") then return nil, "bo" end
	local size = tonumber(opts.size) or T.ENTRANTS_MAX
	if size ~= 4 and size ~= 8 and size ~= 16 and size ~= 32 then return nil, "size" end
	local tid = Arena.NewId("T", function(id) return Find(id) ~= nil end)
	if not tid then return nil, "id" end
	local t = { tid = tid, mode = mode, st = "R", fl = opts.titleFight and "t" or "", cat = opts.cat or "A", size = size, tReg = tReg,
		tCheck = tStart - T.CHECK_BEFORE, tStart = tStart, bo = bo, third = opts.third and true or false, entrants = {}, seeds = {}, bouts = {},
		title = tostring(opts.title or ""):gsub("[%c|~]", ""):sub(1, T.TITLE_MAX), promoter = ns.me, drawer = opts.drawer, heardAt = now,
		marketSpecs = opts.markets == false and false or opts.markets, marketDefault = opts.markets == nil, arbiters = arbiters, arbs = {} }
	Put(t)
	Send(t, true)
	ns.Fire("ARENA_TOURNEY", tid, "R")
	T.Watch()
	return tid
end

local function MarketSheet(t)
	local M = ns.Markets
	return type(M) == "table" and type(M.Sheet) == "function" and M.Sheet(t.tid, t.mode) or nil
end

local function DefaultMarkets(t)
	local n = tonumber(t.n) or 0
	local out = { { type = "CH" } }
	if n > 2 then out[#out + 1] = { type = "RF" } end
	if n > 4 then out[#out + 1] = { type = "RS" } end
	if n > 8 then out[#out + 1] = { type = "RQ" } end
	return out
end

-- Registration freezes the entrant numbers used by every tournament outcome. The first sheet
-- stays open just past check-in so no-shows can be scratched before the draw shortens its lock.
local function OpenMarkets(t)
	if t.marketSpecs == false then return false, "disabled" end
	if MarketSheet(t) then t.marketOpened, t.marketWhy = true, nil return true end
	local M = ns.Markets
	if type(M) ~= "table" or type(M.Open) ~= "function" then t.marketWhy = "markets" return false, t.marketWhy end
	local specs = t.marketSpecs
	if specs == nil then specs = DefaultMarkets(t) end
	if type(specs) ~= "table" or #specs == 0 then t.marketWhy = "markets" return false, t.marketWhy end
	local lockAt = math.max(Now(), tonumber(t.tStart) or Now()) + Arena.OpenMin(true)
	local called, ok, why = pcall(M.Open, t.tid, { markets = specs, mode = t.mode, lockAt = lockAt })
	if called and ok == true and MarketSheet(t) then
		t.marketOpened, t.marketWhy = true, nil
		return true
	end
	t.marketWhy = called and (why or "markets") or "markets"
	return false, t.marketWhy
end

-- A fighter's sign-up (AS~J), check-in (AS~K) or withdrawal (AS~W), on the promoter's client:
-- checked in order (the design) and answered.
function T.OnSign(sender, mode, tid, what, rest)
	local t = Find(tid)
	if not t or not Me(t.promoter) then return Count("tourney") end
	local gk, level, class, race = Arena.Fields(rest or "", 4)
	local function Answer(code) Arena.Send("AS", t.mode, tid .. "~" .. code, { to = sender }) return code end
	local function Entry() for _, e in ipairs(t.entrants) do if Same(e.name, sender) then return e end end end
	if what == "W" then
		local e = Entry()
		if e then e.out = true Send(t, true) end
		return Answer("O")
	end
	if what == "K" then
		local e = Entry()
		if not e or e.out then return Answer("X") end
		if t.st ~= "K" or Now() < t.tCheck or Now() > t.tStart then return Answer("L") end
		e.chk = true
		Send(t, true)
		return Answer("O")
	end
	if what ~= "J" then return end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.Hides and M.Hides(sender) then return Answer("X") end
	if ns.Arena.Sanctioned and ns.Arena.Sanctioned(sender) then return Answer("X") end -- (1.1.6: WatchChat.Barred)
	-- His gk: given, not one the game names for someone else, and no other entrant's (the draw
	-- keys on it; the weigh-in checks it again at each bout).
	if not Gk(gk) then return Answer("X") end
	local P = ns.ArenaProfile
	if P and P.VerifyGk and P.VerifyGk(sender, Gk(gk)) == false then return Answer("X") end
	for _, e in ipairs(t.entrants) do
		if not e.out and e.gk == Gk(gk) and not Same(e.name, sender) then return Answer("C") end
	end
	local blocked = F().Hook("Debts", "Blocked")
	if blocked then local ok, yes = pcall(blocked, sender, Gk(gk)) if ok and yes then return Answer("D") end end
	if Gk(gk) and F().NoShows(Gk(gk), t.mode) >= F().NO_SHOWS_BLOCK then return Answer("B") end
	if not F().InCategory(t.cat, { level = tonumber(level), class = class, race = tonumber(race) }) then return Answer("C") end
	if t.st ~= "R" or (t.tReg > 0 and Now() > t.tReg) then return Answer("L") end
	if Entry() then return Answer("O") end
	-- One player once (his alts too).
	for _, e in ipairs(t.entrants) do if not e.out and F().SamePerson(e.name, sender) then return Answer("C") end end
	local live = 0
	for _, e in ipairs(t.entrants) do if not e.out then live = live + 1 end end
	local cap = T.Cap(t)
	if live >= cap + T.WAITLIST then return Answer("F") end
	t.entrants[#t.entrants + 1] = { gk = Gk(gk), name = ns.FullName(sender), level = tonumber(level), class = class, race = tonumber(race),
		wait = live >= cap, chk = false, at = Now() }
	Send(t)
	return Answer(live >= cap and "P" or "O")
end

-- The promoter's answer to our own sign-up (AS: O F C D X L B P).
function T.OnAnswer(sender, tid, code)
	local t = Find(tid)
	if not t or not Same(sender, t.promoter) then return end
	t.mine = code
	Arena.Changed()
end

-- Sign up (AS~J to the promoter).
function T.Sign(tid)
	local t = Find(tid)
	if not t then return false, "tourney" end
	if not Arena.RulesAccepted() then return false, "rules" end
	local R = ns.Roster
	local classFile
	if UnitClass then classFile = select(2, UnitClass("player")) end
	local raceID
	if UnitRace then raceID = select(3, UnitRace("player")) end
	Arena.Send("AS", t.mode, table.concat({ tid, "J", F().MyGk() or "-", tostring(UnitLevel and UnitLevel("player") or 0),
		classFile and R and R.ClassCode and R.ClassCode(classFile) or "-", tostring(raceID or "-") }, "~"), { to = t.promoter })
	return true
end
function T.CheckIn(tid)
	local t = Find(tid)
	if not t then return false, "tourney" end
	if t.st ~= "K" then return false, "state" end
	Arena.Send("AS", t.mode, tid .. "~K", { to = t.promoter })
	return true
end

-- Registration closed (the design): the entrant list frozen, numbered 1..n (the waitlist after
-- the others, in order); the outright markets open on those numbers. Check-in next.
function T.CloseRegistration(tid)
	local t, why = Mine(tid)
	if not t then return false, why end
	if t.st ~= "R" then return false, "state" end
	local n = 0
	for _, e in ipairs(t.entrants) do
		if not e.out then n = n + 1 e.n = n end
	end
	t.n, t.closed, t.st = n, true, "K"
	-- Entrant numbers must reach banks before the first keyed market sheet does.
	Send(t, true)
	OpenMarkets(t)
	ns.Fire("ARENA_TOURNEY", tid, "K")
	return true
end

-- The entrants signed up and not withdrawn (the events list's count, on every client).
function T.Count(t)
	local n = 0
	for _, e in ipairs(type(t) == "table" and t.entrants or {}) do if not e.out then n = n + 1 end end
	return n
end

-- Who plays: the checked-in entrants, the waitlist filling the places of the no-shows in order.
-- The places of a tournament (its size as the promoter set it), then the waitlist's 8.
function T.Cap(t)
	local s = tonumber(t.size) or 0
	if s ~= 4 and s ~= 8 and s ~= 16 and s ~= 32 then return T.ENTRANTS_MAX end
	return s
end
function T.Field(t)
	local out, seats = {}, T.Cap(t)
	for _, e in ipairs(t.entrants) do
		if not e.out and not e.wait and e.chk then out[#out + 1] = e end
	end
	for _, e in ipairs(t.entrants) do
		if #out >= seats then break end
		if not e.out and e.wait and e.chk then out[#out + 1] = e end
	end
	return out
end
-- An entrant who did not get in or did not check in: scratched (markets refund his outcome).
function T.Scratched(t)
	local inField = {}
	for _, e in ipairs(T.Field(t)) do inField[e.gk or e.name] = true end
	local out = {}
	for _, e in ipairs(t.entrants) do
		if e.n and not inField[e.gk or e.name] then out[#out + 1] = e.n end
	end
	return out
end

local function VoidMarkets(t, code)
	local M = ns.Markets
	if not MarketSheet(t) then return true end
	if type(M) ~= "table" or type(M.Void) ~= "function" then t.marketWhy = "markets" return false, t.marketWhy end
	local called, ok, why = pcall(M.Void, t.tid, "*", code or "X")
	if called and (ok == true or why == "none") then
		t.marketDone, t.marketPending, t.marketWhy = true, nil, nil
		return true
	end
	t.marketWhy = called and (why or "markets") or "markets"
	t.marketPending = true
	return false, t.marketWhy
end

-- Once check-in fixes the field, remove every no-show/waitlist miss, freeze the bracket size and
-- add one stage market for each actual fighter. Any failed terms update voids the sheet rather
-- than letting bets remain attached to a different field.
local function PrepareMarkets(t, field)
	if not MarketSheet(t) then return true end
	local M = ns.Markets
	if type(M) ~= "table" then return VoidMarkets(t, "T") end
	local steps = {
		{ M.Scratch, T.Scratched(t) },
		{ M.SetSize, t.size },
	}
	for _, step in ipairs(steps) do
		if type(step[1]) ~= "function" then return VoidMarkets(t, "T") end
		local called, ok, why = pcall(step[1], t.tid, step[2])
		if not called or ok ~= true then
			t.marketWhy = called and (why or "markets") or "markets"
			VoidMarkets(t, "T")
			return false, t.marketWhy
		end
	end
	local stages = {}
	for _, e in ipairs(field) do stages[#stages + 1] = { type = "ST", param = e.n } end
	if #stages > 0 then
		if type(M.AddMarkets) ~= "function" then return VoidMarkets(t, "T") end
		local called, ok, why = pcall(M.AddMarkets, t.tid, stages)
		if not called or ok ~= true then
			t.marketWhy = called and (why or "markets") or "markets"
			VoidMarkets(t, "T")
			return false, t.marketWhy
		end
	end
	t.marketOpened, t.marketWhy = true, nil
	return true
end

local function DrawEntrants(t)
	local list = {}
	for _, e in ipairs(T.Field(t)) do
		local LG = ns.ArenaLedger
		local rating, fights
		if LG and LG.Rating then rating, fights = LG.Rating(e.gk) end
		list[#list + 1] = { id = e.gk, name = e.name, rating = rating, fights = fights }
	end
	return list
end

-- Check-in over: the field fixed (3 to 32), the draw begins (the drawer in his raid).
function T.StartDraw(tid)
	local t, why = Mine(tid)
	if not t then return false, why end
	if t.st ~= "K" then return false, "state" end
	local field = T.Field(t)
	local AB = ns.ArenaBracket
	if #field < AB.MIN then
		t.st = "X"
		t.endedAt = t.endedAt or Now()
		VoidMarkets(t, "X")
		Send(t, true)
		ns.Fire("ARENA_TOURNEY", tid, "X")
		return false, "few"
	end
	for _, e in ipairs(t.entrants) do if e.n and not e.chk then e.out = true end end
	t.size = AB.Size(#field)
	t.st, t.lines, t.words = "D", {}, {}
	t.drawer = t.drawer or ns.me
	-- Publish the fixed field before the sheet's scratch/size/stage revision.
	Send(t, true)
	PrepareMarkets(t, field)
	ns.Fire("ARENA_TOURNEY", tid, "D")
	T.Watch()
	return true
end

-- The drawer's state: the draw from the rolls taken so far.
function T.DrawState(t)
	local AB = ns.ArenaBracket
	local rolls = t.lines and #t.lines > 0 and t.lines or t.words or {}
	return AB.DrawState(DrawEntrants(t), rolls, AB.SeedCount(#T.Field(t)))
end

-- The drawer's Roll click: one RandomRoll(1, R) for the next step (the game's line decides).
function T.DrawStep(tid) -- gp:arena-clicks
	local t = Find(tid)
	if not t then return false, "tourney" end
	if not (Me(t.drawer) or Me(t.promoter)) then return false, "drawer" end
	if t.st ~= "D" then return false, "state" end
	local state, why = T.DrawState(t)
	if not state then return false, why end
	local lo, hi, step = ns.ArenaBracket.NextRange(state)
	if not lo then return T.FinishDraw(tid) end
	if type(RandomRoll) ~= "function" then return false, "api" end
	T.HookRolls()
	RandomRoll(lo, hi)
	return true, step, hi
end

-- A roll line (CHAT_MSG_SYSTEM): the drawer's own on his client (the step taken, then AD); on a
-- raid member's, the witness's check of the AD words heard.
local rollsHooked = false
function T.HookRolls()
	if rollsHooked then return end
	rollsHooked = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("arena roll line", T.OnSystem, text) end)
end
function T.OnSystem(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local P = ns.ArenaParse
	if not (P and P.Roll) then return end
	local name, value, low, high = P.Roll(text)
	if not name then return end
	for _, t in ipairs(T.All()) do
		local who = ns.Normal and ns.Normal(name) or name
		if t.st == "D" and t.drawer and ns.ShortName(ns.FullName(who)):lower() == ns.ShortName(t.drawer):lower() then
			if Me(t.drawer) then
				t.lines = t.lines or {}
				local before = T.DrawState(t)
				t.lines[#t.lines + 1] = { roll = value, low = low, high = high }
				local after = T.DrawState(t)
				-- The step this line took (the first valid roll counts; others are flagged).
				if before and after and before.step and (after.step ~= before.step or not after.step) then
					local step = before.step
					local pos = ns.ArenaBracket.PositionOf(before.size, before.k + step)
					local e = after.list[before.k + step]
					Arena.Send("AD", t.mode, table.concat({ t.tid, B36(step), B36(value), B36(high), B36(pos or 0), e and e.id or "-" }, "~"),
						{ urgent = true })
					if not after.step then T.FinishDraw(t.tid) end
				end
				Arena.Changed()
			else
				t.witnessLines = t.witnessLines or {}
				t.witnessLines[#t.witnessLines + 1] = { roll = value, low = low, high = high }
				T.CheckWitness(t)
			end
		end
	end
end

-- A raid member compares the drawer's words with the lines he read himself: a step whose roll
-- differs shows "draw disputed" and goes to the Chronicle.
function T.CheckWitness(t)
	if not t.witnessLines or not t.words then return end
	local AB = ns.ArenaBracket
	local own = AB.DrawState(DrawEntrants(t), t.witnessLines, AB.SeedCount(#T.Field(t)))
	if not own then return end
	for _, w in ipairs(t.words) do
		local mine = own.rolls and own.rolls[w.step]
		if mine and mine ~= w.roll and not t.disputed then
			t.disputed = w.step
			local C = ns.Chronicle
			if C and not C.missing and C.Add then C.Add("arena", t.drawer, L.ARENA_CHRONICLE_DRAW:format(t.tid, w.step)) end
			ns.Fire("ARENA_TOURNEY", t.tid, "disputed")
		end
	end
end

-- AD: a draw step, from the drawer (the promoter or his named arbiter).
local function OnDraw(dist, sender, mode, body)
	local tid, step, roll, max, pos, gk = Arena.Fields(body, 6)
	if not gk then return Count("shape") end
	local t = Find(tid)
	if not t or not (Same(sender, t.drawer) or Same(sender, t.promoter)) then return Count("drawer") end
	t.drawer = t.drawer or ns.FullName(sender)
	step, roll, max = N(step, 1, 32), N(roll, 1, 32), N(max, 1, 32)
	if not (step and roll and max) then return Count("shape") end
	t.words = t.words or {}
	for _, w in ipairs(t.words) do if w.step == step then return Count("again") end end
	t.words[#t.words + 1] = { step = step, roll = roll, max = max }
	T.CheckWitness(t)
	ns.Fire("ARENA_TOURNEY", tid, "draw")
	Arena.Changed()
end
ns.Comm.Handle("AD", ns.Arena.Handle("AD", OnDraw))

-- The draw complete: the bracket built (ArenaBracket.Build with the best-of and the third place),
-- the first round's bouts made, live.
function T.FinishDraw(tid)
	local t, why = Mine(tid)
	if not t then
		t = Find(tid)
		if not (t and Me(t.drawer)) then return false, why end
	end
	local AB = ns.ArenaBracket
	local list, flags = AB.ApplyDraw(DrawEntrants(t), t.lines and #t.lines > 0 and t.lines or t.words or {}, AB.SeedCount(#T.Field(t)))
	if not list then return false, flags end
	t.flags = flags
	t.seeds = {}
	for i, e in ipairs(list) do t.seeds[i] = e.id end
	if not Me(t.promoter) then return true end
	t.bracket = AB.Build(list, { bo = t.bo, third = t.third })
	if not t.bracket then return false, "bracket" end
	t.st = "L"
	-- The seeds and drawn state lead the PK revision, so every receiver can validate it.
	Send(t, true)
	local M = ns.Markets
	if MarketSheet(t) then
		-- The full bracket is knowable only now. Its entry is the realm's minimum bet rounded up
		-- to whole silver; the pick itself settles from the finished bracket, never from a guess.
		if t.marketDefault and type(M) == "table" and type(M.AddMarkets) == "function" then
			local settings = type(M.Settings) == "function" and M.Settings() or {}
			local entry = math.max(1, math.ceil((tonumber(settings.minBet) or 1000) / 100))
			local called, ok, marketWhy = pcall(M.AddMarkets, t.tid, { { type = "PK", param = entry } })
			if not called or ok ~= true then t.marketWhy = called and (marketWhy or "markets") or "markets" end
		end
		if type(M) ~= "table" or type(M.CloseBets) ~= "function" then
			VoidMarkets(t, "T")
		else
			local called, ok, marketWhy = pcall(M.CloseBets, t.tid)
			if not called or (ok ~= true and marketWhy ~= "closed") then
				t.marketWhy = called and (marketWhy or "markets") or "markets"
				VoidMarkets(t, "T")
			else
				local sheet = MarketSheet(t)
				t.marketLockAt = sheet and sheet.lockAt or nil
				t.marketPending = true
			end
		end
	end
	T.Advance(tid)
	Send(t, true)
	ns.Fire("ARENA_TOURNEY", tid, "L")
	return true
end

local function EntrantOf(t, gk)
	for _, e in ipairs(t.entrants) do if e.gk == gk then return e end end
	return nil
end

local function EntrantNumber(t, gk)
	local e = EntrantOf(t, gk)
	return e and e.n or nil
end

-- Facts are derived only from the bracket. Reached markets appear once the exact two/four/eight
-- are known; a fighter's stage appears only once he can no longer advance.
function T.MarketResults(tid)
	local t = type(tid) == "table" and tid or Find(tid)
	local br = t and t.bracket
	if not br then return nil end
	local AB = ns.ArenaBracket
	local facts = { stages = {} }
	local finalists, semifinalists, quarterfinalists = {}, {}, {}
	local fieldCount = 0
	for _, e in ipairs(t.entrants or {}) do
		if e.n and e.gk and br.entrants[e.gk] then
			fieldCount = fieldCount + 1
			local reached, alive = AB.Reached(br, e.gk)
			local rank = reached == "3" and (br.rounds - 1) or tonumber(reached)
			if rank and rank >= br.rounds then finalists[#finalists + 1] = e.n end
			if rank and rank >= br.rounds - 1 then semifinalists[#semifinalists + 1] = e.n end
			if rank and rank >= br.rounds - 2 then quarterfinalists[#quarterfinalists + 1] = e.n end
			if not alive then facts.stages[e.n] = AB.Stage(reached, br.rounds) end
		end
	end
	local function Exact(list, n)
		if #list ~= n then return nil end
		table.sort(list)
		return list
	end
	-- A registration market may have opened before no-shows reduced the field. In a three-person
	-- bracket all three have already reached the top four; in a four-person bracket all four have
	-- reached the top eight. `ReadResult` deliberately accepts fewer than k after scratches, so use
	-- the real field rather than waiting forever for entrants which no longer exist.
	facts.finalists = Exact(finalists, math.min(2, fieldCount))
	facts.semifinalists = Exact(semifinalists, math.min(4, fieldCount))
	facts.quarterfinalists = Exact(quarterfinalists, math.min(8, fieldCount))
	local champion = AB.Champion(br)
	facts.champion = champion and EntrantNumber(t, champion) or nil
	local bits, complete = {}, true
	for round = 1, br.rounds do
		for index = 1, br.size / 2 ^ round do
			local m = AB.Match(br, round .. "." .. index)
			if not (m and m.done and m.winner) then
				complete = false
			elseif m.winner == m.a then
				bits[#bits + 1] = 0
			elseif m.winner == m.b then
				bits[#bits + 1] = 1
			else
				complete = false
			end
		end
	end
	local AM = ns.ArenaMath
	if complete and type(AM) == "table" and type(AM.PickHex) == "function" then facts.bracket = AM.PickHex(bits) end
	return facts
end

local function MarketsPending(t)
	local sheet = MarketSheet(t)
	if not sheet then return false end
	for _, idx in ipairs(sheet.order or {}) do
		local m = sheet.markets and sheet.markets[idx]
		if m and (m.state == "O" or m.state == "L") then return true end
	end
	return false
end

local function FinishMarkets(t)
	if not MarketSheet(t) then return true end
	if not MarketsPending(t) then t.marketDone, t.marketPending, t.marketWhy = true, nil, nil return true end
	local M = ns.Markets
	local facts = T.MarketResults(t)
	if type(M) ~= "table" or type(M.Declare) ~= "function" or not facts then t.marketWhy = "markets" return false, t.marketWhy end
	local called, ok, why = pcall(M.Declare, t.tid, facts)
	if not called or ok ~= true then
		t.marketWhy = called and (why or "markets") or "markets"
		t.marketPending = true
		return false, t.marketWhy
	end
	-- When the bracket is over, any still-open row is unknowable rather than merely late. This
	-- includes a champion or reached round lost to a both-absent path and PK when the bracket has no
	-- truthful winner bit. Refund only those unresolved rows; deterministic rows stay settled.
	if t.st == "F" and MarketsPending(t) then
		if type(M.Void) ~= "function" then t.marketWhy = "markets" return false, t.marketWhy end
		local sheet = MarketSheet(t)
		for _, idx in ipairs(sheet and sheet.order or {}) do
			local market = sheet.markets and sheet.markets[idx]
			if market and (market.state == "O" or market.state == "L") then
				local voidCalled, voidOk, voidWhy = pcall(M.Void, t.tid, idx, "N")
				if not voidCalled or (voidOk ~= true and voidWhy ~= "none") then
					t.marketWhy = voidCalled and (voidWhy or "markets") or "markets"
					t.marketPending = true
					return false, t.marketWhy
				end
			end
		end
	end
	t.marketPending = MarketsPending(t) or nil
	if not t.marketPending then t.marketDone, t.marketWhy = true, nil end
	return true
end

-- A bout's arbiter: the one the promoter named for it (T.SetArbiter), else the next of his list in
-- turn, else the promoter himself when he is a public arbiter; never one of its fighters (nor an
-- alt of one). nil: none yet (the bout waits, and the promoter is told).
function T.ArbiterFor(t, key, A, B)
	local R = ns.ArenaRoles
	local function Ok(name)
		return type(name) == "string" and R.IsPublicArbiter(name, t.mode) and not (A and F().SamePerson(name, A)) and not (B and F().SamePerson(name, B))
	end
	if t.arbs and Ok(t.arbs[key]) then return t.arbs[key] end
	local list = type(t.arbiters) == "table" and t.arbiters or {}
	local n = #list
	for i = 1, n do
		local at = ((t.turn or 0) + i - 1) % n + 1
		if Ok(list[at]) then t.turn = at % n return list[at] end
	end
	if Ok(ns.me) then return ns.me end
	return nil
end

-- The promoter names a public arbiter: for one bout (key "<round>.<index>": a bout already made
-- changes hands before it goes live, as a card's does), or (key nil or "*") to his list.
function T.SetArbiter(tid, key, name)
	local t, why = Mine(tid)
	if not t then return false, why end
	local arb = Arena.Name(name or "")
	if not arb or not ns.ArenaRoles.IsPublicArbiter(arb, t.mode) then return false, "arbiter" end
	t.arbiters = type(t.arbiters) == "table" and t.arbiters or {}
	t.arbs = type(t.arbs) == "table" and t.arbs or {}
	if key == nil or key == "*" then
		for _, x in ipairs(t.arbiters) do if Same(x, arb) then return true end end
		t.arbiters[#t.arbiters + 1] = arb
		t.needArbiter, t.waitingArb = nil, nil
		if t.st == "L" then T.Advance(tid) end
		return true
	end
	if type(key) ~= "string" or not key:find("^%d+%.%d+$") then return false, "key" end
	local fid = t.bouts[key]
	local f = fid and F().Find("fights", fid)
	if f then
		local st = F().State(f)
		if not (st == "D" or st == "A" or st == "O" or st == "S") then return false, "state" end
		if F().SamePerson(arb, f.A.name) or (f.B and F().SamePerson(arb, f.B.name)) then return false, "arbiter-fighter" end
		-- (Its markets open: their sheet is its writer's, who alone closes and settles it.)
		if F().Has(f.fl, "m") and not Same(arb, f.writer) then return false, "markets" end
		f.arb, f.writer = arb, arb
		F().SendAF(f, true)
	end
	t.arbs[key] = arb
	t.needArbiter, t.waitingArb = nil, nil
	if not f and t.st == "L" then T.Advance(tid) end
	Arena.Changed()
	return true
end

-- The bracket moves on: every bout FINAL (or a walkover, void) decided in it, and the next round's
-- bouts made once both their feeders are.
function T.Advance(tid)
	local t, why = Mine(tid)
	if not t then return false, why end
	local br = t.bracket
	if not br then return false, "bracket" end
	local AB = ns.ArenaBracket
	for key, fid in pairs(t.bouts) do
		local m = AB.Match(br, key)
		local f = F().Find("fights", fid)
		if m and not m.done and f then
			local st = F().State(f)
			if st == "F" and f.w then
				local wgk, lgk = f[f.w].gk, f[f.w == "A" and "B" or "A"].gk
				local wins, losses = f.sc[f.w == "A" and 1 or 2], f.sc[f.w == "A" and 2 or 1]
				AB.Advance(br, key, wgk, f.m == "R" and "R" or (f.m == "D" and "D" or "K"), wins, losses)
			elseif st == "W" and f.w then
				AB.Walkover(br, key, f[f.w].gk)
			elseif st == "V" or st == "N" then
				AB.BothAbsent(br, key)
			end
		end
	end
	for _, m in ipairs(AB.Next(br)) do
		if not t.bouts[m.key] and m.a and m.b then
			local A, B = EntrantOf(t, m.a), EntrantOf(t, m.b)
			local final = m.round == br.rounds and not m.third
			local LG = ns.ArenaLedger
			local vacant = true
			if LG and LG.Belts then vacant = LG.Belts(t.mode)[t.cat] == nil or LG.Belts(t.mode)[t.cat].holder == nil end
			local arb = T.ArbiterFor(t, m.key, A and A.name, B and B.name)
			local fid, why
			if arb then
				fid, why = F().New({ A = A and A.name, B = B and B.name, gkA = m.a, gkB = m.b, bo = m.bo, cat = t.cat, tid = tid, slot = m.key,
					public = true, title = final and t.fl:find("t", 1, true) ~= nil and vacant, rehearsal = t.mode == "T", arb = arb })
			else
				why = "arbiter"
			end
			if fid then
				local f = F().Find("fights", fid)
				f.accepted.A, f.accepted.B = true, true
				t.bouts[m.key] = fid
				F().Announce(fid)
			elseif not (t.waitingArb and t.waitingArb[m.key]) then
				-- (Told once per bout: the promoter names an arbiter, T.SetArbiter, and it is made then.)
				t.waitingArb = t.waitingArb or {}
				t.waitingArb[m.key] = true
				t.needArbiter = t.needArbiter or m.key
				Count(why or "bout")
				ns.Log("arena tournament %s: bout %s not made: %s", tid, m.key, tostring(why))
				ns.Fire("ARENA_TOURNEY", tid, "arbiter")
			end
		end
	end
	if AB.Finished(br) then
		t.st = "F"
		t.endedAt = t.endedAt or Now()
		ns.Fire("ARENA_TOURNEY", tid, "F")
		-- A title tournament's winner: the number-one contender (a C word), when the belt is held.
		local LG = ns.ArenaLedger
		local champion = AB.Champion(br)
		if t.fl:find("t", 1, true) and champion and LG and LG.Word and ns.ArenaRoles.IsPublicArbiter(ns.me, t.mode) then
			local belt = LG.Belts(t.mode)[t.cat]
			if belt and belt.holder and belt.holder ~= champion then LG.Word("C", t.cat, champion, "tourney") end
		end
	end
	FinishMarkets(t)
	Send(t)
	return true
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- The bracket as this client can build it: the promoter's own, else from the drawn seeds and the
-- bouts' results heard.
function T.Bracket(tid)
	local t = Find(tid)
	if not t then return nil end
	if t.bracket then return t.bracket end
	if not t.seeds or not t.seeds[1] then return nil end
	local AB = ns.ArenaBracket
	local list = {}
	for i, gk in ipairs(t.seeds) do local e = EntrantOf(t, gk) list[i] = { id = gk, name = e and e.name } end
	local br = AB.Build(list, { bo = t.bo, third = t.third })
	if not br then return nil end
	for _ = 1, br.rounds + 1 do
		for key, fid in pairs(t.bouts or {}) do
			local m = AB.Match(br, key)
			local f = F().Find("fights", fid)
			if m and not m.done and m.a ~= nil and m.b ~= nil and f then
				local st = F().State(f)
				if st == "F" and f.w then
					AB.Advance(br, key, f[f.w].gk, f.m == "R" and "R" or (f.m == "D" and "D" or "K"), f.sc[f.w == "A" and 1 or 2], f.sc[f.w == "A" and 2 or 1])
				elseif st == "W" and f.w then AB.Walkover(br, key, f[f.w].gk)
				elseif st == "V" or st == "N" then AB.BothAbsent(br, key) end
			end
		end
	end
	return br
end

-- How far an entrant went (the design): the round he lost in, R + 1 for the champion, "3" for the
-- third-place winner; and whether it can still change.
function T.Reached(tid, gk)
	local br = T.Bracket(tid)
	if not br then return nil end
	return ns.ArenaBracket.Reached(br, gk)
end
-- The stage from the top (ST's outcomes): 1 champion ... 5 earlier; "scratched" for an entrant
-- number who is not in the bracket (no-show, not in, withdrawn). entrant: his number.
function T.StageOf(tid, entrant)
	local t = Find(tid)
	if not t then return nil end
	local e
	for _, x in ipairs(t.entrants) do if x.n == tonumber(entrant) then e = x end end
	if not e then return nil end
	local br = T.Bracket(tid)
	if not br then return nil end
	if not br.entrants[e.gk] then return "scratched" end
	local reached, alive = ns.ArenaBracket.Reached(br, e.gk)
	if alive then return nil end
	return ns.ArenaBracket.Stage(reached, br.rounds)
end
function T.Winner(tid)
	local br = T.Bracket(tid)
	return br and ns.ArenaBracket.Champion(br) or nil
end

-- The bracket's view model: { tid, title, screenTitle (T.ScreenTitle: the one for the King's screen),
-- st, cat, size, rounds, entrants, matches = { { key, round, a = { gk, name, n }, b = ..., fid, state,
-- winner, score } }, draw = { steps, total } }.
function T.View(tid)
	local t = Find(tid)
	if not t then return nil end
	local v = { tid = tid, title = t.title, screenTitle = T.ScreenTitle(tid), st = t.st, cat = t.cat, size = t.size, mode = t.mode, entrants = {}, matches = {}, promoter = t.promoter,
		tStart = t.tStart, tCheck = t.tCheck, disputed = t.disputed, count = T.Count(t), needArbiter = t.needArbiter,
		arbiters = Me(t.promoter) and type(t.arbiters) == "table" and { unpack(t.arbiters) } or nil }
	for _, e in ipairs(t.entrants) do
		v.entrants[#v.entrants + 1] = { n = e.n, gk = e.gk, name = e.name, chk = e.chk, wait = e.wait, out = e.out }
	end
	local br = T.Bracket(tid)
	if br then
		v.rounds = br.rounds
		for key, m in pairs(br.matches) do
			local fid = t.bouts[key]
			local f = fid and F().Find("fights", fid)
			local function Side(gk)
				if gk == nil then return nil end
				if gk == false then return { bye = true } end
				local e = EntrantOf(t, gk)
				return { gk = gk, name = e and e.name, n = e and e.n }
			end
			v.matches[#v.matches + 1] = { key = key, round = m.round, index = m.index, third = m.third, a = Side(m.a), b = Side(m.b), fid = fid,
				state = f and F().State(f) or (m.done and "done" or nil), winner = m.winner, score = m.sa .. ":" .. m.sb }
		end
		table.sort(v.matches, function(a, b) if a.round ~= b.round then return a.round < b.round end return a.index < b.index end)
	end
	if t.st == "D" then
		local state = T.DrawState(t)
		v.draw = { total = state and state.total or 0, steps = state and state.rolls and #state.rolls or 0, next = state and state.max }
	end
	return v
end

-- The title a tournament shows on the King's screen: its own only when the King set it (the design,
-- as a card's: Fight Night titles), else the plain word.
function T.ScreenTitle(tid)
	local t = Find(tid)
	if not t then return nil end
	if ns.ArenaRoles.IsKing(t.promoter) and (t.title or "") ~= "" then return t.title end
	return L.ARENA_TOURNEY
end

-- Answer an AQ~T (the tournament again, by whisper, from its promoter).
function T.Answer(sender, tid)
	local t = Find(tid)
	if not t or not Me(t.promoter) then return false end
	Arena.Send("AT", t.mode, Encode(t), { to = sender })
	return true
end

Arena.Events.Register("T", function(tid)
	local t = Find(tid)
	if not t then return nil end
	local entrants, slots = {}, {}
	for _, e in ipairs(t.entrants) do if e.n then entrants[e.n] = { name = e.name, gk = e.gk, class = e.class } end end
	for i, gk in ipairs(t.seeds or {}) do slots[i] = gk end
	local sheet = MarketSheet(t)
	local lockAt = sheet and sheet.lockAt or nil
	for _, fid in pairs(t.bouts or {}) do
		local f = F().Find("fights", fid)
		if f and f.lockAt and (not lockAt or f.lockAt < lockAt) then lockAt = f.lockAt end
	end
	return { kind = "tourney", opener = t.promoter, entrants = entrants, slots = slots, category = t.cat, public = true, mode = t.mode,
		lockAt = lockAt, state = t.st, size = (t.st == "D" or t.st == "L" or t.st == "F") and t.size or nil, scratched = T.Scratched(t),
		drawn = t.bracket ~= nil or (type(t.seeds) == "table" and t.seeds[1] ~= nil), promoter = t.promoter }
end)

---------------------------------------------------------------------------
-- The promoter's ticker: repeats, check-in opening, the bracket moving on
---------------------------------------------------------------------------

function T.Tick()
	local now = Now()
	for _, t in ipairs(T.All()) do
		if Me(t.promoter) and t.st ~= "F" and t.st ~= "X" then
			if t.st == "R" and t.tReg > 0 and now >= t.tReg then T.CloseRegistration(t.tid) end
			if t.st == "K" then
				if t.marketSpecs ~= false and not MarketSheet(t) then OpenMarkets(t) end
				if now >= t.tStart then T.StartDraw(t.tid) end
			end
			if t.st == "L" then T.Advance(t.tid) end
			local gap = (t.st == "D" or t.st == "L") and T.REPEAT_LIVE or T.REPEAT_OPEN
			if now - (t.sentAt or 0) >= gap then Send(t) end
		elseif Me(t.promoter) and MarketsPending(t) then
			t.marketPending = true
			if t.st == "X" then VoidMarkets(t, "X") else FinishMarkets(t) end
		end
	end
	T.Watch()
end
function T.Watch()
	local any = false
	for _, t in ipairs(T.All()) do
		if (Me(t.promoter) or Me(t.drawer)) and (t.st ~= "F" and t.st ~= "X" or (Me(t.promoter) and MarketsPending(t))) then any = true end
	end
	Arena.Involve("tourney", any or nil)
	Arena.Every(5, "tourney", any and T.Tick or nil)
end
ns.On("LOGIN", T.Watch)
ns.On("ARENA_RESULT", function() for _, t in ipairs(T.All()) do if Me(t.promoter) and t.st == "L" then T.Advance(t.tid) end end end)

Arena.Action("tourney.new", function() return ns.ArenaRoles.MayPromote(ns.me, Arena.NewMode()) end, function(opts) return T.New(opts) end)
Arena.Action("tourney.sign", nil, function(tid) return T.Sign(tid) end)
Arena.Action("tourney.close", nil, function(tid) return T.CloseRegistration(tid) end)
Arena.Action("tourney.checkin", nil, function(tid) return T.CheckIn(tid) end)
Arena.Action("tourney.draw", nil, function(tid) return T.StartDraw(tid) end)
Arena.Action("tourney.roll", nil, function(tid) return T.DrawStep(tid) end)
Arena.Action("tourney.arbiter", nil, function(tid, key, name) return T.SetArbiter(tid, key, name) end)
