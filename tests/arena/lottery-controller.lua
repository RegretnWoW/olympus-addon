-- The Lottery's daily controller over the real Markets/MarketBank code and the wallet stand-in
-- used by the markets suite. These tests cover reachability; Lottery.lua's pure contract tests
-- separately prove the five-place arithmetic and its randomized conservation invariant.
local H = ...
local test, eq = H.test, H.eq
local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/markets-world.lua"))(H)

local function Module(w, c, name)
	return setmetatable({}, { __index = function(_, key)
		local value = c.ns[name][key]
		if type(value) == "function" then return function(...) return w:As(c, value, ...) end end
		return value
	end })
end

local function BindLottery(w)
	-- markets-world supplies generic fixture events. The daily controller generates its own ids,
	-- so its production event resolver must own L for these integration tests.
	for _, c in ipairs(w.clients) do
		w:As(c, c.ns.Arena.Events.Register, "L", c.ns.Lottery.EventOf)
	end
end

local function Setup()
	local w, cast = MW.Standard()
	-- Gold may only be opened by a client whose saved data has survived a login.
	w:Relog(cast.king)
	BindLottery(w)
	w:Group({ cast.king.name, cast.bank.name, cast.b1.name, cast.b2.name, cast.b3.name })
	return w, cast, Module(w, cast.king, "Lottery")
end

-- The minute `ahead` seconds from now on the draw's clock (21:00 US Central; the world's clients
-- have no game clock, so their realm reads UTC and the draw's clock is a fixed UTC-5).
local function NextMinute(w, ahead, offset)
	return math.floor(((w.clock + (ahead or 600) + (offset or -300) * 60) % 86400) / 60)
end

-- A long wait, in steps (the world fires at most so many timers in one Run).
local function Wait(w, sec)
	while sec > 1800 do
		w:Run(1800)
		sec = sec - 1800
	end
	w:Run(math.max(0, sec))
end
-- How many times a client printed exactly this line.
local function Said(c, text)
	local n = 0
	for _, line in ipairs(c.printed) do if line == text then n = n + 1 end end
	return n
end

-- The King's five rolls, as the game's lines (heard by every client in his group, or by `hearers`).
local function Roll(w, cast, values, hearers)
	hearers = hearers or { cast.king, cast.bank, cast.b1, cast.b2, cast.b3 }
	for _, value in ipairs(values) do
		w:System(hearers, ("%s rolls %d (1-10000)"):format(cast.king.short, value))
	end
	w:Run(0)
end

