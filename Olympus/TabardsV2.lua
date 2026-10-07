local ADDON, ns = ...
local L = ns.L

-- Tabards v2 has two independent, versioned, default-off contracts:
--   * the player's own tabard state; and
--   * a direct observation already obtained by Inspect.lua.
-- Neither contract starts an inspection.  The nearby path is called only from the existing
-- INSPECT_READY completion, so it never adds a second NotifyInspect.  Findings are whispered to
-- the exact, recently authenticated King client; only the nameless collector lease is announced
-- on the federation channel.  A queued whisper is guarded again at Comm's real delivery boundary.

local T = {}
ns.TabardsV2 = T

T.CONTRACT = 2
T.RAW_KEEP = 24 * 60 * 60
T.LEASE_FOR = 10 * 60
T.LEASE_EVERY = 8 * 60
T.SELF_EVERY = 10 * 60
T.NEARBY_MIN = 60
T.MAX_SUBJECTS = 2000
T.MAX_OBSERVERS = 40

local OWNER = {}
local GUARD_SELF, GUARD_NEARBY = "self", "nearby"
local collector -- { name, guild, id, expires }
local ownLease -- { id, expires, announced }
local lastSelf = -math.huge
local lastNearby = {} -- subject -> { t, status }; session-only rate guard

local function DB(create)
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.tabardsV2) ~= "table" then
		if not create then return nil end
		ns.db.tabardsV2 = {}
	end
	return ns.db.tabardsV2
end

local function RDB(create)
	if type(ns.rdb) ~= "table" then return nil end
	if type(ns.rdb.tabardsV2) ~= "table" then
		if not create then return nil end
		ns.rdb.tabardsV2 = {}
	end
	local r = ns.rdb.tabardsV2
	if create then
		r.raw = type(r.raw) == "table" and r.raw or {}
		r.seen = type(r.seen) == "table" and r.seen or {}
	end
	return r
end

local function ConsentEntry(which)
	local d = DB(false)
	local e = d and type(d.consent) == "table" and d.consent[which]
	if type(e) ~= "table" or e.v ~= T.CONTRACT or (e.value ~= true and e.value ~= false) then return nil end
	return e
end

function T.Consent(which)
	local e = (which == "self" or which == "nearby") and ConsentEntry(which) or nil
	if not e then return nil end
	return e.value
end

local function Cancel(which, why)
	if not (ns.Comm and ns.Comm.CancelQueued) then return 0 end
	return ns.Comm.CancelQueued(OWNER, which == "self" and GUARD_SELF or GUARD_NEARBY, why or "revoked")
end

function T.SetConsent(which, on)
	if which ~= "self" and which ~= "nearby" then return false end
	local d = DB(true)
	if not d then return false end
	d.consent = type(d.consent) == "table" and d.consent or {}
	d.consent[which] = { v = T.CONTRACT, value = on and true or false }
	if not on then
		Cancel(which, "revoked")
		if which == "nearby" then wipe(lastNearby) end
	end
	if on and which == "self" then lastSelf = -math.huge; T.SendSelf(true) end
	return true
end

local function CleanField(s, limit)
	if type(s) ~= "string" or s == "" or #s > limit or s:find("[~|%c]") then return nil end
	return s
end

local function CleanGuild(s)
	s = CleanField(s, 72)
	return s and ns.IsFederation(s) and s or nil
end

local function CleanName(s)
	s = CleanField(s, 60)
	if not s then return nil end
	local key = ns.Inspect and ns.Inspect.Key and ns.Inspect.Key(s)
	return type(key) == "string" and key ~= "" and key or nil
end

local function NextSeq()
	local d = DB(true)
	if not d then return nil end
	d.seq = ((tonumber(d.seq) or 0) % 2000000000) + 1
	return d.seq
end

local function FreshCollector()
	if type(collector) ~= "table" or type(collector.name) ~= "string" or type(collector.id) ~= "string" then return nil end
	if ns.Now() >= (tonumber(collector.expires) or 0) or not ns.IsKingCharacter(collector.name)
		or not (ns.King and ns.King.FromKing and ns.King.FromKing(collector.name, collector.guild)) then return nil end
	return collector
end

function T.Collector()
	local c = FreshCollector()
	if not c then return nil end
	return { name = c.name, guild = c.guild, id = c.id, expires = c.expires }
end

local function Permit(which)
	return function(_, _, dist, target)
		if dist ~= "WHISPER" or T.Consent(which) ~= true or not ns.IsMember() then return false, "revoked" end
		local c = FreshCollector()
		if not c or target ~= c.name then return false, "recipient-changed" end
		return true
	end
