local ADDON, ns = ...

-- Private, request-bound discovery for the King's layer. Seeing the King's exact nameplate
-- records a fact on this client; it sends nothing by itself. Its remote evidence is short-lived,
-- while its local no/auto policy marker lasts only under the same crown lease and layer. When another player
-- explicitly asks for the King's unknown layer, eligible observers answer that asker alone.
-- The asker waits for at least two independent, verified senders to agree before handing the
-- destination to Hop's existing LQ/LO/LR state machine.
--
--   LY~Q~1~<request>~<crown lease>~<map>                         channel query
--   LY~R~1~<request>~<crown lease>~<map>~<zone UID>~2~<age>     private answer
--   LY~X~1~<request>~<crown lease>                              private withdrawal
--
-- The server stamps every sender. Guild/rank authority is derived locally, never claimed in
-- the payload. Q and R obey Moderation's net-off backstop at the transport boundary; X carries
-- no location and is allowed only to revoke an answer already delivered to that requester.

local Sightings = {}
ns.HopSightings = Sightings

Sightings.VERSION = 1
Sightings.CONFIDENCE = 2
Sightings.CONSENSUS = 2
Sightings.TTL = 20
Sightings.POLICY_TTL = 90 -- covers the causal offer/request chain, but never becomes permanent
Sightings.QUEUE_TTL = 5
Sightings.SETTLE = 3
Sightings.REQUEST_TTL = 8
Sightings.REQUEST_GAP = 20
Sightings.RECEIVE_GAP = 2
Sightings.SEEN_MAX = 96
Sightings.MAX_QUEUED = 8

local active = {}              -- nameplate unit -> generation handed by NAME_PLATE_UNIT_ADDED
local candidates = {}          -- exact King UNITs still present; retried as layer proof matures
local generations = 0
local localSighting             -- this client's direct, private observation
local crownKey, crownEpoch = nil, 0
local revokedLeases, revokedLeaseOrder = {}, {}
local request                   -- this client's one active discovery query
local lastRequestAt = -math.huge
local sequence = math.random and math.random(1, 99999) or 1
local queuedAnswers = {}        -- guard key -> response waiting in Comm
local queuedAnswerCount = 0
local sentAnswers = {}          -- wire key -> response delivered and still revocable
local pendingQueries = {}       -- verified Q words waiting briefly for local layer proof/eligibility
local pendingQueryCount = 0
local receivedAt = {}           -- sender -> last accepted control word
local seenQueries, seenQueryCount = {}, 0
local admitBuckets, admitBucketCount = {}, 0
local admitStats = {}
local stats = { observed = 0, queries = 0, answers = 0, received = 0, consensus = 0,
	withdrawn = 0, cancelled = 0, dropped = {} }

local function Now() return ns.Now() end
local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end
local function Integer(n, low, high)
	n = tonumber(n)
	return n and n == math.floor(n) and n >= low and n <= high and n or nil
end
local function LeaseKey(from, id)
	id = Integer(id, 1, 99999)
	if not id or Secret(from) or type(from) ~= "string" or not ns.IsKingCharacter(from) then return nil end
	return from:lower() .. ":" .. id
end
local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end
local function PlateUnit(unit)
	return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end
local function SelfOff()
	local M = ns.Moderation
	return type(M) == "table" and type(M.SelfOff) == "function" and M.SelfOff() or nil
end
local function Ignored(sender)
	if type(sender) ~= "string" then return true end
	local blocked = ns.db and ns.db.blocked
	if type(blocked) == "table" and blocked[sender:lower()] then return true end
	local api = C_FriendList and C_FriendList.IsIgnored
	if type(api) ~= "function" then return false end
	local ok, ignored = pcall(api, ns.DisplayName(sender))
	return ok and ignored == true
end
local function Fire() ns.Fire("HOP_CHANGED") end
local function GuardedComm()
	local C = ns.Comm
	-- CancelQueued and capability permits shipped together. A client updated without a restart
	-- can still have the older, unguarded transport in memory; never enqueue location evidence
	-- through it because a later opt-out could not stop the queued send.
	return type(C) == "table" and type(C.Send) == "function" and type(C.Whisper) == "function"
		and type(C.CancelQueued) == "function" and C or nil
end

local function GuildField(guild)
	if Secret(guild) or type(guild) ~= "string" then return nil end
	if guild:find("[~|%c]") then return nil end
	return #guild > 0 and #guild <= 48 and ns.IsFederation(guild) and guild or nil
end

-- The sender's guild is server-roster authority for our own guild and fresh, confirmed census
-- authority elsewhere. Ordinary members of another guild are deliberately not inferred.
local function SenderGuild(sender)
	local own = GuildField(type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil)
	local R = ns.Roster
	local fresh = type(R) == "table" and type(R.Fresh) == "function" and R.Fresh() or nil
	if own and fresh == R and type(R.RankOf) == "function" and R.RankOf(sender) ~= nil then
		return own
	end
	local D, found = ns.Data, nil
	if type(D) ~= "table" or type(D.KnownRank) ~= "function" then return nil end
	for guild in pairs(ns.rdb and ns.rdb.guilds or {}) do
		guild = GuildField(guild)
		-- Data.KnownRank deliberately routes our own guild back to Roster.RankOf.  Do not let
		-- that compatibility path re-admit the same stale table rejected above; this loop is
		-- only the independent signed/census authority for other Olympus guilds.
		if guild and (not own or not Same(guild, own)) and D.KnownRank(sender, guild) ~= nil then
			if found and found:lower() ~= guild:lower() then return nil end
			found = guild
		end
	end
	return found
