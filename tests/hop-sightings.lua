-- Request-bound King-nameplate discovery: private answers, consensus and revocation.
local base, test, eq, WithHop = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]hop%-sightings%.lua$")) or "./"
local KING = "High King-Realm"

local function Full(name, realm)
	if type(name) ~= "string" or name == "" or name:find("-", 1, true) then return name end
	return name .. "-" .. (realm or "Realm")
end

local function WithWorld(fn)
	local globals = { "UnitExists", "UnitIsPlayer", "UnitGUID", "UnitFactionGroup", "GetGuildInfo", "IsInInstance",
		"IsInGuild", "IsInGroup", "InCombatLockdown", "C_Map" }
	local saved = {}
	for _, key in ipairs(globals) do saved[key] = _G[key] end
	local w = { clock = 1000, crownOn = true, crown = { from = KING, id = 77, mapID = 1453, t = 1000 }, current = nil }
	local ok, err = pcall(function()
		UnitExists = function(unit) local u = w.current and w.current.units[unit]; return u and u.exists == true or false end
		UnitIsPlayer = function(unit) local u = w.current and w.current.units[unit]; return u and u.player == true or false end
		UnitGUID = function(unit) local u = w.current and w.current.units[unit]; return u and u.guid or nil end
		UnitFactionGroup = function(unit) local u = w.current and w.current.units[unit]; return u and u.faction or nil end
		GetGuildInfo = function() return w.current and w.current.guild or nil end
		IsInInstance = function() return w.current and w.current.instance == true or false end
		IsInGroup = function() return w.current and (w.current.group or 0) > 0 or false end
		InCombatLockdown = function() return w.current and w.current.combat == true or false end
		IsInGuild = function() return true end
		C_Map = { GetBestMapForUnit = function() return w.current and w.current.map or nil end,
			GetMapInfo = function(id) return id and { mapType = 3 } or nil end }

		function w.use(c, call, ...)
			local previous = w.current
			w.current = c
			local function Pack(...) return { n = select("#", ...), ... } end
			local results = Pack(pcall(call, ...))
			w.current = previous
			if not results[1] then error(results[2], 0) end
			return unpack(results, 2, results.n)
		end

		function w.client(name)
			local c = {
				me = name .. "-Realm", realm = "Realm", faction = "Alliance", guild = "Olympus II", map = 1453,
				L = setmetatable({}, { __index = function(_, key) return key end }),
				db = { layerHelp = true, shareLocation = true, blocked = {} }, rdb = { guilds = {} }, units = {}, jobs = {}, sent = {},
				handlers = {}, events = {}, listeners = {}, members = {}, remoteGuilds = {}, unverified = {}, alts = {}, hidden = {}, ready = true,
				channel = "OlympusNet", printed = {}, hopAsks = {}, fires = 0,
				mine = { mapID = 1453, zoneUID = 8, t = w.clock, confirmedAt = w.clock }, sharing = true,
			}
			c.Now = function() return w.clock end
			c.FullName = function(n, realm) return Full(n, realm) end
			c.ShortName = function(n) return type(n) == "string" and n:gsub("%-.*$", "") or nil end
			c.IsMember = function() return c.member ~= false end
			c.UnitFullName = function(unit) local u = c.units[unit]; return u and u.name or nil end
			c.IsFederation = function(guild) return type(guild) == "string" and guild:lower():find("olympus", 1, true) ~= nil end
			c.IsKingCharacter = function(n) return type(n) == "string" and n:lower() == KING:lower() end
			c.KingName = function() return "Asmon" end
			c.Alts = { Linked = function(sender)
				local linked = c.alts[type(sender) == "string" and sender:lower() or ""]
				local out = {}
				for _, other in ipairs(linked or {}) do out[#out + 1] = other end
				return out
			end }
			c.Roster = {
				guild = c.guild, group = c.realmGroup, faction = c.faction, complete = true,
				generation = 1, snapshotAt = w.clock,
				RankOf = function(sender)
				local key = type(sender) == "string" and sender:lower()
				if key and c.members[key] == true and c.unverified[key] ~= true then return 3 end
			end }
			c.Roster.Fresh = function(maxAge)
				local R, age = c.Roster, w.clock - c.Roster.snapshotAt
				maxAge = tonumber(maxAge) or 120
				if R.complete ~= true or type(R.generation) ~= "number" or R.generation < 1
					or R.guild ~= c.guild or R.group ~= c.realmGroup or R.faction ~= c.faction
					or age < 0 or age > maxAge then return nil end
				return R
			end
			c.Data = { KnownRank = function(sender, guild)
				local key = type(sender) == "string" and sender:lower()
				local known = key and c.remoteGuilds[key]
				if known and type(guild) == "string" and known:lower() == guild:lower()
					and c.unverified[key] ~= true then return 1 end
			end }
			c.King = { Location = function() return w.crownOn and w.crown or nil end }
			c.Layers = {
				EVIDENCE_WINDOW = 15, Mine = function() return c.mine end, CurrentMap = function() return c.map end,
				Sharing = function() return c.sharing == true end, Of = function() return c.official end,
			}
			c.Hop = {
				ZoneName = function() return "Stormwind" end,
				WaitLeft = function(now)
					local at, left = now or w.clock, 0
					if c.discoverySentAt then left = math.max(left, 20 - (at - c.discoverySentAt)) end
					if c.discoveryFailedAt then
						left = math.max(left, (c.discoveryWait or 0) - (at - c.discoveryFailedAt))
					end
					return math.max(0, left)
				end,
				DiscoverySent = function() c.discoverySentAt = w.clock end,
				DiscoveryFailed = function(message)
					c.discoveryFails = (c.discoveryFails or 0) + 1
					c.discoveryFailedAt = w.clock
					c.discoveryWait = ({ 20, 60, 180 })[math.min(c.discoveryFails, 3)]
					c.printed[#c.printed + 1] = message
				end,
				CanHelp = function(mapID, zoneUID)
					if c.db.layerHelp ~= true or not c.sharing or c.combat or c.instance or c.help == false then return false end
					if not c.mine or c.mine.mapID ~= mapID or c.mine.zoneUID ~= zoneUID or c.map ~= mapID then return false end
					if c.group and c.group > 0 and (not c.lead or c.group >= 5) then return false end
					return true
				end,
				Ask = function(mapID, zoneUID, label) c.hopAsks[#c.hopAsks + 1] = { mapID, zoneUID, label }; return true end,
			}
			c.Hop.AskDiscovered = c.Hop.Ask
			c.Hop.CanHelpKing = function(mapID, zoneUID)
				if c.db.hopKingChoice == "no" then return false end
				return c.Hop.CanHelp(mapID, zoneUID)
			end
			c.Moderation = {
				Hides = function(sender)
					return type(sender) == "string" and c.hidden[sender:lower()] == true or false
				end,
				SelfOff = function() return c.selfOff and { off = true } or nil end,
				YouText = function() return "net-off" end,
			}
			c.Channels = { VerifiedLevel = function(sender, guild)
				local key = sender:lower()
				local remote = c.remoteGuilds[key]
				local member = (c.members[key] == true
					or (remote and remote:lower() == guild:lower())) and c.IsFederation(guild)
				return member and 1 or 0, member and c.unverified[key] ~= true or false
			end, Admit = function(sender, guild, _, now, options)
				local key, remote = sender:lower(), c.remoteGuilds[sender:lower()]
				if c.members[key] ~= true and not (remote and remote:lower() == guild:lower()) then return false end
				if not c.IsFederation(guild) then return false end
				local buckets = options and options.buckets
				if buckets then
					local bucket = buckets[sender]
					if not bucket then bucket = { tokens = 6, t = now }; buckets[sender] = bucket end
					bucket.t = now
				end
				return true
			end }
			local function Queue(dist, target, msg, done, options)
				if c.reject then if done then done(false, "full") end return false end
				c.jobs[#c.jobs + 1] = { dist = dist, target = target, msg = msg, done = done, options = options }
				return true
			end
			c.Comm = {
				Handle = function(kind, call) c.handlers[kind] = call end,
				ChannelReady = function() return c.ready end,
				ChannelName = function() return c.channel end,
				Send = function(dist, msg, key, urgent, logged, done, options)
					return Queue(dist, nil, msg, done, options)
				end,
				Whisper = function(target, msg, key, urgent, logged, done, options)
					return Queue("WHISPER", target, msg, done, options)
				end,
				CancelQueued = function(owner, key, why)
					local kept, n = {}, 0
					for _, job in ipairs(c.jobs) do
						if job.options and job.options.owner == owner and job.options.key == key then
							n = n + 1; if job.done then job.done(false, why) end
						else kept[#kept + 1] = job end
					end
					c.jobs = kept
					return n
				end,
				Cancel = function(owner)
					local kept = {}
					for _, job in ipairs(c.jobs) do
						if job.options and job.options.owner == owner then if job.done then job.done(false, "cancelled") end
						else kept[#kept + 1] = job end
					end
					c.jobs = kept
				end,
			}
			c.After = function(_, _, call) call() end
			c.Every = function() end
			c.Log = function() end
			c.Print = function(message) c.printed[#c.printed + 1] = message end
			c.RegisterEvent = function(event, call) c.events[event] = call end
			c.On = function(event, call) c.listeners[event] = call end
			c.Fire = function(event, ...)
				if event == "HOP_CHANGED" then c.fires = c.fires + 1 end
				if c.listeners[event] then c.listeners[event](...) end
			end
			assert(loadfile(ROOT .. "Olympus/HopSightings.lua"))("Olympus", c)
			function c.flush(index, dist, target)
				local job = table.remove(c.jobs, index or 1)
				if not job then return false, "empty" end
				local allowed, why = true, nil
				if job.options and job.options.permit then
					allowed, why = job.options.permit(job.options.owner, job.options.key, dist or job.dist,
						target ~= nil and target or job.target, job.msg)
				end
				if allowed then c.sent[#c.sent + 1] = job end
				if job.done then job.done(allowed == true, why) end
				return allowed, why, job
			end
			return c
		end

		fn(w)
	end)
	for _, key in ipairs(globals) do _G[key] = saved[key] end
	if not ok then error(err, 0) end
end

local function KingUnit(name, realm)
	return { exists = true, player = true, guid = "Player-4619-00001234", faction = "Alliance",
		name = Full(name or KING:match("^(.-)%-"), realm or "Realm") }
end

local function Observe(w, client)
	client.units.nameplate1 = KingUnit()
	eq(w.use(client, client.HopSightings.NameplateAdded, "nameplate1"), true)
	eq(#client.jobs, 0, "a direct sighting is private until an active query")
end

local function Start(w, asker)
	eq(w.use(asker, asker.HopSightings.Request,
		{ character = KING, mapID = 1453, label = "Asmon" }, "Asmon's layer"), true)
	local ok, _, query = w.use(asker, asker.flush)
	eq(ok, true)
	assert(query.msg:match("^LY~Q~1~%d+~77~1453$"), query.msg)
	return query
end

local function Answer(w, observer, asker, query)
	observer.members[asker.me:lower()] = true
	eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
	eq(#observer.jobs, 1)
	local ok, _, response = w.use(observer, observer.flush)
	eq(ok, true)
	eq(response.dist, "WHISPER")
	eq(response.target, asker.me)
	assert(response.msg:match("^LY~R~1~%d+~77~1453~8~2~%d+$"), response.msg)
	return response
end

test("hop sighting: observation is private and two independent private answers start the existing hop", function()
	WithWorld(function(w)
		local asker, one, two = w.client("Asker"), w.client("ObserverOne"), w.client("ObserverTwo")
		Observe(w, one); Observe(w, two)
		local query = Start(w, asker)
		asker.members[one.me:lower()], asker.members[two.me:lower()] = true, true
		local first = Answer(w, one, asker, query)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", one.me, first.msg), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "one verified observer never becomes a destination")
		local second = Answer(w, two, asker, query)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", two.me, second.msg), true)
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 1)
		eq(asker.hopAsks[1][1], 1453); eq(asker.hopAsks[1][2], 8)
		eq(asker.HopSightings.Stats().consensus, 1)
	end)
end)

test("hop sighting: linked alts are one observer and wire age is never trusted as freshness proof", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		for _, sender in ipairs({ "AltOne-Realm", "AltTwo-Realm", "Independent-Realm" }) do
			asker.members[sender:lower()] = true
		end
		asker.alts["altone-realm"] = { "AltTwo-Realm" }
		asker.alts["alttwo-realm"] = { "AltOne-Realm" }
		local response = ("LY~R~1~%s~77~1453~8~2~20"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "AltOne-Realm", response), true)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "AltTwo-Realm", response), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "two linked characters are not independent observers")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Independent-Realm", response), true)
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 1, "a fresh request-bound arrival, not its self-declared age, is counted")
	end)
end)

test("hop sighting: a lone spoof cannot redirect, and conflicting observers fail closed", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		for _, sender in ipairs({ "One-Realm", "Two-Realm" }) do asker.members[sender:lower()] = true end
		local fake = ("LY~R~1~%s~77~1453~9~2~5"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "One-Realm", fake), true)
		w.clock = w.clock + asker.HopSightings.RECEIVE_GAP + 1
		local real = ("LY~R~1~%s~77~1453~8~2~5"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Two-Realm", real), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		local before = asker.fires
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "a conflict starts no hop")
		eq(asker.HopSightings.Requesting(), false)
		assert(asker.fires > before, "ambiguity refreshes the open Hop UI as soon as it is final")
	end)
	WithWorld(function(w)
		local asker = w.client("Asker")
		Start(w, asker)
		w.clock = w.clock + asker.HopSightings.REQUEST_TTL
		local before = asker.fires
		w.use(asker, asker.HopSightings.Tick)
		eq(asker.HopSightings.Requesting(), false)
		assert(asker.fires > before, "request expiry refreshes the open Hop UI")
	end)
end)

test("hop sighting: the King's own layer word preempts observer consensus", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		for _, sender in ipairs({ "One-Realm", "Two-Realm" }) do asker.members[sender:lower()] = true end
		local response = ("LY~R~1~%s~77~1453~8~2~5"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "One-Realm", response), true)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Two-Realm", response), true)
		asker.official = { mapID = 1453, zoneUID = 9, t = w.clock }
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 1)
		eq(asker.hopAsks[1][2], 9, "L1 from the King wins over two LY answers")
		eq(asker.HopSightings.Requesting(), false)
	end)
