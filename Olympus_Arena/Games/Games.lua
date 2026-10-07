local _, own = ...; local ns = own.host; if not ns then return end
ns = own -- (the lab's tables stay the companion's own: Olympus has its own ns.Wallet and ns.FarkleRules)
-- (Ported from the Olympus Frame Lab, 2026-09-30: the practice preview, inside the arena.)
-- The Olympus Frame Lab's games, shared by their windows (Bones's table, Farkle.lua; the
-- Lottery's, Bicho.lua) and routed by Lab.lua. Loaded before the games.
--  * The shared practice wallet (ns.Wallet): its balance and the history of every movement (each
--    Lottery bet and payout, each Bones stake and result, practice gold added), in exact
--    copper. Memory only: a /reload starts over at 100g.
--  * The games' window (/oly games, and /lab): the only way between the games. A row each (the
--    Arena greyed, soon; Bones; the Lottery; the Wallet), Play opens it.
--  * Each game's window is its own: no tabs, no switch to another game. One window at a time:
--    opening one closes the other's and hides the games' window. Each opens centred.
--  * The same structure in both game windows: no title bar strip, no portrait; a footer
--    compartment at the bottom holding the window's action buttons, laid out alike: How to play
--    and the wallet (a coin button and the balance, itself a button) on the left, the game's main
--    actions on the right (Games.Footer, Games.WalletButton).
--  * The lab's one pop-up (Games.Popup: How to play, the Lottery's letter, the Wallet), centred
--    over its window, a strata above it; Close, the X or Escape go back to the window, and Escape
--    closes a pop-up before its window.
local floor, min, max = math.floor, math.min, math.max

local Games = {}
ns.Games = Games
function Games.WalletShown()
	local C = own.host and own.host.Compliance
	return C and C.Wallet and C.Wallet() == true or false
end
local ICONS = "Interface\\Icons\\"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"
-- Olympus's writ parchment (QuestBG's page) in the game's dialog border, dark ink pressed into
-- the page, the quest frame's ornamental break: the Lottery table's look.
local PARCHMENT, PAGE = "Interface\\QuestFrame\\QuestBG", { 0, 296 / 512, 0, 331 / 512 }
local INK, SOFT, DIM = { 0.15, 0.07, 0.02 }, { 0.3, 0.18, 0.07 }, { 0.4, 0.34, 0.28 }
local RED, GREEN = { 0.55, 0.08, 0.03 }, { 0.1, 0.36, 0.04 }
local FRAME, FRAME_DIM = { 0.86, 0.66, 0.3 }, { 0.55, 0.52, 0.48 }
local GREY = { 0.6, 0.6, 0.6 }

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe6c35cOlympus:|r " .. msg) end

