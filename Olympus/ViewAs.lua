local ADDON, ns = ...
local L = ns.L

-- View as (1.1.5, the author's ask; 1.2 widens it to every role): the author's local preview, picked
-- from a button in the Olympus window's title bar, left of the help button. In 1.1.5 it switches the
-- previews the addon already has: Asmon's view (King.Preview), the Treasurer's view
-- (Treasury.DevView) and the guild master's view (Nominees.DevView). Presentation only: nothing it
-- does is sent, no rank or authority changes. Olympus's own button and menu (no Blizzard dropdown:
-- the gamepad UI's rules), the window's metal frame (ns.Window).
local V = {}
ns.ViewAs = V

V.OPTIONS = { "my", "king", "treasurer", "gm" }

local menu

function V.Available() return ns.Workshop ~= nil and ns.Workshop.Visible ~= nil and ns.Workshop.Visible() == true end

-- The role whose preview is on ("my": none).
function V.Role()
	if ns.King and ns.King.Preview and ns.King.Preview() then return "king" end
	if ns.Treasury and ns.Treasury.DevView and ns.Treasury.DevView() then return "treasurer" end
	if ns.Nominees and ns.Nominees.DevView and ns.Nominees.DevView() then return "gm" end
	return "my"
end
function V.Previewing() return V.Available() and V.Role() ~= "my" end
function V.Label(key) return rawget(L, "VIEW_AS_" .. tostring(key or V.Role()):upper()) or tostring(key) end

-- One preview at a time: the others off, then the one picked on ("my": all off).
function V.Set(want)
	if not V.Available() then return false end
	local found = false
	for _, v in ipairs(V.OPTIONS) do if v == want then found = true break end end
	if not found then return false end
	local K, T, N = ns.King, ns.Treasury, ns.Nominees
	if want ~= "king" and K and K.Preview and K.Preview() then K.SetDevView(false) end
	if want ~= "treasurer" and T and T.DevView and T.DevView() then T.SetDevView(false) end
	if want ~= "gm" and N and N.DevView and N.DevView() then N.SetDevView(false) end
	if want == "king" and not K.Preview() then K.SetDevView(true) end
	if want == "treasurer" and not T.DevView() then T.SetDevView(true) end
	if want == "gm" and not N.DevView() then N.SetDevView(true) end
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

local function MakeMenu()
	local f = ns.Window("OlympusViewAsMenu", UIParent, { inset = false, close = false })
	f:SetSize(210, #V.OPTIONS * 25 + 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	if f.TitleText then f.TitleText:SetText(L.VIEW_AS_TITLE) end
	f.buttons = {}
	local function Choose(want) return function() V.Set(want); f:Hide() end end
	for i, key in ipairs(V.OPTIONS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(176, 21); b:SetPoint("TOP", 0, -30 - (i - 1) * 25)
		b:SetText(V.Label(key))
		b:SetScript("OnClick", Choose(key))
		b.key = key
		f.buttons[i] = b
	end
	ns.EscapeCloses("OlympusViewAsMenu")
	f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	return f
end

function V.ShowMenu(anchor)
	if not V.Available() then return false end
	menu = menu or MakeMenu()
	local now = V.Role()
	for i, key in ipairs(V.OPTIONS) do
		if key == now then menu.buttons[i]:LockHighlight() else menu.buttons[i]:UnlockHighlight() end
	end
	menu:ClearAllPoints()
	if anchor then menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2) else menu:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
	menu:Show()
	return true, menu
end

function V.ToggleMenu(anchor)
	if menu and menu:IsShown() then menu:Hide() return false end
	return V.ShowMenu(anchor)
end
function V.Menu() return menu end
