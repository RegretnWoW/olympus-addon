local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Kit.lua. A stub the arena's core created for the screens to
-- fill. Widgets: amount stepper (+/-, Min, Max), Fill button, banners, countdown ticker (one
-- C_Timer.NewTicker(0.5) while a countdown shows, never OnUpdate), list and detail through the
-- host's Views.Render.
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = {}
ArenaUI.Kit = Kit

-- The screens read every package's view models through the core's one adapter (ArenaHome.Data),
-- which the solo simulation swaps for its sample data while it runs.
ArenaUI.Data = ns.ArenaHome.Data
local Home = ns.ArenaHome
Kit.Money, Kit.Clock, Kit.Name, Kit.Plain, Kit.V = Home.Money, Home.Clock, Home.Name, Home.Plain, Home.V

-- The owner's look (2026-09-30): dark ink on parchment, 13 px and more, Morpheus titles; the
-- game's own sounds; short fades; each thing in its own area.
function Kit.Font(kind)
	if kind == "title" then return _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge" end
	if kind == "big" then return _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalHuge" end
	if kind == "light" then return "GameFontHighlight" end
	if kind == "small" then return _G.QuestFontNormalSmall and "QuestFontNormalSmall" or "GameFontHighlightSmall" end
	return _G.QuestFont and "QuestFont" or "GameFontHighlight"
end
Kit.INK = { 0.20, 0.13, 0.05 }
Kit.GOLD = { 1, 0.82, 0 }
Kit.Sound = Home.Sound
Kit.FadeIn = Home.FadeIn
Kit.Parchment = Home.Parchment

-- A child a frame template gives (PortraitContainer, TitleText...), or nil where this client's
-- template has none (never a method mistaken for one).
function Kit.Child(f, key)
	local v = type(f) == "table" and f[key] or nil
	if type(v) == "table" then return v end
	return nil
end

-- The simulation's two views (Sim.lua): the gamepad texts and the King's block, for the sim only.
ArenaUI.simGamepad, ArenaUI.simKing = false, false
function Kit.Gamepad() return ArenaUI.simGamepad == true or ns.GamepadUI() end
-- (The sim's King view also cuts names short there: ArenaNet.lua's Arena.Mask asks this.)
ns.Arena.SimKingsView = function() return ArenaUI.simKing == true end
function Kit.KingsView(mode)
	if ns.Arena.Sim() then return ArenaUI.simKing == true end
	return ns.Arena.KingsView(mode)
end

-- The player's remembered choices (ns.db.arenaUI), or the sim's own while it runs (the sim saves
-- nothing).
local simUI = {}
function Kit.Settings()
	if ns.Arena.Sim() then return simUI end
	return Home.UI()
end
function Kit.ResetSimSettings() simUI = {} end
-- A remembered choice under its key (ns.db.arenaUI.seen, a small table of flags and picks), or its
-- default; and Kit.Remember(key, value) keeps it.
function Kit.Recall(key, default)
	local s = Kit.Settings()
	local seen = type(s.seen) == "table" and s.seen or nil
	local v = seen and seen[key]
	if v == nil then return default end
	return v
end
function Kit.Remember(key, value)
	local s = Kit.Settings()
	if type(s.seen) ~= "table" then s.seen = {} end
	local n = 0
	for _ in pairs(s.seen) do n = n + 1 end
	if s.seen[key] == nil and n >= 40 then return end
	s.seen[key] = value
end

-- A large Arena window keeps the player's chosen scale, but may shrink further when the client
-- has fewer UI units available (a smaller window, a high UI scale, or a display change). The
-- game's UIParent size is preferred because it is already expressed in UI units; the physical
-- screen APIs are only a guarded fallback while UIParent has no useful size during login.
-- Returning the requested scale when no credible viewport is available keeps older clients and
-- the offline stand-ins at their former effective layout.
Kit.WINDOW_MARGIN = 16
function Kit.WindowScale(width, height, requested, screenWidth, screenHeight, margin)
	width, height = tonumber(width), tonumber(height)
	requested = tonumber(requested) or 1
	if requested <= 0 then requested = 1 end
	screenWidth, screenHeight = tonumber(screenWidth), tonumber(screenHeight)
	margin = math.max(0, tonumber(margin) or Kit.WINDOW_MARGIN)
	if not width or width <= 0 or not height or height <= 0 then return requested end
	-- Values this small are the registry harness's unresolved UIParent, not a usable WoW viewport.
	if not screenWidth or screenWidth < 320 or not screenHeight or screenHeight < 240 then return requested end
	local fitW = (screenWidth - margin * 2) / width
	local fitH = (screenHeight - margin * 2) / height
	local fit = math.min(fitW, fitH)
	if fit <= 0 then return requested end
	return math.min(requested, fit)
end
local function ViewportSize()
	local parent = rawget(_G, "UIParent")
	local width, height
	if parent and type(parent.GetWidth) == "function" and type(parent.GetHeight) == "function" then
		local okW, valueW = pcall(parent.GetWidth, parent)
		local okH, valueH = pcall(parent.GetHeight, parent)
		if okW then width = tonumber(valueW) end
		if okH then height = tonumber(valueH) end
	end
	if not width or width < 320 then
		local fn = rawget(_G, "GetScreenWidth")
		if type(fn) == "function" then local ok, value = pcall(fn); if ok then width = tonumber(value) end end
	end
	if not height or height < 240 then
		local fn = rawget(_G, "GetScreenHeight")
		if type(fn) == "function" then local ok, value = pcall(fn); if ok then height = tonumber(value) end end
	end
	return width, height
