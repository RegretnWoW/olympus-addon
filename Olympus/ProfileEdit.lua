local ADDON, ns = ...

-- 1.2, the Blood Arena: ProfileEdit.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- "My profile" and its Edit panel in the Olympus window (through UI.profileEditors): frame, title,
-- nickname, emblem and history pickers, the icon picker (Workshop.IconPickerHost: the player's
-- honour marks first, then the game's icons), "preview as others see me"; frames built on first
-- open only. The Realm tab's "My council icon" opens it (UI.OpenIconPicker calls ProfileEdit.Open).
-- API (the design): Open(what) ("icon" opens on the icon picker), ViewModel(), Preview()
local ProfileEdit = {}
ns.ProfileEdit = ProfileEdit

-- The profile's Edit lives in the core (the design): honours are one system for all, and the Arena
-- window is hidden while the live switch is off and missing when the companion is disabled. It is
-- a panel of Olympus's own (OlympusProfileEdit), built the first time it opens, beside the Olympus
-- window when that is open: buttons only (no edit box, no game popup), every one 24 px tall, so it
-- works the same with the gamepad UI; Escape closes it through ns.EscapeCloses. The Arena
-- window's Profile tab (the screens) draws the same view model (ProfileEdit.ViewModel) and calls the same
-- pickers.
--   ViewModel() -> { frames = { { key, label, art, shape, metal, selected } } (the rank's, none, and
--     every frame held), titles = { { key, label, selected } } (none, and every title held), nick =
--     { a, n, text, lists = { A, N } }, emblem, pub, locked, letters = { { key, title, t, read } },
--     preview = Preview(), councillor, honours = the honours held (Honors.Holdings's) }
--   Preview() -> what another client shows of this player now: { frame, title, titleText, mark,
--     frameTexture, shape, markTexture, nick, emblem }
--   PickFrame(key), PickTitle(key), Nick(a, n), Emblem(icon), SetPublic(on), Lock(on),
--   IconPicker(kind) ("emblem": the fighter's emblem; "icon": a councillor's own icon), Close()

local L = ns.L
local PE = ProfileEdit
local Arena = ns.Arena

PE.WIDTH, PE.HEIGHT = 330, 420
PE.ROW = 24
PE.PORTRAIT = 40 -- the preview's portrait (its art reaches past it: HonorsNet.NewPortrait)

local function P() return ns.ArenaProfile end
local function H() return ns.HonorsNet end

---------------------------------------------------------------------------
-- The view model
---------------------------------------------------------------------------

function PE.Preview()
	local HN = H()
	local v = HN.Verified(ns.me)
	local m = P().Mine()
	local tex, shape
	if v.frame ~= "rank" and v.frame ~= "none" then tex, shape = HN.FrameTexture(v.frame) end
	return { frame = v.frame, title = v.title, titleText = v.title and HN.TitleText(v.title) or nil, mark = v.mark,
		frameTexture = tex, shape = shape, markTexture = v.mark ~= "rank" and HN.MarkTexture(v.mark) or nil,
		nick = P().NickText(m.nick), emblem = m.emblem }
end

function PE.ViewModel()
	local HN, PR = H(), P()
	local held = HN.Holdings(ns.me, PR.MyGk())
	local pick = PR.Pick()
	local m = PR.Mine()
	local vm = { frames = {}, titles = {}, honours = held, emblem = m.emblem, pub = m.pub == true, locked = m.locked == true,
		letters = {}, councillor = ns.IsHighCouncillor(ns.me) == true }
	vm.frames[1] = { key = "rank", label = L.PROFILE_FRAME_RANK, selected = (pick.frame or "rank") == "rank" }
	vm.frames[2] = { key = "none", label = L.PROFILE_FRAME_NONE, selected = pick.frame == "none" }
	vm.titles[1] = { key = "none", label = L.PROFILE_TITLE_NONE, selected = pick.title == nil }
	for _, h in ipairs(held) do
		if h.frame then
			vm.frames[#vm.frames + 1] = { key = h.frame, label = HN.TitleText(h.key) or h.key, art = h.art, shape = h.shape, metal = h.metal,
				milestone = h.milestone, selected = pick.frame == h.frame }
		end
		if h.title then vm.titles[#vm.titles + 1] = { key = h.title, label = HN.TitleText(h.key) or h.key, selected = pick.title == h.title } end
	end
	local a, n = tostring(m.nick or "0.0"):match("^(%d+)%.(%d+)$")
	vm.nick = { a = tonumber(a) or 0, n = tonumber(n) or 0, text = PR.NickText(m.nick), lists = { A = L.ARENA_EPI_A, N = L.ARENA_EPI_N } }
	for _, x in ipairs(HN.Letters()) do
		vm.letters[#vm.letters + 1] = { key = x.key, title = HN.TitleText(x.key), t = x.t, read = x.read == true }
	end
	vm.preview = PE.Preview()
	return vm
end

---------------------------------------------------------------------------
-- The pickers (each one click; the profile says itself on every change: AP)
---------------------------------------------------------------------------

function PE.PickFrame(key)
	local pick = P().Pick()
	local ok, why = P().SetPick(key or "rank", pick.title)
	PE.Refresh()
	return ok, why
end
function PE.PickTitle(key)
	local pick = P().Pick()
	local ok, why = P().SetPick(pick.frame or "rank", key ~= "none" and key or nil)
	PE.Refresh()
	return ok, why
end
function PE.Nick(a, n)
	local ok, why = P().SetNick(a, n)
	PE.Refresh()
	return ok, why
end
-- A step through a list (-1 or +1, wrapping, 0 for none).
function PE.NickStep(which, delta)
	local m = P().Mine()
	local a, n = tostring(m.nick or "0.0"):match("^(%d+)%.(%d+)$")
	a, n = tonumber(a) or 0, tonumber(n) or 0
	local size = ns.ArenaProfile.EPITHETS
	if which == "a" then a = (a + delta) % (size + 1) else n = (n + delta) % (size + 1) end
	if a == 0 or n == 0 then
		if a == 0 and n == 0 then return PE.Nick(0, 0) end
		if a == 0 then a = 1 end
		if n == 0 then n = 1 end
	end
	return PE.Nick(a, n)
end
function PE.Emblem(icon)
	local ok, why = P().SetEmblem(icon)
	PE.Refresh()
	return ok, why
end
function PE.SetPublic(on)
	local C = ns.Consent
	if type(C) == "table" and not C.missing and type(C.Choose) == "function" and C.Choose("arenaHistory", on) then
		PE.Refresh()
		return true
	end
	local ok = P().SetPublic(on)
	PE.Refresh()
	return ok
end
function PE.Lock(on)
	P().SetLocked(on)
	PE.Refresh()
	return true
end

-- The icon pickers inside the Edit (Workshop.IconPickerHost). kind "icon", the chat icon
-- (the design: councillors keep their picked icon, otherwise the chosen honour's mark): the
-- player's honour marks first, then, for a councillor, the game's whole list. "emblem" (the
-- default), the fighter's emblem (the design: a game icon, ns.CouncilIconValue on both ends): the
-- game's icons only.
function PE.IconList(kind)
	local HN = H()
	local out = {}
	if kind == "icon" then
		for _, h in ipairs(HN.Holdings(ns.me, P().MyGk())) do
			if h.art then
				out[#out + 1] = { key = h.art, texture = HN.MarkTexture(h.art), label = HN.TitleText(h.key) or h.key }
			end
		end
		if not ns.IsHighCouncillor(ns.me) then return out end
	end
	local W = ns.Workshop
	local icons = type(W) == "table" and type(W.GameIcons) == "function" and W.GameIcons() or {}
	for _, icon in ipairs(icons) do out[#out + 1] = icon end
	return out
end
-- A councillor's own icon as he picked it (Workshop.SetCouncilIcon keeps it), or nil.
local function MyCouncilIcon()
	local mine = ns.db and ns.db.councilIcons
	local v = type(mine) == "table" and mine[ns.me] or nil
	return v and ns.CouncilIconValue(v) or nil
end
-- The honour a mark (its art) belongs to among those held, or nil.
function PE.HonourOfMark(art)
	if type(art) ~= "string" then return nil end
	for _, h in ipairs(H().Holdings(ns.me, P().MyGk())) do
		if h.art == art then return h end
	end
	return nil
end
-- An icon picked in the chat icon picker: an honour's mark picks that honour (its frame: the mark
-- shown is the shown honour's; the title stays) and takes a councillor's own icon away so the
-- mark shows; a game icon is a councillor's own icon. True when taken.
function PE.PickIcon(icon)
	local W = ns.Workshop
	local h = type(icon) == "string" and PE.HonourOfMark(icon)
	if h then
		local pick = P().Pick()
		P().SetPick(h.frame or pick.frame, pick.title)
		if ns.IsHighCouncillor(ns.me) and MyCouncilIcon() and type(W) == "table" and W.SetCouncilIcon then W.SetCouncilIcon(nil) end
		return true
	end
	if ns.IsHighCouncillor(ns.me) and ns.CouncilIconValue(icon) and type(W) == "table" and W.SetCouncilIcon then return W.SetCouncilIcon(icon) end
	ns.Print(L.PROFILE_ICON_REFUSED)
	return false
end
function PE.IconPicker(kind, parent)
	local W = ns.Workshop
	if type(W) ~= "table" or W.missing or type(W.IconPickerHost) ~= "function" then return nil end
	parent = parent or PE.frame
	if not parent then return nil end
	local chat = kind == "icon"
	local current
	if chat then
		current = MyCouncilIcon() or H().Verified(ns.me).art
	else
		current = P().Mine().emblem
	end
	return W.IconPickerHost(parent.pickerHost or parent, PE.IconList(kind), function(icon)
		if chat then
			PE.PickIcon(icon)
		elseif icon ~= nil and not ns.CouncilIconValue(icon) then
			-- (An honour's mark is never an emblem: AP carries a game icon only.)
			ns.Print(L.PROFILE_ICON_REFUSED)
			return
		else
			PE.Emblem(icon)
		end
		PE.Refresh()
	end, current)
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 140, PE.ROW)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Build()
	local f = ns.Window("OlympusProfileEdit", UIParent, { close = false, escape = false })
	f:SetSize(PE.WIDTH, PE.HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	-- (1.1.5: the Olympus window's bronze metal, ns.Window: the title in its title bar.)
	f.title = f.TitleText
	ns.SetWindowTitle(f, L.PROFILE_EDIT_TITLE)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() PE.Close() end)
	f.close = close
	-- The preview: his portrait with the frame others see, as round his own unit frame's
	-- (HonorsNet.NewPortrait), its art clear of the edge, the title and the rows; the title beside it.
	local rig = H().NewPortrait(f, PE.PORTRAIT)
	local reach = rig.reach
	rig.slot:SetPoint("TOPLEFT", 14 + reach.left, -(30 + reach.top))
	f.rig, f.portrait = rig, rig.portrait
	f.seen = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.seen:SetPoint("TOPLEFT", rig.slot, "TOPRIGHT", reach.right + 10, -2)
	f.seen:SetPoint("RIGHT", -16, 0)
	f.seen:SetJustifyH("LEFT")
	-- The rows (made once; refreshed from the view model).
	f.lines = {}
	for i = 1, 12 do
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 16, -104 - (i - 1) * 16)
		fs:SetPoint("RIGHT", -16, 0)
		fs:SetJustifyH("LEFT")
		f.lines[i] = fs
	end
	f.prevFrame = Button(f, "<", 30, function() PE.Cycle("frame", -1) end)
	f.prevFrame:SetPoint("BOTTOMLEFT", 16, 118)
	f.nextFrame = Button(f, ">", 30, function() PE.Cycle("frame", 1) end)
	f.nextFrame:SetPoint("LEFT", f.prevFrame, "RIGHT", 4, 0)
	f.frameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.frameLabel:SetPoint("LEFT", f.nextFrame, "RIGHT", 8, 0)
	f.prevTitle = Button(f, "<", 30, function() PE.Cycle("title", -1) end)
	f.prevTitle:SetPoint("BOTTOMLEFT", 16, 90)
	f.nextTitle = Button(f, ">", 30, function() PE.Cycle("title", 1) end)
	f.nextTitle:SetPoint("LEFT", f.prevTitle, "RIGHT", 4, 0)
	f.titleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.titleLabel:SetPoint("LEFT", f.nextTitle, "RIGHT", 8, 0)
	f.nickA = Button(f, L.PROFILE_NICK_A, 90, function() PE.NickStep("a", 1) end)
	f.nickA:SetPoint("BOTTOMLEFT", 16, 62)
	f.nickN = Button(f, L.PROFILE_NICK_N, 90, function() PE.NickStep("n", 1) end)
	f.nickN:SetPoint("LEFT", f.nickA, "RIGHT", 4, 0)
	f.emblem = Button(f, L.PROFILE_EMBLEM, 110, function() PE.IconPicker("emblem") end)
	f.emblem:SetPoint("LEFT", f.nickN, "RIGHT", 4, 0)
	f.history = Button(f, L.PROFILE_HISTORY_PUBLIC, 140, function() PE.SetPublic(not P().Mine().pub) end)
	f.history:SetPoint("BOTTOMLEFT", 16, 34)
	f.lock = Button(f, L.PROFILE_LOCK, 140, function() PE.Lock(not P().Mine().locked) end)
	f.lock:SetPoint("LEFT", f.history, "RIGHT", 4, 0)
	f.letters = Button(f, L.PROFILE_LETTERS, 140, function()
		local list = H().Letters()
		local last = list[#list]
		if last then H().ShowLetter(last.key) end
	end)
	f.letters:SetPoint("BOTTOMLEFT", 16, 8)
	f.icon = Button(f, L.PROFILE_COUNCIL_ICON, 140, function() PE.IconPicker("icon") end)
	f.icon:SetPoint("LEFT", f.letters, "RIGHT", 4, 0)
	-- Where the hosted icon picker sits (over the rows).
	f.pickerHost = CreateFrame("Frame", nil, f)
	f.pickerHost:SetPoint("TOPLEFT", 12, -100)
	f.pickerHost:SetPoint("BOTTOMRIGHT", -12, 150)
	ns.EscapeCloses("OlympusProfileEdit")
	return f
end

-- The next frame or title held (wrapping), as one click.
function PE.Cycle(what, delta)
	local vm = PE.ViewModel()
	local list = what == "frame" and vm.frames or vm.titles
	local at = 1
	for i, x in ipairs(list) do if x.selected then at = i end end
	local nextOne = list[(at - 1 + delta) % #list + 1]
	if not nextOne then return false end
	if what == "frame" then return PE.PickFrame(nextOne.key) end
	return PE.PickTitle(nextOne.key)
end

function PE.Refresh()
	local f = PE.frame
	if not f or not f:IsShown() then return end
	local vm = PE.ViewModel()
	local pv = vm.preview
	H().DressPortrait(f.rig, pv.frame)
	f.seen:SetText(L.PROFILE_PREVIEW:format(pv.titleText or L.PROFILE_TITLE_NONE, pv.nick or "-"))
	local rows = {}
	rows[#rows + 1] = "|cffffd200" .. L.PROFILE_HONOURS .. "|r"
	for _, h in ipairs(vm.honours) do rows[#rows + 1] = "  " .. (H().TitleText(h.key) or h.key) end
	if #vm.honours == 0 then rows[#rows + 1] = "  |cff9d9d9d" .. L.PROFILE_NO_HONOURS .. "|r" end
	for i, fs in ipairs(f.lines) do fs:SetText(rows[i] or "") end
	local function Selected(list) for _, x in ipairs(list) do if x.selected then return x.label end end return "" end
	f.frameLabel:SetText(L.PROFILE_FRAME:format(Selected(vm.frames)))
	f.titleLabel:SetText(L.PROFILE_TITLE:format(Selected(vm.titles)))
	f.history:SetText(vm.pub and L.PROFILE_HISTORY_PUBLIC or L.PROFILE_HISTORY_PRIVATE)
	f.lock:SetText(vm.locked and L.PROFILE_LOCKED or L.PROFILE_LOCK)
	f.icon:SetShown(vm.councillor)
	f.letters:SetShown(#vm.letters > 0)
end

-- Opened (made the first time): beside the Olympus window when it is open. what "icon": straight on
-- a councillor's icon picker.
function PE.Open(what)
	if not ns.IsMember() then return false, "guild" end
	if InCombatLockdown and InCombatLockdown() and not PE.frame then return false, "combat" end
	PE.frame = PE.frame or Build()
	local f = PE.frame
	f:ClearAllPoints()
	local UI = ns.UI
	local main = type(UI) == "table" and UI.IsShown and UI.IsShown() and _G.OlympusFrame or nil
	if main then f:SetPoint("TOPLEFT", main, "TOPRIGHT", -4, -40) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
	f:Show()
	PE.Refresh()
	if what == "icon" then PE.IconPicker("icon") end
	-- A King's letter waiting (the gamepad UI shows none by itself): this click opens it.
	local HN = H()
	if HN and HN.QueuedLetters and HN.QueuedLetters()[1] then HN.ShowLetter(nil, true) end
	return true
end
function PE.Close()
	if PE.frame then PE.frame:Hide() end
	return true
end
function PE.IsOpen() return PE.frame ~= nil and PE.frame:IsShown() end

ns.On("HONORS_CHANGED", function() if PE.frame and PE.frame:IsShown() then PE.Refresh() end end)

Arena.Action("profile.edit", nil, function(what) return PE.Open(what) end)
