-- 1.1.6, the Missionary Church of Olympus: a small world of clients for tests/church*.lua (not a test
-- file itself: each Church test file loads it). Every client has its own namespace over the harness's
-- (setmetatable, as tests/chat-rooms.lua builds its clients), its own saved data, roster, guild log
-- and WoW globals (World:As swaps them), and loads the real Church files (and ChatRooms.lua) into it.
-- Messages go through a fake Comm that routes as the game does: CHANNEL to everyone online on the
-- realm, GUILD to the sender's guild, WHISPER to the one name; the server stamps the sender.
-- Every name is invented; the author, the King and the council are this world's, never the addon's.
local ns, ROOT = ...

local World = {}
World.__index = World
World.EPOCH = 1800000000
World.GUILD = "Olympus Ember"
World.GUILD2 = "Olympus Vale"
World.AUTHOR = "Quill Scribe-Realm"
World.KING = "Aldo Crown-Realm"
World.HEAD = "Corin Ash-Realm"
World.COUNCILLOR = "Brin Tallow-Realm"
World.COUNCIL = assert(loadfile(ROOT .. "tests/fixtures/church-council.lua"))()
-- The Church's words, into the harness's locale table, as the game loads Locales/ChurchText.lua.
assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", ns)

local GLOBALS = { "GetGuildInfo", "IsInGuild", "InCombatLockdown", "QueryGuildEventLog", "GetNumGuildEvents", "GetGuildEventInfo",
	"UnitIsPlayer", "GetTime", "C_ChatInfo", "GetServerTime" }

local function Key(name) return ns.Fold(ns.ShortName(tostring(name or ""))) end
World.Key = Key

