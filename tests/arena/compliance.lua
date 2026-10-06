-- 1.1.6, the compliance gate (Olympus/Compliance.lua): bets wait for 2.0 and the legal review,
-- region by region. The gate as it ships allows no wager anywhere; every betting path asks it and
-- refuses, the arena's wire neither sends nor takes a wager's message (a modified client's
-- included: here a client given the test row, where.compliance = "open"), the screens grey every
-- betting control with its line, and the games play without stakes. Last, the 1.1.6 package's TOC
-- (scripts/package.sh --release116: without the files scripts/bets-only.txt names) loads and plays.
-- On the test world (tests/arena/lib/world.lua) with World.New{ compliance = "shipped" }. Every
-- name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
-- A module of a client, its functions run as that client.
local function M(w, c, name) return W3.M(w, c, name) end
local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end

-- Compliance.lua alone, in a table of its own, with its words in that language.
local function Gate(locale)
	local L = setmetatable({}, { __index = function(_, k) return k end })
	local ns = { L = L }
	local saved = GetLocale
	GetLocale = function() return locale or "enUS" end
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "Locales/ComplianceText.lua"))("Olympus", ns)
		assert(loadfile(H.ADDON_DIR .. "Compliance.lua"))("Olympus", ns)
	end)
	GetLocale = saved
	if not ok then error(err, 0) end
	return ns.Compliance, L
end

print("1.1.6: the compliance gate")

test("1.1.6 compliance: as it ships, the gate allows no wager of any kind, on any game, for anyone; the wire's and the buttons' lists are wagers only; the line in English and pt-BR", function()
	local C, L = Gate()
	eq(next(C.REGIONS), nil, "no region's row")
	eq(select("#", C.Declared()) > 0 and C.Declared() or nil, nil, "no declared region")
	local kinds = 0
	for kind in pairs(C.KINDS) do
		kinds = kinds + 1
		local ok, why = C.Allows(kind)
		eq(ok, false, kind); eq(why, "compliance", kind)
		for game in pairs(C.GAMES) do eq(C.Allows(kind, game), false, kind .. " on " .. game) end
		eq(C.Waits(kind), L.COMPLIANCE_WAIT, kind)
		eq(C.Waits(kind, nil, true), L.COMPLIANCE_WAIT_SHORT, kind)
	end
	eq(kinds, 4, "a bet, a stake, a Lottery ticket, a payout")
	eq(C.Allows("anything"), false)
	-- Even a player who declares a region gets nothing: the table is empty.
	C.Declared = function() return "BR", 40 end
	for kind in pairs(C.KINDS) do eq(C.Allows(kind), false, kind) end
	-- The wire: every type it lists is refused, and those are wagers' only (the markets, a stake
	-- book, Bone Throw's held stakes and payments, the Lottery's winners, the Oracle).
	for kind, what in pairs(C.WIRE) do
		eq(C.Wire(kind), false, kind)
		assert(C.KINDS[what], kind .. ": " .. tostring(what))
	end
	for _, kind in ipairs({ "BM", "BS", "BK", "ZA", "KD", "KH", "LW", "IO" }) do assert(C.WIRE[kind], kind) end
	for _, kind in ipairs({ "AF", "AS", "AE", "AP", "KI", "KK", "KE", "ZT", "ZR", "ZH", "ZV", "AM", "EC" }) do eq(C.Wire(kind), true, kind) end
	for name in pairs(C.ACTIONS) do eq(C.Action(name), false, name) end
	for _, name in ipairs({ "fights.challenge", "farkle.create", "farkle.practice", "farkle.refund", "lottery.open", "lottery.schedule", "match.open" }) do
		eq(C.Action(name), true, name)
	end
	-- The line, both languages.
	local _, pt = Gate("ptBR")
	for _, key in ipairs({ "COMPLIANCE_WAIT", "COMPLIANCE_WAIT_SHORT", "COMPLIANCE_LOTTERY_PRACTICE" }) do
		local en, p = rawget(L, key), rawget(pt, key)
		assert(type(en) == "string" and en ~= "" and type(p) == "string" and p ~= "" and p ~= en, key)
	end
	assert(L.COMPLIANCE_WAIT:find("region by region", 1, true))
	assert(pt.COMPLIANCE_WAIT:find("região por região", 1, true))
	assert(L.COMPLIANCE_LOTTERY_PRACTICE:find("country by country", 1, true))
	for _, key in ipairs({ "ARENA_REFUSE_COMPLIANCE", "FARKLE_WHY_COMPLIANCE", "LOTTERY_WHY_COMPLIANCE", "MATCH_WHY_COMPLIANCE", "ARENA_WHY_COMPLIANCE" }) do
		eq(rawget(L, key), L.COMPLIANCE_WAIT, key); eq(rawget(pt, key), pt.COMPLIANCE_WAIT, key)
	end
	eq(rawget(L, "FARKLE_B_WHY_COMPLIANCE"), L.COMPLIANCE_WAIT_SHORT)
end)

