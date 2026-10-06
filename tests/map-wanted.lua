-- The map option is artwork-only; sightings consent and minimap pins stay independent.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]map%-wanted%.lua$") or "./"
local function Frame(name, frames)
	local f = { scripts = {}, shown = false, labels = {}, ScrollContainer = false, OnMapChanged = false }
	if name then frames[name] = f end
	function f:SetScript(event, fn) self.scripts[event] = fn end
	function f:GetScript(event) return self.scripts[event] end
	function f:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:SetShown(on) if on then self:Show() else self:Hide() end end
	function f:SetChecked(on) self.checked = on end
	function f:GetChecked() return self.checked end
	function f:GetFrameLevel() return 1 end
	function f:CreateTexture() return Frame(nil, frames) end
	function f:CreateFontString()
		local label = Frame(nil, frames)
		function label:SetText(text) self.text = text end
		self.labels[#self.labels + 1] = label
		return label
	end
	return setmetatable(f, { __index = function() return function() end end })
end

local function WithMapWanted(fn)
	local names = { "CreateFrame", "WorldMapFrame", "UIParent", "IsInInstance", "UnitGUID", "UnitIsPlayer",
		"UnitFactionGroup", "UnitCanAttack", "UnitIsPVP", "GetGuildInfo", "C_Map", "issecretvalue" }
	local saved = {}
	for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
	local ok, err = pcall(function()
		local frames, hooks, world, mini = {}, {}, {}, {}
		local member, inside, worldAllowed = true, false, true
		local guid = "Player-1-0A000001"
		local lib = {}
		function lib:AddWorldMapIconMap(_, f) world[f] = true end
		function lib:RemoveWorldMapIcon(_, f) world[f] = nil end
		function lib:AddMinimapIconMap(_, f) mini[f] = true end
		function lib:RemoveMinimapIcon(_, f) mini[f] = nil end
		CreateFrame = function(_, name) return Frame(name, frames) end
		UIParent, WorldMapFrame = Frame(nil, frames), Frame(nil, frames)
		IsInInstance = function() return inside end
		UnitGUID = function(unit) return unit == "target" and guid or "Player-1-0A000002" end
		UnitIsPlayer = function() return true end
		UnitFactionGroup = function() return "Horde" end
		UnitCanAttack, UnitIsPVP = function() return true end, function() return true end
		GetGuildInfo = function(unit) return unit == "player" and "Olympus" or nil end
		issecretvalue = function() return false end
		C_Map = { GetMapInfo = function() return { mapType = 3 } end,
			GetBestMapForUnit = function() return 1429 end,
			GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.5 end } end }
		local c = setmetatable({ db = {}, rdb = {}, Wanted = false, me = "Observer-Realm", faction = "Alliance",
			UI = {}, Consent = {}, Comm = {}, Data = { ServerTime = function() return 1800000000 end },
			Moderation = { SelfOff = function() return false end }, Layers = {},
			Gate = { Hooks = function(key, value) hooks[key] = value end, Allowed = function() return true end },
			On = function() end, RegisterEvent = function() end, IsMember = function() return member end,
			Pins = function() return lib end, MakeRoundButton = function(name) return Frame(name, frames) end,
			UnitFullName = function(unit) return unit == "target" and "Enemy-Realm" or "Observer-Realm" end,
			WorldMapIcons = function()
				if not worldAllowed then for f in pairs(world) do world[f] = nil end end
				return worldAllowed
			end }, { __index = ns })
		assert(loadfile(ROOT .. "Olympus/Map.lua"))("Olympus", c)
		hooks["map-overlay"].install()
		local menu = assert(frames.OlympusMapMenu)
		fn(c, menu, world, mini, guid, function(m, i, w) member, inside, worldAllowed = m, i, w end)
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

test("Wanted map option: labelled, enabled by default and safe without Wanted loaded", function()
	WithMapWanted(function(c, menu)
		local cb
		for _, check in ipairs(menu.checks) do if check.opt.key == "showWanted" then cb = check end end
		assert(cb, "Wanted checkbox exists")
		eq(menu.labels[#menu.labels].text, "Wanted")
		menu:Show(); eq(cb:GetChecked(), true)
		cb:SetChecked(false); cb:GetScript("OnClick")(cb); eq(c.db.showWanted, false)
		menu:Show(); eq(cb:GetChecked(), false)
		cb:SetChecked(true); cb:GetScript("OnClick")(cb); eq(c.db.showWanted, true)
		eq(c.db.wantedSightings, nil, "map choice never answers the consent question")
	end)
end)

test("Wanted map option: hides and restores actual sightings without changing minimap or consent", function()
	WithMapWanted(function(c, menu, world, mini, guid, mode)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		assert(c.Wanted.ObserveUnit("target"))
		local f = assert(c.Wanted.PinFrames()[guid])
		eq(world[f.world], true); eq(mini[f.mini], true)
		local cb
		for _, check in ipairs(menu.checks) do if check.opt.key == "showWanted" then cb = check end end
		assert(cb, "Wanted checkbox exists")
		cb:SetChecked(false); cb:GetScript("OnClick")(cb)
		eq(world[f.world], nil); eq(mini[f.mini], true); eq(#c.Wanted.Sightings(), 1)
		eq(c.db.wantedSightings, nil); eq(c.Wanted.SightingsOn(), true)
		c.Wanted.RefreshPins(); eq(world[f.world], nil)
		cb:SetChecked(true); cb:GetScript("OnClick")(cb)
		eq(world[f.world], true); eq(mini[f.mini], true)
		mode(true, false, false); c.Wanted.RefreshPins()
		eq(world[f.world], nil); eq(mini[f.mini], true, "gamepad gate stays independent")
		mode(true, false, true); c.Wanted.RefreshPins(); eq(world[f.world], true)
		mode(true, true, true); c.Wanted.RefreshPins()
		eq(next(world), nil); eq(next(mini), nil, "instances hide both")
		mode(false, false, true); c.Wanted.RefreshPins(); eq(next(world), nil); eq(next(mini), nil)
		mode(true, false, true); c.Wanted.RefreshPins(); eq(world[f.world], true); eq(mini[f.mini], true)
		c.Wanted.SetSightings(false, true)
		eq(c.db.wantedSightings, false); eq(#c.Wanted.Sightings(), 0)
		eq(next(world), nil); eq(next(mini), nil, "consent refusal still removes both")
	end)
end)
