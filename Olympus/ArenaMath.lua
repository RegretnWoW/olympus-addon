local ADDON, ns = ...

-- The Blood Arena's money arithmetic (1.2): pari-mutuel pools, odds, payouts in copper, the fee
-- (6% of the money won by default: 4% to the guild and 2% to the arbiter, or all of it to the
-- guild when no arbiter is paid), refunds, the bracket pool, and the limits that grow with a
-- player's standing.
-- Pure functions: no events, no messages, no saved data, no game API. Money is whole copper
-- everywhere; nothing here ever makes a fraction of a copper, and a settlement pays out exactly
-- what came in.
-- This is the one implementation of the markets section's formula (the design), the money
-- section's Settle (the design) and its standing caps (as the design amends them). The bank,
-- the arbiter, the opponent in a direct bet, every client replaying the ledger and each bettor
-- checking his own ticket must all get the same copper, so nothing else should compute these
-- again: a second formula that rounds another way makes a false dispute.
-- Every list here (bets, entries, winners, debts, a history) is a plain list, keys 1..n. A table
-- keyed any other way (by a slip's nonce, say), or with a hole, is refused whole: read with
-- ipairs it would look shorter than it is and drop stakes without a word.
--
-- The settlement (the design), for the winning outcomes that had bets (k' of them):
--   W = their pools; L = the rest of the pool (the money won); cut = floor(L * fee / 10000);
--   arbFee = floor(L * arbiterFee / 10000); D = L - cut; share = floor(D / k'), each such
--   outcome's part; a bet of s on one of them is paid s + floor(share * s / that outcome's pool),
--   every other bet 0. The guild gets cut - arbFee and every copper of rounding (the split of D
--   between outcomes, and each bet's), and the arbiter's part too when it goes to the guild.
--   Refunded instead, every stake back and no fee: a void; no bets ("empty"); bets on one outcome
--   only ("onesided"); nobody on any winner ("nobody"); every bet on a winner ("allwon").
--
-- THE CONTRACT (the design). Every copper figure is a whole number; malformed input returns nil
-- and a short code (never a guess).
--
-- The fee, as the contract functions take it: nil for the defaults (600, of which 200 is the
-- arbiter's), or one of three forms, all with the optional to = "g" | "a" | nil:
--   { feeBp, arbBp, to }            by position, the WHOLE fee first, then the arbiter's part of
--                                   it, as the ledger's n:<...>:<feeBp>:<arbBp>:... and the
--                                   King's T1~O ~feeBp~arbBp carry them ({ 600, 200 } is 6%);
--   { feeBp = , arbBp = , to = }    the same by name;
--   { g = , a = , to = }            the design's notation: the guild's part and the arbiter's
--                                   (f = g + a; { g = 400, a = 200 } is 6%).
--   A field left out takes its default (feeBp 600, arbBp 200; g 400, a 200). A number is floored
--   and clamped: the whole fee to 0..FEE_CAP, then the arbiter's part to 0..the whole, the guild
--   keeping the rest. to = "g" moves the arbiter's part to the guild (the King arbitrates and
--   holds no gold, or no arbiter is paid); "a" or nil pays it to the arbiter. Anything else is
--   refused ("fee"): a rate that is not a number, another `to`, an unknown field, or two forms
--   mixed ({ 600, g = 400 }). A typo must not move the arbiter's part, nor charge a fee nobody
--   set, and a whole fee must never be read as the guild's part (which would charge 8%).
--
-- Exact arithmetic (the design)
--   ArenaMath.IDiv(n, d) -> floor(n / d), exactly (whole 0 <= n < 2^52, whole 1 <= d <= 2^52;
--       nil outside those)
--   ArenaMath.MulDiv(a, b, c) -> floor(a * b / c), exactly (whole a, b >= 0; 1 <= c <= 2^44;
--       nil outside those, or when the result would reach 2^53)
--   ArenaMath.Part(copper, bps) -> floor(copper * bps / 10000), exactly
--
-- Settling (the design)
--   ArenaMath.Settle(bets, winners, fee, scratched) -> result | nil, why[, index]
--       bets: { { o = outcome, s = copper, who = name|nil }, ... } in ledger order; s from 1 to
--         MAX_COPPER; the pool at most MAX_POOL.
--       An outcome (o, and every key of winners, scratched and the odds' pools) is a non-empty
--         string or a whole number from 0 to MAX_KEY, never VOID. It is compared in the ledger's
--         text form: the number 7 and the ledger's "7" are one outcome, so bets read from b
--         entries and a winner turned into a number still settle; text is never read as a number
--         ("07" is not 7), and one outcome given twice (7 and "7" in one set) is refused.
--       winners: a set { [o] = true }, a list { o, ... }, one outcome, or ArenaMath.VOID ("V", as
--         the ledger's x writes a void). A winner nobody backed is fine (it passes its part on).
--       scratched (optional, the same shapes, never VOID): outcomes whose bets get their stake
--         back and leave the pools (a tournament entrant scratched, a stage the bracket can't
--         produce); none of them may be a winner.
--       result = { payouts = { [i] = copper },   each bet's payout, in the bets' order
--                  guildFee, arbFee,             the guild's (the rounding in it) and the arbiter's
--                  refund = nil | "void" | "empty" | "onesided" | "nobody" | "allwon",
--                  byWho = { [who] = copper },   each named bettor's payouts summed
--                  pool,                         every stake, the scratched ones too
--                  scratchPool,                  the scratched stakes (paid back)
--                  winPool, losePool,            the rest's winning and losing sides (both 0 on a
--                                                void); pool = winPool + losePool + scratchPool
--                                                otherwise
--                  cut, share, remainder }       the whole fee, each winning outcome's part of
--                                                what is left, the rounding (in guildFee)
--       Always: the sum of payouts + guildFee + arbFee == pool (asserted). A scratched bet is paid
--       its stake even when the rest settles; refund names the rest.
--       why: "bets", "bet" (index), "pool", "winners", "scratched", "fee".
--   ArenaMath.Pickem(entries, results, rounds, fee) -> result | nil, why[, index]
--       The bracket pool (the design), from the ledger: entries are its b bets,
--       { { o = "p<hex>", s = copper, who = name|nil }, ... }, every one the same stake; results
--       its x, "P<hex>"; rounds: the bracket's rounds (1..PICK_ROUNDS; 2^rounds slots). A pick is
--       one bit per match, 0 when the upper slot wins, in bracket order (round 1 top to bottom,
--       then round 2, ...), written in hex most significant bit first, padded with 0 bits to a
--       whole digit (Picks, PickHex). A pick is right when the fighter it sends through wins that
--       match, and is worth 2^(round - 1). The best score splits the pool: each such entry gets
--       its stake plus an even part of the winnings after the fee (the rounding to the guild).
--       result = { scores = { [i] = points }, top, winners = { i, ... },
--                  payouts, guildFee, arbFee, refund = nil | "empty" | "tied", byWho, pool, ... }
--       "tied": every entry has the same score (all 0 too), and every stake comes back.
--       why: "entries", "entry" (index: its picks, stake or name), "stake" (index: not the first
--       entry's), "results", "rounds", "fee", "pool".
--   ArenaMath.Picks(hex, rounds) -> { [i] = 0|1 } | nil, why ("picks", "rounds")
--       a bracket's picks (or result) from its hex, with or without the leading p or P; the
--       length must be exact and the padding bits 0.
--   ArenaMath.PickHex(bits) -> hex | nil     the other way (lower case, no leading p): 2^r - 1 bits
--   ArenaMath.PickScore(picks, results, rounds) -> points | nil, why    one entry's score
--   ArenaMath.Direct(sw, sl, fee) -> { loserPays, guildFee, kept } | nil, why ("stake", "fee")
--       a direct 1v1 (the design): the loser owes the winner his own stake sl by trade; the
--       winner owes the guild the whole fee (feeBp, or g + a: there is no arbiter) on it, and
--       keeps the rest.
--
-- Odds (the design): estimates that never promise more than a settlement pays
--   pools = { [o] = copper } (0 or more each, the sum at most MAX_POOL), keyed by outcomes as
--   Settle takes them.
--   ArenaMath.Odds(pools, o, fee) -> hundredths | nil[, why]
--       what 1 gold on o returns if o wins, at the pools as they stand, in hundredths (241 is
--       "2.41"): floor(100 x the exact payout of a 1-gold ticket already in the pool / 1 gold).
--       nil alone for an outcome nobody backed yet ("the first bet sets the odds"); 100 when
--       nothing is on the other side (it would be refunded). why: "pools", "outcome", "fee".
--   ArenaMath.OddsAtLeast(pools, o, k, fee) -> hundredths | nil[, why]
--       the same with k places ("at least"): the other k - 1 winners taken to be the most backed
--       outcomes, which leaves the least money lost and splits it most ways. why: also "k".
--   ArenaMath.Preview(pools, o, s, fee, k) -> copper | nil, why
--       what a new bet of s on o would be paid if o wins (the least, with k places; k nil is 1),
--       were it the last bet: s + floor(D' * s / (P_o + s)). why: "pools", "outcome", "copper",
--       "pool" (it would pass MAX_POOL), "k", "fee".
--   ArenaMath.OddsText(hundredths) -> "2.41x"
--
-- Limits (the design, as amended)
--   record = { points = n, probation = true|nil, open = debts, dispute = disputes,
--              paidMax = copper }: standing points (volume: see Earns); probation: a late payment
--     in the last 7 days (a tier lower); open: debts, fees or claims not yet paid; dispute: an
--     open direct-mode dispute against him (his direct cap only); paidMax: the largest direct debt
--     he paid on time. nil is a newcomer. open and dispute count unless nil, false, a number
--     <= 0 or an empty table (Debts.Open() when nothing is owed): any other doubt goes against him.
--   ArenaMath.BetCap(record, kind, scalePct, limit) -> copper[, why]
--       kind: "bet" (a wallet bet, per market), "balance" (a wallet's balance), "daily"
--       (deposits a day) or "direct" (a direct bet). The tier is floor(points / 5), at most 5
--       (a tier lower on probation); the table's row times the King's scalePct (nil: 100;
--       clamped to SCALE_LOW..SCALE_HIGH), under the code ceiling; "direct" needs DIRECT_NEED
--       points and is DirectCap over DirectTier. limit: a lower ceiling the King set (maxBet,
--       directMax); it never raises a cap. 0 comes with why: "open", "dispute", "history",
--       "probation", "record", "scale", "limit" (malformed ones are refused, never read as
--       nothing). Another kind: nil, "kind" (an arbiter's holding cap comes from the King's T1~M
--       word, not from points).
--   ArenaMath.DirectTier(record) -> tier | NO_DIRECT, why
--       the tier a bank writes in a standing token: NO_DIRECT (-1) under DIRECT_NEED points, with
--       an open debt or dispute, or on probation at tier 0 (a tier lower than the row's 1 gold
--       is its "none"; a reading of the design for Daniel to confirm). why: "history", "open",
--       "dispute", "probation", "record".
--   ArenaMath.DirectCap(tier, paidMax, scalePct, limit) -> copper[, why]
--       min(the tier's direct cap, max(1 gold, 2 x paidMax)): 1 gold before any direct debt
--       paid, then at most twice the largest paid on time. tier NO_DIRECT: 0, "history"; why
--       also "tier", "paidMax", "scale", "limit".
--   ArenaMath.Earns(stake, tierCap, minBet) -> true | false, why
--       whether a settled stake earns a standing point: stake >= max(minBet, tierCap / 4)
--       (minBet nil: MIN_BET). why: "min", "small", "stake", "cap", "rules" (malformed minBet).
--   ArenaMath.Tier(kind, record) -> 0..TIER_TOP | nil, why ("kind", "record")
--       the table's row (a tier lower on probation, never below 0); whether he may bet direct at
--       all is DirectTier's.
--   ArenaMath.Points(history) -> points | nil, "history"[, index]
--       a record in time order: true for a payment on time (+1), false for a late one (halves).
--   ArenaMath.HoldAdvice(record, scalePct) -> copper[, why]
--       the design's holding cap from an arbiter's own points: advice for auditors only. The
--       cap each party enforces is the King's (T1~M).
--   ArenaMath.Room(cap, held) -> copper[, why]    what an arbiter may still take under his
--       T1~M cap in copper (never below 0). cap nil: the arbiter is on T1~M without a cap, which
--       reads as HOLD_DEFAULT (100 gold, the design). why: "cap", "held" (malformed: 0).
--   ArenaMath.BetOk(copper, cap, staked, rules) -> true | false, why
--       a new bet, the bank's checks 5, 12 and 13 (the design). cap: the most this player may
--       have on this market (BetCap, with the King's maxBet as its limit); staked: what he has
--       on it already (Staked), so the cap holds for the market and not for each slip. For a
--       direct bet: BetCap(record, "direct"), and staked = his direct bets not yet paid.
--       rules (optional): { minBet = copper (MIN_BET_LOW..MIN_BET_HIGH; nil: MIN_BET),
--         maxDay = copper, today = what he bet today (every market),
--         maxPool = copper, pool = the market's pool now }.
--       why: "copper" (not whole, or past MAX_COPPER), "silver" (not whole silver), "min",
--       "staked", "cap", "day", "pool", "rules" (malformed).
--   ArenaMath.NetOff(copper, debts) -> paid, left | nil, why[, index]
--       a debtor's winnings go to his debts first (debts: copper owed, oldest first); paid[i]
--       is what goes to debt i, left what is still his. why: "copper", "debts".
--
-- A market object, for a bank or a screen that holds one (the same formula underneath):
--   { outcomes = { key, ... },      2 to MAX_OUTCOMES distinct keys, strings or numbers
--     places = k or nil,            how many outcomes win: nil or 1, or k (fewer than the
--                                   outcomes) for "reaches the final" (2), "semifinal" (4) and
--                                   "quarterfinal" (8)
--     mode = "arbiter" | "direct",  "arbiter": the arbiter is paid his part of the fee;
--                                   "direct": the whole fee is the guild's (a direct bet, or a
--                                   market the King arbitrates: he holds no gold and takes no part)
--     fee = bps or nil,             the whole fee, in basis points of the money won; nil:
--                                   DEFAULT_FEE; a number is clamped to 0..FEE_CAP
--     arbiterFee = bps or nil,      the arbiter's part of that fee; nil: DEFAULT_ARBITER_FEE; a
--                                   number is clamped to 0..fee; unused in "direct"
--                                   (the caller freezes both when the market opens)
--     bets = { { who = "Name-Realm", outcome = key, copper = n }, ... } }   a list, book order
--   who is whatever the caller keys its players by (Name-Realm or GUID). A player may bet more
--   than once, on one outcome or several: each bet is a ticket of its own, paid on its own, and
--   his payout is the sum of his tickets'.
--   ArenaMath.Check(market) -> true | nil, why[, index]
--       why: "market", "outcomes", "places", "mode", "fee", "bets", "bet" (index: which one), "pool".
--   ArenaMath.Pools(market) -> pools, total, bettors | nil, why[, index]
--       pools[key]: copper on each outcome (0 when none); total: the whole pool;
--       bettors[key]: how many players backed each outcome.
--   ArenaMath.Staked(market, who) -> copper | nil, why[, index]
--       what who has on the market so far, every outcome (0 if nothing); why: Check's, or "who".
--   ArenaMath.MarketOdds(market) -> { [key] = hundredths } | nil, why[, index]
--       Odds for every outcome (OddsAtLeast with several places); nil for one nobody backed.
--   ArenaMath.Quote(market, key, copper) -> copper | nil, why[, index]
--       Preview on the market. why: Check's, or "outcome" (not the market's), "copper" (not
--       whole, or past MAX_COPPER), "pool" (the pool would pass MAX_POOL).
--   ArenaMath.SettleMarket(market, winners) -> result | nil, why[, index]
--       winners: the winning key, or a list of exactly `places` distinct keys.
--       why: Check's, or "outcome" (a key not the market's, a key twice, or the wrong count).
--   ArenaMath.Void(market) -> result | nil, why[, index]      every stake back, no fee
--       result = { winners = { key, ... } (empty for a void), outcome = the key if one place,
--                  refund = true|false, why = nil | "void" | "empty" | "onesided" | "nobody" | "allwon",
--                  pool, winPool, losePool, share (each winning outcome's part after the fee),
--                  bets = { [i] = copper },       each bet's payout, in the market's order
--                  payouts = { [who] = copper },  every bettor, the sum of his bets' (0: lost)
--                  stakes = { [who] = copper },   what each one put in, all outcomes
--                  cut, guildFee, arbiter,        cut = guildFee + arbiter
--                  remainder, guild }             guild = guildFee + remainder
--       Always: the sum of payouts + guild + arbiter == pool (asserted).
--   ArenaMath.Fee(bps) -> bps | nil, "fee"         the whole fee to use: nil gives DEFAULT_FEE, a
--       number is floored and clamped to 0..FEE_CAP, anything else is refused.
--   ArenaMath.Split(fee, arbiterFee, mode) -> guildBps, arbiterBps | nil, why ("fee", "mode")
--       the fee's rates after the defaults and the clamps (600/200 "arbiter": 400, 200).
--   ArenaMath.Fees(copper, fee, arbiterFee, mode) -> guild, arbiter, net | nil, why
--       the fee on copper won, in copper: guild + arbiter is floor(copper * fee / 10000), the
--       arbiter's floor(copper * arbiterFee / 10000), and net what the winner keeps of it.
--       why: "copper" (not whole, or past MAX_POOL), "fee", "mode".

local ArenaMath = {}
ns.ArenaMath = ArenaMath

local floor = math.floor

ArenaMath.SILVER = 100
ArenaMath.GOLD = 10000
local SILVER, GOLD = ArenaMath.SILVER, ArenaMath.GOLD

ArenaMath.MIN_BET = 10 * SILVER             -- the smallest bet unless the King sets another (about 10s)
ArenaMath.MIN_BET_LOW = SILVER              -- what he may set: 1s ...
ArenaMath.MIN_BET_HIGH = 10 * GOLD          -- ... to 10g (the money section's bounds)
ArenaMath.MAX_COPPER = 2147483647           -- one bet's most: the game's gold cap (214,748g)
ArenaMath.MAX_POOL = 2 ^ 43                 -- a market's most (879 million gold, never reached: it
                                            -- keeps MulDiv's long division exact)
ArenaMath.MAX_OUTCOMES = 64                 -- a tournament's slots, one outcome each (64 at most)
ArenaMath.BPS = 10000                       -- basis points in the whole
local BPS = ArenaMath.BPS

-- The fee, in basis points of the money won. The King may set the rates; the market freezes
-- them when it opens, so a later change never touches a market that already has bets.
ArenaMath.DEFAULT_FEE = 600                 -- 6% ...
ArenaMath.DEFAULT_ARBITER_FEE = 200         -- ... of which 2% is the arbiter's ...
ArenaMath.DEFAULT_GUILD_FEE = 400           -- ... and 4% the guild's
ArenaMath.FEE_CAP = 1000                    -- 10%, the hard cap

-- The ledger's x writes a void as V, so V is never an outcome.
ArenaMath.VOID = "V"
local VOID = ArenaMath.VOID

-- A bracket pool's brackets: 2 to 64 slots (1 to 6 rounds).
ArenaMath.PICK_ROUNDS = 6

local TWO52, TWO53 = 2 ^ 52, 2 ^ 53

-- A whole number from 0 up to where doubles stop being exact (NaN and the infinities fail).
local function Whole(n) return type(n) == "number" and n == floor(n) and n >= 0 and n < TWO53 end

-- A whole number of copper, from 1 to the most one bet may be.
local function Copper(n) return Whole(n) and n >= 1 and n <= ArenaMath.MAX_COPPER end

-- A number that is one (not NaN).
local function Number(n) return type(n) == "number" and n == n end

-- How many entries a plain list has, or nil when t is not one: its keys must be exactly 1..n.
local function List(t)
	if type(t) ~= "table" then return nil end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do
		if t[i] == nil then return nil end
	end
	return n
end

-- An outcome's key in a market object: a non-empty string, or a finite number.
local function Key(k)
	if type(k) == "string" then return k ~= "" end
	return type(k) == "number" and k == k and k ~= math.huge and k ~= -math.huge
end

-- An outcome's key in the contract functions, as the ledger writes it (its b selections and x
-- winners are text): a non-empty string as it is, a whole number from 0 to MAX_KEY in decimal.
-- So the slot 7 and the ledger's "7" are one outcome, and a caller that turned one side into
-- numbers and not the other still settles: compared raw, no bet would be on a winner, and the
-- market would be refunded whole without a word. Text is never read as a number ("07" is not 7).
-- nil for anything else.
ArenaMath.MAX_KEY = 2147483647
local function Canon(k)
	if type(k) == "string" then
		if k == "" then return nil end
		return k
	end
	if Whole(k) and k <= ArenaMath.MAX_KEY then return ("%d"):format(k) end
	return nil
end

-- A flag that counts unless it is nil, false, a number <= 0 or an empty table: a debt or a
-- dispute sent as a count, a list with anything in it, text or true all count, so the doubt goes
-- against the player, never for him. An empty list (Debts.Open() when nothing is owed) is none.
local function Flag(v)
	if type(v) == "table" then return next(v) ~= nil end
	return v ~= nil and v ~= false and not (Number(v) and v <= 0)
end

---------------------------------------------------------------------------
-- Exact arithmetic
---------------------------------------------------------------------------

-- A Lua number is exact for whole numbers below 2^53 only. A bet's part of the winnings is
-- floor(share * stake / pool), and that product passes 2^53 once a pool holds about 9,500 gold
-- (10,000g * 10,000g in copper is 10^16): the division can then be off by a copper, and the
-- payouts would not add up to the pool (the tests hold such a pool). MulDiv keeps the product in
-- bytes and divides it by long division, where every step stays below 2^52.

-- floor(p / c) for whole p < 2^52 and c >= 1: the float division may round up across a whole
-- number, and one correction puts it right (its error is under one).
local function Div(p, c)
	local q = floor(p / c)
	local r = p - q * c
	if r < 0 then q = q - 1 elseif r >= c then q = q + 1 end
	return q
end

local function Bytes(n)
	local out = {}
	while n > 0 do
		local rest = floor(n / 256)
		out[#out + 1] = n - rest * 256
		n = rest
	end
	return out
end

local MULDIV_C = 2 ^ 44

local function MulDiv(a, b, c)
	local p = a * b
	if p < TWO52 then return Div(p, c) end
	local A, B, P = Bytes(a), Bytes(b), {}
	for i = 1, #A + #B do P[i] = 0 end
	for i = 1, #A do
		local carry = 0
		for j = 1, #B do
			local v = P[i + j - 1] + A[i] * B[j] + carry
			carry = floor(v / 256)
			P[i + j - 1] = v - carry * 256
		end
		local k = i + #B
		while carry > 0 do
			local v = P[k] + carry
			carry = floor(v / 256)
			P[k] = v - carry * 256
			k = k + 1
		end
	end
	local q, r = 0, 0
	for i = #P, 1, -1 do
		r = r * 256 + P[i]
		local d = Div(r, c)
		r = r - d * c
		q = q * 256 + d
	end
	return q
end

function ArenaMath.IDiv(n, d)
	if not (Whole(n) and Whole(d)) or n >= TWO52 or d < 1 or d > TWO52 then return nil end
	return Div(n, d)
end

-- nil when an argument is out of its range, or when the result would not be exact (2^53 or more).
function ArenaMath.MulDiv(a, b, c)
	if not (Whole(a) and Whole(b) and Whole(c)) or c < 1 or c > MULDIV_C then return nil end
	local q = MulDiv(a, b, c)
	if q >= TWO53 then return nil end
	return q
end

function ArenaMath.Part(copper, bps)
	return ArenaMath.MulDiv(copper, bps, BPS)
end

---------------------------------------------------------------------------
-- The fee
---------------------------------------------------------------------------

-- Whole basis points, within lo..hi.
local function Clamp(n, lo, hi)
	n = floor(n)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- A market object's two rates: the whole fee and the arbiter's part of it. A rate that is set
-- but is not a number is refused, never replaced by the default, and so is a mode that is
-- neither "arbiter" nor "direct".
local function Rates(fee, arbiterFee, mode)
	if fee ~= nil and not Number(fee) then return nil, "fee" end
	if arbiterFee ~= nil and not Number(arbiterFee) then return nil, "fee" end
	if mode ~= "arbiter" and mode ~= "direct" then return nil, "mode" end
	local total = Clamp(fee == nil and ArenaMath.DEFAULT_FEE or fee, 0, ArenaMath.FEE_CAP)
	if mode ~= "arbiter" then return total, 0 end
	return total, Clamp(arbiterFee == nil and ArenaMath.DEFAULT_ARBITER_FEE or arbiterFee, 0, total)
end

-- Which form each field of a contract fee belongs to (see the top); `to` goes with any.
local FEE_FIELDS = { [1] = "ledger", [2] = "ledger", feeBp = "named", arbBp = "named", g = "guild", a = "guild",
	[3] = "to", to = "to" }

-- The contract's fee (see the top): the whole fee and the arbiter's part of it (0 when
-- to = "g"), or nil.
local function FeeRates(fee)
	if fee == nil then return ArenaMath.DEFAULT_FEE, ArenaMath.DEFAULT_ARBITER_FEE end
	if type(fee) ~= "table" then return nil end
	local form
	for k in pairs(fee) do
		local f = FEE_FIELDS[k]
		if not f then return nil end
		if f ~= "to" then
			if form and form ~= f then return nil end
			form = f
		end
	end
	if fee.to ~= nil and fee[3] ~= nil then return nil end
	local to = fee.to
	if to == nil then to = fee[3] end
	if to ~= nil and to ~= "g" and to ~= "a" then return nil end
	local mode = to == "g" and "direct" or "arbiter"
	if form ~= "guild" then
		-- The whole fee and the arbiter's part, as the ledger and the King's word carry them.
		local total, arbiter
		if form == "named" then
			total, arbiter = Rates(fee.feeBp, fee.arbBp, mode)
		else
			total, arbiter = Rates(fee[1], fee[2], mode)
		end
		return total, total and arbiter
	end
	local g, a = fee.g, fee.a
	if g == nil then g = ArenaMath.DEFAULT_GUILD_FEE elseif not Number(g) then return nil end
	if a == nil then a = ArenaMath.DEFAULT_ARBITER_FEE elseif not Number(a) then return nil end
	g, a = Clamp(g, 0, ArenaMath.FEE_CAP), Clamp(a, 0, ArenaMath.FEE_CAP)
	local total = g + a
	if total > ArenaMath.FEE_CAP then total = ArenaMath.FEE_CAP end
	if a > total then a = total end
	if to == "g" then return total, 0 end
	return total, a
end

function ArenaMath.Fee(bps)
	if bps == nil then return ArenaMath.DEFAULT_FEE end
	if not Number(bps) then return nil, "fee" end
	return Clamp(bps, 0, ArenaMath.FEE_CAP)
end

function ArenaMath.Split(fee, arbiterFee, mode)
	local total, arbiter = Rates(fee, arbiterFee, mode)
	if not total then return nil, arbiter end
	return total - arbiter, arbiter
end

-- The fee comes out of the WINNINGS (the money lost by the other side), never out of the
-- winners' own stakes: a winning bettor always gets back at least what he put in, and a pool
-- nobody lost (everyone on one side) pays no fee at all. Taken from the whole pool instead, a
-- heavy favourite could "win" and still lose gold (on 95g against 5g, 6% of 100g is more than
-- the 5g won), which no player would call a win. (Every section and the design read
-- the 6% this way; the owner is asked to confirm it: an open question of the design.)
-- The whole fee is rounded down once and the arbiter's part is rounded down, and the guild's is
-- the rest, so the fee is exactly its rate of the money won and the split's odd copper is the
-- guild's. Rounding the guild's part and the arbiter's apart would lose a copper between them:
-- 10% of 1000c split 6.67% + 3.33% would be 66c + 33c, a fee of 99c.
local function Cut(lose, total, arbiterBps)
	local cut = MulDiv(lose, total, BPS)
	local arbiter = MulDiv(lose, arbiterBps, BPS)
	return cut, cut - arbiter, arbiter, lose - cut
end

function ArenaMath.Fees(copper, fee, arbiterFee, mode)
	if not Whole(copper) or copper > ArenaMath.MAX_POOL then return nil, "copper" end
	local total, arbiterBps = Rates(fee, arbiterFee, mode)
	if not total then return nil, arbiterBps end
	local _, guild, arbiter, net = Cut(copper, total, arbiterBps)
	return guild, arbiter, net
end

---------------------------------------------------------------------------
-- The settlement (one formula for every caller)
---------------------------------------------------------------------------

-- outs[i], stakes[i]: bet i's outcome and copper (checked already); won: the set of winning
-- outcomes (empty: a void); total, arbiterBps: the rates (arbiterBps 0 when the arbiter's part
-- goes to the guild). Each winning bet is paid on its own: its stake back, and its part of its
-- outcome's share, rounded down to the copper. A bettor can work his own ticket out from the
-- public pools, and it is the same whether he placed one bet or three; the coppers the rounding
-- leaves (fewer than the winning bets and outcomes) go to the guild.
local function Engine(outs, stakes, won, total, arbiterBps)
	local pools, pool, sides = {}, 0, 0
	for i = 1, #outs do
		local o = outs[i]
		if not pools[o] then pools[o] = 0; sides = sides + 1 end
		pools[o] = pools[o] + stakes[i]
		pool = pool + stakes[i]
	end
	local win, live, any = 0, 0, false
	for o in pairs(won) do
		any = true
		if pools[o] then win, live = win + pools[o], live + 1 end
	end
	local s = { pool = pool, winPool = win, losePool = any and pool - win or 0, pays = {},
		cut = 0, guildFee = 0, arbiter = 0, remainder = 0, guild = 0, share = 0 }
	if not any then
		s.why = "void"
	elseif pool == 0 then
		s.why = "empty"
	elseif sides < 2 then
		-- Bets on one outcome only: nobody lost to anyone, so nobody wins anything.
		s.why = "onesided"
	elseif live == 0 then
		-- Nobody backed a winner: there is nobody to pay the pool to.
		s.why = "nobody"
	elseif win == pool then
		-- Every bet was on a winner (several places): nobody lost anything.
		s.why = "allwon"
	end
	if s.why then
		for i = 1, #outs do s.pays[i] = stakes[i] end
		return s
	end
	-- The winning outcomes that had bets share the winnings; one nobody backed passes its part on.
	local lose = pool - win
	local cut, guildFee, arbiter, net = Cut(lose, total, arbiterBps)
	local share = Div(net, live)
	local paid, winning = 0, 0
	for i = 1, #outs do
		local o, pay = outs[i], 0
		if won[o] then
			pay = stakes[i] + MulDiv(share, stakes[i], pools[o])
			winning = winning + 1
		end
		s.pays[i] = pay
		paid = paid + pay
	end
	local remainder = pool - cut - paid
	assert(remainder >= 0 and remainder < winning + live, "ArenaMath: the rounding left more than a copper a winning bet")
	s.cut, s.guildFee, s.arbiter, s.remainder, s.guild, s.share = cut, guildFee, arbiter, remainder, guildFee + remainder, share
	assert(paid + s.guild + arbiter == pool, "ArenaMath: the payouts and the cuts must add up to the pool")
	return s
end

-- An outcome of the contract functions in its ledger form (Canon), never VOID; or nil.
local function Outcome(k)
	k = Canon(k)
	if k == VOID then return nil end
	return k
end

-- Outcomes as a set of their ledger forms: one key, a set { [key] = true } or a list
-- { key, ... }; never VOID, never empty, and no outcome twice (7 and "7" are one). The set, or nil.
local function KeySet(keys)
	if type(keys) ~= "table" then
		local k = Outcome(keys)
		if not k then return nil end
		return { [k] = true }
	end
	if next(keys) == nil then return nil end
	local set, isSet = {}, true
	for _, v in pairs(keys) do
		if v ~= true then isSet = false; break end
	end
	if isSet then
		for key in pairs(keys) do
			local k = Outcome(key)
			if not k or set[k] then return nil end
			set[k] = true
		end
		return set
	end
	local n = List(keys)
	if not n then return nil end
	for i = 1, n do
		local k = Outcome(keys[i])
		if not k or set[k] then return nil end
		set[k] = true
	end
	return set
end

-- A contract bet { o, s, who }: its outcome's ledger form, or nil.
local function BetOf(b)
	if type(b) ~= "table" or not Copper(b.s) or not (b.who == nil or (type(b.who) == "string" and b.who ~= "")) then
		return nil
	end
	return Outcome(b.o)
end

-- The contract's result from the engine's: pays by bet, then summed by name.
local function Result(bets, s, pays)
	local byWho = {}
	for i, b in ipairs(bets) do
		if b.who then byWho[b.who] = (byWho[b.who] or 0) + pays[i] end
	end
	return { payouts = pays, guildFee = s.guild, arbFee = s.arbiter, refund = s.why, byWho = byWho,
		pool = s.pool, winPool = s.winPool, losePool = s.losePool, scratchPool = s.scratchPool or 0,
		cut = s.cut, share = s.share, remainder = s.remainder }
end

function ArenaMath.Settle(bets, winners, fee, scratched)
	local n = List(bets)
	if not n then return nil, "bets" end
	local total, arbiterBps = FeeRates(fee)
	if not total then return nil, "fee" end
	local scratch = {}
	if scratched ~= nil and not (type(scratched) == "table" and next(scratched) == nil) then
		scratch = KeySet(scratched)
		if not scratch then return nil, "scratched" end
	end
	local won = {}
	if winners ~= VOID then
		won = KeySet(winners)
		if not won then return nil, "winners" end
		for k in pairs(won) do
			if scratch[k] then return nil, "winners" end
		end
	end
	local pool, scratchPool, outs, stakes, index, pays = 0, 0, {}, {}, {}, {}
	for i = 1, n do
		local b = bets[i]
		local o = BetOf(b)
		if not o then return nil, "bet", i end
		pool = pool + b.s
		if pool > ArenaMath.MAX_POOL then return nil, "pool" end
		if scratch[o] then
			pays[i] = b.s
			scratchPool = scratchPool + b.s
		else
			outs[#outs + 1], stakes[#stakes + 1], index[#index + 1] = o, b.s, i
		end
	end
	local s = Engine(outs, stakes, won, total, arbiterBps)
	for j, i in ipairs(index) do pays[i] = s.pays[j] end
	s.pool, s.scratchPool = pool, scratchPool
	local out = 0
	for i = 1, n do out = out + pays[i] end
	assert(out + s.guild + s.arbiter == pool, "ArenaMath.Settle: the payouts and the cuts must add up to the pool")
	return Result(bets, s, pays)
end

---------------------------------------------------------------------------
-- The bracket pool (the design)
---------------------------------------------------------------------------

-- The picks' bits from their hex: 2^rounds - 1 of them, most significant bit first.
local function Bits(hex, rounds)
	if type(hex) ~= "string" then return nil end
	local first = hex:sub(1, 1)
	if first == "p" or first == "P" then hex = hex:sub(2) end
	local count = 2 ^ rounds - 1
	local digits = math.ceil(count / 4)
	if #hex ~= digits or hex:find("[^%x]") then return nil end
	local bits = {}
	for d = 1, digits do
		local v = tonumber(hex:sub(d, d), 16)
		for b = 3, 0, -1 do
			local bit = floor(v / 2 ^ b) % 2
			local i = (d - 1) * 4 + 4 - b
			if i <= count then
				bits[i] = bit
			elseif bit ~= 0 then
				return nil
			end
		end
	end
	return bits
end

local function Rounds(rounds)
	return Whole(rounds) and rounds >= 1 and rounds <= ArenaMath.PICK_ROUNDS
end

function ArenaMath.Picks(hex, rounds)
	if not Rounds(rounds) then return nil, "rounds" end
	local bits = Bits(hex, rounds)
	if not bits then return nil, "picks" end
	return bits
end

function ArenaMath.PickHex(bits)
	local n = List(bits)
	if not n then return nil end
	local fits
	for r = 1, ArenaMath.PICK_ROUNDS do
		if 2 ^ r - 1 == n then fits = true end
	end
	if not fits then return nil end
	local out = {}
	for d = 1, math.ceil(n / 4) do
		local v = 0
		for b = 1, 4 do
			local i = (d - 1) * 4 + b
			local bit = 0
			if i <= n then
				bit = bits[i]
				if bit ~= 0 and bit ~= 1 then return nil end
			end
			v = v * 2 + bit
		end
		out[d] = ("%x"):format(v)
	end
	return table.concat(out)
end

-- The slot each match's winner came from, match by match in bracket order: a pick is right when
-- it sends the same fighter through as the result, whatever it picked before.
local function Path(bits, rounds)
	local alive, won, i = {}, {}, 0
	for p = 1, 2 ^ rounds do alive[p] = p end
	for _ = 1, rounds do
		local through = {}
		for j = 1, #alive / 2 do
			i = i + 1
			through[j] = bits[i] == 0 and alive[2 * j - 1] or alive[2 * j]
			won[i] = through[j]
		end
		alive = through
	end
	return won
end

-- A correct pick in round r is worth 2^(r - 1).
local function Score(mine, actual, rounds)
	local score, i = 0, 0
	for r = 1, rounds do
		local worth = 2 ^ (r - 1)
		for _ = 1, 2 ^ (rounds - r) do
			i = i + 1
			if mine[i] == actual[i] then score = score + worth end
		end
	end
	return score
end

function ArenaMath.PickScore(picks, results, rounds)
	if not Rounds(rounds) then return nil, "rounds" end
	local mine = Bits(picks, rounds)
	if not mine then return nil, "picks" end
	local actual = Bits(results, rounds)
	if not actual then return nil, "results" end
	return Score(Path(mine, rounds), Path(actual, rounds), rounds)
end

-- Each entry is an outcome of its own, so two entries with the same picks are paid alike and
-- apart: the best scores split the winnings evenly (the design with k' = their count, each pool E).
function ArenaMath.Pickem(entries, results, rounds, fee)
	local n = List(entries)
	if not n then return nil, "entries" end
	if not Rounds(rounds) then return nil, "rounds" end
	local total, arbiterBps = FeeRates(fee)
	if not total then return nil, "fee" end
	local actual = Bits(results, rounds)
	if not actual then return nil, "results" end
	actual = Path(actual, rounds)
	local scores, outs, stakes, pool, top, stake = {}, {}, {}, 0, nil, nil
	for i = 1, n do
		local e = entries[i]
		if type(e) ~= "table" or not Copper(e.s) or (e.who ~= nil and not (type(e.who) == "string" and e.who ~= "")) then
			return nil, "entry", i
		end
		local bits = Bits(e.o, rounds)
		if not bits then return nil, "entry", i end
		if stake and e.s ~= stake then return nil, "stake", i end
		stake = e.s
		pool = pool + e.s
		if pool > ArenaMath.MAX_POOL then return nil, "pool" end
		scores[i] = Score(Path(bits, rounds), actual, rounds)
		if not top or scores[i] > top then top = scores[i] end
		outs[i], stakes[i] = i, e.s
	end
	local won, winners, tied = {}, {}, true
	for i = 1, n do
		if scores[i] == top then
			won[i] = true
			winners[#winners + 1] = i
		else
			tied = false
		end
	end
	local s
	if n == 0 or tied then
		-- Nobody, or everybody, has the best score: every stake back.
		s = Engine(outs, stakes, {}, total, arbiterBps)
		s.why = n == 0 and "empty" or "tied"
	else
		s = Engine(outs, stakes, won, total, arbiterBps)
	end
	local r = Result(entries, s, s.pays)
	r.scores, r.top, r.winners = scores, top, winners
	return r
end

---------------------------------------------------------------------------
-- A direct 1v1 bet (no arbiter, the design)
---------------------------------------------------------------------------

-- sw, sl: the winner's and the loser's stakes (usually the same). The loser pays his to the
-- winner by trade; the winner mails the guild the fee on it, the same fee a pool takes from its
-- winnings, all of it the guild's (there is no arbiter to share it with).
function ArenaMath.Direct(sw, sl, fee)
	if not Copper(sw) or not Copper(sl) then return nil, "stake" end
	local total = FeeRates(fee)
	if not total then return nil, "fee" end
	local guildFee = MulDiv(sl, total, BPS)
	return { loserPays = sl, guildFee = guildFee, kept = sl - guildFee }
end

---------------------------------------------------------------------------
-- Odds and previews (the design)
---------------------------------------------------------------------------

-- The pools keyed by the outcomes' ledger forms, and their sum; nil when they are not
-- { [outcome] = whole copper } under MAX_POOL, or name one outcome twice (7 and "7").
local function PoolsOf(pools)
	if type(pools) ~= "table" then return nil end
	local out, total = {}, 0
	for key, c in pairs(pools) do
		local k = Outcome(key)
		if not k or out[k] or not Whole(c) then return nil end
		out[k] = c
		total = total + c
		if total > ArenaMath.MAX_POOL then return nil end
	end
	return out, total
end

-- The least o's backers can be paid with k places: the other winners taken to be the most
-- backed outcomes, which leaves the least money lost and the most outcomes to split it with
-- (an outcome with bets always lowers o's part more than one without). The money lost then, and
-- how many winning outcomes had bets (o counted, as it has or will have one).
local function Worst(pools, total, o, k)
	local others = {}
	for key, c in pairs(pools) do
		if key ~= o then others[#others + 1] = c end
	end
	table.sort(others, function(a, b) return a > b end)
	local kept, live = 0, 1
	for i = 1, k - 1 do
		local c = others[i]
		if not c then break end
		kept = kept + c
		if c > 0 then live = live + 1 end
	end
	return total - (pools[o] or 0) - kept, live
end

-- The payout of s on o, were it the last bet (s already in pools[o]: s = 0 is added).
local function Paid(pools, total, o, s, fee, k)
	local lose, live = Worst(pools, total, o, k)
	if lose == 0 then return s, 0 end
	local _, _, _, net = Cut(lose, fee, 0)
	local share = Div(net, live)
	return s + MulDiv(share, s, (pools[o] or 0) + s), share
end

-- The markets section's odds are 100 + floor(L * (10000 - f) / (100 * k * P)), which leaves out
-- that the fee and the split between the k winners are rounded down, so with several places it
-- can show a hundredth more than a ticket gets. This takes the same winnings through the
-- settlement's own rounding: the exact payout of a 1-gold ticket in the pool (in the worst case,
-- with several places), truncated to the hundredth, never more than a settlement pays that ticket.
local function OddsOf(pools, total, o, k, fee)
	local p = pools[o] or 0
	if p == 0 then return nil end
	local _, share = Paid(pools, total, o, 0, fee, k)
	return 100 + MulDiv(share, 100, p)
end

-- The pools and the outcome in their ledger forms, the pools' sum and the whole fee; or nil, why.
local function OddsArgs(pools, o, fee)
	local total
	pools, total = PoolsOf(pools)
	if not pools then return nil, "pools" end
	o = Outcome(o)
	if not o then return nil, "outcome" end
	local rate = FeeRates(fee)
	if not rate then return nil, "fee" end
	return pools, o, total, rate
end

function ArenaMath.Odds(pools, o, fee)
	local p, key, total, rate = OddsArgs(pools, o, fee)
	if not p then return nil, key end
	return OddsOf(p, total, key, 1, rate)
end

function ArenaMath.OddsAtLeast(pools, o, k, fee)
	local p, key, total, rate = OddsArgs(pools, o, fee)
	if not p then return nil, key end
	if not (Whole(k) and k >= 1) then return nil, "k" end
	return OddsOf(p, total, key, k, rate)
end

function ArenaMath.Preview(pools, o, s, fee, k)
	local p, key, total, rate = OddsArgs(pools, o, fee)
	if not p then return nil, key end
	if not Copper(s) then return nil, "copper" end
	if total + s > ArenaMath.MAX_POOL then return nil, "pool" end
	if k == nil then k = 1 elseif not (Whole(k) and k >= 1) then return nil, "k" end
	return (Paid(p, total, key, s, rate, k))
end

function ArenaMath.OddsText(hundredths)
	if not Whole(hundredths) then return nil end
	return ("%d.%02dx"):format(floor(hundredths / 100), hundredths % 100)
end

---------------------------------------------------------------------------
-- A market object
---------------------------------------------------------------------------

function ArenaMath.Check(market)
	if type(market) ~= "table" then return nil, "market" end
	local outcomes = market.outcomes
	local n = List(outcomes)
	if not n or n < 2 or n > ArenaMath.MAX_OUTCOMES then return nil, "outcomes" end
	local known = {}
	for i = 1, n do
		local k = outcomes[i]
		if not Key(k) or k == VOID or known[k] then return nil, "outcomes" end
		known[k] = true
	end
	local places = market.places
	if places ~= nil and not (Whole(places) and places >= 1 and places < n) then return nil, "places" end
	local total, why = Rates(market.fee, market.arbiterFee, market.mode)
	if not total then return nil, why end
	local bets = market.bets
	if bets == nil then return true end
	local count = List(bets)
	if not count then return nil, "bets" end
	local pool = 0
	for i = 1, count do
		local b = bets[i]
		if type(b) ~= "table" or type(b.who) ~= "string" or b.who == "" or not Key(b.outcome) or not known[b.outcome]
			or not Copper(b.copper) then
			return nil, "bet", i
		end
		pool = pool + b.copper
		if pool > ArenaMath.MAX_POOL then return nil, "pool" end
	end
	return true
end

-- The market added up: { pools, total, bettors, stakes = { [who] = copper }, places, fee,
-- arbiterFee, outs, copper (each bet's outcome and copper, in order) }.
local function Tally(market)
	local ok, why, index = ArenaMath.Check(market)
	if not ok then return nil, why, index end
	local t = { pools = {}, total = 0, bettors = {}, stakes = {}, places = market.places or 1, outs = {}, copper = {} }
	t.fee, t.arbiterFee = Rates(market.fee, market.arbiterFee, market.mode)
	for _, k in ipairs(market.outcomes) do t.pools[k], t.bettors[k] = 0, 0 end
	local backed = {}
	for i, b in ipairs(market.bets or {}) do
		local k, who, c = b.outcome, b.who, b.copper
		t.outs[i], t.copper[i] = k, c
		t.pools[k] = t.pools[k] + c
		t.total = t.total + c
		t.stakes[who] = (t.stakes[who] or 0) + c
		local mine = backed[who]
		if not mine then mine = {}; backed[who] = mine end
		if not mine[k] then mine[k] = true; t.bettors[k] = t.bettors[k] + 1 end
	end
	return t
end

local function Known(market, k)
	for _, o in ipairs(market.outcomes) do
		if o == k then return true end
	end
	return false
end

-- The winning keys as a list, and as a set: exactly `places` of them, each the market's, none
-- twice. One key may be given bare.
local function Winners(market, keys)
	local list = keys
	if type(keys) ~= "table" then list = { keys } end
	local n = List(list)
	if not n or n ~= (market.places or 1) then return nil end
	local out, won = {}, {}
	for i = 1, n do
		local k = list[i]
		if won[k] or not Known(market, k) then return nil end
		won[k] = true
		out[i] = k
	end
	return out, won
end

function ArenaMath.Pools(market)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	return t.pools, t.total, t.bettors
end

function ArenaMath.Staked(market, who)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	if type(who) ~= "string" or who == "" then return nil, "who" end
	return t.stakes[who] or 0
end

function ArenaMath.MarketOdds(market)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	local odds = {}
	for _, k in ipairs(market.outcomes) do odds[k] = OddsOf(t.pools, t.total, k, t.places, t.fee) end
	return odds
end

function ArenaMath.Quote(market, key, copper)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	if not Known(market, key) then return nil, "outcome" end
	if not Copper(copper) then return nil, "copper" end
	if t.total + copper > ArenaMath.MAX_POOL then return nil, "pool" end
	return (Paid(t.pools, t.total, key, copper, t.fee, t.places))
end

-- The engine's figures in the market object's result.
local function MarketResult(market, t, list, s)
	local payouts = {}
	for who in pairs(t.stakes) do payouts[who] = 0 end
	for i, b in ipairs(market.bets or {}) do payouts[b.who] = payouts[b.who] + s.pays[i] end
	return { winners = list, outcome = t.places == 1 and list[1] or nil, refund = s.why ~= nil, why = s.why,
		pool = s.pool, winPool = s.winPool, losePool = s.losePool, share = s.share,
		bets = s.pays, payouts = payouts, stakes = t.stakes,
		cut = s.cut, guildFee = s.guildFee, arbiter = s.arbiter, remainder = s.remainder, guild = s.guild }
end

function ArenaMath.Void(market)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	return MarketResult(market, t, {}, Engine(t.outs, t.copper, {}, t.fee, t.arbiterFee))
end

function ArenaMath.SettleMarket(market, winners)
	local t, why, index = Tally(market)
	if not t then return nil, why, index end
	local list, won = Winners(market, winners)
	if not list then return nil, "outcome" end
	return MarketResult(market, t, list, Engine(t.outs, t.copper, won, t.fee, t.arbiterFee))
end

---------------------------------------------------------------------------
-- Limits (the money section's standing, as the design amends it)
---------------------------------------------------------------------------

-- A player's standing points buy him a tier, one per 5 points (an arbiter's advice, one per
-- ten), up to TIER_TOP; each kind of cap is a row of gold by tier, times the King's scalePct,
-- never past its ceiling. A late payment halves the points (Points) and puts a player on
-- probation for 7 days, a tier lower (the caller keeps the date); any open debt makes every cap
-- 0. A direct bet needs DIRECT_NEED points first: a debtor who wipes his saved variables or
-- rolls a new character can't be traced, so only a paid history buys credit; it is never more
-- than twice the largest direct debt he paid on time (1 gold before any); and probation at the
-- direct row's tier 0 closes it (DirectTier).
ArenaMath.TIER_TOP = 5
ArenaMath.DIRECT_NEED = 3
ArenaMath.NO_DIRECT = -1
ArenaMath.SCALE_LOW, ArenaMath.SCALE_HIGH = 25, 300
-- An arbiter on the King's T1~M list without a cap holds up to the lowest tier's (the design).
ArenaMath.HOLD_DEFAULT = 100 * GOLD

local function Gold(list)
	local out = {}
	for i, g in ipairs(list) do out[i] = g * GOLD end
	return out
end

ArenaMath.CAPS = {
	-- A wallet bet, per market (held up front: nothing to welsh on).
	bet = { per = 5, need = 0, probation = true, ceiling = 500 * GOLD, tiers = Gold({ 5, 10, 20, 40, 80, 150 }) },
	-- A wallet's balance at a bank.
	balance = { per = 5, need = 0, probation = true, ceiling = 5000 * GOLD, tiers = Gold({ 50, 100, 200, 400, 800, 1500 }) },
	-- Deposits in a day.
	daily = { per = 5, need = 0, probation = true, ceiling = 2500 * GOLD, tiers = Gold({ 25, 50, 100, 200, 400, 750 }) },
	-- A direct bet (the loser pays later, on his word): small, and only after a paid history.
	direct = { per = 5, need = ArenaMath.DIRECT_NEED, probation = true, ceiling = 100 * GOLD, tiers = Gold({ 1, 2, 5, 10, 20, 50 }) },
	-- Advice only (the design): an arbiter's own points (a clean match +1, a late guild fee
	-- halves them), a tier per 10, no probation. BetCap refuses it: the enforced cap is T1~M's.
	hold = { per = 10, need = 0, probation = false, advice = true, ceiling = 5000 * GOLD, tiers = Gold({ 100, 200, 400, 800, 1500, 3000 }) },
}
local CAPS = ArenaMath.CAPS

-- A record's fields: points, probation, whether a debt or a dispute is open, and the largest
-- direct debt paid. A malformed record is nil, "record".
local function Standing(record)
	if record == nil then return 0, false, false, false, 0 end
	if type(record) ~= "table" then return nil, "record" end
	local points, probation, paidMax = record.points, record.probation, record.paidMax
	if points == nil then
		points = 0
	elseif not (type(points) == "number" and points == floor(points) and points >= 0) then
		return nil, "record"
	end
	if probation ~= nil and type(probation) ~= "boolean" then return nil, "record" end
	if paidMax == nil then
		paidMax = 0
	elseif not Whole(paidMax) then
		return nil, "record"
	end
	return points, probation == true, Flag(record.open), Flag(record.dispute), paidMax
end

local function TierOf(rule, points, probation)
	local tier = floor(points / rule.per)
	if tier > ArenaMath.TIER_TOP then tier = ArenaMath.TIER_TOP end
	if probation and rule.probation and tier > 0 then tier = tier - 1 end
	return tier
end

-- The King's scale: nil is 100, a number is clamped, anything else closes the cap.
local function Scale(scale)
	if scale == nil then return 100 end
	if Number(scale) then return Clamp(scale, ArenaMath.SCALE_LOW, ArenaMath.SCALE_HIGH) end
	return nil, "scale"
end

-- The King's limit only lowers a cap; one that isn't a number >= 0 closes it rather than being
-- skipped, since skipping it would let a player past what the King set.
local function Limit(cap, limit)
	if limit == nil then return cap end
	if not (Number(limit) and limit >= 0) then return nil, "limit" end
	if limit < cap then return floor(limit) end
	return cap
end

-- A tier's row of the table, scaled, under the ceiling.
local function TierCap(rule, tier, scale)
	local cap = MulDiv(rule.tiers[tier + 1], scale, 100)
	if cap > rule.ceiling then cap = rule.ceiling end
	return cap
end

function ArenaMath.Points(history)
	if history == nil then return 0 end
	local n = List(history)
	if not n then return nil, "history" end
	local points = 0
	for i = 1, n do
		local paid = history[i]
		if paid == true then
			points = points + 1
		elseif paid == false then
			points = floor(points / 2)
		else
			return nil, "history", i
		end
	end
	return points
end

function ArenaMath.Tier(kind, record)
	local rule = CAPS[kind]
	if not rule then return nil, "kind" end
	local points, probation = Standing(record)
	if not points then return nil, probation end
	return TierOf(rule, points, probation)
end

-- Probation is a tier lower, and below the direct row's tier 0 is its "none": a player who just
-- paid late gets no credit until the 7 days pass, whatever his points.
function ArenaMath.DirectTier(record)
	local points, probation, open, dispute = Standing(record)
	if not points then return ArenaMath.NO_DIRECT, probation end
	if open then return ArenaMath.NO_DIRECT, "open" end
	if dispute then return ArenaMath.NO_DIRECT, "dispute" end
	if points < CAPS.direct.need then return ArenaMath.NO_DIRECT, "history" end
	local tier = TierOf(CAPS.direct, points, false)
	if probation then
		if tier == 0 then return ArenaMath.NO_DIRECT, "probation" end
		tier = tier - 1
	end
	return tier
end

function ArenaMath.DirectCap(tier, paidMax, scalePct, limit)
	if tier == ArenaMath.NO_DIRECT then return 0, "history" end
	if not (Whole(tier) and tier <= ArenaMath.TIER_TOP) then return 0, "tier" end
	if paidMax == nil then
		paidMax = 0
	elseif not Whole(paidMax) then
		return 0, "paidMax"
	end
	local scale, why = Scale(scalePct)
	if not scale then return 0, why end
	local cap = TierCap(CAPS.direct, tier, scale)
	local history = 2 * paidMax
	if history < GOLD then history = GOLD end
	if history < cap then cap = history end
	cap, why = Limit(cap, limit)
	if not cap then return 0, why end
	return cap
end

function ArenaMath.BetCap(record, kind, scalePct, limit)
	local rule = CAPS[kind]
	if not rule or rule.advice then return nil, "kind" end
	local points, probation, open, dispute, paidMax = Standing(record)
	if not points then return 0, probation end
	if open then return 0, "open" end
	if kind == "direct" then
		local tier, why = ArenaMath.DirectTier(record)
		if tier == ArenaMath.NO_DIRECT then return 0, why end
		return ArenaMath.DirectCap(tier, paidMax, scalePct, limit)
	end
	local scale, why = Scale(scalePct)
	if not scale then return 0, why end
	local cap
	cap, why = Limit(TierCap(rule, TierOf(rule, points, probation), scale), limit)
	if not cap then return 0, why end
	return cap
end

-- A settled stake earns a point only when it is at least a quarter of the tier's cap for that
-- kind (and the minimum bet): three 10s bets a day no longer climb to tier 5.
function ArenaMath.Earns(stake, tierCap, minBet)
	if not Copper(stake) then return false, "stake" end
	if not Whole(tierCap) then return false, "cap" end
	if minBet == nil then
		minBet = ArenaMath.MIN_BET
	elseif not (Whole(minBet) and minBet >= 1) then
		return false, "rules"
	end
	if stake < minBet then return false, "min" end
	if stake * 4 < tierCap then return false, "small" end
	return true
end

function ArenaMath.HoldAdvice(record, scalePct)
	local points, _, open = Standing(record)
	if not points then return 0, "record" end
	if open then return 0, "open" end
	local scale, why = Scale(scalePct)
	if not scale then return 0, why end
	return TierCap(CAPS.hold, TierOf(CAPS.hold, points, false), scale)
end

function ArenaMath.Room(cap, held)
	if cap == nil then cap = ArenaMath.HOLD_DEFAULT end
	if not Whole(cap) then return 0, "cap" end
	if not Whole(held) then return 0, "held" end
	if cap > held then return cap - held end
	return 0
end

function ArenaMath.BetOk(copper, cap, staked, rules)
	if not Copper(copper) then return false, "copper" end
	if copper % SILVER ~= 0 then return false, "silver" end
	local minBet, maxDay, today, maxPool, pool = ArenaMath.MIN_BET, nil, nil, nil, nil
	if rules ~= nil then
		if type(rules) ~= "table" then return false, "rules" end
		if rules.minBet ~= nil then
			minBet = rules.minBet
			if not (Whole(minBet) and minBet >= ArenaMath.MIN_BET_LOW and minBet <= ArenaMath.MIN_BET_HIGH) then
				return false, "rules"
			end
		end
		maxDay, today, maxPool, pool = rules.maxDay, rules.today, rules.maxPool, rules.pool
		if maxDay ~= nil and not (Whole(maxDay) and Whole(today)) then return false, "rules" end
		if maxPool ~= nil and not (Whole(maxPool) and Whole(pool)) then return false, "rules" end
	end
	if copper < minBet then return false, "min" end
	-- The cap is for the market, not for each slip: what he has on it already counts, or ten
	-- slips at the cap would put ten times the cap on it.
	if not Whole(staked) then return false, "staked" end
	if not Whole(cap) or staked + copper > cap then return false, "cap" end
	if maxDay and today + copper > maxDay then return false, "day" end
	if maxPool and pool + copper > maxPool then return false, "pool" end
	return true
end

-- A welsher's winnings pay his debts, oldest first, before any of it is his (the owner's
-- net-off). A malformed amount is refused rather than read as 0, which would hand the
-- winnings back to the debtor.
function ArenaMath.NetOff(copper, debts)
	if not Whole(copper) then return nil, "copper" end
	if debts == nil then return {}, copper end
	local n = List(debts)
	if not n then return nil, "debts" end
	local paid, left = {}, copper
	for i = 1, n do
		local owed = debts[i]
		if not Whole(owed) then return nil, "debts", i end
		local p = owed < left and owed or left
		paid[i] = p
		left = left - p
	end
	return paid, left
end
