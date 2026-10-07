-- The Blood Arena's meeting places (Olympus/ArenaPlaces.lua, the design): the
-- places data and its pure functions, on the real functions. Every expected value was worked
-- out by hand and with a separate script from the client's own tables (Forever 1.60.1.70124:
-- AreaTable, UiMap, UiMapAssignment, AreaTrigger), never by the module. World positions are in
-- UnitPosition's order: the first grows to the north, the second to the west.
local H = ...
local test, eq = H.test, H.eq

local function Load()
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "ArenaPlaces.lua"))("Olympus", ns)
	return ns.Places
end
local Places = Load()
local byId = Places.byId

local function Close(got, want, tol, msg)
	if type(got) ~= "number" or math.abs(got - want) > (tol or 0.001) then
		error((msg or "") .. " expected " .. tostring(want) .. ", got " .. tostring(got), 2)
	end
end
local function Ids(list)
	local out = {}
	for i, e in ipairs(list) do out[i] = e.id end
	return table.concat(out, ",")
end
local function Pt(cont, wx, wy) return { cont = cont, wx = wx, wy = wy } end
local function At(id) local p = byId[id]; return Pt(p.cont, p.wx, p.wy) end

print("ArenaPlaces: the data")

test("1.2 the places data: the places data: 63 rows (2 arenas, 15 duel spots, 46 inns: 39 rest triggers, 7 in capitals), unique ids, byId", function()
	eq(Places.BUILD, "1.60.1.70124")
	eq(#Places.list, 63)
	local kinds, rests, ids, conts = {}, {}, {}, { [0] = 0, [1] = 0 }
	for _, p in ipairs(Places.list) do
		kinds[p.kind] = (kinds[p.kind] or 0) + 1
		if p.rest then rests[p.rest] = (rests[p.rest] or 0) + 1 end
		assert(not ids[p.id], "id twice: " .. tostring(p.id))
		ids[p.id] = true
		eq(byId[p.id], p, p.id .. " in byId")
		conts[p.cont] = conts[p.cont] + 1
	end
	eq(kinds.arena, 2); eq(kinds.spot, 15); eq(kinds.inn, 46)
	eq(rests.inn, 39); eq(rests.city, 7)
	eq(conts[0], 32, "the Eastern Kingdoms"); eq(conts[1], 31, "Kalimdor")
	local n = 0
	for id, p in pairs(byId) do n = n + 1; eq(p.id, id) end
	eq(n, 63)
	-- The ones the design names.
	for _, id in ipairs({ "arena_gurubashi", "arena_the_maul", "spot_orgrimmar_gate", "spot_stormwind_gate", "spot_darnassus_gate",
		"spot_ironforge_gates", "spot_goldshire", "spot_crossroads", "spot_thunder_bluff", "spot_undercity_ruins", "spot_brill",
		"spot_southshore", "spot_tarren_mill", "spot_booty_bay", "spot_ratchet", "spot_gadgetzan", "spot_everlook",
		"tavern_slaughtered_lamb" }) do
		assert(byId[id], id)
	end
end)

test("1.2 the places data: the places data: every field's type; cont 0 or 1; every |wx| and |wy| under 20,000; no duels in a capital (Hunter Rise excepted), both flags on the Gurubashi floor, free-for-all alone in The Maul", function()
	local KINDS, FACTIONS = { arena = true, spot = true, inn = true }, { A = true, H = true, N = true }
	local function Whole(v) return type(v) == "number" and v == math.floor(v) end
	local function Text(v) return type(v) == "string" and v ~= "" end
	for _, p in ipairs(Places.list) do
		local id = tostring(p.id)
		assert(Text(p.id) and p.id:find("^[a-z_]+$"), id .. ": id")
		assert(KINDS[p.kind], id .. ": kind"); assert(FACTIONS[p.faction], id .. ": faction")
		assert(Whole(p.mapID) and p.mapID > 0, id .. ": mapID")
		assert(type(p.x) == "number" and p.x >= 0 and p.x <= 1, id .. ": x"); assert(type(p.y) == "number" and p.y >= 0 and p.y <= 1, id .. ": y")
		eq(type(p.subzone), "string", id .. ": subzone"); assert(Text(p.zone), id .. ": zone"); assert(Text(p.name), id .. ": name")
		assert(Whole(p.minLevel) and p.minLevel >= 1 and p.minLevel <= 60, id .. ": minLevel")
		assert(p.areaID == nil or (Whole(p.areaID) and p.areaID > 0), id .. ": areaID")
		assert(p.cont == 0 or p.cont == 1, id .. ": cont")
		assert(type(p.wx) == "number" and math.abs(p.wx) < 20000, id .. ": wx"); assert(type(p.wy) == "number" and math.abs(p.wy) < 20000, id .. ": wy")
		eq(type(p.duel), "boolean", id .. ": duel"); eq(type(p.ffa), "boolean", id .. ": ffa")
		assert(p.inside == nil or Text(p.inside), id .. ": inside"); assert(p.insideAreaID == nil or Whole(p.insideAreaID), id .. ": insideAreaID")
		assert(p.verify == nil or Text(p.verify), id .. ": verify")
		if p.alt ~= nil then
			eq(type(p.alt), "table", id .. ": alt")
			for _, a in ipairs(p.alt) do assert(Text(a), id .. ": alt") end
		end
		if p.kind == "inn" then
			assert(p.rest == "inn" or p.rest == "city", id .. ": rest")
			assert(Text(p.innkeeper) or Text(p.barkeep), id .. ": who keeps it"); assert(Whole(p.npc), id .. ": npc")
			if p.rest == "inn" then
				assert(Whole(p.r) and p.r > 0, id .. ": r"); assert(Whole(p.trigger), id .. ": trigger")
			else
				eq(p.r, nil, id .. ": r"); eq(p.trigger, nil, id .. ": trigger")
			end
		else
			eq(p.rest, nil, id .. ": rest"); eq(p.r, nil, id .. ": r")
		end
	end
	-- The flags (AreaTable Flags_0: 0x40 duels, 0x80 free-for-all). Battle Ring (2177) has both;
	-- The Maul (3217) is free-for-all with no duels; the capitals forbid duels, Hunter Rise (1641)
	-- excepted; the other places allow duels and are no free-for-all.
	eq(byId.arena_gurubashi.areaID, 2177); eq(byId.arena_gurubashi.duel, true); eq(byId.arena_gurubashi.ffa, true)
	eq(byId.arena_the_maul.areaID, 3217); eq(byId.arena_the_maul.duel, false); eq(byId.arena_the_maul.ffa, true)
	eq(byId.spot_thunder_bluff.areaID, 1641); eq(byId.spot_thunder_bluff.duel, true)
	for _, p in ipairs(Places.list) do
		if p.rest == "city" then
			eq(p.duel, false, p.id .. ": no duels in a capital"); eq(p.ffa, false, p.id)
		elseif p.kind ~= "arena" then
			eq(p.duel, true, p.id .. ": duels"); eq(p.ffa, false, p.id)
		end
	end
end)

-- Flags_0 of every area the rows name, as the client's AreaTable has them (build 1.60.1.70124).
local AREA_FLAGS = {
	[12] = 0x40, [14] = 0x40, [141] = 0x40, -- Elwynn Forest, Durotar, Teldrassil: the zones themselves
	[35] = 0x40000040, [42] = 0x40000040, [69] = 0x40000040, [75] = 0x40000040, [87] = 0x40000040,
	[108] = 0x40000040, [117] = 0x40000040, [131] = 0x40000040, [144] = 0x40000040, [150] = 0x40000040,
	[153] = 0x40000040, [159] = 0x40000040, [186] = 0x40000040, [222] = 0x40000040, [228] = 0x40000040,
	[271] = 0x40000040, [272] = 0x40000040, [321] = 0x40000040, [340] = 0x40000040, [349] = 0x40000040,
	[362] = 0x40000040, [378] = 0x40000040, [380] = 0x40000040, [392] = 0x40000040, [415] = 0x40000040,
	[431] = 0x40000040, [442] = 0x40000040, [460] = 0x40000040, [467] = 0x40000040, [484] = 0x40000040,
	[513] = 0x40000040, [608] = 0x40000040, [809] = 0x40000040, [976] = 0x40000040, [1099] = 0x40000040,
	[1116] = 0x40000040, [1641] = 0x40000040, [1659] = 0x40000040, [2255] = 0x40000040,
	[2268] = 0x40000040, [2408] = 0x40000040, [3317] = 0x40000040, [3425] = 0x40000040,
	[2177] = 0x400000d0, -- Battle Ring: duels and free-for-all
	[3217] = 0x40000080, -- The Maul: free-for-all, no duels
	-- The capitals' areas: no duels.
	[1497] = 0x138, [1519] = 0x138, [1537] = 0x138, [1637] = 0x138, [1638] = 0x138, [1657] = 0x138,
}
-- Where a row's point is inside a capital building whose WMO groups map to an area other than
-- areaID (or where areaID is nil: the text exists only in WMOAreaTable), that area's flags hold
-- there (WMOAreaTable.AreaTableID). The Darnassus inn's groups are named "Craftsmen's Terrace" but
-- map to Darnassus (1657, no duels); areaID 1659 is the terrace's terrain (duels), kept for the name.
local BUILDING_AREA = { inn_darnassus = 1657, inn_stormwind = 1519, tavern_slaughtered_lamb = 1519, inn_orgrimmar = 1637,
	inn_undercity = 1497 }

test("1.2 the places data: the places data: duel and ffa are the flags of the area at the point: areaID's, or the capital building's where its WMO groups map elsewhere (the Darnassus inn)", function()
	local function Bit(flags, b) return math.floor(flags / b) % 2 == 1 end
	for _, p in ipairs(Places.list) do
		local area = BUILDING_AREA[p.id] or p.areaID
		local flags = assert(AREA_FLAGS[area], p.id .. ": the flags of area " .. tostring(area))
		eq(p.duel, Bit(flags, 0x40), p.id .. ": duel, area " .. area)
		eq(p.ffa, Bit(flags, 0x80), p.id .. ": ffa, area " .. area)
	end
	-- The Darnassus inn: the terrace's own area allows duels; the building it keeps its innkeeper in does not.
	eq(byId.inn_darnassus.areaID, 1659); eq(Bit(AREA_FLAGS[1659], 0x40), true); eq(byId.inn_darnassus.duel, false)
	-- Every row without an areaID is one of those buildings.
	for _, p in ipairs(Places.list) do
		if p.areaID == nil then assert(BUILDING_AREA[p.id], p.id .. ": no areaID and no building area") end
	end
end)

-- The 39 rest triggers, as the client's AreaTrigger has them (build 1.60.1.70124): id, continent,
-- centre (Pos_0, Pos_1), and a radius, or a box (length, width, yaw; AreaTrigger shape 1).
local TRIGGERS = {
	inn_sentinel_hill = { 71, 0, -10645.900, 1179.060, radius = 27 },
	inn_goldshire = { 562, 0, -9465.580, 16.847, radius = 30 },
	inn_lakeshire = { 682, 0, -9219.370, -2149.940, radius = 30 },
	inn_darkshire = { 707, 0, -10517.000, -1158.390, radius = 30 },
	inn_southshore = { 708, 0, -854.547, -576.314, box = { 56.19, 27.53, 4.712 } }, -- half-diagonal 31.286
	inn_theramore = { 709, 1, -3615.490, -4467.340, radius = 30 },
	inn_kharanos = { 710, 0, -5601.460, -530.747, radius = 35 },
	inn_thelsamar = { 712, 0, -5390.180, -2953.930, radius = 36 },
	inn_menethil = { 713, 0, -3823.060, -834.526, radius = 30 },
	inn_dolanaar = { 715, 1, 9809.050, 959.188, radius = 32 },
	inn_auberdine = { 716, 1, 6410.010, 527.035, radius = 32 },
	inn_astranaar = { 717, 1, 2756.640, -423.057, radius = 32 },
	inn_brill = { 719, 0, 2266.680, 245.993, radius = 30 },
	inn_sepulcher = { 720, 0, 511.536, 1638.630, radius = 50 },
	inn_tarren_mill = { 721, 0, -4.944, -934.910, box = { 24.56, 25.72, 5.829 } }, -- half-diagonal 17.781
	inn_bloodhoof = { 722, 1, -2366.700, -345.983, radius = 30 },
	inn_crossroads = { 742, 1, -405.311, -2645.290, radius = 30 },
	inn_ratchet = { 743, 1, -1051.440, -3653.810, radius = 30 },
	inn_razor_hill = { 843, 1, 341.420, -4684.700, radius = 30 },
	inn_stonard = { 844, 0, -10487.300, -3256.870, radius = 30 },
	inn_booty_bay = { 862, 0, -14457.000, 496.450, radius = 28 },
	inn_camp_taurajo = { 982, 1, -2372.510, -1991.640, radius = 35 },
	inn_sun_rock = { 1022, 1, 898.482, 922.688, radius = 35 },
	inn_gadgetzan = { 1023, 1, -7162.140, -3845.950, radius = 20 },
	inn_feathermoon = { 1024, 1, -4370.830, 3289.150, radius = 35 },
	inn_camp_mojache = { 1025, 1, -4461.920, 242.578, box = { 52.67, 20.53, 3.560 } }, -- half-diagonal 28.265
	inn_aerie_peak = { 1042, 0, 357.220, -2106.090, radius = 60 },
	inn_kargath = { 1606, 0, -6657.350, -2157.100, radius = 30 },
	inn_hammerfall = { 1646, 0, -907.865, -3534.240, radius = 30 },
	inn_nijels_point = { 2266, 1, 245.587, 1251.990, radius = 40 },
	inn_shadowprey = { 2267, 1, -1596.160, 3145.260, box = { 30.03, 30.03, 0.000 } }, -- half-diagonal 21.234
	inn_freewind = { 2286, 1, -5477.910, -2460.320, radius = 20 },
	inn_everlook = { 2287, 1, 6687.990, -4670.070, radius = 20 },
	inn_splintertree = { 2610, 1, 2343.570, -2569.000, radius = 30 },
	inn_revantusk = { 3690, 0, -622.142, -4582.140, box = { 27.39, 27.17, 3.194 } }, -- half-diagonal 19.290
	inn_gromgol = { 3886, 0, -12432.800, 205.169, radius = 18 },
	inn_cenarion_hold = { 3985, 1, -6864.980, 731.612, radius = 20 },
	inn_lights_hope = { 4058, 0, 2298.170, -5340.980, box = { 33.50, 17.69, 2.182 } }, -- half-diagonal 18.942
	inn_stonetalon_peak = { 4090, 1, 2716.600, 1496.820, radius = 30 },
}
-- The six boxes: r is the radius of the circle holding the box, half its diagonal rounded up
-- (the table first gave half the longer side: 28, 13, 26, 15, 14, 17, which left each box's
-- corners outside r, and Shadowprey's and Revantusk's outside r + 5, so InnAt said "no inn" where
-- the game says the player rests).
local BOX_R = { inn_southshore = 32, inn_tarren_mill = 18, inn_camp_mojache = 29, inn_shadowprey = 22, inn_revantusk = 20, inn_lights_hope = 19 }

test("1.2 the places data: the rest triggers: each inn's trigger, continent, centre (to 0.05 yd) and r as the client's AreaTrigger has them; a box's r holds the whole box", function()
	local n = 0
	for _, p in ipairs(Places.list) do
		if p.rest == "inn" then
			n = n + 1
			local t = assert(TRIGGERS[p.id], p.id .. " in the fixture")
			eq(p.trigger, t[1], p.id .. ": trigger"); eq(p.cont, t[2], p.id .. ": continent")
			Close(p.wx, t[3], 0.051, p.id .. ": wx"); Close(p.wy, t[4], 0.051, p.id .. ": wy")
			if t.radius then
				eq(p.r, t.radius, p.id .. ": the trigger's radius")
			else
				local half = math.sqrt((t.box[1] / 2) ^ 2 + (t.box[2] / 2) ^ 2)
				assert(p.r >= half, ("%s: r %d leaves the box's corners (%.3f yd) outside"):format(p.id, p.r, half))
				assert(p.r < half + 1, p.id .. ": r rounded up, not more")
				eq(p.r, BOX_R[p.id], p.id .. ": r")
			end
		end
	end
	eq(n, 39)
	local boxes = 0
	for _ in pairs(BOX_R) do boxes = boxes + 1 end
	eq(boxes, 6)
end)

print("ArenaPlaces: the pure functions")

test("1.2 the places data: the module is pure: it loads and every function runs with only Lua's own library in reach (no WoW API, no global written)", function()
	local LUA = { math = true, table = true, string = true, ipairs = true, pairs = true, type = true, tostring = true, tonumber = true,
		select = true, next = true, error = true, assert = true, setmetatable = true, getmetatable = true, rawget = true, rawset = true,
		unpack = true, pcall = true }
	local env = setmetatable({}, {
		__index = function(_, k) if LUA[k] then return _G[k] end error("reads the global " .. tostring(k), 2) end,
		__newindex = function(_, k) error("writes the global " .. tostring(k), 2) end,
	})
	local chunk = assert(loadfile(H.ADDON_DIR .. "ArenaPlaces.lua"))
	setfenv(chunk, env)
	local ns = {}
	chunk("Olympus", ns)
	local P = ns.Places
	local a, b = Pt(0, -12600, 200), Pt(0, -13800, 600)
	assert(#P.Fair(a, b, { game = "d", faction = "A", level = 35 }) > 0)
	assert(#P.Fair(a, b, { game = "b", staked = true, faction = "Horde", level = 35 }) > 0)
	assert(#P.Near(0, -12600, 200, function(p) return p.kind == "inn" end) > 0)
	assert(P.Dist(a, b)); eq(P.Capital(1453), true); eq(P.Cell(-13202.2), 16); eq(P.Centre(16), -13400)
	assert(P.InnAt(0, -9465.6, 16.8)); eq(P.Bearing(a, b), "south"); eq(select(2, P.HBDWorld(0, 1, 2)), 2)
end)

test("1.2 the places data: the TOC loads ArenaPlaces.lua once, right after Honors.lua (a pure module) and before ArenaNet.lua; it sets ns.Places", function()
	local toc = {}
	for line in io.lines(H.ADDON_DIR .. "Olympus.toc") do
		local file = line:match("^%s*([%w_\\/]+%.lua)%s*$")
		if file then toc[#toc + 1] = file end
	end
	local at, n = nil, 0
	for i, f in ipairs(toc) do if f == "ArenaPlaces.lua" then at, n = i, n + 1 end end
	eq(n, 1)
	eq(toc[at - 1], "Honors.lua"); eq(toc[at + 1], "ArenaNet.lua")
	local ns = {}
	assert(loadfile(H.ADDON_DIR .. "ArenaPlaces.lua"))("Olympus", ns)
	eq(type(ns.Places), "table"); eq(type(ns.Places.Fair), "function"); eq(type(ns.Places.InnAt), "function")
end)

-- Two players in Stranglethorn Vale, at the centres of their 400-yd cells as the wire carries
-- them: a near Grom'gol, b north of Booty Bay.
local STV_A, STV_B = Pt(0, -12600, 200), Pt(0, -13800, 600)
-- Two in The Barrens: a by the Crossroads, b north of Camp Taurajo.
local BAR_A, BAR_B = Pt(1, -200, -2600), Pt(1, -2200, -2200)

test("1.2 the places data: Fair in Stranglethorn Vale (negative coordinates, Eastern Kingdoms): the longer walk first, then the total, both walks given; Alliance and Horde, casual and staked", function()
	-- Alliance, level 35, a casual duel: the arenas and duel spots of the Eastern Kingdoms that
	-- are the Alliance's or neutral, minLevel 35 or less. The Gurubashi floor: a 606.050 yd
	-- (602.2 south, 68.2 west), b 683.708 (597.8 north, 331.8 east).
	local list = Places.Fair(STV_A, STV_B, { game = "d", faction = "A", level = 35 })
	eq(Ids(list), "arena_gurubashi,spot_booty_bay,spot_goldshire,spot_stormwind_gate,spot_ironforge_gates,spot_southshore")
	eq(list[1].place, byId.arena_gurubashi)
	Close(list[1].a, 606.050); Close(list[1].b, 683.708)
	Close(list[2].a, 1880.940); Close(list[2].b, 665.084)
	Close(list[3].a, 3148.149); Close(list[3].b, 4379.530)
	Close(list[6].a, 11810.690); Close(list[6].b, 13037.095)
	-- Staked: the Gurubashi floor is free-for-all (a third player could end the fight): not suggested.
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", staked = true, faction = "A", level = 35 })),
		"spot_booty_bay,spot_goldshire,spot_stormwind_gate,spot_ironforge_gates,spot_southshore")
	-- The Horde's: its own spots, never the Alliance's; the long faction name works the same.
	local horde = "arena_gurubashi,spot_booty_bay,spot_tarren_mill,spot_undercity_ruins,spot_brill"
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "H", level = 35 })), horde)
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "Horde", level = 35 })), horde)
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "Alliance", level = 35 })),
		"arena_gurubashi,spot_booty_bay,spot_goldshire,spot_stormwind_gate,spot_ironforge_gates,spot_southshore")
	-- No faction: neutral ground only.
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", level = 60 })), "arena_gurubashi,spot_booty_bay")
	-- Bone Throw (Horde, 35): every inn of the Horde's or neutral, minLevel 35 or less. Grom'gol
	-- is 167.281 yd from a but 1423.061 from b; the Salty Sailor 1880.522 and 665.102: the longer
	-- walk decides, not the shorter.
	list = Places.Fair(STV_A, STV_B, { game = "b", faction = "H", level = 35 })
	eq(Ids(list), "inn_gromgol,inn_booty_bay,inn_stonard,inn_kargath,inn_hammerfall,inn_tarren_mill,inn_sepulcher,inn_undercity,inn_brill")
	Close(list[1].a, 167.281); Close(list[1].b, 1423.061); Close(list[2].a, 1880.522); Close(list[2].b, 665.102)
	-- The same for gold and for practice.
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "b", staked = true, faction = "H", level = 35 })), Ids(list))
	-- The two players the other way round: the same places, the walks swapped.
	local swapped = Places.Fair(STV_B, STV_A, { game = "b", faction = "H", level = 35 })
	eq(Ids(swapped), Ids(list)); Close(swapped[1].a, 1423.061); Close(swapped[1].b, 167.281)
