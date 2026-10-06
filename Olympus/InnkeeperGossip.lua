local ADDON, ns = ...

-- An opt-in, addon-owned row and dialogue inside the NPC panel. Never add/select a server
-- gossip option or replace the native provider. The guarded shape follows Blizzard's
-- UIPanels_Game/Classic/GossipFrame.xml (Blizzard's wow-ui-source/classic mirror).
-- The exact Forever shape is unverified: optional capability/geometry checks fail closed and
-- preserve the Olympus offer. Source-backed gamepad fixtures never pretend these APIs exist.
local G = {}; ns.InnkeeperGossip = G
local GATE = "innkeeper-gossip"
G.DICE_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
G.ROW_HEIGHT = 24
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
		or not Method(f, "IsProtected") or not Method(f, "Hide")
		or not panel or not Method(scroll, "GetHeight") or not Method(scroll, "SetHeight")
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
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 24)
	b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	b.label:SetPoint("LEFT", 22, 0); b.label:SetWidth(width - 24)
	b.label:SetJustifyH("LEFT"); b.label:SetTextColor(0.15, 0.08, 0)
	b.label:SetText(caption)
	b:SetScript("OnClick", click)
	return b
end

local function Build(f, panel, scroll) -- gp:innkeeper-gossip
	if not ns.Gate.Allowed(GATE) then return false end
	if host == f and row and dialog then return true end
	G.Park()
	if not CreateFrame then return false end
	host = f
	row = Button(panel, scroll:GetWidth(), "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Open()
	end)
	row:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 2, 0); row.icon:SetTexture(G.DICE_TEXTURE)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	dialog = CreateFrame("Frame", nil, panel)
	dialog:SetPoint("TOPLEFT", scroll, "TOPLEFT", 8, -8)
	dialog:SetSize(scroll:GetWidth() - 16, scroll:GetHeight() - G.ROW_HEIGHT - 16)
	dialog.text = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	dialog.text:SetPoint("TOPLEFT", 0, 0); dialog.text:SetWidth(scroll:GetWidth() - 20)
	dialog.text:SetJustifyH("LEFT"); dialog.text:SetJustifyV("TOP"); dialog.text:SetTextColor(0.15, 0.08, 0)
	dialog.confirm = Button(dialog, scroll:GetWidth() - 24, "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Confirm()
	end)
	dialog.confirm:SetPoint("TOPLEFT", dialog.text, "BOTTOMLEFT", 0, -20)
	dialog.cancel = Button(dialog, scroll:GetWidth() - 24, "", function() -- gp:innkeeper-gossip
		if not ns.Gate.Allowed(GATE) then return end
		G.Cancel()
	end)
	dialog.cancel:SetPoint("TOPLEFT", dialog.confirm, "BOTTOMLEFT", 0, -8)
	row:Hide(); dialog:Hide()
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
	local height = scroll:GetHeight()
	if type(height) ~= "number" or height ~= height or height <= 2 * G.ROW_HEIGHT then return false, "geometry" end
	saved = { scroll = scroll, bar = bar, height = height, scrollShown = scroll:IsShown(), barShown = bar:IsShown() }
	keeper, innID, mode = name, id, "row"
	scroll:SetHeight(height - G.ROW_HEIGHT)
	row.label:SetText(ns.L.FARKLE_NAME .. ": " .. (ns.FarkleTable.TrainingComplete() and ns.L.FARKLE_KEEPER_AGAIN or ns.L.FARKLE_KEEPER_LEARN))
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
	dialog.confirm.label:SetText(complete and L.FARKLE_KEEPER_AGAIN or L.FARKLE_KEEPER_LEARN)
	dialog.cancel.label:SetText(L.FARKLE_KEEPER_NOT_NOW)
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
