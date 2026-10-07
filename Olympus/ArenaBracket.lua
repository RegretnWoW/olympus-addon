local ADDON, ns = ...

-- The Blood Arena's knockout brackets (1.2): the championship's draw sheet, in the style of
-- Dragon Ball's World Martial Arts Tournament. Seeding, byes, the public draw from the
-- server's /roll, advancing winners, walkovers, a third-place match, best-of-1/3/5 series,
-- and how far each entrant went (the outright markets settle on it). Pure functions: no
-- events, no messages, no saved data, no game API. The only table a function changes is the
-- bracket passed to it; the tournament's messages, storage and screens are built on top.
--
-- An entrant is { id = <the fighter's GUID (the design's gk)>, name = <shown>, rating = <Elo>,
-- fights = <rated fights> } (rating and fights may be left out); a plain string is taken as
-- { id = <string> }. Other fields are copied along, and must be strings, numbers or booleans:
-- a table would be shared with the caller and between entrants. Ids are unique, and every tie
-- is broken on them in byte order. The bracket sets .seed, and the draw sets .drawn.
-- A bracket is a plain table: the field of 3 to 32 entrants in a size S of 4, 8, 16 or 32, the
-- smallest power of two that holds them (the rest are byes; the UI and the messages use 4 to 32;
-- two fighters would get byes in both semifinals of a 4, a bracket with no stage 3), R rounds
-- (2 to 5; round R is the final), matches keyed "<round>.<index>" ("1.1" is the top match of
-- the first round, "<R>.1" the final, "<R>.2" the third-place match). No table in it appears
-- twice, so it can go in saved variables (which copy a shared table apart on a reload) and be
-- copied freely.
--   bracket = { v = 1, size = S, rounds = R, n = <entrants>, third = <bool>,
--     bo = { [round] = 1|3|5 }, boThird = 1|3|5|nil,
--     entrants = { [id] = <entrant, with .seed, and .drawn = the draw's step when the draw
--       gave him his seed number rather than his rating (the sheet shows no seed for him)> },
--     seeds = { [seed] = id },
--     slots = { [position] = id | false (a bye) }, withdrawn = { [id] = true },
--     matches = { [key] = match } }
--   match = { key, round, index, third = true|nil, bo, a = <side>, b = <side>, sa, sb (games
--     won by each side), games = { { w = id, m = K|R }, ... }, done = true|nil, winner, loser,
--     method }
--   A side is an id, false (nobody: a bye, or no one came through), or nil (still waiting for
--   the match before it). A match's winner and loser are ids or false.
-- Methods: K knockout, R fled, D disqualified, W walkover (the caller's); B a bye (the other
-- side is nobody) and N nobody goes on (both absent, or both sides out), set by the bracket.
-- Failures return nil and a short code: "count", "entrant", "duplicate", "rating", "size",
-- "seeds", "bo", "roll", "rolls", "state", "match", "waiting", "decided", "winner", "method",
-- "score", "stage", "out" (the draw's functions also return the roll's step).
--
-- The draw
--   Size(n) -> S                   the smallest power of two that holds n entrants (3..32): 4..32
--   Order(S) -> { [position] = seed }   standard seeding (1 v S at the top, 2 at the bottom);
--                                  S is 4, 8, 16 or 32
--   PositionOf(S, seed) -> position
--   SeedCount(n) -> k              seeds kept out of the draw by default: max(2, S/4), at most n
--   Seed(entrants) -> list         copies in rating order: the best first, ties to more fights,
--                                  then to the id; unrated entrants last
--   The rolls: a list of
--     numbers                      the rolls taken, by step: rolls[s] is step s's roll (as
--                                  DrawState's rolls lists them, the draw's own record). A number
--                                  at any other place is refused ("rolls"), so a list heard with
--                                  one entry twice or missing can never shift the steps after it:
--                                  words heard go in as words, never appended as numbers
--     words { step = s, roll = r, max = m }   the drawer's word for step s (AD; max, the step's
--                                  /roll max, may be left out): what a spectator outside the raid
--                                  takes. A word counts for its own step wherever it stands, so
--                                  words may come in any order. A word whose roll (or max) is not
--                                  its step's is refused ("roll"), one for a step the draw does not
--                                  have too ("rolls"). A word for a step already heard is ignored
--                                  and flagged "again" (the same roll: heard twice) or "differs"
--                                  (another roll: the first heard counts), and one the draw never
--                                  reaches, because a word before it is missing, "ahead"
--     roll lines { roll = <value>, low = <lo>, high = <hi> }   (any other table) the drawer's
--                                  own /roll lines as this client read them, in the order heard
--                                  (ArenaParse.Roll; the caller keeps only the drawer's).
--                                  Farkle's W1 rule: each step takes the FIRST line whose range is
--                                  the one it needs (1 to the entrants still to draw); every other
--                                  line is ignored and flagged, never refused (CheckRoll gives the
--                                  same why), so rolling again gains nothing: { i = <its place in
--                                  the list>, after = <the steps taken before it>, why = "extra"
--                                  (the range of a step already taken: a roll again), "range" (a
--                                  range the draw does not need then: typed by hand, a later
--                                  step's, another roll; or no whole range at all), "roll" (the
--                                  right range, a value outside it or not a whole number: no
--                                  server line has one) or "done" (the draw needed no more rolls) }
--                                  The flags come in list order.
--   NextRoll(n, rolls, seeds) -> step, max    the /roll 1-max the draw needs next (nil when
--                                  complete). n: the entrants or their count; rolls: the rolls
--                                  so far (as above) or the count taken; seeds: as ApplyDraw's
--   CheckRoll(n, rolls, seeds, roll, lo, hi) -> true, step    whether a roll line (roll lo-hi)
--                                  is the one the draw needs next; else nil and the why DrawState
--                                  flags it with once it is added to rolls (or NextRoll's code)
--   DrawState(entrants, rolls, seeds) -> state    the draw so far, from the rolls (fewer than
--                                  it needs is fine). seeds: as ApplyDraw's.
--                                  state = { k = <seeded>, size = S, total = <rolls the whole
--                                  draw takes>, list = { the k seeds, then each entrant drawn so
--                                  far, in draw order }, left = { the entrants still to draw, in
--                                  byte order of their ids: the next roll r picks left[r] },
--                                  rolls = { [step] = the roll taken }, flags = { the lines and
--                                  words ignored, as above }, step = <the next roll's step> | nil
--                                  (complete), max = <its /roll max> }. The entrant drawn at
--                                  step s is list[k + s]: he is seed k + s, at position
--                                  PositionOf(size, k + s) (the design's AD slot), and carries
--                                  .drawn = s
--   NextRange(state) -> 1, max, step, position    the /roll the drawer makes next (RandomRoll(1,
--                                  max)), and where the entrant it picks goes; nil once the draw
--                                  is complete
--   ApplyDraw(entrants, rolls, seeds) -> list, flags    the seed list for Build once the draw is
--                                  complete: DrawState's list and flags (else nil, "rolls" and
--                                  the step it still needs). seeds: a count k (the top k by
--                                  Seed) or a list of ids in seed order (the promoter's word);
--                                  none, and the whole field is drawn
-- The bracket
--   Build(list, opts) -> bracket   list: the entrants in seed order (Seed's, or ApplyDraw's,
--                                  whose .drawn marks the seed numbers the draw gave);
--                                  opts: bo = 1|3|5, or per round as a list or digit string
--                                  counted back from the final ("135": final bo5, semifinals
--                                  bo3, every round before bo1); third = true for a
--                                  third-place match between the semifinal losers (in a field
--                                  of 3, the one semifinal loser takes it by a bye);
--                                  boThird (default: the semifinals' best-of)
--   Key(round, index) -> key
--   Match(bracket, key) -> match
--   Matches(bracket, round) -> { match, ... }   the round's matches, top to bottom
--   ThirdPlace(bracket) -> match | nil
-- Results (each changes the bracket; true when done, or nil and the code)
--   Game(bracket, key, winner, method) -> true, decided    one duel of the series (K or R);
--                                  the match is decided when a side reaches (bo+1)/2
--   Advance(bracket, key, winner, method, wins, losses) -> true    the whole match at once:
--                                  K or R with the winner's and the loser's games (1-0 by
--                                  default in a bo1; required in a bo3 or bo5); D or W with the
--                                  score so far (by default the games recorded)
--   Walkover(bracket, key, present) -> true      Advance with W
--   BothAbsent(bracket, key) -> true             nobody goes on; the next opponent has a bye
--   Withdraw(bracket, id) -> true                the entrant loses his current and any later
--                                  match by walkover, now or as soon as his opponent is known
-- Reading
--   Score(bracket, key) -> sa, sb, bo, need
--   Next(bracket) -> { match, ... }   the matches ready to fight (both sides known), in playing
--                                  order: by round, the third-place match before the final
--   CurrentRound(bracket) -> round | nil (finished)
--   MatchOf(bracket, id) -> match | nil          the entrant's next match (ready or waiting)
--   Reached(bracket, id) -> reached, alive       how far he went: the round he lost in (1..R),
--                                  R + 1 for the champion, "3" (a string) for the third-place
--                                  match's winner; while he is still in, the round he is placed
--                                  in. alive: whether reached can still change: while he can go
--                                  further, and for a semifinal loser until the third-place
--                                  match is decided (he may yet be "3"); not once he has
--                                  withdrawn, even while his next opponent is unknown. Once alive
--                                  is false, reached never changes: a result settles on it
--   Stage(reached, R) -> stage, label    how far that is, counted from the top, whatever the
--                                  size (the ST market's outcomes): 1 "champion", 2 "final"
--                                  (lost it), 3 "semifinal" (lost one: third place too),
--                                  4 "quarterfinal", 5 "earlier". It settles once Reached's
--                                  alive is false. nil, "stage" for anything else
--   Possible(S) -> { stage, ... }  the stages a bracket of size S produces, from the top
--                                  (4: 1-3; 8: 1-4; 16 and 32: 1-5): every one of them can
--                                  happen, and an ST outcome outside them is scratched. Per
--                                  size, not per entrant: after the draw, a first-round bye rules
--                                  out the first round's stage for the one who has it in sizes 4
--                                  to 16 (in 32, rounds 1 and 2 are both "earlier"), which is
--                                  the markets' to settle
--   Reaches(bracket, id, stage) -> true | false | nil (still open)    settles "reaches the
--                                  <stage>" and "wins the championship"; stage: "champion",
--                                  "final", "semifinal", "quarterfinal", "last16", "last32"
--                                  or a round number
--   Placing(bracket, id) -> place, label | nil (still has a match)    1 champion, 2 final
--                                  (the final's loser), 3 third, 4 fourth, else S/2^round + 1
--                                  and the round's name (a semifinal loser is 3rd, shared,
--                                  without a third-place match); false, "absent" when nobody
--                                  went on from his last match (N): nobody beat him, but he did
--                                  not fight for a place either. The same places as Podium's
--   RoundName(round, R) -> label   "final", "semifinal", "quarterfinal", "last16", "last32";
--                                  "champion" for R + 1
--   Champion(bracket) -> id | nil
--   Podium(bracket) -> first, second, { third, ... }    the third-place match's winner, or
--                                  without one both semifinal losers
--   Finished(bracket) -> true | false
-- A decided match never changes: the next round may already be under way. The tournament
-- advances a bout only once its fight is FINAL (after the grace for corrections).

local ArenaBracket = {}
ns.ArenaBracket = ArenaBracket

-- Entrants, and the bracket sizes they fill (the design: 4 to 32; 32 fit in the drawer's raid
-- for the draw). Three is the fewest: two would fill a bracket of 4 as the design reads, but with a
-- bye in both semifinals its first round holds no real match, so the semifinal stage that
-- Possible(4) promises could not happen (allowing two needs Possible to take n as well as S).
ArenaBracket.MIN, ArenaBracket.MAX = 3, 32
ArenaBracket.MIN_SIZE, ArenaBracket.MAX_SIZE = 4, 32
ArenaBracket.MAX_ROUNDS = 5 -- in a bracket of 32
ArenaBracket.BEST_OF = { [1] = true, [3] = true, [5] = true }
ArenaBracket.METHODS = { K = true, R = true, D = true, W = true } -- what a caller decides a match with
-- The rounds' names, counted back from the final (by the entrants a round holds: 2, 4, 8 ...).
ArenaBracket.ROUND_NAMES = { "final", "semifinal", "quarterfinal", "last16", "last32" }
-- How far an entrant went, counted from the top (Stage): the same five in every size, so the
-- outright markets can key on them before the size is known (the design).
ArenaBracket.STAGES = { "champion", "final", "semifinal", "quarterfinal", "earlier" }

local floor = math.floor

local function Whole(x) return type(x) == "number" and x == floor(x) end

-- Byte order, the same on every client: Lua's own < on strings follows the system's collation
-- (strcoll), which a client in another locale may not share, and a draw has to come out the
-- same on every screen.
local function Before(x, y)
	for i = 1, math.min(#x, #y) do
		local a, b = x:byte(i), y:byte(i)
		if a ~= b then return a < b end
	end
	return #x < #y
end

local function ById(x, y) return Before(x.id, y.id) end

local function RatingOrder(x, y)
	if x.rating ~= y.rating then
		if x.rating == nil then return false end
		if y.rating == nil then return true end
		return x.rating > y.rating
	end
	local fx, fy = x.fights or 0, y.fights or 0
	if fx ~= fy then return fx > fy end
	return Before(x.id, y.id)
end

-- What an entrant's field may hold: a table would be shared with the caller's list (and
-- between entrants given the same one), and a bracket must not share a table with anything.
local FIELD = { string = true, number = true, boolean = true }

-- The entrants as fresh tables (a string is an id), checked: 3 to 32, each with an id of its
-- own, and plain values only. Returns the list, or nil and the code.
local function Entrants(list)
	if type(list) ~= "table" then return nil, "count" end
	local n = #list
	if n < ArenaBracket.MIN or n > ArenaBracket.MAX then return nil, "count" end
	local out, seen = {}, {}
	for i = 1, n do
		local e, copy = list[i], {}
		if type(e) == "string" then
			copy.id = e
		elseif type(e) == "table" then
			for k, v in pairs(e) do
				if not FIELD[type(k)] or not FIELD[type(v)] then return nil, "entrant" end
				copy[k] = v
			end
		else
			return nil, "entrant"
		end
		if type(copy.id) ~= "string" or copy.id == "" then return nil, "entrant" end
		if copy.rating ~= nil and (type(copy.rating) ~= "number" or copy.rating ~= copy.rating) then return nil, "rating" end
		if copy.fights ~= nil and (type(copy.fights) ~= "number" or copy.fights ~= copy.fights) then return nil, "rating" end
		if seen[copy.id] then return nil, "duplicate" end
		seen[copy.id] = true
		copy.seed = nil
		out[i] = copy
	end
	return out
end

local function IsSize(S)
	if not Whole(S) or S < ArenaBracket.MIN_SIZE or S > ArenaBracket.MAX_SIZE then return false end
	while S > 2 do
		if S % 2 ~= 0 then return false end
		S = S / 2
	end
	return true
end

local function Rounds(S)
	local R = 0
	while S > 1 do S, R = S / 2, R + 1 end
	return R
end

local function IsRounds(R)
	return Whole(R) and R >= Rounds(ArenaBracket.MIN_SIZE) and R <= ArenaBracket.MAX_ROUNDS
end

local function Key(round, index) return ("%d.%d"):format(round, index) end
ArenaBracket.Key = Key

local function Need(bo) return (bo + 1) / 2 end

---------------------------------------------------------------------------
-- The draw
---------------------------------------------------------------------------

function ArenaBracket.Size(n)
	if not Whole(n) or n < ArenaBracket.MIN or n > ArenaBracket.MAX then return nil, "count" end
	local S = ArenaBracket.MIN_SIZE
	while S < n do S = S * 2 end
	return S
end

-- Standard seeding, as a printed draw sheet has it: seed 1 at the top, seed 2 at the bottom,
-- each half the mirror of the other, so the best two meet only in the final, the best four only
-- in the semifinals, and so on (when the better seed always wins, the seeds of a match in round
-- r add up to S/2^(r-1) + 1). In each first-round pair the better seed is on top, and the byes
-- (seeds above n) are the ones the top seeds face. For 16 (the design's list):
-- 1,16,8,9,5,12,4,13,3,14,6,11,7,10,2,15.
function ArenaBracket.Order(S)
	if not IsSize(S) then return nil, "size" end
	local order, m = { 1, 2 }, 2
	while m < S do
		local wider = {}
		for j, x in ipairs(order) do
			local y, k = 2 * m + 1 - x, #wider
			if j % 2 == 1 then
				wider[k + 1], wider[k + 2] = x, y
			else
				wider[k + 1], wider[k + 2] = y, x
			end
		end
		order, m = wider, 2 * m
	end
	for p = 1, S - 1, 2 do
		if order[p] > order[p + 1] then order[p], order[p + 1] = order[p + 1], order[p] end
	end
	return order
end

function ArenaBracket.PositionOf(S, seed)
	local order, err = ArenaBracket.Order(S)
	if not order then return nil, err end
	for p, s in ipairs(order) do
		if s == seed then return p end
	end
	return nil, "seeds"
end

-- The design's default: a quarter of the size, at least two, stay seeded by rating; the
-- rest are drawn.
function ArenaBracket.SeedCount(n)
	local S, err = ArenaBracket.Size(n)
	if not S then return nil, err end
	return math.min(n, math.max(2, S / 4))
end

function ArenaBracket.Seed(entrants)
	local list, err = Entrants(entrants)
	if not list then return nil, err end
	table.sort(list, RatingOrder)
	return list
end

local function Count(x)
	if type(x) == "table" then return #x end
	return x
end

-- How many entrants the rolls draw (all but the seeded ones), or nil and the code.
local function Drawn(n, seeds)
	n = Count(n)
	if not Whole(n) or n < ArenaBracket.MIN or n > ArenaBracket.MAX then return nil, "count" end
	local k = Count(seeds or 0)
	if not Whole(k) or k < 0 or k > n then return nil, "seeds" end
	return n - k
end

-- What a roll line is to the draw, with `left` entrants still to draw of the `m` the rolls draw:
-- nil when it is the roll that step needs (/roll 1-left), else the reason it is ignored. Each
-- step's range is its own (one fewer each step), so a line with the range of a step already
-- taken can only be a roll again. Its values are taken as they come (a line is never refused):
-- a range that is not whole numbers is no range the draw needs, and a roll that is not a whole
-- number in it is no roll it takes. DrawState's flags and CheckRoll both come from here.
local function Classify(left, m, roll, low, high)
	if left <= 1 then return "done" end -- the last one left needs no roll
	if not Whole(low) or not Whole(high) then return "range" end
	if low == 1 and high == left then
		if Whole(roll) and roll >= 1 and roll <= left then return nil end
		return "roll"
	end
	if low == 1 and high > left and high <= m then return "extra" end
	return "range"
end

-- The rolls the draw takes, one per step, from the list the caller gives (see "The rolls" at
-- the top): a number at its step's place as it is, a word at its own step (wherever it stands,
-- held until the steps before it are taken), and a roll line only when it is the first with the
-- range the next step needs (farkle W1: the first valid roll counts, at every witness).
-- Returns taken = { [step] = roll } and the flags of the entries ignored, in list order, or nil,
-- the code and the step: a hole or a key that is no place in the list, a number away from its
-- step's place or past the draw's last step, a word for a step the draw does not have
-- ("rolls"); a number or a word whose roll (or max) its step cannot take ("roll").
local function Taken(m, rolls)
	local taken, flags, ahead = {}, {}, {}
	if rolls == nil then return taken, flags end
	if type(rolls) ~= "table" then return nil, "rolls", 1 end
	-- Takes a step's roll, then any word already heard for the steps right after it.
	local function Take(step, roll)
		taken[step] = roll
		while ahead[#taken + 1] do
			local s = #taken + 1
			taken[s], ahead[s] = ahead[s].roll, nil
		end
	end
	-- Counted with pairs, never with #: a hole or a stray key must not cut the list short.
	local count = 0
	for _ in pairs(rolls) do count = count + 1 end
	for i = 1, count do
		local x, step = rolls[i], #taken + 1
		local left = m - step + 1
		if x == nil then
			return nil, "rolls", step
		elseif type(x) ~= "table" then
			-- more rolls than the draw takes, or a number that is not this step's
			if i ~= step or left < 1 then return nil, "rolls", step end
			if not Whole(x) or x < 1 or x > left then return nil, "roll", step end
			Take(step, x) -- a roll of 1 for the last one left is accepted
		elseif x.step ~= nil then
			local s = x.step
			if not Whole(s) or s < 1 or s > m then return nil, "rolls", step end
			local max = m - s + 1 -- the step's /roll max, whenever the word is heard
			if not Whole(x.roll) or x.roll < 1 or x.roll > max or (x.max ~= nil and x.max ~= max) then
				return nil, "roll", s
			end
			local had = taken[s] or (ahead[s] and ahead[s].roll)
			if had then
				flags[#flags + 1] = { i = i, after = step - 1, why = x.roll == had and "again" or "differs" }
			elseif s == step then
				Take(s, x.roll)
			else
				ahead[s] = { roll = x.roll, i = i, after = step - 1 }
			end
		else
			local why = Classify(left, m, x.roll, x.low, x.high)
			if why then
				flags[#flags + 1] = { i = i, after = step - 1, why = why }
			else
				Take(step, x.roll)
			end
		end
	end
	-- Words the draw never reached: a word before them is missing.
	if next(ahead) then
		for _, w in pairs(ahead) do flags[#flags + 1] = { i = w.i, after = w.after, why = "ahead" } end
		table.sort(flags, function(x, y) return x.i < y.i end)
	end
	return taken, flags
end

function ArenaBracket.NextRoll(n, rolls, seeds)
	local m, err = Drawn(n, seeds)
	if not m then return nil, err end
	local done
	if type(rolls) == "table" then
		local taken, why, step = Taken(m, rolls)
		if not taken then return nil, why, step end
		done = #taken
	else
		done = rolls or 0
		if not Whole(done) or done < 0 then return nil, "rolls" end
	end
	if done >= m - 1 then return nil end -- the last one left needs no roll
	return done + 1, m - done
end

-- A roll line counts for the draw only when it is the first with the range it needs next:
-- /roll 1-<max>, in range. Anything else (a roll again, another range, a roll typed by hand
-- with another max) is ignored, and the tool asks for that step again. The same classifier as
-- DrawState's, so a line added to the rolls after this check is flagged with this why.
function ArenaBracket.CheckRoll(n, rolls, seeds, roll, lo, hi)
	local step, max = ArenaBracket.NextRoll(n, rolls, seeds)
	if not step then return nil, max or "done" end
	local why = Classify(max, max + step - 1, roll, lo, hi)
	if why then return nil, why end
	return true, step
end

-- The public draw: the entrants to draw, sorted by id (so the list does not depend on the
-- order each client heard the sign-ups in), and each server roll picks one from those left:
-- the roll of step s is a /roll 1-(m-s+1), m the entrants drawn; the last one left needs no
-- roll. This is Fisher-Yates in its paper-and-pencil form: the list left keeps its order, so a
-- viewer can count the roll down the list on screen, and every client gets the same seed list
-- from the same roll lines. The state partway through is what the drawer's client sends after
-- each roll (AD) and what the overlay shows, so the tournament never sorts the pool itself (a
-- copy using Lua's own < could differ by client).
function ArenaBracket.DrawState(entrants, rolls, seeds)
	local list, err = Entrants(entrants)
	if not list then return nil, err end
	if rolls ~= nil and type(rolls) ~= "table" then return nil, "rolls", 1 end
	for _, e in ipairs(list) do e.drawn = nil end -- only this draw says who was drawn
	local out, pool = {}, {}
	if type(seeds) == "table" then
		local byId, seeded = {}, {}
		for _, e in ipairs(list) do byId[e.id] = e end
		if #seeds > #list then return nil, "seeds" end
		for i = 1, #seeds do
			local e = byId[seeds[i]]
			if not e or seeded[e.id] then return nil, "seeds" end
			seeded[e.id], out[i] = true, e
		end
		for _, e in ipairs(list) do
			if not seeded[e.id] then pool[#pool + 1] = e end
		end
	else
		local k = seeds or 0
		if not Whole(k) or k < 0 or k > #list then return nil, "seeds" end
		table.sort(list, RatingOrder)
		for i, e in ipairs(list) do
			if i <= k then out[i] = e else pool[#pool + 1] = e end
		end
	end
	table.sort(pool, ById)
	local k, m = #out, #pool
	local taken, flags, bad = Taken(m, rolls)
	if not taken then return nil, flags, bad end
	local state = { k = k, size = ArenaBracket.Size(#list), total = math.max(0, m - 1), list = out, left = pool,
		rolls = taken, flags = flags }
	for step = 1, m do
		local roll = taken[step]
		if roll == nil and #pool == 1 then roll = 1 end -- the last one left needs no roll
		if roll == nil then
			state.step, state.max = step, #pool
			break
		end
		local e = table.remove(pool, roll)
		e.drawn = step
		out[#out + 1] = e
	end
	return state
end

-- What the drawer's tool asks for next: RandomRoll(1, max) for that step, and the position the
-- entrant it picks goes to (the AD word's pos). A state that is not DrawState's gives "state".
function ArenaBracket.NextRange(state)
	if type(state) ~= "table" or not Whole(state.k) or not IsSize(state.size) then return nil, "state" end
	if state.step == nil then return nil end
	if not Whole(state.step) or not Whole(state.max) or state.max < 2 then return nil, "state" end
	local pos = ArenaBracket.PositionOf(state.size, state.k + state.step)
	if not pos then return nil, "state" end
	return 1, state.max, state.step, pos
end

function ArenaBracket.ApplyDraw(entrants, rolls, seeds)
	local state, err, step = ArenaBracket.DrawState(entrants, rolls, seeds)
	if not state then return nil, err, step end
	if state.step then return nil, "rolls", state.step end
	return state.list, state.flags
end

---------------------------------------------------------------------------
-- The bracket
---------------------------------------------------------------------------

-- Best-of per round. A list or digit string counts back from the final, because a tournament
-- sets it when it opens and its size is only known at the check-in: "135" is a bo5 final, bo3
-- semifinals and bo1 before, in a field of 5 or of 32 alike.
local function BestOf(spec, R)
	local given = {}
	if spec == nil then
		given[1] = 1
	elseif type(spec) == "number" then
		given[1] = spec
	elseif type(spec) == "string" then
		if not spec:match("^%d+$") then return nil end
		for c in spec:gmatch("%d") do given[#given + 1] = tonumber(c) end
	elseif type(spec) == "table" then
		-- Counted with pairs, never with #: a list with a hole ({ 1, nil, 5 }) has a length
		-- that depends on how the table was built, and would lose its final's best-of.
		local count = 0
		for _ in pairs(spec) do count = count + 1 end
		for i = 1, count do
			if spec[i] == nil then return nil end
			given[i] = spec[i]
		end
	end
	if #given == 0 then return nil end
	for i = 1, #given do
		if not ArenaBracket.BEST_OF[given[i]] then return nil end
	end
	local list = {}
	for r = 1, R do list[r] = given[math.max(1, #given - (R - r))] end
	return list
end

local function NewMatch(round, index, bo)
	return { key = Key(round, index), round = round, index = index, bo = bo, sa = 0, sb = 0, games = {} }
end

-- The bracket's matches in playing order: by round, top to bottom, the third-place match
-- before the final (as the championship plays it).
local function Ordered(br)
	local list = {}
	for r = 1, br.rounds do
		if r == br.rounds and br.third then list[#list + 1] = br.matches[Key(r, 2)] end
		for i = 1, br.size / 2 ^ r do list[#list + 1] = br.matches[Key(r, i)] end
	end
	return list
end

local function Decide(m, side, method, wins, losses)
	m.done, m.method = true, method
	if not side then
		m.winner, m.loser = false, false
		return
	end
	local other = side == "a" and "b" or "a"
	m.winner, m.loser = m[side], m[other]
	if wins then m["s" .. side], m["s" .. other] = wins, losses end
end

-- Who a decided match sends on: its winner to the next round, a semifinal's loser to the
-- third-place match.
local function Sent(feeder, third)
	if third then return feeder.loser end
	return feeder.winner
end

local function Out(br, side)
	return side == false or (side ~= nil and br.withdrawn[side] == true)
end

-- Fills each match from the ones before it and decides at once any match with nobody on a
-- side: a bye (B), a walkover against a withdrawn entrant (W), or nobody at all (N). One pass
-- in playing order is enough, since a match only feeds later rounds.
local function Flow(br)
	for _, m in ipairs(Ordered(br)) do
		if m.round > 1 and not m.done then
			local fa, fb
			if m.third then
				fa, fb = br.matches[Key(m.round - 1, 1)], br.matches[Key(m.round - 1, 2)]
			else
				fa, fb = br.matches[Key(m.round - 1, 2 * m.index - 1)], br.matches[Key(m.round - 1, 2 * m.index)]
			end
			if m.a == nil and fa.done then m.a = Sent(fa, m.third) end
			if m.b == nil and fb.done then m.b = Sent(fb, m.third) end
		end
		if not m.done and m.a ~= nil and m.b ~= nil then
			local outA, outB = Out(br, m.a), Out(br, m.b)
			if outA and outB then
				Decide(m, nil, "N")
			elseif outA then
				Decide(m, "b", m.a == false and "B" or "W")
			elseif outB then
				Decide(m, "a", m.b == false and "B" or "W")
			end
		end
	end
end

function ArenaBracket.Build(list, opts)
	opts = opts or {}
	local entrants, err = Entrants(list)
	if not entrants then return nil, err end
	local n = #entrants
	local S = ArenaBracket.Size(n)
	local R = Rounds(S)
	local bo = BestOf(opts.bo, R)
	if not bo then return nil, "bo" end
	local third, boThird = opts.third and true or false, nil -- every size has semifinals
	if third then
		boThird = opts.boThird or bo[R - 1]
		if not ArenaBracket.BEST_OF[boThird] then return nil, "bo" end
	end
	local br = { v = 1, size = S, rounds = R, n = n, third = third, bo = bo, boThird = boThird,
		entrants = {}, seeds = {}, slots = {}, withdrawn = {}, matches = {} }
	for seed, e in ipairs(entrants) do
		e.seed = seed
		br.entrants[e.id], br.seeds[seed] = e, e.id
	end
	local order = ArenaBracket.Order(S)
	for p = 1, S do
		br.slots[p] = order[p] <= n and br.seeds[order[p]] or false
	end
	for r = 1, R do
		for i = 1, S / 2 ^ r do
			local m = NewMatch(r, i, bo[r])
			if r == 1 then m.a, m.b = br.slots[2 * i - 1], br.slots[2 * i] end
			br.matches[m.key] = m
		end
	end
	if third then
		local m = NewMatch(R, 2, boThird)
		m.third = true
		br.matches[m.key] = m
	end
	Flow(br)
	return br
end

function ArenaBracket.Match(br, key) return br.matches[key] end

function ArenaBracket.Matches(br, round)
	local out = {}
	if not Whole(round) or round < 1 or round > br.rounds then return out end
	for i = 1, br.size / 2 ^ round do out[i] = br.matches[Key(round, i)] end
	return out
end

function ArenaBracket.ThirdPlace(br)
	if br.third then return br.matches[Key(br.rounds, 2)] end
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

-- A match that can take a result: known, not decided, both sides there.
local function Open(br, key)
	local m = br.matches[key]
	if not m then return nil, "match" end
	if m.done then return nil, "decided" end
	if not m.a or not m.b then return nil, "waiting" end
	return m
end

local function SideOf(m, id)
	if id ~= nil and id == m.a then return "a" end
	if id ~= nil and id == m.b then return "b" end
end

function ArenaBracket.Game(br, key, winner, method)
	local m, err = Open(br, key)
	if not m then return nil, err end
	local side = SideOf(m, winner)
	if not side then return nil, "winner" end
	if method ~= "K" and method ~= "R" then return nil, "method" end
	m.games[#m.games + 1] = { w = winner, m = method }
	local field = "s" .. side
	m[field] = m[field] + 1
	if m[field] < Need(m.bo) then return true, false end
	Decide(m, side, method)
	Flow(br)
	return true, true
end

-- A whole match's result. A knockout or a flight ends a series that the winner won: his games
-- are (bo+1)/2 and the loser's fewer. A disqualification or a walkover can end it at any
-- score, which stays what it was (neither side has won yet). A score never goes below the
-- games already recorded with Game.
function ArenaBracket.Advance(br, key, winner, method, wins, losses)
	local m, err = Open(br, key)
	if not m then return nil, err end
	local side = SideOf(m, winner)
	if not side then return nil, "winner" end
	if not ArenaBracket.METHODS[method] then return nil, "method" end
	local other = side == "a" and "b" or "a"
	local need, had, lost = Need(m.bo), m["s" .. side], m["s" .. other]
	if method == "K" or method == "R" then
		if wins == nil and losses == nil and m.bo == 1 then wins, losses = 1, 0 end
		if wins ~= need then return nil, "score" end
	else
		if wins == nil and losses == nil then wins, losses = had, lost end
		if not Whole(wins) or wins >= need then return nil, "score" end
	end
	if not Whole(wins) or not Whole(losses) or losses < lost or losses >= need or wins < had then return nil, "score" end
	Decide(m, side, method, wins, losses)
	Flow(br)
	return true
end

function ArenaBracket.Walkover(br, key, present)
	return ArenaBracket.Advance(br, key, present, "W")
end

function ArenaBracket.BothAbsent(br, key)
	local m, err = Open(br, key)
	if not m then return nil, err end
	Decide(m, nil, "N")
	Flow(br)
	return true
end

function ArenaBracket.Withdraw(br, id)
	if id == nil or not br.entrants[id] then return nil, "entrant" end
	if not ArenaBracket.MatchOf(br, id) then return nil, "out" end
	br.withdrawn[id] = true
	Flow(br)
	return true
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

function ArenaBracket.Score(br, key)
	local m = br.matches[key]
	if not m then return nil, "match" end
	return m.sa, m.sb, m.bo, Need(m.bo)
end

function ArenaBracket.Next(br)
	local out = {}
	for _, m in ipairs(Ordered(br)) do
		if not m.done and m.a and m.b then out[#out + 1] = m end
	end
	return out
end

function ArenaBracket.CurrentRound(br)
	for _, m in ipairs(Ordered(br)) do
		if not m.done then return m.round end
	end
end

function ArenaBracket.Finished(br)
	return ArenaBracket.CurrentRound(br) == nil
end

function ArenaBracket.MatchOf(br, id)
	if id == nil then return nil end
	for _, m in ipairs(Ordered(br)) do
		if not m.done and (m.a == id or m.b == id) then return m end
	end
end

-- The latest match of the draw proper (not the third-place match) that names him, and its
-- round.
local function Latest(br, id)
	for r = br.rounds, 1, -1 do
		for i = 1, br.size / 2 ^ r do
			local m = br.matches[Key(r, i)]
			if m.a == id or m.b == id then return r, m end
		end
	end
end

-- Every entrant is placed in the first round (a bye included), and a winner is sent on at
-- once, so the latest match that names him says how far he got: still in it, out there, or
-- the champion. A withdrawn entrant waiting for his opponent goes no further: that match can
-- only end in a walkover against him or with nobody going on. The round, always a number
-- (the third-place match is not a round of the draw).
local function Furthest(br, id)
	if id == nil or not br.entrants[id] then return nil, "entrant" end
	local r, m = Latest(br, id)
	if not m.done then return r, not br.withdrawn[id] end
	if m.winner == id then return r + 1, r < br.rounds end
	return r, false
end

-- The design: the round lost, R + 1 for the champion, "3" for the third-place match's winner
-- (by a bye or a walkover too, as Placing and Podium count him). Its loser lost his semifinal.
-- A semifinal loser is alive until the third-place match is decided, since winning it changes
-- his value from R - 1 to "3" (his stage stays 3 either way), unless he has withdrawn: then he
-- can only lose it by walkover or with nobody going on, and R - 1 stands.
function ArenaBracket.Reached(br, id)
	local r, alive = Furthest(br, id)
	if not r then return nil, alive end
	local t = ArenaBracket.ThirdPlace(br)
	if t and (t.a == id or t.b == id) then
		if t.done and t.winner == id then return "3", false end
		if not t.done and not br.withdrawn[id] then return r, true end
	end
	return r, alive
end

-- Counted from the top, a stage is the same in a bracket of 4 or of 32, and a bye never
-- changes it (it is not "rounds won"): a fighter out in the round before the semifinals lost
-- a quarterfinal, whether he fought in the round before it or had a bye.
function ArenaBracket.Stage(reached, R)
	if not IsRounds(R) then return nil, "stage" end
	local stage
	if reached == "3" then
		stage = 3 -- he lost his semifinal, then won the third-place match
	elseif Whole(reached) and reached >= 1 and reached <= R + 1 then
		stage = math.min(R - reached + 2, #ArenaBracket.STAGES)
	else
		return nil, "stage"
	end
	return stage, ArenaBracket.STAGES[stage]
end

-- Every stage down to the first round's is reachable in its size: S is the smallest power of
-- two over the field, so the first round holds at least one real match (n > S/2), and every
-- round after it too. The stages past the first round's are not.
function ArenaBracket.Possible(S)
	if not IsSize(S) then return nil, "size" end
	local out = {}
	for stage = 1, math.min(Rounds(S) + 1, #ArenaBracket.STAGES) do out[stage] = stage end
	return out
end

function ArenaBracket.RoundName(round, R)
	if not IsRounds(R) then return nil end
	if round == R + 1 then return "champion" end
	if not Whole(round) or round < 1 or round > R then return nil end
	return ArenaBracket.ROUND_NAMES[R - round + 1]
end

local function Target(br, stage)
	local R = br.rounds
	if Whole(stage) then
		if stage >= 1 and stage <= R + 1 then return stage end
		return nil
	end
	if stage == "champion" then return R + 1 end
	for j, label in ipairs(ArenaBracket.ROUND_NAMES) do
		if label == stage then
			if R - j + 1 >= 1 then return R - j + 1 end
			return nil
		end
	end
end

-- The outright markets: "wins the championship" is Reaches(id, "champion"). True once the
-- entrant is placed in that round (a bye or a walkover counts, as they do on the sheet), false
-- once he is out before it, nil while it is still open.
function ArenaBracket.Reaches(br, id, stage)
	local t = Target(br, stage)
	if not t then return nil, "stage" end
	local r, alive = Furthest(br, id)
	if not r then return nil, alive end
	if r >= t then return true end
	if not alive then return false end
	return nil
end

-- A place comes from the entrant's last match, the one Podium reads too: a loser there takes
-- the place of that round (the final's is 2nd, the third-place match's 4th). When nobody went
-- on from it (N), nobody beat him but he did not fight for the place either, so he takes none:
-- two no-shows in the final are not runners-up. None while he still has a match, even one he
-- is sure to lose (withdrawn): it may still end with nobody going on.
function ArenaBracket.Placing(br, id)
	local r, alive = Furthest(br, id)
	if not r then return nil, alive end
	if alive or ArenaBracket.MatchOf(br, id) then return nil end
	local R = br.rounds
	if r > R then return 1, "champion" end
	local _, last = Latest(br, id)
	local t = br.third and br.matches[Key(R, 2)]
	if t and (t.a == id or t.b == id) then last = t end -- a semifinal loser plays on for third
	if last.method == "N" then return false, "absent" end
	if last == t then
		if t.winner == id then return 3, "third" end
		return 4, "fourth"
	end
	if r == R then return 2, "final" end
	return br.size / 2 ^ r + 1, ArenaBracket.RoundName(r, R)
end

function ArenaBracket.Champion(br)
	local final = br.matches[Key(br.rounds, 1)]
	if final.done and final.winner then return final.winner end
end

function ArenaBracket.Podium(br)
	local R = br.rounds
	local final = br.matches[Key(R, 1)]
	local second
	if final.done and final.loser then second = final.loser end
	local thirds = {}
	if br.third then
		local t = br.matches[Key(R, 2)]
		if t.done and t.winner then thirds[1] = t.winner end
	elseif R >= 2 then
		for i = 1, 2 do
			local semi = br.matches[Key(R - 1, i)]
			if semi.done and semi.loser then thirds[#thirds + 1] = semi.loser end
		end
	end
	return ArenaBracket.Champion(br), second, thirds
end
