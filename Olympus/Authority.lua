local ADDON, ns = ...

-- Dormant migration path for cross-guild write authority. Census reports remain the documented
-- source until the author's signed material explicitly carries an enforcing manifest. Early 1.2
-- test builds put a small manifest inside HT1:
--
--   ^leaders^<faction>^enforce^<epoch>^<issued>^<expires>^<Guild>=<Lord-Realm>,...!...
--
-- A body of "-" is an empty manifest (a tombstone).  Once an enforcing marker for this realm
-- group and faction has been accepted under the author's signature, this client records that
-- boundary in local SavedVariables.  An expiry, malformed replacement, lower epoch, or newer
-- HT1 without the extension then grants nobody; it can never silently fall back to census ranks.
-- Older clients ignore that entry (it has more than the two carets of a department) and still
-- relay the complete signed HT1 blob byte for byte. The scalable successor is a set of HA1 parts:
--
--   HA1~at~realm-group~faction~enforce~epoch~issued~expires~sha256~part~parts~body~signature
--
-- Each part is independently signed by the same author key and binds the digest of the complete,
-- canonical body. A verified first part activates the one-way boundary (and therefore fails
-- closed); roles become usable only after every part of that exact set is present, all signatures
-- hold, the joined body's digest matches, and the whole manifest parses within the limits below.
-- Parts are requested on H3 and returned privately to the requester as H2. Clients that do not
-- know H2 or H3 ignore them. No partial set, SavedVariables edit, Census claim or newer legacy HT1 can
-- reactivate authority.

local Authority = {}
ns.Authority = Authority

Authority.MAX_GUILDS = 128
Authority.MAX_PEOPLE = 25
Authority.MAX_TOTAL = 512
Authority.MAX_EPOCH = 2147483647
Authority.MAX_LIFETIME = 31 * 24 * 60 * 60
Authority.CLOCK_SKEW = 5 * 60
Authority.MIN_TIME = 1577836800 -- 2020-01-01; refuses zero/relative clocks.
Authority.MAX_TEXT = 3000 -- Workshop rejects the complete HT1 blob at this bound too.
Authority.PART_BODY = 5000
Authority.MAX_PARTS = 8
Authority.MAX_PART_TEXT = 6200 -- below Codec.CHUNK * Codec.MAX_CHUNKS, including the signature.
Authority.PENDING_MAX = 8
Authority.BUNDLE_LIFETIME = 10 * 60
Authority.ASK_GAP = 150
Authority.ASKS = 4
Authority.ASK_IDLE = 10 * 60 -- after the login burst, keep recovering when no holder was online
Authority.ANSWER_GAP = 120
Authority.VERIFY_MAX = 16
Authority.OUTGOING_MAX = 1 -- a signed snapshot must never crowd normal addon work off the queue
Authority.QUEUE_WAIT = 45

local FACTIONS = { Alliance = true, Horde = true }
local cachedBlob, cachedRealm, cached
local bundleCacheKey, bundleCache
local pending, pendingCount = {}, 0
local verified, verifiedCount = {}, 0
local verifyTimes = { channel = {}, guild = {} }
local askedFrom, askedCount = {}, 0
local outgoing, outgoingCount = {}, 0
local asks, lastAsk, started = 0, -math.huge, false
local realmInfo = {}

local function Fold(s) return ns.Fold(tostring(s or "")) end

local function GuildName(s)
	s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" or #s > 72 or select(2, s:gsub("[^\128-\191]", "")) > 24 then return nil end
	if not s:match("^[%a\128-\255][%a\128-\255 ]*$") then return nil end
	return s
end

-- Unlike a Steward, a leadership entry must name one exact realm.  The realm must literally
-- occur in the signed HT1 realm group; locally learned realm links cannot broaden the signature.
local function PlayerName(s, realms)
	s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local short, realm = s:match("^([^%-]+)%-([^%-]+)$")
	if not short or #short > 48 or #realm > 40 then return nil end
	if not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") or not realm:match("^[%w\128-\255]+$") then return nil end
	if not realms[Fold(realm)] then return nil end
	return short .. "-" .. realm
