-- 1.2, the Arena's fights, bets and staff (2026-10-04): Watch live from a bet, and the screens'
-- contracts that had no test of their own (the stream-delay line, the profile's newest fight, the
-- Events groups, the right-click lines). Every assertion runs the loaded addon on the test world;
-- the data a screen reads is stubbed only at ArenaHome.Data. Every name is invented.
local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Companion(w, c) return w:As(c, function() return H.LoadCompanion(c.ns) end) end
-- fn with some of a table's fields replaced, put back after (an error too).
local function With(t, fields, fn)
	local saved = {}
	for k, v in pairs(fields) do saved[k] = rawget(t, k) t[k] = v end
	local ok, err = pcall(fn)
	for k in pairs(fields) do t[k] = saved[k] end
	if not ok then error(err, 0) end
end

-- The events a bet can be on, as ArenaHome.Data.Event gives them.
local EVENTS = {
	Lday1 = { id = "Lday1", kind = "lottery" },
	Ktab1 = { id = "Ktab1", kind = "farkle" },
	Ffight1 = { id = "Ffight1", kind = "fight", A = "Parric Stowe", B = "Wenna Crale", state = "O", mode = "L" },
	Ncard1 = { id = "Ncard1", kind = "card" },
	Ttour1 = { id = "Ttour1", kind = "tourney" },
	Fdone1 = { id = "Fdone1", kind = "fight", A = "Parric Stowe", B = "Wenna Crale", over = true, state = "F" },
}
local function EventOf(id) return EVENTS[id] end

print("Watch live")

