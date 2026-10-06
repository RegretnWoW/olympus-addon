local _, own = ...; local ns = own.host; if not ns then return end
ns = own -- (the lab's tables stay the companion's own: Olympus has its own ns.Wallet and ns.FarkleRules)
-- (Ported from the Olympus Frame Lab, 2026-09-30: the practice preview, inside the arena.)

-- Farkle's rules (1.2): the Blood Arena's dice game for two players. Every die comes from the
-- server's /roll, never from a client: one /roll 1-46656 is six dice, 1-7776 five, down to 1-6
-- for one, and each client at the table reads the server's line itself. This file only turns
-- those numbers into dice and keeps the score. Pure functions over the values passed in: no
-- events, no messages, no saved data, no WoW API. The table's code (witnessing the rolls, the
-- messages, the stakes) and the page build on it, and the tests call it directly.
--
-- Dice
--   FarkleRules.Decode(roll, n) -> { d1, ..., dn } | nil
--     One server roll in 1..6^n as n dice: roll - 1 written in base 6, lowest digit first, each
--     digit + 1 (31337 of 1-46656 is 5 3 1 2 1 5). nil when n is not 1..6 or the roll is not a
--     whole number in 1..6^n. A die keeps its position: the dice set aside are named by it.
--   FarkleRules.Encode(dice) -> roll, n | nil    the roll that decodes to these dice (1 to 6 faces)
--   FarkleRules.RangeDice(lo, hi) -> n | nil     how many dice "/roll lo-hi" throws (only 1-6^n)
--   FarkleRules.RANGES[n]                         6^n, the top of the roll for n dice
-- Scoring: Kingdom Come: Deliverance II's dice (the points are FarkleRules.SCORES, one table: change
-- a row there, or set it to false to leave that combination out; the same table and scorer as the
-- addon's Olympus/ArenaFarkle.lua on its 1.2 branch). A lone 1 is 100 and a lone 5 is 50; three of a
-- kind is the face x 100 (three 1s 1000), and each die past the third doubles it (four 3s 600,
-- five 1200, six 2400; four 1s 2000); the runs 1-2-3-4-5 are 500, 2-3-4-5-6 750 and 1-2-3-4-5-6
-- 1500. Nothing else scores: no three pairs, no four and a pair, no bonus for two triplets.
--   FarkleRules.Score(dice) -> points | nil
--     Dice set aside from one roll, scored the best way they split into the combinations, each
--     die used once, the parts added up (1-2-3-4-5-5 is 550: the run and a 5). nil when any die
--     fits no combination (2-3-4-5-6-6: the second 6; 2-2-3-3-4-4), or when the list is not 1 to 6
--     faces of 1..6.
--   FarkleRules.Best(dice) -> points, { positions } | nil
--     The most a roll can score and which dice give it (positions, ascending); 0, {} when it is a
--     Farkle; nil when the list is not a roll. (On a tie, 2-3-4-5-6-6, the lower positions.)
--   FarkleRules.Farkle(dice) -> true | false | nil   true when nothing in the roll scores (no 1,
--     no 5, no face three times)
--   FarkleRules.HotDice(turn) -> true | false         the last dice set aside were the turn's
--     last ones: the next roll is six dice again, with the turn's points kept
-- A turn (a table; read its fields, change it only through these)
--   FarkleRules.Turn.New() -> turn
--     { points, left, phase, dice, kept, hot, rolls, farkle, lost, banked }
--     points: this turn's so far; left: in "roll" and "decide", the dice the next roll throws,
--     but in "keep" the dice just thrown (how many roll next depends on what he sets aside);
--     dice: the last roll's faces; kept: positions set aside from it (nil until he does); lost:
--     what a Farkle wiped; banked: what a bank scored.
--     phase: "roll" (must roll), "keep" (must set aside scoring dice), "decide" (roll again or
--     bank), "done".
--   FarkleRules.Turn.Roll(turn, roll) -> dice, farkle | nil, err
--     A server roll of the dice left (1..6^left). A Farkle ends the turn and loses its points.
--   FarkleRules.Turn.Keep(turn, positions) -> points, hot | nil, err
--     Sets aside dice of the last roll by position ({ 1, 4 }); they must all score together.
--     Once per roll: set aside everything wanted in one call (combinations count within a call).
--   FarkleRules.Turn.Bank(turn) -> points | nil, err   ends the turn with its points
-- A game (a table; read its fields, change it only through these)
--   FarkleRules.New(opts) -> game | nil, err
--     opts (all optional): target (points to reach, FarkleRules.TARGET by default: one of
--     FarkleRules.TARGETS, the ones with a turn cap; any other whole number only with cap given),
--     first (1 or 2, who starts), cap (turns each before the higher score wins:
--     FarkleRules.TURN_CAP[target] by default, false for none), players ({ "Name-Realm",
--     "Name-Realm" }, so moves may name the player instead of his seat; names match in any case).
--     err names the option that is wrong: "opts", "target", "first", "cap" or "players" (two
--     names that differ in more than case).
--     game: { players, target, cap, first, current, scores = { a, b }, turns = { a, b },
--     timeouts = { a, b }, turn, final, capped, sudden, over, winner, reason, last }
--     current: the seat (1 or 2) whose turn it is, nil once over; turns: turns each finished;
--     timeouts: turns in a row each lost to the clock; final: the seat whose turn, once over,
--     ends the game (someone reached the target, or both reached the cap); capped: true when it
--     was the cap (the reason is then "cap"); sudden: the scores were level then, so the players
--     go on a turn each in the same order until one is ahead; winner: the winning seat; reason:
--     "target", "cap", "concede" or "forfeit"; last: the turn just finished,
--     { who, how = "bank"|"farkle"|"timeout"|"foul", points, lost, dice }.
--   FarkleRules.Roll(game, who, roll)       -> dice, farkle | nil, err
--   FarkleRules.Keep(game, who, positions)  -> points, hot | nil, err
--   FarkleRules.Bank(game, who)             -> points | nil, err
--   FarkleRules.Timeout(game, who)          -> true | nil, err   his clock ran out: turn lost
--   FarkleRules.Foul(game, who)             -> true | nil, err   a wrong roll (not the dice he
--                                                                has left): turn lost
--   FarkleRules.Concede(game, who)          -> true | nil, err   either player, at any time
--   FarkleRules.Expect(game) -> who, phase, left | nil   the seat expected to act, the turn's
--     phase and the dice his next roll must throw (a roll is expected in "roll" and allowed in
--     "decide"). In "keep" left is nil: no roll is due until he sets dice aside, and only then is
--     the count known. nil once the game is over, or for anything that is not a game.
--   who is the seat (1 or 2) or the player's name as given in opts.players, in any case.
-- For the table's code: a roll line from the current player that arrives in "keep" is held until
-- his keep is applied (spec W3, the roll can overtake its decision); only then is its range
-- (RangeDice) compared with Expect's left, and a wrong count is a Foul (W2).
-- Errors (the err above; a refused move changes nothing)
--   "over" the game has ended; "player" who is neither player; "turn" not his turn;
--   "done" the turn has ended; "range" the roll is not 1..6^left for the dice left;
--   "keep" dice must be set aside before rolling again or banking; "roll" nothing on the table
--   to set aside (roll first); "dice" the positions are not distinct dice of the last roll;
--   "score" a die set aside doesn't score; "empty" nothing to bank; "game" the game passed is
--   not one made by New (for Turn.*, the turn is not a table).
-- Rules chosen here, and why
--   - The final round: the first bank that reaches the target gives the other player one last
--     turn (nobody loses without a chance to answer), then the higher score wins. Level scores
--     go to sudden death, a turn each in the same order until one is ahead, so a game never ends
--     in a draw that the stakes would have to handle.
--   - The turn cap is a safety net: when both players have had cap turns the higher score wins
--     (level: sudden death). A final round already running goes first, so the player who
--     answers a target always gets his turn.
--   - A turn lost to the clock or to a foul scores nothing, like a Farkle. Three turns in a row
--     lost to the clock forfeit the game: one rule covers a player who disconnects, leaves the
--     group or walks into an instance. Any other finished turn resets his count.