end

local function PruneAdmission(now)
	for wire, t in pairs(seenQueries) do
		if now - t > Sightings.TTL * 3 then
			seenQueries[wire], seenQueryCount = nil, seenQueryCount - 1
		end
	end
	for sender, t in pairs(receivedAt) do
		if now - t > Sightings.TTL * 3 then receivedAt[sender] = nil end
	end
	for sender, bucket in pairs(admitBuckets) do
		if type(bucket) ~= "table" or type(bucket.t) ~= "number" or now - bucket.t > Sightings.TTL * 3 then
			admitBuckets[sender], admitBucketCount = nil, admitBucketCount - 1
		end
	end
	for wire, answer in pairs(sentAnswers) do
		if type(answer) ~= "table" or now - answer.t > Sightings.TTL then sentAnswers[wire] = nil end
	end
end

local function Admit(sender, guild, now)
	local C = ns.Channels
	if type(C) ~= "table" or type(C.Admit) ~= "function" or type(C.VerifiedLevel) ~= "function" then return false end
	local level, verified = C.VerifiedLevel(sender, guild)
	if type(level) ~= "number" or level < 1 or verified ~= true then return false end
	local known = admitBuckets[sender] ~= nil
	if not known and admitBucketCount >= Sightings.SEEN_MAX then return false end
	local accepted = C.Admit(sender, guild, "", now, {
		level = 1, buckets = admitBuckets, stats = admitStats, where = "King sighting",
	})
	if accepted ~= true then
		-- Channels.Admit creates its bucket before authority verification.
		if not known then admitBuckets[sender] = nil end
		return false
	end
	if not known and admitBuckets[sender] then admitBucketCount = admitBucketCount + 1 end
	return true
end

local function SenderAuthority(sender)
	sender = ns.FullName(sender)
	if type(sender) ~= "string" or sender == "" or ns.IsKingCharacter(sender) or Ignored(sender) then return nil end
	local guild = SenderGuild(sender)
	if not guild then return nil end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(sender, guild) then return nil end
	local C = ns.Channels
	if type(C) ~= "table" or type(C.VerifiedLevel) ~= "function" then return nil end
	local level, verified = C.VerifiedLevel(sender, guild)
	if type(level) ~= "number" or level < 1 or verified ~= true then return nil end
	return sender, guild
end

local function VerifiedSender(sender, now)
	local guild
	sender, guild = SenderAuthority(sender)
	if not sender then return nil end
	if not Admit(sender, guild, now) then return nil end
	return sender, guild
end

local function RawCrown()
	local K = ns.King
	local at = type(K) == "table" and type(K.Location) == "function" and K.Location() or nil
	if type(at) ~= "table" or not Integer(at.id, 1, 99999) or not Integer(at.mapID, 1, 9999999)
		or Secret(at.from) or type(at.from) ~= "string" or not ns.IsKingCharacter(at.from) then return nil end
	local leaseKey = LeaseKey(at.from, at.id)
	if not leaseKey or revokedLeases[leaseKey] then return nil end
	return at, leaseKey .. ":" .. at.mapID
end

