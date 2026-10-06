local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)

-- Separate from build70205's strict fixture: this optional native shape follows the current
-- Windows client's Forever 1.60.1.70235 source, wow-ui-source commit a84e2b1b41d3d4137127c07e4da448aa3251d6f1:
-- UIPanels_Game/Mainline/GossipFrame.xml, Shared/GossipFrameShared.lua and SharedXML/Shared/Scroll/ScrollBox.lua.
-- Pixel rendering and real hover still require an in-game check.
local function Frame(parent)
	local f = { parent = parent, shown = true, height = 403, width = 300, scripts = {}, points = {} }
	function f:SetSize(w, h) self.width, self.height = w, h end
	function f:GetHeight() return self.height end
	function f:GetNumPoints() return #self.points end
	function f:SetHeight(h) self.height = h end
	function f:GetWidth() return self.width end
	function f:SetWidth(w) self.width = w end
	function f:IsShown() return self.shown end
	function f:IsProtected() return self.protected == true end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
	function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function f:ClearAllPoints() self.points = {} end
	function f:SetScript(k, call) self.scripts[k] = call end
	function f:HookScript(k, call)
		local before = self.scripts[k]
		self.scripts[k] = function(...) if before then before(...) end; call(...) end
	end
	function f:SetText(v) self.text = v; if self.fontString then self.fontString:SetText(v) end end
	function f:SetTextColor() end
	function f:SetJustifyH() end
	function f:SetJustifyV() end
	function f:SetTexture(v) self.texture = v end
	function f:SetHighlightTexture(v, blend) self.highlight, self.highlightBlend = v, blend end
	function f:GetFontString() return self.fontString end
	function f:GetTextHeight() return self.textHeight or 14 end
	function f:CreateFontString(_, _, font) local fs = Frame(self); fs.font, fs.height = font, 14; return fs end
	function f:CreateTexture() return Frame(self) end
	return f
end

