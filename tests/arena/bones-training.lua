-- Bones' training through the real board, rules and server-line fixture.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

local function Training(dropFinished)
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { companion = {} })
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	local function As(fn, ...) return w:As(a, fn, ...) end
	assert(As(a.ns.Arena.LoadUI))
	local B = a.ns.Arena.ui.FarkleBoard
	local function Parts() return B._.parts() end
	local function V() return As(a.ns.FarkleTable.View, B._.S.id) end
	local function Click(b) assert(As(a.K.UserClick, b)) end
	local function Wait()
		local stop = w.clock + 8
		repeat
			w:Run(0.05)
			assert(w.clock < stop, "training animations did not finish")
		until not As(B.Busy, B._.S.id)
	end
	As(B.StartPractice, 10000, true)
	if Parts().help and Parts().help:IsShown() then Click(Parts().help.ok) end
	local encoded = a.ns.FarkleRules.Encode({ 1, 1, 1, 1, 1, 1 })
	w:QueueRoll(a.name, encoded)
	Click(Parts().primary)
	Wait()
	for turn = 1, 12 do
		eq(V().expect.phase, "keep")
		for _, i in ipairs(B._.sides[1].play) do Click(B._.sides[1].dice[i].f) end
		if dropFinished and turn == 5 then
			-- A completion notification lost by the client must not strand the table.
			local group = B._.sides[1].dice[1].f.move.g
			local setScript = group.SetScript
			group.SetScript = function(self, name, fn)
				if name == "OnFinished" then
					if dropFinished == "late" then
						local finish = fn
						fn = function() w:Timer(a, 2, nil, finish, "delayed completion") end
					else fn = nil end
				end
				return setScript(self, name, fn)
			end
		end
		w:QueueRoll(a.name, encoded)
		local count = #w:Rolls(a.name)
		Click(Parts().primary)
		eq(#w:Rolls(a.name), count + 1, "Keep and roll asks the server once")
		Wait()
		eq(V().expect.phase, "keep")
		eq(#B._.sides[1].play, 6)
	end
	local count, hash = #w:Rolls(a.name), a.ns.FarkleRules.Hash(V().game)
	w:Run(3)
	eq(#w:Rolls(a.name), count, "late completion never asks for another roll")
	eq(a.ns.FarkleRules.Hash(V().game), hash, "late completion never repeats a move")
	eq(B._.S.flying[1], 0, "each throw completes exactly once")
	eq(As(B.Busy, B._.S.id), false)
	for _, i in ipairs(B._.sides[1].play) do Click(B._.sides[1].dice[i].f) end
	Click(Parts().bank)
	local stop = w.clock + 60
	while not V().over do
		w:Run(0.05)
		assert(w.clock < stop, "the training match did not complete")
	end
	eq(V().game.reason, "target")
	eq(V().winner, 1)
	local games = As(a.ns.ArenaLedger.MyGames)
	eq(games[1].g, "p", "a completed lesson is recorded separately from plain practice")
	eq(games[1].how, "t", "completion reached the target, not a concession")
	for _, e in ipairs(a.errors) do error(e) end
	for _, e in ipairs(a.K.errors) do error(e) end
end

test("1.1.6 Bones training: repeated Keep and roll hot dice remains playable", function() Training(false) end)
test("1.1.6 Bones training: lost animation completion cannot strand Keep and roll", function() Training(true) end)
test("1.1.6 Bones training: delayed animation completion does not duplicate Keep and roll", function() Training("late") end)

test("1.1.6 Bones training: old completion cannot mutate a closed board or a new match", function()
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA, { companion = {} })
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	local function As(fn, ...) return w:As(a, fn, ...) end
	assert(As(a.ns.Arena.LoadUI))
	local B = a.ns.Arena.ui.FarkleBoard
	As(B.StartPractice, 10000, true)
	local p = B._.parts()
	if p.help and p.help:IsShown() then assert(As(a.K.UserClick, p.help.ok)) end
	w:QueueRoll(a.name, a.ns.FarkleRules.Encode({ 1, 2, 3, 4, 5, 6 }))
	assert(As(a.K.UserClick, p.primary))
	w:Run(0.4)
	local d = B._.sides[1].dice[1]
	local finish = assert(d.f.move.g.scripts.OnFinished)
	As(B.Close)
	local x, y, moving, where = d.x, d.y, d.moving, d.where
	As(finish)
	eq(d.x, x); eq(d.y, y); eq(d.moving, moving); eq(d.where, where)
	eq(p.win:IsShown(), false, "old callbacks never reopen the board")
	local id = As(a.ns.FarkleTable.Practice, { target = 10000, first = 1, learn = true })
	assert(id); As(B.Show, id)
	x, y, moving, where = d.x, d.y, d.moving, d.where
	local hash = a.ns.FarkleRules.Hash(As(a.ns.FarkleTable.View, id).game)
	As(finish); w:Run(2)
	eq(d.x, x); eq(d.y, y); eq(d.moving, moving); eq(d.where, where)
	eq(a.ns.FarkleRules.Hash(As(a.ns.FarkleTable.View, id).game), hash)
	eq(B._.S.id, id); eq(B._.S.flying[1], 0)
	for _, e in ipairs(a.errors) do error(e) end
	for _, e in ipairs(a.K.errors) do error(e) end
end)
