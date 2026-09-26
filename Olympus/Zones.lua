local ADDON, ns = ...

-- The guild roster gives zone names as localized text. We turn them into uiMapIDs so
-- players on different client languages agree, and so the map knows where to draw.

local Zones = {}
ns.Zones = Zones

local ROOT_MAP = 947 -- Azeroth
local byName, count

local function build()
	byName, count = {}, 0
	if not (C_Map and C_Map.GetMapChildrenInfo) then return end
	local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
	local function add(info)
		if info and info.name and info.name ~= "" then
			if not byName[info.name] or info.mapType == zoneType then
				if not byName[info.name] then count = count + 1 end
				byName[info.name] = info.mapID
			end
		end
	end
	local queue, visited = { ROOT_MAP }, {}
	while #queue > 0 do
		local id = table.remove(queue)
		if not visited[id] then
			visited[id] = true
			local children = C_Map.GetMapChildrenInfo(id)
			if children then
				for _, info in ipairs(children) do
					add(info)
					queue[#queue + 1] = info.mapID
				end
			end
		end
	end
	-- Fallback if the map tree is different on this client (e.g. a new game version).
	if count == 0 and C_Map.GetMapInfo then
		for id = 1, 2500 do add(C_Map.GetMapInfo(id)) end
	end
	ns.Log("zones indexed: %d", count)
end

function Zones.Count()
	return count or 0
end

function Zones.KeyForName(name)
	if not name or name == "" then return nil end
	if not byName then build() end
	local id = byName[name]
	if id then return "m" .. id end
	return "t" .. name
end

function Zones.MapID(key)
	if key and key:sub(1, 1) == "m" then return tonumber(key:sub(2)) end
	return nil
end

function Zones.NameForKey(key)
	local id = Zones.MapID(key)
	if id then
		local info = C_Map.GetMapInfo(id)
		return info and info.name or key
	end
	-- A zone a report named as text: shown as plain text, whatever it carries (0.9.2).
	return ns.Codec.Plain((key or "?"):sub(2))
end
