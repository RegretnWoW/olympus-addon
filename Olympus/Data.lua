local ADDON, ns = ...
local L = ns.L

-- Holds one report per Olympus guild (ours from the roster, others from the channel)
-- and aggregates them into the numbers the UI and the map show.

local Data = {}
ns.Data = Data

Data.FRESH = 15 * 60           -- older: shown grey, its online players and zones leave the totals
Data.KEEP = 7 * 24 * 60 * 60   -- older than this is forgotten (the guild still listed, grey, until then)
Data.TOTAL_KEEP = 24 * 60 * 60 -- a guild's size counts in the army's total this long after its last report
Data.VOUCH_TTL = 30 * 60       -- a report counts as its sender's vote on the guild this long
Data.CLAIM_TTL = 15 * 60       -- a sender quiet this long for its guild may speak for another one
local MAX_VOUCH = 8            -- votes kept per guild (the newest)

-- The key a guild is stored under, whatever the case a report spells it in: a realm has one
-- guild of a name, so "OLYMPUS X" and "Olympus X" are the same one (or one is forged).
function Data.GuildKey(name)
	if type(name) ~= "string" then return nil end
	local guilds = ns.rdb and ns.rdb.guilds
	if not guilds then return nil end
	if guilds[name] then return name end
	local lower = name:lower()
	for key in pairs(guilds) do
		if type(key) == "string" and key:lower() == lower then return key end
	end
	return nil
end
function Data.Guild(name)
	local key = Data.GuildKey(name)
	return key and ns.rdb.guilds[key] or nil
end

-- Where the King is pinned by name (ns.KING_CHARACTER), a report of his guild that names
-- anyone else as its leader (or nobody) is not his guild's: forged, or out of date.
function Data.OtherKing(guild, leader)
	return ns.IsKingGuild(guild) and ns.KingCharacter() ~= nil and not ns.IsKingCharacter(leader)
