local ADDON, ns = ...

-- Local, explicitly requested guidance to an existing training inn. No player location, King
-- policy, crown, waypoint, consent or network state is read or changed. The registry's world
-- coordinates describe an inn's rest area (a capital's keeper spot), not live NPC GPS or a route.
local Arrow = {}
ns.InnkeeperArrow = Arrow
Arrow.NATIVE_ATLAS = "UI-HUD-Minimap-Arrow-Player"
Arrow.NATIVE_TEXTURE = "Interface\\Minimap\\MinimapArrow"
Arrow.REFRESH = 1
Arrow.DIRECTION = 0.08

local frame, ticker, target, drawn
local active, reason, elapsed = false, "inactive", 0
local pinRef = {}
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Finite(v)
	return type(v) == "number" and not Secret(v) and v == v and v ~= math.huge and v ~= -math.huge
end
local function Pins() return ns.Pins and ns.Pins() or nil end

-- The nearest inn eligible under the registry's existing faction/neutral and minimum-level
-- rules. A barkeep-only row is not a training keeper (FarkleTable.Innkeeper uses the same field).
function Arrow.Target()
	if not ns.IsMember or not ns.IsMember() then return nil, "membership" end
	if not IsInInstance or not UnitPosition or not UnitLevel then return nil, "position-api" end
	local ok, inside = pcall(IsInInstance)
	if not ok or Secret(inside) or type(inside) ~= "boolean" then return nil, "instance-api" end
	if inside then return nil, "instance" end
	local read, wx, wy, _, cont = pcall(UnitPosition, "player")
	if not read or not Finite(wx) or not Finite(wy) or not Finite(cont) then return nil, "position" end
	local known, level = pcall(UnitLevel, "player")
	if not known or not Finite(level) or level < 1 then return nil, "level" end
	local faction
	if UnitFactionGroup then
		local got, value = pcall(UnitFactionGroup, "player")
		faction = got and not Secret(value) and value or nil
	end
	if faction ~= "Alliance" and faction ~= "Horde" then return nil, "faction" end
	local P = ns.Places
	if not P or not P.Fair or not P.InnAt or not P.HBDWorld then return nil, "places-api" end
	local pos = { cont = cont, wx = wx, wy = wy }
	local inn, distance
	for _, entry in ipairs(P.Fair(pos, pos, { game = "b", faction = faction, level = level })) do
		local place = entry.place
		if type(place.innkeeper) == "string" and place.innkeeper ~= "" and Finite(place.npc)
			and place.npc > 0 and place.npc == math.floor(place.npc) then inn, distance = place, entry.a; break end
	end
	if not inn then return nil, "no-inn" end
	if IsResting then
		local rest, resting = pcall(IsResting)
		local at = P.InnAt(cont, wx, wy)
		if rest and not Secret(resting) and resting == true and at and at.id == inn.id then return nil, "arrived", inn end
	end
	return inn, "shown", distance
end

function Arrow.Cancel(why) -- gp:minimap!undo
	active, reason, target = false, why or "cancelled", nil
	if ticker and ticker.Cancel then ticker:Cancel() end
	ticker = nil
	if frame then
		frame:SetScript("OnUpdate", nil)
		frame.icon:SetAlpha(0)
		local pins = Pins()
		if pins and pins.RemoveMinimapIcon then pcall(pins.RemoveMinimapIcon, pins, pinRef, frame) end
		frame:Hide()
	end
	drawn, elapsed = nil, 0
	return false, reason
end

local function MakeFrame() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return nil end
	if frame then return frame end
	if type(Minimap) ~= "table" or not CreateFrame then return nil end
	local f = CreateFrame("Frame", nil, Minimap)
	if not f or not f.CreateTexture or not f.SetSize or not f.SetScript or not f.Hide or not f.Show then return nil end
	f:Hide()
	f.olympus = true
	f:SetSize(26, 26)
	if f.EnableMouse then f:EnableMouse(false) end
	if f.SetFrameLevel and Minimap.GetFrameLevel then f:SetFrameLevel(Minimap:GetFrameLevel() + 2) end
	local icon = f:CreateTexture(nil, "OVERLAY")
	if not icon or not icon.SetAlpha or not icon.SetRotation then return nil end
	local native = false
	if icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
		local ok, info = pcall(C_Texture.GetAtlasInfo, Arrow.NATIVE_ATLAS)
		if ok and info ~= nil then native = pcall(icon.SetAtlas, icon, Arrow.NATIVE_ATLAS, true) end
	end
	if not native and icon.SetTexture then native = pcall(icon.SetTexture, icon, Arrow.NATIVE_TEXTURE) end
	if not native then return nil end
	if icon.SetAllPoints then icon:SetAllPoints() end
	if icon.SetBlendMode then icon:SetBlendMode("ADD") end
	icon:SetAlpha(0)
	f.icon, frame = icon, f
	return f
