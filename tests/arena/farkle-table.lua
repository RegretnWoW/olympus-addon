-- 1.2, the Bone Throw tables: Bone Throw's table (Olympus/FarkleTable.lua; the rules are ArenaFarkle.lua's, tested
-- in ArenaFarkle.lua): the protocol by whisper between the players and the arbiter, the server's
-- roll lines witnessed by every client, the clocks, resync and the divergence rule, the stakes
-- glue, the tavern rule (the design), the hiccup (the design), spectators, practice against the House,
-- the self-test and the tester log. On the test world (tests/arena/lib/world.lua) with the
-- table's own additions (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local P1, P2, ARB = N.fighterA, N.fighterB, N.arbiter

-- A module of a client, its functions run as that client.
local function As(w, c, mod)
	return setmetatable({}, { __index = function(_, k)
		local m = c.ns[mod or "FarkleTable"]
		local v = m[k]
		if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
		return v
	end })
end
local function FT(w, c) return As(w, c, "FarkleTable") end
local function Get(c, id) return c.ns.FarkleTable.Get(id) end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function Types(list)
	local out = {}
	for _, s in ipairs(list) do out[#out + 1] = s.msg:sub(1, 2) end
	return table.concat(out, " ")
end
local function Has(list, text)
	for _, l in ipairs(list or {}) do
		local s = type(l) == "table" and l.text or l
		if tostring(s):find(text, 1, true) then return true end
	end
	return false
end
-- A roll of these dice (FarkleRules.Encode): the value /roll 1-6^n gives them.
local function Roll(c, dice) return (c.ns.FarkleRules.Encode(dice)) end
local SIX_FARKLE = { 2, 3, 4, 6, 2, 3 }     -- nothing scores
local ONE_FIVE = { 1, 5, 2, 3, 4, 6 }       -- a 1 and a 5 (150), positions 1 and 2

-- Two players (and an arbiter when asked) grouped; a rehearsal table the first opens with the
-- second, invited, answered and opened; the opening rolled (the first player first). Returns the
-- world, the clients and the id. (Watchers are allowed unless a player says no, since 2026-10-04;
-- these tables say no, as they did before, unless a test lets them in: o.spectators,
-- o.guestSpectators.)
local function Table(o)
	o = o or {}
	local w = FW.New({ seed = o.seed })
	local a = w:Player(P1, o.whereA)
	local b = w:Player(P2, o.whereB)
	local arb = o.arbiter and w:Player(ARB, o.whereArb) or nil
	for _, name in ipairs(o.others or {}) do w:Player(name) end
	w:Group({ a, b, arb }, o.raid)
	if o.matchMid then rawset(b.ns, "ArenaMatch", { Vet = function() return true, o.matchMid end }) end
	local id, why = FT(w, a).Create({ guest = b.name, target = o.target or 2000, rehearsal = o.rehearsal ~= false, mode = arb and "a" or "d",
		arbiter = arb and arb.name or nil, hic = o.hic, spectators = o.spectators == true, stake = o.stake, src = o.src, secs = o.secs, from = o.from })
	assert(id, "create: " .. tostring(why))
	w:Run(0)
	if o.noAnswer then return w, a, b, id, arb end
	assert(FT(w, b).Answer(id, true, o.guestSrc, { hic = o.guestHic, spectators = o.guestSpectators == true }))
	w:Run(0)
	if arb then
		assert(FT(w, arb).AnswerArbiter(id, true))
		w:Run(0)
	end
	if o.noOpening then return w, a, b, id, arb end
	w:QueueRoll(a.name, 90)
	w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id)
	FT(w, b).Roll(id)
	w:Run(0)
	return w, a, b, id, arb
end

print("FarkleTable: invitation, opening, handshake")

