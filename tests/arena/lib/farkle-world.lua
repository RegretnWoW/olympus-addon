-- 1.2, the Bone Throw tables (Bone Throw, the rules' "Farkle"): what the table's tests need of the game beyond
-- the arena's foundation's World (tests/arena/lib/world.lua), added by composition (the design's rule for packages):
--   - the server's /roll: RandomRoll(lo, hi) answers with the game's own line
--     (RANDOM_ROLL_RESULT, "%s rolls %d (%d-%d)"), on CHAT_MSG_SYSTEM, to the roller and to his
--     group, after a delay the test may set per receiver (w.lineDelay), with values the test may
--     queue (w:QueueRoll) or a seeded stand-in server's otherwise;
--   - the drunk lines (the design): the game's DRUNK_MESSAGE_* globals (enUS, from
--     tests/fixtures/arena-drunk-strings.lua) and w:Drink(name, level), the line the drinker and
--     everyone who sees him get;
--   - positions (UnitPosition), CheckInteractDistance, UnitIsConnected, UnitIsVisible, the /sit
--     emote and the party invite, for the tavern rule (the design) and the gap rule (the design).
-- Every name is invented.
--   local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
--   local w = FW.New()                       -- a World with the above
--   local a = w:Player("Torvin Hale")        -- a client, with the globals above
local H = ...
local World = H.World
local FW = {}

FW.DRUNK = assert(loadfile(H.ROOT .. "tests/fixtures/arena-drunk-strings.lua"))()
FW.ROLL = "%s rolls %d (%d-%d)"
-- The Goldshire inn's rest area (Olympus/ArenaPlaces.lua: cont 0, -9465.6, 16.8, r 30).
FW.INN = { cont = 0, wx = -9465.6, wy = 16.8 }
FW.ROAD = { cont = 0, wx = -9400.0, wy = 16.8 } -- 65 yd north of it: no inn

local Methods = {}

-- The stand-in server's /roll: Park-Miller, so the low digits the dice are read from are as
-- random as the high ones.
local function Rng(w, lo, hi)
	w.seed = (w.seed * 48271) % 2147483647
	return lo + w.seed % (hi - lo + 1)
end

-- Who sees c's roll line: himself and his group (the server's rule the design relies on).
local function Witnesses(w, c)
	local out = { c }
	local grp = c.groupId and w.groups[c.groupId]
	for _, m in ipairs(grp and grp.members or {}) do if m ~= c and m.online then out[#out + 1] = m end end
	return out
end

-- A line on each of these clients, each after its own delay (w.lineDelay(from, to) seconds, 0 by
-- default: at once, in the order given).
function Methods:Line(from, text, to)
	for _, r in ipairs(to or Witnesses(self, from)) do
		local d = self.lineDelay and self.lineDelay(from, r) or 0
		if d and d > 0 then
			self:Timer(r, d, nil, function() self:Fire(r, "CHAT_MSG_SYSTEM", text, "", "", "", "", "", 0, 0, "", 0, 0, nil) end, "roll line")
		elseif d ~= false then
			self:Fire(r, "CHAT_MSG_SYSTEM", text, "", "", "", "", "", 0, 0, "", 0, 0, nil)
		end
	end
end

-- The next roll of that player, in whatever range he rolls.
function Methods:QueueRoll(name, ...)
	local c = self:Find(name)
	local q = self.rollQ[c] or {}
	for _, v in ipairs({ ... }) do q[#q + 1] = v end
	self.rollQ[c] = q
end
-- A /roll the player typed (the server's line, whatever the addon asked).
function Methods:TypedRoll(name, lo, hi, value)
	local c = self:Find(name)
	local q = self.rollQ[c]
	value = value or (q and q[1] and table.remove(q, 1)) or Rng(self, lo, hi)
	self.rolls[#self.rolls + 1] = { who = c.name, lo = lo, hi = hi, value = value, t = self.clock }
	self:Line(c, FW.ROLL:format(c.short, value, lo, hi))
	return value
end
-- The rolls the game made, filtered by roller and range.
function Methods:Rolls(name, hi)
	local out = {}
	for _, r in ipairs(self.rolls) do
		if (not name or r.who:lower() == self:Find(name).name:lower()) and (not hi or r.hi == hi) then out[#out + 1] = r end
	end
	return out
end

-- A drunk line (the design): "You feel ..." to the drinker, "<name> looks ..." to everyone who sees him
-- (his group here, and whoever the test names in `to`).
function Methods:Drink(name, level, to)
	local c = self:Find(name)
	local S = FW.DRUNK.enUS
	self:Line(c, S["DRUNK_MESSAGE_SELF" .. (level + 1)], { c })
	local others = to or Witnesses(self, c)
	local list = {}
	for _, r in ipairs(others) do if r ~= c then list[#list + 1] = r end end
	self:Line(c, S["DRUNK_MESSAGE_OTHER" .. (level + 1)]:format(c.short), list)
end

-- Where a player stands ({ cont, wx, wy }), resting there or not.
function Methods:Stand(name, pos, resting)
	local c = self:Find(name)
	c.pos = pos and { cont = pos.cont, wx = pos.wx, wy = pos.wy } or nil
	if resting ~= nil then c.resting = resting and true or nil end
end
-- Both at the Goldshire inn, a few yards apart, resting.
function Methods:AtInn(...)
	for i, name in ipairs({ ... }) do self:Stand(name, { cont = FW.INN.cont, wx = FW.INN.wx + (i - 1) * 3, wy = FW.INN.wy }, true) end
end

local function Dist(a, b)
	if not a or not b or a.cont ~= b.cont then return nil end
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end
FW.Dist = Dist

-- The globals the table reads, for one client.
local function Extend(w, c)
	local g = c.globals
	local function Unit(unit) return unit == "player" and c or w:UnitClient(c, unit) end
	g.RANDOM_ROLL_RESULT = FW.ROLL
	for k, v in pairs(FW.DRUNK.enUS) do g[k] = v end
	g.RandomRoll = function(lo, hi)
		assert(type(lo) == "number" and type(hi) == "number", "RandomRoll takes two numbers")
		c.asked = c.asked or {}
		c.asked[#c.asked + 1] = { lo = lo, hi = hi, t = w.clock }
		if c.refuseRoll then error("ADDON_ACTION_FORBIDDEN RandomRoll", 0) end
		if c.dropRolls then return end
		w:TypedRoll(c.name, lo, hi)
	end
	g.UnitPosition = function(unit)
		local o = Unit(unit)
		if not o or not o.pos then return nil end
		return o.pos.wx, o.pos.wy, 0, o.pos.cont
	end
	g.CheckInteractDistance = function(unit, index)
		local o = Unit(unit)
		if not o then return false end
		local d = Dist(c.pos, o.pos)
		return d ~= nil and d <= (index == 3 and 10 or 28)
	end
	g.UnitIsConnected = function(unit) local o = Unit(unit) return o ~= nil and o.online and not o.linkdead end
	g.UnitIsVisible = function(unit) local o = Unit(unit) return o ~= nil and o.online and not o.unseen end
	g.DoEmote = function(token) c.emotes = c.emotes or {} c.emotes[#c.emotes + 1] = token end
	g.C_PartyInfo = { InviteUnit = function(name) c.invited = c.invited or {} c.invited[#c.invited + 1] = name end }
	g.C_Map = { GetBestMapForUnit = function() return 1429 end }
	g.PlaySound = function(kit, channel) c.sounds = c.sounds or {} c.sounds[#c.sounds + 1] = kit return true, #c.sounds end
	g.StopSound = function() end
end

-- A client of this world with the table's globals (World:Client's where, plus companion state
-- "missing" by default: the core's tests need no screens).
function Methods:Player(name, where)
	where = where or {}
	where.companion = where.companion or { state = "missing" }
	local c = self:Client(name, where)
	Extend(self, c)
	-- Protocol scenarios start at a valid inn; venue tests move players explicitly.
	self:Stand(c.name, FW.INN, true)
	-- Existing table scenarios start with players who finished the innkeeper lesson.
	-- New-player scenarios explicitly opt out; this seeds real saved state, not a gate mock.
	if where.bonesTrained ~= false then self:As(c, function() c.ns.FarkleTable.Opts().innkeeperLearned = true end) end
	return c
end

function FW.New(opts)
	local w = World.New(opts)
	w.seed = (opts and opts.seed or 1) % 2147483646 + 1
	w.rollQ, w.rolls = {}, {}
	for k, fn in pairs(Methods) do w[k] = fn end
	return w
end
FW.Extend = Extend

return FW
