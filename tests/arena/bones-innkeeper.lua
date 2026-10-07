local H = ...
local test, eq, World = H.test, H.eq, H.World
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

local function Fresh()
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = w:Player(World.NAMES.fighterA, { bonesTrained = false })
	w:Stand(a.name, FW.INN, true)
	return w, a
end

test("Bones innkeeper: real venue, NPC identity and first-game prerequisite", function()
	local w, a = Fresh()
	w:As(a, function()
		local FT = a.ns.FarkleTable
		eq(FT.TrainingComplete(), false)
		eq(FT.CanPlayPlayers(), false)
		local ok, why = FT.CanCreate({ guest = World.NAMES.fighterB })
		eq(ok, false); eq(why, "training")
		ok, why = a.ns.ArenaMatch.CanSearch({ game = "b", share = true })
		eq(ok, false); eq(why, "training")
		local name, inn = FT.Innkeeper()
		eq(name, "Innkeeper Farley"); eq(inn, "inn_goldshire")
		eq(FT.Innkeeper(true), nil, "no NPC interaction is not gossip")
	end)
	a.globals.UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-1-295-00001" end end
	a.globals.UnitName = function(unit) if unit == "npc" then return "Localized Innkeeper" end end
	w:As(a, function() eq(a.ns.FarkleTable.Innkeeper(true), "Localized Innkeeper") end)
	a.globals.UnitGUID = function() return "Creature-0-1-0-1-999-00001" end
	w:As(a, function() eq(a.ns.FarkleTable.Innkeeper(true), nil, "another NPC cannot offer the lesson") end)
	w:Stand(a.name, FW.ROAD, true)
	w:As(a, function()
		local id, why = a.ns.FarkleTable.Practice({ target = 2000 })
		eq(id, nil); eq(why, "training_inn", "resting away from the tavern is insufficient")
	end)
end)

test("Bones innkeeper: a complete real game unlocks once, persists per character, and abandonment does not", function()
	local w, a = Fresh()
	local FT, R = a.ns.FarkleTable, a.ns.FarkleRules
	local greetings = 0
	w:As(a, function() a.ns.On("BONES_LEARNED", function() greetings = greetings + 1 end) end)
	local id = w:As(a, FT.Practice, { target = 10000, first = 1, learn = false })
	assert(id)
	eq(FT.Get(id).target, 2000, "the first lesson always uses the shortest game")
	eq(FT.Get(id).learn, true, "first lesson cannot disable teaching")
	w:As(a, function() assert(FT.Concede(id)); eq(FT.TrainingComplete(), false) end)
	eq(greetings, 0)
	id = assert(w:As(a, FT.Practice, { target = 2000, first = 1, learn = true }))
	local t = FT.Get(id)
	eq(t.players[2], "Innkeeper Farley")
	w:Stand(a.name, FW.ROAD, false)
	w:As(a, function() eq(FT.ActWhy(t), "training_inn"); eq(FT.Roll(id), false) end)
	w:Stand(a.name, FW.INN, true)
	math.randomseed(3)
	for _ = 1, 400 do
		if t.game.over then break end
		w:As(a, function()
			local who, phase = R.Expect(t.game)
			if who == 1 then
				if phase == "keep" then local pick, act = R.HouseMove(t.game); assert(FT.Keep(pick, act, id))
				else assert(FT.Roll(id)) end
			end
		end)
		w:Run(1)
	end
	eq(t.game.over, true); assert(t.game.reason == "target" or t.game.reason == "cap")
	w:As(a, function() eq(FT.TrainingComplete(), true); eq(FT.CanPlayPlayers(), true) end)
	eq(greetings, 1)
	local nextid = assert(w:As(a, FT.Practice, { target = 10000, first = 1 }))
	eq(FT.Get(nextid).target, 10000, "later lessons keep the player's target choice")
	w:As(a, FT.Concede, nextid)
	w:Logout(a); w:Login(a); FW.Extend(w, a)
	w:As(a, function() eq(a.ns.FarkleTable.TrainingComplete(), true) end)
	local b = w:Player(World.NAMES.fighterB, { bonesTrained = false })
	w:As(b, function() eq(b.ns.FarkleTable.TrainingComplete(), false) end)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0, table.concat(c.errors, "; ")) end
end)

test("Bones innkeeper: own dialogue offers a tavern lesson and explains multiplayer after completion", function()
	local w, a = Fresh()
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:As(a, function()
		local UI = own.ArenaUI
		local f = assert(UI.Innkeeper())
		eq(f:IsShown(), true); assert(f.text:GetText():find("Innkeeper Farley", 1, true))
		eq(f.play:IsShown(), true); eq(f.next:GetText(), a.ns.L.FARKLE_KEEPER_NOT_NOW)
		assert(a.K.UserClick(f.play))
		local v = a.ns.FarkleTable.View()
		assert(v and v.practice and v.learn); eq(v.players[2], "Innkeeper Farley")
		f = UI.Innkeeper(v.players[2], true)
		eq(f.play:IsShown(), true); eq(f.play:GetText(), a.ns.L.FARKLE_KEEPER_AGAIN)
		assert(f.text:GetText():find("private chat", 1, true))
		local found
		UI.OpenFind = function(game) found = game end
		assert(a.K.UserClick(f.next)); eq(found, "b")
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("Bones innkeeper: Arena entry never recalls a different game", function()
	local w, a = Fresh()
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:As(a, function()
		local UI = own.ArenaUI
		for _, section in ipairs({ "farkle", "lottery" }) do
			UI.ShowSection(section)
			UI.Open()
			eq(UI.CurrentRoute().section, "arena")
			assert(UI.CurrentRoute().pane:find("arena.", 1, true))
		end
	end)
end)

test("Bones innkeeper: the lobby opens anywhere while game entry stays venue-bound", function()
	local w, a = Fresh()
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:Stand(a.name, FW.ROAD, false)
	w:As(a, function()
		local UI = own.ArenaUI
		eq(a.ns.FarkleTable.CanOpen(), false)
		assert(UI.Open("bone")); eq(UI.CurrentRoute().pane, "bone.play")
		UI.ShowSection("farkle"); eq(UI.CurrentRoute().section, "farkle")
		eq(UI.ShowPane("bone.play"), true)
		eq(UI.FarkleBoard.Show(false), nil)
		assert(UI.Open("bone.history"))
		eq(UI.CurrentRoute().pane, "bone.history")
		assert(UI.Open("profile"))
		eq(UI.CurrentRoute().pane, "arena.profile")
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)
