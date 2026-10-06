-- 1.2 (the Blood Arena): the championship's knockout brackets (Olympus/ArenaBracket.lua).
-- Run by tests/run.lua with its helpers; the module is loaded into a table of its own.
local H = ...
local test, eq = H.test, H.eq
local ns = {}
assert(loadfile(H.ADDON_DIR .. "ArenaBracket.lua"))("Olympus", ns)
local B = ns.ArenaBracket

-- Invented fighters: entrant i has id Id(i) and a rating that makes him seed i.
local function Id(i) return ("Player-9999-%08X"):format(i) end
local function Field(n)
	local list = {}
	for i = 1, n do list[i] = { id = Id(i), name = "Fighter" .. i, rating = 2000 - i * 10, fights = 20 } end
	return list
end
local function Same(got, want, msg)
	eq(#got, #want, (msg or "") .. " length")
	for i = 1, #want do eq(got[i], want[i], (msg or "") .. " [" .. i .. "]") end
end
local function Ids(list)
	local out = {}
	for i, e in ipairs(list) do out[i] = e.id end
	return out
end
local function Keys(matches)
	local out = {}
	for i, m in ipairs(matches) do out[i] = m.key end
	return out
end
local function SeedOf(br, id) return br.entrants[id].seed end
-- Plays every ready match (up to round last, when given) until none is left, the better seed
-- winning by knockout with the series' full score. check(match), when given, looks at each
-- match before it is played.
local function Favourites(br, check, last)
	while true do
		local ready = {}
		for _, m in ipairs(B.Next(br)) do
			if not last or m.round <= last then ready[#ready + 1] = m end
		end
		if #ready == 0 then return end
		for _, m in ipairs(ready) do
			if check then check(m) end
			local _, _, _, need = B.Score(br, m.key)
			local w = SeedOf(br, m.a) < SeedOf(br, m.b) and m.a or m.b
			assert(B.Advance(br, m.key, w, "K", need, 0))
		end
	end
end
local function Copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = Copy(v) end
	return out
end

-- Size and the standard seeding order ------------------------------------

-- The design's sizes changed from 2-64 to 4-32 (the design: "The UI and messages use 4 to
-- 32"), and 64 no longer exists. A field of 2 is refused: in a bracket of 4 it
-- would have a bye in both semifinals, so no real first-round match and no stage 3, which
-- Possible(4) lists (whether two may enter is Daniel's call; then Possible would take n too).
test("arena bracket: the size is the smallest power of two that holds the field: 3 to 32 fighters, sizes 4 to 32", function()
	eq(B.Size(3), 4); eq(B.Size(4), 4); eq(B.Size(5), 8); eq(B.Size(8), 8)
	eq(B.Size(11), 16); eq(B.Size(17), 32); eq(B.Size(32), 32)
	for _, bad in ipairs({ 2, 1, 0, 33, 64, 2.5, -4, 0 / 0 }) do
		local s, err = B.Size(bad)
		eq(s, nil, tostring(bad)); eq(err, "count", tostring(bad))
	end
	eq(select(2, B.Size(nil)), "count"); eq(select(2, B.Size("8")), "count")
	eq(B.MIN_SIZE, 4); eq(B.MAX_SIZE, 32); eq(B.MIN, 3); eq(B.MAX, 32)
end)

test("arena bracket: a field of two or of 33 builds no bracket, and no draw", function()
	for _, n in ipairs({ 2, 33 }) do
		local ids = {}
		for i = 1, n do ids[i] = Id(i) end
		eq(select(2, B.Build(Field(n))), "count", "Build " .. n)
		eq(select(2, B.Seed(ids)), "count", "Seed " .. n)
		eq(select(2, B.ApplyDraw(ids, {})), "count", "ApplyDraw " .. n)
		eq(select(2, B.DrawState(ids, {})), "count", "DrawState " .. n)
		eq(select(2, B.NextRoll(n, {})), "count", "NextRoll " .. n)
		eq(select(2, B.SeedCount(n)), "count", "SeedCount " .. n)
	end
	local br = assert(B.Build(Field(32), { third = true }))
	eq(br.size, 32); eq(br.rounds, 5); eq(br.n, 32)
	br = assert(B.Build(Field(3)))
	eq(br.size, 4); eq(br.rounds, 2)
end)

test("arena bracket: Order(16) is the design's list, and the small sizes are the standard sheets", function()
	Same(B.Order(16), { 1, 16, 8, 9, 5, 12, 4, 13, 3, 14, 6, 11, 7, 10, 2, 15 }, "16")
	Same(B.Order(8), { 1, 8, 4, 5, 3, 6, 2, 7 }, "8")
	Same(B.Order(4), { 1, 4, 2, 3 }, "4")
	for _, bad in ipairs({ 2, 64, 1, 3, 12, 128, 0 }) do
		local o, err = B.Order(bad)
		eq(o, nil, tostring(bad)); eq(err, "size", tostring(bad))
	end
end)

test("arena bracket: every order is a permutation, each first pair has the better seed on top and adds to S+1", function()
	for _, S in ipairs({ 4, 8, 16, 32 }) do
		local order, seen = B.Order(S), {}
		eq(#order, S, "size " .. S)
		for _, s in ipairs(order) do
			assert(not seen[s] and s >= 1 and s <= S, "seed " .. s .. " once in " .. S)
			seen[s] = true
		end
		for p = 1, S, 2 do
			assert(order[p] < order[p + 1], "better seed on top at " .. p .. " of " .. S)
			eq(order[p] + order[p + 1], S + 1, "pair at " .. p .. " of " .. S)
		end
		eq(order[1], 1, "seed 1 at the top of " .. S); eq(order[S] == 2 or order[S - 1] == 2, true, "seed 2 at the bottom of " .. S)
	end
end)

test("arena bracket: with the favourites winning, each round pairs seeds adding to S/2^(r-1)+1, and 1 meets 2 only in the final", function()
	for _, S in ipairs({ 4, 8, 16, 32 }) do
		local br = assert(B.Build(Field(S)))
		local met = 0
		Favourites(br, function(m)
			eq(SeedOf(br, m.a) + SeedOf(br, m.b), S / 2 ^ (m.round - 1) + 1, ("S %d round %d"):format(S, m.round))
			if SeedOf(br, m.a) + SeedOf(br, m.b) == 3 then met = met + 1; eq(m.round, br.rounds, "1 v 2 is the final of " .. S) end
		end)
		eq(met, 1, "1 and 2 meet once in " .. S)
		eq(B.Champion(br), Id(1), "champion of " .. S)
	end
end)

test("arena bracket: PositionOf and SeedCount", function()
	eq(B.PositionOf(16, 1), 1); eq(B.PositionOf(16, 2), 15); eq(B.PositionOf(16, 16), 2); eq(B.PositionOf(8, 7), 8)
	eq(select(2, B.PositionOf(16, 17)), "seeds"); eq(select(2, B.PositionOf(12, 1)), "size")
	eq(select(2, B.PositionOf(64, 1)), "size")
	eq(B.SeedCount(3), 2); eq(B.SeedCount(4), 2); eq(B.SeedCount(8), 2); eq(B.SeedCount(11), 4)
	eq(B.SeedCount(16), 4); eq(B.SeedCount(17), 8); eq(B.SeedCount(32), 8)
	eq(select(2, B.SeedCount(1)), "count")
end)

-- Seeding by rating ----------------------------------------------------------

test("arena bracket: Seed sorts by rating, ties to more fights then to the id; unrated last; copies", function()
	local input = {
		{ id = "Player-9999-0000000C", name = "Corvane", rating = 1500, fights = 5 },
		{ id = "Player-9999-0000000A", name = "Aldrith", rating = 1600 },
		{ id = "Player-9999-0000000B", name = "Brenlow", rating = 1500, fights = 9 },
		{ id = "Player-9999-0000000D", name = "Dusmere" },
		{ id = "Player-9999-0000000E", name = "Elgarth", rating = 1500, fights = 5 },
	}
	local out = assert(B.Seed(input))
	Same(Ids(out), { "Player-9999-0000000A", "Player-9999-0000000B", "Player-9999-0000000C", "Player-9999-0000000E", "Player-9999-0000000D" })
	out[1].name = "changed"
	eq(input[2].name, "Aldrith", "the caller's entrant untouched")
	eq(input[1].id, "Player-9999-0000000C", "the caller's list keeps its order")
	-- ties on the id go by byte order ("B" 66 < "a" 97 < "b" 98). This pins the order, but it
	-- cannot tell the module's byte compare from Lua's own <: LuaJIT's < is byte order too,
	-- while the client's Lua 5.1 compares strings with the system's collation. That part is
	-- an in-game check.
	Same(Ids(assert(B.Seed({ "b", "a", "B" }))), { "B", "a", "b" })
end)

test("arena bracket: entrant lists are checked (count, ids, duplicates, ratings)", function()
	eq(select(2, B.Seed({ "only" })), "count")
	local big = {}
	for i = 1, 33 do big[i] = Id(i) end
	eq(select(2, B.Seed(big)), "count")
	eq(select(2, B.Seed("x")), "count")
	eq(select(2, B.Seed({ "x", "x", "z" })), "duplicate")
	eq(select(2, B.Seed({ "x", "", "z" })), "entrant")
	eq(select(2, B.Seed({ "x", 42, "z" })), "entrant")
	eq(select(2, B.Seed({ "x", { name = "no id" }, "z" })), "entrant")
	eq(select(2, B.Seed({ "x", { id = "y", rating = "high" }, "z" })), "rating")
	eq(select(2, B.Seed({ "x", { id = "y", rating = 0 / 0 }, "z" })), "rating")
	eq(select(2, B.Build({ "x", "x", "z" })), "duplicate")
	eq(select(2, B.ApplyDraw({ "x" }, {})), "count")
end)

test("arena bracket: an entrant's fields are plain values, so the bracket shares no table with its caller", function()
	local facts = { guild = "Olympus" }
	local br, err = B.Build({ { id = "a", facts = facts }, { id = "b", facts = facts }, "c" })
	eq(br, nil, "a table field would be the same table in both entrants and in the caller's list"); eq(err, "entrant")
	eq(select(2, B.Seed({ "x", { id = "y", onClick = function() end }, "z" })), "entrant")
	eq(select(2, B.ApplyDraw({ "x", { id = "y", [{}] = 1 }, "z" }, { 1 })), "entrant", "a table key")
	br = assert(B.Build({ { id = "a", name = "Morvenna", guild = "Olympus", title = true, wins = 3 }, "b", "c" }))
	eq(br.entrants.a.guild, "Olympus"); eq(br.entrants.a.title, true); eq(br.entrants.a.wins, 3)
end)

-- The public draw ----------------------------------------------------------

test("arena bracket: the draw is set by the rolls alone, whatever order the entrants came in", function()
	local A, Bb, C, D, E = "Player-9999-0000000A", "Player-9999-0000000B", "Player-9999-0000000C", "Player-9999-0000000D", "Player-9999-0000000E"
	-- the pool is sorted by id: A B C D E. Roll 3 of 5: C; 1 of 4 (A B D E): A; 3 of 3 (B D E): E;
	-- 2 of 2 (B D): D; B is left.
	local rolls = { 3, 1, 3, 2 }
	local one = assert(B.ApplyDraw({ { id = C, name = "Corvane" }, { id = E }, { id = A }, { id = D }, { id = Bb } }, rolls))
	Same(Ids(one), { C, A, E, D, Bb })
	eq(one[1].name, "Corvane", "the entrant's fields come along")
	Same(Ids(assert(B.ApplyDraw({ Bb, D, A, E, C }, rolls))), { C, A, E, D, Bb }, "another order heard")
	Same(Ids(assert(B.ApplyDraw({ Bb, D, A, E, C }, { 3, 1, 3, 2, 1 }))), { C, A, E, D, Bb }, "a last roll of 1")
	-- two clients build the same sheet from the same roll lines
	local b1 = assert(B.Build(assert(B.ApplyDraw({ A, Bb, C, D, E }, rolls))))
	local b2 = assert(B.Build(assert(B.ApplyDraw({ E, D, C, Bb, A }, rolls))))
	Same(b1.slots, b2.slots, "slots")
	eq(b1.slots[1], C, "the first drawn is seed 1"); eq(b1.slots[2], false, "and faces a bye")
end)

test("arena bracket: the entrants drawn are counted by id, never by rating (another client's ratings may differ)", function()
	local rated = { { id = "d", rating = 1900 }, { id = "c", rating = 1800 }, { id = "b", rating = 1700 }, { id = "a", rating = 1600 } }
	Same(Ids(assert(B.ApplyDraw(rated, { 1, 1, 1 }))), { "a", "b", "c", "d" })
	local other = { { id = "b", rating = 2100 }, { id = "d", rating = 1200 }, { id = "a", rating = 1500 }, { id = "c" } }
	Same(Ids(assert(B.ApplyDraw(other, { 1, 1, 1 }))), { "a", "b", "c", "d" }, "other ratings, same draw")
	Same(Ids(assert(B.ApplyDraw(rated, { 1, 1 }, { "c" }))), { "c", "a", "b", "d" }, "after the promoter's seeds")
	Same(Ids(assert(B.ApplyDraw(rated, { 2, 1 }, 1))), { "d", "b", "a", "c" }, "after the top seed by rating")
end)

test("arena bracket: every order of four comes from exactly one set of rolls (a fair draw)", function()
	local seen, count = {}, 0
	for r1 = 1, 4 do
		for r2 = 1, 3 do
			for r3 = 1, 2 do
				local key = table.concat(Ids(assert(B.ApplyDraw({ "a", "b", "c", "d" }, { r1, r2, r3 }))), ",")
				assert(not seen[key], "drawn twice: " .. key)
				seen[key], count = true, count + 1
			end
		end
	end
	eq(count, 24)
end)

test("arena bracket: bad rolls are refused with their step", function()
	local field = { "a", "b", "c", "d", "e" }
	local list, err, step = B.ApplyDraw(field, { 3, 5 })
	eq(list, nil); eq(err, "roll"); eq(step, 2)
	list, err, step = B.ApplyDraw(field, { 0 })
	eq(err, "roll"); eq(step, 1)
	list, err, step = B.ApplyDraw(field, { 2.5 })
	eq(err, "roll"); eq(step, 1)
	list, err, step = B.ApplyDraw(field, { 3, 1 })
	eq(err, "rolls", "too few"); eq(step, 3)
	list, err, step = B.ApplyDraw(field, { 3, 1, 3, 2, 2 })
	eq(err, "roll", "the last one left is a 1"); eq(step, 5)
	list, err, step = B.ApplyDraw(field, { 3, 1, 3, 2, 1, 1 })
	eq(err, "rolls", "too many"); eq(step, 6)
	eq(select(2, B.ApplyDraw(field, "3,1")), "rolls")
	eq(select(2, B.ApplyDraw(field, {}, 6)), "seeds")
	eq(select(2, B.ApplyDraw(field, {}, -1)), "seeds")
	eq(select(2, B.ApplyDraw(field, {}, { "a", "zz" })), "seeds", "a seed who is no entrant")
	eq(select(2, B.ApplyDraw(field, {}, { "a", "a" })), "seeds", "a seed twice")
	eq(select(2, B.ApplyDraw(field, {}, { "a", "b", "c", "d", "e", "f" })), "seeds", "more seeds than entrants")
	eq(select(2, B.DrawState(field, {}, { "a", "b", "c", "d", "e", "f" })), "seeds")
	-- a roll after a gap, or a key that is no step, was never asked for
	list, err, step = B.ApplyDraw(field, { 3, nil, 2 })
	eq(list, nil); eq(err, "rolls", "a gap"); eq(step, 2)
	list, err, step = B.DrawState(field, { 3, nil, 2 })
	eq(list, nil); eq(err, "rolls", "a gap, partway too"); eq(step, 2)
	list, err, step = B.DrawState(field, { 3, x = 1 })
	eq(err, "rolls", "not a step"); eq(step, 2)
	list, err, step = B.DrawState(field, { 9 })
	eq(err, "roll", "partway, a bad roll is still refused"); eq(step, 1)
end)

test("arena bracket: seeds stay out of the draw: the top k by rating, or the promoter's list", function()
	local field = Field(6)
	-- the top two by rating, then the other four drawn (ids 3 4 5 6): 2 of 4 → 4; 3 of 3 (3 5 6) → 6; 1 of 2 (3 5) → 3; 5 left
	local list = assert(B.ApplyDraw({ field[5], field[2], field[6], field[1], field[4], field[3] }, { 2, 3, 1 }, 2))
	Same(Ids(list), { Id(1), Id(2), Id(4), Id(6), Id(3), Id(5) })
	-- the promoter's word names the seeds (a client's own ratings may differ from his)
	list = assert(B.ApplyDraw(field, { 1, 1, 1 }, { Id(5), Id(3) }))
	Same(Ids(list), { Id(5), Id(3), Id(1), Id(2), Id(4), Id(6) })
	-- all seeded: no roll at all
	Same(Ids(assert(B.ApplyDraw(field, nil, 6))), { Id(1), Id(2), Id(3), Id(4), Id(5), Id(6) })
	eq(select(2, B.ApplyDraw(field, { 1 }, 6)), "rolls")
end)

test("arena bracket: NextRoll says which /roll the draw needs next, and CheckRoll takes only that one", function()
	local s, max = B.NextRoll(5, {})
	eq(s, 1); eq(max, 5)
	s, max = B.NextRoll(5, { 3 })
	eq(s, 2); eq(max, 4)
	s, max = B.NextRoll(5, 3)
	eq(s, 4); eq(max, 2)
	eq(B.NextRoll(5, { 3, 1, 3, 2 }), nil, "complete: the last one needs no roll")
	s, max = B.NextRoll(Field(6), {}, 2)
	eq(s, 1); eq(max, 4)
	s, max = B.NextRoll(6, {}, { Id(1), Id(2), Id(3) })
	eq(s, 1); eq(max, 3)
	eq(B.NextRoll(6, {}, 5), nil, "one left to draw")
	eq(select(2, B.NextRoll(1, {})), "count"); eq(select(2, B.NextRoll(5, {}, 6)), "seeds")
	local ok, step = B.CheckRoll(5, { 3 }, nil, 2, 1, 4)
	eq(ok, true); eq(step, 2)
	eq(select(2, B.CheckRoll(5, { 3 }, nil, 2, 1, 100)), "range", "a /roll with another max")
	eq(select(2, B.CheckRoll(5, { 3 }, nil, 2, 2, 4)), "range")
	eq(select(2, B.CheckRoll(5, { 3 }, nil, 5, 1, 4)), "roll")
	eq(select(2, B.CheckRoll(5, { 3, 1, 3, 2 }, nil, 1, 1, 1)), "done")
	-- the rolls CheckRoll takes are the ones ApplyDraw completes
	local rolls = {}
	for _, r in ipairs({ { 4, 5 }, { 9, 100 }, { 2, 4 }, { 1, 3 }, { 2, 2 } }) do
		if B.CheckRoll(5, rolls, nil, r[1], 1, r[2]) then rolls[#rolls + 1] = r[1] end
	end
	Same(rolls, { 4, 2, 1, 2 })
	assert(B.ApplyDraw({ "a", "b", "c", "d", "e" }, rolls))
end)

test("arena bracket: CheckRoll leaves the seeds out of the roll's range", function()
	local ok, step = B.CheckRoll(6, {}, 2, 3, 1, 4)
	eq(ok, true); eq(step, 1)
	eq(select(2, B.CheckRoll(6, {}, 2, 3, 1, 6)), "range", "a /roll over the whole field, seeds included")
	ok, step = B.CheckRoll(Field(6), { 2 }, { Id(1), Id(2), Id(3) }, 1, 1, 2)
	eq(ok, true); eq(step, 2)
	-- one fewer left after a roll: the first step's 1-3 again is a roll again (farkle W1), no
	-- longer the step the draw needs
	eq(select(2, B.CheckRoll(6, { 2 }, { Id(1), Id(2), Id(3) }, 3, 1, 3)), "extra", "one fewer left after a roll")
	eq(select(2, B.CheckRoll(6, { 2, 1 }, { Id(1), Id(2), Id(3) }, 1, 1, 1)), "done")
	eq(select(2, B.CheckRoll(6, {}, 7, 1, 1, 1)), "seeds")
end)

-- The first n of a list (the rolls taken by a given moment).
local function First(list, n)
	local out = {}
	for i = 1, n do out[i] = list[i] end
	return out
end

test("arena bracket: DrawState shows the draw partway: each roll's pick, its slot, and the list left", function()
	local field = Field(11) -- 16 places: four seeds by rating, seven drawn with six rolls
	local k = B.SeedCount(11)
	local rolls = { 5, 1, 4, 2, 3, 1 }
	local final = assert(B.ApplyDraw(field, rolls, k))
	local br = assert(B.Build(final))
	local s0 = assert(B.DrawState(field, {}, k))
	eq(s0.k, 4); eq(s0.size, 16); eq(s0.total, 6, "the last one left needs no roll"); eq(s0.step, 1); eq(s0.max, 7)
	Same(Ids(s0.list), { Id(1), Id(2), Id(3), Id(4) }, "only the seeds before any roll")
	Same(Ids(s0.left), { Id(5), Id(6), Id(7), Id(8), Id(9), Id(10), Id(11) }, "the pool in id order")
	for s = 1, #rolls do
		local before = assert(B.DrawState(field, First(rolls, s - 1), k))
		local after = assert(B.DrawState(field, First(rolls, s), k))
		local step, max = B.NextRoll(11, s - 1, k)
		eq(before.step, step, "step " .. s); eq(before.max, max, "max at " .. s); eq(#before.left, max)
		local picked = before.left[rolls[s]].id
		eq(after.list[k + s].id, picked, "roll " .. s .. " picks left[roll]")
		eq(after.list[k + s].drawn, s)
		eq(final[k + s].id, picked, "the complete draw's seed k+s")
		eq(br.slots[B.PositionOf(16, k + s)], picked, "the AD slot of roll " .. s)
		if s < #rolls then
			eq(#after.left, max - 1, "one fewer left after roll " .. s)
		else
			eq(#after.left, 0, "after the last roll, the one left is placed at once")
		end
		for _, e in ipairs(after.left) do assert(e.id ~= picked, "drawn and still left at " .. s) end
	end
	local done = assert(B.DrawState(field, rolls, k))
	eq(done.step, nil); eq(done.max, nil); eq(#done.left, 0); eq(#done.list, 11)
	eq(done.list[11].drawn, 7, "the last one is drawn without a roll")
	Same(Ids(done.list), Ids(final))
	eq(field[5].drawn, nil, "the caller's entrants are untouched")
	-- the promoter's seeds, and a field with no one to draw
	local s = assert(B.DrawState(field, {}, { Id(7), Id(2) }))
	eq(s.k, 2); eq(s.max, 9); Same(Ids(s.list), { Id(7), Id(2) }); eq(s.left[1].id, Id(1))
	s = assert(B.DrawState(field, nil, 11))
	eq(s.step, nil); eq(s.total, 0); eq(#s.list, 11)
end)

test("arena bracket: the bracket marks the seed numbers the draw gave (the sheet shows no seed for them)", function()
	local field = Field(6)
	local br = assert(B.Build(assert(B.ApplyDraw(field, { 2, 3, 1 }, 2))))
	eq(br.entrants[Id(1)].drawn, nil); eq(br.entrants[Id(2)].drawn, nil)
	local steps = {}
	for i = 3, 6 do
		local e = br.entrants[Id(i)]
		assert(e.drawn, "entrant " .. i .. " was drawn")
		eq(e.seed, 2 + e.drawn, "seed k + step for " .. i)
		steps[e.drawn] = true
	end
	for s = 1, 4 do eq(steps[s], true, "step " .. s) end
	for _, e in pairs(assert(B.Build(field)).entrants) do eq(e.drawn, nil, "seeded by rating alone") end
	-- a list drawn before and then seeded whole by the promoter: only this draw counts
	local again = assert(B.ApplyDraw(assert(B.ApplyDraw(field, { 1, 1, 1, 1, 1 })), nil, Ids(Field(6))))
	for _, e in ipairs(again) do eq(e.drawn, nil, "no longer drawn: " .. e.id) end
end)

-- Building ---------------------------------------------------------------

test("arena bracket: 11 entrants: byes against seeds 1 to 5, and the ready matches", function()
	local br = assert(B.Build(Field(11)))
	eq(br.size, 16); eq(br.rounds, 4); eq(br.n, 11)
	local byes = 0
	for _, slot in ipairs(br.slots) do if slot == false then byes = byes + 1 end end
	eq(byes, 5)
	for _, k in ipairs({ "1.1", "1.3", "1.4", "1.5", "1.8" }) do
		local m = B.Match(br, k)
		eq(m.done, true, k); eq(m.method, "B", k); eq(m.b, false, k); eq(m.loser, false, k)
		assert(SeedOf(br, m.winner) <= 5, "a top seed has the bye at " .. k)
	end
	eq(B.Match(br, "2.1").a, Id(1), "seed 1 is through"); eq(B.Match(br, "2.1").b, nil, "waiting for 8 v 9")
	Same(Keys(B.Next(br)), { "1.2", "1.6", "1.7", "2.2" }, "8v9, 6v11, 7v10, and 5v4 (both byes)")
	eq(SeedOf(br, B.Match(br, "2.2").a), 5); eq(SeedOf(br, B.Match(br, "2.2").b), 4)
	eq(B.CurrentRound(br), 1)
	local r, alive = B.Reached(br, Id(1))
	eq(r, 2); eq(alive, true)
	eq(B.Reaches(br, Id(1), "quarterfinal"), true, "the bye puts him in the last 8")
	eq(B.Reaches(br, Id(9), "quarterfinal"), nil, "still open")
	eq(select(2, B.Advance(br, "1.1", Id(1), "K")), "decided", "a bye is not played")
end)

test("arena bracket: best-of per round counts back from the final", function()
	local function Bos(n, bo)
		local br = assert(B.Build(Field(n), { bo = bo }))
		local out = {}
		for r = 1, br.rounds do out[r] = B.Match(br, B.Key(r, 1)).bo end
		return out
	end
	Same(Bos(8, "135"), { 1, 3, 5 })
	Same(Bos(16, "135"), { 1, 1, 3, 5 })
	Same(Bos(4, "135"), { 3, 5 })
	Same(Bos(3, "135"), { 3, 5 })
	Same(Bos(32, "135"), { 1, 1, 1, 3, 5 })
	Same(Bos(8, { 3, 5 }), { 3, 3, 5 })
	Same(Bos(8, 3), { 3, 3, 3 })
	Same(Bos(8), { 1, 1, 1 })
	for _, bad in ipairs({ 2, 7, 0, 1.5, 0 / 0, "1a", "", "12", {}, { 1, 2 }, true }) do
		local br, err = B.Build(Field(8), { bo = bad })
		eq(br, nil, tostring(bad)); eq(err, "bo", tostring(bad))
	end
	-- a list with a hole or a stray key is refused, not read as far as its first gap (which
	-- would quietly lose the final's bo5)
	for name, bad in pairs({ hole = { 1, nil, 5 }, gap = { [1] = 3, [3] = 5 }, second = { [2] = 3 }, key = { 3, 5, final = 5 } }) do
		local br, err = B.Build(Field(8), { bo = bad })
		eq(br, nil, name); eq(err, "bo", name)
	end
end)

-- (Before sizes 4-32, a field of two had no semifinals and no third-place match; every bracket
-- has semifinals now, so the smallest case is a field of three with a bye in one semifinal.)
test("arena bracket: the third-place match: its best-of, and in a field of three the bye's", function()
	local br = assert(B.Build(Field(8), { bo = "135", third = true }))
	local t = B.ThirdPlace(br)
	eq(t.key, "3.2"); eq(t.third, true); eq(t.bo, 3, "the semifinals' best-of")
	br = assert(B.Build(Field(8), { bo = "135", third = true, boThird = 1 }))
	eq(B.ThirdPlace(br).bo, 1)
	eq(select(2, B.Build(Field(8), { third = true, boThird = 4 })), "bo")
	eq(B.ThirdPlace(assert(B.Build(Field(8)))), nil, "off unless asked")
	-- three: seed 1 has a bye in his semifinal, so its loser is nobody and 2 v 3's loser is third
	br = assert(B.Build(Field(3), { third = true }))
	eq(br.third, true); eq(B.ThirdPlace(br).key, "2.2")
	eq(B.Match(br, "1.1").method, "B")
	assert(B.Advance(br, "1.2", Id(3), "K"))
	t = B.ThirdPlace(br)
	eq(t.a, false); eq(t.b, Id(2)); eq(t.done, true); eq(t.method, "B"); eq(t.winner, Id(2))
	eq(B.Reached(br, Id(2)), "3")
	local place, label = B.Placing(br, Id(2))
	eq(place, 3); eq(label, "third")
	Same(Keys(B.Next(br)), { "2.1" }, "only the final is left")
end)

test("arena bracket: plain ids work as entrants, and Matches lists a round top to bottom", function()
	local br = assert(B.Build({ "x", "y", "z" }))
	eq(br.size, 4); eq(br.seeds[1], "x"); eq(br.entrants.z.seed, 3)
	Same(Keys(B.Matches(br, 1)), { "1.1", "1.2" }); Same(Keys(B.Matches(br, 2)), { "2.1" })
	eq(#B.Matches(br, 3), 0); eq(#B.Matches(br, 0), 0)
	eq(B.Match(br, "1.1").a, "x"); eq(B.Match(br, "1.1").method, "B")
	eq(B.Match(br, "1.2").a, "y"); eq(B.Match(br, "1.2").b, "z")
end)

-- Results ----------------------------------------------------------------

test("arena bracket: impossible advances are refused", function()
	local br = assert(B.Build(Field(4))) -- 1.1 is 1 v 4, 1.2 is 2 v 3, 2.1 the final
	eq(select(2, B.Advance(br, "9.9", Id(1), "K")), "match")
	eq(select(2, B.Advance(br, nil, Id(1), "K")), "match")
	eq(select(2, B.Advance(br, "2.1", Id(1), "K")), "waiting", "the final before its semifinals")
	eq(select(2, B.Advance(br, "1.1", Id(2), "K")), "winner", "not in that match")
	eq(select(2, B.Advance(br, "1.1", nil, "K")), "winner")
	eq(select(2, B.Advance(br, "1.1", Id(1), "X")), "method")
	eq(select(2, B.Advance(br, "1.1", Id(1), "B")), "method", "a bye is the bracket's")
	eq(select(2, B.Advance(br, "1.1", Id(1), "N")), "method")
	eq(select(2, B.Game(br, "1.1", Id(1), "D")), "method", "a duel ends by knockout or flight")
	eq(select(2, B.Game(br, "9.9", Id(1), "K")), "match")
	eq(select(2, B.Game(br, "2.1", Id(1), "K")), "waiting", "a duel of the final before its semifinals")
	eq(select(2, B.Game(br, "1.1", Id(2), "K")), "winner", "not in that match")
	eq(select(2, B.Game(br, "1.1", nil, "K")), "winner")
	eq(#B.Match(br, "1.1").games, 0, "a refused duel is not recorded"); eq(B.Match(br, "1.1").sa, 0)
	assert(B.Advance(br, "1.1", Id(4), "R"))
	local m = B.Match(br, "1.1")
	eq(m.winner, Id(4)); eq(m.loser, Id(1)); eq(m.method, "R"); eq(m.sa, 0); eq(m.sb, 1)
	eq(B.Match(br, "2.1").a, Id(4), "the winner goes on")
	eq(select(2, B.Advance(br, "1.1", Id(4), "K")), "decided", "already decided")
	eq(select(2, B.Advance(br, "1.1", Id(1), "K")), "decided")
	eq(select(2, B.Game(br, "1.1", Id(4), "K")), "decided")
	local r, alive = B.Reached(br, Id(1))
	eq(r, 1); eq(alive, false)
	eq(B.Reaches(br, Id(1), "final"), false, "out in the semifinal")
	eq(B.Reaches(br, Id(4), "final"), true)
end)

test("arena bracket: a best-of-3 series game by game, and its score", function()
	local br = assert(B.Build(Field(4), { bo = 3 }))
	local ok, decided = B.Game(br, "1.1", Id(1), "K")
	eq(ok, true); eq(decided, false)
	ok, decided = B.Game(br, "1.1", Id(4), "R")
	eq(decided, false)
	local sa, sb, bo, need = B.Score(br, "1.1")
	eq(sa, 1); eq(sb, 1); eq(bo, 3); eq(need, 2)
	eq(B.Match(br, "1.1").done, nil)
	ok, decided = B.Game(br, "1.1", Id(1), "K")
	eq(decided, true)
	local m = B.Match(br, "1.1")
	eq(m.winner, Id(1)); eq(m.method, "K"); eq(#m.games, 3); eq(m.games[2].w, Id(4)); eq(m.games[2].m, "R")
	sa, sb = B.Score(br, "1.1")
	eq(sa, 2); eq(sb, 1)
	eq(B.Match(br, "2.1").a, Id(1))
	eq(select(2, B.Game(br, "1.1", Id(4), "K")), "decided")
	eq(select(2, B.Score(br, "7.1")), "match")
end)

test("arena bracket: a whole series at once needs a score that ends it", function()
	local br = assert(B.Build(Field(4), { bo = 3 }))
	eq(select(2, B.Advance(br, "1.2", Id(3), "K")), "score", "a bo3 needs its score")
	eq(select(2, B.Advance(br, "1.2", Id(3), "K", 3, 0)), "score")
	eq(select(2, B.Advance(br, "1.2", Id(3), "K", 1, 0)), "score", "not over at 1-0")
	eq(select(2, B.Advance(br, "1.2", Id(3), "K", 2, 2)), "score")
	eq(select(2, B.Advance(br, "1.2", Id(3), "K", 2)), "score")
	eq(select(2, B.Advance(br, "1.2", Id(3), "K", 2, -1)), "score")
	assert(B.Advance(br, "1.2", Id(3), "K", 2, 0))
	local sa, sb = B.Score(br, "1.2")
	eq(sa, 0, "seed 2 (side a) won nothing"); eq(sb, 2)
	-- a score never contradicts the games recorded
	assert(B.Game(br, "1.1", Id(4), "K"))
	eq(select(2, B.Advance(br, "1.1", Id(1), "K", 2, 0)), "score", "seed 4 already won one")
	assert(B.Advance(br, "1.1", Id(1), "K", 2, 1))
	-- bo1: 1-0 by default, and nothing else
	local one = assert(B.Build(Field(4)))
	eq(select(2, B.Advance(one, "1.2", Id(3), "K", 1, 1)), "score")
	assert(B.Advance(one, "1.2", Id(3), "K"))
	sa, sb = B.Score(one, "1.2")
	eq(sa, 0); eq(sb, 1)
end)

test("arena bracket: a disqualification or a walkover mid-series keeps the score so far", function()
	local br = assert(B.Build(Field(4), { bo = 5 }))
	assert(B.Game(br, "1.2", Id(2), "K"))
	assert(B.Game(br, "1.2", Id(2), "K"))
	eq(select(2, B.Advance(br, "1.2", Id(3), "D", 3, 0)), "score", "a DQ can't come with a won series")
	eq(select(2, B.Advance(br, "1.2", Id(3), "D", 0, 1)), "score", "nor undo the games recorded")
	assert(B.Advance(br, "1.2", Id(3), "D"))
	local m = B.Match(br, "1.2")
	eq(m.winner, Id(3)); eq(m.method, "D")
	local sa, sb = B.Score(br, "1.2")
	eq(sa, 2); eq(sb, 0)
	assert(B.Walkover(br, "1.1", Id(4)))
	m = B.Match(br, "1.1")
	eq(m.method, "W"); eq(m.winner, Id(4)); eq(m.sa, 0); eq(m.sb, 0)
	Same(Keys(B.Next(br)), { "2.1" }); eq(B.Match(br, "2.1").a, Id(4)); eq(B.Match(br, "2.1").b, Id(3))
end)

test("arena bracket: walkovers and a double no-show: the next opponent has a bye", function()
	local br = assert(B.Build(Field(4)))
	eq(select(2, B.Walkover(br, "1.1", Id(2))), "winner")
	eq(select(2, B.Walkover(br, "2.1", Id(1))), "waiting")
	assert(B.Walkover(br, "1.1", Id(4)))
	eq(B.Placing(br, Id(1)), 3); eq(select(2, B.Placing(br, Id(1))), "semifinal")
	eq(select(2, B.BothAbsent(br, "1.1")), "decided")
	eq(select(2, B.BothAbsent(br, "2.1")), "waiting")
	eq(select(2, B.BothAbsent(br, "0.0")), "match")
	assert(B.BothAbsent(br, "1.2"))
	local m = B.Match(br, "1.2")
	eq(m.method, "N"); eq(m.winner, false); eq(m.loser, false)
	local final = B.Match(br, "2.1")
	eq(final.b, false); eq(final.done, true); eq(final.method, "B"); eq(final.winner, Id(4))
	eq(B.Champion(br), Id(4)); eq(B.Finished(br), true); eq(B.CurrentRound(br), nil)
	eq(B.Placing(br, Id(4)), 1)
	-- both absent from their semifinal: no third place for either (Podium agrees)
	local place, label = B.Placing(br, Id(2))
	eq(place, false, "absent from the semifinal"); eq(label, "absent")
	eq(B.Placing(br, Id(3)), false)
	eq(B.Reaches(br, Id(2), "semifinal"), true, "he was placed there, for the markets")
	eq(B.Reaches(br, Id(2), "final"), false); eq(B.Reaches(br, Id(4), "champion"), true)
	local first, second, thirds = B.Podium(br)
	eq(first, Id(4)); eq(second, nil, "nobody lost the final"); Same(thirds, { Id(1) }, "the absent pair is not on the podium")
end)

test("arena bracket: a full eight with a third-place match: order of play, placings, markets, podium", function()
	local br = assert(B.Build(Field(8), { third = true })) -- 1v8, 4v5, 3v6, 2v7
	Same(Keys(B.Next(br)), { "1.1", "1.2", "1.3", "1.4" })
	eq(B.Reaches(br, Id(8), "quarterfinal"), true, "all eight are in the quarterfinals")
	eq(B.Reaches(br, Id(1), "champion"), nil)
	Favourites(br, nil, 1)
	eq(B.CurrentRound(br), 2)
	eq(B.Reaches(br, Id(5), "semifinal"), false); eq(B.Reaches(br, Id(4), "semifinal"), true)
	Same(Keys(B.Next(br)), { "2.1", "2.2" })
	assert(B.Advance(br, "2.1", Id(4), "K")) -- the upset: 4 beats 1
	assert(B.Advance(br, "2.2", Id(2), "R"))
	eq(B.CurrentRound(br), 3)
	Same(Keys(B.Next(br)), { "3.2", "3.1" }, "the third-place match before the final")
	eq(B.ThirdPlace(br).a, Id(1)); eq(B.ThirdPlace(br).b, Id(3))
	eq(B.Placing(br, Id(1)), nil, "his place waits for the third-place match")
	-- (was alive = false: the third-place match can still make him "3", so Reached is not
	-- settled yet; the "reaches" markets are, and his stage is 3 either way)
	local r, alive = B.Reached(br, Id(1))
	eq(r, 2); eq(alive, true, "he still plays for third")
	eq(B.Reaches(br, Id(1), "final"), false)
	eq(B.Champion(br), nil)
	assert(B.Advance(br, "3.2", Id(3), "K"))
	assert(B.Advance(br, "3.1", Id(2), "K"))
	eq(B.Finished(br), true)
	local want = { [2] = { 1, "champion" }, [4] = { 2, "final" }, [3] = { 3, "third" }, [1] = { 4, "fourth" },
		[5] = { 5, "quarterfinal" }, [6] = { 5, "quarterfinal" }, [7] = { 5, "quarterfinal" }, [8] = { 5, "quarterfinal" } }
	for i, w in pairs(want) do
		local place, label = B.Placing(br, Id(i))
		eq(place, w[1], "place of " .. i); eq(label, w[2], "label of " .. i)
	end
	eq(B.Reaches(br, Id(2), "champion"), true); eq(B.Reaches(br, Id(4), "champion"), false)
	eq(B.Reaches(br, Id(4), "final"), true); eq(B.Reaches(br, Id(4), 3), true); eq(B.Reaches(br, Id(4), 4), false)
	local ok, err = B.Reaches(br, Id(1), "last16")
	eq(ok, nil); eq(err, "stage", "no last 16 in a field of 8")
	eq(select(2, B.Reaches(br, Id(1), 5)), "stage"); eq(select(2, B.Reaches(br, Id(1), "semis")), "stage")
	eq(select(2, B.Reaches(br, "Player-9999-FFFFFFFF", "final")), "entrant")
	eq(select(2, B.Placing(br, "Player-9999-FFFFFFFF")), "entrant")
	local first, second, thirds = B.Podium(br)
	eq(first, Id(2)); eq(second, Id(4)); Same(thirds, { Id(3) })
end)

test("arena bracket: without a third-place match both semifinal losers share third", function()
	local br = assert(B.Build(Field(8)))
	Favourites(br)
	eq(B.Champion(br), Id(1))
	local place, label = B.Placing(br, Id(3))
	eq(place, 3); eq(label, "semifinal")
	eq(B.Placing(br, Id(4)), 3)
	local _, second, thirds = B.Podium(br)
	eq(second, Id(2)); Same(thirds, { Id(4), Id(3) })
end)

test("arena bracket: both absent from a semifinal: the final and third place go by byes", function()
	local br = assert(B.Build(Field(8), { third = true }))
	Favourites(br, nil, 1)
	assert(B.BothAbsent(br, "2.1")) -- 1 and 4
	assert(B.Advance(br, "2.2", Id(2), "K")) -- 2 beats 3
	eq(B.Finished(br), true)
	eq(B.Champion(br), Id(2)); eq(B.Match(br, "3.1").method, "B")
	eq(B.ThirdPlace(br).winner, Id(3)); eq(B.ThirdPlace(br).method, "B")
	local place, label = B.Placing(br, Id(3))
	eq(place, 3); eq(label, "third")
	place, label = B.Placing(br, Id(1))
	eq(place, false, "absent from his semifinal: no fourth place either"); eq(label, "absent")
	eq(B.Placing(br, Id(4)), false)
	eq(B.Reaches(br, Id(4), "semifinal"), true); eq(B.Reaches(br, Id(4), "final"), false)
	local first, second, thirds = B.Podium(br)
	eq(first, Id(2)); eq(second, nil); Same(thirds, { Id(3) })
end)

test("arena bracket: a semifinal lost by walkover still sends its loser to the third-place match", function()
	local br = assert(B.Build(Field(8), { third = true }))
	Favourites(br, nil, 1)
	assert(B.Walkover(br, "2.1", Id(4))) -- seed 1 did not come to his semifinal
	assert(B.Advance(br, "2.2", Id(2), "K"))
	local t = B.ThirdPlace(br)
	eq(t.a, Id(1), "the absent semifinalist plays for third"); eq(t.b, Id(3)); eq(t.done, nil)
	eq(B.Placing(br, Id(1)), nil, "his place waits for it")
	assert(B.Advance(br, "3.2", Id(1), "K"))
	local place, label = B.Placing(br, Id(1))
	eq(place, 3); eq(label, "third")
	place, label = B.Placing(br, Id(3))
	eq(place, 4); eq(label, "fourth")
	-- gone for good: he withdraws, and loses that match by walkover as soon as it has its other side
	br = assert(B.Build(Field(8), { third = true }))
	Favourites(br, nil, 1)
	assert(B.Walkover(br, "2.1", Id(4)))
	assert(B.Withdraw(br, Id(1)))
	eq(B.Placing(br, Id(1)), nil, "still in the third-place match")
	assert(B.Advance(br, "2.2", Id(2), "K"))
	t = B.ThirdPlace(br)
	eq(t.done, true); eq(t.method, "W"); eq(t.winner, Id(3))
	eq(B.Placing(br, Id(3)), 3); eq(B.Placing(br, Id(1)), 4)
	-- withdrawn while waiting in his semifinal: no place yet, not "semifinal"
	br = assert(B.Build(Field(8), { third = true }))
	assert(B.Advance(br, "1.1", Id(1), "K"))
	assert(B.Withdraw(br, Id(1)))
	eq(B.Placing(br, Id(1)), nil)
	eq(B.Reaches(br, Id(1), "final"), false)
end)

-- Placing's podium places are Podium's: 1 is first, 2 second, 3 in thirds, and nobody else.
local function Agrees(br, what)
	local first, second, thirds = B.Podium(br)
	local third = {}
	for _, id in ipairs(thirds) do third[id] = true end
	for id in pairs(br.entrants) do
		local place = B.Placing(br, id)
		eq(place == 1, id == first, what .. ": first, " .. id)
		eq(place == 2, id == second, what .. ": second, " .. id)
		eq(place == 3, third[id] == true, what .. ": third, " .. id)
	end
end

test("arena bracket: no-shows take no place, and Placing agrees with Podium", function()
	-- both absent from the final: nobody is champion or runner-up
	local br = assert(B.Build(Field(4)))
	assert(B.Advance(br, "1.1", Id(1), "K")); assert(B.Advance(br, "1.2", Id(2), "K"))
	assert(B.BothAbsent(br, "2.1"))
	eq(B.Finished(br), true); eq(B.Champion(br), nil)
	local place, label = B.Placing(br, Id(1))
	eq(place, false, "not the runner-up"); eq(label, "absent"); eq(B.Placing(br, Id(2)), false)
	eq(B.Reaches(br, Id(1), "final"), true); eq(B.Reaches(br, Id(1), "champion"), false)
	eq(B.Placing(br, Id(3)), 3, "a semifinal loser keeps third")
	local first, second, thirds = B.Podium(br)
	eq(first, nil); eq(second, nil); Same(thirds, { Id(4), Id(3) })
	Agrees(br, "final absent")
	-- both absent in the first round: out there, with no place
	br = assert(B.Build(Field(8)))
	assert(B.BothAbsent(br, "1.2")) -- 4 and 5
	Favourites(br)
	eq(B.Placing(br, Id(5)), false); eq(B.Placing(br, Id(6)), 5, "a quarterfinal loser")
	eq(B.Match(br, "2.1").method, "B", "seed 1 walks through")
	Agrees(br, "first round absent")
	-- a withdrawn finalist loses the final by walkover: the runner-up all the same
	br = assert(B.Build(Field(4)))
	assert(B.Advance(br, "1.1", Id(1), "K"))
	assert(B.Withdraw(br, Id(1)))
	assert(B.Advance(br, "1.2", Id(2), "K"))
	eq(B.Champion(br), Id(2)); eq(B.Placing(br, Id(1)), 2)
	Agrees(br, "final by walkover")
	-- and the full brackets, with and without a third-place match
	for _, third in ipairs({ true, false }) do
		br = assert(B.Build(Field(16), { third = third }))
		Favourites(br)
		Agrees(br, "favourites, third " .. tostring(third))
	end
end)

test("arena bracket: a withdrawn entrant loses his match by walkover, now or when his opponent arrives", function()
	local br = assert(B.Build(Field(8)))
	assert(B.Withdraw(br, Id(1)))
	local m = B.Match(br, "1.1")
	eq(m.method, "W"); eq(m.winner, Id(8)); eq(m.loser, Id(1))
	eq(select(2, B.Withdraw(br, Id(1))), "out")
	eq(select(2, B.Withdraw(br, "Player-9999-FFFFFFFF")), "entrant")
	assert(B.Advance(br, "1.3", Id(3), "K"))
	eq(select(2, B.Withdraw(br, Id(6))), "out", "already out")
	assert(B.Withdraw(br, Id(3))) -- waiting in 2.2 for the winner of 2 v 7
	eq(B.Match(br, "2.2").done, nil, "nothing to decide yet")
	eq(B.MatchOf(br, Id(3)).key, "2.2")
	-- he goes no further, whoever comes: the markets on him settle now
	local r, alive = B.Reached(br, Id(3))
	eq(r, 2); eq(alive, false, "withdrawn, though his match is not decided")
	eq(B.Reaches(br, Id(3), "semifinal"), true); eq(B.Reaches(br, Id(3), "final"), false)
	eq(B.Reaches(br, Id(3), "champion"), false)
	eq(B.Placing(br, Id(3)), nil, "his place waits for his match")
	assert(B.Advance(br, "1.4", Id(2), "K"))
	m = B.Match(br, "2.2")
	eq(m.done, true); eq(m.method, "W"); eq(m.winner, Id(2))
	r, alive = B.Reached(br, Id(3))
	eq(r, 2); eq(alive, false)
	local place, label = B.Placing(br, Id(3))
	eq(place, 3, "a semifinal lost by walkover"); eq(label, "semifinal")
end)

test("arena bracket: withdrawn against nobody, and both semifinal losers withdrawn: nobody goes on", function()
	local br = assert(B.Build(Field(8)))
	assert(B.Advance(br, "1.1", Id(1), "K"))
	assert(B.Withdraw(br, Id(1)))
	assert(B.BothAbsent(br, "1.2"))
	local m = B.Match(br, "2.1")
	eq(m.method, "N"); eq(m.winner, false)
	eq(B.Match(br, "3.1").a, false)
	local t = assert(B.Build(Field(4), { third = true }))
	assert(B.Advance(t, "1.1", Id(1), "K"))
	assert(B.Withdraw(t, Id(4))) -- waiting in the third-place match
	assert(B.Withdraw(t, Id(3)))
	eq(B.Match(t, "1.2").method, "W"); eq(B.Match(t, "1.2").winner, Id(2))
	m = B.ThirdPlace(t)
	eq(m.done, true); eq(m.method, "N")
	-- nobody played for third: neither is third or fourth (before, both were "fourth")
	eq(B.Placing(t, Id(4)), false); eq(select(2, B.Placing(t, Id(3))), "absent")
	local _, _, thirds = B.Podium(t)
	eq(#thirds, 0)
end)

test("arena bracket: MatchOf follows an entrant through the sheet", function()
	local br = assert(B.Build(Field(4)))
	eq(B.MatchOf(br, Id(1)).key, "1.1")
	assert(B.Advance(br, "1.1", Id(1), "K"))
	local m = B.MatchOf(br, Id(1))
	eq(m.key, "2.1"); eq(m.b, nil, "waiting for the other semifinal")
	eq(B.MatchOf(br, Id(4)), nil, "out")
	eq(B.MatchOf(br, nil), nil)
	eq(#B.Next(br), 1, "only the other semifinal is ready")
end)

-- Stages, sizes, and keeping a bracket -------------------------------------

test("arena bracket: 32 entrants: bo per stage, the favourites' placings, the round names", function()
	local br = assert(B.Build(Field(32), { bo = "135", third = true }))
	eq(br.rounds, 5)
	eq(B.RoundName(1, 5), "last32"); eq(B.RoundName(2, 5), "last16"); eq(B.RoundName(3, 5), "quarterfinal")
	eq(B.RoundName(4, 5), "semifinal"); eq(B.RoundName(5, 5), "final"); eq(B.RoundName(6, 5), "champion")
	eq(B.RoundName(0, 5), nil); eq(B.RoundName(7, 5), nil); eq(B.RoundName(1, 6), nil, "no bracket of 64")
	eq(B.RoundName(1, 2), "semifinal"); eq(B.RoundName(1, 1), nil, "no bracket of 2")
	Favourites(br)
	eq(B.Finished(br), true); eq(B.Champion(br), Id(1))
	eq(B.Match(br, "5.1").sa, 3, "a bo5 final"); eq(B.Match(br, "4.1").sa, 2, "bo3 semifinals"); eq(B.Match(br, "3.1").sa, 1)
	local function Check(i, place, label)
		local p, l = B.Placing(br, Id(i))
		eq(p, place, "place of " .. i); eq(l, label, "label of " .. i)
	end
	Check(1, 1, "champion"); Check(2, 2, "final"); Check(3, 3, "third"); Check(4, 4, "fourth")
	for i = 5, 8 do Check(i, 5, "quarterfinal") end
	for i = 9, 16 do Check(i, 9, "last16") end
	for i = 17, 32 do Check(i, 17, "last32") end
	eq(B.Reaches(br, Id(16), "last16"), true); eq(B.Reaches(br, Id(17), "last16"), false)
	eq(select(2, B.Reaches(br, Id(1), "last64")), "stage", "no last 64 any more")
end)

test("arena bracket: three entrants: seed 1 has a bye into the final", function()
	local br = assert(B.Build({ { id = "p1", name = "Morvenna" }, { id = "p2", name = "Quillon" }, { id = "p3", name = "Tamsel" } }))
	eq(br.size, 4); eq(br.rounds, 2)
	eq(B.RoundName(1, br.rounds), "semifinal")
	Same(Keys(B.Next(br)), { "1.2" }, "2 v 3, while 1 waits in the final")
	eq(B.Match(br, "2.1").a, "p1")
	assert(B.Advance(br, "1.2", "p3", "K"))
	assert(B.Advance(br, "2.1", "p3", "R"))
	eq(B.Champion(br), "p3")
	local place, label = B.Placing(br, "p1")
	eq(place, 2); eq(label, "final")
	place, label = B.Placing(br, "p2")
	eq(place, 3); eq(label, "semifinal")
	eq(select(2, B.Reaches(br, "p1", "quarterfinal")), "stage")
	local first, second, thirds = B.Podium(br)
	eq(first, "p3"); eq(second, "p1"); Same(thirds, { "p2" })
end)

test("arena bracket: a bracket shares no table inside, so a saved and reloaded copy plays on the same", function()
	local br = assert(B.Build(Field(11), { bo = "35", third = true }))
	assert(B.Advance(br, "1.2", Id(9), "K", 2, 1))
	assert(B.Game(br, "2.2", Id(4), "K"))
	local seen = {}
	local function Walk(t, path)
		assert(not seen[t], "shared table at " .. path .. " (also at " .. tostring(seen[t]) .. ")")
		seen[t] = path
		for k, v in pairs(t) do
			if type(v) == "table" then Walk(v, path .. "." .. tostring(k)) end
		end
	end
	Walk(br, "bracket")
	local saved = Copy(br)
	for _, b in ipairs({ br, saved }) do
		assert(B.Game(b, "2.2", Id(4), "K"))
		Favourites(b)
	end
	eq(B.Champion(saved), B.Champion(br)); eq(B.Champion(saved), Id(1))
	for i = 1, 11 do eq(B.Placing(saved, Id(i)), B.Placing(br, Id(i)), "place of " .. i) end
	eq(B.Match(saved, "3.1").b, B.Match(br, "3.1").b)
end)

-- The drawer's roll lines: the first valid roll per step (farkle W1) --------

-- A /roll line as ArenaParse.Roll reads it (value, low, high).
local function Line(roll, low, high) return { roll = roll, low = low, high = high } end
-- The drawer's word for a step (AD: step, roll and the step's max), as a spectator takes it.
local function Word(step, roll, max) return { step = step, roll = roll, max = max } end
local function Flags(list)
	local out = {}
	for i, f in ipairs(list) do out[i] = ("%d@%d:%s"):format(f.i, f.after, f.why) end
	return out
end
local FIVE = { "Player-9999-0000000A", "Player-9999-0000000B", "Player-9999-0000000C", "Player-9999-0000000D", "Player-9999-0000000E" }

test("arena bracket: the draw takes each step's first roll line only; a roll again is ignored and flagged", function()
	local lines = {
		Line(3, 1, 5), -- step 1
		Line(5, 1, 5), -- the same range again: extra
		Line(1, 1, 4), -- step 2
		Line(4, 1, 4), -- extra
		Line(2, 1, 5), -- step 1's range once more: extra
		Line(57, 1, 100), -- another roll: range
		Line(3, 1, 3), -- step 3
		Line(2, 1, 2), -- step 4: the last one left is placed without a roll
		Line(1, 1, 2), -- the draw is complete: done
		Line(1, 1, 1), -- done
	}
	local list, flags = B.ApplyDraw(FIVE, lines)
	assert(list, "the draw completes")
	Same(Ids(list), Ids(assert(B.ApplyDraw(FIVE, { 3, 1, 3, 2 }))), "the same draw as the first rolls alone")
	Same(Flags(flags), { "2@1:extra", "4@2:extra", "5@2:extra", "6@2:range", "9@4:done", "10@4:done" })
	local state = assert(B.DrawState(FIVE, lines))
	Same(state.rolls, { 3, 1, 3, 2 }, "the rolls taken, one per step")
	eq(state.step, nil, "complete")
	-- plain numbers flag nothing
	local _, none = B.ApplyDraw(FIVE, { 3, 1, 3, 2 })
	eq(#none, 0)
end)

test("arena bracket: rolling again gains nothing: whatever the second roll, the first one counts", function()
	for a = 1, 5 do
		local want = Ids(assert(B.ApplyDraw(FIVE, { a, 1, 1, 1 })))
		for b = 1, 5 do
			local lines = { Line(a, 1, 5), Line(b, 1, 5), Line(1, 1, 4), Line(1, 1, 3), Line(1, 1, 2) }
			local list, flags = B.ApplyDraw(FIVE, lines)
			Same(Ids(assert(list)), want, ("first %d, again %d"):format(a, b))
			Same(Flags(flags), { "2@1:extra" }, ("first %d, again %d"):format(a, b))
		end
	end
end)

test("arena bracket: a roll with another max is ignored, and the step is asked for again", function()
	local lines = {
		Line(4, 1, 6), -- a max above the field: range
		Line(2, 2, 5), -- not from 1: range
		Line(3, 1, 4), -- the next step's range, before its turn: range (not kept for later)
		Line(3, 1, 5), -- step 1
		Line(2, 1, 4), -- step 2: this one, not the early 1-4
	}
	local state = assert(B.DrawState(FIVE, lines))
	Same(state.rolls, { 3, 2 })
	eq(state.step, 3); eq(state.max, 3)
	Same(Flags(state.flags), { "1@0:range", "2@0:range", "3@0:range" })
	Same(Ids(state.list), { FIVE[3], FIVE[2] }, "C (3rd of A-E), then B (2nd of A B D E)")
	eq(select(2, B.ApplyDraw(FIVE, lines)), "rolls", "not complete yet")
	eq(select(3, B.ApplyDraw(FIVE, lines)), 3)
	-- the right range with a number outside it (no server line has one) is not the step's roll
	state = assert(B.DrawState(FIVE, { Line(6, 1, 5), Line(0, 1, 5), Line(2, 1, 5) }))
	Same(state.rolls, { 2 }); Same(Flags(state.flags), { "1@0:roll", "2@0:roll" })
end)

test("arena bracket: a witness's roll lines and a spectator's rolls from the drawer's word build the same sheet", function()
	local field = Field(11)
	local k = B.SeedCount(11) -- 4 seeds, 7 drawn, 6 rolls: 1-7, 1-6, ... 1-2
	local heard = {
		Line(40, 1, 100), Line(5, 1, 7), Line(7, 1, 7), Line(1, 1, 6), Line(4, 1, 5), Line(1, 1, 5),
		Line(2, 1, 4), Line(3, 1, 3), Line(9, 1, 20), Line(1, 1, 2), Line(2, 1, 2), Line(1, 1, 3),
	}
	local state = assert(B.DrawState(field, heard, k))
	eq(state.step, nil, "complete")
	Same(state.rolls, { 5, 1, 4, 2, 3, 1 }, "the rolls taken")
	Same(Flags(state.flags), { "1@0:range", "3@1:extra", "6@3:extra", "9@5:range", "11@6:done", "12@6:done" })
	-- the drawer's client sends one AD word per step taken: its step, roll and max (1-7 down to 1-2)
	local words = {}
	for s, roll in ipairs(state.rolls) do words[s] = Word(s, roll, 8 - s) end
	local fromLines, fromWords = assert(B.ApplyDraw(field, heard, k)), assert(B.ApplyDraw(field, words, k))
	Same(Ids(fromLines), Ids(fromWords))
	Same(assert(B.Build(fromLines)).slots, assert(B.Build(fromWords)).slots, "the same slots")
	Same(Ids(assert(B.ApplyDraw(field, state.rolls, k))), Ids(fromWords), "and the draw's own record, by step")
	-- a spectator who heard them out of order, one twice
	local shuffled = { words[2], words[1], words[4], words[3], words[1], words[6], words[5] }
	local list, flags = B.ApplyDraw(field, shuffled, k)
	Same(Ids(assert(list)), Ids(fromWords)); Same(Flags(flags), { "5@4:again" })
	-- a mix: the words for the steps he missed, then the lines he heard himself
	local mixed = { words[1], words[2], words[3], Line(2, 1, 4), Line(4, 1, 4), Line(3, 1, 3), Line(1, 1, 2) }
	list, flags = B.ApplyDraw(field, mixed, k)
	Same(Ids(assert(list)), Ids(fromWords)); Same(Flags(flags), { "5@4:extra" })
end)

test("arena bracket: the drawer's words count at their own step: one heard twice shifts nothing", function()
	local want = Ids(assert(B.ApplyDraw(FIVE, { 3, 1, 2, 1 })))
	Same(want, { FIVE[3], FIVE[1], FIVE[4], FIVE[2], FIVE[5] }, "c, a, d, b, e")
	-- The review's case: step 1's word heard twice. Taken as numbers appended as heard, the list
	-- read { 3, 3, 1, 2, 1 } and drew c, d, a, e, b with no flag. As words it is the true draw.
	local words = { Word(1, 3, 5), Word(1, 3, 5), Word(2, 1, 4), Word(3, 2, 3), Word(4, 1, 2) }
	local list, flags = B.ApplyDraw(FIVE, words)
	Same(Ids(assert(list)), want, "heard twice")
	Same(Flags(flags), { "2@1:again" })
	-- in any order, and without the max
	list, flags = B.ApplyDraw(FIVE, { Word(4, 1), Word(2, 1), Word(3, 2), Word(1, 3) })
	Same(Ids(assert(list)), want, "any order"); eq(#flags, 0)
	-- a second word for a step with another roll: the first heard counts, and it is flagged
	list, flags = B.ApplyDraw(FIVE, { Word(1, 3), Word(2, 1), Word(1, 5), Word(3, 2), Word(2, 4), Word(4, 1) })
	Same(Ids(assert(list)), want, "the first word counts"); Same(Flags(flags), { "3@2:differs", "5@3:differs" })
	-- the same for a word still waiting for the steps before it
	list, flags = B.ApplyDraw(FIVE, { Word(3, 2), Word(3, 1), Word(3, 2), Word(1, 3), Word(2, 1), Word(4, 1) })
	Same(Ids(assert(list)), want, "held, then taken"); Same(Flags(flags), { "2@0:differs", "3@0:again" })
	-- the last one left: a word of 1 for it is accepted, as a number is
	list, flags = B.ApplyDraw(FIVE, { Word(1, 3), Word(2, 1), Word(3, 2), Word(4, 1), Word(5, 1, 1) })
	Same(Ids(assert(list)), want); eq(#flags, 0)
	-- a line after a word for its step is a roll again, as after a line
	local state = assert(B.DrawState(FIVE, { Word(1, 3), Line(4, 1, 5), Line(1, 1, 4) }))
	Same(state.rolls, { 3, 1 }); Same(Flags(state.flags), { "2@1:extra" })
end)

test("arena bracket: a missing word leaves the draw at its step; bad words and numbers away from their step are refused", function()
	-- step 2's word never came: the draw stops there, and the words after it wait, flagged
	local state = assert(B.DrawState(FIVE, { Word(1, 3), Word(3, 2), Word(4, 1) }))
	Same(state.rolls, { 3 }); eq(state.step, 2); eq(state.max, 4)
	Same(Ids(state.list), { FIVE[3] })
	Same(Flags(state.flags), { "2@1:ahead", "3@1:ahead" })
	local list, err, step = B.ApplyDraw(FIVE, { Word(1, 3), Word(3, 2), Word(4, 1) })
	eq(list, nil); eq(err, "rolls"); eq(step, 2, "the step it misses")
	eq(B.NextRoll(5, { Word(1, 3), Word(3, 2), Word(4, 1) }), 2)
	-- once it comes, wherever it lands in the list, the draw completes
	local flags
	list, flags = B.ApplyDraw(FIVE, { Word(1, 3), Word(3, 2), Word(4, 1), Word(2, 1) })
	Same(Ids(assert(list)), { FIVE[3], FIVE[1], FIVE[4], FIVE[2], FIVE[5] }); eq(#flags, 0)
	-- a word whose roll or max is not its step's, or for a step the draw does not have
	local function Bad(rolls, code, at, what, seeds)
		local s, e, n = B.DrawState(FIVE, rolls, seeds)
		eq(s, nil, what); eq(e, code, what); eq(n, at, what)
	end
	Bad({ Word(1, 6) }, "roll", 1, "a roll over its step's max")
	Bad({ Word(1, 0) }, "roll", 1, "a roll of 0")
	Bad({ Word(1, 3), Word(3, 4) }, "roll", 3, "step 3 draws from 3, whenever it is heard")
	Bad({ Word(2, 2, 5) }, "roll", 2, "a max that is not step 2's")
	Bad({ Word(1, 3, "5") }, "roll", 1, "a max that is a string")
	Bad({ Word(1, 2.5) }, "roll", 1, "a roll that is not whole")
	Bad({ Word(1, "3") }, "roll", 1, "a roll that is a string")
	Bad({ Word(1, 3), Word(2, 1), Word(3, 2), Word(4, 1), Word(5, 2) }, "roll", 5, "the last one left is a 1")
	Bad({ Word(0, 1) }, "rolls", 1, "no step 0")
	Bad({ Word(1, 3), Word(6, 1) }, "rolls", 2, "no step 6 in a draw of five")
	Bad({ Word(1.5, 1) }, "rolls", 1, "no step 1.5")
	Bad({ Word("1", 1) }, "rolls", 1, "a step that is a string")
	Bad({ Word(1, 1) }, "rolls", 1, "all seeded: no step at all", 5)
	-- numbers are the rolls taken, by step: one away from its step's place is refused, so an
	-- entry before it that the draw did not take cannot shift it
	Bad({ Line(9, 1, 100), 3, 1, 2, 1 }, "rolls", 1, "a number after a line the draw did not take")
	Bad({ Word(1, 3), Word(1, 3), 1, 2, 1 }, "rolls", 2, "a number after a word heard twice")
	Bad({ Word(2, 1), 3, 1 }, "rolls", 1, "a number after a word held for later")
	Same(Ids(assert(B.ApplyDraw(FIVE, { 3, Word(2, 1), 2, Line(1, 1, 2) }))), { FIVE[3], FIVE[1], FIVE[4], FIVE[2], FIVE[5] },
		"numbers at their own steps, among words and lines")
end)

-- (These malformed lines were refused with "rolls" before, which one such line appended by a
-- client that checks with CheckRoll and keeps every line heard would turn into a broken draw;
-- they are now flagged with the why CheckRoll gives them, and the step stays open.)
test("arena bracket: roll lists: a line without whole numbers is flagged, never taken, and a number after the draw is complete is refused", function()
	local function Open(rolls, want, what)
		local state = assert(B.DrawState(FIVE, rolls), what)
		Same(state.rolls, {}, what .. ": nothing taken"); eq(state.step, 1, what); eq(state.max, 5, what)
		Same(Flags(state.flags), want, what)
	end
	Open({ Line("3", 1, 5) }, { "1@0:roll" }, "a roll that is a string")
	Open({ Line(2.5, 1, 5) }, { "1@0:roll" }, "a roll that is not whole")
	Open({ Line(0 / 0, 1, 5) }, { "1@0:roll" }, "a roll that is no number")
	Open({ { roll = 3 } }, { "1@0:range" }, "no range at all")
	Open({ Line(3, "1", 5), Line(3, 1, 5.5), Line(3, 1, 0 / 0) }, { "1@0:range", "2@0:range", "3@0:range" }, "a range that is not whole")
	local state = assert(B.DrawState(FIVE, { Line(3, 1, 5), Line(1, 1, 4.5), Line(2.5, 1, 4), Line(1, 1, 4) }))
	Same(state.rolls, { 3, 1 }, "step 2 is the first whole line with its range")
	Same(Flags(state.flags), { "2@1:range", "3@1:roll" })
	local list, flags = B.ApplyDraw(FIVE, { Line(3, 1, 5), Line(1, 1, 4), Line(3, 1, 3), Line(2, 1, 2), 1 })
	assert(list, "a 1 for the last one left is still accepted"); eq(#flags, 0)
	_, err, step = B.ApplyDraw(FIVE, { Line(3, 1, 5), Line(1, 1, 4), Line(3, 1, 3), Line(2, 1, 2), 1, 1 })
	eq(err, "rolls"); eq(step, 6)
	_, err, step = B.ApplyDraw(FIVE, { Line(3, 1, 5), nil, Line(1, 1, 4) })
	eq(err, "rolls", "a hole"); eq(step, 2)
end)

test("arena bracket: NextRoll and CheckRoll count only the lines the draw took", function()
	local s, max = B.NextRoll(5, { Line(3, 1, 5), Line(5, 1, 5), Line(9, 1, 100) })
	eq(s, 2); eq(max, 4)
	s, max = B.NextRoll(5, { Line("x", 1, 5) }) -- (was "rolls": a malformed line is flagged now)
	eq(s, 1, "a line that is no roll takes no step"); eq(max, 5)
	eq(select(2, B.CheckRoll(5, { Line(3, 1, 5) }, nil, 4, 1, 5)), "extra", "step 1's range again")
	eq(select(2, B.CheckRoll(5, { 3 }, nil, 4, 1, 5)), "extra", "after the drawer's word too")
	eq(select(2, B.CheckRoll(5, { Line(3, 1, 5) }, nil, 1, 1, 3)), "range", "a later step's range")
	eq(select(2, B.CheckRoll(5, { Line(3, 1, 5) }, nil, 5, 1, 4)), "roll")
	eq(select(2, B.CheckRoll(5, { Line(3, 1, 5) }, nil, 2, "1", 4)), "range")
	eq(select(2, B.CheckRoll(5, { Line(3, 1, 5) }, nil, 2.5, 1, 4)), "roll")
	local ok, step = B.CheckRoll(5, { Line(3, 1, 5), Line(5, 1, 5) }, nil, 2, 1, 4)
	eq(ok, true); eq(step, 2)
	-- the drawer's client checks each line against the ones before it: it keeps exactly the
	-- lines DrawState takes, and every other one is a flag
	local stream = { Line(2, 1, 5), Line(2, 1, 5), Line(8, 1, 10), Line(4, 1, 4), Line(1, 1, 3), Line(3, 1, 4),
		Line(2, 1, 2), Line(1, 1, 2) }
	local heard, kept = {}, {}
	for i, l in ipairs(stream) do
		if B.CheckRoll(5, heard, nil, l.roll, l.low, l.high) then kept[#kept + 1] = i end
		heard[i] = l
	end
	Same(kept, { 1, 4, 5, 7 })
	local state = assert(B.DrawState(FIVE, heard))
	Same(state.rolls, { 2, 4, 1, 2 })
	eq(#state.flags + #kept, #stream, "each line kept or flagged")
end)

test("arena bracket: CheckRoll's why is the flag DrawState gives that line, malformed lines included", function()
	-- A client that checks each line and keeps every line heard (as above) must never break its
	-- draw with one line. Before, a line CheckRoll called "roll" or "range" made DrawState refuse
	-- the whole list ("rolls").
	local stream = {
		Line(2.5, 1, 5), Line(2, 1, 5), Line(2, 1, 5), Line(3, "1", 4), { roll = 1 }, Line(4, 1, 4.5),
		Line(0 / 0, 1, 4), Line(9, 1, 4), Line(3, 1, 4), Line(1, 1, 2), Line(1, 1, 3), Line(2, 1, 2),
		Line("1", 1, 2), Line(1, 1, 2), Line(1, 1, 1),
	}
	local heard, want, kept = {}, {}, {}
	for i, l in ipairs(stream) do
		local ok, why = B.CheckRoll(5, heard, nil, l.roll, l.low, l.high)
		if ok then kept[#kept + 1] = i else want[#want + 1] = ("%d:%s"):format(i, why) end
		heard[i] = l
		assert(B.DrawState(FIVE, heard), "the draw still reads after line " .. i)
	end
	Same(want, { "1:roll", "3:extra", "4:range", "5:range", "6:range", "7:roll", "8:roll", "10:range", "13:done",
		"14:done", "15:done" })
	Same(kept, { 2, 9, 11, 12 })
	local state = assert(B.DrawState(FIVE, heard))
	local got = {}
	for j, f in ipairs(state.flags) do got[j] = ("%d:%s"):format(f.i, f.why) end
	Same(got, want, "the same whys")
	Same(state.rolls, { 2, 3, 1, 2 }); eq(state.step, nil, "complete")
end)

test("arena bracket: NextRange gives the drawer's next /roll and where its pick goes", function()
	local field, k, rolls = Field(11), 4, { 5, 1, 4, 2, 3, 1 }
	local br = assert(B.Build(assert(B.ApplyDraw(field, rolls, k))))
	for s = 1, #rolls do
		local state = assert(B.DrawState(field, First(rolls, s - 1), k))
		local lo, hi, step, pos = B.NextRange(state)
		local wantStep, wantMax = B.NextRoll(11, s - 1, k)
		eq(lo, 1, "from 1 at " .. s); eq(hi, wantMax, "max at " .. s); eq(step, wantStep); eq(step, s)
		eq(pos, B.PositionOf(16, k + s), "the AD slot at " .. s)
		eq(br.slots[pos], state.left[rolls[s]].id, "the roll's pick lands at pos, step " .. s)
	end
	eq(B.NextRange(assert(B.DrawState(field, rolls, k))), nil, "complete")
	eq(B.NextRange(assert(B.DrawState(field, nil, 10))), nil, "one left to draw needs no roll")
	-- from roll lines, the extra ones left out
	local lo, hi, step, pos = B.NextRange(assert(B.DrawState(FIVE, { Line(3, 1, 5), Line(5, 1, 5) })))
	eq(lo, 1); eq(hi, 4); eq(step, 2); eq(pos, B.PositionOf(8, 2))
	for _, bad in ipairs({ false, "state", { k = 0, size = 12, step = 1, max = 3 }, { k = 0, size = 8, step = 1, max = 1 },
		{ size = 8, step = 1, max = 3 }, { k = 9, size = 8, step = 1, max = 3 } }) do
		eq(select(2, B.NextRange(bad)), "state", tostring(bad))
	end
	eq(select(2, B.NextRange(nil)), "state")
end)

-- How far each went: Reached, Stage, Possible --------------------------------

test("arena bracket: Reached is the round lost, R + 1 for the champion, and \"3\" for the third-place winner", function()
	local br = assert(B.Build(Field(8), { third = true })) -- R = 3
	Favourites(br, nil, 1) -- 1, 4, 3, 2 go through; 8, 5, 6, 7 lose in round 1
	assert(B.Advance(br, "2.1", Id(1), "K"))
	assert(B.Advance(br, "2.2", Id(3), "K")) -- 3 beats 2
	-- The semifinal losers play on for third, so their value is not settled yet: the winner
	-- becomes "3". (This was alive = false, and then "3" after the third-place match: a value
	-- that moved after Reached had called it settled. Their stage is 3 either way.)
	local r, alive = B.Reached(br, Id(4))
	eq(r, 2, "lost his semifinal"); eq(alive, true, "he may yet be third")
	eq(B.Stage(r, br.rounds), 3)
	r, alive = B.Reached(br, Id(2))
	eq(r, 2); eq(alive, true)
	r, alive = B.Reached(br, Id(1))
	eq(r, 3, "in the final"); eq(alive, true)
	assert(B.Advance(br, "3.2", Id(4), "R")) -- 4 wins the third-place match
	r, alive = B.Reached(br, Id(4))
	eq(r, "3"); eq(alive, false)
	eq(B.Stage(r, br.rounds), 3)
	r, alive = B.Reached(br, Id(2))
	eq(r, 2, "the third-place loser lost his semifinal"); eq(alive, false)
	assert(B.Advance(br, "3.1", Id(3), "K"))
	r, alive = B.Reached(br, Id(3))
	eq(r, 4, "the champion: R + 1"); eq(alive, false)
	eq(B.Reached(br, Id(1)), 3, "lost the final")
	for i = 5, 8 do eq(B.Reached(br, Id(i)), 1, "lost in round 1: " .. i) end
	eq(select(2, B.Reached(br, "Player-9999-FFFFFFFF")), "entrant"); eq(select(2, B.Reached(br, nil)), "entrant")
	-- the markets' readings are unchanged by the "3"
	eq(B.Reaches(br, Id(4), "semifinal"), true); eq(B.Reaches(br, Id(4), "final"), false)
	eq(B.Placing(br, Id(4)), 3)
	-- a third place won by walkover is "3" as well; without a third-place match, nobody has it
	local w = assert(B.Build(Field(8), { third = true }))
	Favourites(w, nil, 2)
	assert(B.Walkover(w, "3.2", Id(3)))
	eq(B.Reached(w, Id(3)), "3"); eq(B.Reached(w, Id(4)), 2)
	local plain = assert(B.Build(Field(8)))
	Favourites(plain, nil, 2)
	r, alive = B.Reached(plain, Id(3))
	eq(r, 2); eq(alive, false, "no third-place match: settled when the semifinal is")
	Favourites(plain)
	eq(B.Reached(plain, Id(3)), 2); eq(B.Reached(plain, Id(4)), 2)
	-- a semifinal loser who has withdrawn can only lose the third-place match: settled at once,
	-- and it stays
	local wd = assert(B.Build(Field(8), { third = true }))
	Favourites(wd, nil, 1)
	assert(B.Advance(wd, "2.1", Id(1), "K")) -- 4 waits in the third-place match
	assert(B.Withdraw(wd, Id(4)))
	r, alive = B.Reached(wd, Id(4))
	eq(r, 2); eq(alive, false, "withdrawn: he can only lose it")
	assert(B.Advance(wd, "2.2", Id(2), "K"))
	eq(B.ThirdPlace(wd).method, "W"); eq(B.ThirdPlace(wd).winner, Id(3))
	r, alive = B.Reached(wd, Id(4))
	eq(r, 2, "unchanged"); eq(alive, false)
	eq(B.Reached(wd, Id(3)), "3")
end)

test("arena bracket: Stage counts from the top, the same in every size", function()
	local function Is(reached, R, stage, label)
		local s, l = B.Stage(reached, R)
		eq(s, stage, ("Stage(%s, %d)"):format(tostring(reached), R)); eq(l, label, ("label (%s, %d)"):format(tostring(reached), R))
	end
	Is(3, 2, 1, "champion"); Is(2, 2, 2, "final"); Is(1, 2, 3, "semifinal"); Is("3", 2, 3, "semifinal")
	Is(4, 3, 1, "champion"); Is(3, 3, 2, "final"); Is(2, 3, 3, "semifinal"); Is(1, 3, 4, "quarterfinal")
	Is(5, 4, 1, "champion"); Is(4, 4, 2, "final"); Is(3, 4, 3, "semifinal"); Is(2, 4, 4, "quarterfinal"); Is(1, 4, 5, "earlier")
	Is(6, 5, 1, "champion"); Is(5, 5, 2, "final"); Is(4, 5, 3, "semifinal"); Is(3, 5, 4, "quarterfinal")
	Is(2, 5, 5, "earlier"); Is(1, 5, 5, "earlier"); Is("3", 5, 3, "semifinal")
	for R = 2, 5 do
		eq(B.Stage(R + 1, R), 1); eq(B.Stage(R, R), 2); eq(B.Stage(R - 1, R), 3); eq(B.Stage("3", R), 3)
	end
	Same(B.STAGES, { "champion", "final", "semifinal", "quarterfinal", "earlier" })
	for _, bad in ipairs({ { 0, 3 }, { 5, 3 }, { "4", 3 }, { "3 ", 3 }, { 2.5, 3 }, { 0 / 0, 3 }, { true, 3 },
		{ 3, 1 }, { 3, 6 }, { 3, 2.5 }, { 3, 0 / 0 }, { 3, "3" } }) do
		local s, err = B.Stage(bad[1], bad[2])
		eq(s, nil, tostring(bad[1]) .. "," .. tostring(bad[2])); eq(err, "stage")
	end
	eq(select(2, B.Stage(nil, 3)), "stage"); eq(select(2, B.Stage(3, nil)), "stage")
end)

test("arena bracket: Possible lists the stages each size produces", function()
	Same(B.Possible(4), { 1, 2, 3 })
	Same(B.Possible(8), { 1, 2, 3, 4 })
	Same(B.Possible(16), { 1, 2, 3, 4, 5 })
	Same(B.Possible(32), { 1, 2, 3, 4, 5 })
	for _, bad in ipairs({ 2, 64, 12, 0, "8", 8.5 }) do
		local p, err = B.Possible(bad)
		eq(p, nil, tostring(bad)); eq(err, "size", tostring(bad))
	end
	eq(select(2, B.Possible(nil)), "size")
end)

-- The stages every entrant ends on, in stage order, and how many at each.
local function StagesOf(br)
	local count, seen = {}, {}
	for id in pairs(br.entrants) do
		local r, alive = B.Reached(br, id)
		eq(alive, false, "settled: " .. id)
		local s = assert(B.Stage(r, br.rounds))
		count[s] = (count[s] or 0) + 1
		seen[s] = true
	end
	local list = {}
	for s = 1, #B.STAGES do if seen[s] then list[#list + 1] = s end end
	return list, count
end

test("arena bracket: every field of 3 to 32 ends on exactly the stages Possible lists for its size", function()
	for n = 3, 32 do
		for _, third in ipairs({ false, true }) do
			local br = assert(B.Build(Field(n), { third = third }))
			Favourites(br)
			local list, count = StagesOf(br)
			local what = ("n %d third %s"):format(n, tostring(third))
			Same(list, assert(B.Possible(br.size)), what)
			eq(count[1], 1, what .. ": one champion"); eq(count[2], 1, what .. ": one runner-up")
		end
	end
end)

test("arena bracket: with any results, byes, withdrawals and no-shows, a settled Reached and its stage never change, and agree with Reaches", function()
	local seed = 20260930
	local function Rand(k)
		seed = seed * 16807 % 2147483647
		return seed % k + 1
	end
	local NAMES = { [2] = "final", [3] = "semifinal", [4] = "quarterfinal" }
	for trial = 1, 120 do
		local n = 3 + (trial - 1) % 30
		local br = assert(B.Build(Field(n), { third = trial % 2 == 0, bo = trial % 3 == 0 and "13" or 1 }))
		local possible = {}
		for _, s in ipairs(assert(B.Possible(br.size))) do possible[s] = true end
		local settled, value = {}, {}
		local function Check(what)
			for id in pairs(br.entrants) do
				local r, alive = B.Reached(br, id)
				if not alive then
					local s = assert(B.Stage(r, br.rounds))
					assert(possible[s], what .. ": stage " .. s .. " outside Possible(" .. br.size .. ")")
					if settled[id] then
						eq(s, settled[id], what .. ": the stage of " .. id .. " changed")
						eq(r, value[id], what .. ": Reached of " .. id .. " changed after it settled")
					end
					settled[id], value[id] = s, r
					-- the ST outcome and the "reaches" markets settle alike
					for stage, name in pairs(NAMES) do
						if stage <= br.rounds + 1 then
							eq(B.Reaches(br, id, name), s <= stage, what .. ": reaches " .. name .. " for " .. id)
						end
					end
					eq(B.Reaches(br, id, "champion"), s == 1, what .. ": champion " .. id)
				end
			end
		end
		local guard = 0
		while not B.Finished(br) do
			guard = guard + 1
			assert(guard < 200, "the bracket ends")
			local ready = B.Next(br)
			local roll = Rand(20)
			if roll == 1 and #ready > 0 then
				assert(B.BothAbsent(br, ready[Rand(#ready)].key))
			elseif roll == 2 then
				local alive = {}
				for id in pairs(br.entrants) do
					local _, a = B.Reached(br, id)
					if a then alive[#alive + 1] = id end
				end
				table.sort(alive)
				if #alive > 0 then assert(B.Withdraw(br, alive[Rand(#alive)])) end
			elseif #ready > 0 then
				local m = ready[Rand(#ready)]
				local w = Rand(2) == 1 and m.a or m.b
				local _, _, _, need = B.Score(br, m.key)
				assert(B.Advance(br, m.key, w, Rand(2) == 1 and "K" or "R", need, 0))
			end
			Check("trial " .. trial)
		end
		Check("trial " .. trial .. " finished")
		local champion = B.Champion(br)
		if champion then eq(settled[champion], 1, "trial " .. trial .. ": the champion's stage") end
	end
end)
