-- 1.1.6, Bones' lesson (Olympus_Arena/FarkleBoard.lua's Board.Lesson and Board.BustChance): a
-- practice game against the innkeeper with Show tips checked says, in the table's column, what
-- the rules make of the dice in front of the player: which dice of a throw score and for how much,
-- the turn's points and the chance of BONES! with the dice left, hot dice, a bust and a bank. The
-- plain practice (Start) says none of it. Last, the points (Daniel's call for 1.1.6): practice and
-- games for fun play for points, and their words never say a bet or a stake. On the test world with
-- the table's additions and the board's stand-in frames (tests/arena/lib/board-ui.lua), as
-- farkle-board.lua. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local N = H.World.NAMES

local function check(cond, msg, ...) if not cond then error((msg or "check failed"):format(...), 2) end end
local function Seat(w, name)
	local c = w:Player(name, { companion = {} })
	c.K = BoardUI.New(function() return w.clock end)
	c.K.Install(c.globals)
	c.w = w
	return c
end
local function Board(c) return c.ns.Arena.ui.FarkleBoard end
local function X(c) return Board(c)._ end
local function P(c) return X(c).parts() end
local function R(c) return c.ns.FarkleRules end
local function Show(w, c, what, id, extra) return w:As(c, function() return c.ns.FarkleTable.ShowUI(what, id, extra) end) end
local function Click(w, c, b) return w:As(c, function() return c.K.UserClick(b) end) end
local function View(w, c) return w:As(c, function() return c.ns.FarkleTable.View(X(c).S.id) end) end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
		if c.K then for _, e in ipairs(c.K.errors) do error(c.name .. " (a script): " .. e, 2) end end
	end
end
local function Roll(c, dice) return (R(c).Encode(dice)) end
local function Num(n)
	local s, k = tostring(n), 0
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
local function InPlay(c)
	local sd, out = X(c).sides[1], {}
	for j, i in ipairs(sd.play) do out[j] = sd.dice[i] end
	return out
end
local function Step(w, seconds)
	local stop = w.clock + seconds
	while w.clock < stop - 1e-9 do w:Run(math.min(0.05, stop - w.clock)) end
end
local function Until(w, pred, limit)
	local t0 = w.clock
	while not pred() do
		check(w.clock - t0 <= (limit or 30), "waited %.1f s", w.clock - t0)
		Step(w, 0.05)
	end
end
local function Idle(c)
	local S = X(c).S
	if S.animating or #S.queue > 0 or S.flying[1] > 0 or S.flying[2] > 0 then return false end
	return not c.w:As(c, function() return Board(c).Busy(S.id) end)
end
local function Info(c) return P(c).info:GetText() or "" end
local function T(c, key, ...) return c.ns.L[key]:format(...) end

-- The practice setup, the guide closed, the target 2,000, optional tips, then Start.
local function Lesson(o)
	o = o or {}
	local w = FW.New({ seed = o.seed or 7, compliance = "shipped" })
	local a = Seat(w, N.fighterA)
	Show(w, a, "practice")
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	for i, t in ipairs(R(a).TARGETS) do if t == 2000 then Click(w, a, P(a).targets[i]) end end
	if not o.plain then check(Click(w, a, P(a).setup.tips), "Show tips") end
	check(Click(w, a, P(a).setup.start), "the setup's Start button")
	w:Run(0)
	return w, a
end

print("1.1.6: Bones' lesson, the rules' tips")

test("1.1.6 Bones lesson: the chance of BONES! with n dice, from the rules: 67% with one die down to 3% with six", function()
	local w = FW.New()
	local a = Seat(w, N.fighterA)
	eq(w:As(a, function() return a.ns.Arena.LoadUI() end), true)
	local B = Board(a)
	local want = { 67, 44, 28, 16, 8, 3 }
	for n = 1, 6 do eq(w:As(a, B.BustChance, n), want[n], n .. " dice") end
	eq(w:As(a, B.BustChance, 0), nil); eq(w:As(a, B.BustChance, 7), nil)
	NoErrors(w)
end)

test("1.1.6 Bones lesson: Show tips then Start teaches the throw, scoring dice, BONES! chance, banking and a bust", function()
	local w, a = Lesson()
	local v = View(w, a)
	eq(v.practice, true); eq(v.learn, true, "a lesson"); eq(v.stake, 0, "nothing at stake")
	check(P(a).win.sub:GetText():find(a.ns.L.FARKLE_B_LESSON, 1, true), "the table says lesson: %s", P(a).win.sub:GetText())
	eq(Info(a), T(a, "FARKLE_L_ROLL", 6), "before the throw: what scores")
	-- A throw with a 1 and a 5: they are named, and their points.
	w:QueueRoll(a.name, Roll(a, { 1, 5, 2, 2, 3, 6 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1] and InPlay(a)[1].where == "lane" end, 5)
	eq(Info(a), T(a, "FARKLE_L_KEEP", "1 5", Num(150)))
	-- The 1 picked: 100 at stake, five dice left and their chance of BONES!.
	Click(w, a, InPlay(a)[1].f)
	eq(Info(a), T(a, "FARKLE_L_DECIDE", Num(100), 5, 8))
	-- Banked: the tip says what it made and what is left to reach, while the House plays.
	Click(w, a, P(a).bank)
	Until(w, function() local x = View(w, a) return x.expect and x.expect.who == 2 and Idle(a) end, 10)
	eq(Info(a), T(a, "FARKLE_L_BANKED", Num(100), Num(100), Num(2000)))
	-- His next turn: a 1, kept, roll on with five, and BONES!: the 100 lost.
	Until(w, function() local x = View(w, a) return x.over or (x.expect and x.expect.who == 1 and Idle(a)) end, 60)
	eq(Info(a), T(a, "FARKLE_L_ROLL", 6))
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1] and InPlay(a)[1].where == "lane" end, 5)
	Click(w, a, InPlay(a)[1].f)
	-- (Keep & roll asks for five dice: before the roll line comes, the tip of the roll on)
	w:QueueRoll(a.name, Roll(a, { 2, 3, 4, 6, 2 }))
	w.lineDelay = function() return 2 end
	Click(w, a, P(a).primary)
	local x = View(w, a)
	eq(x.expect.phase, "roll"); eq(x.turn.points, 100)
	eq(w:As(a, Board(a).Lesson, x), T(a, "FARKLE_L_ROLL_ON", Num(100), 5, 8), "what a roll on risks")
	w.lineDelay = nil
	Until(w, function() local y = View(w, a) return y.expect and y.expect.who == 2 and Idle(a) end, 10)
	eq(Info(a), T(a, "FARKLE_L_BUST", Num(100)))
	-- Conceded: a game of the ledger's lesson kind, the player's own.
	assert(w:As(a, a.ns.FarkleTable.Concede, X(a).S.id))
	w:Run(1)
	local mine = w:As(a, a.ns.ArenaLedger.MyGames)
	eq(mine[1].g, "p", "a lesson in his games")
	NoErrors(w)
end)

