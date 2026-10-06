local ADDON, ns = ...

-- An opt-in, addon-owned row and dialogue inside the NPC panel. Never add/select a server
-- gossip option or replace the native provider. The optional native shape, base choice template
-- and extent API are verified in Forever 1.60.1.70235's UI source (wow-ui-source a84e2b1):
-- UIPanels_Game/Mainline/GossipFrame.xml, Shared/GossipFrameShared.lua and SharedXML/Shared/Scroll/ScrollBox.lua.
-- Capability/geometry checks fail closed and preserve the Olympus offer on other clients.
local G = {}; ns.InnkeeperGossip = G
local GATE = "innkeeper-gossip"
G.DICE_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
G.ROW_GAP = 4
local host, row, dialog, saved, keeper, innID
local generation, mode = 0, "inactive"
local hooked = setmetatable({}, { __mode = "k" })
local function Method(obj, key) return obj and type(obj[key]) == "function" end

local function Context()
	if not ns.IsMember or not ns.IsMember() then return nil, "membership" end
	if not InCombatLockdown or InCombatLockdown() then return nil, "combat" end
	local FT = ns.FarkleTable
	if not FT or not FT.Innkeeper or not FT.Live or FT.Live() then return nil, "game" end
	local name, id = FT.Innkeeper(true)
	if not name or not id then return nil, "npc" end
	return name, id
end

local function Native() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return nil end
	local f = rawget(_G, "GossipFrame")
	local panel = f and f.GreetingPanel
	local scroll, bar = panel and panel.ScrollBox, panel and panel.ScrollBar
	if not Method(f, "IsShown") or not f:IsShown() or not Method(f, "HookScript")
		or not Method(f, "RegisterFontStrings") or not Method(f, "UpdateFontStrings")
		or not Method(f, "IsProtected") or not Method(f, "Hide")
		or not panel or not Method(scroll, "GetHeight") or not Method(scroll, "SetHeight")
		or not Method(scroll, "GetDerivedExtent")
		or not Method(scroll, "GetNumPoints") or scroll:GetNumPoints() ~= 1
		or not Method(scroll, "IsProtected")
		or not Method(scroll, "GetWidth") or not Method(scroll, "IsShown")
		or not Method(scroll, "Show") or not Method(scroll, "Hide")
		or not Method(bar, "IsShown") or not Method(bar, "Show") or not Method(bar, "Hide")
		or not Method(bar, "IsProtected")
		or not rawget(_G, "C_GossipInfo") or type(rawget(_G, "C_GossipInfo").CloseGossip) ~= "function" then return nil end
	-- Parking also runs in combat. Never borrow geometry from a protected native region.
	local checked, protected = pcall(f.IsProtected, f)
	if not checked or protected ~= false then return nil end
	checked, protected = pcall(scroll.IsProtected, scroll)
	if not checked or protected ~= false then return nil end
	checked, protected = pcall(bar.IsProtected, bar)
	if not checked or protected ~= false then return nil end
	return f, panel, scroll, bar
end

function G.Park() -- gp:innkeeper-gossip!undo
	generation = generation + 1
	if row then row:Hide() end
	if dialog then dialog:Hide() end
	if saved then
		saved.scroll:SetHeight(saved.height)
		if saved.scrollShown then saved.scroll:Show() else saved.scroll:Hide() end
		if saved.barShown then saved.bar:Show() else saved.bar:Hide() end
	end
	saved, keeper, innID, mode = nil, nil, nil, "inactive"
end