end

local function Guard(which)
	return { owner = OWNER, key = which == "self" and GUARD_SELF or GUARD_NEARBY, permit = Permit(which) }
end

local function OwnStatus()
	local guild = GetGuildInfo and GetGuildInfo("player")
	local level = UnitLevel and tonumber(UnitLevel("player")) or nil
	if not CleanGuild(guild) or not level or level <= 0 then return "U", level or 0, guild end
	if level < (ns.Inspect and ns.Inspect.MIN_LEVEL or 15) then return "Y", level, guild end
	if type(GetInventoryItemID) ~= "function" then return "U", level, guild end
	local item = GetInventoryItemID("player", INVSLOT_TABARD or 19)
	if item == nil then return "N", level, guild end
	return ns.Inspect and ns.Inspect.GUILD_TABARDS and ns.Inspect.GUILD_TABARDS[item] and "G" or "O", level, guild
end

local VALID_STATUS = { G = true, N = true, O = true, U = true, Y = true }
local function StatusFits(level, status)
	level = tonumber(level)
	if not level or level < 0 or level > 255 or level ~= math.floor(level) or not VALID_STATUS[status] then return false end
	local minimum = ns.Inspect and ns.Inspect.MIN_LEVEL or 15
	if level == 0 then return status == "U" end
	if level < minimum then return status == "Y" or status == "U" end
	return status ~= "Y"
end

function T.SendSelf(force)
	if T.Consent("self") ~= true or not ns.IsMember() or ns.King.IsKing() then return false end
	local c, now = FreshCollector(), ns.Now()
	if not c or (not force and now - lastSelf < T.SELF_EVERY) then return false end
	local status, level, guild = OwnStatus()
	guild = CleanGuild(guild)
	local seq = NextSeq()
	if not guild or not seq or not VALID_STATUS[status] then return false end
	local msg = ("U3~%d~%s~%d~%d~%s~%s"):format(T.CONTRACT, c.id, seq, math.max(0, math.floor(level or 0)), guild, status)
	if #msg > 250 then return false end
	lastSelf = now
	ns.Comm.Whisper(c.name, msg, "tabardv2-self", nil, nil, nil, Guard("self"))
	return true
end