end

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if type(g) ~= "table" or now - (g.t or 0) > Data.KEEP then
			ns.rdb.guilds[name] = nil
		elseif not g.mine and Data.OtherKing(name, g.leader) then
			-- Kept from before the King was pinned: the next real report takes its place.
			ns.Log("dropped guild %s: names %s its leader, not the King", name, tostring(g.leader))
			ns.rdb.guilds[name] = nil
		end
	end
	-- Kept by older versions: a report bigger than a guild can be (forged), and one guild under
	-- two spellings (the newer one stays). Collected first: pairs() must not see removals twice.
	local drop, byLower = {}, {}
	for name, g in pairs(ns.rdb.guilds) do
		if (tonumber(g.total) or 0) > ns.Codec.GUILD_CAP then
			drop[#drop + 1] = name
		else
			local other = byLower[name:lower()]
			if other then
				local older = (g.t or 0) < (ns.rdb.guilds[other].t or 0) and name or other
				drop[#drop + 1] = older
				if older == other then byLower[name:lower()] = name end
			else
				byLower[name:lower()] = name
			end
		end
	end
	for _, name in ipairs(drop) do
		ns.Log("dropped guild %s: forged size or a second spelling", name)
		ns.rdb.guilds[name] = nil
	end
	local seen = Data.Seen()
	for name, e in pairs(seen) do
		if type(e) ~= "table" or now - (e.t or 0) > Data.KEEP then seen[name] = nil end
	end
	-- Sightings kept before v0.7.11 may carry a "-Realm" of our census group on the guild's
	-- name (Who.GuildName): they go under its plain name, the newest one kept, or the guild
	-- would show twice. Collect first: pairs() must not see new keys.
	local renamed = {}
	for name in pairs(seen) do
		local base = type(name) == "string" and ns.Who.GuildName and ns.Who.GuildName(name)
		if base and base ~= name then renamed[#renamed + 1] = { name, base } end
	end
	for _, pair in ipairs(renamed) do
		local e, old = seen[pair[1]], seen[pair[2]]
		seen[pair[1]] = nil
		if type(old) ~= "table" or (e.t or 0) > (old.t or 0) then seen[pair[2]] = e end
	end
end)

-- Olympus guilds seen online with /who (census Refresh, Join screen), per realm:
-- [guild] = { online = players seen, capped = more may be online, t }. Kept apart from the
-- reports on purpose: a sighting knows no members, leader or zones, never counts in the
-- totals, and must never pass for a report (the conflict and rank checks trust
-- ns.rdb.guilds). The census lists the guilds seen that nobody reports, in grey.
function Data.Seen()
	ns.rdb.seen = ns.rdb.seen or {}
	return ns.rdb.seen
end

-- players: the Olympus players of the current round of /who searches (Who.lua), each once.
-- Players of other realms count too: /who only lists who shares our world, and on the
-- Forever beta Olympus guilds span PvP and PvP 2, so everyone we can see belongs here.
function Data.RecordSightings(players, capped)
	local count = {}
	for _, p in ipairs(players or {}) do
		if ns.IsFederation(p.guild) then
			count[p.guild] = (count[p.guild] or 0) + 1
		end
	end
	local seen, now = Data.Seen(), ns.Now()
	for guild, n in pairs(count) do seen[guild] = { online = n, capped = capped or nil, t = now } end
	if next(count) then ns.Fire("DATA_CHANGED") end
end
ns.Who.Listen(Data.RecordSightings)

function Data.SetLocal(r)
	r.t = ns.Now()
	r.reporter = ns.DisplayName(ns.me)
	r.reporterFull = ns.me
	r.realm = ns.realm
	r.from = ns.realm -- travels in the report: whoever hears it on another realm knows the channel is shared
	r.heardOn = ns.realm -- see Data.Receive
	r.mine = true
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
end

-- Sender names are set by the server and cannot be forged, so we tie every sender to the
-- one guild it reports. A (modified) client that reports several guilds is ignored, and a
-- guild whose reports disagree about its leader, its size or its officers is flagged as a
-- conflict.
local senderGuild = {} -- "Name-Realm" -> { guild, t }

-- One guild per sender, shared by reports and chat: a name that speaks for one guild can't
-- speak for another. A player who really moved guilds speaks again after CLAIM_TTL quiet.
function Data.ClaimGuild(sender, guild)
	local who, now = ns.FullName(sender), ns.Now()
	local c = senderGuild[who]
	if c and c.guild:lower() ~= guild:lower() and now - c.t < Data.CLAIM_TTL then return false end
	senderGuild[who] = { guild = guild, t = now }
	return true
end

-- Every rank a report names, as "Name-Realm" -> 0 (leader) or 1 (officer). Names without a
-- realm belong to the reporter's realm, so a same-named player from another realm never matches.
local function Ranks(g)
	local home, out = g.realm or ns.realm, {}
	for _, o in ipairs(g.officers or {}) do out[ns.FullName(o.name, home)] = 1 end
	if g.leader then out[ns.FullName(g.leader, home)] = 0 end
	return out
end

-- The guild as a report pictures it: leader and officers, names in "Name-Realm" form so the
-- same people match whatever realm each reporter plays on. A list cut at MAX_OFFICERS is
-- pictured by its leader only (two cut lists need not hold the same officers).
local function Signature(r, ranks)
	local cut = #(r.officers or {}) >= ns.Codec.MAX_OFFICERS
	local parts = {}
	for name, rank in pairs(ranks) do
		if rank == 0 or not cut then parts[#parts + 1] = name .. "=" .. rank end
	end
	table.sort(parts)
	return table.concat(parts, ",") .. (cut and ",+" or "")
end

-- The votes kept for a guild: one per sender (its newest report), for VOUCH_TTL, the newest
-- MAX_VOUCH. Votes of older versions (no signature) are dropped.
local function Votes(map, now)
	local list, out = {}, {}
	for sender, v in pairs(map or {}) do
		if type(v) == "table" and v.sig and v.ranks and now - (v.t or 0) <= Data.VOUCH_TTL then
			list[#list + 1] = { sender = sender, v = v }
		end
	end
	table.sort(list, function(a, b) return a.v.t > b.v.t end)
	for i = 1, math.min(MAX_VOUCH, #list) do out[list[i].sender] = list[i].v end
	return out
end

-- The picture most senders agree on right now, its count, and every picture with that many
-- senders (`tops`). `top` is nil when there is none, or when two pictures have as many
-- senders each: then the guild is contested, and only what all of them agree on counts.
local function Majority(votes, now)
	local count = {}
	for _, v in pairs(votes) do
		if now - (v.t or 0) <= Data.VOUCH_TTL then count[v.sig] = (count[v.sig] or 0) + 1 end
	end
	local best, tops = 0, {}
	for sig, n in pairs(count) do
		if n > best then best, tops = n, { [sig] = true } elseif n == best then tops[sig] = true end
	end
	local top, n = nil, 0
	for sig in pairs(tops) do top, n = sig, n + 1 end
	if n ~= 1 then top = nil end
	return top, best, tops
end
Data.Majority = Majority -- for /oly status and tests

-- Votes heard on one channel say nothing on another (the public channel lets anyone vote):
-- called when we move to another channel, e.g. when the realm key arrives.
function Data.ForgetVotes()
	for _, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" then g.vouch, g.conflict = nil, nil end
	end
end

-- No Crown from other guilds' votes until a full reporting cycle has passed since login: a
-- guild's reporter and runner-up must have had the time to vote before outsiders can win.
Data.CROWN_AFTER = 200

function Data.Receive(r, sender)
	if not ns.IsFederation(r.guild) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim (in any spelling).
	local mine = GetGuildInfo("player")
	if mine and r.guild:lower() == mine:lower() then return false end
	local who = ns.FullName(sender)
	-- The other faction's Olympus guilds are not ours to count (their channel is another one;
	-- this only matters if a report reaches ours anyway).
	if (r.faction or "Alliance") ~= (ns.faction or "Alliance") then
		ns.Log("ignored %s from %s: a %s guild", r.guild, who, tostring(r.faction))
		return false
	end
	-- The King's guild is led by the King: where he is pinned by name, a report naming anyone
	-- else at its head counts for nothing, not even as a vote. It can't replace the row
	-- everyone sees, nor outvote the real reporters (GitHub issue #18).
	if Data.OtherKing(r.guild, r.leader) then
		ns.Log("ignored %s from %s: names %s its leader, not the King", r.guild, who, tostring(r.leader))
		return false
	end
	if not Data.ClaimGuild(who, r.guild) then
		local claimed = senderGuild[who]
		ns.Log("ignored %s: already reported %s, now claims %s", who, claimed and claimed.guild or "?", r.guild)
		return false
	end
	-- One guild whatever the case it is spelled in: the spelling already stored is its key, and
	-- a report under another spelling is one more vote on that guild.
	r.guild = Data.GuildKey(r.guild) or r.guild
	local previous = ns.rdb.guilds[r.guild]
	-- Realms of one census group share this store, but a name without a realm takes the realm
	-- of the character that heard it. A report heard on another realm of the group names people
	-- in that realm's form: compared with ours, the same reporter and officers would look new
	-- (a false conflict), so here it counts as no report at all.
	if previous and previous.heardOn and previous.heardOn ~= ns.realm then previous = nil end
	local previousWho = previous and (previous.reporterFull or ns.FullName(previous.reporter))
	r.t = ns.Now()
	r.reporter = ns.DisplayName(who)
	r.reporterFull = who
	r.heardOn = ns.realm
	-- The realm of the sender's name as we got it, not the report's `from`: a report's short
	-- names are compared with senders in that same form (a sender that reaches us without a
	-- realm carries ours, whatever realm it plays on).
	r.realm = ns.RealmOf(who) or ns.realm
	local now = r.t
	-- Every report is its sender's vote on who leads the guild and who its officers are. Ranks
	-- count only from the picture most senders agree on (Data.KnownRank): one sender changing
	-- or repeating a report can't move it, and two pictures with as many senders each are a
	-- contest where no rank counts. Nothing here needs saved history (the Forever beta client
	-- never loads it back).
	local votes = Votes(previous and previous.vouch, now)
	local ranks = Ranks(r)
	votes[who] = { t = now, sig = Signature(r, ranks), ranks = ranks }
	r.vouch = votes
	local top, _, tops = Majority(votes, now)
	-- Against the picture most senders give while that picture is fresh: the vote counts, the
	-- row everyone sees (and the King's guild's leader with it) stays the majority's.
	if previous and top and votes[who].sig ~= top and now - (previous.t or 0) <= Data.FRESH then
		previous.vouch = votes
		if not previous.outvoted then ns.Log("conflict on %s: %s's report is not what the other senders say", r.guild, who) end
		previous.outvoted = true
		ns.Fire("DATA_CHANGED")
		return false
	end
	-- Shown in the census: the senders are split on this guild (no picture leads).
	local pictures = 0
	for _ in pairs(tops) do pictures = pictures + 1 end
	r.conflict = (top == nil and pictures > 1) and true or nil
	if r.conflict and not (previous and previous.conflict) then
		ns.Log("conflict on %s: the senders are split on it", r.guild)
	end
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
	return true
end

-- What rank does this sender really have in that guild? Our own guild: from our roster.
-- Other guilds: from that guild's report (leader = 0, officers = 1). nil = unknown.
-- soft: for what only shows (the King's layer line and crown), one report naming them is
-- enough while no other one disagrees; the Crown's powers need two. Both wait CROWN_AFTER
-- after login, when the real reports have come in (a lone forged one would be alone then).
function Data.KnownRank(sender, guild, soft)
	local who = ns.FullName(sender)
	if guild == GetGuildInfo("player") then return ns.Roster.RankOf(who) end
	local g = Data.Guild(guild)
	local now = ns.Now()
	-- A report kept from an earlier session proves nothing about who leads the guild now.
	if not g or now - (g.t or 0) > Data.FRESH then return nil end
	local votes = Votes(g.vouch, now)
	local _, _, tops = Majority(votes, now)
	-- The rank the leading picture gives (every leading picture, if they tie: then only what
	-- they all agree on counts), named by someone else too: a report never proves its own
	-- sender's rank. The Crown (every guild master, the officers of <Olympus>) needs two
	-- senders naming them (theirs may be one).
	-- A sender is itself by its name alone: "Asmon-OtherRealm" can't vouch for "Asmon-Realm".
	local self = ns.ShortName(who)
	local bySig, total, named, others = {}, 0, 0, 0
	for src, v in pairs(votes) do
		if tops[v.sig] then
			if ns.ShortName(src) ~= self then total = total + 1 end
			local k = v.ranks[who]
			if bySig[v.sig] == nil then bySig[v.sig] = k or false end
			if k then
				named = named + 1
				if ns.ShortName(src) ~= self then others = others + 1 end
				if bySig[v.sig] and k < bySig[v.sig] then bySig[v.sig] = k end
			end
		end
	end
	local rank
	for sig in pairs(tops) do
		local k = bySig[sig]
		if not k or (rank and k ~= rank) then return nil end
		rank = k
	end
	if not rank or others < 1 then return nil end
	-- A picture cut at MAX_OFFICERS leaves the officers out of its signature: an officer needs
	-- most of the other senders of the leading picture to name them, not just one.
	if rank > 0 and others * 2 <= total then
		for sig in pairs(tops) do
			if sig:sub(-2) == ",+" then return nil end
		end
	end
	if ns.IsCrownRank(guild, rank) then
		if named < 2 and not soft then return nil end
		if now - (ns.Comm and ns.Comm.loginAt or 0) < Data.CROWN_AFTER then return nil end
	end
	return rank
end

function Data.Summary()
	local now = ns.Now()
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(ns.rdb.guilds) do
		if ns.IsFederation(name) then
			local age = now - (g.t or 0)
			local fresh = age <= Data.FRESH
			-- A guild keeps its size from its last report when its reporters log off (the army
			-- does not shrink every night), for a day; listed (grey) for a week; who is online
			-- and where only count while fresh.
			if age <= Data.KEEP then
				s.guilds[#s.guilds + 1] = { name = name, g = g, fresh = fresh, counted = age <= Data.TOTAL_KEEP }
				if age <= Data.TOTAL_KEEP then s.total = s.total + math.min(g.total or 0, ns.Codec.GUILD_CAP) end
			end
			if fresh then
				s.fresh = s.fresh + 1
				s.online = s.online + (g.online or 0)
				if (g.t or 0) > s.newest then s.newest = g.t end
				for key, n in pairs(g.zones or {}) do
					s.zones[key] = (s.zones[key] or 0) + n
					s.zoneGuilds[key] = s.zoneGuilds[key] or {}
					s.zoneGuilds[key][name] = n
				end
			end
		end
	end
	table.sort(s.guilds, function(a, b)
		if a.fresh ~= b.fresh then return a.fresh end
		if (a.g.total or 0) ~= (b.g.total or 0) then return (a.g.total or 0) > (b.g.total or 0) end
		return a.name < b.name
	end)
	-- Guilds only /who has seen, for the census list alone: in no total, tree or map.
	s.seen = {}
	for name, e in pairs(Data.Seen()) do
		if ns.IsFederation(name) and not ns.rdb.guilds[name] and type(e) == "table" and now - (e.t or 0) <= Data.KEEP then
			s.seen[#s.seen + 1] = { name = name, online = e.online or 0, capped = e.capped, t = e.t }
		end
	end
	table.sort(s.seen, function(a, b)
		if a.online ~= b.online then return a.online > b.online end
		return a.name < b.name
	end)
	for key, n in pairs(s.zones) do s.zoneList[#s.zoneList + 1] = { key = key, count = n } end
	table.sort(s.zoneList, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.key < b.key
	end)
	return s
end

function Data.DiscordText()
	local s = Data.Summary()
	local F = ns.FormatNumber
	local out = {}
	out[#out + 1] = L.DISCORD_HEADER:format(F(s.total), F(s.online), #s.guilds)
	local where = {}
	for i = 1, math.min(8, #s.zoneList) do
		local z = s.zoneList[i]
		where[#where + 1] = ns.Zones.NameForKey(z.key) .. " " .. F(z.count)
	end
	if #where > 0 then out[#out + 1] = L.DISCORD_WHERE .. table.concat(where, " · ") end
	out[#out + 1] = "```"
	out[#out + 1] = ("%-22s %7s %7s  %s"):format("Guild", "Members", "Online", "Leader")
	for _, e in ipairs(s.guilds) do
		local g = e.g
		local leader = g.leader and (g.leader .. (g.leaderOnline and " (on)" or "")) or "?"
		out[#out + 1] = ("%-22s %7s %7s  %s%s"):format(e.name, F(g.total), F(g.online), leader, e.fresh and "" or "  [stale]")
	end
	out[#out + 1] = "```"
	out[#out + 1] = ("_Olympus addon v%s_"):format(ns.VERSION)
	return table.concat(out, "\n")
end
