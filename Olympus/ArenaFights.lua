local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaFights.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Fights (AF AG AC AW AR), challenges and sign-ups (AS), Fight Night cards (AN), the duel decision
-- rule, presence, walkovers and the Agenda rows. Registers AF AG AC AW AR AS AN, Arena.Events for
-- F and N, and a Week.providers row source.
-- API (the design):
--   Challenges: Challenge(opponent, opts), AskArbiter(oid, name)
--   Lifecycle: New(opts), Announce(fid), Accept(fid), Call(fid), Here(fid), Bell(fid), NextRound(fid),
--     Walkover(fid, side), Void(fid, code), NoContest(fid, code), Disqualify(fid, side, code),
--     Correct(fid, round, side, method)
--   Reading: Fight(fid), List(filter), IsFighter(fid, name) (alts included)
--   Cards: Card.New, AddBout, SetArbiter, SetFotN
--   (the fights part's review) this character's own fights: MyFights(mode); the weigh-in's unit: TokenOf(gk,
--     name); a staked challenge's checks: CheckIou(oid, payer, wire, stake, salt), CheckChallenger(c)
-- Promoters: ArenaRoles.MayPromote (the King, his Stewards and Hands, public arbiters: the owner's
-- answer). The duel itself starts with the game's own Duel button (the design).
local ArenaFights = {}
ns.ArenaFights = ArenaFights

-- Every fight is one record with one writer (the design): a public or private fight's writer is
-- its arbiter (or the card's promoter for a bout on his card), a direct fight's its challenger.
-- Every client takes a record only from its writer, by the name the server stamps.
--
-- The record (the design, with its renames):
--   { fid, mode ("L"|"T"), st, fl, bo, cat, arb (Name-Realm, nil: direct), card (cid), tid, slot,
--     A = { name, gk }, B = { name, gk } (nil: an open slot), writer, promoter,
--     tAnn, tCall, deadline, lockAt, round, sc = { a, b }, w ("A"|"B"), m (K R D W N V), dur,
--     rounds = { [r] = { w, m, dur, src, nW } }, graceEnd, code, facts = { A, B } (the weigh-in),
--     accepted = { A, B }, heardAt, from (a matchmaking id), stake }
-- States (the design): D draft (the writer's alone), A announced, O an open slot, S set, C called,
-- Y ready, Z last call, L live, B between rounds, R result (grace), F final, V void, N no contest,
-- W walkover.
-- Flags: p public, t title, m markets open, o open slot, k a tournament's bout, d direct, c on a
-- card, s stakes held by the arbiter, r rated (the arbiter's word), b may move its belt (the
-- arbiter's word: a public arbiter's title fight with both fighters eligible), x no markets (its
-- promoter kept the public fight out of betting: the arbiter who takes it over opens none).
--
-- Where records live (the design): the fights this client is part of (fighter, arbiter, writer,
-- promoter) in the core store (Arena.Store); the others in the companion's heavy tables while it is
-- loaded, else in this session's memory (a public event this client only shows).

local L = ns.L
local F = ArenaFights
local Arena = ns.Arena

F.CALL_WINDOW = 300     -- seconds to reach the ring once called
F.WO_AUTO = 120         -- after the deadline, a walkover the arbiter did not give applies by itself
F.WO_EXTEND = 300       -- the arbiter may extend the deadline once, by this much
F.RING_RANGE = 60       -- yards: a fighter's reported position this close to the arbiter's is at the ring
F.HERE_EVERY = 20       -- "I'm here" again every this many seconds until the bell...
F.HERE_MAX = 15         -- ...this many times at most
F.HERE_LAPSE = 45       -- a position older than this no longer counts
F.RESULT_WAIT = 15      -- the arbiter waits this long for reports before a result is held
F.WITNESS_WAIT = 10     -- a witness waits a random 0 to this many seconds before it reports
F.WITNESSES_MAX = 20    -- witnesses counted per round
F.REPORT_LATE = 60      -- a report is taken up to this long after its round
F.GRACE = 120           -- the grace for corrections...
F.GRACE_HELD = 300      -- ...with markets open or stakes held (the design)
F.FINAL_SLACK = 30      -- other clients turn a result final this long after its grace
F.DIRECT_WAIT = 600     -- a direct fight with one side's report missing this long is disputed
F.REPEAT_NEAR = 60      -- AF again every minute for a live bout and the next one...
F.REPEAT_FAR = 600      -- ...every 10 minutes otherwise
F.REPEAT_AFTER = 3600   -- ...and for an hour after it ended
F.CARD_LIVE = 120       -- AN again every 2 minutes while live...
F.CARD_PLANNED = 900    -- ...15 minutes while planned
F.BOUTS_MAX = 12
F.TITLE_MAX = 40        -- bytes of a card's title
F.AHEAD = 60            -- a time further ahead of the server's clock is refused
F.SIGN_GAP = 3          -- AS at most every 3 s per sender
F.CHALLENGE_GAP = 60    -- no new challenge from a player for 60 s after a no
F.CALL_GAP = 20         -- a fight called again within 20 s raises no new alert
F.NO_SHOW_DAYS = 30
F.NO_SHOWS_BLOCK = 2
F.KEEP = 300            -- fights kept in a store
F.MEM_KEEP = 60         -- fights kept in memory (not involved, companion not loaded)
F.CARDS_KEEP = 20
F.MARKET_RETRY = 30     -- a bank may come online after the announcement; retry without marking it open
F.MAX_LEVEL = 60
F.CODES = { dc = true, off = true, help = true, char = true, flee = true, late = true, early = true, absent = true,
	lvl = true, arb = true, int = true, cancel = true, held = true, disputed = true, refused = true }

local STATES = { A = true, O = true, S = true, C = true, Y = true, Z = true, L = true, B = true, R = true, F = true,
	V = true, N = true, W = true }
local ENDED = { F = true, V = true, N = true, W = true }
local LIVE = { C = true, Y = true, Z = true, L = true, B = true }
local METHODS = { K = true, R = true, D = true, W = true, N = true, V = true }

local stats = { refused = {}, dropped = {}, secret = 0, lines = 0 }
local function Count(t, why) t[why] = (t[why] or 0) + 1 end
function F.Stats() return stats end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local B36, N = Arena.B36, Arena.N
local function Now() return Arena.Now() end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b) local x = Lower(a) return x ~= nil and x == Lower(b) end
local function Me(name) return Same(name, ns.me) end
local function Has(fl, c) return type(fl) == "string" and fl:find(c, 1, true) ~= nil end
local function AddFlag(f, c) if not Has(f.fl, c) then f.fl = (f.fl or "") .. c end end
local function DropFlag(f, c) f.fl = (f.fl or ""):gsub(c, "") end
local function Other(side) return side == "A" and "B" or "A" end
F.Same, F.Has = Same, Has

-- A name as a body carries it: short on the sender's realm, else with its realm.
local function Wire(name)
	if type(name) ~= "string" or name == "" then return "-" end
	local full = ns.FullName(name)
	if (ns.RealmOf(full) or ns.realm) == ns.realm then return ns.ShortName(full) end
	return full
end
-- ...and back: a name through King.CleanName (Arena.Name), on the sender's realm when it gives none.
local function Unwire(s, sender)
	if type(s) ~= "string" or s == "" or s == "-" then return nil end
	if not s:find("-", 1, true) then s = s .. "-" .. Arena.RealmOf(sender or ns.me) end
	return Arena.Name(s)
end
F.Wire, F.Unwire = Wire, Unwire

local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end
local function MyGk()
	local g = UnitGUID and UnitGUID("player")
	if issecretvalue and issecretvalue(g) then return nil end
	return Arena.GK(g)
end
F.MyGk = MyGk

-- A time a body carries (base 36, server time), refused past AHEAD; 0 is none.
local function Time(s)
	local t = N(s, 0, 4294967295)
	if not t then return nil end
	if t > Now() + F.AHEAD then return nil end
	return t
end

local function Say(key, ...)
	local s = L[key]
	if select("#", ...) > 0 then s = s:format(...) end
	ns.Print(s)
end

-- Another package's function, when that package is built (a stub has none): nil otherwise.
local function Hook(module, fn)
	local m = ns[module]
	if type(m) ~= "table" or m.missing then return nil end
	local f = m[fn]
	return type(f) == "function" and f or nil
end
F.Hook = Hook
-- The compliance gate (Compliance.lua): a stake, the markets on a fight and their payouts only where
-- it allows them (1.1.6: nowhere; a fight without a stake, rated, for a belt or in a tournament,
-- always goes on).
local function Wagers(kind)
	local allows = Hook("Compliance", "Allows")
	return allows ~= nil and allows(kind, "fight") == true
end
F.Wagers = Wagers
-- Arbiters only where a wager may happen (Compliance.Arbiters; 1.1.6: none, so a challenge is
-- always direct and no ask to judge is taken).
local function Arbiters()
	local on = Hook("Compliance", "Arbiters")
	return on ~= nil and on() == true
end
F.Arbiters = Arbiters

-- The challenges this session holds (AS, below), declared here: an AF of a direct fight is taken
-- only against the challenge it answers.
local chal = {} -- [oid] = { oid, A, B, bo, stake, how "d"|"a", arbiter, cur, from, state, t, fid, mode, incoming, salt, iou, myIou, token }
F.challenges = chal

-- the money part's money functions a staked challenge needs (the full contract of its 1.2 branch), looked up
-- at call time: all of them, or nil (a stake is then refused: the money side is not there).
local MONEY_DIRECT = { { "Debts", "Iou" }, { "Debts", "ReadIou" }, { "Debts", "CheckIou" }, { "Debts", "KeyOf" }, { "Debts", "Verified" },
	{ "Debts", "Commit" }, { "Debts", "SignResult" }, { "Standing", "TokenWire" }, { "Standing", "CheckWire" }, { "Standing", "Cap" },
	{ "Stakes", "Direct" } }
local MONEY_HELD = { { "Standing", "Cap" }, { "Stakes", "Open" }, { "Stakes", "Result" } }
local function Money(list)
	local out = {}
	for _, x in ipairs(list) do
		local fn = Hook(x[1], x[2])
		if not fn then return nil, x[1] .. "." .. x[2] end
		out[x[2]] = fn
	end
	return out
end
F.Money = function(how) return Money(how == "a" and MONEY_HELD or MONEY_DIRECT) end

---------------------------------------------------------------------------
-- Stores
---------------------------------------------------------------------------

local mem = { L = { fights = {}, cards = {}, n = 0 }, T = { fights = {}, cards = {}, n = 0 } }
local function Mem(mode) return mem[mode == "T" and "T" or "L"] end
-- The core store's table of a kind; made only when `make` (a read never writes saved data, nor
-- opens the rehearsal store).
local function Core(mode, kind, make)
	if mode == "T" and not make and not Arena.Sim() and not (type(ns.rdb) == "table" and type(ns.rdb.arenaTest) == "table") then return nil end
	local s = Arena.Store(mode)
	if not s then return nil end
	if type(s[kind]) ~= "table" then
		if not make then return nil end
		s[kind] = {}
	end
	return s[kind]
end
F.Core = Core
local function HeavyOf(mode, kind)
	local s = Arena.Heavy(mode)
	if not s then return nil end
	if type(s[kind]) ~= "table" then s[kind] = {} end
	return s[kind]
end

-- A record of `kind` ("fights", "cards") by id, in either mode: the record and its mode.
local function Find(kind, id)
	if type(id) ~= "string" then return nil end
	for _, mode in ipairs({ "L", "T" }) do
		-- (Three places, any of them missing: never ipairs over them, which stops at the first nil.)
		local places = { Core(mode, kind), HeavyOf(mode, kind), Mem(mode)[kind] }
		for i = 1, 3 do
			local r = places[i] and places[i][id]
			if type(r) == "table" then return r, mode end
		end
	end
	return nil
end
F.Find = Find

