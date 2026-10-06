local H = ...
local test, eq, World = H.test, H.eq, H.World
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local function Client(noAnimation)
	local w = World.New({ compliance = "shipped" })
	local c = w:Client(World.NAMES.fighterA)
	c.K = BoardUI.New(function() return w.clock end, { screen = { 1280, 960 } })
	c.K.Install(c.globals)
	if noAnimation then
		local create = c.globals.CreateFrame
		c.globals.CreateFrame = function(...)
			local frame = create(...)
			local texture = frame.CreateTexture
			frame.CreateTexture = function(...)
				local t = texture(...); t.CreateAnimationGroup = false; return t
			end
			return frame
		end
	end
	c.db.arenaRules = { yes = true }
	local own = w:As(c, function() return H.LoadCompanion(c.ns) end)
	local UI = own.ArenaUI
	w:As(c, function() UI.Open("lottery") end)
	local f = w:As(c, UI.LotteryPracticeWindow, true)
	return w, c, UI, f
end
local prizes = { 4827, 1005, 1109, 2313, 17 }
local function Draw(w, c, UI, f, values)
	w:As(c, function()
		if f.result:IsVisible() then assert(c.K.UserClick(f.draw)) end
		assert(c.K.UserClick(f.cards[2]))
		assert(UI.LotteryPracticeDraw(values or prizes))
	end)