test("1.2 the Bone Throw tables: a direct rehearsal table: KI, KA, KG by whisper, the opening rolls read from each client's own lines, KY, then play", function()
	local w, a, b, id = Table({ noOpening = true })
	NoErrors(w)
	eq(Types(w:Sent({ from = a })), "KI KG")
	eq(Types(w:Sent({ from = b })), "KA")
	for _, s in ipairs(w.sent) do eq(s.dist, "WHISPER") end
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.state, "open"); eq(tb.state, "open")
	eq(ta.mode, "T"); eq(tb.mode, "T")
	-- the opening: the higher roll starts, from the lines each client read itself
	w:QueueRoll(a.name, 12); w:QueueRoll(b.name, 77)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(0)
	eq(a.asked[1].hi, 100); eq(b.asked[1].hi, 100)
	eq(ta.state, "play"); eq(tb.state, "play")
	eq(ta.game.current, 2); eq(tb.game.current, 2)
	eq(ta.game.chain, tb.game.chain)
	eq(Types(w:Sent({ from = a, type = "KY" })), "KY")
	eq(Types(w:Sent({ from = b, type = "KY" })), "KY")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a matched table ends the hand-off on both clients without adding its private id to KI", function()
	local w, a, b, id = Table({ from = "M7", matchMid = "M7" })
	local endedA, endedB
	rawset(a.ns, "ArenaMatch", { Ended = function(...) endedA = { ... } return true end })
	rawset(b.ns, "ArenaMatch", { Ended = function(...) endedB = { ... } return true end })
	assert(FT(w, a).Concede(id))
	w:Run(0)
	eq(endedA[1], "M7")
	eq(endedB[1], "M7", "Vet links the guest locally; KI still carries no match id")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a turn: Roll throws the dice left through RandomRoll, a decision (KK) goes to the other player only, both chains agree", function()
	local w, a, b, id = Table()
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.game.current, 1)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	assert(FT(w, a).Roll(id))
	w:Run(0)
	eq(a.asked[#a.asked].hi, 46656)
	eq(ta.game.turn.phase, "keep"); eq(tb.game.turn.phase, "keep")
	-- keep the 1 and the 5, roll the other four
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	w:Run(0)
	local kk = w:Sent({ from = a, type = "KK" })
	eq(#kk, 1); eq(kk[1].target:lower(), b.name:lower())
	eq(tb.game.turn.points, 150); eq(tb.game.turn.left, 4)
	w:QueueRoll(a.name, Roll(a, { 1, 1, 1, 2 }))
	assert(FT(w, a).Roll(id))
	w:Run(0)
	eq(a.asked[#a.asked].hi, 1296)
	assert(FT(w, a).Keep({ 1, 2, 3 }, "b", id))
	w:Run(0)
	eq(ta.game.scores[1], 1150); eq(tb.game.scores[1], 1150)
	eq(ta.game.current, 2); eq(tb.game.current, 2)
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

print("FarkleTable: witnessing (the design, W1-W4)")

test("1.2 the Bone Throw tables: the roll line in another language's positional format is read (RANDOM_ROLL_RESULT at call time)", function()
	local w, a, b, id = Table({ noOpening = true })
	local FMT = "%1$s wirft %2$d (%3$d-%4$d)."
	for _, c in ipairs({ a, b }) do c.globals.RANDOM_ROLL_RESULT = FMT end
	local function Line(c, v) w:Line(c, ("%s wirft %d (1-100)."):format(c.short, v)) end
	Line(a, 70); Line(b, 30)
	w:Run(0)
	eq(Get(a, id).state, "play"); eq(Get(b, id).state, "play")
	eq(Get(a, id).game.current, 1); eq(Get(b, id).game.current, 1)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: another group member's roll, an emote and a secret line never count; a /roll the player types counts like the button", function()
	local w, a, b, id = Table({ noOpening = true })
	local c = w:Player("Wenna Crale")
	w:Group({ a, b, c })
	-- a third member rolls 1-100: ignored at every table client
	w:TypedRoll(c.name, 1, 100, 99)
	-- an emote that looks like a roll: another event, never read
	w:Fire(b, "CHAT_MSG_EMOTE", a.short .. " rolls 100 (1-100)", a.short)
	-- a secret line: skipped before any string work, the table marked blind
	b.globals.issecretvalue = function(v) return v == "SECRET" end
	w:Fire(b, "CHAT_MSG_SYSTEM", "SECRET")
	eq(Get(b, id).blind, true)
	b.globals.issecretvalue = nil
	eq(Get(b, id).game.opening[1], nil); eq(Get(b, id).game.opening[2], nil)
	-- typed rolls: the server's line is the same
	w:TypedRoll(a.name, 1, 100, 40)
	w:TypedRoll(b.name, 1, 100, 60)
	w:Run(0)
	eq(Get(a, id).game.current, 2); eq(Get(b, id).game.current, 2)
	eq(Get(b, id).blind, nil)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a wrong count is refused without losing either client's turn", function()
	local w, a, b, id = Table()
	local ta, tb = Get(a, id), Get(b, id)
	local ca, cb = ta.game.chain, tb.game.chain
	w:TypedRoll(a.name, 1, 7776, 1)
	w:Run(0)
	for _, t in ipairs({ ta, tb }) do
		eq(t.game.current, 1); eq(t.game.last, nil); eq(t.game.turn.phase, "roll")
		eq(t.game.turn.points, 0); eq(t.game.scores[1], 0); eq(t.game.turns[1], 0)
	end
	eq(ta.game.chain, ca); eq(tb.game.chain, cb)
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a roll that overtakes the decision (W3) waits for it, then counts: every client writes one chain", function()
	local w, a, b, id = Table()
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	-- keep and roll at once: the roll line reaches the other client before the whispered KK
	w:QueueRoll(a.name, Roll(a, { 5, 5, 5, 2 }))
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	assert(FT(w, a).Roll(id))
	local tb = Get(b, id)
	eq(#tb.game.queue, 1, "held at the other client")
	w:Run(0)
	eq(#tb.game.queue, 0)
	eq(tb.game.turn.points, 150); eq(tb.game.turn.phase, "keep")
	eq(Get(a, id).game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a second roll before the decision is no better roll: it counts after the next decision, at every client", function()
	local w, a, b, id = Table()
	w:QueueRoll(a.name, Roll(a, ONE_FIVE), Roll(a, { 1, 1, 1, 1, 1, 1 }))
	FT(w, a).Roll(id)
	-- a second six-dice roll while his keep is due: held, never read in place of the first
	w:TypedRoll(a.name, 1, 46656)
	w:Run(0)
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.game.turn.dice[1], 1); eq(ta.game.turn.dice[2], 5)
	eq(#ta.game.queue, 1); eq(#tb.game.queue, 1)
	-- The held six-dice line is invalid after two dice are kept: discard it, not the turn.
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	w:Run(0)
	for _, t in ipairs({ ta, tb }) do
		eq(t.game.last, nil); eq(t.game.current, 1); eq(t.game.turn.phase, "roll")
		eq(t.game.turn.points, 150); eq(t.game.turn.left, 4); eq(#t.game.queue, 0)
	end
	eq(ta.game.chain, tb.game.chain)
	-- The first valid next roll counts normally, rather than selecting the discarded six.
	w:QueueRoll(a.name, Roll(a, { 5, 5, 5, 2 }))
	assert(FT(w, a).Roll(id)); w:Run(0)
	for _, t in ipairs({ ta, tb }) do
		eq(t.game.turn.phase, "keep"); eq(#t.game.turn.dice, 4)
		eq(t.game.turn.dice[1], 5); eq(t.game.turn.dice[4], 2); eq(t.game.turn.points, 150)
	end
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the name a line gives: First Surname on our realm, First Surname-Realm from another, in any case", function()
	local w = FW.New()
	local a = w:Player(P1)
	local LineIs = a.ns.FarkleTable.LineIs
	w:As(a, function()
		assert(LineIs("Torvin Hale", "Torvin Hale-Emberfall"))
		assert(LineIs("torvin hale", "Torvin Hale-Emberfall"))
		assert(LineIs("Torvin Hale-Emberfall2", "Torvin Hale-Emberfall2"))
		assert(not LineIs("Torvin Hale-Emberfall2", "Torvin Hale-Emberfall"))
		assert(not LineIs("Torvin", "Torvin Hale-Emberfall"))
	end)
end)

test("1.2 the Bone Throw tables: a table never starts in an instance or chat lockdown; an invitation there is refused", function()
	local w = FW.New()
	local a, b = w:Player(P1), w:Player(P2)
	w:Group({ a, b })
	a.instance = true
	local id, why = FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true })
	eq(id, nil); eq(why, "instance")
	a.instance = nil
	w:Lockdown(a, true)
	id, why = FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true })
	eq(id, nil); eq(why, "instance")
	w:Lockdown(a, false)
	b.instance = true
	id = FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true })
	w:Run(0)
	local ka = w:Sent({ from = b, type = "KA" })
	-- (an instance holds the guest's arena messages back: its refusal leaves once he is out)
	b.instance = nil
	w:Fire(b, "ZONE_CHANGED_NEW_AREA")
	w:Run(2)
	ka = w:Sent({ from = b, type = "KA" })
	eq(#ka, 1); assert(ka[1].msg:find("~0~c~", 1, true), ka[1].msg)
	eq(Get(a, id).state, "declined")
	NoErrors(w)
end)

test("1.2.0 the Bone Throw tables: a guest who hasn't played his first game with an innkeeper refuses with that reason, and both are told why", function()
	local w = FW.New()
	local a, b = w:Player(P1), w:Player(P2, { bonesTrained = false })
	w:Group({ a, b })
	local told
	b.ns.Print = function(msg) told = msg end
	local id = FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true })
	assert(id, "the host's invite goes")
	w:Run(0)
	local ka = w:Sent({ from = b, type = "KA" })
	eq(#ka, 1); assert(ka[1].msg:find("~0~f~", 1, true), ka[1].msg)
	eq(Get(a, id).state, "declined"); eq(Get(a, id).why, "f", "the host's reason: his first game")
	assert(a.ns.L.FARKLE_WHY_F ~= "FARKLE_WHY_F", "the host's words for it")
	assert(told and told:find(b.ns.L.FARKLE_INVITED_NOT_TRAINED:match("^%%s(.-)%."), 1, true), "the guest is told: " .. tostring(told))
	NoErrors(w)
end)

print("FarkleTable: the wire (the design)")

-- A table message as another client would send it (a forged or out-of-turn one).
local function Forge(w, from, to, kind, body, mode)
	w:As(from, function() assert(from.ns.Arena.Send(kind, mode or "T", body, { to = to.name })) end)
	w:Run(0)
end

test("1.2 the Bone Throw tables: a decision from the player not to act is ignored; a copy of one already taken is dropped", function()
	local w, a, b, id = Table()
	local tb = Get(b, id)
	local before = tb.game.step
	-- it is the first player's turn: the second sends a decision in his name's seat
	Forge(w, b, a, "KK", ("%s~%s~12~b~%s"):format(id, a.ns.Arena.B36(before), tb.game.chain))
	eq(Get(a, id).game.step, before)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	local step, chain = Get(a, id).game.step, Get(a, id).game.chain
	assert(FT(w, a).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	local after = tb.game.step
	-- the same KK again: a lower step, dropped
	Forge(w, a, b, "KK", ("%s~%s~12~b~%s"):format(id, a.ns.Arena.B36(step), chain))
	eq(tb.game.step, after)
	eq(Get(a, id).game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: KG from anyone but the host, or from outside the group, opens nothing; a KG whose digest differs aborts", function()
	local w, a, b, id = Table({ noAnswer = true })
	-- the guest's answer never reaches the host (offline a moment): the guest waits for KG
	a.online = false
	assert(FT(w, b).Answer(id, true))
	w:Run(0)
	a.online = true
	local tb = Get(b, id)
	eq(tb.state, "agreed")
	local body = FT(w, a).Digest(Get(a, id))
	local c = w:Player("Wenna Crale")
	w:Group({ a, b, c })
	Forge(w, c, b, "KG", ("%s~%s~%s~%s~-~2~%s~2"):format(id, body, a.name, b.name, "1o"))
	eq(tb.state, "agreed", "not from the host")
	w:Group({ b, c })
	Forge(w, a, b, "KG", ("%s~%s~%s~%s~-~2~%s~2"):format(id, body, a.name, b.name, "1o"))
	eq(tb.state, "agreed", "not from outside the group")
	w:Group({ a, b, c })
	Forge(w, a, b, "KG", ("%s~%s~%s~%s~-~2~%s~2"):format(id, "00000000", a.name, b.name, "1o"))
	eq(tb.state, "aborted"); eq(tb.why, "terms")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the KG digest covers the salt and every agreed term: nobody without the salt can check a guessed stake", function()
	local w = FW.New()
	local a = w:Player(P1)
	local base = { id = "K1", kind = "d", cur = "g", stake = 50000, src = { "o", "o" }, secs = 60, hic = true, mode = "L", host = a.name,
		guest = P2, target = 5000, salt = "ab12" }
	local function D(t) return w:As(a, a.ns.FarkleTable.Digest, t) end
	local d0 = D(base)
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	t.salt = "ab13"; assert(D(t) ~= d0, "the salt")
	t.salt = "ab12"; t.stake = 60000; assert(D(t) ~= d0, "the stake")
	t.stake = 50000; t.hic = false; assert(D(t) ~= d0, "the hiccup")
	t.hic = true; eq(D(t), d0)
end)

test("1.2 the Bone Throw tables: every table message goes by whisper to each other participant: a decision reaches the opponent and the arbiter only", function()
	local w, a, b, id, arb = Table({ arbiter = true })
	local c = w:Player("Wenna Crale")
	w:Group({ a, b, arb, c }, true)
	eq(Get(arb, id).state, "play")
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	local to = {}
	for _, s in ipairs(w:Sent({ from = a, type = "KK" })) do eq(s.dist, "WHISPER"); to[#to + 1] = s.target:lower() end
	table.sort(to)
	local want = { b.name:lower(), arb.name:lower() }
	table.sort(want)
	eq(table.concat(to, " "), table.concat(want, " "))
	-- (only a public table's notice and state go on the channel, the design: this arbiter is a
	-- signed, public one)
	for _, s in ipairs(w.sent) do assert(s.dist == "WHISPER" or s.msg:find("^K[NS]~"), s.msg) end
	eq(Get(arb, id).game.chain, Get(a, id).game.chain)
	eq(Get(c, id), nil, "a group member who isn't at the table gets nothing")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a client that lost its place (a /reload) finds its table in its saved data and asks the others (KQ): the rolls it missed come marked relayed", function()
	local w, a, b, id = Table()
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	w:Logout(b)
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	w:QueueRoll(a.name, Roll(a, { 5, 3, 3, 2 }))
	FT(w, a).Roll(id)
	w:Run(0)
	w:Login(b)
	w:Group({ a, b })
	w:Run(0)
	local tb = Get(b, id)
	assert(tb, "the table found again")
	eq(tb.reloaded, true)
	eq(#w:Sent({ from = b, type = "KQ" }), 1)
	eq(#w:Sent({ from = a, type = "KR" }) >= 1, true)
	eq(tb.game.chain, Get(a, id).game.chain)
	local last = tb.game.events[tb.game.step]
	assert(last:find("%*$"), "the roll it didn't see is marked relayed: " .. last)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: direct mode: a roll the actor made before his bank reached the other (W4) splits the records; the other player's witnessing decides, the dispute is recorded against the actor (the design)", function()
	local w, a, b, id = Table({ secs = 30 })
	local disputes = {}
	for _, c in ipairs({ a, b }) do
		c.ns.Debts.Disputed = function(ref, e) disputes[#disputes + 1] = { by = c.name, ref = ref, against = e.against } end
	end
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	-- he banks, and rolls four dice before his bank reaches the other client
	assert(FT(w, a).Keep({ 1, 2 }, "b", id))
	w:TypedRoll(a.name, 1, 1296, Roll(a, { 1, 1, 1, 5 }))
	w:Run(0)
	local ta, tb = Get(a, id), Get(b, id)
	assert(ta.game.chain ~= tb.game.chain, "the records split")
	eq(ta.game.current, 2); eq(tb.game.current, 1)
	-- each waits for the other; the clocks run out, the claims cross, the records are compared
	w:Run(80)
	eq(ta.game.chain, tb.game.chain)
	assert(#disputes >= 1, "the dispute recorded")
	for _, d in ipairs(disputes) do eq(d.against:lower(), a.name:lower()); eq(d.ref, "F" .. id) end
	assert(not ta.game.over)
	NoErrors(w)
end)

print("FarkleTable: stakes and settlement (the design)")

-- The money package's documented calls (the design: Standing, Debts, Stakes, Markets), faked on a
-- client: each records what it was asked in `calls`.
local function FakeMoney(c, calls, o)
	o = o or {}
	local n = c.ns
	local function Rec(name, ...) calls[#calls + 1] = { by = c.name, fn = name, args = { ... } } end
	n.Standing.Token = function() return "tok" end
	n.Standing.CheckToken = function() return true end
	n.Standing.Cap = function(kind)
		return kind == "direct" and (o.directCap or 500000) or (o.cap or 500000)
	end
	n.Debts.Iou = function() return "iou" end
	n.Debts.CheckIou = function() return true end
	n.Debts.SignResult = function() return "sig" end
	n.Debts.Disputed = function(...) Rec("Debts.Disputed", ...) end
	n.Debts.Paid = function(...) Rec("Debts.Paid", ...) end
	n.Stakes.Direct = function(...) Rec("Stakes.Direct", ...) return true end
	n.Stakes.Open = function(...) Rec("Stakes.Open", ...) return true end
	n.Stakes.Held = function(id) Rec("Stakes.Held", id) return o.held or { A = 0, B = 0 } end
	n.Stakes.Result = function(...) Rec("Stakes.Result", ...) end
	n.Stakes.Lines = function(...) Rec("Stakes.Lines", ...) return {} end
	n.Markets.Open = function(...) Rec("Markets.Open", ...) return true end
	n.Markets.Bet = function(...) Rec("Markets.Bet", ...) return { nonce = "n1" } end
	n.Markets.View = function(id) return o.view and o.view(id) or nil end
	n.Markets.Declare = function(...) Rec("Markets.Declare", ...) end
	n.Markets.Void = function(...) Rec("Markets.Void", ...) end
	n.Markets.Has = function(id) return o.has == true end
end
local function Calls(calls, fn, by)
	local out = {}
	for _, c in ipairs(calls) do if c.fn == fn and (not by or c.by:lower() == by:lower()) then out[#out + 1] = c end end
	return out
end

-- The arena live on the King's realm, the rules accepted, saved data proven kept (a logout and a
-- login), the players (and the arbiter) grouped at the Goldshire inn, the money package faked.
local function Live(o)
	o = o or {}
	local w = FW.New()
	-- (no screens in the table's tests: the board's own, tests/arena/farkle-board.lua, have them)
	local king = w:Role("king", { companion = { state = "missing" } })
	local a, b = w:Player(P1), w:Player(P2)
	local arb = o.arbiter and (o.arbiter == "king" and king or w:Player(ARB)) or nil
	if arb == king then FW.Extend(w, king) end
	local list = { a, b }
	if arb and arb ~= king then list[#list + 1] = arb end
	for _, c in ipairs(list) do w:Logout(c); w:Login(c) end
	assert(king.Roles.SetSettings({ live = 1 }))
	w:Run(0)
	local calls = {}
	for _, c in ipairs({ a, b, arb }) do
		c.Arena.SetRules(true)
		FakeMoney(c, calls, o.money)
	end
	w:Group({ a, b, arb })
	w:AtInn(a.name, b.name, arb and arb.name or nil)
	return w, a, b, arb, king, calls
end

test("1.2 the Bone Throw tables: the stake sources: direct o/o, an arbiter's t/t or w/w, the King w/w; nothing mixed is offered or taken", function()
	local w, a, b, arb, king = Live({ arbiter = true })
	local S = 10000
	local function Can(o) return w:As(a, a.ns.FarkleTable.CanCreate, o) end
	eq(select(2, Can({ guest = b.name, stake = S, mode = "d", src = "t" })), "source")
	eq(select(2, Can({ guest = b.name, stake = S, mode = "d", src = "w" })), "source")
	eq(select(2, Can({ guest = b.name, stake = S, mode = "a", arbiter = arb.name, src = "o" })), "source")
	eq(select(2, Can({ guest = b.name, stake = S, mode = "a", arbiter = king.name, src = "t" })), "king")
	eq(Can({ guest = b.name, stake = S, mode = "d", src = "o", target = 5000 }), true)
	eq(Can({ guest = b.name, stake = S, mode = "a", arbiter = arb.name, src = "t", target = 5000 }), true)
	eq(Can({ guest = b.name, stake = S, mode = "a", arbiter = king.name, src = "w", target = 5000 }), true)
	-- the guest answers with the host's own source in arbiter mode, or refuses
	local id = FT(w, a).Create({ guest = b.name, stake = S, mode = "a", arbiter = arb.name, src = "w", target = 5000 })
	w:Run(0)
	eq(select(2, FT(w, b).CanAnswer(id, true, "t")), "mixed")
	eq(select(2, FT(w, b).CanAnswer(id, true, "o")), "source")
	eq(FT(w, b).CanAnswer(id, true, "w"), true)
	-- an arbiter asked with mixed sources refuses (a forged KO)
	w:As(a, function() a.ns.Arena.Send("KO", "L", ("%s~%s~%s~%s~5~tw~1o~2"):format("Kzzz1", a.name, b.name, a.ns.Arena.B36(S)), { to = arb.name }) end)
	w:Run(0)
	local kp = w:Sent({ from = arb, type = "KP" })
	eq(#kp, 2); assert(kp[1].msg:find("Kzzz1~0~s", 1, true), kp[1].msg)
	local w2, c, d = Live({ money = { directCap = S - 1 } })
	eq(select(2, w2:As(c, c.ns.FarkleTable.CanCreate, { guest = d.name, stake = S, mode = "d", src = "o", target = 5000 })), "cap")
	NoErrors(w)
	NoErrors(w2)
end)

test("1.2 the Bone Throw tables: a direct game for gold: the loser's own record makes his obligation (Stakes.Direct), the winner's fee is 6% of the money won; the creditor's KD r clears it, the debtor's KD p alone never does", function()
	local w, a, b, arb, king, calls = Live()
	local S = 12300
	local id, why = FT(w, a).Create({ guest = b.name, stake = S, mode = "d", src = "o", target = 2000 })
	assert(id, why)
	w:Run(0)
	eq(Get(b, id).mode, "L")
	assert(FT(w, b).Answer(id, true, "o"))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(0)
	eq(Get(a, id).state, "play")
	assert(FT(w, a).Concede(id))
	w:Run(0)
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.game.winner, 2); eq(tb.game.winner, 2)
	-- the loser's obligation, from his own client only
	local direct = Calls(calls, "Stakes.Direct")
	eq(#direct, 1); eq(direct[1].by:lower(), a.name:lower())
	eq(direct[1].args[1].copper, S); eq(direct[1].args[1].winner:lower(), b.name:lower()); eq(direct[1].args[1].id, "F" .. id)
	eq(ta.lines[1].kind, "pay"); eq(ta.lines[1].copper, S)
	eq(tb.lines[1].kind, "fee"); eq(tb.lines[1].copper, math.floor(S * 6 / 100))
	-- the signed result rides the KE of a staked direct game (the design)
	for _, s in ipairs(w:Sent({ type = "KE" })) do assert(s.msg:find("~sig$"), s.msg) end
	-- the debtor says he paid: nothing clears
	w:As(a, function() a.ns.FarkleTable.OnMoney({ kind = "trade", partner = b.name, gave = 5000 }) end)
	w:Run(0)
	eq(#Calls(calls, "Debts.Paid"), 0)
	eq(tb.theyPaid, 5000)
	-- the creditor's client saw the gold arrive: its receipt clears on the debtor's side
	w:As(b, function() b.ns.FarkleTable.OnMoney({ kind = "trade", partner = a.name, got = 5000 }) end)
	w:As(b, function() b.ns.FarkleTable.OnMoney({ kind = "trade", partner = a.name, got = 7300 }) end)
	w:Run(0)
	local paid = Calls(calls, "Debts.Paid")
	eq(#paid, 2); eq(paid[1].by:lower(), a.name:lower()); eq(paid[1].args[2] + paid[2].args[2], S)
	eq(tb.received, S)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a rehearsal with a stake: the same table, but no obligation, no fill line and nothing that counts", function()
	local w, a, b, arb, king, calls = Live()
	local id = FT(w, a).Create({ guest = b.name, stake = 10000, mode = "d", src = "o", target = 2000, rehearsal = true })
	w:Run(0)
	eq(Get(b, id).mode, "T")
	assert(FT(w, b).Answer(id, true, "o"))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(0)
	assert(FT(w, a).Concede(id))
	w:Run(0)
	eq(#calls, 0)
	eq(Get(a, id).lines, nil); eq(Get(b, id).lines, nil)
	eq(Get(a, id).state, "closed"); eq(Get(b, id).state, "closed")
	eq(FT(w, b).View(id).rehearsal, false, "free mode T is not the explicit simulation exemption")
	NoErrors(w)
end)

-- A staked table with an arbiter, from the invitation to play (the opening rolled).
local function Held(o)
	local S = o.stake or 10000
	local w, a, b, arb, king, calls = Live({ arbiter = o.king and "king" or true, money = o.money })
	local id, why = FT(w, a).Create({ guest = b.name, stake = S, mode = "a", arbiter = arb.name, src = o.src, target = 2000 })
	assert(id, why)
	w:Run(0)
	assert(FT(w, b).Answer(id, true, o.src))
	w:Run(0)
	assert(FT(w, arb).AnswerArbiter(id, true))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(2)
	return w, a, b, arb, id, calls, S
end

test("1.2 the Bone Throw tables: stakes held by the arbiter (t/t): play starts once his book holds both (KH); his lines settle only when his KE agrees with a player's, after the 300 s grace (the design)", function()
	local S = 10000
	local w, a, b, arb, id, calls = Held({ src = "t", stake = S, money = { held = { A = S, B = S } } })
	eq(#Calls(calls, "Stakes.Open", arb.name), 1)
	eq(Get(arb, id).state, "play"); eq(Get(a, id).state, "play"); eq(Get(b, id).state, "play")
	eq(#w:Sent({ from = arb, type = "KH" }), 2)
	assert(FT(w, a).Concede(id))
	w:Run(5)
	eq(Get(arb, id).state, "end")
	eq(#Calls(calls, "Stakes.Result"), 0, "not before the grace")
	w:Run(300)
	local r = Calls(calls, "Stakes.Result")
	eq(#r, 1); eq(r[1].by:lower(), arb.name:lower()); eq(r[1].args[2], "B")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: held stakes never settle on the arbiter's KE alone: with both players' records against his, the table holds", function()
	local S = 10000
	local w, a, b, arb, id, calls = Held({ src = "t", stake = S, money = { held = { A = S, B = S } } })
	assert(FT(w, a).Concede(id))
	w:Run(2)
	-- both players' KE turn out to differ from the arbiter's (forged here)
	for _, c in ipairs({ a, b }) do
		w:As(c, function() c.ns.Arena.Send("KE", "L", ("%s~1~0~0~3~deadbeef~0"):format(id), { to = arb.name }) end)
	end
	w:Run(400)
	eq(#Calls(calls, "Stakes.Result"), 0)
	eq(Get(arb, id).settled, nil)
	local ag = FT(w, arb).Agreement(id)
	eq(ag.agreed, nil); eq(ag.arbiter, "2")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: wallet stakes (w/w, the King as arbiter): the arbiter opens the table's FK market, each player backs his seat; the bank hears every KE and settles only on an agreeing player's", function()
	local S = 20000
	local pools = { 0, 0 }
	local bankName = N.bank
	-- (the FK sheet as Markets.View shows it: its bank, its opener (the arbiter), its parties)
	local view = function(id) return { bank = bankName, opener = N.king, parties = { P1, P2 },
		markets = { { idx = 1, outcomes = { { o = "1", pool = pools[1] }, { o = "2", pool = pools[2] } } } } } end
	local w, a, b, arb, id, calls = Held({ src = "w", stake = S, king = true, money = { view = view } })
	local open = Calls(calls, "Markets.Open", arb.name)
	eq(#open, 1); eq(open[1].args[1], id); eq(open[1].args[2].kind, "FK")
	local bets = Calls(calls, "Markets.Bet")
	eq(#bets, 2)
	for _, bet in ipairs(bets) do eq(bet.args[4], S / 100) end
	eq(Get(a, id).state, "stakes")
	pools = { S, S }
	w:Run(2)
	eq(Get(a, id).state, "play"); eq(Get(arb, id).state, "play")
	-- the bank: a client told of the market (Markets.Has), hearing the KEs
	local bank = w:Player(bankName)
	-- (A late login takes L once it has heard the live switch: the King's repeat.)
	w:As(arb, arb.ns.ArenaRoles.Repeat)
	w:Run(2)
	FakeMoney(bank, calls, { has = true, view = view })
	local agreed = {}
	bank.ns.On("FARKLE_AGREED", function(eid, res) agreed[#agreed + 1] = { id = eid, res = res } end)
	assert(FT(w, b).Concede(id))
	w:Run(2)
	eq(#w:Sent({ from = arb, type = "KE", to = bankName }), 1)
	eq(#agreed >= 1, true); eq(agreed[1].res, "1")
	w:Run(300)
	local d = Calls(calls, "Markets.Declare", arb.name)
	eq(#d, 1); eq(d[1].args[2][1], "1")
	NoErrors(w)
end)

-- A void game at a wallet table: the arbiter voided its FK market by Declare { "V" }, which
-- Markets reads as no result at all (a void needs its code), so both stakes stayed locked in the
-- bank. It voids the market now, code X (a void game), and declares nothing.
test("1.2 the Bone Throw tables: a void game at a wallet table voids its FK market (code X): both stakes come back, nothing is declared", function()
	local S = 20000
	local view = function() return { bank = N.bank, opener = N.king, parties = { P1, P2 },
		markets = { { idx = 1, outcomes = { { o = "1", pool = S }, { o = "2", pool = S } } } } } end
	local w, a, b, arb, id, calls = Held({ src = "w", stake = S, king = true, money = { view = view } })
	w:Run(2)
	eq(Get(arb, id).state, "play")
	eq(w:As(arb, function() return arb.ns.Arena.Do("farkle.void", id) end), true)
	w:Run(5)
	eq(Get(arb, id).game.reason, "void")
	w:Run(300)
	eq(#Calls(calls, "Markets.Declare", arb.name), 0, "no winner declared")
	local v = Calls(calls, "Markets.Void", arb.name)
	eq(#v, 1); eq(v[1].args[1], id); eq(v[1].args[2], "*"); eq(v[1].args[3], "X")
	NoErrors(w)
end)

print("FarkleTable: the crowd's bets at a public arbiter's table")

-- A table whose host let watchers in and the crowd bet, judged by a public arbiter (the signed
-- arbiter of the test world), from the invitation to the opening rolled.
local function Crowd(o)
	o = o or {}
	local w, a, b, arb, king, calls = Live({ arbiter = true, money = o.money })
	local crowdA = w:Player(N.bettor1)
	-- (A late login takes L once it has heard the live switch: the King's repeat.)
	w:As(king, king.ns.ArenaRoles.Repeat)
	w:Run(0)
	local id, why = FT(w, a).Create({ guest = b.name, stake = o.stake or 0, src = o.src, mode = "a", arbiter = arb.name, target = 2000,
		spectators = true, crowd = o.crowd ~= false, rehearsal = o.rehearsal })
	assert(id, why)
	w:Run(0)
	assert(FT(w, b).Answer(id, true, o.src))
	w:Run(0)
	assert(FT(w, arb).AnswerArbiter(id, true))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(2)
	return w, a, b, arb, id, calls, crowdA
end

test("1.2 the crowd's bets at a Bone Throw table: the public arbiter opens the crowd's winner market as the table opens; the first throw waits for its lock; he declares the winner after the grace", function()
	local w, a, b, arb, id, calls, crowdA = Crowd()
	local open = Calls(calls, "Markets.Open", arb.name)
	eq(#open, 1, "one market, the arbiter's")
	eq(open[1].args[1], id)
	local spec = open[1].args[2]
	eq(#spec.markets, 1); eq(spec.markets[1].type, "MW")
	eq(spec.private, nil, "the crowd's: public"); eq(spec.stake, nil, "never a stake")
	local window = w:As(arb, arb.ns.Arena.OpenMin, true)
	eq(spec.lockAt, w:As(arb, arb.ns.Arena.Now) + window - 2, "closes the window after the table opened")
	eq(#Calls(calls, "Markets.Open", a.name) + #Calls(calls, "Markets.Open", b.name), 0, "the players open nothing")
	-- The first throw waits: no KH while the crowd still bets, on any client.
	for _, c in ipairs({ a, b, arb }) do eq(Get(c, id).state, "stakes", c.short) end
	eq(#w:Sent({ from = arb, type = "KH" }), 0)
	assert(Get(a, id).stakesWait >= FT(w, a).STAKES_WAIT + window, "a player waits through the bets' window")
	w:Run(window - 10)
	eq(Get(arb, id).state, "stakes", "still betting")
	w:Run(12)
	eq(#w:Sent({ from = arb, type = "KH" }), 2, "the lock passed: KH to both players")
	for _, c in ipairs({ a, b, arb }) do eq(Get(c, id).state, "play", c.short) end
	-- The table's view says so; a member who only heard its notice knows the event, never a stake.
	local v = FT(w, arb).View(id)
	eq(v.crowd, true); eq(v.crowdOpen, true)
	local ev = w:As(crowdA, crowdA.ns.Arena.EventOf, id)
	assert(ev, "the crowd knows the table from the arbiter's notice")
	eq(ev.kind, "farkle"); eq(ev.public, true); eq(ev.opener, arb.name)
	eq(ev.fighters.A.name, a.name); eq(ev.fighters.B.name, b.name); eq(ev.stake, nil)
	-- The guest concedes: the host won. Declared only after the agreement and its grace.
	assert(FT(w, b).Concede(id))
	w:Run(5)
	eq(#Calls(calls, "Markets.Declare"), 0, "not before the grace")
	w:Run(300)
	local d = Calls(calls, "Markets.Declare", arb.name)
	eq(#d, 1); eq(d[1].args[1], id); eq(d[1].args[2][1], "1")
	eq(#Calls(calls, "Markets.Void"), 0)
	eq(#Calls(calls, "Stakes.Result"), 0, "no stakes at a table for fun")
	NoErrors(w)
end)

test("1.2 the crowd's bets at a Bone Throw table: a void game voids them (X), a table that never plays returns them (W); a table without the crowd's word opens nothing", function()
	-- A void game.
	local w, a, b, arb, id, calls = Crowd()
	w:Run(w:As(arb, arb.ns.Arena.OpenMin, true) + 2)
	eq(Get(arb, id).state, "play")
	eq(w:As(arb, function() return arb.ns.Arena.Do("farkle.void", id) end), true)
	w:Run(305)
	eq(#Calls(calls, "Markets.Declare"), 0)
	local v = Calls(calls, "Markets.Void", arb.name)
	eq(#v, 1); eq(v[1].args[1], id); eq(v[1].args[3], "X")
	NoErrors(w)
	-- Stakes held by the arbiter that never come: the table closes after the wait and the bets'
	-- window; the stakes and the crowd's bets go back.
	local S = 10000
	w, a, b, arb, id, calls = Crowd({ stake = S, src = "t", money = { held = { A = S, B = 0 } } })
	eq(Get(arb, id).state, "stakes")
	w:Run(FT(w, arb).STAKES_WAIT + w:As(arb, arb.ns.Arena.OpenMin, true) + 5)
	for _, c in ipairs({ a, b, arb }) do eq(Get(c, id).state, "aborted", c.short) end
	local r = Calls(calls, "Stakes.Result", arb.name)
	eq(#r, 1); eq(r[1].args[2], "V")
	v = Calls(calls, "Markets.Void", arb.name)
	eq(#v, 1); eq(v[1].args[1], id); eq(v[1].args[3], "W")
	NoErrors(w)
	-- The same table without the host's word for the crowd: no market, play at once.
	w, a, b, arb, id, calls = Crowd({ crowd = false })
	eq(#Calls(calls, "Markets.Open"), 0)
	eq(Get(arb, id).state, "play")
	eq(Get(arb, id).crowd, nil)
	NoErrors(w)
end)

-- A rehearsal's stake is never traded (not Real): the crowd's wait asked for both stakes in the
-- arbiter's book anyway, which stays empty with no Stakes.Open, so the table never started and
-- closed on "stakes" after the wait and the bets' window. It waits for the lock alone now, then
-- plays; the board shows the crowd's wait, not the stakes nor a Pay stake.
test("1.2 the crowd's bets at a rehearsal with a stake: the table waits for the bets' lock alone (no stake is held), then plays; no Pay stake", function()
	local S = 50000
	local w, a, b, arb, id, calls = Crowd({ stake = S, src = "t", rehearsal = true })
	eq(Get(arb, id).mode, "T")
	eq(#Calls(calls, "Stakes.Open"), 0, "a rehearsal trades nothing")
	eq(#Calls(calls, "Markets.Open", arb.name), 1, "the crowd's market")
	for _, c in ipairs({ a, b, arb }) do eq(Get(c, id).state, "stakes", c.short) end
	local v = FT(w, a).View(id)
	eq(v.crowdWait, true, "the wait is the crowd's alone")
	local window = w:As(arb, arb.ns.Arena.OpenMin, true)
	w:Run(window - 10)
	eq(Get(arb, id).state, "stakes", "still betting")
	w:Run(12)
	eq(#w:Sent({ from = arb, type = "KH" }), 2, "the lock passed: KH to both players")
	for _, c in ipairs({ a, b, arb }) do eq(Get(c, id).state, "play", c.short) end
	eq(#Calls(calls, "Stakes.Result"), 0)
	eq(#Calls(calls, "Markets.Void"), 0, "the crowd's bets stand")
	NoErrors(w)
end)

-- A client that is not at the table (the bank, a bettor) knew a Bones crowd's event only from the
-- notices in memory, which KN fills while the table is open; KN stops as the table closes, when
-- the arbiter declares. Every rev of the sheet needs the event (Markets.CheckSheet), so a bank
-- that reloaded then could never take the declared result: the market voided and the winners
-- were refunded. The event is kept now where the market involves the client (Markets.Involved),
-- across a reload, KEEP_NOTICE at most; never on a client it does not involve (the weight rule).
test("1.2 the crowd's bets at a Bone Throw table: a client the crowd's market involves keeps the table's event across a reload; one it does not keeps nothing", function()
	local w, a, b, arb, id, calls, crowdA = Crowd()
	local involved = false
	local function Fake(c)
		c.ns.Markets.Find = function(eid, mode) if involved and eid == id then return { eid = eid, mode = "L" }, "L" end return nil end
		c.ns.Markets.Involved = function(rec) return type(rec) == "table" and rec.eid == id end
	end
	local function Event() return w:As(crowdA, crowdA.ns.Arena.EventOf, id) end
	local function Relog() w:Logout(crowdA); w:Login(crowdA); Fake(crowdA) end
	Fake(crowdA)
	assert(Event(), "heard from the notice")
	-- Not involved: nothing kept; a reload forgets the table (until its next notice).
	Relog()
	eq(Event(), nil, "nothing kept for a client the market does not involve")
	local function Kept()
		local store = w:As(crowdA, crowdA.ns.Arena.Store, "L")
		for _, m in pairs(type(store) == "table" and type(store.farkle) == "table" and store.farkle or {}) do
			if type(m) == "table" and type(m.kept) == "table" and m.kept[id] then return true end
		end
		return false
	end
	eq(Kept(), false, "no saved data written")
	-- Involved (it holds the sheet as the bank, or a ticket): the next notice keeps the event.
	involved = true
	w:Run(FT(w, arb).NOTICE_EVERY + 1)
	eq(Kept(), true)
	Relog()
	local ev = Event()
	assert(ev, "the event survives the reload")
	eq(ev.kind, "farkle"); eq(ev.public, true); eq(ev.opener, arb.name); eq(ev.mode, "L")
	eq(ev.fighters.A.name, a.name); eq(ev.fighters.B.name, b.name); eq(ev.stake, nil, "never a stake")
	-- KEEP_NOTICE later it is pruned at login.
	w.clock = w.clock + FT(w, crowdA).KEEP_NOTICE + 1
	Relog()
	eq(Event(), nil, "pruned")
	NoErrors(w)
end)

test("1.2 the crowd's bets at a Bone Throw table: only with an arbiter, watchers let in and no stakes in the wallet; never from an arbiter who is not public", function()
	local w, a, b, arb, king, calls = Live({ arbiter = true })
	local function Can(o) return w:As(a, a.ns.FarkleTable.CanCreate, o) end
	local base = { guest = b.name, target = 2000, mode = "a", arbiter = arb.name, spectators = true, crowd = true }
	eq(Can(base), true)
	local function With(k, v) local o = {} for x, y in pairs(base) do o[x] = y end o[k] = v return o end
	eq(select(2, Can(With("spectators", false))), "crowd", "watchers kept out")
	eq(select(2, Can(With("mode", "d"))), "crowd", "a direct table")
	local walled = With("stake", 20000); walled.src = "w"; walled.arbiter = king.name
	eq(select(2, Can(walled)), "crowd", "beside the wallet's stakes (their FK market)")
	-- An arbiter the King lists but who is not public: the table plays, without the crowd's bets.
	local listed = w:Player(N.bettor3)
	FakeMoney(listed, calls)
	listed.Arena.SetRules(true)
	-- (he came after the King's word that the arena is live: he hears it again)
	assert(king.Roles.SetArbiters({ { name = listed.name, cap = 100 } }))
	assert(king.Roles.SetSettings({ live = 1 }))
	w:Run(0)
	w:Group({ a, b, listed })
	eq(w:As(listed, listed.ns.ArenaRoles.IsPublicArbiter, listed.name, "L"), false)
	local id = assert(FT(w, a).Create(With("arbiter", listed.name)))
	w:Run(0)
	assert(FT(w, b).Answer(id, true))
	w:Run(0)
	assert(FT(w, listed).AnswerArbiter(id, true))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(2)
	eq(#Calls(calls, "Markets.Open"), 0, "no market from him")
	eq(FT(w, listed).View(id).crowdOpen, false)
	eq(Get(listed, id).state, "play")
	NoErrors(w)
end)

print("FarkleTable: the clocks (the design)")

test("1.2 the Bone Throw tables: the turn timer: the acting player's own client stops at secs - 5, the waiting player claims at secs + 5; three timeouts in a row forfeit", function()
	local w, a, b, id = Table({ secs = 30 })
	local ta, tb = Get(a, id), Get(b, id)
	w:Run(26)
	eq(select(1, FT(w, a).ActWhy(ta)), "late")
	eq(ta.game.timeouts[1], 0)
	w:Run(10)
	eq(ta.game.timeouts[1], 1); eq(tb.game.timeouts[1], 1)
	eq(#w:Sent({ from = b, type = "KT" }), 1)
	eq(ta.game.current, 2)
	-- nobody plays: a timeout each in turn, until the first player's third
	w:Run(36 * 4)
	eq(ta.game.over, true); eq(tb.game.over, true)
	eq(ta.game.reason, "forfeit"); eq(ta.game.winner, 2); eq(tb.game.winner, 2)
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a player in combat reports it (KT p): the clock waits, 120 s a game at most, and the other board says why", function()
	local w, a, b, id = Table({ secs = 30 })
	local ta, tb = Get(a, id), Get(b, id)
	w:Run(10)
	w:Combat(a, true)
	w:Run(0)
	eq(#w:Sent({ from = a, type = "KT" }), 1)
	eq(FT(w, b).View(id).clock.paused, "combat")
	w:Run(100)
	eq(tb.game.timeouts[1], 0, "no timeout while he fights")
	w:Run(60)
	-- (past 120 s of combat the clock runs again: 20 s used before, 35 s to the claim)
	eq(tb.game.timeouts[1], 1)
	w:Combat(a, false)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a claim that comes before this client's own clock agrees waits for it", function()
	local w, a, b, id = Table({ secs = 30 })
	local ta = Get(a, id)
	w:Run(5)
	-- a timeout claimed far too early (a forged KT)
	w:As(b, function() b.ns.Arena.Send("KT", "T", ("%s~%s~t~1~%s~0"):format(id, b.ns.Arena.B36(ta.game.step), ta.game.chain), { to = a.name }) end)
	w:Run(0)
	eq(ta.game.timeouts[1], 0)
	w:Run(21)
	eq(ta.game.timeouts[1], 1)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a concession ends the game for the other player at every client; a void needs both players (or the arbiter)", function()
	local w, a, b, id = Table()
	assert(FT(w, b).Concede(id))
	w:Run(0)
	eq(Get(a, id).game.winner, 1); eq(Get(a, id).game.reason, "concede")
	local w2, c, d, id2 = Table()
	assert(FT(w2, c).Void(id2))
	w2:Run(0)
	eq(Get(d, id2).game.over, false)
	eq(Get(d, id2).otherVoid, true)
	assert(FT(w2, d).Void(id2))
	w2:Run(0)
	eq(Get(c, id2).game.reason, "void"); eq(Get(d, id2).game.reason, "void")
	NoErrors(w); NoErrors(w2)
end)

print("FarkleTable: the tavern rule (the design)")

test("1.2 the Bone Throw tables: a game for gold starts only in one party, both resting at the same inn, within about 10 yards", function()
	local w, a, b = Live()
	local function Can() return w:As(a, a.ns.FarkleTable.CanCreate, { guest = b.name, stake = 10000, mode = "d", src = "o", target = 2000 }) end
	eq(Can(), true)
	w:Stand(a.name, FW.ROAD, false)
	eq(select(2, Can()), "tavern-rest")
	w:Stand(a.name, FW.ROAD, true)
	eq(select(2, Can()), "tavern-inn")
	w:AtInn(a.name)
	w:Stand(b.name, { cont = 0, wx = FW.INN.wx + 20, wy = FW.INN.wy }, true)
	eq(select(2, Can()), "tavern-far")
	w:Stand(b.name, { cont = 0, wx = -10645.9, wy = 1179.1 }, true) -- (Sentinel Hill's inn)
	eq(select(2, Can()), "tavern-inn")
	w:AtInn(a.name, b.name)
	w:Group({ a })
	w:Group({ b })
	eq(select(2, Can()), "tavern-group")
	w:Group({ a, b })
	eq(Can(), true)
	-- Ordinary and rehearsal games both require a tavern/camp; innkeeper practice stays at an inn.
	w:Stand(a.name, FW.ROAD, false)
	eq(select(2, w:As(a, a.ns.FarkleTable.CanCreate, { guest = b.name, target = 2000 })), "tavern-rest")
	eq(select(2, w:As(a, a.ns.FarkleTable.CanCreate, { guest = b.name, target = 2000, rehearsal = true })), "tavern-rest")
	eq(select(2, w:As(a, a.ns.FarkleTable.CanCreate, { guest = b.name, stake = 10000, mode = "d", src = "o", target = 2000, rehearsal = true })), "tavern-rest")
	local practice, why = FT(w, a).Practice({ target = 2000 })
	eq(practice, nil); eq(why, "training_inn", "the innkeeper's training stays at a tavern")
	NoErrors(w)
end)

-- 1.1.6: Bones at a tavern or at a camp. A camp is the Board's (dropped where the player stood, its
-- zone and nothing finer): one of the two players' camp, in the zone they are in, both in one party
-- within about 10 yards. Out in the world, no inn needed. The arena's test world loads no Board, so
-- each client gets its seam, Board.CampOf (tested with the Board itself in tests/run.lua's camps):
-- the camps up now, by name, as every Board heard them.
local function Camps(w, ...)
	local up = {}
	for _, c in ipairs({ ... }) do
		rawset(c.ns, "Board", { CampOf = function(name)
			for who, camp in pairs(up) do if FT(w, c).Same(who, name) then return camp end end
			return nil
		end })
	end
	return up
end

test("1.1.6 Bones at a camp: a game between players starts by a camp either of them dropped in their zone, out on the road; none, or another zone's, is no place", function()
	local w, a, b = Live()
	w:Stand(a.name, FW.ROAD, false)
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
	local function Can(c, other) return w:As(c, c.ns.FarkleTable.CanCreate, { guest = other.name, target = 2000 }) end
	local up = Camps(w, a, b)
	eq(select(2, Can(a, b)), "tavern-rest", "no inn, no camp")
	-- b drops a camp in Elwynn Forest (the test world's zone): both clients see it
	up[b.name] = { zone = 1429, raisedAt = w.clock }
	eq(Can(a, b), true); eq(Can(b, a), true)
	-- apart, or another zone's camp: no
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 20, wy = FW.ROAD.wy }, false)
	eq(select(2, Can(a, b)), "tavern-far")
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
	a.globals.C_Map = { GetBestMapForUnit = function() return 1433 end }
	eq(select(2, Can(a, b)), "tavern-rest", "the camp is in another zone than a's")
	a.globals.C_Map = { GetBestMapForUnit = function() return 1429 end }
	eq(Can(a, b), true)
	-- not in one party: no
	w:Group({ a }); w:Group({ b })
	eq(select(2, Can(a, b)), "tavern-group")
	w:Group({ a, b })
	-- a camp somebody else dropped is not theirs; theirs ended: no place any more
	up[b.name] = nil
	up[N.arbiter] = { zone = 1429, raisedAt = w.clock }
	eq(select(2, Can(a, b)), "tavern-rest")
	-- in a dungeon, no camp
	up[a.name] = { zone = 1429, raisedAt = w.clock }
	eq(Can(a, b), true)
	a.globals.IsInInstance = function() return true, "party" end
	eq(select(2, w:As(a, a.ns.FarkleTable.TavernStart, b.name)), "rest", "(the table itself refuses an instance first)")
	NoErrors(w)
end)

test("1.1.6 Bones at a camp: the table is the camp's; a player who walks off pauses the game, gone past the grace he forfeits", function()
	local w, a, b = Live()
	w:Stand(a.name, FW.ROAD, false)
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
	local up = Camps(w, a, b)
	up[a.name] = { zone = 1429, raisedAt = w.clock }
	local id = assert(FT(w, a).Create({ guest = b.name, target = 2000, secs = 30 }))
	w:Run(0)
	assert(FT(w, b).Answer(id, true))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(0)
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.state, "play"); eq(ta.mode, "L")
	eq(ta.camp, true); eq(tb.camp, true); eq(ta.inn, nil)
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 60, wy = FW.ROAD.wy }, false)
	w:Run(2)
	eq(FT(w, a).View(id).clock.paused, "tavern")
	local left = FT(w, b).View(id).awayLeft
	assert(type(left) == "number" and left > 0 and left <= 60, "the departed camp player's remaining grace")
	eq(FT(w, a).View(id).awayLeft, nil, "the player still at the camp has no departure countdown")
	w:Run(3)
	eq(FT(w, b).View(id).awayLeft, left - 3)
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
	w:Run(2)
	eq(FT(w, a).View(id).clock.paused, nil)
	eq(FT(w, b).View(id).awayLeft, nil, "return clears the countdown")
	w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 60, wy = FW.ROAD.wy }, false)
	w:Run(62)
	eq(ta.game.over, true); eq(ta.game.winner, 1); eq(tb.game.winner, 1)
	eq(FT(w, b).View(id).awayLeft, nil, "a finished game has no departure countdown")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: at a gold table a player who walks off pauses the game; back in time it goes on, gone past the grace he forfeits", function()
	local w, a, b, arb, king = Live()
	local id = FT(w, a).Create({ guest = b.name, stake = 10000, mode = "d", src = "o", target = 2000, secs = 30 })
	w:Run(0)
	assert(FT(w, b).Answer(id, true, "o"))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id); FT(w, b).Roll(id)
	w:Run(0)
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.state, "play"); assert(ta.inn and tb.inn, "the inn is the table's")
	w:Stand(a.name, FW.ROAD, false)
	w:Run(2)
	eq(FT(w, b).View(id).clock.paused, "tavern")
	eq(select(1, FT(w, a).ActWhy(ta)), "tavern")
	local left = FT(w, a).View(id).awayLeft
	assert(type(left) == "number" and left > 0 and left <= 60, "the departed inn player's remaining grace")
	eq(FT(w, b).View(id).awayLeft, nil)
	w:Run(40)
	eq(FT(w, a).View(id).awayLeft, left - 40)
	eq(tb.game.timeouts[1], 0)
	w:AtInn(a.name, b.name)
	w:Run(2)
	eq(FT(w, b).View(id).clock.paused, nil)
	eq(FT(w, a).View(id).awayLeft, nil)
	w:Stand(a.name, FW.ROAD, false)
	w:Run(62)
	eq(tb.game.over, true); eq(tb.game.winner, 2); eq(ta.game.winner, 2)
	eq(FT(w, a).View(id).awayLeft, nil)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: 'Sit down' is the game's /sit emote, the player's own click, never required", function()
	local w = FW.New()
	local a = w:Player(P1)
	FT(w, a).Sit()
	eq(a.emotes[1], "SIT")
end)

print("FarkleTable: the hiccup (the design)")

test("1.2 the Bone Throw tables: the drunk-line reader: every DRUNK_MESSAGE line of the eight languages, plain and item forms, grammar tokens resolved or raw, read right; a tie or an emote is never read", function()
	local w = FW.New()
	local a = w:Player(P1)
	local KEYS = {}
	for _, who in ipairs({ "SELF", "OTHER" }) do
		for n = 1, 4 do
			KEYS[#KEYS + 1] = { key = "DRUNK_MESSAGE_" .. who .. n, self = who == "SELF", level = n - 1 }
			KEYS[#KEYS + 1] = { key = "DRUNK_MESSAGE_ITEM_" .. who .. n, self = who == "SELF", level = n - 1, item = true }
		end
	end
	local function Ko(s, pick) return (s:gsub("|1([^;]*);([^;]*);", function(x, y) return pick == 1 and x or y end)) end
	local MODES = { function(s) return s end, function(s) return (Ko(s, 1):gsub("|2 ", "de ")) end, function(s) return (Ko(s, 2):gsub("|2 ", "d'")) end }
	local total = 0
	for _, loc in ipairs({ "enUS", "deDE", "frFR", "esES", "ptBR", "ruRU", "koKR", "zhCN" }) do
		local S = FW.DRUNK[loc]
		for k, v in pairs(S) do a.globals[k] = v end
		for _, mode in ipairs(MODES) do
			for _, k in ipairs(KEYS) do
				for _, name in ipairs({ "Brannoc", "Aldric Stonebrew", "Ysolde Ashvale" }) do
					for _, item in ipairs({ "Rhapsody Malt", "Jug of Badlands Bourbon", "Ale" }) do
						local fmt = S[k.key]
						local text = mode(k.self and (k.item and fmt:format(item) or fmt) or (k.item and fmt:format(name, item) or fmt:format(name)))
						local who, level = w:As(a, a.ns.FarkleTable.ReadDrunk, text)
						total = total + 1
						eq(level, k.level, loc .. " " .. k.key .. ": " .. text)
						eq(who, k.self and "self" or name, loc .. " " .. k.key .. ": " .. text)
					end
				end
			end
		end
	end
	eq(total, 3456)
	for k, v in pairs(FW.DRUNK.enUS) do a.globals[k] = v end
	eq(w:As(a, a.ns.FarkleTable.ReadDrunk, "Brannoc rolls 4 (1-6)"), nil)
	-- an emote never reaches the reader: the table reads CHAT_MSG_SYSTEM alone
	local events = w:Events(a, true)
	eq(events.CHAT_MSG_EMOTE, nil)
end)

test("1.2 the Bone Throw tables: sober tables: either player may ask (KI, KA hic 0), a client whose drunk lines are blanked asks by itself; the agreed value is in KG and its digest", function()
	-- both yes
	local w, a, b, id = Table({ noOpening = true })
	eq(Get(a, id).hic, true); eq(Get(b, id).hic, true)
	assert(w:Sent({ from = a, type = "KI" })[1].msg:find("~2~%w%w%w%w$"), "KI explicitly negotiates reuse rule 2")
	-- the host asks for a sober table
	local w2, c, d, id2 = Table({ noOpening = true, hic = false })
	eq(Get(c, id2).hic, false); eq(Get(d, id2).hic, false)
	-- the guest asks
	local w3, e, f, id3 = Table({ noOpening = true, guestHic = false })
	eq(Get(e, id3).hic, false); eq(Get(f, id3).hic, false)
	assert(w3:Sent({ from = f, type = "KA" })[1].msg:find("~0$"), "KA hic 0")
	assert(w3:Sent({ from = e, type = "KG" })[1].msg:find("~0$"), "KG hic 0")
	-- another addon blanked a line: that client can't read levels, so it asks for a sober table
	local w4 = FW.New()
	local g, h = w4:Player(P1), w4:Player(P2)
	w4:Group({ g, h })
	h.globals.DRUNK_MESSAGE_OTHER4 = ""
	local id4 = FT(w4, g).Create({ guest = h.name, target = 2000, rehearsal = true })
	w4:Run(0)
	assert(FT(w4, h).Answer(id4, true))
	w4:Run(0)
	eq(Get(g, id4).hic, false); eq(Get(h, id4).hic, false)
	for _, x in ipairs({ w, w2, w3, w4 }) do NoErrors(x) end
end)

-- A hiccup table where the second player got completely smashed at the table and the first one's
-- decision wrote it (his turn after is smashed).
local function Smashed(o)
	o = o or {}
	local w, a, b, id, arb = Table(o)
	w:Drink(b.name, 3, o.seenBy and o.seenBy(a, b, arb) or nil)
	w:Run(o.after or 1)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	return w, a, b, id, arb
end

test("1.2 the Bone Throw tables: a level is what the opponent's client saw: his next decision (KK) carries it, only when it changes the recorded one", function()
	local w, a, b, id = Smashed()
	local kk = w:Sent({ from = a, type = "KK" })
	assert(kk[1].msg:find("~3$"), kk[1].msg)
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.game.level[2], 3); eq(tb.game.level[2], 3)
	eq(select(2, w:As(b, b.ns.FarkleRules.Level, tb.game, 2)), 33)
	eq(FT(w, b).View(id).feel, 3)
	-- nothing new seen: the next decision carries no level
	w:QueueRoll(b.name, Roll(b, ONE_FIVE))
	FT(w, b).Roll(id)
	w:Run(0)
	assert(FT(w, b).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1 }, "b", id))
	w:Run(0)
	kk = w:Sent({ from = a, type = "KK" })
	assert(not kk[2].msg:find("~%d$"), kk[2].msg)
	eq(tb.game.level[2], 3)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: HIC!: the original eligible throw saves or loses the turn without another server roll", function()
	local w, a, b, id = Smashed()
	local ta, tb = Get(a, id), Get(b, id)
	local asked = #b.asked
	w:QueueRoll(b.name, Roll(b, { 2, 2, 3, 3, 4, 4 }))
	FT(w, b).Roll(id)
	w:Run(0)
	eq(select(2, FT(w, b).ActWhy(tb)), "roll")
	eq(#b.asked, asked + 1); eq(b.asked[#b.asked].hi, b.ns.FarkleRules.RANGES[6])
	eq(FT(w, b).Hiccup(id), false, "no standalone HIC action")
	eq(ta.game.turn.phase, "roll"); eq(ta.game.turn.left, 6); eq(ta.game.shakes[2], 1)
	eq(ta.game.chain, tb.game.chain)
	for _, code in ipairs(ta.game.events) do assert(not code:find("^H")) end
	-- A different eligible ordered throw fails without consuming another shake-off.
	w:QueueRoll(b.name, Roll(b, { 6, 6, 4, 4, 3, 3 }))
	FT(w, b).Roll(id)
	w:Run(0)
	eq(ta.game.current, 1); eq(ta.game.last.how, "farkle")
	eq(ta.game.shakes[2], 1); eq(ta.game.timeouts[2], 0)
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: HIC! reuse has no separate clock; a saved throw stays on the ordinary turn timer", function()
	local w, a, b, id = Smashed()
	local ta, tb = Get(a, id), Get(b, id)
	w:QueueRoll(b.name, Roll(b, { 2, 2, 3, 3, 4, 4 }))
	FT(w, b).Roll(id)
	w:Run(11)
	eq(select(1, FT(w, b).ActWhy(tb)), nil)
	eq(ta.game.turn.phase, "roll"); eq(tb.game.turn.phase, "roll")
	w:Run(10)
	eq(ta.game.current, 2); eq(tb.game.current, 2)
	eq(ta.clock.phase, "roll"); eq(tb.clock.phase, "roll")
	eq(ta.game.timeouts[2], 0)
	eq(ta.game.chain, tb.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the gap rule: a player the other client can't see (UnitIsVisible false) is sober in its news until his next line", function()
	local w, a, b, id = Smashed()
	local tb = Get(b, id)
	w:QueueRoll(b.name, Roll(b, ONE_FIVE))
	FT(w, b).Roll(id)
	w:Run(0)
	assert(FT(w, b).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	b.unseen = true
	w:Run(2)
	b.unseen = nil
	w:Run(1)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1 }, "b", id))
	w:Run(0)
	local kk = w:Sent({ from = a, type = "KK" })
	assert(kk[#kk].msg:find("~0$"), kk[#kk].msg)
	eq(tb.game.level[2], 0)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: an observer's /reload changes nothing: the recorded level stands, its next decision carries none", function()
	local w, a, b, id = Smashed()
	w:QueueRoll(b.name, Roll(b, ONE_FIVE))
	FT(w, b).Roll(id)
	w:Run(0)
	assert(FT(w, b).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	w:Logout(a)
	w:Login(a)
	w:Group({ a, b })
	w:Run(12)
	local ta = Get(a, id)
	eq(ta.game.level[2], 3)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1 }, "b", id))
	w:Run(0)
	local kk = w:Sent({ from = a, type = "KK" })
	assert(not kk[#kk].msg:find("~%d$"), kk[#kk].msg)
	eq(Get(b, id).game.level[2], 3)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the arbiter's floor: a level he saw at least 8 s before a decision that left it out goes out as KL for that seat's turn after next, at every client alike", function()
	-- the first player never sees the drink; the arbiter does, 10 s before the decision
	local w, a, b, id, arb = Smashed({ arbiter = true, after = 10, seenBy = function(a, b, arb) return { b, arb } end })
	local kl = w:Sent({ from = arb, type = "KL" })
	eq(#kl, 2)
	w:Run(0)
	-- the floor lands where the second player's turn after next is handed over
	local tb, ta = Get(b, id), Get(a, id)
	eq(tb.game.level[2], 0)
	eq(#tb.game.pending >= 0, true)
	-- play on: his turn (sober), the first player's, then his next: smashed by the floor
	for _ = 1, 2 do
		local c = ta.game.current == 1 and a or b
		w:QueueRoll(c.name, Roll(c, ONE_FIVE))
		FT(w, c).Roll(id)
		w:Run(0)
		assert(FT(w, c).Keep({ 1 }, "b", id))
		w:Run(0)
	end
	eq(ta.game.current, 2)
	eq((w:As(a, a.ns.FarkleRules.Level, ta.game, 2)), 3)
	eq(ta.game.chain, tb.game.chain); eq(Get(arb, id).game.chain, ta.game.chain)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: no floor for a line the arbiter saw less than 8 s before the decision", function()
	local w, a, b, id, arb = Smashed({ arbiter = true, after = 3, seenBy = function(a, b, arb) return { b, arb } end })
	eq(#w:Sent({ from = arb, type = "KL" }), 0)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: direct mode's dispute flag: turns the drinker began below his own 'You feel' level count, and his KE carries the count", function()
	local w, a, b, id = Table()
	-- only he sees his line; the other player's decision can't record it
	w:Drink(b.name, 3, { b })
	w:Run(10)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1, 2 }, "b", id))
	w:Run(0)
	local tb = Get(b, id)
	eq(tb.ld, 1); eq(FT(w, b).View(id).lower, true)
	assert(FT(w, b).Concede(id))
	w:Run(0)
	local ke = w:Sent({ from = b, type = "KE" })
	assert(ke[1].msg:find("~1$"), ke[1].msg)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a legacy HIC relay is rejected as a whole before a prefix, dispute or resync acknowledgement", function()
	local w, a, b, id = Smashed()
	local ta = Get(a, id)
	local disputes = {}
	a.ns.Debts.Disputed = function(ref, e) disputes[#disputes + 1] = e end
	w:QueueRoll(b.name, Roll(b, { 6, 6, 4, 4, 3, 3 }))
	FT(w, b).Roll(id)
	w:Run(0)
	eq(ta.game.current, 1, "the Farkle stood at the first player's client")
	local step = ta.game.step
	-- A pending ahead-of-history decision asks for resync, then a batch carries an old H.
	local B36 = a.ns.Arena.B36
	local fake = ta.game.chains[step - 1]
	w:As(b, function() b.ns.Arena.Send("KK", "T", ("%s~%s~12~b~%s"):format(id, B36(step + 2), fake), { to = a.name }) end)
	w:Run(5)
	-- (it asks him: his own client's honest answer changes nothing, and the decision still waits)
	assert(#w:Sent({ from = a, type = "KQ", to = b.name }) >= 1)
	local own = ta.game.events[step]
	assert(own:find("^R2:"), own)
	local transcript = a.ns.FarkleRules.Transcript(ta.game)
	local ack = ta.resync.at
	w:As(b, function() b.ns.Arena.Send("KR", "T", ("%s~%s~%s,H2:10*"):format(id, B36(step - 1), own), { to = a.name }) end)
	w:Run(0)
	eq(ta.game.events[step], own, "what it saw stands")
	eq(a.ns.FarkleRules.Transcript(ta.game), transcript); eq(ta.resync.at, ack)
	eq(#disputes, 0, "reject obsolete rules before any divergent-record side effect")
	NoErrors(w)
end)

print("FarkleTable: spectators and public tables (the design)")

test("1.2 the Bone Throw tables: a player who allows spectators announces the table (KN, no stake) and relays its state (KS) to each watcher; a watcher's view never settles anything", function()
	local w, a, b, id = Table({ spectators = true, others = { "Wenna Crale" } })
	local c = w:Find("Wenna Crale")
	local kn = w:Sent({ from = a, type = "KN" })
	eq(#kn, 1); eq(kn[1].dist, "CHANNEL")
	assert(not kn[1].msg:find("10000", 1, true))
	local live = FT(w, c).LiveTables()
	eq(#live, 1); eq(live[1].id, id)
	assert(FT(w, c).Watch(id))
	w:Run(0)
	local tc = Get(c, id)
	eq(tc.role, "watch")
	assert(tc.snap, "the state relayed")
	eq(tc.snap.cur, 1); eq(tc.snap.phase, "roll")
	-- a throw and a keep: the watcher's view follows
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	eq(table.concat(tc.snap.dice, ""), "152346")
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	w:Run(0)
	eq(tc.snap.turnPts, 150)
	local ks = w:Sent({ from = a, type = "KS" })
	for _, s in ipairs(ks) do eq(s.dist, "WHISPER"); eq(s.target:lower(), c.name:lower()) end
	-- both levels and both shake-offs left ride the state (the design)
	assert(ks[#ks].msg:find("~00~22$"), ks[#ks].msg)
	eq(tc.game, nil)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: Watchable(name): the live table a player sits at, for the right-click's Watch (his table allows watchers); nobody's else", function()
	local w, a, b, id = Table({ spectators = true, others = { "Wenna Crale" } })
	local c = w:Find("Wenna Crale")
	eq(FT(w, c).Watchable(a.name), id); eq(FT(w, c).Watchable(b.short), id, "either player, by his short name too")
	eq(FT(w, c).Watchable(c.name), nil); eq(FT(w, c).Watchable(nil), nil)
	-- a table that allows no watchers is announced nowhere: nothing to watch
	local w2, a2 = Table({ others = { "Wenna Crale" } })
	eq(FT(w2, w2:Find("Wenna Crale")).Watchable(a2.name), nil)
	-- and Stop watching (the board's button) forgets the table
	assert(FT(w, c).Watch(id))
	w:Run(0)
	eq(w:As(c, function() return c.ns.Arena.Do("farkle.stopwatching", id) end), true)
	eq(Get(c, id), nil)
	NoErrors(w)
end)

-- Spectators are let in by default (the owner's call, 2026-10-04): a table made with nothing said
-- is announced by both players. The host's no closes it to watchers for everyone at it: KG says
-- so, and neither his guest (who said yes) nor a public arbiter announces or relays it.
test("1.2 the Bone Throw tables: watchers are let in by default; the host's no closes the table for his guest and its public arbiter too", function()
	local w = FW.New()
	local a, b, c = w:Player(P1), w:Player(P2), w:Player("Wenna Crale")
	w:Group({ a, b })
	local function Open(host, guest, opts, answer)
		opts.guest, opts.target, opts.rehearsal = guest.name, 2000, true
		local id = assert(FT(w, host).Create(opts))
		w:Run(0)
		assert(FT(w, guest).Answer(id, true, nil, answer))
		w:Run(0)
		return id
	end
	-- Nothing said: both announce it; the member sees it live and may watch.
	local id = Open(a, b, {}, {})
	eq(Get(a, id).spec[1], true); eq(Get(b, id).spec[2], true)
	eq(#w:Sent({ from = a, type = "KN" }), 1); eq(#w:Sent({ from = b, type = "KN" }), 1)
	eq(FT(w, c).Watchable(a.name), id)
	assert(not w:Sent({ from = a, type = "KG" })[1].msg:find("~0$"), "no closing word")
	assert(FT(w, a).Concede(id))
	w:Run(0)
	-- The host says no, the guest yes: closed for both; KG carries it.
	w.sent = {}
	local id2 = Open(b, a, { spectators = false }, { spectators = true })
	local kg = w:Sent({ from = b, type = "KG" })
	eq(#kg, 1); assert(kg[1].msg:find("~0~0$"), kg[1].msg)
	eq(#w:Sent({ type = "KN" }), 0, "nobody announces it")
	eq(Get(a, id2).noWatch, true); eq(FT(w, a).View(id2).noWatch, true)
	for _, n in ipairs(FT(w, c).LiveTables()) do assert(n.id ~= id2, "not live for the member") end
	assert(FT(w, b).Concede(id2))
	w:Run(0)
	-- The same no at a public arbiter's table: he keeps quiet too.
	local arb = w:Player(ARB)
	w:Group({ a, b, arb })
	w:Run(31) -- (a guest takes one invitation per sender every 30 s)
	w.sent = {}
	local id3 = assert(FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true, mode = "a", arbiter = arb.name, spectators = false }))
	w:Run(0)
	assert(FT(w, b).Answer(id3, true))
	w:Run(0)
	assert(FT(w, arb).AnswerArbiter(id3, true))
	w:Run(0)
	eq(Get(arb, id3).noWatch, true)
	eq(#w:Sent({ type = "KN" }), 0, "not even the public arbiter")
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FT(w, a).Roll(id3); FT(w, b).Roll(id3)
	w:Run(0)
	eq(#w:Sent({ type = "KS", dist = "CHANNEL" }), 0, "no state on the channel")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: a notice or a state from anyone but the table's players or a public arbiter is ignored", function()
	local w = FW.New()
	local a, c = w:Player(P1), w:Player("Wenna Crale")
	-- a member announces a table of two others: not his
	w:As(a, function() a.ns.Arena.Send("KN", "T", ("Kabc1~%s~%s~-~2~-~o~-"):format(P2, "Lida Fenn-Emberfall"), {}) end)
	w:Run(0)
	eq(#FT(w, c).LiveTables(), 0)
	-- a listed arbiter who isn't a public one: not official either
	w:As(a, function() a.ns.Arena.Send("KN", "T", ("Kabc2~%s~%s~%s~2~-~o~-"):format(P2, "Lida Fenn-Emberfall", a.name), {}) end)
	w:Run(0)
	eq(#FT(w, c).LiveTables(), 0)
	-- a public arbiter's own table: official, and FARKLE_PUBLIC fires once
	local arb = w:Player(ARB)
	local fired = 0
	c.ns.On("FARKLE_PUBLIC", function() fired = fired + 1 end)
	for _ = 1, 2 do
		w:As(arb, function() arb.ns.Arena.Send("KN", "T", ("Kabc3~%s~%s~%s~2~-~o~-"):format(P2, "Lida Fenn-Emberfall", arb.name), {}) end)
		w:Run(0)
	end
	eq(#FT(w, c).LiveTables(), 1); eq(FT(w, c).LiveTables()[1].official, true); eq(fired, 1)
	NoErrors(w)
end)

print("FarkleTable: practice, self-test, tester log, storage")

test("Bones first lesson opening: a reset learner starts before the House despite stored alternation", function()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(P1, { bonesTrained = false })
	w:Stand(a.name, FW.INN, true)
	FT(w, a).Opts().practiceFirst = 1
	FT(w, a).Opts().innkeeperLearned = nil
	local id = assert(FT(w, a).Practice({ target = 5000 }))
	local t = Get(a, id)
	eq(t.first, 1, "first lesson starts with the learner after reset")
	eq(t.target, 2000)
	eq(t.game.scores[1], 0); eq(t.game.scores[2], 0)
	eq(t.game.over, false)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: practice own drunk readability: missing other formats still observes real self drink lines, missing self levels disables safely", function()
	local w = FW.New()
	local a = w:Player(P1)
	w:Stand(a.name, FW.INN, true)
	a.globals.DRUNK_MESSAGE_OTHER4 = nil
	eq(FT(w, a).DrunkReadable(), false, "multiplayer still requires every format")
	local id = assert(FT(w, a).Practice({ target = 2000, first = 1 }))
	local text = FW.DRUNK.enUS.DRUNK_MESSAGE_ITEM_SELF3:format("Rhapsody Malt")
	w:Fire(a, "CHAT_MSG_SYSTEM", text)
	eq(FT(w, a).View(id).feel, 2, "practice observes the player's own server line")
	eq(Get(a, id).news.level, 2, "the observed level reaches the practice decision")
	eq(#w.sent, 0, "practice sends no messages")
	assert(FT(w, a).Close(id))
	for n = 1, 4 do
		a.globals["DRUNK_MESSAGE_SELF" .. n] = nil
		a.globals["DRUNK_MESSAGE_ITEM_SELF" .. n] = nil
	end
	local sober = assert(FT(w, a).Practice({ target = 2000, first = 1 }))
	eq(Get(a, sober).hic, false)
	w:Fire(a, "CHAT_MSG_SYSTEM", text)
	eq(FT(w, a).View(sober).feel, nil)
	eq(Get(a, sober).news, nil)
	eq(#w.sent, 0)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: practice against the House: the player's dice from his own /roll lines (the real parser), the House's local dice; a seeded game plays to its end and nothing is sent", function()
	local w = FW.New({ seed = 7 })
	local a = w:Player(P1)
	w:Stand(a.name, FW.INN, true)
	math.randomseed(3)
	local id = FT(w, a).Practice({ target = 2000, first = 1 })
	assert(id)
	local t = Get(a, id)
	eq(t.role, "practice")
	local R = a.ns.FarkleRules
	for _ = 1, 400 do
		if t.game.over then break end
		local who, phase = w:As(a, R.Expect, t.game)
		if who == 1 then
			if phase == "keep" then
				local pos, act = w:As(a, R.HouseMove, t.game)
				assert(FT(w, a).Keep(pos, act, id))
			else
				assert(FT(w, a).Roll(id))
			end
		end
		w:Run(1)
	end
	eq(t.game.over, true)
	eq(t.closed, true)
	eq(#w.sent, 0)
	assert(#a.asked > 0)
	for _, r in ipairs(a.asked) do assert(R.RangeK(r.lo, r.hi) or r.hi == 100) end
	-- the House's own dice never come from /roll lines: a line naming the House counts nothing
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: practice, drunk: the player's own 'You feel' line counts, written by the House's next decision; his own decisions write no level, the House never drinks", function()
	local w = FW.New({ seed = 7 })
	local a = w:Player(P1)
	w:Stand(a.name, FW.INN, true)
	local id = FT(w, a).Practice({ target = 5000, first = 1 })
	local t = Get(a, id)
	eq(t.hic, true)
	w:Drink(a.name, 3)
	w:Run(3)
	eq(t.news and t.news.level, 3, "his own line is the news, and a second passes: no gap rule against the House")
	-- his decision: no level written, the news kept
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
	assert(FT(w, a).Roll(id))
	w:Run(0)
	assert(FT(w, a).Keep({ 1 }, "b", id))
	eq(t.game.events[#t.game.events], "K1:1:b"); eq(t.game.level[2], 0, "the House never drinks")
	eq(t.news and t.news.level, 3)
	-- the House's first decision writes it: his next turn plays smashed (its throw: three 1s,
	-- which it keeps and banks)
	local R = a.ns.FarkleRules
	local real, forced = math.random, R.Encode({ 1, 1, 1, 2, 3, 4 })
	math.random = function(lo, hi)
		if lo == 1 and hi == 46656 and forced then local v = forced; forced = nil; return v end
		if lo == nil then return real() end
		if hi == nil then return real(lo) end
		return real(lo, hi)
	end
	local ok, err = pcall(function()
		for _ = 1, 60 do
			if t.game.current == 1 or t.game.over then break end
			w:Run(1)
		end
	end)
	math.random = real
	if not ok then error(err, 0) end
	local found
	for _, code in ipairs(t.game.events) do if code:find("^K2:.*:3$") then found = code end end
	assert(found, table.concat(t.game.events, " "))
	eq((w:As(a, R.Level, t.game, 1)), 3)
	eq(t.news, nil, "written: the news spent")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: /oly farkle test rolls 46656 and reads the line back (name, range, value, dice, the match) into a copy pop-up, /oly status and /oly bug", function()
	local w = FW.New()
	local a = w:Player(P1)
	local copies = {}
	a.ns.UI = { ShowCopy = function(title, text) copies[#copies + 1] = text end }
	w:QueueRoll(a.name, 31337)
	w:As(a, function() a.ns.Arena.RunSlash("farkle test") end)
	w:Run(0)
	local last = FT(w, a).LastSelfTest()
	eq(last.value, 31337); eq(last.match, true); eq(table.concat(last.dice, " "), "5 3 1 2 1 5")
	eq(#copies, 1); assert(copies[1]:find("31337", 1, true), copies[1])
	local lines = {}
	for _, fn in ipairs(a.ns.statusLines) do w:As(a, fn, lines) end
	local text = table.concat(lines, "\n")
	assert(text:find("31337", 1, true), text)
	-- no line: said after 20 s
	a.dropRolls = true
	w:As(a, function() a.ns.Arena.RunSlash("farkle test") end)
	w:Run(21)
	eq(FT(w, a).LastSelfTest().none, true)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the tester log: every roll line read, with its time since the decision before it, and every resync; 200 lines at most", function()
	local w, a, b, id = Table()
	w:As(b, function() b.ns.Arena.RunSlash("farkle log on") end)
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FT(w, a).Roll(id)
	w:Run(0)
	assert(FT(w, a).Keep({ 1, 2 }, "r", id))
	w:Run(3)
	FT(w, a).Roll(id)
	w:Run(0)
	local log = b.db.farkleLog.lines
	eq(#log, 2)
	assert(log[2]:find("3.0s after the last decision", 1, true), log[2])
	for i = 1, 250 do w:As(b, b.ns.FarkleTable.Note, "line %d", i) end
	eq(#b.db.farkleLog.lines, 200)
	w:As(b, function() b.ns.Arena.RunSlash("farkle log off") end)
	eq(b.db.farkleLog.on, false)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: chatrolls off hides only this table's players' Bone Throw lines from the chat frames, never the addon's reading of them", function()
	local w, a, b, id = Table({ noOpening = true })
	local filter
	b.globals.ChatFrame_AddMessageEventFilter = function(event, fn) if event == "CHAT_MSG_SYSTEM" then filter = fn end end
	w:As(b, function() b.ns.Arena.RunSlash("farkle chatrolls off") end)
	assert(filter, "a filter")
	local function Hidden(text) return w:As(b, filter, nil, "CHAT_MSG_SYSTEM", text) end
	eq(Hidden(a.short .. " rolls 55 (1-100)"), true)
	eq(Hidden(a.short .. " rolls 3 (1-6)"), true)
	eq(Hidden("Wenna Crale rolls 55 (1-100)"), false)
	eq(Hidden(a.short .. " rolls 55 (1-1000)"), false)
	w:As(b, function() b.ns.Arena.RunSlash("farkle chatrolls on") end)
	eq(Hidden(a.short .. " rolls 55 (1-100)"), false)
	-- read all the same
	w:TypedRoll(a.name, 1, 100, 70); w:TypedRoll(b.name, 1, 100, 20)
	w:Run(0)
	eq(Get(b, id).state, "play")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the history (100 games) and the transcripts (10, 7 days) live in the companion's saved data; a client that never played keeps nothing and runs nothing", function()
	local w = FW.New()
	local a = w:Player(P1)
	-- idle: no event, timer or frame of the table's
	local weight = w:ArenaWeight(a)
	for _, e in ipairs(weight.events) do assert(e ~= "CHAT_MSG_SYSTEM", "no roll reader while idle") end
	eq(a.rdb.arenaTest, nil)
	w:As(a, function() a.ns.Arena.AttachHeavy({}) end)
	local R = a.ns.FarkleRules
	w:Stand(a.name, FW.INN, true)
	for n = 1, 3 do
		local id = FT(w, a).Practice({ target = 2000, first = 1 })
		FT(w, a).Concede(id)
		w:Run(0)
	end
	local h = FT(w, a).History("T")
	eq(#h, 3); eq(h[1].res, "L"); eq(h[1].practice, true)
	for i = 1, 120 do table.insert(h, { id = "P" .. i, t = 0 }) end
	w:As(a, a.ns.FarkleTable.Prune)
	eq(#FT(w, a).History("T"), 100)
	NoErrors(w)
end)

print("FarkleTable: invitations and arbiters (the design)")

test("1.2 the Bone Throw tables: an invitation lasts 60 s; a guest takes one per sender every 30 s and none while at a table ('b', silent)", function()
	local w, a, b, id = Table({ noAnswer = true })
	-- a second invitation from the same host within 30 s: refused busy
	w:Run(5)
	local id2 = FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true })
	eq(id2, nil, "the host has one pending")
	w:Run(56)
	eq(Get(a, id).state, "expired"); eq(Get(b, id).state, "expired")
	assert(Has(Get(a, id).log, "No answer"), "the host is told")
	-- a guest at a live table refuses the next invitation, whoever sends it
	local w2, c, d, id3 = Table()
	local e = w2:Player("Wenna Crale")
	w2:Group({ c, d, e })
	local id4 = FT(w2, e).Create({ guest = d.name, target = 2000, rehearsal = true })
	w2:Run(0)
	eq(Get(e, id4).state, "declined"); eq(Get(e, id4).why, "b")
	NoErrors(w); NoErrors(w2)
end)

test("1.2 the Bone Throw tables: accepted but not in one party: the host is told to invite, and the table opens by itself once the other player joins (no click)", function()
	local w = FW.New()
	local a, b = w:Player(P1), w:Player(P2)
	local id = assert(FT(w, a).Create({ guest = b.name, target = 2000, rehearsal = true }))
	w:Run(0)
	assert(FT(w, b).Answer(id, true))
	w:Run(0)
	local t = Get(a, id)
	eq(t.state, "agreed"); eq(t.needGroup, true)
	assert(Has(t.log, "Invite"), "the host is told to invite")
	eq(#w:Sent({ from = a, type = "KG" }), 0)
	w:Run(5)
	eq(#w:Sent({ from = a, type = "KG" }), 0, "nothing while apart")
	w:Group({ a, b })
	w:Run(1.5)
	eq(#w:Sent({ from = a, type = "KG" }), 1, "the party joined: KG goes out")
	eq(Get(a, id).state, "open"); eq(Get(b, id).state, "open"); eq(Get(a, id).needGroup, nil)
	-- an accepted table is live: its players are busy for another invitation meanwhile
	local w2 = FW.New()
	local c, d, e = w2:Player(P1), w2:Player(P2), w2:Player("Wenna Crale")
	local id2 = assert(FT(w2, c).Create({ guest = d.name, target = 2000, rehearsal = true }))
	w2:Run(0)
	assert(FT(w2, d).Answer(id2, true))
	w2:Run(0)
	eq(Get(d, id2).state, "agreed")
	eq(FT(w2, d).Live().id, id2, "the guest's accepted table is his live one")
	eq(FT(w2, c).Create({ guest = e.name, target = 2000, rehearsal = true }), nil, "the host too: busy")
	-- never grouped: it closes after two minutes on both sides, nothing owed, and they are free
	w2:Run(125)
	eq(Get(c, id2).state, "expired"); eq(Get(d, id2).state, "expired")
	assert(Has(Get(c, id2).log, "didn't open"), "the host is told")
	eq(FT(w2, d).Live(), nil)
	NoErrors(w); NoErrors(w2)
end)

test("1.2 the Bone Throw tables: an arbiter is asked with KO: a player of the table, or one already holding three, refuses; his yes opens the table to all three", function()
	local w, a, b, id, arb = Table({ arbiter = true, noOpening = true })
	eq(Get(arb, id).state, "open"); eq(Get(a, id).state, "open"); eq(Get(b, id).state, "open")
	eq(#w:Sent({ from = arb, type = "KP" }), 2)
	-- a KO naming the arbiter as a player is refused 'a'
	w:As(a, function() a.ns.Arena.Send("KO", "T", ("Kself1~%s~%s~0~2~--~1o~2"):format(a.name, arb.name), { to = arb.name }) end)
	w:Run(0)
	local kp = w:Sent({ from = arb, type = "KP" })
	assert(kp[#kp].msg:find("Kself1~0~a", 1, true), kp[#kp].msg)
	eq(Get(arb, "Kself1"), nil)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: the arbiter voids a game in play (his Void): every client's game ends void, nobody wins", function()
	local w, a, b, id, arb = Table({ arbiter = true })
	eq(Get(arb, id).state, "play")
	eq(w:As(arb, function() return arb.ns.Arena.Do("farkle.void", id) end), true)
	w:Run(0)
	local kt = w:Sent({ from = arb, type = "KT" })
	eq(#kt, 2)
	for _, c in ipairs({ a, b, arb }) do
		local g = Get(c, id).game
		eq(g.over, true, c.short); eq(g.winner, nil, c.short); eq(g.reason, "void", c.short)
	end
	NoErrors(w)
end)

test("1.2 the Bone Throw tables: every table is an arena event (Arena.EventOf 'K'): its fighters, whether it is public, never its stake to anyone but those at it", function()
	local w, a, b, id, arb = Table({ arbiter = true })
	local ev = w:As(a, a.ns.Arena.EventOf, id)
	eq(ev.kind, "farkle"); eq(ev.fighters.A.name, a.name); eq(ev.fighters.B.name, b.name); eq(ev.public, true)
	eq(w:As(a, a.ns.Arena.EventOf, "Knothing1"), nil)
	NoErrors(w)
end)
