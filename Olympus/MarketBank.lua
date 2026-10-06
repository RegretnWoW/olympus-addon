local ADDON, ns = ...

-- 1.2, the Blood Arena: MarketBank.lua. A stub the arena's core created for the markets (markets) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- On the bank's client: slip checks, lock, grace, hold, settlement, void, flags (BF) and the BO
-- pump. Registers BF. The bank's markets are an index rebuilt from the ledger at load.
local MarketBank = {}
ns.MarketBank = MarketBank

local L = ns.L

-- The bank's half of the markets (the design, as amended). It acts only
-- on the client of a bank of this realm's T1~B that a sheet names (Roles.IsBank), never on a
-- treasury keeper's, and in gold only where saved data survives (Arena.Persists, the design).
--   A SLIP (BS) is checked in this order, the cheap checks first (the design):
--     U  not a market of mine (no sheet, not this bank, not on duty: closing, the King's live
--        switch off in L, a keeper's client)
--     K  the same (sender, nonce) taken already with the same tuple: answered again (at most once
--        every K_GAP), never held twice; U when that nonce came with another (event, market,
--        outcome, stake), on any of this bank's events
--     R  the sender's rate (1 per 2 s, 20 per event): every slip from here on counts for the 2 s,
--        so a flood of refusals is refused too
--     E  the account's key is not verified (Debts.Verified): the bettor's client sends its ZT
--     r  the bank is busy (its per-minute rate, lockdown): try again in N s (the code carries N)
--     C  closed (the market is not O, or the bank's clock is at lockAt or past it): not whispered
--     O  the outcome (scratched, or not one of the market's; a bracket pool's picks)
--     M  the stake (whole silver, at least minBet; a bracket pool's entry; a stake market's own)
--     W  no wallet account
--     E  not eligible (no Olympus guild or under minLevel at deposit, frozen, no bound GUID)
--     N  net-off (Moderation)
--     D  an open debt (Debts.Blocked)
--     A  a conflict (the design): the event's officials, the bank, a fighter or an
--        entrant past what he may bet, their alts and keys; KO and B3 to a fighter's guildmate
--     X  the caps (the King's maxBet, 5 g on KO and B3, his standing's; maxDay; one bracket entry)
--     P  the room (maxPool, a tenth on KO and B3; MAX_BETS_EVENT; the bank's cap at Wallet.Hold)
--     F  the funds (Wallet.Available, then Wallet.Hold)
--   An accepted bet is the ledger's b entry (Wallet.Hold writes it): no whisper, but for a stake
--   market (CX, FK), whose entry goes on the channel as an opaque digest, and a resent nonce (K).
--   Refusals are whispered on the ordinary lane, at most one per sender every ANSWER_GAP.
--   The LOCK is the bank's clock: at lockAt every open market closes (Wallet.Close, the ledger's z,
--   sent urgently), or voids when one-sided (1) or a stake is missing (S); the locked book goes
--   urgently. The GRACE runs GRACE from the declaration (a correction restarts it); a HOLD (the
--   declaration against the game's duel line "!", the witnesses disagreeing, whenever the bank
--   learns it, a leader's BV H, a gate's "hold", or a gate still waiting GATE_WAIT after the grace)
--   stops it; after HOLD_MAX a hold from the game settles by the game's duel line (the arbiter's
--   client or two independent witnesses recorded one) or voids, one from a word pays the declared
--   result (the design). SETTLEMENT is Wallet.Settle (every credit through ArenaMath.Settle, the
--   scratched refunded); a VOID is Wallet.Void. A market is shown settled or void only once the
--   wallet did it; else it holds ("wallet") for a leader's P, and after HOLD_MAX voids, unless the
--   ledger shows it settled already. A Lottery settles all five positions first; Wallet.Carry moves
--   only its exact retained unclaimed profit to a later day that names it.
--   While the King's live switch is off (L) the bank takes no slip and moves no money: its markets
--   wait (locks, payouts, voids) and its books wait for the switch, none dropped.
--
-- WHAT IT CALLS (the money part's Wallet, bank side, as its 1.2 branch builds it; the design):
--   Wallet.Account(name) -> acct | nil
--   Wallet.Facts(acct) -> { gk, guild, level, fp, frozen, bound (false: no GUID bound yet) }
--   Wallet.Available(acct, cur) -> copper
--   Wallet.Register(eid, idx, spec) -> writes n; spec = { market = "<eid>.<idx36>", type, param, n,
--     nsel, places (k), closes (lockAt), feeBp (the whole fee), arbBp, to ("a"|"g"; always "g" for
--     the Lottery), kind ("p" pool | "s" stakes | "l" Lottery v2), parties, stakes, rounds, cur, arbiter (the
--     opener), mode }
--   Wallet.Hold(acct, copper, ref) -> seq | nil, why ("funds" | "cap" | ...); ref = { eid, idx,
--     market, o (the selection's text: "3", "p1a2"), nonce, t (the bank's second), cur, mode, stake }
--   Wallet.Close(eid, idx)                   the z entry (urgent)
--   Wallet.Settle(eid, idx, winners, scratched) -> credits through ArenaMath.Settle (or
--     ArenaMath.Pickem for "P<hex>"); winners: { "1", "a" } or "P<hex>"; scratched: { "3", ... }
--     (their stakes back, the design; the money part writes them into x so a replay settles alike). A pot the
--     market carries in (Wallet.Pot) joins the money won there, from the wallet's own ledger.
--     false or nil, why: not paid (the market holds).
--   Wallet.SettleLottery(eid, idx, draw) -> versioned five-place result; refunds once, then
--     50/25/15/10 profit tranches and fifth refund-only, with aggregate 6% fee.
--   Wallet.Void(eid, idx, code) -> every stake back, no fee; false or nil, why: not done (it holds)
--   Wallet.Carry(eid, idx, toEid, toIdx) -> copper   moves a settled Lottery's unclaimed profit.
--     On a settled void market, it moves only the incoming pot it kept; refunded stakes never roll.
--   Wallet.Pot(eid, idx) -> copper           the pot a market holds from earlier ones
--   Wallet.Market(eid, idx) -> { closed, settled, result } | nil   (a void's fallback checks it)
--   Wallet.Lag() -> seconds (the book's lag; else Wallet.Backlog(mode) -> entries, at BANK_RATE)
--   Wallet.Entries(fn, mode)                 optional: fn(seq, entry) for the bank's own ledger,
--     oldest first, entry = { k = "n"|"b"|"z"|"x", eid, idx, o, copper, nonce, t, who, acct,
--     result }: the index is rebuilt from it at load (the design "bankEvents"); without it,
--     Wallet.Bets(eid, idx) and Wallet.Market(eid, idx)
-- and Debts.Verified, Debts.Blocked, Debts.SameOwner, Standing.Cap, Moderation.Hidden/Hides.
-- WHAT OTHERS CALL: MarketBank.SetGate(letter, fn) (the Bones tables' "K": a Farkle stake market settles only
-- when the arbiter's KE agrees with a player's; the Lottery's "L": the draw's roll lines as the bank saw
-- them: fn(eid, idx, result, mode) -> true | false (wait) | "hold"); MarketBank.Auditors = fn(mode,
-- ev) (the money part may give the auditors it heard, ZQ~H); MarketBank.View(mode) (the bank's console);
-- MarketBank.AuditOf(mode, eid) (an auditor's screen: flags, mismatches); MarketBank.Rebuild(mode).

MarketBank.BO_GAP, MarketBank.BO_GAP_LAST, MarketBank.BO_LAST = 10, 5, 60 -- an event's book at most every 10 s (5 s in its last minute)
MarketBank.BO_ALL_GAP = 4           -- ... and 4 s between any two ordinary books (round robin)
MarketBank.BO_LONG_GAP = 30         -- a tournament's (open for days) change at most every 30 s
MarketBank.BO_REPEAT, MarketBank.BO_REPEAT_LONG = 120, 300
MarketBank.BO_AFTER, MarketBank.BO_AFTER_FOR = 300, 1800
MarketBank.RATE_GAP, MarketBank.RATE_EVENT = 2, 20
MarketBank.ANSWER_GAP = 2           -- at most one refusal whispered to a sender this often (the rest dropped)
MarketBank.K_GAP = 20               -- a nonce taken already is answered K at most this often
MarketBank.BANK_RATE = 150          -- bets a minute the ledger can publish (the design: plan on 150)
MarketBank.BUSY_WAIT = 30           -- "try again in" when busy
MarketBank.LOCKDOWN_WAIT = 60
MarketBank.MAX_BETS_EVENT = 6000
MarketBank.EVENTS_MAX, MarketBank.FULL_EVENTS, MarketBank.FULL_KEEP = 40, 10, 30 * 86400
-- The flags (the design): not refusals, whispered to auditors.
MarketBank.UNDER = 25               -- % of the pool an outcome held before a spike, or a surge
MarketBank.SPIKE_POOL = 50 * 10000  -- the pool at least this for a spike
MarketBank.SPIKE_MEDIAN, MarketBank.SPIKE_SHARE, MarketBank.SPIKE_MIN = 3, 10, 20 * 10000
MarketBank.LATE_WINDOW, MarketBank.LATE_GROW, MarketBank.LATE_MIN = 120, 50, 50 * 10000
MarketBank.GUILDMATE_MIN = 20 * 10000
MarketBank.REPEAT_U = 3

local function Markets() return ns.Markets end
local function Roles() return ns.ArenaRoles end
local function Now() return ns.Arena.Now() end
local function B36(n) return ns.Arena.B36(n) end
local function N36(s, lo, hi) return ns.Arena.N(s, lo, hi) end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b)
	local x = Lower(a)
	return x ~= nil and x == Lower(b)
end
local function Fn(t, k)
	local v = type(t) == "table" and t[k]
	return type(v) == "function" and v or nil
end
local function Call(t, k, ...)
	local f = Fn(t, k)
	if not f then return nil end
	local ok, a, b, c, d = pcall(f, ...)
	if not ok then ns.Log("market bank: %s failed: %s", tostring(k), tostring(a)) return nil end
	return a, b, c, d
end
local function Wallet() return ns.Wallet end
local function Sel(o) return type(o) == "number" and B36(o) or tostring(o) end

---------------------------------------------------------------------------
-- Duty and the index (Arena.Store(mode).bankEvents, role data kept in OlympusDB on the bank)
---------------------------------------------------------------------------

-- The King's live switch for a mode: a rehearsal (T) never waits for it.
function MarketBank.Live(mode)
	if mode ~= "L" then return true end
	local R = Roles()
	return R ~= nil and type(R.Live) == "function" and R.Live() == true
end

-- Is this client a bank taking bets in this mode, and why not: its name on T1~B (open), no
-- character of its account a leader, arbiter or keeper (ArenaRoles.MayBank), not a keeper's
-- client, and in gold only where saved data survives.
function MarketBank.Duty(mode, cur)
	local R = Roles()
	if not (R and R.IsBank and R.IsBank(ns.me, mode)) then return false, "bank" end
	if mode == "L" then
		-- (The King's live switch: off, no bet is taken, whatever a client that missed the word sends.)
		if not MarketBank.Live(mode) then return false, "live" end
		if R.BankState and R.BankState(ns.me) == "c" then return false, "closing" end
		if R.MayBank then
			local ok = R.MayBank()
			if not ok then return false, "account" end
		end
		if cur == "g" and not ns.Arena.Persists() then return false, "persists" end
	end
	local T = ns.Treasury
	if Fn(T, "IsKeeper") and T.IsKeeper() then return false, "keeper" end
	return true
end

-- The bank's events of a mode; made only when create is true (a bank taking a sheet or a slip):
-- every other client reads nothing and writes nothing (the weight rule).
local EMPTY = setmetatable({}, { __newindex = function() error("market bank: index written without create") end })
local function Index(mode, create)
	local store = Markets().StoreOf(mode, create)
	if type(store) ~= "table" then return create and nil or EMPTY end
	if type(store.bankEvents) ~= "table" then
		if not create then return EMPTY end
		store.bankEvents = {}
	end
	return store.bankEvents
end
MarketBank.Index = Index
local session = { epoch = nil } -- this session's book epoch (the bank's login second)
local function Epoch()
	if not session.epoch then session.epoch = Now() end
	return session.epoch
end
function MarketBank.Event(mode, eid)
	local idx = Index(mode)
	return idx and idx[eid] or nil
end
local function NewEvent(mode, eid)
	local list = Index(mode, true)
	local ev = { eid = eid, mode = mode, markets = {}, bySlip = {}, senders = {}, n = 0, created = Now(), flags = {} }
	list[eid] = ev
	return ev
end
local function MarketOf(ev, idx)
	local bm = ev.markets[idx]
	if not bm then
		bm = { idx = idx, state = "O", pools = {}, counts = {}, bets = {} }
		ev.markets[idx] = bm
	end
	return bm
end
-- Bets on a market (Markets.HasBets asks).
function MarketBank.Count(mode, eid, idx)
	local ev = MarketBank.Event(mode, eid)
	local bm = ev and ev.markets[idx]
	return bm and #bm.bets or 0
end

local Involve -- (below)
local function Rec(mode, eid) return Markets().Rec(mode, eid) end
local function Kind(typ) return Markets().KINDS[typ] end

local function MarketKey(eid, idx) return eid .. "." .. B36(idx) end
MarketBank.MarketKey = MarketKey

---------------------------------------------------------------------------
-- The book (BO) and its pump (the design)
---------------------------------------------------------------------------

-- A market's book row: its state (grace shows L), pools in silver and counts per outcome (a
-- scratched outcome's are 0: the pools shrink), and its result.
local function Row(ev, bm, m, sheet)
	local kind = Kind(m.type)
	local state = bm.state
	if state == "R" then state = "L" end
	if bm.hold and (state == "L" or state == "O") then state = "H" end
	local pools, counts = {}, {}
	if kind.pick then
		local total = 0
		for _, b in ipairs(bm.bets) do total = total + b.s end
		pools[1], counts[1] = B36(math.floor(total / 100)), B36(#bm.bets)
	else
		local scratched = Markets().ScratchedOf(sheet, m, Markets().Event(ev.eid))
		for o = 1, m.n do
			local key = Sel(o)
			local p = scratched[o] and 0 or (bm.pools[key] or 0)
			pools[o] = B36(math.floor(p / 100))
			counts[o] = B36(scratched[o] and 0 or (bm.counts[key] or 0))
		end
	end
	local part = ("%s:%s:%s:%s"):format(B36(m.idx), state, table.concat(pools, "."), table.concat(counts, "."))
	if state == "S" or state == "V" then part = part .. ":" .. tostring(bm.result) end
	return part
end
function MarketBank.BookBody(ev)
	local rec = Rec(ev.mode, ev.eid)
	local sheet = rec and rec.sheet
	if not sheet then return nil end
	local rows = {}
	for _, idx in ipairs(sheet.order) do
		local m = sheet.markets[idx]
		rows[#rows + 1] = Row(ev, MarketOf(ev, idx), m, sheet)
	end
	ev.n = (ev.n or 0) + 1
	-- The lag: the money part's Wallet.Lag (seconds), else its backlog (entries) at BANK_RATE a minute.
	local lag = tonumber((Call(Wallet(), "Lag", ev.mode)))
	if not lag then
		local backlog = Call(Wallet(), "Backlog", ev.mode) or 0
		lag = math.ceil((tonumber(backlog) or 0) * 60 / MarketBank.BANK_RATE)
	end
	lag = math.max(0, math.floor(lag))
	return table.concat({ ev.eid, B36(sheet.rev), B36(Epoch()) .. "." .. B36(ev.n), B36(Now()), B36(lag), table.concat(rows, ";") }, "~")
end

local lastAny = -math.huge
local function SendBook(ev, urgent)
	local rec = Rec(ev.mode, ev.eid)
	local sheet = rec and rec.sheet
	if not sheet then return false end
	-- A book the arena refuses now (the live switch off) stays due, urgent if it was: it goes as
	-- soon as it may, so no ticket waits for a book that was dropped.
	if ns.Arena.Refusal("BO", ev.mode, {}) then return false end
	local body = MarketBank.BookBody(ev)
	if not body then return false end
	local o = { key = "bo " .. ev.eid, urgent = urgent and true or nil, must = urgent and true or nil }
	local ok = false
	if Markets().SheetPrivate(sheet) then
		local to = {}
		for _, f in ipairs(Markets().Fighters(Markets().Event(ev.eid))) do to[#to + 1] = f.name end
		if sheet.from then to[#to + 1] = sheet.from end
		local seen = {}
		for _, name in ipairs(to) do
			if not Same(name, ns.me) and not seen[Lower(name)] then
				seen[Lower(name)] = true
				if ns.Arena.Send("BO", ev.mode, body, { key = o.key, urgent = o.urgent, must = o.must, to = name }) then ok = true end
			end
		end
	else
		ok = ns.Arena.Send("BO", ev.mode, body, o)
	end
	ev.sentAt, ev.dirty = Now(), false
	if urgent then ev.urgent = false else lastAny = Now() end
	-- The bank keeps its own book as every client does (its screen, and the tickets' view).
	local book = Markets().ReadBook(body)
	if book and rec then
		book.from, book.heard = ns.me, Now()
		rec.book = book
	end
	return ok
end
MarketBank.SendBook = SendBook
local function Dirty(ev, urgent)
	ev.dirty = true
	if urgent then ev.urgent = true end
end

-- Whether every market of the event is settled or void.
local function Over(ev, sheet)
	for idx in pairs(sheet.markets) do
		local bm = ev.markets[idx]
		if not bm or (bm.state ~= "S" and bm.state ~= "V") then return false end
	end
	return true
end

-- One ordinary book at a time across events (BO_ALL_GAP), each event at most every BO_GAP (5 s in
-- its last minute, BO_LONG_GAP when it locks days away); repeats for late logins; urgent ones at
-- once.
local function Pump(now)
	local all = {}
	for _, mode in ipairs({ "L", "T" }) do
		for _, ev in pairs(Index(mode) or {}) do
			if type(ev) == "table" then all[#all + 1] = ev end
		end
	end
	table.sort(all, function(a, b) return (a.sentAt or 0) < (b.sentAt or 0) end)
	for _, ev in ipairs(all) do
		local rec = Rec(ev.mode, ev.eid)
		local sheet = rec and rec.sheet
		if sheet and Same(sheet.bank, ns.me) then
			if ev.urgent then
				SendBook(ev, true)
			else
				local since = now - (ev.sentAt or -math.huge)
				local left = sheet.lockAt - now
				local gap = MarketBank.BO_GAP
				if left > 0 and left <= MarketBank.BO_LAST then gap = MarketBank.BO_GAP_LAST end
				if left > Markets().LONG_OPEN then gap = MarketBank.BO_LONG_GAP end
				local over = Over(ev, sheet)
				local rep = left > Markets().LONG_OPEN and MarketBank.BO_REPEAT_LONG or MarketBank.BO_REPEAT
				if over then
					ev.overAt = ev.overAt or now
					rep = (now - ev.overAt <= MarketBank.BO_AFTER_FOR) and MarketBank.BO_AFTER or nil
				end
				local due = (ev.dirty and since >= gap) or (rep and since >= rep)
				if due and now - lastAny >= MarketBank.BO_ALL_GAP then SendBook(ev, false) end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Voids, locks, settlement
---------------------------------------------------------------------------

local function Fire(eid) ns.Fire("MARKETS_SETTLED", eid) end

-- A Wallet call that moves money: true when it ran and did not say no (false, or nil and why);
-- else false and why ("missing": the money part's function is not there).
local function Pay(name, ...)
	local f = Fn(Wallet(), name)
	if not f then return false, "missing" end
	local ok, res, why = pcall(f, ...)
	if not ok then
		ns.Log("market bank: Wallet.%s failed: %s", name, tostring(res))
		return false, "error"
	end
	if res == false or (res == nil and why ~= nil) then return false, why end
	return true, res
end

-- The wallet did not do it: never shown settled or void. The market holds ("wallet") for a
-- leader's P (which tries again); after HOLD_MAX it voids, unless the ledger did it already.
local function WalletHold(ev, bm, what, why)
	ns.Log("market bank: %s.%s not %s: %s", ev.eid, tostring(bm.idx), what, tostring(why))
	bm.hold = bm.hold or { at = Now() }
	if not bm.hold.wallet then
		bm.hold.wallet = true
		Dirty(ev, true)
	end
	return false
end

local function Pool(bm)
	local total = 0
	for _, p in pairs(bm.pools) do total = total + p end
	return total
end

-- A market done: its state and result on the bank, its book urgently, the screens told.
local function Done(ev, bm, state, result)
	bm.state, bm.result, bm.settledAt, bm.hold = state, result, Now(), nil
	Dirty(ev, true)
	Fire(ev.eid)
end

-- The ledger's word on a market (the money part's Wallet.Market): its x written already, and its result.
local function LedgerDone(ev, idx)
	local info = Call(Wallet(), "Market", ev.eid, idx)
	if type(info) == "table" and info.settled then return true, info.result end
	return false, info ~= nil
end

local Unclaim -- (the Lottery's, below)
local function VoidMarket(ev, idx, code)
	local bm = MarketOf(ev, idx)
	if bm.state == "S" or bm.state == "V" then return false end
	local done, result = LedgerDone(ev, idx)
	if done then
		-- The ledger settled it already (a settlement that failed only on its way back): what the
		-- ledger did stands, never a refund on top of the credits it paid.
		result = tostring(result)
		if result == "V" or result:sub(1, 1) == "V" then Done(ev, bm, "V", code) return true end
		if result:sub(1, 1) == "C" then result = "R." .. B36(Pool(bm) + (bm.carryIn or 0)) end
		Done(ev, bm, "S", result)
		return false
	end
	local known = result
	local paid, why = Pay("Void", ev.eid, idx, code, ev.mode)
	-- (A market the ledger never registered, with no bet, has nothing to give back.)
	if not paid and (known or #bm.bets > 0) then return WalletHold(ev, bm, "voided", why) end
	Done(ev, bm, "V", code)
	-- A Lottery day whose pot a later day claimed: that day cannot have what it was promised.
	if bm.carryTo then Unclaim(ev, bm) end
	return true
end
MarketBank.VoidMarket = VoidMarket
function MarketBank.VoidEvent(ev, code)
	local rec = Rec(ev.mode, ev.eid)
	local n = 0
	for idx in pairs(rec and rec.sheet and rec.sheet.markets or ev.markets) do
		if VoidMarket(ev, idx, code) then n = n + 1 end
	end
	return n
end

-- Terms changed under bets (a rev refused by rule 9): the event voids, T.
function MarketBank.TermsChanged(mode, eid)
	local ev = MarketBank.Event(mode, eid)
	if not ev then return end
	local rec = Rec(mode, eid)
	if not (rec and rec.sheet and Same(rec.sheet.bank, ns.me)) then return end
	MarketBank.VoidEvent(ev, "T")
	Involve()
end

-- The scratched outcomes' texts (for Wallet.Settle), a set's keys.
local function ScratchList(sheet, m)
	local out = {}
	local set = Markets().ScratchedOf(sheet, m, Markets().Event(sheet.eid))
	for o in pairs(set) do out[#out + 1] = Sel(o) end
	table.sort(out)
	return out
end

local function Lock(ev, idx, sheet)
	local bm = MarketOf(ev, idx)
	if bm.state ~= "O" then return end
	local m = sheet.markets[idx]
	local kind = Kind(m.type)
	local scratched = Markets().ScratchedOf(sheet, m, Markets().Event(ev.eid))
	if Markets().WholeScratch(sheet, m) then return VoidMarket(ev, idx, "I") end
	if kind.stake then
		-- Both stakes held before the lock, or the stake market voids (S) and the one held goes back.
		if (bm.pools["1"] or 0) == 0 or (bm.pools["2"] or 0) == 0 then return VoidMarket(ev, idx, "S") end
	elseif kind.pick then
		if #bm.bets < 2 then return VoidMarket(ev, idx, "1") end
	elseif not kind.lottery then
		local sides = 0
		for key, p in pairs(bm.pools) do
			local o = N36(key, 1, m.n)
			if p > 0 and not (o and scratched[o]) then sides = sides + 1 end
		end
		if sides < 2 then return VoidMarket(ev, idx, "1") end
	end
	Call(Wallet(), "Close", ev.eid, idx, ev.mode)
	bm.state, bm.lockedAt = "L", Now()
	bm.lockPools = {}
	for k, v in pairs(bm.pools) do bm.lockPools[k] = v end
	MarketBank.LateFlags(ev, bm, m, sheet)
	Dirty(ev, true)
end

-- The result the bank pays: the declared one, or (a hold from the game resolved after HOLD_MAX)
-- the game's duel line's. winners in the ledger's form.
local function WinnersOf(m, result)
	local res = Markets().ReadResult(m, result)
	return res and Markets().Winners(m, res) or nil, res
end

local gates = {}
-- A settlement gate for an event letter (the Bones tables' "K": the arbiter's KE must agree with a player's).
function MarketBank.SetGate(letter, fn)
	if type(letter) ~= "string" or #letter ~= 1 then return false end
	gates[letter] = type(fn) == "function" and fn or nil
	return true
end

---------------------------------------------------------------------------
-- The Lottery's carry (the design): after settlement, each unclaimed profit tranche stays in
-- this ledger for the next day that names the exact retained copper (Wallet.Carry), once.
-- On the source day's market: carryTo = { eid, idx, copper } (the day that takes it), awaitFrom
-- (since when it waits for one), rolled (the copper that went). On the day that names it:
-- carryFrom, carryIn (the copper it was promised), carried (the pot came).
---------------------------------------------------------------------------

local function LotteryIdx(sheet)
	for _, idx in ipairs(type(sheet) == "table" and sheet.order or {}) do
		if Kind(sheet.markets[idx].type).lottery then return idx end
	end
	return nil
end
-- The pot a market holds from earlier days, by the wallet's own ledger.
local function Pot(eid, idx) return tonumber((Call(Wallet(), "Pot", eid, idx))) or 0 end

local function LotteryCarry(sheet, m, bm)
	if not (sheet and m and bm and m.state == "R") then return nil, "result" end
	return Markets().LotterySettlement(m, bm.pools, true, 600)
end

-- Why a day may not take the pot of `from` it names (nil: it may; the pot is claimed for it).
local function ClaimCarry(ev, sheet, m, from, copper)
	local src = MarketBank.Event(ev.mode, from)
	local srec = Rec(ev.mode, from)
	local ssheet = srec and srec.sheet
	if not src or not ssheet or not Same(ssheet.bank, ns.me) or from == ev.eid then return "source" end
	if ssheet.cur ~= sheet.cur then return "cur" end
	local sidx = LotteryIdx(ssheet)
	local sbm = sidx and src.markets[sidx]
	if not sbm then return "source" end
	local to = sbm.carryTo
	if to and not (to.eid == ev.eid and to.idx == m.idx) then return "taken" end
	local expected
	if sbm.state == "V" then
		-- A void day keeps the pot it carried in (its own stakes went back).
		expected = Pot(from, sidx)
	elseif sbm.state == "R" then
		local sm = ssheet.markets[sidx]
		local calc = LotteryCarry(ssheet, sm, sbm)
		if not calc then return "result" end
		expected = calc.nextCarry
	elseif sbm.state == "S" then
		local Lo = ns.Lottery
		local settled = Lo and Lo.DecodeResult and Lo.DecodeResult(sbm.result)
		if not settled then return "version" end
		expected = settled.nextCarry
	elseif sbm.state == "O" or sbm.state == "L" then
		return "wait"
	else
		return "state"
	end
	if expected ~= copper then return "copper" end
	sbm.carryTo = { eid = ev.eid, idx = m.idx, copper = copper }
	return nil
end

-- The day that claimed a pot cannot have it (its source was paid, or voided with other money):
-- that day voids (C), and the pot may be named again.
Unclaim = function(ev, bm)
	local to = bm.carryTo
	if not to then return end
	bm.carryTo = nil
	local dev = MarketBank.Event(ev.mode, to.eid)
	local dbm = dev and dev.markets[to.idx]
	if dbm and not dbm.carried and dbm.state ~= "S" and dbm.state ~= "V" then VoidMarket(dev, to.idx, "C") end
end

-- A settled day (or a void day) gives a later day only the pot still retained in its ledger.
-- For v2 settlement that is exactly the sum of unclaimed profit tranches.
local function MoveRetained(ev, idx, bm)
	local to = bm.carryTo
	if (bm.state ~= "S" and bm.state ~= "V") or not to or bm.potGone then return false end
	local dev = MarketBank.Event(ev.mode, to.eid)
	local dbm = dev and dev.markets[to.idx]
	if not dbm or dbm.carried or dbm.state == "S" or dbm.state == "V" then return false end
	local paid, moved = Pay("Carry", ev.eid, idx, to.eid, to.idx)
	if not paid then return false end
	bm.potGone, dbm.carried = true, true
	if (tonumber(moved) or to.copper) ~= to.copper then VoidMarket(dev, to.idx, "C") end
	Dirty(dev, false)
	return true
end

-- The day's LO market names a pot: claimed from its source day, or the day voids (C). A source
-- not yet declared is waited for SHEET_WAIT (the caller sends the declaration first).
local function TakeCarry(ev, sheet, m)
	local bm = MarketOf(ev, m.idx)
	if bm.carryChecked or bm.state == "S" or bm.state == "V" then return end
	local copper, from = Markets().CarryIn(m)
	if copper <= 0 then bm.carryChecked = true return end
	local why = ClaimCarry(ev, sheet, m, from, copper)
	if why == "wait" and Now() - (bm.carrySeen or Now()) < Markets().SHEET_WAIT then
		bm.carrySeen = bm.carrySeen or Now()
		return
	end
	bm.carryChecked = true
	if why then
		ns.Log("market bank: %s carries in %s from %s, refused: %s", ev.eid, tostring(copper), tostring(from), why)
		return VoidMarket(ev, m.idx, "C")
	end
	bm.carryFrom, bm.carryIn = from, copper
	local src = MarketBank.Event(ev.mode, from)
	local sidx = LotteryIdx(Rec(ev.mode, from).sheet)
	if src.markets[sidx].state == "V" or src.markets[sidx].state == "S" then MoveRetained(src, sidx, src.markets[sidx]) end
end
MarketBank.TakeCarry = TakeCarry

-- The pot a day was promised has not come: it waits for its source day (in its grace, or held),
-- and voids (C) when the source can no longer give it or after CARRY_WAIT.
local function PotDue(ev, idx, bm)
	if not bm.carryFrom or bm.carried then return false end
	local src = MarketBank.Event(ev.mode, bm.carryFrom)
	local srec = Rec(ev.mode, bm.carryFrom)
	local sidx = srec and LotteryIdx(srec.sheet)
	local sbm = src and sidx and src.markets[sidx]
	if sbm and (sbm.state == "V" or sbm.state == "S") then MoveRetained(src, sidx, sbm) end
	if bm.carried then return false end
	local claimed = sbm and sbm.carryTo and sbm.carryTo.eid == ev.eid
	bm.potWait = bm.potWait or Now()
	if not claimed or Now() - bm.potWait >= Markets().CARRY_WAIT then
		VoidMarket(ev, idx, "C")
		return true
	end
	return true
end

local function Settle(ev, idx, sheet, result)
	local bm = MarketOf(ev, idx)
	if bm.state == "S" or bm.state == "V" then return false end
	local m = sheet.markets[idx]
	-- (The compliance gate, Compliance.lua: no payout while it says no; a void and its refunds still go.)
	local C = ns.Compliance
	if not (type(C) == "table" and type(C.Allows) == "function" and C.Allows("payout") == true) then return false end
	local kind = Kind(m.type)
	local winners, res = WinnersOf(m, result)
	if not winners then return VoidMarket(ev, idx, "N") end
	local paid, why, final, lotteryCarry
	if kind.lottery then
		-- The pot this day was promised has not come yet (its source day is still in its grace):
		-- it waits, so every winner is paid the pot the sheet showed.
		if PotDue(ev, idx, bm) then return false end
		-- All five places settle in the versioned wallet contract. It returns a signed wire with the
		-- exact retained carry, rather than the old head-only winner or whole-pot rollover word.
		paid, why = Pay("SettleLottery", ev.eid, idx, res.animals)
		if paid and type(why) == "table" then
			final, lotteryCarry = why.wire, why.nextCarry
			if type(final) ~= "string" or type(lotteryCarry) ~= "number" then paid, why = false, "result" end
		end
	elseif kind.pick then
		-- The bracket pool from the ledger's entries: the top score and how many share it go in the
		-- book, so every entrant's client computes his own payout.
		local M = ns.ArenaMath
		local entries = {}
		for _, b in ipairs(bm.bets) do entries[#entries + 1] = { o = b.o, s = b.s } end
		local rounds = 0
		while 2 ^ rounds < (sheet.size or m.n) do rounds = rounds + 1 end
		local r = #entries > 0 and M.Pickem(entries, res.pick, rounds, Markets().FeeArg(sheet)) or nil
		paid, why = Pay("Settle", ev.eid, idx, winners, nil)
		local nwin = r and (r.refund and #entries or #r.winners) or 0
		final = ("%s.%s.%s"):format(winners, B36(r and r.top or 0), B36(nwin))
	else
		-- A scratched outcome never wins (its stakes go back).
		local scratched = Markets().ScratchedOf(sheet, m, Markets().Event(ev.eid))
		local live = {}
		for _, sel in ipairs(winners) do
			local o = N36(sel, 1, m.n)
			if not (o and scratched[o]) then live[#live + 1] = sel end
		end
		if #live == 0 then return VoidMarket(ev, idx, "N") end
		winners = live
		paid, why = Pay("Settle", ev.eid, idx, winners, ScratchList(sheet, m))
		final = table.concat(winners, "+")
	end
	-- The wallet did not pay: never shown as settled (WalletHold).
	if not paid then return WalletHold(ev, bm, "settled", why) end
	MarketBank.RepeatFlags(ev, bm, m)
	Done(ev, bm, "S", final)
	if kind.lottery then
		if bm.carryTo and bm.carryTo.copper ~= lotteryCarry then
			Unclaim(ev, bm)
		elseif bm.carryTo and lotteryCarry > 0 then
			MoveRetained(ev, idx, bm)
		end
	end
	return true
end
MarketBank.Settle = Settle

---------------------------------------------------------------------------
-- Holds and overrules (the design)
---------------------------------------------------------------------------

-- Is a word refused on the bank: from the event's officials, its fighters or entrants, the bank,
-- or anyone holding a bet on the event; each of them with his alts (SameOwner) and his key.
local function Interested(ev, sheet, name)
	local M = Markets()
	local rec = Rec(ev.mode, ev.eid)
	local why = rec and M.Interested(rec, name)
	if why then return why end
	local D = ns.Debts
	local _, fp = Call(D, "Verified", name)
	local function Is(other, ofp)
		if type(other) ~= "string" then return false end
		if Same(other, name) or Call(D, "SameOwner", other, name) == true then return true end
		return fp ~= nil and ofp ~= nil and ofp == fp
	end
	for _, bm in pairs(ev.markets) do
		for _, b in ipairs(bm.bets) do
			if Is(b.who, b.fp) then return "ticket" end
		end
	end
	local e = M.Event(ev.eid)
	for _, f in ipairs(M.Fighters(e)) do
		if Is(f.name, f.fp) then return "fighter" end
	end
	for _, en in pairs(type(e) == "table" and type(e.entrants) == "table" and e.entrants or {}) do
		if type(en) == "table" and Is(en.name, en.fp) then return "fighter" end
	end
	for _, o in ipairs(M.Officials(e, sheet)) do
		local _, ofp = Call(D, "Verified", o)
		if Is(o, ofp) then return "official" end
	end
	-- The bank's own characters and key (Debts.MyKey: this client's key).
	local _, _, myFp = Call(D, "MyKey")
	if Is(ns.me, myFp) then return "bank" end
	return nil
end
MarketBank.Interested = Interested

-- The words that count on the bank for a market.
local function Words(ev, rec, idx)
	local out = {}
	for _, w in ipairs(Markets().WordsFor(rec, idx)) do
		if not Interested(ev, rec.sheet, w.by) then out[#out + 1] = w end
	end
	return out
end

-- A market's hold has sources: "duel" (declared against the game's duel line, or the witnesses
-- disagree), "word" (a leader's BV H, or an unconfirmed weight-1 V or P), "gate" (the Bones tables': the
-- arbiter's KE agrees with no player's). It holds while any source does; HOLD_MAX runs from the
-- first.
local function Hold(ev, bm, source)
	if bm.state == "S" or bm.state == "V" then return end
	if bm.hold and bm.hold[source] then return end
	bm.hold = bm.hold or { at = Now() }
	bm.hold[source] = true
	Dirty(ev, true)
end
MarketBank.Hold = Hold
local function Release(ev, bm, source)
	if not bm.hold then return end
	if source == "all" then
		bm.hold = nil
	else
		bm.hold[source] = nil
		if not (bm.hold.duel or bm.hold.word or bm.hold.gate or bm.hold.wallet) then bm.hold = nil end
	end
	if not bm.hold then Dirty(ev, true) end
end

-- The effect of the words on a market: a V (the King's or a Steward's, or two independent
-- weight-1 words) voids it (L); an H holds it; a P (confirmed) releases every hold, and it pays
-- by the declared result after its grace.
local function Rule(ev, rec, idx)
	local bm = MarketOf(ev, idx)
	if bm.state == "S" or bm.state == "V" then return end
	local code = Markets().Effective(Words(ev, rec, idx))
	if code == "V" then return VoidMarket(ev, idx, "L") end
	if code == "H" then return Hold(ev, bm, "word") end
	if code == "P" then return Release(ev, bm, "all") end
	Release(ev, bm, "word")
end

function MarketBank.OnWord(mode, rec, w)
	local ev = MarketBank.Event(mode, rec.eid)
	if not ev or not rec.sheet or not Same(rec.sheet.bank, ns.me) then return end
	for idx in pairs(rec.sheet.markets) do
		if w.idx == "*" or w.idx == idx then Rule(ev, rec, idx) end
	end
	Involve()
end

---------------------------------------------------------------------------
-- The sheet on the bank
---------------------------------------------------------------------------

local function RegisterMarket(ev, sheet, m)
	local bm = MarketOf(ev, m.idx)
	if bm.registered then return end
	local kind = Kind(m.type)
	bm.registered = true
	local parties
	if kind.stake then
		parties = {}
		for _, f in ipairs(Markets().Fighters(Markets().Event(ev.eid))) do parties[#parties + 1] = f.name end
	end
	local rounds
	if kind.pick then
		rounds = 0
		while 2 ^ rounds < (sheet.size or m.n) do rounds = rounds + 1 end
	end
	-- (The Lottery pays no arbiter: all of its fee is the guild's, whatever a sheet said.)
	Call(Wallet(), "Register", ev.eid, m.idx, { market = MarketKey(ev.eid, m.idx), type = m.type, param = m.param, n = m.n, nsel = m.n, places = kind.k or 1,
		parties = parties, rounds = rounds,
		closes = sheet.lockAt, feeBp = sheet.fee.g + sheet.fee.a, arbBp = sheet.fee.a, to = kind.lottery and "g" or sheet.fee.to,
		kind = kind.lottery and "l" or (kind.stake and "s" or "p"),
		cur = sheet.cur, arbiter = sheet.from, mode = ev.mode })
end

-- A sheet naming this bank was taken (Markets.lua checked it whole): the markets registered, a
-- declaration's grace and holds, the voids, the scratches.
function MarketBank.OnSheet(mode, rec, was)
	local sheet = rec.sheet
	if not sheet or not Same(sheet.bank, ns.me) then return end
	local ev = MarketBank.Event(mode, rec.eid) or NewEvent(mode, rec.eid)
	local now = Now()
	local e = Markets().Event(rec.eid)
	-- A declaration against the game's duel line (or witnesses disagreeing) holds the whole event.
	local against = type(e) == "table" and e.disagree == true
	for _, m in pairs(sheet.markets) do
		if m.state == "R" then
			local res = Markets().ReadResult(m, m.result)
			if res and res.against then against = true end
		end
	end
	for _, idx in ipairs(sheet.order) do
		local m = sheet.markets[idx]
		RegisterMarket(ev, sheet, m)
		local bm = MarketOf(ev, idx)
		-- (A Lottery day that names a pot: claimed from this ledger's own day, or it voids, C.)
		if Kind(m.type).lottery then TakeCarry(ev, sheet, m) end
		if m.state == "V" then
			VoidMarket(ev, idx, m.result)
		elseif m.state == "R" and bm.state ~= "S" and bm.state ~= "V" then
			if bm.state == "O" and now < sheet.lockAt then
				-- A result while the market is still open: the whole event voids (E).
				MarketBank.VoidEvent(ev, "E")
				break
			end
			if bm.state == "O" then Lock(ev, idx, sheet) end
			if bm.state ~= "V" and (bm.declared ~= m.result or bm.declaredT ~= m.t) then
				bm.declared, bm.declaredT = m.result, m.t
				-- The grace runs from the declaration, by this clock (never earlier than its arrival).
				bm.graceFrom = math.max(tonumber(m.t) or now, now)
				if against then
					Hold(ev, bm, "duel")
				else
					-- A corrected result that agrees with the game releases the game's hold.
					Release(ev, bm, "duel")
				end
				if bm.state == "L" then bm.state = "R" end
				Rule(ev, rec, idx)
				Dirty(ev, true)
			end
		end
		if Markets().WholeScratch(sheet, m) and bm.state == "O" then VoidMarket(ev, idx, "I") end
	end
	-- The scratches: those outcomes' holds go back now where the Wallet can (else at settlement).
	for entrant in pairs(sheet.scratched or {}) do
		if not (ev.scratched or {})[entrant] then
			ev.scratched = ev.scratched or {}
			ev.scratched[entrant] = true
			Call(Wallet(), "Scratch", ev.eid, entrant, ev.mode)
		end
	end
	if not was or was.rev ~= sheet.rev then Dirty(ev, false) end
	Involve()
end

---------------------------------------------------------------------------
-- The slip (BS): the design
---------------------------------------------------------------------------

local minute = {} -- this bank's acceptances in the last minute (times)
local function Busy(now)
	while minute[1] and now - minute[1] >= 60 do table.remove(minute, 1) end
	return #minute >= MarketBank.BANK_RATE
end

-- The bank's whispered answer. An acceptance (a stake market's K) goes urgently; a refusal, or a
-- K for a nonce taken already, on the ordinary lane, at most one per sender every ANSWER_GAP (the
-- rest dropped: the bettor's client sends again after ACK_WAIT), so a flood of slips never fills
-- the urgent share the ledger's entries and the locked books need.
local answered = {} -- [sender lower] = when the last refusal went (memory)
local function Answer(to, mode, eid, nonce, code, urgent)
	if not urgent then
		local key, now = Lower(to), Now()
		if now - (answered[key] or -math.huge) < MarketBank.ANSWER_GAP then return false end
		answered[key] = now
		-- (Pruned as it grows: only the last ANSWER_GAP matters.)
		local n = 0
		for _ in pairs(answered) do n = n + 1 end
		if n > 400 then
			for k, t in pairs(answered) do if now - t >= MarketBank.ANSWER_GAP then answered[k] = nil end end
		end
	end
	return ns.Arena.Send("BK", mode, ("%s~%s~%s"):format(eid, nonce, code), { to = to, urgent = urgent and true or nil })
end
MarketBank.Answer = Answer

local function Median(list)
	if #list == 0 then return 0 end
	local c = {}
	for i, v in ipairs(list) do c[i] = v end
	table.sort(c)
	local n = #c
	if n % 2 == 1 then return c[(n + 1) / 2] end
	return math.floor((c[n / 2] + c[n / 2 + 1]) / 2)
end

-- The conflict rules (A): true when the sender may not make this bet.
local function Conflict(ev, sheet, m, o, sender, facts, fp)
	local M = Markets()
	local e = M.Event(ev.eid)
	local kind = Kind(m.type)
	local D = ns.Debts
	local function Is(name, pfp)
		if Same(name, sender) then return true end
		if Call(D, "SameOwner", name, sender) == true then return true end
		if fp and pfp and fp == pfp then return true end
		return false
	end
	-- The officials and the bank: nothing on the event.
	for _, name in ipairs(M.Officials(e, sheet)) do
		local _, ofp = Call(D, "Verified", name)
		if Is(name, ofp) then return true end
	end
	if Is(ns.me, nil) then return true end
	-- A fighter (or his alt, or his key): only MW and SW on himself; his own stake.
	for _, f in ipairs(M.Fighters(e)) do
		if Is(f.name, f.fp) then
			local own = f.side == "A" and 1 or 2
			if kind.stake then return not Same(f.name, sender) or o ~= own end
			if kind.self == "side" and o == own then return false end
			return true
		end
	end
	if kind.stake then return true end -- only the named parties
	-- An entrant: CH and CC on himself, the champion outcome of his own stage market.
	for i, en in pairs(type(e) == "table" and type(e.entrants) == "table" and e.entrants or {}) do
		if type(en) == "table" and Is(en.name, en.fp) then
			if kind.self == "entrant" and o == i then return false end
			if kind.self == "stage" and m.value == i and o == 1 then return false end
			return true
		end
	end
	-- KO and B3: never a fighter's guildmate (the design).
	if Markets().CAPPED[m.type] and type(facts) == "table" and type(facts.guild) == "string" then
		for _, f in ipairs(M.Fighters(e)) do
			if type(f.guild) == "string" and f.guild:lower() == facts.guild:lower() then return true end
		end
	end
	return false
end
MarketBank.Conflict = Conflict

-- Checks a slip; returns nil (accept: acct, facts, fp) or the code.
function MarketBank.Check(mode, sender, eid, idx, o, silver, nonce)
	local M = Markets()
	local rec = Rec(mode, eid)
	local sheet = rec and rec.sheet
	-- U: my market?
	if not sheet or not Same(sheet.bank, ns.me) then return "U" end
	local m = sheet.markets[idx]
	if not m then return "U" end
	local kind = Kind(m.type)
	if kind.direct then return "U" end
	-- (The compliance gate: a slip only on a market it allows here.)
	local wagers = Fn(M, "Wagers")
	if not (wagers and wagers({ m }, (ns.Arena.EventOf(eid) or {}).kind)) then return "U" end
	local duty = MarketBank.Duty(mode, sheet.cur)
	if not duty then return "U" end
	local ev = MarketBank.Event(mode, eid) or NewEvent(mode, eid)
	-- The nonce: the same tuple again is answered K (never held twice); another tuple, on this
	-- event or any other of this bank's, is U (the design).
	local key = Lower(sender) .. "#" .. nonce
	local seen = ev.bySlip[key]
	if seen then
		if seen.idx == idx and seen.o == Sel(o) and seen.s == silver * 100 then return "K" end
		return "U"
	end
	for _, other in pairs(Index(mode)) do
		if type(other) == "table" and other ~= ev and type(other.bySlip) == "table" and other.bySlip[key] then return "U" end
	end
	-- R: the sender's rate, before any other check (a flood of slips the bank would refuse anyway
	-- is refused here, cheaply): every slip from here counts for the 2 s, taken or refused; only
	-- the taken ones for the 20.
	local now = Now()
	local s = ev.senders[Lower(sender)] or { n = 0, at = -math.huge }
	if now - s.at < MarketBank.RATE_GAP or s.n >= MarketBank.RATE_EVENT then return "R" end
	s.at = now
	ev.senders[Lower(sender)] = s
	-- E: no verified key, no bet (the bettor's client sends its ZT).
	local D = ns.Debts
	local gk, fp = Call(D, "Verified", sender)
	if not gk then return "E" end
	-- r: busy (the ledger's publishing rate), or in lockdown.
	if ns.Arena.Blocked() then return "r" .. B36(MarketBank.LOCKDOWN_WAIT) end
	if Busy(now) then return "r" .. B36(MarketBank.BUSY_WAIT) end
	-- C: open, by this clock.
	local bm = MarketOf(ev, idx)
	if bm.state ~= "O" or m.state ~= "O" or now >= sheet.lockAt then return "C" end
	-- O: the outcome.
	local ov = M.SlipOutcome(m, o, sheet)
	if not ov then return "O" end
	if type(ov) == "number" and (M.ScratchedOf(sheet, m, M.Event(eid))[ov] or M.WholeScratch(sheet, m)) then return "O" end
	-- M: the stake.
	local copper = silver * 100
	local settings = M.Settings()
	local minBet = tonumber(settings.minBet) or 1000
	if kind.pick then
		if silver ~= m.value then return "M" end
	elseif kind.stake then
		local side = type(ov) == "number" and ov or 0
		if silver ~= (m.value[side] or -1) then return "M" end
	elseif copper < minBet or copper > 2147483647 then
		return "M"
	end
	-- W: an account.
	local W = Wallet()
	local acct = Call(W, "Account", sender)
	if acct == nil then return "W" end
	-- E: eligible (an Olympus guild and minLevel at deposit, not frozen, its GUID bound).
	local facts = Call(W, "Facts", acct)
	if type(facts) ~= "table" then return "E" end
	if facts.frozen or facts.bound == false then return "E" end
	if type(facts.guild) ~= "string" or not (ns.IsFederation and ns.IsFederation(facts.guild)) then return "E" end
	if (tonumber(facts.level) or 0) < (tonumber(settings.minLevel) or 10) then return "E" end
	-- N: net-off.
	local Mo = ns.Moderation
	if Mo and not Mo.missing and (Call(Mo, "Hidden", sender) or Call(Mo, "Hides", sender, facts.guild)) then return "N" end
	-- (1.1.6: a moderator's timeout or hold, as this bank's client knows it, WatchChat.Barred "games":
	-- he bets on nothing while it lasts, whichever client or queue his slip came from.)
	local A = ns.Arena
	if A and A.Sanctioned and A.Sanctioned(sender) then return "N" end
	-- D: an open debt.
	if Call(D, "Blocked", sender, gk, fp, mode) then return "D" end
	-- A: the anti-fix rules.
	if Conflict(ev, sheet, m, ov, sender, facts, fp) then return "A" end
	-- X: the caps (one bracket entry, one stake a party).
	local staked, today = 0, 0
	local day = math.floor(now / 86400)
	for _, b in ipairs(bm.bets) do if Same(b.who, sender) then staked = staked + b.s end end
	if (kind.pick or kind.stake) and staked > 0 then return "X" end
	for _, other in pairs(Index(mode)) do
		local dd = type(other) == "table" and other.day and other.day[Lower(sender)]
		if dd and dd.day == day then today = today + dd.copper end
	end
	local pool = 0
	for _, b in ipairs(bm.bets) do pool = pool + b.s end
	if not kind.stake and not kind.pick then
		local cap = M.BetCapOf(m, settings)
		local own = Call(ns.Standing, "Cap", "bet", sender, mode)
		if type(own) == "number" and own < cap then cap = own end
		local okCap, why = ns.ArenaMath.BetOk(copper, cap, staked, { minBet = math.max(100, math.min(100000, minBet)),
			maxDay = tonumber(settings.maxDay) or 600000, today = today, maxPool = M.PoolCap(m, settings), pool = pool })
		if not okCap then
			if why == "pool" then return "P" end
			if why == "min" or why == "silver" or why == "copper" then return "M" end
			return "X"
		end
	end
	-- P: the room.
	local bets = 0
	for _, x in pairs(ev.markets) do bets = bets + #x.bets end
	if bets >= MarketBank.MAX_BETS_EVENT then return "P" end
	-- F: the funds.
	local avail = Call(W, "Available", acct, sheet.cur)
	if type(avail) ~= "number" or avail < copper then return "F" end
	return nil, acct, facts, fp, gk, ov
end

-- Wallet.Hold's reasons as the slip's codes (anything else: F).
local HOLD_CODES = { U = "U", closed = "C", late = "C", closing = "U", duty = "U", market = "U", silver = "M", shape = "O",
	frozen = "E", bound = "E", account = "W", funds = "F", cap = "P" }

-- Accepted: the hold (the ledger's b), the index, the flags.
local function Take(ev, sheet, m, sender, acct, facts, fp, gk, ov, silver, nonce)
	local copper = silver * 100
	local now = Now()
	local sel = Sel(ov)
	local seq, why = Call(Wallet(), "Hold", acct, copper, { eid = ev.eid, idx = m.idx, market = MarketKey(ev.eid, m.idx), o = sel, nonce = nonce,
		t = now, cur = sheet.cur, mode = ev.mode, stake = Kind(m.type).stake or nil })
	-- The wallet's own refusals (the money part's Hold): its reason as the slip's code.
	if not seq then return HOLD_CODES[why] or "F" end
	local bm = MarketOf(ev, m.idx)
	local before = {}
	for k, v in pairs(bm.pools) do before[k] = v end
	local stakes = {}
	for _, b in ipairs(bm.bets) do stakes[#stakes + 1] = b.s end
	local bet = { who = ns.FullName(sender), acct = acct, o = sel, s = copper, nonce = nonce, t = now, seq = seq, guild = facts.guild, fp = fp, gk = gk }
	bm.bets[#bm.bets + 1] = bet
	bm.pools[sel] = (bm.pools[sel] or 0) + copper
	bm.counts[sel] = (bm.counts[sel] or 0) + 1
	ev.bySlip[Lower(sender) .. "#" .. nonce] = { idx = m.idx, o = sel, s = copper, i = #bm.bets }
	local s = ev.senders[Lower(sender)] or { n = 0, at = -math.huge }
	s.n, s.at = s.n + 1, now
	ev.senders[Lower(sender)] = s
	ev.day = ev.day or {}
	local day = math.floor(now / 86400)
	local d = ev.day[Lower(sender)]
	if not d or d.day ~= day then d = { day = day, copper = 0 } ev.day[Lower(sender)] = d end
	d.copper = d.copper + copper
	minute[#minute + 1] = now
	MarketBank.BetFlags(ev, sheet, m, bm, bet, before, stakes)
	Dirty(ev, false)
	return nil
end

function MarketBank.HandleSlip(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local eid, idx, o, silver, nonce = ns.Arena.Fields(body, 5)
	if not nonce or not Markets().EidOk(eid) or not nonce:find("^[0-9a-z]+$") or #nonce ~= 6 then return end
	idx = N36(idx, 1, Markets().MAX_MARKETS)
	silver = N36(silver, 1, math.floor(2147483647 / 100))
	if not idx or not silver or type(o) ~= "string" or o == "" or #o > 20 then return end
	local rec = Rec(mode, eid)
	-- Not a sheet of ours: nothing is said (another bank's, or a stranger's guess).
	if not (rec and rec.sheet and Same(rec.sheet.bank, ns.me)) then return end
	local code, acct, facts, fp, gk, ov = MarketBank.Check(mode, sender, eid, idx, o, silver, nonce)
	local ev = MarketBank.Event(mode, eid) or NewEvent(mode, eid)
	if code == nil then
		code = Take(ev, rec.sheet, rec.sheet.markets[idx], sender, acct, facts, fp, gk, ov, silver, nonce)
		-- A stake market's acceptance is whispered (its entry goes on the channel as a digest).
		if code == nil and Kind(rec.sheet.markets[idx].type).stake then Answer(sender, mode, eid, nonce, "K", true) end
		if code == nil then Involve() return end
	end
	if code == "K" then
		-- A slip sent again (no entry heard yet): K once every K_GAP for that nonce.
		local seen = ev.bySlip[Lower(sender) .. "#" .. nonce]
		local now = Now()
		if seen and now - (seen.kAt or -math.huge) < MarketBank.K_GAP then return end
		if Answer(sender, mode, eid, nonce, "K") and seen then seen.kAt = now end
		return
	end
	-- A late slip hears nothing (the lock shows in the book); every other refusal is whispered.
	if code ~= "C" then Answer(sender, mode, eid, nonce, code) end
	ev.refused = (ev.refused or 0) + 1
end

---------------------------------------------------------------------------
-- Flags (the design): whispered to auditors on the low lane, never to the event's officials
---------------------------------------------------------------------------

-- The auditors to tell (the design): the King's character, the High Councillors, the signed
-- auditors (in T the King's stand-ins); the money part may set MarketBank.Auditors to the ones it heard.
function MarketBank.DefaultAuditors(mode)
	local out, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		local full = ns.FullName(name)
		if seen[full:lower()] or Same(full, ns.me) then return end
		seen[full:lower()] = true
		out[#out + 1] = full
	end
	local R = Roles()
	local king = ns.KingCharacter and ns.KingCharacter()
	if king then Add(ns.FullName(king, (ns.KingRealm and ns.KingRealm()) or ns.realm)) end
	local c = ns.rdb and ns.rdb.council
	for short in pairs(type(c) == "table" and type(c.names) == "table" and c.names or {}) do
		Add(R and R.ProperName and R.ProperName(short .. "-" .. tostring(ns.realm)) or short)
	end
	for _, e in ipairs(ns.SignedArbiters and ns.SignedArbiters() or {}) do
		if type(e) == "table" and e.audit then Add(e.name) end
	end
	if mode == "T" and R and type(R.standIns) == "function" then
		local ok, list = pcall(R.standIns, "k", "T")
		for _, n in ipairs(ok and type(list) == "table" and list or {}) do Add(n) end
	end
	return out
end
MarketBank.Auditors = nil

local function Flag(ev, sheet, idx, code, bet)
	local key = code .. "|" .. tostring(idx) .. "|" .. Lower(bet.who)
	ev.flagged = ev.flagged or {}
	if ev.flagged[key] then return false end
	ev.flagged[key] = true
	ev.flags[#ev.flags + 1] = { idx = idx, code = code, who = bet.who, o = bet.o, s = bet.s, t = Now() }
	local list = type(MarketBank.Auditors) == "function" and MarketBank.Auditors(ev.mode, ev) or MarketBank.DefaultAuditors(ev.mode)
	local M = Markets()
	local e = M.Event(ev.eid)
	local body = ("%s~%s~%s~%s~%s~%s~%s"):format(ev.eid, B36(idx), code, ns.FullName(bet.who), bet.o, B36(math.floor(bet.s / 100)), B36(Now()))
	for _, name in ipairs(type(list) == "table" and list or {}) do
		local official = false
		for _, o in ipairs(M.Officials(e, sheet)) do if Same(o, name) then official = true end end
		for _, f in ipairs(M.Fighters(e)) do if Same(f.name, name) then official = true end end
		if not official and not Same(name, bet.who) then ns.Arena.Send("BF", ev.mode, body, { to = name, low = true }) end
	end
	return true
end
MarketBank.Flag = Flag

-- At acceptance: U (an underdog spike), T (both sides of one market by one person), G (against a
-- guildmate).
function MarketBank.BetFlags(ev, sheet, m, bm, bet, before, stakes)
	local total = 0
	for _, v in pairs(before) do total = total + v end
	local mine = before[bet.o] or 0
	local k = MarketBank
	-- U: the outcome held < 25% before, the pool at least 50 g, the stake at least max(3 x the
	-- median accepted stake, 10% of the pool, 20 g).
	if total >= k.SPIKE_POOL and mine * 100 < total * k.UNDER then
		local need = math.max(k.SPIKE_MEDIAN * Median(stakes), math.floor(total * k.SPIKE_SHARE / 100), k.SPIKE_MIN)
		if bet.s >= need then
			if Flag(ev, sheet, m.idx, "U", bet) then
				bm.spikes = bm.spikes or {}
				bm.spikes[#bm.spikes + 1] = bet.who
			end
		end
	end
	-- T: one person (an alt, a key) on two outcomes of one market.
	local D = ns.Debts
	for _, b in ipairs(bm.bets) do
		if b ~= bet and b.o ~= bet.o and (Same(b.who, bet.who) or Call(D, "SameOwner", b.who, bet.who) == true or (b.fp and bet.fp and b.fp == bet.fp)) then
			Flag(ev, sheet, m.idx, "T", bet)
			break
		end
	end
	-- G: on a fighter's opponent, from his guild, 20 g or more.
	if bet.s >= k.GUILDMATE_MIN and type(bet.guild) == "string" then
		local e = Markets().Event(ev.eid)
		for _, f in ipairs(Markets().Fighters(e)) do
			local opponent = f.side == "A" and "2" or "1"
			local kind = Kind(m.type)
			if (m.type == "MW" or m.type == "SW" or kind.stake) and bet.o == opponent and type(f.guild) == "string" and f.guild:lower() == bet.guild:lower() then
				Flag(ev, sheet, m.idx, "G", bet)
			end
		end
	end
end

-- At the lock: L (a late surge): an outcome under 25% at lockAt - 120 that grew by half its size
-- then and by 50 g; its bettors of the last 120 s are flagged, once per market.
function MarketBank.LateFlags(ev, bm, m, sheet)
	local mark = bm.lateMark
	if not mark then return end
	local k = MarketBank
	local total = 0
	for _, v in pairs(mark) do total = total + v end
	for key, now in pairs(bm.pools) do
		local was = mark[key] or 0
		local grew = now - was
		if total > 0 and was * 100 < total * k.UNDER and grew * 100 >= was * k.LATE_GROW and grew >= k.LATE_MIN then
			for _, b in ipairs(bm.bets) do
				if b.o == key and b.t >= sheet.lockAt - k.LATE_WINDOW then Flag(ev, sheet, m.idx, "L", b) end
			end
		end
	end
end

-- At settlement: R (a bettor flagged U in 3 or more settled markets of the same fighter).
function MarketBank.RepeatFlags(ev, bm, m)
	if not bm.spikes then return end
	local store = ns.Arena.Store(ev.mode)
	if type(store) ~= "table" then return end
	store.bankSpikes = type(store.bankSpikes) == "table" and store.bankSpikes or {}
	local e = Markets().Event(ev.eid)
	local rec = Rec(ev.mode, ev.eid)
	for _, who in ipairs(bm.spikes) do
		for _, f in ipairs(Markets().Fighters(e)) do
			local key = Lower(who) .. "|" .. (f.gk or Lower(f.name))
			store.bankSpikes[key] = (store.bankSpikes[key] or 0) + 1
			if store.bankSpikes[key] >= MarketBank.REPEAT_U then
				for _, b in ipairs(bm.bets) do
					if Same(b.who, who) then Flag(ev, rec and rec.sheet, m.idx, "R", b) break end
				end
			end
		end
	end
end

-- BF on an auditor's client: from the event's bank only, to auditors only (never the event's
-- officials), kept per event (the design "audit").
local function OnFlag(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local eid, idx, code, who, o, silver, t = ns.Arena.Fields(body, 7)
	if not t or not Markets().EidOk(eid) or not ("ULTGR"):find(code or "?", 1, true) or #code ~= 1 then return end
	local R = Roles()
	if not (R and R.Auditor and R.Auditor(ns.me, mode)) then return end
	local rec = Rec(mode, eid)
	local sheet = rec and rec.sheet
	if not sheet or not Same(sheet.bank, sender) then return end
	for _, name in ipairs(Markets().Officials(Markets().Event(eid), sheet)) do if Same(name, ns.me) then return end end
	who = ns.Arena.Name(who)
	idx, silver, t = N36(idx, 1, 40), N36(silver, 0), N36(t, 0)
	if not who or not idx or not silver or not t then return end
	local store = ns.Arena.Store(mode)
	store.audit = type(store.audit) == "table" and store.audit or {}
	local a = store.audit[eid] or { flags = {}, t = Now() }
	store.audit[eid] = a
	if #a.flags >= Markets().AUDIT_FLAGS then return end
	a.flags[#a.flags + 1] = { idx = idx, code = code, who = who, o = o, silver = silver, t = t }
	ns.Arena.Changed()
end

---------------------------------------------------------------------------
-- Auditors' check of the book against the ledger (the design): the b entries heard per outcome must
-- equal the locked book's pools. What only the bank could have done wrong holds the market at
-- once (BV H): the ledger shows more than the locked book (a bet the pools hid), or a bet at or
-- after lockAt. Less than the book is shown on the auditor's screen (MarketBank.AuditOf), never
-- held by itself: an entry this client missed (a /reload, a loading screen) looks the same; it
-- clears when the missing entries come, and the auditor holds it with a click if it stays. The
-- King's own client holds nothing by itself (his H only he could lift): it shows it.
---------------------------------------------------------------------------

local function Audit(mode, eid)
	local store = ns.Arena.Store(mode)
	if type(store) ~= "table" then return nil end
	store.audit = type(store.audit) == "table" and store.audit or {}
	local a = store.audit[eid]
	if not a then
		a = { flags = {}, t = Now() }
		store.audit[eid] = a
	end
	return a
end
-- An auditor's record of an event (nil when none): { flags = { { idx, code, who, o, silver, t } },
-- late, mismatch = { [idx] = { kind = "over"|"under"|"late", at, held } } }.
function MarketBank.AuditOf(mode, eid)
	local store = ns.Arena.Store(mode or "L")
	local a = type(store) == "table" and type(store.audit) == "table" and store.audit[eid] or nil
	return a
end
function MarketBank.AuditEntry(bank, seq, e)
	local R = Roles()
	if not (R and R.Auditor and R.Auditor(ns.me, "L")) then return end
	for _, mode in ipairs({ "L", "T" }) do
		local rec = Rec(mode, e.eid)
		if rec and rec.sheet and Same(rec.sheet.bank, bank) then
			local a = Audit(mode, e.eid)
			a.sums, a.seen, a.heardFrom = a.sums or {}, a.seen or {}, a.heardFrom or {}
			local key = tostring(e.idx)
			-- (A grouped entry's bets share its seq: each is told apart by its place in it.)
			local id = key .. "|" .. seq .. "|" .. tostring(e.i or 1)
			if a.seen[id] then return end
			a.seen[id] = true
			-- Heard from its registration (the ledger's n): only then is every bet of it known here.
			if e.k == "n" then a.heardFrom[key] = true return end
			if e.k ~= "b" then return end
			a.sums[key] = a.sums[key] or {}
			a.sums[key][e.o] = (a.sums[key][e.o] or 0) + (e.copper or 0)
			if e.t and e.t >= rec.sheet.lockAt then
				a.late = (a.late or 0) + 1
				a.lateBy = a.lateBy or {}
				a.lateBy[key] = (a.lateBy[key] or 0) + 1
				a.flags[#a.flags + 1] = { idx = e.idx, code = "late", o = e.o, silver = math.floor((e.copper or 0) / 100), t = e.t }
			end
			return
		end
	end
end
-- A book heard on an auditor's client: once a market is declared, the sums of its b entries (this
-- auditor heard them from its registration) against the locked book's pools, the scratched
-- outcomes aside (their stakes go back); checked again at every book, so a shortfall clears when
-- the entries it lacked arrive.
function MarketBank.AuditBook(mode, rec, was)
	local R = Roles()
	if not (R and R.Auditor and R.Auditor(ns.me, mode)) then return end
	local a = Audit(mode, rec.eid)
	local book, sheet = rec.book, rec.sheet
	a.lockPools = a.lockPools or {}
	for idx, b in pairs(book.markets) do
		local key = tostring(idx)
		local m = sheet.markets[idx]
		if m and b.state == "L" and not a.lockPools[key] and not Kind(m.type).pick then
			a.lockPools[key] = {}
			for o, p in ipairs(b.pools) do a.lockPools[key][Sel(o)] = p * 100 end
		end
		if m and m.state == "R" and a.lockPools[key] and (a.heardFrom or {})[key] then
			local sums = (a.sums or {})[key] or {}
			local scratched = Markets().ScratchedOf(sheet, m, Markets().Event(rec.eid))
			local over, under = false, false
			for o = 1, m.n do
				local sel = Sel(o)
				if not scratched[o] then
					local p, s = a.lockPools[key][sel] or 0, sums[sel] or 0
					if s > p then over = true elseif s < p then under = true end
				end
			end
			local late = ((a.lateBy or {})[key] or 0) > 0
			a.mismatch = a.mismatch or {}
			local mm = a.mismatch[key]
			local kind = (over and "over") or (late and "late") or (under and "under") or nil
			if not kind then
				-- (Matched now: a shortfall was entries this client had missed.)
				if mm and mm.kind == "under" then a.mismatch[key] = nil ns.Arena.Changed() end
			else
				if not mm or mm.kind ~= kind then
					mm = { kind = kind, at = Now(), held = mm and mm.held }
					a.mismatch[key] = mm
					ns.Arena.Changed()
				end
				if kind ~= "under" and not mm.held and not (R.IsKing and R.IsKing(ns.me)) then
					if Markets().CanOverrule(rec.eid, idx, "H", mode) then
						mm.held = Markets().Overrule(rec.eid, idx, "H", mode) and true or nil
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The bank's tick: locks, the late-surge marks, grace and holds, the arbiter-gone voids, the pump
---------------------------------------------------------------------------

local function Letter(eid) return eid:sub(1, 1) end

local function Resolve(ev, rec, idx, now)
	local sheet = rec.sheet
	local m = sheet.markets[idx]
	local bm = MarketOf(ev, idx)
	if bm.state ~= "R" then return end
	Rule(ev, rec, idx)
	if bm.state ~= "R" then return end
	-- The witnesses (or the Lottery's roll lines) disagree with the declaration, however late the
	-- bank learns it: the market holds by the game (the design).
	local e = Markets().Event(ev.eid)
	if type(e) == "table" and e.disagree == true and not (bm.hold and bm.hold.duel) then Hold(ev, bm, "duel") end
	-- A hold nobody ruled on: after HOLD_MAX, the game's duel line or a void (a hold from the game
	-- or a gate: the suspect word never pays alone), the declared result (a hold from a word only:
	-- nobody freezes payouts with a complaint).
	if bm.hold then
		if now < bm.hold.at + Markets().HOLD_MAX then return end
		if not bm.hold.duel and not bm.hold.gate and not bm.hold.wallet then
			bm.hold = nil
			return Settle(ev, idx, sheet, m.result)
		end
		local duel = type(e) == "table" and e.duel
		local seen = type(duel) == "table" and (duel.arbiter or (tonumber(duel.witnesses) or 0) >= 2) and (duel.winner == "A" or duel.winner == "B")
		if seen then
			local res = Markets().ResultFromFacts(m, { winner = duel.winner, method = duel.method, dur = duel.dur }, e)
			if res and res ~= "V" and Markets().ReadResult(m, res) then
				bm.hold = nil
				return Settle(ev, idx, sheet, res)
			end
		end
		return VoidMarket(ev, idx, "G")
	end
	if now < (bm.graceFrom or now) + Markets().GRACE then return end
	local gate = gates[Letter(ev.eid)]
	if gate then
		local ok, verdict = pcall(gate, ev.eid, idx, m.result, ev.mode)
		if ok and verdict == "hold" then return Hold(ev, bm, "gate") end
		if not ok or verdict ~= true then
			-- A gate still waiting GATE_WAIT after the grace holds the market (then HOLD_MAX's
			-- ruling applies), never keeping the stakes in escrow for ever.
			bm.gateFrom = bm.gateFrom or now
			if now - bm.gateFrom >= Markets().GATE_WAIT then Hold(ev, bm, "gate") end
			return
		end
	end
	bm.gateFrom = nil
	return Settle(ev, idx, sheet, m.result)
end

function MarketBank.Tick()
	local now = Now()
	for _, mode in ipairs({ "L", "T" }) do
		-- (The King's live switch off: no lock, payout or void moves money until it is on again;
		-- the books wait with them.)
		local live = MarketBank.Live(mode)
		for eid, ev in pairs(live and Index(mode) or {}) do
			local rec = type(ev) == "table" and Rec(mode, eid)
			local sheet = rec and rec.sheet
			if sheet and Same(sheet.bank, ns.me) then
				for _, idx in ipairs(sheet.order) do
					local bm = MarketOf(ev, idx)
					local m = sheet.markets[idx]
					-- (A Lottery day whose pot's source was not declared yet when it came: again.)
					if m and Kind(m.type).lottery and not bm.carryChecked then TakeCarry(ev, sheet, m) end
					if bm.state == "O" then
						if not bm.lateMark and now >= sheet.lockAt - MarketBank.LATE_WINDOW then
							bm.lateMark = {}
							for k, v in pairs(bm.pools) do bm.lateMark[k] = v end
						end
						if now >= sheet.lockAt then Lock(ev, idx, sheet) end
					elseif bm.state == "R" then
						Resolve(ev, rec, idx, now)
					elseif bm.state == "L" then
						-- The arbiter gone: no result NO_RESULT after the lock (a tournament's, TOURNEY_MAX; a
						-- Bones table's, TABLE_MAX: its game goes on after the lock). An event's own
						-- noResult (a Lottery day's draw hour) only on a bank online since the lock: it heard any
						-- declaration made in that time. A bank that came on later cannot tell no draw from a
						-- declaration it missed (its repeats come every REPEAT_LOCKED), so it waits the long time
						-- and the declaration wins.
						local kind = Markets().Event(eid)
						local k = type(kind) == "table" and kind.kind or nil
						local wait = (k == "tourney" or k == "lottery") and Markets().TOURNEY_MAX
							or (k == "farkle" and Markets().TABLE_MAX) or Markets().NO_RESULT
						local own = type(kind) == "table" and tonumber(kind.noResult) or nil
						if own and Markets().OnlineFor(now) >= now - sheet.lockAt then wait = own end
						if now >= sheet.lockAt + wait then VoidMarket(ev, idx, "G") end
					end
				end
			end
		end
	end
	Pump(now)
	-- (Every hour while on duty: closed events compacted, the oldest dropped, the design.)
	if now - (session.pruned or 0) >= 3600 then
		session.pruned = now
		MarketBank.Prune()
	end
	Involve()
end

local tickOn = false
Involve = function()
	local busy = false
	for _, mode in ipairs({ "L", "T" }) do
		for eid, ev in pairs(Index(mode) or {}) do
			local rec = type(ev) == "table" and Rec(mode, eid)
			local sheet = rec and rec.sheet
			if sheet and Same(sheet.bank, ns.me) then
				if not Over(ev, sheet) or ev.dirty or ev.urgent then busy = true end
				if Over(ev, sheet) and ev.overAt and Now() - ev.overAt <= MarketBank.BO_AFTER_FOR then busy = true end
				if Over(ev, sheet) and not ev.overAt then busy = true end
			end
		end
	end
	if busy and not tickOn then
		tickOn = true
		ns.Arena.Every(1, "market bank", function() ns.SafeCall("market bank tick", MarketBank.Tick) end)
	end
	ns.Arena.Involve("market bank", busy)
	return busy
end
MarketBank.Involve = function() return Involve() end

---------------------------------------------------------------------------
-- The index rebuilt from the ledger at load (the design): the ledger is the one source.
---------------------------------------------------------------------------

-- A settled bracket pool's book carries its top score and how many share it: counted again from
-- the ledger's entries when the ledger gives its bracket result alone ("P<hex>").
local function PickResults(ev, sheet)
	for idx, bm in pairs(ev.markets) do
		local m = sheet.markets[idx]
		if m and Kind(m.type).pick and bm.state == "S" and type(bm.result) == "string" and not bm.result:find(".", 1, true) then
			local res = Markets().ReadResult(m, bm.result)
			local entries = {}
			for _, b in ipairs(bm.bets) do entries[#entries + 1] = { o = b.o, s = b.s } end
			local rounds = 0
			while 2 ^ rounds < (sheet.size or m.n) do rounds = rounds + 1 end
			local r = res and #entries > 0 and ns.ArenaMath.Pickem(entries, res.pick, rounds, Markets().FeeArg(sheet)) or nil
			local nwin = r and (r.refund and #entries or #r.winners) or 0
			bm.result = ("%s.%s.%s"):format(bm.result, B36(r and r.top or 0), B36(nwin))
		end
	end
end

-- What the ledger does not say comes back from the index as it was saved: the late-surge marks,
-- the spikes, the Lottery's pot claims, the gate's wait.
local KEEP = { "lateMark", "spikes", "carryTo", "carryFrom", "carryIn", "carried", "carryChecked", "carrySeen", "awaitFrom", "rolled",
	"potGone", "potWait", "gateFrom" }
local function Keep(bm, o)
	if type(o) ~= "table" then return end
	for _, k in ipairs(KEEP) do bm[k] = o[k] end
end
-- A second x C entry moves an already-settled v2 Lottery's retained carry; its signed L2 result
-- remains the book result. The R conversion is only for a pre-v2 ledger being rebuilt.
local function LedgerResult(bm, result, o)
	if type(result) == "string" and result:sub(1, 1) == "C" then
		local Lo = ns.Lottery
		if Lo and Lo.DecodeResult then
			if Lo.DecodeResult(bm.result) then return bm.result end
			if type(o) == "table" and Lo.DecodeResult(o.result) then return o.result end
		end
		if type(o) == "table" and o.state == "S" and type(o.result) == "string" and o.result:sub(1, 1) == "R" then return o.result end
		return "R." .. B36(Pool(bm) + (type(o) == "table" and o.carryIn or 0))
	end
	return result
end

-- Without Wallet.Entries: each market of the sheets naming this bank, from Wallet.Bets(eid, idx)
-- ({ acct, o, s, nonce, seq, t }) and Wallet.Market(eid, idx) ({ closed, settled, result }).
local function RebuildFromBets(mode, list)
	local W = Wallet()
	local bets, market = Fn(W, "Bets"), Fn(W, "Market")
	if not bets then return false end
	for _, rec in ipairs(Markets().All(mode)) do
		local sheet = rec.sheet
		if sheet and Same(sheet.bank, ns.me) then
			local old = list[rec.eid]
			local ev = { eid = rec.eid, mode = mode, markets = {}, bySlip = {}, senders = {}, n = old and old.n or 0, created = old and old.created or Now(),
				flags = old and old.flags or {}, flagged = old and old.flagged, scratched = old and old.scratched, day = old and old.day }
			for _, idx in ipairs(sheet.order) do
				local bm = MarketOf(ev, idx)
				local o = old and old.markets and old.markets[idx]
				local okB, list2 = pcall(bets, rec.eid, idx)
				if okB and type(list2) == "table" then
					bm.registered = true
					for _, b in ipairs(list2) do
						local who = ns.FullName(tostring(b.acct or "?"))
						local bet = { who = who, acct = b.acct, o = tostring(b.o), s = tonumber(b.s) or 0, nonce = b.nonce, t = b.t or 0, seq = b.seq }
						bm.bets[#bm.bets + 1] = bet
						bm.pools[bet.o] = (bm.pools[bet.o] or 0) + bet.s
						bm.counts[bet.o] = (bm.counts[bet.o] or 0) + 1
						if bet.nonce then ev.bySlip[Lower(who) .. "#" .. bet.nonce] = { idx = idx, o = bet.o, s = bet.s, i = #bm.bets } end
					end
				end
				local okM, info = pcall(market or function() end, rec.eid, idx)
				if okM and type(info) == "table" then
					if info.settled then
						bm.state, bm.result = info.result == "V" and "V" or "S", LedgerResult(bm, info.result, o)
					elseif info.closed then
						bm.state = "L"
						bm.lockPools = {}
						for k, v in pairs(bm.pools) do bm.lockPools[k] = v end
					end
				end
				if o then
					if bm.state == "L" and (o.state == "R" or o.hold) then
						bm.state, bm.declared, bm.declaredT, bm.graceFrom, bm.hold = "R", o.declared, o.declaredT, o.graceFrom, o.hold
					end
					Keep(bm, o)
					if bm.state == "S" and o.state == "S" then bm.result = o.result end
				end
			end
			PickResults(ev, sheet)
			list[rec.eid] = ev
			MarketBank.OnSheet(mode, rec, rec.sheet)
		end
	end
	Involve()
	return true
end

function MarketBank.Rebuild(mode)
	local W = Wallet()
	-- Only a bank has a ledger to rebuild from (an idle client makes nothing here).
	local R = Roles()
	if not (R and R.IsBank and R.IsBank(ns.me, mode)) then return false end
	local f = Fn(W, "Entries")
	if not f then
		local list = Index(mode, true)
		if not list then return false end
		return RebuildFromBets(mode, list)
	end
	local list = Index(mode, true)
	if not list then return false end
	local fresh = {}
	local ok, err = pcall(f, function(seq, entry)
		local e = Markets().ParseEntry(entry)
		if not e then return end
		local ev = fresh[e.eid]
		if not ev then
			ev = { eid = e.eid, mode = mode, markets = {}, bySlip = {}, senders = {}, n = (list[e.eid] and list[e.eid].n) or 0, created = Now(), flags = {} }
			fresh[e.eid] = ev
		end
		local bm = MarketOf(ev, e.idx)
		if e.k == "n" then
			bm.registered = true
		elseif e.k == "b" then
			local who = e.who and ns.FullName(e.who) or tostring(e.acct or e.code or "?")
			local bet = { who = who, acct = e.acct, o = e.o, s = e.copper or 0, nonce = e.nonce, t = e.t or 0, seq = seq }
			bm.bets[#bm.bets + 1] = bet
			bm.pools[e.o] = (bm.pools[e.o] or 0) + bet.s
			bm.counts[e.o] = (bm.counts[e.o] or 0) + 1
			if e.nonce then ev.bySlip[Lower(who) .. "#" .. e.nonce] = { idx = e.idx, o = e.o, s = bet.s, i = #bm.bets } end
		elseif e.k == "z" then
			bm.state = "L"
			bm.lockPools = {}
			for k, v in pairs(bm.pools) do bm.lockPools[k] = v end
		elseif e.k == "x" then
			if e.result == "V" or (type(e.result) == "string" and e.result:sub(1, 1) == "V") then
				bm.state, bm.result = "V", e.code or "V"
			else
				local old = list[e.eid]
				bm.state, bm.result = "S", LedgerResult(bm, e.result, old and old.markets and old.markets[e.idx])
			end
		end
	end, mode)
	if not ok then ns.Log("market bank: rebuild failed: %s", tostring(err)) return false end
	-- What the ledger does not say (a declaration in its grace, holds) comes back from the sheets.
	for eid, ev in pairs(fresh) do
		local old = list[eid]
		if type(old) == "table" then
			ev.flags, ev.flagged, ev.scratched = old.flags or {}, old.flagged, old.scratched
			for idx, bm in pairs(ev.markets) do
				local o = old.markets and old.markets[idx]
				if o and bm.state == "L" and (o.state == "R" or o.state == "H") then
					bm.state, bm.declared, bm.declaredT, bm.graceFrom, bm.hold = "R", o.declared, o.declaredT, o.graceFrom, o.hold
				end
				Keep(bm, o)
			end
		end
		list[eid] = ev
		local rec = Rec(mode, eid)
		if rec and rec.sheet then
			PickResults(ev, rec.sheet)
			MarketBank.OnSheet(mode, rec, rec.sheet)
		end
	end
	Involve()
	return true
end

-- The bank's console: its events, what is open, owed flags.
function MarketBank.View(mode)
	local out = {}
	for eid, ev in pairs(Index(mode or "L") or {}) do
		if type(ev) == "table" then
			local row = { eid = eid, markets = {}, flags = #(ev.flags or {}), refused = ev.refused or 0 }
			for idx, bm in pairs(ev.markets) do
				local pool = 0
				for _, b in ipairs(bm.bets) do pool = pool + b.s end
				row.markets[#row.markets + 1] = { idx = idx, state = bm.state, bets = #bm.bets, pool = pool, hold = bm.hold and (bm.hold.duel and "duel" or (bm.hold.gate and "gate" or (bm.hold.wallet and "wallet" or "word"))) or nil,
					graceEnds = bm.graceFrom and (bm.graceFrom + Markets().GRACE) or nil,
					-- (The Lottery's pot: the day that claimed it, since when it waits for one, the pot promised in.)
					carryTo = bm.carryTo and bm.carryTo.eid or nil, awaiting = bm.awaitFrom, carryFrom = bm.carryFrom, carryIn = bm.carryIn }
			end
			table.sort(row.markets, function(a, b) return a.idx < b.idx end)
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b) return a.eid < b.eid end)
	return out
end

-- Pruning (the design bankEvents: 40 events, full rows for 10 or 30 days): closed events' bet rows
-- are compacted to their totals, the oldest closed ones dropped past the cap.
function MarketBank.Prune()
	local now = Now()
	for _, mode in ipairs({ "L", "T" }) do
		local list = Index(mode)
		local closed = {}
		for _, ev in pairs(list or {}) do
			local done = true
			for _, bm in pairs(type(ev) == "table" and ev.markets or {}) do
				if bm.state ~= "S" and bm.state ~= "V" then done = false end
			end
			if done and type(ev) == "table" then closed[#closed + 1] = ev end
		end
		table.sort(closed, function(a, b) return (a.created or 0) > (b.created or 0) end)
		for i, ev in ipairs(closed) do
			if i > MarketBank.FULL_EVENTS or now - (ev.created or now) > MarketBank.FULL_KEEP then
				for _, bm in pairs(ev.markets) do
					if #bm.bets > 0 then bm.compact, bm.bets = #bm.bets, {} end
				end
				ev.bySlip = {}
			end
		end
		local n = 0
		for _ in pairs(list or {}) do n = n + 1 end
		for i = #closed, 1, -1 do
			if n <= MarketBank.EVENTS_MAX then break end
			list[closed[i].eid] = nil
			n = n - 1
		end
	end
end

ns.On("LOGIN", function()
	session.epoch = Now()
	for _, mode in ipairs({ "L", "T" }) do MarketBank.Rebuild(mode) end
	MarketBank.Prune()
	Involve()
end)

ns.Comm.Handle("BF", ns.Arena.Handle("BF", OnFlag))