test("Lottery controller: schedule opens one v2 sheet, all five witnessed rolls settle it, and the next day claims carry exactly once", function()
	local w, cast, lottery = Setup()
	local at = NextMinute(w, 600)
	eq(lottery.SetSchedule({ on = true, at = at }), true)
	w:Run(0)
	local first = lottery.Book().day
	assert(first and first.eid, "the scheduled day opened")
	eq(cast.king.M.Sheet(first.eid).markets[1].param, "2", "the immutable v2 sheet term")
	for _ = 1, 4 do lottery.Cycle() end
	eq(lottery.Book().day.eid, first.eid, "a cycle cannot open the same scheduled day twice")

	-- One losing ticket makes the whole 10g eligible profit unclaimed.
	local bettor = Module(w, cast.b1, "Lottery")
	assert(bettor.Bet(9, 1000))
	w:Run(first.lockAt - w.clock)
	w:As(cast.bank, cast.bank.ns.Lottery.WatchDraw, true)
	Roll(w, cast, { 1, 5, 9, 13, 17 }) -- animals 1..5; no ticket on any of them
	eq(cast.king.M.Sheet(first.eid).markets[1].result, "0001.0005.0009.0013.0017")
	-- A day's winners are paid by the next day (the owner's call, 2026-10-04: the bank settles when
	-- its client is on), and the next day waits for that settlement: it names only a pot the bank
	-- holds settled.
	for _ = 1, 3 do lottery.Cycle() end
	eq(lottery.Book().day.eid, first.eid, "the controller waits for the bank settlement")

	w:Run(cast.king.M.GRACE + 20)
	local book = assert(cast.king.M.Book(first.eid))
	local wire = assert(cast.king.ns.Lottery.DecodeResult(book.markets[1].result))
	eq(wire.nextCarry, 100000)
	local second = lottery.Book().day
	assert(second.eid ~= first.eid, "the next scheduled day opened")
	eq(second.from, first.eid); eq(second.carry, 100000)
	eq(cast.king.M.Sheet(second.eid).markets[1].param,
		"2." .. first.eid .. "." .. cast.king.ns.Arena.B36(100000))
	for _ = 1, 5 do lottery.Cycle() end
	eq(lottery.Book().day.eid, second.eid, "reload/tick dedupe keeps one successor")
	eq(#lottery.History(), 1)

	-- The first day's retained profit came to the second exactly once: the copper it named.
	w:Run(5)
	eq(#(w.carries or {}), 1, "the pot moved once")
	eq(w:As(cast.bank, cast.bank.ns.Wallet.Pot, second.eid, 1), 100000)
	eq(cast.b3.M.View(second.eid).markets[1].state, "O", "the second day still takes bets")
	eq(cast.b3.M.View(second.eid).markets[1].carry, 100000)
	for _ = 1, 3 do lottery.Cycle() end
	eq(lottery.Book().day.eid, second.eid)
	w:NoErrors()
end)

-- The bank (its client) logs out, and back in, with its saved data. (The world puts the wallet's
-- stand-in in after the login, so the bank's index is rebuilt from its ledger then, as the login
-- does with the wallet there.)
local function Away(w, cast) w:Logout(cast.bank) end
local function Back(w, cast)
	w:Login(cast.bank)
	w:Install(cast.bank)
	w:As(cast.bank, cast.bank.ns.Arena.Events.Register, "L", cast.bank.ns.Lottery.EventOf)
	w:As(cast.bank, cast.bank.ns.MarketBank.Rebuild, "L")
end
local function BankState(w, cast, eid)
	local ev = w:As(cast.bank, cast.bank.ns.MarketBank.Event, "L", eid)
	return ev and ev.markets[1] and ev.markets[1].state
end

test("Lottery controller: a bank away from the declaration settles it when it is back; only then the next day opens, naming its pot, and takes bets", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	w:Run(0)
	local first = lottery.Book().day
	assert(Module(w, cast.b1, "Lottery").Bet(9, 1000)) -- not drawn: 10g of profit unclaimed
	w:Run(first.lockAt - w.clock + 10)
	eq(BankState(w, cast, first.eid), "L", "the bank locked the book at the draw time")
	-- The bank goes away; the King rolls the five within the hour and declares them.
	Away(w, cast)
	Roll(w, cast, { 1, 5, 9, 13, 17 }, { cast.king, cast.b1, cast.b2, cast.b3 })
	eq(cast.king.M.Sheet(first.eid).markets[1].state, "R")
	local opened = 0
	cast.king.ns.On("LOTTERY_OPEN", function() opened = opened + 1 end)
	for _ = 1, 3 do lottery.Cycle() end
	eq(lottery.Book().day.eid, first.eid, "no next day while the bank has not settled the first")
	-- Two hours later the bank is back: the declaration's repeat settles the day with its draw.
	Wait(w, 7200)
	Back(w, cast)
	Wait(w, 1800)
	eq(BankState(w, cast, first.eid), "S", "settled with the declared draw, not void")
	local second = lottery.Book().day
	assert(second.eid ~= first.eid, "the next day, once the bank settled the first")
	eq(second.from, first.eid); eq(second.carry, 100000)
	eq(BankState(w, cast, second.eid), "O", "the next day takes bets")
	eq(w:As(cast.bank, cast.bank.ns.Wallet.Pot, second.eid, 1), 100000, "its pot came")
	eq(opened, 1, "one next day: none of them voided for a pot the bank could not give")
	assert(Module(w, cast.b2, "Lottery").Bet(3, 500))
	w:Run(5)
	eq(cast.b3.M.View(second.eid).markets[1].outcomes[3].pool, 50000, "b2's bet taken")
	w:NoErrors()
end)
test("Lottery controller: incompatible next-day terms retain carry in the settled source until compatible terms return", function()
	local w, cast, lottery = Setup()
	local at = NextMinute(w, 600)
	assert(lottery.SetSchedule({ on = true, at = at }))
	w:Run(0)
	local first = lottery.Book().day
	assert(Module(w, cast.b1, "Lottery").Bet(9, 1000))
	-- Stop automatic succession while this draw settles.
	assert(lottery.SetSchedule({ on = false }))
	w:Run(first.lockAt - w.clock)
	w:As(cast.bank, cast.bank.ns.Lottery.WatchDraw, true)
	Roll(w, cast, { 1, 5, 9, 13, 17 })
	w:Run(cast.king.M.GRACE + 20)
	eq(cast.king.M.Carry(first.eid), 100000)

	assert(cast.king.Roles.SetSettings({ cur = "p" }))
	w:Run(0)
	assert(lottery.SetSchedule({ on = true }))
	eq(lottery.Book().day.eid, first.eid, "gold carry is not discarded into a points day")
	eq(cast.king.M.Carry(first.eid), 100000, "the source ledger still owns every copper")
	eq(cast.king.M.Sheet(first.eid).markets[1].state, "R", "a settled source is not falsely voided")

	assert(cast.king.Roles.SetSettings({ cur = "g" }))
	w:Run(0)
	eq(lottery.Cycle(), true)
	local second = lottery.Book().day
	assert(second.eid ~= first.eid)
	eq(second.from, first.eid); eq(second.carry, 100000)
	w:NoErrors()
end)

test("Lottery winners: the day's bank publishes them once settled and the King's rankings switch is on, every client keeps them from that bank only, and the Games tab shows them", function()
	local w, cast, lottery = Setup()
	local at = NextMinute(w, 600)
	assert(lottery.SetSchedule({ on = true, at = at }))
	w:Run(0)
	local day = lottery.Book().day
	-- 10g on the Mechanostrider (1st place), 5g on the Cobra (not drawn).
	assert(Module(w, cast.b1, "Lottery").Bet(1, 1000))
	assert(Module(w, cast.b2, "Lottery").Bet(9, 500))
	assert(lottery.SetSchedule({ on = false }))
	w:Run(day.lockAt - w.clock)
	w:As(cast.bank, cast.bank.ns.Lottery.WatchDraw, true)
	Roll(w, cast, { 1, 5, 9, 13, 17 }) -- beasts 1 to 5
	w:Run(cast.king.M.GRACE + 20)
	w:Run(30)
	-- Settled, but a name next to an amount stays off the channel while the switch is off.
	eq(#w:Sent({ type = "LW" }), 0, "nothing while the King's rankings switch is off")
	eq(#Module(w, cast.b3, "Lottery").Winners().latest, 0)
	local bankView = w:As(cast.bank, cast.bank.ns.Lottery.DayWinners, day.eid)
	eq(#bankView, 1, "the bank knows them")
	-- The King switches the rankings on: the bank publishes the settled day, once.
	assert(cast.king.Roles.SetSettings({ rankPub = 1 }))
	w:Run(30)
	eq(#w:Sent({ from = cast.bank, type = "LW" }), 1, "published once, by the day's bank")
	eq(#w:Sent({ type = "LW" }), 1, "by nobody else")
	-- The refund is 10g; the 5g profit pool's 1st tranche, 2.5g, less 6%, is b1's: a 2.35g gain.
	for _, c in ipairs({ cast.b3, cast.king, cast.b2, cast.bank }) do
		local list = Module(w, c, "Lottery").Winners()
		eq(#list.latest, 1, c.name .. " heard the day's winners")
		local r = list.latest[1]
		eq(r.name, cast.b1.name); eq(r.amount, 23500); eq(r.beast, c.ns.Lottery.Label(1)); eq(r.eid, day.eid)
		eq(#list.biggest, 1); eq(list.biggest[1].name, cast.b1.name); eq(list.biggest[1].amount, 23500)
	end
	-- Later changes and the bank's settle event again: not sent twice.
	for _ = 1, 3 do w:As(cast.bank, function() cast.bank.ns.Fire("ARENA_CHANGED") cast.bank.ns.Fire("MARKETS_SETTLED", day.eid) end) w:Run(2) end
	eq(#w:Sent({ from = cast.bank, type = "LW" }), 1, "a day's winners go out once")

	-- Only that day's bank is heard, for a day drawn here, with beasts of that draw and no more than its pot.
	local function Take(c, from, body) return w:As(c, c.ns.Lottery.TakeWinners, from, "L", body) end
	local B36 = cast.b3.ns.Arena.B36
	local forged = ("%s~%s~%s:1:%s"):format(day.eid, B36(w.clock + 1), "Parric Stowe", B36(9999))
	eq(select(2, Take(cast.b3, cast.b2.name, forged)), "sender", "a bettor cannot publish a day's winners")
	eq(select(2, Take(cast.b3, cast.bank.name, ("%s~%s~Parric Stowe:9:%s"):format(day.eid, B36(w.clock + 1), B36(100)))), "row",
		"a beast that was not drawn")
	eq(select(2, Take(cast.b3, cast.bank.name, ("%s~%s~Parric Stowe:1:%s"):format(day.eid, B36(w.clock + 1), B36(150001)))), "row",
		"more than the day's pot")
	eq(select(2, Take(cast.b3, cast.bank.name, ("Lt99999zz~%s~-"):format(B36(w.clock + 1)))), "day", "a day nobody drew")
	eq(select(2, Take(cast.b3, cast.bank.name, ("%s~%s~-"):format(day.eid, B36(w.clock - 3600)))), "older", "an older word for that day")
	eq(Module(w, cast.b3, "Lottery").Winners().latest[1].name, cast.b1.name, "the refused words changed nothing")

	-- The Games tab: the Lottery's winners for a member while the switch is on, for its staff alone after.
	local function Shows(c)
		return w:As(c, function()
			c.ns.ArenaHome.rankGame = "lottery"
			for _, line in ipairs(c.ns.ArenaHome.TabLines()) do
				if line.text and tostring(line.text):find(c.ns.L.ARENA_GAMES_LOTTERY_LATEST, 1, true) then return true end
			end
			return false
		end)
	end
	eq(Shows(cast.b3), true, "a member, while the King's switch is on")
	assert(cast.king.Roles.SetSettings({ rankPub = 0 }))
	w:Run(5)
	eq(Shows(cast.b3), false, "a member: not once the switch is off")
	eq(Shows(cast.steward), true, "the staff still see what was published")
	w:NoErrors()
end)

test("Lottery winners: with more drawn days known than the caller keeps in his history, the bank still publishes each day's winners once", function()
	local w, cast, lottery = Setup()
	assert(cast.king.Roles.SetSettings({ rankPub = 1 }))
	w:Run(0)
	local days = lottery.HISTORY_MAX + 1
	local eids = {}
	for n = 1, days do
		-- (Each day 10 minutes ahead: the King moves the draw time, then stops the schedule while it settles.)
		assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
		assert(lottery.SetSchedule({ on = false }))
		w:Run(0)
		local day = lottery.Book().day
		assert(not eids[day.eid], "day " .. n .. " is a new day")
		eids[day.eid], eids[n] = true, day.eid
		assert(Module(w, cast.b1, "Lottery").Bet(1, 1000))
		assert(Module(w, cast.b2, "Lottery").Bet(9, 500))
		w:Run(day.lockAt - w.clock)
		w:As(cast.bank, cast.bank.ns.Lottery.WatchDraw, true)
		Roll(w, cast, { 1, 5, 9, 13, 17 })
		w:Run(cast.king.M.GRACE + 30)
		eq(BankState(w, cast, day.eid), "S", "day " .. n .. " settled")
	end
	eq(#w:As(cast.bank, cast.bank.ns.Lottery.Days), days, "the bank knows every one of them")
	local function PerDay()
		local count = {}
		for _, sent in ipairs(w:Sent({ from = cast.bank, type = "LW" })) do
			local eid = sent.msg:match("^LW~[^~]+~([^~]+)~")
			count[eid] = (count[eid] or 0) + 1
		end
		return count
	end
	local count = PerDay()
	for n = 1, days do eq(count[eids[n]], 1, "day " .. n .. " published once") end
	-- Later changes and idle minutes: nothing goes out again.
	local before = #w:Sent({ type = "LW" })
	for _ = 1, 20 do w:As(cast.bank, function() cast.bank.ns.Fire("ARENA_CHANGED") end) w:Run(2) end
	w:Run(120)
	eq(#w:Sent({ type = "LW" }), before, "no day published twice")
	eq(#Module(w, cast.b3, "Lottery").Winners().latest, lottery.WINNERS_SHOWN)
	w:NoErrors()
end)

test("Lottery controller: the draw is at 21:00 US Central, by the realm's own clock on a Central realm and a fixed UTC-5 on any other", function()
	-- The world's clock is in September: Central is on CDT, UTC-5, so 21:00 is 02:00 UTC either way.
	for _, case in ipairs({ { offset = -300, zone = "central" }, { offset = -240, zone = "fixed" }, { offset = 0, zone = "fixed" } }) do
		local w, cast, lottery = Setup()
		-- (The realm's clock, the game's GetGameTime on every client of the realm.)
		for _, c in ipairs(w.clients) do
			c.globals.GetGameTime = function()
				local here = (w.clock + case.offset * 60) % 86400
				return math.floor(here / 3600), math.floor(here % 3600 / 60)
			end
		end
		eq(lottery.Zone(), case.zone, "realm at " .. case.offset)
		assert(lottery.SetSchedule({ on = true, at = 21 * 60 }))
		w:Run(0)
		local day = lottery.Book().day
		eq(day.lockAt % 86400, 2 * 3600, "21:00 UTC-5, realm at " .. case.offset)
		local L = cast.king.ns.L
		local name = case.zone == "central" and L.LOTTERY_ZONE_CENTRAL or L.LOTTERY_ZONE_FIXED
		eq(lottery.WhenText(day.lockAt), "21:00 " .. name)
		eq(Said(cast.king, L.LOTTERY_OPENED:format("21:00 " .. name)), 1, "the King is told the draw's clock")
		w:NoErrors()
	end
end)

test("Lottery reminders: 60, 15 and 5 minutes before the draw (last bets; the draw, for a bettor; the roll, for the King and the bank), then results now for a bettor, each once", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 7200) }))
	w:Run(0)
	local day = lottery.Book().day
	assert(day.lockAt - w.clock > 3600 + 600, "the day opened more than an hour before its draw")
	assert(Module(w, cast.b1, "Lottery").Bet(1, 1000))
	w:Run(5)
	local alerts = {}
	for _, c in ipairs({ cast.king, cast.bank, cast.b1, cast.b2 }) do
		local alert = c.ns.Alert
		c.ns.Alert = function(kind, tone, a)
			alerts[#alerts + 1] = c.name .. ":" .. tostring(a and a.text)
			return alert(kind, tone, a)
		end
	end
	local L = cast.king.ns.L
	local when = lottery.WhenText(day.lockAt)
	-- One timer, for the next reminder, on every client that knows the day.
	for _, c in ipairs({ cast.king, cast.bank, cast.b1, cast.b2, cast.b3 }) do
		local r = w:As(c, c.ns.Lottery.Reminder)
		eq(r and r.eid, day.eid, c.name); eq(r and r.mark, 3600, c.name)
	end
	local words = { roll = L.LOTTERY_REMIND_ROLL, mine = L.LOTTERY_REMIND_MINE, bet = L.LOTTERY_REMIND_BET }
	local who = { { cast.king, "roll" }, { cast.bank, "roll" }, { cast.b1, "mine" }, { cast.b2, "bet" }, { cast.b3, "bet" } }
	for _, minutes in ipairs({ 60, 15, 5 }) do
		Wait(w, day.lockAt - minutes * 60 - w.clock - 1)
		for _, x in ipairs(who) do eq(Said(x[1], words[x[2]]:format(minutes, when)), 0, x[1].name .. ": not before its time, " .. minutes) end
		w:Run(1)
		for _, x in ipairs(who) do
			for kind, text in pairs(words) do
				eq(Said(x[1], text:format(minutes, when)), kind == x[2] and 1 or 0, x[1].name .. ", " .. minutes .. " minutes: " .. kind)
			end
		end
	end
	-- The 5 minutes' is an alert for the King and the bank alone.
	local roll5 = L.LOTTERY_REMIND_ROLL:format(5, when)
	table.sort(alerts)
	local expect = { cast.king.name .. ":" .. roll5, cast.bank.name .. ":" .. roll5 }
	table.sort(expect)
	eq(table.concat(alerts, "|"), table.concat(expect, "|"))
	-- At the draw time: the results now, for a bettor alone (and an alert).
	w:Run(day.lockAt - w.clock)
	eq(Said(cast.b1, L.LOTTERY_REMIND_NOW), 1)
	eq(alerts[#alerts], cast.b1.name .. ":" .. L.LOTTERY_REMIND_NOW)
	for _, c in ipairs({ cast.b2, cast.b3, cast.king, cast.bank }) do eq(Said(c, L.LOTTERY_REMIND_NOW), 0, c.name) end
	-- Nothing armed after it: no reminder's timer is left on a member once the bets are closed.
	for _, c in ipairs({ cast.b1, cast.b2, cast.b3 }) do
		eq(w:As(c, c.ns.Lottery.Reminder), nil, c.name)
		for _, t in ipairs(w:Timers(c, true)) do assert(t.where ~= "C_Timer.NewTimer", c.name .. ": a reminder's timer left") end
	end
	-- Later changes say none of them again.
	for _ = 1, 3 do w:As(cast.b2, function() cast.b2.ns.Fire("ARENA_CHANGED") end) w:Run(2) end
	for _, minutes in ipairs({ 60, 15, 5 }) do eq(Said(cast.b2, L.LOTTERY_REMIND_BET:format(minutes, when)), 1) end
	w:NoErrors()
end)

test("Lottery reminders: never one that is past: a day opened ten minutes before its draw says the 5 minutes' alone", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	w:Run(0)
	local day = lottery.Book().day
	assert(day.lockAt - w.clock < 900, "the 15 minutes' is past at the opening")
	w:Run(5)
	local armed = w:As(cast.b2, cast.b2.ns.Lottery.Reminder)
	eq(armed and armed.mark, 300, "the 5 minutes' is the first armed")
	w:Run(day.lockAt - w.clock)
	local L = cast.king.ns.L
	local when = lottery.WhenText(day.lockAt)
	eq(Said(cast.b2, L.LOTTERY_REMIND_BET:format(5, when)), 1)
	local late = 0
	for _, line in ipairs(cast.b2.printed) do
		for _, minutes in ipairs({ 60, 15 }) do if line == L.LOTTERY_REMIND_BET:format(minutes, when) then late = late + 1 end end
	end
	eq(late, 0, "no past reminder")
	w:NoErrors()
end)

test("Lottery's draw hour: no draw within the hour after the draw time voids the day, every stake back; a roll after it counts for nothing; the next day opens", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	w:Run(0)
	local day = lottery.Book().day
	local before = w:Balance(cast.bank, cast.b1)
	assert(Module(w, cast.b1, "Lottery").Bet(9, 1000))
	w:Run(5)
	eq(w:Balance(cast.bank, cast.b1), before - 100000)
	-- One prize rolled near the hour's end; the other four never come.
	Wait(w, day.lockAt + 3600 - 20 - w.clock)
	eq(lottery.CanDraw(), true, "the King may still roll")
	Roll(w, cast, { 1 })
	eq(#lottery.Book().day.prizes, 1)
	w:Run(25)
	eq(cast.king.M.Sheet(day.eid).markets[1].state, "V", "void at the hour's end")
	local L = cast.king.ns.L
	eq(Said(cast.king, L.LOTTERY_VOID_LATE), 1)
	-- A roll after the hour: no prize of that day.
	w:As(cast.king, function() eq(cast.king.ns.Lottery.OnRoll(("%s rolls 5 (1-10000)"):format(cast.king.short)), false) end)
	eq(cast.king.M.Sheet(day.eid).markets[1].result, "G", "no draw declared")
	-- The bank gives the stake back; the bettor is told once.
	w:Run(30)
	eq(w:Balance(cast.bank, cast.b1), before, "the stake back")
	eq(Said(cast.b1, L.LOTTERY_VOID_MINE:format(lottery.WhenText(day.lockAt))), 1)
	-- The next day opened (the schedule is on).
	w:Run(30)
	local second = lottery.Book().day
	assert(second.eid ~= day.eid, "the next day")
	eq(second.carry, 0)
	w:NoErrors()
end)

test("Lottery's draw hour: with the King away, the bank voids the undrawn day after the hour (and its slack), not two days later", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	w:Run(0)
	local day = lottery.Book().day
	assert(Module(w, cast.b1, "Lottery").Bet(9, 1000))
	w:Run(5)
	local before = w:Balance(cast.bank, cast.b1)
	w:Logout(cast.king)
	local slack = cast.bank.ns.Lottery.DRAW_WINDOW + cast.bank.ns.Lottery.VOID_SLACK
	Wait(w, day.lockAt + slack - 5 - w.clock)
	eq(cast.b3.M.View(day.eid).markets[1].state, "L", "still waiting for its draw")
	Wait(w, 30)
	eq(cast.b3.M.View(day.eid).markets[1].state, "V", "void")
	eq(w:Balance(cast.bank, cast.b1), before + 100000, "the stake back")
	w:NoErrors()
end)

test("Lottery's draw hour: a bank away when the King declared within the hour pays the winners once it is back, and never voids the day", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	assert(lottery.SetSchedule({ on = false })) -- (no next day in the way)
	w:Run(0)
	local day = lottery.Book().day
	local b1, b2 = w:Balance(cast.bank, cast.b1), w:Balance(cast.bank, cast.b2)
	assert(Module(w, cast.b1, "Lottery").Bet(1, 1000)) -- the Mechanostrider: 1st place
	assert(Module(w, cast.b2, "Lottery").Bet(9, 500)) -- the Cobra: not drawn
	w:Run(day.lockAt - w.clock + 10)
	eq(BankState(w, cast, day.eid), "L")
	Away(w, cast)
	Roll(w, cast, { 1, 5, 9, 13, 17 }, { cast.king, cast.b1, cast.b2, cast.b3 })
	eq(cast.king.M.Sheet(day.eid).markets[1].state, "R", "declared within the hour")
	-- Back two hours later, long past the draw's hour and its slack: it cannot tell no draw from a
	-- declaration it missed, so it waits for the King's repeat instead of voiding at its first tick.
	Wait(w, 7200)
	Back(w, cast)
	w:Run(5)
	eq(BankState(w, cast, day.eid), "L", "not void at the login")
	Wait(w, 900)
	eq(BankState(w, cast, day.eid), "S", "settled with the declared draw")
	-- b1's 10g back and 1st place's half of b2's 5g less 6%: 2.35g; b2's 5g lost.
	eq(w:Balance(cast.bank, cast.b1), b1 + 23500, "the winner paid")
	eq(w:Balance(cast.bank, cast.b2), b2 - 50000, "the loser's stake not given back")
	w:NoErrors()
end)

test("Lottery's draw hour: with the King and the bank both away at its end, the bank back first waits; the King's client voids the day when he is back", function()
	local w, cast, lottery = Setup()
	assert(lottery.SetSchedule({ on = true, at = NextMinute(w, 600) }))
	assert(lottery.SetSchedule({ on = false }))
	w:Run(0)
	local day = lottery.Book().day
	local before = w:Balance(cast.bank, cast.b1)
	assert(Module(w, cast.b1, "Lottery").Bet(9, 1000))
	w:Run(day.lockAt - w.clock + 10)
	Away(w, cast)
	w:Logout(cast.king)
	Wait(w, 7200)
	Back(w, cast)
	Wait(w, 900)
	eq(BankState(w, cast, day.eid), "L", "the bank cannot tell: it waits")
	eq(w:Balance(cast.bank, cast.b1), before - 100000)
	-- The King's client: no draw declared in its hour, void at his login, every stake back.
	w:Login(cast.king)
	w:Install(cast.king)
	w:As(cast.king, cast.king.ns.Arena.Events.Register, "L", cast.king.ns.Lottery.EventOf)
	w:Run(30)
	eq(cast.king.M.Sheet(day.eid).markets[1].state, "V")
	eq(BankState(w, cast, day.eid), "V")
	eq(w:Balance(cast.bank, cast.b1), before, "the stake back")
	w:NoErrors()
end)
