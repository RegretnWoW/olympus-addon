-- 1.2 integration: the real fight and tournament controllers must drive the canonical Markets
-- sheet. These are route tests, not direct Markets.Open/Declare tests: every transition starts at
-- the public ArenaFights/ArenaTourney functions a player's button calls.
local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = H.World.NAMES

local function M(w, c, name) return W3.M(w, c, name) end

local function WorldWithBank(extra)
	local more = { { "bank", N.bank } }
	for _, e in ipairs(extra or {}) do more[#more + 1] = e end
	local w, cast = W3.New({ more = more })
	assert(cast.king.Roles.SetBanks({ N.bank }))
	w:Run(0)
	return w, cast
end

local function Booked(w, cast, opts)
	local AF = M(w, cast.arbiter, "ArenaFights")
	local spec = { A = cast.A.name, B = cast.B.name, bo = 1 }
	for k, v in pairs(opts or {}) do spec[k] = v end
	local fid = assert(AF.New(spec))
	assert(AF.Announce(fid))
	w:Run(0)
	assert(M(w, cast.A, "ArenaFights").Accept(fid))
	assert(M(w, cast.B, "ArenaFights").Accept(fid))
	w:Run(0)
	return fid
end

local function Live(w, cast, fid)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 100, 120)
	local AF = M(w, cast.arbiter, "ArenaFights")
	assert(AF.Call(fid))
	w:Run(0)
	assert(M(w, cast.A, "ArenaFights").Here(fid))
	assert(M(w, cast.B, "ArenaFights").Here(fid))
	w:Run(1)
	assert(AF.Bell(fid))
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(f.lockAt, sheet.lockAt, "the fight and its real sheet share one lock")
	w:Run(math.max(0, f.lockAt - w.clock))
	eq(f.st, "L")
	return f
end

test("1.2 integration: a public hosted fight opens its requested deterministic markets, the Bell closes the real sheet, and a best-of-three settles each market exactly once", function()
	local w, cast = WorldWithBank()
	local fid = Booked(w, cast, { bo = 3, markets = { { type = "MW" }, { type = "SW" }, { type = "B3" }, { type = "KO" } } })
	local AF = M(w, cast.arbiter, "ArenaFights")
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	assert(sheet, "F.New must reach Markets.Open")
	assert(cast.bank.ns.Markets.Sheet(fid, "L"), "the bank heard the event before its sheet")
	assert(cast.spectator.ns.Markets.Sheet(fid, "L"), "a bettor can reach the announced sheet immediately")
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "m"), true)
	eq(#sheet.order, 4)
	eq(sheet.markets[1].type, "MW"); eq(sheet.markets[2].type, "SW")
	eq(sheet.markets[3].type, "B3"); eq(sheet.markets[4].type, "KO")
	local ev = w:As(cast.arbiter, cast.arbiter.ns.Arena.EventOf, fid)
	eq(ev.arbiter, cast.arbiter.name, "the official is excluded by the sheet's authority matrix")

	Live(w, cast, fid)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0); assert(AF.NextRound(fid)); w:Run(0)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.B, cast.A)
	w:Run(0); assert(AF.NextRound(fid)); w:Run(0)
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(f.st, "R")
	local facts = w:As(cast.arbiter, cast.arbiter.ns.ArenaFights.Results, f)
	eq(facts.rounds, "ABA", "series markets receive the actual round sequence")
	eq(#facts.roundDetails, 3)
	w:Run(f.graceEnd - w.clock)
	eq(f.st, "F")
	sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(sheet.markets[1].state .. sheet.markets[1].result, "R1")
	eq(sheet.markets[2].state .. sheet.markets[2].result, "R1")
	eq(sheet.markets[3].state .. sheet.markets[3].result, "R2", "A won the series 2:1")
	eq(sheet.markets[4].state .. sheet.markets[4].result, "R1")
	eq(f.marketDone, true)
	local rev = sheet.rev
	w:As(cast.arbiter, cast.arbiter.ns.ArenaFights.Ended, f)
	w:As(cast.arbiter, cast.arbiter.ns.ArenaFights.Tick)
	eq(cast.arbiter.ns.Markets.Sheet(fid, "L").rev, rev, "replayed completion cannot settle twice")
	W3.NoErrors(w)
end)

