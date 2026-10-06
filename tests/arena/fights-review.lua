-- 1.2, the fights part's review (its 1.2 branch): one regression test per finding the two reviews made of
-- the fights, the ledger, the tournaments and the honours' words, on the test world. Each fails on
-- the branch as it was built (9ff9aee) and passes with its fix (ported onto the canonical markets:
-- the fights' own sheets are real ones, a bank listed, WithBank). the money part's money side is stood in
-- where a test needs its keys and signatures (W3.Money, its contract). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
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
	local o = { A = cast.A.name, B = cast.B.name, bo = 1 }
	for k, v in pairs(opts or {}) do o[k] = v end
	local fid = assert(AF.New(o))
	assert(AF.Announce(fid))
	w:Run(0)
	Fights(w, cast.A).Accept(fid)
	Fights(w, cast.B).Accept(fid)
	w:Run(0)
	return fid
end
-- Called, ready (their own positions), belled, live; the arbiter holds each fighter's unit
-- (opts.sees = false: none, no weigh-in).
local function Live(w, cast, fid, opts)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 100, 120)
	if not (opts and opts.sees == false) then W3.Sees(cast.arbiter, { [cast.A] = true, [cast.B] = true }) end
	local AF = Fights(w, cast.arbiter)
	assert(AF.Call(fid))
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	Fights(w, cast.B).Here(fid)
	w:Run(1)
	assert(AF.Bell(fid))
	w:Run(0)
	-- (Its lock: the last call's, or its open sheet's, WithBank.)
	local f = AF.Find("fights", fid)
	w:Run(math.max(0, f.lockAt - w.clock))
	eq(State(w, cast.arbiter, fid), "L")
end
-- A world with a bank the King listed: a public fight's writer opens its real markets sheet
-- (Markets.Open through ArenaFights, as market-reachability.lua's routes do).
local function WithBank(opts)
	opts = opts or {}
	local more = { { "bank", N.bank } }
	for _, e in ipairs(opts.more or {}) do more[#more + 1] = e end
	opts.more = more
	local w, cast = W3.New(opts)
	assert(cast.king.Roles.SetBanks({ N.bank }))
	w:Run(0)
	return w, cast
end
-- A challenge agreed (AS X, Y): its oid.
local function Agreed(w, cast, opts)
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, opts))
	w:Run(0)
	assert(Fights(w, cast.B).Answer(oid, true))
	w:Run(0)
	return oid
end

print("the fights part review: the money (blocker and majors)")

test("1.2 the fights part review: a rehearsal's (T) staked fights open, settle and record their stakes in T (the money part's Mode: a missing mode is L), never as live obligations", function()
	local w, cast = W3.New({ live = false })
	local money = {}
	for _, c in ipairs({ cast.A, cast.B, cast.arbiter }) do money[c] = W3.Money(w, c) end
	-- Held by an arbiter.
	local oid = Agreed(w, cast, { how = "a", arbiter = cast.arbiter.name, stake = 10000, cur = "g" })
	assert(Fights(w, cast.arbiter).Judge(oid, true))
	w:Run(0)
	local open = money[cast.arbiter].open[1]
	eq(open ~= nil, true, "the arbiter's book opened")
	eq(open.mode, "T", "a rehearsal's book")
	local fid = open.id
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.mode, "T")
	for _, c in ipairs({ cast.A, cast.B }) do
		eq(money[c].open[1] and money[c].open[1].mode, "T", c.short .. "'s side of the book, in T")
	end
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(f.st, "R")
	w:Run(cast.arbiter.ns.ArenaFights.GRACE_HELD + 1)
	eq(f.st, "F")
	eq(money[cast.arbiter].result[1] and money[cast.arbiter].result[1].mode, "T", "paid out in T")
	eq(money[cast.arbiter].result[1].side, "A")
	-- Direct.
	w:Run(5)
	local oid2 = Agreed(w, cast, { how = "d", stake = 10000, cur = "g" })
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	eq(State(w, cast.A, oid2), "F"); eq(State(w, cast.B, oid2), "F")
	for _, c in ipairs({ cast.A, cast.B }) do
		local d = money[c].direct[1]
		eq(d ~= nil, true, c.short .. " records it")
		eq(d.mode, "T", c.short .. ": a rehearsal's")
	end
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a staked direct fight settles on both fighters' clients with its mode, the loser's IOU and his signed result; the opponent's fight carries the agreed stake", function()
	local w, cast = W3.New()
	local money = { [cast.A] = W3.Money(w, cast.A), [cast.B] = W3.Money(w, cast.B) }
	local oid = Agreed(w, cast, { how = "d", stake = 20000, cur = "g" })
	local cA = cast.A.ns.ArenaFights.challenges[oid]
	local cB = cast.B.ns.ArenaFights.challenges[oid]
	eq(cA.state, "set")
	eq(type(cA.theirIou), "string", "the opponent's IOU kept (AS~Y)")
	eq(type(cB.iou), "string", "the challenger's IOU kept (AS~X)"); eq(cB.salt, cA.salt, "one salt")
	local fA, fB = cast.A.ns.ArenaFights.Find("fights", oid), cast.B.ns.ArenaFights.Find("fights", oid)
	eq(fA.stake, 20000); eq(fB.stake, 20000, "the opponent's copy has the stake")
	-- B wins.
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	eq(State(w, cast.A, oid), "F"); eq(State(w, cast.B, oid), "F")
	for _, c in ipairs({ cast.A, cast.B }) do
		local d = money[c].direct[1]
		eq(d ~= nil and #money[c].direct, 1, c.short .. ": Stakes.Direct once")
		eq(d.mode, "L"); eq(d.copper, 20000); eq(d.loser, cast.A.name); eq(d.winner, cast.B.name)
	end
	-- The winner's proof: A's IOU (his AS~X) and A's signed result (his AW).
	local d = money[cast.B].direct[1]
	local commit, sig = cA.myIou:match("^(%w+)%.(%w+)$")
	eq(d.iou and d.iou.commit, commit); eq(d.iou.sig, sig)
	eq(d.result and d.result.fid, oid); eq(d.result.round, 1)
	local expected = w:As(cast.A, cast.A.ns.Debts.SignResult, oid, 1, fB.B.gk, fB.A.gk)
	eq(d.result.sig, expected, "the loser's own signature")
	-- Kept on the fight record (a reload keeps the proof).
	eq(fB.sigs[1].A, expected); eq(fB.ious.A, cA.myIou)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a staked direct challenge: the stake in whole silver, a token and an IOU the opponent checks (a forged IOU, a token no bank signed: refused), the challenger's check of the answer's IOU", function()
	local w, cast = W3.New()
	W3.Money(w, cast.A)
	W3.Money(w, cast.B)
	local AF = Fights(w, cast.A)
	local oid, why = AF.Challenge(cast.B.name, { stake = 12345, how = "d", cur = "g" })
	eq(oid, nil); eq(why, "silver")
	-- No token: nothing goes.
	W3.Money(w, cast.A, { token = false })
	oid, why = AF.Challenge(cast.B.name, { stake = 10000, how = "d", cur = "g" })
	eq(oid, nil); eq(why, "token")
	eq(#w:Sent{ from = cast.A, type = "AS" }, 0)
	W3.Money(w, cast.A)
	-- A forged IOU (another commitment than the stake's): the opponent refuses with i.
	oid = assert(AF.Challenge(cast.B.name, { stake = 10000, how = "d", cur = "g" }))
	w:Run(0)
	local cB = cast.B.ns.ArenaFights.challenges[oid]
	cB.iou = "0000000000000000." .. cB.iou:match("%.(%w+)$")
	local ok, code = Fights(w, cast.B).Answer(oid, true)
	eq(ok, false); eq(code, "i")
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[oid].state, "no"); eq(cast.A.ns.ArenaFights.challenges[oid].why, "i")
	eq(cast.A.ns.ArenaFights.Find("fights", oid), nil)
	-- A token no bank signed: t.
	w:Run(5)
	oid = assert(AF.Challenge(cast.B.name, { stake = 10000, how = "d", cur = "g" }))
	w:Run(0)
	cast.B.ns.ArenaFights.challenges[oid].token = "Nobody Here-Emberfall.5.1.1.1.X.Y"
	ok, code = Fights(w, cast.B).Answer(oid, true)
	eq(ok, false); eq(code, "t")
	-- The answer's IOU forged on the way: the challenger makes no fight.
	w:Run(5)
	oid = assert(AF.Challenge(cast.B.name, { stake = 10000, how = "d", cur = "g" }))
	w:Run(0)
	local iou = cast.B.ns.Debts.Iou
	cast.B.ns.Debts.Iou = function(...) local t = iou(...) t.wire = "1111111111111111." .. t.sig return t end
	assert(Fights(w, cast.B).Answer(oid, true))
	w:Run(0)
	cast.B.ns.Debts.Iou = iou
	eq(cast.A.ns.ArenaFights.challenges[oid].state, "no"); eq(cast.A.ns.ArenaFights.challenges[oid].why, "i")
	eq(cast.A.ns.ArenaFights.Find("fights", oid), nil, "no fight on a bad IOU")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the currency, the live switch and the caps (the design): the opponent refuses a stake in another currency; an answer keeps the challenge's mode; an arbiter with no cap, a Judge without the money side: refused", function()
	local w, cast = W3.New()
	for _, c in ipairs({ cast.A, cast.B, cast.arbiter }) do W3.Money(w, c) end
	-- The opponent's realm says glory points (its King's word, as he holds it): a gold stake is no.
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { stake = 10000, how = "d", cur = "g" }))
	local cur = cast.B.ns.ArenaRoles.Currency
	cast.B.ns.ArenaRoles.Currency = function() return "p" end
	w:Run(0)
	cast.B.ns.ArenaRoles.Currency = cur
	eq(cast.A.ns.ArenaFights.challenges[oid].state, "no"); eq(cast.A.ns.ArenaFights.challenges[oid].why, "c")
	-- An L challenge answered where the live switch is off (its mode, not the answerer's NewMode).
	w:Run(5)
	oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	local live = cast.B.ns.ArenaRoles.Live
	cast.B.ns.ArenaRoles.Live = function() return false end
	local ok, why = Fights(w, cast.B).Answer(oid, true)
	cast.B.ns.ArenaRoles.Live = live
	eq(ok, false); eq(why, "live")
	eq(cast.B.ns.ArenaFights.challenges[oid].state, "asked", "unchanged")
	-- An arbiter-held stake with an arbiter who has no cap (not an arbiter at all): refused.
	local can = W3.M(w, cast.A, "Arena").Can
	ok, why = can("fights.challenge", cast.B.name, { stake = 10000, how = "a", arbiter = cast.spectator.name, cur = "g" })
	eq(ok, false); eq(why, "arbiter-cap")
	-- A Judge whose money side is missing refuses the stake (no book, no unchecked stake).
	w:Run(5)
	oid = Agreed(w, cast, { how = "a", arbiter = cast.arbiter.name, stake = 10000, cur = "g" })
	cast.arbiter.ns.Stakes.Open = nil
	ok, why = Fights(w, cast.arbiter).Judge(oid, true)
	eq(ok, false); eq(why, "money")
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[oid].state, "arbiter-no")
	W3.NoErrors(w)
