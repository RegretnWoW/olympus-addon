local H = ...
local ns = {}
assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
assert(loadfile(H.ADDON_DIR .. "ArenaFarkle.lua"))("Olympus", ns)
local F, eq = ns.FarkleRules, H.eq
local function Snapshot(value)
	if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
	local keys, out = {}, {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(keys) do out[#out + 1] = Snapshot(key) .. "=" .. Snapshot(value[key]) end
	return "{" .. table.concat(out, ";") .. "}"
end
local fields = { target = 5000, first = 1 }
local function Roll(p, dice) return { t = "R", p = p, k = #dice, value = F.Encode(dice) } end
local first = Roll(1, { 1, 2, 2, 3, 3, 6 })
local function Game() return assert(F.New(fields)) end
local function Refused(g, fn, why)
	local before = Snapshot(g)
	local ok, err = fn()
	eq(ok, nil); eq(err, why); eq(Snapshot(g), before, "a rejected action changes no game field")
end

local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local function RelayTable(arbiter)
	local w = FW.New()
	local a = w:Player(H.World.NAMES.fighterA)
	local b = w:Player(H.World.NAMES.fighterB)
	local arb = arbiter and w:Player(H.World.NAMES.arbiter) or nil
	w:Group({ a, b, arb })
	local function Call(c, fn, ...) return w:As(c, fn, ...) end
	local id = assert(Call(a, a.ns.FarkleTable.Create, { guest = b.name, target = 5000,
		rehearsal = true, mode = arb and "a" or "d", arbiter = arb and arb.name, spectators = false }))
	w:Run(0)
	assert(Call(b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	if arb then assert(Call(arb, arb.ns.FarkleTable.AnswerArbiter, id, true)); w:Run(0) end
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Call(a, a.ns.FarkleTable.Roll, id); Call(b, b.ns.FarkleTable.Roll, id); w:Run(0)
	return w, a, b, arb, id
end

H.test("Bones invalid actions: direct and arbiter live relays reject the whole penalty batch", function()
	for _, arbitration in ipairs({ true, false }) do
		for _, prefix in ipairs({ false, true }) do
			local w, a, b, arb, id = RelayTable(arbitration)
			local t = a.ns.FarkleTable.Get(id)
			local rules, peer = a.ns.FarkleRules, arb or b
			assert(rules.Apply(t.game, { t = "R", p = 1, k = 6, value = rules.Encode({ 1, 2, 2, 3, 3, 6 }) }))
			if not prefix then assert(rules.Apply(t.game, "K1:1:r")) end
			t.resync = { to = peer.name, at = 17 }
			if arbitration and prefix then t.lateFloor = true end
			local game, resync = Snapshot(t.game), Snapshot(t.resync)
			local before = Snapshot({ disputed = t.disputed, against = t.disputedAgainst, state = t.state,
				lateFloor = t.lateFloor, pending = t.pending })
			local codes = prefix and "K1:1:r,F1" or "F1"
			local envelope = "KR~" .. t.mode .. a.ns.Arena.PROTO .. "~" .. id .. "~" .. a.ns.Arena.B36(t.game.step) .. "~" .. codes
			w:As(a, a.comm.handlers.KR, "WHISPER", peer.name, envelope)
			eq(Snapshot(t.game), game, "no accepted prefix or penalty from a rejected batch")
			eq(Snapshot(t.resync), resync, "a rejected relay does not acknowledge resync")
			eq(Snapshot({ disputed = t.disputed, against = t.disputedAgainst, state = t.state,
				lateFloor = t.lateFloor, pending = t.pending }), before, "no dispute or rebuild side effects")
			for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
		end
	end
end)

H.test("Bones invalid actions: wrong count/range, invalid picks and live F are immutable refusals", function()
	local g = Game()
	assert(F.Apply(g, first)); assert(F.Keep(g, 1, { 1 }))
	Refused(g, function() return F.Apply(g, Roll(1, { 1, 1, 1, 2, 3, 4 })) end, "count")
	Refused(g, function() return F.Apply(g, { t = "R", p = 1, k = 5, value = 7777 }) end, "range")
	Refused(g, function() return F.Roll(g, 1, 7777) end, "range")
	Refused(g, function() return F.Apply(g, "F1") end, "event")
	Refused(g, function() return F.Foul(g, 1) end, "event")
	assert(F.Roll(g, 1, F.Encode({ 1, 2, 2, 3, 3 })))
	Refused(g, function() return F.Apply(g, "K1:2:b") end, "score")
	eq(g.turn.points, 100); eq(g.current, 1)
end)

H.test("Bones invalid actions: bad held count cannot cancel a valid bank or first valid roll", function()
	local g = Game()
	assert(F.Apply(g, first)); assert(F.Apply(g, Roll(1, { 1, 1, 1, 2, 3, 4 })))
	assert(F.Apply(g, "K1:1:b")); eq(g.scores[1], 100); eq(g.current, 2)
	eq(#g.queue, 0); eq(g.events[#g.events], "K1:1:b")
	local q = Game()
	assert(F.Apply(q, first)); assert(F.Apply(q, Roll(1, { 1, 1, 1, 2, 3, 4 })))
	local valid = Roll(1, { 5, 2, 2, 3, 3 })
	assert(F.Apply(q, valid)); local ok, note = F.Apply(q, "K1:1:b")
	eq(ok, true); eq(note, "stands"); eq(q.current, 1); eq(q.turn.points, 100)
	eq(q.events[#q.events], F.Code(valid)); eq(q.turn.phase, "keep")
	local held = Game()
	assert(F.Apply(held, first)); assert(F.Apply(held, Roll(1, { 1, 1, 1, 2, 3, 4 })))
	assert(F.Apply(held, "K1:1:r")); eq(held.turn.points, 100); eq(held.current, 1)
	eq(held.turn.phase, "roll"); eq(#held.queue, 0); eq(held.last, nil)
end)

H.test("Bones invalid actions: old F history replays while valid zero-score dice still bust", function()
	local old = { F.Code(first), "K1:1:r", "F1" }
	local g = assert(F.Replay(fields, old))
	eq(g.last.how, "foul"); eq(g.last.lost, 100); eq(g.current, 2)
	eq(table.concat(g.events, " "), table.concat(old, " "))
	local q = Game()
	assert(F.Apply(q, Roll(1, { 2, 2, 3, 3, 4, 6 })))
	eq(q.last.how, "farkle"); eq(q.current, 2)
	local wrong, why = F.Replay(fields, { "F2" })
	eq(wrong, nil); eq(why, "turn", "legacy replay still validates the acting seat")
end)
