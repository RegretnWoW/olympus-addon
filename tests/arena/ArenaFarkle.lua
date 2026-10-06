-- Farkle's rules (Olympus/ArenaFarkle.lua, 1.2): dice from the server's roll, scoring, the turn,
-- the game, its event codes, chain and transcript, and the House. Run by tests/run.lua, which
-- passes { test, eq, ADDON_DIR, ROOT }.
local H = ...
local test, eq = H.test, H.eq

-- Sign.lua loads before ArenaFarkle.lua in the TOC: the chain and the hash use its SHA-256.
local ns = {}
assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
local F = ns.FarkleRules

-- Invented players.
local A, B = "Thessaly Ironbrand-Realm", "Corvin Ashgrove-Realm"

local function list(t) return table.concat(t, " ") end
local function err(_, why) return why end
local function codes(g) return table.concat(g.events, " ") end
-- The server roll that throws these dice (Encode is checked against Decode below).
local function R(...) return (F.Encode({ ... })) end
-- A roll event of these dice, as a witness reports the server's line (k from the range).
local function Roll(p, ...) return { t = "R", p = p, k = select("#", ...), value = R(...) } end
-- A started game (the seat that starts named, as practice does), to 2,000 unless said.
local function Game(fields)
	fields = fields or {}
	if fields.target == nil then fields.target = 2000 end
	if fields.first == nil then fields.first = 1 end
	return assert(F.New(fields))
end
-- A whole turn with the page's moves: roll these six dice, set aside the best of them, bank.
local function Play(g, who, ...)
	assert(F.Roll(g, who, R(...)))
	local _, pick = F.Best(g.turn.dice)
	assert(F.Keep(g, who, pick))
	return assert(F.Bank(g, who))
end
-- The game tests' rolls with KCD2's points (2026-09-30): 5 2 3 3 6 6 scores 50 (its 5) and
-- 1 2 3 4 6 6 scores 100 (its 1); 1 1 1 1 5 5 scores 2,100 (four 1s and two 5s), reaching the
-- 2,000 target in one turn. Under the old table they were 5 2 3 4 6 6, which now holds the run
-- 2-3-4-5-6 (750), and 1 1 1 5 5 5, two triplets at 2,500, now two threes of a kind at 1,500.
-- A turn that farkles at once (nothing in 2 2 3 3 4 6 scores).
local function Bust(g, who)
	local dice, farkle = F.Roll(g, who, R(2, 2, 3, 3, 4, 6))
	assert(dice and farkle, "a Farkle expected")
