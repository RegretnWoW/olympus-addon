local ADDON, ns = ...

-- 1.2, the Blood Arena: Wallet.lua. A stub the arena's core created for the money part (money) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The bank's ledger (per currency, blinded codes, MAC and public hash chain, snapshots), deposits,
-- withdrawals with intents, replication (ZH ZE ZN ZG), recovery, reconciliation, the operator's
-- queues, and the player's wallet and receipts. Registers ZH ZE ZN ZG ZD ZK ZC ZW ZS ZQ ZL ZJ.
-- One balance for the Arena, Farkle and the Lottery (the design).
-- API (the design):
--   Player: Wallet.Banks(), Wallet.Online(bank), Wallet.Statement(bank) -> { g = { bal, escrow,
--     reserved }, p = { bal, escrow }, pending, code, token }, Wallet.Deposit(bank, how, copper),
--     Wallet.Withdraw(bank, copper|"all") (gold only), Wallet.Receipts()
--   Wallet.OnEntry(fn): fn(bank, seq, entry) for every entry heard (Markets matches the full tuple)
--   Bank: Wallet.Account(name), Wallet.Facts(acct) -> { gk, guild, level, fp, frozen },
--     Wallet.Available(acct), Wallet.Register(eid, idx, spec), Wallet.Hold(acct, copper, ref) -> seq
--     or nil, why; Wallet.Close(eid, idx), Wallet.Settle(eid, idx, winners), Wallet.Void(eid, idx,
--     code), Wallet.Owed(), Wallet.Liabilities()
--   Operator: Wallet.CallNext(), Wallet.PayNext(), Wallet.PayGuild(), Wallet.Accept(claim),
--     Wallet.Drill()
--   Auditors: Wallet.Replica(bank)
-- Hooks it fills: ArenaRoles.stillOwing (a dropped bank with liabilities stays closing), the
-- bank's duty through Arena.SetDuty("bank", on) (Comm leaves a bank out of the census election).
--
-- the money part's full contract (the names the markets, the Farkle table, the Lottery and the screens use):
--   Units. Every amount is a whole number of ledger units: copper for gold ("g"); for glory points
--     ("p", the King's option) and a rehearsal's chips ("c", kept in the "p" balance of the
--     rehearsal's store) 100 units are one point or one chip (Wallet.UNIT), so a slip's stake in
--     whole silver is whole points too. Wallet.POINTS_WEEK: the weekly grant (1,000 points).
--   Modes. The bank works in one mode at a time (Wallet.Duty), "L" (the realm's live store) or "T"
--     (a rehearsal's); every bank-side call acts on the duty's mode. Player-side calls take an
--     optional last argument mode ("L" by default).
--   The player: Wallet.Banks(mode) -> { { name, state = "o"|"c", online, heardAt, mapID, persists,
--       epoch, full, paused, closing, trading (the head's "d": a depositor was called; bets are
--       still taken) } }; Wallet.Online(bank, mode); Wallet.Statement(bank, mode) (also seq,
--       at, epoch; pending = gold sent and not yet credited); Wallet.Deposit(bank, how "t"|"m",
--       copper, mode) -> receipt or nil, why ("rate": one ZD, and one ZW, per bank every
--       Wallet.ASK_GAP = 10 s; it whispers ZD and the key claim; the gold moves only
--       on the player's own click: Wallet.FillDeposit(id) fills the mail, or the trade once the bank
--       calls him); Wallet.Withdraw(bank, copper|"all", mode) -> intent or nil, why;
--       Wallet.Claim(bank, id, mode) (a lost receipt: ZL); Wallet.AskStatement(bank, mode);
--       Wallet.Receipts(mode) -> newest first, each { id, bank, how, copper, t, state = "asked"|
--       "queued"|"called"|"sent"|"mail"|"credited"|"refused"|"returned" (the game sent an untaken
--       mail back after 30 days), claim ("Tell the bank" is due), notTaken (a mail the bank has not
--       taken after 24 hours) }; Wallet.TopUp(bank) (a chips rehearsal's tester: 100 chips, once an
--       hour, ZQ~T); Wallet.AutoWithdraw(on) ("send my winnings after each
--       event", gold: ZW all when a statement shows gold leaving his bets); Wallet.View(mode) -> the
--       Wallet tab's model: { persists, live, currency ("g"|"p"|"c" for this view), unit, slot,
--       rehearsal, copper, banks = { Statement +
--       Banks row }, receipts, intents, debts = Debts.View(mode), token, autoWithdraw, tickets = nil
--       (Markets') }.
--     Wallet.Listen(key, on): a client with open tickets hears the ledger (ZE) and gets OnEntry;
--     anyone else ignores its bytes (the weight rule). Auditors and the bank always hear it.
--     OnEntry's entry: the parsed entry, { k = "b", market, eid, idx, o, s (units), nonce, t, i }
--     for each bet of a grouped entry, { k = "z"|"x"|"n"|..., market, ... } otherwise; codes stay
--     blinded except on an auditor's client.
--   The bank (its duty; every call that writes needs it, else nil, "duty"):
--     Wallet.Duty(on, mode) -> ok, why ("unlisted", a MayBank reason, "live", "persist" for gold
--       where saved data does not survive, "consent"); Wallet.OnDuty() -> mode or nil;
--       Wallet.Pause(on); Wallet.SetBankYes(on) (the privacy page's "arenabank" line).
--     Wallet.Account(name, create) -> acct key; Wallet.Facts(acct) (also bound, name, code);
--       Wallet.Available(acct, cur).
--     Wallet.Register(eid, idx, spec): spec = { nsel, closes (lockAt), feeBp, arbBp, kind "p"|"s"|"l",
--       cur "g"|"p"|"c", to "a"|"g", arbiter = name, rounds (a bracket pool), public (the event
--       is public; else Arena.EventOf(eid).public), event (its kind; else EventOf's); a stake
--       market (kind "s": the King's fights, a Bones game from the wallets) also parties =
--       { A = name, B = name } and stakes = { A = copper, B = copper } in whole silver: Hold then
--       takes only party o's own stake, exactly, on "A" or "B", once ("party", "stake", "held");
--       its entries go on the channel as h:<digest>, their text to the auditors }. The
--       arbiter is paid his part only when one is named who is not the King; otherwise all of the
--       fee is the guild's. A points or chips market takes no fee. A closing bank registers
--       nothing ("closing"); gold with no fee receiver is refused ("receiver"); an arbiter of the
--       bank's own account or key ("arbiter"); a stake market without its two parties and stakes
--       ("parties"). Returns the seq.
--     Wallet.Hold(acct, copper, ref): ref = { eid, idx, o, nonce } -> seq, place, or nil, why
--       ("market", "closed", "closing", "late", "silver", "funds", "frozen", "bound", "shape", "U"
--       another tuple under a known nonce; a stake market's "party", "stake", "held"); the same nonce and tuple again: its seq and place
--       (nothing held twice). Grouped: bets of one market, outcome and bank second share an entry.
--     Wallet.Close(eid, idx); Wallet.Settle(eid, idx, winners, scratched) -> ArenaMath's result;
--       winners: an outcome, a list of them, or "P<hex>" for a bracket pool. A Lottery registers
--       kind "l" and uses Wallet.SettleLottery(eid, idx, fiveAnimals), the versioned pure contract.
--       Wallet.Void(eid, idx, code). Wallet.Carry(eid, idx, toEid, toIdx) moves only retained
--       unclaimed Lottery profit (or a void day's incoming pot); Wallet.Pot(eid, idx).
--       Wallet.Bets(eid, idx) -> the market's bets from the ledger ({ acct, o, s, nonce, seq, i });
--       Wallet.Market(eid, idx) -> its registration and state (rebuilt from the ledger).
--     Wallet.Lag() -> BO's lag: seconds for the bets waiting for the channel at Wallet.RATE (150)
--       a minute. Wallet.Oracle(from, to, cur) -> the Oracle's inputs (the fights part's IO): { { name, profit,
--       staked, markets, first } } over the public pool markets of that currency (the realm's by
--       default) settled in [from, to), by name; never a private event's, the Lottery's, a void.
--     Wallet.SaveReady() -> true when "Save now" is offered (no market open, nothing to send), or
--       nil, "open"|"backlog". Wallet.ChipsGrant(acct): a chips rehearsal's chips, once (the
--       first action does it by itself); the tester's top up is ZQ~T (100 chips an hour).
--     Wallet.Grant(acct, cur, units, why, ref): chips ("J", "rehearse") or points ("P").
--     Wallet.Owed() (guild fees not yet mailed), Wallet.Liabilities() -> { g, p, owed, float,
--       accounts }, Wallet.Reserve() -> { gold, liabilities, owed, float, surplus, unexplained,
--       deficit, points }.
--     Operator: Wallet.CallNext(), Wallet.PayNext(), Wallet.PayTrade(qseq), Wallet.PayGuild(),
--       Wallet.GiveBack(key), Wallet.Accept(nonce), Wallet.Refuse(nonce), Wallet.ApplyOrder(nonce),
--       Wallet.Reconcile(qseq, sent), Wallet.Checkpoint() (nil, "open"|"pot" while a market or a
--       carried pot waits), Wallet.ReseatAsk(oldEpoch), Wallet.Reseat(auditorA, auditorB) (or two
--       replica tables and the last head { seq, head }), Wallet.Drill(), Wallet.SendHead().
--     Wallet.Console() -> the Bank tab's model: { mode, name, epoch, seq, state, paused, currency,
--       queue, inbox (each mail: take or return, and why), withdrawals = { queue, intents,
--       blocked }, fees = { owed, ref, due, state, receiver, updated }, reserve, claims, orders,
--       giveBack, items, accounts, markets, health = { queue, backlog, lastSent, replayed },
--       saveNow (Wallet.SaveReady: "Save now" is offered) }.
--   Auditors: Wallet.Replica(bank, mode) -> { name, epoch, seq, head, matches, verified, accounts =
--     { { name, code, g, p } }, liabilities, owed, float, reserve (the bank's ZG), attest (the
--     reserve seen in a trade), flags, gap, kb }; Wallet.ReplicaMarket(bank, eid, idx, mode) ->
--     { cur, kind, closes, pools = { [o] = units }, pool, bets, closed, settled, result, late }
--     (the markets compares the pools with the L book at x and holds with BV H when they differ);
--     Wallet.Ledgers(mode) -> { banks, arbiters =
--     Stakes.Books, debts = Debts.Ledger }; Wallet.Attest(bank) (the reserve attestation: open a
--     trade with the bank; its gold is read from the window and the trade is cancelled);
--     Wallet.Order(bank, code, sign, copper, why, ref); Wallet.Hello() (the auditors' and the fee
--     receiver's ZQ~H, 40 s after login and every 15 minutes).
--   Wallet.ReceiverUpdated() -> the fee receiver's 1.2 client was heard in the last 7 days.
--   Wallet.CheckBackup(v) -> v or nil: Backup.arenaChecks.bank (a restored ledger's shape and its
--     MAC chain under its own secret).
--   The buttons (Arena.Can, Arena.Do): see the end of this file.
--   Wallet.Ledger engine (shared by the bank and the replicas, pure): Wallet.Apply(st, e),
--     Wallet.Render(e, seq, kb), Wallet.Parse(text, seq, kb), Wallet.NewState(), Wallet.Totals(st),
--     Wallet.Chain(h, n, text), Wallet.Genesis(ep), Wallet.Mac(secret, prev, n, text),
--     Wallet.Blind(code, kb, seq, i), Wallet.SnapDigest(st), Wallet.Recompute(replica, seq).
-- The entries (the design, as amended; numbers base 36, codes blinded per entry):
--   o float in; d deposit; q withdrawal asked; W its intent (before the fill); w sent; c taken;
--   r came back; n a market (currency, fee, who gets the arbiter's part); B<market>.<o>.<t>: bets;
--   z closed; x settled (w1+w2, V, P<hex>, or C<market>: carried); A the arbiter's credit; g the
--   guild's fee mailed; G it came back; t wallet to wallet; a adjustment (C claim, J order, W
--   write-off, P weekly points); u gold that matched nothing; v one account at a snapshot; k the
--   checkpoint; h:<digest> an opaque stake-market entry (its full text whispered to auditors).
-- Events: WALLET_CREDITED (bank, copper), WALLET_PAID (bank, copper), WALLET_REFUSED (bank, why),
--   WALLET_CALLED (bank: the player's trade may start; the screens raises the alert).

local L = ns.L
local Wallet = {}
ns.Wallet = Wallet

Wallet.BANK_FRESH = 150        -- a bank whose head was heard this recently is online
Wallet.HEAD_EVERY = 60
Wallet.RESERVE_EVERY = 300
Wallet.TICK = 10
Wallet.MIN_WITHDRAW = 10000    -- 1 g, or all of a balance of three postages at least
Wallet.GROUP_MAX = 11          -- bets in one grouped entry
Wallet.ZE_ROOM = 225           -- bytes of entries in one ZE (a message is 255 at most)
Wallet.ACCOUNTS_MAX = 5000
Wallet.ENTRIES_MAX = 5000
Wallet.BACKLOG_MAX = 2000
Wallet.CALL_WAIT = 60          -- a called depositor trades within this, else goes to the back once
Wallet.HOLDER_FRESH = 1800     -- statements go to holders heard this recently
Wallet.HELLO_AFTER = 40
Wallet.HELLO_EVERY = 900
Wallet.RECEIVER_FRESH = 7 * 86400
Wallet.CLAIM_AFTER = 600       -- a trade not credited this long after it completed: "Tell the bank"
Wallet.RECEIPTS_MAX = 100
Wallet.INTENTS_MAX = 20
Wallet.UNIT = { g = 1, p = 100, c = 100 }
Wallet.POINTS_WEEK = 1000 * 100
Wallet.CHIPS = 1000 * 100     -- a chips rehearsal's chips each, when its director names none
Wallet.CHIPS_MAX = 100000 * 100
Wallet.TOPUP = 100 * 100       -- a tester's "Top up": 100 chips...
Wallet.TOPUP_EVERY = 3600      -- ...at most once an hour
Wallet.COPPER_DEPOSIT = 10000  -- a copper rehearsal: 1 g a deposit at most...
Wallet.COPPER_HELD = 500000    -- ...and 50 g held by its bank
Wallet.TOKEN_REISSUE = 3600    -- a standing token is signed again when it has less than this left
Wallet.CHECKPOINT_AFTER = 200  -- entries since the last checkpoint before one is written by itself

local function A() return ns.Arena end
local function Now() return ns.Arena.Now() end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end
local function B36(n) return ns.Arena.B36(n) end
local function N(s, lo, hi) return ns.Arena.N(s, lo, hi) end
local function D() return ns.Debts end
local function R() return ns.ArenaRoles end
local function Money() return ns.ArenaMoney end
local function Slot(cur) return cur == "g" and "g" or "p" end
local function Mode(mode) return mode == "T" and "T" or "L" end
local function Store(mode) return ns.Arena.Store(Mode(mode)) end
local function Peek(mode) return ns.Debts.Peek(Mode(mode)) end

---------------------------------------------------------------------------
-- The ledger engine (pure): the same state from the same entries, on the bank and on every
-- auditor's replica (the design, as amended).
---------------------------------------------------------------------------

-- A wallet code on the channel, blinded per entry (the design): code40 XOR the first 5 bytes of
-- SHA256(kb .. "|m|" .. seq .. "|" .. i), byte by byte. Its own inverse.
local bxor = bit and bit.bxor or function(a, b)
	local r, p = 0, 1
	while a > 0 or b > 0 do
		local x, y = a % 2, b % 2
		if x ~= y then r = r + p end
		a, b, p = (a - x) / 2, (b - y) / 2, p * 2
	end
	return r
end
function Wallet.Blind(code, kb, seq, i)
	local mask = ns.Sign.SHA256(tostring(kb) .. "|m|" .. tostring(seq) .. "|" .. tostring(i or 1))
	local out, c = 0, code
	local bytes = {}
	for k = 5, 1, -1 do
		bytes[k] = c % 256
		c = (c - bytes[k]) / 256
	end
	for k = 1, 5 do out = out * 256 + bxor(bytes[k], mask:byte(k)) end
	return out
end

-- The hash chain everyone can check: h_n = SHA256(h_{n-1} .. "|" .. n .. "|" .. SHA256(text_n));
-- an opaque entry "h:<digest>" gives its digest (the SHA-256 of its full text) directly.
local function Digest(text)
	local d = type(text) == "string" and text:match("^h:([%w%-_]+)$")
	if d then
		local raw = ns.Ed25519.FromB64(d)
		if raw and #raw == 32 then return raw end
	end
	return ns.Sign.SHA256(text)
end
function Wallet.Chain(prev, n, text) return ns.Sign.SHA256(prev .. "|" .. tostring(n) .. "|" .. Digest(text)) end
function Wallet.Genesis(ep) return ns.Sign.SHA256("OLYH1|" .. tostring(ep)) end
function Wallet.HeadHex(h) return (h:sub(1, 8):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
-- The MAC only the bank can make (its secret): the full text of an opaque entry.
function Wallet.Mac(secret, prev, n, text)
	local h = ns.Sign.SHA256(tostring(secret) .. "|" .. tostring(prev) .. "|" .. tostring(n) .. "|" .. text)
	local v = 0
	for i = 1, 5 do v = v * 256 + h:byte(i) end
	return B36(v)
end

local function Acc(st, code)
	local a = st.acc[code]
	if not a then
		a = { g = { bal = 0, reserved = 0, escrow = 0 }, p = { bal = 0, escrow = 0 } }
		st.acc[code] = a
	end
	return a
end

function Wallet.NewState()
	return { acc = {}, owed = 0, float = 0, post = 0, m = {}, wd = {}, wseqs = {}, u = { i = 0, o = 0 }, deposits = 0, sums = { d = 0, r = 0, ap = 0, am = 0, w = 0, g = 0 },
		carry = {}, carryCur = {} }
end

-- Parses a market id "<eid>.<idx36>".
local function MarketParts(market)
	local eid, idx = tostring(market):match("^([%w%-]+)%.([0-9a-z]+)$")
	return eid, idx and N(idx, 0)
end
function Wallet.MarketId(eid, idx) return tostring(eid) .. "." .. B36(idx) end

-- Applies an entry (codes unblinded) to a state. nil, why when it can't apply (a replica flags it).
function Wallet.Apply(st, e, seq)
	local k = e.k
	if k == "o" then
		st.float = st.float + e.copper
	elseif k == "d" then
		local a = Acc(st, e.code)
		a.g.bal = a.g.bal + e.copper
		st.sums.d = st.sums.d + e.copper
		st.deposits = st.deposits + e.copper
	elseif k == "q" then
		local a = Acc(st, e.code)
		if a.g.bal < e.copper then return nil, "funds" end
		a.g.bal, a.g.reserved = a.g.bal - e.copper, a.g.reserved + e.copper
		st.wd[seq] = { code = e.code, copper = e.copper, nonce = e.nonce, state = "q" }
	elseif k == "W" then
		local w = st.wd[e.qseq]
		-- (Its q before the snapshot this state started from: the reservation is in the v line.)
		if not w then
			w = { code = e.code, copper = e.copper, state = "q", early = true }
			st.wd[e.qseq] = w
		end
		w.state, w.Wseq = "W", seq
	elseif k == "w" then
		local a = Acc(st, e.code)
		local w = e.qseq and st.wd[e.qseq]
		if e.qseq and not w and a.g.reserved >= e.copper then
			-- (A request from before the snapshot: its reservation is in the v line.)
			w = { code = e.code, copper = e.copper, state = "q", early = true }
			st.wd[e.qseq] = w
		end
		if w and w.code == e.code then
			local take = math.min(e.copper, a.g.reserved)
			a.g.reserved = a.g.reserved - take
			if e.copper > take then a.g.bal = a.g.bal - (e.copper - take) end
			w.sent = (w.sent or 0) + e.copper
			w.state, w.wseq = w.sent >= w.copper and "w" or "q", seq
		else
			if a.g.bal < e.copper then return nil, "funds" end
			a.g.bal = a.g.bal - e.copper
		end
		st.wseqs[seq] = { code = e.code, copper = e.copper, post = e.post, qseq = e.qseq }
		st.sums.w = st.sums.w + e.copper
	elseif k == "c" then
		local w = st.wseqs[e.wseq]
		if w then w.confirmed = true end
	elseif k == "r" then
		local w = st.wseqs[e.wseq]
		if w and w.code ~= e.code then return nil, "wseq" end
		local a = Acc(st, e.code)
		a.g.bal = a.g.bal + e.copper
		if w then w.returned = true end
		st.sums.r = st.sums.r + e.copper
	elseif k == "n" then
		if st.m[e.market] then return nil, "market" end
		local eid = MarketParts(e.market)
		if (eid and eid:sub(1, 1) == "L") ~= (e.kind == "l") then return nil, "version" end
		if e.kind == "l" and (e.nsel ~= 25 or e.feeBp ~= 600 or e.arbBp ~= 0 or e.to ~= "g" or e.cur ~= "g") then return nil, "version" end
		st.m[e.market] = { nsel = e.nsel, closes = e.closes, feeBp = e.feeBp, arbBp = e.arbBp, kind = e.kind, cur = e.cur, to = e.to, bets = {}, pool = 0, pools = {} }
	elseif k == "B" then
		local m = st.m[e.market]
		if not m then return nil, "market" end
		if m.closed or m.settled then return nil, "closed" end
		local slot = Slot(m.cur)
		for i, b in ipairs(e.bets) do
			local a = Acc(st, b.code)
			if a[slot].bal < b.s then return nil, "funds" end
			a[slot].bal, a[slot].escrow = a[slot].bal - b.s, a[slot].escrow + b.s
			m.bets[#m.bets + 1] = { code = b.code, o = e.o, s = b.s, nonce = b.nonce, seq = seq, i = i, t = e.t }
			m.pool = m.pool + b.s
			m.pools[e.o] = (m.pools[e.o] or 0) + b.s
		end
	elseif k == "z" then
		local m = st.m[e.market]
		if not m then return nil, "market" end
		m.closed = true
	elseif k == "x" then
		local m = st.m[e.market]
		if not m then return nil, "market" end
		local M = ns.ArenaMath
		local Lo = ns.Lottery
		st.carry, st.carryCur = st.carry or {}, st.carryCur or {}
		local slot0 = Slot(m.cur)
		-- A carry entry ("C<market>") moves retained money into the later market's pot. Version-2
		-- Lottery markets must settle first, so their path below can move only unclaimed profit.
		local to = e.result:match("^C([%w%-]+%.[0-9a-z]+)$")
		-- A void refunded this day's stakes but deliberately retained a pot carried into it.  A later
		-- Lottery day may claim that pot: the second x entry moves only that retained pot, never this
		-- market's already-refunded pool.  Keeping the original V result makes rebuilds continue to
		-- recognise the source as a void day.
		if m.settled then
			local lotteryResult = m.kind == "l" and Lo and Lo.DecodeResult and Lo.DecodeResult(m.result)
			if (m.result ~= "V" and not lotteryResult) or not to or m.carryTo or m.voidCarryTo then return nil, "settled" end
			if to == e.market then return nil, "carry" end
			if st.carryCur[to] and st.carryCur[to] ~= m.cur then return nil, "cur" end
			local pot = st.carry[e.market] or 0
			if pot <= 0 then return nil, "pot" end
			st.carry[e.market], st.carryCur[e.market] = nil, nil
			st.carry[to], st.carryCur[to] = (st.carry[to] or 0) + pot, m.cur
			m.carryTo, m.carried = to, pot
			if m.result == "V" then m.voidCarryTo, m.voidCarried = to, pot end
			return true
		end
		if to then
			if m.kind == "l" then return nil, "settled" end
			if to == e.market then return nil, "carry" end
			if st.carryCur[to] and st.carryCur[to] ~= m.cur then return nil, "cur" end
			for _, b in ipairs(m.bets) do
				local a = Acc(st, b.code)
				a[slot0].escrow = a[slot0].escrow - b.s
			end
			local pot = m.pool + (st.carry[e.market] or 0)
			st.carry[e.market], st.carryCur[e.market] = nil, nil
			st.carry[to], st.carryCur[to] = (st.carry[to] or 0) + pot, m.cur
			m.settled, m.result, m.res, m.arbDue = true, e.result, { payouts = {}, guildFee = 0, arbFee = 0, carried = pot }, 0
			return true
		end
		local lotteryWire = Lo and Lo.DecodeResult and Lo.DecodeResult(e.result)
		if m.kind == "l" and e.result ~= "V" then
			if not lotteryWire or m.feeBp ~= 600 or m.arbBp ~= 0 or m.to ~= "g" then return nil, "version" end
			local tickets = {}
			for i, bet in ipairs(m.bets) do
				local id = Lo.TicketId(bet.seq, bet.i, bet.nonce)
				local animal = tonumber(bet.o)
				if not id or not animal then return nil, "ticket" end
				tickets[i] = { id = id, animal = animal, stake = bet.s, who = tostring(bet.code) }
			end
			local pot = st.carry[e.market] or 0
			local res, why = Lo.Settle({ version = Lo.SETTLEMENT_VERSION, tickets = tickets,
				draw = lotteryWire.draw, carry = pot, feeBp = 600 })
			if not res then return nil, "settle:" .. tostring(why) end
			if res.nextCarry ~= lotteryWire.nextCarry then return nil, "carry" end
			local slot = Slot(m.cur)
			for i, bet in ipairs(m.bets) do
				local a = Acc(st, bet.code)
				a[slot].escrow = a[slot].escrow - bet.s
				a[slot].bal = a[slot].bal + (res.payouts[i] or 0)
			end
			st.carry[e.market] = res.nextCarry > 0 and res.nextCarry or nil
			st.carryCur[e.market] = res.nextCarry > 0 and m.cur or nil
			st.owed = st.owed + res.fee
			res.wire, res.carried = e.result, res.nextCarry
			m.settled, m.result, m.res, m.settledAt, m.arbDue = true, e.result, res, e.t, 0
			return true
		elseif lotteryWire then
			return nil, "version"
		elseif m.kind == "l" and e.result ~= "V" then
			return nil, "version"
		end
		-- (Paid by the bet's place: a code is a number, and ArenaMath names a bettor by text only.)
		local bets = {}
		for i, b in ipairs(m.bets) do bets[i] = { o = b.o, s = b.s } end
		-- A pot carried here joins the pool as a stake nobody backs ("~"): it is money won, the fee
		-- taken on it only now; refunded (a void, nobody on the winner) it stays this market's pot.
		local pot = st.carry[e.market] or 0
		if pot > 0 then bets[#bets + 1] = { o = "~", s = pot } end
		local fee = { m.feeBp, m.arbBp, m.to == "g" and "g" or nil }
		local res, why
		if e.result == "V" then
			res, why = M.Settle(bets, M.VOID, fee)
		elseif e.result:sub(1, 1) == "P" then
			local rounds = 1
			while 2 ^ rounds < (m.nsel or 2) and rounds < M.PICK_ROUNDS do rounds = rounds + 1 end
			if #bets == 0 then res = { payouts = {}, guildFee = 0, arbFee = 0, refund = "empty" }
			else res, why = M.Pickem(bets, e.result, rounds, fee) end
		else
			local winners = {}
			for w in e.result:gmatch("[^+]+") do winners[#winners + 1] = w end
			local scratched
			if e.scratched and e.scratched ~= "" then
				scratched = {}
				for s in e.scratched:gmatch("[^+]+") do scratched[#scratched + 1] = s end
			end
			res, why = M.Settle(bets, winners, fee, scratched)
		end
		if not res then return nil, "settle:" .. tostring(why) end
		local slot = Slot(m.cur)
		for i, b in ipairs(m.bets) do
			local a = Acc(st, b.code)
			a[slot].escrow = a[slot].escrow - b.s
			a[slot].bal = a[slot].bal + (res.payouts[i] or 0)
		end
		if pot > 0 then
			local back = res.payouts[#m.bets + 1] or 0
			st.carry[e.market] = back > 0 and back or nil
			st.carryCur[e.market] = back > 0 and m.cur or nil
		end
		if m.cur == "g" then st.owed = st.owed + (res.guildFee or 0) end
		m.settled, m.result, m.res, m.settledAt = true, e.result, res, e.t
		m.arbDue = res.arbFee or 0
	elseif k == "A" then
		local m = st.m[e.market]
		if not m or not m.settled then return nil, "market" end
		if e.copper > (m.arbDue or 0) then return nil, "arbiter" end
		m.arbDue = m.arbDue - e.copper
		local a = Acc(st, e.code)
		local slot = Slot(m.cur)
		a[slot].bal = a[slot].bal + e.copper
	elseif k == "g" then
		if e.copper > st.owed then return nil, "owed" end
		st.owed = st.owed - e.copper
		st.float = st.float - (e.post or 0)
		st.post = st.post + (e.post or 0)
		st.sums.g = st.sums.g + e.copper
	elseif k == "G" then
		st.owed = st.owed + e.copper
		st.sums.g = st.sums.g - e.copper
	elseif k == "t" then
		local from, to = Acc(st, e.from), Acc(st, e.to)
		if from.g.bal < e.copper then return nil, "funds" end
		from.g.bal, to.g.bal = from.g.bal - e.copper, to.g.bal + e.copper
	elseif k == "a" then
		local a = Acc(st, e.code)
		local slot = Slot(e.cur)
		if e.sign == "-" then
			if a[slot].bal < e.copper then return nil, "funds" end
			a[slot].bal = a[slot].bal - e.copper
			if slot == "g" then st.sums.am = st.sums.am + e.copper end
		else
			a[slot].bal = a[slot].bal + e.copper
			if slot == "g" then st.sums.ap = st.sums.ap + e.copper end
		end
	elseif k == "u" then
		st.u[e.dir == "o" and "o" or "i"] = st.u[e.dir == "o" and "o" or "i"] + e.copper
	elseif k == "v" then
		local a = Acc(st, e.code)
		a.g.bal, a.g.reserved, a.g.escrow = e.g.bal, e.g.reserved, e.g.escrow
		a.p.bal, a.p.escrow = e.p.bal, e.p.escrow
	elseif k == "k" then
		-- A state that started at this snapshot (a late replica, a re-seat) takes what it could not
		-- count itself from the checkpoint; a full one keeps its own count, checked against it.
		if st.fromSnap and not st.snapTaken then
			st.owed, st.float, st.snapTaken = e.owed, e.float, true
		end
		st.checkpoint = { seq = seq, liabG = e.liabG, escG = e.escG, owed = e.owed, float = e.float, liabP = e.liabP, digest = e.digest }
	elseif k == "h" then
		-- (Opaque on the channel: its full text, when known, is applied in its place.)
	else
		return nil, "kind"
	end
	return true
end

-- Liabilities per currency: every balance, reservation and escrow.
function Wallet.Totals(st)
	local g, p, escG, n = 0, 0, 0, 0
	for _, a in pairs(st.acc) do
		g = g + a.g.bal + a.g.reserved + a.g.escrow
		escG = escG + a.g.escrow
		p = p + a.p.bal + a.p.escrow
		if a.g.bal + a.g.reserved + a.g.escrow + a.p.bal + a.p.escrow > 0 then n = n + 1 end
	end
	-- (A pot carried to a later market is owed to its winners: gold in it is a liability too.)
	local carried = 0
	for market, pot in pairs(st.carry or {}) do
		if (st.carryCur or {})[market] == "g" then g, escG, carried = g + pot, escG + pot, carried + pot else p = p + pot end
	end
	return { g = g, p = p, escG = escG, accounts = n, owed = st.owed, float = st.float, carried = carried }
end

-- An entry's text (the channel form: every code blinded with this entry's seq). full: the text
-- of an opaque entry (a stake market's), whose channel form is "h:<digest>".
local function C(code, kb, seq, i) return B36(Wallet.Blind(code, kb, seq, i)) end
function Wallet.Render(e, seq, kb)
	local k = e.k
	if k == "o" then return ("o:%s:%s"):format(B36(e.copper), e.how or "s")
	elseif k == "d" then return ("d:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), e.how or "t")
	elseif k == "q" then return ("q:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), e.nonce or "-")
	elseif k == "W" then return ("W:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), B36(e.qseq))
	elseif k == "w" then return ("w:%s:%s:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), B36(e.post or 0), e.how or "m", e.qseq and B36(e.qseq) or "-")
	elseif k == "c" then return ("c:%s"):format(B36(e.wseq))
	elseif k == "r" then return ("r:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), B36(e.wseq))
	elseif k == "n" then
		return ("n:%s:%s:%s:%s:%s:%s:%s:%s"):format(e.market, B36(e.nsel), B36(e.closes), B36(e.feeBp), B36(e.arbBp), e.kind, e.cur, e.to)
	elseif k == "B" then
		local parts = {}
		for i, b in ipairs(e.bets) do parts[i] = ("%s.%s.%s"):format(C(b.code, kb, seq, i), B36(math.floor(b.s / 100)), b.nonce) end
		return ("B%s.%s.%s:%s"):format(e.market, e.o, B36(e.t), table.concat(parts, ","))
	elseif k == "z" then return "z:" .. e.market
	elseif k == "x" then
		local s = ("x:%s:%s:%s"):format(e.market, e.result, B36(e.t or 0))
		if e.scratched and e.scratched ~= "" then s = s .. ":" .. e.scratched end
		return s
	elseif k == "A" then return ("A:%s:%s:%s"):format(C(e.code, kb, seq), B36(e.copper), e.market)
	elseif k == "g" then return ("g:%s:%s:%s"):format(B36(e.copper), B36(e.post or 0), e.ref)
	elseif k == "G" then return ("G:%s:%s"):format(B36(e.copper), e.ref)
	elseif k == "t" then return ("t:%s:%s:%s:%s"):format(C(e.from, kb, seq, 1), C(e.to, kb, seq, 2), B36(e.copper), e.ref or "-")
	elseif k == "a" then return ("a:%s:%s:%s:%s:%s:%s"):format(C(e.code, kb, seq), e.sign, B36(e.copper), e.why, e.ref or "-", e.cur or "g")
	elseif k == "u" then return ("u:%s:%s:%s"):format(B36(e.copper), e.dir, e.how or "t")
	elseif k == "v" then
		return ("v:%s:%s.%s.%s:%s.%s"):format(C(e.code, kb, seq), B36(e.g.bal), B36(e.g.reserved), B36(e.g.escrow), B36(e.p.bal), B36(e.p.escrow))
	elseif k == "k" then
		return ("k:%s:%s:%s:%s:%s:%s"):format(B36(e.liabG), B36(e.escG), B36(e.owed), B36(e.float), B36(e.liabP), e.digest)
	end
	return nil
end

-- The other way: an entry from its text (codes unblinded with kb; kept blinded without it, as
-- "c'" in code, blind = true). nil for anything malformed.
function Wallet.Parse(text, seq, kb)
	if type(text) ~= "string" or #text > 250 then return nil end
	local function Code(s, i)
		local v = N(s, 0, 2 ^ 40)
		if not v then return nil end
		if kb then return Wallet.Blind(v, kb, seq, i) end
		return v
	end
	local k = text:sub(1, 1)
	local f = {}
	if k == "B" then
		local head, list = text:match("^B([^:]+):(.+)$")
		if not head then return nil end
		local eid, idx, o, t = head:match("^([%w%-]+)%.([0-9a-z]+)%.([%w]+)%.([0-9a-z]+)$")
		if not eid or #o > 17 then return nil end
		local e = { k = "B", market = eid .. "." .. idx, eid = eid, idx = N(idx, 0), o = o, t = N(t, 0), bets = {}, blind = not kb }
		local i = 0
		for part in (list .. ","):gmatch("([^,]*),") do
			i = i + 1
			local c, s, nonce = part:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
			local code, silver = c and Code(c, i), s and N(s, 1, 21474836)
			if not code or not silver or #nonce > 8 then return nil end
			e.bets[i] = { code = code, s = silver * 100, nonce = nonce }
		end
		if i == 0 or i > Wallet.GROUP_MAX then return nil end
		return e
	end
	for part in (text .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
	if f[1] ~= k then return nil end
	local e = { k = k, blind = not kb }
	if k == "o" then
		e.copper, e.how = N(f[2], 0), f[3]
		if not e.copper or not (e.how == "s" or e.how == "t" or e.how == "m") then return nil end
	elseif k == "d" then
		e.code, e.copper, e.how = Code(f[2]), N(f[3], 1), f[4]
		if not e.code or not e.copper then return nil end
	elseif k == "q" then
		e.code, e.copper, e.nonce = Code(f[2]), N(f[3], 1), f[4]
		if not e.code or not e.copper then return nil end
	elseif k == "W" then
		e.code, e.copper, e.qseq = Code(f[2]), N(f[3], 1), N(f[4], 1)
		if not e.code or not e.copper or not e.qseq then return nil end
	elseif k == "w" then
		e.code, e.copper, e.post, e.how, e.qseq = Code(f[2]), N(f[3], 1), N(f[4], 0), f[5], f[6] ~= "-" and N(f[6], 1) or nil
		if not e.code or not e.copper or not e.post then return nil end
	elseif k == "c" then
		e.wseq = N(f[2], 1)
		if not e.wseq then return nil end
	elseif k == "r" then
		e.code, e.copper, e.wseq = Code(f[2]), N(f[3], 1), N(f[4], 1)
		if not e.code or not e.copper or not e.wseq then return nil end
	elseif k == "n" then
		e.market, e.nsel, e.closes, e.feeBp, e.arbBp, e.kind, e.cur, e.to = f[2], N(f[3], 0), N(f[4], 0), N(f[5], 0, 1000), N(f[6], 0, 1000), f[7], f[8], f[9]
		if not e.market or not MarketParts(e.market) or not e.nsel or not e.closes or not e.feeBp or not e.arbBp then return nil end
		if not (e.kind == "p" or e.kind == "s" or e.kind == "l") or not (e.cur == "g" or e.cur == "p" or e.cur == "c") or not (e.to == "a" or e.to == "g") then return nil end
		e.eid, e.idx = MarketParts(e.market)
	elseif k == "z" then
		e.market = f[2]
		if not MarketParts(e.market) then return nil end
		e.eid, e.idx = MarketParts(e.market)
	elseif k == "x" then
		e.market, e.result, e.t, e.scratched = f[2], f[3], N(f[4], 0), f[5]
		if not MarketParts(e.market) or not e.result or e.result == "" then return nil end
		local lottery = e.result:find("^L2%.%d+%.%d+%.%d+%.%d+%.%d+%.[0-9a-z]+$")
		if not (e.result:find("^[%w+]+$") or e.result:find("^C[%w%-]+%.[0-9a-z]+$") or lottery) then return nil end
		e.eid, e.idx = MarketParts(e.market)
	elseif k == "A" then
		e.code, e.copper, e.market = Code(f[2]), N(f[3], 1), f[4]
		if not e.code or not e.copper or not MarketParts(e.market) then return nil end
	elseif k == "g" then
		e.copper, e.post, e.ref = N(f[2], 1), N(f[3], 0), f[4]
		if not e.copper or not e.post or not e.ref then return nil end
	elseif k == "G" then
		e.copper, e.ref = N(f[2], 1), f[3]
		if not e.copper then return nil end
	elseif k == "t" then
		e.from, e.to, e.copper, e.ref = Code(f[2], 1), Code(f[3], 2), N(f[4], 1), f[5]
		if not e.from or not e.to or not e.copper then return nil end
	elseif k == "a" then
		e.code, e.sign, e.copper, e.why, e.ref, e.cur = Code(f[2]), f[3], N(f[4], 1), f[5], f[6], f[7]
		if not e.code or not (e.sign == "+" or e.sign == "-") or not e.copper or not (e.cur == "g" or e.cur == "p" or e.cur == "c") then return nil end
	elseif k == "u" then
		e.copper, e.dir, e.how = N(f[2], 1), f[3], f[4]
		if not e.copper or not (e.dir == "i" or e.dir == "o") then return nil end
	elseif k == "v" then
		local code = Code(f[2])
		local gb, gr, ge = (f[3] or ""):match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
		local pb, pe = (f[4] or ""):match("^([0-9a-z]+)%.([0-9a-z]+)$")
		if not code or not gb or not pb then return nil end
		e.code, e.g, e.p = code, { bal = N(gb, 0), reserved = N(gr, 0), escrow = N(ge, 0) }, { bal = N(pb, 0), escrow = N(pe, 0) }
	elseif k == "k" then
		e.liabG, e.escG, e.owed, e.float, e.liabP, e.digest = N(f[2], 0), N(f[3], 0), N(f[4], 0), N(f[5], 0), N(f[6], 0), f[7]
		if not e.liabG or not e.digest then return nil end
	elseif k == "h" then
		e.digest = f[2]
		if not e.digest or not e.digest:find("^[%w%-_]+$") then return nil end
	else
		return nil
	end
	return e
end

-- Is this entry about a stake market (opaque on the channel, the design)?
local function Opaque(st, e)
	local market = e.market
	if not market then return false end
	local m = st.m[market]
	if e.k == "n" then return e.kind == "s" end
	return m ~= nil and m.kind == "s"
end

---------------------------------------------------------------------------
-- The bank's own ledger (a role store: Arena.Store(mode).bank)
---------------------------------------------------------------------------

local duty         -- the mode on duty, or nil
local paused = false
local bankState    -- { st, ... } the working state, rebuilt from the saved balances at duty

local function Bank(mode)
	local s = Peek(mode or duty)
	return s and type(s.bank) == "table" and s.bank or nil
end
Wallet.BankStore = Bank

local function Random32()
	local parts = {}
	for i = 1, 6 do
		local Link = ns.Link
		parts[#parts + 1] = type(Link) == "table" and type(Link.EntropySample) == "function" and Link.EntropySample() or ""
		parts[#parts + 1] = tostring(math.random()) .. tostring({}) .. tostring(Now()) .. tostring(i)
	end
	return ns.Sign.SHA256(table.concat(parts, "|"))
end
local function Hex(bytes) return D().Hex(bytes) end
local function Unhex(h) return ns.Ed25519.FromHex(h) end

-- A new epoch: a fresh secret, its blinding key, the chain's start, and the float (o).
local function NewLedger(mode)
	local s = Store(mode)
	local old = type(s.bank) == "table" and s.bank or nil
	-- (The server's second in base 36: a counter would start again at 1 after a wipe, and a
	-- replica would take the new ledger for the old one.)
	local n = math.max(Now(), (old and tonumber(old.epochN) or 0) + 1)
	local secret = Random32()
	local kb = ns.Sign.SHA256(secret .. "|blind")
	local b = {
		epochN = n, epoch = (Mode(mode) == "T" and "R" or "") .. B36(n), secret = Hex(secret), kb = Hex(kb), seq = 0, mac = "0",
		head = Hex(Wallet.Genesis((Mode(mode) == "T" and "R" or "") .. B36(n))), accounts = {}, byCode = {}, entries = {}, full = {}, macs = {},
		backlog = {}, firstSeq = 1, queue = {}, sent = {}, claims = {}, orders = {}, giveBack = {}, items = {}, blocked = {}, verified = {},
		wnonces = {}, nonces = {}, meta = {}, heard = {}, told = {}, mode = Mode(mode), created = Now(),
		st = Wallet.NewState(),
	}
	s.bank = b
	return b
end

local function Code(b, key) return D().First(ns.Sign.SHA256(Unhex(b.secret) .. "|a|" .. key), 5) end
-- The bank's ledger while it is on duty (every call that writes, or whispers as the bank, needs it).
local function OnDuty() return duty and Bank() or nil end

-- Writes an entry: seals the open group first (never across another entry), renders it, extends the
-- MAC and hash chains, applies it and queues it for the channel.
local Seal, Queue, SendNow, Statement, TellAuditors -- (below)
local entrySubs = {}

local function Fire(bank, seq, e)
	for _, fn in ipairs(entrySubs) do ns.SafeCall("wallet entry", fn, bank, seq, e) end
end

local function Write(b, e, o)
	o = o or {}
	if b.group and e ~= b.group then Seal(b) end
	local st = b.st
	local seq = e.seq or (b.seq + 1)
	local ok, why = Wallet.Apply(st, e, seq)
	if not ok then return nil, why end
	b.seq = seq
	local kb = Unhex(b.kb)
	local full = Wallet.Render(e, seq, kb)
	local text = full
	if Opaque(st, e) then
		text = "h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full))
		b.full[seq] = full
	end
	b.mac = Wallet.Mac(Unhex(b.secret), b.mac, seq, Opaque(st, e) and full or text)
	b.head = Hex(Wallet.Chain(Unhex(b.head), seq, text))
	b.entries[seq] = text
	b.macs[seq] = b.mac
	b.backlog[#b.backlog + 1] = seq
	-- (Entries after the last verified snapshot are kept; the older ones go once two auditors checked it.)
	if #b.backlog > Wallet.BACKLOG_MAX then table.remove(b.backlog, 1) end
	if b.full[seq] then TellAuditors(b, "full", seq) end
	if e.k == "B" then
		for i, bet in ipairs(e.bets) do Fire(ns.me, seq, { k = "b", market = e.market, eid = e.eid, idx = e.idx, o = e.o, s = bet.s, nonce = bet.nonce, t = e.t, i = i, code = bet.code }) end
	else
		Fire(ns.me, seq, e)
	end
	if o.urgent then SendNow(b) else Queue(b) end
	ns.Arena.Changed()
	return seq
end
Wallet.Write = function(e, o) local b = OnDuty() if not b then return nil, "duty" end return Write(b, e, o) end

-- The open group of bets (one market, outcome and bank second; 11 at most): its seq is reserved
-- when it opens, so nothing else is written in between; it is sealed (rendered, chained) when
-- anything else is written, when full, and before the pump sends.
Seal = function(b)
	local g = b.group
	if not g then return end
	b.group = nil
	local st = b.st
	-- (Its bets were applied as they came: the text and the chains now.)
	local seq = g.seq
	b.seq = seq
	local kb = Unhex(b.kb)
	local full = Wallet.Render(g, seq, kb)
	local text = full
	if Opaque(st, g) then
		text = "h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full))
		b.full[seq] = full
	end
	b.mac = Wallet.Mac(Unhex(b.secret), b.mac, seq, Opaque(st, g) and full or text)
	b.head = Hex(Wallet.Chain(Unhex(b.head), seq, text))
	b.entries[seq] = text
	b.macs[seq] = b.mac
	b.backlog[#b.backlog + 1] = seq
	if b.full[seq] then TellAuditors(b, "full", seq) end
end
Wallet.Seal = function() local b = Bank() if b then Seal(b) end end

---------------------------------------------------------------------------
-- Publishing (the design, ZE): heads every minute and on change; entries on the low lane,
-- while Comm's queue has room (never keyed, never dropped: must-deliver), urgent ones at once.
---------------------------------------------------------------------------

local function HeadBody(b)
	local R0 = R()
	local state = "o"
	if paused or ns.Arena.Blocked() then state = "p"
	elseif R0 and R0.BankState(ns.me) == "c" then state = "c" end
	local tot = Wallet.Totals(b.st)
	local settings = R0 and R0.Settings() or {}
	if state == "o" and tot.g + tot.owed >= (settings.bankCap or math.huge) then state = "f" end
	if state == "o" then
		-- (Taking trades now: a depositor was called.)
		for _, q in ipairs(b.queue or {}) do if q.called then state = "d" break end end
	end
	local _, _, fp = D().MyKey()
	local flags = (ns.Arena.Persists() and "s" or "") .. ((tot.g + tot.owed) > 0 and "L" or "")
	local mapID = "-"
	local Layers = ns.Layers
	if Layers and Layers.Sharing and Layers.Sharing() and C_Map and C_Map.GetBestMapForUnit then
		local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
		if ok and tonumber(id) then mapID = B36(id) end
	end
	return ("%s~%s~%s~%s~%s~%s~%s~%s"):format(b.epoch, B36(b.seq), b.mac, b.head:sub(1, 16), state, mapID, fp or "-", flags ~= "" and flags or "-"), state
end
local function SendHead()
	local b = Bank()
	if not b or not duty then return end
	Seal(b)
	local body = HeadBody(b)
	ns.Arena.Send("ZH", duty, body, { key = "zh", evenBlocked = true })
end
Wallet.SendHead = SendHead

-- The next ZE: the backlog's oldest entries, up to ZE_ROOM bytes (a lone long one goes in pieces).
local function NextZE(b)
	if not b.backlog[1] then return nil end
	local first = b.backlog[1]
	local parts, bytes, last = {}, 0, nil
	while b.backlog[1] do
		local seq = b.backlog[1]
		if last and seq ~= last + 1 then break end
		local text = b.entries[seq]
		if not text then table.remove(b.backlog, 1) break end
		if #parts > 0 and bytes + #text + 1 > Wallet.ZE_ROOM then break end
		parts[#parts + 1] = text
		bytes = bytes + #text + 1
		last = seq
		table.remove(b.backlog, 1)
	end
	if not last then return nil end
	b.lastSent = Now()
	return ("%s~%s~%s~%s"):format(b.epoch, B36(first), table.concat(parts, ";"), b.macs[last] or "0")
end
local function Producer()
	local b = Bank()
	if not b or not duty then return nil end
	if b.group and Now() > (b.group.opened or 0) then Seal(b) end
	local body = NextZE(b)
	if not body then return nil end
	return "ZE", duty, body, { must = true }
end
Queue = function(b)
	if not duty then return end
	ns.Arena.Later("wallet ze", Producer)
end
-- Urgent: everything waiting goes now, in order (z at the lock, W before its fill, w at the send, x).
SendNow = function(b)
	if not duty then return end
	Seal(b)
	while b.backlog[1] do
		local body = NextZE(b)
		if not body then break end
		ns.Arena.Send("ZE", duty, body, { must = true, urgent = true })
	end
	SendHead()
end

-- To the auditors heard (their hello): the names behind the codes (ZN), the blinding key once an
-- epoch, the reserve (ZG), and the full text of opaque entries (ZE by whisper).
TellAuditors = function(b, what, arg)
	if not duty then return end
	local auditors = D().Auditors(duty)
	if what == "full" then
		local body = ("%s~%s~!%s~%s"):format(b.epoch, B36(arg), b.full[arg], b.macs[arg] or "0")
		for _, name in ipairs(auditors) do ns.Arena.Send("ZE", duty, body, { to = name, must = true }) end
		return
	end
	for _, name in ipairs(auditors) do
		local told = b.told[Lower(name)] or {}
		b.told[Lower(name)] = told
		if told.epoch ~= b.epoch then
			told.epoch, told.names = b.epoch, {}
			ns.Arena.Send("ZN", duty, ("%s~K~%s"):format(b.epoch, b.kb), { to = name, low = true })
		end
		local list = {}
		for key, acct in pairs(b.accounts) do
			if not told.names[key] then
				list[#list + 1] = ("%s=%s/%s"):format(B36(acct.code), acct.gk or "-", ns.FullName(acct.name))
				told.names[key] = true
			end
		end
		-- (In pieces of a message each: EP carries a long one.)
		local chunk = {}
		local function Flush()
			if chunk[1] then ns.Arena.Send("ZN", duty, b.epoch .. "~" .. table.concat(chunk, ","), { to = name, low = true }) end
			chunk = {}
		end
		for _, item in ipairs(list) do
			chunk[#chunk + 1] = item
			if #table.concat(chunk, ",") > 1800 then Flush() end
		end
		Flush()
		if what == "reserve" or not told.reserve or Now() - told.reserve >= Wallet.RESERVE_EVERY then
			told.reserve = Now()
			local tot = Wallet.Totals(b.st)
			local bal, res = 0, 0
			for _, a in pairs(b.st.acc) do bal, res = bal + a.g.bal, res + a.g.reserved end
			local gold = GetMoney and tonumber(GetMoney()) or 0
			ns.Arena.Send("ZG", duty, ("%s~%s~%s~%s~%s~%s~%s~%s~%s"):format(b.epoch, B36(b.seq), B36(gold), B36(bal), B36(tot.escG), B36(res), B36(tot.owed),
				B36(tot.accounts), B36(tot.float)), { to = name, low = true })
		end
	end
end

---------------------------------------------------------------------------
-- Accounts (the design, as amended): keyed by the lower-case name when first seen, its
-- GUID bound from a trade or a verified claim; no bet or withdrawal until it is.
---------------------------------------------------------------------------

local function Own(name)
	local T = ns.Treasury
	if type(T) == "table" and type(T.IsOwnCharacter) == "function" and T.IsOwnCharacter(name) then return true end
	return Same(name, ns.me)
end

function Wallet.Account(name, create)
	local b = Bank()
	local key = Lower(name)
	if not b or not key then return nil end
	local acct = b.accounts[key]
	if not acct and create and duty then
		local n = 0
		for _ in pairs(b.accounts) do n = n + 1 end
		if n >= Wallet.ACCOUNTS_MAX then return nil, "full" end
		acct = { key = key, name = ns.FullName(name), code = Code(b, key), created = Now() }
		b.accounts[key] = acct
		b.byCode[B36(acct.code)] = key
		-- (Its code once, by whisper; the auditors learn the name behind it.)
		ns.Arena.Send("ZC", duty, ("%s~%s"):format(b.epoch, B36(acct.code)), { to = acct.name, urgent = true })
		TellAuditors(b, "names")
	end
	if acct then Wallet.Bind(acct) end
	return acct and key or nil
end
local function Acct(key) local b = Bank() return b and b.accounts[Lower(key) or key] or nil end
Wallet.Acct = Acct

-- Binds an account's GUID from a verified claim; a verified GUID that differs freezes it and tells
-- the auditors (the design).
function Wallet.Bind(acct, guid, how)
	if type(acct) ~= "table" then acct = Acct(acct) end
	if not acct then return false end
	local gk, fp = D().Verified(acct.name)
	if guid then gk = ns.Arena.GK(guid) or gk end
	if not gk then return acct.bound == true end
	if acct.gk and acct.gk ~= gk then
		acct.frozen, acct.frozenWhy = true, "guid"
		local b = Bank()
		if b then b.flags = b.flags or {} b.flags[#b.flags + 1] = { what = "guid", name = acct.name, at = Now() } end
		return false
	end
	acct.gk, acct.bound = gk, true
	acct.fp = fp or acct.fp
	return true
end

-- 1.1.6: a player on hold while his case is decided (WatchChat.Barred "wallet": a moderator's
-- timeout until lifted) has his wallet frozen on the bank's client too: no bet, no withdrawal; a
-- deposit still lands (a debtor pays). Nothing of his balance moves or goes.
function Wallet.Held(name)
	local WC = ns.WatchChat
	return type(name) == "string" and type(WC) == "table" and not WC.missing and type(WC.Barred) == "function"
		and WC.Barred("wallet", name) ~= nil or false
end

function Wallet.Facts(key)
	local acct = Acct(key)
	if not acct then return nil end
	return { gk = acct.gk, guild = acct.guild, level = acct.level, fp = acct.fp, frozen = acct.frozen == true or Wallet.Held(acct.name),
		bound = acct.bound == true, name = acct.name, code = acct.code }
end
function Wallet.Available(key, cur)
	local acct = Acct(key)
	local b = Bank()
	if not acct or not b then return 0 end
	local a = b.st.acc[acct.code]
	if not a then return 0 end
	return a[Slot(cur or "g")].bal
end
function Wallet.Owed() local b = Bank() return b and b.st.owed or 0 end
function Wallet.Liabilities()
	local b = Bank()
	if not b then return { g = 0, p = 0 } end
	local t = Wallet.Totals(b.st)
	return { g = t.g, p = t.p, owed = t.owed, float = t.float, accounts = t.accounts }
end

local function WeekNo(t)
	local Dues = ns.Dues
	if type(Dues) == "table" and type(Dues.WeekOf) == "function" then return Dues.WeekOf(t) end
	return math.floor(t / 604800)
end

-- The weekly glory points (the design): on an account's first action of the week, while this realm
-- plays for points, 1,000 of them in the points balance only (never gold).
local function PointsGrant(b, acct)
	if duty ~= "L" or not R() or R().Currency() ~= "p" then return end
	local week = WeekNo(Now())
	if acct.week == week then return end
	acct.week = week
	Write(b, { k = "a", code = acct.code, sign = "+", copper = Wallet.POINTS_WEEK, why = "P", ref = B36(week), cur = "p" })
end
Wallet.PointsGrant = function(key) local b, acct = Bank(), Acct(key) if b and acct then PointsGrant(b, acct) end end

-- A chips rehearsal (the design): the bank credits each participant the
-- rehearsal's chips (1,000 by default, 100,000 at most) on his first action (a bet, a stake held,
-- a statement asked), once per rehearsal, and a tester's "Top up" (ZQ~T) adds 100 at most once an
-- hour. Chips only: no gold, mail or fee.
local function ChipsRun()
	if duty ~= "T" then return nil end
	local T = ns.ArenaTest
	if type(T) ~= "table" or type(T.Running) ~= "function" then return nil end
	local ok, r = pcall(T.Running)
	-- (Money "p" is a copper rehearsal: real copper, no chips.)
	if not ok or type(r) ~= "table" or r.money == "p" then return nil end
	return r
end
local function Participant(name)
	local T = ns.ArenaTest
	if type(T) ~= "table" or type(T.Participant) ~= "function" then return true end
	local ok, yes = pcall(T.Participant, name)
	return ok and yes and true or false
end
local function ChipsGrant(b, acct)
	local r = ChipsRun()
	if not r or not acct or not Participant(acct.name) then return end
	local rid = tostring(r.rid or "?")
	if acct.chipsRid == rid then return end
	acct.chipsRid = rid
	local units = math.floor((tonumber(r.chips) or Wallet.CHIPS / Wallet.UNIT.c) * Wallet.UNIT.c)
	units = math.max(0, math.min(units, Wallet.CHIPS_MAX))
	if units > 0 then Write(b, { k = "a", code = acct.code, sign = "+", copper = units, why = "J", ref = "rehearse", cur = "c" }) end
end
Wallet.ChipsGrant = function(key) local b, acct = OnDuty(), Acct(key) if b and acct then ChipsGrant(b, acct) end end
-- The top up at the bank: nil, why ("topup" outside a chips rehearsal or for a non-participant,
-- "rate" with the seconds to wait), or the entry's seq.
local function TopUp(b, acct)
	if not ChipsRun() or not Participant(acct.name) then return nil, "topup" end
	ChipsGrant(b, acct)
	local wait = (acct.topUpAt or -math.huge) + Wallet.TOPUP_EVERY - Now()
	if wait > 0 then return nil, "rate", wait end
	acct.topUpAt = Now()
	return Write(b, { k = "a", code = acct.code, sign = "+", copper = Wallet.TOPUP, why = "J", ref = "topup", cur = "c" })
end

function Wallet.Grant(key, cur, units, why, ref)
	local b, acct = OnDuty(), Acct(key)
	if not b or not acct then return nil, "account" end
	if cur == "g" then return nil, "cur" end
	units = math.floor(tonumber(units) or 0)
	if units <= 0 then return nil, "units" end
	return Write(b, { k = "a", code = acct.code, sign = "+", copper = units, why = why or "J", ref = ref or "grant", cur = cur == "c" and "c" or "p" })
end

---------------------------------------------------------------------------
-- The bank's checks on a deposit (the design): before the gold lands (its answer), and again
-- when it lands (credited then all the same, but frozen for bets and put on the give-back list).
---------------------------------------------------------------------------

local function Settings() return R() and R().Settings() or {} end

local function DepositWhy(b, key, name, copper, level, guild, how)
	local s = Settings()
	-- (Gold stays off where saved data does not survive, a copper rehearsal's too: its record of
	-- every copper moved, db.arenaCopper, would be lost at the next login. the design.)
	if not ns.Arena.Persists() and (duty == "L" or ns.ArenaMoney.CopperMode()) then return "persist" end
	if R() and R().BankState(ns.me) == "c" then return "closed" end
	if level and level < (s.minLevel or 10) then return "lvl" end
	if guild and not ns.IsFederation(guild) then return "guild" end
	local M = ns.Moderation
	if M and not M.missing and M.Hides and M.Hides(name, guild) then return "net" end
	local tot = Wallet.Totals(b.st)
	if tot.g + tot.owed + copper > (s.bankCap or math.huge) then return "full" end
	if duty == "T" and ns.ArenaMoney.CopperMode() then
		if copper > Wallet.COPPER_DEPOSIT then return "cap" end
		if tot.g + copper > Wallet.COPPER_HELD then return "full" end
	end
	local acct = b.accounts[key]
	local a = acct and b.st.acc[acct.code]
	local bal = a and (a.g.bal + a.g.reserved + a.g.escrow) or 0
	-- (A debtor may still deposit: to pay, the design. His caps here ignore the open debt.)
	local M = ns.ArenaMath
	local rec = ns.Standing.Record(name, duty)
	rec.open, rec.dispute = nil, nil
	if bal + copper > (M.BetCap(rec, "balance", s.scalePct) or 0) then return "cap" end
	local day = math.floor(Now() / 86400)
	local dep = acct and acct.dep
	local today = (type(dep) == "table" and dep.day == day) and dep.copper or 0
	if today + copper > (M.BetCap(rec, "daily", s.scalePct) or 0) then return "day" end
	return nil
end

local function Answer(b, to, what, answer, value)
	ns.Arena.Send("ZK", duty, ("%s~%s~%s~%s"):format(b.epoch, what, answer, B36(value or 0)), { to = to, urgent = true })
end

-- One deposit intent (ZD) and one new withdrawal (ZW) per sender every 10 s (the design): more is
-- dropped unanswered (an honest client waits itself; a resent withdrawal nonce still gets its
-- answer). This session's memory only.
Wallet.ASK_GAP = 10
local asked = {}
local function TooSoon(kind, key)
	local k = kind .. key
	if Now() - (asked[k] or -math.huge) < Wallet.ASK_GAP then return true end
	asked[k] = Now()
	return false
end

-- A deposit's intent (ZD): a place in the trade queue, or a yes for a mail, or why not. Never credit.
local function OnDeposit(dist, sender, mode, body)
	local b = Bank()
	if dist ~= "WHISPER" or not b or mode ~= duty then return end
	local ep, how, copper, level = ns.Arena.Fields(body, 4)
	copper, level = ns.Arena.Copper(copper), N(level, 0, 100)
	if not copper or copper <= 0 or not (how == "t" or how == "m") then return end
	if ep ~= b.epoch then return Answer(b, sender, "D", "ep", 0) end
	local key = Lower(sender)
	if TooSoon("D", key) then return end
	b.heard[key] = Now()
	local why = DepositWhy(b, key, sender, copper, level, nil, how)
	local acct = b.accounts[key]
	if acct then acct.level = level or acct.level end
	Wallet.Spoke(b, key)
	b.claimsOf = b.claimsOf or {}
	b.claimsOf[key] = { level = level, at = Now() }
	if why then
		ns.Fire("WALLET_REFUSED", ns.me, why)
		return Answer(b, sender, "D", why, copper)
	end
	if how == "m" then return Answer(b, sender, "D", "ok", copper) end
	for i, q in ipairs(b.queue) do
		if q.key == key then return Answer(b, sender, "D", "q", i) end
	end
	b.queue[#b.queue + 1] = { key = key, name = ns.FullName(sender), copper = copper, at = Now() }
	Answer(b, sender, "D", "q", #b.queue)
	ns.Arena.Changed()
end
ns.Comm.Handle("ZD", ns.Arena.Handle("ZD", OnDeposit))

-- The operator's "Call next": the next depositor in the queue is told the bank is ready; he opens
-- the trade himself (his click). One who does not trade within a minute goes to the back once.
function Wallet.CallNext()
	local b = OnDuty()
	if not b then return nil, "duty" end
	for _, q in ipairs(b.queue) do
		if not q.called then
			q.called, q.calledAt = true, Now()
			Answer(b, q.name, "D", "go", q.copper)
			SendHead()
			ns.Arena.Changed()
			return q
		end
	end
	return nil, "empty"
end
local function QueueTick(b)
	for i = #b.queue, 1, -1 do
		local q = b.queue[i]
		if q.called and Now() - q.calledAt > Wallet.CALL_WAIT then
			table.remove(b.queue, i)
			if not q.moved then
				q.moved, q.called, q.calledAt = true, nil, nil
				b.queue[#b.queue + 1] = q
			end
		end
	end
end

---------------------------------------------------------------------------
-- The bank's flows (ArenaMoney's watcher): trades and mails as they land
---------------------------------------------------------------------------

local function Credited(b, acct, copper)
	local key = acct.key
	local day = math.floor(Now() / 86400)
	acct.dep = (type(acct.dep) == "table" and acct.dep.day == day) and acct.dep or { day = day, copper = 0 }
	acct.dep.copper = acct.dep.copper + copper
	Answer(b, acct.name, "D", "c", copper)
	Statement(b, acct, true)
	ns.Fire("WALLET_CREDITED", ns.me, copper)
end

local function Deposit(b, name, copper, how, r)
	local key = Lower(name)
	local acct = b.accounts[Wallet.Account(name, true) or key]
	if not acct then return end
	if r and r.guid then Wallet.Bind(acct, r.guid, "unit") end
	if r and r.level then acct.level = r.level end
	if r and r.guild then acct.guild = r.guild end
	local claim = b.claimsOf and b.claimsOf[key]
	local level = r and r.level or (claim and claim.level)
	local why = DepositWhy(b, key, acct.name, copper, level, r and r.guild or nil, how)
	-- A mail from someone whose client never spoke: his gold, frozen for bets until it does.
	if not r and not claim then why = why or "unknown" end
	Write(b, { k = "d", code = acct.code, copper = copper, how = how })
	-- (Out of the trade queue: served.)
	for i, q in ipairs(b.queue) do if q.key == key then table.remove(b.queue, i) break end end
	if why and why ~= "unknown" then
		acct.frozen, acct.frozenWhy = true, why
		b.giveBack[#b.giveBack + 1] = { key = key, name = acct.name, copper = copper, why = why, at = Now() }
	elseif why == "unknown" then
		acct.frozen, acct.frozenWhy = true, "unknown"
	end
	Credited(b, acct, copper)
end

-- A holder's client spoke to the bank (a deposit's intent, a withdrawal, a statement asked): a
-- mail deposit it froze because nothing had come from his addon is his to bet with now.
function Wallet.Spoke(b, key)
	local acct = b and b.accounts[key]
	if acct and acct.frozen and acct.frozenWhy == "unknown" then acct.frozen, acct.frozenWhy = nil, nil end
end

-- The subject of a withdrawal: "Arena wallet <code> <qseq>".
local function WdSubject(b, acct, qseq) return ns.ArenaMoney.Subject("wallet", B36(acct.code) .. " " .. B36(qseq), duty == "T") end

local function OnBankFlow(r)
	local b = Bank()
	if not b or not duty then return end
	local Mn = ns.ArenaMoney
	local out, copper = Mn.Net(r)
	local mode = duty
	if r.kind == "trade" then
		if (r.items and r.items.got or 0) > 0 then
			b.items[#b.items + 1] = { name = r.partner, n = r.items.got, at = Now() }
			ns.Print(L.WALLET_ITEMS_BACK:format(ns.DisplayName(r.partner) or "?"))
		end
		if copper <= 0 then return end
		if Own(r.partner) then
			if out then Write(b, { k = "u", copper = copper, dir = "o", how = "t" }) else Write(b, { k = "o", copper = copper, how = "t" }) end
			return
		end
		if not out then return Deposit(b, r.partner, copper, "t", r) end
		-- Gold out by trade: the withdrawal the operator paid by trade, else unmatched.
		local pay = b.payTrade
		local acct = b.accounts[Lower(r.partner)]
		if pay and acct and pay.key == acct.key then
			b.payTrade = nil
			Write(b, { k = "w", code = acct.code, copper = copper, post = 0, how = "t", qseq = pay.qseq }, { urgent = true })
			Statement(b, acct, true)
			return
		end
		Write(b, { k = "u", copper = copper, dir = "o", how = "t" })
	elseif r.kind == "mailTaken" then
		if Own(r.partner) then return Write(b, { k = "o", copper = copper, how = "m" }) end
		return Deposit(b, r.partner, copper, "m", nil)
	elseif r.kind == "mailReturned" then
		-- Matched by subject against the bank's own sent mails (the design): never a deposit.
		local kind, ref = Mn.ReadSubject(r.subject)
		for i = #b.sent, 1, -1 do
			local s = b.sent[i]
			if s.subject == r.subject and not s.back then
				s.back = Now()
				if s.kind == "w" then
					local acct = b.accounts[s.key]
					Write(b, { k = "r", code = acct.code, copper = copper, wseq = s.wseq })
					Statement(b, acct, true)
				elseif s.kind == "g" then
					Write(b, { k = "G", copper = s.copper, ref = s.ref })
					local o = D().Find(s.obligation or "")
					if o then D().Returned(o.id) end
				else
					Write(b, { k = "u", copper = copper, dir = "i", how = "m" })
				end
				return
			end
		end
		Write(b, { k = "u", copper = copper, dir = "i", how = "m" })
	elseif r.kind == "mailSent" then
		local pay, fee = b.paying, b.payingFee
		if pay and Same(pay.to, r.partner) and pay.subject == r.subject then
			b.paying = nil
			local acct = b.accounts[pay.key]
			local post = Mn.Postage()
			local seq = Write(b, { k = "w", code = acct.code, copper = copper + post, post = post, how = "m", qseq = pay.qseq }, { urgent = true })
			b.sent[#b.sent + 1] = { kind = "w", to = pay.to, subject = r.subject, copper = copper, key = pay.key, qseq = pay.qseq, wseq = seq, at = Now() }
			Statement(b, acct, true)
			TellAuditors(b, "reserve")
			ns.Fire("WALLET_PAID", ns.me, copper)
			return
		end
		if fee and Same(fee.to, r.partner) and fee.subject == r.subject then
			b.payingFee = nil
			local post = Mn.Postage()
			Write(b, { k = "g", copper = copper, post = post, ref = fee.ref }, { urgent = true })
			b.sent[#b.sent + 1] = { kind = "g", to = fee.to, subject = r.subject, copper = copper, ref = fee.ref, obligation = fee.obligation, at = Now() }
			b.feeRef = nil
			local o = D().Find(fee.obligation or "")
			if o then o.copper = copper end
			TellAuditors(b, "reserve")
			return
		end
		Write(b, { k = "u", copper = copper, dir = "o", how = "m" })
	end
end
ns.ArenaMoney.Subscribe(function(r) OnBankFlow(r) end)

---------------------------------------------------------------------------
-- Withdrawals (the design, as amended): q reserves; "Pay next" writes the W intent and sends
-- it before it fills the mail; w at the send; c when the player took it; r when it came back.
---------------------------------------------------------------------------

local function OnWithdraw(dist, sender, mode, body)
	local b = Bank()
	if dist ~= "WHISPER" or not b or mode ~= duty then return end
	local ep, nonce, amount, how = ns.Arena.Fields(body, 4)
	if ep ~= b.epoch then return Answer(b, sender, "W", "ep", 0) end
	if type(nonce) ~= "string" or not nonce:find("^[0-9a-z]+$") or #nonce > 8 then return end
	local key = Lower(sender)
	b.heard[key] = Now()
	local acct = b.accounts[key]
	if not acct then return Answer(b, sender, "W", "a", 0) end
	Wallet.Spoke(b, key)
	local done = b.wnonces[nonce]
	if done and done.key == key then return Answer(b, sender, "W", "q", done.qseq) end
	if TooSoon("W", key) then return end
	if Wallet.Held(sender) then return Answer(b, sender, "W", "frozen", 0) end -- (1.1.6: on hold)
	-- The server-stamped sender is the account; a gold withdrawal only, once its GUID is bound.
	if not Wallet.Bind(acct) then return Answer(b, sender, "W", "b", 0) end
	local a = b.st.acc[acct.code]
	local bal = a and a.g.bal or 0
	local copper = amount == "all" and bal or ns.Arena.Copper(amount)
	local post = ns.ArenaMoney.Postage()
	if not copper or copper <= 0 or copper > bal then return Answer(b, sender, "W", "f", bal) end
	if copper < Wallet.MIN_WITHDRAW and not (amount == "all" and copper >= 3 * post) then return Answer(b, sender, "W", "m", Wallet.MIN_WITHDRAW) end
	local qseq = Write(b, { k = "q", code = acct.code, copper = copper, nonce = nonce })
	if not qseq then return Answer(b, sender, "W", "f", bal) end
	Seal(b)
	b.wnonces[nonce] = { key = key, qseq = qseq }
	b.wq = b.wq or {}
	b.wq[#b.wq + 1] = { code = acct.code, qseq = qseq, copper = copper, at = Now(), how = how == "t" and "t" or "m" }
	Answer(b, sender, "W", "q", qseq)
	Statement(b, acct, true)
	ns.Arena.Changed()
end
ns.Comm.Handle("ZW", ns.Arena.Handle("ZW", OnWithdraw))

-- The queue's requests not yet sent, oldest first (each with its account's key once known: a
-- replayed request's account is known again when its holder next speaks, the design).
local function Waiting(b)
	local out = {}
	for _, w in ipairs(b.wq or {}) do
		local rec = b.st.wd[w.qseq]
		w.key = b.byCode[B36(w.code)]
		if rec and rec.state ~= "w" then out[#out + 1] = w end
	end
	return out
end

-- The name a payout goes to now: the GUID's current name (a rename keeps the account), else its own.
local function PayName(acct)
	local guid = acct.gk and ns.Arena.GuidOf(acct.gk)
	local now = guid and D().InfoName(guid)
	return now or acct.name
end

-- "Pay next", at a mailbox: the W intent first (urgent), then the mail filled; the operator presses
-- Send. A rehearsal's chips move no gold: marked sent at once.
function Wallet.PayNext()
	local b = OnDuty()
	if not b then return nil, "duty" end
	if ns.ArenaMoney.TakePending() then return nil, "wait" end
	for _, w in ipairs(Waiting(b)) do
		local acct = w.key and b.accounts[w.key]
		if acct and not b.blocked[B36(w.code)] then
			local rec = b.st.wd[w.qseq]
			local copper = rec.copper - (rec.sent or 0)
			if rec.state ~= "W" then Write(b, { k = "W", code = acct.code, copper = copper, qseq = w.qseq }, { urgent = true }) end
			local to = PayName(acct)
			local subject = WdSubject(b, acct, w.qseq)
			b.paying = { key = w.key, qseq = w.qseq, to = to, subject = subject }
			local post = ns.ArenaMoney.Postage()
			local how = ns.ArenaMoney.FillMail(to, subject, copper - post)
			return { name = to, copper = copper, qseq = w.qseq, subject = subject, fill = how }
		end
	end
	return nil, "empty"
end
-- "Pay by trade", with the player's trade open: the gold filled; recorded when the trade completes.
function Wallet.PayTrade(qseq)
	local b = OnDuty()
	if not b then return nil, "duty" end
	for _, w in ipairs(Waiting(b)) do
		if w.qseq == qseq and w.key and not b.blocked[B36(w.code)] then
			local acct = b.accounts[w.key]
			local rec = b.st.wd[qseq]
			if rec.state ~= "W" then Write(b, { k = "W", code = acct.code, copper = rec.copper, qseq = qseq }, { urgent = true }) end
			b.payTrade = { key = w.key, qseq = qseq }
			return { name = acct.name, copper = rec.copper, fill = ns.ArenaMoney.FillTrade(rec.copper, acct.name) }
		end
	end
	return nil, "request"
end
-- After a crash: a W with no w blocks that account's payouts until the operator says whether the
-- mail went (sent: w written now; not sent: it can be paid again).
function Wallet.Reconcile(qseq, sent)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local rec = b.st.wd[qseq]
	if not rec or rec.state ~= "W" then return nil, "intent" end
	local key = b.byCode[B36(rec.code)]
	if sent then
		local post = ns.ArenaMoney.Postage()
		local seq = Write(b, { k = "w", code = rec.code, copper = rec.copper - (rec.sent or 0), post = post, how = "m", qseq = qseq }, { urgent = true })
		b.sent[#b.sent + 1] = { kind = "w", key = key, qseq = qseq, wseq = seq, copper = rec.copper - post, at = Now(), subject = key and WdSubject(b, b.accounts[key], qseq) }
	else
		rec.state = "q"
	end
	b.blocked[B36(rec.code)] = nil
	ns.Arena.Changed()
	return true
end

---------------------------------------------------------------------------
-- Fees (the design): the guild's share mailed to the fee receiver, exactly what is owed (the
-- postage on top, from the float), with its ref; cleared by the receiver's ZF for that ref.
---------------------------------------------------------------------------

function Wallet.ReceiverUpdated()
	local s = Store("L")
	local R0 = R()
	if not R0 or not R0.FeeReceiver() then return false end
	for name, t in pairs(type(s.feeHello) == "table" and s.feeHello or {}) do
		if Now() - t <= Wallet.RECEIVER_FRESH and R0.IsFeeReceiver(name) then return true end
	end
	return false
end

-- The bank's fee obligation follows what it owes the guild (created at the first settled fee,
-- growing until it is mailed): due 72 h after that settlement.
local function FeeAccrual(b)
	if duty ~= "L" then return end
	local owed = b.st.owed
	if owed <= 0 then return end
	local Db = D()
	local o = b.feeRef and Db.Find(b.feeRef)
	if o and (o.state == "open" or o.state == "l" or o.state == "o") then
		o.copper = owed
		return
	end
	local ref = "B" .. b.epoch .. "-" .. B36(b.seq)
	local ob = Db.Owe({ kind = "fee", copper = owed, ref = ref, due = Now() + 72 * 3600, mode = "L" })
	if ob then b.feeRef = ob.id end
end

function Wallet.PayGuild()
	local b = OnDuty()
	if not b then return nil, "duty" end
	local owed = b.st.owed
	if owed <= 0 then return nil, "nothing" end
	local to = R() and R().FeeReceiver()
	if not to then ns.Print(L.WALLET_NO_RECEIVER) return nil, "receiver" end
	if duty == "L" and not Wallet.ReceiverUpdated() then ns.Print(L.WALLET_RECEIVER_OLD) return nil, "updated" end
	if ns.ArenaMoney.TakePending() then return nil, "wait" end
	FeeAccrual(b)
	local o = b.feeRef and D().Find(b.feeRef)
	local ref = o and o.ref or ("B" .. b.epoch .. "-" .. B36(b.seq))
	local subject = ns.ArenaMoney.Subject("fee", ref, duty == "T")
	b.payingFee = { to = to, subject = subject, ref = ref, copper = owed, obligation = o and o.id }
	return { to = to, copper = owed, ref = ref, subject = subject, fill = ns.ArenaMoney.FillMail(to, subject, owed) }
end

---------------------------------------------------------------------------
-- Markets on the bank (the ledger's side; MarketBank, the markets, checks the slips)
---------------------------------------------------------------------------

local function MarketOf(b, eid, idx)
	local market = Wallet.MarketId(eid, idx)
	return market, b.st.m[market]
end

function Wallet.Register(eid, idx, spec)
	local b = OnDuty()
	if not b then return nil, "duty" end
	if type(eid) ~= "string" or not eid:find("^[%w%-]+$") or #eid > 16 then return nil, "eid" end
	spec = type(spec) == "table" and spec or {}
	local market, m = MarketOf(b, eid, idx)
	if m then return nil, "known" end
	if duty == "L" and R() and R().BankState(ns.me) == "c" then return nil, "closing" end
	local cur = spec.cur or (duty == "T" and "c" or (R() and R().Currency()) or "g")
	if cur == "g" and duty == "T" and not ns.ArenaMoney.CopperMode() then cur = "c" end
	-- Gold only where someone receives the guild's fee (the design): with none, no gold bets.
	if cur == "g" and duty == "L" and not (R() and R().FeeReceiver()) then return nil, "receiver" end
	local s = Settings()
	local feeBp, arbBp = tonumber(spec.feeBp) or s.feeBp or 600, tonumber(spec.arbBp) or s.arbBp or 200
	local lottery = spec.kind == "l"
	-- Lottery ledger ids and their versioned kind travel together.  Reject an old caller that
	-- registers an L market through the generic pool path before it can be written ambiguously.
	if (eid:sub(1, 1) == "L") ~= lottery then return nil, "version" end
	if lottery then feeBp, arbBp = 600, 0 end
	-- Points and chips pay no fee (the design): there is no gold to give the guild.
	if cur ~= "g" then feeBp, arbBp = 0, 0 end
	if lottery and (eid:sub(1, 1) ~= "L" or cur ~= "g" or feeBp ~= 600 or arbBp ~= 0
		or math.floor(tonumber(spec.nsel) or 0) ~= 25) then return nil, "version" end
	arbBp = math.min(arbBp, feeBp)
	-- The arbiter is paid his part only when there is one to credit; the King holds no gold (the
	-- design): with none, or the King, all of the fee is the guild's (else it would be lost).
	local arbiter = spec.arbiter and ns.FullName(spec.arbiter) or nil
	-- The market's arbiter is never one of the bank's own characters, nor of its key (the design).
	if arbiter then
		local _, _, myFp = D().MyKey()
		local _, fp = D().Verified(arbiter)
		if Own(arbiter) or (fp and myFp and fp == myFp) then return nil, "arbiter" end
	end
	-- A stake market (the design: the King's fights, a Bones game from the wallets): two
	-- named parties, each staking exactly his stake on himself.
	local parties, stakes
	if spec.kind == "s" then
		local P, S = type(spec.parties) == "table" and spec.parties or {}, type(spec.stakes) == "table" and spec.stakes or {}
		local a, bn = type(P.A) == "string" and ns.FullName(P.A) or nil, type(P.B) == "string" and ns.FullName(P.B) or nil
		local sa, sb = math.floor(tonumber(S.A) or 0), math.floor(tonumber(S.B) or 0)
		if not a or not bn or Same(a, bn) or sa <= 0 or sb <= 0 or sa % 100 ~= 0 or sb % 100 ~= 0 then return nil, "parties" end
		parties, stakes = { A = a, B = bn }, { A = sa, B = sb }
	end
	local to = (spec.to == "g" or not arbiter or (R() and R().IsKing(arbiter))) and "g" or "a"
	local ledgerKind = lottery and "l" or (spec.kind == "s" and "s" or "p")
	local seq = Write(b, { k = "n", market = market, eid = eid, idx = idx, nsel = spec.kind == "s" and 2 or math.max(0, math.floor(tonumber(spec.nsel) or 2)),
		closes = math.floor(tonumber(spec.closes or spec.lockAt) or 0), feeBp = feeBp, arbBp = arbBp, kind = ledgerKind, cur = cur, to = to })
	if seq then
		-- (Kept on the bank's own store, not in the ledger: whether the event is public and what it
		-- is, from the spec or the events registry, for the Oracle, which counts public markets only.)
		local ev = ns.Arena.EventOf and ns.Arena.EventOf(eid) or nil
		local public = spec.public
		if public == nil and ev then public = ev.public end
		b.meta[market] = { arbiter = arbiter, parties = parties, stakes = stakes, rounds = spec.rounds,
			public = public == true, event = spec.event or (ev and ev.kind) or (eid:sub(1, 1) == "L" and "lottery" or nil) }
	end
	return seq
end

function Wallet.Hold(key, copper, ref)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local acct = Acct(key)
	if not acct or type(ref) ~= "table" then return nil, "account" end
	local market, m = MarketOf(b, ref.eid, ref.idx)
	if not m then return nil, "market" end
	local o = tostring(ref.o)
	local nonce = tostring(ref.nonce or "")
	copper = math.floor(tonumber(copper) or 0)
	-- The same nonce again: its entry, whatever happened since; another tuple under it: "U".
	local known = b.nonces[nonce]
	if known then
		if known.key == acct.key and known.market == market and known.o == o and known.s == copper then return known.seq, known.i end
		return nil, "U"
	end
	if not o:find("^[%w]+$") or #o > 17 or not nonce:find("^[0-9a-z]+$") or #nonce > 8 then return nil, "shape" end
	if m.closed or m.settled then return nil, "closed" end
	-- A closing bank takes no bet (the design): withdrawals only.
	if duty == "L" and R() and R().BankState(ns.me) == "c" then return nil, "closing" end
	if m.closes > 0 and Now() >= m.closes then return nil, "late" end
	if copper <= 0 or copper % 100 ~= 0 then return nil, "silver" end
	if acct.frozen or Wallet.Held(acct.name) then return nil, "frozen" end
	if m.cur == "g" and not Wallet.Bind(acct) then return nil, "bound" end
	if m.kind == "s" then
		-- (Only its parties, each exactly his stake on himself, once: the design.)
		local meta = b.meta[market] or {}
		local party = meta.parties and meta.parties[o]
		if not party or not Same(party, acct.name) then return nil, "party" end
		if not meta.stakes or copper ~= meta.stakes[o] then return nil, "stake" end
		for _, bet in ipairs(m.bets) do if bet.o == o then return nil, "held" end end
	end
	PointsGrant(b, acct)
	if m.cur == "c" then ChipsGrant(b, acct) end
	local a = b.st.acc[acct.code]
	local slot = Slot(m.cur)
	if not a or a[slot].bal < copper then return nil, "funds" end
	local t = Now()
	local g = b.group
	if not (g and g.market == market and g.o == o and g.t == t and #g.bets < Wallet.GROUP_MAX and not Opaque(b.st, g)) then
		Seal(b)
		g = { k = "B", market = market, eid = ref.eid, idx = ref.idx, o = o, t = t, bets = {}, seq = b.seq + 1, opened = t }
		b.group = g
	end
	local bet = { code = acct.code, s = copper, nonce = nonce }
	local one = { k = "B", market = market, o = o, t = t, bets = { bet } }
	local ok, why = Wallet.Apply(b.st, one, g.seq)
	if not ok then
		if #g.bets == 0 then b.group = nil end
		return nil, why
	end
	-- (Apply numbered it as place 1 of its own; its place is in the group.)
	local placed = m.bets[#m.bets]
	g.bets[#g.bets + 1] = bet
	placed.i = #g.bets
	local i = #g.bets
	b.nonces[nonce] = { key = acct.key, market = market, o = o, s = copper, seq = g.seq, i = i }
	Fire(ns.me, g.seq, { k = "b", market = market, eid = ref.eid, idx = ref.idx, o = o, s = copper, nonce = nonce, t = t, i = i, code = acct.code })
	if #g.bets >= Wallet.GROUP_MAX or Opaque(b.st, g) then Seal(b) end
	b.heard[acct.key] = Now()
	Queue(b)
	Statement(b, acct)
	ns.Arena.Changed()
	return g.seq, i
end

function Wallet.Close(eid, idx)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local market, m = MarketOf(b, eid, idx)
	if not m then return nil, "market" end
	if m.closed then return true end
	return Write(b, { k = "z", market = market }, { urgent = true })
end

-- Settles from the ledger's own bets (ArenaMath): each winner credited, the guild's fee owed, the
-- arbiter's share credited to his wallet at this bank (or the guild's, "to g").
function Wallet.Settle(eid, idx, winners, scratched)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local market, m = MarketOf(b, eid, idx)
	if not m then return nil, "market" end
	if m.settled then return m.res end
	if not m.closed then Write(b, { k = "z", market = market }) end
	local result
	if winners == "V" or winners == nil then result = "V"
	elseif type(winners) == "string" and winners:sub(1, 1) == "P" then result = winners
	elseif type(winners) == "table" then
		local list = {}
		for k, v in pairs(winners) do list[#list + 1] = tostring(v == true and k or v) end
		table.sort(list)
		result = table.concat(list, "+")
	else result = tostring(winners) end
	local sc
	if type(scratched) == "table" and next(scratched) then
		local list = {}
		for k, v in pairs(scratched) do list[#list + 1] = tostring(v == true and k or v) end
		table.sort(list)
		sc = table.concat(list, "+")
	end
	local seq, why = Write(b, { k = "x", market = market, result = result, t = Now(), scratched = sc }, { urgent = true })
	if not seq then return nil, why end
	local res = m.res
	-- The arbiter's share: his own credit, blinded (the design: never next to its event in the clear).
	if (m.arbDue or 0) > 0 then
		local meta = b.meta[market] or {}
		local key = meta.arbiter and Wallet.Account(meta.arbiter, true)
		local acct = key and b.accounts[key]
		if acct then
			Write(b, { k = "A", code = acct.code, copper = m.arbDue, market = market }, { urgent = true })
			Statement(b, acct)
		end
	end
	-- Standing: a settled wallet stake of enough volume earns a point (on this bank's record).
	if duty == "L" and m.cur == "g" and result ~= "V" then
		local by = {}
		for _, bet in ipairs(m.bets) do by[bet.code] = (by[bet.code] or 0) + bet.s end
		for code, s in pairs(by) do
			local key = b.byCode[B36(code)]
			local acct = key and b.accounts[key]
			if acct then ns.Standing.Earn(acct.name, "wallet", nil, s, "L") end
		end
	end
	for _, bet in ipairs(m.bets) do
		local key = b.byCode[B36(bet.code)]
		if key then Statement(b, b.accounts[key]) end
	end
	FeeAccrual(b)
	return res
end

-- Version-2 Lottery settlement. The wire carries all five animal positions and the exact retained
-- carry; Apply recomputes the same pure contract before moving a copper, so replicas reject a
-- mixed-version or altered result instead of interpreting the five positions as equal winners.
function Wallet.SettleLottery(eid, idx, draw)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local market, m = MarketOf(b, eid, idx)
	if not m then return nil, "market" end
	if m.kind ~= "l" then return nil, "version" end
	if m.settled then return m.res end
	local Lo = ns.Lottery
	if not (Lo and Lo.Settle and Lo.EncodeResult) then return nil, "version" end
	local tickets = {}
	for i, bet in ipairs(m.bets) do
		local id = Lo.TicketId(bet.seq, bet.i, bet.nonce)
		local animal = tonumber(bet.o)
		if not id or not animal then return nil, "ticket" end
		tickets[i] = { id = id, animal = animal, stake = bet.s, who = tostring(bet.code) }
	end
	local preview, why = Lo.Settle({ version = Lo.SETTLEMENT_VERSION, tickets = tickets, draw = draw,
		carry = (b.st.carry or {})[market] or 0, feeBp = 600 })
	if not preview then return nil, why end
	local result = Lo.EncodeResult(draw, preview.nextCarry)
	if not result then return nil, "result" end
	if not m.closed then Write(b, { k = "z", market = market }) end
	local seq
	seq, why = Write(b, { k = "x", market = market, result = result, t = Now() }, { urgent = true })
	if not seq then return nil, why end
	local res = m.res
	if not res or res.wire ~= result then return nil, "apply" end
	if duty == "L" and m.cur == "g" then
		local by = {}
		for _, bet in ipairs(m.bets) do by[bet.code] = (by[bet.code] or 0) + bet.s end
		for code, s in pairs(by) do
			local key = b.byCode[B36(code)]
			local acct = key and b.accounts[key]
			if acct then ns.Standing.Earn(acct.name, "wallet", nil, s, "L") end
		end
	end
	for _, bet in ipairs(m.bets) do
		local key = b.byCode[B36(bet.code)]
		if key then Statement(b, b.accounts[key]) end
	end
	FeeAccrual(b)
	return res
end
function Wallet.Void(eid, idx, code)
	return Wallet.Settle(eid, idx, "V")
end

-- Move retained Lottery carry to a later day. A v2 day is settled first, so this moves only its
-- unclaimed profit tranches; refunds, paid profit and fee can never enter the later pot. A void day
-- still moves only the pot it had carried in. Returns the exact pot moved.
function Wallet.Carry(eid, idx, toEid, toIdx)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local market, m = MarketOf(b, eid, idx)
	if not m then return nil, "market" end
	if type(toEid) ~= "string" or not toEid:find("^[%w%-]+$") or #toEid > 16 then return nil, "to" end
	local to = Wallet.MarketId(toEid, toIdx)
	if to == market then return nil, "carry" end
	if m.settled then
		local lottery = m.kind == "l" and ns.Lottery and ns.Lottery.DecodeResult and ns.Lottery.DecodeResult(m.result)
		if m.result ~= "V" and not lottery then return nil, "settled" end
		local carriedTo, carried = m.carryTo or m.voidCarryTo, m.carried or m.voidCarried
		if carriedTo then
			if carriedTo == to then return carried or 0 end
			return nil, "settled"
		end
		-- A settled day with no retained pot has nothing to move. In particular, none of its
		-- refunded stakes or paid profit may be counted again as a rollover.
		if ((b.st.carry or {})[market] or 0) <= 0 then return 0 end
	end
	if not m.closed then Write(b, { k = "z", market = market }) end
	local seq, why = Write(b, { k = "x", market = market, result = "C" .. to, t = Now() }, { urgent = true })
	if not seq then return nil, why end
	return m.settled and (m.carried or m.voidCarried or 0) or (m.res and m.res.carried or 0)
end
-- The acknowledgement lag (the design): the bets waiting for the channel at 150 a minute, in seconds
-- (Markets' BO carries it: how long a bettor waits before sending the same nonce again).
Wallet.RATE = 150
function Wallet.Lag()
	local b = Bank()
	if not b or not duty then return 0 end
	local n = b.group and #b.group.bets or 0
	for _, seq in ipairs(b.backlog) do
		local text = b.entries[seq] or ""
		if text:sub(1, 1) == "B" then
			local _, commas = text:gsub(",", "")
			n = n + commas + 1
		else
			n = n + 1
		end
	end
	return math.ceil(n * 60 / Wallet.RATE)
end

-- The Oracle's inputs (the design, the fights part's IO): each account's net profit, total staked and
-- markets over the public pool markets of one currency (the realm's by default) that settled in
-- [from, to), from the ledger. { { name, profit, staked, markets, first }, ... }, by name. Never a
-- private event's market (friends could farm it), a void or refunded one, a stake market (the
-- parties' own stakes), or the Lottery's (luck, not a prediction).
function Wallet.Oracle(from, to, cur)
	local b = Bank()
	if not b or b.mode ~= "L" then return {} end
	cur = cur or (R() and R().Currency()) or "g"
	local by = {}
	for market, m in pairs(b.st.m) do
		local at = m.settledAt or 0
		local meta = b.meta and b.meta[market] or {}
		if m.settled and m.kind == "p" and m.cur == cur and m.result ~= "V" and m.res and at >= (from or 0) and at < (to or math.huge)
			and m.res.refund == nil and meta.public == true and meta.event ~= "lottery" and not market:find("^L") then
			local seen = {}
			for i, bet in ipairs(m.bets) do
				local r = by[bet.code] or { profit = 0, staked = 0, markets = 0, first = bet.t or at }
				by[bet.code] = r
				r.staked = r.staked + bet.s
				r.profit = r.profit + (m.res.payouts[i] or 0) - bet.s
				if (bet.t or at) < r.first then r.first = bet.t or at end
				if not seen[bet.code] then seen[bet.code] = true r.markets = r.markets + 1 end
			end
		end
	end
	local out = {}
	for code, r in pairs(by) do
		local key = b.byCode[B36(code)]
		local acct = key and b.accounts[key]
		if acct then out[#out + 1] = { name = acct.name, profit = r.profit, staked = r.staked, markets = r.markets, first = r.first } end
	end
	table.sort(out, function(x, y) return x.name < y.name end)
	return out
end

-- The pot a market holds from earlier ones (carried in), in its units.
function Wallet.Pot(eid, idx)
	local b = Bank()
	if not b then return 0 end
	return (b.st.carry or {})[Wallet.MarketId(eid, idx)] or 0
end

function Wallet.Market(eid, idx)
	local b = Bank()
	if not b then return nil end
	local market, m = MarketOf(b, eid, idx)
	if not m then return nil end
	return { market = market, nsel = m.nsel, closes = m.closes, feeBp = m.feeBp, arbBp = m.arbBp, kind = m.kind, cur = m.cur, to = m.to,
		closed = m.closed == true, settled = m.settled == true, result = m.result, pool = m.pool, pools = m.pools, res = m.res }
end
function Wallet.Bets(eid, idx)
	local b = Bank()
	if not b then return nil end
	local _, m = MarketOf(b, eid, idx)
	if not m then return nil end
	local out = {}
	for _, bet in ipairs(m.bets) do
		out[#out + 1] = { acct = b.byCode[B36(bet.code)], o = bet.o, s = bet.s, nonce = bet.nonce, seq = bet.seq, i = bet.i, t = bet.t }
	end
	return out
end

---------------------------------------------------------------------------
-- Statements (ZS): after a change, to holders heard lately, on the low lane; with the standing
-- token the bank signs for that account's key (the design).
---------------------------------------------------------------------------

Statement = function(b, acct, force)
	if not acct or not duty then return end
	local heard = b.heard[acct.key]
	if not force and (not heard or Now() - heard > Wallet.HOLDER_FRESH) then return end
	local a = b.st.acc[acct.code] or { g = { bal = 0, reserved = 0, escrow = 0 }, p = { bal = 0, escrow = 0 } }
	local token = "-"
	if duty == "L" and acct.gk then
		local t = acct.token
		if not t or (t.expiry or 0) - Now() < Wallet.TOKEN_REISSUE then
			t = ns.Standing.Issue(acct.gk, acct.name, "L")
			acct.token = t
		end
		if t then token = t.wire end
	end
	local body = ("%s~%s~g:%s.%s.%s~p:%s.%s~%s~%s"):format(b.epoch, B36(acct.code), B36(a.g.bal), B36(a.g.escrow), B36(a.g.reserved), B36(a.p.bal),
		B36(a.p.escrow), B36(b.seq), token)
	ns.Arena.Send("ZS", duty, body, { to = acct.name, low = true, key = "zs " .. acct.key })
end

---------------------------------------------------------------------------
-- The asks (ZQ): H the auditors' and the fee receiver's hello; R a bank's replay ask; E an
-- auditor's gap; S a holder's statement.
---------------------------------------------------------------------------

local Replay -- (below)
local function OnAsk(dist, sender, mode, body)
	local what, ep, seq = ns.Arena.Fields(body, 3)
	seq = N(seq, 0)
	local R0 = R()
	if what == "H" then
		if R0 and R0.IsFeeReceiver(sender) then
			local s = Store("L")
			s.feeHello = type(s.feeHello) == "table" and s.feeHello or {}
			s.feeHello[ns.FullName(sender)] = Now()
		end
		if R0 and R0.Auditor(sender, mode) then
			D().HeardAuditor(sender)
			local b = Bank()
			if b and duty == mode then
				-- A whispered H names the snapshot this auditor checked (the design).
				if dist == "WHISPER" and ep == b.epoch and seq and b.snap and b.snap.seq == seq then
					b.snap.by = b.snap.by or {}
					b.snap.by[Lower(sender)] = true
					local n = 0
					for _ in pairs(b.snap.by) do n = n + 1 end
					if n >= 2 then Wallet.Prune(b) end
				elseif dist ~= "WHISPER" then
					-- A hello (every 15 minutes, and after a login): the key and every name again, as
					-- he may not have known this bank when they went (the design: "to an auditor's hello").
					b.told[Lower(sender)] = nil
				end
				TellAuditors(b, "names")
			end
			local St = ns.Stakes
			if St and St.Hello then ns.SafeCall("stakes hello", St.Hello, sender, mode) end
			-- (the games' ledger, 1.1.6: this character's games not yet told to him, and on an
			-- auditor's client the words he was not given)
			local LGh = ns.ArenaLedger
			if LGh and LGh.GamesHello then ns.SafeCall("games hello", LGh.GamesHello, sender) end
		end
	elseif what == "R" then
		if dist ~= "CHANNEL" and dist ~= "RAID" and dist ~= "PARTY" then return end
		if R0 and R0.IsBank(sender, mode) and R0.Auditor(ns.me, mode) then Replay(sender, mode, ep, seq) end
	elseif what == "E" then
		local b = Bank()
		if dist ~= "WHISPER" or not b or duty ~= mode or ep ~= b.epoch or not seq then return end
		if not (R0 and R0.Auditor(sender, mode)) then return end
		b.gapAsks = b.gapAsks or {}
		if Now() - (b.gapAsks[Lower(sender)] or 0) < 60 then return end
		b.gapAsks[Lower(sender)] = Now()
		Wallet.SendRange(b, sender, seq, b.seq)
	elseif what == "S" then
		local b = Bank()
		if dist ~= "WHISPER" or not b or duty ~= mode then return end
		-- (In a chips rehearsal asking is a first action: the account and its chips.)
		local key = ChipsRun() and Participant(sender) and Wallet.Account(sender, true) or Lower(sender)
		local acct = b.accounts[key]
		if not acct then return end
		b.heard[acct.key] = Now()
		Wallet.Spoke(b, acct.key)
		ChipsGrant(b, acct)
		b.sAsks = b.sAsks or {}
		if Now() - (b.sAsks[acct.key] or 0) < 300 then return end
		b.sAsks[acct.key] = Now()
		Statement(b, acct, true)
	elseif what == "T" then
		-- A tester's "Top up" (the design): chips only, at most once an hour.
		local b = Bank()
		if dist ~= "WHISPER" or not b or duty ~= "T" or mode ~= "T" then return end
		if ep ~= b.epoch then return Answer(b, sender, "T", "ep", 0) end
		local key = ChipsRun() and Participant(sender) and Wallet.Account(sender, true)
		local acct = key and b.accounts[key]
		if not acct then return Answer(b, sender, "T", "topup", 0) end
		b.heard[acct.key] = Now()
		Wallet.Spoke(b, acct.key)
		local seq, why, wait = TopUp(b, acct)
		if not seq then return Answer(b, sender, "T", why, math.ceil(wait or 0)) end
		Answer(b, sender, "T", "ok", Wallet.TOPUP)
		Statement(b, acct, true)
	end
end
ns.Comm.Handle("ZQ", ns.Arena.Handle("ZQ", OnAsk))

-- Entries from..to by whisper, in the chunks the channel carried (each ending on a MAC the bank
-- recorded), so the receiver can check them.
function Wallet.SendRange(b, to, from, last)
	if from < (b.firstSeq or 1) and b.base then
		-- (Pruned before it: where the kept entries start, and the head there.)
		ns.Arena.Send("ZE", duty, ("%s~0~^%s.%s.%s.%s~-"):format(b.epoch, B36(b.firstSeq), b.base, B36(b.seq), b.head:sub(1, 16)), { to = to, must = true })
	end
	from = math.max(b.firstSeq or 1, from)
	local parts, first, bytes = {}, nil, 0
	for seq = from, last do
		local text = b.full[seq] and ("!" .. b.full[seq]) or b.entries[seq]
		if not text then parts, first, bytes = {}, nil, 0 else
			if #parts > 0 and bytes + #text > Wallet.ZE_ROOM * 6 then
				ns.Arena.Send("ZE", duty, ("%s~%s~%s~%s"):format(b.epoch, B36(first), table.concat(parts, ";"), b.macs[seq - 1] or "0"), { to = to, low = true, must = true })
				parts, first, bytes = {}, nil, 0
			end
			first = first or seq
			parts[#parts + 1] = text
			bytes = bytes + #text + 1
		end
	end
	if parts[1] then ns.Arena.Send("ZE", duty, ("%s~%s~%s~%s"):format(b.epoch, B36(first), table.concat(parts, ";"), b.macs[last] or "0"), { to = to, low = true, must = true }) end
end

---------------------------------------------------------------------------
-- Heads (ZH): every client keeps each bank's, small (the design heads).
---------------------------------------------------------------------------

local function Heads(mode, create)
	local s = create and Store(mode) or Peek(mode)
	if not s then return {} end
	if type(s.heads) ~= "table" then
		if not create then return {} end
		s.heads = {}
	end
	return s.heads
end

local function OnHead(dist, sender, mode, body)
	if dist == "WHISPER" then return end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return end
	local R0 = R()
	if not (R0 and R0.IsBank(sender, mode)) then return end
	local ep, seq, mac, head, state, mapID, fp, flags = ns.Arena.Fields(body, 8)
	seq = N(seq, 0)
	if not ep or not ep:find("^R?[0-9a-z]+$") or not seq or not head or not head:find("^%x+$") or not state or not ("odfpc"):find(state, 1, true) then return end
	local heads = Heads(mode, true)
	local key = Lower(sender)
	heads[key] = { name = ns.FullName(sender), epoch = ep, seq = seq, mac = mac, head = head, state = state, mapID = mapID ~= "-" and N(mapID, 0) or nil,
		fp = fp ~= "-" and fp or nil, persists = flags:find("s", 1, true) ~= nil, liab = flags:find("L", 1, true) ~= nil, heardAt = Now() }
	-- An auditor's replica checks its head against it.
	local s = Peek(mode)
	local rep = s and s.replicas and s.replicas[key]
	if rep and rep.epoch == ep then rep.zh = { seq = seq, head = head, at = Now() } Wallet.CheckHead(rep) end
	ns.Arena.Changed()
end
ns.Comm.Handle("ZH", ns.Arena.Handle("ZH", OnHead))

-- A dropped bank the heads or the replicas still show owing stays, closing (the design).
R().stillOwing = function(name)
	for _, mode in ipairs({ "L" }) do
		local h = Heads(mode)[Lower(name) or ""]
		if h and h.liab then return true end
		local s = Peek(mode)
		local rep = s and s.replicas and s.replicas[Lower(name) or ""]
		if rep and rep.st then
			local t = Wallet.Totals(rep.st)
			if t.g + t.owed > 0 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The ledger heard (ZE): on the channel only from the bank itself; by whisper to the bank only
-- from auditors (a replay); by whisper from the bank to auditors (opaque entries' full text, a gap).
---------------------------------------------------------------------------

local listen = {}
function Wallet.Listen(key, on)
	if type(key) == "string" then listen[key] = on and true or nil end
end
function Wallet.OnEntry(fn) if type(fn) == "function" then entrySubs[#entrySubs + 1] = fn end end

local function Replicas(mode)
	local s = Store(mode)
	s.replicas = type(s.replicas) == "table" and s.replicas or {}
	return s.replicas
end
local function Replica(bank, mode, ep, create)
	local reps = Replicas(mode)
	local key = Lower(bank)
	local rep = reps[key]
	if rep and ep and rep.epoch ~= ep and create then rep = nil end
	if not rep and create then
		rep = { name = ns.FullName(bank), epoch = ep, seq = 0, head = Hex(Wallet.Genesis(ep)), entries = {}, full = {}, macs = {}, names = {}, st = Wallet.NewState(),
			flags = {}, firstSeq = 1, heardAt = Now() }
		reps[key] = rep
	end
	return rep
end
Wallet.ReplicaStore = Replica

-- Applies entries in order onto a replica, the hash chain extended as it goes; unblinded once the
-- auditor holds the blinding key (kb), else kept to apply when it comes.
local function Advance(rep)
	while true do
		local seq = rep.seq + 1
		local text = rep.entries[seq]
		if not text then break end
		local body = rep.full[seq] or text
		if text:sub(1, 2) == "h:" and not rep.full[seq] then break end -- (its full text first)
		rep.head = Hex(Wallet.Chain(Unhex(rep.head), seq, text))
		rep.seq = seq
		rep.hist = rep.hist or {}
		rep.hist[seq] = rep.head:sub(1, 16)
		rep.hist[seq - 300] = nil
		if rep.zh and rep.zh.seq == seq then Wallet.CheckHead(rep) end
		if rep.kb then
			local e = Wallet.Parse(body, seq, Unhex(rep.kb))
			if not e then
				rep.flags[#rep.flags + 1] = { seq = seq, what = "parse" }
			else
				if e.k == "B" then
					-- (A bet at or after its market's lock is flagged: the design.)
					local m = rep.st.m[e.market]
					if m and m.closes > 0 and (e.t or 0) >= m.closes then rep.flags[#rep.flags + 1] = { seq = seq, what = "late", market = e.market } end
				end
				local ok, why = Wallet.Apply(rep.st, e, seq)
				if not ok then rep.flags[#rep.flags + 1] = { seq = seq, what = why } end
				if e.k == "k" then Wallet.CheckSnapshot(rep, seq, e) end
			end
		end
	end
end
Wallet.Advance = Advance

-- The replica's head against the last ZH everyone heard: the same bytes, at the same seq (checked
-- when the replica reaches that seq, or from its recent heads when it passed it already).
function Wallet.CheckHead(rep)
	local zh = rep.zh
	if not zh then return nil end
	local mine = rep.seq == zh.seq and rep.head:sub(1, 16) or (rep.hist and rep.hist[zh.seq])
	if mine and zh.checked ~= zh.seq then
		zh.checked = zh.seq
		rep.matches = mine == zh.head
		if not rep.matches then rep.flags[#rep.flags + 1] = { seq = zh.seq, what = "head" } end
	end
	return rep.matches
end

local function OnLedger(dist, sender, mode, body)
	local ep, first, list, lastmac = ns.Arena.Fields(body, 4)
	first = N(first, 0)
	if not ep or not first or not list then return end
	-- (Seq 0: a header, whispered: a re-seat's to a bank that asked, or a pruned bank's start to an
	-- auditor; nothing else.)
	if first == 0 and dist ~= "WHISPER" then return end
	local R0 = R()
	local b = Bank()
	-- On the bank: a replay from an auditor (the design), or a replica for a re-seat it asked.
	if b and duty == mode and dist == "WHISPER" then
		if R0 and R0.Auditor(sender, mode) then
			if b.reseat and ep == b.reseat.ep then Wallet.TakeReseat(b, sender, first, list) else Wallet.TakeReplay(b, sender, ep, first, list, lastmac) end
		end
		return
	end
	if not (R0 and R0.IsBank(sender, mode)) then return end
	local auditor = R0.Auditor(ns.me, mode)
	if dist == "WHISPER" then
		-- The bank's whisper to an auditor: the full text of an opaque entry, or a range it asked.
		if not auditor then return end
		local rep = Replica(sender, mode, ep, true)
		if first == 0 then
			-- The bank pruned before what this replica misses: it starts where the bank's entries do.
			local fs, base = tostring(list):match("^%^([0-9a-z]+)%.(%x+)%.")
			fs = fs and N(fs, 1)
			if fs and rep.seq < fs - 1 then
				for s2 in pairs(rep.entries) do if s2 < fs then rep.entries[s2], rep.full[s2] = nil, nil end end
				rep.firstSeq, rep.base, rep.head, rep.seq, rep.st = fs, base, base, fs - 1, Wallet.NewState()
				rep.st.fromSnap = true
				Advance(rep)
			end
			return
		end
		local seq = first
		for part in (list .. ";"):gmatch("([^;]*);") do
			if part:sub(1, 1) == "!" then
				local full = part:sub(2)
				if not rep.entries[seq] or rep.entries[seq] == "h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full)) then
					rep.full[seq] = full
					rep.entries[seq] = rep.entries[seq] or ("h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full)))
				end
			elseif part ~= "" then
				rep.entries[seq] = rep.entries[seq] or part
			end
			seq = seq + 1
		end
		rep.macs[seq - 1] = lastmac
		Advance(rep)
		return
	end
	if dist ~= "CHANNEL" and dist ~= "RAID" and dist ~= "PARTY" then return end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return end
	local want = auditor or next(listen) ~= nil
	if not want then return end
	local rep = auditor and Replica(sender, mode, ep, true) or nil
	local seq = first
	for part in (list .. ";"):gmatch("([^;]*);") do
		if part ~= "" then
			if rep then rep.entries[seq] = part end
			if next(listen) or #entrySubs > 0 then
				local e = Wallet.Parse(part, seq, rep and rep.kb and Unhex(rep.kb) or nil)
				if e and e.k == "B" then
					for i, bet in ipairs(e.bets) do
						local out = { k = "b", market = e.market, eid = e.eid, idx = e.idx, o = e.o, s = bet.s, nonce = bet.nonce, t = e.t, i = i }
						if rep and rep.kb then out.code = bet.code end
						Fire(ns.FullName(sender), seq, out)
					end
				elseif e then
					Fire(ns.FullName(sender), seq, e)
				end
			end
			seq = seq + 1
		end
	end
	if rep then
		rep.macs[seq - 1] = lastmac
		rep.heardAt = Now()
		-- A gap: asked for once a minute at most.
		if first > rep.seq + 1 and not rep.entries[rep.seq + 1] and Now() - (rep.askedAt or 0) >= 60 then
			rep.askedAt = Now()
			ns.Arena.Send("ZQ", mode, ("E~%s~%s"):format(ep, B36(rep.seq + 1)), { to = sender })
		end
		Advance(rep)
	end
end
ns.Comm.Handle("ZE", ns.Arena.Handle("ZE", OnLedger))

-- The names behind the codes, and the blinding key (auditors only; and a bank collecting a
-- re-seat's replicas from auditors).
local function OnNames(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local R0 = R()
	local b = Bank()
	if b and duty == mode and b.reseat and R0 and R0.Auditor(sender, mode) then
		local ep, rest = ns.Arena.Fields(body, 2)
		if ep ~= b.reseat.ep or not rest then return end
		local got = Wallet.ReseatFrom(b, sender)
		local kb = rest:match("^K~(%x+)$")
		if kb then got.kb = kb return end
		for part in rest:gmatch("[^,]+") do
			local code, gk, name = part:match("^([0-9a-z]+)=([^/]+)/(.+)$")
			name = name and ns.Arena.Name(name)
			if code and name then got.names[code] = { name = name, gk = gk ~= "-" and gk or nil } end
		end
		return
	end
	if not (R0 and R0.Auditor(ns.me, mode) and R0.IsBank(sender, mode)) then return end
	local ep, rest = ns.Arena.Fields(body, 2)
	if not ep or not rest then return end
	local rep = Replica(sender, mode, ep, true)
	local kb = rest:match("^K~(%x+)$")
	if kb then
		if #kb == 64 and rep.kb ~= kb then
			rep.kb = kb
			-- Everything heard so far applied again with the key.
			rep.st, rep.seq, rep.head = Wallet.NewState(), (rep.firstSeq or 1) - 1, rep.base or Hex(Wallet.Genesis(ep))
			rep.st.fromSnap = (rep.firstSeq or 1) > 1 or nil
			Advance(rep)
		end
		return
	end
	for part in rest:gmatch("[^,]+") do
		local code, gk, name = part:match("^([0-9a-z]+)=([^/]+)/(.+)$")
		name = name and ns.Arena.Name(name)
		if code and name then rep.names[code] = { name = name, gk = gk ~= "-" and gk or nil } end
	end
	ns.Arena.Changed()
end
ns.Comm.Handle("ZN", ns.Arena.Handle("ZN", OnNames))

-- The bank's reserve declaration (auditors: its own word, beside the attestation).
local function OnReserve(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local R0 = R()
	if not (R0 and R0.Auditor(ns.me, mode) and R0.IsBank(sender, mode)) then return end
	local ep, seq, gold, bal, escrow, reserved, owed, accounts, float = ns.Arena.Fields(body, 9)
	local rep = Replica(sender, mode, ep, true)
	rep.reserve = { seq = N(seq, 0), gold = N(gold, 0), bal = N(bal, 0), escrow = N(escrow, 0), reserved = N(reserved, 0), owed = N(owed, 0),
		accounts = N(accounts, 0), float = N(float, 0), at = Now() }
	ns.Arena.Changed()
end
ns.Comm.Handle("ZG", ns.Arena.Handle("ZG", OnReserve))

---------------------------------------------------------------------------
-- Snapshots (the design): a checkpoint writes one v per account with anything, then k with the
-- totals and a digest; auditors recompute it from their own entries and say so (a whispered
-- ZQ~H); entries before it go only once two auditors checked it.
---------------------------------------------------------------------------

local function SnapDigest(st)
	local codes = {}
	for code, a in pairs(st.acc) do
		if a.g.bal + a.g.reserved + a.g.escrow + a.p.bal + a.p.escrow > 0 then codes[#codes + 1] = code end
	end
	table.sort(codes)
	local parts = {}
	for _, code in ipairs(codes) do
		local a = st.acc[code]
		parts[#parts + 1] = ("%s:%d.%d.%d:%d.%d"):format(B36(code), a.g.bal, a.g.reserved, a.g.escrow, a.p.bal, a.p.escrow)
	end
	parts[#parts + 1] = ("%d:%d"):format(st.owed, st.float)
	return Hex(ns.Sign.SHA256(table.concat(parts, ";"))):sub(1, 16)
end
Wallet.SnapDigest = SnapDigest

function Wallet.Checkpoint()
	local b = OnDuty()
	if not b then return nil, "duty" end
	for _, m in pairs(b.st.m) do
		if not m.settled then return nil, "open" end
	end
	-- (A pot carried to a later market is in no v line: the checkpoint waits for it to be paid.)
	for _, pot in pairs(b.st.carry or {}) do
		if pot > 0 then return nil, "pot" end
	end
	Seal(b)
	local digest = SnapDigest(b.st)
	local first, base = b.seq + 1, b.head
	local codes = {}
	for code in pairs(b.st.acc) do codes[#codes + 1] = code end
	table.sort(codes)
	for _, code in ipairs(codes) do
		local a = b.st.acc[code]
		if a.g.bal + a.g.reserved + a.g.escrow + a.p.bal + a.p.escrow > 0 then
			Write(b, { k = "v", code = code, g = { bal = a.g.bal, reserved = a.g.reserved, escrow = a.g.escrow }, p = { bal = a.p.bal, escrow = a.p.escrow } })
		end
	end
	local t = Wallet.Totals(b.st)
	local seq = Write(b, { k = "k", liabG = t.g, escG = t.escG, owed = t.owed, float = t.float, liabP = t.p, digest = digest })
	b.snap = { seq = seq, first = first, base = base, digest = digest, by = {}, at = Now() }
	return seq
end

-- An auditor's check of a snapshot: its digest from the replica's own balances.
function Wallet.CheckSnapshot(rep, seq, e)
	local mine = SnapDigest(rep.st)
	rep.snap = { seq = seq, ok = mine == e.digest, at = Now() }
	if not rep.snap.ok then rep.flags[#rep.flags + 1] = { seq = seq, what = "snapshot" } return end
	-- (Told to the bank by whisper: it prunes once two auditors checked.)
	local mode = rep.mode or "L"
	ns.Arena.Send("ZQ", mode, ("H~%s~%s"):format(rep.epoch, B36(seq)), { to = rep.name })
end

-- Entries before a snapshot two auditors checked go (the bank's; each replica prunes its own
-- once it checked the snapshot and holds more than ENTRIES_MAX).
function Wallet.Prune(b)
	local snap = b.snap
	if not snap or not snap.seq then return end
	local first = snap.first or snap.seq
	for seq in pairs(b.entries) do
		if seq < first then b.entries[seq], b.full[seq], b.macs[seq] = nil, nil, nil end
	end
	-- (The snapshot's own v lines stay: a replica that starts here rebuilds every balance from them.)
	b.firstSeq, b.base = first, snap.base
end

---------------------------------------------------------------------------
-- Recovery (the design, as amended): the bank's saved ledger may be older than what it
-- published before a crash. It asks (ZQ~R); auditors answer with the entries after its seq, in
-- the chunks the channel carried; it takes those whose MAC chains under its own secret. A replay
-- that runs past its saved seq blocks payouts on any W without its w until the operator says.
---------------------------------------------------------------------------

Replay = function(bank, mode, ep, seq)
	local rep = Replica(bank, mode)
	if not rep or rep.epoch ~= ep or not seq or rep.seq <= seq then return end
	-- A re-seat's ask (seq 0, the bank lost everything): first this replica's base (the head before
	-- its first entry) and the last head it heard in ZH, then the key and the names.
	if seq == 0 then
		local zh = rep.zh or {}
		ns.Arena.Send("ZE", mode, ("%s~0~^%s.%s.%s.%s~-"):format(rep.epoch, B36(rep.firstSeq or 1), rep.base or Hex(Wallet.Genesis(rep.epoch)),
			B36(zh.seq or 0), zh.head or "-"), { to = bank, must = true })
		if rep.kb then ns.Arena.Send("ZN", mode, ("%s~K~%s"):format(rep.epoch, rep.kb), { to = bank, must = true }) end
		local list = {}
		for code, info in pairs(rep.names) do list[#list + 1] = ("%s=%s/%s"):format(code, info.gk or "-", ns.FullName(info.name)) end
		table.sort(list)
		local chunk = {}
		for _, item in ipairs(list) do
			chunk[#chunk + 1] = item
			if #table.concat(chunk, ",") > 1800 then
				ns.Arena.Send("ZN", mode, rep.epoch .. "~" .. table.concat(chunk, ","), { to = bank, must = true, low = true })
				chunk = {}
			end
		end
		if chunk[1] then ns.Arena.Send("ZN", mode, rep.epoch .. "~" .. table.concat(chunk, ","), { to = bank, must = true, low = true }) end
		seq = (rep.firstSeq or 1) - 1
	end
	-- (Chunks ending where the channel's own ZE ended: each carries the bank's MAC for its end.)
	local parts, first, bytes = {}, nil, 0
	local function Flush(last)
		if not parts[1] then return end
		ns.Arena.Send("ZE", mode, ("%s~%s~%s~%s"):format(rep.epoch, B36(first), table.concat(parts, ";"), rep.macs[last] or "0"), { to = bank, low = true, must = true })
		parts, first, bytes = {}, nil, 0
	end
	for s = seq + 1, rep.seq do
		local text = rep.full[s] and ("!" .. rep.full[s]) or rep.entries[s]
		if not text then break end
		first = first or s
		parts[#parts + 1] = text
		bytes = bytes + #text + 1
		if rep.macs[s] then Flush(s) end
	end
	Flush(rep.seq)
end

function Wallet.TakeReplay(b, sender, ep, first, list, lastmac)
	if ep ~= b.epoch then return end
	b.replay = b.replay or { chunks = {} }
	b.replay.chunks[first] = b.replay.chunks[first] or {}
	table.insert(b.replay.chunks[first], { list = list, mac = lastmac, from = ns.FullName(sender) })
	-- Chunks in order from the ledger's seq on; the first that checks wins (a forged one cannot).
	local progressed = true
	while progressed do
		progressed = false
		local at = b.seq + 1
		for _, c in ipairs(b.replay.chunks[at] or {}) do
			local texts = {}
			for part in (c.list .. ";"):gmatch("([^;]*);") do if part ~= "" then texts[#texts + 1] = part end end
			local mac, head = b.mac, Unhex(b.head)
			local secret = Unhex(b.secret)
			for i, part in ipairs(texts) do
				local seq = at + i - 1
				local full = part:sub(1, 1) == "!" and part:sub(2) or nil
				local text = full and ("h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full))) or part
				mac = Wallet.Mac(secret, mac, seq, full or text)
				head = Wallet.Chain(head, seq, text)
			end
			if #texts > 0 and mac == c.mac then
				-- Checks: applied as the bank's own.
				local kb = Unhex(b.kb)
				for i, part in ipairs(texts) do
					local seq = at + i - 1
					local full = part:sub(1, 1) == "!" and part:sub(2) or nil
					local e = Wallet.Parse(full or part, seq, kb)
					if e then
						Wallet.Apply(b.st, e, seq)
						if e.k == "q" then
							b.wq = b.wq or {}
							b.wq[#b.wq + 1] = { code = e.code, qseq = seq, copper = e.copper, at = Now() }
							if e.nonce then b.wnonces[e.nonce] = { key = b.byCode[B36(e.code)], qseq = seq } end
						elseif e.k == "B" then
							for j, bet in ipairs(e.bets) do
								b.nonces[bet.nonce] = { key = b.byCode[B36(bet.code)], market = e.market, o = e.o, s = bet.s, seq = seq, i = j }
							end
						end
					end
					b.entries[seq] = full and ("h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(full))) or part
					if full then b.full[seq] = full end
				end
				b.seq = at + #texts - 1
				b.mac, b.head = mac, Hex(head)
				b.macs[b.seq] = mac
				b.replayed = (b.replayed or 0) + #texts
				progressed = true
				break
			else
				b.replay.refused = (b.replay.refused or 0) + 1
				ns.Log("wallet replay chunk from %s at %d refused", tostring(c.from), at)
			end
		end
		b.replay.chunks[at] = progressed and nil or b.replay.chunks[at]
	end
	-- Past the saved seq: every W without its w blocks that account's payouts (the design).
	if (b.replayed or 0) > 0 then
		for qseq, w in pairs(b.st.wd) do
			if w.state == "W" then b.blocked[B36(w.code)] = qseq end
		end
	end
	ns.Arena.Changed()
end

---------------------------------------------------------------------------
-- Re-seat (the design, as amended): the bank's saved data gone and no backup. A new
-- epoch whose opening balances come from a replica whose recomputed head equals the last ZH the
-- bank's head says, confirmed by a second auditor's replica: one "a" (J, "reseat") per account.
-- rep1, rep2: the two auditors' replicas as they sent them ({ epoch, entries, full, kb, names,
-- base, firstSeq }); lastHead: the last ZH head (16 hex) and seq heard. The operator's click.
---------------------------------------------------------------------------

-- A replica's balances recomputed from its entries alone, and its head at `seq`.
function Wallet.Recompute(rep, seq)
	local st = Wallet.NewState()
	st.fromSnap = (rep.firstSeq or 1) > 1 or nil
	local head = rep.base and Unhex(rep.base) or Wallet.Genesis(rep.epoch)
	local kb = rep.kb and Unhex(rep.kb)
	if not kb then return nil, "kb" end
	for s = rep.firstSeq or 1, seq do
		local text = rep.entries[s]
		if not text then return nil, "gap" end
		head = Wallet.Chain(head, s, text)
		local body = rep.full and rep.full[s] or text
		if text:sub(1, 2) ~= "h:" or (rep.full and rep.full[s]) then
			local e = Wallet.Parse(body, s, kb)
			if not e then return nil, "parse" end
			local ok, why = Wallet.Apply(st, e, s)
			if not ok then return nil, why end
		end
	end
	return st, Hex(head):sub(1, 16)
end

-- The bank asks (its old epoch, which any client's heads name): the auditors whisper their
-- replicas (Replay with seq 0).
function Wallet.ReseatAsk(oldEp)
	local b = OnDuty()
	if not b then return nil, "duty" end
	if type(oldEp) ~= "string" or oldEp == b.epoch then return nil, "epoch" end
	b.reseat = { ep = oldEp, from = {}, at = Now() }
	return ns.Arena.Send("ZQ", duty, ("R~%s~0"):format(oldEp), {})
end
function Wallet.ReseatFrom(b, sender)
	local key = Lower(sender)
	local got = b.reseat.from[key]
	if not got then
		got = { from = ns.FullName(sender), epoch = b.reseat.ep, entries = {}, full = {}, names = {} }
		b.reseat.from[key] = got
	end
	return got
end
function Wallet.TakeReseat(b, sender, first, list)
	local got = Wallet.ReseatFrom(b, sender)
	if first == 0 then
		local fs, base, zseq, zhead = tostring(list):match("^%^([0-9a-z]+)%.(%x+)%.([0-9a-z]+)%.([%x%-]+)$")
		if not fs then return end
		got.firstSeq, got.base = N(fs, 1), base
		got.zh = { seq = N(zseq, 0), head = zhead ~= "-" and zhead or nil }
		return
	end
	local seq = first
	for part in (list .. ";"):gmatch("([^;]*);") do
		if part:sub(1, 1) == "!" then
			got.full[seq] = part:sub(2)
			got.entries[seq] = "h:" .. ns.Ed25519.ToB64(ns.Sign.SHA256(part:sub(2)))
		elseif part ~= "" then
			got.entries[seq] = part
		end
		seq = seq + 1
	end
end
-- The collected replicas of two auditors (by name), or two replicas as tables with the last head
-- everyone heard (last = { seq, head }): the balances only from both, agreeing, each reaching it.
function Wallet.Reseat(rep1, rep2, last)
	local b = OnDuty()
	if not b then return nil, "duty" end
	if type(rep1) == "string" and type(rep2) == "string" then
		local got = b.reseat and b.reseat.from or {}
		rep1, rep2 = got[Lower(rep1)], got[Lower(rep2)]
		if not rep1 or not rep2 then return nil, "replicas" end
		-- (The head both heard last: the same, else no re-seat.)
		if not rep1.zh or not rep2.zh or rep1.zh.seq ~= rep2.zh.seq or rep1.zh.head ~= rep2.zh.head or not rep1.zh.head then return nil, "head" end
		last = last or rep1.zh
	end
	if type(rep1) ~= "table" or type(rep2) ~= "table" or type(last) ~= "table" then return nil, "replicas" end
	if Same(rep1.from, rep2.from) then return nil, "second" end
	local st1, h1 = Wallet.Recompute(rep1, last.seq)
	local st2, h2 = Wallet.Recompute(rep2, last.seq)
	if not st1 or h1 ~= last.head then return nil, "head" end
	if not st2 or h2 ~= last.head then return nil, "second" end
	if SnapDigest(st1) ~= SnapDigest(st2) then return nil, "differ" end
	-- A new epoch: the balances carried over, each account by its name.
	local oldEp = rep1.epoch
	NewLedger(duty)
	b = Bank()
	b.reseatOf = oldEp
	Write(b, { k = "o", copper = GetMoney and tonumber(GetMoney()) or 0, how = "s" })
	for code, a in pairs(st1.acc) do
		local info = rep1.names and rep1.names[B36(code)]
		local key = info and Wallet.Account(info.name, true)
		local acct = key and b.accounts[key]
		if acct then
			if a.g.bal + a.g.reserved + a.g.escrow > 0 then
				Write(b, { k = "a", code = acct.code, sign = "+", copper = a.g.bal + a.g.reserved + a.g.escrow, why = "J", ref = "reseat", cur = "g" })
			end
			if a.p.bal + a.p.escrow > 0 then
				Write(b, { k = "a", code = acct.code, sign = "+", copper = a.p.bal + a.p.escrow, why = "J", ref = "reseat", cur = "p" })
			end
		end
	end
	SendNow(b)
	return b.epoch
end

---------------------------------------------------------------------------
-- Reconciliation (the design, as amended): the reserve is the bank's gold less what it
-- owes; a claim (ZL) is credited only from gold nothing else explains, and consumes it.
---------------------------------------------------------------------------

function Wallet.Reserve()
	local b = Bank()
	if not b then return nil end
	local t = Wallet.Totals(b.st)
	local gold = GetMoney and tonumber(GetMoney()) or 0
	local surplus = gold - t.g - t.owed
	return { gold = gold, liabilities = t.g, owed = t.owed, float = t.float, surplus = surplus, unexplained = surplus - t.float,
		deficit = surplus < t.float and (t.float - surplus) or 0, points = t.p }
end

local function OnClaim(dist, sender, mode, body)
	local b = Bank()
	if dist ~= "WHISPER" or not b or mode ~= duty then return end
	local ep, nonce, how, copper, time = ns.Arena.Fields(body, 5)
	copper, time = ns.Arena.Copper(copper), N(time, 0)
	if ep ~= b.epoch or not copper or not nonce or not nonce:find("^[0-9a-z]+$") or #nonce > 8 then return end
	if b.claims[nonce] then return end
	b.claims[nonce] = { nonce = nonce, name = ns.FullName(sender), how = how == "m" and "m" or "t", copper = copper, time = time, state = "open", at = Now() }
	ns.Arena.Changed()
end
ns.Comm.Handle("ZL", ns.Arena.Handle("ZL", OnClaim))

function Wallet.Accept(nonce)
	local b = OnDuty()
	if not b then return nil, "duty" end
	local c = b.claims[type(nonce) == "table" and nonce.nonce or nonce]
	if not c or c.state ~= "open" then return nil, "claim" end
	local r = Wallet.Reserve()
	if c.copper > r.unexplained then return nil, "surplus" end
	local key = Wallet.Account(c.name, true)
	local acct = key and b.accounts[key]
	if not acct then return nil, "account" end
	Write(b, { k = "a", code = acct.code, sign = "+", copper = c.copper, why = "C", ref = c.nonce, cur = "g" })
	c.state, c.done = "accepted", Now()
	Statement(b, acct, true)
	return true
end
function Wallet.Refuse(nonce)
	local b = OnDuty()
	local c = b and b.claims[nonce]
	if not c or c.state ~= "open" then return nil end
	c.state, c.done = "refused", Now()
	return true
end

-- A leader's order (ZJ, the King's character or an auditor): kept for the operator's click; never
-- from a sender whose key is the bank's own (the design).
local function OnOrder(dist, sender, mode, body)
	local b = Bank()
	if dist ~= "WHISPER" or not b or mode ~= duty then return end
	local R0 = R()
	if not (R0 and (R0.IsKing(sender) or R0.Auditor(sender, mode))) then return end
	local _, _, myFp = D().MyKey()
	local _, fp = D().Verified(sender)
	if fp and fp == myFp then return end
	local ep, nonce, code, sign, copper, why, ref = ns.Arena.Fields(body, 7)
	copper = ns.Arena.Copper(copper)
	if ep ~= b.epoch or not nonce or not code or not (sign == "+" or sign == "-") or not copper or not (why == "J" or why == "W") then return end
	if b.orders[nonce] then return end
	b.orders[nonce] = { nonce = nonce, from = ns.FullName(sender), code = code, sign = sign, copper = copper, why = why, ref = ref, state = "open", at = Now() }
	ns.Arena.Changed()
end
ns.Comm.Handle("ZJ", ns.Arena.Handle("ZJ", OnOrder))

function Wallet.ApplyOrder(nonce)
	local b = OnDuty()
	local o = b and b.orders[nonce]
	if not o or o.state ~= "open" then return nil, "order" end
	local key = b.byCode[o.code]
	local acct = key and b.accounts[key]
	if not acct then return nil, "account" end
	local seq, why = Write(b, { k = "a", code = acct.code, sign = o.sign, copper = o.copper, why = o.why, ref = (o.ref or "-"):sub(1, 12), cur = "g" })
	if not seq then return nil, why end
	o.state, o.done = "applied", Now()
	Statement(b, acct, true)
	return seq
end

-- An auditor's order to a bank (the King's character or an auditor).
function Wallet.Order(bank, code, sign, copper, why, ref, mode)
	mode = Mode(mode)
	local rep = Replica(bank, mode)
	if not rep then return nil, "replica" end
	local nonce = B36(math.random(0, 36 ^ 5 - 1))
	return ns.Arena.Send("ZJ", mode, ("%s~%s~%s~%s~%s~%s~%s"):format(rep.epoch, nonce, tostring(code), sign == "-" and "-" or "+", B36(copper), why == "W" and "W" or "J",
		tostring(ref or "-"):gsub("[~|]", ""):sub(1, 12)), { to = bank })
end

---------------------------------------------------------------------------
-- The bank's duty (Wallet.Duty): its role checked (and its account's characters, the design), its
-- yes on the privacy page, gold only where saved data survives (the design).
---------------------------------------------------------------------------

-- The bank's yes (the design): a line of its own on the privacy page, shown on a bank's
-- character only; nil (never answered) is no. Kept per character on the account, never in a backup.
local function BankAnswer()
	local t = ns.db and ns.db.arenaBankYes
	local v = type(t) == "table" and ns.me and t[ns.me:lower()]
	if v == true or v == false then return v end
	return nil
end
local function BankYes() return BankAnswer() == true end
function Wallet.SetBankYes(on)
	if not ns.db or not ns.me then return false end
	ns.db.arenaBankYes = type(ns.db.arenaBankYes) == "table" and ns.db.arenaBankYes or {}
	ns.db.arenaBankYes[ns.me:lower()] = on and true or false
	if not on and duty then Wallet.Duty(false) end
	return true
end
if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({ key = "arenabank", label = "WALLET_CONSENT_LABEL", text = "WALLET_CONSENT_TEXT",
		shown = function()
			if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then return false end
			local R0 = R() return R0 ~= nil and (R0.IsBank(ns.me, "L") or R0.IsBank(ns.me, "T"))
		end,
		get = BankAnswer, set = function(on) Wallet.SetBankYes(on) end })
end

local function Tick()
	local b = Bank()
	if not b or not duty then return end
	QueueTick(b)
	if b.group and Now() > (b.group.opened or 0) then Seal(b) Queue(b) end
	FeeAccrual(b)
	if b.backlog[1] then Queue(b) end
	-- A checkpoint by itself once enough entries passed and every market is settled.
	if b.seq - ((b.snap and b.snap.seq) or 0) >= Wallet.CHECKPOINT_AFTER then
		local open = false
		for _, m in pairs(b.st.m) do if not m.settled then open = true break end end
		if not open and not b.backlog[1] then Wallet.Checkpoint() end
	end
end

function Wallet.OnDuty() return duty end
function Wallet.Pause(on)
	paused = on and true or false
	SendHead()
	return paused
end

function Wallet.Duty(on, mode)
	mode = Mode(mode)
	if not on then
		if not duty then return true end
		local b = Bank()
		if b then Seal(b) SendNow(b) b.onDuty = nil end
		ns.Arena.Every(Wallet.HEAD_EVERY, "wallet head", nil)
		ns.Arena.Every(Wallet.TICK, "wallet tick", nil)
		ns.Arena.Later("wallet ze", nil)
		ns.ArenaMoney.Forget("bank")
		duty = nil
		ns.Arena.SetDuty("bank", false)
		return true
	end
	local R0 = R()
	if not (R0 and R0.IsBank(ns.me, mode)) then return false, "unlisted" end
	if mode == "L" then
		local may, why = R0.MayBank()
		if not may then return false, why end
		if not R0.Live() then return false, "live" end
		if R0.Currency() == "g" and not ns.Arena.Persists() then ns.Print(L.WALLET_PERSIST) return false, "persist" end
	end
	if not BankYes() then return false, "consent" end
	duty = mode
	local b = Bank(mode)
	local fresh = false
	if not b then
		b = NewLedger(mode)
		fresh = true
	end
	b.onDuty = true
	b.st = b.st or Wallet.NewState()
	ns.Arena.SetDuty("bank", true)
	ns.ArenaMoney.Expect("bank", { dir = "both", mode = mode })
	ns.Arena.Every(Wallet.HEAD_EVERY, "wallet head", SendHead)
	ns.Arena.Every(Wallet.TICK, "wallet tick", Tick)
	if fresh then Write(b, { k = "o", copper = GetMoney and tonumber(GetMoney()) or 0, how = "s" }) end
	SendHead()
	-- After a restart its saved ledger may be behind what it published: asked once on duty.
	if not fresh then ns.Arena.Send("ZQ", mode, ("R~%s~%s"):format(b.epoch, B36(b.seq)), {}) end
	TellAuditors(b, "names")
	return true
end

-- A dropped bank or a /reload: the duty resumes at login when it was on (its operator's yes kept).
ns.On("LOGIN", function()
	for _, mode in ipairs({ "L", "T" }) do
		local s = Peek(mode)
		local b = s and type(s.bank) == "table" and s.bank or nil
		if b and b.onDuty then
			ns.Arena.After(5, "wallet resume " .. mode, function() Wallet.Duty(true, mode) end)
		end
	end
	-- The auditors' and the fee receiver's hello (ZQ~H): 40 s after login, then every 15 minutes;
	-- only on such a character (an idle client runs no arena timer).
	local R0 = R()
	if R0 and (R0.Auditor(ns.me, "L") or R0.IsFeeReceiver(ns.me)) then
		ns.Arena.After(Wallet.HELLO_AFTER, "wallet hello", function() Wallet.Hello() end)
	end
end)
function Wallet.Hello()
	local R0 = R()
	if not R0 then return false end
	local auditor = R0.Auditor(ns.me, "L")
	local receiver = R0.IsFeeReceiver(ns.me)
	if not auditor and not receiver then
		ns.Arena.Every(Wallet.HELLO_EVERY, "wallet hello", nil)
		return false
	end
	ns.Arena.Send("ZQ", "L", "H~-~0", { dist = "CHANNEL", obligation = true })
	if receiver then
		local s = Store("L")
		s.feeHello = type(s.feeHello) == "table" and s.feeHello or {}
		s.feeHello[ns.me] = Now()
	end
	ns.Arena.Every(Wallet.HELLO_EVERY, "wallet hello", Wallet.Hello)
	return true
end

---------------------------------------------------------------------------
-- The player's wallet (the design, 7): his own view, from the bank's statements and his own
-- receipts; every gold movement his own click.
---------------------------------------------------------------------------

local WatchReturn -- (below)
local function MyBank(bank, mode, create)
	local m = D().Mine(mode, create)
	if not m then return nil end
	local key = ns.FullName(bank)
	local w = m.banks[key]
	if type(w) ~= "table" then
		if not create then return nil end
		w = {}
		m.banks[key] = w
	end
	w.receipts = type(w.receipts) == "table" and w.receipts or {}
	w.intents = type(w.intents) == "table" and w.intents or {}
	return w
end

function Wallet.Banks(mode)
	mode = Mode(mode)
	local out = {}
	local heads = Heads(mode)
	for _, b in ipairs(R() and R().Banks(mode) or {}) do
		local h = heads[Lower(b.name)] or {}
		out[#out + 1] = { name = b.name, state = b.state, online = Wallet.Online(b.name, mode), heardAt = h.heardAt, mapID = h.mapID, persists = h.persists,
			epoch = h.epoch, full = h.state == "f", paused = h.state == "p", closing = b.state == "c" or h.state == "c", trading = h.state == "d", liab = h.liab }
	end
	return out
end

-- The player's deposit assignments by designated receiving character.  This is deliberately
-- local evidence: it balances this player's next deposit between receivers his client can see,
-- and never pretends to be a realm-wide dispatcher.  A receiver is eligible only while its bank
-- head says it is online, open, persistent and able to take another deposit.
local RECEIPT_PENDING = { asked = true, queued = true, called = true, sent = true, mail = true }
function Wallet.RecipientPlan(banks, receipts)
	local rows, byName = {}, {}
	for _, bank in ipairs(type(banks) == "table" and banks or {}) do
		if type(bank) == "table" and type(bank.name) == "string" then
			local row = {}
			for k, v in pairs(bank) do row[k] = v end
			row.name = ns.FullName(row.name)
			row.assigned, row.received, row.pendingCount = 0, 0, 0
			rows[#rows + 1] = row
			byName[Lower(row.name)] = row
		end
	end
	for _, rec in ipairs(type(receipts) == "table" and receipts or {}) do
		local row = type(rec) == "table" and byName[Lower(rec.bank)] or nil
		if row then
			row.assigned = row.assigned + 1
			if rec.state == "credited" then row.received = row.received + 1 end
			if RECEIPT_PENDING[rec.state] then row.pendingCount = row.pendingCount + 1 end
		end
	end
	local eligible = {}
	for _, row in ipairs(rows) do
		row.eligible = row.state == "o" and row.online == true and row.persists == true
			and not row.full and not row.paused and not row.closing and not row.trading
		if row.eligible then eligible[#eligible + 1] = row end
	end
	table.sort(eligible, function(a, b)
		if a.pendingCount ~= b.pendingCount then return a.pendingCount < b.pendingCount end
		if a.assigned ~= b.assigned then return a.assigned < b.assigned end
		if a.received ~= b.received then return a.received < b.received end
		return Lower(a.name) < Lower(b.name)
	end)
	return eligible[1] and eligible[1].name or nil, rows
end

-- The receiving character recommended for a new deposit.  Live gold remains behind every
-- existing switch and persistence guard; this helper opens none of them.
function Wallet.DepositRecipient(mode)
	mode = Mode(mode)
	local R0 = R()
	local name, rows = Wallet.RecipientPlan(Wallet.Banks(mode), Wallet.Receipts(mode))
	if mode == "L" then
		if not (R0 and R0.Live()) then return nil, "live", rows end
		if R0.Currency() ~= "g" then return nil, "cur", rows end
		if not ns.Arena.Persists() then return nil, "persist", rows end
	end
	if not name then return nil, "offline", rows end
	return name, nil, rows
end

-- Used by a deposit UI that wants the addon's assignment rather than choosing the first bank.
function Wallet.DepositAssigned(how, copper, mode)
	local bank, why = Wallet.DepositRecipient(mode)
	if not bank then return nil, why end
	return Wallet.Deposit(bank, how, copper, mode)
end
function Wallet.Online(bank, mode)
	local h = Heads(Mode(mode))[Lower(bank) or ""]
	return h ~= nil and Now() - (h.heardAt or 0) <= Wallet.BANK_FRESH
end

function Wallet.Statement(bank, mode)
	mode = Mode(mode)
	local w = MyBank(bank, mode) or { receipts = {} }
	local s = w.statement or {}
	local pending = 0
	for _, r in ipairs(w.receipts) do
		if r.state == "sent" or r.state == "mail" then pending = pending + r.copper end
	end
	return { g = { bal = s.gbal or 0, escrow = s.gesc or 0, reserved = s.gres or 0 }, p = { bal = s.pbal or 0, escrow = s.pesc or 0 }, pending = pending,
		code = w.code, token = w.token, seq = s.seq, at = s.at, epoch = w.epoch }
end

local function Nonce()
	local s = ""
	for _ = 1, 6 do
		local d = math.random(0, 35)
		s = s .. ("0123456789abcdefghijklmnopqrstuvwxyz"):sub(d + 1, d + 1)
	end
	return s
end
Wallet.Nonce = Nonce

-- Why this client may not deposit there now, or nil.
local function MayDeposit(bank, how, copper, mode)
	local R0 = R()
	if not (R0 and R0.IsBank(bank, mode)) then return "bank" end
	if R0.BankState(bank) == "c" and mode == "L" then return "closed" end
	if not Wallet.Online(bank, mode) then return "offline" end
	if mode == "L" then
		if not R0.Live() then return "live" end
		if R0.Currency() ~= "g" then return "cur" end
		if not ns.Arena.Persists() then return "persist" end
		local h = Heads(mode)[Lower(bank)]
		if h and not h.persists then return "bankpersist" end
	elseif not ns.ArenaMoney.CopperMode() then
		return "chips"
	elseif not ns.Arena.Persists() then
		return "persist"
	elseif copper > Wallet.COPPER_DEPOSIT then
		return "cap"
	end
	if not (how == "t" or how == "m") or copper <= 0 then return "amount" end
	return nil
end

function Wallet.Deposit(bank, how, copper, mode)
	mode = Mode(mode)
	copper = math.floor(tonumber(copper) or 0)
	bank = ns.FullName(bank)
	local why = MayDeposit(bank, how, copper, mode)
	if why then return nil, why end
	local w = MyBank(bank, mode, true)
	if Now() - (w.askedD or -math.huge) < Wallet.ASK_GAP then return nil, "rate" end
	local h = Heads(mode)[Lower(bank)]
	local id = Nonce()
	local level = UnitLevel and tonumber(UnitLevel("player")) or 0
	-- The key claim goes with it (a trade gives the bank a unit to bind it with, the design).
	D().SendClaim(bank, mode)
	if not ns.Arena.Send("ZD", mode, ("%s~%s~%s~%s"):format(h.epoch, how, B36(copper), B36(level)), { to = bank }) then return nil, "send" end
	w.askedD = Now()
	local r = { id = id, bank = bank, how = how, copper = copper, t = Now(), state = "asked", epoch = h.epoch, mode = mode }
	table.insert(w.receipts, 1, r)
	while #w.receipts > Wallet.RECEIPTS_MAX do table.remove(w.receipts) end
	w.epoch = h.epoch
	ns.ArenaMoney.Expect("dep:" .. id, { partner = bank, dir = "out", copper = copper, mode = mode })
	ns.Arena.Involve("wallet", true)
	return r
end

-- The fill for a deposit (his click): the mail, anywhere; the trade, with the bank's window open.
function Wallet.FillDeposit(id, mode)
	mode = Mode(mode)
	for _, b in ipairs(Wallet.Banks(mode)) do
		local w = MyBank(b.name, mode) or { receipts = {} }
		for _, r in ipairs(w.receipts) do
			if r.id == id then
				if r.how == "m" then return ns.ArenaMoney.FillMail(r.bank, ns.ArenaMoney.Subject("deposit", nil, mode == "T"), r.copper) end
				return ns.ArenaMoney.FillTrade(r.copper, r.bank)
			end
		end
	end
	return nil, "receipt"
end

function Wallet.Withdraw(bank, amount, mode)
	mode = Mode(mode)
	bank = ns.FullName(bank)
	if Wallet.Held(ns.me) then return nil, "frozen" end -- (1.1.6: on hold while his case is decided)
	local R0 = R()
	if not (R0 and R0.IsBank(bank, mode)) then return nil, "bank" end
	if not Wallet.Online(bank, mode) then return nil, "offline" end
	if mode == "L" and not ns.Arena.Persists() then return nil, "persist" end
	local copper = amount == "all" and "all" or math.floor(tonumber(amount) or 0)
	if copper ~= "all" and copper <= 0 then return nil, "amount" end
	local w = MyBank(bank, mode, true)
	if Now() - (w.askedW or -math.huge) < Wallet.ASK_GAP then return nil, "rate" end
	local h = Heads(mode)[Lower(bank)]
	local nonce = Nonce()
	D().SendClaim(bank, mode)
	if not ns.Arena.Send("ZW", mode, ("%s~%s~%s~m"):format(h.epoch, nonce, copper == "all" and "all" or B36(copper)), { to = bank }) then return nil, "send" end
	w.askedW = Now()
	local intent = { nonce = nonce, bank = bank, copper = copper, t = Now(), state = "asked", mode = mode }
	table.insert(w.intents, 1, intent)
	while #w.intents > Wallet.INTENTS_MAX do table.remove(w.intents) end
	ns.ArenaMoney.Expect("wd:" .. nonce, { partner = bank, dir = "in", subjectPrefix = "Arena wallet", mode = mode })
	ns.Arena.Involve("wallet", true)
	return intent
end

-- A lost receipt (the design): the trade that was not credited, told to the bank.
function Wallet.Claim(bank, id, mode)
	mode = Mode(mode)
	local w = MyBank(bank, mode) or { receipts = {} }
	for _, r in ipairs(w.receipts) do
		if r.id == id and (r.state == "sent" or r.state == "mail") then
			r.claimed = Now()
			return ns.Arena.Send("ZL", mode, ("%s~%s~%s~%s~%s"):format(r.epoch or "-", r.id, r.how, B36(r.copper), B36(r.landed or r.t)), { to = bank })
		end
	end
	return nil, "receipt"
end
-- A tester's "Top up" (the design): 100 chips from the rehearsal's bank, at most once an hour;
-- only in a chips rehearsal (never gold, never a copper one).
function Wallet.TopUp(bank)
	local T = ns.ArenaTest
	local ok, r = pcall(function() return type(T) == "table" and type(T.Running) == "function" and T.Running() or nil end)
	if not ok or type(r) ~= "table" or r.money == "p" then return nil, "topup" end
	bank = ns.FullName(bank)
	if not (R() and R().IsBank(bank, "T")) then return nil, "bank" end
	local h = Heads("T")[Lower(bank)]
	if not h or not Wallet.Online(bank, "T") then return nil, "offline" end
	local w = MyBank(bank, "T", true)
	local wait = (w.topUpAt or -math.huge) + Wallet.TOPUP_EVERY - Now()
	if wait > 0 then return nil, "rate", math.ceil(wait) end
	if not ns.Arena.Send("ZQ", "T", ("T~%s~0"):format(h.epoch), { to = bank }) then return nil, "send" end
	w.topUpAt = Now()
	return true
end

function Wallet.AskStatement(bank, mode)
	mode = Mode(mode)
	local h = Heads(mode)[Lower(bank)]
	if not h then return nil, "offline" end
	return ns.Arena.Send("ZQ", mode, ("S~%s~0"):format(h.epoch), { to = bank })
end

function Wallet.Receipts(mode)
	mode = Mode(mode)
	local out = {}
	local m = D().Mine(mode)
	for bank, w in pairs(m and m.banks or {}) do
		for _, r in ipairs(type(w) == "table" and type(w.receipts) == "table" and w.receipts or {}) do
			local copy = {}
			for k, v in pairs(r) do copy[k] = v end
			copy.bank = copy.bank or bank
			copy.claim = (r.state == "sent") and Now() - (r.landed or r.t) >= Wallet.CLAIM_AFTER and Wallet.Online(bank, mode) and not r.claimed
			-- (A mail the bank has not taken a day after it went: "not taken yet".)
			copy.notTaken = r.state == "mail" and Now() - (r.landed or r.t) >= 86400 or nil
			out[#out + 1] = copy
		end
	end
	table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
	return out
end

-- A deposit in the mail is watched for its return (the game sends an untaken mail back after 30
-- days) until the bank credits it; at login again for each still in the mail (the weight rule:
-- nothing is watched without one).
WatchReturn = function(rec, bank, mode)
	ns.ArenaMoney.Expect("back:" .. rec.id, { partner = bank, dir = "in", copper = rec.copper, mode = mode })
end
ns.On("LOGIN", function()
	for _, mode in ipairs({ "L", "T" }) do
		local m = D().Mine(mode)
		for bank, w in pairs(m and type(m.banks) == "table" and m.banks or {}) do
			for _, rec in ipairs(type(w) == "table" and type(w.receipts) == "table" and w.receipts or {}) do
				if rec.state == "mail" and rec.id then WatchReturn(rec, rec.bank or bank, mode) end
			end
		end
	end
end)

-- The player's flows: his deposit landed at the bank (a trade complete, a mail sent), his
-- withdrawal's mail taken (the receipt that confirms it goes to the bank).
local function OnPlayerFlow(r)
	local Mn = ns.ArenaMoney
	for _, key in ipairs(r.keys or {}) do
		local spec = Mn.Expects(key)
		local id = key:match("^dep:(.+)$")
		if id and spec then
			local w = MyBank(spec.partner, spec.mode) or { receipts = {} }
			for _, rec in ipairs(w.receipts) do
				if rec.id == id and (rec.state == "asked" or rec.state == "queued" or rec.state == "called") then
					rec.state, rec.landed = r.kind == "trade" and "sent" or "mail", Now()
					if rec.state == "mail" then WatchReturn(rec, spec.partner, spec.mode) end
				end
			end
			Mn.Forget(key)
		end
		-- A deposit mail the bank never took, back after the game's 30 days: "returned to you".
		id = r.kind == "mailReturned" and key:match("^back:(.+)$")
		if id and spec then
			local w = MyBank(spec.partner, spec.mode) or { receipts = {} }
			for _, rec in ipairs(w.receipts) do
				if rec.id == id and rec.state == "mail" then rec.state, rec.returned = "returned", Now() end
			end
			Mn.Forget(key)
			ns.Arena.Changed()
		end
	end
	-- A withdrawal's mail taken: the intent its subject names (its qseq), once.
	if r.kind ~= "mailTaken" then return end
	local kind, ref = Mn.ReadSubject(r.subject)
	local qseq = kind == "wallet" and tostring(ref or ""):match("^[0-9a-z]+ ([0-9a-z]+)$")
	if not qseq then return end
	for _, key in ipairs(r.keys or {}) do
		local spec = key:match("^wd:") and Mn.Expects(key)
		if spec then
			local w = MyBank(spec.partner, spec.mode) or { intents = {} }
			for _, it in ipairs(w.intents) do
				if it.qseq and B36(it.qseq) == qseq and it.state ~= "taken" then
					it.state, it.taken = "taken", Now()
					D().Receipt({ ref = "W" .. (w.epoch or "-") .. "-" .. qseq, payer = spec.partner, payee = ns.me, copper = r.got, how = "m", mode = spec.mode,
						to = { spec.partner }, auditors = false })
					Mn.Forget("wd:" .. it.nonce)
					ns.Fire("WALLET_PAID", spec.partner, r.got)
					return
				end
			end
		end
	end
end
ns.ArenaMoney.Subscribe(function(r) OnPlayerFlow(r) end)

-- The bank's answers (ZK), only to our own asks.
local function OnAnswer(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local ep, what, answer, value = ns.Arena.Fields(body, 4)
	value = N(value, 0)
	local w = MyBank(sender, mode)
	if not w or not value then return end
	if what == "D" then
		local open
		for i = #w.receipts, 1, -1 do
			local r = w.receipts[i]
			if r.state ~= "credited" and r.state ~= "refused" then
				if answer == "c" then
					if (r.state == "sent" or r.state == "mail" or r.state == "asked" or r.state == "queued" or r.state == "called") and r.copper == value then open = r break end
				else
					if r.state == "asked" or r.state == "queued" or r.state == "called" then open = r break end
				end
			end
		end
		if not open then return end
		if answer == "c" then
			open.state, open.credited = "credited", Now()
			ns.ArenaMoney.Forget("back:" .. open.id)
			ns.Fire("WALLET_CREDITED", ns.FullName(sender), value)
		elseif answer == "q" then
			open.state, open.place = "queued", value
		elseif answer == "ok" then
			open.state = "queued"
		elseif answer == "go" then
			open.state = "called"
			ns.Print(L.WALLET_CALLED:format(ns.DisplayName(sender)))
			ns.Fire("WALLET_CALLED", ns.FullName(sender))
		else
			open.state, open.why = "refused", answer
			ns.ArenaMoney.Forget("dep:" .. open.id)
			ns.Print(L.WALLET_REFUSED:format(ns.DisplayName(sender), Wallet.WhyText(answer)))
			ns.Fire("WALLET_REFUSED", ns.FullName(sender), answer)
		end
	elseif what == "T" then
		-- (A top up: granted, or why not; the chips show in the statement that follows.)
		if answer == "ok" then
			w.topUp = { at = Now(), units = value }
		else
			if answer == "rate" then w.topUpAt = Now() - Wallet.TOPUP_EVERY + value end
			ns.Print(L.WALLET_REFUSED:format(ns.DisplayName(sender), Wallet.WhyText(answer)))
			ns.Fire("WALLET_REFUSED", ns.FullName(sender), answer)
		end
	elseif what == "W" then
		local open
		for _, it in ipairs(w.intents) do if it.state == "asked" then open = it break end end
		if not open then return end
		if answer == "q" then
			open.state, open.qseq = "queued", value
		else
			open.state, open.why = "refused", answer
			ns.ArenaMoney.Forget("wd:" .. open.nonce)
			ns.Print(L.WALLET_REFUSED:format(ns.DisplayName(sender), Wallet.WhyText(answer)))
			ns.Fire("WALLET_REFUSED", ns.FullName(sender), answer)
		end
	end
	ns.Arena.Changed()
end
ns.Comm.Handle("ZK", ns.Arena.Handle("ZK", OnAnswer))

function Wallet.WhyText(why)
	local s = L["WALLET_WHY_" .. tostring(why):upper()]
	return s ~= ("WALLET_WHY_" .. tostring(why):upper()) and s or tostring(why)
end

local function OnCode(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	if not (R() and R().IsBank(sender, mode)) then return end
	local ep, code = ns.Arena.Fields(body, 2)
	if not ep or not N(code, 0) then return end
	local w = MyBank(sender, mode, true)
	w.epoch, w.code = ep, code
	ns.Arena.Changed()
end
ns.Comm.Handle("ZC", ns.Arena.Handle("ZC", OnCode))

-- "Send my winnings after each event" (the design): the player's own switch, kept on his client;
-- when a statement shows gold leaving his bets (a market he bet on settled) and a balance to send,
-- ZW all goes (the mail still waits for the operator's click). Gold only.
function Wallet.AutoWithdraw(on)
	local m = D().Mine("L", true)
	if not m then return false end
	m.autoWithdraw = on and true or nil
	return true
end
local function AutoWithdraw(bank, w, before, mode)
	local m = D().Mine(mode)
	local s = w.statement
	if mode ~= "L" or not m or not m.autoWithdraw or not s or not before then return end
	if s.gesc < (before.gesc or 0) and s.gbal >= Wallet.MIN_WITHDRAW then
		for _, it in ipairs(w.intents) do if it.state == "asked" or it.state == "queued" then return end end
		local _, why = Wallet.Withdraw(bank, "all", mode)
		-- (Asked a moment ago by hand: once the 10 s have passed.)
		if why == "rate" then ns.Arena.After(Wallet.ASK_GAP, "wallet auto " .. bank, function() Wallet.Withdraw(bank, "all", mode) end) end
	end
end

local function OnStatement(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	if not (R() and R().IsBank(sender, mode)) then return end
	local ep, code, g, p, seq, token = ns.Arena.Fields(body, 6)
	local gb, ge, gr = tostring(g):match("^g:([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
	local pb, pe = tostring(p):match("^p:([0-9a-z]+)%.([0-9a-z]+)$")
	if not gb or not pb or not N(seq, 0) then return end
	local w = MyBank(sender, mode, true)
	local before = w.statement
	w.epoch, w.code = ep, code
	w.statement = { gbal = N(gb, 0), gesc = N(ge, 0), gres = N(gr, 0), pbal = N(pb, 0), pesc = N(pe, 0), seq = N(seq, 0), at = Now() }
	if token and token ~= "-" and mode == "L" then w.token = ns.Standing.Keep(sender, token, mode) end
	AutoWithdraw(ns.FullName(sender), w, before, mode)
	ns.Arena.Changed()
end
ns.Comm.Handle("ZS", ns.Arena.Handle("ZS", OnStatement))

-- The bank's record for the standing token (the design): a direct bet paid (ref D), an arbiter's
-- payout received (ref P), on time, as the payee confirms it (his receipt is the evidence).
table.insert(ns.Debts.receiptHooks, function(r, sender, mode)
	local b = Bank()
	if not b or duty ~= "L" or mode ~= "L" or not r.onTime or not Same(sender, r.payee) then return end
	local kind = r.ref:sub(1, 1)
	if kind ~= "D" and kind ~= "P" then return end
	b.earned = type(b.earned) == "table" and b.earned or {}
	if b.earned[r.ref] then return end
	b.earned[r.ref] = Now()
	local n = 0
	for _ in pairs(b.earned) do n = n + 1 end
	if n > 2000 then
		for ref, t in pairs(b.earned) do if Now() - t > 30 * 86400 then b.earned[ref] = nil end end
	end
	local S = ns.Standing
	local payerKey, payeeKey = D().Verified(r.payer) or r.payer, D().Verified(r.payee) or r.payee
	if kind == "D" then
		S.Earn(r.payer, "direct", payeeKey, r.copper, "L")
		S.Earn(r.payee, "direct", payerKey, r.copper, "L")
		local rec = S.RecordOf(r.payer, "L", true)
		if rec then rec.paidMax = math.max(tonumber(rec.paidMax) or 0, r.copper) end
	else
		S.Earn(r.payee, "arbiter", payerKey, r.copper, "L")
	end
	-- (A fresh token at the next statement.)
	local acct = b.accounts[Lower(r.payer)]
	if acct then acct.token = nil end
end)

-- The bank's side of a receipt: the recipient took his withdrawal (c:<wseq>).
table.insert(ns.Debts.receiptHooks, function(r, sender, mode)
	local b = Bank()
	if not b or duty ~= mode or not Same(r.payer, ns.me) then return end
	local ep, qseq = r.ref:match("^W(R?[0-9a-z]+)%-([0-9a-z]+)$")
	qseq = qseq and N(qseq, 1)
	if ep ~= b.epoch or not qseq then return end
	local rec = b.st.wd[qseq]
	if rec and rec.wseq and not (b.st.wseqs[rec.wseq] or {}).confirmed and Same(sender, r.payee) then
		Write(b, { k = "c", wseq = rec.wseq })
	end
end)

---------------------------------------------------------------------------
-- Views: the player's Wallet tab, the bank's console, the auditors' ledgers
---------------------------------------------------------------------------

function Wallet.View(mode)
	mode = Mode(mode)
	local R0 = R()
	local copper = mode == "T" and ns.ArenaMoney.CopperMode() ~= nil
	local currency = mode == "T" and (copper and "g" or "c") or (R0 and R0.Currency() or "g")
	local banks = {}
	for _, b in ipairs(Wallet.Banks(mode)) do
		local s = Wallet.Statement(b.name, mode)
		for k, v in pairs(b) do s[k] = v end
		banks[#banks + 1] = s
	end
	local m = D().Mine(mode)
	local intents = {}
	for bank, w in pairs(m and m.banks or {}) do
		for _, it in ipairs(type(w) == "table" and type(w.intents) == "table" and w.intents or {}) do
			intents[#intents + 1] = { bank = bank, nonce = it.nonce, copper = it.copper, state = it.state, qseq = it.qseq, t = it.t, why = it.why }
		end
	end
	table.sort(intents, function(a, b) return (a.t or 0) > (b.t or 0) end)
	local receipts = Wallet.Receipts(mode)
	local recommended, receiverWhy, receivers = Wallet.DepositRecipient(mode)
	local receiverByName = {}
	for _, row in ipairs(receivers or {}) do receiverByName[Lower(row.name)] = row end
	for _, bank in ipairs(banks) do
		local row = receiverByName[Lower(bank.name)]
		if row then
			bank.assigned, bank.received, bank.pendingCount, bank.eligible = row.assigned, row.received, row.pendingCount, row.eligible
		end
	end
	return { persists = ns.Arena.Persists(), live = R0 and R0.Live() or false, currency = currency,
		unit = Wallet.UNIT[currency] or 1, slot = Slot(currency), rehearsal = mode == "T",
		copper = copper, banks = banks, receipts = receipts, intents = intents, debts = D().View(mode),
		receivers = receivers, recommended = recommended, receiverWhy = receiverWhy,
		token = ns.Standing.Token(mode), autoWithdraw = mode == "L" and m ~= nil and m.autoWithdraw == true }
end

-- "Save now" (the design): offered when no market is open and nothing waits to be sent, so a
-- later crash has less to replay. nil, "open" | "backlog" otherwise.
function Wallet.SaveReady()
	local b = OnDuty()
	if not b then return nil, "duty" end
	for _, m in pairs(b.st.m) do
		if not m.settled then return nil, "open" end
	end
	if b.group or #b.backlog > 0 then return nil, "backlog" end
	return true
end

function Wallet.Console()
	local b = Bank()
	if not b or not duty then return nil end
	local queue = {}
	for i, q in ipairs(b.queue) do queue[i] = { name = q.name, copper = q.copper, called = q.called == true, at = q.at } end
	local waiting, intents = {}, {}
	for _, w in ipairs(Waiting(b)) do
		local acct = w.key and b.accounts[w.key]
		local rec = b.st.wd[w.qseq]
		waiting[#waiting + 1] = { name = acct and acct.name, code = B36(w.code), copper = rec.copper, qseq = w.qseq, state = rec.state, blocked = b.blocked[B36(w.code)] ~= nil }
		if rec.state == "W" then intents[#intents + 1] = { name = acct and acct.name, qseq = w.qseq, copper = rec.copper } end
	end
	local inbox = {}
	local count = GetInboxNumItems and tonumber((GetInboxNumItems())) or 0
	for i = 1, count do
		local T = ns.Treasury
		local mail = T and T.PlayerMail and T.PlayerMail(i)
		if mail and (mail.money or 0) > 0 then
			local name = ns.ArenaMoney.Full(mail.sender)
			local key = Lower(name)
			local why = not mail.returned and DepositWhy(b, key, name, mail.money, b.claimsOf and b.claimsOf[key] and b.claimsOf[key].level or nil, nil, "m") or nil
			inbox[#inbox + 1] = { i = i, sender = name, subject = mail.subject, money = mail.money, returned = mail.returned == true,
				verdict = mail.returned and "returned" or (why and "return" or "take"), why = why }
		end
	end
	local claims, orders = {}, {}
	for _, c in pairs(b.claims) do claims[#claims + 1] = c end
	for _, o in pairs(b.orders) do orders[#orders + 1] = o end
	table.sort(claims, function(x, y) return (x.at or 0) < (y.at or 0) end)
	table.sort(orders, function(x, y) return (x.at or 0) < (y.at or 0) end)
	local markets = {}
	for market, m in pairs(b.st.m) do
		markets[#markets + 1] = { market = market, pool = m.pool, bets = #m.bets, closed = m.closed == true, settled = m.settled == true, cur = m.cur, kind = m.kind }
	end
	table.sort(markets, function(x, y) return x.market < y.market end)
	local o = b.feeRef and D().Find(b.feeRef)
	local n = 0
	for _ in pairs(b.accounts) do n = n + 1 end
	local _, state = HeadBody(b)
	local C0 = ns.Comm
	return {
		mode = duty, name = ns.me, epoch = b.epoch, seq = b.seq, state = state, paused = paused, currency = R() and R().Currency() or "g",
		queue = queue, inbox = inbox, withdrawals = { queue = waiting, intents = intents, blocked = b.blocked },
		fees = { owed = b.st.owed, ref = o and o.ref, due = o and o.due, state = o and o.state, receiver = R() and R().FeeReceiver(), updated = Wallet.ReceiverUpdated() },
		reserve = Wallet.Reserve(), claims = claims, orders = orders, giveBack = b.giveBack, items = b.items, accounts = n, markets = markets,
		health = { queue = C0 and C0.QueueSize and C0.QueueSize() or 0, backlog = #b.backlog, lastSent = b.lastSent, replayed = b.replayed },
		saveNow = Wallet.SaveReady() == true,
	}
end

-- The operator gives back a frozen deposit (the design): a normal withdrawal, q then w.
function Wallet.GiveBack(key)
	local b = OnDuty()
	if not b then return nil, "duty" end
	for i, g in ipairs(b.giveBack) do
		if g.key == key or g.name == key then
			local acct = b.accounts[g.key]
			local a = acct and b.st.acc[acct.code]
			if not a or a.g.bal < g.copper then return nil, "funds" end
			local qseq = Write(b, { k = "q", code = acct.code, copper = g.copper, nonce = "gb" .. B36(i) })
			Seal(b)
			b.wq = b.wq or {}
			b.wq[#b.wq + 1] = { code = acct.code, qseq = qseq, copper = g.copper, at = Now() }
			table.remove(b.giveBack, i)
			return qseq
		end
	end
	return nil, "none"
end

function Wallet.Replica(bank, mode)
	mode = Mode(mode)
	if not (R() and R().Auditor(ns.me, mode)) then return nil end
	local rep = Replica(bank, mode)
	if not rep then return nil end
	local accounts = {}
	for code, a in pairs(rep.st.acc) do
		local info = rep.names[B36(code)]
		accounts[#accounts + 1] = { name = info and ns.Arena.Mask(info.name) or nil, code = B36(code), g = { bal = a.g.bal, reserved = a.g.reserved, escrow = a.g.escrow },
			p = { bal = a.p.bal, escrow = a.p.escrow } }
	end
	table.sort(accounts, function(x, y) return (x.name or x.code) < (y.name or y.code) end)
	local t = Wallet.Totals(rep.st)
	return { name = rep.name, epoch = rep.epoch, seq = rep.seq, head = rep.head:sub(1, 16), matches = rep.matches, verified = rep.snap, accounts = accounts,
		liabilities = { g = t.g, p = t.p }, owed = t.owed, float = t.float, reserve = rep.reserve, attest = rep.attest, flags = rep.flags,
		gap = rep.entries[rep.seq + 1] == nil and rep.zh and rep.zh.seq > rep.seq or false, kb = rep.kb ~= nil }
end
-- One market as an auditor's replica holds it (the design, late bets are visible): at x, auditors
-- require the b sums per outcome to equal the pools of the urgent L book (BO state L, the markets'), and
-- hold the market with BV H when they differ. { cur, kind, closes, pools = { [o] = units }, pool,
-- bets, closed, settled, result, late (bet entries flagged at or after the lock) }, or nil.
function Wallet.ReplicaMarket(bank, eid, idx, mode)
	mode = Mode(mode)
	if not (R() and R().Auditor(ns.me, mode)) then return nil end
	local rep = Replica(bank, mode)
	local market = Wallet.MarketId(eid, idx)
	local m = rep and rep.st.m[market]
	if not m then return nil end
	local pools = {}
	for o, units in pairs(m.pools or {}) do pools[o] = units end
	local late = 0
	for _, f in ipairs(rep.flags or {}) do if f.what == "late" and f.market == market then late = late + 1 end end
	return { cur = m.cur, kind = m.kind, closes = m.closes, pools = pools, pool = m.pool, bets = #m.bets, closed = m.closed == true,
		settled = m.settled == true, result = m.result, late = late }
end

function Wallet.Ledgers(mode)
	mode = Mode(mode)
	if not (R() and R().Auditor(ns.me, mode)) then return nil end
	local out = {}
	for key in pairs(Replicas(mode)) do out[#out + 1] = Wallet.Replica(key, mode) end
	table.sort(out, function(x, y) return tostring(x.name) < tostring(y.name) end)
	local St = ns.Stakes
	return { banks = out, arbiters = St and St.Books and St.Books(mode) or {}, debts = D().Ledger(mode) }
end

-- The reserve attestation (the design, in-game check 18): an auditor opens a trade with the bank,
-- the operator puts the claimed reserve in the window; this client reads the bank's gold there
-- and the trade is cancelled. Nothing moves.
function Wallet.Attest(bank, mode)
	mode = Mode(mode)
	if not (R() and R().Auditor(ns.me, mode)) then return nil, "auditor" end
	ns.ArenaMoney.Expect("attest", { partner = bank, dir = "both", attest = true, mode = mode })
	return true
end
function Wallet.AttestRead(bank, copper, mode)
	local rep = Replica(bank, Mode(mode))
	if not rep then return nil end
	rep.attest = { copper = copper, at = Now() }
	ns.ArenaMoney.Forget("attest")
	ns.Arena.Changed()
	return rep.attest
end
ns.ArenaMoney.Subscribe(function(r)
	if r.kind ~= "tradeView" then return end
	local spec = ns.ArenaMoney.Expects("attest")
	if spec and Same(spec.partner, r.partner) then Wallet.AttestRead(r.partner, r.got, spec.mode) end
end)

-- The crash drill (the sim, the design): the bank loses what it did not send; the replay from
-- the replicas brings it back. Here: the unsent backlog dropped from a copy of the ledger.
function Wallet.Drill()
	local b = OnDuty()
	if not b then return nil, "duty" end
	Seal(b)
	local lost = #b.backlog
	b.backlog = {}
	return lost
end

---------------------------------------------------------------------------
-- The bank's ledger in a backup (the design; Backup.arenaChecks.bank): a closer look at the
-- part before it is restored, where no ledger is held (Backup.ApplyArena never lowers a seq). Its
-- secret and blinding key, epoch, seq and MAC, and every table the bank reads; each kept entry
-- chains under the secret to the saved MAC, so a damaged or edited copy is left out. The replay
-- from the auditors (ZQ~R) then brings it up to date.
---------------------------------------------------------------------------

local function HexOf(v, n) return type(v) == "string" and #v == n and v:find("^[0-9a-f]+$") ~= nil end
Wallet.BACKUP_SEQ_MAX = 1000000 -- a bank's ledger seq a backup may carry (the design holds 5,000 entries)
function Wallet.CheckBackup(v)
	if type(v) ~= "table" or not HexOf(v.secret, 64) or not HexOf(v.kb, 64) or not HexOf(v.head, 64) then return nil end
	if type(v.epoch) ~= "string" or not v.epoch:find("^R?[0-9a-z]+$") or #v.epoch > 12 then return nil end
	local seq = tonumber(v.seq)
	-- (1.2.0: bounded: a crafted text's huge seq would hang the client in the chain's loop.)
	if not seq or seq < 0 or seq % 1 ~= 0 or seq > Wallet.BACKUP_SEQ_MAX or type(v.mac) ~= "string" then return nil end
	for _, k in ipairs({ "accounts", "entries", "macs", "backlog", "st" }) do
		if type(v[k]) ~= "table" then return nil end
	end
	if type(v.st.acc) ~= "table" or type(v.st.m) ~= "table" then return nil end
	-- (The chain: the entries kept, from the first one whose MAC before it is known, to the last.)
	local secret = Unhex(v.secret)
	local prev = "0" -- (the MAC before the first entry)
	for n = 1, seq do
		local text = type(v.full) == "table" and v.full[n] or v.entries[n]
		if text ~= nil and prev ~= nil then
			if type(text) ~= "string" or Wallet.Mac(secret, prev, n, text) ~= v.macs[n] then return nil end
		end
		prev = v.macs[n]
	end
	if seq > 0 and prev ~= nil and prev ~= v.mac then return nil end
	return v
end
do
	local B = ns.Backup
	if type(B) == "table" and type(B.arenaChecks) == "table" then B.arenaChecks.bank = Wallet.CheckBackup end
end

---------------------------------------------------------------------------
-- The buttons (the design: every screen button through Arena.Can and Arena.Do). A player's:
--   "wallet.deposit" (bank, how, copper, mode), "wallet.fill" (id, mode), "wallet.withdraw" (bank,
--   copper|"all", mode), "wallet.claim" (bank, id, mode), "wallet.statement" (bank, mode),
--   "wallet.autowithdraw" (on), "wallet.topup" (bank: a chips rehearsal's tester).
-- The bank's (on its duty): "bank.duty" (on, mode), "bank.pause" (on), "bank.call", "bank.pay",
--   "bank.paytrade" (qseq), "bank.payguild", "bank.giveback" (key), "bank.accept" (nonce),
--   "bank.refuse" (nonce), "bank.order" (nonce), "bank.reconcile" (qseq, sent), "bank.checkpoint",
--   "bank.reseat" (oldEpoch | auditorA, auditorB), "bank.save" (Wallet.SaveReady: the reload).
-- An auditor's: "audit.attest" (bank), "audit.order" (bank, code, sign, copper, why, ref).
---------------------------------------------------------------------------

local function OnBankDuty() if not duty then return false, "duty" end return true end
local function Persisting(mode)
	if Mode(mode) == "L" and not ns.Arena.Persists() then return false, "persist" end
	return true
end
local A = ns.Arena
A.Action("wallet.deposit", function(bank, how, copper, mode)
	local why = MayDeposit(ns.FullName(bank or ""), how, math.floor(tonumber(copper) or 0), Mode(mode))
	if why then return false, why end
	return true
end, function(...) return Wallet.Deposit(...) end)
A.Action("wallet.fill", nil, function(...) return Wallet.FillDeposit(...) end)
A.Action("wallet.withdraw", function(bank, amount, mode)
	local R0 = R()
	if not (R0 and R0.IsBank(bank, Mode(mode))) then return false, "bank" end
	if not Wallet.Online(bank, mode) then return false, "offline" end
	return Persisting(mode)
end, function(...) return Wallet.Withdraw(...) end)
A.Action("wallet.claim", nil, function(...) return Wallet.Claim(...) end)
A.Action("wallet.statement", nil, function(...) return Wallet.AskStatement(...) end)
A.Action("wallet.topup", nil, function(bank) return Wallet.TopUp(bank) end)
A.Action("wallet.autowithdraw", nil, function(on) return Wallet.AutoWithdraw(on) end)
A.Action("bank.duty", function(on, mode)
	if not on then return true end
	local R0 = R()
	if not (R0 and R0.IsBank(ns.me, Mode(mode))) then return false, "unlisted" end
	if Mode(mode) == "L" and R0.Currency() == "g" then return Persisting(mode) end
	return true
end, function(...) return Wallet.Duty(...) end)
A.Action("bank.pause", OnBankDuty, function(on) return Wallet.Pause(on) end)
A.Action("bank.call", OnBankDuty, function() return Wallet.CallNext() end)
A.Action("bank.pay", OnBankDuty, function() return Wallet.PayNext() end)
A.Action("bank.paytrade", OnBankDuty, function(qseq) return Wallet.PayTrade(qseq) end)
A.Action("bank.payguild", function()
	if not duty then return false, "duty" end
	if not (R() and R().FeeReceiver()) then return false, "receiver" end
	if duty == "L" and not Wallet.ReceiverUpdated() then return false, "updated" end
	return true
end, function() return Wallet.PayGuild() end)
A.Action("bank.giveback", OnBankDuty, function(key) return Wallet.GiveBack(key) end)
A.Action("bank.accept", OnBankDuty, function(nonce) return Wallet.Accept(nonce) end)
A.Action("bank.refuse", OnBankDuty, function(nonce) return Wallet.Refuse(nonce) end)
A.Action("bank.order", OnBankDuty, function(nonce) return Wallet.ApplyOrder(nonce) end)
A.Action("bank.reconcile", OnBankDuty, function(qseq, sent) return Wallet.Reconcile(qseq, sent) end)
A.Action("bank.checkpoint", OnBankDuty, function() return Wallet.Checkpoint() end)
-- (The operator's own click reloads the interface: the game saves only at logout or a reload.)
A.Action("bank.save", function() return Wallet.SaveReady() end, function()
	local reload = ReloadUI or (C_UI and C_UI.Reload) -- gp:reload-button
	if type(reload) ~= "function" then return nil, "reload" end
	reload()
	return true
end)
A.Action("bank.reseat", OnBankDuty, function(a, b2)
	if b2 == nil then return Wallet.ReseatAsk(a) end
	return Wallet.Reseat(a, b2)
end)
A.Action("audit.attest", function() return R() ~= nil and R().Auditor(ns.me, "L"), "auditor" end, function(bank) return Wallet.Attest(bank) end)
A.Action("audit.order", function() return R() ~= nil and (R().Auditor(ns.me, "L") or R().IsKing(ns.me)), "auditor" end,
	function(...) return Wallet.Order(...) end)
