local ADDON, ns = ...

-- GUILD: "hello" pings so members with the addon know each other and elect one reporter.
-- CHANNEL (hidden "OlympusNet"): the elected reporter of each guild broadcasts its summary.
-- Chat lines of the channels (Channels.lua) ride the same hidden channel in a lane of their own.

local Comm = {}
ns.Comm = Comm
local Codec = ns.Codec

local HELLO_EVERY = 60
local PEER_WINDOW = 180  -- the election only trusts peers heard in the last 3 minutes
local COUNT_WINDOW = 720 -- quiet members say hello every 10 min: count them for 12
local BROADCAST_EVERY = 170
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 60
local CHAT_QUEUE = 6  -- chat parts waiting in their own lane (two long lines)
local CHAT_TTL = 30   -- a chat part that waited this long is dropped, not sent late
local GUARD_AFTER = 400  -- an elected reporter never heard reporting our guild for this long...
local GUARD_FOR = 30 * 60 -- ...is left out of the election for this long (see MaybeBroadcast)
local KEY_ASK_EVERY = 600 -- at most one key request this often while a sealed reporter is elected
local WITNESS_EVERY = 600 -- the runner-up of the election reports this often (see MaybeBroadcast)
local JOIN_BY = 15        -- seconds after login we join the channel at the latest (see JoinSoon)
local ASK_AFTER = 4       -- seconds after joining we ask the channel for the census (Q1)...
local ASK_AGAIN = 65      -- ...and once more this later, for the reporters that had just answered
local ANSWER_GAP = BROADCAST_EVERY -- a reporter answers census requests at most this often
local WITNESS_ANSWER_GAP = 300     -- the runner-up at most this often
local ANSWER_MIN_AGE = 45 -- ...and only when its last report is at least this old
local MAX_KEYS = 20      -- distinct keys per diagnostic count (the rest count as "other")
local HEAL_GAP = 60      -- the same healing call on our channel at most this often (Comm.HealChannel)
local MAX_HURT = 20      -- banned or muted names kept per channel to let back in (oldest dropped)
local LOCKED_RETRY = { 60, 120, 300, 600 } -- a channel locked against us is tried again after these, then every 10 min

local peers = {}
local queue = {}
local chatQueue = {}  -- chat lines (Channels.lua): { msg, done, t }
local lastWasChat = false
local asm = Codec.NewAssembler()
local msgId = 0
local lastBroadcast = 0
local early -- { every, due }: the report due then went out early, as a census answer (see Q1)
local channelIndex = 0
local stats = { sent = 0, recv = 0, reports = 0, fails = 0, bad = 0, partial = 0, echo = 0, byType = {},
	raw = { ch = {}, g = {} }, rawSample = {}, reportRealms = {}, otherChannel = 0, asked = 0, answered = 0 }
local deliveredLogged = false -- true while a CHAT_MSG_ADDON_LOGGED message is being handled
local lastAnswer = -math.huge
local askTries = 0 -- census requests tried while the channel was not joined (Comm.AskCensus)
local joinedName -- name of the channel we joined (set by Comm.JoinChannel)
local peerRealm = {} -- guild peer -> realm from its hello, "old" for versions that send none
local peerVersion = {} -- guild peer -> the addon version its hello named
local peerSealed = {} -- guild peer -> "s" (on the sealed channel) or "p" (public), from its hello
local peerZone = {} -- guild peer -> true when its hello says it shares its zone (0.9.1, Comm.SharesZone)
-- Short name -> last time we heard it report our guild on the channel. Short: the server may
-- send a name with its realm over GUILD and without it over CHANNEL (names are region-unique
-- on the realmless client).
local heardOwn = {}
local benched = {}   -- guild peer -> time it may be elected again
local watch          -- { name, since }: the peer we elected while we are on the channel
local lastKeyAsk     -- when MaybeBroadcast last asked our guild for the key

-- count[key] + 1, with at most MAX_KEYS distinct keys (senders choose some of them).
local function Count(t, key)
	if t[key] == nil then
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n >= MAX_KEYS then key = "other" end
	end
	t[key] = (t[key] or 0) + 1
end

function Comm.PeerCount()
	local now, n = ns.Now(), 0
	for _, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then n = n + 1 end
	end
	return n
end

-- The addon versions of our guild's users counted now, ours included: { ["0.8.2"] = 3 }.
-- Rides in our report (field 24) for the author's Workshop.
function Comm.PeerVersions()
	local now, out = ns.Now(), { [ns.VERSION] = 1 }
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then
			local v = peerVersion[name] or "?"
			out[v] = (out[v] or 0) + 1
		end
	end
	return out
end

-- Guild peers counted now, by the realm their hello named.
local function PeerRealms(now)
	local out = {}
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then Count(out, peerRealm[name] or "old") end
	end
	return out
end