local function WithGossip(fn)
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { bonesTrained = false })
	w:Stand(a.name, FW.INN, true)
	local f, panel = Frame(), Frame()
	f.GreetingPanel = panel
	panel.ScrollBox, panel.ScrollBar = Frame(panel), Frame(panel)
	panel.ScrollBox.contentHeight = 96
	function panel.ScrollBox:GetDerivedExtent() return self.contentHeight end
	panel.ScrollBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -65)
	panel.GoodbyeButton = Frame(panel)
	local goods, home = {}, {}
	f.gossipOptions = { goods, home }
	local pending, closed, starts = {}, 0, {}
	a.globals.GossipFrame = f
	a.globals.CreateFrame = function(_, _, parent, template)
		local b = Frame(parent); b.template = template
		if template == "GossipTitleButtonTemplate" then
			-- The client's base gossip choice owns its font, icon, highlight and text-height resize;
			-- unlike its Option derivative, this template has no server-select OnClick handler.
			b:SetSize(300, 16)
			b.fontString = b:CreateFontString(nil, "ARTWORK", "QuestFontLeft")
			b.fontString:SetPoint("LEFT", 20, 0); b.fontString:SetWidth(275)
			b.Icon = b:CreateTexture(); b.Icon:SetSize(16, 16)
			b.Icon:SetPoint("TOPLEFT", 3, 1)
			b.Icon:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			function b:SetTextAndResize(text)
				self:SetText(text)
				self:SetHeight(math.max(self:GetTextHeight() + 2, self.Icon:GetHeight()))
			end
		end
		return b
	end
	a.globals.UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-1-295-00001" end end
	a.globals.UnitName = function(unit) if unit == "npc" then return "Localized Innkeeper" end end
	a.globals.C_GossipInfo = { CloseGossip = function() closed = closed + 1; f:Hide() end }
	a.globals.InCombatLockdown = function() return w.combat == true end
	local after = a.ns.After
	a.ns.After = function(_, _, call) pending[#pending + 1] = call end
	local show = a.ns.FarkleTable.ShowUI
	a.ns.FarkleTable.ShowUI = function(what, id, extra)
		eq(f.shown, false, "native conversation closed before training launch")
		starts[#starts + 1] = { what = what, id = id, extra = extra }; return true
	end
	w:As(a, function()
		assert(loadfile(H.ADDON_DIR .. "InnkeeperGossip.lua"))("Olympus", a.ns)
		local g = a.ns.InnkeeperGossip
		local ok, err = pcall(fn, g, { w = w, a = a, f = f, panel = panel, pending = pending,
			starts = starts, closed = function() return closed end, goods = goods, home = home })
		g.Park()
		if not ok then error(err, 0) end
	end)
	a.ns.After, a.ns.FarkleTable.ShowUI = after, show
end

test("Innkeeper gossip: opt-in row preserves goods/home and exact native layout", function()
	WithGossip(function(g, t)
		local scroll = t.panel.ScrollBox
		local anchors = scroll.points
		g.OnShow(); eq(#t.pending, 1); eq(g.State().mode, "inactive", "no automatic dialogue")
		t.pending[1](); eq(g.State().mode, "row"); eq(scroll.height, 403)
		eq(scroll.points, anchors); eq(#anchors, 1, "native anchors never changed")
		eq(t.f.gossipOptions[1], t.goods); eq(t.f.gossipOptions[2], t.home); eq(#t.f.gossipOptions, 2)
		eq(g.State().row.parent, t.panel); eq(g.State().row.icon.texture, g.DICE_TEXTURE)
		g.State().row.scripts.OnClick(); eq(g.State().mode, "dialog")
		eq(g.State().dialog.parent, t.panel); eq(scroll.shown, false); eq(t.panel.ScrollBar.shown, false)
		eq(t.panel.GoodbyeButton.shown, true, "native Goodbye remains available")
		eq(t.closed(), 0); eq(#t.starts, 0, "opt-in alone does not start a game")
		g.State().dialog.cancel.scripts.OnClick(); eq(g.State().mode, "row"); eq(scroll.shown, true)
		g.Park(); eq(scroll.height, 403); eq(scroll.shown, true); eq(t.panel.ScrollBar.shown, true)
		eq(scroll.points, anchors)
	end)
end)

test("Innkeeper gossip: Bones follows the native choices instead of the bottom of the parchment", function()
	WithGossip(function(g, t)
		local scroll = t.panel.ScrollBox
		eq(g.ShowRow(), true)
		local row = g.State().row
		eq(row.points[1][1], "TOPLEFT"); eq(row.points[1][2], scroll)
		eq(row.points[1][3], "TOPLEFT", "anchor after the actual conversation, not the viewport bottom")
		eq(row.points[1][4], 0); eq(row.points[1][5], -(scroll.contentHeight + 4))
		eq(scroll.height, 403, "a short native conversation does not need a smaller viewport")
		g.Park(); scroll.contentHeight = 700
		eq(g.ShowRow(), true)
		eq(scroll.height, 403 - row:GetHeight() - 4, "a long conversation retains its own scrolling")
		eq(row.points[1][5], -(scroll.height + 4), "reserved row stays clear of scrolling native choices")
		g.Park(); eq(scroll.height, 403)
		scroll.contentHeight = 122; eq(g.ShowRow(), true)
		eq(row.points[1][5], -126, "reopening recalculates a different conversation's extent")
		eq(#row.points, 1, "old row anchors are replaced")
	end)
end)

test("Innkeeper gossip: all local choices use native gossip font, icons, hover and wrapped-text height", function()
	WithGossip(function(g, t)
		eq(g.ShowRow(), true); eq(g.Open(), true)
		local state = g.State()
		eq(state.dialog.text.font, "QuestFont", "body uses the native greeting font without the UI font's shadow")
		for _, b in ipairs({ state.row, state.dialog.confirm, state.dialog.cancel }) do
			eq(b.template, "GossipTitleButtonTemplate", "reuse the base native option, with no server-selection script")
			eq(b.label, b:GetFontString()); eq(b.label.font, "QuestFontLeft")
			eq(b.icon, b.Icon); eq(b.icon.width, 16); eq(b.icon.height, 16)
			eq(b.highlight, "Interface\\QuestFrame\\UI-QuestTitleHighlight"); eq(b.highlightBlend, "ADD")
			eq(b:GetHeight(), 16, "one native text line plus its built-in padding")
		end
		eq(state.row.icon.texture, g.DICE_TEXTURE); eq(state.dialog.confirm.icon.texture, g.DICE_TEXTURE)
		eq(state.dialog.cancel.icon.texture, "Interface\\QuestFrame\\UI-Quest-BulletPoint")
		eq(state.dialog.confirm.label.text, t.a.ns.L.FARKLE_KEEPER_LEARN)
		eq(state.dialog.cancel.label.text, t.a.ns.L.FARKLE_KEEPER_NOT_NOW)
		state.dialog.confirm.textHeight = 42; state.dialog.cancel.textHeight = 28
		eq(g.Open(), true)
		eq(state.dialog.confirm:GetHeight(), 44); eq(state.dialog.cancel:GetHeight(), 30,
			"wrapped localized choices keep a native highlight and hit area covering every line")
		state.dialog.cancel.scripts.OnClick(); eq(g.State().mode, "row")
		eq(t.f.gossipOptions[1], t.goods); eq(t.f.gossipOptions[2], t.home); eq(#t.f.gossipOptions, 2)
		eq(t.closed(), 0); eq(#t.starts, 0, "local Cancel never selects a native server option")
	end)
end)

test("Innkeeper gossip: missing native template or unreadable content extent leaves no visible partial choice", function()
	WithGossip(function(g, t)
		local scroll, extent = t.panel.ScrollBox, t.panel.ScrollBox.GetDerivedExtent
		scroll.GetDerivedExtent = nil
		eq(g.ShowRow(), false); eq(g.State().row, nil); eq(scroll.height, 403)
		scroll.GetDerivedExtent = extent
		for _, value in ipairs({ 0, -1, 0 / 0, math.huge, "unmeasured" }) do
			scroll.contentHeight = value
			local ok, reason = g.ShowRow()
			eq(ok, false); eq(reason, "geometry"); eq(g.State().mode, "inactive")
			eq(g.State().saved, nil); eq(g.State().row.shown, false); eq(scroll.height, 403)
		end
		scroll.GetDerivedExtent = function() error("native layout not ready") end
		eq(g.ShowRow(), false); eq(scroll.height, 403)
	end)
	WithGossip(function(g, t)
		local create, frames, choices = CreateFrame, {}, 0
		CreateFrame = function(kind, name, parent, template)
			local f = create(kind, name, parent, template); frames[#frames + 1] = f
			if template == "GossipTitleButtonTemplate" then
				choices = choices + 1
				if choices == 2 then f.SetTextAndResize = nil end
			end
			return f
		end
		eq(g.ShowRow(), false); eq(g.State().row, nil, "partial native build is never cached")
		for _, f in ipairs(frames) do eq(f.shown, false, "partial frames stay hidden") end
		eq(t.panel.ScrollBox.height, 403); eq(t.panel.ScrollBox.shown, true)
		CreateFrame = create
		eq(g.ShowRow(), true, "a supported native template can retry cleanly")
	end)
end)

test("Innkeeper gossip: explicit confirmation closes NPC panel then launches first lesson", function()
	WithGossip(function(g, t)
		eq(g.ShowRow(), true); eq(g.Open(), true)
		eq(g.Confirm(), true); eq(t.closed(), 1); eq(#t.starts, 1)
		eq(t.starts[1].what, "practice"); eq(t.starts[1].extra.learn, true)
		eq(t.starts[1].extra.target, t.a.ns.FarkleRules.TARGETS[1])
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 403)
		eq(g.Confirm(), false, "stale confirm cannot launch twice"); eq(#t.starts, 1)
	end)
end)

test("Innkeeper gossip: wrong NPC, combat, venue loss and closed generation reject callbacks", function()
	WithGossip(function(g, t)
		g.OnShow(); g.Park(); t.pending[1](); eq(g.State().mode, "inactive", "closed generation not resurrected")
		g.ShowRow(); g.Open()
		UnitGUID = function() return "Creature-0-1-0-1-999-00001" end
		eq(g.Confirm(), false); eq(#t.starts, 0); eq(t.closed(), 0); eq(t.panel.ScrollBox.height, 403)
		UnitGUID = t.a.globals.UnitGUID
		g.ShowRow(); g.Open(); t.w.combat = true; eq(g.Confirm(), false); eq(#t.starts, 0)
		t.w.combat = false; g.ShowRow(); g.Open()
		t.w:Stand(t.a.name, FW.ROAD, true)
		eq(g.Confirm(), false); eq(#t.starts, 0, "resting alone does not grant inn access")
	end)
end)

test("Innkeeper gossip: optional native API failure and existing hidden state are safe", function()
	WithGossip(function(g, t)
		t.panel.ScrollBar:Hide(); eq(g.ShowRow(), true); g.Open(); g.Cancel(); g.Park()
		eq(t.panel.ScrollBar.shown, false, "original hidden native bar restored")
		C_GossipInfo.CloseGossip = nil; eq(g.ShowRow(), false); eq(t.panel.ScrollBox.height, 403)
		eq(g.State().mode, "inactive")
		C_GossipInfo.CloseGossip = function() end
		t.f.protected = true; eq(g.ShowRow(), false)
		t.f.protected = false
		t.panel.ScrollBox:SetPoint("BOTTOMRIGHT", t.f, "BOTTOMRIGHT", 0, 0)
		eq(g.ShowRow(), false, "a native layout constrained by two anchors is not resized")
		t.panel.ScrollBox.points[2] = nil
		t.panel.ScrollBox.protected = true; eq(g.ShowRow(), false); eq(t.panel.ScrollBox.height, 403)
		eq(g.State().mode, "inactive", "protected native geometry never borrowed")
	end)
end)

test("Innkeeper gossip: completed practice, membership loss and native close park exactly", function()
	WithGossip(function(g, t)
		t.a.ns.FarkleTable.Opts().innkeeperLearned = true
		eq(g.ShowRow(), true); eq(g.Open(), true); eq(g.Confirm(), true)
		eq(t.starts[1].extra, nil, "completed learner gets ordinary practice, not another prerequisite lesson")
		t.f:Show(); g.ShowRow(); g.Open()
		t.a.guild = nil; t.w:Fire(t.a, "PLAYER_GUILD_UPDATE", "player")
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 403)
		eq(g.ShowRow(), false, "actual membership predicate revoked")
		t.a.guild = H.World.GUILD; g.ShowRow(); g.Open()
		t.f:Hide(); eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 403)
		t.f:Show(); g.ShowRow(); g.Open()
		-- World loads Core's real stand-in gate after Gamepad.lua; exercise its hook runner,
		-- not a replacement gate. The dedicated gamepad pass covers actual input transitions.
		t.a.ns.Gate.Run("park", "innkeeper-gossip")
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 403)
	end)
end)

test("Innkeeper gossip: confirmation starts the real free lesson with the NPC's localized name", function()
	WithGossip(function(g, t)
		local FT = t.a.ns.FarkleTable
		local realPractice = FT.Practice
		local started
		FT.ShowUI = function(what, _, opts)
			eq(what, "practice"); eq(t.f.shown, false)
			UnitGUID = function() return nil end -- native close has cleared the gossip unit
			started = assert(realPractice(opts))
			return true
		end
		eq(g.ShowRow(), true); eq(g.Open(), true); eq(g.Confirm(), true)
		local game = assert(FT.Get(started))
		eq(game.guest, "Localized Innkeeper", "the actual NPC remains the opponent after native close")
		eq(game.target, 2000); eq(game.stake, 0); eq(game.learn, true)
		eq(game.role, "practice"); eq(game.inn, "inn_goldshire")
		eq(FT.TrainingComplete(), false, "acceptance alone does not unlock player matches")
		eq(#t.w:Sent({ from = t.a }), 0, "private training sends no network message")
	end)
end)

test("Innkeeper gossip: missing native capability retains the existing Olympus offer", function()
	WithGossip(function(g, t)
		GossipFrame = nil
		local FT = t.a.ns.FarkleTable
		local shown = 0
		FT.ShowUI = function(what, _, name)
			eq(what, "innkeeper"); eq(name, "Localized Innkeeper")
			eq(t.closed(), 0, "fallback keeps native conversation open")
			shown = shown + 1; return true
		end
		g.OnShow(); t.pending[1]()
		eq(shown, 1); eq(g.State().mode, "inactive")
	end)
end)

test("Innkeeper gossip: a delayed native close event still hides the conversation before training", function()
	WithGossip(function(g, t)
		C_GossipInfo.CloseGossip = function() end
		eq(g.ShowRow(), true); eq(g.Open(), true); eq(g.Confirm(), true)
		eq(t.f.shown, false); eq(#t.starts, 1)
	end)
end)

test("Innkeeper gossip: a fresh simulation still requires the lesson and trained simulation remains unlocked", function()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { bonesTrained = false,
		testBuild = { n = 1, base = "1.1.6", built = w.clock - 100, expires = w.clock + 86400 } })
	w:As(a, function()
		local FT, arena = a.ns.FarkleTable, a.ns.Arena
		eq(FT.CanPlayPlayers(), false)
		eq(arena.SetSim(true), true); eq(arena.Sim(), true)
		eq(FT.TrainingComplete(), false); eq(FT.CanPlayPlayers(), false,
			"test mode cannot show the player-game entries before the first lesson")
		local allowed, reason = FT.CanCreate({ guest = H.World.NAMES.fighterB, stake = 0 })
		eq(allowed, false); eq(reason, "training", "the actual table entry action also refuses the bypass")
		FT.Opts().innkeeperLearned = true
		eq(FT.TrainingComplete(), true); eq(FT.CanPlayPlayers(), true)
		arena.SetSim(false)
		eq(FT.CanPlayPlayers(), false, "simulation completion does not grant live training")
		FT.Opts().innkeeperLearned = true
		eq(FT.CanPlayPlayers(), true, "completed live training remains unlocked")
	end)
end)
