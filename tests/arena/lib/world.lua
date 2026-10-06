-- 1.2, the Blood Arena's test world (the design): many clients in one Lua state, each with its own
-- namespace, saved data, clock-driven timers, events and WoW globals, talking through a fake Comm
-- that routes by lane as the game does. the arena's foundation's, frozen after the arena's core: a package that needs more writes
-- its own tests/arena/lib/<wp>-world.lua that extends World by composition.
--
--   local World = H.World
--   local w = World.New{ paced = false }             -- paced: Comm's 1.2 s and 60-item queue
--   local a = w:Client("Lida Fenn", { realm = "Emberfall", guild = "Olympus Ember" })
--   a.Arena.Send(...)            -- a module's functions run as that client (w:As swaps its globals)
--   w:Run(30)                    -- the clock moves: timers fire, queued messages go out
--   w:Sent{ from = a, type = "AF", dist = "CHANNEL" }, w:ChannelText()
--
-- Every name here is invented. The world overrides the King's, the Treasurer's and the author's
-- constants in each client, so no fixture holds a real name.
local H = ...
local World = {}
World.__index = World

World.REALMS = { "Emberfall", "Emberfall2" }
World.GROUP = "Emberfall+Emberfall2"
World.GUILD = "Olympus Ember"          -- an Olympus guild (ns.IsFederation)
World.KING_GUILD = "Olympus"           -- the Alliance King's guild (ns.KING_GUILD.Alliance)
World.KING_GUILD_HORDE = "Olympus Horde" -- the Horde King's, in this world
World.CLOCK = 1790000000
-- The cast (the design's invented names where it has them).
World.NAMES = {
	king = "Aldric Crownhall-Emberfall", kingHorde = "Grom Tuskbane-Emberfall",
	steward = "Marrek Oakhand-Emberfall", councillor = "Brannoc Weald-Emberfall", councillor2 = "Idris Vane-Emberfall",
	arbiter = "Oswin Marrow-Emberfall", auditor = "Hesta Quill-Emberfall", author = "Quillon Scribe-Emberfall",
	treasurer = "Tamsin Ledger-Emberfall", treasurerMail = "Tamsin Coinwell-Emberfall",
	feeReceiver = "Grukk Tallyhand-Emberfall", bank = "Coffrey Vault-Emberfall", hand = "Petra Wick-Emberfall",
	fighterA = "Torvin Hale-Emberfall", fighterB = "Selka Drummond-Emberfall",
	bettor1 = "Lida Fenn-Emberfall", bettor2 = "Parric Stowe-Emberfall", bettor3 = "Wenna Crale-Emberfall",
}
-- The High Council's lists signed with a throwaway key (tests/fixtures/arena-council.lua): the
-- councillors, the Steward and the arena's signed arbiters above.
World.COUNCIL = assert(loadfile(H.ROOT .. "tests/fixtures/arena-council.lua"))()

-- The core's files, as Olympus.toc lists them, from ArenaMath.lua on; and every file of ours a
-- stack may name, for the weight rule's count.
local function TocFiles()
	local out, arena = {}, false
	for line in io.lines(H.ADDON_DIR .. "Olympus.toc") do
		local file = line:match("^([%w_]+)%.lua%s*$")
		if file == "ArenaMath" then arena = true end
		if arena and file then out[#out + 1] = file end
	end
	return out
end
World.ARENA_FILES = TocFiles()
local ARENA_SOURCE = {}
for _, f in ipairs(World.ARENA_FILES) do ARENA_SOURCE[f] = true end
local function FromArena()
	local tb = debug.traceback("", 2)
	for file in tb:gmatch("Olympus[/\\]([%w_]+)%.lua") do
		if ARENA_SOURCE[file] then return true end
	end
	return tb:find("Olympus_Arena[/\\]") ~= nil
end
World.FromArena = FromArena

-- The existing modules a scenario asserts on (the design), in TOC order, loaded into each client.
World.MODULES = { "Channels", "King", "Treasury", "Dues", "Moderation", "Alts", "Workshop", "Consent" }
-- Loaded into each client too, before them, never shared: Ed25519.lua's job queue (one client's
-- signature checks never count against another's limit, nor run with its globals).
World.OWN = { "Ed25519" }
World.LOCALES = { "ArenaNetText", "ArenaMoneyText", "ArenaMarketsText", "ArenaFightsText", "ArenaFarkleText", "ArenaHomeText", "ArenaLotteryText",
	"ComplianceText" }
-- 1.1.6, the compliance gate (Compliance.lua): the scenarios of the 2.0 betting paths run with a test
-- row that allows every kind of wager, declared by each client (Compliance.REGIONS.TEST). The table
-- as it ships (1.1.6: no wager anywhere) is World.New{ compliance = "shipped" }'s, or one client's
-- (where.compliance = "shipped"; "open" gives one client of a shipped world the test row: a
-- modified client). tests/arena/compliance.lua holds the shipped gate's tests.
World.COMPLIANCE_TEST_ROW = { bet = true, stake = true, lottery = true, payout = true }

local function Copy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, x in pairs(v) do out[Copy(k, seen)] = Copy(x, seen) end
	return out
end
World.Copy = Copy

---------------------------------------------------------------------------
-- Stand-in frames (enough for the core and the companion's registry)
---------------------------------------------------------------------------

local FrameMethods = {}
local FrameMT = { __index = function(_, k) return FrameMethods[k] or function() end end }
local function NewFrame(kind, name, parent)
	return setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {}, events = {}, text = "" }, FrameMT)
end
function FrameMethods.Show(f) f.shown = true end
function FrameMethods.Hide(f) f.shown = false end
function FrameMethods.IsShown(f) return f.shown end
function FrameMethods.IsVisible(f) return f.shown end
function FrameMethods.SetShown(f, on) f.shown = on and true or false end
function FrameMethods.SetScript(f, kind, fn) f.scripts[kind] = fn end
function FrameMethods.GetScript(f, kind) return f.scripts[kind] end
function FrameMethods.HookScript(f, kind, fn) f.scripts[kind] = fn end
function FrameMethods.SetText(f, t) f.text = t end
function FrameMethods.GetText(f) return f.text end
function FrameMethods.SetTexture(f, texture) f.texture = texture end
function FrameMethods.GetName(f) return f.name end
function FrameMethods.GetParent(f) return f.parent end
function FrameMethods.SetParent(f, p) f.parent = p end
function FrameMethods.RegisterEvent(f, e) f.events[e] = true end
function FrameMethods.UnregisterEvent(f, e) f.events[e] = nil end
function FrameMethods.GetWidth() return 100 end
function FrameMethods.GetHeight() return 20 end
function FrameMethods.GetStringWidth(f) return #(tostring(f.text or "")) * 7 end
function FrameMethods.GetStringHeight() return 14 end
function FrameMethods.CreateTexture(f) return NewFrame("Texture", nil, f) end
function FrameMethods.CreateFontString(f) return NewFrame("FontString", nil, f) end
function FrameMethods.CreateAnimationGroup(f) return NewFrame("AnimationGroup", nil, f) end
-- (1.2: the games' windows ask their frames' levels and make animations: a level of 1 by default;
-- kept apart from the frame's own fields, as the client keeps it: the Find sheet's `level` is a row)
function FrameMethods.GetFrameLevel(f) return rawget(f, "frameLevel") or 1 end
function FrameMethods.SetFrameLevel(f, v) f.frameLevel = v end
function FrameMethods.CreateAnimation(f) return NewFrame("Animation", nil, f) end
World.NewFrame = NewFrame

---------------------------------------------------------------------------
-- The world
---------------------------------------------------------------------------

function World.New(opts)
	opts = opts or {}
	local w = setmetatable({ clock = opts.clock or World.CLOCK, clients = {}, sent = {}, failed = {}, timers = {}, groups = {},
		paced = opts.paced == true, council = opts.council ~= false, seq = 0, logged = false,
		compliance = opts.compliance, arenaFiles = opts.arenaFiles }, World)
	return w
end

function World:Find(name)
	if type(name) ~= "string" then return nil end
	local key = name:lower()
	for _, c in ipairs(self.clients) do
		if c.name:lower() == key or c.short:lower() == key then return c end
	end
	return nil
end
local function Of(w, c) if type(c) == "string" then return assert(w:Find(c), "no client " .. c) end return c end

-- fn(...) with that client's WoW globals in place (one Lua state, the design); errors propagate.
function World:As(c, fn, ...)
	c = Of(self, c)
	local g = c.globals
	local saved = {}
	for k in pairs(g) do saved[k] = rawget(_G, k) end
	-- The companion's saved variables are a global the client's own code writes: set, then taken back.
	local savedDB, startDB = rawget(_G, "OlympusArenaDB"), g.OlympusArenaDB
	for k, v in pairs(g) do rawset(_G, k, v) end
	rawset(_G, "OlympusArenaDB", startDB)
	local was = self.current
	self.current = c
	local res = { pcall(fn, ...) }
	local nowDB = rawget(_G, "OlympusArenaDB")
	if nowDB ~= startDB then g.OlympusArenaDB = nowDB end
	self.current = was
	for k in pairs(g) do if k ~= "OlympusArenaDB" then rawset(_G, k, saved[k]) end end
	rawset(_G, "OlympusArenaDB", savedDB)
	if not res[1] then error(res[2], 0) end
	return unpack(res, 2, table.maxn(res))
end

-- A proxy of a module table whose functions run as the client.
local function Proxy(w, c, t)
	return setmetatable({}, {
		__index = function(_, k)
			local v = t[k]
			if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
			return v
		end,
		__newindex = function(_, k, v) t[k] = v end,
	})
end

---------------------------------------------------------------------------
-- Timers (C_Timer, ns.After, ns.Every) on the world's clock
---------------------------------------------------------------------------

function World:Timer(c, sec, every, fn, where, iterations)
	self.seq = self.seq + 1
	local t = { c = c, at = self.clock + math.max(0, tonumber(sec) or 0), every = every and math.max(0.01, every) or nil, fn = fn,
		where = where, n = iterations, seq = self.seq, arena = FromArena(), session = c.session }
	function t.Cancel() t.cancelled = true end
	function t.IsCancelled() return t.cancelled == true end
	self.timers[#self.timers + 1] = t
	return t
end
-- The timers still to fire of a client (arena: only the ones an arena file made).
function World:Timers(c, arena)
	c = Of(self, c)
	local out = {}
	for _, t in ipairs(self.timers) do
		if t.c == c and not t.cancelled and t.session == c.session and (not arena or t.arena) then out[#out + 1] = t end
	end
	return out
end

local function Due(w, stop)
	local best
	for _, t in ipairs(w.timers) do
		if not t.cancelled and t.c.online and t.session == t.c.session and t.at <= stop and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best = t end
	end
	return best
end
local function NextPump(w)
	if not w.paced then return nil end
	local best
	for _, c in ipairs(w.clients) do
		if c.online and (c.comm.queue[1] or c.comm.chatq[1]) then
			local at = math.max(w.clock, c.comm.nextAt or -math.huge)
			if not best or at < best then best = at end
		end
	end
	return best
end

local function RetireTimers(w)
	local kept = {}
	for _, t in ipairs(w.timers) do
		if not t.cancelled and t.session == t.c.session then kept[#kept + 1] = t end
	end
	w.timers = kept
end

-- The clock moves `seconds`: timers fire in order, messages go out (1.2 s apart when paced).
function World:Run(seconds)
	local stop = self.clock + (tonumber(seconds) or 0)
	self:Flush()
	for step = 1, 200000 do
		-- Retired one-shot timers cannot fire again. Bound their scan cost during long runs;
		-- keep offline timers and the survivors' order, as the final cleanup always did.
		if step % 128 == 0 then RetireTimers(self) end
		local t, pump = Due(self, stop), NextPump(self)
		if pump and pump > stop then pump = nil end
		if not t and not pump then break end
		if pump and (not t or pump <= t.at) then
			self.clock = math.max(self.clock, pump)
			self:Flush()
		else
			self.clock = math.max(self.clock, t.at)
			if t.every then
				t.at = t.at + t.every
				if t.n then
					t.n = t.n - 1
					if t.n <= 0 then t.cancelled = true end
				end
			else
				t.cancelled = true
			end
			local ok, err = pcall(self.As, self, t.c, t.fn, t)
			if not ok then t.c.errors[#t.c.errors + 1] = "timer " .. tostring(t.where) .. ": " .. tostring(err) end
			self:Flush()
		end
	end
	self.clock = stop
	self:Flush()
	RetireTimers(self)
end

---------------------------------------------------------------------------
-- The fake Comm: Comm.lua's queue (a key replaces the waiting message and its done, urgent ones
-- first, 60 at most, the oldest ordinary one dropped), sent at once or 1.2 s apart (paced), routed
-- by lane as the game does: CHANNEL the sender's realm, GUILD its guild on every realm, WHISPER the
-- target, RAID and PARTY its group. Results the test chooses (3, 8, 11, 12...) fail the next sends;
-- a message over 255 bytes fails with 2 (Enum.SendAddonMessageResult.InvalidMessage) as the game
-- refuses it. Chat lines (Comm.SendChat) wait in a lane of their own, as Comm.lua's: 6 at most,
-- never counted by QueueSize, dropped ("late") after 30 s, and taking at most every other slot
-- while the queue waits.
---------------------------------------------------------------------------

World.MAX_QUEUE = 60
World.PACE = 1.2
World.MAX_MESSAGE = 255
World.CHAT_QUEUE, World.CHAT_TTL = 6, 30

local function FakeComm(w, c)
	local comm = { queue = {}, chatq = {}, handlers = {}, results = {} }
	c.comm = comm
	local C = { pieceHooks = {}, isReporter = false }
	local function Held(msg)
		local M = rawget(c.ns, "Moderation")
		return M ~= nil and not M.missing and M.Blocks and M.Blocks(msg) == true
	end
	local function Refused(done, why) if done then done(false, why) end end
	local function Enqueue(dist, msg, key, target, urgent, logged, done, chunked)
		local q = comm.queue
		if key then
			for _, item in ipairs(q) do
				if item.key == key then
					item.msg, item.target, item.logged = msg, target, logged
					if done then item.done = done end
					return
				end
			end
		end
		if #q >= World.MAX_QUEUE then
			local drop = 1
			for i, item in ipairs(q) do if not item.urgent then drop = i break end end
			local gone = table.remove(q, drop)
			if gone.done then w:As(c, gone.done, false, "dropped") end
		end
		local item = { dist = dist, msg = msg, key = key, target = target, urgent = urgent and true or nil, logged = logged, done = done, chunked = chunked }
		if urgent then
			local at = 1
			while q[at] and q[at].urgent do at = at + 1 end
			table.insert(q, at, item)
		else
			q[#q + 1] = item
		end
	end
	function C.Handle(kind, fn) comm.handlers[kind] = fn end
	function C.Send(dist, msg, key, urgent, logged, done)
		if dist == "GUILD" and not c.guild then return Refused(done, "guild") end
		if Held(msg) then return Refused(done, "held") end
		Enqueue(dist, msg, key, nil, urgent, logged, done)
	end
	function C.Whisper(target, msg, key, urgent, logged, done)
		if type(target) ~= "string" or target == "" then return Refused(done, "target") end
		if Held(msg) then return Refused(done, "held") end
		Enqueue("WHISPER", msg, key, target, urgent, logged, done)
	end
	-- (Comm.lua cuts a long payload in its own pieces and puts them together again: here it goes
	-- whole, as its receivers' handlers get it.)
	function C.SendChunked(payload, urgent, dist)
		Enqueue(dist == "GUILD" and "GUILD" or "CHANNEL", payload, nil, nil, urgent, nil, nil, true)
	end
	function C.SendChat(msg, done)
		if #comm.chatq >= World.CHAT_QUEUE or Held(msg) then return false end
		comm.chatq[#comm.chatq + 1] = { dist = "CHANNEL", msg = msg, logged = true, done = done, chat = true, t = w.clock }
		return true
	end
	function C.QueueSize() return #comm.queue end
	function C.QueueRoom() return World.MAX_QUEUE - #comm.queue end
	function C.ChatRoom() return World.CHAT_QUEUE - #comm.chatq end
	function C.DeliveredLogged() return w.logged end
	function C.ChannelReady() return true end
	function C.Hello() comm.hellos = (comm.hellos or 0) + 1 end
	function C.BankOnDuty()
		local A = rawget(c.ns, "Arena")
		return type(A) == "table" and type(A.OnDuty) == "function" and A.OnDuty("bank") == true
	end
	function C.Stats() return { sent = comm.sent or 0, queue = #comm.queue } end
	function C.Pump() return w:Pump(c, true) end
	return C
end

-- Who a message reaches.
function World:Recipients(from, dist, target)
	local out = {}
	if dist == "WHISPER" then
		local t = self:Find(target and (target:find("-", 1, true) and target or (target .. "-" .. from.realm)))
		if t and t.online then out[1] = t end
		return out
	end
	for _, c in ipairs(self.clients) do
		if c ~= from and c.online then
			local reach = false
			if dist == "CHANNEL" then reach = c.realm == from.realm and c.onChannel ~= false and from.onChannel ~= false
			elseif dist == "GUILD" then reach = c.guild ~= nil and c.guild == from.guild
			elseif dist == "RAID" or dist == "PARTY" then reach = from.groupId ~= nil and c.groupId == from.groupId end
			if reach then out[#out + 1] = c end
		end
	end
	return out
end

-- One message of that client's queue leaves: the result the test chose, else delivered.
function World:SendNow(c, item)
	local res = table.remove(c.comm.results, 1) or 0
	if res == 0 and #item.msg > World.MAX_MESSAGE and not item.chunked then res = 2 end
	local recipients = self:Recipients(c, item.dist, item.target)
	if res == 0 and item.dist == "WHISPER" and not recipients[1] then res = 12 end
	if res == 0 and (item.dist == "RAID" or item.dist == "PARTY") and not c.groupId then res = 5 end
	if res == 0 and item.dist == "RAID" and not (self.groups[c.groupId] and self.groups[c.groupId].raid) then res = 4 end
	if res ~= 0 then
		self.failed[#self.failed + 1] = { client = c, from = c.name, dist = item.dist, msg = item.msg, target = item.target, result = res, t = self.clock }
		-- (A chat line's done says "failed", as Comm.lua's lane says it.)
		if item.done then self:As(c, item.done, false, item.chat and "failed" or res) end
		return false
	end
	c.comm.sent = (c.comm.sent or 0) + 1
	self.sent[#self.sent + 1] = { client = c, from = c.name, realm = c.realm, dist = item.dist, msg = item.msg, target = item.target,
		logged = item.logged, urgent = item.urgent, t = self.clock }
	-- As the game delivers it: Comm strips "|" and control bytes from everything but a chat line.
	local text = item.msg
	if text:sub(1, 3) ~= "M1~" then text = text:gsub("[%c|]", "") end
	for _, r in ipairs(recipients) do
		local h = text:sub(3, 3) == "~" and r.comm.handlers[text:sub(1, 2)]
		if h then
			local was = self.logged
			self.logged = item.logged == true
			local ok, err = pcall(self.As, self, r, h, item.dist, c.name, text)
			self.logged = was
			if not ok then r.errors[#r.errors + 1] = "handler " .. text:sub(1, 2) .. ": " .. tostring(err) end
		end
	end
	if item.done then self:As(c, item.done, true) end
	return true
end
-- What that client may send now: everything (unpaced), or one message a PACE (paced). The chat
-- lane first, but at most every other slot while the queue waits; its lines that waited CHAT_TTL
-- are dropped.
function World:Pump(c, one)
	local comm = c.comm
	while (comm.queue[1] or comm.chatq[1]) and c.online do
		if self.paced and (comm.nextAt or -math.huge) > self.clock then return end
		while comm.chatq[1] and self.clock - comm.chatq[1].t > World.CHAT_TTL do
			local late = table.remove(comm.chatq, 1)
			if late.done then self:As(c, late.done, false, "late") end
		end
		local item
		if comm.chatq[1] and not (comm.lastWasChat and comm.queue[1]) then
			comm.lastWasChat = true
			item = table.remove(comm.chatq, 1)
		else
			comm.lastWasChat = false
			item = table.remove(comm.queue, 1)
		end
		if not item then return end
		comm.nextAt = self.clock + World.PACE
		self:SendNow(c, item)
		if self.paced or one then return end
	end
end
-- Delivers until nothing more may leave now.
function World:Flush()
	for _ = 1, 100000 do
		local any = false
		for _, c in ipairs(self.clients) do
			if c.online and (c.comm.queue[1] or c.comm.chatq[1]) and (not self.paced or (c.comm.nextAt or -math.huge) <= self.clock) then
				self:Pump(c)
				any = true
			end
		end
		if not any then return end
	end
	error("world: messages never settle")
end

-- The next sends of that client fail with these results (Enum.SendAddonMessageResult).
function World:Results(c, list)
	c = Of(self, c)
	for _, r in ipairs(list) do c.comm.results[#c.comm.results + 1] = r end
end

-- The messages sent, filtered: { from = client or name, type = "AF", dist = "CHANNEL", to = name }.
function World:Sent(f)
	f = f or {}
	local from = f.from and Of(self, f.from)
	local out = {}
	for _, s in ipairs(self.sent) do
		if (not from or s.client == from) and (not f.type or s.msg:sub(1, 2) == f.type) and (not f.dist or s.dist == f.dist)
			and (not f.to or (s.target or ""):lower() == f.to:lower()) then
			out[#out + 1] = s
		end
	end
	return out
end
-- Every byte that went on a channel (the privacy scans).
function World:ChannelText()
	local out = {}
	for _, s in ipairs(self.sent) do if s.dist == "CHANNEL" then out[#out + 1] = s.msg end end
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------

-- What loading Core.lua and Channels.lua writes to the game's tables: put back after each client.
local SAVED_GLOBALS = { "SLASH_OLYMPUS1", "SLASH_OLYMPUS2", "SLASH_OLYMPUSARENA1", "SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1",
	"SLASH_OLYMPUSLORDS1", "OlympusDB" }
local function Short(name) return (name:gsub("%-.*$", "")) end

local function Globals(w, c)
	local g = {}
	g.GetServerTime = function() return w.clock end
	g.GetTime = function() return w.clock end
	g.IsInGuild = function() return c.guild ~= nil end
	g.GetGuildInfo = function(unit)
		if unit == nil or unit == "player" then return c.guild, c.rankName, c.rank end
		local o = w:UnitClient(c, unit)
		if o then return o.guild, o.rankName, o.rank end
		return nil
	end
	g.UnitFullName = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		if not o then return nil end
		return o.short, o.realm
	end
	g.UnitName = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		if not o then return nil end
		return o.short, o.realm ~= c.realm and o.realm or nil
	end
	g.GetUnitName = function(unit, withRealm)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		if not o then return nil end
		return withRealm and (o.short .. "-" .. o.realm) or o.short
	end
	g.UnitGUID = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		return o and o.guid or nil
	end
	g.UnitExists = function(unit) return (unit == "player" or w:UnitClient(c, unit) ~= nil) end
	g.UnitIsPlayer = g.UnitExists
	g.UnitLevel = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		return o and o.level or 0
	end
	g.UnitFactionGroup = function() return c.faction end
	g.GetRealmName = function() return c.realm end
	g.GetNormalizedRealmName = function() return c.realm end
	g.IsInRaid = function() local grp = c.groupId and w.groups[c.groupId] return grp ~= nil and grp.raid == true end
	g.IsInGroup = function() return c.groupId ~= nil end
	g.GetNumGroupMembers = function() local grp = c.groupId and w.groups[c.groupId] return grp and #grp.members or 0 end
	g.InCombatLockdown = function() return c.combat == true end
	g.IsInInstance = function() return c.instance == true, c.instance and "party" or "none" end
	g.IsResting = function() return c.resting == true end
	g.C_ChatInfo = {
		InChatMessagingLockdown = function() return c.lockdown == true end,
		RegisterAddonMessagePrefix = function() return true end,
		SendAddonMessage = function() return 0 end,
		SendAddonMessageLogged = function() return 0 end,
	}
	g.C_Timer = {
		After = function(sec, fn) w:Timer(c, sec, nil, fn, "C_Timer.After") end,
		NewTicker = function(sec, fn, n) return w:Timer(c, sec, sec, fn, "C_Timer.NewTicker", n) end,
		NewTimer = function(sec, fn) return w:Timer(c, sec, nil, fn, "C_Timer.NewTimer") end,
	}
	g.C_AddOns = {
		LoadAddOn = function(name) return w:LoadAddOn(c, name) end,
		IsAddOnLoaded = function(name) return name == "Olympus" or (name == "Olympus_Arena" and c.companion.loaded == true) end,
		GetAddOnMetadata = function(name, field)
			if field ~= "Version" then return nil end
			if name == "Olympus_Arena" then return c.companion.version or World.CompanionVersion() end
			return c.ns and c.ns.VERSION
		end,
	}
	g.CreateFrame = function(kind, name, parent)
		local f = NewFrame(kind, name, parent)
		c.frames[#c.frames + 1] = { frame = f, arena = FromArena() }
		return f
	end
	g.GetMoney = function() return c.money end
	g.GetAddOnMemoryUsage = function(name)
		if name == "Olympus" then return 2048 end
		if name == "Olympus_Arena" then return c.companion.loaded and 512 or 0 end
		return 0
	end
	g.UpdateAddOnMemoryUsage = function() c.memoryUpdates = (c.memoryUpdates or 0) + 1 end
	g.hooksecurefunc = function(name, fn)
		if type(name) ~= "string" then return end
		c.hooks[name] = c.hooks[name] or {}
		table.insert(c.hooks[name], fn)
	end
	g.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		c.printed[#c.printed + 1] = table.concat(parts, " ")
	end
	g.OlympusArenaDB = nil
	g.ERR_TRADE_COMPLETE = "Trade complete."
	g.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
	-- Trade and mail (w:Trade, w:Mail): what this client's windows show now.
	g.GetTargetTradeMoney = function() return c.trade and c.trade.got or 0 end
	g.GetPlayerTradeMoney = function() return c.trade and c.trade.gave or 0 end
	g.GetTradePlayerItemInfo = function(i) local it = c.trade and c.trade.gaveItems and c.trade.gaveItems[i] if it then return it.name, nil, it.count or 1 end end
	g.GetTradeTargetItemInfo = function(i) local it = c.trade and c.trade.gotItems and c.trade.gotItems[i] if it then return it.name, nil, it.count or 1 end end
	g.GetTradePlayerItemLink = function(i) local it = c.trade and c.trade.gaveItems and c.trade.gaveItems[i] return it and it.link end
	g.GetTradeTargetItemLink = function(i) local it = c.trade and c.trade.gotItems and c.trade.gotItems[i] return it and it.link end
	g.GetSendMailMoney = function() return c.mailOut and c.mailOut.copper or 0 end
	g.GetSendMailCOD = function() return c.mailOut and c.mailOut.cod or 0 end
	g.GetSendMailItem = function() return nil end
	g.SendMail = function(to, subject)
		for _, fn in ipairs(c.hooks.SendMail or {}) do fn(to, subject, "") end
	end
	g.GetInboxNumItems = function() return #c.inbox end
	g.GetInboxHeaderInfo = function(i)
		local m = c.inbox[i]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, m.money, m.cod or 0, m.days or 30, false, false, m.returned == true, false, true, false
	end
	g.GetInboxInvoiceInfo = function() return nil end
	g.TakeInboxMoney = function(i) for _, fn in ipairs(c.hooks.TakeInboxMoney or {}) do fn(i) end end
	return g
end

-- The client a unit token names for c: "NPC" (the trade's other side), "target", "party1".., "raid1"..
function World:UnitClient(c, unit)
	if unit == "NPC" then return c.trade and c.trade.with or nil end
	if unit == "target" then return c.target and self:Find(c.target) or nil end
	local n = type(unit) == "string" and tonumber(unit:match("^party(%d)$") or unit:match("^raid(%d+)$"))
	if n and c.groupId then
		local members, i = self.groups[c.groupId].members, 0
		for _, m in ipairs(members) do
			if m ~= c or unit:find("^raid") then
				i = i + 1
				if i == n then return m end
			end
		end
	end
	return nil
end

function World.CompanionVersion()
	for line in io.lines(H.ROOT .. "Olympus_Arena/Olympus_Arena.toc") do
		local v = line:match("^## Version:%s*(%S+)")
		if v then return v end
	end
end

-- The companion as the game loads it (C_AddOns.LoadAddOn): its files, then its saved variables and
-- ADDON_LOADED. c.companion.state: "ok", "missing", "disabled", "interface", "dep".
local STATES = { missing = "MISSING", disabled = "DISABLED", interface = "INTERFACE_VERSION", dep = "DEP_DISABLED" }
function World:LoadAddOn(c, name)
	if name ~= "Olympus_Arena" then return false, "MISSING" end
	local state = c.companion.state or "ok"
	if STATES[state] then return false, STATES[state] end
	if c.companion.loaded then return true end
	c.companion.loaded = true
	c.companion.own = H.LoadCompanion(nil, { keepHandoff = true, version = c.companion.version })
	c.globals.OlympusArenaDB = c.saved and c.saved.heavy or nil
	rawset(_G, "OlympusArenaDB", c.globals.OlympusArenaDB)
	self:Fire(c, "ADDON_LOADED", "Olympus_Arena")
	return true
end
-- The companion loaded some other way than Olympus's (another addon's LoadAddOn, "load always"):
-- no handoff, so it does nothing.
function World:PreloadCompanion(c)
	c = Of(self, c)
	self:As(c, function()
		c.companion.loaded = true
		c.companion.own = H.LoadCompanion(false)
	end)
	self:Fire(c, "ADDON_LOADED", "Olympus_Arena")
end

-- A WoW event on that client's handlers (ns.RegisterEvent).
function World:Fire(c, event, ...)
	c = Of(self, c)
	local list = c.events[event]
	if not list then return 0 end
	local n = 0
	for _, e in ipairs(list) do
		local ok, err = pcall(self.As, self, c, e.fn, ...)
		if not ok then c.errors[#c.errors + 1] = "event " .. event .. ": " .. tostring(err) end
		n = n + 1
	end
	return n
end
-- The events registered on that client (arena: only by an arena file), a set.
function World:Events(c, arena)
	c = Of(self, c)
	local out = {}
	for event, list in pairs(c.events) do
		for _, e in ipairs(list) do
			if not arena or e.arena then out[event] = true end
		end
	end
	return out
end
function World:Frames(c, arena)
	c = Of(self, c)
	local n = 0
	for _, f in ipairs(c.frames) do if not arena or f.arena then n = n + 1 end end
	return n
end

-- The client's namespace: a table over the harness's, with Core.lua and the modules a scenario
-- asserts on loaded into it (their own locals, their own saved data), then the arena's files.
local function Load(w, c)
	local cns = setmetatable({}, { __index = H.ns })
	c.ns = cns
	local saved, slash, popups = {}, {}, {}
	for _, k in ipairs(SAVED_GLOBALS) do saved[k] = rawget(_G, k) end
	for k, v in pairs(SlashCmdList) do slash[k] = v end
	for k, v in pairs(StaticPopupDialogs) do popups[k] = v end
	w:As(c, function()
		-- (1.1.5: the gamepad gate, the client's own, loaded first as the TOC has it, so Core.lua's
		-- and the modules' hooks are never the harness's; its one event a no-op here.)
		cns.RegisterEvent = function() end
		assert(loadfile(H.ADDON_DIR .. "Gamepad.lua"))("Olympus", cns)
		assert(loadfile(H.ADDON_DIR .. "Core.lua"))("Olympus", cns)
		cns.Now = function() return w.clock end
		cns.RegisterEvent = function(event, fn)
			c.events[event] = c.events[event] or {}
			table.insert(c.events[event], { fn = fn, arena = FromArena() })
		end
		cns.After = function(sec, where, fn) w:Timer(c, sec, nil, function() cns.SafeCall(where, fn) end, where) end
		cns.Every = function(sec, where, fn) return w:Timer(c, sec, sec, function() cns.SafeCall(where, fn) end, where) end
		cns.CaptureError = function(where, err) c.errors[#c.errors + 1] = tostring(where) .. ": " .. tostring(err) end
		cns.Print = function(msg) c.printed[#c.printed + 1] = tostring(msg) end
		cns.Log = function(fmt, ...)
			local ok, s = pcall(string.format, fmt, ...)
			c.log[#c.log + 1] = ok and s or tostring(fmt)
		end
		cns.statusLines = {}
		cns.me, cns.realm, cns.group, cns.faction = c.name, c.realm, World.GROUP, c.faction
		cns.db, cns.rdb = c.db, c.rdb
		-- Invented names in place of the real constants (the design).
		cns.KING_CHARACTER = { Alliance = Short(World.NAMES.king), Horde = Short(World.NAMES.kingHorde) }
		cns.KING_GUILD = { Alliance = World.KING_GUILD:lower(), Horde = World.KING_GUILD_HORDE:lower() }
		cns.KING_REALM, cns.KING_REALM_HORDE = World.REALMS[1], World.REALMS[1]
		cns.KING_NAME = "the King"
		cns.TREASURER = Short(World.NAMES.treasurer)
		cns.TREASURER_CHARACTERS = { Short(World.NAMES.treasurer), Short(World.NAMES.treasurerMail) }
		cns.TREASURER_REALM = World.REALMS[1]
		cns.AUTHOR, cns.AUTHOR_REALM = Short(World.NAMES.author), World.REALMS[1]
		cns.TEST_BUILD = c.testBuild
		cns.Comm = FakeComm(w, c)
		for _, f in ipairs(World.OWN) do assert(loadfile(H.ADDON_DIR .. f .. ".lua"))("Olympus", cns) end
		for _, f in ipairs(World.MODULES) do assert(loadfile(H.ADDON_DIR .. f .. ".lua"))("Olympus", cns) end
		for _, f in ipairs(World.LOCALES) do assert(loadfile(H.ADDON_DIR .. "Locales/" .. f .. ".lua"))("Olympus", cns) end
		-- (opts.arenaFiles: another list of the core's arena files, a package profile's TOC.)
		for _, f in ipairs(w.arenaFiles or World.ARENA_FILES) do assert(loadfile(H.ADDON_DIR .. f .. ".lua"))("Olympus", cns) end
		if (c.compliance or w.compliance) ~= "shipped" and type(rawget(cns, "Compliance")) == "table" then
			-- Future account scenarios opt in explicitly; shipped-release tests keep it hidden.
			cns.Compliance.WALLET_ENABLED = true
			cns.Compliance.REGIONS = { TEST = World.COMPLIANCE_TEST_ROW }
			cns.Compliance.Declared = function() return "TEST", 30 end
		end
	end)
	-- (1.1.5: the slash commands are registered at login with mouse and keyboard, through the
	-- gate: the client's own, as its login would.)
	w:As(c, function() cns.Gate.Install("slash") end)
	for _, k in ipairs(SAVED_GLOBALS) do rawset(_G, k, saved[k]) end
	c.slashes = {}
	for k, v in pairs(SlashCmdList) do c.slashes[k] = v end
	wipe(SlashCmdList)
	for k, v in pairs(slash) do SlashCmdList[k] = v end
	c.popups = {}
	for k, v in pairs(StaticPopupDialogs) do c.popups[k] = v end
	wipe(StaticPopupDialogs)
	for k, v in pairs(popups) do StaticPopupDialogs[k] = v end
	-- The modules, as the client's: c.Arena.Send(...) runs as c.
	for _, m in ipairs({ "Arena", "ArenaRoles", "Comm", "King", "Treasury", "Dues", "Moderation", "Alts", "Workshop", "Channels", "Consent" }) do
		if rawget(cns, m) then c[m] = Proxy(w, c, cns[m]) end
	end
	c.Roles = c.ArenaRoles
end

-- Saved data as the game gives it at login: kept (persists) or gone (the Forever beta).
local function OpenData(c)
	local db = c.saved and c.saved.db or {}
	if not c.persists then db = {} end
	db.blocked, db.log, db.errors = db.blocked or {}, db.log or {}, db.errors or {}
	db.sessions = (db.sessions or 0) + 1
	db.links = db.links or {}
	for _, r in ipairs(World.REALMS) do db.links[r] = World.GROUP end
	db.addonChat, db.rollCall = true, true
	db.realms = db.realms or {}
	db.realms[World.GROUP] = db.realms[World.GROUP] or {}
	local rdb = db.realms[World.GROUP]
	rdb.guilds = rdb.guilds or {}
	c.db, c.rdb = db, rdb
	if not c.persists then c.saved = nil end
end

-- A client: name ("First Surname" on the first realm, or "First Surname-Realm"), and where =
-- { realm, guild (nil: none), rank (0 the guild master), faction, level, guid, money, persists
-- (false models the beta), companion = { state }, testBuild, council (false: no signed lists) }.
function World:Client(name, where)
	where = where or {}
	local realm = where.realm or (name:match("%-(.+)$")) or World.REALMS[1]
	local short = name:gsub("%-.*$", "")
	local full = short .. "-" .. realm
	assert(not self:Find(full), "a client twice: " .. full)
	self.seq = self.seq + 1
	local c = {
		name = full, short = short, realm = realm, faction = where.faction or "Alliance",
		guild = where.guild == false and nil or (where.guild or World.GUILD), rank = where.rank or 3, rankName = where.rank == 0 and "Guild Master" or "Member",
		level = where.level or 60, guid = where.guid or ("Player-%d-%08X"):format(4000 + #self.clients, 0x100000 + self.seq * 7919),
		money = where.money or 0, persists = where.persists ~= false, testBuild = where.testBuild, council = where.council, compliance = where.compliance,
		companion = where.companion or {}, events = {}, frames = {}, hooks = {}, inbox = {}, printed = {}, errors = {}, log = {},
		online = false, session = 0,
	}
	c.globals = Globals(self, c)
	self.clients[#self.clients + 1] = c
	self:Login(c)
	return c
end
-- A role of the cast, in the right guild (the King: guild master of the King's guild).
function World:Role(role, where)
	where = where or {}
	local name = assert(World.NAMES[role], "no role " .. tostring(role))
	if role == "king" and where.guild == nil then where.guild, where.rank = World.KING_GUILD, 0 end
	if role == "treasurer" and where.guild == nil then where.guild = World.KING_GUILD end
	if role == "kingHorde" then
		where.faction = "Horde"
		if where.guild == nil then where.guild, where.rank = World.KING_GUILD_HORDE, 0 end
	end
	return self:Client(name, where)
end

-- The signed High Council lists (the councillors, the Steward, the signed arbiters) taken by c.
function World:TakeCouncil(c)
	c = Of(self, c)
	local K = World.COUNCIL
	self:As(c, function()
		c.ns.Sign.WithKey(K.N, K.MU, K.K, function()
			-- (Kept from an earlier session where saved data persists: already held.)
			local held = type(c.rdb.councilTitles) == "table" and c.rdb.councilTitles.blob == K.TITLES
			if held then return end
			assert(c.ns.Workshop.TakeCouncil(K.NAMES), "the test council's names")
			assert(c.ns.Workshop.TakeTitles(K.TITLES), "the test council's titles")
		end)
	end)
end

function World:Login(c)
	c = Of(self, c)
	c.session = c.session + 1
	c.events, c.frames, c.hooks = {}, {}, {}
	c.companion.loaded, c.companion.own = nil, nil
	c.comm = nil
	OpenData(c)
	c.globals.OlympusArenaDB = nil
	Load(self, c)
	c.online = true
	if self.council and c.council ~= false then self:TakeCouncil(c) end
	self:As(c, function() c.ns.Fire("INIT") end)
	self:As(c, function() c.ns.Fire("LOGIN") end)
	self:Fire(c, "PLAYER_LOGIN")
	self:Fire(c, "PLAYER_ENTERING_WORLD", true, false)
	self:Flush()
	return c
end
-- The logout: PLAYER_LOGOUT runs, then the saved data is written (kept only where it persists).
function World:Logout(c)
	c = Of(self, c)
	self:Fire(c, "PLAYER_LOGOUT")
	c.saved = c.persists and { db = Copy(c.db), heavy = Copy(c.globals.OlympusArenaDB) } or nil
	c.online = false
	c.comm.queue, c.comm.chatq = {}, {}
	c.groupId = nil
	return c
end

---------------------------------------------------------------------------
-- The game around them
---------------------------------------------------------------------------

-- Puts these clients in one group (a raid with raid = true).
function World:Group(names, raid)
	self.seq = self.seq + 1
	local id = self.seq
	local grp = { raid = raid == true, members = {} }
	for _, n in ipairs(names) do
		local c = Of(self, n)
		c.groupId = id
		grp.members[#grp.members + 1] = c
	end
	self.groups[id] = grp
	return id
end
function World:Lockdown(c, on)
	c = Of(self, c)
	c.lockdown = on and true or nil
	if not on then self:Fire(c, "ZONE_CHANGED_NEW_AREA") end
end
function World:Combat(c, on)
	c = Of(self, c)
	c.combat = on and true or nil
	self:Fire(c, on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
function World:Money(c, copper) Of(self, c).money = copper end
-- A system line (a duel's, a roll's, the server's not found) on these clients.
function World:System(to, text)
	for _, n in ipairs(type(to) == "table" and not to.name and to or { to }) do self:Fire(n, "CHAT_MSG_SYSTEM", text, "", "", "", "", "", 0, 0, "", 0, 0, nil) end
end

-- A trade between a and b: { aGives, bGives (copper), aItems, bItems, complete }. Both sides see
-- TRADE_SHOW, the money, and on completion ERR_TRADE_COMPLETE, PLAYER_MONEY and TRADE_CLOSED.
function World:Trade(a, b, spec)
	a, b = Of(self, a), Of(self, b)
	spec = spec or {}
	a.trade = { with = b, gave = spec.aGives or 0, got = spec.bGives or 0, gaveItems = spec.aItems, gotItems = spec.bItems }
	b.trade = { with = a, gave = spec.bGives or 0, got = spec.aGives or 0, gaveItems = spec.bItems, gotItems = spec.aItems }
	for _, c in ipairs({ a, b }) do
		self:Fire(c, "TRADE_SHOW")
		self:Fire(c, "TRADE_MONEY_CHANGED")
		self:Fire(c, "TRADE_ACCEPT_UPDATE", 1, 1)
	end
	if spec.complete ~= false then
		for _, c in ipairs({ a, b }) do
			c.money = c.money - c.trade.gave + c.trade.got
			self:Fire(c, "UI_INFO_MESSAGE", 0, c.globals.ERR_TRADE_COMPLETE)
			self:Fire(c, "PLAYER_MONEY")
		end
	end
	for _, c in ipairs({ a, b }) do
		self:Fire(c, "TRADE_CLOSED")
		c.trade = nil
	end
	self:Flush()
end
World.POSTAGE = 30
-- A mail with gold: the sender's hooks and MAIL_SEND_SUCCESS; the recipient's inbox gets it.
function World:Mail(from, to, copper, subject, cod)
	from = Of(self, from)
	local target = Of(self, to)
	from.mailOut = { copper = copper or 0, cod = cod or 0, subject = subject or "" }
	self:As(from, function() SendMail(target.name, subject or "", "") end)
	from.money = from.money - (copper or 0) - World.POSTAGE
	self:Fire(from, "MAIL_SEND_SUCCESS")
	self:Fire(from, "PLAYER_MONEY")
	from.mailOut = nil
	target.inbox[#target.inbox + 1] = { sender = from.short, from = from, subject = subject or "", money = copper or 0, cod = cod or 0 }
	self:Fire(target, "MAIL_INBOX_UPDATE")
	self:Flush()
	return #target.inbox
end
-- The recipient takes mail i's gold.
function World:Take(to, i)
	local c = Of(self, to)
	local m = assert(c.inbox[i], "no mail " .. tostring(i))
	self:As(c, function() TakeInboxMoney(i) end)
	c.money = c.money + m.money
	m.money = 0
	self:Fire(c, "PLAYER_MONEY")
	self:Fire(c, "MAIL_INBOX_UPDATE")
	self:Flush()
end
-- The recipient returns mail i: it goes back to its sender, marked returned.
function World:Return(to, i)
	local c = Of(self, to)
	local m = assert(table.remove(c.inbox, i), "no mail " .. tostring(i))
	local back = m.from
	back.inbox[#back.inbox + 1] = { sender = c.short, from = c, subject = m.subject, money = m.money, cod = m.cod, returned = true }
	self:Fire(c, "MAIL_INBOX_UPDATE")
	self:Fire(back, "MAIL_INBOX_UPDATE")
	self:Flush()
end

-- What an arena file costs an idle client (the weight rule): its events, running timers, frames.
function World:ArenaWeight(c)
	c = Of(self, c)
	local events = {}
	for event in pairs(self:Events(c, true)) do events[#events + 1] = event end
	table.sort(events)
	return { events = events, timers = #self:Timers(c, true), frames = self:Frames(c, true) }
end

-- Errors the client's handlers, timers and events raised (ns.CaptureError and the world's own).
function World:Errors(c) return Of(self, c).errors end

return World
