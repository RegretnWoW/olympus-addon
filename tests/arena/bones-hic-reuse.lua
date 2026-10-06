local H = ...
local ns = {}
assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
local R, eq, test = ns.FarkleRules, H.eq, H.test
local function Game(rule)
	return assert(R.New({ target = 2000, first = 1, hiccup = true, hiccupRule = rule }))
end

test("Bones HIC reuse: exact conditional odds and canonical ordered outcomes", function()
	local totals = { 4, 16, 60, 204, 600, 1440 }
	for n = 1, 6 do
		for lvl = 0, 3 do
			local wins, total, pct = R.HiccupOdds(n, lvl)
			eq(total, totals[n]); eq(wins, math.floor(total * R.HICCUP[lvl] / 100 + 0.5))
			eq(pct, 100 * wins / total)
		end
	end
	-- Exhaustively exercise actual result API, including permutations, for small dice counts.
	for n = 1, 3 do
		for lvl = 0, 3 do
			local eligible, successes = 0, 0
			for value = 1, R.RANGES[n] do
				local dice = R.Decode(value, n)
				if R.Farkle(dice) then
					local saved, rank, wins, total = R.HiccupReuse(dice, lvl)
					assert(rank >= 1 and rank <= total); eq(saved, rank <= wins)
					eligible = eligible + 1; if saved then successes = successes + 1 end
				end
			end
			eq(eligible, totals[n]); eq(successes, R.HiccupOdds(n, lvl))
		end
	end
	eq(select(2, R.HiccupReuse({ 2, 3 }, 3)), 2)
	eq(select(2, R.HiccupReuse({ 3, 2 }, 3)), 5, "order, not a sum")
	eq(R.HiccupReuse({ 1 }, 3), nil); eq(R.HiccupReuse({ 5 }, 3), nil)
	eq(R.HiccupReuse({ 2, 2, 2 }, 3), nil); eq(R.HiccupReuse({ 7 }, 3), nil)
	eq(R.HiccupOdds(0, 3), nil); eq(R.HiccupOdds(7, 3), nil)
	eq(R.HiccupOdds(1, 4), nil); eq(R.HiccupReuse({}, 3), nil)
end)

test("Bones HIC reuse: authenticated throw restores points without another roll or H event", function()
	local g = Game("bones2")
	assert(g.head:find("farkle2h", 1, true))
	assert(R.Floor(g, 1, 1, 3))
	assert(R.Roll(g, 1, R.Encode({ 1, 2, 3, 4, 6, 2 })))
	assert(R.Keep(g, 1, { 1 }))
	local ok, note = R.Apply(g, { t = "R", p = 1, k = 5, value = R.Encode({ 2, 2, 3, 3, 4 }) })
	eq(ok, true); eq(note, "shaken"); eq(g.turn.points, 100)
	eq(g.turn.left, 5); eq(g.turn.phase, "roll"); eq(g.shakes[1], 1)
	local wins, total, pct = R.HiccupTurnOdds(g, 1)
	eq(wins, 198); eq(total, 600); eq(pct, 33)
	eq(R.HiccupTurnOdds(g, 3), nil); eq(R.HiccupTurnOdds({}, 1), nil)
	for _, code in ipairs(g.events) do assert(not code:find("^H")) end
	local before, step, lines = R.Transcript(g), g.step, g.lines
	eq(R.Apply(g, { t = "H", p = 1, value = 1 }), nil)
	eq(R.Hiccup(g, 1, 1), nil)
	eq(R.Roll(g, 1, 0), nil)
	eq(R.Transcript(g), before); eq(g.step, step); eq(g.lines, lines)
	local replay = assert(R.Replay({ target = 2000, first = 1, hiccup = true, hiccupRule = "bones2" }, g.events))
	eq(R.Transcript(replay), before); eq(replay.turn.points, 100)
	local fail = Game("bones2"); assert(R.Floor(fail, 1, 1, 3))
	assert(R.Roll(fail, 1, R.Encode({ 6, 6, 4, 4, 3, 3 })))
	eq(fail.current, 2); eq(fail.shakes[1], 0)
	local spent = Game("bones2"); assert(R.Floor(spent, 1, 1, 3))
	for i = 1, R.SHAKES do
		assert(R.Roll(spent, 1, R.Encode({ 2, 2, 3, 3, 4, 4 })))
		eq(spent.shakes[1], i); eq(spent.current, 1)
	end
	assert(R.Roll(spent, 1, R.Encode({ 2, 2, 3, 3, 4, 4 })))
	eq(spent.current, 2); eq(spent.shakes[1], R.SHAKES)
end)