end)

test("1.2 the places data: Fair in The Barrens (negative coordinates, Kalimdor): the Horde's duel spots and inns, the Alliance's inns", function()
	local list = Places.Fair(BAR_A, BAR_B, { game = "d", faction = "H", level = 20 })
	eq(Ids(list), "spot_crossroads,spot_ratchet,spot_thunder_bluff,spot_orgrimmar_gate")
	Close(list[1].a, 217.451); Close(list[1].b, 1838.131)
	Close(list[2].a, 1292.878); Close(list[2].b, 1910.920)
	Close(list[3].a, 2796.719); Close(list[3].b, 2245.235)
	Close(list[4].a, 2351.530); Close(list[4].b, 4159.896)
	-- Bone Throw: Thunder Bluff's inn (longer walk 2858.785, total 5271.453) before Bloodhoof's
	-- (3126.516, total 4987.996): the longer walk decides before the total.
	list = Places.Fair(BAR_A, BAR_B, { game = "b", faction = "H", level = 20 })
	eq(Ids(list), "inn_crossroads,inn_ratchet,inn_camp_taurajo,inn_thunder_bluff,inn_bloodhoof,inn_razor_hill,inn_sun_rock,inn_orgrimmar,inn_splintertree")
	Close(list[1].b, 1849.119); Close(list[2].b, 1852.786); Close(list[3].a, 2256.082); Close(list[3].b, 270.531)
	Close(list[4].a, 2858.785); Close(list[5].a, 3126.516)
	-- The Alliance's: Ratchet is neutral; Theramore (35) is past level 20.
	eq(Ids(Places.Fair(BAR_A, BAR_B, { game = "b", faction = "A", level = 20 })),
		"inn_ratchet,inn_astranaar,inn_stonetalon_peak,inn_auberdine,inn_dolanaar,inn_darnassus")
	-- Level 60: Gadgetzan and Everlook join; The Maul (no duels) never does, staked or not.
	local all = "spot_crossroads,spot_ratchet,spot_thunder_bluff,spot_orgrimmar_gate,spot_gadgetzan,spot_everlook"
	eq(Ids(Places.Fair(BAR_A, BAR_B, { game = "d", faction = "H", level = 60 })), all)
	eq(Ids(Places.Fair(BAR_A, BAR_B, { game = "d", staked = true, faction = "H", level = 60 })), all)
end)

