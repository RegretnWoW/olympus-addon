local H = ...
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local eq, test = H.eq, H.test
local function Snapshot(value, seen)
	if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
	seen = seen or {}
	if seen[value] then return "seen:" .. seen[value] end
	local keys, out = {}, {}; seen[value] = tostring(value)
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(keys) do out[#out + 1] = Snapshot(key, seen) .. "=" .. Snapshot(value[key], seen) end
	return "{" .. table.concat(out, ";") .. "}"
end
local function Call(w, c, fn, ...) return w:As(c, fn, ...) end
local function KG(w, a, receiver, id)
	local t = a.ns.FarkleTable.Get(id)
	local body = table.concat({ id, a.ns.FarkleTable.Digest(t), a.name, t.guest, t.arbiter or "-",
		"2", a.ns.Arena.B36(t.secs), "2", "0", "0" }, "~")
	Call(w, receiver, receiver.comm.handlers.KG, "WHISPER", a.name, "KG~" .. t.mode .. a.ns.Arena.PROTO .. "~" .. body)
end
local function Unchanged(w, a, receiver, id, state)
	local t = receiver.ns.FarkleTable.Get(id)
	local before = { t.state, t.game, t.own, t.clock, t.noWatch, t.crowd, t.hic, t.hiccupRule, t.resync }
	local record = Snapshot(t)
	eq(t.state, state); eq(t.game, nil)
	KG(w, a, receiver, id)
	local after = { t.state, t.game, t.own, t.clock, t.noWatch, t.crowd, t.hic, t.hiccupRule, t.resync }
	for i = 1, 9 do eq(after[i], before[i], "KG without local acceptance changes no start field " .. i) end
	eq(Snapshot(t), record, "the entire participant record stays unchanged")
end

test("Bones start consent: matching host KG cannot open a guest before local Answer", function()
	local w = FW.New({ compliance = "shipped" })
	local a, b = w:Player(H.World.NAMES.fighterA), w:Player(H.World.NAMES.fighterB)
	w:Group({ a, b })
	local id = assert(Call(w, a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, hic = true, spectators = false }))
	w:Run(0)
	Unchanged(w, a, b, id, "invite")
	assert(Call(w, b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	local ta, tb = a.ns.FarkleTable.Get(id), b.ns.FarkleTable.Get(id)
	eq(tb.state, "open"); assert(tb.game); eq(tb.game.head, ta.game.head)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
end)

test("Bones start consent: matching host KG cannot appoint an arbiter before local AnswerArbiter", function()
	local w = FW.New()
	local a, b, arb = w:Player(H.World.NAMES.fighterA), w:Player(H.World.NAMES.fighterB), w:Player(H.World.NAMES.arbiter)
	w:Group({ a, b, arb })
	local id = assert(Call(w, a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000,
		rehearsal = true, mode = "a", arbiter = arb.name, hic = true, spectators = false }))
	w:Run(0); assert(Call(w, b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	Unchanged(w, a, arb, id, "asked")
	assert(Call(w, arb, arb.ns.FarkleTable.AnswerArbiter, id, true)); w:Run(0)
	local ta, tb, tc = a.ns.FarkleTable.Get(id), b.ns.FarkleTable.Get(id), arb.ns.FarkleTable.Get(id)
	eq(tc.state, "open"); assert(tc.game); eq(tc.game.head, ta.game.head); eq(tb.game.head, ta.game.head)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0) end
end)