end)

test("hop sighting: only an active request accepts private, verified, well-shaped answers", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		eq(w.use(asker, asker.HopSightings.Receive, "CHANNEL", "Member-Realm", "LY~R~1~2~77~1453~8~2~5"), false, "response lane")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Member-Realm", "LY~R~1~2~77~1453~8~2~5"), false, "no request")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		local response = ("LY~R~1~%s~77~1453~8~2~5"):format(id)
		asker.members[asker.me:lower()] = true
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", asker.me, response), false, "the asker is not its own observer")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Outsider-Realm", response), false, "unverified")
		asker.members["member-realm"] = true
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Member-Realm", response), true)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Member-Realm", response), false, "duplicate")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Member-Realm",
			("LY~R~1~%s~78~1453~8~2~5"):format(id)), false, "wrong lease")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Member-Realm",
			("LY~R~1~%s~77~1453~8~1~5"):format(id)), false, "self-claimed weak confidence")
	end)
end)

test("hop sighting: stale local roster rows never admit received evidence after identity changes", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		local response = ("LY~R~1~%s~77~1453~8~2~5"):format(id)

		asker.members["incomplete-realm"] = true
		asker.Roster.complete = false
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Incomplete-Realm", response), false,
			"a partial roster generation grants no observer authority")

		asker.Roster.complete = true
		asker.Roster.snapshotAt = w.clock - 121
		asker.members["stale-realm"] = true
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Stale-Realm", response), false,
			"an expired local roster grants no observer authority")

		asker.Roster.snapshotAt = w.clock
		asker.guild = "Olympus III"
		asker.members["oldguild-realm"] = true
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "OldGuild-Realm", response), false,
			"rows from the previous guild are not members of the new current guild")

		asker.rdb.guilds["Olympus Zeus"] = {}
		asker.remoteGuilds["external-realm"] = "Olympus Zeus"
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "External-Realm", response), true,
			"independent authority for another Olympus guild remains available")
	end)
