local ADDON, ns = ...
local L = ns.L

-- Royal decrees sent to every Olympus guild over OlympusNet:
--   ARMS   "Call to Arms!"  (Horde attacking here) - raid warning + sound, marker for 5 min
--   MUSTER "Muster here"    (gather point)          - softer alert, marker for 30 min
-- Only Captains (rank <= ns.CAPTAIN_RANK) can send. Receivers rate-limit per sender.

local Decree = {}
ns.Decree = Decree

local Pins = ns.Pins()
local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local DURATION = { ARMS = 5 * 60, MUSTER = 30 * 60, ROYAL = 60 * 60, HERALDRY = 60 * 60 }
local CROWN_ONLY = { ROYAL = true, HERALDRY = true }
Decree.CROWN_ONLY = CROWN_ONLY
local SEND_COOLDOWN = 60
local PER_SENDER_COOLDOWN = 60
local MAX_PER_MINUTE = 6

local active = {}          -- list of decrees
local lastSent = 0
local lastBySender = {}
local recent = {}          -- timestamps of accepted decrees (flood guard)

local function Where()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	return mapID, x, y
end

local LABEL = { ARMS = "ARMS", MUSTER = "MUSTER", ROYAL = "ROYAL", HERALDRY = "HERALDRY_CALL" }
local ICONS = {
	ARMS = "Interface\\Icons\\Ability_Warrior_WarCry",
	MUSTER = "Interface\\Icons\\INV_Misc_Horn_01",
	ROYAL = "Interface\\AddOns\\Olympus\\media\\logo64",
	HERALDRY = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
}
local function Label(d)
	return L[LABEL[d.kind] or "MUSTER"]
end
Decree.Label = Label

local function PinEnter(self)
	local d = self.decree
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Label(d), 1, 0.25, 0.25)
	if d.text ~= "" then GameTooltip:AddLine(d.text, 1, 1, 1, true) end
	GameTooltip:AddLine(L.DECREE_BY:format(d.sender, d.guild ~= "" and d.guild or "?", ns.Ago(d.t)), 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function MakePin(d)
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(34, 34)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexture(ICONS[d.kind] or ICONS.MUSTER)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetVertexColor(d.kind == "ARMS" and 1 or 1, d.kind == "ARMS" and 0.2 or 0.8, 0.2)
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(64, 64)
	f:EnableMouse(true)
	f:SetScript("OnEnter", PinEnter)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.decree = d
	return f
end

local function Show(d)
	d.expires = d.t + DURATION[d.kind]
	table.insert(active, 1, d)
	local zone = ns.Zones.NameForKey("m" .. d.mapID)
	local text = ("%s %s%s"):format(Label(d), zone, d.text ~= "" and (" - " .. d.text) or "")
	ns.Print(("|cffff4040%s|r  (%s <%s>)"):format(text, d.sender, d.guild))
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.1 })
	end
	ns.PlayAlert(d.kind == "MUSTER" and "soft" or "loud")
	if Pins then d.pin = MakePin(d) end
	Decree.RefreshPins()
	ns.Log("decree %s from %s <%s> map %d", d.kind, d.sender, d.guild, d.mapID)
	ns.Fire("DECREES_CHANGED")
end

-- (Not on the world map with the gamepad UI: ns.WorldMapIcons.)
local function RefreshPinsNow()
	if not Pins then return end
	local world = ns.WorldMapIcons(Pins, Decree)
	for _, d in ipairs(active) do
		if d.pin then
			if ns.db.showDecrees then
				if world then Pins:AddWorldMapIconMap(Decree, d.pin, d.mapID, d.x, d.y, SHOW_FLAG) end
			else
				if world then Pins:RemoveWorldMapIcon(Decree, d.pin) end
				d.pin:Hide()
			end
		end
	end
end

function Decree.RefreshPins()
	ns.SafeCall("decree pins", RefreshPinsNow)
end

function Decree.CanSend(kind)
	if CROWN_ONLY[kind] then return ns.IsCrown() end
	return ns.Roster.IsOfficer()
end

function Decree.Send(kind, text)
	if not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	if CROWN_ONLY[kind] and not ns.IsCrown() then
		ns.Print(L.CROWN_ONLY)
		return
	end
	if not ns.Roster.IsOfficer() then
		ns.Print(L.DECREE_OFFICERS_ONLY)
		return
	end
	local now = ns.Now()
	if now - lastSent < SEND_COOLDOWN then
		ns.Print(L.DECREE_COOLDOWN:format(SEND_COOLDOWN - (now - lastSent)))
		return
	end
	local mapID, x, y = Where()
	if not mapID then
		ns.Print(L.DECREE_NO_POSITION)
		return
	end
	lastSent = now
	local guild = GetGuildInfo("player") or ""
	ns.Comm.Send("CHANNEL", ns.Codec.EncodeDecree(kind, mapID, x, y, guild, ns.Roster.MyRank(), text))
	Show({ kind = kind, mapID = mapID, x = x, y = y, guild = guild, rank = ns.Roster.MyRank(), text = text or "", sender = ns.DisplayName(ns.me), t = now })
end

-- Local-only preview so anyone can see what a decree looks like (nothing is sent).
function Decree.Preview(kind)
	local mapID, x, y = Where()
	if not mapID then return end
	Show({ kind = kind, mapID = mapID, x = x, y = y, guild = GetGuildInfo("player") or "Olympus", rank = 0,
		text = L.DECREE_PREVIEW_TEXT, sender = ns.DisplayName(ns.me), t = ns.Now() })
end

function Decree.Active()
	local now, out = ns.Now(), {}
	for i = #active, 1, -1 do
		local d = active[i]
		if now > d.expires then
			if Pins and d.pin then
				if ns.WorldMapIcons(Pins, Decree) then Pins:RemoveWorldMapIcon(Decree, d.pin) end
				d.pin:Hide()
			end
			table.remove(active, i)
		end
	end
	for _, d in ipairs(active) do out[#out + 1] = d end
	return out
end

ns.Comm.Handle("D1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local d = ns.Codec.DecodeDecree(text)
	if not d or not ns.IsFederation(d.guild) then return end
	-- Trust the rank we can verify, never the rank written in the message.
	local rank = ns.Data.KnownRank(sender, d.guild)
	if not rank then
		ns.Log("decree from %s ignored: rank in %s not verified", sender, d.guild)
		return
	end
	d.rank = rank
	if CROWN_ONLY[d.kind] then
		if not ns.IsCrownRank(d.guild, rank) then return end
	elseif rank > ns.CAPTAIN_RANK then
		return
	end
	local now = ns.Now()
	if lastBySender[sender] and now - lastBySender[sender] < PER_SENDER_COOLDOWN then return end
	for i = #recent, 1, -1 do if now - recent[i] > 60 then table.remove(recent, i) end end
	if #recent >= MAX_PER_MINUTE then return end
	lastBySender[sender] = now
	recent[#recent + 1] = now
	d.sender, d.t = ns.DisplayName(sender), now
	Show(d)
end)

ns.On("LOGIN", function()
	ns.Every(15, "decree expiry", function()
		local before = #active
		Decree.Active()
		if #active ~= before then ns.Fire("DECREES_CHANGED") end
	end)
end)
