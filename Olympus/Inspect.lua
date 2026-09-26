local ADDON, ns = ...
local L = ns.L

-- Tabard Inspection: inspects nearby Olympus members and records whether they wear a
-- tabard. "Patrol" mode scans target, mouseover, party/raid and friendly nameplates on
-- its own; officers can also mark any player or whole guild by hand. Results are kept in
-- OlympusDB.inspect and can be copied to Discord.

local Inspect = {}
ns.Inspect = Inspect

local TABARD_SLOT = INVSLOT_TABARD or 19
Inspect.GUILD_TABARDS = { [5976] = true } -- "Guild Tabard"
local RECHECK = 10 * 60   -- do not re-inspect the same player on patrol for 10 minutes
local INTERVAL = 1.5      -- one inspect request at a time, spaced out
local TIMEOUT = 4

local STATUS_ORDER = { NONE = 1, OTHER = 2, UNKNOWN = 3, UNCHECKED = 4, GUILD = 5 }
Inspect.STATUS_ORDER = STATUS_ORDER

local patrol = false
local queue, queued = {}, {}
local pending -- { guid, unit, at }
Inspect.stats = { requests = 0, ready = 0, timeouts = 0 }

-- Kept per realm (ns.rdb): the players of one realm say nothing about another one.
local function Store()
	local db = ns.rdb
	db.inspect = db.inspect or {}
	db.inspect.players = db.inspect.players or {}
	db.inspect.guildMarks = db.inspect.guildMarks or {}
	return db.inspect
end

local Source = Store

-- Every player a patrol ever checked stays in the saved variables, and the Tabards tab draws a
-- line for each: after a few weeks of patrols in a crowded capital that is thousands. Kept:
-- the last MAX_AGE, and at most MAX_PLAYERS of them, the ones that matter first (marked by
-- hand, then caught without the colors), then the newest. A mark by hand stays past MAX_AGE.
Inspect.MAX_AGE = 14 * 86400
Inspect.MAX_PLAYERS = 2000
local function Keep(p)
	if p.marked then return 1 end
	if p.status == "NONE" or p.status == "OTHER" then return 2 end
	return 3
