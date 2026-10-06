local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)

-- Deliberately separate from Forever's strict fixture: this optional native shape follows
-- Blizzard's Classic GossipFrame.xml and Shared/GossipFrameShared.lua in wow-ui-source.
-- It proves local integration behaviour, not that build70205 exposes these native frames.
local function Frame(parent)
	local f = { parent = parent, shown = true, height = 334, width = 300, scripts = {}, points = {} }
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
	function f:SetScript(k, call) self.scripts[k] = call end
	function f:HookScript(k, call)
		local before = self.scripts[k]
		self.scripts[k] = function(...) if before then before(...) end; call(...) end
	end
	function f:SetText(v) self.text = v end
	function f:SetTextColor() end
	function f:SetJustifyH() end
	function f:SetJustifyV() end
	function f:SetTexture(v) self.texture = v end
	function f:SetHighlightTexture(v) self.highlight = v end
	function f:CreateFontString() return Frame(self) end
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
	panel.ScrollBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -65)
	panel.GoodbyeButton = Frame(panel)
	local goods, home = {}, {}
	f.gossipOptions = { goods, home }
	local pending, closed, starts = {}, 0, {}
	a.globals.GossipFrame = f
	a.globals.CreateFrame = function(_, _, parent) return Frame(parent) end
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
		t.pending[1](); eq(g.State().mode, "row"); eq(scroll.height, 310)
		eq(scroll.points, anchors); eq(#anchors, 1, "native anchors never changed")
		eq(t.f.gossipOptions[1], t.goods); eq(t.f.gossipOptions[2], t.home); eq(#t.f.gossipOptions, 2)
		eq(g.State().row.parent, t.panel); eq(g.State().row.icon.texture, g.DICE_TEXTURE)
		g.State().row.scripts.OnClick(); eq(g.State().mode, "dialog")
		eq(g.State().dialog.parent, t.panel); eq(scroll.shown, false); eq(t.panel.ScrollBar.shown, false)
		eq(t.panel.GoodbyeButton.shown, true, "native Goodbye remains available")
		eq(t.closed(), 0); eq(#t.starts, 0, "opt-in alone does not start a game")
		g.State().dialog.cancel.scripts.OnClick(); eq(g.State().mode, "row"); eq(scroll.shown, true)
		g.Park(); eq(scroll.height, 334); eq(scroll.shown, true); eq(t.panel.ScrollBar.shown, true)
		eq(scroll.points, anchors)
	end)
end)

test("Innkeeper gossip: explicit confirmation closes NPC panel then launches first lesson", function()
	WithGossip(function(g, t)
		eq(g.ShowRow(), true); eq(g.Open(), true)
		eq(g.Confirm(), true); eq(t.closed(), 1); eq(#t.starts, 1)
		eq(t.starts[1].what, "practice"); eq(t.starts[1].extra.learn, true)
		eq(t.starts[1].extra.target, t.a.ns.FarkleRules.TARGETS[1])
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 334)
		eq(g.Confirm(), false, "stale confirm cannot launch twice"); eq(#t.starts, 1)
	end)
end)

test("Innkeeper gossip: wrong NPC, combat, venue loss and closed generation reject callbacks", function()
	WithGossip(function(g, t)
		g.OnShow(); g.Park(); t.pending[1](); eq(g.State().mode, "inactive", "closed generation not resurrected")
		g.ShowRow(); g.Open()
		UnitGUID = function() return "Creature-0-1-0-1-999-00001" end
		eq(g.Confirm(), false); eq(#t.starts, 0); eq(t.closed(), 0); eq(t.panel.ScrollBox.height, 334)
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
		C_GossipInfo.CloseGossip = nil; eq(g.ShowRow(), false); eq(t.panel.ScrollBox.height, 334)
		eq(g.State().mode, "inactive")
		C_GossipInfo.CloseGossip = function() end
		t.f.protected = true; eq(g.ShowRow(), false)
		t.f.protected = false
		t.panel.ScrollBox:SetPoint("BOTTOMRIGHT", t.f, "BOTTOMRIGHT", 0, 0)
		eq(g.ShowRow(), false, "a native layout constrained by two anchors is not resized")
		t.panel.ScrollBox.points[2] = nil
		t.panel.ScrollBox.protected = true; eq(g.ShowRow(), false); eq(t.panel.ScrollBox.height, 334)
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
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 334)
		eq(g.ShowRow(), false, "actual membership predicate revoked")
		t.a.guild = H.World.GUILD; g.ShowRow(); g.Open()
		t.f:Hide(); eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 334)
		t.f:Show(); g.ShowRow(); g.Open()
		-- World loads Core's real stand-in gate after Gamepad.lua; exercise its hook runner,
		-- not a replacement gate. The dedicated gamepad pass covers actual input transitions.
		t.a.ns.Gate.Run("park", "innkeeper-gossip")
		eq(g.State().mode, "inactive"); eq(t.panel.ScrollBox.height, 334)
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
