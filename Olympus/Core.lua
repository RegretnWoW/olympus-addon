local ADDON, ns = ...
local L = ns.L

ns.NAME = "Olympus"
ns.VERSION = "0.9.9"
ns.PREFIX = "OLYMPUS"        -- addon message prefix (max 16 chars)
ns.CHANNEL = "OlympusNet"    -- hidden chat channel shared by every Olympus guild (Alliance)
ns.CHANNEL_HORDE = "OlympusNetH" -- the Horde's: the two factions never see each other's guilds
ns.ICON = "Interface\\AddOns\\Olympus\\media\\logo64"
ns.LOGO = "Interface\\AddOns\\Olympus\\media\\logo128"
ns.EMBLEM = "Interface\\AddOns\\Olympus\\media\\emblem128"
ns.COLOR = "ffe6c35c"

local DEFAULTS = {
	showMap = true,
	minimapAngle = 200,
	hideMinimap = false,
	debug = false,
	warnDays = 3,          -- leaders/officers offline this many days are flagged
	sharePosition = false, -- guildmate dots are disabled: positions are not live enough
	showMates = false,
	showDecrees = true,    -- show decree markers on the map
	sound = true,          -- alert sounds (throttled)
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Now() return time() end

function ns.Print(msg)
	print("|c" .. ns.COLOR .. "Olympus:|r " .. tostring(msg))
end

function ns.FormatNumber(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local sign, digits = s:match("^(%-?)(%d+)$")
	if not digits then return s end
	local out = digits:reverse():gsub("(%d%d%d)", "%1" .. L.THOUSANDS):reverse()
	if out:sub(1, #L.THOUSANDS) == L.THOUSANDS then out = out:sub(#L.THOUSANDS + 1) end
	return sign .. out
end

function ns.Ago(t)
	if not t or t == 0 then return L.NEVER end
	local d = math.max(0, ns.Now() - t)
	if d < 60 then return L.AGO_SEC:format(d) end
	if d < 3600 then return L.AGO_MIN:format(math.floor(d / 60)) end
	return L.AGO_HOUR:format(math.floor(d / 3600))
end

-- At most n bytes of s, never half a letter (an accented letter is two bytes or more).
function ns.Cut(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	local b = s:byte(n + 1)
	while n > 0 and b and b >= 128 and b < 192 do
		n = n - 1
		b = s:byte(n + 1)
	end
	return s:sub(1, n)
end

function ns.ShortName(name)
	if not name then return nil end
	return (name:gsub("%-.*$", ""))
end

-- This realm's key, the same form the server uses in "Name-Realm" (no spaces or dashes).
function ns.CurrentRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if not realm or realm == "" then realm = ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "") end
	return realm ~= "" and realm or "?"
end

-- Identity is always "Name-Realm". Names without a realm belong to `realm` (default: ours).
-- Comparing short names let a same-named player from another realm pass as someone else.
function ns.FullName(name, realm)
	if not name or name == "" or name:find("-", 1, true) then return name end
	realm = realm or ns.realm
	if not realm or realm == "" or realm == "?" then return name end
	return name .. "-" .. realm
end

function ns.RealmOf(name)
	return name and name:match("%-(.+)$")
end

-- Short name for people on our realm, Name-Realm for anyone else.
function ns.DisplayName(name)
	if not name then return nil end
	local realm = ns.RealmOf(name)
	if not realm or realm == ns.realm then return ns.ShortName(name) end
	return name
end

-- The name a whisper, an invite or /who takes. WoW: Forever's server finds "First Surname"
-- but not "First Surname-Realm" ("No player named ... is currently playing"), and its names
-- are one across a realm group: there the realm is left out for our realms. Elsewhere the
-- short name on our realm, Name-Realm for anyone else, as Blizzard's own chat does.
function ns.TellName(name)
	if type(name) ~= "string" or name == "" then return name end
	name = ns.Normal(name)
	local base, realm = name:match("^(.+)%-([^%-]+)$")
	if not realm then return name end
	if realm == ns.realm or realm == ns.CurrentRealm() or (ns.splitNames and ns.IsRealmName(realm)) then return base end
	return name
end

-- WoW: Forever's names are a first name and a surname ("Faladoriel Skylance"), and its unit
-- functions hand the surname back where the realm goes: UnitFullName("player") gives
-- "Faladoriel", "Skylance", and GetUnitName(unit, true) "Faladoriel-Skylance". The server
-- stamps addon messages "Faladoriel Skylance-ClassicBetaPvP", like the guild roster and /who:
-- that is the name everyone compares. ns.splitNames: this client splits names so (our own
-- "realm" is none).
function ns.IsRealmName(realm)
	if type(realm) ~= "string" or realm == "" then return false end
	if realm == ns.realm or realm == ns.CurrentRealm() or ns.InGroup(realm) then return true end
	return ns.GroupOf(realm) ~= realm -- a realm of a known group
end

function ns.PlayerName()
	local name, realm = UnitFullName("player")
	if not name then return "?" end
	local home = ns.realm or ns.CurrentRealm()
	if realm and realm ~= "" and realm ~= home and not ns.IsRealmName(realm) then
		ns.splitNames = true
		name, realm = name .. " " .. realm, nil
	end
	if not realm or realm == "" then realm = home end
	if realm and realm ~= "" and realm ~= "?" then return name .. "-" .. realm end
	return name
end

-- A name the game's functions or events give ("First-Surname" on Forever), as the server
-- writes it ("First Surname", with "-Realm" when it had one).
function ns.Normal(name)
	if not ns.splitNames or type(name) ~= "string" then return name end
	local first, rest = name:match("^([^%-]+)%-(.+)$")
	if not first or first:find(" ", 1, true) then return name end
	local surname, realm = rest:match("^([^%-]+)%-(.+)$")
	if surname and ns.IsRealmName(realm) then return first .. " " .. surname .. "-" .. realm end
	if ns.IsRealmName(rest) then return name end
	return first .. " " .. rest
end

-- A unit's full name as the server writes it ("Name-Realm"), or nil.
function ns.UnitFullName(unit)
	local name, realm
	if UnitFullName then name, realm = UnitFullName(unit) end
	if not name or name == "" then
		local n = GetUnitName and GetUnitName(unit, true)
		return n and ns.FullName(ns.Normal(n)) or nil
	end
	if realm and realm ~= "" and ns.splitNames and not ns.IsRealmName(realm) then name, realm = name .. " " .. realm, nil end
	return ns.FullName(name, (realm and realm ~= "") and realm or nil)
end

---------------------------------------------------------------------------
-- Realm groups. Realms whose guilds span each other share one census, one realm key and one
-- chat history: they are stored together under the group's name ("A+B", realms sorted).
-- ns.realm stays the character's own realm, for identities ("Name-Realm").
-- WoW: Forever's beta PvP realms are one group from the start (a guild of one is homed on
-- the other); any other link is learned from the roster (a guild homed on another realm).
---------------------------------------------------------------------------

local SEED_BETA = "ClassicBetaPvP+ClassicBetaPvP2"
local SEED = { ClassicBetaPvP = SEED_BETA, ClassicBetaPvP2 = SEED_BETA }

-- A realm name in the form the server uses in "Name-Realm", or nil when unusable.
local function CleanRealm(realm)
	if type(realm) ~= "string" then return nil end
	realm = realm:gsub("[%s%-]", "")
	if realm == "" or realm == "?" or realm:find("+", 1, true) then return nil end
	return realm
end

-- The group a realm belongs to: learned (db.links), else the seed, else the realm alone.
local function Learned(db, realm)
	local links = db and db.links
	local group = type(links) == "table" and links[realm]
	return type(group) == "string" and group ~= "" and group or nil
end

function ns.GroupOf(realm, db)
	return Learned(db or ns.db, realm) or SEED[realm] or realm
end

function ns.GroupRealms(group)
	local out = {}
	for realm in tostring(group or ""):gmatch("[^+]+") do out[#out + 1] = realm end
	return out
end

-- Where our group comes from, for /oly status: "learned", "seed" or "own" (not linked).
function ns.GroupSource(realm)
	if Learned(ns.db, realm) then return "learned" end
	if SEED[realm] then return "seed" end
	return "own"
end

-- Our faction: "Horde" or "Alliance". Olympus started on the Alliance, so anything unknown
-- (reports of older versions, a client that can't tell yet) counts as Alliance.
function ns.Faction()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return f == "Horde" and "Horde" or "Alliance"
end

-- Each faction keeps its census, realm key and inspections apart: the Alliance in the
-- top-level db.realms (as before), the Horde in db.horde.realms.
local function Stores(db)
	if ns.faction ~= "Horde" then return db end
	if type(db.horde) ~= "table" then db.horde = {} end
	return db.horde
end

-- Is this realm one of the realms whose census we share (ours included)?
function ns.InGroup(realm)
	if not realm then return false end
	for _, r in ipairs(ns.GroupRealms(ns.group or ns.realm)) do
		if r == realm then return true end
	end
	return false
end

-- Newest `t` wins, per key; on a tie the entry already there stays.
local function MergeNewest(dst, src)
	if type(src) ~= "table" then return end
	for k, v in pairs(src) do
		local old = dst[k]
		if type(v) == "table" and (type(old) ~= "table" or (tonumber(v.t) or 0) > (tonumber(old.t) or 0)) then dst[k] = v end
	end
end

-- Inspections: newest wins too, but an officer's mark and note never go with the older entry
-- (false is an explicit unmark: it stays).
local function MergePlayers(dst, src)
	if type(src) ~= "table" then return end
	for k, v in pairs(src) do
		local old = dst[k]
		if type(v) == "table" then
			local keep, other = v, old
			if type(old) == "table" and (tonumber(v.t) or 0) <= (tonumber(old.t) or 0) then keep, other = old, v end
			if type(other) == "table" then
				if keep.marked == nil then keep.marked = other.marked end
				if keep.note == nil then keep.note = other.note end
			end
			dst[k] = keep
		end
	end
end

local CHAT_KEEP = 100 -- lines per tier, like Channels.lua's HISTORY

-- Chat lines of both stores in time order, each once, the newest CHAT_KEEP kept.
local function MergeChat(dst, src)
	for tier, list in pairs(src) do
		if type(list) == "table" then
			local out, seen = {}, {}
			local function Add(from)
				for _, e in ipairs(type(from) == "table" and from or {}) do
					local key = type(e) == "table" and (tostring(e.t) .. "\1" .. tostring(e.sender) .. "\1" .. tostring(e.text))
					if key and not seen[key] then
						seen[key] = true
						out[#out + 1] = e
					end
				end
			end
			Add(dst[tier])
			Add(list)
			table.sort(out, function(a, b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
			while #out > CHAT_KEEP do table.remove(out, 1) end
			dst[tier] = out
		end
	end
end

-- Moves one store into another, losing nothing that is newer. Our own guild's report (`mine`)
-- is kept like any other: an alt's own guild is a report nobody else may be sending. The
-- realm key is settled by OpenStore, which sees every store at once.
local function MergeStore(dst, src)
	for _, key in ipairs({ "guilds", "seen" }) do
		dst[key] = type(dst[key]) == "table" and dst[key] or {}
		MergeNewest(dst[key], src[key])
	end
	if type(src.inspect) == "table" then
		dst.inspect = type(dst.inspect) == "table" and dst.inspect or {}
		local d, s = dst.inspect, src.inspect
		d.players = type(d.players) == "table" and d.players or {}
		MergePlayers(d.players, s.players)
		d.guildMarks = type(d.guildMarks) == "table" and d.guildMarks or {}
		for k, v in pairs(type(s.guildMarks) == "table" and s.guildMarks or {}) do
			if d.guildMarks[k] == nil then d.guildMarks[k] = v end
		end
	end
	if type(src.chat) == "table" then
		dst.chat = type(dst.chat) == "table" and dst.chat or {}
		MergeChat(dst.chat, src.chat)
	end
	-- Anything else (the "shared" proof, fields of later versions): the newest, or whichever is set.
	for k, v in pairs(src) do
		if k ~= "guilds" and k ~= "seen" and k ~= "inspect" and k ~= "chat" and k ~= "realmKey" then
			local old = dst[k]
			if old == nil or (type(v) == "table" and type(old) == "table" and (tonumber(v.t) or 0) > (tonumber(old.t) or 0)) then dst[k] = v end
		end
	end
end

-- The group's store, with the store of each of its realms (or of a smaller group of them)
-- merged in and removed, so running it again changes nothing. Realm keys: one key, or the
-- same key everywhere, is kept; different keys are all dropped, and our officers hand ours
-- out again over guild chat (K0/K1 at login).
local function OpenStore(db, group)
	if type(db.realms) ~= "table" then db.realms = {} end
	local R = db.realms[group]
	if type(R) ~= "table" then R = {} end
	db.realms[group] = R
	local members = {}
	for _, realm in ipairs(ns.GroupRealms(group)) do members[realm] = true end
	-- Collect first: the merge must not change db.realms while pairs() walks it.
	local merge = {}
	for key in pairs(db.realms) do
		if key ~= group and type(key) == "string" then
			local inside = true
			for _, realm in ipairs(ns.GroupRealms(key)) do
				if not members[realm] then inside = false end
			end
			if inside then merge[#merge + 1] = key end
		end
	end
	if #merge == 0 then return R end
	table.sort(merge)
	local keys, distinct = {}, 0
	local function Key(k)
		if type(k) == "string" and k ~= "" and not keys[k] then
			keys[k] = true
			distinct = distinct + 1
		end
	end
	Key(R.realmKey)
	for _, key in ipairs(merge) do
		local src = db.realms[key]
		if type(src) == "table" then
			Key(src.realmKey)
			-- A realm's own store (v0.7.8-0.7.10): its reports were heard on that realm (Data.Receive).
			if not key:find("+", 1, true) and type(src.guilds) == "table" then
				for _, g in pairs(src.guilds) do
					if type(g) == "table" and g.heardOn == nil then g.heardOn = key end
				end
			end
			MergeStore(R, src)
		end
		db.realms[key] = nil
	end
	if distinct == 1 then
		R.realmKey = next(keys)
	elseif distinct > 1 then
		R.realmKey = nil
	end
	ns.Log("census of %s merged into %s%s", table.concat(merge, ", "), group, distinct > 1 and " (different realm keys dropped)" or "")
	return R
end

-- Learns that realms a and b share guilds: their groups become one, for good (db.links).
-- If that changes our own group, the census moves over at once. Returns true if anything
-- was learned.
function ns.LinkRealms(a, b)
	local db = ns.db
	a, b = CleanRealm(a), CleanRealm(b)
	if not db or not a or not b or a == b then return false end
	local set, list = {}, {}
	for _, realm in ipairs({ a, b }) do
		for _, m in ipairs(ns.GroupRealms(ns.GroupOf(realm))) do
			if not set[m] then
				set[m] = true
				list[#list + 1] = m
			end
		end
	end
	table.sort(list)
	local group = table.concat(list, "+")
	local learned = false
	for _, m in ipairs(list) do
		if ns.GroupOf(m) ~= group then
			if type(db.links) ~= "table" then db.links = {} end
			db.links[m] = group
			learned = true
		end
	end
	if not learned then return false end
	ns.Log("realms linked: %s", group)
	local mine = ns.realm and ns.GroupOf(ns.realm)
	if mine and mine ~= ns.group then
		local oldKey = ns.rdb and ns.rdb.realmKey
		ns.group = mine
		ns.rdb = OpenStore(Stores(db), mine)
		ns.Print(L.REALMS_LINKED:format((mine:gsub("%+", " + "))))
		ns.Fire("DATA_CHANGED")
		-- A new key means another channel. Before our first join, that join picks it up (and
		-- the login's key request asks for a dropped key).
		if ns.rdb.realmKey ~= oldKey and ns.Comm and ns.Comm.ChannelName() then
			ns.Comm.JoinChannel()
			-- Ours was dropped (the realms had different keys): our officers hand it out again.
			if not ns.rdb.realmKey then ns.Comm.RequestKey() end
		end
	end
	return true
end

-- HereBeDragons-Pins, only if it loaded completely (a half-loaded library means no map
-- features instead of an error on every refresh).
function ns.Pins()
	local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	if pins and pins.AddWorldMapIconMap and pins.RemoveAllWorldMapIcons and pins.AddMinimapIconMap then return pins end
	return nil
end

-- Whether `ref` (Map, Decree, King, Positions) puts its icons on the world map (0.9.9). Every
-- add or remove there goes through the pin library into the map's canvas (MarkCanvasDirty,
-- which clears its current zoom), from Olympus's code. With Blizzard's gamepad UI (Forever) the
-- gamepad map then zooms, builds its button bar and closes with B in our taint, and the game
-- blocks it until a /reload. There no icon of ours goes on the world map; the minimap is not the
-- gamepad UI's, its icons stay. Icons `ref` put on the world map before a switch to the gamepad
-- UI (without a /reload) are taken off, once. With mouse and keyboard: true, as always.
local worldMapIconsOf = {} -- [ref] = true: may have icons on the world map
function ns.WorldMapIcons(pins, ref)
	if not ns.GamepadUI() then
		worldMapIconsOf[ref] = true
		return true
	end
	if worldMapIconsOf[ref] then
		worldMapIconsOf[ref] = nil
		pins:RemoveAllWorldMapIcons(ref)
	end
	return false
end

-- Round logo button with the exact geometry of minimap buttons (LibDBIcon layout at 31px,
-- scaled to the requested size): gold tracking ring, dark disc, round logo.
function ns.MakeRoundButton(name, parent, size)
	local k = size / 31
	local b = CreateFrame("Button", name, parent)
	b:SetSize(size, size)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20 * k, 20 * k)
	bg:SetPoint("TOPLEFT", 7 * k, -5 * k)
	-- The logo, a disc (the mask): centred on the dark disc behind it (LibDBIcon's square
	-- icons sit 1.5 px off it, which the ring hides; a disc there shows a crescent).
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.LOGO)
	icon:SetSize(18 * k, 18 * k)
	icon:SetPoint("TOPLEFT", 8 * k, -6 * k)
	if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53 * k, 53 * k)
	ring:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	b.icon = icon
	return b
end

-- One alert sound at most every 15 seconds, whatever triggers it.
local lastSound = 0
function ns.PlayAlert(kind)
	if not (ns.db and ns.db.sound) or not PlaySound or not SOUNDKIT then return end
	local now = GetTime()
	if now - lastSound < 15 then return end
	lastSound = now
	local id = kind == "soft" and (SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING) or SOUNDKIT.RAID_WARNING
	if id then pcall(PlaySound, id) end
end

-- Captains (officers) are rank index 1, right below the guild master, in every guild. It is
-- fixed so that senders and receivers always agree on who may send decrees.
ns.CAPTAIN_RANK = 1

-- What the army calls the King on the lines and the crown made for him (Hop.lua, King.lua),
-- whatever his character's name in the census.
ns.KING_NAME = "Asmon"
-- The addon's author (Workshop.lua): his character on Forever. Names there are a first name
-- and a surname, unique across the realm group; no Classic realm allows a space in a name.
ns.AUTHOR = "Faladoriel Skylance"
ns.AUTHOR_REALM = "ClassicBetaPvP" -- his realm group, where only he carries that name
-- A name of the realm group of `realm` (a name without a realm is ours). Forever's names are
-- one across a realm group only: the same name on another group is someone else.
local function OfGroup(name, realm)
	local own = ns.RealmOf(ns.FullName(name)) or ns.realm or ns.CurrentRealm()
	return ns.GroupOf(own) == ns.GroupOf(realm)
end
-- The Treasurer of Olympus, chosen by Asmongold's chat on September 23, 2026: exactly this
-- character, in the guild named Olympus. Look-alikes in other guilds exist: both must match,
-- and his realm group (Forever's PvP realms), where only he carries that name.
ns.TREASURER = "Pyralis Ashandar"
ns.TREASURER_REALM = "ClassicBetaPvP"
ns.COIN = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t "
function ns.IsTreasurer(name, guild)
	return type(name) == "string" and type(guild) == "string" and ns.ShortName(name) == ns.TREASURER and guild:lower() == "olympus"
		and OfGroup(name, ns.TREASURER_REALM)
end
-- The King's name on the lines and the crown: the army's name for him on the Alliance side,
-- his character's on the Horde (whose <Olympus> has a guild master of its own).
function ns.KingName(leader)
	if ns.faction == "Horde" then return leader and ns.ShortName(leader) or "?" end
	return ns.KING_NAME
end
ns.CROWN_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"

-- The King's guild on each side: the guild master of this exact name is the King, its officers
-- are of the Crown. The Alliance's is <Olympus>; the Horde's is set here once Asmongold founds
-- it (a guild name is one per realm, so it can't be "Olympus" there).
ns.KING_GUILD = { Alliance = "olympus", Horde = "mudhutters" } -- (the Horde's: <Mudhutters>, 0.9.4)
function ns.IsKingGuild(guild)
	if type(guild) ~= "string" then return false end
	local want = ns.KING_GUILD[ns.faction or "Alliance"]
	return want ~= nil and guild:lower() == want
end

-- The King himself, by his character's name, like the Treasurer: sender names are set by the
-- server, so nobody else can speak as him, and no census vote (anyone on the channel can
-- vote) can crown someone else or take the Crown from him. The Alliance's is the guild master
-- of <OLYMPUS> as the census saw him on September 24, 2026 (a Forever name, one across the
-- realm group). The Horde's is set here once it is known: until then nobody commands there
-- (his position and his name on the lines still come from the census). His name is his on his
-- realm group alone (ns.KING_REALM's): anywhere else (Forever's other realms, Classic Era,
-- Anniversary) there is no King by name either, like the Horde's, and a namesake on another
-- group is not him.
-- The Horde's (0.9.4): Duskmonkey Boneback, guild master of <Mudhutters>. His realm is not known
-- yet: until it is (ns.KING_REALM_HORDE), his name alone counts on the Horde, anywhere (Forever
-- names are one per region; a namesake can only exist on another client or region).
ns.KING_CHARACTER = { Alliance = "Asmongold Asmongler", Horde = "Duskmonkey Boneback" }
ns.KING_REALM = "ClassicBetaPvP"
ns.KING_REALM_HORDE = nil
-- Until it is set here, the Horde King's realm is learned from the first message of his that
-- reaches us (his name is his alone), and from then on only that realm group counts: shown in
-- /oly status so it can be written here.
local function KingRealm()
	if ns.faction == "Horde" then return ns.KING_REALM_HORDE or (ns.rdb and ns.rdb.kingRealmHorde) end
	return ns.KING_REALM
end
ns.KingRealm = KingRealm
function ns.KingCharacter()
	local realm = KingRealm()
	if realm and ns.GroupOf(ns.realm or ns.CurrentRealm()) ~= ns.GroupOf(realm) then return nil end
	return ns.KING_CHARACTER[ns.faction or "Alliance"]
end
function ns.IsKingCharacter(name)
	local pin = ns.KingCharacter()
	if pin == nil or type(name) ~= "string" or ns.ShortName(name) ~= pin then return false end
	local realm = KingRealm()
	return realm == nil or OfGroup(name, realm)
end
-- Learned only from a message he sent (King.lua: the sender name is the server's), never from
-- a name written inside a report, which anyone could forge to lock him out.
function ns.LearnKingRealm(sender)
	if ns.faction ~= "Horde" or KingRealm() ~= nil or not ns.rdb or not ns.IsKingCharacter(sender) then return end
	local realm = ns.RealmOf(ns.FullName(sender))
	if not realm then return end
	ns.rdb.kingRealmHorde = realm
	ns.Log("the Horde's King is on %s (learned from his first message)", realm)
end

-- The High Council: the Olympus moderators, shown with their mark and their colour in the Olympus
-- chats. No name is written in this code (it is public, and names get sniped on launch realms):
-- the list is signed by the author on his own computer and checked by every client (Sign.lua,
-- Workshop.lua).
-- The mark (0.9.9, Max's): the game's target-frame skull, the one nameplates show. Fixed: nobody
-- picks or changes it. Each councillor's own icon (0.9.8, Workshop.lua) is flavour after it; a
-- councillor who never picked one shows the mark alone.
ns.HIGH_COUNCIL_SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
ns.HIGH_COUNCIL_MARK = "|T" .. ns.HIGH_COUNCIL_SKULL .. ":0|t"
ns.HIGH_COUNCIL_COLOR = "ffb048f8"
-- Names are one per realm group: a signed list counts on the group of whoever published it.
-- The list names it "A+B": any realm of it, as this client groups realms (0.9.8: a realm linked
-- to that group since, which makes our group "A+B+C", no longer loses the list). None: anywhere.
local function OfListGroup(name, group)
	if group == nil then return true end
	for _, realm in ipairs(ns.GroupRealms(group)) do
		if OfGroup(name, realm) then return true end
	end
	return false
end
function ns.IsHighCouncillor(name)
	local c = ns.rdb and ns.rdb.council
	if type(name) ~= "string" or type(c) ~= "table" or type(c.names) ~= "table" then return false end
	if not c.names[ns.ShortName(name):lower()] then return false end
	return OfListGroup(name, c.realm)
end

-- A councillor's icon as it travels and is kept (0.9.8): a file number, or a plain icon name
-- (letters, digits and _) under Interface\Icons. Anything else is nil: nothing but these two
-- ever reaches the |T...|t of a chat line (no pipe, colon, slash or path of someone's choosing).
function ns.CouncilIconValue(v)
	if type(v) == "string" and v:match("^%d+$") then
		if #v > 10 then return nil end
		v = tonumber(v)
	end
	if type(v) == "number" then
		return (v >= 1 and v < 2147483648 and v == math.floor(v)) and v or nil
	end
	if type(v) == "string" and #v <= 64 and v:match("^[%w_]+$") then return v end
	return nil
end

-- The texture for a council icon (a file number, or its path under Interface\Icons), or nil.
function ns.CouncilIconTexture(v)
	v = ns.CouncilIconValue(v)
	if type(v) == "string" then return "Interface\\Icons\\" .. v end
	return v
end

-- A councillor's own icon, after the mark: our own choice for our lines, what their client
-- announced for anyone else's (Workshop.lua keeps it), else "" (0.9.9: no default icon any
-- more, the mark says it). Checked again here: the ones heard are kept in the SavedVariables
-- too. A name without its realm, or with another realm of the group (the titles list, a census
-- row), finds the one heard under that name: names are one per realm group, and only
-- councillors' icons are kept.
function ns.CouncilIcon(name)
	local v
	local who = type(name) == "string" and ns.FullName(name) or nil
	if who and who == ns.me then
		local mine = ns.db and ns.db.councilIcons
		v = type(mine) == "table" and mine[who] or nil
	elseif who then
		local heard = ns.rdb and ns.rdb.councilIcons
		local e = type(heard) == "table" and heard[who]
		if type(e) ~= "table" and type(heard) == "table" then
			local short = ns.ShortName(who):lower()
			for k, x in pairs(heard) do
				if type(k) == "string" and ns.ShortName(k):lower() == short then e = x break end
			end
		end
		v = type(e) == "table" and e.icon or nil
	end
	local texture = ns.CouncilIconTexture(v)
	return texture and ("|T" .. texture .. ":0|t") or ""
end

-- What goes with a councillor's name: the mark, then their own icon if they picked one. ""
-- for anyone not on the council.
function ns.CouncilMark(name)
	if not ns.IsHighCouncillor(name) then return "" end
	return ns.HIGH_COUNCIL_MARK .. ns.CouncilIcon(name)
end

-- The council's departments and titles (0.9.9, Workshop.TakeTitles), signed apart from the
-- names: nil when none reached us, or when it is another realm group's (like the names).
function ns.CouncilTitles()
	local t = ns.rdb and ns.rdb.councilTitles
	if type(t) ~= "table" or type(t.depts) ~= "table" then return nil end
	if not OfListGroup(ns.me, t.realm) then return nil end
	return t
end

-- A councillor's place in that list: { title, dept, icon } (the department's icon), each of
-- them nil when the list gives none; nil for anyone not on the council's name list, or not in
-- the titles. Kept in the SavedVariables: checked again here.
function ns.CouncilTitle(name)
	local t = ns.IsHighCouncillor(name) and ns.CouncilTitles()
	if not t then return nil end
	local short = ns.ShortName(name):lower()
	for _, d in ipairs(t.depts) do
		for _, m in ipairs(type(d) == "table" and type(d.members) == "table" and d.members or {}) do
			if type(m) == "table" and type(m.name) == "string" and m.name:lower() == short then
				local dept = type(d.name) == "string" and d.name ~= "" and d.name or nil
				local title = type(m.title) == "string" and m.title ~= "" and m.title or nil
				return { title = title, dept = dept, icon = dept and ns.CouncilIconValue(d.icon) or nil }
			end
		end
	end
	return nil
end

-- The King's own screen (0.9.9, the author's, for Asmon's stream): the King's client, or the
-- author's "Asmon's view" (King.Preview) so he can try it. Nobody else's.
function ns.KingsScreen()
	local K = ns.King
	if type(K) ~= "table" or type(K.IsKing) ~= "function" then return false end
	return K.IsKing() == true or (type(K.Preview) == "function" and K.Preview() == true)
end

-- Who sees the High Council in the census, its marks there and its titles (0.9.9, the author's
-- call): until launch the councillors themselves, the author's own client (the one holding the
-- signed lists, CouncilList.lua) and the King's (names hidden, below); everyone once the signed
-- titles list says it is public. The Olympus chats show the mark to everyone, as in 0.9.8.
function ns.CouncilVisible()
	if ns.COUNCIL_SIGNED ~= nil or ns.COUNCIL_TITLES ~= nil or ns.IsHighCouncillor(ns.me) or ns.KingsScreen() then return true end
	local t = ns.CouncilTitles()
	return t ~= nil and t.public == true
end

-- The King streams: on his screen the councillors' names stay hidden (0.9.9). The High Council
-- in the Realm shows each name cut short (ns.MaskName), and no council mark, icon or title goes
-- with a name anywhere else (census rows, person card, Olympus chats), until he clicks the eye
-- under the council's header. Never saved: every login and /reload starts hidden again.
local councilNamesShown = false
function ns.CouncilNamesShown() return councilNamesShown end
function ns.SetCouncilNamesShown(on) councilNamesShown = on == true end
function ns.CouncilMasked() return not councilNamesShown and ns.KingsScreen() end

-- A councillor's name while hidden: its first four characters (UTF-8: a character is a lead
-- byte and the continuation bytes after it), or all of a shorter name, then "****".
function ns.MaskName(name)
	local s, chars, cut = tostring(name or ""), 0, nil
	for i = 1, #s do
		local b = s:byte(i)
		if b < 0x80 or b >= 0xC0 then
			chars = chars + 1
			if chars > 4 then cut = i - 1 break end
		end
	end
	return (cut and s:sub(1, cut) or s) .. "****"
end

-- Letters folded for a search (the Workshop's, 0.9.9; the tabs', 1.0.0), byte by byte: A-Z, and
-- Latin-1's accented capitals (À to Þ but ×, in UTF-8 C3 80-9E, their small letters C3 A0-BE).
-- Not the C library's lower(): its idea of a letter can change with the locale and split a UTF-8
-- letter. Any other letter stays whole.
function ns.Fold(s)
	s = tostring(s or ""):gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
	return (s:gsub("\195([\128-\158])", function(c)
		if c == "\151" then return nil end
		return "\195" .. string.char(c:byte() + 32)
	end))
end

-- Does one of the texts hold `query` (folded, ns.Fold)? As plain text, never a Lua pattern, and
-- only what a row shows: its colour codes, textures and a link's data left out, the link's
-- [text] kept, an escaped "||" one "|" (and no code). No query (nil or ""): everything does.
function ns.Holds(query, ...)
	if not query or query == "" then return true end
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if type(s) == "string" and s ~= "" then
			s = s:gsub("||", "\1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
			if ns.Fold((s:gsub("\1", "|"))):find(query, 1, true) then return true end
		end
	end
	return false
end

-- The Crown: guild masters of any Olympus guild, and the officers of the King's guild.
function ns.IsCrownRank(guild, rankIndex)
	if not guild or not rankIndex then return false end
	if rankIndex == 0 then return true end
	return ns.IsKingGuild(guild) and rankIndex <= ns.CAPTAIN_RANK
end

function ns.IsCrown()
	local guild, _, rankIndex = GetGuildInfo("player")
	return ns.IsFederation(guild) and ns.IsCrownRank(guild, rankIndex)
end

-- Fixed on purpose: only guilds with "Olympus" in their name belong to the realm, however
-- they spelled it. Guilds were made with the word misspelled (OLYMPVS the Roman way, Olimpvs,
-- Olmps, Olympuz...). Each word of the name is read the way it sounds (v as u, i as y, z as s,
-- 0 as o, a doubled letter once); then one slip anywhere in a word counts (a letter changed,
-- missing or added, or two swapped), and two at the start of a word that starts with an O
-- (Olmps, Olymp, Olympe, Oymps). Olimpo/Olympo/Olympos count the same way. Words are never
-- joined: "Holy Mpulse" is not Olympus. Olympia, Olympic, Olympian, Olympiad and the like in
-- other languages (Olympique, olympisch) are other words and are left out, and so is polyp.
-- The main guild itself (the King's, the Treasurer's) is still the exact name, see IsCrownRank.
local REALM_WORDS = { "olympus", "olympo" } -- as they sound: Olympus, Olympo, Olimpo, Olympos
local OTHER = { "olympy[aceoq]", "olympysch", "polyp" } -- as they sound: Olympia, Olympic...

-- How many slips from a to b (a letter changed, missing or added, or two neighbours
-- swapped), counted up to limit + 1.
local function Slips(a, b, limit)
	local la, lb = #a, #b
	if la - lb > limit or lb - la > limit then return limit + 1 end
	local prev2, prev, row = nil, {}, nil
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		row = { [0] = i }
		local best = i
		local ca = a:byte(i)
		for j = 1, lb do
			local cost = (ca == b:byte(j)) and 0 or 1
			local v = math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
			if prev2 and i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then
				v = math.min(v, prev2[j - 2] + 1)
			end
			row[j] = v
			if v < best then best = v end
		end
		if best > limit then return limit + 1 end
		prev2, prev = prev, row
	end
	return prev[lb]
end
ns.Slips = Slips -- tests

-- A word as it sounds: v as u, i as y, z as s, a doubled letter once.
local function Sounds(word)
	word = word:gsub("v", "u"):gsub("i", "y"):gsub("z", "s")
	local out, last = {}, nil
	for c in word:gmatch(".") do
		if c ~= last then out[#out + 1] = c end
		last = c
	end
	return table.concat(out)
end
ns.Sounds = function(guild) return Sounds(guild:lower():gsub("0", "o"):gsub("[^%a]", "")) end -- tests

local function OlympusWord(word)
	for _, other in ipairs(OTHER) do
		if word:find(other) then return false end
	end
	for _, target in ipairs(REALM_WORDS) do
		if word:find(target, 1, true) then return true end
		-- One slip anywhere in the word (Olympo's no shorter than itself: "olymo" is in polymorph).
		for len = target == "olympo" and #target or #target - 1, #target + 1 do
			for i = 1, #word - len + 1 do
				if Slips(word:sub(i, i + len - 1), target, 1) <= 1 then return true end
			end
		end
		-- Two at its start, if it starts with an O.
		if word:sub(1, 1) == "o" then
			for len = #target - 2, #target + 2 do
				if len >= 5 and len <= #word and Slips(word:sub(1, len), target, 2) <= 2 then return true end
			end
		end
	end
	return false
end

-- A guild against Olympus is none of it: "ANTI OLYMPUS", "Against Olympus", "Down with
-- Olympus", "AntiOlympus", "Olympus Haters". The word before (or the one before "with", "to",
-- "the", "of"), glued in front, or the word after.
local AGAINST = { anti = true, against = true, no = true, ["not"] = true, never = true, down = true,
	death = true, kill = true, hate = true, hates = true, haters = true, destroy = true }
local LINKS = { with = true, to = true, the = true, of = true }
local AGAINST_AFTER = { haters = true, hater = true, sucks = true }

local function Against(words, i)
	if words[i]:find("^anti") then return true end -- glued: AntiOlympus
	local before, before2 = words[i - 1], words[i - 2]
	if before and AGAINST[before] then return true end
	if before and LINKS[before] and before2 and AGAINST[before2] then return true end
	local after = words[i + 1]
	return after ~= nil and AGAINST_AFTER[after] == true
end

local federation, federationSize = {}, 0 -- [name] = true|false, asked often: kept
local function Federation(guild)
	local words = {}
	for word in guild:lower():gsub("0", "o"):gsub("1", "l"):gmatch("%a+") do words[#words + 1] = word end
	for i, word in ipairs(words) do
		if (word:find("olympus", 1, true) or OlympusWord(Sounds(word))) and not Against(words, i) then return true end
	end
	return false
end

function ns.IsFederation(guild)
	if type(guild) ~= "string" or guild == "" then return false end
	-- The King's own guild is Olympus whatever its name (the Horde's is <Mudhutters>, 0.9.4).
	if ns.IsKingGuild(guild) then return true end
	local known = federation[guild]
	if known == nil then
		known = Federation(guild)
		if federationSize >= 2000 then federation, federationSize = {}, 0 end
		federation[guild], federationSize = known, federationSize + 1
	end
	return known
end

-- The addon only works for members of an Olympus guild.
function ns.IsMember()
	return IsInGuild() and ns.IsFederation(GetGuildInfo("player"))
end

---------------------------------------------------------------------------
-- Log (ring buffer in SavedVariables, readable from WTF/.../SavedVariables/Olympus.lua)
---------------------------------------------------------------------------

function ns.Log(fmt, ...)
	local msg
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, fmt, ...)
		msg = ok and res or tostring(fmt)
	else
		msg = tostring(fmt)
	end
	local db = ns.db
	if not db then return end
	local log = db.log
	log[#log + 1] = date("%m-%d %H:%M:%S ") .. msg
	while #log > 400 do table.remove(log, 1) end
	if db.debug then ns.Print("|cff999999" .. msg .. "|r") end
end

---------------------------------------------------------------------------
-- Internal callbacks and WoW events. Every handler runs protected so one bug
-- never breaks the rest of the addon; errors go to ns.CaptureError (Diagnostics.lua).
---------------------------------------------------------------------------

function ns.SafeCall(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and ns.CaptureError then ns.CaptureError(where, err) end
	return ok
end

local listeners = {}
function ns.On(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end
function ns.Fire(name, ...)
	local l = listeners[name]
	if not l then return end
	for i = 1, #l do ns.SafeCall("callback " .. name, l[i], ...) end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if not h then return end
	for i = 1, #h do ns.SafeCall("event " .. event, h[i], ...) end
end)

-- Timers that also run protected.
function ns.After(seconds, where, fn)
	C_Timer.After(seconds, function() ns.SafeCall(where, fn) end)
end
function ns.Every(seconds, where, fn)
	return C_Timer.NewTicker(seconds, function() ns.SafeCall(where, fn) end)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	OlympusDB = OlympusDB or {}
	local db = OlympusDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	db.blocked = db.blocked or {}
	db.pattern = nil
	db.log = db.log or {}
	db.errors = db.errors or {}
	db.sessions = (db.sessions or 0) + 1
	-- v0.5: guildmate dots are retired, switch them off for existing installs too.
	if (db.configVersion or 0) < 2 then
		db.showMates, db.sharePosition = false, false
		db.configVersion = 2
	end
	-- v0.7.9: demo data is gone (testers took it for real data). Forget the old setting.
	db.demo = nil
	if db.configVersion < 3 then db.configVersion = 3 end
	-- Guild reports and the realm key belong to one realm group (ns.GroupOf): realms whose
	-- guilds span each other (PvP and PvP 2 in the beta) share them, any other realm keeps
	-- its own. The stores v0.7.8-0.7.10 kept per realm are merged into their group's here.
	ns.db = db
	ns.realm = ns.CurrentRealm()
	ns.group = ns.GroupOf(ns.realm, db)
	ns.faction = ns.Faction()
	ns.Log("---- session %d, v%s, realm %s, census %s, %s ----", db.sessions, ns.VERSION, ns.realm, ns.group, ns.faction)
	local R = OpenStore(Stores(db), ns.group)
	R.guilds = R.guilds or {}
	R.seen = R.seen or {} -- Olympus guilds seen with /who (Data.lua), never mixed with the reports
	-- Old account-wide census and key: there is no telling which realm they came from, so
	-- drop them. The census refills from the channel within minutes and officers hand the
	-- key out again over guild chat (K0/K1) at login.
	db.guilds, db.realmKey, db.officerRank = nil, nil, nil
	-- Tabard inspections are about the players of one realm group too. The old account-wide
	-- ones can only be the Alliance's: they wait at the account level for an Alliance login.
	if db.inspect and ns.faction ~= "Horde" then
		if R.inspect == nil then R.inspect = db.inspect end
		db.inspect = nil
	end
	-- Block list keys become "name-realm" (old keys were short names from this realm).
	-- Collect first: adding keys while pairs() walks the table is an error in Lua 5.1.
	if ns.realm ~= "?" then
		local short = {}
		for k in pairs(db.blocked) do
			if not k:find("-", 1, true) then short[#short + 1] = k end
		end
		for _, k in ipairs(short) do
			db.blocked[k] = nil
			db.blocked[(k .. "-" .. ns.realm):lower()] = true
		end
	end
	ns.rdb = R
	ns.Fire("INIT")
end)

-- Files added by an update only load once the game restarts: it reads the file list at
-- startup and /reload keeps the old one. Until then these stand-ins take the calls the
-- other files make, so the rest keeps working, and the player is told to restart.
-- Set here, before the files that use them load; the real files replace them.
local function StandIn(key, say)
	local restart = function() ns.Print(L.RESTART_NEEDED) end
	local stub = { missing = true }
	for _, fn in ipairs(say) do stub[fn] = restart end
	ns[key] = setmetatable(stub, { __index = function() return function() end end })
end
StandIn("Who", { "Search", "SendPlain" })
StandIn("Channels", { "Send", "ToggleMute" })
StandIn("King", { "Summon", "Inspect", "AgendaPrompt" })
StandIn("Hop", { "Ask", "AskKing", "SetHelp", "SetAuto" })
StandIn("Workshop", { "RollCall" })
StandIn("Vox", { "Prompt", "CloseNow", "SetOff" })
StandIn("Court", { "Toggle" })
StandIn("Treasury", {})
StandIn("Acts", { "WritPrompt" })
StandIn("Dialog", {})
StandIn("Bank", {})

-- Blizzard's gamepad UI (WoW: Forever's controller mode) is on.
function ns.GamepadUI()
	local current = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
	local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
	if not current or gamepad == nil then return false end
	local ok, style = pcall(current)
	return ok and style == gamepad
end

-- The addon's popups (its StaticPopupDialogs entries): with mouse and keyboard the game's own,
-- as always; with the gamepad UI Olympus's (Dialog.lua), because there the game's popups
-- break when an addon opens one (the "blocked" loop that freezes the game).
-- Escape closes our windows (UISpecialFrames), except with Blizzard's gamepad UI on: its menus
-- close every window on that list, ours with them, while the player is using it (0.9.6). There
-- they close with their own X.
-- With the gamepad UI Olympus writes nothing to that list (0.9.8). Blizzard reads it with no
-- protection (CloseSpecialWindows, from its menus and when the player loses control), and a
-- name table.remove moves down a place is one Olympus wrote from then on. A name of ours put
-- there before a switch to the gamepad UI leaves only when it is the last one: nothing moves.
function ns.EscapeCloses(name)
	if type(name) ~= "string" or not UISpecialFrames then return end
	local gamepad = ns.GamepadUI()
	for i, n in ipairs(UISpecialFrames) do
		if n == name then
			-- Switched to the gamepad UI since: off the list (checked each time it shows).
			if gamepad and i == #UISpecialFrames then UISpecialFrames[i] = nil end
			return
		end
	end
	if not gamepad then table.insert(UISpecialFrames, name) end
end

function ns.ShowDialog(which, a, b, data)
	ns.Log("dialog %s (%s)", tostring(which), ns.GamepadUI() and "olympus window, gamepad UI" or "game popup")
	if ns.GamepadUI() then
		-- Updated without restarting the game (Dialog.lua not loaded yet): never the game's
		-- popup there, the player is told to restart.
		if ns.Dialog.missing then ns.Print(L.RESTART_NEEDED) return nil end
		return ns.Dialog.Show(which, a, b, data)
	end
	return StaticPopup_Show(which, a, b, data)
end
function ns.HideDialog(which, data)
	if not ns.Dialog.missing then ns.Dialog.Hide(which, data) end
	if not ns.GamepadUI() and StaticPopup_Hide then StaticPopup_Hide(which, data) end
end

-- The keyboard to one of our edit boxes (setFocus: its own SetFocus). With the gamepad UI,
-- not while another box has it (the chat's): its focus change would run the game's gamepad
-- code from ours, and the game blocks it (see Dialog.lua); the player clicks into ours.
function ns.Focus(eb, setFocus)
	setFocus = setFocus or eb.SetFocus
	if ns.GamepadUI() and GetCurrentKeyBoardFocus then
		local current = GetCurrentKeyBoardFocus()
		if current and current ~= eb and not current.olympusBox then return false end
	end
	setFocus(eb)
	return true
end

-- The faction may not be known yet at ADDON_LOADED: if it turns out to be the other one,
-- switch to that faction's store before anything is received.
function ns.CheckFaction()
	local f = ns.Faction()
	if not ns.db or f == ns.faction then return false end
	ns.faction = f
	local R = OpenStore(Stores(ns.db), ns.group)
	R.guilds = R.guilds or {}
	R.seen = R.seen or {}
	ns.rdb = R
	ns.Log("faction is %s: using its census", f)
	return true
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	ns.CheckFaction()
	local missing = {}
	for _, key in ipairs({ "Who", "Channels", "King", "Hop", "Workshop", "Vox", "Court", "Treasury", "Acts", "Dialog", "Bank" }) do
		if ns[key].missing then missing[#missing + 1] = key .. ".lua" end
	end
	if #missing > 0 then
		ns.Log("not loaded until the game restarts: %s", table.concat(missing, ", "))
		ns.Print(L.RESTART_NEEDED)
	end
	ns.me = ns.PlayerName()
	ns.Log("login as %s", ns.me)
	ns.Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
	ns.Print("v" .. ns.VERSION .. " commands:")
	print("  /oly - open/close the window")
	print("  /oly tabard - Heraldry Inspection tab")
	print("  /oly sound - turn alert sounds on/off")
	print("  /oly patrol - start/stop inspecting nearby Olympus members")
	print("  /oly mark [reason] - mark your target")
	print("  /oly map - show/hide zone counts on the world map")
	print("  /oly realm - the Realm tree (leaders, officers, ranks)")
	print("  /oly layers - layers of your zone (in the Realm tab)")
	print(L.HELP_HOP)
	print(L.HELP_LAYERHELP)
	print(L.HELP_LAYERAUTO)
	print(L.HELP_LOCATION)
	print(L.HELP_ROLLCALL)
	print(L.HELP_TREASURER)
	print(L.HELP_INSPECTION)
	print(L.HELP_ISSUE)
	print(L.HELP_COUNCIL)
	print("  /oly decrees - decrees")
	print("  /oly arms [text] | /oly muster [text] - decree (officers; 'test' = local preview)")
	print(L.HELP_CHAN_ALL)
	print(L.HELP_CHAN_CAPTAINS)
	print(L.HELP_CHAN_LORDS)
	print(L.HELP_CHAN_MUTE)
	print(L.HELP_CHATWIN)
	print(L.HELP_VOX)
	print("  /oly mates - show/hide guildmates on map and minimap")
	print("  /oly share - share/stop sharing your position with your guild")
	print("  /oly bug - copy a bug report (errors + diagnostics)")
	print("  /oly status - print diagnostics in chat")
	print("  /oly key <secret> - officers: seal the Olympus channel with a shared secret")
	print("  /oly block <name> - ignore everything a player sends")
	print("  /oly layer - show the layer id of your target (test)")
	print("  /oly minimap - show/hide the minimap button")
	print("  /oly debug - verbose log in chat")
	print("  /oly reset - forget all cached guild reports and /who sightings")
end

SLASH_OLYMPUS1 = "/olympus"
SLASH_OLYMPUS2 = "/oly"
SlashCmdList.OLYMPUS = function(input)
	ns.SafeCall("slash " .. tostring(input), function()
		local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
		cmd = (cmd or ""):lower()
		if cmd == "" then
			ns.UI.Toggle()
		elseif cmd == "inspect" or cmd == "tabard" or cmd == "heraldry" then
			ns.UI.SelectTab("heraldry")
		elseif cmd == "sound" then
			ns.db.sound = not ns.db.sound
			ns.Print("sound = " .. tostring(ns.db.sound))
		elseif cmd == "patrol" then
			ns.Inspect.SetPatrol(not ns.Inspect.IsPatrolling())
		elseif cmd == "mark" then
			ns.Inspect.MarkTarget(rest)
		elseif cmd == "map" then
			ns.Map.SetEnabled(not ns.db.showMap)
		elseif cmd == "throne" or cmd == "trono" then
			if ns.King.Visible and ns.King.Visible() then
				if rest == "letter" or rest == "carta" then ns.King.Show("letter") end
				ns.UI.SelectTab("throne")
			else
				ns.Print(ns.L.THRONE_ONLY_KING)
			end
		elseif cmd == "vox" then
			local word = rest:lower()
			if word == "on" or word == "off" then
				ns.Vox.SetOff(word == "off")
			elseif ns.Vox.Visible and ns.Vox.Visible() then
				ns.UI.SelectTab("vox")
			else
				ns.Print(L.HELP_VOX)
			end
		elseif cmd == "realm" or cmd == "tree" or cmd == "layers" then
			if ns.Views.CloseChat then ns.Views.CloseChat() end
			ns.UI.SelectTab("realm")
		elseif cmd == "decrees" then
			ns.UI.SelectTab("decrees")
		elseif cmd == "arms" or cmd == "muster" then
			local kind = cmd == "arms" and "ARMS" or "MUSTER"
			if rest == "test" or not ns.Roster.IsOfficer() then ns.Decree.Preview(kind) else ns.Decree.Send(kind, rest) end
		elseif cmd == "mates" then
			ns.Positions.SetEnabled(not ns.db.showMates)
		elseif cmd == "share" then
			ns.Positions.SetSharing(not ns.db.sharePosition)
		elseif cmd == "council" then
			-- The High Council's list (the author's or the King's character): add, remove, list.
			local verb, arg = rest:match("^(%S*)%s*(.-)$")
			verb = (verb or ""):lower()
			if verb == "help" then
				local a = arg:lower()
				if a == "on" or a == "off" then ns.Workshop.SetCouncilHelp(a == "on")
				else ns.Print(ns.db.councilHelp and L.COUNCIL_HELP_ON or L.COUNCIL_HELP_OFF) end
			elseif verb == "icon" then ns.Workshop.ShowIconPicker() -- a councillor's own icon (0.9.8)
			else ns.Workshop.EditCouncil(verb) end
		elseif cmd == "helpme" then
			if rest ~= "" then ns.Workshop.AskCouncil(rest) else ns.ShowDialog("OLYMPUS_COUNCIL_ASK") end
		elseif cmd == "issuereporter" then
			-- Blizzard's Issue Reporter box (beta and PTR clients): hidden at every login, or not.
			local how = rest:lower()
			local hide = (how == "hide" or how == "off") and true or ((how == "show" or how == "on") and false or not ns.UI.IssueReporterHidden())
			ns.UI.SetIssueReporterHidden(hide)
		elseif cmd == "inspection" then
			-- Taking part in the King's Royal Inspection (a patrol of 2 minutes that reports to him).
			local on = rest:lower()
			if on == "on" or on == "off" then ns.db.royalInspection = on == "on" end
			ns.Print(ns.db.royalInspection == false and L.INSPECTION_OPT_OFF or L.INSPECTION_OPT_ON)
		elseif cmd == "treasurer" then
			-- The Treasurer's yes to sharing his book and the guild bank (Treasury.lua).
			local on = rest:lower()
			if on == "on" or on == "off" then
				ns.Treasury.SetConsent(on == "on")
			else
				local v = ns.Treasury.Consent()
				ns.Print(v == true and L.TREASURER_SHARE_ON or L.TREASURER_SHARE_OFF)
			end
		elseif cmd == "rollcall" then
			-- The author's roll calls and update notices (Workshop.lua): answered, or not.
			local on = rest:lower()
			if on == "on" or on == "off" then
				ns.Workshop.SetAnswers(on == "on")
			else
				ns.Print(ns.Workshop.Answers() and L.ROLLCALL_ON or L.ROLLCALL_OFF)
			end
		elseif cmd == "location" then
			-- Sharing zone and layer on the Olympus channel (Layers.Sharing); alone, says which.
			local on = rest:lower()
			if on == "on" or on == "off" then
				ns.Layers.SetSharing(on == "on")
			else
				ns.Print(ns.Layers.Sharing() and L.LOCATION_ON or L.LOCATION_OFF)
			end
		elseif cmd == "officer" then
			ns.Print(ns.L.OFFICER_FIXED)
		elseif cmd == "demo" then
			ns.Print(ns.L.DEMO_REMOVED)
		elseif cmd == "bug" then
			ns.UI.ShowBugReport()
		elseif cmd == "status" then
			for line in ns.StatusText():gmatch("[^\n]+") do print("  " .. line) end
		elseif cmd == "key" then
			ns.Comm.SetRealmKey(rest)
		elseif cmd == "block" then
			if rest ~= "" then
				-- Stored as the sender reaches Comm (ns.FullName(ns.Normal(name)), the realm's
				-- spaces and hyphens out), whatever form the player typed.
				local name = ns.Normal(rest)
				name = name:gsub("%-([^%-]+)$", function(realm) return "-" .. realm:gsub("[%s%-]", "") end)
				local key = ns.FullName(name):lower()
				ns.db.blocked[key] = true
				ns.Print("blocked " .. key)
			end
		elseif cmd == "layer" then
			ns.PrintLayer()
		elseif cmd == "hop" then
			ns.Hop.AskKing()
		elseif cmd == "layerhelp" or cmd == "layerauto" then
			local on = rest:lower()
			if on ~= "on" and on ~= "off" then
				ns.Print(cmd == "layerhelp" and L.HELP_LAYERHELP or L.HELP_LAYERAUTO)
			elseif cmd == "layerhelp" then
				ns.Hop.SetHelp(on == "on")
			else
				ns.Hop.SetAuto(on == "on")
			end
		elseif cmd == "minimap" then
			ns.db.hideMinimap = not ns.db.hideMinimap
			ns.UI.UpdateMinimapButton()
		elseif cmd == "debug" then
			ns.db.debug = not ns.db.debug
			ns.Print("debug = " .. tostring(ns.db.debug))
		elseif cmd == "reset" then
			wipe(ns.rdb.guilds)
			wipe(ns.Data.Seen())
			ns.Who.Reset()
			ns.Fire("DATA_CHANGED")
			ns.Print("cache cleared")
		elseif cmd == "error" then
			error("test error from /oly error")   -- to check that bug capture works
		elseif cmd == "all" or cmd == "captains" or cmd == "lords" then
			ns.Channels.Send(ns.Channels.TierForWord(cmd), rest)
		elseif cmd == "mute" then
			ns.Channels.ToggleMute(rest)
		elseif cmd == "chatwindow" then
			ns.Channels.ChooseWindow(rest)
		else
			Help()
		end
	end)
end