function Comm.Stats()
	local now = ns.Now()
	local lastOwn, lastOwnAt = nil, 0
	for name, t in pairs(heardOwn) do
		if t > lastOwnAt then lastOwn, lastOwnAt = name, t end
	end
	local out = {}
	for name, t in pairs(benched) do
		if t > now then out[#out + 1] = ns.DisplayName(name) end
	end
	table.sort(out)
	return {
		channelName = joinedName, sealed = ns.rdb and ns.rdb.realmKey ~= nil,
		channel = channelIndex, peers = Comm.PeerCount(), reporter = Comm.reporterName,
		isReporter = Comm.isReporter, sent = stats.sent, recv = stats.recv, reports = stats.reports,
		fails = stats.fails, bad = stats.bad, queue = #queue, chatQueue = #chatQueue, lastFail = stats.lastFail,
		partial = stats.partial, echo = stats.echo, byType = stats.byType, otherChannel = stats.otherChannel,
		chanArgs = stats.chanArgs, asked = stats.asked, answered = stats.answered, runnerUp = Comm.isRunnerUp, pending = (function() local n = 0 for _ in pairs(asm.buf) do n = n + 1 end return n end)(),
		raw = stats.raw, rawSample = stats.rawSample, reportRealms = stats.reportRealms, shared = ns.rdb and ns.rdb.shared,
		peerRealms = PeerRealms(now), heardOwn = lastOwn and ns.DisplayName(lastOwn), heardOwnAt = lastOwn and lastOwnAt,
		benched = out, guard = Comm.GuardStats and Comm.GuardStats(),
	}
end

-- urgent: ahead of everything waiting (a player waits for the answer: a layer ask, an offer,
-- a vote), behind the other urgent ones.
local function Enqueue(dist, msg, key, target, urgent)
	if key then
		for _, item in ipairs(queue) do
			if item[3] == key then
				item[2], item[4] = msg, target
				return
			end
		end
	end
	if #queue >= MAX_QUEUE then
		-- Full: the oldest ordinary message goes (never an urgent one).
		local drop = 1
		for i, item in ipairs(queue) do
			if not item[5] then drop = i break end
		end
		table.remove(queue, drop)
	end
	local item = { dist, msg, key, target, urgent or nil }
	if urgent then
		local at = 1
		while queue[at] and queue[at][5] do at = at + 1 end
		table.insert(queue, at, item)
	else
		queue[#queue + 1] = item
	end
end

-- Other modules send small messages through here and register a handler per type.
--   Comm.Send("GUILD" | "CHANNEL", msg, dedupeKey)
--   Comm.Handle("P1", function(dist, sender, text) ... end)
local handlers = {}
function Comm.Send(dist, msg, key, urgent)
	if dist == "GUILD" and not IsInGuild() then return end
	Enqueue(dist, msg, key, nil, urgent)
end
-- An addon message to one player only (answers to the King, Throne tab).
function Comm.Whisper(target, msg, key, urgent)
	if type(target) ~= "string" or target == "" then return end
	Enqueue("WHISPER", msg, key, target, urgent)
end
function Comm.Handle(msgType, fn)
	handlers[msgType] = fn
end
-- Long payloads (> 255 bytes) go through the same chunking as reports; urgent ones (a
-- question to the army) ahead of the census, their pieces still in order.
function Comm.SendChunked(payload, urgent)
	msgId = (msgId + 1) % 1000
	for _, c in ipairs(Codec.Chunk(payload, tostring(msgId))) do Enqueue("CHANNEL", c, nil, nil, urgent) end
end
function Comm.ChannelReady()
	return channelIndex > 0
end

-- Chat lines wait in a short lane of their own: they never go through Enqueue, so they can
-- never push report chunks out of MAX_QUEUE. done(sent) is called once the part went out
-- (or was dropped). Returns false when the lane is full.
function Comm.SendChat(msg, done)
	if #chatQueue >= CHAT_QUEUE then return false end
	chatQueue[#chatQueue + 1] = { msg = msg, done = done, t = GetTime() }
	return true
end
function Comm.ChatRoom()
	return CHAT_QUEUE - #chatQueue
end

local function IsSuccess(res)
	-- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
	return res == nil or res == true or res == 0
end

-- Player text goes through the logged API, Blizzard's function for plain text payloads
-- (receivers get CHAT_MSG_ADDON_LOGGED). Clients without it use the usual one.
local function SendNow(dist, msg, logged, whisperTo)
	-- (A whisper goes to the name the server finds: ns.TellName.)
	local target = dist == "CHANNEL" and channelIndex or ns.TellName(whisperTo)
	local send = logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
	local ok, res = pcall(send, ns.PREFIX, msg, dist, target)
	if ok and IsSuccess(res) then
		stats.sent = stats.sent + 1
		return true
	end
	stats.fails = stats.fails + 1
	stats.lastFail = ("%s %s"):format(dist, tostring(res))
	ns.Log("send failed on %s: %s", dist, tostring(res))
	return false
end

-- Every chat part still waiting is dropped, and its sender is told.
local function DropChat()
	local items = {}
	for i, item in ipairs(chatQueue) do items[i] = item end
	wipe(chatQueue)
	for _, item in ipairs(items) do
		if item.done then ns.SafeCall("chat drop", item.done, false) end
	end
end

local function Pump()
	if not queue[1] and not chatQueue[1] then return end
	if not ns.IsMember() then
		wipe(queue) -- outside an Olympus guild the addon sends nothing
		DropChat()
		return
	end
	-- The channel may have been left (the Chat Channels panel) and its number given to another
	-- one: check before sending, or [Lords] text would go to that other channel.
	if channelIndex > 0 and joinedName and GetChannelName then
		local id = GetChannelName(joinedName) or 0
		if id ~= channelIndex then
			ns.Log("channel %s is now #%d (was #%d)", joinedName, id, channelIndex)
			channelIndex = id
		end
	end
	local now = GetTime()
	while chatQueue[1] and now - chatQueue[1].t > CHAT_TTL do
		local item = table.remove(chatQueue, 1)
		if item.done then ns.SafeCall("chat drop", item.done, false) end
	end
	-- Chat goes first, but while reports wait it takes at most every other slot: an idle lane
	-- sends a line within 1.2 s, and the total rate stays one message per SEND_INTERVAL.
	if chatQueue[1] and channelIndex > 0 and not (lastWasChat and queue[1]) then
		lastWasChat = true
		local item = table.remove(chatQueue, 1)
		local sent = SendNow("CHANNEL", item.msg, true)
		if item.done then ns.SafeCall("chat sent", item.done, sent) end
		return
	end
	lastWasChat = false
	-- Channel messages wait until we joined; guild messages behind them go out meanwhile.
	local index
	for i, item in ipairs(queue) do
		if item[1] ~= "CHANNEL" or channelIndex > 0 then
			index = i
			break
		end
	end
	if not index then return end
	local dist, msg, target = queue[index][1], queue[index][2], queue[index][4]
	table.remove(queue, index)
	SendNow(dist, msg, false, target)
end
Comm.Pump = Pump -- for tests

---------------------------------------------------------------------------
-- The shared channel. Without a key it is the public "OlympusNet". With a realm key (set by
-- an officer with /oly key, then passed to guildmates over GUILD messages, which the server
-- only delivers to members of that guild) the channel gets a name derived from the key and
-- the key as its password: outsiders can neither find it nor join it, edited code or not.
---------------------------------------------------------------------------

local function Hash36(text)
	local h1, h2 = 5381, 52711
	for i = 1, #text do
		local c = text:byte(i)
		h1 = (h1 * 33 + c) % 2147483647
		h2 = (h2 * 31 + c * 7) % 2147483647
	end
	local digits, out, n = "0123456789abcdefghijklmnopqrstuvwxyz", "", h1 * 1000 + (h2 % 1000)
	for _ = 1, 8 do
		local d = n % 36
		out = digits:sub(d + 1, d + 1) .. out
		n = math.floor(n / 36)
	end
	return out
end
Comm.Hash36 = Hash36

-- Each faction has its own channel (and sealed name), so the Horde and the Alliance never
-- mix their census, chat or decrees, whether or not the game shares channel names between them.
function Comm.ChannelSpec()
	local horde = ns.faction == "Horde"
	local key = ns.rdb and ns.rdb.realmKey
	if key and key ~= "" then return (horde and "OlyH" or "Oly") .. Hash36(key), key end
	return horde and ns.CHANNEL_HORDE or ns.CHANNEL, nil
end

local function HideChannelFromChat(name)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, name) end
	end
end

---------------------------------------------------------------------------
-- The channel's owner. Our hidden channel is an ordinary custom chat channel: the first
-- player in owns it, and when the owner leaves WoW hands it (and a moderator's seat) to
-- another member, so any player with the addon can end up owning it. An owner could /password
-- it (nobody who logs in afterwards gets in, and the network dies as people relog), /ban or
-- /ckick players (the King, the Treasurer), make a friend /moderator or give it away with
-- /owner. Olympus never uses these powers against anyone. It follows the channel's notices,
-- tells a player who was handed the channel what that means, and while the channel is ours it
-- only undoes harm (Comm.HealChannel). A channel locked against us is tried again, slower and
-- slower (Comm.JoinChannel). There is no other name to flee to: whoever locks one name can
-- squat any name we could predict as easily, and clients on different names would split the
-- army. We keep knocking on the same door until an honest owner opens it.
---------------------------------------------------------------------------

-- What we know of the channel named `name`, from its notices: a new record when we move to
-- another channel (the realm key arrived).
local function NewGuard(name)
	return { name = name, mine = {}, banned = {}, muted = {}, seen = {} }
end
local guard = NewGuard(nil)
local told = {}          -- role -> true once the player was told this session
local toldLocked = false -- ...and about a channel locked against us
local healAt = {}        -- healing call -> when it was last made (HEAL_GAP)
local healPending, rolePending = false, false
local healRefused = false -- the game refused one of these calls to addons: no more this session
local joinTries = 0      -- JoinChannelByName calls: one failed join counts once, however many notices say so

local function GuardFor(name)
	if guard.name ~= name then guard = NewGuard(name) end
	return guard
end

-- Our channel, whatever form a notice gives its name ("OlympusNet" or "5. OlympusNet").
local function OurChannel(...)
	local ours = joinedName or Comm.ChannelSpec()
	if type(ours) ~= "string" then return nil end
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if type(n) == "string" and n ~= "" and n:gsub("^%d+%.%s*", ""):lower() == ours:lower() then return ours end
	end
	return nil
end

local function IsMe(name)
	if type(name) ~= "string" or name == "" or not ns.me then return false end
	if ns.Channels and ns.Channels.IsMe then return ns.Channels.IsMe(name) end
	return ns.FullName(ns.Normal(name)) == ns.me
end

-- A name the way the server finds it again (ns.TellName), or nil.
local function ServerName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.TellName(name)
end

-- list[name] = when, at most MAX_HURT names (the oldest goes).
local function Remember(list, name, now)
	name = ServerName(name)
	if not name then return end
	local n, oldest = 0, nil
	for k, t in pairs(list) do
		n = n + 1
		if not oldest or t < list[oldest] then oldest = k end
	end
	if not list[name] and n >= MAX_HURT then list[oldest] = nil end
	list[name] = now
end

local function Mine(g) return g.mine.owner or g.mine.moderator end

-- Players the channel must never lose, the way the server finds them: the Treasurer, and the
-- King's character when our client knows it (our own roster in his guild, or a character
-- pinned in Core.lua).
local function Protected()
	local out, seen = {}, {}
	local function Add(name)
		name = ServerName(name)
		if name and not seen[name:lower()] then
			seen[name:lower()] = true
			out[#out + 1] = name
		end
	end
	Add(ns.TREASURER)
	local pinned = ns.KING_CHARACTER
	if type(pinned) == "table" then pinned = pinned[ns.faction or "Alliance"] end
	Add(pinned)
	if ns.IsKingGuild and ns.IsKingGuild(GetGuildInfo("player")) and ns.Roster and type(ns.Roster.byName) == "table" then
		for name, rank in pairs(ns.Roster.byName) do
			if rank == 0 then Add(name) break end
		end
	end
	return out
end

-- One healing call, protected, the same one at most every HEAL_GAP: "done", "failed",
-- "later" (too soon: try again) or "missing" (this client has no such function).
local function HealCall(what, fn, ...)
	if type(fn) ~= "function" or healRefused then return "missing" end
	local now = ns.Now()
	if now - (healAt[what] or -math.huge) < HEAL_GAP then return "later" end
	healAt[what] = now
	local ok, err = pcall(fn, ...)
	ns.Log("channel %s: %s%s", tostring(guard.name), what, ok and "" or (" failed: " .. tostring(err)))
	return ok and "done" or "failed"
end

local function HealSoon(delay)
	if healPending then return end
	healPending = true
	ns.After(delay or 2, "channel heal", function()
		healPending = false
		Comm.HealChannel()
	end)
end

-- Only while the channel is ours (owner or moderator), only to undo harm, never against
-- anyone: the password it should have (none on the public channel, the key on the sealed
-- one), no moderation, and whoever was banned or muted while we were on it let back in, the
-- Treasurer and the King always. Only for the channel we are meant to be on: what we saw on
-- another one (the public channel once we have a key) changes nothing.
-- What someone does with the channel from our own client is not undone here: the next owner's
-- client does it.
function Comm.HealChannel()
	local g = guard
	local name, key = Comm.ChannelSpec()
	if not name or g.name ~= name or not Mine(g) or not ns.IsMember() then return end
	if type(GetChannelName) ~= "function" or (GetChannelName(name) or 0) == 0 then return end
	local later = false
	local function Do(what, fn, ...)
		local r = HealCall(what, fn, ...)
		if r == "later" then later = true end
		return r
	end
	-- The password: after a change we saw, or when the channel came to us and we had not
	-- watched it since we joined (a /reload forgets what was seen before it).
	if g.password or g.unwatched then
		if Do("password " .. (key and "back to the key" or "cleared"), SetChannelPassword, name, key or "") ~= "later" then
			g.password, g.unwatched = nil, nil
		end
	end
	-- Moderation is switched over, not set: only when we know it is on, once for each time we
	-- saw it turned on. (Today's clients have no ChannelModerate: nobody can turn it on either.)
	if g.moderationOn and Do("moderation off", ChannelModerate, name) ~= "later" then g.moderationOn = nil end
	local unban = {}
	for who in pairs(g.banned) do unban[who] = true end
	if g.protect then
		for _, who in ipairs(Protected()) do unban[who] = true end
	end
	local waiting = false
	for who in pairs(unban) do
		if Do("unban " .. who, ChannelUnban, name, who) == "later" then waiting = true else g.banned[who] = nil end
	end
	if not waiting then g.protect = nil end
	-- (No ChannelUnmute in today's clients either: kept for one that has it.)
	for who in pairs(g.muted) do
		if Do("unmute " .. who, ChannelUnmute, name, who) ~= "later" then g.muted[who] = nil end
	end
	if later then HealSoon(HEAL_GAP) end
end

-- Handed the channel (owner or moderator): the player is told once a session what that
-- means, then the heal runs. A moment later, so an owner's two notices make one line.
local function RoleGiven(g)
	if rolePending then return end
	rolePending = true
	ns.After(2, "channel role", function()
		rolePending = false
		if guard ~= g or not Mine(g) then return end
		local role = g.mine.owner and "owner" or "moderator"
		if not told[role] then
			told[role] = true
			if role == "owner" then told.moderator = true end
			ns.Print("|cffffd200" .. (role == "owner" and ns.L.CHANNEL_OWNER_YOU or ns.L.CHANNEL_MODERATOR_YOU):format(g.name) .. "|r")
		end
		Comm.HealChannel()
	end)
end

-- Joining failed: a password or a ban. The player is told once a session; the next try waits
-- LOCKED_RETRY (see Comm.JoinChannel).
local function Locked(g, why, now)
	local lock = g.locked
	if not lock then
		lock = { why = why, tries = 0, since = now }
		g.locked = lock
		if not toldLocked then
			toldLocked = true
			ns.Print("|cffffd200" .. ns.L.CHANNEL_LOCKED:format(g.name) .. "|r")
		end
	end
	lock.why = why
	if lock.try == joinTries then return end
	lock.try = joinTries
	lock.tries = lock.tries + 1
	lock.nextAt = now + LOCKED_RETRY[math.min(lock.tries, #LOCKED_RETRY)]
	ns.Log("channel %s locked against us (%s, try %d): next try in %ds", g.name, why, lock.tries, lock.nextAt - now)
end

-- In again after being locked out: the census missed in the meantime is asked for.
local function Unlocked(g)
	if not g.locked then return end
	ns.Log("channel %s open to us again after %d tries", g.name, g.locked.tries)
	g.locked = nil
	askTries = 0
	ns.After(ASK_AFTER, "census request", Comm.AskCensus)
end

-- CHAT_MSG_CHANNEL_NOTICE and CHAT_MSG_CHANNEL_NOTICE_USER: (notice type, player, language,
-- "5. OlympusNet", second player, flags, zone channel id, channel number, "OlympusNet", ...).
-- With two players (banned, kicked, unbanned) the first is the one it happened to and the
-- second who did it. Only our channel's notices count.
function Comm.OnChannelNotice(notice, player, _, channelName, player2, _, _, _, baseName)
	-- Forever may hand these over as secret values while chat is locked down: nothing to read.
	if type(issecretvalue) == "function" and (issecretvalue(notice) or issecretvalue(player) or issecretvalue(player2)) then return end
	if type(notice) ~= "string" then return end
	local name = OurChannel(baseName, channelName)
	if not name then return end
	local g, now = GuardFor(name), ns.Now()
	player = type(player) == "string" and player ~= "" and player or nil
	player2 = type(player2) == "string" and player2 ~= "" and player2 or nil
	if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
		g.watched = true -- in from the start: every change after this reaches us
		Unlocked(g)
	elseif notice == "YOU_LEFT" or notice == "SUSPENDED" then
		g.mine, g.watched = {}, nil -- whoever leaves gives the channel away
	elseif notice == "WRONG_PASSWORD" or notice == "BANNED" then
		Locked(g, notice, now)
	elseif notice == "OWNER_CHANGED" or notice == "CHANNEL_OWNER" then
		if notice == "OWNER_CHANGED" then Count(g.seen, "owner") end
		g.owner, g.ownerAt = player, now
		if not IsMe(player) then
			g.mine.owner = nil
		elseif not g.mine.owner then
			g.mine.owner = true
			g.unwatched = not g.watched or nil
			g.protect = true
			RoleGiven(g)
		end
	elseif notice == "SET_MODERATOR" or notice == "UNSET_MODERATOR" then
		if not IsMe(player) then
			if notice == "SET_MODERATOR" then Count(g.seen, "moderator") end -- a seat handed to someone else
		elseif notice == "UNSET_MODERATOR" then
			g.mine.moderator = nil
		elseif not g.mine.moderator then
			g.mine.moderator = true
			g.protect = true
			RoleGiven(g)
		end
	elseif notice == "PASSWORD_CHANGED" then
		Count(g.seen, "password")
		if not IsMe(player) then g.password = { by = player, t = now } end
	elseif notice == "MODERATION_ON" or notice == "MODERATION_OFF" then
		Count(g.seen, "moderation")
		g.moderation = notice == "MODERATION_ON" and "on" or "off"
		g.moderationOn = notice == "MODERATION_ON" and not IsMe(player) or nil
	elseif notice == "ANNOUNCEMENTS_ON" or notice == "ANNOUNCEMENTS_OFF" then
		g.announce = notice == "ANNOUNCEMENTS_ON" and "on" or "off"
	elseif notice == "PLAYER_BANNED" or notice == "PLAYER_KICKED" then
		Count(g.seen, notice == "PLAYER_BANNED" and "ban" or "kick")
		if IsMe(player) then
			g.mine, g.watched = {}, nil
		elseif notice == "PLAYER_BANNED" and not IsMe(player2) then
			Remember(g.banned, player, now)
		end
	elseif notice == "PLAYER_UNBANNED" then
		local who = ServerName(player)
		if who then g.banned[who] = nil end
	elseif notice == "UNSET_SPEAK" or notice == "UNSET_VOICE" then
		Count(g.seen, "mute")
		Remember(g.muted, player, now)
	elseif notice == "SET_SPEAK" or notice == "SET_VOICE" then
		local who = ServerName(player)
		if who then g.muted[who] = nil end
	elseif notice == "MUTED" then
		Count(g.seen, "we muted") -- we may not speak there
	else
		return
	end
	ns.Log("channel %s: %s %s%s", name, notice, tostring(player or "-"), player2 and (" by " .. player2) or "")
	if Mine(g) then HealSoon() end
end

-- Blizzard's own password prompt for our channel: the same as a wrong password.
function Comm.OnPasswordRequest(channel)
	local name = OurChannel(channel)
	if name then Locked(GuardFor(name), "WRONG_PASSWORD", ns.Now()) end
end

-- None of the calls above is marked protected, but should the game ever refuse one to addons,
-- the first refusal ends healing for the session: never a string of "blocked" warnings.
function Comm.OnActionRefused(addon, func)
	if addon ~= ADDON or type(func) ~= "string" then return end
	if func:find("SetChannelPassword", 1, true) or func:find("ChannelUn", 1, true) or func:find("ChannelModerate", 1, true) then
		healRefused = true
		ns.Log("channel healing off for this session: the game refused %s", func)
	end
end

-- For /oly status: the channel's owner as last seen, our seat, what was seen.
function Comm.GuardStats()
	local g, now = guard, ns.Now()
	local function Size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	return {
		name = g.name, owner = g.owner, ownerAt = g.ownerAt,
		role = g.mine.owner and "owner" or (g.mine.moderator and "moderator" or "member"),
		moderation = g.moderation, announce = g.announce, seen = g.seen, watched = g.watched == true,
		banned = Size(g.banned), muted = Size(g.muted), password = g.password ~= nil,
		locked = g.locked and { why = g.locked.why, tries = g.locked.tries, nextIn = math.max(0, (g.locked.nextAt or now) - now) },
	}
end

function Comm.JoinChannel()
	if not ns.IsMember() then return end
	local name, password = Comm.ChannelSpec()
	if joinedName and joinedName ~= name then
		-- Another channel (the realm key arrived): votes heard on the old one don't count here,
		-- and its reporters have not heard our census request.
		if ns.Data and ns.Data.ForgetVotes then ns.Data.ForgetVotes() end
		askTries = 0
		ns.After(10, "census request", Comm.AskCensus)
	end
	if joinedName and joinedName ~= name and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName) -- the key changed: leave the old channel
		channelIndex = 0
	end
	if joinedName ~= name then watch = nil end -- another channel: the election guard starts again
	joinedName = name
	local id = GetChannelName(name)
	if id and id > 0 then
		if channelIndex ~= id then ns.Log("channel %s is #%d", name, id) end
		channelIndex = id
		HideChannelFromChat(name)
		return
	end
	-- Locked against us (a password or a ban): not before the next try is due (Locked).
	local lock = guard.name == name and guard.locked
	if lock and ns.Now() < (lock.nextAt or 0) then return end
	joinTries = joinTries + 1
	ns.Log("joining channel %s%s", name, password and " (sealed)" or "")
	watch = nil -- time off this channel says nothing about what we hear on it (election guard)
	JoinChannelByName(name, password)
	ns.After(3, "channel check", function()
		channelIndex = GetChannelName(name) or 0
		if channelIndex > 0 and guard.name == name then Unlocked(guard) end
		Comm.joinedAt = ns.Now()
		ns.SafeCall("channel last", Comm.KeepLast)
		ns.Log("channel %s -> #%d", name, channelIndex)
		HideChannelFromChat(name)
	end)
end

function Comm.ChannelName() return joinedName end
function Comm.DeliveredLogged() return deliveredLogged end

-- Who can read the channel, as the privacy questions tell the player (Layers, Channels):
-- anyone without a realm key, whoever holds the key with one.
function Comm.Audience()
	return (ns.rdb and ns.rdb.realmKey) and ns.L.CHANNEL_SEALED or ns.L.CHANNEL_PUBLIC
end

-- No key? Ask our guild (officers who have it answer, over GUILD).
function Comm.RequestKey()
	if ns.IsMember() and ns.rdb and not ns.rdb.realmKey then Enqueue("GUILD", "K0~", "keyreq") end
end

-- /oly key <secret>: officers seal the channel; guildmates receive the key automatically.
function Comm.SetRealmKey(secret)
	if not ns.IsMember() or not ns.Roster.IsOfficer() then
		ns.Print(ns.L.KEY_OFFICERS_ONLY)
		return
	end
	secret = (secret or ""):gsub("[~|\n]", "")
	if #secret < 6 then
		ns.Print(ns.L.KEY_TOO_SHORT)
		return
	end
	ns.rdb.realmKey = secret
	Enqueue("GUILD", "K1~" .. secret, "key")
	ns.Print(ns.L.KEY_SET)
	Comm.JoinChannel()
end

-- In a full guild, 1000 members saying hello every minute would be ~16 messages per second.
-- Only names that could win the reporter election need to keep talking: once 10 members
-- that sort before us are known, we go quiet (still one hello per 10 minutes to be counted).
local lastHello = 0
-- force: now, whatever the above (the player changed what the hello says).
function Comm.Hello(force)
	if not IsInGuild() then return end
	local now, before = ns.Now(), 0
	for name, t in pairs(peers) do
		if now - t <= PEER_WINDOW and name < (ns.me or "") and (benched[name] or 0) <= now then before = before + 1 end
	end
	if not force and before >= 10 and now - lastHello < 600 then return end
	lastHello = now
	-- Our realm rides along: guildmates on another realm show in /oly status (topology). So does
	-- our channel: without the key we can't hear a reporter on the sealed one (MaybeBroadcast).
	-- And "z" when we share our zone (0.9.1): our guild's reporter may name it then, never
	-- otherwise. Older versions read the fields before it and ignore the rest.
	local sealed = ns.rdb and ns.rdb.realmKey and "s" or "p"
	local zone = ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing() and "~z" or ""
	Enqueue("GUILD", "H1~" .. ns.VERSION .. "~" .. tostring(ns.realm) .. "~" .. sealed .. zone, "hello")
end

-- Does this guildmate share their zone (their hello says so, or it is us and we do)? By the
-- short name the roster gives, like heardOwn: the roster and guild messages may write the
-- realm apart. Only while they are counted (COUNT_WINDOW): quiet peers say hello every 10 min.
function Comm.SharesZone(name)
	if type(name) ~= "string" or name == "" then return false end
	local short = ns.ShortName(ns.Normal(name)):lower()
	if ns.me and short == ns.ShortName(ns.me):lower() then
		return ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing() or false
	end
	local now = ns.Now()
	for peer, t in pairs(peers) do
		if peerZone[peer] and now - t <= COUNT_WINDOW and ns.ShortName(peer):lower() == short then return true end
	end
	return false
end

-- The peers that may be elected: every one, but those left out by the guard below.
local function Electable(now)
	local pool = {}
	for name, t in pairs(peers) do
		if (benched[name] or 0) <= now then pool[name] = t end
	end
	return pool
end

-- When our last report counts as sent, for a sender reporting every `every` seconds: a census
-- answer sends the next due report early (Q1 below), and the one after it then waits a full
-- period from when the answered one was due. Answers move reports forward, never add one.
local function LastReport(every)
	if early and early.every == every and early.due > lastBroadcast then return early.due end
	return lastBroadcast
end

function Comm.MaybeBroadcast(report)
	local now = ns.Now()
	-- Peers are keyed "Name-Realm" like ns.me, so every client compares the same strings.
	local pool = Electable(now)
	local best = Codec.PickReporter(ns.me, pool, now, PEER_WINDOW)
	-- Rollout guard: a peer that wins the election but never reports (an old or broken
	-- version, or one that is not on the channel) keeps our guild off everyone's census.
	-- Elected for GUARD_AFTER while we are on the channel and never heard reporting our guild
	-- there, it is left out for GUARD_FOR and the next one is elected (maybe us).
	-- A reporter on the sealed channel is not ours to judge while we have no key: we can't hear
	-- it, and its reports reach the guilds they should. We ask for the key instead.
	local deaf = best ~= ns.me and peerSealed[best] == "s" and not (ns.rdb and ns.rdb.realmKey)
	if deaf then
		watch = nil
		if now - (lastKeyAsk or Comm.loginAt or 0) >= KEY_ASK_EVERY then
			lastKeyAsk = now
			Comm.RequestKey()
		end
	elseif best ~= ns.me and channelIndex > 0 then
		if not watch or watch.name ~= best then watch = { name = best, since = now } end
		if now - math.max(watch.since, heardOwn[ns.ShortName(best)] or 0) >= GUARD_AFTER then
			benched[best] = now + GUARD_FOR
			ns.Log("reporter %s never heard in %ds: left out of the election for %dm", best, GUARD_AFTER, GUARD_FOR / 60)
			pool[best], watch = nil, nil
			best = Codec.PickReporter(ns.me, pool, now, PEER_WINDOW)
		end
	else
		watch = nil
	end
	Comm.isReporter = best == ns.me
	Comm.reporterName = ns.DisplayName(best)
	Comm.lastReport = report
	-- The runner-up of the election reports too, every WITNESS_EVERY: a report never proves
	-- its own sender's rank, so other guilds trust a reporter who leads the guild (or is an
	-- officer) only once a second sender names them (Data.KnownRank).
	local second
	if not Comm.isReporter then
		-- Only a peer that can back the reporter: on 0.7.11 or later (older ones never send a
		-- runner-up report) and on the same channel as the reporter (sealed or public).
		local rest = {}
		for name, t in pairs(pool) do
			if name ~= best and peerRealm[name] ~= "old" and (peerSealed[name] == nil or peerSealed[name] == peerSealed[best]) then
				rest[name] = t
			end
		end
		second = Codec.PickReporter(ns.me, rest, now, PEER_WINDOW)
	end
	-- Only while the reporter is heard on our channel: the point is to back an active one.
	Comm.isRunnerUp = second == ns.me and best ~= nil and now - (heardOwn[ns.ShortName(best)] or -math.huge) <= 2 * BROADCAST_EVERY
	local every = Comm.isReporter and BROADCAST_EVERY or (Comm.isRunnerUp and WITNESS_EVERY or nil)
	if not every or now - LastReport(every) < every then return end
	-- Right after login we don't know our guildmates yet and would wrongly think we are the
	-- reporter: wait one hello round first.
	if now - (Comm.loginAt or 0) < HELLO_EVERY + 10 then return end
	Comm.Broadcast(report)
end

function Comm.Broadcast(report)
	lastBroadcast = ns.Now()
	msgId = (msgId + 1) % 1000
	-- Where people are goes out only with their yes (0.9.1): nothing of it unless we share our
	-- own zone, and then the counts per zone and the zones of the leader and officers who
	-- share theirs. Our own window keeps the whole report (it never leaves this client).
	local sharing = ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()
	local payload = Codec.EncodeReport(Codec.Shareable(report, sharing, sharing and Comm.SharesZone or nil))
	local chunks = Codec.Chunk(payload, tostring(msgId))
	for _, c in ipairs(chunks) do Enqueue("CHANNEL", c) end
	ns.Log("broadcast %s: %d bytes in %d chunks", report.guild, #payload, #chunks)
end

-- The census on request. The Forever beta client saves addon data but never loads it back, so
-- every login starts with an empty census: we ask the channel (Q1), and each guild's reporter
-- sends its report right away instead of within 3 minutes. Bounded: a reporter answers at
-- most once every ANSWER_GAP, and only if its last report is ANSWER_MIN_AGE old. A reporter
-- that had just answered someone else stays quiet, so we ask once more ASK_AGAIN later, unless
-- a report came meanwhile (the reporters are answering; the quiet ones report on their own
-- within BROADCAST_EVERY).
-- Tries again a little later while the channel is not joined yet (at most 3 times), and once
-- more after the channel changes (the realm key arrived).
function Comm.AskCensus()
	if not ns.IsMember() then return end
	if channelIndex == 0 then
		askTries = askTries + 1
		if askTries < 3 then ns.After(20, "census request", Comm.AskCensus) end
		return
	end
	-- Login and a guild change can both ask within seconds: once a minute is enough.
	local now = ns.Now()
	if Comm.lastAsk and now - Comm.lastAsk < 60 then return end
	Comm.lastAsk = now
	stats.asked = stats.asked + 1
	Enqueue("CHANNEL", "Q1~", "censusreq")
	if stats.asked == 1 then
		local heard = stats.reports
		ns.After(ASK_AGAIN, "census request", function()
			if stats.reports > heard then return end
			Comm.AskCensus()
		end)
	end
end

-- We join as soon as the game's own channels are in (General is /1 for two seconds), so
-- General/Trade/LocalDefense keep their usual numbers (/1, /2...), and at JOIN_BY whatever
-- happens. The census request follows ASK_AFTER later, once the channel has its number.
function Comm.JoinSoon(t, seenAt)
	local _, first = GetChannelName(1)
	if first and first ~= "" then seenAt = seenAt or t end
	if t >= JOIN_BY or (seenAt and t - seenAt >= 2) then
		Comm.JoinChannel()
		ns.After(ASK_AFTER, "census request", Comm.AskCensus)
		return
	end
	ns.After(1, "join channel", function() Comm.JoinSoon(t + 1, seenAt) end)
end

-- For tests: the channel we joined.
function Comm.JoinedName() return joinedName end
function Comm.SetJoinedForTest(name) joinedName = name end

-- Our hidden channel after the game's own. Joined before them (a slow login), it took /1 and
-- pushed General to /2, Trade to /3: moved past each of the game's channels numbered after
-- it, they get their usual numbers back. The player's own channels and other addons' keep
-- theirs.
function Comm.KeepLast()
	if not joinedName or not GetChannelList then return end
	local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
	local infoOf = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
	if not swap or not infoOf then return end
	local ours = GetChannelName(joinedName) or 0
	if ours <= 0 then return end
	local list = { GetChannelList() }
	local stride = type(list[3]) == "boolean" and 3 or 2 -- (id, name, disabled) or (id, name)
	local after = {}
	for i = 1, #list, stride do
		local id = tonumber(list[i])
		local ok, info = pcall(infoOf, list[i + 1])
		-- The game's channels (General, Trade...) are zone channels; custom ones are not.
		if id and id > ours and ok and type(info) == "table" and (tonumber(info.zoneChannelID) or 0) > 0 then after[#after + 1] = id end
	end
	if #after == 0 then return end
	table.sort(after)
	local at = ours
	for _, id in ipairs(after) do
		if not pcall(swap, at, id) then break end
		at = id
	end
	channelIndex = GetChannelName(joinedName) or channelIndex
	ns.Log("channel %s moved from #%d to #%d", joinedName, ours, channelIndex)
end

-- Right after login we may think we are the reporter only because we have not heard our
-- guildmates yet (see MaybeBroadcast): no answers then.
local function Settled(now)
	return now - (Comm.loginAt or 0) >= HELLO_EVERY + 10
end

-- The reporter answers, and the runner-up too (a little later): a client that just logged in
-- then has two senders' word on each guild at once, which the Crown needs (Data.KnownRank).
-- Every login asks, so with thousands of players requests never stop: an answer is the next
-- due report sent early (LastReport), and the reporter still sends one report per
-- BROADCAST_EVERY, the runner-up one per WITNESS_EVERY, however many ask.
Comm.Handle("Q1", function(dist, sender, text)
	if dist ~= "CHANNEL" or not Comm.lastReport or not (Comm.isReporter or Comm.isRunnerUp) then return end
	local now = ns.Now()
	local every = Comm.isReporter and BROADCAST_EVERY or WITNESS_EVERY
	local gap = Comm.isReporter and ANSWER_GAP or WITNESS_ANSWER_GAP
	if not Settled(now) or now - lastAnswer < gap or now - LastReport(every) < ANSWER_MIN_AGE then return end
	lastAnswer = now
	stats.answered = stats.answered + 1
	-- A short random delay spreads the answers of every guild.
	local delay = Comm.isReporter and math.random(1, 8) or math.random(9, 16)
	ns.After(delay, "census answer", function()
		local later = ns.Now()
		if not (Comm.isReporter or Comm.isRunnerUp) or not Comm.lastReport or not Settled(later) then return end
		local period = Comm.isReporter and BROADCAST_EVERY or WITNESS_EVERY
		local last = LastReport(period)
		if later - last < ANSWER_MIN_AGE then return end
		Comm.Broadcast(Comm.lastReport)
		early = { every = period, due = last + period }
	end)
end)

local function OnAddonMessage(prefix, text, dist, sender, target, zoneChannelID, localID, channelName)
	if prefix ~= ns.PREFIX then return end
	if type(sender) ~= "string" or sender == "" then return end
	-- Only our channel counts: an outsider in any other channel we sit in could otherwise
	-- reach us there, past the sealed channel. Clients that don't give the number pass.
	if dist == "CHANNEL" then
		if not stats.chanArgs then
			stats.chanArgs = ("localID=%s name=%s target=%s"):format(tostring(localID), tostring(channelName), tostring(target))
		end
		if type(localID) == "number" and localID > 0 and localID ~= channelIndex then
			-- Our number may be stale (just after a /reload, or the channel moved): ask again.
			local name = joinedName or Comm.ChannelSpec()
			local id = name and GetChannelName and GetChannelName(name) or 0
			if id and id > 0 and joinedName then channelIndex = id end
			if id ~= localID then
				stats.otherChannel = stats.otherChannel + 1
				return
			end
		end
	end
	-- The sender as the server sent it: which realms get a suffix tells the realms apart.
	local lane, rawRealm = dist == "CHANNEL" and "ch" or "g", sender:match("%-(.+)$")
	Count(stats.raw[lane], rawRealm or "bare")
	local sample = stats.rawSample[lane]
	if not sample or (rawRealm and not sample:find("-", 1, true)) then stats.rawSample[lane] = sender end
	-- Same-realm senders arrive without "-Realm": make every name "Name-Realm" once, here
	-- (and Forever's "First-Surname" the server's "First Surname": ns.Normal).
	sender = ns.FullName(ns.Normal(sender))
	if sender == ns.me then
		stats.echo = stats.echo + 1 -- our own message coming back (proves the channel works)
		return
	end
	if not ns.IsMember() then return end -- outside an Olympus guild the addon hears nothing
	if ns.db.blocked[sender:lower()] then return end
	stats.recv = stats.recv + 1
	local kind = (dist == "CHANNEL" and "ch:" or "g:") .. (text:match("^C%w+:") and "chunk" or text:sub(1, 2))
	Count(stats.byType, kind) -- (unknown prefixes fold into "other": a flood of them stays small)
	local now = ns.Now()
	-- Realm key, only over GUILD (server-verified guildmates) and only from our officers.
	if dist == "GUILD" and text:sub(1, 3) == "K1~" then
		local rank = ns.Roster.RankOf(sender)
		if rank and rank <= ns.CAPTAIN_RANK then
			local key = text:sub(4)
			if key ~= "" and key ~= ns.rdb.realmKey then
				ns.rdb.realmKey = key
				ns.Log("realm key received from officer %s", sender)
				Comm.JoinChannel()
			end
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "K0~" then
		-- A guildmate asks for the key: officers who have it answer (at most once a minute).
		if ns.rdb.realmKey and ns.Roster.IsOfficer() and now - (Comm.lastKeyAnswer or 0) > 60 then
			Comm.lastKeyAnswer = now
			ns.After(math.random(1, 5), "key answer", function() Enqueue("GUILD", "K1~" .. ns.rdb.realmKey, "key") end)
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "H1~" then
		if not peers[sender] then ns.Log("peer %s (%s)", sender, text:sub(4)) end
		peers[sender] = now
		peerRealm[sender] = Codec.RealmField(text:match("^H1~[^~]*~([^~]+)")) or "old"
		peerVersion[sender] = text:match("^H1~(%d+%.%d+%.%d+)") or "?"
		local sealed = text:match("^H1~[^~]*~[^~]*~([^~]*)")
		peerSealed[sender] = (sealed == "s" or sealed == "p") and sealed or nil
		peerZone[sender] = text:match("^H1~[^~]*~[^~]*~[^~]*~([^~]*)") == "z" or nil
		return
	end
	local handler = handlers[text:sub(1, 2)]
	if handler and text:sub(3, 3) == "~" then
		handler(dist, sender, text)
		return
	end
	if dist == "CHANNEL" then
		local full = Codec.Feed(asm, sender, text, now)
		if not full then return end
		local fullHandler = handlers[full:sub(1, 2)]
		if fullHandler and full:sub(3, 3) == "~" then
			fullHandler(dist, sender, full)
			return
		end
		local r = Codec.DecodeReport(full)
		if not r then
			stats.bad = stats.bad + 1
			ns.Log("bad report from %s: %s", sender, full:sub(1, 80))
			return
		end
		stats.reports = stats.reports + 1
		-- A report from a reporter on another realm proves the channel crosses realms.
		Count(stats.reportRealms, r.from or "old")
		if r.from and r.from ~= ns.realm then ns.rdb.shared = { realm = r.from, to = ns.realm, t = now } end
		-- Our guild's reporter is heard: the election guard (MaybeBroadcast) leaves it in.
		local own = GetGuildInfo("player")
		if own and r.guild:lower() == own:lower() then
			local short = ns.ShortName(sender)
			heardOwn[short] = now
			for name in pairs(benched) do
				if ns.ShortName(name) == short then benched[name] = nil end
			end
		end
		if ns.Data.Receive(r, sender) then
			ns.Log("report %s from %s: %d members, %d online", r.guild, sender, r.total, r.online)
		end
	end
end

-- Outside an Olympus guild the addon stays out of the channel (called when the guild changes).
-- Joining is left to the housekeeping ticker, so we never jump ahead of General/Trade at login.
function Comm.CheckMembership()
	if ns.IsMember() then
		-- Joined an Olympus guild after login: ask for the census once we are on the channel.
		if stats.asked == 0 then
			askTries = 0
			Comm.AskCensus()
		end
		return
	end
	if joinedName and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName)
		ns.Log("left channel %s: not in an Olympus guild", joinedName)
		joinedName, channelIndex = nil, 0
		wipe(queue)
		DropChat()
	end
end

ns.On("LOGIN", function()
	Comm.loginAt = ns.Now()
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	-- No key yet? Ask our guild once (officers who have it answer).
	ns.After(20, "key request", Comm.RequestKey)
	ns.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
	-- Chat lines come through the logged API (the server keeps them, so they can be reported).
	ns.RegisterEvent("CHAT_MSG_ADDON_LOGGED", function(...)
		deliveredLogged = true
		local ok, err = pcall(OnAddonMessage, ...)
		deliveredLogged = false
		if not ok then error(err, 0) end
	end)
	-- Who holds our channel and what is done with it (the channel's owner, above).
	ns.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", Comm.OnChannelNotice)
	ns.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER", Comm.OnChannelNotice)
	ns.RegisterEvent("CHANNEL_PASSWORD_REQUEST", Comm.OnPasswordRequest)
	ns.RegisterEvent("ADDON_ACTION_BLOCKED", Comm.OnActionRefused)
	ns.RegisterEvent("ADDON_ACTION_FORBIDDEN", Comm.OnActionRefused)
	ns.After(3, "join channel", function() Comm.JoinSoon(3) end)
	ns.After(6, "hello", Comm.Hello)
	ns.Every(HELLO_EVERY, "hello ticker", Comm.Hello)
	ns.Every(SEND_INTERVAL, "send pump", Pump)
	ns.Every(60, "housekeeping", function()
		local dropped, sample = Codec.Gc(asm, ns.Now())
		if dropped > 0 then
			stats.partial = stats.partial + dropped
			ns.Log("incomplete report dropped: %s", tostring(sample))
		end
		if channelIndex == 0 or GetChannelName(joinedName or (Comm.ChannelSpec())) == 0 then Comm.JoinChannel() end
	end)
	-- The game joins its own channels (General, Trade...) after ours on a slow login: ours
	-- moves behind them once the list settles.
	-- Only in the minutes after we joined: later changes are the player's.
	local lastPending = false
	ns.RegisterEvent("CHANNEL_UI_UPDATE", function()
		if lastPending or ns.Now() - (Comm.joinedAt or 0) > 180 then return end
		lastPending = true
		ns.After(2, "channel last", function()
			lastPending = false
			Comm.KeepLast()
		end)
	end)
end)
