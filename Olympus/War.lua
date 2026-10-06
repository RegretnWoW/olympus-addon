local ADDON, ns = ...
local L = ns.L

-- The guild War Room. Everything in this file belongs to the player's current guild and uses
-- GUILD, whose sender and guild are stamped by the game. A second, local roster check is required
-- for every officer mutation. There is deliberately no federal/cross-guild writer: the signed
-- role model for those offices does not exist yet.
--
-- Roles and LFG cards are a player's own declarations. Class is displayed as roster context but
-- never converted into a role. Operations, Centuries, posts and after-action records are officer
-- records. A relayed reload snapshot is visibly attributed to the officer who relayed it; it
-- cannot impersonate the original member, and therefore never contains another player's roles,
-- LFG card or RSVP.
--
-- WZ~1~R~<revision>~<roles>                                      own accepted roles
-- WZ~1~L~<id>~<revision>~<expiry>~<kind>~<roles>~<note>          own expiring LFG card
-- WZ~1~l~<id>~<revision>                                        lower own LFG card
-- WZ~1~O~<id>~<rev>~<kind>~<state>~<start>~<leader>~<slots>~<title>
-- WZ~1~V~<operation>~<rev>~<status>~<role>                      own RSVP
-- WZ~1~C~<id>~<rev>~<centurion>~<specialty>~<slots>~<name>
-- WZ~1~P~<century>~<rev>~<member>~<role-or-minus>               officer post
-- WZ~1~A~<id>~<rev>~<operation>~<century-or-minus>~<training>~<result>~<members>
-- WZ~1~Q~<nonce>[~<cursor>]                                      recovery request
-- WZ~1~S~<nonce>~<cursor>~<next cursor>~<total>^<officer record>^... bounded officer snapshot
-- Older clients ignore WZ. All fields are bounded and reject separators/control bytes.

local War = {}
ns.War = War

War.PROTOCOL = 1
War.LFG_MIN, War.LFG_MAX = 5 * 60, 4 * 60 * 60
War.ROLE_FRESH = 30 * 86400
War.ROLE_MAX, War.LFG_MAX_ROWS, War.RSVP_MAX = 500, 200, 200
War.REPLAY_KEEP = 180 * 86400
War.OP_MAX, War.CENTURY_MAX, War.POST_MAX, War.POST_TOTAL_MAX, War.AAR_MAX = 40, 20, 100, 200, 50
War.OP_KEEP, War.AAR_KEEP = 30 * 86400, 90 * 86400
War.SNAPSHOT_BYTES, War.SNAPSHOT_PAGES = 4800, 32
War.SNAPSHOT_RECORDS = War.OP_MAX + War.CENTURY_MAX + War.POST_TOTAL_MAX + War.AAR_MAX
War.ASK_GAP, War.ASK_WINDOW = 60, 120
War.INBOUND_MAX, War.INBOUND_WINDOW = 60, 60
War.WRITE_MAX, War.WRITE_WINDOW = 20, 60
War.LFG_RAISES, War.LFG_WINDOW = 4, 3600

local ROLES = { tank = true, healer = true, melee = true, ranged = true, support = true, caller = true, scout = true }
local ROLE_ORDER = { "tank", "healer", "melee", "ranged", "support", "caller", "scout" }
local ROLE_LABEL = {
	tank = "WAR_ROLE_TANK", healer = "WAR_ROLE_HEALER", melee = "WAR_ROLE_MELEE", ranged = "WAR_ROLE_RANGED",
	support = "WAR_ROLE_SUPPORT", caller = "WAR_ROLE_CALLER", scout = "WAR_ROLE_SCOUT",
}
local KINDS = { raid = true, pvp = true }
local STATES = { planned = true, active = true, complete = true, cancelled = true }
local STATE_ORDER = { planned = 1, active = 2, complete = 3 }
local SPECIALTIES = { raid = true, rated = true, openworld = true, scouting = true, logistics = true }
local RSVP = { confirmed = "C", standby = "S", declined = "X" }
local RSVP_CODE = { C = "confirmed", S = "standby", X = "declined" }

local function StateAdvances(old, new)
	if not STATES[old] or not STATES[new] then return false end
	if old == new then return true end
	if old == "complete" or old == "cancelled" then return false end
	if new == "cancelled" then return true end
	return (STATE_ORDER[new] or 0) > (STATE_ORDER[old] or 0)
end

local counter = 0
local opened, lastAsk = false, -math.huge
local asked = {}       -- nonce -> when our client asked; only those snapshots are accepted
local inbound = {}     -- sender -> recent message times
local writes = {}      -- local bucket -> recent action times
local lfgWrites = {}
local queryProgress = {} -- asker+nonce -> last strictly increasing recovery cursor and activity
local outgoingSnapshots = {} -- asker+nonce -> immutable officer records for one bounded recovery
local expanded = { operations = {}, centuries = {} }

War.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local function Now() return ns.Now() end
local function ServerNow()
	if type(GetServerTime) == "function" then
		local ok, n = pcall(GetServerTime)
		if ok and type(n) == "number" and n > 0 then return math.floor(n) end
	end
	return math.floor(Now())
end
local function B36(n) return ns.Codec.Base36(math.max(0, math.floor(tonumber(n) or 0))) or "0" end
local function UnB36(s)
	return type(s) == "string" and #s > 0 and #s <= 8 and s:match("^[0-9a-z]+$") and tonumber(s, 36) or nil
end
local function Grey(s) return "|cff9d9d9d" .. tostring(s) .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s) .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s) .. "|r" end
local function Red(s) return "|cffff4040" .. tostring(s) .. "|r" end
local function Provenance(e)
	local key = type(e) == "table" and e.direct and "WAR_RECORDED_BY" or "WAR_RELAYED_BY"
	return L[key]:format(ns.DisplayName(type(e) == "table" and (e.via or e.by) or "?"), ns.Ago(type(e) == "table" and e.rev or 0))
end