end

local function BadSplit(s, sep)
	return s == "" or s:sub(1, #sep) == sep or s:sub(-#sep) == sep or s:find(sep .. sep, 1, true) ~= nil
end

local function Hex(s)
	return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function RealmInfo(realmGroup)
	local raw = ns.GroupRealms(realmGroup)
	local signature = table.concat(raw, "\1")
	local key = tostring(realmGroup or "")
	local cachedInfo = realmInfo[key]
	if cachedInfo and cachedInfo.signature == signature then return cachedInfo end
	local folded, set = {}, {}
	for _, realm in ipairs(raw) do
		local name = Fold(realm)
		folded[#folded + 1], set[name] = name, true
	end
	local canonical = { unpack(folded) }
	table.sort(canonical)
	cachedInfo = { signature = signature, folded = folded, set = set,
		canonical = #canonical > 0 and table.concat(canonical, "+") or nil }
	realmInfo[key] = cachedInfo
	return cachedInfo
end

local function CanonicalGroup(realmGroup)
	return RealmInfo(realmGroup).canonical
end

local function BundleKey(realmGroup, faction)
	local group = CanonicalGroup(realmGroup)
	return group and FACTIONS[faction] and (group .. "|" .. faction) or nil
end

local function CurrentRealmIn(realmGroup)
	local current = Fold(ns.RealmOf and ns.RealmOf(ns.me or "") or ns.realm)
	if current == "" then current = Fold(ns.realm) end
	return RealmInfo(realmGroup).set[current] == true
end

local function ParseBody(body, realmGroup, epoch, issued, expires)
	local realms = RealmInfo(realmGroup).set
	if next(realms) == nil then return nil, "realm" end
	local manifest = { epoch = epoch, issued = issued, expires = expires, guilds = {}, people = {} }
	if body == "-" then return manifest end
	if BadSplit(body or "", "!") then return nil, "shape" end
	local guildCount, total = 0, 0
	for item in body:gmatch("[^!]+") do
		local guild, names = item:match("^([^=]+)=([^=]+)$")
		guild = guild and GuildName(guild)
		if not guild or BadSplit(names or "", ",") then return nil, "guild" end
		local guildKey = Fold(guild)
		if manifest.guilds[guildKey] then return nil, "duplicate-guild" end
		guildCount = guildCount + 1
		if guildCount > Authority.MAX_GUILDS then return nil, "guild-limit" end
		local roles, n = {}, 0
		for raw in names:gmatch("[^,]+") do
			local name = PlayerName(raw, realms)
			local key = name and Fold(name)
			if not name or roles[key] ~= nil or manifest.people[key] then return nil, "duplicate-player" end
			n, total = n + 1, total + 1
			if n > Authority.MAX_PEOPLE or total > Authority.MAX_TOTAL then return nil, "player-limit" end
			roles[key] = n == 1 and 0 or 1
			manifest.people[key] = { guild = guild, rank = roles[key] }
		end
		manifest.guilds[guildKey] = { name = guild, roles = roles }
	end
	return manifest
end

local function ListParts(blob)
	if type(blob) ~= "string" then return nil end
	local text, at, realm, list = blob:match("^(HT1~(%d+)~([^~]*)~[01]~([^~]*))~%x+$")
	if not text then return nil end
	return tonumber(at), realm ~= "" and realm or nil, list
end

local function Marker(entry)
	local faction, epoch = entry:match("^%^leaders%^(%a+)%^enforce%^([^%^]*)")
	if not FACTIONS[faction] then return nil end
	epoch = epoch and epoch:match("^%d+$") and tonumber(epoch) or 0
	if not epoch or epoch < 1 or epoch > Authority.MAX_EPOCH then epoch = 0 end
	return faction, epoch
end

-- Parse all enforcing leadership entries. One malformed/duplicated entry invalidates the whole
-- manifest. `present` is returned separately: the signed enforcement boundary remains meaningful
-- even if its payload is bad and therefore grants nobody.
function Authority.Read(text, realmGroup)
	if type(text) ~= "string" then return nil, "shape", {} end
	if not CanonicalGroup(realmGroup) then return nil, "realm", {} end
	local out, present = {}, {}
	-- Find every explicit boundary before parsing. If one entry is malformed or duplicated, its
	-- valid epoch is still a revocation floor; a later, lower generation cannot recover roles by
	-- exploiting the malformed replacement. The whole signed HT1 is bounded before this reader in
	-- production; keep the reader's own bound explicit for callers and tests too.
	local scan = #text > Authority.MAX_TEXT and text:sub(1, Authority.MAX_TEXT) or text
	for entry in scan:gmatch("[^;]+") do
		local marked, epoch = Marker(entry)
		if marked then present[marked] = math.max(tonumber(present[marked]) or 0, epoch) end
	end
	if #text > Authority.MAX_TEXT then return nil, "size", present end
	for entry in text:gmatch("[^;]+") do
		if entry:match("^%^leaders%^") then
			local faction, epoch, issued, expires, body = entry:match("^%^leaders%^(%a+)%^enforce%^(%d+)%^(%d+)%^(%d+)%^([^%^]*)$")
			epoch, issued, expires = tonumber(epoch), tonumber(issued), tonumber(expires)
			if not faction or not FACTIONS[faction] or out[faction] or not epoch or epoch < 1 or epoch > Authority.MAX_EPOCH
				or not issued or not expires or issued < Authority.MIN_TIME or expires <= issued
				or expires - issued > Authority.MAX_LIFETIME then return nil, "shape", present end
			local manifest, why = ParseBody(body, realmGroup, epoch, issued, expires)
			if not manifest then return nil, why, present end
			out[faction] = manifest
		end
	end
	if next(present) == nil then return nil, "absent", present end
	return out, nil, present
end

local function GroupKeys(realmGroup, faction)
	local realms = RealmInfo(realmGroup).folded
	if #realms == 0 or not FACTIONS[faction] then return {} end
	local keys = {}
	for i, realm in ipairs(realms) do keys[i] = realm .. "|" .. faction end
	return keys
end

local function CurrentTitles()
	local t = ns.CouncilTitles and ns.CouncilTitles()
	if type(t) ~= "table" or type(t.blob) ~= "string" then return nil end
	local at, realm, list = ListParts(t.blob)
	if not at or at ~= tonumber(t.at) or realm ~= t.realm then return nil end
	return t, at, realm, list
end

-- Called immediately after a signed HT1 is accepted, and lazily for lists accepted by an older
-- build. Existing enforcement records advance with every newer HT1, including one with no
-- leadership extension; that makes replay of the old manifest unable to reopen its roles.
function Authority.AcceptTitles(t)
	if type(t) ~= "table" or type(t.blob) ~= "string" then return false end
	local at, realm, list = ListParts(t.blob)
	if not at or at ~= tonumber(t.at) or realm ~= t.realm then return false end
	local parsed, _, present = Authority.Read(list, realm)
	if not ns.db then return false end
	local store = ns.db.authorityEnforced
	if type(store) ~= "table" then
		if next(present) == nil then return false end -- old HT1: do not even change SavedVariables
		store = {}
		ns.db.authorityEnforced = store
	end
	for faction in pairs(FACTIONS) do
		for _, key in ipairs(GroupKeys(realm, faction)) do
			local old = store[key]
			if type(old) == "table" and at > (tonumber(old.at) or 0) then
				old.at, old.kind, old.root = at, "HT", nil
			end
			if present[faction] then
				local manifest = parsed and parsed[faction]
				local epoch = manifest and manifest.epoch or tonumber(present[faction]) or 0
				if type(old) ~= "table" then
					old = { at = at, epoch = epoch, kind = "HT" }
					store[key] = old
				else
					old.at = math.max(tonumber(old.at) or 0, at)
					old.epoch = math.max(tonumber(old.epoch) or 0, epoch)
					if old.at == at then old.kind, old.root = "HT", nil end
				end
			end
		end
	end
	return next(present) ~= nil
end

local function Record(faction, realm)
	local store = ns.db and ns.db.authorityEnforced
	if type(store) ~= "table" or next(store) == nil then return nil end
	local found
	for _, key in ipairs(GroupKeys(realm or ns.group or ns.realm, faction)) do
		local r = store[key]
		if type(r) == "table" then
			found = found or { at = 0, epoch = 0 }
			local at, epoch = tonumber(r.at) or 0, tonumber(r.epoch) or 0
			if at > found.at or (at == found.at and epoch > found.epoch) then
				found.at, found.epoch, found.kind, found.root = at, epoch, r.kind, r.root
			elseif at == found.at and epoch == found.epoch and (found.root ~= r.root or found.kind ~= r.kind) then
				-- Realm aliases must agree on the same boundary; a partial/corrupt SavedVariables edit
				-- grants nothing.
				found.kind, found.root = nil, nil
			end
		end
	end
	return found
end

local function Part(blob)
	if type(blob) ~= "string" or #blob > Authority.MAX_PART_TEXT then return nil, "size" end
	local text, at, realm, faction, epoch, issued, expires, root, index, count, body, sig = blob:match(
		"^(HA1~(%d+)~([^~]*)~(%a+)~enforce~(%d+)~(%d+)~(%d+)~(%x+)~(%d+)~(%d+)~([^~]*))~(%x+)$")
	at, epoch, issued, expires, index, count = tonumber(at), tonumber(epoch), tonumber(issued), tonumber(expires), tonumber(index), tonumber(count)
	if not text or not at or at < Authority.MIN_TIME or not FACTIONS[faction] or not CanonicalGroup(realm)
		or not epoch or epoch < 1 or epoch > Authority.MAX_EPOCH or not issued or issued < Authority.MIN_TIME
		or not expires or expires <= issued or expires - issued > Authority.MAX_LIFETIME
		or #root ~= 64 or not index or not count or count < 1 or count > Authority.MAX_PARTS
		or index < 1 or index > count or body == "" or #body > Authority.PART_BODY
		or (body == "-" and (count ~= 1 or index ~= 1)) or (body ~= "-" and (body:sub(1, 1) == "!" or body:sub(-1) == "!")) then
		return nil, "shape"
	end
	return { blob = blob, text = text, sig = sig, at = at, realm = realm, faction = faction,
		epoch = epoch, issued = issued, expires = expires, root = root:lower(), index = index, count = count, body = body }
end

local function SetBoundary(p)
	if not ns.db then return false, "db" end
	local store = ns.db.authorityEnforced
	if type(store) ~= "table" then store = {}; ns.db.authorityEnforced = store end
	local allowed, reason = true, nil
	for _, key in ipairs(GroupKeys(p.realm, p.faction)) do
		local old = store[key]
		if type(old) ~= "table" then old = { at = 0, epoch = 0 }; store[key] = old end
		local oldAt, oldEpoch = tonumber(old.at) or 0, tonumber(old.epoch) or 0
		if p.at < oldAt or p.epoch < oldEpoch then
			-- A genuinely newer signed downgrade still advances the replay floor, but never grants.
			if p.at > oldAt then old.at, old.kind, old.root = p.at, "HA", nil end
			allowed, reason = false, "replay"
		elseif p.at == oldAt and old.kind == "HA" and old.root and old.root ~= p.root then
			allowed, reason = false, "conflict"
		else
			old.at, old.epoch, old.kind, old.root = math.max(oldAt, p.at), math.max(oldEpoch, p.epoch), "HA", p.root
		end
	end
	return allowed, reason
end

local function StoredBundle(faction, realm)
	local store = ns.rdb and ns.rdb.authorityBundles
	local key = BundleKey(realm or ns.group or ns.realm, faction)
	local b = type(store) == "table" and key and store[key] or nil
	return type(b) == "table" and b or nil, key
end

local function BundleFromBlobs(blobs, expected, alreadyVerified)
	if type(blobs) ~= "table" or #blobs < 1 or #blobs > Authority.MAX_PARTS then return nil, "parts" end
	local first, parts = nil, {}
	for _, blob in ipairs(blobs) do
		local p, why = Part(blob)
		if not p then return nil, why end
		if not ns.Sign or not ns.Sign.Plausible(p.sig)
			or (not (alreadyVerified and verified[blob]) and not ns.Sign.Verify(p.text, p.sig)) then return nil, "signature" end
		first = first or p
		if p.at ~= first.at or p.realm ~= first.realm or p.faction ~= first.faction or p.epoch ~= first.epoch
			or p.issued ~= first.issued or p.expires ~= first.expires or p.root ~= first.root or p.count ~= first.count
			or parts[p.index] then return nil, "set" end
		parts[p.index] = p
	end
	if #blobs ~= first.count then return nil, "partial" end
	local bodies, ordered = {}, {}
	for i = 1, first.count do
		if not parts[i] then return nil, "partial" end
		bodies[i], ordered[i] = parts[i].body, parts[i].blob
	end
	local body = first.count == 1 and bodies[1] == "-" and "-" or table.concat(bodies, "!")
	if Hex(ns.Sign.SHA256(body)) ~= first.root then return nil, "digest" end
	local manifest, why = ParseBody(body, first.realm, first.epoch, first.issued, first.expires)
	if not manifest then return nil, why end
	if expected and (expected.at ~= first.at or expected.epoch ~= first.epoch or expected.root ~= first.root) then return nil, "stale" end
	return { at = first.at, realm = first.realm, faction = first.faction, epoch = first.epoch,
		issued = first.issued, expires = first.expires, root = first.root, blobs = ordered, manifest = manifest }
end

local function SaveBundle(bundle)
	if not ns.rdb then return false end
	local key = BundleKey(bundle.realm, bundle.faction)
	if not key then return false end
	ns.rdb.authorityBundles = type(ns.rdb.authorityBundles) == "table" and ns.rdb.authorityBundles or {}
	ns.rdb.authorityBundles[key] = { at = bundle.at, realm = bundle.realm, faction = bundle.faction,
		epoch = bundle.epoch, issued = bundle.issued, expires = bundle.expires, root = bundle.root, blobs = bundle.blobs }
	bundleCacheKey, bundleCache = key .. ":" .. bundle.root, bundle
	if ns.Fire then ns.Fire("DATA_CHANGED") end
	return true
end

local function BundleManifest(faction, realm)
	local record = Record(faction, realm)
	if not record or record.kind ~= "HA" or type(record.root) ~= "string" then return nil end
	local stored, key = StoredBundle(faction, realm)
	if not stored or stored.at ~= record.at or stored.epoch ~= record.epoch or stored.root ~= record.root then return nil end
	local cacheKey = tostring(key) .. ":" .. record.root
	if bundleCacheKey == cacheKey and bundleCache then return bundleCache.manifest, bundleCache end
	local bundle = BundleFromBlobs(stored.blobs, record)
	if not bundle then return nil end
	bundleCacheKey, bundleCache = cacheKey, bundle
	return bundle.manifest, bundle
end

local function DropOldPending(now)
	for key, set in pairs(pending) do
		if now - set.t > Authority.BUNDLE_LIFETIME then pending[key], pendingCount = nil, math.max(0, pendingCount - 1) end
	end
end

local function PutPart(p)
	local now = ns.Now()
	DropOldPending(now)
	local key = BundleKey(p.realm, p.faction) .. ":" .. p.at .. ":" .. p.epoch .. ":" .. p.root
	local set = pending[key]
	if not set then
		if pendingCount >= Authority.PENDING_MAX then
			local oldest, oldestAt
			for k, v in pairs(pending) do if not oldestAt or v.t < oldestAt then oldest, oldestAt = k, v.t end end
			if oldest then pending[oldest], pendingCount = nil, pendingCount - 1 end
		end
		set = { t = now, at = p.at, epoch = p.epoch, root = p.root, count = p.count, parts = {}, got = 0 }
		pending[key], pendingCount = set, pendingCount + 1
	end
	if set.count ~= p.count then return false, "set" end
	set.t = now
	if not set.parts[p.index] then set.parts[p.index], set.got = p.blob, set.got + 1 end
	if set.got ~= set.count then return true, "partial" end
	local blobs = {}
	for i = 1, set.count do blobs[i] = set.parts[i] end
	local record = Record(p.faction, p.realm)
	-- TakePart verified every exact blob before admitting it to this set. Avoid another bounded but
	-- expensive RSA pass when the last part arrives; BundleManifest still re-verifies persisted raw
	-- blobs after reload, where this in-memory cache is deliberately empty.
	local bundle, why = BundleFromBlobs(blobs, record, true)
	pending[key], pendingCount = nil, pendingCount - 1
	if not bundle then return false, why end
	SaveBundle(bundle)
	return true, "complete"
end

local function VerifyBudget(sender, dist, blob)
	if verified[blob] then return true end
	local author = ns.Workshop and ns.Workshop.IsAuthorName and ns.Workshop.IsAuthorName(sender)
	if not author then
		local lane = dist == "GUILD" and verifyTimes.guild or verifyTimes.channel
		local now = ns.Now()
		for i = #lane, 1, -1 do if now - lane[i] >= 60 then table.remove(lane, i) end end
		if #lane >= Authority.VERIFY_MAX then return false end
		lane[#lane + 1] = now
	end
	return true
end

-- A signed logical HA1 part. A valid first part establishes the fail-closed boundary; only a
-- complete set reaches SaveBundle. `dist` is used solely for independent verification budgets.
function Authority.TakePart(blob, sender, dist)
	local p, why = Part(blob)
	if not p or not CurrentRealmIn(p.realm) then return false, why or "realm" end
	local cachedPart = verified[blob]
	if not cachedPart then
		if not ns.Sign or not ns.Sign.Plausible(p.sig) then return false, "signature" end
		if sender and not VerifyBudget(sender, dist, blob) then return false, "budget" end
		if not ns.Sign.Verify(p.text, p.sig) then return false, "signature" end
		if verifiedCount >= 100 then wipe(verified); verifiedCount = 0 end
		verified[blob], verifiedCount = p, verifiedCount + 1
	else
		p = cachedPart
	end
	local allowed, boundaryWhy = SetBoundary(p)
	if not allowed then return false, boundaryWhy end
	return PutPart(p)
end

local function Parsed()
	local t, at, realm, list = CurrentTitles()
	if not t then return nil, nil, nil, nil end
	if t.blob == cachedBlob and t.realm == cachedRealm then return cached, t, at, realm end
	cachedBlob, cachedRealm = t.blob, t.realm
	cached = Authority.Read(list, realm)
	Authority.AcceptTitles(t)
	return cached, t, at, realm
end

function Authority.Enforced(faction)
	faction = faction or ns.faction or "Alliance"
	local _, _, _, realm = Parsed()
	return Record(faction, realm) ~= nil
end

function Authority.Valid(manifest, now)
	if type(manifest) ~= "table" then return false end
	now = tonumber(now) or ns.Now()
	return now + Authority.CLOCK_SKEW >= manifest.issued and now <= manifest.expires
end

function Authority.Manifest(faction, now)
	faction = faction or ns.faction or "Alliance"
	local bundleManifest = BundleManifest(faction, ns.group or ns.realm)
	if bundleManifest then return Authority.Valid(bundleManifest, now) and bundleManifest or nil end
	local all, _, at, realm = Parsed()
	local record = Record(faction, realm)
	local manifest = type(all) == "table" and all[faction] or nil
	if not record or record.kind == "HA" or not manifest or at < (tonumber(record.at) or 0)
		or manifest.epoch < (tonumber(record.epoch) or 0) or not Authority.Valid(manifest, now) then return nil end
	return manifest
end

function Authority.Rank(name, guild, now)
	if type(name) ~= "string" or type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild) then return nil end
	local manifest = Authority.Manifest(nil, now)
	local g = manifest and manifest.guilds[Fold(guild)]
	local full = ns.FullName(name)
	if not g or not ns.RealmOf(full) then return nil end
	local rank = g.roles[Fold(full)]
	return rank, rank ~= nil and "signed" or nil
end

-- The signed guild and rank for an identity when a caller (layer-hop trust, for example) does not
-- start with a claimed guild. A player occurs only once in a valid faction manifest.
function Authority.Role(name, now)
	local manifest = Authority.Manifest(nil, now)
	local full = type(name) == "string" and ns.FullName(name) or nil
	local e = manifest and full and ns.RealmOf(full) and manifest.people[Fold(full)] or nil
	if not e or not ns.IsFederation(e.guild) then return nil end
	return e.guild, e.rank, "signed"
end

local wireId = 0
local function HeldBundle(faction)
	local manifest, bundle = BundleManifest(faction or ns.faction or "Alliance", ns.group or ns.realm)
	return manifest and bundle or nil
end

local function StillHeld(bundle)
	local held = HeldBundle(bundle.faction)
	return held ~= nil and held.at == bundle.at and held.epoch == bundle.epoch and held.root == bundle.root
		and ns.IsMember and ns.IsMember()
		and not (ns.Moderation and not ns.Moderation.missing and ns.Moderation.Blocks
			and ns.Moderation.Blocks("H2~") == true)
end

local function SendBundle(bundle, target)
	if not bundle or type(target) ~= "string" or target == "" or not ns.Comm or not ns.Codec then return false end
	local transferKey = Fold(ns.FullName(target))
	if outgoing[transferKey] or outgoingCount >= Authority.OUTGOING_MAX then return false end
	local transfer = { bundle = bundle, target = target, deadline = ns.Now() + Authority.QUEUE_WAIT }
	outgoing[transferKey] = transfer
	outgoingCount = outgoingCount + 1
	local function FinishTransfer()
		if outgoing[transferKey] ~= transfer then return end
		outgoing[transferKey] = nil
		outgoingCount = math.max(0, outgoingCount - 1)
	end
	local function SendPart(i)
		if outgoing[transferKey] ~= transfer then return false end
		local blob = bundle.blobs and bundle.blobs[i]
		if not blob then FinishTransfer(); return true end
		wireId = (wireId + 1) % 1000
		local pieces = ns.Codec.Chunk("H2~" .. blob, "A" .. wireId)
		-- Comm ordinarily makes room for a new ordinary transfer by evicting older ordinary work.
		-- Authority is background recovery, so wait for genuinely free capacity instead.
		if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < #pieces then
			if ns.Now() >= transfer.deadline or not StillHeld(bundle) then FinishTransfer(); return false end
			ns.After(5, "signed authority queue", function()
				if outgoing[transferKey] == transfer then SendPart(i) end
			end)
			return true
		end
		local ok = ns.Comm.SendBatch("WHISPER", pieces, "authority:" .. transferKey .. ":" .. bundle.root .. ":" .. i, target, false, function(sent)
			if outgoing[transferKey] ~= transfer then return end
			if sent and StillHeld(bundle) then
				transfer.deadline = ns.Now() + Authority.QUEUE_WAIT
				SendPart(i + 1)
			else
				FinishTransfer()
			end
		end, {
			owner = transfer, guardKey = bundle.root, guard = function() return StillHeld(bundle) end,
		})
		if not ok then FinishTransfer() end
		return ok
	end
	return SendPart(1)
end

function Authority.HandlePart(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" then return false, "route" end
	local blob = text:match("^H2~(HA1~.*)$")
	if not blob then return false, "shape" end
	return Authority.TakePart(blob, ns.FullName(sender), dist)
end

local function AskKey(sender)
	-- One requester's public routes share a budget. Otherwise the same client could ask on the
	-- federation channel and GUILD together, receiving two large private transfers at once.
	return Fold(ns.FullName(sender))
end

function Authority.HandleAsk(dist, sender, text)
	if (dist ~= "CHANNEL" and dist ~= "GUILD") or type(text) ~= "string" or #text > 80 then return false end
	local faction, at, epoch = text:match("^H3~(%a+)~(%d+)~(%d+)$")
	at, epoch = tonumber(at), tonumber(epoch)
	sender = ns.FullName(sender)
	if not FACTIONS[faction] or not at or not epoch or type(sender) ~= "string" or sender == ns.me then return false end
	local now, key = ns.Now(), AskKey(sender)
	if now - (askedFrom[key] or -math.huge) < Authority.ANSWER_GAP then return false end
	if not askedFrom[key] then
		if askedCount >= 200 then
			for k, t in pairs(askedFrom) do if now - t >= Authority.ANSWER_GAP then askedFrom[k], askedCount = nil, askedCount - 1 end end
			if askedCount >= 200 then wipe(askedFrom); askedCount = 0 end
		end
		askedCount = askedCount + 1
	end
	askedFrom[key] = now
	local bundle = HeldBundle(faction)
	if not bundle or (bundle.at < at or (bundle.at == at and bundle.epoch <= epoch)) then return false end
	local author = ns.Workshop and ns.Workshop.IsAuthor and ns.Workshop.IsAuthor()
	local users = dist == "GUILD" and (ns.Comm.PeerCount and ns.Comm.PeerCount() or 1)
		or (ns.King and ns.King.AddonsOnline and ns.King.AddonsOnline() or 1)
	if not author and math.random() > math.min(1, 3 / math.max(1, users)) then return false end
	local delay = author and 1 or 2 + math.random() * 10
	ns.After(delay, "signed authority answer", function()
		if StillHeld(bundle) then SendBundle(bundle, sender) end
	end)
	return true
end

function Authority.Ask(force)
	if not started or not ns.Comm or not ns.IsMember or not ns.IsMember() then return false end
	local now = ns.Now()
	local gap = asks < Authority.ASKS and Authority.ASK_GAP or Authority.ASK_IDLE
	if not force and now - lastAsk < gap then return false end
	local bundle = HeldBundle(ns.faction or "Alliance")
	local at, epoch = bundle and bundle.at or 0, bundle and bundle.epoch or 0
	local msg = ("H3~%s~%d~%d"):format(ns.faction or "Alliance", at, epoch)
	asks, lastAsk = asks + 1, now
	ns.Comm.Send("CHANNEL", msg, "authorityask")
	ns.Comm.Send("GUILD", msg, "authorityaskguild")
	return true
end

function Authority.LoadLocal(parts)
	if type(parts) ~= "table" then return false end
	local any = false
	for _, blob in ipairs(parts) do
		local ok = Authority.TakePart(blob, nil, "LOCAL")
		any = ok or any
	end
	return any
end

function Authority.Start()
	if started then return end
	started = true
	if ns.Comm and ns.Comm.Handle then
		ns.Comm.Handle("H2", function(...) Authority.HandlePart(...) end)
		ns.Comm.Handle("H3", function(...) Authority.HandleAsk(...) end)
	end
	if type(ns.COUNCIL_AUTHORITY) == "table" then Authority.LoadLocal(ns.COUNCIL_AUTHORITY) end
	ns.After(30 + math.random() * 20, "signed authority ask", function() Authority.Ask(true) end)
	ns.Every(60, "signed authority", function() Authority.Ask(false); DropOldPending(ns.Now()) end)
end
if ns.On then ns.On("LOGIN", function() Authority.Start() end) end

function Authority.Reset()
	cachedBlob, cachedRealm, cached = nil, nil, nil
	bundleCacheKey, bundleCache = nil, nil
	wipe(pending); pendingCount = 0
	wipe(verified); verifiedCount = 0
	wipe(verifyTimes.channel); wipe(verifyTimes.guild)
	wipe(askedFrom); askedCount = 0
	wipe(outgoing); outgoingCount = 0
	wipe(realmInfo)
	asks, lastAsk, started = 0, -math.huge, false
end -- tests