end
local function Errors(c)
	eq(#c.errors, 0, table.concat(c.errors, "; ")); eq(#c.K.errors, 0, table.concat(c.K.errors, "; "))
end
local function RollingDigits(fn)
	local original, tick = math.random, 0
	math.random = function() tick = tick + 1; return tick % 10 end
	local ok, err = pcall(fn)
	math.random = original
	assert(ok, err)
end

test("Lottery presentation: original rolling tiles land sequentially before the free result", function()
	local w, c, UI, f = Client()
	eq(UI.IsShown(), false, "direct entry, not history/profile")
	eq(#f.cards, 25); eq(f.cards[1].art.tex, "Interface\\Icons\\Ability_Mount_MechaStrider")
	eq(f.cards[25].art.tex, "Interface\\Icons\\Ability_Mount_Kodo_01")
	eq(f.draw:IsEnabled(), false)
	local sent = #w.sent
	RollingDigits(function()
		Draw(w, c, UI, f)
		local before = f.prizes[1].number:GetText()
		w:Run(0.06)
		assert(f.prizes[1].number:GetText() ~= before, "visible digits really roll between callbacks")
	end)
	assert(f.result:IsVisible() and not f.grid:IsVisible())
	eq(f.prizes[2].number:GetText(), "----", "later results are not revealed immediately")
	eq(f.prizes[1].art:IsShown(), false); eq(f.outcome:GetText(), "")
	eq(f.draw:IsEnabled(), false, "no repeated click during the reveal")
	assert(f.prizes[1].digit and #f.prizes[1].digit == 4, "original four visible digit tiles")
	-- Restored original spin then 0.72s settling phase, not the former immediate tile landing.
	w:Run(0.48)
	eq(f.prizes[1].digit[1]:GetText(), "4", "first digit lands after the initial spin")
	eq(f.prizes[1].flash[1]:IsShown(), true)
	eq(f.prizes[1].art:IsShown(), false, "animal waits for all four digits")
	w:Run(0.25)
	eq(f.prizes[1].digit[3]:GetText(), "2")
	eq(f.prizes[1].digit[3].textColor[1], 0.62, "last two digits use the original red ink")
	w:Run(0.4)
	eq(f.prizes[1].number:GetText(), "4827"); eq(f.prizes[1].art:IsShown(), true)
	eq(f.prizes[2].number:GetText(), "----")
	w:Run(8)
	for i, value in ipairs(prizes) do
		eq(f.prizes[i].number:GetText(), ("%04d"):format(value)); eq(f.prizes[i].art:IsShown(), true)
	end
	eq(f.prizes[2].art.tex, f.cards[2].art.tex)
	eq(f.outcome:GetText(), UI.LotteryPracticeModel().outcome); eq(f.draw:IsEnabled(), true)
	eq(#w.sent, sent, "no monetary wire messages")
	eq(#c.ns.ArenaLedger.MyGames(), 1, "presentation does not record the draw twice")
	w:As(c, function() assert(c.K.UserClick(f.draw)) end)
	assert(f.grid:IsVisible() and not f.result:IsVisible()); eq(UI.LotteryPracticeModel().pick, nil)
	Errors(c)
end)

test("Lottery presentation: selection and redraw invalidate every previous animation callback", function()
	local w, c, UI, f = Client()
	Draw(w, c, UI, f); w:Run(0.3)
	eq(w:As(c, UI.LotteryPracticeDraw, { 1, 2 }), false, "a bad draw cannot interrupt the current reveal")
	w:As(c, UI.LotteryPracticePick, 25)
	w:Run(10)
	eq(UI.LotteryPracticeModel().pick, 25); eq(#UI.LotteryPracticeModel().rows, 0)
	assert(f.grid:IsVisible() and not f.result:IsVisible())
	w:As(c, UI.LotteryPracticeDraw, prizes); w:Run(0.3)
	local replacement = { 100, 200, 300, 400, 500 }
	w:As(c, UI.LotteryPracticeDraw, replacement); w:Run(10)
	for i, value in ipairs(replacement) do eq(f.prizes[i].number:GetText(), ("%04d"):format(value)) end
	eq(UI.LotteryPracticeModel().pick, 25); Errors(c)
end)

test("Lottery presentation: close and combat cancel callbacks; reopening keeps the real result", function()
	local w, c, UI, f = Client()
	Draw(w, c, UI, f); w:Run(0.3)
	local before = f.prizes[1].number:GetText()
	w:As(c, UI.LotteryPracticeWindow, false); w:Run(10)
	eq(f.prizes[1].number:GetText(), before, "no hidden-frame mutation")
	w:As(c, UI.LotteryPracticeWindow, true)
	eq(f.prizes[1].number:GetText(), "4827"); eq(f.draw:IsEnabled(), true)
	Draw(w, c, UI, f); w:Run(0.3)
	c.globals.InCombatLockdown = function() return true end
	w:Fire(c, "PLAYER_REGEN_DISABLED"); eq(f:IsShown(), false)
	before = f.prizes[1].number:GetText(); w:Run(10)
	eq(f.prizes[1].number:GetText(), before)
	eq(w:As(c, UI.LotteryPracticeWindow, true), false, "cannot reopen in combat")
	Errors(c)
end)

test("Lottery presentation: live gamepad and a client without texture animations still reveal all prizes", function()
	H.WithGamepadUI(true, function()
		local w, c, UI, f = Client(true)
		eq(f.prizes[1].pop, nil, "no animation API fallback")
		Draw(w, c, UI, f)
		eq(f.prizes[2].number:GetText(), "----")
		w:Run(0.54); eq(f.prizes[1].digit[1]:GetText(), "4")
		w:Run(10)
		for i, value in ipairs(prizes) do eq(f.prizes[i].number:GetText(), ("%04d"):format(value)) end
		eq(f.draw:IsEnabled(), true); Errors(c)
	end)
end)

test("Lottery presentation: original left slip and right head card keep the original result geometry", function()
	local w, c, UI, f = Client()
	local head = assert(f.head, "original large first-prize card")
	eq(head.points[1].x, 441); eq(head.points[1].y, -122)
	eq(head:GetWidth(), 354); eq(head:GetHeight(), 346)
	eq(head.art:GetWidth(), 104)
	for i, row in ipairs(f.prizes) do
		eq(row.points[1].x, 21); eq(row.points[1].y, -(182 + (i - 1) * 58))
		eq(row:GetWidth(), 404); eq(row:GetHeight(), 54)
		eq(row.art:GetWidth(), 44)
		for d, digit in ipairs(row.digit) do
			eq(digit.points[1].x, 60 + (d - 1) * 40); eq(digit:GetWidth(), 36)
		end
	end
	Draw(w, c, UI, f)
	eq(head.content:IsVisible(), false, "head is not exposed while its digits still spin")
	w:Run(1.15); eq(head.content:IsVisible(), false, "head waits for the icon pop")
	w:Run(0.3)
	eq(head.content:IsVisible(), true); eq(head.number:GetText(), "4827")
	eq(head.art.tex, f.prizes[1].art.tex)
	eq(f.prizes[2].number:GetText(), "----", "next prize still waits its turn")
	w:Run(10); Errors(c)
end)

test("Lottery presentation: original draw sound loop stops on settling and closing", function()
	local w, c, UI, f = Client()
	local played, stopped = {}, {}
	c.globals.PlaySound = function(id) played[id] = (played[id] or 0) + 1; return true, id end
	c.globals.StopSound = function(handle) stopped[handle] = (stopped[handle] or 0) + 1 end
	Draw(w, c, UI, f)
	eq(played[31579], 1, "original draw start"); eq(played[31580], 1, "original rolling loop")
	w:Run(1.1)
	eq(played[31581], 1, "original settle"); eq(stopped[31580], 1)
	w:Run(0.3); eq(played[31578], 1, "first prize toast follows the pop")
	w:Run(0.5); eq(played[31580], 2, "second prize begins only after the first")
	w:As(c, UI.LotteryPracticeWindow, false)
	eq(stopped[31580], 2, "closing stops the active loop")
	w:Run(10); eq(played[31580], 2, "no hidden replay"); Errors(c)
end)
