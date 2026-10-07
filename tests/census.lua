-- Census boundaries and alt membership revisions. Loaded by tests/run.lua.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%.lua$")) or "./"
local Codec = ns.Codec

local function Decode(fields)
	fields.guild = fields.guild or "Olympus Test"
	return Codec.DecodeReport(Codec.EncodeReport(fields))
end

test("census: a zero-member report cannot contribute online members", function()
	local r = assert(Decode({ total = 0, online = 10000 }))
	eq(r.online, 0)
	eq(Decode({ total = 0, online = 10000, zones = { m1453 = 10000 } }), nil)
end)
test("census: zone, class and level distributions cannot exceed online members", function()
	for _, field in ipairs({ "zones", "classes", "levels" }) do
		local counts = field == "levels" and { 3, 3 } or { a = 3, b = 3 }
		local r = { total = 10, online = 5, [field] = counts }
		eq(Decode(r), nil, field .. ": individually plausible counts, impossible sum")
	end
	eq(Decode({ total = 1000, online = 5000, zones = { m1453 = 10000 } }), nil)
end)

test("census: partial, privacy-suppressed and older reports keep their wire contract", function()
	local r = assert(Decode({ total = 100, online = 20, zones = { m1453 = 3 }, classes = { WA = 2 }, levels = { 1, 1 } }))
	eq(r.online, 20); eq(r.zones.m1453, 3); eq(r.classes.WA, 2); eq(r.levels[1], 1)
	local hidden = Codec.Shareable(r, false, nil)
	local d = assert(Decode(hidden))
	eq(next(d.zones), nil); eq(d.online, 20)
	local old = assert(Codec.DecodeReport("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0"))
	eq(old.online, 2); eq(old.zones.m1453, 2)
	local clamped = assert(Decode({ total = 10, online = 20 }))
	eq(clamped.online, 10, "the existing online clamp remains")
end)

-- The source Alts module, with only identity/state/event/transport boundaries supplied by
-- this scene. Claims, revisions, grouping and duplicate counts all run through Alts.lua.
local function WithAlts(fn)
	local savedGuild, savedDialog = GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM
	local w = { now = 1800000000, guild = "Olympus Old" }
	GetGuildInfo = function() return w.guild end
	local function Client(me, own)
		local c = setmetatable({ me = me, realm = "Realm", db = {}, rdb = {}, sent = {}, timers = {}, events = {}, callbacks = {}, changes = 0 }, { __index = ns })
		c.Now = function() return w.now end
		c.Data = { ServerTime = c.Now }
		c.IsMember = function() return type(w.guild) == "string" and w.guild:find("Olympus", 1, true) ~= nil end
		c.On = function(event, cb) c.callbacks[event] = cb end
		c.RegisterEvent = function(event, cb) c.events[event] = cb end
		c.After = function(delay, label, cb) c.timers[#c.timers + 1] = { delay = delay, label = label, cb = cb } end
		c.Every = function() end
		c.Fire = function(event) if event == "DATA_CHANGED" then c.changes = c.changes + 1 end end
		c.Log = function() end
		c.Moderation = { Character = function() end }
		c.Comm = {
			Handle = function() end,
			Send = function(dist, msg) c.sent[#c.sent + 1] = { dist = dist, msg = msg } end,
		}
		if own then
			c.db.alts = {
				at = w.now - 10,
				links = { ["alt guy-realm"] = { name = "Alt Guy-Realm", main = "Main Guy-Realm", at = w.now - 10 } },
				guilds = { ["alt guy-realm"] = "Olympus Old", ["main guy-realm"] = "Olympus Main" },
			}
		end
		assert(loadfile(ROOT .. "Olympus/Alts.lua"))("Olympus", c)
		function c.Run(delay)
			local pending = c.timers
			c.timers = {}
			for _, timer in ipairs(pending) do
				if timer.delay <= delay then timer.cb() else c.timers[#c.timers + 1] = timer end
			end
		end
		return c
	end
	local ok, err = pcall(function() fn(w, Client) end)
	GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM = savedGuild, savedDialog
	if not ok then error(err, 0) end
end

local function Revision(msg) return assert(tonumber(msg:match("^AL~(%d+)~"))) end
local function GuildOf(alts, name)
	for _, member in ipairs(assert(alts.Group(name)).members) do
		if member.name == name then return member.guild end
	end
	error("missing group member " .. name)
end

test("alts: a live guild change revises and sends the claim, refreshing both clients' counts", function()
	WithAlts(function(w, Client)
		local c, peer = Client("Alt Guy-Realm", true), Client("Watcher-Realm")
		peer.Alts.Handle("CHANNEL", "Main Guy-Realm", ("AL~%d~M~Olympus Main~Alt Guy"):format(w.now - 10))
		assert(c.Alts.Send(false))
		local old = c.sent[1].msg
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(c.Alts, c.me), "Olympus Old")
		eq(GuildOf(peer.Alts, c.me), "Olympus Old")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 1)
		w.guild = "Olympus New"
		assert(c.events.PLAYER_GUILD_UPDATE, "membership changes are observed")("player")
		c.Run(2)
		eq(#c.sent, 2, "a guild change does not wait thirty minutes")
		local changed = c.sent[2].msg
		assert(Revision(changed) > Revision(old), "a changed guild has a newer revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New", "own cached group invalidated")
		peer.Alts.Handle("CHANNEL", c.me, changed)
		eq(GuildOf(peer.Alts, c.me), "Olympus New")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 0)
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus new"] = true }), 1)
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(peer.Alts, c.me), "Olympus New", "a delayed old claim cannot undo the move")
		local revision = c.db.alts.at
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		eq(c.db.alts.at, revision); eq(#c.sent, 2, "an unchanged guild produces no extra send")
	end)
end)

test("alts: login refresh revises a saved guild before the first claim", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		local old = c.db.alts.at
		w.guild = "Olympus New"
		c.callbacks.LOGIN()
		c.Run(10)
		assert(c.db.alts.at > old, "login membership change increments the wire revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New")
		eq(#c.sent, 0, "login still waits for its channel before sending")
		c.Run(c.Alts.LOGIN_AFTER)
		eq(#c.sent, 1)
		eq(Revision(c.sent[1].msg), c.db.alts.at)
		assert(c.sent[1].msg:find("~Olympus New~", 1, true))
	end)
end)

test("alts: leaving updates local membership without sending outside Olympus; rejoining advances again", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(true))
		local old = c.db.alts.at
		w.guild = nil
		assert(c.events.PLAYER_GUILD_UPDATE)("player"); c.Run(2)
		eq(GuildOf(c.Alts, c.me), nil)
		assert(c.db.alts.at > old)
		eq(#c.sent, 1, "no network claim outside Olympus")
		local left = c.db.alts.at
		w.guild = "Olympus New"
		c.events.PLAYER_GUILD_UPDATE("target"); c.Run(2)
		eq(c.db.alts.at, left, "another unit's event leaves this character alone")
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		assert(c.db.alts.at > left, "even multiple changes in one second are ordered")
		eq(#c.sent, 2)
	end)
end)

test("alts: the send path records a newly observed guild even without a delivered event", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(false))
		local old = Revision(c.sent[1].msg)
		w.guild = "Olympus New"
		assert(c.Alts.Send(false), "a new guild overrides the ordinary repeat interval")
		assert(Revision(c.sent[2].msg) > old)
		eq(c.db.alts.guilds["alt guy-realm"], "Olympus New")
		eq(c.Alts.Send(false), false, "repeats remain paced")
	end)
end)
