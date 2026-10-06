-- The Blood Arena's ratings (Olympus/ArenaRating.lua): Elo, anti-farming, records, rankings,
-- tiers and belts, on the real functions. The numbers asserted were worked out by hand and
-- with a separate script (integer Elo, halves rounded up as the design's floor(x + 0.5)),
-- never by the module.
local H = ...
local test, eq = H.test, H.eq

local ns = {}
assert(loadfile(H.ADDON_DIR .. "ArenaRating.lua"))("Olympus", ns)
local R = ns.ArenaRating

local MIN, HOUR, DAY, WEEK = 60, 3600, 86400, 7 * 86400
local T0 = 1790000000 -- a server time
local G = R.GLOBAL

-- A counted fight, knocked out in a minute, unless `extra` says otherwise.
local function Fight(id, a, b, winner, t, extra)
	local f = { id = id, a = a, b = b, winner = winner, method = "knockout", t = t, duration = 60,
		arbiter = "Judge-Oakhelm", counts = true }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

-- A fighter's rated fights against fresh sparring partners (one fight each, so they never
-- rank and no pair repeats): "WWL" is two wins then a defeat, an hour apart, from T0 or `at`.
local spar = 0
local function Ladder(list, key, results, facts, at)
	for i = 1, #results do
		spar = spar + 1
		local other = "Spar" .. spar
		local id = at and (key .. "@" .. at .. "#" .. i) or (key .. "#" .. i)
		local f = Fight(id, key, other, results:sub(i, i) == "W" and key or other, (at or T0) + i * HOUR)
		if facts then f.aClass, f.aRace = facts.class, facts.race end
		list[#list + 1] = f
	end
	return list
end

local function Deltas(built, key)
	local out = {}
	local recent = R.Recent(built, key, 1000)
	for i = #recent, 1, -1 do out[#out + 1] = recent[i].delta end
	return table.concat(out, ",")
end

local function Halvings(built, key)
	local out = {}
	local recent = R.Recent(built, key, 1000)
	for i = #recent, 1, -1 do out[#out + 1] = recent[i].halvings end
	return table.concat(out, ",")
end

local function Keys(list)
	local out = {}
	for i, r in ipairs(list) do out[i] = type(r) == "table" and (r.key or tostring(r.id)) or tostring(r) end
	return table.concat(out, ",")
end

-- Every fighter's numbers as one line, to compare two builds.
local function Table(built)
	local keys = {}
	for key in pairs(built.fighters) do keys[#keys + 1] = key end
	table.sort(keys)
	local out = {}
	for _, key in ipairs(keys) do
		local r = R.Record(built, key)
		out[#out + 1] = table.concat({ key, r.rating, r.peak, r.fights, r.wins, r.losses, r.fled, r.streak,
			r.woWins, r.woLosses, tostring(r.avgDuration) }, ":")
	end
	local ids = {}
	for i, e in ipairs(built.log) do ids[i] = tostring(e.id) .. "=" .. e.aDelta .. "/" .. e.bDelta end
	return table.concat(out, " ") .. " | " .. table.concat(ids, " ")
end

local function Reigns(state, cat)
	local out = {}
	for i, r in ipairs(R.Lineage(state, cat)) do
		out[i] = table.concat({ r.holder, r.since, tostring(r.fight), tostring(r.from), r.defences, tostring(r.ends),
			tostring(r.how), tostring(r.to) }, ":")
	end
	return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Elo
---------------------------------------------------------------------------

test("arena rating: the expected score is in per mille, both sides add up to 1000, gaps past 800 count as 800", function()
	eq(R.Expected(1500, 1500), 500)
	eq(R.Expected(1500, 1600), 360)
	eq(R.Expected(1500, 1900), 91)
	eq(R.Expected(1900, 1500), 909)
	eq(R.Expected(1500, 2300), 10, "an 800 gap")
	eq(R.Expected(1500, 3000), 10, "a 1500 gap counts as 800")
	eq(R.Expected(3000, 1500), 990)
	local before = 1000
	for gap = 0, 1200 do
		local e = R.Expected(1500, 1500 + gap)
		eq(e + R.Expected(1500 + gap, 1500), 1000, "gap " .. gap)
		assert(e <= before and e == math.floor(e), "an integer that never grows with the gap (" .. gap .. ")")
		before = e
	end
end)

-- The design rounds with floor(x + 0.5): the first version rounded -1.5 to -2 (halves away
-- from zero), which the design never asked for; -1.5 is -1 now.
test("arena rating: a change rounds halves up, K is 40 for 10 fights, then 24, then 16 from 2000; halvings are capped", function()
	eq(R.Delta(1500, 1500, true, 40, 0), 20)
	eq(R.Delta(1500, 1500, false, 24, 0), -12)
	eq(R.Delta(1500, 1500, true, 24, 3), 2, "1.5 rounds up")
	eq(R.Delta(1500, 1500, false, 24, 3), -1, "and -1.5 up too: floor(-1.5 + 0.5)")
	eq(R.Delta(1500, 1900, true, 24, 0), 22, "an upset pays")
	eq(R.Delta(1500, 1900, false, 24, 0), -2, "losing to the favourite costs little")
	eq(R.Delta(1500, 1500, true, 40, 16), 0)
	eq(R.Delta(1500, 1500, true, 40, 5000), 0, "a huge count of halvings is still a number")
	eq(R.KFactor(nil), 40)
	eq(R.KFactor(0), 40)
	eq(R.KFactor(9), 40, "the 10th fight")
	eq(R.KFactor(10), 24, "the 11th fight")
	eq(R.KFactor(10, false, 1999), 24)
	eq(R.KFactor(10, false, 2000), 16, "from 2000 up")
	eq(R.KFactor(0, true, 2400), 16, "settled at 2400")
	eq(R.KFactor(3, false, 2100), 40, "provisional first, whatever the rating")
	eq(R.KFactor(12, false, 0 / 0), 24, "a rating that is no number")
end)

test("arena rating: K 16 from a rating of 2000 up, taken before each fight; a provisional fighter stays at 40", function()
	local start = {
		Top = { rating = 2000, settled = true }, Edge = { rating = 1999, settled = true },
		Fresh = { rating = 2100 }, Climber = { rating = 1990, settled = true },
		Giant1 = { rating = 2300, settled = true }, Giant2 = { rating = 2300, settled = true },
	}
	local built = R.Build({
		Fight("h1", "Top", "NewA", "NewA", T0),
		Fight("h2", "Edge", "NewB", "NewB", T0),
		Fight("h3", "Fresh", "NewC", "NewC", T0),
		Fight("h4", "Climber", "Giant1", "Climber", T0 + HOUR),
		Fight("h5", "Climber", "Giant2", "Climber", T0 + 2 * HOUR),
	}, start)
	eq(Deltas(built, "Top"), "-15", "16 x -947 / 1000 = -15.152 (K 24 would give -23)")
	eq(Deltas(built, "NewA"), "38", "the newcomer at K 40")
	eq(Deltas(built, "Edge"), "-23", "a point under 2000: K 24")
	eq(Deltas(built, "Fresh"), "-39", "carried at 2100 but not settled: K 40")
	eq(Deltas(built, "Climber"), "21,13", "K 24 from 1990 to 2011, then K 16 (K 24 would give 20)")
	eq(R.Rating(built, "Climber"), 2024)
	eq(Deltas(built, "Giant1"), "-14", "the giant loses at K 16")
end)

test("arena rating: a first fight moves both fighters 20 from 1500; someone never seen is at 1500 with 0 fights", function()
	local built = R.Build({ Fight("f1", "Varkoth", "Mirelle", "Varkoth", T0) })
	local r, n = R.Rating(built, "Varkoth")
	eq(r, 1520); eq(n, 1)
	r, n = R.Rating(built, "Mirelle")
	eq(r, 1480); eq(n, 1)
	r, n = R.Rating(built, "Nobody")
	eq(r, 1500); eq(n, 0)
	r, n = R.Rating(R.Build(nil), "Varkoth")
	eq(r, 1500, "no fights at all"); eq(n, 0)
end)

test("arena rating: K is 40 for a fighter's first 10 rated fights and 24 from the 11th; a newcomer still loses at 40", function()
	local fights = {}
	for i = 1, 11 do fights[#fights + 1] = Fight("k" .. i, "Varkoth", "Rookie" .. i, "Varkoth", T0 + i * HOUR) end
	local built = R.Build(fights)
	eq(Deltas(built, "Varkoth"), "20,19,18,17,16,15,14,13,13,12,7")
	eq(R.Rating(built, "Varkoth"), 1664)
	eq(R.Recent(built, "Rookie11", 1)[1].delta, -12, "the rookie's own K is 40")
	eq(R.Rating(built, "Rookie11"), 1488)
end)

test("arena rating: the same two within 24 h weigh 1, 1/2, 1/4; past 24 h a fight weighs 1 again", function()
	local built = R.Build({
		Fight("p1", "Varkoth", "Mirelle", "Varkoth", T0),
		Fight("p2", "Varkoth", "Mirelle", "Varkoth", T0 + HOUR),
		Fight("p3", "Mirelle", "Varkoth", "Varkoth", T0 + 2 * HOUR), -- the sides swapped: still the same pair
		Fight("p4", "Varkoth", "Mirelle", "Mirelle", T0 + 2 * HOUR + DAY),
	})
	eq(Halvings(built, "Varkoth"), "0,1,2,0")
	eq(Deltas(built, "Varkoth"), "20,9,4,-24")
	eq(Deltas(built, "Mirelle"), "-20,-9,-4,24")
	eq(R.Rating(built, "Varkoth"), 1509)
	eq(R.Rating(built, "Mirelle"), 1491)
end)

test("arena rating: the 24 h window slides and ends at exactly 24 h; another opponent doesn't halve anything", function()
	local inside = R.Build({ Fight("w1", "Varkoth", "Mirelle", "Varkoth", T0), Fight("w2", "Varkoth", "Mirelle", "Varkoth", T0 + DAY - 1) })
	eq(Halvings(inside, "Varkoth"), "0,1", "a second short of 24 h")
	local outside = R.Build({ Fight("w1", "Varkoth", "Mirelle", "Varkoth", T0), Fight("w2", "Varkoth", "Mirelle", "Varkoth", T0 + DAY) })
	eq(Halvings(outside, "Varkoth"), "0,0", "24 h to the second")
	local mixed = R.Build({
		Fight("m1", "Varkoth", "Mirelle", "Varkoth", T0),
		Fight("m2", "Varkoth", "Tazdun", "Varkoth", T0 + MIN),
		Fight("m3", "Varkoth", "Mirelle", "Varkoth", T0 + 2 * MIN),
		Fight("m4", "Varkoth", "Tazdun", "Varkoth", T0 + 3 * MIN),
	})
	eq(Halvings(mixed, "Varkoth"), "0,0,1,1")
end)

test("arena rating: a walkover moves no rating, counts in no K, pair or streak, and shows in the fighter's fights", function()
	local built = R.Build({
		Fight("o1", "Varkoth", "Mirelle", "Varkoth", T0, { duration = 60 }),
		Fight("o2", "Varkoth", "Mirelle", "Varkoth", T0 + HOUR, { method = "walkover", duration = 5 }),
		Fight("o3", "Mirelle", "Varkoth", "Varkoth", T0 + 2 * HOUR, { duration = 90 }),
	})
	eq(Deltas(built, "Varkoth"), "20,0,9", "the third fight is the pair's second rated one: halved once")
	eq(Halvings(built, "Varkoth"), "0,0,1")
	eq(R.Rating(built, "Varkoth"), 1529)
	eq(R.Rating(built, "Mirelle"), 1471)
	local v, m = R.Record(built, "Varkoth"), R.Record(built, "Mirelle")
	eq(v.fights, 2); eq(v.wins, 2); eq(v.woWins, 1); eq(v.woLosses, 0); eq(v.streak, 2)
	eq(v.avgDuration, 75, "the walkover's 5 s are no fight")
	eq(m.fights, 2); eq(m.losses, 2); eq(m.woLosses, 1); eq(m.streak, -2)
	local wo = R.Recent(built, "Varkoth", 3)[2]
	eq(wo.id, "o2"); eq(wo.method, "walkover"); eq(wo.rated, false); eq(wo.delta, 0); eq(wo.won, true); eq(wo.rating, 1520)
end)

test("arena rating: a walkover doesn't count toward K: the 10th rated fight is still at 40 after one", function()
	local fights = {}
	for i = 1, 9 do fights[i] = Fight("kw" .. i, "Varkoth", "Rookie" .. i, "Varkoth", T0 + i * HOUR) end
	fights[10] = Fight("kw10", "Varkoth", "Rookie10", "Varkoth", T0 + 10 * HOUR, { method = "walkover" })
	fights[11] = Fight("kw11", "Varkoth", "Rookie11", "Varkoth", T0 + 11 * HOUR)
	local built = R.Build(fights)
	eq(Deltas(built, "Varkoth"), "20,19,18,17,16,15,14,13,13,0,12", "12 at K 40 (K 24 would give 7)")
	eq(select(2, R.Rating(built, "Varkoth")), 10)
	eq(R.Rating(built, "Varkoth"), 1657)
end)

---------------------------------------------------------------------------
-- What counts
---------------------------------------------------------------------------

test("arena rating: fights that don't count, rehearsals and broken records are left out, each with its reason", function()
	local good = Fight("ok", "Varkoth", "Mirelle", "Varkoth", T0)
	local bad = {
		Fight("n1", "Varkoth", "Mirelle", "Mirelle", T0 + 1, { counts = false }),
		Fight("n2", "Varkoth", "Mirelle", "Mirelle", T0 + 2, { counts = "yes" }),
		Fight("n3", "Varkoth", "Mirelle", "Mirelle", T0 + 3, { rehearsal = true }),
		Fight("n4", "Varkoth", "Mirelle", "Tazdun", T0 + 4),
		Fight("n5", "Varkoth", "Varkoth", "Varkoth", T0 + 5),
		Fight("n6", "Varkoth", "Mirelle", "Mirelle", T0 + 6, { method = "draw" }),
		Fight("n7", "Varkoth", "Mirelle", "Mirelle", T0 + 7, { t = "soon" }),
		Fight("n8", "Varkoth", "Mirelle", "Mirelle", 0 / 0),
		Fight("", "Varkoth", "Mirelle", "Mirelle", T0 + 9),
		Fight("n10", "Varkoth", "Mirelle", "Mirelle", T0 + 10, { arbiter = "Mirelle" }),
		Fight("n11", "Varkoth", nil, "Varkoth", T0 + 11),
		"a line of text",
	}
	local nocount = Fight("n12", "Varkoth", "Mirelle", "Mirelle", T0 + 12)
	nocount.counts = nil
	bad[#bad + 1] = nocount
	local fights = { good }
	for _, f in ipairs(bad) do fights[#fights + 1] = f end
	local built = R.Build(fights)
	eq(#built.log, 1)
	eq(R.Rating(built, "Varkoth"), 1520)
	eq(R.Rating(built, "Mirelle"), 1480)
	eq(R.Rating(built, "Tazdun"), 1500)
	eq(#built.skipped, #bad)
	local why = {}
	for _, s in ipairs(built.skipped) do why[s.why] = (why[s.why] or 0) + 1 end
	eq(why["not counted"], 3); eq(why.rehearsal, 1); eq(why.winner, 1); eq(why.fighters, 2); eq(why.method, 1)
	eq(why.time, 2); eq(why.id, 1); eq(why.arbiter, 1); eq(why["not a fight"], 1)
	local ok, reason = R.Check(bad[3])
	eq(ok, false); eq(reason, "rehearsal")
	eq(R.Check(good), true)
	-- { arbiter = nil } would be an empty table and keep the default arbiter: take it off the fight.
	local unjudged = Fight("x", "Varkoth", "Mirelle", "Mirelle", T0)
	unjudged.arbiter = nil
	eq(R.Check(unjudged), true, "an arbiter is not required here (the ledger decides who judged)")
end)

test("arena rating: an id seen twice counts once, and the same record is kept whatever order they came in", function()
	local early = Fight("dup", "Varkoth", "Mirelle", "Varkoth", T0)
	local late = Fight("dup", "Varkoth", "Mirelle", "Mirelle", T0 + 5)
	for _, fights in ipairs({ { early, late }, { late, early } }) do
		local built = R.Build(fights)
		eq(#built.log, 1)
		eq(R.Rating(built, "Varkoth"), 1520, "the earlier record kept")
		eq(#built.skipped, 1); eq(built.skipped[1].why, "duplicate")
	end
	local x = Fight("same", "Varkoth", "Mirelle", "Varkoth", T0)
	local y = Fight("same", "Varkoth", "Mirelle", "Mirelle", T0)
	local one, other = R.Build({ x, y }), R.Build({ y, x })
	eq(#one.log, 1)
	eq(Table(one), Table(other), "a tie in time is broken by the records' fields")
	local n = R.Build({ Fight(7, "Varkoth", "Mirelle", "Varkoth", T0), Fight("7", "Varkoth", "Mirelle", "Varkoth", T0 + 1) })
	eq(#n.log, 1, "7 and \"7\" are one id")
end)

-- tostring of NaN and infinity differs between Windows and Mac clients, so such an id would
-- sort and match differently on each.
test("arena rating: an id is a whole number or a non-empty string; a duration past DURATION_MAX is left out", function()
	for _, id in ipairs({ 0 / 0, math.huge, -math.huge, 1.5, {}, true }) do
		local ok, why = R.Check(Fight(id, "Varkoth", "Mirelle", "Varkoth", T0))
		eq(ok, false, tostring(id)); eq(why, "id", tostring(id))
	end
	eq(R.Check(Fight(42, "Varkoth", "Mirelle", "Varkoth", T0)), true)
	eq(R.Check(Fight(-3, "Varkoth", "Mirelle", "Varkoth", T0)), true)
	eq(R.DURATION_MAX, 3 * HOUR)
	local built = R.Build({
		Fight("u1", "Varkoth", "Mirelle", "Varkoth", T0, { duration = math.huge }),
		Fight("u2", "Varkoth", "Tazdun", "Varkoth", T0 + 1, { duration = 0 / 0 }),
		Fight("u3", "Varkoth", "Oskren", "Varkoth", T0 + 2, { duration = 3 * HOUR + 1 }),
		Fight("u4", "Varkoth", "Pellwyn", "Varkoth", T0 + 3, { duration = -5 }),
		Fight("u5", "Varkoth", "Grusha", "Varkoth", T0 + 4, { duration = "long" }),
		Fight("u6", "Varkoth", "Brunna", "Varkoth", T0 + 5, { duration = 90 }),
		Fight("u7", "Varkoth", "Cedrik", "Varkoth", T0 + 6, { duration = 3 * HOUR }),
	})
	eq(#built.log, 7, "each still counts")
	eq(R.Record(built, "Varkoth").fights, 7)
	eq(R.Record(built, "Varkoth").avgDuration, 5445, "(90 + 10800) / 2: the broken ones left out")
	eq(R.Record(built, "Mirelle").avgDuration, nil)
	eq(R.Recent(built, "Varkoth", 7)[7].duration, nil, "u1's infinity is shown as no duration")
end)

test("arena rating: the same fights in any order, as a list or keyed by id, give the same table, all integers", function()
	local names = { "Varkoth", "Mirelle", "Tazdun", "Oskren", "Pellwyn", "Grusha" }
	local methods = { "knockout", "knockout", "fled", "walkover" }
	local seed, fights = 12345, {}
	local function Next(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
	for i = 1, 90 do
		local a = Next(#names)
		local b = (a + Next(#names - 1) - 1) % #names + 1
		local f = Fight("g" .. i, names[a], names[b], Next(2) == 1 and names[a] or names[b], T0 + math.floor(i / 3) * 600,
			{ method = methods[Next(#methods)], duration = 10 + Next(200) })
		fights[#fights + 1] = f
	end
	local base = R.Build(fights)
	eq(#base.log, 90)
	local reversed, shuffled, keyed = {}, {}, {}
	for i = #fights, 1, -1 do reversed[#reversed + 1] = fights[i] end
	for i, f in ipairs(fights) do shuffled[i] = f end
	for i = #shuffled, 2, -1 do
		local j = Next(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	for _, f in ipairs(fights) do keyed[f.id] = f end
	eq(Table(R.Build(reversed)), Table(base))
	eq(Table(R.Build(shuffled)), Table(base))
	eq(Table(R.Build(keyed)), Table(base))
	for key in pairs(base.fighters) do
		local r = R.Rating(base, key)
		eq(r, math.floor(r), key .. "'s rating is an integer")
	end
end)

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

test("arena rating: a record counts wins, knocked-out defeats and fled ones apart, with the streak, KO rate, time and peak", function()
	local built = R.Build({
		Fight("r1", "Varkoth", "Brunna", "Varkoth", T0, { duration = 30, aClass = "WA", aRace = 2 }),
		Fight("r2", "Varkoth", "Cedrik", "Varkoth", T0 + HOUR, { method = "fled", duration = 45 }),
		Fight("r3", "Dagny", "Varkoth", "Dagny", T0 + 2 * HOUR, { duration = 90, bClass = "PA" }),
		Fight("r4", "Varkoth", "Eldor", "Eldor", T0 + 3 * HOUR, { method = "fled", duration = 20, aClass = "", aRace = "" }),
		Fight("r5", "Varkoth", "Fenna", "Varkoth", T0 + 4 * HOUR, { duration = 61 }),
		Fight("r6", "Varkoth", "Gorm", "Varkoth", T0 + 5 * HOUR, { duration = 40, aRace = 5 }),
	})
	local v = R.Record(built, "Varkoth")
	eq(v.fights, 6); eq(v.wins, 4); eq(v.losses, 1); eq(v.fled, 1)
	eq(v.streak, 2)
	eq(v.koWins, 3); eq(v.koRate, 75)
	eq(v.avgDuration, 48, "286 s over 6 fights")
	eq(v.class, "PA", "the latest weigh-in (as b), kept through fights without one and an empty one")
	eq(v.race, 5, "the latest weigh-in")
	eq(v.last, T0 + 5 * HOUR, "the time of his latest counted fight")
	eq(v.rating, R.Rating(built, "Varkoth"))
	local peak = R.START
	for _, e in ipairs(R.Recent(built, "Varkoth", 10)) do if e.rating > peak then peak = e.rating end end
	eq(v.peak, peak)
	assert(v.peak > v.rating, "the defeats came after the peak")
	local c = R.Record(built, "Cedrik")
	eq(c.fled, 1, "Cedrik fled"); eq(c.losses, 0); eq(c.streak, -1)
	local e = R.Record(built, "Eldor")
	eq(e.wins, 1); eq(e.koRate, 0, "his win was Varkoth fleeing")
	local none = R.Record(built, "Nobody")
	eq(none.rating, 1500); eq(none.fights, 0); eq(none.streak, 0); eq(none.koRate, nil); eq(none.avgDuration, nil)
end)

test("arena rating: Recent gives the last fights newest first, 10 unless told, from the fighter's side", function()
	local fights = {}
	for i = 1, 12 do fights[i] = Fight(("c%02d"):format(i), "Rookie" .. i, "Varkoth", "Varkoth", T0 + i * HOUR) end
	local built = R.Build(fights)
	local recent = R.Recent(built, "Varkoth")
	eq(#recent, 10)
	eq(recent[1].id, "c12"); eq(recent[10].id, "c03")
	eq(recent[1].opponent, "Rookie12"); eq(recent[1].won, true); eq(recent[1].opponentRating, 1500)
	eq(recent[1].rating, R.Rating(built, "Varkoth"))
	eq(recent[1].method, "knockout"); eq(recent[1].duration, 60); eq(recent[1].rated, true)
	eq(#R.Recent(built, "Varkoth", 3), 3)
	eq(#R.Recent(built, "Varkoth", "3"), 3, "a number as text")
	eq(#R.Recent(built, "Varkoth", "lots"), 10, "no number: the default")
	eq(#R.Recent(built, "Varkoth", 0), 0)
	eq(#R.Recent(built, "Nobody"), 0)
	local rookie = R.Recent(built, "Rookie12")
	eq(#rookie, 1); eq(rookie[1].opponent, "Varkoth"); eq(rookie[1].won, false)
	eq(rookie[1].rating, R.Rating(built, "Rookie12")); eq(rookie[1].opponentRating, recent[2].rating)
end)

test("arena rating: head to head counts each side's wins and knockouts, walkovers apart, newest first", function()
	local built = R.Build({
		Fight("h1", "Varkoth", "Mirelle", "Varkoth", T0),
		Fight("h2", "Mirelle", "Varkoth", "Mirelle", T0 + 2 * DAY, { method = "fled" }),
		Fight("h3", "Varkoth", "Mirelle", "Varkoth", T0 + 4 * DAY, { method = "walkover" }),
		Fight("h4", "Varkoth", "Mirelle", "Mirelle", T0 + 6 * DAY),
		Fight("h5", "Varkoth", "Tazdun", "Varkoth", T0 + 7 * DAY),
	})
	local h = R.HeadToHead(built, "Varkoth", "Mirelle")
	eq(h.fights, 3); eq(h.walkovers, 1)
	eq(h.wins.Varkoth, 1); eq(h.wins.Mirelle, 2)
	eq(h.knockouts.Varkoth, 1); eq(h.knockouts.Mirelle, 1)
	eq(Keys(h.list), "h4,h3,h2,h1")
	eq(h.list[1].opponent, "Mirelle"); eq(h.list[1].won, false)
	local back = R.HeadToHead(built, "Mirelle", "Varkoth")
	eq(back.wins.Mirelle, 2); eq(back.wins.Varkoth, 1); eq(back.list[1].won, true)
	local self = R.HeadToHead(built, "Varkoth", "Varkoth")
	eq(self.fights, 0); eq(#self.list, 0)
	local never = R.HeadToHead(built, "Varkoth", "Nobody")
	eq(never.fights, 0); eq(never.wins.Nobody, 0); eq(never.wins.Varkoth, 0)
	eq(R.HeadToHead(built, nil, "Varkoth").fights, 0, "a missing name is no error")
	eq(R.HeadToHead(nil, "Varkoth", "Mirelle").fights, 0, "nor a missing table")
end)

---------------------------------------------------------------------------
-- Categories, rankings, tiers
---------------------------------------------------------------------------

test("arena rating: categories are A, C<class code> and R<race ID>, read back by ParseCategory", function()
	eq(R.ClassCategory("MA"), "CMA")
	eq(R.RaceCategory(4), "R4"); eq(R.RaceCategory("4"), "R4")
	eq(R.ClassCategory(nil), nil)
	eq(R.ClassCategory(""), nil, "Roster.ClassCode's answer for an unknown class"); eq(R.RaceCategory(""), nil)
	eq(R.RaceCategory(0 / 0), nil); eq(R.ClassCategory({}), nil)
	eq(R.ParseCategory(G), "global")
	local kind, value = R.ParseCategory("CMA")
	eq(kind, "class"); eq(value, "MA")
	kind, value = R.ParseCategory("R4")
	eq(kind, "race"); eq(value, "4")
	eq(R.ParseCategory("X1"), nil); eq(R.ParseCategory("C"), nil); eq(R.ParseCategory(5), nil); eq(R.ParseCategory(nil), nil)
end)

test("arena rating: rankings list the fighters with 5 rated fights, best first, equal ratings sharing a rank, per class and race", function()
	local fights = {}
	Ladder(fights, "Varkoth", "WWWWW", { class = "WA", race = 2 })
	Ladder(fights, "Mirelle", "WWWWL", { class = "MA", race = 1 })
	Ladder(fights, "Tazdun", "WWWWL", { class = "MA", race = 4 })
	Ladder(fights, "Oskren", "WWWW", { class = "MA", race = 1 })
	Ladder(fights, "Pellwyn", "LLLLL")
	local built = R.Build(fights)
	local global = R.Ranking(built, G)
	eq(Keys(global), "Varkoth,Mirelle,Tazdun,Pellwyn", "Oskren has 4 fights; the sparring partners one")
	eq(Keys(R.Ranking(built)), Keys(global), "global unless told")
	eq(global[1].rating, 1590); eq(global[1].fights, 5)
	eq(global[2].rating, global[3].rating, "the same results, the same rating")
	eq(global[1].rank, 1); eq(global[2].rank, 2); eq(global[3].rank, 2); eq(global[4].rank, 4)
	eq(#R.Ranking(built, G, 0), 5 + 4 * 5 + 4, "everyone, sparring partners too")
	eq(Keys(R.Ranking(built, "CMA")), "Mirelle,Tazdun")
	eq(Keys(R.Ranking(built, "CMA", 1)), "Oskren,Mirelle,Tazdun", "Oskren's 4 wins, when 1 fight is enough")
	eq(Keys(R.Ranking(built, R.RaceCategory(4))), "Tazdun")
	eq(Keys(R.Ranking(built, "R1")), "Mirelle")
	eq(#R.Ranking(built, "X1"), 0)
	eq(R.InCategory(built, "Tazdun", "CMA"), true)
	eq(R.InCategory(built, "Tazdun", "CWA"), false)
	eq(R.InCategory(built, "Pellwyn", G), true)
	eq(R.InCategory(built, "Nobody", G), false)
	eq(table.concat(R.Categories(built), ","), "A,CMA,CWA,R1,R2,R4")
	eq(#R.Categories(R.Build({})), 0)
end)

test("arena rating: an empty class or race is no weigh-in: no category \"C\" or \"R\", and the last real one stays", function()
	local built = R.Build({
		Fight("y1", "Varkoth", "Mirelle", "Varkoth", T0, { aClass = "WA", aRace = 2, bClass = "", bRace = "" }),
		Fight("y2", "Varkoth", "Mirelle", "Varkoth", T0 + DAY, { aClass = "", aRace = "" }),
	})
	eq(table.concat(R.Categories(built), ","), "A,CWA,R2")
	local v, m = R.Record(built, "Varkoth"), R.Record(built, "Mirelle")
	eq(v.class, "WA"); eq(v.race, 2); eq(m.class, nil); eq(m.race, nil)
	eq(R.InCategory(built, "Varkoth", "CWA"), true)
end)

test("arena rating: equal ratings rank the fighter with more rated fights first, then by key", function()
	local built = R.Build({
		Fight("e1", "Alpha", "Spar-e1", "Alpha", T0),
		Fight("e2", "Champ", "Spar-e2", "Champ", T0 + HOUR),
		Fight("e3", "Champ", "Alpha", "Champ", T0 + 2 * HOUR),                    -- 1520 against 1520: -20
		Fight("e4", "Adrok", "Aenwe", "Adrok", T0 + 3 * HOUR, { method = "walkover" }), -- 1500, no rated fight
	})
	eq(R.Rating(built, "Alpha"), 1500, "a win, then a defeat at even odds")
	local ranked = R.Ranking(built, G, 0)
	eq(Keys(ranked), "Champ,Alpha,Adrok,Aenwe,Spar-e1,Spar-e2")
	eq(ranked[2].rank, 2); eq(ranked[3].rank, 2); eq(ranked[4].rank, 2); eq(ranked[5].rank, 5); eq(ranked[6].rank, 5)
end)

test("arena rating: 10 ranked fighters make 1 gold, 2 silver, 3 bronze and 4 without; the unranked get none", function()
	local seqs = {
		Six = "WWWWWW", FiveA = "WWWWWL", FiveB = "LWWWWW", FourA = "WWWWLL", FourB = "LLWWWW",
		ThreeA = "WWWLLL", ThreeB = "LLLWWW", Two = "WWLLLL", One = "LLLLLW", Zero = "LLLLLL",
	}
	local fights = {}
	for key, s in pairs(seqs) do Ladder(fights, key, s) end
	Ladder(fights, "Fourwin", "WWWW")
	local built = R.Build(fights)
	local ranked = R.Ranking(built, G)
	eq(#ranked, 10)
	for i = 2, #ranked do assert(ranked[i].rating < ranked[i - 1].rating, "distinct ratings for this test") end
	local tiers = R.Tiers(built)
	local count = {}
	for key, tier in pairs(tiers) do count[tier] = (count[tier] or 0) + 1; assert(seqs[key], key .. " is ranked") end
	eq(count.gold, 1); eq(count.silver, 2); eq(count.bronze, 3)
	eq(tiers.Six, "gold"); eq(tiers.Zero, nil); eq(tiers.Fourwin, nil, "4 fights: unranked")
	local want = { "gold", "silver", "silver", "bronze", "bronze", "bronze" }
	for i, r in ipairs(ranked) do eq(tiers[r.key], want[i], "place " .. i) end
end)

test("arena rating: tiers with few ranked fighters: 1 bronze; 2 silver; 3 silver, bronze; 5 gold, silver, bronze", function()
	local function TiersOf(seqs)
		local fights = {}
		for i, s in ipairs(seqs) do Ladder(fights, "Few" .. i, s) end
		local tiers, out = R.Tiers(R.Build(fights)), {}
		for i = 1, #seqs do out[i] = tiers["Few" .. i] or "-" end
		return table.concat(out, ",")
	end
	eq(TiersOf({}), "")
	eq(TiersOf({ "WWWWW" }), "bronze")
	eq(TiersOf({ "WWWWW", "LLLLL" }), "silver,-")
	eq(TiersOf({ "WWWWW", "WWWLL", "LLLLL" }), "silver,bronze,-")
	eq(TiersOf({ "WWWWW", "WWWLL", "WWLLL", "LLLLL" }), "silver,bronze,-,-")
	eq(TiersOf({ "WWWWW", "WWWWL", "WWWLL", "WWLLL", "LLLLL" }), "gold,silver,bronze,-,-")
end)

test("arena rating: equal ratings share the better tier, and tiers can be taken within a class", function()
	local fights = {}
	Ladder(fights, "TieA", "WWWWW", { class = "MA" })
	Ladder(fights, "TieB", "WWWWW", { class = "MA" })
	Ladder(fights, "Mid", "WWWLL", { class = "MA" })
	Ladder(fights, "Low", "WWLLL", { class = "RO" })
	Ladder(fights, "Last", "LLLLL", { class = "RO" })
	local built = R.Build(fights)
	local tiers = R.Tiers(built)
	eq(tiers.TieA, "gold"); eq(tiers.TieB, "gold", "tied for the one gold place")
	eq(tiers.Mid, "bronze", "third place: past the 2 places gold and silver hold together")
	eq(tiers.Low, nil); eq(tiers.Last, nil)
	-- Three mages: no gold (10% of 3 rounds to 0), one place for silver and one for bronze;
	-- the tie shares the silver place, so the third mage is third, past both.
	local mages = R.Tiers(built, "CMA")
	eq(mages.TieA, "silver"); eq(mages.TieB, "silver"); eq(mages.Mid, nil); eq(mages.Low, nil)
end)

---------------------------------------------------------------------------
-- Seasons: the carry-over
---------------------------------------------------------------------------

test("arena rating: the carry-over takes a rating halfway back to 1500, rounded down", function()
	local vectors = {
		{ 1500, 1500 }, { 1700, 1600 }, { 1701, 1600 }, { 1699, 1599 }, { 2000, 1750 }, { 1501, 1500 },
		{ 1499, 1499 }, { 1300, 1400 }, { 1301, 1400 }, { 1299, 1399 }, { 900, 1200 },
	}
	for _, v in ipairs(vectors) do eq(R.CarryOver(v[1]), v[2], tostring(v[1])) end
	for _, bad in ipairs({ "1600", 0 / 0, math.huge, -math.huge }) do eq(R.CarryOver(bad), 1500, tostring(bad)) end
end)

test("arena rating: Carry gives each fighter his carried rating, settled after 10 rated fights, with his class and race", function()
	local fights = {}
	for i = 1, 11 do fights[i] = Fight("k" .. i, "Varkoth", "Rookie" .. i, "Varkoth", T0 + i * HOUR, { aClass = "WA", aRace = 2 }) end
	for i = 1, 9 do fights[#fights + 1] = Fight("m" .. i, "Mirelle", "Novice" .. i, "Mirelle", T0 + i * HOUR) end
	fights[#fights + 1] = Fight("m10", "Mirelle", "Novice10", "Mirelle", T0 + 10 * HOUR, { method = "walkover" })
	local built = R.Build(fights)
	eq(R.Rating(built, "Varkoth"), 1664); eq(R.Rating(built, "Rookie11"), 1488)
	local carry = R.Carry(built)
	eq(carry.Varkoth.rating, 1582, "1500 + floor(164 / 2)"); eq(carry.Varkoth.settled, true, "11 rated fights")
	eq(carry.Varkoth.class, "WA"); eq(carry.Varkoth.race, 2)
	eq(carry.Rookie11.rating, 1494, "1500 + floor(-12 / 2)"); eq(carry.Rookie11.settled, false)
	eq(carry.Mirelle.settled, false, "9 rated fights and a walkover")
	local ten = {}
	for i = 1, 10 do ten[i] = Fight("n" .. i, "Tazdun", "Pupil" .. i, "Tazdun", T0 + i * HOUR) end
	eq(R.Carry(R.Build(ten)).Tazdun.settled, true, "exactly 10 rated fights")
	eq(carry.Novice10.rating, 1500, "a walkover moved nothing")
	eq(next(R.Carry(R.Build({}))), nil)
	eq(next(R.Carry(nil)), nil)
end)

test("arena rating: a season starts from the carried ratings; a settled fighter is at K 24 from his first fight", function()
	local start = {
		Vet = { rating = 1600, settled = true, class = "WA", race = 2 },
		Kid = { rating = 1600 },
		Idle = { rating = 1450, settled = true, class = "MA", race = 4 },
	}
	local built = R.Build({
		Fight("s1", "Vet", "NewA", "Vet", T0),
		Fight("s2", "Kid", "NewB", "Kid", T0),
	}, start)
	eq(R.Recent(built, "Vet", 1)[1].delta, 9, "24 x 360 / 1000 = 8.64: K 24 at once")
	eq(R.Recent(built, "Kid", 1)[1].delta, 14, "40 x 360 / 1000 = 14.4: not settled, still K 40")
	eq(R.Recent(built, "NewA", 1)[1].delta, -14, "the newcomer at K 40 against a carried 1600")
	eq(R.Rating(built, "Vet"), 1609); eq(R.Rating(built, "Kid"), 1614); eq(R.Rating(built, "NewA"), 1486)
	local r, n = R.Rating(built, "Idle")
	eq(r, 1450, "carried, no fight yet this season"); eq(n, 0)
	local idle = R.Record(built, "Idle")
	eq(idle.peak, 1450); eq(idle.settled, true); eq(idle.class, "MA"); eq(idle.last, nil)
	eq(R.Record(built, "Vet").settled, true); eq(R.Record(built, "Kid").settled, false)
	eq(R.InCategory(built, "Idle", "CMA"), true, "known in his class table before his first fight")
	eq(#R.Ranking(built, "CMA"), 0, "but ranked only with this season's fights")
	eq(R.Tiers(built).Idle, nil)
	eq(R.KFactor(0, true), 24); eq(R.KFactor(0, "yes"), 40, "only true settles")
	-- A start entry that is not what Carry writes: that fighter starts at 1500 like anyone.
	local broken = {
		A1 = { rating = "1600" }, A2 = { rating = 1600.5 }, A3 = { rating = 0 / 0 }, A4 = { rating = 2 ^ 40 },
		A5 = 1600, [7] = { rating = 1600 }, [""] = { rating = 1600 },
	}
	local b = R.Build({ Fight("s3", "A1", "A2", "A1", T0) }, broken)
	eq(R.Rating(b, "A1"), 1520); eq(R.Rating(b, "A2"), 1480)
	for _, key in ipairs({ "A3", "A4", "A5" }) do eq(R.Rating(b, key), 1500, key); eq(b.fighters[key], nil, key) end
	eq(R.Rating(R.Build({}, "text"), "Vet"), 1500, "a start that is no table")
	-- The round trip: last season's table, carried, starts the next.
	local last = R.Build({ Fight("t1", "Vet", "Kid", "Vet", T0) }, start)
	local nextSeason = R.Build({ Fight("t2", "Vet", "Kid", "Kid", T0 + 60 * DAY) }, R.Carry(last))
	eq(R.Recent(nextSeason, "Vet", 1)[1].opponentRating, R.CarryOver(R.Rating(last, "Kid")))
	-- Settled is earned again each season (the design: 10 rated fights last season): carried in
	-- as settled with fewer this season, he starts the next one provisional.
	local carried = R.Carry(built)
	eq(carried.Vet.settled, false, "settled last season, 1 rated fight this one")
	eq(carried.Idle.settled, false, "settled last season, no fight this one")
	eq(carried.Idle.rating, 1475, "1500 + floor(-50 / 2)"); eq(carried.Idle.class, "MA")
end)

---------------------------------------------------------------------------
-- Belts
---------------------------------------------------------------------------

local VAC = 6 * WEEK -- VACANT_WEEKS' default, in seconds

-- A rated title fight the ledger lets move its belt (`belt` = true), unless `extra` says
-- otherwise.
local function Title(id, a, b, winner, t, cat, extra)
	local f = Fight(id, a, b, winner, t)
	f.title, f.belt = cat, true
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

local function Word(id, kind, cat, gk, t, extra)
	local w = { id = id, kind = kind, cat = cat, gk = gk, t = t }
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end

local function Undo(id, ref, t, by, king)
	return { id = id, kind = "U", ref = ref, t = t, by = by, king = king }
end

-- The words Belts left out, as "id:why", in its order.
local function Why(belts)
	local out = {}
	for i, s in ipairs(belts.ignored) do out[i] = tostring(s.id) .. ":" .. s.why end
	return table.concat(out, ",")
end

-- Everything Belts worked out, as one line, to compare two runs.
local function Summary(belts)
	local cats = {}
	for cat in pairs(belts.belts) do cats[#cats + 1] = cat end
	table.sort(cats)
	local out = {}
	for _, cat in ipairs(cats) do
		local b = R.Belt(belts, cat)
		out[#out + 1] = table.concat({ cat, Reigns(belts, cat), tostring(b.contender), tostring(b.contenderUntil),
			tostring(b.podium[2]), tostring(b.podium[3]) }, "|")
	end
	return table.concat(out, " / ") .. " // " .. Why(belts)
end

-- Summary without the words left out: what every client shows.
local function State(belts)
	return (Summary(belts):gsub(" // .*$", ""))
end

-- A reign's title wins as "fight>beaten@seconds after T0".
local function Wins(reign)
	local out = {}
	for i, w in ipairs(reign.wins) do out[i] = tostring(w.fight) .. ">" .. tostring(w.beat) .. "@" .. (w.t - T0) end
	return table.concat(out, ",")
end

test("arena rating: a vacant belt is won, defended, kept through a non-title defeat, and changes hands only in a title defeat", function()
	local fights = {
		Title("b1", "Varkoth", "Mirelle", "Varkoth", T0, G),
		Title("b2", "Tazdun", "Varkoth", "Varkoth", T0 + DAY, G),
		Fight("b3", "Mirelle", "Varkoth", "Mirelle", T0 + 2 * DAY),                           -- no title at stake
		Title("b4", "Tazdun", "Varkoth", "Tazdun", T0 + 3 * DAY, G, { belt = false }),         -- rated, but no belt
		Title("b5", "Mirelle", "Tazdun", "Mirelle", T0 + 4 * DAY, G),                          -- without the holder
		Title("b6", "Tazdun", "Varkoth", "Tazdun", T0 + 5 * DAY, G, { method = "walkover" }),  -- not in the ring
		Title("b7", "Varkoth", "Mirelle", "Mirelle", T0 + 6 * DAY, G, { method = "fled" }),
	}
	local now = T0 + 7 * DAY
	local function Upto(n)
		local some = {}
		for i = 1, n do some[i] = fights[i] end
		return R.Belts(some, nil, now)
	end
	eq(R.Holder(Upto(0), G), nil, "never held")
	eq(R.Belt(Upto(0), G), nil)
	local s = Upto(1)
	local holder, reign = R.Holder(s, G)
	eq(holder, "Varkoth"); eq(reign.since, T0); eq(reign.fight, "b1"); eq(reign.from, nil); eq(reign.defences, 0)
	for n = 2, 6 do
		local b = R.Belt(Upto(n), G)
		eq(b.holder, "Varkoth", "after fight " .. n); eq(b.defences, 1, "after fight " .. n)
		eq(b.last, T0 + DAY); eq(b.vacatesAt, T0 + DAY + VAC); eq(b.count, 1)
	end
	s = Upto(7)
	local b = R.Belt(s, G)
	eq(b.holder, "Mirelle"); eq(b.since, T0 + 6 * DAY); eq(b.defences, 0); eq(b.from, "Varkoth"); eq(b.fight, "b7"); eq(b.count, 2)
	eq(Reigns(s, G), "Varkoth:" .. T0 .. ":b1:nil:1:" .. (T0 + 6 * DAY) .. ":lost:Mirelle Mirelle:" .. (T0 + 6 * DAY) .. ":b7:Varkoth:0:nil:nil:nil")
	eq(R.Lineage(s, G)[1].lostIn, "b7")
	eq(Wins(R.Lineage(s, G)[1]), "b1>Mirelle@0,b2>Tazdun@86400", "the fight that crowned him, then the defence")
	eq(Wins(R.Lineage(s, G)[2]), "b7>Varkoth@518400")
	eq(R.Lineage(s, G)[1].vacates, T0 + DAY + VAC); eq(R.Lineage(s, G)[2].vacates, T0 + 6 * DAY + VAC)
	eq(#R.Lineage(s, "CMA"), 0)
	eq(R.BeltsOf(s, "Mirelle")[1], G); eq(#R.BeltsOf(s, "Varkoth"), 0)
	local walk = R.Belts({ Title("v1", "Varkoth", "Mirelle", "Varkoth", T0, G, { method = "walkover" }) })
	eq(R.Belt(walk, G), nil, "a walkover wins no vacant belt either")
	eq(Summary(R.Belts(nil, nil)), " // ", "nothing at all")
end)

-- The first version let only rated title fights (counts = true) touch a belt, so the rating
-- caps the ledger works out (the design) decided belts: a holder knocked out in 12 s kept
-- his belt, and one could shield it by making the title fight the pair's 4th of the week.
-- A client holding only the core `titles` can't work those caps out either.
test("arena rating: a title fight moves its belt rated or not (a 12 s knockout, a pair's 4th of the week); belt = true decides", function()
	local won = Title("q1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	local quick = Title("q2", "Varkoth", "Mirelle", "Mirelle", T0 + DAY, G, { duration = 12, counts = false })
	local s = R.Belts({ won, quick }, nil, T0 + 2 * DAY)
	eq(R.Holder(s, G), "Mirelle", "knocked out in 12 s: the belt changes hands")
	eq(R.Lineage(s, G)[1].how, "lost"); eq(R.Lineage(s, G)[1].lostIn, "q2")
	local built = R.Build({ won, quick })
	eq(#built.log, 1, "while the rating leaves it out"); eq(R.Rating(built, "Mirelle"), 1480)
	-- Three defences against the same challenger in a week, then the 4th, unrated by the pair's cap.
	local week = { won }
	for i = 1, 3 do week[#week + 1] = Title("q" .. (2 + i), "Varkoth", "Mirelle", "Varkoth", T0 + i * DAY, G) end
	week[#week + 1] = Title("q6", "Mirelle", "Varkoth", "Mirelle", T0 + 4 * DAY, G, { counts = false })
	s = R.Belts(week, nil, T0 + 5 * DAY)
	eq(R.Holder(s, G), "Mirelle", "the pair's 4th fight of the week still takes the belt")
	eq(R.Lineage(s, G)[1].defences, 3)
	-- A client holding the title fights without any `counts` gets the same belts.
	local bare = {}
	for i, f in ipairs(week) do
		local copy = {}
		for k, v in pairs(f) do copy[k] = v end
		copy.counts = nil
		bare[i] = copy
	end
	eq(Summary(R.Belts(bare, nil, T0 + 5 * DAY)), Summary(s))
	-- Only belt = true lets a title fight touch its belt: false (an alt, net-off, no public
	-- arbiter), anything else, or no flag, rated or not.
	for _, flag in ipairs({ false, "yes", 1 }) do
		s = R.Belts({ won, Title("q7", "Varkoth", "Mirelle", "Mirelle", T0 + DAY, G, { belt = flag }) }, nil, T0 + 2 * DAY)
		eq(R.Holder(s, G), "Varkoth", tostring(flag)); eq(R.Belt(s, G).defences, 0, tostring(flag))
	end
	local unflagged = Title("q8", "Varkoth", "Mirelle", "Mirelle", T0 + DAY, G)
	unflagged.belt = nil
	eq(R.Holder(R.Belts({ won, unflagged }, nil, T0 + 2 * DAY), G), "Varkoth", "no flag")
	eq(R.Belt(R.Belts({ unflagged }), G), nil, "nor does it win a vacant belt")
end)

test("arena rating: CheckTitle says why a fight can't touch a belt; whether it was rated is not asked", function()
	local mages = { aClass = "MA", bClass = "MA" }
	local function Mage(id, a, b, winner, t, extra)
		local f = Title(id, a, b, winner, t, "CMA", mages)
		for k, v in pairs(extra or {}) do f[k] = v end
		return f
	end
	eq(R.CheckTitle(Mage("ct", "Varkoth", "Mirelle", "Varkoth", T0, { counts = false })), true, "unrated")
	eq(R.CheckTitle(Mage("ct", "Varkoth", "Mirelle", "Varkoth", T0, { method = "fled" })), true)
	local cases = {
		{ "a line of text", "not a fight" },
		{ Mage("t1", "Varkoth", "Mirelle", "Varkoth", T0, { rehearsal = true }), "rehearsal" },
		{ Fight("t2", "Varkoth", "Mirelle", "Varkoth", T0, { belt = true }), "no title" },
		{ Mage("t3", "Varkoth", "Mirelle", "Varkoth", T0, { belt = false }), "no belt" },
		{ Mage("", "Varkoth", "Mirelle", "Varkoth", T0), "id" },
		{ Mage("t5", "Varkoth", "Varkoth", "Varkoth", T0), "fighters" },
		{ Mage("t6", "Varkoth", "Mirelle", "Tazdun", T0), "winner" },
		{ Mage("t7", "Varkoth", "Mirelle", "Varkoth", T0, { method = "draw" }), "method" },
		{ Mage("t8", "Varkoth", "Mirelle", "Varkoth", 0 / 0), "time" },
		{ Mage("t9", "Varkoth", "Mirelle", "Varkoth", T0, { arbiter = "Mirelle" }), "arbiter" },
		{ Mage("t10", "Varkoth", "Mirelle", "Varkoth", T0, { method = "walkover" }), "walkover" },
		{ Mage("t11", "Varkoth", "Mirelle", "Varkoth", T0, { bClass = "WA" }), "category" },
		{ Mage("t12", "Varkoth", "Mirelle", "Varkoth", T0, { title = "X1" }), "category" },
	}
	for _, case in ipairs(cases) do
		local ok, why = R.CheckTitle(case[1])
		eq(ok, false, case[2]); eq(why, case[2])
	end
end)

test("arena rating: a rehearsal never touches a belt, even a title fight marked as counting", function()
	local s = R.Belts({ Title("rh1", "Varkoth", "Mirelle", "Varkoth", T0, G, { rehearsal = true }) })
	eq(R.Belt(s, G), nil, "no belt won in a rehearsal")
	s = R.Belts({
		Title("rh2", "Varkoth", "Mirelle", "Varkoth", T0, G),
		Title("rh3", "Mirelle", "Varkoth", "Mirelle", T0 + DAY, G, { rehearsal = true }),
		Title("rh4", "Varkoth", "Tazdun", "Varkoth", T0 + 2 * DAY, G, { rehearsal = true }),
	}, nil, T0 + 3 * DAY)
	local b = R.Belt(s, G)
	eq(b.holder, "Varkoth", "not lost in a rehearsal"); eq(b.defences, 0, "nor defended in one"); eq(b.count, 1)
	eq(b.vacatesAt, T0 + VAC, "a rehearsal doesn't start the clock again")
end)

test("arena rating: a class or race belt is fought between two of that class or race, by the fight's own weigh-in", function()
	local s = R.Belts({
		Title("c1", "Mirelle", "Varkoth", "Mirelle", T0, "CMA", { aClass = "MA", bClass = "WA" }),
		Title("c2", "Mirelle", "Tazdun", "Tazdun", T0 + HOUR, "CMA", { aClass = "MA" }),
		Title("c3", "Tazdun", "Oskren", "Oskren", T0 + 2 * HOUR, "R4", { aRace = 4, bRace = "4" }),
		Title("c4", "Tazdun", "Oskren", "Tazdun", T0 + 3 * HOUR, "X9"),
		Title("c5", "Tazdun", "Oskren", "Tazdun", T0 + 4 * HOUR, "C", { aClass = "", bClass = "" }),
		Title("c6", "Tazdun", "Oskren", "Tazdun", T0 + 5 * HOUR, "CMA", { aClass = "MA", bClass = "" }),
	})
	eq(R.Belt(s, "CMA"), nil, "a warrior in it, then a fighter without a class, then one with an empty class")
	eq(R.Holder(s, "R4"), "Oskren", "race 4 as a number or as text")
	eq(R.Belt(s, "X9"), nil); eq(R.Belt(s, "C"), nil)
	-- tostring(math.huge) is "inf" on a Mac and "1.#INF" on Windows: such a weigh-in is none,
	-- or the two clients would disagree on who fought for the belt.
	s = R.Belts({ Title("c8", "Tazdun", "Oskren", "Tazdun", T0, "Cinf", { aClass = math.huge, bClass = math.huge }) })
	eq(R.Belt(s, "Cinf"), nil)
	s = R.Belts({ Title("c7", "Mirelle", "Tazdun", "Tazdun", T0, "CMA", { aClass = "MA", bClass = "MA" }) })
	eq(R.Holder(s, "CMA"), "Tazdun")
	eq(R.Holder(s, G), nil, "the global belt was not at stake")
end)

test("arena rating: BeltsOf lists a holder's belts global first, then his class, then his race", function()
	local s = R.Belts({
		Title("bo1", "Varkoth", "Oskren", "Varkoth", T0, "R1", { aRace = 1, bRace = 1 }),
		Title("bo2", "Varkoth", "Oskren", "Varkoth", T0 + HOUR, "CMA", { aClass = "MA", bClass = "MA" }),
		Title("bo3", "Varkoth", "Oskren", "Varkoth", T0 + 2 * HOUR, G),
		Title("bo4", "Mirelle", "Tazdun", "Mirelle", T0 + 3 * HOUR, "CWA", { aClass = "WA", bClass = "WA" }),
	}, nil, T0 + DAY)
	eq(table.concat(R.BeltsOf(s, "Varkoth"), ","), "A,CMA,R1")
	eq(table.concat(R.BeltsOf(s, "Mirelle"), ","), "CWA")
	eq(#R.BeltsOf(s, "Oskren"), 0); eq(#R.BeltsOf(s, nil), 0)
end)

test("arena rating: a holder who wins no title fight for 6 weeks loses the belt at that very second", function()
	local won = Title("i1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	eq(R.VACANT_WEEKS, 6)
	local before = R.Belts({ won }, nil, T0 + VAC - 1)
	eq(R.Holder(before, G), "Varkoth", "a second before")
	eq(R.Belt(before, G).vacatesAt, T0 + VAC)
	eq(R.Lineage(before, G)[1].ends, nil, "still his a second before")
	local at = R.Belts({ won }, nil, T0 + VAC)
	eq(at.now, T0 + VAC); eq(at.vac, VAC)
	eq(R.Holder(at, G), nil, "vacant at that second")
	eq(R.Belt(at, G).vacantSince, T0 + VAC); eq(R.Belt(at, G).holder, nil)
	local lineage = R.Lineage(at, G)
	eq(#lineage, 1); eq(lineage[1].ends, T0 + VAC); eq(lineage[1].how, "inactive"); eq(lineage[1].to, nil)
	eq(R.Holder(R.Belts({ won }), G), "Varkoth", "without a clock nothing lapses")
	eq(R.Holder(R.Belts({ won }, nil, "later"), G), "Varkoth", "a clock that is no number is no clock (and no error)")
	-- A defence starts the clock again; a win without the title doesn't.
	local defended = R.Belts({ won, Title("i2", "Varkoth", "Tazdun", "Varkoth", T0 + 5 * WEEK, G) }, nil, T0 + VAC + 1)
	eq(R.Holder(defended, G), "Varkoth"); eq(R.Belt(defended, G).vacatesAt, T0 + 5 * WEEK + VAC)
	local idle = R.Belts({ won, Fight("i3", "Varkoth", "Tazdun", "Varkoth", T0 + 5 * WEEK) }, nil, T0 + VAC)
	eq(R.Holder(idle, G), nil)
	-- The old holder can win it back, as a new reign won from a vacant belt.
	local back = R.Belts({ won, Title("i4", "Mirelle", "Varkoth", "Varkoth", T0 + 7 * WEEK, G) }, nil, T0 + 7 * WEEK)
	lineage = R.Lineage(back, G)
	eq(#lineage, 2)
	eq(lineage[1].how, "inactive"); eq(lineage[1].ends, T0 + VAC)
	eq(lineage[2].holder, "Varkoth"); eq(lineage[2].from, nil); eq(lineage[2].since, T0 + 7 * WEEK); eq(lineage[2].defences, 0)
	-- The vacancy also applies between fights, with no clock at all.
	local between = R.Belts({ won, Title("i5", "Mirelle", "Varkoth", "Mirelle", T0 + 7 * WEEK, G) })
	lineage = R.Lineage(between, G)
	eq(lineage[1].how, "inactive", "gone at 6 weeks, not lost at 7"); eq(lineage[2].from, nil)
end)

test("arena rating: Belts takes the season's vacWeeks; without a usable one, VACANT_WEEKS", function()
	local won = Title("vw1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	local s = R.Belts({ won }, nil, T0 + 2 * WEEK, 1)
	eq(s.vac, WEEK)
	eq(R.Holder(s, G), nil, "vacant after 1 week"); eq(R.Belt(s, G).vacantSince, T0 + WEEK)
	eq(R.Belt(R.Belts({ won }, nil, T0, 1), G).vacatesAt, T0 + WEEK)
	eq(R.Belt(R.Belts({ won }, nil, T0, 1.5), G).vacatesAt, T0 + 907200, "a week and a half")
	local lost = R.Belts({ won, Title("vw2", "Mirelle", "Varkoth", "Mirelle", T0 + 2 * WEEK, G) }, nil, nil, 1)
	eq(R.Lineage(lost, G)[1].how, "inactive", "gone at 1 week, before the fight at 2"); eq(R.Lineage(lost, G)[1].ends, T0 + WEEK)
	eq(R.Holder(lost, G), "Mirelle")
	for _, bad in ipairs({ "six", 0, -2, 0 / 0, math.huge }) do
		eq(R.Belts({ won }, nil, T0, bad).vac, VAC, tostring(bad))
	end
	local saved = R.VACANT_WEEKS
	local ok, err = pcall(function()
		R.VACANT_WEEKS = 2
		eq(R.Belts({ won }).vac, 2 * WEEK, "the default is read when used")
		eq(R.Belts({ won }, nil, nil, 3).vac, 3 * WEEK, "the season's word over the default")
		eq(R.Belts({ won }, nil, nil, 0).vac, 2 * WEEK, "a season's 0 is no setting: the default")
		R.VACANT_WEEKS = "six"
		eq(R.Belts({ won }).vac, VAC, "a default that is no number: 6 weeks")
	end)
	R.VACANT_WEEKS = saved
	assert(ok, err)
end)

-- The first version applied one vacWeeks to all history: a new season's shorter setting ended
-- an old reign after the fact, so clients that had and hadn't heard the season word disagreed.
test("arena rating: vacWeeks as a schedule: each reign keeps the setting in force at its latest title win", function()
	local titles = {
		Title("a", "Varkoth", "Mirelle", "Varkoth", T0, G),
		Title("b", "Tazdun", "Oskren", "Tazdun", T0 + 5 * WEEK, G), -- without the holder: not applied
		Title("c", "Varkoth", "Pellwyn", "Varkoth", T0 + 5 * WEEK + 3 * DAY, G),
	}
	local at = T0 + 6 * WEEK
	local six = R.Belts(titles, nil, at)
	eq(R.Holder(six, G), "Varkoth"); eq(#R.Lineage(six, G), 1)
	-- Season 2 starts at 8 weeks with 4: nothing before it changes.
	local season2 = { { from = T0 + 8 * WEEK, weeks = 4 } }
	local later = R.Belts(titles, nil, at, season2)
	eq(Summary(later), Summary(six), "a later, shorter setting leaves the earlier reign alone")
	eq(R.Belt(later, G).vacatesAt, T0 + 5 * WEEK + 3 * DAY + VAC)
	eq(later.vac, VAC, "the setting in force at now, before season 2")
	-- One number for all history, as the first version did: at 4 weeks his reign lapsed before
	-- the fight at 5 weeks, which went to Tazdun.
	eq(R.Holder(R.Belts(titles, nil, at, 4), G), "Tazdun")
	-- At 12 weeks his reign is over 6 weeks after its last win, not 4.
	local lapsed = R.Belts(titles, nil, T0 + 12 * WEEK, season2)
	eq(R.Holder(lapsed, G), nil); eq(R.Lineage(lapsed, G)[1].ends, T0 + 5 * WEEK + 3 * DAY + VAC)
	eq(R.Lineage(lapsed, G)[1].how, "inactive")
	eq(lapsed.vac, 4 * WEEK, "season 2's setting at now")
	-- A win inside season 2 takes season 2's setting.
	local defended = { titles[1], titles[3], Title("d", "Varkoth", "Grusha", "Varkoth", T0 + 9 * WEEK, G) }
	eq(R.Belt(R.Belts(defended, nil, T0 + 10 * WEEK, season2), G).vacatesAt, T0 + 13 * WEEK, "9 weeks + 4")
	eq(R.Holder(R.Belts(defended, nil, T0 + 13 * WEEK - 1, season2), G), "Varkoth")
	eq(R.Holder(R.Belts(defended, nil, T0 + 13 * WEEK, season2), G), nil, "vacant at 13 weeks to the second")
	-- A win at a step's very second is under that step.
	local edge = { titles[1], Title("e", "Varkoth", "Grusha", "Varkoth", T0 + 5 * WEEK, G) }
	eq(R.Belt(R.Belts(edge, nil, nil, { { from = T0 + 5 * WEEK, weeks = 1 } }), G).vacatesAt, T0 + 6 * WEEK)
	eq(R.Belt(R.Belts(edge, nil, nil, { { from = T0 + 5 * WEEK + 1, weeks = 1 } }), G).vacatesAt, T0 + 5 * WEEK + VAC)
	-- The steps in any order, as a list or a map; at one `from` the shorter; a step that is no
	-- setting is left out; before the first step, VACANT_WEEKS.
	local messy = {
		z = { from = T0 + 8 * WEEK, weeks = 5 }, { from = T0 + 8 * WEEK, weeks = 4 }, { from = "soon", weeks = 1 },
		{ from = T0, weeks = 0 }, { from = T0, weeks = 0 / 0 }, { weeks = 1 }, { from = T0, weeks = "2" }, "x",
	}
	local tidy = R.Belts(titles, nil, T0 + 12 * WEEK, messy)
	eq(Summary(tidy), Summary(lapsed)); eq(tidy.vac, 4 * WEEK, "4 over 5 at the same time")
	local reversed = { { from = T0 + 8 * WEEK, weeks = 5 }, { from = T0 + 8 * WEEK, weeks = 4 } }
	eq(R.Belts(titles, nil, T0 + 12 * WEEK, reversed).vac, 4 * WEEK, "whatever order they came in")
	eq(R.Belts(titles, nil, nil, season2).vac, 4 * WEEK, "no clock: the latest setting")
	eq(R.Belts(titles, nil, T0, {}).vac, VAC, "an empty schedule: VACANT_WEEKS")
	eq(R.Belts(titles, nil, T0, { { from = T0 + WEEK, weeks = 2 } }).vac, VAC, "before the first step")
end)

test("arena rating: S and V end the named holder's reign at their time; a word naming anyone else changes nothing", function()
	local won = Title("sv1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	local strip = Word("w1", "S", G, "Varkoth", T0 + DAY)
	local s = R.Belts({ won }, { strip }, T0 + 2 * DAY)
	eq(R.Holder(s, G), nil, "stripped")
	local b = R.Belt(s, G)
	eq(b.vacantSince, T0 + DAY); eq(b.count, 1)
	local reign = R.Lineage(s, G)[1]
	eq(reign.how, "stripped"); eq(reign.ends, T0 + DAY); eq(reign.word, "w1"); eq(reign.to, nil)
	eq(Why(s), "")
	s = R.Belts({ won }, { Word("w2", "V", G, "Varkoth", T0 + DAY) }, T0 + 2 * DAY)
	eq(R.Lineage(s, G)[1].how, "vacated"); eq(R.Lineage(s, G)[1].word, "w2")
	-- The next title fight is for a vacant belt, even without the old holder.
	s = R.Belts({ won, Title("sv2", "Mirelle", "Tazdun", "Mirelle", T0 + 2 * DAY, G) }, { strip }, T0 + 3 * DAY)
	eq(R.Holder(s, G), "Mirelle"); eq(R.Belt(s, G).from, nil); eq(R.Belt(s, G).count, 2)
	-- A word naming someone who doesn't hold the belt then.
	s = R.Belts({ won }, { Word("w3", "S", G, "Mirelle", T0 + DAY) }, T0 + 2 * DAY)
	eq(R.Holder(s, G), "Varkoth"); eq(Why(s), "w3:not the holder")
	-- The clock came first; and a belt never held has no holder to strip.
	s = R.Belts({ won }, { Word("w4", "S", G, "Varkoth", T0 + VAC), Word("w5", "V", "CMA", "Varkoth", T0) }, T0 + VAC)
	eq(R.Lineage(s, G)[1].how, "inactive"); eq(Why(s), "w4:not the holder,w5:not the holder")
	eq(R.Belt(s, "CMA"), nil, "nothing to show")
	-- In one second the title fight goes first: defended, then stripped.
	s = R.Belts({ won, Title("sv3", "Varkoth", "Tazdun", "Varkoth", T0 + DAY, G) }, { strip }, T0 + DAY)
	reign = R.Lineage(s, G)[1]
	eq(reign.defences, 1); eq(reign.how, "stripped")
	-- A word is about one belt.
	local mage = Title("sv4", "Varkoth", "Oskren", "Varkoth", T0, "CMA", { aClass = "MA", bClass = "MA" })
	s = R.Belts({ won, mage }, { Word("w6", "S", "CMA", "Varkoth", T0 + DAY) }, T0 + 2 * DAY)
	eq(R.Holder(s, G), "Varkoth", "his global belt stays"); eq(R.Holder(s, "CMA"), nil)
	eq(table.concat(R.BeltsOf(s, "Varkoth"), ","), G)
end)

test("arena rating: U cancels a word as if never given: the King's anyone's, a councillor's only his own", function()
	local won = Title("u1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	local mid = Title("u2", "Mirelle", "Tazdun", "Mirelle", T0 + 2 * DAY, G)
	local strip = Word("s1", "S", G, "Varkoth", T0 + DAY, { by = "Councillor" })
	local now = T0 + 4 * DAY
	eq(R.Holder(R.Belts({ won, mid }, { strip }, now), G), "Mirelle", "stripped, then won by Mirelle")
	-- His own undo: the strip never happened, so the fight at 2 days was without the holder.
	local s = R.Belts({ won, mid }, { strip, Undo("x1", "s1", T0 + 3 * DAY, "Councillor") }, now)
	eq(R.Holder(s, G), "Varkoth"); eq(#R.Lineage(s, G), 1); eq(R.Lineage(s, G)[1].defences, 0)
	eq(Why(s), "s1:undone")
	-- A councillor's undo fails on the King's word, and on another councillor's.
	local kings = Word("s2", "S", G, "Varkoth", T0 + DAY, { by = "King", king = true })
	s = R.Belts({ won }, { kings, Undo("x2", "s2", T0 + 3 * DAY, "Councillor") }, now)
	eq(R.Holder(s, G), nil, "the King's strip stands"); eq(Why(s), "x2:not his")
	s = R.Belts({ won }, { strip, Undo("x3", "s1", T0 + 3 * DAY, "Steward") }, now)
	eq(R.Holder(s, G), nil); eq(Why(s), "x3:not his")
	s = R.Belts({ won }, { strip, Undo("x4", "s1", T0 + 3 * DAY, "Steward", "yes") }, now)
	eq(Why(s), "x4:not his", "only king = true is the King")
	-- The King's undo counts over anyone's; his own words he undoes too.
	s = R.Belts({ won, mid }, { strip, Undo("x5", "s1", T0 + 3 * DAY, "King", true) }, now)
	eq(R.Holder(s, G), "Varkoth")
	s = R.Belts({ won }, { kings, Undo("x6", "s2", T0 + 3 * DAY, "King", true) }, now)
	eq(R.Holder(s, G), "Varkoth")
	-- An undo can be undone: the word stands again.
	s = R.Belts({ won }, { strip, Undo("x7", "s1", T0 + 2 * DAY, "Councillor"), Undo("x8", "x7", T0 + 3 * DAY, "King", true) }, now)
	eq(R.Holder(s, G), nil, "stripped after all"); eq(Why(s), "x7:undone")
	-- An undo names a word before it, one that exists.
	s = R.Belts({ won }, { Undo("x9", "nothing", T0 + DAY, "King", true), strip, Undo("y1", "s1", T0, "Councillor") }, now)
	eq(R.Holder(s, G), nil); eq(Why(s), "x9:unknown word,y1:not before")
	s = R.Belts({ won }, { strip, Undo("y2", "u1", T0 + 3 * DAY, "King", true) }, now)
	eq(Why(s), "y2:unknown word", "a fight is no word")
	-- Without a giver, a word is nobody's own.
	s = R.Belts({ won }, { Word("s3", "S", G, "Varkoth", T0 + DAY), Undo("y3", "s3", T0 + 2 * DAY) }, now)
	eq(R.Holder(s, G), nil); eq(Why(s), "y3:not his")
end)

-- The first version kept the belts as a state that each call built on, and wrote the vacancy at
-- `now` into it, so a title fight older than `now` but heard afterwards (a backfill from the
-- clerk) was judged on top of a vacancy that never happened. Belts now starts from scratch.
test("arena rating: belts come out the same whatever order the fights and words came in, and a late fight lands in place", function()
	local fights = {
		Title("o1", "Varkoth", "Mirelle", "Varkoth", T0, G),
		Title("o2", "Varkoth", "Tazdun", "Varkoth", T0 + DAY, G),
		Title("o3", "Oskren", "Mirelle", "Oskren", T0 + DAY, "CMA", { aClass = "MA", bClass = "MA" }),
		Title("o4", "Tazdun", "Varkoth", "Tazdun", T0 + 3 * DAY, G),
		Fight("o5", "Pellwyn", "Grusha", "Pellwyn", T0 + DAY),
	}
	local words = {
		Word("w1", "C", G, "Mirelle", T0 + 2 * DAY, { by = "Arbiter" }),
		Word("w2", "2", "CMA", "Mirelle", T0 + 2 * DAY, { by = "Clerk" }),
		Word("w3", "V", "CMA", "Oskren", T0 + 4 * DAY, { by = "Arbiter" }),
		Undo("w4", "w3", T0 + 5 * DAY, "Arbiter"),
		Word("w5", "S", G, "Mirelle", T0 + 4 * DAY, { by = "Arbiter" }),
	}
	local now = T0 + 6 * DAY
	local base = R.Belts(fights, words, now)
	eq(R.Holder(base, G), "Tazdun"); eq(R.Holder(base, "CMA"), "Oskren")
	eq(Why(base), "w3:undone,w5:not the holder")
	local function Reversed(list)
		local out = {}
		for i = #list, 1, -1 do out[#out + 1] = list[i] end
		return out
	end
	local function Keyed(list)
		local out = {}
		for _, x in ipairs(list) do out[x.id] = x end
		return out
	end
	eq(Summary(R.Belts(Reversed(fights), Reversed(words), now)), Summary(base))
	eq(Summary(R.Belts(Keyed(fights), Keyed(words), now)), Summary(base))
	-- He logs in at 7 weeks with the first fight only; the defence at 5 weeks comes later.
	local won = fights[1]
	local defence = Title("q2", "Varkoth", "Tazdun", "Varkoth", T0 + 5 * WEEK, G)
	local seen = T0 + 7 * WEEK
	eq(R.Holder(R.Belts({ won }, nil, seen), G), nil, "vacant by the clock, with what he had")
	local caught = R.Belts({ won, defence }, nil, seen)
	eq(R.Holder(caught, G), "Varkoth", "the defence heard late counts where it belongs")
	eq(#R.Lineage(caught, G), 1); eq(R.Lineage(caught, G)[1].defences, 1)
	-- A defence 10 s before the deadline, heard 15 s after it.
	local wire = Title("q4", "Varkoth", "Tazdun", "Varkoth", T0 + VAC - 10, G)
	eq(R.Holder(R.Belts({ won }, nil, T0 + VAC + 5), G), nil)
	eq(R.Holder(R.Belts({ won, wire }, nil, T0 + VAC + 20), G), "Varkoth", "defended in time")
	-- Two title fights in one second go in id order, not by arrival.
	local x, y = Title("m-a", "Varkoth", "Mirelle", "Varkoth", T0, G), Title("m-b", "Mirelle", "Varkoth", "Mirelle", T0, G)
	eq(R.Holder(R.Belts({ y, x }), G), "Mirelle"); eq(Reigns(R.Belts({ y, x }), G), Reigns(R.Belts({ x, y }), G))
end)

-- Belts starts from scratch, so a store that prunes its inputs changes history (the review:
-- the oldest title fight dropped crowned someone else, an S word dropped gave the belt back).
-- Prunable names the only words a store may drop.
test("arena rating: dropping a title fight or an S word changes history; dropping what Prunable names changes nothing", function()
	local first = Title("pr1", "Varkoth", "Mirelle", "Varkoth", T0, G)
	local other = Title("pr2", "Tazdun", "Oskren", "Tazdun", T0 + DAY, G)
	local mage = Title("pr3", "Mirelle", "Oskren", "Mirelle", T0, "CMA", { aClass = "MA", bClass = "MA" })
	local strip = Word("ps", "S", G, "Varkoth", T0 + HOUR, { by = "Arbiter" })
	eq(R.Holder(R.Belts({ first, other }, nil, T0 + 2 * DAY), G), "Varkoth")
	eq(R.Holder(R.Belts({ other }, nil, T0 + 2 * DAY), G), "Tazdun", "why every title fight is kept")
	eq(R.Holder(R.Belts({ first, other }, { strip }, T0 + 2 * DAY), G), "Tazdun")
	eq(R.Holder(R.Belts({ first, other }, {}, T0 + 2 * DAY), G), "Varkoth", "why every S word is kept")
	local fights = { first, other, mage }
	local words = {
		strip,                                                                      -- S: for good
		Word("pc1", "C", G, "Mirelle", T0 + 2 * DAY, { by = "Arbiter" }),            -- over by 30 days
		Undo("pu1", "pc1", T0 + 3 * DAY, "Arbiter"),                                 -- goes with pc1
		Undo("pu2", "pu1", T0 + 4 * DAY, "King", true),                              -- and with pu1
		Word("pc2", "C", G, "Oskren", T0 + 20 * DAY, { by = "Arbiter" }),            -- still standing
		Word("p2a", "2", G, "Mirelle", T0 + DAY, { by = "Clerk" }),                   -- p2b came after
		Word("p2b", "2", G, "Oskren", T0 + 5 * DAY, { by = "Clerk" }),                -- the latest live 2
		Word("p2c", "2", G, "Pellwyn", T0 + 6 * DAY, { by = "Clerk" }),               -- later, but undone:
		Undo("pu3", "p2c", T0 + 7 * DAY, "Clerk"),                                   -- both kept
		Word("p3a", "3", G, "Grusha", T0 + DAY, { by = "Clerk" }),                    -- the only 3
		Word("pm2a", 2, "CMA", "Cedrik", T0 + DAY, { by = "Clerk" }),                 -- pm2b came after
		Word("pm2b", "2", "CMA", "Dagny", T0 + 3 * DAY, { by = "Clerk" }),
		Word("pv", "V", "CMA", "Mirelle", T0 + 10 * DAY, { by = "Arbiter" }),        -- V and its undo:
		Undo("pu4", "pv", T0 + 11 * DAY, "Arbiter"),                                 -- for good
		Undo("pu5", "nothing", T0 + 12 * DAY, "King", true),                         -- a word not held
	}
	local now = T0 + 40 * DAY
	local prunable = R.Prunable(words, now)
	local names = {}
	for id in pairs(prunable) do names[#names + 1] = id end
	table.sort(names)
	eq(table.concat(names, ","), "p2a,pc1,pm2a,pu1,pu2")
	local kept = {}
	for _, w in ipairs(words) do if not prunable[tostring(w.id)] then kept[#kept + 1] = w end end
	for _, t in ipairs({ now, now + 8 * DAY, now + 60 * DAY }) do
		eq(State(R.Belts(fights, kept, t)), State(R.Belts(fights, words, t)), "at " .. (t - T0))
	end
	local b = R.Belt(R.Belts(fights, kept, now), G)
	eq(b.holder, "Tazdun"); eq(b.contender, "Oskren"); eq(b.podium[2], "Oskren"); eq(b.podium[3], "Grusha")
	eq(R.Holder(R.Belts(fights, kept, now), "CMA"), "Mirelle", "the V undone")
	-- A C word goes only when its 28 days are over, and never without a clock.
	eq(R.Prunable(words, T0 + 30 * DAY - 1).pc1, nil)
	eq(R.Prunable(words, T0 + 30 * DAY).pc1, true)
	eq(next(R.Prunable({ words[2] })), nil, "no clock")
	eq(next(R.Prunable(nil, now)), nil); eq(next(R.Prunable({ "x", strip }, now)), nil)
end)

test("arena rating: a belt keeps its last 50 reigns, oldest first", function()
	local fights = {}
	for i = 1, 60 do
		local winner = i % 2 == 1 and "Varkoth" or "Mirelle"
		fights[i] = Title(("t%02d"):format(i), "Varkoth", "Mirelle", winner, T0 + i * HOUR, G)
	end
	local s = R.Belts(fights)
	local lineage = R.Lineage(s, G)
	eq(#lineage, 50); eq(R.Belt(s, G).count, 50)
	eq(lineage[1].since, T0 + 11 * HOUR, "the 10 oldest reigns went")
	for i = 2, 50 do assert(lineage[i].since > lineage[i - 1].since, "oldest first") end
	eq(lineage[50].holder, "Mirelle"); eq(lineage[50].ends, nil)
	eq(lineage[49].how, "lost"); eq(lineage[49].to, "Mirelle")
	lineage[1].holder = "Forger"
	eq(R.Lineage(s, G)[1].holder, "Varkoth", "Lineage gives a copy")
	local _, reign = R.Holder(s, G)
	reign.holder = "Forger"
	eq(R.Holder(s, G), "Mirelle", "and Holder too")
end)

test("arena rating: a word is checked before it counts, and each one left out is named once", function()
	local good = Word("g1", "S", G, "Varkoth", T0)
	eq(R.CheckWord(good), true)
	local cases = {
		{ "a line of text", "not a word" },
		{ Word("", "S", G, "Varkoth", T0), "id" },
		{ Word(1.5, "S", G, "Varkoth", T0), "id" },
		{ Word("k1", "X", G, "Varkoth", T0), "kind" },
		{ Word("k2", 4, G, "Varkoth", T0), "kind" },
		{ Word("k3", "S", G, "Varkoth", 0 / 0), "time" },
		{ Word("k4", "S", "X1", "Varkoth", T0), "category" },
		{ Word("k5", "C", nil, "Varkoth", T0), "category" },
		{ Word("k6", "S", G, "", T0), "fighter" },
		{ Word("k7", "V", G, nil, T0), "fighter" },
		{ Word("k8", "C", G, 42, T0), "fighter" },
		{ Word("k9", "2", G, 42, T0), "fighter" },
		{ Undo("k10", nil, T0, "King", true), "ref" },
		{ Undo("k11", {}, T0, "King", true), "ref" },
	}
	for _, case in ipairs(cases) do
		local ok, why = R.CheckWord(case[1])
		eq(ok, false, case[2]); eq(why, case[2])
	end
	eq(R.CheckWord(Word("k12", 2, G, nil, T0)), true, "2 as a number, nobody in that place")
	eq(R.CheckWord(Word("k13", "3", G, "", T0)), true)
	eq(R.CheckWord(Undo("k14", 7, T0, "King", true)), true, "an undo needs no category")
	-- In Belts: each bad word named with its reason, an id seen twice counts once (the earlier).
	local words = {}
	for i, case in ipairs(cases) do words[i] = case[1] end
	words[#words + 1] = Word("d1", "S", G, "Varkoth", T0 + 2 * DAY)
	words[#words + 1] = Word("d1", "V", G, "Varkoth", T0 + DAY)
	local s = R.Belts({ Title("f1", "Varkoth", "Mirelle", "Varkoth", T0, G) }, words, T0 + 3 * DAY)
	eq(R.Lineage(s, G)[1].how, "vacated", "the earlier d1 kept"); eq(R.Lineage(s, G)[1].ends, T0 + DAY)
	local count = {}
	for _, x in ipairs(s.ignored) do count[x.why] = (count[x.why] or 0) + 1 end
	eq(#s.ignored, #cases + 1)
	eq(count.duplicate, 1); eq(count.id, 2); eq(count.kind, 2); eq(count.fighter, 4); eq(count.ref, 2)
	eq(count.category, 2); eq(count.time, 1); eq(count["not a word"], 1)
	local again = R.Belts({ Title("f1", "Varkoth", "Mirelle", "Varkoth", T0, G) },
		{ words[#words], words[#words - 1] }, T0 + 3 * DAY)
	eq(R.Lineage(again, G)[1].how, "vacated", "whatever order the two came in")
end)

---------------------------------------------------------------------------
-- Tiers with the belts
---------------------------------------------------------------------------

test("arena rating: a belt raises its holder's tier: the global belt to gold, a class or race belt to silver", function()
	local fights = {}
	Ladder(fights, "Top", "WWWWWW", { class = "MA", race = 1 })
	Ladder(fights, "High", "WWWWWL", { class = "MA", race = 1 })
	Ladder(fights, "Mid", "WWWWLL", { class = "WA", race = 2 })
	Ladder(fights, "Low", "WWWLLL", { class = "MA", race = 2 })
	Ladder(fights, "Last", "LLLLLL", { class = "MA", race = 2 })
	local built = R.Build(fights)
	eq(Keys(R.Ranking(built)), "Top,High,Mid,Low,Last")
	local plain = R.Tiers(built)
	eq(plain.Top, "gold"); eq(plain.High, "silver"); eq(plain.Mid, "bronze"); eq(plain.Low, nil); eq(plain.Last, nil)
	-- Belts won last season: their fights are not in this season's table.
	local old = T0 - 10 * DAY
	local titles = {
		Title("ot1", "Last", "Spar-o1", "Last", old, G),
		Title("ot2", "Low", "Spar-o2", "Low", old, "CMA", { aClass = "MA", bClass = "MA" }),
		Title("ot3", "Top", "Spar-o3", "Top", old, "R1", { aRace = 1, bRace = 1 }),
		Title("ot4", "Mid", "Spar-o4", "Mid", old, "R2", { aRace = 2, bRace = 2 }),
		Title("ot5", "Stranger", "Spar-o5", "Stranger", old, "CWA", { aClass = "WA", bClass = "WA" }),
	}
	local belts = R.Belts(titles, nil, T0 + DAY)
	local tiers = R.Tiers(built, G, belts)
	eq(tiers.Last, "gold", "the global belt, whatever his place")
	eq(tiers.Low, "silver"); eq(tiers.Mid, "silver", "bronze by the table, silver by his race belt")
	eq(tiers.Top, "gold", "a belt never lowers a tier"); eq(tiers.High, "silver", "no place taken from anyone")
	eq(tiers.Stranger, "silver", "a holder without a fight this season")
	eq(R.Tiers(built, nil, belts).Last, "gold", "global unless told")
	-- A class table shows the holders who belong to it: 4 mages, so silver, bronze, none, none.
	local mages = R.Tiers(built, "CMA", belts)
	eq(mages.Top, "silver"); eq(mages.High, "bronze"); eq(mages.Low, "silver"); eq(mages.Last, "gold")
	eq(mages.Mid, nil, "a warrior"); eq(mages.Stranger, nil, "not in this season's table")
	-- A belt lapsed by then raises nobody.
	eq(R.Tiers(built, G, R.Belts({ titles[1] }, nil, old + VAC)).Last, nil)
	eq(R.Tiers(built, G, "belts").Last, nil, "belts that are no table")
end)

---------------------------------------------------------------------------
-- Contender status, the number-one contender, the podium
---------------------------------------------------------------------------

local MA1, MA4 = { class = "MA", race = 1 }, { class = "MA", race = 4 }

-- Four mages with 20, 11, 10 and 9 straight wins (all in the first day), and Varkoth, who wins
-- the vacant global belt at 1 day and defends it against the best of them at 2 days.
local function Field()
	local fights = {}
	Ladder(fights, "Aldric", string.rep("W", 20), MA1)
	Ladder(fights, "Brenna", string.rep("W", 11), MA1)
	Ladder(fights, "Corvin", string.rep("W", 10), MA4)
	Ladder(fights, "Dunmor", string.rep("W", 9), MA1)
	fights[#fights + 1] = Title("x1", "Varkoth", "Mirelle", "Varkoth", T0 + DAY, G)
	fights[#fights + 1] = Title("x2", "Varkoth", "Aldric", "Varkoth", T0 + 2 * DAY, G)
	return fights
end

test("arena rating: contender status needs the category, 10 rated fights, one within 30 days, and no exclusion", function()
	local built = R.Build(Field())
	local now = T0 + 3 * DAY
	eq(R.Eligible(built, "Aldric", G, { now = now }), true)
	eq(R.Eligible(built, "Corvin", "R4", { now = now }), true)
	local function Why2(...) return select(2, R.Eligible(...)) end
	eq(Why2(built, "Dunmor", G, { now = now }), "fights", "9 rated fights")
	eq(Why2(built, "Varkoth", G, { now = now }), "fights")
	eq(Why2(built, "Corvin", "R1", { now = now }), "category")
	eq(Why2(built, "Nobody", G), "category")
	local last = R.Record(built, "Brenna").lastRated
	eq(last, T0 + 11 * HOUR)
	eq(R.Eligible(built, "Brenna", G, { now = last + 30 * DAY - 1 }), true, "a second inside 30 days")
	eq(Why2(built, "Brenna", G, { now = last + 30 * DAY }), "inactive", "30 days to the second")
	eq(R.Eligible(built, "Brenna", G), true, "without a clock activity can't be told")
	eq(R.Eligible(built, "Brenna", nil), true, "global unless told")
	eq(Why2(built, "Brenna", G, { exclude = { Brenna = true } }), "excluded")
	eq(Why2(built, "Brenna", G, { exclude = function(key) return key == "Brenna" end }), "excluded")
	eq(R.Eligible(built, "Brenna", G, { exclude = { Aldric = true } }), true)
	-- A walkover is no fight in the ring: nine rated fights and a walkover are still nine.
	local wo = Ladder({}, "Esker", string.rep("W", 9), MA1)
	wo[#wo + 1] = Fight("wo-e", "Esker", "Fenn", "Esker", T0 + DAY, { method = "walkover" })
	local woBuilt = R.Build(wo)
	eq(Why2(woBuilt, "Esker", G, { now = T0 + 2 * DAY }), "fights")
	eq(R.Record(woBuilt, "Esker").lastRated, T0 + 9 * HOUR, "the walkover is not his latest rated fight")
end)

test("arena rating: the number-one contender is the best with contender status but the holder, after the holder's recent title victims", function()
	local fights = Field()
	Ladder(fights, "Aldric", "W", MA1, T0 + 20 * DAY) -- both stay active past the rematch window
	Ladder(fights, "Brenna", "W", MA1, T0 + 20 * DAY)
	local built = R.Build(fights)
	eq(Keys(R.Ranking(built, G, 10)), "Aldric,Brenna,Corvin", "the lost title fight left Aldric first")
	local now = T0 + 21 * DAY
	local belts = R.Belts(fights, nil, now)
	eq(R.Holder(belts, G), "Varkoth")
	local key, rating, how = R.Contender(built, belts, G)
	eq(key, "Brenna", "Varkoth beat Aldric for the belt 19 days ago"); eq(rating, R.Rating(built, "Brenna")); eq(how, "table")
	eq(R.Contender(built, belts, G, { now = T0 + 32 * DAY - 1 }), "Brenna", "a second inside 30 days")
	eq(R.Contender(built, belts, G, { now = T0 + 32 * DAY }), "Aldric", "30 days on, his turn again")
	eq(R.Contender(built, belts, G, { exclude = { Brenna = true, Corvin = true } }), "Aldric", "nobody else: the rematch after all")
	eq(R.Contender(built, belts, G, { exclude = { Brenna = true } }), "Corvin")
	eq(R.Contender(built, belts, "R4"), "Corvin", "the race 4 belt, never held: the best of the race")
	eq(R.Contender(built, belts, "R9"), nil, "nobody in it")
	eq(R.Contender(built, belts, "CMA", { exclude = function(k) return k ~= "Dunmor" end }), nil, "Dunmor has 9 fights")
	eq(R.Contender(built, R.Belts(fights), G), "Aldric", "no clock: the rematch window can't be told")
	-- A beating in a title fight for another belt, or a plain defeat, is no reason to wait.
	local other = Field()
	other[#other] = Title("x2", "Varkoth", "Aldric", "Varkoth", T0 + 2 * DAY, "R1", { aRace = 1, bRace = 1 })
	eq(R.Contender(R.Build(other), R.Belts(other, nil, now), G, { now = T0 + 3 * DAY }), "Aldric")
	local plain = Field()
	plain[#plain] = Fight("x2", "Varkoth", "Aldric", "Varkoth", T0 + 2 * DAY)
	eq(R.Contender(R.Build(plain), R.Belts(plain, nil, now), G, { now = T0 + 3 * DAY }), "Aldric", "a plain defeat")
	-- The holder is never his own contender.
	local champ = R.Belts({ Title("x9", "Aldric", "Spar-x9", "Aldric", T0 + 3 * DAY, G) }, nil, now)
	eq(R.Contender(built, champ, G), "Brenna")
	eq(R.Contender(built, nil, G, { now = now }), "Aldric", "no belts at all: no holder, and nobody's victim to pass over")
end)

-- The first version looked for the holder's title wins in this season's table only, so a
-- fighter he beat 10 days before the season turned over was number one at once; and it took
-- any rated fight marked with the title, even one that never touched the belt.
test("arena rating: the rematch wait counts the holder's wins that touched this belt, last season's too, and nothing else", function()
	local function Season(extra)
		local fights = {}
		Ladder(fights, "Aldric", string.rep("W", 20), MA1)
		Ladder(fights, "Brenna", string.rep("W", 11), MA1)
		for _, f in ipairs(extra or {}) do fights[#fights + 1] = f end
		return fights
	end
	local now = T0 + DAY
	local built = R.Build(Season())
	eq(Keys(R.Ranking(built, G, 10)), "Aldric,Brenna")
	-- Last season, 10 days before this one began: Varkoth took the vacant belt from Aldric.
	local crowned = Title("rm1", "Varkoth", "Aldric", "Varkoth", T0 - 10 * DAY, G)
	local belts = R.Belts({ crowned }, nil, now)
	eq(R.Holder(belts, G), "Varkoth")
	eq(R.Contender(built, belts, G), "Brenna", "beaten 11 days ago, last season")
	eq(R.Contender(built, belts, G, { now = T0 + 20 * DAY - 1 }), "Brenna")
	eq(R.Contender(built, belts, G, { now = T0 + 20 * DAY }), "Aldric", "30 days to the second")
	-- This season's title fights that never touched the belt beat nobody for it: one the
	-- ledger kept off the belt, a walkover, and a class title fight Aldric weighed in for as
	-- a warrior (his later fights say mage).
	local held = Title("rm2", "Varkoth", "Mirelle", "Varkoth", T0 - 20 * DAY, G)
	for _, extra in ipairs({ { belt = false }, { method = "walkover" } }) do
		local f = Title("rm3", "Varkoth", "Aldric", "Varkoth", T0 + 21 * HOUR, G, extra)
		local fights = Season({ f })
		fights[#fights + 1] = held
		local s = R.Belts(fights, nil, now)
		eq(R.Holder(s, G), "Varkoth"); eq(R.Belt(s, G).defences, 0)
		local b = R.Build(fights)
		eq(Keys(R.Ranking(b, G, 10)), "Aldric,Brenna")
		eq(R.Contender(b, s, G), "Aldric", extra.method or "belt = false")
	end
	local mages = Title("rm4", "Varkoth", "Mirelle", "Varkoth", T0 - 20 * DAY, "CMA", { aClass = "MA", bClass = "MA" })
	local catch = Title("rm5", "Varkoth", "Aldric", "Varkoth", T0 + 30 * MIN, "CMA", { aClass = "MA", bClass = "WA" })
	local fights = Season({ catch })
	fights[#fights + 1] = mages
	local s, b = R.Belts(fights, nil, now), R.Build(fights)
	eq(R.Holder(s, "CMA"), "Varkoth"); eq(R.Belt(s, "CMA").defences, 0)
	eq(R.Record(b, "Aldric").class, "MA"); eq(Keys(R.Ranking(b, "CMA", 10)), "Aldric,Brenna")
	eq(R.Contender(b, s, "CMA"), "Aldric", "no class title fight between two mages")
	-- An earlier reign of his counts: he beat Aldric, was stripped, then took the vacant belt again.
	s = R.Belts({ crowned, Title("rm6", "Varkoth", "Mirelle", "Varkoth", T0 - 5 * DAY, G) },
		{ Word("rm7", "S", G, "Varkoth", T0 - 8 * DAY, { by = "Arbiter" }) }, now)
	eq(#R.Lineage(s, G), 2); eq(R.Holder(s, G), "Varkoth")
	eq(R.Contender(built, s, G), "Brenna")
	-- Another holder's win doesn't: Oskren beat Aldric, then lost the belt to Varkoth.
	s = R.Belts({ Title("rm8", "Oskren", "Aldric", "Oskren", T0 - 10 * DAY, G),
		Title("rm9", "Varkoth", "Oskren", "Varkoth", T0 - 5 * DAY, G) }, nil, now)
	eq(R.Holder(s, G), "Varkoth"); eq(R.Contender(built, s, G), "Aldric")
end)

test("arena rating: a C word names the contender for 28 days, until he fights for the belt; a later one replaces it", function()
	local fights = Field()
	local built = R.Build(fights)
	local c = Word("c1", "C", G, "Corvin", T0 + 3 * DAY, { by = "Arbiter" })
	local now = T0 + 4 * DAY
	local belts = R.Belts(fights, { c }, now)
	local b = R.Belt(belts, G)
	eq(b.contender, "Corvin"); eq(b.contenderUntil, T0 + 31 * DAY); eq(b.contenderWord, "c1")
	local key, rating, how = R.Contender(built, belts, G)
	eq(key, "Corvin"); eq(rating, R.Rating(built, "Corvin")); eq(how, "word")
	eq(R.Contender(built, belts, G, { now = T0 + 31 * DAY - 1 }), "Corvin", "a second inside 28 days")
	eq(select(3, R.Contender(built, belts, G, { now = T0 + 31 * DAY })), "table", "28 days to the second")
	eq(R.Belt(R.Belts(fights, { c }, T0 + 31 * DAY), G).contender, nil, "gone from the belt by then")
	eq(R.Contender(built, belts, G, { exclude = { Corvin = true } }), "Brenna", "a debtor is no contender, word or not")
	-- He had his shot: the word is spent, whoever won.
	local shot = { Title("x3", "Varkoth", "Corvin", "Varkoth", T0 + 5 * DAY, G) }
	for _, f in ipairs(fights) do shot[#shot + 1] = f end
	eq(R.Belt(R.Belts(shot, { c }, T0 + 6 * DAY), G).contender, nil)
	-- A defence against someone else leaves it; so does a title fight that didn't touch the belt
	-- (his, without the holder), and a fight for another belt.
	local without = { Title("x4", "Varkoth", "Brenna", "Varkoth", T0 + 5 * DAY, G),
		Title("x5", "Corvin", "Spar-x5", "Corvin", T0 + 5 * DAY, "R4", { aRace = 4, bRace = 4 }),
		Title("x6", "Corvin", "Mirelle", "Corvin", T0 + 5 * DAY + HOUR, G) }
	for _, f in ipairs(fights) do without[#without + 1] = f end
	local kept = R.Belts(without, { c }, T0 + 6 * DAY)
	eq(R.Belt(kept, G).defences, 2, "the defence touched the belt"); eq(R.Belt(kept, G).contender, "Corvin")
	-- A title tournament's winner gets the word: a later one replaces the earlier, in any order.
	local tourney = Word("c2", "C", G, "Dunmor", T0 + 3 * DAY + HOUR, { by = "Promoter" })
	eq(R.Contender(built, R.Belts(fights, { c, tourney }, now), G), "Dunmor", "the word stands even with 9 fights")
	eq(R.Contender(built, R.Belts(fights, { tourney, c }, now), G), "Dunmor")
	-- Undone, or naming the holder: the table again.
	eq(R.Contender(built, R.Belts(fights, { c, Undo("c3", "c1", T0 + 3 * DAY + 1, "Arbiter") }, now), G), "Brenna")
	local mine = R.Belts(fights, { Word("c4", "C", G, "Varkoth", T0 + 3 * DAY) }, now)
	eq(R.Belt(mine, G).contender, nil); eq(R.Contender(built, mine, G), "Brenna")
	-- A word for a belt never held shows that belt.
	local fresh = R.Belts({}, { Word("c5", "C", "CMA", "Brenna", T0) }, T0 + DAY)
	b = R.Belt(fresh, "CMA")
	eq(b.count, 0); eq(b.holder, nil); eq(b.vacantSince, nil); eq(b.contender, "Brenna")
end)

test("arena rating: the podium is the holder, then the two best with contender status; the 2nd loses his silver when overtaken", function()
	local fights = Field()
	local built = R.Build(fights)
	local now = T0 + 3 * DAY
	local belts = R.Belts(fights, nil, now)
	local p = R.Podium(built, belts, G)
	eq(p[1], "Varkoth"); eq(p[2], "Aldric", "beaten for the belt, still second"); eq(p[3], "Brenna")
	p = R.Podium(built, belts, G, { exclude = { Aldric = true } })
	eq(p[2], "Brenna"); eq(p[3], "Corvin")
	p = R.Podium(built, belts, "R4")
	eq(p[1], nil); eq(p[2], "Corvin"); eq(p[3], nil, "nobody else of race 4 with the status")
	-- A vacant belt, never held or stripped, still gives silver and bronze.
	p = R.Podium(built, belts, "CMA")
	eq(p[1], nil); eq(p[2], "Aldric"); eq(p[3], "Brenna")
	p = R.Podium(built, R.Belts(fights, { Word("s1", "S", G, "Varkoth", T0 + 2 * DAY + HOUR) }, now), G)
	eq(p[1], nil); eq(p[2], "Aldric"); eq(p[3], "Brenna")
	-- The holder takes gold, not silver.
	local champ = R.Belts({ Title("x9", "Aldric", "Spar-x9", "Aldric", T0 + 2 * DAY + HOUR, G) }, nil, now)
	p = R.Podium(built, champ, G)
	eq(p[1], "Aldric"); eq(p[2], "Brenna"); eq(p[3], "Corvin")
	-- Overtaken: Brenna wins ten more and passes Aldric.
	local more = Field()
	Ladder(more, "Brenna", string.rep("W", 10), MA1, T0 + 2 * DAY + HOUR)
	local later = R.Build(more)
	eq(Keys(R.Ranking(later, G, 10)), "Brenna,Aldric,Corvin")
	p = R.Podium(later, R.Belts(more, nil, T0 + 4 * DAY), G)
	eq(p[2], "Brenna"); eq(p[3], "Aldric", "down to bronze")
	-- Inactive fighters drop off; the clock is the belts' unless told.
	p = R.Podium(built, R.Belts(fights, nil, T0 + 11 * HOUR + 30 * DAY), G)
	eq(p[2], "Aldric", "his title fight at 2 days keeps him active"); eq(p[3], nil)
	p = R.Podium(built, belts, G, { now = T0 + 11 * HOUR + 30 * DAY })
	eq(p[2], "Aldric"); eq(p[3], nil)
	p = R.Podium(built, nil, G)
	eq(p[1], nil); eq(p[2], "Aldric"); eq(p[3], "Brenna")
end)

test("arena rating: the clerk's 2 and 3 words: the latest of each place, never the holder, undone like any word", function()
	local fights = Field()
	local now = T0 + 3 * DAY
	local words = {
		Word("p1", "2", G, "Brenna", T0 + DAY, { by = "Clerk" }),
		Word("p2", "3", G, "Corvin", T0 + DAY, { by = "Clerk" }),
		Word("p3", "2", G, "Aldric", T0 + 2 * DAY, { by = "Clerk" }),
		Word("p4", 3, G, "", T0 + 2 * DAY, { by = "Clerk" }),
	}
	local b = R.Belt(R.Belts(fights, words, now), G)
	eq(b.podium[2], "Aldric", "the latest word of each place"); eq(b.podium[3], nil, "nobody third now")
	b = R.Belt(R.Belts(fights, { words[1], words[2] }, now), G)
	eq(b.podium[2], "Brenna"); eq(b.podium[3], "Corvin")
	b = R.Belt(R.Belts(fights, { Word("p5", "2", G, "Varkoth", T0 + 2 * DAY + 1, { by = "Clerk" }) }, now), G)
	eq(b.podium[2], nil, "the holder is never on his own podium")
	b = R.Belt(R.Belts(fights, { words[1], words[3], Undo("p6", "p3", T0 + 2 * DAY + 2, "Clerk") }, now), G)
	eq(b.podium[2], "Brenna", "the undone word gone, the earlier stands")
	b = R.Belt(R.Belts({}, { Word("p7", "2", "CMA", "Brenna", T0, { by = "Clerk" }) }, now), "CMA")
	eq(b.count, 0); eq(b.holder, nil); eq(b.podium[2], "Brenna")
	eq(R.Belt(R.Belts({}, { Word("p8", "3", "CMA", "", T0) }, now), "CMA"), nil, "nobody in the one place: nothing to show")
end)

-- The first version set the two places apart: with the clerk's 3 = X heard and the 2 = Y
-- sent with it lost or late, X showed as silver and bronze at once.
test("arena rating: a 2 or 3 word takes its fighter off the other place: nobody is silver and bronze at once", function()
	local fights = Field()
	local now = T0 + 3 * DAY
	local was = Word("pp1", "2", G, "Aldric", T0 + DAY, { by = "Clerk" })
	local moved = Word("pp2", "3", G, "Aldric", T0 + 2 * DAY, { by = "Clerk" })
	local b = R.Belt(R.Belts(fights, { was, moved }, now), G)
	eq(b.podium[2], nil, "the silver word sent with it not heard yet"); eq(b.podium[3], "Aldric")
	local late = Word("pp3", "2", G, "Brenna", T0 + 2 * DAY, { by = "Clerk" })
	for _, words in ipairs({ { was, moved, late }, { late, moved, was } }) do
		b = R.Belt(R.Belts(fights, words, now), G)
		eq(b.podium[2], "Brenna"); eq(b.podium[3], "Aldric")
	end
	b = R.Belt(R.Belts(fights, { Word("pp4", "3", G, "Corvin", T0 + DAY), Word("pp5", "2", G, "Corvin", T0 + 2 * DAY) }, now), G)
	eq(b.podium[2], "Corvin", "up from bronze"); eq(b.podium[3], nil)
	b = R.Belt(R.Belts(fights, { Word("pp6", "3", G, "Corvin", T0 + DAY), Word("pp7", "2", G, "", T0 + 2 * DAY) }, now), G)
	eq(b.podium[2], nil, "nobody second"); eq(b.podium[3], "Corvin", "takes nobody off")
end)

test("arena rating: a broken saved belts table never raises an error in a query", function()
	local built = R.Build(Field())
	local sound = { holder = "Varkoth", since = T0, last = T0, defences = 0 }
	local broken = {
		"a line of text",
		{ belts = "x" },
		{ belts = { A = "x" } },
		{ belts = { A = { cat = "A" } } },                                                    -- no reigns
		{ belts = { A = { reigns = { "x" } } } },                                             -- a reign that is no reign
		{ belts = { A = { reigns = { { holder = "Varkoth" } } } } },                          -- a reign without its times
		{ belts = { A = { reigns = { { holder = "Varkoth", since = T0, last = "x", defences = 0 } } } } },
		{ belts = { A = { reigns = { sound, "x" } } } },
		{ belts = { A = { reigns = { { holder = "Varkoth", since = T0, last = T0, defences = 0, ends = "x" } } } } },
	}
	for i, belts in ipairs(broken) do
		for name, fn in pairs({ Holder = R.Holder, Belt = R.Belt, Lineage = R.Lineage }) do
			local ok, err = pcall(fn, belts, G)
			eq(ok, true, name .. ", state " .. i .. ": " .. tostring(err))
		end
		eq((pcall(R.BeltsOf, belts, "Varkoth")), true, "BeltsOf, state " .. i)
		eq((pcall(R.Contender, built, belts, G)), true, "Contender, state " .. i)
		eq((pcall(R.Podium, built, belts, G)), true, "Podium, state " .. i)
		eq((pcall(R.Tiers, built, G, belts)), true, "Tiers, state " .. i)
		eq(R.Holder(belts, G), nil, "state " .. i); eq(R.Belt(belts, G), nil, "state " .. i)
		eq(#R.Lineage(belts, G), 0, "state " .. i); eq(#R.BeltsOf(belts, "Varkoth"), 0, "state " .. i)
	end
	-- A sound reign in an otherwise odd table still reads, the odd parts as nothing.
	local odd = { belts = { A = { reigns = { sound }, contender = "x", podium = "x" }, [5] = { reigns = {} } }, vac = "x" }
	eq(R.Holder(odd, G), "Varkoth")
	local b = R.Belt(odd, G)
	eq(b.vacatesAt, T0 + VAC); eq(b.contender, nil); eq(next(b.podium), nil)
	eq(table.concat(R.BeltsOf(odd, "Varkoth"), ","), G)
	eq(R.Contender(built, odd, G), "Aldric")
	eq(R.Tiers(built, G, odd).Varkoth, "gold")
end)

---------------------------------------------------------------------------
-- 1.1.6: the level factor (a duel's points consider the levels). The numbers were worked out by
-- hand: a level counts as 50 rating points; 1000 / (1 + 10 ^ (gap / 400)) rounded; the change
-- K x (score - expected) / 1000 rounded half up.
---------------------------------------------------------------------------

test("1.1.6 arena rating, the level factor: the expected score counts a level as 50 points, both sides add up to 1000, the cap holds, equal or unknown levels change nothing", function()
	eq(R.LEVEL_POINTS, 50)
	eq(R.Expected(1500, 1500, 60, 60), 500, "equal levels")
	eq(R.Expected(1500, 1500, 50, 60), 53, "10 levels under: a 500 gap")
	eq(R.Expected(1500, 1500, 60, 50), 947)
	eq(R.Expected(1500, 1500, 60, 59), 571, "one level over: a 50 gap the other way (1000 - 429)")
	eq(R.Expected(1500, 1500, 44, 60), 10, "16 levels under: the cap's 800")
	eq(R.Expected(1500, 1500, 30, 60), 10, "30 levels under still counts as 800")
	eq(R.Expected(1600, 1500, 50, 60), 91, "the ratings' gap and the levels' add up: -100 + 500 = 400")
	eq(R.Expected(1500, 1600, 60, 58), 500, "...and cancel out: 100 - 100")
	-- No level: a fight rates as it always did.
	for _, bad in ipairs({ { nil, 60 }, { 60, nil }, { 0, 60 }, { 60, 101 }, { 59.5, 60 }, { "60", 50 }, { 0 / 0, 60 }, { math.huge, 1 } }) do
		eq(R.Expected(1500, 1500, bad[1], bad[2]), 500, tostring(bad[1]) .. " vs " .. tostring(bad[2]))
		eq(R.LevelGap(bad[1], bad[2]), 0)
	end
	eq(R.Expected(1500, 1900, nil, 60), R.Expected(1500, 1900))
	for gap = -40, 40 do
		local la, lb = 60, 60 + gap
		if lb >= 1 and lb <= R.LEVEL_MAX then
			eq(R.Expected(1500, 1520, la, lb) + R.Expected(1520, 1500, lb, la), 1000, "levels " .. la .. " vs " .. lb)
		end
	end
	eq(R.LevelGap(50, 60), 500); eq(R.LevelGap(60, 50), -500)
end)

test("1.1.6 arena rating, the level factor: beating a higher level is worth more, beating a much lower one nothing, losing to a much higher one costs little", function()
	-- Equal ratings, K 24.
	eq(R.Delta(1500, 1500, true, 24, 0, 60, 60), 12, "equal levels: as before")
	eq(R.Delta(1500, 1500, true, 24, 0, 50, 60), 23, "beating 10 levels up: 24 x 947 / 1000 = 22.7")
	eq(R.Delta(1500, 1500, false, 24, 0, 60, 50), -23, "losing 10 levels down costs as much")
	eq(R.Delta(1500, 1500, true, 24, 0, 60, 50), 1, "beating 10 levels down: 24 x 53 / 1000 = 1.27")
	eq(R.Delta(1500, 1500, false, 24, 0, 50, 60), -1, "losing to 10 levels up: -1.27")
	eq(R.Delta(1500, 1500, true, 24, 0, 60, 44), 0, "beating 16 levels down: 24 x 10 / 1000 = 0.24, nothing")
	eq(R.Delta(1500, 1500, false, 24, 0, 44, 60), 0, "losing to 16 levels up: -0.24, nothing")
	eq(R.Delta(1500, 1500, true, 40, 0, 60, 44), 0, "a newcomer's K 40 too: 0.4")
	eq(R.Delta(1500, 1500, false, 40, 0, 44, 60), 0, "-0.4")
	eq(R.Delta(1500, 1500, true, 24, 0, 44, 60), 24, "the biggest upset: 24 x 990 / 1000 = 23.76")
	eq(R.Delta(1500, 1500, true, 24, 0, 60, 30), 0, "far past the cap: nothing")
	-- A win is never worth less against a higher level, nor more against a lower one.
	local before = -1
	for other = 1, R.LEVEL_MAX do
		local d = R.Delta(1500, 1500, true, 24, 0, 60, other)
		assert(d >= before, "a win over level " .. other .. " (" .. d .. ") is worth less than over " .. (other - 1))
		before = d
	end
	eq(R.Delta(1500, 1500, true, 24, 0, nil, 30), 12, "an unknown level: as before")
end)

test("1.1.6 arena rating, the level factor: Build rates with the weigh-in's levels, the same on every client whatever order the fights came in; a duplicate that differs only in a level keeps one record", function()
	local list = {
		Fight("v1", "Low", "High", "Low", T0, { aLevel = 50, bLevel = 60 }),
		Fight("v2", "High", "Mid", "High", T0 + HOUR, { aLevel = 60, bLevel = 59 }),
		Fight("v3", "Mid", "Low", "Mid", T0 + 2 * HOUR, { aLevel = 59 }), -- (Low's level unknown here)
	}
	local built = R.Build(list)
	-- v1: K 40 each, equal ratings, Low 10 levels under High: expected 53, so Low +38 (40 x 947 /
	-- 1000 = 37.88) and High -38.
	-- v2: High 1462 (level 60) beats Mid 1500 (59): High's gap 38 - 50 = -12, expected 1000 - 483
	-- = 517, +19 (19.32); Mid -19.
	-- v3: Low's level unknown, the ratings alone: Mid 1481 beats Low 1538, expected 419, +23
	-- (23.24); Low -23.
	eq(Deltas(built, "Low"), "38,-23"); eq(Deltas(built, "High"), "-38,19"); eq(Deltas(built, "Mid"), "-19,23")
	eq(R.Rating(built, "Low"), 1515); eq(R.Rating(built, "High"), 1481); eq(R.Rating(built, "Mid"), 1504)
	local again = R.Build({ list[3], list[1], list[2] })
	for _, key in ipairs({ "Low", "High", "Mid" }) do eq(R.Rating(again, key), R.Rating(built, key), key) end
	-- One id twice, the levels told apart: one record, the same one whatever the order.
	local x = Fight("w1", "Ann", "Bea", "Ann", T0, { aLevel = 40, bLevel = 50 })
	local y = Fight("w1", "Ann", "Bea", "Ann", T0, { aLevel = 50, bLevel = 50 })
	eq(R.Rating(R.Build({ x, y }), "Ann"), R.Rating(R.Build({ y, x }), "Ann"))
end)

test("1.1.6 arena rating, the level factor: the ledger hands the weigh-in's levels to the ratings (ArenaLedger.Fight)", function()
	local w = H.World.New()
	local king = w:Role("king")
	w:As(king, function()
		local LG = king.ns.ArenaLedger
		local e = { fid = "Fv1", t = T0, gkA = "Player-1-0000000A", gkB = "Player-1-0000000B", w = "A", m = "K", dur = 60, sc = "1:0", fl = "r",
			fA = { class = "WA", race = 1, level = 50 }, fB = { class = "MA", race = 4, level = 60 } }
		local f = LG.Fight(e, true)
		eq(f.aLevel, 50); eq(f.bLevel, 60); eq(f.counts, true)
		local built = king.ns.ArenaRating.Build({ f })
		eq(king.ns.ArenaRating.Rating(built, e.gkA), 1538, "the lower level's win: +38")
		e.fA, e.fB = nil, nil -- (no weigh-in: no levels, rated as before)
		f = LG.Fight(e, true)
		eq(f.aLevel, nil); eq(f.bLevel, nil)
		eq(king.ns.ArenaRating.Rating(king.ns.ArenaRating.Build({ f }), e.gkA), 1520)
	end)
	for _, c in ipairs(w.clients) do for _, err in ipairs(c.errors) do error(c.name .. ": " .. err) end end
end)
