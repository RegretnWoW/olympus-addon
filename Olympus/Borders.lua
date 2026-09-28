local ADDON, ns = ...
local L = ns.L

-- The elite borders (1.0.1, asked for on the community Discord): the game's own elite and rare
-- art around the portrait of an Olympus player on your target and focus frames, and around your
-- own portrait for your own rank, like Elite Player Frame (Enhanced) but for other players too.
-- `/oly borders on|off`, on by default.
--
-- How, on Forever's unit frames (Blizzard_UnitFrame, the "Camelot" family: TargetFrameTemplate
-- and PlayerFrame): the game draws an elite or rare creature's border with BossPortraitFrameTexture,
-- a texture of the frame's TargetFrameContainer, set in TargetFrameMixin:CheckClassification
-- (GetBossPortraitFrameData gives the atlas and where it goes). Olympus leaves that texture alone:
-- it puts its own hidden textures on the same container, one per border, just above the game's
-- (same layer, one sublevel up), with the same atlases and offsets, sized and anchored once, out of
-- combat. From then on it only shows and hides them: Show and Hide are not protected for a texture
-- (the client's API documentation marks them protected for a frame only), so a target change in
-- combat is fine. The game's frames get no call from Olympus but those CreateTexture, and nothing
-- written in them but hooksecurefunc's hook, which keeps their CheckClassification secure.
-- After the game's CheckClassification on the target and focus frames (hooksecurefunc on the frames
-- themselves: the mixin's functions were copied into them when they were made) Olympus shows the
-- border of the unit again, so it follows every update the game makes.
--
-- The gamepad UI (Forever's controller mode): off there. Olympus leaves the game's frames alone with
-- the gamepad UI (0.9.8), and nothing offline can show that a hook in the target frame's update is
-- harmless to it (0.9.9: the world map looked harmless too). Logged in with the gamepad UI, Olympus
-- neither hooks nor makes textures; switched to it later, its textures hide at once and the hook
-- returns without a call; back to mouse and keyboard, the borders come back.
--
-- Cheap: a unit's border is worked out only when the target or focus changes, when its name or
-- guild reaches the client (UNIT_NAME_UPDATE, PLAYER_GUILD_UPDATE), or when the census report of
-- its guild (or the High Council's list) changes, and only from lookups: its guild's report by
-- name, never a walk over every guild.

local Borders = {}
ns.Borders = Borders

-- Max's second option: the High Council gold, like the King. Off: the High Council is silver.
ns.BORDERS_COUNCIL_GOLD = false

-- Who gets which border, checked from the top: the first that holds is the border. The art is
-- the game's own, as Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua (GetBossPortraitFrameData)
-- gives it for a boss, a rare and an elite creature, with the offsets the game anchors each at
-- (x, y: from the top right of the target frame's container; mirrored on your own frame).
-- shade: drawn without colour, this dark (1 = as the game draws it).
-- Who:
--   king     the King of our faction: his character (ns.IsKingCharacter) in his guild
--            (ns.IsKingGuild); where no character is pinned, that guild's guild master
--   council  the High Council (the signed list, ns.IsHighCouncillor): true, or the name of the
--            ns flag that must be on for it (except on the King's screen while he streams)
--   leader   the guild master of an Olympus guild, as its census report names him (our own
--            guild's: our roster)
--   officer  its officers: the report's officers, or our own guild's officer ranks (Roster.lua)
--   ranks    a member of an Olympus guild whose rank name holds one of these words (any case, a
--            whole word): rank names are what each guild master wrote, as the game shows them
Borders.TIERS = {
	{ name = "gold", atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", x = 11, y = -4,
		king = true, council = "BORDERS_COUNCIL_GOLD" },
	{ name = "silver", atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", x = 8, y = -7,
		council = true, leader = true, officer = true },
	{ name = "grey", atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", x = 0, y = 1, shade = 0.55,
		ranks = { "veteran", "veterano", "veterana", "raider" } },
}

-- Where they go: the frame (a global of the game's), its container, and the hook that follows the
-- game's updates. Your own portrait sits on the left, so there the art is mirrored.
local RIGS = {
	{ unit = "target", frame = "TargetFrame", container = "TargetFrameContainer", hook = "CheckClassification" },
	{ unit = "focus", frame = "FocusFrame", container = "TargetFrameContainer", hook = "CheckClassification" },
	{ unit = "player", frame = "PlayerFrame", container = "PlayerFrameContainer", mirror = true },
}
local TRACKED = { target = true, focus = true, player = true }

local rigs = {}  -- [unit] = { tex = { [tier name] = texture }, shown = tier name or nil }
local known = {} -- [unit] = { guid, tier, guild, report, rt, council }: the last worked out
local installed, waiting = false, false
Borders.stats = { computed = 0 } -- (tests, /oly status)

-- Values the client hides from addons (secret values) count as none.
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

local function RankHolds(ranks, rankName)
	if type(rankName) ~= "string" or rankName == "" then return false end
	for word in ns.Fold(rankName):gmatch("[^%s%p%d]+") do
		for _, want in ipairs(ranks) do
			if word == ns.Fold(want) then return true end
		end
	end
	return false
end

-- What decides a unit's border, or nil for anyone no border is for: not a player, of the other
-- faction (the census is per faction, and so is the King), or a value the client hides.
local function Facts(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local faction = UnitFactionGroup(unit)
	local name, realm = UnitFullName(unit)
	local guild, rankName, rankIndex = GetGuildInfo(unit)
	if Secret(faction, name, realm, guild, rankName, rankIndex) then return nil end
	if faction ~= (ns.faction or "Alliance") then return nil end
	local who = ns.UnitFullName(unit)
	if type(who) ~= "string" or who == "" then return nil end
	local f = { guild = type(guild) == "string" and guild or nil }
	f.council = ns.IsHighCouncillor(who) and not ns.CouncilMasked()
	if not f.guild or not ns.IsFederation(f.guild) then return f end
	f.olympus, f.rankName = true, rankName
	f.king = ns.IsKingGuild(f.guild) and (ns.IsKingCharacter(who) or (ns.KingCharacter() == nil and rankIndex == 0))
	local guilds = ns.rdb and ns.rdb.guilds
	local report = type(guilds) == "table" and guilds[f.guild] or nil
	f.report = report
	local mine = GetGuildInfo("player")
	if mine and f.guild == mine then
		-- Our own guild: the rank the server gives (our roster's if it gives none).
		local rank = type(rankIndex) == "number" and rankIndex or (ns.Roster and ns.Roster.RankOf(who))
		f.leader = rank == 0
		f.officer = type(rank) == "number" and rank > 0 and rank <= ns.CAPTAIN_RANK
	elseif type(report) == "table" then
		-- Another guild: its census report (Data.lua), whose names belong to its reporter's realm.
		local home = report.realm or ns.realm
		f.leader = type(report.leader) == "string" and ns.FullName(report.leader, home) == who
		if not f.leader and type(report.officers) == "table" then
			for _, o in ipairs(report.officers) do
				if type(o) == "table" and type(o.name) == "string" and ns.FullName(o.name, home) == who then f.officer = true break end
			end
		end
	end
	return f
end

local function Match(f)
	if not f then return nil end
	for _, t in ipairs(Borders.TIERS) do
		local council = t.council == true or (type(t.council) == "string" and ns[t.council] == true)
		if (t.king and f.king) or (council and f.council) or (t.leader and f.leader) or (t.officer and f.officer)
			or (t.ranks and f.olympus and RankHolds(t.ranks, f.rankName)) then
			return t
		end
	end
	return nil
end

-- The border a unit gets now ("gold", "silver", "grey" or nil), worked out afresh.
function Borders.TierOf(unit)
	local t = Match(Facts(unit))
	return t and t.name or nil
end

local function Compute(unit, guid)
	Borders.stats.computed = Borders.stats.computed + 1
	local f = Facts(unit)
	local t = Match(f)
	local report = f and f.report
	local k = { guid = guid, tier = t and t.name or nil, guild = f and f.guild, report = report,
		rt = type(report) == "table" and report.t or nil, council = ns.rdb and ns.rdb.council }
	known[unit] = k
	return k
end

function Borders.Enabled() return not (ns.db and ns.db.borders == false) end

-- On, with mouse and keyboard, for a member of an Olympus guild (outside one the addon offers
-- nothing but the Join Olympus screen).
local function Active()
	return Borders.Enabled() and not ns.GamepadUI() and ns.IsMember() == true
end

local function AtlasExists(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo
	if type(info) ~= "function" then return true end
	local ok, v = pcall(info, atlas)
	return ok and v ~= nil
end

-- Once, with mouse and keyboard and out of combat (a texture of the game's frames may count as
-- theirs, whose points and size are not ours to set in combat): the textures, then the hooks.
-- A client without Forever's unit frames (Classic Era, Anniversary) gets none.
function Borders.Install()
	if installed then return true end
	if ns.GamepadUI() then return false end
	if InCombatLockdown and InCombatLockdown() then
		waiting = true
		return false
	end
	waiting, installed = false, true
	for _, spec in ipairs(RIGS) do
		local frame = _G[spec.frame]
		local container = type(frame) == "table" and frame[spec.container] or nil
		if type(container) == "table" and type(container.CreateTexture) == "function" then
			local rig = { tex = {} }
			for _, t in ipairs(Borders.TIERS) do
				if AtlasExists(t.atlas) then
					local tex = container:CreateTexture(nil, "ARTWORK", nil, 3)
					tex:SetAtlas(t.atlas, true, nil, true)
					if spec.mirror then
						-- The game's way to turn an atlas round (Blizzard_OrderHallTalents.lua). The target's
						-- portrait sits 26 px from its frame's right edge, yours 24 px from its left.
						tex:SetTexCoord(1, 0, 0, 1)
						tex:SetPoint("TOPLEFT", container, "TOPLEFT", -(t.x + 2), t.y)
					else
						tex:SetPoint("TOPRIGHT", container, "TOPRIGHT", t.x, t.y)
					end
					if t.shade then
						tex:SetDesaturated(true)
						tex:SetVertexColor(t.shade, t.shade, t.shade)
					end
					tex:Hide()
					rig.tex[t.name] = tex
				end
			end
			rigs[spec.unit] = rig
			if spec.hook and type(frame[spec.hook]) == "function" and type(hooksecurefunc) == "function" then
				local unit, where = spec.unit, "borders " .. spec.unit
				hooksecurefunc(frame, spec.hook, function() ns.SafeCall(where, Borders.Refresh, unit) end)
			end
		end
	end
	ns.Log("borders: set up on %s", Borders.Frames())
	return true
end

local function Show(rig, name)
	if rig.shown == name then return end
	if rig.shown and rig.tex[rig.shown] then rig.tex[rig.shown]:Hide() end
	rig.shown = nil
	if name and rig.tex[name] then
		rig.tex[name]:Show()
		rig.shown = name
	end
end

local function HideAll()
	for _, rig in pairs(rigs) do Show(rig, nil) end
end

-- The unit's border again: the one worked out for it while it is the same unit (fresh: work it
-- out again), none while the borders are off.
function Borders.Refresh(unit, fresh)
	if not Active() then
		if rigs[unit] then Show(rigs[unit], nil) end
		return
	end
	if not installed and not Borders.Install() then return end
	local rig = rigs[unit]
	if not rig then return end
	local guid = UnitGUID and UnitGUID(unit)
	if Secret(guid) then guid = nil end
	local k = known[unit]
	if fresh or not k or guid == nil or k.guid ~= guid then k = Compute(unit, guid) end
	Show(rig, k.tier)
end

function Borders.RefreshAll(fresh)
	for _, spec in ipairs(RIGS) do Borders.Refresh(spec.unit, fresh) end
end

-- The census or the High Council's list changed: only a unit whose guild's report (or the list)
-- is not the one its border was worked out from is worked out again.
function Borders.CensusChanged()
	if not installed then return end
	local rdb = ns.rdb
	for unit, k in pairs(known) do
		local report = k.guild and rdb and type(rdb.guilds) == "table" and rdb.guilds[k.guild] or nil
		if report ~= k.report or (type(report) == "table" and report.t or nil) ~= k.rt or (rdb and rdb.council) ~= k.council then
			Borders.Refresh(unit, true)
		end
	end
end

function Borders.Report()
	if not Borders.Enabled() then return ns.Print(L.BORDERS_OFF) end
	ns.Print(ns.BORDERS_COUNCIL_GOLD == true and L.BORDERS_ON_COUNCIL_GOLD or L.BORDERS_ON)
	if ns.GamepadUI() then ns.Print(L.BORDERS_GAMEPAD) end
end

function Borders.SetEnabled(on)
	ns.db.borders = on and true or false
	Borders.RefreshAll(true)
	Borders.Report()
end

-- The frames that got their textures ("target, focus, player"), for the log and /oly status.
function Borders.Frames()
	local out = {}
	for _, spec in ipairs(RIGS) do
		if rigs[spec.unit] then out[#out + 1] = spec.unit end
	end
	return #out > 0 and table.concat(out, ", ") or "none (not Forever's unit frames)"
end

function Borders.StatusLine()
	local state = Borders.Enabled() and "on" or "off (/oly borders on)"
	if Borders.Enabled() and ns.GamepadUI() then state = "on, hidden with the gamepad UI" end
	local where
	if installed then
		local shown = {}
		for _, spec in ipairs(RIGS) do
			local rig = rigs[spec.unit]
			if rig then shown[#shown + 1] = spec.unit .. " " .. (rig.shown or "-") end
		end
		where = #shown > 0 and table.concat(shown, ", ") or Borders.Frames()
	else
		where = waiting and "set up after combat" or "not set up yet"
	end
	return ("%s  |  %s  |  worked out %d times  |  council gold: %s"):format(state, where, Borders.stats.computed,
		tostring(ns.BORDERS_COUNCIL_GOLD == true))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("LOGIN", function() Borders.RefreshAll(true) end)
ns.On("DATA_CHANGED", function() Borders.CensusChanged() end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Borders.Refresh("target") end)
ns.RegisterEvent("UNIT_NAME_UPDATE", function(unit) if TRACKED[unit] then Borders.Refresh(unit, true) end end)
-- A unit's guild reaching the client (or ours changing: every border again).
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit == nil or unit == "player" then Borders.RefreshAll(true)
	elseif TRACKED[unit] then Borders.Refresh(unit, true) end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if waiting then Borders.RefreshAll(true) end end)
-- Not on every client: registered where the game has them.
pcall(ns.RegisterEvent, "PLAYER_FOCUS_CHANGED", function() Borders.Refresh("focus") end)
-- A switch between mouse and keyboard and the gamepad UI (Blizzard_SharedXML/InputUtil.lua's):
-- to the gamepad UI, every border hides at once; either way they are looked at again just after.
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function(newMode)
	local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
	if gamepad ~= nil and newMode == gamepad then HideAll() end
	ns.After(0.2, "borders style", function() Borders.RefreshAll(true) end)
end)