end)

print("the fights part review: who decides a fight")

test("1.2 the fights part review: a fighter and two friends can't settle a live round: reports decide only after RESULT_WAIT with no line of the arbiter's, and his own line overrules them in the grace (src L, disputed)", function()
	local w, cast = W3.New({ more = { { "x", "Parric Stowe" }, { "y", "Wenna Crale" } } })
	local chronicle = {}
	rawset(cast.arbiter.ns, "Chronicle", { Add = function(kind, by, what) chronicle[#chronicle + 1] = what end })
	local function Fake(fid)
		local body = table.concat({ fid, "1", "K", cast.A.short, cast.B.short, "0", "0" }, "~")
		for _, c in ipairs({ cast.A, cast.x, cast.y }) do
			w:As(c, function() c.ns.Arena.Send("AW", "L", body, { to = cast.arbiter.name, urgent = true }) end)
		end
	end
	-- Fake reports at the bell, the real duel 5 s later: the arbiter's own line decides.
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	Fake(fid)
	w:Run(5)
	eq(f.st, "L", "not settled by the reports")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(1)
	eq(f.w, "B"); eq(f.rounds[1].src, "L")
	-- Fake reports, and the duel only after the wait: W at first, then the arbiter's line overrules.
	fid = Booked(w, cast)
	Live(w, cast, fid)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	Fake(fid)
	w:Run(cast.arbiter.ns.ArenaFights.RESULT_WAIT + 2)
	eq(f.st, "R"); eq(f.w, "A"); eq(f.rounds[1].src, "W")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(1)
	eq(f.st, "R"); eq(f.w, "B", "his own line"); eq(f.rounds[1].src, "L"); eq(f.code, "disputed")
	eq(cast.spectator.ns.ArenaFights.Find("fights", fid).w, "B", "every client")
	assert(chronicle[#chronicle] and chronicle[#chronicle]:find("disputed", 1, true), "the Chronicle has it")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a direct best of 3 goes on after its first round (the next duel is the next round) and ends 2:0 on both clients", function()
	local w, cast = W3.New()
	local oid = Agreed(w, cast, { bo = 3 })
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	local fa, fb = cast.A.ns.ArenaFights.Find("fights", oid), cast.B.ns.ArenaFights.Find("fights", oid)
	eq(fa.st, "B"); eq(fa.sc[1], 1)
	w:Run(90)
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(fa.round, 2); eq(fb.round, 2)
	eq(fa.st, "F"); eq(fb.st, "F"); eq(fa.sc[1], 2); eq(fb.sc[1], 2); eq(fb.w, "A")
	W3.NoErrors(w)
end)

test("free duel identity: an explicitly different realm's result cannot finish our challenge", function()
	local w, cast = W3.New()
	local oid = Agreed(w, cast, { bo = 1 })
	local text = W3.DUEL_KO:format(cast.A.short .. "-Anotherrealm", cast.B.short .. "-Anotherrealm")
	w:System({ cast.A, cast.B }, text)
	w:Run(0)
	eq(cast.A.ns.ArenaFights.Find("fights", oid).st, "S")
	eq(cast.B.ns.ArenaFights.Find("fights", oid).st, "S")
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(cast.A.ns.ArenaFights.Find("fights", oid).st, "F")
	eq(cast.B.ns.ArenaFights.Find("fights", oid).st, "F")
	W3.NoErrors(w)
end)

test("free duel qualification: native local completion and both reports retain guild GUID and levels once", function()
	local w, cast = W3.New({ world = { compliance = "shipped" } })
	cast.A.target, cast.B.target = cast.B.name, cast.A.name
	cast.A.level, cast.B.level = 40, 47
	cast.B.guild = "Olympus Other"
	local oid = Agreed(w, cast, { bo = 1 })
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(#Fights(w, cast.A).Qualification(), 0, "a nearby system line alone is not participation")
	w:Fire(cast.A, "DUEL_FINISHED")
	w:Fire(cast.B, "DUEL_FINISHED")
	local qa, qb = Fights(w, cast.A).Qualification(), Fights(w, cast.B).Qualification()
	eq(#qa, 1); eq(#qb, 1)
	eq(qa[1].fid, oid); eq(qa[1].levelA, 40); eq(qa[1].levelB, 47)
	eq(qa[1].guildB, "Olympus Other"); eq(qa[1].A, cast.A.ns.Arena.GK(cast.A.guid))
	eq(qa[1].w, "A"); eq(qb[1].mine, "B")
	eq(qa.pointsTenths, 17); eq(qa.points, 1.7); eq(qb.pointsTenths, 0, "losing earns no qualifying points")
	local ownStore = w:As(cast.A, cast.A.ns.Arena.Store, "L")
	local otherStore = w:As(cast.spectator, cast.spectator.ns.Arena.Store, "L")
	otherStore.duelQualification = ownStore.duelQualification
	eq(Fights(w, cast.spectator).Qualification().pointsTenths, 0, "same account's other character does not inherit points")
	w:Fire(cast.A, "DUEL_FINISHED")
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(#Fights(w, cast.A).Qualification(), 1, "duplicate finish and line do not count again")
	eq(#Ledger(w, cast.A).Entries(), 0, "qualification does not create an arbiter's ranking")
	W3.NoErrors(w)
end)

test("free duel qualification: one physical native completion across challenges; level policy bounded and order independent", function()
	for _, row in ipairs({ { 40, 40, 10 }, { 40, 43, 13 }, { 43, 40, 7 }, { 40, 60, 20 }, { 60, 40, 0 } }) do
		local w, cast = W3.New()
		cast.A.target, cast.B.target = cast.B.name, cast.A.name
		cast.A.level, cast.B.level = row[1], row[2]
		Agreed(w, cast, { bo = 1 })
		w:Run(4)
		Agreed(w, cast, { bo = 1 })
		w:Fire(cast.A, "DUEL_FINISHED")
		W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
		w:Run(0)
		local q = Fights(w, cast.A).Qualification()
		eq(#q, 1, "one duel is not two challenges' points")
		eq(q.pointsTenths, row[3]); eq(q.wins, 1)
		W3.NoErrors(w)
	end
end)

test("free duel identity: a rehearsal report cannot confirm a live challenge and methods must agree", function()
	local w, cast = W3.New()
	local oid = Agreed(w, cast, { bo = 1 })
	local body = table.concat({ oid, "1", "K", cast.A.short, cast.B.short, cast.A.ns.Arena.B36(w.clock), "0" }, "~")
	assert(w:As(cast.B, cast.B.ns.Arena.Send, "AW", "T", body, { to = cast.A.name, urgent = true }))
	w:Run(0)
	W3.Duel(w, { cast.A }, cast.A, cast.B)
	w:Run(0)
	eq(cast.A.ns.ArenaFights.Find("fights", oid).st, "L", "no cross-mode confirmation")
	W3.Duel(w, { cast.B }, cast.A, cast.B, true)
	w:Run(0)
	local f = cast.A.ns.ArenaFights.Find("fights", oid)
	eq(f.st, "L"); eq(f.code, "disputed", "knockout and fleeing are different outcomes")
	W3.NoErrors(w)
end)

test("free duel qualification: retained evidence cap folds points and replay boundary survives module reload", function()
	local w, cast = W3.New()
	cast.A.target, cast.B.target = cast.B.name, cast.A.name
	cast.A.level, cast.B.level = 40, 43
	cast.A.ns.ArenaFights.KEEP = 1
	for _ = 1, 2 do
		Agreed(w, cast, { bo = 1 })
		W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
		w:Run(0)
		w:Fire(cast.A, "DUEL_FINISHED")
		w:Run(4)
	end
	local q = Fights(w, cast.A).Qualification()
	eq(#q, 1); eq(q.pointsTenths, 26); eq(q.wins, 2)
	w:As(cast.A, function()
		assert(loadfile(H.ADDON_DIR .. "ArenaFights.lua"))("Olympus", cast.A.ns)
	end)
	q = Fights(w, cast.A).Qualification()
	eq(#q, 1); eq(q.pointsTenths, 26); eq(q.wins, 2)
	W3.NoErrors(w)
end)

test("free duel identity: agreement on the winner alone does not settle a different knockout and fled outcome", function()
	local w, cast = W3.New()
	local oid = Agreed(w, cast, { bo = 1 })
	W3.Duel(w, { cast.A }, cast.A, cast.B)
	W3.Duel(w, { cast.B }, cast.A, cast.B, true)
	w:Run(0)
	local f = cast.A.ns.ArenaFights.Find("fights", oid)
	eq(f.st, "L"); eq(f.code, "disputed")
	W3.NoErrors(w)
end)

test("free duel qualification: missing membership identity levels bilateral report or native event gives no evidence", function()
	for _, kind in ipairs({ "guild", "identity", "level", "report", "native", "stale", "mismatch" }) do
		local w, cast = W3.New()
		cast.A.target, cast.B.target = cast.B.name, cast.A.name
		Agreed(w, cast, { bo = 1 })
		if kind == "guild" then cast.B.guild = "Ordinary Guild" end
		if kind == "identity" then cast.A.target = cast.spectator.name end
		if kind == "level" then cast.B.level = 0 end
		W3.Duel(w, { cast.A }, cast.A, cast.B)
		if kind ~= "report" then W3.Duel(w, { cast.B }, cast.A, cast.B, kind == "mismatch") end
		w:Run(0)
		if kind == "stale" then w:Run(3) end
		if kind ~= "native" then w:Fire(cast.A, "DUEL_FINISHED") end
		eq(#Fights(w, cast.A).Qualification(), 0, kind)
		W3.NoErrors(w)
	end
end)

test("1.2 the fights part review: nobody plants a direct fight in another player's saved data: a direct AF without our agreed challenge, a result over AF or AR, all refused", function()
	local w, cast = W3.New({ more = { { "x", "Parric Stowe" } } })
	local x, B = cast.x, cast.B
	local fid = w:As(x, function() return x.ns.Arena.NewId("F", function() return false end) end)
	local body = table.concat({ fid, "F", "d", "1", "A", "-", "-", x.short, "-", B.short, "-", "0", "0", "0", "1", "1:0", "A", "K", "0" }, "~")
	w:As(x, function() x.ns.Arena.Send("AF", "L", body, { to = B.name, urgent = true }) end)
	w:Run(0)
	eq(B.ns.ArenaFights.Find("fights", fid), nil, "no challenge agreed: refused")
	local store = w:As(B, function() return B.ns.Arena.Store("L") end)
	eq(store.myFights and store.myFights[B.name] and #store.myFights[B.name] or 0, 0, "nothing in his own history")
	-- A real direct fight: its writer's result words are never taken (each side's own lines decide).
	local oid = Agreed(w, cast, { bo = 1 })
	local fb = B.ns.ArenaFights.Find("fights", oid)
	eq(fb.st, "S")
	local forged = table.concat({ oid, "F", "d", "1", "A", "-", "-", cast.A.short, "-", B.short, "-", "0", "0", "0", "1", "1:0", "A", "K", "0" }, "~")
	w:As(cast.A, function() cast.A.ns.Arena.Send("AF", "L", forged, { to = B.name, urgent = true }) end)
	w:As(cast.A, function() cast.A.ns.Arena.Send("AR", "L", table.concat({ oid, "1", "1:0", "A", "K", "0", "0", "F", "1", "0", "-" }, "~"), { to = B.name, urgent = true }) end)
	w:Run(0)
	eq(fb.st, "S", "no result by a word"); eq(fb.w, nil)
	-- His walkover to us (he concedes) is taken; a void before any round is too.
	local concede = table.concat({ oid, "W", "d", "1", "A", "-", "-", cast.A.short, "-", B.short, "-", "0", "0", "0", "1", "0:0", "B", "W", "0" }, "~")
	w:As(cast.A, function() cast.A.ns.Arena.Send("AF", "L", concede, { to = B.name, urgent = true }) end)
	w:Run(0)
	eq(fb.st, "W"); eq(fb.w, "B")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a rated entry never carries a GUID the arbiter did not see: a fighter naming another's gk in his AC is weighed in by his own unit; with no unit seen, unrated", function()
	local w, cast = W3.New({ more = { { "x", "Parric Stowe" } } })
	for _, c in ipairs({ cast.arbiter, cast.spectator }) do W3.Companion(w, c) end
	local x, B = cast.x, cast.B
	local gkX = w:As(x, function() return x.ns.ArenaProfile.MyGk() end)
	local gkB = w:As(B, function() return B.ns.ArenaProfile.MyGk() end)
	local function Spoofed()
		local AF = Fights(w, cast.arbiter)
		local fid = assert(AF.New({ A = cast.A.name, B = B.name, bo = 1 }))
		assert(AF.Announce(fid))
		w:Run(0)
		Fights(w, cast.A).Accept(fid)
		w:As(B, function() B.ns.Arena.Send("AC", "L", fid .. "~A~0~0~0~0~" .. gkX, { to = cast.arbiter.name, urgent = true }) end)
		w:Run(2)
		return fid
	end
	-- The arbiter holds B's own unit (he targets one fighter, the design): its GUID replaces the one
	-- B's word gave.
	cast.arbiter.target = B.name
	local fid = Spoofed()
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(200)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.st, "F"); eq(f.B.gk, gkB, "his own unit's GUID")
	assert(f.entry and not f.entry:find(gkX, 1, true), "the victim's gk is in no entry")
	-- No unit of either seen (no weigh-in): unrated, no entry at all.
	w:Run(10)
	cast.arbiter.target = nil
	cast.arbiter.globals.UnitTokenFromGUID, cast.arbiter.globals.CheckInteractDistance = nil, nil
	fid = Spoofed()
	Live(w, cast, fid, { sees = false })
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(200)
	f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(f.st, "F"); eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "r"), false, "unrated: no weigh-in")
	eq(f.entry, nil)
	W3.NoErrors(w)
end)

print("the fights part review: the ledger")

test("1.2 the fights part review: an AE only from the fight's own arbiter: a listed arbiter's forged entry for a fight held here is refused, and the real one kept; for a fight not held here an arbiter whose id it is not, refused; the real arbiter's replaces a first-come", function()
	local w, cast = W3.New({ more = { { "x", "Parric Stowe" } } })
	local x = cast.x
	assert(w:As(cast.king, function() return cast.king.ns.ArenaRoles.SetArbiters({ { name = x.name, cap = 100 } }) end))
	w:Run(0)
	for _, c in ipairs({ cast.arbiter, cast.spectator, x }) do W3.Companion(w, c) end
	local sp = cast.spectator
	local LG = sp.ns.ArenaLedger
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(2)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local e = { season = 1, fid = fid, t = w.clock, cat = "A", bo = 1, gkA = f.A.gk, A = f.A.name, gkB = f.B.gk, B = f.B.name, sc = "0:1", w = "B", m = "K",
		dur = 40, gkArb = w:As(x, function() return x.ns.ArenaProfile.MyGk() end), fl = "pr" }
	w:As(x, function() x.ns.Arena.Send("AE", "L", x.ns.ArenaLedger.Encode(e), { must = true }) end)
	w:Run(2)
	eq(LG.Stats().refused["not-arbiter"], 1, "not this fight's arbiter")
	w:Run(200)
	local book = w:As(sp, LG.Book, "L", 1)
	eq(book.list[fid] and book.list[fid].w, "A", "the real entry")
	-- A fight not held here: a listed (not public) arbiter's entry for an id that is not his: refused.
	local other = { season = 1, fid = "F9zz" .. sp.ns.Arena.Hash36(N.arbiter:lower(), 2), t = w.clock - 10, cat = "A", bo = 1, gkA = "3e8.00000001", A = "Ab Cd-Emberfall",
		gkB = "3e8.00000002", B = "Ef Gh-Emberfall", sc = "1:0", w = "A", m = "K", dur = 40, gkArb = "3e8.00000009", fl = "pr" }
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", x.name, "AE~L1~" .. LG.Encode(other)) end)
	eq(book.list[other.fid], nil)
	-- A public arbiter's entry kept first for a fight not heard yet (a draft of the arbiter's): once
	-- the fight is held here, its own arbiter's entry replaces it.
	local fid2 = assert(Fights(w, cast.arbiter).New({ A = cast.A.name, B = cast.B.name, bo = 1 }))
	local forged = {}
	for k, v in pairs(other) do forged[k] = v end
	forged.fid, forged.w, forged.sc = fid2, "B", "0:1"
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.king, "AE~L1~" .. LG.Encode(forged)) end)
	eq(book.list[fid2] and book.list[fid2].w, "B", "first come")
	assert(Fights(w, cast.arbiter).Announce(fid2))
	w:Run(0)
	eq(sp.ns.ArenaFights.Find("fights", fid2).arb, cast.arbiter.name)
	local real = {}
	for k, v in pairs(forged) do real[k] = v end
	real.w, real.sc, real.gkArb = "A", "1:0", w:As(cast.arbiter, function() return cast.arbiter.ns.ArenaProfile.MyGk() end)
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. LG.Encode(real)) end)
	eq(book.list[fid2].w, "A", "the fight's own arbiter's replaces it")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the launch season (no season word ever said) goes into the Hall when the first word opens season 2", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local B = sp.ns.Arena.B36
	local s1 = w:As(sp, LG.Season)
	eq(s1, LG.DEFAULT)
	w.clock = s1.start + 100
	w:As(sp, LG.Keep, { season = 1, fid = "F1aa", t = w.clock - 50, cat = "A", bo = 1, gkA = "3e8.00000001", A = "Ab Cd-Emberfall", gkB = "3e8.00000002",
		B = "Ef Gh-Emberfall", sc = "1:0", w = "A", m = "K", dur = 40, gkArb = "3e8.00000009", fl = "rp" }, "L", "clerk")
	w.clock = s1.stop - 86400
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.king, "AH~L1~" .. table.concat({ B(2), B(s1.stop), B(s1.stop + 8 * 7 * 86400), B(6), B(4), B(0), B(w.clock) }, "~")) end)
	eq(w:As(sp, LG.Season).n, 2)
	local hall = w:As(sp, LG.Hall, 1)
	eq(hall ~= nil, true, "season 1 in the Hall")
	eq(hall.n, 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: AQ~F answers a private fight only to its fighters, arbiter and promoter", function()
	local w, cast = W3.New()
	local oid = Agreed(w, cast, { how = "a", arbiter = cast.arbiter.name, bo = 1 })
	assert(Fights(w, cast.arbiter).Judge(oid, true))
	w:Run(0)
	local fid = cast.A.ns.ArenaFights.challenges[oid].fid
	local sp = cast.spectator
	w:As(sp, function() sp.ns.ArenaLedger.Ask("F", cast.arbiter.name, fid) end)
	w:Run(0)
	eq(sp.ns.ArenaFights.Find("fights", fid), nil, "a spectator gets nothing")
	eq(cast.arbiter.ns.ArenaLedger.Stats().refused.private, 1)
	-- A fighter who lost his copy asks: answered.
	local B = cast.B
	local store = w:As(B, function() return B.ns.Arena.Store("L") end)
	store.fights[fid] = nil
	w:Run(11)
	w:As(B, function() B.ns.ArenaLedger.Ask("F", cast.arbiter.name, fid) end)
	w:Run(0)
	eq(B.ns.ArenaFights.Find("fights", fid) ~= nil, true)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: before any clerk's digest a client holding part of the ledger takes a public arbiter's podium word (it can't tell it holds the whole)", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	w:As(sp, LG.Keep, { season = 1, fid = "F1aa", t = w.clock - 50, cat = "A", bo = 1, gkA = "3e8.00000001", A = "Ab Cd-Emberfall", gkB = "3e8.00000002",
		B = "Ef Gh-Emberfall", sc = "1:0", w = "A", m = "K", dur = 40, gkArb = "3e8.00000009", fl = "rp" }, "L", "clerk")
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AV~L1~" .. table.concat({ "V2ab", "A", "2", "3e8.00000020", sp.ns.Arena.B36(w.clock - 10), "-", "-" }, "~")) end)
	eq(#w:As(sp, LG.PodiumWords, "L"), 1)
	eq(LG.Stats().refused.podium, nil)
	eq(w:As(sp, LG.Synced, "L"), false)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: HONORS_CHANGED once for a burst of ledger entries (the first at once, the burst's last after HONORS_GAP), not once per entry", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local LG = sp.ns.ArenaLedger
	local fired = 0
	sp.ns.On("HONORS_CHANGED", function() fired = fired + 1 end)
	local GAP = LG.HONORS_GAP or 2
	w:Run(GAP + 1)
	fired = 0
	for i = 1, 30 do
		w:As(sp, LG.Keep, { season = 1, fid = "F" .. i .. "bb", t = w.clock - 50, cat = "A", bo = 1, gkA = ("3e8.%08x"):format(i), A = "Ab Cd-Emberfall",
			gkB = ("3e8.%08x"):format(100 + i), B = "Ef Gh-Emberfall", sc = "1:0", w = "A", m = "K", dur = 40, gkArb = "3e8.00000009", fl = "rp" }, "L", "clerk")
	end
	eq(fired, 1, "the first at once")
	w:Run(GAP + 1)
	eq(fired, 2, "and one after the burst")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the history view model lists this character's own direct and unrated fights, and everyone's unrated public ones; never someone else's private or direct fight", function()
	local w, cast = W3.New()
	for _, c in ipairs({ cast.A, cast.spectator }) do W3.Companion(w, c) end
	-- A direct fight A wins.
	local oid = Agreed(w, cast, { bo = 1 })
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	-- A public walkover (unrated): A present, B not.
	local fid = Booked(w, cast)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 105, 100)
	W3.Stand(cast.B, 9000, 9000)
	Fights(w, cast.arbiter).Call(fid)
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	w:Run(cast.arbiter.ns.ArenaFights.CALL_WINDOW + cast.arbiter.ns.ArenaFights.WO_AUTO + 2)
	eq(State(w, cast.spectator, fid), "W")
	local gkA = w:As(cast.A, function() return cast.A.ns.ArenaProfile.MyGk() end)
	local mine = Ledger(w, cast.A).History({ gk = gkA })
	local seen = {}
	for _, r in ipairs(mine) do seen[r.fid] = r end
	eq(seen[oid] ~= nil, true, "his direct fight"); eq(seen[oid].won, true); eq(seen[oid].direct, true)
	eq(seen[fid] ~= nil, true, "his walkover"); eq(seen[fid].rated, false)
	-- Another viewer: the public walkover, never the direct fight.
	local his = Ledger(w, cast.spectator).History({ gk = gkA })
	local other = {}
	for _, r in ipairs(his) do other[r.fid] = r end
	eq(other[fid] ~= nil, true); eq(other[oid], nil)
	local recent = Ledger(w, cast.spectator).History({})
	local any = false
	for _, r in ipairs(recent) do if r.fid == fid then any = true end end
	eq(any, true, "an unrated public fight in the recent list")
	eq(#w:As(cast.A, cast.A.ns.ArenaFights.MyFights), 2)
	W3.NoErrors(w)
end)

print("the fights part review: tournaments, cards, the King")

test("1.2 the fights part review: a Steward's tournament (the design) makes its bouts with the public arbiters he names (T.New's arbiters, T.SetArbiter), each arbiter taking his bout over; none named: the bout waits and the promoter is told", function()
	local more = { { "stew", N.steward } }
	local names = { "Aric", "Bram", "Cael", "Dorn" }
	for i, n in ipairs(names) do more[#more + 1] = { "e" .. i, n .. " Stone" } end
	local w, cast = W3.New({ more = more })
	local st = cast.stew
	eq(w:As(st, st.ns.ArenaRoles.IsArbiter, st.name, "L"), false, "a Steward is no arbiter")
	local function Run(opts)
		local T = W3.M(w, st, "ArenaTourney")
		local tid = assert(T.New(opts))
		w:Run(0)
		for i = 1, 4 do W3.M(w, cast["e" .. i], "ArenaTourney").Sign(tid) w:Run(4) end
		local t = st.ns.ArenaTourney.Find(tid)
		assert(T.CloseRegistration(tid))
		w.clock = t.tCheck + 1
		for i = 1, 4 do W3.M(w, cast["e" .. i], "ArenaTourney").CheckIn(tid) w:Run(4) end
		w:Group({ st.name, cast.e1.name }, true)
		assert(T.StartDraw(tid))
		st.globals.RandomRoll = function() end
		-- Each Roll click and its line (with 4 entrants all seeded, the one click finishes the draw).
		for _ = 1, 8 do
			if t.st ~= "D" then break end
			local _, _, hi = T.DrawStep(tid)
			if hi then W3.Roll(w, { st, cast.e1 }, st, 1, 1, hi) end
			w:Run(0)
		end
		return T, tid, t
	end
	local T, tid, t = Run({ title = "Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1", arbiters = { cast.arbiter.name } })
	eq(t.st, "L")
	local bouts = {}
	for _, fid in pairs(t.bouts) do bouts[#bouts + 1] = fid end
	-- Every first-round match with both its fighters drawn has its bout (4 entrants: the bracket's).
	local ready = 0
	for _, m in ipairs(w:As(st, st.ns.ArenaBracket.Next, t.bracket)) do if m.a and m.b then ready = ready + 1 end end
	eq(#bouts >= 1, true, "bouts made"); eq(#bouts, ready)
	for _, m in ipairs(w:As(st, st.ns.ArenaBracket.Next, t.bracket)) do
		if m.a and m.b then eq(t.bouts[m.key] ~= nil, true, "bout " .. m.key) end
	end
	for _, fid in ipairs(bouts) do
		local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
		eq(f ~= nil and f.writer, cast.arbiter.name, "the arbiter took it over")
		eq(cast.spectator.ns.ArenaFights.Find("fights", fid).writer, cast.arbiter.name)
		eq(cast.spectator.ns.ArenaFights.Find("fights", fid).tid, tid, "the bout names its tournament")
	end
	-- None named: the bout waits, the promoter is told; naming one makes it.
	w:Group({ st.name }, false)
	w:Run(60)
	local told = {}
	st.ns.On("ARENA_TOURNEY", function(x, what) told[#told + 1] = what end)
	local T2, tid2, t2 = Run({ title = "Cup 2", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" })
	local n = 0
	for _ in pairs(t2.bouts) do n = n + 1 end
	eq(n, 0); eq(t2.needArbiter ~= nil, true)
	local any = false
	for _, x in ipairs(told) do if x == "arbiter" then any = true end end
	eq(any, true, "told")
	assert(T2.SetArbiter(tid2, "*", cast.arbiter.name))
	w:Run(0)
	n = 0
	for _ in pairs(t2.bouts) do n = n + 1 end
	eq(n, #bouts, "made once he names one")
	eq(t2.needArbiter, nil)
	eq(T2.SetArbiter(tid2, "*", cast.spectator.name), false, "a plain member is no arbiter")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a tournament's bout handed to a public arbiter gets its markets from that arbiter, whoever promotes it (a Steward, the King): the sheet's opener rings, settles and voids it; a bout with its markets open keeps its arbiter", function()
	for _, who in ipairs({ "stew", "king" }) do
		local more = { { "stew", N.steward } }
		for i, n in ipairs({ "Aric", "Bram", "Cael", "Dorn" }) do more[#more + 1] = { "e" .. i, n .. " Stone" } end
		local w, cast = WithBank({ more = more })
		local pr = cast[who]
		local T = W3.M(w, pr, "ArenaTourney")
		local tid = assert(T.New({ title = "Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1", arbiters = { cast.arbiter.name } }))
		w:Run(0)
		for i = 1, 4 do W3.M(w, cast["e" .. i], "ArenaTourney").Sign(tid) w:Run(4) end
		local t = pr.ns.ArenaTourney.Find(tid)
		assert(T.CloseRegistration(tid))
		w:Run(0)
		w.clock = t.tCheck + 1
		for i = 1, 4 do assert(W3.M(w, cast["e" .. i], "ArenaTourney").CheckIn(tid)) w:Run(4) end
		w:Group({ pr.name, cast.e1.name }, true)
		assert(T.StartDraw(tid))
		pr.globals.RandomRoll = function() end
		for _ = 1, 8 do
			if t.st ~= "D" then break end
			local _, _, hi = T.DrawStep(tid)
			if hi then W3.Roll(w, { pr, cast.e1 }, pr, 1, 1, hi) end
			w:Run(0)
		end
		eq(t.st, "L", who)
		w:Run(5)
		local AF = cast.arbiter.ns.ArenaFights
		local keys = {}
		for key in pairs(t.bouts) do keys[#keys + 1] = key end
		table.sort(keys)
		eq(#keys, 2, who .. ": both first-round bouts")
		local fid = t.bouts[keys[1]]
		local f = AF.Find("fights", fid)
		eq(f.writer, cast.arbiter.name, who)
		eq(AF.Has(f.fl, "m"), true, who .. ": his own sheet")
		eq(w:As(pr, pr.ns.Markets.CloseBets, fid), false, who .. " opened none of his bouts' sheets")
		-- A bout with its markets open keeps its arbiter (another could neither close nor settle them).
		local ok, why = T.SetArbiter(tid, keys[2], cast.king.name)
		eq(ok, false); eq(why, "markets", who)
		-- The arbiter rings it (his sheet closes), and it settles on his sheet.
		local function Client(name) for i = 1, 4 do if cast["e" .. i].name == name then return cast["e" .. i] end end end
		local a, b = Client(f.A.name), Client(f.B.name)
		W3.Stand(cast.arbiter, 100, 100)
		W3.Stand(a, 110, 100)
		W3.Stand(b, 100, 120)
		assert(Fights(w, cast.arbiter).Call(fid))
		w:Run(0)
		Fights(w, a).Here(fid)
		Fights(w, b).Here(fid)
		w:Run(1)
		local rung, whyNot = Fights(w, cast.arbiter).Bell(fid)
		eq(rung, true, who .. ": the bell (" .. tostring(whyNot) .. ")")
		eq(f.lockAt, cast.arbiter.ns.Markets.Sheet(fid, "L").lockAt)
		w:Run(math.max(0, f.lockAt - w.clock))
		eq(f.st, "L")
		W3.Duel(w, { cast.arbiter, a, b }, a, b)
		w:Run(0)
		w:Run(f.graceEnd - w.clock + 1)
		eq(f.st, "F", who)
		local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
		eq(sheet.markets[1].state .. sheet.markets[1].result, "R1", who)
		eq(f.marketDone, true)
		W3.NoErrors(w)
	end
end)

test("1.2 the fights part review: the events list counts a tournament's entrants on every client (not only the promoter's)", function()
	local more = {}
	for i, n in ipairs({ "Aric", "Bram", "Cael" }) do more[#more + 1] = { "e" .. i, n .. " Stone" } end
	local w, cast = W3.New({ more = more })
	local T = W3.M(w, cast.king, "ArenaTourney")
	local tid = assert(T.New({ title = "Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" }))
	w:Run(0)
	for i = 1, 3 do W3.M(w, cast["e" .. i], "ArenaTourney").Sign(tid) w:Run(4) end
	local function Count(c) for _, e in ipairs(w:As(c, c.ns.ArenaFights.Events, {})) do if e.id == tid then return e.count end end end
	eq(Count(cast.king), 3); eq(Count(cast.spectator), 3)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a tournament's sign-up needs the fighter's own gk, one each (the draw keys on it); another public arbiter never takes a tournament over on its promoter's own client", function()
	local more = {}
	for i, n in ipairs({ "Aric", "Bram" }) do more[#more + 1] = { "e" .. i, n .. " Stone" } end
	local w, cast = W3.New({ more = more })
	local king = cast.king
	local tid = assert(W3.M(w, king, "ArenaTourney").New({ title = "Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" }))
	w:Run(0)
	local gk1 = w:As(cast.e1, function() return cast.e1.ns.ArenaProfile.MyGk() end)
	local function Sign(c, gk) w:As(c, function() c.ns.Arena.Send("AS", "L", table.concat({ tid, "J", gk, "60", "WA", "1" }, "~"), { to = king.name }) end) w:Run(4) end
	Sign(cast.e1, "-")
	local t = king.ns.ArenaTourney.Find(tid)
	eq(#t.entrants, 0, "no gk: refused")
	Sign(cast.e1, gk1)
	eq(#t.entrants, 1)
	Sign(cast.e2, gk1)
	eq(#t.entrants, 1, "another's gk: refused")
	-- The promoter keeps saying it; another public arbiter's AT after 30 minutes changes nothing here.
	w:Run(king.ns.ArenaTourney.TAKE_OVER + 60)
	local body = king.ns.ArenaTourney.Encode(t)
	w:As(king, function() king.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AT~L1~" .. body) end)
	eq(t.promoter, king.name)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: AN and AT from a wrong sender are ignored (the design): a plain member's, another promoter's for a card or a tournament held", function()
	local w, cast = W3.New()
	local sp = cast.spectator
	local AF = sp.ns.ArenaFights
	local cid = assert(W3.M(w, cast.arbiter, "ArenaFights").Card.New("Night", w.clock + 3600))
	w:Run(0)
	local card = AF.Card.Get(cid)
	eq(card ~= nil, true)
	local function AN(from, id, title)
		w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", from, "AN~L1~" .. table.concat({ id, "P", "-", "1", sp.ns.Arena.B36(w.clock + 3600), "0", "-", "-.-.-", title }, "~")) end)
	end
	AN(N.bettor2, "N1ab" .. sp.ns.Arena.Hash36(N.bettor2:lower(), 2), "Mine")
	eq(AF.Card.Get("N1ab" .. sp.ns.Arena.Hash36(N.bettor2:lower(), 2)), nil, "a plain member")
	AN(N.king, cid, "Stolen")
	eq(AF.Card.Get(cid).title, "Night", "another promoter's word for a card held")
	local tid = assert(W3.M(w, cast.arbiter, "ArenaTourney").New({ title = "Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000 }))
	w:Run(0)
	local t = sp.ns.ArenaTourney.Find(tid)
	local body = cast.arbiter.ns.ArenaTourney.Encode(cast.arbiter.ns.ArenaTourney.Find(tid)):gsub("~Cup$", "~Stolen")
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.bettor2, "AT~L1~" .. body) end)
	w:As(sp, function() sp.ns.Arena.Inject("CHANNEL", N.king, "AT~L1~" .. body) end)
	eq(t.title, "Cup"); eq(t.promoter, cast.arbiter.name)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the King's void of a set fight reaches every client (his AR), and its writer voids its markets", function()
	local w, cast = WithBank()
	local fid = Booked(w, cast)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "m"), true, "the writer opened its sheet")
	local ok = w:As(cast.king, cast.king.ns.ArenaFights.Void, fid, "arb")
	eq(ok, true)
	w:Run(0)
	for _, c in ipairs({ cast.king, cast.arbiter, cast.A, cast.B, cast.spectator }) do eq(State(w, c, fid), "V", c.short) end
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(sheet.markets[1].state .. sheet.markets[1].result, "VX", "the writer voided its markets")
	eq(f.marketDone, true)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: matchmaking's end (ArenaMatch.Ended, the design) for a match an arbiter judged, on the challenger's client", function()
	local w, cast = W3.New()
	local ended = {}
	rawset(cast.A.ns, "ArenaMatch", { Vet = function() return true end, Ended = function(mid) ended[#ended + 1] = mid end })
	local oid = Agreed(w, cast, { how = "a", arbiter = cast.arbiter.name, bo = 1, from = "M1" })
	assert(Fights(w, cast.arbiter).Judge(oid, true))
	w:Run(0)
	local fid = cast.A.ns.ArenaFights.challenges[oid].fid
	eq(cast.A.ns.ArenaFights.Find("fights", fid).from, "M1")
	w:As(cast.arbiter, cast.arbiter.ns.ArenaFights.Void, fid, "cancel")
	w:Run(0)
	eq(#ended, 1); eq(ended[1], "M1")
	W3.NoErrors(w)
end)

print("the fights part review: markets, the Chronicle, obligations")

test("1.2 the fights part review: a fight's markets flag is its real sheet's: grace 300, the bell closes the bets, the result declares them; a duel before the bell voids them and they stay voided (the ticker never opens them again)", function()
	local w, cast = WithBank()
	local AF = cast.arbiter.ns.ArenaFights
	local fid = Booked(w, cast)
	local f = AF.Find("fights", fid)
	eq(AF.Has(f.fl, "m"), true)
	eq(cast.spectator.ns.ArenaFights.Has(cast.spectator.ns.ArenaFights.Find("fights", fid).fl, "m"), true, "every client hears it")
	-- Called, ready, belled: the bell closes the real sheet, one lock for both.
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 100, 120)
	assert(Fights(w, cast.arbiter).Call(fid))
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	Fights(w, cast.B).Here(fid)
	w:Run(1)
	assert(Fights(w, cast.arbiter).Bell(fid))
	eq(f.lockAt, cast.arbiter.ns.Markets.Sheet(fid, "L").lockAt)
	w:Run(math.max(0, f.lockAt - w.clock))
	eq(f.st, "L")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(f.graceEnd - w.clock, 300)
	w:Run(301)
	eq(f.st, "F")
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(sheet.markets[1].state .. sheet.markets[1].result, "R1", "declared: A won")
	-- A duel between the two before the bell: the sheet voided ("early"), the flag off on every
	-- client, and after the ticker's retry still off (its sheet is still held here: never again).
	local fid2 = Booked(w, cast)
	local f2 = AF.Find("fights", fid2)
	eq(AF.Has(f2.fl, "m"), true)
	local voids = {}
	cast.arbiter.ns.On("ARENA_VOID", function(x, code) voids[#voids + 1] = code end)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(voids[#voids], "early")
	local sheet2 = cast.arbiter.ns.Markets.Sheet(fid2, "L")
	eq(sheet2.markets[1].state .. sheet2.markets[1].result, "VE")
	eq(AF.Has(f2.fl, "m"), false)
	eq(cast.spectator.ns.ArenaFights.Has(cast.spectator.ns.ArenaFights.Find("fights", fid2).fl, "m"), false, "said to every client")
	w:Run(AF.MARKET_RETRY + 1)
	eq(AF.Has(f2.fl, "m"), false, "not opened again")
	eq(w:As(cast.arbiter, AF.GraceOf, f2), 120, "voided before the bell: no longer open")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: every client that hears a ruling (src A) or a correction writes it in its Chronicle (the design), once", function()
	local w, cast = W3.New()
	local lines = {}
	rawset(cast.spectator.ns, "Chronicle", { Add = function(kind, by, what) lines[#lines + 1] = by .. ": " .. what end })
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	W3.Duel(w, { cast.A }, cast.A, cast.B)
	w:Run(cast.arbiter.ns.ArenaFights.RESULT_WAIT + 2)
	assert(Fights(w, cast.arbiter).Rule(fid, "B", "K"))
	w:Run(0)
	eq(#lines, 1); assert(lines[1]:find("ruled fight " .. fid, 1, true), lines[1])
	assert(Fights(w, cast.arbiter).Correct(fid, 1, "A", "K"))
	w:Run(0)
	eq(#lines, 2); assert(lines[2]:find("corrected the result of fight " .. fid, 1, true), lines[2])
	w:Run(400)
	eq(#lines, 2, "the final word adds none")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a fighter's AW is an obligation only for a staked direct fight (the design): with the arena off, none for a public fight, the signed one for a staked direct fight", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	cast.A.db.arenaOff = true
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(#w:Sent{ from = cast.A, type = "AW" }, 0, "off: a public fight's report is not his obligation")
	cast.A.db.arenaOff = nil
	w:Run(200)
	-- A staked direct fight: his signed result goes, arena off or not.
	W3.Money(w, cast.A)
	W3.Money(w, cast.B)
	local oid = Agreed(w, cast, { how = "d", stake = 10000, cur = "g" })
	cast.A.db.arenaOff = true
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Run(0)
	local sent = w:Sent{ from = cast.A, type = "AW" }
	eq(#sent, 1, "his signed result")
	assert(sent[1].msg:find(oid, 1, true))
	cast.A.db.arenaOff = nil
	W3.NoErrors(w)
end)

test("1.2 the fights part review: AS~X never overwrites a challenge held (its id must be the sender's own, never one held); an answer that could not go leaves the challenge asked", function()
	local w, cast = W3.New({ more = { { "x", "Parric Stowe" } } })
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	local B = cast.B
	local held = B.ns.ArenaFights.challenges[oid]
	w:As(B, function() B.ns.Arena.Inject("WHISPER", cast.x.name, "AS~L1~" .. table.concat({ oid, "X", "3", "0", "d", "-", "g" }, "~")) end)
	eq(B.ns.ArenaFights.challenges[oid], held, "another's id: refused")
	w:Run(4)
	w:As(B, function() B.ns.Arena.Inject("WHISPER", cast.A.name, "AS~L1~" .. table.concat({ oid, "X", "3", "0", "d", "-", "g" }, "~")) end)
	eq(B.ns.ArenaFights.challenges[oid].bo, 1, "held: never replaced")
	-- The answer refused by the send (the arena off here): not yes.
	B.db.arenaOff = true
	local ok = Fights(w, B).Answer(oid, true)
	B.db.arenaOff = nil
	eq(ok, false); eq(B.ns.ArenaFights.challenges[oid].state, "asked")
	W3.NoErrors(w)
end)

print("the fights part review: honours")

test("1.2 the fights part review: the level race's claims are each sender's own: another's IL naming his gk takes no slot of his; a full book drops its oldest unvouched claim; a claim that can no longer be vouched holds nobody up", function()
	local w, cast = W3.New()
	local x = w:Role("bettor2")
	local B = cast.B
	local obs = cast.spectator
	local gkB = w:As(B, function() return B.ns.ArenaProfile.MyGk() end)
	local B36 = obs.ns.Arena.B36
	w:As(x, function() x.ns.Arena.Send("IL", "L", table.concat({ gkB, B36(60), B36(w.clock) }, "~"), {}) end)
	w:Run(0)
	w:As(B, function() B.ns.Arena.Send("IL", "L", table.concat({ gkB, B36(60), B36(w.clock) }, "~"), {}) end)
	w:Run(0)
	local s = w:As(obs, function() return obs.ns.HonorsNet.Store() end)
	eq(s.claims[B.name:lower() .. ":60"] ~= nil, true, "B's own claim kept")
	-- (The race runs from the 1.2 release: the clock after it.)
	w.clock = obs.ns.HonorsNet.RACE_START + 30 * 86400
	eq(s.claims[B.name:lower() .. ":60"].name, B.name)
	-- The book full of one sender's inventions: impossible (one per sender and milestone); full of
	-- many: the oldest unvouched goes.
	local HN = obs.ns.HonorsNet
	for k in pairs(s.claims) do s.claims[k] = nil end
	for i = 1, HN.CLAIMS_MAX do s.claims["someone" .. i .. ":40"] = { gk = ("3e8.%08x"):format(i), name = "Some One-Emberfall", level = 40, t = w.clock - 1000 + i, heardLocal = w.clock, vouched = false } end
	w:As(B, function() B.ns.Arena.Send("IL", "L", table.concat({ gkB, B36(40), B36(w.clock) }, "~"), {}) end)
	w:Run(0)
	eq(s.claims[B.name:lower() .. ":40"] ~= nil, true, "taken")
	eq(s.claims["someone1:40"], nil, "the oldest unvouched dropped")
	-- An unvouched claim past the vouching window: B's later, vouched claim takes the place.
	for k in pairs(s.claims) do s.claims[k] = nil end
	s.claims["early:20"] = { gk = "3e8.0000abcd", name = "Early Bird-Emberfall", level = 20, t = w.clock - 3 * 86400, heardLocal = w.clock - 3 * 86400, vouched = false }
	s.claims[B.name:lower() .. ":20"] = { gk = gkB, name = B.name, level = 20, t = w.clock - 2 * 86400, heardLocal = w.clock - 2 * 86400, vouched = true }
	w:As(obs, HN.RunRace)
	local levels = w:As(obs, HN.Levels)
	eq(levels[20] and levels[20][1] and levels[20][1].name, B.name)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: under the gamepad UI the King's letter never opens by itself: it waits (said once in chat) until the player opens his profile's Edit", function()
	local w, cast = W3.New()
	local A = cast.A
	A.globals.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
	A.globals.Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
	w:As(A, A.ns.HonorsNet.QueueLetter, "arena-champion")
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter == nil or not letter:IsShown(), true, "not by itself")
	eq(Printed(A, A.ns.L.HONOR_LETTER_WAITING), true)
	eq(#A.ns.HonorsNet.QueuedLetters(), 1)
	w:As(A, A.ns.ProfileEdit.Open)
	letter = A.ns.HonorsNet.LetterFrame()
	eq(letter ~= nil and letter:IsShown(), true, "the player's click opened it")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: in the chat icon picker an honour's mark picks that honour and takes a councillor's own icon away (the design); a non-councillor's list is his marks only", function()
	local w, cast = W3.New({ more = { { "hc", N.councillor } } })
	local hc = cast.hc
	hc.globals.GetLooseMacroIcons = function(t) t[1] = 134400 t[2] = 134401 end
	-- A title fight hc won (a vacant global belt: the gryphon's gold).
	local e = table.concat({ "1", "Fzzq", hc.ns.Arena.B36(w.clock - 600), "A", "1", hc.ns.Arena.GK(hc.guid), hc.short, "-", hc.ns.Arena.GK(cast.B.guid), cast.B.short,
		"-", "1:0", "A", "K", "3c", hc.ns.Arena.GK(cast.arbiter.guid), "prtb" }, "~")
	w:As(hc, function() hc.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end)
	w:Run(3)
	eq(w:As(hc, hc.ns.Workshop.SetCouncilIcon, 134400), true)
	eq(hc.ns.CouncilIcon(hc.name) ~= nil, true)
	w:As(hc, hc.ns.ArenaProfile.SetPick, "rank", nil)
	local PE = W3.M(w, hc, "ProfileEdit")
	local list = PE.IconList("icon")
	eq(type(list[1]), "table"); eq(list[1].key, "gryphon-gold")
	eq(#list > 1, true, "a councillor: the game's icons after his marks")
	-- The picker's OK with his honour's mark (Workshop.IconPickerHost's onPick, as the game calls it).
	local onPick
	hc.ns.Workshop.IconPickerHost = function(parent, l, fn) onPick = fn return {} end
	PE.IconPicker("icon", {})
	w:As(hc, onPick, "gryphon-gold")
	eq(hc.ns.ArenaProfile.Pick().frame, "arena-champion", "the honour picked")
	eq(hc.ns.CouncilIcon(hc.name), "", "his own icon taken away: the mark shows")
	-- A non-councillor: his marks only.
	local e2 = table.concat({ "1", "Fzzr", hc.ns.Arena.B36(w.clock - 500), "CWA", "1", hc.ns.Arena.GK(cast.A.guid), cast.A.short, "WA1.60", hc.ns.Arena.GK(cast.B.guid),
		cast.B.short, "WA1.60", "1:0", "A", "K", "3c", hc.ns.Arena.GK(cast.arbiter.guid), "prtb" }, "~")
	w:As(cast.A, function() cast.A.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e2) end)
	w:Run(3)
	for _, icon in ipairs(W3.M(w, cast.A, "ProfileEdit").IconList("icon")) do eq(type(icon), "table", "marks only") end
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the weigh-in's guild text goes through King.CleanGuild on receipt (the design)", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local sp = cast.spectator
	w:As(sp, function()
		sp.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AG~L1~" .. table.concat({ fid, "A", sp.ns.Arena.GK(cast.A.guid), "WA", "1", "2", "60", "A",
			"Not Olympus Evil Guild Name Here", "3", "5000", sp.ns.Arena.B36(w.clock), "-" }, "~"))
	end)
	local f = sp.ns.ArenaFights.Find("fights", fid)
	eq(f.facts.A ~= nil, true); eq(f.facts.A.guild, nil, "not an Olympus guild's name")
	W3.NoErrors(w)
end)

print("the fights part review: sizes (the design)")

test("1.2 the fights part review: the longest names and fields keep every single A/I message within 250 bytes (a staked AS and the donors' ID go in pieces); AT with 32 entrants and 8 waiting fits in 30 pieces (the design)", function()
	local w, cast = W3.New()
	local F = cast.arbiter.ns.ArenaFights
	local A = cast.arbiter.ns.Arena
	-- The longest a name travels: two words of 12 letters (the game's longest) on the other realm
	-- of the group (the realm's name with it: ClassicBetaPvP, 14), 40 bytes.
	local long = "Abcdefghijkl Mnopqrstuvwx-ClassicBetaPvP"
	local long2 = "Zyxwvutsrqpo Nmlkjihgfedc-ClassicBetaPvP"
	eq(#long, 40)
	local gk = "zzz.ffffffff"
	local fid = "F" .. A.B36(4294967295) .. A.B36(99999) .. "zz"
	local f = { fid = fid, st = "R", fl = "ptmcsrbx", bo = 5, cat = "CWL", arb = long, card = "N" .. A.B36(4294967295) .. A.B36(99999) .. "zz",
		A = { name = long, gk = gk }, B = { name = long2, gk = gk }, tAnn = w.clock, tCall = w.clock, lockAt = w.clock, round = 9, sc = { 9, 9 }, w = "A", m = "K",
		dur = 86400, mode = "L" }
	local msgs = {}
	msgs.AF = "AF~L1~" .. w:As(cast.arbiter, F.Encode, f)
	local LG = cast.arbiter.ns.ArenaLedger
	msgs.AE = "AE~L1~" .. w:As(cast.arbiter, LG.Encode, { season = 999, fid = fid, t = w.clock, cat = "CWL", bo = 5, gkA = gk, A = long, fA = { class = "WL", race = 10, level = 60 },
		gkB = gk, B = long2, fB = { class = "WL", race = 10, level = 60 }, sc = "9:9", w = "A", m = "K", dur = 86400, gkArb = gk, fl = "ptmokdcsrb" })
	msgs.AR = "AR~L1~" .. table.concat({ fid, "9", "9:9", "A", "K", A.B36(86400), A.B36(20), "A", "1", A.B36(w.clock), "disputed" }, "~")
	-- (A staked direct fight's AW carries the loser's Ed25519 signature: 86 characters of base64url.)
	msgs.AW = "AW~L1~" .. table.concat({ fid, "9", "K", long, long2, A.B36(w.clock), A.B36(86400000), string.rep("x", 86) }, "~")
	msgs.AG = "AG~L1~" .. table.concat({ fid, "A", gk, "WL", "10", "3", "60", "H", "Olympus Knights Of Blood", "9", "999999", A.B36(w.clock), "abcdefghij" }, "~")
	msgs.AC = "AC~L1~" .. table.concat({ fid, "H", "9", A.B36(2000000), A.B36(2000000), A.B36(99999999), gk }, "~")
	msgs.ASY = "AS~L1~" .. table.concat({ fid, "Y", "0", "notnow" }, "~")
	msgs.ASQ = "AS~L1~" .. table.concat({ fid, "Q", long, long2, A.B36(21474836), "5" }, "~")
	msgs.ASZ = "AS~L1~" .. table.concat({ fid, "Z", "1", "-", fid }, "~")
	msgs.AN = "AN~L1~" .. table.concat({ f.card, "L", "-", A.B36(99999), A.B36(w.clock), A.B36(99999), table.concat({ fid, fid, fid }, ","),
		fid .. "." .. fid .. "." .. fid, string.rep("W", 40) }, "~")
	local vid = "V" .. A.B36(w.clock) .. "zz" .. A.B36(999999)
	msgs.AV = "AV~L1~" .. table.concat({ vid, "CWL", "3", gk, A.B36(w.clock), string.rep("r", 16), vid }, "~")
	msgs.AH = "AH~L1~" .. table.concat({ A.B36(999), A.B36(w.clock), A.B36(w.clock), "1g", "1g", "1", A.B36(w.clock) }, "~")
	msgs.IL = "IL~L1~" .. table.concat({ gk, A.B36(60), A.B36(w.clock) }, "~")
	msgs.IO = "IO~L1~" .. table.concat({ A.B36(99999), A.B36(w.clock), table.concat({ long, long2, long }, ",") }, "~")
	msgs.AP = "AP~L1~" .. table.concat({ gk, "WL", "10", "3", "60", "32.32", "134400", "1", "arena-class-warlock-3", "arena-race-nightelf-3", A.B36(w.clock) }, "~")
	for kind, text in pairs(msgs) do
		assert(#text <= 250, kind .. ": " .. #text .. " bytes")
	end
	-- The donors' ID with six names on the other realm is longer than one message: it goes keyed, in
	-- pieces (Arena.Send), whole or not at all.
	local id = "ID~L1~" .. table.concat({ A.B36(w.clock), A.B36(99999), table.concat({ long, long2, long }, ","), table.concat({ long, long2, long }, ",") }, "~")
	assert(math.ceil(#id / A.PIECE) <= 2, "ID: " .. #id .. " bytes")
	-- A tournament of 32 and 8 waiting, the longest names on another realm, every slot and bout.
	local T = cast.arbiter.ns.ArenaTourney
	local t = { tid = "T" .. A.B36(4294967295) .. A.B36(99999) .. "zz", st = "L", fl = "t", cat = "CWL", size = 32, tReg = w.clock, tCheck = w.clock,
		tStart = w.clock, bo = "13555", third = true, entrants = {}, seeds = {}, bouts = {}, title = string.rep("W", 40) }
	for i = 1, 40 do t.entrants[i] = { n = i, gk = ("zzz.%08x"):format(0xfffff000 + i), name = i % 2 == 0 and long or long2, chk = true, wait = i > 32 } end
	for i = 1, 32 do t.seeds[i] = t.entrants[i].gk end
	for r = 1, 5 do for i = 1, 2 ^ (5 - r) do t.bouts[r .. "." .. i] = fid end end
	t.bouts["5.2"] = fid
	local text = "AT~L1~" .. w:As(cast.arbiter, T.Encode, t)
	local pieces = math.ceil(#text / A.PIECE)
	assert(pieces <= A.PIECES_MAX and pieces <= 30, "AT: " .. pieces .. " pieces")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the honours' art keeps its provenance in the repository: media/honors/src/SHA256SUMS names every shipped file and the lab file it is (the Paladin's gold is paladin-new.tga); sampled files hash to it (the whole set: scripts/make-honors.py --check)", function()
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "Honors.lua"))("Olympus", ns)
	assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", ns)
	local f = assert(io.open(H.ROOT .. "media/honors/src/SHA256SUMS", "rb"), "the manifest")
	local sums, n = {}, 0
	for line in f:lines() do
		local digest, lab, name = line:match("^(%x+)  (%S+)  (%S+)$")
		if digest then sums[name] = { digest = digest, lab = lab } n = n + 1 end
	end
	f:close()
	local want = 0
	for _, art in ipairs(ns.Honors.ArtFiles()) do
		for _, name in ipairs({ art .. ".tga", art .. "-mark.tga" }) do
			want = want + 1
			eq(sums[name] ~= nil, true, name .. " in SHA256SUMS")
		end
	end
	eq(n, want, "nothing else")
	eq(sums["paladin-gold.tga"].lab, "paladin-new.tga")
	eq(sums["gryphon-gold.tga"].lab, "gryphon.tga")
	local function Hash(name)
		local file = assert(io.open(H.ADDON_DIR .. "media/honors/" .. name, "rb"))
		local data = file:read("*a")
		file:close()
		return (ns.Sign.SHA256(data):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
	end
	for _, name in ipairs({ "paladin-gold.tga", "owl-gold-mark.tga", "comet-bronze-mark.tga" }) do eq(Hash(name), sums[name].digest, name) end
end)

print("the fights part review (the port's review): voids after a decided round, a bout kept out of betting, a creature's unit, a later duel, the letter's window")

test("1.2 the fights part review: the King's void of a fight in its grace or between the rounds of a best of 3 is a void on every client, never the decided round's final win: its writer refunds the stakes and voids the sheet", function()
	local w, cast = WithBank()
	local money = W3.Money(w, cast.arbiter)
	local results = {}
	for _, c in ipairs({ cast.arbiter, cast.A, cast.B, cast.spectator }) do
		c.ns.On("ARENA_RESULT", function(fid) results[#results + 1] = c.short .. " " .. tostring(fid) end)
	end
	-- In the grace: A beat B.
	local fid = Booked(w, cast, { stakes = true })
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "m"), true, "its sheet open")
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(f.st, "R")
	eq(w:As(cast.king, cast.king.ns.ArenaFights.Void, fid, "arb"), true)
	w:Run(0)
	for _, c in ipairs({ cast.king, cast.arbiter, cast.A, cast.B, cast.spectator }) do eq(State(w, c, fid), "V", c.short) end
	eq(#results, 0, "no final result anywhere")
	eq(#money.result, 1); eq(money.result[1].side, "V", "the stakes refunded, never paid out")
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(sheet.markets[1].state .. sheet.markets[1].result, "VX", "the sheet voided, never declared")
	eq(cast.spectator.ns.ArenaFights.Find("fights", fid).rounds[1].m, "K", "the round kept as it was decided")
	w:Run(cast.arbiter.ns.ArenaFights.GRACE_HELD + cast.arbiter.ns.ArenaFights.FINAL_SLACK + 1)
	eq(State(w, cast.spectator, fid), "V", "still void after its grace")
	-- Between the rounds of a best of 3: round 1 to A.
	local fid2 = Booked(w, cast, { bo = 3 })
	Live(w, cast, fid2)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(State(w, cast.arbiter, fid2), "B")
	eq(w:As(cast.king, cast.king.ns.ArenaFights.Void, fid2, "arb"), true)
	w:Run(0)
	for _, c in ipairs({ cast.king, cast.arbiter, cast.A, cast.B, cast.spectator }) do eq(State(w, c, fid2), "V", c.short) end
	eq(#results, 0)
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the writer's void or no contest in the grace reaches every client as that, never first as the decided round's final result: no ARENA_RESULT, no win or loss in a fighter's own history", function()
	local w, cast = W3.New()
	for _, c in ipairs({ cast.A, cast.B }) do W3.Companion(w, c) end
	local results = {}
	for _, c in ipairs({ cast.A, cast.B, cast.spectator }) do
		c.ns.On("ARENA_RESULT", function(fid) results[#results + 1] = c.short .. " " .. tostring(fid) end)
	end
	for _, how in ipairs({ "V", "N" }) do
		local fid = Booked(w, cast)
		Live(w, cast, fid)
		W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
		w:Run(0)
		eq(State(w, cast.A, fid), "R")
		if how == "V" then assert(Fights(w, cast.arbiter).Void(fid, "arb")) else assert(Fights(w, cast.arbiter).NoContest(fid, "arb")) end
		w:Run(0)
		for _, c in ipairs({ cast.arbiter, cast.A, cast.B, cast.spectator }) do eq(State(w, c, fid), how, c.short) end
		eq(#results, 0, how .. ": no final result")
		for _, c in ipairs({ cast.A, cast.B }) do
			local mine = w:As(c, c.ns.ArenaFights.MyFights, "L")
			local e = mine[#mine]
			eq(e and e.fid, fid, c.short)
			eq(e.w, "-", c.short .. ": neither won"); eq(e.m, how)
			local gk = w:As(c, function() return c.ns.ArenaProfile.MyGk() end)
			for _, row in ipairs(Ledger(w, c).History({ gk = gk })) do eq(row.fid ~= fid, true, c.short .. ": not in his history") end
		end
		w:Run(5)
	end
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a card's bout its promoter kept out of betting (markets = false) gets no sheet from the arbiter who takes it over (flag x); a list of markets of its own is never cut down on the way to another arbiter (F.New, Card.SetArbiter: markets)", function()
	local w, cast = WithBank()
	for _, c in ipairs({ cast.arbiter, cast.spectator }) do W3.Companion(w, c) end
	local king = cast.king
	local C = king.ns.ArenaFights.Card
	local AF = cast.arbiter.ns.ArenaFights
	local cid = assert(w:As(king, C.New, "Night of Blades", w.clock + 3600))
	-- Kept out of betting, handed to the public arbiter.
	local fid = assert(w:As(king, C.AddBout, cid, { A = cast.A.name, B = cast.B.name, bo = 1, markets = false, arb = cast.arbiter.name }))
	assert(w:As(king, king.ns.ArenaFights.Announce, fid))
	w:Run(0)
	local f = AF.Find("fights", fid)
	eq(f.writer, cast.arbiter.name, "taken over")
	eq(cast.arbiter.ns.Markets.Sheet(fid, "L"), nil, "no sheet")
	eq(AF.Has(f.fl, "m"), false); eq(f.marketSpecs, nil)
	eq(AF.Has(f.fl, "x"), true, "the promoter's word travels")
	w:Run(AF.MARKET_RETRY + 1)
	eq(cast.arbiter.ns.Markets.Sheet(fid, "L"), nil, "nor after the ticker's retry")
	eq(AF.Has(cast.spectator.ns.ArenaFights.Find("fights", fid).fl, "x"), true, "on every client")
	-- The default: its winner market, from its arbiter.
	local fid2 = assert(w:As(king, C.AddBout, cid, { A = cast.A.name, B = cast.B.name, bo = 1, arb = cast.arbiter.name }))
	assert(w:As(king, king.ns.ArenaFights.Announce, fid2))
	w:Run(0)
	local f2 = AF.Find("fights", fid2)
	eq(AF.Has(f2.fl, "m"), true, "the default opens"); eq(AF.Has(f2.fl, "x"), false)
	-- A list of its own can't travel: refused for another arbiter, and its bout keeps its arbiter.
	local custom = { { type = "MW" }, { type = "DU", param = 90 } }
	local none, why = w:As(king, C.AddBout, cid, { A = cast.A.name, B = cast.B.name, bo = 1, markets = custom, arb = cast.arbiter.name })
	eq(none, nil); eq(why, "markets")
	local own = assert(w:As(king, C.AddBout, cid, { A = cast.A.name, B = cast.B.name, bo = 1, markets = custom }))
	local ok, why2 = w:As(king, C.SetArbiter, cid, own, cast.arbiter.name)
	eq(ok, false); eq(why2, "markets")
	-- The bout kept out of betting, fought and rated: its entry goes without the flag (the ledger's
	-- flags refuse it), so every client's ledger takes it.
	eq(Fights(w, cast.A).Accept(fid), true); eq(Fights(w, cast.B).Accept(fid), true)
	w:Run(0)
	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	w:Run(f.graceEnd - w.clock + 1)
	eq(f.st, "F"); eq(AF.Has(f.fl, "r"), true, "rated")
	local held = false
	for _, e in ipairs(Ledger(w, cast.spectator).Entries(nil, "L")) do if e.fid == fid then held = true end end
	eq(held, true, "the spectator's ledger takes its entry")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the fighter's unit search skips a creature the arbiter has targeted (its name and GUID are secrets, an error to compare): the called fight still reaches its walkover", function()
	local w, cast = W3.New()
	local fid = Booked(w, cast)
	local AF = cast.arbiter.ns.ArenaFights
	local f = AF.Find("fights", fid)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 9000, 9000)
	W3.Sees(cast.arbiter, { [cast.A] = true })
	-- A creature in his target: the game gives its name and GUID as secrets (UnitFullName and
	-- UnitGUID are SecretWhenUnitIdentityRestricted), which error on any comparison or string use.
	local function Boom() error("a secret used", 2) end
	local SECRET = setmetatable({}, { __index = Boom, __tostring = Boom, __concat = Boom, __lt = Boom, __le = Boom, __eq = Boom, __len = Boom })
	local g = cast.arbiter.globals
	local exists, player, fullName, guid = g.UnitExists, g.UnitIsPlayer, g.UnitFullName, g.UnitGUID
	g.issecretvalue = function(v) return rawequal(v, SECRET) end
	g.UnitExists = function(unit) if unit == "target" then return true end return exists(unit) end
	g.UnitIsPlayer = function(unit) if unit == "target" then return false end return player(unit) end
	g.UnitFullName = function(unit) if unit == "target" then return SECRET, SECRET end return fullName(unit) end
	g.UnitGUID = function(unit) if unit == "target" then return SECRET end return guid(unit) end
	eq(w:As(cast.arbiter, AF.TokenOf, f.B.gk, f.B.name), nil, "not him")
	assert(Fights(w, cast.arbiter).Call(fid))
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	w:Run(AF.CALL_WINDOW + AF.WO_AUTO + 2)
	eq(f.st, "W", "the walkover applied by itself"); eq(f.w, "A")
	eq(f.facts.A and f.facts.A.seen, true, "the fighter's own unit still weighed in")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: the arbiter's own line overrules only a fighter's and his witnesses' reports: a rematch for fun in the grace, or a warm-up before a best-of's next bell, never changes a round both fighters' own lines decided", function()
	local w, cast = W3.New()
	local AF = cast.arbiter.ns.ArenaFights
	-- Both fighters report A (the arbiter out of range); in the grace B wins a duel in his sight.
	local fid = Booked(w, cast)
	Live(w, cast, fid)
	local f = AF.Find("fights", fid)
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(AF.RESULT_WAIT + 2)
	eq(f.st, "R"); eq(f.w, "A"); eq(f.rounds[1].src, "F")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(1)
	eq(f.st, "R"); eq(f.w, "A", "the fighters' own duel stands"); eq(f.rounds[1].src, "F"); eq(f.code, nil, "not disputed")
	eq(cast.spectator.ns.ArenaFights.Find("fights", fid).w, "A", "on every client")
	w:Run(AF.GRACE + 1)
	eq(f.st, "F"); eq(f.w, "A")
	-- A best of 3: round 1 to A by both fighters' lines; a warm-up B wins before round 2's bell.
	local fid2 = Booked(w, cast, { bo = 3 })
	Live(w, cast, fid2)
	local f2 = AF.Find("fights", fid2)
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(AF.RESULT_WAIT + 2)
	eq(f2.st, "B"); eq(f2.sc[1] .. ":" .. f2.sc[2], "1:0")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(1)
	eq(f2.st, "B"); eq(f2.sc[1] .. ":" .. f2.sc[2], "1:0", "round 1 as the fighters reported it")
	eq(f2.rounds[1].w, "A"); eq(f2.rounds[1].src, "F")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: under the gamepad UI a waiting letter opens with the Olympus window even when the window was made after the letter came (on its first open, whatever its template)", function()
	-- HonorsNet: the window's open shows the letter waiting for the player's click.
	local w, cast = W3.New()
	local A = cast.A
	A.globals.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
	A.globals.Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
	w:As(A, A.ns.HonorsNet.QueueLetter, "arena-champion")
	eq(Printed(A, A.ns.L.HONOR_LETTER_WAITING), true)
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter == nil or not letter:IsShown(), true, "not by itself")
	eq(w:As(A, A.ns.HonorsNet.WindowShown), true)
	letter = A.ns.HonorsNet.LetterFrame()
	eq(letter ~= nil and letter:IsShown(), true, "opened with the window")
	W3.NoErrors(w)
	-- UI.lua: the window, made on its first open, tells HonorsNet when it shows (each time).
	H.WithUI(function()
		local uns = setmetatable({}, { __index = H.ns })
		uns.On = function() end
		local shown = 0
		uns.HonorsNet = { WindowShown = function() shown = shown + 1 end }
		assert(loadfile(H.ADDON_DIR .. "UI.lua"))("Olympus", uns)
		H.WithStub("UI", uns.UI, function()
			eq(rawget(_G, "OlympusFrame") or rawget(_G, "OlympusFrameBasic"), nil, "no window yet")
			uns.UI.Toggle()
			eq(shown, 1, "the first open")
			uns.UI.Toggle()
			uns.UI.Toggle()
			eq(shown, 2, "and the next")
		end)
	end)
end)
