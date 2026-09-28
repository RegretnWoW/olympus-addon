local ADDON, ns = ...
local L = ns.L

-- Content of the four tabs. Each tab gives: column headers (optional), a list of lines,
-- a detail box (title + text, like the guild "Message of the Day" box) and three buttons.
-- The renderer draws lines with Blizzard fonts; a line is either
--   { text, right, indent, header, color, onClick, tooltip = function(tt) end }
-- or a table row { cols = { ... } } drawn with the tab's column layout. `key` (a player's
-- name) marks a line that opens a person: the HD window keeps it lit while it is open.

local Views = {}
ns.Views = Views

local ROW_H = 16
local ROW_H_HD = 20 -- the Guild & Communities roster's rows (CommunitiesMemberList.xml)
local ITEM, ITEM_GAP = 30, 2 -- an item on an items row (line.items) without the game's button template (37 with it)
local expanded = {}
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13|t "
local ASSIST = "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:12:12|t "

local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Red(s) return "|cffff4040" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
Views.Green, Views.Grey, Views.Red, Views.Gold = Green, Grey, Red, Gold

-- Names and guilds from other players' reports: shown as plain text, whatever they carry
-- (0.9.2; Comm.lua already strips every escape code from what arrives).
local Plain = ns.Codec.Plain

local function ClassColored(name, classFile)
	name = Plain(name)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return c and ("|c%s%s|r"):format(c.colorStr, name) or name
end

-- `dim`: what an old report said (older than Data.FRESH), all grey, as its guild is in the tree.
local function Presence(online, days, dim)
	if online then return (dim and Grey or Green)(L.ONLINE_NOW) end
	if not days or days < 1 then return Grey(L.OFFLINE_TODAY) end
	local d = math.floor(days)
	local text = L.OFFLINE_DAYS:format(d)
	if d >= (ns.db.warnDays or 3) then return (dim and Grey or Red)(text .. " !") end
	return Grey(text)
end

---------------------------------------------------------------------------
-- Column layouts, as fractions of the list width (so they follow the window size)
---------------------------------------------------------------------------

Views.COLUMNS = {
	census = {
		{ key = "COL_GUILD", sort = "name", x = 0.00, w = 0.40 },
		{ key = "COL_MEMBERS", sort = "members", x = 0.40, w = 0.20, justify = "RIGHT" },
		{ key = "COL_ONLINE", sort = "online", x = 0.60, w = 0.16, justify = "RIGHT" },
		{ key = "COL_LORD", sort = "lord", x = 0.76, w = 0.24 },
	},
	heraldry = {
		{ key = "COL_NAME", x = 0.00, w = 0.30 },
		{ key = "COL_GUILD", x = 0.30, w = 0.32 },
		{ key = "COL_TABARD", x = 0.63, w = 0.24 },
		{ key = "COL_WHEN", x = 0.87, w = 0.13, justify = "RIGHT" },
	},
}

---------------------------------------------------------------------------
-- Renderer
---------------------------------------------------------------------------

-- Rows follow the look of the window they are in (content.style, see UI.lua): the old one's,
-- or the HD one's like the Guild & Communities roster (20 tall, its row background on the
-- rows that can be clicked, its gold bar under the mouse and under the person open).
local function Row(content, i)
	content.rows = content.rows or {}
	local r = content.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	if content.style == "hd" then
		r:SetHeight(ROW_H_HD)
		r.stripe = r:CreateTexture(nil, "BACKGROUND")
		r.stripe:SetAllPoints()
		r.stripe:SetTexture("Interface\\GuildFrame\\GuildFrame")
		r.stripe:SetTexCoord(0.36230469, 0.38183594, 0.95898438, 0.99804688)
		r:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
	else
		r:SetHeight(ROW_H)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.35)
	end
	r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.left:SetJustifyH("LEFT")
	r.left:SetWordWrap(false)
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetPoint("RIGHT", -2, 0)
	r.right:SetJustifyH("RIGHT")
	r.right:SetWordWrap(false)
	r.cols = {}
	for c = 1, 4 do
		local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		r.cols[c] = fs
	end
	r.index = i
	r:SetScript("OnClick", function(self)
		if not self.line then return end
		-- HD: the person opened stays lit, like the roster's selected member.
		if content.style == "hd" and self.line.key then ns.SafeCall("view select", Views.Select, content, self.line.key) end
		-- Where the row was clicked, for the redraw its click causes (UI.lua keeps it in place):
		-- its place in the list, the list's offset then (the list is the scroll frame's child).
		local scroll = content:GetParent()
		local offset = scroll and scroll.GetVerticalScroll and scroll:GetVerticalScroll()
		content.click = { index = self.index, top = self.top or 0, lines = content.lineCount or 0, t = GetTime(),
			offset = type(offset) == "number" and offset or nil }
		if self.line.onClick then ns.SafeCall("view click", self.line.onClick) end
		if ns.UI.Clicked then ns.UI.Clicked() end
	end)
	r:SetScript("OnEnter", function(self)
		if not (self.line and self.line.tooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.SafeCall("view tooltip", self.line.tooltip, GameTooltip)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	content.rows[i] = r
	return r
end

-- An item's icon: the snapshot's, or the client's for the id.
local function ItemIcon(it)
	if it.icon then return it.icon end
	if GetItemInfoInstant then
		local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, it.id)
		if ok and icon then return icon end
	end
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, it.id)
		if ok and icon then return icon end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- One slot of an items row: the game's own item button (ItemButtonTemplate: the slot, the
-- icon, the count, the quality border) where the client has it, the same made here where
-- not; the item's own tooltip on hover, like a bag's.
local function ItemButton(r, k)
	local ok, b = pcall(CreateFrame, "Button", nil, r, "ItemButtonTemplate")
	if ok and b and b.icon and SetItemButtonTexture then
		b.blizzard = true
		r.itemSize = 37
	else
		if ok and b then b:Hide() end
		b = CreateFrame("Button", nil, r)
		b:SetSize(ITEM, ITEM)
		b.slot = b:CreateTexture(nil, "BACKGROUND")
		b.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
		b.slot:SetTexCoord(0.2, 0.8, 0.2, 0.8)
		b.slot:SetAllPoints()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		r.itemSize = r.itemSize or ITEM
	end
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function(self)
		-- Shift-click: the link into the chat box, as in a bag (not with the gamepad UI: its
		-- chat box would be blocked, see Dialog.lua).
		local it = self.item
		if not it or not IsShiftKeyDown or not IsShiftKeyDown() or ns.GamepadUI() or not ChatEdit_InsertLink then return end
		local link = it.link
		if not link and GetItemInfo then local okInfo, _, l = pcall(GetItemInfo, it.id); if okInfo then link = l end end
		if link then pcall(ChatEdit_InsertLink, link) end
	end)
	b:SetScript("OnEnter", function(self)
		local it = self.item
		if not it then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = false
		if it.link and GameTooltip.SetHyperlink then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) end
		if not ok and it.id and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id) end
		if not ok then GameTooltip:AddLine("#" .. tostring(it.id), 1, 1, 1) end
		if (it.n or 0) > 1 then GameTooltip:AddLine("x" .. it.n, 0.8, 0.8, 0.8) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.items = r.items or {}
	r.items[k] = b
	return b
end

