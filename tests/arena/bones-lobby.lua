local H = ...
local test, eq, World = H.test, H.eq, H.World
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local function Near(actual, expected)
	assert(math.abs(actual - expected) < 0.000001, "resolved coordinate expected " .. expected .. ", got " .. actual)
end

local function Client(trained, fn)
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(World.NAMES.fighterA, { bonesTrained = trained })
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	-- Declare this client API before World:As snapshots globals, so the arrow case restores it.
	a.globals.Minimap = a.globals.CreateFrame("Frame", nil, a.globals.UIParent)
	w:Stand(a.name, FW.ROAD, false)
	w:As(a, function()
		local own = H.LoadCompanion(a.ns)
		local calls = 0
		-- Observe this endpoint, not the training/venue checks themselves.
		own.ArenaUI.Innkeeper = function() calls = calls + 1 end
		fn(w, a, own.ArenaUI, function() return calls end)
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end

test("Bones lobby: the real Play parchment explains the first lesson in steps, then changes after training", function()
	Client(false, function(w, a, UI)
		local FT, L = a.ns.FarkleTable, a.ns.L
		UI.Open("bone")
		local canvas = assert(UI.Canvas("bone.play"))
		local first = canvas.letterBody:GetText()
		assert(first:find(L.FARKLE_LOBBY_FIRST, 1, true), "the visible parchment includes first-game instructions")
		local _, bullets = first:gsub("•", "")
		eq(bullets, 3, "three readable steps, not one dense paragraph")
		local keeper = assert(first:find("speak to an innkeeper", 1, true))
		local lesson = assert(first:find("2,000-point", 1, true))
		local players = assert(first:find("Find a Player", 1, true))
		assert(keeper < lesson and lesson < players, "explain the prerequisite before player matchmaking")
		eq(canvas.find:IsEnabled(), false); eq(FT.Live(), nil)
		FT.Opts().innkeeperLearned = true
		w:Stand(a.name, FW.INN, true); UI.Refresh()
		local returning = canvas.letterBody:GetText()
		assert(returning:find(L.FARKLE_LOBBY_RETURN, 1, true))
		assert(not returning:find(L.FARKLE_LOBBY_FIRST, 1, true), "a completed lesson no longer asks for the first game")
		eq(canvas.find:IsEnabled(), true); eq(FT.Live(), nil, "explaining the next step starts no game")
	end)
end)

test("Bones lobby: first visit outside an inn allows browsing and rules, never starts training or search", function()
	Client(false, function(w, a, UI, npcCalls)
		local FT, L = a.ns.FarkleTable, a.ns.L
		local sent = #w:Sent({ from = a })
		eq(FT.CanOpen(), false); eq(FT.CanPlayPlayers(), false)
		UI.Open("bone")
		eq(UI.IsShown(), true); eq(UI.Model().closed, nil); eq(UI.Model().pane, "bone.play")
		local keys = {}; for _, pane in ipairs(UI.SectionPanes("farkle")) do keys[#keys + 1] = pane.key end
		eq(table.concat(keys, ","), "bone.play,bone.live,bone.history")
		for _, key in ipairs({ "bone.live", "bone.history", "bone.play" }) do
			eq(UI.ShowPane(key), true); eq(UI.Model().pane, key); eq(UI.Model().closed, nil)
		end
		eq(UI.BonePlayReady(), false)
		local ok, why = UI.FindOpponent("b"); eq(ok, false); eq(why, "training")
		ok, why = UI.OpenFind("b"); eq(ok, false); eq(why, "training"); eq(UI.FindFrame(), nil)
		local canvas = assert(UI.Canvas("bone.play"))
		eq(canvas.find:IsEnabled(), false)
		assert(a.K.UserClick(canvas.learn), "the learning action remains available on the road")
		local parts = UI.FarkleBoard._.parts()
		assert(parts.help and parts.help:IsShown(), "learning opens the actual rules guide")
		eq(FT.Live(), nil); eq(FT.TrainingComplete(), false)
		eq(npcCalls(), 0); eq(#w:Sent({ from = a }), sent, "browsing and refused actions send no messages")
	end)
end)

test("Bones lobby: a new table remains disabled at the inn until the real saved lesson is complete", function()
	Client(false, function(w, a, UI, npcCalls)
		w:Stand(a.name, FW.INN, true)
		local FT = a.ns.FarkleTable
		eq(FT.CanOpen(), true); eq(FT.CanPlayPlayers(), false)
		UI.Open("bone")
		local buttons = UI.Pane("bone.play").buttons({ key = "bone.play" })
		eq(buttons[1].enabled, false); eq(buttons[2][1], a.ns.L.ARENA_BONE_NEW); eq(buttons[2].enabled, false)
		local ok, why = FT.CanCreate({ guest = World.NAMES.fighterB }); eq(ok, false); eq(why, "training")
		assert(a.K.UserClick(UI.Canvas("bone.play").learn))
		eq(UI.FarkleBoard._.parts().help:IsShown(), true); eq(FT.Live(), nil); eq(npcCalls(), 0)
		FT.Opts().innkeeperLearned = true
		UI.Refresh()
		eq(UI.BonePlayReady(), true)
		buttons = UI.Pane("bone.play").buttons({ key = "bone.play" })
		eq(buttons[1].enabled, true); eq(buttons[2].enabled, true)
	end)
end)

test("Bones lobby: returning players can browse anywhere, but an old Find callback rechecks the inn", function()
	Client(true, function(w, a, UI, npcCalls)
		UI.Open("bone")
		local ok, why = UI.BonePlayReady(); eq(ok, false); eq(why, a.ns.L.FARKLE_LOG_TAVERN_REST)
		ok, why = UI.FindOpponent("b"); eq(ok, false); eq(why, "tavern-rest")
		ok, why = UI.OpenFind("b"); eq(ok, false); eq(why, "tavern-rest")
		local buttons = UI.Pane("bone.play").buttons({ key = "bone.play" }); eq(buttons[2].enabled, false)
		w:Stand(a.name, FW.INN, true); UI.Refresh(); eq(UI.BonePlayReady(), true)
		local find = assert(UI.OpenFind("b"))
		-- Explicit search consent, as the sheet's share checkbox supplies it; no eligibility mock.
		find.opts.share = true; UI.FindRefresh()
		local can, reason = a.ns.ArenaMatch.CanSearch(UI.FindOpts())
		assert(can, "the cached search must really be eligible before departure: " .. tostring(reason))
		eq(find.go:IsEnabled(), true)
		local stale = assert(find.go:GetScript("OnClick"))
		local sent = #w:Sent({ from = a })
		w:Stand(a.name, FW.ROAD, false)
		stale(find.go)
		eq(select(1, a.ns.ArenaMatch.View()).state, "idle", "leaving cannot start the cached search action")
		eq(find.line:GetText(), a.ns.L.FARKLE_LOG_TAVERN_REST)
		w:Stand(a.name, FW.INN, true); a.ns.FarkleTable.Opts().innkeeperLearned = nil
		stale(find.go)
		eq(a.ns.ArenaMatch.View().state, "idle"); eq(find.line:GetText(), a.ns.L.FARKLE_LOBBY_FIRST)
		eq(#w:Sent({ from = a }), sent); eq(npcCalls(), 0)
	end)
end)

test("Bones lobby: actual wooden table has border-only framing and separated top and bottom action bands", function()
	Client(true, function(w, a, UI)
		w:Stand(a.name, FW.INN, true)
		assert(UI.FarkleBoard.Show(false))
		local p = UI.FarkleBoard._.parts()
		local win, shell = p.win, p.shell
		-- The shared Games.Bar is 56px; the original wooden tabletop stays exactly 800x400.
		eq(win:GetWidth(), 800); eq(win:GetHeight(), 456); eq(win:GetScale(), 1.1)
		assert(shell:GetWidth() >= 880)
		eq(rawget(shell, "TitleContainer"), nil); eq(rawget(shell, "windowTitle"), nil)
		eq(shell.border.template, "DialogBorderTemplate")
		local bar = assert(win.bar.wood)
		local x, y, width, height = a.K.Within(bar, win)
		Near(x, 0); Near(y, 400); Near(width, 800); Near(height, 56)
		local _, sitTop, _, sitH = a.K.Within(win.sit, win)
		Near(sitTop, 12); assert(sitTop + sitH < 68, "sit remains above target and status text")
		local _, helpTop, _, helpH = a.K.Within(win.helpButton, win)
		assert(helpTop >= 400 and helpTop + helpH <= 456, "help joins the original shared footer")
		for _, button in ipairs({ p.primary, p.bank, p.extra }) do
			-- Games.Bar deliberately clears anchors for hidden actions; they must not be clickable.
			if button:IsShown() then
				local left, top, bw, bh = a.K.Within(button, win)
				assert(left >= 0 and left + bw <= 800 and top >= 400 and top + bh <= 456, "playing actions fit only the bottom band")
			else eq(a.K.UserClick(button), false) end
		end
		local _, woodY, woodWidth, woodHeight = a.K.Within(win.table[2], win)
		Near(woodWidth, 800); Near(woodY + woodHeight, 400)
	end)
end)

test("Bones lobby: Bones keeps Play, Live tables and Your games even when a lab opener accepts sections", function()
	Client(true, function(_, _, UI)
		local calls = {}
		UI.OpenGame = function(section) calls[#calls + 1] = section; return true end
		UI.ShowSection("farkle"); eq(UI.state.section, "farkle"); eq(#calls, 0)
		UI.Open("bone"); eq(UI.Model().pane, "bone.play"); eq(#calls, 0)
		UI.ShowPane("bone.history"); UI.ShowSection("farkle")
		eq(UI.state.section, "farkle"); eq(#calls, 0)
		UI.ShowSection("lottery"); eq(#calls, 1); eq(calls[1], "lottery", "the separate Lottery lab route is unchanged")
	end)
end)

test("Bones lobby: keeper guidance starts and cancels the actual nearest-inn arrow without opening an NPC", function()
	Client(false, function(w, a, UI, npcCalls)
		local g = a.globals
		g.Minimap:SetSize(140, 140); g.Minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		local create = g.CreateFrame
		g.CreateFrame = function(kind, name, parent, template)
			local frame = create(kind, name, parent, template)
			if parent == g.Minimap then
				local texture = frame.CreateTexture
				frame.CreateTexture = function(self, ...)
					local icon = texture(self, ...)
					-- Native Texture rotation is covered by the standalone arrow client fixture.
					icon.SetRotation = function(self, angle) self.rotation = angle end
					return icon
				end
			end
			return frame
		end
		CreateFrame = g.CreateFrame
		local pins = { adds = 0, removes = 0 }
		function pins:AddMinimapIconWorld(_, frame) self.adds = self.adds + 1; frame:SetPoint("CENTER", g.Minimap, "CENTER", 30, 0); return true end
		function pins:RemoveMinimapIcon() self.removes = self.removes + 1 end
		a.ns.Pins = function() return pins end
		assert(loadfile(H.ADDON_DIR .. "InnkeeperArrow.lua"))("Olympus", a.ns)
		local arrow = a.ns.InnkeeperArrow
		local target = assert(arrow.Target()); eq(target.id, "inn_goldshire", "the real eligible venue registry chooses the nearest keeper")
		local sent = #w:Sent({ from = a })
		eq(UI.BoneFindInnkeeper(), true); eq(arrow.State().active, true); eq(pins.adds, 1)
		local ticker = arrow.State().ticker
		eq(UI.BoneFindInnkeeper(), true); eq(arrow.State().active, false); eq(ticker.cancelled, true)
		eq(UI.BoneFindInnkeeper(), true)
		w:Stand(a.name, FW.INN, true); arrow.Refresh(); eq(arrow.State().active, false)
		local ok, why = UI.BoneFindInnkeeper(); eq(ok, false); eq(why, "arrived")
		eq(UI.lastSaid, a.ns.L.FARKLE_LOBBY_TALK:format(target.innkeeper))
		eq(npcCalls(), 0); eq(a.ns.FarkleTable.TrainingComplete(), false); eq(a.ns.FarkleTable.Live(), nil)
		eq(#w:Sent({ from = a }), sent)
	end)
end)
