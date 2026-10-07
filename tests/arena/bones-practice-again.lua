-- Repeat innkeeper training through the real board and table, with optional lesson tips.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

local function Client(trained, locale)
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { companion = {}, bonesTrained = trained })
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	a.globals.GetLocale = function() return locale or "enUS" end
	w:Stand(a.name, FW.INN, true)
	assert(w:As(a, a.ns.Arena.LoadUI))
	return w, a, a.ns.Arena.ui.FarkleBoard
end
local function Click(w, a, button) assert(w:As(a, a.K.UserClick, button), "the control accepts a click") end
local function Parts(B) return B._.parts() end
local function Quiet(w, a)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end
local function SetupOnly(p)
	eq(p.setup:IsVisible(), true)
	for _, key in ipairs({ "find", "someone", "learn" }) do
		eq(p.setup[key] and p.setup[key]:IsVisible() or false, false, "training has no " .. key .. " action")
	end
	assert(p.setup.tips and p.setup.tips:IsVisible(), "training offers the tips checkbox")
	assert(p.setup.start:IsVisible(), "training keeps its Start button")
end
local function CloseGuide(w, a, p)
	if p.help and p.help:IsShown() then Click(w, a, p.help.ok) end
end
local function Wait(w, fn, limit)
	local stop = w.clock + (limit or 10)
	while not fn() do
		w:Run(0.05)
		assert(w.clock < stop, "the match must progress")
	end
end
local function Complete(w, a, B)
	assert(w:As(a, B.StartPractice, 2000, true))
	local p, id = Parts(B), B._.S.id
	CloseGuide(w, a, p)
	w:QueueRoll(a.name, a.ns.FarkleRules.Encode({ 1, 1, 1, 1, 1, 1 }))
	Click(w, a, p.primary)
	Wait(w, function() return not w:As(a, B.Busy, id) end)
	for _, i in ipairs(B._.sides[1].play) do Click(w, a, B._.sides[1].dice[i].f) end
	Click(w, a, p.bank)
	Wait(w, function() return w:As(a, a.ns.FarkleTable.View, id).over end, 60)
	eq(w:As(a, a.ns.FarkleTable.TrainingComplete), true)
	return id
end

test("Bones practice setup: Practice again after completing a real lesson only repeats innkeeper training", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local w, a, B = Client(false, locale)
		local id = Complete(w, a, B)
		local card = assert(w:As(a, B.ShowCard, id))
		Click(w, a, card.buttons[2])
		local p = Parts(B)
		SetupOnly(p)
		eq(p.setup.tips.label:GetText(), a.ns.L.FARKLE_B_TIPS)
		eq(p.setup.tips.checked, false, "repeat practice starts with optional tips off")
		eq(p.setup.tips:IsEnabled(), true)
		Click(w, a, p.targets[3])
		eq(B._.S.target, 10000, "repeat training keeps its selectable target")
		Click(w, a, p.setup.tips)
		eq(p.setup.tips.checked, true)
		eq(B._.S.id, nil, "toggling tips does not start or navigate to a match")
		Click(w, a, p.setup.start)
		local v = w:As(a, a.ns.FarkleTable.View, B._.S.id)
		eq(v.practice, true); eq(v.learn, true); eq(v.target, 10000)
		eq(v.players[2], "Innkeeper Farley")
		eq(p.setup.tips:IsVisible(), false, "the setup does not cover an active match")
		Quiet(w, a)
	end
end)

test("Bones practice setup: the board's Practice again retains plain training and its inn requirement", function()
	local w, a, B = Client(true)
	assert(w:As(a, B.StartPractice, 5000))
	local id = B._.S.id
	CloseGuide(w, a, Parts(B))
	assert(w:As(a, a.ns.FarkleTable.Concede, id))
	Wait(w, function() return Parts(B).primary:IsEnabled() end)
	Click(w, a, Parts(B).primary)
	local p = Parts(B)
	SetupOnly(p)
	Click(w, a, p.targets[2])
	eq(p.setup.tips.checked, false)
	Click(w, a, p.setup.tips); eq(p.setup.tips.checked, true)
	Click(w, a, p.setup.tips); eq(p.setup.tips.checked, false, "tips can be switched off again before Start")
	w:Stand(a.name, FW.ROAD, false)
	Click(w, a, p.setup.start)
	eq(B._.S.id, nil, "repeat training cannot start away from an inn")
	eq(p.info:GetText(), B.WhyText("training_inn"))
	w:Stand(a.name, FW.INN, true)
	Click(w, a, p.setup.start)
	local v = w:As(a, a.ns.FarkleTable.View, B._.S.id)
	eq(v.practice, true); eq(v.learn, false); eq(v.target, 5000)
	eq(w:As(a, B.Lesson, v), nil, "plain training shows no lesson tips")
	Quiet(w, a)
end)

test("Bones practice setup: the first lesson still requires tips and the short target with gamepad UI", function()
	H.WithGamepadUI(true, function()
		local w, a, B = Client(false)
		assert(w:As(a, a.ns.FarkleTable.ShowUI, "practice"))
		local p = Parts(B)
		CloseGuide(w, a, p)
		SetupOnly(p)
		eq(p.setup.tips.checked, true); eq(p.setup.tips:IsEnabled(), false)
		eq(w:As(a, a.K.UserClick, p.setup.tips), false, "first-game teaching cannot be disabled")
		eq(p.targets[2]:IsEnabled(), false); eq(p.targets[3]:IsEnabled(), false)
		local _, _, _, height = a.K.Within(p.setup.tips, p.win)
		eq(height >= 32, true, "the checkbox retains a gamepad-sized click area")
		Click(w, a, p.setup.start)
		local v = w:As(a, a.ns.FarkleTable.View, B._.S.id)
		eq(v.practice, true); eq(v.learn, true); eq(v.target, 2000)
		eq(w:As(a, a.ns.FarkleTable.TrainingComplete), false, "Start does not itself finish the lesson")
		Quiet(w, a)
	end)
end)

test("Bones practice setup: normal player creation and matches have no tips control or lesson text", function()
	local w, a, B = Client(true)
	local b = w:Player(H.World.NAMES.fighterB)
	w:Stand(b.name, FW.INN, true)
	w:Group({ a, b })
	assert(w:As(a, a.ns.FarkleTable.ShowUI, "practice"))
	local p = Parts(B)
	CloseGuide(w, a, p)
	-- A retained training preference must never affect the player-game creation flow.
	Click(w, a, p.setup.tips)
	assert(w:As(a, B.OpenCreate, { guest = b.name, target = 2000 }))
	eq(p.setup.tips:IsVisible(), false)
	Click(w, a, p.create.send)
	local id = B._.S.id
	w:Run(0)
	assert(w:As(b, b.ns.FarkleTable.Answer, id, true))
	w:Run(2)
	local v = w:As(a, a.ns.FarkleTable.View, id)
	eq(v.practice, false); eq(v.learn, false)
	eq(p.setup.tips:IsVisible(), false)
	eq(w:As(a, B.Lesson, v), nil)
	eq((p.info:GetText() or ""):find("Tip:", 1, true), nil)
	Quiet(w, a)
	eq(#b.errors, 0, table.concat(b.errors, "; "))
end)
