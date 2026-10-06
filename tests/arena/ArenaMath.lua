-- ArenaMath (1.2): pari-mutuel pools, odds, the fee, settlements and refunds, the bracket pool,
-- direct bets, and the caps that grow with a player's standing. Run by tests/run.lua with its
-- helpers. The the design contract (Settle, Pickem, Odds, Preview, Direct, BetCap, DirectCap,
-- Earns, IDiv, MulDiv) comes first, checked against the markets and money sections' worked
-- examples and hand-computed figures; the market object's functions follow.
local H = ...
local test, eq = H.test, H.eq

local ns = {}
assert(loadfile(H.ADDON_DIR .. "ArenaMath.lua"))("Olympus", ns)
local M = ns.ArenaMath

local GOLD, SILVER = 10000, 100
local MAX = 2147483647
local floor = math.floor

-- Park-Miller: exact in a double, the same sequence on every run.
local function Randoms(seed)
	return function(n)
		seed = seed * 16807 % 2147483647
		return seed % n + 1
	end
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- A contract bet.
local function B(o, s, who) return { o = o, s = s, who = who } end

-- What left the pool in a contract result: every payout, the guild's and the arbiter's.
local function Out(r)
	local sum = r.guildFee + r.arbFee
	for _, c in ipairs(r.payouts) do sum = sum + c end
	return sum
end

