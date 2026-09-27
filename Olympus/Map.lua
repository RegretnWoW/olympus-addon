local ADDON, ns = ...
local L = ns.L

-- World map markers: one circle per zone with the number of Olympus members there.
-- Uses HereBeDragons-Pins (the same library Questie uses), shown on the zone map,
-- its parent and the continent. A checkbox on the map toggles them, like Questie.

local Map = {}
ns.Map = Map

local Pins = ns.Pins()
Map.libOk = Pins ~= nil

local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local SHOW_HERE = HBD_PINS_WORLDMAP_SHOW_CURRENT or 0
local pool, active = {}, {}
local AddContinentTotals -- defined below, used by RefreshNow
local refreshQueued = false

local function ShortCount(n)
	if n >= 10000 then return ("%dk"):format(math.floor(n / 1000)) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(n)
end

local function PinEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.Zones.NameForKey(self.key), 1, 0.82, 0)
	GameTooltip:AddLine(L.PIN_TOTAL:format(ns.FormatNumber(self.count)), 1, 1, 1)
	local list = {}
	for name, n in pairs(self.guilds or {}) do list[#list + 1] = { name, n } end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(10, #list) do
		-- (Guilds from other players' reports: plain text, whatever they carry, 0.9.2.)
		GameTooltip:AddDoubleLine(ns.Codec.Plain(list[i][1]), ns.FormatNumber(list[i][2]), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreatePin()
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetSize(20, 20)
	p:EnableMouse(true)
	p.edge = p:CreateTexture(nil, "BACKGROUND", nil, -1)
	p.edge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	p.edge:SetVertexColor(0.9, 0.76, 0.36, 0.95)
	p.edge:SetPoint("TOPLEFT", -2, 2)
	p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
	p.bg = p:CreateTexture(nil, "BACKGROUND", nil, 1)
	p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	p.bg:SetVertexColor(0.12, 0.07, 0.02, 0.9)
	p.bg:SetAllPoints()
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.text:SetPoint("CENTER", 0, 0)
	p:SetScript("OnEnter", PinEnter)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return p
end

-- A city's map is not a child of the zone around it (Stormwind's parent is Eastern Kingdoms,
-- not Elwynn Forest), so its pin would not show on that zone's map. The zone that contains a
-- map's centre, found once through HereBeDragons' world coordinates: { zone, x, y } or false.
local containerOf = {}
local function ContainerOf(mapID)
	if containerOf[mapID] ~= nil then return containerOf[mapID] end
	local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
	if not HBD or not HBD.GetWorldCoordinatesFromZone or not C_Map.GetMapInfo then return false end
	containerOf[mapID] = false
	local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)
	local info = C_Map.GetMapInfo(mapID)
	if not wx or not info or not info.parentMapID then return false end
	local ownW, ownH = HBD:GetZoneSize(mapID)
	local best, bestArea
	for _, child in ipairs(C_Map.GetMapChildrenInfo(info.parentMapID) or {}) do
		local zone = child.mapID
		if zone ~= mapID then
			local x, y = HBD:GetZoneCoordinatesFromWorld(wx, wy, zone)
			local w, h = HBD:GetZoneSize(zone)
			local area = (w or 0) * (h or 0)
			-- A city: its whole map lies inside a zone at least four times bigger (neighbouring
			-- zones only overlap at their borders), and the smallest such zone.
			local ax, ay = HBD:GetWorldCoordinatesFromZone(0, 0, mapID)
			local bx, by = HBD:GetWorldCoordinatesFromZone(1, 1, mapID)
			local inside = ax and bx and HBD:GetZoneCoordinatesFromWorld(ax, ay, zone) and HBD:GetZoneCoordinatesFromWorld(bx, by, zone)
			if x and y and inside and area >= 4 * (ownW or 0) * (ownH or 0) and (not best or area < bestArea) then
				best, bestArea = { zone = zone, x = x, y = y }, area
			end
		end
	end
	containerOf[mapID] = best or false
	return containerOf[mapID]
end
Map.ContainerOf = ContainerOf -- for tests

local function RefreshNow()
	refreshQueued = false
	if not Pins then return end
	-- With the gamepad UI no zone circles (they are the pin library's, ns.WorldMapIcons); the
	-- continent totals below are drawn by us, never through the library, and stay.
	local world = ns.WorldMapIcons(Pins, Map)
	if world then Pins:RemoveAllWorldMapIcons(Map) end
	for i = #active, 1, -1 do
		active[i]:Hide()
		pool[#pool + 1] = active[i]
		active[i] = nil
	end
	if not ns.db.showMap or not ns.IsMember() then
		AddContinentTotals({ zoneList = {}, zoneGuilds = {} }) -- also clears the continent circles
		return
	end
	local s = ns.Data.Summary()
	for _, z in ipairs(world and s.zoneList or {}) do
		local mapID = ns.Zones.MapID(z.key)
		if mapID and z.count > 0 then
			local p = table.remove(pool) or CreatePin()
			local size = math.min(34, 16 + math.floor(5 * math.log10(z.count)))
			p:SetSize(size, size)
			p.text:SetText(ShortCount(z.count))
			p.key, p.count, p.guilds = z.key, z.count, s.zoneGuilds[z.key]
			Pins:AddWorldMapIconMap(Map, p, mapID, 0.5, 0.5, SHOW_FLAG)
			active[#active + 1] = p
			-- The same count where the city sits on the map of the zone around it.
			local around = ContainerOf(mapID)
			if around then
				local q = table.remove(pool) or CreatePin()
				q:SetSize(size, size)
				q.text:SetText(ShortCount(z.count))
				q.key, q.count, q.guilds = z.key, z.count, s.zoneGuilds[z.key]
				Pins:AddWorldMapIconMap(Map, q, around.zone, around.x, around.y, SHOW_HERE)
				active[#active + 1] = q
			end
		end
	end
	AddContinentTotals(s)
end

-- Totals per continent, drawn only on the world (Azeroth) map.
local WORLD_MAP = 947
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local continentOf = {}
local function ContinentOf(mapID)
	if continentOf[mapID] ~= nil then return continentOf[mapID] end
	local id, guard = mapID, 0
	while id and guard < 10 do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		if info.mapType == CONTINENT then
			continentOf[mapID] = id
			return id
		end
		id, guard = info.parentMapID, guard + 1
	end
	continentOf[mapID] = false
	return false
end

-- { [continentMapID] = count } plus per-guild breakdown, from a Data.Summary().
function Map.ContinentTotals(s)
	local totals, guilds = {}, {}
	for _, z in ipairs(s.zoneList) do
		local mapID = ns.Zones.MapID(z.key)
		local cont = mapID and ContinentOf(mapID)
		if cont then
			totals[cont] = (totals[cont] or 0) + z.count
			guilds[cont] = guilds[cont] or {}
			for name, n in pairs(s.zoneGuilds[z.key] or {}) do guilds[cont][name] = (guilds[cont][name] or 0) + n end
		end
	end
	return totals, guilds
end

-- Continent totals are drawn straight on the world map canvas. The pin library places
-- pins through world coordinates, which the Azeroth map does not have, so it put every
-- continent total inside Eastern Kingdoms.
local overlay, overlayData = {}, {}

local function Canvas()
	return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
end

local function CanvasScale()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	local scale = sc and sc.GetCanvasScale and sc:GetCanvasScale()
	if not scale or scale <= 0 then
		local canvas = Canvas()
		scale = canvas and canvas:GetScale() or 1
	end
	return (scale and scale > 0) and scale or 1
end

function Map.LayoutOverlay()
	for _, f in ipairs(overlay) do f:Hide() end
	local canvas = Canvas()
	if not canvas or not WorldMapFrame:IsShown() or not ns.db.showMap or not ns.IsMember() then return end
	if not WorldMapFrame.GetMapID or WorldMapFrame:GetMapID() ~= WORLD_MAP then return end
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), CanvasScale()
	for i, d in ipairs(overlayData) do
		local f = overlay[i]
		if not f then
			f = CreatePin()
			f:SetParent(canvas)
			overlay[i] = f
		end
		f:SetFrameLevel(canvas:GetFrameLevel() + 100)
		-- Undo the canvas zoom so the circle keeps the same size on screen; SetPoint offsets
		-- are in the frame's own (scaled) units, hence the * scale.
		f:SetScale(1 / scale)
		f:SetSize(44, 44)
		f.text:SetText(ShortCount(d.count))
		f.key, f.count, f.guilds = "m" .. d.cont, d.count, d.guilds
		f:ClearAllPoints()
		f:SetPoint("CENTER", canvas, "TOPLEFT", d.x * w * scale, -d.y * h * scale)
		f:Show()
	end
end

function AddContinentTotals(s)
	wipe(overlayData)
	local totals, guilds = Map.ContinentTotals(s)
	for cont, count in pairs(totals) do
		local minX, maxX, minY, maxY
		if C_Map.GetMapRectOnMap then minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(cont, WORLD_MAP) end
		if minX and maxX and minY and maxY then
			overlayData[#overlayData + 1] = { cont = cont, count = count, guilds = guilds[cont], x = (minX + maxX) / 2, y = (minY + maxY) / 2 }
		end
	end
	Map.LayoutOverlay()
end

function Map.Refresh()
	ns.SafeCall("map refresh", RefreshNow)
end

local function QueueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	ns.After(1, "map refresh", Map.Refresh)
end

-- "Olympus" menu on the world map: everything map related lives here, like Questie's toggle.
local toggle, menu
local OPTIONS = {
	{ key = "showMap", label = "MAPOPT_ZONES", apply = function() Map.Refresh() end },
	{ key = "showDecrees", label = "MAPOPT_DECREES", apply = function() ns.Decree.RefreshPins() end },
}

local function CreateMapToggle()
	if toggle or not WorldMapFrame then return end
	local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
	-- Round, bottom left corner of the map (Questie uses the top right; Forever's map has its
	-- own buttons along the bottom right).
	toggle = ns.MakeRoundButton("OlympusMapToggle", WorldMapFrame, 30)
	toggle:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 6, 6)
	toggle:SetFrameLevel(anchor:GetFrameLevel() + 50)

	local okMenu, m = pcall(CreateFrame, "Frame", "OlympusMapMenu", toggle, "BackdropTemplate")
	menu = okMenu and m or CreateFrame("Frame", "OlympusMapMenuPlain", toggle)
	menu:SetSize(170, 24 + #OPTIONS * 22)
	menu:SetPoint("BOTTOMLEFT", toggle, "TOPLEFT", 0, 2)
	if menu.SetBackdrop then
		menu:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		menu:SetBackdropColor(0, 0, 0, 0.9)
	end
	local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText(L.TITLE)
	menu.checks = {}
	for i, opt in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb:SetPoint("TOPLEFT", 6, -20 - (i - 1) * 22)
		local label = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
		label:SetText(L[opt.label])
		cb:SetScript("OnClick", function(self)
			ns.db[opt.key] = self:GetChecked() and true or false
			ns.SafeCall("map option", opt.apply)
		end)
		cb.opt = opt
		menu.checks[i] = cb
	end
	menu:SetScript("OnShow", function(self)
		for _, cb in ipairs(self.checks) do cb:SetChecked(ns.db[cb.opt.key]) end
	end)
	menu:Hide()
	toggle:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.MAPOPT_TIP, 1, 1, 1)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Map.SetEnabled(on)
	ns.db.showMap = on and true or false
	if menu and menu:IsShown() then menu:GetScript("OnShow")(menu) end
	ns.Print(ns.db.showMap and L.MAP_ON or L.MAP_OFF)
	Map.Refresh()
	ns.Fire("MAP_TOGGLED")
end

ns.On("DATA_CHANGED", QueueRefresh)

local hooked = false
local function HookWorldMap()
	if hooked or not WorldMapFrame then return end
	hooked = true
	local function relayout() ns.SafeCall("map overlay", Map.LayoutOverlay) end
	if WorldMapFrame.OnMapChanged then pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", relayout) end
	WorldMapFrame:HookScript("OnShow", relayout)
	WorldMapFrame:HookScript("OnHide", relayout)
	local sc = WorldMapFrame.ScrollContainer
	if sc then
		sc:HookScript("OnMouseWheel", relayout)
		sc:HookScript("OnSizeChanged", relayout)
	end
end

-- The pin library's world map provider, with the gamepad UI (0.9.9). On every map change, and
-- at each loading screen, it clears its pins from the map whether it has any or not, through
-- RemoveAllPinsByTemplate: that marks the map's canvas dirty (MarkCanvasDirty clears its current
-- zoom) from the library's code, which is ours when our copy is the one loaded. The gamepad map
-- then zooms, builds its button bar and closes with B in our taint, and the game blocks it
-- until a /reload. So there, with none of the library's pins on the map, it returns at once:
-- there is nothing to clear. With pins to clear, and always with mouse and keyboard, the
-- library's own code runs, as it came. Only our own copy (another addon's code is not ours to
-- change), wrapped once at login, before the map is first opened; the provider and its pool
-- stay, other addons may use this copy too.
local providerQuiet = false
function Map.QuietPinsProvider()
	if providerQuiet then return true end
	local lib = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	local provider = type(lib) == "table" and lib.worldmapProvider
	local original = type(provider) == "table" and provider.RemoveAllData
	if type(original) ~= "function" or type(issecurevariable) ~= "function" then return false end
	local _, owner = issecurevariable(provider, "RemoveAllData")
	if owner ~= ADDON then return false end
	providerQuiet = true
	provider.RemoveAllData = function(self, ...)
		if ns.GamepadUI() then
			local pinPool = lib.worldmapPinsPool
			if type(pinPool) == "table" and type(pinPool.GetNumActive) == "function" and pinPool:GetNumActive() == 0 then return end
		end
		return original(self, ...)
	end
	return true
end

ns.On("LOGIN", function()
	ns.SafeCall("map provider", Map.QuietPinsProvider)
	ns.SafeCall("map hooks", HookWorldMap)
	if not Pins then
		local raw = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
		-- A half-loaded library can still run its per-frame update and raise an error on
		-- every frame. Stop it: no map features is fine, a flood of errors is not.
		if raw and raw.updateFrame then
			raw.updateFrame:SetScript("OnUpdate", nil)
			raw.updateFrame:SetScript("OnEvent", nil)
			raw.updateFrame:UnregisterAllEvents()
			ns.Log("stopped the broken map library update loop")
		end
		local minors = LibStub and LibStub.minors or {}
		ns.Log("map library unavailable: pins=%s minor=%s hbd=%s AddWorldMapIconMap=%s RemoveAll=%s AddMinimap=%s",
			tostring(raw ~= nil), tostring(minors["HereBeDragons-Pins-2.0"]), tostring(minors["HereBeDragons-2.0"]),
			tostring(raw and raw.AddWorldMapIconMap ~= nil), tostring(raw and raw.RemoveAllWorldMapIcons ~= nil),
			tostring(raw and raw.AddMinimapIconMap ~= nil))
		ns.Log("map env: WorldMapFrame=%s GetCanvas=%s pinPools=%s AddDataProvider=%s CreateUnsecuredRegionPoolInstance=%s CreateFramePool=%s MapCanvasPinMixin=%s Minimap=%s",
			tostring(WorldMapFrame ~= nil), tostring(WorldMapFrame and WorldMapFrame.GetCanvas ~= nil),
			type(WorldMapFrame and WorldMapFrame.pinPools), tostring(WorldMapFrame and WorldMapFrame.AddDataProvider ~= nil),
			tostring(CreateUnsecuredRegionPoolInstance ~= nil), tostring(CreateFramePool ~= nil),
			tostring(MapCanvasPinMixin ~= nil), tostring(Minimap ~= nil))
	end
	CreateMapToggle()
	if not toggle then
		ns.RegisterEvent("ADDON_LOADED", function(name)
			if name == "Blizzard_WorldMap" then CreateMapToggle(); ns.SafeCall("map hooks", HookWorldMap) end
		end)
	end
	QueueRefresh()
end)