local function RevokeLease(from, id)
	local key = LeaseKey(from, id)
	if not key or revokedLeases[key] then return false end
	revokedLeases[key] = true
	revokedLeaseOrder[#revokedLeaseOrder + 1] = key
	if #revokedLeaseOrder > Sightings.SEEN_MAX then
		revokedLeases[table.remove(revokedLeaseOrder, 1)] = nil
	end
	return true
end

local function SyncCrown()
	local at, key = RawCrown()
	local changed = key ~= crownKey
	if changed then crownKey, crownEpoch = key, crownEpoch + 1 end
	return at, key, changed
end

local function StrongLayer()
	local layers = ns.Layers
	if type(layers) ~= "table" or type(layers.Mine) ~= "function" or type(layers.CurrentMap) ~= "function" then return nil end
	local mine, now = layers.Mine(), Now()
	local window = tonumber(layers.EVIDENCE_WINDOW) or 15
	if type(mine) ~= "table" or not Integer(mine.mapID, 1, 9999999) or not Integer(mine.zoneUID, 1, 2147483647)
		or mine.mapID ~= layers.CurrentMap() or type(mine.t) ~= "number" or now - mine.t > window
		or type(mine.confirmedAt) ~= "number" or now - mine.confirmedAt < 0 or now - mine.confirmedAt > window then return nil end
	return mine
end

-- The King's own L1 announcement is stronger than discovery. If it appears while Q/R is in
-- flight, it takes over immediately; two observers can never outvote or race the King's word.
local function OfficialLayer(r)
	local L = ns.Layers
	local where = type(L) == "table" and type(L.Of) == "function" and L.Of(r.king, true) or nil
	if type(where) ~= "table" or not Integer(where.mapID, 1, 9999999)
		or not Integer(where.zoneUID, 1, 2147483647) then return nil end
	return where
end

local function ObservationEligible(mapID, zoneUID)
	if type(ns.IsMember) ~= "function" or ns.IsMember() ~= true or SelfOff() then return false, "member" end
	if not (ns.db and ns.db.layerHelp == true) then return false, "consent" end
	if not (ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()) then return false, "private" end
	local mine = StrongLayer()
	if not mine or mine.mapID ~= mapID or mine.zoneUID ~= zoneUID then return false, "layer" end
	return true
end

local function HelperEligible(mapID, zoneUID)
	local eligible, why = ObservationEligible(mapID, zoneUID)
	if not eligible then return false, why end
	if not (ns.Hop and ns.Hop.CanHelpKing and ns.Hop.CanHelpKing(mapID, zoneUID)) then return false, "helper" end
	return true
end

local function QueryEligible(r)
	if request ~= r or r.phase ~= "sending" then return false, "cancelled" end
	if type(ns.IsMember) ~= "function" or ns.IsMember() ~= true or SelfOff() then return false, "member" end
	if (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown()) then return false, "context" end
	if IsInGroup and IsInGroup() then return false, "group" end
	if not (ns.Layers and ns.Layers.CurrentMap and ns.Layers.CurrentMap() == r.mapID) then return false, "map" end
	local at, key = RawCrown()
	if not at or key ~= r.crownKey or at.id ~= r.lease or at.mapID ~= r.mapID or not Same(at.from, r.king) then return false, "lease" end
	if not (ns.Comm and ns.Comm.ChannelReady and ns.Comm.ChannelReady()) then return false, "channel" end
	if not ns.Comm.ChannelName or ns.Comm.ChannelName() ~= r.channel then return false, "moved" end
	if Now() - r.queuedAt > Sightings.QUEUE_TTL then return false, "stale" end
	return true
end

local function CancelJob(job, why)
	if not job or job.cancelled then return false end
	job.cancelled = true
	if job.answer and queuedAnswers[job.guardKey] == job then
		queuedAnswers[job.guardKey], queuedAnswerCount = nil, queuedAnswerCount - 1
	end
	if ns.Comm and ns.Comm.CancelQueued then ns.Comm.CancelQueued(Sightings, job.guardKey, why or "cancelled")
	elseif ns.Comm and ns.Comm.Cancel then ns.Comm.Cancel(Sightings) end
	return true
end

local function CancelAnswers(why)
	local list = {}
	for _, job in pairs(queuedAnswers) do list[#list + 1] = job end
	local changed = false
	for _, job in ipairs(list) do if CancelJob(job, why) then changed = true end end
	return changed
end

local function SendWithdrawal(wire, answer)
	if answer.withdrawing then return end
	answer.withdrawing = true
	-- A withdrawal names no map/layer/guild. Moderation deliberately lets this safety word
	-- leave even when the opt-out that caused it was net-off itself. Keep failed admissions for
	-- the one-second retry instead of pretending a full transport queue revoked the evidence.
	local accepted = ns.Comm.Whisper(answer.target,
		("LY~X~%d~%d~%d"):format(Sightings.VERSION, answer.id, answer.lease),
		("lysx:%s:%d:%d"):format(answer.target:lower(), answer.id, answer.lease), true, false,
		function(sent)
			answer.withdrawing = nil
			if sent and sentAnswers[wire] == answer then
				sentAnswers[wire] = nil
				stats.withdrawn = stats.withdrawn + 1
			end
		end)
	if not accepted then answer.withdrawing = nil end
end

local function WithdrawSent()
	local changed = false
	for wire, answer in pairs(sentAnswers) do
		if not answer.revoked then changed = true end
		answer.revoked = true
		SendWithdrawal(wire, answer)
	end
	return changed
end

local function RetryWithdrawals()
	for wire, answer in pairs(sentAnswers) do
		if answer.revoked then SendWithdrawal(wire, answer) end
	end
end

local function ClearLocal(why)
	if not localSighting and queuedAnswerCount == 0 and not next(sentAnswers) then return false end
	localSighting = nil
	CancelAnswers(why or "invalid")
	WithdrawSent()
	Fire()
	return true
end

local function CancelRequest(why, quiet)
	local r = request
	if not r then return false end
	request = nil
	if r.job then CancelJob(r.job, why or "cancelled") end
	stats.cancelled = stats.cancelled + 1
	if not quiet and why then ns.Print(why) end
	Fire()
	return true
end
Sightings.CancelRequest = CancelRequest

local function FailRequest(message)
	if not CancelRequest(nil, true) then return false end
	if ns.Hop and ns.Hop.DiscoveryFailed then ns.Hop.DiscoveryFailed(message) else ns.Print(message) end
	return true
end

Sightings.CancelPending = function(why)
	local changed = CancelRequest(why, true)
	if ClearLocal(why) then changed = true end
	return changed
end

local function ExactUnit(unit)
	local generation = active[unit]
	candidates[unit] = nil
	if not PlateUnit(unit) or not generation then return nil end
	if type(UnitExists) ~= "function" or type(UnitIsPlayer) ~= "function" or type(UnitGUID) ~= "function"
		or type(UnitFactionGroup) ~= "function" then return nil end
	local exists, player = UnitExists(unit), UnitIsPlayer(unit)
	local guid, faction = UnitGUID(unit), UnitFactionGroup(unit)
	if Secret(exists, player, guid, faction) or exists ~= true or player ~= true or type(guid) ~= "string"
		or not guid:match("^Player%-") or faction ~= ns.faction then return nil end
	if type(ns.UnitFullName) ~= "function" then return nil end
	local ok, name = pcall(ns.UnitFullName, unit)
	local at, key = RawCrown()
	if not ok or Secret(name) or type(name) ~= "string" or not at or not Same(name, at.from)
		or not ns.IsKingCharacter(name) then return nil end
	candidates[unit] = generation
	return at, key
end

function Sightings.Observe(unit)
	local at, key, crownChanged = SyncCrown()
	if crownChanged then ClearLocal("lease") end
	local exact, exactKey = ExactUnit(unit)
	if not exact or exact ~= at or exactKey ~= key then return Drop("unit") end
	local mine = StrongLayer()
	if not mine then return Drop("evidence") end
	local eligible, why = ObservationEligible(mine.mapID, mine.zoneUID)
	if not eligible then return Drop(why) end
	localSighting = { king = at.from, lease = at.id, mapID = mine.mapID, zoneUID = mine.zoneUID,
		at = Now(), crownKey = key, epoch = crownEpoch }
	stats.observed = stats.observed + 1
	Fire()
	return true, "ok"
end

function Sightings.NameplateAdded(unit)
	if not PlateUnit(unit) then return false end
	generations = generations + 1
	local generation = generations
	active[unit] = generation
	local ok = Sightings.Observe(unit)
	if not ok and ns.After then
		ns.After(0, "King nameplate sighting", function()
			if active[unit] == generation then Sightings.Observe(unit) end
		end)
	end
	return ok
end

function Sightings.NameplateRemoved(unit)
	if not PlateUnit(unit) then return false end
	active[unit], candidates[unit] = nil, nil
	return true
end

function Sightings.UnitNameUpdated(unit)
	if not active[unit] then return false end
	return Sightings.Observe(unit)
end

local function AnswerEligible(job)
	if queuedAnswers[job.guardKey] ~= job or job.cancelled then return false, "cancelled" end
	if Now() - job.queuedAt > Sightings.QUEUE_TTL then return false, "stale" end
	local sighting = localSighting
	if sighting ~= job.sighting or Now() - sighting.at > Sightings.TTL then return false, "stale" end
	local at, key = RawCrown()
	if not at or key ~= sighting.crownKey or sighting.epoch ~= crownEpoch or at.id ~= job.lease
		or at.mapID ~= job.mapID or not Same(at.from, sighting.king) then return false, "lease" end
	local target, guild = SenderAuthority(job.target)
	if not target or not Same(target, job.target) or not Same(guild, job.requesterGuild) then return false, "requester" end
	return HelperEligible(job.mapID, job.zoneUID)
end

local function RecheckAnswers()
	local list = {}
	for _, job in pairs(queuedAnswers) do list[#list + 1] = job end
	for _, job in ipairs(list) do
		local eligible, why = AnswerEligible(job)
		if not eligible then CancelJob(job, why) end
	end
end

local function QueueAnswer(target, requesterGuild, id, lease, mapID)
	local comm = GuardedComm()
	if not comm then return Drop("guard") end
	if queuedAnswerCount >= Sightings.MAX_QUEUED then return Drop("capacity") end
	local sighting = localSighting
	if not sighting or sighting.lease ~= lease or sighting.mapID ~= mapID or Now() - sighting.at > Sightings.TTL then return Drop("none") end
	local eligible, why = HelperEligible(sighting.mapID, sighting.zoneUID)
	if not eligible then return Drop(why) end
	local age = math.ceil(math.max(0, Now() - sighting.at)) + Sightings.QUEUE_TTL
	if age > Sightings.TTL then return Drop("stale") end
	local guardKey = table.concat({ "R", target:lower(), id, lease, mapID, sighting.zoneUID }, ":")
	if queuedAnswers[guardKey] then return false, "queued" end
	local msg = ("LY~R~%d~%d~%d~%d~%d~%d~%d"):format(Sightings.VERSION, id, lease, mapID,
		sighting.zoneUID, Sightings.CONFIDENCE, age)
	local job = { answer = true, guardKey = guardKey, target = target, id = id, lease = lease,
		requesterGuild = requesterGuild, mapID = mapID, zoneUID = sighting.zoneUID,
		sighting = sighting, queuedAt = Now(), msg = msg }
	queuedAnswers[guardKey], queuedAnswerCount = job, queuedAnswerCount + 1
	local accepted = comm.Whisper(target, msg, nil, true, false, function(sent, why)
		if queuedAnswers[guardKey] == job then
			queuedAnswers[guardKey], queuedAnswerCount = nil, queuedAnswerCount - 1
		end
		if sent then
			local wire = target:lower() .. ":" .. id .. ":" .. lease
			sentAnswers[wire] = { target = target, id = id, lease = lease, t = Now() }
			stats.answers = stats.answers + 1
		else
			stats.dropped[why or "send"] = (stats.dropped[why or "send"] or 0) + 1
		end
	end, {
		owner = Sightings, key = guardKey,
		permit = function(owner, permitKey, dist, permitTarget, permitMsg)
			if owner ~= Sightings or permitKey ~= guardKey or dist ~= "WHISPER"
				or permitTarget ~= target or permitMsg ~= msg then return false, "target" end
			return AnswerEligible(job)
		end,
	})
	if not accepted and queuedAnswers[guardKey] == job then
		queuedAnswers[guardKey], queuedAnswerCount = nil, queuedAnswerCount - 1
	end
	return accepted and true or false, accepted and "ok" or "queue"
end

local function RemovePendingQuery(wire)
	if not pendingQueries[wire] then return end
	pendingQueries[wire], pendingQueryCount = nil, pendingQueryCount - 1
end

local function ProcessPendingQuery(wire, q)
	if pendingQueries[wire] ~= q then return false, "gone" end
	local now = Now()
	if now - q.t >= Sightings.REQUEST_TTL then RemovePendingQuery(wire); return false, "stale" end
	if not ns.IsMember or ns.IsMember() ~= true or SelfOff() then
		RemovePendingQuery(wire); return false, "member"
	end
	local target, guild = SenderAuthority(q.target)
	if not target or not Same(target, q.target) or not Same(guild, q.guild) then
		RemovePendingQuery(wire); return false, "requester"
	end
	local at = RawCrown()
	-- A temporarily hidden crown may return under the same authenticated lease. Keep the Q only
	-- until its own short request TTL; a different visible lease invalidates it immediately.
	if at and (at.id ~= q.lease or at.mapID ~= q.mapID) then
		RemovePendingQuery(wire); return false, "lease"
	end
	local sighting = localSighting
	if not at or not sighting or sighting.lease ~= q.lease or sighting.mapID ~= q.mapID then return false, "pending" end
	if not HelperEligible(sighting.mapID, sighting.zoneUID) then return false, "pending" end
	local accepted, why = QueueAnswer(target, guild, q.id, q.lease, q.mapID)
	if accepted then RemovePendingQuery(wire); return true, "ok" end
	return false, why
end

local function ProcessPendingQueries()
	local list = {}
	for wire, q in pairs(pendingQueries) do list[#list + 1] = { wire, q } end
	for _, item in ipairs(list) do ProcessPendingQuery(item[1], item[2]) end
end

local function ReceiveQuery(sender, text)
	local version, id, lease, mapID = text:match("^LY~Q~(%d+)~(%d+)~(%d+)~(%d+)$")
	version, id = Integer(version, 1, 9), Integer(id, 1, 99999)
	lease, mapID = Integer(lease, 1, 99999), Integer(mapID, 1, 9999999)
	if version ~= Sightings.VERSION or not id or not lease or not mapID then return Drop("shape") end
	if not ns.IsMember or ns.IsMember() ~= true or SelfOff() then return Drop("member") end
	local at, key = RawCrown()
	if not at or at.id ~= lease or at.mapID ~= mapID then return Drop("lease") end
	local now = Now()
	PruneAdmission(now)
	local verified, guild = VerifiedSender(sender, now)
	if not verified or Same(verified, ns.me) then return Drop("unverified") end
	local wire = table.concat({ verified:lower(), id, lease }, ":")
	if seenQueries[wire] then return Drop("replay") end
	if seenQueryCount >= Sightings.SEEN_MAX or pendingQueryCount >= Sightings.MAX_QUEUED then return Drop("capacity") end
	seenQueries[wire], seenQueryCount = now, seenQueryCount + 1
	local currentAt, currentKey, changed = SyncCrown()
	if changed then ClearLocal("lease") end
	if currentAt ~= at or currentKey ~= key then return Drop("lease") end
	if not localSighting then
		for unit, generation in pairs(candidates) do
			if active[unit] == generation then Sightings.Observe(unit) end
		end
	end
	local q = { target = verified, guild = guild, id = id, lease = lease, mapID = mapID, t = now }
	pendingQueries[wire], pendingQueryCount = q, pendingQueryCount + 1
	local accepted, why = ProcessPendingQuery(wire, q)
	if accepted then return true, why end
	if pendingQueries[wire] == q then return true, "pending" end
	return Drop(why)
end

local function ReceiveAnswer(sender, text)
	local version, id, lease, mapID, zoneUID, confidence, age =
		text:match("^LY~R~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)$")
	version, id = Integer(version, 1, 9), Integer(id, 1, 99999)
	lease, mapID = Integer(lease, 1, 99999), Integer(mapID, 1, 9999999)
	zoneUID = Integer(zoneUID, 1, 2147483647)
	confidence = Integer(confidence, Sightings.CONFIDENCE, Sightings.CONFIDENCE)
	age = Integer(age, Sightings.QUEUE_TTL, Sightings.TTL)
	if version ~= Sightings.VERSION or not id or not lease or not mapID or not zoneUID or not confidence or not age then return Drop("shape") end
	local r = request
	if not r or r.phase ~= "waiting" or id ~= r.id or lease ~= r.lease or mapID ~= r.mapID then return Drop("request") end
	local now = Now()
	if now - r.t >= Sightings.REQUEST_TTL then
		FailRequest(ns.L.HOP_SIGHTING_NONE:format(ns.KingName()))
		return Drop("stale")
	end
	PruneAdmission(now)
	local verified, guild = VerifiedSender(sender, now)
	if not verified or Same(verified, ns.me) then return Drop("unverified") end
	if now - (receivedAt[verified] or -math.huge) < Sightings.RECEIVE_GAP then return Drop("rate") end
	if r.responses[verified] then return Drop("replay") end
	receivedAt[verified] = now
	-- `confidence` and `age` are retained only as bounded wire-compatibility fields. They are
	-- declarations by the remote client, not proof. Freshness comes from receiving this answer
	-- inside our live request; authority comes from two independently identified senders below.
	r.responses[verified] = { sender = verified, guild = guild, zoneUID = zoneUID, receivedAt = now }
	stats.received = stats.received + 1
	Fire()
	return true, "ok"
end

local function ReceiveWithdrawal(sender, text)
	local version, id, lease = text:match("^LY~X~(%d+)~(%d+)~(%d+)$")
	version, id, lease = Integer(version, 1, 9), Integer(id, 1, 99999), Integer(lease, 1, 99999)
	local r = request
	if version ~= Sightings.VERSION or not id or not lease or not r or id ~= r.id or lease ~= r.lease then return Drop("request") end
	sender = ns.FullName(sender)
	if type(sender) ~= "string" or not r.responses[sender] then return Drop("sender") end
	r.responses[sender] = nil
	stats.withdrawn = stats.withdrawn + 1
	Fire()
	return true, "ok"
end

function Sightings.Receive(dist, sender, text)
	if type(text) ~= "string" or Secret(dist, sender, text) then return Drop("lane") end
	local mode = text:match("^LY~([QRX])~")
	if mode == "Q" then
		if dist ~= "CHANNEL" then return Drop("lane") end
		return ReceiveQuery(sender, text)
	elseif mode == "R" or mode == "X" then
		if dist ~= "WHISPER" then return Drop("lane") end
		if mode == "R" then return ReceiveAnswer(sender, text) end
		return ReceiveWithdrawal(sender, text)
	end
	return Drop("shape")
end

function Sightings.Request(king, label)
	if type(king) ~= "table" then return Drop("king") end
	local at, key, changed = SyncCrown()
	if changed then ClearLocal("lease") end
	if not at or (king.character and not Same(at.from, king.character)) then return Drop("lease") end
	if king.mapID and king.mapID ~= at.mapID then return Drop("lease") end
	if not ns.IsMember or ns.IsMember() ~= true then return ns.Print(ns.L.MEMBERS_ONLY) end
	local off = SelfOff()
	if off then return ns.Print(ns.Moderation.YouText(off)) end
	if (IsInInstance and IsInInstance()) then return ns.Print(ns.L.HOP_INSTANCE) end
	if (InCombatLockdown and InCombatLockdown()) then return ns.Print(ns.L.HOP_COMBAT) end
	if IsInGroup and IsInGroup() then return ns.Print(ns.L.HOP_IN_GROUP) end
	if not ns.Layers or not ns.Layers.CurrentMap or ns.Layers.CurrentMap() ~= at.mapID then
		return ns.Print(ns.L.HOP_KING_ELSEWHERE:format(king.label or ns.KingName(), ns.Hop.ZoneName(at.mapID)))
	end
	if request then return ns.Print(ns.L.HOP_BUSY) end
	local now = Now()
	local hopWait = ns.Hop and ns.Hop.WaitLeft and ns.Hop.WaitLeft(now) or 0
	if hopWait > 0 then return ns.Print(ns.L.HOP_WAIT:format(math.ceil(hopWait))) end
	local left = Sightings.REQUEST_GAP - (now - lastRequestAt)
	if left > 0 then return ns.Print(ns.L.HOP_WAIT:format(math.ceil(left))) end
	local comm = GuardedComm()
	if not comm or not comm.ChannelReady or not comm.ChannelReady() then return ns.Print(ns.L.CHAN_NOT_READY) end
	local channel = comm.ChannelName and comm.ChannelName()
	if type(channel) ~= "string" or channel == "" then return ns.Print(ns.L.CHAN_NOT_READY) end
	sequence = sequence % 99999 + 1
	local r = { id = sequence, lease = at.id, mapID = at.mapID, king = at.from, crownKey = key,
		label = label or ns.L.LAYER_OF:format(king.label or ns.KingName()), channel = channel,
		guild = GetGuildInfo("player"), phase = "sending", queuedAt = now, responses = {} }
	local guardKey = table.concat({ "Q", r.id, r.lease, r.mapID }, ":")
	local msg = ("LY~Q~%d~%d~%d~%d"):format(Sightings.VERSION, r.id, r.lease, r.mapID)
	local job = { guardKey = guardKey, msg = msg, request = r }
	r.job, request = job, r
	local accepted = comm.Send("CHANNEL", msg, nil, true, false, function(sent, why)
		if request ~= r or r.phase ~= "sending" then return end
		if not sent then
			request = nil
			stats.dropped[why or "send"] = (stats.dropped[why or "send"] or 0) + 1
			ns.Print(ns.L.HOP_GAVE_UP)
			return Fire()
		end
		r.job, r.phase, r.t, lastRequestAt = nil, "waiting", Now(), Now()
		if ns.Hop and ns.Hop.DiscoverySent then ns.Hop.DiscoverySent() end
		stats.queries = stats.queries + 1
		ns.Print(ns.L.HOP_SIGHTING_ASKING:format(king.label or ns.KingName()))
		Fire()
	end, {
		owner = Sightings, key = guardKey,
		permit = function(owner, permitKey, dist, target, permitMsg)
			if owner ~= Sightings or permitKey ~= guardKey or dist ~= "CHANNEL" or target ~= nil or permitMsg ~= msg then
				return false, "target"
			end
			return QueryEligible(r)
		end,
	})
	if not accepted and request == r and r.phase == "sending" then request = nil end
	Fire()
	return accepted and true or false
end

function Sightings.Requesting() return request ~= nil end

function Sightings.Progress()
	local r = request
	if not r then return nil end
	if r.phase == "sending" then return r.phase, math.max(0, Sightings.QUEUE_TTL - (Now() - r.queuedAt)) end
	if r.phase == "waiting" then return r.phase, math.max(0, Sightings.REQUEST_TTL - (Now() - r.t)) end
	return r.phase, 0
end

-- This is only a local predicate for the existing King-layer no/auto/manual choice. It never
-- supplies Hop.King or a remote destination. Unlike an R, it may outlive the short evidence TTL,
-- but only for a bounded causal window and while the crown lease/local layer remain unchanged.
function Sightings.LocalKingLayer(mapID, zoneUID)
	local sighting = localSighting
	if not sighting or Now() - sighting.at > Sightings.POLICY_TTL
		or sighting.mapID ~= mapID or sighting.zoneUID ~= zoneUID then return false end
	local at, key = RawCrown()
	if not at or key ~= sighting.crownKey or crownEpoch ~= sighting.epoch
		or at.id ~= sighting.lease or at.mapID ~= sighting.mapID
		or not Same(at.from, sighting.king) then return false end
	local L = ns.Layers
	local mine = type(L) == "table" and type(L.Mine) == "function" and L.Mine() or nil
	return type(mine) == "table" and mine.mapID == mapID and mine.zoneUID == zoneUID
		and type(L.CurrentMap) == "function" and L.CurrentMap() == mapID or false
end

local function PruneResponses(r, now)
	local changed = false
	for sender, answer in pairs(r.responses) do
		local verified, guild = SenderAuthority(sender)
		if now - answer.receivedAt > Sightings.REQUEST_TTL or not verified or not Same(guild, answer.guild) then
			r.responses[sender], changed = nil, true
		end
	end
	return changed
end

local function SameObserver(a, b)
	if Same(a, b) then return true end
	local D = ns.Debts
	if type(D) == "table" and type(D.SameOwner) == "function" then
		local ok, same = pcall(D.SameOwner, a, b)
		if not ok then return nil end
		if ok and same == true then return true end
	end
	local A = ns.Alts
	if type(A) == "table" and type(A.Linked) == "function" then
		local ok, linked = pcall(A.Linked, ns.FullName(a))
		if not ok or type(linked) ~= "table" then return nil end
		for _, name in ipairs(linked) do
			if Same(name, b) then return true end
		end
	end
	return false
end

local function Consensus(r)
	local zoneUID, independent = nil, {}
	for _, answer in pairs(r.responses) do
		if zoneUID and zoneUID ~= answer.zoneUID then return nil, "ambiguous" end
		zoneUID = answer.zoneUID
		local distinct = true
		for _, kept in ipairs(independent) do
			if SameObserver(answer.sender, kept.sender) ~= false then distinct = false break end
		end
		if distinct then independent[#independent + 1] = answer end
	end
	if zoneUID and #independent >= Sightings.CONSENSUS then return zoneUID, "ok" end
	return nil, "few"
end

function Sightings.Tick()
	local now = Now()
	PruneAdmission(now)
	RetryWithdrawals()
	local at, key, changed = SyncCrown()
	if changed then
		ClearLocal("lease")
		if request and request.crownKey ~= key then CancelRequest(ns.L.HOP_KING_HIDDEN:format(ns.KingName())) end
	end
	if localSighting then
		local lease = at and key == localSighting.crownKey and crownEpoch == localSighting.epoch
			and at.id == localSighting.lease and at.mapID == localSighting.mapID
			and Same(at.from, localSighting.king)
		local L, mine = ns.Layers, ns.Layers and ns.Layers.Mine and ns.Layers.Mine()
		local here = type(mine) == "table" and mine.mapID == localSighting.mapID
			and mine.zoneUID == localSighting.zoneUID and L.CurrentMap and L.CurrentMap() == mine.mapID
		if not lease or not here or now - localSighting.at > Sightings.POLICY_TTL then
			ClearLocal("invalid")
		else
			local fresh = now - localSighting.at <= Sightings.TTL
				and ObservationEligible(localSighting.mapID, localSighting.zoneUID)
			local helpful = fresh and HelperEligible(localSighting.mapID, localSighting.zoneUID)
			if not helpful then
				local cancelled = CancelAnswers(fresh and "helper" or "stale")
				local withdrawn = WithdrawSent()
				if cancelled or withdrawn then Fire() end
			end
		end
	end
	if not localSighting then
		for unit, generation in pairs(candidates) do
			if active[unit] == generation then Sightings.Observe(unit) else candidates[unit] = nil end
		end
	end
	RecheckAnswers()
	ProcessPendingQueries()
	local r = request
	if not r then return end
	local official = OfficialLayer(r)
	if official then
		CancelRequest(nil, true)
		local ask = ns.Hop.AskDiscovered or ns.Hop.Ask
		return ask(official.mapID, official.zoneUID, r.label)
	end
	if r.phase == "sending" then
		local eligible = QueryEligible(r)
		if not eligible then CancelRequest(ns.L.HOP_CONTEXT_CHANGED) end
		return
	end
	if r.phase ~= "waiting" then return end
	if PruneResponses(r, now) then Fire() end
	if not at or key ~= r.crownKey or at.id ~= r.lease or at.mapID ~= r.mapID
		or not ns.IsMember or ns.IsMember() ~= true or SelfOff()
		or not ns.Layers or not ns.Layers.CurrentMap or ns.Layers.CurrentMap() ~= r.mapID
		or (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown())
		or (IsInGroup and IsInGroup()) then
		return CancelRequest(ns.L.HOP_CONTEXT_CHANGED)
	end
	if now - r.t >= Sightings.SETTLE then
		local zoneUID, why = Consensus(r)
		if zoneUID then
			request = nil
			stats.consensus = stats.consensus + 1
			Fire()
			ns.Print(ns.L.HOP_SIGHTING_FOUND:format(ns.KingName()))
			local ask = ns.Hop.AskDiscovered or ns.Hop.Ask
			return ask(r.mapID, zoneUID, r.label)
		elseif why == "ambiguous" then
			return FailRequest(ns.L.HOP_SIGHTING_AMBIGUOUS:format(ns.KingName()))
		elseif now - r.t >= Sightings.REQUEST_TTL then
			return FailRequest(ns.L.HOP_SIGHTING_NONE:format(ns.KingName()))
		end
	end
end

function Sightings.Stats() return stats end
function Sightings.Reset()
	CancelRequest(nil, true)
	ClearLocal("reset")
	active, candidates, generations, localSighting = {}, {}, 0, nil
	crownKey, crownEpoch = nil, 0
	revokedLeases, revokedLeaseOrder = {}, {}
	request, lastRequestAt = nil, -math.huge
	queuedAnswers, queuedAnswerCount, sentAnswers = {}, 0, {}
	pendingQueries, pendingQueryCount = {}, 0
	receivedAt, seenQueries, seenQueryCount = {}, {}, 0
	admitBuckets, admitBucketCount, admitStats = {}, 0, {}
	stats = { observed = 0, queries = 0, answers = 0, received = 0, consensus = 0,
		withdrawn = 0, cancelled = 0, dropped = {} }
end

ns.Comm.Handle("LY", function(...) Sightings.Receive(...) end)
pcall(ns.RegisterEvent, "NAME_PLATE_UNIT_ADDED", function(unit) Sightings.NameplateAdded(unit) end)
pcall(ns.RegisterEvent, "NAME_PLATE_UNIT_REMOVED", function(unit) Sightings.NameplateRemoved(unit) end)
ns.RegisterEvent("UNIT_NAME_UPDATE", function(unit) Sightings.UnitNameUpdated(unit) end)
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"ZONE_CHANGED_NEW_AREA", "CHANNEL_UI_UPDATE" }) do
	pcall(ns.RegisterEvent, event, function() Sightings.Tick() end)
end
ns.On("CONSENT_CHANGED", function(key) if key == "layerhelp" or key == "location" then Sightings.Tick() end end)
ns.On("NETOFF_CHANGED", function() Sightings.Tick() end)
ns.On("HOP_HELP_CHANGED", function() Sightings.Tick() end)
ns.On("LAYER_SHARING_CHANGED", function() Sightings.Tick() end)
ns.On("KING_LOCATION_CHANGED", function(action, from, id)
	-- Expiry/network absence is temporary and the same authenticated lease may return. An
	-- explicit T1~Q hide is different: never resurrect that consent period if a delayed P or a
	-- pre-lease client reuses its id.
	if action == "hide" or action == "revoke" then RevokeLease(from, id) end
	for unit in pairs(active) do Sightings.Observe(unit) end
	Sightings.Tick()
end)
ns.On("LAYERS_CHANGED", function()
	-- A new two-GUID local proof refreshes remote evidence while an exact plate generation is
	-- still present. The one-second policy tick alone never refreshes it.
	for unit in pairs(active) do Sightings.Observe(unit) end
	Sightings.Tick()
end)
ns.On("LOGIN", function() ns.Every(1, "King nameplate sighting", Sightings.Tick) end)