-- A slot's item (nil: empty), drawn the way the game draws it.
local function SetSlot(b, it)
	b.item = it
	if b.blizzard then
		SetItemButtonTexture(b, it and ItemIcon(it) or nil)
		if SetItemButtonCount then SetItemButtonCount(b, it and it.n or 0) end
		if SetItemButtonQuality then
			local quality
			if it and GetItemInfo then
				local ok, _, _, q = pcall(GetItemInfo, it.link or it.id)
				if ok then quality = q end
			end
			pcall(SetItemButtonQuality, b, quality, it and (it.link or it.id) or nil)
		end
	else
		b.icon:SetTexture(it and ItemIcon(it) or nil)
		b.icon:SetShown(it ~= nil)
		b.count:SetText(it and (it.n or 0) > 1 and tostring(it.n) or "")
	end
end

function Views.LayoutColumns(fontStrings, layout, width, offset)
	for c, fs in ipairs(fontStrings) do
		local col = layout and layout[c]
		if col then
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", (offset or 0) + col.x * width, 0)
			fs:SetWidth(col.w * width - 4)
			fs:SetJustifyH(col.justify or "LEFT")
			fs:Show()
		else
			fs:Hide()
		end
	end
end

-- The row whose line has `key` stays lit (nil: none). HD rows only.
function Views.Select(content, key)
	content.selectedKey = key
	for _, r in ipairs(content.rows or {}) do
		if key and r.line and r.line.key == key then r:LockHighlight() else r:UnlockHighlight() end
	end
end

function Views.ClearSelection(content) Views.Select(content, nil) end