local FarkleRules = {}
ns.GamesRules = FarkleRules

FarkleRules.DICE = 6
FarkleRules.RANGES = { 6, 36, 216, 1296, 7776, 46656 }   -- /roll 1-RANGES[n] throws n dice
FarkleRules.TARGET = 10000                               -- a game's target when the host names none
-- Drink (the design, the fourth How to play page): how often, in 100, a bust is shaken off when
-- tipsy, drunk or completely smashed (1 in 10, 1 in 5, 1 in 3), and how many times a game.
FarkleRules.HICCUP = { 10, 20, 33 }
FarkleRules.SHAKES = 2
FarkleRules.TARGETS = { 2000, 5000, 10000 }              -- the targets the table offers
-- Turns each at most, by target: far above a normal game, so it only ends a game two players
-- stall. Every target offered has one, and New takes no other target unless its cap is named.
-- (Seeded games played with these rules and KCD2's points, 2,000 per target, took 4.4, 9.9 and
-- 19.6 turns each on average; the longest 11, 19 and 29.)
FarkleRules.TURN_CAP = { [2000] = 12, [5000] = 25, [10000] = 45 }
FarkleRules.TIMEOUTS = 3                                 -- turns in a row lost to the clock forfeit

-- The points: the dice of Kingdom Come: Deliverance II, the base game's rules (the owner's decision
-- of 2026-09-30). A row set to false or 0 (anything not a table), or a value in a row set to false
-- or to nothing above 0, is left out.
FarkleRules.SCORES = {
	single = { [1] = 100, [5] = 50 },                   -- a lone 1 or 5
	triple = { 1000, 200, 300, 400, 500, 600 },          -- three of a kind, by face: face x 100, three 1s 1000
	-- four, five and six of a kind: the face's three of a kind times this (four 3s 600, five 1200,
	-- six 2400; six 1s 8000). A face whose three of a kind is left out has none of these either.
	kind = { [4] = 2, [5] = 4, [6] = 8 },
	-- the runs, keyed by their faces: they count in any dice set aside that hold them, next to
	-- other combinations (1-2-3-4-5-5 is 550)
	run = { ["12345"] = 500, ["23456"] = 750, ["123456"] = 1500 },
}

