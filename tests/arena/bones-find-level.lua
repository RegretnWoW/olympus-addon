local H = ...
local test, eq = H.test, H.eq
local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/match-world.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

test("Bones find level: actual search sheet hides label and control, ignores stale selection, and restores Arena filter", function()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { bonesTrained = true })
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	w:Stand(a.name, FW.INN, true)
	w:As(a, function()
		local own = H.LoadCompanion(a.ns)
		local UI = own.ArenaUI
		local f = assert(UI.OpenFind("b"))
		f.opts.level = 10; UI.FindRefresh()
		for _, button in ipairs(f.level.buttons) do eq(button:IsShown(), false) end
		eq(f.level.label:IsShown(), false)
		eq(UI.FindOpts().level, 0)
		eq(UI.FindOpts().game, "b"); eq(UI.FindOpts().reach, "z")
		UI.OpenFind("d"); f.opts.level = 10; UI.FindRefresh()
		for _, button in ipairs(f.level.buttons) do eq(button:IsShown(), true) end
		eq(f.level.label:IsShown(), true)
		eq(UI.FindOpts().level, 10)
	end)
	eq(#a.errors, 0); eq(#a.K.errors, 0)
end)

test("Bones find level: real wire search accepts distant levels while Arena still rejects them", function()
	for _, game in ipairs({ "b", "d" }) do
		local w = H.World.New()
		local a = MW.Client(w, "Lida Fenn", { level = 60, pos = { cont = 0, wx = -13000, wy = 300 } })
		local b = MW.Client(w, "Parric Stowe", { level = 20, pos = { cont = 0, wx = -13400, wy = 250 }, findable = true })
		eq(a.Match.Start({ game = game, kind = "c", level = 5, reach = "z" }), true)
		w:Run(5)
		eq(a.Match.View().search.level, game == "b" and 0 or 5)
		eq(MW.Last(w, b, "O") ~= nil, game == "b", "actual remote reply")
		eq(a.Match.View().search.answers, game == "b" and 1 or 0, "actual retained offer")
		MW.NoErrors(w)
	end
end)