end)

test("hop sighting: consent or net-off cancels at the queue boundary and withdraws delivered evidence", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		observer.selfOff = true
		local sent, why = w.use(observer, observer.flush)
		eq(sent, false); eq(why, "member", "permit rechecks net-off at the actual whisper")
		eq(#observer.sent, 0)
		local blocked = w.client("BlockedAsker")
		eq(w.use(blocked, blocked.HopSightings.Request,
			{ character = KING, mapID = 1453, label = "Asmon" }, "Asmon's layer"), true)
		blocked.selfOff = true
		sent, why = w.use(blocked, blocked.flush)
		eq(sent, false); eq(why, "member", "the channel query rechecks net-off too")
	end)
	WithWorld(function(w)
		local asker, observer, other = w.client("Asker"), w.client("Observer"), w.client("Other")
		Observe(w, observer); Observe(w, other)
		local query = Start(w, asker)
		asker.members[observer.me:lower()], asker.members[other.me:lower()] = true, true
		local first = Answer(w, observer, asker, query)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", observer.me, first.msg), true)
		observer.reject = true
		observer.selfOff = true
		w.use(observer, observer.listeners.NETOFF_CHANGED)
		eq(#observer.jobs, 0, "a saturated queue does not pretend the withdrawal was delivered")
		observer.reject = false
		w.use(observer, observer.HopSightings.Tick)
		eq(#observer.jobs, 1, "the private withdrawal is retried at the next tick")
		local ok, _, withdrawal = w.use(observer, observer.flush)
		eq(ok, true); assert(withdrawal.msg:match("^LY~X~1~%d+~77$"), withdrawal.msg)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", observer.me, withdrawal.msg), true)
		local second = Answer(w, other, asker, query)
		w.clock = w.clock + asker.HopSightings.RECEIVE_GAP + 1
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", other.me, second.msg), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "withdrawn evidence no longer contributes to consensus")
	end)
end)

test("hop sighting: requester authority is rechecked before a queued private answer leaves", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		eq(#observer.jobs, 1)
		observer.hidden[asker.me:lower()] = true
		w.use(observer, observer.listeners.NETOFF_CHANGED)
		eq(#observer.jobs, 0, "the queued whisper is cancelled as soon as requester authority disappears")
		local sent, why = w.use(observer, observer.flush)
		eq(sent, false); eq(why, "empty")
		eq(#observer.sent, 0)
	end)
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		observer.db.blocked[asker.me:lower()] = true
		local sent, why = w.use(observer, observer.flush)
		eq(sent, false); eq(why, "requester", "/oly block is rechecked at the location send boundary")
		eq(#observer.sent, 0)
	end)
end)

test("hop sighting: a queued answer rechecks roster identity and freshness at the actual send", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		eq(#observer.jobs, 1)
		observer.guild = "Olympus III"
		local sent, why = w.use(observer, observer.flush)
		eq(sent, false); eq(why, "requester", "the permit rejects an old-guild requester after transfer")
		eq(#observer.sent, 0)
	end)
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		observer.Roster.snapshotAt = w.clock - 120
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		w.clock = w.clock + 1
		local sent, why = w.use(observer, observer.flush)
		eq(sent, false); eq(why, "requester", "a queued whisper cannot outlive its roster proof")
		eq(#observer.sent, 0)
	end)
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		observer.guild = "Olympus III"
		w.use(observer, observer.events.PLAYER_GUILD_UPDATE)
		eq(#observer.jobs, 0, "a guild event promptly cancels the queued location answer")
	end)
end)

test("hop sighting: accepted evidence is pruned when observer authority disappears", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		for _, sender in ipairs({ "One-Realm", "Two-Realm" }) do asker.members[sender:lower()] = true end
		local response = ("LY~R~1~%s~77~1453~8~2~5"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "One-Realm", response), true)
		local before = asker.fires
		asker.hidden["one-realm"] = true
		w.use(asker, asker.listeners.NETOFF_CHANGED)
		assert(asker.fires > before, "authority revocation refreshes the UI immediately")
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Two-Realm", response), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "the revoked observer no longer contributes to consensus without an X")
	end)
	WithWorld(function(w)
		local asker = w.client("Asker")
		local query = Start(w, asker)
		local id = query.msg:match("^LY~Q~1~(%d+)~")
		for _, sender in ipairs({ "One-Realm", "Two-Realm" }) do asker.members[sender:lower()] = true end
		local response = ("LY~R~1~%s~77~1453~8~2~5"):format(id)
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "One-Realm", response), true)
		asker.db.blocked["one-realm"] = true
		eq(w.use(asker, asker.HopSightings.Receive, "WHISPER", "Two-Realm", response), true)
		w.clock = w.clock + asker.HopSightings.SETTLE
		w.use(asker, asker.HopSightings.Tick)
		eq(#asker.hopAsks, 0, "/oly block revokes already accepted observer evidence before settle")
	end)
end)

test("hop sighting: a validated query waits for the second local NPC proof", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		observer.mine.confirmedAt = nil
		observer.units.nameplate1 = KingUnit()
		eq(w.use(observer, observer.HopSightings.NameplateAdded, "nameplate1"), false)
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		eq(#observer.jobs, 0, "one NPC GUID is not enough")
		observer.mine.confirmedAt = w.clock
		w.use(observer, observer.listeners.LAYERS_CHANGED)
		eq(#observer.jobs, 1, "the same active Q is answered once the independent proof matures")
		local sent, _, response = w.use(observer, observer.flush)
		eq(sent, true); assert(response.msg:match("^LY~R~1~"), response.msg)
	end)
end)

test("hop sighting: the existing King no choice keeps local proof private and emits no answer", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		observer.db.hopKingChoice = "no"
		Observe(w, observer)
		eq(w.use(observer, observer.HopSightings.LocalKingLayer, 1453, 8), true,
			"the observation remains usable only for the local no/auto choice")
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		eq(#observer.jobs, 0)
		w.use(observer, observer.HopSightings.Tick)
		eq(#observer.jobs, 0, "Can't right now never emits LY R")
	end)
end)

test("hop sighting: remote evidence expires without losing the local no-auto policy marker", function()
	WithWorld(function(w)
		local asker, observer = w.client("Asker"), w.client("Observer")
		Observe(w, observer)
		w.clock = w.clock + observer.HopSightings.TTL + 1
		w.use(observer, observer.HopSightings.Tick)
		eq(w.use(observer, observer.HopSightings.LocalKingLayer, 1453, 8), true,
			"the crown lease and unchanged local layer still identify the policy layer")
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), true)
		eq(#observer.jobs, 0, "the old observation is not reused as remote destination evidence")
		w.clock = w.clock + observer.HopSightings.POLICY_TTL
		w.use(observer, observer.HopSightings.Tick)
		eq(w.use(observer, observer.HopSightings.LocalKingLayer, 1453, 8), false,
			"the local policy marker is bounded when the exact plate stops refreshing it")
	end)
end)

test("hop sighting integration: discovery shares the public ask cooldown except for its causal handoff", function()
	assert(type(WithHop) == "function", "WithHop fixture")
	WithHop(function(w, H)
		H.DiscoverySent()
		eq(H.WaitLeft(), H.ASK_GAP)
		H.Ask(1453, 8, "uncoupled")
		eq(H.State(), nil, "cancel/retry cannot turn one click into adjacent Q and LQ broadcasts")
		H.AskDiscovered(1453, 8, "consensus")
		assert(H.State() ~= nil, "verified consensus enters the ordinary Hop state machine")
	end)
end)

test("hop sighting: failed discovery shares the ordinary escalating hop backoff", function()
	WithWorld(function(w)
		local asker = w.client("Asker")
		Start(w, asker)
		w.clock = w.clock + asker.HopSightings.REQUEST_TTL
		w.use(asker, asker.HopSightings.Tick)
		eq(asker.discoveryFails, 1); eq(asker.Hop.WaitLeft(w.clock), 20)
		w.clock = w.clock + 20
		Start(w, asker)
		w.clock = w.clock + asker.HopSightings.REQUEST_TTL
		w.use(asker, asker.HopSightings.Tick)
		eq(asker.discoveryFails, 2); eq(asker.Hop.WaitLeft(w.clock), 60)
		eq(w.use(asker, asker.HopSightings.Request,
			{ character = KING, mapID = 1453, label = "Asmon" }, "Asmon's layer"), nil,
			"a third public question is held by the shared backoff")
	end)
end)

test("hop sighting: a temporarily absent crown may return with the same authenticated lease", function()
	WithWorld(function(w)
		local observer, asker = w.client("Observer"), w.client("Asker")
		Observe(w, observer)
		w.crownOn = false
		w.use(observer, observer.HopSightings.Tick)
		w.crownOn = true
		w.clock = w.clock + 1
		w.use(observer, observer.HopSightings.Tick)
		w.use(observer, observer.HopSightings.UnitNameUpdated, "nameplate1")
		local query = Start(w, asker)
		local response = Answer(w, observer, asker, query)
		assert(response.msg:find("~77~1453~", 1, true), "same lease is valid after a fresh authenticated crown word")
	end)
end)

test("hop sighting: an explicitly hidden crown lease cannot be resurrected by a delayed position", function()
	WithWorld(function(w)
		local observer, asker = w.client("Observer"), w.client("Asker")
		Observe(w, observer)
		w.crownOn = false
		w.use(observer, observer.listeners.KING_LOCATION_CHANGED, "hide", KING, 77)
		w.crownOn = true
		w.clock = w.clock + 1
		eq(w.use(observer, observer.HopSightings.UnitNameUpdated, "nameplate1"), false,
			"the old lease stays revoked even if a delayed P makes the crown visible again")
		local query = Start(w, asker)
		observer.members[asker.me:lower()] = true
		eq(w.use(observer, observer.HopSightings.Receive, "CHANNEL", asker.me, query.msg), false)
		eq(#observer.jobs, 0)
	end)
end)

test("hop sighting integration: validated local proof applies the existing no and auto choices", function()
	assert(type(WithHop) == "function", "WithHop fixture")
	WithHop(function(w, H)
		local saved = base.HopSightings.LocalKingLayer
		local ok, err = pcall(function()
			base.HopSightings.LocalKingLayer = function(mapID, zoneUID)
				return mapID == 1453 and zoneUID == 7
			end
			w.see(7)
			base.db.hopKingChoice = "no"
			H.HandleAsk("CHANNEL", "Nope-Realm", "LQ~41~1453~7")
			eq(#w.whispered, 0, "Can't right now offers nothing on the locally observed King layer")
			base.db.hopKingChoice = "auto"
			H.HandleAsk("CHANNEL", "Auto-Realm", "LQ~42~1453~7")
			assert(w.whispered[#w.whispered]:match("^Auto%-Realm LO~42~"), tostring(w.whispered[#w.whispered]))
			H.HandleRequest("WHISPER", "Auto-Realm", "LR~42")
			eq(w.invited[1], "Auto", "For Olympus invites through the existing Hop machine")
			eq(#w.popups, 0)
		end)
		base.HopSightings.LocalKingLayer = saved
		if not ok then error(err, 0) end
	end)
end)

test("hop sighting integration: status and failures stay in the existing Hop state", function()
	assert(type(WithHop) == "function", "WithHop fixture")
	WithHop(function(w, H)
		local saved = base.HopSightings.Progress
		local ok, err = pcall(function()
			base.HopSightings.Progress = function() return "waiting", 6 end
			eq(H.ProgressText(), base.L.HOP_SIGHTING_PROGRESS:format(6))
			base.HopSightings.Progress = saved
			eq(H.DiscoveryFailed("missing"), 20)
			w.clock = w.clock + 20
			eq(H.DiscoveryFailed("missing again"), 60)
			eq(H.WaitLeft(), 60)
		end)
		base.HopSightings.Progress = saved
		if not ok then error(err, 0) end
	end)
end)

test("hop sighting moderation: LY queries/answers are held under net-off, withdrawals remain possible", function()
	eq(base.Moderation.BLOCKED.LY, true)
	local saved = base.Moderation.SelfOff
	base.Moderation.SelfOff = function() return { off = true } end
	local ok, err = pcall(function()
		eq(base.Moderation.Blocks("LY~Q~1~1~77~1453"), true)
		eq(base.Moderation.Blocks("LY~R~1~1~77~1453~8~2~5"), true)
		eq(base.Moderation.Blocks("LY~X~1~1~77"), false)
		eq(base.Moderation.Blocks("LY~X~1~1~77~1453"), true, "only the location-free withdrawal bypasses net-off")
	end)
	base.Moderation.SelfOff = saved
	if not ok then error(err, 0) end
end)

test("hop sighting integration: Hop never installs one sighting as King authority and asks discovery on click", function()
	WithWorld(function(w)
		local requested
		local h = {
			L = setmetatable({}, { __index = function(_, key) return key end }), db = {}, me = "Asker-Realm", realm = "Realm",
			CROWN_ICON = "Interface\\Icons\\INV_Misc_Coin_01",
			rdb = { guilds = { Olympus = { leader = KING:match("^(.-)%-"), leaderOnline = true, realm = "Realm", t = w.clock } } },
		}
		h.Now = function() return w.clock end
		h.IsKingGuild = function(guild) return guild == "Olympus" end
		h.FullName, h.ShortName = Full, function(n) return n and n:gsub("%-.*$", "") end
		h.RealmOf = function(n) return n and n:match("%-(.+)$") end
		h.KingCharacter = function() return KING:match("^(.-)%-") end
		h.IsKingCharacter = function(n) return n == KING end
		h.KingName = function() return "Asmon" end
		h.Data = { FRESH = 300, KnownRank = function() return 0 end }
		h.Layers = { Of = function() return nil end, Mine = function() return nil end, CurrentMap = function() return 1453 end,
			Sharing = function() return true end }
		h.King = { Location = function() return { from = KING, id = 77, mapID = 1453, t = w.clock } end, IsKing = function() return false end }
		h.HopSightings = { Request = function(king, label) requested = { king = king, label = label }; return true end,
			Requesting = function() return false end, CancelRequest = function() return false end }
		h.Comm = { Handle = function() end, Cancel = function() end, ChannelReady = function() return true end,
			Send = function() return true end }
		h.Moderation = {}
		h.On, h.RegisterEvent, h.Every, h.After, h.Fire, h.Print, h.Log = function() end, function() end, function() end,
			function() end, function() end, function() end, function() end
		h.IsMember = function() return true end
		h.GamepadUI = function() return false end
		assert(loadfile(ROOT .. "Olympus/Hop.lua"))("Olympus", h)
		h.Hop.HeardKing(KING)
		eq(h.Hop.King().zoneUID, nil, "no direct sighting is installed as authority")
		w.use(h, h.Hop.AskKing)
		assert(requested and requested.king.character == KING)
		eq(requested.king.mapID, 1453)
		requested = nil
		h.Layers.Mine = function() return { mapID = 1453, zoneUID = 8, t = w.clock, confirmedAt = w.clock } end
		h.HopSightings.LocalKingLayer = function(mapID, zoneUID) return mapID == 1453 and zoneUID == 8 end
		w.use(h, h.Hop.AskKing)
		eq(requested, nil, "a local exact sighting broadcasts no needless discovery query")
		assert(h.Hop.KingLines()[1].text:find(h.L.HOP_KING_HERE:format("Asmon"), 1, true),
			"the local UI says the player is already on the King's layer")
	end)
end)