test("1.1.6 compliance: the 2.0 seam: a region's row allows only its kinds and games, and only to a player of its age who declared it", function()
	local C = Gate()
	C.REGIONS = { BR = { minAge = 18, stake = { fight = true }, bet = true }, ["US-WA"] = { stake = true } }
	eq(C.Allows("stake", "fight"), false, "nobody declared a region")
	C.Declared = function() return "BR", 30 end
	eq(C.Allows("stake", "fight"), true); eq(C.Allows("stake", "bones"), false); eq(C.Allows("stake"), true, "some game")
	eq(C.Allows("bet", "lottery"), true); eq(C.Allows("lottery", "lottery"), false); eq(C.Allows("payout"), false)
	eq(C.Wire("ZA"), true); eq(C.Wire("LW"), false)
	C.Declared = function() return "BR", 16 end
	eq(C.Allows("stake", "fight"), false, "under the row's age")
	C.Declared = function() return "US-WA" end
	eq(C.Allows("lottery"), false, "a region with no lottery at all")
	eq(C.Allows("stake", "bones"), true)
	C.Declared = function() return "XX", 40 end
	eq(C.Allows("stake"), false, "a region the table does not list")
end)

test("1.1.6 compliance: on the wire, a 1.1.6 client sends no wager's message and drops every one a modified client sends it", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client(N.bettor1)
	local evil = w:Client(N.bettor2, { compliance = "open" })
	local C = a.ns.Compliance
	assert(C, "the gate loads with the arena's files")
	local types = {}
	for kind in pairs(C.WIRE) do types[#types + 1] = kind end
	table.sort(types)
	for _, kind in ipairs(types) do
		local ok, why = w:As(a, a.ns.Arena.Send, kind, "T", "x", { to = evil.name })
		eq(ok, false, kind); eq(why, "compliance", kind)
		eq(w:As(a, a.ns.Arena.Refusal, kind, "T", { to = evil.name }), "compliance", kind)
		assert(w:As(a, a.ns.Arena.Handles, kind), kind .. " has a handler on the 1.1.6 client: the gate drops it, not a missing file")
	end
	w:Run(0)
	eq(#w:Sent({ from = a }), 0, "nothing went")
	local before = w:As(a, a.ns.Arena.Stats).dropped.compliance or 0
	for _, kind in ipairs(types) do assert(w:As(evil, evil.ns.Arena.Send, kind, "T", "x", { to = a.name }), kind) end
	w:Run(0)
	eq(#w:Sent({ from = evil }), #types, "the modified client sent them all")
	eq((w:As(a, a.ns.Arena.Stats).dropped.compliance or 0) - before, #types, "each dropped by the gate")
	-- A type that is not a wager goes as before.
	assert(w:As(a, a.ns.Arena.Send, "AP", "T", "x", { to = evil.name }))
	NoErrors(w)
end)

test("1.1.6 compliance: fights: a stake is refused (nothing sent), a modified client's staked challenge or arbiter's ask is never taken, no market opens on a public fight, and a fight without a stake goes on", function()
	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	local arb = w:Role("arbiter")
	local a = w:Role("fighterA")
	local evil = w:Role("fighterB", { compliance = "open" })
	W3.Live(w, king)
	for _, c in ipairs(w.clients) do W3.Rules(w, c) end
	W3.Money(w, evil)
	-- This client's own stake: refused before anything goes, in the action's words.
	local ok, why = M(w, a, "ArenaFights").CanChallenge(evil.name, { stake = 10000, how = "d", cur = "g" })
	eq(ok, false); eq(why, "compliance")
	eq(select(2, w:As(a, a.ns.Arena.Can, "fights.challenge", evil.name, { stake = 10000, how = "d", cur = "g" })), "compliance")
	eq(select(2, M(w, a, "ArenaFights").Challenge(evil.name, { stake = 10000, how = "d", cur = "g" })), "compliance")
	eq(select(2, M(w, a, "ArenaMatch").StakedFor("d", 10000, evil.name)), "compliance", "matchmaking offers no staked duel")
	eq(#w:Sent({ from = a, type = "AS" }), 0)
	-- A modified client's staked challenge: dropped on arrival, no challenge, no answer.
	local oid = assert(M(w, evil, "ArenaFights").Challenge(a.name, { stake = 10000, how = "d", cur = "g" }))
	w:Run(0)
	eq(#w:Sent({ from = evil, type = "AS" }), 1)
	eq(a.ns.ArenaFights.challenges[oid], nil, "never taken")
	eq(#w:Sent({ from = a, type = "AS" }), 0, "nothing said back")
	-- ...nor its ask to an arbiter to hold the stakes (AS~Q).
	w:Run(5)
	local qid = w:As(evil, evil.ns.Arena.NewId, "F", function() return false end)
	assert(w:As(evil, evil.ns.Arena.Send, "AS", "L", table.concat({ qid, "Q", evil.short, a.short, evil.ns.Arena.B36(100), "1" }, "~"), { to = arb.name }))
	w:Run(0)
	eq(arb.ns.ArenaFights.challenges[qid], nil, "the arbiter holds no stake")
	-- A public fight: no market.
	local AF = M(w, arb, "ArenaFights")
	local fid = assert(AF.New({ A = a.name, B = evil.name, bo = 1 }))
	local f = AF.Find("fights", fid)
	eq(f.marketSpecs, nil, "no market asked")
	eq(select(2, M(w, arb, "Markets").Open(fid, { markets = { { type = "MW" } } })), "compliance")
	eq(select(2, AF.New({ A = a.name, B = evil.name, bo = 1, stake = 10000, stakes = true })), "compliance")
	assert(AF.Announce(fid))
	w:Run(0)
	eq(#w:Sent({ from = arb, type = "BM" }), 0)
	-- Stakes and their payouts, asked directly.
	eq(select(2, M(w, arb, "Stakes").Open({ id = "F1", kind = "fight", A = { name = a.name }, B = { name = evil.name }, stake = { A = 10000, B = 10000 }, arbiter = arb.name })), "compliance")
	eq(select(2, M(w, a, "Stakes").Direct({ id = "F1", loser = a.name, winner = evil.name, copper = 10000 })), "compliance")
	-- A challenge without a stake: taken, answered, the fight made on both sides.
	w:Run(5)
	local casual = assert(M(w, evil, "ArenaFights").Challenge(a.name, { bo = 1 }))
	w:Run(0)
	assert(a.ns.ArenaFights.challenges[casual], "a casual challenge is taken")
	assert(M(w, a, "ArenaFights").Answer(casual, true))
	w:Run(0)
	assert(a.ns.ArenaFights.Find("fights", casual), "the fight is made")
	assert(evil.ns.ArenaFights.Find("fights", casual))
	NoErrors(w)
end)

-- Bone Throw's world: a 1.1.6 player and a modified one (o.allShipped: a 1.1.6 one too), saved
-- data proven kept (a logout and a login), the rules said yes to, grouped at the inn; no screens
-- loaded by the game (their tests load them themselves: H.LoadCompanion).
local function Bones(o)
	o = o or {}
	local w = FW.New({ compliance = "shipped", arenaFiles = o.files })
	local a = w:Player(N.fighterA)
	local evil = w:Player(N.fighterB, { compliance = o.allShipped and nil or "open" })
	for _, c in ipairs({ a, evil }) do w:Logout(c); w:Login(c) end
	FW.Extend(w, a); FW.Extend(w, evil)
	for _, c in ipairs({ a, evil }) do w:As(c, function() c.ns.Arena.SetRules(true) end) end
	w:Group({ a, evil })
	w:AtInn(a.name, evil.name)
	return w, a, evil
end

test("1.1.6 compliance: Bone Throw: a stake or the crowd's bets are refused, a modified client's staked invitation and betting table are never taken; a game without a stake and the House's play", function()
	local w, a, evil = Bones()
	local FT = function(c) return M(w, c, "FarkleTable") end
	eq(FT(a).StakeWhy("o", 10000), "compliance")
	eq(select(2, FT(a).CanCreate({ guest = evil.name, stake = 10000, mode = "d", src = "o", target = 2000, rehearsal = true })), "compliance")
	eq(select(2, w:As(a, a.ns.Arena.Can, "farkle.create", { guest = evil.name, stake = 10000, mode = "d", src = "o", target = 2000 })), "compliance")
	eq(select(2, FT(a).CanCreate({ guest = evil.name, mode = "a", arbiter = N.arbiter, spectators = true, crowd = true, target = 2000 })), "compliance")
	for _, action in ipairs({ "farkle.staked", "farkle.pay", "farkle.paystake", "farkle.payfee", "farkle.payout" }) do
		eq(select(2, w:As(a, a.ns.Arena.Can, action, "K1")), "compliance", action)
	end
	eq(select(2, M(w, a, "ArenaMatch").StakedFor("b", 10000, evil.name)), "compliance")
	-- The modified client's staked invitation: dropped, no table, no popup, no answer.
	evil.ns.Standing.Cap = function() return 500000 end
	local id, why = FT(evil).Create({ guest = a.name, stake = 10000, mode = "d", src = "o", target = 2000, rehearsal = true })
	assert(id, "the modified client's own table: " .. tostring(why))
	w:Run(0)
	eq(#w:Sent({ from = evil, type = "KI" }), 1)
	eq(a.ns.FarkleTable.Get(id), nil, "a staked invitation is never taken")
	eq(#w:Sent({ from = a, type = "KA" }), 0)
	-- Asked to hold a betting table (KO with a stake, or the crowd's bets): nothing.
	local B36 = a.ns.Arena.B36
	for i, body in ipairs({ ("Kzz%d~%s~%s~%s~5~oo~1o~1"):format(1, evil.name, N.bettor3, B36(10000)),
		("Kzz%d~%s~%s~0~5~--~1o~1~1"):format(2, evil.name, N.bettor3) }) do
		assert(w:As(evil, evil.ns.Arena.Send, "KO", "T", body, { to = a.name }), body)
		w:Run(0)
		eq(a.ns.FarkleTable.Get("Kzz" .. i), nil, body)
	end
	eq(#w:Sent({ from = a, type = "KP" }), 0, "no answer to either")
	-- (The modified client's own invitation lapses unanswered.)
	w:Run(65)
	-- A game without a stake: invited, taken, opened, played.
	local free = assert(FT(evil).Create({ guest = a.name, target = 2000, rehearsal = true }))
	w:Run(0)
	assert(a.ns.FarkleTable.Get(free), "a game without a stake is taken")
	assert(FT(a).Answer(free, true))
	w:Run(0)
	w:QueueRoll(evil.name, 90); w:QueueRoll(a.name, 10)
	FT(evil).Roll(free); FT(a).Roll(free)
	w:Run(0)
	eq(a.ns.FarkleTable.Get(free).state, "play")
	assert(FT(a).Concede(free))
	w:Run(0)
	local live = a.ns.FarkleTable.Live()
	assert(not live, live and (live.id .. " " .. live.state .. " " .. tostring(live.role)))
	-- Practice against the House.
	local house = assert(FT(a).Practice({ target = 2000 }))
	eq(a.ns.FarkleTable.Get(house).role, "practice")
	assert(a.ns.FarkleTable.Close(house))
	-- A table its modified host opens with the crowd's bets (KG's flag): the 1.1.6 guest never joins it.
	w:Run(31)
	local crowd = assert(FT(evil).Create({ guest = a.name, target = 2000, rehearsal = true }))
	w:Run(0)
	local send = evil.ns.Arena.Send
	evil.ns.Arena.Send = function(kind, mode, body, o)
		if kind == "KG" then body = body .. "~1" end -- (its ninth field: the crowd's bets)
		return send(kind, mode, body, o)
	end
	assert(FT(a).Answer(crowd, true))
	w:Run(0)
	evil.ns.Arena.Send = send
	local kg = w:Sent({ from = evil, type = "KG" })
	assert(kg[#kg].msg:find("~1$"), "the host opened it with the crowd's bets")
	local t = a.ns.FarkleTable.Get(crowd)
	assert(t.state ~= "open" and t.state ~= "play", "never joined: " .. tostring(t.state))
	eq(t.crowd, nil)
	NoErrors(w)
end)

test("1.1.6 compliance: the Lottery: no ticket, no day opened, no draw paid; the board and its practice table say a compliance review is under way, practice first, and the practice draw plays", function()
	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	local a = w:Client(N.bettor1)
	W3.Live(w, king)
	W3.Rules(w, a)
	local ok, why = M(w, king, "Lottery").SetSchedule({ on = true })
	eq(ok, false); eq(why, "compliance")
	assert(Printed(king, king.ns.L.COMPLIANCE_WAIT), "the King is told why")
	eq(king.ns.Lottery.Schedule().on, false, "the schedule stays off")
	w:Run(60)
	for _, kind in ipairs({ "BM", "BO", "LW" }) do eq(#w:Sent({ type = kind }), 0, "no day's sheet, book or winners: " .. kind) end
	eq(select(2, M(w, a, "Lottery").CanBet(1, 100)), "compliance")
	eq(select(2, M(w, a, "Lottery").Bet(1, 100)), "compliance")
	eq(select(2, w:As(a, a.ns.Arena.Can, "lottery.bet", 1, 100)), "compliance")
	eq(select(2, w:As(a, a.ns.Arena.Can, "lottery.draw")), "compliance")
	eq(select(2, M(w, king, "Lottery").CanDraw()), "compliance")
	-- The screens.
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, L = own.ArenaUI, a.ns.L
	local board = w:As(a, UI.LotteryModel)
	eq(board.compliance, L.COMPLIANCE_LOTTERY_PRACTICE)
	assert(board.line:find(L.COMPLIANCE_LOTTERY_PRACTICE, 1, true), "the board's line says why")
	eq(board.bet.can, false); eq(board.bet.why, L.COMPLIANCE_WAIT, "its Bet greyed with the line")
	eq(UI.Panes("lottery")[1].key, "lottery.practice", "practice comes first")
	eq(w:As(a, UI.LotteryPracticeModel).compliance, L.COMPLIANCE_LOTTERY_PRACTICE)
	assert(w:As(a, UI.LotteryPracticePick, 7))
	local result = w:As(a, UI.LotteryPracticeDraw, { 1, 5, 9, 13, 17 })
	eq(#result.rows, 5); assert(result.result)
	-- (1.1.6's games' ledger: the draw is a game of his, told to the King, an auditor heard; nothing
	-- else goes, no ticket, no market)
	w:Run(5)
	eq(#w:Sent({ from = a, type = "AY", to = king.name }), 1, "its record, to the King")
	for _, s in ipairs(w:Sent({ from = a })) do
		eq(s.msg:sub(1, 2), "AY", "practice sends only its record to the auditors: " .. s.msg)
		eq(s.target and s.target:lower(), king.name:lower())
	end
	NoErrors(w)
end)

test("1.1.6 compliance: the screens: the bet slip and a Staked challenge are greyed with the line, the challenge opens casual", function()
	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	local a = w:Role("fighterA")
	local b = w:Role("fighterB")
	W3.Live(w, king)
	for _, c in ipairs(w.clients) do W3.Rules(w, c) end
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, L = own.ArenaUI, a.ns.L
	local slip = w:As(a, UI.SlipModel, "Fzz1", 1, "A", 10)
	eq(slip.ok, false); eq(slip.why, "compliance"); eq(slip.whyText, L.COMPLIANCE_WAIT)
	w:As(a, UI.Challenge, b.name, { stake = 10000 })
	local m = UI.lastChallenge
	eq(m.stake, 0, "a stake the hand-off asked opens casual"); eq(m.ok, true)
	assert(UI.ChallengeFrame().note:GetText():find(L.COMPLIANCE_WAIT, 1, true), "the note says why")
	NoErrors(w)
end)

test("1.1.6 compliance: the Arena's betting panels are hidden behind the gate: an event's markets panel, the King's overlay's bets countdown, its last call, its bets-closed stamp and its payouts; a build the gate allows shows them", function()
	for _, shipped in ipairs({ true, false }) do
		local w = World.New({ compliance = shipped and "shipped" or nil })
		local king = w:Role("king")
		local arb = w:Role("arbiter")
		local a = w:Role("fighterA")
		local b = w:Role("fighterB")
		W3.Live(w, king)
		for _, c in ipairs(w.clients) do W3.Rules(w, c) end
		local AF = M(w, arb, "ArenaFights")
		local fid = assert(AF.New({ A = a.name, B = b.name, bo = 1 }))
		assert(AF.Announce(fid))
		w:Run(0)
		M(w, a, "ArenaFights").Accept(fid)
		M(w, b, "ArenaFights").Accept(fid)
		w:Run(0)
		-- (called, both at the ring, the bell: the fight's lock, the last call before it)
		W3.Stand(arb, 100, 100); W3.Stand(a, 110, 100); W3.Stand(b, 100, 120)
		W3.Sees(arb, { [a] = true, [b] = true })
		assert(AF.Call(fid))
		w:Run(0)
		M(w, a, "ArenaFights").Here(fid); M(w, b, "ArenaFights").Here(fid)
		w:Run(1)
		assert(AF.Bell(fid))
		w:Run(0)
		local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
		local UI = own.ArenaUI
		eq(w:As(a, UI.BetsShown, "fight"), not shipped)
		local canvas = CreateFrame("Frame")
		w:As(a, function() UI.Pane("arena.events").detail(canvas, { key = "arena.events", sel = fid }) end)
		if shipped then eq(rawget(canvas, "markets"), nil, "no markets panel")
		else assert(rawget(canvas, "markets"), "the markets panel where bets may be") end
		local ev = w:As(a, function() return UI.Data.Event(fid) end)
		local m = w:As(a, UI.Overlay.Model, fid)
		assert(ev.lockAt, "the fight has its lock")
		if shipped then eq(m.closesAt, nil, "no BETS CLOSE IN") else eq(m.closesAt, ev.lockAt) end
		eq(w:As(a, UI.Overlay.Model, fid, "LIVE").stamp, (not shipped) and a.ns.L.ARENA_OVERLAY_CLOSED or nil, "BETS CLOSED")
		eq(w:As(a, UI.Overlay.Model, fid, "PAYOUTS").mode, shipped and "RESULT" or "PAYOUTS", "the King's payouts pin")
		-- (review of 1.1.6) The bets' last call: a fight about to lock is still the tape, and the King's
		-- pin on it stamps no LAST CALL.
		local now = w:As(a, a.ns.Arena.Now)
		eq(w:As(a, UI.Overlay.ModeOf, { kind = "fight", public = true, lockAt = now + 5 }), shipped and "TAPE" or "LASTCALL", "LAST CALL")
		eq(w:As(a, UI.Overlay.ModeOf, { kind = "fight", public = true, state = "Z" }), shipped and "TAPE" or "LASTCALL")
		local lc = w:As(a, UI.Overlay.Model, fid, "LASTCALL")
		eq(lc.mode, shipped and "TAPE" or "LASTCALL"); eq(lc.stamp, (not shipped) and a.ns.L.ARENA_OVERLAY_LASTCALL or nil, "the LAST CALL stamp")
		NoErrors(w)
	end
end)

test("1.1.6 compliance: a bank that turns to the table as it ships with a market from before (an open build's): it takes no slip and pays no winner", function()
	local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/markets-world.lua"))(H)
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	assert(t.arbiter.M.Open(eid, { markets = { { type = "MW" } } }))
	w:Run(0)
	assert(t.b1.M.Bet(eid, 1, 1, 1000)); assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(0)
	local C = t.bank.ns.Compliance
	local open = C.REGIONS
	C.REGIONS = {}
	eq(w:As(t.bank, t.bank.ns.MarketBank.Check, "L", t.b3.name, eid, 1, "1", 1000, "n09999"), "U", "the bank takes no slip")
	C.REGIONS = open
	w:Run(200)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(0)
	C.REGIONS = {}
	w:Run(302)
	eq(w:Balance(t.bank, t.b1), 900000, "no winner paid")
	assert(t.b3.M.View(eid).markets[1].state ~= "S", "not settled")
	w:NoErrors()
end)

test("1.1.6 compliance: an arbiter who turns to the table as it ships, holding a match's stakes from before: no winner paid, its void still refunds each stake", function()
	local W1 = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
	local G = 10000
	local w = World.New()
	local cast = W1.Cast(w, { duty = false })
	local arb = W1.Role(w, "arbiter")
	local torvin, selka = W1.Client(w, "Torvin Hale", { money = 50000 }), W1.Client(w, "Selka Drummond", { money = 50000 })
	for _, c in ipairs({ arb, torvin, selka }) do W1.Relog(w, c) end
	assert(cast.king.Roles.SetArbiters({ { name = N.arbiter, cap = 2 } }))
	w:Run(301)
	local t = { id = "F1s", kind = "fight", A = { name = torvin.name }, B = { name = selka.name }, stake = { A = 1 * G, B = 1 * G }, arbiter = N.arbiter }
	for _, c in ipairs({ arb, torvin, selka }) do assert(c.Stakes.Open(t)) end
	w:Trade(torvin, arb, { aGives = 1 * G })
	w:Trade(selka, arb, { aGives = 1 * G })
	w:Run(5)
	eq(arb.Stakes.Held("F1s").both, true)
	arb.ns.Compliance.REGIONS = {}
	local lines, why = arb.Stakes.Result("F1s", "A")
	eq(lines, nil); eq(why, "compliance")
	for _, o in ipairs(arb.Debts.Open()) do assert(o.kind ~= "p" and o.kind ~= "f", "no payout or fee owed: " .. tostring(o.kind)) end
	local back = assert(arb.Stakes.Result("F1s", "V"))
	eq(#back, 2); eq(back[1].kind, "refund"); eq(back[2].kind, "refund")
	eq(back[1].copper + back[2].copper, 2 * G)
	NoErrors(w)
end)

print("1.1.6: the package without the files only the bets need")

-- The files scripts/bets-only.txt names (the 1.1.6 package leaves them out).
local function BetsOnly()
	local out = {}
	for line in io.lines(H.ROOT .. "scripts/bets-only.txt") do
		line = line:gsub("\r$", "")
		if line ~= "" and line:sub(1, 1) ~= "#" then out[#out + 1] = line end
	end
	return out
end
-- The core's arena files as the 1.1.6 package's TOC lists them (World.ARENA_FILES less those).
local function Files116()
	local gone = {}
	for _, path in ipairs(BetsOnly()) do
		local file = path:match("^Olympus/([%w_]+)%.lua$")
		if file then gone[file] = true end
	end
	local out = {}
	for _, f in ipairs(World.ARENA_FILES) do if not gone[f] then out[#out + 1] = f end end
	return out, gone
end


test("1.1.6 package: scripts/bets-only.txt names files that only carry wagers' types and are in the TOC; their TOC (scripts/package.sh --release116) loads and plays: logins, a fight, Bone Throw with and without the House, the Lottery's practice", function()
	local files, gone = Files116()
	local listed = BetsOnly()
	assert(#listed >= 1, "bets-only.txt names a file")
	local toc = {}
	for line in io.lines(H.ADDON_DIR .. "Olympus.toc") do toc[(line:gsub("\r$", ""))] = true end
	local C = Gate()
	for _, path in ipairs(listed) do
		local file = assert(path:match("^Olympus/([%w_]+)%.lua$"), path .. ": a file of the core")
		assert(toc[file .. ".lua"], path .. " in Olympus.toc")
		local f = assert(io.open(H.ADDON_DIR .. file .. ".lua"))
		local code = f:read("*a"):gsub("%-%-[^\n]*", "")
		f:close()
		for kind in code:gmatch('Comm%.Handle%("(%w%w)"') do assert(C.WIRE[kind], path .. " registers " .. kind .. ", not a wager's type") end
		for name in code:gmatch('Arena%.Action%("([%w%.]+)"') do assert(C.ACTIONS[name] or name == "overrule" or name == "closebets", path .. " registers the action " .. name) end
	end
	assert(gone.Markets and gone.MarketBank, "the markets and the bank's half")
	for _, f in ipairs({ "Compliance", "Lottery", "Stakes", "Wallet", "FarkleTable", "ArenaFights", "Honors" }) do
		local found = false
		for _, g in ipairs(files) do if g == f then found = true end end
		assert(found, f .. " ships in 1.1.6")
	end
	-- The arena's clients on that TOC: they log in clean, with no market.
	local w, a, evil = Bones({ files = files, allShipped = true })
	local king = w:Role("king", { companion = { state = "missing" } })
	local arb = w:Role("arbiter", { companion = { state = "missing" } })
	FW.Extend(w, king); FW.Extend(w, arb)
	W3.Live(w, king)
	for _, c in ipairs(w.clients) do
		eq(c.ns.Markets, nil, c.name); eq(c.ns.MarketBank, nil, c.name)
		assert(c.ns.Compliance and c.ns.Stakes and c.ns.Lottery, c.name)
		W3.Rules(w, c)
	end
	NoErrors(w)
	-- A public fight, announced and accepted; a direct one from a challenge.
	local AF = M(w, arb, "ArenaFights")
	local fid = assert(AF.New({ A = a.name, B = evil.name, bo = 1 }))
	assert(AF.Announce(fid))
	w:Run(0)
	M(w, a, "ArenaFights").Accept(fid)
	M(w, evil, "ArenaFights").Accept(fid)
	w:Run(31)
	eq(#w:Sent({ type = "BM" }), 0)
	local oid = assert(M(w, evil, "ArenaFights").Challenge(a.name, { bo = 1 }))
	w:Run(0)
	assert(M(w, a, "ArenaFights").Answer(oid, true))
	w:Run(0)
	assert(a.ns.ArenaFights.Find("fights", oid), "the direct fight is made")
	eq(select(2, M(w, a, "ArenaFights").Challenge(evil.name, { stake = 10000, how = "d", cur = "g" })), "compliance")
	-- Bone Throw without a stake, and against the House.
	local FT = function(c) return M(w, c, "FarkleTable") end
	local free = assert(FT(evil).Create({ guest = a.name, target = 2000, rehearsal = true }))
	w:Run(0)
	assert(FT(a).Answer(free, true))
	w:Run(0)
	w:QueueRoll(evil.name, 90); w:QueueRoll(a.name, 10)
	FT(evil).Roll(free); FT(a).Roll(free)
	w:Run(0)
	eq(a.ns.FarkleTable.Get(free).state, "play")
	assert(FT(a).Concede(free))
	w:Run(0)
	assert(FT(a).Practice({ target = 2000 }))
	-- The Lottery: no day, its screens and its practice.
	eq(select(2, M(w, king, "Lottery").SetSchedule({ on = true })), "compliance")
	eq(select(2, M(w, a, "Lottery").CanBet(1, 100)), "compliance")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	eq(w:As(a, UI.LotteryModel).bet.can, false)
	eq(UI.Panes("lottery")[1].key, "lottery.practice")
	assert(w:As(a, UI.LotteryPracticePick, 3))
	eq(#w:As(a, UI.LotteryPracticeDraw, { 2, 4, 6, 8, 10 }).rows, 5, "a free practice ticket: no stake to choose")
	-- The bet slip: no markets to bet on.
	eq(w:As(a, UI.SlipModel, fid, 1, "A", 10).ok, false)
	w:Run(120)
	NoErrors(w)
end)

-- 1.1.6: no arbiters without bets (an arbiter is there for the money: the stakes he holds, the
-- bets on what he judges). As it ships, nothing asks for one, shows one or waits on one.
test("1.1.6 compliance: no arbiters without a wager: the gate's rule; a challenge asked with an arbiter goes direct, no ask to judge is taken, no arbiter's action", function()
	local C = Gate()
	eq(C.Arbiters(), false, "as it ships")
	C.Declared = function() return "TEST", 30 end
	C.REGIONS = { TEST = { stake = true } }
	eq(C.Arbiters(), true, "a region that allows a stake has arbiters")
	C.REGIONS = { TEST = { bet = { bones = true } } }
	eq(C.Arbiters(), true, "...and one that allows the crowd's bets")
	C.REGIONS = { TEST = { lottery = true } }
	eq(C.Arbiters(), false, "a Lottery ticket needs none")
	eq(C.Action("fights.judge"), false); eq(C.Action("fights.challenge"), true)

	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	local arb = w:Role("arbiter")
	local a = w:Role("fighterA")
	local evil = w:Role("fighterB", { compliance = "open" })
	W3.Live(w, king)
	for _, c in ipairs(w.clients) do W3.Rules(w, c) end
	eq(arb.ns.ArenaRoles.IsArbiter(arb.name, "L"), true, "a signed arbiter, whose role stays for 2.0")
	-- The arbiter's own actions are refused before their rule, in the gate's words.
	for _, action in ipairs({ "fights.new", "fights.judge", "arbiter.duty", "card.arbiter", "tourney.arbiter" }) do
		eq(select(2, w:As(arb, arb.ns.Arena.Can, action)), "compliance", action)
	end
	-- A challenge asked "with an arbiter" goes direct: it names none and waits on none.
	local AF = M(w, a, "ArenaFights")
	local oid = assert(AF.Challenge(evil.name, { bo = 1, how = "a", arbiter = arb.name }))
	local c = a.ns.ArenaFights.challenges[oid]
	eq(c.how, "d"); eq(c.arbiter, nil)
	eq(select(2, AF.AskArbiter(oid, arb.name)), "compliance")
	w:Run(0)
	local sent = w:Sent({ from = a, type = "AS" })
	assert(sent[#sent] and sent[#sent].msg:find(oid .. "~X~1~0~d~-~", 1, true), sent[#sent] and sent[#sent].msg)
	assert(M(w, evil, "ArenaFights").Answer(oid, true))
	w:Run(0)
	local f = assert(a.ns.ArenaFights.Find("fights", oid), "the fight is made at the yes")
	eq(f.arb, nil, "between the two fighters")
	eq(#w:Sent({ to = arb.name }), 0, "the arbiter is never asked")
	-- A modified client's challenge that waits on an arbiter: never taken.
	w:Run(5)
	local evilOid = assert(M(w, evil, "ArenaFights").Challenge(a.name, { bo = 1, how = "a", arbiter = arb.name }))
	w:Run(0)
	eq(a.ns.ArenaFights.challenges[evilOid], nil, "never taken")
	-- ...nor its ask to an arbiter to judge a fight without a stake (AS~Q): no fight, no answer.
	w:Run(5)
	local qid = w:As(evil, evil.ns.Arena.NewId, "F", function() return false end)
	assert(w:As(evil, evil.ns.Arena.Send, "AS", "L", table.concat({ qid, "Q", evil.short, a.short, "0", "1" }, "~"), { to = arb.name }))
	w:Run(0)
	eq(arb.ns.ArenaFights.challenges[qid], nil, "the arbiter judges nothing")
	eq(#w:Sent({ from = arb, type = "AS" }), 0, "nothing said back")
	NoErrors(w)
end)

test("1.1.6 compliance: no arbiters without a wager: Bone Throw: no table by an arbiter, a modified client's invitation that waits on one or its ask to hold a table is never taken", function()
	local w, a, evil = Bones()
	local FT = function(c) return M(w, c, "FarkleTable") end
	eq(select(2, FT(a).CanCreate({ guest = evil.name, mode = "a", arbiter = N.arbiter, target = 2000 })), "compliance", "without a stake too")
	eq(select(2, FT(a).CanCreate({ guest = evil.name, mode = "a", arbiter = N.arbiter, target = 2000, rehearsal = true })), "compliance")
	-- An invitation to a table an arbiter holds, without a stake (KI kind a): dropped, no answer.
	assert(w:As(evil, evil.ns.Arena.Send, "KI", "T", ("Kzz7~a~0~5~%s~-~1o~1~ab12"):format(N.arbiter), { to = a.name }))
	w:Run(0)
	eq(a.ns.FarkleTable.Get("Kzz7"), nil, "never taken")
	eq(#w:Sent({ from = a, type = "KA" }), 0, "no answer")
	-- An arbiter asked to hold a table without a stake or the crowd's bets (KO): nothing.
	local arb = w:Player(N.arbiter)
	assert(w:As(evil, evil.ns.Arena.Send, "KO", "T", ("Kzz8~%s~%s~0~5~--~1o~1"):format(evil.name, a.name), { to = arb.name }))
	w:Run(0)
	eq(arb.ns.FarkleTable.Get("Kzz8"), nil, "no arbiter's table")
	eq(#w:Sent({ from = arb, type = "KP" }), 0, "no answer")
	NoErrors(w)
end)

test("1.1.6 compliance: no arbiters without a wager: the screens: no Arbiter page, no arbiters' list or arbiter's lines in the Games tab, no arbiter in the challenge, no Arbiter's preview; a build the gate allows has them", function()
	for _, shipped in ipairs({ true, false }) do
		local w = World.New({ compliance = shipped and "shipped" or nil })
		local king = w:Role("king")
		local author, b = w:Role("author"), w:Role("fighterB")
		local lida = w:Client("Lida Fenn")
		W3.Live(w, king)
		for _, c in ipairs(w.clients) do W3.Rules(w, c) end
		assert(king.Roles.SetArbiters({ { name = lida.name, cap = 5 } }))
		w:Run(0)
		local L = lida.ns.L
		local function Find(lines, text)
			for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return l end end
			return nil
		end
		local on = not shipped
		w:As(lida, function()
			local AH = lida.ns.ArenaHome
			eq(AH.ArbitersOn(), on)
			eq(AH.IsArbiterHere(), true, "listed by the King's word, his role kept")
			eq(AH.ArbiterShown(), on)
			local lines = AH.TabLines()
			eq(Find(lines, L.ARENA_GAMES_CONSOLE) ~= nil, on, "the console line")
			eq(Find(lines, L.ARENA_GAMES_NEW_FIGHT) ~= nil, on, "a new fight")
			local own = H.LoadCompanion(lida.ns)
			local UI = own.ArenaUI
			eq(UI.ArbiterVisible(), on, "the Arbiter page")
			-- A challenge a hand-off asks with an arbiter.
			UI.Challenge(b.name, { how = "a", arbiter = N.arbiter })
			local m = UI.lastChallenge
			eq(m.how, on and "a" or "d"); eq(m.arbiter, on and N.arbiter or nil)
			eq(UI.ChallengeFrame().how.buttons[2]:IsShown(), false, "casual: no way to hold a stake either way")
		end)
		w:As(king, function()
			local lines = king.ns.ArenaHome.TabLines()
			eq(Find(lines, (L.ARENA_GAMES_ARBITERS:gsub("%%d.*$", ""))) ~= nil, on, "the arbiters' list in the staff section")
			eq(Find(lines, L.ARENA_GAMES_CONSOLE) ~= nil, on, "the King is a public arbiter: his console line")
		end)
		w:As(author, function()
			assert(loadfile(H.ADDON_DIR .. "ViewAs.lua"))("Olympus", author.ns)
			local VA = author.ns.ViewAs
			eq(VA.Offered("arbiter"), on); eq(VA.Set("arbiter"), on, "the Arbiter's preview")
			assert(VA.Set("my"))
			local ok, menu = VA.ShowMenu()
			assert(ok, "the menu")
			for i, key in ipairs(VA.OPTIONS) do
				eq(menu.buttons[i]:IsShown(), key ~= "arbiter" or on, key)
			end
		end)
		NoErrors(w)
	end
end)
