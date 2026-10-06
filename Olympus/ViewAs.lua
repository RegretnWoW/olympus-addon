local ADDON, ns = ...
local L = ns.L

-- View as (1.1.5, the author's ask; 1.2 widens it to every role): author-only, session-local
-- presentation previews. They change which pages are drawn, never the rank/authority checks used
-- by network handlers or actions, and never unlock private data. Each role drives the preview the
-- addon has for it: "king" Asmon's view (King.Preview), "treasurer" the Treasurer's view
-- (Treasury.DevView), "gm" the guild master's view (Nominees.DevView: his Guild tab and its
-- centurions and correspondents, nothing of it sent).
-- 1.2: the author (and his test builds) sees every tab in his own view ("my": he works as part of
-- the council and debugs everything; each page still shows only what his own client holds and may
-- show). A role picked from the Olympus window's title bar (UI.lua) shows that role's tabs and
-- sections instead, labelled as a preview there. Stewards and Hands are the High Council's now.
local V = {}
ns.ViewAs = V

V.OPTIONS = { "my", "king", "councillor", "treasurer", "arbiter", "gm", "officer", "correspondent", "member", "outsider" }
-- What a role has past every member's tabs (the Census, Realm, Chat, Decrees, Crafters, Games and
-- Wanted, each by its own rule): "watch", The Watch's desk; "heraldry", its Tabards (still the
-- King's publication for whoever is not on the patrols' staff: TabardsV2.SurfaceVisible);
-- "games-staff", the Games tab's staff section (ArenaHome.GamesStaff); "judgments", The Watch's
-- Judgments (Judgment.lua: the King's final word, the High Council's votes); "arbiter", the Games
-- tab's lines of an arbiter (ArenaHome.ArbiterShown: the King and the councillors are arbiters too,
-- ArenaRoles.IsPublicArbiter). The High Council shares the King's desk layout; local reports,
-- cases and audit records still require the real character's guild-local officer authority.
-- Correspondents and members have no tab of their own (yet): what they see is every member's.
V.GRANTS = {
	king = { throne = true, vox = true, treasury = true, watch = true, heraldry = true, ["games-staff"] = true, judgments = true, arbiter = true },
	councillor = { throne = true, vox = true, treasury = true, watch = true, heraldry = true, ["games-staff"] = true, judgments = true, arbiter = true },
	treasurer = { treasury = true, heraldry = true },
	arbiter = { heraldry = true, arbiter = true },
	gm = { throne = true, vox = true, treasury = true, watch = true, heraldry = true }, -- ("throne": his Guild tab in its place)
	officer = { treasury = true, watch = true, heraldry = true },
	correspondent = { heraldry = true },
	member = { heraldry = true },
	outsider = {},
}
-- The tabs only a role opens: under a preview, for the roles given them alone, whatever the
-- author's own character may open.
V.RESTRICTED = { throne = true, vox = true, workshop = true }

local role = "my"
local menu

-- The author, or his test build (Dev.lua).
local function Author()
	return ns.Workshop and ((ns.Workshop.IsAuthor and ns.Workshop.IsAuthor()) or (ns.Workshop.Preview and ns.Workshop.Preview()))
end

function V.Available() return Author() == true end
function V.Role() return role end
function V.Is(want) return V.Available() and role == want end
-- Another role than his own is picked: what shows is that role's, labelled as a preview.
function V.Previewing() return V.Available() and role ~= "my" end
-- A role's name in the menu (the role picked: nil).
function V.Label(key)
	key = key or role
	return rawget(L, "VIEW_AS_" .. tostring(key):upper()) or tostring(key)
end