end

local function Atan2(y, x)
	if math.atan2 then return math.atan2(y, x) end
	if x > 0 then return math.atan(y / x) end
	if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
	if y > 0 then return math.pi / 2 end
	if y < 0 then return -math.pi / 2 end
	return 0
end

-- HereBeDragons positions the pin, including the rotating minimap. Read that screen vector,
-- as KingArrow does, instead of guessing player facing/map axes. Show inside minimap range too.
local function UpdateDirection() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return Arrow.Cancel("gamepad") end
	if not active or not drawn or not frame then return false end
	if not frame.GetCenter or not Minimap or not Minimap.GetCenter then frame.icon:SetAlpha(0); return false end
	local fx, fy = frame:GetCenter()
	local mx, my = Minimap:GetCenter()
	if not Finite(fx) or not Finite(fy) or not Finite(mx) or not Finite(my) or (fx == mx and fy == my) then
		frame.icon:SetAlpha(0); return false
	end
	local ok = pcall(frame.icon.SetRotation, frame.icon, -Atan2(fx - mx, fy - my))
	frame.icon:SetAlpha(ok and 1 or 0)
	return ok
end

local function Failed(where, err)
	Arrow.Cancel("error")
	if ns.Log then ns.Log("innkeeper minimap arrow %s: %s", where, tostring(err)) end
	return false, "error"
end

function Arrow.UpdateDirection() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return Arrow.Cancel("gamepad") end
	local ok, result = pcall(UpdateDirection)
	if not ok then return Failed("direction", result) end
	return result
end

local function Refresh() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return Arrow.Cancel("gamepad") end
	if not active then return false, reason end
	local inn, why = Arrow.Target()
	if not inn then return Arrow.Cancel(why) end
	local pins = Pins()
	if not pins or not pins.AddMinimapIconWorld or not pins.RemoveMinimapIcon then return Arrow.Cancel("pin-api") end
	local f = MakeFrame()
	if not f then return Arrow.Cancel("frame-api") end
	if not drawn or drawn ~= inn.id then
		if drawn then pcall(pins.RemoveMinimapIcon, pins, pinRef, f) end
		local instanceID, x, y = ns.Places.HBDWorld(inn.cont, inn.wx, inn.wy)
		local ok, added = pcall(pins.AddMinimapIconWorld, pins, pinRef, f, instanceID, x, y, true)
		if not ok or added ~= true then return Arrow.Cancel("pin-api") end
		drawn = inn.id
	end
	target, reason = inn, why
	f:Show()
	UpdateDirection()
	return true, target
end

function Arrow.Refresh() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return Arrow.Cancel("gamepad") end
	local ok, result, detail = pcall(Refresh)
	if not ok then return Failed("refresh", result) end
	return result, detail
end

local function Start() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return false, "gamepad" end
	Arrow.Cancel("restart")
	active = true
	local ok, why = Arrow.Refresh()
	if not ok then return false, why end
	-- Only an active request owns a ticker. Cancel/arrival/instance/API failure cancels it.
	if not ns.Every or not C_Timer or not C_Timer.NewTicker then return Arrow.Cancel("timer-api") end
	local made, handle = pcall(ns.Every, Arrow.REFRESH, "innkeeper minimap arrow", Arrow.Refresh)
	if not made then return Failed("timer", handle) end
	ticker = handle
	if not ticker or not ticker.Cancel then return Arrow.Cancel("timer-api") end
	frame:SetScript("OnUpdate", function(_, dt) -- gp:minimap
		if not ns.Gate.Allowed("minimap") then Arrow.Cancel("gamepad"); return end
		elapsed = elapsed + (tonumber(dt) or 0)
		if elapsed < Arrow.DIRECTION then return end
		elapsed = 0
		Arrow.UpdateDirection()
	end)
	return true, target
end

function Arrow.Start() -- gp:minimap
	if not ns.Gate.Allowed("minimap") then return false, "gamepad" end
	local ok, result, detail = pcall(Start)
	if not ok then return Failed("start", result) end
	return result, detail
end

function Arrow.State()
	return { active = active, reason = reason, target = target, frame = frame, ticker = ticker, pinRef = pinRef }
end

ns.On("LOGOUT", function() Arrow.Cancel("logout") end)
