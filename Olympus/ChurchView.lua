local ADDON, ns = ...
local L = ns.L

-- The Missionary Church of Olympus (1.1.6): its tab in the Olympus window. Ranking | Mine | People |
-- Name | Review, each page shown only to who can use it, in the Realm's subtab row; the public
-- ranking for everyone else while the author's switch is open. Everything is read from Church.lua
-- (places) and ChurchCount.lua (numbers); a click names, removes or registers through the same
-- calls /oly church makes. Dialogs go through ns.ShowDialog (Olympus's own window under the gamepad
-- UI), the right-click line through PlayerMenu.Add (no line at all under the gamepad UI); nothing
-- here hooks a Blizzard frame.
--
-- The companion "invite addon" seam (documented, not built; design section 14). A separate invite
-- addon would get its tab the way any companion addon does once that generic tab exists, and talk
-- to the Church only through a read-only table Bridge.lua's door would carry:
--   OlympusBridge.Church = { API_VERSION = 1,
--     Place = function(name) end,          -- "H"|"A"|"M"|"C"|nil from this client's book
--     MyNumbers = function() end,          -- a copy of this player's Mine page
--     Register = function(name) end }      -- ChurchCount.Register: the same limits as the Name page
-- A companion's word never counts more than the player's own client: what it registers is a
-- registration, and what it says it invited is never evidence (the guild's log is).

local View = {}
ns.ChurchView = View
local Church, Count = ns.Church, ns.ChurchCount

View.page, View.list, View.window = "ranking", "a", "m"
View.open = {}

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local Plain = ns.Codec.Plain
local function Name(n) return Plain(ns.DisplayName(ns.FullName(n or "?")) or "?") end
local function Pts(v)
	v = math.floor((tonumber(v) or 0) * 10 + 0.5) / 10
	if v == math.floor(v) then return tostring(math.floor(v)) end
	return ("%.1f"):format(v)
end
local function Tip(title, text)
	return function(tt)
		tt:AddLine(title, 1, 0.82, 0)
		if text then tt:AddLine(text, 1, 1, 1, true) end
	end
end
local function Redraw()
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end
View.COLUMNS = {
	{ key = "CHURCH_COL_NAME", x = 0.00, w = 0.40 },
	{ key = "CHURCH_COL_SCORE", x = 0.40, w = 0.14, justify = "RIGHT" },
	{ key = "CHURCH_COL_SPLIT", x = 0.55, w = 0.22, justify = "RIGHT" },
	{ key = "CHURCH_COL_RECRUITS", x = 0.78, w = 0.22, justify = "RIGHT" },
}
if ns.Views and ns.Views.COLUMNS then ns.Views.COLUMNS.church = View.COLUMNS end

---------------------------------------------------------------------------
-- Who sees the tab, and which pages
---------------------------------------------------------------------------

local function PreviewRole()
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and V.Previewing and V.Previewing() then return V.Role() end
end

local function Audience()
	local role = PreviewRole()
	if role then return role == "king" or role == "councillor" end
	return Church.InAudience(ns.me)
end

local function Person()
	if PreviewRole() then return false end
	return Church.IsPerson(ns.me)
end

local function Rights()
	local role = PreviewRole()
	if not role then return Church.Rights() end
	if role == "king" then return { root = "K", apostle = Church.APOSTLES_MAX - Church.State().apostles, correspondent = Church.OwnGuild() } end
	if role == "councillor" then return { apostle = Church.APOSTLES_MAX - Church.State().apostles } end
	if role == "gm" then return { correspondent = Church.OwnGuild() } end
	return {}
end

-- Everyone in Olympus may see the people. Private numbers and actions keep their own gates.
function View.Visible()
	return ns.IsMember() == true and PreviewRole() ~= "outsider"
end

function View.Pages()
	local out = {}
	if not View.Visible() then return out end
	local audience = Audience()
	if audience then out[#out + 1] = "ranking" end
	if Person() then out[#out + 1] = "mine" end
	out[#out + 1] = "people"
	local r = Rights()
	if r.apostle or r.missionary or r.correspondent then out[#out + 1] = "name" end
	if r.root then out[#out + 1] = "review" end
	if not audience and Count.PublicView() then out[#out + 1] = "public" end
	return out
end

local function Allowed(page)
	for _, p in ipairs(View.Pages()) do if p == page then return true end end
	return false
end

function View.Show(page, arg)
	View.page, View.arg = page, arg
	Redraw()
end

local PAGE_LABEL = { ranking = "CHURCH_NAV_RANKING", mine = "CHURCH_NAV_MINE", people = "CHURCH_NAV_PEOPLE", name = "CHURCH_NAV_NAME",
	review = "CHURCH_NAV_REVIEW", public = "CHURCH_NAV_PUBLIC" }

local function Nav(current)
	local nav = {}
	for _, page in ipairs(View.Pages()) do
		local p = page
		nav[#nav + 1] = { text = L[PAGE_LABEL[p]], selected = current == p, onClick = current ~= p and function() View.Show(p) end or nil }
	end
	return { nav = nav, pageNav = true, id = "church-navigation" }
end

local function ListFilter()
	local nav, value = {}, nil
	for _, it in ipairs({ { "a", "CHURCH_LIST_APOSTLES" }, { "m", "CHURCH_LIST_MISSIONARIES" }, { "c", "CHURCH_LIST_CORRESPONDENTS" } }) do
		local key = it[1]
		if View.list == key then value = L[it[2]] end
		nav[#nav + 1] = { text = L[it[2]], selected = View.list == key, onClick = View.list ~= key and function() View.list = key; Redraw() end or nil }
	end
	return { label = L.CHURCH_FILTER_WHO, value = value or L.CHURCH_LIST_APOSTLES, options = nav, understated = true }
end

local function WindowFilter()
	local nav, value = {}, nil
	for _, it in ipairs({ { "w", "CHURCH_WINDOW_WEEK" }, { "m", "CHURCH_WINDOW_MONTH" }, { "a", "CHURCH_WINDOW_ALL" } }) do
		local key = it[1]
		if View.window == key then value = L[it[2]] end
		nav[#nav + 1] = { text = L[it[2]], selected = View.window == key, onClick = View.window ~= key and function() View.window = key; Redraw() end or nil }
	end
	return { label = L.CHURCH_FILTER_WHEN, value = value or L.CHURCH_WINDOW_MONTH, options = nav, understated = true }
end

local function Filters(who)
	local filters = who and { ListFilter(), WindowFilter() } or { WindowFilter() }
	return { filters = filters, id = "church-filters", gapAfter = true }
end

local ROLE_LABEL = { W = "CHURCH_ROLE_AUTHOR", K = "CHURCH_ROLE_KING", H = "CHURCH_HEAD", A = "CHURCH_APOSTLE", M = "CHURCH_MISSIONARY",
	C = "CHURCH_CORRESPONDENT", N = "CHURCH_ROLE_COUNCIL" }
function View.RoleLabel(role) return role and L[ROLE_LABEL[role]] or "" end

---------------------------------------------------------------------------
-- Dialogs (ns.ShowDialog: the game's popups with mouse and keyboard, Olympus's own window with the
-- gamepad UI)
---------------------------------------------------------------------------

-- What a name dialog does with the name typed: data.kind apostle, missionary (data.under: a
-- root's chosen parent), correspondent (data.guild), register.
function View.Submit(data, text)
	if PreviewRole() then return false end
	if type(data) ~= "table" then return end
	if data.kind == "apostle" then return Church.NameApostle(text)
	elseif data.kind == "missionary" then return Church.NameMissionary(text, data.under)
	elseif data.kind == "correspondent" then return Church.NameCorrespondent(text, data.guild)
	elseif data.kind == "register" then return Count.Register(text)
	elseif data.kind == "move" then return Church.Move(data.name, text) end
end

-- What a confirmation does on Yes.
function View.Confirm(data)
	if PreviewRole() then return false end
	if type(data) ~= "table" then return end
	if data.kind == "remove" then return Church.Remove(data.role, data.name)
	elseif data.kind == "uncorrespondent" then return Church.RemoveCorrespondent(data.guild)
	elseif data.kind == "keep" then return Church.Keep(data.name)
	elseif data.kind == "missionary" then return Church.NameMissionary(data.name, data.under)
	elseif data.kind == "apostle" then return Church.NameApostle(data.name)
	elseif data.kind == "withdraw" then return Count.Withdraw(data.name) end
end

local PROMPTS = { apostle = "CHURCH_PROMPT_APOSTLE", missionary = "CHURCH_PROMPT_MISSIONARY", correspondent = "CHURCH_PROMPT_CORRESPONDENT",
	register = "CHURCH_PROMPT_REGISTER", move = "CHURCH_PROMPT_MOVE" }
function View.Ask(kind, extra)
	if PreviewRole() then return false end
	local data = { kind = kind }
	for k, v in pairs(extra or {}) do data[k] = v end
	local what = data.under and Name(data.under) or (data.guild or (data.name and Name(data.name)) or "")
	local prompt = PROMPTS[kind] or "CHURCH_PROMPT_MINE"
	if kind == "missionary" and not data.under then prompt = "CHURCH_PROMPT_MINE" end
	return ns.ShowDialog("OLYMPUS_CHURCH_NAME", L[prompt]:format(what), nil, data)
end

local CONFIRMS = { remove = "CHURCH_CONFIRM_REMOVE", uncorrespondent = "CHURCH_CONFIRM_UNCORRESPONDENT", keep = "CHURCH_CONFIRM_KEEP",
	missionary = "CHURCH_CONFIRM_MISSIONARY", apostle = "CHURCH_CONFIRM_APOSTLE", withdraw = "CHURCH_CONFIRM_WITHDRAW" }
function View.AskConfirm(kind, extra)
	if PreviewRole() then return false end
	local data = { kind = kind }
	for k, v in pairs(extra or {}) do data[k] = v end
	local who = data.name and Name(data.name) or (data.guild or "")
	return ns.ShowDialog("OLYMPUS_CHURCH_CONFIRM", L[CONFIRMS[kind]]:format(who), nil, data)
end

if StaticPopupDialogs then
	StaticPopupDialogs["OLYMPUS_CHURCH_NAME"] = {
		text = "%s",
		button1 = OKAY or "OK",
		button2 = CANCEL or "Cancel",
		hasEditBox = true,
		editBoxWidth = 240,
		maxLetters = 72,
		OnShow = function(self, data)
			local eb = self.editBox or self.EditBox
			if not eb then return end
			local kind = type(data) == "table" and data.kind
			local target = kind ~= "move" and UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName and ns.UnitFullName("target")
			eb:SetText(target and ns.DisplayName(target) or "")
			eb:SetFocus()
		end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			ns.SafeCall("church name", View.Submit, data or (self and self.data), eb and eb:GetText())
		end,
		EditBoxOnEnterPressed = function(self, data)
			local parent = self:GetParent()
			ns.SafeCall("church name", View.Submit, data or (parent and parent.data), self:GetText())
			parent:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs["OLYMPUS_CHURCH_CONFIRM"] = {
		text = "%s",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(self, data) ns.SafeCall("church confirm", View.Confirm, data or (self and self.data)) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------

local function AsOfLine(asOf, remote)
	local desk = Church.Desk()
	local text
	if not remote then text = L.CHURCH_ASOF_LIVE
	elseif asOf then text = L.CHURCH_ASOF:format(ns.Ago(asOf))
	else text = L.CHURCH_ASOF_NONE end
	if remote then text = text .. "  " .. (desk and L.CHURCH_DESK:format(Name(desk)) or L.CHURCH_NO_KEEPER) end
	return { text = Grey(text), tooltip = Tip(L.CHURCH_ASOF_TITLE, L.CHURCH_ASOF_TIP) }
end

local function SwitchLine()
	if PreviewRole() then return nil end
	if not Church.MayPublish(ns.me) then return nil end
	local open = Church.Public()
	return { header = true, text = L.CHURCH_PUBLIC_SWITCH, right = open and Green(L.CHURCH_PUBLIC_OPEN) or Grey(L.CHURCH_PUBLIC_SHUT),
		onClick = function() Church.SetPublic(not Church.Public()) end, tooltip = Tip(L.CHURCH_PUBLIC_SWITCH, L.CHURCH_PUBLIC_SWITCH_TIP), gapAfter = true }
end

-- The breakdown of a score: own + level 1 + level 2 + level 3 (D: the person's own line).
function View.Breakdown(levels, own)
	return L.CHURCH_BREAKDOWN:format(Pts(own), Pts(levels[1]), Pts(levels[2]), Pts(levels[3]))
end

local function MyLevels()
	local lines = Count.DetailView(ns.me, View.window)
	for _, d in ipairs(lines or {}) do
		if d[1] == "s" then return { tonumber(d[3]) or 0, tonumber(d[4]) or 0, tonumber(d[5]) or 0 }, tonumber(d[2]) or 0 end
	end
	return nil
end

function View.RankingLines()
	local lines = { Nav("ranking"), Filters(true) }
	local switch = SwitchLine()
	if switch then lines[#lines + 1] = switch end
	local rows, asOf, remote = Count.RankingView(View.list, View.window)
	if remote and not PreviewRole() then Count.Ask(View.list, View.window) end
	lines[#lines + 1] = AsOfLine(asOf, remote)
	lines[#lines + 1] = { header = true, text = L["CHURCH_RANKING_" .. View.list:upper()],
		tooltip = Tip(L["CHURCH_RANKING_" .. View.list:upper()], L.CHURCH_POINTS_TIP) }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_RANKING_EMPTY) } end
	local me = Church.Key(ns.me)
	for _, row in ipairs(rows) do
		local recruits = View.list == "a" and L.CHURCH_RECRUITS_NET:format(row.joins, row.net, row.stays) or L.CHURCH_RECRUITS:format(row.joins, row.stays)
		local mine = row.key == me
		local nameText = ("%d.  %s"):format(row.rank, Name(row.name))
		lines[#lines + 1] = {
			cols = { mine and Gold(nameText) or nameText, Pts(row.score), L.CHURCH_SPLIT:format(Pts(row.own), Pts(row.share)), recruits },
			player = ns.FullName(row.name), key = row.key,
			tooltip = Tip(Name(row.name), L.CHURCH_ROW_TIP:format(Pts(row.score), Pts(row.own), Pts(row.share), row.joins, row.stays)),
			onClick = not PreviewRole() and Count.MaySeeDetail(ns.me, ns.FullName(row.name)) and function() View.Show("detail", ns.FullName(row.name)) end or nil,
		}
		if mine then
			local levels, own = row.levels, row.own
			if not levels then
				levels, own = MyLevels()
				if not levels and not PreviewRole() then Count.Ask("me", View.window) end
			end
			lines[#lines + 1] = { indent = 2, text = Grey(levels and View.Breakdown(levels, own or row.own)
				or L.CHURCH_SPLIT_LONG:format(Pts(row.own), Pts(row.share))) }
		end
	end
	return lines, L.CHURCH_TITLE, L.CHURCH_RANKING_DETAIL
end

---------------------------------------------------------------------------
-- A person's numbers (Mine, and another person's detail)
---------------------------------------------------------------------------

local STATE_LABEL = { open = "CHURCH_REG_OPEN", credited = "CHURCH_REG_CREDITED", pending = "CHURCH_REG_PENDING", taken = "CHURCH_REG_TAKEN",
	transfer = "CHURCH_REG_TRANSFER", alt = "CHURCH_REG_TRANSFER", withdrawn = "CHURCH_REG_WITHDRAWN", expired = "CHURCH_REG_EXPIRED" }

local function DetailLinesFor(person, lines, skipRegs)
	local detail, asOf, remote = Count.DetailView(person, View.window)
	if remote then
		local mine = Church.Key(person) == Church.Key(ns.me)
		Count.Ask(mine and "me" or "p", View.window, not mine and person or nil)
	end
	lines[#lines + 1] = AsOfLine(asOf, remote)
	local seen = false
	for _, d in ipairs(detail or {}) do
		seen = true
		local kind = d[1]
		if kind == "s" then
			lines[#lines + 1] = { header = true, text = L.CHURCH_SCORE_LINE:format(Pts((tonumber(d[2]) or 0) + (tonumber(d[3]) or 0) + (tonumber(d[4]) or 0) + (tonumber(d[5]) or 0))),
				tooltip = Tip(L.CHURCH_SCORE_TITLE, L.CHURCH_POINTS_TIP) }
			lines[#lines + 1] = { indent = 1, text = View.Breakdown({ tonumber(d[3]) or 0, tonumber(d[4]) or 0, tonumber(d[5]) or 0 }, tonumber(d[2]) or 0) }
		elseif kind == "j" then
			lines[#lines + 1] = { indent = 1, text = L.CHURCH_JOINS_LINE:format(tonumber(d[2]) or 0, tonumber(d[3]) or 0, tonumber(d[4]) or 0),
				tooltip = Tip(L.CHURCH_JOINS_TITLE, L.CHURCH_JOINS_TIP) }
			lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_TRANSFERS_LINE:format(tonumber(d[5]) or 0)) }
		elseif kind == "t" then
			lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_TAKEN_LINE:format(tonumber(d[2]) or 0, tonumber(d[3]) or 0)) }
			lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_NETWORK_LINE:format(tonumber(d[4]) or 0)), gapAfter = true }
		elseif kind == "g" then
			lines[#lines + 1] = { indent = 1, text = L.CHURCH_GUILD_LINE:format(Plain(tostring(d[2])), tonumber(d[3]) or 0, tonumber(d[4]) or 0) }
		elseif kind == "r" and not skipRegs then
			local state = tostring(d[4])
			lines[#lines + 1] = { indent = 1, text = L.CHURCH_REG_LINE:format(Name(tostring(d[2])), L[STATE_LABEL[state] or "CHURCH_REG_OPEN"]),
				right = Grey(ns.Ago(tonumber(d[3]) or 0)) }
		end
	end
	if not seen then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_NO_NUMBERS) } end
end

local function PlaceText(name)
	local S = Church.State()
	local role = Church.Role(name)
	local p = Church.Place(name)
	if role == "M" and p then
		local net = p.net and S.apostle[p.net] and S.apostle[p.net].n
		local parent = p.parent and ((S.apostle[p.parent] and S.apostle[p.parent].n) or (S.miss[p.parent] and S.miss[p.parent].n))
		return L.CHURCH_PLACE_MISSIONARY:format(net and Name(net) or L.CHURCH_HEAD, parent and Name(parent) or L.CHURCH_HEAD)
	elseif role == "C" then
		local gkey = S.corrOf[Church.Key(name)]
		return L.CHURCH_PLACE_CORRESPONDENT:format(gkey and S.corr[gkey] and S.corr[gkey].g or "?")
	end
	return role and View.RoleLabel(role) or L.CHURCH_PLACE_NONE
end

function View.MineLines()
	local lines = { Nav("mine"), Filters() }
	lines[#lines + 1] = { header = true, text = L.CHURCH_MY_PLACE, right = PlaceText(ns.me) }
	DetailLinesFor(ns.me, lines, true)
	local loc = Count.Local()
	lines[#lines + 1] = { indent = 1, text = L.CHURCH_INVITES_LINE:format(loc.invWeek, loc.invAll), tooltip = Tip(L.CHURCH_INVITES_TITLE, L.CHURCH_INVITES_TIP) }
	if Church.State().corrOf[Church.Key(ns.me)] then
		lines[#lines + 1] = { indent = 1, text = L.CHURCH_FILL_LINE:format(Church.OwnGuild() or "?", loc.members or 0, loc.joins, loc.leaves),
			tooltip = Tip(L.CHURCH_FILL_TITLE, L.CHURCH_FILL_TIP) }
	end
	if Church.IsPerson(ns.me) then
		local on = Count.PublicRow()
		lines[#lines + 1] = { header = true, text = L.CHURCH_MY_ROW, right = on and Green(L.CHURCH_ROW_YES) or Grey(L.CHURCH_ROW_NO),
			onClick = function() Count.SetPublicRow(not Count.PublicRow()) end, tooltip = Tip(L.CHURCH_MY_ROW, L.CHURCH_MY_ROW_TIP) }
		local m = Count.Mine()
		local regs = {}
		for _, r in pairs(m.regs) do regs[#regs + 1] = r end
		table.sort(regs, function(a, b) return (a.at or 0) > (b.at or 0) end)
		lines[#lines + 1] = { header = true, text = L.CHURCH_MY_REGS:format(#regs, Count.REG_OPEN),
			onClick = function() View.Ask("register") end, tooltip = Tip(L.CHURCH_MY_REGS:format(#regs, Count.REG_OPEN), L.CHURCH_REGISTER_TIP) }
		-- Each with its state as the keepers last said (open, credited, taken...); a click withdraws it.
		local states = {}
		for _, d in ipairs((Count.DetailView(ns.me, View.window))) do
			if d[1] == "r" then states[Church.Key(tostring(d[2]))] = tostring(d[4]) end
		end
		for _, r in ipairs(regs) do
			local name = ns.FullName(r.n)
			local state = states[Church.Key(r.n)]
			lines[#lines + 1] = { indent = 1, text = L.CHURCH_REG_LINE:format(Name(r.n), L[STATE_LABEL[state] or "CHURCH_REG_OPEN"]),
				right = Grey(ns.Ago(r.at)), onClick = function() View.AskConfirm("withdraw", { name = name }) end }
		end
	end
	return lines, L.CHURCH_TITLE, L.CHURCH_MINE_DETAIL
end

function View.DetailLines(person)
	local lines = { Nav("ranking"), Filters() }
	lines[#lines + 1] = { header = true, text = Name(person), right = PlaceText(person),
		onClick = function() View.Show("ranking") end, tooltip = Tip(L.CHURCH_BACK, nil) }
	DetailLinesFor(person, lines)
	return lines, L.CHURCH_TITLE, L.CHURCH_DETAIL_DETAIL
end

---------------------------------------------------------------------------
-- People: the Head, the Apostles and their networks, the orphans, the correspondents
---------------------------------------------------------------------------

local function Actions(lines, info, indent)
	if PreviewRole() then return end
	local S = Church.State()
	local root = Church.RootCode(ns.me)
	local me = Church.Key(ns.me)
	local name = ns.FullName(info.n)
	local role = info.role
	local canName = (root or info.key == me) and (role == "A" or (info.valid and (info.depth or 0) < Church.DEPTH_MAX))
		and (S.named[info.key] or 0) < Church.NAMES_PER
	if canName then
		lines[#lines + 1] = { indent = indent, text = Gold(L.CHURCH_ACT_NAME_UNDER:format(Name(info.n))),
			onClick = function() View.Ask("missionary", { under = root and name or nil }) end }
	end
	local mayRemove = root or info.key == me
	if role == "M" and not mayRemove then mayRemove = (info.p and Church.Key(info.p.ac) == me) or Church.Above(me, info.key) end
	if mayRemove then
		lines[#lines + 1] = { indent = indent, text = Red(L.CHURCH_ACT_REMOVE:format(Name(info.n))),
			onClick = function() View.AskConfirm("remove", { role = role, name = name }) end }
	end
	if root and role == "M" and (info.adopted or info.orphan) then
		lines[#lines + 1] = { indent = indent, text = Green(L.CHURCH_ACT_KEEP), onClick = function() View.AskConfirm("keep", { name = name }) end }
		lines[#lines + 1] = { indent = indent, text = L.CHURCH_ACT_MOVE, onClick = function() View.Ask("move", { name = name }) end }
	end
end

local function Mark(info)
	if info.orphan then return " " .. Red(L.CHURCH_MARK_ORPHAN) end
	if info.adopted then return " " .. Gold(L.CHURCH_MARK_REVIEW) end
	if info.p and info.p.via then return " " .. Grey(L.CHURCH_MARK_RELAYED) end
	return ""
end

local function Tree(lines, parentKey, indent, q, budget)
	for _, info in ipairs(Church.Children(parentKey)) do
		if budget.n <= 0 then return end
		budget.n = budget.n - 1
		local open = View.open[info.key]
		local shown = not q or ns.Holds(q, info.n)
		if shown then
			lines[#lines + 1] = { indent = indent, text = Name(info.n) .. Mark(info), right = Grey(L.CHURCH_UNDER:format(#Church.Children(info.key))),
				player = ns.FullName(info.n), key = info.key,
				onClick = function() View.open[info.key] = not View.open[info.key] or nil; Redraw() end }
			if open then Actions(lines, { key = info.key, n = info.n, role = "M", valid = info.valid, depth = info.depth, p = info.p,
				adopted = info.adopted, orphan = info.orphan }, indent + 1) end
		end
		Tree(lines, info.key, indent + 1, q, budget)
	end
end

function View.PeopleLines()
	local lines = { Nav("people") }
	local q = ns.Views and ns.Views.Query and ns.Views.Query("church")
	lines[#lines + 1] = { text = L.SEARCH, input = { text = ns.Views.Filter("church"), onChange = function(text) ns.Views.SetFilter("church", text) end },
		tooltip = Tip(L.SEARCH, L.CHURCH_SEARCH_TIP) }
	local S = Church.State()
	lines[#lines + 1] = { header = true, text = L.CHURCH_HEAD, right = L.CHURCH_HEAD_NAME,
		tooltip = Tip(L.CHURCH_HEAD, L.CHURCH_HEAD_TIP) }
	lines[#lines + 1] = { header = true, text = L.CHURCH_APOSTLES:format(S.apostles, Church.APOSTLES_MAX), tooltip = Tip(L.CHURCH_APOSTLE, L.CHURCH_APOSTLES_TIP) }
	if Rights().apostle and S.apostles < Church.APOSTLES_MAX then
		lines[#lines + 1] = { indent = 1, text = Gold(L.CHURCH_ACT_NAME_APOSTLE), onClick = function() View.Ask("apostle") end }
	end
	local budget = { n = 400 }
	for _, k in ipairs(S.order) do
		local a = S.apostle[k]
		local open = View.open[k]
		local shown = not q or ns.Holds(q, a.n)
		local net = 0
		local queue = { k }
		local i = 1
		while i <= #queue and i <= Church.MISSIONARIES_MAX do
			for _, c in ipairs(Church.Children(queue[i])) do queue[#queue + 1] = c.key; net = net + 1 end
			i = i + 1
		end
		if shown then
			lines[#lines + 1] = { indent = 1, text = Gold(Name(a.n)) .. (a.signed and "" or (" " .. Grey(L.CHURCH_MARK_INGAME))),
				right = Grey(L.CHURCH_NETWORK:format(net)), player = ns.FullName(a.n), key = k,
				onClick = function() View.open[k] = not View.open[k] or nil; Redraw() end }
		end
		if open then Actions(lines, { key = k, n = a.n, role = "A" }, 2) end
	end
	local corr = {}
	for _, c in pairs(S.corr) do corr[#corr + 1] = c end
	table.sort(corr, function(a, b) return ns.Fold(a.g) < ns.Fold(b.g) end)
	lines[#lines + 1] = { header = true, text = L.CHURCH_CORRESPONDENTS:format(#corr), tooltip = Tip(L.CHURCH_CORRESPONDENT, L.CHURCH_CORRESPONDENTS_TIP) }
	for _, c in ipairs(corr) do
		if not q or ns.Holds(q, c.n, c.g) then
			lines[#lines + 1] = { indent = 1, text = Plain(c.g), right = Name(c.n), player = ns.FullName(c.n) }
		end
	end
	-- The third group is always visible, not hidden behind collapsed Apostle rows. Keep
	-- networks (and the signed Apostle order) rather than inventing a new appointment order.
	lines[#lines + 1] = { header = true, text = L.CHURCH_MISSIONARIES:format(S.valid),
		tooltip = Tip(L.CHURCH_MISSIONARY, L.CHURCH_MISSIONARIES_TIP) }
	local rights = Rights()
	if not PreviewRole() and rights.missionary and rights.missionary > 0 then
		lines[#lines + 1] = { indent = 1, text = Gold(L.CHURCH_NAME_MISSIONARY:format(rights.missionary, Church.NAMES_PER)),
			onClick = function() View.Ask("missionary") end, tooltip = Tip(L.CHURCH_MISSIONARY, L.CHURCH_NAME_MISSIONARY_TIP) }
	end
	for _, k in ipairs(S.order) do
		if #Church.Children(k) > 0 then
			lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_MISSIONARY_NETWORK:format(Name(S.apostle[k].n))) }
			Tree(lines, k, 2, q, budget)
		end
	end
	local orphans = Church.Children("")
	if #orphans > 0 then
		lines[#lines + 1] = { header = true, text = L.CHURCH_ORPHANS:format(#orphans), tooltip = Tip(L.CHURCH_ORPHANS:format(#orphans), L.CHURCH_ORPHANS_TIP) }
		Tree(lines, "", 1, q, budget)
	end
	if S.valid == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_NO_MISSIONARIES) } end
	return lines, L.CHURCH_TITLE, L.CHURCH_PEOPLE_DETAIL
end

---------------------------------------------------------------------------
-- Name, Review, Public
---------------------------------------------------------------------------

function View.NameLines()
	local lines = { Nav("name") }
	local r = Rights()
	if r.missionary then
		lines[#lines + 1] = { header = true, text = Gold(L.CHURCH_NAME_MISSIONARY:format(r.missionary, Church.NAMES_PER)),
			onClick = r.missionary > 0 and function() View.Ask("missionary") end or nil, tooltip = Tip(L.CHURCH_MISSIONARY, L.CHURCH_NAME_MISSIONARY_TIP) }
	end
	if r.apostle then
		lines[#lines + 1] = { header = true, text = Gold(L.CHURCH_NAME_APOSTLE:format(r.apostle, Church.APOSTLES_MAX)),
			onClick = r.apostle > 0 and function() View.Ask("apostle") end or nil, tooltip = Tip(L.CHURCH_APOSTLE, L.CHURCH_NAME_APOSTLE_TIP) }
		if r.root then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_ROOT_UNDER) } end
	end
	if r.correspondent then
		local guild = r.correspondent
		local S = Church.State()
		local c = S.corr[ns.Fold(guild)]
		lines[#lines + 1] = { header = true, text = Gold(L.CHURCH_NAME_CORRESPONDENT:format(guild)), right = c and Name(c.n) or Grey(L.CHURCH_NONE),
			onClick = function() View.Ask("correspondent", { guild = guild }) end, tooltip = Tip(L.CHURCH_CORRESPONDENT, L.CHURCH_CORRESPONDENTS_TIP) }
		if c then lines[#lines + 1] = { indent = 1, text = Red(L.CHURCH_ACT_UNCORRESPONDENT), onClick = function() View.AskConfirm("uncorrespondent", { guild = guild }) end } end
	end
	-- A root names the correspondent of any Olympus guild in the census.
	if r.root and ns.Data and ns.Data.Summary then
		local S = Church.State()
		lines[#lines + 1] = { header = true, text = L.CHURCH_GUILDS }
		local n = 0
		for _, e in ipairs(ns.Data.Summary().guilds or {}) do
			if n >= 64 then break end
			local guild = e.name
			if type(guild) == "string" and ns.IsFederation(guild) and guild ~= r.correspondent then
				n = n + 1
				local c = S.corr[ns.Fold(guild)]
				lines[#lines + 1] = { indent = 1, text = Plain(guild), right = c and Name(c.n) or Grey(L.CHURCH_NONE),
					onClick = function() View.Ask("correspondent", { guild = guild }) end }
			end
		end
	end
	if Person() then
		local open = 0
		for _ in pairs(Count.Mine().regs) do open = open + 1 end
		lines[#lines + 1] = { header = true, text = Gold(L.CHURCH_REGISTER:format(open, Count.REG_OPEN)),
			onClick = function() View.Ask("register") end, tooltip = Tip(L.CHURCH_REGISTER:format(open, Count.REG_OPEN), L.CHURCH_REGISTER_TIP) }
	end
	return lines, L.CHURCH_TITLE, L.CHURCH_NAME_DETAIL
end

function View.ReviewLines()
	local lines = { Nav("review") }
	local S = Church.State()
	local any = false
	lines[#lines + 1] = { header = true, text = L.CHURCH_REVIEW_MARKED }
	for _, info in pairs(S.miss) do
		if info.valid and (info.adopted or info.orphan or info.p.via) then
			any = true
			lines[#lines + 1] = { indent = 1, text = Name(info.n) .. Mark(info), right = info.p.via and Grey(L.CHURCH_VIA:format(Name(info.p.via))) or "",
				player = ns.FullName(info.n), onClick = function() View.open[info.key] = not View.open[info.key] or nil; Redraw() end }
			if View.open[info.key] then
				Actions(lines, { key = info.key, n = info.n, role = "M", valid = true, depth = info.depth, p = info.p, adopted = info.adopted, orphan = info.orphan }, 2)
			end
		end
	end
	lines[#lines + 1] = { header = true, text = L.CHURCH_REVIEW_INVALID }
	for _, e in ipairs(S.invalid) do
		any = true
		lines[#lines + 1] = { indent = 1, text = Name(e.n), right = Red(L["CHURCH_WHY_" .. tostring(e.why):upper()] or e.why),
			onClick = function() View.AskConfirm("remove", { role = e.role, name = ns.FullName(e.n) }) end }
	end
	-- Correspondents heard in another guild than the one they keep.
	lines[#lines + 1] = { header = true, text = L.CHURCH_REVIEW_AWAY }
	for _, c in pairs(S.corr) do
		local ok, h = Church.Online(c.n)
		if ok and h and h.guild and ns.Fold(h.guild) ~= ns.Fold(c.g) then
			any = true
			lines[#lines + 1] = { indent = 1, text = Name(c.n), right = Grey(L.CHURCH_AWAY:format(Plain(c.g), Plain(h.guild))) }
		end
	end
	if not any then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_REVIEW_NONE) } end
	return lines, L.CHURCH_TITLE, L.CHURCH_REVIEW_DETAIL
end

function View.PublicLines()
	local lines = { Nav("public") }
	local v = Count.PublicView()
	lines[#lines + 1] = { header = true, text = L.CHURCH_TITLE }
	for _, it in ipairs({ { "a", "CHURCH_RANKING_A" }, { "m", "CHURCH_RANKING_M" } }) do
		lines[#lines + 1] = { header = true, text = L[it[2]] }
		local rows = v and v[it[1]] or {}
		local n = 0
		for rank = 1, Count.PUBLIC_ROWS do
			local row = rows[rank]
			if row then
				n = n + 1
				lines[#lines + 1] = { cols = { ("%d.  %s"):format(rank, Name(row.name)), Pts(row.s30), L.CHURCH_ALL_TIME:format(Pts(row.sall)), "" },
					player = ns.FullName(row.name) }
			end
		end
		if n == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.CHURCH_RANKING_EMPTY) } end
	end
	return lines, L.CHURCH_TITLE, L.CHURCH_PUBLIC_DETAIL
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

function View.Build()
	if not View.Visible() then return {}, L.CHURCH_TITLE, L.CHURCH_NO_ACCESS end
	local page = View.page
	if page == "detail" then
		local person = View.arg
		if person and not PreviewRole() and Count.MaySeeDetail(ns.me, person) and Audience() then return View.DetailLines(person) end
		page = "ranking"
	end
	if not Allowed(page) then page = View.Pages()[1] end
	View.page = page
	if page == "ranking" then return View.RankingLines()
	elseif page == "mine" then return View.MineLines()
	elseif page == "people" then return View.PeopleLines()
	elseif page == "name" then return View.NameLines()
	elseif page == "review" then return View.ReviewLines()
	elseif page == "public" then return View.PublicLines() end
	return {}, L.CHURCH_TITLE, L.CHURCH_NO_ACCESS
end

function View.Open()
	if not View.Visible() then return ns.Print(L.CHURCH_NO_ACCESS) end
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("church") end
end

-- The Church's room on the Chat tab.
function View.OpenChat()
	if PreviewRole() then return false end
	if not Audience() then return ns.Print(L.CHURCH_NO_ACCESS) end
	local CW = ns.ChatWindow
	if type(CW) ~= "table" or CW.missing then return ns.Print(L.RESTART_NEEDED) end
	if CW.Open then CW.Open() end
	if CW.SelectLogical then CW.SelectLogical("church") end
end

function View.Refresh()
	if Audience() and not PreviewRole() then
		if View.page == "ranking" then Count.Ask(View.list, View.window, nil, true)
		elseif View.page == "mine" then Count.Ask("me", View.window, nil, true)
		elseif View.page == "detail" and View.arg then Count.Ask("p", View.window, View.arg, true) end
	end
	Redraw()
end

local buttons = {
	{ "CHURCH_BTN_REFRESH", function() View.Refresh() end },
	{ "CHURCH_BTN_CHAT", function() View.OpenChat() end, shown = Audience },
	{ "CHURCH_BTN_REGISTER", function() View.Ask("register") end, shown = Person },
}

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "church", label = "TAB_CHURCH", after = "crafters",
		icon = function()
			return ns.UI.FirstTexture and ns.UI.FirstTexture({ "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", "Interface\\Icons\\INV_Misc_Book_09" })
				or "Interface\\Icons\\INV_Misc_Book_09"
		end,
		visible = View.Visible, build = View.Build, buttons = buttons })
end

-- The page's "?": what the Church is and how its numbers are counted (the answer bank's).
if ns.Answers and type(ns.Answers.PAGES) == "table" then ns.Answers.PAGES.church = { "feat-church", "feat-church-count" } end

-- The right-click line on a player (PlayerMenu.lua: Blizzard's own menus, none under the gamepad
-- UI): an Apostle or a missionary names him a missionary of his network, a root an Apostle.
function View.MenuLines(target, menu)
	if not (target and target.name) then return end
	local r = Church.Rights()
	local p = Church.Place(target.name)
	if p or Church.RootCode(target.name) then return end
	local name = target.name
	if r.missionary and r.missionary > 0 then
		menu.Button(L.CHURCH_MENU_MISSIONARY, function() View.AskConfirm("missionary", { name = name }) end,
			L.CHURCH_MISSIONARY, L.CHURCH_MENU_MISSIONARY_TIP, not target.locked)
	end
	if r.apostle and r.apostle > 0 then
		menu.Button(L.CHURCH_MENU_APOSTLE, function() View.AskConfirm("apostle", { name = name }) end,
			L.CHURCH_APOSTLE, L.CHURCH_MENU_APOSTLE_TIP, not target.locked)
	end
end
if ns.PlayerMenu and ns.PlayerMenu.Add then
	ns.PlayerMenu.Add("church", function(target, menu) View.MenuLines(target, menu) end, 40)
end

for _, event in ipairs({ "CHURCH_CHANGED", "CHURCH_COUNT_CHANGED", "CHURCH_PUBLIC_CHANGED" }) do
	ns.On(event, function()
		if ns.UI and ns.UI.IsShown and ns.UI.IsShown() then Redraw() end
	end)
end