test("1.1.6 Bones lesson: hot dice: all six scored, the tip says rolling on throws six again with the points kept", function()
	local w, a = Lesson()
	w:QueueRoll(a.name, Roll(a, { 1, 1, 1, 5, 5, 5 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[6] and InPlay(a)[6].where == "lane" end, 5)
	for i = 1, 6 do Click(w, a, InPlay(a)[i].f) end
	eq(Info(a), T(a, "FARKLE_L_HOT", Num(1500)))
	NoErrors(w)
end)

test("1.1.6 Bones lesson: Start (the plain practice) gives no tip, the table's own words", function()
	local w, a = Lesson({ plain = true })
	local v = View(w, a)
	eq(v.learn, false); eq(v.practice, true)
	eq(w:As(a, Board(a).Lesson, v), nil)
	check(not Info(a):find("Tip:", 1, true), "no tip: %s", Info(a))
	w:QueueRoll(a.name, Roll(a, { 1, 5, 2, 2, 3, 6 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1] and InPlay(a)[1].where == "lane" end, 5)
	check(not Info(a):find("Tip:", 1, true), "no tip after the throw: %s", Info(a))
	NoErrors(w)
end)

test("1.1.6 Bones lesson: with the gamepad UI, Show tips has a 32 px click area and the lesson plays with its tips", function()
	H.WithGamepadUI(true, function()
		local w, a = Lesson()
		local x, y, wd, h = a.K.Within(P(a).setup.tips, P(a).win)
		check(h >= 32 - 0.01, "the tips checkbox is %.0f px tall", h)
		eq(View(w, a).learn, true)
		eq(Info(a), T(a, "FARKLE_L_ROLL", 6))
		NoErrors(w)
	end)
end)

print("1.1.6: practice and games for fun play for points")

-- A word of betting in a text (English or pt-BR), or nil.
local BET_WORDS = { "%f[%a]bets?%f[%A]", "%f[%a]betting", "%f[%a]bettors?%f[%A]", "%f[%a]stakes?%f[%A]", "%f[%a]staked", "wager", "apost" }
local function BetWord(text)
	local low = tostring(text or ""):lower()
	for _, p in ipairs(BET_WORDS) do if low:find(p) then return p end end
	return nil
end
-- The words of the practice, the lesson, a game for fun, the Lottery's practice and the games'
-- page in a language, read from the locale files themselves.
local function Words(locale)
	local L = setmetatable({}, { __index = function(_, k) return k end })
	local saved = GetLocale
	GetLocale = function() return locale end
	local ok, err = pcall(function()
		for _, f in ipairs({ "ComplianceText", "ArenaHomeText" }) do assert(loadfile(H.ADDON_DIR .. "Locales/" .. f .. ".lua"))("Olympus", { L = L }) end
		for _, f in ipairs({ "FarkleText", "LotteryText", "UIText" }) do
			assert(loadfile(H.ROOT .. "Olympus_Arena/Locales/" .. f .. ".lua"))("Olympus_Arena", { host = { L = L } })
		end
	end)
	GetLocale = saved
	if not ok then error(err, 0) end
	return L
end
local POINTS_KEYS = { "FARKLE_B_SETUP_NOTE", "FARKLE_B_SETUP_HINT", "FARKLE_B_TIPS", "FARKLE_B_LESSON", "FARKLE_B_CREATE_HINT_POINTS", "FARKLE_B_C_PLAYS_FOR",
	"FARKLE_B_C_POINTS", "FARKLE_B_POINTS_FUN", "COMPLIANCE_LOTTERY_PRACTICE", "ARENA_CHALLENGE_CASUAL", "ARENA_GAMES_MINE", "ARENA_GAMES_MINE_DESC",
	"ARENA_GAMES_MINE_TIP", "ARENA_GAMES_EVERY_GAME", "ARENA_GAMES_EVERY_GAME_TIP", "ARENA_PANE_GAMES" }
local POINTS_PREFIXES = { "FARKLE_L_", "LOTTERY_PRACTICE_", "ARENA_GAME_", "ARENA_GAMES_HEAD", "ARENA_GAMES_TEXT", "ARENA_GAMES_ABOUT", "ARENA_GAMES_NONE" }

test("1.1.6 points: while the gate allows no stake, a game for fun says points, never a bet or a stake (the create panel, the invitation, the result card); the practice, the lesson, the Lottery's practice and the games' page neither (English and pt-BR)", function()
	local w = FW.New({ seed = 11, compliance = "shipped" })
	local a, b = Seat(w, N.fighterA), Seat(w, N.fighterB)
	w:Group({ a, b })
	Show(w, a, "create", nil, { guest = b.name, target = 2000 })
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	local L, cp = a.ns.L, P(a).create
	check(cp:IsShown(), "the create panel")
	eq(cp.stakeLabel:GetText(), L.FARKLE_B_C_PLAYS_FOR); eq(cp.amount:GetText(), L.FARKLE_B_C_POINTS)
	check(not cp.plus:IsShown() and not cp.minus:IsShown(), "no stake to raise")
	eq(Info(a), L.FARKLE_B_CREATE_HINT_POINTS)
	local said = { cp.stakeLabel:GetText(), cp.amount:GetText(), Info(a) }
	check(Click(w, a, cp.send), "Invite")
	w:Run(0)
	check(P(b).ask and P(b).ask:IsShown(), "the guest's pop-up")
	eq(P(b).ask.lines[3]:GetText(), L.FARKLE_B_POINTS_FUN)
	said[#said + 1] = P(b).ask.lines[3]:GetText()
	-- The result card of a game for fun (a live table's: a rehearsal's says it is one).
	local v = { id = "Kx", role = "host", seat = 1, players = { a.name, b.name }, over = true, scores = { 2100, 900 }, stake = 0, target = 2000,
		src = { "-", "-" }, kind = "d", state = "end", game = { over = true }, winner = 1 }
	local real = a.ns.FarkleTable.View
	a.ns.FarkleTable.View = function(x) if x == "Kx" then return v end return real(x) end
	local ok, spec = pcall(function() return w:As(a, function() return Board(a).CardSpec("Kx") end) end)
	a.ns.FarkleTable.View = real
	if not ok then error(spec, 0) end
	eq(spec.note, L.FARKLE_B_POINTS_FUN, "the card's line")
	said[#said + 1] = spec.note
	for _, text in ipairs(said) do eq(BetWord(text), nil, text) end
	-- The words themselves, both languages.
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local W = Words(locale)
		local n = 0
		for _, key in ipairs(POINTS_KEYS) do
			local text = rawget(W, key)
			check(type(text) == "string" and text ~= "", "%s %s: no words", locale, key)
			eq(BetWord(text), nil, locale .. " " .. key .. ": " .. text)
			n = n + 1
		end
		for key, text in pairs(W) do
			for _, prefix in ipairs(POINTS_PREFIXES) do
				if key:sub(1, #prefix) == prefix then
					eq(BetWord(text), nil, locale .. " " .. key .. ": " .. tostring(text))
					n = n + 1
				end
			end
		end
		check(n >= 50, "%s: %d texts read", locale, n)
		check(W.FARKLE_B_SETUP_NOTE:lower():find(locale == "ptBR" and "pontos" or "points", 1, true), "%s: the practice is for points", locale)
	end
	NoErrors(w)
end)

-- 1.1.6: Bones at a tavern or at a camp (FarkleTable.lua's place rule): said plainly where a player
-- starts a game (the create panel) or looks for one (the Find button's tip, the Bones page and its
-- explanation), in both languages.
test("1.1.6 Bones at a tavern or at a camp: the create panel, the Find button's tip, the Bones page and its explanation say so (English and pt-BR)", function()
	local w = FW.New({ seed = 12, compliance = "shipped" })
	local a, b = Seat(w, N.fighterA), Seat(w, N.fighterB)
	w:Group({ a, b })
	Show(w, a, "create", nil, { guest = b.name, target = 2000 })
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(Info(a):find("Bones can be played at a tavern or at a camp", 1, true), "the create panel: %s", Info(a))
	local SAY = { enUS = "Bones can be played at a tavern or at a camp", ptBR = "O Bones pode ser jogado numa taverna ou num acampamento" }
	for locale, line in pairs(SAY) do
		local W = Words(locale)
		for _, key in ipairs({ "FARKLE_B_CREATE_HINT_POINTS", "ARENA_FIND_PLAYER_TIP", "ARENA_BONE_ABOUT", "ARENA_EXPLAIN_BONE" }) do
			check(tostring(rawget(W, key)):find(line, 1, true), "%s %s: %s", locale, key, tostring(rawget(W, key)))
		end
		check(not tostring(W.ARENA_BONE_ABOUT):lower():find("gold"), "%s: no gold games on the Bones page", locale)
	end
	NoErrors(w)
end)
