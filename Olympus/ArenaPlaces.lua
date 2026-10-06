local ADDON, ns = ...

-- Meeting places for the Blood Arena's matchmaking (1.2): the open-world arenas, the duel spots
-- players use, and every inn (the Bones tavern rule), with the pure functions that choose
-- among them (below the table). Data and arithmetic only: no events, no frames, no messages, no
-- saved data, no WoW API.
-- Built from the WoW: Forever client of build 1.60.1.70124 (AreaTable, WMOAreaTable, UiMap,
-- UiMapAssignment and AreaTrigger from wago.tools, plus that build's map tiles and WMOs).
-- Sources, method and the in-game checks still open: the matchmaking notes (places.md) this
-- table came with.
--
-- Positions. World positions are in the order UnitPosition("player") returns them: the first
-- value (wx) grows to the north, the second (wy) to the west. Both are negative on much of each
-- continent, and every place's lies between -20000 and 20000 (UiMapAssignment: Kalimdor -11,733
-- to 12,800 and -19,733 to 17,067; the Eastern Kingdoms -16,000 to 7,467 and -19,200 to 16,000).
-- Distances are straight lines in yards.
--
-- Each place:
--   id        stable key
--   kind      "arena" | "spot" | "inn"
--   faction   "A" | "H" | "N" (neutral ground both factions use)
--   mapID     uiMapID, as C_Map.GetBestMapForUnit("player") returns it there
--   x, y      0-1 position on mapID, as C_Map.GetPlayerMapPosition(mapID, "player"):GetXY()
--   subzone   enUS GetSubZoneText() standing at x, y ("" = no subzone, the zone itself)
--   zone      enUS GetZoneText()
--   minLevel  lower bound of the zone's level range (1 in capitals)
--   areaID    AreaTable id of the area at x, y (the subzone, or the zone when subzone is ""):
--             C_Map.GetAreaInfo(areaID) gives the localized name, and its flags duel and ffa
--             (but see duel); nil when the text exists only in WMOAreaTable (no localized name
--             via the API)
--   name      enUS label for the UI
--   inside    enUS GetSubZoneText() inside the inn building, where it differs from subzone
--   insideAreaID  AreaTable id of inside, when it has one
--   alt       other texts shown on the same site
--   cont, wx, wy  continent (0 Eastern Kingdoms, 1 Kalimdor) and world position, in the order
--             UnitPosition("player") returns them: yards between places without map math
--   r         rest trigger radius in yards (inns outside the capitals): the radius of the circle
--             that holds the whole rest area. Six inns rest in a box, not a circle (AreaTrigger
--             shape 1: Southshore 708, Tarren Mill 721, Camp Mojache 1025, Shadowprey 2267,
--             Revantusk 3690, Light's Hope 4058); their r is half the box's diagonal, rounded up
--             (the table first had half its longer side, which left the corners outside)
--   rest      "inn" (the inn's rest trigger) or "city" (the whole capital is a rest area)
--   duel      the area at x, y allows /duel (AreaTable flag 0x40); false: "Dueling isn't allowed
--             here". That area is areaID's, except inside a capital building whose WMO groups map
--             to the city's area (WMOAreaTable): the Darnassus inn's groups carry the text
--             "Craftsmen's Terrace" but map to Darnassus (1657, no duels), while areaID 1659, the
--             terrace's terrain, allows them; the rows without an areaID take their building's
--             area the same way (Stormwind City, Orgrimmar, Undercity). Fair never offers an inn
--             for a duel, so this changes no choice.
--   ffa       free-for-all PvP ground (AreaTable flag 0x80), from the same area as duel
--   innkeeper, barkeep, npc  who keeps the place (name, creature id)
--   trigger   AreaTrigger id of the rest area
--   verify    what still needs an in-game check

local Places = {}
ns.Places = Places

Places.BUILD = "1.60.1.70124"
Places.list = {
	-- Open-world arenas (free-for-all ground)
	{ id = "arena_gurubashi", kind = "arena", faction = "N", mapID = 1434, x = 0.306, y = 0.478,
		subzone = "Battle Ring", zone = "Stranglethorn Vale", minLevel = 30, areaID = 2177,
		name = "Gurubashi Arena", alt = { "Gurubashi Arena", "The Great Arena" }, cont = 0,
		wx = -13202.2, wy = 268.2, duel = true, ffa = true,
		verify = "FFA and duels on the floor (AreaTable 2177 flags); the stands are WMO 568 (text \"The Great Arena\", AreaTable 1741: duels, no FFA)." },
	{ id = "arena_the_maul", kind = "arena", faction = "N", mapID = 1444, x = 0.626, y = 0.299,
		subzone = "The Maul", zone = "Feralas", minLevel = 40, areaID = 3217,
		name = "The Maul, Dire Maul", cont = 1, wx = -3752.0, wy = 1091.0, duel = false,
		ffa = true,
		verify = "AreaTable 3217 has the free-for-all flag and lacks the duel flag: expect \"Dueling isn't allowed here\" in the pit." },
	-- Duel spots
	{ id = "spot_orgrimmar_gate", kind = "spot", faction = "H", mapID = 1411, x = 0.455, y = 0.130,
		subzone = "", zone = "Durotar", minLevel = 1, areaID = 14,
		name = "Outside the Orgrimmar gate", cont = 1, wx = 1350.1, wy = -4368.3, duel = true,
		ffa = false,
		verify = "Durotar ground south of the gate guards; the city (AreaTable 1637) forbids duels." },
	{ id = "spot_ironforge_gates", kind = "spot", faction = "A", mapID = 1426, x = 0.528,
		y = 0.367, subzone = "Gates of Ironforge", zone = "Dun Morogh", minLevel = 1, areaID = 809,
		name = "Gates of Ironforge", cont = 0, wx = -5082.1, wy = -798.3, duel = true,
		ffa = false },
	{ id = "spot_stormwind_gate", kind = "spot", faction = "A", mapID = 1429, x = 0.325, y = 0.510,
		subzone = "", zone = "Elwynn Forest", minLevel = 1, areaID = 12,
		name = "Outside the Stormwind gate", cont = 0, wx = -9120.0, wy = 407.4, duel = true,
		ffa = false,
		verify = "Just past the city guards on the Elwynn side; Valley of Heroes terrain (AreaTable 1617) also allows duels but the city's WMO groups do not." },
	{ id = "spot_goldshire", kind = "spot", faction = "A", mapID = 1429, x = 0.429, y = 0.655,
		subzone = "Goldshire", zone = "Elwynn Forest", minLevel = 1, areaID = 87,
		name = "Goldshire", cont = 0, wx = -9455.6, wy = 46.4, duel = true, ffa = false },
	{ id = "spot_darnassus_gate", kind = "spot", faction = "A", mapID = 1438, x = 0.378, y = 0.543,
		subzone = "", zone = "Teldrassil", minLevel = 1, areaID = 141,
		name = "Outside the Darnassus gate", cont = 1, wx = 9988.4, wy = 1889.9, duel = true,
		ffa = false },
	{ id = "spot_crossroads", kind = "spot", faction = "H", mapID = 1413, x = 0.519, y = 0.300,
		subzone = "The Crossroads", zone = "The Barrens", minLevel = 10, areaID = 380,
		name = "The Crossroads", cont = 1, wx = -414.4, wy = -2636.3, duel = true, ffa = false },
	{ id = "spot_thunder_bluff", kind = "spot", faction = "H", mapID = 1456, x = 0.581, y = 0.838,
		subzone = "Hunter Rise", zone = "Thunder Bluff", minLevel = 1, areaID = 1641,
		name = "Hunter Rise, Thunder Bluff", cont = 1, wx = -1433.1, wy = -89.8, duel = true,
		ffa = false,
		verify = "Hunter Rise (AreaTable 1641) has the duel flag, unlike the rest of the city; no rest flag there." },
	{ id = "spot_undercity_ruins", kind = "spot", faction = "H", mapID = 1420, x = 0.586,
		y = 0.690, subzone = "Ruins of Lordaeron", zone = "Tirisfal Glades", minLevel = 1,
		areaID = 153, name = "Ruins of Lordaeron, outside the Undercity", cont = 0, wx = 1758.9,
		wy = 385.3, duel = true, ffa = false,
		verify = "The ruins' WMO groups (Forever WMO 20736) map to AreaTable 1497 Undercity, which forbids duels; only open ground outside the walls (terrain area 153) allows them. Brill is the safe alternative." },
	{ id = "spot_brill", kind = "spot", faction = "H", mapID = 1420, x = 0.593, y = 0.502,
		subzone = "Brill", zone = "Tirisfal Glades", minLevel = 1, areaID = 159, name = "Brill",
		cont = 0, wx = 2325.2, wy = 353.7, duel = true, ffa = false },
	{ id = "spot_southshore", kind = "spot", faction = "A", mapID = 1424, x = 0.498, y = 0.568,
		subzone = "Southshore", zone = "Hillsbrad Foothills", minLevel = 20, areaID = 271,
		name = "Southshore", cont = 0, wx = -811.7, wy = -526.9, duel = true, ffa = false },
	{ id = "spot_tarren_mill", kind = "spot", faction = "H", mapID = 1424, x = 0.618, y = 0.214,
		subzone = "Tarren Mill", zone = "Hillsbrad Foothills", minLevel = 20, areaID = 272,
		name = "Tarren Mill", cont = 0, wx = -56.5, wy = -910.9, duel = true, ffa = false },
	{ id = "spot_booty_bay", kind = "spot", faction = "N", mapID = 1434, x = 0.270, y = 0.773,
		subzone = "Booty Bay", zone = "Stranglethorn Vale", minLevel = 30, areaID = 35,
		name = "Booty Bay", cont = 0, wx = -14457.2, wy = 497.9, duel = true, ffa = false },
	{ id = "spot_ratchet", kind = "spot", faction = "N", mapID = 1413, x = 0.619, y = 0.380,
		subzone = "Ratchet", zone = "The Barrens", minLevel = 10, areaID = 392, name = "Ratchet",
		cont = 1, wx = -954.9, wy = -3649.6, duel = true, ffa = false },
	{ id = "spot_gadgetzan", kind = "spot", faction = "N", mapID = 1446, x = 0.524, y = 0.269,
		subzone = "Gadgetzan", zone = "Tanaris", minLevel = 40, areaID = 976, name = "Gadgetzan",
		cont = 1, wx = -7112.4, wy = -3834.3, duel = true, ffa = false },
	{ id = "spot_everlook", kind = "spot", faction = "N", mapID = 1452, x = 0.613, y = 0.371,
		subzone = "Everlook", zone = "Winterspring", minLevel = 53, areaID = 2255,
		name = "Everlook", cont = 1, wx = 6777.3, wy = -4669.0, duel = true, ffa = false },
	-- Inns and taverns (the Bones tavern rule)
	{ id = "inn_sentinel_hill", kind = "inn", faction = "A", mapID = 1436, x = 0.525, y = 0.534,
		subzone = "Sentinel Hill", zone = "Westfall", minLevel = 10, areaID = 108,
		name = "Sentinel Hill inn", cont = 0, wx = -10645.9, wy = 1179.1, r = 27, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Heather", npc = 8931, trigger = 71 },
	{ id = "inn_goldshire", kind = "inn", faction = "A", mapID = 1429, x = 0.438, y = 0.659,
		subzone = "Goldshire", zone = "Elwynn Forest", minLevel = 1, areaID = 87,
		name = "Goldshire inn", cont = 0, wx = -9465.6, wy = 16.8, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Farley", npc = 295, trigger = 562,
		verify = "Forever replaced the Goldshire inn model (WMO 21072, no area names), so the Classic text \"Lion's Pride Inn\" should no longer show; expect \"Goldshire\" inside." },
	{ id = "inn_lakeshire", kind = "inn", faction = "A", mapID = 1433, x = 0.216, y = 0.445,
		subzone = "Lakeshire", zone = "Redridge Mountains", minLevel = 15, areaID = 69,
		name = "Lakeshire Inn", inside = "Lakeshire Inn", cont = 0, wx = -9219.4, wy = -2149.9,
		r = 30, rest = "inn", duel = true, ffa = false, innkeeper = "Innkeeper Brianna",
		npc = 6727, trigger = 682,
		verify = "Inside text may be \"Lakeshire Inn\" (root row) or \"Lakeshire\" (group rows' AreaTable 69). Forever changed Redridge's map bounds: Classic coordinates (26.8, 44.8) are wrong here." },
	{ id = "inn_darkshire", kind = "inn", faction = "A", mapID = 1431, x = 0.738, y = 0.445,
		subzone = "Darkshire", zone = "Duskwood", minLevel = 18, areaID = 42,
		name = "Scarlet Raven Tavern", inside = "Scarlet Raven Tavern", cont = 0, wx = -10517.0,
		wy = -1158.4, r = 30, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Trelayne", npc = 6790, trigger = 707,
		verify = "Inside text from the WMO root row; expect \"Scarlet Raven Tavern\" (as Classic shows \"Lion's Pride Inn\" from the same row shape)." },
	{ id = "inn_southshore", kind = "inn", faction = "A", mapID = 1424, x = 0.513, y = 0.588,
		subzone = "Southshore", zone = "Hillsbrad Foothills", minLevel = 20, areaID = 271,
		name = "Southshore inn", cont = 0, wx = -854.5, wy = -576.3, r = 32, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Anderson", npc = 2352, trigger = 708 },
	{ id = "inn_theramore", kind = "inn", faction = "A", mapID = 1445, x = 0.665, y = 0.452,
		subzone = "Theramore Isle", zone = "Dustwallow Marsh", minLevel = 35, areaID = 513,
		name = "Theramore inn", cont = 1, wx = -3615.5, wy = -4467.3, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Janene", npc = 6272, trigger = 709 },
	{ id = "inn_kharanos", kind = "inn", faction = "A", mapID = 1426, x = 0.474, y = 0.525,
		subzone = "Kharanos", zone = "Dun Morogh", minLevel = 1, areaID = 131,
		name = "Thunderbrew Distillery", inside = "Thunderbrew Distillery", insideAreaID = 2102,
		cont = 0, wx = -5601.5, wy = -530.7, r = 35, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Belm", npc = 1247, trigger = 710 },
	{ id = "inn_thelsamar", kind = "inn", faction = "A", mapID = 1432, x = 0.348, y = 0.491,
		subzone = "Thelsamar", zone = "Loch Modan", minLevel = 10, areaID = 144,
		name = "Stoutlager Inn", inside = "Stoutlager Inn", insideAreaID = 2101, cont = 0,
		wx = -5390.2, wy = -2953.9, r = 36, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Hearthstove", npc = 6734, trigger = 712 },
	{ id = "inn_menethil", kind = "inn", faction = "A", mapID = 1437, x = 0.108, y = 0.608,
		subzone = "Menethil Harbor", zone = "Wetlands", minLevel = 20, areaID = 150,
		name = "Deepwater Tavern", inside = "Deepwater Tavern", insideAreaID = 2104, cont = 0,
		wx = -3823.1, wy = -834.5, r = 30, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Helbrek", npc = 1464, trigger = 713 },
	{ id = "inn_dolanaar", kind = "inn", faction = "A", mapID = 1438, x = 0.561, y = 0.596,
		subzone = "Dolanaar", zone = "Teldrassil", minLevel = 1, areaID = 186,
		name = "Dolanaar inn", cont = 1, wx = 9809.0, wy = 959.2, r = 32, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Keldamyr", npc = 6736, trigger = 715 },
	{ id = "inn_auberdine", kind = "inn", faction = "A", mapID = 1439, x = 0.369, y = 0.440,
		subzone = "Auberdine", zone = "Darkshore", minLevel = 10, areaID = 442,
		name = "Auberdine inn", cont = 1, wx = 6410.0, wy = 527.0, r = 32, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Shaussiy", npc = 6737, trigger = 716 },
	{ id = "inn_astranaar", kind = "inn", faction = "A", mapID = 1440, x = 0.368, y = 0.499,
		subzone = "Astranaar", zone = "Ashenvale", minLevel = 18, areaID = 415,
		name = "Astranaar inn", cont = 1, wx = 2756.6, wy = -423.1, r = 32, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Kimlya", npc = 6738, trigger = 717 },
	{ id = "inn_brill", kind = "inn", faction = "H", mapID = 1420, x = 0.617, y = 0.521,
		subzone = "Brill", zone = "Tirisfal Glades", minLevel = 1, areaID = 159,
		name = "Gallows' End Tavern", inside = "Gallows' End Tavern", insideAreaID = 2119,
		cont = 0, wx = 2266.7, wy = 246.0, r = 30, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Renee", npc = 5688, trigger = 719 },
	{ id = "inn_sepulcher", kind = "inn", faction = "H", mapID = 1421, x = 0.431, y = 0.413,
		subzone = "The Sepulcher", zone = "Silverpine Forest", minLevel = 10, areaID = 228,
		name = "The Sepulcher inn", cont = 0, wx = 511.5, wy = 1638.6, r = 50, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Bates", npc = 6739, trigger = 720 },
	{ id = "inn_tarren_mill", kind = "inn", faction = "H", mapID = 1424, x = 0.625, y = 0.190,
		subzone = "Tarren Mill", zone = "Hillsbrad Foothills", minLevel = 20, areaID = 272,
		name = "Tarren Mill inn", cont = 0, wx = -4.9, wy = -934.9, r = 18, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Shay", npc = 2388, trigger = 721 },
	{ id = "inn_bloodhoof", kind = "inn", faction = "H", mapID = 1412, x = 0.459, y = 0.642,
		subzone = "Bloodhoof Village", zone = "Mulgore", minLevel = 1, areaID = 222,
		name = "Bloodhoof Village inn", cont = 1, wx = -2366.7, wy = -346.0, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Kauth", npc = 6747, trigger = 722,
		verify = "Forever changed Mulgore's map bounds: Classic coordinates (46.6, 61.1) are wrong here." },
	{ id = "inn_crossroads", kind = "inn", faction = "H", mapID = 1413, x = 0.520, y = 0.299,
		subzone = "The Crossroads", zone = "The Barrens", minLevel = 10, areaID = 380,
		name = "Crossroads inn", cont = 1, wx = -405.3, wy = -2645.3, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Boorand Plainswind", npc = 3934,
		trigger = 742 },
	{ id = "inn_ratchet", kind = "inn", faction = "N", mapID = 1413, x = 0.619, y = 0.394,
		subzone = "Ratchet", zone = "The Barrens", minLevel = 10, areaID = 392,
		name = "Ratchet inn", cont = 1, wx = -1051.4, wy = -3653.8, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Wiley", npc = 6791, trigger = 743 },
	{ id = "inn_razor_hill", kind = "inn", faction = "H", mapID = 1411, x = 0.515, y = 0.416,
		subzone = "Razor Hill", zone = "Durotar", minLevel = 1, areaID = 362,
		name = "Razor Hill inn", cont = 1, wx = 341.4, wy = -4684.7, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Grosk", npc = 6928, trigger = 843 },
	{ id = "inn_stonard", kind = "inn", faction = "H", mapID = 1435, x = 0.451, y = 0.567,
		subzone = "Stonard", zone = "Swamp of Sorrows", minLevel = 35, areaID = 75,
		name = "Stonard inn", cont = 0, wx = -10487.3, wy = -3256.9, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Karakul", npc = 6930, trigger = 844 },
	{ id = "inn_booty_bay", kind = "inn", faction = "N", mapID = 1434, x = 0.270, y = 0.773,
		subzone = "Booty Bay", zone = "Stranglethorn Vale", minLevel = 30, areaID = 35,
		name = "The Salty Sailor Tavern", inside = "The Salty Sailor Tavern", cont = 0,
		wx = -14457.0, wy = 496.5, r = 28, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Skindle", npc = 6807, trigger = 862,
		verify = "Booty Bay is a new WMO in Forever; the tavern groups are named \"The Salty Sailor Tavern\"." },
	{ id = "inn_camp_taurajo", kind = "inn", faction = "H", mapID = 1413, x = 0.455, y = 0.590,
		subzone = "Camp Taurajo", zone = "The Barrens", minLevel = 10, areaID = 378,
		name = "Camp Taurajo inn", cont = 1, wx = -2372.5, wy = -1991.6, r = 35, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Byula", npc = 7714, trigger = 982 },
	{ id = "inn_sun_rock", kind = "inn", faction = "H", mapID = 1442, x = 0.476, y = 0.620,
		subzone = "Sun Rock Retreat", zone = "Stonetalon Mountains", minLevel = 15, areaID = 460,
		name = "Sun Rock Retreat inn", cont = 1, wx = 898.5, wy = 922.7, r = 35, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Jayka", npc = 7731, trigger = 1022 },
	{ id = "inn_gadgetzan", kind = "inn", faction = "N", mapID = 1446, x = 0.526, y = 0.280,
		subzone = "Gadgetzan", zone = "Tanaris", minLevel = 40, areaID = 976,
		name = "Gadgetzan inn", cont = 1, wx = -7162.1, wy = -3845.9, r = 20, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Fizzgrimble", npc = 7733, trigger = 1023 },
	{ id = "inn_feathermoon", kind = "inn", faction = "A", mapID = 1444, x = 0.310, y = 0.433,
		subzone = "Feathermoon Stronghold", zone = "Feralas", minLevel = 40, areaID = 1116,
		name = "Feathermoon Stronghold inn", cont = 1, wx = -4370.8, wy = 3289.1, r = 35,
		rest = "inn", duel = true, ffa = false, innkeeper = "Innkeeper Shyria", npc = 7736,
		trigger = 1024 },
	{ id = "inn_camp_mojache", kind = "inn", faction = "H", mapID = 1444, x = 0.748, y = 0.452,
		subzone = "Camp Mojache", zone = "Feralas", minLevel = 40, areaID = 1099,
		name = "Camp Mojache inn", cont = 1, wx = -4461.9, wy = 242.6, r = 29, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Greul", npc = 7737, trigger = 1025 },
	{ id = "inn_aerie_peak", kind = "inn", faction = "A", mapID = 1425, x = 0.138, y = 0.432,
		subzone = "Wildhammer Keep", zone = "The Hinterlands", minLevel = 40, areaID = 349,
		name = "Wildhammer Keep inn", cont = 0, wx = 357.2, wy = -2106.1, r = 60, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Thulfram", npc = 7744, trigger = 1042 },
	{ id = "inn_kargath", kind = "inn", faction = "H", mapID = 1418, x = 0.031, y = 0.463,
		subzone = "Kargath", zone = "Badlands", minLevel = 35, areaID = 340, name = "Kargath inn",
		cont = 0, wx = -6657.4, wy = -2157.1, r = 30, rest = "inn", duel = true, ffa = false,
		innkeeper = "Innkeeper Shul'kar", npc = 9356, trigger = 1606 },
	{ id = "inn_hammerfall", kind = "inn", faction = "H", mapID = 1417, x = 0.741, y = 0.323,
		subzone = "Hammerfall", zone = "Arathi Highlands", minLevel = 30, areaID = 321,
		name = "Hammerfall inn", cont = 0, wx = -907.9, wy = -3534.2, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Adegwa", npc = 9501, trigger = 1646 },
	{ id = "inn_nijels_point", kind = "inn", faction = "A", mapID = 1443, x = 0.663, y = 0.069,
		subzone = "Nijel's Point", zone = "Desolace", minLevel = 30, areaID = 608,
		name = "Nijel's Point inn", cont = 1, wx = 245.6, wy = 1252.0, r = 40, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Lyshaerya", npc = 11103, trigger = 2266 },
	{ id = "inn_shadowprey", kind = "inn", faction = "H", mapID = 1443, x = 0.242, y = 0.683,
		subzone = "Shadowprey Village", zone = "Desolace", minLevel = 30, areaID = 2408,
		name = "Shadowprey Village inn", cont = 1, wx = -1596.2, wy = 3145.3, r = 22, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Sikewa", npc = 11106, trigger = 2267 },
	{ id = "inn_freewind", kind = "inn", faction = "H", mapID = 1441, x = 0.461, y = 0.515,
		subzone = "Freewind Post", zone = "Thousand Needles", minLevel = 25, areaID = 484,
		name = "Freewind Post inn", cont = 1, wx = -5477.9, wy = -2460.3, r = 20, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Abeqwa", npc = 11116, trigger = 2286 },
	{ id = "inn_everlook", kind = "inn", faction = "N", mapID = 1452, x = 0.613, y = 0.390,
		subzone = "Everlook", zone = "Winterspring", minLevel = 53, areaID = 2255,
		name = "Everlook inn", cont = 1, wx = 6688.0, wy = -4670.1, r = 20, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Vizzie", npc = 11118, trigger = 2287 },
	{ id = "inn_splintertree", kind = "inn", faction = "H", mapID = 1440, x = 0.740, y = 0.606,
		subzone = "Splintertree Post", zone = "Ashenvale", minLevel = 18, areaID = 431,
		name = "Splintertree Post inn", cont = 1, wx = 2343.6, wy = -2569.0, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Kaylisk", npc = 12196, trigger = 2610 },
	{ id = "inn_revantusk", kind = "inn", faction = "H", mapID = 1425, x = 0.781, y = 0.814,
		subzone = "Revantusk Village", zone = "The Hinterlands", minLevel = 40, areaID = 3317,
		name = "Revantusk Village inn", cont = 0, wx = -622.1, wy = -4582.1, r = 20, rest = "inn",
		duel = true, ffa = false, innkeeper = "Lard", npc = 14731, trigger = 3690 },
	{ id = "inn_gromgol", kind = "inn", faction = "H", mapID = 1434, x = 0.316, y = 0.297,
		subzone = "Grom'gol Base Camp", zone = "Stranglethorn Vale", minLevel = 30, areaID = 117,
		name = "Grom'gol inn", cont = 0, wx = -12432.8, wy = 205.2, r = 18, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Thulbek", npc = 5814, trigger = 3886 },
	{ id = "inn_cenarion_hold", kind = "inn", faction = "N", mapID = 1451, x = 0.518, y = 0.390,
		subzone = "Cenarion Hold", zone = "Silithus", minLevel = 55, areaID = 3425,
		name = "Cenarion Hold inn", cont = 1, wx = -6865.0, wy = 731.6, r = 20, rest = "inn",
		duel = true, ffa = false, innkeeper = "Calandrath", npc = 15174, trigger = 3985 },
	{ id = "inn_lights_hope", kind = "inn", faction = "N", mapID = 1423, x = 0.717, y = 0.486,
		subzone = "Light's Hope Chapel", zone = "Eastern Plaguelands", minLevel = 53,
		areaID = 2268, name = "Light's Hope Chapel inn", cont = 0, wx = 2298.2, wy = -5341.0,
		r = 19, rest = "inn", duel = true, ffa = false, innkeeper = "Jessica Chambers",
		npc = 16256, trigger = 4058,
		verify = "Forever changed Eastern Plaguelands' map bounds: Classic coordinates (81.6, 58.1) are wrong here." },
	{ id = "inn_stonetalon_peak", kind = "inn", faction = "A", mapID = 1442, x = 0.358, y = 0.061,
		subzone = "Stonetalon Peak", zone = "Stonetalon Mountains", minLevel = 15, areaID = 467,
		name = "Stonetalon Peak inn", cont = 1, wx = 2716.6, wy = 1496.8, r = 30, rest = "inn",
		duel = true, ffa = false, innkeeper = "Innkeeper Faralia", npc = 16458, trigger = 4090 },
	{ id = "inn_stormwind", kind = "inn", faction = "A", mapID = 1453, x = 0.604, y = 0.753,
		subzone = "Trade District", zone = "Stormwind City", minLevel = 1,
		name = "The Gilded Rose", cont = 0, wx = -8867.8, wy = 673.9, rest = "city", duel = false,
		ffa = false, innkeeper = "Innkeeper Allison", npc = 6740,
		verify = "Forever's Stormwind map has new bounds (the harbor): Classic/Wowhead coordinates (52.6, 65.6) are wrong here; the inn floor is named \"Trade District\" in Forever's new Stormwind WMO." },
	{ id = "inn_ironforge", kind = "inn", faction = "A", mapID = 1455, x = 0.182, y = 0.514,
		subzone = "Ironforge", zone = "Ironforge", minLevel = 1, areaID = 1537,
		name = "Stonefire Tavern", cont = 0, wx = -4840.4, wy = -857.5, rest = "city",
		duel = false, ffa = false, innkeeper = "Innkeeper Firebrew", npc = 5111,
		verify = "Forever's new Ironforge WMO (20884) has no \"Stonefire Tavern\" name (Classic Era's old WMO 208 had one); expect \"Ironforge\"." },
	{ id = "inn_darnassus", kind = "inn", faction = "A", mapID = 1457, x = 0.674, y = 0.156,
		subzone = "Craftsmen's Terrace", zone = "Darnassus", minLevel = 1, areaID = 1659,
		name = "Darnassus inn", cont = 1, wx = 10128.2, wy = 2225.0, rest = "city", duel = false,
		ffa = false, innkeeper = "Innkeeper Saelienne", npc = 6735 },
	{ id = "inn_orgrimmar", kind = "inn", faction = "H", mapID = 1454, x = 0.541, y = 0.684,
		subzone = "Valley of Strength", zone = "Orgrimmar", minLevel = 1, name = "Orgrimmar inn",
		cont = 1, wx = 1634.1, wy = -4439.4, rest = "city", duel = false, ffa = false,
		innkeeper = "Innkeeper Gryshka", npc = 6929 },
	{ id = "inn_thunder_bluff", kind = "inn", faction = "H", mapID = 1456, x = 0.458, y = 0.647,
		subzone = "", zone = "Thunder Bluff", minLevel = 1, areaID = 1638,
		name = "Thunder Bluff inn", cont = 1, wx = -1300.2, wy = 38.6, rest = "city", duel = false,
		ffa = false, innkeeper = "Innkeeper Pala", npc = 6746,
		verify = "The inn building (WMO 783) and the mesa (AreaTable 1638, the zone itself) carry no subzone name, so GetSubZoneText() should return \"\" here." },
	{ id = "inn_undercity", kind = "inn", faction = "H", mapID = 1458, x = 0.677, y = 0.379,
		subzone = "Trade Quarter", zone = "Undercity", minLevel = 1, name = "Undercity inn",
		cont = 0, wx = 1635.3, wy = 223.7, rest = "city", duel = false, ffa = false,
		innkeeper = "Innkeeper Norman", npc = 6741,
		verify = "Rest trigger 3547 sits above ground; the city flag covers the underground inn." },
	{ id = "tavern_slaughtered_lamb", kind = "inn", faction = "A", mapID = 1453, x = 0.420,
		y = 0.827, subzone = "The Slaughtered Lamb", zone = "Stormwind City", minLevel = 1,
		name = "The Slaughtered Lamb", cont = 0, wx = -8953.8, wy = 993.8, rest = "city",
		duel = false, ffa = false, barkeep = "Jarel Moor", npc = 1305,
		verify = "A tavern without an innkeeper (barkeep Jarel Moor); resting comes from the city." },
}

Places.byId = {}
for _, place in ipairs(Places.list) do
	Places.byId[place.id] = place
end

---------------------------------------------------------------------------
-- The pure functions (the design). A point is { cont = 0|1, wx = yards, wy = yards }, the
-- fields a place has, so a place row is a point too; a table with none of those fields may give
-- the three as a list, { cont, wx, wy }, as the design writes it. A bad argument gets nil (or an empty
-- list), never an error.
--
--   Places.Fair(a, b, o) -> { { id, place, a = yards, b = yards }, ... }
--       The places for two players at points a and b (on one continent), fairest first: by the
--       longer of the two walks, shortest first (the fair middle), then by the total walk, then
--       by id. o = { game = "d" (duel) | "b" (Bones), staked = any true value (true, the
--       stake, its letter) | nil | false, faction = "A"|"H" (or "Alliance"|"Horde", as
--       UnitFactionGroup says), level = the lower of the two levels }.
--       Kept: places on a's continent, of that faction or neutral ("N"; no faction: neutral
--       only), minLevel at or below level; for a duel, arenas and spots with duel = true, and
--       for a staked duel only those without ffa (a third player could end it); for Bones,
--       every inn (for gold and for practice). a and b in each entry are the two walks.
--   Places.Near(cont, wx, wy, filter) -> { { id, place, d = yards }, ... }
--       The places on that continent, nearest first (then by id); filter(place, d), when given,
--       keeps those it returns a true value for (anything but nil and false).
--   Places.Dist(a, b) -> yards, or nil across continents.
--   Places.Capital(mapID) -> true on the six capital cities' maps (the maps of the "city" inns).
--   Places.Cell(w[, step]) -> the step (Places.CELL, 400 yd, by default; Places.POINT, 25 yd, for
--       a point) a world coordinate falls in: floor((w + 20000) / step), from 0; nil outside
--       -20000 <= w < 20000. The wire writes it in base 36 (the design).
--   Places.Centre(c[, step]) -> the world coordinate at the middle of step c: c * step - 20000 +
--       step / 2; nil for a step that does not exist.
--   Places.InnAt(cont, wx, wy) -> the inn whose rest area holds the point (and the yards to it):
--       within r + 5 yd of a rest-trigger inn, or within 20 yd of a capital inn's innkeeper (the
--       Slaughtered Lamb's barkeep). The nearest when two qualify. Resting is the game's to say
--       (IsResting); this only says which inn.
--   Places.Bearing(from, to) -> "north", "north-east", "east", "south-east", "south",
--       "south-west", "west" or "north-west" (Places.BEARINGS): the eighth of the compass the
--       straight line from one point to the other points into, each word covering 45 degrees
--       around its direction (a line exactly between two words gets the one nearer north or
--       south); nil for the same point or across continents.
--   Places.HBDWorld(cont, wx, wy) -> instanceID, x, y as HereBeDragons' world functions take them
--       (AddMinimapIconWorld and the rest): UnitPosition's two values swapped, x the second (west)
--       and y the first (north) (HereBeDragons-2.0.lua, GetUnitWorldPosition).
---------------------------------------------------------------------------

local floor, sqrt, abs, max, huge = math.floor, math.sqrt, math.abs, math.max, math.huge
local sort = table.sort

Places.OFFSET = 20000  -- added to a world coordinate before it is cut into steps
Places.CELL = 400      -- a cell's side: what a search tells of a position (the design)
Places.POINT = 25      -- a point's step: "Where I am"
Places.INN_MARGIN = 5  -- yards past a rest trigger's r that still count as at the inn
Places.CITY_INN = 20   -- yards from a capital inn's innkeeper that count as at the inn
Places.BEARINGS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

local OFFSET, CELL, INN_MARGIN, CITY_INN = Places.OFFSET, Places.CELL, Places.INN_MARGIN, Places.CITY_INN
local TAN_22_5 = sqrt(2) - 1 -- tan(22.5 degrees): the edge between a word and the next
local FACTIONS = { A = "A", H = "H", Alliance = "A", Horde = "H" }

local function Finite(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge end

-- A point's three numbers: its named fields, or, with none of them, its first three values
-- ({ cont, wx, wy }, as the design writes a point); nil unless all three are finite numbers.
local function Coords(p)
	if type(p) ~= "table" then return nil end
	local cont, wx, wy = p.cont, p.wx, p.wy
	if cont == nil and wx == nil and wy == nil then cont, wx, wy = p[1], p[2], p[3] end
	if Finite(cont) and Finite(wx) and Finite(wy) then return cont, wx, wy end
	return nil
end

local function Dist(a, b)
	local ac, ax, ay = Coords(a)
	local bc, bx, by = Coords(b)
	if not ac or not bc or ac ~= bc then return nil end
	local dx, dy = ax - bx, ay - by
	return sqrt(dx * dx + dy * dy)
end
Places.Dist = Dist

-- Whether a place suits the game: a duel's ground allows /duel (and, staked, is no free-for-all);
-- Bones is played at an inn.
local function Suits(place, game, staked)
	if game == "d" then
		return (place.kind == "arena" or place.kind == "spot") and place.duel == true and not (staked and place.ffa)
	end
	return game == "b" and place.kind == "inn"
end

function Places.Fair(a, b, o)
	local out = {}
	local ac, bc = Coords(a), Coords(b)
	if not ac or not bc or ac ~= bc or type(o) ~= "table" then return out end
	local game, level = o.game, o.level
	if (game ~= "d" and game ~= "b") or not Finite(level) then return out end
	local faction = FACTIONS[o.faction]
	for _, place in ipairs(Places.list) do
		if place.cont == ac and (place.faction == "N" or place.faction == faction) and place.minLevel <= level
			and Suits(place, game, o.staked) then
			out[#out + 1] = { id = place.id, place = place, a = Dist(a, place), b = Dist(b, place) }
		end
	end
	sort(out, function(x, y)
		local fx, fy = max(x.a, x.b), max(y.a, y.b)
		if fx ~= fy then return fx < fy end
		local tx, ty = x.a + x.b, y.a + y.b
		if tx ~= ty then return tx < ty end
		return x.id < y.id
	end)
	return out
end

function Places.Near(cont, wx, wy, filter)
	local out = {}
	local here = { cont = cont, wx = wx, wy = wy }
	if not Coords(here) or (filter ~= nil and type(filter) ~= "function") then return out end
	for _, place in ipairs(Places.list) do
		if place.cont == cont then
			local d = Dist(here, place)
			if not filter or filter(place, d) then out[#out + 1] = { id = place.id, place = place, d = d } end
		end
	end
	sort(out, function(x, y)
		if x.d ~= y.d then return x.d < y.d end
		return x.id < y.id
	end)
	return out
end

local CAPITALS = {}
for _, place in ipairs(Places.list) do
	if place.rest == "city" then CAPITALS[place.mapID] = true end
end
function Places.Capital(mapID) return CAPITALS[mapID] == true end

local function Step(step)
	if step == nil then return CELL end
	if type(step) == "number" and step >= 1 and step == floor(step) and step <= 2 * OFFSET then return step end
	return nil
end

function Places.Cell(w, step)
	step = Step(step)
	if not step or not Finite(w) or w < -OFFSET or w >= OFFSET then return nil end
	return floor((w + OFFSET) / step)
end

function Places.Centre(c, step)
	step = Step(step)
	if not step or not Finite(c) or c ~= floor(c) or c < 0 or c * step >= 2 * OFFSET then return nil end
	return c * step - OFFSET + step / 2
end

function Places.InnAt(cont, wx, wy)
	local here = { cont = cont, wx = wx, wy = wy }
	if not Coords(here) then return nil end
	local best, bestD
	for _, place in ipairs(Places.list) do
		if place.kind == "inn" and place.cont == cont then
			local reach = (place.rest == "inn" and Finite(place.r) and place.r + INN_MARGIN) or (place.rest == "city" and CITY_INN) or nil
			local d = reach and Dist(here, place)
			if d and d <= reach and (not best or d < bestD or (d == bestD and place.id < best.id)) then best, bestD = place, d end
		end
	end
	return best, bestD
end

function Places.Bearing(from, to)
	local fc, fx, fy = Coords(from)
	local tc, tx, ty = Coords(to)
	if not fc or not tc or fc ~= tc then return nil end
	local north, east = tx - fx, fy - ty -- (the second value grows to the west)
	if north == 0 and east == 0 then return nil end
	local n, e = abs(north), abs(east)
	if e <= TAN_22_5 * n then return north > 0 and "north" or "south" end
	if n < TAN_22_5 * e then return east > 0 and "east" or "west" end
	if north > 0 then return east > 0 and "north-east" or "north-west" end
	return east > 0 and "south-east" or "south-west"
end

function Places.HBDWorld(cont, wx, wy)
	if not Coords({ cont = cont, wx = wx, wy = wy }) then return nil end
	return cont, wy, wx
end
