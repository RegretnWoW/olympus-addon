-- 1.1.6, the games' ledger (ArenaLedger.lua's AY; the owner's ask of 2026-10-05: "a ledger of every
-- game, for me, the council and the King to see, besides each player seeing his own"): every kind
-- of game without a bet goes into it. A duel and a fight its arbiter judges, Bones against the
-- House and the lesson (the rules' tips), the Lottery's practice draws (free practice tickets);
-- a tournament's and a Fight Night's bouts named as such. Each player sees his own games; the
-- auditors (the King's character, a High Councillor, the author's own character: a signed arbiter
-- with "+a" in the test council) every game, with a search and the filters (player, game, date);
-- nobody else (a member, a rehearsal's stand-in King). An auditor offline gets a game later from
-- the games' clerk. The privacy page says so in one line. No message of a bet goes. On the 1.1.6
-- package's TOC (without scripts/bets-only.txt's files), the compliance gate as it ships, the
-- King's live switch off (every game in T, as in 1.1.6). Bones between players:
-- tests/arena/farkle-ledger.lua. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function M(w, c, name) return W3.M(w, c, name) end
local function Find(lines, text)
	for _, l in ipairs(lines) do
		if tostring(l.text or ""):find(text, 1, true) or tostring(l.right or ""):find(text, 1, true) then return l end
	end
	return nil
end
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
-- The games' page's spec (a staff page every member opens).
local function GamesSpec(UI)
	for _, e in ipairs(UI.StaffTabs()) do if e.key == "staff.games" then return e.spec end end
	error("no games' page")
end
-- No message of a bet's type went (Compliance.WIRE), from anyone.
local function NoBets(w, c)
	local wire = c.ns.Compliance.WIRE
	for _, s in ipairs(w.sent) do
		local kind = s.msg:sub(1, 2)
		if wire[kind] then error("a bet's message went: " .. s.msg, 2) end
	end
end

-- The 1.1.6 world: two players (their companion's saved data handed over), the King, a High
-- Councillor, the author's own character, the signed arbiter and a member; every hello heard (40 s
-- after login). o.offline(cast) names one logged out first.
local function World116(o)
	o = o or {}
	local w = FW.New({ compliance = "shipped", arenaFiles = Files116() })
	local a = w:Player(N.fighterA)
	local b = w:Player(N.fighterB)
	local cast = { a = a, b = b }
	cast.king = w:Role("king", { companion = { state = "missing" } })
	cast.councillor = w:Role("councillor", { companion = { state = "missing" } })
	cast.author = w:Role("author", { companion = { state = "missing" } })
	cast.arb = w:Player(N.arbiter)
	cast.member = w:Client(N.bettor1, { companion = { state = "missing" } })
	for _, c in ipairs({ a, b, cast.arb }) do
		c.heavyDB = {}
		w:As(c, function() c.ns.Arena.AttachHeavy(c.heavyDB) end)
	end
	for _, c in ipairs(w.clients) do W3.Rules(w, c) end
	w:Group({ a, b, cast.arb })
	w:AtInn(a.name, b.name)
	if o.offline then w:Logout(o.offline(cast)) end
	w:Run(41)
	return w, cast
end
local function Auditors(cast) return { cast.king, cast.councillor, cast.author } end
local function Rows(w, c) return M(w, c, "ArenaLedger").AllGames() end

-- A duel without a stake: a's challenge, b's yes, the game's duel line (winner first). Its fid.
local function Duel(w, a, b, winner, loser)
	local oid = assert(M(w, a, "ArenaFights").Challenge(b.name, { bo = 1 }))
	w:Run(0)
	assert(M(w, b, "ArenaFights").Answer(oid, true))
	w:Run(0)
	W3.Duel(w, { a, b }, winner, loser)
	w:Run(0)
	return oid
end
local function Final(w, c, fid)
	local f = c.ns.ArenaFights.Find("fights", fid)
	return f and w:As(c, c.ns.ArenaFights.State, f) == "F", f
end

print("1.1.6: the games' ledger, every kind of game")

test("1.1.6 games ledger: a duel without a stake: each fighter sees his own game, won or lost; the King, a councillor and the author get both fighters' words, agreed; a member nothing; no bet's message", function()
	local w, c = World116()
	local a, b = c.a, c.b
	eq(a.ns.Markets, nil, "the 1.1.6 package")
	local fid = Duel(w, a, b, a, b)
	w:Run(5) -- (the records go on the low lane)
	local okA, f = Final(w, a, fid)
	assert(okA, "final on the challenger's client"); assert((Final(w, b, fid)), "and on the other's")
	eq(f.mode, "T", "the King's live switch is off: a rehearsal's mode, as in 1.1.6")
	eq(f.stake, nil, "no stake")
	local aSide = f.A.name:lower() == a.name:lower() and "1" or "2"
	for _, aud in ipairs(Auditors(c)) do
		local list = Rows(w, aud)
		eq(#list, 1, aud.name)
		local e = list[1]
		eq(e.id, fid); eq(e.g, "d"); eq(e.game, "arena"); eq(e.w, aSide); eq(e.winner:lower(), a.name:lower())
		eq(e.how, "K", "a knockout"); eq(e.reports, 2); eq(e.state, "agreed", aud.name); eq(e.mode, "T")
	end
	eq(#w:Sent({ type = "AY", dist = "CHANNEL" }), 0, "never on the channel")
	eq(#w:Sent({ type = "AY", to = c.member.name }), 0, "nothing to a member")
	eq(#Rows(w, c.member), 0)
	eq(c.member.rdb.arenaGames and c.member.rdb.arenaGames.gamesLedger, nil, "a member keeps no ledger")
	local mineA, mineB = M(w, a, "ArenaLedger").MyGames(), M(w, b, "ArenaLedger").MyGames()
	eq(#mineA, 1); eq(mineA[1].result, "W"); eq(#mineB, 1); eq(mineB[1].result, "L")
	eq(#M(w, c.member, "ArenaLedger").MyGames(), 0, "the member played nothing")
	NoBets(w, a)
	NoErrors(w)
end)

test("1.1.6 games ledger: a public fight its signed arbiter judges, without a stake: the three words reach the auditors, agreed; a tournament's bout and a Fight Night's are named as such", function()
	local w, c = World116()
	local a, b, arb = c.a, c.b, c.arb
	local AF = M(w, arb, "ArenaFights")
	local fid = assert(AF.New({ A = a.name, B = b.name, bo = 1 }))
	assert(AF.Announce(fid))
	w:Run(0)
	M(w, a, "ArenaFights").Accept(fid)
	M(w, b, "ArenaFights").Accept(fid)
	w:Run(0)
	W3.Stand(arb, 100, 100); W3.Stand(a, 110, 100); W3.Stand(b, 100, 120)
	W3.Sees(arb, { [a] = true, [b] = true })
	assert(AF.Call(fid))
	w:Run(0)
	M(w, a, "ArenaFights").Here(fid); M(w, b, "ArenaFights").Here(fid)
	w:Run(1)
	assert(AF.Bell(fid))
	w:Run(0)
	local f = AF.Find("fights", fid)
	w:Run(math.max(0, f.lockAt - w.clock))
	W3.Duel(w, { arb, a, b }, b, a)
	w:Run(0)
	w:Run(arb.ns.ArenaFights.GRACE_HELD + arb.ns.ArenaFights.FINAL_SLACK + 5)
	for _, x in ipairs({ arb, a, b }) do assert((Final(w, x, fid)), x.name .. ": final") end
	for _, aud in ipairs(Auditors(c)) do
		local e = Rows(w, aud)[1]
		eq(e.id, fid); eq(e.g, "d"); eq(e.arb:lower(), arb.name:lower()); eq(e.winner:lower(), b.name:lower())
		eq(e.reports, 3, aud.name .. ": both fighters and the arbiter"); eq(e.state, "agreed")
	end
	eq(M(w, arb, "ArenaLedger").MyGames()[1].result, "J", "the arbiter's own: judged")
	-- (the same record as a tournament's bout, and as a Fight Night's)
	local copy = {}
	for k, v in pairs(f) do copy[k] = v end
	copy.tid = "T1abc"
	local rec = M(w, arb, "ArenaFights").LedgerRecord(copy)
	eq(rec.g, "t"); assert(rec.x:find("%.T1abc$"), rec.x)
	copy.tid, copy.card = nil, "N1abc"
	eq(M(w, arb, "ArenaFights").LedgerRecord(copy).g, "n")
	NoBets(w, a)
	NoErrors(w)
end)

test("1.1.6 games ledger: Bones against the House and the lesson (the rules' tips): each a game of its own kind, the player's alone (one word), told to the auditors", function()
	local w, c = World116()
	local a = c.a
	local FT = M(w, a, "FarkleTable")
	local house = assert(FT.Practice({ target = 2000, first = 1 }))
	w:Run(0)
	assert(FT.Concede(house))
	w:Run(5)
	local lesson = assert(FT.Practice({ target = 2000, first = 1, learn = true }))
	eq(a.ns.FarkleTable.Get(lesson).learn, true)
	eq(w:As(a, a.ns.FarkleTable.View, lesson).learn, true, "the board is told it is a lesson")
	w:Run(0)
	assert(FT.Concede(lesson))
	w:Run(5)
	local mine = M(w, a, "ArenaLedger").MyGames()
	eq(#mine, 2); eq(mine[1].g, "p", "the lesson, newest first"); eq(mine[2].g, "h"); eq(mine[1].result, "L"); eq(mine[2].result, "L")
	for _, aud in ipairs(Auditors(c)) do
		local list = Rows(w, aud)
		eq(#list, 2, aud.name)
		eq(list[1].g, "p"); eq(list[2].g, "h"); eq(list[1].p2, nil, "against the House"); eq(list[1].state, "one")
		eq(list[1].w, "2", "the House won")
	end
	NoBets(w, a)
	NoErrors(w)
end)

test("1.1.6 games ledger: the Lottery's practice: a free practice ticket (no stake to choose), the draw in the player's games and the auditors'; no ticket or market message", function()
	local w, c = World116()
	local a = c.a
	local own = w:As(a, function() return H.LoadCompanion(a.ns, { db = a.heavyDB }) end)
	local UI, L, Lt = own.ArenaUI, a.ns.L, a.ns.Lottery
	local m = w:As(a, UI.LotteryPracticeModel)
	eq(m.free, true); eq(m.stake, nil, "no stake")
	eq(m.compliance, L.COMPLIANCE_LOTTERY_PRACTICE, "the line about the review, country by country")
	assert(L.COMPLIANCE_LOTTERY_PRACTICE:find("country by country", 1, true))
	eq(select(2, w:As(a, UI.LotteryPracticeDraw, { 1, 5, 9, 13, 17 })), "pick", "a beast first")
	assert(w:As(a, UI.LotteryPracticePick, 2))
	local result = w:As(a, UI.LotteryPracticeDraw, { 1, 5, 9, 13, 17 })
	w:Run(5)
	eq(#result.rows, 5); eq(#result.positions, 1, "the beast came out once")
	local mine = M(w, a, "ArenaLedger").MyGames()
	eq(#mine, 1); eq(mine[1].g, "o"); eq(mine[1].w, "1", "a hit"); eq(mine[1].s1, 1); eq(mine[1].s2, 2)
	eq(mine[1].x, "0001.0005.0009.0013.0017", "the five numbers")
	for _, aud in ipairs(Auditors(c)) do
		local e = Rows(w, aud)[1]
		eq(e.g, "o", aud.name); eq(e.p1:lower(), a.name:lower()); eq(e.state, "one")
	end
	for _, kind in ipairs({ "BS", "BK", "BM", "BO", "LW" }) do eq(#w:Sent({ type = kind }), 0, kind) end
	-- A miss: the row says so.
	assert(w:As(a, UI.LotteryPracticePick, 25))
	w:As(a, UI.LotteryPracticeDraw, { 1, 5, 9, 13, 17 })
	local row = M(w, a, "ArenaLedger").MyGames()[1]
	eq(row.w, "2"); eq(row.s1, 0)
	w:As(a, function()
		local text = UI.GameLine(row, true)
		eq(text, L.ARENA_GAMES_MISS:format(UI.Kit.Name(a.name)))
	end)
	NoBets(w, a)
	NoErrors(w)
end)

test("1.1.6 games ledger: the page: a player sees his own games only; an auditor every game, with the filters (game, period) and the search (a player)", function()
	local w, c = World116()
	local a, b = c.a, c.b
	Duel(w, a, b, b, a)
	w:Run(5)
	local FT = M(w, a, "FarkleTable")
	local house = assert(FT.Practice({ target = 2000, first = 1 }))
	w:Run(0)
	assert(FT.Concede(house))
	w:Run(5)
	local bh = assert(M(w, b, "FarkleTable").Practice({ target = 2000, first = 1 }))
	w:Run(0)
	assert(M(w, b, "FarkleTable").Concede(bh))
	w:Run(5)
	-- An older game a player told the King (12 days ago: in the month maybe, never in the week).
	local LGk = M(w, c.king, "ArenaLedger")
	local B36 = c.king.ns.Arena.B36
	local now = w:As(c.king, c.king.ns.Arena.Now)
	local old = table.concat({ "Gold1aa", "h", B36(now - 12 * 86400), "3c", a.short, "-", "-", "1", B36(2000), "0", "t", "2", "-" }, "~")
	assert(LGk.TakeGame(a.name, "T", old))
	-- The King: every game.
	local all = LGk.GamesView({ scope = "all" })
	eq(all.scope, "all"); eq(all.may, true); eq(all.total, 4)
	eq(LGk.GamesView({ scope = "all", game = "arena" }).total, 1, "the Arena's games")
	eq(LGk.GamesView({ scope = "all", game = "bones" }).total, 3, "Bones'")
	eq(LGk.GamesView({ scope = "all", game = "h" }).total, 3, "against the House")
	eq(LGk.GamesView({ scope = "all", game = "lottery" }).total, 0)
	eq(LGk.GamesView({ scope = "all", period = "week" }).total, 3, "the old game is not this week's")
	eq(LGk.GamesView({ scope = "all", period = "today" }).total, 3)
	local hale = LGk.GamesView({ scope = "all", player = a.short:match("^%S+"):lower() })
	eq(hale.total, 3, "the search: his duel, his House game, the old one")
	for _, r in ipairs(hale.list) do assert(r.p1:lower() == a.name:lower() or (r.p2 and r.p2:lower() == a.name:lower()), r.id) end
	eq(LGk.GamesView({ scope = "all", player = "nobody" }).total, 0)
	assert(#all.players >= 2, "the names offered"); eq(all.players[1].name:lower(), a.name:lower(), "the most games first")
	eq(LGk.GamesView({ scope = "mine" }).total, 0, "the King's own: none")
	-- A player: his own, whatever he asks for.
	local va = M(w, a, "ArenaLedger").GamesView({ scope = "all" })
	eq(va.scope, "mine"); eq(va.may, false); eq(va.total, 2, "his duel and his House game")
	for _, r in ipairs(va.list) do assert(r.side ~= nil, "a game of his own") end
	eq(M(w, c.member, "ArenaLedger").GamesView({ scope = "all" }).total, 0, "a member: nothing")
	-- The screens: the King's page, every game, then the Arena's only, then one player's.
	local own = w:As(c.king, function() return H.LoadCompanion(c.king.ns) end)
	local UI, L = own.ArenaUI, c.king.ns.L
	w:As(c.king, function()
		local spec = GamesSpec(UI)
		UI.ShowGames("all")
		local lines = spec.lines({ key = "staff.games" })
		eq(lines[1].text, L.ARENA_GAMES_HEAD_ALL); eq(lines[1].right, L.ARENA_GAMES_COUNT:format(4))
		assert(Find(lines, L.ARENA_BONE_LEDGER_WON:format(UI.Kit.Name(b.name), UI.Kit.Name(a.name))), "the duel: who beat whom")
		assert(Find(lines, L.ARENA_GAME_D), "named a duel")
		UI.SetGames("game", "arena")
		eq(#spec.lines({ key = "staff.games" }), 2, "the head and the duel")
		UI.SetGames("game", nil)
		UI.SetGames("player", b.name)
		local only = spec.lines({ key = "staff.games" })
		eq(only[1].right, L.ARENA_GAMES_COUNT:format(2), "Selka's duel and his House game")
		-- A row picked: the parchment says it whole, the footer offers its players' games.
		local duel
		for _, l in ipairs(only) do if l.text:find(L.ARENA_GAME_D, 1, true) then duel = l end end
		local st = { key = "staff.games", sel = duel.key }
		local buttons = spec.buttons(st)
		eq(buttons[1][1], L.ARENA_BTN_COPY)
		assert(buttons[2][1] == L.ARENA_GAMES_ONLY:format(UI.Kit.Name(a.name)) or buttons[3][1] == L.ARENA_GAMES_ONLY:format(UI.Kit.Name(a.name)), "a player's games, no typing")
		local copy = spec.copy(st)
		assert(copy:find(L.ARENA_GAME_D, 1, true) and copy:find(L.ARENA_GAME_H, 1, true), copy)
	end)
	-- The member's page: his own (none), the head says so.
	local mown = w:As(c.member, function() return H.LoadCompanion(c.member.ns) end)
	w:As(c.member, function()
		local spec = GamesSpec(mown.ArenaUI)
		mown.ArenaUI.ShowGames("all")
		local lines = spec.lines({ key = "staff.games" })
		eq(lines[1].text, L.ARENA_GAMES_HEAD_MINE, "a member asking for every game gets his own")
		assert(Find(lines, L.ARENA_GAMES_NONE_MINE))
		eq(Find(lines, mown.ArenaUI.Kit.Name(a.name)), nil)
	end)
	NoErrors(w)
end)

test("1.1.6 games ledger: the King offline when a duel ends, its fighters gone too: at his hello the games' clerk (the first councillor by name) passes on both words, once", function()
	local w, c = World116({ offline = function(cast) return cast.king end })
	local a, b = c.a, c.b
	local fid = Duel(w, a, b, a, b)
	w:Run(5)
	eq(#w:Sent({ type = "AY", to = c.king.name }), 0, "the King was offline")
	eq(#Rows(w, c.councillor), 1)
	w:Logout(a); w:Logout(b)
	w:Login(c.king)
	w:Run(45)
	eq(#w:Sent({ from = c.councillor, type = "AY", to = c.king.name }), 2, "the clerk passed on both fighters' words")
	eq(#w:Sent({ from = c.author, type = "AY", to = c.king.name }), 0, "one clerk only")
	local e = Rows(w, c.king)[1]
	eq(e.id, fid); eq(e.reports, 2); eq(e.state, "agreed")
	local told = #w:Sent({ type = "AY", to = c.king.name })
	w:Run(900)
	eq(#w:Sent({ type = "AY", to = c.king.name }), told, "not again at his next hello")
	NoErrors(w)
end)

test("1.1.6 games ledger: a rehearsal's stand-in King is no auditor of it: told nothing, refuses a word, sees only his own", function()
	local w, c = World116()
	local a, b, member = c.a, c.b, c.member
	for _, x in ipairs(w.clients) do
		x.ns.ArenaRoles.standIn = function(name, letter) return letter == "k" and type(name) == "string" and name:lower() == member.name:lower() end
	end
	eq(w:As(a, a.ns.ArenaRoles.Auditor, member.name, "T"), true, "a rehearsal's King in T")
	eq(w:As(a, a.ns.ArenaLedger.GamesAuditor, member.name), false, "never the games' ledger's")
	w:As(a, function() a.ns.Debts.HeardAuditor(member.name) end)
	Duel(w, a, b, a, b)
	w:Run(5)
	eq(#w:Sent({ type = "AY", to = member.name }), 0, "told nothing")
	local body = w:Sent({ from = a, type = "AY", to = c.king.name })[1].msg:match("^AY~T%d+~(.*)$")
	eq(select(2, M(w, member, "ArenaLedger").TakeGame(a.name, "T", body)), "auditor")
	eq(M(w, member, "ArenaLedger").GamesView({ scope = "all" }).scope, "mine")
	NoErrors(w)
end)

test("1.1.6 games ledger: the privacy page says in one line that game results are recorded and who sees them (English and pt-BR)", function()
	local w, c = World116()
	local a = c.a
	local L = a.ns.L
	local intro = w:As(a, a.ns.Consent.Intro)
	assert(intro:find(L.CONSENT_GAMES_RECORDED, 1, true), "the line on the page")
	for _, who in ipairs({ "King", "High Council", "author" }) do assert(L.CONSENT_GAMES_RECORDED:find(who, 1, true), who) end
	-- (pt-BR: the arena's fights' words in that language)
	local pt = setmetatable({}, { __index = function(_, k) return k end })
	local saved = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaFightsText.lua"))("Olympus", { L = pt }) end)
	GetLocale = saved
	if not ok then error(err, 0) end
	local line = rawget(pt, "CONSENT_GAMES_RECORDED")
	assert(type(line) == "string" and line ~= L.CONSENT_GAMES_RECORDED and line:find("Rei", 1, true) and line:find("Alto Conselho", 1, true), tostring(line))
	NoErrors(w)
end)

-- (Review of 1.1.6: the games were kept in the rehearsal store, which a new rehearsal's word, its
-- end 7 days on and `test clear` empty: the King's every game and each player's own went with it.)
test("1.1.6 games ledger: a rehearsal never empties it: a group rehearsal's word, `test clear` and a rehearsal's store dropped 7 days after it closed leave every player's games and the King's every game", function()
	local w, c = World116()
	local a, b, king = c.a, c.b, c.king
	Duel(w, a, b, a, b)
	w:Run(5)
	eq(#M(w, a, "ArenaLedger").MyGames(), 1); eq(#Rows(w, king), 1)
	eq(type(king.rdb.arenaGames) == "table" and type(king.rdb.arenaGames.gamesLedger), "table", "the games' own store")
	eq(king.rdb.arenaTest and king.rdb.arenaTest.gamesLedger, nil, "not the rehearsal store")
	-- The signed arbiter starts a rehearsal in the fighters' group: their clients join it.
	assert(w:As(c.arb, c.arb.ns.ArenaTest.Start, "group"))
	w:Run(1)
	assert(w:As(a, a.ns.ArenaTest.Running), "the fighter joined the rehearsal")
	-- The King: `test clear`, then a rehearsal he joined, closed 8 days ago, dropped at login.
	eq(w:As(king, king.ns.ArenaTest.Clear), true)
	local s = w:As(king, king.ns.Arena.Store, "T")
	s.rid, s.closedAt = 5, w:As(king, king.ns.Arena.Now) - 8 * 86400
	eq(select(2, w:As(king, king.ns.ArenaTest.CheckStore)), "old", "the rehearsal's store dropped")
	-- Another duel: each list holds both games, the King's ledger too.
	Duel(w, a, b, b, a)
	w:Run(5)
	eq(#M(w, a, "ArenaLedger").MyGames(), 2, "the fighter's own games")
	eq(#M(w, b, "ArenaLedger").MyGames(), 2)
	eq(#Rows(w, king), 2, "the King's every game")
	NoErrors(w)
end)

-- (Review of 1.1.6: a free practice draw takes a click; every one went to every auditor, and they
-- shared one cap with the games between players.)
test("1.1.6 games ledger: practice never crowds out a game between players: a player tells the auditors only so many games played alone a day (the rest his own list's, never told, nor at a hello); his list and the auditors' keep games played alone apart", function()
	local w, c = World116()
	local a, b, king = c.a, c.b, c.king
	-- (small caps: a few draws stand for a day of clicks)
	local LGa = a.ns.ArenaLedger
	LGa.GAMES_SOLO_DAY, LGa.GAMES_MINE_MAX, LGa.GAMES_MINE_SOLO_MAX = 3, 3, 3
	for _, aud in ipairs(Auditors(c)) do
		local LG = aud.ns.ArenaLedger
		LG.GAMES_MAX, LG.GAMES_SOLO_MAX, LG.GAMES_SOLO_DAY = 3, 3, 3
	end
	local fid = Duel(w, a, b, a, b)
	w:Run(5)
	local own = w:As(a, function() return H.LoadCompanion(a.ns, { db = a.heavyDB }) end)
	local UI = own.ArenaUI
	assert(w:As(a, UI.LotteryPracticePick, 2))
	for _ = 1, 5 do w:As(a, UI.LotteryPracticeDraw, { 1, 5, 9, 13, 17 }) end
	w:Run(30)
	local function Draws(to)
		local n = 0
		for _, x in ipairs(w:Sent({ from = a, type = "AY", to = to.name })) do
			if tostring(x.msg:match("^AY~T%d+~(.*)$")):match("^[^~]*~(%a)~") == "o" then n = n + 1 end
		end
		return n
	end
	for _, aud in ipairs(Auditors(c)) do eq(Draws(aud), 3, aud.name .. ": three draws told, not five") end
	local function Has(list, id)
		for _, r in ipairs(list) do if r.id == id then return true end end
		return false
	end
	local mine = M(w, a, "ArenaLedger").MyGames()
	eq(#mine, 4, "the duel and the three newest draws")
	assert(Has(mine, fid), "the duel stays in his own list")
	for _, aud in ipairs(Auditors(c)) do
		local list = Rows(w, aud)
		eq(#list, 4, aud.name); assert(Has(list, fid), aud.name .. ": the duel stays in the ledger")
	end
	-- An auditor's next hellos: the draws never told are never resent.
	w:Run(900)
	eq(Draws(king), 3, "not at his hello")
	NoErrors(w)
end)

-- (Review of 1.1.6: the line was only on the page, which opens by itself only for a line waiting
-- for an answer: a member who answered every line before 1.1.6 was never shown it.)
test("1.1.6 games ledger: a member who answered every privacy line before is shown the page once at login, for the games' line; not at the next login", function()
	local w, c = World116()
	local a = c.a
	local Consent, L = a.ns.Consent, a.ns.L
	w:As(a, function()
		for _, item in ipairs(Consent.Pending()) do Consent.Choose(item.key, false) end
		-- (the zone and layer's lines: their modules are not in the test world; his 1.1.5 answers)
		a.db.shareLocation, a.db.layerHelp = false, false
		local left = {}
		for _, item in ipairs(Consent.Pending()) do left[#left + 1] = item.key end
		eq(table.concat(left, ","), "", "every line answered (1.1.5)")
		if Consent.Frame() then Consent.Frame():Hide() end
		Consent.Reset()
		a.db.consentNotices = nil
		eq(Consent.NoticeDue(), true)
		eq(Consent.Ask("login"), true, "the page, for the games' line")
		local page = Consent.Frame()
		assert(page and page:IsShown(), "the page")
		assert(tostring(page.intro:GetText()):find(L.CONSENT_GAMES_RECORDED, 1, true), "the line on it")
		eq(Consent.NoticeDue(), false, "shown")
		page:Hide()
		Consent.Reset()
		eq(Consent.Ask("login"), false, "once: not at the next login")
	end)
	NoErrors(w)
end)

test("1.1.6 games ledger: with the gamepad UI the auditor's page offers its players from a list and a picked row, no search box; with mouse and keyboard the search box too", function()
	for _, gamepad in ipairs({ true, false }) do
		H.WithGamepadUI(gamepad, function()
			local w = FW.New({ compliance = "shipped", arenaFiles = Files116() })
			local a = w:Player(N.fighterA)
			local b = w:Player(N.fighterB)
			local king = w:Role("king")
			for _, x in ipairs(w.clients) do W3.Rules(w, x) end
			w:Group({ a, b })
			w:Run(41)
			Duel(w, a, b, a, b)
			w:Run(5)
			-- (Opened the way the Arena's button does: with the gamepad UI, 1.1.5's gate installs no typed
			-- /oly command.)
			w:As(king, function() king.ns.Arena.RunSlash("") end)
			local UI = king.companion.own.ArenaUI
			eq(w:As(king, UI.Kit.Gamepad), gamepad)
			w:As(king, function() UI.Open("games.all") end)
			local f = UI.Frame()
			local head = f.heads["staff.games"]
			assert(head, "the filters over the list")
			eq(head.who:IsShown(), true, "whose games: a list to pick from")
			eq(head.search:IsShown(), not gamepad, "the search box only with mouse and keyboard")
			-- (every control a Kit.Button, 24 px or taller by its rule: the world's stand-in frames keep no
			-- sizes to measure; the page's gamepad route to a player is the picked row's footer button,
			-- the page's test above)
			for _, btn in ipairs({ head.game, head.period, head.who, head.prev, head.next }) do eq(btn:IsShown(), true) end
			eq(#(UI.lastModel.lines or {}), 2, "the head line and the duel")
			NoErrors(w)
		end)
	end
end)