local function Button(parent, width, caption, click) -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return nil end
	-- The base template supplies the game's quest font, icon and ADD hover. Its Option
	-- derivative also selects a server choice: use only the base, with our own local click.
	local b = CreateFrame("Button", nil, parent, "GossipTitleButtonTemplate")
	b:Hide()
	if not Method(b, "GetFontString") or not Method(b, "SetTextAndResize")
		or not Method(b.Icon, "SetTexture") then return nil end
	b.label, b.icon = b:GetFontString(), b.Icon
	if not Method(b.label, "SetWidth") then return nil end
	b:SetWidth(width); b.label:SetWidth(width - 25)
	b:SetTextAndResize(caption)
	b:SetScript("OnClick", click)
	-- Native spell tooltips are irrelevant to these choices; keep template callbacks gated too.
	local function Hover() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
	end
	b:SetScript("OnEnter", Hover); b:SetScript("OnLeave", Hover)
	return b
end

local function Build(f, panel, scroll) -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false end
	if host == f and row and dialog then return true end
	G.Park()
	if not CreateFrame then return false end
	local nextRow = Button(panel, scroll:GetWidth(), "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Open()
	end)
	if not nextRow then return false end
	nextRow.icon:SetTexture(G.DICE_TEXTURE)
	local nextDialog = CreateFrame("Frame", nil, panel)
	nextDialog:Hide()
	nextDialog:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
	nextDialog:SetSize(scroll:GetWidth(), scroll:GetHeight())
	nextDialog.text = nextDialog:CreateFontString(nil, "ARTWORK", "QuestFont")
	nextDialog.text:SetPoint("TOPLEFT", 10, -10); nextDialog.text:SetWidth(scroll:GetWidth() - 30)
	nextDialog.text:SetJustifyH("LEFT"); nextDialog.text:SetJustifyV("TOP")
	nextDialog.confirm = Button(nextDialog, scroll:GetWidth(), "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Confirm()
	end)
	if not nextDialog.confirm then return false end
	nextDialog.confirm.icon:SetTexture(G.DICE_TEXTURE)
	-- Blizzard leaves two 16px gossip spacers between greeting and choices.
	nextDialog.confirm:SetPoint("TOPLEFT", nextDialog.text, "BOTTOMLEFT", -10, -32)
	nextDialog.cancel = Button(nextDialog, scroll:GetWidth(), "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Cancel()
	end)
	if not nextDialog.cancel then return false end
	nextDialog.cancel:SetPoint("TOPLEFT", nextDialog.confirm, "BOTTOMLEFT", 0, 0)
	-- Native choices register with the host's quest contrast theme before it colors them.
	f:RegisterFontStrings(nextRow.label, nextDialog.text, nextDialog.confirm.label, nextDialog.cancel.label)
	f:UpdateFontStrings()
	host, row, dialog = f, nextRow, nextDialog
	return true
end

function G.ShowRow() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false, "gamepad" end
	local name, id = Context()
	if not name then G.Park(); return false, id end
	local f, panel, scroll, bar = Native()
	if not f then G.Park(); return false, "native-api" end
	G.Park()
	local ok, built = pcall(Build, f, panel, scroll)
	if not ok or not built then G.Park(); return false, "frame-api" end
	row:SetTextAndResize(ns.L.FARKLE_NAME .. ": " .. (ns.FarkleTable.TrainingComplete() and ns.L.FARKLE_KEEPER_AGAIN or ns.L.FARKLE_KEEPER_LEARN))
	local height, rowHeight = scroll:GetHeight(), row:GetHeight()
	local measured, extent = pcall(scroll.GetDerivedExtent, scroll)
	if not measured or type(extent) ~= "number" or extent ~= extent or extent <= 0 or extent == math.huge
		or type(height) ~= "number" or height ~= height or height == math.huge
		or type(rowHeight) ~= "number" or rowHeight ~= rowHeight or rowHeight <= 0
		or height <= 2 * (rowHeight + G.ROW_GAP) then return false, "geometry" end
	saved = { scroll = scroll, bar = bar, height = height, scrollShown = scroll:IsShown(), barShown = bar:IsShown() }
	keeper, innID, mode = name, id, "row"
	local rowTop = math.min(extent, height - rowHeight - G.ROW_GAP)
	if extent > rowTop then scroll:SetHeight(rowTop) end
	row:ClearAllPoints(); row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(rowTop + G.ROW_GAP))
	row:Show()
	if not hooked[f] then
		hooked[f] = true
		f:HookScript("OnHide", function() -- gp:innkeeper-gossip
			if not ns.Gate.Allowed(GATE) then return end
			G.Park()
		end)
	end
	return true