local function Clean(s, max)
	s = tostring(s or ""):gsub("[%c|~%^]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return ns.Cut(s, max)
end
-- Locally entered prose is normalized before it is sent. On the wire, accept only that canonical
-- representation: silently truncating or repairing a peer's field would make two versions store
-- different records and would turn a size limit into a lossy conversion rather than validation.
local function WireText(s, max, allowEmpty)
	if type(s) ~= "string" or #s > max or s ~= Clean(s, max) then return nil end
	if s == "" and not allowEmpty then return nil end
	return s
end
local function ValidID(s) return type(s) == "string" and #s >= 3 and #s <= 18 and s:match("^[0-9a-z]+$") ~= nil end
local function ValidName(s)
	return type(s) == "string" and #s >= 2 and #s <= 72 and not s:find("[~|%^%c]") and s:find("[%a\128-\255]") ~= nil
end
local function Full(s) return ValidName(s) and ns.FullName(ns.Normal(s)) or nil end

local function Guild()
	local guild = IsInGuild() and GetGuildInfo("player")
	return type(guild) == "string" and guild ~= "" and ns.IsFederation(guild) and guild or nil
end

local function NewStore(guild)
	return { guild = guild, roles = {}, lfg = {}, lfgFloor = {}, operations = {}, rsvp = {}, centuries = {}, posts = {}, after = {} }
end

local function Store(create)
	local guild = Guild()
	if not guild or not ns.rdb then return nil end
	if type(ns.rdb.warGuilds) ~= "table" then
		if not create then return nil end
		ns.rdb.warGuilds = {}
	end
	local key = ns.Fold(guild)
	local s = ns.rdb.warGuilds[key]
	if type(s) ~= "table" or s.guild ~= guild then
		if not create then return nil end
		s = NewStore(guild)
		ns.rdb.warGuilds[key] = s
	end
	for _, field in ipairs({ "roles", "lfg", "lfgFloor", "operations", "rsvp", "centuries", "posts", "after" }) do
		if type(s[field]) ~= "table" then s[field] = {} end
	end
	return s
end
War.Store = Store

local function Member(name)
	local full = Full(name)
	if not full then return nil end
	local want, display = ns.Fold(full), ns.Fold(ns.ShortName(full))
	for known in pairs(ns.Roster.byName or {}) do
		if ns.Fold(known) == want or ns.Fold(ns.ShortName(known)) == display then return known end
	end
	return nil
end
War.Member = Member

local function MemberExact(name)
	local full = Full(name)
	if not full then return nil end
	local want = ns.Fold(full)
	for known in pairs(ns.Roster.byName or {}) do if ns.Fold(known) == want then return known end end
	return nil
end
local function RecordedName(name)
	-- Recovery carries a bounded historical name, not current-membership authority. A current role,
	-- RSVP or readiness slot still needs that player's direct declaration; only direct officer writes
	-- use MemberExact below. This lets a departed attendee survive a reload without making them a member.
	if not ValidName(name) or name ~= Clean(name, 72) then return nil end
	return Full(name)
end
local function Rank(name)
	local full = MemberExact(name)
	return full and ns.Roster.RankOf(full) or nil
end
-- The signed War office is useful in its holder's own guild, never a cross-guild writer.
function War.IsWarCouncillor(name)
	local R = ns.Roster
	if not (R and R.Fresh and R.Fresh()) or not MemberExact(name) then return false end
	if not (ns.IsHighCouncillor and ns.IsHighCouncillor(name) == true) then return false end
	local title = ns.CouncilTitle and ns.CouncilTitle(name)
	return type(title) == "table" and title.dept == "Department of War"
end

local function Preview()
	local V = ns.ViewAs
	return V and not V.missing and V.Available and V.Available() == true and V.Role and V.Role() ~= "my"
end

local function Officer(name)
	local rank = Rank(name)
	if rank == nil then return false end
	if rank <= ns.CAPTAIN_RANK then return true end
	if War.IsWarCouncillor(name) then return true end
	local N = ns.Nominees
	return N and not N.missing and N.IsCorrespondent and N.IsCorrespondent(name, Guild(), "Department of War") == true or false
end
function War.IsOfficer()
	if ns.IsMember() ~= true then return false end
	if ns.Roster.IsOfficer() == true then return true end
	if War.IsWarCouncillor(ns.me) then return true end
	local N = ns.Nominees
	return N and not N.missing and N.IsCorrespondent and N.IsCorrespondent(ns.me, Guild(), "Department of War") == true or false
end

local function Rate(t, max, window, key, now)
	now = now or Now()
	local list = t[key]
	if type(list) ~= "table" then list = {}; t[key] = list end
	for i = #list, 1, -1 do if now - list[i] >= window then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now
	return true
end

local function ParseRoles(text, allowEmpty)
	local set = {}
	text = tostring(text or ""):lower():gsub("[,/]", " ")
	for role in text:gmatch("[%a]+") do if ROLES[role] then set[role] = true else return nil, role end end
	local out = {}
	for _, role in ipairs(ROLE_ORDER) do if set[role] then out[#out + 1] = role end end
	if #out == 0 and not allowEmpty then return nil, "empty" end
	return out
end
War.ParseRoles = ParseRoles

local function RoleCSV(roles)
	local out, seen = {}, {}
	for _, role in ipairs(type(roles) == "table" and roles or {}) do
		if ROLES[role] and not seen[role] then seen[role], out[#out + 1] = true, role end
	end
	table.sort(out, function(a, b)
		local ai, bi = 99, 99
		for i, r in ipairs(ROLE_ORDER) do if a == r then ai = i end; if b == r then bi = i end end
		return ai < bi
	end)
	return table.concat(out, ",")
end

local function ParseSlots(text)
	if type(text) ~= "string" or text == "" or #text > 96 then return nil end
	local slots = {}
	local count = 0
	for part in tostring(text or ""):gmatch("[^,]+") do
		local role, n = part:match("^([a-z]+):(%d+)$")
		n = tonumber(n)
		if not role or not ROLES[role] or not n or n < 1 or n > 40 or slots[role] then return nil end
		count = count + 1
		if count > #ROLE_ORDER then return nil end
		slots[role] = n
	end
	return next(slots) and slots or nil
end
local function SlotCSV(slots)
	local out = {}
	for _, role in ipairs(ROLE_ORDER) do
		local n = math.floor(tonumber(type(slots) == "table" and slots[role]) or 0)
		if n > 0 and n <= 40 then out[#out + 1] = role .. ":" .. n end
	end
	return table.concat(out, ",")
end

local function FreshRevision(rev)
	rev = UnB36(rev)
	local now = ServerNow()
	return rev and rev >= now - 180 * 86400 and rev <= now + 3600 and rev or nil
end
local function NextRevision(old)
	return math.max(ServerNow(), (type(old) == "table" and tonumber(old.rev) or 0) + 1)
end

local function NextSerial()
	counter = (counter + 1) % 1296
	local floor = ServerNow() * 1296
	local s = Store(true)
	if s then
		s.serial = math.max(floor, math.floor(tonumber(s.serial) or 0)) + 1
		return s.serial
	end
	return floor + counter
end

local function NewID(prefix)
	local name = ns.Fold(ns.me or "player")
	local h = 0
	for i = 1, #name do h = (h * 33 + name:byte(i)) % 46656 end
	return prefix .. B36(NextSerial()) .. B36(h)
end

local function TrimNewest(map, max, field)
	local list = {}
	for key, e in pairs(map) do list[#list + 1] = { key = key, t = type(e) == "table" and tonumber(e[field or "rev"]) or 0 } end
	if #list <= max then return false end
	table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.key < b.key end)
	for i = max + 1, #list do map[list[i].key] = nil end
	return true
end

local function TrimPosts(posts, max)
	local list = {}
	for cid, map in pairs(posts) do
		for key, e in pairs(map) do list[#list + 1] = { cid = cid, key = key, t = type(e) == "table" and tonumber(e.rev) or 0 } end
	end
	if #list <= max then return false end
	table.sort(list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		if a.cid ~= b.cid then return a.cid < b.cid end
		return a.key < b.key
	end)
	for i = max + 1, #list do
		local e = list[i]
		posts[e.cid][e.key] = nil
	end
	return true
end

function War.Prune(now)
	local s = Store(false)
	if not s then return false end
	now = now or ServerNow()
	local changed = false
	for key, e in pairs(s.lfg) do
		if type(e) ~= "table" or not tonumber(e.expires) or e.expires <= now then
			if type(e) == "table" and tonumber(e.rev) then
				local floor = s.lfgFloor[key]
				if type(floor) ~= "table" or (tonumber(floor.rev) or 0) < e.rev then s.lfgFloor[key] = { id = e.id, rev = e.rev } end
			end
			s.lfg[key] = nil
			changed = true
		end
	end
	for key, e in pairs(s.lfgFloor) do
		if type(e) ~= "table" or not ValidID(e.id) or not tonumber(e.rev) or now - e.rev > War.REPLAY_KEEP then s.lfgFloor[key], changed = nil, true end
	end
	for key, e in pairs(s.roles) do
		if type(e) ~= "table" or not tonumber(e.rev) or now - e.rev > War.REPLAY_KEEP then s.roles[key], changed = nil, true end
	end
	for id, e in pairs(s.operations) do
		if type(e) ~= "table" or not ValidID(id) or ((e.state == "complete" or e.state == "cancelled") and now - (e.rev or 0) > War.OP_KEEP) then
			s.operations[id], s.rsvp[id] = nil, nil
			changed = true
		end
	end
	changed = TrimNewest(s.operations, War.OP_MAX, "rev") or changed
	for id, map in pairs(s.rsvp) do
		if not s.operations[id] or type(map) ~= "table" then s.rsvp[id], changed = nil, true
		else changed = TrimNewest(map, War.RSVP_MAX, "rev") or changed end
	end
	for id, e in pairs(s.centuries) do
		if type(e) ~= "table" or not ValidID(id) then s.centuries[id], changed = nil, true end
	end
	changed = TrimNewest(s.centuries, War.CENTURY_MAX, "rev") or changed
	for cid, posts in pairs(s.posts) do
		if not s.centuries[cid] or type(posts) ~= "table" then s.posts[cid], changed = nil, true
		else
			for key, e in pairs(posts) do
				if type(e) ~= "table" or (not e.role and now - (e.rev or 0) > War.AAR_KEEP) then posts[key], changed = nil, true end
			end
			changed = TrimNewest(posts, War.POST_MAX, "rev") or changed
		end
	end
	changed = TrimPosts(s.posts, War.POST_TOTAL_MAX) or changed
	for id, e in pairs(s.after) do
		if type(e) ~= "table" or now - (e.rev or 0) > War.AAR_KEEP or not s.operations[e.operation]
			or (e.century and not s.centuries[e.century]) then s.after[id], changed = nil, true end
	end
	changed = TrimNewest(s.roles, War.ROLE_MAX, "rev") or changed
	changed = TrimNewest(s.lfg, War.LFG_MAX_ROWS, "rev") or changed
	changed = TrimNewest(s.lfgFloor, War.LFG_MAX_ROWS, "rev") or changed
	changed = TrimNewest(s.after, War.AAR_MAX, "rev") or changed
	return changed
end

local function Changed()
	War.Prune()
	ns.Fire("WAR_CHANGED")
	ns.Fire("REALM_PAGE_CHANGED", "war")
end

local function CanSend(kind, expected, msg, origin)
	local current = Guild()
	if not ns.IsMember() or current == nil then return false, "left" end
	if current ~= origin then return false, "guild-changed" end
	if ns.ChatLocked and ns.ChatLocked() then return false, "locked" end
	if kind == "officer" and not War.IsOfficer() then return false, "revoked" end
	if type(expected) == "function" and expected() ~= msg then return false, "changed" end
	return true
end

local function Send(msg, key, kind, expected, logged)
	local origin = Guild()
	if not origin then return false end
	local options = { owner = War, key = key, permit = function(_, guardKey, dist, target, current)
		if dist ~= "GUILD" or target ~= nil or guardKey ~= key then return false, "lane" end
		-- A chunked job hands its current transport piece to this callback, not the original payload.
		-- Recompute the complete record from saved state and compare it with the captured whole message.
		return CanSend(kind, expected, #msg <= 255 and current or msg, origin)
	end }
	if #msg <= 255 then return ns.Comm.Send("GUILD", msg, "war:" .. key, true, logged == true, nil, options) end
	if #msg > War.SNAPSHOT_BYTES then return false end
	return ns.Comm.SendChunked(msg, true, "GUILD", nil, options)
end

local function EncodeRoles(e) return ("WZ~1~R~%s~%s"):format(B36(e.rev), RoleCSV(e.roles)) end
local function EncodeLFG(e)
	return ("WZ~1~L~%s~%s~%s~%s~%s~%s"):format(e.id, B36(e.rev), B36(e.expires), e.kind, RoleCSV(e.roles), Clean(e.note, 64))
end
local function EncodeOperation(e)
	return ("WZ~1~O~%s~%s~%s~%s~%s~%s~%s~%s"):format(e.id, B36(e.rev), e.kind, e.state, B36(e.start), e.leader, SlotCSV(e.slots), Clean(e.title, 48))
end
local function EncodeRSVP(op, e)
	return ("WZ~1~V~%s~%s~%s~%s"):format(op, B36(e.rev), e.status, e.role or "-")
end
local function EncodeCentury(e)
	return ("WZ~1~C~%s~%s~%s~%s~%s~%s"):format(e.id, B36(e.rev), e.centurion, e.specialty, SlotCSV(e.slots), Clean(e.name, 40))
end
local function EncodePost(cid, e)
	return ("WZ~1~P~%s~%s~%s~%s"):format(cid, B36(e.rev), e.player, e.role or "-")
end
local function EncodeAfter(e)
	return ("WZ~1~A~%s~%s~%s~%s~%s~%s~%s"):format(e.id, B36(e.rev), e.operation or "-", e.century or "-", e.training and "1" or "0", Clean(e.result, 64), table.concat(e.participants or {}, ","))
end

function War.SetRoles(text)
	if not ns.IsMember() then return false, "member" end
	local roles, bad = ParseRoles(text, false)
	if not roles then ns.Print(L.WAR_ROLES_BAD:format(tostring(bad))); return false, "roles" end
	if not Rate(writes, War.WRITE_MAX, War.WRITE_WINDOW, "roles") then ns.Print(L.WAR_RATE); return false, "rate" end
	local s = Store(true)
	if not s then return false, "guild" end
	local key = ns.Fold(ns.me)
	local e = { player = ns.me, roles = roles, rev = NextRevision(s.roles[key]), by = ns.me, direct = true }
	s.roles[key] = e
	local msg = EncodeRoles(e)
	Send(msg, "roles", "member", function() local x = Store(false); x = x and x.roles[key]; return x and EncodeRoles(x) end, true)
	Changed()
	return e
end

local function ParseLFG(text)
	local head, note = tostring(text or ""):match("^(.-)%s*|%s*(.*)$")
	head, note = head or text or "", note or ""
	local kind, minutes, rest = tostring(head):lower():match("^(%a+)%s+(%d+)%s+(.+)$")
	minutes = tonumber(minutes)
	local roles = rest and ParseRoles(rest, false)
	if not KINDS[kind] or not minutes or minutes * 60 < War.LFG_MIN or minutes * 60 > War.LFG_MAX or not roles then return nil end
	return kind, minutes, roles, Clean(note, 64)
end

function War.PostLFG(text)
	if not ns.IsMember() then return false, "member" end
	local kind, minutes, roles, note = ParseLFG(text)
	if not kind then ns.Print(L.WAR_LFG_USAGE); return false, "shape" end
	if not Rate(lfgWrites, War.LFG_RAISES, War.LFG_WINDOW, ns.Fold(ns.me)) then ns.Print(L.WAR_RATE); return false, "rate" end
	local s, now = Store(true), ServerNow()
	if not s then return false, "guild" end
	local key = ns.Fold(ns.me)
	local previous = s.lfg[key]
	if type(s.lfgFloor[key]) == "table" and (not previous or (s.lfgFloor[key].rev or 0) > (previous.rev or 0)) then previous = s.lfgFloor[key] end
	local e = { player = ns.me, id = NewID("l"), rev = NextRevision(previous), expires = now + minutes * 60,
		kind = kind, roles = roles, note = note, by = ns.me, direct = true }
	s.lfg[key] = e
	s.lfgFloor[key] = { id = e.id, rev = e.rev }
	local msg = EncodeLFG(e)
	Send(msg, "lfg", "member", function() local x = Store(false); x = x and x.lfg[key]; return x and EncodeLFG(x) end, true)
	Changed()
	return e
end

function War.LowerLFG()
	local s = Store(false)
	local key = ns.Fold(ns.me)
	local old = s and s.lfg[key]
	if not old then return false, "none" end
	local rev, id = NextRevision(old), old.id
	s.lfgFloor[key] = { id = id, rev = rev }
	s.lfg[key] = nil
	local msg = ("WZ~1~l~%s~%s"):format(id, B36(rev))
	Send(msg, "lfg", "member", function() local x = Store(false); return (not x or not x.lfg[key]) and msg or nil end)
	Changed()
	return true
end

local DEFAULT_SLOTS = { raid = { tank = 2, healer = 4, melee = 5, ranged = 5, caller = 1 },
	pvp = { healer = 2, melee = 3, ranged = 3, support = 1, caller = 1, scout = 1 } }

local function ParseOfficerSpec(text, century)
	if century then
		local left, centurion, title = tostring(text or ""):match("^(.-)%s*|%s*(.-)%s*|%s*(.+)$")
		if not left then return nil end
		local specialty, slots = left:match("^(%a+)%s*(.*)$")
		if not SPECIALTIES[specialty] then return nil end
		centurion = Member(centurion)
		if not centurion then return nil end
		local parsed = slots ~= "" and ParseSlots((slots:gsub("=", ":"):gsub("%s+", ","))) or nil
		if not parsed then return nil end
		return specialty, centurion, parsed, Clean(title, 40)
	end
	local left, title = tostring(text or ""):match("^(.-)%s*|%s*(.+)$")
	if not left then return nil end
	local kind, minutes, slots = left:match("^(%a+)%s+(%d+)%s*(.*)$")
	minutes = tonumber(minutes)
	if not KINDS[kind] or not minutes or minutes < 0 or minutes > 10080 then return nil end
	local parsed = slots ~= "" and ParseSlots((slots:gsub("=", ":"):gsub("%s+", ","))) or DEFAULT_SLOTS[kind]
	if not parsed then return nil end
	return kind, minutes, parsed, Clean(title, 48)
end

local function OfficerWrite(bucket)
	if not War.IsOfficer() then ns.Print(L.WAR_OFFICERS_ONLY); return false end
	if ns.ChatLocked and ns.ChatLocked() then ns.Print(L.WAR_LOCKED); return false end
	if not Rate(writes, War.WRITE_MAX, War.WRITE_WINDOW, bucket) then ns.Print(L.WAR_RATE); return false end
	return true
end

function War.CreateOperation(text)
	if not OfficerWrite("operation") then return false, "officer" end
	local kind, minutes, slots, title = ParseOfficerSpec(text, false)
	if not kind or title == "" then ns.Print(L.WAR_OPERATION_USAGE); return false, "shape" end
	local s = Store(true)
	if not s then return false, "guild" end
	local e = { id = NewID("o"), rev = ServerNow(), kind = kind, state = "planned", start = ServerNow() + minutes * 60,
		leader = ns.me, slots = slots, title = title, by = ns.me, direct = true }
	s.operations[e.id] = e
	local msg = EncodeOperation(e)
	Send(msg, "operation:" .. e.id, "officer", function() local x = Store(false); x = x and x.operations[e.id]; return x and EncodeOperation(x) end, true)
	Changed()
	return e
end

function War.SetOperation(id, state)
	if not OfficerWrite("operation") then return false, "officer" end
	local s, e = Store(false)
	e = s and s.operations[id]
	if not e or not STATES[state] then return false, "operation" end
	if not StateAdvances(e.state, state) then return false, "closed" end
	e.state, e.rev, e.by, e.direct = state, NextRevision(e), ns.me, true
	local msg = EncodeOperation(e)
	Send(msg, "operation:" .. id, "officer", function() local x = Store(false); x = x and x.operations[id]; return x and EncodeOperation(x) end, true)
	Changed()
	return e
end

function War.RSVP(id, status, role)
	local s, e = Store(false)
	e = s and s.operations[id]
	status = RSVP[status] or status
	if role == "-" then role = nil end
	if not e or (e.state ~= "planned" and e.state ~= "active") or not RSVP_CODE[status] or (role and not ROLES[role]) then return false, "rsvp" end
	if status == "C" and not role then return false, "role" end
	if not Rate(writes, War.WRITE_MAX, War.WRITE_WINDOW, "rsvp") then return false, "rate" end
	local map, key = s.rsvp[id] or {}, ns.Fold(ns.me)
	s.rsvp[id] = map
	local x = { player = ns.me, status = status, role = role, rev = NextRevision(map[key]), by = ns.me, direct = true }
	map[key] = x
	local msg = EncodeRSVP(id, x)
	Send(msg, "rsvp:" .. id, "member", function() local a = Store(false); a = a and a.rsvp[id]; a = a and a[key]; return a and EncodeRSVP(id, a) end)
	Changed()
	return x
end

function War.CreateCentury(text)
	if not OfficerWrite("century") then return false, "officer" end
	local specialty, centurion, slots, name = ParseOfficerSpec(text, true)
	if not specialty or name == "" then ns.Print(L.WAR_CENTURY_USAGE); return false, "shape" end
	local s = Store(true)
	if not s then return false, "guild" end
	local e = { id = NewID("c"), rev = ServerNow(), centurion = centurion, specialty = specialty,
		slots = slots, name = name, by = ns.me, direct = true }
	s.centuries[e.id] = e
	local msg = EncodeCentury(e)
	Send(msg, "century:" .. e.id, "officer", function() local x = Store(false); x = x and x.centuries[e.id]; return x and EncodeCentury(x) end, true)
	Changed()
	return e
end

function War.AssignPost(text)
	if not OfficerWrite("post") then return false, "officer" end
	local left, name = tostring(text or ""):match("^(.-)%s*|%s*(.+)$")
	local cid, role
	if left then cid, role = left:match("^(%S+)%s+(%S+)$") end
	local s = Store(false)
	local c = s and s.centuries[cid]
	local player = Member(name)
	if not c then ns.Print(L.WAR_POST_USAGE); return false, "century" end
	if not player then ns.Print(L.WAR_POST_USAGE); return false, "player" end
	if role ~= "-" and not ROLES[role] then ns.Print(L.WAR_POST_USAGE); return false, "role" end
	local map = s.posts[cid] or {}; s.posts[cid] = map
	local key, old = ns.Fold(player), map[ns.Fold(player)]
	local e = { player = player, role = role ~= "-" and role or nil, rev = NextRevision(old), by = ns.me, direct = true }
	map[key] = e -- a bounded tombstone is synchronized, so an old reload copy cannot resurrect a removed post
	local msg = EncodePost(cid, e)
	Send(msg, "post:" .. cid .. ":" .. key, "officer", function()
		local x = Store(false); x = x and x.posts[cid]; x = x and x[key]
		return x and EncodePost(cid, x)
	end, true)
	Changed()
	return e
end

local function ParticipantList(text, exact, historical)
	local out, seen = {}, {}
	for raw in tostring(text or ""):gmatch("[^,]+") do
		if exact and (not ValidName(raw) or raw ~= Clean(raw, 72)) then return nil end
		local member = historical and RecordedName(raw) or (exact and MemberExact or Member)(Clean(raw, 72))
		if not member then return nil end
		local key = ns.Fold(member)
		if not seen[key] then seen[key], out[#out + 1] = true, member end
		if #out > 24 then return nil end
	end
	table.sort(out, function(a, b) return ns.Fold(a) < ns.Fold(b) end)
	return #out > 0 and out or nil
end

function War.RecordAfter(text)
	if not OfficerWrite("after") then return false, "officer" end
	local head, people = tostring(text or ""):match("^(.-)%s*;%s*(.+)$")
	local op, century, kind, result
	if head then op, century, kind, result = head:match("^(%S+)%s+(%S+)%s+(%S+)%s+(.+)$") end
	local s = Store(false)
	if century == "-" then century = nil end
	local operation = op and s and s.operations[op]
	if not operation or (operation.state ~= "complete" and operation.state ~= "cancelled") or (century and not s.centuries[century]) or (kind ~= "training" and kind ~= "action") then
		ns.Print(L.WAR_AFTER_USAGE); return false, "shape"
	end
	local participants = ParticipantList(people)
	result = Clean(result, 64)
	if not participants or result == "" then ns.Print(L.WAR_AFTER_USAGE); return false, "shape" end
	local e = { id = NewID("a"), rev = ServerNow(), operation = op, century = century, training = kind == "training",
		result = result, participants = participants, by = ns.me, direct = true }
	s.after[e.id] = e
	local msg = EncodeAfter(e)
	Send(msg, "after:" .. e.id, "officer", function() local x = Store(false); x = x and x.after[e.id]; return x and EncodeAfter(x) end, true)
	Changed()
	return e
end

local function Newer(old, rev) return type(old) ~= "table" or (tonumber(old.rev) or 0) < rev end
local function SenderKey(sender) return ns.Fold(Full(sender) or "") end

local function TakeRecord(sender, kind, fields, sync)
	local s = Store(true)
	local full, skey = Full(sender), SenderKey(sender)
	if not s or not full or skey == "" then return false end
	if kind == "R" then
		if sync then return false end
		local rev, roles = FreshRevision(fields[1]), ParseRoles(fields[2], false)
		if not rev or not roles or fields[3] ~= nil or not Newer(s.roles[skey], rev) then return false end
		s.roles[skey] = { player = full, roles = roles, rev = rev, by = full, direct = true }
		return true
	elseif kind == "L" then
		if sync then return false end
		local id, rev, expires, activity, roleText, note = fields[1], FreshRevision(fields[2]), UnB36(fields[3]), fields[4], fields[5], fields[6]
		local roles = ParseRoles(roleText, false)
		local now = ServerNow()
		note = WireText(note, 64, true)
		local floor = s.lfgFloor[skey]
		if not ValidID(id) or not rev or not expires or expires <= now or expires > now + War.LFG_MAX + 300 or not KINDS[activity] or not roles or not note or fields[7] ~= nil then return false end
		if not Newer(s.lfg[skey], rev) or (type(floor) == "table" and (floor.rev or 0) >= rev) then return false end
		s.lfg[skey] = { player = full, id = id, rev = rev, expires = expires, kind = activity, roles = roles,
			note = note, by = full, direct = true }
		s.lfgFloor[skey] = { id = id, rev = rev }
		return true
	elseif kind == "l" then
		if sync then return false end
		local id, rev = fields[1], FreshRevision(fields[2])
		local old, floor = s.lfg[skey], s.lfgFloor[skey]
		if not ValidID(id) or not rev or fields[3] ~= nil or (old and old.id ~= id) or (old and (old.rev or 0) >= rev)
			or (type(floor) == "table" and (floor.rev or 0) >= rev) then return false end
		s.lfgFloor[skey] = { id = id, rev = rev }
		s.lfg[skey] = nil
		return true
	elseif kind == "V" then
		if sync then return false end
		local op, rev, status, role = fields[1], FreshRevision(fields[2]), fields[3], fields[4]
		if role == "-" then role = nil end
		local operation = s.operations[op]
		if not ValidID(op) or not rev or not RSVP_CODE[status] or (role and not ROLES[role]) or fields[5] ~= nil or not operation
			or (operation.state ~= "planned" and operation.state ~= "active") then return false end
		local map = s.rsvp[op] or {}; s.rsvp[op] = map
		if not Newer(map[skey], rev) then return false end
		map[skey] = { player = full, status = status, role = role, rev = rev, by = full, direct = true }
		return true
	end
	if not Officer(sender) then return false end
	local ResolveRecordedName = sync and RecordedName or MemberExact
	if kind == "O" then
		local id, rev, activity, state, start, leader, slots, title = fields[1], FreshRevision(fields[2]), fields[3], fields[4], UnB36(fields[5]), ResolveRecordedName(fields[6]), ParseSlots(fields[7]), WireText(fields[8], 48, false)
		local old = s.operations[id]
		if not ValidID(id) or not rev or not KINDS[activity] or not STATES[state] or not start or start < ServerNow() - War.OP_KEEP or start > ServerNow() + 370 * 86400
			or not leader or not slots or not title or fields[9] ~= nil or not Newer(old, rev) or (old and not StateAdvances(old.state, state)) then return false end
		s.operations[id] = { id = id, rev = rev, kind = activity, state = state, start = start, leader = leader, slots = slots,
			title = title, by = full, via = sync and full or nil, direct = not sync }
		return true
	elseif kind == "C" then
		local id, rev, centurion, specialty, slots, name = fields[1], FreshRevision(fields[2]), ResolveRecordedName(fields[3]), fields[4], ParseSlots(fields[5]), WireText(fields[6], 40, false)
		if not ValidID(id) or not rev or not centurion or not SPECIALTIES[specialty] or not slots or not name or fields[7] ~= nil or not Newer(s.centuries[id], rev) then return false end
		s.centuries[id] = { id = id, rev = rev, centurion = centurion, specialty = specialty, slots = slots, name = name,
			by = full, via = sync and full or nil, direct = not sync }
		return true
	elseif kind == "P" then
		local cid, rev, player, role = fields[1], FreshRevision(fields[2]), ResolveRecordedName(fields[3]), fields[4]
		if not ValidID(cid) or not rev or not s.centuries[cid] or not player or (role ~= "-" and not ROLES[role]) or fields[5] ~= nil then return false end
		local map = s.posts[cid] or {}; s.posts[cid] = map
		local key, old = ns.Fold(player), map[ns.Fold(player)]
		if not Newer(old, rev) then return false end
		map[key] = { player = player, role = role ~= "-" and role or nil, rev = rev, by = full, via = sync and full or nil, direct = not sync }
		return true
	elseif kind == "A" then
		local id, rev, op, century, training, result, list = fields[1], FreshRevision(fields[2]), fields[3], fields[4], fields[5], WireText(fields[6], 64, false), fields[7]
		if century == "-" then century = nil end
		if not ValidID(id) then return false, "id" end
		if not rev then return false, "revision" end
		if not ValidID(op) or not s.operations[op] or (s.operations[op].state ~= "complete" and s.operations[op].state ~= "cancelled") then return false, "operation" end
		if century and not s.centuries[century] then return false, "century" end
		if training ~= "0" and training ~= "1" then return false, "training" end
		if not result then return false, "result" end
		if fields[8] ~= nil then return false, "fields" end
		if not Newer(s.after[id], rev) then return false, "replay" end
		local participants = ParticipantList(list, true, sync)
		if not participants then return false, "participants" end
		s.after[id] = { id = id, rev = rev, operation = op, century = century, training = training == "1", result = result,
			participants = participants, by = full, via = sync and full or nil, direct = not sync }
		return true
	end
	return false
end

local function Fields(s)
	local out = {}
	for field in (s .. "~"):gmatch("(.-)~") do out[#out + 1] = field end
	return out
end

local function ReplyOfficer()
	if not War.IsOfficer() then return false end
	local online = {}
	for _, m in ipairs(ns.Roster.members or {}) do
		if m.online and tonumber(m.rankIndex) and m.rankIndex <= ns.CAPTAIN_RANK then online[#online + 1] = m.full or ns.FullName(m.name) end
	end
	-- Do not let every officer answer while the roster is unavailable. Recovery will be requested
	-- again after the roster settles; a missing roster is never evidence that this client won election.
	if #online == 0 then return false end
	table.sort(online, function(a, b) return ns.Fold(a) < ns.Fold(b) end)
	return ns.Fold(online[1]) == ns.Fold(ns.me)
end

local function SnapshotRecords()
	War.Prune()
	local s, out = Store(false), {}
	if not s then return out end
	local function Add(msg)
		local body = msg:match("^WZ~1~(.+)$")
		if body and #body + 1 <= War.SNAPSHOT_BYTES - 64 and #out < War.SNAPSHOT_RECORDS then out[#out + 1] = body end
	end
	-- Dependency order matters after a reload: operations and Centuries before records that name
	-- them. Sort inside each section only, so pairs() cannot make two clients disagree.
	local function Section(map, encode)
		local section = {}
		for key, e in pairs(map or {}) do section[#section + 1] = { key = key, text = encode(e, key) } end
		table.sort(section, function(a, b) return a.key < b.key end)
		for _, e in ipairs(section) do Add(e.text) end
	end
	Section(s.operations, function(e) return EncodeOperation(e) end)
	Section(s.centuries, function(e) return EncodeCentury(e) end)
	local posts = {}
	for cid, map in pairs(s.posts) do for key, e in pairs(map) do posts[#posts + 1] = { key = cid .. "\1" .. key, text = EncodePost(cid, e) } end end
	table.sort(posts, function(a, b) return a.key < b.key end)
	for _, e in ipairs(posts) do Add(e.text) end
	Section(s.after, function(e) return EncodeAfter(e) end)
	return out
end
War.SnapshotRecords = SnapshotRecords

local function SnapshotPage(cursor, records)
	local all, page, bytes = records or SnapshotRecords(), {}, 0
	cursor = math.max(0, math.floor(tonumber(cursor) or 0))
	for i = cursor + 1, #all do
		local n = #all[i] + 1
		if #page > 0 and bytes + n > War.SNAPSHOT_BYTES - 64 then return page, i - 1 end
		if n <= War.SNAPSHOT_BYTES - 64 then page[#page + 1], bytes = all[i], bytes + n end
	end
	return page, 0
end
War.SnapshotPage = SnapshotPage

local function Answer(requester, nonce, cursor)
	local s = Store(false)
	if not s or not ns.IsMember() then return end
	local key = ns.Fold(ns.me)
	cursor = math.max(0, math.floor(tonumber(cursor) or 0))
	if cursor == 0 then
		local role = s.roles[key]
		if role then Send(EncodeRoles(role), "answer:roles:" .. nonce, "member", nil) end
		local lfg = s.lfg[key]
		if lfg and lfg.expires > ServerNow() then Send(EncodeLFG(lfg), "answer:lfg:" .. nonce, "member", nil) end
		for op, map in pairs(s.rsvp) do
			local e, operation = map[key], s.operations[op]
			if e and operation and (operation.state == "planned" or operation.state == "active") then
				Send(EncodeRSVP(op, e), "answer:rsvp:" .. op .. ":" .. nonce, "member", nil)
			end
		end
	end
	if ReplyOfficer() then
		local qkey, session = ns.Fold(requester) .. "\1" .. nonce, nil
		local now = Now()
		for key, e in pairs(outgoingSnapshots) do if type(e) ~= "table" or now - (e.t or 0) > War.ASK_WINDOW then outgoingSnapshots[key] = nil end end
		if cursor == 0 then
			local count = 0
			for _ in pairs(outgoingSnapshots) do count = count + 1 end
			if count >= 4 then return end
			session = { t = now, records = SnapshotRecords() }
			outgoingSnapshots[qkey] = session
		else
			session = outgoingSnapshots[qkey]
			if type(session) ~= "table" then return end
			session.t = now
		end
		local records, nextCursor = SnapshotPage(cursor, session.records)
		if #records > 0 then
			local msg = "WZ~1~S~" .. nonce .. "~" .. tostring(cursor) .. "~" .. tostring(nextCursor) .. "~" .. tostring(#session.records) .. "^" .. table.concat(records, "^")
			Send(msg, "answer:snapshot:" .. nonce .. ":" .. cursor, "officer", nil)
		end
		local progress = queryProgress[qkey]
		if type(progress) == "table" then progress.expected = nextCursor end
		if nextCursor == 0 then outgoingSnapshots[qkey] = nil end
	end
end

function War.Ask(force)
	local now = Now()
	if not ns.IsMember() or not Guild() or (not force and now - lastAsk < War.ASK_GAP) then return false end
	if not Rate(writes, 3, 600, "ask") then return false end
	lastAsk = now
	local nonce = B36(NextSerial())
	asked[nonce] = { t = now, pages = 0, cursor = 0 }
	for id, e in pairs(asked) do if type(e) ~= "table" or now - (e.t or 0) > War.ASK_WINDOW then asked[id] = nil end end
	local msg = "WZ~1~Q~" .. nonce
	return Send(msg, "ask", "member", function() return asked[nonce] and msg or nil end)
end

local function TakeSnapshot(sender, rest)
	local nonce, pageCursor, nextCursor, total, body = rest:match("^([0-9a-z]+)~(%d+)~(%d+)~(%d+)%^(.*)$")
	local request = nonce and asked[nonce]
	pageCursor, nextCursor, total = tonumber(pageCursor), tonumber(nextCursor), tonumber(total)
	if not request or Now() - (request.t or 0) > War.ASK_WINDOW or not pageCursor or pageCursor > 10000 or not nextCursor or nextCursor > 10000 or not Officer(sender)
		or not total or total < 1 or total > War.SNAPSHOT_RECORDS or body == "" or body:sub(1, 1) == "^" or body:sub(-1) == "^" or body:find("^^", 1, true) then return false end
	local records = {}
	for record in body:gmatch("[^%^]+") do
		local recordKind = record:match("^([A-Z])~")
		if not recordKind or (recordKind ~= "O" and recordKind ~= "C" and recordKind ~= "P" and recordKind ~= "A")
			or #record + 1 > War.SNAPSHOT_BYTES - 64 then return false end
		records[#records + 1] = record
	end
	local cursor = math.max(0, math.floor(tonumber(request.cursor) or 0))
	-- A response names the first record not included. It must exactly follow the page we asked for;
	-- this rejects duplicate, reordered and replayed pages before they can advance recovery state.
	if pageCursor ~= cursor or (request.sender and request.sender ~= ns.Fold(sender)) or (request.total and request.total ~= total)
		or cursor + #records > total or (nextCursor > 0 and (nextCursor ~= cursor + #records or nextCursor >= total))
		or (nextCursor == 0 and cursor + #records ~= total) then return false end
	request.sender, request.total = ns.Fold(sender), total
	request.pages = (request.pages or 0) + 1
	if request.pages > War.SNAPSHOT_PAGES then asked[nonce] = nil; return false end
	local changed = false
	for _, record in ipairs(records) do
		local kind, tail = record:match("^([A-Z])~(.*)$")
		if kind and (kind == "O" or kind == "C" or kind == "P" or kind == "A") then
			if TakeRecord(sender, kind, Fields(tail), true) then changed = true end
		end
	end
	if nextCursor > 0 then
		request.t, request.cursor = Now(), nextCursor
		local msg = "WZ~1~Q~" .. nonce .. "~" .. tostring(nextCursor)
		Send(msg, "ask:" .. nonce, "member", function() return asked[nonce] and msg or nil end)
	else
		asked[nonce] = nil
	end
	return changed
end

function War.Handle(dist, sender, text)
	if dist ~= "GUILD" or not ns.IsMember() or not Guild() or type(text) ~= "string" or #text > War.SNAPSHOT_BYTES or text:sub(1, 5) ~= "WZ~1~" then return false end
	sender = Full(sender)
	if not sender or ns.Fold(sender) == ns.Fold(ns.me or "") then return false end
	if not Rate(inbound, War.INBOUND_MAX, War.INBOUND_WINDOW, ns.Fold(sender)) then return false end
	local kind, rest = text:match("^WZ~1~([^~])~(.*)$")
	if not kind then return false end
	if kind == "Q" then
		local nonce, cursor = rest:match("^([0-9a-z]+)~?(%d*)$")
		cursor = cursor ~= "" and tonumber(cursor) or 0
		if not nonce or #nonce > 18 or not cursor or cursor > 10000 then return false end
		local qkey = ns.Fold(sender) .. "\1" .. nonce
		local now = Now()
		for key, e in pairs(queryProgress) do if type(e) ~= "table" or now - (e.t or 0) > War.ASK_WINDOW then queryProgress[key], outgoingSnapshots[key] = nil, nil end end
		if cursor == 0 then
			if queryProgress[qkey] then return false end
			if not Rate(inbound, 3, 600, "ask:" .. ns.Fold(sender)) then return false end
			if not Rate(inbound, 6, 60, "ask:*") then return false end
			queryProgress[qkey] = { cursor = 0, t = now }
		elseif type(queryProgress[qkey]) ~= "table" or cursor ~= queryProgress[qkey].expected then return false
		else queryProgress[qkey].cursor, queryProgress[qkey].t = cursor, now end
		local delay = 1 + (#ns.Fold(ns.me or "") + #nonce) % 5
		War.after(delay, "war answer", function() Answer(sender, nonce, cursor) end)
		return true
	elseif kind == "S" then
		local changed = TakeSnapshot(sender, rest)
		if changed then Changed() end
		return changed
	end
	local changed = TakeRecord(sender, kind, Fields(rest), false)
	if changed then Changed() end
	return changed
end

ns.Comm.Handle("WZ", function(...) War.Handle(...) end)

local function RoleRecord(name)
	local s = Store(false)
	return s and s.roles[ns.Fold(Full(name) or "")]
end
function War.RoleOf(name)
	local e = RoleRecord(name)
	if not e or ServerNow() - (e.rev or 0) > War.ROLE_FRESH then return nil end
	local labels = {}
	for _, role in ipairs(e.roles or {}) do labels[#labels + 1] = L[ROLE_LABEL[role]] end
	return #labels > 0 and table.concat(labels, ", ") or nil
end

local function Accepted(name, role, now)
	local e = RoleRecord(name)
	if not e or (now or ServerNow()) - (e.rev or 0) > War.ROLE_FRESH then return false end
	for _, r in ipairs(e.roles or {}) do if r == role then return true end end
	return false
end

function War.OperationReadiness(id, now)
	local s = Store(false)
	local op = s and s.operations[id]
	local out = { required = {}, filled = {}, gaps = {}, unconfirmed = 0, confirmed = 0, standby = 0 }
	if not op then return out end
	for role, n in pairs(op.slots or {}) do out.required[role], out.filled[role] = n, 0 end
	for _, e in pairs(s.rsvp[id] or {}) do
		if e.status == "S" then out.standby = out.standby + 1
		elseif e.status == "C" then
			if e.role and Accepted(e.player, e.role, now) then out.filled[e.role] = (out.filled[e.role] or 0) + 1; out.confirmed = out.confirmed + 1
			else out.unconfirmed = out.unconfirmed + 1 end
		end
	end
	for _, role in ipairs(ROLE_ORDER) do
		local missing = math.max(0, (out.required[role] or 0) - (out.filled[role] or 0))
		if missing > 0 then out.gaps[role] = missing end
	end
	return out
end

function War.CenturyReadiness(id, now)
	local s = Store(false)
	local c = s and s.centuries[id]
	local out = { required = {}, filled = {}, gaps = {}, unconfirmed = 0, members = 0, levels = {}, classes = {}, attendance = 0 }
	if not c then return out end
	for role, n in pairs(c.slots or {}) do out.required[role], out.filled[role] = n, 0 end
	for _, e in pairs(s.posts[id] or {}) do
		if e.role then
			out.members = out.members + 1
			if Accepted(e.player, e.role, now) then out.filled[e.role] = (out.filled[e.role] or 0) + 1 else out.unconfirmed = out.unconfirmed + 1 end
			for _, m in ipairs(ns.Roster.members or {}) do
				if ns.Fold(m.full or ns.FullName(m.name)) == ns.Fold(e.player) then
					if m.level then out.levels[m.level] = (out.levels[m.level] or 0) + 1 end
					if m.class then out.classes[m.class] = (out.classes[m.class] or 0) + 1 end
					break
				end
			end
		end
	end
	for _, role in ipairs(ROLE_ORDER) do
		local missing = math.max(0, (out.required[role] or 0) - (out.filled[role] or 0))
		if missing > 0 then out.gaps[role] = missing end
	end
	local seen = {}
	for _, a in pairs(s.after or {}) do
		if a.century == id then
			out.lastAction = math.max(out.lastAction or 0, a.rev or 0)
			if a.training then out.lastTraining = math.max(out.lastTraining or 0, a.rev or 0) end
			for _, p in ipairs(a.participants or {}) do if not seen[ns.Fold(p)] then seen[ns.Fold(p)], out.attendance = true, out.attendance + 1 end end
		end
	end
	return out
end

local function GapText(readiness)
	local out = {}
	for _, role in ipairs(ROLE_ORDER) do if readiness.gaps[role] then out[#out + 1] = L[ROLE_LABEL[role]] .. " " .. readiness.gaps[role] end end
	return #out > 0 and table.concat(out, ", ") or L.WAR_READY
end

local function SlotText(slots)
	local out = {}
	for _, role in ipairs(ROLE_ORDER) do
		local n = tonumber(type(slots) == "table" and slots[role])
		if n and n > 0 then out[#out + 1] = L[ROLE_LABEL[role]] .. " " .. n end
	end
	return table.concat(out, ", ")
end

local function MixText(readiness)
	local levels, classes = {}, {}
	for level, n in pairs(readiness.levels or {}) do levels[#levels + 1] = { level = tonumber(level) or 0, n = n } end
	table.sort(levels, function(a, b) return a.level > b.level end)
	local levelText = {}
	for _, e in ipairs(levels) do levelText[#levelText + 1] = tostring(e.level) .. "×" .. tostring(e.n) end
	for code, n in pairs(readiness.classes or {}) do
		local file = ns.CLASS_FILES and ns.CLASS_FILES[code]
		local label = (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or code
		classes[#classes + 1] = { label = label, n = n }
	end
	table.sort(classes, function(a, b) return a.label < b.label end)
	local classText = {}
	for _, e in ipairs(classes) do classText[#classText + 1] = e.label .. "×" .. tostring(e.n) end
	if #levelText == 0 and #classText == 0 then return L.WAR_NO_MIX end
	return L.WAR_MIX:format(#levelText > 0 and table.concat(levelText, ", ") or "?", #classText > 0 and table.concat(classText, ", ") or "?")
end

local function Prompt(prefix, title, hint)
	return ns.ShowDialog("OLYMPUS_WAR_INPUT", title, hint, { prefix = prefix })
end

function War.Lines(q)
	War.Prune()
	local s = Store(true)
	local lines = { { text = Gold(L.CHATS_BACK), onClick = function() ns.Views.ShowPage(nil) end } }
	if not s then lines[#lines + 1] = { text = Grey(L.WAR_NOT_MEMBER) }; return lines end
	local officer = War.IsOfficer()
	for _, line in ipairs(ns.WarSquads and ns.WarSquads.Lines(q) or {}) do lines[#lines + 1] = line end
	if Preview() then
		local role = ns.ViewAs.Role()
		officer = role == "gm" or role == "officer"
	end
	if not q then
		lines[#lines + 1] = { header = true, text = L.WAR_TITLE, right = Grey(L.WAR_OWN_GUILD:format(s.guild)) }
		lines[#lines + 1] = { text = Grey(L.WAR_PROVENANCE) }
		local mine = RoleRecord(ns.me)
		lines[#lines + 1] = { text = Gold(mine and L.WAR_CHANGE_ROLES or L.WAR_DECLARE_ROLES), right = Grey(War.RoleOf(ns.me) or L.WAR_NONE),
			onClick = function() Prompt("roles ", L.WAR_DECLARE_ROLES, L.WAR_ROLES_USAGE) end }
		local myLFG = s.lfg[ns.Fold(ns.me)]
		lines[#lines + 1] = { text = Gold(myLFG and L.WAR_LOWER_LFG or L.WAR_RAISE_LFG),
			right = myLFG and Grey(L.WAR_MINUTES_LEFT:format(math.max(1, math.ceil((myLFG.expires - ServerNow()) / 60)))) or nil,
			onClick = function() if myLFG then War.LowerLFG() else Prompt("lfg ", L.WAR_RAISE_LFG, L.WAR_LFG_USAGE) end end }
		if officer then
			lines[#lines + 1] = { text = Gold(L.WAR_CREATE_OPERATION), onClick = function() Prompt("operation ", L.WAR_CREATE_OPERATION, L.WAR_OPERATION_USAGE) end }
			lines[#lines + 1] = { text = Gold(L.WAR_CREATE_CENTURY), onClick = function() Prompt("century ", L.WAR_CREATE_CENTURY, L.WAR_CENTURY_USAGE) end }
		end
		lines[#lines + 1] = { text = "|TInterface\\Icons\\INV_Misc_Note_01:14:14|t " .. Gold(L.WAR_LOOT_LINK),
			onClick = function() ns.Views.ShowPage("loot") end, tooltip = function(tt) tt:AddLine(L.WAR_LOOT_LINK, 1, .82, 0); tt:AddLine(L.WAR_LOOT_LINK_TIP, 1, 1, 1, true) end }
	end

	local lfg = {}
	for _, e in pairs(s.lfg) do if not q or ns.Holds(q, e.player, e.kind, RoleCSV(e.roles), e.note) then lfg[#lfg + 1] = e end end
	table.sort(lfg, function(a, b) if a.expires ~= b.expires then return a.expires < b.expires end return ns.Fold(a.player) < ns.Fold(b.player) end)
	lines[#lines + 1] = { header = true, text = L.WAR_LFG_TITLE, right = tostring(#lfg) }
	for _, e in ipairs(lfg) do
		local note = e.note ~= "" and ('  "' .. e.note .. '"') or ""
		lines[#lines + 1] = { indent = 1, player = e.player, text = ns.DisplayName(e.player) .. "  " .. Gold(e.kind:upper()) .. "  " .. Grey(War.RoleOf(e.player) or RoleCSV(e.roles)) .. note,
			right = Grey(L.WAR_MINUTES_LEFT:format(math.max(1, math.ceil((e.expires - ServerNow()) / 60)))),
			onClick = ns.Fold(e.player) == ns.Fold(ns.me) and function() War.LowerLFG() end or function() ns.UI.ShowPerson({ name = e.player, guild = s.guild }) end }
	end
	if #lfg == 0 then lines[#lines + 1] = { indent = 1, text = Grey(q and L.SEARCH_NO_MATCH or L.WAR_LFG_EMPTY) } end

	local ops = {}
	for _, e in pairs(s.operations) do
		local matched = not q or ns.Holds(q, e.title, e.kind, e.state, e.leader)
		if q and not matched then
			for _, a in pairs(s.after) do
				if a.operation == e.id and ns.Holds(q, a.result, a.by, unpack(a.participants or {})) then matched = true break end
			end
		end
		if matched then ops[#ops + 1] = e end
	end
	table.sort(ops, function(a, b) if a.start ~= b.start then return a.start < b.start end return a.id < b.id end)
	lines[#lines + 1] = { header = true, text = L.WAR_OPERATIONS, right = tostring(#ops) }
	for _, op in ipairs(ops) do
		local ready = War.OperationReadiness(op.id)
		lines[#lines + 1] = { text = (expanded.operations[op.id] and "- " or "+ ") .. Gold(op.title),
			right = Grey(op.state .. "  ·  " .. GapText(ready)), onClick = function() expanded.operations[op.id] = not expanded.operations[op.id]; ns.UI.Refresh() end,
			tooltip = function(tt) tt:AddLine(op.title, 1, .82, 0); tt:AddLine(Provenance(op), .6, .6, .6, true) end }
		if expanded.operations[op.id] then
			lines[#lines + 1] = { indent = 1, text = L.WAR_OPERATION_META:format(op.kind:upper(), date("%Y-%m-%d %H:%M", op.start), ns.DisplayName(op.leader)), right = Grey(op.id) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_CAPABILITY_SLOTS, right = Grey(SlotText(op.slots)) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_READINESS, right = (next(ready.gaps) and Red or Green)(GapText(ready)) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_CONFIRMATIONS:format(ready.confirmed, ready.standby, ready.unconfirmed) }
			local reports = {}
			for _, a in pairs(s.after) do if a.operation == op.id then reports[#reports + 1] = a end end
			table.sort(reports, function(a, b) if a.rev ~= b.rev then return a.rev > b.rev end return a.id > b.id end)
			for _, a in ipairs(reports) do
				local present = {}
				for _, player in ipairs(a.participants or {}) do present[#present + 1] = ns.DisplayName(player) end
				lines[#lines + 1] = { indent = 2, text = L.WAR_AFTER_LINE:format(a.training and L.WAR_AFTER_TRAINING or L.WAR_AFTER_ACTION, a.result, #present),
					right = Grey(ns.Ago(a.rev)), tooltip = function(tt)
						tt:AddLine(L.WAR_AFTER_TIP:format(Provenance(a), table.concat(present, ", ")), 1, 1, 1, true)
					end }
			end
			if #reports == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.WAR_AFTER_EMPTY) } end
			if op.state == "planned" or op.state == "active" then
				local mine = RoleRecord(ns.me)
				for _, role in ipairs(mine and mine.roles or {}) do
					local picked = role
					lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_CONFIRM_AS:format(L[ROLE_LABEL[picked]])), onClick = function() War.RSVP(op.id, "confirmed", picked) end }
				end
				lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_STANDBY), onClick = function() War.RSVP(op.id, "standby") end }
			end
			if officer and op.state == "planned" then lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_START), onClick = function() War.SetOperation(op.id, "active") end } end
			if officer and op.state == "active" then lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_COMPLETE), onClick = function() War.SetOperation(op.id, "complete") end } end
			if officer and (op.state == "planned" or op.state == "active") then lines[#lines + 1] = { indent = 2, text = Red(L.WAR_CANCEL), onClick = function() War.SetOperation(op.id, "cancelled") end } end
			if officer and (op.state == "complete" or op.state == "cancelled") then lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_RECORD_AFTER), onClick = function() Prompt("after " .. op.id .. " ", L.WAR_RECORD_AFTER, L.WAR_AFTER_HINT) end } end
		end
	end
	if #ops == 0 then lines[#lines + 1] = { indent = 1, text = Grey(q and L.SEARCH_NO_MATCH or L.WAR_OPERATIONS_EMPTY) } end

	local centuries = {}
	for _, e in pairs(s.centuries) do
		local matched = not q or ns.Holds(q, e.name, e.specialty, e.centurion)
		if q and not matched then
			for _, post in pairs(s.posts[e.id] or {}) do if post.role and ns.Holds(q, post.player, post.role) then matched = true break end end
		end
		if matched then centuries[#centuries + 1] = e end
	end
	table.sort(centuries, function(a, b) return ns.Fold(a.name) < ns.Fold(b.name) end)
	lines[#lines + 1] = { header = true, text = L.WAR_CENTURIES, right = tostring(#centuries) }
	for _, c in ipairs(centuries) do
		local ready = War.CenturyReadiness(c.id)
		lines[#lines + 1] = { text = (expanded.centuries[c.id] and "- " or "+ ") .. Gold(c.name),
			right = Grey(c.specialty .. "  ·  " .. GapText(ready)), onClick = function() expanded.centuries[c.id] = not expanded.centuries[c.id]; ns.UI.Refresh() end,
			tooltip = function(tt) tt:AddLine(c.name, 1, .82, 0); tt:AddLine(Provenance(c), .6, .6, .6, true) end }
		if expanded.centuries[c.id] then
			lines[#lines + 1] = { indent = 1, text = L.WAR_CENTURION:format(ns.DisplayName(c.centurion)), right = Grey(c.id) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_CAPABILITY_SLOTS, right = Grey(SlotText(c.slots)) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_READINESS, right = (next(ready.gaps) and Red or Green)(GapText(ready)) }
			lines[#lines + 1] = { indent = 1, text = Grey(MixText(ready)) }
			lines[#lines + 1] = { indent = 1, text = L.WAR_ATTENDANCE:format(ready.attendance),
				right = Grey(L.WAR_FRESHNESS:format(ready.lastAction and ns.Ago(ready.lastAction) or L.WAR_NEVER,
					ready.lastTraining and ns.Ago(ready.lastTraining) or L.WAR_NEVER)) }
			local posts = {}
			for _, post in pairs(s.posts[c.id] or {}) do if post.role then posts[#posts + 1] = post end end
			table.sort(posts, function(a, b) return ns.Fold(a.player) < ns.Fold(b.player) end)
			for _, post in ipairs(posts) do
				local ok = Accepted(post.player, post.role)
				lines[#lines + 1] = { indent = 2, player = post.player, text = ns.DisplayName(post.player) .. "  " .. L[ROLE_LABEL[post.role]],
					right = ok and Green(L.WAR_DECLARED) or Red(L.WAR_UNCONFIRMED), tooltip = function(tt) tt:AddLine(Provenance(post), .6, .6, .6, true) end }
			end
			if #posts == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.WAR_POSTS_EMPTY) } end
			if officer then lines[#lines + 1] = { indent = 2, text = Gold(L.WAR_ASSIGN_POST), onClick = function() Prompt("post " .. c.id .. " ", L.WAR_ASSIGN_POST, L.WAR_POST_HINT) end } end
		end
	end
	if #centuries == 0 then lines[#lines + 1] = { indent = 1, text = Grey(q and L.SEARCH_NO_MATCH or L.WAR_CENTURIES_EMPTY) } end

	if not q then
		lines[#lines + 1] = { header = true, text = L.WAR_UNAVAILABLE_TITLE }
		lines[#lines + 1] = { indent = 1, text = Grey(L.WAR_UNAVAILABLE) }
	end
	-- A role preview cannot act, including a callback kept before changing the preview.
	for i = 2, #lines do
		local action = lines[i].onClick
		if action then lines[i].onClick = not Preview() and function() if not Preview() then action() end end or nil end
	end
	return lines
end

function War.Link()
	local s = Store(false)
	War.Prune()
	local ops, lfg = 0, 0
	for _, e in pairs(s and s.operations or {}) do if e.state == "planned" or e.state == "active" then ops = ops + 1 end end
	for _ in pairs(s and s.lfg or {}) do lfg = lfg + 1 end
	return { text = "|TInterface\\Icons\\INV_Sword_04:14:14|t " .. Gold(L.WAR_LINK), right = Grey(L.WAR_LINK_COUNTS:format(ops, lfg)),
		onClick = function() War.Show() end, tooltip = function(tt) tt:AddLine(L.WAR_LINK, 1, .82, 0); tt:AddLine(L.WAR_LINK_TIP, 1, 1, 1, true) end }
end

function War.Show()
	opened = true
	ns.Views.ShowPage("war")
	ns.UI.SelectTab("realm")
	if not Preview() then War.Ask() end
end

function War.Slash(text)
	text = tostring(text or "")
	local verb, rest = text:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	if verb == "" or verb == "open" then return War.Show()
	elseif verb == "roles" then return War.SetRoles(rest)
	elseif verb == "lfg" then return War.PostLFG(rest)
	elseif verb == "off" then return War.LowerLFG()
	elseif verb == "operation" then return War.CreateOperation(rest)
	elseif verb == "start" or verb == "complete" or verb == "cancel" then return War.SetOperation(rest, verb == "cancel" and "cancelled" or verb == "start" and "active" or "complete")
	elseif verb == "confirm" or verb == "standby" or verb == "decline" then
		local id, role = rest:match("^(%S+)%s*(%S*)$")
		return War.RSVP(id, verb == "confirm" and "confirmed" or verb, role ~= "" and role or nil)
	elseif verb == "century" then return War.CreateCentury(rest)
	elseif verb == "post" then return War.AssignPost(rest)
	elseif verb == "squadadd" then
		local leader, soldier = rest:match("^([^|]+)|(.+)$")
		return ns.WarSquads and leader and ns.WarSquads.Assign(leader, soldier) or false
	elseif verb == "after" then return War.RecordAfter(rest)
	elseif verb == "sync" then return War.Ask(true)
	end
	ns.Print(L.WAR_HELP)
	return false, "verb"
end

StaticPopupDialogs["OLYMPUS_WAR_INPUT"] = {
	text = "%s\n\n%s", button1 = L.WAR_SAVE, button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 360, maxLetters = 220,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox; data = data or self.data
		if eb and type(data) == "table" then ns.SafeCall("war input", War.Slash, (data.prefix or "") .. eb:GetText()) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent, data = self:GetParent(), self:GetParent().data
		if type(data) == "table" then ns.SafeCall("war input", War.Slash, (data.prefix or "") .. self:GetText()) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "war", Link = function() return War.Link() end, Lines = function(q) return War.Lines(q) end, tip = "WAR" })

ns.On("WAR_CHANGED", function()
	if opened and ns.Views and ns.Views.PageShown and ns.Views.PageShown() == "war" and ns.UI and ns.UI.IsShown and ns.UI.IsShown() then ns.UI.RefreshSoon() end
end)
ns.On("SQUADS_CHANGED", function()
	if ns.UI and ns.UI.IsShown and ns.UI.IsShown() and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end)
ns.On("LOGIN", function()
	War.Prune()
	War.after(15, "war recovery", function() if ns.IsMember() then War.Ask() end end)
	ns.Every(60, "war expiry", function()
		if War.Prune() then
			ns.Fire("WAR_CHANGED")
			ns.Fire("REALM_PAGE_CHANGED", "war")
		end
	end)
end)

function War.Reset()
	if ns.rdb then ns.rdb.warGuilds = nil end
	counter, opened, lastAsk = 0, false, -math.huge
	wipe(asked); wipe(inbound); wipe(writes); wipe(lfgWrites); wipe(expanded.operations); wipe(expanded.centuries)
	wipe(queryProgress); wipe(outgoingSnapshots)
end