-- The markets section's example 1 (the design): A has 600g from 30 bettors, B 400g from 21 (one 10g
-- bet, the 22nd in the list, and twenty of 19g 50s).
local function Example1()
	local bets = {}
	for i = 1, 30 do bets[#bets + 1] = B("A", 20 * GOLD, "Lida" .. i .. "-Realm") end
	bets[#bets + 1] = B("B", 10 * GOLD, "Parric-Realm")
	for i = 1, 20 do bets[#bets + 1] = B("B", 19 * GOLD + 50 * SILVER, "Wenna" .. i .. "-Realm") end
	return bets
end

-- Example 3: 8 slots holding 300, 200, 100, 100, 50, 50, 100 and 100 gold, in 10g bets.
local function Example3()
	local bets = {}
	for slot, g in ipairs({ 300, 200, 100, 100, 50, 50, 100, 100 }) do
		for i = 1, g / 10 do bets[#bets + 1] = B(slot, 10 * GOLD, "Slot" .. slot .. "Fan" .. i) end
	end
	return bets
end

---------------------------------------------------------------------------
-- Exact arithmetic (the design)
---------------------------------------------------------------------------

-- A slow exact reference that shares nothing with the module: a * b in 16-bit limbs (a and b
-- below 2^53, so a winning outcome's share times a stake at the gold cap fits), then the quotient
-- one bit at a time (binary long division, c below 2^52). Returns the quotient, or nil from 2^53 up.
local function Limbs(n)
	local out = {}
	for i = 1, 4 do
		out[i] = n % 65536
		n = floor(n / 65536)
	end
	return out
end

local function SlowMulDiv(a, b, c)
	local A, Bl, limbs = Limbs(a), Limbs(b), {}
	for i = 1, 9 do limbs[i] = 0 end
	for i = 1, 4 do
		for j = 1, 4 do limbs[i + j - 1] = limbs[i + j - 1] + A[i] * Bl[j] end
	end
	for i = 1, 8 do
		local carry = floor(limbs[i] / 65536)
		limbs[i] = limbs[i] - carry * 65536
		limbs[i + 1] = limbs[i + 1] + carry
	end
	local q, r = 0, 0
	for i = 8, 1, -1 do
		for bit = 15, 0, -1 do
			r = r * 2 + floor(limbs[i] / 2 ^ bit) % 2
			if q >= 2 ^ 52 then return nil end
			q = q * 2
			if r >= c then r = r - c; q = q + 1 end
		end
	end
	return q
end

-- The same reference for floor(n / d).
local function SlowDiv(n, d) return SlowMulDiv(n, 1, d) end

test("ArenaMath: IDiv and MulDiv give the markets section's vectors exactly", function()
	eq(M.MulDiv(2147483647, 2147483647, 2147483647), 2147483647)
	eq(M.MulDiv(2147483646, 2147483645, 2147483647), 2147483644)
	eq(M.MulDiv(1, 1, 3), 0)
	eq(M.MulDiv(2000000000, 1999999999, 2147483647), 1862645149)
	-- IDiv up to 2^52: one float division, corrected where it rounds across a whole number.
	eq(M.IDiv(10, 3), 3)
	eq(M.IDiv(0, 7), 0)
	eq(M.IDiv(2 ^ 52 - 1, 1), 2 ^ 52 - 1)
	eq(M.IDiv(2 ^ 52 - 1, 3), 1501199875790165)
	eq(M.IDiv(2 ^ 52 - 1, 2 ^ 52), 0)
	eq(M.IDiv(4503599627370494, 4503599627370495), 0, "one under the divisor")
	eq(M.IDiv(9007199254740, 3), 3002399751580)
	for _, bad in ipairs({ { 2 ^ 52, 1 }, { -1, 1 }, { 1.5, 1 }, { 1, 0 }, { 1, 2 ^ 52 + 2 }, { "10", 3 }, { 0 / 0, 1 } }) do
		eq(M.IDiv(bad[1], bad[2]), nil, "IDiv(" .. tostring(bad[1]) .. ", " .. tostring(bad[2]) .. ")")
	end
end)

test("ArenaMath: IDiv and MulDiv are exact over 10,000 random stakes, against a slow long division", function()
	local Rand = Randoms(1203)
	local fast, long, overflow = 0, 0, 0
	-- Stakes anywhere up to the gold cap; a quarter near it and a quarter under 100g.
	local function Stake()
		local pick = Rand(4)
		if pick == 1 then return MAX - Rand(1000) + 1 end
		if pick == 2 then return Rand(100 * GOLD) - 1 end
		return Rand(MAX) - 1
	end
	for i = 1, 10000 do
		-- A small divisor now and then, where the quotient can pass 2^53 and must be refused.
		local a, b, c = Stake(), Stake(), Rand(8) == 1 and Rand(1000) or Stake()
		if c == 0 then c = 1 end
		local want = SlowMulDiv(a, b, c)
		local got = M.MulDiv(a, b, c)
		eq(got, want, "MulDiv(" .. a .. ", " .. b .. ", " .. c .. ") #" .. i)
		if not want then overflow = overflow + 1 elseif a * b < 2 ^ 52 then fast = fast + 1 else long = long + 1 end
		-- IDiv: q * d <= n < (q + 1) * d, all exact below 2^53.
		local n = (Rand(2 ^ 26) - 1) * 2 ^ 26 + Rand(2 ^ 26) - 1
		local d = Rand(3) == 1 and Rand(1000) or Stake() + 1
		local q = M.IDiv(n, d)
		assert(q == floor(q) and q * d <= n and n - q * d < d, "IDiv(" .. n .. ", " .. d .. ") gave " .. tostring(q))
	end
	assert(fast > 1000 and long > 3000 and overflow > 20,
		"every path exercised (" .. fast .. " products under 2^52, " .. long .. " by long division, " .. overflow .. " refused past 2^53)")
end)

test("ArenaMath: MulDiv past the stakes' range: exact up to 2^53, and refused where it can't be", function()
	-- Expected values from Python's integers.
	eq(M.MulDiv(10 ^ 15, 1000, 1000), 10 ^ 15)
	eq(M.MulDiv(2 ^ 40 + 1, 2 ^ 40 + 3, 2 ^ 40 + 7), 1099511627773)
	eq(M.MulDiv(123456789012345, 987654321, 2 ^ 44 - 1), 6931067623)
	eq(M.MulDiv(2 ^ 53 - 1, 3, 7), 3860228252031853)
	eq(M.MulDiv(0, MAX, 3), 0)
	eq(M.MulDiv(7, 3, 2), 10)
	eq(M.MulDiv(2 ^ 52 - 1, 2 ^ 52 - 3, 2 ^ 44), nil, "the result would pass 2^53")
	eq(M.MulDiv(1, 1, 0), nil)
	eq(M.MulDiv(1, 1, 2 ^ 44 + 1), nil, "a divisor past 2^44")
	eq(M.MulDiv(-1, 1, 1), nil)
	eq(M.MulDiv(1.5, 1, 1), nil)
	eq(M.Part(1234567, 600), 74074)
	eq(M.Part(8589934588, 400), 343597383)
end)

---------------------------------------------------------------------------
-- Settle (the design)
---------------------------------------------------------------------------

test("ArenaMath: Settle pays the markets section's worked examples to the copper", function()
	-- 1. MW, B wins: 36g cut (12g the arbiter's), 564g shared over B's 400g.
	local r = M.Settle(Example1(), "B")
	eq(r.refund, nil)
	eq(r.payouts[31], 241000, "the 10g bet on B receives 24g 10s")
	eq(r.payouts[32], 469950, "19g 50s on B")
	eq(r.payouts[1], 0, "a bet on A")
	eq(r.guildFee, 24 * GOLD); eq(r.arbFee, 12 * GOLD)
	eq(r.pool, 1000 * GOLD); eq(r.winPool, 400 * GOLD); eq(r.losePool, 600 * GOLD); eq(r.cut, 36 * GOLD)
	eq(r.share, 564 * GOLD); eq(r.remainder, 0)
	eq(Out(r), 1000 * GOLD)
	eq(r.byWho["Parric-Realm"], 241000, "summed by name")
	eq(r.byWho["Lida1-Realm"], 0)
	-- 2. Rounding: three 1g bets on A, 1g 1s on B, A wins: 13,164 each, the 2c left the guild's.
	r = M.Settle({ B("A", GOLD), B("A", GOLD), B("A", GOLD), B("B", GOLD + SILVER) }, "A")
	eq(r.payouts[1], 13164); eq(r.payouts[2], 13164); eq(r.payouts[3], 13164); eq(r.payouts[4], 0)
	eq(r.cut, 606); eq(r.arbFee, 202); eq(r.remainder, 2)
	eq(r.guildFee, 406, "404 and the 2c of rounding")
	eq(Out(r), 40100)
	-- 3. RF: the finalists are slots 1 and 5; 611g left, 305g 50s for each finalist's backers.
	r = M.Settle(Example3(), { [1] = true, [5] = true })
	eq(r.payouts[1], 20 * GOLD + 18 * SILVER + 33, "10g on slot 1 receives 20g 18s 33c")
	eq(r.payouts[71], 71 * GOLD + 10 * SILVER, "10g on slot 5 receives 71g 10s")
	eq(r.payouts[31], 0, "slot 2")
	eq(r.share, 305 * GOLD + 50 * SILVER)
	eq(r.guildFee, 26 * GOLD + 10, "26g 10c: 10c of it the per-bet rounding on slot 1")
	eq(r.arbFee, 13 * GOLD)
	eq(Out(r), 1000 * GOLD)
	eq(M.Settle(Example3(), { 5, 1 }).payouts[71], 71 * GOLD + 10 * SILVER, "the winners as a list")
	-- 4. CX: Torvin stakes 10g, Selka 5g.
	local cx = { B("A", 10 * GOLD, "Torvin-Realm"), B("B", 5 * GOLD, "Selka-Realm") }
	r = M.Settle(cx, "A")
	eq(r.payouts[1], 14 * GOLD + 70 * SILVER); eq(r.guildFee, 20 * SILVER); eq(r.arbFee, 10 * SILVER)
	r = M.Settle(cx, "B")
	eq(r.payouts[2], 14 * GOLD + 40 * SILVER); eq(r.guildFee, 40 * SILVER); eq(r.arbFee, 20 * SILVER)
	-- 5. DR: Selka stakes 5g against Torvin's 5g and loses: she owes him 5g, he owes the guild 30s.
	local d = M.Direct(5 * GOLD, 5 * GOLD)
	eq(d.loserPays, 5 * GOLD); eq(d.guildFee, 30 * SILVER); eq(d.kept, 4 * GOLD + 70 * SILVER)
end)

test("ArenaMath: Settle's fee: the defaults, by name or by position, the King's all to the guild, clamps and nonsense", function()
	local base = M.Settle(Example1(), "B")
	for _, fee in ipairs({ { g = 400, a = 200 }, { 600, 200 }, { 600, 200, "a" }, { feeBp = 600, arbBp = 200 },
		{ g = 400 }, { a = 200 }, { 600 }, { feeBp = 600 }, { arbBp = 200 }, {}, { to = "a" } }) do
		local r = M.Settle(Example1(), "B", fee)
		eq(r.payouts[31], base.payouts[31]); eq(r.guildFee, 24 * GOLD); eq(r.arbFee, 12 * GOLD)
	end
	-- The King arbitrates: the arbiter's 2% goes to the guild; the winners get the same.
	local r = M.Settle(Example1(), "B", { to = "g" })
	eq(r.payouts[31], 241000); eq(r.guildFee, 36 * GOLD); eq(r.arbFee, 0)
	eq(Out(r), 1000 * GOLD)
	r = M.Settle(Example1(), "B", { 600, 200, "g" })
	eq(r.guildFee, 36 * GOLD); eq(r.arbFee, 0)
	r = M.Settle(Example1(), "B", { feeBp = 600, arbBp = 200, to = "g" })
	eq(r.guildFee, 36 * GOLD); eq(r.arbFee, 0)
	-- No fee: the proposal's 2.50x.
	r = M.Settle(Example1(), "B", { g = 0, a = 0 })
	eq(r.payouts[31], 25 * GOLD); eq(r.guildFee, 0); eq(r.arbFee, 0)
	-- 9% + 3% is clamped to 10%, the arbiter keeping his 3%.
	r = M.Settle(Example1(), "B", { g = 900, a = 300 })
	eq(r.cut, 60 * GOLD); eq(r.arbFee, 18 * GOLD); eq(r.guildFee, 42 * GOLD)
	eq(r.payouts[31], 235000); eq(r.payouts[32], 458250)
	r = M.Settle(Example1(), "B", { g = 400, a = 2000 })
	eq(r.arbFee, 60 * GOLD, "the arbiter's part never passes the whole fee"); eq(r.guildFee, 0)
	r = M.Settle(Example1(), "B", { g = -5, a = 200 })
	eq(r.guildFee, 0); eq(r.arbFee, 12 * GOLD)
	-- 10% of 1000c with 3.33% the arbiter's: 67c and 33c, never 66c and 33c.
	r = M.Settle({ B("A", 1000), B("B", 1000) }, "A", { g = 667, a = 333 })
	eq(r.payouts[1], 1900); eq(r.guildFee, 67); eq(r.arbFee, 33)
	for _, bad in ipairs({ "6%", 600, { g = "4" }, { a = 0 / 0 }, { to = "x" }, { to = "guild" }, true }) do
		local res, why = M.Settle(Example1(), "B", bad)
		eq(res, nil, "fee " .. tostring(bad)); eq(why, "fee")
	end
end)

test("ArenaMath: a fee replayed from the ledger's n entry (feeBp 600, arbBp 200) is 6%, never read as the guild's part", function()
	-- The review's probe: { 600, 200 } was read as 6% to the guild plus 2% to the arbiter, a cut
	-- of 48g instead of 36g on example 1, and B's 400g paid 952g instead of 964g.
	local feeBp, arbBp = 600, 200 -- in the order n:<market>:...:<feeBp>:<arbBp>:... lists them
	for _, fee in ipairs({ { feeBp, arbBp }, { feeBp = feeBp, arbBp = arbBp } }) do
		local r = M.Settle(Example1(), "B", fee)
		eq(r.cut, 36 * GOLD, "6% of the 600g won"); eq(r.arbFee, 12 * GOLD); eq(r.guildFee, 24 * GOLD)
		eq(r.payouts[31], 241000, "the 10g bet on B receives 24g 10s")
		local onB = 0
		for i = 31, 51 do onB = onB + r.payouts[i] end
		eq(onB, 964 * GOLD, "B's 400g is paid 400g and 564g")
		eq(Out(r), 1000 * GOLD)
	end
	-- The King's T1~O word carries the same two numbers in the same order.
	eq(M.Direct(10 * GOLD, 10 * GOLD, { feeBp, arbBp }).guildFee, 60 * SILVER, "a direct bet: the whole 6%")
	eq(M.Odds({ A = 600 * GOLD, B = 400 * GOLD }, "B", { feeBp, arbBp }), 241)
	eq(M.Preview({ A = 600 * GOLD, B = 400 * GOLD }, "B", 10 * GOLD, { feeBp, arbBp }), 237560)
	local p = M.Pickem({ B("p5a", GOLD), B("p00", GOLD) }, "P5a", 3, { feeBp, arbBp })
	eq(p.payouts[1], GOLD + GOLD - 6 * SILVER); eq(p.guildFee, 4 * SILVER); eq(p.arbFee, 2 * SILVER)
	-- A first number is always the whole fee: { 400, 200 } is 4%, half of it the arbiter's.
	local r = M.Settle(Example1(), "B", { 400, 200 })
	eq(r.cut, 24 * GOLD); eq(r.arbFee, 12 * GOLD); eq(r.guildFee, 12 * GOLD)
	-- Clamped as the King's bounds read (0-1000 / 0-feeBp): the whole to 10%, the arbiter's part
	-- to the whole.
	r = M.Settle(Example1(), "B", { 1200, 300 })
	eq(r.cut, 60 * GOLD); eq(r.arbFee, 18 * GOLD); eq(r.guildFee, 42 * GOLD)
	r = M.Settle(Example1(), "B", { feeBp = 600, arbBp = 900 })
	eq(r.cut, 36 * GOLD); eq(r.arbFee, 36 * GOLD, "the arbiter's part never passes the whole"); eq(r.guildFee, 0)
	r = M.Settle(Example1(), "B", { -5, 200 })
	eq(r.cut, 0); eq(r.arbFee, 0); eq(r.payouts[31], 25 * GOLD)
	eq(M.Settle(Example1(), "B", { 0, 0 }).payouts[31], 25 * GOLD, "no fee: the proposal's 2.50x")
	-- Two forms at once, a field no form has, or text for a rate: refused, never guessed.
	for i, bad in ipairs({ { 600, 200, g = 400 }, { feeBp = 600, a = 200 }, { 600, arbBp = 200 }, { g = 400, arbBp = 200 },
		{ 600, 200, "g", to = "g" }, { 600, 200, "g", "a" }, { fee = 600 }, { feeBp = 600, arb = 200 },
		{ "600", "200" }, { feeBp = "600" }, { 600, 0 / 0 }, { feeBp = 600, to = "x" }, { 600, 200, "guild" } }) do
		local tag = "fee #" .. i
		local res, why = M.Settle(Example1(), "B", bad)
		eq(res, nil, tag); eq(why, "fee", tag)
		res, why = M.Direct(10 * GOLD, 10 * GOLD, bad)
		eq(res, nil, "direct " .. tag); eq(why, "fee", "direct " .. tag)
		res, why = M.Odds({ A = GOLD, B = GOLD }, "A", bad)
		eq(res, nil, "odds " .. tag); eq(why, "fee", "odds " .. tag)
	end
end)

test("ArenaMath: Settle refunds, fee-free: a void, nobody on the winner, everyone on it, one side only, no bets", function()
	local function Refunded(r, reason, bets)
		eq(r.refund, reason)
		eq(r.guildFee, 0, reason); eq(r.arbFee, 0, reason); eq(r.cut, 0, reason)
		for i, b in ipairs(bets) do eq(r.payouts[i], b.s, reason .. ": bet " .. i .. " back") end
		eq(Out(r), r.pool, reason)
	end
	local bets = Example1()
	Refunded(M.Settle(bets, M.VOID), "void", bets)
	eq(M.VOID, "V", "as the ledger's x writes a void")
	-- Bets on A and B, and C wins.
	Refunded(M.Settle(bets, "C"), "nobody", bets)
	-- Everyone on the winners (two places, both backed): nobody lost.
	local two = { B(1, 3 * GOLD), B(2, GOLD), B(2, GOLD) }
	Refunded(M.Settle(two, { 1, 2 }), "allwon", two)
	-- One side only, whichever wins (the bank voids it at the lock with code 1).
	local one = { B("A", 3 * GOLD), B("A", GOLD) }
	Refunded(M.Settle(one, "A"), "onesided", one)
	Refunded(M.Settle(one, "B"), "onesided", one)
	-- No bets.
	local r = M.Settle({}, "A")
	Refunded(r, "empty", {})
	eq(r.pool, 0); eq(#r.payouts, 0)
end)

test("ArenaMath: Settle refunds a scratched slot's bets and settles the rest on the smaller pools", function()
	-- A champion market: Lida on slot 1, Parric on 2, Wenna on 3; slot 3 is scratched before the
	-- lock and slot 1 wins: Wenna gets her 20g back, and Lida wins Parric's 5g less 6%.
	local bets = { B(1, 10 * GOLD, "Lida-Realm"), B(2, 5 * GOLD, "Parric-Realm"), B(3, 20 * GOLD, "Wenna-Realm") }
	local r = M.Settle(bets, 1, nil, { 3 })
	eq(r.refund, nil)
	eq(r.payouts[3], 20 * GOLD, "the scratched stake back")
	eq(r.payouts[1], 14 * GOLD + 70 * SILVER)
	eq(r.payouts[2], 0)
	eq(r.guildFee, 20 * SILVER); eq(r.arbFee, 10 * SILVER)
	eq(r.pool, 35 * GOLD, "the whole pool, the scratched stakes too")
	eq(r.losePool, 5 * GOLD, "the money won is only the other side's")
	eq(r.winPool, 10 * GOLD)
	eq(r.scratchPool, 20 * GOLD, "the scratched stakes, so the three sides add up to the pool")
	eq(r.winPool + r.losePool + r.scratchPool, r.pool)
	eq(M.Settle(bets, 1).scratchPool, 0, "nothing scratched")
	eq(Out(r), 35 * GOLD)
	eq(M.Settle(bets, 1, nil, { [3] = true }).payouts[1], 14 * GOLD + 70 * SILVER, "a set")
	eq(M.Settle(bets, 1, nil, 3).payouts[3], 20 * GOLD, "a bare key")
	eq(M.Settle(bets, 1, nil, {}).payouts[1], 10 * GOLD + 23 * GOLD + 50 * SILVER, "none scratched: 25g won less 6%")
	-- Scratching slot 2 as well leaves one side: everything comes back.
	r = M.Settle(bets, 1, nil, { 2, 3 })
	eq(r.refund, "onesided")
	eq(r.payouts[1], 10 * GOLD); eq(r.payouts[2], 5 * GOLD); eq(r.payouts[3], 20 * GOLD)
	-- A scratched entrant can't win, and a void still returns everything.
	local res, why = M.Settle(bets, 3, nil, { 3 })
	eq(res, nil); eq(why, "winners")
	res, why = M.Settle(bets, { 1, 3 }, nil, { 3 })
	eq(res, nil); eq(why, "winners")
	r = M.Settle(bets, M.VOID, nil, { 3 })
	eq(r.refund, "void"); eq(r.payouts[1], 10 * GOLD); eq(r.payouts[3], 20 * GOLD)
	for _, bad in ipairs({ M.VOID, { M.VOID }, { 3, 3 }, true, { [""] = true } }) do
		res, why = M.Settle(bets, 1, nil, bad)
		eq(res, nil, "scratched " .. tostring(bad)); eq(why, "scratched")
	end
end)

test("ArenaMath: outcomes compare as the ledger writes them: the slot 1 and the text \"1\" are one outcome", function()
	-- The review's probe: bets read from the ledger's b entries ("1", "2") and a winner turned
	-- into a number (1) found nobody on the winner, refunded every stake and took no fee.
	local bets = { B("1", 5 * GOLD, "Lida-Realm"), B("2", 5 * GOLD, "Parric-Realm") }
	for _, winners in ipairs({ 1, "1", { 1 }, { [1] = true }, { ["1"] = true } }) do
		local r = M.Settle(bets, winners)
		eq(r.refund, nil, "winner " .. tostring(winners))
		eq(r.payouts[1], 9 * GOLD + 70 * SILVER, "5g back and 5g won less 6%"); eq(r.payouts[2], 0)
		eq(r.guildFee, 20 * SILVER); eq(r.arbFee, 10 * SILVER)
	end
	-- The other way: slots as numbers, the result as the ledger's text.
	local text = M.Settle(Example3(), { "1", "5" })
	eq(text.payouts[71], 71 * GOLD + 10 * SILVER); eq(text.payouts[1], 20 * GOLD + 18 * SILVER + 33)
	eq(M.Settle(Example3(), { ["5"] = true, [1] = true }).guildFee, 26 * GOLD + 10, "a set of both kinds")
	-- Bets on 1 and on "1" are one pool; a scratched "3" is the slot 3.
	local r = M.Settle({ B(1, 2 * GOLD), B("1", 3 * GOLD), B(2, 5 * GOLD) }, "1")
	eq(r.winPool, 5 * GOLD); eq(r.payouts[1], 38800); eq(r.payouts[2], 58200)
	r = M.Settle({ B(1, 10 * GOLD), B(2, 5 * GOLD), B(3, 20 * GOLD) }, 1, nil, { "3" })
	eq(r.payouts[3], 20 * GOLD, "scratched"); eq(r.payouts[1], 14 * GOLD + 70 * SILVER)
	-- Text is never read as a number: "01" is not the slot 1 (nobody backed "01": all back).
	eq(M.Settle(bets, "01").refund, "nobody")
	-- One outcome named twice is refused, never counted as two winners.
	for _, twice in ipairs({ { 1, "1" }, { [1] = true, ["1"] = true } }) do
		local res, why = M.Settle(bets, twice)
		eq(res, nil); eq(why, "winners")
	end
	for _, twice in ipairs({ { 3, "3" }, { [3] = true, ["3"] = true } }) do
		local res, why = M.Settle({ B(1, GOLD), B(2, GOLD), B(3, GOLD) }, 1, nil, twice)
		eq(res, nil); eq(why, "scratched")
	end
	-- Numbers are whole, from 0 to MAX_KEY; anything else is refused.
	for _, o in ipairs({ 1.5, -1, M.MAX_KEY + 1, 1 / 0 }) do
		local res, why, i = M.Settle({ B(1, GOLD), B(o, GOLD) }, 1)
		eq(res, nil, "outcome " .. tostring(o)); eq(why, "bet"); eq(i, 2)
		res, why = M.Settle({ B(1, GOLD), B(2, GOLD) }, o)
		eq(res, nil, "winner " .. tostring(o)); eq(why, "winners")
	end
	eq(M.Settle({ B(0, GOLD), B(M.MAX_KEY, GOLD) }, "0").payouts[1], 2 * GOLD - 6 * SILVER, "0 and MAX_KEY are outcomes")
	-- The odds read their pools the same way.
	eq(M.Odds({ ["1"] = 600 * GOLD, ["2"] = 400 * GOLD }, 2), 241)
	eq(M.Odds({ 600 * GOLD, 400 * GOLD }, "2"), 241)
	eq(M.OddsAtLeast({ 600 * GOLD, 400 * GOLD, 100 * GOLD }, "2", 2), M.OddsAtLeast({ 600 * GOLD, 400 * GOLD, 100 * GOLD }, 2, 2))
	eq(M.Preview({ ["1"] = 600 * GOLD }, 2, 10 * GOLD), 574 * GOLD)
	local res, why = M.Odds({ [1] = 5 * GOLD, ["1"] = 5 * GOLD, ["2"] = GOLD }, "2")
	eq(res, nil, "one outcome's pool twice"); eq(why, "pools")
	res, why = M.Odds({ A = GOLD, [1.5] = GOLD }, "A")
	eq(res, nil); eq(why, "pools")
	res, why = M.Odds({ A = GOLD }, M.VOID)
	eq(res, nil, "V is never an outcome"); eq(why, "outcome")
end)

test("ArenaMath: Settle refuses malformed bets, winners and pools whole, never reading them as fewer", function()
	local function No(want, bets, winners, index)
		local r, why, i = M.Settle(bets, winners)
		eq(r, nil, want); eq(why, want); eq(i, index, want)
	end
	No("bets", nil, "A")
	No("bets", "bets", "A")
	No("bets", { n1 = B("A", GOLD), n2 = B("B", GOLD) }, "A", nil) -- keyed by the slips' nonces
	local holed = { B("A", GOLD) }
	holed[3] = B("B", GOLD)
	No("bets", holed, "A")
	local bad = { B("A", 10.5), B("A", 0), B("A", -GOLD), B("A", MAX + 1), B("A", "100"), B("", GOLD),
		B(M.VOID, GOLD), B(nil, GOLD), B(0 / 0, GOLD), B("A", GOLD, ""), B("A", GOLD, 7), "bet" }
	for i, b in ipairs(bad) do No("bet", { B("B", GOLD), b }, "A", 2) end
	-- A pool past MAX_POOL (2^43): 4096 bets at the gold cap fit, 4097 don't.
	local whales = {}
	for i = 1, 4096 do whales[i] = B(i % 2 == 0 and "A" or "B", MAX) end
	assert(M.Settle(whales, "A"), "4096 bets at the cap")
	whales[4097] = B("A", MAX)
	No("pool", whales, "A")
	No("winners", { B("A", GOLD), B("B", GOLD) }, nil)
	for _, w in ipairs({ {}, { "A", "A" }, { A = 1 }, { A = true, [1] = "B" }, { [""] = true }, { M.VOID }, false, 0 / 0 }) do
		No("winners", { B("A", GOLD), B("B", GOLD) }, w)
	end
end)

test("ArenaMath: Settle and Pickem leave their input as it was", function()
	local bets = Example1()
	local winners = { B = true }
	M.Settle(bets, winners, { g = 500, a = 100 })
	M.Settle(bets, M.VOID)
	eq(#bets, 51); eq(bets[31].s, 10 * GOLD); eq(bets[31].o, "B"); eq(bets[31].who, "Parric-Realm")
	eq(Count(winners), 1)
	local entries = { B("p5a", GOLD, "Lida-Realm"), B("p00", GOLD) }
	M.Pickem(entries, "P5a", 3)
	eq(#entries, 2); eq(entries[1].o, "p5a"); eq(entries[2].who, nil)
end)

test("ArenaMath: Settle over random markets pays every ticket what the design gives in slow exact arithmetic", function()
	-- The markets section's test 2: 1 to 60 bets, 2 to 64 outcomes, k from 1 to 8 winners, fees
	-- of 0 to 1000 basis points in each of the three forms, up to 3 losing outcomes scratched,
	-- stakes up to the gold cap in a quarter of the rounds, and each outcome written as a number
	-- or as the ledger's text, bet by bet. The expected copper is worked out here from the
	-- section's formula with the slow long division above (nothing shared with the module): the
	-- refund's reason, the cut, the arbiter's part, each outcome's share, and each ticket's
	-- s + floor(share * s / P_o). The market object must pay every ticket the same.
	local Rand = Randoms(20260930)
	local settled, refunds, scratchedBets, tickets, bigTickets = 0, 0, 0, 0, 0
	for round = 1, 600 do
		local tag = "round " .. round
		local n = Rand(63) + 1
		local k = Rand(8)
		if k > n then k = n end
		local big = Rand(4) == 1
		-- raw: the test's own record of each bet, its outcome as a number.
		local raw, bets = {}, {}
		for i = 1, Rand(60) do
			raw[i] = { o = Rand(n), s = big and Rand(MAX) or Rand(100 * GOLD) }
			bets[i] = B(Rand(2) == 1 and tostring(raw[i].o) or raw[i].o, raw[i].s, "Tester" .. Rand(15) .. "-Realm")
		end
		local g = Rand(1001) - 1
		local a = Rand(1001 - g) - 1
		local to = Rand(3) == 1 and "g" or nil
		local form = Rand(3)
		local fee = form == 1 and { g = g, a = a, to = to } or form == 2 and { g + a, a, to }
			or { feeBp = g + a, arbBp = a, to = to }
		-- The winners: most often an outcome someone backed, or with 64 outcomes and a few bets
		-- nearly every market would be a refund.
		local winners, won = {}, {}
		for _ = 1, k do
			local w = Rand(n)
			if #raw > 0 and Rand(4) > 1 then w = raw[Rand(#raw)].o end
			while won[w] do w = w % n + 1 end
			winners[#winners + 1], won[w] = Rand(2) == 1 and tostring(w) or w, true
		end
		-- A third of the rounds scratch up to 3 backed outcomes that did not win.
		local scratched, gone = {}, {}
		if #raw > 0 and Rand(3) == 1 then
			for _ = 1, Rand(3) do
				local o = raw[Rand(#raw)].o
				if not won[o] and not gone[o] then
					gone[o] = true
					scratched[#scratched + 1] = Rand(2) == 1 and tostring(o) or o
				end
			end
		end
		local r = M.Settle(bets, winners, fee, scratched)
		assert(r, tag .. " settled")
		-- The pools, the sides and the refund's reason, as the test sees them.
		local pools, pool, scratchPool, sides = {}, 0, 0, 0
		for _, b in ipairs(raw) do
			pool = pool + b.s
			if gone[b.o] then
				scratchPool = scratchPool + b.s
			else
				if not pools[b.o] then pools[b.o] = 0; sides = sides + 1 end
				pools[b.o] = pools[b.o] + b.s
			end
		end
		local win, live = 0, 0
		for w in pairs(won) do
			if pools[w] then win, live = win + pools[w], live + 1 end
		end
		local lose = pool - scratchPool - win
		local expect = pool == scratchPool and "empty" or sides < 2 and "onesided" or live == 0 and "nobody"
			or lose == 0 and "allwon" or nil
		eq(r.refund, expect, tag .. ": the refund's reason")
		eq(r.pool, pool, tag); eq(r.scratchPool, scratchPool, tag)
		eq(r.winPool + r.losePool + r.scratchPool, pool, tag .. ": the three sides")
		eq(Out(r), pool, tag .. ": in equals out")
		if expect then
			refunds = refunds + 1
			eq(r.guildFee + r.arbFee, 0, tag .. ": a refund takes no fee")
			for i, b in ipairs(raw) do eq(r.payouts[i], b.s, tag .. ": a refund, bet " .. i) end
		else
			settled = settled + 1
			local cut = SlowMulDiv(lose, g + a, M.BPS)
			local arb = to == "g" and 0 or SlowMulDiv(lose, a, M.BPS)
			local share = SlowDiv(lose - cut, live)
			eq(r.losePool, lose, tag); eq(r.winPool, win, tag)
			eq(r.cut, cut, tag .. ": the cut"); eq(r.arbFee, arb, tag .. ": the arbiter's part"); eq(r.share, share, tag .. ": the share")
			local parts = 0
			for i, b in ipairs(raw) do
				if gone[b.o] then
					eq(r.payouts[i], b.s, tag .. ": scratched bet " .. i .. " back")
					scratchedBets = scratchedBets + 1
				elseif won[b.o] then
					local part = SlowMulDiv(share, b.s, pools[b.o])
					eq(r.payouts[i], b.s + part, tag .. ": winning ticket " .. i)
					parts = parts + part
					tickets = tickets + 1
					if share * b.s >= 2 ^ 53 then bigTickets = bigTickets + 1 end
				else
					eq(r.payouts[i], 0, tag .. ": losing ticket " .. i)
				end
			end
			-- The guild: the cut less the arbiter's part, and every copper the rounding left.
			eq(r.guildFee, cut - arb + (lose - cut - parts), tag .. ": the guild's")
		end
		-- The market object on the same bets pays every ticket the same.
		if k < n and #scratched == 0 then
			local outcomes = {}
			for i = 1, n do outcomes[i] = i end
			local mb, list = {}, {}
			for i, b in ipairs(raw) do mb[i] = { who = bets[i].who, outcome = b.o, copper = b.s } end
			for w in pairs(won) do list[#list + 1] = w end
			local mr = M.SettleMarket({ outcomes = outcomes, places = k, mode = to == "g" and "direct" or "arbiter",
				fee = g + a, arbiterFee = a, bets = mb }, list)
			for i = 1, #raw do eq(mr.bets[i], r.payouts[i], tag .. ": ticket " .. i .. " as a market object") end
			eq(mr.guild, r.guildFee, tag); eq(mr.arbiter, r.arbFee, tag)
		end
	end
	assert(settled > 400 and refunds > 40 and scratchedBets > 300 and tickets > 3000 and bigTickets > 600,
		"every case exercised (" .. settled .. " settled, " .. refunds .. " refunds, " .. scratchedBets .. " scratched bets, "
		.. tickets .. " winning tickets, " .. bigTickets .. " past 2^53)")
end)

---------------------------------------------------------------------------
-- The bracket pool (the design)
---------------------------------------------------------------------------

-- An 8-slot bracket (3 rounds, 7 picks: round 1's four matches top to bottom, the two
-- semi-finals, the final). The result: 1 beats 2, 4 beats 3, 5 beats 6, 8 beats 7; 4 beats 1,
-- 5 beats 8; 5 wins the final. Bits 0,1,0,1, 1,0, 1 and a 0 pad: 0101 1010 = "5a".
local RESULT8 = "P5a"

test("ArenaMath: picks go in hex, most significant bit first, padded to a digit, and back", function()
	local bits = M.Picks(RESULT8, 3)
	eq(#bits, 7)
	local want = { 0, 1, 0, 1, 1, 0, 1 }
	for i = 1, 7 do eq(bits[i], want[i], "pick " .. i) end
	eq(M.PickHex(bits), "5a")
	eq(M.PickHex({ 1 }), "8", "one pick: the top bit of one digit")
	eq(M.PickHex({ 0, 1, 1 }), "6")
	eq(#M.Picks("pda", 3), 7, "a lower-case p, as the ledger's b writes it")
	eq(#M.Picks("5A", 3), 7, "no p, upper case")
	-- 64 slots: 63 picks in 16 digits, the last bit padding.
	local all = {}
	for i = 1, 63 do all[i] = 1 end
	eq(M.PickHex(all), "fffffffffffffffe")
	eq(#M.Picks("pfffffffffffffffe", 6), 63)
	local function No(hex, rounds, why)
		local r, w = M.Picks(hex, rounds)
		eq(r, nil, tostring(hex)); eq(w, why, tostring(hex))
	end
	No("pffffffffffffffff", 6, "picks") -- the padding bit set
	No("p5b", 3, "picks")
	No("p9", 1, "picks")
	No("p5", 3, "picks") -- too short
	No("p5a0", 3, "picks") -- too long
	No("pzz", 3, "picks")
	No("p5-", 3, "picks")
	No(90, 3, "picks")
	No("p5a", 0, "rounds")
	No("p5a", 7, "rounds")
	No("p5a", 2.5, "rounds")
	eq(M.PickHex({ 0, 1 }), nil, "not 2^r - 1 picks")
	eq(M.PickHex({ 0, 2, 1 }), nil)
	eq(M.PickHex({ 0, 1, 1, x = 1 }), nil)
	eq(M.PickHex(nil), nil)
end)

test("ArenaMath: a pick scores when the fighter it sends through wins, worth 2^(round - 1)", function()
	eq(M.PickScore("p5a", RESULT8, 3), 12, "a perfect bracket: 4 + 2 x 2 + 4")
	-- Every upper slot: right on 1 and 5 in round 1, on 5 in the semi-final.
	eq(M.PickScore("p00", RESULT8, 3), 4)
	-- Every lower slot in round 1, then 4, 6, and 4 for the title: 2 + 2.
	eq(M.PickScore("pf8", RESULT8, 3), 4)
	-- 2, 4, 5, 8; then 4 and 5; 5 champion: wrong only on the first match.
	eq(M.PickScore("pda", RESULT8, 3), 11)
	-- 1, 3, 5, 7; then 3 (the lower slot), 5; 5 champion. The first semi-final's bit is the
	-- result's (lower), but it sends 3 through where 4 won: no points. 2 + 2 + 4, not 10.
	eq(M.PickScore("p0a", RESULT8, 3), 8)
	eq(M.PickScore("p8", "P8", 1), 1, "two slots: one pick")
	eq(M.PickScore("p0", "P8", 1), 0)
	local all = {}
	for i = 1, 63 do all[i] = i % 3 == 0 and 1 or 0 end
	local hex = M.PickHex(all)
	eq(M.PickScore("p" .. hex, "P" .. hex, 6), 192, "64 slots: 6 rounds of 32 points")
	local r, why = M.PickScore("p5a", "P5", 3)
	eq(r, nil); eq(why, "results")
	r, why = M.PickScore("p5", RESULT8, 3)
	eq(r, nil); eq(why, "picks")
	r, why = M.PickScore("p5a", RESULT8, 9)
	eq(r, nil); eq(why, "rounds")
end)

test("ArenaMath: Pickem settles a bracket pool from the ledger's picks and result: the best score takes the winnings", function()
	-- Five 1g entries, as the ledger's b entries carry them (p<hex>), and its x result (P<hex>).
	local entries = {
		B("p5a", GOLD, "Lida-Realm"),   -- 12, the best
		B("p00", GOLD, "Parric-Realm"), -- 4
		B("pf8", GOLD, "Wenna-Realm"),  -- 4
		B("pda", GOLD, "Torvin-Realm"), -- 11
		B("p0a", GOLD, "Selka-Realm"),  -- 8
	}
	local r = M.Pickem(entries, RESULT8, 3)
	eq(r.refund, nil)
	local scores = { 12, 4, 4, 11, 8 }
	for i = 1, 5 do eq(r.scores[i], scores[i], "entry " .. i) end
	eq(r.top, 12); eq(#r.winners, 1); eq(r.winners[1], 1)
	-- 4g lost: 24s cut (8s the arbiter's), 3g 76s to the one winner.
	eq(r.payouts[1], 4 * GOLD + 76 * SILVER)
	for i = 2, 5 do eq(r.payouts[i], 0, "entry " .. i) end
	eq(r.guildFee, 16 * SILVER); eq(r.arbFee, 8 * SILVER)
	eq(r.byWho["Lida-Realm"], 4 * GOLD + 76 * SILVER)
	eq(Out(r), 5 * GOLD)
	-- The King arbitrates: all 6% to the guild.
	r = M.Pickem(entries, RESULT8, 3, { to = "g" })
	eq(r.payouts[1], 4 * GOLD + 76 * SILVER); eq(r.guildFee, 24 * SILVER); eq(r.arbFee, 0)
	-- The same result settles the same, every time and on every client.
	local again = M.Pickem(entries, "5A", 3)
	for i = 1, 5 do eq(again.payouts[i], M.Pickem(entries, RESULT8, 3).payouts[i]) end
end)

test("ArenaMath: Pickem splits evenly between the best scores, entry by entry, with the rounding to the guild", function()
	-- Three perfect entries (two of them the same picks, paid apart) and four others, 1g each:
	-- 4g lost, 3g 76s shared three ways is 12,533c each, and the odd copper is the guild's.
	local entries = {
		B("p5a", GOLD, "Lida-Realm"), B("p5A", GOLD, "Parric-Realm"), B("p5a", GOLD, "Parric-Realm"),
		B("p00", GOLD), B("pf8", GOLD), B("pda", GOLD), B("p0a", GOLD),
	}
	local r = M.Pickem(entries, RESULT8, 3)
	eq(#r.winners, 3)
	eq(r.payouts[1], 22533); eq(r.payouts[2], 22533); eq(r.payouts[3], 22533)
	eq(r.byWho["Parric-Realm"], 2 * 22533, "his two entries, each paid on its own")
	eq(r.guildFee, 1601, "16s and the copper left"); eq(r.arbFee, 800)
	eq(r.remainder, 1)
	eq(Out(r), 7 * GOLD)
end)

test("ArenaMath: Pickem refunds a tie (all zero too) and an empty pool, and refuses a malformed ledger whole", function()
	local function Refund(r, reason, n, stake)
		eq(r.refund, reason)
		eq(r.guildFee, 0); eq(r.arbFee, 0)
		for i = 1, n do eq(r.payouts[i], stake, reason .. " " .. i) end
	end
	-- Two slots, the lower won; both picked the upper: both 0.
	Refund(M.Pickem({ B("p0", GOLD), B("p0", GOLD) }, "P8", 1), "tied", 2, GOLD)
	-- Everyone perfect.
	Refund(M.Pickem({ B("p5a", 5 * GOLD), B("p5a", 5 * GOLD), B("p5a", 5 * GOLD) }, RESULT8, 3), "tied", 3, 5 * GOLD)
	-- One entry alone: nobody to win from.
	local r = M.Pickem({ B("p00", GOLD) }, RESULT8, 3)
	Refund(r, "tied", 1, GOLD)
	eq(r.scores[1], 4)
	r = M.Pickem({}, RESULT8, 3)
	Refund(r, "empty", 0)
	eq(r.pool, 0); eq(r.top, nil)
	local function No(want, entries, results, rounds, index, fee)
		local res, why, i = M.Pickem(entries, results, rounds, fee)
		eq(res, nil, want); eq(why, want, want); eq(i, index, want)
	end
	local good = { B("p5a", GOLD), B("p00", GOLD) }
	No("entries", nil, RESULT8, 3)
	No("entries", { a = B("p5a", GOLD) }, RESULT8, 3)
	No("rounds", good, RESULT8, 0)
	No("rounds", good, RESULT8, 7)
	No("fee", good, RESULT8, 3, nil, "6%")
	No("results", good, "P5", 3)
	No("results", good, nil, 3)
	No("results", good, "P5b", 3)
	No("entry", { B("p5a", GOLD), B("p5", GOLD) }, RESULT8, 3, 2)
	No("entry", { B("p5a", GOLD), B("p5a", 0) }, RESULT8, 3, 2)
	No("entry", { B("p5a", GOLD), B("p5a", GOLD, "") }, RESULT8, 3, 2)
	No("entry", { B("p5a", GOLD), "p00" }, RESULT8, 3, 2)
	No("stake", { B("p5a", GOLD), B("p00", 2 * GOLD) }, RESULT8, 3, 2)
end)

---------------------------------------------------------------------------
-- Direct mode (the design)
---------------------------------------------------------------------------

test("ArenaMath: a direct bet: the loser owes his own stake, the winner owes the guild the whole fee on it", function()
	local d = M.Direct(10 * GOLD, 10 * GOLD)
	eq(d.loserPays, 10 * GOLD); eq(d.guildFee, 60 * SILVER); eq(d.kept, 9 * GOLD + 40 * SILVER)
	-- Uneven stakes: what moves is the loser's.
	d = M.Direct(10 * GOLD, 1234567)
	eq(d.loserPays, 1234567); eq(d.guildFee, 74074, "rounded down to the copper"); eq(d.kept, 1160493)
	d = M.Direct(1234567, 10 * GOLD)
	eq(d.loserPays, 10 * GOLD); eq(d.guildFee, 60 * SILVER)
	-- No arbiter: the arbiter's rate is the guild's too, whatever "to" says.
	eq(M.Direct(10 * GOLD, 10 * GOLD, { g = 400, a = 200 }).guildFee, 60 * SILVER)
	eq(M.Direct(10 * GOLD, 10 * GOLD, { g = 400, a = 200, to = "a" }).guildFee, 60 * SILVER)
	eq(M.Direct(10 * GOLD, 10 * GOLD, { g = 1400, a = 100 }).guildFee, GOLD, "clamped to 10%")
	eq(M.Direct(10 * GOLD, 10 * GOLD, { g = 0, a = 0 }).guildFee, 0)
	local function No(want, sw, sl, fee)
		local r, why = M.Direct(sw, sl, fee)
		eq(r, nil, want); eq(why, want)
	end
	No("stake", 10 * GOLD, 0)
	No("stake", 0, 10 * GOLD)
	No("stake", 10 * GOLD, 10.5)
	No("stake", 10 * GOLD, MAX + 1)
	No("stake", nil, 10 * GOLD)
	No("fee", 10 * GOLD, 10 * GOLD, "0")
	No("fee", 10 * GOLD, 10 * GOLD, { g = 0 / 0 })
end)

---------------------------------------------------------------------------
-- Odds and previews (the design)
---------------------------------------------------------------------------

test("ArenaMath: the odds truncate to the hundredth: 2.41 and 1.62 in example 1, 2.50 and 1.66 without the fee", function()
	local pools = { A = 600 * GOLD, B = 400 * GOLD }
	eq(M.Odds(pools, "B"), 241)
	eq(M.Odds(pools, "A"), 162)
	eq(M.OddsText(M.Odds(pools, "B")), "2.41x")
	eq(M.Odds(pools, "B", { g = 0, a = 0 }), 250)
	eq(M.Odds(pools, "A", { g = 0, a = 0 }), 166)
	eq(M.Odds(pools, "B", { to = "g" }), 241, "the same fee, whoever takes it")
	-- Nobody on it yet: no odds ("the first bet sets the odds"); alone: refunded, 1.00.
	local r, why = M.Odds(pools, "C")
	eq(r, nil); eq(why, nil, "not an error")
	eq(M.Odds({ A = 0, B = 5 * GOLD }, "A"), nil)
	eq(M.Odds({ A = 5 * GOLD }, "A"), 100)
	eq(M.OddsText(100), "1.00x"); eq(M.OddsText(1234), "12.34x"); eq(M.OddsText(7), "0.07x")
	eq(M.OddsText(nil), nil)
	for _, bad in ipairs({ -1, 1.5, "241" }) do eq(M.OddsText(bad), nil) end
	local function No(want, ...)
		local res, w = M.Odds(...)
		eq(res, nil, want); eq(w, want)
	end
	No("pools", nil, "A")
	No("pools", { A = -1 }, "A")
	No("pools", { A = 1.5 }, "A")
	No("pools", { A = "5" }, "A")
	No("pools", { [""] = 5 }, "A")
	No("pools", { A = M.MAX_POOL, B = 1 }, "A")
	No("outcome", pools, nil)
	No("outcome", pools, "")
	No("fee", pools, "A", "6%")
	r, why = M.OddsAtLeast(pools, "A", 0)
	eq(r, nil); eq(why, "k")
	r, why = M.OddsAtLeast(pools, "A", 1.5)
	eq(r, nil); eq(why, "k")
	eq(M.OddsAtLeast(pools, "B", 1), 241, "one place is Odds")
end)

test("ArenaMath: the odds are what a 1-gold ticket in the pool is paid, truncated: never more, over random pools", function()
	local Rand = Randoms(42)
	for round = 1, 300 do
		local tag = "round " .. round
		local n = Rand(7) + 1
		local g = Rand(701) - 1
		local a = Rand(301) - 1
		local fee = { g = g, a = a }
		-- One 1g ticket on the first outcome, and random bets on every outcome.
		local bets = { B(1, GOLD) }
		for i = 1, Rand(20) do bets[#bets + 1] = B(Rand(n), Rand(Rand(2) == 1 and 50 * GOLD or MAX)) end
		local pools = {}
		for i = 1, n do pools[i] = 0 end
		for _, b in ipairs(bets) do pools[b.o] = pools[b.o] + b.s end
		local odds = M.Odds(pools, 1, fee)
		local paid = M.Settle(bets, 1, fee).payouts[1]
		eq(odds, floor(paid / 100), tag .. ": the 1g ticket's payout, truncated")
		assert(odds * 100 <= paid, tag .. ": never promises more than it pays")
		-- With k places, the least over every other set of winners.
		if n >= 3 then
			local least
			for other = 2, n do
				local pay = M.Settle(bets, { 1, other }, fee).payouts[1]
				least = least and (pay < least and pay or least) or pay
			end
			local at = M.OddsAtLeast(pools, 1, 2, fee)
			eq(at, floor(least / 100), tag .. ": two places, the worst case")
			assert(at <= odds, tag .. ": at least never above the single-winner odds")
		end
	end
end)

test("ArenaMath: with 1 to 8 places, the odds and the preview are the least paid over every set of winners", function()
	-- The markets section's test 5: 2 to 10 outcomes, k from 1 to 8, a 1-gold ticket on outcome 1
	-- and random bets (some outcomes left unbacked), and a new whole-silver bet for the preview.
	-- For every set of k winners that holds outcome 1, Settle pays the ticket at least the odds,
	-- and the new bet at least the preview; the least of them is exactly each.
	local Rand = Randoms(46656)
	local sets, byK = 0, {}
	for round = 1, 300 do
		local tag = "round " .. round
		local n = Rand(9) + 1
		local k = Rand(n - 1 < 8 and n - 1 or 8)
		local g = Rand(701) - 1
		local a = Rand(301) - 1
		local form = Rand(3)
		local fee = form == 1 and { g = g, a = a } or form == 2 and { g + a, a } or { feeBp = g + a, arbBp = a }
		local bets = { B(1, GOLD) }
		for _ = 1, Rand(20) - 1 do bets[#bets + 1] = B(Rand(n), Rand(Rand(2) == 1 and 50 * GOLD or MAX)) end
		local pools = {}
		for o = 1, n do pools[o] = 0 end
		for _, b in ipairs(bets) do pools[b.o] = pools[b.o] + b.s end
		local s = Rand(10000) * SILVER
		local with = {}
		for i, b in ipairs(bets) do with[i] = b end
		with[#with + 1] = B(1, s)
		local odds = M.OddsAtLeast(pools, 1, k, fee)
		local preview = M.Preview(pools, 1, s, fee, k)
		if k == 1 then
			eq(odds, M.Odds(pools, 1, fee), tag .. ": one place is Odds")
			eq(preview, M.Preview(pools, 1, s, fee), tag)
		end
		local least, leastNew
		local set = { 1 }
		local function Walk(from)
			if #set == k then
				local winners = {}
				for i, o in ipairs(set) do winners[i] = o end
				local pay = M.Settle(bets, winners, fee).payouts[1]
				assert(odds * 100 <= pay, tag .. ": odds " .. odds .. " promise more than the " .. pay .. "c paid with "
					.. table.concat(winners, ","))
				least = least and (pay < least and pay or least) or pay
				local payNew = M.Settle(with, winners, fee).payouts[#with]
				assert(preview <= payNew, tag .. ": the preview " .. preview .. " is more than the " .. payNew .. "c paid")
				leastNew = leastNew and (payNew < leastNew and payNew or leastNew) or payNew
				sets = sets + 1
				return
			end
			for o = from, n do
				set[#set + 1] = o
				Walk(o + 1)
				set[#set] = nil
			end
		end
		Walk(2)
		eq(odds, floor(least / 100), tag .. ": the worst case, truncated")
		eq(preview, leastNew, tag .. ": the worst case, to the copper")
		byK[k] = (byK[k] or 0) + 1
	end
	for k = 1, 8 do assert((byK[k] or 0) >= 3, "k = " .. k .. " exercised (" .. tostring(byK[k]) .. " rounds)") end
	assert(sets > 3000, "enough sets of winners (" .. sets .. ")")
end)

test("ArenaMath: a preview is what the new bet is paid if nothing else comes in", function()
	local pools = { A = 600 * GOLD, B = 400 * GOLD }
	eq(M.Preview(pools, "B", 10 * GOLD), 237560, "10g more on B: 564g of winnings over 410g on B")
	local bets = Example1()
	bets[#bets + 1] = B("B", 10 * GOLD, "Oswin-Realm")
	eq(M.Settle(bets, "B").payouts[#bets], 237560, "and settling pays exactly that")
	eq(M.Preview({ A = 600 * GOLD }, "B", 10 * GOLD), 10 * GOLD + 564 * GOLD, "the first bet on B takes all of A's")
	eq(M.Preview({ A = 600 * GOLD }, "A", 10 * GOLD), 10 * GOLD, "more on the only side: a refund")
	eq(M.Preview(pools, "B", 10 * GOLD, { to = "g" }), 237560)
	-- Two places: the least over every other finalist.
	local bets3 = Example3()
	local p3 = {}
	for _, b in ipairs(bets3) do p3[b.o] = (p3[b.o] or 0) + b.s end
	local q = M.Preview(p3, 5, 10 * GOLD, nil, 2)
	bets3[#bets3 + 1] = B(5, 10 * GOLD)
	local least
	for other = 1, 8 do
		if other ~= 5 then
			local pay = M.Settle(bets3, { 5, other }).payouts[#bets3]
			assert(pay >= q, "paid under the preview with " .. other)
			least = least and (pay < least and pay or least) or pay
		end
	end
	eq(least, q)
	local function No(want, ...)
		local r, w = M.Preview(...)
		eq(r, nil, want); eq(w, want)
	end
	No("pools", "pools", "A", GOLD)
	No("outcome", pools, nil, GOLD)
	No("copper", pools, "B", 0)
	No("copper", pools, "B", 10.5)
	No("copper", pools, "B", MAX + 1)
	No("k", pools, "B", GOLD, nil, 0)
	No("fee", pools, "B", GOLD, { to = 1 })
	No("pool", { A = M.MAX_POOL - 10 }, "B", 11)
	assert(M.Preview({ A = M.MAX_POOL - 10 }, "B", 10), "the last copper that fits")
end)

---------------------------------------------------------------------------
-- Limits (the design)
---------------------------------------------------------------------------

-- The design's table, in gold, by tier 0..5.
local TABLE = {
	bet = { 5, 10, 20, 40, 80, 150 },
	balance = { 50, 100, 200, 400, 800, 1500 },
	daily = { 25, 50, 100, 200, 400, 750 },
	direct = { 1, 2, 5, 10, 20, 50 },
}

test("ArenaMath: BetCap is the design's table: a tier per 5 points up to 5, direct from 3 points", function()
	local points = { [0] = { 0, 4 }, { 5, 9 }, { 10, 14 }, { 15, 19 }, { 20, 24 }, { 25, 1000 } }
	for kind, row in pairs(TABLE) do
		for tier = 0, 5 do
			for _, p in ipairs(points[tier]) do
				-- The direct cap also needs a paid history big enough not to bind (the design).
				local record = { points = p, paidMax = 100 * GOLD }
				local want = row[tier + 1] * GOLD
				if kind == "direct" and p < 3 then want = 0 end
				eq(M.BetCap(record, kind), want, kind .. " at " .. p .. " points")
			end
		end
	end
	eq(M.BetCap(nil, "bet"), 5 * GOLD, "a newcomer: tier 0")
	eq(M.BetCap({}, "daily"), 25 * GOLD)
	eq(M.BetCap({ points = 3, paidMax = 100 * GOLD }, "direct"), GOLD, "1g from 3 points")
	local cap, why = M.BetCap({ points = 2 }, "direct")
	eq(cap, 0); eq(why, "history")
	cap, why = M.BetCap(nil, "direct")
	eq(cap, 0); eq(why, "history")
	-- Probation: a tier lower, never below 0.
	eq(M.BetCap({ points = 12, probation = true }, "bet"), 10 * GOLD)
	eq(M.BetCap({ probation = true }, "bet"), 5 * GOLD)
	eq(M.BetCap({ points = 5, probation = true, paidMax = 100 * GOLD }, "direct"), GOLD)
	eq(M.Tier("bet", { points = 12 }), 2)
	eq(M.Tier("bet", { points = 12, probation = true }), 1)
	eq(M.Tier("direct", { points = 1e300 }), 5)
	-- The review's case: 10 on time, then 1 late: 5 points, 10g; 5g while on probation.
	eq(M.BetCap({ points = M.Points({ true, true, true, true, true, true, true, true, true, true, false }) }, "bet"), 10 * GOLD)
	-- Kinds: an arbiter's holding cap is the King's T1~M, never computed from points here.
	cap, why = M.BetCap({ points = 25 })
	eq(cap, nil, "no kind"); eq(why, "kind")
	for _, kind in ipairs({ "hold", "deposit", "wallet", 100 }) do
		cap, why = M.BetCap({ points = 25 }, kind)
		eq(cap, nil, "kind " .. tostring(kind)); eq(why, "kind")
	end
	local t
	t, why = M.Tier("wallet", {})
	eq(t, nil); eq(why, "kind")
	t, why = M.Tier("bet", { points = -1 })
	eq(t, nil); eq(why, "record")
end)

test("ArenaMath: BetCap: the King's scale and limit, under the code ceilings", function()
	eq(M.BetCap({ points = 25 }, "bet", 300), 450 * GOLD, "300%")
	eq(M.BetCap({ points = 25 }, "bet", 1000), 450 * GOLD, "clamped to 300%")
	eq(M.BetCap({}, "bet", 25), 12500, "25%: 1g 25s")
	eq(M.BetCap({}, "bet", 10), 12500, "clamped to 25%")
	eq(M.BetCap({ points = 25 }, "balance", 300), 4500 * GOLD, "under its 5,000g ceiling")
	eq(M.BetCap({ points = 25 }, "daily", 300), 2250 * GOLD, "under its 2,500g ceiling")
	eq(M.BetCap({ points = 25, paidMax = 100 * GOLD }, "direct", 300), 100 * GOLD, "150g held to the 100g ceiling")
	for _, bad in ipairs({ "x", 0 / 0, true }) do
		local cap, w = M.BetCap({ points = 25 }, "bet", bad)
		eq(cap, 0, "a nonsense scale closes it: " .. tostring(bad)); eq(w, "scale")
	end
	-- The limit only lowers.
	eq(M.BetCap({ points = 25 }, "bet", nil, 30 * GOLD), 30 * GOLD)
	eq(M.BetCap({}, "bet", nil, 30 * GOLD), 5 * GOLD, "not raised")
	eq(M.BetCap({ points = 25 }, "bet", nil, math.huge), 150 * GOLD)
	eq(M.BetCap({ points = 25 }, "bet", nil, 0), 0, "0 closes betting")
	eq(M.BetCap({ points = 25 }, "bet", nil, 12345.6), 12345, "whole copper")
	eq(M.BetCap({ points = 25, paidMax = 100 * GOLD }, "direct", 300, 50 * GOLD), 50 * GOLD, "the King's directMax")
	for _, bad in ipairs({ -5, "20", 0 / 0, true }) do
		local cap, why = M.BetCap({ points = 25 }, "bet", nil, bad)
		eq(cap, 0, "limit " .. tostring(bad)); eq(why, "limit")
		cap, why = M.BetCap({ points = 25, paidMax = 100 * GOLD }, "direct", nil, bad)
		eq(cap, 0, "direct limit " .. tostring(bad)); eq(why, "limit")
	end
end)

test("ArenaMath: any doubt about a debt, or a malformed record, closes every cap; a dispute closes the direct cap only", function()
	for _, open in ipairs({ 1, 0.5, true, "1", 0 / 0, { { copper = 5000 } }, { false }, { n = 0 }, math.huge }) do
		for kind in pairs(TABLE) do
			local cap, why = M.BetCap({ points = 1000, paidMax = 100 * GOLD, open = open }, kind)
			eq(cap, 0, kind .. " with open = " .. tostring(open)); eq(why, "open")
		end
	end
	for _, none in ipairs({ 0, -1, false }) do
		eq(M.BetCap({ points = 25, open = none }, "bet"), 150 * GOLD, "open = " .. tostring(none) .. " is none")
	end
	-- An empty list is no debt: what Debts.Open() gives when nothing is owed must not close every
	-- cap for everyone (the review's probe had BetCap({ points = 25, open = {} }, "bet") at 0).
	for kind, row in pairs(TABLE) do
		eq(M.BetCap({ points = 25, paidMax = 100 * GOLD, open = {} }, kind), row[6] * GOLD, kind .. " with open = {}")
		eq(M.BetCap({ points = 25, paidMax = 100 * GOLD, dispute = {} }, kind), row[6] * GOLD, kind .. " with dispute = {}")
	end
	eq(M.DirectTier({ points = 25, open = {}, dispute = {} }), 5)
	eq(M.HoldAdvice({ points = 50, open = {} }), 3000 * GOLD)
	-- An open direct-mode dispute (the design) closes his direct cap until an auditor clears it.
	for _, dispute in ipairs({ 1, true, "X" }) do
		local cap, why = M.BetCap({ points = 25, paidMax = 100 * GOLD, dispute = dispute }, "direct")
		eq(cap, 0); eq(why, "dispute")
		eq(M.BetCap({ points = 25, dispute = dispute }, "bet"), 150 * GOLD, "his wallet bets stay")
	end
	for _, record in ipairs({ { points = "x" }, { points = -4 }, { points = 1.5 }, { points = 0 / 0 },
		{ probation = "yes" }, { probation = 1 }, { paidMax = -1 }, { paidMax = "1g" }, "x", 5 }) do
		for kind in pairs(TABLE) do
			local cap, why = M.BetCap(record, kind)
			eq(cap, 0, "a malformed record, " .. kind); eq(why, "record")
		end
		local cap, why = M.HoldAdvice(record)
		eq(cap, 0); eq(why, "record")
	end
end)

test("ArenaMath: DirectCap: 1 gold before any paid direct debt, then at most twice the largest paid, under the tier's cap", function()
	eq(M.DirectCap(0, 0), GOLD)
	eq(M.DirectCap(0, nil), GOLD)
	eq(M.DirectCap(5, 0), GOLD, "tier 5 but nothing paid yet: 1g")
	eq(M.DirectCap(5, 30 * SILVER), GOLD, "twice 30s is under 1g")
	eq(M.DirectCap(5, 5 * GOLD), 10 * GOLD, "twice 5g")
	eq(M.DirectCap(5, 25 * GOLD), 50 * GOLD)
	eq(M.DirectCap(5, 100 * GOLD), 50 * GOLD, "the tier's 50g")
	eq(M.DirectCap(2, GOLD), 2 * GOLD)
	eq(M.DirectCap(2, 3 * GOLD), 5 * GOLD, "the tier's 5g")
	eq(M.DirectCap(1, 0), GOLD)
	-- Paid on time, one after another: the cap grows 1g, 2g, 4g, 8g, 16g, then the tier's 50g.
	local cap, paid = M.DirectCap(5, 0), 0
	local seen = {}
	for _ = 1, 7 do
		seen[#seen + 1] = cap / GOLD
		paid = cap
		cap = M.DirectCap(5, paid)
	end
	eq(table.concat(seen, ","), "1,2,4,8,16,32,50")
	-- The King's scale bounds the tier's cap, not the 1g floor of the history rule.
	eq(M.DirectCap(0, 0, 25), 2500, "25% of 1g")
	eq(M.DirectCap(5, 100 * GOLD, 300), 100 * GOLD, "the 100g ceiling")
	eq(M.DirectCap(5, 100 * GOLD, nil, 20 * GOLD), 20 * GOLD, "the King's directMax")
	local function No(want, ...)
		local c, w = M.DirectCap(...)
		eq(c, 0, want); eq(w, want)
	end
	No("history", M.NO_DIRECT, 100 * GOLD)
	No("tier", 6, 0)
	No("tier", -2, 0)
	No("tier", 1.5, 0)
	No("tier", "1", 0)
	No("tier", nil, 0)
	No("paidMax", 5, -1)
	No("paidMax", 5, 1.5)
	No("paidMax", 5, "5g")
	No("scale", 5, 0, "x")
	No("limit", 5, 0, nil, -1)
	-- BetCap's direct kind is the same rule over the record's paidMax.
	eq(M.BetCap({ points = 10, paidMax = 2 * GOLD }, "direct"), 4 * GOLD)
	eq(M.BetCap({ points = 25 }, "direct"), GOLD, "no paidMax: nothing paid yet")
end)

test("ArenaMath: DirectTier is the tier a bank signs into a standing token, or NO_DIRECT", function()
	eq(M.NO_DIRECT, -1)
	local function Tier(record, want, why)
		local t, w = M.DirectTier(record)
		eq(t, want, tostring(why)); eq(w, why)
	end
	Tier(nil, M.NO_DIRECT, "history")
	Tier({ points = 2 }, M.NO_DIRECT, "history")
	Tier({ points = 3 }, 0, nil)
	Tier({ points = 5, probation = true }, 0, nil)
	Tier({ points = 10 }, 2, nil)
	Tier({ points = 1000 }, 5, nil)
	Tier({ points = 25, open = 1 }, M.NO_DIRECT, "open")
	Tier({ points = 25, dispute = true }, M.NO_DIRECT, "dispute")
	Tier({ points = "x" }, M.NO_DIRECT, "record")
	-- Probation is a tier lower (the design), and below the direct row's tier 0 (1g) is its
	-- "none": a player who just paid late gets no direct credit until the 7 days pass.
	Tier({ points = 3, probation = true }, M.NO_DIRECT, "probation")
	Tier({ points = 4, probation = true }, M.NO_DIRECT, "probation")
	Tier({ points = 9, probation = true }, 0, nil)
	Tier({ points = 25, probation = true }, 4, nil)
	local cap, why = M.BetCap({ points = 3, probation = true, paidMax = 10 * GOLD }, "direct")
	eq(cap, 0, "3 points on probation: no direct bet"); eq(why, "probation")
	eq(M.BetCap({ points = 3, paidMax = 10 * GOLD }, "direct"), GOLD, "1g once the probation ends")
	eq(M.BetCap({ points = 3, probation = true }, "bet"), 5 * GOLD, "his wallet bets stay at tier 0")
	eq(M.BetCap({ points = 25, probation = true, paidMax = 100 * GOLD }, "direct"), 20 * GOLD, "tier 5 on probation: tier 4's 20g")
	-- The opponent's side, from the token: the same cap as the bank's own record gives.
	local record = { points = 17, paidMax = 7 * GOLD }
	eq(M.DirectCap(M.DirectTier(record), record.paidMax), M.BetCap(record, "direct"))
	eq(M.BetCap(record, "direct"), 10 * GOLD, "tier 3's 10g, under twice 7g")
end)

test("ArenaMath: Earns: a settled stake earns a point only from a quarter of the tier's cap and the minimum bet", function()
	-- Tier 0's wallet cap is 5g: a quarter is 1g 25s.
	local cap = M.BetCap(nil, "bet")
	eq(M.Earns(12500, cap), true, "exactly a quarter")
	local ok, why = M.Earns(12400, cap)
	eq(ok, false); eq(why, "small")
	-- Tier 5's 150g: 37g 50s.
	cap = M.BetCap({ points = 25 }, "bet")
	eq(M.Earns(37 * GOLD + 50 * SILVER, cap), true)
	eq((M.Earns(37 * GOLD + 49 * SILVER, cap)), false)
	-- Three 10s bets a day no longer climb the tiers: at no tier does a 10s stake earn.
	for points = 0, 25, 5 do
		eq((M.Earns(10 * SILVER, M.BetCap({ points = points }, "bet"))), false, "10s at " .. points .. " points")
	end
	-- The minimum bet, the default or the King's.
	ok, why = M.Earns(5 * SILVER, 0)
	eq(ok, false); eq(why, "min")
	eq(M.Earns(M.MIN_BET, 0), true, "a closed cap's quarter is 0")
	ok, why = M.Earns(50 * SILVER, 0, GOLD)
	eq(ok, false); eq(why, "min")
	eq(M.Earns(GOLD, 0, GOLD), true)
	-- A direct bet against its own tier's cap: tier 2's 5g, a quarter 1g 25s.
	eq(M.Earns(2 * GOLD, M.BetCap({ points = 10, paidMax = 100 * GOLD }, "direct")), true)
	local function No(want, ...)
		local r, w = M.Earns(...)
		eq(r, false, want); eq(w, want)
	end
	No("stake", 0, 0)
	No("stake", 10.5, 0)
	No("stake", "1g", 0)
	No("stake", MAX + 1, 0)
	No("cap", GOLD, -1)
	No("cap", GOLD, nil)
	No("cap", GOLD, 1.5)
	No("rules", GOLD, 0, 0)
	No("rules", GOLD, 0, "10s")
end)

test("ArenaMath: standing points: one per payment on time, halved by a late one", function()
	eq(M.Points(nil), 0)
	eq(M.Points({}), 0)
	eq(M.Points({ true, true, true, true, true, true, true, true, true, true }), 10)
	eq(M.Points({ true, true, true, true, true, true, true, true, true, true, false }), 5, "a late payment halves them")
	eq(M.Points({ true, true, true, false, true }), 2, "halved to 1, then one more")
	eq(M.Points({ false, true }), 1)
	local p, why, index = M.Points({ true, "yes" })
	eq(p, nil); eq(why, "history"); eq(index, 2)
	local holed = { true }
	holed[3] = true
	eq((M.Points(holed)), nil, "a hole")
	eq((M.Points({ true, late = false })), nil, "a keyed entry")
	eq((M.Points("x")), nil)
end)

test("ArenaMath: an arbiter's cap is the King's (T1~M): Room under it, and the design's points as advice only", function()
	eq(M.Room(200 * GOLD, 150 * GOLD), 50 * GOLD)
	eq(M.Room(200 * GOLD, 300 * GOLD), 0, "over the cap: no room, never negative")
	eq(M.Room(200 * GOLD, 0), 200 * GOLD)
	eq(M.Room(0, 0), 0, "no cap set: nothing")
	-- What he holds must be stated: a missing or nonsense amount is never read as nothing held.
	local room, w = M.Room(200 * GOLD, nil)
	eq(room, 0, "held left out"); eq(w, "held")
	for _, held in ipairs({ "1500000", 0 / 0, -1, 1.5 }) do
		room, w = M.Room(200 * GOLD, held)
		eq(room, 0, "held " .. tostring(held)); eq(w, "held")
	end
	-- On the T1~M list without a cap: the lowest tier's 100g (the design), not nothing.
	eq(M.HOLD_DEFAULT, 100 * GOLD)
	eq(M.Room(nil, 0), 100 * GOLD, "no cap in T1~M")
	eq(M.Room(nil, 30 * GOLD), 70 * GOLD)
	eq(M.Room(nil, 150 * GOLD), 0)
	room, w = M.Room(nil, nil)
	eq(room, 0); eq(w, "held")
	for _, cap in ipairs({ "200g", -1, 1.5, false, 0 / 0 }) do
		room, w = M.Room(cap, 0)
		eq(room, 0, "cap " .. tostring(cap)); eq(w, "cap")
	end
	-- The advice auditors may see: a tier per 10 clean matches, no probation, an owed fee 0.
	eq(M.HoldAdvice({}), 100 * GOLD)
	eq(M.HoldAdvice({ points = 9 }), 100 * GOLD)
	eq(M.HoldAdvice({ points = 10 }), 200 * GOLD)
	eq(M.HoldAdvice({ points = 50 }), 3000 * GOLD)
	eq(M.HoldAdvice({ points = 10, probation = true }), 200 * GOLD)
	eq(M.HoldAdvice({ points = 50 }, 300), 5000 * GOLD, "9,000g held to the 5,000g ceiling")
	eq(M.Tier("hold", { points = 12 }), 1)
	local cap, why = M.HoldAdvice({ points = 1000, open = 1 })
	eq(cap, 0); eq(why, "open")
	cap, why = M.HoldAdvice({ points = 10 }, "x")
	eq(cap, 0); eq(why, "scale")
end)

test("ArenaMath: BetOk checks whole silver, the minimum, the cap over all his bets on the market, the day and the pool", function()
	eq(M.BetOk(M.MIN_BET, 5 * GOLD, 0), true)
	eq(M.BetOk(5 * GOLD, 5 * GOLD, 0), true, "the cap itself")
	local function No(want, ...)
		local ok, why = M.BetOk(...)
		eq(ok, false, want); eq(why, want)
	end
	No("min", M.MIN_BET - SILVER, 5 * GOLD, 0)
	No("silver", 1050, 5 * GOLD, 0)
	No("cap", 5 * GOLD + SILVER, 5 * GOLD, 0)
	No("cap", M.MIN_BET, 0, 0) -- a cap of 0 (a debt open)
	No("cap", M.MIN_BET, nil, 0)
	No("cap", M.MIN_BET, 0 / 0, 0)
	No("copper", 1500.5, 5 * GOLD, 0)
	No("copper", "20", 5 * GOLD, 0)
	No("copper", 0, 5 * GOLD, 0)
	No("copper", MAX + 1, 5 * GOLD, 0)
	-- What he already has on the market counts.
	eq(M.BetOk(GOLD, 5 * GOLD, 4 * GOLD), true)
	No("cap", GOLD + SILVER, 5 * GOLD, 4 * GOLD)
	No("cap", M.MIN_BET, 5 * GOLD, 5 * GOLD)
	No("staked", M.MIN_BET, 5 * GOLD, nil)
	No("staked", M.MIN_BET, 5 * GOLD, "0")
	No("staked", M.MIN_BET, 5 * GOLD, -1)
	-- The King's minimum.
	No("min", 50 * SILVER, 5 * GOLD, 0, { minBet = GOLD })
	eq(M.BetOk(SILVER, 5 * GOLD, 0, { minBet = SILVER }), true, "his 1s")
	No("rules", GOLD, 5 * GOLD, 0, { minBet = 50 })
	No("rules", GOLD, 5 * GOLD, 0, { minBet = 20 * GOLD })
	No("rules", GOLD, 5 * GOLD, 0, { minBet = "10s" })
	No("rules", GOLD, 5 * GOLD, 0, "rules")
	-- A day's most, over every market.
	No("day", 10 * GOLD, 20 * GOLD, 0, { maxDay = 60 * GOLD, today = 55 * GOLD })
	eq(M.BetOk(10 * GOLD, 20 * GOLD, 0, { maxDay = 60 * GOLD, today = 50 * GOLD }), true, "up to the day's most")
	No("rules", 10 * GOLD, 20 * GOLD, 0, { maxDay = 60 * GOLD })
	-- A market's most.
	No("pool", 10 * GOLD, 20 * GOLD, 0, { maxPool = 1000 * GOLD, pool = 995 * GOLD })
	eq(M.BetOk(10 * GOLD, 20 * GOLD, 0, { maxPool = 1000 * GOLD, pool = 990 * GOLD }), true)
	No("rules", 10 * GOLD, 20 * GOLD, 0, { maxPool = 1000 * GOLD })
end)

test("ArenaMath: net-off pays a debtor's debts from his winnings, oldest first", function()
	local paid, left = M.NetOff(30 * GOLD, { 10 * GOLD, 25 * GOLD })
	eq(paid[1], 10 * GOLD); eq(paid[2], 20 * GOLD); eq(left, 0)
	paid, left = M.NetOff(50 * GOLD, { 10 * GOLD, 25 * GOLD })
	eq(paid[1], 10 * GOLD); eq(paid[2], 25 * GOLD); eq(left, 15 * GOLD)
	paid, left = M.NetOff(5 * GOLD, {})
	eq(#paid, 0); eq(left, 5 * GOLD)
	paid, left = M.NetOff(5 * GOLD, nil)
	eq(left, 5 * GOLD)
	paid, left = M.NetOff(0, { GOLD })
	eq(paid[1], 0); eq(left, 0)
	-- A debt that isn't a whole amount is refused, not read as 0 (which hands the winnings back).
	local why, index
	paid, why, index = M.NetOff(10 * GOLD, { 5 * GOLD, "3g" })
	eq(paid, nil); eq(why, "debts"); eq(index, 2)
	paid, why = M.NetOff(10 * GOLD, { first = 5 * GOLD })
	eq(paid, nil); eq(why, "debts")
	paid, why = M.NetOff(10 * GOLD, { 0 / 0 })
	eq(paid, nil); eq(why, "debts")
	for _, bad in ipairs({ -1, 10.5, 0 / 0, "10" }) do
		paid, why = M.NetOff(bad, { GOLD })
		eq(paid, nil, tostring(bad)); eq(why, "copper")
	end
end)

---------------------------------------------------------------------------
-- The market object (the same formula, for a holder of a whole market)
---------------------------------------------------------------------------

local function Market(mode, fee, bets, outcomes)
	return { outcomes = outcomes or { "A", "B" }, mode = mode, fee = fee, bets = bets }
end

local function Bet(who, outcome, copper) return { who = who, outcome = outcome, copper = copper } end

-- What left the pool: every payout, the guild's and the arbiter's.
local function PaidOut(r)
	local sum = r.guild + r.arbiter
	for _, c in pairs(r.payouts) do sum = sum + c end
	return sum
end

-- The proposal's example (3.5): 30 players with 20g on A, 20 with 20g on B.
local function Example(mode, fee)
	local bets = {}
	for i = 1, 30 do bets[#bets + 1] = Bet("Aster" .. i .. "-Realm", "A", 20 * GOLD) end
	for i = 1, 20 do bets[#bets + 1] = Bet("Bramble" .. i .. "-Realm", "B", 20 * GOLD) end
	return Market(mode, fee, bets)
end

-- The design's example 3 as a market: "reaches the final", one bettor per 10g.
local function Final()
	local bets = {}
	for slot, g in ipairs({ 300, 200, 100, 100, 50, 50, 100, 100 }) do
		for i = 1, g / 10 do bets[#bets + 1] = Bet("Slot" .. slot .. "Fan" .. i, slot, 10 * GOLD) end
	end
	return { outcomes = { 1, 2, 3, 4, 5, 6, 7, 8 }, places = 2, mode = "arbiter", bets = bets }
end

test("ArenaMath: the pools add up per outcome, and each backer counts once", function()
	local m = Market("arbiter", nil, {
		Bet("Corwen-Realm", "A", 5 * GOLD),
		Bet("Corwen-Realm", "A", 2 * GOLD),
		Bet("Delphine-Realm", "A", 50 * SILVER),
		Bet("Corwen-Realm", "B", 1 * GOLD),
	}, { "A", "B", "C" })
	local pools, total, bettors = M.Pools(m)
	eq(pools.A, 75000, "A")
	eq(pools.B, 10000, "B")
	eq(pools.C, 0, "an outcome nobody backed is 0, not missing")
	eq(total, 85000, "total")
	eq(bettors.A, 2, "Corwen's two bets on A are one backer")
	eq(bettors.B, 1)
	eq(bettors.C, 0)
	eq(M.Staked(m, "Corwen-Realm"), 8 * GOLD, "what he has on the market, every outcome")
	eq(M.Staked(m, "Delphine-Realm"), 50 * SILVER)
	eq(M.Staked(m, "Evander-Realm"), 0, "nothing yet")
	local r, why = M.Staked(m, "")
	eq(r, nil); eq(why, "who")
	r, why = M.Staked(Market("arbiter", nil, { Bet("Corwen-Realm", "A", 10.5) }), "Corwen-Realm")
	eq(r, nil); eq(why, "bet")
end)

test("ArenaMath: a malformed market is refused whole, by every function", function()
	local function Why(m) local ok, why, i = M.Check(m); eq(ok, nil); return why, i end
	eq(Why(nil), "market")
	eq(Why(Market("arbiter", nil, {}, { "A" })), "outcomes", "one outcome")
	eq(Why(Market("arbiter", nil, {}, { "A", "A" })), "outcomes", "the same outcome twice")
	eq(Why(Market("arbiter", nil, {}, { "A", "" })), "outcomes", "an empty key")
	eq(Why(Market("arbiter", nil, {}, { "A", M.VOID })), "outcomes", "V is the ledger's void, never an outcome")
	eq(Why(Market("arbiter", nil, {}, { 1, 0 / 0 })), "outcomes", "NaN for a key")
	eq(Why(Market("arbiter", nil, {}, { "A", "B", extra = "C" })), "outcomes", "a keyed outcome")
	local many = {}
	for i = 1, M.MAX_OUTCOMES + 1 do many[i] = i end
	eq(Why(Market("arbiter", nil, {}, many)), "outcomes", "more than MAX_OUTCOMES")
	many[#many] = nil
	eq(M.Check(Market("arbiter", nil, {}, many)), true, "MAX_OUTCOMES (a 64-slot bracket) itself is fine")
	eq(Why(Market("arbitre", nil, {})), "mode", "a misspelt mode never sends the arbiter's part elsewhere")
	eq(Why(Market(nil, nil, {})), "mode")
	eq(Why(Market("direct", "6%", {})), "fee")
	eq(Why(Market("direct", 0 / 0, {})), "fee")
	local m = Market("arbiter", 600, {})
	m.arbiterFee = "2%"
	eq(Why(m), "fee", "the arbiter's rate too")
	for _, places in ipairs({ 0, 2, 1.5, "1", -1 }) do
		m = Market("arbiter", nil, {})
		m.places = places
		eq(Why(m), "places", "places " .. tostring(places) .. " of 2 outcomes")
	end
	m = Market("arbiter", nil, {}, { 1, 2, 3, 4 })
	m.places = 3
	eq(M.Check(m), true, "3 places of 4")
	eq(Why(Market("direct", nil, "bets")), "bets")
	local bad = {
		Bet("Corwen-Realm", "C", GOLD),       -- an outcome the market doesn't have
		Bet("Corwen-Realm", "A", 10.5),       -- a fraction of a copper
		Bet("Corwen-Realm", "A", 0),
		Bet("Corwen-Realm", "A", -GOLD),
		Bet("Corwen-Realm", "A", 0 / 0),
		Bet("Corwen-Realm", "A", MAX + 1),    -- past the game's gold cap
		Bet("Corwen-Realm", "A", "100"),
		Bet("", "A", GOLD),
		Bet(nil, "A", GOLD),
	}
	for i, b in ipairs(bad) do
		local why, index = Why(Market("direct", nil, { Bet("Delphine-Realm", "B", GOLD), b }))
		eq(why, "bet", "bad bet " .. i)
		eq(index, 2, "names the bad bet " .. i)
	end
	-- A pool past MAX_POOL (2^43 copper) is refused: 4096 bets at the gold cap fit, 4097 don't.
	local bets = {}
	for i = 1, 4096 do bets[i] = Bet("Whale" .. i, i % 2 == 0 and "A" or "B", MAX) end
	eq(M.Check(Market("direct", nil, bets)), true, "4096 bets at the cap")
	bets[4097] = Bet("Whale4097", "A", MAX)
	eq(Why(Market("direct", nil, bets)), "pool")
	-- Every function refuses it the same way.
	local broken = Market("direct", nil, { Bet("Corwen-Realm", "A", 10.5) })
	for _, fn in ipairs({ "Pools", "MarketOdds", "Void" }) do
		local r, why = M[fn](broken)
		eq(r, nil, fn); eq(why, "bet", fn)
	end
	local r, why = M.SettleMarket(broken, "A")
	eq(r, nil); eq(why, "bet")
	r, why = M.Quote(broken, "A", GOLD)
	eq(r, nil); eq(why, "bet")
end)

test("ArenaMath: bets keyed by anything but 1..n, or with a hole, are refused, never read as fewer", function()
	-- Keyed by the slips' nonces: read with ipairs they were an empty market, "refunded" with
	-- nobody paid and the stakes left held.
	local keyed = Market("arbiter", 600, { n1 = Bet("Corwen-Realm", "A", 50 * SILVER), n2 = Bet("Delphine-Realm", "B", 50 * SILVER) })
	local ok, why = M.Check(keyed)
	eq(ok, nil); eq(why, "bets")
	local r
	r, why = M.SettleMarket(keyed, "A")
	eq(r, nil, "not an empty refund"); eq(why, "bets")
	-- Numbered and keyed together: the keyed stake was dropped from the pool.
	local mixed = Market("arbiter", 600, { Bet("Corwen-Realm", "A", GOLD), Bet("Delphine-Realm", "B", GOLD) })
	mixed.bets.n3 = Bet("Evander-Realm", "B", 5 * GOLD)
	ok, why = M.Check(mixed)
	eq(ok, nil); eq(why, "bets")
	r, why = M.Pools(mixed)
	eq(r, nil); eq(why, "bets")
	-- A hole: the bets after it were dropped.
	local holed = Market("arbiter", 600, {})
	holed.bets[1] = Bet("Corwen-Realm", "A", GOLD)
	holed.bets[3] = Bet("Delphine-Realm", "B", GOLD)
	ok, why = M.Check(holed)
	eq(ok, nil); eq(why, "bets")
end)

test("ArenaMath: the fee's rates: clamped numbers, the arbiter's part its own rate, and nonsense refused", function()
	eq(M.Fee(nil), 600, "the default is 6%")
	eq(M.Fee(600), 600)
	eq(M.Fee(0), 0, "the King may take no fee")
	eq(M.Fee(-50), 0)
	eq(M.Fee(2500), 1000, "a King's 25% is clamped to 10%")
	eq(M.Fee(612.9), 612, "whole basis points")
	for _, bad in ipairs({ "lots", "0", 0 / 0, true }) do
		local r, why = M.Fee(bad)
		eq(r, nil, "not a number: " .. tostring(bad)); eq(why, "fee")
	end
	local g, a = M.Split(600, nil, "arbiter")
	eq(g, 400); eq(a, 200)
	g, a = M.Split(nil, nil, "arbiter")
	eq(g, 400, "the defaults: 4 + 2"); eq(a, 200)
	g, a = M.Split(600, nil, "direct")
	eq(g, 600, "no arbiter: all the guild's"); eq(a, 0)
	g, a = M.Split(900, nil, "arbiter")
	eq(g, 700, "a King's 9%: the arbiter's rate stays 2%"); eq(a, 200)
	g, a = M.Split(900, 300, "arbiter")
	eq(g, 600); eq(a, 300)
	g, a = M.Split(100, nil, "arbiter")
	eq(g, 0, "the arbiter's part never passes the fee"); eq(a, 100)
	g, a = M.Split(5000, 500, "arbiter")
	eq(g, 500, "the fee clamped to 10% first"); eq(a, 500)
	g, a = M.Split(600, 200, "arbitre")
	eq(g, nil, "a misspelt mode is refused, not read as direct"); eq(a, "mode")
	g, a = M.Split(600, 200, nil)
	eq(g, nil); eq(a, "mode")
	g, a = M.Split("0", nil, "direct")
	eq(g, nil); eq(a, "fee")
	g, a = M.Split(600, "2", "arbiter")
	eq(g, nil); eq(a, "fee")
end)

test("ArenaMath: the fee is its rate of the money won to the copper, and its split's odd copper is the guild's", function()
	-- 10% of 1000c, 3.33% of it the arbiter's: 100c in all (67c + 33c), never 66c + 33c.
	local guild, arbiter, net = M.Fees(1000, 1000, 333, "arbiter")
	eq(guild, 67); eq(arbiter, 33); eq(net, 900)
	local r = M.SettleMarket({ outcomes = { "A", "B" }, mode = "arbiter", fee = 1000, arbiterFee = 333,
		bets = { Bet("Ansel-Realm", "A", 1000), Bet("Caius-Realm", "B", 1000) } }, "A")
	eq(r.payouts["Ansel-Realm"], 1900, "the winner gets 1000c less 10% of the 1000c won")
	eq(r.cut, 100); eq(r.guildFee, 67); eq(r.arbiter, 33); eq(r.guild, 67)
	eq(PaidOut(r), 2000)
	-- The Farkle section's example (the design): S = 10g won, with an arbiter; and direct.
	guild, arbiter, net = M.Fees(10 * GOLD, nil, nil, "arbiter")
	eq(guild, 40 * SILVER); eq(arbiter, 20 * SILVER); eq(net, 9 * GOLD + 40 * SILVER)
	guild, arbiter, net = M.Fees(10 * GOLD, nil, nil, "direct")
	eq(guild, 60 * SILVER); eq(arbiter, 0); eq(net, 9 * GOLD + 40 * SILVER)
	eq((M.Fees(0, nil, nil, "direct")), 0, "nothing won, no fee")
	local why
	for _, bad in ipairs({ -1, 1.5, "100", M.MAX_POOL + 1 }) do
		r, why = M.Fees(bad, 600, nil, "direct")
		eq(r, nil, tostring(bad)); eq(why, "copper")
	end
	r, why = M.Fees(1000, "6", nil, "direct")
	eq(r, nil); eq(why, "fee")
	r, why = M.Fees(1000, 600, nil, "guild")
	eq(r, nil); eq(why, "mode")
end)

test("ArenaMath: a market pays each winner his stake and his share of the winnings after the fee; the odd coppers go to the guild", function()
	-- A wins. Winners 100c and 200c, 1000c lost on B. 6% of the 1000c lost: 40c guild, 20c
	-- arbiter; 940c shared 1:2 is 313.33c and 626.67c, rounded down, and the 1c left is the guild's.
	local m = Market("arbiter", 600, {
		Bet("Ansel-Realm", "A", 100), Bet("Berenike-Realm", "A", 200), Bet("Caius-Realm", "B", 1000),
	})
	local r = M.SettleMarket(m, "A")
	eq(r.refund, false)
	eq(r.outcome, "A"); eq(#r.winners, 1); eq(r.winners[1], "A")
	eq(r.pool, 1300); eq(r.winPool, 300); eq(r.losePool, 1000); eq(r.share, 940)
	eq(r.payouts["Ansel-Realm"], 413)
	eq(r.payouts["Berenike-Realm"], 826)
	eq(r.payouts["Caius-Realm"], 0, "the loser is listed, with nothing")
	eq(r.bets[1], 413); eq(r.bets[2], 826); eq(r.bets[3], 0, "each ticket, in the market's order")
	eq(r.cut, 60); eq(r.guildFee, 40); eq(r.arbiter, 20); eq(r.remainder, 1); eq(r.guild, 41)
	eq(r.stakes["Caius-Realm"], 1000)
	eq(PaidOut(r), r.pool, "everything that came in goes out")
	-- Direct: the whole 6% to the guild; the winners get the same.
	m.mode = "direct"
	r = M.SettleMarket(m, "A")
	eq(r.payouts["Ansel-Realm"], 413); eq(r.payouts["Berenike-Realm"], 826)
	eq(r.guildFee, 60); eq(r.arbiter, 0); eq(r.guild, 61)
	eq(PaidOut(r), 1300)
	-- B wins: one winner takes the 300c lost, less 6% (18c).
	r = M.SettleMarket(m, "B")
	eq(r.payouts["Caius-Realm"], 1282); eq(r.payouts["Ansel-Realm"], 0)
	eq(r.guild, 18); eq(r.remainder, 0)
	-- One winning key may also be given as a list of one.
	eq(M.SettleMarket(m, { "B" }).payouts["Caius-Realm"], 1282)
end)

test("ArenaMath: each bet is paid on its own, so a bettor's payout is the same however he split it", function()
	-- The design's example 2, the three bets on A all one player's: 1g 1s lost,
	-- 606c cut (202c the arbiter's), 9494c shared: each 1g bet gets 13,164c, and the 2c the
	-- three roundings leave are the guild's (406c). Rounded once over his 3g he'd get 39,494c,
	-- which his own client, working ticket by ticket from the public pools, can't show him.
	local m = Market("arbiter", 600, {
		Bet("Halvard-Realm", "A", GOLD), Bet("Halvard-Realm", "A", GOLD), Bet("Halvard-Realm", "A", GOLD),
		Bet("Isolde-Realm", "B", GOLD + SILVER),
	})
	local r = M.SettleMarket(m, "A")
	eq(r.bets[1], 13164); eq(r.bets[2], 13164); eq(r.bets[3], 13164); eq(r.bets[4], 0)
	eq(r.payouts["Halvard-Realm"], 3 * 13164, "the sum of his tickets")
	eq(r.cut, 606); eq(r.arbiter, 202); eq(r.remainder, 2); eq(r.guild, 406)
	eq(PaidOut(r), 40100)
	-- The review's case: P bets 1600c twice, Q 1000c, all on A, R 1300c on B.
	m = Market("arbiter", 600, {
		Bet("Philon-Realm", "A", 1600), Bet("Philon-Realm", "A", 1600), Bet("Quintus-Realm", "A", 1000),
		Bet("Rhea-Realm", "B", 1300),
	})
	r = M.SettleMarket(m, "A")
	eq(r.bets[1], 2065); eq(r.bets[2], 2065)
	eq(r.payouts["Philon-Realm"], 4130, "per ticket, not 4131 from his 3200c at once")
	eq(PaidOut(r), 5500)
end)

test("ArenaMath: the proposal's example: 600g on A, 400g on B, and B wins", function()
	local r = M.SettleMarket(Example("arbiter", 600), "B")
	eq(r.pool, 1000 * GOLD)
	for i = 1, 20 do eq(r.payouts["Bramble" .. i .. "-Realm"], 48 * GOLD + 20 * SILVER, "20g on B pays 48g 20s") end
	for i = 1, 30 do eq(r.payouts["Aster" .. i .. "-Realm"], 0) end
	eq(r.guild, 24 * GOLD, "4% of the 600g lost"); eq(r.arbiter, 12 * GOLD, "2%"); eq(r.remainder, 0)
	eq(PaidOut(r), 1000 * GOLD)
	-- With no fee, the proposal's 2.50x: 20g on B pays 50g.
	r = M.SettleMarket(Example("arbiter", 0), "B")
	eq(r.payouts["Bramble1-Realm"], 50 * GOLD)
	eq(r.guild, 0); eq(r.arbiter, 0)
end)

test("ArenaMath: a market's odds are Odds on its pools, and a 1-gold ticket in it is paid at least them", function()
	local odds = M.MarketOdds(Example("arbiter", 600))
	eq(odds.B, 241, "B pays 2.41x")
	eq(odds.A, 162, "A pays 1.6266x, truncated")
	eq(M.OddsText(odds.A), "1.62x")
	odds = M.MarketOdds(Example("direct", 0))
	eq(M.OddsText(odds.B), "2.50x")
	-- An outcome nobody backed has no odds yet; one side alone pays 1.00x (it would be refunded).
	local m = Market("arbiter", 600, { Bet("Corwen-Realm", "A", 5 * GOLD) }, { "A", "B", "C" })
	odds = M.MarketOdds(m)
	eq(odds.A, 100); eq(odds.B, nil); eq(odds.C, nil)
	-- A player whose 1 gold is in the pool on B is paid B's odds, truncated to the hundredth.
	m = Example("arbiter", 600)
	m.bets[#m.bets + 1] = Bet("Evander-Realm", "B", GOLD)
	odds = M.MarketOdds(m)
	local paid = M.SettleMarket(m, "B").payouts["Evander-Realm"]
	eq(floor(paid / 100), odds.B)
	eq(odds.B, M.Odds(M.Pools(m), "B"), "the same as Odds on the pools")
end)

test("ArenaMath: a quote says what a new bet would return now, and settling pays it", function()
	local m = Example("arbiter", 600)
	local q = M.Quote(m, "B", 10 * GOLD)
	eq(q, 237560, "10g more on B: 564g of winnings over 410g on B")
	m.bets[#m.bets + 1] = Bet("Evander-Realm", "B", 10 * GOLD)
	eq(M.SettleMarket(m, "B").payouts["Evander-Realm"], q)
	-- On an outcome nobody backed yet, the quote is the whole losing pool (after the fee).
	eq(M.Quote(Market("arbiter", 600, { Bet("Corwen-Realm", "A", 600 * GOLD) }), "B", 10 * GOLD), 10 * GOLD + 564 * GOLD)
	-- Adding to the only side backed would just be refunded.
	eq(M.Quote(Market("arbiter", 600, { Bet("Corwen-Realm", "A", 600 * GOLD) }), "A", 10 * GOLD), 10 * GOLD)
	local r, why = M.Quote(m, "C", GOLD)
	eq(r, nil); eq(why, "outcome")
	r, why = M.Quote(m, "B", 0.5)
	eq(r, nil); eq(why, "copper")
	-- A bet that would take the pool past MAX_POOL is not quoted: 4096 bets at the gold cap
	-- leave room for 4096c more, not 4097c.
	local bets = {}
	for i = 1, 4096 do bets[i] = Bet("Whale" .. i, i % 2 == 0 and "A" or "B", MAX) end
	local whales = Market("direct", 600, bets)
	r, why = M.Quote(whales, "A", 4097)
	eq(r, nil); eq(why, "pool")
	assert(M.Quote(whales, "A", 4096) > 4096, "the last copper that fits is quoted")
end)

test("ArenaMath: a market's refunds: a void, nobody on a winner, one side only, no bets, every bet a winner; never a fee", function()
	local function Refunded(r, why, outcome)
		eq(r.refund, true, why)
		eq(r.why, why)
		eq(r.outcome, outcome, why)
		eq(r.guild, 0, why); eq(r.arbiter, 0, why); eq(r.guildFee, 0, why); eq(r.remainder, 0, why); eq(r.cut, 0, why)
		for who, c in pairs(r.stakes) do eq(r.payouts[who], c, why .. ": " .. who .. " gets his stake back") end
		eq(Count(r.payouts), Count(r.stakes), why)
		eq(PaidOut(r), r.pool, why)
	end
	local r = M.Void(Example("arbiter", 600))
	Refunded(r, "void", nil)
	eq(#r.winners, 0)
	eq(r.pool, 1000 * GOLD)
	eq(r.payouts["Aster7-Realm"], 20 * GOLD)
	eq(r.bets[50], 20 * GOLD, "every ticket back")
	-- A three-way market: bets on X and Y, and Z wins.
	local three = Market("arbiter", 600, {
		Bet("Corwen-Realm", "X", 3 * GOLD), Bet("Delphine-Realm", "Y", 4 * GOLD), Bet("Corwen-Realm", "Y", GOLD),
	}, { "X", "Y", "Z" })
	r = M.SettleMarket(three, "Z")
	Refunded(r, "nobody", "Z")
	eq(r.payouts["Corwen-Realm"], 4 * GOLD)
	eq(r.bets[1], 3 * GOLD); eq(r.bets[3], GOLD)
	-- Every bet on one outcome: refunded whichever wins.
	local one = Market("direct", 600, { Bet("Corwen-Realm", "X", 3 * GOLD), Bet("Delphine-Realm", "X", GOLD) }, { "X", "Y" })
	Refunded(M.SettleMarket(one, "X"), "onesided", "X")
	Refunded(M.SettleMarket(one, "Y"), "onesided", "Y")
	-- No bets at all (an empty list, or none).
	r = M.SettleMarket(Market("arbiter", 600, {}), "A")
	Refunded(r, "empty", "A")
	eq(r.pool, 0)
	Refunded(M.SettleMarket(Market("arbiter", 600, nil), "B"), "empty", "B")
	-- Two places, and the only two outcomes backed both reach the final: nobody lost.
	local final = { outcomes = { 1, 2, 3, 4 }, places = 2, mode = "arbiter",
		bets = { Bet("Corwen-Realm", 1, 3 * GOLD), Bet("Delphine-Realm", 2, GOLD) } }
	r = M.SettleMarket(final, { 2, 1 })
	Refunded(r, "allwon", nil)
	eq(r.winners[1], 2); eq(r.winners[2], 1)
	Refunded(M.SettleMarket(final, { 3, 4 }), "nobody", nil)
end)

test("ArenaMath: settling a market on outcomes it doesn't have, or the wrong number of them, is refused", function()
	local function Refused(m, winners, msg)
		local r, why = M.SettleMarket(m, winners)
		eq(r, nil, msg); eq(why, "outcome", msg)
	end
	Refused(Example("arbiter", 600), "C", "not an outcome")
	Refused(Example("arbiter", 600), nil, "no winner")
	Refused(Example("arbiter", 600), { "A", "B" }, "two winners of a one-place market")
	Refused(Example("arbiter", 600), {}, "an empty list")
	Refused(Final(), 1, "one winner of a two-place market")
	Refused(Final(), { 1, 1 }, "the same winner twice")
	Refused(Final(), { 1, 9 }, "a slot the bracket doesn't have")
	Refused(Final(), { 1, 5, 6 }, "three finalists")
	Refused(Final(), { 1, 5, extra = 6 }, "a keyed winner")
end)

test("ArenaMath: a player who backed both sides is paid from his stake on the winner", function()
	local m = Market("direct", 600, {
		Bet("Halvard-Realm", "A", 10 * GOLD), Bet("Halvard-Realm", "B", 5 * GOLD), Bet("Isolde-Realm", "B", 10 * GOLD),
	})
	local r = M.SettleMarket(m, "A")
	-- 15g lost on B, 6% of it (90s) to the guild: his 10g back and 14g 10s.
	eq(r.payouts["Halvard-Realm"], 24 * GOLD + 10 * SILVER)
	eq(r.stakes["Halvard-Realm"], 15 * GOLD, "his stake counts both bets")
	eq(r.bets[2], 0, "his bet on B lost")
	eq(r.payouts["Isolde-Realm"], 0)
	eq(r.guild, 90 * SILVER)
	eq(PaidOut(r), 25 * GOLD)
end)

test("ArenaMath: a tournament outright, one outcome per fighter", function()
	local f = { "Player-4701-00A1", "Player-4701-00B2", "Player-4701-00C3", "Player-4701-00D4" }
	local m = Market("arbiter", 600, {
		Bet("Corwen-Realm", f[1], 10 * GOLD), Bet("Delphine-Realm", f[2], 30 * GOLD),
		Bet("Evander-Realm", f[2], 20 * GOLD), Bet("Fenwick-Realm", f[3], 40 * GOLD),
	}, f)
	local r = M.SettleMarket(m, f[2])
	-- 50g lost on the others: 2g to the guild, 1g to the arbiter, 47g shared 3:2.
	eq(r.payouts["Delphine-Realm"], 30 * GOLD + 28 * GOLD + 20 * SILVER)
	eq(r.payouts["Evander-Realm"], 20 * GOLD + 18 * GOLD + 80 * SILVER)
	eq(r.payouts["Corwen-Realm"], 0); eq(r.payouts["Fenwick-Realm"], 0)
	eq(r.guild, 2 * GOLD); eq(r.arbiter, GOLD)
	eq(PaidOut(r), 100 * GOLD)
	eq(M.SettleMarket(m, f[4]).why, "nobody", "the fighter nobody backed wins: all refunded")
	eq(M.MarketOdds(m)[f[4]], nil)
end)

test("ArenaMath: reaches the final: two winners share the winnings evenly, then pro rata (the design's example 3)", function()
	-- The finalists are slots 1 and 5: 350g on them, 650g lost; 39g cut (13g the arbiter's),
	-- 611g left, 305g 50s for each finalist's backers.
	local r = M.SettleMarket(Final(), { 1, 5 })
	eq(r.refund, false)
	eq(r.outcome, nil, "no single outcome with two places")
	eq(r.winners[1], 1); eq(r.winners[2], 5)
	eq(r.winPool, 350 * GOLD); eq(r.losePool, 650 * GOLD); eq(r.cut, 39 * GOLD)
	eq(r.share, 305 * GOLD + 50 * SILVER)
	eq(r.payouts["Slot5Fan1"], 71 * GOLD + 10 * SILVER, "10g on slot 5")
	eq(r.payouts["Slot1Fan1"], 20 * GOLD + 18 * SILVER + 33, "10g on slot 1")
	eq(r.payouts["Slot2Fan1"], 0)
	eq(r.arbiter, 13 * GOLD)
	eq(r.remainder, 10, "a third of a copper on each of slot 1's 30 bets")
	eq(r.guild, 26 * GOLD + 10, "26g 10c")
	eq(PaidOut(r), 1000 * GOLD)
	-- A finalist nobody backed (a ninth slot) passes his part on: 700g lost, 42g cut, and slot
	-- 1's backers share all 658g left, 21g 93s 33c on each 10g.
	local m = Final()
	m.outcomes[9] = 9
	r = M.SettleMarket(m, { 1, 9 })
	eq(r.losePool, 700 * GOLD)
	eq(r.share, 658 * GOLD, "one winning outcome with bets takes it all")
	eq(r.payouts["Slot1Fan1"], 31 * GOLD + 93 * SILVER + 33)
	eq(PaidOut(r), 1000 * GOLD)
end)

test("ArenaMath: with several places, the odds and a quote are the least a bet can be paid", function()
	-- A 1-gold ticket on every slot: whoever the other finalist is, the ticket gets at least the
	-- odds shown, and they are its payout truncated when the other finalist is the most backed.
	local m = Final()
	for slot = 1, 8 do m.bets[#m.bets + 1] = Bet("Tester" .. slot, slot, GOLD) end
	local odds = M.MarketOdds(m)
	for slot = 1, 8 do
		local least
		for other = 1, 8 do
			if other ~= slot then
				local pay = M.SettleMarket(m, { slot, other }).payouts["Tester" .. slot]
				assert(pay >= odds[slot] * 100, "slot " .. slot .. " with " .. other .. ": paid under the odds")
				least = least and (pay < least and pay or least) or pay
			end
		end
		eq(odds[slot], floor(least / 100), "slot " .. slot .. ": the odds are the worst case")
	end
	eq(M.OddsText(odds[1]), "1.79x", "slot 1 with slot 2: 506g lost, 475g 64s after the fee, 237g 82s over 301g")
	-- A quote is the same least, and the bet once placed is paid at least that.
	local q = M.Quote(m, 5, 10 * GOLD)
	m.bets[#m.bets + 1] = Bet("Latecomer", 5, 10 * GOLD)
	local least
	for other = 1, 8 do
		if other ~= 5 then
			local pay = M.SettleMarket(m, { 5, other }).payouts["Latecomer"]
			assert(pay >= q, "paid under the quote with " .. other)
			least = least and (pay < least and pay or least) or pay
		end
	end
	eq(least, q)
end)

test("ArenaMath: settling leaves the market as it was", function()
	local m = Example("arbiter", 600)
	M.SettleMarket(m, "B"); M.SettleMarket(m, "A"); M.Void(m); M.MarketOdds(m); M.Quote(m, "A", GOLD); M.Pools(m); M.Staked(m, "Aster1-Realm")
	eq(#m.bets, 50)
	for i = 1, 30 do eq(m.bets[i].copper, 20 * GOLD); eq(m.bets[i].outcome, "A") end
	eq(m.fee, 600); eq(m.mode, "arbiter"); eq(#m.outcomes, 2); eq(m.arbiterFee, nil); eq(m.places, nil)
	local f = Final()
	local winners = { 1, 5 }
	M.SettleMarket(f, winners); M.MarketOdds(f)
	eq(#winners, 2); eq(winners[1], 1); eq(#f.bets, 100); eq(f.places, 2)
end)

test("ArenaMath: pools whose products pass 2^53 still settle to the exact copper", function()
	-- Two winners near the gold cap; the losers' 8,591,611,316c make each share's product ~2^63,
	-- where a float division gives the first winner a copper too many (6,184,541,824) and the
	-- payouts would pass the pool. The exact values (Python integers): a cut of 515,496,678c
	-- (171,832,226c the arbiter's), and 1c of rounding left over.
	local m = Market("arbiter", 600, {
		Bet("Galatea-Realm", "A", 2146510302), Bet("Hector-Realm", "A", 2146537728),
		Bet("Iason-Realm", "B", MAX), Bet("Jocasta-Realm", "B", MAX), Bet("Kallias-Realm", "B", MAX),
		Bet("Leander-Realm", "B", MAX), Bet("Myrrine-Realm", "B", 1676728),
	})
	local r = M.SettleMarket(m, "A")
	eq(r.losePool, 8591611316)
	eq(r.payouts["Galatea-Realm"], 6184541823)
	eq(r.payouts["Hector-Realm"], 6184620844)
	eq(r.cut, 515496678); eq(r.guildFee, 343664452); eq(r.arbiter, 171832226); eq(r.remainder, 1); eq(r.guild, 343664453)
	eq(PaidOut(r), 12884659346)
	-- The contract's Settle on the same bets: the same copper.
	local bets = {}
	for i, b in ipairs(m.bets) do bets[i] = B(b.outcome, b.copper) end
	local c = M.Settle(bets, "A")
	eq(c.payouts[1], 6184541823); eq(c.payouts[2], 6184620844); eq(c.guildFee, 343664453); eq(c.arbFee, 171832226)
	-- Three winners and four losers, all at the gold cap.
	bets = {}
	for i = 1, 3 do bets[#bets + 1] = Bet("Nikias" .. i, "A", MAX) end
	for i = 1, 4 do bets[#bets + 1] = Bet("Orestes" .. i, "B", MAX) end
	r = M.SettleMarket(Market("arbiter", 600, bets), "A")
	for i = 1, 3 do eq(r.payouts["Nikias" .. i], 4838996484) end
	eq(r.cut, 515396075); eq(r.guildFee, 343597384); eq(r.arbiter, 171798691); eq(r.remainder, 2); eq(r.guild, 343597386)
	eq(PaidOut(r), 7 * MAX)
end)

test("ArenaMath: 400 random markets: in equals out, each ticket gets its exact part, and the refunds are right", function()
	local Rand = Randoms(20260930)
	local names = {}
	for i = 1, 12 do names[i] = "Tester" .. i .. "-Realm" end
	local checked = 0
	for round = 1, 400 do
		local tag = "round " .. round
		local n = Rand(6) + 1
		local outcomes = {}
		for i = 1, n do outcomes[i] = "o" .. i end
		local places = (n >= 3 and Rand(3) == 1) and Rand(n - 1) or 1
		-- Most rounds stay small, where a float holds every product exactly and can check each
		-- ticket; one in four goes up to the gold cap, for the sums.
		local big = Rand(4) == 1
		local bets = {}
		for i = 1, Rand(30) - 1 do
			bets[i] = Bet(names[Rand(#names)], outcomes[Rand(n)], big and Rand(MAX) or Rand(100 * GOLD))
		end
		local fee, arbiterFee = Rand(1500) - 1, Rand(1200) - 1
		local mode = Rand(2) == 1 and "arbiter" or "direct"
		local m = { outcomes = outcomes, places = places, mode = mode, fee = fee, arbiterFee = arbiterFee, bets = bets }
		local left, winners, won = {}, {}, {}
		for i = 1, n do left[i] = outcomes[i] end
		for i = 1, places do
			winners[i] = table.remove(left, Rand(#left))
			won[winners[i]] = true
		end
		local r = M.SettleMarket(m, winners)
		assert(r, tag .. " settled")
		eq(PaidOut(r), r.pool, tag)
		-- The pools, as the test sees them.
		local pools, total, sides, onWin, live = {}, 0, 0, 0, 0
		for _, b in ipairs(bets) do
			if not pools[b.outcome] then pools[b.outcome] = 0; sides = sides + 1 end
			pools[b.outcome] = pools[b.outcome] + b.copper
			total = total + b.copper
			if won[b.outcome] then onWin = onWin + b.copper end
		end
		for k in pairs(won) do if pools[k] then live = live + 1 end end
		eq(r.pool, total, tag)
		local expect = #bets == 0 and "empty" or sides < 2 and "onesided" or live == 0 and "nobody"
			or onWin == total and "allwon" or nil
		eq(r.why, expect, tag .. ": the refund's reason")
		eq(r.refund, expect ~= nil, tag)
		-- A bettor's payout is the sum of his tickets'.
		local sums = {}
		for i, b in ipairs(bets) do sums[b.who] = (sums[b.who] or 0) + r.bets[i] end
		for who, c in pairs(r.payouts) do eq(c, sums[who], tag .. ": " .. who .. "'s tickets") end
		if r.refund then
			eq(r.guild + r.arbiter, 0, tag .. ": a refund takes no fee")
			for i, b in ipairs(bets) do eq(r.bets[i], b.copper, tag) end
		else
			local f = fee > M.FEE_CAP and M.FEE_CAP or fee
			local a = mode == "arbiter" and (arbiterFee < f and arbiterFee or f) or 0
			local lose = total - onWin
			eq(r.losePool, lose, tag)
			-- The cut is its rate of the money won, rounded down once; the arbiter's the same.
			assert(r.cut <= lose * f / M.BPS and lose * f / M.BPS < r.cut + 1, tag .. ": the cut")
			assert(r.arbiter <= lose * a / M.BPS and lose * a / M.BPS < r.arbiter + 1, tag .. ": the arbiter's part")
			eq(r.guildFee + r.arbiter, r.cut, tag)
			-- Each winning outcome with bets gets an even part of what is left.
			local net = lose - r.cut
			assert(r.share * live <= net and net < (r.share + 1) * live, tag .. ": the even split between the winners")
			assert(r.remainder < live + #bets, tag .. ": less than a copper a winning bet and outcome left over")
			for i, b in ipairs(bets) do
				if won[b.outcome] then
					assert(r.bets[i] >= b.copper, tag .. ": a winning ticket got back less than its stake")
					if not big then
						-- Its stake, and its part of its outcome's share, less under a copper.
						local exact = b.copper + r.share * b.copper / pools[b.outcome]
						assert(r.bets[i] <= exact and exact < r.bets[i] + 1, tag .. ": ticket " .. i .. " paid " .. r.bets[i] .. ", not " .. exact)
						checked = checked + 1
					end
				else
					eq(r.bets[i], 0, tag .. ": a losing ticket is paid nothing")
				end
			end
		end
	end
	assert(checked > 500, "enough winning tickets checked one by one (" .. checked .. ")")
end)

test("ArenaMath: splitting a bet into slips never gets a player past his cap on a market", function()
	-- A newcomer's cap is 5g. Ten slips of 5g each used to pass one by one, and put 50g on
	-- the market; checked against what he has on it, only the first one does.
	local cap = M.BetCap({}, "bet")
	local m = Market("arbiter", 600, { Bet("Ansel-Realm", "B", GOLD) })
	local accepted = 0
	for _ = 1, 10 do
		if M.BetOk(cap, cap, M.Staked(m, "Newcomer-Realm")) then
			m.bets[#m.bets + 1] = Bet("Newcomer-Realm", "A", cap)
			accepted = accepted + 1
		end
	end
	eq(accepted, 1)
	eq(M.SettleMarket(m, "A").stakes["Newcomer-Realm"], cap)
	-- Smaller slips add up to the cap and no further.
	m = Market("arbiter", 600, { Bet("Ansel-Realm", "B", GOLD) })
	for _ = 1, 10 do
		if M.BetOk(GOLD, cap, M.Staked(m, "Newcomer-Realm")) then m.bets[#m.bets + 1] = Bet("Newcomer-Realm", "A", GOLD) end
	end
	eq(M.Staked(m, "Newcomer-Realm"), cap)
end)