test("1.2 integration: no bank means no false market marker; an open-slot fight opens its default winner market only after booking the second fighter", function()
	local w0, cast0 = W3.New({ more = { { "bank", N.bank } } })
	local AF0 = M(w0, cast0.arbiter, "ArenaFights")
	local fid0 = assert(AF0.New({ A = cast0.A.name, B = cast0.B.name }))
	assert(AF0.Announce(fid0), "the fight itself remains usable")
	local f0 = cast0.arbiter.ns.ArenaFights.Find("fights", fid0)
	eq(cast0.arbiter.ns.Markets.Sheet(fid0, "L"), nil)
	eq(cast0.arbiter.ns.ArenaFights.Has(f0.fl, "m"), false)
	eq(f0.marketWhy, "bank", "assignment/configuration failure is not a receipt or an open market")
	assert(cast0.king.Roles.SetBanks({ N.bank })); w0:Run(31)
	eq(cast0.arbiter.ns.ArenaFights.Has(f0.fl, "m"), true, "a newly available bank makes the announced market reachable")
	assert(cast0.arbiter.ns.Markets.Sheet(fid0, "L"), "the controller retries without requiring a duplicate announcement")

	local w, cast = WorldWithBank()
	local AF = M(w, cast.arbiter, "ArenaFights")
	local fid = assert(AF.New({ A = cast.A.name }))
	assert(AF.Announce(fid)); w:Run(0)
	eq(cast.arbiter.ns.Markets.Sheet(fid, "L"), nil, "there is no two-sided outcome before booking")
	assert(M(w, cast.B, "ArenaFights").Sign(fid)); w:Run(0)
	assert(AF.Book(fid, cast.B.name)); w:Run(0)
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	assert(sheet, "F.Book must reach Markets.Open")
	assert(cast.bank.ns.Markets.Sheet(fid, "L"), "the booked fighter reaches the bank before the sheet")
	eq(#sheet.order, 1); eq(sheet.markets[1].type, "MW")
	eq(cast.arbiter.ns.ArenaFights.Has(f.fl, "m"), true)
	W3.NoErrors(w0); W3.NoErrors(w)
end)

test("1.2 integration: cancelling a hosted fight refunds its real sheet instead of passing an internal fight reason as a market code", function()
	local w, cast = WorldWithBank()
	local fid = Booked(w, cast)
	local AF = M(w, cast.arbiter, "ArenaFights")
	assert(AF.Void(fid, "cancel"))
	local f = cast.arbiter.ns.ArenaFights.Find("fights", fid)
	local sheet = cast.arbiter.ns.Markets.Sheet(fid, "L")
	eq(f.st, "V"); eq(f.marketDone, true)
	eq(sheet.markets[1].state .. sheet.markets[1].result, "VX")
	W3.NoErrors(w)
end)

test("1.2 integration: the tournament route opens outright/reached markets, scratches a no-show, adds only field stage markets, closes at the draw and settles after promoter reload", function()
	local more = {}
	for i, name in ipairs({ "Aric Stone", "Bram Stone", "Cael Stone", "Dorn Stone", "Eska Stone", "Fenn Stone", "Garr Stone", "Hale Stone", "Iria Stone" }) do
		more[#more + 1] = { "e" .. i, name }
	end
	local w, cast = WorldWithBank(more)
	local king = cast.king
	local T = M(w, king, "ArenaTourney")
	local tid = assert(T.New({ title = "Reachable Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" }))
	w:Run(0)
	for i = 1, 9 do assert(M(w, cast["e" .. i], "ArenaTourney").Sign(tid)); w:Run(4) end
	local t = king.ns.ArenaTourney.Find(tid)
	assert(T.CloseRegistration(tid))
	w:Run(0)
	local sheet = king.ns.Markets.Sheet(tid, "L")
	assert(sheet, "T.CloseRegistration must reach Markets.Open")
	assert(cast.bank.ns.Markets.Sheet(tid, "L"), "the bank validates entrant numbers before the sheet")
	eq(sheet.size, nil, "the bracket size is not frozen before check-in")
	eq(sheet.markets[1].type, "CH"); eq(sheet.markets[2].type, "RF"); eq(sheet.markets[3].type, "RS"); eq(sheet.markets[4].type, "RQ")

	w.clock = t.tCheck + 1
	for _, i in ipairs({ 1, 3, 4, 9 }) do assert(M(w, cast["e" .. i], "ArenaTourney").CheckIn(tid)); w:Run(4) end
	w:Group({ king.name, cast.e1.name, cast.e3.name }, true)
	assert(T.StartDraw(tid))
	w:Run(0)
	sheet = king.ns.Markets.Sheet(tid, "L")
	eq(sheet.size, 4)
	eq(sheet.scratched[2], true, "the no-show's frozen entrant number is scratched")
	eq(sheet.scratched[5] and sheet.scratched[6] and sheet.scratched[7] and sheet.scratched[8], true, "unused waitlist entrants are scratched too")
	eq(#sheet.order, 8, "four event markets plus four actual-field stage markets before the bracket exists")
	local stageParams = {}
	for i = 5, 8 do stageParams[sheet.markets[i].value] = true end
	eq(stageParams[1] and stageParams[3] and stageParams[4] and stageParams[9], true)
	eq(stageParams[2], nil, "no stage market for the no-show")

	king.globals.RandomRoll = function(_, hi) king.rolled = hi end
	local state = w:As(king, king.ns.ArenaTourney.DrawState, t)
	for step = 1, state.total do
		local ok, got, hi = T.DrawStep(tid)
		eq(ok, true); eq(got, step)
		W3.Roll(w, { king, cast.e1, cast.e3 }, king, 1, 1, hi)
		w:Run(0)
	end
	eq(t.st, "L")
	sheet = king.ns.Markets.Sheet(tid, "L")
	eq(#sheet.order, 9); eq(sheet.markets[9].type, "PK", "the bracket pool appears only after the witnessed draw")
	eq(cast.bank.ns.Markets.Sheet(tid, "L").markets[9].type, "PK", "the bank heard the drawn bracket before PK")
	assert(sheet.lockAt >= w.clock, "the draw closes, rather than bypasses, the sheet")

	-- Pending settlement and the bracket both survive a real saved-data logout/login. LOGIN's
	-- Watch reconstructs the pending work from the unresolved canonical sheet.
	w:Logout(king); w:Login(king)
	T = M(w, king, "ArenaTourney")
	t = king.ns.ArenaTourney.Find(tid)
	sheet = king.ns.Markets.Sheet(tid, "L")
	assert(t and t.bracket and sheet)
	w:Run(math.max(0, sheet.lockAt - w.clock) + 1)
	for _ = 1, 8 do
		if t.st == "F" then break end
		for _, fid in pairs(t.bouts) do
			local f = king.ns.ArenaFights.Find("fights", fid)
			if f and f.st == "S" then assert(w:As(king, king.ns.ArenaFights.Walkover, fid, "A")) end
		end
		w:Run(6)
	end
	eq(t.st, "F")
	sheet = king.ns.Markets.Sheet(tid, "L")
	for _, idx in ipairs(sheet.order) do eq(sheet.markets[idx].state, "R", "market " .. idx .. " settled") end
	local facts = T.MarketResults(tid)
	eq(type(facts.champion), "number"); eq(#facts.finalists, 2); eq(#facts.semifinalists, 4)
	eq(#facts.quarterfinalists, 4, "a top-eight market settles from the four-person field left after scratches")
	assert(type(facts.bracket) == "string" and facts.bracket ~= "", "the settled bracket has a deterministic pick hex")
	eq(t.marketDone, true)
	local rev = sheet.rev
	assert(T.Advance(tid))
	eq(king.ns.Markets.Sheet(tid, "L").rev, rev, "a repeated bracket advance cannot settle twice")
	W3.NoErrors(w)
end)

test("1.2 integration: a finished tournament refunds only outcomes a both-absent final made unknowable", function()
	local more = {
		{ "e1", "Jora Flint" }, { "e2", "Kerr Flint" }, { "e3", "Lysa Flint" }, { "e4", "Marn Flint" },
		{ "e5", "Nera Flint" },
	}
	local w, cast = WorldWithBank(more)
	local king = cast.king
	local T = M(w, king, "ArenaTourney")
	local tid = assert(T.New({ title = "No Champion Cup", size = 4, tStart = w.clock + 7200, tReg = w.clock + 3000, bo = "1" }))
	w:Run(0)
	for i = 1, 5 do assert(M(w, cast["e" .. i], "ArenaTourney").Sign(tid)); w:Run(4) end
	assert(T.CloseRegistration(tid)); w:Run(0)
	local t = T.Find(tid)
	w.clock = t.tCheck + 1
	for i = 1, 4 do assert(M(w, cast["e" .. i], "ArenaTourney").CheckIn(tid)); w:Run(4) end
	w:Group({ king.name, cast.e1.name, cast.e2.name }, true)
	assert(T.StartDraw(tid)); w:Run(0)
	king.globals.RandomRoll = function(_, hi) king.rolled = hi end
	local state = w:As(king, king.ns.ArenaTourney.DrawState, t)
	for step = 1, state.total do
		local ok, got, hi = T.DrawStep(tid)
		eq(ok, true); eq(got, step)
		W3.Roll(w, { king, cast.e1, cast.e2 }, king, 1, 1, hi)
		w:Run(0)
	end

	local AF = M(w, king, "ArenaFights")
	for _, fid in pairs(t.bouts) do
		local f = AF.Find("fights", fid)
		if f and f.st == "S" then assert(AF.Walkover(fid, "A")) end
	end
	assert(T.Advance(tid)); w:Run(0)
	local finalFid = t.bouts[t.bracket.rounds .. ".1"]
	assert(finalFid and AF.Find("fights", finalFid).st == "S")
	assert(AF.Void(finalFid, "cancel"))
	assert(T.Advance(tid))
	eq(t.st, "F"); eq(T.Winner(tid), nil, "a both-absent final has no invented champion")

	local sheet = king.ns.Markets.Sheet(tid, "L")
	w:Run(math.max(0, sheet.lockAt - w.clock) + 1)
	T.Tick()
	sheet = king.ns.Markets.Sheet(tid, "L")
	local byType = {}
	for _, idx in ipairs(sheet.order) do
		local market = sheet.markets[idx]
		byType[market.type] = byType[market.type] or {}
		byType[market.type][#byType[market.type] + 1] = market
	end
	eq(byType.CH[1].state .. byType.CH[1].result, "VN", "champion is refunded as no data")
	eq(byType.PK[1].state .. byType.PK[1].result, "VN", "an incomplete bracket pick is refunded")
	eq(byType.RF[1].state, "R", "the two finalists remain deterministic")
	eq(byType.RS[1].state, "R", "the four semifinalists remain deterministic")
	for _, market in ipairs(byType.ST) do eq(market.state, "R", "each actual fighter's stage remains deterministic") end
	eq(t.marketDone, true)
	W3.NoErrors(w)
end)
