local ADDON, ns = ...

-- 1.2, the Blood Arena: Markets.lua. A stub the arena's core created for the markets (markets) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Sheets (BM), books (BO), slips and tickets (BS, BK), overrules (BV), quotes and view models.
-- Registers BM BO BS BK BV. A long keyed BM/BO goes through Arena.Send with o.key (ArenaNet
-- rebuilds its pieces at its turn, the design).
-- API (the design):
--   Opener: Markets.Open(eid, spec), Markets.SetLock(eid, lockAt), Markets.Declare(eid, results),
--     Markets.Void(eid, idx|"*", code), Markets.Has(eid)
--   Leaders: Markets.Overrule(eid, idx, code)
--   Bettor: Markets.Quote(eid, idx, o, silver) -> { ok, why, odds, payout, fee = { g, a }, cap, after },
--     Markets.Bet(eid, idx, o, silver, queued) -> ticket, Markets.Tickets(filter)
--   View: Markets.View(eid) -> { lockAt, bank, cur, fee, markets = { { idx, type, label, state,
--     result, outcomes = { { o, label, pool, count, odds } } } } }, Markets.Public()
-- Events come from Arena.EventOf(eid) (fights F/N, tournaments T, Farkle K, the Lottery's day L).
local Markets = {}
ns.Markets = Markets

local L = ns.L

-- the markets (the design, as amended). One writer per object (the design):
--   the SHEET (BM), what can be bet and when, is the event's opener's (Arena.EventOf(eid).opener);
--   the BOOK (BO), the pools, is the bank's the sheet names (MarketBank.lua, on the bank's client);
--   a BET is the bettor's slip (BS, whispered to that bank) and the bank's acceptance, which is the
--   ledger's b entry itself (Wallet.OnEntry: the ticket is matched on its full tuple, event,
--   market, outcome, stake and random nonce, never on a wallet code, which is blinded);
--   an OVERRULE (BV) is a leader's word, weighted, never from anyone with an interest in the event.
-- Nothing another player sends puts free text on a screen: every label comes from the event
-- (names through King.CleanName) or from this file's fixed words.
--
-- The messages (numbers in base 36, times server time; the design):
--   BM~<M>1~eid~rev~bank|-~cur~g.a.to~lockAt~rounds~scratched~idx:type:param:n:state[:result:t];...
--     cur g (gold) | p (glory points) | c (chips, T only); g.a the guild's and the arbiter's parts of
--     the fee in basis points, to = a (the arbiter's wallet) or g (the guild: the King arbitrates,
--     no arbiter, points and chips); rounds: a series' round winners ("AB"), or a tournament's
--     bracket size once it is known ("S8"), or -; scratched: entrant numbers withdrawn ("3.b") or
--     -; state O open, L locked, R declared, V void; result: the winning outcomes "+"-joined, "!"
--     after them when the arbiter declared against the game's duel line, "P<hex>" for a bracket
--     pool, "<n1>.<n2>.<n3>.<n4>.<n5>" (four digits each, 0000-9999) for the Lottery's draw, the
--     void's code when V; t: when it was declared or voided. A rev moves a market only O -> L -> R,
--     R -> R (a correction) or to V (final). The Lottery's version-2 param is "2", or
--     "2.<from eid>.<copper b36>" when it carries a pot. Versionless one-head sheets are refused.
--   BO~<M>1~eid~sheetRev~epoch.n~t~lag~idx:state:pools:counts[:result];...   (MarketBank.lua)
--     state O | L | S settled | V void | H held; pools in silver, counts per outcome ("."-joined);
--     a bracket pool has one pool and one count (its entries); result: S the outcomes paid (a
--     bracket pool: P<hex>.<top>.<winners>; the Lottery: L2.<animal>...<animal>.<carry b36>), V
--     the void's code.
--   BS~<M>1~eid~idx~o~silver~nonce       whispered to the sheet's bank; nonce: 6 random characters
--   BK~<M>1~eid~nonce~code               the bank's answer: a refusal (not C), or K (a stake market's
--                                        acceptance, or a nonce already taken with the same tuple)
--   BV~<M>1~eid~idx|*~V|H|P~t            a leader's overrule, on the channel only (it names the event
--                                        only; a whispered one is refused: the auditors must see it)
--   BF (MarketBank.lua)                  a flag, whispered to auditors only
--
-- WHAT OTHER PACKAGES CALL (the exact functions; see each one below):
--   the fights part (the fight's arbiter, the tournament's promoter): Open, AddMarkets, SetLock, CloseBets (the
--     Bell: lockAt = now + Arena.LastCall), Declare, Void, Scratch, SetSize, FightReady ("Fight!").
--   the Bones tables (the Farkle table's arbiter): Open with FK, Declare; on the bank MarketBank.SetGate("K", fn)
--     (settles only when the arbiter's KE agrees with a player's, the design). A public table whose
--     host let the crowd bet: Open with one MW (the crowd's winner market), Declare or Void.
--   the screens (the screens): View, Public, Quote, Tickets, Ticket, Arena.Can/Do("bet", ...),
--     Arena.Can/Do("overrule", ...), the events MARKETS_OPEN, MARKETS_CLOSING, MARKETS_SETTLED.
--   the Lottery (the Menagerie Lottery, the design): see "The Lottery" below: Open with one LO market
--     (or OpenLottery), SetLock, Declare with the prizes (or DeclareDraw), Void, Carry, BeastOf;
--     on the bank MarketBank.SetGate("L", fn) (the draw's five server rolls, seen by the bank).
-- WHAT THIS FILE CALLS (the money part's documented interfaces, looked up at call time, so a missing one
-- refuses rather than breaks): Wallet.OnEntry, Wallet.Statement, Wallet.Online, Debts.SendClaim,
-- Standing.Cap; and on the bank MarketBank.lua's (see there).

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

Markets.SILVER, Markets.GOLD = 100, 10000
Markets.MAX_MARKETS = 40             -- markets on one sheet
Markets.POT_MAX = 2147483647         -- a Lottery pot carried in, copper (ArenaMath's bound on one stake)
Markets.GRACE = 300                  -- seconds between a declaration and the payout (the design)
Markets.HOLD_MAX = 86400             -- a hold nobody rules on is resolved after this long (the design)
Markets.GATE_WAIT = 86400            -- a settlement gate still saying "wait" this long after the grace holds the market
Markets.CARRY_WAIT = 86400           -- a Lottery day waits this long for carry promised by its source ledger
Markets.NO_RESULT = 1800             -- a fight's markets with no result this long after the lock: void G
Markets.TOURNEY_MAX = 172800         -- ... a tournament's
Markets.TABLE_MAX = 21600            -- ... a Bones table's (its game locks at the first throw and is
                                     -- declared after the last, the agreement and the grace: hours at 10,000)
Markets.LOCK_AHEAD_MAX = 14 * 86400  -- lockAt at most this far ahead
Markets.SHEET_WAIT = 60              -- a sheet (or a book) that came before its event (or sheet) waits this long
Markets.SHEET_SLACK = 30             -- receivers' slack on the open window and the last call (the send queue's delay)
Markets.PRIVATE_OPEN = 5             -- a private sheet's shortest window (a Farkle table's, a 1v1's stakes)
Markets.OPEN_SLACK = 90              -- a sheet heard at rev 1 by a client online this long opened at most this long before
Markets.BOOK_OPEN_SLACK = 5          -- a book saying O is taken until lockAt + this
Markets.FEE_CHANGE = 600             -- a sheet opened under the previous fee word is taken this long after a change
Markets.UI_CLOSE_EARLY = 3           -- the bettor's button greys out this long before lockAt
Markets.SLIP_GAP = 2                 -- a bettor's slips at most one every 2 s ...
Markets.SLIPS_EVENT = 20             -- ... and 20 per event
Markets.ACK_WAIT = 20                -- seconds after the bank's lag before a slip goes again (same nonce)
Markets.TRIES = 3                    -- sends of one slip at most, then "unconfirmed"
Markets.KEY_WAIT = 10                -- after an E (no verified key), the slip goes again once, this later
Markets.FIGHT_WAIT = 30              -- "Fight!" without the bank's locked book: this long after lockAt
Markets.KO_EARLY = 20                -- a flee in the first 20 s voids the knockout market (N)
Markets.BANK_HEARD = 180             -- a bank heard (BO, BK) this recently counts as online
Markets.CAPPED = { KO = true, B3 = true }  -- the losing fighter controls them (the design)
Markets.CAPPED_BET = 5 * Markets.GOLD      -- their bet cap ...
Markets.CAPPED_POOL_DIV = 10               -- ... and a tenth of the main market's pool cap
-- The props a fighter's own screen could fake are trials in T only until in-game check 3 passes
-- (UNIT_COMBAT readable for party tokens); set true there, and they run in L too.
Markets.LIVE_PROPS = { DU = false, FB = false, BH = false }
-- The opener's sheet repeats (the design), and a leader's overrule's.
Markets.REPEAT_OPEN, Markets.REPEAT_OPEN_LONG = 60, 300
Markets.REPEAT_LOCKED, Markets.REPEAT_GRACE = 120, 60
Markets.REPEAT_AFTER, Markets.REPEAT_AFTER_FOR = 300, 1800
Markets.LONG_OPEN = 3600             -- a sheet locking further off than this repeats as a tournament's does
Markets.BV_REPEAT, Markets.BV_AFTER = 120, 1800
-- Storage (the design): tickets per character, events kept.
Markets.TICKETS_MAX, Markets.TICKET_KEEP = 400, 90 * 86400
Markets.EVENTS_MAX, Markets.EVENT_KEEP = 60, 7 * 86400
Markets.AUDIT_EVENTS, Markets.AUDIT_FLAGS = 30, 200
Markets.PRUNE_EVERY = 3600

-- The winning class market's outcomes, in a fixed order (the classes of this client).
Markets.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_INDEX = {}
for i, c in ipairs(Markets.CLASSES) do CLASS_INDEX[c] = i end

-- The market kinds (the design). event: the event kinds it belongs to; n: its outcomes
-- (entrants: one per entrant; pick: the bracket's size); k: winners (reaches the final, the
-- semifinal, the quarterfinal); param: what the sheet's param holds; stake: a 1v1's own stakes
-- (private, only the named parties, each on himself, exactly his stake); direct: no stakeholder;
-- trial: a prop that needs LIVE_PROPS in L; capped: KO and B3's smaller caps.
Markets.KINDS = {
	-- (The winner: a fight's, and the crowd's at a public Bones table, 2026-10-04.)
	MW = { event = { fight = true, farkle = true }, n = 2, self = "side" },
	SW = { event = { fight = true }, n = 2, self = "side", series = true },
	B3 = { event = { fight = true }, n = 4, series = true, bo = 3 },
	KO = { event = { fight = true }, n = 2 },
	DU = { event = { fight = true }, n = 2, trial = true, param = "line" },
	FB = { event = { fight = true }, n = 2, trial = true },
	BH = { event = { fight = true }, n = 2, trial = true },
	CH = { event = { tourney = true }, entrants = true, self = "entrant" },
	CC = { event = { tourney = true }, entrants = true, self = "entrant", category = true },
	RF = { event = { tourney = true }, entrants = true, k = 2 },
	RS = { event = { tourney = true }, entrants = true, k = 4 },
	RQ = { event = { tourney = true }, entrants = true, k = 8 },
	ST = { event = { tourney = true }, n = 5, param = "entrant", self = "stage" },
	WC = { event = { tourney = true }, n = #Markets.CLASSES },
	PK = { event = { tourney = true }, param = "fee", pick = true },
	CX = { event = { fight = true }, n = 2, param = "stakes", stake = true, private = true },
	FK = { event = { farkle = true }, n = 2, param = "stakes", stake = true, private = true },
	DR = { event = { fight = true, farkle = true }, n = 2, param = "stakes", direct = true, private = true },
	-- The Menagerie Lottery's day (the design; the Lottery's type name): 25 beasts, the pot carried in.
	LO = { event = { lottery = true }, n = 25, param = "carry", lottery = true },
}
local KINDS = Markets.KINDS
-- The void codes (the design): result while open, no start, the arbiter gone, interference,
-- one-sided, a stake missing, terms changed, no data, a tie, cancelled, leadership; the Lottery's:
-- R an unusable carry was left with its source ledger, C the carry a day names does not match the
-- exact unclaimed profit retained there.
Markets.VOIDS = { E = true, W = true, G = true, I = true, ["1"] = true, S = true, T = true, N = true, Z = true, X = true, L = true, R = true, C = true }

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Arena() return ns.Arena end
local function Roles() return ns.ArenaRoles end
local function Math() return ns.ArenaMath end
local function Now() return ns.Arena.Now() end
local function B36(n) return ns.Arena.B36(n) end
local function N36(s, lo, hi) return ns.Arena.N(s, lo, hi) end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b)
	local x = Lower(a)
	return x ~= nil and x == Lower(b)
end
Markets.Same = Same
local function Fn(t, k)
	local v = type(t) == "table" and t[k]
	return type(v) == "function" and v or nil
end
local function Call(t, k, ...)
	local f = Fn(t, k)
	if not f then return nil end
	local ok, a, b, c, d = pcall(f, ...)
	if not ok then ns.Log("markets: %s failed: %s", tostring(k), tostring(a)) return nil end
	return a, b, c, d
end
Markets.Call = Call
-- A name as the event gives it (King.CleanName'd by its owner), for a label.
local function NameOf(p)
	if type(p) == "table" then p = p.name end
	if type(p) ~= "string" then return "?" end
	return ns.Arena.Mask(ns.DisplayName and ns.DisplayName(p) or p)
end
local function Changed() ns.Arena.Changed() end
local function EidOk(eid)
	return type(eid) == "string" and #eid >= 3 and #eid <= 20 and eid:find("^[FNTKL][0-9a-z]+$") ~= nil
end
Markets.EidOk = EidOk
-- An outcome as the wire and the ledger write it: its number in base 36, or a bracket's picks.
local function Sel(o) return type(o) == "number" and B36(o) or tostring(o) end
Markets.Sel = Sel

---------------------------------------------------------------------------
-- Where the markets live (the design): every event heard is a record { eid, mode, sheet, book,
-- words }. An event this client is involved in (it opened it, it holds it as the bank, it is a
-- party, it holds a ticket or gave an overrule on it) is kept in the core's store
-- (Arena.Store(mode).markets); every other one in the companion's (Arena.Heavy) while it is
-- loaded, else in memory only. The sim's stores are its own (Arena.Store gives them).
---------------------------------------------------------------------------

-- The core store of a mode as Arena.Store gives it, made only when create is true: an idle client
-- that only hears a public sheet writes nothing to its saved data (the weight rule).
local function StoreOf(mode, create)
	if create or ns.Arena.Sim() then return ns.Arena.Store(mode) end
	if type(ns.rdb) ~= "table" then return nil end
	if mode == "T" then return type(ns.rdb.arenaTest) == "table" and ns.rdb.arenaTest or nil end
	local a = ns.rdb.arena
	local r = type(a) == "table" and type(a.realms) == "table" and a.realms[ns.realm]
	return type(r) == "table" and r or nil
end
Markets.StoreOf = StoreOf
local memory = setmetatable({}, { __mode = "k" }) -- [mode, or the sim's store] = { [eid] = rec }
local function Tables(mode, create)
	local store = StoreOf(mode, create)
	local core = type(store) == "table" and store.markets or nil
	if type(store) == "table" and type(core) ~= "table" and create then
		core = {}
		store.markets = core
	end
	if type(core) ~= "table" then core = nil end
	local key = ns.Arena.Sim() and ns.Arena.Store(mode) or mode
	local mem = memory[key]
	if not mem then mem = {} memory[key] = mem end
	local heavy = ns.Arena.Heavy(mode)
	if type(heavy) == "table" and type(heavy.markets) ~= "table" then heavy.markets = {} end
	return core, heavy and heavy.markets or nil, mem, store
end
local function Rec(mode, eid)
	local core, heavy, mem = Tables(mode)
	return (core and core[eid]) or (heavy and heavy[eid]) or mem[eid]
end
Markets.Rec = Rec
-- The event's record and its mode: L first, then T.
local function Find(eid, mode)
	if mode then return Rec(mode, eid), mode end
	local r = Rec("L", eid)
	if r then return r, "L" end
	r = Rec("T", eid)
	if r then return r, "T" end
	return nil
end
Markets.Find = Find

local Involved -- (below)
-- Puts rec where it belongs now (the core when involved), out of the other tables.
local function Place(mode, rec)
	local involved = Involved(rec)
	local core, heavy, mem = Tables(mode, involved)
	local eid = rec.eid
	if core then core[eid] = nil end
	mem[eid] = nil
	if heavy then heavy[eid] = nil end
	if involved and core then core[eid] = rec
	elseif heavy then heavy[eid] = rec
	else mem[eid] = rec end
end
Markets.Place = Place
local function NewRec(mode, eid)
	local rec = { eid = eid, mode = mode, words = {}, heard = Now() }
	Place(mode, rec)
	return rec
end

-- The companion loaded: what memory held goes into its saved variables.
ns.On("ARENA_UI_LOADED", function()
	for _, mode in ipairs({ "L", "T" }) do
		local _, heavy, mem = Tables(mode)
		if heavy and mem then
			for eid, rec in pairs(mem) do
				if not heavy[eid] then heavy[eid] = rec end
				mem[eid] = nil
			end
		end
	end
end)

---------------------------------------------------------------------------
-- The event (Arena.EventOf, the design) and the people in it
---------------------------------------------------------------------------

-- The event, or nil: { kind = "fight"|"tourney"|"farkle"|"lottery", opener, fighters = { A = { name,
-- gk, fp, guild }, B = ... }, entrants = { [i] = { name, gk, fp, class, guild } }, category, public,
-- mode, lockAt, bo, size, drawn (a tournament's bracket is drawn: its bracket pool PK may open then,
-- the design), arbiter, promoter, director, excluded (more names that may neither bet nor overrule:
-- the Lottery's caller and bank), duel = { winner = "A"|"B", method, arbiter (the arbiter's client
-- recorded it), witnesses (independent witnesses who did) }, disagree (the witnesses, or the
-- Lottery's roll lines, disagree with the declaration: the bank holds, whenever it learns it) }. The
-- fields past the design's are read when present.
local function Event(eid) return ns.Arena.EventOf(eid) end

-- The compliance gate (Compliance.lua): a market of this type on an event of this kind, as a wager
-- (the Lottery's day a "lottery", a stake market a "stake", every other a "bet") and its game.
local WAGER_GAME = { fight = "fight", card = "fight", tourney = "fight", farkle = "bones", lottery = "lottery" }
function Markets.WagerOf(mtype, evKind)
	local k = KINDS[mtype]
	local kind = (k and k.lottery) and "lottery" or ((k and (k.stake or k.direct)) and "stake" or "bet")
	return kind, WAGER_GAME[evKind or ""]
end
-- Whether every market of the list may be opened or bet on here (1.1.6: none may).
local function Wagers(list, evKind)
	local C = ns.Compliance
	if type(C) ~= "table" or type(C.Allows) ~= "function" or type(list) ~= "table" then return false end
	for _, m in ipairs(list) do
		local kind, game = Markets.WagerOf(type(m) == "table" and m.type or nil, evKind)
		if C.Allows(kind, game) ~= true then return false end
	end
	return true
end
Markets.Wagers = Wagers
Markets.Event = Event

local function Fighters(ev)
	local out = {}
	local f = type(ev) == "table" and ev.fighters
	if type(f) == "table" then
		for _, side in ipairs({ "A", "B" }) do
			local p = f[side]
			if type(p) == "table" and type(p.name) == "string" then out[#out + 1] = { side = side, name = p.name, gk = p.gk, fp = p.fp, guild = p.guild } end
		end
	end
	return out
end
Markets.Fighters = Fighters
local function Entrants(ev)
	local e = type(ev) == "table" and ev.entrants
	return type(e) == "table" and e or {}
end
-- The people who may never bet on the event (the design): its opener, arbiter,
-- director and promoter.
local function Officials(ev, sheet)
	local out = {}
	local function Add(name) if type(name) == "string" and name ~= "" then out[#out + 1] = name end end
	if type(ev) == "table" then
		Add(ev.opener); Add(ev.arbiter); Add(ev.promoter); Add(ev.director)
		if type(ev.arbiter) == "table" then Add(ev.arbiter.name) end
		for _, name in ipairs(type(ev.excluded) == "table" and ev.excluded or {}) do Add(name) end
	end
	if type(sheet) == "table" then Add(sheet.from) end
	return out
end
Markets.Officials = Officials
-- The side ("A" | "B") a name fights on in the event, or nil.
local function SideOf(ev, name)
	for _, f in ipairs(Fighters(ev)) do if Same(f.name, name) then return f.side, f end end
	return nil
end
Markets.SideOf = SideOf
-- The entrant number of a name in a tournament, or nil.
local function EntrantOf(ev, name)
	for i, e in pairs(Entrants(ev)) do
		if type(e) == "table" and Same(e.name, name) then return i, e end
	end
	return nil
end
Markets.EntrantOf = EntrantOf

-- May sheets of this event go on the channel (a public event, with public markets)?
local function PublicEvent(ev)
	return type(ev) == "table" and ev.public ~= false
end

---------------------------------------------------------------------------
-- Sheets: read, write, check (the design)
---------------------------------------------------------------------------

local function ParseParam(kind, param)
	if param == "-" then
		if kind.param == nil then return true, nil end
		return nil
	end
	if kind.param == "line" then
		local v = N36(param, 1, 3600)
		return v ~= nil, v
	elseif kind.param == "entrant" then
		local v = N36(param, 1, 64)
		return v ~= nil, v
	elseif kind.param == "fee" then
		local v = N36(param, 1, 2147483647 / 100)
		return v ~= nil, v
	elseif kind.param == "carry" then
		-- Contract v2 is part of the immutable sheet terms. This deliberately makes a v2 sheet
		-- unreadable to the one-head parser, while this parser refuses its versionless form.
		if param == "2" then return true, { version = 2 } end
		local from, c = param:match("^2%.(L[0-9a-z]+)%.([0-9a-z]+)$")
		c = N36(c, 1, Markets.POT_MAX)
		if not from or not EidOk(from) or not c then return nil end
		return true, { version = 2, from = from, copper = c }
	elseif kind.param == "stakes" then
		local a, b = param:match("^([0-9a-z]+)%.([0-9a-z]+)$")
		a, b = N36(a, 1, 2147483647 / 100), N36(b, 1, 2147483647 / 100)
		return a ~= nil and b ~= nil, a and b and { a, b } or nil
	end
	return nil
end
Markets.ParseParam = ParseParam

-- A declared result's outcomes (a set of numbers) and whether it carries "!", or nil.
local function ReadResult(m, text)
	if type(text) ~= "string" then return nil end
	local kind = KINDS[m.type]
	if kind.pick then
		local hex = text:match("^P(%x+)$")
		return hex and { pick = hex:lower() } or nil
	end
	if kind.lottery then
		local nums = { text:match("^(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)$") }
		if #nums ~= 5 then return nil end
		local set, animals = {}, {}
		for i = 1, 5 do
			nums[i] = tonumber(nums[i])
			animals[i] = Markets.BeastOf(nums[i])
			set[animals[i]] = true
		end
		return { draw = nums, animals = animals, set = set, list = animals }
	end
	local body, bang = text:match("^([0-9a-z+]+)(!?)$")
	if not body then return nil end
	local set, list = {}, {}
	for part in (body .. "+"):gmatch("([^+]*)%+") do
		local o = N36(part, 1, m.n)
		if not o or set[o] then return nil end
		set[o] = true
		list[#list + 1] = o
	end
	local k = kind.k or 1
	if #list < 1 or #list > k then return nil end
	table.sort(list)
	return { set = set, list = list, against = bang == "!" }
end
Markets.ReadResult = ReadResult
-- The pot a Lottery market carries in, in copper (0 for none), and the day it rolled over from.
local function CarryIn(m)
	local v = type(m) == "table" and KINDS[m.type] and KINDS[m.type].lottery and m.value or nil
	if type(v) ~= "table" then return 0, nil end
	return tonumber(v.copper) or 0, v.from
end
Markets.CarryIn = CarryIn

-- Recompute the public, aggregate part of a v2 Lottery settlement from a sheet row and its pools.
-- A single synthetic ticket per animal is sufficient for refunds, claimed tranches, fee and carry;
-- individual ticket allocation remains the wallet ledger's job. `copperPools` distinguishes the
-- bank's in-memory copper pools from a published book's silver pools.
function Markets.LotterySettlement(m, pools, copperPools, feeBp)
	local kind = type(m) == "table" and KINDS[m.type]
	local Lo = ns.Lottery
	if not (kind and kind.lottery and type(m.value) == "table" and m.value.version == 2
		and Lo and Lo.Settle and type(pools) == "table") then return nil, "version" end
	local declared = ReadResult(m, m.result)
	if not declared then return nil, "result" end
	local tickets = {}
	for animal = 1, m.n do
		local stake = tonumber(pools[animal] or pools[Sel(animal)] or 0)
		if not stake or stake < 0 or stake ~= math.floor(stake) then return nil, "pool", animal end
		if not copperPools then stake = stake * 100 end
		if stake > 0 then tickets[#tickets + 1] = { id = ("pool.%02d"):format(animal), animal = animal, stake = stake } end
	end
	return Lo.Settle({ version = Lo.SETTLEMENT_VERSION, tickets = tickets, draw = declared.animals,
		carry = CarryIn(m), feeBp = feeBp == nil and Lo.DEFAULT_FEE_BP or feeBp })
end

-- A settled v2 Lottery book row's unclaimed profit (copper), including zero; nil for an
-- incompatible or non-lottery result.
function Markets.Rolled(b)
	if type(b) ~= "table" or b.state ~= "S" or type(b.result) ~= "string" then return nil end
	local Lo = ns.Lottery
	local r = Lo and Lo.DecodeResult and Lo.DecodeResult(b.result)
	return r and r.nextCarry or nil
end

-- The winners' ledger form: { "1", "a" } (text, as ArenaMath and the ledger compare them).
function Markets.Winners(m, res)
	if not res then return nil end
	if res.pick then return "P" .. res.pick end
	local out = {}
	for _, o in ipairs(res.list) do out[#out + 1] = Sel(o) end
	return out
end

local function ParseMarket(part)
	local idx, typ, param, n, state, result, t = part:match("^([0-9a-z]+):(%u[%u%d]):([^:]+):([0-9a-z]+):([OLRV])$")
	if not idx then
		idx, typ, param, n, state, result, t = part:match("^([0-9a-z]+):(%u[%u%d]):([^:]+):([0-9a-z]+):([OLRV]):([^:]+):([0-9a-z]+)$")
		if not idx or (state ~= "R" and state ~= "V") then return nil end
	elseif state == "R" or state == "V" then
		return nil
	end
	local kind = KINDS[typ]
	if not kind then return nil, "type" end
	idx = N36(idx, 1, Markets.MAX_MARKETS)
	n = N36(n, 1, 64)
	if not idx or not n then return nil end
	local okParam, value = ParseParam(kind, param)
	if not okParam then return nil, "param" end
	local m = { idx = idx, type = typ, param = param, value = value, n = n, state = state }
	if state == "R" then
		m.result, m.t = result, N36(t, 0)
		if not m.t or not ReadResult(m, result) then return nil, "result" end
	elseif state == "V" then
		if not Markets.VOIDS[result] then return nil, "result" end
		m.result, m.t = result, N36(t, 0)
		if not m.t then return nil end
	end
	return m
end

-- A sheet's body: the sheet, or nil and why (refused whole, the design).
function Markets.ReadSheet(body)
	local eid, rev, bank, cur, fee, lockAt, rounds, scratched, list = ns.Arena.Fields(body, 9)
	if not list then return nil, "shape" end
	if not EidOk(eid) then return nil, "eid" end
	rev = N36(rev, 1, 36 ^ 7)
	lockAt = N36(lockAt, 1)
	if not rev or not lockAt then return nil, "shape" end
	if bank ~= "-" then
		bank = ns.Arena.Name(bank)
		if not bank then return nil, "bank" end
	else
		bank = nil
	end
	if cur ~= "g" and cur ~= "p" and cur ~= "c" then return nil, "cur" end
	local g, a, to = fee:match("^([0-9a-z]+)%.([0-9a-z]+)%.([ag])$")
	g, a = N36(g, 0, 1000), N36(a, 0, 1000)
	if not g or not a or g + a > 1000 then return nil, "fee" end
	local s = { eid = eid, rev = rev, bank = bank, cur = cur, fee = { g = g, a = a, to = to }, lockAt = lockAt,
		scratched = {}, markets = {}, order = {} }
	if rounds ~= "-" then
		if rounds:find("^[AB]+$") and #rounds <= 5 then
			s.rounds = rounds
		else
			local size = rounds:match("^S([0-9a-z]+)$")
			size = N36(size, 2, 64)
			if not size then return nil, "rounds" end
			s.size = size
		end
	end
	if scratched ~= "-" then
		for part in (scratched .. "."):gmatch("([^.]*)%.") do
			local e = N36(part, 1, 64)
			if not e then return nil, "scratched" end
			s.scratched[e] = true
		end
	end
	if list == "" then return nil, "markets" end
	for part in (list .. ";"):gmatch("([^;]*);") do
		local m, why = ParseMarket(part)
		if not m then return nil, why or "market" end
		if s.markets[m.idx] then return nil, "idx" end
		s.markets[m.idx] = m
		s.order[#s.order + 1] = m.idx
		if #s.order > Markets.MAX_MARKETS then return nil, "count" end
	end
	return s
end

function Markets.SheetBody(s)
	local parts = {}
	for _, idx in ipairs(s.order) do
		local m = s.markets[idx]
		local p = ("%s:%s:%s:%s:%s"):format(B36(idx), m.type, m.param or "-", B36(m.n), m.state)
		if m.state == "R" or m.state == "V" then p = p .. ":" .. tostring(m.result) .. ":" .. B36(m.t or 0) end
		parts[#parts + 1] = p
	end
	local sc = {}
	for e in pairs(s.scratched or {}) do sc[#sc + 1] = e end
	table.sort(sc)
	for i, e in ipairs(sc) do sc[i] = B36(e) end
	local rounds = s.rounds or (s.size and ("S" .. B36(s.size))) or "-"
	return table.concat({ s.eid, B36(s.rev), s.bank and ns.FullName(s.bank) or "-", s.cur,
		B36(s.fee.g) .. "." .. B36(s.fee.a) .. "." .. s.fee.to, B36(s.lockAt), rounds, #sc > 0 and table.concat(sc, ".") or "-",
		table.concat(parts, ";") }, "~")
end

-- How many outcomes a market of this kind has on this event (rule 8), or nil when it cannot be
-- said yet (a bracket pool before the draw).
local function Outcomes(kind, ev, sheet)
	if kind.n then return kind.n end
	if kind.entrants then
		local n = 0
		for i in pairs(Entrants(ev)) do if type(i) == "number" and i > n then n = i end end
		return n > 0 and n or nil
	end
	if kind.pick then
		local size = (sheet and sheet.size) or (type(ev) == "table" and tonumber(ev.size)) or nil
		return size
	end
	return nil
end
Markets.Outcomes = Outcomes

local function Settings(realm)
	local R = Roles()
	return R and R.Settings and R.Settings(realm) or {}
end
Markets.Settings = Settings
-- The pool cap of a market in copper (KO and B3: a tenth).
local function PoolCap(m, settings)
	local cap = tonumber(settings.maxPool) or 1000 * Markets.GOLD
	if Markets.CAPPED[m.type] then cap = math.floor(cap / Markets.CAPPED_POOL_DIV) end
	return cap
end
Markets.PoolCap = PoolCap
local function BetCapOf(m, settings)
	local cap = tonumber(settings.maxBet) or 20 * Markets.GOLD
	if Markets.CAPPED[m.type] then cap = math.min(cap, Markets.CAPPED_BET) end
	return cap
end
Markets.BetCapOf = BetCapOf
-- A prop that needs the live switch's LIVE_PROPS in L (a trial in T).
local function TrialRefused(typ, mode)
	return KINDS[typ].trial and mode == "L" and not Markets.LIVE_PROPS[typ]
end
Markets.TrialRefused = TrialRefused
-- The first bets exist on this market (the kept book says so, or the bank's own index).
local function HasBets(rec, idx)
	local b = rec and rec.book and rec.book.markets[idx]
	if b then
		for _, c in ipairs(b.counts or {}) do if c > 0 then return true end end
	end
	local MB = ns.MarketBank
	local f = Fn(MB, "Count")
	if f then return (f(rec.mode, rec.eid, idx) or 0) > 0 end
	return false
end
Markets.HasBets = HasBets

-- The King's fee as this client saw it change: the word in force, and the one before it for
-- FEE_CHANGE after the King's word changed it (its own time, settings.at: every client then agrees
-- on when an old-fee sheet stops being taken, whenever each one checked a sheet).
local feeSeen = {} -- [realm] = { cur = { feeBp, arbBp }, prev, till }
function Markets.FeeOk(g, a, settings)
	local f, arb = tonumber(settings.feeBp) or 600, tonumber(settings.arbBp) or 200
	local now = Now()
	local m = feeSeen[ns.realm]
	if not m then
		m = { cur = { f, arb } }
		feeSeen[ns.realm] = m
	elseif m.cur[1] ~= f or m.cur[2] ~= arb then
		local at = tonumber(settings.at)
		if not at or at > now then at = now end
		m.prev, m.till, m.cur = m.cur, at + Markets.FEE_CHANGE, { f, arb }
	end
	if g + a == f and a == arb then return true end
	return m.prev ~= nil and now <= m.till and g + a == m.prev[1] and a == m.prev[2]
end

-- The moves a market may make from one rev to the next (besides staying): O -> L -> R, O -> R, R -> R
-- (a correction, the same state), and any to V.
local STEPS = { O = { L = true, R = true, V = true }, L = { R = true, V = true }, R = { V = true }, V = {} }

-- The shortest betting window (the design): a public sheet's is Arena.OpenMin (the
-- King's delay in it), a private one's PRIVATE_OPEN.
local function WindowMin(public) return public and ns.Arena.OpenMin(true) or Markets.PRIVATE_OPEN end
Markets.WindowMin = WindowMin

-- How long this client has been online (its login's second, LOGIN below).
local session = {}
function Markets.OnlineFor(now) return session.login and (now or Now()) - session.login or 0 end

-- The betting window (the design): a sheet with an open market locks at
-- least WindowMin after it opened and never under the last call from now. A receiver cannot know
-- when a sheet it did not see open was opened, so:
--   * a sheet heard for the first time, whatever its rev: the whole window ahead, less the send's
--     slack (a modified opener starting at rev 2 gains nothing; a member who logs in during the
--     window's last minute and a half sees that sheet from its next rev on);
--   * a later rev that moves lockAt: at least the last call from now, less the slack; and, when this
--     client heard the sheet's rev 1 while it had been online OPEN_SLACK already (its 60 s repeats
--     reach everyone online, so it opened at most OPEN_SLACK before), at least WindowMin from that
--     first hearing, less OPEN_SLACK (the opener's honest Bell always passes). A refused rev keeps
--     the rev before it: its later lockAt, never a shorter window.
function Markets.WindowOk(sheet, rec, kept, public, now, opts)
	opts = opts or {}
	local anyOpen = false
	for _, m in pairs(sheet.markets) do if m.state == "O" then anyOpen = true end end
	if not anyOpen then return true end
	local slack = opts.self and 0 or Markets.SHEET_SLACK
	local window, last = WindowMin(public), ns.Arena.LastCall(public)
	if opts.self or not kept then
		if sheet.lockAt < now + window - slack then return nil, "window" end
	elseif sheet.lockAt ~= kept.lockAt then
		if sheet.lockAt < now + last - slack then return nil, "soon" end
		if rec and rec.tight and sheet.lockAt < (rec.opened or now) + window - Markets.OPEN_SLACK then return nil, "window" end
	end
	return true
end

-- The design's nine rules, as amended. sheet: read; sender: the server's;
-- private: it came by whisper; opts.self: the opener's own check (strict open window).
-- Returns true, or nil and why; a second value "terms" asks the bank to void the event (T).
function Markets.CheckSheet(sheet, sender, mode, private, opts)
	opts = opts or {}
	local ev = Event(sheet.eid)
	if not ev then return nil, "event" end
	-- (2) the event's opener alone writes it.
	if not Same(ev.opener, sender) then return nil, "opener" end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return nil, "realm" end
	local R = Roles()
	local now = Now()
	local anyPublic, anyPrivate, guildFee, lotteryFee = false, false, false, false
	for _, idx in ipairs(sheet.order) do
		local m = sheet.markets[idx]
		local kind = KINDS[m.type]
		if kind.private then anyPrivate = true else anyPublic = true end
		-- (The Lottery has no arbiter, and a direct record no bank: their fee is all the guild's.)
		if kind.lottery or kind.direct then guildFee = true end
		if kind.lottery then lotteryFee = true end
		-- (8) the kind fits the event, its outcomes and its param.
		if not kind.event[ev.kind] then return nil, "kind" end
		if kind.bo and tonumber(ev.bo) ~= kind.bo then return nil, "series" end
		if kind.series and not kind.bo and (tonumber(ev.bo) or 1) < 3 then return nil, "series" end
		if kind.category and (ev.category == nil or ev.category == "" or ev.category == "open") then return nil, "category" end
		-- (A bracket pool after the draw, the design: the event says it is drawn, not only its size.)
		if kind.pick and not (ev.drawn and (sheet.size or ev.size)) then return nil, "draw" end
		local n = Outcomes(kind, ev, sheet)
		if not n or m.n ~= n then return nil, "n" end
		if kind.k and n <= kind.k then return nil, "n" end
		if kind.param == "entrant" and not Entrants(ev)[m.value] then return nil, "param" end
		if TrialRefused(m.type, mode) then return nil, "trial" end
		if kind.param == "fee" and m.value * 100 < (tonumber(Settings().minBet) or 1000) then return nil, "param" end
		if kind.stake or kind.direct then
			-- Only between the two fighters of the event.
			if #Fighters(ev) ~= 2 then return nil, "parties" end
		end
		if kind.direct and sheet.bank then return nil, "bank" end
		if not kind.direct and not sheet.bank then return nil, "bank" end
	end
	if anyPublic and anyPrivate then return nil, "mixed" end
	-- (1) public on the lane of public objects, private by whisper to a party (or the bank).
	if anyPublic then
		if private then return nil, "lane" end
		if not PublicEvent(ev) then return nil, "public" end
		-- (3) a public arbiter opens public markets (the Lottery's day: its caller, the King's
		-- character; never a bank, which sees every bet by name before a draw it could roll).
		if not (R and R.IsPublicArbiter and R.IsPublicArbiter(sender, mode)) then return nil, "public" end
		if R and R.IsBank and R.IsBank(sender, mode) then return nil, "public" end
	else
		if not private and not opts.self then return nil, "lane" end
		if not opts.self then
			local party = false
			for _, f in ipairs(Fighters(ev)) do if Same(f.name, ns.me) then party = true end end
			if sheet.bank and Same(sheet.bank, ns.me) then party = true end
			if not party then return nil, "party" end
		end
	end
	if sheet.bank and not (R and R.IsBank and R.IsBank(sheet.bank, mode)) then return nil, "bank" end
	-- (5) the currency: L needs this realm's live switch with that currency (gold: a fee receiver);
	-- chips only in T. It freezes when the sheet opens: a later rev keeps it, whatever the King's
	-- switch says by then (an event under way still settles).
	local settings = Settings()
	local rec0 = Rec(mode, sheet.eid)
	local kept0 = rec0 and rec0.sheet
	if mode == "L" and sheet.cur == "c" then return nil, "cur" end
	if lotteryFee and sheet.cur ~= "g" then return nil, "cur" end
	if kept0 and not opts.self then
		if sheet.cur ~= kept0.cur then return nil, "cur" end
	elseif mode == "L" then
		if not (R and R.Live and R.Live()) then return nil, "live" end
		if (R.Currency and R.Currency() or "g") ~= sheet.cur then return nil, "cur" end
		if sheet.cur == "g" and not (R.FeeReceiver and R.FeeReceiver()) then return nil, "receiver" end
	end
	-- (6) the fee: gold's is the King's word (or the one before it, within FEE_CHANGE of the King's
	-- change), frozen when the sheet opens (a later rev keeps it); points and chips carry none. The
	-- Lottery's and a direct record's go all to the guild (the design: no arbiter).
	if guildFee and sheet.fee.to ~= "g" then return nil, "fee" end
	if kept0 and not opts.self then
		if sheet.fee.g ~= kept0.fee.g or sheet.fee.a ~= kept0.fee.a or sheet.fee.to ~= kept0.fee.to then return nil, "fee" end
	elseif sheet.cur == "g" then
		local f = sheet.fee
		if lotteryFee then
			if f.g ~= 600 or f.a ~= 0 or f.to ~= "g" then return nil, "fee" end
		elseif not Markets.FeeOk(f.g, f.a, settings) then return nil, "fee" end
		-- The King holds no gold: his markets pay the arbiter's part to the guild.
		if R and R.IsKing and R.IsKing(sender) and f.to ~= "g" then return nil, "fee" end
	elseif sheet.fee.g ~= 0 or sheet.fee.a ~= 0 then
		return nil, "fee"
	end
	-- (7) the lock: at most 14 days ahead; the window (below).
	if sheet.lockAt > now + Markets.LOCK_AHEAD_MAX then return nil, "lockAt" end
	local rec = Rec(mode, sheet.eid)
	local kept = rec and rec.sheet
	-- (4) newer than the kept one (the same rev with other contents: the first kept, logged).
	if kept then
		if sheet.rev < kept.rev then return nil, "older" end
		if sheet.rev == kept.rev then return nil, Markets.SheetBody(sheet) == Markets.SheetBody(kept) and "same" or "clash" end
	end
	local okWindow, whyWindow = Markets.WindowOk(sheet, rec, kept, anyPublic, now, opts)
	if not okWindow then return nil, whyWindow end
	if kept then
		-- A market moves only O -> L -> R, R -> R (a correction) or to V; a void is final; a market
		-- added later opens (O) or is void.
		for idx, new in pairs(sheet.markets) do
			local old = kept.markets[idx]
			if not old then
				if new.state ~= "O" and new.state ~= "V" then return nil, "state" end
			elseif old.state ~= new.state and not STEPS[old.state][new.state] then
				return nil, old.state == "V" and "void" or "state"
			end
		end
		-- (9) immutable under bets: a market with bets keeps its type, param and outcomes; the fee,
		-- the currency and the bank stay; scratches may only be added, before the lock.
		for idx, old in pairs(kept.markets) do
			local new = sheet.markets[idx]
			if old.state == "V" and (not new or new.state ~= "V") then return nil, "void" end
			if HasBets(rec, idx) then
				if not new or new.type ~= old.type or new.n ~= old.n then return nil, "terms", "T" end
				if new.param ~= old.param then return nil, "terms", "T" end
			end
		end
		local bets = false
		for idx in pairs(kept.markets) do if HasBets(rec, idx) then bets = true end end
		if bets then
			if sheet.bank ~= kept.bank and not Same(sheet.bank, kept.bank) then return nil, "terms", "T" end
			if sheet.cur ~= kept.cur or sheet.fee.g ~= kept.fee.g or sheet.fee.a ~= kept.fee.a or sheet.fee.to ~= kept.fee.to then return nil, "terms", "T" end
			for e in pairs(kept.scratched or {}) do if not sheet.scratched[e] then return nil, "terms", "T" end end
			for e in pairs(sheet.scratched) do
				if not kept.scratched[e] and now >= kept.lockAt then return nil, "terms", "T" end
			end
			if kept.size and sheet.size ~= kept.size then return nil, "terms", "T" end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Scratched outcomes (the design): an entrant withdrawn, a stage the bracket's size
-- cannot produce, a class nobody left plays. Their bets are refunded; the pools shrink.
---------------------------------------------------------------------------

local function ClassOf(e) return type(e) == "table" and type(e.class) == "string" and e.class:upper() or nil end
function Markets.ScratchedOf(sheet, m, ev)
	local out = {}
	local kind = KINDS[m.type]
	if kind.entrants then
		for e in pairs(sheet.scratched or {}) do if e <= m.n then out[e] = true end end
	elseif kind.param == "entrant" then
		local size = sheet.size or (type(ev) == "table" and tonumber(ev.size)) or nil
		local B = ns.ArenaBracket
		if size and B and B.Possible then
			local ok, possible = pcall(B.Possible, size)
			if ok and type(possible) == "table" then
				for stage = 1, m.n do if not possible[stage] then out[stage] = true end end
			end
		end
	elseif m.type == "WC" then
		local present, known = {}, false
		for i, e in pairs(Entrants(ev)) do
			local c = ClassOf(e)
			if c then known = true end
			if c and not (sheet.scratched or {})[i] and CLASS_INDEX[c] then present[CLASS_INDEX[c]] = true end
		end
		if known then
			for o = 1, m.n do if not present[o] then out[o] = true end end
		end
	end
	return out
end
-- A stage market on an entrant withdrawn is void as a whole.
function Markets.WholeScratch(sheet, m)
	local kind = KINDS[m.type]
	return kind.param == "entrant" and (sheet.scratched or {})[m.value] == true
end

---------------------------------------------------------------------------
-- Involvement and the one ticker's work (the weight rule, the design)
---------------------------------------------------------------------------

-- This character's tickets in a mode ({ [eid#nonce] = ticket }); made on first use only when
-- create is true (an idle client that heard a sheet stores nothing of its own).
local EMPTY = setmetatable({}, { __newindex = function() error("markets: tickets written without create") end })
local function TicketsOf(mode, create, who)
	local store = StoreOf(mode, create)
	if type(store) ~= "table" then return EMPTY end
	who = ns.FullName(who or ns.me)
	local all = store.tickets
	if type(all) ~= "table" or type(all[who]) ~= "table" then
		if not create then return EMPTY end
		if type(all) ~= "table" then all = {} store.tickets = all end
		all[who] = {}
	end
	return all[who]
end
Markets.TicketsOf = TicketsOf
local OPEN_TICKET = { queued = true, sent = true, accepted = true, unconfirmed = true, locked = true, held = true, offline = true, key = true }
Markets.OPEN_TICKET = OPEN_TICKET

Involved = function(rec)
	if not rec then return false end
	local s = rec.sheet
	if s and (Same(s.from, ns.me) or Same(s.bank, ns.me)) then return true end
	if rec.party or rec.given then return true end
	for _, t in pairs(TicketsOf(rec.mode)) do
		if type(t) == "table" and t.eid == rec.eid then return true end
	end
	return false
end
Markets.Involved = Involved

local Tick -- (below)
local tickOn = false
-- Anything this client must do on time: its own sheets (repeats and the lock), open tickets, its
-- overrules' repeats. The bank's own work is MarketBank's.
local function Busy()
	for _, mode in ipairs({ "L", "T" }) do
		local core = Tables(mode)
		for _, rec in pairs(core or {}) do
			if type(rec) == "table" and (rec.own or rec.given) then
				if rec.own and not rec.done then return true end
				if rec.given and not rec.givenDone then return true end
			end
		end
		-- (A ticket taken, locked or held waits for books, which come by themselves: only a slip
		-- still unanswered needs the clock.)
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and (t.state == "sent" or t.state == "key") then return true end
		end
	end
	return false
end
-- A ticket not yet acknowledged: the Wallet reads the ledger's entries for it (the money part's
-- Wallet.Listen: a client listening to nobody's entries parses none, the weight rule).
local AWAITING = { sent = true, unconfirmed = true, offline = true, key = true, queued = true }
local listening = false
function Markets.Involve()
	local on = Busy()
	if on and not tickOn then
		tickOn = true
		ns.Arena.Every(1, "markets", function() ns.SafeCall("markets tick", Tick) end)
	end
	ns.Arena.Involve("markets", on)
	local awaiting = false
	for _, mode in ipairs({ "L", "T" }) do
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and AWAITING[t.state] then awaiting = true end
		end
	end
	if awaiting ~= listening then
		listening = awaiting
		Call(ns.Wallet, "Listen", "markets", awaiting)
	end
	return on
end

-- Every event record of a mode this client holds (the core's, the companion's, memory's).
function Markets.All(mode)
	local out = {}
	local core, heavy, mem = Tables(mode)
	for _, t in ipairs({ core or {}, heavy or {}, mem or {} }) do
		for _, rec in pairs(t) do if type(rec) == "table" then out[#out + 1] = rec end end
	end
	return out
end

---------------------------------------------------------------------------
-- Sending sheets (the opener's) and the repeats (the design)
---------------------------------------------------------------------------

local function SheetPrivate(sheet)
	for _, m in pairs(sheet.markets) do if KINDS[m.type].private then return true end end
	return false
end
Markets.SheetPrivate = SheetPrivate
-- The parties of a private sheet: the two fighters and the bank (not ourselves).
local function PartiesOf(sheet, ev)
	local out = {}
	for _, f in ipairs(Fighters(ev)) do if not Same(f.name, ns.me) then out[#out + 1] = f.name end end
	if sheet.bank and not Same(sheet.bank, ns.me) then
		local dup = false
		for _, n in ipairs(out) do if Same(n, sheet.bank) then dup = true end end
		if not dup then out[#out + 1] = sheet.bank end
	end
	return out
end
Markets.PartiesOf = PartiesOf

local function SendSheet(rec, urgent)
	local s = rec.sheet
	if not s then return false end
	-- A send the arena refuses now (the King's live switch off): it goes at the first tick it may,
	-- urgently if it was urgent, rather than waiting for the next repeat.
	if ns.Arena.Refusal("BM", rec.mode, {}) then
		rec.unsent = (urgent or rec.unsent == "u") and "u" or "r"
		return false
	end
	rec.unsent = nil
	local body = Markets.SheetBody(s)
	local o = { key = "bm " .. s.eid, urgent = urgent and true or nil, must = urgent and true or nil }
	if SheetPrivate(s) then
		local any = false
		for _, to in ipairs(PartiesOf(s, Event(s.eid))) do
			local oo = { key = "bm " .. s.eid, urgent = o.urgent, must = o.must, to = to }
			if ns.Arena.Send("BM", rec.mode, body, oo) then any = true end
		end
		rec.sentAt = Now()
		return any
	end
	local ok = ns.Arena.Send("BM", rec.mode, body, o)
	rec.sentAt = Now()
	return ok
end
Markets.SendSheet = SendSheet

-- When the opener's sheet goes out again (the design): 60 s while open (300 s for one open for
-- days), 120 s locked, 60 s in the grace, 300 s for 30 minutes after it is all settled or void.
local function RepeatGap(rec)
	local s, now = rec.sheet, Now()
	local open, grace, over = false, false, true
	for _, m in pairs(s.markets) do
		if m.state == "O" then open = true end
		if m.state == "R" and now < (m.t or 0) + Markets.GRACE then grace = true end
		if m.state == "O" or m.state == "L" or m.state == "R" then over = false end
	end
	local book = rec.book
	if book then
		local settled = true
		for idx, m in pairs(s.markets) do
			local b = book.markets[idx]
			if m.state ~= "V" and not (b and (b.state == "S" or b.state == "V")) then settled = false end
		end
		if settled then over = true end
	end
	if over then
		rec.overAt = rec.overAt or now
		if now - rec.overAt > Markets.REPEAT_AFTER_FOR then return nil end
		return Markets.REPEAT_AFTER
	end
	if open then return s.lockAt - now > Markets.LONG_OPEN and Markets.REPEAT_OPEN_LONG or Markets.REPEAT_OPEN end
	if grace then return Markets.REPEAT_GRACE end
	return Markets.REPEAT_LOCKED
end

-- A new rev of the opener's sheet: kept, sent urgently.
local function Publish(rec, urgent)
	local s = rec.sheet
	s.rev = (s.rev or 0) + 1
	s.from = ns.me
	rec.done, rec.overAt = nil, nil
	SendSheet(rec, urgent ~= false)
	Place(rec.mode, rec)
	-- Our own message never comes back: a bank opening its own event (the Lottery's day) takes it here.
	if Same(s.bank, ns.me) then
		local f = Fn(ns.MarketBank, "OnSheet")
		if f then ns.SafeCall("markets bank sheet", f, rec.mode, rec, nil) end
	end
	Markets.Involve()
	Changed()
	return true
end

---------------------------------------------------------------------------
-- The opener (the fights part's fight arbiter or promoter, the Bones tables' table arbiter, the Lottery's King)
---------------------------------------------------------------------------

-- The first open bank of this realm by name (the sheet's stakeholder by default).
function Markets.DefaultBank(mode)
	local R = Roles()
	local list = R and R.Banks and R.Banks(mode) or {}
	local names = {}
	for _, b in ipairs(list) do if b.state == "o" then names[#names + 1] = b.name end end
	table.sort(names)
	return names[1]
end

-- The fee a new sheet freezes (the design): gold's from the King's word, with
-- the arbiter's part to the guild when the King opens it (he holds no gold), there is no arbiter
-- (the Lottery) or spec.waive; none on points and chips.
local function FeeFor(cur, opener, spec, anyKind)
	if cur ~= "g" then return { g = 0, a = 0, to = "g" } end
	local s = Settings()
	local feeBp, arbBp = tonumber(s.feeBp) or 600, tonumber(s.arbBp) or 200
	local R = Roles()
	local kind = KINDS[anyKind]
	if kind and kind.lottery then return { g = 600, a = 0, to = "g" } end
	local toGuild = spec.waive or (R and R.IsKing and R.IsKing(opener)) or (kind and (kind.lottery or kind.direct))
	return { g = feeBp - arbBp, a = arbBp, to = toGuild and "g" or "a" }
end

-- A market's spec: { type = "MW", param = number|{ a, b }|nil } -> the sheet's market, or nil, why.
-- The Lottery's param is emitted only in its v2 form: "2" (no pot carried in), or
-- "2.<from eid>.<copper b36>" / { from, copper }.
local function MarketOf(idx, spec, ev, sheet)
	if type(spec) ~= "table" then return nil, "market" end
	local typ = spec.type
	local kind = KINDS[typ]
	if not kind then return nil, "type" end
	-- (A bracket pool opens once the bracket is drawn, the design: the size alone is known before.)
	if kind.pick and not (type(ev) == "table" and ev.drawn) then return nil, "draw" end
	local param = "-"
	if kind.param == "carry" then
		local p = spec.param
		if type(p) == "table" then
			local c = tonumber(p.copper)
			p = (type(p.from) == "string" and c and c > 0) and ("2." .. p.from .. "." .. B36(c)) or "2"
		end
		if p == nil or p == "" then p = "2" end
		if type(p) ~= "string" then return nil, "param" end
		param = p
	elseif kind.param == "line" or kind.param == "entrant" or kind.param == "fee" then
		local v = tonumber(spec.param)
		if not v or v ~= math.floor(v) or v < 0 then return nil, "param" end
		param = B36(v)
	elseif kind.param == "stakes" then
		local p = spec.param
		if type(p) ~= "table" or not tonumber(p[1]) or not tonumber(p[2]) then return nil, "param" end
		param = B36(p[1]) .. "." .. B36(p[2])
	end
	local okParam, value = ParseParam(kind, param)
	if not okParam then return nil, "param" end
	local n = Outcomes(kind, ev, sheet)
	if not n then return nil, kind.pick and "draw" or "n" end
	return { idx = idx, type = typ, param = param, value = value, n = n, state = "O" }
end

-- Markets.Open(eid, spec): on the event's opener's client, the sheet's first rev (or, when it
-- exists already, a new rev with markets added). spec = {
--   markets = { { type = "MW" }, { type = "DU", param = 90 }, { type = "ST", param = 3 },
--               { type = "PK", param = <entry fee in silver> }, { type = "CX", param = { aSilver, bSilver } },
--               { type = "LO", param = "<from eid>.<copper b36>" | { from, copper } | "-" }, ... },
--   lockAt (default: the event's, else now + Arena.OpenMin), bank (default: the first open bank;
--   none for DR), cur (default: this realm's currency; chips "c" in T), waive (the arbiter's part
--   to the guild), mode (default: the event's, else Arena.NewMode) }.
-- Returns true, or false and why. The sheet is checked as every client will check it.
function Markets.Open(eid, spec)
	spec = type(spec) == "table" and spec or {}
	if not EidOk(eid) then return false, "eid" end
	if ns.Arena.Off() then return false, "off" end
	local ev = Event(eid)
	if not ev then return false, "event" end
	if not Wagers(spec.markets, ev.kind) then return false, "compliance" end
	if not Same(ev.opener, ns.me) then return false, "opener" end
	local mode = spec.mode or ev.mode or ns.Arena.NewMode(false)
	if mode ~= "L" and mode ~= "T" then return false, "mode" end
	local rec = Rec(mode, eid)
	if rec and rec.sheet and rec.own then return Markets.AddMarkets(eid, spec.markets) end
	local list = type(spec.markets) == "table" and spec.markets or {}
	if #list == 0 or #list > Markets.MAX_MARKETS then return false, "markets" end
	local R = Roles()
	local cur = spec.cur or (mode == "T" and "c" or (R and R.Currency and R.Currency() or "g"))
	local anyKind, direct = nil, false
	for _, m in ipairs(list) do
		anyKind = anyKind or (type(m) == "table" and m.type)
		if type(m) == "table" and KINDS[m.type] and KINDS[m.type].direct then direct = true end
	end
	local bank = spec.bank
	if not direct and not bank then bank = Markets.DefaultBank(mode) end
	if direct then bank = nil end
	if not direct and not bank then return false, "bank" end
	local sheet = { eid = eid, rev = 0, bank = bank and ns.FullName(bank) or nil, cur = cur, fee = FeeFor(cur, ns.me, spec, anyKind),
		lockAt = math.floor(tonumber(spec.lockAt) or tonumber(ev.lockAt) or (Now() + ns.Arena.OpenMin(PublicEvent(ev)))),
		scratched = {}, markets = {}, order = {}, size = tonumber(spec.size) or tonumber(ev.size) or nil }
	for e in pairs(type(spec.scratched) == "table" and spec.scratched or {}) do sheet.scratched[e] = true end
	for i, ms in ipairs(list) do
		local m, why = MarketOf(i, ms, ev, sheet)
		if not m then return false, why end
		sheet.markets[i] = m
		sheet.order[i] = i
	end
	sheet.rev = 1
	local ok, why = Markets.CheckSheet(sheet, ns.me, mode, SheetPrivate(sheet), { self = true })
	if not ok then return false, why end
	sheet.rev = 0
	rec = rec or NewRec(mode, eid)
	rec.sheet, rec.own, rec.mode = sheet, true, mode
	sheet.mode, sheet.taken = mode, Now()
	-- When the betting window opened (the Bell and SetLock keep it at least OpenMin long).
	rec.opened = sheet.taken
	return Publish(rec, true)
end

-- Adds markets to a sheet (a tournament's bracket pool after the draw): a new rev.
function Markets.AddMarkets(eid, list)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	if type(list) ~= "table" or #list == 0 then return false, "markets" end
	local s = rec.sheet
	local ev = Event(eid)
	if not ev then return false, "event" end
	if not Wagers(list, ev.kind) then return false, "compliance" end
	if Now() >= s.lockAt then return false, "closed" end
	local added = {}
	for _, ms in ipairs(list) do
		local exists = false
		for _, m in pairs(s.markets) do
			if type(ms) == "table" and m.type == ms.type and (ms.param == nil or tostring(m.value) == tostring(ms.param)) then exists = true end
		end
		if not exists then
			local idx = #s.order + 1
			if idx > Markets.MAX_MARKETS then return false, "count" end
			local m, why = MarketOf(idx, ms, ev, s)
			if not m then return false, why end
			if TrialRefused(m.type, rec.mode) then return false, "trial" end
			s.markets[idx] = m
			s.order[#s.order + 1] = idx
			added[#added + 1] = idx
		end
	end
	if #added == 0 then return true end
	return Publish(rec, true)
end

-- The earliest lock the opener may set now: the last call from now, and the whole window from
-- when the sheet opened.
local function EarliestLock(rec, public)
	local now = Now()
	local opened = rec.opened or (rec.sheet and rec.sheet.taken) or now
	return math.max(now + ns.Arena.LastCall(public), opened + WindowMin(public))
end

-- The Bell (the design): lockAt = now + Arena.LastCall(public), to the second, but never before
-- the window's OpenMin from its opening (the design: rung early, the bets stay open that long).
function Markets.CloseBets(eid)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	local ev = Event(eid)
	return Markets.SetLock(eid, EarliestLock(rec, PublicEvent(ev) and not SheetPrivate(rec.sheet)))
end
-- A new lock time: never under the last call from now (the King's delay in it), nor before the
-- window's OpenMin from its opening, nor past 14 days.
function Markets.SetLock(eid, lockAt)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	lockAt = math.floor(tonumber(lockAt) or 0)
	local s, now = rec.sheet, Now()
	local open = false
	for _, m in pairs(s.markets) do if m.state == "O" then open = true end end
	if not open then return false, "closed" end
	if now >= s.lockAt then return false, "closed" end
	local ev = Event(eid)
	local public = PublicEvent(ev) and not SheetPrivate(s)
	if lockAt < EarliestLock(rec, public) then return false, "soon" end
	if lockAt > now + Markets.LOCK_AHEAD_MAX then return false, "far" end
	if lockAt == s.lockAt then return true end
	s.lockAt = lockAt
	return Publish(rec, true)
end

-- The opener's own markets turn L at lockAt (the bank locks by its own clock either way).
local function LockOwn(rec)
	local s, now, changed = rec.sheet, Now(), false
	if now < s.lockAt then return false end
	for _, m in pairs(s.markets) do
		if m.state == "O" then m.state = "L" changed = true end
	end
	return changed
end

-- The result of a market from the facts (see Declare), or nil (not known yet), or "V", code.
local function Side(x) return x == "A" and 1 or (x == "B" and 2 or nil) end
function Markets.ResultFromFacts(m, facts, ev)
	local typ, kind = m.type, KINDS[m.type]
	local bang = facts.against and "!" or ""
	if typ == "MW" or typ == "CX" or typ == "FK" or typ == "DR" then
		local o = Side(facts.winner)
		return o and (B36(o) .. bang) or nil
	elseif typ == "SW" or typ == "B3" then
		local rounds = type(facts.rounds) == "string" and facts.rounds or ""
		local a, b = 0, 0
		for c in rounds:gmatch(".") do if c == "A" then a = a + 1 elseif c == "B" then b = b + 1 end end
		local need = math.floor((tonumber(ev and ev.bo) or 3) / 2) + 1
		if typ == "SW" then
			if a >= need then return "1" .. bang end
			if b >= need then return "2" .. bang end
			local o = Side(facts.winner)
			if o and facts.final then return B36(o) .. bang end
			if facts.final then return "V", "I" end
			return nil
		end
		if a == 2 and b == 0 then return "1" .. bang end
		if a == 2 and b == 1 then return "2" .. bang end
		if b == 2 and a == 1 then return "3" .. bang end
		if b == 2 and a == 0 then return "4" .. bang end
		if facts.final then return "V", "I" end
		return nil
	elseif typ == "KO" then
		if facts.method == "K" then return "1" .. bang end
		if facts.method == "R" then
			local dur = tonumber(facts.dur)
			if dur and dur < Markets.KO_EARLY then return "V", "N" end
			return "2" .. bang
		end
		if facts.winner then return "V", "N" end
		return nil
	elseif typ == "DU" then
		local dur = tonumber(facts.dur)
		if dur then return (dur >= m.value + 1 and "1" or "2") .. bang end
		if facts.winner then return "V", "N" end
		return nil
	elseif typ == "FB" then
		local o = Side(facts.fb)
		if o then return B36(o) .. bang end
		if facts.winner then return "V", "N" end
		return nil
	elseif typ == "BH" then
		if facts.bh == "tie" then return "V", "Z" end
		local o = Side(facts.bh)
		if o then return B36(o) .. bang end
		if facts.winner then return "V", "N" end
		return nil
	elseif typ == "CH" or typ == "CC" then
		local e = tonumber(facts.champion)
		return e and B36(e) or nil
	elseif kind.k then
		local list = typ == "RF" and facts.finalists or (typ == "RS" and facts.semifinalists or facts.quarterfinalists)
		if type(list) ~= "table" or #list == 0 then return nil end
		local sorted = {}
		for _, e in ipairs(list) do if tonumber(e) then sorted[#sorted + 1] = tonumber(e) end end
		table.sort(sorted)
		for i, e in ipairs(sorted) do sorted[i] = B36(e) end
		return table.concat(sorted, "+")
	elseif typ == "ST" then
		local stages = type(facts.stages) == "table" and facts.stages or {}
		local st = tonumber(stages[m.value])
		return st and B36(st) or nil
	elseif typ == "WC" then
		local c = type(facts.class) == "string" and CLASS_INDEX[facts.class:upper()] or nil
		return c and B36(c) or nil
	elseif typ == "PK" then
		local hex = type(facts.bracket) == "string" and facts.bracket:match("^[pP]?(%x+)$") or nil
		return hex and ("P" .. hex:lower()) or nil
	elseif kind.lottery then
		local lot = type(facts.lottery) == "table" and facts.lottery or nil
		return Markets.DrawText(facts.draw or (lot and (lot.prizes or lot.text)))
	end
	return nil
end

-- The Lottery's result as the sheet writes it: five prizes, each four digits ("0427.9981.1200.0033.5555"),
-- from { n1, ..., n5 } (0-9999; the /roll's 10000 is 0000) or that text; nil for anything else.
function Markets.DrawText(d)
	if type(d) == "string" then
		return d:find("^%d%d%d%d%.%d%d%d%d%.%d%d%d%d%.%d%d%d%d%.%d%d%d%d$") and d or nil
	end
	if type(d) ~= "table" or #d ~= 5 then return nil end
	local out = {}
	for i = 1, 5 do
		local v = tonumber(d[i])
		if not v or v ~= math.floor(v) or v < 0 or v > 10000 then return nil end
		out[i] = ("%04d"):format(v % 10000)
	end
	return table.concat(out, ".")
end

-- Markets.Declare(eid, results): the opener declares, after lockAt. results is either explicit,
-- { [idx] = outcome | { outcome, ... } | "P<hex>" | "V<code>" }, or the facts, from which each
-- market's result follows (a market whose fact is not known yet is left as it is):
--   a fight or a Farkle game: { winner = "A"|"B", method = "K"|"R" (knockout, fled), dur (whole
--     seconds from the bell to the duel line), rounds = "ABA" (a series), final (the series is
--     over), fb = "A"|"B", bh = "A"|"B"|"tie" (who landed the biggest hit), against = true (the
--     arbiter declares against the game's duel line: every market of the event holds) };
--   a tournament: { champion = e, finalists = { e, e }, semifinalists = {...}, quarterfinalists =
--     {...}, stages = { [e] = 1-5 }, class = "MAGE", bracket = "P<hex>" } (entrant numbers);
--   the Lottery: { draw = { n1, n2, n3, n4, n5 } } (the five rolls, 0-9999; 10000 is 0000), or
--     { lottery = { prizes = { n1..n5 }, text = "0427.9981.1200.0033.5555" } }. The old numeric
--     per-market head result is refused as an incompatible version.
-- A market declared again with another result is a correction (a new rev: the grace restarts).
-- Returns true and how many markets changed, or false and why.
function Markets.Declare(eid, results)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	if type(results) ~= "table" then return false, "results" end
	local s, now = rec.sheet, Now()
	if now < s.lockAt then return false, "open" end
	LockOwn(rec)
	local ev = Event(eid)
	local explicit = false
	for k in pairs(results) do if type(k) == "number" then explicit = true end end
	local draw = Markets.DrawText(results.draw or (type(results.lottery) == "table" and (results.lottery.text or results.lottery.prizes)) or nil)
	for _, idx in ipairs(s.order) do
		local m = s.markets[idx]
		if KINDS[m.type].lottery and explicit and results[idx] ~= nil then return false, "version" end
	end
	local changed = 0
	for _, idx in ipairs(s.order) do
		local m = s.markets[idx]
		if m.state ~= "V" then
			local res, code
			if KINDS[m.type].lottery and draw and not explicit then
				res = draw
			elseif explicit then
				local v = results[idx]
				if type(v) == "string" and v:match("^V(.)$") then
					res, code = "V", v:sub(2)
				elseif type(v) == "table" then
					local list = {}
					for _, o in ipairs(v) do list[#list + 1] = tonumber(o) end
					table.sort(list)
					for i, o in ipairs(list) do list[i] = B36(o) end
					res = #list > 0 and table.concat(list, "+") or nil
				elseif type(v) == "number" then
					res = B36(v)
				elseif type(v) == "string" then
					res = v
				end
			else
				res, code = Markets.ResultFromFacts(m, results, ev)
			end
			if res == "V" then
				if Markets.VOIDS[code] then
					m.state, m.result, m.t = "V", code, now
					changed = changed + 1
				end
			elseif res and ReadResult(m, res) and (m.state ~= "R" or m.result ~= res) then
				m.state, m.result, m.t = "R", res, now
				changed = changed + 1
			end
		end
	end
	-- A series' round winners so far go on the sheet (its rounds field) for every client to show.
	local rounds = not explicit and results.rounds
	if type(rounds) == "string" and rounds:find("^[AB]+$") and #rounds <= 5 and rounds ~= s.rounds and not s.size then
		s.rounds = rounds
		if changed == 0 then Publish(rec, true) end
	end
	if changed == 0 then return true, 0 end
	Publish(rec, true)
	return true, changed
end

-- Markets.Void(eid, idx|"*", code): the opener voids one market or every one (the design:
-- E a duel before the lock, W no start, I interference, N no data, Z a tie, X cancelled, S a stake
-- missing). A void is final.
function Markets.Void(eid, idx, code)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	if not Markets.VOIDS[code] then return false, "code" end
	local s, now, changed = rec.sheet, Now(), 0
	for _, i in ipairs(s.order) do
		local m = s.markets[i]
		if (idx == "*" or idx == i) and m.state ~= "V" then
			m.state, m.result, m.t = "V", code, now
			changed = changed + 1
		end
	end
	if changed == 0 then return false, "none" end
	return Publish(rec, true)
end

-- Entrants withdrawn before the lock (a no-show at check-in, the design): their outcomes are
-- scratched (refunded, the pools shrink), a stage market on one of them is void.
function Markets.Scratch(eid, entrants)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	local s = rec.sheet
	if Now() >= s.lockAt then return false, "closed" end
	if type(entrants) ~= "table" then entrants = { entrants } end
	local changed = false
	for _, e in ipairs(entrants) do
		e = tonumber(e)
		if e and e >= 1 and e <= 64 and not s.scratched[e] then s.scratched[e] = true changed = true end
	end
	if not changed then return true end
	for _, m in pairs(s.markets) do
		if Markets.WholeScratch(s, m) and m.state == "O" then m.state, m.result, m.t = "V", "I", Now() end
	end
	return Publish(rec, true)
end
-- The bracket's size once it is fixed (after check-in): stages it cannot produce are scratched,
-- and the bracket pool may open (AddMarkets).
function Markets.SetSize(eid, size)
	local rec = Find(eid)
	if not rec or not rec.own or not rec.sheet then return false, "sheet" end
	size = tonumber(size)
	if not size or size < 2 or size > 64 then return false, "size" end
	if rec.sheet.size == size then return true end
	if rec.sheet.size then return false, "size" end
	rec.sheet.size = size
	return Publish(rec, true)
end

-- Whether the opener's sheet exists here (any client: heard).
function Markets.Has(eid)
	local rec = Find(eid)
	return rec ~= nil and rec.sheet ~= nil
end
function Markets.Sheet(eid, mode)
	local rec = Find(eid, mode)
	return rec and rec.sheet or nil
end
function Markets.Book(eid, mode)
	local rec = Find(eid, mode)
	return rec and rec.book or nil
end

-- "Fight!" is enabled once the bank's locked book was heard, or FIGHT_WAIT after lockAt without
-- one (the bank locks by its own clock either way): the stream always shows final odds first.
function Markets.FightReady(eid)
	local rec = Find(eid)
	if not rec or not rec.sheet then return true end
	local s, now = rec.sheet, Now()
	if not s.bank then return now >= s.lockAt end
	if now < s.lockAt then return false, "open" end
	local book = rec.book
	if book then
		local locked = true
		for idx, m in pairs(s.markets) do
			local b = book.markets[idx]
			if m.state ~= "V" and not (b and b.state ~= "O") then locked = false end
		end
		if locked then return true end
	end
	if now >= s.lockAt + Markets.FIGHT_WAIT then return true end
	return false, "book"
end

---------------------------------------------------------------------------
-- Receiving sheets (every client, the bank too)
---------------------------------------------------------------------------

local pending = {} -- sheets and books waiting for their event or sheet: { kind, dist, sender, mode, body, at }
local HandleSheet, HandleBook -- (below)

local function RetryPending()
	if not pending[1] then return end
	local now, list = Now(), pending
	pending = {}
	for _, p in ipairs(list) do
		if now - p.at <= Markets.SHEET_WAIT then
			local fn = p.kind == "BM" and HandleSheet or HandleBook
			local ok, why = fn(p.dist, p.sender, p.mode, p.body, true)
			if not ok and (why == "event" or why == "wait") then pending[#pending + 1] = p end
		end
	end
end
Markets.RetryPending = RetryPending
function Markets.Pending() return #pending end
local function Wait(kind, dist, sender, mode, body)
	for i = #pending, 1, -1 do
		local p = pending[i]
		if p.kind == kind and p.sender == sender and p.body:sub(1, 20) == body:sub(1, 20) then table.remove(pending, i) end
	end
	if #pending >= 40 then table.remove(pending, 1) end
	pending[#pending + 1] = { kind = kind, dist = dist, sender = sender, mode = mode, body = body, at = Now() }
end
-- An event registered, a fight heard: what waited for it is tried again (no timer: the weight rule).
ns.On("ARENA_CHANGED", function() if pending[1] then RetryPending() end end)

local function Alert(rec, was)
	local s = rec.sheet
	if SheetPrivate(s) then return end
	local open = false
	for _, m in pairs(s.markets) do if m.state == "O" then open = true end end
	if open and not rec.alerted then
		rec.alerted = true
		ns.Fire("MARKETS_OPEN", rec.eid)
	end
	if open and was and s.lockAt < was.lockAt and not rec.closing then
		rec.closing = true
		ns.Fire("MARKETS_CLOSING", rec.eid)
	end
end

HandleSheet = function(dist, sender, mode, body, retry)
	local sheet, why = Markets.ReadSheet(body)
	if not sheet then ns.Log("markets: sheet from %s refused: %s", tostring(sender), tostring(why)) return false, why end
	local private = dist == "WHISPER"
	local ok, why2, void = Markets.CheckSheet(sheet, sender, mode, private)
	if not ok then
		if why2 == "event" and not retry then Wait("BM", dist, sender, mode, body) end
		if why2 ~= "same" then ns.Log("markets: sheet %s rev %s from %s refused: %s", sheet.eid, tostring(sheet.rev), tostring(sender), tostring(why2)) end
		if void == "T" then
			local f = Fn(ns.MarketBank, "TermsChanged")
			if f then ns.SafeCall("markets terms", f, mode, sheet.eid) end
		end
		return false, why2
	end
	local rec = Rec(mode, sheet.eid) or NewRec(mode, sheet.eid)
	local was = rec.sheet
	sheet.from, sheet.mode, sheet.private, sheet.taken = ns.FullName(sender), mode, private, Now()
	if not was then
		-- First heard: when (the window's later revs are checked against it), and whether that was
		-- the sheet's opening give or take OPEN_SLACK (its rev 1, heard by a client online that long,
		-- repeating every 60 s: Markets.WindowOk).
		local now = Now()
		rec.opened = now
		rec.tight = sheet.rev == 1 and Markets.OnlineFor(now) >= Markets.OPEN_SLACK and sheet.lockAt - now <= Markets.LONG_OPEN or nil
	end
	-- The pool cap it opened under (a later word never refuses its books).
	sheet.maxPool = math.max(tonumber(Settings().maxPool) or 0, was and tonumber(was.maxPool) or 0)
	rec.sheet, rec.heard = sheet, Now()
	if private then
		for _, f in ipairs(Fighters(Event(sheet.eid))) do if Same(f.name, ns.me) then rec.party = true end end
	end
	Place(mode, rec)
	Alert(rec, was)
	local f = Fn(ns.MarketBank, "OnSheet")
	if f then ns.SafeCall("markets bank sheet", f, mode, rec, was) end
	-- A book that came before this rev.
	if pending[1] then RetryPending() end
	Markets.Involve()
	Changed()
	return true
end
local function OnSheet(dist, sender, mode, body) HandleSheet(dist, sender, mode, body) end

---------------------------------------------------------------------------
-- Books (BO): read and check here; written on the bank (MarketBank.lua)
---------------------------------------------------------------------------

function Markets.ReadBook(body)
	local eid, sheetRev, rev, t, lag, list = ns.Arena.Fields(body, 6)
	if not list then return nil, "shape" end
	if not EidOk(eid) then return nil, "eid" end
	local epoch, n = (rev or ""):match("^([0-9a-z]+)%.([0-9a-z]+)$")
	local b = { eid = eid, sheetRev = N36(sheetRev, 1, 36 ^ 7), epoch = N36(epoch, 1), n = N36(n, 0), t = N36(t, 1), lag = N36(lag, 0, 36 ^ 4), markets = {} }
	if not b.sheetRev or not b.epoch or not b.n or not b.t or not b.lag then return nil, "shape" end
	if list == "" then return nil, "markets" end
	for part in (list .. ";"):gmatch("([^;]*);") do
		local idx, state, pools, counts, result = part:match("^([0-9a-z]+):([OLSVH]):([0-9a-z.]*):([0-9a-z.]*):?(.*)$")
		idx = N36(idx, 1, Markets.MAX_MARKETS)
		if not idx or b.markets[idx] then return nil, "market" end
		local m = { state = state, pools = {}, counts = {}, result = result ~= "" and result or nil }
		for v in (pools .. "."):gmatch("([^.]*)%.") do
			local x = N36(v, 0, 2147483647)
			if not x then return nil, "pools" end
			m.pools[#m.pools + 1] = x
		end
		for v in (counts .. "."):gmatch("([^.]*)%.") do
			local x = N36(v, 0, 1000000)
			if not x then return nil, "counts" end
			m.counts[#m.counts + 1] = x
		end
		if (state == "S" or state == "V") and not m.result then return nil, "result" end
		b.markets[idx] = m
	end
	return b
end

-- A book's consistency against the sheet (the design): true, or nil and why.
function Markets.CheckBook(book, sheet, sender, mode, private)
	local R = Roles()
	if not sheet.bank or not Same(sender, sheet.bank) then return nil, "sender" end
	if not (R and R.IsBank and R.IsBank(sender, mode)) then return nil, "bank" end
	if private ~= SheetPrivate(sheet) then return nil, "lane" end
	if book.sheetRev > sheet.rev then return nil, "wait" end
	local now = Now()
	if book.epoch > now + 60 then return nil, "epoch" end
	local settings = Settings()
	local minSilver = math.max(1, math.floor((tonumber(settings.minBet) or 1000) / 100))
	for idx, b in pairs(book.markets) do
		local m = sheet.markets[idx]
		if not m then return nil, "market" end
		local kind = KINDS[m.type]
		local n = kind.pick and 1 or m.n
		if #b.pools ~= n or #b.counts ~= n then return nil, "outcomes" end
		local sum = 0
		local capPool = math.floor(math.max(PoolCap(m, settings), sheet.maxPool and PoolCap(m, { maxPool = sheet.maxPool }) or 0) / 100)
		local floor = minSilver
		if kind.stake then floor = 1 end
		if kind.pick then floor = m.value end
		for i = 1, n do
			local p, c = b.pools[i], b.counts[i]
			if (p == 0) ~= (c == 0) then return nil, "zero" end
			if p < c * floor then return nil, "floor" end
			if kind.pick and p ~= c * m.value then return nil, "entries" end
			if p > math.floor(2147483647 / 100) then return nil, "pool" end
			sum = sum + p
		end
		if not kind.stake and not kind.lottery and sum > capPool then return nil, "cap" end
		-- The state against the sheet's: no S before its R, and the result it declared (a hold
		-- resolved by the game's duel line, or the Lottery rolled over, may pay another).
		if b.state == "O" and now >= sheet.lockAt + Markets.BOOK_OPEN_SLACK then return nil, "open" end
		if b.state == "S" then
			if m.state ~= "R" then return nil, "early" end
			local res = ReadResult(m, m.result)
			if kind.pick then
				if not (b.result or ""):match("^P" .. (res and res.pick or "?") .. "%.") then return nil, "result" end
			elseif kind.lottery then
				local Lo = ns.Lottery
				local wire = Lo and Lo.DecodeResult and Lo.DecodeResult(b.result)
				local calc = res and Markets.LotterySettlement(m, b.pools, false, 600)
				if not wire or not calc or wire.nextCarry ~= calc.nextCarry then return nil, "result" end
				for position = 1, 5 do
					if wire.draw[position] ~= res.animals[position] then return nil, "result" end
				end
			else
				local declared = res and table.concat(Markets.Winners(m, res), "+") or nil
				if b.result ~= declared and not (res and res.against) then return nil, "result" end
			end
		end
	end
	return true
end

-- Newer than the kept book: a later epoch (a new bank session), then a higher counter.
local function NewerBook(book, kept)
	if not kept then return true end
	if book.epoch ~= kept.epoch then return book.epoch > kept.epoch end
	return book.n > kept.n
end

local SettleTickets -- (below)
local heardBank = {} -- [bank lower] = when a BO or BK came from it
HandleBook = function(dist, sender, mode, body, retry)
	local book, why = Markets.ReadBook(body)
	if not book then ns.Log("markets: book from %s refused: %s", tostring(sender), tostring(why)) return false, why end
	local rec = Rec(mode, book.eid)
	if not rec or not rec.sheet then
		if not retry then Wait("BO", dist, sender, mode, body) end
		return false, "wait"
	end
	local ok, why2 = Markets.CheckBook(book, rec.sheet, sender, mode, dist == "WHISPER")
	if not ok then
		if why2 == "wait" and not retry then Wait("BO", dist, sender, mode, body) end
		ns.Log("markets: book %s from %s refused: %s", book.eid, tostring(sender), tostring(why2))
		return false, why2
	end
	heardBank[Lower(sender)] = Now()
	if not NewerBook(book, rec.book) then return false, "older" end
	local was = rec.book
	book.from, book.heard = ns.FullName(sender), Now()
	rec.book = book
	Place(mode, rec)
	-- Tickets waiting for the bank to be online go now; others learn their fate.
	SettleTickets(mode, rec, was)
	local newlyDone = false
	for idx, b in pairs(book.markets) do
		local old = was and was.markets[idx]
		if (b.state == "S" or b.state == "V") and not (old and old.state == b.state) then newlyDone = true end
	end
	if newlyDone then ns.Fire("MARKETS_SETTLED", rec.eid) end
	local f = Fn(ns.MarketBank, "AuditBook")
	if f then ns.SafeCall("markets audit", f, mode, rec, was) end
	Changed()
	return true
end
local function OnBook(dist, sender, mode, body) HandleBook(dist, sender, mode, body) end

-- A bank is online: the Wallet says so (its ZH), or its book or answer came lately.
function Markets.BankOnline(bank)
	if not bank then return false end
	local W = ns.Wallet
	local f = Fn(W, "Online")
	if f then
		local ok, yes = pcall(f, bank)
		if ok and yes == true then return true end
	end
	local t = heardBank[Lower(bank)]
	return t ~= nil and Now() - t <= Markets.BANK_HEARD
end

---------------------------------------------------------------------------
-- The market's state as a screen shows it: the book's when it settled, held or voided, else the
-- sheet's (L once lockAt passed).
---------------------------------------------------------------------------

function Markets.StateOf(rec, idx)
	local s = rec and rec.sheet
	local m = s and s.markets[idx]
	if not m then return nil end
	local b = rec.book and rec.book.markets[idx]
	if b and (b.state == "S" or b.state == "V") then return b.state, b.result end
	if m.state == "V" then return "V", m.result end
	if b and b.state == "H" then return "H", m.result end
	if m.state == "R" then return "R", m.result end
	if m.state == "L" or (b and b.state == "L") or Now() >= s.lockAt then return "L" end
	return "O"
end

-- The pools of a market in copper, by outcome key (its ledger form), from the latest book.
function Markets.PoolsOf(rec, idx)
	local s = rec and rec.sheet
	local m = s and s.markets[idx]
	if not m then return nil end
	local b = rec.book and rec.book.markets[idx]
	local pools, counts = {}, {}
	if KINDS[m.type].pick then
		return { total = b and b.pools[1] * 100 or 0 }, { total = b and b.counts[1] or 0 }
	end
	for o = 1, m.n do
		pools[Sel(o)] = b and (b.pools[o] or 0) * 100 or 0
		counts[Sel(o)] = b and (b.counts[o] or 0) or 0
	end
	return pools, counts
end

local function FeeArg(sheet) return { g = sheet.fee.g, a = sheet.fee.a, to = sheet.fee.to } end
Markets.FeeArg = FeeArg

---------------------------------------------------------------------------
-- Tickets: the bettor's side (the design)
---------------------------------------------------------------------------

local function Nonce()
	local out = {}
	local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	for i = 1, 6 do
		local d = math.random(1, 36)
		out[i] = chars:sub(d, d)
	end
	return table.concat(out)
end
Markets.random = Nonce -- (tests may swap it)

local lastSlip = -math.huge
local slipsPer = {} -- [eid] = slips sent this session

-- The outcome of a slip as the wire writes it, checked against the market: its number, or a
-- bracket pool's "p<hex>" picks of the right length.
local function SlipOutcome(m, o, sheet)
	local kind = KINDS[m.type]
	if kind.pick then
		local hex = type(o) == "string" and o:match("^p(%x+)$")
		local size = sheet.size or m.n
		local rounds = 0
		while 2 ^ rounds < size do rounds = rounds + 1 end
		local M = Math()
		if not hex or not (M and M.Picks and M.Picks(hex:lower(), rounds)) then return nil end
		return "p" .. hex:lower()
	end
	local v = tonumber(o) or (type(o) == "string" and N36(o, 1, m.n))
	if not v or v ~= math.floor(v) or v < 1 or v > m.n then return nil end
	return v
end
Markets.SlipOutcome = SlipOutcome

-- What this client says before a bet goes (the bank checks everything again): true, or false and
-- why (the tail of a MARKETS_WHY word).
function Markets.CanBet(eid, idx, o, silver)
	if ns.Arena.Off() then return false, "off" end
	if not ns.Arena.RulesAccepted() then return false, "rules" end
	local M = ns.Moderation
	if M and not M.missing and Fn(M, "SelfOff") and M.SelfOff() then return false, "netoff" end
	-- (1.1.6: a moderator's sanction on this player, WatchChat.Barred "games": a queued bet too.)
	if ns.Arena.Sanctioned and ns.Arena.Sanctioned() then return false, "sanction" end
	local rec, mode = Find(eid)
	local s = rec and rec.sheet
	local m = s and s.markets[tonumber(idx) or -1]
	if not m then return false, "unknown" end
	local kind = KINDS[m.type]
	if not Wagers({ m }, (Event(eid) or {}).kind) then return false, "compliance" end
	if kind.direct then return false, "direct" end
	if TrialRefused(m.type, mode) then return false, "trial" end
	local state = Markets.StateOf(rec, m.idx)
	if state ~= "O" or Now() >= s.lockAt - Markets.UI_CLOSE_EARLY then return false, "closed" end
	if not s.bank then return false, "bank" end
	if ns.Arena.RealmOf(s.bank) ~= ns.realm then return false, "realm" end
	local ov = SlipOutcome(m, o, s)
	if not ov then return false, "outcome" end
	if type(ov) == "number" and (Markets.ScratchedOf(s, m, Event(eid))[ov] or Markets.WholeScratch(s, m)) then return false, "outcome" end
	silver = tonumber(silver)
	if not silver or silver ~= math.floor(silver) or silver < 1 then return false, "min" end
	local settings = Settings()
	local copper = silver * 100
	local ev = Event(eid)
	if kind.pick then
		if silver ~= m.value then return false, "min" end
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and t.eid == eid and t.idx == m.idx and t.state ~= "refused" then return false, "one" end
		end
	elseif kind.stake then
		local side = SideOf(ev, ns.me)
		if not side or Side(side) ~= ov then return false, "conflict" end
		if silver ~= m.value[Side(side)] then return false, "min" end
	elseif copper < (tonumber(settings.minBet) or 1000) then
		return false, "min"
	end
	-- The anti-fix rules this client can see (the bank checks the rest, alts and keys included).
	for _, name in ipairs(Officials(ev, s)) do if Same(name, ns.me) then return false, "conflict" end end
	if Same(s.bank, ns.me) then return false, "conflict" end
	local side = SideOf(ev, ns.me)
	if side and not kind.stake and not (kind.self == "side" and Side(side) == ov) then return false, "conflict" end
	local e = EntrantOf(ev, ns.me)
	if e then
		local okSelf = (kind.self == "entrant" and ov == e) or (kind.self == "stage" and m.value == e and ov == 1)
		if not okSelf then return false, "conflict" end
	end
	if Markets.CAPPED[m.type] then
		local guild = GetGuildInfo and GetGuildInfo("player")
		for _, f in ipairs(Fighters(ev)) do
			if guild and f.guild and f.guild:lower() == guild:lower() then return false, "conflict" end
		end
	end
	if not kind.stake and not kind.pick then
		local cap = Markets.MyCap(rec, m)
		if copper > cap then return false, "cap" end
	end
	if Now() - lastSlip < Markets.SLIP_GAP then return false, "rate" end
	if (slipsPer[eid] or 0) >= Markets.SLIPS_EVENT then return false, "rate" end
	return true
end

-- What this character may still put on this market: the King's cap (KO and B3: 5 g), under his
-- standing's (Standing.Cap), less what his tickets hold there already.
function Markets.MyCap(rec, m)
	local settings = Settings()
	local cap = BetCapOf(m, settings)
	local St = ns.Standing
	local own = Call(St, "Cap", "bet", ns.me, rec.mode)
	if type(own) == "number" and own < cap then cap = own end
	local staked = 0
	for _, t in pairs(TicketsOf(rec.mode)) do
		if type(t) == "table" and t.eid == rec.eid and t.idx == m.idx and t.state ~= "refused" and t.state ~= "void" then staked = staked + (t.copper or 0) end
	end
	return math.max(0, cap - staked)
end

local function SendSlip(t)
	local sent = ns.Arena.Send("BS", t.mode, ("%s~%s~%s~%s~%s"):format(t.eid, B36(t.idx), Sel(t.o), B36(t.silver), t.nonce), {
		to = t.bank,
		done = function(ok, why)
			if not ok and (why == 12 or why == "notfound") and OPEN_TICKET[t.state] and t.state ~= "accepted" then t.state, t.code = "offline", "offline" Changed() end
		end,
	})
	t.tries = (t.tries or 0) + 1
	t.sentAt = Now()
	return sent
end

-- Markets.Bet(eid, idx, o, silver, queued): the slip, whispered to the sheet's bank. o: the
-- outcome's number (a bracket pool: "p<hex>"); silver: whole silver. queued: while the bank is
-- offline the ticket waits and goes when its next book is heard, if before the lock (a tournament
-- open for days). Returns the ticket, or nil and why.
function Markets.Bet(eid, idx, o, silver, queued)
	idx = tonumber(idx)
	local ok, why = Markets.CanBet(eid, idx, o, silver)
	if not ok then return nil, why end
	local rec, mode = Find(eid)
	local s = rec.sheet
	local m = s.markets[idx]
	local ov = SlipOutcome(m, o, s)
	local tickets = TicketsOf(mode, true)
	local nonce
	for _ = 1, 20 do
		nonce = Markets.random()
		if not tickets[eid .. "#" .. nonce] then break end
	end
	local t = { id = eid .. "#" .. nonce, eid = eid, idx = idx, o = ov, silver = tonumber(silver), copper = tonumber(silver) * 100, nonce = nonce,
		bank = ns.FullName(s.bank), mode = mode, cur = s.cur, type = m.type, t = Now(), state = "queued", tries = 0 }
	tickets[t.id] = t
	slipsPer[eid] = (slipsPer[eid] or 0) + 1
	lastSlip = Now()
	if queued and not Markets.BankOnline(s.bank) then
		t.state = "queued"
	else
		t.state = "sent"
		SendSlip(t)
	end
	Place(mode, rec)
	Markets.Involve()
	Changed()
	return t
end

-- My tickets: filter = { eid, open = true, mode }. A ticket: { id, eid, idx, o, silver, copper,
-- nonce, bank, mode, cur, type, t, state, code, payout }; state: queued, sent, key, unconfirmed,
-- offline, accepted, locked, held (OPEN_TICKET), refused (code: the bank's), won, lost, void (code:
-- the void's, or "refund"), settled (the payout could not be told here). A v2 Lottery ticket is
-- won whenever it receives its one refund (and any profit); only unclaimed profit, never a ticket,
-- is rolled forward.
function Markets.Tickets(filter)
	filter = type(filter) == "table" and filter or {}
	local out = {}
	for _, mode in ipairs(filter.mode and { filter.mode } or { "L", "T" }) do
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and (not filter.eid or t.eid == filter.eid) and (not filter.open or OPEN_TICKET[t.state]) then out[#out + 1] = t end
		end
	end
	table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
	return out
end
function Markets.Ticket(id, mode)
	for _, md in ipairs(mode and { mode } or { "L", "T" }) do
		local t = TicketsOf(md)[id]
		if t then return t end
	end
	return nil
end

-- The payout of one ticket from a settled book (principle 2: every bettor computes his own, to
-- the copper, from the public pools and the result): its copper, or nil when it cannot tell.
function Markets.PayoutOf(rec, t)
	local s = rec.sheet
	local m = s and s.markets[t.idx]
	local b = rec.book and rec.book.markets[t.idx]
	if not m or not b or b.state ~= "S" then return nil end
	local kind = KINDS[m.type]
	local M = Math()
	local fee = FeeArg(s)
	if kind.pick then
		local top, nwin = (b.result or ""):match("^P%x+%.([0-9a-z]+)%.([0-9a-z]+)$")
		top, nwin = N36(top, 0), N36(nwin, 0)
		local res = ReadResult(m, m.result)
		local size = s.size or m.n
		local rounds = 0
		while 2 ^ rounds < size do rounds = rounds + 1 end
		local mine = res and M.PickScore(t.o:sub(2), res.pick, rounds)
		if not top or not nwin or mine == nil then return nil end
		local entries = b.counts[1]
		if nwin == 0 or nwin >= entries then return t.copper end
		if mine ~= top then return 0 end
		-- The winners share as one outcome (each the same stake): stake + floor(D / winners).
		local bets = {}
		for i = 1, nwin do bets[#bets + 1] = { o = "w", s = t.copper } end
		for i = 1, entries - nwin do bets[#bets + 1] = { o = "l", s = t.copper } end
		local r = M.Settle(bets, { "w" }, fee)
		return r and r.payouts[1] or nil
	end
	if kind.lottery then
		local Lo = ns.Lottery
		local wire = Lo and Lo.DecodeResult and Lo.DecodeResult(b.result)
		local ledger = rec.ledgerBets
		if not wire or type(ledger) ~= "table" then return nil end
		local tickets, totals, mine = {}, {}, nil
		for id, bet in pairs(ledger) do
			if bet.eid == t.eid and bet.idx == t.idx then
				local animal, stake = tonumber(bet.o), tonumber(bet.copper)
				if not animal or not stake then return nil end
				tickets[#tickets + 1] = { id = id, animal = animal, stake = stake }
				totals[animal] = (totals[animal] or 0) + stake
				if id == t.ticketId then mine = id end
			end
		end
		for animal = 1, m.n do
			if (totals[animal] or 0) ~= (b.pools[animal] or 0) * 100 then return nil end
		end
		if not mine then return nil end
		local r = Lo.Settle({ version = Lo.SETTLEMENT_VERSION, tickets = tickets, draw = wire.draw,
			carry = CarryIn(m), feeBp = 600 })
		if not r or r.nextCarry ~= wire.nextCarry then return nil end
		return r.byId[mine]
	end
	local winners
	winners = {}
	for part in (b.result .. "+"):gmatch("([^+]*)%+") do winners[#winners + 1] = part end
	-- The pools as bets, his own apart: the per-bet rounding depends only on the pools and his stake.
	local bets, mine = {}, nil
	local scratched = Markets.ScratchedOf(s, m, Event(rec.eid))
	if scratched[t.o] or Markets.WholeScratch(s, m) then return t.copper end
	for o = 1, m.n do
		local p = (b.pools[o] or 0) * 100
		if o == t.o then
			if p < t.copper then return nil end
			bets[#bets + 1] = { o = Sel(o), s = t.copper }
			mine = #bets
			if p > t.copper then bets[#bets + 1] = { o = Sel(o), s = p - t.copper } end
		elseif p > 0 then
			bets[#bets + 1] = { o = Sel(o), s = p }
		end
	end
	-- The pot carried in joins the money won as a stake nobody backs (as the wallet settles it).
	if not mine then return nil end
	local r = M.Settle(bets, winners, fee)
	return r and r.payouts[mine] or nil
end

-- A book came: tickets on its markets learn their state (locked, won, lost, void, held); tickets
-- queued for an offline bank go now.
SettleTickets = function(mode, rec, was)
	local book = rec.book
	local changed = false
	for _, t in pairs(TicketsOf(mode)) do
		if type(t) == "table" and t.eid == rec.eid then
			local b = book.markets[t.idx]
			if t.state == "queued" and b and b.state == "O" and Now() < rec.sheet.lockAt then
				t.state = "sent"
				SendSlip(t)
				changed = true
			elseif b and (t.state == "accepted" or t.state == "locked" or t.state == "held" or t.state == "unconfirmed" or t.state == "sent" or t.state == "queued" or t.state == "offline") then
				if b.state == "V" then
					if t.state == "accepted" or t.state == "locked" or t.state == "held" then t.state, t.code, t.payout = "void", b.result, t.copper end
					if t.state == "sent" or t.state == "queued" or t.state == "unconfirmed" or t.state == "offline" then t.state, t.code = "void", b.result end
					changed = true
				elseif b.state == "S" and (t.state == "accepted" or t.state == "locked" or t.state == "held") then
					local pay = Markets.PayoutOf(rec, t)
					t.payout = pay
					local m = rec.sheet and rec.sheet.markets[t.idx]
					if pay == nil then t.state = "settled"
					elseif pay == 0 then t.state = "lost"
					elseif m and KINDS[m.type].lottery then t.state, t.code = "won", pay == t.copper and "refund" or nil
					elseif pay == t.copper then t.state, t.code = "void", "refund"
					else t.state = "won" end
					changed = true
				elseif b.state == "H" and (t.state == "accepted" or t.state == "locked") then
					t.state = "held"
					changed = true
				elseif (b.state == "L") and t.state == "accepted" then
					t.state = "locked"
					changed = true
				end
			end
		end
	end
	if changed then Place(mode, rec) Markets.Involve() end
end

-- The ledger's b entry is the acknowledgement (the design): matched on the full tuple (the
-- bank, the event, the market, the outcome, the stake and the nonce), never on a wallet code.
-- entry: a parsed table { k = "b", eid, idx, o (text: "3", "p1a2"), copper, nonce, t, code, i (its
-- place in a grouped entry: the bets of one seq are told apart by it) }, or
-- the money section's text "b:<code>:<eid>.<idx36>:<sel>:<copper>:<nonce>[:<t36>]".
function Markets.ParseEntry(entry)
	if type(entry) == "table" then
		local k = entry.k or entry.kind
		if k ~= "b" and k ~= "z" and k ~= "x" and k ~= "n" then return nil end
		local e = { k = k, eid = entry.eid, idx = tonumber(entry.idx), o = entry.o ~= nil and tostring(entry.o) or nil,
			copper = tonumber(entry.copper) or tonumber(entry.s) or (tonumber(entry.silver) and tonumber(entry.silver) * 100) or nil, nonce = entry.nonce,
			t = tonumber(entry.t), code = entry.code, acct = entry.acct, who = entry.who, result = entry.result,
			i = tonumber(entry.i) }
		if (not e.eid or not e.idx) and type(entry.market) == "string" then
			local eid, idx = entry.market:match("^([FNTKL][0-9a-z]+)%.([0-9a-z]+)$")
			e.eid, e.idx = eid, N36(idx, 1, Markets.MAX_MARKETS)
		end
		if not EidOk(e.eid) or not e.idx then return nil end
		return e
	end
	if type(entry) ~= "string" then return nil end
	local code, eid, idx, sel, copper, nonce, t = entry:match("^b:([^:]+):([FNTKL][0-9a-z]+)%.([0-9a-z]+):([%w]+):(%d+):([0-9a-z]+):?([0-9a-z]*)$")
	if code then
		return { k = "b", code = code, eid = eid, idx = N36(idx, 1, Markets.MAX_MARKETS), o = sel, copper = tonumber(copper), nonce = nonce, t = N36(t, 0) }
	end
	local ze = entry:match("^z:([FNTKL][0-9a-z]+%.[0-9a-z]+)$")
	if ze then
		local e2, i2 = ze:match("^(.+)%.(.+)$")
		return { k = "z", eid = e2, idx = N36(i2, 1, Markets.MAX_MARKETS) }
	end
	return nil
end

function Markets.OnEntry(bank, seq, entry)
	local e = Markets.ParseEntry(entry)
	if not e then return end
	local f = Fn(ns.MarketBank, "AuditEntry")
	if f then ns.SafeCall("markets audit entry", f, bank, seq, e) end
	if e.k ~= "b" then return end
	for _, mode in ipairs({ "L", "T" }) do
		local rec = Rec(mode, e.eid)
		local market = rec and rec.sheet and rec.sheet.markets[e.idx]
		if market and KINDS[market.type].lottery and Same(rec.sheet.bank, bank) then
			local Lo = ns.Lottery
			local id = Lo and Lo.TicketId and Lo.TicketId(seq, e.i or 1, e.nonce)
			if id then
				rec.ledgerBets = rec.ledgerBets or {}
				rec.ledgerBets[id] = { eid = e.eid, idx = e.idx, o = e.o, copper = e.copper,
					nonce = e.nonce, seq = seq, i = e.i or 1 }
			end
		end
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and t.eid == e.eid and t.idx == e.idx and t.nonce == e.nonce and Same(t.bank, bank)
				and Sel(t.o) == e.o and t.copper == e.copper and (t.state == "sent" or t.state == "unconfirmed" or t.state == "offline" or t.state == "key") then
				t.state, t.seq, t.i, t.acceptedAt = "accepted", seq, e.i or 1, Now()
				local Lo = ns.Lottery
				t.ticketId = Lo and Lo.TicketId and Lo.TicketId(seq, t.i, e.nonce) or nil
				local rec = Rec(mode, t.eid)
				if rec and rec.sheet and e.t and e.t >= rec.sheet.lockAt then t.late = true end
				if rec and rec.book then SettleTickets(mode, rec) end
				Markets.Involve()
				Changed()
			end
		end
	end
end

-- Subscribed once for each Wallet provider that can take it.  The test world installs the money part's
-- documented provider after INIT; an in-session provider hand-off must not strand open tickets on
-- the provider that was present before the hand-off.
local subscribed
function Markets.Subscribe()
	local f = Fn(ns.Wallet, "OnEntry")
	if not f then return false end
	if subscribed == f then return true end
	subscribed = f
	f(function(bank, seq, entry) ns.SafeCall("markets entry", Markets.OnEntry, bank, seq, entry) end)
	return true
end

-- The bank's answer: only for our own slip (the event and the nonce of a ticket to that bank).
local function OnAnswer(dist, sender, mode, body)
	local eid, nonce, code = ns.Arena.Fields(body, 3)
	if not code or not EidOk(eid) or not (nonce or ""):find("^[0-9a-z]+$") then return end
	local t = TicketsOf(mode)[eid .. "#" .. nonce]
	if not t or not Same(t.bank, sender) then return end
	heardBank[Lower(sender)] = Now()
	local rec = Rec(mode, eid)
	if code == "K" then
		if t.state == "sent" or t.state == "unconfirmed" or t.state == "offline" or t.state == "key" then t.state, t.acceptedAt = "accepted", Now() end
	elseif code == "E" then
		-- No verified key at the bank: our key claim goes to it, and the slip goes again once.
		Call(ns.Debts, "SendClaim", sender, mode)
		if not t.keyTried and OPEN_TICKET[t.state] then
			t.keyTried, t.state, t.code, t.keyAt = true, "key", "E", Now()
		else
			t.state, t.code = "refused", "E"
		end
	elseif code:match("^r[0-9a-z]*$") then
		t.busy = N36(code:sub(2), 0, 3600) or 30
		t.sentAt = Now() + t.busy - Markets.ACK_WAIT
	elseif code:match("^[UCOMRWENDAXPF]$") then
		if t.state ~= "accepted" and t.state ~= "locked" then t.state, t.code = "refused", code end
	end
	if rec and rec.book then SettleTickets(mode, rec) end
	Markets.Involve()
	Changed()
end

-- Resending (no BT recovery any more): the same slip again, same nonce, while the market is open,
-- after the bank's lag and ACK_WAIT, TRIES times at most; then "unconfirmed" (the ledger may
-- still bring its entry: it stays open).
local function TicketTick(now)
	for _, mode in ipairs({ "L", "T" }) do
		for _, t in pairs(TicketsOf(mode)) do
			if type(t) == "table" and OPEN_TICKET[t.state] then
				local rec = Rec(mode, t.eid)
				local s = rec and rec.sheet
				local open = s and now < s.lockAt and Markets.StateOf(rec, t.idx) == "O"
				local lag = rec and rec.book and rec.book.lag or 0
				if t.state == "sent" and open and now >= (t.sentAt or 0) + lag + Markets.ACK_WAIT then
					if t.tries < Markets.TRIES then SendSlip(t) else t.state = "unconfirmed" end
					Changed()
				elseif t.state == "key" and open and now >= (t.keyAt or 0) + Markets.KEY_WAIT then
					t.state = "sent"
					SendSlip(t)
				elseif (t.state == "sent" or t.state == "queued" or t.state == "offline" or t.state == "key") and s and not open then
					-- Never taken before the lock: nothing was held.
					if t.state ~= "sent" or now >= s.lockAt + Markets.ACK_WAIT * 3 then t.state, t.code = "unconfirmed", t.code end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quotes and the view (the design): every number a slip or a board shows comes from here
---------------------------------------------------------------------------

-- Markets.Quote(eid, idx, o, silver) -> { ok, why, odds (hundredths, nil for an outcome nobody
-- backed), payout (copper, if o wins, were it the last bet), fee = { g, a } (the guild's and the
-- arbiter's copper out of that win), cap (what may still be put here), after (the wallet's
-- balance after) }.
function Markets.Quote(eid, idx, o, silver)
	idx = tonumber(idx)
	local q = { fee = { g = 0, a = 0 } }
	q.ok, q.why = Markets.CanBet(eid, idx, o, silver)
	local rec = Find(eid)
	local s = rec and rec.sheet
	local m = s and s.markets[idx or -1]
	if not m then q.ok, q.why = false, "unknown" return q end
	local kind = KINDS[m.type]
	local M = Math()
	local ov = SlipOutcome(m, o, s)
	local copper = (tonumber(silver) or 0) * 100
	q.cap = kind.stake and (ov and m.value[ov] and m.value[ov] * 100 or 0) or (kind.pick and m.value * 100 or Markets.MyCap(rec, m))
	local W = ns.Wallet
	local st = Call(W, "Statement", s.bank)
	if type(st) == "table" then
		local bal = type(st[s.cur == "p" and "p" or "g"]) == "table" and st[s.cur == "p" and "p" or "g"].bal
		if type(bal) == "number" then q.after = bal - copper end
	end
	if not ov or type(ov) ~= "number" then return q end
	-- A Lottery ticket has no single "if this beast wins" quote: its refund is once per ticket and
	-- its profit depends on which of five positions (possibly several) the beast occupies. Showing
	-- the pool-market preview here would silently present all five positions as equal winners.
	if kind.lottery then q.lottery, q.contractVersion = true, 2 return q end
	local pools = Markets.PoolsOf(rec, idx)
	local fee = FeeArg(s)
	local k = kind.k or 1
	local scratched = Markets.ScratchedOf(s, m, Event(eid))
	for so in pairs(scratched) do pools[Sel(so)] = nil end
	if kind.lottery and CarryIn(m) > 0 then pools["~"] = CarryIn(m) end
	if k > 1 then q.odds = M.OddsAtLeast(pools, Sel(ov), k, fee) else q.odds = M.Odds(pools, Sel(ov), fee) end
	if copper > 0 then
		q.payout = M.Preview(pools, Sel(ov), copper, fee, k)
		if q.payout then
			-- His part of the fee on that win: what the winnings would be without it, less with it.
			local gross = M.Preview(pools, Sel(ov), copper, { g = 0, a = 0, to = "g" }, k)
			local cut = gross and gross - q.payout or 0
			local withArb = M.Preview(pools, Sel(ov), copper, { g = fee.g, a = 0, to = "g" }, k)
			local arbPart = 0
			if fee.to == "a" and withArb and gross then
				-- The arbiter's part: the payout with only the guild's part taken, less the payout.
				arbPart = withArb - q.payout
			end
			q.fee = { g = math.max(0, cut - arbPart), a = math.max(0, arbPart) }
		end
	end
	return q
end

local function KindLabel(m, ev)
	local key = "MARKETS_KIND_" .. m.type
	local text = L[key] or m.type
	if m.type == "DU" then return text:format(m.value or 0) end
	if m.type == "ST" then
		local e = Entrants(ev)[m.value]
		return text:format(e and NameOf(e) or ("#" .. tostring(m.value)))
	end
	return text
end
local function ClassName(token)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return type(names) == "table" and names[token] or (token:sub(1, 1) .. token:sub(2):lower())
end
function Markets.OutcomeLabel(m, o, ev)
	local typ = m.type
	local f = type(ev) == "table" and ev.fighters or {}
	if typ == "MW" or typ == "SW" or typ == "FB" or typ == "BH" or typ == "CX" or typ == "FK" or typ == "DR" then
		return NameOf(f[o == 1 and "A" or "B"])
	elseif typ == "B3" then
		local who = o <= 2 and NameOf(f.A) or NameOf(f.B)
		local score = (o == 1 or o == 4) and "2-0" or "2-1"
		return (L.MARKETS_SCORE or "%s %s"):format(who, score)
	elseif typ == "KO" then
		return o == 1 and L.MARKETS_KNOCKOUT or L.MARKETS_FLED
	elseif typ == "DU" then
		return (o == 1 and L.MARKETS_OVER or L.MARKETS_UNDER):format(m.value or 0)
	elseif typ == "ST" then
		return L["MARKETS_STAGE_" .. o] or tostring(o)
	elseif typ == "WC" then
		return ClassName(Markets.CLASSES[o] or "?")
	elseif KINDS[typ].lottery then
		local Lo = ns.Lottery
		local beast = type(Lo) == "table" and type(Lo.BEASTS) == "table" and Lo.BEASTS[o]
		local name = type(beast) == "table" and beast.name or (type(beast) == "string" and beast) or nil
		return name and ("%02d %s"):format(o, name) or ("%02d"):format(o)
	elseif KINDS[typ].entrants then
		local e = Entrants(ev)[o]
		return (L.MARKETS_ENTRANT or "#%d %s"):format(o, e and NameOf(e) or "?")
	end
	return tostring(o)
end

-- Markets.View(eid) -> { eid, mode, lockAt, bank, cur, fee = { g, a, to }, private, trial,
--   markets = { { idx, type, label, state, result, param, trial, scratched, outcomes = { { o, label,
--   pool (copper), count, odds (hundredths or nil), scratched } } } } }, or nil. A Lottery day also
--   has carry = { from, copper } (the pot it carried in; each row its copper as row.carry) and, once
--   drawn, lottery = { prizes = { n1..n5 }, text }; its row's result is the book's once settled (the
--   versioned L2 wire, whose final field is unclaimed profit: Markets.Rolled).
function Markets.View(eid)
	local rec, mode = Find(eid)
	local s = rec and rec.sheet
	if not s then return nil end
	local ev = Event(eid)
	local M = Math()
	local fee = FeeArg(s)
	local v = { eid = eid, mode = mode, lockAt = s.lockAt, bank = s.bank, cur = s.cur, fee = { g = s.fee.g, a = s.fee.a, to = s.fee.to },
		private = SheetPrivate(s), rehearsal = mode == "T", markets = {}, bankOnline = Markets.BankOnline(s.bank),
		lag = rec.book and rec.book.lag or nil, bookAt = rec.book and rec.book.heard or nil }
	for _, idx in ipairs(s.order) do
		local m = s.markets[idx]
		local kind = KINDS[m.type]
		local state, result = Markets.StateOf(rec, idx)
		local row = { idx = idx, type = m.type, label = KindLabel(m, ev), state = state, result = result, param = m.param, trial = kind.trial and true or nil,
			private = kind.private and true or nil, outcomes = {} }
		local pools, counts = Markets.PoolsOf(rec, idx)
		local scratched = Markets.ScratchedOf(s, m, ev)
		if kind.pick then
			row.pool, row.count, row.entry = pools.total, counts.total, m.value * 100
		else
			local oddsPools = {}
			for o = 1, m.n do if not scratched[o] then oddsPools[Sel(o)] = pools[Sel(o)] end end
			if kind.lottery then
				local carry, from = CarryIn(m)
				if carry > 0 then oddsPools["~"] = carry end
				row.carry = carry
				v.carry = v.carry or (from and { from = from, copper = carry }) or nil
				local res = (m.state == "R") and ReadResult(m, m.result) or nil
				if res and not v.lottery then v.lottery = { prizes = res.draw, text = m.result } end
			end
			for o = 1, m.n do
				local odds
				if not scratched[o] and not kind.private and not kind.lottery then
					if (kind.k or 1) > 1 then odds = M.OddsAtLeast(oddsPools, Sel(o), kind.k, fee) else odds = M.Odds(oddsPools, Sel(o), fee) end
				end
				row.outcomes[#row.outcomes + 1] = { o = o, label = Markets.OutcomeLabel(m, o, ev), pool = pools[Sel(o)], count = counts[Sel(o)],
					odds = odds, scratched = scratched[o] or nil }
			end
		end
		v.markets[#v.markets + 1] = row
	end
	return v
end

-- The public markets heard (every mode): { { eid, mode, lockAt, state, bank } }, lockAt order.
function Markets.Public()
	local out = {}
	for _, mode in ipairs({ "L", "T" }) do
		local core, heavy, mem = Tables(mode)
		for _, t in ipairs({ core or {}, heavy or {}, mem or {} }) do
			for eid, rec in pairs(t) do
				local s = type(rec) == "table" and rec.sheet
				if s and not SheetPrivate(s) then
					local open = false
					for idx in pairs(s.markets) do if Markets.StateOf(rec, idx) == "O" then open = true end end
					out[#out + 1] = { eid = eid, mode = mode, lockAt = s.lockAt, open = open, bank = s.bank }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.lockAt < b.lockAt end)
	return out
end

---------------------------------------------------------------------------
-- Overrules (BV, as the design amends them)
---------------------------------------------------------------------------

-- A leader's weight: the King's character 3, a Steward 2, a High Councillor or a signed arbiter 1
-- (in T the stand-ins: the King's 3, a public arbiter's 1); 0 for anyone else.
function Markets.Weight(name, mode)
	if type(name) ~= "string" or name == "" then return 0 end
	local R = Roles()
	local full = ns.FullName(name)
	if R and R.IsKing and R.IsKing(full) then return 3 end
	local K = ns.King
	if K and K.IsStewardName and K.IsStewardName(full) then return 2 end
	if ns.IsHighCouncillor(full) or ns.IsSignedArbiter(full) then return 1 end
	if mode == "T" and R and type(R.standIn) == "function" then
		local ok, k = pcall(R.standIn, full, "k", "T")
		if ok and k == true then return 3 end
		local ok2, p = pcall(R.standIn, full, "p", "T")
		if ok2 and p == true then return 1 end
	end
	return 0
end

-- Why a name may not overrule this event (the part every client can see; the bank adds the ticket
-- holders, their alts and keys): "official", "fighter", "bank", "ticket", or nil.
function Markets.Interested(rec, name)
	local s = rec and rec.sheet
	local ev = Event(rec.eid)
	for _, n in ipairs(Officials(ev, s)) do if Same(n, name) then return "official" end end
	for _, f in ipairs(Fighters(ev)) do if Same(f.name, name) then return "fighter" end end
	for _, e in pairs(Entrants(ev)) do if type(e) == "table" and Same(e.name, name) then return "fighter" end end
	if s and Same(s.bank, name) then return "bank" end
	if Same(name, ns.me) then
		for _, t in pairs(TicketsOf(rec.mode)) do
			if type(t) == "table" and t.eid == rec.eid and t.state ~= "refused" then return "ticket" end
		end
	end
	return nil
end

-- The words kept for a market: its own and the event's ("*"), newest per sender.
local function WordsFor(rec, idx)
	local out = {}
	for _, key in ipairs({ tostring(idx), "*" }) do
		for _, w in pairs(rec.words[key] or {}) do out[#out + 1] = w end
	end
	return out
end
Markets.WordsFor = WordsFor
-- Two weight-1 words are independent when they come from two people (no alt link, no shared key).
local function Independent(a, b)
	if Same(a.by, b.by) then return false end
	local D = ns.Debts
	local so = Call(D, "SameOwner", a.by, b.by)
	if so == true then return false end
	if a.fp and b.fp and a.fp == b.fp then return false end
	local Al = ns.Alts
	local linked = Call(Al, "Linked", a.by)
	for _, n in ipairs(type(linked) == "table" and linked or {}) do if Same(n, b.by) then return false end end
	return true
end
-- What the words say now: nil (nothing), or code ("H" | "P" | "V") and the weight it holds with.
-- The highest weight decides (a word never undoes a higher one), its newest word; a weight-1 V or
-- P is a hold until a second, independent weight-1 word confirms it (a weight-2 word decides
-- above it anyway). Only the King's or a Steward's V is final alone.
function Markets.Effective(words)
	local top = 0
	for _, w in ipairs(words) do if w.weight > top then top = w.weight end end
	if top == 0 then return nil end
	local level = {}
	for _, w in ipairs(words) do if w.weight == top then level[#level + 1] = w end end
	table.sort(level, function(a, b) return a.t > b.t end)
	local newest = level[1]
	if top >= 2 or newest.code == "H" then return newest.code, top end
	for i = 2, #level do
		local w = level[i]
		if w.code == newest.code and Independent(newest, w) then return newest.code, top end
	end
	return "H", top
end

local function WordBody(eid, idx, code, t) return ("%s~%s~%s~%s"):format(eid, idx == "*" and "*" or B36(idx), code, B36(t)) end
local function SendWord(rec, w)
	return ns.Arena.Send("BV", rec.mode, WordBody(rec.eid, w.idx, w.code, w.t), { key = "bv " .. rec.eid .. " " .. tostring(w.idx), dist = ns.Arena.Lane(rec.mode, true) })
end

-- A private market's sheet goes to its parties and its bank alone: a leader rules on it (a Farkle
-- table held for the auditors, the design) by its event's id, and the bank checks his interest.
function Markets.CanOverrule(eid, idx, code, mode)
	if ns.Arena.Off() then return false, "off" end
	if code ~= "V" and code ~= "H" and code ~= "P" then return false, "code" end
	if not EidOk(eid) then return false, "unknown" end
	local rec, found = Find(eid, mode)
	mode = found or mode or ns.Arena.NewMode(false)
	if Markets.Weight(ns.me, mode) == 0 then return false, "leader" end
	if Markets.Interested(rec or { eid = eid, mode = mode }, ns.me) then return false, "conflict" end
	if rec and rec.sheet and idx ~= "*" and not rec.sheet.markets[tonumber(idx) or -1] then return false, "unknown" end
	return true
end

-- Markets.Overrule(eid, idx|"*", "V"|"H"|"P"): a leader's word on the channel, repeated every
-- BV_REPEAT until the markets are settled or void, and BV_AFTER after.
function Markets.Overrule(eid, idx, code, mode)
	if idx ~= "*" then idx = tonumber(idx) end
	local ok, why = Markets.CanOverrule(eid, idx, code, mode)
	if not ok then return false, why end
	local rec, found = Find(eid, mode)
	mode = found or mode or ns.Arena.NewMode(false)
	rec = rec or NewRec(mode, eid)
	local w = { idx = idx, code = code, t = Now(), by = ns.FullName(ns.me), weight = Markets.Weight(ns.me, mode) }
	local key = tostring(idx)
	rec.words[key] = rec.words[key] or {}
	rec.words[key][Lower(ns.me)] = w
	rec.given, rec.givenDone, rec.givenAt = w, nil, Now()
	SendWord(rec, w)
	Place(mode, rec)
	local f = Fn(ns.MarketBank, "OnWord")
	if f then ns.SafeCall("markets bank word", f, mode, rec, w) end
	Markets.Involve()
	Changed()
	return true
end

local function OnWord(dist, sender, mode, body)
	-- (A word goes on the channel, where the auditors hear it too: never one whispered to the bank.)
	if dist == "WHISPER" then return end
	local eid, idx, code, t = ns.Arena.Fields(body, 4)
	if not t or not EidOk(eid) or (code ~= "V" and code ~= "H" and code ~= "P") then return end
	t = N36(t, 1)
	if not t or t > Now() + 60 then return end
	if idx ~= "*" then idx = N36(idx, 1, Markets.MAX_MARKETS) if not idx then return end end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return end
	local rec = Rec(mode, eid)
	if not rec or not rec.sheet then return end
	local weight = Markets.Weight(sender, mode)
	if weight == 0 then return end
	-- Refused from anyone with an interest (as far as this client knows; the bank knows more).
	local why = Markets.Interested(rec, sender)
	if why then ns.Log("markets: overrule on %s from %s refused: %s", eid, sender, why) return end
	local key = tostring(idx)
	rec.words[key] = rec.words[key] or {}
	local kept = rec.words[key][Lower(sender)]
	if kept and kept.t >= t then return end
	local _, fp = Call(ns.Debts, "Verified", sender)
	local w = { idx = idx, code = code, t = t, by = ns.FullName(sender), weight = weight, fp = type(fp) == "string" and fp or nil }
	rec.words[key][Lower(sender)] = w
	local f = Fn(ns.MarketBank, "OnWord")
	if f then ns.SafeCall("markets bank word", f, mode, rec, w) end
	Changed()
end

---------------------------------------------------------------------------
-- The ticker's work: the opener's lock and repeats, the tickets, the overrules' repeats
---------------------------------------------------------------------------

local lastPrune = -math.huge
Tick = function()
	local now = Now()
	for _, mode in ipairs({ "L", "T" }) do
		local core = Tables(mode)
		for _, rec in pairs(core or {}) do
			if type(rec) == "table" and rec.sheet and rec.own and not rec.done then
				if LockOwn(rec) then
					Publish(rec, true)
				else
					local gap = RepeatGap(rec)
					if rec.unsent then
						SendSheet(rec, rec.unsent == "u")
					elseif not gap then
						rec.done = true
					elseif now - (rec.sentAt or 0) >= gap then
						SendSheet(rec, false)
					end
				end
			end
			-- A leader's word goes again every BV_REPEAT until its markets are settled or void, and
			-- BV_AFTER after (a private market this client never saw: BV_AFTER after it was given).
			if type(rec) == "table" and rec.given and not rec.givenDone then
				local w = rec.given
				local over = true
				for idx in pairs(rec.sheet and rec.sheet.markets or {}) do
					local st = Markets.StateOf(rec, idx)
					if (w.idx == "*" or w.idx == idx) and st ~= "S" and st ~= "V" then over = false end
				end
				if over then rec.overWordAt = rec.overWordAt or (rec.sheet and now or w.t) end
				if over and now - rec.overWordAt > Markets.BV_AFTER then
					rec.givenDone = true
				elseif now - (rec.givenAt or 0) >= Markets.BV_REPEAT then
					rec.givenAt = now
					SendWord(rec, w)
				end
			end
		end
	end
	TicketTick(now)
	if pending[1] then RetryPending() end
	if now - lastPrune >= Markets.PRUNE_EVERY then
		lastPrune = now
		Markets.Prune()
	end
	Markets.Involve()
end
Markets.Tick = function() return Tick() end

-- Pruning (the design): tickets past their keep (never an open one), events past theirs (never an
-- open one), each table under its cap.
function Markets.Prune()
	local now = Now()
	for _, mode in ipairs({ "L", "T" }) do
		local store = StoreOf(mode)
		if type(store) == "table" and type(store.tickets) == "table" then
			for who, list in pairs(store.tickets) do
				local n, closed = 0, {}
				for id, t in pairs(list) do
					if type(t) ~= "table" then list[id] = nil
					else
						n = n + 1
						if not OPEN_TICKET[t.state] then closed[#closed + 1] = t end
					end
				end
				table.sort(closed, function(a, b) return (a.t or 0) < (b.t or 0) end)
				for _, t in ipairs(closed) do
					if now - (t.t or 0) > Markets.TICKET_KEEP or n > Markets.TICKETS_MAX then list[t.id] = nil n = n - 1 end
				end
			end
		end
		local core, heavy, mem = Tables(mode)
		for _, t in ipairs({ core or {}, heavy or {}, mem or {} }) do
			local list = {}
			for eid, rec in pairs(t) do
				if type(rec) ~= "table" then t[eid] = nil
				else list[#list + 1] = rec end
			end
			table.sort(list, function(a, b) return (a.heard or 0) < (b.heard or 0) end)
			local n = #list
			for _, rec in ipairs(list) do
				local open = false
				for idx in pairs(rec.sheet and rec.sheet.markets or {}) do
					local st = Markets.StateOf(rec, idx)
					if st ~= "S" and st ~= "V" then open = true end
				end
				if not open and (now - (rec.heard or 0) > Markets.EVENT_KEEP or n > Markets.EVENTS_MAX) and not (rec.own and not rec.done) then
					t[rec.eid] = nil
					n = n - 1
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The Lottery (the design): the market engine as the Lottery uses it. A day is an event of the letter L
-- (the Lottery's Arena.Events.Register("L", fn): { kind = "lottery", opener = the caller, the King's
-- character (a King's stand-in in T), public = true, mode, lockAt = the draw, excluded = { the
-- caller, the bank }: they and their alts and keys bet nothing }), with one market of type LO: 25
-- outcomes, the beasts, all of the 6% to the guild (the sheet says to = "g"; receivers refuse any
-- other), no arbiter. Never opened by a bank: it sees every bet by name before a draw it may roll.
-- The exact calls, on the caller's client unless said:
--   OPEN     Markets.Open(eid, { markets = { { type = "LO", param = <carry> } }, lockAt = <draw>,
--              bank, cur, mode }) -> true | false, why; or Markets.OpenLottery(eid, { drawAt,
--              carry = { from, copper } | nil, bank, cur, mode }). Its wire param is "2" (none), or
--              "2.<from eid>.<copper b36>"; Markets.Carry(from) gives an earlier day's unclaimed
--              profit after it is declared (or a void day's retained incoming pot).
--   LOCK     nothing to call: the bank closes the day by its own clock at lockAt (the draw);
--              Markets.SetLock(eid, t) moves it (the opener only; never under the window's rules).
--   SETTLE   Markets.DeclareDraw(eid, { n1..n5 }) -> true, n | false, why (0-9999, the /roll's
--              10000 is 0000). After GRACE the bank calls Wallet.SettleLottery: every ticket on a
--              drawn animal is refunded once; the profit pool pays 50/25/15/10 by position, fifth
--              refund-only; 6% is charged once on claimed gross profit. Its L2 result names all five
--              animals and the exact unclaimed carry. A versionless per-market result is refused.
--   CARRY    each unclaimed gross tranche remains in the settled source ledger until a later v2
--              day names that exact amount. Wallet.Carry moves only that retained profit, once;
--              refunds, paid profit and fee never roll forward.
--   VOID     Markets.Void(eid, idx|"*", code): X (cancelled), R (a pot that cannot go on: the
--              next day's terms differ), ...; a void day's pot carried in is Markets.Carry's too.
--   READ     Markets.View(eid): v.carry = { from, copper }, v.lottery = { prizes, text } once
--              drawn, the row's state (O L R H S V), L2 result and Markets.Rolled carry;
--              Markets.Tickets{ eid }: { o, silver, copper, state, payout }.
--   DRAW     on the bank, the Lottery registers MarketBank.SetGate("L", fn(eid, idx, result, mode)): true
--              only when the bank's client saw the drawer's five server roll lines, in order, after
--              lockAt, matching the declared prizes; "hold" when it saw other ones (and every client
--              whose own roll lines differ sets its event's disagree: the bank holds then too);
--              false while it has seen none (after GATE_WAIT of that, the bank holds).
--   Markets.BeastOf(n) -> 1-25   the beast of a four-digit number (01-04 = 1 ... 97-00 = 25).
---------------------------------------------------------------------------

-- The last two digits: 01-04 is 1 ... 97-00 is 25.
function Markets.BeastOf(n)
	n = tonumber(n)
	if not n or n ~= math.floor(n) or n < 0 or n > 10000 then return nil end
	local d = n % 100
	if d == 0 then d = 100 end
	return math.floor((d + 3) / 4)
end
function Markets.OpenLottery(eid, spec)
	spec = type(spec) == "table" and spec or {}
	local carry = spec.carry
	if type(carry) ~= "table" and spec.from then carry = { from = spec.from, copper = carry } end
	return Markets.Open(eid, { markets = { { type = "LO", param = type(carry) == "table" and carry or nil } }, lockAt = spec.drawAt or spec.lockAt,
		bank = spec.bank, cur = spec.cur, mode = spec.mode })
end
function Markets.DeclareDraw(eid, draw)
	return Markets.Declare(eid, { draw = draw })
end
-- The unclaimed profit a day passes on (copper, and from = eid). A declared v2 day can expose it
-- from the public pools before the bank has moved it; a settled row carries its signed wire value.
-- A void day exposes only the pot it had carried in. Zero means there is nothing to claim.
function Markets.Carry(eid)
	local rec = Find(eid)
	local s = rec and rec.sheet
	if not s then return 0 end
	for _, idx in ipairs(s.order) do
		local m = s.markets[idx]
		local b = rec.book and rec.book.markets[idx]
		if KINDS[m.type].lottery then
			local rolled = Markets.Rolled(b)
			if rolled ~= nil then return rolled, rolled > 0 and eid or nil end
			if (b and b.state == "V") or m.state == "V" then
				local c = CarryIn(m)
				return c, c > 0 and eid or nil
			end
			if m.state == "R" and b and b.state ~= "O" then
				local r = Markets.LotterySettlement(m, b.pools, false, 600)
				if r then return r.nextCarry, r.nextCarry > 0 and eid or nil end
			end
			return 0
		end
	end
	return 0
end

---------------------------------------------------------------------------
-- Actions (every button goes through Arena.Can/Do) and wiring
---------------------------------------------------------------------------

ns.Arena.Action("bet", function(eid, idx, o, silver) return Markets.CanBet(eid, tonumber(idx), o, silver) end,
	function(eid, idx, o, silver, queued)
		local t, why = Markets.Bet(eid, idx, o, silver, queued)
		if not t then return false, why end
		return true, t
	end)
ns.Arena.Action("overrule", function(eid, idx, code) return Markets.CanOverrule(eid, idx == "*" and "*" or tonumber(idx), code) end,
	function(eid, idx, code) return Markets.Overrule(eid, idx, code) end)
ns.Arena.Action("closebets", function(eid)
	-- (The Bell is off in combat lockdown, the design: its urgent sheet could not go.)
	if ns.Arena.Blocked() then return false, "blocked" end
	local rec = Find(eid)
	if not rec or not rec.own then return false, "sheet" end
	return true
end, function(eid) return Markets.CloseBets(eid) end)

ns.On("INIT", function() Markets.Subscribe() end)
ns.On("LOGIN", function()
	session.login = Now()
	-- (The fee in force at login: a change the King makes later keeps the one before it FEE_CHANGE.)
	local s = Settings()
	feeSeen[ns.realm] = { cur = { tonumber(s.feeBp) or 600, tonumber(s.arbBp) or 200 } }
	Markets.Subscribe()
	Markets.Prune()
	Markets.Involve()
end)

ns.Comm.Handle("BM", ns.Arena.Handle("BM", OnSheet))
ns.Comm.Handle("BO", ns.Arena.Handle("BO", OnBook))
ns.Comm.Handle("BK", ns.Arena.Handle("BK", OnAnswer))
ns.Comm.Handle("BV", ns.Arena.Handle("BV", OnWord))
-- The slip is the bank's to judge (MarketBank.lua): registered here, where the design lists it.
ns.Comm.Handle("BS", ns.Arena.Handle("BS", function(dist, sender, mode, body)
	local f = Fn(ns.MarketBank, "HandleSlip")
	if f then f(dist, sender, mode, body) end
end))
