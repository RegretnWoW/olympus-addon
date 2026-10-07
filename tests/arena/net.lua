-- 1.2, the arena's foundation: the Blood Arena's foundation (ArenaNet.lua, ArenaRoles.lua, the companion's handoff
-- and registry, the hooks in existing files, the packaging's shape), on the test world
-- (tests/arena/lib/world.lua). Every name is invented (World.NAMES).
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)

local function Types(list)
	local out = {}
	for _, s in ipairs(list) do out[#out + 1] = s.msg:sub(1, 2) end
	return table.concat(out, " ")
end
local function Read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end
local function Printed(c, text)
	local n = 0
	for _, line in ipairs(c.printed) do if line == text or line:find(text, 1, true) then n = n + 1 end end
	return n
end
-- A handler registered on a client for a type, recording what it was given.
local function Catch(c, kind)
	local got = {}
	local A = c.ns.Arena
	c.ns.Comm.Handle(kind, A.Handle(kind, function(dist, sender, mode, body)
		got[#got + 1] = { dist = dist, sender = sender, mode = mode, body = body }
	end))
	return got
end
-- The King's settings word (the live switch on by default), taken by everyone on his realm.
local function GoLive(w, king, t)
	local ok, why = king.Roles.SetSettings(t or { live = 1 })
	assert(ok, "settings: " .. tostring(why))
	w:Run(0)
end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local DAY = 86400
local function TestBuild(w, extra)
	local t = { n = 3, base = "1.2.0", built = w.clock - 100, expires = w.clock + 21 * DAY, commit = "abc1234", lane = "group" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
-- The body of a King's word as another client would send it (a forged or out-of-bounds one).
local function Word(w, c, kind, body, at, guild)
	w:As(c, function()
		c.ns.Comm.Send("CHANNEL", ("T1~%s~%d~%s~%d~%s"):format(kind, 7, guild or GetGuildInfo("player") or "", at or w.clock, body))
	end)
	w:Run(0)
end

print("ArenaNet: the envelope, lanes and modes")

test("1.2 the arena's foundation: the envelope: no mode, another mode or protocol 2 never reach the handler; L1 and T1 do", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(b, "AF")
	for _, text in ipairs({ "AF~~x", "AF~1~x", "AF~X1~x", "AF~L2~x", "AF~L~x", "AF~l1~x", "AF~LL1~x", "AF~T0~x" }) do
		b.Arena.Inject("CHANNEL", a.name, text)
	end
	eq(#got, 0, "refused before the handler:")
	local d = b.Arena.Stats().dropped
	eq((d.mode or 0) + (d.proto or 0) + (d.envelope or 0), 8)
	b.Arena.Inject("CHANNEL", a.name, "AF~L1~x~y")
	b.Arena.Inject("WHISPER", a.name, "AF~T1~z")
	eq(#got, 2); eq(got[1].mode, "L"); eq(got[1].body, "x~y"); eq(got[2].mode, "T"); eq(got[2].sender, a.name); eq(got[2].dist, "WHISPER")
	-- What goes out has the envelope.
	a.Arena.Send("AF", "T", "hello")
	w:Run(0)
	eq(w:Sent{ from = a, type = "AF" }[1].msg, "AF~T1~hello")
	eq(got[3].body, "hello")
	NoErrors(w)
end)

test("1.2 the arena's foundation: a release sends L only with its realm's live switch on (honours and a player's own obligations go anyway), T on the channel, one-to-one by whisper", function()
	local w = World.New()
	local king, a, b = w:Role("king"), w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(b, "AF")
	eq(a.Arena.NewMode(false), "T", "the live switch off: everything new is a rehearsal")
	eq(a.Arena.Mode({ mode = "T" }), "T"); eq(a.Arena.Mode({}), "L"); eq(a.Arena.Mode("L"), "L")
	eq(select(2, a.Arena.Send("AF", "L", "x")), "live-off")
	eq(a.Arena.Send("AP", "L", "profile"), true, "a profile is an honour's")
	eq(a.Arena.Send("ZR", "L", "receipt", { to = b.name }), true, "a receipt: the player's own obligation")
	eq(a.Arena.Send("ZX", "L", "mark", { obligation = true }), true, "a debt mark about himself")
	eq(select(2, a.Arena.Send("ZX", "L", "mark")), "live-off", "someone else's mark is not his obligation")
	eq(a.Arena.Send("AF", "T", "t"), true)
	eq(select(2, a.Arena.Send("QQ", "T", "x")), "type", "a type that is not the arena's")
	eq(select(2, a.Arena.Send("AF", "X", "x")), "mode")
	eq(select(2, a.Arena.Send("AF", "T", "x", { dist = "GUILD" })), "guild-lane", "nothing but ID rides GUILD")
	w:Run(0)
	eq(Types(w:Sent{ from = a }), "AP ZR ZX AF")
	eq(w:Sent{ from = a, type = "ZR" }[1].dist, "WHISPER"); eq(w:Sent{ from = a, type = "ZR" }[1].target, b.name)
	eq(w:Sent{ from = a, type = "AF" }[1].dist, "CHANNEL")
	eq(a.Arena.Lane("L", true), "CHANNEL"); eq(a.Arena.Lane("T", true), "CHANNEL", "an army rehearsal"); eq(a.Arena.Lane("L", false), "WHISPER")
	-- The King turns it on: L goes.
	GoLive(w, king)
	eq(a.Roles.Live(), true); eq(a.Arena.NewMode(false), "L"); eq(a.Arena.NewMode(true), "T", "a rehearsal ticked")
	eq(a.Arena.Send("AF", "L", "live"), true)
	w:Run(0)
	eq(got[#got].body, "live"); eq(got[#got].mode, "L")
	-- A group rehearsal: RAID in a raid, else PARTY.
	a.ns.ArenaTest.Running = function() return { lane = "group" } end
	eq(a.Arena.Lane("T", true), nil, "alone")
	w:Group({ a, b })
	eq(a.Arena.Lane("T", true), "PARTY"); eq(a.Arena.Lane("L", true), "CHANNEL")
	w:Group({ a, b, king }, true)
	eq(a.Arena.Lane("T", true), "RAID")
	a.ns.ArenaTest.Running = nil
	NoErrors(w)
end)

test("1.2 the arena's foundation: a release takes L on the channel and by whisper (ID on GUILD too), T on any lane but GUILD", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local af, id = Catch(b, "AF"), Catch(b, "ID")
	for _, case in ipairs({ { "CHANNEL", "L", 1 }, { "WHISPER", "L", 1 }, { "RAID", "L", 0 }, { "PARTY", "L", 0 }, { "GUILD", "L", 0 },
		{ "CHANNEL", "T", 1 }, { "RAID", "T", 1 }, { "PARTY", "T", 1 }, { "WHISPER", "T", 1 }, { "GUILD", "T", 0 } }) do
		local before = #af
		b.Arena.Inject(case[1], a.name, "AF~" .. case[2] .. "1~x")
		eq(#af - before, case[3], case[1] .. " " .. case[2])
	end
	b.Arena.Inject("GUILD", a.name, "ID~L1~x")
	b.Arena.Inject("GUILD", a.name, "ID~T1~x")
	eq(#id, 1, "ID in L on GUILD: the Treasurer's own word reaches his guild on both realms")
	NoErrors(w)
end)

test("1.2 the arena's foundation: a test build sends T only, to its raid or party (nothing alone, said once), and takes T on RAID, PARTY or WHISPER only", function()
	local w = World.New()
	local tb = TestBuild(w)
	local a = w:Client("Wenna Crale", { testBuild = tb })
	local b, c = w:Client("Lida Fenn", { testBuild = TestBuild(w) }), w:Client("Parric Stowe")
	eq(a.Arena.TestBuild().n, 3)
	eq(a.Arena.Mode({}), "T", "everything is T on a test build"); eq(a.Arena.NewMode(false), "T")
	eq(select(2, a.Arena.Send("AF", "L", "x")), "test-live")
	eq(select(2, a.Arena.Send("AF", "T", "x", { dist = "CHANNEL" })), "test-channel")
	eq(select(2, a.Arena.Send("AF", "T", "x")), "group")
	eq(select(2, a.Arena.Send("AF", "T", "x")), "group")
	eq(Printed(a, a.ns.L.ARENA_TEST_NO_GROUP), 1, "said once")
	w:Run(0)
	eq(#w:Sent{ from = a }, 0, "nothing left this client")
	w:Group({ a, b })
	eq(a.Arena.Send("AF", "T", "party"), true)
	w:Group({ a, b, c }, true)
	eq(a.Arena.Send("AF", "T", "raid"), true)
	eq(a.Arena.Send("AF", "T", "whisper", { to = b.name }), true)
	w:Run(0)
	eq(Types(w:Sent{ from = a }), "AF AF AF"); eq(#w:Sent{ from = a, dist = "CHANNEL" }, 0)
	eq(w:Sent{ from = a }[1].dist, "PARTY"); eq(w:Sent{ from = a }[2].dist, "RAID"); eq(w:Sent{ from = a }[3].dist, "WHISPER")
	-- Receiving: L from any lane and T from the channel are dropped and counted.
	local got = Catch(b, "AF")
	for _, case in ipairs({ { "CHANNEL", "L" }, { "RAID", "L" }, { "WHISPER", "L" }, { "CHANNEL", "T" }, { "GUILD", "T" } }) do
		b.Arena.Inject(case[1], c.name, "AF~" .. case[2] .. "1~x")
	end
	eq(#got, 0); eq(b.Arena.Stats().dropped["live-in-test"], 5)
	b.Arena.Inject("RAID", c.name, "AF~T1~x"); b.Arena.Inject("PARTY", c.name, "AF~T1~x"); b.Arena.Inject("WHISPER", c.name, "AF~T1~x")
	eq(#got, 3)
	-- Its login line, once a session.
	eq(Printed(a, a.ns.L.ARENA_TEST_LOGIN:format(3)), 1)
	NoErrors(w)
end)

test("1.2 the arena's foundation: Arena.TestBuild takes only the right shape; an expired one turns the arena off at login (the rest of Olympus works)", function()
	local w = World.New()
	local base = TestBuild(w)
	local function Shape(extra)
		local t = {}
		for k, v in pairs(base) do t[k] = v end
		for k, v in pairs(extra) do if v == "nil" then t[k] = nil else t[k] = v end end
		local c = w:Client("Tester " .. ("abcdefghijklmnopqrstuvwxyz"):sub(#w.clients + 1, #w.clients + 1), { testBuild = t })
		return c.Arena.TestBuild()
	end
	eq(type(Shape({})), "table")
	eq(Shape({ n = 0 }), nil); eq(Shape({ n = 1000 }), nil); eq(Shape({ n = 2.5 }), nil); eq(Shape({ n = "3" }), nil)
	eq(Shape({ base = "1.2" }), nil); eq(Shape({ base = "1.2.0-test" }), nil)
	eq(Shape({ built = "x" }), nil); eq(Shape({ expires = base.built }), nil, "expires before built")
	eq(Shape({ expires = base.built + 61 * DAY }), nil, "more than 60 days")
	eq(type(Shape({ expires = base.built + 60 * DAY })), "table")
	eq(Shape({ commit = "bad commit!" }), nil); eq(type(Shape({ commit = "nil" })), "table")
	local old = w:Client("Tester Expired", { testBuild = TestBuild(w, { built = w.clock - 30 * DAY, expires = w.clock - DAY }) })
	eq(old.Arena.Expired(), true); eq(old.Arena.Off(), true)
	eq(Printed(old, old.ns.L.ARENA_TEST_EXPIRED), 1)
	eq(select(2, old.Arena.Send("AF", "T", "x")), "off")
	eq(old.ns.db.arenaOff, nil, "for the session only: nothing saved")
	eq(old.ns.Arena.TestBuildLine(), old.ns.L.ARENA_TEST_LINE:format(3, "1.2.0", date("%m-%d", w.clock - 30 * DAY), date("%m-%d", w.clock - DAY), "group", "abc1234"))
	NoErrors(w)
end)

print("ArenaNet: pieces, the low lane, retries, the outbox, lockdown")

-- A payload of exactly `n` pieces (each Arena.PIECE bytes).
local function Long(kind, mode, n, fill)
	local total = n * 220
	return (fill or "x"):rep(total - #(kind .. "~" .. mode .. "1~"))
end

test("1.2 the arena's foundation: EP pieces: 30 pieces arrive whole on any lane, a 31st refused, out of order, per sender and in all, 60 s, an unknown or other-mode inside dropped", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(b, "AF")
	local body = Long("AF", "T", 30)
	eq(a.Arena.Send("AF", "T", body), true)
	eq(select(2, a.Arena.Send("AF", "T", Long("AF", "T", 30) .. "y")), "long", "31 pieces")
	w:Run(0)
	eq(#w:Sent{ from = a, type = "EP" }, 30); eq(#w:Sent{ from = a, type = "AF" }, 0)
	for _, s in ipairs(w:Sent{ from = a, type = "EP" }) do assert(#s.msg <= 255, #s.msg) end
	eq(#got, 1); eq(got[1].body, body); eq(got[1].dist, "CHANNEL")
	-- By whisper too (Comm puts pieces together on the channel and GUILD only).
	a.Arena.Send("AF", "T", Long("AF", "T", 2, "w"), { to = b.name })
	w:Run(0)
	eq(#got, 2); eq(got[2].dist, "WHISPER"); eq(got[2].body, Long("AF", "T", 2, "w"))
	-- Out of order, by hand.
	local whole = "AF~T1~" .. ("z"):rep(500)
	local function Piece(pid, i, n, chunk, mode) return ("EP~%s1~%s~%s~%s~%s"):format(mode or "T", pid, i, n, chunk) end
	local p1, p2, p3 = whole:sub(1, 220), whole:sub(221, 440), whole:sub(441)
	b.Arena.Inject("RAID", a.name, Piece("k1", 3, 3, p3))
	b.Arena.Inject("RAID", a.name, Piece("k1", 1, 3, p1))
	eq(#got, 2)
	b.Arena.Inject("RAID", a.name, Piece("k1", 2, 3, p2))
	eq(#got, 3); eq(got[3].body, ("z"):rep(500)); eq(got[3].dist, "RAID")
	-- 60 s to finish.
	b.Arena.Inject("RAID", a.name, Piece("k2", 1, 2, p1))
	w:Run(61)
	b.Arena.Inject("RAID", a.name, Piece("k2", 2, 2, p2))
	eq(#got, 3); eq(b.Arena.Stats().dropped["pieces-late"], 1)
	eq(b.Arena.OpenPieces(a.name), 1, "the second piece waits alone")
	-- Inside: a type not the arena's, EP itself, or another mode than the pieces'.
	for _, inner in ipairs({ "QQ~T1~" .. ("x"):rep(300), "EP~T1~" .. ("x"):rep(300), "AF~L1~" .. ("x"):rep(300) }) do
		local d = b.Arena.Stats().dropped.inner or 0
		b.Arena.Inject("WHISPER", N.bettor3, Piece("i1", 1, 2, inner:sub(1, 220), "T"))
		b.Arena.Inject("WHISPER", N.bettor3, Piece("i1", 2, 2, inner:sub(221), "T"))
		eq(b.Arena.Stats().dropped.inner, d + 1, inner:sub(1, 6))
	end
	-- 4 open per sender; 64 in all.
	for i = 1, 5 do b.Arena.Inject("RAID", a.name, Piece("s" .. i, 1, 2, "x")) end
	eq(b.Arena.OpenPieces(a.name), 4); eq(b.Arena.Stats().dropped["pieces-open"], 2)
	for s = 1, 20 do
		for i = 1, 4 do b.Arena.Inject("RAID", "Sender Number" .. s .. "-Emberfall", Piece("q" .. i, 1, 2, "x")) end
	end
	eq(b.Arena.OpenPieces(), 64)
	eq(#got, 3)
	NoErrors(w)
end)

test("1.2 the arena's foundation: a 3-piece keyed payload updated twice while queued arrives whole, as the newest version; one updated in flight arrives whole, then the newest", function()
	local w = World.New({ paced = true })
	local a, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "BO")
	for _, v in ipairs({ "1", "2", "3" }) do eq(a.Arena.Send("BO", "T", Long("BO", "T", 3, v), { key = "bo e1" }), true) end
	eq(a.Arena.ProducerCount(), 1)
	w:Run(15)
	eq(#got, 1); eq(got[1].body, Long("BO", "T", 3, "3"))
	eq(#w:Sent{ from = a, type = "EP" }, 3, "one version's pieces alone")
	-- In flight: the first piece left, then a newer one: this one finishes, the newest follows.
	a.Arena.Send("BO", "T", Long("BO", "T", 3, "4"), { key = "bo e1" })
	w:Run(1.5)
	eq(#w:Sent{ from = a, type = "EP" }, 4)
	a.Arena.Send("BO", "T", Long("BO", "T", 3, "5"), { key = "bo e1" })
	w:Run(20)
	eq(#got, 3); eq(got[2].body, Long("BO", "T", 3, "4")); eq(got[3].body, Long("BO", "T", 3, "5"))
	eq(a.Arena.ProducerCount(), 0, "done: the producer goes")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the low lane sends only while Comm's queue holds Arena.ROOM (2) or fewer; producers take turns and end with nil", function()
	local w = World.New({ paced = true })
	local a, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "ZE")
	for i = 1, 6 do a.Comm.Send("CHANNEL", "ZZ~other module " .. i) end
	a.Arena.Send("ZE", "T", "low one", { low = true })
	local seen = {}
	-- Watch the queue each time an arena message is handed on.
	local send = a.ns.Comm.Send
	a.ns.Comm.Send = function(dist, msg, ...)
		if msg:sub(1, 2) == "ZE" then seen[#seen + 1] = a.ns.Comm.QueueSize() end
		return send(dist, msg, ...)
	end
	local n1, n2 = 0, 0
	a.Arena.Later("p1", function() n1 = n1 + 1 if n1 <= 2 then return "ZE", "T", "p1 " .. n1 end end)
	a.Arena.Later("p2", function() n2 = n2 + 1 if n2 <= 2 then return { "ZE", "T", "p2 " .. n2 } end end)
	w:Run(30)
	eq(#got, 5)
	for _, q in ipairs(seen) do assert(q <= a.ns.Arena.ROOM, "handed on with " .. q .. " waiting") end
	eq(got[1].body, "low one")
	local order = {}
	for i = 2, 5 do order[#order + 1] = got[i].body end
	eq(table.concat(order, ","), "p1 1,p2 1,p1 2,p2 2", "round robin")
	eq(a.Arena.ProducerCount(), 0)
	w:Run(5)
	eq(a.Arena.Ticking(), false, "nothing left: the ticker stops")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the involvement ticker: idle, no timer; involved, Arena.Every runs; cleared, it stops; Arena.After keeps it for its one call", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	eq(a.Arena.Ticking(), false); eq(#w:Timers(a, true), 0)
	local n = 0
	a.Arena.Every(5, "count", function() n = n + 1 end)
	w:Run(30)
	eq(n, 0, "Every waits while nothing is involved"); eq(#w:Timers(a, true), 0)
	a.Arena.Involve("fight:F1", true)
	eq(a.Arena.Ticking(), true); eq(#w:Timers(a, true), 1, "one ticker")
	w:Run(20)
	eq(n, 4)
	eq(table.concat(a.Arena.Involved(), ","), "fight:F1")
	a.Arena.Involve("fight:F1", false)
	eq(a.Arena.Ticking(), false); eq(#w:Timers(a, true), 0)
	w:Run(20)
	eq(n, 4)
	local fired = 0
	a.Arena.After(3, "once", function() fired = fired + 1 end)
	eq(a.Arena.Ticking(), true)
	w:Run(10)
	eq(fired, 1); eq(a.Arena.Ticking(), false)
	-- ARENA_CHANGED at most once a second.
	local changed = 0
	a.ns.On("ARENA_CHANGED", function() changed = changed + 1 end)
	for _ = 1, 5 do a.Arena.Changed() end
	eq(changed, 1)
	w:Run(2)
	eq(changed, 2, "the rest in one, a second later")
	w:Run(5)
	eq(a.Arena.Ticking(), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation: must-deliver: refused with results 3, 8 and 11, an arena message arrives after the condition clears (2, 4, 8 s); an ordinary one is lost", function()
	local w = World.New()
	local a, b = w:Client("Oswin Marrow"), w:Client("Parric Stowe")
	local got = Catch(b, "AE")
	w:Results(a, { 3, 8, 11 })
	local done
	a.Arena.Send("AE", "T", "entry", { must = true, done = function(sent, why) done = { sent, why } end })
	w:Run(0)
	eq(#got, 0); eq(#w.failed, 1); eq(w.failed[1].result, 3)
	w:Run(2)
	eq(#w.failed, 2); eq(w.failed[2].result, 8)
	w:Run(4)
	eq(#w.failed, 3); eq(w.failed[3].result, 11)
	eq(done, nil, "not given up")
	w:Run(8)
	eq(#got, 1); eq(got[1].body, "entry"); eq(done[1], true)
	eq(a.Arena.Stats().retried, 3)
	w:Results(a, { 3 })
	local lost
	a.Arena.Send("AE", "T", "ordinary", { done = function(sent, why) lost = { sent, why } end })
	w:Run(30)
	eq(#got, 1); eq(lost[1], false); eq(lost[2], 3)
	eq(a.Arena.Ticking(), false)
	NoErrors(w)
end)

-- (Ordinary whispers: a must-deliver one to a target offline waits for him instead, the review's
-- tests below.)
test("1.2 the arena's foundation: whispers go one at a time per target; result 12 or the server's not-found line drops that target's other ordinary arena whispers", function()
	local w = World.New({ paced = true })
	local a, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "ZK")
	local ghost = "Nobody Here-Emberfall"
	local told = {}
	for i = 1, 3 do a.Arena.Send("ZK", "T", "g" .. i, { to = ghost, done = function(sent, why) told[#told + 1] = tostring(sent) .. " " .. tostring(why) end }) end
	eq(a.Arena.OutboxSize(ghost), 3)
	eq(#a.comm.queue, 1, "one at a time")
	w:Run(5)
	eq(#w.failed, 1, "the first one only"); eq(w.failed[1].result, 12)
	eq(table.concat(told, ","), "false 12,false 12,false 12")
	eq(a.Arena.OutboxSize(ghost), 0)
	-- A new one right after is dropped too (for a minute).
	a.Arena.Send("ZK", "T", "g4", { to = ghost })
	eq(a.Arena.OutboxSize(ghost), 0); eq(#a.comm.queue, 0)
	-- The not-found line: what waits for that target goes.
	for i = 1, 3 do a.Arena.Send("ZK", "T", "b" .. i, { to = b.name }) end
	eq(a.Arena.OutboxSize(b.name), 3)
	w:System(a, "No player named 'Parric Stowe' is currently playing.")
	eq(a.Arena.OutboxSize(b.name), 1, "the one handed to Comm still goes")
	w:Run(10)
	eq(#got, 1); eq(got[1].body, "b1")
	-- Otherwise each goes after the one before.
	w:Run(61)
	for i = 1, 3 do a.Arena.Send("ZK", "T", "c" .. i, { to = b.name }) end
	w:Run(10)
	eq(#got, 4); eq(got[4].body, "c3")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the urgent share: 20 urgent arena whispers keep at most 8 urgent in Comm's queue, and an urgent BO behind them still arrives", function()
	local w = World.New({ paced = true })
	local bank = w:Client("Coffrey Vault")
	local targets = {}
	for i = 1, 20 do targets[i] = w:Client("Bettor Number" .. string.char(96 + i)) end
	local watcher = w:Client("Parric Stowe")
	local bo = Catch(watcher, "BO")
	local other = 0
	for i = 1, 50 do bank.Comm.Send("CHANNEL", "ZZ~another module " .. i) end
	for i = 1, 20 do bank.Arena.Send("BK", "T", "refused " .. i, { to = targets[i].name, urgent = true }) end
	local function UrgentInQueue()
		local n = 0
		for _, item in ipairs(bank.comm.queue) do if item.urgent then n = n + 1 end end
		return n
	end
	eq(UrgentInQueue(), 8); eq(bank.Arena.UrgentOut(), 8)
	bank.Arena.Send("BO", "T", "lock", { urgent = true, must = true, key = "bo e1" })
	eq(UrgentInQueue(), 8, "the BO waits here, not in Comm")
	local most = 0
	for _ = 1, 60 do
		w:Run(1)
		most = math.max(most, UrgentInQueue())
	end
	assert(most <= 8, "urgent arena items in Comm's queue: " .. most)
	eq(#bo, 1); eq(bo[1].body, "lock")
	for i = 1, 20 do eq(#w:Sent{ from = bank, type = "BK", to = targets[i].name }, 1, "refusal " .. i) end
	NoErrors(w)
end)

test("1.2 the arena's foundation: lockdown (chat messaging lockdown, or an instance) holds every arena message here, and the recheck sends them on", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(b, "AF")
	w:Lockdown(a, true)
	eq(a.Arena.Blocked(), true)
	a.Arena.Send("AF", "T", "one")
	a.Arena.Send("AF", "T", "two", { to = b.name })
	eq(#a.comm.queue, 0, "nothing handed to Comm"); eq(a.Arena.BacklogSize(), 2, "the whisper too")
	w:Run(10)
	eq(#got, 0)
	w:Lockdown(a, false)
	w:Run(0)
	eq(#got, 2); eq(got[1].body, "one"); eq(got[2].body, "two")
	-- An instance holds too.
	a.instance = true
	eq(a.Arena.Blocked(), true)
	a.Arena.Send("AF", "T", "three")
	w:Run(5)
	eq(#got, 2)
	a.instance = nil
	w:Run(2)
	eq(#got, 3, "the ticker's recheck")
	eq(a.Arena.Ticking(), false)
	NoErrors(w)
end)

print("ArenaNet: the persistence gate, ids, the King's delay, the switches")

test("1.2 the arena's foundation: Arena.Persists: false on a first login and on the beta (saved data lost at every login); true once the logout's sentinel came back", function()
	local w = World.New()
	local keep = w:Client("Lida Fenn")
	local beta = w:Client("Parric Stowe", { persists = false })
	eq(keep.Arena.Persists(), false, "not proven yet"); eq(beta.Arena.Persists(), false)
	w:Logout(keep); w:Logout(beta)
	eq(type(keep.db.arenaSaved), "table", "the sentinel written at logout")
	w:Login(keep); w:Login(beta)
	eq(keep.Arena.Persists(), true); eq(beta.Arena.Persists(), false)
	eq(keep.db.sessions, 2); eq(beta.db.sessions, 1, "the beta: every login a first one")
	local lines = {}
	keep.Arena.StatusLines(lines)
	eq(lines[4], keep.ns.L.ARENA_SAVED_KEPT)
	lines = {}
	beta.Arena.StatusLines(lines)
	eq(lines[4], beta.ns.L.ARENA_SAVED_LOST)
	NoErrors(w)
end)

test("1.2 the arena's foundation: Arena.NewId: five in one second from one writer are distinct, two writers never collide, a taken id is passed over", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local seen = {}
	for _, c in ipairs({ a, b }) do
		for _ = 1, 5 do
			local id = c.Arena.NewId("F")
			assert(id:find("^F[0-9a-z]+$"), id)
			assert(not seen[id], "twice: " .. id)
			seen[id] = true
		end
	end
	local sec = a.Arena.B36(w.clock)
	local one = a.Arena.NewId("K")
	eq(one:sub(2, 1 + #sec), sec, "the server second in base 36")
	assert(a.Arena.NewId("T") ~= b.Arena.NewId("T"), "the writer's mark tells them apart")
	-- The next two candidates taken: the third is given, well formed, neither of them.
	local asked = {}
	local given = a.Arena.NewId("N", function(id) asked[#asked + 1] = id return #asked <= 2 end)
	eq(#asked, 3); eq(given, asked[3]); assert(given ~= asked[1] and given ~= asked[2], given)
	assert(given:find("^N[0-9a-z]+$") and asked[1]:find("^N[0-9a-z]+$"), given)
	eq(a.Arena.NewId("N", function() return true end), nil, "every one taken: none")
	local skip = a.Arena.NewId("N", function(id) return id:sub(-3, -3) == "d" end)
	assert(skip and skip:sub(-3, -3) ~= "d", skip)
	eq(a.Arena.NewId("X"), nil, "a letter of no object")
	eq(a.Arena.NewId("L"):sub(1, 1), "L", "the Lottery's day")
	-- The parse helpers.
	local A = a.ns.Arena
	eq(A.B36(0), "0"); eq(A.B36(35), "z"); eq(A.B36(36), "10"); eq(A.N("10"), 36); eq(A.N("Z"), nil); eq(A.N("zz", 0, 100), nil)
	eq(A.Copper(A.B36(2147483647)), 2147483647); eq(A.Copper(A.B36(2147483648)), nil)
	eq(select("#", A.Fields("a~b~c~d", 3)), 3); eq(select(3, A.Fields("a~b~c~d", 3)), "c~d"); eq(A.Fields("a~b", 3), nil)
	eq(A.Name("Torvin Hale-Emberfall"), "Torvin Hale-Emberfall"); eq(A.Name("Torvin Hale"), "Torvin Hale-Emberfall")
	eq(A.Name("<script>"), nil); eq(A.Name("Torvin Hale-Bad Realm!"), nil)
	eq(A.GK("Player-4395-0A1B2C3D"), A.B36(4395) .. ".0a1b2c3d"); eq(A.GuidOf(A.GK("Player-4395-0A1B2C3D")), "Player-4395-0A1B2C3D")
	eq(A.GK("Creature-0-1"), nil); eq(A.GuidOf("x.y"), nil)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the King's delay (T1~L): his alone, it lapses 15 minutes after the last; LastCall and OpenMin exactly", function()
	local w = World.New()
	local king, steward, hc, b = w:Role("king"), w:Role("steward"), w:Role("councillor"), w:Client("Lida Fenn")
	eq(king.Arena.KingsView(), true); eq(b.Arena.KingsView(), false)
	eq(king.Arena.SetDelay(30), true)
	w:Run(0)
	eq(b.Roles.KingDelay(), 30)
	eq(king.Arena.LastCall(true), 50); eq(king.Arena.OpenMin(true), 120)
	eq(b.Arena.LastCall(true), 50, "a public event anyone opens keeps the King's delay"); eq(b.Arena.OpenMin(true), 120)
	eq(b.Arena.LastCall(false), 20); eq(b.Arena.OpenMin(false), 120)
	king.Arena.SetDelay(120)
	w:Run(0)
	eq(king.Arena.LastCall(true), 140); eq(king.Arena.OpenMin(true), 195)
	eq(hc.Arena.LastCall(true), 140, "a High Councillor opening while the King's word says 120"); eq(hc.Arena.OpenMin(true), 195)
	-- A client's own stored delay counts only in the King's view.
	b.db.arenaUI = { delay = 300 }
	eq(select(2, b.Arena.SetDelay(10)), "king")
	-- He repeats it while online; logged out, it lapses 15 minutes after the last.
	w:Run(600)
	eq(b.Roles.KingDelay(), 120)
	w:Logout(king)
	w:Run(899)
	eq(b.Roles.KingDelay(), 120)
	w:Run(302)
	eq(b.Roles.KingDelay(), 0)
	eq(b.Arena.LastCall(true), 20, "a non-King client with a stored delay and no King's word"); eq(b.Arena.OpenMin(true), 120)
	-- A Steward's T1~L is no word.
	Word(w, steward, "L", "600")
	eq(b.Roles.KingDelay(), 0)
	eq(king.Arena.SetDelay(901), false); eq(king.Arena.SetDelay(-1), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the kill switch: nothing sent, shown or handled while off, but a player's own obligations; refused while he owes", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(a, "AF")
	a.ns.Debts.Open = function() return { { id = "d1" } } end
	eq(select(2, a.Arena.SetOff(true)), "obligations"); eq(a.db.arenaOff, nil)
	eq(Printed(a, a.ns.L.ARENA_OFF_REFUSED), 1)
	a.ns.Debts.Open = function() return {} end
	eq(a.Arena.SetOff(true), true); eq(a.db.arenaOff, true); eq(a.Arena.Off(), true)
	eq(select(2, a.Arena.Send("AF", "T", "x")), "off")
	eq(a.Arena.Send("ZF", "L", "receipt", { to = b.name }), true)
	eq(a.Arena.Send("KD", "T", "paid", { to = b.name }), true)
	eq(a.Arena.Send("AW", "T", "signed result", { to = b.name, obligation = true }), true)
	a.Arena.Inject("CHANNEL", b.name, "AF~T1~x")
	eq(#got, 0, "no handler acts")
	eq(select(2, a.Arena.Can("anything")), "unknown")
	a.Arena.Action("bet", function() return true end, function() return "placed" end)
	eq(select(2, a.Arena.Can("bet")), "off")
	a.Arena.SetOff(false)
	eq(a.Arena.Off(), false); eq(a.Arena.Can("bet"), true); eq(a.Arena.Do("bet"), "placed")
	w:Run(0)
	eq(Types(w:Sent{ from = a }), "ZF KD AW")
	NoErrors(w)
end)

test("1.2 the arena's foundation: actions and the /oly arena router: Can asks the action's rule, Do acts; sub-commands, help, and /oly arena and /ola through Core", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local acted = {}
	a.Arena.Action("challenge", function(who) if who == "self" then return false, "self" end return true end, function(who) acted[#acted + 1] = who end)
	eq(select(2, a.Arena.Can("challenge", "self")), "self")
	eq(a.Arena.Do("challenge", "self"), false); eq(#acted, 0)
	eq(a.Arena.Do("challenge", "Torvin Hale"), true); eq(acted[1], "Torvin Hale")
	a.Arena.Action("broken", function() error("oops") end, function() end)
	eq(select(2, a.Arena.Can("broken")), "error")
	local ran = {}
	a.Arena.Slash("zz", function(args) ran[#ran + 1] = args end, "/oly arena zz - a test's")
	a.Arena.RunSlash("ZZ one two")
	eq(ran[1], "one two")
	a.Arena.RunSlash("help")
	eq(Printed(a, "/oly arena zz - a test's"), 1)
	a.Arena.RunSlash("nosuch")
	eq(Printed(a, "/oly arena zz - a test's"), 2, "an unknown one shows the help")
	-- Through Core's /oly and /ola.
	w:As(a, function() a.slashes.OLYMPUS("arena zz three") end)
	eq(ran[2], "three")
	w:As(a, function() a.slashes.OLYMPUS("farkle zz") end)
	a.Arena.Slash("farkle", function(args) ran[#ran + 1] = "farkle " .. args end)
	w:As(a, function() a.slashes.OLYMPUS("farkle new table") end)
	eq(ran[3], "farkle new table")
	a.Arena.Slash("say", function(args) ran[#ran + 1] = "say " .. args end)
	w:As(a, function() a.slashes.OLYMPUSARENA("hello room") end)
	eq(ran[4], "say hello room")
	-- /oly arena status: the arena's lines (the memory measured on the command alone).
	w:As(a, function() a.slashes.OLYMPUS("arena status") end)
	eq(a.memoryUpdates, 1)
	eq(Printed(a, a.ns.L.ARENA_SAVED_LOST), 1)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the sim: the author's Workshop or a test build only; nothing sent, real traffic ignored, its own stores in memory", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	eq(a.Arena.SetSim(true), false); eq(a.Arena.Sim(), false); eq(Printed(a, a.ns.L.ARENA_SIM_REFUSED), 1)
	eq(t.Arena.SetSim(true), true); eq(t.Arena.Sim(), true)
	local store = t.Arena.Store("L")
	local live = t.rdb.arena and t.rdb.arena.realms and t.rdb.arena.realms.Emberfall
	assert(store ~= live, "not the live store")
	store.x = 1
	eq(live and live.x, nil)
	eq(select(2, t.Arena.Send("AF", "T", "x")), "sim")
	eq(t.Arena.Counts("L"), false, "nothing counts in the sim")
	local got = Catch(t, "AF")
	t.Arena.Inject("RAID", a.name, "AF~T1~injected")
	eq(#got, 1, "the sim's own traffic reaches the handlers")
	w:As(t, function() t.comm.handlers.AF("RAID", a.name, "AF~T1~real") end)
	eq(#got, 1, "real traffic is ignored while the sim runs")
	t.Arena.SetSim(false)
	eq(t.Arena.Store("L"), t.rdb.arena.realms.Emberfall)
	eq(t.rdb.arena.realms.Emberfall.x, nil, "the sim wrote nothing there")
	eq(t.Arena.Counts("L"), true); eq(t.Arena.Counts("T"), false)
	-- The author's Workshop may run it too.
	a.ns.Workshop.Visible = function() return true end
	eq(a.Arena.SetSim(true), true)
	a.Arena.SetSim(false)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the rules' yes is the account's, and a new version of the rules asks again", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	eq(a.Arena.RulesAccepted(), false)
	a.Arena.SetRules(true)
	eq(a.Arena.RulesAccepted(), true); eq(a.db.arenaRules.v, a.ns.Arena.RULES_VERSION)
	a.ns.Arena.RULES_VERSION = a.ns.Arena.RULES_VERSION + 1
	eq(a.Arena.RulesAccepted(), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation: stores: Store(L) is this realm's live store, Store(T) the rehearsal's, Heavy nil until the companion is loaded", function()
	local w = World.New()
	local a = w:Client("Lida Fenn", { realm = "Emberfall2" })
	eq(a.Arena.Store("L"), a.rdb.arena.realms.Emberfall2); eq(a.Arena.Store("L").v, 1)
	eq(a.Arena.Store("T"), a.rdb.arenaTest)
	eq(a.Arena.RealmStore("Emberfall"), a.rdb.arena.realms.Emberfall)
	eq(a.Arena.Heavy("L"), nil); eq(a.Arena.Heavy("T"), nil)
	eq(a.Arena.RealmOf("Torvin Hale-Emberfall"), "Emberfall"); eq(a.Arena.RealmOf("Torvin Hale"), "Emberfall2")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the signature queue: one claim per sender and session, answers kept (failures too), Ed25519 fed below its limit", function()
	local w = World.New()
	local a = w:Client("Coffrey Vault")
	local Ed = a.ns.Ed25519
	local seed = ("\7"):rep(32)
	local pk = Ed.PublicKey(seed)
	local msg = "OLYW1|F1|1|a|b"
	local sig = Ed.Sign(seed, msg, pk)
	local answers = {}
	local function Cb(tag) return function(ok) answers[#answers + 1] = tag .. "=" .. tostring(ok) end end
	eq(a.Arena.Verify(N.fighterA, { pk = pk, msg = msg, sig = sig, key = "gk1|pk1" }, Cb("A")), nil, "pending")
	a.Arena.Verify(N.fighterA, { pk = pk, msg = msg, sig = sig, key = "gk1|pk1" }, Cb("A2"))
	w:Run(1)
	eq(table.concat(answers, ","), "A=true,A2=true")
	eq(a.Arena.Verify(N.fighterA, { pk = pk, msg = msg, sig = sig, key = "gk1|pk1" }, Cb("A3")), true, "kept")
	eq(a.Arena.Verify(N.fighterA, { pk = pk, msg = "other", sig = sig, key = "gk2|pk1" }, Cb("A4")), false, "one claim a session")
	a.Arena.Verify(N.fighterB, { pk = pk, msg = "forged", sig = sig, key = "gk3|pk1" }, Cb("B"))
	w:Run(1)
	eq(answers[#answers], "B=false")
	eq(a.Arena.Verify(N.fighterB, { pk = pk, msg = "forged", sig = sig, key = "gk3|pk1" }, Cb("B2")), false, "a failure is kept")
	-- Ed25519's queue full: the claim waits here.
	local busy = Ed.Busy
	Ed.Busy = function() return 40 end
	local ok, err = pcall(function()
		a.Arena.Verify(N.bettor1, { pk = pk, msg = msg, sig = sig, key = "gk4|pk1" }, Cb("C"))
		eq(a.Arena.VerifyQueue(), 1)
		w:Run(3)
		eq(a.Arena.VerifyQueue(), 1, "not fed while Ed25519 has 40 jobs")
	end)
	Ed.Busy = busy
	if not ok then error(err, 0) end
	w:Run(3)
	eq(a.Arena.VerifyQueue(), 0); eq(answers[#answers], "C=true")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the rehearsal's director (ER): on a test build a signed arbiter or his named co-director; copper mode never names the director bank or fee stand-in", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	local A = t.Arena
	eq(A.MayDirect(N.arbiter, { lane = "g", money = "c", roles = {} }), true)
	eq(select(2, A.MayDirect(N.bettor1, { lane = "g", money = "c", roles = {} })), "director", "a tester who is no signed arbiter")
	local current = { director = N.arbiter, roles = { [N.bettor1] = "d" } }
	eq(A.MayDirect(N.bettor1, { lane = "g", money = "c", roles = {} }, current), true, "named co-director")
	eq(select(2, A.MayDirect(N.bettor2, { lane = "g", money = "c", roles = {} }, current)), "director")
	eq(select(2, A.MayDirect(N.bettor1, { lane = "g", money = "c", roles = {} }, { director = N.bettor3, roles = { [N.bettor1] = "d" } })), "director",
		"named by a director who is no signed arbiter")
	eq(select(2, A.MayDirect(N.arbiter, { lane = "g", money = "p", roles = { [N.arbiter] = "b" } })), "self")
	eq(select(2, A.MayDirect(N.arbiter, { lane = "g", money = "p", roles = { [N.arbiter] = "t" } })), "self")
	eq(A.MayDirect(N.arbiter, { lane = "g", money = "p", roles = { [N.bettor1] = "b", [N.bettor2] = "t" } }), true)
	-- A release: the King, a Steward, a High Councillor, a signed arbiter.
	local r = w:Client("Lida Fenn")
	eq(r.Arena.MayDirect(N.steward, { lane = "a", money = "c", roles = {} }), true)
	eq(r.Arena.MayDirect(N.councillor, { lane = "a", money = "c", roles = {} }), true)
	eq(select(2, r.Arena.MayDirect(N.bettor2, { lane = "a", money = "c", roles = {} })), "director")
	NoErrors(w)
end)

print("ArenaRoles: the King's words")

test("1.2 the arena's foundation: T1~B: the King's or a Steward's word (a Hand's refused); a keeper, the Treasurer's character or an arbiter is never a bank", function()
	local w = World.New()
	local king, steward, hand, b = w:Role("king"), w:Role("steward"), w:Role("hand"), w:Client("Lida Fenn")
	w:As(king, function() king.ns.King.AddHand(N.hand) end)
	w:Run(30)
	eq(b.King.IsHandName(N.hand), true, "a Hand of the King's")
	-- A Hand's word is no word.
	Word(w, hand, "B", N.bank .. ":o")
	eq(#b.Roles.Banks("L"), 0)
	eq(select(2, hand.Roles.SetBanks({ N.bank })), "king", "his own client refuses too")
	-- A Steward's is.
	eq(steward.Roles.SetBanks({ N.bank }), true)
	w:Run(0)
	eq(#b.Roles.Banks("L"), 1); eq(b.Roles.Banks("L")[1].name, N.bank); eq(b.Roles.BankState(N.bank), "o")
	eq(b.Roles.IsBank(N.bank, "L"), true); eq(b.Roles.IsBank(N.bettor2, "L"), false)
	eq(king.Roles.IsBank(N.bank, "L"), true)
	eq(Printed(king, "changed the arena's"), 1, "the King is told his Steward changed it")
	-- Refused by the giver's composer and by every client.
	eq(select(2, king.Roles.SetBanks({ N.treasurerMail })), "keeper")
	eq(select(2, king.Roles.SetBanks({ N.arbiter })), "arbiter")
	eq(select(2, king.Roles.SetBanks({ N.councillor })), "councillor")
	eq(select(2, king.Roles.SetBanks({ N.steward })), "steward")
	eq(select(2, king.Roles.SetBanks({ N.king })), "king")
	eq(select(2, king.Roles.SetBanks({ "A", "B", "C", "D" })), "count")
	Word(w, king, "B", N.treasurerMail .. ":o," .. N.bank .. ":c", w.clock + 5)
	eq(#b.Roles.Banks("L"), 1, "the keeper left out on every client"); eq(b.Roles.BankState(N.bank), "c")
	-- A keeper the King lists (T1~K) the same.
	w:As(king, function() king.ns.Treasury.AddKeeper(N.bettor3) end)
	w:Run(0)
	Word(w, king, "B", N.bettor3 .. ":o", w.clock + 10)
	eq(#b.Roles.Banks("L"), 0)
	eq(b.Roles.Why(N.bettor3, "bank"), "keeper")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the words: the newest wins, the King's own on the same second; a word dated more than a minute ahead or malformed is not taken", function()
	local w = World.New()
	local king, steward, b = w:Role("king"), w:Role("steward"), w:Client("Lida Fenn")
	local t0 = w.clock
	Word(w, steward, "B", N.bank .. ":o", t0)
	Word(w, king, "B", N.bettor1 .. ":o", t0)
	eq(b.Roles.Banks("L")[1].name, N.bettor1, "the King's on the same second")
	Word(w, steward, "B", N.bettor2 .. ":o", t0)
	eq(b.Roles.Banks("L")[1].name, N.bettor1, "a Steward's on the same second never replaces the King's")
	Word(w, steward, "B", N.bettor2 .. ":o", t0 + 1)
	eq(b.Roles.Banks("L")[1].name, N.bettor2, "newer")
	Word(w, king, "B", N.bank .. ":o", t0 - 5)
	eq(b.Roles.Banks("L")[1].name, N.bettor2, "older")
	Word(w, king, "B", N.bank .. ":o", w.clock + 61)
	eq(b.Roles.Banks("L")[1].name, N.bettor2, "more than a minute ahead")
	for _, bad in ipairs({ N.bank .. ":x", N.bank, "<b>:o", N.bank .. ":o," .. N.bank .. ":o" }) do
		Word(w, king, "B", bad, w.clock)
		eq(b.Roles.Banks("L")[1].name, N.bettor2, bad)
	end
	-- Not from the King or a Steward: no word at all, nothing answered.
	eq(steward.Roles.SetBanks({ N.bank }), true)
	w:Run(0)
	local function Words()
		local n = 0
		for _, s in ipairs(w:Sent{ from = steward }) do if s.msg:find("^T1~B~") then n = n + 1 end end
		return n
	end
	local before = Words()
	Word(w, b, "B", N.bettor1 .. ":o", t0 - 100, "Olympus Ember")
	eq(Words(), before, "not from the King or a Steward")
	-- An older word heard on the giver's side (the King's client missed it) is answered with the
	-- newer one, once: another within ANSWER_GAP (30 s) is not; after it, again. (The older words
	-- above were answered already: 30 s first.)
	w:Run(31)
	before = Words()
	local kept = steward.Roles.Banks("L")[1].name
	Word(w, king, "B", N.bettor1 .. ":o", t0 - 100)
	eq(Words(), before + 1, "answered")
	eq(king.Roles.Banks("L")[1].name, kept, "the King's client takes the newer one")
	Word(w, king, "B", N.bettor1 .. ":o", t0 - 90)
	eq(Words(), before + 1, "not again within 30 s")
	w:Run(31)
	Word(w, king, "B", N.bettor1 .. ":o", t0 - 80)
	eq(Words(), before + 2)
	eq(b.Roles.Banks("L")[1].name, kept, "nobody took the older ones")
	NoErrors(w)
end)

test("1.2 the arena's foundation: T1~M: up to 40 arbiters with their caps in gold (none: the lowest tier, 100 g); never a bank; public arbiters hold 100 g", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	local list = { { name = N.fighterA, cap = 250 }, { name = N.fighterB } }
	for i = 1, 38 do list[#list + 1] = { name = "Arbiter Number" .. ("abcdefghijklmnopqrstuvwxyzabcdefghijkl"):sub(i, i) .. i, cap = i } end
	eq(select(2, king.Roles.SetArbiters(list)), "name", "a name the addon takes")
	list = { { name = N.fighterA, cap = 250 }, { name = N.fighterB } }
	for i = 1, 38 do list[#list + 1] = { name = "Arbiter " .. ("abcdefghijklmnopqrstuvwxyz"):sub((i - 1) % 26 + 1, (i - 1) % 26 + 1) .. string.rep("x", math.floor((i - 1) / 26) + 1), cap = 100 + i } end
	eq(king.Roles.SetArbiters(list), true)
	w:Run(0)
	eq(#b.Roles.Arbiters(), 40)
	eq(b.Roles.ArbiterCap(N.fighterA), 250 * 10000); eq(b.Roles.ArbiterCap(N.fighterB), 100 * 10000)
	eq(b.Roles.IsArbiter(N.fighterA, "L"), true); eq(b.Roles.IsPublicArbiter(N.fighterA, "L"), false)
	eq(b.Roles.ArbiterCap(N.arbiter), 100 * 10000, "a signed arbiter the word leaves out"); eq(b.Roles.ArbiterCap(N.bettor1), 0)
	eq(#w:Sent{ from = king, dist = "CHANNEL" } > 0, true)
	list[#list + 1] = { name = "One Toomany" }
	eq(select(2, king.Roles.SetArbiters(list)), "count")
	eq(select(2, king.Roles.SetArbiters({ { name = N.fighterA, cap = 0 } })), "cap")
	eq(select(2, king.Roles.SetArbiters({ { name = N.fighterA, cap = 50001 } })), "cap")
	king.Roles.SetBanks({ N.bank })
	w:Run(0)
	eq(select(2, king.Roles.SetArbiters({ { name = N.bank, cap = 10 } })), "bank")
	Word(w, king, "M", N.bettor1 .. ":0", w.clock + 1)
	eq(#b.Roles.Arbiters(), 40, "a cap of 0 refuses the word")
	NoErrors(w)
end)

test("1.2 the arena's foundation: T1~O: gold by default; bounds refuse the whole word; gold with no fee receiver refused (a Horde world), a named one accepted", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	local s = b.Roles.Settings()
	eq(s.cur, "g"); eq(s.live, 0); eq(s.feeBp, 600); eq(s.arbBp, 200); eq(s.minBet, 1000); eq(s.maxBet, 200000); eq(s.maxDay, 600000)
	eq(s.maxPool, 10000000); eq(s.bankCap, 50000000); eq(s.directMax, 500000); eq(s.scalePct, 100); eq(s.minLevel, 10); eq(s.feeTo, nil)
	eq(b.Roles.Currency(), "g"); eq(b.Roles.Live(), false)
	eq(b.Roles.FeeReceiver(), N.treasurerMail, "the Treasurer's mail character on his realm group")
	eq(b.Roles.IsFeeReceiver(N.treasurer), true); eq(b.Roles.IsFeeReceiver(N.bettor1), false)
	for _, bad in ipairs({ { feeBp = 1001 }, { arbBp = 700 }, { minBet = 99 }, { maxBet = 501 * 10000 }, { scalePct = 24 }, { minLevel = 61 }, { cur = "x" } }) do
		local k = next(bad)
		eq(select(2, king.Roles.SetSettings(bad)), k == "maxBet" and "maxBet" or k, k)
	end
	GoLive(w, king, { live = 1, cur = "p", scalePct = 150 })
	eq(b.Roles.Live(), true); eq(b.Roles.Currency(), "p"); eq(b.Roles.Settings().scalePct, 150)
	-- Out of bounds on the wire: the whole word refused.
	local text = b.Roles.SettingsText(b.Roles.Settings()):gsub("^1~p~600", "0~g~1500")
	Word(w, king, "O", text, w.clock + 1)
	eq(b.Roles.Live(), true, "unchanged")
	-- A Horde world: no Treasurer there, no fee receiver unless the King names one.
	local h = World.New()
	local hk = h:Role("kingHorde")
	local hb = h:Client("Grukk Tallyhand", { faction = "Horde" })
	local other = h:Client("Lida Fenn", { faction = "Horde" })
	eq(other.Roles.FeeReceiver(), nil)
	eq(select(2, hk.Roles.SetSettings({ live = 1 })), "receiver")
	local refused = hb.Roles.SettingsText(hb.Roles.Settings()):gsub("^0~", "1~")
	Word(h, hk, "O", refused)
	eq(other.Roles.Live(), false, "gold with nobody to receive the fee: the whole word refused")
	eq(hk.Roles.SetSettings({ live = 1, feeTo = N.feeReceiver }), true)
	h:Run(0)
	eq(other.Roles.Live(), true); eq(other.Roles.FeeReceiver(), N.feeReceiver); eq(other.Roles.IsFeeReceiver(N.feeReceiver), true)
	eq(select(2, hk.Roles.SetSettings({ live = 1, feeTo = false })), "receiver")
	eq(hk.Roles.SetSettings({ cur = "p", feeTo = false }), true, "glory points need no receiver")
	NoErrors(w)
	NoErrors(h)
end)

test("1.2 the arena's foundation: realm scope: a word belongs to its sender's realm; the other realm's arena is separate", function()
	local w = World.New()
	local king2 = w:Role("king", { realm = "Emberfall2" })
	local r1, r2 = w:Client("Lida Fenn"), w:Client("Parric Stowe", { realm = "Emberfall2" })
	GoLive(w, king2)
	eq(r2.Roles.Live(), true); eq(r1.Roles.Live(), false, "the channel is per realm: realm 1 never heard it")
	-- Heard anyway (a shared channel): kept under realm 2, never realm 1's.
	local text = ("T1~O~5~%s~%d~%s"):format(World.KING_GUILD, w.clock, r1.Roles.SettingsText({ live = 1, cur = "g", feeBp = 600, arbBp = 200, minBet = 1000,
		maxBet = 200000, maxDay = 600000, maxPool = 10000000, bankCap = 50000000, directMax = 500000, scalePct = 100, minLevel = 10 }))
	w:As(r1, function() r1.ns.King.HandleCommand("CHANNEL", king2.name, text) end)
	eq(r1.Roles.Live(), false); eq(r1.Roles.Live("Emberfall2"), true)
	eq(r1.rdb.arena.realms.Emberfall2.roles.settings.from, king2.name)
	NoErrors(w)
end)

test("1.2 the arena's foundation: who is who: the signed arbiters and auditors (^arbiter^), leaders, auditors (never a Steward alone), promoters (the King's Hands too)", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	w:As(king, function() king.ns.King.AddHand(N.hand) end)
	w:Run(30)
	local ns2 = b.ns
	eq(ns2.IsSignedArbiter(N.arbiter), true); eq(ns2.IsSignedAuditor(N.arbiter), false)
	eq(ns2.IsSignedArbiter(N.auditor), true); eq(ns2.IsSignedAuditor(N.auditor), true)
	eq(ns2.IsSignedArbiter("Oswin Marrow-Emberfall2"), true, "names are one per realm group")
	eq(ns2.IsSignedArbiter("Oswin Marrow-Farshore"), false, "a namesake on another group")
	eq(ns2.IsSignedArbiter(N.bettor1), false); eq(ns2.IsSignedArbiter(nil), false)
	local R = b.Roles
	eq(R.IsPublicArbiter(N.king), true); eq(R.IsPublicArbiter(N.councillor), true); eq(R.IsPublicArbiter(N.arbiter), true)
	eq(R.IsPublicArbiter(N.steward), false)
	eq(R.Leader(N.steward), true); eq(R.Leader(N.arbiter), true); eq(R.Leader(N.bettor1), false); eq(R.Leader(N.hand), false)
	eq(R.Auditor(N.king), true); eq(R.Auditor(N.councillor), true); eq(R.Auditor(N.auditor), true)
	eq(R.Auditor(N.arbiter), false, "no +a"); eq(R.Auditor(N.steward), false, "a Steward is no auditor (the owner's answer)")
	eq(R.MayPromote(N.hand), true); eq(R.MayPromote(N.steward), true); eq(R.MayPromote(N.arbiter), true); eq(R.MayPromote(N.bettor1), false)
	eq(R.IsKing(N.king), true); eq(R.IsKing(N.steward), false)
	-- Stand-ins count in T alone.
	R.standIn = function(name, letter) return name == N.bettor1 and letter == "p" end
	eq(R.IsPublicArbiter(N.bettor1, "T"), true); eq(R.IsPublicArbiter(N.bettor1, "L"), false)
	R.standIns = function(letter) return letter == "b" and { N.bettor2 } or {} end
	eq(R.IsBank(N.bettor2, "T"), true); eq(R.IsBank(N.bettor2, "L"), false)
	-- ns.ReadArbiters: "+a", at most 5 a faction, bad names left out.
	local read = ns2.ReadArbiters("^arbiter^Alliance^One Name-Realm+a,Two Name,<x>,Three Name-Realm+q,A B,C D,E F,G H;^arbiter^Horde^Orc Name")
	eq(#read.Alliance, 5); eq(read.Alliance[1].name, "One Name-Realm"); eq(read.Alliance[1].audit, true); eq(read.Alliance[2].audit, nil)
	eq(read.Horde[1].name, "Orc Name")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the bank's role is refused on its own client while any character of its account is a leader, an arbiter or a keeper", function()
	local w = World.New()
	local bank = w:Role("bank")
	eq(bank.Roles.MayBank(), true)
	for _, case in ipairs({ { N.steward, "steward" }, { N.councillor, "councillor" }, { N.arbiter, "arbiter" }, { N.treasurerMail, "keeper" }, { N.king, "king" } }) do
		bank.db.myCharacters = { [bank.name:lower()] = true, [case[1]:lower()] = true }
		local ok, why, who = bank.Roles.MayBank()
		eq(ok, false, case[1]); eq(why, case[2]); eq(who, case[1])
	end
	bank.db.myCharacters = { [bank.name:lower()] = true, [N.bettor1:lower()] = true }
	eq(bank.Roles.MayBank(), true)
	eq(bank.Roles.ProperName("marrek oakhand-emberfall2"), "Marrek Oakhand-Emberfall2")
	NoErrors(w)
end)

test("1.2 the arena's foundation: a bank a newer word leaves out while it still owes stays, closing; the composer refuses to drop it", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	king.Roles.SetBanks({ N.bank })
	w:Run(0)
	for _, c in ipairs({ king, b }) do c.Roles.stillOwing = function(name) return name == N.bank end end
	eq(select(2, king.Roles.SetBanks({ N.bettor2 })), "owing")
	Word(w, king, "B", N.bettor2 .. ":o", w.clock + 1)
	local banks = b.Roles.Banks("L")
	eq(#banks, 2); eq(b.Roles.BankState(N.bank), "c"); eq(b.Roles.BankState(N.bettor2), "o")
	b.Roles.stillOwing = function() return false end
	eq(#b.Roles.Banks("L"), 1, "paid: gone")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the giver's client repeats its own words every 5 minutes for late logins; nobody else's does", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	king.Roles.SetBanks({ N.bank })
	w:Run(0)
	local sent = #w:Sent{ from = king }
	w:Run(301)
	assert(#w:Sent{ from = king } > sent, "repeated")
	eq(#w:Sent{ from = b }, 0, "a client that only heard it sends nothing")
	eq(#w:Timers(b, true), 0)
	local late = w:Client("Parric Stowe")
	eq(#late.Roles.Banks("L"), 0)
	w:Run(300)
	eq(#late.Roles.Banks("L"), 1, "a late login hears it")
	NoErrors(w)
end)

print("ArenaNet: the weight rule and the companion")

test("1.2 the arena's foundation: an idle client: no arena timer or frame, only keeper gossip and logout events, nothing stored in the heavy tables", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	w:Run(3600)
	local weight = w:ArenaWeight(a)
	eq(table.concat(weight.events, ","), "GOSSIP_SHOW,PLAYER_LOGOUT"); eq(weight.timers, 0); eq(weight.frames, 0)
	eq(a.Arena.Heavy("L"), nil); eq(a.companion.loaded, nil)
	-- A message sent and done: back to nothing.
	a.Arena.Send("AF", "T", "x", { to = "Parric Stowe" })
	w:Run(120)
	weight = w:ArenaWeight(a)
	eq(weight.timers, 0)
	eq(table.concat(weight.events, ","), "CHAT_MSG_SYSTEM,GOSSIP_SHOW,PLAYER_LOGOUT", "the not-found line's handler, on first use")
	NoErrors(w)
end)

test("1.2 the arena's foundation: /oly arena loads the companion with the handoff; its registry, its heavy tables kept across a login where saved data persists", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	w:As(a, function() a.slashes.OLYMPUS("arena") end)
	eq(a.companion.loaded, true); eq(a.Arena.UILoaded(), true); eq(a.ns.Arena.companionReady, true)
	-- (the screens built the window: /oly arena opens it now, where the stubs said there was none.)
	eq(Printed(a, a.ns.L.ARENA_NO_WINDOW), 0, "the window is the screens'")
	eq(a.companion.own.ArenaUI.IsShown(), true, "the window opened")
	eq(rawget(_G, "OlympusArenaHandoff"), nil, "the handoff lasts one call")
	local UIr = a.ns.Arena.ui
	eq(type(UIr.RegisterPane), "function")
	eq(UIr.RegisterPane("fights", { section = "arena", label = "Fights", order = 2 }), true)
	eq(UIr.RegisterPane("farkle", { section = "farkle", label = "Farkle" }), true)
	eq(UIr.RegisterPane("lotto", { section = "lottery", label = "Lottery", visible = function() return false end }), true)
	eq(UIr.RegisterPane("fights", { section = "arena", label = "Again" }), false, "a key taken")
	eq(UIr.RegisterPane("x", { section = "poker", label = "X" }), false, "a section there is not")
	eq(UIr.RegisterPane("tourney", { section = "arena", label = "Tournament", order = 1 }), true)
	-- (Read among this test's own keys: the screens' panes are registered there too.)
	local function Keys(list, want)
		local out = {}
		for _, e in ipairs(list) do if want[e.key] then out[#out + 1] = e.key end end
		return table.concat(out, ",")
	end
	eq(Keys(UIr.Panes("arena"), { fights = true, tourney = true, farkle = true, lotto = true }), "tourney,fights")
	eq(Keys(UIr.Panes("lottery"), { lotto = true }), "", "not visible")
	eq(UIr.RegisterStaffTab("bank", { label = "Bank", visible = function() return true end }), true)
	-- (this test's Bank, and the games' page every member opens: the games' ledger, 1.1.6)
	eq(#UIr.StaffTabs(), 2)
	eq(UIr.StaffTabs()[1].key, "staff.games")
	eq(table.concat(UIr.SECTIONS, ","), "arena,farkle,lottery")
	local heavy = a.Arena.Heavy("L")
	eq(type(heavy), "table")
	heavy.kept = "yes"
	eq(a.Arena.LoadUI(), true, "once")
	w:Logout(a)
	w:Login(a)
	eq(a.Arena.Heavy("L"), nil, "not before the companion loads")
	a.Arena.LoadUI()
	eq(a.Arena.Heavy("L").kept, "yes")
	-- The companion is idle too: no frame, no event, no timer of its own (once ARENA_CHANGED went).
	w:Run(5)
	local weight = w:ArenaWeight(a)
	eq(weight.frames, 0); eq(weight.timers, 0)
	NoErrors(w)
end)

test("1.2 the arena's foundation: LoadUI refuses in combat and says why for DISABLED, MISSING, INTERFACE_VERSION, DEP_*, another version, and a companion another addon loaded", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local L = a.ns.L
	w:Combat(a, true)
	eq(select(2, a.Arena.LoadUI()), "combat"); eq(Printed(a, L.ARENA_UI_COMBAT), 1); eq(a.companion.loaded, nil)
	w:Combat(a, false)
	for _, case in ipairs({ { "disabled", "DISABLED", L.ARENA_UI_DISABLED }, { "missing", "MISSING", L.ARENA_UI_MISSING },
		{ "interface", "INTERFACE_VERSION", L.ARENA_UI_OUTDATED }, { "dep", "DEP_DISABLED", L.ARENA_UI_DEP } }) do
		a.companion.state = case[1]
		eq(select(2, a.Arena.LoadUI()), case[2]); eq(Printed(a, case[3]), 1, case[1])
	end
	a.companion.state = nil
	local b = w:Client("Parric Stowe", { companion = { version = "9.9.9" } })
	eq(select(2, b.Arena.LoadUI()), "version"); eq(Printed(b, b.ns.L.ARENA_UI_VERSION), 1); eq(b.ns.Arena.companionReady, false)
	eq(b.Arena.Heavy("L"), nil)
	eq(select(2, b.Arena.LoadUI()), "version", "and at the next open: never 'another addon loaded it early'")
	eq(Printed(b, b.ns.L.ARENA_UI_EARLY), 0)
	local c = w:Client("Wenna Crale")
	w:PreloadCompanion(c)
	eq(select(2, c.Arena.LoadUI()), "early"); eq(Printed(c, c.ns.L.ARENA_UI_EARLY), 1); eq(c.ns.Arena.companionReady, false)
	c.Arena.LoadUI()
	eq(Printed(c, c.ns.L.ARENA_UI_EARLY), 1, "said once")
	eq(a.Arena.LoadUI(), true)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the companion: its TOC (load on demand, Olympus's version and dependency, its saved variables, every file there), each file behind the host line", function()
	local toc = Read(H.ARENA_DIR .. "Olympus_Arena.toc")
	local core = Read(H.ADDON_DIR .. "Olympus.toc")
	eq(toc:match("## Version:%s*(%S+)"), core:match("## Version:%s*(%S+)"))
	eq(toc:match("## Version:%s*(%S+)"), H.ns.VERSION, "the base version (ns.VERSION)")
	eq(toc:match("## Interface:%s*([^\r\n]+)"), core:match("## Interface:%s*([^\r\n]+)"))
	eq(toc:match("## LoadOnDemand:%s*(%S+)"), "1"); eq(toc:match("## Dependencies:%s*(%S+)"), "Olympus")
	eq(toc:match("## SavedVariables:%s*(%S+)"), "OlympusArenaDB")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		local f = line:match("^([%w_\\]+%.lua)$")
		if f then files[#files + 1] = f:gsub("\\", "/") end
	end
	eq(files[1], "Handoff.lua"); eq(files[#files], "Sim.lua")
	for _, f in ipairs({ "Panes.lua", "Kit.lua", "Window.lua", "FarkleBoard.lua", "LotteryBoard.lua", "Locales/UIText.lua" }) do
		local found = false
		for _, g in ipairs(files) do if g == f then found = true end end
		assert(found, f)
	end
	for i, f in ipairs(files) do
		local src = Read(H.ARENA_DIR .. f)
		if i > 1 then assert(src:find("^local _, own = %.%.%.; local ns = own%.host; if not ns then return end"), f .. ": the host line") end
	end
	-- Loaded outside Olympus's handoff it does nothing, and says nothing.
	local own = H.LoadCompanion(false)
	eq(own.host, nil); eq(own.ArenaUI, nil)
end)

print("ArenaNet: the registry, the source rules, the hooks")

-- The arena's types as the design lists them, by owner, and matchmaking's AM (the design,
-- which takes the design's count from 63 to 64), and the Lottery's LW (a day's bank publishes its
-- winners for the Games tab's rankings: only the bank knows whose tickets they are), and the
-- games' ledger's AY (1.1.6: a finished game's record, any game, from its players to the auditors;
-- ArenaLedger's, as Bone Throw's KW was before the ledger took every kind of game).
local SPEC_TYPES = {
	ArenaNet = "EP", ArenaChat = "EC EM", ArenaTest = "ER EH", Wallet = "ZH ZE ZN ZG ZD ZK ZC ZW ZS ZQ ZL ZJ", Debts = "ZT ZX ZY ZR ZF",
	Stakes = "ZA ZV", Markets = "BM BO BS BK BV", MarketBank = "BF", ArenaFights = "AF AG AC AW AR AS AN", ArenaLedger = "AE AB AQ AV AH AY",
	ArenaTourney = "AT AD", ArenaProfile = "AP", HonorsNet = "IL ID IO", FarkleTable = "KI KA KO KP KG KY KH KK KT KE KQ KR KS KN KD KL",
	ArenaMatch = "AM", Lottery = "LW", ArenaRoles = "AU",
}

test("1.2 the arena's foundation: the registry: Arena.TYPES names all 66 types by owner; Comm.lua lists all but runtime KL; a file registers only its own", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local src = Read(H.ADDON_DIR .. "Comm.lua")
	local block = src:match("1%.2, the Blood Arena.-\nlocal handlers = {}")
	assert(block, "the 1.2 lines of Comm.lua's list")
	block = block:gsub("\n%-%-%s*", " "):match("Arena%.Handle%): (.-)%.%s")
	assert(block, "its owners and types")
	local listed = {}
	for part in (block .. "|"):gmatch("([^|]*)|") do
		local owner, types = part:match("^%s*(%a+)%s+(.-)%s*$")
		for kind in types:gmatch("%S+") do
			assert(not listed[kind], kind .. " listed twice")
			listed[kind] = owner
		end
	end
	local n, spec, legacy = 0, {}, 0
	for owner, types in pairs(SPEC_TYPES) do
		for kind in types:gmatch("%S+") do
			n = n + 1
			spec[kind] = owner
			if kind == "KL" then
				eq(listed[kind], nil, "KL is registered by FarkleTable without editing Comm.lua")
			else
				eq(listed[kind], owner, kind .. " in Comm.lua's list")
				legacy = legacy + 1
			end
			eq(a.ns.Arena.TYPES[kind], owner, kind .. " in Arena.TYPES")
		end
	end
	eq(n, 68)
	eq(legacy, 67)
	for kind in pairs(listed) do assert(spec[kind], kind .. " in Comm.lua is no arena type") end
	local m = 0
	for kind in pairs(a.ns.Arena.TYPES) do m = m + 1; assert(spec[kind], kind .. " is not in the design's list") end
	eq(m, 68)
	-- Registered only by their owners' files, through Arena.Handle, with a literal.
	for _, file in ipairs(World.ARENA_FILES) do
		local code = Read(H.ADDON_DIR .. file .. ".lua"):gsub("%-%-[^\n]*", "")
		for kind in code:gmatch('Comm%.Handle%("(%w%w)"') do
			eq(spec[kind], file, kind .. " registered in " .. file)
			assert(code:find(('ns.Comm.Handle("%s", ns.Arena.Handle("%s"'):format(kind, kind), 1, true) or code:find(('ns.Comm.Handle("%s", Arena.Handle("%s"'):format(kind, kind), 1, true), kind .. " through Arena.Handle")
		end
	end
	eq(a.ns.Arena.Handles("EP"), true)
end)

test("1.2 the arena's foundation: the source rules: no arena or companion file names the author, uses OnUpdate (companion) or the game's popups; no real name in the arena's files and tests", function()
	-- (The pure modules are the arena's parser's: they come with their own branches' rules.)
	local PURE = { ArenaMath = true, ArenaRating = true, ArenaBracket = true, ArenaFarkle = true, ArenaParse = true, Honors = true }
	local files = {}
	for _, f in ipairs(World.ARENA_FILES) do if not PURE[f] then files[#files + 1] = H.ADDON_DIR .. f .. ".lua" end end
	for _, f in ipairs({ "ArenaNetText", "ArenaMoneyText", "ArenaMarketsText", "ArenaFightsText", "ArenaFarkleText", "ArenaHomeText", "ArenaLotteryText" }) do
		files[#files + 1] = H.ADDON_DIR .. "Locales/" .. f .. ".lua"
	end
	local companion = {}
	for line in io.lines(H.ARENA_DIR .. "Olympus_Arena.toc") do
		local f = line:match("^([%w_\\]+%.lua)%s*$")
		if f then companion[#companion + 1] = H.ARENA_DIR .. f:gsub("\\", "/") end
	end
	for _, f in ipairs(companion) do files[#files + 1] = f end
	local isCompanion = {}
	for _, f in ipairs(companion) do isCompanion[f] = true end
	for _, path in ipairs(files) do
		local code = Read(path):gsub("%-%-[^\n]*", "")
		-- (The owner's call, 2026-09-30: the Frame Lab's practice games ship inside the companion as
		-- they are, under Olympus_Arena/Games/: their animation driver runs an OnUpdate only while
		-- something moves, and their Escape handling edits UISpecialFrames itself. Only those two
		-- words are allowed there; every other rule holds for them too.)
		local labGame = path:find("Olympus_Arena/Games/", 1, true) ~= nil
		for _, word in ipairs({ "ns.AUTHOR", "IsAuthorName", "IsAuthor", "StaticPopup_", "UISpecialFrames" }) do
			if not (labGame and word == "UISpecialFrames") then assert(not code:find(word, 1, true), path .. " uses " .. word) end
		end
		if isCompanion[path] and not labGame then assert(not code:find("OnUpdate", 1, true), path .. " uses OnUpdate") end
	end
	-- The real characters Olympus pins (the King, the Treasurer, the author) are nowhere in them, in
	-- the pure modules, nor in any arena test or fixture (every package's, under tests/arena/ and
	-- tests/fixtures/arena-*); nor is anyone named as the source of a decision ("the owner's answer").
	-- the arena's parser's Honors.lua names the author in two comments: a named exception, reworded at integration.
	local EXCEPT = { [H.ADDON_DIR .. "Honors.lua"] = true }
	local real = { H.ns.KING_CHARACTER.Alliance, H.ns.KING_CHARACTER.Horde, H.ns.TREASURER, H.ns.AUTHOR, H.ns.KING_NAME }
	for _, n in ipairs(H.ns.TREASURER_CHARACTERS) do real[#real + 1] = n end
	local scan = {}
	for _, f in ipairs(files) do scan[#scan + 1] = f end
	for f in pairs(PURE) do scan[#scan + 1] = H.ADDON_DIR .. f .. ".lua" end
	local function Find(dir)
		local out = {}
		local p = io.popen('find "' .. dir .. '" -type f -name "*.lua" 2>/dev/null')
		for line in p:lines() do out[#out + 1] = line end
		p:close()
		return out
	end
	local tests = Find(H.ROOT .. "tests/arena")
	assert(#tests >= 3, "the arena's tests found")
	for _, f in ipairs(tests) do scan[#scan + 1] = f end
	for _, f in ipairs(Find(H.ROOT .. "tests/fixtures")) do
		if f:find("/arena%-[^/]*%.lua$") then scan[#scan + 1] = f end
	end
	local ROLES = { King = true, Steward = true, Treasurer = true, Council = true, Director = true }
	for _, path in ipairs(scan) do
		if not EXCEPT[path] then
			local raw = Read(path)
			local src = raw:lower()
			for _, n in ipairs(real) do
				for word in n:lower():gmatch("%S+") do
					if #word > 3 then assert(not src:find(word, 1, true), path .. " names " .. n) end
				end
			end
			for _, phrase in ipairs({ "(%u%l+)'s answer to open question", "(%u%l+)'s decision" }) do
				for who in raw:gmatch(phrase) do assert(ROLES[who], path .. " names " .. who .. " as a decision's source") end
			end
		end
	end
end)

test("1.2 the arena's foundation: every word the arena's core says exists in English and pt-BR, the same keys", function()
	local en, pt = {}, {}
	local src = Read(H.ADDON_DIR .. "Locales/ArenaNetText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	for k in head:gmatch("\nL%.([%w_]+) =") do en[k] = true end
	for k in tail:gmatch("\n\tL%.([%w_]+) =") do pt[k] = true end
	for k in pairs(en) do assert(pt[k], "pt-BR lacks " .. k) end
	for k in pairs(pt) do assert(en[k], "English lacks " .. k) end
	-- Each L.X the core's arena files and hooks use is defined.
	local used = {}
	for _, f in ipairs({ "ArenaNet.lua", "ArenaRoles.lua", "Backup.lua", "Workshop.lua", "UI.lua" }) do
		local code = Read(H.ADDON_DIR .. f)
		for k in code:gmatch("L%.(ARENA_[%w_]+)") do used[k] = true end
		for k in code:gmatch("L%.(BACKUP_ARENA[%w_]*)") do used[k] = true end
		for k in code:gmatch("L%.(WORKSHOP_[%w_]+)") do if k:find("ARENA") or k == "WORKSHOP_NO_RELEASED" then used[k] = true end end
	end
	used.PROFILE_EDIT_BTN = true
	for _, part in ipairs({ "BANK", "KEY", "COPPER", "MINE", "STAKES", "TICKETS" }) do used["BACKUP_ARENA_" .. part] = true end
	for _, why in ipairs({ "KING", "STEWARD", "COUNCILLOR", "KEEPER", "ARBITER", "UNLISTED", "NAME", "PUBLIC", "AUDITOR", "LEADER", "ROLE" }) do used["ARENA_WHY_" .. why] = true end
	for _, word in ipairs({ "BANKS", "ARBITERS", "SETTINGS" }) do used["ARENA_WORD_" .. word] = true end
	for k in pairs(used) do assert(en[k], "not defined: " .. k) end
	local L = H.ns.L
	eq(L.SOUND_ARENA ~= "SOUND_ARENA", true); eq(L.HELP_ARENA ~= "HELP_ARENA", true)
end)

test("1.2 the arena's foundation: Core: the arena's sound kind, the Treasurer's characters by name on his realm group, Olympus_Arena's errors are Olympus's", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local ns2 = a.ns
	local found = false
	for _, k in ipairs(ns2.SOUND_KINDS) do if k == "arena" then found = true end end
	eq(found, true); eq(ns2.SoundLabel("arena"), ns2.L.SOUND_ARENA)
	eq(ns2.IsTreasurerCharacter(N.treasurer), true); eq(ns2.IsTreasurerCharacter(N.treasurerMail), true)
	eq(ns2.IsTreasurerCharacter("Tamsin Coinwell-Emberfall2"), true, "names are one per realm group")
	eq(ns2.IsTreasurerCharacter("Tamsin Coinwell-Farshore"), false, "a namesake elsewhere")
	eq(ns2.IsTreasurerCharacter(N.bettor1), false); eq(ns2.IsTreasurerCharacter(""), false); eq(ns2.IsTreasurerCharacter(nil), false)
	eq(ns2.IsTreasurer(N.treasurerMail, nil), false, "(the whisper's case: IsTreasurer needs a guild)")
	local own = H.ns.OwnError
	eq(own("Interface/AddOns/Olympus_Arena/Window.lua:3: boom"), true)
	eq(own("x", "Interface\\AddOns\\Olympus_Arena\\Panes.lua:9: in function"), true)
	eq(own("Interface/AddOns/Olympus_ArenaPlus/X.lua:1: other"), false)
	eq(own("Interface/AddOns/Olympus/Core.lua:1: ours"), true)
	eq(own("x", "Interface/AddOns/Olympus/Bootstrap.lua:40: handler\nInterface/AddOns/Other/A.lua:2"), false)
	NoErrors(w)
end)

-- (Refused in Arena.Send itself, through the client's own Moderation.lua: before 1.2's review the
-- slip was taken and held by Comm, and a long one went out as EP pieces, which Comm cannot tell.)
test("1.2 the arena's foundation: Moderation: a net-off client sends none of the arena's calls (EC BS ZD AS AP IL KI KO KN KS), long or not (never as EP pieces), always its own obligations", function()
	local M = H.ns.Moderation
	for _, kind in ipairs({ "EC", "BS", "ZD", "AS", "AP", "IL", "KI", "KO", "KN", "KS" }) do eq(M.BLOCKED[kind], true, kind) end
	for _, kind in ipairs({ "AW", "ZX", "ZR", "ZT", "ZF", "KD" }) do eq(M.BLOCKED[kind], nil, kind) end
	local w = World.New()
	local a = w:Client("Lida Fenn")
	w:Role("bank")
	a.ns.Moderation.SelfOff = function() return true end
	eq(select(2, a.Arena.Send("BS", "T", "slip", { to = N.bank })), "held")
	eq(select(2, a.Arena.Send("AS", "T", ("s"):rep(400), { to = N.bank })), "held", "a long sign-up (its token or IOU)")
	eq(select(2, a.Arena.Send("AP", "T", ("p"):rep(400))), "held", "a long profile")
	eq(select(2, a.Arena.Send("KI", "T", ("k"):rep(300), { to = N.bank })), "held", "a long Farkle invitation")
	eq(select(2, a.Arena.Send("EC", "T", "room~1~wa~hi", { chat = true })), "held")
	eq(a.Arena.Send("ZR", "T", "receipt", { to = N.bank }), true)
	eq(a.Arena.Send("ZX", "T", ("x"):rep(400), { obligation = true }), true, "his own mark with its proof, in pieces")
	w:Run(0)
	eq(Types(w:Sent{ from = a }), "ZR EP EP", "the receipt and the mark went")
	eq(a.Arena.Stats().refused.held, 5)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the status lines: /oly status carries the arena's (ns.statusLines); one that fails says so", function()
	local lines = H.ns.statusLines
	local n = #lines
	table.insert(lines, function(out) out[#out + 1] = "arena test line" end)
	table.insert(lines, function() error("broken line") end)
	local ok, err = pcall(function()
		local text = H.ns.StatusText()
		assert(text:find("arena test line", 1, true), "the line")
		assert(text:find("status line failed", 1, true), "the failure")
		assert(H.ns.BuildBugReport():find("arena test line", 1, true), "and in /oly bug")
	end)
	for i = #lines, n + 1, -1 do lines[i] = nil end
	if not ok then error(err, 0) end
	local w = World.New()
	local a = w:Client("Lida Fenn")
	-- (ArenaNet's comes first: the core loads first; each package may add its own after it, as
	-- Bone Throw's table does with its self-test and tester log.)
	assert(#a.ns.statusLines >= 1, "ArenaNet adds one")
	local out = {}
	w:As(a, a.ns.statusLines[1], out)
	eq(out[1], a.ns.L.ARENA_STATUS_BUILD:format(a.ns.VERSION))
	eq(out[6], a.ns.L.ARENA_STATUS_MEMORY:format(2048, 0, a.ns.L.ARENA_UI_CLOSED))
	NoErrors(w)
end)

test("1.2 the arena's foundation: the week's other rows (Week.providers): shown in order, read-only, a failing provider adds nothing", function()
	local Wk = H.ns.Week
	local n = #Wk.providers
	local now = H.ns.Now()
	table.insert(Wk.providers, function() return { { at = now + 3600, title = "Fight Night: Torvin Hale v Selka Drummond", zone = "Elwynn Forest", tip = "A card of 4" } } end)
	table.insert(Wk.providers, function() error("broken provider") end)
	table.insert(Wk.providers, function() return { { at = "x", title = 5 }, "junk" } end)
	local ok, err = pcall(function()
		local rows = Wk.Provided(now)
		eq(#rows, 1); eq(rows[1].provided, true); eq(rows[1].title, "Fight Night: Torvin Hale v Selka Drummond")
		local lines = {}
		Wk.Section(lines)
		local row
		for _, l in ipairs(lines) do if type(l.text) == "string" and l.text:find("Torvin Hale", 1, true) then row = l end end
		assert(row, "the row on the week")
		for _, l in ipairs(lines) do assert(not (l.indent == 3 and type(l.text) == "string" and l.text:find(H.ns.L.WEEK_CAL_BTN, 1, true)), "no calendar button for it") end
	end)
	for i = #Wk.providers, n + 1, -1 do Wk.providers[i] = nil end
	if not ok then error(err, 0) end
end)

test("1.2 the arena's foundation: Views.Register: another file's tab builder, never a key taken; a failing one shows an empty list", function()
	local V = H.ns.Views
	eq(V.Register("census", function() end), false)
	eq(V.Register("arena-core-test", function(s) return { { text = "a bout" } }, "The Arena", "detail" end), true)
	eq(V.Register("arena-core-test", function() end), false, "taken")
	local lines, title, text = V.Build("arena-core-test")
	eq(lines[1].text, "a bout"); eq(title, "The Arena"); eq(text, "detail")
	local captured = {}
	local ok, err = pcall(H.WithStub, "CaptureError", function(where) captured[#captured + 1] = where end, function()
		eq(V.Register("arena-core-broken", function() error("boom") end), true)
		local l2 = V.Build("arena-core-broken")
		eq(#l2, 0); eq(captured[1], "tab arena-core-broken")
	end)
	-- (Let go: the harness's Views is every test's.)
	eq(V.Unregister("arena-core-test"), true); eq(V.Unregister("arena-core-broken"), true)
	eq(V.Unregister("census"), false, "never a tab of Views.lua's own")
	eq(V.Register("arena-core-test", function() end), true, "free again")
	V.Unregister("arena-core-test")
	if not ok then error(err, 0) end
end)

test("1.2 the arena's foundation: Alts.freezers: a freezer that says so freezes the links as net-off does; one that fails freezes nothing", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local Al = a.Alts
	eq(Al.Frozen(), false)
	local asked
	table.insert(a.ns.Alts.freezers, function(names) asked = names return false end)
	eq(Al.Frozen({ N.bettor2 }), false)
	assert(asked and #asked >= 2, "the names and their groups'")
	table.insert(a.ns.Alts.freezers, function() error("broken") end)
	eq(Al.Frozen(), false)
	table.insert(a.ns.Alts.freezers, function(names)
		for _, n in ipairs(names) do if n == N.bettor2 then return true end end
		return false
	end)
	eq(Al.Frozen({ N.bettor2 }), true, "a linked name with an open mark: frozen"); eq(Al.Frozen(), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation: the Workshop on a test build: never names an unreleased version, 'behind' once the release is out, 't' in the roll-call answer, its line and the sim's button", function()
	local w = World.New()
	local author = w:Role("author", { testBuild = TestBuild(w, { base = H.ns.VERSION }) })
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w, { base = H.ns.VERSION }) })
	local r = w:Client("Lida Fenn")
	eq(r.Workshop.Latest(), r.ns.VERSION, "a release: its own version")
	eq(t.Workshop.Latest(), nil, "a test build: none marked as out")
	t.db.releasedVersion = "1.0.0"
	eq(t.Workshop.Latest(), "1.0.0")
	eq(t.Workshop.Flags():find("t", 1, true) ~= nil, true); eq(r.Workshop.Flags():find("t", 1, true), nil)
	-- The roll call's answer.
	t.ns.Workshop.random = function(a, b) if a then return a end return 0 end
	w:As(author, function() author.ns.Comm.Whisper(t.name, "V1~42~100") end)
	w:As(author, function() author.ns.Comm.Whisper(r.name, "V1~42~100") end)
	r.ns.Workshop.random = t.ns.Workshop.random
	w:Run(60)
	local answers = {}
	for _, s in ipairs(w:Sent{ type = "V2" }) do answers[s.from] = s.msg end
	assert(answers[t.name] and answers[t.name]:match("~t~0~0~$") or answers[t.name]:match("t[^~]*~0~0~$"), tostring(answers[t.name]))
	assert(answers[r.name] and not answers[r.name]:match("t[^~]*~0~0~$"), tostring(answers[r.name]))
	-- Behind: the author's released version is the test's base.
	eq(t.Workshop.Behind(), nil)
	w:As(t, function() t.ns.Workshop.HeardVersion(t.ns.VERSION) end)
	eq(t.Workshop.Behind(), t.ns.VERSION)
	eq(Printed(t, t.ns.L.ARENA_TEST_BEHIND:format(t.ns.VERSION)), 1)
	w:As(r, function() r.ns.Workshop.HeardVersion(r.ns.VERSION) end)
	eq(r.Workshop.Behind(), nil, "a release of that version is not behind")
	-- The Workshop tab's lines: the test build's, and the sim's button.
	local lines = w:As(author, function() return author.ns.Workshop.Build({}) end)
	local sim
	for _, l in ipairs(lines) do if type(l.text) == "string" and l.text:find(author.ns.L.WORKSHOP_ARENA_SIM, 1, true) then sim = l end end
	assert(sim and sim.onClick, "the Arena simulation button")
	local ran
	author.ns.Arena.RunSlash = function(s) ran = s end
	w:As(author, sim.onClick)
	eq(ran, "sim")
	local line
	for _, l in ipairs(lines) do if type(l.text) == "string" and l.text:find("Arena test build 3", 1, true) then line = l end end
	assert(line, "the test build's line on the author's own test build")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the backup: the arena's settings (never 'pub'), the bank's ledger, the key, every copper line, the wallet, stakes and tickets; never the rehearsal, the rules' yes, the checklist or the sentinel", function()
	local w = World.New()
	local a = w:Client("Coffrey Vault")
	w:As(a, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", a.ns) end)
	local B = a.ns.Backup
	local db, r = a.db, a.Arena.Store("L")
	db.arenaOff = true
	db.arenaUI = { delay = 30, alerts = true }
	db.arenaFollow = { ["1abc.00aa11bb"] = "Torvin Hale" }
	db.arenaProfile = { [a.name] = { nick = "a.n", emblem = 134400, pub = true, frame = "rank" } }
	db.arenaKey = { seed = "seedbytes", pk = "pkbytes", at = 5 }
	db.arenaCopper = { c1 = { rid = 4, from = N.bettor1, copper = 10000, how = "t", dir = "in", state = "open" } }
	db.arenaRules = { v = 1, yes = true }
	db.arenaChecklist = { t01 = { s = "p" } }
	r.bank = { epoch = 3, secret = "banksecret", kb = "blindkey", seq = 12 }
	r.mine = { [a.name] = { banks = { [N.bank] = { code = "k1" } } } }
	r.stakes = { { id = "F1", copper = 50000 } }
	r.tickets = { [a.name] = { { eid = "F1", o = "A" } } }
	a.rdb.arenaTest = { rid = 4, director = N.arbiter }
	local d = w:As(a, B.Data)
	eq(d.settings.arenaOff, true)
	eq(d.arenaSettings.ui.delay, 30); eq(d.arenaSettings.follow["1abc.00aa11bb"], "Torvin Hale")
	eq(d.arenaSettings.profile[a.name].nick, "a.n"); eq(d.arenaSettings.profile[a.name].pub, nil, "never pub")
	-- 1.2.0: never the key nor the bank's secret (a key restored from a text could be its writer's).
	eq(d.arena.bank.secret, nil); eq(d.arena.bank.kb, nil); eq(d.arena.bank.seq, 12); eq(d.arena.key, nil); eq(d.arena.copper.c1.state, "open")
	eq(d.arena.mine.banks[N.bank].code, "k1"); eq(d.arena.stakes[1].id, "F1"); eq(d.arena.tickets[1].o, "A")
	eq(B.HoldsKey(d), false)
	local text = w:As(a, B.Export)
	assert(not text:find("pkbytes", 1, true) and not text:find("banksecret", 1, true) and not text:find("blindkey", 1, true))
	-- A text that carries them anyway (an older export, or written to plant a key): never taken.
	local data = B.Data
	B.Data = function() local x = data(); x.arena.key = { pk = "planted" }; x.arena.bank.secret = "planted"; return x end
	local planted = w:As(a, B.Export)
	B.Data = data
	for _, never in ipairs({ "arenaTest", "arenaRules", "arenaChecklist", "arenaSaved", "director" }) do
		assert(not text:find(never, 1, true), "the backup holds " .. never)
	end
	-- Read back on another realm of the group: the account's parts (the key, the copper lines) come
	-- back, the realm's (the ledger, the wallet, stakes, tickets) stay that realm's, and the confirm
	-- says so. (Before the review nothing came back there, the key and the copper lines neither.)
	local b = w:Client("Coffrey Vault", { realm = "Emberfall2" })
	w:As(b, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", b.ns) end)
	local other = w:As(b, b.ns.Backup.Read, text)
	eq(type(other), "table"); eq(other.arena.key, nil); eq(other.arena.copper.c1.state, "open")
	eq(other.arena.bank, nil, "another realm's ledger is not this realm's"); eq(other.arena.mine, nil); eq(other.arena.stakes, nil); eq(other.arena.tickets, nil)
	eq(other.arenaElsewhere, "Emberfall")
	local said = table.concat(w:As(b, b.ns.Backup.Summary, other), "\n")
	assert(said:find(b.ns.L.BACKUP_ARENA_ELSEWHERE:format("Emberfall"), 1, true), said)
	-- On the same character's fresh install: each part only where none is held, copper lines added.
	local w2 = World.New()
	local c = w2:Client("Coffrey Vault")
	w2:As(c, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", c.ns) end)
	c.db.arenaKey = { pk = "held here" }
	c.db.arenaCopper = { c0 = { state = "open" } }
	c.db.arenaProfile = { [c.name] = { nick = "x.y" } }
	local back = w2:As(c, c.ns.Backup.Read, planted)
	eq(type(back.arena), "table"); eq(back.arena.bank.secret, nil, "a planted secret is dropped"); eq(back.arena.key, nil, "a planted key is dropped")
	c.ns.UI = {} -- (the windows are not the point here)
	w2:As(c, c.ns.Backup.Apply, back)
	local r2 = c.Arena.Store("L")
	eq(c.db.arenaKey.pk, "held here", "a key held here is never replaced")
	eq(w2:As(c, c.ns.Backup.ApplyArena, { key = { pk = "planted" } }) and c.db.arenaKey.pk, "held here")
	c.db.arenaKey = nil
	w2:As(c, c.ns.Backup.ApplyArena, { key = { pk = "planted" } })
	eq(c.db.arenaKey, nil, "nor planted where none is held")
	eq(r2.bank.secret, nil); eq(r2.bank.seq, 12); eq(c.db.arenaCopper.c0.state, "open"); eq(c.db.arenaCopper.c1.copper, 10000)
	eq(r2.mine[c.name].banks[N.bank].code, "k1"); eq(r2.tickets[c.name][1].o, "A"); eq(r2.stakes[1].id, "F1")
	eq(c.db.arenaOff, true); eq(c.db.arenaUI.delay, 30); eq(c.db.arenaFollow["1abc.00aa11bb"], "Torvin Hale")
	eq(c.db.arenaProfile[c.name].nick, "a.n"); eq(c.db.arenaProfile[c.name].pub, nil, "a text never turns sharing on")
	eq(c.db.arenaRules, nil); eq(c.rdb.arenaTest, nil)
	-- A part that is no plain data is left out (Backup.Plain).
	eq(c.ns.Backup.Plain({ x = "a|b" }, { n = 10 }), nil); eq(c.ns.Backup.Plain({ x = 0 / 0 }, { n = 10 }), nil)
	eq(c.ns.Backup.Plain({ x = { y = "ok" } }, { n = 10 }).x.y, "ok"); eq(c.ns.Backup.Plain({ 1, 2, 3 }, { n = 2 }), nil, "the budget")
	NoErrors(w)
	NoErrors(w2)
end)

print("Comm.lua: done on Send, the hello's bank flag")

-- Comm.lua itself in a namespace of its own (fresh queue, peers and stats), the game's
-- SendAddonMessage answering with the results the test gives (Enum.SendAddonMessageResult).
local function RealComm(fn)
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = H.ns })
	cns.RegisterEvent = function(event, f) events[event] = events[event] or {}; table.insert(events[event], f) end
	cns.On = function(name, f) if name == "LOGIN" then table.insert(login, f) end end
	cns.After, cns.Every, cns.Log = function() end, function() end, function() end
	cns.clock = 100000
	cns.Now = function() return cns.clock end
	local results, sent = {}, {}
	local saved = { C_ChatInfo = C_ChatInfo, IsInGuild = IsInGuild, GetGuildInfo = GetGuildInfo }
	local function Send(prefix, msg, dist, target)
		local r = table.remove(results, 1) or 0
		sent[#sent + 1] = { msg = msg, dist = dist, target = target, result = r }
		return r
	end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send }
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		for _, f in ipairs(login) do f() end
		local function Deliver(dist, sender, text)
			for _, f in ipairs(events.CHAT_MSG_ADDON) do f(H.ns.PREFIX, text, dist, sender) end
		end
		fn(cns.Comm, cns, results, sent, Deliver)
	end)
	C_ChatInfo, IsInGuild, GetGuildInfo = saved.C_ChatInfo, saved.IsInGuild, saved.GetGuildInfo
	if not ok then error(err, 0) end
end

test("1.2 the arena's foundation: Comm.Send passes done: results 3, 8, 11 and 12 fire done(false, result), success done(true); refused before the queue, at once with why", function()
	RealComm(function(C, cns, results, sent)
		local done = {}
		local function D(tag) return function(ok, why) done[#done + 1] = tag .. ":" .. tostring(ok) .. ":" .. tostring(why) end end
		for i = 1, 3 do C.Send("GUILD", "ZZ~" .. i, nil, false, false, D("g" .. i)) end
		C.Whisper("Nobody-Realm", "ZZ~w", nil, false, false, D("w"))
		C.Send("GUILD", "ZZ~ok", "k", true, false, D("ok"))
		-- The game's answers, in the order they leave (the urgent one first).
		for _, r in ipairs({ 0, 3, 8, 11, 12 }) do results[#results + 1] = r end
		for _ = 1, 6 do C.Pump() end
		eq(table.concat(done, ","), "ok:true:nil,g1:false:3,g2:false:8,g3:false:11,w:false:12", "urgent first")
		-- Refused before the queue: done at once.
		done = {}
		C.Whisper("", "ZZ~x", nil, false, false, D("target"))
		IsInGuild = function() return false end
		C.Send("GUILD", "ZZ~x", nil, false, false, D("guild"))
		IsInGuild = function() return true end
		eq(table.concat(done, ","), "target:false:target,guild:false:guild")
		-- A full queue drops its oldest ordinary message: done(false, "dropped").
		done = {}
		for i = 1, 61 do C.Send("GUILD", "ZZ~" .. i, nil, false, false, D("q" .. i)) end
		eq(done[1], "q1:false:dropped")
		-- Out of an Olympus guild: everything waiting goes, "left".
		GetGuildInfo = function() return "Not Ours" end
		C.Pump()
		eq(#done, 61); eq(done[61], "q61:false:left")
		-- The key still replaces the waiting message and its done (Comm.lua's dedupe), done kept when none given.
		GetGuildInfo = function() return "Olympus II" end
		done = {}
		C.Send("GUILD", "ZZ~a", "same", false, false, D("a"))
		C.Send("GUILD", "ZZ~b", "same", false, false, D("b"))
		C.Send("GUILD", "ZZ~c", "same")
		C.Pump()
		eq(sent[#sent].msg, "ZZ~c"); eq(table.concat(done, ","), "b:true:nil")
	end)
end)

test("1.2 the arena's foundation: the hello's sixth field says an arena bank on duty; guildmates leave it out of the census election, and a bank never reports", function()
	RealComm(function(C, cns, results, sent, Deliver)
		cns.me = "Zed-Realm"
		local duty = false
		cns.Arena = { OnDuty = function(role) return role == "bank" and duty end }
		C.Hello(true); C.Pump()
		assert(not sent[#sent].msg:find("~b$"), sent[#sent].msg)
		duty = true
		C.Hello(true); C.Pump()
		assert(sent[#sent].msg:find("^H1~[^~]*~[^~]*~[^~]*~[^~]*~b$"), sent[#sent].msg)
		duty = false
		-- Guildmates: a bank (first by name) and another.
		Deliver("GUILD", "Abank-Realm", "H1~1.2.0~Realm~p~~b")
		Deliver("GUILD", "Bob-Realm", "H1~1.2.0~Realm~p~")
		C.MaybeBroadcast({ guild = "Olympus II" })
		eq(C.reporterName, "Bob", "the bank is left out")
		-- The same peer's hello without the flag: electable again.
		Deliver("GUILD", "Abank-Realm", "H1~1.2.0~Realm~p~")
		C.MaybeBroadcast({ guild = "Olympus II" })
		eq(C.reporterName, "Abank")
		-- A 1.1 hello (five fields) reads as before.
		Deliver("GUILD", "Abank-Realm", "H1~1.1.1~Realm~p~z")
		C.MaybeBroadcast({ guild = "Olympus II" })
		eq(C.reporterName, "Abank"); eq(C.SharesZone("Abank-Realm"), true)
		-- A bank on duty never reports, even alone.
		duty = true
		C.MaybeBroadcast({ guild = "Olympus II" })
		eq(C.isReporter, false); eq(C.isRunnerUp, false)
		eq(C.BankOnDuty(), true)
	end)
end)

test("1.2 the arena's foundation: Arena.SetDuty('bank') says hello at once with the flag; the world's clients keep their books apart (the world's self-test)", function()
	local w = World.New()
	local bank = w:Role("bank")
	bank.Arena.SetDuty("bank", true)
	eq(bank.comm.hellos, 1); eq(bank.Comm.BankOnDuty(), true); eq(bank.Arena.OnDuty("bank"), true)
	eq(table.concat(bank.Arena.Involved(), ","), "duty:bank")
	bank.Arena.SetDuty("bank", false)
	eq(bank.comm.hellos, 2); eq(#bank.Arena.Involved(), 0)
	-- Two treasury keepers record different gifts: each book holds its own.
	local keeper, mail = w:Role("treasurer"), w:Role("treasurerMail")
	local d1, d2 = w:Client("Lida Fenn", { money = 100000 }), w:Client("Parric Stowe", { money = 100000 })
	w:Run(10)
	w:Trade(d1, keeper, { aGives = 5000 })
	w:Trade(d2, mail, { aGives = 7000 })
	local b1 = w:As(keeper, keeper.ns.Treasury.Book)
	local b2 = w:As(mail, mail.ns.Treasury.Book)
	eq(#b1.lines, 1); eq(b1.lines[1].money, 5000); eq(b1.lines[1].name, "Lida Fenn")
	eq(#b2.lines, 1); eq(b2.lines[1].money, 7000); eq(b2.lines[1].name, "Parric Stowe")
	eq(d1.money, 95000); eq(keeper.money, 5000)
	assert(keeper.rdb ~= mail.rdb and keeper.db ~= mail.db, "saved data apart")
	NoErrors(w)
end)

test("1.2 the arena's foundation: the world's mail: sent with the sender's hooks and its postage, taken with PLAYER_MONEY, returned marked; a keeper's book takes it as the game would give it", function()
	local w = World.New()
	local keeper = w:Role("treasurerMail")
	local d = w:Client("Wenna Crale", { money = 50000 })
	w:Run(10)
	local sentHook
	w:As(d, function() hooksecurefunc("SendMail", function(to, subject) sentHook = to .. "|" .. subject end) end)
	local i = w:Mail(d, keeper, 20000, "For the treasury")
	eq(i, 1); eq(sentHook, keeper.name .. "|For the treasury")
	eq(d.money, 50000 - 20000 - World.POSTAGE)
	local header = { w:As(keeper, function() return GetInboxHeaderInfo(1) end) }
	eq(header[3], "Wenna Crale"); eq(header[4], "For the treasury"); eq(header[5], 20000); eq(header[10], false)
	w:Take(keeper, 1)
	eq(keeper.money, 20000); eq(keeper.inbox[1].money, 0)
	local book = w:As(keeper, keeper.ns.Treasury.Book)
	eq(#book.lines, 1); eq(book.lines[1].money, 20000); eq(book.lines[1].how, "mail")
	-- Returned: back in the sender's box, marked returned.
	w:Mail(d, keeper, 1000, "Oops")
	w:Return(keeper, 2)
	eq(#keeper.inbox, 1); eq(d.inbox[1].returned, true); eq(d.inbox[1].money, 1000)
	eq(select(10, w:As(d, function() return GetInboxHeaderInfo(1) end)), true)
	NoErrors(w)
end)

print("the arena's foundation review: the send path")

test("1.2 the arena's foundation review: a must-deliver payload in pieces whose second piece the game keeps refusing arrives whole (that piece again under the same id, then the whole under a new one), and its done says so only then", function()
	local w = World.New()
	local bank, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "BO")
	local body = Long("BO", "T", 2, "p")
	local done = {}
	local t0 = w.clock
	w:Results(bank, { 0, 3, 3, 3, 3, 3, 3 })
	eq(bank.Arena.Send("BO", "T", body, { urgent = true, must = true, done = function(sent, why) done[#done + 1] = { sent, why, w.clock - t0 } end }), true)
	w:Run(0)
	eq(#got, 0); eq(#done, 0, "the first piece left, the second was refused")
	w:Run(200)
	eq(#w.failed, 6)
	eq(#got, 1, "put together once"); eq(got[1].body, body)
	eq(#done, 1); eq(done[1][1], true)
	assert(done[1][3] < bank.ns.Arena.PIECE_TTL, "sent in the receivers' time: " .. done[1][3])
	eq(b.Arena.Stats().assembled, 1)
	-- An ordinary one: its done says why the first refused piece was not sent, once.
	local told = {}
	w:Results(bank, { 0, 3 })
	bank.Arena.Send("BO", "T", Long("BO", "T", 3, "q"), { done = function(sent, why) told[#told + 1] = tostring(sent) .. ":" .. tostring(why) end })
	w:Run(60)
	eq(table.concat(told, ","), "false:3"); eq(#got, 1)
	eq(bank.Arena.Ticking(), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: six keyed long payloads from one sender at once go one after another (a producer keeps its turn to its last piece): a receiver puts all six together", function()
	local w = World.New({ paced = true })
	local bank, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "BO")
	local fills = { "a", "b", "c", "d", "e", "f" }
	for i, f in ipairs(fills) do eq(bank.Arena.Send("BO", "T", Long("BO", "T", 3, f), { key = "bo e" .. i }), true) end
	eq(bank.Arena.ProducerCount(), 6)
	w:Run(120)
	eq(#got, 6)
	local bodies = {}
	for _, g in ipairs(got) do bodies[g.body:sub(1, 1)] = g.body end
	for _, f in ipairs(fills) do eq(bodies[f], Long("BO", "T", 3, f), f) end
	eq(b.Arena.Stats().dropped["pieces-open"], nil)
	local pids = {}
	for _, s in ipairs(w:Sent{ from = bank, type = "EP" }) do pids[#pids + 1] = s.msg:match("^EP~T1~([^~]+)~") end
	eq(#pids, 18)
	for i = 1, 18, 3 do eq(pids[i] == pids[i + 1] and pids[i] == pids[i + 2], true, "payload " .. i .. "'s pieces together") end
	eq(bank.Arena.ProducerCount(), 0)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: a must-deliver whisper to a target offline (result 12) waits for him, and goes when he is heard again or a probe gets through; his ordinary whispers are dropped; given up after PARK_TRIES", function()
	local w = World.New()
	local fee = w:Role("treasurerMail")
	local p, q = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local heard = Catch(fee, "AF")
	w:Logout(p); w:Logout(q)
	local told = {}
	local function D(tag) return function(sent, why) told[#told + 1] = tag .. "=" .. tostring(sent) .. ":" .. tostring(why) end end
	eq(fee.Arena.Send("ZF", "T", "receipt 1", { to = p.name, must = true, done = D("zf1") }), true)
	w:Run(0)
	eq(fee.Arena.ParkedSize(p.name), 1, "parked"); eq(#told, 0, "not given up")
	fee.Arena.Send("ZK", "T", "ordinary", { to = p.name, done = D("zk") })
	eq(told[1], "zk=false:12", "an ordinary whisper to him is dropped")
	fee.Arena.Send("ZF", "T", "receipt 2", { to = p.name, must = true, done = D("zf2") })
	eq(fee.Arena.ParkedSize(p.name), 2)
	-- He logs in and says anything: both go, in their order.
	w:Login(p)
	local zf = Catch(p, "ZF")
	w:Run(10)
	eq(#zf, 0, "the first probe is a minute after")
	p.Arena.Send("AF", "T", "back", { to = fee.name })
	w:Run(0)
	eq(#heard, 1)
	eq(#zf, 2); eq(zf[1].body, "receipt 1"); eq(zf[2].body, "receipt 2")
	eq(table.concat(told, ","), "zk=false:12,zf1=true:nil,zf2=true:nil")
	eq(fee.Arena.ParkedSize(), 0)
	-- q logs in and says nothing: the probe a minute after the park gets through.
	told = {}
	fee.Arena.Send("ZF", "T", "receipt 3", { to = q.name, must = true, done = D("zf3") })
	w:Run(0)
	eq(fee.Arena.ParkedSize(q.name), 1)
	w:Login(q)
	local zq = Catch(q, "ZF")
	w:Run(55)
	eq(#zq, 0)
	w:Run(10)
	eq(#zq, 1); eq(told[1], "zf3=true:nil")
	-- Never back: given up after PARK_TRIES probes (60, 120 and 300 s apart), told 12.
	fee.ns.Arena.PARK_TRIES = 2
	told = {}
	fee.Arena.Send("ZF", "T", "receipt 4", { to = "Nobody Here-Emberfall", must = true, done = D("zf4") })
	w:Run(0)
	w:Run(479)
	eq(#told, 0)
	w:Run(2)
	eq(told[1], "zf4=false:12"); eq(fee.Arena.ParkedSize(), 0)
	eq(fee.Arena.Ticking(), false)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: a must-deliver whisper long enough for pieces, to a target offline, is parked whole and goes again in new pieces once he is back", function()
	local w = World.New()
	local a, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	w:Logout(b)
	local long = Long("ZR", "T", 2, "z")
	local told
	a.Arena.Send("ZR", "T", long, { to = b.name, must = true, done = function(sent, why) told = tostring(sent) .. ":" .. tostring(why) end })
	w:Run(0)
	eq(a.Arena.ParkedSize(b.name), 1); eq(told, nil)
	w:Login(b)
	local got = Catch(b, "ZR")
	w:Run(61)
	eq(#got, 1); eq(got[1].body, long); eq(told, "true:nil")
	for _, s in ipairs(w:Sent{ from = a }) do assert(#s.msg <= 255, "every message the game's size: " .. #s.msg) end
	NoErrors(w)
end)

test("1.2 the arena's foundation review: the server's not-found line parks a must-deliver whisper still waiting (never drops it); it goes once a whisper to the target leaves", function()
	local w = World.New({ paced = true })
	local a, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local got = Catch(b, "ZR")
	local told = {}
	for i = 1, 2 do a.Arena.Send("ZR", "T", "r" .. i, { to = b.name, must = true, done = function(sent) told[#told + 1] = tostring(sent) end }) end
	eq(a.Arena.OutboxSize(b.name), 2)
	w:System(a, "No player named 'Parric Stowe' is currently playing.")
	eq(a.Arena.OutboxSize(b.name), 1, "the one handed to Comm"); eq(a.Arena.ParkedSize(b.name), 1, "the other parked"); eq(#told, 0)
	w:Run(10)
	eq(#got, 2); eq(got[2].body, "r2"); eq(table.concat(told, ","), "true,true")
	NoErrors(w)
end)

test("1.2 the arena's foundation review: the kill switch drops what waits but a player's own obligations (a signed AW, his ZX, a receipt in pieces), each dropped one told why; the other packages' producers wait, then go on", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local aw, zx, zr, af, ae = Catch(b, "AW"), Catch(b, "ZX"), Catch(b, "ZR"), Catch(b, "AF"), Catch(b, "AE")
	local told = {}
	local function D(tag) return function(sent, why) told[tag] = tostring(sent) .. ":" .. tostring(why) end end
	-- A must-deliver entry refused once: waiting to be offered again.
	w:Results(a, { 3 })
	a.Arena.Send("AE", "T", "entry", { must = true, done = D("AE") })
	w:Run(0)
	eq(a.Arena.RetrySize(), 1)
	w:Lockdown(a, true)
	a.Arena.Send("AW", "T", "signed result", { to = b.name, obligation = true, done = D("AW") })
	a.Arena.Send("ZX", "T", "self mark", { obligation = true, done = D("ZX") })
	local long = Long("ZR", "T", 2, "r")
	a.Arena.Send("ZR", "T", long, { to = b.name, done = D("ZR") })
	a.Arena.Send("AF", "T", "ordinary", { done = D("AF") })
	eq(a.Arena.BacklogSize(), 5, "AW, ZX, the receipt's two pieces, AF")
	local calls = 0
	a.Arena.Later("clerk", function() calls = calls + 1 return "AB", "T", "carousel " .. calls end)
	a.ns.Debts.Open = function() return {} end
	eq(a.Arena.SetOff(true), true)
	eq(told.AF, "false:off"); eq(told.AE, "false:off", "a retry dropped is told"); eq(a.Arena.RetrySize(), 0)
	eq(told.AW, nil); eq(told.ZX, nil); eq(told.ZR, nil)
	eq(a.Arena.BacklogSize(), 4)
	eq(a.Arena.ProducerCount(), 1, "another package's producer stays")
	w:Lockdown(a, false)
	w:Run(5)
	eq(#aw, 1); eq(#zx, 1); eq(#zr, 1); eq(zr[1].body, long); eq(#af, 0); eq(#ae, 0)
	eq(told.AW, "true:nil"); eq(told.ZX, "true:nil"); eq(told.ZR, "true:nil")
	eq(calls, 0, "it waits while the arena is off")
	a.Arena.SetOff(false)
	w:Run(3)
	assert(calls > 0, "and goes on after")
	a.Arena.Later("clerk", nil)
	-- The sim drops the same way, told "sim".
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	w:Group({ t, b })
	w:Lockdown(t, true)
	t.Arena.Send("AF", "T", "rehearsal", { done = D("sim") })
	eq(t.Arena.SetSim(true), true)
	eq(told.sim, "false:sim")
	t.Arena.SetSim(false)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: a fight-room line (o.chat) typed while blocked is dropped at once, told why, never sent late", function()
	local w = World.New()
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	local got = Catch(b, "EC")
	local told = {}
	local function D(sent, why) told[#told + 1] = tostring(sent) .. ":" .. tostring(why) end
	w:Lockdown(a, true)
	eq(a.Arena.Send("EC", "T", "room~1~wa~hello", { chat = true, done = D }), true)
	eq(a.Arena.Send("EC", "T", "room~2~wa~psst", { chat = true, to = b.name, logged = true, done = D }), true)
	eq(table.concat(told, ","), "false:lockdown,false:lockdown"); eq(a.Arena.BacklogSize(), 0)
	w:Run(3600)
	w:Lockdown(a, false)
	w:Run(5)
	eq(#got, 0); eq(#w:Sent{ from = a, type = "EC" }, 0)
	-- In an instance too; out of it, a line goes on the chat lane.
	a.instance = true
	a.Arena.Send("EC", "T", "room~3~wa~inside", { chat = true, done = D })
	eq(told[3], "false:lockdown")
	a.instance = nil
	a.Arena.Send("EC", "T", "room~4~wa~outside", { chat = true })
	w:Run(0)
	eq(#got, 1); eq(got[1].body, "room~4~wa~outside")
	NoErrors(w)
end)

test("1.2 the arena's foundation review: a state word sent even while blocked (o.evenBlocked: a bank's ZH p) goes from an instance, never in chat lockdown; the rest waits", function()
	local w = World.New()
	local bank, b = w:Client("Coffrey Vault"), w:Client("Parric Stowe")
	local zh, af = Catch(b, "ZH"), Catch(b, "AF")
	bank.instance = true
	eq(bank.Arena.Blocked(), true); eq(bank.Arena.Lockdown(), false); eq(bank.Arena.InInstance(), true)
	bank.Arena.Send("ZH", "T", "1~2~mac~head~p~-~fp~s", { evenBlocked = true })
	bank.Arena.Send("AF", "T", "waits")
	w:Run(0)
	eq(#zh, 1, "from the instance"); eq(#af, 0); eq(bank.Arena.BacklogSize(), 1)
	w:Lockdown(bank, true)
	bank.Arena.Send("ZH", "T", "1~3~mac~head~p~-~fp~s", { evenBlocked = true })
	w:Run(2)
	eq(#zh, 1, "never in chat lockdown")
	w:Lockdown(bank, false)
	w:Run(2)
	eq(#zh, 2, "once it is over"); eq(#af, 0, "still in the instance")
	bank.instance = nil
	w:Run(2)
	eq(#af, 1)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: /oly arena sim loads the companion first, then turns the sim on and opens it (the first click too); refused in combat, the sim stays off", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	local opened = {}
	t.ns.On("ARENA_UI_LOADED", function() t.ns.Arena.ui.Sim = function(args) opened[#opened + 1] = args end end)
	w:As(t, function() t.slashes.OLYMPUS("arena sim") end)
	eq(#opened, 1, "the first click opens it"); eq(t.Arena.Sim(), true); eq(t.companion.loaded, true)
	w:As(t, function() t.slashes.OLYMPUS("arena sim off") end)
	eq(t.Arena.Sim(), false)
	local u = w:Client("Lida Fenn", { testBuild = TestBuild(w) })
	w:Combat(u, true)
	w:As(u, function() u.slashes.OLYMPUS("arena sim") end)
	eq(u.Arena.Sim(), false, "no window: no sim"); eq(Printed(u, u.ns.L.ARENA_UI_COMBAT), 1)
	w:Group({ u, t })
	eq(u.Arena.Send("AF", "T", "x"), true, "its sends are not refused as the sim's")
	-- Someone who may not run it: told so, and the companion stays unloaded.
	local r = w:Client("Parric Stowe")
	w:As(r, function() r.slashes.OLYMPUS("arena sim") end)
	eq(Printed(r, r.ns.L.ARENA_SIM_REFUSED), 1); eq(r.companion.loaded, nil)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: the limits: a full backlog drops an ordinary message (told why) and brings a must-deliver one back later; 20 retries at most; the low lane's cap; the signature queue's; a handler that fails is caught", function()
	local w = World.New()
	local a, b = w:Client("Oswin Marrow"), w:Client("Parric Stowe")
	local af, ae = Catch(b, "AF"), Catch(b, "AE")
	local told = {}
	local function D(tag) return function(sent, why) told[tag] = tostring(sent) .. ":" .. tostring(why) end end
	-- BACKLOG_MAX (a client's own table: the world's clients never share it)
	a.ns.Arena.BACKLOG_MAX = 2
	w:Lockdown(a, true)
	a.Arena.Send("AF", "T", "one"); a.Arena.Send("AF", "T", "two")
	a.Arena.Send("AF", "T", "three", { done = D("three") })
	eq(told.three, "false:backlog"); eq(a.Arena.Stats().dropped.backlog, 1)
	a.Arena.Send("AE", "T", "entry", { must = true, done = D("entry") })
	eq(told.entry, nil); eq(a.Arena.RetrySize(), 1)
	w:Lockdown(a, false)
	w:Run(10)
	eq(#af, 2); eq(#ae, 1); eq(told.entry, "true:nil")
	-- RETRIES_MAX: refused 21 times, given up with the last result.
	local results = {}
	for i = 1, 21 do results[i] = 3 end
	w:Results(a, results)
	a.Arena.Send("AE", "T", "throttled", { must = true, done = D("throttled") })
	w:Run(900)
	eq(told.throttled, nil, "still trying")
	w:Run(200)
	eq(told.throttled, "false:3"); eq(a.Arena.Stats().dropped.retries, 1); eq(#ae, 1)
	-- LOW_MAX
	a.ns.Arena.LOW_MAX = 2
	a.Arena.Send("AF", "T", "low 1", { low = true }); a.Arena.Send("AF", "T", "low 2", { low = true })
	a.Arena.Send("AF", "T", "low 3", { low = true, done = D("low") })
	eq(told.low, "false:low")
	w:Run(5)
	eq(af[#af].body, "low 2")
	-- VERIFY_QUEUE: full, a claim is refused at once.
	a.ns.Arena.VERIFY_QUEUE = 1
	local Ed = a.ns.Ed25519
	local busy = Ed.Busy
	Ed.Busy = function() return 40 end
	local answers = {}
	local function Cb(ok) answers[#answers + 1] = tostring(ok) end
	eq(a.Arena.Verify(N.fighterA, { pk = ("\1"):rep(32), msg = "m", sig = ("\2"):rep(64), key = "k1" }, Cb), nil)
	eq(a.Arena.Verify(N.fighterB, { pk = ("\1"):rep(32), msg = "m", sig = ("\2"):rep(64), key = "k2" }, Cb), false)
	eq(table.concat(answers, ","), "false"); eq(a.Arena.VerifyQueue(), 1)
	Ed.Busy = busy
	w:Run(5)
	eq(a.Arena.VerifyQueue(), 0); eq(#answers, 2)
	-- A handler that fails: caught (and kept), the next message handled.
	b.ns.Comm.Handle("AC", b.ns.Arena.Handle("AC", function() error("broken handler") end))
	a.Arena.Send("AC", "T", "x", { to = b.name })
	a.Arena.Send("AF", "T", "after")
	w:Run(0)
	eq(#b.errors, 1); assert(b.errors[1]:find("arena AC", 1, true), b.errors[1])
	eq(af[#af].body, "after")
	wipe(b.errors)
	NoErrors(w)
end)

print("the arena's foundation review: the King's words, the backup, the login line")

test("1.2 the arena's foundation review: a test build gives no King's word and repeats none (never on the channel, never live): his settings, banks, arbiters and delay stay his client's", function()
	local w = World.New()
	local king = w:Role("king", { testBuild = TestBuild(w) })
	local r = w:Client("Lida Fenn")
	local function Words()
		local n = 0
		for _, s in ipairs(w:Sent{ from = king }) do if s.msg:find("^T1~") then n = n + 1 end end
		return n
	end
	eq(select(2, king.Roles.SetSettings({ live = 1 })), "test-channel")
	eq(select(2, king.Roles.SetBanks({ N.bank })), "test-channel")
	eq(select(2, king.Roles.SetArbiters({ { name = N.fighterA, cap = 200 } })), "test-channel")
	eq(king.Arena.SetDelay(60), true, "kept for his own view")
	eq(select(2, king.Roles.SendDelay(60)), "test-channel")
	king.Roles.Repeat()
	w:Run(700)
	eq(Words(), 0); eq(r.Roles.Live(), false); eq(r.Roles.KingDelay(), 0); eq(#r.Roles.Banks("L"), 0)
	eq(king.Roles.Live(), false, "his own client took nothing either")
	-- A test-build Steward who hears an older word answers nothing.
	local w2 = World.New()
	local king2 = w2:Role("king")
	local steward = w2:Role("steward", { testBuild = TestBuild(w2) })
	eq(king2.Roles.SetBanks({ N.bank }), true)
	w2:Run(0)
	eq(steward.Roles.Banks("L")[1].name, N.bank, "it hears the words")
	Word(w2, king2, "B", N.bettor1 .. ":o", w2.clock - 100)
	eq(#w2:Sent{ from = steward }, 0)
	NoErrors(w)
	NoErrors(w2)
end)

test("1.2 the arena's foundation review: the King's delay goes on after he logs in again (repeated every 5 minutes, the first a minute after login), and is published again from what he typed when the word was lost", function()
	local w = World.New()
	local king, b = w:Role("king"), w:Client("Lida Fenn")
	king.Arena.SetDelay(120)
	w:Run(0)
	eq(b.Roles.KingDelay(), 120)
	w:Logout(king)
	w:Login(king)
	w:Run(700)
	eq(b.Roles.KingDelay(), 120, "still his, 700 s after he came back")
	-- Gone long enough to lapse, and the word lost from his saved data: published again.
	w:Logout(king)
	w:Run(1000)
	eq(b.Roles.KingDelay(), 0, "lapsed")
	king.saved.db.realms[World.GROUP].arena.realms.Emberfall.roles.kingDelay = nil
	w:Login(king)
	w:Run(61)
	eq(b.Roles.KingDelay(), 120)
	-- Off: nothing repeated.
	king.Arena.SetDelay("off")
	w:Run(0)
	eq(b.Roles.KingDelay(), 0)
	w:Logout(king)
	w:Login(king)
	eq(table.concat(king.Arena.Involved(), ","), "", "nothing to repeat")
	NoErrors(w)
end)

test("1.2 the arena's foundation review: the backup at the design's caps (a bank of 5,000 accounts and 5,000 entries) keeps the copper lines and the ledger (1.2.0: never the key nor the bank's secret); a part its owner's check refuses, or whose check fails, is left out and named; the copy box shows what Export writes", function()
	local w = World.New()
	local a = w:Client("Coffrey Vault")
	w:As(a, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", a.ns) end)
	local A = a.ns.Arena
	local r = a.Arena.Store("L")
	local accounts, entries = {}, {}
	for i = 1, 5000 do
		accounts["c" .. A.B36(i)] = { g = { bal = 1000 * i, reserved = 0, escrow = 0 }, p = { bal = 1000, escrow = 0 }, guid = ("Player-4395-%08X"):format(i),
			bound = true, keyFp = "a1b2c3d4" }
		entries[i] = ("b:%s:c%s:+:%s"):format(A.B36(i), A.B36(i), A.B36(1000 * i))
	end
	r.bank = { epoch = 3, secret = "banksecret", kb = "blindkey", seq = 5000, accounts = accounts, entries = entries }
	a.db.arenaKey = { seed = "seedbytes", pk = "pkbytes", at = 5 }
	a.db.arenaCopper = { c1 = { rid = 4, copper = 10000, state = "open" } }
	r.stakes = { { id = "F1", copper = 50000 } }
	r.tickets = { [a.name] = { { eid = "F1", o = "A" } } }
	local text = w:As(a, a.ns.Backup.Export)
	assert(#text <= a.ns.Backup.MAX, "a bank at the caps fits a backup: " .. #text)
	-- A fresh install of the same character, whose stakes' and tickets' owners check them.
	local w2 = World.New()
	local c = w2:Client("Coffrey Vault")
	w2:As(c, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", c.ns) end)
	local B = c.ns.Backup
	B.arenaChecks.stakes = function() return nil end
	B.arenaChecks.tickets = function() error("a check that fails") end
	local back = w2:As(c, B.Read, text)
	eq(back.arena.key, nil, "1.2.0: never the key"); eq(back.arena.copper.c1.copper, 10000)
	local n = 0
	for _ in pairs(back.arena.bank.accounts) do n = n + 1 end
	eq(n, 5000); eq(#back.arena.bank.entries, 5000); eq(back.arena.bank.secret, nil, "nor the bank's secret")
	eq(back.arena.stakes, nil); eq(back.arena.tickets, nil)
	eq(table.concat(back.arenaFailed, ","), "stakes,tickets")
	local L2 = c.ns.L
	local summary = table.concat(w2:As(c, B.Summary, back), "\n")
	assert(summary:find(L2.BACKUP_ARENA_FAILED:format(L2.BACKUP_ARENA_STAKES .. ", " .. L2.BACKUP_ARENA_TICKETS), 1, true), summary)
	-- The copy box: Export's text; the key held here never goes in it, so no key warning.
	local shown
	c.ns.UI = { ShowCopy = function(title, t) shown = { title = title, text = t } end }
	c.db.arenaKey = { pk = "held here" }
	w2:As(c, B.ShowExport)
	eq(shown.text, w2:As(c, B.Export))
	assert(not shown.text:find("held here", 1, true), "the key is not in it")
	eq(shown.title, L2.BACKUP_TITLE, "no key in it: no warning"); eq(Printed(c, L2.BACKUP_ARENA_KEY_WARNING), 0)
	NoErrors(w)
	NoErrors(w2)
end)

test("1.2 the arena's foundation review: a client without ArenaNet.lua (updated without a restart) names that file at login, never 'Arena.lua'", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local dispatch
	for _, f in ipairs(a.frames) do
		if not dispatch and f.frame.scripts.OnEvent then dispatch = f.frame.scripts.OnEvent end
	end
	assert(dispatch, "Core.lua's event frame")
	a.ns.Arena.missing = true
	w:As(a, function() dispatch(nil, "PLAYER_LOGIN") end)
	a.ns.Arena.missing = nil
	local line
	for _, l in ipairs(a.log) do if l:find("not loaded until the game restarts", 1, true) then line = l end end
	assert(line and line:find("ArenaNet.lua", 1, true), tostring(line))
	assert(not line:find("Arena.lua", 1, true), line)
end)

print("the arena's foundation review: the test world and the harness")

test("1.2 the arena's foundation review: the world's Comm: chat lines in a lane of their own (never in QueueSize, every other slot, late after 30 s); a message over 255 bytes refused (2), a chunked payload whole; each client's own Ed25519", function()
	local w = World.New({ paced = true })
	local a, b = w:Client("Lida Fenn"), w:Client("Parric Stowe")
	for i = 1, 2 do eq(a.Comm.SendChat("EC~T1~chat " .. i), true) end
	eq(a.Comm.QueueSize(), 0, "the chat lane is not the queue"); eq(a.Comm.ChatRoom(), 4)
	for i = 1, 2 do a.Comm.Send("CHANNEL", "ZZ~queue " .. i) end
	eq(a.Comm.QueueSize(), 2)
	w:Run(10)
	local order = {}
	for _, s in ipairs(w:Sent{ from = a }) do order[#order + 1] = s.msg:match("~(%a+ %d)$") end
	eq(table.concat(order, ","), "chat 1,queue 1,chat 2,queue 2", "every other slot")
	for i = 1, 6 do a.Comm.SendChat("EC~T1~more " .. i) end
	eq(a.Comm.SendChat("EC~T1~seventh"), false, "six at most")
	local told
	a.comm.chatq[1].done = function(sent, why) told = tostring(sent) .. ":" .. tostring(why) end
	for _, item in ipairs(a.comm.chatq) do item.t = w.clock - 31 end
	w:Run(0)
	eq(told, "false:late"); eq(#a.comm.chatq, 0)
	-- Too long for the game.
	local res
	w:As(a, function() a.ns.Comm.Send("CHANNEL", ("x"):rep(256), nil, nil, nil, function(sent, why) res = { sent, why } end) end)
	w:Run(2)
	eq(res[1], false); eq(res[2], 2); eq(w.failed[#w.failed].result, 2)
	local whole = {}
	b.ns.Comm.Handle("ZY", function(_, _, text) whole[#whole + 1] = text end)
	w:As(a, function() a.ns.Comm.SendChunked("ZY~" .. ("y"):rep(600), false, "CHANNEL") end)
	w:Run(2)
	eq(#whole, 1); eq(#whole[1], 603)
	-- Ed25519: each client's own job queue.
	assert(a.ns.Ed25519 ~= b.ns.Ed25519 and a.ns.Ed25519 ~= H.ns.Ed25519, "not shared")
	w:As(a, function() a.ns.Ed25519.Run(function() return true end, function() end) end)
	eq(a.ns.Ed25519.Busy(), 1); eq(b.ns.Ed25519.Busy(), 0)
	w:Run(1)
	eq(a.ns.Ed25519.Busy(), 0)
	NoErrors(w)
end)

test("1.2 the arena's foundation review: H.LoadCompanion gives the companion its saved variables of its own (opts.db) and ADDON_LOADED, so Arena.Heavy is there for a test that calls it; H.WithStub puts a value back", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local db = {}
	local own = w:As(a, function() return H.LoadCompanion(a.ns, { db = db }) end)
	eq(own.db, db); eq(a.ns.Arena.companionReady, true)
	local heavy = a.Arena.Heavy("L")
	eq(type(heavy), "table"); assert(next(db.stores) ~= nil, "kept in its own saved variables")
	eq(rawget(_G, "OlympusArenaDB"), nil, "the game's global put back")
	-- Without a db: one of its own each call.
	local b = w:Client("Parric Stowe")
	local own2 = w:As(b, function() return H.LoadCompanion(b.ns) end)
	eq(type(own2.db), "table"); assert(own2.db ~= db)
	eq(type(b.Arena.Heavy("T")), "table")
	-- opts.fire = false: neither.
	local c = w:Client("Wenna Crale")
	w:As(c, function() H.LoadCompanion(c.ns, { fire = false }) end)
	eq(c.Arena.Heavy("L"), nil)
	-- H.WithStub
	local was = H.ns.CaptureError
	local ok = pcall(H.WithStub, "CaptureError", function() end, function()
		assert(H.ns.CaptureError ~= was)
		error("fails inside")
	end)
	eq(ok, false); eq(H.ns.CaptureError, was, "put back after a failure")
	NoErrors(w)
end)

print("the arena's foundation review: Comm.lua")

test("1.2 the arena's foundation review: leaving an Olympus guild drops Comm's queue with each done told 'left' (ArenaNet's urgent share and outbox are not left counting)", function()
	RealComm(function(C, cns)
		local done = {}
		local function D(tag) return function(ok, why) done[#done + 1] = tag .. ":" .. tostring(ok) .. ":" .. tostring(why) end end
		local saved = { GetChannelName = GetChannelName, LeaveChannelByName = LeaveChannelByName }
		local ok, err = pcall(function()
			GetChannelName = function() return 5 end
			LeaveChannelByName = function() end
			C.SetJoinedForTest("OlympusNet")
			C.Send("CHANNEL", "ZZ~1", nil, false, false, D("c1"))
			C.Whisper("Someone-Realm", "ZZ~2", nil, true, false, D("w1"))
			cns.IsMember = function() return false end
			C.CheckMembership()
		end)
		GetChannelName, LeaveChannelByName = saved.GetChannelName, saved.LeaveChannelByName
		if not ok then error(err, 0) end
		eq(table.concat(done, ","), "w1:false:left,c1:false:left")
		eq(C.QueueSize(), 0)
	end)
end)

test("1.2 the arena's foundation review: the real Comm and Moderation: a net-off client's bet slip gets done(false, 'held') at once, its receipt goes", function()
	RealComm(function(C, cns, results, sent)
		assert(loadfile(H.ADDON_DIR .. "Moderation.lua"))("Olympus", cns)
		cns.Moderation.SelfOff = function() return true end
		local done = {}
		local function D(tag) return function(ok, why) done[#done + 1] = tag .. ":" .. tostring(ok) .. ":" .. tostring(why) end end
		C.Whisper("Coffrey Vault-Realm", "BS~T1~e1~1~A~100~abcdef", nil, false, false, D("bs"))
		C.Whisper("Coffrey Vault-Realm", "ZR~T1~receipt", nil, false, false, D("zr"))
		eq(done[1], "bs:false:held"); eq(C.QueueSize(), 1)
		C.Pump()
		eq(table.concat(done, ","), "bs:false:held,zr:true:nil")
		eq(#sent, 1); eq(sent[1].msg, "ZR~T1~receipt")
	end)
end)

-- The owner's call, 2026-09-30: in the sim and the normal view names showed as "Fala****" on the
-- author's client (its preview of the King's view). Names are whole now; cut short only on the
-- King's own screen while the council's names are hidden there, and in the sim's King view.
test("1.2 arena names: whole in the normal view and the sim, cut short only on the King's own screen or in the sim's King view", function()
	local w = World.New()
	local c = w:Client("Parric Stowe")
	local ns = c.ns
	local K, A = ns.King, ns.Arena
	local saved = { isKing = K.IsKing, preview = K.Preview, sim = A.Sim, simKing = A.SimKingsView, shown = ns.CouncilNamesShown() }
	local ok, err = pcall(w.As, w, c, function()
		ns.SetCouncilNamesShown(false)
		A.Sim = function() return false end
		K.IsKing, K.Preview = function() return false end, function() return true end
		eq(A.Mask("Lida Fenn"), "Lida Fenn", "the author's preview of the King's view: whole")
		eq(ns.ArenaHome.Name("Lida Fenn"), "Lida Fenn", "the screens' name too")
		K.Preview = function() return false end
		eq(A.Mask("Lida Fenn"), "Lida Fenn", "a player's own screen: whole")
		K.IsKing = function() return true end
		eq(A.Mask("Lida Fenn"), "Lida****", "the King's own screen, the council's names hidden")
		ns.SetCouncilNamesShown(true)
		eq(A.Mask("Lida Fenn"), "Lida Fenn", "the King showed them (the eye)")
		ns.SetCouncilNamesShown(false)
		-- The sim: whole unless its King view is on.
		A.Sim = function() return true end
		A.SimKingsView = function() return false end
		eq(A.Mask("Lida Fenn"), "Lida Fenn", "the sim's normal view")
		K.IsKing = function() return false end
		A.SimKingsView = function() return true end
		eq(A.Mask("Lida Fenn"), "Lida****", "the sim's King view")
	end)
	K.IsKing, K.Preview, A.Sim, A.SimKingsView = saved.isKing, saved.preview, saved.sim, saved.simKing
	ns.SetCouncilNamesShown(saved.shown)
	if not ok then error(err, 0) end
end)

-- The owner's call, 2026-09-30 (the event pane's card had text over text): one fact a line in
-- words that fit, no "self-reported" or "the ledger" after them, and no odds row (the market
-- buttons under the card carry them).
test("1.2 the event pane's card: one fact a line (class · level, the record, the division), no source words, no odds", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Card = own.ArenaUI.Card
	local f = { name = "Parric Stowe", class = "WARRIOR", classSrc = "own", level = 60, levelSrc = "own", record = "14-5", recordSrc = "ledger",
		tier = "silver", title = "Bonecrusher", titleSrc = "own", odds = 2.28, pool = 37100, count = 28 }
	local rows = w:As(a, function() return Card.Rows(f, "g", "compact") end)
	local L = a.ns.L
	local values = {}
	for i, r in ipairs(rows) do
		values[i] = r.value
		eq(r.tag, "", "no source word: " .. r.label)
		assert(not r.value:find(L.ARENA_SRC_OWN, 1, true) and not r.value:find(L.ARENA_SRC_LEDGER, 1, true), r.value)
	end
	eq(#rows, 3, table.concat(values, " | "))
	assert(rows[1].value:find("60", 1, true) and rows[1].value:find(" · ", 1, true), rows[1].value)
	eq(rows[2].value, L.ARENA_CARD_RECORD .. " 14-5")
	eq(rows[3].value, L.ARENA_TIER_SILVER)
	-- The Tale of the tape (the window size) keeps its fuller rows.
	local full = w:As(a, function() return Card.Rows(f, "g", "window") end)
	assert(#full > 3, "the window's card: " .. #full .. " rows")
end)

-- The owner's rule, 2026-09-30: no label wider than its button. Kit.Fit sizes a button from its
-- words (the font string's width and 20 px, at least the minimum); the stepper's buttons are fitted.
test("1.2 arena buttons: Kit.Fit sizes a button from its words; the amount stepper's buttons are fitted", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Kit = own.ArenaUI.Kit
	local function Fake(textW, text)
		return { GetFontString = function() return { GetStringWidth = function() return textW end } end, GetText = function() return text end,
			SetWidth = function(self, v) self.w = v end, GetWidth = function(self) return self.w end }
	end
	local b = Fake(70.4, "Parric 2.28x")
	Kit.Fit(b); eq(b.w, 91, "71 and 20")
	b = Fake(6, "+"); Kit.Fit(b); eq(b.w, 32, "at least 32")
	b = Fake(6, "+"); Kit.Fit(b, 60); eq(b.w, 60, "at least the minimum asked")
	b = Fake(nil, "Max"); Kit.Fit(b); eq(b.w, 41, "no width measured: 7 a character and 20")
	-- The stepper: every step button went through Kit.Fit (its width set from its words).
	local fitted = {}
	local was = Kit.Fit
	Kit.Fit = function(btn, minW) fitted[#fitted + 1] = btn return was(btn, minW) end
	local s = w:As(a, function() return Kit.Stepper(a.ns.UIParent or UIParent, { width = 320, min = 1000, max = 100000 }) end)
	Kit.Fit = was
	eq(#fitted, #s.stepButtons + 2, "Min, the steps and Max")
end)

-- The owner's look for the bracket (2026-09-30): it fills its parchment, the round's title over
-- each column, the final's slots bigger in the centre.
test("1.2 the bracket's layout: 16 fighters fill the large window, titles by round, the final bigger in the centre, nothing overlaps", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local B = own.ArenaUI.Bracket
	local geo = B.SIZES.large
	local lay = B.Layout(16, "large")
	eq(lay.columns, 7)
	local players = {}
	for i, c in ipairs(lay.cols) do players[i] = c.players end
	eq(table.concat(players, ","), "16,8,4,2,4,8,16", "Round of 16, Quarter-finals, Semi-finals, Final and back")
	assert(lay.slotH >= 40 and lay.slotW >= 110, "twice the old 22 px tall, wider: " .. lay.slotW .. " x " .. lay.slotH)
	assert(lay.width <= geo.w and lay.height <= geo.h, "inside the window")
	assert(lay.width >= geo.w * 0.9, "fills its width: " .. lay.width)
	-- (Build 3's verdict, "misaligned vertically": each later round's slot centred exactly on its
	-- two feeders' midpoint, the final one box of its two finalists centred on the middle.)
	local final = {}
	for i, s in ipairs(lay.slots) do
		assert(s.y >= lay.head, "under the titles' row")
		if s.half == "F" then final[s.slot] = s; eq(s.col, 4, "the final in the centre column") end
		for j = i + 1, #lay.slots do assert(not B.Overlap(s, lay.slots[j]), "slots " .. i .. " and " .. j .. " overlap") end
	end
	eq(final[1].y + final[1].h, final[2].y, "the finalists' box: one above the other, no gap")
	eq(final[2].y, lay.mid, "the box's centre on the middle")
	local function Centre(s) return s.y + s.h / 2 end
	for _, s in ipairs(lay.slots) do
		if s.half ~= "F" and s.round > 1 then
			local feeders = {}
			for _, p in ipairs(lay.slots) do
				-- (A feeder: the round before, same half, half a span above or below.)
				if p.half == s.half and p.round == s.round - 1 then
					if math.abs(Centre(p) - Centre(s)) <= (lay.slotH + B.SIZES.large.vgap) * 2 ^ (s.round - 2) + 1 then feeders[#feeders + 1] = p end
				end
			end
			eq(#feeders, 2, "two feeders for a slot of round " .. s.round)
			assert(math.abs(Centre(s) - (Centre(feeders[1]) + Centre(feeders[2])) / 2) <= 1, "centred on its feeders' midpoint")
		end
	end
	-- The semi-finals' pairs meet on the middle: the final's connectors come in there.
	for _, half in ipairs({ "L", "R" }) do
		local semis = {}
		for _, s in ipairs(lay.slots) do if s.half == half and s.round == lay.rounds - 1 then semis[#semis + 1] = s end end
		eq(#semis, 2)
		assert(math.abs((Centre(semis[1]) + Centre(semis[2])) / 2 - lay.mid) <= 1, half .. ": the semi-finals meet on the middle")
	end
	local L = a.ns.L
	eq(L.ARENA_ROUND_16, "Round of 16"); eq(L.ARENA_ROUND_8, "Quarter-finals"); eq(L.ARENA_ROUND_4, "Semi-finals"); eq(L.ARENA_ROUND_2, "Final")
end)

-- The owner's rule, 2026-09-30: one pop-up at a time, never stacked on another (the rules' yes
-- and the chat panel may stay over one: they stack).
test("1.2 arena pop-ups: one at a time; a stacking one (the rules' yes) opens over another and closes none", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Kit = own.ArenaUI.Kit
	local function Open(f) f:Show() f:GetScript("OnShow")(f) end
	w:As(a, function()
		local one = Kit.Frame("OlympusArenaTestOne", 300, 200, { title = "One" })
		local two = Kit.Frame("OlympusArenaTestTwo", 300, 200, { title = "Two" })
		local gate = Kit.Frame("OlympusArenaTestGate", 300, 200, { title = "Gate", stack = true })
		assert(one.footer and two.footer, "a footer compartment each")
		Open(one)
		Open(two)
		eq(one:IsShown(), false, "the first closed when the second opened"); eq(two:IsShown(), true)
		Open(gate)
		eq(two:IsShown(), true, "the rules' yes stacks over it"); eq(gate:IsShown(), true)
	end)
end)

-- The owner's critique of build 3 (2026-09-30): no row of section, staff or wallet buttons in the
-- arena window; its panes as tabs; New fight in the footer (the list's Find an opponent and
-- Challenge someone lines are gone); a wider window.
-- (Then the owner's layout after build 5, 2026-09-30: 960 x 700, the tabs kept at the top, the
-- list in a dark panel like the Census's on the left, the games' one bar across the bottom.)
test("1.2 the arena window: 960 x 700, tabs at the top, the list's dark panel, no top row of buttons, New fight in the games' bar, the list without its action lines", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	w:As(a, function() a.slashes.OLYMPUS("arena") end)
	local UI = a.companion.own.ArenaUI
	local f = UI.Frame()
	eq(UI.W, 960); eq(UI.H, 700)
	assert(UI.W <= 1024 and UI.H <= 768, "inside 1024 x 768")
	assert(rawget(f, "listPanel") and rawget(f, "bar"), "the list's panel and the games' bar")
	eq(rawget(f, "side"), nil, "no sidebar")
	eq(f.list.content.style, "hd", "the Census's rows")
	eq(rawget(f, "navButtons"), nil, "no row of section or staff buttons")
	eq(rawget(f, "walletButton"), nil, "no Wallet button: the footer's coin and balance")
	local L = a.ns.L
	eq(f.newFight:GetText(), L.ARENA_NEW_FIGHT); eq(f.newFight:IsShown(), true)
	local tabs = 0
	for _, t in ipairs(f.paneButtons) do if t:IsShown() then tabs = tabs + 1 end end
	eq(tabs, #UI.SectionPanes("arena"), "a tab a pane")
	for _, line in ipairs(f.list.lines or {}) do
		assert(not tostring(line.text or ""):find(L.ARENA_FIND_OPPONENT, 1, true), "no Find an opponent line")
		assert(not tostring(line.text or ""):find(L.ARENA_CHALLENGE_SOMEONE, 1, true), "no Challenge someone line")
	end
	NoErrors(w)
end)

-- The design: the canonical Wallet lives in the main addon's Treasury tab for every member.
-- A normal client never mistakes the companion's local practice balance for a real wallet.
test("1.2 Wallet: the Treasury tab owns the canonical page; a normal client gets no invented practice balance; the games' coin button opens it", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local T, L = a.ns.Treasury, a.ns.L
	w:As(a, function()
		own.Wallet.Move(-1000, "Bones: stake", "Bones: stake", "bonethrow")
		own.Wallet.Move(2500, "Bones: won", "Bones: won", "bonethrow")
		T.Show("summary")
		local lines = T.Build()
		eq(lines[1].text:find(L.MONEY_LINK, 1, true) ~= nil, true, "Wallet first on the summary")
		lines[1].onClick()
		eq(T.mode, "wallet")
		lines = T.Build()
		local scope, status, text = nil, nil, {}
		for _, l in ipairs(lines) do
			if l.key == "wallet-scope" then scope = l end
			if l.key == "wallet-status" then status = l end
			text[#text + 1] = tostring(l.text or "")
		end
		assert(scope and scope.text:find(L.MONEY_WALLET_SCOPE, 1, true), "the wallet is distinguished from Treasury books")
		assert(status and status.text:find(L.MONEY_WALLET_DISABLED, 1, true), "real gold remains disabled")
		local all = table.concat(text, "\n")
		assert(not all:find("Bones: won", 1, true) and not all:find("Bones: stake", 1, true), "no local practice history on the canonical page")
		-- The companion's transaction form follows the planner's designated receiver instead of the
		-- first online name, so successive assignments can be distributed by Wallet.RecipientPlan.
		local wasView = a.ns.Wallet.View
		a.ns.Wallet.View = function() return { live = true, persists = true, currency = "g", banks = {
			{ name = N.bank, state = "o", online = true, persists = true, g = {} },
			{ name = N.treasurerMail, state = "o", online = true, persists = true, g = {} },
		}, recommended = N.treasurerMail, receivers = {}, receipts = {}, intents = {}, debts = {} } end
		eq(own.ArenaUI.WalletModel().bankName, N.treasurerMail, "the recommended designated receiver")
		a.ns.Wallet.View = wasView
		T.Show("summary")
		-- (The Olympus window itself is not built in the test world: its tab choice is read.)
		local savedUI, selected = a.ns.UI, nil
		a.ns.UI = { SelectTab = function(key) selected = key end }
		own.Games.OnMoney()
		a.ns.UI = savedUI
		eq(T.mode, "wallet", "the coin button opens Wallet"); eq(selected, "treasury", "on the Treasury tab")
	end)
end)

-- The owner's call, 2026-09-30: the Games tab has a button a game (Arena, Bones, Lottery) and the
-- Wallet, and a row each with its line; no "Open the Arena" or "My bets" buttons.
test("1.2 the Games tab: Arena, Bones, Lottery and Wallet, as buttons and as rows", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local AH, L = a.ns.ArenaHome, a.ns.L
	local labels = {}
	for i, b in ipairs(AH.BUTTONS) do labels[i] = b[1] end
	eq(table.concat(labels, ","), "ARENA_SECTION_ARENA,ARENA_SECTION_BONE,ARENA_SECTION_LOTTERY,ARENA_GAME_WALLET")
	eq(L.ARENA_SECTION_BONE, "Bones")
	local lines = w:As(a, function() return AH.TabLines() end)
	local rows = 0
	for _, l in ipairs(lines) do
		for _, g in ipairs(AH.GAMES) do if l.onClick and l.text:find(L[g.label], 1, true) and l.right and l.right:find(L[g.desc], 1, true) then rows = rows + 1 end end
	end
	eq(rows, 4, "a row a game, with its line")
	eq(AH.GAMES[1].icons[1], "Interface\\Icons\\INV_Sword_04", "Duels/Arena has a real Blizzard sword icon first")
	eq(AH.GAMES[4].icons[1], "Interface\\MoneyFrame\\UI-GoldIcon", "Wallet has the Blizzard money icon first")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:As(a, own.Games.Hub, true)
	local hub = own.Games._.parts().hub
	eq(#hub.rows, 4)
	eq(hub.rows[1].icon.texture, "Interface\\Icons\\INV_Sword_04")
	eq(hub.rows[2].icon.texture, "Interface\\Icons\\INV_Misc_Bone_10")
	eq(hub.rows[3].icon.texture, "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01")
	eq(hub.rows[4].icon.texture, "Interface\\MoneyFrame\\UI-GoldIcon")
end)

-- test33 (the owner's client, the Games tab's "The games"): the Bones and Lottery rows showed their
-- icon and name, the Arena and Wallet rows "." and ".." in their place. No icon or word was missing:
-- their descriptions, longer than the row, took all of it (Views.Render's right text was as wide as
-- its words, the left one got what was left, cut to an ellipsis). The rows drawn as the window
-- draws them, in a list as wide as that window's (305: the HD look's, 338 - 7 - 24 - 2), where the
-- client draws each text (a text anchored on one side only is as wide as its words): every game's
-- icon and name whole, in both languages, its description after them and cut inside the row, said
-- whole by the row's tooltip. Its icon is one Forever has: FOREVER, the files Forever drew in test33
-- (the bone and the Darkmoon ticket on these rows, the Treasury tab's coins) or a file Forever loads
-- names (Blizzard_FrameXML's PVPHonorSystem coin; the honor icons of each faction, on the Honor tab
-- of Forever's own Character window, Blizzard_UIPanels_Game/Camelot/CharacterFrame.lua); a client
-- finding none of a game's files by path (GetFileIDFromPath) gets the list's last, one of those.
-- (Changed on purpose, the review of test33: the dual-wield icon was in FOREVER, named only by
-- Blizzard_ChallengesUI/Mainline and a Cata file, neither loaded by Forever: the Arena's list now
-- ends with the player's faction's honor icon.)
test("test33 the Games tab's rows: each game's icon and name drawn whole in both languages, its description cut in the rest, an icon Forever has", function()
	local FOREVER = {
		["Interface\\Icons\\INV_Misc_Bone_10"] = true, ["Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01"] = true,
		["Interface\\Icons\\INV_Misc_Coin_02"] = true, ["Interface\\Icons\\INV_Misc_Coin_01"] = true,
		["Interface\\Icons\\INV_SideTab_Honor_Alliance_c60"] = true, ["Interface\\Icons\\INV_SideTab_Honor_Horde_c60"] = true,
	}
	local W = 305
	-- Where the client draws a font string of a row, from the row's left: each side from its anchor
	-- (on the row, or on the other text's edge); a side not anchored is the words' width away.
	local function Edges(fs)
		local l, r
		for _, p in ipairs(fs.points) do
			local point, rel, relPoint, x = p[1], p[2], p[3], p[4]
			local base
			if rel == fs.parent then
				base = relPoint:find("LEFT") and 0 or relPoint:find("RIGHT") and fs.parent:GetWidth() or fs.parent:GetWidth() / 2
			else
				local rl, rr = Edges(rel)
				base = relPoint:find("LEFT") and rl or relPoint:find("RIGHT") and rr or (rl + rr) / 2
			end
			if point:find("LEFT") then l = base + x elseif point:find("RIGHT") then r = base + x end
		end
		local words = fs:GetUnboundedStringWidth()
		if l and not r then r = l + words elseif r and not l then l = r - words end
		return l, r
	end
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local AH, L = a.ns.ArenaHome, a.ns.L
	local KEYS = {}
	for _, g in ipairs(AH.GAMES) do KEYS[#KEYS + 1] = g.label; KEYS[#KEYS + 1] = g.desc end
	local pt = {}
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local okPt, errPt = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaHomeText.lua"))("Olympus", { L = pt }) end)
	GetLocale = savedLocale
	assert(okPt, errPt)
	H.WithUI(function()
		local uns = setmetatable({}, { __index = H.ns })
		uns.On = function() end
		assert(loadfile(H.ADDON_DIR .. "UI.lua"))("Olympus", uns)
		local savedUI, savedFile, savedWords, savedFaction = rawget(a.ns, "UI"), rawget(_G, "GetFileIDFromPath"), {}, rawget(a.ns, "faction")
		for _, k in ipairs(KEYS) do savedWords[k] = rawget(L, k) end
		rawset(a.ns, "UI", uns.UI)
		local ok, err = pcall(function()
			for _, lang in ipairs({ "enUS", "ptBR" }) do
				if lang == "ptBR" then for _, k in ipairs(KEYS) do rawset(L, k, assert(pt[k], "pt-BR " .. k)) end end
				-- (A Horde player in pt-BR, an Alliance one in English: each faction's own honor icon.)
				a.ns.faction = lang == "ptBR" and "Horde" or "Alliance"
				for _, finds in ipairs({ "forever", "none" }) do
					GetFileIDFromPath = function(path) return finds == "forever" and FOREVER[path] and 1 or nil end
					local lines = w:As(a, function() return AH.TabLines() end)
					local content = CreateFrame("Frame", nil, UIParent)
					content.w, content.style = W, "hd"
					H.ns.Views.Render(content, lines)
					for _, g in ipairs(AH.GAMES) do
						local name, desc = L[g.label], L[g.desc]
						local where = lang .. ", " .. finds .. ", " .. g.label
						assert(type(name) == "string" and name ~= "" and name ~= g.label, where .. ": a name")
						local row
						for _, r in ipairs(content.rows) do
							if r:IsShown() and r.line and r.line.onClick and tostring(r.line.text):find(name, 1, true) and r.line.right then row = r end
						end
						assert(row, where .. ": its row")
						local icon = row.left:GetText():match("^|T([^:|]+):18:18|t")
						assert(icon and FOREVER[icon], where .. ": an icon Forever has, not " .. tostring(icon))
						if g.label == "ARENA_SECTION_ARENA" then
							eq(icon, "Interface\\Icons\\INV_SideTab_Honor_" .. a.ns.faction .. "_c60", where .. ": the player's faction's honor icon")
						end
						local l, r = Edges(row.left)
						assert(r - l >= row.left:GetUnboundedStringWidth(), where .. ": the icon and the name whole (" .. (r - l) .. " for " .. row.left:GetUnboundedStringWidth() .. ")")
						local dl, dr = Edges(row.right)
						assert(dl >= r and dr <= W, where .. ": the description after them, inside the row")
						eq(row.right:GetText(), "|cff9d9d9d" .. desc .. "|r", where)
						local tip = { AddLine = function(self, text) self[#self + 1] = text end }
						row.line.tooltip(tip)
						eq(tip[1], name, where); eq(tip[2], desc, where .. ": the description whole in the tooltip")
					end
				end
			end
		end)
		GetFileIDFromPath = savedFile
		rawset(a.ns, "UI", savedUI); rawset(a.ns, "faction", savedFaction)
		for _, k in ipairs(KEYS) do rawset(L, k, savedWords[k]) end
		if not ok then error(err, 0) end
	end)
end)

-- The owner's call, 2026-09-30: no mock-data label on the windows (the screens are shown to the
-- guild): no SIMULATION strip, no SAMPLE DATA stamp; the sim's own bar says so.
test("1.2 the sim: no SIMULATION strip on the windows and no SAMPLE DATA stamp on the overlay", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	eq(t.Arena.SetSim(true), true)
	w:As(t, function()
		eq(t.ns.ArenaHome.Banner(), nil, "no strip")
		for _, l in ipairs(t.ns.ArenaHome.TabLines()) do
			assert(not tostring(l.text or ""):find(t.ns.L.ARENA_BANNER_SIM, 1, true), "no strip on the Games tab")
		end
	end)
	t.Arena.SetSim(false)
end)

-- The owner on build 4: the letter's portrait sat off the frame's ring; on test build 33 every
-- Olympus portrait still looked unlike his own on his unit frame. The Arena's own letter (the
-- sim's, and any build without HonorsNet's letters) draws his portrait as HonorsNet.NewPortrait
-- does (Borders.NewPortrait: his frame's portrait, ring and art round it, at its offsets, scaled
-- as a whole), the honour he won on it, a first place in the Arena's "-1" spelling as the honour;
-- the lines above and below clear of its art.
test("1.2 the King's letter (the Arena's own): his portrait drawn as his own on his unit frame, the honour won on it; the words clear of the art", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	w:As(t, function()
		rawset(t.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", t.ns)
	end)
	local points, pictures = {}, {}
	local create = t.globals.CreateFrame
	local function Keep(region)
		rawset(region, "SetPoint", function(self, point, ...)
			points[self] = points[self] or {}
			points[self][point] = { point, ... }
		end)
		return region
	end
	t.globals.CreateFrame = function(...)
		local f = Keep(create(...))
		rawset(f, "CreateFontString", function(self) return Keep(World.NewFrame("FontString", nil, self)) end)
		return f
	end
	t.globals.SetPortraitTexture = function(tex, unit, square) pictures[#pictures + 1] = { tex = tex, unit = unit, square = square } end
	eq(t.Arena.SetSim(true), true)
	local AH = t.ns.ArenaHome
	w:As(t, AH.Letter, "arena-champion-1")
	local f = AH.LetterFrame()
	eq(f ~= nil and f:IsShown(), true, "the letter")
	local rig = f.rig
	assert(type(rig) == "table" and rig.container and rig.box and rig.underlay and not rig.plain, "Borders.NewPortrait's rig, not a drawing of the letter's own")
	eq(rig.size, 96); eq(rig.mirror, true, "turned round, as round his own portrait")
	eq(rig.shown, "arena-champion", "the champion's first place: the honour itself")
	eq(rig.honor.winged.texture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold"); eq(rig.honor.winged.shown, true)
	local last = pictures[#pictures]
	eq(last.tex, rig.portrait); eq(last.unit, "player"); eq(last.square, true, "square: the rig's mask rounds it")
	-- Second place: the silver gryphon on the same texture.
	w:As(t, AH.ReadLetter, { key = "arena-champion-2" })
	eq(rig.shown, "arena-champion-2"); eq(rig.honor.winged.texture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-silver")
	-- The words clear of the art: "To <name>," above it, the honour's title below it.
	local at, title = points[rig.slot].TOP, points[f.honour].TOP
	eq(-at[3] - rig.reach.top >= 84, true, "below the greeting")
	eq(-title[5] >= -at[3] + rig.size + rig.reach.bottom, true, "the title below the art")
	t.Arena.SetSim(false)
end)

-- The owner's rankings (2026-09-30): places 1-3 wear the honour's mark (the gryphon overall, the
-- class's animal, the race's mount; gold, silver, bronze); everyone else the division's icon.
test("1.2 rankings: the podium's marks by category and place, none past third", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	assert(UI.RankMark("A", 1):find("gryphon%-gold%-mark$"), "overall: the gryphon")
	assert(UI.RankMark("CMA", 2):find("mage%-silver%-mark$"), "a class: its animal")
	assert(UI.RankMark("CWA", 1):find("boar%-gold%-mark$"), "the warriors' boar")
	assert(UI.RankMark("R6", 3):find("kodo%-bronze%-mark$"), "a race: its mount")
	eq(UI.RankMark("A", 4), nil, "fourth: the division's icon")
	for _, cat in ipairs({ "CWA", "CPA", "CHU", "CRO", "CPR", "CSH", "CMA", "CWL", "CDR", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8" }) do
		local file = UI.RankMark(cat, 1):match("honours\\(.+)$")
		local f = io.open(H.ROOT .. "Olympus/media/honours/" .. file .. ".tga", "rb")
		assert(f, "the file is there: " .. file)
		f:close()
	end
end)

-- The owner on build 7: the grey-left, parchment-right structure on every arena tab. The rankings
-- are a list in the grey block (their filters over it) and the podium on the parchment.
test("1.2 rankings: the list in the grey block with its filters, the podium on the parchment, the test build's note in a corner", function()
	local w = World.New()
	local a = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	w:As(a, function() a.slashes.OLYMPUS("arena") end)
	local UI = a.companion.own.ArenaUI
	local spec = UI.Pane("arena.rankings")
	assert(spec.lines and spec.detail and spec.head, "a list, a detail and a head")
	w:As(a, function() UI.ShowPane("arena.rankings") end)
	local f = UI.Frame()
	eq(f.listPanel:IsShown(), true, "the grey block shows")
	assert(f.heads["arena.rankings"], "the filters over the list")
	eq(f.banner:IsShown(), false, "no strip for the test build")
	assert((f.testNote:GetText() or "") ~= "", "its note in the corner")
	NoErrors(w)
end)

-- The owner's profile page (2026-09-30): the stat blocks and the in-profile fight History in the
-- grey block, the portrait and who he is on the parchment; Visibility opens the privacy page.
test("1.2 the profile: its stat blocks and History, the Visibility button, the privacy page's Profile lines", function()
	local w = World.New()
	local a = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	w:As(a, function() a.slashes.OLYMPUS("arena") end)
	local UI, L = a.companion.own.ArenaUI, a.ns.L
	local spec = UI.Pane("arena.profile")
	assert(spec.lines and spec.detail, "a list and a detail")
	local lines = w:As(a, function() return spec.lines({ key = "arena.profile" }) end)
	local heads = {}
	for _, l in ipairs(lines) do if l.header then heads[#heads + 1] = l.text end end
	eq(table.concat(heads, ","), table.concat({ L.ARENA_PROF_FIGHTS, L.ARENA_HISTORY_TITLE, L.ARENA_PROF_BONES, L.ARENA_PROF_LOTTERY, L.ARENA_PROF_DONATIONS,
		L.ARENA_PROF_PLACES, L.ARENA_PROF_TABARD, L.ARENA_PROF_ONLINE }, ","))
	local buttons = spec.buttons({ key = "arena.profile" })
	eq(buttons[1][1], L.ARENA_HISTORY_SHOW_RECENT, "History's Mine/Everyone control stays in Profile")
	eq(buttons[2][1], L.ARENA_PROF_VISIBILITY)
	local keys = {}
	for _, item in ipairs(a.ns.Consent.Items and a.ns.Consent.Items() or {}) do keys[item.key] = true end
	if a.ns.Consent.Items then assert(keys.arenaProfileStats and keys.arenaProfileHours, "the Profile lines on the privacy page") end
	NoErrors(w)
end)

-- The owner's bug on build 7: the Games tab's Arena button showed "ARENA_SECTION_ARENA" (a key
-- only the companion's words had, read by the core before the companion loads). Every word the
-- code names must be where that code reads it, in English and in pt-BR: a key named in a core
-- file (L.X, L["X"], or "X" as a label handed on) in the core's locales; a companion file's in the
-- core's or the companion's. A few words are the same in both languages (names, formats).
test("1.2 every locale key the code names exists where it reads it, in English and pt-BR", function()
	local function Files(dir, pattern)
		local out = {}
		local p = io.popen('find "' .. dir .. '" -name "' .. pattern .. '" 2>/dev/null')
		for f in p:lines() do out[#out + 1] = f end
		p:close()
		return out
	end
	local function Keys(files)
		local en, pt = {}, {}
		for _, f in ipairs(files) do
			for line in io.lines(f) do
				local k = line:match("^L%.([%a_][%w_]*)%s*=") or line:match('^L%["([%w_]+)"%]%s*=')
				if k then en[k] = true end
				k = line:match("^\tL%.([%a_][%w_]*)%s*=") or line:match('^\tL%["([%w_]+)"%]%s*=')
				if k then pt[k] = true end
			end
		end
		return en, pt
	end
	local coreLoc = Files(H.ADDON_DIR .. "Locales", "*.lua")
	coreLoc[#coreLoc + 1] = H.ADDON_DIR .. "Locales.lua"
	local cen, cpt = Keys(coreLoc)
	local aen, apt = Keys(Files(H.ARENA_DIR .. "Locales", "*.lua"))
	local SAME = { TITLE = true, LINK_TITLE = true, COL_ONLINE = true, DUES_GUILD_ROW = true, DUES_NO_GUILD_ROW = true }
	local function Check(files, en, pt, where)
		local n = 0
		for _, f in ipairs(files) do
			local code = Read(f):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
			local used = {}
			for k in code:gmatch("[^%w_%.]L%.([%u][%u%d_]+)") do used[k] = true end
			for k in code:gmatch('[^%w_%.]L%["([%u][%u%d_]+)"%]') do used[k] = true end
			-- a label handed on as data: a string naming a key some locale has
			for k in code:gmatch('"([%u][%u%d_]+)"') do if (cen[k] or aen[k]) and k:find("_") then used[k] = true end end
			for k in pairs(used) do
				n = n + 1
				assert(en[k], where .. ": " .. f .. " names " .. k .. ", which its words lack")
				assert(pt[k] or SAME[k], where .. ": " .. k .. " has no pt-BR")
			end
		end
		return n
	end
	local core = Files(H.ADDON_DIR, "*.lua")
	local only = {}
	for _, f in ipairs(core) do if not f:find("/Locales") and not f:find("/Dev") then only[#only + 1] = f end end
	local merged, mergedPt = {}, {}
	for k in pairs(cen) do merged[k] = true end
	for k in pairs(aen) do merged[k] = true end
	for k in pairs(cpt) do mergedPt[k] = true end
	for k in pairs(apt) do mergedPt[k] = true end
	local comp = {}
	for _, f in ipairs(Files(H.ARENA_DIR, "*.lua")) do if not f:find("/Locales/") then comp[#comp + 1] = f end end
	assert(Check(only, cen, cpt, "core") > 1000, "the core's keys were read")
	assert(Check(comp, merged, mergedPt, "companion") > 300, "the companion's keys were read")
end)

-- The owner's Games tab (2026-09-30): the games' rankings in one switchable view and a staff
-- section, for the King, the High Council and the author; the rankings for everyone once the
-- King's word (T1~O's new rankPub) says so. A word from a build before the field still reads.
test("1.2 the Games tab: the rankings and the staff section for the staff; rankPub in the King's settings", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local AH, L, R = a.ns.ArenaHome, a.ns.L, a.ns.ArenaRoles
	local function Has(lines, text) for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return true end end return false end
	w:As(a, function()
		eq(AH.GamesStaff(), false)
		local lines = AH.TabLines()
		eq(Has(lines, L.ARENA_GAMES_RANKINGS), false, "a member: no rankings while the King keeps them to the staff")
		eq(Has(lines, L.ARENA_GAMES_STAFF), false, "no staff section")
		local was = a.ns.IsHighCouncillor
		a.ns.IsHighCouncillor = function() return true end
		lines = AH.TabLines()
		eq(Has(lines, L.ARENA_GAMES_RANKINGS), true, "a councillor sees the rankings")
		eq(Has(lines, L.ARENA_GAMES_STAFF), true, "and the staff section")
		a.ns.IsHighCouncillor = was
	end)
	-- rankPub: the last field of T1~O; the older word (without it) reads, as 0
	local s = R.Settings()
	eq(s.rankPub, 0)
	local text = R.SettingsText(s)
	local old = text:gsub("~[01]$", "")
	local t = R.ReadSettings(old)
	assert(t, "an older build's word still reads")
	eq(t.rankPub, 0)
	s.rankPub = 1
	eq(R.ReadSettings(R.SettingsText(s)).rankPub, 1)
end)

-- 1.2 (Daniel, 2026-10-05): the author's View as previews a role's Games tab too: the staff
-- section for the King's and the High Council's preview, none for a member's or an arbiter's; his
-- own view keeps his. Presentation alone: never more than his own staff view shows him.
test("1.2 the Games tab: the author's View as shows the staff section of the role it previews; nobody else has View as", function()
	local w = World.New()
	local author, a = w:Role("author"), w:Client("Lida Fenn")
	w:As(author, function()
		local ns = author.ns
		assert(loadfile(H.ADDON_DIR .. "ViewAs.lua"))("Olympus", ns)
		local AH, VA = ns.ArenaHome, ns.ViewAs
		eq(ns.Workshop.IsAuthor(), true, "the world's author")
		eq(AH.GamesStaff(), true, "his own view: the staff section")
		assert(VA.Set("member")); eq(AH.GamesStaff(), false, "a member's preview: none")
		assert(VA.Set("arbiter")); eq(AH.GamesStaff(), false, "an arbiter is no staff")
		assert(VA.Set("councillor")); eq(AH.GamesStaff(), true, "the High Council's preview")
		assert(VA.Set("king")); eq(AH.GamesStaff(), true)
		eq(ns.King.IsKing(), false, "the preview crowns nobody")
		assert(VA.Set("my")); eq(AH.GamesStaff(), true)
	end)
	w:As(a, function()
		assert(loadfile(H.ADDON_DIR .. "ViewAs.lua"))("Olympus", a.ns)
		eq(a.ns.ViewAs.Set("king"), false, "no View as but the author's"); eq(a.ns.ViewAs.Previewing(), false)
		eq(a.ns.ArenaHome.GamesStaff(), false)
	end)
end)

-- The arbiter's console had no way in from the guild window: only /oly arena arbiter. A listed
-- arbiter who is not on the staff now has his own lines in the Games tab (on duty or off, the
-- console, his fights, a new fight); a member has none.
test("1.2 the Games tab: a listed arbiter who is not staff gets his console lines; a member does not", function()
	local w = World.New()
	local king = w:Role("king")
	local lida, wenna = w:Client("Lida Fenn"), w:Client("Wenna Crale")
	assert(king.Roles.SetArbiters({ { name = lida.name, cap = 5 } }))
	w:Run(0)
	local L = lida.ns.L
	local function Find(lines, text)
		for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return l end end
		return nil
	end
	w:As(wenna, function()
		local AH = wenna.ns.ArenaHome
		local lines = AH.TabLines()
		eq(Find(lines, L.ARENA_GAMES_CONSOLE), nil, "a member: no console line")
		eq(Find(lines, L.ARENA_GAMES_NEW_FIGHT), nil, "nor a new fight")
	end)
	w:As(lida, function()
		local AH = lida.ns.ArenaHome
		eq(AH.GamesStaff(), false, "not staff")
		eq(lida.ns.ArenaRoles.IsArbiter(lida.name, "L"), true, "listed by the King's word")
		local lines = AH.TabLines()
		eq(Find(lines, L.ARENA_GAMES_STAFF), nil, "no staff section")
		local head = Find(lines, L.ARENA_GAMES_ARBITER)
		assert(head and head.header, "the Arbiter header")
		eq(AH.IsArbiterHere(), true)
		assert(tostring(head.right):find(L.ARENA_GAMES_OFF_DUTY, 1, true), "off duty: " .. tostring(head.right))
		local console, fights, new = Find(lines, L.ARENA_GAMES_CONSOLE), Find(lines, L.ARENA_GAMES_MY_FIGHTS), Find(lines, L.ARENA_GAMES_NEW_FIGHT)
		assert(console and console.onClick and fights and fights.onClick and new and new.onClick, "the console, his fights, a new fight")
		eq(fights.right, "0")
		-- The console line opens the Arena window on its Arbiter tab; New fight, its pop-up over it.
		console.onClick()
		local UI = lida.ns.Arena.ui
		assert(type(UI) == "table", "the companion loaded")
		eq(UI.state.staff, "staff.arbiter")
		UI.state.staff = nil
		new.onClick()
		eq(UI.state.staff, "staff.arbiter")
		local pop = UI.NewFight()
		assert(pop and pop:IsShown(), "the new fight pop-up")
	end)
	eq(w:As(wenna, wenna.ns.ArenaHome.IsArbiterHere), false, "the member is no arbiter")
	NoErrors(w)
end)

-- Reviewer (2026-10-05): the Arbiter's preview showed a member's Games tab (the arbiter's lines
-- went by the author's own character alone), and every other preview showed them once his
-- character was an arbiter. Now the previews of the roles that are arbiters have them (the Arbiter,
-- the King and the High Council: ArenaRoles.IsPublicArbiter), acting for none when the author is no
-- arbiter (the console's switches would send for real); the others' do not.
test("1.2 the Games tab: the author's Arbiter preview shows an arbiter's lines, acting for none; the others' as their roles have them", function()
	local function Find(lines, text)
		for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return l end end
		return nil
	end
	-- The arbiter's own header (the staff section's "Arbiters (n)" is another line).
	local function Head(lines, L)
		for _, l in ipairs(lines) do if l.header and l.text == L.ARENA_GAMES_ARBITER then return l end end
		return nil
	end
	local NOT_ARBITERS = { "member", "officer", "gm", "treasurer", "correspondent" }
	-- An author with no signed lists here: no arbiter (not signed one, not the King's listed one).
	local w = World.New()
	local king, author = w:Role("king"), w:Role("author", { council = false })
	assert(king.Roles.SetArbiters({ { name = w:Client("Lida Fenn").name, cap = 5 } }))
	w:Run(0)
	w:As(author, function()
		local ns = author.ns
		local L = ns.L
		assert(loadfile(H.ADDON_DIR .. "ViewAs.lua"))("Olympus", ns)
		local AH, VA = ns.ArenaHome, ns.ViewAs
		eq(ns.Workshop.IsAuthor(), true); eq(AH.IsArbiterHere(), false, "no arbiter")
		eq(Head(AH.TabLines(), L), nil, "his own view: his own lines, none")
		for _, role in ipairs({ "arbiter", "king", "councillor" }) do
			assert(VA.Set(role))
			local lines = AH.TabLines()
			local head = Head(lines, L)
			assert(head, role .. "'s preview: an arbiter's header")
			for _, text in ipairs({ L.ARENA_GAMES_CONSOLE, L.ARENA_GAMES_MY_FIGHTS, L.ARENA_GAMES_NEW_FIGHT }) do
				local line = Find(lines, text)
				assert(line, role .. ": the line " .. text)
				eq(line.onClick, nil, role .. ": acting for none: " .. text)
			end
		end
		assert(VA.Set("arbiter")); eq(Find(AH.TabLines(), L.ARENA_GAMES_STAFF), nil, "an arbiter is no staff")
		for _, role in ipairs(NOT_ARBITERS) do
			assert(VA.Set(role)); eq(Head(AH.TabLines(), L), nil, role .. "'s preview: no arbiter's lines")
		end
		assert(VA.Set("my"))
	end)
	NoErrors(w)
	-- The author's character a signed arbiter (the test council's +a): his own view and the Arbiter's
	-- have his lines, acting (his own), and a member's preview not.
	local w2 = World.New()
	local author2 = w2:Role("author")
	w2:Run(0)
	w2:As(author2, function()
		local ns = author2.ns
		local L = ns.L
		assert(loadfile(H.ADDON_DIR .. "ViewAs.lua"))("Olympus", ns)
		local AH, VA = ns.ArenaHome, ns.ViewAs
		eq(AH.IsArbiterHere(), true, "a signed arbiter")
		assert(Head(AH.TabLines(), L), "his own view")
		for _, role in ipairs(NOT_ARBITERS) do
			assert(VA.Set(role)); eq(Head(AH.TabLines(), L), nil, role .. "'s preview: none")
		end
		assert(VA.Set("arbiter"))
		local console = Find(AH.TabLines(), L.ARENA_GAMES_CONSOLE)
		assert(console and console.onClick, "his console line acts: his own")
		assert(VA.Set("my"))
	end)
	NoErrors(w2)
end)

-- Who publishes the games' rankings (the owner's answer, 2026-10-04: the King and the councillors
-- he names, per game). The switch is now a publish word per game (AU), no longer the settings'
-- rankPub (a councillor's click on that was refused after the fact): the King names councillors
-- for a game (T1~J); a named one flips that game's switch, for everyone, and the change is kept
-- with who made it; an unnamed one sees it read-only and his word is ignored; named no more, his
-- word stops counting at once. The giver's client repeats its word for late logins.
test("1.2 the rankings' publish word: the King names a councillor per game; his switch shows that game's ranking to everyone, logged; read-only and ignored for the rest; revoked at once", function()
	local w = World.New()
	local king, hc, hc2 = w:Role("king"), w:Role("councillor"), w:Role("councillor2")
	local lida = w:Client("Lida Fenn")
	local L = king.ns.L
	local ARENA, BONES = L.ARENA_SECTION_ARENA, L.ARENA_SECTION_BONE
	local function Find(lines, text)
		for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return l end end
		return nil
	end
	local function Lines(c) return w:As(c, c.ns.ArenaHome.TabLines) end
	local function Public(c, game) return w:As(c, c.ns.ArenaHome.RankingsPublic, game) end
	local switch = L.ARENA_GAMES_SHOW_GAME:format(ARENA)
	-- Nobody named yet: the councillor sees the Arena's switch read-only; the member no rankings.
	local line = Find(Lines(hc), switch)
	assert(line, "the councillor sees the switch")
	eq(line.onClick, nil, "read-only")
	assert(tostring(line.right):find(L.ARENA_GAMES_READ_ONLY, 1, true), tostring(line.right))
	eq(w:As(hc, hc.ns.ArenaHome.MaySetRankings, "arena"), false)
	eq(Find(Lines(lida), L.ARENA_GAMES_RANKINGS), nil, "the member: no rankings yet")
	eq(Find(Lines(hc), L.ARENA_GAMES_PUBLISHERS:format(ARENA)), nil, "only the King names publishers")
	-- The King names Brannoc for the Arena: his council's line, clicked. (The King's screen cuts
	-- the councillors' names short until he clicks the eye; shown here.)
	local cut = Find(Lines(king), L.ARENA_GAMES_PUBLISHERS:format(ARENA))
	assert(cut, "the King's publishers lines")
	eq(Find(Lines(king), "Brannoc Weald"), nil, "the names cut short on the King's screen")
	w:As(king, king.ns.SetCouncilNamesShown, true)
	local kingLines = Lines(king)
	assert(Find(kingLines, L.ARENA_GAMES_PUBLISHERS:format(ARENA)), "the King's publishers lines")
	local named = Find(kingLines, "Brannoc Weald")
	assert(named and named.onClick, "Brannoc's line can be clicked")
	assert(tostring(named.right):find(L.ARENA_NO, 1, true), "not named yet")
	w:As(king, named.onClick)
	w:Run(0)
	local j = w:Sent({ from = king, type = "T1" })
	assert(j[#j].msg:find("^T1~J~") and j[#j].msg:find("Brannoc Weald:a", 1, true), j[#j].msg)
	eq(w:As(lida, lida.ns.ArenaRoles.MayPublish, hc.name, "arena"), true, "every client hears the naming")
	eq(w:As(lida, lida.ns.ArenaRoles.MayPublish, hc.name, "bones"), false, "per game")
	eq(w:As(lida, lida.ns.ArenaRoles.MayPublish, hc2.name, "arena"), false, "the other councillor: not named")
	-- Brannoc's switch now clicks: the Arena's ranking for everyone, on the channel (AU).
	line = Find(Lines(hc), switch)
	assert(line and line.onClick, "named: his switch clicks")
	w:As(hc, line.onClick)
	w:Run(0)
	local au = w:Sent({ from = hc, type = "AU" })
	eq(#au, 1); eq(au[1].dist, "CHANNEL"); assert(au[1].msg:find("^AU~L1~a~1~%d+$"), au[1].msg)
	eq(Public(lida, "arena"), true, "the member hears it"); eq(Public(lida, "bones"), false, "the Arena's alone")
	local head = Find(Lines(lida), L.ARENA_GAMES_RANKINGS)
	assert(head and head.header, "the member sees the rankings")
	assert(tostring(head.right):find(ARENA, 1, true) and not tostring(head.right):find(BONES, 1, true), "only the Arena's: " .. tostring(head.right))
	eq(Find(Lines(lida), L.ARENA_GAMES_STAFF), nil, "still no staff section")
	-- Logged: the change, who made it, on every client; in the switch's tooltip.
	local log = w:As(lida, lida.ns.ArenaRoles.PublishLog)
	eq(#log, 1); eq(log[1].game, "arena"); eq(log[1].on, true); eq(log[1].from, hc.name)
	local tip = {}
	Find(Lines(king), switch).tooltip({ AddLine = function(_, t) tip[#tip + 1] = t end })
	local said = table.concat(tip, "\n")
	assert(said:find(L.ARENA_GAMES_SHOWN, 1, true) and said:find("Brannoc Weald", 1, true), said)
	-- An unnamed councillor's word, and Brannoc's for a game he was not named for: ignored.
	local now = w:As(hc2, hc2.ns.Arena.Now)
	w:As(hc2, function() hc2.ns.Arena.Send("AU", "L", ("a~0~%d"):format(now + 1), { dist = "CHANNEL" }) end)
	w:As(hc, function() hc.ns.Arena.Send("AU", "L", ("b~1~%d"):format(now + 1), { dist = "CHANNEL" }) end)
	w:Run(0)
	eq(Public(lida, "arena"), true, "Idris's word ignored"); eq(Public(lida, "bones"), false, "Brannoc's Bones word ignored")
	eq(select(2, w:As(hc, hc.ns.ArenaRoles.Publish, "bones", true)), "publisher")
	-- The King's own switch, for Bones; a client that logs in later hears it repeated.
	w:As(king, function() king.ns.ArenaHome.rankGame = "bones" end)
	line = Find(Lines(king), L.ARENA_GAMES_SHOW_GAME:format(BONES))
	assert(line and line.onClick, "the King's Bones switch")
	w:As(king, line.onClick)
	w:Run(0)
	eq(Public(lida, "bones"), true)
	local late = w:Client("Parric Stowe")
	eq(Public(late, "bones"), false, "not heard yet")
	w:Run(king.ns.ArenaRoles.REPEAT + 1)
	eq(Public(late, "bones"), true, "the King's client repeats its word")
	eq(Public(late, "arena"), true, "and Brannoc's his")
	-- Named no more: Brannoc's word stops counting everywhere at once, his switch is read-only again.
	named = Find(Lines(king), "Brannoc Weald")
	w:As(king, function() king.ns.ArenaHome.rankGame = "arena" end)
	named = Find(Lines(king), "Brannoc Weald")
	assert(tostring(named.right):find(L.ARENA_YES, 1, true), "named for the Arena")
	w:As(king, named.onClick)
	w:Run(0)
	eq(w:As(lida, lida.ns.ArenaRoles.MayPublish, hc.name, "arena"), false)
	eq(Public(lida, "arena"), false, "his word no longer counts: back to the settings' (off)")
	eq(Public(lida, "bones"), true, "the King's stands")
	eq(Find(Lines(hc), switch).onClick, nil, "read-only again")
	NoErrors(w)
end)

-- The owner's answer was "the King plus named councillors", not "the King plus Stewards": a Steward
-- published every game's ranking unnamed (MayPublish took any Steward) and could name or revoke
-- the publishers himself (T1~J was lent to him). He is a publisher now only when the King names
-- him as a councillor; his own switch is read-only, his AU word and his T1~J are ignored, and the
-- King's character alone names.
test("1.2 the rankings' publish word: a Steward publishes only when the King names him as a councillor; his word and his naming are ignored otherwise", function()
	local w = World.New()
	local king, steward, hc = w:Role("king"), w:Role("steward"), w:Role("councillor")
	local lida = w:Client("Lida Fenn")
	local function May(name, game) return w:As(lida, lida.ns.ArenaRoles.MayPublish, name, game) end
	local function Public(game) return w:As(lida, lida.ns.ArenaHome.RankingsPublic, game) end
	eq(May(steward.name, "arena"), false, "a Steward is no publisher of his own")
	eq(w:As(steward, steward.ns.ArenaHome.MaySetRankings, "arena"), false, "his switch read-only")
	eq(w:As(steward, steward.ns.ArenaHome.NamesPublishers), false, "he names nobody")
	eq(select(2, w:As(steward, steward.ns.ArenaRoles.Publish, "arena", true)), "publisher")
	-- His word on the channel, by hand: ignored on every client.
	local now = w:As(steward, steward.ns.Arena.Now)
	w:As(steward, function() steward.ns.Arena.Send("AU", "L", ("a~1~%d"):format(now + 1), { dist = "CHANNEL" }) end)
	w:Run(0)
	eq(Public("arena"), false, "the Steward's AU ignored")
	-- His naming: refused on his client, and a T1~J from him is no word.
	eq(select(2, w:As(steward, steward.ns.ArenaRoles.SetPublishers, { { name = hc.name, games = { arena = true } } })), "king")
	Word(w, steward, "J", "Brannoc Weald:a")
	eq(May(hc.name, "arena"), false, "a Steward's T1~J names nobody")
	-- The King's names count; the King publishes himself.
	assert(w:As(king, king.ns.ArenaRoles.SetPublishers, { { name = hc.name, games = { bones = true } } }))
	w:Run(0)
	eq(May(hc.name, "bones"), true, "the King's naming")
	eq(May(king.name, "lottery"), true, "the King publishes every game")
	eq(May(steward.name, "bones"), false, "the Steward still not")
	NoErrors(w)
end)

-- The arena's How to play (the owner's call, 2026-09-30): the games' pop-up with four pages; the
-- fee's numbers come from the King's settings (6% of the money won: 4% guild, 2% arbiter) and the
-- worked example adds up.
test("1.1.6 free play guides: permitted fixture retains the arena's four pages and exact fee example", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	eq(a.ns.Compliance.Allows("bet", "fight"), true, "the existing open test fixture exercises retained instructions")
	local fees = w:As(a, function() return UI.HowToParas(3) end)
	assert(fees[1]:find("6%", 1, true) and fees[1]:find("4%", 1, true) and fees[1]:find("2%", 1, true), fees[1])
	local ex = fees[3]
	local Money = a.ns.ArenaHome.Money
	assert(ex:find(Money(100000), 1, true) and ex:find("2.00x", 1, true), ex)
	assert(ex:find(Money(6000), 1, true), "the fee: 6% of the 10g won is 60s: " .. ex)
	assert(ex:find(Money(194000), 1, true), "back: 20g less 60s: " .. ex)
	for k = 1, 4 do assert(#w:As(a, function() return UI.HowToParas(k) end) >= 3, "page " .. k) end
end)

-- The owner, "the mock data is missing": on a test build the screens read the sim's sample data
-- where the real modules have nothing (the showcase), without the sim; a player's client does not.
test("1.2 the showcase: a test build's screens show the sample data where nothing real is there; a player's show nothing", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	local p = w:Client("Lida Fenn")
	w:As(t, function() t.slashes.OLYMPUS("arena") end)
	w:As(p, function() p.slashes.OLYMPUS("arena") end)
	eq(t.Arena.Sim(), false, "not the sim")
	local tr = w:As(t, function() return t.ns.ArenaHome.Data.Rankings("all", "A", 1) end)
	assert(tr and #(tr.rows or {}) > 0, "the test build: sample rankings")
	assert(#(w:As(t, function() return t.ns.ArenaHome.Data.Events() end) or {}) > 0, "and sample events")
	local pr = w:As(p, function() return p.ns.ArenaHome.Data.Rankings("all", "A", 1) end)
	eq(#((pr or {}).rows or {}), 0, "a player's client: nothing made up")
	NoErrors(w)
end)

-- The token portrait (the owner's call, 2026-09-30): one helper; where no unit shows him, his
-- race's portrait where the client has the atlas, else his class's icon.
test("1.2 Kit.Portrait: his race's portrait where the atlas is there, else his class's icon", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Kit = own.ArenaUI.Kit
	local atlas
	local tex = { SetAtlas = function(_, x) atlas = x end, SetTexture = function(self, x) self.file = x end, SetTexCoord = function() end }
	local was = rawget(_G, "C_Texture")
	C_Texture = { GetAtlasInfo = function(x) return x == "raceicon128-orc-male" and {} or nil end }
	local kind = w:As(a, function() return Kit.Portrait(tex, "Parric Stowe", { class = "WARRIOR", race = 2 }) end)
	eq(kind, "race"); eq(atlas, "raceicon128-orc-male")
	atlas = nil
	kind = w:As(a, function() return Kit.Portrait(tex, "Parric Stowe", { class = "WARRIOR", race = 5 }) end)
	eq(atlas, nil, "no atlas for that race here"); eq(kind, "class", "his class's icon")
	C_Texture = was
end)

-- The owner's overflow audit (2026-09-30): a pop-up is as tall as its words; a button grows to its
-- label (never narrower than its words), whatever the language or the name.
test("1.2 the overflow audit: Kit.FitHeight sizes a pop-up from its text; a button grows to a longer label", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Kit = own.ArenaUI.Kit
	local f = { SetHeight = function(self, v) self.h = v end }
	Kit.FitHeight(f, { GetStringHeight = function() return 212.4 end }, 58, 76, 200)
	eq(f.h, 347, "58 + 213 + 76")
	Kit.FitHeight(f, { GetStringHeight = function() return 20 end }, 58, 76, 200)
	eq(f.h, 200, "at least the minimum")
	local fs = { GetStringWidth = function() return 180 end }
	local b = { w = 120, GetFontString = function() return fs end, SetText = function() end, GetWidth = function(self) return self.w end,
		SetWidth = function(self, v) self.w = v end, SetEnabled = function() end, SetScript = function() end, GetText = function() return "" end }
	Kit.SetButton(b, "Parric Stowe-Emberfall 2.28x", true)
	eq(b.w, 200, "grown to 180 and 20")
	fs.GetStringWidth = function() return 40 end
	Kit.SetButton(b, "Bet", true)
	eq(b.w, 200, "never shrunk here")
end)

-- The owner: his own profile and History look lived in on a test build (the showcase): his own
-- sample fights, stakes and stats; never on a player's client.
test("1.2 the showcase: the player's own profile and history have sample data on a test build", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	w:As(t, function() t.slashes.OLYMPUS("arena") end)
	local UI = t.companion.own.ArenaUI
	local m = w:As(t, function() return UI.ProfileModel(nil) end)
	assert(m and m.record and type(m.stats) == "table" and m.stats.bones, "his own record and stats")
	local hist = w:As(t, function() return t.ns.ArenaHome.Data.History({ mine = true }) end)
	assert(#hist >= 8 and #hist <= 12, "8 to 12 fights of his: " .. #hist)
	local staked = 0
	for _, h in ipairs(hist) do if h.stake then staked = staked + 1 end end
	assert(staked > 0, "some staked")
	NoErrors(w)
end)

-- The owner saw thin dashes where the dice wait in the hands on Bones' setup screen: every die is
-- hidden whole (its frame and every texture of it) until it is on the table or in a tray.
test("1.2 Bones: on the setup screen no die draws anything", function()
	local w = FW.New()
	local a = w:Player("Wenna Crale", { testBuild = TestBuild(w) })
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local ok, err = pcall(w.As, w, a, function()
		own.Farkle.Open()
		-- (the test world's Show fires no OnShow: the table's own, which draws it, by hand)
		local win = own.Farkle.Window()
		win:GetScript("OnShow")(win)
	end)
	assert(ok, tostring(err))
	local sides = own.Farkle._.sides
	local seen = 0
	for seat = 1, 2 do
		for _, d in ipairs(sides[seat].dice) do
			seen = seen + 1
			local f = d.f
			eq(f:IsShown() == true, false, "a die's frame")
			for _, t in ipairs({ f.face, f.lit, f.tumble }) do eq(t:IsShown() == true, false, "a die's texture") end
		end
	end
	assert(seen >= 12, "both sides' dice: " .. seen)
end)

test("1.2 P1.8 Bones entry: the full table is an in-world introduction with one Start Playing action, then the fixed Bones matcher", function()
	local w = FW.New()
	local a = w:Player("Wenna Crale", { testBuild = TestBuild(w) })
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local ok, err = pcall(w.As, w, a, function()
		own.Farkle.Open()
		-- The test world's Show does not run scripts; draw exactly what the client draws on show.
		local win = own.Farkle.Window()
		win:GetScript("OnShow")(win)
	end)
	assert(ok, tostring(err))
	local p = own.Farkle._.parts()
	local intro = assert(p.intro, "the full-window Bones introduction")
	assert(intro:IsShown(), "the introduction is the initial Bones surface")
	eq(#intro.actions, 1, "one primary action")
	eq(intro.actions[1], intro.start)
	eq(intro.start:GetText(), a.ns.L.FARKLE_START_PLAYING)
	eq(type(intro.start:GetScript("OnClick")), "function", "Start Playing is wired")
	local visible = table.concat({ intro.kicker:GetText(), intro.title:GetText(), intro.body:GetText(), intro.start:GetText() }, "\n")
	for _, forbidden in ipairs({ "Play to", "Stake", "The House", "Wenna" }) do
		assert(not visible:find(forbidden, 1, true), "intro exposed " .. forbidden)
	end
	assert(not p.help:IsShown(), "the rules popup does not obscure the one-action entry")
	eq(a.ns.ArenaMatch.View().state, "idle", "fresh matcher")
	local opened, rawOpen = 0, own.ArenaUI.OpenFind
	own.ArenaUI.OpenFind = function(...)
		opened = opened + 1
		return rawOpen(...)
	end

	-- Exercise the actual handoff: the button opens the existing fixed-game matcher, whose filters
	-- and protocol remain ArenaMatch's single state machine, inside this window. (Until test 32 the
	-- window closed here and the sheet opened on its own; the owner: the search is a component of
	-- the Bones window, which stays: tests/arena/farkle-board.lua's in-window Find case.)
	-- This world uses the core frame stand-in (whose Click method is intentionally a no-op), so
	-- invoke the real OnClick script installed on the actual button.
	w:As(a, function() intro.start:GetScript("OnClick")(intro.start, "LeftButton") end)
	eq(opened, 1, "the matcher opened its fixed-game filters")
	local find = assert(own.ArenaUI.FindFrame(), "the existing Find sheet opened")
	assert(find:IsShown(), "the search/filter sheet is visible")
	assert(own.Farkle.Window():IsShown(), "the Bones window stays open under its Find sheet")
	eq(find:GetParent(), own.Farkle.Window(), "the sheet is the window's component")
	eq(find.opts.game, "b")
	eq(rawget(find, "game"), nil, "no mixed Arena/Bones selector")
	NoErrors(w)
end)

-- /oly games photos (the owner's slides): a test build's tour of the games' screens, its rolls
-- scripted (RandomRoll handed straight to the game's reader, never to chat), put back at the end;
-- refused on a player's client.
test("1.2 /oly games photos: a test build's tour, its rolls scripted and RandomRoll put back; a player's client refuses", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	local p = w:Client("Lida Fenn")
	local rolled = 0
	local was = rawget(_G, "RandomRoll")
	RandomRoll = function() rolled = rolled + 1 end
	local mine = RandomRoll
	w:As(p, function() p.slashes.OLYMPUS("games photos") end)
	eq(Printed(p, p.companion.own.ArenaUI and p.ns.L.ARENA_GAMES_PHOTOS_REFUSED or "?") > 0 or p.companion.loaded ~= true, true, "refused")
	-- (the Olympus window itself is not built in the test world: its tab choice is a no-op here; a
	-- step that fails ends the tour, so the rest runs only when every step works)
	t.ns.UI.SelectTab = function() end
	w:As(t, function() t.slashes.OLYMPUS("games photos") end)
	eq(t.companion.own.ArenaUI.Kit.PhotoStaged(), true, "the windows on black while it runs")
	local shots = 0
	local wasShot = rawget(_G, "Screenshot")
	Screenshot = function() shots = shots + 1 end
	w:Run(200)
	Screenshot = wasShot
	eq(RandomRoll, mine, "RandomRoll put back")
	eq(t.companion.own.ArenaUI.Kit.PhotoStaged(), false, "the black stage taken away at the end")
	eq(rolled, 0, "nothing rolled for real")
	assert(shots >= 17, "a shot a step: " .. shots .. " " .. tostring(t.companion.own.ArenaUI.lastPhotosError))
	eq(Printed(t, t.ns.L.ARENA_GAMES_PHOTOS_DONE:format(shots)), 1, "done said")
	RandomRoll = was
end)

-- (The 1.1.6 base: the gamepad gate's "photo" covers the companion's tours too, now that the audit
-- reads Olympus_Arena/.) With the gamepad UI on, a test build's tour does not start: RandomRoll
-- stays the game's, no shot, no black stage.
test("1.2 /oly games photos with the gamepad UI on: refused, RandomRoll left alone", function()
	local w = World.New()
	local t = w:Client("Wenna Crale", { testBuild = TestBuild(w) })
	local was = rawget(_G, "RandomRoll")
	local mine = function() end
	RandomRoll = mine
	-- (the tour's own entry: with the gamepad UI no /oly command runs at all, the gate's "slash")
	local own = w:As(t, function() return H.LoadCompanion(t.ns) end)
	H.WithGamepadUI(true, function()
		w:As(t, function() eq(own.ArenaUI.GamesPhotos(), false, "refused") end)
	end)
	eq(RandomRoll, mine, "the game's RandomRoll untouched")
	eq(own.ArenaUI.Kit.PhotoStaged(), false, "no black stage")
	eq(Printed(t, t.ns.L.PHOTO_GAMEPAD), 1, "the player told why")
	RandomRoll = was
end)

-- The owner, 2026-09-30: Check version and Ask to update from the guild's rows too: the guild
-- rosters' menus are hooked (this client's: COMMUNITIES_GUILD_MEMBER and COMMUNITIES_WOW_MEMBER;
-- the old Guild window's GUILD), and a right-click on an Olympus window row that names a player
-- opens a menu of the same lines.
test("1.2 the guild's rows: the rosters' menus hooked; an Olympus row's right-click opens the player menu's lines", function()
	-- (the harness's own client: it loads 1.1.2's PlayerMenu.lua and Versions.lua)
	local ns = H.ns
	local PM = ns.PlayerMenu
	local which = {}
	for _, x in ipairs(PM.WHICH) do which[x] = true end
	assert(which.COMMUNITIES_GUILD_MEMBER and which.COMMUNITIES_WOW_MEMBER and which.GUILD, "the guild rosters' menus")
	-- the row menu: the client's own context menu, the same lines for the name
	local built, owner
	local was = rawget(_G, "MenuUtil")
	MenuUtil = { CreateContextMenu = function(o, fn)
		owner = o
		local root = { items = {} }
		function root:CreateTitle(t) self.items[#self.items + 1] = "title:" .. tostring(t) return {} end
		function root:CreateButton(t) self.items[#self.items + 1] = "button:" .. tostring(t) return { SetEnabled = function() end, SetTooltip = function() end } end
		function root:CreateDivider() return {} end
		fn(o, root)
		built = root.items
	end }
	local ok
	H.WithStub("IsMember", function() return true end, function() ok = PM.OpenFor("row", "Parric Stowe-Emberfall") end)
	MenuUtil = was
	eq(ok, true); eq(owner, "row")
	local text = table.concat(built or {}, " | ")
	assert(text:find("button:" .. ns.L.VERSION_CHECK, 1, true), "Check version: " .. text)
	assert(text:find("button:" .. ns.L.VERSION_ASK, 1, true), "Ask to update: " .. text)
	eq(PM.OpenFor("row", nil), false, "a row with no player: nothing")
end)
