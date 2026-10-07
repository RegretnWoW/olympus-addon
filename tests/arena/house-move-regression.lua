local H = ...
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
H.test("House legality regression: actual choices apply on first bank, hot dice and drunk turns", function()
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
	assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
	local F = ns.FarkleRules
	local function Roll(g, dice)
		local p, _, k = F.Expect(g)
		H.eq(k, #dice)
		assert(F.Apply(g, { t = "R", p = p, k = k, value = F.Encode(dice) }))
	end
	local function Move(g)
		local p = F.Expect(g)
		local pick, act = F.HouseMove(g)
		assert(pick)
		assert(F.Apply(g, { t = "K", p = p, mask = pick, act = act }))
		assert(not g.last or g.last.how ~= "foul")
		return act
	end
	for level = 0, 3 do
		local g = assert(F.New({ target = 5000, first = 2, hiccup = true }))
		if level > 0 then assert(F.Floor(g, 2, 1, level)) end
		Roll(g, { 1, 1, 5, 5, 2, 3 })
		H.eq(Move(g), "b", "first bank of 300 is legal, no entry minimum")
		H.eq(g.scores[2], 300)
	end
	local hot = assert(F.New({ target = 5000, first = 2 }))
	Roll(hot, { 5, 5, 5, 2, 3, 4 }); H.eq(Move(hot), "r")
	Roll(hot, { 1, 5, 5 }); H.eq(Move(hot), "r")
	H.eq(hot.turn.left, 6); H.eq(hot.turn.points, 700)
	Roll(hot, { 1, 1, 1, 2, 3, 4 }); H.eq(Move(hot), "b")
	H.eq(hot.scores[2], 1700)
	local drunk = assert(F.New({ target = 5000, first = 2, hiccup = true }))
	assert(F.Floor(drunk, 2, 1, 3))
	Roll(drunk, { 2, 2, 3, 3, 4, 6 })
	H.eq(select(2, F.HouseMove(drunk)), "h")
	assert(F.Apply(drunk, { t = "H", p = 2, value = 1 }))
	Roll(drunk, { 1, 1, 1, 2, 3, 4 }); H.eq(Move(drunk), "b")
end)
H.test("House target regression: 5000 wins immediately with no answer turn or later AI move", function()
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
	assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
	local F = ns.FarkleRules
	local g = assert(F.New({ target = 5000, first = 1 }))
	local function Bank(dice)
		assert(F.Apply(g, { t = "R", p = 1, k = 6, value = F.Encode(dice) }))
		local pick, act = F.HouseMove(g)
		H.eq(act, "b")
		assert(F.Apply(g, { t = "K", p = 1, mask = pick, act = act }))
	end
	for _ = 1, 2 do
		Bank({ 1, 1, 1, 1, 2, 3 })
		assert(F.Apply(g, { t = "R", p = 2, k = 6, value = F.Encode({ 2, 2, 3, 3, 4, 6 }) }))
	end
	Bank({ 1, 1, 1, 2, 3, 4 })
	H.eq(g.scores[1], 5000); H.eq(g.final, nil)
	H.eq(g.over, true); H.eq(g.winner, 1)
	local steps = g.step
	H.eq(F.HouseMove(g), nil)
	local ok, why = F.Apply(g, { t = "R", p = 2, k = 6, value = 1 })
	H.eq(ok, nil); H.eq(why, "over"); H.eq(g.step, steps)
end)
H.test("House race regression: scheduled moves never foul with valid scoring dice", function()
	local w = FW.New({ seed = 77 })
	local c = w:Player(H.World.NAMES.fighterA)
	w:Stand(c.name, FW.INN, true)
	local F, FT = c.ns.FarkleRules, c.ns.FarkleTable
	local start = w.clock
	FT.busy = function() local dt = w.clock - start return dt >= 2.05 and dt < 2.25 end
	local original = math.random
	local calls = 0
	math.random = function(lo, hi)
		calls = calls + 1
		if hi == F.RANGES[6] then return F.Encode({ 1, 2, 2, 3, 3, 6 }) end
		if hi == F.RANGES[5] then return F.Encode({ 1, 1, 1, 2, 3 }) end
		return lo
	end
	local ok, err = pcall(function()
		local id = w:As(c, FT.Practice, { target = 5000, first = 2 })
		assert(id)
		w:Run(8)
		local t = FT.Get(id)
		for _, code in ipairs(t.game.events) do assert(not code:match("^F"), "House foul: " .. table.concat(t.game.events, " ")) end
		assert(calls > 1)
	end)
	math.random = original
	if not ok then error(err, 0) end
end)

H.test("House target regression: banks a target-winning 50 below ordinary risk thresholds", function()
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
	assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
	local F = ns.FarkleRules
	local g = assert(F.New({ target = 2000, first = 2 }))
	local function Roll(p, dice) assert(F.Roll(g, p, F.Encode(dice))) end
	local function Bust() Roll(1, { 2, 2, 3, 3, 4, 6 }) end
	Roll(2, { 1, 1, 1, 2, 3, 4 }); assert(F.Keep(g, 2, { 1, 2, 3 })); assert(F.Bank(g, 2)); Bust()
	Roll(2, { 5, 5, 5, 4, 2, 3 }); assert(F.Keep(g, 2, { 1, 2, 3 }))
	Roll(2, { 4, 4, 4 }); assert(F.Keep(g, 2, { 1, 2, 3 }))
	Roll(2, { 5, 2, 2, 3, 3, 6 }); assert(F.Keep(g, 2, { 1 })); assert(F.Bank(g, 2)); Bust()
	H.eq(g.scores[2], 1950)
	Roll(2, { 5, 2, 2, 3, 3, 6 })
	local pick, act = F.HouseMove(g)
	H.eq(act, "b", "banking 50 reaches the target immediately")
	assert(F.Apply(g, { t = "K", p = 2, mask = pick, act = act }))
	H.eq(g.scores[2], 2000); H.eq(g.over, true); H.eq(g.winner, 2)
end)
