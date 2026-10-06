local ADDON, ns = ...
local L = ns.L

-- The version letters (1.1.5, the author's call): after the addon updates to a new version, once a
-- version, a short letter about what changed in it, from the dev (no name), on a pop-up of Olympus's
-- own in the Olympus window's bronze metal, without its portrait and logo (only the Olympus window
-- has them: ns.Window, Dialog.lua), and a parchment compartment (the Royal Writs' paper,
-- UI.PARCHMENTS). The Olympus window's help button (its "i", UI.ShowHelp) keeps them all: the help
-- page's Version letters button lists every letter, newest first, and a click opens that
-- version's letter; `/oly letters` opens the list too, `/oly letters <version>` that letter.
-- When it shows by itself: after login (LOGIN_WAIT, then on the minute until it could), for a
-- member of an Olympus guild (outside one the addon offers nothing but the Join Olympus screen),
-- never in combat or an instance, and only while no first-open page shows or waits: the privacy
-- page (Consent.lua) is asked first, and the letter waits until it is closed. Once a version,
-- saved per account (ns.db.lettersRead[version]). A first session shows it too: WoW: Forever's
-- beta client saves addon data but never loads it back, so there every session is a first one
-- (Core.lua's db.sessions is 1 each time), and taking that for a new install kept the letter from
-- ever showing by itself. There it shows again every session, as the privacy page asks again; a
-- real new install sees the running version's letter once. Only the running version's letter
-- shows by itself (the letters of versions a player skipped wait in the list).
-- The gamepad UI: Olympus's own frame, never the game's popup; nothing in it takes the keyboard
-- (no edit box); it goes on the escape list only with mouse and keyboard (ns.EscapeCloses), and
-- its X and Close hide it in either mode, in combat too (onCloseCallback, as the Olympus window).
-- The letters themselves are strings (Locales.lua: L.LETTER_<version>_TITLE and L.LETTER_<version>,
-- the version's dots as underscores), English and pt-BR; a version listed here without its
-- strings is left out. Plain text, but for the marks of the game's chat a letter may draw (1.1.5's
-- legend of who is who): {star}, {gold}, {silver} and {bronze} become, as the page shows the
-- letter, the very art the chat puts before names (Borders.ChatLegendText, at MARK_SIZE); a mark
-- this client has no art for (a dragon's atlas it lacks, or Borders.lua stopped by an error at
-- load, its legend missing) is its name in words (L.LETTER_MARK_<MARK>), never a broken code. Any
-- other {word} stays as written. (Not an update without a restart: Borders.lua is in the file list
-- since 1.0.0, so /reload loads its new self; Letters.lua is the new file there, and its stand-in,
-- Core.lua's, says to restart before any letter shows.)

local Letters = {}
ns.Letters = Letters

-- Every version with a letter, newest first.
Letters.LIST = { "1.2.0", "1.1.5", "1.1.4", "1.1.3", "1.1.2", "1.1.1", "1.1.0" }
Letters.LOGIN_WAIT = 60 -- after login (the privacy page asks at 45 s: Consent.LOGIN_WAIT)
Letters.WIDTH, Letters.HEIGHT = 440, 470

local frame, ticker

local function Key(version) return "LETTER_" .. tostring(version):gsub("%.", "_") end

-- The marks a letter may draw: its word in the text -> Borders' mark.
Letters.MARKS = { star = "member", gold = "gold", silver = "silver", bronze = "bronze" }
Letters.MARK_SIZE = 16 -- (the chat's are 14 px, beside a smaller font)
local MARK_WORDS = { star = "Star:", gold = "Gold dragon:", silver = "Silver dragon:", bronze = "Bronze dragon:" }

-- A letter's text with its marks drawn (see the top of the file).
function Letters.DrawMarks(text)
	if type(text) ~= "string" then return text end
	return (text:gsub("{(%a+)}", function(word)
		local mark = Letters.MARKS[word]
		if not mark then return nil end
		local B = ns.Borders
		local ok, art = false, nil
		if type(B) == "table" and type(B.ChatLegendText) == "function" then ok, art = pcall(B.ChatLegendText, mark, Letters.MARK_SIZE) end
		if ok and type(art) == "string" and art ~= "" then return art end
		local said = rawget(L, "LETTER_MARK_" .. word:upper())
		return type(said) == "string" and said ~= "" and said or MARK_WORDS[word]
	end))
end

local function Strings(version)
	local key = Key(version)
	local title, body = rawget(L, key .. "_TITLE"), rawget(L, key)
	if type(title) ~= "string" or type(body) ~= "string" or title == "" or body == "" then return nil end
	return title, body
end

-- A version's letter: its title and its text as the page shows them (its marks drawn), or nil when
-- it has none.
function Letters.Text(version)
	local title, body = Strings(version)
	if not title then return nil end
	return Letters.DrawMarks(title), Letters.DrawMarks(body)
end
function Letters.Has(version) return Strings(version) ~= nil end

-- The versions with a letter, newest first.
function Letters.Versions()
	local out = {}
	for _, v in ipairs(Letters.LIST) do if Letters.Has(v) then out[#out + 1] = v end end
	return out
end

local function Read()
	local db = ns.db
	if type(db) ~= "table" then return {} end
	if type(db.lettersRead) ~= "table" then db.lettersRead = {} end
	return db.lettersRead
end
function Letters.IsRead(version) return Read()[version] == true end
function Letters.MarkRead(version) if version then Read()[version] = true end end

local function Busy()
	return (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) and true or false
end

-- A first-open page shows, or waits to ask this session (Consent.Waiting).
local function PageFirst()
	local C = ns.Consent
	if type(C) ~= "table" or C.missing then return false end
	local f = type(C.Frame) == "function" and C.Frame() or nil
	if f and f:IsShown() then return true end
	return type(C.Waiting) == "function" and C.Waiting() == true
end

---------------------------------------------------------------------------
-- The pop-up
---------------------------------------------------------------------------

local function Height(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return h end
	end
	-- (No measure: about 6 pixels a letter, 14 a line.)
	local lines = 0
	for line in ((fs:GetText() or "") .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(#line / math.max(1, math.floor(width / 6))))
	end
	return lines * 14
end

local function Button(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 22)
	b:SetText(label)
	return b
end

local function SetTitle(f, text) ns.SetWindowTitle(f, text) end

-- The metal without the portrait (ns.Window): no inset box of its own, the letter brings its
-- compartment. Escape closes it with mouse and keyboard (checked each time it shows); with the
-- gamepad UI its X and Close do, in combat too.
local function Make()
	local f = ns.Window("OlympusLetterFrame", UIParent, { inset = false })
	f:SetSize(Letters.WIDTH, Letters.HEIGHT)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	-- The header, under the title bar (where the Olympus window has its army's count).
	f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.head:SetPoint("TOPLEFT", 14, -30)
	f.head:SetPoint("RIGHT", -14, 0)
	f.head:SetJustifyH("LEFT")
	if f.head.SetWordWrap then f.head:SetWordWrap(false) end
	-- The compartment: the game's inset box, the parchment inside it.
	local okBox, box = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if not okBox or not box then box = CreateFrame("Frame", nil, f) end
	box:SetPoint("TOPLEFT", 10, -54)
	box:SetPoint("BOTTOMRIGHT", -10, 38)
	f.box = box
	local paper = box:CreateTexture(nil, "BACKGROUND", nil, 1)
	paper:SetPoint("TOPLEFT", 3, -3)
	paper:SetPoint("BOTTOMRIGHT", -3, 3)
	local file = ns.UI and ns.UI.FirstTexture and ns.UI.FirstTexture(ns.UI.PARCHMENTS) or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		paper:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		paper:SetTexture(file)
		if file:find("QuestBG", 1, true) then paper:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	f.paper = paper
	-- The page, scrolled when a letter is longer than the box.
	local scroll = CreateFrame("ScrollFrame", f:GetName() .. "Scroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -10)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	f.scroll = scroll
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(Letters.WIDTH - 70, 10)
	scroll:SetScrollChild(page)
	f.page = page
	f.title = page:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.title:SetJustifyH("LEFT")
	f.body = page:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	f.body:SetJustifyH("LEFT")
	if f.body.SetJustifyV then f.body:SetJustifyV("TOP") end
	if f.body.SetWordWrap then f.body:SetWordWrap(true) end
	f.sign = page:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	f.sign:SetJustifyH("RIGHT")
	f.rows = {}
	-- The buttons: every letter (from a letter), and Close.
	f.done = Button(f, L.LETTERS_CLOSE, 100)
	f.done:SetPoint("BOTTOMRIGHT", -12, 10)
	f.done:SetScript("OnClick", function() f:Hide() end)
	f.all = Button(f, L.LETTERS_ALL, 130)
	f.all:SetPoint("BOTTOMLEFT", 12, 10)
	f.all:SetScript("OnClick", function() ns.SafeCall("letters", Letters.ShowHistory) end)
	return f
end

local function Frame()
	if frame and rawget(_G, frame:GetName()) ~= frame then frame = nil end -- (tests: a rebuilt toolkit)
	frame = frame or Make()
	return frame
end

local function HideRows(f)
	for _, r in ipairs(f.rows) do r:Hide() end
end

-- A version's letter on the page; true when it has one.
function Letters.Show(version)
	local title, body = Letters.Text(version)
	if not title then return false end
	local f = Frame()
	HideRows(f)
	local width = Letters.WIDTH - 70
	SetTitle(f, L.LETTER_TITLE:format(version))
	f.head:SetText(L.LETTERS_TITLE)
	f.mode, f.version = "letter", version
	f.title:ClearAllPoints()
	f.title:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, 0)
	f.title:SetWidth(width)
	f.title:SetText(title)
	local y = -Height(f.title, width) - 10
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, y)
	f.body:SetWidth(width)
	f.body:SetText(body)
	y = y - Height(f.body, width) - 12
	f.sign:ClearAllPoints()
	f.sign:SetPoint("TOPRIGHT", f.page, "TOPRIGHT", 0, y)
	f.sign:SetWidth(width)
	f.sign:SetText(L.LETTER_SIGNED)
	y = y - 20
	for _, part in ipairs({ f.title, f.body, f.sign }) do part:Show() end
	f.page:SetHeight(-y)
	if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
	f.all:Show()
	Letters.MarkRead(version)
	f:Show()
	return true
end

local function Row(f, i)
	local r = f.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, f.page)
	r:SetHeight(22)
	r.text = r:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	r.text:SetPoint("LEFT", 4, 0)
	r.text:SetPoint("RIGHT", -4, 0)
	r.text:SetJustifyH("LEFT")
	if r.text.SetWordWrap then r.text:SetWordWrap(false) end
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r:SetScript("OnClick", function(self) ns.SafeCall("letters", Letters.Show, self.version) end)
	f.rows[i] = r
	return r
end

-- Every letter, newest first; a click opens that version's letter.
function Letters.ShowHistory()
	local f = Frame()
	SetTitle(f, L.LETTERS_TITLE)
	f.head:SetText(L.LETTERS_INTRO)
	f.mode, f.version = "list", nil
	for _, part in ipairs({ f.title, f.body, f.sign }) do part:Hide() end
	local width, y = Letters.WIDTH - 70, 0
	local list = Letters.Versions()
	for i, v in ipairs(list) do
		local r = Row(f, i)
		r.version = v
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, y)
		r:SetWidth(width)
		local title = Letters.Text(v)
		local now = v == ns.VERSION and ("  |cff9d9d9d(" .. L.LETTERS_CURRENT .. ")|r") or ""
		r.text:SetText(L.LETTERS_ROW:format(v, title) .. now)
		r:Show()
		y = y - 24
	end
	for i = #list + 1, #f.rows do f.rows[i]:Hide() end
	f.page:SetHeight(math.max(10, -y))
	if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
	f.all:Hide()
	f:Show()
	return f
end

function Letters.Frame() return frame end
function Letters.Hide() if frame then frame:Hide() end end

---------------------------------------------------------------------------
-- By itself, once a version
---------------------------------------------------------------------------

-- The running version's letter, if it has one and it was never shown, when nothing keeps it
-- back (see the top of the file). True when it showed.
function Letters.Ask(reason)
	local v = ns.VERSION
	if not Letters.Has(v) or Letters.IsRead(v) then return false end
	if ns.IsMember() ~= true or Busy() or PageFirst() then return false end
	if frame and frame:IsShown() then return false end
	ns.Log("version letter %s shown (%s)", tostring(v), tostring(reason or "?"))
	return Letters.Show(v)
end

-- The running version's letter, if it was never shown on this account (a first session too: see
-- the top of the file), from LOGIN_WAIT after login, then on the minute until it could.
function Letters.OnLogin()
	if not Letters.Has(ns.VERSION) or Letters.IsRead(ns.VERSION) then return end
	ns.After(Letters.LOGIN_WAIT, "version letter", function() Letters.Ask("login") end)
	ticker = ns.Every(60, "version letter", function()
		if Letters.IsRead(ns.VERSION) then
			if ticker and ticker.Cancel then ticker:Cancel() end
			ticker = nil
			return
		end
		Letters.Ask("login")
	end)
end
ns.On("LOGIN", function() Letters.OnLogin() end)

-- `/oly letters` (the list), `/oly letters <version>` (that letter; one without a letter: the list).
function Letters.Slash(rest)
	local v = type(rest) == "string" and rest:match("^%s*(%d+%.%d+%.%d+)%s*$") or nil
	if v and Letters.Show(v) then return end
	Letters.ShowHistory()
end

function Letters.StatusLine()
	local read = {}
	for _, v in ipairs(Letters.Versions()) do if Letters.IsRead(v) then read[#read + 1] = v end end
	return ("%s  |  read: %s"):format(Letters.Has(ns.VERSION) and (Letters.IsRead(ns.VERSION) and "this version's shown" or "this version's waiting")
		or "none for this version", #read > 0 and table.concat(read, ", ") or "none")
end

-- Tests start from a clean state.
function Letters.Reset()
	if ticker and ticker.Cancel then ticker:Cancel() end
	ticker = nil
	if frame and rawget(_G, frame:GetName()) == frame then frame:Hide() end
	frame = nil
end
