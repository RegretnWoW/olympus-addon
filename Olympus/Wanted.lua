local ADDON, ns = ...
local L = ns.L

-- Horde Most Wanted keeps observations local until a human review. A reviewer may receive a
-- bounded, private evidence summary (WX, WHISPER only), explicitly accept it, and publish the
-- resulting top three (WY). WY contains GUIDs and scores only: never victims, locations or raw
-- evidence. It is signed with the existing Arena account key and accepted only when the
-- server-stamped sender is currently the King, a signed High Councillor, or the author. Thus the
-- local kill ledger can never award a global frame by itself.
--
-- The reviewer's ledger is durable: every row he accepts is kept in his saved data (bounded;
-- the oldest fold into a base of open bounties and slayer totals), so his all-time top three
-- does not start over after a reload. The receivers keep the last word they accepted live, and
-- after a reload check it again (its signature, the key pinned for its issuer, its expiry, and
-- that its issuer still holds the role) before it shows any frame. A saved word is only ever
-- used by the client that heard it: words are taken from other players live, from their
-- issuer, never relayed. Editing a saved word's rows breaks its signature, and a word under
-- another key than the one pinned for its issuer is refused; whoever rewrites both in his own
-- saved data changes only what his own client shows, as editing the addon itself would.
--
-- Sightings (the section "Most Wanted sightings" below): a Horde player this client saw,
-- where its own player stood then, on its map for 15 minutes and whispered to the same reviewers
-- as the evidence. On for members until their No; never on the channel, never in an instance.
local Wanted = {}
ns.Wanted = Wanted