end
function Inspect.Prune()
	local players, now, n = Store().players, ns.Now(), 0
	for name, p in pairs(players) do
		if type(p) ~= "table" or (not p.marked and now - (tonumber(p.t) or 0) > Inspect.MAX_AGE) then
			players[name] = nil
		else
			n = n + 1
		end
	end
	if n <= Inspect.MAX_PLAYERS then return end
	local list = {}
	for name, p in pairs(players) do list[#list + 1] = { name = name, keep = Keep(p), t = tonumber(p.t) or 0 } end
	table.sort(list, function(a, b)
		if a.keep ~= b.keep then return a.keep < b.keep end
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	for i = Inspect.MAX_PLAYERS + 1, #list do players[list[i].name] = nil end
end

-- itemID nil + some other gear visible = really no tabard. Nothing visible at all usually
-- means the inspect data did not load, so we call it UNKNOWN instead of accusing anyone.
function Inspect.Classify(tabardID, anyGearVisible)
	if tabardID then return Inspect.GUILD_TABARDS[tabardID] and "GUILD" or "OTHER" end
	return anyGearVisible and "NONE" or "UNKNOWN"
end

function Inspect.IsPatrolling() return patrol end

-- Everyone inspected on this realm group (the Throne's Royal Inspection reads it).
function Inspect.Players() return Store().players end

-- A player another addon reported during a Royal Inspection (King.PublishShame): kept like
-- our own inspections, so the usual Wall of Shame can publish them.
-- One key per player in the store: "Name" for our realm, "Name-Realm" for another, whatever
-- the name came from (a unit, a report, what 0.8.1 saved). On Forever, "First Surname".
local function Key(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.DisplayName(ns.FullName(ns.Normal(name)))
end
Inspect.Key = Key

function Inspect.AddReported(name, guild, status)
	name = Key(name)
	if type(name) ~= "string" or name == "" then return end
	local p = Store().players[name] or {}
	p.name, p.guild, p.status, p.t, p.reported = name, guild, status, ns.Now(), true
	Store().players[name] = p
	ns.Fire("INSPECT_CHANGED")
end

-- The Olympus rule: the tabard is required from this level on. Younger players are never
-- flagged (nor inspected on patrol).
Inspect.MIN_LEVEL = 15
local function TooYoung(level) return type(level) == "number" and level > 0 and level < Inspect.MIN_LEVEL end

function Inspect.Record(name, guild, classFile, level, tabardID, anyGear)
	name = Key(name)
	if not name then return nil end
	local s = Store()
	local p = s.players[name] or {}
	local previous = p.status
	p.name, p.guild, p.class, p.level = name, guild, classFile, level
	p.item = tabardID
	p.status = Inspect.Classify(tabardID, anyGear)
	if TooYoung(level) and (p.status == "NONE" or p.status == "OTHER") then p.status = "YOUNG" end
	p.t = ns.Now()
	s.players[name] = p
	ns.Log("inspect %s <%s>: %s (%s)", name, tostring(guild), p.status, tostring(tabardID))
	if (p.status == "NONE" or p.status == "OTHER") and previous ~= p.status then
		local label = p.status == "NONE" and L.TABARD_NONE or L.TABARD_OTHER
		ns.Print(("|cffff4040%s|r <%s>: %s"):format(ns.ShortName(name), guild or "?", label))
		ns.PlayAlert("soft")
	end
	if not previous then Inspect.Prune() end -- (only a new player makes the store grow)
	ns.Fire("INSPECT_CHANGED")
	return p
end

local function Enqueue(unit, force)
	if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
	local guid = UnitGUID(unit)
	if not guid or queued[guid] or (pending and pending.guid == guid) then return end
	local guild = GetGuildInfo(unit)
	if not force and not ns.IsFederation(guild) then return end
	-- Olympus guilds of the other faction are not ours to inspect (the Horde has its own too).
	if not force and UnitFactionGroup and UnitFactionGroup(unit) ~= UnitFactionGroup("player") then return end
	if not force and TooYoung(UnitLevel(unit)) then return end
	if not force then
		local p = Store().players[Key(ns.UnitFullName(unit))]
		if p and p.status ~= "UNKNOWN" and p.status ~= "UNCHECKED" and ns.Now() - (p.t or 0) < RECHECK then return end
	end
	queued[guid] = true
	table.insert(queue, force and 1 or #queue + 1, { unit = unit, guid = guid })
end

local function ScanNearby()
	Enqueue("target")
	Enqueue("mouseover")
	if IsInRaid() then
		for i = 1, 40 do Enqueue("raid" .. i) end
	else
		for i = 1, 4 do Enqueue("party" .. i) end
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then Enqueue(unit) end
	end
end

local function Pump()
	if pending then
		if GetTime() - pending.at < TIMEOUT then return end
		Inspect.stats.timeouts = Inspect.stats.timeouts + 1
		pending = nil
	end
	if InCombatLockdown() then return end
	if InspectFrame and InspectFrame:IsShown() then return end -- the player is inspecting by hand
	if patrol then ScanNearby() end
	while #queue > 0 do
		local item = table.remove(queue, 1)
		queued[item.guid] = nil
		local unit = item.unit
		if UnitGUID(unit) == item.guid and CanInspect(unit) and CheckInteractDistance(unit, 1) then
			pending = { guid = item.guid, unit = unit, at = GetTime() }
			Inspect.stats.requests = Inspect.stats.requests + 1
			NotifyInspect(unit)
			return
		end
	end
end

local function FindUnit(guid, hint)
	if hint and UnitGUID(hint) == guid then return hint end
	for _, u in ipairs({ "target", "mouseover", "focus" }) do
		if UnitGUID(u) == guid then return u end
	end
	for i = 1, 40 do
		if UnitGUID("nameplate" .. i) == guid then return "nameplate" .. i end
	end
	return nil
end

local function OnInspectReady(guid)
	if not pending or pending.guid ~= guid then return end
	local unit = FindUnit(guid, pending.unit)
	pending = nil
	Inspect.stats.ready = Inspect.stats.ready + 1
	if unit then
		local anyGear = false
		for slot = 1, 18 do
			if GetInventoryItemID(unit, slot) then anyGear = true break end
		end
		local _, classFile = UnitClass(unit)
		Inspect.Record(ns.UnitFullName(unit), GetGuildInfo(unit), classFile, UnitLevel(unit),
			GetInventoryItemID(unit, TABARD_SLOT), anyGear)
	end
	if not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then ClearInspectPlayer() end
end

function Inspect.SetPatrol(on)
	if on and not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	patrol = on and true or false
	ns.Print(patrol and L.PATROL_ON or L.PATROL_OFF)
	ns.Log("patrol = %s", tostring(patrol))
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.InspectTarget()
	if not UnitIsPlayer("target") then
		ns.Print(L.NEED_PLAYER_TARGET)
		return
	end
	Enqueue("target", true)
	Pump()
end

function Inspect.MarkTarget(note)
	if not UnitIsPlayer("target") then
		ns.Print(L.NEED_PLAYER_TARGET)
		return
	end
	local name = Key(ns.UnitFullName("target"))
	local s = Store()
	local p = s.players[name] or { name = name, status = "UNCHECKED", t = ns.Now() }
	local _, classFile = UnitClass("target")
	p.guild, p.class, p.level = GetGuildInfo("target"), classFile, UnitLevel("target")
	p.marked = true
	if note and note ~= "" then p.note = note end
	s.players[name] = p
	ns.Print(L.MARKED:format(ns.ShortName(name), p.guild or "?"))
	Enqueue("target", true)
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.ToggleMark(name)
	local p = Source().players[Key(name)]
	if not p then return end
	p.marked = not p.marked
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.ToggleGuildMark(guild)
	local marks = Source().guildMarks
	marks[guild] = not marks[guild] or nil
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.Clear()
	local s = Store()
	wipe(s.players)
	wipe(s.guildMarks)
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.Summary()
	local src = Source()
	local out = { players = {}, guilds = {}, counts = { GUILD = 0, OTHER = 0, NONE = 0, UNKNOWN = 0, UNCHECKED = 0 }, total = 0 }
	local byGuild = {}
	for _, p in pairs(src.players) do
		out.players[#out.players + 1] = p
		out.total = out.total + 1
		out.counts[p.status] = (out.counts[p.status] or 0) + 1
		local gname = p.guild or "?"
		local g = byGuild[gname]
		if not g then
			g = { name = gname, total = 0, bad = 0, marked = src.guildMarks[gname] and true or false }
			byGuild[gname] = g
			out.guilds[#out.guilds + 1] = g
		end
		g.total = g.total + 1
		if p.status == "NONE" or p.status == "OTHER" or p.marked then g.bad = g.bad + 1 end
	end
	for gname in pairs(src.guildMarks) do
		if not byGuild[gname] then out.guilds[#out.guilds + 1] = { name = gname, total = 0, bad = 0, marked = true } end
	end
	table.sort(out.players, function(a, b)
		if (a.marked and true or false) ~= (b.marked and true or false) then return a.marked and true or false end
		local oa, ob = STATUS_ORDER[a.status] or 9, STATUS_ORDER[b.status] or 9
		if oa ~= ob then return oa < ob end
		return (a.t or 0) > (b.t or 0)
	end)
	table.sort(out.guilds, function(a, b)
		if a.marked ~= b.marked then return a.marked end
		if a.bad ~= b.bad then return a.bad > b.bad end
		return a.name < b.name
	end)
	return out
end

function Inspect.DiscordText()
	local s = Inspect.Summary()
	local c = s.counts
	local out = {}
	out[#out + 1] = L.DISCORD_INSPECT_HEADER:format(s.total, c.GUILD, c.NONE, c.OTHER)
	local guilds = {}
	for _, g in ipairs(s.guilds) do
		if g.bad > 0 or g.marked then
			guilds[#guilds + 1] = ("%s%s %d/%d"):format(g.marked and "[!] " or "", g.name, g.bad, g.total)
		end
	end
	if #guilds > 0 then out[#out + 1] = "**Guilds:** " .. table.concat(guilds, " · ") end
	out[#out + 1] = "```"
	local any = false
	for _, p in ipairs(s.players) do
		if p.status == "NONE" or p.status == "OTHER" or p.marked then
			any = true
			local label = p.status == "NONE" and "NO TABARD" or p.status == "OTHER" and "WRONG TABARD" or "MARKED"
			out[#out + 1] = ("%-14s %-20s %-12s %s"):format(ns.ShortName(p.name), "<" .. (p.guild or "?") .. ">", label, p.note or "")
		end
	end
	if not any then out[#out + 1] = L.DISCORD_INSPECT_CLEAN end
	out[#out + 1] = "```"
	return table.concat(out, "\n")
end

function Inspect.TooltipLine(name)
	local p = Source().players[Key(name)]
	if not p then return nil end
	if p.status == "YOUNG" and not p.marked then return nil end -- the rule starts at MIN_LEVEL
	local text
	if p.status == "GUILD" then text = "|cff40ff40" .. L.TABARD_OK .. "|r"
	elseif p.status == "NONE" then text = "|cffff4040" .. L.TABARD_NONE .. "|r"
	elseif p.status == "OTHER" then text = "|cffffd200" .. L.TABARD_OTHER .. "|r"
	else text = "|cff9d9d9d" .. L.TABARD_UNKNOWN .. "|r" end
	if p.marked then text = text .. "  |cffff4040[" .. L.MARK .. "]|r" end
	return L.TABARD .. ": " .. text .. "  |cff9d9d9d" .. ns.Ago(p.t) .. "|r"
end

---------------------------------------------------------------------------
-- Wall of Shame: the Crown publishes the list of players caught without the colors,
-- every Olympus member with the addon sees it (chat, raid warning, Heraldry tab).
-- Closed until the tabard rule is in force, midnight in Texas (where Asmongold is) between
-- September 24 and 25, 2026: nothing published, lists sent by older versions ignored, and
-- the Tabards page counts down to it.
---------------------------------------------------------------------------

Inspect.SHAME_FROM = 1790312400 -- 2026-09-25 00:00 CDT (05:00 UTC)
local function ServerNow() return (GetServerTime and GetServerTime()) or time() end
function Inspect.ShameOpen() return ServerNow() >= Inspect.SHAME_FROM end
function Inspect.ShameOpensIn() return math.max(0, Inspect.SHAME_FROM - ServerNow()) end

-- Pardoned by the King (Acts.lua): off every list for a week, ours and the ones we receive.
local function Pardoned(name) return ns.Acts and ns.Acts.Pardoned and ns.Acts.Pardoned(name) == true end

function Inspect.ShameList()
	local out = {}
	for _, p in ipairs(Inspect.Summary().players) do
		if (p.status == "NONE" or p.status == "OTHER" or p.marked) and not Pardoned(p.name) then
			out[#out + 1] = { name = ns.ShortName(p.name), guild = p.guild }
		end
	end
	return out
end

-- A wall is a raid warning and a loud alert on every screen, so like the decrees (Decree.lua)
-- it is rate-limited on both ends: the Crown publishes once a minute, each sender is heard
-- once a minute and all of them SHAME_PER_MINUTE times a minute, and a wall that names the
-- same players as the one shown changes nothing (no alert, no redraw).
Inspect.SHAME_COOLDOWN = 60
Inspect.SHAME_PER_SENDER = 60
Inspect.SHAME_PER_MINUTE = 6
local lastShameSent = -math.huge
local shameBySender = {}
local shameRecent = {} -- when the walls we accepted arrived (flood guard)

function Inspect.PublishShame()
	if not Inspect.ShameOpen() then return end
	if not ns.IsCrown() then
		ns.Print(L.CROWN_ONLY)
		return
	end
	local now = ns.Now()
	if now - lastShameSent < Inspect.SHAME_COOLDOWN then
		ns.Print(L.SHAME_COOLDOWN:format(math.ceil(Inspect.SHAME_COOLDOWN - (now - lastShameSent))))
		return
	end
	Inspect.Prune() -- (the Royal Inspection just added what the patrols reported)
	local list = Inspect.ShameList()
	if #list == 0 then
		ns.Print(L.DISCORD_INSPECT_CLEAN)
		return
	end
	lastShameSent = now
	local guild, _, rankIndex = GetGuildInfo("player")
	ns.Comm.SendChunked(ns.Codec.EncodeShame(guild, rankIndex, list))
	local by = ns.DisplayName(ns.me)
	-- The same wall again (for those who logged in since): sent, and only a line here.
	if not Inspect.ShowShame({ by = by, guild = guild, list = list, t = now }) then
		ns.Print("|cffff4040" .. L.SHAME_PUBLISHED:format(#list, by) .. "|r")
	end
end

-- The same players (and guilds) in any order.
local function SameWall(a, b)
	if not a or not b or #a.list ~= #b.list then return false end
	local names = {}
	for _, p in ipairs(a.list) do names[tostring(p.name) .. ":" .. tostring(p.guild)] = true end
	for _, p in ipairs(b.list) do
		if not names[tostring(p.name) .. ":" .. tostring(p.guild)] then return false end
	end
	return true
end

-- Shows a wall; false when it names the same players as the one shown (nothing happens).
function Inspect.ShowShame(shame)
	for i = #shame.list, 1, -1 do
		if Pardoned(shame.list[i].name) then table.remove(shame.list, i) end
	end
	if SameWall(Inspect.shame, shame) then return false end
	Inspect.shame = shame
	local text = L.SHAME_PUBLISHED:format(#shame.list, shame.by)
	ns.Print("|cffff4040" .. text .. "|r")
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.1 })
	end
	ns.PlayAlert("loud")
	ns.Fire("INSPECT_CHANGED")
	return true
end

function Inspect.Shame()
	return Inspect.shame
end

function Inspect.HandleShame(dist, sender, text)
	if dist ~= "CHANNEL" or not Inspect.ShameOpen() then return end
	local s = ns.Codec.DecodeShame(text)
	if not s or not ns.IsFederation(s.guild) then return end
	local rank = ns.Data.KnownRank(sender, s.guild)
	if not rank or not ns.IsCrownRank(s.guild, rank) then return end
	local now = ns.Now()
	if now - (shameBySender[sender] or -math.huge) < Inspect.SHAME_PER_SENDER then return end
	for i = #shameRecent, 1, -1 do if now - shameRecent[i] > 60 then table.remove(shameRecent, i) end end
	if #shameRecent >= Inspect.SHAME_PER_MINUTE then return end
	shameBySender[sender] = now
	shameRecent[#shameRecent + 1] = now
	Inspect.ShowShame({ by = ns.DisplayName(sender), guild = s.guild, list = s.list, t = now })
end
ns.Comm.Handle("S1", function(...) Inspect.HandleShame(...) end)

-- Tests start from a clean state.
function Inspect.ResetShame()
	lastShameSent = -math.huge
	wipe(shameBySender); wipe(shameRecent)
	Inspect.shame = nil
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function OnTooltipUnit(tooltip)
	if tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	if not unit or not UnitIsPlayer(unit) then return end
	local name = ns.UnitFullName(unit)
	local line = Inspect.TooltipLine(name)
	if line then tooltip:AddLine(line) end
	-- The Treasurer of Olympus: his name and the game's own word on his guild.
	if ns.IsTreasurer(name, GetGuildInfo(unit)) then tooltip:AddLine(ns.COIN .. L.TREASURER_TITLE, 1, 0.82, 0) end
	if patrol then Enqueue(unit) end
end

ns.On("INIT", function() Inspect.Prune() end) -- (Prune makes the store too)

ns.On("LOGIN", function()
	ns.RegisterEvent("INSPECT_READY", OnInspectReady)
	ns.Every(INTERVAL, "inspect pump", Pump)
	local hooked = false
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
			ns.SafeCall("tooltip", OnTooltipUnit, tt)
		end)
	end
	if not hooked then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt)
			ns.SafeCall("tooltip", OnTooltipUnit, tt)
		end)
	end
	ns.Log("tooltip hook: %s", hooked and "TooltipDataProcessor" or "OnTooltipSetUnit")
end)