end

function G.Open() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false, "gamepad" end
	local name, id = Context()
	if not saved or not Native() or not name or id ~= innID or name ~= keeper then G.Park(); return false, "npc" end
	local FT, L = ns.FarkleTable, ns.L
	local complete = FT.TrainingComplete()
	local voice = FT.InnkeeperVoice and FT.InnkeeperVoice()
	local flavor = voice and rawget(L, "FARKLE_KEEPER_FLAVOR_" .. voice:upper()) or nil
	dialog.text:SetText(complete and L.FARKLE_KEEPER_DONE:format(name) or L.FARKLE_KEEPER_HELLO:format(name, flavor or L.FARKLE_KEEPER_FLAVOR))
	dialog.confirm:SetTextAndResize(complete and L.FARKLE_KEEPER_AGAIN or L.FARKLE_KEEPER_LEARN)
	dialog.cancel:SetTextAndResize(L.FARKLE_KEEPER_NOT_NOW)
	dialog.confirm:Show(); dialog.cancel:Show()
	saved.scroll:Hide(); saved.bar:Hide(); row:Hide(); dialog:Show(); mode = "dialog"
	return true
end

function G.Cancel() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false end
	-- Cancel remains in the NPC conversation and restores its unmodified native choices.
	G.Park()
	return G.ShowRow()
end

function G.Confirm() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false, "gamepad" end
	local name, id = Context()
	local native = Native()
	if mode ~= "dialog" or not native or not name or id ~= innID or name ~= keeper then G.Park(); return false, "npc" end
	local FT, R = ns.FarkleTable, ns.FarkleRules
	if not FT.ShowUI or not R or not R.TARGETS then G.Park(); return false, "training-api" end
	local opts = not FT.TrainingComplete() and { target = R.TARGETS[1], learn = true } or nil
	if FT.InnkeeperVoice then FT.InnkeeperVoice() end
	G.Park()
	local closed = pcall(rawget(_G, "C_GossipInfo").CloseGossip)
	if not closed then return false, "native-api" end
	-- Some clients deliver GOSSIP_CLOSED later. Finish closing the checked, unprotected panel
	-- before the board opens; its Blizzard OnHide handler still owns the normal close cleanup.
	if native:IsShown() then native:Hide() end
	if ns.InnkeeperArrow then ns.InnkeeperArrow.Cancel("training") end
	return FT.ShowUI("practice", nil, opts)
end

function G.OnShow() -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return end
	G.Park()
	if not ns.After then return end
	local current = generation
	-- Blizzard also handles GOSSIP_SHOW; wait one frame for its own layout, without polling.
	ns.After(0, "Bones native gossip", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		if current == generation then
			local shown = G.ShowRow()
			if not shown then
				local name = Context()
				if name then ns.FarkleTable.ShowUI("innkeeper", nil, name) end
			end
		end
	end)
end

function G.State() return { mode = mode, host = host, row = row, dialog = dialog, saved = saved } end
local function Install() -- gp:innkeeper-gossip!hook
	if not ns.Gate.Allowed(GATE) then return end
	if Native() then G.OnShow() end
end
ns.Gate.Hooks(GATE, { install = Install, park = G.Park, leftover = function() return saved ~= nil end })
for _, event in ipairs({ "GOSSIP_CLOSED", "PLAYER_REGEN_DISABLED", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" }) do
	pcall(ns.RegisterEvent, event, function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		if event == "GOSSIP_CLOSED" or event == "PLAYER_REGEN_DISABLED" or not Context() then G.Park() end
	end)
end
ns.On("LOGOUT", G.Park)
