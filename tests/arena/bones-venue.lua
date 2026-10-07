-- Free peer games use the same real venues as counted tables, without changing money modes.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local function FT(c) return c.ns.FarkleTable end
local function As(w, c, fn, ...) return w:As(c, fn, ...) end
local function Errors(w)
	for _, c in ipairs(w.clients) do
		eq(#c.errors, 0, table.concat(c.errors, "; "))
		if c.K then eq(#c.K.errors, 0, table.concat(c.K.errors, "; ")) end
	end
end
local function Pair(ui)
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA)
	local b = w:Player(H.World.NAMES.fighterB, ui and { companion = {} } or nil)
	if ui then b.K = BoardUI.New(function() return w.clock end); b.K.Install(b.globals) end
	w:Stand(a.name, FW.INN, true)
	w:Stand(b.name, { cont = FW.INN.cont, wx = FW.INN.wx + 3, wy = FW.INN.wy }, true)
	return w, a, b
end
local function Agree(w, a, b)
	local id = assert(As(w, a, FT(a).Create, { guest = b.name, target = 2000, secs = 30 }))
	w:Run(0)
	assert(As(w, b, FT(b).Answer, id, true))
	w:Run(0)
	eq(FT(a).Get(id).state, "agreed")
	eq(FT(a).Get(id).needGroup, true)
	return id
end
local function Opening(w, a, b, id)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	assert(As(w, a, FT(a).Roll, id)); assert(As(w, b, FT(b).Roll, id))
	w:Run(0)
	eq(FT(a).Get(id).state, "play"); eq(FT(b).Get(id).state, "play")
end

test("Bones venue: keeper voice comes only from recognized gossip race and is session local", function()
	local w, a = Pair()
	local function Voice() return As(w, a, FT(a).InnkeeperVoice) end
	eq(Voice(), nil)
	local calls = 0
	a.globals.UnitGUID = function() return "Creature-0-1-0-1-999-00001" end
	a.globals.UnitRace = function() calls = calls + 1; return "Human", "Human" end
	eq(Voice(), nil); eq(calls, 0, "another NPC's race is never read")
	a.globals.UnitGUID = function() return "Creature-0-1-0-1-295-00001" end
	eq(Voice(), "Human"); eq(calls, 1)
	a.globals.UnitRace = function() return "Unknown", "Unknown" end
	eq(Voice(), nil, "unrecognized race stays unknown")
	a.globals.UnitRace = function() error("unavailable") end
	eq(Voice(), nil)
	a.globals.UnitRace = function() return "Human", "Human" end
	a.globals.issecretvalue = function(value) return value == "Human" end
	eq(Voice(), nil, "secret race is not used")
	a.globals.issecretvalue = nil
	a.globals.UnitGUID = function() return nil end
	eq(Voice(), "Human", "the known keeper's voice survives closing gossip")
	w:Stand(a.name, FW.ROAD, false); eq(Voice(), nil, "another place has no inferred voice")
	w:Stand(a.name, FW.INN, true)
	w:Logout(a); w:Login(a); FW.Extend(w, a)
	eq(Voice(), nil, "no race observation is saved across sessions")
	Errors(w)
end)

test("Bones venue: a delayed keeper move waits outside the inn without completing training", function()
	local w, a = Pair()
	As(w, a, function() FT(a).Opts().innkeeperLearned = nil end)
	local id = assert(As(w, a, FT(a).Practice, { first = 2, target = 2000 }))
	local t = FT(a).Get(id)
	w:Run(0.4)
	local events = #t.game.events
	w:Stand(a.name, FW.ROAD, false); w:Run(4)
	eq(#t.game.events, events, "the pending roll cannot apply outside its inn")
	eq(As(w, a, FT(a).TrainingComplete), false)
	w:Stand(a.name, FW.INN, true); w:Run(4)
	assert(#t.game.events > events, "the same move resumes after returning")
	Errors(w)
end)

test("Bones venue: automatic free T invites before the party and opens at the shared inn", function()
	local w, a, b = Pair()
	local id = Agree(w, a, b)
	eq(FT(a).Get(id).mode, "T")
	eq(As(w, a, a.ns.Arena.Counts, "T"), false, "venue enforcement never turns on financial counting")
	w:Group({ a, b }); w:Run(2)
	eq(FT(a).Get(id).state, "open"); eq(FT(b).Get(id).state, "open")
	eq(FT(a).Get(id).inn, "inn_goldshire"); eq(FT(b).Get(id).inn, "inn_goldshire")
	Opening(w, a, b, id)
	eq(As(w, b, FT(b).View, id).rehearsal, false, "automatic T is not the simulator")
	Errors(w)
end)

test("Bones venue: free invitations and acceptance require a local venue, not a party yet", function()
	local w, a, b = Pair()
	w:Stand(a.name, FW.ROAD, false)
	local ok, why = As(w, a, FT(a).CanCreate, { guest = b.name, target = 2000 })
	eq(ok, false); eq(why, "tavern-rest")
	w:Stand(a.name, FW.INN, true)
	local id = assert(As(w, a, FT(a).Create, { guest = b.name, target = 2000 }))
	w:Run(0); w:Stand(b.name, FW.ROAD, false)
	ok, why = As(w, b, FT(b).CanAnswer, id, true)
	eq(ok, false); eq(why, "tavern-rest")
	eq(As(w, b, FT(b).CanAnswer, id, false), true, "declining remains available anywhere")
	w:Stand(b.name, FW.INN, true)
	eq(As(w, b, FT(b).CanAnswer, id, true), true, "the party is needed at opening, not at acceptance")
	Errors(w)
end)

test("Bones venue: a guest leaving before KG is received never begins the free table", function()
	local w, a, b = Pair()
	local id = Agree(w, a, b)
	w:Group({ a, b })
	assert(As(w, a, FT(a).Open, id))
	local send = w.SendNow
	w.SendNow = function(self, from, item)
		if from == a and item.msg:sub(1, 2) == "KG" then
			self:Stand(b.name, FW.ROAD, false)
			self.SendNow = send
		end
		return send(self, from, item)
	end
	w:Run(0)
	local guest = FT(b).Get(id)
	eq(guest.state, "agreed"); eq(guest.game, nil, "KG must return before Begin")
	eq(guest.tavernWhy, "rest")
	eq(As(w, b, FT(b).Roll, id), false, "the guest cannot make an opening roll outside the venue")
	Errors(w)
end)

test("Bones venue: hidden free T board shows the real departure countdown and return clears it", function()
	local w, a, b = Pair(true)
	local id = Agree(w, a, b)
	w:Group({ a, b }); w:Run(2); Opening(w, a, b, id)
	w:Stand(b.name, FW.ROAD, false); w:Run(2)
	local v = As(w, b, FT(b).View, id)
	eq(v.rehearsal, false); assert(v.awayLeft and v.awayLeft > 0)
	local B = b.ns.Arena.ui.FarkleBoard
	assert(B.departure and B.departure:IsShown()); eq(B.IsOpen(), false)
	eq(B.departure.id, id)
	local left = v.awayLeft
	w:Run(3); eq(As(w, b, FT(b).View, id).awayLeft, left - 3)
	w:Stand(b.name, { cont = FW.INN.cont, wx = FW.INN.wx + 3, wy = FW.INN.wy }, true); w:Run(2)
	eq(As(w, b, FT(b).View, id).awayLeft, nil); eq(B.departure:IsShown(), false)
	Errors(w)
end)

test("Bones venue: a free camp table keeps its camp after reload and still pauses on departure", function()
	local w, a, b = Pair()
	for i, c in ipairs({ a, b }) do
		w:Stand(c.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + (i - 1) * 3, wy = FW.ROAD.wy }, false)
		rawset(c.ns, "Board", { CampOf = function(name)
			if FT(c).Same(name, a.name) or FT(c).Same(name, b.name) then return { zone = 1429, raisedAt = w.clock } end
		end })
	end
	local id = Agree(w, a, b)
	w:Group({ a, b }); w:Run(2); Opening(w, a, b, id)
	eq(FT(a).Get(id).camp, true); eq(FT(b).Get(id).camp, true)
	w:Logout(a); w:Login(a); FW.Extend(w, a); w:Group({ a, b })
	local t = assert(FT(a).Get(id))
	eq(t.camp, true); eq(t.inn, nil); assert(t.spot)
	w:Stand(b.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + 60, wy = FW.ROAD.wy }, false)
	w:Run(2)
	eq(As(w, a, FT(a).View, id).clock.paused, "tavern")
	Errors(w)
end)