local floor = math.floor

local function Int(x) return type(x) == "number" and x % 1 == 0 end
local function Value(v) return type(v) == "number" and v > 0 and v or nil end

-- A list of 1 to 6 faces (a roll, or dice set aside from one): how many of each face, and how
-- many dice. nil for anything else, a table with holes or extra keys included.
local function Counts(dice)
	if type(dice) ~= "table" then return nil end
	local n = #dice
	if n < 1 or n > FarkleRules.DICE then return nil end
	local keys = 0
	for _ in pairs(dice) do keys = keys + 1 end
	if keys ~= n then return nil end
	local c = { 0, 0, 0, 0, 0, 0 }
	for i = 1, n do
		local f = dice[i]
		if not Int(f) or f < 1 or f > 6 then return nil end
		c[f] = c[f] + 1
	end
	return c, n
end

-- A row of FarkleRules.SCORES, or nil when it is set to false, 0 or anything else not a table.
local function Row(name)
	local row = FarkleRules.SCORES[name]
	return type(row) == "table" and row or nil
end

-- The points for m dice of face f taken as one combination (a lone 1 or 5; three, four, five or
-- six of a kind), or nil.
local function Unit(f, m)
	if m == 1 then
		local single = Row("single")
		return Value(single and single[f])
	end
	local triples = m >= 3 and Row("triple")
	local triple = triples and Value(triples[f])
	if not triple or m == 3 then return triple or nil end
	local kind = Row("kind")
	local times = Value(kind and kind[m])
	return times and triple * times
end

