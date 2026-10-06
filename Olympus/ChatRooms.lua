local ADDON, ns = ...
local L = ns.L

-- Logical rooms on the Chat page. They are deliberately not extra Channels tiers:
-- [Olympus], [Captains] and [Lords] keep their public wire, consent, chat-window routing and
-- Chattynator integration unchanged. These rooms use a versioned whole message of their own:
--
--   M2~1~<room>~<id>~<class>~<guild>~<text>
--
-- Guild uses the game's native guild chat. Race and class are open topic rooms on the logged Olympus lane; choosing
-- one never publishes the character's race/class. The local client reads its own race/class only
-- to distinguish a member from an outsider request. Restricted rooms go as one logged
-- whisper to each recipient from the signed authority lists. There is no broadcast fallback for
-- a private audience, and every queued whisper rechecks both ends immediately before it leaves.

local Rooms = {}
ns.ChatRooms = Rooms

Rooms.HISTORY = 100
Rooms.ROOMS_MAX = 12
Rooms.TEXT_MAX = 150
Rooms.SEND_GAP = 1.5
Rooms.PER_MINUTE = 6
Rooms.FLOOD = 60
Rooms.REQUEST_WAIT = 30 * 60

local RACES = {
	{ id = "race:1", label = "Human", race = 1 },
	{ id = "race:2", label = "Orc", race = 2 },
	{ id = "race:3", label = "Dwarf", race = 3 },
	{ id = "race:4", label = "Night Elf", race = 4 },
	{ id = "race:5", label = "Undead", race = 5 },
	{ id = "race:6", label = "Tauren", race = 6 },
	{ id = "race:7", label = "Gnome", race = 7 },
	{ id = "race:8", label = "Troll", race = 8 },
}
local CLASSES = {
	{ id = "class:WA", file = "WARRIOR", label = "Warrior" },
	{ id = "class:PA", file = "PALADIN", label = "Paladin" },
	{ id = "class:HU", file = "HUNTER", label = "Hunter" },
	{ id = "class:RO", file = "ROGUE", label = "Rogue" },
	{ id = "class:PR", file = "PRIEST", label = "Priest" },
	{ id = "class:SH", file = "SHAMAN", label = "Shaman" },
	{ id = "class:MA", file = "MAGE", label = "Mage" },
	{ id = "class:WL", file = "WARLOCK", label = "Warlock" },
	{ id = "class:DR", file = "DRUID", label = "Druid" },
}

-- The signed titles list remains the authority. Aliases only normalize labels that have existed
-- in that list; they never grant somebody absent from it a room.
local DEPARTMENTS = {
	{ id = "dept:treasury", label = "Federal Treasury", aliases = { "federal treasury", "treasury" } },
	{ id = "dept:war", label = "Department of War", aliases = { "department of war", "war" } },
	{ id = "dept:citizenry", label = "Association of Artisanry", aliases = { "association of artisanry", "association of citizenry", "artisanship" } },
	{ id = "dept:heritage", label = "Department of Heritage", aliases = { "department of heritage", "heritage", "heraldry", "outreach" } },
	{ id = "dept:justice", label = "Council of Justice", aliases = { "council of justice", "justice" } },
	{ id = "dept:church", label = "The Missionary Church of Olympus", aliases = { "the missionary church of olympus" } },
}
local DEPT_BY_NAME, DEPT_BY_ID = {}, {}
for _, d in ipairs(DEPARTMENTS) do
	DEPT_BY_ID[d.id] = d
	for _, name in ipairs(d.aliases) do DEPT_BY_NAME[name] = d end
end

