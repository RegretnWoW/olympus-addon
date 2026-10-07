-- 1.2, the fights part: fights (ArenaFights.lua), the ledger (ArenaLedger.lua) and tournaments (ArenaTourney.lua)
-- on the test world: the lifecycle, the duel lines and the decision rule, challenges, cards, the
-- ledger's rules and its clerk, belts, the rankings' view models. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local CH = assert(loadfile(H.ROOT .. "tests/arena/lib/chat-host.lua"))(H)
local N = World.NAMES

local function Fights(w, c) return W3.M(w, c, "ArenaFights") end
local function Ledger(w, c) return W3.M(w, c, "ArenaLedger") end
local function State(w, c, fid)
	local f = c.ns.ArenaFights.Find("fights", fid)
	return f and w:As(c, c.ns.ArenaFights.State, f) or nil
end
local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end

-- A public fight judged by the signed arbiter, set (both fighters accepted); returns its fid.
local function Booked(w, cast, opts)
	local AF = Fights(w, cast.arbiter)
	local o = { A = cast.A.name, B = cast.B.name, bo = opts and opts.bo or 1, title = opts and opts.title, cat = opts and opts.cat }
	for k, v in pairs(opts or {}) do o[k] = v end
	local fid = assert(AF.New(o))
	assert(AF.Announce(fid))
	w:Run(0)
	eq(Fights(w, cast.A).Accept(fid), true)
	eq(Fights(w, cast.B).Accept(fid), true)
	w:Run(0)
	return fid
end
-- Both at the ring (their own positions, as AC~H reports them), called, ready, belled, live. The
-- arbiter holds a token for each (he targets one and focuses the other, the design): the weigh-in a
-- rated fight needs (review: the ledger names only GUIDs its arbiter saw).
local function Live(w, cast, fid)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 100, 120)
	W3.Sees(cast.arbiter, { [cast.A] = true, [cast.B] = true })
	local AF = Fights(w, cast.arbiter)
	assert(AF.Call(fid))
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	Fights(w, cast.B).Here(fid)
	w:Run(1)
	eq(State(w, cast.arbiter, fid), "Y", "both at the ring: ready")
	assert(AF.Bell(fid))
	w:Run(0)
	eq(State(w, cast.arbiter, fid), "Z", "the last call")
	w:Run(cast.arbiter.ns.Arena.LastCall(true))
	eq(State(w, cast.arbiter, fid), "L", "live at lockAt")
end

print("ArenaFights: the lifecycle")