---------------------------------------------------------------------------
-- Money as the game writes it (the Lottery's Bicho.Money, Coins and Signed are these)
---------------------------------------------------------------------------

local GOLD, SILVER = 10000, 100
local function Commas(n)
	local s, k = tostring(n), 0
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
-- Copper as text: 12g 40s 5c (thousands with commas; the parts that are zero left out, 0 as 0g).
function Games.Money(c)
	c = floor(c or 0)
	local sign = c < 0 and "-" or ""
	c = math.abs(c)
	local g, s, k = floor(c / GOLD), floor(c % GOLD / SILVER), c % SILVER
	local out = {}
	if g > 0 then out[#out + 1] = Commas(g) .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if k > 0 then out[#out + 1] = k .. "c" end
	if #out == 0 then return "0g" end
	return sign .. table.concat(out, " ")
end
-- The same with the game's coins, as its money frames show it: 12(gold) 40(silver) 5(copper).
local COINS = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
Games.COINS = COINS
function Games.Coins(c)
	c = floor(c or 0)
	local parts, out = { floor(c / GOLD), floor(c % GOLD / SILVER), c % SILVER }, {}
	for i, n in ipairs(parts) do
		if n > 0 or (i == 1 and c == 0) then out[#out + 1] = (i == 1 and Commas(n) or tostring(n)) .. "|T" .. COINS[i] .. ":0:0:2:0|t" end
	end
	return table.concat(out, " ")
end
-- A gain or a loss: +9(g) 95(s), -22(g), 0(g).
function Games.Signed(c)
	if c > 0 then return "+" .. Games.Coins(c) elseif c < 0 then return "-" .. Games.Coins(-c) end
	return Games.Coins(0)
end
local Money, Coins, Signed = Games.Money, Games.Coins, Games.Signed

---------------------------------------------------------------------------
-- The shared practice wallet
---------------------------------------------------------------------------

local Wallet = { START = 100 * GOLD, balance = 100 * GOLD, history = {} }
ns.Wallet = Wallet
local function Stamp()
	if type(date) == "function" then
		local ok, s = pcall(date, "%d %b %H:%M")
		if ok and type(s) == "string" then return s end
	end
	return ""
end
-- A movement: amount (signed copper) in or out, what it was (in full), how the Wallet's history
-- words it (forms: the wording, then shorter ones for a line too narrow), the game. Every change
-- of the balance goes through here, so the history adds up to the balance.
function Wallet.Move(amount, what, forms, game)
	amount = floor(amount or 0)
	forms = type(forms) == "table" and forms or { forms or what }
	Wallet.balance = Wallet.balance + amount
	table.insert(Wallet.history, 1, { amount = amount, what = what, forms = forms, short = forms[1], game = game, when = Stamp(),
		after = Wallet.balance, seq = #Wallet.history + 1 })
	if Games.WalletChanged then Games.WalletChanged() end
	return Wallet.balance
end
-- For testing: practice gold added, the wallet back to its start, or set to an amount (a line each).
function Wallet.Add(amount) return Wallet.Move(amount or 100 * GOLD, "Practice gold added", "Practice gold added", "wallet") end
function Wallet.Reset()
	Wallet.history = {}
	return Wallet.Move(Wallet.START - Wallet.balance, "Wallet reset to " .. Money(Wallet.START), "Wallet reset", "wallet")
end
function Wallet.Set(c) return Wallet.Move(c - Wallet.balance, "Practice gold set to " .. Money(c), "Practice gold set", "wallet") end

---------------------------------------------------------------------------
-- Drawing on the parchment
---------------------------------------------------------------------------

-- One line of dark ink on the parchment, never wrapped: its top left at (x, y) of `rel`, y down.
local function Ink(parent, rel, x, y, w, size, color, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if not fs:SetFont(font or STANDARD_TEXT_FONT, size, "") then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowColor(1, 0.94, 0.8, 0.6); fs:SetShadowOffset(1, -1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetPoint("TOPLEFT", rel, "TOPLEFT", x, -y)
	fs:SetWidth(w); fs:SetWordWrap(false)
	return fs
end
local function Tint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
-- The first of the texts that fits the line's box with 5% to spare (the last one whatever it measures).
local function Fit(fs, list)
	local w = fs:GetWidth()
	for i, t in ipairs(list) do
		fs:SetText(t)
		local sw = fs:GetStringWidth()
		if i == #list or (type(sw) == "number" and sw <= w * 0.95) then return end
	end
end
Games.Fit = Fit
-- The quest frame's ornamental break (UI-HorizontalBreak), its curls at their own shape.
local function Break(parent, x, y, w, h)
	local cap = floor(40 * h / 18 + 0.5)
	for _, p in ipairs({ { 23, 63, 0, cap }, { 63, 192, cap, w - 2 * cap }, { 192, 232, w - cap, cap } }) do
		local t = parent:CreateTexture(nil, "BORDER", nil, 1)
		t:SetTexture("Interface\\QuestFrame\\UI-HorizontalBreak"); t:SetTexCoord(p[1] / 256, p[2] / 256, 7 / 32, 25 / 32)
		t:SetPoint("TOPLEFT", parent, "TOPLEFT", x + p[3], -y); t:SetSize(p[4], h)
	end
end
local function Button(parent, label, w, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 32); b:SetText(label)
	b:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
	b:SetScript("OnClick", fn)
	return b
end
-- A window of the lab's (the games' window, the Wallet): QuestBG's page in the game's dialog
-- border (its dark tile hidden, it would cover the parchment), the X, movable, centred.
local function Window(name, w, h)
	local f = CreateFrame("Frame", name, UIParent)
	f:Hide()
	f:SetSize(w, h)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
	f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(PARCHMENT); bg:SetTexCoord(PAGE[1], PAGE[2], PAGE[3], PAGE[4])
	bg:SetPoint("TOPLEFT", 10, -10); bg:SetPoint("BOTTOMRIGHT", -10, 10)
	f.bg = bg
	local ok, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if ok and border then
		border:SetAllPoints()
		if rawget(border, "Bg") then border.Bg:Hide() end
		f.border = border
	end
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetFrameLevel(f:GetFrameLevel() + 10)
	f.close:SetScript("OnClick", function() f:Hide() end)
	return f
end

---------------------------------------------------------------------------
-- The lab's one pop-up
---------------------------------------------------------------------------

-- For every game's How to play and its other notes (Bones's How to play is the pattern):
-- QuestBG's page in a thin dark frame, bronze at its outer edge; on UIParent a strata above the
-- game windows (FULLSCREEN_DIALOG over their DIALOG, so none of a table's buttons draws on it),
-- centred over its game's window each time it opens (the same centre); movable; the X at its top
-- right; Escape (ns.EscapeCloses: with mouse and keyboard only). Built hidden, so building it
-- makes no sound. The caller adds its Got it and hooks (HookScript) its OnShow and OnHide.
local POPUP_PAGE = { 0, 300 / 512, 0, 336 / 512 }
local POPUP_FRAME = { { 3, 0.07, 0.04, 0.02, 0.95 }, { 4, 0.45, 0.28, 0.12, 0.7 } }   -- width, colour
function Games.Popup(name, w, h, over)
	local f = CreateFrame("Frame", name, UIParent)
	f:Hide()
	f:SetSize(w, h)
	f:SetPoint("CENTER", over or UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
	f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetTexture(PARCHMENT); f.bg:SetTexCoord(POPUP_PAGE[1], POPUP_PAGE[2], POPUP_PAGE[3], POPUP_PAGE[4]); f.bg:SetAllPoints()
	f.frame = {}
	-- The game windows' own frame round every pop-up (the owner on build 4, 2026-09-30: How to play,
	-- the Wallet, the letter...): DialogBorderTemplate, 10 px outside the page so none of it is
	-- covered; the thin lines below only where the client lacks it.
	local okB, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if okB and border then
		border:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 10)
		border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 10, -10)
		if rawget(border, "Bg") then border.Bg:Hide() end
		f.border = border
	end
	for _, e in ipairs(f.border and {} or POPUP_FRAME) do
		local fw, r, g, b, a = e[1], e[2], e[3], e[4], e[5]
		for _, sd in ipairs({
			{ "TOPLEFT", -fw, fw, "TOPRIGHT", fw, 0 }, { "BOTTOMLEFT", -fw, 0, "BOTTOMRIGHT", fw, -fw },
			{ "TOPLEFT", -fw, 0, "BOTTOMLEFT", 0, 0 }, { "TOPRIGHT", 0, 0, "BOTTOMRIGHT", fw, 0 },
		}) do
			local t = f:CreateTexture(nil, "BORDER")
			t:SetColorTexture(r, g, b, a)
			t:SetPoint(sd[1], f, sd[1], sd[2], sd[3]); t:SetPoint(sd[4], f, sd[4], sd[5], sd[6])
			f.frame[#f.frame + 1] = t
		end
	end
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", f.border and 6 or 2, f.border and 6 or 2)
	f.close:SetScript("OnClick", function() f:Hide() end)
	-- over its window (f.over: the Wallet's is whichever window asked for it), wherever that
	-- window was dragged
	f.over = over
	-- Escape: through Olympus's ns.EscapeCloses each time it shows, so with the gamepad UI on no name
	-- of its goes to UISpecialFrames (Blizzard's gamepad menus read that list unprotected), and a
	-- name put there before a switch leaves it when it is the last one.
	f:SetScript("OnShow", function()
		local EscapeCloses = own.host.EscapeCloses
		if type(EscapeCloses) == "function" then EscapeCloses(name) end
		if f.over then f:ClearAllPoints(); f:SetPoint("CENTER", f.over, "CENTER", 0, 0) end
	end)
	return f
end
Games.POPUP = { PAGE = POPUP_PAGE, FRAME = POPUP_FRAME }

-- Escape closes what is on top: a window's pop-up first, then the window. The client's
-- CloseSpecialWindows hides every shown frame named in UISpecialFrames at once, so a window is
-- named there only while it is shown and none of its pop-ups is; the list changes a frame later,
-- never while the client walks it.
local function Special(name, on) -- gp:escape-list
	-- With the gamepad UI Olympus writes nothing to that list (Core.lua's ns.EscapeCloses, the gate's
	-- "escape-list"): the windows close with their own X there; a name put there before the switch
	-- leaves only when it is the last one, so nothing of Blizzard's moves.
	local gamepad = not own.host.Gate.Allowed("escape-list")
	if type(UISpecialFrames) ~= "table" then return end
	local at
	for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then at = i end end
	if gamepad then
		if at and at == #UISpecialFrames then UISpecialFrames[at] = nil end
		return
	end
	if on and not at then table.insert(UISpecialFrames, name)
	elseif not on and at then table.remove(UISpecialFrames, at) end
end
local escapes = {}         -- [window] = { name, its pop-ups }
local wallet               -- the Wallet pop-up (below), a pop-up of whichever window it is over
function Games.Escape(name, win, popups)
	escapes[win] = { name = name, popups = popups or {} }
	C_Timer.After(0, function()
		local on = win:IsShown()
		for _, p in ipairs(popups or {}) do if p:IsShown() then on = false end end
		if wallet and wallet:IsShown() and wallet.over == win then on = false end
		Special(name, on)
	end)
end
local function EscapeAgain(win)
	local e = win and escapes[win]
	if e then Games.Escape(e.name, win, e.popups) end
end


---------------------------------------------------------------------------
-- The sections of the games' window
---------------------------------------------------------------------------

-- In the games' window's order. Each icon is in Forever 1.60.1.70124's ManifestInterfaceData (the
-- first the client has is used): the Arena's two swords (the design), Bones's
-- the Dirty Knucklebones' bone dice, the Lottery's the Darkmoon Faire Prize Ticket, the Wallet's
-- a pile of gold coins. desc: one line, the first of them that fits. module: the game's Open,
-- Close and Window (ns.Farkle, ns.Bicho); the Wallet opens its pop-up over the games' window.
local GAMES = {
	{ key = "arena", name = "Arena", icons = { ICONS .. "INV_Sword_04", ICONS .. "Ability_DualWield" }, module = "ArenaWindow",
		desc = { "Duels and tournaments: the events, the rankings, your history.", "Duels and tournaments." } },
	{ key = "bonethrow", name = "Bones", icons = { ICONS .. "INV_Misc_Bone_10", ICONS .. "INV_Misc_Bone_06" }, module = "Farkle",
		desc = { "Six bone dice against a practice opponent.", "Bone dice against a practice opponent." } },
	{ key = "lottery", name = "Lottery", icons = { ICONS .. "INV_Misc_Ticket_Darkmoon_01", ICONS .. "INV_Misc_Coin_02" }, module = "Bicho",
		desc = { "Pick one of 25 beasts; five rolls draw it.", "Pick a beast; five rolls draw it." } },
	{ key = "wallet", name = "Wallet", icons = { "Interface\\MoneyFrame\\UI-GoldIcon", ICONS .. "INV_Misc_Coin_01", ICONS .. "INV_Misc_Bag_10" }, play = "Open",
		desc = { "The practice gold the games share, and its history.", "The games' practice gold." } },
}
Games.LIST = GAMES
local WALLET_ICON = GAMES[4].icons
local function Module(g) return g and g.module and ns[g.module] end
local function Find(key) for _, g in ipairs(GAMES) do if g.key == key then return g end end end
-- the first icon the client has (Olympus's UI.FirstTexture)
local function FirstTexture(paths)
	for _, p in ipairs(paths) do
		if type(GetFileIDFromPath) ~= "function" then return p end
		local ok, id = pcall(GetFileIDFromPath, p)
		if ok and id then return p end
	end
	return paths[#paths]
end
Games.FirstTexture = FirstTexture

local hub

-- A game's window was shown (the games' window's Play or its own command): the other game's
-- closes, the games' window hides (and the Wallet pop-up, when it was over another window).
function Games.Shown(key)
	for _, g in ipairs(GAMES) do
		local m = Module(g)
		if g.key ~= key and m and m.Close then m.Close() end
	end
	if hub and hub:IsShown() then hub:Hide() end
end

-- The games' window's Play: it hides, the game's window opens.
function Games.Open(key)
	local g = Find(key)
	if not g or g.soon then return end
	if InCombatLockdown() then return Say("not in combat.") end
	if key == "wallet" then return Games.ShowWallet(hub and hub:IsShown() and hub or nil) end
	local m = Module(g)
	if not (m and m.Open) then return end
	if hub then hub:Hide() end
	m.Open()
end

---------------------------------------------------------------------------
-- The footer compartment and the wallet's buttons (both game windows alike)
---------------------------------------------------------------------------

Games.FOOT = { BUTTON = 32, HELP_W = 130, COIN = 32, BALANCE_W = 170, PAD = 12 }

-- The footer's compartment: from y to the window's bottom (less its inset), set off by a line
-- above it and a darker wash; the window's action buttons live in it. Returns the wash.
function Games.Footer(win, y, h, inset)
	inset = inset or 8
	local line = win:CreateTexture(nil, "BORDER", nil, 3)
	line:SetColorTexture(0.2, 0.1, 0.03, 0.45)
	line:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -y); line:SetSize(win:GetWidth() - 2 * inset, 1)
	local lit = win:CreateTexture(nil, "BORDER", nil, 3)
	lit:SetColorTexture(1, 0.92, 0.72, 0.35)
	lit:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -(y + 1)); lit:SetSize(win:GetWidth() - 2 * inset, 1)
	local wash = win:CreateTexture(nil, "BORDER", nil, 1)
	wash:SetColorTexture(0.35, 0.2, 0.07, 0.14)
	wash:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -(y + 2)); wash:SetSize(win:GetWidth() - 2 * inset, h - 2)
	return { line = line, lit = lit, wash = wash, y = y, h = h }
end

-- The games' one tab (Bones' How to play tabs, the owner's rule 2026-09-30: every tab of the
-- games): the name in Morpheus, faded when not shown, an ink bar under the one shown, a faint one
-- while the mouse is on another. InkTab(parent, label, w, fn) -> tab; tab:SetSelected(on).
local TAB_OFF, TAB_ON, TAB_BAR = { 0.37, 0.23, 0.09 }, { 0.15, 0.07, 0.02 }, { 0.42, 0.12, 0.03 }
-- (light: the same tab on a dark ground, the arena's grey block: pale gold words, a gold bar)
local LIGHT_OFF, LIGHT_ON, LIGHT_BAR = { 0.72, 0.64, 0.48 }, { 1, 0.82, 0 }, { 1, 0.82, 0 }
function Games.InkTab(parent, label, w, fn, size, light)
	local OFF, ON, BAR = light and LIGHT_OFF or TAB_OFF, light and LIGHT_ON or TAB_ON, light and LIGHT_BAR or TAB_BAR
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(w, 28)
	tab.text = tab:CreateFontString(nil, "ARTWORK")
	tab.text:SetFont(MORPHEUS, size or 18, "")
	tab.text:SetPoint("CENTER", 0, 0); tab.text:SetWidth(w); tab.text:SetWordWrap(false)
	tab.text:SetText(label)
	tab.text:SetTextColor(OFF[1], OFF[2], OFF[3])
	tab.bar = tab:CreateTexture(nil, "ARTWORK")
	tab.bar:SetColorTexture(BAR[1], BAR[2], BAR[3], 1); tab.bar:SetSize(math.max(20, w - 36), light and 2 or 3)
	tab.bar:SetPoint("TOP", tab, "BOTTOM", 0, light and 2 or -2); tab.bar:Hide()
	-- (the bar follows the tab's width)
	local setWidth = tab.SetWidth
	function tab:SetWidth(v) setWidth(self, v); self.bar:SetWidth(math.max(20, v - (light and 12 or 36))) end
	function tab:SetSelected(on)
		self.selected = on == true
		local c = self.selected and ON or OFF
		self.text:SetTextColor(c[1], c[2], c[3])
		self.bar:SetAlpha(0.9); self.bar:SetShown(self.selected)
	end
	function tab:SetLabel(t) self.text:SetText(t) end
	tab:SetScript("OnClick", fn)
	tab:SetScript("OnEnter", function(self) if not self.selected then self.bar:SetAlpha(0.35); self.bar:Show() end end)
	tab:SetScript("OnLeave", function(self) if not self.selected then self.bar:Hide() end end)
	return tab
end

-- The games' bottom bar, ONE for the three games (the owner's rule, 2026-09-30): Bones' wood strip
-- across the window's bottom (its table's wood, a shade darker) under the footer's line; on the
-- left the coin and the balance, then How to play; on the right the actions, the same button
-- template, height and gaps; only their words differ per game.
-- opts = { y (its top, from the window's top), h, inset (the window's inner edge), balance, tip,
-- helpText, help (How to play's click) }. Returns { wood, foot, wallet, help, Place(buttons) }:
-- Place lays the given buttons from the right edge leftwards, 8 px apart.
Games.WOOD = { file = "Interface\\AddOns\\Olympus_Arena\\media\\games\\farkle-table", coords = { 4 / 1024, 1020 / 1024, 300 / 512, 372 / 512 }, tint = { 0.86, 0.8, 0.72 } }
Games.BAR = { H = 56, BUTTON_H = 32, GAP = 8, PAD = 10 } -- (H: Bones' footer; one height for the three)
function Games.WoodBar(win, x, y, w, h)
	-- (BORDER, under the footer's line and wash: above every BACKGROUND texture of the window, its
	-- parchment included, so the wood always shows, the owner on build 7)
	local t = win:CreateTexture(nil, "BORDER", nil, -2)
	t:SetTexture(Games.WOOD.file)
	t:SetTexCoord(unpack(Games.WOOD.coords))
	t:SetVertexColor(unpack(Games.WOOD.tint))
	t:SetPoint("TOPLEFT", win, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	return t
end
function Games.Bar(win, opts)
	opts = opts or {}
	local F, B = Games.FOOT, Games.BAR
	-- (One height, always: nothing overrides it, the owner on build 5.)
	local inset, y, h = opts.inset or 10, opts.y or 0, B.H
	local bar = { y = y, h = h }
	bar.wood = Games.WoodBar(win, inset, y, (tonumber(win:GetWidth()) or 0) - 2 * inset, h)
	bar.foot = Games.Footer(win, y, h, inset)
	local by = y + (h - B.BUTTON_H) / 2
	bar.wallet = Games.WalletButton(win, win, inset + B.PAD, by, opts)
	bar.help = Button(win, opts.helpText or "How to play", F.HELP_W, opts.help)
	bar.help:SetPoint("TOPLEFT", win, "TOPLEFT", inset + B.PAD + (Games.WalletShown() and (F.COIN + 6 + F.BALANCE_W + F.PAD) or 0), -by)
	-- (Relayout: only the shown ones, from the right end, so an action never floats mid-bar when
	-- the one right of it hides; the owner on build 7)
	function bar.Relayout()
		bar.wallet.Refresh()
		bar.help:ClearAllPoints()
		bar.help:SetPoint("TOPLEFT", win, "TOPLEFT", inset + B.PAD + (Games.WalletShown() and (F.COIN + 6 + F.BALANCE_W + F.PAD) or 0), -by)
		local prev
		for _, b in ipairs(bar.list or {}) do
			b:SetHeight(B.BUTTON_H)
			b:ClearAllPoints()
			if b:IsShown() then
				if prev then b:SetPoint("RIGHT", prev, "LEFT", -B.GAP, 0) else b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -(inset + B.PAD), -by) end
				prev = b
			end
		end
	end
	function bar.Place(buttons)
		bar.list = buttons
		bar.Relayout()
	end
	return bar
end

-- The wallet in a footer: the coin (a small icon button) and the balance next to it (itself a
-- button); either opens the Wallet pop-up over `over`. Its top left at (x, y) of `over`.
-- (In the arena, 2026-09-30: opts = { balance = fn () -> copper, tip }: the arena window's footer
-- shows its own wallet with the same coin and balance. A click opens Games.OnMoney when set, the
-- Olympus window's Treasury > My money, else the Wallet pop-up.)
function Games.WalletButton(parent, over, x, y, opts)
	local F = Games.FOOT
	local coin = CreateFrame("Button", nil, parent)
	coin:SetSize(F.COIN, F.COIN); coin:SetPoint("TOPLEFT", over, "TOPLEFT", x, -y)
	coin:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
	coin.icon = coin:CreateTexture(nil, "ARTWORK")
	coin.icon:SetTexture(FirstTexture(WALLET_ICON)); coin.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); coin.icon:SetAllPoints()
	coin.frame = coin:CreateTexture(nil, "ARTWORK", nil, 2)
	coin.frame:SetTexture("Interface\\Common\\WhiteIconFrame"); coin.frame:SetVertexColor(FRAME[1], FRAME[2], FRAME[3]); coin.frame:SetAllPoints()
	coin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local balance = CreateFrame("Button", nil, parent)
	balance:SetSize(F.BALANCE_W, F.BUTTON); balance:SetPoint("TOPLEFT", over, "TOPLEFT", x + F.COIN + 6, -y)
	balance:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
	balance.text = Ink(balance, balance, 2, 8, F.BALANCE_W - 4, 14, INK)
	balance:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	local function Open()
		if not Games.WalletShown() then return false end
		if Games.OnMoney then return Games.OnMoney(over) end
		Games.ShowWallet(over)
	end
	coin:SetScript("OnClick", Open); balance:SetScript("OnClick", Open)
	for _, b in ipairs({ coin, balance }) do
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(opts and opts.tip or "Practice wallet")
			GameTooltip:AddLine("The practice gold the games share, and its history.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	local w = { coin = coin, balance = balance }
	function w.Refresh()
		local shown = Games.WalletShown()
		coin:SetShown(shown); balance:SetShown(shown)
		if not shown then balance.text:SetText("") return end
		local b = opts and opts.balance and opts.balance() or Wallet.balance
		Fit(balance.text, { "Practice wallet " .. Coins(b), "Wallet " .. Coins(b), "Wallet " .. Money(b), Coins(b), Money(b) })
	end
	w.Refresh()
	return w
end

---------------------------------------------------------------------------
-- The Wallet: the lab's one pop-up over the window that asked for it, the balance, practice gold
-- for testing (Add 100g, Reset) and the history, newest first; Close, the X or Escape go back
---------------------------------------------------------------------------

local WW, WH = 660, 580                        -- the pop-up
local WX = 40                                  -- its margin, inside the parchment's rims
local PAGE_ROWS, ROW_Y, ROW_H = 12, 262, 20    -- the history: a page's rows, the first row's y, a row
-- the history's columns: x, width, justify (from WX to WW - WX)
local COLS = { when = { WX, 90, "LEFT" }, what = { WX + 96, 238, "LEFT" }, amount = { WX + 340, 116, "RIGHT" }, after = { WX + 462, WW - 2 * WX - 462, "RIGHT" } }

local function WalletRefresh()
	if not wallet then return end
	local h = Wallet.history
	wallet.balance:SetText(Coins(Wallet.balance))
	local pages = max(1, math.ceil(#h / PAGE_ROWS))
	wallet.page = max(1, min(wallet.page or 1, pages))
	local first = (wallet.page - 1) * PAGE_ROWS
	for i, row in ipairs(wallet.rows) do
		local e = h[first + i]
		for _, fs in pairs(row) do fs:SetText("") end
		if e then
			row.when:SetText(e.when)
			Fit(row.what, e.forms)
			-- (a long amount without the coins' icons)
			Fit(row.amount, { Signed(e.amount), (e.amount > 0 and "+" or "") .. Money(e.amount) })
			Tint(row.amount, e.amount > 0 and GREEN or e.amount < 0 and RED or SOFT)
			Fit(row.after, { Coins(e.after), Money(e.after) })
		end
	end
	wallet.empty:SetShown(#h == 0)
	wallet.newest:SetText(#h > PAGE_ROWS and ("newest first " .. "\194\183" .. " page %d of %d"):format(wallet.page, pages) or "newest first")
	wallet.newer:SetShown(#h > PAGE_ROWS); wallet.older:SetShown(#h > PAGE_ROWS)
	if wallet.page > 1 then wallet.newer:Enable() else wallet.newer:Disable() end
	if wallet.page < pages then wallet.older:Enable() else wallet.older:Disable() end
end
-- (a game's own wallet line follows through its Refresh; the pop-up follows here)
function Games.WalletChanged() if wallet and wallet:IsShown() then WalletRefresh() end end

-- In combat the lab's windows close (the games close their own). Made with the first window,
-- not at load: the arena's companion keeps no frame of its own while idle.
local events
local function Events()
	if events then return end
	events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function()
		Games.HideWallet()
		if hub and hub:IsShown() then hub:Hide() end
	end)
end

local function BuildWallet()
	Events()
	wallet = Games.Popup("OlympusArenaGamesWallet", WW, WH)
	wallet.title = Ink(wallet, wallet, WX, 20, WW - 2 * WX, 26, INK, MORPHEUS, "CENTER")
	wallet.title:SetText("Practice wallet")
	wallet.sub = Ink(wallet, wallet, WX, 54, WW - 2 * WX, 13, SOFT, nil, "CENTER")
	wallet.sub:SetText("The practice wallet the games share: practice gold, nothing real.")
	-- the balance, big, in the game's coins
	wallet.label = Ink(wallet, wallet, WX, 82, WW - 2 * WX, 13, SOFT, nil, "CENTER")
	wallet.label:SetText("Balance")
	wallet.balance = Ink(wallet, wallet, WX, 100, WW - 2 * WX, 30, INK, nil, "CENTER")
	-- practice gold for testing
	wallet.add = Button(wallet, "Add 100g", 140, function() Wallet.Add(100 * GOLD) end)
	wallet.add:SetPoint("TOPLEFT", wallet, "TOPLEFT", WW / 2 - 145, -144)
	wallet.reset = Button(wallet, "Reset", 140, function() Wallet.Reset(); wallet.page = 1; WalletRefresh() end)
	wallet.reset:SetPoint("TOPLEFT", wallet, "TOPLEFT", WW / 2 + 5, -144)
	Break(wallet, WX, 188, WW - 2 * WX, 12)
	wallet.historyTitle = Ink(wallet, wallet, WX, 206, 160, 20, INK, MORPHEUS)
	wallet.historyTitle:SetText("History")
	wallet.newest = Ink(wallet, wallet, WW - WX - 260, 212, 260, 13, SOFT, nil, "RIGHT")
	-- the columns' names, a line under them
	wallet.heads = {}
	for key, name in pairs({ when = "When", what = "What", amount = "Amount", after = "Balance after" }) do
		local c = COLS[key]
		wallet.heads[key] = Ink(wallet, wallet, c[1], 236, c[2], 13, SOFT, nil, c[3])
		wallet.heads[key]:SetText(name)
	end
	local line = wallet:CreateTexture(nil, "BORDER", nil, 2)
	line:SetColorTexture(0.25, 0.13, 0.04, 0.35)
	line:SetPoint("TOPLEFT", wallet, "TOPLEFT", WX, -255); line:SetSize(WW - 2 * WX, 1)
	wallet.rows = {}
	for i = 1, PAGE_ROWS do
		local y = ROW_Y + (i - 1) * ROW_H
		local row = {}
		for key, c in pairs(COLS) do row[key] = Ink(wallet, wallet, c[1], y, c[2], 13, INK, nil, c[3]) end
		wallet.rows[i] = row
	end
	wallet.empty = Ink(wallet, wallet, WX, ROW_Y + 4, WW - 2 * WX, 14, SOFT, nil, "CENTER")
	wallet.empty:SetText("Nothing yet: bet in the Lottery, or stake a Bones game.")
	-- at the bottom, as How to play's: Newer, Close, Older (the pages when there are more than one)
	local by = WH - 52
	Break(wallet, WX, by - 16, WW - 2 * WX, 12)
	wallet.newer = Button(wallet, "Newer", 110, function() wallet.page = wallet.page - 1; WalletRefresh() end)
	wallet.newer:SetPoint("TOPLEFT", wallet, "TOPLEFT", WX, -by)
	wallet.ok = Button(wallet, "Close", 140, function() wallet:Hide() end)
	wallet.ok:SetPoint("TOP", wallet, "TOPLEFT", WW / 2, -by)
	wallet.older = Button(wallet, "Older", 110, function() wallet.page = wallet.page + 1; WalletRefresh() end)
	wallet.older:SetPoint("TOPRIGHT", wallet, "TOPLEFT", WW - WX, -by)
	wallet.page = 1
	wallet:HookScript("OnShow", function() wallet.page = 1; WalletRefresh(); EscapeAgain(wallet.over) end)
	wallet:HookScript("OnHide", function()
		EscapeAgain(wallet.over)
		-- the window under it shows the balance as it is now
		local o = wallet.over
		if o and o.walletButton then o.walletButton.Refresh() end
	end)
end

-- The Wallet over a window (a game's, or the games' window); over nothing: centred on the screen.
-- That window's other pop-ups close (one pop-up at a time).
function Games.ShowWallet(over)
	if not Games.WalletShown() then
		if wallet then wallet:Hide() end
		return false
	end
	if InCombatLockdown() then return Say("not in combat.") end
	if not wallet then BuildWallet() end
	local e = over and escapes[over]
	if e then for _, p in ipairs(e.popups) do if p ~= wallet then p:Hide() end end end
	if wallet:IsShown() and wallet.over ~= over then wallet:Hide() end
	wallet.over = over
	wallet:Show()
	wallet:ClearAllPoints(); wallet:SetPoint("CENTER", over or UIParent, "CENTER", 0, 0)
end
-- /lab wallet: the Wallet on or off, over the window that is open (a game's, the games' window),
-- else centred on the screen.
function Games.WalletCommand()
	if wallet and wallet:IsShown() then return wallet:Hide() end
	for _, g in ipairs(GAMES) do
		local m = Module(g)
		local w = m and m.Window and m.Window()
		if w and w:IsShown() then return Games.ShowWallet(w) end
	end
	return Games.ShowWallet(hub and hub:IsShown() and hub or nil)
end
-- Closes the Wallet (over `over` only, when given).
function Games.HideWallet(over)
	if wallet and wallet:IsShown() and (over == nil or wallet.over == over) then wallet:Hide() end
end

---------------------------------------------------------------------------
-- The games' window (/oly games, and /lab): a row a section, Play opens it
---------------------------------------------------------------------------

local HW, MX, ROW0, ROWH = 540, 34, 94, 58     -- its width, its margin, its first row, a row
local ICON, TX, BW = 40, 86, 96                -- a section's icon, its text's x, the button's width
local HH = ROW0 + #GAMES * ROWH + 62           -- its height

local function BuildHub()
	Events()
	hub = Window("OlympusArenaGames", HW, HH)
	hub.title = Ink(hub, hub, 44, 20, HW - 88, 26, INK, MORPHEUS, "CENTER")
	hub.title:SetText("Olympus games")
	hub.sub = Ink(hub, hub, MX, 55, HW - 2 * MX, 13, SOFT, nil, "CENTER")
	hub.sub:SetText("Practice games: nothing is sent, nothing is saved.")
	Break(hub, MX, 76, HW - 2 * MX, 12)
	hub.rows = {}
	local games = {}
	for _, g in ipairs(GAMES) do
		-- (a game whose file the package left out, e.g. the lab's lottery in the release: not listed)
		if (g.key ~= "wallet" or Games.WalletShown()) and (not g.module or Module(g)) then games[#games + 1] = g end
	end
	hub:SetHeight(ROW0 + #games * ROWH + 62)
	for i, g in ipairs(games) do
		local y = ROW0 + (i - 1) * ROWH
		local r = { game = g }
		r.icon = hub:CreateTexture(nil, "ARTWORK")
		r.icon:SetTexture(FirstTexture(g.icons)); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.icon:SetSize(ICON, ICON); r.icon:SetPoint("TOPLEFT", hub, "TOPLEFT", MX, -(y + 7))
		r.frame = hub:CreateTexture(nil, "ARTWORK", nil, 2)
		r.frame:SetTexture("Interface\\Common\\WhiteIconFrame"); r.frame:SetAllPoints(r.icon)
		local c = g.soon and FRAME_DIM or FRAME
		r.frame:SetVertexColor(c[1], c[2], c[3])
		r.name = Ink(hub, hub, TX, y + 6, HW - MX - BW - 10 - TX, 18, g.soon and DIM or INK, MORPHEUS)
		r.name:SetText(g.name)
		r.desc = Ink(hub, hub, TX, y + 31, HW - MX - BW - 10 - TX, 13, g.soon and DIM or SOFT)
		Fit(r.desc, g.desc)
		r.button = Button(hub, g.soon and "Soon" or g.play or "Play", BW, function() Games.Open(g.key) end)
		r.button:SetPoint("TOPLEFT", hub, "TOPLEFT", HW - MX - BW, -(y + 12))
		if g.soon then
			-- the Arena isn't here yet: greyed, and its button does nothing
			r.icon:SetDesaturated(true); r.icon:SetAlpha(0.7)
			r.button:Disable()
		end
		if i < #games then
			local line = hub:CreateTexture(nil, "BORDER", nil, 2)
			line:SetColorTexture(0.25, 0.13, 0.04, 0.25)
			line:SetPoint("TOPLEFT", hub, "TOPLEFT", MX, -(y + ROWH - 1)); line:SetSize(HW - 2 * MX, 1)
		end
		hub.rows[i] = r
	end
	local y = ROW0 + #games * ROWH + 2
	Break(hub, MX, y, HW - 2 * MX, 12)
	hub.foot = Ink(hub, hub, MX, y + 20, HW - 2 * MX, 13, SOFT, nil, "CENTER")
	hub.foot:SetText("Each game has its own window: its X closes it, /oly games comes back here.")
	hub:SetScript("OnShow", function() Games.Escape("OlympusArenaGames", hub) end)
	hub:SetScript("OnHide", function() Games.HideWallet(hub); Games.Escape("OlympusArenaGames", hub) end)
end

-- /oly games: the games' window on or off (show: true only opens it). Opening it closes an open
-- game (each keeps its state: it goes on where it was).
function Games.Hub(show)
	if InCombatLockdown() then return Say("not in combat.") end
	if not hub then BuildHub() end
	if show == nil then show = not hub:IsShown() end
	if not show then return hub:Hide() end
	for _, g in ipairs(GAMES) do
		local m = Module(g)
		if m and m.Close then m.Close() end
	end
	hub:Show()
end
function Games.CloseHub() if hub then hub:Hide() end end


-- For the offline tests (read only).
Games._ = { GAMES = GAMES, geo = { W = HW, H = HH, MX = MX, ROW0 = ROW0, ROWH = ROWH, ICON = ICON, BW = BW, WW = WW, WH = WH, PAGE_ROWS = PAGE_ROWS },
	parts = function() return { hub = hub, wallet = wallet } end, refresh = function() WalletRefresh() end }