Wanted.VERSION = 1
Wanted.MAX_TARGETS = 200
Wanted.MAX_SLAYERS = 500
Wanted.MAX_EVIDENCE = 512
Wanted.MAX_SEEN = 2048
Wanted.MAX_VICTIMS = 32
Wanted.MAX_CLAIMS = 30
Wanted.MAX_AUDIT = 100
Wanted.MAX_MONTHS = 24
Wanted.MAX_POINTS = 100000
Wanted.RATE_MAX = 20
Wanted.RATE_WINDOW = 60
Wanted.GLOBAL_BORDERS_ACTIVE = true
Wanted.REVIEW_MAX = 256
Wanted.REVIEW_PER_SENDER = 32
Wanted.REVIEW_RATE_MAX = 8
Wanted.REVIEW_RATE_WINDOW = 60
Wanted.GLOBAL_ROWS = 3
-- A signed word holds for a month unless a newer one replaces it, its issuer loses the role or
-- he revokes it (was 30 minutes, for one session). Publishing again starts a new month.
Wanted.GLOBAL_LIFE = 31 * 86400
Wanted.GLOBAL_SKEW = 2 * 60
-- The publisher repeats his word for late logins: 6 times 5 minutes apart, then every 30
-- minutes while he stays online, and once 90 seconds after he logs in. Never a new expiry.
Wanted.GLOBAL_BURST = 6
Wanted.GLOBAL_BURST_GAP = 5 * 60
Wanted.GLOBAL_REPEAT_EVERY = 30 * 60
Wanted.GLOBAL_LOGIN_REPEAT = 90
-- One death has one killer: rows naming the same victim this close together describe one death.
Wanted.DEATH_WINDOW = 5
Wanted.EVIDENCE_AGE = 31 * 86400 -- a reviewer refuses evidence older than this
Wanted.LEDGER_MAX = 512          -- accepted rows a reviewer keeps; older ones fold into the base
Wanted.LEDGER_BASE_MAX = 512     -- open bounties, slayers and last deaths the base keeps
Wanted.SEND_BATCH = 8            -- evidence rows one click sends (the reviewer's per-sender burst)
-- Between two clicks to one reviewer: his rate window (REVIEW_RATE_MAX rows a minute from one
-- sender, the rest dropped on his side), and a margin for the time the whispers take to go.
Wanted.SEND_WAIT = Wanted.REVIEW_RATE_WINDOW + 5
Wanted.REVIEW_SHOWN = 50         -- accepted rows the review page lists (the newest)
Wanted.GLOBAL_MAX_SEQ = 2147483647
Wanted.GLOBAL_MAX_EPOCH = 2147483647
Wanted.GLOBAL_MAX_VERIFY = 8
-- Sightings (see "Most Wanted sightings" below).
Wanted.SIGHT_TTL = 15 * 60       -- a pin shows this long after the sighting
Wanted.SIGHT_GAP = 180           -- this client records one Horde player once this often on one map
Wanted.SIGHT_GRID = 5            -- the observer's spot, in thousandths of the map rounded to 5 (0.5%)
Wanted.SIGHT_SEND_MAX = 3        -- sightings this client sends a window...
Wanted.SIGHT_WINDOW = 60         -- ...of this many seconds (the rest stay on its own map)
Wanted.SIGHT_QUEUE_MAX = 8       -- sighting whispers waiting in Comm, at most
Wanted.SIGHT_QUEUE_TTL = 30      -- a sighting that waited this long in Comm is not sent
Wanted.SIGHT_RECV_MAX = 3        -- sightings a reviewer takes from one sender a window...
Wanted.SIGHT_INTAKE_MAX = 30     -- ...and from everyone
Wanted.SIGHT_SENDERS_MAX = 128   -- senders a reviewer counts at once
Wanted.SIGHT_PINS = 48           -- pins held at most (the newest)
Wanted.SIGHT_SEEN_MAX = 512      -- sighting ids remembered (replays)
Wanted.SIGHT_OWN_MAX = 256       -- Horde players this client remembers seeing (SIGHT_GAP)
Wanted.SIGHT_LAYER_FRESH = 120   -- this client's layer, when Layers saw it this recently
Wanted.SIGHT_TICK = 15           -- pins expire (and follow the interface style) on this beat
Wanted.SIGHT_QUIET = 5           -- the server's "No player named" for a sighting whisper, kept out of chat this long
Wanted.SIGHT_BADGE = 16          -- the world map's badge
Wanted.SIGHT_MINI = 12           -- the minimap's
Wanted.REVIEWER_FIRST = 45       -- a reviewer says he takes sightings this long after login...
Wanted.REVIEWER_EVERY = 5 * 60   -- ...then this often...
Wanted.REVIEWER_FOR = 11 * 60    -- ...and is sent them for this long after the last time
Wanted.REVIEWERS_MAX = 32
Wanted.ICON_PATHS = {
	"Interface\\Icons\\INV_Misc_Tournaments_banner_Orc",
	"Interface\\Icons\\INV_BannerPVP_01",
	"Interface\\Icons\\INV_Misc_QuestionMark",
}

local stats = { accepted = 0, replay = 0, refused = 0, corrected = 0, checkpointed = 0, conflict = 0,
	reviewed = 0, globalAccepted = 0, globalRefused = 0, globalReplay = 0, globalRestored = 0,
	sightSeen = 0, sightRepeat = 0, sightRate = 0, sightSent = 0, sightCancelled = 0, sightTaken = 0,
	sightRefused = 0, sightReplay = 0, sightExpired = 0, sightWithdrawn = 0, leases = 0 }
local rate = {}
local mode, opened = "list", nil
-- The word shown now. After a reload it comes back only through RestoreGlobal, which checks the
-- saved copy again; the copy alone (or any other saved field) never shows a frame.
local authenticatedGlobal
local globalFloor, publisherHeads = nil, {}
local pendingGlobal, pendingGlobalCount = {}, 0
-- The saved word being checked again after a load (its floor and pin hold meanwhile), and each
-- saved text's signature, checked once a session.
local restoring, restoreChecked = nil, {}
-- Pending submissions stay for the session only (untrusted, bounded); what a reviewer accepts
-- moves into his durable ledger (Ledger below).
local reviewInbox, reviewOrder = {}, {}
local reviewRate = {}
local publishedGlobal
-- [reviewer] = { [evidence id] = true }: sent this session. Only this session's: after a reload
-- the rows can go again, and the reviewer drops the ones he holds without counting them.
local sentTo = {}
local batches = {} -- [reviewer] = { name, at, ids }: the last batch sent him (Wanted.NotFound)
local watchingNotFound = false
local ScheduleGlobalRepeat
-- Sightings, this session's only (nothing of them is saved): the pins ([Horde GUID] = the newest
-- sighting of him), their frames, the ids taken (replays), this client's own last sighting of each
-- Horde player (SIGHT_GAP), when its last ones went (SIGHT_SEND_MAX), its whispers waiting in Comm,
-- the reviewers they reached (a No takes them back), the reviewers whose "No player named" it
-- keeps out of chat for a moment, each sender's count and everyone's (a reviewer's intake), and
-- the reviewers heard taking them.
local pins, pinFrames, spareFrames = {}, {}, {}
local sightSeen, sightSeenOrder = {}, {}
local ownSeen, ownSeenCount = {}, 0
local sightSends = {}
local sightJobs, sightJobCount = {}, 0
-- (told.by: [folded reviewer] = { name, target }; told.quiet: [lowered name] = until)
local told = { by = {}, quiet = {}, filter = false }
local sightFrom, sightFromCount, sightIntake = {}, 0, { at = 0, n = 0 }
local reviewers, reviewerCount = {}, 0
local leaseGen, leaseAt = 0, nil
local pinTicker = false
local SightingNotFound
local deathSerial = 0
local knownHorde = {} -- this session's verified unit identities, never addon messages

local function Clock()
	local D = ns.Data
	return (D and D.ServerTime and D.ServerTime()) or ns.Now()
end

local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end

local function Whole(v, lo, hi)
	if Secret(v) then return nil end
	local ok, number = pcall(tonumber, v)
	v = ok and number or nil
	return v and v == math.floor(v) and v >= lo and v <= hi and v or nil
end

local function Count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
	return n
end

local function Clean(value, limit)
	if Secret(value) then return nil end
	local ok, s = pcall(tostring, value or "")
	if not ok then return nil end
	s = s:gsub("[~|%^%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	return ns.Cut(s, limit or 96)
end

local function CleanRealm(realm)
	if Secret(realm) then return nil end
	realm = type(realm) == "string" and realm:gsub("[%s%-]", "") or nil
	if not realm or realm == "" or realm == "?" or realm:find("+", 1, true) then return nil end
	return ns.Cut(realm, 48)
end

local function CleanName(name, realm)
	if Secret(name, realm) then return nil end
	name = Clean(ns.Normal and ns.Normal(name) or name, 72)
	if not name then return nil end
	local namedRealm = ns.RealmOf and ns.RealmOf(name) or name:match("%-(.+)$")
	local short = ns.ShortName and ns.ShortName(name) or name:gsub("%-.*$", "")
	short = Clean(short, 48)
	if not short then return nil end
	realm = CleanRealm(namedRealm) or CleanRealm(realm) or CleanRealm(ns.realm)
	return realm and (short .. "-" .. realm) or short
end

local function Guid(guid)
	if Secret(guid) then return nil end
	if type(guid) ~= "string" or #guid > 64 then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	if not server or #id < 8 or #id > 16 then return nil end
	return "Player-" .. server .. "-" .. id:upper()
end

local function GuidKey(guid)
	guid = Guid(guid)
	return guid and ("g:" .. guid) or nil
end

local function NameKey(name)
	name = CleanName(name)
	return name and ("n:" .. ns.Fold(name)) or nil
end

local function Identity(value, guid, realm)
	if type(value) == "table" then
		guid, realm, value = value.guid, value.realm, value.name
	end
	local name = CleanName(value, realm)
	guid = Guid(guid)
	if not name and not guid then return nil end
	return { name = name, realm = name and ns.RealmOf(name) or CleanRealm(realm), guid = guid,
		key = GuidKey(guid) or NameKey(name), nameKey = NameKey(name), guidKey = GuidKey(guid) }
end
Wanted.Identity = Identity

local function SameIdentity(a, b)
	a, b = type(a) == "table" and a or Identity(a), type(b) == "table" and b or Identity(b)
	if not a or not b then return false end
	if a.guid and b.guid then return a.guid == b.guid end
	return a.nameKey ~= nil and a.nameKey == b.nameKey
end

local function Store(create)
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.wanted
	if type(s) ~= "table" or s.version ~= Wanted.VERSION or s.group ~= ns.group or s.faction ~= ns.faction then
		if not create then return nil end
		s = { version = Wanted.VERSION, group = ns.group, faction = ns.faction, targets = {}, aliases = {},
		slayers = {}, slayerAliases = {}, baseSlayers = {}, evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {}, seq = 0 }
		ns.rdb.wanted = s
	end
	for _, key in ipairs({ "targets", "aliases", "slayers", "slayerAliases", "baseSlayers", "evidence", "seen", "seenOrder", "recent", "audit" }) do
		if type(s[key]) ~= "table" then s[key] = {} end
	end
	s.seq = Whole(s.seq, 0, 2147483647) or 0
	return s
end

local function Sighting(value)
	if type(value) ~= "table" then return nil end
	local zone, at = Clean(value.zone, 80), Whole(value.at, 0, 4294967295)
	if not zone or not at then return nil end
	return { zone = zone, at = at, precision = value.precision == "consented" and "consented" or "approximate",
		evidence = value.evidence == "SELF_DEATH" and "SELF_DEATH" or "PARTY_KILL" }
end

local function TargetDerived(t)
	return {
		current = Whole(t.current, 0, Wanted.MAX_POINTS) or 0,
		lifetimeKills = Whole(t.lifetimeKills, 0, Wanted.MAX_POINTS) or 0,
		cycle = Whole(t.cycle, 1, Wanted.MAX_POINTS) or 1,
		openSince = Whole(t.openSince, 0, 4294967295) or (tonumber(t.addedAt) or 0),
		lastDeath = Whole(t.lastDeath, 0, 4294967295),
		lastSighting = Sighting(t.lastSighting),
		victimOverflow = Whole(t.victimOverflow, 0, Wanted.MAX_POINTS) or 0,
		victims = type(t.victims) == "table" and t.victims or {},
		claims = type(t.claims) == "table" and t.claims or {},
	}
end

local function CopyList(list, limit)
	local out = {}
	for i = math.max(1, #(type(list) == "table" and list or {}) - (limit or 100) + 1), #(type(list) == "table" and list or {}) do
		local e = list[i]
		if type(e) == "table" then
			local c = {}
			for k, v in pairs(e) do
				if type(v) == "table" then c[k] = CopyList(v, Wanted.MAX_VICTIMS) else c[k] = v end
			end
			out[#out + 1] = c
		end
	end
	return out
end

local function CopySlayers(rows)
	local out = {}
	for key, r in pairs(type(rows) == "table" and rows or {}) do
		if type(key) == "string" and type(r) == "table" then
			local months, monthAt, monthClaims, available = {}, {}, {}, {}
			for m, n in pairs(type(r.months) == "table" and r.months or {}) do
				m, n = tonumber(m), Whole(n, 0, Wanted.MAX_POINTS)
				if m and n then available[#available + 1] = { m, n } end
			end
			table.sort(available, function(a, b) return a[1] > b[1] end)
			for i = 1, math.min(Wanted.MAX_MONTHS, #available) do
				local m, n = available[i][1], available[i][2]
				months[m] = n
				monthAt[m] = Whole(type(r.monthAt) == "table" and r.monthAt[m], 0, 4294967295) or 0
				monthClaims[m] = Whole(type(r.monthClaims) == "table" and r.monthClaims[m], 0, Wanted.MAX_POINTS) or 0
			end
			out[key] = { key = key, name = CleanName(r.name), guid = Guid(r.guid), total = Whole(r.total, 0, Wanted.MAX_POINTS) or 0,
				claims = Whole(r.claims, 0, Wanted.MAX_POINTS) or 0, reachedAt = Whole(r.reachedAt, 0, 4294967295) or 0,
				lastAt = Whole(r.lastAt, 0, 4294967295) or 0, months = months, monthAt = monthAt, monthClaims = monthClaims }
		end
	end
	return out
end

local function MergeSlayer(into, from)
	into.total = math.min(Wanted.MAX_POINTS, (into.total or 0) + (from.total or 0))
	into.claims = math.min(Wanted.MAX_POINTS, (into.claims or 0) + (from.claims or 0))
	into.reachedAt = math.max(into.reachedAt or 0, from.reachedAt or 0)
	into.lastAt = math.max(into.lastAt or 0, from.lastAt or 0)
	into.months, into.monthAt, into.monthClaims = into.months or {}, into.monthAt or {}, into.monthClaims or {}
	for month, points in pairs(from.months or {}) do
		into.months[month] = math.min(Wanted.MAX_POINTS, (into.months[month] or 0) + points)
		into.monthAt[month] = math.max(into.monthAt[month] or 0, from.monthAt and from.monthAt[month] or 0)
		into.monthClaims[month] = math.min(Wanted.MAX_POINTS,
			(into.monthClaims[month] or 0) + (from.monthClaims and from.monthClaims[month] or 0))
	end
	into.name, into.guid = into.name or from.name, into.guid or from.guid
	return into
end

local function ResolveSlayer(s, value, create, upgrade)
	local ident = Identity(value)
	if not ident then return nil end
	if upgrade == nil then upgrade = create == true end
	local gk, nk = ident.guidKey, ident.nameKey
	local key = gk and (s.slayerAliases[gk] or gk) or nil
	local r = key and s.slayers[key] or nil
	if not r and nk then
		key = s.slayerAliases[nk] or nk
		r = s.slayers[key]
	end
	if r and r.guid and ident.guid and r.guid ~= ident.guid then return nil end
	if r and gk and r.key ~= gk and upgrade then
		local oldKey, other = r.key, s.slayers[gk]
		if other and other ~= r then
			r = MergeSlayer(other, r)
			s.slayers[oldKey] = nil
		else
			s.slayers[oldKey] = nil
			r.key = gk
			s.slayers[gk] = r
		end
		s.slayerAliases[oldKey] = gk
		key = gk
	elseif not r and create then
		if Count(s.slayers) >= Wanted.MAX_SLAYERS then return nil, "full" end
		key = gk or nk
		if not key then return nil, "identity" end
		r = { key = key, name = ident.name, guid = ident.guid, total = 0, claims = 0,
			months = {}, monthAt = {}, monthClaims = {} }
		s.slayers[key] = r
	end
	if not r then return nil end
	if upgrade or create then r.name, r.guid = ident.name or r.name, ident.guid or r.guid end
	if upgrade or create then
		if nk then s.slayerAliases[nk] = r.key end
		if gk then s.slayerAliases[gk] = r.key end
	end
	return r, r.key
end

local function TrimList(list, max)
	while #list > max do table.remove(list, 1) end
end

local function ResolveTarget(s, ident, upgrade)
	if not ident then return nil end
	local key = ident.guidKey and (s.aliases[ident.guidKey] or ident.guidKey) or nil
	local t = key and s.targets[key] or nil
	if not t and ident.nameKey then
		key = s.aliases[ident.nameKey] or ident.nameKey
		t = s.targets[key]
	end
	if not t then return nil end
	if t.guid and ident.guid and t.guid ~= ident.guid then return nil end
	if ident.guid and not t.guid and upgrade then
		local newKey = ident.guidKey
		local other = s.targets[newKey]
		if other and other ~= t then return nil end
		local oldKey = t.key
		s.targets[oldKey] = nil
		t.key, t.guid = newKey, ident.guid
		if ident.name then t.name, t.realm = ident.name, ident.realm end
		s.targets[newKey] = t
		s.aliases[oldKey], s.aliases[ident.nameKey or oldKey] = newKey, newKey
		for _, e in ipairs(s.evidence) do if e.targetKey == oldKey then e.targetKey = newKey end end
		key = newKey
	elseif ident.name and upgrade and (not t.name or ident.guid and t.guid == ident.guid and t.name ~= ident.name) then
		local oldNameKey = NameKey(t.name)
		t.name, t.realm = ident.name, ident.realm
		if oldNameKey then s.aliases[oldNameKey] = t.key end
		s.aliases[ident.nameKey] = t.key
	end
	return t, key
end

local function MonthNow()
	local c = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if type(c) == "table" and Whole(c.year, 1970, 9999) and Whole(c.month, 1, 12) then return c.year * 12 + c.month - 1 end
	local now = Clock()
	local offset = 0
	if type(GetGameTime) == "function" then
		local ok, h, m = pcall(GetGameTime)
		if ok and type(h) == "number" and type(m) == "number" then
			local d = (h * 60 + m - math.floor(now / 60) % 1440) % 1440
			if d > 720 then d = d - 1440 end
			offset = math.floor(d / 15 + 0.5) * 900
		end
	end
	if ns.Honors and ns.Honors.MonthOf then return ns.Honors.MonthOf(now, offset) end
	local dateFn = date or (os and os.date)
	if type(dateFn) ~= "function" then return math.floor(now / 2592000) end
	local d = dateFn("!*t", now + offset)
	return d.year * 12 + d.month - 1
end
Wanted.MonthNow = MonthNow

local function TrimMonths(r, current)
	local first = current - Wanted.MAX_MONTHS + 1
	for month in pairs(type(r.months) == "table" and r.months or {}) do
		if type(month) ~= "number" or month < first or month > current then
			r.months[month] = nil
			if type(r.monthAt) == "table" then r.monthAt[month] = nil end
			if type(r.monthClaims) == "table" then r.monthClaims[month] = nil end
		end
	end
end

local function AddVictim(t, e)
	local row = { name = e.victimName, guid = e.victimGuid, at = e.at, evidence = e.kind, id = e.id,
		zone = e.zone, precision = e.precision }
	t.victims[#t.victims + 1] = row
	if #t.victims > Wanted.MAX_VICTIMS then
		table.remove(t.victims, 1)
		t.victimOverflow = (t.victimOverflow or 0) + 1
	end
end

local function ApplyEvidence(s, e)
	local t = s.targets[e.targetKey]
	if not t then return false end
	if e.action == "bounty" then
		if t.current >= Wanted.MAX_POINTS or t.lifetimeKills >= Wanted.MAX_POINTS then return false end
		t.current, t.lifetimeKills = t.current + 1, t.lifetimeKills + 1
		AddVictim(t, e)
	elseif e.action == "claim" then
		local points = t.current
		local r
		if points > 0 then
			r = ResolveSlayer(s, { name = e.killerName, guid = e.killerGuid }, true)
			if not r then return false end
		end
		e.points = points
		local claim = { id = e.id, at = e.at, slayer = e.killerName, slayerGuid = e.killerGuid, points = points,
			evidence = e.kind, cycle = t.cycle, victims = CopyList(t.victims, Wanted.MAX_VICTIMS), overflow = t.victimOverflow or 0 }
		t.claims[#t.claims + 1] = claim
		TrimList(t.claims, Wanted.MAX_CLAIMS)
		t.current, t.victims, t.victimOverflow = 0, {}, 0
		t.lastDeath, t.openSince, t.cycle = e.at, e.at, math.min(Wanted.MAX_POINTS, t.cycle + 1)
		if points > 0 then
			r.name, r.guid = e.killerName or r.name, e.killerGuid or r.guid
			r.monthClaims = r.monthClaims or {}
			r.total, r.claims, r.reachedAt, r.lastAt = math.min(Wanted.MAX_POINTS, (r.total or 0) + points),
				math.min(Wanted.MAX_POINTS, (r.claims or 0) + 1), e.at, e.at
			local month = e.month
			r.months[month], r.monthAt[month] = math.min(Wanted.MAX_POINTS, (r.months[month] or 0) + points), e.at
			r.monthClaims[month] = math.min(Wanted.MAX_POINTS, (r.monthClaims[month] or 0) + 1)
			TrimMonths(r, MonthNow())
		end
	else
		return false
	end
	if e.zone then t.lastSighting = { zone = e.zone, at = e.at, precision = e.precision, evidence = e.kind } end
	return true
end

local function Rebuild(s)
	for _, t in pairs(s.targets) do
		local b = TargetDerived(type(t.base) == "table" and t.base or {})
		t.current, t.lifetimeKills, t.cycle, t.openSince, t.lastDeath = b.current, b.lifetimeKills, b.cycle, b.openSince, b.lastDeath
		t.lastSighting = b.lastSighting
		t.victimOverflow, t.victims, t.claims = b.victimOverflow, CopyList(b.victims, Wanted.MAX_VICTIMS), CopyList(b.claims, Wanted.MAX_CLAIMS)
	end
	s.slayers = CopySlayers(s.baseSlayers)
	for _, e in ipairs(s.evidence) do if type(e) == "table" and not e.void then ApplyEvidence(s, e) end end
	return true
end
Wanted.Rebuild = function() local s = Store(false); return s and Rebuild(s) or false end

local function Checkpoint(s)
	for _, t in pairs(s.targets) do
		t.base = TargetDerived(t)
		t.base.victims, t.base.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
	end
	s.baseSlayers = CopySlayers(s.slayers)
	for _, r in pairs(s.baseSlayers) do TrimMonths(r, MonthNow()) end
	s.evidence = {}
	stats.checkpointed = stats.checkpointed + 1
end

local function Audit(s, op, target, detail)
	s.audit[#s.audit + 1] = { op = op, target = target, detail = detail, at = math.floor(Clock()), by = ns.me }
	TrimList(s.audit, Wanted.MAX_AUDIT)
end

local function Changed()
	ns.Fire("WANTED_CHANGED")
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end

function Wanted.CanManage()
	if not ns.IsMember or not ns.IsMember() or not ns.me then return false end
	local M = ns.Moderation
	if M and M.CanIssue and M.CanIssue() == true then return true end
	local W = ns.Workshop
	return W and W.IsAuthor and W.IsAuthor() == true or false
end

function Wanted.AddTarget(value, guid, realm)
	if not Wanted.CanManage() then return false, "access" end
	local ident = Identity(value, guid, realm)
	if not ident then return false, "identity" end
	local s = Store(true)
	local t = ResolveTarget(s, ident, true)
	if t then
		if t.active then return false, "listed" end
		t.active, t.removedAt, t.removedBy = true, nil, nil
		t.addedAt, t.addedBy = math.floor(Clock()), ns.me
	else
		if Count(s.targets) >= Wanted.MAX_TARGETS then return false, "full" end
		t = { key = ident.key, name = ident.name, realm = ident.realm, guid = ident.guid, active = true,
			addedAt = math.floor(Clock()), addedBy = ns.me, source = "manual", current = 0, lifetimeKills = 0,
			cycle = 1, openSince = math.floor(Clock()), victims = {}, claims = {}, victimOverflow = 0 }
		s.targets[t.key] = t
		if ident.nameKey then s.aliases[ident.nameKey] = t.key end
		if ident.guidKey then s.aliases[ident.guidKey] = t.key end
	end
	Audit(s, "add", t.key)
	Changed()
	return true, t.key
end

function Wanted.RemoveTarget(value, guid, realm)
	if not Wanted.CanManage() then return false, "access" end
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not (t and t.active) then return false, "missing" end
	t.active, t.removedAt, t.removedBy = false, math.floor(Clock()), ns.me
	Audit(s, "remove", t.key)
	if opened == t.key then mode, opened = "list", nil end
	Changed()
	return true
end

local function UnitIdentity(unit)
	if type(UnitIsPlayer) == "function" then
		local ok, yes = pcall(UnitIsPlayer, unit)
		if not ok or yes ~= true then return nil end
	end
	local okName, name = pcall(function() return ns.UnitFullName and ns.UnitFullName(unit) or nil end)
	local okGuid, guid = pcall(function() return UnitGUID and UnitGUID(unit) or nil end)
	if not okName or not okGuid or Secret(name, guid) then return nil end
	return Identity(name, guid)
end

function Wanted.AddTargetUnit(unit)
	unit = unit or "target"
	local ident = UnitIdentity(unit)
	if not ident then return false, "identity" end
	if type(UnitFactionGroup) == "function" then
		local ok, known, horde = pcall(function()
			local faction = UnitFactionGroup(unit)
			if Secret(faction) then return true, false end
			return faction ~= nil, faction == "Horde"
		end)
		if not ok or known and not horde then return false, "faction" end
	end
	return Wanted.AddTarget(ident)
end

local function UnitMatches(unit, ident)
	local u = UnitIdentity(unit)
	return u and SameIdentity(u, ident)
end

local function RememberHorde(ident)
	if not ident or not ident.guid or not ident.name then return end
	local now = math.floor(Clock())
	knownHorde[ident.guid] = { identity = ident, at = now }
	for guid, row in pairs(knownHorde) do if now - row.at > 60 or row.at > now then knownHorde[guid] = nil end end
	while Count(knownHorde) > Wanted.MAX_TARGETS do
		local oldest
		for guid, row in pairs(knownHorde) do if not oldest or row.at < knownHorde[oldest].at then oldest = guid end end
		knownHorde[oldest] = nil
	end
end

local function KnownHorde(ident)
	if not ident or not ident.guid then return nil end
	local units = { "target", "focus", "mouseover" }
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	for _, unit in ipairs(units) do
		local observed = UnitIdentity(unit)
		if observed and observed.guid == ident.guid then
			local ok, faction = pcall(function() return UnitFactionGroup and UnitFactionGroup(unit) end)
			if ok and not Secret(faction) and faction == "Horde" then RememberHorde(observed); return observed end
			return nil -- current contradictory/unknown faction overrides an old observation
		end
	end
	local row, now = knownHorde[ident.guid], math.floor(Clock())
	return row and row.at <= now and now - row.at <= 60 and row.identity or nil
end

local function VerifiedOlympian(ident)
	if not ident then return false end
	local mine = UnitIdentity("player") or Identity(ns.me)
	if mine and SameIdentity(mine, ident) and ns.IsMember and ns.IsMember() then return true end
	local R = ns.Roster
	if ident.name and R and R.RankOf and R.RankOf(ident.name) ~= nil then return true end
	local units = { "player", "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for _, unit in ipairs(units) do
		if UnitMatches(unit, ident) then
			local guild = GetGuildInfo and GetGuildInfo(unit)
			if not Secret(guild) and type(guild) == "string" and ns.IsFederation(guild) then return true end
		end
	end
	return false
end

local function Zone()
	if type(GetRealZoneText) ~= "function" then return nil end
	local ok, zone = pcall(GetRealZoneText)
	return ok and Clean(zone, 80) or nil
end

local function RateAllowed(now)
	for i = #rate, 1, -1 do if now - rate[i] >= Wanted.RATE_WINDOW then table.remove(rate, i) end end
	if #rate >= Wanted.RATE_MAX then return false end
	rate[#rate + 1] = now
	return true
end

local function Remember(s, id, fingerprint, at, seq)
	s.seen[id] = { at = at, seq = seq }
	s.seenOrder[#s.seenOrder + 1] = id
	s.recent[fingerprint] = at
	while #s.seenOrder > Wanted.MAX_SEEN do
		local old = table.remove(s.seenOrder, 1)
		if old and s.seen[old] and s.seen[old].seq <= seq - Wanted.MAX_SEEN then s.seen[old] = nil end
	end
	for key, seenAt in pairs(s.recent) do if at - (tonumber(seenAt) or 0) > 30 then s.recent[key] = nil end end
end

local function EvidenceId(kind, raw, killer, victim)
	local source = Clean(raw, 64) or tostring(math.floor(Clock()))
	return ns.Cut(table.concat({ kind, killer.guid or killer.name or "?", victim.guid or victim.name or "?", source }, ":"), 160)
end

-- The newest live evidence about this victim's death inside the death window: "replay" when it
-- names the same killer (two adapters, or one row read twice across a 3-second bucket),
-- "conflict" when it names another (one death never pays twice, nor two slayers).
local function SameDeath(s, killer, victim, now)
	for i = #s.evidence, 1, -1 do
		local e = s.evidence[i]
		if type(e) == "table" and not e.void and math.abs(now - (tonumber(e.at) or 0)) <= Wanted.DEATH_WINDOW
			and SameIdentity(Identity(e.victimName, e.victimGuid), victim) then
			return SameIdentity(Identity(e.killerName, e.killerGuid), killer) and "replay" or "conflict"
		end
	end
	return nil
end

local function RecordKill(kind, rawId, killer, victim, opts)
	killer, victim = Identity(killer), Identity(victim)
	-- Both sides must be players the row names and identifies (Guid takes Player- GUIDs only): a
	-- pet, a creature or the environment never credits a kill, and a pet or an NPC that merely
	-- carries a listed target's name never matches that target. (Prune keeps no other row.)
	if not killer or not victim or not killer.name or not killer.guid or not victim.name or not victim.guid then
		stats.refused = stats.refused + 1
		return false, "identities"
	end
	local s = Store(false)
	if not s and opts and opts.autoHorde and kind == "SELF_DEATH" and VerifiedOlympian(victim)
		and SameIdentity(UnitIdentity("player"), victim) then s = Store(true) end
	if not s then return false, "store" end
	-- Resolve first without learning anything: a rejected/forged row must not be able to pin a
	-- new GUID or spelling onto a listed target merely by naming it.
	local killerTarget = ResolveTarget(s, killer, false)
	local victimTarget = ResolveTarget(s, victim, false)
	local auto = not killerTarget and not victimTarget and opts and opts.autoHorde
		and kind == "SELF_DEATH" and SameIdentity(UnitIdentity("player"), victim) and VerifiedOlympian(victim)
	if auto then
		if Count(s.targets) >= Wanted.MAX_TARGETS then return false, "full" end
		killerTarget = { key = killer.key, name = killer.name, realm = killer.realm, guid = killer.guid, active = true,
			addedAt = math.floor(Clock()), addedBy = ns.me, source = "SELF_DEATH", current = 0, lifetimeKills = 0,
			cycle = 1, openSince = math.floor(Clock()), victims = {}, claims = {}, victimOverflow = 0 }
	end
	if (killerTarget and victimTarget) or (not killerTarget and not victimTarget) then
		stats.refused = stats.refused + 1
		return false, killerTarget and "ambiguous" or "unlisted"
	end
	local action, target, olympian
	if killerTarget then action, target, olympian = "bounty", killerTarget, victim
	else action, target, olympian = "claim", victimTarget, killer end
	if not target.active or not VerifiedOlympian(olympian) then
		stats.refused = stats.refused + 1
		return false, target.active and "olympus" or "removed"
	end
	if action == "claim" and target.current > 0 and not ResolveSlayer(s, killer, false, false)
		and Count(s.slayers) >= Wanted.MAX_SLAYERS then return false, "slayers" end
	local now = math.floor(Clock())
	local id = EvidenceId(kind, rawId, killer, victim)
	local fingerprint = table.concat({ killer.guidKey or killer.nameKey, victim.guidKey or victim.nameKey, tostring(math.floor(now / 3)) }, ">")
	if s.seen[id] or s.recent[fingerprint] and math.abs(now - s.recent[fingerprint]) <= 5 then
		stats.replay = stats.replay + 1
		return false, "replay"
	end
	local death = SameDeath(s, killer, victim, now)
	if death == "replay" then stats.replay = stats.replay + 1 return false, "replay" end
	if death == "conflict" then stats.conflict = stats.conflict + 1 return false, "conflict" end
	if not RateAllowed(now) then stats.refused = stats.refused + 1 return false, "rate" end
	if auto then
		s.targets[target.key] = target
		s.aliases[killer.guidKey], s.aliases[killer.nameKey] = target.key, target.key
	end
	local learned = ResolveTarget(s, action == "bounty" and killer or victim, true)
	if not learned or learned ~= target then return false, "identity" end
	target = learned
	if #s.evidence >= Wanted.MAX_EVIDENCE then Checkpoint(s) end
	s.seq = s.seq + 1
	local e = { id = id, seq = s.seq, at = now, month = MonthNow(), kind = kind, action = action, targetKey = target.key,
		killerName = killer.name, killerGuid = killer.guid, victimName = victim.name, victimGuid = victim.guid,
		zone = opts and opts.zone or nil, precision = opts and opts.precision or nil }
	Remember(s, id, fingerprint, now, e.seq)
	s.evidence[#s.evidence + 1] = e
	if not ApplyEvidence(s, e) then
		e.void = true
		Rebuild(s)
		return false, "bounds"
	end
	stats.accepted = stats.accepted + 1
	Changed()
	return true, e
end

-- The combat-log adapter accepts only PARTY_KILL, whose payload names both sides.  UNIT_DIED and
-- damage rows never identify a killer reliably and are intentionally ignored.
function Wanted.CaptureCombatLog(...)
	local a = { ... }
	if #a == 0 and type(CombatLogGetCurrentEventInfo) == "function" then
		local ok, values = pcall(function() return { CombatLogGetCurrentEventInfo() } end)
		if not ok then return false, "api" end
		a = values
	end
	local timestamp, subevent, sourceGuid, sourceName, destGuid, destName = a[1], a[2], a[4], a[5], a[8], a[9]
	if Secret(timestamp, subevent, sourceGuid, sourceName, destGuid, destName) then return false, "secret" end
	if subevent ~= "PARTY_KILL" then return false, "event" end
	if not sourceGuid or not sourceName or not destGuid or not destName then return false, "identities" end
	return RecordKill("PARTY_KILL", tostring(timestamp or ""), { name = sourceName, guid = sourceGuid },
		{ name = destName, guid = destGuid }, { zone = Zone(), precision = "approximate" })
end

-- Native frame event, distinct from the CLEU subevent: UnitDocumentation.lua, PartyKill,
-- https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua
-- Payload is attackerGUID, targetGUID, secret when unit identity is restricted. Forever's
-- extracted fixture confirms the event exists; its current payload still needs a live check.
-- Credit only our own killing blow against an already listed, active player GUID. Other party
-- members and pets are not attributed to us, and no target/nameplate supplies a guessed killer.
function Wanted.CapturePartyKill(attackerGUID, targetGUID)
	if Secret(attackerGUID, targetGUID) then return false, "secret" end
	local attacker, victim = Guid(attackerGUID), Guid(targetGUID)
	if not attacker or not victim then return false, "identities" end
	local mine = UnitIdentity("player")
	if not mine or mine.guid ~= attacker then return false, "attacker" end
	if not ns.IsMember or ns.IsMember() ~= true then return false, "olympus" end
	local s = Store(false)
	local target = s and ResolveTarget(s, Identity(nil, victim), false)
	if not target or target.guid ~= victim then return false, "unlisted" end
	if not target.active then return false, "removed" end
	return RecordKill("PARTY_KILL", "native:" .. tostring(math.floor(Clock())), mine, Identity(target),
		{ zone = Zone(), precision = "approximate" })
end

local function FatalRecap(row)
	if type(row) ~= "table" then return false end
	local ok, fatal = pcall(function()
		return row.killingBlow == true or row.isKillingBlow == true or row.fatal == true
			or row.subEvent == "PARTY_KILL" or row.event == "PARTY_KILL"
	end)
	return ok and fatal == true
end

-- A recap row is accepted only when it explicitly marks the fatal event and contains both
-- identities.  In particular, a target name by itself is never promoted to "killer".
function Wanted.CaptureSelfDeathRecap(recap)
	if type(UnitIsDeadOrGhost) == "function" then
		local ok, dead = pcall(UnitIsDeadOrGhost, "player")
		if not ok or dead ~= true then return false, "alive" end
	end
	local rows = type(recap) == "table" and recap or {}
	if rows[1] == nil and FatalRecap(rows) then rows = { rows } end
	local mine = UnitIdentity("player") or Identity(ns.me)
	for i = #rows, 1, -1 do
		local row = rows[i]
		if FatalRecap(row) then
			local killer = Identity(row.killerName or row.sourceName, row.killerGUID or row.sourceGUID)
			local victim = Identity(row.victimName or row.destName, row.victimGUID or row.destGUID)
			if not killer or not victim then return false, "identities" end
			if not mine or not SameIdentity(mine, victim) then return false, "victim" end
			return RecordKill("SELF_DEATH", row.eventID or row.id or row.timestamp, killer, victim,
				{ zone = Zone(), precision = "approximate" })
		end
	end
	return false, "fatal"
end

local function ReadSelfDeathRecap()
	-- Forever's last-death reader (HeadHunter's native probe, build 69913, 2026-09-23):
	-- https://github.com/GudaAddons/HeadHunter/blob/main/Detection/ForeverDeaths.lua
	-- Require both APIs to work without an ID; other clients' ID-based readers fail closed.
	-- Only an explicit, recent hostile player killing blow counts. Never guess from a target,
	-- the latest damage, or a pet's possible owner. The victim is our own verified player unit.
	local recap = C_DeathRecap
	if type(recap) == "table" and type(recap.HasRecapEvents) == "function" and type(recap.GetRecapEvents) == "function" then
		local hasOK, has = pcall(recap.HasRecapEvents)
		local readOK, events
		if hasOK and not Secret(has) and has == true then readOK, events = pcall(recap.GetRecapEvents) end
		if readOK and type(events) == "table" then
			local mine, s, now = UnitIdentity("player"), Store(false), math.floor(Clock())
			local deadOK, dead = pcall(function() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)
			if mine and deadOK and not Secret(dead) and dead == true then
				for i = #events, 1, -1 do
					local row = events[i]
					if type(row) == "table" and not Secret(row.sourceGUID, row.sourceName, row.sourceFlags, row.event, row.overkill, row.timestamp) then
						local stampOK, stamp = pcall(tonumber, row.timestamp)
						local at = stampOK and stamp and stamp >= now - Wanted.DEATH_WINDOW and stamp <= now + 1 and stamp or nil
						local flags = Whole(row.sourceFlags, 0, 2147483647)
						local overkill = Whole(row.overkill, 0, 2147483647)
						local kind = row.event
						local killer = Identity(row.sourceName, row.sourceGUID)
						local target = killer and s and ResolveTarget(s, killer, false)
						local known = killer and not target and KnownHorde(killer)
						if at and flags and overkill and type(kind) == "string" and kind:match("_DAMAGE$")
							and bit.band(flags, 0x440) == 0x440 and (target and target.guid == killer.guid or known) then
							return RecordKill("SELF_DEATH", "native:" .. tostring(at), target and Identity(target) or known, mine,
								{ zone = Zone(), precision = "approximate", autoHorde = known ~= nil })
						end
					end
				end
			end
		end
	end
	local D = C_DeathInfo
	local fn = type(D) == "table" and (D.GetDeathRecapEvents or D.GetDeathRecap) or nil
	if type(fn) ~= "function" then return false end
	local ok, rows = pcall(fn, "player")
	if not ok or type(rows) ~= "table" then ok, rows = pcall(fn) end
	if not ok or type(rows) ~= "table" then return false end
	return Wanted.CaptureSelfDeathRecap(rows)
end

function Wanted.Correct(id, reason)
	if not Wanted.CanManage() then return false, "access" end
	id = Clean(id, 160)
	if not id then return false, "id" end
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do
		if e.id == id and not e.void then
			e.void, e.correctedAt, e.correctedBy, e.correction = true, math.floor(Clock()), ns.me, Clean(reason, 80)
			Audit(s, "correct", e.targetKey, id)
			Rebuild(s)
			stats.corrected = stats.corrected + 1
			Changed()
			return true
		end
	end
	return false, "expired"
end

local function PublicTarget(t)
	if type(t) ~= "table" then return nil end
	return { key = t.key, name = t.name, realm = t.realm, guid = t.guid, active = t.active == true, addedAt = t.addedAt,
		addedBy = t.addedBy, current = t.current or 0, lifetimeKills = t.lifetimeKills or 0, cycle = t.cycle or 1,
		openSince = t.openSince, lastDeath = t.lastDeath, lastSighting = t.lastSighting and CopyList({ t.lastSighting }, 1)[1] or nil,
		victimOverflow = t.victimOverflow or 0, victims = CopyList(t.victims, Wanted.MAX_VICTIMS), claims = CopyList(t.claims, Wanted.MAX_CLAIMS) }
end

function Wanted.Target(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	return PublicTarget(t)
end

function Wanted.Targets(activeOnly)
	local s, out = Store(false), {}
	for _, t in pairs(s and s.targets or {}) do if not activeOnly or t.active then out[#out + 1] = PublicTarget(t) end end
	table.sort(out, function(a, b)
		if a.active ~= b.active then return a.active end
		if a.current ~= b.current then return a.current > b.current end
		if a.lifetimeKills ~= b.lifetimeKills then return a.lifetimeKills > b.lifetimeKills end
		return tostring(a.name or a.guid or a.key) < tostring(b.name or b.guid or b.key)
	end)
	return out
end

local function Ranked(rows, month)
	local out = {}
	for _, r in pairs(type(rows) == "table" and rows or {}) do
		local points = month and (type(r.months) == "table" and r.months[month] or 0) or r.total
		if (tonumber(points) or 0) > 0 then
			out[#out + 1] = { key = r.key, name = r.name, guid = r.guid, points = points,
				claims = month and (r.monthClaims and r.monthClaims[month] or 0) or r.claims or 0,
				reachedAt = month and (r.monthAt and r.monthAt[month] or 0) or r.reachedAt or 0, lastAt = r.lastAt or 0 }
		end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.key < b.key
	end)
	for i, r in ipairs(out) do r.place = i end
	return out
end

function Wanted.Rankings(month)
	local s = Store(false)
	month = tonumber(month) or MonthNow()
	return { month = Ranked(s and s.slayers or {}, month), all = Ranked(s and s.slayers or {}, nil), monthNo = month }
end

---------------------------------------------------------------------------
-- Human review and the signed global top three
---------------------------------------------------------------------------

local function Hex(bytes)
	return type(bytes) == "string" and (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) or nil
end

local function Digest(text)
	local S = ns.Sign
	local raw = S and S.SHA256 and S.SHA256(tostring(text or "")) or nil
	return raw and Hex(raw):sub(1, 16) or nil
end

local function Scope()
	return Digest(tostring(ns.group or ns.realm or "?") .. "|" .. tostring(ns.faction or "?"))
end

local function SameName(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(ns.FullName(a)) == ns.Fold(ns.FullName(b))
end

-- Authority is derived every time from the current signed/pinned state. Preview/debug views never
-- count. Revoking the signed council list therefore removes a held snapshot on the next read.
function Wanted.CanPublish(name)
	name = CleanName(name)
	if not name or not ns.IsMember or ns.IsMember() ~= true then return false end
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return true end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(name) == true then return true end
	return false
end

local function WireGuid(guid)
	guid = Guid(guid)
	if not guid then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	return server .. "." .. id:lower()
end

local function GameGuid(wire)
	if type(wire) ~= "string" or #wire > 24 then return nil end
	local server, id = wire:match("^(%d+)%.(%x+)$")
	if not server or #server > 7 or #id < 8 or #id > 16 or id:find("[A-F]") then return nil end
	return Guid("Player-" .. server .. "-" .. id)
end

local function CanonicalRows(rows)
	local out, seen = {}, {}
	for _, row in ipairs(type(rows) == "table" and rows or {}) do
		local guid = Guid(type(row) == "table" and row.guid)
		local points = Whole(type(row) == "table" and row.points, 1, Wanted.MAX_POINTS)
		local claims = Whole(type(row) == "table" and row.claims, 0, Wanted.MAX_POINTS)
		local reachedAt = Whole(type(row) == "table" and row.reachedAt, 0, 4294967295)
		if not guid or not points or not claims or not reachedAt or seen[guid] then return nil, "rows" end
		seen[guid] = true
		out[#out + 1] = { key = GuidKey(guid), guid = guid, points = points, claims = claims, reachedAt = reachedAt }
		if #out > Wanted.GLOBAL_ROWS then return nil, "rows" end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.guid < b.guid
	end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, row in ipairs(rows) do
		local wire = WireGuid(row.guid)
		if not wire then return nil end
		out[i] = table.concat({ wire, row.points, row.claims, row.reachedAt }, ":")
	end
	return #out > 0 and table.concat(out, ",") or "-"
end

local function ReadRows(text)
	if text == "-" then return {} end
	if type(text) ~= "string" or text == "" or #text > 256 then return nil, "rows" end
	local rows = {}
	for item in text:gmatch("[^,]+") do
		local wire, points, claims, reachedAt = item:match("^([^:]+):(%d+):(%d+):(%d+)$")
		rows[#rows + 1] = { guid = GameGuid(wire), points = tonumber(points), claims = tonumber(claims), reachedAt = tonumber(reachedAt) }
	end
	return CanonicalRows(rows)
end

local function AuthorityWeight(name)
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return 3 end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return 2 end
	return 1
end

-- Between publishers the newer word wins (its issue time), then the higher role, then a fixed
-- name order; the epoch and sequence come last, and one publisher's own words also follow his
-- pins (NewerSnapshot). (It was the epoch first: a publisher whose key generation began earlier,
-- the King say, could then never replace or revoke the word of a councillor who began later.)
local function Order(snapshot)
	return { snapshot.issued, AuthorityWeight(snapshot.issuer), ns.Fold(snapshot.issuer), snapshot.epoch, snapshot.seq }
end

local function CompareOrder(a, b)
	if not b then return 1 end
	for i = 1, 5 do
		if a[i] ~= b[i] then
			if i == 3 then return a[i] < b[i] and 1 or -1 end -- deterministic name tie-break
			return a[i] > b[i] and 1 or -1
		end
	end
	return 0
end

local function Fresh(snapshot, now)
	now = now or math.floor(Clock())
	return snapshot.issued <= now + Wanted.GLOBAL_SKEW and snapshot.expires >= now
		and snapshot.epoch <= snapshot.issued + Wanted.GLOBAL_SKEW
		and snapshot.expires > snapshot.issued and snapshot.expires - snapshot.issued <= Wanted.GLOBAL_LIFE
end

-- The saved copy of the word shown (this realm group and faction's store): its text, its issuer,
-- when it came, and the publishers' pins as they were then. Only RestoreGlobal reads it.
local function SaveGlobal(snapshot)
	local s = Store(true)
	if not s then return end
	s.global = { text = snapshot.text, issuer = snapshot.issuer, at = math.floor(Clock()) }
	local heads = {}
	for who, h in pairs(publisherHeads) do heads[who] = { epoch = h.epoch, seq = h.seq, pk64 = h.pk64 } end
	s.globalHeads = heads
end

local function ForgetGlobal(text)
	local s = Store(false)
	if s and type(s.global) == "table" and (text == nil or s.global.text == text) then s.global, s.globalHeads = nil, nil end
end

local function ClearGlobal(expired)
	local held = authenticatedGlobal
	authenticatedGlobal = nil
	-- The floor and per-publisher key pins protect only a currently valid word. Keeping them
	-- after that word expires, leaves this realm/faction, or loses its authority would let a
	-- revoked publisher strand every legitimate replacement until /reload.
	globalFloor, publisherHeads = nil, {}
	-- An expired word leaves the saved data too. One whose issuer does not hold the role now
	-- (the council's list may not have come yet) or of another realm group stays saved for
	-- RestoreGlobal to look at again; it shows nothing meanwhile.
	if expired and held then ForgetGlobal(held.text) end
	if held then Changed() end
	return held ~= nil
end

local function CurrentGlobal()
	local held = authenticatedGlobal
	if held then
		if not Fresh(held) then ClearGlobal(true)
		elseif not Wanted.CanPublish(held.issuer) or held.scope ~= Scope() then ClearGlobal(false) end
	end
	return authenticatedGlobal
end

-- A private, deliberately untrusted review inbox. The wire omits names, victims' guilds and
-- locations. Accepting a row is a human decision and still does not grant a border.
-- Each sender's rows count against this rate (REVIEW_RATE_MAX a window) once they are new here.
local function ReviewAdmit(sender, now)
	local key = ns.Fold(sender)
	local bucket = reviewRate[key]
	if not bucket then
		if Count(reviewRate) >= Wanted.REVIEW_MAX then
			for other, held in pairs(reviewRate) do
				if now - held.at >= Wanted.REVIEW_RATE_WINDOW then reviewRate[other] = nil end
			end
			if Count(reviewRate) >= Wanted.REVIEW_MAX then return false end
		end
		bucket = { at = now, count = 0 }
		reviewRate[key] = bucket
	elseif now - bucket.at >= Wanted.REVIEW_RATE_WINDOW then
		bucket.at, bucket.count = now, 0
	end
	if bucket.count >= Wanted.REVIEW_RATE_MAX then return false end
	bucket.count = bucket.count + 1
	return true
end

---------------------------------------------------------------------------
-- The reviewer's durable ledger: the rows he accepted, oldest first by the time of the death,
-- and a base the oldest fold into once there are more than LEDGER_MAX:
--   s.ledger = { accepted = { row, ... }, folded = n, foldedAt = time of the newest folded death,
--                base = { targets = { [guid] = open bounty }, slayers = { [guid] = { points,
--                         claims, reachedAt } }, deaths = { [action|victim guid] = at } } }
-- A row: { key = sender#digest, digest, from, at, month, kind, action, killerGuid, victimGuid,
-- reviewedAt, reviewedBy }. Only accepted rows are kept: pending and rejected ones never are.
-- The base keeps totals, not rows: a row about a death at or before foldedAt is no longer taken
-- (Late). It may be one folded already (sent again), and none could be put back in its place
-- in the order of the deaths.
---------------------------------------------------------------------------

local LEDGER_KINDS = { PARTY_KILL = true, SELF_DEATH = true }
local LEDGER_ACTIONS = { bounty = true, claim = true }

local function LedgerRow(e)
	if type(e) ~= "table" then return nil end
	local digest = type(e.digest) == "string" and e.digest:match("^%x+$") and #e.digest == 16 and e.digest or nil
	local from = CleanName(e.from)
	local at, month = Whole(e.at, 0, 4294967295), Whole(e.month, 0, 120000)
	local killer, victim = Guid(e.killerGuid), Guid(e.victimGuid)
	if not digest or not from or not at or not month or not killer or not victim
		or not LEDGER_KINDS[e.kind] or not LEDGER_ACTIONS[e.action] then return nil end
	return { key = ns.Fold(from) .. "#" .. digest, digest = digest, from = from, at = at, month = month, kind = e.kind,
		action = e.action, killerGuid = killer, victimGuid = victim, reviewedAt = Whole(e.reviewedAt, 0, 4294967295) or 0,
		reviewedBy = CleanName(e.reviewedBy) }
end

local function Earlier(a, b)
	if a.at ~= b.at then return a.at < b.at end
	return a.key < b.key
end

local function Ledger(create)
	local s = Store(create)
	if not s then return nil end
	local l = s.ledger
	if type(l) ~= "table" then
		if not create then return nil end
		l = {}
		s.ledger = l
	end
	if type(l.accepted) ~= "table" then l.accepted = {} end
	if type(l.base) ~= "table" then l.base = {} end
	for _, key in ipairs({ "targets", "slayers", "deaths" }) do
		if type(l.base[key]) ~= "table" then l.base[key] = {} end
	end
	l.folded = Whole(l.folded, 0, 2147483647) or 0
	l.foldedAt = Whole(l.foldedAt, 0, 4294967295)
	return l
end

-- A death at or before the newest one folded into the base: refused (see above).
local function Late(l, at)
	return l ~= nil and l.foldedAt ~= nil and at <= l.foldedAt
end

local function DeathKey(e) return e.action .. "|" .. e.victimGuid end

-- One accepted row applied to the running totals. A row about a death already counted (the same
-- victim inside the death window: another observer's copy) is provenance, not points.
local function ApplyReviewed(targets, slayers, deaths, e)
	local death = DeathKey(e)
	local last = deaths[death]
	if last and math.abs(e.at - last) <= Wanted.DEATH_WINDOW then return false end
	deaths[death] = e.at
	if e.action == "bounty" then
		targets[e.killerGuid] = math.min(Wanted.MAX_POINTS, (targets[e.killerGuid] or 0) + 1)
	else
		local points = targets[e.victimGuid] or 0
		targets[e.victimGuid] = nil
		if points > 0 then
			local r = slayers[e.killerGuid] or { guid = e.killerGuid, points = 0, claims = 0, reachedAt = e.at }
			r.points, r.claims, r.reachedAt = math.min(Wanted.MAX_POINTS, r.points + points),
				math.min(Wanted.MAX_POINTS, r.claims + 1), e.at
			r.months = type(r.months) == "table" and r.months or {}
			local m = r.months[e.month] or { points = 0, claims = 0 }
			m.points, m.claims, m.reachedAt = math.min(Wanted.MAX_POINTS, m.points + points),
				math.min(Wanted.MAX_POINTS, m.claims + 1), e.at
			r.months[e.month] = m
			for month in pairs(r.months) do
				if not Whole(month, MonthNow() - Wanted.MAX_MONTHS + 1, MonthNow()) then r.months[month] = nil end
			end
			slayers[e.killerGuid] = r
		end
	end
	return true
end

-- Keeps one of the base's tables within its bound: the entry `worse` ranks lowest goes first.
local function Bound(t, worse)
	local n = Count(t)
	while n > Wanted.LEDGER_BASE_MAX do
		local drop
		for key, v in pairs(t) do if drop == nil or worse(v, t[drop], key, drop) then drop = key end end
		t[drop], n = nil, n - 1
	end
end

local function Fold(l, e)
	local b = l.base
	ApplyReviewed(b.targets, b.slayers, b.deaths, e)
	l.folded = math.min(2147483647, l.folded + 1)
	l.foldedAt = math.max(l.foldedAt or 0, e.at)
	Bound(b.deaths, function(a, z) return a < z end)
	Bound(b.targets, function(a, z) return a < z end)
	Bound(b.slayers, function(a, z, ka, kz)
		if a.points ~= z.points then return a.points < z.points end
		if a.reachedAt ~= z.reachedAt then return a.reachedAt > z.reachedAt end
		return ka > kz
	end)
end

local function LedgerFind(l, key)
	for i, e in ipairs(l and l.accepted or {}) do if e.key == key then return e, i end end
	return nil
end

local function LedgerAdd(e)
	local row = LedgerRow(e)
	local l = row and Ledger(true)
	if not l then return false end
	if LedgerFind(l, row.key) then return true end
	-- (Inserted before every row, it would fold at once, after newer deaths already folded.)
	if Late(l, row.at) then return false, "late" end
	local at = #l.accepted + 1
	while at > 1 and Earlier(row, l.accepted[at - 1]) do at = at - 1 end
	table.insert(l.accepted, at, row)
	while #l.accepted > Wanted.LEDGER_MAX do Fold(l, table.remove(l.accepted, 1)) end
	return true
end

-- Another observer's account of the same death that names a different killer: accepted rows
-- (and, unless acceptedOnly, the pending ones). A reviewer accepts only one of them.
local function ConflictOf(e, acceptedOnly)
	local function Disagrees(o)
		return o ~= e and o.key ~= e.key and o.action == e.action and o.victimGuid == e.victimGuid
			and o.killerGuid ~= e.killerGuid and math.abs(o.at - e.at) <= Wanted.DEATH_WINDOW
	end
	local l = Ledger(false)
	for _, o in ipairs(l and l.accepted or {}) do if Disagrees(o) then return o end end
	if acceptedOnly then return nil end
	for _, key in ipairs(reviewOrder) do
		local o = reviewInbox[key]
		if o and o.state == "pending" and Disagrees(o) then return o end
	end
	return nil
end

-- 1.2.0: an Olympus member (our roster, or a federation guild's claim the channel takes).
local function EvidenceMember(sender)
	local R = ns.Roster
	if R and R.RankOf and R.RankOf(sender) ~= nil then return true end
	local C, M = ns.Channels, ns.Moderation
	if type(C) ~= "table" or type(C.VerifiedLevel) ~= "function" then return false end
	local guild = M and M.GuildOf and M.GuildOf(sender)
	if type(guild) ~= "string" or guild == "" or not (ns.IsFederation and ns.IsFederation(guild)) then return false end
	local ok, level = pcall(C.VerifiedLevel, sender, guild)
	return ok and type(level) == "number" and level >= 1
end

-- Whether a player GUID is the sender's character: true or false when this client can name it
-- (a unit, or the game's cache of seen players), nil when it cannot.
local function GuidIsSender(guid, sender)
	local who = ns.Fold(ns.FullName(sender))
	if type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and type(token) == "string" and not Secret(token) then
			local name = ns.UnitFullName(token)
			if type(name) == "string" and not Secret(name) then return ns.Fold(ns.FullName(name)) == who end
		end
	end
	if type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) and not Secret(realm) then
			return ns.Fold(ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)) == who
		end
	end
	return nil
end

local function ReviewEvidence(sender, body)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	local version, digest, at, month, kind, action, killerWire, victimWire =
		body:match("^WX~(%d+)~(%x+)~(%d+)~(%d+)~([PS])~([BC])~([^~]+)~([^~]+)$")
	at, month = tonumber(at), tonumber(month)
	local killer, victim = GameGuid(killerWire), GameGuid(victimWire)
	if version ~= "1" or not digest or #digest ~= 16 or not at or not Whole(month, 0, 120000)
		or not killer or not victim then return false, "shape" end
	local now = math.floor(Clock())
	if at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.EVIDENCE_AGE then return false, "stale" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	-- 1.2.0: a member's own evidence only: the Olympian side of the row (the killer of a party
	-- kill, the victim of a death) is the sender whenever this client can name that GUID.
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(sender) then return false, "olympus" end
	if not EvidenceMember(sender) then return false, "olympus" end
	if GuidIsSender(kind == "S" and victim or killer, sender) == false then return false, "not-own" end
	local key = ns.Fold(sender) .. "#" .. digest
	-- A row held already costs the sender's rate nothing: after his reload his client may send
	-- again what it sent before. Pending here, or accepted (in this session or an earlier one:
	-- already counted), or about a death the ledger's base already holds.
	if reviewInbox[key] then return false, "replay" end
	local l = Ledger(false)
	if LedgerFind(l, key) then return false, "reviewed" end
	if Late(l, at) then return false, "late" end
	if not ReviewAdmit(sender, now) then return false, "rate" end
	-- The inbox holds the pending rows only (an accepted one moves to the ledger), so these bounds
	-- are on what waits for the reviewer, not on what he took.
	local from, held = ns.Fold(sender), 0
	for _, reviewKey in ipairs(reviewOrder) do
		local existing = reviewInbox[reviewKey]
		if existing and ns.Fold(existing.from) == from then held = held + 1 end
	end
	if held >= Wanted.REVIEW_PER_SENDER then return false, "sender-full" end
	if #reviewOrder >= Wanted.REVIEW_MAX then return false, "full" end
	local e = { key = key, digest = digest, from = sender, at = at, month = month,
		kind = kind == "S" and "SELF_DEATH" or "PARTY_KILL", action = action == "C" and "claim" or "bounty",
		killerGuid = killer, victimGuid = victim, receivedAt = now, state = "pending" }
	-- Observers who disagree (another killer for the same death) are both shown, flagged; the
	-- reviewer can accept only one of them (Wanted.Review).
	e.conflict = ConflictOf(e) ~= nil
	reviewInbox[key], reviewOrder[#reviewOrder + 1] = e, key
	return true, key
end

-- This client's live evidence rows that a reviewer can check (both GUIDs known, and not so old
-- that he refuses them: EVIDENCE_AGE, less a margin for his clock), newest first (after a
-- reload, the rows sent before are the older ones): one target's (its key) or every target's.
local function Sendable(targetKey)
	local s, out = Store(false), {}
	local oldest = math.floor(Clock()) - Wanted.EVIDENCE_AGE + Wanted.GLOBAL_SKEW
	local evidence = s and s.evidence or {}
	for i = #evidence, 1, -1 do
		local e = evidence[i]
		if type(e) == "table" and not e.void and Guid(e.killerGuid) and Guid(e.victimGuid) and (tonumber(e.at) or 0) >= oldest
			and (targetKey == nil or e.targetKey == targetKey) then out[#out + 1] = e end
	end
	return out
end

-- done(sent, why): as Comm.Whisper's, once the whisper went (or did not).
function Wanted.SubmitEvidence(reviewer, id, done)
	reviewer = CleanName(reviewer)
	if not reviewer or not Wanted.CanPublish(reviewer) then return false, "reviewer" end
	local s, found = Store(false), nil
	for _, e in ipairs(s and s.evidence or {}) do if e.id == id and not e.void then found = e break end end
	if not found or not found.killerGuid or not found.victimGuid then return false, "evidence" end
	if Clock() - found.at > Wanted.EVIDENCE_AGE - Wanted.GLOBAL_SKEW then return false, "stale" end
	local digest = Digest(table.concat({ found.id, found.at, found.kind, found.action, found.killerGuid, found.victimGuid }, "|"))
	local killer, victim = WireGuid(found.killerGuid), WireGuid(found.victimGuid)
	if not digest or not killer or not victim then return false, "evidence" end
	local body = ("WX~1~%s~%d~%d~%s~%s~%s~%s"):format(digest, found.at, found.month,
		found.kind == "SELF_DEATH" and "S" or "P", found.action == "claim" and "C" or "B", killer, victim)
	local C = ns.Comm
	if not C or not C.Whisper then return false, "transport" end
	return C.Whisper(ns.TellName(reviewer), body, nil, false, false, done)
end

-- The server's "No player named ... is currently playing" (its pattern as Treasury reads it)
-- for a reviewer we have just sent a batch: none of it reached him. Those rows can be sent again,
-- and at once (his intake counted none of them). A reviewer we send sightings to who is offline
-- is not sent any more (SightingNotFound): his lease goes, and what waits for him.
function Wanted.NotFound(text)
	if type(text) ~= "string" or Secret(text) or (next(batches) == nil and next(reviewers) == nil) then return false end
	local T = ns.Treasury
	local pattern = T and T.NotFoundPattern and T.NotFoundPattern()
	local who = pattern and text:match(pattern)
	if not who then return false end
	who = who:lower()
	local s, now, back = Store(false), math.floor(Clock()), false
	for key, batch in pairs(batches) do
		local name = batch.name
		if now - batch.at <= Wanted.SEND_WAIT
			and ((ns.TellName(name) or ""):lower() == who or (ns.DisplayName(name) or ""):lower() == who) then
			for _, id in ipairs(batch.ids) do if sentTo[key] then sentTo[key][id] = nil end end
			batches[key] = nil
			if s and type(s.sentAt) == "table" then s.sentAt[key] = nil end
			back = true
		end
	end
	if next(reviewers) ~= nil and SightingNotFound and SightingNotFound(who) then back = true end
	return back
end

-- (Registered the first time a batch goes, as the Arena's whispers do.)
local function WatchNotFound()
	if watchingNotFound then return end
	watchingNotFound = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) Wanted.NotFound(text) end)
end

-- The Send evidence button: rows not yet sent to that reviewer this session, one target's or
-- all, at most what his intake takes from one sender in a window (REVIEW_RATE_MAX; more would be
-- dropped on his side), and the next batch SEND_WAIT later: before, false, "wait", seconds left.
-- When that batch went is kept in the saved data, so that a reload does not cut the wait short.
-- A row whose whisper failed, or that the server could not deliver (Wanted.NotFound), can be
-- sent again. Returns how many went, or false, why.
function Wanted.SendEvidence(reviewer, targetKey)
	reviewer = CleanName(reviewer)
	if not reviewer or not Wanted.CanPublish(reviewer) then return false, "reviewer" end
	local rows = Sendable(targetKey)
	if #rows == 0 then return false, "evidence" end
	local who, s, now = ns.Fold(reviewer), Store(false), math.floor(Clock())
	local done = sentTo[who] or {}
	sentTo[who] = done
	local unsent = false
	for _, e in ipairs(rows) do if not done[e.id] then unsent = true break end end
	if not unsent then return false, "sent" end
	if type(s.sentAt) ~= "table" then s.sentAt = {} end
	local last = Whole(s.sentAt[who], 0, 4294967295)
	if last and now - last < Wanted.SEND_WAIT and last <= now then return false, "wait", Wanted.SEND_WAIT - (now - last) end
	local batch = { name = reviewer, at = now, ids = {} }
	local sent, why = 0, nil
	for _, e in ipairs(rows) do
		if sent >= math.min(Wanted.SEND_BATCH, Wanted.REVIEW_RATE_MAX) then break end
		local id = e.id
		if not done[id] then
			done[id] = true
			local ok, refused = Wanted.SubmitEvidence(reviewer, id, function(went)
				-- His window runs from the last whisper that actually went.
				if went and batches[who] == batch and type(s.sentAt) == "table" then
					s.sentAt[who] = math.max(Whole(s.sentAt[who], 0, 4294967295) or 0, math.floor(Clock()))
				elseif not went then done[id] = nil end
			end)
			if not ok then done[id] = nil why = refused or "transport" break end
			sent, batch.ids[#batch.ids + 1] = sent + 1, id
		end
	end
	if sent == 0 then return false, why or "sent" end
	batches[who], s.sentAt[who] = batch, now
	WatchNotFound()
	s.reviewer = reviewer
	return sent
end

function Wanted.ReviewInbox()
	local out = {}
	for _, key in ipairs(reviewOrder) do
		local e = reviewInbox[key]
		if e then local c = {} for k, v in pairs(e) do c[k] = v end out[#out + 1] = c end
	end
	return out
end

local function Unlist(key)
	reviewInbox[key] = nil
	for i, reviewKey in ipairs(reviewOrder) do
		if reviewKey == key then table.remove(reviewOrder, i) break end
	end
end

function Wanted.Review(key, accept)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	local e = reviewInbox[key]
	if not e or e.state ~= "pending" then return false, "missing" end
	if accept == true then
		-- Two accounts of one death with different killers: the reviewer keeps one. To take the
		-- other instead, he withdraws the one he accepted first (Wanted.Withdraw).
		if ConflictOf(e, true) then return false, "conflict" end
		local added, why = LedgerAdd(e)
		if not added then return false, why or "ledger" end
		local row = LedgerFind(Ledger(false), key)
		if row then row.reviewedAt, row.reviewedBy = math.floor(Clock()), CleanName(ns.me) end
	end
	-- Rejected, untrusted submissions do not consume the bounded inbox forever. An accepted row
	-- leaves it too: it is in the ledger now (sent again, it is "reviewed"), and the inbox's bounds
	-- are on what still waits for the reviewer, not on what he took.
	Unlist(key)
	stats.reviewed = stats.reviewed + 1
	Changed()
	return true
end

-- The reviewer takes back a row he accepted (not one already folded into the base). The signed
-- top three changes only when he publishes again.
function Wanted.Withdraw(key)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	local l = Ledger(false)
	local row, i = LedgerFind(l, key)
	if not row then return false, "missing" end
	table.remove(l.accepted, i)
	Changed()
	return true
end

-- The accepted rows (copies, newest first) and how many older ones folded into the base.
function Wanted.Ledger()
	local l, out = Ledger(false), {}
	for i = #(l and l.accepted or {}), 1, -1 do
		local c = {} for k, v in pairs(l.accepted[i]) do c[k] = v end out[#out + 1] = c
	end
	return out, l and l.folded or 0
end

-- The reviewer's cumulative all-time top three: his ledger's base plus every row he accepted,
-- in the order the deaths happened. It survives reloads with the ledger.
local function ReviewedMonths(source)
	local out, now = {}, MonthNow()
	for month, v in pairs(type(source) == "table" and source or {}) do
		if Whole(month, now - Wanted.MAX_MONTHS + 1, now) and type(v) == "table"
			and Whole(v.points, 1, Wanted.MAX_POINTS) and Whole(v.claims, 0, Wanted.MAX_POINTS)
			and Whole(v.reachedAt, 0, 4294967295) then
			out[month] = { points = v.points, claims = v.claims, reachedAt = v.reachedAt }
		end
	end
	return out
end
function Wanted.ReviewedRankings(month)
	if month ~= nil and not Whole(month, 0, 120000) then return {} end
	local l = Ledger(false)
	local targets, slayers, deaths = {}, {}, {}
	if l then
		for guid, points in pairs(l.base.targets) do
			if Guid(guid) and Whole(points, 1, Wanted.MAX_POINTS) then targets[guid] = points end
		end
		for guid, r in pairs(l.base.slayers) do
			if Guid(guid) and type(r) == "table" and Whole(r.points, 1, Wanted.MAX_POINTS) then
				slayers[guid] = { guid = guid, points = r.points, claims = Whole(r.claims, 0, Wanted.MAX_POINTS) or 0,
					reachedAt = Whole(r.reachedAt, 0, 4294967295) or 0, months = ReviewedMonths(r.months) }
			end
		end
		for key, at in pairs(l.base.deaths) do if type(key) == "string" and Whole(at, 0, 4294967295) then deaths[key] = at end end
		for _, e in ipairs(l.accepted) do ApplyReviewed(targets, slayers, deaths, e) end
	end
	local rows = {}
	for guid, row in pairs(slayers) do
		local m = month and row.months and row.months[month]
		if not month then rows[#rows + 1] = row
		elseif m then rows[#rows + 1] = { guid = guid, points = m.points, claims = m.claims, reachedAt = m.reachedAt } end
	end
	table.sort(rows, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.guid < b.guid
	end)
	while #rows > Wanted.GLOBAL_ROWS do table.remove(rows) end
	return CanonicalRows(rows) or {}
end

local function ParseSnapshot(sender, text)
	if type(text) ~= "string" or #text > 1200 then return nil, "size" end
	local version, scope, issuer, epoch, seq, issued, expires, rowsText, pk64, sig64 =
		text:match("^WY~(%d+)~(%x+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)$")
	epoch, seq, issued, expires = tonumber(epoch), tonumber(seq), tonumber(issued), tonumber(expires)
	issuer = CleanName(issuer)
	if version ~= "1" or not issuer or not Whole(epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or not Whole(seq, 1, Wanted.GLOBAL_MAX_SEQ)
		or not Whole(issued, 0, 4294967295) or not Whole(expires, 0, 4294967295) then return nil, "shape" end
	if scope ~= Scope() then return nil, "scope" end
	if not SameName(sender, issuer) or not Wanted.CanPublish(sender) then return nil, "authority" end
	local rows, why = ReadRows(rowsText)
	if not rows then return nil, why end
	local D, Ed = ns.Debts, ns.Ed25519
	local pk = D and D.UnB64 and D.UnB64(pk64) or nil
	local sig = D and D.UnB64 and D.UnB64(sig64) or nil
	if not pk or #pk ~= 32 or not sig or #sig ~= 64 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk) then return nil, "signature" end
	local signed = table.concat({ "OLYW1", scope, issuer, epoch, seq, issued, expires, rowsText }, "|")
	return { scope = scope, issuer = issuer, epoch = epoch, seq = seq, issued = issued, expires = expires,
		rows = rows, rowsText = rowsText, pk = pk, pk64 = pk64, sig = sig, signed = signed, text = text }
end

local function NewerSnapshot(snapshot)
	local head = publisherHeads[ns.Fold(snapshot.issuer)]
	if head then
		if snapshot.epoch < head.epoch then return false, "rollback" end
		if snapshot.epoch == head.epoch and snapshot.seq <= head.seq then return false, "replay" end
		if snapshot.epoch == head.epoch and snapshot.pk64 ~= head.pk64 then return false, "key" end
	end
	if CompareOrder(Order(snapshot), globalFloor) <= 0 then return false, "rollback" end
	return true
end

-- The order (Order) of the word a WY body carries, read from its fields, or nil.
local function BodyOrder(body)
	if type(body) ~= "string" then return nil end
	local issuer, epoch, seq, issued = body:match("^WY~%d+~%x+~([^~]+)~(%d+)~(%d+)~(%d+)~")
	if not issuer then return nil end
	return Order({ issued = tonumber(issued), issuer = issuer, epoch = tonumber(epoch), seq = tonumber(seq) })
end

-- A word this client checked that is newer than the one published here replaced ours for good:
-- ours is not repeated any more, after a reload neither. (A client that never heard the newer
-- word would take ours, the older, from the repeat: an issuer's revocation undone by another's
-- older word.)
local function NoteReplaced(snapshot)
	local p = publishedGlobal
	local mine = p and not p.replaced and BodyOrder(p.body)
	if not mine or CompareOrder(Order(snapshot), mine) <= 0 then return end
	p.replaced = true
	local last = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if type(last) == "table" and last.body == p.body then last.replaced = true end
end

local function Install(snapshot)
	globalFloor = Order(snapshot)
	authenticatedGlobal = snapshot
	NoteReplaced(snapshot)
	Changed()
	if ns.After then
		local held = snapshot
		ns.After(math.max(1, snapshot.expires - math.floor(Clock()) + 1), "wanted global expiry", function()
			if authenticatedGlobal == held and not Fresh(held) then ClearGlobal(true) end
		end)
	end
	return true
end

local function AcceptSnapshot(snapshot)
	-- Recheck every mutable trust input after the asynchronous Ed25519 job. In particular, a
	-- realm/faction transition while verification yielded must never install the old scope.
	if snapshot.scope ~= Scope() or not Fresh(snapshot) or not Wanted.CanPublish(snapshot.issuer) then return false, "stale" end
	local ok, why = NewerSnapshot(snapshot)
	if not ok then return false, why end
	publisherHeads[ns.Fold(snapshot.issuer)] = { epoch = snapshot.epoch, seq = snapshot.seq, pk64 = snapshot.pk64 }
	stats.globalAccepted = stats.globalAccepted + 1
	Install(snapshot)
	SaveGlobal(snapshot)
	return true
end

-- After a load, and again while no word is shown (a change of authority or realm group): the
-- saved word comes back only once its signature holds again under the key pinned for its
-- issuer, unexpired, of this realm group and faction, from someone who holds the role now. Its
-- order and pins hold while the signature is checked, so a live replay of an older word cannot
-- slip in meanwhile; a newer live word simply wins. Nothing else saved ever shows a frame.
local function RestoreGlobal()
	if authenticatedGlobal or restoring then return false, "held" end
	local s = Store(false)
	local saved = s and s.global
	if type(saved) ~= "table" then return false, "none" end
	local snapshot, why = ParseSnapshot(saved.issuer, saved.text)
	if not snapshot then
		-- Not a role holder here now, or another realm group's word: kept for a later look.
		if why ~= "authority" and why ~= "scope" then ForgetGlobal() end
		return false, why
	end
	if not Fresh(snapshot) then ForgetGlobal() return false, "stale" end
	local pins = {}
	for who, h in pairs(type(s.globalHeads) == "table" and s.globalHeads or {}) do
		local epoch = type(h) == "table" and Whole(h.epoch, 1, Wanted.GLOBAL_MAX_EPOCH)
		local seq = type(h) == "table" and Whole(h.seq, 1, Wanted.GLOBAL_MAX_SEQ)
		if type(who) == "string" and epoch and seq and type(h.pk64) == "string" then pins[who] = { epoch = epoch, seq = seq, pk64 = h.pk64 } end
	end
	local pin = pins[ns.Fold(snapshot.issuer)]
	if not pin or pin.epoch ~= snapshot.epoch or pin.seq ~= snapshot.seq or pin.pk64 ~= snapshot.pk64 then
		ForgetGlobal()
		return false, "key"
	end
	local floor = Order(snapshot)
	globalFloor, publisherHeads, restoring = floor, pins, snapshot
	local function Done(valid)
		if restoring ~= snapshot then return false, "superseded" end
		restoring = nil
		restoreChecked[snapshot.text] = valid
		local current = not authenticatedGlobal and globalFloor == floor
		if valid and current and snapshot.scope == Scope() and Fresh(snapshot) and Wanted.CanPublish(snapshot.issuer) then
			stats.globalRestored = stats.globalRestored + 1
			return Install(snapshot)
		end
		if not valid then ForgetGlobal(snapshot.text) stats.globalRefused = stats.globalRefused + 1 end
		if current then globalFloor, publisherHeads = nil, {} end
		return false, valid and "stale" or "signature"
	end
	if restoreChecked[snapshot.text] ~= nil then return Done(restoreChecked[snapshot.text]) end
	local Ed = ns.Ed25519
	local started = Ed and Ed.Run and Ed.Verify and not (Ed.Busy and Ed.Busy() >= 40) and Ed.Run(function()
		return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig)
	end, function(jobOk, valid) Done(jobOk and valid == true) end)
	if not started then
		if restoring == snapshot then restoring, globalFloor, publisherHeads = nil, nil, {} end
		return false, "busy"
	end
	return true, "pending"
end
Wanted.RestoreGlobal = RestoreGlobal

function Wanted.HandleGlobalSnapshot(dist, sender, text)
	if dist ~= "CHANNEL" then stats.globalRefused = stats.globalRefused + 1 return false, "lane" end
	CurrentGlobal() -- expiry/revocation must release its ordering floor before a replacement arrives
	local snapshot, why = ParseSnapshot(sender, text)
	if not snapshot or not Fresh(snapshot) then stats.globalRefused = stats.globalRefused + 1 return false, why or "stale" end
	local ok
	ok, why = NewerSnapshot(snapshot)
	if not ok then
		if why == "replay" or why == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
		stats.globalRefused = stats.globalRefused + 1
		return false, why
	end
	local digest = Digest(snapshot.signed .. snapshot.pk64 .. tostring(text:match("([^~]+)$") or ""))
	if not digest or pendingGlobal[digest] or pendingGlobalCount >= Wanted.GLOBAL_MAX_VERIFY then return false, pendingGlobal[digest] and "pending" or "busy" end
	local Ed = ns.Ed25519
	if not Ed or not Ed.Run or Ed.Busy and Ed.Busy() >= 40 then return false, "busy" end
	pendingGlobal[digest], pendingGlobalCount = snapshot, pendingGlobalCount + 1
	local started = Ed.Run(function() return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig) end, function(jobOk, valid)
		pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1)
		if jobOk and valid == true then
			local accepted, refused = AcceptSnapshot(snapshot)
			if not accepted then
				if refused == "replay" or refused == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
				stats.globalRefused = stats.globalRefused + 1
			end
		else stats.globalRefused = stats.globalRefused + 1 end
	end)
	if not started then pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1) return false, "busy" end
	return true, "pending"
end

local function PublishRows(rows)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	rows = CanonicalRows(rows)
	if not rows then return false, "rows" end
	local D, C = ns.Debts, ns.Comm
	local _, pk
	if D and D.MyKey then _, pk = D.MyKey() end
	local Ed = ns.Ed25519
	if type(pk) ~= "string" or #pk ~= 32 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk)
		or not D.Sign or not D.B64 or not C or not C.SendChunked then return false, "key" end
	local now = math.floor(Clock())
	if type(ns.db) ~= "table" then return false, "store" end
	local p = type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher or {}
	local pk64 = D.B64(pk)
	local epoch = Whole(p.epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or math.min(now, Wanted.GLOBAL_MAX_EPOCH)
	-- A regenerated account key starts a new epoch automatically. Within one epoch receivers pin
	-- the first public key, so an edited packet cannot swap it underneath an accepted publisher.
	if type(p.pk64) == "string" and p.pk64 ~= pk64 then
		if epoch >= Wanted.GLOBAL_MAX_EPOCH then return false, "sequence" end
		epoch = math.max(epoch + 1, math.min(now, Wanted.GLOBAL_MAX_EPOCH))
	end
	if epoch > now + Wanted.GLOBAL_SKEW then return false, "epoch" end
	local seq = epoch == p.epoch and p.pk64 == pk64 and (tonumber(p.seq) or 0) + 1 or 1
	if seq > Wanted.GLOBAL_MAX_SEQ then return false, "sequence" end
	local rowsText, issuer, scope = RowsText(rows), CleanName(ns.me), Scope()
	local expires = now + Wanted.GLOBAL_LIFE
	local signed = table.concat({ "OLYW1", scope, issuer, epoch, seq, now, expires, rowsText }, "|")
	local sig = D.Sign(signed)
	if type(sig) ~= "string" or #sig ~= 64 then return false, "key" end
	p.epoch, p.seq, p.pk64 = epoch, seq, pk64
	ns.db.wantedPublisher = p
	local body = table.concat({ "WY", 1, scope, issuer, epoch, seq, now, expires, rowsText, pk64, D.B64(sig) }, "~")
	publishedGlobal = { body = body, expires = expires, issuer = issuer, scope = scope }
	local sent, why = C.SendChunked(body, true, nil, nil, { owner = Wanted, key = "wanted-global", guard = function()
		return Wanted.CanPublish(ns.me) and ns.IsMember and ns.IsMember() == true
	end })
	if sent then
		-- Kept, so that after his next login the publisher repeats this same word (Wanted.Load).
		p.last = { body = body, expires = expires, issuer = issuer, scope = scope }
		if ScheduleGlobalRepeat then ScheduleGlobalRepeat(publishedGlobal) end
		-- Our own message never comes back to us (Comm drops our echo): the word is taken here as
		-- heard from ourselves, through every check another client makes, so that the publisher's
		-- own client shows it (or, a revocation, stops showing the frames) as everyone's does.
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, body)
	end
	return sent, why
end

-- What this reviewer last published here (for his review page), or nil.
function Wanted.LastPublished()
	local p = publishedGlobal
	if not p then
		local saved = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
		p = type(saved) == "table" and saved.scope == Scope() and SameName(saved.issuer, ns.me) and saved or nil
	end
	if not p or type(p.body) ~= "string" then return nil end
	local issued, expires, rowsText = p.body:match("^WY~%d+~%x+~[^~]+~%d+~%d+~(%d+)~(%d+)~([^~]+)~")
	local rows = rowsText and ReadRows(rowsText) or nil
	return { issued = tonumber(issued), expires = tonumber(expires), rows = rows or {} }
end

-- The public publication path is deliberately tied to rows this client explicitly reviewed.
-- An authority may publish an empty reviewed table or use RevokeGlobal for an emergency removal,
-- but no caller can hand this API an arbitrary scoreboard.
function Wanted.PublishGlobal()
	return PublishRows(Wanted.ReviewedRankings())
end

function Wanted.RevokeGlobal()
	return PublishRows({})
end

-- Repeats the same signed word for late logins; it never extends its expiry or silently turns a
-- stale review into a fresh one. A caller/timer may invoke this while the publisher stays online.
-- A word replaced is not repeated: by a newer one this client checked (NoteReplaced), or by the
-- saved one it is checking again after a load (its floor is newer than ours).
function Wanted.RepeatGlobal()
	local p, C = publishedGlobal, ns.Comm
	local mine = p and BodyOrder(p.body)
	if not mine or p.expires < math.floor(Clock()) or not SameName(p.issuer, ns.me) or not Wanted.CanPublish(ns.me)
		or (p.scope and p.scope ~= Scope()) or not C or not C.SendChunked then return false, "stale" end
	if p.replaced or globalFloor and CompareOrder(globalFloor, mine) > 0 then return false, "replaced" end
	local sent, why = C.SendChunked(p.body, false, nil, nil, { owner = Wanted, key = "wanted-global-repeat", guard = function()
		return publishedGlobal == p and not p.replaced and p.expires >= math.floor(Clock()) and Wanted.CanPublish(ns.me)
	end })
	-- Heard from ourselves again where this client does not hold it (its check was busy when he
	-- published, say), as PublishRows does.
	if sent and not restoring and not (authenticatedGlobal and authenticatedGlobal.text == p.body) then
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, p.body)
	end
	return sent, why
end

-- GLOBAL_BURST repeats GLOBAL_BURST_GAP apart, then one every GLOBAL_REPEAT_EVERY, for as long
-- as this word is the one published, has not expired and was not replaced (a tick while the role
-- is not known sends nothing and waits for the next one).
ScheduleGlobalRepeat = function(p, n)
	if not ns.After then return end
	n = n or 0
	ns.After(n < Wanted.GLOBAL_BURST and Wanted.GLOBAL_BURST_GAP or Wanted.GLOBAL_REPEAT_EVERY, "wanted global repeat", function()
		if publishedGlobal ~= p or p.replaced or p.expires < math.floor(Clock()) then return end
		if Wanted.CanPublish(ns.me) then Wanted.RepeatGlobal() end
		ScheduleGlobalRepeat(p, n + 1)
	end)
end

-- Pure deterministic assignment used by the future authoritative publication: the current
-- all-time first, second and third get distinct keys; everyone else is absent (revoked).
function Wanted.BorderAssignments(rows)
	local ranked = type(rows) == "table" and rows or {}
	local out = {}
	for i = 1, math.min(3, #ranked) do
		local r = ranked[i]
		if type(r) == "table" and type(r.key) == "string" then out[r.key] = "wanted-slayer-" .. i end
	end
	return out
end

function Wanted.GlobalBorder(name, guid)
	if Wanted.GLOBAL_BORDERS_ACTIVE ~= true then return nil end
	local snapshot = CurrentGlobal()
	local key = GuidKey(guid)
	if not snapshot or not key then return nil end -- never award a global frame by a name alone
	return Wanted.BorderAssignments(snapshot.rows)[key]
end

function Wanted.GlobalSnapshot()
	local s = CurrentGlobal()
	if not s then return nil end
	return { issuer = s.issuer, epoch = s.epoch, seq = s.seq, issued = s.issued, expires = s.expires,
		rows = CopyList(s.rows, Wanted.GLOBAL_ROWS) }
end

function Wanted.Icon()
	local UI = ns.UI
	return UI and UI.FirstTexture and UI.FirstTexture(Wanted.ICON_PATHS) or Wanted.ICON_PATHS[#Wanted.ICON_PATHS]
end

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local PLACE = { "|cffffd200#1|r", "|cffc7c7cf#2|r", "|cffb07a45#3|r" }

local function Display(identity)
	return identity.name and ((ns.DisplayName and ns.DisplayName(identity.name)) or ns.ShortName(identity.name) or identity.name)
		or L.WANTED_UNKNOWN
end

local function EvidenceLabel(kind)
	return kind == "PARTY_KILL" and L.WANTED_EVIDENCE_PARTY or kind == "SELF_DEATH" and L.WANTED_EVIDENCE_RECAP or L.WANTED_UNKNOWN
end

local function TargetTip(t)
	return function(tt)
		tt:AddLine(Display(t), 1, 0.82, 0)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current), 1, 1, 1)
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills), 0.8, 0.8, 0.8)
		if t.lastSighting then
			local precision = t.lastSighting.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE
			tt:AddLine(L.WANTED_LAST_SIGHTING:format(t.lastSighting.zone or L.WANTED_UNKNOWN, precision, ns.Ago(t.lastSighting.at)), 0.8, 0.8, 0.8, true)
		end
		for _, v in ipairs(t.victims) do
			tt:AddLine(L.WANTED_VICTIM_TIP:format(v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN,
				v.zone or L.WANTED_UNKNOWN, EvidenceLabel(v.evidence), ns.Ago(v.at)), 1, 1, 1, true)
		end
		if t.victimOverflow > 0 then tt:AddLine(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow), 0.7, 0.7, 0.7) end
	end
end

function Wanted.OpenTarget(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not t then return false end
	mode, opened = "target", t.key
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

-- The reviewer's page (the King, a signed High Councillor or the author): what waits for him,
-- what he accepted, and the top three he would sign.
function Wanted.OpenReview()
	if not Wanted.CanPublish(ns.me) then return false end
	mode, opened = "review", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.Back()
	if mode == "list" then return false end
	mode, opened = "list", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.PageId()
	if mode == "target" then return "target:" .. tostring(opened) end
	return mode == "review" and "review" or "list"
end

local function OpenSlayer(r)
	if not (r and r.name and ns.UI and ns.UI.ShowPerson) then return false end
	return ns.UI.ShowPerson({ name = ns.ShortName(r.name), realm = ns.RealmOf(r.name), source = "addon", at = r.lastAt })
end

local function Red(s) return "|cffff4040" .. tostring(s or "") .. "|r" end

-- A GUID as a name a person can read: what this client knows of it (its slayers, its targets,
-- the game's own lookup through Debts.InfoName), else the GUID itself.
local function GuidName(guid)
	guid = Guid(guid)
	if not guid then return L.WANTED_UNKNOWN end
	local s, key = Store(false), GuidKey(guid)
	local known = s and (s.slayers[s.slayerAliases[key] or key] or s.targets[s.aliases[key] or key]) or nil
	local name = type(known) == "table" and known.name or nil
	if not name then
		local D = ns.Debts
		local ok, info = false, nil
		if type(D) == "table" and type(D.InfoName) == "function" then ok, info = pcall(D.InfoName, guid) end
		name = ok and type(info) == "string" and info ~= "" and not Secret(info) and info or nil
	end
	return name and (ns.DisplayName and ns.DisplayName(name) or name) or guid
end

local function DaysLeft(expires)
	return math.max(0, math.ceil(((tonumber(expires) or 0) - Clock()) / 86400))
end

local function IssuerName(name) return ns.DisplayName and ns.DisplayName(name) or name end

local function RankingLines(lines, title, rows)
	lines[#lines + 1] = { header = true, text = title }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } return end
	for i, r in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, key = r.key, player = r.name,
			text = (PLACE[i] or ("#" .. i)) .. "  " .. (r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN),
			right = L.WANTED_POINTS:format(r.points), onClick = r.name and function() return OpenSlayer(r) end or nil,
			tooltip = function(tt)
				tt:AddLine(r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(r.points, r.claims), 1, 1, 1, true)
			end }
	end
end

-- The signed all-time top three this client holds (the one that sets the frames), if any.
local function SignedLines(lines)
	local g = Wanted.GlobalSnapshot()
	if not g then return false end
	lines[#lines + 1] = { header = true, text = L.WANTED_SIGNED, right = Grey(L.WANTED_SIGNED_BY:format(IssuerName(g.issuer), ns.Ago(g.issued))) }
	if #g.rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_SIGNED_EMPTY) } end
	for i, row in ipairs(g.rows) do
		local name = GuidName(row.guid)
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. name,
			right = L.WANTED_POINTS:format(row.points), tooltip = function(tt)
				tt:AddLine(name, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(row.points, row.claims), 1, 1, 1, true)
				tt:AddLine(L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)), 0.8, 0.8, 0.8, true)
			end }
	end
	lines[#lines].gapAfter = true
	return true
end

local function ListLines()
	local lines, targets = {}, Wanted.Targets(true)
	lines[#lines + 1] = { header = true, text = L.WANTED_TARGETS, right = Grey(tostring(#targets)) }
	if #targets == 0 then lines[#lines + 1] = { text = Grey(L.WANTED_EMPTY) } end
	for _, t in ipairs(targets) do
		lines[#lines + 1] = { id = "wanted:" .. t.key, key = t.key, text = Display(t),
			right = L.WANTED_ROW_COUNTS:format(t.current, t.lifetimeKills), onClick = function() return Wanted.OpenTarget(t) end,
			tooltip = TargetTip(t) }
	end
	lines[#lines].gapAfter = true
	local signed = SignedLines(lines)
	-- This client's own two boards: what it observed, never everyone's ranking (only the signed
	-- top three above is that).
	local rank = Wanted.Rankings()
	local year, month = math.floor(rank.monthNo / 12), rank.monthNo % 12 + 1
	RankingLines(lines, L.WANTED_MONTHLY:format(year, month), rank.month)
	lines[#lines].gapAfter = true
	RankingLines(lines, L.WANTED_LOCAL_ALL, rank.all)
	if not signed then lines[#lines + 1] = { text = Grey(L.WANTED_AUTHORITY_OFF), gapAfter = true } end
	return lines
end

local function LiveEvidence(id)
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do if e.id == id and not e.void then return true end end
	return false
end

-- A Watch moderator or the author voids a row still live (not yet checkpointed), with a reason.
local function CorrectClick(id, label)
	if not (id and Wanted.CanManage() and LiveEvidence(id)) then return nil end
	return function() return ns.ShowDialog("OLYMPUS_WANTED_CORRECT", label, nil, id) end
end

local function TargetLines()
	local s, t = Store(false), nil
	if s and opened then t = s.targets[s.aliases[opened] or opened] end
	if not t then mode, opened = "list", nil return ListLines() end
	t = PublicTarget(t)
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back },
		{ header = true, text = Display(t), right = t.active and Green(L.WANTED_LISTED) or Grey(L.WANTED_REMOVED) },
		{ indent = 1, text = L.WANTED_GUID:format(t.guid or L.WANTED_UNKNOWN) },
		{ indent = 1, text = L.WANTED_BOUNTY:format(t.current), right = L.WANTED_LIFETIME:format(t.lifetimeKills) },
		{ indent = 1, text = L.WANTED_CYCLE:format(t.cycle, t.openSince and ns.Ago(t.openSince) or L.WANTED_UNKNOWN) },
	}
	if t.lastSighting then
		local precision = t.lastSighting.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE
		lines[#lines + 1] = { indent = 1, text = L.WANTED_LAST_SIGHTING:format(t.lastSighting.zone or L.WANTED_UNKNOWN, precision,
			ns.Ago(t.lastSighting.at)) }
	end
	lines[#lines + 1] = { header = true, text = L.WANTED_OPEN_CYCLE }
	if #t.victims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_VICTIMS) } end
	for _, v in ipairs(t.victims) do
		local label = v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN
		lines[#lines + 1] = { indent = 1, text = label, right = Grey(ns.Ago(v.at)), onClick = CorrectClick(v.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_EVIDENCE, 1, 0.82, 0)
				tt:AddLine(EvidenceLabel(v.evidence), 1, 1, 1, true)
				tt:AddLine(L.WANTED_LOCATION:format(v.zone or L.WANTED_UNKNOWN, v.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE),
					0.8, 0.8, 0.8, true)
			end }
	end
	if t.victimOverflow > 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow)) } end
	lines[#lines + 1] = { header = true, text = L.WANTED_CLAIMS }
	if #t.claims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_CLAIMS) } end
	for i = #t.claims, 1, -1 do
		local c = t.claims[i]
		local label = c.slayer and (ns.DisplayName(c.slayer) or c.slayer) or L.WANTED_UNKNOWN
		lines[#lines + 1] = { indent = 1, text = label, right = L.WANTED_CLAIM_POINTS:format(c.points or 0), onClick = CorrectClick(c.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_CLAIM_TIP:format(c.points or 0, c.cycle or 0, EvidenceLabel(c.evidence), ns.Ago(c.at)), 1, 1, 1, true)
			end }
	end
	return lines
end

local function ReviewSummary(e)
	return (e.action == "claim" and L.WANTED_CLAIM_LINE or L.WANTED_BOUNTY_LINE):format(GuidName(e.killerGuid), GuidName(e.victimGuid))
end

local function ReviewTip(e, conflict)
	return function(tt)
		tt:AddLine(ReviewSummary(e), 1, 0.82, 0, true)
		tt:AddLine(L.WANTED_REVIEW_TIP:format(EvidenceLabel(e.kind), IssuerName(e.from or L.WANTED_UNKNOWN), ns.Ago(e.at)), 1, 1, 1, true)
		tt:AddLine(L.WANTED_GUIDS:format(e.killerGuid, e.victimGuid), 0.7, 0.7, 0.7, true)
		if conflict then tt:AddLine(L.WANTED_CONFLICT, 1, 0.25, 0.25, true) end
	end
end

local function ReviewLines()
	if not Wanted.CanPublish(ns.me) then mode, opened = "list", nil return ListLines() end
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back } }
	local pending = {}
	for _, e in ipairs(Wanted.ReviewInbox()) do if e.state == "pending" then pending[#pending + 1] = e end end
	lines[#lines + 1] = { header = true, text = L.WANTED_PENDING, right = Grey(tostring(#pending)) }
	if #pending == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_PENDING) } end
	for _, e in ipairs(pending) do
		local conflict = ConflictOf(e) ~= nil
		local summary = ReviewSummary(e)
		lines[#lines + 1] = { indent = 1, id = "wanted-review:" .. e.key, text = (conflict and Red("! ") or "") .. summary,
			right = Grey(ns.Ago(e.at)), tooltip = ReviewTip(e, conflict),
			onClick = function() return ns.ShowDialog("OLYMPUS_WANTED_REVIEW", summary, nil, e.key) end }
	end
	lines[#lines].gapAfter = true
	local accepted, folded = Wanted.Ledger()
	lines[#lines + 1] = { header = true, text = L.WANTED_ACCEPTED, right = Grey(tostring(#accepted + folded)) }
	if #accepted + folded == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_ACCEPTED) } end
	for i = 1, math.min(#accepted, Wanted.REVIEW_SHOWN) do
		local e = accepted[i]
		local summary = ReviewSummary(e)
		lines[#lines + 1] = { indent = 1, id = "wanted-ledger:" .. e.key, text = summary, right = Grey(ns.Ago(e.at)),
			tooltip = ReviewTip(e, false), onClick = function() return ns.ShowDialog("OLYMPUS_WANTED_WITHDRAW", summary, nil, e.key) end }
	end
	local older = math.max(0, #accepted - Wanted.REVIEW_SHOWN) + folded
	if older > 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_OLDER_ACCEPTED:format(older)) } end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.WANTED_TO_PUBLISH }
	local rows = Wanted.ReviewedRankings()
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } end
	for i, row in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. GuidName(row.guid),
			right = L.WANTED_POINTS:format(row.points) }
	end
	local last = Wanted.LastPublished()
	lines[#lines + 1] = { indent = 1, text = Grey(last and last.issued and L.WANTED_LAST_PUBLISHED:format(ns.Ago(last.issued), DaysLeft(last.expires))
		or L.WANTED_NOT_PUBLISHED) }
	return lines
end

function Wanted.Build()
	if mode == "review" then
		local lines = ReviewLines()
		if mode == "review" then return lines, L.WANTED_REVIEW_TITLE, L.WANTED_REVIEW_ABOUT end
		return lines, L.WANTED_TITLE, L.WANTED_ABOUT
	end
	local lines = mode == "target" and TargetLines() or ListLines()
	local g = Wanted.GlobalSnapshot()
	local note = g and L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)) or L.WANTED_AUTHORITY_OFF
	return lines, L.WANTED_TITLE, L.WANTED_ABOUT .. "\n" .. Grey(note)
end

local function PromptAdd()
	if not Wanted.CanManage() then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_ADD")
end

local function PromptRemove()
	if not Wanted.CanManage() or not opened then return false end
	local s = Store(false)
	local t = s and s.targets[s.aliases[opened] or opened]
	if not (s and t) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REMOVE", Display(t), nil, t.key)
end

-- The open target's key (its current one), or nil on the list.
local function OpenedKey()
	local s = Store(false)
	if mode ~= "target" or not (s and opened) then return nil end
	local t = s.targets[s.aliases[opened] or opened]
	return t and t.key or nil
end

local function HasSendable()
	local key = OpenedKey()
	if mode == "target" and not key then return false end
	return #Sendable(key) > 0
end

local function PromptSend()
	if not HasSendable() then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_SEND", nil, nil, OpenedKey())
end

local function PendingCount()
	local n = 0
	for _, key in ipairs(reviewOrder) do
		local e = reviewInbox[key]
		if e and e.state == "pending" then n = n + 1 end
	end
	return n
end

local function RowsSummary(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = ("#%d %s · %s"):format(i, GuidName(row.guid), L.WANTED_POINTS:format(row.points)) end
	return #out > 0 and table.concat(out, "\n") or L.WANTED_SIGNED_EMPTY
end

local function PromptPublish()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_PUBLISH", RowsSummary(Wanted.ReviewedRankings()))
end

local function PromptRevoke()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REVOKE")
end

local function Failed(why) ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end

local function Focus(eb)
	if ns.Focus then ns.Focus(eb) elseif eb.SetFocus then eb:SetFocus() end
end

StaticPopupDialogs["OLYMPUS_WANTED_ADD"] = {
	text = L.WANTED_ADD_PROMPT, button1 = ADD or "Add", button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 72,
	-- (Focus: with the gamepad UI, never the keyboard taken from another box, the chat's.)
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); Focus(eb) end end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		local text = eb and eb:GetText() or ""
		local ok, why
		if text:gsub("%s", "") == "" then ok, why = Wanted.AddTargetUnit("target")
		else ok, why = Wanted.AddTarget(text) end
		if not ok then ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local text = self:GetText() or ""
		local ok, why
		if text:gsub("%s", "") == "" then ok, why = Wanted.AddTargetUnit("target")
		else ok, why = Wanted.AddTarget(text) end
		if not ok then ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_REMOVE"] = {
	text = L.WANTED_REMOVE_PROMPT, button1 = REMOVE or "Remove", button2 = CANCEL or "Cancel",
	OnAccept = function(self, key)
		key = key or (self and self.data)
		local s = Store(false)
		local t = s and s.targets[s.aliases[key] or key]
		local ok, why
		if t then ok, why = Wanted.RemoveTarget(t) else ok, why = false, "missing" end
		if not ok then ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Send evidence: to the reviewer typed (prefilled with the last one), this target's rows or all.
local function SendTo(name, key)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then return Failed("reviewer") end
	local reviewer = ns.FullName and ns.FullName(name) or name
	local sent, why, wait = Wanted.SendEvidence(reviewer, key)
	if not sent and why == "wait" then return ns.Print(L.WANTED_SEND_WAIT:format(wait or Wanted.SEND_WAIT)) end
	if not sent then return Failed(why) end
	ns.Print(L.WANTED_SENT:format(sent, IssuerName(CleanName(reviewer) or reviewer)))
end

StaticPopupDialogs["OLYMPUS_WANTED_SEND"] = {
	text = L.WANTED_SEND_PROMPT, button1 = L.WANTED_SEND_ACCEPT, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 72,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		local s = Store(false)
		if eb then eb:SetText(s and s.reviewer and (ns.TellName(s.reviewer) or s.reviewer) or ""); Focus(eb) end
	end,
	OnAccept = function(self, key)
		local eb = self.editBox or self.EditBox
		SendTo(eb and eb:GetText() or "", key)
	end,
	EditBoxOnEnterPressed = function(self, key)
		local parent = self:GetParent()
		SendTo(self:GetText() or "", key)
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- A pending row: Accept (into the ledger), Reject (gone), or Later (it stays pending).
StaticPopupDialogs["OLYMPUS_WANTED_REVIEW"] = {
	text = L.WANTED_REVIEW_PROMPT, button1 = L.WANTED_ACCEPT_BTN, button2 = L.WANTED_LATER_BTN, button3 = L.WANTED_REJECT_BTN,
	OnAccept = function(self, key)
		local ok, why = Wanted.Review(key or (self and self.data), true)
		if not ok then Failed(why) end
	end,
	OnAlt = function(self, key)
		local ok, why = Wanted.Review(key or (self and self.data), false)
		if not ok then Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_WITHDRAW"] = {
	text = L.WANTED_WITHDRAW_PROMPT, button1 = L.WANTED_WITHDRAW_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function(self, key)
		local ok, why = Wanted.Withdraw(key or (self and self.data))
		if not ok then Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_PUBLISH"] = {
	text = L.WANTED_PUBLISH_PROMPT, button1 = L.WANTED_PUBLISH_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.PublishGlobal()
		if ok then ns.Print(L.WANTED_PUBLISHED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_REVOKE"] = {
	text = L.WANTED_REVOKE_PROMPT, button1 = L.WANTED_REVOKE_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.RevokeGlobal()
		if ok then ns.Print(L.WANTED_REVOKED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_CORRECT"] = {
	text = L.WANTED_CORRECT_PROMPT, button1 = L.WANTED_CORRECT_BTN, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 80,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); Focus(eb) end end,
	OnAccept = function(self, id)
		local eb = self.editBox or self.EditBox
		local ok, why = Wanted.Correct(id or (self and self.data), eb and eb:GetText() or "")
		if not ok then Failed(why) end
	end,
	EditBoxOnEnterPressed = function(self, id)
		local parent = self:GetParent()
		local ok, why = Wanted.Correct(id or (parent and parent.data), self:GetText() or "")
		if not ok then Failed(why) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local buttons = {
	{ "WANTED_BACK_BTN", Wanted.Back, shown = function() return mode ~= "list" end },
	{ "WANTED_ADD_BTN", PromptAdd, shown = function() return mode == "list" and Wanted.CanManage() end },
	{ "WANTED_REVIEW_BTN", Wanted.OpenReview, shown = function() return mode == "list" and Wanted.CanPublish(ns.me) end,
		label = function()
			local n = PendingCount()
			return n > 0 and L.WANTED_REVIEW_BTN_COUNT:format(n) or L.WANTED_REVIEW_BTN
		end },
	{ "WANTED_SEND_BTN", PromptSend, shown = function() return mode ~= "review" and HasSendable() end },
	{ "WANTED_REMOVE_BTN", PromptRemove, shown = function() return mode == "target" and Wanted.CanManage() end },
	{ "WANTED_PUBLISH_BTN", PromptPublish, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
	{ "WANTED_REVOKE_BTN", PromptRevoke, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
}
Wanted.buttons = buttons -- (tests)

---------------------------------------------------------------------------
-- Most Wanted sightings
--
-- A sighting is what this client saw itself: a Horde player its own list names, or a hostile one
-- flagged for PvP (never one of an Olympus guild unless listed), by his name and GUID as the game
-- gives them (a secret value is refused), and where this player stood then: his own map position,
-- rounded to SIGHT_GRID thousandths of the map, and his layer when Layers knows it. "Seen nearby":
-- never the Horde player's own coordinates. On for members by default, off by their No (the
-- privacy page, /oly sightings off), which stops collecting, cancels what waits in Comm and takes
-- back what reached a reviewer, at once. The privacy page asks it like its other lines until it is
-- answered (on meanwhile), so a member who answered the others before is shown it too. It is a
-- line of its own: it goes whatever the member answered about his zone and layer (Layers.Sharing),
-- and says so. The King's position is his crown on the map (King.SharingLocation, as for his
-- layer): while it is hidden his client sends none, and hiding it takes back what went. Nothing
-- is collected in an instance, nor by a client the moderators took off (net-off).
-- It shows on this client's own map, and goes where this member's evidence goes (WX): to the one
-- reviewer (the King, a signed High Councillor, the author) he sends it to (Wanted.SendEvidence),
-- by whisper only, never on the channel, and only while that reviewer's client says it takes
-- sightings (its lease: no place in it); a member who sent evidence to nobody sends his sightings
-- to nobody. SIGHT_SEND_MAX a window from this client, each Horde player once per SIGHT_GAP.
-- Comm checks each whisper again when it leaves (the No, net-off, the crown, the reviewer's
-- lease, its age).
--   WS~R~1                                                             channel: a reviewer's lease
--   WS~R~0                                                             channel: his No (lease off)
--   WS~S~1~<guild>~<id>~<at>~<map>~<x>~<y>~<layer>~<guid>~<name>       whisper: one sighting
--   WS~X~1                                                             whisper: the sender's taken back
-- A reviewer takes one only while his own sightings are on, from a member of an Olympus guild (as
-- the Olympus chats verify one), fresh (SIGHT_TTL, GLOBAL_SKEW), once (its id, per sender),
-- SIGHT_RECV_MAX a window from one sender and SIGHT_INTAKE_MAX from all (counted before anything
-- is parsed). A client without WS (1.1.4, or 1.2 before it) ignores every one of these words.
-- A pin is one Horde player where he was seen last, SIGHT_TTL long, SIGHT_PINS at most; its hover
-- says his name, his kills by this client's Most Wanted ledger, how long ago and by whom. Nothing
-- of it is saved. Pins follow the map rules of Olympus's other icons: on the world map only with
-- mouse and keyboard (ns.WorldMapIcons), on the minimap always, for members only, none while this
-- player is in an instance.
---------------------------------------------------------------------------

-- (1.2.0: off until the member's own Yes on its line.)
local function SightingsOn() return type(ns.db) == "table" and ns.db.wantedSightings == true end
Wanted.SightingsOn = SightingsOn
-- (The section's helpers: Wanted.lua's main chunk is near Lua's 200 locals.)
local Sight = {}

-- The moderators took this client off (net-off): it sends none of this.
local function NetOff()
	local M = ns.Moderation
	if type(M) ~= "table" or M.missing or type(M.SelfOff) ~= "function" then return false end
	local ok, off = pcall(M.SelfOff)
	return not ok or (off ~= nil and off ~= false)
end

local function InInstance()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside = pcall(IsInInstance)
	if not ok or Secret(inside) then return true end -- (not known: as if inside)
	return inside == true
end

-- A unit API's first answer, nil when it fails or is secret.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

-- This client collects sightings: a member's, on the Alliance side, not refused, not off.
local function Collects()
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if ns.faction == "Horde" then return false, "faction" end
	if not SightingsOn() then return false, "off" end
	if NetOff() then return false, "netoff" end
	return true
end

-- This client takes sightings: a reviewer's (Wanted.CanPublish), a member's, not off (his own
-- No stops what he takes too), not net-off.
local function TakesSightings()
	return ns.IsMember and ns.IsMember() == true and ns.me ~= nil and ns.faction ~= "Horde"
		and SightingsOn() and Wanted.CanPublish(ns.me) and not NetOff()
end

-- The King's position goes out only while his crown shows on the map (King.SharingLocation), as
-- his zone and layer do (Layers.Sharing): while it is hidden, his client sends no sighting (it
-- still pins what it saw on his own map). Not known (King.lua missing, or failing): hidden for a
-- King's character.
function Sight.CrownHidden()
	local K = ns.King
	if type(K) ~= "table" or K.missing or type(K.IsKing) ~= "function" or type(K.SharingLocation) ~= "function" then
		return ns.IsKingCharacter ~= nil and ns.me ~= nil and ns.IsKingCharacter(ns.me) == true
	end
	local ok, king = pcall(K.IsKing)
	if not ok then return true end
	if king ~= true then return false end
	local okShown, shown = pcall(K.SharingLocation)
	return not okShown or shown ~= true
end

function Sight.GuildName(guild)
	if Secret(guild) or type(guild) ~= "string" or guild == "" or #guild > 48 or guild:find("[~|%c]") then return nil end
	return ns.IsFederation and ns.IsFederation(guild) and guild or nil
end

-- This player's Olympus guild, as the game says it.
function Sight.OwnGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and Sight.GuildName(guild) or nil
end

-- A zone's map (or a smaller one in it): never a continent, the world, or a dungeon's.
function Sight.OpenMap(mapID)
	if not Whole(mapID, 1, 9999999) or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return false end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	if not ok or type(info) ~= "table" or Secret(info.mapType) then return false end
	local T = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or {}
	return info.mapType == (T.Zone or 3) or info.mapType == (T.Micro or 5)
end

function Sight.Grid(v)
	local g = Wanted.SIGHT_GRID
	return math.max(0, math.min(1000, math.floor(v * 1000 / g + 0.5) * g))
end

-- Where this player stands: his map and position there, rounded (Grid), or nil.
function Sight.Spot()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
	local mapID = Ask(C_Map.GetBestMapForUnit, "player")
	if not Sight.OpenMap(mapID) then return nil end
	local pos = Ask(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos then return nil end
	local ok, x, y = pcall(function() return pos:GetXY() end)
	if not ok or Secret(x, y) or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
		or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
	return mapID, Sight.Grid(x), Sight.Grid(y)
end

-- This player's layer on that map when Layers saw it lately, else 0 (not known).
function Sight.MyLayer(mapID)
	local Ly = ns.Layers
	if type(Ly) ~= "table" or Ly.missing or type(Ly.Mine) ~= "function" then return 0 end
	local ok, m = pcall(Ly.Mine)
	local now = ns.Now()
	if not ok or type(m) ~= "table" or m.mapID ~= mapID or not Whole(m.zoneUID, 1, 2147483647) or type(m.t) ~= "number"
		or now - m.t > Wanted.SIGHT_LAYER_FRESH or m.t > now + 5 then return 0 end
	return m.zoneUID
end

-- The unit, when it is a sighting: a Horde player (not us) listed here (true). Only the wanted:
-- nobody else is recorded, sent or pinned. nil, why otherwise (and, for a hostile one flagged for
-- PvP of no Olympus guild, his identity: remembered here as Horde, for one's own death recap).
local function SightedUnit(unit)
	if Ask(UnitIsPlayer, unit) ~= true then return nil, "player" end
	if Ask(UnitFactionGroup, unit) ~= "Horde" then return nil, "faction" end
	local ident = UnitIdentity(unit)
	if not ident or not ident.guid or not ident.name then return nil, "identity" end
	local me = UnitIdentity("player") or Identity(ns.me)
	if me and SameIdentity(me, ident) then return nil, "self" end
	local s = Store(false)
	local t = s and ResolveTarget(s, ident, false)
	if t and t.active then return ident, true end
	if Ask(UnitCanAttack, "player", unit) ~= true or Ask(UnitIsPVP, unit) ~= true then return nil, "unlisted" end
	if type(GetGuildInfo) == "function" then
		local ok, guild = pcall(GetGuildInfo, unit)
		if not ok or Secret(guild) or (type(guild) == "string" and ns.IsFederation and ns.IsFederation(guild)) then return nil, "unlisted" end
	end
	return nil, "unlisted", ident
end

local function SightLive(e, now)
	return now - e.at <= Wanted.SIGHT_TTL and e.at <= now + Wanted.GLOBAL_SKEW
end

-- The newest sighting of each Horde player, SIGHT_PINS of them at most (the oldest go first).
local function Keep(e)
	local old = pins[e.guid]
	if old and old.at > e.at then return false end
	pins[e.guid] = e
	local n = Count(pins)
	while n > Wanted.SIGHT_PINS do
		local oldest
		for guid, p in pairs(pins) do if not oldest or p.at < pins[oldest].at then oldest = guid end end
		pins[oldest], n = nil, n - 1
	end
	return pins[e.guid] == e
end

local function LeaseLive(r, now)
	return type(r) == "table" and now - r.at <= Wanted.REVIEWER_FOR and r.at <= now + Wanted.GLOBAL_SKEW
		and Wanted.CanPublish(r.name)
end

-- Whom a sighting goes to: the reviewer this member sends his evidence to (s.reviewer, set by
-- Wanted.SendEvidence), while his client says it takes them (his lease) and he holds the role;
-- never us, never anyone else. Nobody when this member sent evidence to nobody.
local function Recipients(now)
	local s = Store(false)
	local chosen = s and CleanName(s.reviewer) or nil
	if not chosen or SameName(chosen, ns.me) then return {} end
	local r = reviewers[ns.Fold(chosen)]
	if not LeaseLive(r, now) then return {} end
	return { r.name }
end
Wanted.SightingRecipients = function() return Recipients(math.floor(Clock())) end

local function DropJob(job)
	if sightJobs[job.key] == job then sightJobs[job.key], sightJobCount = nil, sightJobCount - 1 end
end

-- Cancels the sightings waiting in Comm (every one, or one reviewer's: his folded name).
local function CancelSightings(why, onlyTo)
	local list = {}
	for _, job in pairs(sightJobs) do
		if onlyTo == nil or job.toKey == onlyTo then list[#list + 1] = job end
	end
	local C = ns.Comm
	for _, job in ipairs(list) do
		job.cancelled = true
		DropJob(job)
		if type(C) == "table" and type(C.CancelQueued) == "function" then C.CancelQueued(Wanted, job.key, why or "cancelled") end
	end
	stats.sightCancelled = stats.sightCancelled + #list
	return #list
end

-- When Comm is about to send one: still wanted, still allowed, still fresh, still taken.
local function SightPermit(job)
	if sightJobs[job.key] ~= job or job.cancelled then return false, "cancelled" end
	local ok, why = Collects()
	if not ok then return false, why end
	if Sight.CrownHidden() then return false, "crown" end
	local now = math.floor(Clock())
	if now - job.at > Wanted.SIGHT_QUEUE_TTL then return false, "stale" end
	if not LeaseLive(reviewers[job.toKey], now) then return false, "reviewer" end
	return true
end

-- The server's "No player named <reviewer> is currently playing" that answers a whisper this
-- client sent him on its own (a sighting, or taking them back): kept out of the chat frames for
-- SIGHT_QUIET seconds after it went (Wanted.NotFound still reads it, and drops him). The player
-- typed nothing, and a line naming the King out of nowhere says nothing to him. A line for anyone
-- else, or later, shows as ever.
function Wanted.QuietLine(_, _, text)
	if not ns.Gate.Allowed("system-filters") then return false end
	if next(told.quiet) == nil or type(text) ~= "string" or Secret(text) then return false end
	local T = ns.Treasury
	local pattern = T and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	local untilAt = told.quiet[who:lower()]
	local now = math.floor(Clock())
	return untilAt ~= nil and now <= untilAt and untilAt - now <= Wanted.SIGHT_QUIET
end

function Sight.Quiet(name)
	local now = math.floor(Clock())
	for who, untilAt in pairs(told.quiet) do if untilAt < now then told.quiet[who] = nil end end
	for _, shown in ipairs({ ns.TellName and ns.TellName(name), ns.DisplayName and ns.DisplayName(name) }) do
		if type(shown) == "string" and shown ~= "" then told.quiet[shown:lower()] = now + Wanted.SIGHT_QUIET end
	end
	if told.filter or not ns.Gate.Allowed("system-filters") then return end
	local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
	local add = type(U) == "table" and type(U.AddMessageEventFilter) == "function" and U.AddMessageEventFilter
		or rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then return end
	told.filter = true
	pcall(add, "CHAT_MSG_SYSTEM", Wanted.QuietLine) -- gp:system-filters
end

-- A reviewer this client's sightings reached this session (Withdraw takes them back).
function Sight.Told(job)
	if not told.by[job.toKey] then told.by[job.toKey] = { name = job.to, target = job.target } end
	Sight.Quiet(job.to)
end

-- Takes this client's sightings off the maps of the reviewers they reached this session (a No,
-- the King's crown hidden): one whisper each. (A reviewer who logged out since kept none: his
-- pins are his session's.) Returns how many were asked.
function Sight.Withdraw()
	local C = ns.Comm
	local list = {}
	for key, r in pairs(told.by) do list[#list + 1] = { key = key, name = r.name, target = r.target } end
	for key in pairs(told.by) do told.by[key] = nil end
	if type(C) ~= "table" or type(C.Whisper) ~= "function" then return 0 end
	table.sort(list, function(a, b) return a.key < b.key end)
	local n = 0
	for _, r in ipairs(list) do
		local asked = C.Whisper(r.target, "WS~X~1", "wanted-sighting-back:" .. r.key, false, false, function(sent)
			if sent then Sight.Quiet(r.name) end
		end)
		if asked then n = n + 1 end
	end
	return n
end

local function SendSighting(e)
	local C = ns.Comm
	-- (Only through a Comm that can cancel what waits: a No must reach every queued sighting.)
	if type(C) ~= "table" or type(C.Whisper) ~= "function" or type(C.CancelQueued) ~= "function" then return 0, "transport" end
	if Sight.CrownHidden() then return 0, "crown" end
	-- (1.2.0: a sighting carries where this player stands and his layer: none goes while he keeps
	-- his zone and layer private.)
	local Ly = ns.Layers
	if not (type(Ly) == "table" and type(Ly.Sharing) == "function" and Ly.Sharing() == true) then return 0, "private" end
	local guild = Sight.OwnGuild()
	if not guild then return 0, "guild" end
	local now = math.floor(Clock())
	for i = #sightSends, 1, -1 do
		if now - sightSends[i] >= Wanted.SIGHT_WINDOW or sightSends[i] > now then table.remove(sightSends, i) end
	end
	if #sightSends >= Wanted.SIGHT_SEND_MAX then stats.sightRate = stats.sightRate + 1 return 0, "rate" end
	local to = Recipients(now)
	if #to == 0 then return 0, "reviewers" end
	local wire = WireGuid(e.guid)
	if not wire then return 0, "identity" end
	local body = ("WS~S~1~%s~%s~%d~%d~%d~%d~%d~%s~%s"):format(guild, e.id, e.at, e.mapID, e.x, e.y, e.layer, wire, e.name)
	if #body > 255 then return 0, "size" end
	local queued = 0
	for _, name in ipairs(to) do
		if sightJobCount >= Wanted.SIGHT_QUEUE_MAX then break end
		local toKey = ns.Fold(name)
		local key = "wanted-sighting:" .. toKey .. ":" .. e.id
		local target = ns.TellName and ns.TellName(name) or name
		local job = { key = key, toKey = toKey, to = name, target = target, body = body, at = now }
		sightJobs[key], sightJobCount = job, sightJobCount + 1
		local accepted = C.Whisper(target, body, nil, false, false, function(sent)
			DropJob(job)
			if sent then stats.sightSent = stats.sightSent + 1 Sight.Told(job) end
		end, { owner = Wanted, key = key, permit = function(owner, permitKey, dist, permitTarget, msg)
			if owner ~= Wanted or permitKey ~= key or dist ~= "WHISPER" or permitTarget ~= target or msg ~= body then return false, "target" end
			return SightPermit(job)
		end })
		if accepted then queued = queued + 1 else DropJob(job) end
	end
	if queued == 0 then return 0, "queue" end
	sightSends[#sightSends + 1] = now
	WatchNotFound()
	return queued
end

local function RememberOwn(guid, now, mapID)
	if not ownSeen[guid] then ownSeenCount = ownSeenCount + 1 end
	ownSeen[guid] = { at = now, mapID = mapID }
	if ownSeenCount <= Wanted.SIGHT_OWN_MAX then return end
	for key, o in pairs(ownSeen) do
		if now - o.at >= Wanted.SIGHT_GAP or o.at > now then ownSeen[key], ownSeenCount = nil, ownSeenCount - 1 end
	end
	while ownSeenCount > Wanted.SIGHT_OWN_MAX do
		local oldest
		for key, o in pairs(ownSeen) do if not oldest or o.at < ownSeen[oldest].at then oldest = key end end
		ownSeen[oldest], ownSeenCount = nil, ownSeenCount - 1
	end
end

-- What this client sees (a nameplate, its target, the unit under the mouse). Returns true and the
-- sighting, or false and why it is none.
function Wanted.ObserveUnit(unit)
	local ok, why = Collects()
	if not ok then
		-- (1.2.0: sightings wait for a Yes; until one is answered, a hostile Horde player seen is
		-- still remembered here, never sent, for one's own death recap. A No stops that too.)
		if why == "off" and type(ns.db) == "table" and ns.db.wantedSightings == nil and type(unit) == "string" and not InInstance() then
			local _, _, horde = SightedUnit(unit)
			if horde then RememberHorde(horde) end
		end
		return false, why
	end
	if InInstance() then return false, "instance" end
	if type(unit) ~= "string" then return false, "unit" end
	-- A Horde player this client recorded on this map within SIGHT_GAP: dropped before anything
	-- else is asked of the game (nameplates come and go all through a fight).
	local now = math.floor(Clock())
	local last = ownSeen[Guid(Ask(UnitGUID, unit)) or false]
	if last and now - last.at < Wanted.SIGHT_GAP and last.at <= now and type(C_Map) == "table"
		and last.mapID == Ask(C_Map.GetBestMapForUnit, "player") then
		stats.sightRepeat = stats.sightRepeat + 1
		return false, "repeat"
	end
	local ident, listed, horde = SightedUnit(unit)
	if horde then RememberHorde(horde) end
	if not ident then return false, listed end
	RememberHorde(ident)
	local mapID, x, y = Sight.Spot()
	if not mapID then return false, "position" end
	local observer = CleanName(ns.me)
	local id = observer and Digest(table.concat({ "OLYS1", observer, ident.guid, now, mapID, x, y }, "|"))
	if not id then return false, "identity" end
	RememberOwn(ident.guid, now, mapID)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = Sight.MyLayer(mapID),
		at = now, observer = observer, own = true, listed = listed }
	stats.sightSeen = stats.sightSeen + 1
	Keep(e)
	e.sent = SendSighting(e)
	Wanted.RefreshPins()
	return true, e
end

-- The No (or Yes again). Off, at once: no more collecting, what waits in Comm cancelled, what
-- reached a reviewer taken back (Withdraw), every pin off this client's map, and a reviewer stops
-- taking them: his lease goes off on the channel (WS~R~0), so members stop whispering him. On
-- again: a reviewer says at once that he takes them.
function Wanted.SetSightings(on, silent)
	if type(ns.db) ~= "table" then return false end
	on = on == true
	ns.db.wantedSightings = on
	if not on then
		knownHorde = {}
		CancelSightings("off")
		Sight.Withdraw()
		for guid in pairs(pins) do pins[guid] = nil end
		for key in pairs(ownSeen) do ownSeen[key] = nil end
		ownSeenCount = 0
		local C = ns.Comm
		if leaseAt ~= nil and type(C) == "table" and type(C.Send) == "function" then
			leaseAt = nil
			-- (The lease's key: a lease still waiting in Comm is replaced, not sent before it.)
			C.Send("CHANNEL", "WS~R~0", "wanted-reviewer", false, false, nil, { owner = Wanted })
		end
	end
	Wanted.RefreshPins()
	if not silent then ns.Print(on and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF) end
	if on and TakesSightings() and leaseAt == nil then Wanted.AnnounceReviewer() end
	return true
end

-- /oly sightings on | off; alone, says which.
function Wanted.SightingsSlash(rest)
	local word = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	if word == "on" or word == "off" then return Wanted.SetSightings(word == "on") end
	ns.Print(SightingsOn() and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF)
	return true
end

-- The reviewer's lease: "I take sightings", on the channel (no place, no name but his own, which
-- the server stamps). Every client checks his role itself.
function Wanted.AnnounceReviewer()
	local C = ns.Comm
	if not TakesSightings() then return false, "reviewer" end
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	leaseAt = math.floor(Clock())
	return C.Send("CHANNEL", "WS~R~1", "wanted-reviewer", false, false, nil, { owner = Wanted, guard = TakesSightings })
end

local function HeardLease(dist, sender, text)
	if dist ~= "CHANNEL" or (text ~= "WS~R~1" and text ~= "WS~R~0") then return false, "shape" end
	sender = CleanName(sender)
	-- His No: no lease, nothing waiting for him (only his own: the server stamps the sender).
	if text == "WS~R~0" then
		local key = sender and ns.Fold(sender)
		if not key or not reviewers[key] then return false, "unknown" end
		reviewers[key], reviewerCount = nil, reviewerCount - 1
		CancelSightings("reviewer", key)
		return true
	end
	if not sender or SameName(sender, ns.me) or not Wanted.CanPublish(sender) then return false, "authority" end
	local key, now = ns.Fold(sender), math.floor(Clock())
	if not reviewers[key] then
		if reviewerCount >= Wanted.REVIEWERS_MAX then
			local oldest
			for k, r in pairs(reviewers) do if not oldest or r.at < reviewers[oldest].at then oldest = k end end
			reviewers[oldest], reviewerCount = nil, reviewerCount - 1
			CancelSightings("reviewer", oldest)
		end
		reviewerCount = reviewerCount + 1
	end
	reviewers[key] = { key = key, name = sender, at = now }
	stats.leases = stats.leases + 1
	return true
end

-- The server says a reviewer is not online: no lease, nothing waiting for him.
SightingNotFound = function(who)
	local hit = false
	for key, r in pairs(reviewers) do
		if (ns.TellName(r.name) or ""):lower() == who or (ns.DisplayName(r.name) or ""):lower() == who then
			reviewers[key], reviewerCount = nil, reviewerCount - 1
			CancelSightings("offline", key)
			hit = true
		end
	end
	return hit
end

-- The sender speaks for an Olympus guild as the Olympus chats check it (Channels.VerifiedLevel),
-- and the moderators did not take him off.
local function FromOlympian(sender, guild)
	local Ch = ns.Channels
	if type(Ch) ~= "table" or Ch.missing or type(Ch.VerifiedLevel) ~= "function" then return false end
	local ok, level, verified = pcall(Ch.VerifiedLevel, sender, guild)
	if not ok or type(level) ~= "number" or level < 1 or verified ~= true then return false end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local okHides, hidden = pcall(M.Hides, sender, guild)
		if not okHides or hidden then return false end
	end
	return true
end

-- SIGHT_RECV_MAX a window from one sender, SIGHT_INTAKE_MAX from all, SIGHT_SENDERS_MAX counted.
local function SightAdmit(sender, now)
	if now - sightIntake.at >= Wanted.SIGHT_WINDOW or sightIntake.at > now then sightIntake.at, sightIntake.n = now, 0 end
	if sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return false end
	local key = ns.Fold(sender)
	local b = sightFrom[key]
	if not b then
		if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then
			for other, held in pairs(sightFrom) do
				if now - held.at >= Wanted.SIGHT_WINDOW then sightFrom[other], sightFromCount = nil, sightFromCount - 1 end
			end
			if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then return false end
		end
		b = { at = now, n = 0 }
		sightFrom[key], sightFromCount = b, sightFromCount + 1
	elseif now - b.at >= Wanted.SIGHT_WINDOW or b.at > now then
		b.at, b.n = now, 0
	end
	if b.n >= Wanted.SIGHT_RECV_MAX then return false end
	b.n, sightIntake.n = b.n + 1, sightIntake.n + 1
	return true
end

local function RememberSight(key)
	sightSeen[key] = true
	sightSeenOrder[#sightSeenOrder + 1] = key
	while #sightSeenOrder > Wanted.SIGHT_SEEN_MAX do sightSeen[table.remove(sightSeenOrder, 1)] = nil end
end

local function Refuse(why)
	stats.sightRefused = stats.sightRefused + 1
	return false, why
end

-- This window is full (everyone's, or this sender's): checked before anything is parsed.
function Sight.Full(sender, now)
	if now - sightIntake.at < Wanted.SIGHT_WINDOW and sightIntake.at <= now and sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return true end
	local b = sightFrom[ns.Fold(sender)]
	return b ~= nil and now - b.at < Wanted.SIGHT_WINDOW and b.at <= now and b.n >= Wanted.SIGHT_RECV_MAX
end

local function TakeSighting(dist, sender, text)
	if dist ~= "WHISPER" then return Refuse("lane") end
	if not TakesSightings() then return Refuse("reviewer") end
	local cleanSender = CleanName(sender)
	if cleanSender and Sight.Full(cleanSender, math.floor(Clock())) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	if #text > 255 then return Refuse("shape") end
	local version, guild, id, at, mapID, x, y, layer, wire, name =
		text:match("^WS~S~(%d+)~([^~]+)~(%x+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)$")
	at, mapID, x, y, layer = tonumber(at), tonumber(mapID), tonumber(x), tonumber(y), tonumber(layer)
	local guid = GameGuid(wire)
	local ident = guid and Identity(name, guid) or nil
	guild = Sight.GuildName(guild)
	if version ~= "1" or not id or #id ~= 16 or not Whole(at, 0, 4294967295) or not Whole(x, 0, 1000) or not Whole(y, 0, 1000)
		or not Whole(layer, 0, 2147483647) or not Sight.OpenMap(mapID) or not ident or not ident.name or not guild then return Refuse("shape") end
	local now = math.floor(Clock())
	if at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.SIGHT_TTL then return Refuse("stale") end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return Refuse("sender") end
	if not FromOlympian(sender, guild) then return Refuse("olympus") end
	local listed = Store(false)
	listed = listed and ResolveTarget(listed, ident, false)
	if not (listed and listed.active) then return Refuse("unlisted") end
	local key = ns.Fold(sender) .. "#" .. id
	if sightSeen[key] then stats.sightReplay = stats.sightReplay + 1 return false, "replay" end
	if not SightAdmit(sender, now) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	RememberSight(key)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = layer, at = at,
		observer = sender, guild = guild, own = false }
	stats.sightTaken = stats.sightTaken + 1
	Keep(e)
	Wanted.RefreshPins()
	return true, e
end

-- The sender takes his sightings back (his No, or the King's crown hidden): his pins leave this
-- map, whatever this client's own answer. (Only his own: the server stamps the sender.)
function Sight.TakeBack(dist, sender, text)
	if dist ~= "WHISPER" or text ~= "WS~X~1" then return false, "shape" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	local n = 0
	for guid, e in pairs(pins) do
		if not e.own and SameName(e.observer, sender) then pins[guid], n = nil, n + 1 end
	end
	stats.sightWithdrawn = stats.sightWithdrawn + n
	if n > 0 then Wanted.RefreshPins() end
	return true, n
end

function Wanted.HandleSighting(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return false, "shape" end
	local kind = text:match("^WS~(%u)~")
	if kind == "R" then return HeardLease(dist, sender, text) end
	if kind == "S" then return TakeSighting(dist, sender, text) end
	if kind == "X" then return Sight.TakeBack(dist, sender, text) end
	return false, "shape"
end

-- The pins held now (copies), the newest first.
function Wanted.Sightings()
	local now, out = math.floor(Clock()), {}
	for _, e in pairs(pins) do
		if SightLive(e, now) then local c = {} for k, v in pairs(e) do c[k] = v end out[#out + 1] = c end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return a.guid < b.guid
	end)
	return out
end

-- How long ago, in this computer's clock (ns.Ago) from the server's.
local function SightAgo(at)
	return ns.Ago(ns.Now() - math.max(0, math.floor(Clock()) - at))
end

-- A pin's hover: his name, his kills by this client's ledger, when and by whom he was seen, the
-- layer against this player's, and that the spot is where the Olympian stood.
function Wanted.SightingTip(tt, e)
	if type(tt) ~= "table" or type(e) ~= "table" then return false end
	tt:AddLine(Display({ name = e.name }), 1, 0.82, 0)
	local s = Store(false)
	local t = s and ResolveTarget(s, Identity(e.name, e.guid), false)
	if t and t.active then
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current or 0), 0.8, 0.8, 0.8)
	elseif t then
		-- Taken off the list here: his kills stay a fact, no bounty is said.
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_SIGHT_REMOVED, 0.8, 0.8, 0.8, true)
	else
		tt:AddLine(L.WANTED_SIGHT_UNLISTED, 0.8, 0.8, 0.8, true)
	end
	tt:AddLine(L.WANTED_SIGHT_SEEN:format(SightAgo(e.at), e.own and L.WANTED_SIGHT_BY_YOU or IssuerName(e.observer)), 1, 1, 1, true)
	if (e.layer or 0) > 0 then
		local mine = Sight.MyLayer(e.mapID)
		if mine > 0 then tt:AddLine(mine == e.layer and L.WANTED_SIGHT_YOUR_LAYER or L.WANTED_SIGHT_OTHER_LAYER, 0.8, 0.8, 0.8) end
	end
	tt:AddLine(L.WANTED_SIGHT_NEARBY, 0.6, 0.6, 0.6, true)
	return true
end

local function PinEnter(self)
	local e = self and self.sighting and pins[self.sighting]
	if not e or type(GameTooltip) ~= "table" then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	Wanted.SightingTip(GameTooltip, e)
	GameTooltip:Show()
end
local function PinLeave() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

-- A pin's two frames: the world map's badge (Map.Badge: the orc banner in a red disc) and the
-- minimap's icon. nil where the map module or frames are missing.
local function MakeFrames()
	local M = ns.Map
	if type(M) ~= "table" or M.missing or type(M.Badge) ~= "function" or type(M.SetBadge) ~= "function" then return nil end
	local world = M.Badge(Wanted.SIGHT_BADGE, true)
	M.SetBadge(world, Wanted.Icon(), 0.8, 0.12, 0.08)
	world.badge:SetScript("OnEnter", PinEnter)
	world.badge:SetScript("OnLeave", PinLeave)
	local mini = CreateFrame("Frame", nil, UIParent)
	mini.olympus = true -- (ours: photo mode leaves it shown, UI.TogglePhoto)
	mini:SetSize(Wanted.SIGHT_MINI, Wanted.SIGHT_MINI)
	mini.icon = mini:CreateTexture(nil, "OVERLAY")
	mini.icon:SetAllPoints()
	mini.icon:SetTexture(Wanted.Icon())
	mini:EnableMouse(true)
	mini:SetScript("OnEnter", PinEnter)
	mini:SetScript("OnLeave", PinLeave)
	mini:Hide() -- (the pin library shows it when it puts it on the minimap)
	return { world = world, mini = mini }
end

local SIGHT_SHOW = HBD_PINS_WORLDMAP_SHOW_PARENT or 1

local function RefreshPinsNow()
	local now = math.floor(Clock())
	for guid, e in pairs(pins) do
		if not SightLive(e, now) then pins[guid] = nil stats.sightExpired = stats.sightExpired + 1 end
	end
	if next(pins) == nil and next(pinFrames) == nil then return true end -- (nothing to draw or take off)
	local P = ns.Pins and ns.Pins()
	if not P then return false end
	local world = ns.WorldMapIcons(P, Wanted)
	-- This map-menu choice hides only world-map artwork, not consent or minimap sightings.
	if ns.db and ns.db.showWanted == false then
		for _, f in pairs(pinFrames) do
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			f.onWorld = nil
		end
		world = false
	end
	-- Members only, never in an instance.
	local allowed = ns.IsMember ~= nil and ns.IsMember() == true and not InInstance()
	for guid, f in pairs(pinFrames) do
		if not (allowed and pins[guid]) then
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			P:RemoveMinimapIcon(Wanted, f.mini)
			f.world:Hide()
			f.mini:Hide()
			f.onWorld, f.drawn, f.world.badge.sighting, f.mini.sighting = nil, nil, nil, nil
			pinFrames[guid] = nil
			spareFrames[#spareFrames + 1] = f
		end
	end
	if not allowed then return true end
	for guid, e in pairs(pins) do
		local f = pinFrames[guid]
		if not f then
			f = table.remove(spareFrames) or MakeFrames()
			if not f then return false end
			pinFrames[guid] = f
		end
		f.world.badge.sighting, f.mini.sighting, f.world.since = guid, guid, e.at
		-- (With the gamepad UI ns.WorldMapIcons took this module's world icons off already.)
		if not world then f.onWorld = nil end
		if f.drawn ~= e or (world and not f.onWorld) then
			if world then
				P:AddWorldMapIconMap(Wanted, f.world, e.mapID, e.x / 1000, e.y / 1000, SIGHT_SHOW)
				f.onWorld = true
			end
			if f.drawn ~= e then P:AddMinimapIconMap(Wanted, f.mini, e.mapID, e.x / 1000, e.y / 1000, false, false) end
			f.drawn = e
		end
	end
	return true
end

function Wanted.RefreshPins()
	if ns.SafeCall then return ns.SafeCall("wanted pins", RefreshPinsNow) end
	return RefreshPinsNow()
end

-- (Tests: the frames each pin has now.)
function Wanted.PinFrames() return pinFrames end

-- A reviewer's lease is due: he takes sightings and has not said so for a beat (a few seconds'
-- slack: the timer's beat and the role's arrival may come close together).
local function LeaseDue()
	return TakesSightings() and (leaseAt == nil or math.floor(Clock()) - leaseAt >= Wanted.REVIEWER_EVERY - 5)
end

-- The lease, LOGIN's REVIEWER_FIRST later, then every REVIEWER_EVERY while the reviewer stays.
local function ScheduleLease(gen, wait)
	if not ns.After then return end
	ns.After(wait, "wanted reviewer", function()
		if gen ~= leaseGen then return end
		if LeaseDue() then Wanted.AnnounceReviewer() end
		ScheduleLease(gen, Wanted.REVIEWER_EVERY)
	end)
end

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "wantedsightings", label = "CONSENT_WANTED_SIGHTINGS", text = "CONSENT_WANTED_SIGHTINGS_TEXT",
		shown = function() return ns.IsMember() == true and ns.faction ~= "Horde" end,
		get = function() return SightingsOn() end,
		set = function(on) Wanted.SetSightings(on) end,
		-- 1.2.0: off until its own Yes, and asked like the page's other lines until it is answered
		-- (the page opens by itself for it once a session); the bulk Yes never turns it on.
		pending = function() return type(ns.db) == "table" and ns.db.wantedSightings == nil end,
		explicit = true,
	})
end

function Wanted.Prune()
	local s = Store(false)
	if not s then return false end
	for key, t in pairs(s.targets) do
		local ident = type(t) == "table" and Identity(t.name, t.guid, t.realm) or nil
		if not ident or type(key) ~= "string" then
			s.targets[key] = nil
		else
			t.key, t.name, t.guid, t.realm = key, ident.name, ident.guid, ident.realm
			t.active = t.active == true
			t.addedAt = Whole(t.addedAt, 0, 4294967295) or 0
			t.addedBy = CleanName(t.addedBy)
			t.source = "manual"
			local d = TargetDerived(t)
			for field, value in pairs(d) do t[field] = value end
			t.victims, t.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
			if ident.nameKey then s.aliases[ident.nameKey] = key end
			if ident.guidKey then s.aliases[ident.guidKey] = key end
		end
	end
	local evidence, first = {}, math.max(1, #s.evidence - Wanted.MAX_EVIDENCE + 1)
	for i = first, #s.evidence do
		local e = s.evidence[i]
		local id = type(e) == "table" and Clean(e.id, 160) or nil
		local targetKey = type(e) == "table" and type(e.targetKey) == "string" and (s.aliases[e.targetKey] or e.targetKey) or nil
		local target = targetKey and s.targets[targetKey] or nil
		local killer = type(e) == "table" and Identity(e.killerName, e.killerGuid) or nil
		local victim = type(e) == "table" and Identity(e.victimName, e.victimGuid) or nil
		local targetIdentity = e and e.action == "bounty" and killer or victim
		if id and target and killer and killer.name and killer.guid and victim and victim.name and victim.guid
			and (e.kind == "PARTY_KILL" or e.kind == "SELF_DEATH") and (e.action == "bounty" or e.action == "claim")
			and SameIdentity(Identity(target), targetIdentity) and Whole(e.at, 0, 4294967295) and Whole(e.month, 0, 200000) then
			evidence[#evidence + 1] = { id = id, seq = Whole(e.seq, 0, 2147483647) or 0, at = math.floor(e.at), month = math.floor(e.month),
				kind = e.kind, action = e.action, targetKey = targetKey, killerName = killer.name, killerGuid = killer.guid,
				victimName = victim.name, victimGuid = victim.guid, zone = Clean(e.zone, 80),
				precision = e.precision == "consented" and "consented" or "approximate", void = e.void == true,
				correctedAt = Whole(e.correctedAt, 0, 4294967295), correctedBy = CleanName(e.correctedBy),
				correction = Clean(e.correction, 80) }
		end
	end
	s.evidence = evidence
	local order, seen, have = {}, {}, {}
	first = math.max(1, #s.seenOrder - Wanted.MAX_SEEN + 1)
	for i = first, #s.seenOrder do
		local id = Clean(s.seenOrder[i], 160)
		local old = id and s.seen[id]
		if id and not have[id] and type(old) == "table" then
			local at, seq = Whole(old.at, 0, 4294967295), Whole(old.seq, 0, 2147483647)
			if at and seq then order[#order + 1], seen[id], have[id] = id, { at = at, seq = seq }, true end
		end
	end
	s.seenOrder, s.seen = order, seen
	local now = math.floor(Clock())
	for fingerprint, at in pairs(s.recent) do
		if type(fingerprint) ~= "string" or not Whole(at, 0, 4294967295) or now - at > 30 then s.recent[fingerprint] = nil end
	end
	TrimList(s.audit, Wanted.MAX_AUDIT)
	-- The reviewer's ledger, by shape: rows as LedgerRow keeps them, once each, in time order,
	-- within LEDGER_MAX (the overflow folds), and a base of well-formed totals only.
	if type(s.ledger) == "table" then
		local l = Ledger(false)
		local rows, have = {}, {}
		for _, e in ipairs(l.accepted) do
			local row = LedgerRow(e)
			if row and not have[row.key] then rows[#rows + 1], have[row.key] = row, true end
		end
		table.sort(rows, Earlier)
		l.accepted = rows
		while #l.accepted > Wanted.LEDGER_MAX do Fold(l, table.remove(l.accepted, 1)) end
		local b = l.base
		for guid, points in pairs(b.targets) do
			if Guid(guid) ~= guid or not Whole(points, 1, Wanted.MAX_POINTS) then b.targets[guid] = nil end
		end
		for guid, r in pairs(b.slayers) do
			if Guid(guid) ~= guid or type(r) ~= "table" or not Whole(r.points, 1, Wanted.MAX_POINTS) then b.slayers[guid] = nil
			else
				b.slayers[guid] = { guid = guid, points = r.points, claims = Whole(r.claims, 0, Wanted.MAX_POINTS) or 0,
					reachedAt = Whole(r.reachedAt, 0, 4294967295) or 0, months = ReviewedMonths(r.months) }
			end
		end
		for key, at in pairs(b.deaths) do
			if type(key) ~= "string" or #key > 96 or not Whole(at, 0, 4294967295) then b.deaths[key] = nil end
		end
	end
	-- The saved word, by shape only: RestoreGlobal checks everything else before it shows it.
	local g = s.global
	if type(g) ~= "table" or type(g.text) ~= "string" or #g.text > 1200 or type(g.issuer) ~= "string" then s.global = nil end
	if type(s.globalHeads) ~= "table" then s.globalHeads = nil end
	if type(s.reviewer) ~= "string" or not CleanName(s.reviewer) then s.reviewer = nil end
	-- When a batch of evidence last went to each reviewer (SendEvidence's wait): recent ones only.
	if type(s.sentAt) == "table" then
		for who, at in pairs(s.sentAt) do
			if type(who) ~= "string" or not Whole(at, 0, 4294967295) or now - at >= Wanted.SEND_WAIT or at > now then s.sentAt[who] = nil end
		end
	else
		s.sentAt = nil
	end
	Rebuild(s)
	for _, r in pairs(s.slayers) do TrimMonths(r, MonthNow()) end
	return true
end

-- At login: the saved data checked (Prune), the saved word looked at again (RestoreGlobal),
-- and the publisher's own last word repeated once he is back online (the same body and expiry),
-- unless a newer one replaced it. On LOGIN (PLAYER_LOGIN), not INIT (ADDON_LOADED): only then
-- does the client know the character's name (ns.me), and so whether the word is his, and its
-- faction's store (ns.CheckFaction).
function Wanted.Load()
	Wanted.Prune()
	local p = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if not publishedGlobal and type(p) == "table" and type(p.body) == "string" and Whole(p.expires, 0, 4294967295)
		and not p.replaced and p.expires >= math.floor(Clock()) and SameName(p.issuer, ns.me) and p.scope == Scope() then
		local held = { body = p.body, expires = p.expires, issuer = p.issuer, scope = p.scope }
		publishedGlobal = held
		if ns.After then
			ns.After(Wanted.GLOBAL_LOGIN_REPEAT, "wanted global login", function()
				if publishedGlobal ~= held or held.replaced then return end
				Wanted.RepeatGlobal()
				ScheduleGlobalRepeat(held, Wanted.GLOBAL_BURST)
			end)
		end
	end
	-- Once the publisher's own word is known: a newer saved word, checked again, replaces it.
	RestoreGlobal()
	-- Sightings: a reviewer's lease REVIEWER_FIRST after login (his name is known now), then on
	-- its beat; the pins expire on theirs.
	leaseGen = leaseGen + 1
	ScheduleLease(leaseGen, Wanted.REVIEWER_FIRST)
	if ns.Every and not pinTicker then
		pinTicker = true
		ns.Every(Wanted.SIGHT_TICK, "wanted pins", Wanted.RefreshPins)
	end
	return true
end

function Wanted.Stats() return stats end
function Wanted.ResetForTests()
	deathSerial = deathSerial + 1
	knownHorde = {}
	rate, mode, opened = {}, "list", nil
	authenticatedGlobal, globalFloor, publisherHeads = nil, nil, {}
	pendingGlobal, pendingGlobalCount, reviewInbox, reviewOrder = {}, 0, {}, {}
	reviewRate = {}
	publishedGlobal = nil
	restoring, restoreChecked, sentTo, batches = nil, {}, {}, {}
	pins, pinFrames, spareFrames = {}, {}, {}
	sightSeen, sightSeenOrder, ownSeen, ownSeenCount, sightSends = {}, {}, {}, 0, {}
	sightJobs, sightJobCount, sightFrom, sightFromCount, sightIntake = {}, 0, {}, 0, { at = 0, n = 0 }
	told.by, told.quiet = {}, {}
	reviewers, reviewerCount, leaseGen, leaseAt = {}, 0, leaseGen + 1, nil
	for key in pairs(stats) do stats[key] = 0 end
end

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "wanted", label = "TAB_WANTED", after = "realm",
		icon = Wanted.Icon, visible = function() return ns.IsMember and ns.IsMember() end, build = Wanted.Build, buttons = buttons })
end

-- Never COMBAT_LOG_EVENT_UNFILTERED: on Forever it is a restricted event (HasRestrictions in the
-- client's CombatLog API documentation), and an addon's RegisterEvent on it is blocked with the
-- game's "blocked from an action" pop-up at every login (Daniel's test build, taint.log:
-- Frame:RegisterEvent() from this line). Wanted.CaptureCombatLog stays for a source the client
-- allows (the player's own death recap, PLAYER_DEAD below).
-- Unsupported/restricted registration must not abort login; this is not the restricted CLEU.
pcall(ns.RegisterEvent, "PARTY_KILL", Wanted.CapturePartyKill)
ns.RegisterEvent("PLAYER_DEAD", function()
	deathSerial = deathSerial + 1
	local serial = deathSerial
	local captured = ReadSelfDeathRecap()
	-- The native recap may arrive after PLAYER_DEAD. Bounded retries belong to this death
	-- alone, and the native timestamp/identity/fatal checks still run on every attempt.
	if not captured and ns.After and C_DeathRecap and type(C_DeathRecap.HasRecapEvents) == "function" then
		for _, delay in ipairs({ 0.3, 1, 2 }) do
			ns.After(delay, "wanted death recap", function()
				if not captured and serial == deathSerial then captured = ReadSelfDeathRecap() end
			end)
		end
	end
end)
ns.On("LOGIN", Wanted.Load)
-- An expiry or a lost role clears the word shown; a role that came back (the council's list),
-- or another realm group's store, may bring a saved one back.
-- A reviewer whose role came (the council's list) says at once that he takes sightings.
ns.On("DATA_CHANGED", function()
	CurrentGlobal()
	if not authenticatedGlobal then RestoreGlobal() end
	if LeaseDue() then Wanted.AnnounceReviewer() end
end)
-- The King hid his crown: what waits for a reviewer is cancelled, what went is taken back.
ns.On("KING_LOCATION_CHANGED", function()
	if Sight.CrownHidden() and (sightJobCount > 0 or next(told.by) ~= nil) then
		CancelSightings("crown")
		Sight.Withdraw()
	end
end)
-- What this client sees: the nameplates, its target, the unit under the mouse (sightings); the
-- pins follow it in and out of instances.
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Wanted.ObserveUnit(unit) end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Wanted.ObserveUnit("target") end)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Wanted.ObserveUnit("mouseover") end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() Wanted.RefreshPins() end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Wanted.RefreshPins() end)
if ns.Comm and ns.Comm.Handle then
	ns.Comm.Handle("WX", function(dist, sender, text)
		if dist == "WHISPER" and type(text) == "string" then ReviewEvidence(sender, text) end
	end)
	ns.Comm.Handle("WY", function(...) Wanted.HandleGlobalSnapshot(...) end)
	ns.Comm.Handle("WS", function(...) Wanted.HandleSighting(...) end)
end