-- A world: opts.apostles (names, signed), opts.head (the Head, World.HEAD, signed as an Apostle
-- marked Head, "*"; false: none), opts.listAt (the signed list's time).
function World.New(opts)
	opts = opts or {}
	local w = setmetatable({ clock = World.EPOCH, clients = {}, byKey = {}, pending = {}, sent = {}, timers = {}, alts = {}, off = {},
		gm = {}, ranks = {}, council = {}, census = {}, log = {}, members = {} }, World)
	w.council[Key(World.HEAD)] = true
	w.council[Key("Dela Moss")] = true
	w.council[Key(World.COUNCILLOR)] = true
	w:SignedList(opts.apostles or {}, opts.head ~= false, opts.listAt or (World.EPOCH - 86400))
	return w
end

-- The signed titles list the world's clients hold (CouncilTitles' shape): the War department and
-- the ^apostles^ entry, the Head (one of the Twelve, marked "*") its first when `head`.
function World:SignedList(apostles, head, at)
	local depts = {}
	depts[#depts + 1] = "Department of War^^" .. ns.ShortName(World.COUNCILLOR) .. "=Marshal"
	local signed = {}
	if head then signed[1] = "*" .. World.HEAD end
	for _, n in ipairs(apostles) do signed[#signed + 1] = n end
	if #signed > 0 then depts[#depts + 1] = "^apostles^Alliance^" .. table.concat(signed, ",") end
	local field = table.concat(depts, ";")
	local parsed = {}
	parsed[#parsed + 1] = { name = "Department of War", members = { { name = ns.ShortName(World.COUNCILLOR) } } }
	self.titles = { at = at, depts = parsed, blob = ("HT1~%d~Realm~1~%s~%s"):format(at, field, ("ab"):rep(256)) }
end

local function Copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = Copy(v) end
	return o
end
World.Copy = Copy

-- A client. opts: guild (World.GUILD by default; false: none), rank (0: guild master), old (a client
-- before 1.1.6: none of the Church files), view (ChurchView.lua too), real (no stand-ins for the
-- council: the harness's own signed lists), rdb (saved data to start from).
function World:Client(name, opts)
	opts = opts or {}
	local w = self
	local full = name:find("-", 1, true) and name or (name .. "-Realm")
	local cl = { name = full, key = Key(full), guild = opts.guild == nil and World.GUILD or (opts.guild or nil), rank = opts.rank or 3,
		online = true, handlers = {}, listeners = {}, printed = {}, dialogs = {}, fired = {}, log = {}, combat = false, peers = opts.peers or 1,
		queries = 0, registered = {}, menu = nil, tabs = {} }
	local c = setmetatable({ me = full, realm = "Realm", faction = "Alliance", group = "Realm", rdb = opts.rdb or {},
		db = { chatRooms = true, addonChat = true } }, { __index = ns })
	cl.ns = c
	c.Now = function() return w.clock end
	c.Data = setmetatable({ ServerTime = function() return w.clock end,
		AuthorizedRank = function(who, guild)
			local r = w.census[ns.Fold(guild) .. ":" .. Key(who)]
			return r
		end,
		Summary = function()
			local out = { guilds = {} }
			for _, g in ipairs({ World.GUILD, World.GUILD2 }) do out.guilds[#out.guilds + 1] = { name = g, g = {}, fresh = true } end
			return out
		end }, { __index = ns.Data })
	c.IsMember = function() return cl.guild ~= nil and ns.IsFederation(cl.guild) end
	if not opts.real then
		c.IsKingCharacter = function(n) return type(n) == "string" and Key(n) == Key(World.KING) end
		c.KingCharacter = function() return World.KING end
		c.IsHighCouncillor = function(n) return type(n) == "string" and w.council[Key(n)] == true end
		c.CouncilTitles = function() return w.titles end
	end
	c.Workshop = { IsAuthorName = function(n) return type(n) == "string" and Key(n) == Key(World.AUTHOR) end,
		IsAuthor = function() return Key(c.me) == Key(World.AUTHOR) end }
	c.KingsScreen = function() return Key(c.me) == Key(World.KING) end
	c.ChatLocked = function() return w.locked == true end
	c.Alts = { Linked = function(n) return w.alts[Key(n)] or {} end }
	c.Moderation = { SelfOff = function() return w.off[cl.key] end, Hides = function(sender) return w.off[Key(sender)] end,
		YouText = function() return "net-off" end, Any = function() return false end }
	c.Dues = { WeekOf = function(t) return math.floor(t / (7 * 86400)) end, WeekStart = function(k) return k * 7 * 86400 end }
	c.Fire = function(event, ...)
		cl.fired[#cl.fired + 1] = event
		for _, fn in ipairs(cl.listeners[event] or {}) do fn(...) end
	end
	c.On = function(event, fn)
		cl.listeners[event] = cl.listeners[event] or {}
		table.insert(cl.listeners[event], fn)
	end
	c.Print = function(m) cl.printed[#cl.printed + 1] = tostring(m) end
	c.Log = function() end
	c.PlayAlert = function() end
	c.ShowDialog = function(which, a, b, data) cl.dialogs[#cl.dialogs + 1] = { which = which, a = a, b = b, data = data } return which end
	c.After = function(seconds, _, fn) w:Later(cl, seconds, fn) end
	c.Every = function() end
	c.RegisterEvent = function(event, fn) cl.registered[#cl.registered + 1] = event; cl.events = cl.events or {}; cl.events[event] = fn end
	c.Comm = {
		Handle = function(kind, fn) cl.handlers[kind] = fn end,
		Send = function(dist, msg, _, _, logged) return w:Queue(cl, dist, msg, nil, logged) end,
		Whisper = function(target, msg, _, _, logged) return w:Queue(cl, "WHISPER", msg, target, logged) end,
		QueueRoom = function() return w.room or 60 end,
		Hash36 = ns.Comm.Hash36,
		PeerCount = function() return cl.peers end,
		ChannelReady = function() return true end,
		ChannelName = function() return "OlympusNet" end,
		DeliveredLogged = function() return true end,
		Cancel = function() end, CancelQueued = function() return 0 end,
	}
	c.Channels = { IsMe = function(n) return Key(n) == cl.key end, Admit = function() return true, "ok" end }
	c.Consent = { Register = function() end, Ask = function() end }
	c.PlayerMenu = { Add = function(key, fn) cl.menu = fn end }
	c.Answers = { PAGES = {} }
	c.UI = { AddTab = function(t) cl.tabs[#cl.tabs + 1] = t return true end, RefreshSoon = function() end, IsShown = function() return false end,
		FirstTexture = function(list) return list[1] end, SelectTab = function(k) cl.selected = k end,
		ShowCopy = function(title, text) cl.copied = { title = title, text = text } end }
	c.Views = { COLUMNS = {}, Filter = function() return cl.filter or "" end, Query = function() return cl.filter and ns.Fold(cl.filter) or nil end,
		SetFilter = function(_, text) cl.filter = text ~= "" and text or nil end }
	c.ChatWindow = { Open = function() cl.chatOpened = true end, SelectLogical = function(id) cl.chatRoom = id return true end }
	-- The roster this client's guild shows (Roster.Fresh's shape).
	c.Roster = { complete = true, generation = 1, group = "Realm", faction = "Alliance" }
	function c.Roster.RankOf(n)
		if not cl.guild then return nil end
		local other = w.byKey[Key(n)]
		if other and other.guild == cl.guild then return other.rank end
		return nil
	end
	function c.Roster.Fresh() return cl.guild and c.Roster or nil end
	cl.c = c
	w.clients[#w.clients + 1] = cl
	w.byKey[cl.key] = cl
	w:RefreshRosters()
	if not opts.old then
		-- (ChatRooms.lua defines its request dialog in the game's global table: the harness's own is put back.)
		local harnessRequest = StaticPopupDialogs and StaticPopupDialogs.OLYMPUS_CHATROOM_REQUEST
		w:As(cl, function()
			assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
			if StaticPopupDialogs then StaticPopupDialogs.OLYMPUS_CHATROOM_REQUEST = harnessRequest end
			assert(loadfile(ROOT .. "Olympus/Church.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/ChurchCount.lua"))("Olympus", c)
			if opts.view then assert(loadfile(ROOT .. "Olympus/ChurchView.lua"))("Olympus", c) end
		end)
		c.Church.after = function(seconds, _, fn) w:Later(cl, seconds, fn) end
		c.ChurchCount.after = c.Church.after
		c.Church.random = function(a) return a end
		c.ChurchCount.random = function(a) return a end
		c.Church.chance = function() return 0 end
		c.ChurchCount.chance = function() return 0 end
		c.ChatRooms.Reset()
		cl.Church, cl.Count, cl.View = c.Church, c.ChurchCount, c.ChurchView
	end
	return cl
end

-- Every client's roster: the members of its guild in this world (and `extra` names: players with no
-- addon, w.members[guild]).
function World:RefreshRosters()
	self.members = self.members or {}
	for _, cl in ipairs(self.clients) do
		local rows, byName = {}, {}
		if cl.guild then
			for _, o in ipairs(self.clients) do
				if o.guild == cl.guild then rows[#rows + 1] = { full = o.name, name = ns.ShortName(o.name), rankIndex = o.rank }; byName[o.name] = o.rank end
			end
			for _, n in ipairs(self.members[cl.guild] or {}) do
				local f = n:find("-", 1, true) and n or (n .. "-Realm")
				if not byName[f] then rows[#rows + 1] = { full = f, name = ns.ShortName(f), rankIndex = 4 }; byName[f] = 4 end
			end
		end
		local R = cl.c.Roster
		R.members, R.byName, R.guild, R.snapshotAt = rows, byName, cl.guild, self.clock
		R.generation = (R.generation or 0) + 1
	end
end

-- Runs fn as this client: its WoW globals in place, put back after (even when fn fails).
function World:As(cl, fn, ...)
	local saved = {}
	for _, g in ipairs(GLOBALS) do saved[g] = _G[g] end
	local w = self
	GetGuildInfo = function() if cl.guild then return cl.guild, "Rank", cl.rank end return nil end
	IsInGuild = function() return cl.guild ~= nil end
	InCombatLockdown = function() return cl.combat == true end
	QueryGuildEventLog = function() cl.queries, cl.queried = cl.queries + 1, true end
	GetNumGuildEvents = function() return #(w.log[cl.guild or ""] or {}) end
	GetGuildEventInfo = function(i)
		local e = (w.log[cl.guild or ""] or {})[i]
		if not e then return nil end
		local ago = math.max(0, math.floor((w.clock - e.t) / 3600))
		local days, hours = math.floor(ago / 24), ago % 24
		return e.kind, e.p1, e.p2, 1, 0, 0, days, hours
	end
	UnitIsPlayer = function() return false end
	GetTime = function() return w.clock end
	GetServerTime = function() return w.clock end
	C_ChatInfo = { SendAddonMessageLogged = function() end, InChatMessagingLockdown = function() return false end }
	local out = { pcall(fn, ...) }
	for _, g in ipairs(GLOBALS) do _G[g] = saved[g] end
	if not out[1] then error(out[2], 0) end
	return unpack(out, 2)
end

function World:Queue(from, dist, msg, target, logged)
	if type(msg) ~= "string" or #msg > 255 then return false end
	if dist == "GUILD" and not from.guild then return false end
	local e = { from = from, dist = dist, msg = msg, target = target, logged = logged, at = self.clock }
	self.sent[#self.sent + 1] = e
	self.pending[#self.pending + 1] = e
	return true
end

-- Who hears one message: the channel, the guild, or the one name (online, and a member).
local function Recipients(w, e)
	local out = {}
	for _, cl in ipairs(w.clients) do
		if cl ~= e.from and cl.online and cl.guild and ns.IsFederation(cl.guild) then
			if e.dist == "CHANNEL" or (e.dist == "GUILD" and cl.guild == e.from.guild)
				or (e.dist == "WHISPER" and Key(e.target) == cl.key) then out[#out + 1] = cl end
		end
	end
	return out
end

function World:Deliver(e)
	for _, cl in ipairs(Recipients(self, e)) do
		local h = cl.handlers[e.msg:sub(1, 2)]
		if h and e.msg:sub(3, 3) == "~" then self:As(cl, h, e.dist, e.from.name, e.msg) end
		cl.log[#cl.log + 1] = e
	end
end

-- Every message waiting (and every one they cause), in order.
function World:Flush(max)
	local n = 0
	while #self.pending > 0 and n < (max or 5000) do
		local e = table.remove(self.pending, 1)
		n = n + 1
		self:Deliver(e)
	end
	return n
end

function World:Later(cl, seconds, fn)
	self.timers[#self.timers + 1] = { at = self.clock + (tonumber(seconds) or 0), cl = cl, fn = fn, seq = #self.timers }
end

-- The clock moves on `seconds`: due timers run (as their client), messages are delivered.
function World:Run(seconds)
	local stop = self.clock + (seconds or 0)
	self:Flush()
	while true do
		table.sort(self.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
		local t = self.timers[1]
		if not t or t.at > stop then break end
		table.remove(self.timers, 1)
		if t.at > self.clock then self.clock = t.at end
		self:As(t.cl, t.fn)
		self:Flush()
	end
	self.clock = stop
	self:Flush()
end

-- Each client's Church tick (presence, sync, reads, the desk), then the messages.
function World:Tick(list)
	for _, cl in ipairs(list or self.clients) do
		if cl.Church and cl.online then self:As(cl, cl.Church.Tick) end
	end
	self:Flush()
	self:AnswerLogs()
end

-- What a client sent: messages of `type` (two letters), optional dist and kind (the third field).
function World:Sent(from, kind, dist, sub)
	local out = {}
	for _, e in ipairs(self.sent) do
		if (not from or e.from == from) and e.msg:sub(1, 2) == kind and (not dist or e.dist == dist)
			and (not sub or e.msg:match("^%u%u~1~([^~]+)") == sub) then out[#out + 1] = e end
	end
	return out
end
function World:ClearSent() self.sent = {} end

-- A guild log event: kind invite (p1 invited p2), join (p1), quit (p1), remove (p1 removed p2), t
-- hours ago (the world's clock).
function World:LogEvent(guild, kind, p1, p2, hoursAgo)
	self.log = self.log or {}
	self.log[guild] = self.log[guild] or {}
	table.insert(self.log[guild], { kind = kind, p1 = p1, p2 = p2, t = self.clock - (hoursAgo or 0) * 3600 })
end

-- The server answers every client that asked for its guild's log (GUILD_EVENT_LOG_UPDATE).
function World:AnswerLogs()
	for _, cl in ipairs(self.clients) do
		if cl.queried and cl.events and cl.events.GUILD_EVENT_LOG_UPDATE then
			cl.queried = false
			self:As(cl, cl.events.GUILD_EVENT_LOG_UPDATE)
		end
	end
	self:Flush()
end

-- A client reads its guild's log now (the minute between reads waited out first): true when it read.
function World:ReadLog(cl)
	if cl.Count then
		local ok, why = self:As(cl, cl.Count.Read)
		if not ok and why == "gap" then
			self:Run(cl.Count.READ_GAP + 1)
			ok = self:As(cl, cl.Count.Read)
		end
		self:AnswerLogs()
		return ok
	end
	return false
end

-- Everyone says who he is (presence), as the ticker does, and the book syncs.
function World:Presence(list)
	for _, cl in ipairs(list or self.clients) do
		if cl.Church and cl.online then self:As(cl, cl.Church.SendPresence, true) end
	end
	self:Flush()
end

-- An act by a client, through the same function its Name page calls.
function World:Act(cl, fn, ...)
	local out = { self:As(cl, fn, ...) }
	self:Flush()
	return unpack(out)
end

function World:Printed(cl) return cl.printed[#cl.printed] end

return World