end
-- The first 8 hex digits of a SHA-256: how the design defines the transcript hash (and this
-- file's chain), so an auditor with any SHA-256 can check a transcript.
local function Hex8(text) return (ns.Sign.SHA256(text):sub(1, 4):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
-- A seeded stand-in for the server's /roll.
local function Server(seed)
	return function(top)
		seed = seed * 16807 % 2147483647
		return seed % top + 1
	end
end
-- Calls fn with every set of 1 to 6 dice (923 of them), faces in ascending order.
local function Every(fn)
	local dice = {}
	local function Walk(from, n)
		if #dice == n then return fn(dice) end
		for f = from, 6 do
			dice[#dice + 1] = f
			Walk(f, n)
			dice[#dice] = nil
		end
	end
	for n = 1, 6 do Walk(1, n) end
end

---------------------------------------------------------------------------
-- Dice
---------------------------------------------------------------------------

test("1.2 Farkle: one server roll decodes to dice, lowest base-6 digit first", function()
	eq(list(F.Decode(1, 6)), "1 1 1 1 1 1")
	eq(list(F.Decode(46656, 6)), "6 6 6 6 6 6")
	eq(list(F.Decode(31337, 6)), "5 3 1 2 1 5")
	eq(list(F.Decode(2000, 5)), "2 4 2 4 2")
	eq(list(F.Decode(7, 2)), "1 2")
	for v = 1, 6 do eq(list(F.Decode(v, 1)), tostring(v), "one die reads as the roll") end
	eq(F.RANGES[6], 46656)
	eq(F.RANGES[1], 6)
end)

test("1.2 Farkle: Decode refuses what is not a roll of n dice", function()
	local bad = {
		{ 0, 6 }, { 46657, 6 }, { 37, 2 }, { 7, 1 }, { -1, 1 }, { 1.5, 6 }, { "5", 1 }, { nil, 1 },
		{ 0 / 0, 6 }, { math.huge, 6 }, { 1, 0 }, { 1, 7 }, { 1, 2.5 }, { 1, nil }, { 1, "6" },
	}
	for i, c in ipairs(bad) do eq(F.Decode(c[1], c[2]), nil, "case " .. i) end
end)

test("1.2 Farkle: every roll of 1..6^n is a different set of n fair dice, and Encode inverts it", function()
	for n = 1, 6 do
		local top = F.RANGES[n]
		local seen, per = {}, {}
		for i = 1, n do per[i] = { 0, 0, 0, 0, 0, 0 } end
		for v = 1, top do
			local d = F.Decode(v, n)
			eq(#d, n)
			local key = list(d)
			assert(not seen[key], "two rolls give " .. key)
			seen[key] = true
			local back, count = F.Encode(d)
			eq(back, v, "Encode of " .. key)
			eq(count, n)
			for i, f in ipairs(d) do per[i][f] = per[i][f] + 1 end
		end
		for i = 1, n do
			for f = 1, 6 do eq(per[i][f], top / 6, ("n %d, die %d, face %d"):format(n, i, f)) end
		end
	end
end)

test("1.2 Farkle: Encode refuses what is not 1 to 6 faces", function()
	eq(F.Encode({ 6, 6 }), 36)
	eq(F.Encode({}), nil)
	eq(F.Encode({ 7 }), nil)
	eq(F.Encode({ 0 }), nil)
	eq(F.Encode({ 2.5 }), nil)
	eq(F.Encode({ 1, 2, 3, 4, 5, 6, 1 }), nil, "seven dice")
	eq(F.Encode({ 1, nil, 3 }), nil, "a hole")
	eq(F.Encode({ 1, x = 2 }), nil, "an extra key")
	eq(F.Encode("11"), nil)
	eq(F.Encode(nil), nil)
end)

test("1.2 Farkle: RangeK reads the dice count from a /roll range, 1-6^k only", function()
	eq(F.RangeK(1, 6), 1)
	eq(F.RangeK(1, 36), 2)
	eq(F.RangeK(1, 216), 3)
	eq(F.RangeK(1, 1296), 4)
	eq(F.RangeK(1, 7776), 5)
	eq(F.RangeK(1, 46656), 6)
	eq(F.RangeK(1, 100), nil, "the opening roll is no dice")
	eq(F.RangeK(2, 36), nil)
	eq(F.RangeK(0, 6), nil)
	eq(F.RangeK(1, 37), nil)
	eq(F.RangeK(1, nil), nil)
	eq(F.RangeK("1", "6"), nil)
end)

test("1.2 Farkle: Mask writes a set of dice positions the one way the codes use", function()
	local text, pos = F.Mask({ 5, 1, 3 })
	eq(text, "135"); eq(list(pos), "1 3 5")
	text, pos = F.Mask("51")
	eq(text, "15"); eq(list(pos), "1 5")
	eq((F.Mask("123456")), "123456")
	eq((F.Mask({ 6 })), "6")
	local bad = {
		{}, "", { 1, 1 }, "11", { 7 }, "7", "0", { 0 }, { 1.5 }, { 1, x = 2 }, "1a", "1 2", 12,
		"1234567", { 1, 2, 3, 4, 5, 6, 1 }, { "1" },
	}
	for i, m in ipairs(bad) do eq(F.Mask(m), nil, "case " .. i) end
	eq(F.Mask(nil), nil)
end)

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

-- Bone Throw scores like Kingdom Come: Deliverance II's dice (the owner, 2026-09-30), replacing
-- the common rule set these tests first asserted: four, five and six of a kind now double the
-- face's three of a kind per die past the third (they were a flat 1,000, 2,000 and 3,000 for any
-- face), the runs 1-2-3-4-5 (500) and 2-3-4-5-6 (750) are new and count next to other dice, and
-- three pairs, four and a pair and the two-triplets bonus are gone. Every value below that differs
-- from the old table differs for one of these reasons; the rest (singles, three of a kind, the
-- whole run) did not change.

-- Runs fn with rows of F.SCORES changed ({ { row, key, value }, ... }: row is F.SCORES itself or
-- one of its tables), and puts back every one it made even when fn or a later change fails.
local function With(changes, fn)
	local saved, made = {}, 0
	local ok, why = pcall(function()
		for i, c in ipairs(changes) do
			saved[i] = c[1][c[2]]
			c[1][c[2]] = c[3]
			made = i
		end
		fn()
	end)
	for i = made, 1, -1 do
		local c = changes[i]
		c[1][c[2]] = saved[i]
	end
	if not ok then error(why, 0) end
end

test("1.2 Farkle: every combination scores its points (KCD2's table)", function()
	local rows = {
		{ { 1 }, 100 }, { { 5 }, 50 }, { { 1, 5 }, 150 }, { { 5, 1, 1 }, 250 },
		{ { 1, 1, 1 }, 1000 }, { { 2, 2, 2 }, 200 }, { { 3, 3, 3 }, 300 }, { { 4, 4, 4 }, 400 },
		{ { 5, 5, 5 }, 500 }, { { 6, 6, 6 }, 600 },
		-- the runs (1-2-3-4-5 and 2-3-4-5-6 are new; the whole run is unchanged), dice in any order
		{ { 1, 2, 3, 4, 5 }, 500 }, { { 5, 4, 3, 2, 1 }, 500 }, { { 2, 3, 4, 5, 6 }, 750 },
		{ { 6, 2, 5, 3, 4 }, 750 }, { { 3, 6, 1, 5, 2, 4 }, 1500 },
	}
	for _, r in ipairs(rows) do eq(F.Score(r[1]), r[2], list(r[1])) end
	-- four, five and six of a kind for every face: the three of a kind x 2, x 4 and x 8 (KCD2;
	-- the old table gave any face a flat 1,000, 2,000 and 3,000)
	local kinds = {
		[1] = { 2000, 4000, 8000 }, [2] = { 400, 800, 1600 }, [3] = { 600, 1200, 2400 },
		[4] = { 800, 1600, 3200 }, [5] = { 1000, 2000, 4000 }, [6] = { 1200, 2400, 4800 },
	}
	for f, want in pairs(kinds) do
		for i, points in ipairs(want) do
			local dice = {}
			for j = 1, i + 3 do dice[j] = f end
			eq(F.Score(dice), points, (i + 3) .. " x " .. f)
		end
	end
	-- the owner's question: four 3s 600, five 1,200, six 2,400
	eq(F.Score({ 3, 3, 3, 3 }), 600)
	eq(F.Score({ 3, 3, 3, 3, 3 }), 1200)
	eq(F.Score({ 3, 3, 3, 3, 3, 3 }), 2400)
end)

test("1.2 Farkle: a selection scores the best way it splits, every die used once, the parts added up", function()
	local rows = {
		-- KCD2's worked examples (the design's rules); each differs from the old table
		-- or is new with the runs of five
		{ { 1, 2, 3, 4, 5, 5 }, 550, "the run 1-5 and a 5" },
		{ { 1, 1, 2, 3, 4, 5 }, 600, "the run 1-5 and a 1" },
		{ { 2, 3, 4, 5, 6, 1 }, 1500, "the whole run beats 2-6 and a 1 (850)" },
		{ { 1, 2, 3, 4, 5, 6 }, 1500 },
		{ { 3, 3, 3, 3 }, 600, "one combination, not three 3s and a dead 3" },
		{ { 3, 3, 3, 3, 3 }, 1200 },
		{ { 3, 3, 3, 3, 3, 3 }, 2400, "not two threes of a kind (600)" },
		{ { 1, 1, 1, 1 }, 2000, "not three 1s and a 1 (1,100, the old table's answer)" },
		{ { 1, 1, 1, 1, 1, 1 }, 8000, "the best throw" },
		{ { 5, 5, 5, 5, 1 }, 1100, "four 5s and a 1" },
		{ { 2, 3, 4, 5, 6, 5 }, 800, "the run 2-6 and a 5" },
		{ { 1, 1, 1, 5, 5, 5 }, 1500, "two threes of a kind add up: no two-triplets bonus (was 2,500)" },
		{ { 2, 2, 2, 3, 3, 3 }, 500 },
		{ { 4, 4, 4, 4, 1, 1 }, 1000, "four 4s and two 1s: no four-and-a-pair bonus (was 1,500)" },
		{ { 1, 1, 5, 5 }, 300 },
		-- more runs with extra 1s and 5s
		{ { 5, 1, 2, 3, 4, 1 }, 600 }, { { 6, 5, 4, 3, 2, 5 }, 800 }, { { 1, 5, 4, 3, 2 }, 500 },
		-- the old table's rows that still hold
		{ { 1, 1, 1, 5 }, 1050 },
		{ { 5, 5, 5, 5 }, 1000, "four of a kind (now 500 x 2), not three 5s and a 5 (550)" },
		{ { 5, 5, 5, 1, 5 }, 1100 },
		{ { 1, 5, 5, 5, 5, 5 }, 2100, "five 5s and a 1" },
		-- the old table's rows that changed with KCD2
		{ { 1, 1, 1, 1, 1 }, 4000, "five 1s (was 2,000)" },
		{ { 1, 1, 1, 1, 5, 5 }, 2100, "four 1s and two 5s (was 1,500 as four and a pair)" },
		{ { 1, 1, 2, 2, 2, 2 }, 600, "four 2s and two 1s (was 1,500 as four and a pair)" },
		{ { 1, 1, 1, 1, 1, 5 }, 4050, "five 1s and a 5 (was 2,050)" },
	}
	for _, r in ipairs(rows) do eq(F.Score(r[1]), r[2], r[3] or list(r[1])) end
end)

test("1.2 Farkle: a selection with a die that doesn't score, or that isn't dice, scores nil", function()
	local bad = {
		{ 1, 2 }, { 2 }, { 2, 2 }, { 3, 3, 3, 4 }, { 2, 2, 3, 3 }, { 2, 2, 3, 3, 4 },
		{ 2, 2, 3, 3, 4, 6 }, {}, { 0 }, { 7 }, { 1.5 }, { 1, 1, 1, 1, 1, 1, 1 }, { 1, 5, x = 1 },
		-- KCD2: these scored under the old table (three pairs, four and a pair) or are no run
		{ 2, 2, 3, 3, 4, 4 }, { 1, 1, 5, 5, 6, 6 }, { 2, 2, 2, 2, 3, 3 }, { 2, 3, 4, 5, 6, 6 },
		{ 1, 2, 3, 4, 5, 2 }, { 1, 2, 3, 4 }, { 3, 4, 5, 6 }, { 1, 3, 4, 5, 6 }, { 2, 3, 4, 6 },
	}
	for i, d in ipairs(bad) do eq(F.Score(d), nil, "case " .. i .. ": " .. list(d)) end
	eq(F.Score("11"), nil)
	eq(F.Score(nil), nil)
end)

test("1.2 Farkle: the points are one table the rules read: every row can be changed or left out", function()
	local S = F.SCORES
	-- a row changed
	With({ { S.run, "12345", 600 }, { S.kind, 4, 3 }, { S.triple, 3, 350 } }, function()
		eq(F.Score({ 1, 2, 3, 4, 5 }), 600)
		eq(F.Score({ 1, 2, 3, 4, 5, 5 }), 650)
		eq(F.Score({ 3, 3, 3 }), 350)
		eq(F.Score({ 3, 3, 3, 3 }), 1050, "four of a kind follows the three of a kind and its multiplier")
		eq(F.Score({ 3, 3, 3, 3, 3 }), 1400)
	end)
	-- a lone 5
	With({ { S.single, 5, false } }, function()
		eq(F.Score({ 5 }), nil, "a lone 5 left out")
		eq(F.Score({ 1, 1, 1, 1, 5, 5 }), nil, "and two 5s no longer score")
		eq(F.Score({ 5, 5, 5 }), 500, "three 5s still count")
		eq(F.Score({ 1, 2, 3, 4, 5, 5 }), nil, "the run 1-5 counts, its extra 5 not")
		eq(F.Score({ 1, 2, 3, 4, 5 }), 500)
		eq(F.Farkle({ 5, 2, 3, 3, 6, 6 }), true)
		eq(F.CanScore({ 5, 2, 3, 3, 6, 6 }), false)
	end)
	-- a face's three of a kind: its four, five and six go with it
	With({ { S.triple, 3, false } }, function()
		eq(F.Score({ 3, 3, 3 }), nil)
		eq(F.Score({ 3, 3, 3, 3 }), nil)
		eq(F.Score({ 3, 3, 3, 3, 3, 3 }), nil)
		eq(F.Score({ 4, 4, 4, 4 }), 800, "another face keeps them")
	end)
	-- four of a kind
	With({ { S.kind, 4, false } }, function()
		eq(F.Score({ 3, 3, 3, 3 }), nil, "no four 3s: three 3s and a 3 that fits nothing")
		eq(F.Score({ 1, 1, 1, 1 }), 1100, "three 1s and a 1")
		eq(F.Score({ 3, 3, 3, 3, 3 }), 1200, "five still count")
		local points, pick = F.Best({ 3, 3, 3, 3, 2, 6 })
		eq(points, 300); eq(list(pick), "1 2 3")
	end)
	-- five of a kind
	With({ { S.kind, 5, false } }, function()
		eq(F.Score({ 3, 3, 3, 3, 3 }), nil)
		eq(F.Score({ 1, 1, 1, 1, 1 }), 2100, "four 1s and a 1")
		eq(F.Score({ 5, 5, 5, 5, 5 }), 1050, "four 5s and a 5")
		eq(F.Score({ 3, 3, 3, 3 }), 600)
	end)
	-- six of a kind
	With({ { S.kind, 6, false } }, function()
		eq(F.Score({ 3, 3, 3, 3, 3, 3 }), 600, "then two threes of a kind")
		eq(F.Score({ 1, 1, 1, 1, 1, 1 }), 4100, "five 1s and a 1")
		eq(F.Score({ 3, 3, 3, 3, 3 }), 1200)
	end)
	-- the run 1-2-3-4-5
	With({ { S.run, "12345", false } }, function()
		eq(F.Score({ 1, 2, 3, 4, 5 }), nil)
		eq(F.Score({ 1, 2, 3, 4, 5, 6 }), 1500, "the whole run stays")
		local points, pick = F.Best({ 1, 2, 3, 4, 5, 2 })
		eq(points, 150); eq(list(pick), "1 5")
	end)
	-- the run 2-3-4-5-6
	With({ { S.run, "23456", false } }, function()
		eq(F.Score({ 2, 3, 4, 5, 6 }), nil)
		eq(F.Score({ 2, 3, 4, 5, 6, 5 }), nil)
		local points, pick = F.Best({ 2, 3, 4, 5, 6, 6 })
		eq(points, 50); eq(list(pick), "4")
	end)
	-- the whole run
	With({ { S.run, "123456", false } }, function()
		eq(F.Score({ 1, 2, 3, 4, 5, 6 }), 850, "then 2-3-4-5-6 and a 1")
		eq(F.Score({ 1, 2, 3, 4, 5 }), 500)
	end)
	-- every run, and every four to six of a kind
	With({ { S, "run", false }, { S, "kind", false } }, function()
		eq(F.Score({ 1, 2, 3, 4, 5, 6 }), nil)
		eq(F.Best({ 2, 3, 4, 5, 6, 6 }), 50)
		eq(F.Score({ 1, 1, 1, 1 }), 1100)
		eq(F.Score({ 1, 1, 1, 1, 1, 1 }), 2000, "two threes of a kind")
	end)
	-- a row with no points above 0 is left out too, and a key that is not faces is no run
	With({ { S.run, "23456", 0 }, { S.run, "1234", 200 }, { S.run, "x", 900 } }, function()
		eq(F.Score({ 2, 3, 4, 5, 6 }), nil)
		eq(F.Score({ 1, 2, 3, 4 }), 200, "a run added to the table counts")
		eq(F.Farkle({ 2, 3, 4, 6, 6, 3 }), true)
	end)
	eq(F.Score({ 1, 2, 3, 4 }), nil, "restored")
	eq(F.Score({ 2, 3, 4, 5, 6 }), 750, "restored")
	eq(F.Score({ 1, 1, 1, 1 }), 2000, "restored")
end)

-- A whole row set to 0 (or to anything that is not a table) is left out like false, not an
-- error: Farkle reads the rows on every roll, so an error there would stop every table.
test("1.2 Farkle: a whole row set to 0 is left out, not an error", function()
	local S = F.SCORES
	local function Calls(dice)
		local ok, why = pcall(function() return F.Score(dice), F.Best(dice), F.Farkle(dice) end)
		assert(ok, "raised: " .. tostring(why))
		return F.Score(dice), (F.Best(dice)), F.Farkle(dice)
	end
	With({ { S, "single", 0 } }, function()
		eq(Calls({ 1 }), nil, "no lone 1")
		eq(select(3, Calls({ 1, 2, 3, 4, 6, 6 })), true, "no lone dice, no run, no set: a Farkle")
		eq(Calls({ 1, 1, 1 }), 1000, "three 1s still count")
		eq(Calls({ 1, 2, 3, 4, 5 }), 500, "and the runs")
	end)
	With({ { S, "triple", 0 } }, function()
		eq(Calls({ 3, 3, 3 }), nil, "no three of a kind")
		eq(Calls({ 3, 3, 3, 3 }), nil, "and no four, which follows it")
		eq(Calls({ 1, 1, 1 }), 300, "three lone 1s")
		eq(select(3, Calls({ 2, 2, 2, 3, 4, 6 })), true)
	end)
	With({ { S, "kind", 0 } }, function()
		eq(Calls({ 1, 1, 1, 1 }), 1100, "three 1s and a 1")
		eq(Calls({ 3, 3, 3, 3 }), nil)
		eq(Calls({ 3, 3, 3 }), 300)
	end)
	With({ { S, "run", 0 } }, function()
		eq(Calls({ 2, 3, 4, 5, 6 }), nil)
		eq(select(2, Calls({ 1, 2, 3, 4, 5, 6 })), 150, "a 1 and a 5")
	end)
	eq(F.Score({ 3, 3, 3, 3 }), 600, "restored")
end)

test("1.2 Farkle: Best names the most a roll scores and which dice give it", function()
	local points, pick = F.Best({ 5, 3, 1, 2, 1, 5 })
	eq(points, 300); eq(list(pick), "1 3 5 6")
	points, pick = F.Best({ 2, 3, 4, 6, 6, 3 })
	eq(points, 0); eq(#pick, 0)
	-- KCD2: no three pairs (was 1,500 with every die)
	points, pick = F.Best({ 2, 2, 3, 3, 4, 4 })
	eq(points, 0); eq(#pick, 0)
	-- KCD2: four 1s are one combination (was 1,100)
	points, pick = F.Best({ 1, 1, 1, 1, 2, 3 })
	eq(points, 2000); eq(list(pick), "1 2 3 4")
	points, pick = F.Best({ 4, 1, 4, 4 })
	eq(points, 500); eq(list(pick), "1 2 3 4")
	points, pick = F.Best({ 5, 2, 5 })
	eq(points, 100); eq(list(pick), "1 3")
	-- KCD2's runs: with an extra 1 or 5 every die scores; a second 6 stays on the table (the first
	-- one found is kept, the lower position)
	points, pick = F.Best({ 1, 2, 3, 4, 5, 5 })
	eq(points, 550); eq(list(pick), "1 2 3 4 5 6")
	points, pick = F.Best({ 2, 3, 4, 5, 6, 1 })
	eq(points, 1500); eq(list(pick), "1 2 3 4 5 6")
	points, pick = F.Best({ 2, 3, 4, 5, 6, 6 })
	eq(points, 750); eq(list(pick), "1 2 3 4 5")
	points, pick = F.Best({ 6, 2, 3, 4, 5, 6 })
	eq(points, 750); eq(list(pick), "1 2 3 4 5")
	points, pick = F.Best({ 1, 1, 5, 5, 6, 6 })
	eq(points, 300); eq(list(pick), "1 2 3 4")
	points, pick = F.Best({ 4, 4, 4, 4, 1, 1 })
	eq(points, 1000); eq(list(pick), "1 2 3 4 5 6")
	eq(F.Best({}), nil)
	eq(F.Best({ 1, 9 }), nil)
	eq(F.Best(nil), nil)
end)

test("1.2 Farkle: CanScore and Farkle say whether anything in a roll scores", function()
	-- KCD2: three pairs score nothing (the old table scored 2-2-3-3-4-4 at 1,500)
	eq(F.CanScore({ 2, 2, 3, 3, 4, 4 }), false, "no three pairs: a Farkle")
	eq(F.Farkle({ 2, 2, 3, 3, 4, 4 }), true)
	eq(F.Farkle({ 2, 2, 3, 3, 6, 6 }), true)
	eq(F.CanScore({ 2, 3, 4, 6, 6, 3 }), false, "a Farkle")
	eq(F.Farkle({ 2, 3, 4, 6, 6, 3 }), true, "2-3-4 and 3-4-6 are no runs")
	eq(F.Farkle({ 2, 3, 4, 6, 2 }), true)
	eq(F.Farkle({ 2 }), true)
	eq(F.Farkle({ 3, 3 }), true)
	eq(F.Farkle({ 5 }), false)
	eq(F.CanScore({ 5 }), true)
	eq(F.Farkle({ 4, 4, 4 }), false)
	eq(F.Farkle({ 6, 2, 3, 6, 4, 6 }), false)
	eq(F.CanScore({ 2, 3, 4, 5, 6, 6 }), true, "the run 2-6")
	for _, bad in ipairs({ {}, { 1, 7 }, { 1.5 }, "15" }) do
		eq(F.Farkle(bad), nil)
		eq(F.CanScore(bad), nil, "not a roll: neither true nor false")
	end
	eq(F.CanScore(nil), nil)
end)

-- Counted by hand: a Farkle has no 1 or 5 and no face three times (every run holds a 1 or a 5),
-- so its dice are 2, 3, 4 and 6 with each face at most twice (six dice: 1,440 such rolls). These
-- are KCD2's odds: 66.7%, 44.4%, 27.8%, 15.7%, 7.7% and 3.1%. (The old table's three pairs saved
-- 360 of the six-dice rolls: 1,080 and 2.3% then.)
test("1.2 Farkle: over every roll of n dice, the Farkles number 4, 16, 60, 204, 600 and 1,440", function()
	local want = { 4, 16, 60, 204, 600, 1440 }
	for n = 1, 6 do
		local count = 0
		for v = 1, F.RANGES[n] do
			local dice = F.Decode(v, n)
			if F.Farkle(dice) then count = count + 1 end
			eq(F.CanScore(dice), not F.Farkle(dice))
		end
		eq(count, want[n], n .. " dice")
	end
end)

test("1.2 Farkle: Farkle agrees with Best on every set of 1 to 6 dice, with the points changed too", function()
	local function Agree(label)
		local sets = 0
		Every(function(d)
			sets = sets + 1
			local points = F.Best(d)
			eq(F.Farkle(d), points == 0, label .. ": " .. list(d))
			eq(F.CanScore(d), points > 0, label .. ": " .. list(d))
		end)
		eq(sets, 923, "every set of 1 to 6 dice")
	end
	Agree("the table's points")
	local S = F.SCORES
	-- (the old table's three pairs row is gone; the run 2-3-4-5-6 takes its place here)
	With({ { S.single, 5, false }, { S.triple, 2, false }, { S.kind, 4, false }, { S.run, "23456", false } }, function()
		Agree("points changed")
		eq(F.Farkle({ 2, 2, 2, 3, 4, 6 }), true, "three 2s left out")
		eq(F.Farkle({ 2, 2, 2, 2, 3, 4 }), true, "and four 2s with them")
		eq(F.Farkle({ 2, 3, 4, 5, 6, 6 }), true, "and the run 2-6, and the lone 5")
		eq(F.Farkle({ 3, 3, 3, 3, 2, 4 }), false, "three 3s still count")
		eq(F.Farkle({ 2, 2, 2, 3, 3, 3 }), false, "and so do two threes of a kind, by their 3s")
	end)
	-- a run is the only way these rolls score
	With({ { S, "single", false } }, function()
		Agree("no lone dice")
		eq(F.Farkle({ 1, 2, 3, 4, 5, 2 }), false, "the run 1-5")
		eq(F.Farkle({ 6, 2, 3, 4, 5, 6 }), false, "the run 2-6")
		eq(F.Farkle({ 1, 3, 4, 5, 6, 6 }), true, "no run")
	end)
end)

-- The page's Best button and the House select these dice, so they must score what Best says,
-- and with the table's points no selection of other faces may score as much (a tie would leave
-- the choice to the order of the search). KCD2's runs of five changed how this is counted: in
-- 2-3-4-5-6-6 either 6 completes the run, so two selections of the same faces score 750, and
-- selections are now told apart by their faces, not their positions (Best takes the lower one).
test("1.2 Farkle: on every set of 1 to 6 dice, Best's dice score its points and no selection of other faces does", function()
	local sets, twins = 0, 0
	Every(function(d)
		sets = sets + 1
		local n = #d
		local points, pick = F.Best(d)
		if points == 0 then return eq(#pick, 0, list(d)) end
		local faces = {}
		for i, p in ipairs(pick) do faces[i] = d[p] end
		eq(F.Score(faces), points, "the dice Best names, from " .. list(d))
		local same, seen = 0, {}
		for mask = 1, 2 ^ n - 1 do
			local sel, m = {}, mask
			for i = 1, n do
				if m % 2 == 1 then sel[#sel + 1] = d[i] end
				m = math.floor(m / 2)
			end
			local score = F.Score(sel)
			local key = list(sel)             -- d is in ascending order, and so is sel
			if score == points and not seen[key] then
				seen[key] = true
				same = same + 1
			elseif score == points then
				twins = twins + 1
			end
			assert((score or 0) <= points, "a selection beats Best in " .. list(d))
		end
		eq(same, 1, "one selection of faces scores " .. points .. " in " .. list(d))
	end)
	eq(sets, 923)
	-- 1-2-3-4-5 with a 2, 3 or 4, and 2-3-4-5-6 with a 2, 3, 4 or 6
	eq(twins, 7, "the runs of five with a second die of one of their faces")
end)

---------------------------------------------------------------------------
-- A turn
---------------------------------------------------------------------------

test("1.2 Farkle: a turn rolls, sets aside, rolls the dice left and banks; wrong moves change nothing", function()
	local t = F.Turn.New()
	eq(t.points, 0); eq(t.left, 6); eq(t.phase, "roll")
	eq(err(F.Turn.Bank(t)), "empty", "no bank before rolling")
	eq(err(F.Turn.Keep(t, { 1 })), "roll", "nothing on the table yet")
	local dice, farkle = F.Turn.Roll(t, 31337)
	eq(list(dice), "5 3 1 2 1 5"); eq(farkle, false); eq(t.phase, "keep"); eq(t.rolls, 1)
	eq(err(F.Turn.Roll(t, 46656)), "keep", "set aside before rolling again")
	eq(err(F.Turn.Bank(t)), "keep", "set aside before banking")
	eq(err(F.Turn.Keep(t, { 2 })), "score", "a 3 doesn't score")
	eq(err(F.Turn.Keep(t, { 3, 2 })), "score", "a 1 and a 3")
	eq(err(F.Turn.Keep(t, { 7 })), "dice", "no seventh die")
	eq(err(F.Turn.Keep(t, { 0 })), "dice")
	eq(err(F.Turn.Keep(t, { 3, 3 })), "dice", "one die twice")
	eq(err(F.Turn.Keep(t, {})), "dice")
	eq(err(F.Turn.Keep(t, { 1.5 })), "dice")
	eq(err(F.Turn.Keep(t, "35")), "dice")
	eq(err(F.Turn.Keep(t, { 3, x = 5 })), "dice")
	eq(err(F.Turn.Keep(t, { 1, 2, 3, 4, 5, 6, 1 })), "dice")
	eq(t.points, 0); eq(t.left, 6); eq(t.phase, "keep"); eq(t.kept, nil)
	local points, hot = F.Turn.Keep(t, { 5, 3 })
	eq(points, 200); eq(hot, false); eq(t.points, 200); eq(t.left, 4); eq(t.phase, "decide")
	eq(list(t.kept), "3 5")
	eq(err(F.Turn.Keep(t, { 1 })), "roll", "one set-aside per roll")
	eq(err(F.Turn.Roll(t, 1297)), "range", "four dice roll 1-1296")
	eq(err(F.Turn.Roll(t, 7776)), "range")
	eq(t.points, 200); eq(t.left, 4); eq(t.rolls, 1)
	dice = F.Turn.Roll(t, R(5, 2, 3, 4))
	eq(list(dice), "5 2 3 4"); eq(t.rolls, 2)
	eq(t.kept, nil, "the new roll has nothing set aside yet")
	eq(F.Turn.Keep(t, { 1 }), 50)
	eq(t.points, 250); eq(t.left, 3)
	eq(F.Turn.Bank(t), 250)
	eq(t.banked, 250); eq(t.phase, "done")
	eq(err(F.Turn.Roll(t, 1)), "done")
	eq(err(F.Turn.Keep(t, { 1 })), "done")
	eq(err(F.Turn.Bank(t)), "done")
end)

test("1.2 Farkle: the turn's moves refuse what is not a turn instead of raising an error", function()
	for _, t in ipairs({ false, 5, "turn" }) do
		eq(err(F.Turn.Roll(t, 5)), "game")
		eq(err(F.Turn.Keep(t, { 1 })), "game")
		eq(err(F.Turn.Bank(t)), "game")
	end
	eq(err(F.Turn.Roll(nil, 5)), "game")
	eq(err(F.Turn.Keep(nil, { 1 })), "game")
	eq(err(F.Turn.Bank(nil)), "game")
end)

test("1.2 Farkle: a Farkle ends the turn and loses its points", function()
	local t = F.Turn.New()
	F.Turn.Roll(t, R(1, 2, 3, 4, 6, 6))
	eq(F.Turn.Keep(t, { 1 }), 100)
	local dice, farkle = F.Turn.Roll(t, R(2, 3, 4, 6, 2))
	eq(list(dice), "2 3 4 6 2"); eq(farkle, true)
	eq(t.farkle, true); eq(t.points, 0); eq(t.lost, 100); eq(t.phase, "done")
	eq(err(F.Turn.Bank(t)), "done")
	-- a Farkle on the first roll
	t = F.Turn.New()
	dice, farkle = F.Turn.Roll(t, R(2, 2, 3, 3, 4, 6))
	eq(farkle, true); eq(t.lost, 0); eq(t.phase, "done")
end)

test("1.2 Farkle: hot dice: every die set aside, all six roll again and the points stay", function()
	local t = F.Turn.New()
	F.Turn.Roll(t, R(3, 6, 1, 5, 2, 4))
	local points, hot = F.Turn.Keep(t, { 1, 2, 3, 4, 5, 6 })
	eq(points, 1500); eq(hot, true); eq(F.HotDice(t), true); eq(t.left, 6); eq(t.phase, "decide")
	local dice = F.Turn.Roll(t, 46656)
	eq(#dice, 6, "six dice again"); eq(F.HotDice(t), false)
	-- six 6s: 600 x 8 with KCD2's points (the old table's flat six of a kind was 3,000)
	eq(F.Turn.Keep(t, { 1, 2, 3, 4, 5, 6 }), 4800)
	eq(t.points, 6300)
	-- over several set-asides
	t = F.Turn.New()
	F.Turn.Roll(t, R(1, 1, 1, 2, 3, 4))
	eq(F.Turn.Keep(t, { 1, 2, 3 }), 1000)
	eq(t.left, 3); eq(F.HotDice(t), false)
	eq(err(F.Turn.Roll(t, 217)), "range", "three dice roll 1-216")
	F.Turn.Roll(t, R(5, 5, 5))
	points, hot = F.Turn.Keep(t, { 3, 1, 2 })
	eq(points, 500); eq(hot, true); eq(t.left, 6)
	eq(F.Turn.Bank(t), 1500, "a bank on hot dice")
	-- the roll after hot dice can still farkle, and loses it all
	t = F.Turn.New()
	F.Turn.Roll(t, R(1, 2, 3, 4, 5, 6))
	F.Turn.Keep(t, { 1, 2, 3, 4, 5, 6 })
	local _, farkle = F.Turn.Roll(t, R(2, 2, 3, 3, 4, 6))
	eq(farkle, true); eq(t.lost, 1500); eq(t.points, 0)
	eq(F.HotDice(nil), false)
end)

---------------------------------------------------------------------------
-- A new game
---------------------------------------------------------------------------

-- The design: New takes an explicit target of 2,000, 5,000 or 10,000 (the table always passes it; the
-- page's default is 5,000), and the turn caps 12, 25 and 45 follow from it on every client.
test("1.2 Farkle: New needs the target named, one of 2,000, 5,000 or 10,000, and the cap follows from it", function()
	eq(F.TARGET, 5000, "the page's default")
	eq(list(F.TARGETS), "2000 5000 10000")
	eq(F.New({ target = 2000 }).cap, 12)
	eq(F.New({ target = 5000 }).cap, 25)
	eq(F.New({ target = 10000 }).cap, 45)
	local caps = 0
	for target, cap in pairs(F.TURN_CAP) do
		caps = caps + 1
		eq(F.New({ target = target }).cap, cap)
	end
	eq(caps, #F.TARGETS, "a cap for every target offered, and no other")
	eq(err(F.New({})), "target", "no default target")
	eq(err(F.New({ players = { A, B } })), "target")
	for _, bad in ipairs({ 1000, 3000, 0, -5000, 5000.5, 1e308, 2 ^ 53 + 2, 0 / 0, "5000", "5", 5, true }) do
		eq(err(F.New({ target = bad })), "target", tostring(bad))
	end
	eq(F.New({ target = 2000, cap = 3 }).cap, 12, "no cap of the caller's: one rule set")
	eq(err(F.New()), "fields")
	eq(err(F.New("x")), "fields")
end)

-- KI and KG carry the target as its code 2|5|10 (the design). TARGETS is a list, so
-- TARGETS[code] would read a quick game as 5,000 on every client, and 5 or 10 as no target.
test("1.2 Farkle: the wire's target code 2|5|10 reads as 2,000, 5,000 or 10,000 points, and back", function()
	eq(F.TARGET_BY_CODE[2], 2000, "a quick game")
	eq(F.TARGET_BY_CODE[5], 5000)
	eq(F.TARGET_BY_CODE[10], 10000)
	local seen = 0
	for code, target in pairs(F.TARGET_BY_CODE) do
		seen = seen + 1
		eq(F.TARGET_CODE[target], code, "back to the code")
		eq(F.New({ target = target }).target, target, "a target New takes")
	end
	eq(seen, #F.TARGETS, "a code for every target offered")
	seen = 0
	for _ in pairs(F.TARGET_CODE) do seen = seen + 1 end
	eq(seen, #F.TARGETS)
	for _, bad in ipairs({ 0, 1, 3, 2000, "2", "5", 2.5, true }) do
		eq(F.TARGET_BY_CODE[bad], nil, "no target for code " .. tostring(bad))
	end
	eq(F.TARGET_CODE[3000], nil); eq(F.TARGET_CODE[2], nil)
end)

test("1.2 Farkle: a new game opens with the opening rolls, unless the seat that starts is named", function()
	local g = F.New({ target = 5000, players = { A, B } })
	eq(g.open, true); eq(g.current, nil); eq(g.first, nil); eq(g.over, false)
	eq(g.scores[1], 0); eq(g.scores[2], 0); eq(g.turns[1], 0); eq(g.ties, 0)
	eq(g.step, 0); eq(#g.events, 0)
	local who, phase, left = F.Expect(g)
	eq(who, 0, "either player"); eq(phase, "open"); eq(left, nil)
	eq(err(F.Roll(g, A, 46656)), "open", "no dice before the opening decides")
	eq(err(F.Keep(g, A, { 1 })), "open")
	eq(err(F.Bank(g, A)), "open")
	eq(err(F.Timeout(g, A)), "open")
	eq(err(F.Foul(g, A)), "open")
	eq(F.HouseMove(g), nil)
	g = F.New({ target = 5000, first = 2 })
	eq(g.open, false); eq(g.current, 2); eq(g.first, 2)
	who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "roll"); eq(left, 6)
	eq(err(F.New({ target = 5000, first = 3 })), "first")
	eq(err(F.New({ target = 5000, first = "1" })), "first")
	eq(err(F.New({ target = 5000, first = 0 })), "first")
end)

test("1.2 Farkle: New checks the names, the id and the terms that start the chain", function()
	eq(F.New({ target = 2000, players = { A, B } }).players[2], B)
	local bad = {
		{ A, A }, { A, A:lower() }, { "Aa-R", "aa-R" }, { A }, { A, "" }, { A, 5 }, { A, "Bo|b-R" },
		{ A, "Bob\n-R" }, "AB",
	}
	for i, p in ipairs(bad) do eq(err(F.New({ target = 2000, players = p })), "players", "case " .. i) end
	eq(err(F.New({ target = 2000, id = "k|1" })), "id")
	eq(err(F.New({ target = 2000, id = "k\n1" })), "id")
	eq(err(F.New({ target = 2000, id = 7 })), "id")
	eq(err(F.New({ target = 2000, terms = "a\nb" })), "terms")
	eq(err(F.New({ target = 2000, terms = {} })), "terms")
	local g = F.New({ target = 2000, id = "k7x2q9", players = { A, B }, terms = "d|1000|-|o|o|60" })
	eq(g.id, "k7x2q9")
	eq(g.head, "farkle1|k7x2q9|2000|thessaly ironbrand-realm|corvin ashgrove-realm||d|1000|-|o|o|60",
		"the terms may hold | (they end the line); names in lower case")
	eq(F.New({ target = 2000, first = 1 }).head, "farkle1||2000|||1|")
	-- the head line starts the chain: any agreed field that differs makes another chain
	local chains = {}
	for _, f in ipairs({
		{ target = 2000, id = "k7x2q9", terms = "d|1000" },
		{ target = 5000, id = "k7x2q9", terms = "d|1000" },
		{ target = 2000, id = "k7x2q8", terms = "d|1000" },
		{ target = 2000, id = "k7x2q9", terms = "d|1001" },
		{ target = 2000, id = "k7x2q9", terms = "d|1000", first = 1 },
		{ target = 2000, id = "k7x2q9", terms = "d|1000", players = { A, B } },
		{ target = 2000, id = "k7x2q9", terms = "d|1000", players = { B, A } },
	}) do
		local c = F.New(f).chain
		eq(#c, 8)
		assert(not chains[c], "two different games share a first link")
		chains[c] = true
	end
	eq(F.New({ target = 2000, players = { A, B } }).chain, F.New({ target = 2000, players = { A:upper(), B:lower() } }).chain,
		"names in any case make the same chain")
end)

test("1.2 Farkle: without Sign.lua a game cannot start (its chain needs the SHA-256); the scoring still works", function()
	local bare = {}
	assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", bare)
	local G = bare.FarkleRules
	eq(err(G.New({ target = 2000 })), "sign")
	eq(G.Score({ 1, 1, 1, 1 }), 2000, "four 1s (KCD2; the old table's 1,100)")
	eq(G.Chain("0", "V"), nil)
end)

---------------------------------------------------------------------------
-- A game played with the page's moves
---------------------------------------------------------------------------

test("1.2 Farkle: moves out of turn, by a stranger or with nothing to bank are refused and change nothing", function()
	local g = Game({ players = { A, B } })
	local chain = g.chain
	eq(err(F.Roll(g, B, 46656)), "turn")
	eq(err(F.Roll(g, 2, 46656)), "turn")
	eq(err(F.Roll(g, "Marda Vell-Realm", 46656)), "player")
	eq(err(F.Roll(g, 3, 46656)), "player")
	eq(err(F.Roll(g, nil, 46656)), "player")
	eq(err(F.Bank(g, A)), "empty", "banking with 0")
	eq(err(F.Keep(g, A, { 1 })), "roll")
	eq(err(F.Timeout(g, B)), "turn")
	eq(err(F.Foul(g, B)), "turn")
	eq(err(F.Roll(g, A, 0)), "range")
	eq(err(F.Roll(g, A, 46657)), "range")
	eq(err(F.Concede(g, "Marda Vell-Realm")), "player")
	eq(g.current, 1); eq(g.turn.phase, "roll"); eq(g.turn.rolls, 0); eq(g.turns[1], 0); eq(g.over, false)
	eq(g.step, 0); eq(g.chain, chain, "nothing written")
	local dice = F.Roll(g, A, 31337)
	eq(list(dice), "5 3 1 2 1 5")
	local rolled = g.chain
	eq(err(F.Roll(g, A, 46656)), "keep", "no second roll before he sets dice aside")
	eq(g.step, 1); eq(g.chain, rolled); eq(g.current, 1); eq(g.turn.phase, "keep"); eq(g.turn.rolls, 1)
	eq(list(g.turn.dice), "5 3 1 2 1 5")
	eq(err(F.Keep(g, B, { 3 })), "turn", "the other player can't set aside")
	eq(err(F.Keep(g, A, { 2 })), "score")
	eq(err(F.Keep(g, A, { 9 })), "dice", "not a die of the roll")
	eq(err(F.Bank(g, A)), "keep")
	eq(F.Keep(g, A, { 1, 3, 5, 6 }), 300)
	eq(err(F.Bank(g, B)), "turn")
	eq(F.Bank(g, A), 300)
	eq(g.scores[1], 300); eq(g.scores[2], 0); eq(g.current, 2); eq(g.turns[1], 1)
	eq(g.turn.phase, "roll"); eq(g.turn.points, 0); eq(g.turn.left, 6)
	eq(g.last.who, 1); eq(g.last.how, "bank"); eq(g.last.points, 300)
	eq(err(F.Roll(g, A, 46656)), "turn", "the turn passed")
	local who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "roll"); eq(left, 6)
	eq(codes(g), "R1:6:31337 K1:1356:b", "the page's moves write the codes the table's events do")
end)

test("1.2 Farkle: a player is named in any case, and the game's moves refuse what is not a game", function()
	local g = Game({ players = { A, B } })
	eq(err(F.Roll(g, B:lower(), 46656)), "turn", "still the other player")
	local dice = F.Roll(g, A:upper(), 31337)
	eq(list(dice), "5 3 1 2 1 5")
	eq(F.Keep(g, A:lower(), { 3 }), 100)
	eq(F.Bank(g, "thessaly ironbrand-realm"), 100)
	eq(g.current, 2)
	eq(F.Concede(g, B:upper()), true)
	eq(g.winner, 1)
	-- nothing that New made: a table the table's code dropped, or a stray value
	for _, bad in ipairs({ false, 7, "game", {}, { turn = {} }, { turn = {}, players = {} } }) do
		eq(err(F.Roll(bad, 1, 5)), "game")
		eq(err(F.Keep(bad, 1, { 1 })), "game")
		eq(err(F.Bank(bad, 1)), "game")
		eq(err(F.Timeout(bad, 1)), "game")
		eq(err(F.Foul(bad, 1)), "game")
		eq(err(F.Concede(bad, 1)), "game")
		eq(err(F.Void(bad)), "game")
		eq(err(F.Apply(bad, "V")), "game")
		eq(F.Expect(bad), nil)
		eq(F.HouseMove(bad), nil)
		eq(F.Transcript(bad), nil)
		eq(F.Hash(bad), nil)
		eq(F.ChainAt(bad, 0), nil)
	end
	eq(err(F.Roll(nil, 1, 5)), "game")
	eq(err(F.Keep(nil, 1, { 1 })), "game")
	eq(err(F.Bank(nil, 1)), "game")
	eq(err(F.Timeout(nil, 1)), "game")
	eq(err(F.Foul(nil, 1)), "game")
	eq(err(F.Concede(nil, 1)), "game")
	eq(F.Expect(nil), nil)
end)

-- The table's code checks a roll's range against the dice Expect names, and fouls a wrong count
-- (spec W2). In "keep" the roll that comes next is not due yet (it can reach a witness before
-- the keep, spec W3), so Expect names no count there rather than the dice just thrown: an honest
-- re-roll of four dice must never be compared with six.
test("1.2 Farkle: Expect names who acts, what he must do and the dice his roll throws (none while he sets aside)", function()
	local g = Game({ first = 2 })
	local who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "roll"); eq(left, 6)
	F.Roll(g, 2, R(1, 5, 2, 3, 4, 6))
	who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "keep"); eq(left, nil, "no count until he sets dice aside")
	F.Keep(g, 2, { 1, 2 })
	who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "decide"); eq(left, 4)
	eq(F.RangeK(1, 1296), left, "his honest roll of four dice fits")
	F.Roll(g, 2, R(1, 1, 1, 2))
	who, phase, left = F.Expect(g)
	eq(phase, "keep"); eq(left, nil)
	F.Keep(g, 2, { 1, 2, 3 })
	who, phase, left = F.Expect(g)
	eq(phase, "decide"); eq(left, 1)
	F.Roll(g, 2, 5)
	F.Keep(g, 2, { 1 })
	who, phase, left = F.Expect(g)
	eq(phase, "decide"); eq(left, 6, "hot dice: six again"); eq(F.HotDice(g.turn), true)
end)

test("1.2 Farkle: a Farkle passes the turn with nothing", function()
	local g = Game()
	F.Roll(g, 1, R(1, 2, 3, 4, 6, 6))
	F.Keep(g, 1, { 1 })
	local _, farkle = F.Roll(g, 1, R(2, 3, 4, 6, 2))
	eq(farkle, true)
	eq(g.scores[1], 0); eq(g.current, 2); eq(g.turns[1], 1)
	eq(g.last.how, "farkle"); eq(g.last.lost, 100); eq(list(g.last.dice), "2 3 4 6 2")
	eq(g.turn.phase, "roll"); eq(g.turn.left, 6)
	eq(codes(g), ("R1:6:%d K1:1:r R1:5:%d"):format(R(1, 2, 3, 4, 6, 6), R(2, 3, 4, 6, 2)))
end)

-- Four 1s and two 5s (2,100) reach the 2,000 target in one turn; 1 2 3 4 6 6 scores 100.
test("1.2 Farkle: banking the target wins immediately without an answer turn", function()
	local g = Game()
	eq(Play(g, 1, 1, 1, 1, 1, 5, 5), 2100)
	eq(g.over, true); eq(g.winner, 1); eq(g.reason, "target"); eq(g.current, nil)
	eq(g.final, nil)
	eq(F.Expect(g), nil)
	eq(err(F.Roll(g, 1, 46656)), "over")
	eq(err(F.Concede(g, 2)), "over")
	eq(err(F.Roll(g, 2, 46656)), "over", "the other player cannot answer")
	-- The second player can win on his own turn too, without an extra turn for the first.
	g = Game()
	Play(g, 1, 5, 2, 3, 3, 6, 6)
	Play(g, 2, 1, 1, 1, 1, 5, 5)
	eq(g.over, true); eq(g.winner, 2); eq(g.scores[1], 50); eq(g.turns[1], 1); eq(g.turns[2], 1)
	-- a bank short of the target starts nothing (KCD2: two threes of a kind, 1,500; the old
	-- table's four 1s at 1,100 are 2,000 now, the target itself)
	g = Game()
	Play(g, 1, 1, 1, 1, 5, 5, 5)
	eq(g.scores[1], 1500); eq(g.final, nil); eq(g.current, 2)
end)

test("1.2 Farkle: level at the turn cap goes to sudden death, a turn each until one is ahead", function()
	local g = Game()
	for _ = 1, 12 do Bust(g, 1); Bust(g, 2) end
	eq(g.over, false, "0 all"); eq(g.sudden, true); eq(g.current, 1)
	Play(g, 1, 5, 2, 3, 3, 6, 6)
	eq(g.over, false, "the second player still has his turn")
	Bust(g, 2)
	eq(g.over, true); eq(g.winner, 1); eq(g.reason, "cap")
	-- level again: go on
	g = Game()
	for _ = 1, 12 do Bust(g, 1); Bust(g, 2) end
	Bust(g, 1)
	Bust(g, 2)
	eq(g.over, false); eq(g.current, 1)
	Play(g, 1, 5, 2, 3, 3, 6, 6)
	Play(g, 2, 1, 2, 3, 4, 6, 6)
	eq(g.over, true); eq(g.winner, 2); eq(g.scores[1], 50); eq(g.scores[2], 100)
end)

test("1.2 Farkle: the turn cap (12, 25 and 45 turns each) ends a stalled game on the higher score", function()
	local g = Game()
	for _ = 1, 11 do Bust(g, 1); Bust(g, 2) end
	Play(g, 1, 1, 2, 3, 4, 6, 6)
	eq(g.over, false, "the second player's twelfth turn is still to come")
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	eq(g.over, true); eq(g.winner, 1); eq(g.reason, "cap"); eq(g.turns[1], 12); eq(g.turns[2], 12)
	-- level at the cap: sudden death
	g = Game()
	for _ = 1, 12 do Bust(g, 1); Bust(g, 2) end
	eq(g.over, false, "0 all at the cap"); eq(g.sudden, true); eq(g.current, 1)
	Bust(g, 1)
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	eq(g.winner, 2); eq(g.reason, "cap"); eq(g.turns[1], 13)
	-- Reaching the target on the capped turn still wins immediately.
	g = Game()
	for _ = 1, 11 do Bust(g, 1); Bust(g, 2) end
	Play(g, 1, 5, 2, 3, 3, 6, 6)
	Play(g, 2, 1, 1, 1, 1, 5, 5)
	eq(g.over, true); eq(g.final, nil); eq(g.current, nil)
	eq(g.winner, 2); eq(g.reason, "target"); eq(g.turns[1], 12)
	-- the other targets' caps
	for target, cap in pairs({ [5000] = 25, [10000] = 45 }) do
		g = Game({ target = target })
		for _ = 1, cap - 1 do Bust(g, 1); Bust(g, 2) end
		Play(g, 1, 5, 2, 3, 3, 6, 6)
		eq(g.over, false, target .. ": one turn left")
		Bust(g, 2)
		eq(g.winner, 1, target); eq(g.reason, "cap"); eq(g.turns[2], cap)
	end
end)

test("1.2 Farkle: a turn lost to the clock scores nothing; three in a row forfeit", function()
	local g = Game()
	F.Roll(g, 1, R(1, 2, 3, 4, 6, 6))
	F.Keep(g, 1, { 1 })
	eq(F.Timeout(g, 1), true)
	eq(g.scores[1], 0); eq(g.last.how, "timeout"); eq(g.last.lost, 100); eq(g.timeouts[1], 1); eq(g.current, 2)
	eq(codes(g), ("R1:6:%d T1"):format(R(1, 2, 3, 4, 6, 6)), "a set-aside he never acted on is not written")
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1)
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	eq(g.timeouts[1], 2); eq(g.over, false)
	F.Timeout(g, 1)
	eq(g.over, true); eq(g.winner, 2); eq(g.reason, "forfeit")
	eq(g.events[#g.events], "A1", "the third timeout in a row is written as the forfeit")
	-- a turn played in between starts the count again, and a foul is no timeout
	g = Game()
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	Play(g, 1, 5, 2, 3, 3, 6, 6)
	eq(g.timeouts[1], 0)
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	eq(err(F.Foul(g, 1)), "event")
	eq(g.timeouts[1], 2, "a refused action does not reset timeout history")
	Bust(g, 1)
	eq(g.timeouts[1], 0); eq(g.over, false)
	Bust(g, 2)
	F.Timeout(g, 1); Bust(g, 2)
	eq(g.timeouts[1], 1); eq(g.over, false)
	-- a Farkle is a turn played too
	g = Game()
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1); Play(g, 2, 5, 2, 3, 3, 6, 6)
	eq(g.timeouts[1], 2)
	Bust(g, 1)
	eq(g.timeouts[1], 0, "the Farkle starts the count again")
	Play(g, 2, 5, 2, 3, 3, 6, 6)
	F.Timeout(g, 1)
	eq(g.timeouts[1], 1); eq(g.over, false, "one timeout since, no forfeit")
end)

test("1.2 Farkle: a live foul request is refused without losing the turn or points", function()
	local g = Game()
	F.Roll(g, 1, R(1, 1, 1, 2, 3, 4))
	F.Keep(g, 1, { 1, 2, 3 })
	local before = codes(g)
	eq(err(F.Foul(g, 1)), "event")
	eq(g.scores[1], 0); eq(g.last, nil); eq(g.turn.points, 1000); eq(g.current, 1); eq(g.timeouts[1], 0)
	eq(codes(g), before)
end)

test("1.2 Farkle: either player may concede, on his turn or not; then the game takes no move", function()
	local g = Game({ players = { A, B } })
	eq(F.Concede(g, B), true, "not his turn")
	eq(g.over, true); eq(g.winner, 1); eq(g.reason, "concede")
	eq(codes(g), "C2")
	eq(err(F.Concede(g, A)), "over")
	eq(err(F.Bank(g, A)), "over")
	eq(err(F.Timeout(g, A)), "over")
	eq(err(F.Foul(g, A)), "over")
	eq(err(F.Keep(g, A, { 1 })), "over")
	eq(err(F.Void(g)), "over")
	g = Game()
	F.Roll(g, 1, R(1, 1, 1, 2, 3, 4))
	eq(F.Concede(g, 1), true)
	eq(g.winner, 2)
	-- in the opening too
	g = F.New({ target = 2000 })
	eq(F.Concede(g, 2), true)
	eq(g.winner, 1); eq(g.reason, "concede")
end)

test("1.2 Farkle: a void ends the game with no winner", function()
	local g = Game()
	F.Roll(g, 1, R(1, 1, 1, 2, 3, 4))
	eq(F.Void(g), true)
	eq(g.over, true); eq(g.winner, nil); eq(g.reason, "void"); eq(g.current, nil)
	eq(g.events[#g.events], "V")
	eq(F.Expect(g), nil)
	eq(err(F.Apply(g, Roll(1, 2, 2, 3, 3, 4, 6))), "over")
	g = F.New({ target = 2000 })
	eq(F.Apply(g, "V"), true, "in the opening too")
	eq(g.reason, "void")
end)

test("1.2 Farkle: 300 games on a seeded server all end with the winner ahead, in steps of 50", function()
	local roll = Server(20260930)
	local reasons = {}
	for n = 1, 300 do
		local g = Game({ target = F.TARGETS[n % 3 + 1], first = n % 2 + 1 })
		local steps = 0
		while not g.over do
			steps = steps + 1
			assert(steps < 20000, "game " .. n .. " never ended")
			local who, phase, left = F.Expect(g)
			if phase == "keep" then
				local _, pick = F.Best(g.turn.dice)
				assert(F.Keep(g, who, pick))
			elseif phase == "decide" and (g.turn.points >= 1000 or (g.turn.points >= 300 and left <= 2)) then
				assert(F.Bank(g, who))
			else
				assert(F.Roll(g, who, roll(F.RANGES[left])))
			end
		end
		local w = g.winner
		assert(w == 1 or w == 2, "a winner")
		assert(g.scores[w] > g.scores[3 - w], "game " .. n .. ": the winner is ahead")
		eq(g.scores[1] % 50, 0); eq(g.scores[2] % 50, 0)
		assert(math.abs(g.turns[1] - g.turns[2]) <= 1, "game " .. n .. ": turns even")
		if g.reason == "target" then
			assert(math.max(g.scores[1], g.scores[2]) >= g.target, "game " .. n .. ": target reached")
		else
			eq(g.reason, "cap")
			assert(g.turns[1] >= g.cap and g.turns[2] >= g.cap, "game " .. n .. ": cap reached")
		end
		reasons[g.reason] = (reasons[g.reason] or 0) + 1
		eq(g.step, #g.events)
	end
	assert((reasons.target or 0) > 0, "some games reach the target")
end)

---------------------------------------------------------------------------
-- Events: what a client at the table witnessed (Apply)
---------------------------------------------------------------------------

test("1.2 Farkle: the opening rolls decide who starts; a tie rolls again; only the first roll of each counts", function()
	local g = F.New({ target = 5000, players = { A, B } })
	eq(F.Apply(g, { t = "O", p = A, value = 40 }), true, "a name works as the seat")
	local who, phase = F.Expect(g)
	eq(who, 2, "the guest still to roll"); eq(phase, "open")
	local step, chain = g.step, g.chain
	eq(err(F.Apply(g, { t = "O", p = 1, value = 99 })), "extra", "his second opening roll is ignored (W1)")
	eq(err(F.Apply(g, Roll(1, 1, 1, 1, 1, 1, 1))), "open", "a dice roll in the opening")
	eq(err(F.Apply(g, { t = "T", p = 2 })), "open")
	eq(err(F.Apply(g, { t = "K", p = 1, mask = "1", act = "b" })), "open")
	eq(err(F.Apply(g, { t = "O", p = 2, value = 0 })), "range")
	eq(err(F.Apply(g, { t = "O", p = 2, value = 101 })), "range")
	eq(err(F.Apply(g, { t = "O", p = 2, value = 50.5 })), "range")
	eq(err(F.Apply(g, { t = "O", p = "Marda Vell-Realm", value = 50 })), "player")
	eq(g.step, step); eq(g.chain, chain, "refusals write nothing")
	eq(F.Apply(g, { t = "O", p = 2, value = 70 }), true)
	eq(g.open, false); eq(g.first, 2); eq(g.current, 2)
	local left
	who, phase, left = F.Expect(g)
	eq(who, 2); eq(phase, "roll"); eq(left, 6)
	eq(err(F.Apply(g, { t = "O", p = 1, value = 100 })), "started")
	eq(codes(g), "O1:40 O2:70")
	-- ties
	g = F.New({ target = 5000 })
	eq(F.Apply(g, "O2:50"), true)
	local ok, note = F.Apply(g, "O1:50")
	eq(ok, true); eq(note, "tie"); eq(g.ties, 1); eq(g.open, true)
	eq(F.Expect(g), 0, "both roll again")
	eq(F.Apply(g, "O2:10"), true)
	eq(F.Expect(g), 1)
	eq(F.Apply(g, "O1:90"), true)
	eq(g.current, 1); eq(g.first, 1); eq(g.ties, 1)
	eq(codes(g), "O2:50 O1:50 O2:10 O1:90")
	eq(F.OPENING_TIES, 5, "the table gives up after five ties (the design)")
end)

-- 31337 is 5 3 1 2 1 5: the two 1s (positions 3 and 5) score 200 and leave four dice.
test("1.2 Farkle: events play a turn, write their codes and move the chain; refused ones change nothing", function()
	local g = Game({ players = { A, B }, id = "k7x2q9" })
	local chains = { [0] = g.chain }
	local function Ok(ev)
		local ok, note = F.Apply(g, ev)
		assert(ok, "refused: " .. tostring(note))
		chains[g.step] = g.chain
		return note
	end
	local function No(ev, want, msg)
		local step, chain, cur, phase = g.step, g.chain, g.current, g.turn.phase
		eq(err(F.Apply(g, ev)), want, msg)
		eq(g.step, step, msg); eq(g.chain, chain, msg); eq(g.current, cur, msg); eq(g.turn.phase, phase, msg)
	end
	-- (the other player's roll of six dice is held for his turn instead: tested below)
	No({ t = "R", p = 2, k = 5, value = 1 }, "turn", "the other player's roll of five dice")
	No({ t = "R", p = 1, k = 6, value = 46657 }, "range")
	No({ t = "R", p = 1, k = 7, value = 1 }, "range")
	No({ t = "R", p = 1, k = 6, value = 0 }, "range")
	No({ t = "K", p = 1, mask = "1", act = "r" }, "roll", "nothing to set aside yet")
	No({ t = "Z", p = 1 }, "event")
	No("nonsense", "event")
	No(42, "event")
	No(nil, "event")
	eq(Ok({ t = "R", p = A:lower(), k = 6, value = 31337 }), nil)
	eq(list(g.turn.dice), "5 3 1 2 1 5")
	No({ t = "K", p = 1, mask = "2", act = "r" }, "score", "a 3")
	No({ t = "K", p = 1, mask = "9", act = "r" }, "dice")
	No({ t = "K", p = 1, mask = "33", act = "r" }, "dice")
	No({ t = "K", p = 1, mask = "35", act = "x" }, "event")
	No({ t = "K", p = 2, mask = "35", act = "r" }, "turn")
	eq(Ok({ t = "K", p = 1, mask = { 5, 3 }, act = "r" }), nil)
	local who, phase, left = F.Expect(g)
	eq(who, 1); eq(phase, "roll", "he chose to roll on: a roll is due"); eq(left, 4)
	No({ t = "K", p = 1, mask = "1", act = "b" }, "roll", "no second decision before the roll")
	eq(err(F.Bank(g, 1)), "roll", "nor a bank from the page")
	eq(Ok(Roll(1, 5, 2, 3, 4)), nil)
	eq(Ok("K1:1:b"), nil)
	eq(g.scores[1], 250); eq(g.current, 2); eq(g.last.how, "bank"); eq(g.last.points, 250)
	eq(codes(g), ("R1:6:31337 K1:35:r R1:4:%d K1:1:b"):format(R(5, 2, 3, 4)))
	eq(g.step, 4)
	-- each link is the SHA-256 of the one before and the code (the design), from the head line
	eq(chains[0], Hex8(g.head))
	for i = 1, 4 do
		eq(chains[i], Hex8(chains[i - 1] .. "|" .. g.events[i]), "link " .. i)
		eq(F.Chain(chains[i - 1], g.events[i]), chains[i])
		eq(F.ChainAt(g, i), chains[i])
	end
	eq(F.ChainAt(g, 0), chains[0]); eq(F.ChainAt(g), g.chain)
	eq(F.ChainAt(g, 5), nil); eq(F.ChainAt(g, -1), nil); eq(F.ChainAt(g, 1.5), nil)
	eq(F.Chain(nil, "V"), nil); eq(F.Chain("x", nil), nil)
end)

-- W3: the decision and the roll line travel different paths. One witness sees the decision
-- first, the other the roll; both must write the same codes in logical order.
test("1.2 Farkle: a roll that overtakes its decision is held, then applied after it: equal chains on every client (W3)", function()
	local fields = { target = 2000, first = 1, id = "w3" }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	local first = Roll(1, 5, 3, 1, 2, 1, 5)
	local keep = { t = "K", p = 1, mask = "35", act = "r" }
	local second = Roll(1, 1, 1, 1, 4)
	-- x in the order sent
	assert(F.Apply(x, first)); assert(F.Apply(x, keep)); assert(F.Apply(x, second))
	-- y sees the second roll before the decision
	assert(F.Apply(y, first))
	local step = y.step
	local ok, note = F.Apply(y, second)
	eq(ok, true); eq(note, "held"); eq(y.step, step, "held, not written")
	eq(#y.queue, 1); eq(y.queue[1].value, second.value)
	eq(err(F.Keep(y, 1, { 3 })), "held", "only the decision itself settles a held roll")
	eq(select(2, F.Apply(y, keep)), nil)
	eq(#y.queue, 0)
	eq(codes(y), codes(x)); eq(y.chain, x.chain); eq(F.Hash(y), F.Hash(x))
	eq(y.turn.phase, "keep"); eq(list(y.turn.dice), "1 1 1 4"); eq(y.turn.points, 200)
	-- A held wrong count is discarded once the decision says how many dice he has left.
	local z = assert(F.New(fields))
	assert(F.Apply(z, first))
	assert(F.Apply(z, Roll(1, 1, 1, 1, 4, 2, 2)))
	ok, note = F.Apply(z, keep)
	eq(ok, true); eq(note, nil)
	eq(codes(z), "R1:6:31337 K1:35:r")
	eq(z.current, 1); eq(z.last, nil); eq(z.turn.points, 200); eq(z.turn.phase, "roll")
end)

-- W4: a witness that sees a roll before the player's bank reads the bank as rolling on. A
-- witness that saw the bank first ended the turn and ignores the roll: the chains then differ,
-- which the table settles (the design). The rules only make each side's reading
-- deterministic.
test("1.2 Farkle: a roll seen before the bank stands, and the bank reads as rolling on (W4)", function()
	local fields = { target = 2000, first = 1 }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	local first = Roll(1, 5, 3, 1, 2, 1, 5)
	local bank = { t = "K", p = 1, mask = "35", act = "b" }
	local late = Roll(1, 2, 3, 4, 6)          -- nothing scores: he rolled, saw it, and "banked"
	for _, g in ipairs({ x, y }) do assert(F.Apply(g, first)) end
	-- x saw the roll first
	eq(select(2, F.Apply(x, late)), "held")
	local ok, note = F.Apply(x, bank)
	eq(ok, true); eq(note, "stands")
	eq(codes(x), ("R1:6:31337 K1:35:r R1:4:%d"):format(late.value), "written as keep and roll")
	eq(x.scores[1], 0); eq(x.last.how, "farkle"); eq(x.last.lost, 200); eq(x.current, 2)
	-- y saw the bank first: the turn is over, and the roll is not his to make
	assert(F.Apply(y, bank))
	eq(y.scores[1], 200); eq(y.current, 2)
	eq(err(F.Apply(y, late)), "turn")
	assert(x.chain ~= y.chain, "the two readings diverge, and the chain shows it")
	eq(F.ChainAt(x, 1), F.ChainAt(y, 1), "up to the decision they agree")
	-- A wrong-count roll cannot prevent the valid bank.
	local z = assert(F.New(fields))
	assert(F.Apply(z, first))
	assert(F.Apply(z, Roll(1, 1, 1, 1, 1, 1, 1)))
	ok, note = F.Apply(z, bank)
	eq(ok, true); eq(note, nil)
	eq(codes(z), "R1:6:31337 K1:35:b")
	eq(z.scores[1], 200); eq(z.last.how, "bank")
end)

-- W3 across a turn: every table message is whispered to each participant in turn (the design),
-- one message every 1.2 s (the design). The guest can see the host's bank and roll while the same bank
-- is still on its way to the arbiter, whose client then sees the guest's roll line first.
test("1.2 Farkle: the next player's roll that overtakes the bank is held for his turn: three clients, one chain", function()
	local fields = { target = 2000, id = "x3", players = { A, B }, first = 1, terms = "a|1000|Marda Vell-Realm" }
	local host, guest, arbiter = assert(F.New(fields)), assert(F.New(fields)), assert(F.New(fields))
	local first = Roll(1, 5, 3, 1, 2, 1, 5)
	local bank = { t = "K", p = 1, mask = "35", act = "b" }
	local answer = Roll(2, 1, 1, 1, 2, 3, 4)       -- the guest's first roll, once he saw the bank
	for _, g in ipairs({ host, guest, arbiter }) do assert(F.Apply(g, first)) end
	-- the host (his own bank) and the guest (whispered first) see the bank, then the roll line
	for _, g in ipairs({ host, guest }) do
		assert(F.Apply(g, bank))
		eq(select(2, F.Apply(g, answer)), nil, "his turn: the roll counts at once")
	end
	-- the arbiter sees the roll line before the bank reaches him
	local step, chain = arbiter.step, arbiter.chain
	local ok, note = F.Apply(arbiter, answer)
	eq(ok, true); eq(note, "held")
	eq(arbiter.step, step, "held, not written"); eq(arbiter.chain, chain)
	eq(arbiter.current, 1); eq(arbiter.turn.phase, "keep"); eq(arbiter.ahead[1].value, answer.value)
	ok, note = F.Apply(arbiter, bank)
	eq(ok, true); eq(note, nil)
	eq(#arbiter.ahead, 0)
	eq(codes(arbiter), ("R1:6:31337 K1:35:b R2:6:%d"):format(answer.value), "the roll written after the bank")
	for _, g in ipairs({ host, guest }) do
		eq(codes(arbiter), codes(g)); eq(arbiter.chain, g.chain); eq(F.Hash(arbiter), F.Hash(g))
	end
	eq(arbiter.scores[1], 200); eq(arbiter.current, 2); eq(arbiter.turn.phase, "keep")
	eq(list(arbiter.turn.dice), "1 1 1 2 3 4")
	-- and the game goes on the same on all three
	for _, g in ipairs({ host, guest, arbiter }) do assert(F.Apply(g, "K2:123:b")) end
	eq(arbiter.chain, host.chain); eq(arbiter.chain, guest.chain)
	eq(arbiter.scores[2], 1000); eq(arbiter.current, 1)
end)

-- In direct mode the waiting player claims the timeout (KT) and then rolls; the absent player's
-- client can see that roll before the claim. A held roll that farkles passes the turn at once.
test("1.2 Farkle: a roll that overtakes a timeout claim is held too, and a held Farkle hands the turn back", function()
	local fields = { target = 2000, first = 1 }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	local answer = Roll(2, 5, 2, 3, 4, 6, 6)
	-- x hears the claim first; y sees the claimant's roll first
	assert(F.Apply(x, "T1")); assert(F.Apply(x, answer))
	eq(select(2, F.Apply(y, answer)), "held")
	assert(F.Apply(y, "T1"))
	eq(codes(y), codes(x)); eq(y.chain, x.chain)
	eq(y.current, 2); eq(y.turn.phase, "keep"); eq(y.timeouts[1], 1)
	-- he banks 50; seat 1's next roll farkles, and y saw it before the bank
	local bust = Roll(1, 2, 2, 3, 3, 4, 6)
	assert(F.Apply(x, "K2:1:b")); assert(F.Apply(x, bust))
	eq(select(2, F.Apply(y, bust)), "held")
	assert(F.Apply(y, "K2:1:b"))
	eq(codes(y), codes(x)); eq(y.chain, x.chain); eq(F.Hash(y), F.Hash(x))
	eq(y.current, 2, "the held roll farkled: the turn is back with seat 2")
	eq(y.last.who, 1); eq(y.last.how, "farkle"); eq(y.turns[1], 2); eq(y.scores[2], 50)
	eq(y.timeouts[1], 0, "a Farkle is a turn played")
end)

test("1.2 Farkle: the waiting player's lines start with a roll of six; later ones wait behind it, the rest are refused, and the game's end drops them", function()
	local g = Game({ players = { A, B } })
	assert(F.Apply(g, Roll(1, 5, 3, 1, 2, 1, 5)))
	local function No(ev, want, msg)
		local step, chain, held = g.step, g.chain, #g.ahead
		eq(err(F.Apply(g, ev)), want, msg)
		eq(g.step, step, msg); eq(g.chain, chain, msg); eq(g.current, 1, msg); eq(#g.ahead, held, msg)
		eq(g.turn.phase, "keep", msg)
	end
	No(Roll(2, 1), "turn", "a /roll 6 typed while waiting costs him nothing")
	No(Roll(2, 1, 1, 1, 1, 1), "turn", "no turn starts with five dice")
	No({ t = "R", p = 2, k = 6, value = 46657 }, "range")
	No({ t = "R", p = 2, k = 6, value = 0 }, "range")
	No({ t = "K", p = 2, mask = "1", act = "r" }, "turn", "only a roll is held, never a decision")
	No({ t = "T", p = 2 }, "turn")
	No({ t = "F", p = 2 }, "event", "live penalties are refused, even for the waiting seat")
	eq(err(F.Roll(g, B, 46656)), "turn", "the page's moves stay in turn")
	eq(#g.ahead, 0)
	-- the first roll of six is held, relay mark and all; his later lines wait behind it
	local held = R(1, 1, 1, 2, 3, 4)
	eq(select(2, F.Apply(g, { t = "R", p = B, k = 6, value = held, relayed = true })), "held")
	eq(select(2, F.Apply(g, Roll(2, 6, 6, 6, 6, 6, 6))), "held", "a second roll waits behind the first: every roll counts")
	eq(select(2, F.Apply(g, Roll(2, 1))), "held")
	eq(#g.ahead, 3); eq(g.ahead[1].value, held)
	-- the player to act goes on meanwhile; the held lines wait for the end of his turn
	assert(F.Apply(g, "K1:35:r"))
	assert(F.Apply(g, Roll(1, 5, 2, 3, 4)))
	eq(g.ahead[1].value, held, "still held while his turn goes on")
	assert(F.Apply(g, "K1:1:b"))
	eq(#g.ahead, 0)
	eq(g.events[#g.events], ("R2:6:%d*"):format(held), "written as the first roll of seat 2's turn")
	eq(g.current, 2); eq(g.turn.phase, "keep"); eq(list(g.turn.dice), "1 1 1 2 3 4")
	eq(#g.queue, 2, "his other two rolls wait for his decisions")
	-- He keeps the three 1s: both held wrong counts are discarded, without consuming his turn.
	local ok, note = F.Apply(g, "K2:123:r")
	eq(ok, true); eq(note, nil)
	eq(g.events[#g.events], "K2:123:r"); eq(g.current, 2); eq(g.turn.points, 1000); eq(#g.queue, 0); eq(#g.ahead, 0)
	-- a turn that ends the game drops the held roll: every client writes the same (nothing)
	local x, y = Game(), Game()
	local late = Roll(2, 1, 1, 1, 5, 5, 5)
	for _, h in ipairs({ x, y }) do
		assert(F.Apply(h, Roll(1, 1, 1, 1, 1, 5, 5))) -- 2,100: the bank will end the game
	end
	eq(select(2, F.Apply(x, late)), "held")
	assert(F.Apply(x, "K1:123456:b"))
	eq(x.over, true); eq(x.winner, 1); eq(#x.ahead, 0)
	assert(F.Apply(y, "K1:123456:b"))
	eq(err(F.Apply(y, late)), "over")
	eq(codes(x), codes(y)); eq(x.chain, y.chain)
	-- and so do a concession and a void
	for _, finish in ipairs({ function(h) return F.Concede(h, 2) end, function(h) return F.Void(h) end }) do
		local h = Game()
		assert(F.Apply(h, Roll(1, 5, 3, 1, 2, 1, 5)))
		eq(select(2, F.Apply(h, Roll(2, 1, 1, 1, 2, 3, 4))), "held")
		assert(finish(h))
		eq(h.over, true); eq(#h.ahead, 0)
	end
end)

test("1.2 Farkle: a roll of the wrong number of dice is refused without writing F", function()
	local g = Game()
	assert(F.Apply(g, Roll(1, 5, 3, 1, 2, 1, 5)))
	assert(F.Apply(g, "K1:35:r"))
	local ok, note = F.Apply(g, Roll(1, 1, 1, 1, 1, 1, 1))
	eq(ok, nil); eq(note, "count")
	eq(g.events[#g.events], "K1:35:r"); eq(g.scores[1], 0); eq(g.turn.points, 200); eq(g.current, 1)
	eq(g.timeouts[1], 0)
	-- the first roll of a turn is six dice
	local first = Game({ first = 2 })
	ok, note = F.Apply(first, Roll(2, 1, 1, 1))
	eq(ok, nil); eq(note, "count"); eq(first.current, 2)
	eq(err(F.Apply(g, "F1")), "event"); eq(g.current, 1); eq(g.last, nil)
end)

test("1.2 Farkle: timeouts as events: the third in a row is written A, and an early A is refused", function()
	local fields = { target = 2000, first = 1 }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	local bust2 = Roll(2, 2, 2, 3, 3, 4, 6)
	for _ = 1, 2 do
		eq(err(F.Apply(x, "A1")), "count", "not his third")
		assert(F.Apply(x, "T1")); assert(F.Apply(x, bust2))
		assert(F.Apply(y, "T1")); assert(F.Apply(y, bust2))
	end
	eq(err(F.Apply(x, "A2")), "turn")
	-- one witness hears the timeout claim, the other the forfeit claim: the same code
	assert(F.Apply(x, "T1"))
	assert(F.Apply(y, "A1"))
	eq(x.events[#x.events], "A1"); eq(codes(x), codes(y)); eq(x.chain, y.chain)
	eq(x.over, true); eq(x.winner, 2); eq(x.reason, "forfeit"); eq(y.reason, "forfeit")
	-- a timeout drops a held roll with the turn
	local g = assert(F.New(fields))
	assert(F.Apply(g, Roll(1, 5, 3, 1, 2, 1, 5)))
	eq(select(2, F.Apply(g, Roll(1, 1, 1, 1, 1))), "held")
	assert(F.Apply(g, "T1"))
	eq(#g.queue, 0); eq(#g.ahead, 0, "five dice start no turn: dropped")
	eq(g.current, 2); eq(g.last.how, "timeout"); eq(g.last.lost, 0)
	eq(err(F.Apply(g, "K1:35:r")), "turn", "his decision after the claim is refused")
end)

test("1.2 Farkle: event codes: one spelling for each event, read back as the same event", function()
	local rows = {
		{ { t = "O", p = 1, value = 57 }, "O1:57" },
		{ { t = "O", p = 2, value = 100, relayed = true }, "O2:100*" },
		{ { t = "R", p = 1, k = 6, value = 31337 }, "R1:6:31337" },
		{ { t = "R", p = 2, k = 1, value = 6, relayed = true }, "R2:1:6*" },
		{ { t = "K", p = 1, mask = { 6, 1, 3 }, act = "r" }, "K1:136:r" },
		{ { t = "K", p = 2, mask = "5", act = "b" }, "K2:5:b" },
		{ { t = "F", p = 1 }, "F1" }, { { t = "T", p = 2 }, "T2" }, { { t = "C", p = 1 }, "C1" },
		{ { t = "A", p = 2 }, "A2" }, { { t = "V" }, "V" },
		{ { t = "K", p = 2, mask = "15", act = "b", lvl = 3 }, "K2:15:b:3" },
		{ { t = "K", p = 1, mask = "123456", act = "r", lvl = 0 }, "K1:123456:r:0" },
		{ { t = "H", p = 1, value = 33 }, "H1:33" }, { { t = "H", p = 2, value = 100, relayed = true }, "H2:100*" },
		{ { t = "L", p = 2, lvl = 2 }, "L2:2" }, { { t = "L", p = 1, lvl = 0 }, "L1:0" },
	}
	for _, r in ipairs(rows) do
		eq(F.Code(r[1]), r[2])
		local ev = F.Event(r[2])
		eq(F.Code(ev), r[2], "read back: " .. r[2])
		eq(ev.t, r[1].t)
	end
	eq(F.Event("R1:6:31337*").relayed, true)
	eq(F.Event("R1:6:31337").relayed, nil)
	eq(F.Event("K1:136:r").mask, "136")
	local bad = {
		"O1:0", "O1:101", "O1:050", "O1:", "O3:5", "R1:6:0", "R1:6:46657", "R1:7:1", "R1:2:37",
		"R1:6:031337", "R1:6:5**", "R1:6", "K1:31:r", "K1:11:r", "K1:7:r", "K1::r", "K1:1:x",
		"K1:1:r*", "K3:1:r", "T0", "T1x", "T1*", "V1", "V*", "", "X1", "t1", " T1", "R1:6:11111111111111",
		"K1:1:r:4", "K1:1:r:", "K1:1:r:03", "K1:1:r:3*", "H1:0", "H1:101", "H1:050", "H1:", "H3:5",
		"H1:5**", "L1:4", "L1:", "L1:1*", "L1:01", "L3:1", "K1:123456:r:3x",
	}
	for _, code in ipairs(bad) do eq(F.Event(code), nil, code) end
	eq(F.Event(nil), nil); eq(F.Event(5), nil)
	local badEvents = {
		{ t = "K", p = 1, mask = {}, act = "r" }, { t = "R", p = 3, k = 1, value = 1 }, { t = "O", p = 1 },
		{ t = "R", p = 1, k = 2, value = 37 }, { t = "Q", p = 1 }, { p = 1 }, { t = "T" },
		{ t = "K", p = 1, mask = "1", act = "r", lvl = 4 }, { t = "K", p = 1, mask = "1", act = "r", lvl = 1.5 },
		{ t = "H", p = 1, value = 0 }, { t = "H", p = 1 }, { t = "L", p = 1 }, { t = "L", p = 1, lvl = -1 },
	}
	for i, ev in ipairs(badEvents) do eq(F.Code(ev), nil, "event " .. i) end
	eq(F.Code("V"), nil)
end)

---------------------------------------------------------------------------
-- The transcript, its hash and a replay
---------------------------------------------------------------------------

test("1.2 Farkle: the transcript is the head line and the codes; its hash is the first 8 hex digits of its SHA-256", function()
	local g = assert(F.New({ target = 5000, id = "k7x2q9", players = { A, B }, terms = "a|2000|Marda Vell-Realm" }))
	assert(F.Apply(g, "O1:12")); assert(F.Apply(g, "O2:88"))
	assert(F.Apply(g, Roll(2, 1, 1, 1, 5, 5, 5)))
	assert(F.Apply(g, "K2:123456:r"))
	assert(F.Apply(g, Roll(2, 2, 2, 3, 3, 4, 6)))
	eq(F.Transcript(g), table.concat({
		"farkle1|k7x2q9|5000|thessaly ironbrand-realm|corvin ashgrove-realm||a|2000|Marda Vell-Realm",
		"O1:12", "O2:88", "R2:6:" .. R(1, 1, 1, 5, 5, 5), "K2:123456:r", "R2:6:" .. R(2, 2, 3, 3, 4, 6),
	}, "\n"))
	eq(F.Hash(g), Hex8(F.Transcript(g)))
	eq(#F.Hash(g), 8)
	eq(g.last.how, "farkle"); eq(g.last.lost, 1500, "two threes of a kind (KCD2; two triplets were 2,500)")
	local before = F.Hash(g)
	assert(F.Apply(g, "C1"))
	assert(F.Hash(g) ~= before, "every event changes the hash")
	eq(F.Transcript(F.New({ target = 2000, first = 2 })), "farkle1||2000|||2|", "no events: the head line alone")
end)

-- The table checks a message's chain at its step (KK, KT, KQ). WoW runs PUC Lua, several times
-- slower than LuaJIT, so recomputing the chain from the head at every check would grow with the
-- game; ChainAt looks the link up instead. The SHA-256 calls are counted through a Sign.lua
-- that forwards to the real one.
test("1.2 Farkle: ChainAt looks the chain up at any step: no hashing, the same links", function()
	local calls = 0
	local counted = { Sign = { SHA256 = function(text) calls = calls + 1; return ns.Sign.SHA256(text) end } }
	assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", counted)
	local C = counted.FarkleRules
	local g = assert(C.New({ target = 10000, first = 1, id = "ca" }))
	local roll = Server(424242)
	while g.step < 120 and not g.over do
		local who, phase, left = C.Expect(g)
		if phase == "keep" then
			local _, pick = C.Best(g.turn.dice)
			assert(C.Keep(g, who, pick))
		elseif phase == "decide" and g.turn.points >= 300 then
			assert(C.Bank(g, who))
		else
			assert(C.Roll(g, who, roll(C.RANGES[left])))
		end
	end
	local steps = g.step
	assert(steps >= 100, "a long game")
	local before = calls
	for step = 0, steps do
		local link = C.ChainAt(g, step)
		eq(#link, 8)
		if step > 0 then eq(link, F.Chain(C.ChainAt(g, step - 1), g.events[step]), "link " .. step) end
	end
	eq(C.ChainAt(g), g.chain)
	eq(calls, before, "no SHA-256 for a lookup")
	eq(C.ChainAt(g, 0), Hex8(g.head))
	eq(C.ChainAt(g, steps + 1), nil)
end)

-- A client that reloaded takes the rolls it missed from another participant (the design, KQ/KR):
-- they are marked relayed in its own record, and it must still hash the same game.
test("1.2 Farkle: a relayed roll is marked in the events and left out of the chain, the transcript and the hash", function()
	local fields = { target = 2000, first = 1, id = "rl" }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	local r1 = Roll(1, 5, 3, 1, 2, 1, 5)
	assert(F.Apply(x, r1))
	local relayed = { t = "R", p = 1, k = 6, value = r1.value, relayed = true }
	assert(F.Apply(y, relayed))
	eq(y.events[1], "R1:6:31337*"); eq(x.events[1], "R1:6:31337")
	eq(y.chain, x.chain); eq(F.Transcript(y), F.Transcript(x)); eq(F.Hash(y), F.Hash(x))
	-- a held roll keeps its mark until it is written
	assert(F.Apply(x, "K1:35:r")); assert(F.Apply(y, "R1:4:1*")); assert(F.Apply(y, "K1:35:r"))
	assert(F.Apply(x, "R1:4:1"))
	eq(y.events[3], "R1:4:1*"); eq(y.chain, x.chain); eq(F.Hash(y), F.Hash(x))
	-- the same for an opening roll
	local o1, o2 = assert(F.New({ target = 2000 })), assert(F.New({ target = 2000 }))
	assert(F.Apply(o1, "O1:5")); assert(F.Apply(o2, "O1:5*"))
	eq(o2.events[1], "O1:5*"); eq(o2.chain, o1.chain)
end)

test("1.2 Farkle: Replay rebuilds a game from its fields and codes, and names the first code it refuses", function()
	local fields = { target = 2000, id = "rp", players = { A, B } }
	local g = assert(F.New(fields))
	for _, code in ipairs({ "O1:30", "O2:20", "R1:6:31337*", "K1:35:r", "R1:4:1", "K1:123:b", "T2", "R1:6:46656", "K1:123456:b" }) do
		assert(F.Apply(g, code), code)
	end
	eq(g.scores[1], 1200 + 4800, "six 6s are 600 x 8 (KCD2; the old table's 3,000)")
	local again = assert(F.Replay(fields, g.events))
	eq(again.chain, g.chain); eq(F.Hash(again), F.Hash(g)); eq(codes(again), codes(g))
	eq(again.scores[1], g.scores[1]); eq(again.current, g.current); eq(again.over, g.over)
	eq(again.timeouts[2], 1)
	-- a transcript is in logical order: a roll it would have to hold is refused
	local game, why, at = F.Replay(fields, { "O1:30", "O2:20", "R1:6:31337", "R1:4:1", "K1:35:r" })
	eq(game, nil); eq(why, "held"); eq(at, 4)
	game, why, at = F.Replay(fields, { "O1:30", "O2:20", "R2:6:1" })
	eq(game, nil); eq(why, "held"); eq(at, 3, "the other player's roll before the turn passed")
	game, why, at = F.Replay(fields, { "O1:30", "O2:20", "R2:5:1" })
	eq(game, nil); eq(why, "turn"); eq(at, 3)
	game, why, at = F.Replay(fields, { "O1:30", "bogus" })
	eq(game, nil); eq(why, "event"); eq(at, 2)
	game, why, at = F.Replay(fields, { "O1:30", 7 })
	eq(why, "event"); eq(at, 2)
	eq(err(F.Replay(fields, "O1:30")), "codes")
	eq(err(F.Replay({ target = 3000 }, {})), "target")
	-- the head is part of it: the same codes under other terms hash differently
	local other = assert(F.Replay({ target = 2000, id = "rq", players = { A, B } }, g.events))
	assert(F.Hash(other) ~= F.Hash(g))
end)

---------------------------------------------------------------------------
-- The House (practice)
---------------------------------------------------------------------------

-- The design: keep Best's dice (the highest-scoring set; on a tie, the lower positions: with
-- KCD2's runs that is no longer every scoring die, as 2-3-4-5-6-6 keeps one 6); bank at 1,000
-- or more, at 300 or more with 2 dice or fewer left, at 550 or more with 3 or fewer, or
-- whenever banking wins.
test("1.2 Farkle: the House keeps Best's dice (a tie: the lower positions) and banks at 1,000, at 550 with 3 dice left, at 300 with 2", function()
	local function Move(...)
		local g = Game()
		assert(F.Roll(g, 1, R(...)))
		local pick, act = F.HouseMove(g)
		return pick and list(pick), act
	end
	-- KCD2 (2026-09-30): four 1s are 2,000; 5 2 3 4 6 6 and 1 5 2 3 4 4 held a run of five, so
	-- the rows for 50 and 150 use 5 2 3 3 6 6 and 1 5 2 3 6 6; 1 1 5 5 6 6 is no three pairs
	-- but 300 for the 1s and 5s, with 2 dice left; and the runs are new rows
	local rows = {
		{ { 1, 1, 1, 2, 3, 4 }, "1 2 3", "b", "1,000" },
		{ { 1, 1, 1, 1, 2, 3 }, "1 2 3 4", "b", "2,000: four 1s, every one kept" },
		{ { 5, 2, 3, 3, 6, 6 }, "1", "r", "50, five dice left" },
		{ { 1, 5, 2, 3, 6, 6 }, "1 2", "r", "150, four left" },
		{ { 6, 6, 6, 2, 3, 4 }, "1 2 3", "b", "600 with 3 left" },
		{ { 5, 5, 5, 2, 3, 4 }, "1 2 3", "r", "500 with 3 left: under 550" },
		{ { 3, 3, 3, 2, 4, 6 }, "1 2 3", "r", "300 with 3 left: 300 needs 2 or fewer" },
		{ { 4, 4, 4, 1, 2, 3 }, "1 2 3 4", "b", "500 with 2 left" },
		{ { 2, 2, 2, 5, 3, 4 }, "1 2 3 4", "r", "250 with 2 left" },
		{ { 1, 1, 5, 5, 6, 6 }, "1 2 3 4", "b", "300 with 2 left: the 6s stay (no three pairs)" },
		{ { 5, 2, 3, 4, 6, 6 }, "1 2 3 4 5", "b", "the run 2-6: 750 with 1 left, the second 6 stays" },
		{ { 1, 2, 3, 4, 5, 5 }, "1 2 3 4 5 6", "r", "the run 1-5 and a 5: 550, hot dice, six to roll" },
		{ { 1, 2, 3, 4, 5, 6 }, "1 2 3 4 5 6", "b", "the whole run: 1,500" },
	}
	for _, r in ipairs(rows) do
		local pick, act = Move((unpack or table.unpack)(r[1]))
		eq(pick, r[2], r[4]); eq(act, r[3], r[4])
	end
	-- hot dice with fewer than 1,000: six dice to roll, so it rolls on
	local g = Game()
	assert(F.Roll(g, 1, R(5, 5, 5, 2, 3, 4)))
	assert(F.Keep(g, 1, { 1, 2, 3 }))
	assert(F.Roll(g, 1, R(1, 5, 5)))
	local pick, act = F.HouseMove(g)
	eq(list(pick), "1 2 3"); eq(act, "r", "700 and hot dice")
	-- in "roll" it rolls; in "decide" (dice set aside by the page) it only says what to do
	g = Game()
	eq(select(2, F.HouseMove(g)), "r"); eq(F.HouseMove(g), nil)
	assert(F.Roll(g, 1, R(1, 1, 1, 2, 3, 4)))
	assert(F.Keep(g, 1, { 1 }))
	pick, act = F.HouseMove(g)
	eq(pick, nil); eq(act, "r", "100 with five left")
end)

-- Each threshold met exactly, with a count of dice left that no other row covers: 300 needs 2
-- or fewer, 550 exactly 3 (under 1,000; 2 would meet the 300 row), 1,000 four or more.
test("1.2 Farkle: the House banks at exactly 300 with 2 dice left, 550 with 3 and 1,000 with 6", function()
	-- 300 with 2 left: 1 1 5 5 in one roll
	local g = Game()
	assert(F.Roll(g, 1, R(1, 1, 5, 5, 2, 3)))
	local pick, act = F.HouseMove(g)
	eq(list(pick), "1 2 3 4"); eq(act, "b", "300 with 2 left")
	-- 1,000 with six to roll: 600, then 400 with the last three (hot dice)
	g = Game()
	assert(F.Roll(g, 1, R(6, 6, 6, 2, 3, 4)))
	assert(F.Keep(g, 1, { 1, 2, 3 }))
	assert(F.Roll(g, 1, R(4, 4, 4)))
	pick, act = F.HouseMove(g)
	eq(list(pick), "1 2 3"); eq(act, "b", "1,000 and hot dice")
	-- 550 with 3 left: 350 over six dice (hot dice), then 1 5 5 of a new six. (KCD2: the rolls
	-- of one 5 and the new six hold no run of five; 5 2 3 4 6 6, 5 2 3 4 6 and 1 5 5 2 3 4 did.)
	g = Game()
	for _, roll in ipairs({ R(5, 2, 3, 3, 6, 6), R(5, 2, 3, 3, 6), R(5, 2, 3, 4) }) do
		assert(F.Roll(g, 1, roll))
		eq(select(2, F.HouseMove(g)), "r")
		assert(F.Keep(g, 1, { 1 }))
	end
	assert(F.Roll(g, 1, R(2, 2, 2)))
	assert(F.Keep(g, 1, { 1, 2, 3 }))
	eq(g.turn.points, 350); eq(g.turn.left, 6); eq(F.HotDice(g.turn), true)
	assert(F.Roll(g, 1, R(1, 5, 5, 2, 3, 6)))
	pick, act = F.HouseMove(g)
	eq(list(pick), "1 2 3"); eq(act, "b", "550 with 3 left")
	-- the same 550 with 4 left rolls on; so does 900 with six
	g = Game()
	for _, roll in ipairs({ R(5, 2, 3, 3, 6, 6), R(5, 2, 3, 3, 6), R(5, 2, 3, 4) }) do
		assert(F.Roll(g, 1, roll)); assert(F.Keep(g, 1, { 1 }))
	end
	assert(F.Roll(g, 1, R(2, 2, 2))); assert(F.Keep(g, 1, { 1, 2, 3 }))
	assert(F.Roll(g, 1, R(1, 1, 3, 4, 6, 6)))
	pick, act = F.HouseMove(g)
	eq(list(pick), "1 2"); eq(act, "r", "550 with 4 left")
	g = Game()
	assert(F.Roll(g, 1, R(6, 6, 6, 2, 3, 4))); assert(F.Keep(g, 1, { 1, 2, 3 }))
	assert(F.Roll(g, 1, R(3, 3, 3)))
	pick, act = F.HouseMove(g)
	eq(list(pick), "1 2 3"); eq(act, "r", "900 and hot dice")
end)

test("1.2 Farkle: the House cannot answer a target win, and banks to win at the cap", function()
	local g = Game()
	Play(g, 1, 1, 1, 1, 1, 5, 5)
	eq(F.HouseMove(g), nil)
	eq(err(F.Roll(g, 2, R(1, 1, 1, 2, 3, 4))), "over")
	local act
	-- the turn that completes the cap
	g = Game()
	for _ = 1, 11 do Bust(g, 1); Bust(g, 2) end
	Play(g, 1, 1, 2, 3, 4, 6, 6)           -- 100 on the twelfth turn
	assert(F.Roll(g, 2, R(5, 2, 3, 3, 6, 6)))
	_, act = F.HouseMove(g)
	eq(act, "r", "50 would lose at the cap")
	g = Game()
	for _ = 1, 11 do Bust(g, 1); Bust(g, 2) end
	Play(g, 1, 5, 2, 3, 3, 6, 6)           -- 50
	assert(F.Roll(g, 2, R(1, 2, 3, 4, 6, 6)))
	_, act = F.HouseMove(g)
	eq(act, "b", "100 against 50 wins at the cap")
	-- level is no win: it rolls on for the lead
	g = Game()
	for _ = 1, 11 do Bust(g, 1); Bust(g, 2) end
	Play(g, 1, 1, 2, 3, 4, 6, 6)
	assert(F.Roll(g, 2, R(1, 2, 3, 4, 6, 6)))
	_, act = F.HouseMove(g)
	eq(act, "r", "100 all")
end)

-- Practice and the table in one: two Houses play through Apply, a second client sees every roll
-- before its decision (W3), a third sees every next player's first roll before the bank that
-- passed him the dice, and a replay of the codes rebuilds the same game.
test("1.2 Farkle: seeded House games through events all finish, equal on clients that saw rolls early, and replay", function()
	local roll = Server(19770101)
	local finished, crossed = 0, 0
	for n = 1, 60 do
		local fields = { target = F.TARGETS[n % 3 + 1], id = "h" .. n, players = { A, B } }
		local x, y, z = assert(F.New(fields)), assert(F.New(fields)), assert(F.New(fields))
		local held
		local steps = 0
		while not x.over do
			steps = steps + 1
			assert(steps < 5000, "game " .. n .. " never ended")
			local who, phase, left = F.Expect(x)
			local ev
			if phase == "open" then
				ev = { t = "O", p = who == 0 and 1 or who, value = roll(100) }
			elseif phase == "keep" then
				local pick, act = F.HouseMove(x)
				ev = { t = "K", p = who, mask = pick, act = act }
			else
				ev = { t = "R", p = who, k = left, value = roll(F.RANGES[left]) }
			end
			assert(F.Apply(x, ev))
			if ev.t == "K" and ev.act == "r" and not x.over and F.Expect(x) == who then
				-- y gets each roll after a decision to roll on ahead of that decision
				local _, _, k = F.Expect(x)
				held = { t = "R", p = who, k = k, value = roll(F.RANGES[k]) }
				eq(select(2, F.Apply(y, held)), "held")
				assert(F.Apply(y, ev))
				assert(F.Apply(z, ev)); assert(F.Apply(z, held))
				assert(F.Apply(x, held))
			elseif ev.t == "K" and ev.act == "b" and not x.over then
				-- z gets the next player's first roll ahead of the bank that passed him the dice
				local answer = { t = "R", p = x.current, k = 6, value = roll(F.RANGES[6]) }
				eq(select(2, F.Apply(z, answer)), "held")
				assert(F.Apply(z, ev))
				assert(F.Apply(y, ev)); assert(F.Apply(y, answer))
				assert(F.Apply(x, answer))
				crossed = crossed + 1
			else
				assert(F.Apply(y, ev)); assert(F.Apply(z, ev))
			end
			eq(y.chain, x.chain, "game " .. n .. " step " .. x.step)
			eq(z.chain, x.chain, "game " .. n .. " step " .. x.step)
		end
		eq(y.over, true); eq(y.winner, x.winner); eq(F.Hash(y), F.Hash(x))
		eq(z.over, true); eq(z.winner, x.winner); eq(F.Hash(z), F.Hash(x)); eq(codes(z), codes(x))
		assert(x.winner == 1 or x.winner == 2)
		assert(x.scores[x.winner] > x.scores[3 - x.winner], "game " .. n .. ": the winner is ahead")
		local again = assert(F.Replay(fields, x.events))
		eq(F.Hash(again), F.Hash(x)); eq(again.winner, x.winner); eq(again.scores[1], x.scores[1])
		finished = finished + 1
	end
	eq(finished, 60)
	assert(crossed > 300, "banks crossed by the next roll: " .. crossed)
end)

---------------------------------------------------------------------------
-- Bone Throw's hiccup: the drunk rule (the design)
---------------------------------------------------------------------------

-- A hiccup table where seat 2 has banked 100 and his decision recorded seat 1 at lvl: seat 1 to
-- play his first turn.
local function Drunk(lvl, fields)
	fields = fields or {}
	fields.hiccup, fields.first = true, 2
	if fields.target == nil then fields.target = 2000 end
	local g = assert(F.New(fields))
	assert(F.Apply(g, Roll(2, 1, 2, 3, 4, 6, 6)))
	assert(F.Apply(g, ("K2:1:b:%d"):format(lvl)))
	return g
end
local BUST6 = { 2, 2, 3, 3, 4, 6 }          -- six dice, nothing scores

test("1.2 Bone Throw (the design): a hiccup table names itself in the head line; a sober one refuses levels, L and H", function()
	local g = assert(F.New({ target = 2000, first = 1, hiccup = true, id = "k7x2q9" }))
	eq(g.head, "farkle1h|k7x2q9|2000|||1|")
	eq(F.New({ target = 2000, first = 1, hiccup = false }).head, "farkle1||2000|||1|", "false is the sober table")
	eq(err(F.New({ target = 2000, hiccup = "yes" })), "hiccup")
	eq(err(F.New({ target = 2000, hiccup = 1 })), "hiccup")
	local s = Game()
	assert(F.Apply(s, Roll(1, 5, 3, 1, 2, 1, 5)))
	local step, chain = s.step, s.chain
	eq(err(F.Apply(s, "K1:35:r:3")), "sober")
	eq(err(F.Apply(s, "H1:5")), "sober")
	eq(err(F.Apply(s, "L2:3")), "sober")
	eq(err(F.Floor(s, 2, 2, 3)), "sober")
	eq(err(F.Hiccup(s, 1, 5)), "sober")
	eq(s.step, step); eq(s.chain, chain)
	eq(select(2, F.Level(s, 1)), 0); eq(select(3, F.Level(s, 1)), 0)
	-- a sober Farkle on a sober table still ends the turn at once
	assert(F.Apply(s, "K1:35:r"))
	eq(select(2, F.Apply(s, Roll(1, 2, 3, 4, 6))), nil); eq(s.current, 2)
end)

test("1.2 Bone Throw (the design): a drunk Farkle waits for his hiccup; at or under the chance it is shaken off, the points kept and the same dice thrown again", function()
	local g = Drunk(3)
	eq(g.level[1], 3); eq(g.level[2], 0, "nobody writes his own level")
	local lvl, pct, left = F.Level(g, 1)
	eq(lvl, 3); eq(pct, 33); eq(left, 2)
	assert(F.Apply(g, Roll(1, 5, 3, 1, 2, 1, 5)))
	assert(F.Apply(g, "K1:35:r"))
	local ok, note = F.Apply(g, Roll(1, 2, 3, 4, 6))
	eq(ok, true); eq(note, "hiccup")
	local who, phase, k = F.Expect(g)
	eq(who, 1); eq(phase, "hiccup"); eq(k, nil)
	eq(g.turn.points, 0); eq(g.turn.lost, 200); eq(g.current, 1)
	eq(select(2, F.HouseMove(g)), "h", "practice: the House presses HIC!")
	ok, note = F.Apply(g, "H1:33")
	eq(ok, true); eq(note, "shaken")
	who, phase, k = F.Expect(g)
	eq(phase, "roll"); eq(k, 4, "the same four dice again")
	eq(g.turn.points, 200); eq(g.shakes[1], 1)
	eq(select(3, F.Level(g, 1)), 1, "one shake-off left")
	assert(F.Apply(g, Roll(1, 1, 2, 3, 4)))
	assert(F.Apply(g, "K1:1:b"))
	eq(g.scores[1], 300); eq(g.current, 2)
	eq(codes(g), ("R2:6:%d K2:1:b:3 R1:6:31337 K1:35:r R1:4:%d H1:33 R1:4:%d K1:1:b")
		:format(R(1, 2, 3, 4, 6, 6), R(2, 3, 4, 6), R(1, 2, 3, 4)))
end)

test("1.2 Bone Throw (the design): over the chance the Farkle stands; tipsy is 10, drunk 20, smashed 33, sober none", function()
	local g = Drunk(3)
	assert(F.Apply(g, Roll(1, 5, 3, 1, 2, 1, 5))); assert(F.Apply(g, "K1:35:r"))
	eq(select(2, F.Apply(g, Roll(1, 2, 3, 4, 6))), "hiccup")
	local ok, note = F.Apply(g, "H1:34")
	eq(ok, true); eq(note, nil)
	eq(g.current, 2); eq(g.scores[1], 0); eq(g.last.how, "farkle"); eq(g.last.lost, 200)
	eq(g.shakes[1], 0); eq(g.timeouts[1], 0)
	for lvl, pct in pairs({ [1] = 10, [2] = 20, [3] = 33 }) do
		local h = Drunk(lvl)
		eq(F.HICCUP[lvl], pct)
		eq(select(2, F.Apply(h, Roll(1, unpack(BUST6)))), "hiccup")
		eq(select(2, F.Apply(h, ("H1:%d"):format(pct))), "shaken", "at the chance")
		eq(select(2, F.Apply(h, Roll(1, unpack(BUST6)))), "hiccup", "a new Farkle, a new hiccup")
		eq(select(2, F.Apply(h, ("H1:%d"):format(pct + 1))), nil, "one over")
		eq(h.current, 2)
	end
	local s = Drunk(0)
	eq(select(2, F.Apply(s, Roll(1, unpack(BUST6)))), nil, "sober: the Farkle ends the turn at once")
	eq(s.current, 2)
end)

test("1.2 Bone Throw (the design): after hot dice a shaken Farkle throws six again, and a wrong count is refused", function()
	local g = Drunk(2)
	assert(F.Apply(g, Roll(1, 1, 1, 1, 5, 5, 5)))
	assert(F.Apply(g, "K1:123456:r"))
	eq(g.turn.left, 6); eq(g.turn.points, 1500, "two threes of a kind: hot dice")
	eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), "hiccup")
	eq(select(2, F.Apply(g, "H1:20")), "shaken")
	local _, phase, left = F.Expect(g)
	eq(phase, "roll"); eq(left, 6); eq(g.turn.points, 1500)
	local ok, note = F.Apply(g, Roll(1, 1, 1, 1, 1, 1))
	eq(ok, nil); eq(note, "count", "five dice where six are due")
	eq(g.scores[1], 0); eq(g.current, 1); eq(g.turn.points, 1500); eq(g.turn.phase, "roll")
end)

test("1.2 Bone Throw (the design): while the hiccup is due a dice roll is ignored, only the first 1-100 counts, and 1-100 rolls at other times are ignored", function()
	local g = Drunk(3)
	eq(err(F.Apply(g, "H1:5")), "phase", "no Farkle yet")
	eq(err(F.Apply(g, "H2:5")), "turn", "the waiting player's 1-100")
	assert(F.Apply(g, Roll(1, unpack(BUST6))))
	local step, chain = g.step, g.chain
	eq(err(F.Apply(g, Roll(1, 1, 1, 1, 1, 1, 1))), "hiccup", "an extra roll before the hiccup")
	eq(err(F.Roll(g, 1, 1)), "hiccup")
	eq(err(F.Apply(g, "K1:1:r")), "roll")
	eq(err(F.Apply(g, { t = "H", p = 1, value = 0 })), "range"); eq(err(F.Apply(g, { t = "H", p = 1, value = 101 })), "range")
	eq(err(F.Apply(g, "H1:0")), "event", "no code spells it")
	eq(g.step, step); eq(g.chain, chain)
	eq(select(2, F.Apply(g, "H1:90")), nil)
	eq(g.current, 2)
	eq(err(F.Apply(g, "H1:1")), "turn", "a second 1-100 is ignored")
	-- the page's own move
	local h = Drunk(3)
	eq(err(F.Hiccup(h, 1, 5)), "phase")
	local dice, farkle = F.Roll(h, 1, R(unpack(BUST6)))
	eq(list(dice), "2 2 3 3 4 6"); eq(farkle, true); eq(select(2, F.Expect(h)), "hiccup")
	eq(err(F.Hiccup(h, 2, 5)), "turn"); eq(err(F.Hiccup(h, 1, 101)), "range")
	eq(F.Hiccup(h, 1, 33), true)
	F.Roll(h, 1, R(unpack(BUST6)))
	eq(F.Hiccup(h, 1, 34), false); eq(h.current, 2)
end)

test("1.2 Bone Throw (the design): a hiccup left to the clock is a Farkle, no timeout: three in a row never forfeit", function()
	local g = Drunk(3)
	for i = 1, 3 do
		eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), "hiccup", "turn " .. i)
		eq(err(F.Apply(g, "A1")), "count", "a missed hiccup is never the third timeout")
		assert(F.Apply(g, "T1"))
		eq(g.events[#g.events], "T1"); eq(g.last.how, "farkle"); eq(g.timeouts[1], 0); eq(g.over, false)
		Bust(g, 2)
	end
	eq(g.over, false); eq(g.shakes[1], 0)
	-- after two real timeouts, a missed hiccup still resets the count
	assert(F.Apply(g, "T1")); Bust(g, 2); assert(F.Apply(g, "T1")); Bust(g, 2)
	eq(g.timeouts[1], 2)
	eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), "hiccup")
	eq(err(F.Apply(g, "A1")), "count")
	assert(F.Timeout(g, 1))
	eq(g.over, false); eq(g.timeouts[1], 0); eq(g.last.how, "farkle")
end)

test("1.2 Bone Throw (the design): two shake-offs per seat per game; then a Farkle ends the turn at once", function()
	local g = Drunk(3)
	eq(F.SHAKES, 2)
	for i = 1, 2 do
		eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), "hiccup")
		eq(select(2, F.Apply(g, "H1:1")), "shaken", "shake-off " .. i)
	end
	eq(select(2, F.Level(g, 1)), 0, "no chance left this game")
	eq(select(3, F.Level(g, 1)), 0); eq(F.Level(g, 1), 3, "still smashed")
	eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), nil, "the third Farkle stands at once")
	eq(g.current, 2)
	eq(select(2, F.Level(g, 1)), 0)
	Bust(g, 2)
	eq(select(2, F.Apply(g, Roll(1, unpack(BUST6)))), nil, "and in his later turns")
	eq(g.shakes[2], 0, "the other seat keeps his own")
end)

test("1.2 Bone Throw (the design): a seat's level is written by the other seat's decisions and counts from his next turn", function()
	local g = assert(F.New({ target = 5000, first = 1, hiccup = true }))
	assert(F.Apply(g, "R1:6:31337"))
	assert(F.Apply(g, "K1:35:b:1"))
	eq(g.level[2], 1); eq(g.level[1], 0)
	assert(F.Apply(g, Roll(2, 1, 2, 3, 4, 6, 6)))
	eq(select(2, F.Level(g, 2)), 10, "locked at his first roll")
	assert(F.Apply(g, "K2:1:b"))
	eq(g.level[1], 0, "no level in the decision: nothing changes")
	assert(F.Apply(g, "R1:6:31337"))
	assert(F.Apply(g, "K1:35:b:3"))
	eq(g.events[#g.events], "K1:35:b:3"); eq(g.level[2], 3)
	eq(select(2, F.Level(g, 2)), 33)
	assert(F.Apply(g, Roll(2, 1, 2, 3, 4, 6, 6)))
	eq(g.turn.chance, 33)
	eq(err(F.Apply(g, "K2:1:b:4")), "event")
	eq(err(F.Apply(g, { t = "K", p = 2, mask = "1", act = "b", lvl = 7 })), "event")
	assert(F.Apply(g, "K2:1:b:0"))
	eq(g.level[1], 0)
	-- sobering is written the same way
	assert(F.Apply(g, "R1:6:31337")); assert(F.Apply(g, "K1:35:b:0"))
	eq(g.level[2], 0); eq(select(2, F.Level(g, 2)), 0)
end)

test("1.2 Bone Throw (the design): the arbiter's floor is written where the named turn is handed over, the same on every client, and is late once that turn has an event", function()
	local fields = { target = 5000, first = 1, hiccup = true, id = "fl" }
	local x, y, z = assert(F.New(fields)), assert(F.New(fields)), assert(F.New(fields))
	eq(select(2, F.Floor(x, 2, 2, 3)), "pending", "seat 2 smashed from his second turn")
	eq(err(F.Floor(x, 2, 2, 4)), "level"); eq(err(F.Floor(x, 2, "2", 1)), "level")
	eq(err(F.Floor(x, 3, 2, 1)), "player")
	local codes2 = { "R1:6:31337", "K1:35:b", ("R2:6:%d"):format(R(1, 2, 3, 4, 6, 6)), "K2:1:b",
		"R1:6:31337", "K1:35:b" }
	for _, c in ipairs(codes2) do
		for _, g in ipairs({ x, y, z }) do assert(F.Apply(g, c), c) end
		if c == "K2:1:b" then
			eq(x.floor[2], 0, "not in his first turn")
			eq(err(F.Apply(x, "L2:3")), "level", "an L only where that seat's turn is handed over")
		end
	end
	eq(x.events[#x.events], "L2:3", "written at the hand-over, before his first roll")
	eq(x.floor[2], 3); eq(x.level[2], 0); eq(F.Level(x, 2), 3)
	-- y gets the arbiter's message only now, before seat 2's first roll: still the same place
	eq(F.Floor(y, 2, 2, 3), true)
	eq(y.chain, x.chain); eq(codes(y), codes(x))
	eq(F.Floor(y, 2, 2, 3), true, "the same floor again writes nothing")
	eq(y.chain, x.chain)
	local roll2 = Roll(2, unpack(BUST6))
	eq(select(2, F.Apply(x, roll2)), "hiccup"); eq(select(2, F.Apply(y, roll2)), "hiccup")
	eq(x.turn.chance, 33)
	-- z hears of it after that roll: too late for this turn (its chance was fixed at the roll)
	eq(select(2, F.Apply(z, roll2)), nil); eq(z.current, 1)
	eq(err(F.Floor(z, 2, 2, 3)), "late")
	-- a transcript with the floor replays
	local again = assert(F.Replay(fields, x.events))
	eq(again.chain, x.chain); eq(again.floor[2], 3); eq(select(2, F.Expect(again)), "hiccup")
end)

-- The review's case (drunk/review-cheat/order.lua): KK reaches the second participant (here the
-- arbiter) 1.2 s after the first, so the arbiter sees the Farkle, the HIC! line and the rethrow
-- before the decision they follow. Every line waits in order, so both write one chain.
test("1.2 Bone Throw (the design): the Farkle, the HIC! line and the rethrow seen before their decision give the chain of a client that saw the decision first", function()
	local fields = { target = 5000, first = 2, hiccup = true, id = "hic", players = { A, B } }
	eq(R(2, 3), 14); eq(R(1, 4), 19); eq(R(1, 2), 7)
	local function Start()
		local g = assert(F.New(fields))
		assert(F.Apply(g, Roll(2, 1, 2, 3, 4, 6, 6))); assert(F.Apply(g, "K2:1:b:3"))
		assert(F.Apply(g, "R1:6:31337"))
		return g
	end
	local function Both(lines)
		local fast, slow = Start(), Start()
		assert(F.Apply(fast, "K1:1356:r"))
		for _, c in ipairs(lines) do F.Apply(fast, c) end
		for _, c in ipairs(lines) do
			local ok, note = F.Apply(slow, c)
			eq(ok, true, c); eq(note, "held", c)
		end
		eq(#slow.queue, #lines)
		assert(F.Apply(slow, "K1:1356:r"))
		eq(#slow.queue, 0)
		eq(codes(slow), codes(fast)); eq(slow.chain, fast.chain); eq(F.Hash(slow), F.Hash(fast))
		return fast
	end
	-- shaken off: the rethrow counts
	local g = Both({ "R1:2:14", "H1:5", "R1:2:19" })
	eq(codes(g):match("K1:1356:r R1:2:14 H1:5 R1:2:19$") ~= nil, true)
	eq(g.turn.phase, "keep"); eq(g.turn.points, 300)
	-- a dice line before the HIC! line is an extra roll on both
	g = Both({ "R1:2:14", "R1:2:7", "H1:5", "R1:2:19" })
	eq(codes(g):match("K1:1356:r R1:2:14 H1:5 R1:2:19$") ~= nil, true)
	-- the Farkle stands: the rethrow is no longer his turn's, on both
	g = Both({ "R1:2:14", "H1:58", "R1:2:19" })
	eq(codes(g):match("K1:1356:r R1:2:14 H1:58$") ~= nil, true)
	eq(g.current, 2); eq(#g.ahead, 0)
	-- a relayed copy (a client that was away) writes the same chain, the marks left out
	local away = Start()
	for _, c in ipairs({ "K1:1356:r", "R1:2:14*", "H1:5*", "R1:2:19*" }) do assert(F.Apply(away, c)) end
	local fast = Both({ "R1:2:14", "H1:5", "R1:2:19" })
	eq(away.chain, fast.chain); eq(F.Hash(away), F.Hash(fast))
	eq(away.events[#away.events - 1], "H1:5*")
	local again = assert(F.Replay(fields, away.events))
	eq(again.chain, fast.chain)
end)

test("1.2 Bone Throw (the design): the next player's Farkle, hiccup and rethrow seen before the bank that passes him the dice: one chain", function()
	local fields = { target = 5000, first = 1, hiccup = true, id = "hj" }
	local x, y = assert(F.New(fields)), assert(F.New(fields))
	for _, g in ipairs({ x, y }) do assert(F.Apply(g, "R1:6:31337")) end
	local bank = "K1:35:b:3"                -- seat 1 banks 200 and saw seat 2 smashed
	local lines = { Roll(2, unpack(BUST6)), "H2:10", Roll(2, 1, 2, 3, 4, 6, 6) }
	assert(F.Apply(x, bank))
	eq(select(2, F.Apply(x, lines[1])), "hiccup"); eq(select(2, F.Apply(x, lines[2])), "shaken")
	assert(F.Apply(x, lines[3]))
	for _, l in ipairs(lines) do eq(select(2, F.Apply(y, l)), "held") end
	eq(#y.ahead, 3)
	assert(F.Apply(y, bank))
	eq(codes(y), codes(x)); eq(y.chain, x.chain)
	eq(y.turn.chance, 33); eq(y.shakes[2], 1); eq(y.turn.phase, "keep")
	-- a 1-100 line first, or a roll of five, starts nothing
	local z = assert(F.New(fields))
	assert(F.Apply(z, "R1:6:31337"))
	eq(err(F.Apply(z, "H2:10")), "turn"); eq(err(F.Apply(z, Roll(2, 1, 1, 1, 1, 1))), "turn")
end)

-- The review's pre-existing split (order.txt part 2, no drink): two typed rolls reach a witness
-- before the decision between them. With one held roll the lagging witness refused the second;
-- with the queue both witnesses take both, in turn.
test("1.2 Farkle (the design): two rolls ahead of two decisions give one chain on every client", function()
	local fields = { target = 2000, first = 1 }
	eq(R(1, 2), 7); eq(R(5), 5); eq(R(1), 1)
	local fast, slow = assert(F.New(fields)), assert(F.New(fields))
	for _, g in ipairs({ fast, slow }) do assert(F.Apply(g, "R1:6:31337")) end
	for _, c in ipairs({ "K1:1356:r", "R1:2:7", "R1:1:5", "K1:1:r", "R1:1:1" }) do assert(F.Apply(fast, c), c) end
	for _, c in ipairs({ "R1:2:7", "R1:1:5", "K1:1356:r", "K1:1:r", "R1:1:1" }) do assert(F.Apply(slow, c), c) end
	eq(codes(slow), codes(fast)); eq(slow.chain, fast.chain)
	eq(fast.events[#fast.events], "R1:1:5", "each roll the next decision's")
	eq(#fast.queue, 1); eq(#slow.queue, 1, "the third still waits for his next decision")
	-- held lines have a limit
	local g = assert(F.New(fields))
	assert(F.Apply(g, "R1:6:31337"))
	for i = 1, F.HOLD do eq(select(2, F.Apply(g, "R1:1:1")), "held", "line " .. i) end
	eq(err(F.Apply(g, "R1:1:1")), "extra")
	-- a bank with only a 1-100 line held is a bank (a 1-100 line is no roll, W4)
	local h = Drunk(3)
	assert(F.Apply(h, "R1:6:31337"))
	eq(select(2, F.Apply(h, Roll(1, 2, 3, 4, 6))), "held")
	eq(select(2, F.Apply(h, "H1:5")), "held")
	eq(select(2, F.Apply(h, "K1:35:b")), "stands", "the roll held before the bank stands")
	local b = Drunk(3)
	assert(F.Apply(b, "R1:6:31337"))
	eq(err(F.Apply(b, "H1:5")), "phase", "nothing held before it: ignored")
	assert(F.Apply(b, "K1:35:b"))
	eq(b.scores[1], 200); eq(b.current, 2)
end)

-- Found by the design's stress run: the arbiter's copy of a bank can lag a whole turn of the other
-- player. There, the banker's next-turn roll arrives before the bank, and W4 read the bank as
-- rolling on. The server's line order settles it the same everywhere: the other player's roll
-- came first, so he had seen the bank, and the banker's later roll belongs to his next turn.
test("1.2 Farkle (the design): a roll that came after the other player's held line never stands against the bank (W4)", function()
	local fields = { target = 2000, first = 1 }
	local fast, slow = assert(F.New(fields)), assert(F.New(fields))
	for _, g in ipairs({ fast, slow }) do assert(F.Apply(g, "R1:6:31337")) end
	local bust2 = Roll(2, 2, 2, 3, 3, 4, 6)
	local next1 = Roll(1, 1, 2, 3, 4, 6, 6)
	-- fast: the bank, seat 2's Farkle, seat 1's next first roll
	assert(F.Apply(fast, "K1:35:b")); assert(F.Apply(fast, bust2)); assert(F.Apply(fast, next1))
	-- slow: both rolls before the bank
	eq(select(2, F.Apply(slow, bust2)), "held"); eq(#slow.ahead, 1)
	eq(select(2, F.Apply(slow, next1)), "held"); eq(#slow.queue, 1)
	local ok, note = F.Apply(slow, "K1:35:b")
	eq(ok, true); eq(note, nil, "a bank, not W4")
	eq(codes(slow), codes(fast)); eq(slow.chain, fast.chain)
	eq(slow.scores[1], 200); eq(slow.current, 1); eq(slow.turn.phase, "keep")
	-- with no line of the other player before it, a roll seen before the bank still stands (W4)
	local w4 = assert(F.New(fields))
	assert(F.Apply(w4, "R1:6:31337"))
	eq(select(2, F.Apply(w4, Roll(1, 1, 2, 3, 4))), "held", "the four dice left are a valid roll-on")
	eq(select(2, F.Apply(w4, "K1:35:b")), "stands")
end)

-- Three clients (the two players and the arbiter) at a hiccup table, each applying what reaches
-- it in its own order: the server's lines at once, every message after a whisper delay of up to
-- 3 s, each player acting only on what his own client shows. Decisions carry levels, the arbiter
-- sends floors, Farkles hiccup: every client must write the same game.
test("1.2 Bone Throw (the design): seeded hiccup games on three clients with random message delays: one chain", function()
	local rng = Server(20260930)
	local function Secs(lo, hi) return lo + rng(1000) * (hi - lo) / 1000 end
	local total = { games = 0, hiccups = 0, shaken = 0, floors = 0, held = 0, late = 0, levels = 0 }
	for n = 1, 40 do
		local fields = { target = F.TARGETS[n % 3 + 1], id = "d" .. n, players = { A, B }, hiccup = true,
			first = n % 2 + 1 }
		local c = { assert(F.New(fields)), assert(F.New(fields)), assert(F.New(fields)) }
		local inbox, seq, busy, waiting = {}, 0, { false, false }, { {}, {}, {} }
		local function Post(at, to, item)
			seq = seq + 1
			item.at, item.seq, item.to = at, seq, to
			inbox[#inbox + 1] = item
		end
		local function Line(at, ev) for to = 1, 3 do Post(at, to, { ev = ev }) end end
		-- one sender's whispers reach each recipient in the order sent (Comm's queue; KK also
		-- carries its step), each after its own delay
		local last = { {}, {}, {} }
		local function Msg(at, from, item)
			for to = 1, 3 do
				local when = at
				if to ~= from then
					when = math.max(at + Secs(0.1, 3), (last[from][to] or 0) + 0.01)
					last[from][to] = when
				end
				Post(when, to, { ev = item.ev, floor = item.floor, step = item.step })
			end
		end
		-- a player acts on his own client's state, after a reaction time
		local function Act(me, now)
			local g = c[me]
			if busy[me] or g.over then return end
			local who, phase, left = F.Expect(g)
			if who ~= me then return end
			busy[me] = true
			local at = now + Secs(0.3, 1.8)
			if phase == "roll" then
				Post(at, 0, { act = me, ev = { t = "R", p = me, k = left, value = rng(F.RANGES[left]) } })
			elseif phase == "hiccup" then
				Post(at, 0, { act = me, ev = { t = "H", p = me, value = rng(100) } })
			elseif phase == "keep" then
				local pick, act = F.HouseMove(g)
				local ev = { t = "K", p = me, mask = pick, act = act }
				if rng(10) <= 3 then
					local lvl = rng(4) - 1
					if lvl ~= g.level[3 - me] then ev.lvl = lvl; total.levels = total.levels + 1 end
				end
				Post(at, 0, { act = me, ev = ev, msg = true })
			end
		end
		for me = 1, 2 do Act(me, 0) end
		local guard = 0
		while #inbox > 0 do
			guard = guard + 1
			assert(guard < 20000, "game " .. n .. " never settled")
			local best = 1
			for i = 2, #inbox do
				local a, b = inbox[i], inbox[best]
				if a.at < b.at or (a.at == b.at and a.seq < b.seq) then best = i end
			end
			local item = table.remove(inbox, best)
			if item.act then
				-- the player's own action leaves his client now
				busy[item.act] = false
				if item.msg then
					-- KK carries the sender's step: the decision is event step + 1
					Msg(item.at, item.act, { ev = item.ev, step = c[item.act].step })
				else
					Line(item.at, item.ev)
				end
			elseif item.step and item.step > c[item.to].step then
				-- a decision ahead of an event this client has not written yet (another sender's
				-- whisper still on its way): the table waits for it (the design: a gap)
				waiting[item.to][#waiting[item.to] + 1] = item
			else
				local g = c[item.to]
				if item.floor then
					local f = item.floor
					local ok, why = F.Floor(g, f.p, f.turn, f.lvl)
					if not ok and why == "late" then total.late = total.late + 1 end
				elseif not g.over then
					local ok, note = F.Apply(g, item.ev)
					if note == "held" then total.held = total.held + 1 end
					if item.to == 3 and ok and item.ev.t == "K" and rng(100) <= 15 then
						-- the arbiter's floor for a seat, from that seat's turn after next
						local p = rng(2)
						local f = { p = p, turn = g.turns[p] + 2, lvl = rng(4) - 1 }
						total.floors = total.floors + 1
						Msg(item.at, 3, { floor = f })
					end
				end
				-- the decisions it waited for whose step has come
				local w, i = waiting[item.to], 1
				while i <= #w do
					if w[i].step == g.step then
						local again = table.remove(w, i)
						eq(F.Apply(g, again.ev), true, "a decision that waited for its step")
						i = 1
					else
						i = i + 1
					end
				end
				if item.to <= 2 then Act(item.to, item.at) end
			end
		end
		for i = 1, 3 do eq(#waiting[i], 0, "nothing left waiting") end
		for i = 1, 3 do eq(c[i].over, true, "game " .. n .. " client " .. i) end
		eq(codes(c[2]), codes(c[1]), "game " .. n); eq(codes(c[3]), codes(c[1]), "game " .. n)
		eq(c[2].chain, c[1].chain); eq(c[3].chain, c[1].chain); eq(c[3].winner, c[1].winner)
		for _, code in ipairs(c[1].events) do
			if code:sub(1, 1) == "H" then total.hiccups = total.hiccups + 1 end
		end
		total.shaken = total.shaken + c[1].shakes[1] + c[1].shakes[2]
		local again = assert(F.Replay(fields, c[3].events))
		eq(F.Hash(again), F.Hash(c[1])); eq(again.winner, c[1].winner)
		total.games = total.games + 1
	end
	eq(total.games, 40); eq(total.late, 0, "a floor named for the turn after next is never late here")
	assert(total.hiccups > 40, "hiccups: " .. total.hiccups)
	assert(total.shaken > 10, "shake-offs: " .. total.shaken)
	assert(total.held > 200, "lines held by a lagging client: " .. total.held)
	assert(total.floors > 20, "floors: " .. total.floors)
	if os.getenv("VERBOSE") then
		print(("       %d games, %d hiccups, %d shaken, %d held lines, %d floors, %d levels, %d late")
			:format(total.games, total.hiccups, total.shaken, total.held, total.floors, total.levels, total.late))
	end
end)