-- Every record of a kind this client holds (both modes, each once).
local function All(kind)
	local out, seen = {}, {}
	for _, mode in ipairs({ "L", "T" }) do
		local places = { Core(mode, kind) or {}, HeavyOf(mode, kind) or {}, Mem(mode)[kind] }
		for i = 1, 3 do
			for id, r in pairs(places[i]) do
				if type(r) == "table" and not seen[id] then seen[id] = true out[#out + 1] = r end
			end
		end
	end
	return out
end
F.All = All

-- Whether this client is part of a fight: a fighter, its arbiter, its writer, or its card's promoter.
local function Involved(f)
	if type(f) ~= "table" then return false end
	if Me(f.writer) or Me(f.arb) or Me(f.A and f.A.name) or Me(f.B and f.B.name) then return true end
	if f.card then
		local c = Find("cards", f.card)
		if c and Me(c.promoter) then return true end
	end
	if f.tid then
		local T = ns.ArenaTourney
		local t = type(T) == "table" and type(T.Find) == "function" and T.Find(f.tid)
		if t and Me(t.promoter) then return true end
	end
	return false
end
F.Involved = Involved

-- Kept where it belongs (core while involved, else heavy or memory), in one place only.
local function Prune(t, keep)
	local n, list = 0, {}
	for id, r in pairs(t) do
		n = n + 1
		if type(r) == "table" and ENDED[r.st] then list[#list + 1] = { id = id, t = r.heardAt or 0 } end
	end
	if n <= keep then return end
	table.sort(list, function(a, b) return a.t < b.t end)
	for i = 1, math.min(#list, n - keep) do t[list[i].id] = nil end
end
local function Put(kind, r)
	local mode = r.mode == "T" and "T" or "L"
	local id = r.fid or r.cid
	local mine = (kind == "fights" and Involved(r)) or (kind == "cards" and Me(r.promoter))
	-- (The core's table is made only for what is ours: an idle client's saved data stays as it was.)
	local core, heavy, memory = Core(mode, kind, mine), HeavyOf(mode, kind), Mem(mode)[kind]
	local home
	local keep = kind == "cards" and F.CARDS_KEEP or F.KEEP
	if mine then home = core
	elseif heavy then home = heavy
	else home = memory; keep = kind == "cards" and F.CARDS_KEEP or F.MEM_KEEP end
	home = home or memory
	local places = { core, heavy, memory }
	for i = 1, 3 do
		if places[i] and places[i] ~= home then places[i][id] = nil end
	end
	home[id] = r
	Prune(home, keep)
end
F.Put = Put

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- A fight's state as this client sees it now: a result past its grace (and slack) is final here
-- too, whatever its writer's word says (the design).
local function State(f)
	if f.st == "R" and f.graceEnd and Now() >= f.graceEnd + F.FINAL_SLACK and not Me(f.writer) then return "F" end
	return f.st
end
F.State = State

function F.Fight(fid)
	local f = Find("fights", fid)
	return f
end

-- filter: { mode, st (a set or a letter), public, mine, card, tid, name } (all optional).
function F.List(filter)
	filter = filter or {}
	local out = {}
	for _, f in ipairs(All("fights")) do
		local st = State(f)
		local ok = (not filter.mode or f.mode == filter.mode)
			and (not filter.st or (type(filter.st) == "table" and filter.st[st]) or filter.st == st)
			and (filter.public == nil or Has(f.fl, "p") == filter.public)
			and (not filter.mine or Involved(f))
			and (not filter.card or f.card == filter.card)
			and (not filter.tid or f.tid == filter.tid)
			and (not filter.name or F.IsFighter(f.fid, filter.name))
		if ok then out[#out + 1] = f end
	end
	table.sort(out, function(a, b)
		local ta, tb = a.lockAt or a.tCall or a.tAnn or 0, b.lockAt or b.tCall or b.tAnn or 0
		if ta ~= tb then return ta > tb end
		return a.fid < b.fid
	end)
	return out
end

-- The same player: the name, or a linked alt of it (Alts.Person, the design).
local function Person(name)
	local A = ns.Alts
	if type(A) == "table" and not A.missing and type(A.Person) == "function" then
		local ok, p = pcall(A.Person, name)
		if ok and type(p) == "string" then return p:lower() end
	end
	return ns.ShortName(ns.FullName(name)):lower()
end
F.Person = Person
local function SamePerson(a, b) return type(a) == "string" and type(b) == "string" and (Same(a, b) or Person(a) == Person(b)) end
F.SamePerson = SamePerson

-- Is `name` (or a linked alt of his) one of the fight's fighters? "A", "B" or false.
function F.IsFighter(fid, name)
	local f = type(fid) == "table" and fid or Find("fights", fid)
	if not f or type(name) ~= "string" then return false end
	if f.A and SamePerson(f.A.name, name) then return "A" end
	if f.B and SamePerson(f.B.name, name) then return "B" end
	return false
end
local function SideOf(f, name)
	if f.A and Same(f.A.name, name) then return "A" end
	if f.B and Same(f.B.name, name) then return "B" end
	return nil
end
F.SideOf = SideOf

---------------------------------------------------------------------------
-- The wire: AF
---------------------------------------------------------------------------

local function Score(f) return (f.sc and f.sc[1] or 0) .. ":" .. (f.sc and f.sc[2] or 0) end
-- (The card field names a bout's card, or its tournament: "N..." or "T...", whose promoter may
-- write it as a card's does.)
local function Encode(f)
	return table.concat({ f.fid, f.st, f.fl ~= "" and f.fl or "-", tostring(f.bo or 1), f.cat or "A", f.arb and Wire(f.arb) or "-",
		f.card or f.tid or "-", Wire(f.A and f.A.name), f.A and f.A.gk or "-", f.B and Wire(f.B.name) or "-", f.B and f.B.gk or "-",
		B36(f.tAnn), B36(f.tCall), B36(f.lockAt), B36(f.round), Score(f), f.w or "-", f.m or "-", B36(f.dur) }, "~")
end
F.Encode = Encode

-- Where a fight's messages go: public on its lane; private to its fighters (and the arbiter for
-- what a fighter sends); direct to the opponent.
local function Recipients(f)
	local out = {}
	for _, side in ipairs({ "A", "B" }) do
		local s = f[side]
		if s and s.name and not Me(s.name) then out[#out + 1] = s.name end
	end
	if f.arb and not Me(f.arb) then out[#out + 1] = f.arb end
	return out
end

local function SendAF(f, urgent)
	if f.st == "D" then return end
	local body = Encode(f)
	f.sentAt = Now()
	if Has(f.fl, "p") then
		Arena.Send("AF", f.mode, body, { key = "af " .. f.fid, urgent = urgent })
	else
		for _, to in ipairs(Recipients(f)) do Arena.Send("AF", f.mode, body, { to = to, key = "af " .. f.fid, urgent = urgent }) end
	end
end
F.SendAF = SendAF

local Changed -- (below)

-- The writer's hash in an id (Arena.NewId): the fid's last two characters are its creator's.
local function MadeBy(fid, name) return type(fid) == "string" and fid:sub(-2) == Arena.Hash36(ns.FullName(name):lower(), 2) end
F.MadeBy = MadeBy

local function CardPromoter(cid)
	local c = cid and Find("cards", cid)
	return c and c.promoter or nil
end
-- A tournament's promoter (the tid a bout's AF carries in its card field), when known here.
local function TourneyPromoter(tid)
	local T = ns.ArenaTourney
	local t = tid and type(T) == "table" and type(T.Find) == "function" and T.Find(tid)
	return t and t.promoter or nil
end
-- The promoter of a fight's card or tournament (who may write its bout, correct it, void it).
local function Promoter(f)
	if type(f) ~= "table" then return nil end
	return CardPromoter(f.card) or TourneyPromoter(f.tid)
end
F.Promoter = Promoter

local OnFight -- the AF handler (below)
local MatchFromChallenge -- assigned once the challenge table exists (below)
local MarketSpecs, OpenMarkets -- a public fight's own sheet (below)
local function Refuse(why) Count(stats.refused, why) return false, why end

-- An AF heard from `sender`: taken, or false and why (the design).
function F.Take(dist, sender, mode, body)
	local fid, st, fl, bo, cat, arb, card, a, gkA, b, gkB, tAnn, tCall, lockAt, round, sc, w, m, dur = Arena.Fields(body, 19)
	if not dur then return Refuse("shape") end
	if not fid:find("^F[0-9a-z]+$") or #fid > 20 then return Refuse("fid") end
	if not STATES[st] then return Refuse("state") end
	fl = fl == "-" and "" or fl
	if not fl:find("^[ptmokdcsrbx]*$") then return Refuse("flags") end
	bo = tonumber(bo)
	if bo ~= 1 and bo ~= 3 and bo ~= 5 then return Refuse("bo") end
	if not cat:find("^[ACRB][%w]*$") or #cat > 4 then return Refuse("cat") end
	arb = Unwire(arb, sender)
	card = card ~= "-" and card or nil
	local tid
	if card and card:find("^T[0-9a-z]+$") and #card <= 20 then
		tid, card = card, nil
	elseif card and (not card:find("^N[0-9a-z]+$") or #card > 20) then
		return Refuse("card")
	end
	local A = { name = Unwire(a, sender), gk = Gk(gkA) }
	local Bn = Unwire(b, sender)
	local B = Bn and { name = Bn, gk = Gk(gkB) } or nil
	if not A.name then return Refuse("fighter") end
	tAnn, tCall, lockAt, round = Time(tAnn), Time(tCall), N(lockAt, 0, 4294967295), N(round, 0, 9)
	if not (tAnn and tCall and lockAt and round) then return Refuse("time") end
	if lockAt > Now() + 3600 then return Refuse("time") end
	local sa, sb = sc:match("^(%d):(%d)$")
	if not sa then return Refuse("score") end
	w = (w == "A" or w == "B") and w or nil
	m = METHODS[m] and m or nil
	dur = N(dur, 0, 86400)
	local direct = Has(fl, "d")
	-- Who may write it: its arbiter, the promoter of its card or tournament for his bout, or
	-- (direct) its challenger.
	local promoter = CardPromoter(card) or TourneyPromoter(tid)
	if direct then
		if arb then return Refuse("direct-arbiter") end
		if not (Same(sender, A.name) or (B and Same(sender, B.name))) then return Refuse("writer") end
		if dist ~= "WHISPER" then return Refuse("lane") end
	else
		if not arb then return Refuse("arbiter") end
		if not (Same(sender, arb) or (promoter and Same(sender, promoter))) then return Refuse("writer") end
		local R = ns.ArenaRoles
		if Has(fl, "p") then
			if not R.IsPublicArbiter(arb, mode) then return Refuse("public") end
		elseif not R.IsArbiter(arb, mode) then
			return Refuse("arbiter")
		end
		if SamePerson(arb, A.name) or (B and SamePerson(arb, B.name)) then return Refuse("arbiter-fighter") end
		if not Has(fl, "p") and dist ~= "WHISPER" then return Refuse("lane") end
	end
	if not (MadeBy(fid, sender) or (promoter and MadeBy(fid, promoter))) then return Refuse("hash") end
	local f = Find("fights", fid)
	if direct then return F.TakeDirect(f, sender, mode, fid, st, fl, bo, cat, A, B, w) end
	if f then
		-- The first AF fixes the writer; later ones only from him, the arbiter he named (a card's
		-- bout, whose arbiter takes it over), or the card's promoter.
		if Has(f.fl, "d") then return Refuse("direct") end
		if not (Same(sender, f.writer) or (f.arb and Same(sender, f.arb)) or (promoter and Same(sender, promoter))) then
			return Refuse("not-writer")
		end
		if f.mode ~= mode then return Refuse("mode") end
		f.writer = ns.FullName(sender)
	else
		f = { fid = fid, mode = mode, writer = ns.FullName(sender), rounds = {}, facts = {}, accepted = {} }
	end
	local was = f.st
	f.st, f.fl, f.bo, f.cat, f.arb, f.card, f.tid = st, fl, bo, cat, arb, card, tid or f.tid
	f.A = { name = A.name, gk = A.gk or (f.A and f.A.gk) }
	f.B = B and { name = B.name, gk = B.gk or (f.B and f.B.gk) } or nil
	f.tAnn, f.tCall = tAnn > 0 and tAnn or nil, tCall > 0 and tCall or nil
	f.lockAt = lockAt > 0 and lockAt or nil
	f.round, f.sc, f.w, f.m, f.dur = round, { tonumber(sa), tonumber(sb) }, w, m, dur
	f.heardAt = Now()
	f.promoter = promoter
	if not f.from and MatchFromChallenge then f.from = MatchFromChallenge(f) end
	-- A bout its promoter (a card's, a tournament's) gave us to judge: we write it from now on, and
	-- say so (every copy's writer is then its arbiter); its public markets are ours to open (the
	-- winner's: the sheet's opener is the writer who rings, settles and voids it, OpenMarkets), none
	-- when its promoter kept it out of betting (x).
	local takeover = arb and Me(arb) and not direct and not Me(f.writer)
	if arb and Me(arb) and not direct then f.writer = ns.me end
	if takeover and f.marketSpecs == nil then f.marketSpecs = MarketSpecs(Has(fl, "p") and not Has(fl, "x"), nil) end
	Put("fights", f)
	if takeover and f.st ~= "D" then
		SendAF(f, true)
		if f.B and f.marketSpecs and not Has(f.fl, "m") and OpenMarkets(f) then SendAF(f, true) end
	end
	-- A fighter of a fight whose stakes its arbiter holds: his side of the book (the money part).
	if Has(fl, "s") and SideOf(f, ns.me) then F.OpenPartyStake(f) end
	if was ~= st then Changed(f, was) end
	return true
end

-- A direct fight's AF (the challenger's, whispered to the opponent). New: only the challenge this
-- client agreed to (AS~Y yes), from its challenger, with its fighters and format, set; the stake,
-- the IOUs, the salt and the match id (Vet's) come from our own challenge record, never from the
-- wire. Known: each side decides its own result from its own duel line and the other's
-- (DirectCheck), so a result (R, F, N) is never taken from the wire; only a void before any round
-- was decided, and a walkover that gives us the win (the writer conceding).
function F.TakeDirect(f, sender, mode, fid, st, fl, bo, cat, A, B, w)
	if f then
		if not Has(f.fl, "d") then return Refuse("direct") end
		if f.mode ~= mode then return Refuse("mode") end
		if not Same(sender, f.writer) then return Refuse("not-writer") end
		f.heardAt = Now()
		if ENDED[f.st] or st == f.st or st == "S" or st == "A" or st == "L" or st == "B" then return true end
		local mine = SideOf(f, ns.me)
		local decided = ((f.sc and f.sc[1]) or 0) + ((f.sc and f.sc[2]) or 0) > 0
		local was = f.st
		if st == "V" and not decided then
			f.st, f.code, f.graceEnd = "V", f.code or "cancel", f.graceEnd or Now()
		elseif st == "W" and mine and w == mine then
			f.st, f.w, f.m, f.graceEnd = "W", w, "W", f.graceEnd or Now()
			if f.round == 0 then f.round = 1 end
		else
			return Refuse("direct-state")
		end
		Put("fights", f)
		Changed(f, was)
		return true
	end
	local c = chal[fid]
	if not (c and c.incoming and not c.judge and Same(sender, c.A) and (c.state == "yes" or c.state == "set")) then return Refuse("challenge") end
	if not (Same(A.name, c.A) and B and Same(B.name, ns.me)) or bo ~= c.bo then return Refuse("challenge") end
	if mode ~= c.mode then return Refuse("mode") end
	if st ~= "S" and st ~= "A" then return Refuse("direct-state") end
	f = { fid = fid, mode = mode, writer = ns.FullName(sender), st = st, fl = fl, bo = bo, cat = cat, A = { name = A.name, gk = A.gk },
		B = { name = B.name, gk = MyGk() or B.gk }, round = 0, sc = { 0, 0 }, rounds = {}, facts = {}, accepted = { A = true, B = true },
		tAnn = Now(), heardAt = Now(), from = c.from }
	if (c.stake or 0) > 0 then
		f.stake, f.salt = c.stake, c.salt
		f.ious = { A = c.iou, B = c.myIou }
		local verified = Hook("Debts", "Verified")
		if verified then
			local ok, gk = pcall(verified, c.A)
			if ok and type(gk) == "string" then f.A.gk = gk end
		end
	end
	c.state, c.fid = "set", fid
	Put("fights", f)
	Changed(f, nil)
	return true
end

---------------------------------------------------------------------------
-- Events, involvement, the ticker
---------------------------------------------------------------------------

local ticking = false
local Tick -- (below)
local function Watch()
	local any = false
	for _, f in ipairs(All("fights")) do
		local key = "fight:" .. f.fid
		local on = Involved(f) and not (ENDED[f.st] and Now() - (f.endedAt or 0) > F.REPEAT_AFTER)
		Arena.Involve(key, on or nil)
		if on then any = true end
	end
	for _, c in ipairs(All("cards")) do
		local on = Me(c.promoter) and c.st ~= "D" and c.st ~= "X"
		Arena.Involve("card:" .. c.cid, on or nil)
		if on then any = true end
	end
	if any ~= ticking then
		ticking = any
		Arena.Every(1, "fights", any and function() Tick() end or nil)
	end
end
F.Watch = Watch

local systemHooked = false
local OnSystem -- (below)
local Qualify -- paired local native finish and bilateral result (below)
local nativeFinish
-- The duel lines, on first involvement with a fight that can have one (the design).
local function HookSystem()
	if systemHooked then return end
	systemHooked = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("arena duel line", OnSystem, text) end)
	-- Classic's DuelInfoDocumentation.lua declares this local event without a payload.
	-- A client that cannot register it supplies no participation proof and earns no qualifier.
	pcall(ns.RegisterEvent, "DUEL_FINISHED", function()
		nativeFinish = Now()
		for _, f in ipairs(All("fights")) do if Qualify then Qualify(f, f.round) end end
	end)
end

Changed = function(f, was)
	local st = State(f)
	if ENDED[st] and not f.endedAt then f.endedAt = Now() end
	if LIVE[st] or st == "S" then HookSystem() end
	ns.Fire("ARENA_FIGHT", f.fid, st)
	if st == "L" and was ~= "L" and was ~= "B" then ns.Fire("ARENA_LOCK", f.fid, f.lockAt) end
	if st == "Z" and was ~= "Z" then ns.Fire("ARENA_LAST_CALL", f.fid, f.lockAt) end
	if st == "F" and was ~= "F" then
		ns.Fire("ARENA_RESULT", f.fid, F.Record(f))
		F.Ended(f)
	elseif (st == "V" or st == "N" or st == "W") and was ~= st then
		ns.Fire("ARENA_VOID", f.fid, f.code or st)
		F.Ended(f)
	end
	Watch()
	Arena.Changed()
end
F.Changed = Changed

-- What a final fight is, for ARENA_RESULT and the fighters' own history.
function F.Record(f)
	return { fid = f.fid, mode = f.mode, cat = f.cat, bo = f.bo, A = f.A, B = f.B, w = f.w, m = f.m, sc = f.sc, dur = f.dur,
		rounds = f.rounds, lockAt = f.lockAt, arb = f.arb, fl = f.fl, t = f.graceEnd or Now(), public = Has(f.fl, "p") }
end

-- A fight over: the fighter's own history (the design's mine, the design myFights: direct and unrated
-- too), matchmaking's end, the stakes and the markets on the writer's client.
local FinishMarket -- assigned after F.Results, below
function F.Ended(f)
	if f.endedDone then return end
	f.endedDone = true
	local side = SideOf(f, ns.me)
	if side and Arena.Counts(f.mode) then
		local store = Arena.Store(f.mode)
		store.myFights = type(store.myFights) == "table" and store.myFights or {}
		local mine = store.myFights[ns.me] or {}
		store.myFights[ns.me] = mine
		local opp = f[Other(side)]
		local dup = false
		for _, e in ipairs(mine) do if e.fid == f.fid then dup = true end end
		if not dup then
			-- (Enough to list it in the fighter's own history, LG.History, once the record itself is gone.
			-- Only a final result or a walkover has a winner: a void or no contest after a decided round
			-- keeps that round's winner on the record, never in the history.)
			local st = State(f)
			local won = (st == "F" or st == "W") and f.w or nil
			mine[#mine + 1] = { fid = f.fid, t = f.graceEnd or Now(), opp = opp and opp.name, oppGk = opp and opp.gk, side = side,
				w = won == side and "W" or (won and "L" or "-"), m = won and f.m or st, sc = Score(f), cat = f.cat, dur = f.dur,
				rated = Has(f.fl, "r"), direct = Has(f.fl, "d"), public = Has(f.fl, "p"), title = Has(f.fl, "t") }
			while #mine > 200 do table.remove(mine, 1) end
		end
	end
	-- The games' ledger (1.1.6, ArenaLedger.Played): every fight that ended, rated or not, either
	-- mode, from each fighter's client and its arbiter's.
	if side or Me(f.arb) then F.ToLedger(f) end
	-- Matchmaking's end of the match this fight came from (the design), once: its id is
	-- the challenge's, on either fighter's client (MatchFromChallenge, AttachMatch).
	local ended = Hook("ArenaMatch", "Ended")
	if ended and f.from and not f.matchEnded then
		f.matchEnded = true
		ns.SafeCall("arena match ended", ended, f.from)
	end
	if Me(f.writer) then
		local st = State(f)
		-- The money is the mode's: a rehearsal's (T) stakes are the rehearsal's (the money part's Mode()).
		if Has(f.fl, "s") then
			local result = Hook("Stakes", "Result")
			if result then ns.SafeCall("arena stakes result", result, f.fid, st == "F" and f.w or "V", f.mode) end
		end
		if Has(f.fl, "m") and FinishMarket then FinishMarket(f) end
	end
	-- A staked direct fight settles on BOTH fighters' clients (the design, the money part's Stakes.Direct): the
	-- loser's own debt on his, the winner's credit and its proof on his: the loser's IOU (from his
	-- AS) and his signed result for the deciding round (from his AW).
	if Has(f.fl, "d") and f.stake and State(f) == "F" and side and f.w then
		local direct = Hook("Stakes", "Direct")
		if direct then
			local loser = Other(f.w)
			local commit, isig = F.IouParts(f.ious and f.ious[loser])
			local rsig = f.sigs and f.sigs[f.round] and f.sigs[f.round][loser]
			ns.SafeCall("arena direct stakes", direct, { id = f.fid, loser = f[loser].name, winner = f[f.w].name, copper = f.stake, mode = f.mode,
				iou = commit and { commit = commit, sig = isig } or nil, result = rsig and { fid = f.fid, round = f.round, sig = rsig } or nil })
		end
	end
end

-- A fight that ended, as the games' ledger takes it (ArenaLedger.Played): a tournament's bout (t),
-- a Fight Night's (n) or a duel (d); the winner's side (1 is A) or v (a void, a no contest); the
-- rounds won; how (the method, or the state that ended it); cat.bo[.tid]. What every participant
-- says alike; the time and the length are the record's.
function F.LedgerRecord(f)
	if type(f) ~= "table" or type(f.fid) ~= "string" or not (f.A and f.A.name and f.B and f.B.name) then return nil end
	local st = State(f)
	local won = (st == "F" or st == "W") and (f.w == "A" or f.w == "B") and f.w or nil
	local g = (f.tid or Has(f.fl, "k")) and "t" or ((f.card or Has(f.fl, "c")) and "n" or "d")
	local sc = type(f.sc) == "table" and f.sc or {}
	local x = tostring(f.cat or "A") .. "." .. tostring(f.bo or 1) .. (f.tid and ("." .. tostring(f.tid)) or "")
	return { id = f.fid, g = g, t = f.graceEnd or f.endedAt or Now(), dur = f.dur or 0, p1 = f.A.name, p2 = f.B.name, arb = f.arb,
		w = won and (won == "A" and "1" or "2") or "v", s1 = sc[1], s2 = sc[2], how = won and (f.m or st) or st,
		x = (x:gsub("[^%w%.%-]", "")) }
end
function F.ToLedger(f)
	if f.ledgered then return end
	local played = Hook("ArenaLedger", "Played")
	local rec = played and F.LedgerRecord(f)
	if not rec then return end
	f.ledgered = true
	ns.SafeCall("arena games ledger", played, f.mode, rec)
end

-- This character's own fights (the design myFights: direct, private and unrated ones too), oldest
-- first: { fid, t, opp, oppGk, side, w ("W"|"L"|"-"), m, sc, cat, dur, rated, direct, public,
-- title }. Read only (a rehearsal's store is never made here).
function F.MyFights(mode)
	local all = Core(mode or "L", "myFights")
	local list = type(all) == "table" and all[ns.me]
	return type(list) == "table" and list or {}
end

-- An IOU as the AS carries it (the money part's Debts.Iou(...).wire, "<commit>.<sig>"): its two parts.
function F.IouParts(wire)
	if type(wire) ~= "string" then return nil end
	local commit, sig = wire:match("^([^.~]+)%.([^~]+)$")
	return commit, sig
end

-- What the markets settle on (the design): the winner, the method, the score, each round's time.
function F.Results(f)
	local rounds, details = {}, {}
	for r = 1, f.round or 0 do
		local x = f.rounds[r]
		if x and (x.w == "A" or x.w == "B") then
			rounds[#rounds + 1] = x.w
			details[r] = { w = x.w, m = x.m, dur = x.dur }
		end
	end
	return { winner = f.w, method = f.m, sc = Score(f), dur = f.dur, rounds = table.concat(rounds), roundDetails = details,
		src = f.src, lockAt = f.lockAt, final = ENDED[State(f)] == true, against = f.corrected == true or f.code == "disputed" }
end

-- A fight's words are more detailed than the sheet's one-letter void codes. Keep the financial
-- result conservative: nothing pays when the bout did not yield a final winner.
local function MarketVoidCode(f, st)
	if st == "W" then return "W" end
	if f.code == "early" then return "E" end
	if f.code == "help" or f.code == "int" then return "I" end
	if f.code == "held" or f.code == "disputed" then return "N" end
	if f.code == "absent" or f.code == "dc" or f.code == "off" or f.code == "late" then return "W" end
	return st == "N" and "N" or "X"
end

-- Settlement is retried by the fight ticker after a reload or a transient refusal. `marketDone`
-- is written only after the canonical Markets sheet accepted the declaration/void.
FinishMarket = function(f)
	if f.marketDone then return true end
	local M = ns.Markets
	if type(M) ~= "table" or type(M.Sheet) ~= "function" or not M.Sheet(f.fid, f.mode) then
		f.marketWhy = "sheet"
		return false, f.marketWhy
	end
	local st = State(f)
	local fn, a, b
	if st == "F" then
		fn, a = M.Declare, F.Results(f)
	else
		fn, a, b = M.Void, "*", MarketVoidCode(f, st)
	end
	if type(fn) ~= "function" then f.marketWhy = "markets" return false, f.marketWhy end
	local called, ok, why = pcall(fn, f.fid, a, b)
	if called and (ok == true or (st ~= "F" and why == "none")) then
		f.marketDone, f.marketWhy = true, nil
		return true
	end
	f.marketWhy = called and (why or "markets") or "markets"
	return false, f.marketWhy
end

-- Public hosted fights open a winner market by default. An explicit list may add only market
-- kinds which Markets itself accepts; private/direct stakes continue through Stakes and never
-- share this public sheet. An open slot keeps the request until its second fighter is booked.
MarketSpecs = function(public, requested)
	if not public or requested == false then return nil end
	-- (No market on a fight while the compliance gate allows no bet: the fight goes on without one.)
	if not Wagers("bet") then return nil end
	if requested == nil then return { { type = "MW" } } end
	if type(requested) ~= "table" or #requested == 0 then return nil, "markets" end
	local out = {}
	for i, spec in ipairs(requested) do
		if type(spec) ~= "table" then return nil, "markets" end
		out[i] = {}
		for k, v in pairs(spec) do out[i][k] = v end
	end
	return out
end

-- On the writer's client. A bout made for another arbiter (a card's or a tournament's, which he
-- takes over) waits for him: the sheet's opener must be the one who later closes, declares and
-- voids it (Markets.CloseBets/Declare/Void are the opener's own).
OpenMarkets = function(f)
	if not (Has(f.fl, "p") and f.B and type(f.marketSpecs) == "table") then return false, "not-ready" end
	if f.arb and not Me(f.arb) then return false, "arbiter" end
	-- (Voided before the bell, "early": its sheet stays voided, never opened again.)
	if f.marketsOff then return false, "void" end
	f.marketTryAt = Now()
	local M = ns.Markets
	if type(M) ~= "table" or type(M.Open) ~= "function" then f.marketWhy = "markets" return false, f.marketWhy end
	if type(M.Has) == "function" and M.Has(f.fid) then
		AddFlag(f, "m")
		f.marketWhy = nil
		return true
	end
	local called, ok, why = pcall(M.Open, f.fid, { markets = f.marketSpecs, mode = f.mode })
	if called and ok == true then
		AddFlag(f, "m")
		f.marketWhy = nil
		return true
	end
	f.marketWhy = called and (why or "markets") or "markets"
	return false, f.marketWhy
end

---------------------------------------------------------------------------
-- Making a fight (the writer's side)
---------------------------------------------------------------------------

local function Grace(f) return (Has(f.fl, "m") or Has(f.fl, "s")) and F.GRACE_HELD or F.GRACE end
F.GraceOf = Grace

-- opts: { A = name, B = name (nil: an open slot), arb = name (default: me, when I may judge; none:
--   direct), direct = true (no arbiter: I am a fighter), bo = 1|3|5, cat = "A"|"C<xx>"|"R<n>",
--   card = cid, tid, slot, public = bool (a public arbiter's own choice; default: public when he is
--   one and no stakes), title = bool, rehearsal = bool, stake = copper, stakes = bool (held by the
--   arbiter), markets = false | { market specs } (default: winner; a bout made for another
--   arbiter, who opens its sheet when he takes it over, gets the winner's or none: false, flag x),
--   from = a match id, fid = an id already made by me }
-- Returns the fid (a draft: Announce sends it), or nil and why.
function F.New(opts)
	opts = opts or {}
	local R = ns.ArenaRoles
	local A = Arena.Name(opts.A or "")
	if not A then return nil, "fighter" end
	local B = opts.B and Arena.Name(opts.B) or nil
	if B and SamePerson(A, B) then return nil, "same" end
	local mode = Arena.NewMode(opts.rehearsal)
	local direct = opts.direct == true
	local arb = not direct and Arena.Name(opts.arb or ns.me) or nil
	local promoter = (opts.card and CardPromoter(opts.card)) or (opts.tid and TourneyPromoter(opts.tid)) or nil
	if direct then
		if not (Me(A) or (B and Me(B))) then return nil, "writer" end
		if not B then return nil, "opponent" end
	else
		if not arb then return nil, "arbiter" end
		if not (Me(arb) or (promoter and Me(promoter))) then return nil, "writer" end
		if not R.IsArbiter(arb, mode) then return nil, "arbiter" end
		if SamePerson(arb, A) or (B and SamePerson(arb, B)) then return nil, "arbiter-fighter" end
	end
	local public = not direct and (opts.public ~= false and R.IsPublicArbiter(arb, mode)) or false
	if opts.public == true and not public then return nil, "public" end
	if (opts.stakes or (tonumber(opts.stake) or 0) > 0) and not Wagers("stake") then return nil, "compliance" end
	local marketSpecs, marketWhy = MarketSpecs(public, opts.markets)
	if marketWhy then return nil, marketWhy end
	-- (Only the flag travels to the arbiter who takes the bout over, never a list of markets.)
	if marketSpecs and opts.markets ~= nil and not Me(arb) then return nil, "markets" end
	local bo = tonumber(opts.bo) or 1
	if bo ~= 1 and bo ~= 3 and bo ~= 5 then return nil, "bo" end
	local cat = opts.cat or "A"
	if not tostring(cat):find("^[ACRB][%w]*$") then return nil, "cat" end
	local fid = opts.fid or Arena.NewId("F", function(id) return Find("fights", id) ~= nil end)
	if not fid then return nil, "id" end
	local fl = ""
	if public then fl = fl .. "p" end
	if opts.title and public then fl = fl .. "t" end
	if not B then fl = fl .. "o" end
	if direct then fl = fl .. "d" end
	if opts.card then fl = fl .. "c" end
	if opts.tid then fl = fl .. "k" end
	if opts.stakes then fl = fl .. "s" end
	if public and opts.markets == false then fl = fl .. "x" end
	local f = { fid = fid, mode = mode, st = "D", fl = fl, bo = bo, cat = cat, arb = arb, card = opts.card, tid = opts.tid, slot = opts.slot,
		A = { name = A, gk = opts.gkA }, B = B and { name = B, gk = opts.gkB } or nil, writer = ns.me, promoter = promoter,
		round = 0, sc = { 0, 0 }, rounds = {}, facts = {}, accepted = {}, heardAt = Now(), from = opts.from, stake = opts.stake,
		marketSpecs = marketSpecs, marketList = type(opts.markets) == "table" or nil }
	if Me(A) then f.A.gk = f.A.gk or MyGk() end
	if B and Me(B) then f.B.gk = f.B.gk or MyGk() end
	Put("fights", f)
	return fid
end

local function Mine(fid)
	local f = Find("fights", fid)
	if not f then return nil, "fight" end
	if not (Me(f.writer) or Me(Promoter(f))) then return nil, "writer" end
	return f
end

-- Sent out: announced (an open slot waits for its fighter), and shown on the week when public.
function F.Announce(fid)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "D" and f.st ~= "A" and f.st ~= "O" then return false, "state" end
	local was = f.st
	f.st = f.B and "A" or "O"
	f.tAnn = f.tAnn or Now()
	-- Both sides already agreed (a challenge, a direct fight): set at once.
	if f.B and ((f.accepted.A and f.accepted.B) or Has(f.fl, "d")) then f.st = "S" end
	-- The event word must lead its public sheet on the channel. Otherwise a bank or spectator that
	-- did not hold this draft yet quite correctly refuses the sheet as an unknown event.
	SendAF(f, true)
	if f.B and f.marketSpecs and not Has(f.fl, "m") and OpenMarkets(f) then SendAF(f, true) end
	Changed(f, was)
	return true
end

-- The writer takes a fighter's acceptance (AC~A), or a fighter who answered a sign-up.
local function Accepted(f, side)
	f.accepted[side] = true
	if f.st == "A" and f.accepted.A and f.accepted.B then
		local was = f.st
		f.st = "S"
		SendAF(f, true)
		Changed(f, was)
	end
end

local function SendAC(f, to, body, urgent)
	return Arena.Send("AC", f.mode, f.fid .. "~" .. body, { to = to, urgent = urgent ~= false })
end

-- A fighter accepts his fight (AC~A to its writer).
function F.Accept(fid)
	local f = Find("fights", fid)
	if not f then return false, "fight" end
	local side = SideOf(f, ns.me)
	if not side then return false, "fighter" end
	if not Arena.RulesAccepted() then return false, "rules" end
	if Me(f.writer) then Accepted(f, side) return true end
	SendAC(f, f.writer, "A~" .. B36(f.round) .. "~0~0~0~" .. (MyGk() or "-"))
	f.accepted[side] = true
	return true
end

-- The arbiter calls both fighters to the ring (AC~C with the deadline to each).
function F.Call(fid)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "S" and f.st ~= "C" then return false, "state" end
	local was = f.st
	f.st = "C"
	f.tCall = Now()
	f.deadline = Now() + F.CALL_WINDOW
	f.presence = f.presence or {}
	for _, side in ipairs({ "A", "B" }) do
		if not Me(f[side].name) then SendAC(f, f[side].name, "C~" .. B36(f.round) .. "~" .. B36(f.deadline)) end
	end
	SendAF(f, true)
	Changed(f, was)
	return true
end

-- The arbiter extends the deadline once (AC~E).
function F.Extend(fid)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "C" or f.extended then return false, "state" end
	f.extended = true
	f.deadline = (f.deadline or Now()) + F.WO_EXTEND
	for _, side in ipairs({ "A", "B" }) do
		if not Me(f[side].name) then SendAC(f, f[side].name, "E~" .. B36(f.round) .. "~" .. B36(f.deadline)) end
	end
	Arena.Changed()
	return true
end

-- Where this client stands: world yards and its instance (UnitPosition), or nil (an instance, a
-- secret, a client without it).
local function Position()
	if type(UnitPosition) ~= "function" then return nil end
	local ok, y, x, _, inst = pcall(UnitPosition, "player")
	if not ok or type(y) ~= "number" or type(x) ~= "number" then return nil end
	if issecretvalue and (issecretvalue(y) or issecretvalue(x) or issecretvalue(inst)) then return nil end
	return math.floor(x + 0.5), math.floor(y + 0.5), tonumber(inst) or 0
end
F.Position = Position
local OFFSET = 1000000
local function Coord(v) return B36(v + OFFSET) end
local function Uncoord(s) local v = N(s, 0, 2 * OFFSET) return v and v - OFFSET or nil end

-- "I'm here" (AC~H with the fighter's own position), again every HERE_EVERY until the bell.
function F.Here(fid)
	local f = Find("fights", fid)
	if not f then return false, "fight" end
	local side = SideOf(f, ns.me)
	if not side then return false, "fighter" end
	if not (f.st == "C" or f.st == "Y" or f.st == "S" or f.st == "Z") then return false, "state" end
	local x, y, inst = Position()
	local body = "H~" .. B36(f.round) .. "~" .. (x and Coord(x) or "-") .. "~" .. (y and Coord(y) or "-") .. "~" .. (inst and B36(inst) or "-")
		.. "~" .. (MyGk() or "-")
	f.hereSent = (f.hereSent or 0) + 1
	f.hereAt = Now()
	if Me(f.writer) then return true end
	SendAC(f, f.writer, body)
	return true
end

-- A token for a fighter the arbiter can see, and whether the game says he is close (the design:
-- CheckInteractDistance, never UnitInRange, which is secret on this client).
local function TokenClose(gk, name)
	if type(CheckInteractDistance) ~= "function" then return false end
	-- (The fighter's own unit: a token for a gk the game gives someone else is not his, F.TokenOf.)
	local token = F.TokenOf(gk, name)
	if token == nil then return false end
	local ok2, close = pcall(CheckInteractDistance, token, 4)
	if not ok2 or (issecretvalue and issecretvalue(close)) then return false end
	return close == true or close == 1
end
F.TokenClose = TokenClose

-- Is a fighter at the ring, as the arbiter sees it: his own position, fresh, within RING_RANGE of
-- the arbiter's in the same instance; or the arbiter's token for him close.
local function Present(f, side)
	local p = f.presence and f.presence[side]
	if p and p.x and Now() - p.at <= F.HERE_LAPSE then
		local x, y, inst = Position()
		if x and inst == p.inst and math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2) <= F.RING_RANGE then return "pos" end
	end
	if f[side] and TokenClose(f[side].gk, f[side].name) then return "token" end
	return nil
end
F.Present = Present

-- The units an arbiter's client may hold a fighter's token in (the design: he targets one fighter
-- and focuses the other; the group; the nameplates).
local UNITS = { "player", "target", "focus", "mouseover" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end
-- (issecretvalue asked first: a secret errors on any comparison, even with nil.)
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
-- The unit token of the fighter `name` and the GUID the game gives it: the token for his gk when
-- that unit is him, else any unit with his name (a gk that names someone else is not his).
local function TokenOf(gk, name)
	local function Him(token)
		if not name then return true end
		-- Players only: a creature's name is secret (UnitFullName is SecretWhenUnitIdentityRestricted:
		-- a unit not player-controlled), read before ns.UnitFullName compares it, as Borders does.
		if type(UnitIsPlayer) ~= "function" then return false end
		local okP, player = pcall(UnitIsPlayer, token)
		if not okP or Secret(player) or not player then return false end
		if type(UnitFullName) == "function" then
			local okN, raw, realm = pcall(UnitFullName, token)
			if not okN or Secret(raw) or Secret(realm) then return false end
		end
		local ok, n = pcall(ns.UnitFullName, token)
		return ok and not Secret(n) and type(n) == "string" and Same(n, name)
	end
	local guid = gk and Arena.GuidOf(gk)
	if guid and type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and token and not Secret(token) and Him(token) then return token, guid end
	end
	if not name or type(UnitGUID) ~= "function" then return nil end
	for _, unit in ipairs(UNITS) do
		local okE, exists = pcall(UnitExists or function() return true end, unit)
		if okE and exists and not Secret(exists) and Him(unit) then
			local okG, g = pcall(UnitGUID, unit)
			if okG and type(g) == "string" and not Secret(g) and g:find("^Player%-") then return unit, g end
		end
	end
	return nil
end
F.TokenOf = TokenOf

-- The weigh-in (the design): the facts the arbiter reads from a fighter's own unit, with the
-- GUID the game gives it (seen: the ledger names only GUIDs its arbiter saw, the design).
local function Facts(gk, name)
	local token, guid = TokenOf(gk, name)
	if not token then return nil end
	local function Read(fn, ...)
		if type(fn) ~= "function" then return nil end
		local r = { pcall(fn, ...) }
		if not r[1] then return nil end
		for i = 2, #r do if issecretvalue and issecretvalue(r[i]) then return nil end end
		return unpack(r, 2, table.maxn(r))
	end
	local _, classFile = Read(UnitClass, token)
	local _, _, raceID = Read(UnitRace, token)
	local level = Read(UnitLevel, token)
	local sex = Read(UnitSex, token)
	local faction = Read(UnitFactionGroup, token)
	local guild, _, rankIdx = Read(GetGuildInfo, token)
	local hp = Read(UnitHealthMax, token)
	local R = ns.Roster
	return { gk = Arena.GK(guid) or gk, class = classFile and R and R.ClassCode and R.ClassCode(classFile) or nil, race = tonumber(raceID), sex = tonumber(sex),
		level = tonumber(level), faction = faction, guild = guild, rankIdx = tonumber(rankIdx), hp = tonumber(hp), t = Now(), seen = true }
end
F.Facts = Facts

local function SendAG(f, side)
	local x = f.facts[side]
	if not x or not Has(f.fl, "p") then return end
	local function S(v) return v ~= nil and tostring(v) or "-" end
	local guild = x.guild and ns.King and ns.King.CleanGuild and ns.King.CleanGuild(x.guild) or "-"
	Arena.Send("AG", f.mode, table.concat({ f.fid, side, x.gk or "-", S(x.class), S(x.race), S(x.sex), S(x.level),
		x.faction == "Horde" and "H" or "A", guild or "-", S(x.rankIdx), S(x.hp), B36(x.t), x.fp or "-" }, "~"), { key = "ag " .. f.fid .. side })
end

-- The ring's check, each tick while called: both there, the weigh-in sent, READY.
local function CheckRing(f)
	f.presence = f.presence or {}
	local both = true
	for _, side in ipairs({ "A", "B" }) do
		local how = Present(f, side)
		f.presence[side] = f.presence[side] or {}
		f.presence[side].how = how
		-- (Seen at the ring since the call: never walked over, whatever lapsed after.)
		if how then f.presence[side].ever = true end
		if not how then both = false end
		if how and not (f.facts[side] and f.facts[side].seen) and f[side] then
			local x = Facts(f[side].gk, f[side].name)
			if x then
				-- The GUID his own unit gives beats the one his word gave (a spoofed gk, the design).
				if x.gk and x.gk ~= f[side].gk then f[side].gk, x.swapped = x.gk, true end
				f.facts[side] = x
				SendAG(f, side)
			end
		end
	end
	if both and f.st == "C" then
		f.st = "Y"
		SendAF(f, true)
		Changed(f, "C")
	end
end

-- The bell (the design): lockAt = now + Arena.LastCall(public); the fight goes live
-- at lockAt. Only in READY, or once called with override.
function F.Bell(fid, override)
	local f, why = Mine(fid)
	if not f then return false, why end
	if not (f.st == "Y" or (f.st == "C" and override)) then return false, "state" end
	if Arena.Blocked() then return false, "blocked" end
	local lockAt = Now() + Arena.LastCall(Has(f.fl, "p"))
	if Has(f.fl, "m") then
		local M = ns.Markets
		if type(M) ~= "table" or type(M.CloseBets) ~= "function" or type(M.Sheet) ~= "function" then return false, "markets" end
		local called, ok, marketWhy = pcall(M.CloseBets, f.fid)
		local sheet = M.Sheet(f.fid, f.mode)
		if not called or (ok ~= true and marketWhy ~= "closed") or not (sheet and tonumber(sheet.lockAt)) then
			return false, called and (marketWhy or "markets") or "markets"
		end
		lockAt = tonumber(sheet.lockAt)
	end
	local was = f.st
	f.st = "Z"
	f.lockAt = lockAt
	if f.round == 0 then f.round = 1 end
	SendAF(f, true)
	Changed(f, was)
	return true
end

local function GoLive(f)
	local was = f.st
	f.st = "L"
	f.roundAt = Now()
	for _, side in ipairs({ "A", "B" }) do
		if not Me(f[side].name) then SendAC(f, f[side].name, "B~" .. B36(f.round) .. "~" .. B36(f.lockAt)) end
	end
	SendAF(f, true)
	Changed(f, was)
end

-- The next round of a best-of: the bell again, straight to LIVE (no last call).
function F.NextRound(fid)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "B" then return false, "state" end
	f.round = f.round + 1
	f.lockAt = Now()
	for _, side in ipairs({ "A", "B" }) do
		if not Me(f[side].name) then SendAC(f, f[side].name, "N~" .. B36(f.round) .. "~" .. B36(f.lockAt)) end
	end
	GoLive(f)
	return true
end

---------------------------------------------------------------------------
-- Results (the writer's side)
---------------------------------------------------------------------------

local function SendAR(f, round, code)
	local x = f.rounds[round] or {}
	-- (A fight ended without a result, V or N, says so in its method whatever its last round
	-- decided: a void in the grace or between rounds is never taken for that round's final win.)
	local m = (f.st == "V" or f.st == "N") and f.st or x.m or f.m
	local body = table.concat({ f.fid, B36(round), Score(f), x.w or f.w or "-", m or "-", B36(x.dur or f.dur), B36(x.nW or 0),
		x.src or f.src or "A", f.st == "R" and "0" or (ENDED[f.st] and "1" or "0"), B36(f.graceEnd), code or f.code or "-" }, "~")
	if Has(f.fl, "p") then
		Arena.Send("AR", f.mode, body, { urgent = true, must = ENDED[f.st] and true or nil })
	else
		for _, to in ipairs(Recipients(f)) do Arena.Send("AR", f.mode, body, { to = to, urgent = true }) end
	end
end

local function Need(f) return math.floor((f.bo or 1) / 2) + 1 end

-- A round decided (w the side, m K R D, src L F W A): the score, then between rounds or the result.
local function RoundResult(f, round, w, m, dur, src, nW, code)
	if round ~= f.round then return false, "round" end
	local x = f.rounds[round] or {}
	f.rounds[round] = x
	if x.w then return false, "decided" end
	x.w, x.m, x.dur, x.src, x.nW = w, m, dur, src, nW
	f.sc = f.sc or { 0, 0 }
	if w == "A" then f.sc[1] = f.sc[1] + 1 else f.sc[2] = f.sc[2] + 1 end
	f.dur = (f.dur or 0) + (dur or 0)
	f.src = src
	local was = f.st
	if f.sc[1] >= Need(f) or f.sc[2] >= Need(f) then
		f.w = f.sc[1] >= Need(f) and "A" or "B"
		f.m = m
		f.st = "R"
		f.graceEnd = Now() + Grace(f)
	else
		f.st = "B"
	end
	SendAR(f, round, code)
	SendAF(f, true)
	Changed(f, was)
	return true
end
F.RoundResult = RoundResult

-- The fight over (a result, a walkover, a void): its end on every client that hears it.
local function Close(f, st, w, m, code, noAF)
	local was = f.st
	f.st, f.code = st, code
	if w then f.w = w end
	if m then f.m = m end
	f.graceEnd = f.graceEnd or Now()
	SendAR(f, f.round > 0 and f.round or 1, code)
	-- (The King's void of a fight he does not write goes as his AR only: every client takes that,
	-- while an AF is taken from its writer alone.)
	if not noAF then SendAF(f, true) end
	Changed(f, was)
end

-- A walkover (the design): the present fighter wins, unrated; the no-show on the promoter's list.
function F.Walkover(fid, side, auto)
	local f, why = Mine(fid)
	if not f then return false, why end
	if not (f.st == "C" or f.st == "Y" or f.st == "S" or f.st == "Z") then return false, "state" end
	if side ~= "A" and side ~= "B" then return false, "side" end
	F.NoShow(f, Other(side))
	DropFlag(f, "r")
	if f.round == 0 then f.round = 1 end
	Close(f, "W", side, "W", auto and "absent" or nil)
	return true
end

function F.Void(fid, code)
	local f = Find("fights", fid)
	if not f then return false, "fight" end
	local writes = Me(f.writer) or Me(Promoter(f))
	if not (writes or ns.ArenaRoles.IsKing(ns.me)) then return false, "writer" end
	if ENDED[f.st] and f.st ~= "W" then return false, "state" end
	if f.st == "F" then return false, "state" end
	if Has(f.fl, "d") and not writes then return false, "direct" end
	DropFlag(f, "r")
	if f.round == 0 then f.round = 1 end
	Close(f, "V", nil, "V", F.CODES[code] and code or "arb", not writes)
	return true
end

function F.NoContest(fid, code)
	local f, why = Mine(fid)
	if not f then return false, why end
	if ENDED[f.st] then return false, "state" end
	DropFlag(f, "r")
	if f.round == 0 then f.round = 1 end
	Close(f, "N", nil, "N", F.CODES[code] and code or "arb")
	return true
end

-- Disqualified (the design): the other side wins by D; for "char" unrated.
function F.Disqualify(fid, side, code)
	local f, why = Mine(fid)
	if not f then return false, why end
	if side ~= "A" and side ~= "B" then return false, "side" end
	if ENDED[f.st] then return false, "state" end
	if code == "char" then DropFlag(f, "r") end
	if f.round == 0 then f.round = 1 end
	local was = f.st
	f.w, f.m, f.code = Other(side), "D", F.CODES[code] and code or "help"
	f.st = "R"
	f.graceEnd = Now() + Grace(f)
	f.rounds[f.round] = { w = f.w, m = "D", dur = 0, src = "A" }
	SendAR(f, f.round, f.code)
	SendAF(f, true)
	Changed(f, was)
	return true
end

-- A correction during the grace (the design): by the writer, the card's promoter, or the King.
function F.Correct(fid, round, side, method)
	local f = Find("fights", fid)
	if not f then return false, "fight" end
	if not (Me(f.writer) or Me(Promoter(f)) or ns.ArenaRoles.IsKing(ns.me)) then return false, "writer" end
	if Has(f.fl, "d") then return false, "direct" end
	if f.st ~= "R" or Now() > (f.graceEnd or 0) then return false, "grace" end
	if side ~= "A" and side ~= "B" then return false, "side" end
	if not (method == "K" or method == "R" or method == "D") then return false, "method" end
	round = tonumber(round) or f.round
	local x = f.rounds[round]
	if not x then return false, "round" end
	if x.w ~= side then
		if x.w == "A" then f.sc[1] = f.sc[1] - 1 elseif x.w == "B" then f.sc[2] = f.sc[2] - 1 end
		if side == "A" then f.sc[1] = f.sc[1] + 1 else f.sc[2] = f.sc[2] + 1 end
	end
	x.w, x.m, x.src = side, method, "A"
	f.w = f.sc[1] > f.sc[2] and "A" or "B"
	f.m = method
	f.corrected = true
	local C = ns.Chronicle
	if C and not C.missing and C.Add then C.Add("arena", ns.me, L.ARENA_CHRONICLE_CORRECT:format(fid, round)) end
	SendAR(f, round, "held")
	SendAF(f, true)
	Changed(f, f.st)
	return true
end

-- The no-show list of the promoter's (writer's) client: never sent (the design).
function F.NoShow(f, side)
	local s = f[side]
	if not (s and s.gk) or not Arena.Counts(f.mode) then return end
	local store = Arena.Store(f.mode)
	store.noShows = type(store.noShows) == "table" and store.noShows or {}
	local e = store.noShows[s.gk] or { times = {} }
	store.noShows[s.gk] = e
	e.times[#e.times + 1] = Now()
	while #e.times > 5 do table.remove(e.times, 1) end
end
function F.NoShows(gk, mode)
	local store = Arena.Store(mode or "L")
	local e = store and type(store.noShows) == "table" and store.noShows[gk]
	local n = 0
	for _, t in ipairs(e and e.times or {}) do if Now() - t <= F.NO_SHOW_DAYS * 86400 then n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- Who won: the duel lines (the design)
---------------------------------------------------------------------------

local obs = {} -- [fid] = { [round] = { own = { w, m, t }, fighters = { [side] = { w, m } }, witnesses = { [key] = { w, m } }, nW, at } }
local function Obs(f, round)
	obs[f.fid] = obs[f.fid] or {}
	local o = obs[f.fid][round]
	if not o then
		o = { fighters = {}, witnesses = {}, nW = 0, at = Now() }
		obs[f.fid][round] = o
	end
	return o
end

-- Local qualifying evidence is separate from the arbiter's realm ledger, ranks and belts.
-- No wire message imports this tally: a remote tournament cannot treat a self-reported tally
-- as proof. The organizer's cutoff/verification policy is deliberately not invented here.
local function QualificationPoints(e)
	if e.mine ~= e.w then return 0 end
	local myLevel = e.mine == "A" and e.levelA or e.levelB
	local otherLevel = e.mine == "A" and e.levelB or e.levelA
	return math.max(0, math.min(20, 10 + otherLevel - myLevel))
end
local function QualificationInt(n, lo, hi)
	return type(n) == "number" and n == n and n >= lo and n <= hi and n % 1 == 0
end
local function QualificationRow(e)
	return type(e) == "table" and QualificationInt(e.t, 0, 4294967295)
		and QualificationInt(e.levelA, 1, 1000) and QualificationInt(e.levelB, 1, 1000)
		and (e.mine == "A" or e.mine == "B") and (e.w == "A" or e.w == "B")
		and (e.m == "K" or e.m == "R") and e.provenance == "local-native-bilateral"
end
local function QualificationBase(q)
	local wins, points = q.baseWins or 0, q.basePointsTenths or 0
	if not QualificationInt(wins, 0, 2147483647) or not QualificationInt(points, 0, 2147483647) or points > wins * 20 then return 0, 0 end
	return wins, points
end
function F.Qualification()
	local s = Arena.Store("L")
	local all = s and type(s.duelQualification) == "table" and s.duelQualification or {}
	local q = type(all[ns.me]) == "table" and all[ns.me] or {}
	local wins, points = QualificationBase(q)
	local out = { pointsTenths = points, wins = wins }
	for _, e in pairs(type(q.records) == "table" and q.records or {}) do
		if QualificationRow(e) then
			out[#out + 1] = e
			if e.mine == e.w then
				out.pointsTenths = out.pointsTenths + QualificationPoints(e)
				out.wins = out.wins + 1
			end
		end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	out.points = out.pointsTenths / 10
	return out
end

-- UI callers receive the policy without borrowing the arbiter's rating/rank vocabulary.
function F.QualificationPointReason()
	return { equal = 1, perLevel = 0.1, min = 0, max = 2, measured = "both-local-unit-levels" }
end

Qualify = function(f, round)
	if f.mode ~= "L" or not Arena.Counts(f.mode) or f.stake or not Has(f.fl, "d") then return end
	local mine = SideOf(f, ns.me)
	local o = obs[f.fid] and obs[f.fid][round]
	local x = f.rounds and f.rounds[round]
	local proof = o and o.localDuel
	if not mine or not proof or not nativeFinish or math.abs(nativeFinish - proof.t) > 2 then return end
	if not x or x.src ~= "F" or x.w ~= proof.w or x.m ~= proof.m then return end
	local a, b = o.fighters.A, o.fighters.B
	if not a or not b or a.w ~= b.w or a.m ~= b.m then return end
	if not (proof.A and proof.B and proof.A.gk and proof.B.gk and proof.A.gk ~= proof.B.gk) then return end
	for _, side in ipairs({ "A", "B" }) do
		local facts = proof[side]
		if not facts.guild or not ns.IsFederation(facts.guild) or Arena.RealmOf(f[side].name) ~= ns.realm then return end
		if f[side].gk and f[side].gk ~= facts.gk then return end
		if not facts.level or facts.level < 1 or facts.level > 1000 or facts.level % 1 ~= 0 then return end
	end
	local s = Arena.Store("L")
	if not s then return end
	if type(s.duelQualification) ~= "table" then s.duelQualification = {} end
	if type(s.duelQualification[ns.me]) ~= "table" then s.duelQualification[ns.me] = {} end
	local q = s.duelQualification[ns.me]
	if type(q.records) ~= "table" then q.records = {} end
	q.baseWins, q.basePointsTenths = QualificationBase(q)
	if not QualificationInt(q.lastFinish, 0, 4294967295) then q.lastFinish = nil end
	for key, e in pairs(q.records) do if not QualificationRow(e) then q.records[key] = nil end end
	local key = tostring(nativeFinish)
	-- One native completion, even when several active challenges heard the same system line.
	if q.lastFinish and nativeFinish <= q.lastFinish then return end
	q.lastFinish = nativeFinish
	q.records[key] = { fid = f.fid, round = round, t = nativeFinish, A = proof.A.gk, B = proof.B.gk,
		nameA = f.A.name, nameB = f.B.name, guildA = proof.A.guild, guildB = proof.B.guild,
		levelA = proof.A.level, levelB = proof.B.level, w = x.w, m = x.m, mine = mine,
		provenance = "local-native-bilateral" }
	local list = F.Qualification()
	for i = 1, #list - F.KEEP do
		local e = list[i]
		q.basePointsTenths = q.basePointsTenths + QualificationPoints(e)
		if e.mine == e.w then q.baseWins = q.baseWins + 1 end
		q.records[tostring(e.t)] = nil
	end
	Arena.Changed()
end

-- Which side a duel line names as winner, or nil when the line is not these two's.
local function LineSide(f, winner, loser)
	local function Is(side, name)
		local s = f[side]
		if not (s and name) then return false end
		local n = ns.Normal and ns.Normal(name) or name
		-- The game can omit a realm in its local system line. When a realm is supplied,
		-- it is part of the identity and must never fall back to the short name.
		if Same(n, s.name) then return true end
		return not n:find("-", 1, true) and ns.ShortName(ns.FullName(n)):lower() == ns.ShortName(s.name):lower()
	end
	if Is("A", winner) and Is("B", loser) then return "A" end
	if Is("B", winner) and Is("A", loser) then return "B" end
	return nil
end

-- The Chronicle (the design): every src A decision, correction and disputed result is written on
-- every client that hears it (the arbiter's own and each AR's), once per fight, round and kind.
local function Chronicle(f, round, kind, fmt, by)
	f.chron = f.chron or {}
	local k = tostring(round) .. ":" .. kind
	if f.chron[k] then return end
	f.chron[k] = true
	local C = ns.Chronicle
	if C and not C.missing and C.Add then C.Add("arena", by or ns.me, fmt:format(f.fid, round)) end
end
F.Chronicle = Chronicle

-- Whether a line of the arbiter's own, come after the round was decided from reports, may still
-- decide it: only a round one fighter and the witnesses decided (src W), the other fighter's own
-- line never agreeing (a fighter and two friends who report before the duel). A line seen after
-- both fighters' own lines agreed (src F) is another duel's (a rematch for fun in the grace, a
-- warm-up before the next bell): a game's duel line never says which duel it ends.
local function Overrulable(f, round)
	local x = f.rounds[round]
	if not (x and x.src == "W") then return false end
	local o = obs[f.fid] and obs[f.fid][round]
	local fa, fb = o and o.fighters.A, o and o.fighters.B
	return not (fa and fb and fa.w == x.w and fb.w == x.w)
end

-- The arbiter's own line came after a round was decided from reports it may overrule
-- (Overrulable) and names the other winner: his line decides it (src L) and the round is flagged
-- disputed. Changed only while it is the last round decided and the fight is between rounds or in
-- its grace; later, the flag and the Chronicle's line stay.
local function Redecide(f, round, own)
	local x = f.rounds[round]
	if not x then return end
	if x.w == own.w then x.src = "L" return end
	Chronicle(f, round, "disputed", L.ARENA_CHRONICLE_DISPUTED)
	f.code = "disputed"
	if round ~= f.round or not (f.st == "R" or f.st == "B") then
		ns.Fire("ARENA_FIGHT", f.fid, "disputed")
		Arena.Changed()
		return
	end
	if x.w == "A" then f.sc[1] = f.sc[1] - 1 elseif x.w == "B" then f.sc[2] = f.sc[2] - 1 end
	if own.w == "A" then f.sc[1] = f.sc[1] + 1 else f.sc[2] = f.sc[2] + 1 end
	x.w, x.m, x.src = own.w, own.m, "L"
	local was = f.st
	if f.sc[1] >= Need(f) or f.sc[2] >= Need(f) then
		f.w, f.m, f.st = f.sc[1] >= Need(f) and "A" or "B", own.m, "R"
		f.graceEnd = Now() + Grace(f)
	else
		f.w, f.m, f.st, f.graceEnd = nil, nil, "B", nil
	end
	SendAR(f, round, "disputed")
	SendAF(f, true)
	Changed(f, was)
end
F.Redecide = Redecide

-- The decision rule (the design) on the writer's client. The arbiter's own line decides at once
-- with a fighter agreeing (or against both, disputed). Without a line of his, the fighters' and the
-- witnesses' reports decide only in the final pass, RESULT_WAIT after the first report (a fighter
-- and two friends can't settle a round the moment it goes live), and a line of his that comes
-- later still overrules a fighter's and his witnesses' (Overrulable, Redecide).
local function Decide(f, round, final)
	if not Me(f.writer) then return end
	local o = Obs(f, round)
	local decided = f.rounds[round]
	if decided and decided.w then
		if o.own and Overrulable(f, round) then Redecide(f, round, o.own) end
		return
	end
	local agree = function(x) return x and o.own and x.w == o.own.w end
	local fa, fb = o.fighters.A, o.fighters.B
	local function Result(w, m, src, code)
		local dur = o.own and o.own.dur or ((fa and fa.dur) or (fb and fb.dur) or 0)
		if code == "disputed" then Chronicle(f, round, "disputed", L.ARENA_CHRONICLE_DISPUTED) end
		RoundResult(f, round, w, m, dur, src, o.nW, code)
	end
	if o.own then
		if agree(fa) or agree(fb) then return Result(o.own.w, o.own.m, "L") end
		if fa and fb then return Result(o.own.w, o.own.m, "L", "disputed") end
		if final then return Result(o.own.w, o.own.m, "L") end
		return
	end
	if not final then return end
	if fa and fb and fa.w == fb.w then return Result(fa.w, fa.m, "F") end
	local one = fa or fb
	if one and not (fa and fb) then
		local n = 0
		for _, x in pairs(o.witnesses) do if x.w == one.w then n = n + 1 end end
		if n >= 2 then return Result(one.w, one.m, "W") end
	end
	if not f.held then
		f.held = round
		Arena.Changed()
		ns.Fire("ARENA_FIGHT", f.fid, "held")
	end
end
F.Decide = Decide

-- The arbiter decides a held round himself (src A, logged).
function F.Rule(fid, side, method)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "L" then return false, "state" end
	if side == "N" then return F.NoContest(fid, "held") end
	if side ~= "A" and side ~= "B" then return false, "side" end
	local o = Obs(f, f.round)
	Chronicle(f, f.round, "ruled", L.ARENA_CHRONICLE_RULED)
	f.held = nil
	return RoundResult(f, f.round, side, (method == "R" or method == "K") and method or "K", 0, "A", o.nW, "held")
end

-- A fighter's report of his duel line. Only a staked direct fight's (its signed result, the design)
-- is an obligation (sent with the arena off, never held by the live switch, the design); its
-- signature is kept on the fight, with the opponent's, for the creditor's proof.
local function SendAW(f, to, round, side, method)
	local winner, loser = f[side].name, f[Other(side)].name
	local body = table.concat({ f.fid, B36(round), method, Wire(winner), Wire(loser), B36(Now()),
		B36(math.max(0, (Now() - (f.roundAt or f.lockAt or Now())) * 1000)) }, "~")
	local staked = Has(f.fl, "d") and f.stake ~= nil
	local sign = staked and Hook("Debts", "SignResult")
	if sign then
		local ok, sig = pcall(sign, f.fid, round, f[side].gk, f[Other(side)].gk)
		if ok and type(sig) == "string" and sig ~= "" and not sig:find("~", 1, true) then
			body = body .. "~" .. sig
			local mine = SideOf(f, ns.me)
			if mine then
				f.sigs = f.sigs or {}
				f.sigs[round] = f.sigs[round] or {}
				f.sigs[round][mine] = sig
			end
		end
	end
	Arena.Send("AW", f.mode, body, { to = to, urgent = true, must = staked or nil, obligation = staked or nil })
end

-- A duel line this client read (CHAT_MSG_SYSTEM). With the arena off (Arena.Off) only a staked
-- direct fight's lines count: the player's own obligation (the design).
local witnessTimers = {}
OnSystem = function(text)
	if type(text) ~= "string" then return end
	if issecretvalue and issecretvalue(text) then stats.secret = stats.secret + 1 return end
	local P = ns.ArenaParse
	if not P or not P.DuelResult then return end
	local winner, loser, method = P.DuelResult(text)
	if not winner then return end
	stats.lines = stats.lines + 1
	local m = method == "fled" and "R" or "K"
	local off = Arena.Off()
	for _, f in ipairs(All("fights")) do
		local side = LineSide(f, winner, loser)
		local st = State(f)
		local direct = Has(f.fl, "d")
		if side and off and not (direct and f.stake) then side = nil end
		-- A direct fight has no bell: agreed, it is live (the game's own duel starts it); between
		-- rounds of a best-of, the next duel is the next round.
		if side and direct and (st == "S" or st == "B") and SideOf(f, ns.me) then
			local was = st
			if st == "B" then f.round = (f.round or 0) + 1 else f.round = math.max(1, f.round or 0) end
			f.st, f.roundAt = "L", (st == "B" and Now()) or f.roundAt or f.tAnn or Now()
			st = "L"
			Changed(f, was)
		end
		if side and (st == "S" or st == "C" or st == "Y" or st == "Z") then
			-- A duel before the bell (the design): the markets void ("early") and stay off (the ticker
			-- never opens them again), the fight goes on; in the last call the arbiter rings again.
			if Me(f.writer) then
				if Has(f.fl, "m") then
					DropFlag(f, "m")
					f.marketsOff = true
					local void = Hook("Markets", "Void")
					if void then ns.SafeCall("arena markets void", void, f.fid, "*", "E") end
					ns.Fire("ARENA_VOID", f.fid, "early")
					if st ~= "Z" then SendAF(f, true) end
				end
				if st == "Z" then
					f.st, f.lockAt = "Y", nil
					SendAF(f, true)
					Changed(f, "Z")
				end
				f.early = (f.early or 0) + 1
				Arena.Changed()
			end
		elseif side and (st == "R" or st == "B") and Me(f.writer) and not direct then
			-- The arbiter's own line after the round was decided from reports: it overrules a fighter's
			-- and his witnesses' (Overrulable), never both fighters' own.
			local x = f.rounds[f.round]
			if x and Overrulable(f, f.round) then
				local o = Obs(f, f.round)
				if not o.own then
					o.own = { w = side, m = m, t = Now(), dur = x.dur or 0 }
					Decide(f, f.round)
				end
			end
		elseif side and st == "L" then
			local round = f.round
			local mySide = SideOf(f, ns.me)
			local dur = math.max(0, Now() - (f.roundAt or f.lockAt or Now()))
			if Me(f.writer) and not direct then
				local o = Obs(f, round)
				if not o.own then
					o.own = { w = side, m = m, t = Now(), dur = dur }
					Decide(f, round)
				end
			elseif direct and mySide then
				-- Direct: each fighter reports to the other; our own line is ours.
				local o = Obs(f, round)
				if not o.fighters[mySide] then
					o.fighters[mySide] = { w = side, m = m, dur = dur }
					o.localDuel = { w = side, m = m, t = Now(), A = Facts(f.A.gk, f.A.name), B = Facts(f.B.gk, f.B.name) }
					SendAW(f, f[Other(mySide)].name, round, side, m)
					F.DirectCheck(f, round)
				end
			elseif mySide then
				SendAW(f, f.arb or f.writer, round, side, m)
			elseif f.arb and not Me(f.arb) then
				-- A witness: a random wait, then a report only if no result came, or another one.
				local key = f.fid .. ":" .. round
				if not witnessTimers[key] then
					witnessTimers[key] = true
					local wait = math.random(0, F.WITNESS_WAIT * 10) / 10
					Arena.After(wait, "witness " .. key, function()
						local x = f.rounds[round]
						if not x or not x.w or x.w ~= side then SendAW(f, f.arb, round, side, m) end
					end)
				end
			end
		end
	end
end
F.OnSystem = OnSystem

-- A direct fight's round: both lines agree, the result stands (the loser's line is his acceptance).
function F.DirectCheck(f, round)
	local o = Obs(f, round)
	local fa, fb = o.fighters.A, o.fighters.B
	if round ~= f.round or not (fa and fb) or (f.rounds[round] and f.rounds[round].w) then return end
	if fa.w ~= fb.w or fa.m ~= fb.m then
		f.code = "disputed"
		Arena.Changed()
		return
	end
	local x = { w = fa.w, m = fa.m, dur = fa.dur, src = "F", nW = 0 }
	f.rounds[round] = x
	if fa.w == "A" then f.sc[1] = f.sc[1] + 1 else f.sc[2] = f.sc[2] + 1 end
	f.dur = (f.dur or 0) + (fa.dur or 0)
	local was = f.st
	if f.sc[1] >= Need(f) or f.sc[2] >= Need(f) then
		f.w, f.m = fa.w, fa.m
		f.st = "F"
		f.graceEnd = Now()
	else
		f.st = "B"
	end
	Changed(f, was)
	Qualify(f, round)
end

---------------------------------------------------------------------------
-- The ticker (the writer's deadlines, the fighters' "I'm here", the repeats)
---------------------------------------------------------------------------

Tick = function()
	local now = Now()
	for _, f in ipairs(All("fights")) do
		if Involved(f) then
			local writer = Me(f.writer)
		if writer then
				if f.st == "C" then
					CheckRing(f)
					if f.st == "C" and f.deadline and now >= f.deadline + F.WO_AUTO then
						local p = f.presence or {}
						local a = Present(f, "A") or (p.A and p.A.ever)
						local b = Present(f, "B") or (p.B and p.B.ever)
						if a and not b then F.Walkover(f.fid, "A", true)
						elseif b and not a then F.Walkover(f.fid, "B", true)
						elseif not a and not b then F.Void(f.fid, "absent") end
					end
				elseif f.st == "Z" and f.lockAt and now >= f.lockAt then
					GoLive(f)
				elseif f.st == "L" and not Has(f.fl, "d") then
					local o = obs[f.fid] and obs[f.fid][f.round]
					if o and now - o.at >= F.RESULT_WAIT then Decide(f, f.round, true) end
				elseif f.st == "R" and f.graceEnd and now >= f.graceEnd then
					F.Finalize(f)
				end
				-- The repeats: the current and next bout every minute, the others every 10.
				if f.st ~= "D" and not ENDED[f.st] then
					local gap = (LIVE[f.st] or f.st == "R" or f.st == "S") and F.REPEAT_NEAR or F.REPEAT_FAR
					if now - (f.sentAt or 0) >= gap then SendAF(f) end
				elseif ENDED[f.st] and Has(f.fl, "p") and now - (f.endedAt or now) <= F.REPEAT_AFTER and now - (f.sentAt or 0) >= F.REPEAT_FAR then
					SendAF(f)
				end
				if (f.st == "A" or f.st == "S" or f.st == "C" or f.st == "Y")
					and Has(f.fl, "p") and f.B and f.marketSpecs and not Has(f.fl, "m")
					and now - (f.marketTryAt or 0) >= F.MARKET_RETRY and OpenMarkets(f) then SendAF(f, true) end
				if ENDED[f.st] and Has(f.fl, "m") and not f.marketDone and FinishMarket then FinishMarket(f) end
			end
			local side = SideOf(f, ns.me)
			if side and not writer then
				if (f.st == "C" or f.st == "Y") and f.hereSent and f.hereSent < F.HERE_MAX and now - (f.hereAt or 0) >= F.HERE_EVERY then
					F.Here(f.fid)
				end
			end
			-- A direct fight (either fighter, its writer too): one line missing DIRECT_WAIT, disputed.
			if side and Has(f.fl, "d") and f.st == "L" and f.code ~= "disputed" then
				local o = obs[f.fid] and obs[f.fid][f.round]
				if o and now - o.at >= F.DIRECT_WAIT and not (f.rounds[f.round] and f.rounds[f.round].w) then
					f.code = "disputed"
					ns.Fire("ARENA_FIGHT", f.fid, "disputed")
					Arena.Changed()
				end
			end
		end
	end
	for _, c in ipairs(All("cards")) do
		if Me(c.promoter) then F.CardTick(c, now) end
	end
	Watch()
end
F.Tick = function() return Tick() end

-- The grace is over on the writer's client: FINAL, the ledger entry for a rated fight.
function F.Finalize(f)
	if f.st ~= "R" then return false end
	local was = f.st
	f.st = "F"
	-- The arbiter's word (the design): rated, and whether it may move its belt.
	if F.Rated(f) then AddFlag(f, "r") else DropFlag(f, "r") end
	if Has(f.fl, "r") and Has(f.fl, "t") and Has(f.fl, "p") and f.m ~= "D" and F.Eligible(f) then AddFlag(f, "b") end
	-- (The record first, with its flags, then the final result: a fighter's own history takes both.)
	SendAF(f, true)
	SendAR(f, f.round)
	if Has(f.fl, "r") and Arena.Counts(f.mode) and ns.ArenaRoles.IsArbiter(ns.me, f.mode) then
		local write = Hook("ArenaLedger", "Write")
		if write then ns.SafeCall("arena ledger write", write, f) end
	end
	Changed(f, was)
	return true
end

-- Whether the arbiter rates it (the design): facts only his client has.
function F.Rated(f)
	if not f.arb or Has(f.fl, "d") then return false, "direct" end
	if not (f.A.gk and f.B and f.B.gk) then return false, "gk" end
	if f.m == "W" then return false, "walkover" end
	if f.m == "D" and f.code == "char" then return false, "char" end
	if SamePerson(f.A.name, f.B.name) then return false, "alts" end
	if SamePerson(f.arb, f.A.name) or SamePerson(f.arb, f.B.name) then return false, "arbiter" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.Hides and (M.Hides(f.A.name) or M.Hides(f.B.name)) then return false, "off" end
	-- The weigh-in (the design): the entry names only GUIDs its arbiter saw, each from
	-- that fighter's own unit (F.Facts); a gk a fighter gave by his own word is never rated.
	local fa, fb = f.facts and f.facts.A, f.facts and f.facts.B
	if not (fa and fa.seen and fa.gk == f.A.gk and fb and fb.seen and fb.gk == f.B.gk) then return false, "weigh-in" end
	local la, lb = f.facts.A and f.facts.A.level, f.facts.B and f.facts.B.level
	if la and lb and F.Bracket(la) ~= F.Bracket(lb) then return false, "catchweight" end
	return true
end
-- The level bracket: max level, or 10-19 ... 50-59 (the design).
function F.Bracket(level)
	level = tonumber(level) or 0
	if level >= F.MaxLevel() then return "max" end
	return "B" .. (math.floor(level / 10) * 10 + 9)
end
function F.MaxLevel()
	if type(GetMaxPlayerLevel) == "function" then
		local ok, v = pcall(GetMaxPlayerLevel)
		if ok and tonumber(v) and tonumber(v) > 0 then return tonumber(v) end
	end
	return F.MAX_LEVEL
end
-- Both fighters in the category at the fight, by the weigh-in (the design).
function F.Eligible(f)
	local a, b = f.facts.A, f.facts.B
	if not (a and b and a.level and b.level) then return false end
	local max = F.MaxLevel()
	if a.level < max or b.level < max then return false end
	local class = f.cat:match("^C(%u%u)$")
	local race = tonumber(f.cat:match("^R(%d+)$"))
	if class then return a.class == class and b.class == class end
	if race then return a.race == race and b.race == race end
	return f.cat == "A"
end

---------------------------------------------------------------------------
-- The handlers
---------------------------------------------------------------------------

OnFight = function(dist, sender, mode, body)
	local ok, why = F.Take(dist, sender, mode, body)
	if not ok then ns.Log("arena AF from %s refused: %s", tostring(sender), tostring(why)) end
end
ns.Comm.Handle("AF", ns.Arena.Handle("AF", OnFight))

-- AG: the weigh-in, from the fight's arbiter only; our own token's facts beat it (a mismatch is flagged).
local function OnWeigh(dist, sender, mode, body)
	local fid, side, gk, class, race, sex, level, faction, guild, rankIdx, hp, t, fp = Arena.Fields(body, 13)
	if not fp then return Refuse("shape") end
	local f = Find("fights", fid)
	if not f or not Same(sender, f.arb) or (side ~= "A" and side ~= "B") then return Refuse("sender") end
	-- (The guild's name through King.CleanGuild here too: nothing another player sends reaches a
	-- screen unchecked, the design.)
	local K = ns.King
	local clean = guild ~= "-" and K and type(K.CleanGuild) == "function" and K.CleanGuild(guild) or nil
	local x = { gk = Gk(gk), class = class ~= "-" and class:sub(1, 2) or nil, race = tonumber(race), sex = tonumber(sex),
		level = tonumber(level), faction = faction == "H" and "Horde" or "Alliance", guild = clean,
		rankIdx = tonumber(rankIdx), hp = tonumber(hp), t = Time(t), fp = fp ~= "-" and fp or nil, by = "arbiter" }
	local own = x.gk and Facts(x.gk, f[side] and f[side].name)
	if own and (own.level ~= x.level or own.class ~= x.class) then x.mismatch = true end
	f.facts[side] = x
	Arena.Changed()
end
ns.Comm.Handle("AG", ns.Arena.Handle("AG", OnWeigh))

-- AC: ring control. Arbiter to fighter: C (call), B (bell), N (next round), E (extended), P (pause);
-- fighter to arbiter: A (accept), H (here), Q (concede), R (refuse the booking).
local function OnControl(dist, sender, mode, body)
	if dist ~= "WHISPER" then return Refuse("lane") end
	local fid, what, round, a, b, c, gk = Arena.Fields(body, 7)
	if not what then fid, what, round, a, b, c = Arena.Fields(body, 6) end
	if not what then fid, what, round, a = Arena.Fields(body, 4) end
	if not what then return Refuse("shape") end
	local f = Find("fights", fid)
	if not f then return Refuse("fight") end
	round = N(round, 0, 9) or 0
	if Same(sender, f.writer) or Same(sender, f.arb) then
		local side = SideOf(f, ns.me)
		if not side then return Refuse("fighter") end
		if what == "C" or what == "E" then
			f.deadline = N(a, 0, 4294967295)
			if what == "C" then
				-- ("I'm here" is the fighter's click; its repeats start with it.)
				f.hereSent = nil
				-- (one alert per CALL_GAP: a writer's repeated calls raise no new one)
				local now = Now()
				if not f.calledAt or now - f.calledAt >= F.CALL_GAP or now < f.calledAt then
					f.calledAt = now
					ns.Fire("ARENA_CALLED", fid)
				end
			end
		elseif what == "B" or what == "N" then
			f.round = round
			f.roundAt = Now()
			f.lockAt = N(a, 0, 4294967295) or Now()
			if f.st ~= "L" then local was = f.st f.st = "L" Changed(f, was) end
		end
		Arena.Changed()
		return
	end
	local side = SideOf(f, sender)
	if not side or not Me(f.writer) then return Refuse("sender") end
	-- The fighter's GUID, his own word: taken unless the game says it is someone else's (the
	-- weigh-in, from the arbiter's own token, beats it).
	gk = Gk(gk)
	if gk and not f[side].gk then
		local P = ns.ArenaProfile
		local ok = P and P.VerifyGk and P.VerifyGk(sender, gk)
		if ok ~= false then f[side].gk = gk end
	end
	if what == "A" then
		Accepted(f, side)
	elseif what == "H" then
		local now = Now()
		f.presence = f.presence or {}
		local p = f.presence[side] or {}
		if p.at and now - p.at < 10 then return Refuse("rate") end
		f.presence[side] = { x = Uncoord(a), y = Uncoord(b), inst = N(c, 0, 99999999) or 0, at = now }
		if f.st == "C" then CheckRing(f) end
	elseif what == "Q" then
		if LIVE[f.st] or f.st == "S" then F.Walkover(fid, Other(side)) end
	elseif what == "R" then
		if f.st == "A" or f.st == "S" then F.Void(fid, "refused") end
	end
	Arena.Changed()
end
ns.Comm.Handle("AC", ns.Arena.Handle("AC", OnControl))

-- AW: a duel line reported (fighters at once, witnesses after their wait).
local function OnWitness(dist, sender, mode, body)
	if dist ~= "WHISPER" then return Refuse("lane") end
	local fid, round, method, winner, loser, t, ms, sig = Arena.Fields(body, 8)
	if not ms then fid, round, method, winner, loser, t, ms = Arena.Fields(body, 7) end
	if not ms then return Refuse("shape") end
	local f = Find("fights", fid)
	if not f then return Refuse("fight") end
	if mode ~= f.mode then return Refuse("mode") end
	round = N(round, 1, 9)
	if not round or (method ~= "K" and method ~= "R") then return Refuse("shape") end
	local side = LineSide(f, Unwire(winner, sender), Unwire(loser, sender))
	if not side then return Refuse("names") end
	local o = Obs(f, round)
	local senderSide = SideOf(f, sender)
	if Has(f.fl, "d") then
		-- Direct: the opponent's line, to the other fighter (once a round); in a staked fight his
		-- signature over it is kept on the fight (the winner's proof, the design).
		local mine = SideOf(f, ns.me)
		if not senderSide or not mine or senderSide == mine then return Refuse("sender") end
		if o.fighters[senderSide] then return Refuse("again") end
		o.fighters[senderSide] = { w = side, m = method, sig = sig }
		if f.stake and type(sig) == "string" and sig ~= "" and #sig <= 120 then
			f.sigs = f.sigs or {}
			f.sigs[round] = f.sigs[round] or {}
			f.sigs[round][senderSide] = sig
		end
		return F.DirectCheck(f, round)
	end
	if not Me(f.writer) then return Refuse("not-arbiter") end
	if round ~= f.round and not (round == f.round - 1 and Now() - (f.roundAt or 0) <= F.REPORT_LATE) then return Refuse("round") end
	if senderSide then
		if o.fighters[senderSide] then return Refuse("again") end
		o.fighters[senderSide] = { w = side, m = method }
	else
		-- A witness: independent (no fighter, no alt of a fighter or of the arbiter), not net-off,
		-- once, 20 at most.
		local M = ns.Moderation
		if type(M) == "table" and not M.missing and M.Hides and M.Hides(sender) then return Refuse("off") end
		if Arena.Sanctioned and Arena.Sanctioned(sender) then return Refuse("off") end -- (1.1.6: WatchChat.Barred)
		if F.IsFighter(f, sender) or SamePerson(sender, f.arb or f.writer) then return Refuse("interested") end
		local key = Lower(sender)
		if o.witnesses[key] then return Refuse("again") end
		if o.nW >= F.WITNESSES_MAX then return Refuse("witnesses") end
		o.witnesses[key] = { w = side, m = method }
		o.nW = o.nW + 1
	end
	Decide(f, round)
end
ns.Comm.Handle("AW", ns.Arena.Handle("AW", OnWitness))

-- AR: a round's or the fight's result, from its writer, the card's promoter or the King (grace).
local function OnResult(dist, sender, mode, body)
	local fid, round, sc, w, m, dur, nW, src, final, graceEnd, code = Arena.Fields(body, 11)
	if not code then return Refuse("shape") end
	local f = Find("fights", fid)
	if not f then return Refuse("fight") end
	-- A direct fight's result is each fighter's own (his line and the other's AW): never a word.
	if Has(f.fl, "d") then return Refuse("direct") end
	-- The King: a correction in the grace, or a void of a fight not yet over (whatever its state,
	-- The design: his AR is the void every client applies; its writer then voids its markets
	-- and refunds its stakes, F.Ended).
	local isKing = ns.ArenaRoles.IsKing(sender)
	local kingVoid = isKing and final == "1" and m == "V" and f.st ~= "F" and f.st ~= "V" and f.st ~= "N"
	local king = isKing and (f.st == "R" or kingVoid)
	if not (Same(sender, f.writer) or Same(sender, Promoter(f)) or king) then return Refuse("sender") end
	if Has(f.fl, "p") and dist ~= "CHANNEL" and dist ~= "RAID" and dist ~= "PARTY" then return Refuse("lane") end
	round = N(round, 1, 9)
	local sa, sb = tostring(sc):match("^(%d):(%d)$")
	if not round or not sa then return Refuse("shape") end
	local x = f.rounds[round] or {}
	f.rounds[round] = x
	local before = x.w
	-- (A void or no contest leaves the round it came after as it was decided.)
	local ending = final == "1" and (m == "V" or m == "N")
	if not ending then
		x.w = (w == "A" or w == "B") and w or x.w
		x.m = METHODS[m] and m or x.m
		x.dur, x.nW, x.src = N(dur, 0, 86400), N(nW, 0, 99), src
	end
	f.sc = { tonumber(sa), tonumber(sb) }
	f.round = math.max(f.round or 0, round)
	f.code = code ~= "-" and code or f.code
	f.graceEnd = Time(graceEnd) or f.graceEnd
	-- The Chronicle on every client that hears it (the design): a ruling (src A), a correction, a
	-- disputed result, each once.
	if src == "A" and x.w and m ~= "V" and m ~= "N" and m ~= "W" then
		if before and before ~= x.w then Chronicle(f, round, "correct:" .. x.w, L.ARENA_CHRONICLE_CORRECT, sender)
		elseif not before then Chronicle(f, round, "ruled", L.ARENA_CHRONICLE_RULED, sender) end
	end
	if code == "disputed" then Chronicle(f, round, "disputed", L.ARENA_CHRONICLE_DISPUTED, sender) end
	local was = f.st
	if final == "1" then
		if ending then f.st, f.m = m, m
		elseif m == "W" then f.st, f.w, f.m = "W", x.w, "W"
		else f.st, f.w, f.m = "F", x.w, x.m end
	elseif f.sc[1] >= Need(f) or f.sc[2] >= Need(f) then
		f.st, f.w, f.m = "R", f.sc[1] >= Need(f) and "A" or "B", x.m
	elseif x.m == "D" and x.w then
		f.st, f.w, f.m = "R", x.w, "D"
	elseif x.w then
		f.st, f.w, f.m = "B", nil, nil
	end
	if was ~= f.st then Changed(f, was) else Arena.Changed() end
end
ns.Comm.Handle("AR", ns.Arena.Handle("AR", OnResult))

---------------------------------------------------------------------------
-- Challenges and sign-ups (AS)
---------------------------------------------------------------------------

-- (The challenges this session holds, chal: declared with the helpers above.)
local lastAS = {} -- [sender] = time (1 per 3 s)
local lastChal = {} -- [challenger] = when we said no to him (none from him for F.CHALLENGE_GAP)

-- Link a fight to the private match that created its local challenge without adding a field to
-- AF or AS. Direct fights have oid == fid. An arbitrated AF may race AS Z, so exact fid wins and
-- otherwise only one challenge with the same full cast and terms is accepted. Ambiguity is safer
-- left to the match timeout than attached to an unrelated fight between the same two players.
MatchFromChallenge = function(f)
	local one, count
	for oid, c in pairs(chal) do
		local direct = Has(f.fl, "d")
		local exact = direct and oid == f.fid or (not direct and c.fid == f.fid)
		local pending = not direct and not c.fid and (c.state == "yes" or c.state == "arbiter")
		if c.mode == f.mode and c.bo == f.bo and Same(c.A, f.A and f.A.name) and Same(c.B, f.B and f.B.name)
			and ((direct and c.how == "d") or (not direct and c.how == "a" and Same(c.arbiter, f.arb))) and (exact or pending) then
			if exact then return c.from end
			count, one = (count or 0) + 1, c
		end
	end
	return count == 1 and one.from or nil
end

local function AttachMatch(f, mid)
	if not f or f.from or type(mid) ~= "string" or mid == "" then return end
	f.from = mid
	if f.endedDone and not f.matchEnded then
		local ended = Hook("ArenaMatch", "Ended")
		if ended then
			f.matchEnded = true
			ns.SafeCall("arena match ended", ended, mid)
		end
	end
end

local function Blocked(name, gk)
	local b = Hook("Debts", "Blocked")
	if not b then return false end
	local ok, yes, why = pcall(b, name, gk)
	return ok and yes == true, why
end

-- A call into another package that may fail: its results, or nothing.
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2, table.maxn(r))
end

-- An IOU as the money part's Debts.Iou gives it (a table with its wire, or the wire itself): the wire, never
-- with the body's separator in it.
local function IouWire(x)
	if type(x) == "table" then x = x.wire end
	if type(x) ~= "string" or x == "" or #x > 160 or x:find("[~|]") or not x:find(".", 1, true) then return nil end
	return x
end
local function WireField(x)
	if type(x) ~= "string" or x == "" or x == "-" or #x > 200 or x:find("[~|]") then return nil end
	return x
end

-- A staked challenge's salt (the design: the IOUs commit to the amount with it, so the published
-- proof never shows the amount); it goes to the opponent in the challenge's own whisper.
local SALT_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Salt()
	local out = {}
	for i = 1, 12 do
		local k = math.random(1, #SALT_CHARS)
		out[i] = SALT_CHARS:sub(k, k)
	end
	return table.concat(out)
end
F.Salt = Salt

-- Whether I may challenge `opponent` now (the action's rule; matchmaking asks it for "Staked").
-- opts: { stake (copper), how = "d"|"a", arbiter, cur, rehearsal, mode (an answer's: the
-- challenge's own mode) }. A stake needs (the design): the realm's currency gold and the
-- challenge's too (no direct or trade-held stakes under glory points); whole silver (both sides
-- sign the same amount); saved data that persists for a live stake; the money side (the money part) there;
-- a cap it knows (a missing or unknown cap refuses); an arbiter's T1~M cap for a held stake.
function F.CanChallenge(opponent, opts)
	opts = opts or {}
	if type(opponent) ~= "string" or opponent == "" then return false, "opponent" end
	if Me(opponent) or SamePerson(opponent, ns.me) then return false, "self" end
	if not ns.IsMember() then return false, "guild" end
	if not Arena.RulesAccepted() then return false, "rules" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.SelfOff and M.SelfOff() then return false, "off" end
	if Blocked(ns.me) then return false, "debtor" end
	local stake = tonumber(opts.stake) or 0
	if stake > 0 then
		if not Wagers("stake") then return false, "compliance" end
		local mode = (opts.mode == "L" or opts.mode == "T") and opts.mode or Arena.NewMode(opts.rehearsal)
		if ns.ArenaRoles.Currency() ~= "g" or (opts.cur or "g") ~= "g" then return false, "currency" end
		if stake % 100 ~= 0 then return false, "silver" end
		if mode == "L" and not Arena.Persists() then return false, "persists" end
		local money = Money(opts.how == "a" and MONEY_HELD or MONEY_DIRECT)
		if not money then return false, "money" end
		local cap = tonumber((Call(money.Cap, opts.how == "a" and "bet" or "direct", ns.me, mode)))
		if not cap or stake > cap then return false, "cap" end
		if opts.how == "a" then
			if not opts.arbiter then return false, "arbiter" end
			local limit = tonumber(ns.ArenaRoles.ArbiterCap(opts.arbiter)) or 0
			if limit <= 0 or 2 * stake > limit then return false, "arbiter-cap" end
		end
	end
	return true
end

-- An IOU another player gave for a staked challenge, checked (the design): his account key's
-- signature over this challenge's id, his gk, ours and the stake's commitment with the salt.
-- true, or false and the code the refusal carries ("k" no verified key, "i" not his IOU).
function F.CheckIou(oid, payer, wire, stake, salt)
	local money = Money(MONEY_DIRECT)
	if not money then return false, "money" end
	local payerGk = Call(money.Verified, payer)
	local payeeGk = MyGk()
	local pk = Call(money.KeyOf, payer)
	if type(payerGk) ~= "string" or type(payeeGk) ~= "string" or not pk then return false, "k" end
	local iou = type(wire) == "string" and Call(money.ReadIou, wire, oid, payerGk, payeeGk) or nil
	if type(iou) ~= "table" or type(salt) ~= "string" or iou.commit ~= Call(money.Commit, stake, salt) then return false, "i" end
	if Call(money.CheckIou, iou.text, iou.sig, pk) ~= true then return false, "i" end
	return true
end

-- The challenger's standing token and IOU, checked by the opponent before he agrees (the design,
-- 9.4): the token a bank signed (the money part's CheckWire keeps it, so his direct cap reads from it) covers
-- the stake, and the IOU is his.
function F.CheckChallenger(c)
	local money = Money(MONEY_DIRECT)
	if not money then return false, "money" end
	if not (c.token and Call(money.CheckWire, c.token, c.A, c.mode)) then return false, "t" end
	local cap = tonumber((Call(money.Cap, "direct", c.A, c.mode)))
	if not cap or c.stake > cap then return false, "t" end
	return F.CheckIou(c.oid, c.A, c.iou, c.stake, c.salt)
end

-- A challenge (the design): to the opponent, who answers AS~Y. opts: { bo, stake, how = "d"|"a",
-- arbiter, cur, from (a match id: its hand-off), rehearsal }. A direct stake carries the
-- challenger's standing token, his signed IOU and the salt: AS~X ...~cur~token~iou~salt.
-- Returns the oid, or nil and why (nothing is kept when the challenge could not go).
function F.Challenge(opponent, opts)
	opts = opts or {}
	local target = Arena.Name(opponent or "")
	if not target then return nil, "opponent" end
	local ok, why = F.CanChallenge(target, opts)
	if not ok then return nil, why end
	local oid = Arena.NewId("F", function(id) return Find("fights", id) ~= nil or chal[id] ~= nil end)
	if not oid then return nil, "id" end
	local how = opts.how == "a" and Arbiters() and "a" or "d"
	local c = { oid = oid, A = ns.me, B = target, bo = tonumber(opts.bo) or 1, stake = math.floor(tonumber(opts.stake) or 0), how = how,
		arbiter = how == "a" and Arena.Name(opts.arbiter or "") or nil, cur = opts.cur or ns.ArenaRoles.Currency(), from = opts.from,
		state = "asked", t = Now(), mode = Arena.NewMode(opts.rehearsal) }
	if c.bo ~= 1 and c.bo ~= 3 and c.bo ~= 5 then return nil, "bo" end
	if how == "a" and not c.arbiter and c.stake > 0 then return nil, "arbiter" end
	local body = table.concat({ oid, "X", B36(c.bo), B36(math.floor(c.stake / 100)), how, c.arbiter and Wire(c.arbiter) or "-", c.cur }, "~")
	if how == "d" and c.stake > 0 then
		local money = Money(MONEY_DIRECT)
		c.salt = Salt()
		local token = WireField(Call(money.TokenWire, c.mode))
		if not token then return nil, "token" end
		local wire = IouWire(Call(money.Iou, oid, target, c.stake, c.salt))
		if not wire then return nil, "iou" end
		c.myIou = wire
		body = body .. "~" .. token .. "~" .. wire .. "~" .. c.salt
	end
	local sent, whySend = Arena.Send("AS", c.mode, body, { to = target, urgent = true })
	if not sent then return nil, whySend or "send" end
	chal[oid] = c
	Arena.Changed()
	return oid
end

-- The opponent's answer to a challenge he got (AS~Y). yes: his agreement, under the challenge's
-- own mode; for a direct stake, once the challenger's token and IOU check out, with his own IOU:
-- AS~Y oid~Y~1~-~iou. The answer counts only once it went (Arena.Send).
function F.Answer(oid, yes, why)
	local c = chal[oid]
	if not c or not c.incoming or c.judge or c.state ~= "asked" then return false, "challenge" end
	local body
	if yes then
		local ok, whyNot = F.CanChallenge(c.A, { stake = c.stake, how = c.how, arbiter = c.arbiter, cur = c.cur, mode = c.mode })
		if not ok then return false, whyNot end
		if c.mode == "L" and Arena.NewMode() ~= "L" then return false, "live" end
		body = table.concat({ oid, "Y", "1", "-" }, "~")
		if c.how == "d" and c.stake > 0 then
			local okC, code = F.CheckChallenger(c)
			if not okC then
				c.state, c.why = "no", code
				Arena.Send("AS", c.mode, table.concat({ oid, "Y", "0", code }, "~"), { to = c.A, urgent = true })
				ns.Fire("ARENA_CHALLENGE", oid)
				Arena.Changed()
				return false, code
			end
			local money = Money(MONEY_DIRECT)
			local wire = IouWire(Call(money.Iou, oid, c.A, c.stake, c.salt))
			if not wire then return false, "iou" end
			c.myIou = wire
			body = body .. "~" .. wire
		end
	else
		lastChal[Lower(c.A)] = Now()
		body = table.concat({ oid, "Y", "0", (tostring(why or "n"):gsub("[~|%c]", "")):sub(1, 8) }, "~")
	end
	local sent, whySend = Arena.Send("AS", c.mode, body, { to = c.A, urgent = true })
	if not sent then return false, whySend or "send" end
	c.state = yes and "yes" or "no"
	Arena.Changed()
	return true
end

-- Ask an arbiter to judge an agreed challenge (AS~Q): again another one when the first said no.
function F.AskArbiter(oid, name)
	if not Arbiters() then return false, "compliance" end
	local c = chal[oid]
	if not c or c.incoming then return false, "challenge" end
	if c.state ~= "yes" and c.state ~= "arbiter-no" then return false, "state" end
	local arb = Arena.Name(name or c.arbiter or "")
	if not arb then return false, "arbiter" end
	if SamePerson(arb, c.A) or SamePerson(arb, c.B) then return false, "arbiter-fighter" end
	c.arbiter, c.state = arb, "arbiter"
	Arena.Send("AS", c.mode, table.concat({ oid, "Q", Wire(c.A), Wire(c.B), B36(math.floor(c.stake / 100)), B36(c.bo) }, "~"),
		{ to = arb, urgent = true })
	Arena.Changed()
	return true
end

-- The challenge agreed, direct: the challenger writes the fight himself (no arbiter), in the
-- challenge's mode, with the stake, both IOUs and the salt.
local function StartDirect(c)
	local verified = Hook("Debts", "Verified")
	local gkB = verified and Call(verified, c.B) or nil
	local fid, why = F.New({ A = c.A, B = c.B, direct = true, bo = c.bo, fid = c.oid, stake = c.stake > 0 and c.stake or nil,
		from = c.from, rehearsal = c.mode == "T", gkB = type(gkB) == "string" and gkB or nil })
	if not fid then ns.Log("arena direct fight not made: %s", tostring(why)) return end
	local f = Find("fights", fid)
	f.accepted.A, f.accepted.B = true, true
	if c.stake > 0 then f.salt, f.ious = c.salt, { A = c.myIou, B = c.theirIou } end
	c.fid, c.state = fid, "set"
	F.Announce(fid)
end

-- A fighter of an arbiter-held stake: his side of the book (the money part's Stakes.Open runs on each
-- party's client too: the watcher for his stake's trade to the arbiter). The fight is linked to
-- his challenge: the challenger's by the arbiter's AS~Z, the opponent's by its fighters.
function F.OpenPartyStake(f)
	if f.partyOpened or not Has(f.fl, "s") or Has(f.fl, "d") or not f.arb then return end
	local mine = SideOf(f, ns.me)
	if not mine then return end
	local c
	for _, x in pairs(chal) do
		if x.how == "a" and (x.stake or 0) > 0 and not x.judge then
			if not x.incoming and x.fid == f.fid then c = x
			elseif x.incoming and not x.fid and x.state == "yes" and f.A and Same(x.A, f.A.name) and Same(x.B, ns.me) and (not c or x.t > c.t) then c = x end
		end
	end
	if not c then return end
	c.fid, c.state = f.fid, "set"
	f.stake, f.partyOpened = c.stake, true
	local open = Hook("Stakes", "Open")
	if open then
		ns.SafeCall("arena party stake", open, { id = f.fid, kind = "fight", A = { name = f.A.name, gk = f.A.gk }, B = { name = f.B.name, gk = f.B.gk },
			stake = { A = c.stake, B = c.stake }, arbiter = f.arb, mode = f.mode })
	end
end

-- The sign-up answer's words (the design).
local SIGN = { O = true, F = true, C = true, D = true, X = true, L = true, B = true, P = true }

local function OnSign(dist, sender, mode, body)
	if dist ~= "WHISPER" then return Refuse("lane") end
	local now = Now()
	local key = Lower(sender)
	if lastAS[key] and now - lastAS[key] < F.SIGN_GAP and not body:find("^[^~]+~[YZ]~") then return Refuse("rate") end
	lastAS[key] = now
	local oid, what, rest = Arena.Fields(body, 3)
	if not what then oid, what = Arena.Fields(body, 2) end
	if not what then return Refuse("shape") end
	rest = rest or ""
	local challengeId = type(oid) == "string" and oid:find("^F[0-9a-z]+$") ~= nil and #oid <= 20
	if what == "X" then
		-- A challenge to us: its id the challenger's own (Arena.NewId's mark), never one held here.
		if not challengeId or not MadeBy(oid, sender) then return Refuse("oid") end
		if chal[oid] or Find("fights", oid) then return Refuse("again") end
		local bo, stake, how, arb, cur, token, iou, salt = Arena.Fields(rest, 8)
		if not cur then bo, stake, how, arb, cur = Arena.Fields(rest, 5) end
		if not cur then return Refuse("shape") end
		local c = { oid = oid, A = ns.FullName(sender), B = ns.me, bo = N(bo, 1, 5) or 1, stake = (N(stake, 0, 21474836) or 0) * 100,
			how = how == "a" and "a" or "d", arbiter = Unwire(arb, sender), cur = cur == "p" and "p" or "g", state = "asked",
			t = now, incoming = true, mode = mode, token = WireField(token), iou = WireField(iou), salt = WireField(salt) }
		local function No(why) Arena.Send("AS", mode, table.concat({ oid, "Y", "0", why }, "~"), { to = sender, urgent = true }) end
		-- (A staked challenge, a modified client's too: never taken while the gate says no.)
		if c.stake > 0 and not Wagers("stake") then return Refuse("compliance") end
		-- (A challenge that waits on an arbiter: never while there are none.)
		if c.how == "a" and not Arbiters() then return Refuse("compliance") end
		if c.bo ~= 1 and c.bo ~= 3 and c.bo ~= 5 then return No("f") end
		-- A stake in this realm's currency only (the design).
		if c.stake > 0 and c.cur ~= ns.ArenaRoles.Currency() then return No("c") end
		-- The agreed stake holds for a matched partner (the design).
		local vet = Hook("ArenaMatch", "Vet")
		if vet then
			local ok, yes, from = pcall(vet, sender, "d", c.stake)
			if ok and yes == false then return No("m") end
			if ok and yes == true and type(from) == "string" then c.from = from end
		end
		if Blocked(sender) then return No("D") end
		local M = ns.Moderation
		if type(M) == "table" and not M.missing and M.Hides and M.Hides(sender) then return No("X") end
		if Arena.Sanctioned and Arena.Sanctioned(sender) then return No("X") end -- (1.1.6: a sanctioned challenger)
		-- One open challenge per challenger (open: unanswered for under a minute), and none for a minute after
		-- we said no to him: no spam.
		for _, x in pairs(chal) do
			if x.incoming and not x.judge and x.state == "asked" and Same(x.A, sender) and now - (x.t or 0) < F.CHALLENGE_GAP then return Refuse("spam") end
		end
		if lastChal[key] and now - lastChal[key] < F.CHALLENGE_GAP then return Refuse("spam") end
		chal[oid] = c
		ns.Fire("ARENA_CHALLENGE", oid)
		Arena.Changed()
	elseif what == "Y" then
		local c = chal[oid]
		if not c or c.incoming or not Same(sender, c.B) or c.state ~= "asked" then return Refuse("challenge") end
		local yes, why, iou = Arena.Fields(rest, 3)
		if not yes then yes, why = Arena.Fields(rest, 2) end
		if yes ~= "1" then
			c.state, c.why = "no", why
			ns.Fire("ARENA_CHALLENGE", oid)
			Arena.Changed()
			return
		end
		-- A direct stake: his IOU is his (the design), else no fight.
		if c.how == "d" and c.stake > 0 then
			local ok, code = F.CheckIou(oid, c.B, WireField(iou), c.stake, c.salt)
			if not ok then
				c.state, c.why = "no", code
				ns.Fire("ARENA_CHALLENGE", oid)
				Arena.Changed()
				return Refuse("iou")
			end
			c.theirIou = WireField(iou)
		end
		c.state = "yes"
		if c.how == "d" then StartDirect(c) else F.AskArbiter(oid, c.arbiter) end
		ns.Fire("ARENA_CHALLENGE", oid)
	elseif what == "Q" then
		-- To the arbiter: judge A against B. His answer is AS~Z (the fight is made on "yes", F.Judge).
		if not challengeId or not MadeBy(oid, sender) then return Refuse("oid") end
		local had = chal[oid]
		if had and not (had.judge and had.state == "judge" and Same(had.A, sender)) then return Refuse("again") end
		local a, b, stake, bo = Arena.Fields(rest, 4)
		if not bo then return Refuse("shape") end
		local A, B = Unwire(a, sender), Unwire(b, sender)
		if not (A and B) or not Same(sender, A) then return Refuse("sender") end
		-- (Asked to hold a stake: never while the gate says no.)
		if (N(stake, 0, 21474836) or 0) > 0 and not Wagers("stake") then return Refuse("compliance") end
		-- (Asked to judge: no arbiters while no wager may happen.)
		if not Arbiters() then return Refuse("compliance") end
		if not ns.ArenaRoles.IsArbiter(ns.me, mode) or SamePerson(ns.me, A) or SamePerson(ns.me, B) then
			Arena.Send("AS", mode, table.concat({ oid, "Z", "0", "a" }, "~"), { to = sender, urgent = true })
			return Refuse("not-arbiter")
		end
		chal[oid] = { oid = oid, A = A, B = B, bo = N(bo, 1, 5) or 1, stake = (N(stake, 0, 21474836) or 0) * 100, how = "a", arbiter = ns.me,
			state = "judge", t = now, incoming = true, judge = true, mode = mode }
		ns.Fire("ARENA_CHALLENGE", oid)
		Arena.Changed()
	elseif what == "Z" then
		local c = chal[oid]
		if not c or c.incoming or not Same(sender, c.arbiter) then return Refuse("challenge") end
		local yes, why, fid = Arena.Fields(rest, 3)
		if not yes then yes, why = Arena.Fields(rest, 2) end
		if yes == "1" and type(fid) == "string" and fid:find("^F[0-9a-z]+$") and #fid <= 20 then
			c.state, c.fid = "set", fid
			-- (The fight may be here already: its match id, and our side of a held stake.)
			local f = Find("fights", fid)
			AttachMatch(f, c.from)
			if f then F.OpenPartyStake(f) end
		else
			c.state, c.why = "arbiter-no", why
		end
		ns.Fire("ARENA_CHALLENGE", oid)
		Arena.Changed()
	elseif what == "J" or what == "W" or what == "K" or what == "A" then
		-- A fighter to an open object's writer: a tournament's (ArenaTourney) or an open slot's.
		local T = ns.ArenaTourney
		if oid:sub(1, 1) == "T" and type(T) == "table" and T.OnSign then return T.OnSign(sender, mode, oid, what, rest) end
		return F.OnSlotSign(sender, mode, oid, what, rest)
	elseif SIGN[what] then
		-- The writer's answer to our own sign-up.
		local T = ns.ArenaTourney
		if oid:sub(1, 1) == "T" and type(T) == "table" and T.OnAnswer then return T.OnAnswer(sender, oid, what) end
		local f = Find("fights", oid)
		if f and Same(sender, f.writer) then
			f.mySign = what
			Arena.Changed()
		end
	end
end
ns.Comm.Handle("AS", ns.Arena.Handle("AS", OnSign))

-- The arbiter's answer to AS~Q: yes makes the fight (private: whispered to the two), and holds the
-- stakes when there are some: gold only (the design), in the fight's own mode (a rehearsal's book is
-- the rehearsal's), refused where the money side (the money part's Stakes.Open) is not there or says no.
function F.Judge(oid, yes, why)
	local c = chal[oid]
	if not c or not c.judge or c.state ~= "judge" then return false, "challenge" end
	local function No(code)
		c.state = "no"
		Arena.Send("AS", c.mode, table.concat({ oid, "Z", "0", (tostring(code or "n"):gsub("[~|%c]", "")):sub(1, 8) }, "~"), { to = c.A, urgent = true })
	end
	if not yes then No(why) return true end
	if c.stake > 0 then
		if ns.ArenaRoles.Currency() ~= "g" then No("c") return false, "currency" end
		if not Money(MONEY_HELD) then No("s") return false, "money" end
	end
	local fid, whyNew = F.New({ A = c.A, B = c.B, bo = c.bo, public = false, stakes = c.stake > 0, stake = c.stake > 0 and c.stake or nil,
		rehearsal = c.mode == "T" })
	if not fid then No(whyNew) return false, whyNew end
	if c.stake > 0 then
		local open = Hook("Stakes", "Open")
		local f = Find("fights", fid)
		local ok, held, whyS = pcall(open, { id = fid, kind = "fight", A = { name = c.A, gk = f.A.gk }, B = { name = c.B, gk = f.B.gk },
			stake = { A = c.stake, B = c.stake }, arbiter = ns.me, mode = f.mode })
		if not ok or held ~= true then
			F.Void(fid, "refused")
			No(whyS or "s")
			return false, whyS or "stakes"
		end
	end
	local f = Find("fights", fid)
	f.accepted.A, f.accepted.B = true, true
	c.state, c.fid = "set", fid
	Arena.Send("AS", c.mode, table.concat({ oid, "Z", "1", "-", fid }, "~"), { to = c.A, urgent = true })
	F.Announce(fid)
	return true
end

-- A sign-up for an open slot (the design): the writer's checks, in order, and his answer.
function F.OnSlotSign(sender, mode, oid, what, rest)
	local f = Find("fights", oid)
	if not f or not Me(f.writer) or f.st ~= "O" then return Refuse("slot") end
	local gk, level, class, race = Arena.Fields(rest, 4)
	local function Answer(code) Arena.Send("AS", mode, oid .. "~" .. code, { to = sender }) return code end
	if what ~= "J" then return end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.Hides and M.Hides(sender) then return Answer("X") end
	if Arena.Sanctioned and Arena.Sanctioned(sender) then return Answer("X") end -- (1.1.6: WatchChat.Barred)
	if Blocked(sender, Gk(gk)) then return Answer("D") end
	if Gk(gk) and F.NoShows(Gk(gk), mode) >= F.NO_SHOWS_BLOCK then return Answer("B") end
	if not F.InCategory(f.cat, { level = tonumber(level), class = class, race = tonumber(race) }) then return Answer("C") end
	if SamePerson(sender, f.A.name) or SamePerson(sender, f.arb) then return Answer("C") end
	-- His gk is his own word until the weigh-in; one the game gives someone else is refused.
	local P = ns.ArenaProfile
	if Gk(gk) and P and P.VerifyGk and P.VerifyGk(sender, Gk(gk)) == false then return Answer("X") end
	f.signs = f.signs or {}
	f.signs[#f.signs + 1] = { name = ns.FullName(sender), gk = Gk(gk), at = Now() }
	Arena.Changed()
	return Answer("O")
end

-- Facts in a category (the sign-up's own word; the weigh-in checks again).
function F.InCategory(cat, x)
	x = x or {}
	local max = F.MaxLevel()
	local b = tostring(cat):match("^B(%d+)$")
	if b then local hi = tonumber(b) return x.level and x.level <= hi and x.level >= hi - 9 end
	if (x.level or 0) < max then return false end
	local class = tostring(cat):match("^C(%u%u)$")
	local race = tonumber(tostring(cat):match("^R(%d+)$"))
	if class then return x.class == class end
	if race then return x.race == race end
	return true
end

-- Sign up for an open slot (AS~J to its writer).
function F.Sign(fid)
	local f = Find("fights", fid)
	if not f or f.st ~= "O" then return false, "slot" end
	if not Arena.RulesAccepted() then return false, "rules" end
	local R = ns.Roster
	local classFile
	if UnitClass then classFile = select(2, UnitClass("player")) end
	local raceID
	if UnitRace then raceID = select(3, UnitRace("player")) end
	local body = table.concat({ fid, "J", MyGk() or "-", tostring(UnitLevel and UnitLevel("player") or 0),
		classFile and R and R.ClassCode and R.ClassCode(classFile) or "-", tostring(raceID or "-") }, "~")
	Arena.Send("AS", f.mode, body, { to = f.writer })
	return true
end

-- The writer books a signed fighter into the open slot.
function F.Book(fid, name)
	local f, why = Mine(fid)
	if not f then return false, why end
	if f.st ~= "O" then return false, "state" end
	local who
	for _, s in ipairs(f.signs or {}) do if Same(s.name, name) then who = s end end
	if not who then return false, "sign" end
	f.B = { name = who.name, gk = who.gk }
	DropFlag(f, "o")
	local was = f.st
	f.st = "A"
	f.accepted.B = true
	SendAF(f, true)
	if f.marketSpecs and OpenMarkets(f) then SendAF(f, true) end
	Changed(f, was)
	return true
end

---------------------------------------------------------------------------
-- Fight Night cards (AN, the design)
---------------------------------------------------------------------------

local Card = {}
F.Card = Card
local CARD_STATES = { P = true, L = true, D = true, X = true }
local CARD_ENDED = { D = true, X = true }

local function CleanTitle(s)
	s = tostring(s or ""):gsub("[%c|~,]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #s > F.TITLE_MAX then s = s:sub(1, F.TITLE_MAX) end
	return s
end

local function EncodeCard(c)
	local aw = c.awards or {}
	return table.concat({ c.cid, c.st, c.fl ~= "" and c.fl or "-", B36(c.no), B36(c.t0), B36(c.mapID), #c.fids > 0 and table.concat(c.fids, ",") or "-",
		(aw.fotn or "-") .. "." .. (aw.ko or "-") .. "." .. (aw.up or "-"), c.title ~= "" and c.title or "-" }, "~")
end

local function SendAN(c, urgent)
	c.sentAt = Now()
	Arena.Send("AN", c.mode, EncodeCard(c), { key = "an " .. c.cid, urgent = urgent })
end
Card.Send = SendAN

-- A card (a numbered Fight Night): by a promoter (the King, his Stewards and Hands, a public arbiter).
-- opts: { t0, mapID, zone, rehearsal }
function Card.New(title, t0, opts)
	opts = opts or {}
	local mode = Arena.NewMode(opts.rehearsal)
	if not ns.ArenaRoles.MayPromote(ns.me, mode) then return nil, "promoter" end
	local cid = Arena.NewId("N", function(id) return Find("cards", id) ~= nil end)
	if not cid then return nil, "id" end
	local store = Arena.Store(mode)
	store.cardNo = (tonumber(store.cardNo) or 0) + 1
	local c = { cid = cid, mode = mode, st = "P", fl = "", no = store.cardNo, t0 = tonumber(t0) or Now(), mapID = tonumber(opts.mapID) or 0,
		zone = opts.zone, fids = {}, awards = {}, title = CleanTitle(title), promoter = ns.me, heardAt = Now() }
	Put("cards", c)
	SendAN(c, true)
	Watch()
	return cid
end

function Card.Get(cid) return (Find("cards", cid)) end

local function MyCard(cid)
	local c = Find("cards", cid)
	if not c then return nil, "card" end
	if not Me(c.promoter) then return nil, "promoter" end
	return c
end

-- A bout on the card: a new fight (fid made here) or one of ours, at pos (default: last).
function Card.AddBout(cid, fidOrOpts, pos)
	local c, why = MyCard(cid)
	if not c then return nil, why end
	if #c.fids >= F.BOUTS_MAX then return nil, "full" end
	local fid = fidOrOpts
	if type(fidOrOpts) == "table" then
		local o = {}
		for k, v in pairs(fidOrOpts) do o[k] = v end
		o.card, o.rehearsal = cid, c.mode == "T"
		o.arb = o.arb or ns.me
		fid, why = F.New(o)
		if not fid then return nil, why end
	end
	local f = Find("fights", fid)
	if not f or f.card ~= cid then return nil, "fight" end
	table.insert(c.fids, math.max(1, math.min(tonumber(pos) or (#c.fids + 1), #c.fids + 1)), fid)
	SendAN(c, true)
	return fid
end

function Card.Drop(cid, fid)
	local c, why = MyCard(cid)
	if not c then return false, why end
	for i, x in ipairs(c.fids) do
		if x == fid then
			local f = Find("fights", fid)
			if f and not (f.st == "D" or f.st == "A" or f.st == "O") then return false, "state" end
			table.remove(c.fids, i)
			if f and f.st ~= "D" then F.Void(fid, "cancel") end
			SendAN(c, true)
			return true
		end
	end
	return false, "fight"
end

-- The promoter re-assigns a bout's arbiter (a public arbiter; the promoter writes its AF).
function Card.SetArbiter(cid, fid, name)
	local c, why = MyCard(cid)
	if not c then return false, why end
	local f = Find("fights", fid)
	if not f or f.card ~= cid then return false, "fight" end
	local arb = Arena.Name(name or "")
	if not arb or not ns.ArenaRoles.IsPublicArbiter(arb, c.mode) then return false, "arbiter" end
	if SamePerson(arb, f.A.name) or (f.B and SamePerson(arb, f.B.name)) then return false, "arbiter-fighter" end
	-- (Its markets open: their sheet is its writer's, who alone closes and settles it; a list of
	-- markets of its own never travels to another arbiter, F.New.)
	if (Has(f.fl, "m") or (f.marketList and f.marketSpecs)) and not Same(arb, f.writer) then return false, "markets" end
	f.arb, f.writer = arb, arb
	SendAF(f, true)
	Arena.Changed()
	return true
end

-- The Fight of the Night (the promoter's pick, the design); the other two awards are worked out.
function Card.SetFotN(cid, fid)
	local c, why = MyCard(cid)
	if not c then return false, why end
	local ok = false
	for _, x in ipairs(c.fids) do if x == fid then ok = true end end
	if not ok then return false, "fight" end
	c.awards = c.awards or {}
	c.awards.fotn = fid
	SendAN(c, true)
	return true
end

-- The fastest knockout and the biggest upset (the lowest expectation below 0.5 among winners).
function Card.Awards(cid)
	local c = Find("cards", cid)
	if not c then return nil end
	local fastest, ko, upset, low = nil, nil, nil, 500
	local LG = ns.ArenaLedger
	for _, fid in ipairs(c.fids) do
		local f = Find("fights", fid)
		if f and State(f) == "F" then
			for _, x in pairs(f.rounds or {}) do
				if x.m == "K" and x.dur and (not fastest or x.dur < fastest) then fastest, ko = x.dur, fid end
			end
			if LG and LG.Expected and f.w then
				local e = LG.Expected(f[f.w].gk, f[Other(f.w)].gk)
				if e and e < low then low, upset = e, fid end
			end
		end
	end
	c.awards = c.awards or {}
	c.awards.ko, c.awards.up = ko, upset
	return c.awards
end

function Card.State(cid)
	local c = Find("cards", cid)
	if not c then return nil end
	local all, void, live = #c.fids > 0, #c.fids > 0, false
	for _, fid in ipairs(c.fids) do
		local f = Find("fights", fid)
		local st = f and State(f) or "A"
		if not ENDED[st] then all = false end
		if st ~= "V" then void = false end
		if LIVE[st] or st == "R" then live = true end
	end
	if void then return "X" end
	if all then return "D" end
	if live then return "L" end
	return "P"
end

function F.CardTick(c, now)
	local st = Card.State(c.cid)
	if st ~= c.st then
		c.st = st
		if CARD_ENDED[st] then c.endedAt = c.endedAt or now else c.endedAt = nil end
		if st == "D" then Card.Awards(c.cid) end
		SendAN(c, true)
		ns.Fire("ARENA_CARD", c.cid, st)
		return
	end
	local gap = st == "L" and F.CARD_LIVE or F.CARD_PLANNED
	if st ~= "D" and st ~= "X" and now - (c.sentAt or 0) >= gap then SendAN(c) end
end

-- AN: from a promoter; the first fixes him.
local function OnCard(dist, sender, mode, body)
	local cid, st, fl, no, t0, mapID, fids, awards, title = Arena.Fields(body, 9)
	if not title then return Refuse("shape") end
	if not cid:find("^N[0-9a-z]+$") or not CARD_STATES[st] then return Refuse("shape") end
	if not ns.ArenaRoles.MayPromote(sender, mode) then return Refuse("promoter") end
	if not MadeBy(cid, sender) then return Refuse("hash") end
	local c = Find("cards", cid)
	if c and not Same(sender, c.promoter) then return Refuse("promoter") end
	c = c or { cid = cid, mode = mode, promoter = ns.FullName(sender) }
	local list = {}
	if fids ~= "-" then
		for fid in fids:gmatch("[^,]+") do
			if fid:find("^F[0-9a-z]+$") and #list < F.BOUTS_MAX then list[#list + 1] = fid end
		end
	end
	local fotn, ko, up = awards:match("^([^.]*)%.([^.]*)%.([^.]*)$")
	local was = c.st
	c.st, c.fl, c.no, c.t0, c.mapID = st, fl ~= "-" and fl or "", N(no, 0, 99999) or 0, N(t0, 0, 4294967295) or 0, N(mapID, 0, 99999) or 0
	c.fids = list
	c.awards = { fotn = fotn ~= "-" and fotn or nil, ko = ko ~= "-" and ko or nil, up = up ~= "-" and up or nil }
	c.title = title ~= "-" and CleanTitle(title) or ""
	c.heardAt = Now()
	if CARD_ENDED[st] then c.endedAt = c.endedAt or c.heardAt else c.endedAt = nil end
	Put("cards", c)
	if was ~= st then ns.Fire("ARENA_CARD", cid, st) end
	Arena.Changed()
end
ns.Comm.Handle("AN", ns.Arena.Handle("AN", OnCard))

-- The title a card shows on the King's screen: its own only when the King set it (the design).
function Card.ScreenTitle(cid)
	local c = Find("cards", cid)
	if not c then return nil end
	if ns.ArenaRoles.IsKing(c.promoter) and c.title ~= "" then return c.title end
	return L.ARENA_CARD_NO:format(c.no or 0)
end

---------------------------------------------------------------------------
-- The events registry (markets learn of an event here), the week, the events list
---------------------------------------------------------------------------

Arena.Events.Register("F", function(fid)
	local f = Find("fights", fid)
	if not f then return nil end
	return { kind = "fight", opener = f.writer, fighters = { A = { name = f.A.name, gk = f.A.gk }, B = f.B and { name = f.B.name, gk = f.B.gk } or nil },
		category = f.cat, public = Has(f.fl, "p"), mode = f.mode, lockAt = f.lockAt, bo = f.bo, state = State(f), card = f.card, tid = f.tid,
		arbiter = f.arb }
end)
Arena.Events.Register("N", function(cid)
	local c = Find("cards", cid)
	if not c then return nil end
	return { kind = "card", opener = c.promoter, fights = c.fids, public = true, mode = c.mode, lockAt = nil, t0 = c.t0, state = c.st }
end)

---------------------------------------------------------------------------
-- Stable rooms in the main addon's Chat page
---------------------------------------------------------------------------

-- The Chat page owns tabs and pins; the Arena owns the stable identity and lifecycle behind one.
-- A host which knows dynamic tabs implements ChatWindow.OpenDynamicRoom(spec). Older builds get
-- ARENA_CHAT_OPEN with the same spec, so an adapter can open it without coupling this core file to
-- ChatWindow or the companion's UI.
Arena.CHAT_ROOM_KEEP_AFTER = 1800
local roomCompleted = {}

local function RoomPhase(ev)
	local st = type(ev) == "table" and ev.state or nil
	if type(ev) ~= "table" then return nil end
	if ev.kind == "fight" then
		if ENDED[st] then return "complete" end
		if st == "R" then return "settling" end
		if LIVE[st] then return "live" end
		return "upcoming"
	end
	if ev.kind == "card" then
		if CARD_ENDED[st] then return "complete" end
		return st == "L" and "live" or "upcoming"
	end
	if ev.kind == "tourney" then
		if st == "F" or st == "X" then return "complete" end
		return (st == "D" or st == "L") and "live" or "upcoming"
	end
	return nil
end

local function RoomRecord(id, kind)
	if kind == "fight" then return Find("fights", id) end
	if kind == "card" then return Find("cards", id) end
	local T = kind == "tourney" and ns.ArenaTourney or nil
	if type(T) == "table" and type(T.Find) == "function" then
		local ok, t = pcall(T.Find, id)
		if ok and type(t) == "table" then return t end
	end
	return nil
end

local function RoomTitle(id, ev)
	if ev.kind == "fight" then
		local fighters = type(ev.fighters) == "table" and ev.fighters or {}
		local function Name(side)
			local p = fighters[side]
			local name = type(p) == "table" and p.name or p
			return type(name) == "string" and ns.ShortName(ns.FullName(name)) or "?"
		end
		return L.ARENA_WEEK_FIGHT:format(Name("A"), Name("B"))
	end
	if ev.kind == "card" then return Card.ScreenTitle(id) or L.ARENA_CARD_NO:format(0) end
	local T = ev.kind == "tourney" and ns.ArenaTourney or nil
	if type(T) == "table" and type(T.ScreenTitle) == "function" then
		local ok, title = pcall(T.ScreenTitle, id)
		if ok and type(title) == "string" and title ~= "" then return title end
	end
	return L.ARENA_TOURNEY
end

local function RoomParticipants(ev)
	local out, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		name = ns.FullName(name)
		local key = name:lower()
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = name
	end
	local fighters = type(ev.fighters) == "table" and ev.fighters or {}
	for _, side in ipairs({ "A", "B" }) do
		local p = fighters[side]
		Add(type(p) == "table" and p.name or p)
	end
	Add(ev.opener)
	return out
end

-- Canonical metadata consumed by both Arena entry points and the main Chat page. The key and id
-- never depend on a translated title or mutable state.
function Arena.ChatRoom(id)
	local ev = Arena.EventOf(id)
	local phase = RoomPhase(ev)
	if not phase then return nil end
	local rec = RoomRecord(id, ev.kind)
	if phase == "complete" then
		roomCompleted[id] = roomCompleted[id] or (rec and tonumber(rec.endedAt)) or Now()
	else
		roomCompleted[id] = nil
	end
	local completedAt = roomCompleted[id]
	local retainUntil = completedAt and (completedAt + Arena.CHAT_ROOM_KEEP_AFTER) or nil
	local active = phase ~= "complete"
	return {
		key = "arena:" .. id, id = id, kind = ev.kind == "fight" and "fight" or "event", eventKind = ev.kind,
		audience = ev.kind == "fight" and "duel" or "event", access = ev.public == true and "members" or "participants",
		title = RoomTitle(id, ev), state = ev.state, phase = phase, active = active,
		completedAt = completedAt, retainFor = Arena.CHAT_ROOM_KEEP_AFTER, retainUntil = retainUntil,
		recoverable = active or (retainUntil ~= nil and Now() < retainUntil),
		opener = ev.opener, fighters = ev.fighters, participants = RoomParticipants(ev),
		supportsBets = ev.kind == "fight", supportsComments = true,
	}
end

-- Tell the Chat host that an already-open/pinned room changed phase. This is deliberately one
-- spec argument: no Chat implementation has to look the event up again and race its next word.
function Arena.ChatRoomChanged(id)
	local spec = Arena.ChatRoom(id)
	if not spec then return false end
	ns.Fire("ARENA_CHAT_ROOM", spec)
	return spec
end

-- True means a current Chat host accepted the request. False means the compatibility event was
-- fired instead; in both cases the second result is the exact canonical spec. The host opens it as
-- every pending conversation opens (ChatRooms.OpenMatter, the owner's pattern): its tab with the
-- Olympus window in front, pinned while the event lives for a party to it (a fighter, the arbiter
-- or promoter who writes it: the spec's participants); a spectator's tab opens unpinned.
function Arena.OpenChatRoom(id)
	local spec = Arena.ChatRoom(id)
	if not spec then return false, nil end
	local host = ns.ChatWindow
	-- Core's update-without-restart stand-in answers every unknown method with a no-op; only an
	-- actual host field counts as support for dynamic rooms.
	local open = type(host) == "table" and not host.missing and rawget(host, "OpenDynamicRoom") or nil
	local R = rawget(ns, "ChatRooms")
	if type(open) == "function" and type(R) == "table" and type(R.OpenMatter) == "function" then
		local party = false
		for _, name in ipairs(spec.participants) do if Me(name) then party = true break end end
		local ok, pane = pcall(R.OpenMatter, { spec = spec, keep = party })
		if ok and pane then return true, spec end
	end
	ns.Fire("ARENA_CHAT_OPEN", spec)
	return false, spec
end

ns.On("ARENA_FIGHT", function(id) Arena.ChatRoomChanged(id) end)
ns.On("ARENA_CARD", function(id) Arena.ChatRoomChanged(id) end)
ns.On("ARENA_TOURNEY", function(id) Arena.ChatRoomChanged(id) end)

-- The Board's week (Week.providers): public fights and cards announced, read-only rows.
function F.WeekRows(now)
	now = now or Now()
	local out = {}
	for _, c in ipairs(All("cards")) do
		if c.mode == "L" and (c.st == "P" or c.st == "L") and (c.t0 or 0) >= now - 6 * 3600 then
			out[#out + 1] = { at = c.t0, title = Card.ScreenTitle(c.cid), tip = L.ARENA_WEEK_CARD_TIP:format(#c.fids) }
		end
	end
	for _, f in ipairs(All("fights")) do
		if f.mode == "L" and Has(f.fl, "p") and not f.card and (f.st == "A" or f.st == "S" or LIVE[f.st]) then
			out[#out + 1] = { at = f.tCall or f.tAnn or now, title = L.ARENA_WEEK_FIGHT:format(ns.ShortName(f.A.name), f.B and ns.ShortName(f.B.name) or "?") }
		end
	end
	return out
end
do
	local W = rawget(ns, "Week")
	if type(W) == "table" and type(W.providers) == "table" then table.insert(W.providers, function(now) return F.WeekRows(now) end) end
end

-- The events list (the owner's ask, 2026-09-30, for the Arena window's one switchable view): the
-- Fight Nights and tournaments, and the standalone public fights: live first, then upcoming by
-- time, then the ended ones newest first. Titles are the King's-screen ones (Card.ScreenTitle,
-- ArenaTourney.ScreenTitle): a promoter's own words only when he is the King.
--   F.Events(opts) -> { { kind = "card"|"tourney"|"fight", id, title, at, state, live, upcoming, ended,
--     promoter, count (bouts or entrants), mode }, ... }; opts: { mode, limit (default 20), kinds = set }
function F.Events(opts)
	opts = opts or {}
	local out = {}
	local function Add(e)
		if opts.mode and e.mode ~= opts.mode then return end
		if opts.kinds and not opts.kinds[e.kind] then return end
		out[#out + 1] = e
	end
	for _, c in ipairs(All("cards")) do
		local st = c.st
		Add({ kind = "card", id = c.cid, title = Card.ScreenTitle(c.cid), at = c.t0, state = st, live = st == "L", upcoming = st == "P",
			ended = st == "D" or st == "X", promoter = c.promoter, count = #c.fids, mode = c.mode })
	end
	local T = ns.ArenaTourney
	if type(T) == "table" and type(T.All) == "function" then
		for _, t in ipairs(T.All()) do
			Add({ kind = "tourney", id = t.tid, title = T.ScreenTitle(t.tid), at = t.tStart, state = t.st,
				live = t.st == "D" or t.st == "L", upcoming = t.st == "R" or t.st == "K", ended = t.st == "F" or t.st == "X",
				promoter = t.promoter, count = T.Count and T.Count(t) or 0, mode = t.mode })
		end
	end
	for _, f in ipairs(All("fights")) do
		if Has(f.fl, "p") and not f.card and not f.tid then
			local st = State(f)
			Add({ kind = "fight", id = f.fid, title = L.ARENA_WEEK_FIGHT:format(ns.ShortName(f.A.name), f.B and ns.ShortName(f.B.name) or "?"),
				at = f.lockAt or f.tCall or f.tAnn, state = st, live = LIVE[st] or st == "R", upcoming = st == "A" or st == "O" or st == "S",
				ended = ENDED[st] or false, promoter = f.writer, count = 2, mode = f.mode })
		end
	end
	local function Rank(e) return e.live and 1 or (e.upcoming and 2 or 3) end
	table.sort(out, function(a, b)
		local ra, rb = Rank(a), Rank(b)
		if ra ~= rb then return ra < rb end
		if ra == 3 then return (a.at or 0) > (b.at or 0) end
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
		return a.id < b.id
	end)
	local limit = tonumber(opts.limit) or 20
	for i = #out, limit + 1, -1 do out[i] = nil end
	return out
end

---------------------------------------------------------------------------
-- Actions (every screen button goes through Arena.Can / Arena.Do)
---------------------------------------------------------------------------

Arena.Action("fights.challenge", function(opponent, opts) return F.CanChallenge(opponent, opts) end,
	function(opponent, opts) return F.Challenge(opponent, opts) end)
Arena.Action("fights.answer", nil, function(oid, yes, why) return F.Answer(oid, yes, why) end)
Arena.Action("fights.judge", nil, function(oid, yes, why) return F.Judge(oid, yes, why) end)
Arena.Action("fights.askArbiter", nil, function(oid, name) return F.AskArbiter(oid, name) end)
Arena.Action("fights.new", nil, function(opts) return F.New(opts) end)
Arena.Action("fights.announce", nil, function(fid) return F.Announce(fid) end)
Arena.Action("fights.accept", nil, function(fid) return F.Accept(fid) end)
Arena.Action("fights.sign", nil, function(fid) return F.Sign(fid) end)
Arena.Action("fights.book", nil, function(fid, name) return F.Book(fid, name) end)
Arena.Action("fights.call", nil, function(fid) return F.Call(fid) end)
Arena.Action("fights.extend", nil, function(fid) return F.Extend(fid) end)
Arena.Action("fights.here", nil, function(fid) return F.Here(fid) end)
Arena.Action("fights.bell", function() if Arena.Blocked() then return false, "blocked" end return true end,
	function(fid, override) return F.Bell(fid, override) end)
Arena.Action("fights.next", nil, function(fid) return F.NextRound(fid) end)
Arena.Action("fights.rule", nil, function(fid, side, m) return F.Rule(fid, side, m) end)
Arena.Action("fights.walkover", nil, function(fid, side) return F.Walkover(fid, side) end)
Arena.Action("fights.void", nil, function(fid, code) return F.Void(fid, code) end)
Arena.Action("fights.nocontest", nil, function(fid, code) return F.NoContest(fid, code) end)
Arena.Action("fights.dq", nil, function(fid, side, code) return F.Disqualify(fid, side, code) end)
Arena.Action("fights.correct", nil, function(fid, round, side, m) return F.Correct(fid, round, side, m) end)
Arena.Action("card.new", function() return ns.ArenaRoles.MayPromote(ns.me, Arena.NewMode()) end, function(title, t0, opts) return Card.New(title, t0, opts) end)
Arena.Action("card.bout", nil, function(cid, x, pos) return Card.AddBout(cid, x, pos) end)
Arena.Action("card.arbiter", nil, function(cid, fid, name) return Card.SetArbiter(cid, fid, name) end)
Arena.Action("card.fotn", nil, function(cid, fid) return Card.SetFotN(cid, fid) end)

-- At login: what this character is part of goes on (the ticker, the duel lines) where saved data
-- kept it.
ns.On("LOGIN", function()
	for _, f in ipairs(All("fights")) do
		if Involved(f) and (LIVE[f.st] or f.st == "S") then HookSystem() end
	end
	Watch()
end)
