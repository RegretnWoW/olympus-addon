local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Window.lua. A stub the arena's core created for the screens to
-- fill. OlympusArenaFrame (700 x 470) and the three sections of the design (Arena, Farkle,
-- Lottery), reached from the buttons along its top. Sets ArenaUI.Toggle(tab) (Arena.Toggle
-- calls it). Closes in combat (PLAYER_REGEN_DISABLED) and comes back after when a table or a
-- countdown is live.
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data

-- The betting window (900 x 560), top to bottom, each part in its own area, 12 px inside the
-- border and 8 px apart (the owner's rules, 2026-09-30: nothing overlaps, no portrait, no title
-- strip, no side tabs, no row of section or staff buttons):
--   the section's panes as the game's own top tabs (Events, Rankings, Profile), the
--   status line on their right (a live search or match, the design; else the census and the next event);
--   a rehearsal's red banner, only when it applies;
--   the body: the list (300, its scroll bar on its own right edge) and the detail canvas (552);
--   the detail box (a title and its text);
--   the footer compartment, the games' own (Games.lua): the coin and the balance, then How to
--   play, on the left; the actions on the right: New fight (a menu: Find an opponent, Challenge
--   someone), at most two of the pane's, and More (a menu) for the rest.
-- Bones and the Lottery open their own windows (Games/); the staff's pages open from /oly arena
-- arbiter | bank | ledgers | director and the Games tab; the games' ledger's page (every member's,
-- 1.1.6) from the Games tab's Your games and Every game (ArenaHome.Open "games.mine" | "games.all").
-- Everything automatic where a default answers: the section and pane open where the player left
-- them, the event in view is the one that matters now (live, then taking bets, then next),
-- choices are remembered. Refreshed on ARENA_CHANGED (at most once a second).