local states = {}          -- room -> bounded session history and receive budgets
local subscriptions = {}   -- explicitly selected race/class topic rooms
local nextId = math.random and math.random(0, 9999) or 0
local lastSend = -math.huge
local sentTimes = {}
local receiveBuckets, receiveSeen, receiveMine = {}, {}, {}
local stats = { sent = 0, shown = 0, dropped = {} }
local providers = {}       -- private rooms owned by later modules (1.2: crafting requests)
local held                 -- dynamic-room key -> when Rooms.OpenMatter pinned it (saved; loaded at first use)
local writing = {}         -- matter key -> a look at the Chat page's box is coming (Rooms.OpenMatter)
-- 1.1.6: restricted M2 rooms whose audience a later module decides (Rooms.RegisterAudience: the
-- Church's). id -> { label, CanAccess(name), Recipients() }; the transport stays this file's.
local audiences, audienceOrder = {}, {}

local function Now() return GetTime and GetTime() or ns.Now() end
local function Lower(s) return tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Lower(a) == Lower(b) end
local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end
local function IsMe(name)
	return ns.Channels and ns.Channels.IsMe and ns.Channels.IsMe(name) == true
end

local function RaceLabel(e)
	local fn = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
	if type(fn) == "function" then
		local ok, info = pcall(fn, e.race)
		if ok and type(info) == "table" and type(info.raceName) == "string" and info.raceName ~= "" then return info.raceName end
	end
	local names = rawget(L, "ARENA_RACE_NAMES")
	return type(names) == "table" and names[e.race] or e.label
end

local function ClassLabel(e)
	local names = LOCALIZED_CLASS_NAMES_MALE
	local name = type(names) == "table" and names[e.file]
	return type(name) == "string" and name ~= "" and name or e.label
end

local function Topic(id)
	for _, e in ipairs(RACES) do
		if e.id == id then return { id = id, kind = "race", label = RaceLabel(e), scope = "topic", race = e.race, raceName = e.label } end
	end
	for _, e in ipairs(CLASSES) do
		if e.id == id then return { id = id, kind = "class", label = ClassLabel(e), scope = "topic", class = id:sub(7), classFile = e.file } end
	end
end

local function DepartmentFor(name)
	local title = ns.CouncilTitle and ns.CouncilTitle(name)
	return title and type(title.dept) == "string" and DEPT_BY_NAME[Lower(title.dept)] or nil
end

local function IsSecretariat(name)
	return (ns.IsKingCharacter and ns.IsKingCharacter(name) == true)
		or (ns.IsSteward and ns.IsSteward(name) == true)
end

local ROLE_ROOMS = {
	{ id = "masters", label = "Guild Masters", preview = "gm" },
	{ id = "treasurers", label = "Treasury correspondents", preview = "treasurer" },
	{ id = "departments", label = "All departments", preview = "correspondent" },
	{ id = "centurions", label = "Guild Centurions", preview = "officer" },
	{ id = "allcenturions", label = "All Centurions", preview = "officer" },
}
local ROLE_BY_ID = {}
for _, room in ipairs(ROLE_ROOMS) do ROLE_BY_ID[room.id] = room end

local function FederalTreasurer(name)
	local T = ns.Treasury
	return T and T.TreasurerPin and T.TreasurerPin(name) == 1 or false
end

local function Guilds()
	local out, seen = {}, {}
	local function Add(guild)
		if type(guild) == "string" and ns.IsFederation(guild) and not seen[Lower(guild)] then
			seen[Lower(guild)], out[#out + 1] = true, guild
		end
	end
	Add(GetGuildInfo and GetGuildInfo("player"))
	if ns.KingGuildName then Add(ns.KingGuildName()) end
	for guild in pairs(ns.rdb and ns.rdb.guilds or {}) do Add(guild) end
	table.sort(out)
	return out
end

local function Rank(name, guild)
	if guild == (GetGuildInfo and GetGuildInfo("player")) then
		local R = ns.Roster
		if not R or not R.Fresh or not R.Fresh() then return nil end
	end
	local D = ns.Data
	return D and D.AuthorizedRank and D.AuthorizedRank(ns.FullName(name), guild) or nil
end

-- Nomination lists are received from proven guild masters, never from a nominee's own claim.
-- Recheck their current authority at every read/send, including the signed enforcement boundary.
local function Nomination(name, guild)
	local N = ns.Nominees
	if not N or not N.ListOf or not N.RoleOf then return nil end
	local list = N.ListOf(guild)
	if not list or type(list.by) ~= "string" then return nil end
	if ns.IsKingGuild(guild) then
		if not ((ns.IsKingCharacter and ns.IsKingCharacter(list.by)) or ns.IsHighCouncillor(list.by)) then return nil end
	elseif Rank(list.by, guild) ~= 0 or not N.Proven or N.Proven(list.by, guild) ~= true then return nil end
	local own = GetGuildInfo and GetGuildInfo("player")
	if own == guild then
		local R = ns.Roster
		if not R or not R.Fresh or not R.Fresh() or not R.RankOf or R.RankOf(ns.FullName(name)) == nil then return nil end
	end
	return N.RoleOf(name, guild)
end

local function Correspondent(name, department)
	for _, guild in ipairs(Guilds()) do
		local role, dept = Nomination(name, guild)
		if role == "correspondent" and (not department or DEPT_BY_NAME[Lower(dept)] == department) then return true end
	end
	return false
end

local function Centurion(name, guild)
	local rank = Rank(name, guild)
	return rank ~= nil and rank > 0 and rank <= ns.CAPTAIN_RANK
		or Nomination(name, guild) == "centurion"
end

local function RoleAccess(id, name)
	if id == "treasurers" then return FederalTreasurer(name) or DepartmentFor(name) == DEPT_BY_ID["dept:treasury"] or Correspondent(name, DEPT_BY_ID["dept:treasury"]) end
	if id == "departments" then return DepartmentFor(name) ~= nil or Correspondent(name) end
	if id == "centurions" then
		local guild = GetGuildInfo and GetGuildInfo("player")
		return guild ~= nil and ns.IsFederation(guild) and Centurion(name, guild) or false
	end
	for _, guild in ipairs(Guilds()) do
		if id == "masters" and Rank(name, guild) == 0 or id == "allcenturions" and Centurion(name, guild) then return true end
	end
	return false
end

local function AudienceLabel(a)
	local ok, label = pcall(function() return type(a.label) == "function" and a.label() or a.label end)
	return ok and type(label) == "string" and label or "?"
end

local function Restricted(id)
	local roleRoom = ROLE_BY_ID[id]
	if roleRoom then return { id = id, kind = "role", label = roleRoom.label, scope = "restricted" } end
	local a = audiences[id]
	if a then return { id = id, kind = id, label = AudienceLabel(a), scope = "restricted", audience = true } end
	if id == "council" then return { id = id, kind = "authority", label = L.CHATROOM_COUNCIL or "Council", scope = "restricted" } end
	if id == "secretariat" then return { id = id, kind = "authority", label = L.CHATROOM_SECRETARIAT or "Secretariat", scope = "restricted" } end
	local d = DEPT_BY_ID[id]
	return d and { id = id, kind = "department", label = d.label, scope = "restricted", department = d } or nil
end

-- The provider whose private room this is, and its description.
local function ProviderFor(id)
	if type(id) ~= "string" then return nil end
	for _, p in ipairs(providers) do
		local ok, info = pcall(p.Info, id)
		if ok and type(info) == "table" then return p, info end
	end
end

-- A later-loaded feature can own private logical rooms without teaching the chat window its
-- transport (1.2: CraftRequests.lua). The provider stays the only authority for its rooms'
-- membership, history and delivery; nothing of a provider room goes over M2.
function Rooms.RegisterProvider(p)
	if type(p) ~= "table" or type(p.Info) ~= "function" or type(p.CanAccess) ~= "function"
		or type(p.History) ~= "function" or type(p.Send) ~= "function" then return false end
	for _, old in ipairs(providers) do if old == p then return true end end
	providers[#providers + 1] = p
	return true
end

-- 1.1.6: a restricted room over M2 whose audience another module keeps (Church.lua). spec.CanAccess(name)
-- says who may read and send; spec.Recipients() who is reached (each still checked by CanAccess,
-- this character left out). Never one of the ids above or a provider's. False when refused.
function Rooms.RegisterAudience(id, spec)
	if type(id) ~= "string" or not id:match("^%l+$") or #id > 16 or type(spec) ~= "table"
		or type(spec.CanAccess) ~= "function" or type(spec.Recipients) ~= "function" then return false end
	if id == "guild" or id == "council" or id == "secretariat" or ROLE_BY_ID[id] or DEPT_BY_ID[id] or Topic(id) or ProviderFor(id) or audiences[id] then return false end
	audiences[id] = spec
	audienceOrder[#audienceOrder + 1] = id
	return true
end

function Rooms.Info(id)
	local _, external = ProviderFor(id)
	if external then return external end
	if id == "guild" then return { id = id, kind = "guild", label = L.CHATROOM_GUILD or "Guild", scope = "guild" } end
	return Topic(id) or Restricted(id)
end

function Rooms.CanAccess(id, name)
	local provider = ProviderFor(id)
	if provider then return provider.CanAccess(id, name or ns.me) == true end
	local info = Rooms.Info(id)
	if not info then return false end
	name = name or ns.me
	if info.scope == "guild" or info.scope == "topic" then return ns.IsMember() == true end
	if id == "council" then return ns.IsHighCouncillor(name) == true or (ns.IsKingCharacter and ns.IsKingCharacter(name) == true) or FederalTreasurer(name) end
	if id == "secretariat" then return IsSecretariat(name) end
	if ROLE_BY_ID[id] then return RoleAccess(id, name) end
	if audiences[id] then
		local ok, yes = pcall(audiences[id].CanAccess, name)
		return ok and yes == true
	end
	return info.department ~= nil and (DepartmentFor(name) == info.department or Correspondent(name, info.department))
end

local function Choices()
	if not ns.db then return nil end
	if type(ns.db.chatRoomChoices) ~= "table" then ns.db.chatRoomChoices = {} end
	return ns.db.chatRoomChoices
end

function Rooms.Selected(kind)
	local c = Choices()
	local id = c and c[kind]
	if (kind == "race" or kind == "class") and Rooms.Info(id) and Rooms.CanAccess(id) then return id end
	return nil
end

local function AuthorityOptions()
	local out = {}
	if Rooms.CanAccess("council") then out[#out + 1] = Rooms.Info("council") end
	if Rooms.CanAccess("secretariat") then out[#out + 1] = Rooms.Info("secretariat") end
	return out
end

local function DepartmentOptions()
	local out = {}
	for _, d in ipairs(DEPARTMENTS) do if Rooms.CanAccess(d.id) then out[#out + 1] = Rooms.Info(d.id) end end
	return out
end

local function PreviewRole()
	local V = ns.ViewAs
	if type(V) == "table" and type(V.Previewing) == "function" and V.Previewing()
		and type(V.Role) == "function" then return V.Role() end
end

-- This menu is presentation only. A preview names a role's possible rooms, never a person's
-- private history; it cannot select one, even when the author's real character has access.
function Rooms.PreviewOnly(id)
	local info = Rooms.Info(id)
	return info ~= nil and info.scope == "restricted" and PreviewRole() ~= nil
end

local function RoleOptions()
	local role, out = PreviewRole(), {}
	local function Add(id, preview)
		local info = Rooms.Info(id)
		if info and (role and preview or not role and Rooms.CanAccess(id)) then
			info.disabled = role ~= nil
			out[#out + 1] = info
		end
	end
	local council = role == "king" or role == "councillor"
	Add("council", council or role == "treasurer")
	Add("secretariat", role == "king")
	for _, d in ipairs(DEPARTMENTS) do Add(d.id, council or role == "correspondent" or role == "treasurer" and d.id == "dept:treasury") end
	for _, room in ipairs(ROLE_ROOMS) do Add(room.id, role == room.preview or room.id == "departments" and council) end
	for _, aid in ipairs(audienceOrder) do Add(aid, aid == "church" and council) end
	return out
end

function Rooms.Options(kind)
	local out = {}
	if kind == "race" then
		for _, e in ipairs(RACES) do out[#out + 1] = Rooms.Info(e.id) end
	elseif kind == "class" then
		for _, e in ipairs(CLASSES) do out[#out + 1] = Rooms.Info(e.id) end
	elseif kind == "authority" then
		out = AuthorityOptions()
	elseif kind == "department" then
		out = DepartmentOptions()
	elseif kind == "role" then
		out = RoleOptions()
	end
	-- Later guild-local features own their dynamic audience and revalidate every entry.
	for _, provider in ipairs(providers) do
		if type(provider.Options) == "function" then
			local ok, options = pcall(provider.Options, kind)
			for _, info in ipairs(ok and type(options) == "table" and options or {}) do
				if type(info) == "table" and type(info.id) == "string" and not Rooms.PreviewOnly(info.id)
					and Rooms.CanAccess(info.id) then out[#out + 1] = info end
			end
		end
	end
	return out
end

-- The compact row's logical destinations after Olympus. Race/class remain unchosen until
-- the player opens their dropdown: neither character API is consulted to pick one.
function Rooms.Tabs()
	local out = { { kind = "guild", id = "guild", label = L.CHATROOM_GUILD or "Guild" } }
	for _, kind in ipairs({ "race", "class" }) do
		local id = Rooms.Selected(kind)
		local info = id and Rooms.Info(id)
		out[#out + 1] = { kind = kind, id = id, label = info and info.label or (kind == "race" and (L.CHATROOM_RACE or "Race") or (L.CHATROOM_CLASS or "Class")), dropdown = true }
	end
	if #Rooms.Options("role") > 0 then
		out[#out + 1] = { kind = "role", label = rawget(L, "CHATROOM_ROLES") or "Roles", dropdown = true }
	end
	for _, p in ipairs(providers) do
		if type(p.Tabs) == "function" then
			local ok, tabs = pcall(p.Tabs)
			if ok and type(tabs) == "table" then for _, tab in ipairs(tabs) do out[#out + 1] = tab end end
		end
	end
	return out
end

function Rooms.Select(id)
	if Rooms.PreviewOnly(id) then return false, "preview" end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.CanAccess(id) or (type(provider.Select) == "function" and provider.Select(id) == false) then return false, "access" end
		ns.Fire("CHAT_ROOM_SELECTED", id)
		return true
	end
	local info = Rooms.Info(id)
	if not info or not Rooms.CanAccess(id) then return false, "access" end
	if info.kind == "race" or info.kind == "class" then
		local c = Choices()
		local old = c and c[info.kind]
		if old and old ~= id then subscriptions[old] = nil end
		if c then c[info.kind] = id end
		subscriptions[id] = true
	end
	ns.Fire("CHAT_ROOM_SELECTED", id)
	return true
end

local function Accepts(id)
	local provider = ProviderFor(id)
	if provider then return Rooms.CanAccess(id) and (type(provider.IsOpen) ~= "function" or provider.IsOpen(id) == true) end
	local info = Rooms.Info(id)
	if not info or not Rooms.CanAccess(id) then return false end
	if info.kind == "race" or info.kind == "class" then return subscriptions[id] == true end
	return true
end
Rooms.IsOpen = Accepts

-- The rooms' consent; a provider room (named by id) answers for itself: its two parties chose it.
function Rooms.ChatOn(id)
	local provider = ProviderFor(id)
	if provider then return type(provider.ChatOn) ~= "function" or provider.ChatOn(id) == true end
	return ns.db ~= nil and ns.db.chatRooms == true
end
function Rooms.SetChatOn(on)
	if not ns.db then return false end
	ns.db.chatRooms = on and true or false
	if not on and ns.Comm and ns.Comm.Cancel then ns.Comm.Cancel(Rooms) end
	ns.Print(on and (L.CHATROOMS_ON or "Chat rooms on.") or (L.CHATROOMS_OFF_MSG or "Chat rooms off."))
	ns.Fire("CHAT_ROOMS_CHANGED")
	return true
end

local function State(id, make)
	local r = states[id]
	if r or not make then return r end
	local count = 0
	for _ in pairs(states) do count = count + 1 end
	if count >= Rooms.ROOMS_MAX then
		local oldest, at
		for key, one in pairs(states) do
			if key ~= "guild" and (not at or (one.used or 0) < at) then oldest, at = key, one.used or 0 end
		end
		if oldest then states[oldest] = nil end
	end
	r = { id = id, lines = {}, recent = {}, used = Now() }
	states[id] = r
	return r
end

-- A topic's membership is a local presentation and sending decision. It is never added to M2:
-- only the neutral RQ marker says that a line is an outsider request. This keeps the existing
-- privacy boundary (no new race/class fact on the wire) while letting updated receivers enforce
-- the request cadence as a defence in depth.
local function LocalTopicMember(info)
	if not info or info.scope ~= "topic" then return true end
	if info.kind == "class" then
		if type(UnitClass) ~= "function" then return nil end
		local ok, _, file = pcall(UnitClass, "player")
		if not ok or type(file) ~= "string" or file == "" then return nil end
		local code = ns.Roster and ns.Roster.ClassCode and ns.Roster.ClassCode(file) or file
		return code == info.class
	end
	if type(UnitRace) ~= "function" then return nil end
	local ok, _, _, race = pcall(UnitRace, "player")
	if not ok or tonumber(race) == nil then return nil end
	return tonumber(race) == info.race
end

local function RequestExempt()
	if ns.IsKingCharacter and ns.IsKingCharacter(ns.me) == true then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(ns.me) == true then return true end
	local W = ns.Workshop
	return type(W) == "table" and type(W.IsAuthor) == "function" and W.IsAuthor() == true or false
end

local function RequestRecords()
	if not ns.db then return nil end
	if type(ns.db.chatRoomRequests) ~= "table" then ns.db.chatRoomRequests = {} end
	return ns.db.chatRoomRequests
end

local function RequestKey(id)
	return Lower(ns.FullName(ns.me or "")) .. "|" .. tostring(id or "")
end

local pendingRequests = {} -- room -> queued request; prevents a second warning/send racing it
local remoteRequests = {}  -- sender|room -> session-only receiver cadence

function Rooms.RequestStatus(id, at)
	local info = Rooms.Info(id)
	if not info or info.scope ~= "topic" then return { member = true, canSend = true } end
	local member = LocalTopicMember(info)
	local exempt = RequestExempt()
	if member == true or exempt then
		return { topic = true, member = member == true, exempt = exempt, canSend = true, info = info }
	end
	local records = RequestRecords()
	local record = records and records[RequestKey(id)]
	if type(record) ~= "table" then record = nil end
	at = tonumber(at) or ns.Now()
	local sentAt = record and tonumber(record.sentAt) or nil
	local replied = sentAt ~= nil and tonumber(record.replyAt) ~= nil and tonumber(record.replyAt) >= sentAt
	local wait = sentAt and math.max(0, Rooms.REQUEST_WAIT - math.max(0, at - sentAt)) or 0
	local pending = pendingRequests[id] ~= nil
	return {
		topic = true, member = false, unknown = member == nil or nil, outsider = member == false or nil,
		exempt = false, pending = pending, sentAt = sentAt, replied = replied,
		wait = wait, canSend = not pending and (sentAt == nil or (wait == 0 and replied)), info = info,
	}
end

function Rooms.StatusText(id, at)
	local s = Rooms.RequestStatus(id, at)
	if not s.topic or s.member or s.exempt then return nil end
	local label = s.info and s.info.label or "?"
	if s.unknown then return (L.CHATROOM_MEMBER_UNKNOWN or "Olympus could not verify whether you belong to %s; messages use the outsider-request rules."):format(label) end
	if s.pending then return (L.CHATROOM_REQUEST_PENDING or "You are not a member of %s. Your request is waiting to be sent."):format(label) end
	if s.canSend then return (L.CHATROOM_OUTSIDER_READY or "You are not a member of %s. You may send one request; a warning appears first."):format(label) end
	local minutes = math.max(1, math.ceil((s.wait or 0) / 60))
	if s.wait > 0 and not s.replied then
		return (L.CHATROOM_REQUEST_WAIT_BOTH or "You are not a member of %s. Wait %d min and for a member to reply before another request."):format(label, minutes)
	elseif s.wait > 0 then
		return (L.CHATROOM_REQUEST_WAIT_TIME or "You are not a member of %s. A member replied; wait %d min before another request."):format(label, minutes)
	end
	return (L.CHATROOM_REQUEST_WAIT_REPLY or "You are not a member of %s. Thirty minutes passed; wait for a member to reply before another request."):format(label)
end

local function Keep(id, e)
	local r = State(id, true)
	if not r then return end
	r.lines[#r.lines + 1] = e
	while #r.lines > Rooms.HISTORY do table.remove(r.lines, 1) end
	r.used = Now()
	ns.Fire("CHAT_ROOM_CHANGED", id)
	-- The window uses CHAT_ROOM_LINE for unread state. A local echo is already visible to
	-- its sender and must not make a background room look unread while the queued send
	-- completes.
	if not e.mine then ns.Fire("CHAT_ROOM_LINE", id, e.sender, e.text) end
end

-- The server's guild event includes guildmates without Olympus. Do not publish it to M2 or
-- echo a send optimistically: the native event is the sole source of the displayed line.
function Rooms.ReceiveGuild(text, sender)
	if not Rooms.ChatOn() or not Accepts("guild") then return false, "off" end
	if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return false, "secret" end
	if type(text) ~= "string" or text == "" or type(sender) ~= "string" or sender == "" then return false, "message" end
	local guild = GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false, "guild" end
	sender = ns.FullName(sender)
	nextId = (nextId + 1) % 10000
	local lineId, now = nextId, Now()
	local admitted, why = ns.Channels.Admit(sender, guild, text, now, {
		id = "guild:native:" .. lineId, chat = "guild", line = lineId, level = 0,
		buckets = receiveBuckets, seen = receiveSeen, mine = receiveMine, stats = stats, where = "guild",
	})
	if not admitted and why ~= "filtered" then return false, why end
	Keep("guild", { t = ns.Now(), sender = sender, guild = guild, text = text, id = lineId,
		mine = ns.Channels.IsMe(sender), hidden = why == "filtered" or nil, native = true })
	stats.shown = stats.shown + 1
	return true
end

function Rooms.History(id)
	if Rooms.PreviewOnly(id) then return {} end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.ChatOn(id) or not Accepts(id) then return {} end
		local ok, history = pcall(provider.History, id)
		return ok and type(history) == "table" and history or {}
	end
	if not Rooms.ChatOn() or not Accepts(id) then return {} end
	local r = State(id, false)
	if not r then return {} end
	r.used = Now()
	local M = ns.Moderation
	if id ~= "guild" and not (M and M.Any and M.Any()) then return r.lines end
	local out = {}
	for _, e in ipairs(r.lines) do
		if (id ~= "guild" or Same(e.guild, GetGuildInfo("player")))
			and not (M and M.Hides and M.Hides(e.sender, e.guild)) then out[#out + 1] = e end
	end
	return out
end

-- 1.1.6 (WatchChat.lua): the rooms this session kept lines of, and those lines themselves (a
-- moderator's deletion marks them; nothing else reads them this way).
function Rooms.KeptRooms()
	local out = {}
	for id in pairs(states) do out[#out + 1] = id end
	table.sort(out)
	return out
end
function Rooms.RawHistory(id)
	local r = State(id, false)
	return r and r.lines or {}
end

local function Members(id)
	local out, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		local full = ns.FullName(name)
		local key = full:lower()
		if not seen[key] and not IsMe(full) and Rooms.CanAccess(id, full) then seen[key], out[#out + 1] = true, full end
	end
	if id == "council" then
		if ns.KingCharacter then Add(ns.KingCharacter()) end
		if ns.TREASURER then Add(ns.TREASURER) end
		local c = ns.rdb and ns.rdb.council
		for key, display in pairs(type(c) == "table" and type(c.names) == "table" and c.names or {}) do
			-- Current signed lists keep lower-case name -> display name. Older in-memory fixtures used
			-- true for the value; the signed key is still the identity in that representation.
			Add(type(display) == "string" and display or key)
		end
	elseif id == "secretariat" then
		if ns.KingCharacter then Add(ns.KingCharacter()) end
		for _, name in ipairs(ns.Stewards and ns.Stewards() or {}) do Add(name) end
	elseif audiences[id] then
		local ok, list = pcall(audiences[id].Recipients)
		for _, name in ipairs(ok and type(list) == "table" and list or {}) do Add(name) end
	else
		-- Candidate discovery grants nothing: Add revalidates each recipient's current role.
		if ROLE_BY_ID[id] or DEPT_BY_ID[id] then
			if ns.TREASURER then Add(ns.TREASURER) end
			for _, member in ipairs(ns.Roster and ns.Roster.members or {}) do Add(member.name) end
			for _, guild in ipairs(Guilds()) do
				local g = ns.Data and ns.Data.Guild and ns.Data.Guild(guild)
				if g then
					if g.leader then Add(ns.FullName(g.leader, g.realm)) end
					for _, officer in ipairs(g.officers or {}) do Add(ns.FullName(officer.name, g.realm)) end
				end
				local N = ns.Nominees
				local list = N and N.ListOf and N.ListOf(guild)
				for _, entry in ipairs(list and list.entries or {}) do Add(entry.name) end
			end
		end
		local d = DEPT_BY_ID[id]
		local t = ns.CouncilTitles and ns.CouncilTitles()
		for _, dept in ipairs(t and t.depts or {}) do
			if (d and DEPT_BY_NAME[Lower(dept.name)] == d) or ROLE_BY_ID[id] then
				for _, m in ipairs(type(dept.members) == "table" and dept.members or {}) do Add(m.name) end
			end
		end
	end
	table.sort(out)
	return out
end
Rooms.Recipients = Members -- diagnostics/tests: the signed audience, with this character left out

local function CleanGuild(guild)
	return tostring(guild or ""):gsub("[~|%c]", ""):sub(1, 72)
end

local function Cut(text, max)
	if #text <= max then return text end
	local at = max
	while at > 0 do
		local b = text:byte(at + 1)
		if not b or b < 128 or b >= 192 then break end
		at = at - 1
	end
	return text:sub(1, at):gsub("%s+$", "")
end

local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

local function Recent(now)
	for i = #sentTimes, 1, -1 do if now - sentTimes[i] >= 60 then table.remove(sentTimes, i) end end
	return #sentTimes
end

local function Permit(id, audience, recipient, channel, guild)
	return function(_, key, dist, target)
		if not Rooms.ChatOn() or not Rooms.CanAccess(id) then return false, "revoked" end
		-- (1.1.6: a moderator's timeout that came while the line waited.)
		local WC = ns.WatchChat
		if WC and WC.SelfTimeout and WC.SelfTimeout() then return false, "timeout" end
		if audience == "topic" then
			if dist ~= "CHANNEL" or ns.Comm.ChannelName() ~= channel then return false, "moved" end
		elseif audience == "guild" then
			if dist ~= "GUILD" or not Same(GetGuildInfo("player"), guild) then return false, "guild" end
		elseif dist ~= "WHISPER" or not Same(target, recipient) or not Rooms.CanAccess(id, recipient) then
			return false, "revoked"
		end
		return true
	end
end

local function Echo(id, lineId, guild, class, text, request)
	receiveMine[id .. ":" .. lineId .. "#" .. text] = Now()
	Keep(id, { t = ns.Now(), sender = ns.me, guild = guild, class = class ~= "" and class ~= "RQ" and class or nil,
		text = text, id = lineId, mine = true, request = request or nil })
	stats.sent = stats.sent + 1
end

local function SendGuild(text) -- gp:roster-actions
	if not ns.Gate.Allowed("roster-actions") then return false, "gamepad" end
	local C = C_ChatInfo
	local send = type(C) == "table" and C.SendChatMessage or SendChatMessage
	if type(send) ~= "function" then return false, "api" end
	local ok, err = pcall(send, text, "GUILD")
	if not ok then
		if ns.Log then ns.Log("native guild chat send: %s", tostring(err)) end
		return false, "failed"
	end
	return true
end

-- Returns true once the complete, fixed audience was admitted to the queue. Completion callbacks
-- add the local echo only after a game send succeeded and expose a failed/partly failed send to
-- the Chat page without rerouting it.
local function Send(id, text, confirmed)
	if Rooms.PreviewOnly(id) then return false, "preview" end
	-- 1.1.6: a moderator's timeout (WatchChat.lua) covers every room, a provider's too.
	local WC = ns.WatchChat
	if WC and WC.RefuseSend and WC.RefuseSend() then return false, "timeout" end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.CanAccess(id) then ns.Print(L.CHATROOM_NO_ACCESS or "You cannot use this room.") return false, "access" end
		return provider.Send(id, text)
	end
	local info = Rooms.Info(id)
	if not info or not Rooms.CanAccess(id) then ns.Print(L.CHATROOM_NO_ACCESS or "You cannot use this room.") return false, "access" end
	if not Rooms.ChatOn() then
		ns.Print(ns.db and ns.db.chatRooms == nil and (L.CHATROOMS_OFF_UNANSWERED or "Choose chat-room consent first.")
			or (L.CHATROOMS_OFF or "Chat rooms are off."))
		if ns.db and ns.db.chatRooms == nil and ns.Consent and ns.Consent.Ask then ns.Consent.Ask("chatrooms") end
		return false, "off"
	end
	if ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff() then
		ns.Print(ns.Moderation.YouText(ns.Moderation.SelfOff()))
		return false, "netoff"
	end
	text = Cut(ns.Codec.SanitizeChat(text), Rooms.TEXT_MAX)
	if text == "" then return false, "empty" end
	if WC and WC.RefuseSevere and WC.RefuseSevere(text) then return false, "severe" end -- (1.1.6, WatchChat.SEVERE)
	local requestStatus = Rooms.RequestStatus(id)
	local request = info.scope == "topic" and not requestStatus.member and not requestStatus.exempt
	if request then
		if not requestStatus.canSend then
			ns.Print(Rooms.StatusText(id))
			return false, requestStatus.pending and "pending" or "request"
		end
		if confirmed ~= true then
			local data = { id = id, text = text, label = info.label }
			ns.ShowDialog("OLYMPUS_CHATROOM_REQUEST", info.label, Rooms.REQUEST_WAIT / 60, data)
			return false, "confirm"
		end
	end
	if Locked() then ns.Print(L.CHAN_LOCKDOWN) return false, "lockdown" end
	local now = Now()
	if now - lastSend < Rooms.SEND_GAP or Recent(now) >= Rooms.PER_MINUTE then
		ns.Print(L.CHAN_TOO_FAST)
		return false, "fast"
	end
	local guild = GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false, "guild" end
	if id == "guild" then
		local ok, why = SendGuild(text)
		if ok then lastSend = now; sentTimes[#sentTimes + 1] = now; stats.sent = stats.sent + 1 end
		return ok, ok and "ok" or why
	end
	-- Topic selection is deliberately not identity disclosure. Updated members keep the
	-- compatibility field empty; an outsider request uses only the neutral RQ marker. Old readers
	-- may still send a class code, which Parse accepts for their existing name-colour presentation.
	local class = request and "RQ" or ""
	nextId = (nextId + 1) % 10000
	local lineId = nextId
	local msg = ("M2~1~%s~%d~%s~%s~%s"):format(id, lineId, class, CleanGuild(guild), text)
	if #msg > 255 then return false, "size" end
	local recipients = info.scope == "restricted" and Members(id) or nil
	local count = recipients and #recipients or 1
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < count then ns.Print(L.CHAN_BUSY) return false, "busy" end
	if info.scope == "topic" and not ns.Comm.ChannelReady() then ns.Print(L.CHAN_NOT_READY) return false, "ready" end

	local channel = info.scope == "topic" and ns.Comm.ChannelName() or nil
	local guardKey = id .. "#" .. lineId
	local pending, successes, failures = count, 0, 0
	local finished = false
	if request then pendingRequests[id] = { key = guardKey, at = ns.Now() } end
	local function Done(ok, why)
		if finished then return end
		pending = pending - 1
		if ok then successes = successes + 1 else failures = failures + 1 end
		if pending > 0 then return end
		finished = true
		if request then
			pendingRequests[id] = nil
			if successes > 0 then
				local records = RequestRecords()
				if records then records[RequestKey(id)] = { sentAt = ns.Now() } end
				ns.Fire("CHAT_ROOM_CHANGED", id)
			end
		end
		if successes > 0 then Echo(id, lineId, guild, class, text, request) end
		if failures > 0 then ns.Fire("CHAT_ROOM_SEND_FAILED", id, why or "failed", text, successes) end
	end
	local accepted = true
	if info.scope == "restricted" then
		-- A room containing only this character is still a useful local history, and sends no bytes.
		if #recipients == 0 then pending = 0; Echo(id, lineId, guild, class, text, request)
		else
			for _, recipient in ipairs(recipients) do
				local ok = ns.Comm.Whisper(recipient, msg, nil, false, true, Done,
					{ owner = Rooms, key = guardKey, permit = Permit(id, info.scope, recipient, nil, guild) })
				if not ok then accepted = false end
			end
			-- Admission is all-or-none: preflight normally makes every whisper fit, but a
			-- synchronous refusal must not leave an admitted prefix aimed at only part of the
			-- audience. All jobs share this exact capability key; unrelated sends stay queued.
			if not accepted and ns.Comm.CancelQueued then ns.Comm.CancelQueued(Rooms, guardKey, "cancelled") end
		end
	else
		local dist = info.scope == "guild" and "GUILD" or "CHANNEL"
		accepted = ns.Comm.Send(dist, msg, nil, false, true, Done,
			{ owner = Rooms, key = guardKey, permit = Permit(id, info.scope, nil, channel, guild) })
	end
	if not accepted then
		if request then pendingRequests[id] = nil; ns.Fire("CHAT_ROOM_CHANGED", id) end
		if pending == count then finished = true end
		return false, "busy"
	end
	lastSend = now
	sentTimes[#sentTimes + 1] = now
	return true, "ok"
end

function Rooms.Send(id, text) return Send(id, text, false) end

-- The held outsider line is sent only after the explicit answer, and every gate is checked again.
function Rooms.ConfirmRequest(data, send)
	if type(data) ~= "table" or data.answered then return false, "answered" end
	data.answered = true
	if not send then
		ns.Print(L.CHATROOM_REQUEST_NOT_SENT or "Request not sent.")
		return false, "cancelled"
	end
	return Send(data.id, data.text, true)
end

if StaticPopupDialogs then
	StaticPopupDialogs["OLYMPUS_CHATROOM_REQUEST"] = {
		text = L.CHATROOM_REQUEST_WARNING or "You are not a member of %s. This is a request to its members. After sending it, you cannot send another until %d minutes have passed and a member replies. Send it?",
		button1 = SEND_LABEL or "Send",
		button2 = CANCEL or "Cancel",
		OnAccept = function(self, data) ns.SafeCall("chat room request", Rooms.ConfirmRequest, data or (self and self.data), true) end,
		OnCancel = function(self, data) ns.SafeCall("chat room request", Rooms.ConfirmRequest, data or (self and self.data), false) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

local function Flooded(r, now)
	for i = #r.recent, 1, -1 do if now - r.recent[i] >= 60 then table.remove(r.recent, i) end end
	if #r.recent >= Rooms.FLOOD then return true end
	r.recent[#r.recent + 1] = now
	return false
end

local function SameName(a, b)
	return type(a) == "string" and type(b) == "string" and Lower(ns.FullName(a)) == Lower(ns.FullName(b))
end

local function RaceMatches(info, value)
	if tonumber(value) ~= nil then return tonumber(value) == info.race end
	local key = Lower(value)
	return key ~= "" and (key == Lower(info.raceName) or key == Lower(info.label))
end

-- Server-provided roster and /who rows can corroborate a sender's membership without adding any
-- personal fact to M2. A legacy class field is retained only as a compatibility fallback; an
-- unknown sender stays unknown and a normal old-client line remains usable.
local function KnownTopicMember(info, sender, guild, class)
	local function From(row)
		if type(row) ~= "table" then return nil end
		if info.kind == "class" and type(row.class) == "string" and row.class ~= "" then return row.class == info.class end
		if info.kind == "race" and row.race ~= nil then return RaceMatches(info, row.race) end
		return nil
	end
	local R = ns.Roster
	for _, row in ipairs(type(R) == "table" and type(R.members) == "table" and R.members or {}) do
		if SameName(row.full or row.name, sender) then
			local known = From(row)
			if known ~= nil then return known end
		end
	end
	local W = ns.Who
	if type(W) == "table" and type(W.GuildSeen) == "function" then
		local ok, list = pcall(W.GuildSeen, guild)
		if ok then
			for _, row in ipairs(type(list) == "table" and list or {}) do
				if SameName(row.name, sender) then
					local known = From(row)
					if known ~= nil then return known end
				end
			end
		end
	end
	if info.kind == "class" and class ~= "" and class ~= "RQ" then return class == info.class end
	return nil
end

local function RemoteKey(id, sender) return Lower(ns.FullName(sender)) .. "|" .. id end

local function RemoteRequestAllowed(id, sender, now)
	local old = remoteRequests[RemoteKey(id, sender)]
	if not old then return true end
	return now - old.sentAt >= Rooms.REQUEST_WAIT and old.replyAt ~= nil and old.replyAt >= old.sentAt
end

local function MarkMemberReply(id, sender, member, request, now)
	if request or member == false or IsMe(sender) then return end
	local changed = false
	local records = RequestRecords()
	local own = records and records[RequestKey(id)]
	if type(own) == "table" and tonumber(own.sentAt) and not own.replyAt then
		own.replyAt = ns.Now()
		changed = true
	end
	for _, state in pairs(remoteRequests) do
		if state.id == id and state.sentAt <= now and not state.replyAt then state.replyAt = now end
	end
	if changed then ns.Fire("CHAT_ROOM_CHANGED", id) end
end

local function Parse(text)
	local version, id, lineId, class, guild, words = tostring(text or ""):match("^M2~([^~]+)~([^~]+)~([^~]+)~([^~]*)~([^~]*)~(.*)$")
	lineId = tonumber(lineId)
	if version ~= "1" or not Rooms.Info(id) or not lineId or lineId < 0 or lineId > 9999 or lineId ~= math.floor(lineId) then return nil end
	if class ~= "" and not class:match("^%u%u$") then return nil end
	if guild == "" or not ns.IsFederation(guild) then return nil end
	words = ns.Codec.SanitizeChat(words)
	if words == "" or #words > Rooms.TEXT_MAX then return nil end
	local request = class == "RQ"
	return id, lineId, request and "" or class, guild, words, request
end

function Rooms.Receive(dist, sender, text, now)
	if not Rooms.ChatOn() then return Drop("off") end
	local id, lineId, class, guild, words, markedRequest = Parse(text)
	if not id then return Drop("shape") end
	if ProviderFor(id) then return Drop("provider") end
	if not Accepts(id) then return Drop("unselected") end
	local info = Rooms.Info(id)
	local expected = info.scope == "guild" and "GUILD" or (info.scope == "topic" and "CHANNEL" or "WHISPER")
	if dist ~= expected then return Drop("lane") end
	sender = ns.FullName(sender)
	if info.scope == "restricted" and not Rooms.CanAccess(id, sender) then return Drop("audience") end
	if info.scope == "guild" then
		local own = GetGuildInfo("player")
		if not Same(guild, own) then return Drop("guild") end
		guild = own
	end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return Drop("unlogged") end
	now = now or Now()
	local member = info.scope == "topic" and KnownTopicMember(info, sender, guild, class) or true
	local request = info.scope == "topic" and (markedRequest or member == false) or false
	if request and not RemoteRequestAllowed(id, sender, now) then return Drop("request") end
	local admitted, why = ns.Channels.Admit(sender, guild, words, now, {
		id = id .. ":" .. lineId, chat = id, line = lineId, level = info.scope == "guild" and 0 or 1,
		buckets = receiveBuckets, seen = receiveSeen, mine = receiveMine, stats = stats, where = id,
	})
	if not admitted and why ~= "filtered" then return Drop(why) end
	local r = State(id, true)
	if Flooded(r, now) then return Drop("flood") end
	if request then remoteRequests[RemoteKey(id, sender)] = { id = id, sentAt = now } end
	MarkMemberReply(id, sender, member, request, now)
	Keep(id, { t = ns.Now(), sender = sender, guild = guild, class = class ~= "" and class or nil,
		text = words, id = lineId, hidden = why == "filtered" or nil, request = request or nil })
	stats.shown = stats.shown + 1
	return true, "ok"
end

function Rooms.Stats() return stats end

-- A signed authority replacement revokes visibility immediately and cancels queued restricted
-- whispers through their permits. Histories no longer authorized are discarded, not merely hidden.
function Rooms.RefreshAuthority()
	local changed = false
	for id in pairs(states) do
		local info = Rooms.Info(id)
		if info and info.scope == "restricted" and not Rooms.CanAccess(id) then states[id], changed = nil, true end
	end
	if changed then ns.Fire("CHAT_ROOMS_CHANGED") end
	return changed
end

function Rooms.Reset()
	states, subscriptions = {}, {}
	pendingRequests, remoteRequests = {}, {}
	nextId = 0
	lastSend, sentTimes = -math.huge, {}
	receiveBuckets, receiveSeen, receiveMine = {}, {}, {}
	stats = { sent = 0, shown = 0, dropped = {} }
	held, writing = nil, {}
	local c = Choices()
	for _, kind in ipairs({ "race", "class" }) do
		local id = c and c[kind]
		if Rooms.Info(id) and Rooms.CanAccess(id) then subscriptions[id] = true elseif c then c[kind] = nil end
	end
end

---------------------------------------------------------------------------
-- 1.2: one pattern for every pending conversation (the owner's decision)
---------------------------------------------------------------------------

-- A matter that may stay unresolved for a while (a match found in Bones or the Arena, a crafting
-- deal, any later transaction between players) gets a tab of its own on the Chat page. Olympus
-- opens that tab, brings the Olympus window to the front on it (over the other windows; a pop-up
-- of Olympus's above it whose work the matter ends gives way: CHAT_MATTER_SHOWN), and keeps it
-- pinned while the matter is open; the matter's own page (the match card, the request) reopens it
-- with this same call. Two kinds of room exist and this is their one door: a provider's private
-- room (m.room, Rooms.RegisterProvider: a crafting request, which keeps its own tab until its deal
-- is over and the player removes it) or one of the Arena's dynamic rooms (m.spec,
-- ChatWindow.OpenDynamicRoom's contract: a matched duel or Bones game, a fight, pinned here and
-- unpinned when the Arena says it ended). It only uses the Chat page's own room and tab calls: nothing here sends a word, draws a
-- tab or decides who belongs to a room (the room's owner does).
--   m = { room = <provider room id> } or { spec = <spec, or a function giving the current one> },
--   m.auto: Olympus opens it by itself, not a click, as every window that opens by itself: in an
--   instance or Busy it waits with the held alerts (ns.Alert, m.kind its sound's switch: its line on
--   the Decrees tab, and it opens when the player is back), in a fight until the fight's end
--   (ns.OutOfCombat), while the player writes in the Chat page's own box until he is done; each
--   matter on its own, and it opens then only while the matter is still open (m.live(), else the
--   spec's active, else the provider's room still open).
--   m.keep = false: a room the player only watches (a spectator's fight), not a matter of his:
--   its tab and the window in front, no pin.
Rooms.WRITING_WAIT = 2            -- seconds between two looks at the Chat page's box while he writes
Rooms.MATTER_PIN_KEEP = 7 * 86400 -- a pin of the door's, kept over reloads this long at most

local function MatterSpec(m)
	local spec = m.spec
	if type(spec) == "function" then
		local ok, current = pcall(spec)
		spec = ok and current or nil
	end
	return type(spec) == "table" and spec or nil
end

local function MatterLive(m, spec)
	if type(m.live) == "function" then
		local ok, live = pcall(m.live)
		return ok and live == true
	end
	if spec then return spec.active == true end
	return Accepts(m.room) == true
end

-- The matter as it is now: its current spec (a dynamic room's), and whether it is still open.
local function MatterNow(m)
	local spec = m.spec ~= nil and MatterSpec(m) or nil
	return spec, (m.spec == nil or spec ~= nil) and MatterLive(m, spec)
end

-- The pins made here, saved as the Chat page saves the pin itself (ChatWindow.PinDynamicRoom): a
-- room restored pinned after a reload is still the matter's, and its end takes the pin back; it
-- never passes for one of the player's own. Each with when it was made; one older than
-- MATTER_PIN_KEEP is forgotten (a match never outlives the session, and the Chat page drops a room
-- past its retention, pinned or not).
local function Held()
	if held then return held end
	local t = ns.db and type(ns.db.chatMatterPins) == "table" and ns.db.chatMatterPins or {}
	local now = ns.Now()
	for key, at in pairs(t) do
		if type(key) ~= "string" or type(at) ~= "number" or now - at > Rooms.MATTER_PIN_KEEP then t[key] = nil end
	end
	held = t
	if ns.db then ns.db.chatMatterPins = next(t) and t or nil end
	return held
end
local function Hold(key, on)
	local t = Held()
	t[key] = on and ns.Now() or nil
	if ns.db then ns.db.chatMatterPins = next(t) and t or nil end
end

-- The Chat page's pin call, made here. The page tells every pin and unpin (CHAT_DYNAMIC_PIN): one
-- that does not come from here is the player's own pin button, and the pin is his from then on.
local pinning = false
local function Pin(C, key, on)
	if type(C.PinDynamicRoom) ~= "function" then return false end
	pinning = true
	local ok, done = pcall(C.PinDynamicRoom, key, on)
	pinning = false
	return ok and done == true
end
function Rooms.PinChanged(key)
	if pinning or type(key) ~= "string" or not Held()[key] then return false end
	Hold(key, false)
	return true
end

-- The player writing in the Chat page's own box (it has the keyboard): a room selected under his
-- hands would take the rest of his line, the page swapping the box's words but not its focus.
local function Writing(C)
	local f = type(C.Frame) == "function" and C.Frame() or nil
	local eb = type(f) == "table" and f.input or nil
	if type(eb) ~= "table" or type(eb.HasFocus) ~= "function" then return false end
	local ok, focused = pcall(eb.HasFocus, eb)
	return ok and focused == true
end

-- The matter's tab shown on the Chat page, the Olympus window in front: that pane, else false and why.
local function Show(m, spec)
	local C = rawget(ns, "ChatWindow")
	if type(C) ~= "table" or C.missing then return false, "window" end
	local pane
	if spec then
		if type(C.OpenDynamicRoom) ~= "function" then return false, "window" end
		pane = C.OpenDynamicRoom(spec)
		-- (A pin the player made himself stays his: only a pin made here goes with the matter.)
		local room = pane and type(C.DynamicRoom) == "function" and C.DynamicRoom(spec.key) or nil
		if pane and spec.active == true and m.keep ~= false and not (room and room.pinned) and Pin(C, spec.key, true) then Hold(spec.key, true) end
	else
		if not Rooms.Info(m.room) or not Rooms.CanAccess(m.room) then return false, "access" end
		if type(C.Open) ~= "function" or type(C.SelectLogical) ~= "function" then return false, "window" end
		local frame = C.Open()
		if frame and C.SelectLogical(m.room) then pane = frame end
	end
	if not pane then return false, "window" end
	local host = type(C.Window) == "function" and C.Window() or nil
	if host and host.Raise then host:Raise() end
	-- (Raise orders the window among those of its own strata alone: a sheet of Olympus's above it
	-- whose work this matter ends, as the Find sheet whose search found the match, hears it here.)
	ns.Fire("CHAT_MATTER_SHOWN", spec and spec.key or m.room)
	return pane
end

-- Olympus's own opening (m.auto), each matter waiting on its own (its key): with the held alerts
-- (shown when the player is back, while the matter is still open), then out of combat, then while
-- the player writes, a look at his box every WRITING_WAIT seconds. Its sound is the matter's own
-- switch (m.kind: "craft" a crafting deal's, else "arena"), at most one with the caller's own just
-- before (ns.PlayAlert's 15 seconds).
local function Arrive(m, key, title)
	local wait = "room:" .. key
	local pane, why = nil, "combat"
	local Try
	local function Wait()
		return ns.Alert(m.kind == "craft" and "craft" or "arena", "soft", { what = L.CHATROOM_MATTER_HELD:format(title), key = wait,
			open = function() return select(2, MatterNow(m)) == true end,
			show = function() ns.OutOfCombat(wait, Try) end })
	end
	Try = function()
		local spec, live = MatterNow(m)
		if not live then why = "over" return end
		local C = rawget(ns, "ChatWindow")
		if type(C) == "table" and not C.missing and Writing(C) then
			why = "writing"
			if not writing[key] then
				writing[key] = true
				-- (Gone into an instance or Busy meanwhile, it waits with the held alerts after all.)
				ns.After(Rooms.WRITING_WAIT, "chat matter", function()
					writing[key] = nil
					if ns.Quiet() then Wait() else ns.OutOfCombat(wait, Try) end
				end)
			end
			return
		end
		pane, why = Show(m, spec)
	end
	if not Wait() then return false, "held" end
	if pane then return pane end
	return false, why
end

-- The Chat tab shown on the matter's room: that pane, else false and why ("held", "combat" and
-- "writing": Olympus's own opening waits; "over": it is no longer open).
function Rooms.OpenMatter(m)
	if type(m) ~= "table" then return false, "matter" end
	local spec = m.spec ~= nil and MatterSpec(m) or nil
	if m.spec ~= nil and not spec then return false, "expired" end
	if not m.auto then return Show(m, spec) end
	if not MatterLive(m, spec) then return false, "over" end
	local info = not spec and Rooms.Info(m.room) or nil
	local title = spec and spec.title or info and info.label or "?"
	return Arrive(m, spec and spec.key or m.room, ns.Codec.Plain(tostring(title)))
end

-- The Arena's word that a room's matter changed (ARENA_CHAT_ROOM, one spec): a pin OpenMatter made
-- goes once the matter is no longer open, so the ended room can be removed and expires as any other.
function Rooms.MatterChanged(spec)
	if type(spec) ~= "table" or type(spec.key) ~= "string" or not Held()[spec.key] or spec.active == true then return false end
	Hold(spec.key, false)
	local C = rawget(ns, "ChatWindow")
	if type(C) == "table" and not C.missing then Pin(C, spec.key, false) end
	return true
end

ns.Comm.Handle("M2", function(dist, sender, text)
	Rooms.Receive(dist, sender, text)
end)

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "chatrooms", label = "CONSENT_CHATROOMS", text = "CONSENT_CHATROOMS_TEXT",
		get = function() return ns.db and ns.db.chatRooms end,
		set = function(on) Rooms.SetChatOn(on) end,
	})
end

ns.On("DATA_CHANGED", Rooms.RefreshAuthority)
ns.RegisterEvent("CHAT_MSG_GUILD", Rooms.ReceiveGuild)
ns.On("INIT", Rooms.Reset)
ns.On("ARENA_CHAT_ROOM", function(spec) Rooms.MatterChanged(spec) end)
ns.On("CHAT_DYNAMIC_PIN", function(key) Rooms.PinChanged(key) end)