test("1.2 the fights part: a public fight from AF to FINAL: announced on the channel from its arbiter, set, called, ready from the fighters' own positions, the bell at now + LastCall, live, the duel line, grace 120 s, FINAL, the ledger entry", function()
	local w, cast = W3.New()
	for _, c in ipairs({ cast.arbiter, cast.spectator }) do W3.Companion(w, c) end
	local fid = Booked(w, cast)
	-- Everyone on the realm heard it; the writer is the arbiter; set once both accepted.
	eq(State(w, cast.spectator, fid), "S")
	eq(cast.spectator.ns.ArenaFights.Find("fights", fid).writer, cast.arbiter.name)
	eq(#w:Sent{ from = cast.arbiter, type = "AF", dist = "CHANNEL" } >= 2, true)
	-- The call reaches each fighter by whisper, with the deadline.
	local called = {}
	cast.A.ns.On("ARENA_CALLED", function(f) called[#called + 1] = f end)
	local lockSeen
	cast.spectator.ns.On("ARENA_LOCK", function(f, lockAt) lockSeen = lockAt end)
	local t0 = w.clock
	Live(w, cast, fid)
	eq(called[1], fid, "the fighter's call")
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.lockAt >= t0 and f.lockAt - f.lockAt % 1, f.lockAt)
	eq(lockSeen, f.lockAt, "ARENA_LOCK on a spectator, with lockAt")
	-- The duel: A knocks B out; the arbiter and both fighters read the line.
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(State(w, cast.arbiter, fid), "R", "a result in its grace")
	eq(f.w, "A"); eq(f.m, "K"); eq(f.rounds[1].src, "L")
	eq(f.graceEnd - w.clock, 120, "grace 120 without markets or held stakes")
	eq(State(w, cast.spectator, fid), "R")
	local results = {}
	cast.spectator.ns.On("ARENA_RESULT", function(x, rec) results[#results + 1] = rec end)
	w:Run(120)
	eq(State(w, cast.arbiter, fid), "F")
	eq(State(w, cast.spectator, fid), "F")
	eq(results[1].w, "A")
	-- Rated (no alts, no catchweight): its ledger entry, kept where the companion is loaded.
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "r"), true)
	eq(#w:Sent{ from = cast.arbiter, type = "AE", dist = "CHANNEL" }, 1)
	local e = w:As(cast.spectator, function() return cast.spectator.ns.ArenaLedger.Entries() end)
	eq(#e, 1); eq(e[1].fid, fid); eq(e[1].w, "A"); eq(e[1].m, "K")
	eq(#w:As(cast.A, function() return cast.A.ns.ArenaLedger.Entries() end), 0, "no companion: no ledger here")
	-- The fighter's own history.
	local mine = cast.A.ns.Arena.Store("L").myFights[cast.A.name]
	eq(#mine, 1); eq(mine[1].w, "W"); eq(mine[1].rated, true)
	W3.NoErrors(w)
end)

test("1.2 the fights part: grace is 300 s with markets open or stakes held, 120 s without (the design); the result is final elsewhere 30 s after the grace", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	-- A synthetic held-stakes flag isolates Grace here. Real market reachability and the same
	-- 300-second path are exercised through an actual Markets sheet in market-reachability.lua.
	f.fl = f.fl .. "s"
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A, true)
	w:Run(0)
	eq(f.w, "B"); eq(f.m, "R", "fled")
	eq(f.graceEnd - w.clock, 300)
	-- A spectator whose writer went quiet: final on its own at graceEnd + 30.
	local g = cast.spectator.ns.ArenaFights.Find("fights", fid)
	g.graceEnd = w.clock - 30
	eq(State(w, cast.spectator, fid), "F")
	W3.NoErrors(w)
end)

test("1.2 the fights part: best of 3 reaches 2:1 (between rounds, the next round straight to live); a round the arbiter voids is fought again", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast, { bo = 3 })
	Live(w, cast, fid)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local AF = Fights(w, cast.arbiter)
	local all = { cast.arbiter, cast.A, cast.B }
	W3.Duel(w, all, cast.A, cast.B)
	w:Run(0)
	eq(f.st, "B"); eq(f.sc[1], 1); eq(f.sc[2], 0)
	eq(State(w, cast.spectator, fid), "B")
	assert(AF.NextRound(fid))
	w:Run(0)
	eq(f.st, "L"); eq(f.round, 2)
	eq(State(w, cast.B, fid), "L", "the fighter told: fight")
	W3.Duel(w, all, cast.B, cast.A)
	w:Run(0)
	eq(f.st, "B"); eq(f.sc[2], 1)
	assert(AF.NextRound(fid))
	w:Run(0)
	W3.Duel(w, all, cast.A, cast.B, true)
	w:Run(0)
	eq(f.st, "R"); eq(f.sc[1], 2); eq(f.sc[2], 1); eq(f.w, "A")
	eq(cast.spectator.ns.ArenaFights.Find("fights", fid).sc[1], 2)
	W3.NoErrors(w)
end)

test("1.2 the fights part: a duel between the two before the bell voids the markets ('early') and the fight goes on; during the last call the bell rings again", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	f.fl = f.fl .. "m"
	local voided = {}
	cast.arbiter.ns.Markets.Void = function(eid, idx, code) voided[#voided + 1] = eid .. " " .. idx .. " " .. code end
	local voids = {}
	cast.arbiter.ns.On("ARENA_VOID", function(x, code) voids[#voids + 1] = code end)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(voided[1], fid .. " * E"); eq(voids[1], "early")
	eq(f.st, "S", "the fight goes on")
	-- The last call: a duel then sends the fight back to ready, and the arbiter rings again.
	W3.Stand(cast.arbiter, 0, 0) W3.Stand(cast.A, 0, 5) W3.Stand(cast.B, 5, 0)
	local AF = Fights(w, cast.arbiter)
	AF.Call(fid) w:Run(0)
	Fights(w, cast.A).Here(fid) Fights(w, cast.B).Here(fid) w:Run(1)
	AF.Bell(fid) w:Run(0)
	eq(f.st, "Z")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	eq(f.st, "Y", "ready again: the bell rings again")
	eq(f.lockAt, nil)
	W3.NoErrors(w)
end)

test("1.2 the fights part: walkovers: a fighter absent at the deadline loses by walkover WO_AUTO later (unrated, the no-show kept by the writer); both absent: void", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 105, 100)
	local AF = Fights(w, cast.arbiter)
	AF.Call(fid) w:Run(0)
	Fights(w, cast.A).Here(fid)
	w:Run(0)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.st, "C", "one of them is not there")
	-- A's "I'm here" repeats every 20 s (his client), so his position stays fresh.
	w:Run(cast.arbiter.ns.ArenaFights.CALL_WINDOW + cast.arbiter.ns.ArenaFights.WO_AUTO + 2)
	eq(f.st, "W"); eq(f.w, "A"); eq(f.code, "absent")
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "r"), false, "unrated")
	eq(cast.arbiter.ns.ArenaFights.NoShows(f.B.gk, "L"), 1, "B's no-show, on the writer's client")
	eq(State(w, cast.spectator, fid), "W")
	eq(#w:Sent{ from = cast.arbiter, type = "AE" }, 0, "no ledger entry")
	-- Both absent: void.
	local fid2 = Booked(w, cast)
	W3.Stand(cast.A, 5000, 5000)
	AF.Call(fid2) w:Run(0)
	w:Run(cast.arbiter.ns.ArenaFights.CALL_WINDOW + cast.arbiter.ns.ArenaFights.WO_AUTO + 2)
	eq(State(w, cast.arbiter, fid2), "V")
	W3.NoErrors(w)
end)

test("1.2 the fights part: presence without UnitInRange (the design): a secret CheckInteractDistance is no error and no presence; a token check that passes keeps a fighter from the automatic walkover", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local SECRET = {}
	for _, c in ipairs(w.clients) do
		c.globals.issecretvalue = function(v) return rawequal(v, SECRET) end
		c.globals.SECRET = SECRET
		-- UnitInRange is secret on this client: any call to it is a test failure.
		c.globals.UnitInRange = function() error("UnitInRange called") end
	end
	W3.Sees(cast.arbiter, { [cast.A] = true, [cast.B] = "secret" })
	local AF = Fights(w, cast.arbiter)
	AF.Call(fid) w:Run(0)
	w:Run(cast.arbiter.ns.ArenaFights.CALL_WINDOW + cast.arbiter.ns.ArenaFights.WO_AUTO + 2)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.st, "W", "B's secret check counts as absent")
	eq(f.w, "A", "A seen close by the arbiter's token: present, never walked over")
	W3.NoErrors(w)
end)

print("ArenaFights: who won")

test("1.2 the fights part: the decision rule (the design): the arbiter's line and a fighter agreeing; both fighters against his line (disputed); no line of his and both fighters agree (F); one fighter and two independent witnesses (W); too little: held, and his ruling logged", function()
	local w, cast = W3.New({ more = { { "w1", "Wenna Crale" }, { "w2", "Parric Stowe" }, { "w3", "Tamsin Vey" } } })
	local all = { cast.arbiter, cast.A, cast.B }
	-- The Chronicle as the arbiter's client keeps it (the world loads no Chronicle of its own).
	local chronicle = {}
	rawset(cast.arbiter.ns, "Chronicle", { Add = function(kind, by, what) chronicle[#chronicle + 1] = kind .. " " .. what end })
	-- His line, and A's agreeing.
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	W3.Duel(w, all, cast.A, cast.B)
	w:Run(0)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.rounds[1].src, "L"); eq(f.rounds[1].w, "A")
	-- Both fighters report B won; the arbiter's own line says A: his line, flagged disputed.
	fid = Booked(w, cast)
	Live(w, cast, fid)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	W3.Duel(w, { cast.arbiter }, cast.A, cast.B)
	w:Run(0)
	eq(f.rounds[1].w, "A"); eq(f.rounds[1].src, "L")
	local ar = W3.Bodies(w, cast.arbiter, "AR", "CHANNEL")
	assert(ar[#ar]:find("~disputed$"), "disputed: " .. ar[#ar])
	-- No line of his: both fighters agree. (Reports alone decide only once RESULT_WAIT passed with
	-- no line of the arbiter's, the review's rule: before, a line of his may still come.)
	local WAIT = cast.arbiter.ns.ArenaFights.RESULT_WAIT
	fid = Booked(w, cast)
	Live(w, cast, fid)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	eq(f.rounds[1], nil, "not yet: the arbiter's own line may still come")
	w:Run(WAIT + 1)
	eq(f.rounds[1].w, "B"); eq(f.rounds[1].src, "F")
	-- One fighter only (B's client missed it), two independent witnesses; an alt's is not counted.
	fid = Booked(w, cast)
	Live(w, cast, fid)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	W3.Duel(w, { cast.A, cast.w1, cast.w2 }, cast.A, cast.B)
	w:Run(WAIT + 1)
	eq(f.rounds[1].w, "A"); eq(f.rounds[1].src, "W"); eq(f.rounds[1].nW, 2)
	-- Too little: held after RESULT_WAIT; the arbiter rules (src A), and the Chronicle has it.
	fid = Booked(w, cast)
	Live(w, cast, fid)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	W3.Duel(w, { cast.A }, cast.A, cast.B)
	w:Run(cast.arbiter.ns.ArenaFights.RESULT_WAIT + 2)
	eq(f.st, "L"); eq(f.held, 1, "held")
	assert(Fights(w, cast.arbiter).Rule(fid, "B", "K"))
	w:Run(0)
	eq(f.rounds[1].w, "B"); eq(f.rounds[1].src, "A")
	assert(chronicle[#chronicle] and chronicle[#chronicle]:find("^arena ruled fight " .. fid), "the Chronicle's line: " .. tostring(chronicle[#chronicle]))
	W3.NoErrors(w)
end)

test("1.2 the fights part: witnesses: 20 at most counted, one each; an alt of a fighter or of the arbiter, and a net-off witness, never count; a report outside the live round is refused", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local AF = cast.arbiter.ns.ArenaFights
	local function Report(from, winner, loser)
		local body = table.concat({ fid, "1", "K", winner, loser, "0", "0" }, "~")
		w:As(cast.arbiter, function() cast.arbiter.ns.Arena.Inject("WHISPER", from, "AW~L1~" .. body) end)
	end
	for i = 1, 25 do Report(("Witness %s-Emberfall"):format(string.char(64 + i)), "Torvin Hale", "Selka Drummond") end
	local o = 0
	for _ in pairs(AF.Stats().refused) do o = o + 1 end
	eq(o > 0, true)
	eq(AF.Stats().refused.witnesses >= 5, true, "past 20: refused")
	Report("Witness A-Emberfall", "Torvin Hale", "Selka Drummond")
	eq((AF.Stats().refused.again or 0) >= 1, true, "one each")
	W3.NoErrors(w)
end)

print("ArenaFights: who may write")

test("1.2 the fights part: AF only from its arbiter (the design S26): a public arbiter's name in someone else's AF, a fid of another's hash, a later AF from anyone but the writer, an arbiter who fights: refused", function()
	local w, cast = W3.New()
	local spectator = cast.spectator
	local AF = spectator.ns.ArenaFights
	local function Inject(from, body)
		w:As(spectator, function() spectator.ns.Arena.Inject("CHANNEL", from, "AF~L1~" .. body) end)
	end
	-- Lida (no arbiter) sends an AF naming the signed arbiter: refused ("writer").
	local fake = { "F1ab" .. spectator.ns.Arena.Hash36((N.bettor2):lower(), 2), "A", "p", "1", "A", "Oswin Marrow", "-", "Torvin Hale", "-",
		"Selka Drummond", "-", "0", "0", "0", "0", "0:0", "-", "-", "0" }
	Inject(N.bettor2, table.concat(fake, "~"))
	eq(AF.Find("fights", fake[1]), nil)
	eq(AF.Stats().refused.writer, 1)
	-- The arbiter's own AF, but with a fid another writer's hash made (squatting): refused.
	fake[1] = "F1ab" .. spectator.ns.Arena.Hash36((N.bettor2):lower(), 2)
	Inject(N.arbiter, table.concat(fake, "~"))
	eq(AF.Stats().refused.hash, 1)
	-- His own, well formed: taken; then a later one from someone else: refused.
	fake[1] = "F1ab" .. spectator.ns.Arena.Hash36((N.arbiter):lower(), 2)
	Inject(N.arbiter, table.concat(fake, "~"))
	eq(AF.Find("fights", fake[1]) ~= nil, true)
	fake[2] = "V"
	Inject(N.councillor, table.concat(fake, "~"))
	eq(AF.Find("fights", fake[1]).st, "A", "unchanged: a public arbiter who is not its writer")
	eq(AF.Stats().refused.writer, 2)
	-- An arbiter who is one of the fighters.
	local own = { "F2ab" .. spectator.ns.Arena.Hash36((N.arbiter):lower(), 2), "A", "p", "1", "A", "Oswin Marrow", "-", "Oswin Marrow", "-",
		"Selka Drummond", "-", "0", "0", "0", "0", "0:0", "-", "-", "0" }
	Inject(N.arbiter, table.concat(own, "~"))
	eq(AF.Find("fights", own[1]), nil)
	-- A time ahead of the clock.
	local ahead = { "F3ab" .. spectator.ns.Arena.Hash36((N.arbiter):lower(), 2), "A", "p", "1", "A", "Oswin Marrow", "-", "Torvin Hale", "-",
		"Selka Drummond", "-", spectator.ns.Arena.B36(w.clock + 3600), "0", "0", "0", "0:0", "-", "-", "0" }
	Inject(N.arbiter, table.concat(ahead, "~"))
	eq(AF.Find("fights", ahead[1]), nil)
	W3.NoErrors(w)
end)

test("1.2 the fights part: AR from anyone but the writer, the card's promoter or the King (in grace) is ignored; AC from someone else is ignored", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	local g = cast.spectator.ns.ArenaFights.Find("fights", fid)
	w:As(cast.spectator, function()
		cast.spectator.ns.Arena.Inject("CHANNEL", N.bettor2, "AR~L1~" .. table.concat({ fid, "1", "0:1", "B", "K", "a", "0", "L", "1", "0", "-" }, "~"))
	end)
	eq(g.st, "L", "a spectator's AR changes nothing")
	-- A fighter's "call" from someone not the arbiter.
	local called = 0
	cast.A.ns.On("ARENA_CALLED", function() called = called + 1 end)
	w:As(cast.A, function() cast.A.ns.Arena.Inject("WHISPER", N.bettor2, "AC~L1~" .. fid .. "~C~1~0~0~0") end)
	eq(called, 0)
	W3.NoErrors(w)
end)

print("ArenaFights: challenges")

test("1.2 the fights part: a direct challenge (AS~X, AS~Y): the challenger writes the fight, whispered to the opponent; both duel lines agree: final, unrated, never on the channel, in each fighter's own history", function()
	local w, cast = W3.New()
	local A, B = Fights(w, cast.A), Fights(w, cast.B)
	local endedA, endedB
	rawset(cast.A.ns, "ArenaMatch", { Ended = function(...) endedA = { ... } end })
	rawset(cast.B.ns, "ArenaMatch", { Vet = function() return true, "M1" end, Ended = function(...) endedB = { ... } end })
	local asked
	cast.B.ns.On("ARENA_CHALLENGE", function(oid) asked = oid end)
	local oid = assert(A.Challenge(cast.B.name, { bo = 1, from = "M1" }))
	w:Run(0)
	eq(asked, oid)
	assert(B.Answer(oid, true))
	w:Run(0)
	local f = cast.A.ns.ArenaFights.Find("fights", oid)
	eq(f.st, "S"); eq(cast.A.ns.ArenaFights.Has(f.fl, "d"), true); eq(f.arb, nil)
	eq(State(w, cast.B, oid), "S", "whispered to the opponent")
	eq(State(w, cast.spectator, oid), nil, "nobody else")
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	eq(State(w, cast.A, oid), "F"); eq(State(w, cast.B, oid), "F")
	eq(f.w, "B")
	eq(#w:Sent{ type = "AF", dist = "CHANNEL" }, 0, "nothing on the channel")
	eq(#w:Sent{ type = "AE" }, 0, "not in the ledger")
	local mineB = cast.B.ns.Arena.Store("L").myFights[cast.B.name]
	eq(mineB[1].w, "W"); eq(mineB[1].direct, true); eq(mineB[1].rated, false)
	eq(endedA[1], "M1", "the opener keeps the exact match id")
	eq(endedB[1], "M1", "Vet links the receiver to the same exact match without changing AS")
	W3.NoErrors(w)
end)

test("1.2 the fights part: an unrelated direct fight against the same opponent cannot end a handed match", function()
	local w, cast = W3.New()
	local endedA, endedB = 0, 0
	rawset(cast.A.ns, "ArenaMatch", { Ended = function() endedA = endedA + 1 end })
	rawset(cast.B.ns, "ArenaMatch", { Ended = function() endedB = endedB + 1 end })
	local A, B = Fights(w, cast.A), Fights(w, cast.B)
	local oid = assert(A.Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(B.Answer(oid, true))
	w:Run(0)
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(endedA, 0); eq(endedB, 0)
	W3.NoErrors(w)
end)

test("1.2 the fights part: an arbitrated matched fight keeps the exact match id whether AS Z arrives before or after AF", function()
	for reverse = 0, 1 do
		local w, cast = W3.New()
		local mid = "M" .. tostring(reverse + 2)
		rawset(cast.A.ns, "ArenaMatch", { Ended = function() end })
		rawset(cast.B.ns, "ArenaMatch", { Vet = function() return true, mid end, Ended = function() end })
		local A, B = Fights(w, cast.A), Fights(w, cast.B)
		local oid = assert(A.Challenge(cast.B.name, { how = "a", arbiter = cast.arbiter.name, bo = 3, from = mid }))
		w:Run(0)
		assert(B.Answer(oid, true))
		w:Run(0)
		assert(Fights(w, cast.arbiter).Judge(oid, true))
		if reverse == 1 then
			local af, rest = {}, {}
			for _, item in ipairs(cast.arbiter.comm.queue) do
				local into = item.msg:sub(1, 2) == "AF" and af or rest
				into[#into + 1] = item
			end
			cast.arbiter.comm.queue = {}
			for _, list in ipairs({ af, rest }) do
				for _, item in ipairs(list) do cast.arbiter.comm.queue[#cast.arbiter.comm.queue + 1] = item end
			end
		end
		w:Run(0)
		local fid = assert(cast.A.ns.ArenaFights.challenges[oid].fid)
		eq(cast.A.ns.ArenaFights.Find("fights", fid).from, mid)
		eq(cast.B.ns.ArenaFights.Find("fights", fid).from, mid)
		W3.NoErrors(w)
	end
end)

test("1.2 the fights part: a challenge with an arbiter (AS X, Y, Q, Z): the arbiter makes a private fight (its own fid), whispered to both fighters; a no from the opponent ends it; a matched partner outside the agreed stake is refused (m)", function()
	local w, cast = W3.New()
	local A, B = Fights(w, cast.A), Fights(w, cast.B)
	local oid = assert(A.Challenge(cast.B.name, { how = "a", arbiter = cast.arbiter.name, bo = 3 }))
	w:Run(0)
	assert(B.Answer(oid, true))
	w:Run(0)
	local judge = cast.arbiter.ns.ArenaFights.challenges[oid]
	eq(judge and judge.state, "judge")
	assert(Fights(w, cast.arbiter).Judge(oid, true))
	w:Run(0)
	local c = cast.A.ns.ArenaFights.challenges[oid]
	eq(c.state, "set")
	local fid = c.fid
	eq(fid ~= oid, true, "the arbiter's own id")
	eq(State(w, cast.A, fid), "S"); eq(State(w, cast.B, fid), "S")
	eq(State(w, cast.spectator, fid), nil, "private")
	eq(cast.A.ns.ArenaFights.Find("fights", fid).bo, 3)
	-- A no (AS goes at most every 3 s from one sender).
	w:Run(3)
	local oid2 = assert(A.Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(B.Answer(oid2, false, "n"))
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[oid2].state, "no")
	-- Matchmaking's agreed stake (the design): outside it, refused with m.
	-- (ArenaMatch.lua is matchmaking's: its Vet, stood in for. The stake in gold, the realm's currency,
	-- with the money part's money side stood in: the review refuses a stake under glory points, the design.)
	rawset(cast.B.ns, "ArenaMatch", { Vet = function(sender, game, stake) return stake <= 5000 end })
	w:Run(3)
	W3.Money(w, cast.A)
	W3.Money(w, cast.B)
	local oid3 = assert(A.Challenge(cast.B.name, { bo = 1, stake = 20000, how = "d", cur = "g", from = "M1" }))
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[oid3].state, "no"); eq(cast.A.ns.ArenaFights.challenges[oid3].why, "m")
	rawset(cast.B.ns, "ArenaMatch", nil)
	W3.NoErrors(w)
end)

test("1.2 the fights part: the challenge action answers Arena.Can (matchmaking's Staked): rules, a debtor, the standing cap, saved data kept for gold", function()
	local w, cast = W3.New()
	local Arena = W3.M(w, cast.A, "Arena")
	eq(Arena.Can("fights.challenge", cast.B.name, { stake = 0 }), true)
	local ok, why = Arena.Can("fights.challenge", cast.A.name, {})
	eq(ok, false); eq(why, "self")
	cast.A.ns.Debts.Blocked = function(name) return name == cast.A.name, "D" end
	ok, why = Arena.Can("fights.challenge", cast.B.name, {})
	eq(why, "debtor")
	cast.A.ns.Debts.Blocked = nil
	-- No stake under glory points (the design: no direct or trade-held stakes), whatever the cap.
	ok, why = Arena.Can("fights.challenge", cast.B.name, { stake = 20000, how = "d", cur = "p" })
	eq(why, "currency")
	-- The beta: saved data lost at login (Arena.Persists false): gold stakes refused.
	ok, why = Arena.Can("fights.challenge", cast.B.name, { stake = 5000, how = "d", cur = "g" })
	eq(why, "persists")
	-- the money part's money side missing (a function of its contract gone, as on a build without it): refused,
	-- never an unchecked stake. (This branch has the money part, so one function is taken away here.)
	local persists = cast.A.ns.Arena.Persists
	cast.A.ns.Arena.Persists = function() return true end
	local direct = cast.A.ns.Stakes.Direct
	cast.A.ns.Stakes.Direct = nil
	ok, why = Arena.Can("fights.challenge", cast.B.name, { stake = 5000, how = "d", cur = "g" })
	eq(why, "money")
	cast.A.ns.Stakes.Direct = direct
	cast.A.ns.Arena.Persists = persists
	-- Past the standing cap.
	W3.Money(w, cast.A, { cap = 10000 })
	ok, why = Arena.Can("fights.challenge", cast.B.name, { stake = 20000, how = "d", cur = "g" })
	eq(why, "cap")
	eq(Arena.Can("fights.challenge", cast.B.name, { stake = 10000, how = "d", cur = "g" }), true)
	w:As(cast.A, function() cast.A.ns.Arena.SetRules(false) end)
	ok, why = Arena.Can("fights.challenge", cast.B.name, {})
	eq(why, "rules")
	W3.NoErrors(w)
end)

print("ArenaFights: cards, the week, the events")

test("1.2 the fights part: a Fight Night card (AN) by a promoter: bouts written by the promoter, one handed to another public arbiter who takes it over; the week's rows; the events list; the Fight of the Night and the fastest knockout", function()
	local w, cast = W3.New({ more = { { "hc", "Brannoc Weald" } } })
	local king = cast.king
	local C = W3.M(w, king, "ArenaFights").Card
	local cid = assert(w:As(king, king.ns.ArenaFights.Card.New, "Night of Blades", w.clock + 3600))
	local fid = assert(w:As(king, king.ns.ArenaFights.Card.AddBout, cid, { A = cast.A.name, B = cast.B.name }))
	w:Run(0)
	local card = cast.spectator.ns.ArenaFights.Card.Get(cid)
	eq(card.promoter, king.name); eq(card.fids[1], fid)
	-- The promoter's own title shows on the King's screen only because he is the King.
	eq(w:As(cast.spectator, cast.spectator.ns.ArenaFights.Card.ScreenTitle, cid), "Night of Blades")
	-- The bout handed to the signed arbiter: he writes it from then on.
	w:As(king, king.ns.ArenaFights.Announce, fid)
	assert(w:As(king, king.ns.ArenaFights.Card.SetArbiter, cid, fid, cast.arbiter.name))
	w:Run(0)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.writer, cast.arbiter.name)
	-- The week (Week.providers: every client's own week gets these rows).
	local rows = w:As(cast.spectator, cast.spectator.ns.ArenaFights.WeekRows, w.clock)
	eq(#rows >= 1, true); eq(rows[1].title, "Night of Blades")
	-- The events list: the card, upcoming.
	local ev = w:As(cast.spectator, cast.spectator.ns.ArenaFights.Events, {})
	eq(ev[1].kind, "card"); eq(ev[1].id, cid); eq(ev[1].upcoming, true); eq(ev[1].count, 1)
	-- The bout is fought; the card is done; the awards.
	eq(Fights(w, cast.A).Accept(fid), true) eq(Fights(w, cast.B).Accept(fid), true) w:Run(0)
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	w:Run(125)
	eq(State(w, cast.arbiter, fid), "F")
	assert(w:As(king, king.ns.ArenaFights.Card.SetFotN, cid, fid))
	w:Run(2)
	local kc = king.ns.ArenaFights.Card.Get(cid)
	eq(kc.st, "D", "every bout final: done")
	eq(kc.awards.fotn, fid); eq(kc.awards.ko, fid)
	eq(cast.spectator.ns.ArenaFights.Card.Get(cid).awards.fotn, fid)
	-- A Hand or Steward may promote (the owner's answer); a plain member may not.
	eq(w:As(cast.spectator, cast.spectator.ns.ArenaFights.Card.New, "Mine", w.clock), nil)
	W3.NoErrors(w)
end)

print("ArenaLedger: the ledger's rules, the clerk")

-- A fighter's invented name from his gk (letters only, as King.CleanName takes names).
local function NameOf(gk)
	local tail = gk:sub(-4)
	return "Fighter " .. tail:gsub("%x", function(c) return string.char(97 + tonumber(c, 16)) end):gsub("^%l", string.upper) .. "-Emberfall"
end
local function Entry(i, a, b, t, extra)
	local e = { season = 1, fid = "F" .. i .. "zz", t = t, cat = "A", bo = 1, gkA = a, A = NameOf(a),
		fA = { class = "WA", race = 1, level = 60 }, gkB = b, B = NameOf(b), fB = { class = "MA", race = 4, level = 60 },
		sc = "1:0", w = "A", m = "K", dur = 60, gkArb = "3e8.aaaaaaaa", fl = "pr" }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

test("1.2 the fights part: what counts (the design): the arbiter's r; rounds under 15 s on average; a fighter's 11th fight of a server day; a pair's 4th in 7 days", function()
	local w, cast = W3.New()
	local LG = cast.spectator.ns.ArenaLedger
	local day = 1790812800 + 86400
	local list = {}
	-- The same two fighters: 3 in 7 days count, the 4th does not.
	for i = 1, 4 do list[#list + 1] = Entry(i, "3e8.00000001", "3e8.00000002", day + i * 60) end
	-- A fighter's day: fights 5.. against fresh opponents; 10 rated in a day, the 11th not.
	for i = 5, 12 do list[#list + 1] = Entry(i, "3e8.00000001", ("3e8.%08x"):format(100 + i), day + i * 60) end
	list[#list + 1] = Entry(13, "3e8.00000003", "3e8.00000004", day + 20 * 60, { dur = 14 })
	list[#list + 1] = Entry(14, "3e8.00000005", "3e8.00000006", day + 21 * 60, { dur = 40, sc = "2:1", bo = 3 })
	list[#list + 1] = Entry(15, "3e8.00000007", "3e8.00000008", day + 22 * 60, { fl = "p" })
	local counts = LG.Counted(list)
	eq(counts.F1zz, true) eq(counts.F3zz, true) eq(counts.F4zz, false, "the pair's 4th in 7 days")
	eq(counts.F11zz, true, "his 10th rated fight of the day (the 4th with the pair did not count)")
	eq(counts.F12zz, false, "his 11th of the day")
	eq(counts.F13zz, false, "14 s")
	eq(counts.F14zz, false, "a bo3 of 40 s over 3 rounds: under 15 s a round")
	eq(counts.F15zz, false, "not rated by its arbiter")
	-- The next day, the same fighter counts again; the pair still waits its week.
	local later = { Entry(20, "3e8.00000001", "3e8.00000099", day + 86400 + 60) }
	for _, e in ipairs(list) do later[#later + 1] = e end
	table.sort(later, function(x, y) return x.t < y.t end)
	eq(LG.Counted(later).F20zz, true)
	W3.NoErrors(w)
end)

test("1.2 the fights part: the ledger takes AE only from a listed arbiter who is not its fighter, never ahead of the clock, never a rehearsal; a fid already held with other content is a conflict (the first kept)", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local function Send(from, e)
		w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", from, "AE~L1~" .. LG.Encode(e)) end)
	end
	local t = w.clock - 100
	Send(N.bettor2, Entry(1, "3e8.00000001", "3e8.00000002", t))
	eq(#w:As(sp, LG.Entries), 0, "not an arbiter")
	Send(N.arbiter, Entry(1, "3e8.00000001", "3e8.00000002", t))
	eq(#w:As(sp, LG.Entries), 1)
	Send(N.arbiter, Entry(1, "3e8.00000001", "3e8.00000002", t, { w = "B" }))
	eq(w:As(sp, LG.Entries)[1].w, "A", "the first kept"); eq(LG.Stats().conflicts, 1)
	Send(N.arbiter, Entry(2, "3e8.00000001", "3e8.00000002", w.clock + 600))
	eq(#w:As(sp, LG.Entries), 1, "ahead of the clock")
	Send(N.arbiter, Entry(3, "3e8.00000001", "3e8.00000002", t, { gkArb = "3e8.00000001" }))
	eq(#w:As(sp, LG.Entries), 1, "its arbiter is its fighter")
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.arbiter, "AE~T1~" .. LG.Encode(Entry(4, "3e8.00000001", "3e8.00000002", t))) end)
	eq(#w:As(sp, LG.Entries), 1, "a rehearsal never enters")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the clerk (a public arbiter with the companion, never the King's character) broadcasts a carousel of the week's entries; 1,000 listeners that join late all hold every entry within one turn, and the clerk's sends do not grow with them", function()
	local w, cast = W3.New({ more = { { "hc", "Brannoc Weald" }, { "late", "Wenna Crale" } } })
	local clerk = cast.arbiter
	W3.Companion(w, clerk)
	W3.Companion(w, cast.king)
	local LG = clerk.ns.ArenaLedger
	-- Forty entries in the ledger of the clerk.
	for i = 1, 40 do
		w:As(clerk, LG.Keep, Entry(i, ("3e8.%08x"):format(i), ("3e8.%08x"):format(1000 + i), w.clock - 3600 + i), "L", "own")
	end
	eq(#w:As(clerk, LG.Entries), 40)
	-- The King's client is never the clerk, even with the ledger loaded.
	eq(w:As(cast.king, cast.king.ns.ArenaLedger.MayClerk), false)
	eq(w:As(clerk, LG.MayClerk), true)
	-- 1,000 listeners of the channel join now: each decodes the pieces it hears (the real decoder).
	local listeners, have = {}, {}
	for i = 1, 1000 do
		local l = { name = ("Listener%04d-Emberfall"):format(i), short = ("Listener%04d"):format(i), realm = "Emberfall", online = true,
			errors = {}, globals = {}, comm = { handlers = {}, queue = {}, chatq = {}, results = {} } }
		have[i] = {}
		l.comm.handlers.AB = function(dist, sender, text)
			local kind, season, week, n, of, entries = text:match("^AB~L1~(P)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~(.*)$")
			if not kind then return end
			for part in (entries .. ";"):gmatch("([^;]*);") do
				if part ~= "" then
					local e = w:As(cast.late, cast.late.ns.ArenaLedger.Decode, season .. "~" .. part, sender)
					if e then have[i][e.fid] = true end
				end
			end
		end
		listeners[i] = l
		w.clients[#w.clients + 1] = l
	end
	W3.Companion(w, cast.late)
	local start = w.clock
	w:Run(LG.CLERK_WAIT + 30 * 20)
	local sent = #w:Sent{ from = clerk, type = "AB" }
	-- Every listener holds all 40; the late real client too.
	for i = 1, 1000 do
		local n = 0
		for _ in pairs(have[i]) do n = n + 1 end
		if n ~= 40 then error(("listener %d holds %d"):format(i, n)) end
	end
	eq(#w:As(cast.late, cast.late.ns.ArenaLedger.Entries), 40, "the late client's ledger")
	local turn = w.clock - start
	eq(turn <= LG.CLERK_WAIT + 600, true, "within one turn")
	-- The pieces are broadcasts: the same count whoever listens (40 entries ~ a few pieces a turn).
	eq(sent < 60, true, "sends: " .. sent)
	for _ = 1, 1000 do table.remove(w.clients) end
	W3.NoErrors(w)
end)

print("ArenaLedger: ratings, belts, the rankings' one view, the history")

test("1.2 the fights part: the rankings' one switchable view: periods today, this week, this month, all time; categories global, a class, a race; a page of rows; the fighter's own row", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local now = w.clock
	local list = {
		Entry(1, "3e8.00000001", "3e8.00000002", now - 40 * 86400),                 -- before this month
		Entry(2, "3e8.00000001", "3e8.00000003", now - 2 * 3600),                   -- today
		Entry(3, "3e8.00000003", "3e8.00000002", now - 3600, { fA = { class = "MA", race = 4, level = 60 }, fB = { class = "MA", race = 1, level = 60 } }),
	}
	for _, e in ipairs(list) do w:As(sp, LG.Keep, e, "L", "clerk") end
	-- (A season word covering the entries.)
	sp.ns.Arena.Store("L").season = { n = 1, start = now - 60 * 86400, stop = now + 30 * 86400, vac = 6, def = 4, brackets = 0, at = now - 60 * 86400 }
	w:As(sp, LG.Bump)
	local view = w:As(sp, LG.RankingView, "today", "A", 1)
	eq(view.period, "today"); eq(view.loaded, true)
	eq(#view.periods, 4); eq(view.periods[1].key, "today"); eq(view.periods[1].selected, true); eq(view.periods[4].key, "all")
	eq(view.categories[1].cat, "A"); eq(view.categories[1].selected, true)
	local cats = {}
	for _, c in ipairs(view.categories) do cats[c.cat] = c.kind end
	eq(cats.CMA, "class"); eq(cats.R4, "race")
	-- Today: 1 and 3 won today; 2 and 3 lost once.
	eq(#view.rows, 3)
	eq(view.rows[1].delta > 0, true)
	local all = w:As(sp, LG.RankingView, "all", "A", 1)
	eq(#all.rows, 3); eq(all.rows[1].rank, 1)
	-- The mages' ranking: fighter 3 (a mage in his latest weigh-in) and 2 (the first fight's).
	local mages = w:As(sp, LG.RankingView, "all", "CMA")
	eq(mages.label ~= nil, true)
	for _, r in ipairs(mages.rows) do assert(r.gk == "3e8.00000003" or r.gk == "3e8.00000002", r.gk) end
	-- The month: the 40-day-old fight is out.
	local month = w:As(sp, LG.Ranking, "month", "A", { now = now })
	for _, r in ipairs(month) do if r.gk == "3e8.00000001" then eq(r.fights, 1, "only today's") end end
	W3.NoErrors(w)
end)

test("1.2 the fights part: the fight history: recent public fights overall, a fighter's own newest first; a private fight hidden from a private fighter's list, a public event always listed (the design)", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local now = w.clock
	w:As(sp, LG.Keep, Entry(1, "3e8.00000001", "3e8.00000002", now - 300), "L", "clerk")
	w:As(sp, LG.Keep, Entry(2, "3e8.00000001", "3e8.00000003", now - 200, { fl = "r" }), "L", "clerk")
	w:As(sp, LG.Keep, Entry(3, "3e8.00000004", "3e8.00000001", now - 100), "L", "clerk")
	local recent = w:As(sp, LG.History, {})
	eq(#recent, 2, "public fights only"); eq(recent[1].fid, "F3zz")
	local his = w:As(sp, LG.History, { gk = "3e8.00000001" })
	eq(#his, 2, "his private fight hidden: his history is private (unanswered)")
	eq(his[1].fid, "F3zz"); eq(his[1].won, false); eq(his[2].won, true)
	-- He shows his list (his AP says pub): the private fight shows, its opponent as "a private fighter".
	sp.ns.Arena.Heavy("L").profiles = { ["3e8.00000001"] = { name = NameOf("3e8.00000001"), gk = "3e8.00000001", pub = true } }
	his = w:As(sp, LG.History, { gk = "3e8.00000001" })
	eq(#his, 3)
	eq(his[2].fid, "F2zz"); eq(his[2].private, true); eq(his[2].opponent, nil)
	W3.NoErrors(w)
end)

test("1.2 the fights part: belts from the core's title fights and belt words (no ledger needed): a vacant belt won in a public title fight; the podium words (AV 2 and 3) from a public arbiter only", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	local LG = sp.ns.ArenaLedger
	local t = w.clock - 600
	local function Send(from, e) w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", from, "AE~L1~" .. LG.Encode(e)) end) end
	Send(N.arbiter, Entry(1, "3e8.00000001", "3e8.00000002", t, { fl = "prtb" }))
	local holders = w:As(sp, LG.Holders, "L")
	eq(#holders, 1); eq(holders[1].gk, "3e8.00000001"); eq(holders[1].cat, "A")
	eq(sp.ns.Arena.Heavy("L"), nil, "no companion: the core's titles did it")
	-- The podium: the clerk's word (a public arbiter); a plain member's refused.
	local function Word(from, id, place, gk)
		w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", from, "AV~L1~" .. table.concat({ id, "A", place, gk, sp.ns.Arena.B36(w.clock - 10), "-", "-" }, "~")) end)
	end
	Word(N.bettor2, "V1aa", "2", "3e8.00000002")
	eq(#w:As(sp, LG.PodiumWords, "L"), 0)
	Word(N.arbiter, "V1ab", "2", "3e8.00000002")
	local pod = w:As(sp, LG.PodiumWords, "L")
	eq(#pod, 1); eq(pod[1].place, 2); eq(pod[1].gk, "3e8.00000002")
	W3.NoErrors(w)
end)

test("1.2 the fights part: a client holding the whole ledger checks a podium word (AV 2 and 3) against its own table: a public arbiter's word that names someone else is refused", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	-- Two fighters with CONTENDER_MIN counted fights each, against fresh opponents (no pair or day
	-- cap): 10 wins for the 2nd place, 9 and a loss for the 3rd.
	local t0 = w.clock - 5 * 86400
	for i = 1, 10 do
		w:As(sp, LG.Keep, Entry(100 + i, "3e8.00000020", "3e8.000001" .. string.format("%02d", i), t0 + i * 600), "L", "clerk")
		w:As(sp, LG.Keep, Entry(200 + i, "3e8.00000030", "3e8.000002" .. string.format("%02d", i), t0 + 86400 + i * 600,
			i == 1 and { w = "B" } or nil), "L", "clerk")
	end
	local b = w:As(sp, LG.Built, "L")
	local table2 = w:As(sp, sp.ns.ArenaRating.Podium, b, w:As(sp, LG.BeltState, "L"), "A", { now = w.clock })
	eq(table2[2], "3e8.00000020"); eq(table2[3], "3e8.00000030")
	local function Word(id, place, gk)
		w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.arbiter, "AV~L1~" .. table.concat({ id, "A", place, gk, sp.ns.Arena.B36(w.clock - 10), "-", "-" }, "~")) end)
	end
	-- The clerk's digest, heard and matching: this client holds the whole ledger (the review: before
	-- a digest, a client can't tell, and takes the word).
	local d = w:As(sp, LG.Digest, "L")
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.arbiter, "AB~L1~" .. table.concat({ "D", sp.ns.Arena.B36(d.season), sp.ns.Arena.B36(d.n), d.hash,
		#d.weeks > 0 and table.concat(d.weeks, ",") or "-" }, "~")) end)
	eq(w:As(sp, LG.Synced, "L"), true)
	Word("V2aa", "2", "3e8.00000030")
	eq(#w:As(sp, LG.PodiumWords, "L"), 0, "not the table's second")
	eq(LG.Stats().refused.podium, 1)
	Word("V2ab", "2", "3e8.00000020")
	Word("V2ac", "3", "3e8.00000030")
	eq(#w:As(sp, LG.PodiumWords, "L"), 2)
	W3.NoErrors(w)
end)

print("ArenaTourney")

test("1.2 the fights part: a tournament of 8: 10 sign up (8 and 2 on the waitlist), registration closes (entrant numbers 1..10), check-in with a no-show (the waitlist fills in), the /roll draw (an extra roll ignored and flagged), the bracket's bouts, Reached and StageOf", function()
	local more = {}
	local names = { "Aric", "Bram", "Cael", "Dorn", "Eska", "Fenn", "Gorm", "Hale", "Isla", "Jory" }
	for i, n in ipairs(names) do more[#more + 1] = { "e" .. i, n .. " Stone" } end
	local w, cast = W3.New({ more = more })
	local king = cast.king
	local T = W3.M(w, king, "ArenaTourney")
	local tid = assert(T.New({ title = "Spring Cup", size = 8, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" }))
	w:Run(0)
	for i = 1, 10 do
		eq(W3.M(w, cast["e" .. i], "ArenaTourney").Sign(tid), true)
		w:Run(4)
	end
	local t = king.ns.ArenaTourney.Find(tid)
	eq(#t.entrants, 10)
	eq(t.entrants[9].wait, true); eq(t.entrants[10].wait, true)
	assert(T.CloseRegistration(tid))
	w:Run(0)
	eq(t.st, "K"); eq(t.entrants[1].n, 1); eq(t.entrants[10].n, 10)
	-- Markets learn the entrants by number (Arena.EventOf).
	local ev = w:As(cast.spectator, cast.spectator.ns.Arena.EventOf, tid)
	eq(ev.kind, "tourney"); eq(ev.entrants[10].name, cast.e10.name)
	-- Check-in: all but the 3rd; the waitlist's first fills in.
	w.clock = t.tCheck + 1
	for i = 1, 10 do
		if i ~= 3 then W3.M(w, cast["e" .. i], "ArenaTourney").CheckIn(tid) w:Run(4) end
	end
	local field = w:As(king, king.ns.ArenaTourney.Field, t)
	eq(#field, 8)
	local inField = {}
	for _, e in ipairs(field) do inField[e.name] = true end
	eq(inField[cast.e9.name], true, "the waitlist's first in"); eq(inField[cast.e10.name], nil); eq(inField[cast.e3.name], nil)
	local scratched = w:As(king, king.ns.ArenaTourney.Scratched, t)
	table.sort(scratched)
	eq(table.concat(scratched, ","), "3,10")
	-- The draw: the King draws in his raid; each Roll click's line counts (the first valid of a step).
	w:Group({ king.name, cast.e1.name, cast.e2.name }, true)
	assert(T.StartDraw(tid))
	eq(t.st, "D")
	local AB = king.ns.ArenaBracket
	local state = w:As(king, king.ns.ArenaTourney.DrawState, t)
	local steps = state.total
	eq(steps, 5, "8 entrants, 2 seeds: 6 to draw, 5 rolls")
	king.globals.RandomRoll = function(lo, hi) king.rolled = hi end
	local witnesses = { king, cast.e1, cast.e2 }
	for s = 1, steps do
		local ok, step, hi = T.DrawStep(tid)
		eq(ok, true); eq(step, s)
		W3.Roll(w, witnesses, king, 1, 1, hi)
		if s == 2 then W3.Roll(w, witnesses, king, 2, 1, hi) end -- a second roll of step 2: ignored, flagged
		w:Run(0)
	end
	eq(t.st, "L", "drawn: live")
	eq(#t.flags >= 1, true, "the extra roll flagged")
	eq(#w:Sent{ from = king, type = "AD" }, steps)
	-- The first round's bouts, public fights of the King's.
	local bouts = 0
	for _ in pairs(t.bouts) do bouts = bouts + 1 end
	eq(bouts, 4)
	-- A raid witness saw the same lines: no dispute.
	eq(cast.e1.ns.ArenaTourney.Find(tid).disputed, nil)
	-- Reached and StageOf before anything is decided: still open.
	local v = w:As(cast.spectator, cast.spectator.ns.ArenaTourney.View, tid)
	eq(#v.matches >= 4, true)
	eq(w:As(king, king.ns.ArenaTourney.StageOf, tid, 3), "scratched", "the no-show")
	local first = t.entrants[1]
	eq(w:As(king, king.ns.ArenaTourney.StageOf, tid, first.n), nil, "still in: not settled")
	-- Each bout to its A side (walkovers: the bracket moves on as FINAL results move it); the
	-- rounds' bouts are made as their feeders end; the champion is the last one standing.
	local stages = {}
	for _, c in ipairs({ king, cast.spectator }) do c.ns.On("ARENA_TOURNEY", function(x, stage) if c == cast.spectator then stages[#stages + 1] = stage end end) end
	for _ = 1, 3 do
		for _, fid in pairs(t.bouts) do
			local f = king.ns.ArenaFights.Find("fights", fid)
			if f.st == "S" then w:As(king, king.ns.ArenaFights.Walkover, fid, "A") end
		end
		w:Run(6)
	end
	eq(t.st, "F", "finished")
	local champion = w:As(king, king.ns.ArenaTourney.Winner, tid)
	assert(champion, "a champion")
	local R = t.bracket.rounds
	eq(R, 3)
	eq(w:As(king, king.ns.ArenaTourney.Reached, tid, champion), R + 1, "the champion: R + 1")
	local champ
	for _, e in ipairs(t.entrants) do if e.gk == champion then champ = e end end
	eq(w:As(king, king.ns.ArenaTourney.StageOf, tid, champ.n), 1, "stage 1: champion")
	-- A spectator builds the same bracket from the seeds and the bouts it heard.
	eq(w:As(cast.spectator, cast.spectator.ns.ArenaTourney.Winner, tid), champion)
	eq(stages[#stages], "F")
	W3.NoErrors(w)
end)

print("ArenaFights: the registry of events and the weight rule")

test("1.2 the fights part: Arena.EventOf for a fight and a card; an idle client that hears a public fight keeps it in memory only, and runs no timer", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local ev = w:As(cast.spectator, cast.spectator.ns.Arena.EventOf, fid)
	eq(ev.kind, "fight"); eq(ev.opener, cast.arbiter.name); eq(ev.fighters.A.name, cast.A.name); eq(ev.public, true); eq(ev.mode, "L")
	local s = cast.spectator.ns.Arena.Store("L")
	eq(s.fights, nil, "not in the core (not involved)")
	eq(cast.spectator.ns.Arena.Heavy("L"), nil)
	w:Run(120)
	eq(#w:Timers(cast.spectator, true), 0, "no arena timer on a spectator")
	eq(cast.spectator.ns.Arena.Ticking(), false)
	W3.NoErrors(w)
end)

test("1.2 Arena chat rooms: a fight's stable identity opens through the main Chat host or its adapter event, and its phase is retained for 30 minutes after completion", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	local changed, fallback = {}, {}
	sp.ns.On("ARENA_CHAT_ROOM", function(spec) changed[#changed + 1] = spec end)
	sp.ns.On("ARENA_CHAT_OPEN", function(spec) fallback[#fallback + 1] = spec end)
	local fid = Booked(w, cast)
	local room = w:As(sp, sp.ns.Arena.ChatRoom, fid)
	eq(room.key, "arena:" .. fid); eq(room.id, fid)
	eq(room.kind, "fight"); eq(room.eventKind, "fight"); eq(room.audience, "duel"); eq(room.access, "members")
	eq(room.title, sp.ns.L.ARENA_WEEK_FIGHT:format(cast.A.short, cast.B.short))
	eq(room.phase, "upcoming"); eq(room.active, true); eq(room.recoverable, true)
	eq(room.supportsBets, true); eq(room.supportsComments, true)
	eq(room.fighters.A.name, cast.A.name); eq(room.fighters.B.name, cast.B.name)
	eq(table.concat(room.participants, ","), table.concat({ cast.A.name, cast.B.name, cast.arbiter.name }, ","))
	eq(changed[#changed].key, room.key, "a lifecycle adapter event carries the canonical spec")

	-- Without a current Chat host, the neutral adapter event receives the exact same room.
	local opened, same = w:As(sp, sp.ns.Arena.OpenChatRoom, fid)
	eq(opened, false); eq(same.key, room.key); eq(fallback[#fallback].key, room.key)
	local beforeFallback = #fallback
	-- (The host opens it through the one door of every pending conversation, ChatRooms.OpenMatter,
	-- which the game loads before the Arena's files; the real host answers the pane it shows, or
	-- false, where this test's first host answered nothing.)
	CH.WithRooms(w, sp)
	local hosted = CH.Host(sp)
	opened, same = w:As(sp, sp.ns.Arena.OpenChatRoom, fid)
	eq(opened, true); eq(same.key, room.key); eq(hosted.spec.key, room.key)
	eq(#fallback, beforeFallback, "an accepting host needs no fallback event")
	local missing, noRoom = w:As(sp, sp.ns.Arena.OpenChatRoom, "Fdoesnotexist")
	eq(missing, false); eq(noRoom, nil); eq(#fallback, beforeFallback, "an unknown event opens nothing")

	Live(w, cast, fid)
	room = w:As(sp, sp.ns.Arena.ChatRoom, fid)
	eq(room.phase, "live"); eq(room.state, "L"); eq(room.key, "arena:" .. fid, "identity never follows state or title")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	room = w:As(sp, sp.ns.Arena.ChatRoom, fid)
	eq(room.phase, "settling"); eq(room.active, true)
	w:Run(120)
	room = w:As(sp, sp.ns.Arena.ChatRoom, fid)
	eq(room.phase, "complete"); eq(room.active, false)
	eq(room.retainFor, 1800); eq(room.retainUntil, room.completedAt + room.retainFor)
	eq(room.recoverable, true)
	w.clock = room.retainUntil - 1
	eq(w:As(sp, sp.ns.Arena.ChatRoom, fid).recoverable, true)
	w.clock = room.retainUntil
	eq(w:As(sp, sp.ns.Arena.ChatRoom, fid).recoverable, false, "the unpinned room may be pruned after retention")
	W3.NoErrors(w)
end)

-- (The owner's decision, 2026-10-04: every pending conversation opens its own tab on the Chat page,
-- the Olympus window in front, pinned while the matter is open, reopened from the matter's page.
-- Before it a fight's room opened from its page unpinned, under any window in front of Olympus's.)
test("1.2 Arena chat rooms: a fight's room opens through the one pending-conversation door: the window in front; pinned while the fight lives for its fighters and arbiter, unpinned at its end; a spectator's tab is not pinned", function()
	local w, cast = W3.New()
	local hosts = {}
	for _, c in ipairs({ cast.A, cast.arbiter, cast.spectator }) do
		CH.WithRooms(w, c)
		hosts[c] = CH.Host(c)
	end
	local fid = Booked(w, cast)
	local key = "arena:" .. fid
	for _, c in ipairs({ cast.A, cast.arbiter, cast.spectator }) do
		local opened, spec = w:As(c, c.ns.Arena.OpenChatRoom, fid)
		eq(opened, true, c.short); eq(spec.key, key)
	end
	eq(table.concat(hosts[cast.A].calls, ","), ("open %s,pin %s,raise"):format(key, key), "a fighter: his matter, pinned, the window in front")
	eq(table.concat(hosts[cast.arbiter].calls, ","), ("open %s,pin %s,raise"):format(key, key), "the arbiter's too")
	eq(table.concat(hosts[cast.spectator].calls, ","), ("open %s,raise"):format(key), "a spectator watches: no pin")
	-- Live and settling it stays; final, the pin goes (the room stays, retained and removable).
	for _, h in pairs(hosts) do h.calls = {} end
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	for _, h in pairs(hosts) do eq(#h.calls, 0, "nothing while it lives") end
	w:Run(120)
	eq(w:As(cast.A, cast.A.ns.Arena.ChatRoom, fid).active, false, "over")
	eq(table.concat(hosts[cast.A].calls, ","), "unpin " .. key)
	eq(table.concat(hosts[cast.arbiter].calls, ","), "unpin " .. key)
	eq(#hosts[cast.spectator].calls, 0, "nothing of the spectator's to unpin")
	-- Its page opens it again, the window in front; an ended fight is not pinned again.
	hosts[cast.A].calls = {}
	eq((w:As(cast.A, cast.A.ns.Arena.OpenChatRoom, fid)), true)
	eq(table.concat(hosts[cast.A].calls, ","), ("open %s,raise"):format(key))
	W3.NoErrors(w)
end)

test("1.2 Arena chat rooms: private fights name participants only; cards and tournaments use larger event rooms and emit the same lifecycle metadata", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	local changed = {}
	sp.ns.On("ARENA_CHAT_ROOM", function(spec) changed[spec.id] = spec end)

	local fid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(Fights(w, cast.B).Answer(fid, true))
	w:Run(0)
	local duel = w:As(cast.A, cast.A.ns.Arena.ChatRoom, fid)
	eq(duel.access, "participants"); eq(duel.audience, "duel")
	eq(table.concat(duel.participants, ","), table.concat({ cast.A.name, cast.B.name }, ","))
	eq(duel.supportsBets, true); eq(duel.supportsComments, true)

	local cid = assert(w:As(cast.king, cast.king.ns.ArenaFights.Card.New, "Crown Night", w.clock + 3600))
	local tid = assert(W3.M(w, cast.king, "ArenaTourney").New({ title = "Crown Cup", size = 4, tStart = w.clock + 7200 }))
	w:Run(0)
	local card = w:As(sp, sp.ns.Arena.ChatRoom, cid)
	eq(card.key, "arena:" .. cid); eq(card.kind, "event"); eq(card.eventKind, "card")
	eq(card.audience, "event"); eq(card.access, "members"); eq(card.title, "Crown Night"); eq(card.phase, "upcoming")
	local tourney = w:As(sp, sp.ns.Arena.ChatRoom, tid)
	eq(tourney.key, "arena:" .. tid); eq(tourney.kind, "event"); eq(tourney.eventKind, "tourney")
	eq(tourney.audience, "event"); eq(tourney.access, "members"); eq(tourney.title, "Crown Cup"); eq(tourney.phase, "upcoming")
	eq(changed[cid].key, card.key); eq(changed[tid].key, tourney.key)

	-- With nobody checked in, closing registration and drawing cancels the tournament. The event
	-- room is now completed, but remains recoverable for the same retention window as a fight.
	local T = W3.M(w, cast.king, "ArenaTourney")
	assert(T.CloseRegistration(tid))
	w:Run(0)
	local ok, why = T.StartDraw(tid)
	eq(ok, false); eq(why, "few")
	w:Run(0)
	tourney = w:As(sp, sp.ns.Arena.ChatRoom, tid)
	eq(tourney.phase, "complete"); eq(tourney.active, false); eq(tourney.recoverable, true)
	eq(changed[tid].phase, "complete")
	W3.NoErrors(w)
end)

print("ArenaFights and ArenaLedger: the rest")

test("1.2 the fights part: an open slot (O): a fighter signs (AS~J) and is answered O; a debtor D; the wrong category C; the writer books a signed fighter and the fight is announced", function()
	local w, cast = W3.New({ more = { { "debtor", "Wenna Crale" }, { "low", "Parric Stowe", { level = 40 } } } })
	local AF = Fights(w, cast.arbiter)
	local fid = assert(AF.New({ A = cast.A.name }))
	assert(AF.Announce(fid))
	w:Run(0)
	eq(State(w, cast.spectator, fid), "O")
	cast.arbiter.ns.Debts.Blocked = function(name) return name and name:find("Wenna", 1, true) ~= nil end
	eq(Fights(w, cast.B).Sign(fid), true)
	eq(Fights(w, cast.debtor).Sign(fid), true)
	eq(Fights(w, cast.low).Sign(fid), true)
	w:Run(0)
	eq(cast.B.ns.ArenaFights.Find("fights", fid).mySign, "O")
	eq(cast.debtor.ns.ArenaFights.Find("fights", fid).mySign, "D")
	eq(cast.low.ns.ArenaFights.Find("fights", fid).mySign, "C", "not at max level: not in the global category")
	cast.arbiter.ns.Debts.Blocked = nil
	eq(AF.Book(fid, cast.debtor.name), false, "only a signed fighter the writer said yes to")
	assert(AF.Book(fid, cast.B.name))
	w:Run(0)
	local f = cast.spectator.ns.ArenaFights.Find("fights", fid)
	eq(f.st, "A"); eq(f.B.name, cast.B.name); eq(cast.spectator.ns.ArenaFights.Has(f.fl, "o"), false)
	W3.NoErrors(w)
end)

test("1.2 the fights part: the arbiter's word on a fight (the design): linked alts, catchweight, a walkover and a disqualification for the wrong character are unrated; a belt moves only in a public title fight with both fighters in the category", function()
	local w, cast = W3.New()
	local F = cast.arbiter.ns.ArenaFights
	-- (The facts as the arbiter's weigh-in reads them from each fighter's own unit: seen, with the
	-- GUID the game gave it; the review's rule rates nothing else.)
	local function Facts(gk, level, class, race) return { gk = gk, seen = true, level = level, class = class, race = race } end
	local function Fight(extra)
		local f = { fid = "Fx", fl = "pt", arb = cast.arbiter.name, cat = "A", A = { name = cast.A.name, gk = "1a.00000001" },
			B = { name = cast.B.name, gk = "1a.00000002" }, m = "K", facts = { A = Facts("1a.00000001", 60, "WA", 1), B = Facts("1a.00000002", 60, "MA", 4) } }
		for k, v in pairs(extra or {}) do f[k] = v end
		return f
	end
	eq(w:As(cast.arbiter, F.Rated, Fight()), true)
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ m = "W" }))), "walkover")
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ m = "D", code = "char" }))), "char")
	eq(w:As(cast.arbiter, F.Rated, Fight({ m = "D", code = "help" })), true, "a disqualification for outside help counts")
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ facts = { A = Facts("1a.00000001", 60), B = Facts("1a.00000002", 45) } }))), "catchweight")
	eq(w:As(cast.arbiter, F.Rated, Fight({ facts = { A = Facts("1a.00000001", 45), B = Facts("1a.00000002", 41) } })), true, "one bracket")
	-- The weigh-in missing, or a gk other than the one the arbiter saw (a fighter's own word): unrated.
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ facts = { A = Facts("1a.00000001", 60) } }))), "weigh-in")
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ facts = { A = { level = 60, gk = "1a.00000001" }, B = Facts("1a.00000002", 60) } }))), "weigh-in")
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ B = { name = cast.B.name, gk = "1a.00000009" } }))), "weigh-in")
	cast.arbiter.ns.Alts.Person = function(name) return "one player" end
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight())), "alts")
	cast.arbiter.ns.Alts.Person = nil
	eq(select(2, w:As(cast.arbiter, F.Rated, Fight({ B = { name = cast.B.name } }))), "gk", "no GUID: no ledger entry")
	eq(w:As(cast.arbiter, F.Eligible, Fight()), true)
	eq(w:As(cast.arbiter, F.Eligible, Fight({ cat = "CMA" })), false, "a warrior in the mages' category")
	eq(w:As(cast.arbiter, F.Eligible, Fight({ facts = { A = Facts("1a.00000001", 59), B = Facts("1a.00000002", 60) } })), false)
	W3.NoErrors(w)
end)

test("1.2 the fights part: a season word (AH) from the King or a public arbiter: 4 to 16 weeks, never starting before the last one's end less 7 days; a new season closes the last one into the Hall", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local B = sp.ns.Arena.B36
	local WEEK = 7 * 86400
	local function Word(from, n, start, weeks, t)
		w:As(sp, function()
			sp.ns.Arena.Inject("CHANNEL", from, "AH~L1~" .. table.concat({ B(n), B(start), B(start + weeks * WEEK), B(6), B(4), B(0), B(t or w.clock) }, "~"))
		end)
	end
	Word(N.bettor2, 1, w.clock - 86400, 8)
	eq(w:As(sp, LG.Season).by, nil, "not a public arbiter: the default season")
	Word(N.arbiter, 1, w.clock - 86400, 2)
	Word(N.arbiter, 1, w.clock - 86400, 20)
	eq(w:As(sp, LG.Season).by, nil, "2 or 20 weeks: refused")
	Word(N.arbiter, 1, w.clock - 86400, 8)
	local s1 = w:As(sp, LG.Season)
	eq(s1.n, 1); eq(s1.by, cast.arbiter.name); eq(s1.vac, 6)
	-- Entries of season 1, then season 2 too early, then in its time.
	w:As(sp, LG.Keep, Entry(1, "3e8.00000001", "3e8.00000002", w.clock - 600), "L", "clerk")
	Word(N.king, 2, w.clock, 8)
	eq(w:As(sp, LG.Season).n, 1, "starts before season 1's end less a week: refused")
	Word(N.king, 2, s1.stop - 3 * 86400, 8)
	eq(w:As(sp, LG.Season).n, 2)
	local hall = w:As(sp, LG.Hall, 1)
	eq(type(hall), "table", "season 1 in the Hall")
	eq(hall.top.A[1].gk, "3e8.00000001")
	W3.NoErrors(w)
end)

test("1.2 the fights part: single asks (AQ, by whisper): a late client asks a fight's writer for it (AF, and AE once final) and a fighter for his profile (AP); three answers a minute at most", function()
	local w, cast = W3.New({ more = { { "late", "Wenna Crale" } } })
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	w:Run(30)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(125)
	eq(State(w, cast.arbiter, fid), "F")
	-- The late one: nothing of it (it logged in after); it asks.
	local late = cast.late
	late.ns.ArenaFights.Find("fights", fid)
	W3.Companion(w, late)
	local LG = Ledger(w, late)
	LG.Ask("F", cast.arbiter.name, fid)
	w:Run(0)
	eq(State(w, late, fid), "F")
	eq(#w:As(late, late.ns.ArenaLedger.Entries), 1, "the entry with it (asked, so taken by whisper)")
	-- A profile.
	w:As(late, function() late.ns.ArenaLedger.Ask("P", cast.A.name, late.ns.Arena.GK(cast.A.guid)) end)
	w:Run(0)
	eq(#w:Sent{ from = cast.A, type = "AP", to = late.name }, 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part: a direct fight with one duel line missing ten minutes is disputed (the debts' rule then applies); nothing settles it by one word", function()
	local w, cast = W3.New()
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(Fights(w, cast.B).Answer(oid, true))
	w:Run(0)
	W3.Duel(w, { cast.A }, cast.A, cast.B)
	w:Run(cast.A.ns.ArenaFights.DIRECT_WAIT + 2)
	local f = cast.A.ns.ArenaFights.Find("fights", oid)
	eq(f.st, "L"); eq(f.code, "disputed")
	eq(f.w, nil, "no result on one word")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the King's screen shows a promoter's own tournament or Fight Night title only when the King set it (the design); a public arbiter's typed title shows as the plain word in the events list and the bracket view", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	local kt = assert(W3.M(w, cast.king, "ArenaTourney").New({ title = "Spring Cup", size = 4, tStart = w.clock + 7200 }))
	local at = assert(W3.M(w, cast.arbiter, "ArenaTourney").New({ title = "Words Of My Choosing", size = 4, tStart = w.clock + 7300 }))
	local ac = assert(w:As(cast.arbiter, cast.arbiter.ns.ArenaFights.Card.New, "Other Words", w.clock + 3600))
	w:Run(0)
	local TW = sp.ns.L.ARENA_TOURNEY
	eq(w:As(sp, sp.ns.ArenaTourney.ScreenTitle, kt), "Spring Cup")
	eq(w:As(sp, sp.ns.ArenaTourney.ScreenTitle, at), TW)
	eq(w:As(sp, sp.ns.ArenaTourney.View, at).screenTitle, TW)
	eq(w:As(sp, sp.ns.ArenaTourney.View, at).title, "Words Of My Choosing", "the promoter's own view keeps it")
	local titles = {}
	for _, e in ipairs(w:As(sp, sp.ns.ArenaFights.Events, {})) do titles[e.id] = e.title end
	eq(titles[kt], "Spring Cup"); eq(titles[at], TW)
	eq(titles[ac] ~= "Other Words", true, "a card of a public arbiter: its number, not his words")
	W3.NoErrors(w)
end)

test("1.2.0 the fights part: no challenge spam: one open challenge per challenger (for a minute), none for a minute after a no, and the challenge sound only for his first", function()
	local w, cast = W3.New()
	local A, B = Fights(w, cast.A), Fights(w, cast.B)
	local asked, played = 0, 0
	cast.B.ns.On("ARENA_CHALLENGE", function() asked = asked + 1 end)
	cast.B.globals.SOUNDKIT = { READY_CHECK = 8960 }
	cast.B.globals.PlaySound = function() played = played + 1; return true end
	local first = assert(A.Challenge(cast.B.name, { bo = 1 }))
	w:Run(0); eq(asked, 1); eq(played, 1, "the first challenge sounds")
	eq(cast.B.ns.ArenaHome.ChallengeFrame():IsShown(), true)
	w:Run(5)
	A.Challenge(cast.B.name, { bo = 3 })
	w:Run(0); eq(asked, 1, "a second one while his first is open is not taken")
	assert(B.Answer(first, false))
	w:Run(10)
	A.Challenge(cast.B.name, { bo = 1 })
	w:Run(0); eq(asked, 1, "nor one within a minute of our no")
	w:Run(60)
	assert(A.Challenge(cast.B.name, { bo = 1 }))
	w:Run(0); eq(asked, 2, "a minute later: taken")
	eq(played, 1, "shown again, but the sound only once per challenger")
	w:Run(61)
	assert(A.Challenge(cast.B.name, { bo = 1 }))
	w:Run(0); eq(asked, 3, "one left unanswered for a minute no longer holds him off")
	W3.NoErrors(w)
end)

test("1.2.0 the fights part: the writer's repeated calls (AC C) raise one alert per 20 seconds, not one per whisper", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local writer = cast.A.ns.ArenaFights.Find("fights", fid).writer
	local called = 0
	cast.A.ns.On("ARENA_CALLED", function() called = called + 1 end)
	local function Call() w:As(cast.A, function() cast.A.ns.Arena.Inject("WHISPER", writer, "AC~L1~" .. fid .. "~C~1~0~0~0") end) end
	Call(); eq(called, 1)
	w:Run(4); Call(); w:Run(4); Call()
	eq(called, 1, "repeats within 20 s: no new alert")
	w:Run(21); Call()
	eq(called, 2, "a call 20 s later alerts again")
	W3.NoErrors(w)
end)