function Views.Render(content, lines, layout)
	local width = content:GetWidth()
	local hd = content.style == "hd"
	local rowH = hd and ROW_H_HD or ROW_H
	local y = -2
	for i, line in ipairs(lines) do
		local r = Row(content, i)
		r.line = line
		r.top = -y -- how far down the list the row starts (UI.lua keeps the list's place)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		r:SetWidth(width)
		local height = rowH
		if line.items then
			-- Items in a grid. line.slots and line.columns: a bank tab as the game draws it (every
			-- slot, empty ones too, items where they sit: it.s); without them, the items one after
			-- another, as many per row as fit. The row grows to hold them all.
			r.left:Hide()
			r.right:Hide()
			for c = 1, 4 do r.cols[c]:Hide() end
			if not (r.items and r.items[1]) then ItemButton(r, 1) end
			local size = (r.itemSize or ITEM) + ITEM_GAP
			local columns = line.columns or math.max(1, math.floor((width - 8) / size))
			local slots = line.slots or #line.items
			local bySlot = {}
			for k, it in ipairs(line.items) do
				local s = line.slots and tonumber(it.s) or k
				if s and s >= 1 and s <= slots then bySlot[s] = it end
			end
			for k = 1, slots do
				local b = r.items[k] or ItemButton(r, k)
				SetSlot(b, bySlot[k])
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 4 + ((k - 1) % columns) * size, -2 - math.floor((k - 1) / columns) * size)
				b:Show()
			end
			for k = slots + 1, #r.items do r.items[k]:Hide() end
			height = math.ceil(math.max(1, slots) / columns) * size + 4
		elseif line.cols then
			r.left:Hide()
			r.right:Hide()
			Views.LayoutColumns(r.cols, layout, width - 4, 4)
			for c = 1, 4 do r.cols[c]:SetText(line.cols[c] or "") end
			local a = line.dim and 0.45 or 1
			for c = 1, 4 do r.cols[c]:SetAlpha(a) end
		else
			for c = 1, 4 do r.cols[c]:Hide() end
			r.left:Show()
			r.right:Show()
			-- line.font: a font object by name (the Throne's dark ink on parchment), if the client has it.
			local font = line.font and _G[line.font] and line.font or nil
			r.left:SetFontObject(font or (line.header and "GameFontNormal" or (line.color or "GameFontHighlightSmall")))
			r.right:SetFontObject(font or "GameFontHighlightSmall")
			r.left:ClearAllPoints()
			r.left:SetPoint("LEFT", 4 + (line.indent or 0) * 12, 0)
			r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
			r.left:SetText(line.text or "")
			r.right:SetText(line.right or "")
		end
		if not line.items then for k = 1, #(r.items or {}) do r.items[k]:Hide() end end
		r:SetHeight(height)
		r:EnableMouse(line.onClick ~= nil or line.tooltip ~= nil)
		if hd then
			r.stripe:SetShown(line.cols ~= nil or line.onClick ~= nil)
			if line.key and line.key == content.selectedKey then r:LockHighlight() else r:UnlockHighlight() end
		end
		r:Show()
		y = y - (line.header and height + 4 or height)
		if line.gapAfter then y = y - 6 end
	end
	for i = #lines + 1, #(content.rows or {}) do content.rows[i]:Hide() end
	content.lineCount = #lines
	content:SetHeight(-y + 8)
end

-- The last row clicked in `content` ({ index, top, lines, t }: where it started, how many lines
-- the list had, when), once: taken by the redraw that follows (UI.lua).
function Views.TakeClick(content)
	local click = content.click
	content.click = nil
	return click
end

-- The id of a guild's row in the Realm tree (line.id): a tab opened on it shows it (UI.SelectTab).
function Views.GuildId(name) return "guild:" .. tostring(name) end

---------------------------------------------------------------------------
-- Shared tooltips
---------------------------------------------------------------------------

local function GuildTooltip(e)
	return function(tt)
		local g = e.g
		tt:AddLine("<" .. Plain(e.name) .. ">", 0.25, 1, 0.25)
		tt:AddDoubleLine(L.COL_MEMBERS, ns.FormatNumber(g.total), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.COL_ONLINE, ns.FormatNumber(g.online), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.LORD, Plain(g.leader or "?"), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.VACANCIES, ns.FormatNumber(math.max(0, 1000 - (g.total or 0))), 1, 0.82, 0, 1, 1, 1)
		if g.avgLevel and g.avgLevel > 0 then tt:AddDoubleLine(L.AVG_LEVEL, ("%.1f"):format(g.avgLevel), 1, 0.82, 0, 1, 1, 1) end
		tt:AddDoubleLine(L.INACTIVE_30, ns.FormatNumber(g.inactive30 or 0), 1, 0.82, 0, 1, 1, 1)
		local classes = {}
		for code, n in pairs(g.classes or {}) do classes[#classes + 1] = { code, n } end
		table.sort(classes, function(a, b) return a[2] > b[2] end)
		if #classes > 0 then
			local parts = {}
			for _, c in ipairs(classes) do
				local file = ns.CLASS_FILES[c[1]]
				local label = (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or c[1]
				parts[#parts + 1] = ClassColored(label .. " " .. c[2], file)
			end
			tt:AddLine(" ")
			for i = 1, #parts, 3 do tt:AddLine(table.concat({ parts[i], parts[i + 1], parts[i + 2] }, "   ")) end
		end
		local zones = {}
		for key, n in pairs(g.zones or {}) do zones[#zones + 1] = { key, n } end
		table.sort(zones, function(a, b) return a[2] > b[2] end)
		if #zones > 0 then
			tt:AddLine(" ")
			for i = 1, math.min(5, #zones) do
				tt:AddDoubleLine(ns.Zones.NameForKey(zones[i][1]), ns.FormatNumber(zones[i][2]), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L.REPORTED_BY:format(g.reporter or "?", ns.Ago(g.t)), 0.6, 0.6, 0.6)
		if not e.fresh then tt:AddLine(L.STALE, 1, 0.4, 0.4) end
	end
end

-- A guild only /who has seen: all we know is how many of it were online.
local function SeenTooltip(e)
	return function(tt)
		tt:AddLine("<" .. e.name .. ">", 0.6, 0.6, 0.6)
		tt:AddDoubleLine(L.SEEN_ONLINE, ns.FormatNumber(e.online) .. (e.capped and "+" or ""), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.SEEN_WHEN, ns.Ago(e.t), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine(L.SEEN_TIP, 0.8, 0.8, 0.8, true)
		if e.capped then tt:AddLine(L.SEEN_CAPPED_TIP, 0.8, 0.8, 0.8, true) end
	end
end

-- How far the round of /who searches got (Who.lua), as grey lines under a list.
local function WhoStatus(lines)
	for _, text in ipairs(ns.Who.StatusLines() or {}) do lines[#lines + 1] = { text = Grey(text) } end
end

---------------------------------------------------------------------------
-- Census
---------------------------------------------------------------------------

Views.sort = { key = "members", desc = true }

local SORTERS = {
	name = function(e) return e.name:lower() end,
	members = function(e) return e.g.total or 0 end,
	online = function(e) return e.g.online or 0 end,
	lord = function(e) return (e.g.leader or ""):lower() end,
}

function Views.SortBy(key)
	if Views.sort.key == key then
		Views.sort.desc = not Views.sort.desc
	else
		Views.sort = { key = key, desc = key == "members" or key == "online" }
	end
end

local function CensusLines(s)
	local lines = {}
	-- The King's Agenda, for the whole army (King.lua).
	local a = ns.King and ns.King.Agenda and ns.King.Agenda()
	if a then
		lines[#lines + 1] = { text = Gold(L.THRONE_AGENDA_LINE:format(a.title, math.max(0, math.ceil((a.at - ns.Now()) / 60)), a.zone)), gapAfter = true }
	end
	-- The King holds court in our zone: one click asks for an audience (Court.lua).
	local court = ns.Court and ns.Court.Line and ns.Court.Line()
	if court then lines[#lines + 1] = court end
	-- While the King is online: one click asks for an invite to his layer (Hop.lua).
	for _, hop in ipairs(ns.Hop and ns.Hop.KingLines and ns.Hop.KingLines() or {}) do lines[#lines + 1] = hop end
	local get = SORTERS[Views.sort.key] or SORTERS.members
	local guilds = {}
	for i, e in ipairs(s.guilds) do guilds[i] = e end
	table.sort(guilds, function(a, b)
		if a.fresh ~= b.fresh then return a.fresh end
		local va, vb = get(a), get(b)
		if va == vb then return a.name < b.name end
		if Views.sort.desc then return va > vb end
		return va < vb
	end)
	for _, e in ipairs(guilds) do
		local g = e.g
		local leader = g.leader and ((g.leaderOnline and "|cff40ff40" or "|cff9d9d9d") .. Plain(g.leader) .. "|r") or Grey("?")
		lines[#lines + 1] = {
			cols = { Plain(e.name), ns.FormatNumber(g.total), Green(ns.FormatNumber(g.online)), leader },
			dim = not e.fresh,
			tooltip = GuildTooltip(e),
			onClick = function()
				-- Opened in the Realm, and the Realm opens on it (UI.KeepPlace).
				expanded[e.name] = true
				ns.UI.SelectTab("realm", Views.GuildId(e.name))
			end,
		}
	end
	if #lines == 0 then lines[1] = { text = Grey(L.EMPTY) } end
	-- Guilds seen with /who that nobody reports: grey, after every reported guild, and in no
	-- total (Data.Summary keeps them apart). Members and Lord are unknown.
	for _, e in ipairs(s.seen or {}) do
		local online = ns.FormatNumber(e.online) .. (e.capped and "+" or "")
		lines[#lines + 1] = { cols = { Grey(e.name), Grey("?"), Grey(online), Grey(L.NO_ADDON) }, tooltip = SeenTooltip(e) }
	end
	if #(s.seen or {}) > 0 then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = Grey(L.SEEN_HINT) }
	end
	WhoStatus(lines)
	-- The addon's author online: Report a bug reaches him directly (Workshop.lua).
	local author = ns.Workshop and ns.Workshop.AuthorOnline and ns.Workshop.AuthorOnline() and ns.Workshop.AuthorName()
	if author then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = Grey(L.AUTHOR_ONLINE:format(ns.DisplayName(author))) }
	end
	return lines
end

local function CensusDetail(s)
	local where = {}
	for i = 1, math.min(6, #s.zoneList) do
		local z = s.zoneList[i]
		where[#where + 1] = ns.Zones.NameForKey(z.key) .. " " .. Gold(ns.FormatNumber(z.count))
	end
	local text = #where > 0 and table.concat(where, "  ·  ") or L.NO_ZONES
	local conts = {}
	if ns.Map.ContinentTotals then
		local totals = ns.Map.ContinentTotals(s)
		for id, n in pairs(totals) do conts[#conts + 1] = { name = ns.Zones.NameForKey("m" .. id), n = n } end
		table.sort(conts, function(a, b) return a.n > b.n end)
	end
	local title = L.WHERE
	if #conts > 0 then
		local parts = {}
		for _, c in ipairs(conts) do parts[#parts + 1] = c.name .. " " .. ns.FormatNumber(c.n) end
		title = L.WHERE .. ":  |cffffffff" .. table.concat(parts, "  ·  ") .. "|r"
	end
	return title, text .. "\n" .. Grey(ns.UI.StatusLine())
end

---------------------------------------------------------------------------
-- The Realm
---------------------------------------------------------------------------

-- The King's guild: the one named exactly "Olympus" (the addon's King everywhere else, the
-- Throne, the layer hop). No such guild reporting: no King line, never another guild's Lord.
local function King(guilds)
	for _, e in ipairs(guilds) do
		if ns.IsKingGuild(e.name) and e.g.leader then return e end
	end
	return nil
end

-- The members of a guild online now, besides its Lord and Captains: our own guild from our
-- roster, any other from /who (the round, and the guild's own search when its row was
-- opened, Who.SearchGuild). Reports carry no member lists: a thousand names per guild would
-- not fit on the channel. { name, level, class (code), zone (key), rank } each, by rank then
-- level.
Views.MAX_MEMBERS = 25
local allMembers = {} -- [guild] = true: its whole list shown ("... and N more" clicked)
function Views.MembersOf(guild, g)
	local skip = {}
	if g and g.leader then skip[ns.ShortName(g.leader)] = true end
	for _, o in ipairs(g and g.officers or {}) do if o.name then skip[ns.ShortName(o.name)] = true end end
	local out, fromWho = {}, guild ~= GetGuildInfo("player")
	if not fromWho then
		for _, m in ipairs(ns.Roster.online or {}) do
			if not skip[ns.ShortName(m.name)] then out[#out + 1] = m end
		end
		return out, false
	end
	local sweep = ns.Who and ns.Who.sweep
	local own = ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(guild)
	for _, source in ipairs({ own or {}, sweep and sweep.list or {} }) do
		for _, p in ipairs(source) do
			local short = p.name and ns.ShortName(p.name)
			if p.guild == guild and short and not skip[short] then
				skip[short] = true -- each once, the guild's own search first
				out[#out + 1] = { name = ns.DisplayName(ns.FullName(p.name)), level = p.level, class = ns.Roster.ClassCode(p.class),
					zone = p.zone and ns.Zones.KeyForName(p.zone) }
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return a.name < b.name
	end)
	return out, true
end

---------------------------------------------------------------------------
-- The Olympus chats, read in the Realm tab: the last lines of each channel our rank reads
-- (Channels.History), newest first, even what was said while the window was closed.
---------------------------------------------------------------------------

local chatTier -- the channel shown instead of the Realm tree, or nil

function Views.ChatShown() return chatTier ~= nil end
function Views.ChatTier() return chatTier end
-- Another tab opened: the Realm opens on its tree again next time.
function Views.CloseChat() chatTier = nil end
function Views.ShowChat(tier)
	chatTier = tier
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function ChatTiers()
	local out = {}
	for _, tier in ipairs(ns.Channels.ORDER or {}) do
		if ns.Channels.CanUse(tier) then out[#out + 1] = tier end
	end
	return out
end

-- Every line the history keeps (Channels.HISTORY): lines kept but never shown were lost all the same.
Views.CHAT_SHOWN = ns.Channels and ns.Channels.HISTORY or 100
local function ChatLines()
	local C = ns.Channels
	local lines = { { text = Gold(L.CHATS_BACK), onClick = function() Views.ShowChat(nil) end, gapAfter = true } }
	local tiers = ChatTiers()
	if not C.TIERS[chatTier] or not C.CanUse(chatTier) then chatTier = tiers[1] end
	if not chatTier then
		lines[#lines + 1] = { text = Grey(L.CHATS_EMPTY) }
		return lines
	end
	-- One line per channel we read: the one shown is lit.
	for _, tier in ipairs(tiers) do
		local label = L[C.TIERS[tier].label]
		local n = #C.History(tier)
		lines[#lines + 1] = {
			header = tier == chatTier,
			text = (tier == chatTier and Gold("> [" .. label .. "]") or ("   [" .. label .. "]")),
			right = Grey(tostring(n)),
			onClick = tier ~= chatTier and function() Views.ShowChat(tier) end or nil,
		}
	end
	lines[#lines].gapAfter = true
	local tierDef = C.TIERS[chatTier]
	lines[#lines + 1] = {
		text = Green(L.CHATS_WRITE:format(L[tierDef.label])),
		onClick = function()
			-- (The gamepad UI: an Olympus window, the game's chat box would be blocked; UI.lua.)
			if ns.GamepadUI() then return ns.UI.ChatWindow(chatTier, L[tierDef.label]) end
			if ChatFrame_OpenChat then ChatFrame_OpenChat(tierDef.slash .. " ") end
		end,
		gapAfter = true,
	}
	local history = C.History(chatTier)
	if #history == 0 then lines[#lines + 1] = { text = Grey(L.CHATS_EMPTY) } end
	for i = #history, math.max(1, #history - Views.CHAT_SHOWN + 1), -1 do
		local e = history[i]
		local who = ns.DisplayName(e.sender) or "?"
		lines[#lines + 1] = {
			text = C.FormatLine(chatTier, e.sender, e.guild, e.class, e.text),
			right = Grey(ns.Ago(e.t)),
			onClick = not e.mine and function()
				if ns.GamepadUI() then return ns.UI.WhisperWindow(ns.TellName(e.sender) or who) end
				if ChatFrame_SendTell then ChatFrame_SendTell(ns.TellName(e.sender) or who) end
			end or nil,
			tooltip = function(tt)
				tt:AddLine(who .. "  <" .. Plain(e.guild or "?") .. ">", 1, 0.82, 0)
				tt:AddLine(ns.Codec.SanitizeChat(e.text), 1, 1, 1, true)
				if not e.mine then tt:AddLine(L.CHATS_LINE_TIP:format(who), 0.6, 0.6, 0.6) end
			end,
		}
	end
	return lines
end

---------------------------------------------------------------------------
-- The High Council in the Realm (0.9.9, Max's): under the King and the Treasurer, the
-- moderators by department with their titles (Workshop.CouncilTree), for whoever may see them
-- (ns.CouncilVisible: until launch, the councillors and the author alone).
---------------------------------------------------------------------------

local COUNCIL_ROW = {} -- its open/closed key in `expanded`: no guild's name can be a table
-- The eye that shows the councillors' names on the King's screen (a game icon, Interface\Icons).
Views.EYE_ICON = "Interface\\Icons\\INV_Misc_Eye_01"

-- What the census knows of these names (a set of short names, lower case): each guild's Lord
-- and Captains from a fresh report, then who was seen online (our roster, /who), then the Lords
-- and Captains of older reports, the first found. (An old report last: days old, it must not
-- hide someone seen online now.) Short name -> a person as the rows open them, and the set of
-- those only an old report knows.
local function Known(s, wanted)
	local out, old = {}, {}
	local function Add(guild, p, stale)
		local key = type(p.name) == "string" and ns.ShortName(p.name):lower()
		if key and wanted[key] and not out[key] then
			p.guild = guild
			out[key], old[key] = p, stale or nil
		end
	end
	local function Reports(fresh)
		for _, e in ipairs(s.guilds) do
			local g = e.g
			if e.fresh == fresh then
				if g.leader then
					Add(e.name, { name = g.leader, realm = g.realm, class = g.leaderClass, level = g.leaderLevel, zone = g.leaderZone,
						rank = L.LORD, online = g.leaderOnline, days = g.leaderDays }, not fresh)
				end
				for _, o in ipairs(g.officers or {}) do
					Add(e.name, { name = o.name, realm = g.realm, class = o.class, level = o.level, zone = o.zone, rank = L.CAPTAIN,
						online = o.online, days = o.days }, not fresh)
				end
			end
		end
	end
	Reports(true)
	local mine = GetGuildInfo("player")
	for _, m in ipairs(mine and ns.Roster.online or {}) do
		Add(mine, { name = m.name, class = m.class, level = m.level, zone = m.zone, rank = m.rank, online = true })
	end
	-- (As Views.MembersOf reads /who: the guild's own search, then the round.)
	local sweep = ns.Who and ns.Who.sweep
	for _, e in ipairs(s.guilds) do
		local own = ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(e.name)
		for _, source in ipairs({ own or {}, sweep and sweep.list or {} }) do
			for _, p in ipairs(source) do
				if p.guild == e.name and p.name then
					Add(e.name, { name = ns.DisplayName(ns.FullName(p.name)), level = p.level, class = ns.Roster.ClassCode(p.class),
						zone = p.zone and ns.Zones.KeyForName(p.zone), online = true })
				end
			end
		end
	end
	Reports(false)
	return out, old
end

local function Council(s) return "|c" .. ns.HIGH_COUNCIL_COLOR .. s .. "|r" end

local function CouncilLines(lines, s)
	local loose, depts = ns.Workshop.CouncilTree()
	local n = #loose
	for _, d in ipairs(depts) do n = n + #d.members end
	if n == 0 then return end
	local open = expanded[COUNCIL_ROW]
	lines[#lines + 1] = {
		text = (open and "[-] " or "[+] ") .. ns.HIGH_COUNCIL_MARK .. " " .. Council(L.COUNCIL_CENSUS:format(n)),
		onClick = function()
			expanded[COUNCIL_ROW] = not expanded[COUNCIL_ROW] or nil
			ns.UI.Refresh()
		end,
		tooltip = function(tt)
			tt:AddLine(L.COUNCIL_CENSUS:format(n), 0.69, 0.28, 0.97)
			tt:AddLine(L.COUNCIL_CENSUS_TIP, 1, 1, 1, true)
		end,
	}
	if not open then return end
	-- The King's screen (his stream): the names hidden until he clicks the eye, and hidden again
	-- on the next click (ns.CouncilMasked, Core.lua).
	local masked = ns.CouncilMasked()
	if ns.KingsScreen() then
		local label = masked and L.COUNCIL_NAMES_SHOW or L.COUNCIL_NAMES_HIDE
		lines[#lines + 1] = {
			indent = 1,
			text = "|T" .. Views.EYE_ICON .. ":0|t " .. Gold(label),
			onClick = function()
				local show = not ns.CouncilNamesShown()
				ns.SetCouncilNamesShown(show)
				if not show and ns.UI.CloseCouncilCards then ns.UI.CloseCouncilCards() end
				ns.UI.Refresh()
			end,
			tooltip = function(tt)
				tt:AddLine(label, 1, 0.82, 0)
				tt:AddLine(L.COUNCIL_NAMES_TIP, 1, 1, 1, true)
			end,
		}
	end
	local wanted = {}
	for _, m in ipairs(loose) do wanted[m.name:lower()] = true end
	for _, d in ipairs(depts) do for _, m in ipairs(d.members) do wanted[m.name:lower()] = true end end
	local known, old = Known(s, wanted)
	-- "<mark><own icon> Name - Title": where the census knows them, when they were last on, and a
	-- click opens what it knows. Hidden (the King's stream): "<mark> Name****", the title, where
	-- they are, and no click (the card would carry the whole name).
	local function Member(m, indent)
		local p = known[m.name:lower()]
		local person = p or { name = m.name }
		lines[#lines + 1] = {
			key = not masked and person.name or nil,
			indent = indent,
			text = (masked and (ns.HIGH_COUNCIL_MARK .. " " .. Council(ns.MaskName(Plain(m.name))))
					or (ns.CouncilMark(m.name) .. " " .. Council(Plain(m.name))))
				.. (m.title and (" - " .. Grey(Plain(m.title))) or ""),
			right = p and Presence(p.online, p.days, old[m.name:lower()]) or nil,
			onClick = not masked and function() ns.UI.ShowPerson(person) end or nil,
		}
	end
	for _, m in ipairs(loose) do Member(m, 1) end
	for _, d in ipairs(depts) do
		local icon = ns.CouncilIconTexture(d.icon)
		lines[#lines + 1] = { indent = 1, text = (icon and ("|T" .. icon .. ":0|t ") or "") .. Gold(Plain(d.name)) }
		for _, m in ipairs(d.members) do Member(m, 2) end
	end
end

local function RealmLines(s)
	if chatTier then return ChatLines() end
	local lines = {}
	-- A councillor's mark and own icon after their name in the rows below (0.9.9), for whoever
	-- may see the council here; none on the King's screen while the names are hidden (his
	-- stream: a whole name next to the mark would give the councillor away).
	local councilShown = ns.CouncilVisible()
	local councilTagged = councilShown and not ns.CouncilMasked()
	local function Tag(name, home)
		local full = ns.FullName(name, home)
		if not councilTagged or not ns.IsHighCouncillor(full) then return "" end
		return " " .. ns.CouncilMark(full)
	end
	-- The King holds court in our zone (Court.lua), then his layer (Hop.lua).
	local court = ns.Court and ns.Court.Line and ns.Court.Line()
	if court then lines[#lines + 1] = court end
	for _, hop in ipairs(ns.Hop and ns.Hop.KingLines and ns.Hop.KingLines() or {}) do lines[#lines + 1] = hop end
	-- The King (and his Hands): Summon the Lords, and who answered (King.lua). While it is
	-- fresh, each Lord and Captain in the tree carries a ready-check mark.
	for _, l in ipairs(ns.King and ns.King.RollCallLines and ns.King.RollCallLines() or {}) do lines[#lines + 1] = l end
	local function Mark(name, home, online)
		return ns.King and ns.King.RollCallMark and ns.King.RollCallMark(ns.FullName(name, home), online) or ""
	end
	local king = King(s.guilds)
	if king then
		lines[#lines + 1] = {
			header = true,
			text = CROWN .. L.KING .. ": " .. Gold(Plain(king.g.leader or "?")),
			right = Presence(king.g.leaderOnline, king.g.leaderDays),
			tooltip = GuildTooltip(king),
		}
		-- The Treasurer of Olympus, under the King: when that guild's report has him (the
		-- Horde's <Olympus> and other realms' have no Treasurer of theirs).
		local t
		for _, o in ipairs(king.name:lower() == "olympus" and king.g.officers or {}) do -- (the Treasurer: <Olympus>, the Alliance's)
			if ns.IsTreasurer(o.name, king.name) then t = o end
		end
		if t then
			local person = { name = t.name, realm = king.g.realm, guild = king.name, class = t.class, level = t.level, zone = t.zone,
				rank = L.CAPTAIN, online = t.online, days = t.days }
			lines[#lines + 1] = {
				key = t.name,
				text = ns.COIN .. L.TREASURER .. ": " .. Gold(Plain(t.name)),
				right = Presence(t.online, t.days),
				onClick = function() ns.UI.ShowPerson(person) end,
			}
			-- The treasury, when he shares it (Treasury.lua).
			local shared = ns.Treasury and ns.Treasury.RealmText and ns.Treasury.RealmText()
			if type(shared) == "string" then lines[#lines + 1] = { indent = 1, text = Grey(shared) } end
		end
	end
	-- The High Council, under them (0.9.9).
	if councilShown then CouncilLines(lines, s) end
	-- The Olympus chats, one click away (the channels our rank reads), above the guilds.
	if #ChatTiers() > 0 then
		if lines[#lines] then lines[#lines].gapAfter = true end
		lines[#lines + 1] = {
			text = "|TInterface\\ChatFrame\\UI-ChatIcon-Chat-Up:14:14|t " .. Gold(L.CHATS_LINK), gapAfter = true,
			onClick = function() Views.ShowChat(ChatTiers()[1]) end,
			tooltip = function(tt)
				tt:AddLine(L.CHATS_LINK, 1, 0.82, 0)
				tt:AddLine(L.CHATS_TIP, 1, 1, 1, true)
			end,
		}
	end
	if #s.guilds == 0 then lines[#lines + 1] = { text = Grey(L.EMPTY) } end
	for _, e in ipairs(s.guilds) do
		local g = e.g
		local open = expanded[e.name]
		lines[#lines + 1] = {
			id = Views.GuildId(e.name),
			text = (open and "[-] " or "[+] ") .. Green("<" .. Plain(e.name) .. ">") .. " " .. Plain(g.leader or "?"),
			right = Presence(g.leaderOnline, g.leaderDays),
			onClick = function()
				expanded[e.name] = not expanded[e.name] or nil
				-- Opened: a /who for that guild alone lists who of it is online (a click, so the
				-- game allows it). Our own guild is in our roster already.
				if expanded[e.name] and e.name ~= GetGuildInfo("player") then ns.SafeCall("guild who", ns.Who.SearchGuild, e.name) end
				ns.UI.Refresh()
			end,
			tooltip = GuildTooltip(e),
			color = e.fresh and "GameFontHighlightSmall" or "GameFontDisableSmall",
		}
		if open then
			if g.leader then
				local lord = { name = g.leader, realm = g.realm, class = g.leaderClass, level = g.leaderLevel, zone = g.leaderZone,
					guild = e.name, rank = L.LORD, online = g.leaderOnline, days = g.leaderDays }
				lines[#lines + 1] = {
					key = g.leader,
					indent = 1, text = Mark(g.leader, g.realm, g.leaderOnline) .. CROWN .. Gold(L.LORD) .. "  " .. ClassColored(g.leader, lord.class and ns.CLASS_FILES[lord.class])
						.. Tag(g.leader, g.realm),
					right = Presence(g.leaderOnline, g.leaderDays),
					onClick = function() ns.UI.ShowPerson(lord) end,
				}
			end
			local officers = g.officers or {}
			lines[#lines + 1] = { indent = 1, text = Gold(L.CAPTAINS:format(#officers)) }
			for _, o in ipairs(officers) do
				local person = { name = o.name, realm = g.realm, class = o.class, level = o.level, zone = o.zone, guild = e.name,
					rank = L.CAPTAIN, online = o.online, days = o.days }
				lines[#lines + 1] = {
					key = o.name,
					indent = 2, text = Mark(o.name, g.realm, o.online) .. ASSIST .. ClassColored(o.name, o.class and ns.CLASS_FILES[o.class])
						.. Tag(o.name, g.realm) .. (ns.IsTreasurer(o.name, e.name) and ("  " .. ns.COIN .. Grey(L.TREASURER)) or ""),
					right = (o.level and Grey(L.LEVEL_N:format(o.level)) .. "  " or "") .. Presence(o.online, o.days),
					onClick = function() ns.UI.ShowPerson(person) end,
				}
			end
			if #officers == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
			-- Everyone else online: our roster, or /who for other guilds.
			local members, fromWho = Views.MembersOf(e.name, g)
			lines[#lines + 1] = {
				indent = 1, text = Gold((fromWho and L.MEMBERS_SEEN or L.MEMBERS_ONLINE):format(#members)),
				tooltip = function(tt)
					tt:AddLine((fromWho and L.MEMBERS_SEEN or L.MEMBERS_ONLINE):format(#members), 1, 0.82, 0)
					tt:AddLine(fromWho and L.MEMBERS_SEEN_TIP or L.MEMBERS_ONLINE_TIP, 1, 1, 1, true)
				end,
			}
			local shown = allMembers[e.name] and #members or math.min(Views.MAX_MEMBERS, #members)
			for i = 1, shown do
				local m = members[i]
				local person = { name = m.name, class = m.class, level = m.level, zone = m.zone, guild = e.name, rank = m.rank, online = true }
				lines[#lines + 1] = {
					key = m.name,
					indent = 2, text = ClassColored(m.name, m.class and ns.CLASS_FILES[m.class]) .. Tag(m.name) .. (m.rank and ("  " .. Grey(m.rank)) or "")
						.. (ns.IsTreasurer(m.name, e.name) and ("  " .. ns.COIN .. Grey(L.TREASURER)) or ""),
					right = m.level and Grey(L.LEVEL_N:format(m.level)) or nil,
					onClick = function() ns.UI.ShowPerson(person) end,
				}
			end
			-- The rest on a click, and back again.
			if #members > shown then
				lines[#lines + 1] = {
					indent = 2, text = Gold(L.MEMBERS_MORE:format(#members - shown)),
					onClick = function() allMembers[e.name] = true; ns.UI.Refresh() end,
				}
			elseif allMembers[e.name] and #members > Views.MAX_MEMBERS then
				lines[#lines + 1] = {
					indent = 2, text = Gold(L.MEMBERS_FEWER),
					onClick = function() allMembers[e.name] = nil; ns.UI.Refresh() end,
				}
			end
			if #members == 0 then lines[#lines + 1] = { indent = 2, text = Grey(fromWho and L.MEMBERS_NONE_SEEN or L.MEMBERS_NONE) } end
			lines[#lines + 1] = { indent = 1, text = Gold(L.RANKS) }
			for i, rank in ipairs(g.ranks or {}) do
				lines[#lines + 1] = { indent = 2, text = ("%d. %s"):format(i, Plain(rank.name)), right = ns.FormatNumber(rank.count) }
			end
			if #(g.ranks or {}) == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
			lines[#lines + 1] = { indent = 1, text = Grey(L.INACTIVE_LINE:format(g.inactive7 or 0, g.inactive30 or 0)), gapAfter = true }
		end
	end

	local racers = {}
	for _, e in ipairs(s.guilds) do
		if e.fresh then
			for _, p in ipairs(e.g.top or {}) do racers[#racers + 1] = { name = p.name, realm = e.g.realm, level = p.level, class = p.class, guild = e.name } end
		end
	end
	table.sort(racers, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.LEVEL_RACE }
	if #racers == 0 then lines[#lines + 1] = { text = Grey(L.NONE_REPORTED) } end
	-- The top 100, shown 25 at a time (0.9.7): the window stays light.
	local shownRacers = math.min(#racers, Views.RACE_MAX, Views.raceShown)
	for i = 1, shownRacers do
		local p = racers[i]
		lines[#lines + 1] = {
			key = p.name,
			text = ("%d. %s  %s"):format(i, ClassColored(p.name, p.class and ns.CLASS_FILES[p.class]), Grey("<" .. Plain(p.guild) .. ">")),
			right = Gold(L.LEVEL_N:format(p.level)),
			onClick = function() ns.UI.ShowPerson({ name = p.name, realm = p.realm, class = p.class, level = p.level, guild = p.guild }) end,
		}
	end

	local total = math.min(#racers, Views.RACE_MAX)
	if total > shownRacers then
		lines[#lines + 1] = { text = Grey(L.SHOW_MORE:format(math.min(Views.RACE_PAGE, total - shownRacers), shownRacers, total)),
			onClick = function() Views.raceShown = Views.raceShown + Views.RACE_PAGE; ns.Fire("DATA_CHANGED") end }
	end

	local open = {}
	for _, e in ipairs(s.guilds) do
		local free = 1000 - (e.g.total or 0)
		if e.fresh and free > 0 then open[#open + 1] = { name = e.name, free = free } end
	end
	table.sort(open, function(a, b) return a.free > b.free end)
	lines[#lines + 1] = { header = true, text = L.RECRUITING }
	-- The gates the King (or a Hand) opened: where new recruits go now (Acts.lua).
	local gates = ns.Acts and ns.Acts.Gates and ns.Acts.Gates()
	local commands = ns.King and (ns.King.CanCommand() or ns.King.Preview())
	if gates then
		local left = math.max(0, gates.at - ns.Now())
		lines[#lines + 1] = {
			text = CROWN .. Gold(L.GATES_LINE:format(gates.guild)),
			onClick = commands and function() ns.Acts.GatesClick(gates.guild) end or nil,
			tooltip = function(tt)
				tt:AddLine(L.GATES_LINE:format(gates.guild), 1, 0.82, 0, true)
				tt:AddLine(L.GATES_TIP:format(math.floor(left / 3600), math.floor(left % 3600 / 60)), 1, 1, 1, true)
				if commands and ns.Acts.CanClose() then tt:AddLine(L.GATES_CLOSE_TIP, 0.6, 0.6, 0.6, true) end
			end,
		}
	end
	if #open == 0 then lines[#lines + 1] = { text = Grey(L.ALL_FULL) } end
	for i = 1, math.min(5, #open) do
		local name = open[i].name
		lines[#lines + 1] = {
			text = Green("<" .. name .. ">"), right = L.FREE_SLOTS:format(ns.FormatNumber(open[i].free)),
			-- The King and his Hands open a guild's gates from here.
			onClick = commands and function() ns.Acts.GatesClick(name) end or nil,
			tooltip = commands and function(tt)
				tt:AddLine("<" .. name .. ">", 0.25, 1, 0.25)
				local closing = gates and gates.guild == name
				tt:AddLine(closing and (ns.Acts.CanClose() and L.GATES_CLOSE_TIP or L.GATES_ONLY_OPENER) or L.GATES_CLICK_TIP, 1, 1, 1, true)
			end or nil,
		}
	end

	local mapID = ns.Layers.CurrentMap()
	local zone = mapID and ns.Zones.NameForKey("m" .. mapID) or "?"
	lines[#lines + 1] = { header = true, text = L.LAYERS_IN:format(zone) }
	local layers = mapID and ns.Layers.ForMap(mapID) or {}
	if #layers == 0 then lines[#lines + 1] = { text = Grey(L.LAYERS_HINT) } end
	for _, layer in ipairs(layers) do
		local head = layer.head
		lines[#lines + 1] = {
			text = (layer.mine and Green("> ") or "   ") .. Gold(ns.Layers.Name(layer)) .. Grey(("  #%d"):format(layer.zoneUID)),
			right = L.LAYER_COUNT:format(layer.count),
			-- Another layer: one click asks the Olympus players there for an invite (Hop.lua).
			onClick = not layer.mine and function() ns.Hop.Ask(mapID, layer.zoneUID, ns.Layers.Name(layer)) end or nil,
			tooltip = function(tt)
				tt:AddLine(ns.Layers.Name(layer), 1, 0.82, 0)
				if head then tt:AddLine(("%s <%s>"):format(head.name, head.guild or "?"), 1, 1, 1) end
				if layer.mine then tt:AddLine(L.LAYER_YOU, 0.25, 1, 0.25) else tt:AddLine(L.HOP_ROW_TIP, 0.25, 1, 0.25, true) end
				tt:AddLine(L.LAYER_EXPERIMENTAL, 0.6, 0.6, 0.6, true)
			end,
		}
	end
	return lines
end

local function RealmDetail(s)
	local lords, captains, inactive = 0, 0, 0
	for _, e in ipairs(s.guilds) do
		if e.fresh then
			lords = lords + 1
			captains = captains + #(e.g.officers or {})
			inactive = inactive + (e.g.inactive30 or 0)
		end
	end
	return L.TAB_REALM, L.REALM_DETAIL:format(lords, captains, ns.FormatNumber(inactive)) .. "\n" .. Grey(L.CLICK_EXPAND)
end

function Views.ExpandAll(on)
	for _, e in ipairs(ns.Data.Summary().guilds) do expanded[e.name] = on or nil end
	expanded[COUNCIL_ROW] = on or nil -- (the High Council's too)
end

---------------------------------------------------------------------------
-- Decrees (layers + decrees)
---------------------------------------------------------------------------

local function DecreeLines()
	-- The King's writs first, for whoever they are for (Acts.lua).
	local lines = ns.Acts and ns.Acts.WritLines and ns.Acts.WritLines() or {}
	lines[#lines + 1] = { header = true, text = L.DECREES }
	local decrees = ns.Decree.Active()
	if #decrees == 0 then lines[#lines + 1] = { text = Grey(L.NO_DECREES), gapAfter = true } end
	for _, d in ipairs(decrees) do
		local color = d.kind == "ARMS" and Red or Gold
		lines[#lines + 1] = {
			text = color(ns.Decree.Label(d)) .. "  " .. ns.Zones.NameForKey("m" .. d.mapID),
			right = Grey(ns.Ago(d.t)),
			tooltip = function(tt)
				tt:AddLine(ns.Decree.Label(d), 1, 0.25, 0.25)
				if d.text ~= "" then tt:AddLine(d.text, 1, 1, 1, true) end
				tt:AddLine(L.DECREE_BY:format(d.sender, d.guild, ns.Ago(d.t)), 0.7, 0.7, 0.7)
			end,
		}
		if d.text ~= "" then lines[#lines + 1] = { indent = 1, text = Grey('"' .. d.text .. '"') } end
	end

	return lines
end

local function DecreeHelp(lines)
	lines[#lines + 1] = { header = true, text = L.DECREE_HELP_TITLE }
	for _, k in ipairs({ "ARMS", "MUSTER", "ROYAL", "HERALDRY" }) do
		local who = ns.Decree.CROWN_ONLY[k] and L.WHO_CROWN or L.WHO_CAPTAINS
		lines[#lines + 1] = { text = Gold(L["HELP_" .. k .. "_NAME"]) .. "  " .. Grey("(" .. who .. ")") }
		lines[#lines + 1] = { indent = 1, text = Grey(L["HELP_" .. k]) }
	end
end

local function DecreeDetail()
	local who
	if ns.IsCrown() then who = L.YOU_ARE_CROWN
	elseif ns.Roster.IsOfficer() then who = L.YOU_ARE_OFFICER
	else who = L.YOU_ARE_SOLDIER end
	return L.DECREES_DETAIL_TITLE, who
end

---------------------------------------------------------------------------
-- Heraldry (tabard inspection + Wall of Shame)
---------------------------------------------------------------------------

local STATUS_TEXT = {
	GUILD = function() return Green(L.TABARD_OK) end,
	NONE = function() return Red(L.TABARD_NONE) end,
	OTHER = function() return Gold(L.TABARD_OTHER) end,
	UNKNOWN = function() return Grey(L.TABARD_UNKNOWN) end,
	UNCHECKED = function() return Grey(L.TABARD_UNCHECKED) end,
	YOUNG = function() return Grey(L.TABARD_YOUNG) end,
}

Views.RACE_MAX, Views.RACE_PAGE = 100, 25 -- the level race: its top 100, 25 at a time
Views.raceShown = Views.RACE_PAGE
Views.INSPECT_ROWS = 200 -- inspected players listed on the Tabards page

local function HeraldryLines()
	local s = ns.Inspect.Summary()
	-- The King (and his Hands): the Royal Inspection, and what the patrols reported (King.lua).
	local lines = {}
	for _, l in ipairs(ns.King and ns.King.InspectionLines and ns.King.InspectionLines() or {}) do lines[#lines + 1] = l end
	-- The untabarded: the King sees his own list (and whether the army sees it); everyone else
	-- sees it only while he shares it.
	local king = ns.King and (ns.King.IsKing() or ns.King.Preview())
	local shame = ns.Inspect.Shame()
	if king then
		shame = { list = ns.Inspect.ShameList(), mine = true }
	end
	if not ns.Inspect.ShameOpen() then
		-- Closed until the tabard rule is in force (Inspect.lua): a countdown.
		local left = ns.Inspect.ShameOpensIn()
		local wait = ("%dh %02dm"):format(math.floor(left / 3600), math.floor(left % 3600 / 60))
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(L.SHAME_OPENS:format(wait)) }
		lines[#lines].gapAfter = true
	elseif not (shame and #shame.list > 0) then
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(king and L.SHAME_EMPTY or L.UNTABARDED_NOT_SHARED) }
		lines[#lines].gapAfter = true
	else
		local right = shame.mine and (ns.King.SharingUntabarded() and L.UNTABARDED_SHARED or L.UNTABARDED_ONLY_KING)
			or L.PUBLISHED_BY:format(shame.by, ns.Ago(shame.t))
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(right) }
		-- The King pardons with a click (Acts.lua); anyone else opens the person.
		for i = 1, math.min(12, #shame.list) do
			local p = shame.list[i]
			local pardon = king and ns.King.CleanName(p.name) ~= nil
			lines[#lines + 1] = { indent = 1, key = p.name, text = p.name .. "  " .. Grey("<" .. (p.guild or "?") .. ">"),
				onClick = pardon and function() ns.ShowDialog("OLYMPUS_PARDON", p.name, nil, p.name) end
					or function() ns.UI.ShowPerson({ name = p.name, guild = p.guild }) end,
				tooltip = pardon and function(tt)
					tt:AddLine(p.name, 1, 0.82, 0)
					tt:AddLine(L.PARDON_TIP, 1, 1, 1, true)
				end or nil }
		end
		if #shame.list > 12 then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#shame.list - 12)) } end
		lines[#lines].gapAfter = true
	end
	lines[#lines + 1] = { header = true, text = L.GUILDS }
	for i = 1, math.min(8, #s.guilds) do
		local g = s.guilds[i]
		lines[#lines + 1] = {
			text = (g.marked and Red("! ") or "") .. Green("<" .. g.name .. ">"),
			right = L.GUILD_BAD:format(g.bad, g.total),
			onClick = function() ns.Inspect.ToggleGuildMark(g.name) end,
			tooltip = function(tt) tt:AddLine("<" .. g.name .. ">", 0.25, 1, 0.25); tt:AddLine(L.CLICK_MARK_GUILD, 0.8, 0.8, 0.8) end,
		}
	end
	if #s.guilds == 0 then lines[#lines + 1] = { text = Grey(L.INSPECT_EMPTY) } end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.INSPECTED_PLAYERS }
	-- A line (and a frame) each: the first INSPECT_ROWS, marked and caught players first
	-- (Inspect.Summary), the rest counted.
	local rows = math.min(#s.players, Views.INSPECT_ROWS)
	for i = 1, rows do
		local p = s.players[i]
		lines[#lines + 1] = {
			key = p.name,
			cols = {
				(p.marked and Red("! ") or "") .. ClassColored(ns.ShortName(p.name), p.class),
				Grey(p.guild and ("<" .. p.guild .. ">") or ""),
				(STATUS_TEXT[p.status or "UNKNOWN"] or STATUS_TEXT.UNKNOWN)(),
				Grey(ns.Ago(p.t)),
			},
			onClick = function()
				local code = ns.Roster.ClassCode(p.class)
				ns.UI.ShowPerson({
					name = ns.ShortName(p.name), realm = ns.RealmOf(p.name), class = code ~= "" and code or nil, level = p.level, guild = p.guild,
					tabard = (STATUS_TEXT[p.status or "UNKNOWN"] or STATUS_TEXT.UNKNOWN)(), note = p.note,
					onMark = function() ns.Inspect.ToggleMark(p.name) end,
				})
			end,
			tooltip = function(tt)
				tt:AddLine(ClassColored(p.name, p.class))
				tt:AddLine("<" .. (p.guild or "?") .. ">" .. (p.level and ("  lvl " .. p.level) or ""), 0.25, 1, 0.25)
				if p.note then tt:AddLine('"' .. p.note .. '"', 1, 0.5, 0.5, true) end
				tt:AddLine(L.CLICK_MARK_PLAYER, 0.6, 0.6, 0.6)
			end,
		}
	end
	if #s.players > rows then lines[#lines + 1] = { text = Grey(L.AND_MORE:format(#s.players - rows)) } end
	return lines
end

local function HeraldryDetail()
	local s = ns.Inspect.Summary()
	local c = s.counts
	return L.INSPECT_COUNTS:format(s.total, c.GUILD, c.NONE, c.OTHER),
		(ns.Inspect.IsPatrolling() and Green(L.PATROL_ON) or Grey(L.PATROL_HINT))
end

---------------------------------------------------------------------------
-- Join Olympus (what non-members see)
---------------------------------------------------------------------------

function Views.RecruitLines()
	local R = ns.Recruit
	local lines = { { header = true, text = L.RECRUIT_TITLE } }
	local guilds = R.Guilds()
	if #guilds == 0 then
		lines[#lines + 1] = { text = Grey(#R.found == 0 and not ns.Who.Searched() and L.RECRUIT_START or L.RECRUIT_NONE_FOUND) }
		return lines
	end
	-- "Showing 50 of 312 online", and which levels the next click searches.
	WhoStatus(lines)
	if #lines > 1 then lines[#lines].gapAfter = true end
	for _, g in ipairs(guilds) do
		lines[#lines + 1] = {
			text = Green("<" .. g.name .. ">"),
			right = Grey(L.RECRUIT_ONLINE:format(#g.members)) .. "  " .. Gold(L.RECRUIT_ASK),
			onClick = function() R.PromptNext(g.name) end,
			tooltip = function(tt)
				tt:AddLine("<" .. g.name .. ">", 0.25, 1, 0.25)
				tt:AddLine(L.RECRUIT_ASK_TIP, 1, 1, 1, true)
			end,
		}
		for _, p in ipairs(g.members) do
			local state = ""
			if R.replied[p.name] then state = Green(L.RECRUIT_STATE_REPLIED)
			elseif R.asked[p.name] then state = Grey(L.RECRUIT_STATE_ASKED) end
			lines[#lines + 1] = {
				indent = 1,
				text = ClassColored(ns.ShortName(p.name), p.class) .. "  " .. Grey((p.level and L.LEVEL_N:format(p.level) or "") .. (p.zone and ("  " .. p.zone) or "")),
				right = state,
				onClick = function() ns.ShowDialog("OLYMPUS_RECRUIT", p.name, p.guild, p) end,
				tooltip = R.replied[p.name] and function(tt)
					tt:AddLine(ns.ShortName(p.name), 1, 0.82, 0)
					-- (A whisper: its links stay, like a chat line's; no other escape code, 0.9.2.)
					tt:AddLine('"' .. ns.Codec.SanitizeChat(R.replied[p.name]) .. '"', 1, 1, 1, true)
				end or nil,
			}
		end
		lines[#lines].gapAfter = true
	end
	return lines
end

---------------------------------------------------------------------------
-- Entry point used by UI.lua
---------------------------------------------------------------------------

-- Each tab's lines, detail title and detail text. A tab missing here (a new one being
-- added) is an empty list.
local BUILD = {
	census = function(s)
		local title, text = CensusDetail(s)
		return CensusLines(s), title, text
	end,
	realm = function(s)
		local title, text = RealmDetail(s)
		return RealmLines(s), title, text
	end,
	decrees = function()
		local title, text = DecreeDetail()
		local lines = DecreeLines()
		DecreeHelp(lines)
		return lines, title, text
	end,
	heraldry = function()
		local title, text = HeraldryDetail()
		return HeraldryLines(), title, text
	end,
	throne = function(s)
		if not (ns.King and ns.King.Build) then return {}, nil, nil end
		local lines, title, text = ns.King.Build(s)
		return lines or {}, title, text
	end,
	vox = function()
		if not (ns.Vox and ns.Vox.Build) then return {}, nil, nil end
		local lines, title, text = ns.Vox.Build()
		return lines or {}, title, text
	end,
	treasury = function()
		if not (ns.Treasury and ns.Treasury.Build) then return {}, nil, nil end
		local lines, title, text = ns.Treasury.Build()
		return lines or {}, title, text
	end,
	workshop = function()
		if not (ns.Workshop and ns.Workshop.Build) then return {}, nil, nil end
		local lines, title, text = ns.Workshop.Build()
		return lines or {}, title, text
	end,
}

function Views.Build(tab)
	local build = BUILD[tab]
	if not build then return {}, nil, nil end
	return build(ns.Data.Summary())
end

-- Kept for the tests: the Realm tree lines.
function Views.RealmLines() return RealmLines(ns.Data.Summary()) end