test("1.2 the places data: Fair's filters: a duel never gets a place without duels (The Maul, any capital inn, any inn), a staked duel no free-for-all; level, faction and continent", function()
	local seen = {}
	for _, cont in ipairs({ 0, 1 }) do
		for _, faction in ipairs({ "A", "H" }) do
			for _, staked in ipairs({ false, true }) do
				-- Both players standing on each place in turn: the nearest is the place itself when it may be picked.
				for _, p in ipairs(Places.list) do
					if p.cont == cont then
						local here = At(p.id)
						for _, e in ipairs(Places.Fair(here, here, { game = "d", staked = staked, faction = faction, level = 60 })) do
							seen[e.id] = true
							eq(e.place.cont, cont, e.id); eq(e.place.duel, true, e.id .. ": duels allowed")
							assert(e.place.kind == "arena" or e.place.kind == "spot", e.id .. ": an arena or a spot")
							assert(e.place.faction == "N" or e.place.faction == faction, e.id .. ": faction")
							if staked then eq(e.place.ffa, false, e.id .. ": no free-for-all for a staked duel") end
						end
						for _, e in ipairs(Places.Fair(here, here, { game = "b", staked = staked, faction = faction, level = 60 })) do
							eq(e.place.kind, "inn", e.id)
						end
					end
				end
			end
		end
	end
	eq(seen.arena_the_maul, nil); eq(seen.inn_orgrimmar, nil); eq(seen.arena_gurubashi, true)
	-- On The Maul itself, the fairest duel ground is elsewhere.
	local maul = At("arena_the_maul")
	local list = Places.Fair(maul, maul, { game = "d", faction = "H", level = 60 })
	assert(list[1].id ~= "arena_the_maul")
	-- minLevel: Stranglethorn's arena and Booty Bay are for 30 and up (at level 30 exactly, yes).
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "H", level = 29 })), "spot_tarren_mill,spot_undercity_ruins,spot_brill")
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "H", level = 30 })), "arena_gurubashi,spot_booty_bay,spot_tarren_mill,spot_undercity_ruins,spot_brill")
	-- Another continent's places never: the two on different continents get nothing.
	for _, e in ipairs(Places.Fair(STV_A, STV_B, { game = "b", faction = "A", level = 60 })) do eq(e.place.cont, 0, e.id) end
	eq(#Places.Fair(STV_A, BAR_B, { game = "d", faction = "H", level = 60 }), 0)
	-- Bad terms: nothing, never an error.
	eq(#Places.Fair(STV_A, STV_B, { game = "x", faction = "H", level = 60 }), 0)
	eq(#Places.Fair(STV_A, STV_B, { game = "d", faction = "H" }), 0, "no level")
	eq(#Places.Fair(STV_A, STV_B, nil), 0)
	eq(#Places.Fair(STV_A, Pt(0, 0 / 0, 1), { game = "d", faction = "H", level = 60 }), 0)
	eq(#Places.Fair({ 0, -12600 }, STV_B, { game = "d", faction = "H", level = 60 }), 0, "two values are no point")
end)

test("1.2 the places data: a point written { cont, wx, wy } (the design's words) is the same point as { cont =, wx =, wy = } in Fair, Dist and Bearing", function()
	local a, b = { 0, -12600, 200 }, { 0, -13800, 600 }
	for _, o in ipairs({ { game = "d", faction = "A", level = 35 }, { game = "d", staked = true, faction = "H", level = 35 },
		{ game = "b", faction = "H", level = 35 } }) do
		local named, listed = Places.Fair(STV_A, STV_B, o), Places.Fair(a, b, o)
		assert(#named > 0)
		eq(Ids(listed), Ids(named), o.game)
		for i = 1, #named do eq(listed[i].a, named[i].a); eq(listed[i].b, named[i].b) end
		eq(Ids(Places.Fair(a, STV_B, o)), Ids(named), "one of each")
	end
	eq(Ids(Places.Fair(a, b, { game = "d", faction = "A", level = 35 })),
		"arena_gurubashi,spot_booty_bay,spot_goldshire,spot_stormwind_gate,spot_ironforge_gates,spot_southshore")
	eq(Places.Dist({ 0, -5000, -5000 }, { 0, -4700, -4600 }), 500)
	eq(Places.Dist({ 0, -5000, -5000 }, byId.spot_goldshire), Places.Dist(Pt(0, -5000, -5000), byId.spot_goldshire))
	eq(Places.Dist({ 0, 1, 1 }, { 1, 1, 1 }), nil, "across continents")
	eq(Places.Bearing({ 0, -5000, -5000 }, { 0, -4900, -5000 }), "north")
	eq(Places.Bearing({ 0, -5000, -5000 }, { 0, -5000, -5100 }), "east")
	-- Named fields win; a half-named table is no point; a list with a bad value is none.
	eq(Places.Dist({ cont = 0, wx = -5000, wy = -5000, 1, 99, 99 }, Pt(0, -4700, -4600)), 500)
	eq(Places.Dist({ cont = 0, -5000, -5000 }, Pt(0, -4700, -4600)), nil)
	eq(Places.Dist({ 0, -5000, 0 / 0 }, Pt(0, -4700, -4600)), nil)
	eq(Places.Dist({ "0", -5000, -5000 }, Pt(0, -4700, -4600)), nil)
end)

test("1.2 the places data: staked and the filter count as Lua truths: a stake letter or amount is staked, a filter's non-boolean true keeps the place", function()
	local casual = Ids(Places.Fair(STV_A, STV_B, { game = "d", faction = "A", level = 35 }))
	local staked = Ids(Places.Fair(STV_A, STV_B, { game = "d", staked = true, faction = "A", level = 35 }))
	assert(casual:find("arena_gurubashi", 1, true) and not staked:find("arena_gurubashi", 1, true))
	-- Whatever true value a caller has at hand (the wire's letter, the amount) keeps the free-for-all floor out.
	for _, v in ipairs({ "s", 500, 1 }) do
		eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", staked = v, faction = "A", level = 35 })), staked, tostring(v))
	end
	eq(Ids(Places.Fair(STV_A, STV_B, { game = "d", staked = false, faction = "A", level = 35 })), casual, "false: casual")
	-- A filter returning a true non-boolean keeps; false and nil drop.
	local g = At("arena_gurubashi")
	eq(Ids(Places.Near(0, g.wx, g.wy, function(p) return p.kind == "inn" and p.id end)), Ids(Places.Near(0, g.wx, g.wy, function(p) return p.kind == "inn" end)))
	eq(#Places.Near(0, g.wx, g.wy, function() return 1 end), 32)
	eq(#Places.Near(0, g.wx, g.wy, function() return nil end), 0)
	eq(#Places.Near(0, g.wx, g.wy, function() return false end), 0)
end)

-- A copy of the module over invented places, to break ties exactly: the players at a = (-5000,
-- -5000) and b = a + (300, 700). Each place is a 3-4-5 triangle away, so every walk is exact.
local function TieWorld()
	local P = Load()
	local function Spot(id, wx, wy) return { id = id, kind = "spot", faction = "N", minLevel = 1, cont = 0, wx = wx, wy = wy, duel = true, ffa = false } end
	local function Inn(id, wx, wy, r) return { id = id, kind = "inn", faction = "N", minLevel = 1, cont = 0, wx = wx, wy = wy, r = r, rest = "inn", duel = true, ffa = false } end
	P.list = {
		Spot("a_three", -4600, -4700), -- a + (400, 300): a 500, b (-100, 400) 412.311
		Spot("k_one", -4700, -4600),   -- a + (300, 400): a 500, b (0, 300) 300: total 800
		Spot("b_two", -5000, -4500),   -- a + (0, 500): a 500, b (300, 200) 360.555
		Spot("z_mid", -4850, -4650),   -- a + (150, 350): a and b both 380.789, the fair middle
		Spot("c_same", -4700, -4600),  -- where k_one is: the same walks, so the id decides
		Inn("inn_north", -3000, -3000, 30), Inn("inn_south", -3010, -3000, 30), -- 10 yd apart
	}
	return P, Pt(0, -5000, -5000), Pt(0, -4700, -4300)
end

test("1.2 the places data: Fair's ties: the same longer walk goes to the shorter total, then the same total to the id", function()
	local P, a, b = TieWorld()
	local list = P.Fair(a, b, { game = "d", faction = "A", level = 1 })
	eq(Ids(list), "z_mid,c_same,k_one,b_two,a_three")
	Close(list[1].a, 380.789); Close(list[1].b, 380.789)
	eq(list[2].a, 500); eq(list[2].b, 300); eq(list[3].a, 500); eq(list[3].b, 300)
	eq(list[4].a, 500); Close(list[4].b, 360.555); eq(list[5].a, 500); Close(list[5].b, 412.311)
	-- The order never depends on the list's order.
	local reversed = {}
	for i = #P.list, 1, -1 do reversed[#reversed + 1] = P.list[i] end
	P.list = reversed
	eq(Ids(P.Fair(a, b, { game = "d", faction = "H", level = 1 })), "z_mid,c_same,k_one,b_two,a_three")
end)

test("1.2 the places data: Near: nearest first, then the id; the filter sees each place and its distance; one continent", function()
	local g = At("arena_gurubashi")
	local list = Places.Near(0, g.wx, g.wy)
	eq(#list, 32, "every place of the Eastern Kingdoms")
	eq(list[1].id, "arena_gurubashi"); eq(list[1].d, 0)
	eq(list[2].id, "inn_gromgol"); Close(list[2].d, 771.975)
	eq(list[3].id, "inn_booty_bay"); Close(list[3].d, 1275.400)
	eq(list[4].id, "spot_booty_bay"); Close(list[4].d, 1275.848)
	eq(Ids(Places.Near(0, g.wx, g.wy, function(p) return p.kind == "inn" end)):match("^([^,]+,[^,]+,[^,]+)"), "inn_gromgol,inn_booty_bay,inn_sentinel_hill")
	eq(Ids(Places.Near(0, g.wx, g.wy, function(_, d) return d < 1000 end)), "arena_gurubashi,inn_gromgol")
	eq(#Places.Near(1, g.wx, g.wy), 31, "Kalimdor's places from the same numbers on the other continent")
	for _, e in ipairs(Places.Near(1, g.wx, g.wy)) do eq(e.place.cont, 1) end
	-- Ties by id.
	local P, a = TieWorld()
	eq(Ids(P.Near(0, a.wx, a.wy, function(p) return p.kind == "spot" end)), "z_mid,a_three,b_two,c_same,k_one")
	-- Bad arguments: nothing.
	eq(#Places.Near(0, nil, 1), 0); eq(#Places.Near("0", 1, 1), 0); eq(#Places.Near(0, 1, 1, "inn"), 0)
end)

test("1.2 the places data: Dist: straight yards on one continent, nil across continents or for a bad point", function()
	-- Outside the Stormwind gate to the Gates of Ironforge: 4037.9 north, 1205.7 east.
	Close(Places.Dist(At("spot_stormwind_gate"), At("spot_ironforge_gates")), 4214.066)
	Close(Places.Dist(byId.spot_stormwind_gate, byId.spot_ironforge_gates), 4214.066, nil, "a place row is a point")
	eq(Places.Dist(Pt(0, -5000, -5000), Pt(0, -4700, -4600)), 500)
	eq(Places.Dist(Pt(0, 1, 1), Pt(1, 1, 1)), nil)
	eq(Places.Dist(Pt(0, 1, 1), nil), nil); eq(Places.Dist(Pt(0, 1, 1), Pt(0, 1 / 0, 1)), nil)
end)

test("1.2 the places data: Capital: the six capital cities' maps, nothing else", function()
	-- UiMap: 1453 Stormwind City, 1454 Orgrimmar, 1455 Ironforge, 1456 Thunder Bluff, 1457
	-- Darnassus, 1458 Undercity.
	for _, id in ipairs({ 1453, 1454, 1455, 1456, 1457, 1458 }) do eq(Places.Capital(id), true, tostring(id)) end
	for _, id in ipairs({ 1429, 1411, 1434, 1413, 1426, 1420, 1438, 1412 }) do eq(Places.Capital(id), false, tostring(id)) end
	eq(Places.Capital(nil), false); eq(Places.Capital("1453"), false)
end)

test("1.2 the places data: Cell and Centre: floor((w + 20000) / step) and back, at negative values; 400-yd cells and 25-yd points; out of range refused", function()
	-- The Gurubashi floor, -13202.2 / 268.2: cells 16 and 50, centres -13400 and 200.
	eq(Places.Cell(-13202.2), 16); eq(Places.Cell(268.2), 50)
	eq(Places.Centre(16), -13400); eq(Places.Centre(50), 200)
	eq(Places.Cell(-13202), 16); eq(Places.Cell(268), 50)
	eq(Places.Cell(Places.Centre(16)), 16); eq(Places.Cell(Places.Centre(50)), 50)
	-- A point, 25 yd: 271 and 810, centres -13212.5 and 262.5.
	eq(Places.Cell(-13202.2, Places.POINT), 271); eq(Places.Cell(268.2, 25), 810)
	eq(Places.Centre(271, 25), -13212.5); eq(Places.Centre(810, 25), 262.5)
	-- Every cell and every point round trip.
	for c = 0, 99 do eq(Places.Cell(Places.Centre(c)), c, "cell " .. c) end
	for c = 0, 1599 do eq(Places.Cell(Places.Centre(c, 25), 25), c, "point " .. c) end
	-- Every place's cell centre is within half a cell of it on each axis.
	for _, p in ipairs(Places.list) do
		assert(math.abs(Places.Centre(Places.Cell(p.wx)) - p.wx) <= 200, p.id)
		assert(math.abs(Places.Centre(Places.Cell(p.wy)) - p.wy) <= 200, p.id)
	end
	-- The edges: -20000 is cell 0, 20000 is past the last.
	eq(Places.Cell(-20000), 0); eq(Places.Cell(19999.9), 99); eq(Places.Cell(20000), nil); eq(Places.Cell(-20000.1), nil)
	eq(Places.Centre(0), -19800); eq(Places.Centre(99), 19800); eq(Places.Centre(100), nil); eq(Places.Centre(-1), nil)
	eq(Places.Centre(1599, 25), 19987.5); eq(Places.Centre(1600, 25), nil)
	eq(Places.Centre(1.5), nil); eq(Places.Cell(0 / 0), nil); eq(Places.Cell("5"), nil); eq(Places.Cell(5, 0), nil)
	eq(Places.CELL, 400); eq(Places.POINT, 25)
end)

test("1.2 the places data: InnAt: within r + 5 yd of a rest trigger (just inside yes, just outside no), 20 yd of a capital innkeeper (15 yd yes, the city's bank no)", function()
	-- The Goldshire inn, r 30, at (-9465.6, 16.8): 34.9 yd north yes, 35.1 no; west the same.
	local inn, d = Places.InnAt(0, -9465.6 + 34.9, 16.8)
	eq(inn, byId.inn_goldshire); Close(d, 34.9)
	eq(Places.InnAt(0, -9465.6 + 35.1, 16.8), nil)
	eq(Places.InnAt(0, -9465.6, 16.8 + 34.9), byId.inn_goldshire); eq(Places.InnAt(0, -9465.6, 16.8 + 35.1), nil)
	-- A box: Shadowprey, r 22 (r + 5 = 27), at (-1596.2, 3145.3).
	eq(Places.InnAt(1, -1596.2 - 26.9, 3145.3), byId.inn_shadowprey); eq(Places.InnAt(1, -1596.2 - 27.1, 3145.3), nil)
	-- Stormwind: Innkeeper Allison at (-8867.8, 673.9): 15 yd off (9 north, 12 west) yes; 19.9 yes,
	-- 20.1 no. The bank's counter (Newton Burnside, about (-8935.0, 613.4), 90 yd away) is no inn.
	eq(Places.InnAt(0, -8867.8 + 9, 673.9 + 12), byId.inn_stormwind)
	eq(Places.InnAt(0, -8867.8 - 19.9, 673.9), byId.inn_stormwind); eq(Places.InnAt(0, -8867.8 - 20.1, 673.9), nil)
	eq(Places.InnAt(0, -8935.0, 613.4), nil)
	-- The Slaughtered Lamb (its barkeep), and Orgrimmar's inn on Kalimdor only.
	eq(Places.InnAt(0, -8953.8 + 10, 993.8), byId.tavern_slaughtered_lamb)
	eq(Places.InnAt(1, 1634.1 + 15, -4439.4), byId.inn_orgrimmar); eq(Places.InnAt(0, 1634.1 + 15, -4439.4), nil)
	-- A duel spot is no inn; the Gurubashi floor is 772 yd from the nearest.
	eq(Places.InnAt(0, -13202.2, 268.2), nil)
	-- Bad points: nil.
	eq(Places.InnAt(nil, 1, 1), nil); eq(Places.InnAt(0, "x", 1), nil); eq(Places.InnAt(0, 0 / 0, 1), nil)
	-- Two in reach: the nearer, then the id.
	local P = TieWorld()
	eq(P.InnAt(0, -3000 - 3, -3000).id, "inn_north"); eq(P.InnAt(0, -3010 + 2, -3000).id, "inn_south")
	eq(P.InnAt(0, -3005, -3000).id, "inn_north", "halfway: the id")
end)

test("1.2 the places data: InnAt holds every rest area: the corners of the six box triggers and the rims of the circles, as the client places them", function()
	for id, t in pairs(TRIGGERS) do
		local cx, cy = t[3], t[4]
		local points = {}
		if t.radius then
			for k = 0, 7 do
				local angle = k * math.pi / 4
				points[#points + 1] = { cx + t.radius * math.cos(angle), cy + t.radius * math.sin(angle) }
			end
		else
			local hl, hw, yaw = t.box[1] / 2, t.box[2] / 2, t.box[3]
			local c, s = math.cos(yaw), math.sin(yaw)
			for _, corner in ipairs({ { hl, hw }, { hl, -hw }, { -hl, hw }, { -hl, -hw } }) do
				points[#points + 1] = { cx + corner[1] * c - corner[2] * s, cy + corner[1] * s + corner[2] * c }
			end
		end
		for i, q in ipairs(points) do
			local inn = Places.InnAt(t[2], q[1], q[2])
			eq(inn and inn.id, id, ("%s: rest area point %d (%.1f, %.1f)"):format(id, i, q[1], q[2]))
		end
		eq(Places.InnAt(t[2], cx, cy).id, id, id .. ": its centre")
	end
end)

test("1.2 the places data: Bearing: eight compass words, north the first value's growth and west the second's", function()
	-- From the Stormwind gate to the Gates of Ironforge: 4037.9 north and 1205.7 east, 16.6 degrees
	-- east of north, inside north's 45 degrees (north-east starts at 22.5).
	eq(Places.Bearing(At("spot_stormwind_gate"), At("spot_ironforge_gates")), "north")
	eq(Places.Bearing(At("spot_ironforge_gates"), At("spot_stormwind_gate")), "south")
	-- Goldshire to Darkshire: 1061.4 south, 1204.8 east (131.4 degrees): south-east. The
	-- Crossroads to Ratchet: 540.5 south, 1013.3 east (118.1): south-east. Brill to Tarren Mill:
	-- 2381.7 south, 1264.6 east (152.0): south-east. Gurubashi to Booty Bay: 1255.0 south, 229.7
	-- west (190.4): south.
	eq(Places.Bearing(At("spot_goldshire"), At("inn_darkshire")), "south-east")
	eq(Places.Bearing(At("spot_crossroads"), At("spot_ratchet")), "south-east")
	eq(Places.Bearing(At("spot_brill"), At("spot_tarren_mill")), "south-east")
	eq(Places.Bearing(At("arena_gurubashi"), At("spot_booty_bay")), "south")
	-- Each word, from (-5000, -5000): +first is north, +second is west.
	local o = Pt(0, -5000, -5000)
	local function To(n, w) return Places.Bearing(o, Pt(0, -5000 + n, -5000 + w)) end
	eq(To(100, 0), "north"); eq(To(100, -100), "north-east"); eq(To(0, -100), "east"); eq(To(-100, -100), "south-east")
	eq(To(-100, 0), "south"); eq(To(-100, 100), "south-west"); eq(To(0, 100), "west"); eq(To(100, 100), "north-west")
	-- The edges, 22.5 degrees either side of a word (tan 0.41421): 41 east of 100 north is north,
	-- 42 is north-east; 42 north of 100 east is north-east, 41 is east.
	eq(To(100, -41), "north"); eq(To(100, -42), "north-east"); eq(To(42, -100), "north-east"); eq(To(41, -100), "east")
	eq(To(-100, 41), "south"); eq(To(-100, 42), "south-west")
	-- The words, for the texts' tables.
	eq(table.concat(Places.BEARINGS, ","), "north,north-east,east,south-east,south,south-west,west,north-west")
	-- The same point, another continent, a bad point: nil.
	eq(Places.Bearing(o, o), nil); eq(Places.Bearing(o, Pt(1, 0, 0)), nil); eq(Places.Bearing(o, nil), nil)
end)

test("1.2 the places data: HBDWorld: HereBeDragons takes UnitPosition's two values swapped (its own source says so)", function()
	eq(select("#", Places.HBDWorld(0, -13202.2, 268.2)), 3)
	local instance, x, y = Places.HBDWorld(0, -13202.2, 268.2)
	eq(instance, 0); eq(x, 268.2); eq(y, -13202.2)
	instance, x, y = Places.HBDWorld(1, 1350.1, -4368.3)
	eq(instance, 1); eq(x, -4368.3); eq(y, 1350.1)
	eq(Places.HBDWorld(0, nil, 1), nil)
	-- The library we ship reads UnitPosition as y, x (HereBeDragons-2.0.lua, GetPlayerWorldPosition).
	local f = assert(io.open(H.ADDON_DIR .. "libs/HereBeDragons/HereBeDragons-2.0.lua", "rb"))
	local src = f:read("*a")
	f:close()
	assert(src:find('local y, x, _z, instanceID = UnitPosition("player")', 1, true), "HereBeDragons reads UnitPosition as y, x")
	local pf = assert(io.open(H.ADDON_DIR .. "libs/HereBeDragons/HereBeDragons-Pins-2.0.lua", "rb"))
	local pins = pf:read("*a")
	pf:close()
	assert(pins:find("function pins:AddMinimapIconWorld(ref, icon, instanceID, x, y, floatOnEdge)", 1, true), "AddMinimapIconWorld's arguments")
end)