test("1.2 Watch live: a bet's event opens the Lottery's board, the Bones table, the fight's card or the event's pane; nothing once it is over", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local opened = {}
	With(UI.Data, { Event = EventOf }, function()
		With(a.ns.ArenaHome, { Open = function(where, arg) opened[#opened + 1] = { where, arg } return true end }, function()
			With(UI.Card, { Open = function(id) opened[#opened + 1] = { "card", id } end }, function()
				w:As(a, function()
					local want = {
						Lday1 = { "lottery", "lottery", nil }, Ktab1 = { "bones", "bone.live", "Ktab1" }, Ffight1 = { "fight", "card", "Ffight1" },
						Ncard1 = { "event", "events", "Ncard1" }, Ttour1 = { "event", "events", "Ttour1" },
					}
					for id, x in pairs(want) do
						local r = UI.WatchRoute(id)
						assert(r, "a route for " .. id)
						eq(r.kind, x[1], id); eq(r.eid, id)
						opened = {}
						local done, kind = UI.WatchLive(id)
						eq(done, true, id); eq(kind, x[1], id)
						eq(#opened, 1, id); eq(opened[1][1], x[2], id); eq(opened[1][2], x[3], id)
					end
					eq(UI.WatchRoute("Fdone1"), nil, "over: nothing to watch")
					eq(UI.WatchRoute("Fnone9"), nil, "an event this client does not know")
					opened = {}
					eq(UI.WatchLive("Fdone1"), false)
					eq(#opened, 0, "nothing opened")
				end)
			end)
		end)
	end)
end)

test("1.2 Watch live: the slip's button watches the fight once its bet is sent; My bets' open bets each have it, a settled one not", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local L = a.ns.L
	local tickets = {
		{ id = "t1", eid = "Ffight1", idx = 1, o = "A", copper = 5000, state = "accepted" },
		{ id = "t2", eid = "Fdone1", idx = 1, o = "B", copper = 2000, state = "won" },
		{ id = "t3", eid = "Lday1", idx = 1, o = "7", copper = 1000, state = "sent" },
	}
	local OPEN = { accepted = true, sent = true }
	local data = {
		Event = EventOf,
		Markets = function(id)
			return id == "Ffight1" and { cur = "g", markets = { { idx = 1, type = "MW", outcomes = { { o = "A", label = "Parric Stowe" }, { o = "B", label = "Wenna Crale" } } } } } or nil
		end,
		Quote = function() return { ok = true, odds = 2, payout = 9700, cap = 100000 } end,
		Wallet = function() return { cur = "g", g = { bal = 50000, escrow = 0 }, banks = {}, debts = {}, receipts = {} } end,
		Tickets = function(filter)
			local out = {}
			for _, t in ipairs(tickets) do if not (filter and filter.open) or OPEN[t.state] then out[#out + 1] = t end end
			return out
		end,
	}
	local opened = {}
	With(UI.Data, data, function()
		-- (the bet's commit, at its boundary: taken)
		With(UI, { Commit = function() return true end }, function()
			With(UI.Card, { Open = function(id) opened[#opened + 1] = { "card", id } end }, function()
				With(a.ns.ArenaHome, { Open = function(where, arg) opened[#opened + 1] = { where, arg } return true end }, function()
					w:As(a, function()
						local slip = UI.Slip("Ffight1", 1, "A")
						eq(UI.lastSlip.watch, nil, "not sent yet: no Watch live")
						eq(slip.place:GetText(), L.ARENA_SLIP_PLACE)
						slip.place:GetScript("OnClick")()
						assert(UI.lastSlip.watch, "sent: the fight to watch")
						eq(UI.lastSlip.watch.kind, "fight")
						eq(slip.place:GetText(), L.ARENA_WATCH_LIVE)
						slip.place:GetScript("OnClick")()
						eq(#opened, 1); eq(opened[1][1], "card"); eq(opened[1][2], "Ffight1")
						-- My bets: the open fight bet and the Lottery's open ticket, not the settled one.
						local m = UI.WalletModel()
						eq(#m.bets, 3)
						eq(m.watch[1].kind, "fight"); eq(m.watch[2], nil, "settled: none"); eq(m.watch[3].kind, "lottery")
						UI.Wallet("bets")
						local lines = UI.lastWallet.lines
						assert(lines and lines[1].onClick and lines[3].onClick, "the open bets' lines are clicks")
						eq(lines[2].onClick, nil)
						assert(tostring(lines[1].right):find(L.ARENA_WATCH_LIVE, 1, true), tostring(lines[1].right))
						opened = {}
						lines[3].onClick()
						eq(#opened, 1); eq(opened[1][1], "lottery", "the Lottery's board, its live draw")
					end)
				end)
			end)
		end)
	end)
end)

print("The screens' contracts: the stream delay, the newest fight, the Events groups, the right-click lines")

-- The stream-delay line is the King's (his screen may be streamed): nil on a member's screen, on
-- the fight card and in the arbiter's console alike; set on the King's, with the delay he set.
test("1.2 the stream-delay line: nil on a member's screen and card, the King's own delay on his", function()
	local w = World.New()
	local king, lida = w:Role("king"), w:Client("Lida Fenn")
	local public = { id = "Fpub1", kind = "fight", A = "Parric Stowe", B = "Wenna Crale", public = true, state = "O", mode = "L" }
	local function Ev(id) return id == "Fpub1" and public or nil end
	local mine = Companion(w, lida)
	w:As(lida, function()
		eq(mine.ArenaUI.DelayLine(), nil, "a member: no delay line")
		eq(mine.ArenaUI.DelayLine("L"), nil)
		With(mine.ArenaUI.Data, { Event = Ev, Markets = function() return nil end }, function()
			local m = mine.ArenaUI.Card.Model("Fpub1")
			assert(m, "the card's model")
			eq(m.delay, nil, "nor on his card of a public fight")
		end)
	end)
	local kings = Companion(w, king)
	w:As(king, function()
		eq(king.ns.Arena.SetDelay(30), true)
		local line = kings.ArenaUI.DelayLine()
		assert(type(line) == "string" and line:find("30", 1, true), "the King's view: " .. tostring(line))
		With(kings.ArenaUI.Data, { Event = Ev, Markets = function() return nil end }, function()
			eq(kings.ArenaUI.Card.Model("Fpub1").delay, line, "and on his card of a public fight")
			public.public = false
			eq(kings.ArenaUI.Card.Model("Fpub1").delay, nil, "never on a private one")
			public.public = true
		end)
	end)
end)

-- The Arena profile's History: with no fight picked, its detail is the newest fight (whatever the
-- rows' order); a row clicked shows that one.
test("1.2 the Arena profile's history: the newest fight is shown expanded until another row is picked", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local fights = {
		{ fid = "F1", t = 1000, A = a.name, B = "Parric Stowe", opponent = "Parric Stowe", winner = a.name, won = true, dur = 72 },
		{ fid = "F2", t = 3000, A = a.name, B = "Wenna Crale", opponent = "Wenna Crale", winner = "Wenna Crale", won = false, dur = 95 },
		{ fid = "F3", t = 2000, A = "Torvin Hale", B = a.name, opponent = "Torvin Hale", winner = a.name, won = true, dur = 40 },
	}
	With(UI.Data, { Profile = function() return { name = a.name, pub = true } end, MyProfile = function() return { pub = true } end,
		History = function() return fights end }, function()
		w:As(a, function()
			local pane = UI.Pane("arena.profile")
			local st = { key = "arena.profile" }
			local canvas = CreateFrame("Frame")
			pane.detail(canvas, st)
			local text = canvas.profile.fight:GetText()
			assert(text:find("Wenna", 1, true), "the newest fight (F2, t 3000) expanded: " .. text)
			assert(text:find(a.ns.ArenaHome.Clock(95), 1, true), "with its duration: " .. text)
			assert(not text:find("Parric", 1, true) and not text:find("Torvin", 1, true), "only that one: " .. text)
			-- A row picked: its fight instead.
			local row
			for _, line in ipairs(pane.lines(st)) do
				if not line.header and tostring(line.text or ""):find("Parric", 1, true) then row = line end
			end
			assert(row and row.onClick, "the F1 row")
			row.onClick()
			pane.detail(canvas, st)
			text = canvas.profile.fight:GetText()
			assert(text:find("Parric", 1, true) and not text:find("Wenna", 1, true), "the picked fight: " .. text)
		end)
	end)
end)

-- The Events list: Live now (only when something is), Coming up, Your matches (the challenges
-- waiting first, then his own private matches), Ended (ten at most); another pair's private match
-- never shows.
test("1.2 the Events list: the groups in order, the challenges first in Your matches, ten ended at most, no one else's private match", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local L = a.ns.L
	local events = {
		{ id = "Flive", kind = "fight", A = "Parric Stowe", B = "Wenna Crale", public = true, live = true, state = "L", t = 500 },
		{ id = "Fnext", kind = "fight", A = "Torvin Hale", B = "Selka Drummond", public = true, state = "O", t = 900 },
		{ id = "Fmine", kind = "fight", A = a.name, B = "Oswin Marrow", state = "S", t = 800 },
		{ id = "Fothers", kind = "fight", A = "Doran Ashpeak", B = "Coffrey Vault", state = "S", t = 700 },
	}
	for i = 1, 12 do events[#events + 1] = { id = "Fend" .. i, kind = "fight", A = "Parric Stowe", B = "Torvin Hale", public = true, over = true, state = "F", t = 100 - i } end
	local challenges = { { oid = "c1", A = "Wenna Crale", B = a.name, t = 10 } }
	With(UI.Data, { Events = function() return events end, Challenges = function() return challenges end, Markets = function() return nil end,
		Event = function(id) for _, e in ipairs(events) do if e.id == id then return e end end return nil end }, function()
		w:As(a, function()
			local lines = UI.Pane("arena.events").lines({ key = "arena.events" })
			local heads, at = {}, {}
			for i, line in ipairs(lines) do
				if line.header then heads[#heads + 1] = line.text at[line.text] = i end
			end
			eq(table.concat(heads, " | "), table.concat({ L.ARENA_EVENTS_LIVE, L.ARENA_EVENTS_NEXT, L.ARENA_EVENTS_MINE, L.ARENA_EVENTS_ENDED }, " | "))
			local function Under(head)
				local i = at[head] + 1
				local out = {}
				while lines[i] and not lines[i].header do out[#out + 1] = lines[i] i = i + 1 end
				return out
			end
			local live = Under(L.ARENA_EVENTS_LIVE)
			eq(#live, 1); eq(live[1].key, "Flive")
			local nextUp = Under(L.ARENA_EVENTS_NEXT)
			eq(#nextUp, 1); eq(nextUp[1].key, "Fnext")
			local mineRows = Under(L.ARENA_EVENTS_MINE)
			eq(#mineRows, 2, "the challenge, then his match")
			eq(mineRows[1].key, nil); assert(mineRows[1].onClick, "the challenge row answers it")
			eq(mineRows[2].key, "Fmine")
			eq(#Under(L.ARENA_EVENTS_ENDED), 10, "ten ended at most")
			for _, line in ipairs(lines) do assert(line.key ~= "Fothers", "another pair's private match never shows") end
			-- Nothing live: no Live now header at all.
			events[1].live, events[1].state = false, "O"
			lines = UI.Pane("arena.events").lines({ key = "arena.events" })
			for _, line in ipairs(lines) do assert(not (line.header and line.text == L.ARENA_EVENTS_LIVE), "no empty Live now") end
		end)
	end)
end)

-- Right-clicking a player: Challenge to a duel, Invite to Bones, Watch (only while his table takes
-- spectators), Arena profile; the first two greyed with the reason while addon messages are held;
-- never on yourself; nothing for a non-member.
test("1.2 the right-click Arena lines: challenge, Bones, Watch only at a watchable table, the profile; greyed when held; never on yourself", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local AH, L = a.ns.ArenaHome, a.ns.L
	local function Menu()
		local got = {}
		return got, { Button = function(text, fn, tipTitle, tipText, enabled) got[#got + 1] = { text = text, fn = fn, tip = tipText, enabled = enabled } end }
	end
	local calls = {}
	With(AH, {
		Challenge = function(name) calls[#calls + 1] = { "challenge", name } return true end,
		Open = function(where, arg) calls[#calls + 1] = { where, arg } return true end,
		WatchableTable = function(name) return name == "Wenna Crale-Emberfall" and "Kwen1" or nil end,
	}, function()
		w:As(a, function()
			local got, menu = Menu()
			eq(AH.MenuLines({ name = "Parric Stowe-Emberfall" }, menu), 3, "no table to watch: three lines")
			eq(got[1].text, L.ARENA_MENU_CHALLENGE); eq(got[2].text, L.ARENA_MENU_BONE); eq(got[3].text, L.ARENA_MENU_PROFILE)
			eq(got[1].enabled, true); eq(got[2].enabled, true)
			for _, g in ipairs(got) do g.fn() end
			eq(calls[1][1], "challenge"); eq(calls[1][2], "Parric Stowe-Emberfall")
			eq(calls[2][1], "bone.invite"); eq(calls[2][2], "Parric Stowe-Emberfall")
			eq(calls[3][1], "profile"); eq(calls[3][2], "Parric Stowe-Emberfall")
			got, menu = Menu()
			eq(AH.MenuLines({ name = "Wenna Crale-Emberfall" }, menu), 4, "at a table that takes spectators: Watch too")
			eq(got[3].text, L.ARENA_MENU_WATCH)
			calls = {}
			got[3].fn()
			eq(calls[1][1], "bone.live"); eq(calls[1][2], "Kwen1")
			-- Held (a dungeon, a raid, a match): the challenge and Bones greyed with the reason.
			got, menu = Menu()
			AH.MenuLines({ name = "Parric Stowe-Emberfall", locked = true }, menu)
			eq(got[1].enabled, false); eq(got[1].tip, L.ARENA_MENU_LOCKED)
			eq(got[2].enabled, false); eq(got[2].tip, L.ARENA_MENU_LOCKED)
			eq(got[3].enabled, true, "the profile still opens")
			-- Never on yourself, from a unit or a name.
			eq(AH.MenuTarget("PLAYER", { name = a.short, isSelf = true }), nil)
			eq(AH.MenuTarget("FRIEND", { name = a.short, server = a.realm }), nil, "his own name")
			local t = AH.MenuTarget("FRIEND", { name = "Parric Stowe", server = a.realm })
			eq(t and t.name, "Parric Stowe-Emberfall")
		end)
	end)
	-- A non-member (a guild outside Olympus): no lines.
	local loner = w:Client("Doran Ashpeak", { guild = "Quiet Hollow" })
	w:As(loner, function()
		local got, menu = Menu()
		eq(loner.ns.ArenaHome.MenuLines({ name = "Parric Stowe-Emberfall" }, menu), 0)
		eq(#got, 0)
	end)
end)

print("The crowd's bets: the arbiter's switch on a new fight")

-- A public fight opens the crowd's winner market by default (ArenaFights' MarketSpecs). The new
-- fight pop-up's Crowd bets switch (on by default) sends markets = false when turned off, so the
-- fight opens no market; a private fight shows no switch at all.
test("1.2 the new fight pop-up: public (watched) by default; the crowd's bets on by default for a public fight, off sends markets = false and the fight opens none; no switch on a private one", function()
	local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
	local w, cast = W3.New()
	local arb = cast.arbiter
	W3.Companion(w, arb)
	local L = arb.ns.L
	local UI = arb.ns.Arena.ui
	local function FightOf(A)
		for _, f in ipairs(arb.ns.ArenaFights.List({})) do
			if (type(f.A) == "table" and f.A.name or f.A) == A then return arb.ns.ArenaFights.Find("fights", f.fid) end
		end
		return nil
	end
	w:As(arb, function()
		local pop = UI.NewFight()
		pop.names.A, pop.names.B = cast.A.name, cast.B.name
		UI.NewFightRefresh()
		local opts = UI.NewFightOpts()
		-- (Spectators by default, the owner's call 2026-10-04: a new fight is public, Private keeps them out.)
		eq(pop.public.selected, true, "public by default")
		eq(opts.public, true); eq(opts.markets, nil, "the fight's default: the crowd's winner market")
		eq(pop.crowd.selected, true, "on by default")
		eq(pop.crowd.buttons[1]:IsShown(), true, "shown for a public fight")
		eq(pop.crowd.buttons[1]:GetText(), L.ARENA_NEW_CROWD_ON)
		pop.go:GetScript("OnClick")()
	end)
	w:Run(0)
	local on = assert(FightOf(cast.A.name), "the fight was made")
	assert(type(on.marketSpecs) == "table" and on.marketSpecs[1].type == "MW", "its winner market waits for the announcement")
	-- The switch off: the next fight carries markets = false and keeps no market.
	local spare = w:Client("Doran Ashpeak")
	w:As(arb, function()
		local pop = UI.NewFight()
		pop.names.A, pop.names.B = spare.name, cast.B.name
		pop.crowd.buttons[2]:GetScript("OnClick")()
		eq(pop.crowd.selected, false)
		eq(UI.NewFightOpts().markets, false)
		-- A private fight: no switch; its opts never name markets.
		pop.public.buttons[2]:GetScript("OnClick")()
		eq(pop.crowd.buttons[1]:IsShown(), false, "no crowd on a private fight")
		eq(UI.NewFightOpts().public, false, "Private: no watchers")
		eq(UI.NewFightOpts().markets, nil)
		pop.public.buttons[1]:GetScript("OnClick")()
		eq(UI.NewFightOpts().markets, false, "the switch kept while the pop-up is open")
		pop.go:GetScript("OnClick")()
	end)
	w:Run(0)
	local off = assert(FightOf(spare.name), "the second fight was made")
	eq(off.marketSpecs, nil, "no market for the crowd")
	W3.NoErrors(w)
end)

print("The crowd's bets: the event's card and the Bones tables")

-- A market's rows as Markets.View gives them: Markets.StateOf's "O" while it takes bets, "L" once
-- locked. The event card's odds buttons asked for "o" (the sample data's spelling), so on real
-- data every open market's buttons were greyed and no bet could be placed from the card.
local function WinnerView(state)
	return { eid = "Ffight1", cur = "g", bank = "Coffrey Vault-Emberfall", markets = {
		{ idx = 1, type = "MW", label = "Winner", state = state, outcomes = {
			{ o = 1, label = "Parric Stowe", pool = 50000, count = 3, odds = 1.8 }, { o = 2, label = "Wenna Crale", pool = 40000, count = 2, odds = 2.25 } } } } }
end

test("1.2 the event's card: an open market's odds buttons take bets (Markets.View's 'O'); a locked one's are greyed", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local state = "O"
	With(UI.Data, { Event = EventOf, Markets = function() return WinnerView(state) end, Tickets = function() return {} end }, function()
		w:As(a, function()
			eq(UI.MarketOpen({ state = "O" }), true); eq(UI.MarketOpen({ state = "o" }), true, "the sample data's")
			eq(UI.MarketOpen({ state = "L" }), false); eq(UI.MarketOpen({ state = "R" }), false); eq(UI.MarketOpen({}), true)
			local pane = UI.Pane("arena.events")
			local st = { key = "arena.events", sel = "Ffight1" }
			local canvas = CreateFrame("Frame")
			pane.detail(canvas, st)
			local row = canvas.markets.rows[1]
			-- (the test world's buttons keep no enabled state: each one's SetEnabled is read here)
			local enabled = {}
			for j = 1, 2 do row.buttons[j].SetEnabled = function(_, on) enabled[j] = on end end
			pane.detail(canvas, st)
			eq(row.buttons[1]:GetText(), "1.80x")
			eq(enabled[1], true, "open: the Bet"); eq(enabled[2], true)
			eq(rawget(row.buttons[1], "why"), nil)
			state = "L"
			pane.detail(canvas, st)
			eq(enabled[1], false, "locked: greyed"); eq(rawget(row.buttons[1], "why"), a.ns.L.ARENA_REFUSE_CLOSED)
		end)
	end)
end)

-- A public arbiter's Bones table with the crowd's market: the live tables' pane offers a Bet per
-- player (its odds), each opening the slip on that pick; none while the table has no market, and
-- greyed once its bets are closed. The Bets were footer buttons: the footer shows two and folds
-- the rest under More (Window.lua), so the window showed [Watch] [Bet on the host] [More] and the
-- guest's Bet hid in the menu, its closed reason lost. They are on the parchment now, both in
-- sight; the footer keeps Watch and Copy.
test("1.2 the Bones tables to watch: a Bet per player at a table with the crowd's market, both on the pane, its slip on that pick; none without one; greyed once closed", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = Companion(w, a)
	local UI = own.ArenaUI
	local L = a.ns.L
	local state, has = "O", true
	local tables = { { id = "Ktab1", p1 = "Parric Stowe-Emberfall", p2 = "Wenna Crale-Emberfall", official = true, mode = "L" } }
	local view = function()
		if not has then return nil end
		local v = WinnerView(state)
		v.eid = "Ktab1"
		return v
	end
	With(UI.Data, { Tables = function() return tables end, Markets = view, Event = EventOf }, function()
		local slips = {}
		With(UI, { Slip = function(eid, idx, o) slips[#slips + 1] = { eid, idx, o } end }, function()
			w:As(a, function()
				local bets = UI.CrowdBets("Ktab1")
				eq(#bets, 2); eq(bets[1].label, "Parric Stowe"); eq(bets[2].o, 2); eq(bets[1].open, true)
				eq(bets[1].pool, 50000); eq(bets[2].count, 2)
				-- The window on the pane, the table picked: the footer's buttons as shown.
				UI.Show()
				UI.ShowPane("bone.live", "Ktab1")
				local f = UI.Frame()
				local function Footer()
					local out = {}
					for _, b in ipairs(f.buttons) do if b:IsShown() then out[#out + 1] = b:GetText() end end
					table.sort(out)
					return table.concat(out, "|")
				end
				local both = { L.ARENA_BONE_WATCH, L.ARENA_BTN_COPY }
				table.sort(both)
				eq(Footer(), table.concat(both, "|"), "Watch and Copy, nothing under More")
				local m = UI.Canvas("bone.live").crowd
				eq(m:IsShown(), true, "the crowd's bets on the pane")
				local enabled = {}
				for j = 1, 2 do m.bets[j].SetEnabled = function(_, on) enabled[j] = on end end
				UI.Refresh()
				eq(m.bets[1]:IsShown(), true); eq(m.bets[2]:IsShown(), true, "the guest's Bet in sight too")
				eq(m.bets[1]:GetText(), L.ARENA_BONE_BET:format("Parric Stowe") .. "  1.80x")
				eq(m.bets[2]:GetText(), L.ARENA_BONE_BET:format("Wenna Crale") .. "  2.25x")
				eq(enabled[1], true); eq(enabled[2], true)
				m.bets[2]:GetScript("OnClick")(m.bets[2])
				eq(#slips, 1); eq(slips[1][1], "Ktab1"); eq(slips[1][2], 1); eq(slips[1][3], 2)
				state = "L"
				UI.Refresh()
				eq(enabled[1], false, "closed"); eq(enabled[2], false, "closed")
				eq(rawget(m.bets[2], "why"), L.ARENA_REFUSE_CLOSED, "each with why")
				has = false
				eq(UI.CrowdBets("Ktab1"), nil)
				UI.Refresh()
				eq(m:IsShown(), false, "no market: no Bets")
				eq(Footer(), table.concat(both, "|"))
				eq(#UI.Pane("bone.live").buttons({ key = "bone.live", sel = "Ktab1" }), 2, "the footer never grows")
			end)
		end)
	end)
end)