end
function Kit.FitWindow(frame, width, height, requested, margin)
	local screenWidth, screenHeight = ViewportSize()
	local scale = Kit.WindowScale(width, height, requested, screenWidth, screenHeight, margin)
	if frame and type(frame.SetScale) == "function" then pcall(frame.SetScale, frame, scale) end
	return scale
end

-- A refusal in words: the screens' own reason words (ARENA_REFUSE_*), else the words of the package
-- that refused (the wallet's, the markets', the fights', Bones's, the matchmaking's, the
-- roles'), else the generic line with the code.
Kit.WHY_PREFIXES = { "ARENA_REFUSE_", "WALLET_WHY_", "MARKETS_WHY_", "FIGHTS_WHY_", "FARKLE_WHY_", "MATCH_WHY_", "ARENA_WHY_" }
function Kit.Why(why)
	if why == nil then return nil end
	local up = tostring(why):upper():gsub("[^%w_]", "_")
	for _, prefix in ipairs(Kit.WHY_PREFIXES) do
		local s = rawget(L, prefix .. up)
		if type(s) == "string" then return s end
	end
	return L.ARENA_REFUSE_GENERIC:format(tostring(why))
end

-- Plain text for the copy pop-up (anything the player may need to copy opens there, never in chat).
function Kit.Copy(title, text)
	local UI = ns.UI
	text = Kit.Plain(text)
	ArenaUI.lastCopy = text
	if type(UI) == "table" and type(UI.ShowCopy) == "function" then UI.ShowCopy(title, text) end
	return text
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- The footer compartment (the lab games' look): the bottom `h` px of a pop-up, set off by a line
-- and a darker wash; the pop-up's action buttons sit in it.
Kit.FOOTER_H = 48
function Kit.Footer(f, h)
	h = h or Kit.FOOTER_H
	local wash = f:CreateTexture(nil, "BORDER")
	wash:SetPoint("BOTTOMLEFT", 12, 10)
	wash:SetPoint("BOTTOMRIGHT", -12, 10)
	wash:SetHeight(h - 10)
	wash:SetColorTexture(0.25, 0.13, 0.04, 0.12)
	local line = f:CreateTexture(nil, "BORDER", nil, 1)
	line:SetPoint("BOTTOMLEFT", wash, "TOPLEFT", 0, 0)
	line:SetPoint("BOTTOMRIGHT", wash, "TOPRIGHT", 0, 0)
	line:SetHeight(1)
	line:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	f.footer = wash
	return wash
end

-- An inset panel on the parchment (the owner's look, 2026-09-30): a thin bronze border, no fill,
-- its content 12 px inside. Returns the panel (a frame over `parent`'s area).
function Kit.Inset(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints(parent)
	-- (no fill: the parchment shows clean inside, the owner after build 7; a thin bronze line only)
	local c = { 0.45, 0.28, 0.12, 0.85 }
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = p:CreateTexture(nil, "BORDER")
		t:SetColorTexture(c[1], c[2], c[3], c[4])
		t:SetPoint(side[1]); t:SetPoint(side[2])
		if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
	end
	return p
end

-- A fighter's portrait, ONE helper for the profile, the podium and the bracket's plaques (the
-- owner's call, 2026-09-30): the live portrait where a unit shows him, else his emblem; where
-- neither, a token: his race's portrait where the client has the atlas (raceicon128-<race>-
-- <gender>, feature-checked), else his class's icon, else the arena's emblem (Card.lua's order).
-- opts = { class, race, gender, emblem } (read from his profile where not given); square: the live
-- portrait without the client's own rounding, for a portrait masked as the player's frame masks
-- his (Kit.DrawPortrait); asSeen: as others see him, never a unit of this client's (his own live
-- portrait least of all: a viewer who has him as no unit sees his emblem, race or class). Returns
-- the kind.
local RACE_ATLAS = { [1] = "human", [2] = "orc", [3] = "dwarf", [4] = "nightelf", [5] = "undead", [6] = "tauren", [7] = "gnome", [8] = "troll" }
function Kit.RaceAtlas(race, gender)
	local name = RACE_ATLAS[tonumber(race) or 0]
	if not name then return nil end
	local atlas = ("raceicon128-%s-%s"):format(name, tonumber(gender) == 3 and "female" or "male")
	local T = rawget(_G, "C_Texture")
	if type(T) ~= "table" or type(T.GetAtlasInfo) ~= "function" then return nil end
	local ok, info = pcall(T.GetAtlasInfo, atlas)
	return ok and info and atlas or nil
end
function Kit.Portrait(tex, name, opts)
	if not tex then return nil end
	opts = opts or {}
	local class, race, emblem = opts.class, opts.race, opts.emblem
	if (class == nil or race == nil) and name and ArenaUI.Data and ArenaUI.Data.Profile then
		local p = ArenaUI.Data.Profile(name)
		if type(p) == "table" then
			class = class or Kit.V(p.class)
			race = race or Kit.V(p.race)
			emblem = emblem or Kit.V(p.emblem)
		end
	end
	local file = ArenaUI.ClassFile and ArenaUI.ClassFile(class) or class
	local Card = ArenaUI.Card
	local unitOf = not opts.asSeen and name or nil -- (the name a live unit is looked for by)
	local kind = Card and Card.Portrait(unitOf, emblem, file).kind
	if kind ~= "live" and kind ~= "emblem" then
		local atlas = Kit.RaceAtlas(race, opts.gender)
		if atlas and tex.SetAtlas and pcall(tex.SetAtlas, tex, atlas) then return "race" end
	end
	if Card then Card.SetPortrait(tex, unitOf, emblem, file, opts.square) end
	return kind
end

-- Portraits in the arena are medallions, not square item icons. Modern clients expose texture
-- masks; older supported clients (and the offline harness) may not, so the shape is a guarded
-- enhancement and the portrait remains usable without it. The mask is made once and then follows
-- the portrait's anchors and size.
Kit.PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local portraitMasks = setmetatable({}, { __mode = "k" })
function Kit.RoundPortrait(tex, parent)
	if not tex then return false end
	if portraitMasks[tex] then return true end
	if not parent and type(tex.GetParent) == "function" then
		local ok, p = pcall(tex.GetParent, tex)
		if ok then parent = p end
	end
	if parent and type(parent.CreateMaskTexture) == "function" and type(tex.AddMaskTexture) == "function" then
		local ok, mask = pcall(parent.CreateMaskTexture, parent)
		if ok and mask then
			if type(mask.SetAllPoints) == "function" then mask:SetAllPoints(tex) end
			if type(mask.SetTexture) == "function" then mask:SetTexture(Kit.PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
			if pcall(tex.AddMaskTexture, tex, mask) then
				portraitMasks[tex] = mask
				return true
			end
		end
	end
	-- Forever and older Classic clients expose Texture:SetMask instead of MaskTexture regions.
	if type(tex.SetMask) == "function" and pcall(tex.SetMask, tex, Kit.PORTRAIT_MASK) then
		portraitMasks[tex] = true
		return true
	end
	return false
end

-- The photo tours' stage (the owner's clean crops, 2026-09-30): the Olympus window's photo mode
-- (UI.TogglePhoto: everything but Olympus's frames faded out, where it is allowed) and a solid
-- black backdrop over the whole screen, below every Olympus frame (OlympusPhotoBackdrop, strata
-- BACKGROUND; Olympus-named, so the photo mode keeps it), so a shot shows only the windows on
-- black. Kit.PhotoStage(true, stop) sets it; false takes both back. Escape takes the backdrop away,
-- and with it the stage: `stop` (the tour's) runs then.
local stage, stagedPhoto, stageStop
function Kit.PhotoStage(on, stop)
	local UI = ns.UI
	if on then
		if not stage then
			stage = CreateFrame("Frame", "OlympusPhotoBackdrop", UIParent)
			stage:SetAllPoints(UIParent)
			stage:SetFrameStrata("BACKGROUND")
			stage:SetFrameLevel(0)
			local t = stage:CreateTexture(nil, "BACKGROUND")
			t:SetAllPoints()
			t:SetColorTexture(0, 0, 0, 1)
			stage:SetScript("OnHide", function()
				if not stageStop then return end
				local fn = stageStop
				stageStop = nil
				Kit.PhotoStage(false)
				ns.SafeCall("photo stage stop", fn)
			end)
			stage:Hide()
		end
		stageStop = stop
		stage:Show()
		ns.EscapeCloses("OlympusPhotoBackdrop")
		if type(UI) == "table" and UI.PhotoMode and not UI.PhotoMode() and UI.PhotoAllowed and UI.PhotoAllowed() and UI.TogglePhoto then
			stagedPhoto = true
			ns.SafeCall("photo stage", UI.TogglePhoto)
		end
		return true
	end
	stageStop = nil
	if stage and stage:IsShown() then stage:Hide() end
	if stagedPhoto then
		stagedPhoto = nil
		if type(UI) == "table" and UI.PhotoMode and UI.PhotoMode() and UI.TogglePhoto then ns.SafeCall("photo stage", UI.TogglePhoto) end
	end
	return true
end
function Kit.PhotoStaged() return stage ~= nil and stage:IsShown() end

-- The pop-ups made (the owner's rule, 2026-09-30: one open at a time, centred over the arena
-- window, never stacked on another).
local popups = {}
Kit.popups = popups

-- A pop-up of Olympus's own, on parchment: name (OlympusArena...), w x h, opts = { title, strata,
-- point = { ... }, noClose, footer = false (no footer compartment), free = true (keeps its own
-- place instead of centring over the arena window), stack = true (may open over another: the
-- chat panel, the rules' yes a committing click waits on) }. Movable, clamped, on the escape
-- list with mouse and keyboard only.
function Kit.Frame(name, w, h, opts)
	opts = opts or {}
	-- (1.1.5: every window in the Olympus window's bronze metal, ns.Window; the parchment inside it,
	-- the title in its title bar; its X and the escape list this pop-up's own, as before.)
	local f = ns.Window(name, UIParent, { inset = false, close = false, escape = false })
	f:SetSize(w, h)
	f:SetFrameStrata(opts.strata or "DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	if opts.point then f:SetPoint(unpack(opts.point)) else f:SetPoint("CENTER", 0, 40) end
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	-- (A pop-up shown inside another window, f.host (the Bones window's Find sheet): a drag moves
	-- that window, the pop-up with it.)
	local function Mover(self) local h = rawget(self, "host") return type(h) == "table" and h or self end
	f:SetScript("OnDragStart", function(self) local m = Mover(self) if m.StartMoving then m:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) local m = Mover(self) if m.StopMovingOrSizing then m:StopMovingOrSizing() end end)
	f.bg = Kit.Parchment(f, 10)
	if opts.footer ~= false then Kit.Footer(f) end
	popups[#popups + 1] = { f = f, stack = opts.stack == true }
	f.title = f.TitleText
	ns.SetWindowTitle(f, opts.title or "")
	if not opts.noClose then
		f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		f.close:SetPoint("TOPRIGHT", -4, -4)
		f.close:SetScript("OnClick", function() f:Hide() end)
	end
	f:SetScript("OnShow", function(self)
		ns.EscapeCloses(name)
		-- One at a time: the others close (a stacking one stays and closes none).
		if not opts.stack then
			for _, p in ipairs(popups) do
				if p.f ~= self and not p.stack and p.f:IsShown() then p.f:Hide() end
			end
		end
		-- Centred over the arena window while it is open (not when another window holds it).
		local win = ArenaUI.frame
		if not opts.free and not rawget(self, "host") and win and win ~= self and win:IsShown() then
			self:ClearAllPoints()
			self:SetPoint("CENTER", win, "CENTER", 0, 0)
		end
		Kit.FadeIn(self)
		local fn = rawget(self, "onShow")
		if fn then ns.SafeCall("arena pop-up", fn, self) end
	end)
	f:Hide()
	ns.EscapeCloses(name)
	return f
end

-- A button, 24 px tall at least (the gamepad cursor's target, the design).
function Kit.Button(parent, w, h, text, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, math.max(24, h or 24))
	b:SetText(text or "")
	b:SetScript("OnClick", function(self)
		Kit.Sound("IG_MAINMENU_OPTION")
		if onClick then ns.SafeCall("arena button", onClick, self) end
	end)
	b.tip = tip
	Kit.SetButton(b, nil, true)
	return b
end
-- Sizes a button from its words (the owner's rule: no label wider than its button): the text's
-- width and 20 px, at least minW (32 by default), the button 24 px tall at least.
function Kit.Fit(b, minW)
	if not b then return end
	local fs = b.GetFontString and b:GetFontString()
	local w = fs and fs.GetStringWidth and tonumber(fs:GetStringWidth())
	if not w or w <= 0 then w = #(b:GetText() or "") * 7 end
	b:SetWidth(math.max(minW or 32, math.ceil(w) + 20))
	return b
end
-- A pop-up's height from its content (the owner's audit, 2026-09-30: wrapped text never spills
-- below the frame or under its footer): `top` px above the text, the text's own height, `bottom` px
-- under it (the footer included), at least `min`. The text needs its width set first.
function Kit.FitHeight(f, fs, top, bottom, min)
	if not (f and fs and fs.GetStringHeight) then return end
	local h = tonumber(fs:GetStringHeight() or 0) or 0
	if h <= 0 then return end
	f:SetHeight(math.max(min or 0, math.ceil(top + h + bottom)))
end
-- Sets a button's words and whether it can be clicked, with the reason in its tooltip.
function Kit.SetButton(b, text, enabled, why)
	if not b then return end
	if text then
		b:SetText(text)
		-- (never a label wider than its button: the button grows to its words, never shrinks here)
		local fs = b.GetFontString and b:GetFontString()
		local tw = fs and fs.GetStringWidth and tonumber(fs:GetStringWidth() or 0) or 0
		if tw > 0 and tw + 20 > (tonumber(b:GetWidth()) or 0) then b:SetWidth(math.ceil(tw) + 20) end
	end
	b:SetEnabled(enabled ~= false)
	b.why = enabled == false and why or nil
	b:SetScript("OnEnter", (rawget(b, "why") or rawget(b, "tip")) and function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self:GetText() or "", 1, 0.82, 0)
		local why, tip = rawget(self, "why"), rawget(self, "tip")
		if why then GameTooltip:AddLine(why, 1, 0.4, 0.4, true) end
		if tip then GameTooltip:AddLine(type(tip) == "function" and tip() or tip, 1, 1, 1, true) end
		GameTooltip:Show()
	end or nil)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
-- A button that does an action (Arena.Can/Do): its words, enabled only when Can says yes, the
-- reason in its tooltip otherwise. def = { text, action, args = { ... }, commit (the rules' yes
-- first), after = fn(ok, why) }.
function Kit.ActionButton(b, def)
	local args = def.args or {}
	local ok, why = ns.Arena.Can(def.action, unpack(args))
	if why == "unknown" then ok, why = false, "missing" end
	-- (A committing action's rules' yes is asked on the click, never a reason to grey it.)
	if not ok and why == "rules" and def.commit then ok = true end
	Kit.SetButton(b, def.text, ok, Kit.Why(why))
	b:SetScript("OnClick", function()
		Kit.Sound("IG_MAINMENU_OPTION")
		local done, w
		if def.commit then done, w = ArenaUI.Commit(def.action, unpack(args))
		else done, w = ns.Arena.Do(def.action, unpack(args)) end
		if not done and w and not def.commit then ArenaUI.Say(Kit.Why(w)) end
		if def.after then ns.SafeCall("arena after", def.after, done, w) end
	end)
end

-- A row of choices, one lit (a period, a category, a mode): labels = { { key, text } ... }.
-- onPick(key). Returns the row; row:Select(key).
function Kit.Choices(parent, labels, width, onPick)
	local row = { buttons = {}, keys = {} }
	local prev
	for i, item in ipairs(labels) do
		local key = item[1]
		local b = Kit.Button(parent, width or 70, 24, item[2], function() row:Select(key) if onPick then onPick(key) end end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
		row.buttons[i], row.keys[i] = b, key
		prev = b
	end
	function row:Select(key)
		self.selected = key
		for i, b in ipairs(self.buttons) do
			if self.keys[i] == key then b:LockHighlight() else b:UnlockHighlight() end
		end
	end
	function row:SetPoint(...) if self.buttons[1] then self.buttons[1]:SetPoint(...) end end
	function row:SetShown(on) for _, b in ipairs(self.buttons) do b:SetShown(on) end end
	return row
end

-- A text on parchment (dark ink) or on the window (light).
function Kit.Text(parent, kind, justify)
	local fs = parent:CreateFontString(nil, "ARTWORK", Kit.Font(kind))
	if justify then fs:SetJustifyH(justify) end
	return fs
end

-- The coloured strip under a header: "rehearsal" red, "sim" purple, "test" red.
local BANNER = { rehearsal = { 0.55, 0.05, 0.05 }, test = { 0.55, 0.05, 0.05 }, sim = { 0.40, 0.15, 0.60 } }
function Kit.Banner(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetHeight(18)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("CENTER")
	function b:Set(kind, text)
		local c = BANNER[kind]
		if not c then self:Hide() self.kind = nil return end
		self.bg:SetColorTexture(c[1], c[2], c[3], 0.9)
		self.text:SetText(text or "")
		self.kind = kind
		self:Show()
	end
	b:Hide()
	return b
end

---------------------------------------------------------------------------
-- Confirmations (the design): the game's popup with mouse and keyboard, Olympus's own dialog with
-- the gamepad UI (ns.ShowDialog). data = { fn }.
---------------------------------------------------------------------------

if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs["OLYMPUS_ARENA_CONFIRM"] = {
		text = "%s",
		button1 = ACCEPT or "Accept",
		button2 = CANCEL or "Cancel",
		OnAccept = function(_, data) if type(data) == "table" and data.fn then ns.SafeCall("arena confirm", data.fn) end end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end
function Kit.Confirm(text, fn)
	ArenaUI.lastConfirm = { text = text, fn = fn }
	if ns.Arena.Sim() then return true end
	return ns.ShowDialog("OLYMPUS_ARENA_CONFIRM", text, nil, { fn = fn })
end

---------------------------------------------------------------------------
-- Amounts (the design): +/- at 10s, 1g, 10g and 100g, Min and Max; the edit box is optional
-- and never focused by the addon (ns.Focus, on the player's click only).
---------------------------------------------------------------------------

Kit.STEPS = { 1000, 10000, 100000, 1000000 } -- copper: 10s, 1g, 10g, 100g
Kit.STEPPER_H = 80 -- the amount (22), then two rows of buttons (24, 4 apart)
function Kit.Stepper(parent, opts)
	opts = opts or {}
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(opts.width or 330, Kit.STEPPER_H)
	s.min, s.max, s.cur = opts.min or 0, opts.max or 0, opts.cur
	s.value = opts.value or s.min
	s.steps = opts.steps or Kit.STEPS
	s.text = s:CreateFontString(nil, "ARTWORK", Kit.Font("title"))
	s.text:SetPoint("TOP", 0, 0)
	local function Changed()
		s.value = math.max(s.min, math.min(s.max, math.floor(s.value)))
		s.text:SetText(Kit.Money(s.value, s.cur))
		local box = rawget(s, "box")
		if box and not (box.HasFocus and box:HasFocus()) then box:SetText(tostring(math.floor(s.value / 10000))) end
		if opts.onChange then ns.SafeCall("arena amount", opts.onChange, s.value) end
	end
	s.Changed = Changed
	local function Step(delta)
		s.value = s.value + delta
		Changed()
	end
	-- Two rows, each button as wide as its words (the owner's rule: no label wider than its
	-- button): Min and the steps down, then the steps up and Max, each row centred.
	s.minButton = Kit.Button(s, 36, 24, L.ARENA_MIN, function() s.value = s.min Changed() end)
	s.stepButtons = {}
	-- (A step's words: money, or a count of chips or points.)
	local function Words(d)
		if s.cur == "c" or s.cur == "p" then return ns.FormatNumber(d) end
		return (Kit.Money(d):gsub(" ", ""))
	end
	for i = #s.steps, 1, -1 do
		local d = s.steps[i]
		local b = Kit.Button(s, 36, 24, "-" .. Words(d), function() Step(-d) end)
		s.stepButtons[#s.stepButtons + 1] = b
	end
	for i = 1, #s.steps do
		local d = s.steps[i]
		local b = Kit.Button(s, 36, 24, "+" .. Words(d), function() Step(d) end)
		s.stepButtons[#s.stepButtons + 1] = b
	end
	s.maxButton = Kit.Button(s, 36, 24, L.ARENA_MAX, function() s.value = s.max Changed() end)
	local down, up = { s.minButton }, {}
	for i, b in ipairs(s.stepButtons) do
		if i <= #s.steps then down[#down + 1] = b else up[#up + 1] = b end
	end
	up[#up + 1] = s.maxButton
	for row, list in ipairs({ down, up }) do
		local total = 0
		for _, b in ipairs(list) do
			Kit.Fit(b, 36)
			total = total + (tonumber(b:GetWidth()) or 36) + 4
		end
		local x = -(total - 4) / 2
		for i, b in ipairs(list) do
			if i == 1 then b:SetPoint("BOTTOMLEFT", s, "BOTTOM", x, row == 1 and 28 or 0)
			else b:SetPoint("LEFT", list[i - 1], "RIGHT", 4, 0) end
		end
	end
	if opts.box ~= false then
		local ok, eb = pcall(CreateFrame, "EditBox", nil, s, "InputBoxTemplate")
		if not ok or not eb then eb = CreateFrame("EditBox", nil, s) end
		eb:SetSize(60, 20)
		eb:SetAutoFocus(false)
		eb:SetNumeric(true)
		eb:SetMaxLetters(6)
		eb:SetPoint("LEFT", s.text, "RIGHT", 10, 0)
		eb.olympusBox = true
		eb:SetScript("OnMouseDown", function(self) ns.Focus(self) end)
		eb:SetScript("OnEnterPressed", function(self)
			local g = tonumber(self:GetText() or "")
			if g then s.value = g * 10000 Changed() end
			self:ClearFocus()
		end)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		eb:SetScript("OnHide", function(self) self:ClearFocus() end)
		s.box = eb
	end
	function s:SetRange(lo, hi, cur)
		self.min, self.max = math.max(0, math.floor(lo or 0)), math.max(0, math.floor(hi or 0))
		if self.max < self.min then self.max = self.min end
		if cur then self.cur = cur end
		Changed()
	end
	function s:Get() return self.value end
	function s:Set(v) self.value = tonumber(v) or self.value Changed() end
	Changed()
	return s
end

---------------------------------------------------------------------------
-- The fills (the design): with mouse and keyboard the trade or the mail is filled (the core's
-- ArenaMoney), the player pressing Trade or Send; with the gamepad UI (or the sim's gamepad view),
-- one line says what to send and no game window is touched.
--   spec = { how = "trade"|"mail", to, copper, subject }
-- Returns "trade", "mail", "gamepad", "type" (the game refused SetTradeMoney: the amount said),
-- "closed" (the window is not open) or "combat".
---------------------------------------------------------------------------

function Kit.FillLabel() return Kit.Gamepad() and L.ARENA_FILL_TELL or L.ARENA_FILL end
function ArenaUI.Fill(spec)
	if type(spec) ~= "table" or not tonumber(spec.copper) then return "closed" end
	local who = Kit.Name(spec.to)
	local amount = Kit.Money(spec.copper)
	local line = spec.how == "mail" and L.ARENA_FILL_MAIL_LINE:format(amount, who, spec.subject or "") or L.ARENA_FILL_TRADE_LINE:format(amount, who)
	if Kit.Gamepad() or ns.Arena.Sim() then
		ns.Print(line)
		ArenaUI.lastFillLine = line
		ArenaUI.Say(line)
		return "gamepad"
	end
	local M = ns.ArenaMoney
	local res
	if spec.how == "mail" and M and M.FillMail then
		local ok, r = pcall(M.FillMail, spec.to, spec.subject or "", spec.copper)
		res = ok and r or nil
	elseif spec.how ~= "mail" and M and M.FillTrade then
		local ok, r = pcall(M.FillTrade, spec.copper)
		res = ok and r or nil
	end
	ArenaUI.lastFillLine = line
	if res == "filled" then return spec.how == "mail" and "mail" or "trade" end
	if res == "said" then return "type" end
	if res == "combat" then return "combat" end
	if res == "gamepad" then return "gamepad" end
	-- (No fill helper in this build, or the window closed: the line says what to send.)
	ns.Print(line)
	ArenaUI.Say(line)
	return "closed"
end

---------------------------------------------------------------------------
-- Countdowns: one C_Timer ticker (0.5 s) runs while a countdown shows; server time, so every
-- client shows the same closing time.
---------------------------------------------------------------------------

local clocks = {} -- fontstring -> { at, fmt, done }
local clockTicker
local function TickClocks()
	local any = false
	local now = ns.Arena.Now()
	for fs, c in pairs(clocks) do
		local shown = fs.IsVisible and fs:IsVisible()
		if shown then
			any = true
			local left = c.at - now
			fs:SetText(left > 0 and c.fmt:format(Kit.Clock(left)) or (c.done or ""))
		end
	end
	if not any and clockTicker then
		if clockTicker.Cancel then clockTicker:Cancel() end
		clockTicker = nil
	end
end
Kit.TickClocks = TickClocks
-- Shows `fmt` ("Bets close in %s") counting down to server time `at` on `fs`, `done` after it.
function Kit.Countdown(fs, at, fmt, done)
	if not fs then return end
	at = tonumber(at)
	if not at then
		clocks[fs] = nil
		return
	end
	clocks[fs] = { at = at, fmt = fmt or "%s", done = done }
	TickClocks()
	if not clockTicker and C_Timer and C_Timer.NewTicker then
		clockTicker = C_Timer.NewTicker(0.5, function() ns.SafeCall("arena clocks", TickClocks) end)
	end
end
function Kit.StopCountdown(fs) clocks[fs] = nil end
function Kit.ClockRunning() return clockTicker ~= nil end

---------------------------------------------------------------------------
-- Lists (the host's Views.Render, rows in dark ink on parchment) in a scroll frame
---------------------------------------------------------------------------

-- (style "hd": the Olympus window's dark list, 2026-09-30: its rows and light words; the ink
-- colours of the lines are turned to their light kin.)
local LIGHT = { ["|cff5c5040"] = "|cff9d9d9d", ["|cff7a4a00"] = "|cffffd200", ["|cff8b1a1a"] = "|cffff6060", ["|cff1f5a12"] = "|cff40ff40", ["|cff17406e"] = "|cff66aaff" }
local function Light(s)
	if type(s) ~= "string" then return s end
	return (s:gsub("|cff%x%x%x%x%x%x", function(c) return LIGHT[c:lower()] or c end))
end
function Kit.List(parent, w, h, style)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, parent) end
	-- (The template's scroll bar hangs off the frame's right edge, 6 to 22 px out: the frame is
	-- made that much narrower, so the bar sits at the list's own right edge, inside w.)
	local bar = ok and 24 or 0
	scroll:SetSize(w - bar, h)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(w - bar - 4, h)
	if scroll.SetScrollChild then scroll:SetScrollChild(content) end
	scroll.content = content
	if style == "hd" then content.style = "hd" end
	function scroll:SetLines(lines, layout)
		self.lines = lines
		local ink = Kit.Font()
		for _, line in ipairs(lines or {}) do
			if style == "hd" then
				line.text, line.right = Light(line.text), Light(line.right)
			elseif line.font == nil and not line.header and not line.cols then
				line.font = ink
			end
		end
		local V = ns.Views
		if V and V.Render then
			local okRender, err = pcall(V.Render, self.content, lines or {}, layout)
			if not okRender then ns.Log("arena list: %s", tostring(err)) end
		end
	end
	return scroll
end

---------------------------------------------------------------------------
-- The rules' yes before anything that commits (the design): bet, deposit, challenge, register,
-- a chat line. Viewing needs none.
---------------------------------------------------------------------------

-- Arena.Do(action, ...) behind the rules page: shown first when the player never said yes, and
-- the action goes on only after "I agree". Returns ok, why.
function ArenaUI.Commit(action, ...)
	local A = ns.Arena
	if ns.Arena.Sim() then return false, "sim" end
	if not A.RulesAccepted() then
		local args = { n = select("#", ...), ... }
		if ArenaUI.ShowRules then
			ArenaUI.ShowRules(function() ArenaUI.Commit(action, unpack(args, 1, args.n)) end)
		end
		return false, "rules"
	end
	local ok, why = A.Do(action, ...)
	if not ok then ArenaUI.Say(Kit.Why(why)) end
	return ok, why
end

-- A line in the window's status area (and the chat when the window is closed).
function ArenaUI.Say(text)
	if type(text) ~= "string" or text == "" then return end
	ArenaUI.lastSaid = text
	local f = ArenaUI.frame
	if f and f.status and f:IsShown() then
		f.status:SetText(text)
	else
		ns.Print(text)
	end
end

---------------------------------------------------------------------------
-- Tier medallions (the design: the arena division's crossed swords, bronze, silver, gold;
-- the design) and the art the companion ships (media/arena, scripts/make-arena-art.py), each with a
-- game-icon fallback.
---------------------------------------------------------------------------

Kit.MEDIA = "Interface\\AddOns\\Olympus_Arena\\media\\arena\\"
local TIER_TINT = { gold = { 1, 0.82, 0.2 }, silver = { 0.82, 0.86, 0.92 }, bronze = { 0.80, 0.52, 0.30 } }
local function Exists(path) return not GetFileIDFromPath or GetFileIDFromPath(path) ~= nil end
Kit.Exists = Exists
-- A medallion's texture and its tint (nil tint: the art is coloured already).
function Kit.TierTexture(tier)
	if not TIER_TINT[tier] then return nil end
	local file = Kit.MEDIA .. "tier-" .. tier
	if Exists(file) then return file, nil end
	local H = ns.HonorsNet
	if type(H) == "table" and type(H.BadgeTexture) == "function" then
		local ok, tex, tint = pcall(H.BadgeTexture, tier)
		if ok and type(tex) == "string" then return tex, type(tint) == "table" and tint or TIER_TINT[tier] end
	end
	return "Interface\\Icons\\Ability_DualWield", TIER_TINT[tier]
end
function Kit.SetTier(tex, tier)
	local file, tint = Kit.TierTexture(tier)
	if not file then tex:Hide() return end
	tex:SetTexture(file)
	if tint and tex.SetVertexColor then tex:SetVertexColor(tint[1], tint[2], tint[3]) elseif tex.SetVertexColor then tex:SetVertexColor(1, 1, 1) end
	tex:Show()
end
-- The tier's inline texture for list rows ("|T...|t").
function Kit.TierMark(tier, size)
	local file, tint = Kit.TierTexture(tier)
	if not file then return "" end
	size = size or 13
	if tint then
		return ("|T%s:%d:%d:0:0:64:64:4:60:4:60:%d:%d:%d|t"):format(file, size, size, tint[1] * 255, tint[2] * 255, tint[3] * 255)
	end
	return ("|T%s:%d:%d|t"):format(file, size, size)
end
function Kit.Emblem()
	local file = Kit.MEDIA .. "emblem"
	if Exists(file) then return file end
	return "Interface\\Icons\\Ability_DualWield"
end

-- Class colours for names (plain text inside).
function Kit.Colored(name, classFile)
	local plain = Kit.Name(name)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return c and c.colorStr and ("|c%s%s|r"):format(c.colorStr, plain) or plain
end

---------------------------------------------------------------------------
-- A fighter's portrait (the design, every screen; 1.2, the owner's ask: identical to the player's
-- own on his unit frame). Borders.NewPortrait draws it: the same picture (SetPortraitTexture's
-- square one, or the token Kit.Portrait picks), the same mask and ring, and round it the same rig
-- of Olympus art as his own portrait, at the same offsets and proportion, at any size. Its frame:
-- the honour the screen names (the profile's pick, the podium's place), else the honour his
-- client picked once this client verified it (HonorsNet.Verified, the fights part; "none": no frame), else his
-- rank's tier (Borders.TierOfName: the trust rules of the marks by his name), else none.
---------------------------------------------------------------------------

-- A portrait `size` across on `parent`; its slot is the square a screen places and anchors to,
-- its top a frame over its art for the screen's own marks. Where Borders.lua is the core's
-- stand-in (a client updated without a restart, Core.lua's StandIn), the picture alone, round.
function Kit.NewPortrait(parent, size)
	local B = ns.Borders
	local rig = B.missing ~= true and B.NewPortrait(parent, size) or nil
	if type(rig) == "table" then return rig end
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(size, size)
	local portrait = slot:CreateTexture(nil, "ARTWORK")
	portrait:SetAllPoints(slot)
	return { slot = slot, portrait = portrait, top = slot, plain = true, round = Kit.RoundPortrait(portrait, slot) }
end
-- Whether its picture is asked for square (its mask rounds it): the player's frame's way, and the
-- stand-in's where its round mask took.
function Kit.Square(rig) return not rig.plain or rig.round == true end
function Kit.SizePortrait(rig, size)
	if rig.plain then return rig.slot:SetSize(size, size) end
	return ns.Borders.SizePortrait(rig, size)
end
-- How far a portrait `size` across may have art past its square, in px each way (whole pixels:
-- Borders.PortraitReach), so a screen keeps its words clear of it; none without Borders.lua.
function Kit.PortraitReach(size)
	local B = ns.Borders
	local r = B.missing ~= true and B.PortraitReach(size) or nil
	local out = { left = 0, right = 0, top = 0, bottom = 0 }
	if type(r) ~= "table" then return out end
	for k in pairs(out) do out[k] = tonumber(r[k]) or 0 end
	return out
end

-- What frames a name here: { kind = "honour", key, tier } (his verified honour; tier, his rank's,
-- for a client without that honour's art), { kind = "rank", key = his tier } or {}.
function Kit.FrameOf(name, guild)
	if type(name) ~= "string" then return {} end
	local v = ArenaUI.Data.Verified(name)
	if type(v) == "table" and v.frame == "none" then return {} end
	local B, tier = ns.Borders, nil
	if type(B) == "table" and type(B.TierOfName) == "function" then
		local ok, t = pcall(B.TierOfName, name, guild)
		if ok then tier = t end
	end
	if type(v) == "table" and v.frame and v.frame ~= "rank" then return { kind = "honour", key = v.frame, tier = tier } end
	if tier then return { kind = "rank", key = tier } end
	return {}
end

-- An honour's frame on a portrait (Borders.ShowHonour: its key as HonorsNet spells it, or the
-- arena's own "-1" spelling of a first place). The key worn, or nil where this client has no art
-- for it.
local function WearHonour(rig, key)
	if type(key) ~= "string" or key == "" or rig.plain then return nil end
	if ns.Borders.ShowHonour(rig, key) then return rig.shown end
	return nil
end

-- The portraits framed with the author's preview's chance (not asSeen) and what framed them, so
-- an Arena already open follows his preview at once, as his unit frame does (BORDERS_PREVIEW:
-- the preview changed, or whether it shows). Weak: a portrait gone is forgotten.
local framed = setmetatable({}, { __mode = "k" })

-- The frame on a portrait (Kit.NewPortrait's): `honour` the screen's, else Kit.FrameOf's; the
-- author's own while his preview shows round his own portrait, the preview, except `asSeen` (as
-- others see him: his preview is his screen's alone). Returns { kind = "honour"|"rank"|nil, key }.
function Kit.SetPortraitFrame(rig, name, guild, honour, asSeen)
	if type(rig) ~= "table" then return {} end
	framed[rig] = not rig.plain and not asSeen and { name, guild, honour } or nil
	-- (the author's border preview on his own, as round his own portrait: /oly borders test)
	if not rig.plain and not asSeen then
		local previewed, kind = ns.Borders.ShowPreviewOn(rig, name)
		if previewed then return { kind = kind, key = kind and ns.Borders.Preview() or nil, preview = true } end
	end
	local worn = WearHonour(rig, honour)
	if worn then return { kind = "honour", key = worn } end
	local fr = Kit.FrameOf(name, guild)
	if fr.kind == "honour" then
		worn = WearHonour(rig, fr.key)
		if worn then return { kind = "honour", key = worn } end
		fr = fr.tier and { kind = "rank", key = fr.tier } or {}
	end
	if not rig.plain then ns.Borders.ShowTier(rig, fr.key) end
	return fr
end

ns.On("BORDERS_PREVIEW", function()
	for rig, by in pairs(framed) do ns.SafeCall("arena portrait preview", Kit.SetPortraitFrame, rig, by[1], by[2], by[3]) end
end)

-- A portrait filled: the picture Kit.Portrait picks (opts: class, race, gender, emblem), the
-- square one as the player's frame asks SetPortraitTexture for, and its frame (opts.guild,
-- opts.honour); opts.asSeen, both as others see him. Returns the picture's kind and the frame.
function Kit.DrawPortrait(rig, name, opts)
	opts = opts or {}
	local kind = Kit.Portrait(rig.portrait, name, { class = opts.class, race = opts.race, gender = opts.gender, emblem = opts.emblem,
		square = Kit.Square(rig), asSeen = opts.asSeen })
	return kind, Kit.SetPortraitFrame(rig, name, opts.guild, opts.honour, opts.asSeen)
end