-- The runs the table scores now, each as { points, n (its dice), c (its dice counted like
-- Counts') }. A key that is not faces 1 to 6 is no run.
local function Runs()
	local run, list = Row("run"), {}
	if not run then return list end
	for faces, points in pairs(run) do
		points = Value(points)
		if points and type(faces) == "string" and faces ~= "" and not faces:find("[^1-6]") then
			local c = { 0, 0, 0, 0, 0, 0 }
			for i = 1, #faces do
				local f = faces:byte(i) - 48
				c[f] = c[f] + 1
			end
			list[#list + 1] = { points = points, n = #faces, c = c }
		end
	end
	return list
end

-- Are the dice counted in r all among those counted in c?
local function Holds(c, r)
	for f = 1, 6 do
		if c[f] < r[f] then return false end
	end
	return true
end

local function Higher(a, b)
	if b and (not a or b > a) then return b end
	return a
end

-- The best points for the dice counted in c (n of them), every die used once; nil when some
-- die fits no combination. A split either holds a run, and each run that fits is tried with the
-- rest split the same way, or it has none, and then the lowest face left goes in a lone die or a
-- set of its face, each tried in turn. So every split is seen, and six dice make a few dozen
-- steps at most. (runs: Runs(), read once by the caller.)
local function Split(c, n, runs)
	if n == 0 then return 0 end
	local best
	for i = 1, #runs do
		local run = runs[i]
		if Holds(c, run.c) then
			for f = 1, 6 do c[f] = c[f] - run.c[f] end
			local rest = Split(c, n - run.n, runs)
			for f = 1, 6 do c[f] = c[f] + run.c[f] end
			if rest then best = Higher(best, run.points + rest) end
		end
	end
	local f = 1
	while c[f] == 0 do f = f + 1 end
	local k = c[f]
	for m = 1, k do
		local points = Unit(f, m)
		if points then
			c[f] = k - m
			local rest = Split(c, n - m, runs)
			c[f] = k
			if rest then best = Higher(best, points + rest) end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Dice
---------------------------------------------------------------------------

-- Lowest base-6 digit first: a roll of 1-6 (one die) reads the same as the die, and the n dice
-- of 1..6^n are independent and fair when the server's roll is.
function FarkleRules.Decode(roll, n)
	local top = Int(n) and FarkleRules.RANGES[n]
	if not top or not Int(roll) or roll < 1 or roll > top then return nil end
	local v, dice = roll - 1, {}
	for i = 1, n do
		dice[i] = v % 6 + 1
		v = floor(v / 6)
	end
	return dice
end

function FarkleRules.Encode(dice)
	local c, n = Counts(dice)
	if not c then return nil end
	local v, place = 0, 1
	for i = 1, n do
		v = v + (dice[i] - 1) * place
		place = place * 6
	end
	return v + 1, n
end

-- The range carries the dice count, so a roll commits to how many dice it throws before anyone
-- sees it (with one range for all, a client could roll first and then say how many it had).
function FarkleRules.RangeDice(lo, hi)
	if lo ~= 1 or not Int(hi) then return nil end
	for n, top in ipairs(FarkleRules.RANGES) do
		if top == hi then return n end
	end
	return nil
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

function FarkleRules.Score(dice)
	local c, n = Counts(dice)
	if not c then return nil end
	return Split(c, n, Runs())
end

-- Every selection of the roll (63 for six dice), the highest score kept, the first found on a
-- tie. With the table's points no selection of other faces ties the best; a run of five in six
-- dice can leave out either of two dice of one face (2-3-4-5-6-6), and then the lower position
-- is kept.
function FarkleRules.Best(dice)
	if not Counts(dice) then return nil end
	local n, runs = #dice, Runs()
	local top, pick = 0, {}
	for mask = 1, 2 ^ n - 1 do
		local c, at, m = { 0, 0, 0, 0, 0, 0 }, {}, mask
		for i = 1, n do
			if m % 2 == 1 then
				c[dice[i]] = c[dice[i]] + 1
				at[#at + 1] = i
			end
			m = floor(m / 2)
		end
		local points = Split(c, #at, runs)
		if points and points > top then top, pick = points, at end
	end
	return top, pick
end

-- Whatever scores is made of combinations, so a roll scores when one of them fits in it: a lone
-- die, a set of one face or a run. (Every roll decides a Farkle, so this stays cheaper than
-- Best.) With the table's points a roll is a Farkle exactly when it has no 1, no 5 and no face
-- three times: every run holds a 1 or a 5.
function FarkleRules.Farkle(dice)
	local c = Counts(dice)
	if not c then return nil end
	for f = 1, 6 do
		for m = 1, c[f] do
			if Unit(f, m) then return false end
		end
	end
	for _, run in ipairs(Runs()) do
		if Holds(c, run.c) then return false end
	end
	return true
end

function FarkleRules.HotDice(turn)
	return type(turn) == "table" and turn.hot == true
end

---------------------------------------------------------------------------
-- A turn
---------------------------------------------------------------------------

local Turn = {}
FarkleRules.Turn = Turn

function Turn.New()
	return { points = 0, left = FarkleRules.DICE, phase = "roll", rolls = 0, hot = false }
end

function Turn.Roll(t, roll)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase == "keep" then return nil, "keep" end
	local dice = FarkleRules.Decode(roll, t.left)
	if not dice then return nil, "range" end
	t.dice, t.kept, t.hot = dice, nil, false
	t.rolls = t.rolls + 1
	if FarkleRules.Farkle(dice) then
		t.farkle, t.lost, t.points = true, t.points, 0
		t.phase = "done"
		return dice, true
	end
	t.phase = "keep"
	return dice, false
end

-- Positions, not faces: two 5s of one roll are two different dice, and the table's messages
-- name them the same way on every client.
function Turn.Keep(t, positions)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase ~= "keep" then return nil, "roll" end
	if type(positions) ~= "table" then return nil, "dice" end
	local n = #positions
	if n < 1 or n > #t.dice then return nil, "dice" end
	local keys = 0
	for _ in pairs(positions) do keys = keys + 1 end
	if keys ~= n then return nil, "dice" end
	local seen, faces, kept = {}, {}, {}
	for i = 1, n do
		local p = positions[i]
		if not Int(p) or p < 1 or p > #t.dice or seen[p] then return nil, "dice" end
		seen[p] = true
		kept[i] = p
	end
	table.sort(kept)
	for i = 1, n do faces[i] = t.dice[kept[i]] end
	local points = FarkleRules.Score(faces)
	if not points then return nil, "score" end
	t.points = t.points + points
	t.left = t.left - n
	t.kept = kept
	if t.left == 0 then
		-- hot dice: every die set aside, so all six go back in the cup and the points stay
		t.left, t.hot = FarkleRules.DICE, true
	end
	t.phase = "decide"
	return points, t.hot
end

-- A bank needs dice set aside from the last roll: nobody banks without looking at his roll.
function Turn.Bank(t)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase == "keep" then return nil, "keep" end
	if t.phase ~= "decide" or t.points <= 0 then return nil, "empty" end
	t.banked = t.points
	t.phase = "done"
	return t.points
end

---------------------------------------------------------------------------
-- A game
---------------------------------------------------------------------------

function FarkleRules.New(opts)
	opts = opts or {}
	if type(opts) ~= "table" then return nil, "opts" end
	local target = opts.target
	if target == nil then target = FarkleRules.TARGET end
	if not Int(target) or target < 1 then return nil, "target" end
	local first = opts.first
	if first == nil then first = 1 end
	if first ~= 1 and first ~= 2 then return nil, "first" end
	local cap = opts.cap
	if cap == nil then
		-- a target without a cap could only end by a concession or a forfeit: the table offers
		-- the targets that have one, and any other needs its cap named
		cap = FarkleRules.TURN_CAP[target]
		if not cap then return nil, "target" end
	end
	if cap ~= false and (not Int(cap) or cap < 1) then return nil, "cap" end
	local players = {}
	if opts.players ~= nil then
		local p = opts.players
		if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string"
			or p[1] == "" or p[2] == "" or p[1]:lower() == p[2]:lower() then
			return nil, "players"
		end
		players = { p[1], p[2] }
	end
	return {
		players = players,
		target = target,
		cap = cap,
		first = first,
		current = first,
		scores = { 0, 0 },
		turns = { 0, 0 },
		timeouts = { 0, 0 },
		turn = Turn.New(),
		sudden = false,
		over = false,
	}
end

-- A realm's names are unique whatever their case, and a name reaches the table in more than one
-- spelling (the server's roll line, a message, the page), so names are compared in lower case.
local function Seat(game, who)
	if who == 1 or who == 2 then return who end
	if type(who) == "string" then
		who = who:lower()
		for i = 1, 2 do
			local name = game.players[i]
			if name and name:lower() == who then return i end
		end
	end
	return nil
end

-- What New made (a table dropped by the table's code arrives here as nil).
local function IsGame(game)
	return type(game) == "table" and type(game.turn) == "table" and type(game.players) == "table"
end

local function Actor(game, who)
	if not IsGame(game) then return nil, "game" end
	if game.over then return nil, "over" end
	local p = Seat(game, who)
	if not p then return nil, "player" end
	if p ~= game.current then return nil, "turn" end
	return p
end

local function Finish(game, winner, reason)
	game.over, game.winner, game.reason = true, winner, reason
	game.current = nil
end

-- A turn of seat p is over (banked, farkled, lost to the clock or to a foul): count it, then
-- see whether the game ends here, else hand the dice to the other player.
local function EndTurn(game, p, how)
	local t, o = game.turn, 3 - p
	local points = how == "bank" and t.banked or 0
	if how ~= "bank" and how ~= "farkle" then
		-- lost to the clock or a foul: like a Farkle, the turn's points go
		t.lost, t.points, t.phase = t.points, 0, "done"
	end
	game.scores[p] = game.scores[p] + points
	game.turns[p] = game.turns[p] + 1
	game.timeouts[p] = how == "timeout" and game.timeouts[p] + 1 or 0
	game.last = { who = p, how = how, points = points, lost = t.lost or 0, dice = t.dice }
	if game.timeouts[p] >= FarkleRules.TIMEOUTS then return Finish(game, o, "forfeit") end
	if not game.final then
		if how == "bank" and game.scores[p] >= game.target then
			game.final = o                 -- the other answers with one last turn
		elseif game.cap and game.turns[1] >= game.cap and game.turns[2] >= game.cap then
			game.final, game.capped = p, true
		end
	end
	if game.final == p then
		local mine, theirs = game.scores[p], game.scores[o]
		if mine ~= theirs then
			return Finish(game, mine > theirs and p or o, game.capped and "cap" or "target")
		end
		game.sudden = true                 -- level: one more turn each, in the same order
	end
	game.current = o
	game.turn = Turn.New()
end

function FarkleRules.Roll(game, who, roll)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	local dice, farkle = Turn.Roll(game.turn, roll)
	if not dice then return nil, farkle end
	if farkle then EndTurn(game, p, "farkle") end
	return dice, farkle
end

function FarkleRules.Keep(game, who, positions)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	return Turn.Keep(game.turn, positions)
end

function FarkleRules.Bank(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	local points, why = Turn.Bank(game.turn)
	if not points then return nil, why end
	EndTurn(game, p, "bank")
	return points
end

function FarkleRules.Timeout(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	EndTurn(game, p, "timeout")
	return true
end

function FarkleRules.Foul(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	EndTurn(game, p, "foul")
	return true
end

-- Either player may concede, on his turn or not.
function FarkleRules.Concede(game, who)
	if not IsGame(game) then return nil, "game" end
	if game.over then return nil, "over" end
	local p = Seat(game, who)
	if not p then return nil, "player" end
	Finish(game, 3 - p, "concede")
	return true
end

-- In "keep" the turn's left still counts the dice just thrown; what the next roll throws is known
-- once he sets some aside, so nothing is promised until then.
function FarkleRules.Expect(game)
	if not IsGame(game) or game.over then return nil end
	local t = game.turn
	if t.phase == "keep" then return game.current, t.phase, nil end
	return game.current, t.phase, t.left
end
