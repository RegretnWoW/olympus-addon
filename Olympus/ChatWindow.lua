local ADDON, ns = ...
local L = ns.L

-- The Olympus chats in the Olympus window (1.1.1): its Chat tab, right after the Realm (UI.lua's
-- TABS). The three chats ([Olympus], [Captains], [Lords]) like the chat pane of the Guild &
-- Communities window: the tabs' search box where the other tabs show the army's counts, and on
-- that row, right of it, a small switch of the channels (only for a rank that reads more than
-- one: most players read [Olympus] alone, and a row of its own for one lone channel took the
-- lines' room) and the settings' gear; each line whole in a bubble that wraps (nothing to hover to
-- read it) from under that row over the list's and the detail box's room, the 100 lines Channels
-- keeps per channel to scroll back through, a box to write in across the bottom where they have
-- their buttons (no Send button: Enter sends), and Olympus's marks by each name (the King's crown,
-- the High Council's mark, the Lords' and Captains' elite marks, Raiders and Veterans bronze, the
-- members' star, the Treasurer's coin, Stewards and Hands).
--
-- The first 1.1.1 build had it in a window of its own; the author wanted it inside the Olympus
-- window. UI.lua hands this file the window in use and where each part goes in its look
-- (ChatWindow.Attach), and the old window's calls stay as the ways to the tab: Open, Toggle and
-- Close (/ol, /olc or /oll alone, /oly talk and the minimap button's Shift-click) open the
-- Olympus window on its Chat tab, on the channel asked for, and close it. The
-- Realm tab's "Olympus chats" page it replaces is gone (the author's call): what that page offered
-- and the tab did not (the Olympus tab's state, the chats on or off with what that means, the
-- public channel's line, the pin for whoever may pin, the count of the lines the block terms hide)
-- is here, the most of it in the settings the gear opens in place of the lines, with each
-- channel's place in the game's chat (muted there or not, the chat window it goes to).
--
-- What it never does, whatever the input mode (mouse and keyboard, or Blizzard's gamepad UI):
-- - It never touches the game's chat boxes or windows: no script of theirs replaced or hooked,
--   and none opened from here (ChatFrame_OpenChat, ChatFrame_SendTell, ChatFrameUtil.*: they
--   write LAST_ACTIVE_CHAT_EDIT_BOX or CHAT_FOCUS_OVERRIDE, which the game's secure chat code
--   reads afterwards, so what the player types next runs tainted and /cast, /target, /use or
--   /click get blocked; with the gamepad UI that froze the game in 0.8.5). Every frame here is
--   Olympus's own. The Olympus tab of the game's chat (below) is made by the player, with the
--   game's own menu: Olympus only reads the game's chat windows to see it appear.
-- - Its box is Olympus's own EditBox: it never takes the keyboard by itself (SetAutoFocus(false)
--   the moment it is made, never focused on opening); the player clicks into it, with the mouse
--   or the gamepad cursor, or (mouse and keyboard, 1.1.1, the owner's ask) presses the game's
--   "Open chat" key while the tab shows: an override binding of Olympus's own button, below. Enter
--   sends through Channels.Send for an army chat, or ArenaChat.Send for a fight room, and the
--   cursor stays for the next line (an empty Enter, Escape or
--   a plain left-click elsewhere, the client's own, lets the keyboard go back to the game); with
--   the gamepad UI every Enter lets it go, as the Communities box does. It runs no command: a line
--   starting with "/" is kept and the player is told the game's chat box is where commands go
--   (and, with the cursor kept, that Escape and then his own key for it get him there).
-- - No game popup from it: the pinned line's takedown and a whisper go through ns.ShowDialog
--   (Olympus's own window with the gamepad UI); the Olympus window closes with Escape through
--   ns.EscapeCloses (nothing on UISpecialFrames with the gamepad UI: its X closes it there).
-- - Links in a line show their tooltip on hover (GameTooltip:SetHyperlink) and go into its own
--   box with a Shift-click; never SetItemRef, ChatEdit_InsertLink or HandleModifiedItemClick.
-- Nothing is drawn while the tab is hidden: a change marks it dirty and it redraws at most every
-- 0.2 s while shown (the census at most every 5 s).

local ChatWindow = {}
ns.ChatWindow = ChatWindow

local TAB = "chat"                                    -- its tab in the Olympus window (UI.lua)
local SEARCH_H = 20                                   -- the top row: the search, the channels' switch, the gear
local TOP_GAP = 4                                     -- between the top row's parts
-- (The destinations under Search, Olympus / Guild / Race / Class / Arena: the Realm's in-page tabs,
-- the same component, Views.DrawNav, in the same place: the first row of the list's box.)
local GEAR_W = 20
local ARROW_W = 12                                    -- the switch's arrow
local ROOM_BUTTON_W = 20                              -- a dynamic room's local pin and remove buttons
local MENU_ROW, MENU_PAD = 20, 4                      -- the switch's list of channels
local INDENT = 12                                     -- a setting under its heading
local PAD = 8                                         -- inside a bubble
local HEADER_H = 16
local EDGE = 8                                        -- a bubble from the box's side
local SHARE = 0.82                                    -- a bubble's width, at most, of the box's
local BUBBLE_MIN = 180
local GAP_IN, GAP_OUT = 3, 10                         -- between bubbles of one writer, between writers
local GROUP_TIME = 300                                -- a pause this long starts a new header
local STICK_SLACK = 2
local THROTTLE, DATA_GAP = 0.2, 5
local LINE_H = 14                                     -- a line of text, where the client gives no height
local PIN_LINES, GUIDE_LINES, COUNT_LINES = 3, 4, 2   -- the strips over the lines, at most
local GUIDE_X = 20                                    -- the Olympus tab's line: the room its x takes on the right
local MAX_NOTES = 5
local LOOK_GAP = 1                                    -- the Olympus tab awaited: the game's chat windows read this often
local GREY = "|cff9d9d9d"
local LINK_TIPS = { item = true, spell = true, enchant = true, quest = true } -- (the links Codec lets through)
local WHY = { moved = "CHATWIN_WHY_MOVED", late = "CHATWIN_WHY_LATE", failed = "CHATWIN_WHY_FAILED", left = "CHATWIN_WHY_LEFT" }
-- The pointer's arrow: the game's tutorial arrow (Blizzard_TutorialTemplates), else the chat
-- frame's own scroll-down arrow (Blizzard_SharedXML's dropdown and store templates use it).
local ARROW_ATLAS, ARROW_FILE = "NPE_ArrowDown", "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
-- The gear: the game's own settings icon (Forever's UIPanelIconDropdownButtonTemplate,
-- SharedUIPanelTemplates.xml), else the gear icon every client carries.
local GEAR_ATLAS, GEAR_FILE = "questlog-icon-setting", "Interface\\Icons\\INV_Misc_Gear_01"
local ROOM_COLOUR = { 0.95, 0.42, 0.28 }              -- the Arena's rust, distinct from the three army chats

local panes = {}             -- Olympus window -> its Chat tab (each look's window has its own)
local frame                  -- the Chat tab in use (a pane of `host`)
local host                   -- the Olympus window it is in
local tier                   -- the channel or stable dynamic-room key shown
ChatWindow.globalTier = nil  -- the legacy Olympus tier to return to from a logical room
local dynamicRooms = {}      -- stable key -> { key, id, spec, pinned, used }; local UI state only
local dynamicOrder = {}      -- stable keys, once each, in the order first opened/restored
local lastRoomPrune = -math.huge
local dirty, dataPending = false, false
local lastData = -math.huge
local unread = {}            -- tier -> lines from others since it was last looked at (while open)
local notes = {}             -- tier -> { { why, text } }: lines that were not sent, this session
ChatWindow.drafts = {}       -- logical room/tier -> this session's independent unfinished text
local revealed = setmetatable({}, { __mode = "k" }) -- history entry -> shown despite the block terms
local stick, newCount = true, 0 -- the view follows the newest line; lines come while it doesn't
local lastAt = 0             -- the offset the view had last
local want                   -- scrolled up: the offset that keeps the line read in its place
local quiet = false          -- our own scrolling: not the player's
local acc, lookAcc = 0, 0
local tipOwner
local pointer                -- the Olympus tab awaited: Olympus's own pointer by the game's chat tab
local watching = false       -- ... and the game's chat windows read until it is there
local sent = false           -- ... the click having sent the channels there already (Chattynator)
local settings = false       -- the settings (the gear) shown in place of the lines
local keyButton              -- Olympus's own button the "Open chat" key clicks (made when first bound)
local boundKeys              -- the keys our override binding holds now (nil: none)
local keysLater = false      -- a binding change asked in combat, made when the fight ends
local toldLater = false      -- the key pressed in combat with the tab gone: said, once a fight
local syncing = false
local DrawMatchContext       -- built below with the tab's ordinary button helper
ChatWindow.requestMinute = nil

local function Grey(s) return GREY .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
-- Locales.lua deliberately returns a missing key as the key itself.  ChatWindow can be reloaded
-- into an older running client by the offline/live developer harness, so `L.KEY or fallback`
-- would show KEY rather than the fallback until the next full game restart.  Keep this on the
-- module table because this large file is already at Lua 5.1's per-chunk local-variable limit.
function ChatWindow.Localized(key, fallback)
	local value = L[key]
	return type(value) == "string" and value ~= key and value or fallback
end
local function Dynamic(t) return type(t) == "string" and dynamicRooms[t] or nil end
function ChatWindow.Logical(t)
	local R = ns.ChatRooms
	return type(t) == "string" and type(R) == "table" and type(R.Info) == "function" and R.Info(t) or nil
end
local function Label(t)
	local r = Dynamic(t)
	if r then return r.spec.title end
	local logical = ChatWindow.Logical(t)
	if logical then return logical.label end
	local d = ns.Channels.TIERS[t]
	return d and L[d.label] or "?"
end
local function Colour(t)
	if Dynamic(t) then return ROOM_COLOUR end
	local logical = ChatWindow.Logical(t)
	if logical then
		if logical.scope == "guild" then return { 0.35, 0.82, 0.45 } end
		if logical.scope == "restricted" then return { 0.72, 0.55, 0.92 } end
		return { 0.40, 0.72, 0.95 }
	end
	local d = ns.Channels.TIERS[t]
	return d and d.color or { 1, 1, 1 }
end
local function Hex(c)
	local function B(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
	return ("ff%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
-- The game's own words for its menus (its global strings, in the player's language), else ours.
local function GameWord(value, fallback)
	return type(value) == "string" and value ~= "" and value or fallback
end

-- The channels this rank reads, in their order.
local function Readable()
	local C, out = ns.Channels, {}
	for _, t in ipairs(C.ORDER or {}) do
		if C.CanUse(t) then out[#out + 1] = t end
	end
	return out
end

-- A text's width as the client draws it on one line, and its height at a width (the client wraps
-- it there; without the height a client gives, whole lines of LINE_H).
local function TextWidth(fs)
	if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() or 0 end
	return fs:GetStringWidth() or 0
end
local function TextHeight(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return math.ceil(h) end
	end
	return math.max(1, math.ceil(TextWidth(fs) / math.max(1, width))) * LINE_H
end

local function Tip(owner, fill)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	fill(GameTooltip)
	GameTooltip:Show()
	tipOwner = owner
end
local function Untip(owner)
	if owner and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- The channel last shown, and the Olympus tab's line put away with its x: ns.db.chatWin =
-- { tier, noTabLine, dynamicPins = { ["arena:<id>"] = "<id>" } }, account-wide (the first
-- 1.1.1 build kept its window's place and size there too; the tab has neither). A dynamic pin is
-- local UI state, never an Arena or Olympus-channel message. It is restored only when the Arena
-- publishes the same canonical key/id again, and is discarded when that event is no longer
-- recoverable.
---------------------------------------------------------------------------

local function Saved()
	local p = ns.db and ns.db.chatWin
	return type(p) == "table" and p or nil
end

local function Remember(t)
	if not ns.db then return end
	local p = Saved() or {}
	if ns.Channels.TIERS[t] then
		p.tier, p.room = t, nil
	elseif ChatWindow.Logical(t) then
		p.room = t
	end
	ns.db.chatWin = p
end

local function SavedPins(make)
	local p = Saved()
	if not p and make and ns.db then p = {}; ns.db.chatWin = p end
	if not p then return nil end
	if type(p.dynamicPins) ~= "table" then
		if not make then return nil end
		p.dynamicPins = {}
	end
	return p.dynamicPins
end

local function RememberPin(r, on)
	if not r then return end
	local pins = SavedPins(on)
	if pins then
		pins[r.key] = on and r.id or nil
		if next(pins) == nil then
			local p = Saved()
			if p then p.dynamicPins = nil end
		end
	end
end

-- The Olympus tab's line, put away for good by its x (the settings and /oly chatwindow tab still
-- make the tab).
local function TabLineOff()
	local p = Saved()
	return p ~= nil and p.noTabLine == true
end
local function PutTabLineAway()
	if not ns.db then return end
	local p = Saved() or {}
	p.noTabLine = true
	ns.db.chatWin = p
end

local function MarkDirty() dirty = true end

function ChatWindow.SaveDraft()
	if not frame or not tier or not frame.input then return end
	local text = frame.input:GetText() or ""
	ChatWindow.drafts[tier] = text ~= "" and text or nil
end

function ChatWindow.LoadDraft(t)
	if not frame or not frame.input then return end
	frame.input:SetText(ChatWindow.drafts[t] or "")
end

-- The choices in the Chat page's existing switch: its three rank-gated channels, unchanged and
-- in their old order, then each dynamic room once. A room is never a Channels tier: this list is
-- presentation only, and reading/sending branches to ArenaChat below.
local function Choices()
	local out = {}
	for _, t in ipairs(Readable()) do out[#out + 1] = { key = t, tier = t } end
	for _, key in ipairs(dynamicOrder) do
		local r = dynamicRooms[key]
		if r then out[#out + 1] = { key = key, room = r } end
	end
	return out
end

local function Choice(key)
	if ns.Channels.TIERS[key] and ns.Channels.CanUse(key) then return { key = key, tier = key } end
	local R = ns.ChatRooms
	if R and type(R.PreviewOnly) == "function" and R.PreviewOnly(key) then return nil end
	if ChatWindow.Logical(key) and type(R) == "table" and type(R.IsOpen) == "function" and R.IsOpen(key) then return { key = key, logical = ChatWindow.Logical(key) } end
	local r = Dynamic(key)
	return r and { key = key, room = r } or nil
end

function ChatWindow.IsShown()
	return frame ~= nil and frame:IsShown() and host ~= nil and host:IsShown() and true or false
end
local function Shown() return ChatWindow.IsShown() end

---------------------------------------------------------------------------
-- Scrolling: it follows the newest line (on opening, on a channel picked, after the player's own
-- line, on a search typed) until the player scrolls up; lines that come meanwhile show as "N new"
-- at the bottom. The client measures the scroll range a frame after the lines change (as
-- UI.KeepPlace knows): the offset is put at the end again then, while it follows.
---------------------------------------------------------------------------

local function Quietly(fn)
	quiet = true
	local ok, err = pcall(fn)
	quiet = false
	if not ok then error(err, 0) end
end

local function ShowNew()
	if not frame then return end
	local b = frame.newPill
	if newCount > 0 and not stick and frame.scroll:IsShown() then
		b:SetText(L.CHATWIN_NEW_LINES:format(newCount))
		b:Show()
	else
		b:Hide()
	end
end

local function ToBottom()
	local s = frame.scroll
	local range = math.max(0, (frame.content:GetHeight() or 0) - (s:GetHeight() or 0))
	Quietly(function() s:SetVerticalScroll(range) end)
	lastAt = s:GetVerticalScroll() or 0
end

local function ScrollToBottom()
	stick, newCount, want = true, 0, nil
	if not frame then return end
	ToBottom()
	ShowNew()
end

-- The range measured again: at its end while the view follows; scrolled up, where the line read
-- stays in its place (Render's anchor, as far as the new range reaches).
local function Held()
	if not frame then return end
	local s = frame.scroll
	local range = s:GetVerticalScrollRange() or 0
	local to
	if stick then
		to = range
	elseif want then
		to = math.min(want, range)
	else
		return
	end
	Quietly(function() s:SetVerticalScroll(to) end)
	lastAt = s:GetVerticalScroll() or 0
end

-- The player scrolled: at the end it follows again; up from where it was, it stays where he put it.
local function Scrolled()
	if quiet or not frame then return end
	want = nil -- (his offset now, not the one a redraw worked out)
	local s = frame.scroll
	local range, at = s:GetVerticalScrollRange() or 0, s:GetVerticalScroll() or 0
	if range - at <= STICK_SLACK then
		stick, newCount = true, 0
	elseif at < lastAt - 0.5 then
		stick = false
	end
	lastAt = at
	ShowNew()
end

-- Scrolled up, the view is held by the lines it shows, not by pixels: at a channel's 100 lines
-- each new one drops the oldest (Channels' AddHistory), everything under it moves up by that
-- bubble, and an offset kept as it was would show other lines. Before a redraw: the bubbles from
-- the one at the view's top down, each with how far it sat from the view's top.
local function InView()
	local at = frame.scroll:GetVerticalScroll() or 0
	local out = {}
	for _, b in ipairs(frame.bubbles) do
		if b:IsShown() and b.entry and b.y and (#out > 0 or b.y + (b:GetHeight() or 0) > at) then
			out[#out + 1] = { entry = b.entry, delta = b.y - at }
		end
	end
	return out
end

-- After it: the first of them still drawn back where it was (the one read dropped: the next
-- one's place); none left, the top.
local function BackInView(was)
	local at = {}
	for _, b in ipairs(frame.bubbles) do
		if b:IsShown() and b.entry and b.y then at[b.entry] = b.y end
	end
	want = 0
	for _, v in ipairs(was) do
		if at[v.entry] then
			want = math.max(0, at[v.entry] - v.delta)
			break
		end
	end
	local s = frame.scroll
	Quietly(function() s:SetVerticalScroll(want) end)
	lastAt = s:GetVerticalScroll() or 0
end

---------------------------------------------------------------------------
-- A name's header: the name, a tag, the guild. No mark before the name since 1.1.5 (the author's
-- call: Olympus's marks are where players outside Olympus are, the game's own chat,
-- Borders.ChatName); the High Council's colour and the Treasurer's coin stay.
---------------------------------------------------------------------------

local function NameText(e)
	local who = ns.FullName(e.sender)
	local guild = e.guild
	local council = ns.IsHighCouncillor(who) and not ns.CouncilMasked()
	local name = ns.Codec.Plain(ns.DisplayName(e.sender) or "?")
	local lead = ns.Channels.RoleBadge and ns.Channels.RoleBadge(who) or ""
	if council then
		name = "|c" .. ns.HIGH_COUNCIL_COLOR .. name .. "|r"
	else
		local file = e.class and ns.CLASS_FILES[e.class]
		local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
		if c and c.colorStr then name = "|c" .. c.colorStr .. name .. "|r" end
	end
	-- The King's Stewards and Hands, by the rule the channels read them with (his guild's lines).
	local tag = ""
	local K = ns.King
	if ns.IsKingGuild(guild) and type(K) == "table" then
		if type(K.IsStewardName) == "function" and K.IsStewardName(who) then
			tag = " " .. Gold(L.CHATWIN_TAG_STEWARD)
		elseif type(K.IsHandName) == "function" and K.IsHandName(who) then
			tag = " " .. Gold(L.CHATWIN_TAG_HAND)
		end
	end
	return lead .. name .. tag .. " " .. Grey("<" .. ns.Codec.Plain(guild or "?") .. ">")
end

---------------------------------------------------------------------------
-- The box's parts: bubbles and grey rows, each from a pool (made once, reused on every redraw).
---------------------------------------------------------------------------

local function Content() return frame and frame.content end

local function Render() return ChatWindow.Render() end

local function InsertLink(text)
	local eb = frame and frame.input
	if not eb or not eb:IsShown() or type(text) ~= "string" then return end
	-- Olympus's own box, where its cursor is; the keyboard stays where it was.
	if eb.Insert then eb:Insert(text) else eb:SetText((eb:GetText() or "") .. text) end
end

local function LinkTip(owner, link)
	local kind = type(link) == "string" and link:match("^(%a+):")
	if not kind or not LINK_TIPS[kind] then return end
	GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
	if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		GameTooltip:Show()
		tipOwner = owner
	else
		GameTooltip:Hide()
	end
end

local function NewBubble()
	local content = Content()
	local ok, b = pcall(CreateFrame, "Frame", nil, content, "BackdropTemplate")
	if not ok or not b then b = CreateFrame("Frame", nil, content) end
	if b.SetBackdrop then
		b:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	else
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
	end
	b:EnableMouse(true)
	-- The header: the name is a button (a whisper), the time on the right.
	b.header = CreateFrame("Button", nil, b)
	b.header:SetHeight(HEADER_H)
	b.header:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -PAD)
	b.who = b.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.who:SetPoint("LEFT", b.header, "LEFT", 0, 0)
	b.who:SetJustifyH("LEFT")
	b.who:SetWordWrap(false)
	b.time = b.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("RIGHT", b.header, "RIGHT", 0, 0)
	b.header:SetScript("OnClick", function(self)
		if self.whisper then ns.SafeCall("chat tab whisper", ns.UI.WhisperWindow, self.whisper) end
	end)
	b.header:SetScript("OnEnter", function(self)
		-- (1.1.6: the moderator's button sits in the header: still shown with the cursor here.)
		ns.SafeCall("chat tab moderation", ChatWindow.HeaderEnter, b)
		if not self.whisper then return end
		Tip(self, function(tt)
			tt:AddLine(self.full or self.whisper, 1, 0.82, 0)
			tt:AddLine(L.CHATWIN_WHISPER_TIP:format(self.whisper), 0.6, 0.6, 0.6)
		end)
	end)
	b.header:SetScript("OnLeave", function(self)
		Untip(self)
		ns.SafeCall("chat tab moderation", ChatWindow.BubbleLeave, b)
	end)
	-- The line itself, whole: the player's chat font, wrapped at any width, never cut.
	b.body = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	b.body:SetJustifyH("LEFT")
	if b.body.SetJustifyV then b.body:SetJustifyV("TOP") end
	b.body:SetWordWrap(true)
	if b.body.SetNonSpaceWrap then b.body:SetNonSpaceWrap(true) end
	b.body:SetTextColor(0.95, 0.95, 0.95)
	-- Its links: a tooltip on hover, into our own box with Shift.
	if b.SetHyperlinksEnabled then b:SetHyperlinksEnabled(true) end
	b:SetScript("OnHyperlinkEnter", function(self, link) ns.SafeCall("chat tab link", LinkTip, self, link) end)
	b:SetScript("OnHyperlinkLeave", function(self) Untip(self) end)
	b:SetScript("OnHyperlinkClick", function(_, _, text)
		if IsShiftKeyDown and IsShiftKeyDown() then ns.SafeCall("chat tab link", InsertLink, text) end
	end)
	-- A line the block terms hide: a click shows it (this session). 1.1.6: a right-click opens a
	-- moderator's choices on a line he may act on (ChatWindow.ModerateLine, WatchChat.lua).
	b:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			ns.SafeCall("chat tab moderation", ChatWindow.ModerateLine, self)
			return
		end
		if self.hidden and self.entry then
			revealed[self.entry] = true
			ns.SafeCall("chat tab", Render)
		end
	end)
	-- 1.1.6: the moderator's button (WatchChat.lua), Olympus's own and a child of this bubble (the
	-- gamepad cursor reaches it here too): shown while the bubble is hovered, on a line this client
	-- may act on; and a deleted line's tooltip (when, by which role).
	b.mod = CreateFrame("Button", nil, b)
	b.mod:SetSize(14, 14)
	b.mod.icon = b.mod:CreateTexture(nil, "ARTWORK")
	b.mod.icon:SetAllPoints()
	b.mod.icon:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
	b.mod:Hide()
	b.mod:SetScript("OnClick", function() ns.SafeCall("chat tab moderation", ChatWindow.ModerateLine, b) end)
	b.mod:SetScript("OnEnter", function(self)
		Tip(self, function(tt)
			tt:AddLine(ChatWindow.Localized("WATCHCHAT_MOD_BTN", "Moderate this line"), 1, 0.82, 0)
			tt:AddLine(ChatWindow.Localized("WATCHCHAT_MOD_BTN_TIP", "Delete it, delete his recent lines, or a timeout."), 1, 1, 1, true)
		end)
	end)
	b.mod:SetScript("OnLeave", function(self)
		Untip(self)
		if not (b.IsMouseOver and b:IsMouseOver()) then self:Hide() end
	end)
	b:SetScript("OnEnter", function(self) ns.SafeCall("chat tab moderation", ChatWindow.BubbleEnter, self) end)
	b:SetScript("OnLeave", function(self) ns.SafeCall("chat tab moderation", ChatWindow.BubbleLeave, self) end)
	return b
end

-- A grey row across the box: the kept note, a day, the empty channel, no match, a line that was
-- not sent.
local function NewRow()
	local r = CreateFrame("Button", nil, Content())
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.text:SetJustifyH("CENTER")
	r.text:SetWordWrap(true)
	r:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat tab row", self.onClick) end end)
	r:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
	r:SetScript("OnLeave", function(self) Untip(self) end)
	return r
end

local function Row(i, text, y, width, onClick, tip)
	local rows = frame.rows
	local r = rows[i] or NewRow()
	rows[i] = r
	local w = math.max(40, width - 2 * EDGE)
	r.text:SetText(text)
	r.text:SetWidth(w)
	local h = TextHeight(r.text, w)
	r:SetSize(w, h)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", EDGE, -y)
	r.onClick, r.tip = onClick, tip
	r:EnableMouse(onClick ~= nil or tip ~= nil)
	r:Show()
	return h
end

local function Hint()
	if not frame then return end
	local eb = frame.input
	local empty = (eb:GetText() or "") == ""
	local focused = eb.HasFocus and eb:HasFocus() or false
	eb.hint:SetShown(empty and not focused)
end

-- A line that was not sent, back in the box (the keyboard stays where it is: no focus). Only into
-- an empty box: what the player is writing is never replaced; the note stays, and he is told.
local function PutBack(t, note)
	local eb = frame and frame.input
	if not eb or not eb:IsShown() then return end
	if Trim(eb:GetText()) ~= "" then
		ns.Print(L.CHATWIN_PUT_BACK_BUSY)
		return
	end
	local list = notes[t]
	if list then
		for i, n in ipairs(list) do
			if n == note then table.remove(list, i) break end
		end
		if #list == 0 then notes[t] = nil end
	end
	eb:SetText(note.text)
	Hint()
	Render()
end

-- A line this character wrote: sent from here (mine) under this name. The history is the realm
-- group's, shared by every character of the account (ns.rdb): a line another character of it
-- sent shows as that character's, with his name, guild and whisper, on the left.
local function Own(e)
	return e.mine and ns.Channels.IsMe(e.sender) and true or false
end

-- One line of the history in its bubble. Returns its height.
local function Bubble(i, e, start, y, maxInner, hides)
	local bubbles = frame.bubbles
	local b = bubbles[i] or NewBubble()
	bubbles[i] = b
	local mine = Own(e)
	-- A line the block terms hide: a grey bubble until a click, then its words marked (as the Realm
	-- tab's chats page marked them) and its border still grey.
	local veiled = not mine and hides ~= nil and hides(e.text or "") or false
	local hidden = veiled and not revealed[e]
	b.entry, b.hidden, b.mine, b.y = e, hidden, mine, y
	-- 1.1.6: a line a moderator deleted (WatchChat.lua): the name stays, greyed; its words are gone.
	local deleted = e.del == true and ns.WatchChat ~= nil and not ns.WatchChat.missing
	b.chat = tier
	if b.mod then b.mod:Hide() end
	local modRoom = not mine and not deleted and ChatWindow.modRoom == true
	local c = Colour(tier)
	local r, g, bl, a = 0.09, 0.09, 0.11, 0.92
	if mine then r, g, bl, a = c[1] * 0.28, c[2] * 0.28, c[3] * 0.28, 0.95 end
	if b.SetBackdropColor then
		b:SetBackdropColor(r, g, bl, a)
		if veiled then b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) else b:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
	elseif b.bg then
		b.bg:SetColorTexture(r, g, bl, a)
	end
	-- The header, at a group's start.
	local headerW, timeW = 0, 0
	if start then
		b.who:SetText(mine and L.CHATWIN_YOU or deleted and Grey(ns.Codec.Plain(ns.DisplayName(e.sender) or "?") .. " <" .. ns.Codec.Plain(e.guild or "?") .. ">")
			or NameText(e))
		b.time:SetText(Grey(date("%H:%M", tonumber(e.t) or 0)))
		timeW = math.ceil(TextWidth(b.time))
		headerW = math.ceil(TextWidth(b.who)) + 8 + timeW + (modRoom and 18 or 0) -- (room for the moderator's button, 1.1.6)
		b.header.whisper = not mine and ns.TellName(e.sender) or nil
		b.header.full = not mine and (ns.Codec.Plain(ns.DisplayName(e.sender) or "?") .. "  <" .. ns.Codec.Plain(e.guild or "?") .. ">") or nil
		b.header:EnableMouse(not mine)
		b.header:Show()
	else
		b.header.whisper, b.header.full = nil, nil
		b.header:Hide()
	end
	b.body:SetText(deleted and ns.WatchChat.DeletedBody() or hidden and Grey(L.CHATWIN_HIDDEN)
		or ((veiled and (Grey(L.FILTER_HIDDEN_MARK) .. " ") or "") .. ns.Codec.SanitizeChat(e.text)))
	local inner = math.min(maxInner, math.max(math.ceil(TextWidth(b.body)), headerW, 1))
	b.body:SetWidth(inner)
	local bodyH = TextHeight(b.body, inner)
	local top = PAD
	if start then
		b.header:SetWidth(inner)
		b.who:SetWidth(math.max(1, inner - timeW - 8 - (modRoom and 18 or 0)))
		top = top + HEADER_H + 2
	end
	-- (The moderator's button, while hovered: left of the time in a header, else the top corner.)
	if b.mod then
		b.mod:ClearAllPoints()
		if start then b.mod:SetPoint("RIGHT", b.time, "LEFT", -4, 0) else b.mod:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3) end
	end
	b.body:ClearAllPoints()
	b.body:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -top)
	local h = top + bodyH + PAD
	b:SetSize(inner + 2 * PAD, h)
	b:ClearAllPoints()
	if mine then
		b:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -EDGE, -y)
	else
		b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", EDGE, -y)
	end
	b:Show()
	return h
end

---------------------------------------------------------------------------
-- 1.1.6: moderation from a line (WatchChat.lua): the hover button and a right-click on a bubble
-- open Olympus's own dialogs (ns.ShowDialog) on a line this client may act on; a deleted line
-- shows its tooltip. Module functions: this file is at Lua's limit of locals per chunk.
---------------------------------------------------------------------------

-- WatchChat, when this client has it (a client updated without a restart has a stand-in).
function ChatWindow.Mod()
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and WC or nil
end

-- Does this client moderate anyone at all (a Watcher, the author, the King, a councillor, an
-- Olympus moderator)? The headers keep room for the button then.
function ChatWindow.ModRoom()
	local WC = ChatWindow.Mod()
	return WC ~= nil and type(WC.CanModerateAny) == "function" and WC.CanModerateAny() == true
end

-- The bubble's line, when this client may act on it: an army chat's or a ChatRooms room's (never
-- a fight room's: the seam), another player's, not deleted.
function ChatWindow.ModEntry(b)
	local WC = ChatWindow.Mod()
	if not WC or not b or b.mine or type(b.entry) ~= "table" or b.entry.del or Dynamic(b.chat) then return nil end
	if type(WC.CanModerateEntry) ~= "function" or not WC.CanModerateEntry(b.entry, b.chat) then return nil end
	return b.entry, WC
end

function ChatWindow.ModerateLine(b)
	if b and b.mod then b.mod:Hide() end
	local e, WC = ChatWindow.ModEntry(b)
	if not e then return false end
	ChatWindow.OpenSubMenu({ kind = "moderation", bubble = b, target = e, chat = b.chat }, b)
	return true
end

function ChatWindow.ModerationOptions(entry)
	local e, WC = ChatWindow.ModEntry(entry.bubble)
	if not e or e ~= entry.target or entry.bubble.chat ~= entry.chat then return {} end
	local function Action(op)
		return function()
			local current, live = ChatWindow.ModEntry(entry.bubble)
			if current ~= e or entry.bubble.chat ~= entry.chat then return end
			if op == "delete" then live.AskWhy({ name = e.sender, entry = e, chat = entry.chat }, "D")
			else live.AskName(e.sender, op) end
		end
	end
	local out = {
		{ label = L.WATCHCHAT_DELETE_LINE, onClick = Action("delete") },
		{ label = L.WATCHCHAT_TIMEOUT_BTN, onClick = Action("timeout") },
		{ label = L.WATCHCHAT_PURGE_BTN, onClick = Action("purge") },
	}
	if type(WC.TimeoutOf) == "function" and WC.TimeoutOf(e.sender) then
		out[#out + 1] = { label = L.WATCHCHAT_LIFT_BTN, onClick = Action("lift") }
	end
	return out
end

function ChatWindow.BubbleEnter(b)
	local e = b and b.entry
	local WC = ChatWindow.Mod()
	if type(e) == "table" and e.del and WC and type(WC.DeletedTip) == "function" then
		Tip(b, function(tt) WC.DeletedTip(tt, e) end)
		return
	end
	if b.mod and ChatWindow.ModEntry(b) then b.mod:Show() end
end

-- The cursor went from the bubble onto its header (the name row, where a first line's button
-- is): the game calls the bubble's OnLeave then, the header being a frame of its own; the button
-- stays while the cursor is anywhere over the bubble (its header and the button are inside it).
function ChatWindow.HeaderEnter(b)
	if b and b.mod and ChatWindow.ModEntry(b) then b.mod:Show() end
end

function ChatWindow.Over(f) return f ~= nil and f.IsMouseOver ~= nil and f:IsMouseOver() == true end
function ChatWindow.BubbleLeave(b)
	Untip(b)
	if b.mod and b.mod:IsShown() and not ChatWindow.Over(b.mod) and not ChatWindow.Over(b) then b.mod:Hide() end
end

local function ContentWidth()
	local w = frame.scroll:GetWidth()
	if not Finite(w) or w <= 0 then w = (frame:GetWidth() or 338) - 20 - (frame.barRoom or 22) end
	return math.max(100, math.floor(w))
end

-- The lines the tab's search box keeps (Views.Query: folded, as every tab's search): whose
-- writer, guild or words hold it. A line the block terms hide is found by its writer and guild
-- alone (its words are not shown).
local function Searched(list, q, hides)
	if not q then return list end
	local out = {}
	local Plain = ns.Codec.Plain
	for _, e in ipairs(list) do
		local hidden = hides ~= nil and not Own(e) and not revealed[e] and hides(e.text or "")
		-- (1.1.6: a line a moderator deleted is found by its writer and guild alone: no words left.)
		local words = not hidden and not e.del and ns.Codec.SanitizeChat(e.text) or nil
		if ns.Holds(q, ns.DisplayName(e.sender) or "?", Plain(e.guild or ""), words) then out[#out + 1] = e end
	end
	return out
end

local function Query()
	local V = ns.Views
	return V and type(V.Query) == "function" and V.Query(TAB) or nil
end

-- The block terms (Filter.lua), when this client has them.
local function Hides()
	local F = ns.Filter
	return F and not F.missing and type(F.Hides) == "function" and F.Hides or nil
end

-- The lines of `all` (the channel's history) that the block terms hide (never ours), in its order.
local function HiddenLines(all)
	local hides, out = Hides(), {}
	if not hides then return out end
	for _, e in ipairs(all) do
		if not Own(e) and not e.del and hides(e.text or "") then out[#out + 1] = e end -- (1.1.6: never a deleted line)
	end
	return out
end

-- The lines of `all`, the channel's history (Render reads it once for the strips and the lines).
local function DrawLines(all)
	local C = ns.Channels
	ChatWindow.modRoom = ChatWindow.ModRoom() -- (1.1.6: this client moderates someone: room for the button)
	local width = ContentWidth()
	frame.content:SetWidth(width)
	local hides = Hides()
	local q = Query()
	local list = Searched(all, q, hides)
	local nb, nr = 0, 0
	local y = 6
	nr = nr + 1
	y = y + Row(nr, Grey(L.CHATWIN_KEPT:format(C.HISTORY or 100)), y, width) + 6
	-- (The count of the lines the block terms hide is a strip over the lines: DrawHiddenCount.)
	if #all == 0 then
		nr = nr + 1
		y = y + 8 + Row(nr, Grey(L.CHATWIN_EMPTY:format(Label(tier))), y + 8, width)
	elseif #list == 0 then
		nr = nr + 1
		y = y + 8 + Row(nr, Grey(L.SEARCH_NO_MATCH), y + 8, width)
	end
	local maxInner = math.max(BUBBLE_MIN, math.floor(width * SHARE)) - 2 * PAD
	local prev, prevDay
	for _, e in ipairs(list) do
		local t = tonumber(e.t) or 0
		local day = date("%Y-%m-%d", t)
		local newDay = day ~= prevDay
		if newDay then
			if prev then y = y + GAP_OUT end
			nr = nr + 1
			y = y + Row(nr, Grey(day), y, width) + 4
			prevDay = day
		end
		local start = newDay or not prev or ns.FullName(prev.sender) ~= ns.FullName(e.sender)
			or Own(prev) ~= Own(e) or t - (tonumber(prev.t) or 0) > GROUP_TIME
		if prev and not newDay then y = y + (start and GAP_OUT or GAP_IN) end
		nb = nb + 1
		y = y + Bubble(nb, e, start, y, maxInner, hides)
		prev = e
	end
	-- The lines of ours that were not sent: a grey note each, a click puts one back in the box.
	local t = tier
	for _, note in ipairs(notes[t] or {}) do
		local key = WHY[note.why] or WHY.failed
		nr = nr + 1
		y = y + GAP_OUT
		y = y + Row(nr, Grey(L.CHATWIN_NOT_SENT:format(L[key]) .. " " .. L.CHATWIN_PUT_BACK), y, width, function() PutBack(t, note) end)
	end
	y = y + 8
	for i = nb + 1, #frame.bubbles do frame.bubbles[i]:Hide(); frame.bubbles[i].entry, frame.bubbles[i].y = nil, nil end
	for i = nr + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].onClick, frame.rows[i].tip = nil, nil end
	frame.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- The top row: the search box, the channels' switch right of it (a rank that reads more than
-- one channel), the gear at its end. The owner's ask: the row of pills under it (one lone
-- underlined "Olympus" for most players) took the lines' room; there is no row of its own now.
-- Then, over the lines, the pinned line, the way to the Olympus tab and the count of the lines the
-- block terms hide, each only while it shows.
---------------------------------------------------------------------------

-- The lines that came in on the channels not shown (unread[t] counts only those, CHAT_LINE).
local function OthersUnread()
	local n = 0
	for _, choice in ipairs(Choices()) do
		if choice.key ~= tier then n = n + (unread[choice.key] or 0) end
	end
	return n
end

-- The switch: the channel shown, in its colour, then "+N" for the lines new in the others, and
-- its arrow. As wide as that.
local function PaintSwitch(maxWidth)
	local b = frame.switch
	local c = Colour(tier)
	b.text:SetText(Label(tier))
	b.text:SetTextColor(c[1], c[2], c[3])
	local n = OthersUnread()
	b.count:SetText(n > 0 and ("+" .. n) or "")
	b.count:SetShown(n > 0)
	-- Event titles are not tab labels: cap the switch so a long fight name never consumes the
	-- search box. The full title is in its tooltip and menu row.
	local extra = 8 + (n > 0 and (4 + math.ceil(TextWidth(b.count))) or 0) + 4 + ARROW_W + 4
	local textW = math.max(1, math.min(190, math.ceil(TextWidth(b.text)), (maxWidth or 214) - extra))
	b.text:SetWidth(textW)
	local w = textW + extra
	b:SetSize(w, SEARCH_H)
end

-- A channel in the switch's list: its colour for the one shown, grey for the others (white under
-- the mouse), and the lines new in it.
local function PaintChoice(r)
	local key = r.choiceKey
	local c = Colour(key)
	local n = unread[key] or 0
	r.text:SetText(Label(key) .. (n > 0 and (" (" .. n .. ")") or ""))
	if key == tier then
		r.text:SetTextColor(c[1], c[2], c[3])
		r.mark:SetColorTexture(c[1], c[2], c[3], 1)
		r.mark:Show()
	else
		local v = r.hover and 1 or 0.6
		r.text:SetTextColor(v, v, v)
		r.mark:Hide()
	end
end

-- The switch's list, under it on its right: the channels this rank reads, in their order.
local function PaintMenu()
	local m = frame.menu
	local y, w = -MENU_PAD, 0
	local shown = {}
	for _, choice in ipairs(Choices()) do
		local key = choice.key
		local r = m.rows[key] or m:AddChoice(key)
		shown[key] = true
		PaintChoice(r)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", m, "TOPLEFT", MENU_PAD, y)
		r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -MENU_PAD, y)
		r:SetHeight(MENU_ROW)
		y = y - MENU_ROW
		w = math.max(w, math.ceil(TextWidth(r.text)))
		r:Show()
	end
	for key, r in pairs(m.rows) do if not shown[key] then r:Hide() end end
	m:SetSize(math.max(frame.switch:GetWidth(), w + 2 * MENU_PAD + 20), -y + MENU_PAD)
	m:ClearAllPoints()
	m:SetPoint("TOPRIGHT", frame.switch, "BOTTOMRIGHT", 0, -2)
end

local function CloseMenu()
	if not frame then return end
	frame.menu:Hide()
	frame.catcher:Hide()
end

local function ToggleMenu()
	if frame.menu:IsShown() then return CloseMenu() end
	PaintMenu()
	frame.catcher:Show()
	frame.menu:Show()
end

-- The gear's look: lit while the settings show.
local function PaintGear()
	local g = frame.gear
	if settings then g:LockHighlight() else g:UnlockHighlight() end
end

function ChatWindow.SubtabEntries()
	local out = { { kind = "global", label = L.CHATROOM_GLOBAL or "Olympus" } }
	local R = ns.ChatRooms
	local arena = { kind = "arena", label = ChatWindow.Localized("ARENA_CHAT_TAB", "Arena"), dropdown = true,
		tip = ChatWindow.Localized("ARENA_CHAT_TAB_TIP", "Fight, event and matched-duel chats you opened or pinned.") }
	local inserted = false
	if type(R) == "table" and type(R.Tabs) == "function" then
		for _, e in ipairs(R.Tabs()) do
			out[#out + 1] = e
			if e.kind == "class" then out[#out + 1], inserted = arena, true end
		end
	end
	if not inserted then out[#out + 1] = arena end
	return out
end

function ChatWindow.OpenArenaFromChat()
	local H = ns.ArenaHome
	if type(H) ~= "table" or type(H.Open) ~= "function" then return false end
	return H.Open("events") ~= false
end

-- The Arena subtab indexes only rooms this client already admitted through the canonical Arena
-- contracts. It discovers no events, participants or stakes of its own. Pinned rooms come first,
-- then active and most recently used retained rooms; the list stays bounded to the menu's rows.
function ChatWindow.ArenaOptions(includeEmpty)
	if ChatWindow.PruneDynamicRooms then ChatWindow.PruneDynamicRooms() end
	local rooms = ChatWindow.DynamicRooms and ChatWindow.DynamicRooms() or {}
	table.sort(rooms, function(a, b)
		local ap, bp = a.pinned and 1 or 0, b.pinned and 1 or 0
		if ap ~= bp then return ap > bp end
		local aa, ba = a.spec and a.spec.active and 1 or 0, b.spec and b.spec.active and 1 or 0
		if aa ~= ba then return aa > ba end
		if (a.used or 0) ~= (b.used or 0) then return (a.used or 0) > (b.used or 0) end
		return tostring(a.key) < tostring(b.key)
	end)
	local out, cap = {}, 10
	local shown = math.min(#rooms, #rooms > cap and cap - 1 or cap)
	for i = 1, shown do
		local room = rooms[i]
		local title = room.spec and room.spec.title or room.id or "?"
		if room.pinned then title = ChatWindow.Localized("ARENA_CHAT_MENU_PINNED", "Pinned: %s"):format(title)
		elseif room.spec and room.spec.active then title = ChatWindow.Localized("ARENA_CHAT_MENU_ACTIVE", "Live: %s"):format(title) end
		out[#out + 1] = { id = room.key, label = title, dynamic = true }
	end
	if #rooms > cap then
		out[#out + 1] = { label = ChatWindow.Localized("ARENA_CHAT_MENU_MORE", "More fights - open the Arena"), onClick = ChatWindow.OpenArenaFromChat }
	elseif #out == 0 and includeEmpty then
		out[1] = { label = ChatWindow.Localized("ARENA_CHAT_MENU_EMPTY", "No fight chat open - open the Arena"), onClick = ChatWindow.OpenArenaFromChat }
	end
	return out
end

function ChatWindow.CloseSubMenu()
	if not frame or not frame.subMenu then return end
	frame.subMenu:Hide()
	frame.subCatcher:Hide()
	frame.subEntry, frame.subSignature = nil, nil
end

function ChatWindow.SubMenuOptions(entry)
	if entry.kind == "moderation" then return ChatWindow.ModerationOptions(entry) end
	local R = ns.ChatRooms
	return entry.kind == "arena" and ChatWindow.ArenaOptions(true)
		or (type(R) == "table" and type(R.Options) == "function" and R.Options(entry.kind) or {})
end
function ChatWindow.SubMenuSignature(entry, options)
	local V = ns.ViewAs
	local out = { entry.kind, tostring(V and V.Previewing and V.Previewing() and V.Role and V.Role() or false) }
	for _, option in ipairs(options) do
		out[#out + 1] = table.concat({ tostring(option.id), tostring(option.label), tostring(option.disabled), tostring(option.dynamic) }, "\031")
	end
	return table.concat(out, "\030")
end

-- A destination as the shared strip draws it (Views.DrawNav): its words and unread count, lit
-- while it is the one shown, a picker's arrow (Race, Class, Arena: a list of rooms opens from it).
function ChatWindow.SubtabItem(entry)
	local logical = ChatWindow.Logical(tier)
	local selected = entry.kind == "global" and ns.Channels.TIERS[tier] ~= nil
		or entry.kind == "arena" and Dynamic(tier) ~= nil
		or entry.kind == "role" and logical ~= nil and logical.scope == "restricted"
		or logical ~= nil and (entry.id == tier or entry.kind == logical.kind)
	local n = 0
	if entry.kind == "global" then
		for _, choice in ipairs(Choices()) do n = n + (unread[choice.key] or 0) end
	elseif entry.id then
		n = unread[entry.id] or 0
	else
		local R = ns.ChatRooms
		local options = entry.kind == "arena" and ChatWindow.ArenaOptions(false)
			or (type(R) == "table" and type(R.Options) == "function" and R.Options(entry.kind) or {})
		for _, option in ipairs(options) do
			if not option.disabled then n = n + (unread[option.id] or 0) end
		end
	end
	return {
		entry = entry, selected = selected == true, picker = entry.dropdown == true,
		text = entry.label .. (n > 0 and (" (" .. n .. ")") or ""),
		onClick = function(button) ChatWindow.ClickSubtab(entry, button) end,
		tooltip = entry.dropdown and function(tt)
			tt:AddLine(entry.label, 1, 0.82, 0)
			tt:AddLine(entry.tip or L.CHATROOM_DROPDOWN_TIP or "Choose a topic room.", 1, 1, 1, true)
		end or nil,
	}
end

-- A destination clicked: Olympus (the army chat last shown), a picker's list of rooms (from its
-- button), or the room itself.
function ChatWindow.ClickSubtab(entry, button)
	if entry.kind == "global" then
		ChatWindow.CloseSubMenu()
		local want = ChatWindow.globalTier
		if not want or not ns.Channels.CanUse(want) then want = Readable()[1] end
		if want then ns.SafeCall("chat subtab", ChatWindow.SelectLegacy, want) end
	elseif entry.dropdown then
		ns.SafeCall("chat subtab menu", ChatWindow.OpenSubMenu, entry, button)
	elseif entry.id then
		ns.SafeCall("chat subtab", ChatWindow.SelectLogical, entry.id)
	end
end

function ChatWindow.OpenSubMenu(entry, owner)
	if not frame then return end
	local options = ChatWindow.SubMenuOptions(entry)
	if #options == 0 then return end
	CloseMenu()
	local menu, y, width = frame.subMenu, -MENU_PAD, 80
	for i, option in ipairs(options) do
		local row = menu.rows[i]
		row.roomId, row.dynamic, row.onClick, row.previewOnly = option.id, option.dynamic == true, option.onClick, option.disabled == true
		row.text:SetText(option.label)
		row.mark:SetShown(tier == option.id)
		row.text:SetTextColor(tier == option.id and 1 or 0.82, tier == option.id and 0.82 or 0.82, tier == option.id and 0 or 0.82)
		row:SetAlpha(row.previewOnly and 0.5 or 1)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD, y)
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MENU_PAD, y)
		row:SetHeight(MENU_ROW)
		row:Show()
		y = y - MENU_ROW
		width = math.max(width, math.ceil(TextWidth(row.text)) + 22)
	end
	for i = #options + 1, #menu.rows do
		menu.rows[i].roomId, menu.rows[i].dynamic, menu.rows[i].onClick = nil, nil, nil
		menu.rows[i]:Hide()
	end
	local menuWidth = math.min(width + MENU_PAD * 2, math.max(80, frame:GetWidth() - 24))
	menu:SetSize(menuWidth, -y + MENU_PAD)
	for i = 1, #options do
		menu.rows[i].text:SetWidth(math.max(1, menuWidth - MENU_PAD * 2 - 22))
		menu.rows[i].text:SetWordWrap(false)
	end
	menu:ClearAllPoints()
	if entry.kind == "moderation" then
		menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	else
	local top = owner:GetBottom() - frame:GetTop() - 2
	if entry.kind == "race" or entry.kind == "class" then
		-- These lists open under the destination clicked, moving left only as far as needed
		-- to keep long labels inside the pane. Arena and role menus keep their existing placement.
		local left = math.max(12, math.min(owner:GetLeft() - frame:GetLeft(), frame:GetWidth() - menuWidth - 12))
		menu:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
	else
		menu:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, top)
	end
	end
	frame.subCatcher:Show()
	frame.subEntry, frame.subSignature = entry, ChatWindow.SubMenuSignature(entry, options)
	menu:Show()
end

-- The destinations, drawn by the Realm's own in-page tabs (Views.DrawNav) where the Realm draws
-- its list's first row: in the list's box, at the list's left and as wide as its rows (UI.lua's
-- places.nav, the list's numbers). They stay there whatever shows under them (the review of
-- test33: anchored to a box that the strips over the lines pushed down, they moved under the
-- pointer from one destination to the next, the pinned line showing on Olympus and not on Guild;
-- the Realm's tabs never move): the box stays where the list's box is, and the strips (the pinned
-- line, the Olympus tab's line, a topic's status, a match's card, the hidden lines' count) and the
-- lines start under the tabs, in that box (ChatWindow.PlaceLines). Hidden with the settings.
-- Returns where the room under them starts, from the window's top (the box's top without them).
function ChatWindow.DrawSubtabs(show)
	local bar = frame and frame.subtabs
	if not bar then return frame and frame.places.box.top or 0 end
	local V, box, nav = ns.Views, frame.places.box, frame.places.nav
	if show and nav and type(V) == "table" and type(V.DrawNav) == "function" then
		local items = {}
		for _, entry in ipairs(ChatWindow.SubtabEntries()) do items[#items + 1] = ChatWindow.SubtabItem(entry) end
		local width = math.max(1, (frame:GetWidth() or 338) - nav.left + nav.right)
		local h = V.DrawNav(bar, items, width)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", frame.box, "TOPLEFT", nav.left - box.left, nav.top - box.top)
		bar:SetSize(width, h)
		bar:Show()
		return nav.top - h
	end
	bar:Hide()
	ChatWindow.CloseSubMenu()
	return box.top
end

-- The lines, and the chats-off page, from `y` (from the window's top) down, in the box: under the
-- tabs and the strips over the lines (Draw).
function ChatWindow.PlaceLines(y)
	local top = y - frame.places.box.top
	frame.scroll:SetPoint("TOPLEFT", frame.box, "TOPLEFT", 4, math.min(-4, top))
	frame.off:SetPoint("TOPLEFT", frame.box, "TOPLEFT", 0, top)
end

-- The box to write in, across the bottom row; 1.1.2: the Answers button (the author, the High
-- Council and the Stewards) at that row's end while it shows, the box ending before it. Never on
-- the top row (1.1.2's review: next to the switch, the search box there shrank to nothing for a
-- Lord of the High Council in the default window), and by the box it fills.
local function PlaceInput(p)
	local input = p.places and p.places.input
	if not input then return end
	local room = 0
	if p.answers and p.answers:IsShown() then
		p.answers:ClearAllPoints()
		p.answers:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", input.right, input.y + math.floor((input.h - SEARCH_H) / 2))
		room = p.answers:GetWidth() + TOP_GAP
	end
	-- (The box's border art reaches 10 past its ends.)
	p.input:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", input.right - 10 - room, input.y)
end

-- The row: the gear at its end; the switch left of it while the lines show and the rank reads more
-- than one channel (never a row of its own; one channel, nothing); the search box in the rest.
-- The settings: their title there instead.
local function DrawTop(choices, on)
	local s = frame.places.search
	if settings then s = { left = s.left, right = s.right, top = -30 } end
	local lines = on and not settings
	local room = Dynamic(tier)
	local right = s.right
	if room then
		frame.gear:Hide()
		frame.roomPin:ClearAllPoints()
		frame.roomPin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, s.top)
		frame.roomPin.pinned = room.pinned and true or false
		frame.roomPin.label:SetText(room.pinned and "P" or "p")
		frame.roomPin:Show()
		right = right - ROOM_BUTTON_W - TOP_GAP
		frame.roomClose:SetShown(not room.pinned)
		if not room.pinned then
			frame.roomClose:ClearAllPoints()
			frame.roomClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, s.top)
			right = right - ROOM_BUTTON_W - TOP_GAP
		end
	else
		frame.roomPin:Hide()
		frame.roomClose:Hide()
		frame.gear:ClearAllPoints()
		frame.gear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", s.right, s.top)
		frame.gear:Show()
		PaintGear()
		right = s.right - GEAR_W - TOP_GAP
	end
	-- 1.1.5: no "?" of the tab's own on this row (1.1.2 had one left of the gear, the owner's ask: it
	-- doubled the window's help "i" just above it, left of the X). The Answers of the author, the
	-- High Council and the Stewards: at the end of the box they fill, while the lines and that box
	-- show (PlaceInput).
	local A = ns.Answers
	frame.answers:SetShown(not room and lines and A ~= nil and type(A.Allowed) == "function" and A.Allowed() == true)
	PlaceInput(frame)
	local sw = frame.switch
	if lines and (ns.Channels.TIERS[tier] or Dynamic(tier)) and #choices > 1 then
		local searchLeft = s.left + math.ceil(TextWidth(frame.searchLabel)) + 12
		PaintSwitch(frame:GetWidth() + right - searchLeft - TOP_GAP - 60)
		sw:ClearAllPoints()
		sw:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, s.top)
		sw:Show()
		right = right - sw:GetWidth() - TOP_GAP
		if frame.menu:IsShown() then PaintMenu() end
	else
		sw:Hide()
		CloseMenu()
	end
	local lw = math.ceil(TextWidth(frame.searchLabel))
	frame.searchLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", s.left, s.top - 4)
	frame.setTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", s.left, s.top - 3)
	frame.search:ClearAllPoints()
	frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", s.left + lw + 12, s.top)
	frame.search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, s.top)
	frame.search:SetShown(lines)
	frame.searchLabel:SetShown(lines)
	frame.setTitle:SetShown(not room and settings)
	frame.navBottom = ChatWindow.DrawSubtabs(not settings)
	frame.underTabs = settings and frame.navBottom or math.min(frame.navBottom - 4, s.top - SEARCH_H - 4)
end

-- The room between the box's sides (a strip over it: the pinned line, the Olympus tab's line, the
-- count of the hidden lines).
local function StripWidth()
	local box = frame.places.box
	return math.max(100, (frame:GetWidth() or 338) - box.left + box.right - 12)
end

local function Strip(s, y)
	local box = frame.places.box
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left + 6, y - 3)
	s:SetPoint("TOPRIGHT", frame, "TOPRIGHT", box.right - 6, y - 3)
end

-- Race/class outsiders keep this warning in sight, not only in the send popup. It also states
-- which of the two independent gates (30 minutes and a member reply) is still closed.
function ChatWindow.DrawTopicStatus(y)
	local R = ns.ChatRooms
	local logical = ChatWindow.Logical(tier)
	local s = frame.topicStatus
	local text = logical and logical.scope == "topic" and type(R) == "table" and type(R.StatusText) == "function" and R.StatusText(tier) or nil
	if not text then s:Hide(); return 0 end
	s.text:SetText(Gold(text))
	local width = StripWidth()
	s.text:SetWidth(width)
	local h = math.min(TextHeight(s.text, width), 3 * LINE_H)
	s:SetHeight(h)
	Strip(s, y)
	s:Show()
	return h + 6
end

-- The strip over the lines while this character is in a timeout: until when, by which role.
function ChatWindow.DrawModStatus(y)
	local s = frame.modStatus
	if not s then return 0 end
	local WC = ChatWindow.Mod()
	local text = WC and type(WC.StripText) == "function" and WC.StripText() or nil
	if not text then s:Hide(); return 0 end
	s.text:SetText("|cffff6060" .. text .. "|r")
	local width = StripWidth()
	s.text:SetWidth(width)
	local h = math.min(TextHeight(s.text, width), 2 * LINE_H)
	s:SetHeight(h)
	Strip(s, y)
	s:Show()
	return h + 6
end

-- The pinned line (Channels.Pin), as the Realm tab shows it (Views.PinLine): its words veiled
-- until a click when the block terms hide them; a click takes it down when allowed. Over the
-- lines' top, at `y`. Returns the room it takes (none without a pin).
local function DrawPin(y)
	local C = ns.Channels
	local pin = frame.pin
	local p = C.Pin and C.Pin()
	if not p then
		pin.onClick, pin.tip = nil, nil
		pin:Hide()
		return 0
	end
	local who = ns.Codec.Plain(ns.DisplayName(p.sender) or "?")
	local mayTakeDown = C.CanTakeDown and C.CanTakeDown()
	local words, veiled = C.PinWords(p)
	pin.onClick = mayTakeDown and function() ns.ShowDialog("OLYMPUS_PIN_DOWN") end or nil
	if veiled then
		pin.onClick = function()
			p.revealed = true
			Render()
		end
	end
	pin.tip = function(tt)
		tt:AddLine(L.PIN_LABEL, 1, 0.82, 0)
		tt:AddLine(words, 1, 1, 1, true)
		local left = math.max(1, math.ceil(((tonumber(p.expires) or ns.Now()) - ns.Now()) / 60))
		tt:AddLine(L.PIN_TIP:format(who, ns.Codec.Plain(p.guild or "?"), ns.Ago(p.setAt), left), 0.7, 0.7, 0.7, true)
		if mayTakeDown and not veiled then tt:AddLine(L.PIN_DOWN_TIP, 0.25, 1, 0.25, true) end
	end
	pin.text:SetText(Gold(L.CHATWIN_PINNED .. ": ") .. (veiled and Grey(L.FILTER_WORDS_HIDDEN) or ("|cffffffff" .. words .. "|r"))
		.. "  " .. Grey(who))
	local width = StripWidth()
	pin.text:SetWidth(width)
	local h = math.min(TextHeight(pin.text, width), PIN_LINES * LINE_H)
	pin:SetHeight(h)
	Strip(pin, y)
	pin:Show()
	return h + 6
end

-- The lines the block terms hide in this channel, counted (as the Realm tab's chats page counted
-- them): a click shows them all, marked, another hides them again (each hidden one is a grey
-- bubble, shown alone by its own click too). A strip over the lines, at `y` (the review of the
-- page's removal: a row atop the scrolled lines sat above the oldest line, out of sight, the tab
-- opening on the newest). `all`: the channel's history. Returns the room it takes (none while no
-- line is hidden).
local function DrawHiddenCount(y, all)
	local s = frame.hiddenCount
	local hidden = HiddenLines(all)
	if #hidden == 0 then
		s.onClick = nil
		s:Hide()
		return 0
	end
	local shown = true
	for _, e in ipairs(hidden) do shown = shown and revealed[e] == true end
	s.onClick = function()
		for _, e in ipairs(hidden) do revealed[e] = not shown or nil end
		Render()
	end
	s.text:SetText(Grey((shown and L.FILTER_SHOWING_LINES or L.FILTER_HIDDEN_LINES):format(#hidden)))
	local width = StripWidth()
	s.text:SetWidth(width)
	local h = math.min(TextHeight(s.text, width), COUNT_LINES * LINE_H)
	s:SetHeight(h)
	Strip(s, y)
	s:Show()
	return h + 6
end

---------------------------------------------------------------------------
-- The Olympus tab of the game's chat, by the player's own hand (1.1.1, the author's ask: a button
-- for it). Olympus cannot make a chat window: the game's code for one (FCF_OpenNewWindow, and the
-- NAME_CHAT popup FCF_NewChatWindow shows) writes the chat's own tables and its last active box
-- from whoever runs it, and run from an addon it taints the chat box (/cast, /target, /use and
-- /click typed there get blocked; with the gamepad UI the game froze). So the line on the Chat
-- tab only shows the player where: Olympus's own small pointer, anchored by the game's main chat
-- tab (ours anchored to theirs; theirs only read), says right-click it, Create New Window, name
-- it Olympus. Then Olympus reads the game's chat windows (Channels.FindTab: GetChatWindowInfo and
-- the frames' own fields) when the game says they changed (UPDATE_CHAT_WINDOWS,
-- UPDATE_FLOATING_CHAT_WINDOWS: FloatingChatFrame.lua and ChatFrameOverrides.lua register them)
-- and every LOOK_GAP while the pointer or the tab shows; the moment a window named Olympus is
-- there it runs Channels.SetupTab (the chats go there, and it says so once) and the pointer goes.
-- With the gamepad UI the game's chat tabs work otherwise: no pointer, the steps as text. With
-- Chattynator (1.1.2) its tabs are the chat and the game's are hidden behind them (the pointer
-- would point at nothing): no pointer, the click runs Channels.SetupTab at once, which says in
-- chat how to make the tab in Chattynator and sends the channels there the moment it exists
-- (nothing tells Olympus when a tab of Chattynator's is made: the Chat tab reads its tabs every
-- LOOK_GAP while it shows, to say it once).
---------------------------------------------------------------------------

local function TabReady()
	local C = ns.Channels
	return not C.missing and type(C.SetupTab) == "function" and type(C.TabState) == "function" and type(C.FindTab) == "function"
end

-- Whether Chattynator's tabs are the chat windows now (Channels.Chattynator, 1.1.2).
local function Chatty()
	local C = ns.Channels
	return type(C.Chattynator) == "function" and C.Chattynator() and true or false
end

local function MainTabWord()
	local C = ns.Channels
	return type(C.MainTabName) == "function" and C.MainTabName() or L.CHATTAB_MAIN_TAB
end

-- The steps to the Olympus tab while it is awaited, for the line over the lines and the settings.
local function TabSteps()
	if Chatty() then return L.CHATTY_TAB_STEPS end
	return L.CHATS_TAB_STEPS:format(MainTabWord(), GameWord(NEW_CHAT_WINDOW, L.CHATWIN_NEW))
end

-- The game's main chat tab (its frame's name and "Tab": ChatFrame1Tab, FloatingChatFrame.xml),
-- when it shows. Read only.
local function MainChatTab() -- gp:lookups
	local f = DEFAULT_CHAT_FRAME
	local name = type(f) == "table" and type(f.GetName) == "function" and f:GetName() or nil
	local tab = type(name) == "string" and _G[name .. "Tab"] or nil
	if type(tab) ~= "table" then tab = _G.ChatFrame1Tab end
	if type(tab) == "table" and type(tab.IsVisible) == "function" and tab:IsVisible() then return tab end
	return nil
end

local function StopWatching()
	watching, lookAcc, sent = false, 0, false
	if pointer then pointer:Hide() end
end

-- The game's chat windows read: a window named Olympus there, the chats go to it (SetupTab, once).
-- With Chattynator (1.1.2) the click sent them there already (AddTab): the tab there, it is said
-- once (Channels.TabArrived: not when a line got there first, its intro saying it), and nothing is
-- chosen again. (The review of 1.1.2: SetupTab again, when the Chat tab next showed, undid a
-- channel the player had moved since, and said the tab's intro and filter hint a second time.)
local function Look()
	if not watching then return false end
	if not TabReady() then
		StopWatching()
		return false
	end
	local C = ns.Channels
	if not C.FindTab() then return false end
	-- (Awaited from the line's click: chosen or not before, it is set up now, and said once.)
	local already = sent
	StopWatching()
	if already and type(C.TabArrived) == "function" then C.TabArrived() else C.SetupTab() end
	MarkDirty()
	if ns.UI and type(ns.UI.RefreshSoon) == "function" then ns.UI.RefreshSoon() end
	return true
end

local function MakePointer()
	local name = "OlympusChatTabPointer"
	local ok, p = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
	if not ok or not p then p = CreateFrame("Frame", name, UIParent) end
	p:Hide()
	if p.SetBackdrop then
		p:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		if p.SetBackdropColor then p:SetBackdropColor(0.05, 0.05, 0.06, 0.95) end
		if p.SetBackdropBorderColor then p:SetBackdropBorderColor(1, 0.82, 0, 1) end
	else
		local bg = p:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
	end
	p:SetFrameStrata("DIALOG")
	p:SetClampedToScreen(true)
	p:SetSize(240, 76)
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -9)
	p.title:SetText(L.CHATTAB_POINTER_TITLE)
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.text:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -27)
	p.text:SetWidth(220)
	p.text:SetJustifyH("LEFT")
	p.text:SetWordWrap(true)
	-- The arrow under it, down onto the tab.
	p.arrow = p:CreateTexture(nil, "OVERLAY")
	p.arrow:SetSize(32, 32)
	p.arrow:SetPoint("TOP", p, "BOTTOMLEFT", 26, 2)
	local atlas = C_Texture and C_Texture.GetAtlasInfo
	local okAtlas, info = false, nil
	if type(atlas) == "function" and type(p.arrow.SetAtlas) == "function" then okAtlas, info = pcall(atlas, ARROW_ATLAS) end
	if okAtlas and info ~= nil then p.arrow:SetAtlas(ARROW_ATLAS) else p.arrow:SetTexture(ARROW_FILE) end
	-- Its X: the pointer goes (the game's chat windows are still read when the game says they
	-- changed, and while the Chat tab shows).
	local okClose, close = pcall(CreateFrame, "Button", nil, p, "UIPanelCloseButton")
	if okClose and close then
		close:SetPoint("TOPRIGHT", p, "TOPRIGHT", 2, 2)
		close:SetScript("OnClick", function() p:Hide() end)
		p.CloseButton = close
	end
	p:SetScript("OnUpdate", function(_, elapsed)
		lookAcc = lookAcc + (tonumber(elapsed) or 0)
		if lookAcc < LOOK_GAP then return end
		lookAcc = 0
		ns.SafeCall("olympus tab", Look)
	end)
	ns.EscapeCloses(name)
	p:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	pointer = p
	return p
end

-- By the game's main chat tab (the screen's bottom left where it does not show). Never with the
-- gamepad UI, nor with Chattynator (AddTab, StepsAgain).
local function ShowPointer()
	if ns.GamepadUI() then return nil end
	local p = pointer or MakePointer()
	p.text:SetText(L.CHATTAB_POINTER:format(GameWord(NEW_CHAT_WINDOW, L.CHATWIN_NEW)))
	p:SetHeight(math.max(76, 36 + TextHeight(p.text, 220)))
	p:ClearAllPoints()
	local tab = MainChatTab()
	if tab then
		p:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", 0, 34)
	else
		p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 260)
	end
	lookAcc = 0
	p:Show()
	return p
end

-- The Chat tab's line (the player's click): a tab named Olympus there already, the chats go to
-- it at once; else the pointer shows and the game's chat windows are read until it is there.
-- With Chattynator (1.1.2), no pointer (the game's tabs are hidden behind Chattynator's, and
-- ChatFrame1Tab is said shown there: the pointer would point at nothing; one shown before
-- Chattynator answered goes): the channels go to its tab named Olympus now, the lines landing there
-- the moment it exists, and chat says how to make it (Channels.SetupTab).
-- Returns true when the chats went to it, false when it is awaited, nil when there is no way.
function ChatWindow.AddTab()
	if not TabReady() then return nil end
	local C = ns.Channels
	if C.TabState() == "open" then
		MarkDirty()
		return true
	end
	watching, lookAcc, sent = true, 0, false
	if Look() then return true end
	if Chatty() then
		if pointer then pointer:Hide() end
		C.SetupTab()
		sent = true
	else
		ShowPointer()
	end
	MarkDirty()
	return false
end

-- A click on the steps while the tab is awaited: the pointer again; with Chattynator, the steps
-- said again in chat (AddTab).
local function StepsAgain()
	if Chatty() then ChatWindow.AddTab() else ShowPointer() end
end
function ChatWindow.Watching() return watching end
function ChatWindow.Pointer() return pointer end -- (tests)

-- (And drawn again: the settings name each channel's window, "gone" while it is not open, and the
-- Olympus tab's state; the line over the lines follows that state too. The review of the page's
-- removal: a window closed or opened while they showed left them stale.)
for _, event in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
	ns.RegisterEvent(event, function()
		if watching then Look() end
		MarkDirty()
	end)
end

-- Whether the line shows, the Olympus tab not open (the review of the Chat tab: it showed for
-- anyone without an open Olympus tab, and nothing put it away). Awaited (the player's click):
-- always, with the steps. Put away with its x: no more. Chosen and not there ("waiting"): yes.
-- Else only while no channel of this character goes to a window of his choosing: a player who
-- sent them to another window (a tab named otherwise, to keep the channel's name there) chose.
local function GuideWanted()
	if watching then return true end
	if TabLineOff() then return false end
	local C = ns.Channels
	if C.TabState() == "waiting" then return true end
	if type(C.ChosenWindow) == "function" then
		for _, t in ipairs(C.ORDER) do
			if C.ChosenWindow(t) then return false end
		end
	end
	return true
end

-- The line over the lines while the Olympus tab is not there: a click adds it (above); awaited,
-- the steps; its x puts it away. Returns the room it takes (none while it does not show).
local function DrawGuide(y)
	local g = frame.guide
	local C = ns.Channels
	if not TabReady() or not C.ChatOn() or C.TabState() == "open" or not GuideWanted() then
		g:Hide()
		return 0
	end
	local text
	if watching then
		text = Grey(TabSteps())
	else
		text = Green("+ " .. L.CHATS_TAB_ADD)
	end
	g.text:SetText(text)
	local width = StripWidth() - GUIDE_X -- (clear of its x)
	g.text:SetWidth(width)
	local h = math.min(TextHeight(g.text, width), GUIDE_LINES * LINE_H)
	g:SetHeight(h)
	Strip(g, y)
	g:Show()
	return h + 6
end

---------------------------------------------------------------------------
-- The settings (the gear at the top row's end, in place of the lines; its click again, or the
-- first line, goes back). What the Realm tab's "Olympus chats" page offered and the lines do not,
-- the page gone (the author's call): the chats on or off on this client and what that means (the
-- first-open page's choice, Consent.lua), whether the channel is public (Views.PublicLines), the
-- Olympus tab of the game's chat (the guided way above), and the pinned line for whoever may pin;
-- and each channel in the game's chat (muted there or not, /oly mute; and the chat window it goes
-- to, as /oly chatwindow picks it). Every change goes through the code its command runs (and says
-- so in chat as that command does): the game's chat windows are only read here, never made,
-- named or set up. ChatWindow.SettingsLines gives the lines (text, onClick, tip, header, indent,
-- gap), as the tests read them.
---------------------------------------------------------------------------

local function MutedInChat(t)
	return ns.db ~= nil and type(ns.db.chatMute) == "table" and ns.db.chatMute[t] and true or false
end

-- The window of the game's chat a channel goes to, as /oly chatwindow and /oly status say it: the
-- main one, else the window chosen, "(gone: ...)" while it is not open.
local function WhereText(t)
	local C = ns.Channels
	local name = type(C.ChosenWindow) == "function" and C.ChosenWindow(t) or nil
	if not name then return L.CHATWIN_MAIN_NAME end
	local there
	if type(C.IsTabName) == "function" and C.IsTabName(name) and type(C.FindTab) == "function" then there = C.FindTab() end
	if not there and type(C.FindWindow) == "function" then there = C.FindWindow(name) end
	return '"' .. ns.Codec.Plain(name) .. '"' .. (there and "" or " " .. L.CHATWIN_GONE_TAG)
end

-- A click on a channel's window: the next one open in the game's chat after the one it goes to
-- (the main one, then the others in their order, then the main one again), through
-- /oly chatwindow's own code (Channels.ChooseWindow, by the window's number). With Chattynator
-- (1.1.2), its tabs in their order, each by its name (Channels.ChooseTab: a tab called "main" or
-- "2" would read otherwise in /oly chatwindow's words).
local function NextWindow(t)
	local C = ns.Channels
	if type(C.OpenWindows) ~= "function" or type(C.ChooseWindow) ~= "function" then return end
	-- One window for each name (the first of it): the choice is a name, and a name picks the first
	-- window of it, so a second one could never be passed (the review of 1.1.2: Chattynator names
	-- each new tab "New tab", and two of them kept the click there, on and on).
	local list, seen = {}, {}
	for _, w in ipairs(C.OpenWindows()) do
		local key = Trim(w.name):lower()
		local rawKey = type(w.raw) == "string" and Trim(w.raw):lower() or key
		if not seen[key] and not seen[rawKey] then list[#list + 1] = w end
		seen[key], seen[rawKey] = true, true
	end
	local current = type(C.ChosenWindow) == "function" and C.ChosenWindow(t) or nil
	local at = 0 -- (the main window)
	if current then
		local key = Trim(current):lower()
		for i, w in ipairs(list) do
			local named = Trim(w.name):lower() == key or (type(w.raw) == "string" and Trim(w.raw):lower() == key)
			if named and at == 0 then at = i end
		end
	end
	local word = C.TIERS[t].word
	local nxt = list[at + 1]
	if not nxt then
		C.ChooseWindow("main " .. word)
	elseif nxt.index then
		C.ChooseWindow(nxt.index .. " " .. word)
	elseif type(C.ChooseTab) == "function" then
		C.ChooseTab(nxt.name, t)
	end
end

function ChatWindow.SettingsLines()
	local C = ns.Channels
	local out = {}
	local function Add(l) out[#out + 1] = l end
	local newWindow = GameWord(NEW_CHAT_WINDOW, L.CHATWIN_NEW)
	Add({ text = Gold(L.CHATSET_BACK), onClick = function() ChatWindow.ShowSettings(false) end, gap = true })
	-- The chats on this client, and what the choice means.
	local on = C.ChatOn()
	Add({ header = true, text = Gold(L.CONSENT_CHAT) })
	Add({ indent = true, text = on and Green(L.CHATSET_CHATS_ON) or Grey(L.CHATSET_CHATS_OFF),
		onClick = function() ns.Consent.Show() end,
		tip = function(tt)
			tt:AddLine(L.CONSENT_CHAT, 1, 0.82, 0)
			tt:AddLine(L.CONSENT_CHAT_TEXT, 1, 1, 1, true)
		end })
	-- Who can read these lines: the channel public, as the Census and the Realm say it.
	local V = ns.Views
	if V and type(V.PublicLines) == "function" then
		local public = {}
		V.PublicLines(public)
		for _, l in ipairs(public) do Add({ indent = true, text = l.text, tip = l.tooltip, onClick = l.onClick }) end
	end
	out[#out].gap = true
	-- Each channel this rank reads, in the game's chat.
	for _, t in ipairs(Readable()) do
		local word = C.TIERS[t].word
		Add({ header = true, text = "|c" .. Hex(Colour(t)) .. "[" .. Label(t) .. "]|r" })
		if type(C.ToggleMute) == "function" then
			Add({ indent = true, text = MutedInChat(t) and Grey(L.CHATSET_MUTED) or L.CHATSET_SHOWN,
				onClick = function()
					C.ToggleMute(word)
					Render()
				end,
				tip = function(tt)
					tt:AddLine("[" .. Label(t) .. "]", 1, 0.82, 0)
					tt:AddLine(L.CHATSET_MUTE_TIP:format(word), 1, 1, 1, true)
				end })
		end
		local choose = type(C.OpenWindows) == "function" and type(C.ChooseWindow) == "function"
		Add({ indent = true, text = L.CHATSET_WHERE:format(WhereText(t)) .. (choose and (" " .. Grey(L.CHATSET_WHERE_NEXT)) or ""),
			onClick = choose and function()
				NextWindow(t)
				Render()
			end or nil,
			tip = function(tt)
				tt:AddLine("[" .. Label(t) .. "]", 1, 0.82, 0)
				tt:AddLine(Chatty() and L.CHATSET_WHERE_TIP_CHATTY or L.CHATSET_WHERE_TIP:format(newWindow), 1, 1, 1, true)
			end })
		out[#out].gap = true
	end
	-- The Olympus tab of the game's chat (the line over the lines, put away or not).
	if TabReady() then
		Add({ header = true, text = Gold(L.CHATSET_TAB) })
		local state = C.TabState()
		local function AddTip(tt)
			tt:AddLine(L.CHATS_TAB_ADD, 1, 0.82, 0)
			tt:AddLine(L.CHATS_TAB_ADD_TIP, 1, 1, 1, true)
		end
		if state == "open" then
			-- (Open: a click sends all three channels there again, SetupTab saying so.)
			Add({ indent = true, text = Grey(L.CHATS_TAB_ON), onClick = function()
				C.SetupTab()
				Render()
			end, tip = function(tt)
				tt:AddLine(L.CHATSET_TAB, 1, 0.82, 0)
				tt:AddLine(L.CHATS_TAB_TIP, 1, 1, 1, true)
			end })
		elseif watching then
			Add({ indent = true, text = Grey(TabSteps()), onClick = function()
				StepsAgain()
				Render()
			end, tip = AddTip })
		else
			Add({ indent = true, text = state == "waiting" and Grey(L.CHATS_TAB_WAITING) or Green("+ " .. L.CHATS_TAB_ADD),
				onClick = function()
					ChatWindow.AddTab()
					Render()
				end, tip = AddTip })
		end
		out[#out].gap = true
	end
	-- The pinned line, for whoever may pin (Channels.CanPin: the King, his Stewards and Hands for
	-- the army, a guild master for his guild), typed in an Olympus dialog (ns.ShowDialog: the
	-- gamepad UI's own window there). Only while the chats are on, where a pin can be set.
	if on and type(C.CanPin) == "function" and C.CanPin() then
		local guildOnly = type(C.PinScope) == "function" and C.PinScope() == "guild"
		local label = guildOnly and L.PIN_ADD_GUILD or L.PIN_ADD
		Add({ header = true, text = Gold(L.PIN_LABEL) })
		Add({ indent = true, text = Green(label), onClick = function() ns.ShowDialog("OLYMPUS_PIN") end,
			tip = function(tt)
				tt:AddLine(label, 1, 0.82, 0)
				tt:AddLine(guildOnly and L.PIN_ADD_GUILD_TIP or L.PIN_ADD_TIP, 1, 1, 1, true)
			end, gap = true })
	end
	-- 1.1.6: "Your moderation record" (WatchChat.lua): what moderators did about this player's
	-- lines, by role only, with an appeal to the High Council a click away.
	local WC = ChatWindow.Mod()
	for _, l in ipairs(WC and type(WC.RecordLines) == "function" and WC.RecordLines() or {}) do Add(l) end
	return out
end

-- A line of the settings, from a pool (made once, reused on every redraw).
local function SettingRow(i)
	local rows = frame.setRows
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, frame.setContent)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(true)
	r:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat settings", self.onClick) end end)
	r:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
	r:SetScript("OnLeave", function(self) Untip(self) end)
	rows[i] = r
	return r
end

local function DrawSettings()
	local s = frame.setScroll
	local width = s:GetWidth()
	if not Finite(width) or width <= 0 then width = (frame:GetWidth() or 338) - 20 - (frame.barRoom or 22) end
	width = math.max(100, math.floor(width))
	frame.setContent:SetWidth(width)
	local y, n = 8, 0
	for _, l in ipairs(ChatWindow.SettingsLines()) do
		n = n + 1
		local r = SettingRow(n)
		local x = EDGE + (l.indent and INDENT or 0)
		local w = math.max(40, width - x - EDGE)
		if r.text.SetFontObject then r.text:SetFontObject(l.header and "GameFontNormal" or "GameFontHighlightSmall") end
		r.text:SetText(l.text)
		r.text:SetWidth(w)
		local h = TextHeight(r.text, w)
		r:SetSize(w, h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", frame.setContent, "TOPLEFT", x, -y)
		r.onClick, r.tip, r.line = l.onClick, l.tip, l
		r:EnableMouse(l.onClick ~= nil or l.tip ~= nil)
		r:Show()
		y = y + h + (l.gap and 12 or (l.header and 4 or 3))
	end
	for i = n + 1, #frame.setRows do
		local r = frame.setRows[i]
		r:Hide()
		r.onClick, r.tip, r.line = nil, nil, nil
	end
	frame.setContent:SetHeight(math.max(1, y + 4))
end

---------------------------------------------------------------------------
-- The box to write in, and the search box.
---------------------------------------------------------------------------

-- The box: the channel's label on its left, a grey hint while empty (the moderators' word when
-- they took us off).
local function DrawInput()
	local eb = frame.input
	local room = Dynamic(tier)
	local short = room and (room.spec.kind == "match" and (L.MATCH_ROOM_LABEL or "Match")
		or (L.ARENA_CHAT_ROOM_LABEL or "Fight")) or Label(tier)
	eb.label:SetText("|c" .. Hex(Colour(tier)) .. "[" .. short .. "]:|r")
	local lw = math.ceil(TextWidth(eb.label))
	eb:SetTextInsets(lw + 6, 6, 0, 0)
	local M = ns.Moderation
	local off = M and type(M.SelfOff) == "function" and M.SelfOff() or nil
	local hint
	if off and type(M.YouText) == "function" then
		hint = M.YouText(off)
	elseif not room and ChatWindow.Mod() and ChatWindow.Mod().StripText() then
		hint = ChatWindow.Mod().StripText() -- (1.1.6: a moderator's timeout, WatchChat.lua)
	else
		-- A fight room has its own ArenaChat route (the private ones are logged whispers to their
		-- participants); the Olympus channel's public warning never describes it.
		local logical = ChatWindow.Logical(tier)
		local public = logical and logical.scope == "topic"
			or not room and not logical and ns.Comm and type(ns.Comm.IsPublic) == "function" and ns.Comm.IsPublic()
		hint = L.CHATWIN_PLACEHOLDER:format(Label(tier)) .. (public and L.CHATWIN_PUBLIC or "")
	end
	eb.hint:SetText(hint)
	eb.hint:ClearAllPoints()
	eb.hint:SetPoint("LEFT", eb, "LEFT", lw + 6, 0)
	eb.hint:SetPoint("RIGHT", eb, "RIGHT", -6, 0)
	Hint()
end

-- The search box shows what the tab's search holds (Views keeps it for the session, as each tab's).
local function DrawSearch()
	local V = ns.Views
	local text = V and type(V.Filter) == "function" and V.Filter(TAB) or ""
	local sb = frame.search
	if (sb:GetText() or "") ~= text then sb:SetText(text) end
	sb.clear:SetShown(text ~= "")
end

---------------------------------------------------------------------------
-- The game's key to start typing (1.1.1, the owner's ask after trying the tab: with the Chat tab
-- open, the key that starts typing starts typing in it). While the tab shows with the chats on,
-- the key or keys the player bound to the game's "Open chat" (OPENCHAT, Bindings_Standard.xml;
-- read with GetBindingKey, never assumed, usually Enter) click Olympus's own button, which puts
-- the keyboard in the tab's box: an override binding that button owns (SetOverrideBindingClick),
-- taken off (ClearOverrideBindings on it) the moment the tab hides, the window closes, another tab
-- is picked or the chats go off. Nothing of the game's chat box is opened, hooked or written (the
-- rules at the top of the file); "/" (OPENCHATSLASH) stays the game's, where commands run.
-- The game lets no addon change a binding in combat (secure code does it there, the restricted
-- environment's SetBindingClick and ClearBindings, RestrictedFrames.lua): a change asked in combat
-- waits for PLAYER_REGEN_ENABLED and is then what the tab is (still open: set; gone: taken off).
-- The key pressed in combat with the tab gone does nothing but say so, once a fight. With the
-- gamepad UI none of this (its own code keeps override bindings on UIParent, InputBindingManager):
-- no binding, the box a click only. A binding change runs the game's UPDATE_BINDINGS handlers from
-- ours at once (a synchronous event), the gamepad UI's among them (ActionBarEditFrame.lua, the HUD
-- bags), so under it Olympus changes none, with one exception: the key ours still holds at the
-- switch to it (INPUT_DEVICE_INTERFACE_TRANSITION, the game rebinding everything itself) goes back
-- to the game there or, switched in a fight, when that fight ends. Switched back, bound at once.
---------------------------------------------------------------------------

local KEY_ACTION = "OPENCHAT"
local SLASH_ACTION = "OPENCHATSLASH"
local KEY_BUTTON = "OlympusChatKey"
local SyncKeys

local function InCombat() return InCombatLockdown ~= nil and InCombatLockdown() == true end

-- The keys bound to the game's "Open chat" (its bindings: GetBindingKey leaves the overrides out
-- unless asked, so ours never hides them): none, one or two.
local function Keys(ok, ...)
	local out = {}
	if not ok then return out end
	for i = 1, select("#", ...) do
		local k = select(i, ...)
		if type(k) == "string" and k ~= "" then out[#out + 1] = k end
	end
	return out
end
local function ChatKeys()
	if type(GetBindingKey) ~= "function" then return {} end
	return Keys(pcall(GetBindingKey, KEY_ACTION))
end

-- The key the player bound to the game's "Open chat with /" (OPENCHATSLASH), as the game names it
-- (GetBindingText): nil when none is bound (never assumed to be "/"). A message ending with the way
-- to the game's chat box names it (line: its words, the key's place a %s), or says nothing of it.
local function SlashKey()
	if type(GetBindingKey) ~= "function" then return nil end
	local key = Keys(pcall(GetBindingKey, SLASH_ACTION))[1]
	if not key then return nil end
	if type(GetBindingText) == "function" then
		local ok, text = pcall(GetBindingText, key)
		if ok and type(text) == "string" and text ~= "" then return text end
	end
	return key
end
local function WithSlashKey(said, line)
	local key = SlashKey()
	if not key then return said end
	return said .. " " .. line:format(key)
end

-- The tab in sight (UIParent hidden with Alt-Z: not), the chats on, mouse and keyboard.
local function KeysWanted(gamepad)
	if gamepad == nil then gamepad = ns.GamepadUI() end
	if gamepad or not Shown() then return false end
	if frame.IsVisible and not frame:IsVisible() then return false end
	local R = ns.ChatRooms
	return (Dynamic(tier) ~= nil or ChatWindow.Logical(tier) and type(R) == "table" and type(R.ChatOn) == "function" and R.ChatOn(tier)
		or not ChatWindow.Logical(tier) and ns.Channels.ChatOn()) and true or false
end

-- The key pressed (our binding's click, on the press): the keyboard to the tab's box, its lines in
-- place of the settings. The tab gone (a fight kept the binding): said, once a fight.
local function KeyPressed(down)
	if down == false then return end -- (the release: the press did it)
	if not KeysWanted() then
		if InCombat() and not toldLater then
			toldLater = true
			ns.Print(WithSlashKey(L.CHATWIN_KEY_LATER, L.CHATWIN_KEY_LATER_SLASH))
		end
		SyncKeys()
		return
	end
	if settings then ChatWindow.ShowSettings(false) end
	CloseMenu()
	local eb = frame.input
	if eb:IsShown() then ns.Focus(eb) end
end

local function KeyButton()
	if keyButton then return keyButton end
	local b = CreateFrame("Button", KEY_BUTTON, UIParent)
	-- On the press, as the game's own binding runs: the release finds the box open (and after an
	-- empty Enter let the keyboard go, the release does not take it back).
	b:RegisterForClicks("AnyDown")
	b:SetScript("OnClick", function(_, _, down) ns.SafeCall("chat tab key", KeyPressed, down) end)
	keyButton = b
	return b
end

local function SameKeys(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

-- The binding made what the tab is now (or, in combat, when the fight ends). With the gamepad UI
-- nothing is changed but when due: at the switch between the two (gamepad: the style switched to)
-- or at the end of the fight that held a change, the key ours still holds goes back to the game.
SyncKeys = function(due, gamepad)
	if syncing then return end
	if gamepad == nil then gamepad = ns.GamepadUI() end
	if gamepad and not due then return end
	local keys = KeysWanted(gamepad) and ChatKeys() or {}
	if SameKeys(keys, boundKeys or {}) then
		keysLater = false
		return
	end
	if InCombat() then
		keysLater = true
		return
	end
	if type(SetOverrideBindingClick) ~= "function" or type(ClearOverrideBindings) ~= "function" then return end -- gp:chat-key
	syncing = true
	local ok, err = pcall(function() -- gp:chat-key
		local b = KeyButton()
		boundKeys = #keys > 0 and keys or nil
		ClearOverrideBindings(b)
		for _, k in ipairs(keys) do SetOverrideBindingClick(b, false, k, KEY_BUTTON, "LeftButton") end
	end)
	syncing, keysLater = false, false
	if not ok then error(err, 0) end
end

-- What the box shows: "lines" (the chats on: the lines, and the box to write in), "off" (the chats
-- off on this client: the choice, and a way to it) or "settings" (the gear's). The top row is
-- DrawTop's.
local function ShowParts(mode)
	local lines = mode == "lines"
	frame.scroll:SetShown(lines)
	frame.input:SetShown(lines)
	frame.off:SetShown(mode == "off")
	frame.setScroll:SetShown(mode == "settings")
	if not lines then
		frame.newPill:Hide()
		frame.guide:Hide()
		frame.hiddenCount:Hide()
		if frame.matchContext then frame.matchContext:Hide() end
		frame.topicStatus:Hide()
		if frame.modStatus then frame.modStatus:Hide() end
	end
	if mode == "settings" then frame.pin:Hide() end
end

local function Draw()
	if not frame or not frame.places then return end
	if ChatWindow.PruneDynamicRooms then ChatWindow.PruneDynamicRooms() end
	local C = ns.Channels
	local tiers = Readable()
	-- A rank that reads none of the channels any more (out of Olympus): the tab goes, and the
	-- window with it on the Census (UI.Refresh).
	if #tiers == 0 then
		frame:Hide()
		if ns.UI and type(ns.UI.Refresh) == "function" then ns.SafeCall("chat tab", ns.UI.Refresh) end
		return
	end
	if not tier or not Choice(tier) then
		tier, ChatWindow.globalTier = tiers[1], tiers[1]
		Remember(tier)
		ChatWindow.LoadDraft(tier)
	end
	local room = Dynamic(tier)
	if room then settings = false; room.used = GetTime and GetTime() or 0 end
	local logical = ChatWindow.Logical(tier)
	local R = ns.ChatRooms
	local on
	if room then
		on = true
	elseif logical then
		-- (A provider's private room answers for its own consent: ChatRooms.ChatOn by the room.)
		on = type(R) == "table" and type(R.ChatOn) == "function" and R.ChatOn(tier) == true
	else
		on = C.ChatOn()
	end
	DrawTop(Choices(), on)
	local box = frame.places.box
	-- The box where the list's box is, whatever shows in it (the destinations' tabs fixed in it,
	-- ChatWindow.DrawSubtabs).
	frame.box:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left, box.top)
	-- Keep the destinations on the window's light ground. The logical box still anchors
	-- the scroll and status rows; only the dark inset begins below the navigation.
	if frame.bodyInset then
		frame.bodyInset:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left,
			settings and box.top or (frame.navBottom or box.top) - 3)
	end
	-- The settings: from the top row down, no strip over them.
	if settings then
		ShowParts("settings")
		DrawSettings()
		return
	end
	local y = frame.underTabs or box.top
	-- The strips over the lines, under the tabs, each taking room only while it shows: the pinned
	-- line, the way to the Olympus tab, the count of the lines the block terms hide (nearest the
	-- lines it counts).
	if room or logical then
		frame.pin:Hide()
		frame.guide:Hide()
	else
		y = y - DrawPin(y)
	end
	if room and DrawMatchContext then y = y - DrawMatchContext(y, room)
	elseif frame.matchContext then frame.matchContext:Hide() end
	local all
	if room then
		local A = ns.ArenaChat
		all = type(A) == "table" and type(A.Lines) == "function" and A.Lines(room.id) or {}
	elseif logical then
		all = type(R) == "table" and type(R.History) == "function" and R.History(tier) or {}
	elseif on then
		all = C.History(tier) -- (read once, for the count and the lines)
	end
	if on then
		if logical then y = y - ChatWindow.DrawTopicStatus(y) else frame.topicStatus:Hide() end
		-- (1.1.6: this character's timeout, WatchChat.lua, over every chat it covers; not a fight room's.)
		if not room then y = y - ChatWindow.DrawModStatus(y) elseif frame.modStatus then frame.modStatus:Hide() end
		if not room and not logical then y = y - DrawGuide(y) end
		y = y - DrawHiddenCount(y, all)
	end
	ChatWindow.PlaceLines(y)
	ShowParts(on and "lines" or "off")
	if not on then
		-- The consent page's explanation, with the choice a click away.
		frame.off.text:SetText(logical and ((L.CHATROOMS_OFF_PAGE or "Chat rooms are off.") .. "\n\n" .. (L.CONSENT_CHATROOMS_TEXT or ""))
			or (L.CHATWIN_OFF .. "\n\n" .. L.CONSENT_CHAT_TEXT))
		return
	end
	DrawSearch()
	DrawInput()
	local was = not stick and InView() or nil
	DrawLines(all)
	if stick then
		want = nil
		ToBottom()
	elseif was and #was > 0 then
		BackInView(was)
	else
		want = nil -- (no line in view: the offset stays as the player left it)
	end
	ShowNew()
end

function ChatWindow.Render()
	dirty = false
	Draw()
	-- (The "Open chat" key follows: the chats on or off, the tab gone with the last channel.)
	ns.SafeCall("chat tab key", SyncKeys)
end

-- The settings in place of the lines (the gear), or the lines again. Never takes the keyboard.
function ChatWindow.ShowSettings(on)
	settings = on and true or false
	CloseMenu()
	ChatWindow.CloseSubMenu()
	if not frame then return end
	if settings then
		frame.input:ClearFocus()
		frame.search:ClearFocus()
	else
		stick, newCount, want = true, 0, nil
	end
	if Shown() then Render() end
end
function ChatWindow.SettingsShown() return settings end

---------------------------------------------------------------------------
-- Writing: Olympus's own box, through the selected chat owner's send API (every check and refusal
-- remains Channels' or ArenaChat's).
---------------------------------------------------------------------------

function ChatWindow.SelectLegacy(t)
	local C = ns.Channels
	local d = C.TIERS[t]
	if not d then return end
	if not C.CanUse(t) then
		ns.Print(L[d.deny]:format(L[d.label]))
		return
	end
	ChatWindow.SaveDraft()
	tier, ChatWindow.globalTier = t, t
	unread[t] = nil
	Remember(t)
	CloseMenu()
	ChatWindow.CloseSubMenu()
	settings = false -- (a channel picked: its lines, not the settings)
	ChatWindow.LoadDraft(t)
	if Shown() then
		stick, newCount = true, 0
		Render()
		ScrollToBottom()
	end
end

function ChatWindow.SelectLogical(id)
	local R = ns.ChatRooms
	if type(R) ~= "table" or type(R.Select) ~= "function" then return false end
	if type(R.PreviewOnly) == "function" and R.PreviewOnly(id) then
		ns.Print(ChatWindow.Localized("CHATROOM_ROLE_PREVIEW", "Preview only - switch back to your own view to use role chats."))
		return false
	end
	local ok = R.Select(id)
	if not ok then
		ns.Print(L.CHATROOM_NO_ACCESS or "You no longer have access to that room.")
		return false
	end
	ChatWindow.SaveDraft()
	tier = id
	unread[id] = nil
	Remember(id)
	CloseMenu()
	ChatWindow.CloseSubMenu()
	settings = false
	ChatWindow.LoadDraft(id)
	if Shown() then
		stick, newCount = true, 0
		Render()
		ScrollToBottom()
	end
	return true
end

local function SelectRoom(key)
	local r = Dynamic(key)
	if not r then return false end
	ChatWindow.SaveDraft()
	tier = key
	unread[key] = nil
	r.used = GetTime and GetTime() or 0
	CloseMenu()
	ChatWindow.CloseSubMenu()
	settings = false
	ChatWindow.LoadDraft(key)
	if Shown() then
		stick, newCount = true, 0
		Render()
		ScrollToBottom()
	end
	return true
end
ChatWindow.SelectDynamicRoom = SelectRoom

local function SelectChoice(key)
	if ns.Channels.TIERS[key] then return ChatWindow.SelectLegacy(key) end
	return SelectRoom(key)
end

local function NextTier()
	if ChatWindow.Logical(tier) then
		local first = ChatWindow.globalTier
		if not first or not ns.Channels.CanUse(first) then first = Readable()[1] end
		if first then ChatWindow.SelectLegacy(first) end
		return
	end
	local choices = Choices()
	if #choices < 2 then return end
	local at = 1
	for i, choice in ipairs(choices) do
		if choice.key == tier then at = i end
	end
	SelectChoice(choices[at % #choices + 1].key)
end

local function Submit()
	if not frame or not tier then return end
	local eb = frame.input
	local text = Trim(eb:GetText())
	-- With mouse and keyboard the cursor stays for the next line (the owner's ask: Enter, type,
	-- Enter, type), with a refused line or a command kept in the box too; an empty Enter lets the
	-- keyboard go back to the game, and so does the privacy warning (its Send or Cancel is next).
	-- With the gamepad UI, as the Communities box: every Enter lets it go.
	local keep = not ns.GamepadUI()
	if text == "" then
		eb:SetText("")
		keep = false
	elseif text:sub(1, 1) == "/" then
		-- This box runs no command and never hands one to the game: the text stays, nothing is sent.
		-- With the cursor kept, the way to the game's box too: Escape, then the player's own key for
		-- it (the open-chat key comes back here; the gamepad UI's box already let go, as before).
		local said = L.CHATWIN_NO_SLASH:format(Label(tier))
		if keep then said = WithSlashKey(said, L.CHATWIN_SLASH_WAY) end
		ns.Print(said)
	else
		-- A dynamic room never goes through Channels.Send: its public/event lane or exclusive
		-- participant whispers, rules, mutes and slow mode stay ArenaChat's one authority. Standard
		-- channels retain their old keepMute behaviour.
		local room = Dynamic(tier)
		local logical = ChatWindow.Logical(tier)
		local ok, why
		if room then
			local A = ns.ArenaChat
			if type(A) == "table" and type(A.Send) == "function" then ok, why = A.Send(room.id, text) else ok, why = false, "room" end
		elseif logical then
			local R = ns.ChatRooms
			if type(R) == "table" and type(R.Send) == "function" then ok, why = R.Send(tier, text) else ok, why = false, "room" end
		else
			ok, why = ns.Channels.Send(tier, text, nil, true)
		end
		-- Sent, or held by the privacy warning (it sends the line on the player's OK): the box
		-- empties. Refused: the text stays (Send said why).
		if ok or why == "confirm" then
			eb:SetText("")
			if ok and not room then notes[tier] = nil end
			ScrollToBottom()
			MarkDirty()
		end
		if why == "confirm" then keep = false end
	end
	if not keep then eb:ClearFocus() end
	Hint()
end

-- Typed in the search box: the tab's search (Views.SetFilter, kept with the tab for the session),
-- the lines drawn again from the newest match.
local function SearchChanged(sb)
	local V = ns.Views
	local text = sb:GetText() or ""
	sb.clear:SetShown(text ~= "")
	if not V or type(V.SetFilter) ~= "function" or text == V.Filter(TAB) then return end
	V.SetFilter(TAB, text)
	stick, newCount, want = true, 0, nil
	MarkDirty()
end

---------------------------------------------------------------------------
-- The tab, made once for each Olympus window
---------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	local step = tonumber(elapsed) or 0
	acc = acc + step
	if watching then
		lookAcc = lookAcc + step
		if lookAcc >= LOOK_GAP and not (pointer and pointer:IsShown()) then
			lookAcc = 0
			ns.SafeCall("olympus tab", Look)
		end
	end
	if acc < THROTTLE then return end
	acc = 0
	if dataPending and GetTime() - lastData >= DATA_GAP then
		dataPending, lastData, dirty = false, GetTime(), true
	end
	-- A rank that no longer reads this channel (a demotion, out of the guild), or a room whose
	-- retention ended: drawn again at once.
	if ChatWindow.PruneDynamicRooms and GetTime() - lastRoomPrune >= LOOK_GAP then ChatWindow.PruneDynamicRooms() end
	if tier and not Choice(tier) then dirty = true end
	local R = ns.ChatRooms
	local logical = ChatWindow.Logical(tier)
	local status = logical and logical.scope == "topic" and type(R) == "table" and type(R.RequestStatus) == "function" and R.RequestStatus(tier) or nil
	local minute = status and status.wait and status.wait > 0 and math.ceil(status.wait / 60) or nil
	if minute ~= ChatWindow.requestMinute then ChatWindow.requestMinute, dirty = minute, true end
	if dirty then ns.SafeCall("chat tab", Render) end
end

-- A texture from the game's atlas when this client has it, else a file every client carries.
local function Icon(tex, atlas, file)
	local info = C_Texture and C_Texture.GetAtlasInfo
	local ok, found = false, nil
	if type(info) == "function" and type(tex.SetAtlas) == "function" then ok, found = pcall(info, atlas) end
	if ok and found ~= nil then
		tex:SetAtlas(atlas)
	else
		tex:SetTexture(file)
		if file == GEAR_FILE then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end -- (an icon's border off)
	end
end

-- A thin dark frame with the tooltip's border (the bubbles' look): the switch and its list.
local function Framed(kind, parent)
	local ok, f = pcall(CreateFrame, kind, nil, parent, "BackdropTemplate")
	if not ok or not f then f = CreateFrame(kind, nil, parent) end
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		if f.SetBackdropColor then f:SetBackdropColor(0.06, 0.06, 0.07, 0.95) end
		if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) end
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
	end
	return f
end

-- The channels' switch on the top row: the channel shown and its arrow; a click lists the channels
-- the rank reads (its own list, Olympus's frames: no game dropdown), a click there picks one.
local function MakeSwitch(p)
	local b = Framed("Button", p)
	b:SetHeight(SEARCH_H)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.count:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
	b.count:SetTextColor(1, 0.82, 0)
	b.arrow = b:CreateTexture(nil, "OVERLAY")
	b.arrow:SetSize(ARROW_W, ARROW_W)
	b.arrow:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.arrow:SetTexture(ARROW_FILE)
	b:SetScript("OnClick", function() ns.SafeCall("chat tab channels", ToggleMenu) end)
	b:SetScript("OnEnter", function(self)
		Tip(self, function(tt)
			tt:AddLine(Dynamic(tier) and Label(tier) or ("[" .. Label(tier) .. "]"), 1, 0.82, 0)
			tt:AddLine(L.CHATSET_SWITCH_TIP, 1, 1, 1, true)
			for _, choice in ipairs(Choices()) do
				local n = unread[choice.key] or 0
				if choice.key ~= tier and n > 0 then tt:AddLine(L.CHATWIN_NEW_IN:format(Label(choice.key), n), 0.7, 0.7, 0.7) end
			end
		end)
	end)
	b:SetScript("OnLeave", function(self) Untip(self) end)
	b:Hide()
	p.switch = b
	-- Its list, over everything in the tab, and under it a catcher the size of the tab: a click
	-- anywhere else closes the list.
	local c = CreateFrame("Button", nil, p)
	c:SetAllPoints(p)
	c:SetFrameLevel((p:GetFrameLevel() or 1) + 30)
	c:SetScript("OnClick", function() ns.SafeCall("chat tab channels", CloseMenu) end)
	c:Hide()
	p.catcher = c
	local m = Framed("Frame", p)
	m:SetFrameLevel((p:GetFrameLevel() or 1) + 40)
	m:EnableMouse(true)
	m.rows = {}
	function m:AddChoice(key)
		local r = CreateFrame("Button", nil, m)
		r.choiceKey = key
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		r.text:SetPoint("LEFT", r, "LEFT", 10, 0)
		-- (The one shown: a bar in its colour at its left.)
		r.mark = r:CreateTexture(nil, "ARTWORK")
		r.mark:SetWidth(2)
		r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -4)
		r.mark:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 2, 4)
		r:SetScript("OnClick", function(self) ns.SafeCall("chat tab choice", SelectChoice, self.choiceKey) end)
		r:SetScript("OnEnter", function(self)
			self.hover = true
			PaintChoice(self)
			Tip(self, function(tt)
				local room = Dynamic(self.choiceKey)
				tt:AddLine(room and Label(self.choiceKey) or ("[" .. Label(self.choiceKey) .. "]"), 1, 0.82, 0)
				if room then
					local access = room.spec.access == "participants" and (L.ARENA_CHAT_ROOM_PRIVATE or "Fighters and arbiter only")
						or (L.ARENA_CHAT_ROOM_MEMBERS or "Olympus members")
					tt:AddLine(access, 0.7, 0.7, 0.7, true)
					if room.pinned then tt:AddLine(L.ARENA_CHAT_ROOM_PINNED or "Pinned locally", 1, 0.82, 0, true) end
				-- The tab shows a channel muted in chat (/oly mute is about the chat frame).
				elseif MutedInChat(self.choiceKey) then
					tt:AddLine(L.CHATWIN_MUTED_TIP, 0.7, 0.7, 0.7, true)
				end
			end)
		end)
		r:SetScript("OnLeave", function(self)
			self.hover = nil
			PaintChoice(self)
			Untip(self)
		end)
		m.rows[key] = r
		return r
	end
	for _, t in ipairs(ns.Channels.ORDER) do m:AddChoice(t) end
	m:Hide()
	p.menu = m
end

-- The gear at the top row's end: the settings in place of the lines, and back.
local function MakeGear(p)
	local g = CreateFrame("Button", nil, p)
	g:SetSize(GEAR_W, GEAR_W)
	g.icon = g:CreateTexture(nil, "ARTWORK")
	g.icon:SetSize(16, 16)
	g.icon:SetPoint("CENTER", g, "CENTER", 0, 0)
	Icon(g.icon, GEAR_ATLAS, GEAR_FILE)
	g:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	g:SetScript("OnClick", function() ns.SafeCall("chat settings", ChatWindow.ShowSettings, not settings) end)
	g:SetScript("OnEnter", function(self)
		Tip(self, function(tt)
			tt:AddLine(L.CHATSET_TITLE, 1, 0.82, 0)
			tt:AddLine(L.CHATSET_TIP, 1, 1, 1, true)
		end)
	end)
	g:SetScript("OnLeave", function(self) Untip(self) end)
	p.gear = g
	-- The settings' title, where the search box is while they show.
	p.setTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.setTitle:SetText(L.CHATSET_TITLE)
	p.setTitle:Hide()
end

-- A dynamic room is a local choice inside the existing Chat page, not a fourth Olympus channel.
-- Its pin and x therefore replace the global page's help/settings controls only while that room
-- is selected. Neither button sends anything: the x closes ArenaChat locally; the pin is saved on
-- this account until the canonical event says the room is no longer recoverable.
local function MakeRoomButtons(p)
	local function Small(label)
		local b = CreateFrame("Button", nil, p)
		b:SetSize(ROOM_BUTTON_W, ROOM_BUTTON_W)
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
		b.label:SetText(label)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:Hide()
		return b
	end
	local pin = Small("p")
	pin:SetScript("OnClick", function(self)
		local r = Dynamic(tier)
		if r then ns.SafeCall("chat room pin", ChatWindow.PinDynamicRoom, r.key, not r.pinned) end
	end)
	pin:SetScript("OnEnter", function(self)
		local r = Dynamic(tier)
		if not r then return end
		Tip(self, function(tt)
			local title = r.pinned and (L.ARENA_CHAT_ROOM_UNPIN or "Unpin fight chat") or (L.ARENA_CHAT_ROOM_PIN or "Pin fight chat")
			tt:AddLine(title, 1, 0.82, 0)
			tt:AddLine(L.ARENA_CHAT_ROOM_PIN_TIP or "A local pin keeps this room until the fight expires.", 1, 1, 1, true)
		end)
	end)
	pin:SetScript("OnLeave", function(self) Untip(self) end)
	p.roomPin = pin

	local close = Small("x")
	close:SetScript("OnClick", function()
		local r = Dynamic(tier)
		if r then ns.SafeCall("chat room remove", ChatWindow.CloseDynamicRoom, r.key) end
	end)
	close:SetScript("OnEnter", function(self)
		Tip(self, function(tt)
			tt:AddLine(L.ARENA_CHAT_ROOM_REMOVE or "Remove fight chat", 1, 0.82, 0)
			tt:AddLine(L.ARENA_CHAT_ROOM_REMOVE_TIP or "Removes this room from your Chat page. You can open it from the fight again.", 1, 1, 1, true)
		end)
	end)
	close:SetScript("OnLeave", function(self) Untip(self) end)
	p.roomClose = close
end

local function Button(parent, text, width)
	local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", nil, parent)
		b:SetNormalFontObject("GameFontNormal")
	end
	b:SetSize(width, 22)
	b:SetText(text)
	return b
end

-- The accepted match keeps its location/readiness controls beside its private conversation. The
-- buttons call ArenaMatch's existing actions; this panel owns no match state and sends no word by
-- merely opening or redrawing. More involved place selection deliberately opens the existing card.
local function MakeMatchContext(p)
	local c = CreateFrame("Frame", nil, p)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	c.bg:SetColorTexture(0.12, 0.07, 0.04, 0.72)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetJustifyH("LEFT")
	c.text:SetJustifyV("TOP")
	c.text:SetWordWrap(true)
	c.buttons = {}
	-- The live card can expose every supported readiness/location action plus Details at once.
	for i = 1, 12 do
		local b = Button(c, "", 90)
		b:SetHeight(22)
		b:SetScript("OnClick", function(self)
			local M = ns.ArenaMatch
			if not (M and M.RoomAction) then return end
			local ok, why = M.RoomAction(self.roomId, self.actionKey)
			if ok == false and why then
				local line = M.RoomWhyText and M.RoomWhyText(why) or tostring(why)
				ns.Print(line)
			end
			MarkDirty()
		end)
		b:Hide()
		c.buttons[i] = b
	end
	c:Hide()
	p.matchContext = c
end

DrawMatchContext = function(y, room)
	local c = frame.matchContext
	local M = ns.ArenaMatch
	if not c or room.spec.kind ~= "match" or type(M) ~= "table" or type(M.RoomView) ~= "function" then
		if c then c:Hide() end
		return 0
	end
	local ok, view = pcall(M.RoomView, room.id)
	if not ok or type(view) ~= "table" then c:Hide() return 0 end
	-- (In the box, under the destinations' tabs, clear of its border as the lines are.)
	local box = frame.places.box
	local width = math.max(140, (frame:GetWidth() or 338) - box.left + box.right - 8)
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left + 4, y - 3)
	c:SetWidth(width)
	c.text:ClearAllPoints()
	c.text:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -6)
	c.text:SetWidth(width - 16)
	c.text:SetText(table.concat(view.lines or {}, "\n"))
	local textH = TextHeight(c.text, width - 16)
	local x, rowY, rows = 8, -(textH + 10), 0
	for i, action in ipairs(view.actions or {}) do
		local b = c.buttons[i]
		if not b then break end
		b.actionKey, b.roomId = action.key, room.id
		b:SetText(action.label or action.key or "")
		local fs = b.GetFontString and b:GetFontString()
		local bw = math.max(78, math.min(width - 16, math.ceil(fs and TextWidth(fs) or 60) + 24))
		if x > 8 and x + bw > width - 8 then x, rowY, rows = 8, rowY - 26, rows + 1 end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", c, "TOPLEFT", x, rowY)
		b:SetWidth(bw)
		b:Show()
		x = x + bw + 6
	end
	for i = #(view.actions or {}) + 1, #c.buttons do c.buttons[i]:Hide() end
	local hasActions = #(view.actions or {}) > 0
	local height = textH + 12 + (hasActions and ((rows + 1) * 26 + 4) or 0)
	c:SetHeight(height)
	c.view = view
	c:Show()
	return height + 6
end

-- 1.1.2: the Answers button (the author, the High Council and the Stewards: a ready answer into
-- this box, Answers.lua), at the box's end (PlaceInput). (1.1.5: the tab's own "?" that went with
-- it on the top row is gone, the owner's ask: the window's help button left of the X is the one
-- "i" over the tab.)
local function MakeAnswers(p)
	local a = Button(p, L.ANSWERS_BTN, 70)
	a:SetHeight(SEARCH_H)
	a:SetScript("OnClick", function()
		ns.SafeCall("chat answers", function() if ns.Answers and ns.Answers.Open then ns.Answers.Open(p.input) end end)
	end)
	a:SetScript("OnEnter", function(self)
		Tip(self, function(tt)
			tt:AddLine(L.ANSWERS_BTN, 1, 0.82, 0)
			tt:AddLine(L.ANSWERS_BTN_TIP, 1, 1, 1, true)
		end)
	end)
	a:SetScript("OnLeave", function(self) Untip(self) end)
	a:Hide()
	p.answers = a
end

function ChatWindow.MakeSubtabs(p)
	-- (Its buttons are the shared strip's, made as it draws them: Views.DrawNav.)
	local bar = CreateFrame("Frame", nil, p)
	bar:Hide()
	p.subtabs = bar

	local catcher = CreateFrame("Button", nil, p)
	catcher:SetAllPoints(p)
	catcher:SetFrameLevel((p:GetFrameLevel() or 1) + 30)
	catcher:SetFrameStrata("DIALOG")
	catcher:SetScript("OnClick", ChatWindow.CloseSubMenu)
	catcher:Hide()
	p.subCatcher = catcher
	local menu = Framed("Frame", p)
	menu:SetFrameLevel((p:GetFrameLevel() or 1) + 40)
	menu:SetFrameStrata("DIALOG")
	menu:EnableMouse(true)
	menu.rows = {}
	for i = 1, 10 do
		local row = CreateFrame("Button", nil, menu)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
		row.mark = row:CreateTexture(nil, "ARTWORK")
		row.mark:SetWidth(2)
		row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
		row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
		row.mark:SetColorTexture(1, 0.82, 0, 1)
		row:SetScript("OnEnter", function(self)
			Tip(self, function(tt) tt:AddLine(self.text:GetText(), 1, 1, 1, true) end)
		end)
		row:SetScript("OnLeave", function(self) Untip(self) end)
		row:SetScript("OnClick", function(self)
			if self.previewOnly then
				ns.Print(ChatWindow.Localized("CHATROOM_ROLE_PREVIEW", "Preview only - switch back to your own view to use role chats."))
				return
			end
			local id, dynamic, onClick = self.roomId, self.dynamic, self.onClick
			ChatWindow.CloseSubMenu()
			if type(onClick) == "function" then ns.SafeCall("chat room choice", onClick)
			elseif dynamic and id then ns.SafeCall("chat arena choice", ChatWindow.SelectDynamicRoom, id)
			elseif id then ns.SafeCall("chat room choice", ChatWindow.SelectLogical, id) end
		end)
		menu.rows[i] = row
	end
	menu:Hide()
	p.subMenu = menu
end

-- A strip over the lines (the pinned line, the Olympus tab's line, the count of the hidden lines): a
-- button with wrapped text.
local function StripButton(p, lines)
	local s = CreateFrame("Button", nil, p)
	s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
	s.text:SetJustifyH("LEFT")
	s.text:SetWordWrap(true)
	if s.text.SetMaxLines then s.text:SetMaxLines(lines) end
	s:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
	s:SetScript("OnLeave", function(self) Untip(self) end)
	s:Hide()
	return s
end

-- The "x" at the end of the search box, as every tab's (Views.lua): empties it and lets go of the
-- keyboard. A button of its own, never a focus change.
local function ClearButton(sb)
	local x = CreateFrame("Button", nil, sb)
	x:SetSize(16, 16)
	x:SetPoint("RIGHT", sb, "RIGHT", -2, 0)
	x.label = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.label:SetPoint("CENTER", x, "CENTER", 0, 1)
	x.label:SetText("x")
	x:SetScript("OnClick", function()
		sb:SetText("")
		sb:ClearFocus()
		ns.SafeCall("chat tab search", SearchChanged, sb)
	end)
	x:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.SEARCH_CLEAR, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function() GameTooltip:Hide() end)
	x:Hide()
	return x
end

local function Build(h)
	if panes[h] then return panes[h] end
	local base = (h.GetName and h:GetName() or "Olympus") .. "Chat"
	local p = CreateFrame("Frame", base, h)
	p:Hide() -- (nothing in it shown, nor its box, before it is ready)
	panes[h] = p
	p.host = h
	p:SetAllPoints(h)
	p.bubbles, p.rows, p.setRows = {}, {}, {}

	-- The search, where the other tabs show the army's counts.
	p.topRow = CreateFrame("Frame", nil, p)
	p.topRow:SetAllPoints(p)
	p.searchLabel = p.topRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.searchLabel:SetText(L.SEARCH)
	local okSearch, sb = pcall(CreateFrame, "EditBox", nil, p.topRow, "InputBoxTemplate")
	if not okSearch or not sb then sb = CreateFrame("EditBox", nil, p.topRow) end
	sb:SetAutoFocus(false)
	sb.olympusBox = true
	sb:SetHeight(SEARCH_H)
	sb:SetMaxLetters(40)
	sb:SetFontObject("ChatFontNormal")
	sb:SetTextInsets(0, 18, 0, 0) -- (the typing stops short of the "x")
	sb.clear = ClearButton(sb)
	sb:SetScript("OnTextChanged", function(self) ns.SafeCall("chat tab search", SearchChanged, self) end)
	sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sb:SetScript("OnHide", function(self) self:ClearFocus() end)
	sb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.SEARCH, 1, 0.82, 0)
		GameTooltip:AddLine(L.SEARCH_TIP_CHAT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p.search = sb

	-- On the same row, right of the search: the channels' switch, and the gear at the row's end.
	MakeSwitch(p)
	MakeGear(p)
	MakeRoomButtons(p)
	MakeMatchContext(p)
	MakeAnswers(p)
	ChatWindow.MakeSubtabs(p)

	-- The pinned line.
	p.pin = StripButton(p, PIN_LINES)
	p.pin:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat tab pin", self.onClick) end end)

	-- A persistent race/class outsider notice, including the two-gate request state.
	p.topicStatus = StripButton(p, 3)
	p.topicStatus:EnableMouse(false)
	p.modStatus = StripButton(p, 2) -- (1.1.6: a timeout's strip, WatchChat.lua)
	p.modStatus:EnableMouse(false)

	-- The count of the lines the block terms hide.
	p.hiddenCount = StripButton(p, COUNT_LINES)
	p.hiddenCount:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat tab hidden", self.onClick) end end)
	p.hiddenCount.tip = function(tt)
		tt:AddLine(L.FILTER_TIP_TITLE, 1, 0.82, 0)
		tt:AddLine(L.FILTER_TIP, 1, 1, 1, true)
	end

	-- The way to the Olympus tab of the game's chat.
	p.guide = StripButton(p, GUIDE_LINES)
	p.guide:SetScript("OnClick", function()
		ns.SafeCall("olympus tab", function()
			if watching then StepsAgain() else ChatWindow.AddTab() end
			Render()
		end)
	end)
	p.guide.tip = function(tt)
		tt:AddLine(L.CHATS_TAB_ADD, 1, 0.82, 0)
		tt:AddLine(L.CHATS_TAB_ADD_TIP, 1, 1, 1, true)
	end
	-- Its x: the line put away for good (the review of the Chat tab: a player who keeps his chats
	-- in the main window had it there always); the pointer goes, and the game's chat windows are no
	-- longer read. The settings (the gear) and /oly chatwindow tab still make the Olympus tab.
	local away = CreateFrame("Button", nil, p.guide)
	away:SetSize(16, 16)
	away:SetPoint("TOPRIGHT", p.guide, "TOPRIGHT", 2, 2)
	away.label = away:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	away.label:SetPoint("CENTER", away, "CENTER", 0, 1)
	away.label:SetText("x")
	away:SetScript("OnClick", function()
		ns.SafeCall("olympus tab", function()
			PutTabLineAway()
			StopWatching()
			Render()
		end)
	end)
	away:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.CHATS_TAB_AWAY, 1, 0.82, 0)
		GameTooltip:AddLine(L.CHATS_TAB_AWAY_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	away:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p.guide.away = away

	-- The box of lines (the Communities chat pane's inset), its scroll frame and its lines: over
	-- the list's and the detail box's room.
	local box = CreateFrame("Frame", nil, p)
	local okInset, inset = pcall(CreateFrame, "Frame", nil, box, "InsetFrameTemplate")
	if not okInset or not inset then
		inset = CreateFrame("Frame", nil, box)
		local bg = inset:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.4)
	end
	inset:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
	p.bodyInset = inset
	p.box = box
	-- Keep the search row above the conversation background.
	p.topRow:SetFrameLevel((inset:GetFrameLevel() or 1) + 2)
	for _, control in ipairs({ p.search, p.gear, p.switch, p.roomPin, p.roomClose }) do
		control:SetParent(p.topRow)
		control:SetFrameLevel(p.topRow:GetFrameLevel() + 1)
	end
	-- (The destinations' strip sits in the box, and the strips over the lines under it: drawn over
	-- it, as the list's rows over the Realm's.)
	for _, s in ipairs({ p.subtabs, p.pin, p.topicStatus, p.hiddenCount, p.guide, p.matchContext }) do
		s:SetFrameLevel((box:GetFrameLevel() or 1) + 2)
	end
	-- (Blizzard's thin scroll bar, else the older one where a client has no ScrollFrameTemplate.)
	local function Scroll(name)
		local okScroll, s = pcall(CreateFrame, "ScrollFrame", name, box, "ScrollFrameTemplate")
		local room = 22 -- (the thin bar sits 6 past the frame's right edge)
		if not okScroll or not s or not s.ScrollBar then
			if okScroll and s then s:Hide() end
			s = CreateFrame("ScrollFrame", name .. "Old", box, "UIPanelScrollFrameTemplate")
			room = 28
		end
		s:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
		s:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -room, 4)
		local c = CreateFrame("Frame", nil, s)
		c:SetSize(10, 10)
		s:SetScrollChild(c)
		return s, c, room
	end
	local scroll, content, room = Scroll(base .. "Scroll")
	p.barRoom = room
	p.scroll, p.content = scroll, content
	scroll:HookScript("OnScrollRangeChanged", function() ns.SafeCall("chat tab place", Held) end)
	scroll:HookScript("OnVerticalScroll", function() ns.SafeCall("chat tab scrolled", Scrolled) end)
	scroll:HookScript("OnMouseWheel", function() ns.SafeCall("chat tab scrolled", Scrolled) end)

	-- "N new": the lines that came while the player looks further up; a click goes down to them.
	p.newPill = Button(box, "", 96)
	p.newPill:SetPoint("BOTTOM", box, "BOTTOM", -(p.barRoom / 2), 8)
	p.newPill:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	p.newPill:SetScript("OnClick", function() ns.SafeCall("chat tab new", ScrollToBottom) end)
	p.newPill:Hide()

	-- The chats off on this client: the choice's page (Consent.lua, Olympus's own frame).
	p.off = CreateFrame("Frame", nil, box)
	p.off:SetAllPoints(box)
	p.off.text = p.off:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	p.off.text:SetPoint("TOPLEFT", p.off, "TOPLEFT", 16, -24)
	p.off.text:SetPoint("TOPRIGHT", p.off, "TOPRIGHT", -16, -24)
	p.off.text:SetWordWrap(true)
	p.off.button = Button(p.off, L.CHATWIN_OFF_BUTTON, 110)
	p.off.button:SetPoint("TOP", p.off.text, "BOTTOM", 0, -14)
	p.off.button:SetScript("OnClick", function() ns.SafeCall("chat tab choice", ns.Consent.Show) end)
	p.off:Hide()

	-- The settings (the gear), in the same box, scrolled on their own.
	p.setScroll, p.setContent = Scroll(base .. "Settings")
	p.setScroll:Hide()

	-- The box to write in, across the bottom where the other tabs have their buttons: Olympus's
	-- own, focused only by the player (his click, or his open-chat key while the tab shows: the key's
	-- section above), and no Send button (Enter sends).
	local eb = CreateFrame("EditBox", base .. "Input", p)
	eb:SetAutoFocus(false)
	eb.olympusBox = true
	eb:SetFontObject("ChatFontNormal")
	eb:SetMaxBytes(ns.Codec.CHAT_PARTS * 210 + 1) -- (three parts; Channels.Send splits the line and says when it cuts)
	if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
	-- The Communities box's border art (CommunitiesChatEditBoxTemplate).
	local left = eb:CreateTexture(nil, "BACKGROUND")
	left:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Left2")
	left:SetSize(32, 32)
	left:SetPoint("LEFT", eb, "LEFT", -10, 0)
	local right = eb:CreateTexture(nil, "BACKGROUND")
	right:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Right2")
	right:SetSize(32, 32)
	right:SetPoint("RIGHT", eb, "RIGHT", 10, 0)
	local mid = eb:CreateTexture(nil, "BACKGROUND")
	mid:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Mid2")
	if mid.SetHorizTile then mid:SetHorizTile(true) end
	mid:SetHeight(32)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	mid:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
	eb.label = eb:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	eb.label:SetPoint("LEFT", eb, "LEFT", 0, 0)
	eb.hint = eb:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	eb.hint:SetTextColor(0.5, 0.5, 0.5)
	eb.hint:SetJustifyH("LEFT")
	eb.hint:SetWordWrap(false)
	eb:SetScript("OnEnterPressed", function() ns.SafeCall("chat tab send", Submit) end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTabPressed", function() ns.SafeCall("chat tab channel", NextTier) end)
	eb:SetScript("OnTextChanged", function(self)
		if tier then
			local text = self:GetText() or ""
			ChatWindow.drafts[tier] = text ~= "" and text or nil
		end
		ns.SafeCall("chat tab box", Hint)
	end)
	eb:SetScript("OnEditFocusGained", function() ns.SafeCall("chat tab box", Hint) end)
	eb:SetScript("OnEditFocusLost", function() ns.SafeCall("chat tab box", Hint) end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	p.input = eb

	p:HookScript("OnHide", function()
		eb:ClearFocus()
		sb:ClearFocus()
		p.menu:Hide()
		p.catcher:Hide()
		p.subMenu:Hide()
		p.subCatcher:Hide()
		Untip(tipOwner)
		-- (The "Open chat" key back to the game: another tab, the window closed, the UI hidden.)
		ns.SafeCall("chat tab key", SyncKeys)
	end)
	p:HookScript("OnShow", function() ns.SafeCall("chat tab key", SyncKeys) end)
	-- The window resized (docked to a guild window that grew): the lines wrap again.
	p:HookScript("OnSizeChanged", MarkDirty)
	if h.HookScript then h:HookScript("OnSizeChanged", MarkDirty) end
	p:SetScript("OnUpdate", OnUpdate)
	return p
end

-- Where the tab's parts go in its window, from UI.lua (offsets from the window's corners, for
-- its look): places = { search = { left, right, top }, box = { left, right, top, bottom },
-- input = { left, right, y, h } }. The search row holds the switch and the gear too (DrawTop:
-- the search box ends where they begin); the box's top moves down under the pinned line, the
-- Olympus tab's line and the count of the hidden lines while they show (Render).
local function Place(p, places)
	if p.places == places then return end
	p.places = places
	local s, box, input = places.search, places.box, places.input
	p.searchLabel:ClearAllPoints()
	p.searchLabel:SetPoint("TOPLEFT", p, "TOPLEFT", s.left, s.top - 4)
	p.setTitle:ClearAllPoints()
	p.setTitle:SetPoint("TOPLEFT", p, "TOPLEFT", s.left, s.top - 3)
	p.box:ClearAllPoints()
	p.box:SetPoint("TOPLEFT", p, "TOPLEFT", box.left, box.top)
	p.box:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", box.right, box.bottom)
	local eb = p.input
	eb:ClearAllPoints()
	eb:SetHeight(input.h)
	eb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", input.left + 10, input.y)
	PlaceInput(p)
end

---------------------------------------------------------------------------
-- The tab in its window (UI.lua), and the ways to it
---------------------------------------------------------------------------

-- Dynamic-room contract. Only the Arena's canonical, stable identity is accepted: a host must
-- never turn a translated title (or arbitrary addon data) into routing. The shallow copy prevents
-- a caller from changing the tab's identity after it was admitted; the Arena remains authoritative
-- for participants, delivery lane, mute/rank checks and every line.
local function RoomSpec(spec)
	if type(spec) ~= "table" then return nil end
	local id, key = spec.id, spec.key
	if type(id) ~= "string" or id == "" or #id > 80 or id:find("[%s~|%c]") then return nil end
	if type(key) ~= "string" or key ~= "arena:" .. id then return nil end
	if spec.kind ~= "fight" and spec.kind ~= "event" and spec.kind ~= "match" then return nil end
	if spec.audience ~= "duel" and spec.audience ~= "event" then return nil end
	if spec.access ~= "members" and spec.access ~= "participants" then return nil end
	if type(spec.title) ~= "string" or Trim(spec.title) == "" then return nil end
	if spec.supportsComments ~= true then return nil end
	if type(spec.active) ~= "boolean" or type(spec.recoverable) ~= "boolean" then return nil end
	local out = {}
	for k, v in pairs(spec) do out[k] = v end
	out.title = Trim(ns.Codec.Plain(spec.title))
	if out.title == "" then return nil end
	return out
end

local function RoomNow() return ns.Now and ns.Now() or time() end
local function RoomAlive(spec, now)
	if type(spec) ~= "table" then return false end
	if spec.active == true then return true end
	local untilAt = tonumber(spec.retainUntil)
	if untilAt then return (now or RoomNow()) < untilAt end
	return spec.recoverable == true
end

local function RemoveRoom(key, clearPin)
	local r = dynamicRooms[key]
	if not r then return false end
	if clearPin then RememberPin(r, false) end
	local A = ns.ArenaChat
	if type(A) == "table" and type(A.Close) == "function" then pcall(A.Close, r.id) end
	dynamicRooms[key] = nil
	for i = #dynamicOrder, 1, -1 do if dynamicOrder[i] == key then table.remove(dynamicOrder, i) end end
	unread[key], notes[key] = nil, nil
	if tier == key then
		tier = Readable()[1]
		if tier then Remember(tier) end
		settings, stick, newCount, want = false, true, 0, nil
	end
	MarkDirty()
	return true
end

-- Called from the page's ticker as well as before a draw: even a pinned room ends locally once the
-- canonical retention ends. A pin keeps a live/recoverable fight through window closes and reloads;
-- it is not a permanent bookmark to an event that no longer exists.
function ChatWindow.PruneDynamicRooms(now)
	lastRoomPrune = GetTime and GetTime() or 0
	now = now or RoomNow()
	local gone = {}
	for key, r in pairs(dynamicRooms) do if not RoomAlive(r.spec, now) then gone[#gone + 1] = key end end
	for _, key in ipairs(gone) do RemoveRoom(key, true) end
	return #gone
end

local function RoomBy(key)
	local r = Dynamic(key)
	if r then return r end
	if type(key) == "string" then
		for _, one in pairs(dynamicRooms) do if one.id == key then return one end end
	end
end

function ChatWindow.DynamicRoom(key) return RoomBy(key) end
function ChatWindow.DynamicRooms()
	local out = {}
	for _, key in ipairs(dynamicOrder) do
		local r = dynamicRooms[key]
		if r then out[#out + 1] = { key = r.key, id = r.id, spec = r.spec, pinned = r.pinned and true or false,
			selected = tier == key, used = tonumber(r.used) or 0 } end
	end
	return out
end

-- Every pin and unpin is told (CHAT_DYNAMIC_PIN): ChatRooms.OpenMatter keeps a pin it made only
-- until the player's own pin button changes it.
function ChatWindow.PinDynamicRoom(key, on)
	local r = RoomBy(key)
	if not r then return false, "room" end
	on = on and true or false
	if on and not RoomAlive(r.spec) then return false, "expired" end
	r.pinned = on or nil
	RememberPin(r, on)
	ns.Fire("CHAT_DYNAMIC_PIN", r.key, on)
	MarkDirty()
	if Shown() then Render() end
	return true
end

-- Removes only an unpinned local tab. It sends no cancellation and changes no Arena event; opening
-- the same fight again recreates the one stable key safely.
function ChatWindow.CloseDynamicRoom(key)
	local r = RoomBy(key)
	if not r then return false, "room" end
	if r.pinned then return false, "pinned" end
	local removed = RemoveRoom(r.key, false)
	if removed and Shown() then Render(); ScrollToBottom() end
	return removed
end

local function RoomConflict(spec)
	local r = dynamicRooms[spec.key]
	if r and r.id ~= spec.id then return true end
	-- One event id cannot acquire a second key: a malformed re-open must not duplicate its tab or
	-- redirect the already-open transport.
	for key, one in pairs(dynamicRooms) do if one.id == spec.id and key ~= spec.key then return true end end
	return false
end

local function UpsertRoom(spec, pinned)
	if RoomConflict(spec) then return nil end
	local r = dynamicRooms[spec.key]
	if not r then
		r = { key = spec.key, id = spec.id, used = GetTime and GetTime() or 0 }
		dynamicRooms[spec.key] = r
		dynamicOrder[#dynamicOrder + 1] = spec.key
	end
	r.spec = spec
	if pinned then r.pinned = true end
	return r
end

-- The Arena deep-link's host. Opening transport first is deliberate: ArenaChat knows whether the
-- event exists and owns all routing/permission checks. The main Chat page only adds/selects one
-- stable local choice; no line is copied into Channels history and no global pin is touched.
function ChatWindow.OpenDynamicRoom(spec)
	spec = RoomSpec(spec)
	if not spec or not RoomAlive(spec) or RoomConflict(spec) then return false end
	local A = ns.ArenaChat
	if type(A) ~= "table" or A.missing or type(A.Open) ~= "function" then return false end
	local ok, opened = pcall(A.Open, spec.id)
	if not ok or not opened then return false end
	local pins = SavedPins(false)
	local pinned = pins and pins[spec.key] == spec.id or false
	local r = UpsertRoom(spec, pinned)
	if not r then return false end
	settings = false
	local pane = ChatWindow.Open()
	if not pane then
		if not r.pinned then RemoveRoom(r.key, false) end
		return false
	end
	SelectRoom(r.key)
	return pane
end

-- A lifecycle update never opens the window. It refreshes a room already present, or restores a
-- locally pinned room once the Arena has republished that exact key/id after a reload.
function ChatWindow.UpdateDynamicRoom(spec)
	spec = RoomSpec(spec)
	if not spec or RoomConflict(spec) then return false end
	local r = dynamicRooms[spec.key]
	local pins = SavedPins(false)
	local pinned = pins and pins[spec.key] == spec.id or false
	if not RoomAlive(spec) then
		if r then RemoveRoom(spec.key, true) elseif pinned then pins[spec.key] = nil end
		return false
	end
	if not r and not pinned then return false end
	if not r then
		local A = ns.ArenaChat
		if type(A) ~= "table" or type(A.Open) ~= "function" then return false end
		local ok, opened = pcall(A.Open, spec.id)
		if not ok or not opened then return false end
	end
	r = UpsertRoom(spec, pinned)
	if not r then return false end
	MarkDirty()
	return true
end

-- On a reload, ask the Arena for each locally pinned identity after every core file has loaded.
-- A room the client does not know yet stays only as a dormant saved pin: a later canonical
-- ARENA_CHAT_ROOM word can restore it. Match rooms are the exception: their private metadata is
-- session-only, so an unknown M id is forgotten. A known expired room is discarded by
-- UpdateDynamicRoom.
function ChatWindow.RestoreDynamicRooms()
	local pins = SavedPins(false)
	local A = ns.Arena
	if not pins then return 0 end
	local pending = {}
	for key, id in pairs(pins) do pending[#pending + 1] = { key, id } end
	table.sort(pending, function(a, b) return a[1] < b[1] end)
	local restored = 0
	for _, one in ipairs(pending) do
		local provider = one[2]:sub(1, 1) == "M" and ns.ArenaMatch or A
		local get = provider and provider.ChatRoom
		local ok, spec = false, nil
		if type(get) == "function" then ok, spec = pcall(get, one[2]) end
		if ok and type(spec) == "table" and spec.key == one[1] and spec.id == one[2]
			and ChatWindow.UpdateDynamicRoom(spec) then restored = restored + 1 end
		-- Match metadata is intentionally session-only. Unlike a published fight which may arrive
		-- later from the Arena lane, an unknown M id after reload cannot become known again.
		if one[2]:sub(1, 1) == "M" and (not ok or type(spec) ~= "table") then pins[one[1]] = nil end
	end
	if next(pins) == nil then
		local p = Saved()
		if p then p.dynamicPins = nil end
	end
	return restored
end

-- The channel it opens on: the one it showed, else the one last shown, else the first readable.
local function Pick()
	local C = ns.Channels
	if Dynamic(tier) then return tier end
	if ChatWindow.Logical(tier) and Choice(tier) then return tier end
	if tier and C.TIERS[tier] and C.CanUse(tier) then return tier end
	local p = Saved()
	local room = p and p.room
	local R = ns.ChatRooms
	if ChatWindow.Logical(room) and type(R) == "table" and type(R.Select) == "function" and R.Select(room) then return room end
	local last = p and p.tier
	if C.TIERS[last] and C.CanUse(last) then return last end
	return Readable()[1]
end

-- UI.lua, when window `h` shows its Chat tab (and on its redraws after): the tab in it, placed as
-- `places` says. Opening (it was not showing): the newest lines (not the settings), unread counts
-- from zero. Never takes the keyboard.
function ChatWindow.Attach(h, places)
	if not h or type(places) ~= "table" then return nil end
	local p = Build(h)
	frame, host = p, h
	Place(p, places)
	if not p:IsShown() then
		tier = Pick()
		if tier and ns.Channels.TIERS[tier] then ChatWindow.globalTier = tier; Remember(tier) end
		unread = {}
		settings = false
		stick, newCount, want, acc = true, 0, nil, 0
		p:Show()
		ChatWindow.LoadDraft(tier)
		Render()
		ScrollToBottom()
	end
	return p
end

-- Another tab, or the window closed: the tab goes (its boxes let go of the keyboard).
function ChatWindow.Detach(h)
	local p = h and panes[h]
	if p and p:IsShown() then p:Hide() end
end

-- The Olympus window on its Chat tab, on `want` (a channel: "A", "C", "L"), else the one last
-- shown if still readable, else the first this rank reads. Never takes the keyboard.
function ChatWindow.Open(want)
	local C = ns.Channels
	if C.missing then
		ns.Print(L.RESTART_NEEDED)
		return nil
	end
	if C.MyLevel() == 0 then
		ns.Print(L.MEMBERS_ONLY)
		return nil
	end
	local d = want ~= nil and C.TIERS[want] or nil
	if d and not C.CanUse(want) then
		ns.Print(L[d.deny]:format(L[d.label]))
		return nil
	end
	if Shown() then
		if d and want ~= tier then ChatWindow.SelectLegacy(want) end
		return frame
	end
	if d then
		tier = want
		Remember(want)
	end
	local UI = ns.UI
	if not UI or type(UI.SelectTab) ~= "function" then return nil end
	UI.SelectTab(TAB)
	if not Shown() then return nil end
	ScrollToBottom()
	return frame
end

-- The Olympus window closed, when it shows the Chat tab.
function ChatWindow.Close()
	if Shown() then host:Hide() end
end

-- Shown on that channel (or none named): the window closes. Shown on another: that one. Else:
-- the window on the Chat tab.
function ChatWindow.Toggle(want)
	if Shown() then
		if want == nil or want == tier then
			host:Hide()
			return nil
		end
		ChatWindow.SelectLegacy(want)
		return frame
	end
	return ChatWindow.Open(want)
end

function ChatWindow.Tier() return tier end
function ChatWindow.CurrentDynamicRoom() return Dynamic(tier) end
function ChatWindow.Frame() return frame end -- (the tab, in its window)
function ChatWindow.Window() return host end -- (the Olympus window it is in)

-- (Tests: a fresh session.)
function ChatWindow.Reset()
	for _, p in pairs(panes) do p:Hide() end
	panes = {}
	frame, host, tier, tipOwner = nil, nil, nil, nil
	ChatWindow.globalTier = nil
	dynamicRooms, dynamicOrder, lastRoomPrune = {}, {}, -math.huge
	dirty, dataPending, lastData = false, false, -math.huge
	unread, notes, ChatWindow.drafts = {}, {}, {}
	revealed = setmetatable({}, { __mode = "k" })
	stick, newCount, lastAt, quiet, acc, want = true, 0, 0, false, 0, nil
	settings = false
	StopWatching()
	pointer = nil
	keyButton, boundKeys, keysLater, toldLater, syncing = nil, nil, false, false, false
end

---------------------------------------------------------------------------
-- What changes it
---------------------------------------------------------------------------

ns.On("CHAT_CHANGED", function(t)
	if t == nil or t == tier then MarkDirty() end
end)
ns.On("CHAT_LINE", function(t)
	if not Shown() or not ns.Channels.TIERS[t] then return end
	if t ~= tier then
		unread[t] = (unread[t] or 0) + 1
	elseif not stick then
		newCount = newCount + 1
	end
	MarkDirty()
end)
ns.On("CHAT_ROOM_LINE", function(id)
	if not Shown() or not ChatWindow.Logical(id) then return end
	if id ~= tier then
		unread[id] = (unread[id] or 0) + 1
	elseif not stick then
		newCount = newCount + 1
	end
	MarkDirty()
end)
ns.On("CHAT_ROOM_CHANGED", function(id)
	if id == tier then MarkDirty() end
end)
ns.On("CHAT_ROOM_SELECTED", MarkDirty)
ns.On("CHAT_ROOMS_CHANGED", MarkDirty)
-- ArenaChat keeps and admits the line; the host only tracks which local room needs repainting.
-- Nothing here fires CHAT_LINE or writes Channels history, so an exclusive room cannot leak into
-- an army/global tab through the presentation adapter.
ns.On("ARENA_CHAT", function(id)
	if type(id) ~= "string" then return end
	local key = "arena:" .. id
	if not dynamicRooms[key] or not Shown() then return end
	if key ~= tier then
		unread[key] = (unread[key] or 0) + 1
	elseif not stick then
		newCount = newCount + 1
	end
	MarkDirty()
end)
ns.On("ARENA_CHAT_ROOM", function(spec)
	ns.SafeCall("chat room lifecycle", ChatWindow.UpdateDynamicRoom, spec)
end)
ns.On("LOGIN", function()
	ns.SafeCall("chat room restore", ChatWindow.RestoreDynamicRooms)
end)
-- (CHAT_SETTINGS_CHANGED, Channels.lua: a channel muted or shown in the game's chat, or sent to
-- another chat window, by /oly mute, /oly chatwindow, a line typed with /ol or the settings' own
-- clicks. The review of the page's removal: the settings stayed as they were drawn, and a stale
-- "shows in your chat" unmuted a channel /oly mute had muted.)
for _, event in ipairs({ "PIN_CHANGED", "FILTER_CHANGED", "NETOFF_CHANGED", "COUNCIL_MASK_CHANGED", "CONSENT_CHANGED",
	"CHAT_SETTINGS_CHANGED", "WATCHCHAT_CHANGED" }) do -- (1.1.6: a timeout, a lift, a deletion: WatchChat.lua)
	ns.On(event, MarkDirty)
end
-- The marks follow the census, at most once every DATA_GAP seconds.
ns.On("DATA_CHANGED", function()
	if frame and frame.subEntry then
		local entry, available = frame.subEntry, false
		if entry.kind == "moderation" then available = #ChatWindow.ModerationOptions(entry) > 0 end
		for _, current in ipairs(ChatWindow.SubtabEntries()) do if current.kind == entry.kind then available = true; break end end
		if not available or frame.subSignature ~= ChatWindow.SubMenuSignature(entry, ChatWindow.SubMenuOptions(entry)) then ChatWindow.CloseSubMenu() end
	end
	if Shown() then dataPending = true end
end)
ns.On("WATCHCHAT_CHANGED", function()
	if frame and frame.subEntry and frame.subEntry.kind == "moderation" then
		local entry = frame.subEntry
		if frame.subSignature ~= ChatWindow.SubMenuSignature(entry, ChatWindow.ModerationOptions(entry)) then ChatWindow.CloseSubMenu() end
	end
end)
-- A line of ours that did not leave (Channels.lua: the channel changed before it went, it waited
-- too long, the game refused it, we left Olympus): a note in its channel, to put it back.
ns.On("CHAT_SEND_FAILED", function(t, why, text)
	if not ns.Channels.TIERS[t] or type(text) ~= "string" or text == "" then return end
	local list = notes[t] or {}
	notes[t] = list
	list[#list + 1] = { why = WHY[why] and why or "failed", text = text }
	while #list > MAX_NOTES do table.remove(list, 1) end
	MarkDirty()
end)
ns.On("CHAT_ROOM_SEND_FAILED", function(id, why, text)
	if not ChatWindow.Logical(id) or type(text) ~= "string" or text == "" then return end
	local list = notes[id] or {}
	notes[id] = list
	list[#list + 1] = { why = WHY[why] and why or "failed", text = text }
	while #list > MAX_NOTES do table.remove(list, 1) end
	MarkDirty()
end)

-- The "Open chat" key: a change the fight held made now (the tab open then: set; gone: taken
-- off); the player's own keys changed (the game's Key Bindings) while it is bound or the tab shows.
-- (With the gamepad UI, the end of a fight that held the switch's change is when it is due.)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	toldLater = false
	if keysLater then SyncKeys(true) end
end)
ns.RegisterEvent("UPDATE_BINDINGS", function()
	if boundKeys or Shown() then SyncKeys() end
end)
-- The switch between mouse and keyboard and the gamepad UI (Blizzard_SharedXML/InputUtil.lua's
-- event, as Borders.lua reads it; not on every client): to the gamepad UI the key goes back to the
-- game at the switch, the one binding change made there; back, bound at once while the tab shows.
-- (1.1.5: through the gamepad gate, Gamepad.lua, the one step it takes in the switch's own event.)
ns.Gate.Hooks("chat-key", { now = true, park = function() SyncKeys(true, true) end, install = function() SyncKeys(true, false) end })

-- The channel last shown, kept only as a channel's letter, and the Olympus tab's line put away,
-- only as true (the first 1.1.1 build's window place and size go).
ns.On("INIT", function()
	local p = ns.db.chatWin
	if p == nil then return end
	local kept = {}
	if type(p) == "table" then
		local t = p.tier
		if type(t) == "string" and ns.Channels.TIERS[t] then kept.tier = t end
		local room = p.room
		if type(room) == "string" and #room <= 80 and room:match("^[%l%d:]+$") then kept.room = room end
		if p.noTabLine == true then kept.noTabLine = true end
		if type(p.dynamicPins) == "table" then
			local keys = {}
			for key, id in pairs(p.dynamicPins) do
				if type(key) == "string" and type(id) == "string" and key == "arena:" .. id
					and id ~= "" and #id <= 80 and not id:find("[%s~|%c]") then keys[#keys + 1] = key end
			end
			table.sort(keys)
			local pins = {}
			for i = 1, math.min(#keys, 10) do pins[keys[i]] = p.dynamicPins[keys[i]] end
			if next(pins) then kept.dynamicPins = pins end
		end
	end
	ns.db.chatWin = next(kept) ~= nil and kept or nil
end)