local function StoreObservation(kind, observer, subject, guild, level, status, at, trusted)
	local r = RDB(true)
	if not r then return false end
	local e = r.raw[subject]
	if type(e) ~= "table" then e = { name = subject, observers = {} }; r.raw[subject] = e end
	e.name, e.guild, e.level = subject, guild, level
	e.observers = type(e.observers) == "table" and e.observers or {}
	local record = { by = observer, guild = guild, level = level, status = status, t = at, source = kind,
		trusted = trusted == true or nil }
	if kind == "king" then e.king = record
	elseif kind == "self" then e.self = record
	else
		e.observers[observer] = record
		local list = {}
		for by, o in pairs(e.observers) do
			list[#list + 1] = { by = by, t = tonumber(o.t) or 0, trusted = o.trusted == true }
		end
		if #list > T.MAX_OBSERVERS then
			table.sort(list, function(a, b)
				if a.trusted ~= b.trusted then return a.trusted end
				return a.t > b.t
			end)
			for i = T.MAX_OBSERVERS + 1, #list do e.observers[list[i].by] = nil end
		end
	end
	T.Prune()
	ns.Fire("INSPECT_CHANGED")
	return true
end

-- Called only by Inspect.OnInspectReady after its existing request completed.  It records or sends
-- that result; it never calls Enqueue, Pump or NotifyInspect itself.
function T.Observe(p, direct)
	-- The second argument is supplied only by Inspect.OnInspectReady after the game's matching
	-- INSPECT_READY.  Stored/manual rows and second-hand reports never enter this send path.
	if direct ~= true or type(p) ~= "table" or p.shared or p.reported then return false end
	local name, guild = CleanName(p.name), CleanGuild(p.guild)
	local status = ({ GUILD = "G", NONE = "N", OTHER = "O", UNKNOWN = "U", YOUNG = "Y" })[p.status]
	local level = tonumber(p.level) or 0
	if not name or not guild or not StatusFits(level, status) then return false end
	if ns.King.IsKing() then return StoreObservation("king", ns.FullName(ns.me), name, guild, level, status, ns.Now(), true) end
	if T.Consent("nearby") ~= true or not ns.IsMember() then return false end
	local c, now = FreshCollector(), ns.Now()
	if not c then return false end
	local was = lastNearby[name]
	if was and now - was.t < T.NEARBY_MIN then return false end
	local seq, observerGuild = NextSeq(), CleanGuild(GetGuildInfo and GetGuildInfo("player"))
	if not seq or not observerGuild then return false end
	local msg = ("U4~%d~%s~%d~%s~%s~%d~%s~%s"):format(T.CONTRACT, c.id, seq, name, guild,
		math.max(0, math.floor(level)), status, observerGuild)
	if #msg > 250 then return false end
	lastNearby[name] = { t = now, status = status }
	ns.Comm.Whisper(c.name, msg, "tabardv2-near:" .. name, nil, nil, nil, Guard("nearby"))
	return true
end

local function KnownMember(sender, claimedGuild)
	local own = ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(sender)
	local myGuild = CleanGuild(GetGuildInfo and GetGuildInfo("player"))
	if own ~= nil then return myGuild ~= nil and claimedGuild:lower() == myGuild:lower() end
	-- Moderation.GuildOf is only what this sender claimed in an earlier message.  It is not
	-- membership proof.  Across guilds, require the signed list (or the pinned King), never the
	-- census: two characters could invent a guild and vouch for each other. Ordinary members remain
	-- unknown until a similarly verified membership source exists.
	if not ns.IsFederation(claimedGuild) then return false end
	local rank, source = nil, nil
	if ns.Data and ns.Data.AuthorizedRank then rank, source = ns.Data.AuthorizedRank(sender, claimedGuild) end
	return rank ~= nil and source ~= "census"
end

-- Someone else's tabard is reported only by an officer (captain or above) of a verified guild.
local function KnownOfficer(sender, claimedGuild)
	if not KnownMember(sender, claimedGuild) then return false end
	local rank = ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(sender)
	if rank == nil and ns.Data and ns.Data.AuthorizedRank then rank = ns.Data.AuthorizedRank(sender, claimedGuild) end
	return type(rank) == "number" and rank <= (ns.CAPTAIN_RANK or 1)
end

local function AcceptSequence(sender, lease, seq)
	seq = tonumber(seq)
	if not seq or seq < 1 or seq > 2000000000 or seq ~= math.floor(seq) then return false end
	if not (ns.King.IsKing() and ownLease and ns.Now() < ownLease.expires and lease == ownLease.id) then return false end
	local r = RDB(true)
	local key = ns.FullName(sender)
	local seen = r.seen[key]
	if type(seen) == "table" and seen.lease == lease and seq <= (tonumber(seen.seq) or 0) then return false end
	r.seen[key] = { lease = lease, seq = seq, t = ns.Now() }
	return true
end

function T.HandleSelf(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 250 then return false end
	local version, lease, seq, level, guild, status = text:match("^U3~(%d+)~([%w]+)~(%d+)~(%d+)~([^~]+)~([GNOUY])$")
	level = tonumber(level)
	guild = CleanGuild(guild)
	if tonumber(version) ~= T.CONTRACT or not guild or not ns.IsFederation(guild) or not StatusFits(level, status) then return false end
	local trusted = KnownMember(sender, guild)
	if not AcceptSequence(sender, lease, seq) then return false end
	return StoreObservation("self", ns.FullName(sender), ns.FullName(sender), guild, level, status, ns.Now(), trusted)
end

function T.HandleNearby(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 250 then return false end
	local version, lease, seq, name, guild, level, status, observerGuild =
		text:match("^U4~(%d+)~([%w]+)~(%d+)~([^~]+)~([^~]+)~(%d+)~([GNOUY])~([^~]+)$")
	name, guild, observerGuild = CleanName(name), CleanGuild(guild), CleanGuild(observerGuild)
	level = tonumber(level)
	if tonumber(version) ~= T.CONTRACT or not name or not guild or not observerGuild or not ns.IsFederation(observerGuild)
		or not StatusFits(level, status) then return false end
	local trusted = KnownOfficer(sender, observerGuild)
	if not AcceptSequence(sender, lease, seq) then return false end
	return StoreObservation("nearby", ns.FullName(sender), name, guild, level, status, ns.Now(), trusted)
end

local function NewLeaseId()
	local d = DB(true)
	if not d then return nil end
	d.leaseSeq = ((tonumber(d.leaseSeq) or 0) % 1679615) + 1
	return ns.Codec.Base36(math.floor(ns.Now())) .. ns.Codec.Base36(d.leaseSeq)
end

function T.Announce(force)
	if not ns.King.IsKing() then ownLease = nil return false end
	local now = ns.Now()
	if not force and ownLease and now - (ownLease.announced or 0) < T.LEASE_EVERY then return false end
	local id, guild = NewLeaseId(), CleanGuild(GetGuildInfo("player"))
	if not id or not guild then return false end
	ownLease = { id = id, announced = now, expires = now + T.LEASE_FOR }
	-- No player/subject name is carried by this channel message.
	ns.Comm.Send("CHANNEL", ("U2~%d~%s~%d~%s"):format(T.CONTRACT, id, T.LEASE_FOR, guild), "tabardv2-lease")
	return true
end

function T.HandleLease(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > 160 then return false end
	local version, id, ttl, guild = text:match("^U2~(%d+)~([%w]+)~(%d+)~([^~]+)$")
	ttl, guild = tonumber(ttl), CleanGuild(guild)
	if tonumber(version) ~= T.CONTRACT or not id or #id > 32 or not ttl or ttl < 60 or ttl > T.LEASE_FOR or not guild then return false end
	if not (ns.IsKingCharacter(sender) and ns.King.FromKing(sender, guild)) then return false end
	local name = ns.FullName(sender)
	local changed = not collector or collector.id ~= id or collector.name ~= name
	if changed then
		Cancel("self", "recipient-changed")
		Cancel("nearby", "recipient-changed")
		wipe(lastNearby)
	end
	collector = { name = name, guild = guild, id = id, expires = ns.Now() + ttl }
	if changed then lastSelf = -math.huge; T.SendSelf(true) end
	return true
end

function T.Prune()
	local r = RDB(false)
	if not r then return 0 end
	local now, list, removed = ns.Now(), {}, 0
	for name, e in pairs(type(r.raw) == "table" and r.raw or {}) do
		if type(e) ~= "table" then r.raw[name], removed = nil, removed + 1
		else
			if type(e.observers) ~= "table" then e.observers = {} end
			for by, o in pairs(e.observers) do
				if type(o) ~= "table" or now - (tonumber(o.t) or 0) > T.RAW_KEEP then e.observers[by] = nil end
			end
			for _, key in ipairs({ "king", "self" }) do
				local o = e[key]
				if type(o) ~= "table" or now - (tonumber(o.t) or 0) > T.RAW_KEEP then e[key] = nil end
			end
			local newest, trusted = 0, e.king ~= nil
			if e.king then newest = math.max(newest, e.king.t or 0) end
			if e.self then newest = math.max(newest, e.self.t or 0) end
			for _, o in pairs(e.observers) do
				newest = math.max(newest, o.t or 0)
				if o.trusted == true then trusted = true end
			end
			if newest == 0 then r.raw[name], removed = nil, removed + 1
			else list[#list + 1] = { name = name, t = newest, trusted = trusted } end
		end
	end
	if #list > T.MAX_SUBJECTS then
		table.sort(list, function(a, b)
			if a.trusted ~= b.trusted then return a.trusted end
			return a.t > b.t
		end)
		for i = T.MAX_SUBJECTS + 1, #list do r.raw[list[i].name], removed = nil, removed + 1 end
	end
	for by, seen in pairs(type(r.seen) == "table" and r.seen or {}) do
		if type(seen) ~= "table" or now - (tonumber(seen.t) or 0) > T.RAW_KEEP then r.seen[by] = nil end
	end
	return removed
end

-- The conclusion and its provenance.  A direct King observation is decisive.  Otherwise a
-- negative state needs two independent fresh direct observers and no fresh conflicting state.
-- Self reports are retained and shown as provenance but never count as a second observer.
function T.Conclusion(name)
	name = CleanName(name)
	local r = RDB(false)
	local e = name and r and type(r.raw) == "table" and r.raw[name]
	if type(e) ~= "table" then return nil end
	local now, statuses, guilds, evidence = ns.Now(), {}, {}, {}
	local function Add(o, trusted)
		if type(o) ~= "table" or now - (tonumber(o.t) or 0) > T.RAW_KEEP or not VALID_STATUS[o.status] then return end
		if trusted then
			statuses[o.status] = (statuses[o.status] or 0) + 1
			if type(o.guild) == "string" then guilds[o.guild] = true end
		end
		evidence[#evidence + 1] = { by = o.by, guild = o.guild, level = o.level, status = o.status, t = o.t,
			source = o.source, trusted = trusted == true }
	end
	Add(e.king, true); Add(e.self, false)
	local observers = { N = {}, O = {}, G = {}, U = {}, Y = {} }
	for by, o in pairs(type(e.observers) == "table" and e.observers or {}) do
		local trusted = o and o.trusted == true
		Add(o, trusted)
		if trusted and observers[o.status] and now - (tonumber(o.t) or 0) <= T.RAW_KEEP then observers[o.status][by] = true end
	end
	local kinds = 0
	for status, n in pairs(statuses) do if n > 0 and status ~= "U" then kinds = kinds + 1 end end
	local guildKinds = 0; for _ in pairs(guilds) do guildKinds = guildKinds + 1 end
	local conflict = kinds > 1 or guildKinds > 1
	if e.king and now - (tonumber(e.king.t) or 0) <= T.RAW_KEEP and (e.king.status == "N" or e.king.status == "O") then
		return e.king.status, true, #evidence, conflict, evidence
	end
	for _, status in ipairs({ "N", "O" }) do
		local n = 0; for _ in pairs(observers[status]) do n = n + 1 end
		if n >= 2 and not conflict then return status, true, n, false, evidence end
	end
	if not conflict and statuses.G then return "G", true, statuses.G, false, evidence end
	return "U", false, #evidence, conflict, evidence
end

function T.PublicationList()
	local out, r = {}, RDB(false)
	for name in pairs(r and type(r.raw) == "table" and r.raw or {}) do
		local status, actionable, _, _, evidence = T.Conclusion(name)
		if actionable and (status == "N" or status == "O") then
			local guild
			for _, o in ipairs(evidence or {}) do
				if o.trusted and o.status == status and type(o.guild) == "string" then guild = o.guild break end
			end
			if guild then out[#out + 1] = { name = ns.ShortName(name), guild = guild } end
		end
	end
	table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return out
end

-- Mixed-version migration: before this client has entered the v2 contract/lease, the existing
-- local King's list keeps its old behaviour. Once v2 is in use, even an empty evidence set is a
-- meaningful v2 publication and must not fall back to uncorroborated legacy reports.
function T.Active()
	if ownLease or collector then return true end
	local r = RDB(false)
	return r and type(r.raw) == "table" and next(r.raw) ~= nil or false
end

function T.SurfaceVisible()
	if ns.King.IsKing() or ns.King.Preview() then return true end
	-- A simulated non-King role still obeys the publication gate.  The author's ordinary view
	-- remains a local preview, but selecting Member cannot reveal data a member has not received.
	local view = ns.ViewAs
	if view and view.Available and view.Available() and view.Role and view.Role() ~= "my" then
		if view.Is and (view.Is("king") or view.Is("gm") or view.Is("officer")) then return true end
		return ns.Inspect and ns.Inspect.Shame and ns.Inspect.Shame() ~= nil
	end
	if ns.Roster and ns.Roster.IsOfficer and ns.Roster.IsOfficer() then return true end
	if ns.Workshop and ((ns.Workshop.IsAuthor and ns.Workshop.IsAuthor()) or (ns.Workshop.Preview and ns.Workshop.Preview())) then return true end
	return ns.Inspect and ns.Inspect.Shame and ns.Inspect.Shame() ~= nil
end

function T.Tick()
	T.Prune()
	if ns.King.IsKing() then T.Announce(false) else T.SendSelf(false) end
end

function T.Reset()
	collector, ownLease, lastSelf = nil, nil, -math.huge
	wipe(lastNearby)
end

ns.Comm.Handle("U2", function(...) T.HandleLease(...) end)
ns.Comm.Handle("U3", function(...) T.HandleSelf(...) end)
ns.Comm.Handle("U4", function(...) T.HandleNearby(...) end)

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "tabardselfv2", label = "CONSENT_TABARD_SELF_V2", text = "CONSENT_TABARD_SELF_V2_TEXT",
		get = function() return T.Consent("self") end,
		set = function(on) T.SetConsent("self", on) end,
	})
	ns.Consent.Register({
		key = "tabardnearbyv2", label = "CONSENT_TABARD_NEARBY_V2", text = "CONSENT_TABARD_NEARBY_V2_TEXT",
		get = function() return T.Consent("nearby") end,
		set = function(on) T.SetConsent("nearby", on) end,
	})
end

ns.On("INIT", function() T.Prune() end)
ns.On("LOGIN", function()
	ns.After(5, "tabards v2", function() T.Tick() end)
	ns.Every(60, "tabards v2", function() T.Tick() end)
end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(slot)
	if tonumber(slot) == (INVSLOT_TABARD or 19) then lastSelf = -math.huge; T.SendSelf(true) end
end)
