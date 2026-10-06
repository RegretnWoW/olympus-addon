local H = ...
local test, eq = H.test, H.eq
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local function Client(locale, fn)
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { bonesTrained = false })
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	a.globals.GetLocale = function() return locale end
	w:As(a, function()
		local own = H.LoadCompanion(a.ns)
		assert(own.ArenaUI.Open("bone.play"))
		fn(w, a, own.ArenaUI)
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end

test("Innkeeper lobby feedback: learn, keeper and player order with first-lesson copy in both locales", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		Client(locale, function(_, a, UI)
			local c, L = UI.Canvas("bone.play"), a.ns.L
			local _, learnY = a.K.Within(c.learn, c)
			local _, keeperY = a.K.Within(c.keeper, c)
			local _, findY, _, findH = a.K.Within(c.find, c)
			assert(learnY < keeperY and keeperY < findY, "How to Play, nearest keeper, Find a Player")
			assert(findY + findH <= c:GetHeight(), "last action remains inside the page")
			assert(c.letterBody:GetStringHeight() <= c.letterBody:GetHeight(), "first instructions fit the reserved area")
			assert(c.letterBody:GetText():find(L.FARKLE_LOBBY_FIRST, 1, true))
			assert(L.FARKLE_INTRO_TEXT:find(locale == "enUS" and "first free 2,000" or "primeira partida gratuita de 2.000", 1, true))
			eq(c.find:IsEnabled(), false, "a lesson is still required, not just new copy")
			local found = {}
			for _, row in ipairs(UI.Pane("bone.play").lines({})) do
				if row.onClick and (row.text:find(L.FARKLE_B_HOW, 1, true) or row.text:find(L.FARKLE_LOBBY_FIND_KEEPER, 1, true)) then found[#found + 1] = row.text end
			end
			assert(found[1]:find(L.FARKLE_B_HOW, 1, true)); assert(found[2]:find(L.FARKLE_LOBBY_FIND_KEEPER, 1, true))
		end)
	end
end)

test("Innkeeper lobby feedback: actual keeper click displays arrival, start, cancellation and unavailable outcomes", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		Client(locale, function(_, a, UI)
			local c, L = UI.Canvas("bone.play"), a.ns.L
			local active, arrived, failed, starts = false, true, nil, 0
			local inn = { innkeeper = "Innkeeper Allison" }
			a.ns.InnkeeperArrow = {
				State = function() return { active = active } end,
				Target = function() if arrived then return nil, "arrived", inn end; return inn, "shown" end,
				Start = function() starts = starts + 1; if failed then return false, failed end; active = true; return true, inn end,
				Cancel = function() active = false end,
			}
			assert(a.K.UserClick(c.keeper)); eq(starts, 0)
			eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_TALK:format(inn.innkeeper))
			eq(UI.lastSaid, c.keeperNotice:GetText())
			local rows = UI.Pane("bone.play").lines({})
			local visible = false
			for _, row in ipairs(rows) do if row.text == c.keeperNotice:GetText() then visible = true end end
			assert(visible, "feedback also accompanies the left-side action")
			arrived = false
			assert(a.K.UserClick(c.keeper)); eq(starts, 1); eq(active, true)
			eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_ARROW:format(inn.innkeeper))
			eq(c.keeper:GetText(), L.FARKLE_LOBBY_STOP_ARROW)
			assert(a.K.UserClick(c.keeper)); eq(active, false); eq(starts, 1)
			eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_STOPPED)
			failed = "no-inn"; assert(a.K.UserClick(c.keeper)); eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_NO_INN)
			failed = "gamepad"; assert(a.K.UserClick(c.keeper)); eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_GUIDE_UNAVAILABLE)
			a.ns.InnkeeperArrow = nil
			local ok, why = UI.BoneFindInnkeeper(); eq(ok, false); eq(why, "missing")
			eq(c.keeperNotice:GetText(), L.FARKLE_LOBBY_GUIDE_UNAVAILABLE)
		end)
	end
end)

test("Innkeeper lobby feedback: target exceptions cancel and report instead of disappearing into SafeCall", function()
	Client("enUS", function(_, a, UI)
		local cancel, logs = 0, {}
		a.ns.Log = function(fmt, ...) logs[#logs + 1] = fmt:format(...) end
		a.ns.InnkeeperArrow = { State = function() return { active = false } end,
			Target = function() error("fixture target failed") end,
			Cancel = function(why) eq(why, "error"); cancel = cancel + 1 end,
			Start = function() error("must not start after target failure") end }
		assert(a.K.UserClick(UI.Canvas("bone.play").keeper))
		eq(cancel, 1); eq(#logs, 1); assert(logs[1]:find("fixture target failed", 1, true))
		eq(UI.Canvas("bone.play").keeperNotice:GetText(), a.ns.L.FARKLE_LOBBY_GUIDE_UNAVAILABLE)
	end)
end)
