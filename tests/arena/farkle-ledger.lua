-- 1.1.6, Bone Throw between players without stakes, and the games' ledger (ArenaLedger.lua's AY,
-- the owner's ask of 2026-10-05: "a ledger of every game, for me, the council and the King to see,
-- besides each player seeing his own"). On the 1.1.6 package's TOC (without the files only the bets
-- need, scripts/bets-only.txt) and the compliance gate as it ships: two players play a game for fun;
-- the auditors (the King's character, a High Councillor, and the author's own character: a signed
-- arbiter with "+a" in the test council) get its record from both players and see it on the games'
-- page (Every game), a member who is no auditor gets nothing; each player sees his own game under
-- Bones' Your games and on the games' page (his own). The other kinds of games:
-- tests/arena/games-ledger.lua.
-- On the test world (tests/arena/lib/world.lua) with the table's additions
-- (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
-- A module of a client, its functions run as that client.
local function M(w, c, name)
	return setmetatable({}, { __index = function(_, k)
		local v = c.ns[name][k]
		if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
		return v
	end })
end
local function Roll(c, dice) return (c.ns.FarkleRules.Encode(dice)) end
local ONE_FIVE = { 1, 5, 2, 3, 4, 6 } -- a 1 and a 5 (150), positions 1 and 2

-- The core's arena files of the 1.1.6 package (scripts/package.sh --release116): the TOC's, less
-- the files scripts/bets-only.txt names.
local function Files116()
	local gone = {}
	for line in io.lines(H.ROOT .. "scripts/bets-only.txt") do
		local file = line:gsub("\r$", ""):match("^Olympus/([%w_]+)%.lua$")
		if file then gone[file] = true end
	end
	local out = {}
	for _, f in ipairs(World.ARENA_FILES) do if not gone[f] then out[#out + 1] = f end end
	return out
end

-- The 1.1.6 world: two players with their companion's saved data (a table of their own, handed to
-- the companion when a test opens its screens; o.arbiter: a signed arbiter at the table too, with
-- his), the King, a High Councillor, the author's own character and a member, every auditor's
-- hello heard (40 s after login; o.offline names one logged out before). o.open: the gate a build
-- that allows wagers has (the test row: arbiters exist there, never in 1.1.6).
local function Ledger116(o)
	o = o or {}
	local w = FW.New({ compliance = not o.open and "shipped" or nil, arenaFiles = Files116() })
	local a = w:Player(N.fighterA)
	local b = w:Player(N.fighterB)
	local king = w:Role("king", { companion = { state = "missing" } })
	local councillor = w:Role("councillor", { companion = { state = "missing" } })
	local author = w:Role("author", { companion = { state = "missing" } })
	local member = w:Client(N.bettor1, { companion = { state = "missing" } })
	local arb = o.arbiter and w:Player(N.arbiter) or nil
	local players = { a, b, arb }
	for _, c in ipairs(players) do
		c.heavyDB = {}
		w:As(c, function() c.ns.Arena.AttachHeavy(c.heavyDB) c.ns.Arena.SetRules(true) end)
	end
	w:Group(players)
	w:AtInn(a.name, b.name, arb and arb.name or nil)
	if o.offline then w:Logout(o.offline(w, { king = king, councillor = councillor, author = author })) end
	w:Run(41)
	return w, { a = a, b = b, arb = arb, king = king, councillor = councillor, author = author, member = member }
end

-- A game without a stake (judged by arb when given): the opening (the host first), the host banks
-- 150, the guest concedes. Returns the table's id.
local function Play(w, a, b, arb)
	local FTa, FTb = M(w, a, "FarkleTable"), M(w, b, "FarkleTable")
	local id = assert(FTa.Create({ guest = b.name, target = 2000, mode = arb and "a" or "d", arbiter = arb and arb.name or nil }))
	w:Run(0)
	assert(FTb.Answer(id, true))
	w:Run(0)
	if arb then
		assert(M(w, arb, "FarkleTable").AnswerArbiter(id, true))
		w:Run(0)
	end
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	FTa.Roll(id); FTb.Roll(id)
	w:Run(0)
	eq(a.ns.FarkleTable.Get(id).state, "play")
	w:QueueRoll(a.name, Roll(a, ONE_FIVE))
	FTa.Roll(id)
	w:Run(0)
	assert(FTa.Keep({ 1, 2 }, "b", id))
	w:Run(0)
	assert(FTb.Concede(id))
	w:Run(10)
	return id
end

local function Targets(w, from)
	local out = {}
	for _, s in ipairs(w:Sent({ from = from, type = "AY" })) do out[#out + 1] = s.target:lower() end
	table.sort(out)
	return table.concat(out, ", ")
end
local function Names(...)
	local out = {}
	for _, c in ipairs({ ... }) do out[#out + 1] = c.name:lower() end
	table.sort(out)
	return table.concat(out, ", ")
end
local function Find(lines, text)
	for _, l in ipairs(lines) do
		if tostring(l.text or ""):find(text, 1, true) or tostring(l.right or ""):find(text, 1, true) then return l end
	end
	return nil
end
local function Keys(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.key end
	return table.concat(out, ",")
end
-- The games' page (a staff page every member opens) on a scope, its lines.
local function GamesLines(UI, scope)
	UI.ShowGames(scope)
	for _, e in ipairs(UI.StaffTabs()) do
		if e.key == "staff.games" then return e.spec.lines({ key = "staff.games" }) end
	end
	error("no games' page")
end
local function Ledger(w, c) return M(w, c, "ArenaLedger").AllGames() end

print("1.1.6: Bone Throw between players without stakes, and the games' ledger")

test("1.1.6 Bones ledger: on the 1.1.6 package, a game for fun between two players reaches the King, a High Councillor and the author's own character from both players, agreed; a member gets nothing and sees only his own games", function()
	local w, c = Ledger116()
	local a, b = c.a, c.b
	eq(a.ns.Markets, nil, "the 1.1.6 package: no markets")
	local id = Play(w, a, b)
	local g = a.ns.FarkleTable.Get(id).game
	eq(g.over, true); eq(g.winner, 1); eq(g.reason, "concede")
	eq(a.ns.FarkleTable.Get(id).stake, 0, "no stake")
	eq(a.ns.FarkleTable.Get(id).mode, "T", "the King's live switch is off: a rehearsal's mode, as in 1.1.6")
	-- Both players told every auditor heard, and nobody else.
	local auditors = Names(c.king, c.councillor, c.author)
	eq(Targets(w, a), auditors)
	eq(Targets(w, b), auditors)
	eq(#w:Sent({ type = "AY", dist = "CHANNEL" }), 0, "never on the channel")
	for _, aud in ipairs({ c.king, c.councillor, c.author }) do
		local list = Ledger(w, aud)
		eq(#list, 1, aud.name)
		local e = list[1]
		eq(e.id, id); eq(e.g, "b"); eq(e.game, "bones"); eq(e.p1:lower(), a.name:lower()); eq(e.p2:lower(), b.name:lower()); eq(e.arb, nil)
		eq(e.winner:lower(), a.name:lower()); eq(e.s1, 150); eq(e.s2, 0); eq(e.how, "o", "conceded")
		assert(e.x:find("^d%.0%.2%."), "a direct table, no stake, to 2000: " .. tostring(e.x))
		eq(e.reports, 2); eq(e.state, "agreed", aud.name .. ": both players' words agree")
		eq(e.mode, "T")
	end
	eq(#Ledger(w, c.member), 0, "a member is told nothing")
	eq(c.member.rdb.arenaGames and c.member.rdb.arenaGames.gamesLedger, nil, "and keeps no ledger")
	-- The auditor's screens: the games' page on Every game, its row; the Games tab's staff line.
	local own = w:As(c.king, function() return H.LoadCompanion(c.king.ns) end)
	local UI, L = own.ArenaUI, c.king.ns.L
	w:As(c.king, function()
		eq(Keys(UI.SectionPanes("farkle")), "bone.play,bone.live,bone.history", "no Bones-only ledger pane: the games' page holds every game")
		local lines = GamesLines(UI, "all")
		local row = assert(Find(lines, L.ARENA_BONE_LEDGER_WON:format(UI.Kit.Name(a.name), UI.Kit.Name(b.name))), "who beat whom")
		assert(row.text:find(L.ARENA_GAME_B, 1, true), row.text)
		assert(row.right:find("150-0", 1, true), row.right)
		assert(row.right:find(L.ARENA_BONE_LEDGER_AGREED, 1, true), row.right)
		assert(Find(c.king.ns.ArenaHome.TabLines(), L.ARENA_GAMES_EVERY_GAME:format(1)), "the Games tab's staff link")
	end)
	local mown = w:As(c.member, function() return H.LoadCompanion(c.member.ns) end)
	w:As(c.member, function()
		eq(Keys(mown.ArenaUI.SectionPanes("farkle")), "bone.play,bone.live,bone.history")
		eq(Find(c.member.ns.ArenaHome.TabLines(), L.ARENA_GAMES_EVERY_GAME:format(0)), nil, "a member: no Every game")
		assert(Find(c.member.ns.ArenaHome.TabLines(), L.ARENA_GAMES_MINE), "his own games' link")
		-- (asking for everyone's on his client gives his own: none)
		local lines = GamesLines(mown.ArenaUI, "all")
		eq(Find(lines, UI.Kit.Name(a.name)), nil, "no game of others")
		assert(Find(lines, L.ARENA_GAMES_NONE_MINE), "his own, none")
	end)
	NoErrors(w)
end)

-- The Your games pane read fields the history never wrote (won, score) and listed the oldest
-- first, and only the live realm's games (L): every game of a player read "Lost" with no score,
-- and in 1.1.6 (the King's live switch off: every game in T) the pane said "No games yet".
-- (Practice against the House, never sent before, is a game of the ledger now: the owner's ask of
-- 2026-10-05 names every game, the House's included.)
test("1.1.6 Bones ledger: each player sees his own games under Your games, newest first: won or lost, against whom, the score from his side; the House's practice there too, and in the ledger as a game against the House", function()
	local w, c = Ledger116()
	local a, b = c.a, c.b
	local id = Play(w, a, b)
	-- Practice against the House afterwards: his, told to the auditors as a game against the House.
	local before = #w:Sent({ from = a, type = "AY" })
	local house = assert(M(w, a, "FarkleTable").Practice({ target = 2000, first = 1 }))
	w:Run(0)
	assert(M(w, a, "FarkleTable").Concede(house))
	w:Run(10)
	eq(#w:Sent({ from = a, type = "AY" }), before + 3, "the House's game, to the three auditors")
	local list = Ledger(w, c.king)
	eq(#list, 2)
	eq(list[1].g, "h"); eq(list[1].p1:lower(), a.name:lower()); eq(list[1].p2, nil); eq(list[1].w, "2", "the House won (he conceded)")
	eq(list[1].state, "one", "a game played alone: one word")
	local mine = M(w, a, "FarkleTable").MyGames()
	eq(#mine, 2); eq(mine[1].practice, true, "newest first"); eq(mine[2].id, id)
	local games = M(w, a, "ArenaLedger").MyGames()
	eq(#games, 2); eq(games[1].g, "h"); eq(games[1].result, "L"); eq(games[2].id, id); eq(games[2].result, "W")
	for _, p in ipairs({ { a, b, "ARENA_WON", "150-0", 2 }, { b, a, "ARENA_LOST", "0-150", 1 } }) do
		local me, other, word, score, rows = p[1], p[2], p[3], p[4], p[5]
		local own = w:As(me, function() return H.LoadCompanion(me.ns, { db = me.heavyDB }) end)
		local UI, L = own.ArenaUI, me.ns.L
		w:As(me, function()
			eq(Keys(UI.SectionPanes("farkle")), "bone.play,bone.live,bone.history", "a player who is no auditor")
			local lines = UI.Pane("bone.history").lines({ key = "bone.history" })
			eq(#lines, 1 + rows, me.name)
			local row = assert(Find(lines, L.ARENA_VS_SHORT:format(UI.Kit.Name(other.name))), me.name .. ": the game against " .. other.name)
			assert(row.text:find(L[word], 1, true), me.name .. ": " .. row.text)
			eq(row.right, score, me.name)
			if me == a then
				assert(lines[2].text:find(L.ARENA_VS_SHORT:format(UI.Kit.Name(L.FARKLE_HOUSE)), 1, true), "the House's game first: " .. lines[2].text)
				eq(lines[3], row, "then the game against the player")
			end
		end)
	end
	NoErrors(w)
end)

test("1.1.6 Bones ledger: an auditor offline at the game's end gets it from the players at his hello after his login, once", function()
	local w, c = Ledger116({ offline = function(_, cast) return cast.councillor end })
	local a, b = c.a, c.b
	local id = Play(w, a, b)
	eq(#w:Sent({ type = "AY", to = c.councillor.name }), 0, "offline: nothing reached him")
	eq(#Ledger(w, c.king), 1, "the King, online, has it")
	w:Login(c.councillor)
	w:Run(45)
	eq(#w:Sent({ from = a, type = "AY", to = c.councillor.name }), 1, "the host told him at his hello")
	eq(#w:Sent({ from = b, type = "AY", to = c.councillor.name }), 1, "and the guest")
	-- (the games' clerk, the author here, passes on both words he holds; the King never relays)
	eq(#w:Sent({ from = c.author, type = "AY", to = c.councillor.name }), 2, "the games' clerk passed on both words")
	eq(#w:Sent({ from = c.king, type = "AY", to = c.councillor.name }), 0)
	local list = Ledger(w, c.councillor)
	eq(#list, 1); eq(list[1].id, id); eq(list[1].state, "agreed")
	-- His next hello (every 15 minutes): nothing again.
	local told = #w:Sent({ type = "AY", to = c.councillor.name })
	w:Run(900)
	eq(#w:Sent({ type = "AY", to = c.councillor.name }), told, "told once")
	NoErrors(w)
end)

test("1.1.6 Bones ledger: the auditor takes a game's word only by whisper from a player or the arbiter it names; a player's other word marks it differ; a member who is no auditor keeps nothing", function()
	local w, c = Ledger116()
	local a, b = c.a, c.b
	local id = Play(w, a, b)
	local king, member = c.king, c.member
	local LGk = M(w, king, "ArenaLedger")
	local body = w:Sent({ from = a, type = "AY", to = king.name })[1].msg:match("^AY~T%d+~(.*)$")
	assert(body, "the host's record")
	local f = {}
	for part in (body .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	eq(#f, 13)
	-- The guest's other word (he won), said by a member (no player of it): refused; by the guest on
	-- the channel: dropped; a member told it: keeps nothing; passed on by a member as the guest's:
	-- refused (only an auditor relays).
	local claim = { unpack(f) }
	claim[8], claim[9], claim[10] = "2", "0", king.ns.Arena.B36(2000)
	claim = table.concat(claim, "~")
	eq(select(2, LGk.TakeGame(member.name, "T", claim)), "sender")
	assert(w:As(b, b.ns.Arena.Send, "AY", "T", claim, { dist = "CHANNEL" }))
	w:Run(5)
	eq(#w:Sent({ from = b, type = "AY", dist = "CHANNEL" }), 1, "it went on the channel")
	eq(LGk.AllGames()[1].state, "agreed", "a word on the channel is not taken")
	eq(select(2, M(w, member, "ArenaLedger").TakeGame(b.name, "T", claim)), "auditor")
	eq(member.rdb.arenaGames and member.rdb.arenaGames.gamesLedger, nil)
	local relayed = claim:gsub("~[^~]*$", "~" .. b.short)
	eq(select(2, LGk.TakeGame(member.name, "T", relayed)), "relay")
	-- Out of shape, or ahead of the clock: refused.
	local bad = { unpack(f) }
	bad[8] = "q"
	eq(select(2, LGk.TakeGame(a.name, "T", table.concat(bad, "~"))), "shape")
	eq(select(2, LGk.TakeGame(a.name, "T", body .. "~-")), "shape", "a field too many")
	local ahead = { unpack(f) }
	ahead[3] = king.ns.Arena.B36(w:As(king, king.ns.Arena.Now) + 3600)
	eq(select(2, LGk.TakeGame(a.name, "T", table.concat(ahead, "~"))), "time")
	-- The same id with other players: the first kept.
	local other = { unpack(f) }
	other[6] = member.short
	eq(select(2, LGk.TakeGame(a.name, "T", table.concat(other, "~"))), "conflict")
	-- The guest (a modified client) whispers he won: the King's ledger says the words differ.
	assert(w:As(b, b.ns.Arena.Send, "AY", "T", claim, { to = king.name }))
	w:Run(5)
	local e = LGk.AllGames()[1]
	eq(e.id, id); eq(e.state, "differ"); eq(e.winner:lower(), a.name:lower(), "the host's word is the one shown")
	local own = w:As(king, function() return H.LoadCompanion(king.ns) end)
	w:As(king, function()
		local lines = GamesLines(own.ArenaUI, "all")
		assert(Find(lines, king.ns.L.ARENA_BONE_LEDGER_DIFFER), "the row says the words differ")
	end)
	NoErrors(w)
end)

-- (1.1.6 has no arbiters without a wager, Compliance.Arbiters: such a table is refused there. The
-- arbiter's word in the games' ledger stays for a build the gate allows, 2.0's.)
test("1.1.6 Bones ledger: a game an arbiter judges: refused as 1.1.6 ships; where the gate allows arbiters, the auditors get all three words, agreed; the arbiter's own games say he judged it", function()
	local w0, c0 = Ledger116({ arbiter = true })
	eq(select(2, M(w0, c0.a, "FarkleTable").CanCreate({ guest = c0.b.name, target = 2000, mode = "a", arbiter = c0.arb.name })), "compliance")
	NoErrors(w0)
	local w, c = Ledger116({ arbiter = true, open = true })
	local a, b, arb = c.a, c.b, c.arb
	eq(w:As(arb, arb.ns.ArenaRoles.Auditor, arb.name, "T"), false, "a signed arbiter without +a is no auditor")
	local id = Play(w, a, b, arb)
	eq(a.ns.FarkleTable.Get(id).kind, "a"); eq(a.ns.FarkleTable.Get(id).stake, 0)
	eq(Targets(w, arb), Names(c.king, c.councillor, c.author), "the arbiter told every auditor too")
	local e = Ledger(w, c.author)[1]
	eq(e.id, id); eq(e.arb:lower(), arb.name:lower()); eq(e.reports, 3); eq(e.state, "agreed")
	eq(M(w, arb, "ArenaLedger").MyGames()[1].result, "J", "his own games: judged")
	local own = w:As(arb, function() return H.LoadCompanion(arb.ns, { db = arb.heavyDB }) end)
	local UI, L = own.ArenaUI, arb.ns.L
	w:As(arb, function()
		local lines = UI.Pane("bone.history").lines({ key = "bone.history" })
		local row = assert(Find(lines, L.ARENA_BONE_LEDGER_PAIR:format(UI.Kit.Name(a.name), UI.Kit.Name(b.name))), "the game he judged")
		assert(row.text:find(L.ARENA_BONE_JUDGED, 1, true), row.text)
		eq(row.right, "150-0")
	end)
	NoErrors(w)
end)