test("Bones HIC reuse: legacy H transcripts retain their original rules", function()
	local g = Game()
	eq(R.HiccupTurnOdds(g, 1), nil)
	assert(g.head:find("farkle1h", 1, true)); assert(R.Floor(g, 1, 1, 3))
	assert(R.Roll(g, 1, R.Encode({ 2, 2, 3, 3, 4, 4 })))
	eq(g.turn.phase, "hiccup"); assert(R.Apply(g, { t = "H", p = 1, value = 1 }))
	local replay = assert(R.Replay({ target = 2000, first = 1, hiccup = true }, g.events))
	eq(R.Transcript(replay), R.Transcript(g)); eq(replay.shakes[1], 1)
	local legacyF = assert(R.Replay({ target = 2000, first = 1, hiccup = true }, { "F1" }))
	eq(legacyF.events[1], "F1"); eq(legacyF.current, 2, "saved old penalties remain historical, not live actions")
	eq(R.New({ target = 2000, hiccup = true, hiccupRule = "unknown" }), nil)
	eq(R.New({ target = 2000, hiccupRule = "bones2" }), nil)
	eq(R.Replay({ target = 2000, first = 1, hiccup = true, hiccupRule = "bones2" }, { "F1" }), nil)
end)

test("Bones HIC reuse: warm odds cache does no enumeration and score mutations invalidate it", function()
	R.HiccupOdds(6, 3)
	local original, calls = R.Farkle, 0
	R.Farkle = function(...) calls = calls + 1; return original(...) end
	for _ = 1, 100 do R.HiccupOdds(6, 3) end
	eq(calls, 0, "repeated UI odds do no outcome enumeration")
	local old = R.SCORES.single[2]
	R.SCORES.single[2] = 100
	local _, total = R.HiccupOdds(1, 3)
	eq(total, 3); assert(calls > 0)
	R.SCORES.single[2] = old
	eq(select(2, R.HiccupOdds(1, 3)), 4)
	R.Farkle = original
end)

local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local function Table()
	local w = FW.New({ compliance = "shipped" })
	local a, b = w:Player(H.World.NAMES.fighterA), w:Player(H.World.NAMES.fighterB)
	w:Group({ a, b })
	local id = assert(w:As(a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, hic = true, spectators = false }))
	w:Run(0)
	return w, a, b, id
end
local function Call(w, c, fn, ...) return w:As(c, fn, ...) end
local function Envelope(c, op, t, body)
	return op .. "~" .. t.mode .. c.ns.Arena.PROTO .. "~" .. body
end