-- Whether a role is offered now: the Arbiter only where arbiters exist (Compliance.Arbiters, 1.1.6:
-- no arbiters without a wager, so no Arbiter's preview either).
function V.Offered(key)
	if key ~= "arbiter" then return true end
	local C = ns.Compliance
	return type(C) == "table" and type(C.Arbiters) == "function" and C.Arbiters() == true
end

function V.Set(want)
	if not V.Available() then role = "my" return false end
	local found = false
	for _, v in ipairs(V.OPTIONS) do if v == want and V.Offered(v) then found = true break end end
	if not found then return false end
	role = want
	if ns.db then
		ns.db.devKingView, ns.db.devTreasurerView, ns.db.devGMView = nil, nil, nil
		-- (Asmon's view's own treasury switches and keepers, and the King's guild's centurions it
		-- named, go with it, as King.SetDevView(false) takes them: 1.1.5.)
		if want ~= "king" then ns.db.previewTreasuryFlags, ns.db.previewTreasuryKeepers, ns.db.previewMainNominees = nil, nil, nil end
	end
	ns.Fire("DATA_CHANGED")
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function V.Allows(page)
	if not V.Previewing() then return false end
	return (V.GRANTS[role] or {})[page] == true
end

-- Whether tab `key` shows (UI.Refresh): nil without the author's views (`real`, the tab's own rule,
-- stands); every tab in his own view; under a preview, the role's tabs, and every member's by their
-- own rule. "Not in Olympus" has no tab: the Join screen alone (UI.Locked).
function V.TabShown(key, real)
	if not V.Available() then return nil end
	if role == "my" then return true end
	if role == "outsider" then return false end
	if (V.GRANTS[role] or {})[key] then return true end
	if V.RESTRICTED[key] then return false end
	return real ~= false
end

-- The Join screen under "Not in Olympus": shown as it is, no row acting and no box to type in (the
-- author is in Olympus: a click there would search with /who or whisper a guild for real).
function V.Inert(lines)
	local out = {}
	for i, line in ipairs(lines or {}) do
		local copy = {}
		for k, v in pairs(line) do if k ~= "onClick" and k ~= "input" then copy[k] = v end end
		out[i] = copy
	end
	return out
end

function V.AtLeast(which)
	if not V.Available() or role == "my" then return false end
	local rank = { member = 1, officer = 2, gm = 3, councillor = 4, treasurer = 4, king = 5 }
	return (rank[role] or 0) >= (rank[which] or 99)
end

-- The menu: Olympus's own frame with a button per role (no Blizzard menu: the gamepad UI's rules),
-- in the Olympus window's metal (ns.Window, 1.1.5), under the title bar's button that opened it.
local function MakeMenu()
	local f = ns.Window("OlympusViewAsMenu", UIParent, { inset = false, close = false, title = L.VIEW_AS_TITLE })
	f:SetSize(210, #V.OPTIONS * 25 + 40)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	f.buttons = {}
	local function Choose(want)
		return function() V.Set(want); f:Hide() end
	end
	for i, key in ipairs(V.OPTIONS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(176, 21); b:SetPoint("TOP", 0, -30 - (i - 1) * 25)
		b:SetText(V.Label(key))
		b:SetScript("OnClick", Choose(key)) -- a distinct Lua 5.1 upvalue for every option
		b.key = key
		f.buttons[i] = b
	end
	ns.EscapeCloses("OlympusViewAsMenu")
	f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	return f
end

-- anchor: the button it opens under (the window's title bar); nil: the screen's middle.
function V.ShowMenu(anchor)
	if not V.Available() then return false end
	menu = menu or MakeMenu()
	local shown = 0
	for i, key in ipairs(V.OPTIONS) do
		local b = menu.buttons[i]
		if key == role then b:LockHighlight() else b:UnlockHighlight() end
		b:SetShown(V.Offered(key))
		if V.Offered(key) then
			b:ClearAllPoints(); b:SetPoint("TOP", 0, -30 - shown * 25)
			shown = shown + 1
		end
	end
	menu:SetSize(210, shown * 25 + 40)
	menu:ClearAllPoints()
	if anchor then menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	else menu:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
	menu:Show()
	return true, menu
end

-- The title bar's button: opens the menu, or closes it when it is open.
function V.ToggleMenu(anchor)
	if menu and menu:IsShown() then menu:Hide() return false end
	return V.ShowMenu(anchor)
end

function V.Reset() role = "my"; if menu then menu:Hide() end end
function V.Menu() return menu end