-- (The owner's call, 2026-09-30: wider, so names are never cut; still inside 1024 x 768. A 12 px
-- margin inside, 8 px between parts.)
-- The owner's layout (2026-09-30, after build 5): the game's tabs along the top; under them on
-- the left the list panel, dark as the Olympus window's Census and Realm lists; on the right the
-- details on the parchment; the games' wood bar across the bottom. Inside 1024 x 768, everything
-- 16 px inside the border's inner edge, 12-16 px between parts.
ArenaUI.W, ArenaUI.H = 960, 700
ArenaUI.MARGIN = 16
ArenaUI.CONTENT_X = 16
ArenaUI.CONTENT_Y = 30 -- (the tabs are inside the grey block, under the metal's title bar: 1.1.5)
ArenaUI.CONTENT_W = ArenaUI.W - 32 -- 928
ArenaUI.LIST_W, ArenaUI.DETAIL_W = 300, ArenaUI.CONTENT_W - 300 - 16 -- 300 and 612
ArenaUI.CARD_W = ArenaUI.DETAIL_W - 24 -- the card inside its inset panel, 12 px each side
ArenaUI.BODY_H = 544
ArenaUI.FOOT_H = 56 -- the games' one bar (Games.BAR.H)
ArenaUI.FOOT_Y = ArenaUI.H - 10 - ArenaUI.FOOT_H -- its top, from the window's top
ArenaUI.SECTION_LABELS = { arena = "ARENA_SECTION_ARENA", farkle = "ARENA_SECTION_BONE", lottery = "ARENA_SECTION_LOTTERY" }
ArenaUI.SECTION_TIPS = { arena = "ARENA_SECTION_ARENA_TIP", farkle = "ARENA_SECTION_BONE_TIP", lottery = "ARENA_SECTION_LOTTERY_TIP" }

local state = { section = "arena", pane = {}, sel = {}, staff = nil }
ArenaUI.state = state

-- The panes of a section as shown now: a stand-in (spec.standin) only while nothing else is there
-- (the Lottery's own board, the Lottery's, replaces ours once it is in the build).
function ArenaUI.SectionPanes(section)
	local list = ArenaUI.Panes(section)
	local real = {}
	for _, e in ipairs(list) do if not e.spec.standin then real[#real + 1] = e end end
	if #real > 0 then return real end
	return list
end
local function PaneEntry()
	if state.staff then
		for _, e in ipairs(ArenaUI.StaffTabs()) do if e.key == state.staff then return e end end
		state.staff = nil
	end
	local list = ArenaUI.SectionPanes(state.section)
	local want = state.pane[state.section]
	for _, e in ipairs(list) do if e.key == want then return e end end
	local first = list[1]
	if first then state.pane[state.section] = first.key end
	return first
end
ArenaUI.PaneEntry = PaneEntry

-- The remembered place: "section:pane" in ns.db.arenaUI.tab.
local function Remember()
	local s = Kit.Settings()
	s.tab = state.section .. ":" .. tostring(state.pane[state.section] or "")
end
local function Recall()
	local s = Kit.Settings()
	local section, pane = tostring(s.tab or ""):match("^(%a+):(.*)$")
	if section and ArenaUI.SECTION_LABELS[section] and not (section ~= "arena" and ArenaUI.OpenGame) then
		state.section = section
		if pane ~= "" then state.pane[section] = pane end
	end
end
ArenaUI.Recall = Recall

-- Arena navigation is its own route stack. It never borrows the normal Olympus window's
-- full-page player profile or its Back state. A copied route is enough for the Arena Profile's
-- one-level Back button, including the selected ranking/event that led to that fighter.
function ArenaUI.CurrentRoute()
	local pane = not state.staff and state.pane[state.section] or nil
	local sel
	if pane then sel = state.sel[pane] end
	return { section = state.section, pane = pane, staff = state.staff, sel = sel }
end
function ArenaUI.RestoreRoute(route)
	if type(route) ~= "table" then return false end
	local section = route.section
	if not ArenaUI.SECTION_LABELS[section] then return false end
	if route.staff then
		local known = false
		for _, entry in ipairs(ArenaUI.StaffTabs()) do if entry.key == route.staff then known = true break end end
		if not known then return false end
		state.section, state.staff = section, route.staff
	else
		local spec = route.pane and ArenaUI.Pane(route.pane)
		if not spec or spec.section ~= section then return false end
		state.section, state.staff = section, nil
		state.pane[section] = route.pane
		state.sel[route.pane] = route.sel
	end
	Remember()
	ArenaUI.Refresh()
	return true
end

---------------------------------------------------------------------------
-- The model: what the window shows, worked out without frames (the tests read it too)
---------------------------------------------------------------------------

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		if ns.CaptureError then ns.CaptureError("arena pane", a) end
		return nil
	end
	return a, b, c
end
ArenaUI.Safe = Safe

-- The census count, the next event and the bank, for the header's line.
local function HeaderLine()
	local parts = {}
	local D = ns.Data
	local ok, s = pcall(function() return D and D.Summary and D.Summary() end)
	if ok and type(s) == "table" and (tonumber(s.online) or 0) > 0 then parts[#parts + 1] = L.ARENA_HEADER_ONLINE:format(ns.FormatNumber(s.online)) end
	local nextEv
	for _, ev in ipairs(Data.Events() or {}) do
		if not ev.over and ev.public then nextEv = ev break end
	end
	if nextEv then parts[#parts + 1] = ns.ArenaHome.EventTitle(nextEv) .. " · " .. ns.ArenaHome.StateWord(nextEv) end
	local w = ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet() and Data.Wallet() or nil
	local bank = type(w) == "table" and w.banks and w.banks[1]
	if bank then parts[#parts + 1] = L.ARENA_HEADER_BANK:format(bank.online and L.ARENA_ONLINE or L.ARENA_OFFLINE) end
	return table.concat(parts, " · ")
end

function ArenaUI.Model()
	local m = { section = state.section, staff = state.staff }
	local A = ns.Arena
	m.title = L.ARENA_WINDOW_TITLE .. (A.TestBuild() and (" " .. L.ARENA_WINDOW_TEST:format(A.TestBuild().n)) or "")
	m.header = HeaderLine()
	m.wallet = ns.ArenaHome.WalletLine()
	m.banner, m.bannerText = ns.ArenaHome.Banner()
	m.status = ns.ArenaHome.MatchLine()
	m.sections = {}
	for _, key in ipairs(ArenaUI.SECTIONS) do m.sections[#m.sections + 1] = { key = key, label = L[ArenaUI.SECTION_LABELS[key]], selected = key == state.section and not state.staff } end
	m.panes = {}
	for _, e in ipairs(ArenaUI.SectionPanes(state.section)) do m.panes[#m.panes + 1] = { key = e.key, label = e.spec.label } end
	m.staffTabs = {}
	for _, e in ipairs(ArenaUI.StaffTabs()) do m.staffTabs[#m.staffTabs + 1] = e.key end
	if not ns.IsMember() and not A.Sim() then
		m.closed = L.ARENA_MEMBERS_ONLY
		return m
	end
	if A.Off() then
		m.closed = L.ARENA_CLOSED
		return m
	end
	local e = PaneEntry()
	if not e then return m end
	m.pane = e.key
	local spec = e.spec
	m.full = spec.lines == nil and (spec.build ~= nil or spec.full == true)
	local st = { sel = state.sel[e.key], key = e.key }
	m.lines = Safe(spec.lines, st) or {}
	m.detailTitle, m.detailText = Safe(spec.text, st)
	m.buttons = Safe(spec.buttons, st) or {}
	m.selected = st.sel
	return m
end

---------------------------------------------------------------------------
-- The frame (built the first time the window opens)
---------------------------------------------------------------------------

local f
local function RequestedScale()
	local value = tonumber(Kit.Settings().scale) or 1
	return math.max(0.7, math.min(1.3, value))
end
function ArenaUI.ApplyWindowScale()
	if not f then return nil end
	return Kit.FitWindow(f, ArenaUI.W, ArenaUI.H, RequestedScale())
end
-- The window: on parchment, with a close button (the owner's call, 2026-09-30: no portrait, no side
-- tabs), and since 1.1.5 in the Olympus window's bronze metal (ns.Window, its title bar on top).
local function PanelTemplate()
	local frame = ns.Window("OlympusArenaFrame", UIParent, { inset = false, close = false, escape = false, title = L.TAB_ARENA })
	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -4, -4)
	frame.close:SetScript("OnClick", function() frame:Hide() end)
	return frame
end

local Refresh -- (below)

-- A section's tab: the games' one tab (Games.InkTab: Bones' How to play tabs, the owner's rule
-- 2026-09-30), sized to its words; a plain button where the games are not loaded.
local function PaneTab(i)
	local G = own.Games
	local tab
	if G and G.InkTab then
		tab = G.InkTab(f.paneBar, "", 70, nil, 13, true) -- (small, light: on the grey block)
		tab.template = "ink"
	else
		tab = Kit.Button(f, 90, 26, "", nil)
		tab.template = "fallback"
	end
	tab:SetID(i)
	f.paneButtons[i] = tab
	return tab
end
local function SetTab(tab, text, selected)
	if tab.template == "ink" then
		tab:SetLabel(text)
		local w = tab.text.GetStringWidth and tab.text:GetStringWidth()
		w = tonumber(w or 0) or 0
		if w > 0 then tab:SetWidth(math.max(56, math.ceil(w) + 14)); tab.text:SetWidth(tab:GetWidth()) end
		tab:SetSelected(selected)
		return
	end
	tab:SetText(text)
	Kit.Fit(tab, 80)
	if selected then tab:LockHighlight() else tab:UnlockHighlight() end
end

-- With the gamepad UI, Olympus's own pop-up of the same lines in its place (no Blizzard menu there:
-- the gamepad gate's "player-menu"): a button each, in columns of MENU_ROWS, under the button that
-- opened it; a pick closes it, and so does its X.
local MENU_ROWS, MENU_W, MENU_H = 12, 176, 24
local ownMenu
local function OwnMenu(owner, items)
	local f = ownMenu
	if not f then
		f = Kit.Frame("OlympusArenaMenu", 200, 80, { footer = false, stack = true, free = true, strata = "FULLSCREEN_DIALOG" })
		f.buttons = {}
		ownMenu = f
	end
	local n = #items
	for i, it in ipairs(items) do
		local b = f.buttons[i]
		if not b then
			b = Kit.Button(f, MENU_W, MENU_H, "", function(self)
				local fn = rawget(self, "fn")
				f:Hide()
				if fn then ns.SafeCall("arena menu", fn) end
			end)
			f.buttons[i] = b
		end
		local col, row = math.floor((i - 1) / MENU_ROWS), (i - 1) % MENU_ROWS
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + col * (MENU_W + 6), -32 - row * (MENU_H + 4))
		b.fn = it[2]
		Kit.SetButton(b, it[1], it.enabled ~= false and it[2] ~= nil)
		b:Show()
	end
	for i = n + 1, #f.buttons do f.buttons[i]:Hide() end
	local cols = math.max(1, math.ceil(n / MENU_ROWS))
	f:SetSize(18 + cols * (MENU_W + 6), 44 + math.min(n, MENU_ROWS) * (MENU_H + 4))
	f:ClearAllPoints()
	if type(owner) == "table" then f:SetPoint("TOP", owner, "BOTTOM", 0, -2) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
	f:Show()
	return true
end
ArenaUI.OwnMenu = function() return ownMenu end

-- A menu of the client's own (MenuUtil) from a button: items = { { text, fn, enabled } ... }; with
-- the gamepad UI, Olympus's own (OwnMenu, above). Without either, the first item that can be done
-- is done.
function ArenaUI.Menu(owner, items) -- gp:player-menu
	if ns.Gate.Allowed("player-menu") then
		if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
			pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
				for _, it in ipairs(items) do
					local fn = it[2]
					local b = root:CreateButton(it[1], function() if fn then ns.SafeCall("arena menu", fn) end end)
					if b and it.enabled == false and b.SetEnabled then b:SetEnabled(false) end
				end
			end)
			return true
		end
	elseif #items > 0 then
		return OwnMenu(owner, items)
	end
	for _, it in ipairs(items) do
		if it.enabled ~= false and it[2] then ns.SafeCall("arena menu", it[2]) return true end
	end
	return false
end

local function Build()
	if f then return f end
	f = PanelTemplate()
	ArenaUI.frame = f
	f:SetSize(ArenaUI.W, ArenaUI.H)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		if self.StopMovingOrSizing then self:StopMovingOrSizing() end
		if ns.Arena.Sim() then return end
		local point, _, rel, x, y = self:GetPoint(1)
		if type(point) == "string" then Kit.Settings().point = { point, rel, x, y } end
	end)
	local s = Kit.Settings()
	if type(s.point) == "table" and type(s.point[1]) == "string" then
		f:SetPoint(s.point[1], UIParent, type(s.point[2]) == "string" and s.point[2] or s.point[1], tonumber(s.point[3]) or 0, tonumber(s.point[4]) or 0)
	else
		f:SetPoint("CENTER", 0, 20)
	end
	ArenaUI.ApplyWindowScale()
	-- The body's parchment, inside the border.
	f.bg = Kit.Parchment(f, 0) -- (inside the metal: f.inner)
	f.paneButtons = {}
	-- The banner (a rehearsal's, only when it applies) over the content, then the status line.
	f.banner = Kit.Banner(f)
	f.banner:SetPoint("TOPLEFT", ArenaUI.CONTENT_X + ArenaUI.LIST_W + 16, -ArenaUI.CONTENT_Y)
	f.banner:SetPoint("TOPRIGHT", -40, -ArenaUI.CONTENT_Y)
	-- (the tabs' row: at the grey block's top, below)
	f.paneBar = CreateFrame("Frame", nil, f)
	f.paneBar.nav = {}
	f.paneBar:SetHeight(24)
	f.testNote = Kit.Text(f, "small", "RIGHT")
	f.testNote:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -8)
	f.testNote:SetWidth(360)
	f.testNote:SetTextColor(0.4, 0.36, 0.3)
	f.status = Kit.Text(f, "small", "LEFT")
	f.status:SetHeight(28)
	f.statusButton = Kit.Button(f, 80, 24, L.ARENA_CANCEL, function() ns.ArenaHome.Call("ArenaMatch", "Stop") end)
	Kit.Fit(f.statusButton, 60)
	f.statusButton:Hide()
	-- The body.
	f.body = CreateFrame("Frame", nil, f)
	-- The list panel (the owner's call on build 6): a solid grey block flush with the window, from
	-- under the tabs down to the games' bar and against its left edge, a clean divider on its right
	-- where the parchment starts; its rows the Census's ("hd": stripes, the highlight bar, light
	-- words), 12 px inside it.
	-- The fixed tabs have a light header; the list beneath keeps the Census's dark marble.
	f.listPanel = CreateFrame("Frame", nil, f)
	f.listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
	f.listPanel:SetSize(ArenaUI.LIST_W + 6, ArenaUI.FOOT_Y - 10)
	local header = f.listPanel:CreateTexture(nil, "BACKGROUND", nil, 2)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(35)
	header:SetColorTexture(0.24, 0.24, 0.24, 1)
	f.listPanel.header = header
	local shade = f.listPanel:CreateTexture(nil, "BACKGROUND", nil, 3)
	shade:SetPoint("TOPLEFT", 0, -35)
	shade:SetPoint("BOTTOMRIGHT")
	shade:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
	if shade.SetHorizTile then shade:SetHorizTile(true) end
	if shade.SetVertTile then shade:SetVertTile(true) end
	f.listPanel.shade = shade
	local divider = f.listPanel:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPRIGHT"); divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(2)
	divider:SetColorTexture(0.45, 0.30, 0.14, 1)
	f.listPanel.divider = divider
	f.list = Kit.List(f.listPanel, ArenaUI.LIST_W - 12, ArenaUI.FOOT_Y - 10 - 40 - 48, "hd")
	f.list:SetPoint("TOPLEFT", 12, -40)
	f.paneBar:SetParent(f.listPanel)
	f.paneBar:ClearAllPoints()
	f.paneBar:SetPoint("TOPLEFT", f.listPanel, "TOPLEFT", 8, -8)
	f.paneBar:SetPoint("TOPRIGHT", f.listPanel, "TOPRIGHT", -8, -8)
	-- the status line at the block's foot, light words on the marble
	f.status:SetParent(f.listPanel)
	f.status:SetTextColor(0.75, 0.72, 0.65)
	f.statusButton:SetParent(f.listPanel)
	f.canvases = {}
	f.heads = {}
	-- The detail box, over the footer.
	f.detailTitle = Kit.Text(f, "title", "LEFT")
	f.detailText = Kit.Text(f, nil, "LEFT")
	if f.detailText.SetJustifyV then f.detailText:SetJustifyV("TOP") end
	-- (on the parchment, right of the list's panel)
	f.detailText:SetPoint("TOPLEFT", ArenaUI.CONTENT_X + ArenaUI.LIST_W + 16, -(ArenaUI.FOOT_Y - 12 - 32))
	f.detailText:SetPoint("RIGHT", -16, 0)
	f.detailText:SetHeight(32)
	f.detailTitle:SetPoint("BOTTOMLEFT", f.detailText, "TOPLEFT", 0, 4)
	-- The bar across the bottom: the games' one bar (Games.Bar: Bones' wood, the coin and the
	-- balance, then How to play, on the left; the actions on the right, the same buttons, height
	-- and gaps in the three games).
	local G = own.Games
	if G and G.Bar then
		f.bar = G.Bar(f, { y = ArenaUI.FOOT_Y, h = ArenaUI.FOOT_H,
			balance = function()
				local w = Data.Wallet()
				return type(w) == "table" and type(w.g) == "table" and tonumber(w.g.bal) or 0
			end,
			tip = L.ARENA_WALLET_TITLE, helpText = L.ARENA_HOW_TO_PLAY,
			help = function() if ArenaUI.HowToPlay then ArenaUI.HowToPlay() elseif ArenaUI.Explain then ArenaUI.Explain(state.section, true) end end,
		})
		f.money, f.help = f.bar.wallet, f.bar.help
	end
	f.buttons = {}
	for i = 1, 4 do f.buttons[i] = Kit.Button(f, 120, 32, "", nil) end
	f.newFight = f.buttons[1]
	f:SetScript("OnShow", function()
		ArenaUI.ApplyWindowScale()
		ns.Arena.Involve("window", true)
		ns.EscapeCloses("OlympusArenaFrame")
		Kit.Sound("IG_MAINMENU_OPEN")
		Kit.FadeIn(f)
	end)
	f:SetScript("OnHide", function()
		ns.Arena.Involve("window", false)
		Kit.Sound("IG_MAINMENU_CLOSE")
		if ArenaUI.ChatPanel and ArenaUI.ChatPanel.Docked then ArenaUI.ChatPanel.Docked(false) end
	end)
	ns.EscapeCloses("OlympusArenaFrame")
	-- Combat closes it (the overlay and the arbiter console stay: the design); it comes back after
	-- combat while a countdown or a table of the player's is live.
	ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if f and f:IsShown() then
			ArenaUI.closedByCombat = true
			f:Hide()
		end
	end)
	ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if not ArenaUI.closedByCombat then return end
		ArenaUI.closedByCombat = false
		if ArenaUI.StillLive() then f:Show() Refresh() end
	end)
	ns.On("ARENA_CHANGED", function() if f and f:IsShown() then ns.SafeCall("arena window", Refresh) end end)
	local function DisplayChanged() if f then ArenaUI.ApplyWindowScale() end end
	for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
		pcall(ns.RegisterEvent, event, DisplayChanged)
	end
	f:Hide()
	return f
end
ArenaUI.Build = Build

-- After combat the window comes back only while something of the player's is live: a countdown
-- on an event he bets on or takes part in, or his Bones table.
function ArenaUI.StillLive()
	if Data.MyTable() then return true end
	local now = ns.Arena.Now()
	for _, ev in ipairs(Data.Events() or {}) do
		if not ev.over and (ev.live or (ev.lockAt and ev.lockAt > now)) then
			if ns.ArenaHome.Mine(ev) then return true end
			for _, t in ipairs(Data.Tickets({ eid = ev.id }) or {}) do if t then return true end end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Layout(m)
	-- The status line at the grey block's foot (its Cancel beside it); the body on the parchment
	-- right of the block, from the window's top (under a rehearsal's banner when it applies).
	f.status:ClearAllPoints()
	f.status:SetPoint("BOTTOMLEFT", f.listPanel, "BOTTOMLEFT", 12, 10)
	f.status:SetWidth(ArenaUI.LIST_W - 12 - (m.status and ((tonumber(f.statusButton:GetWidth()) or 60) + 8) or 0))
	f.statusButton:ClearAllPoints()
	f.statusButton:SetPoint("BOTTOMRIGHT", f.listPanel, "BOTTOMRIGHT", -8, 10)
	local top = -ArenaUI.CONTENT_Y
	if m.banner then top = top - 26 end
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", ArenaUI.CONTENT_X, top)
	f.body:SetSize(ArenaUI.CONTENT_W, ArenaUI.BODY_H + (m.banner and -26 or 0))
end

local function PaneButtons(m)
	if ns.Views and type(ns.Views.DrawNav) == "function" then
		local items = {}
		if #m.panes > 1 then
			for _, p in ipairs(m.panes) do
				local key = p.key
				items[#items + 1] = { text = p.label, selected = key == m.pane and not m.staff,
					onClick = function()
						Kit.Sound("IG_CHARACTER_INFO_TAB")
						if key == "arena.profile" and ArenaUI.ShowProfile then ArenaUI.ShowProfile(nil)
						else ArenaUI.ShowPane(key) end
					end }
			end
		end
		ns.Views.DrawNav(f.paneBar, items, ArenaUI.LIST_W - 10)
		f.paneButtons = f.paneBar.nav or {}
		return
	end
	local prev
	for i, p in ipairs(m.panes) do
		local b = f.paneButtons[i] or PaneTab(i)
		local key = p.key
		SetTab(b, p.label, key == m.pane and not m.staff)
		b:SetScript("OnClick", function()
			Kit.Sound("IG_CHARACTER_INFO_TAB")
			-- The Profile tab always means this player's canonical Arena Profile. A fighter
			-- reached from Rankings keeps a separate Back route instead of making the tab sticky.
			if key == "arena.profile" and ArenaUI.ShowProfile then ArenaUI.ShowProfile(nil)
			else ArenaUI.ShowPane(key) end
		end)
		b:ClearAllPoints()
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", f.paneBar, "LEFT", 0, 0) end
		-- (One pane alone needs no tab; a staff page keeps them, unlit, to come back.)
		b:SetShown(#m.panes > 1)
		prev = b
	end
	for i = #m.panes + 1, #f.paneButtons do f.paneButtons[i]:Hide() end
end

-- The footer's actions, right to left from the window's right margin, 8 px apart, each as wide
-- as its words: More (the pane's third action on), the pane's first two, New fight (the arena's).
local function FooterButtons(m)
	local defs = m.buttons or {}
	local shown = {}
	if state.section == "arena" and not m.staff then
		shown[#shown + 1] = { L.ARENA_NEW_FIGHT, function(self)
			ArenaUI.Menu(self, {
				{ L.ARENA_FIND_OPPONENT, function() ArenaUI.FindOpponent("d") end },
				{ L.ARENA_CHALLENGE_SOMEONE, function() ArenaUI.Challenge() end },
			})
		end, menu = true }
	end
	for i = 1, math.min(2, #defs) do shown[#shown + 1] = defs[i] end
	if #defs > 2 then
		local more = {}
		for i = 3, #defs do more[#more + 1] = { defs[i][1], defs[i][2], enabled = defs[i].enabled } end
		shown[#shown + 1] = { L.ARENA_MORE, function(self) ArenaUI.Menu(self, more) end, menu = true }
	end
	local placed = {}
	for i = #f.buttons, 1, -1 do f.buttons[i]:Hide() end
	for i = #shown, 1, -1 do
		local def, b = shown[i], f.buttons[i]
		Kit.SetButton(b, def[1], def.enabled, def.why)
		Kit.Fit(b, 80)
		local fn = def[2]
		b:SetScript("OnClick", function(self)
			Kit.Sound("IG_MAINMENU_OPTION")
			if fn then ns.SafeCall("arena button " .. tostring(def[1]), fn, self) end
		end)
		b:Show()
		placed[#placed + 1] = b
	end
	-- (Right-aligned by the games' bar, the same gaps as Bones' and the Lottery's.)
	if f.bar and f.bar.Place then f.bar.Place(placed) end
end

-- The canvas of a pane: its own frame, made the first time it shows.
local function Canvas(key, full)
	local c = f.canvases[key]
	if c then return c end
	c = CreateFrame("Frame", nil, f.body)
	if full then
		c:SetAllPoints(f.body)
	else
		c:SetSize(ArenaUI.DETAIL_W, ArenaUI.BODY_H)
		c:SetPoint("TOPLEFT", f.body, "TOPLEFT", ArenaUI.LIST_W + 16, 0)
	end
	c.key = key
	f.canvases[key] = c
	return c
end
ArenaUI.Canvas = function(key) return f and f.canvases[key] end

Refresh = function()
	if not f or not f:IsShown() then return end
	local m = ArenaUI.Model()
	ArenaUI.lastModel = m
	if f.money and f.money.Refresh then f.money.Refresh() end
	-- (a test build says so in small grey words in the top-right corner, the owner on build 7; a
	-- rehearsal keeps its red strip)
	local testNote = m.banner == "test"
	f.banner:Set(not testNote and m.banner or nil, m.bannerText)
	f.testNote:SetText(testNote and m.bannerText or "")
	if testNote then m.banner = nil end
	-- (The census and the next event where nothing else is said: the title strip is gone.)
	f.status:SetText(m.status or ArenaUI.lastSaid or m.header or "")
	f.statusButton:SetShown(m.status ~= nil)
	Layout(m)
	PaneButtons(m)
	for key, c in pairs(f.canvases) do if key ~= m.pane then c:Hide() end end
	if m.closed then
		f.list:SetLines({ { text = m.closed } })
		f.list:Show()
		f.listPanel:Show()
		f.detailTitle:SetText("")
		f.detailText:SetText("")
		for _, b in ipairs(f.buttons) do b:Hide() end
		return
	end
	local e = PaneEntry()
	if not e then return end
	local spec = e.spec
	local st = { sel = state.sel[e.key], key = e.key }
	if m.full then
		f.list:Hide()
		f.listPanel:Hide()
		local c = Canvas(e.key, true)
		if not rawget(c, "built") and spec.build then
			local ok, child = pcall(spec.build, c)
			if not ok and ns.CaptureError then ns.CaptureError("arena pane " .. e.key, child) end
			if ok and type(child) == "table" and child.SetAllPoints then child:SetAllPoints(c) end
			c.child = ok and type(child) == "table" and child or nil
			c.built = true
		end
		c:Show()
		if spec.refresh then Safe(spec.refresh, rawget(c, "child") or c, st) end
	else
		f.list:Show()
		f.listPanel:Show()
		-- A pane's own controls over its list, in the grey block (the rankings' filters).
		local headH = 0
		for key, h in pairs(f.heads) do if key ~= e.key then h:Hide() end end
		if spec.head then
			local h = f.heads[e.key]
			if not h then
				local ok, built = pcall(spec.head, f.listPanel)
				if ok and type(built) == "table" then
					h = built
					h:SetPoint("TOPLEFT", f.listPanel, "TOPLEFT", 12, -40)
					h:SetSize(ArenaUI.LIST_W - 12, spec.headH or 56)
					f.heads[e.key] = h
				elseif ns.CaptureError then ns.CaptureError("arena pane head " .. e.key, built) end
			end
			if h then
				h:Show()
				headH = (spec.headH or 56) + 8
				if spec.headRefresh then Safe(spec.headRefresh, h, st) end
			end
		end
		f.list:ClearAllPoints()
		f.list:SetPoint("TOPLEFT", f.listPanel, "TOPLEFT", 12, -(40 + headH))
		f.list:SetHeight(ArenaUI.FOOT_Y - 10 - 40 - 48 - headH)
		f.list:SetLines(m.lines)
		local c = Canvas(e.key, false)
		c:Show()
		if spec.detail then Safe(spec.detail, c, st) end
	end
	f.detailTitle:SetText(m.detailTitle or "")
	f.detailText:SetText(m.detailText or "")
	FooterButtons(m)
end
ArenaUI.Refresh = function() ns.SafeCall("arena window", Refresh) end

---------------------------------------------------------------------------
-- Moving about
---------------------------------------------------------------------------

-- The first time a section opens, its explanation pop-up (Popups.lua: ArenaUI.Explain) shows by
-- itself, over the window.
local function Explained(section)
	if ns.Arena.Sim() or not ArenaUI.Explain then return end
	if Kit.Recall("explained:" .. section) then return end
	ArenaUI.Explain(section)
end

function ArenaUI.ShowSection(section)
	if not ArenaUI.SECTION_LABELS[section] then return end
	-- (Only explicit test/sim builds may replace these sections with the local practice labs.)
	if section == "lottery" and ArenaUI.OpenGame and ArenaUI.OpenGame(section) then return end
	state.section, state.staff = section, nil
	Remember()
	ArenaUI.Refresh()
	if f and f:IsShown() then Explained(section) end
end
function ArenaUI.ShowPane(key, sel)
	local spec = ArenaUI.Pane(key)
	if not spec then return false end
	state.section, state.staff = spec.section, nil
	state.pane[spec.section] = key
	if sel ~= nil then state.sel[key] = sel end
	Remember()
	ArenaUI.Refresh()
	return true
end
function ArenaUI.ShowStaff(key)
	for _, e in ipairs(ArenaUI.StaffTabs()) do
		if e.key == key then
			state.staff = key
			ArenaUI.Refresh()
			return true
		end
	end
	return false
end
-- Selects a row of the pane in view (its list's click).
function ArenaUI.Select(key, id)
	state.sel[key] = id
	if key == "arena.events" and ns.ArenaHome.Opened then ns.ArenaHome.Opened(id) end
	ArenaUI.Refresh()
end
function ArenaUI.Selected(key) return state.sel[key] end

-- The window shows (built on first use), on its remembered place; the rules pop-up first, the
-- first time, over it (the design: viewing needs no yes).
local rulesAsked = false
local function Show()
	Build()
	if not f:IsShown() then f:Show() end
	ArenaUI.Refresh()
	local r = ns.db and ns.db.arenaRules
	if not rulesAsked and not ns.Arena.Sim() and type(r) ~= "table" and ArenaUI.ShowRules then
		rulesAsked = true
		ArenaUI.ShowRules()
	else
		Explained(state.section)
	end
	return f
end
ArenaUI.Show = Show

-- Where each place of ArenaHome.Open goes: a pane, a staff tab, or a pop-up of its own.
local PLACES = {
	events = "arena.events", rankings = "arena.rankings",
	bone = "bone.play", ["bone.play"] = "bone.play", ["bone.live"] = "bone.live", ["bone.history"] = "bone.history",
}
function ArenaUI.Open(where, arg)
	if where == "bone.invite" and ns.FarkleTable and not ns.FarkleTable.CanOpen() then
		ArenaUI.Say(L.FARKLE_LOG_TAVERN_REST); return false
	end
	if (where == "wallet" or where == "bets" or where == "bank" or where == "ledgers")
		and not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then return false end
	Recall()
	if where == nil or where == "" then
		state.section, state.staff = "arena", nil
		Remember()
		return Show()
	end
	if where == "wallet" or where == "bets" then
		Show()
		return ArenaUI.Wallet and ArenaUI.Wallet(where == "bets" and "bets" or nil)
	end
	if where == "rules" then return ArenaUI.ShowRules and ArenaUI.ShowRules(type(arg) == "function" and arg or nil) end
	if where == "find" then
		Show()
		return ArenaUI.OpenFind and ArenaUI.OpenFind(arg == "b" and "b" or "d")
	end
	if where == "overlay" then return ArenaUI.Overlay and ArenaUI.Overlay.Show() end
	if where == "copy" then return ArenaUI.CopyPane() end
	if where == "profile" or where == "history" then
		Show()
		if ArenaUI.ShowProfile then ArenaUI.ShowProfile(arg)
		else ArenaUI.ShowPane("arena.profile", arg or false) end
		return f
	end
	-- The staff's pages (no buttons of theirs in the window, 2026-09-30): /oly arena arbiter,
	-- bank, ledgers, director, and the Games tab.
	local STAFF = { director = "director", arbiter = "staff.arbiter", bank = "staff.bank", ledgers = "staff.ledgers" }
	if STAFF[where] then
		Show()
		ArenaUI.ShowStaff(STAFF[where])
		return
	end
	-- The games' ledger (1.1.6): his own games (the Games tab's Your games), an auditor's every game.
	if where == "games.mine" or where == "games.all" then
		Show()
		return ArenaUI.ShowGames and ArenaUI.ShowGames(where == "games.all" and "all" or "mine")
	end
	if where == "bone.invite" then
		Show()
		ArenaUI.ShowPane("bone.play")
		return ArenaUI.BoneInvite and ArenaUI.BoneInvite(arg)
	end
	if where == "lottery" then
		if ns.Lottery and ns.Lottery.Wagers and not ns.Lottery.Wagers() and ArenaUI.LotteryPracticeWindow then
			return ArenaUI.LotteryPracticeWindow(true)
		end
		if ArenaUI.OpenGame and ArenaUI.OpenGame("lottery") then return end
		Show()
		return ArenaUI.ShowSection("lottery")
	end
	-- (/oly games photos: the games' photo tour, Games/Hookup.lua)
	if where == "games" and arg == "photos" and ArenaUI.GamesPhotos then return ArenaUI.GamesPhotos() end
	-- (An explicit test/sim build may open the local lab; production stays on the real-data panes.)
	if where == "games" and ArenaUI.OpenGame and ArenaUI.OpenGame("games") then
		return
	end
	local key = PLACES[where]
	Show()
	if key then
		if key == "arena.events" and arg then
			state.sel[key] = arg
			if ns.ArenaHome.Opened then ns.ArenaHome.Opened(arg) end
		end
		if key == "bone.live" and arg then state.sel[key] = arg end
		ArenaUI.ShowPane(key)
	end
	return f
end
function ArenaUI.Toggle(tab)
	if f and f:IsShown() and (tab == nil or tab == "") then
		f:Hide()
		return
	end
	return ArenaUI.Open(tab)
end
function ArenaUI.Frame() return f end
function ArenaUI.IsShown() return f ~= nil and f:IsShown() end
function ArenaUI.Hide() if f then f:Hide() end end

-- A table takes the place of the games page that opened it. Other Olympus pages stay put.
function ArenaUI.HideForGame()
	ArenaUI.Hide()
	local G = own.Games
	if type(G) == "table" and G.CloseHub then G.CloseHub() end
	local U = ns.UI
	if U and U.IsShown and U.IsShown() and U.PageId and U.PageId() == "arena/" and U.Toggle then U.Toggle() end
end

-- The pane in view as plain text (its Copy button, /oly arena copy): no colour, texture or link.
function ArenaUI.CopyText()
	local e = PaneEntry()
	if not e then return "" end
	local st = { sel = state.sel[e.key], key = e.key }
	local text = Safe(e.spec.copy, st)
	if type(text) == "string" then return Kit.Plain(text) end
	local out = {}
	for _, line in ipairs(Safe(e.spec.lines, st) or {}) do
		local t = line.text or (line.cols and table.concat(line.cols, "  ")) or ""
		if line.right and line.right ~= "" then t = t .. "  " .. line.right end
		out[#out + 1] = (line.indent and "  " or "") .. t
	end
	return Kit.Plain(table.concat(out, "\n"))
end
function ArenaUI.CopyPane()
	local text = ArenaUI.CopyText()
	Kit.Copy(L.ARENA_WINDOW_TITLE, text)
	return text
end