test("Bones HIC reuse: free peers negotiate and share the same original-throw proof", function()
	local w, a, b, id = Table()
	assert(Call(w, b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	local ta, tb = a.ns.FarkleTable.Get(id), b.ns.FarkleTable.Get(id)
	eq(ta.hiccupRule, "bones2"); eq(tb.hiccupRule, "bones2"); assert(ta.hic and tb.hic)
	eq(ta.stake, 0); eq(ta.game.head, tb.game.head)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Call(w, a, a.ns.FarkleTable.Roll, id); Call(w, b, b.ns.FarkleTable.Roll, id); w:Run(0)
	w:Drink(a.name, 3); w:Run(0)
	-- The opponent's next legitimate decision records the drunk level for the next turn.
	for _, c in ipairs({ a, b }) do
		w:QueueRoll(c.name, (c.ns.FarkleRules.Encode({ 1, 2, 3, 4, 6, 2 })))
		assert(Call(w, c, c.ns.FarkleTable.Roll, id)); w:Run(0)
		assert(Call(w, c, c.ns.FarkleTable.Keep, { 1 }, "b", id)); w:Run(0)
	end
	eq(ta.game.level[1], 3); eq(tb.game.level[1], 3)
	w:QueueRoll(a.name, (a.ns.FarkleRules.Encode({ 1, 2, 3, 4, 6, 2 })))
	assert(Call(w, a, a.ns.FarkleTable.Roll, id)); w:Run(0)
	assert(Call(w, a, a.ns.FarkleTable.Keep, { 1 }, "r", id)); w:Run(0)
	local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	local board = Call(w, a, function() return H.LoadCompanion(a.ns).ArenaUI.FarkleBoard end)
	Call(w, a, board.Show, id)
	w:QueueRoll(a.name, (a.ns.FarkleRules.Encode({ 2, 2, 3, 3, 4 })))
	local rolls = #w:Rolls(a.name)
	assert(Call(w, a, a.ns.FarkleTable.Roll, id)); w:Run(0)
	eq(#w:Rolls(a.name), rolls + 1, "no additional HIC server roll")
	eq(ta.game.turn.phase, "roll"); eq(ta.game.shakes[1], 1); eq(tb.game.shakes[1], 1)
	eq(ta.game.turn.points, 100); eq(a.ns.FarkleRules.Hash(ta.game), b.ns.FarkleRules.Hash(tb.game))
	eq(Call(w, a, a.ns.FarkleTable.Hiccup, id), false); eq(#w:Rolls(a.name), rolls + 1)
	for _, code in ipairs(ta.game.events) do assert(not code:find("^H")) end
	local view = Call(w, a, a.ns.FarkleTable.View, id)
	eq(view.levels[1].wins, 198); eq(view.levels[1].total, 600)
	local before = a.ns.FarkleRules.Transcript(ta.game)
	-- An unsolicited percentile line cannot become a decision, penalty, or extra shake-off.
	w:Line(a, ("%s rolls 1 (1-100)"):format(a.name)); w:Run(0)
	eq(a.ns.FarkleRules.Transcript(ta.game), before)
	ta.resync = { to = b.name, at = 17 }
	Call(w, a, a.comm.handlers.KR, "WHISPER", b.name, Envelope(a, "KR", ta, id .. "~" .. a.ns.Arena.B36(ta.game.step) .. "~H1:1"))
	eq(ta.resync.at, 17); eq(a.ns.FarkleRules.Transcript(ta.game), before)
	w:Run(2)
	local parts = board._.parts()
	eq(parts.rows[1].mug.wins, 198); eq(parts.rows[1].mug.total, 600)
	local logs = {}; for _, line in ipairs(parts.logs) do logs[#logs + 1] = line:GetText() end
	assert(table.concat(logs, " "):find("saved the original throw", 1, true), "the actual R animation reports its HIC save")
	eq(board._.S.hic, nil, "no HIC countdown or button phase")
	w:QueueRoll(a.name, (a.ns.FarkleRules.Encode({ 6, 6, 4, 4, 3 })))
	assert(Call(w, a, a.ns.FarkleTable.Roll, id)); w:Run(2)
	eq(ta.game.current, 2); eq(ta.game.shakes[1], 1); eq(tb.game.shakes[1], 1)
	eq(a.ns.FarkleRules.Hash(ta.game), b.ns.FarkleRules.Hash(tb.game))
	eq(#a.K.errors, 0)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
end)

test("Bones HIC reuse: old acceptance and mismatched start markers fail closed", function()
	local w, a, b, id = Table()
	local ta = a.ns.FarkleTable.Get(id)
	Call(w, a, a.comm.handlers.KA, "WHISPER", b.name, Envelope(a, "KA", ta, id .. "~1~-~1"))
	eq(ta.state, "invite"); eq(ta.game, nil); assert(ta.hic)
	-- Give genuine local consent while the host is offline, so no normal KG can race this test.
	a.online = false
	assert(Call(w, b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	a.online = true
	local tb = b.ns.FarkleTable.Get(id)
	eq(tb.state, "agreed")
	local fields = { id, a.ns.FarkleTable.Digest(ta), a.name, b.name, "-", "2", a.ns.Arena.B36(ta.secs), "1" }
	Call(w, b, b.comm.handlers.KG, "WHISPER", a.name, Envelope(b, "KG", tb, table.concat(fields, "~")))
	eq(tb.state, "agreed"); eq(tb.game, nil)
	fields[8] = "0"
	Call(w, b, b.comm.handlers.KG, "WHISPER", a.name, Envelope(b, "KG", tb, table.concat(fields, "~")))
	eq(tb.state, "agreed"); eq(tb.game, nil)
	fields[8] = "2"
	Call(w, b, b.comm.handlers.KG, "WHISPER", a.name, Envelope(b, "KG", tb, table.concat(fields, "~")))
	eq(tb.state, "open"); eq(tb.game.hiccupRule, "bones2", "the agreed new marker still starts normally")
	local oldId = Call(w, a, a.ns.Arena.NewId, "K")
	local oldOffer = table.concat({ oldId, "d", "0", "2", "-", "-", a.ns.Arena.B36(ta.secs), "1", ta.salt }, "~")
	local idle = w:Player("Idle Fighter-Realm")
	w:Group({ a, b, idle })
	Call(w, idle, idle.comm.handlers.KI, "WHISPER", a.name, Envelope(idle, "KI", tb, oldOffer))
	eq(idle.ns.FarkleTable.Get(oldId), nil, "old hiccup offers cannot create idle peers' live tables")
	for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
end)

test("Bones HIC reuse: arbiters explicitly acknowledge the new rule marker", function()
	local w = FW.New()
	local a, b, arb = w:Player(H.World.NAMES.fighterA), w:Player(H.World.NAMES.fighterB), w:Player(H.World.NAMES.arbiter)
	w:Group({ a, b, arb })
	local id = assert(Call(w, a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000,
		rehearsal = true, mode = "a", arbiter = arb.name, hic = true, spectators = false }))
	w:Run(0); assert(Call(w, b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	local ta = a.ns.FarkleTable.Get(id)
	eq(ta.state, "asked")
	Call(w, a, a.comm.handlers.KP, "WHISPER", arb.name, Envelope(a, "KP", ta, id .. "~1~-"))
	eq(ta.state, "asked"); eq(ta.arbiterYes, nil); eq(ta.game, nil)
	assert(Call(w, arb, arb.ns.FarkleTable.AnswerArbiter, id, true)); w:Run(0)
	local tb, tc = b.ns.FarkleTable.Get(id), arb.ns.FarkleTable.Get(id)
	eq(ta.game.hiccupRule, "bones2"); eq(tb.game.head, ta.game.head); eq(tc.game.head, ta.game.head)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
end)
