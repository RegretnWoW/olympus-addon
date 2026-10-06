local ADDON, ns = ...

-- The Blood Arena's ratings (1.2): Elo, the bronze/silver/gold tiers, records and streaks,
-- the weights that keep a rating from being farmed, the season carry-over, the championship
-- belts with their words, the number-one contender and the podium. Pure functions over a list
-- of fights (and, for the belts, the belt words): no events, no messages, no saved data, no
-- game API. Who may write a fight or a word, how it travels and where it is kept belong to
-- the ledger; this file only counts. Two clients holding the same fights and words get the
-- same numbers to the point, whatever order they reached them in: everything is taken in
-- (time, id) order, and every rating is an integer reached in integer steps.
--
-- A fight, one record of the arena's ledger:
--   { id = "k3x9a",         unique: a non-empty string or a whole number, read as text (7 and
--                           "7" are one id; an id seen twice counts once)
--     a = key, b = key,     the two fighters: character GUIDs, so a rename keeps the record
--     winner = key,         a or b
--     method = "knockout" | "fled" | "walkover",
--                           fled: the loser left the duel; walkover: the other never came
--     t = seconds,          server time of the result (the arbiter's GetServerTime)
--     duration = seconds,   optional (a walkover has none): from 0 to DURATION_MAX, or it is
--                           left out of the averages (the fight still counts)
--     arbiter = key,        optional; a fight judged by one of its own fighters never counts
--     aClass, bClass,       each fighter's class and race at the fight (the weigh-in): the
--     aRace, bRace,         class as Roster.ClassCode gives it ("MA"), the race as UnitRace's
--                           race ID (4); compared as text; nil or "" is no weigh-in
--     aLevel, bLevel,       each fighter's level at the weigh-in (1.1.6, the level factor
--                           below): a whole number from 1 to LEVEL_MAX, else none
--     title = category,     optional: the belt at stake, e.g. ArenaRating.GLOBAL
--     counts = true,        the ledger's word that it is rated (judged by a listed arbiter, and
--                           none of the unrated rules: alts, catchweight, too short, the day's
--                           or the pair's cap): anything but true and Build leaves it out.
--                           It has no say on the belts: a title fight is judged by `belt`
--     belt = true,          a title fight only: the ledger's word that it may move its belt
--                           (the design: judged by a public arbiter; by the arbiter's own facts
--                           no linked alts, net-off, catchweight or disqualification, both at
--                           max level). The rating caps the ledger works out (under 15 s, a
--                           fighter's 11th of the day, a pair's 4th in 7 days) never enter it,
--                           so a client holding only the core `titles` and `beltWords` gets the
--                           belts a client with the whole ledger gets. Anything but true and the
--                           fight moves no belt (rated or not)
--     rehearsal = true }    optional: a rehearsal never counts and moves no belt, whatever
--                           `counts` and `belt` say
-- The level factor (1.1.6, the owner's call: a duel's points consider the levels). The expected
-- score counts each level of difference as LEVEL_POINTS rating points, on top of the ratings' own
-- gap (and capped with it at GAP_CAP), so a win over a higher-level fighter is worth more, a win
-- over a much lower one little or nothing (16 levels down: the cap, and a change under half a
-- point rounds to 0), and a defeat by a much higher one costs little. Equal levels, or a fight
-- where either level is unknown, rate exactly as before. Whole numbers in and one formula, so
-- every client holding the same fights gets the same ratings.
-- Categories are short codes without a colon, so they survive the ledger's pieces:
-- "A" global (everyone), "C" .. class code (e.g. "CMA"), "R" .. race ID (e.g. "R4"). The
-- ledger must store Roster.ClassCode's two letters, as Honors does, or the codes won't match.
--
-- A belt word, one AV word as the ledger keeps it (who may give it, a public arbiter, and the
-- clerk for 2 and 3, is the ledger's to check):
--   { id,                   unique among the words, as a fight's id
--     kind = "S" | "V" | "C" | "U" | "2" | "3",
--                           S strip, V vacate: the holder named loses the belt at t;
--                           C: the number-one contender for CONTENDER_DAYS (a title
--                           tournament's winner gets one too); U: cancels the word `ref`;
--                           2, 3: the clerk's silver and bronze of the category
--     cat = category,       not for U
--     gk = key,             who the word is about: the holder (S, V), the contender (C), the
--                           podium place's fighter (2, 3: nil or "" is nobody)
--     t = seconds,          server time of the word
--     ref = id,             U only: the word it cancels
--     by = key,             the giver, for U's rule
--     king = true }         given by the King
--
-- Public functions (`built` is what Build returns, `belts` what Belts returns, `o` an
-- optional { now = server time, exclude = { [key] = true } or function(key) -> true when
-- that fighter can't be a contender: a debtor, net-off; facts only the caller has }):
--   Check(fight) -> true | false, why       whether a fight is rated; why: "not a fight",
--       "not counted", "rehearsal", "id", "fighters", "winner", "method", "time", "arbiter"
--   CheckTitle(fight) -> true | false, why  whether a fight touches the belt it names (if
--       its holder is in it or it is vacant); why: "not a fight", "rehearsal", "no title",
--       "no belt", "id", "fighters", "winner", "method", "time", "arbiter", "walkover",
--       "category" (both fighters not in it by the fight's weigh-in)
--   Expected(ra, rb, la, lb) -> per mille    a's expected score against b, 0 to 1000; la and lb
--       (optional) their levels: LevelGap's points join the ratings' gap
--   LevelGap(la, lb) -> rating points         b's levels over a's times LEVEL_POINTS (negative when a
--       is higher); 0 when either is no level (Level: a whole number from 1 to LEVEL_MAX)
--   KFactor(fights, settled, rating) -> K    for a fighter who has this many rated fights and
--       this rating before the fight: K_NEW while provisional (under NEW_FIGHTS and not
--       settled: carried out of it from last season), then K_HIGH from HIGH_RATING up, else K
--   Delta(rating, other, won, k, halvings, level, otherLevel) -> integer change of `rating`
--       after one fight, K x (score - expected) / 2^halvings rounded half up (the design's
--       floor(x + 0.5)); the expected score with the two levels when given (the level factor)
--   Build(fights, start) -> built            every rating, record and fight's change;
--       fights is a list or any table of fight records (the ledger's own map will do);
--       start (optional) is where the season starts, as Carry gives it: { [key] = { rating,
--       settled, class, race } }; anyone not in it starts at START. built.fighters[key],
--       built.log (the counted fights, oldest first, with their changes), built.skipped
--       ({ id, why } for each record left out, "duplicate" included)
--   CarryOver(rating) -> START + floor((rating - START) / 2): halfway back to the start
--   Carry(built) -> the next season's start: each fighter's CarryOver, settled when he had
--       NEW_FIGHTS rated fights this season, and his latest class and race
--   Rating(built, key) -> rating, rated fights (START and 0 for someone never seen)
--   Record(built, key) -> { key, rating, peak, fights, wins, losses, fled, streak, koWins,
--       koRate, avgDuration, woWins, woLosses, class, race, last, lastRated, settled }
--       fights = wins + losses + fled (the rated fights: walkovers apart, in woWins and
--       woLosses); losses: knocked out; fled: lost by leaving the duel; streak: +3 is three
--       wins in a row, -2 two defeats; koRate: the wins by knockout, in percent of the wins
--       (nil without a win); avgDuration: whole seconds, over the fights that have one (nil
--       without any); class and race: from the latest weigh-in that gave them (or the
--       carried ones); last: the time of his latest counted fight (a walkover too);
--       lastRated: of his latest rated one
--   Recent(built, key, n) -> the last n (a number or numeric text, default RECENT) counted
--       fights of key, newest first: { id, t, opponent, won, method, duration, title, rated,
--       halvings, delta, rating (after), opponentRating (before) }
--   HeadToHead(built, x, y) -> { fights (rated), walkovers, wins = { [x], [y] },
--       knockouts = { [x], [y] }, list (as Recent, from x's side, newest first) }
--   GLOBAL; ClassCategory(class), RaceCategory(race) -> category
--   ParseCategory(cat) -> "global" | "class", value | "race", value | nil
--   InCategory(built, key, cat) -> whether a fighter belongs to it (his latest class, race)
--   Categories(built) -> every category with a fighter: GLOBAL, then classes, then races
--   Ranking(built, cat, min) -> { { key, rating, fights, rank }, ... } best first, fighters
--       of the category (default GLOBAL) with at least `min` rated fights (default
--       RANKED_MIN); rank is shared by equal ratings ("1, 2, 2, 4"); equal ratings list by
--       more fights, then by key
--   Tiers(built, cat, belts) -> { [key] = "gold" | "silver" | "bronze" } (nil: no tier), cat
--       default GLOBAL; the rule is at TIER_SHARE below. With belts, a belt holder's tier is
--       at least gold for the global belt and silver for a class or race belt
--   CheckWord(word) -> true | false, why     why: "not a word", "id", "kind", "time",
--       "category", "fighter", "ref"
--   Belts(fights, words, now, vacWeeks) -> belts: every belt worked out from scratch from the
--       title fights CheckTitle passes and the words given, at `now` (nil: no clock, nothing
--       lapses but by a later event). vacWeeks is how long a holder keeps the belt without a
--       title fight won: a number of weeks for all history, or a schedule { { from = t,
--       weeks = n }, ... } in any order (the season words: at time t the step with the
--       latest `from` at or before t is in force, at the same `from` the shorter; before the
--       first step, VACANT_WEEKS; a step without a number `from` or a usable `weeks` is left
--       out). Each reign keeps the setting in force at its latest title win, so a later season's
--       word never rewrites an earlier reign. belts = { now, vac (seconds in force at now;
--       without a clock, the latest setting), belts = { [cat] = { cat, reigns (the
--       lineage), contender, podium } }, ignored = { { id, why } } }: why, for a word left
--       out, is CheckWord's or "duplicate", "undone", "unknown word", "not before", "not
--       his", "not the holder"
--   Prunable(words, now) -> { [id as text] = true }: the words a store may drop without
--       changing any belt (see "What the ledger must keep" below)
--   Holder(belts, cat) -> key, reign | nil        nil while vacant or never held
--   Belt(belts, cat) -> { cat, count (reigns in the lineage), holder, since, defences, last,
--       vacatesAt, fight, from, vacantSince, contender, contenderUntil, contenderWord,
--       podium = { [2] = key, [3] = key } (the clerk's words) } | nil for a belt with nothing
--       to show; holder to from only while held, vacantSince only while vacant after a reign
--   Lineage(belts, cat) -> every reign, oldest first (a copy): { holder, since, fight, from,
--       defences, last, vacates (last + the setting in force then), wins = { { t, fight,
--       beat } } (the title fights he won in it, the one that crowned him first, with the
--       fighter beaten), ends, how ("lost" | "inactive" | "stripped" | "vacated"), to,
--       lostIn, word (the S or V word's id) }
--   BeltsOf(belts, key) -> the categories key holds: global first, then class, race
--   Eligible(built, key, cat, o) -> true | false, why    contender status: in the category,
--       CONTENDER_MIN rated fights, one within ACTIVE_DAYS of o.now (no clock: not checked),
--       not excluded; why: "category", "fights", "inactive", "excluded"
--   Contender(built, belts, cat, o) -> key, rating, how ("word" | "table") | nil: the
--       number-one contender; o.now defaults to belts.now
--   Podium(built, belts, cat, o) -> { [1] = holder, [2] = silver, [3] = bronze } (any may
--       be nil), the category's podium from the table; o.now defaults to belts.now
-- A saved belts table that is not what Belts wrote (a hand edit, a bug) never makes the
-- queries fail: a broken belt reads as nothing to show.
--
-- What the ledger must keep. Belts works from scratch every time, so a title fight or a word
-- missing from its input changes history (a reign won from someone else, a stripped holder
-- back). Every title fight (with its `belt` flag and weigh-in) and every S and V word, with
-- the undos over them, are kept for good, whatever a store's cap. The only words that may go
-- are the ones Prunable names: a C word CONTENDER_DAYS after its time (it names nobody by
-- then), a 2 or 3 word once a later live word of the same place and category is held (if that
-- later word is undone afterwards, the place reads empty until the clerk's next word), and an
-- undo whose word may go. The words themselves must reach every client, backfilled like the
-- title fights: a client that never heard an S word keeps the stripped holder.
--
-- Inactivity counts title wins only (the design says any rated fight): a client holding only
-- the core `titles` and `beltWords` can't see the other fights, and the belts must come out
-- the same on every client. This waits for an amendment of the design or Daniel's word.

local ArenaRating = {}
ns.ArenaRating = ArenaRating

ArenaRating.START = 1500         -- every fighter's first rating
ArenaRating.K_NEW = 40           -- K for a fighter's first NEW_FIGHTS rated fights: a newcomer finds his level fast...
ArenaRating.NEW_FIGHTS = 10
ArenaRating.K = 24               -- ...and a settled rating moves slower...
ArenaRating.K_HIGH = 16          -- ...and slower still from HIGH_RATING up (the design)
ArenaRating.HIGH_RATING = 2000
ArenaRating.GAP_CAP = 800        -- a wider gap counts as this one (800 already expects 99%): an upset can't pay a fortune
ArenaRating.LEVEL_POINTS = 50    -- a level of difference counts as this many rating points (the level factor):
                                 -- 5 levels expect 81%, 10 levels 95%, 16 levels the cap's 99%
ArenaRating.LEVEL_MAX = 100      -- a level above this is a broken record: no level
ArenaRating.PAIR_WINDOW = 86400  -- the same two fighters within 24 h: their fights weigh 1, 1/2, 1/4...
ArenaRating.PAIR_HALVINGS = 16   -- ...1/65536 at most (a change that small is 0 anyway)
ArenaRating.RANKED_MIN = 5       -- rated fights for a tier and a place in the rankings
ArenaRating.TIERS = { "gold", "silver", "bronze" }            -- best first
ArenaRating.TIER_SHARE = { gold = 10, silver = 20, bronze = 30 } -- percent of the ranked fighters
ArenaRating.VACANT_WEEKS = 6     -- a holder without a title fight won for this long loses the belt, unless
                                 -- Belts is told otherwise (the season's word)
ArenaRating.CONTENDER_MIN = 10   -- rated fights for contender status (and the podium)...
ArenaRating.ACTIVE_DAYS = 30     -- ...with one of them this recent
ArenaRating.REMATCH_DAYS = 30    -- a fighter the holder beat in a title fight this recently waits his turn
ArenaRating.CONTENDER_DAYS = 28  -- a C word names the number-one contender for this long
ArenaRating.LINEAGE_MAX = 50     -- reigns kept per belt, the oldest go first
ArenaRating.RECENT = 10          -- fights Recent gives when not told how many
ArenaRating.DURATION_MAX = 3 * 3600 -- a longer fight is a broken record's number: left out of the averages
ArenaRating.GLOBAL = "A"

local floor, min, abs, huge = math.floor, math.min, math.abs, math.huge
local GLOBAL = ArenaRating.GLOBAL
local DAY = 86400
local WEEK = 7 * DAY
local METHODS = { knockout = true, fled = true, walkover = true }
local KIND_ORDER = { global = 1, class = 2, race = 3 }
local WORD_KINDS = { S = true, V = true, C = true, U = true, ["2"] = true, ["3"] = true }
local ENDS = { S = "stripped", V = "vacated" }
local RATING_LIMIT = 2 ^ 31      -- a carried rating past this is a broken record, not a fighter

-- num / den (den > 0) to the nearest integer, halves up: the design's floor(x + 0.5), so
-- 1.5 gives 2 and -1.5 gives -1. Integers in, so every client gets the same integer out.
local function RoundDiv(num, den)
	return floor((2 * num + den) / (2 * den))
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = Copy(x) end
	return out
end

local function Finite(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge end

-- A value as text that reads the same on every client: tostring of NaN or infinity differs
-- between Windows and Mac ("nan", "-nan(ind)", "1.#INF"), and of a table from one run to the next.
local function Text(v)
	if v == nil then return "" end
	if type(v) == "string" then return v end
	if Finite(v) then return tostring(v) end
	return "?" .. type(v)
end

-- A weigh-in fact (class code, race ID): a non-empty string or a finite number, else none.
-- Roster.ClassCode gives "" for an unknown class, and "" would make the category "C".
local function Fact(v)
	if (type(v) == "string" and v ~= "") or Finite(v) then return v end
	return nil
end

-- A fighter's level: a whole number from 1 to LEVEL_MAX, else none.
local function Level(v)
	if Finite(v) and v == floor(v) and v >= 1 and v <= ArenaRating.LEVEL_MAX then return v end
	return nil
end
ArenaRating.Level = Level

local function Duration(v)
	if Finite(v) and v >= 0 and v <= ArenaRating.DURATION_MAX then return v end
	return nil
end

-- A whole number or a non-empty string: an id is sorted and matched as text, which must read
-- the same on every client.
local function ValidId(id)
	return (type(id) == "string" and id ~= "") or (Finite(id) and id == floor(id))
end

local function Key(v) return type(v) == "string" and v ~= "" end

---------------------------------------------------------------------------
-- The fights: which count, and in what order
---------------------------------------------------------------------------

-- The fields every fight needs, rated or for a belt.
local function Sound(f)
	if not ValidId(f.id) then return false, "id" end
	local a, b = f.a, f.b
	if not Key(a) or not Key(b) or a == b then return false, "fighters" end
	if f.winner ~= a and f.winner ~= b then return false, "winner" end
	if not METHODS[f.method] then return false, "method" end
	if not Finite(f.t) then return false, "time" end
	if f.arbiter ~= nil and (f.arbiter == a or f.arbiter == b) then return false, "arbiter" end
	return true
end

function ArenaRating.Check(f)
	if type(f) ~= "table" then return false, "not a fight" end
	if f.counts ~= true then return false, "not counted" end
	if f.rehearsal then return false, "rehearsal" end
	return Sound(f)
end

-- The order every client takes the fights (and the words) in: by time, then by id (as text).
local function Before(x, y)
	if x.t ~= y.t then return x.t < y.t end
	return tostring(x.id) < tostring(y.id)
end

local function Signature(f)
	return table.concat({ f.a, f.b, f.winner, f.method, Text(f.duration), Text(f.title), Text(f.arbiter),
		Text(f.aClass), Text(f.bClass), Text(f.aRace), Text(f.bRace), Text(f.aLevel), Text(f.bLevel) }, "~")
end

-- Of two records with one id (a ledger should never hold them, but a double delivery or a
-- forger might), the one kept: the earlier, then the smaller by its fields. Every client
-- keeps the same one whatever order they came in, and the id counts once.
local function Preferred(x, y, sign)
	if x.t ~= y.t then return x.t < y.t end
	return sign(x) < sign(y)
end

local function SortSkipped(skipped)
	table.sort(skipped, function(x, y)
		if Text(x.id) ~= Text(y.id) then return Text(x.id) < Text(y.id) end
		return x.why < y.why
	end)
end

-- The records `check` passes, one per id, in order; each one left out goes into `skipped`.
local function Collect(records, check, sign, skipped)
	local byId = {}
	for _, f in pairs(type(records) == "table" and records or {}) do
		local ok, why = check(f)
		if not ok then
			skipped[#skipped + 1] = { id = type(f) == "table" and f.id or nil, why = why }
		else
			local id = tostring(f.id)
			local held = byId[id]
			if not held then
				byId[id] = f
			elseif Preferred(f, held, sign) then
				byId[id] = f
				skipped[#skipped + 1] = { id = held.id, why = "duplicate" }
			else
				skipped[#skipped + 1] = { id = f.id, why = "duplicate" }
			end
		end
	end
	local list = {}
	for _, f in pairs(byId) do list[#list + 1] = f end
	table.sort(list, Before)
	return list
end

-- The counted fights in order, and what was left out (sorted, so it reads the same anywhere).
local function Prepare(fights)
	local skipped = {}
	local list = Collect(fights, ArenaRating.Check, Signature, skipped)
	SortSkipped(skipped)
	return list, skipped
end

---------------------------------------------------------------------------
-- Elo
---------------------------------------------------------------------------

-- In per mille, so it is an integer. Only a gap of 0 or more is worked out; a's side of a
-- negative gap is 1000 less b's, so the two sides always add up to 1000 exactly. No gap from
-- 0 to 800 lands within a millionth of a half, so every client's pow rounds it alike.
function ArenaRating.LevelGap(la, lb)
	la, lb = Level(la), Level(lb)
	if not la or not lb then return 0 end
	return ArenaRating.LEVEL_POINTS * (lb - la)
end

-- (A negative gap is the other side's: 1000 less its expected score, so both sides always add up
-- to 1000, the levels' points included.)
function ArenaRating.Expected(ra, rb, la, lb)
	local gap = rb - ra + ArenaRating.LevelGap(la, lb)
	local flip = gap < 0
	if flip then gap = -gap end
	if gap > ArenaRating.GAP_CAP then gap = ArenaRating.GAP_CAP end
	local e = floor(1000 / (1 + 10 ^ (gap / 400)) + 0.5)
	return flip and 1000 - e or e
end

function ArenaRating.KFactor(fights, settled, rating)
	if settled ~= true and (tonumber(fights) or 0) < ArenaRating.NEW_FIGHTS then return ArenaRating.K_NEW end
	if Finite(rating) and rating >= ArenaRating.HIGH_RATING then return ArenaRating.K_HIGH end
	return ArenaRating.K
end

-- K times (score - expected), halved once for each earlier fight of the same two fighters
-- within PAIR_WINDOW, rounded half up. Each side is worked out with its own K (a newcomer's
-- is higher, a fighter's from 2000 lower), so a fight between a newcomer and a settled
-- fighter moves the newcomer more. With the two levels, the level factor's expected score.
function ArenaRating.Delta(rating, other, won, k, halvings, level, otherLevel)
	local e = ArenaRating.Expected(rating, other, level, otherLevel)
	local den = 1000 * 2 ^ min(halvings or 0, ArenaRating.PAIR_HALVINGS)
	return RoundDiv(k * ((won and 1000 or 0) - e), den)
end

-- How many rated fights of these two (a pair's times, oldest first) fall within the window
-- before time t: those make this one weigh less. The window slides with each fight, so it
-- doesn't depend on anyone's calendar or time zone.
local function Halvings(times, t)
	local n = 0
	for i = #times, 1, -1 do
		if t - times[i] >= ArenaRating.PAIR_WINDOW then break end
		n = n + 1
	end
	return n
end

local function NewFighter(key, rating)
	rating = rating or ArenaRating.START
	return { key = key, rating = rating, peak = rating, fights = 0, wins = 0, losses = 0, fled = 0,
		koWins = 0, woWins = 0, woLosses = 0, streak = 0, durSum = 0, durN = 0, log = {} }
end

local function Won(p, e)
	p.wins = p.wins + 1
	if e.method == "knockout" then p.koWins = p.koWins + 1 end
	p.streak = p.streak > 0 and p.streak + 1 or 1
end

local function Lost(p, e)
	if e.method == "fled" then p.fled = p.fled + 1 else p.losses = p.losses + 1 end
	p.streak = p.streak < 0 and p.streak - 1 or -1
end

-- The season's start: the fighters carried over, each at his carried rating. An entry that
-- is not what Carry writes (a hand edit) is left out: that fighter starts at START.
local function Start(start)
	local fighters = {}
	for key, s in pairs(type(start) == "table" and start or {}) do
		local rating = type(s) == "table" and s.rating
		if Key(key) and Finite(rating) and rating == floor(rating) and abs(rating) < RATING_LIMIT then
			local p = NewFighter(key, rating)
			p.settled = s.settled == true
			p.class, p.race = Fact(s.class), Fact(s.race)
			fighters[key] = p
		end
	end
	return fighters
end

function ArenaRating.Build(fights, start)
	local list, skipped = Prepare(fights)
	local fighters, log, pairTimes = Start(start), {}, {}
	local function Fighter(key)
		local p = fighters[key]
		if not p then p = NewFighter(key); fighters[key] = p end
		return p
	end
	for _, f in ipairs(list) do
		local a, b = Fighter(f.a), Fighter(f.b)
		-- The latest weigh-in says which class and race rankings a fighter is in.
		a.class, b.class = Fact(f.aClass) or a.class, Fact(f.bClass) or b.class
		a.race, b.race = Fact(f.aRace) or a.race, Fact(f.bRace) or b.race
		a.last, b.last = f.t, f.t
		local e = { id = f.id, t = f.t, a = f.a, b = f.b, winner = f.winner, method = f.method,
			duration = Duration(f.duration), title = f.title, aLevel = Level(f.aLevel), bLevel = Level(f.bLevel),
			aBefore = a.rating, bBefore = b.rating, aDelta = 0, bDelta = 0, halvings = 0,
			rated = f.method ~= "walkover" }
		local winner, loser = f.winner == f.a and a or b, f.winner == f.a and b or a
		if e.rated then
			-- A walkover says nothing about who fights better: it moves no rating, counts in no
			-- K or tier, and doesn't touch a streak. Every other counted fight is rated.
			local lo, hi = f.a < f.b and f.a or f.b, f.a < f.b and f.b or f.a
			pairTimes[lo] = pairTimes[lo] or {}
			local times = pairTimes[lo][hi] or {}
			pairTimes[lo][hi] = times
			e.halvings = Halvings(times, f.t)
			times[#times + 1] = f.t
			local aWon = f.winner == f.a
			e.aDelta = ArenaRating.Delta(a.rating, b.rating, aWon, ArenaRating.KFactor(a.fights, a.settled, a.rating), e.halvings, e.aLevel, e.bLevel)
			e.bDelta = ArenaRating.Delta(b.rating, a.rating, not aWon, ArenaRating.KFactor(b.fights, b.settled, b.rating), e.halvings, e.bLevel, e.aLevel)
			a.rating, b.rating = a.rating + e.aDelta, b.rating + e.bDelta
			if a.rating > a.peak then a.peak = a.rating end
			if b.rating > b.peak then b.peak = b.rating end
			a.fights, b.fights = a.fights + 1, b.fights + 1
			a.lastRated, b.lastRated = f.t, f.t
			Won(winner, e)
			Lost(loser, e)
			if e.duration then
				a.durSum, a.durN = a.durSum + e.duration, a.durN + 1
				b.durSum, b.durN = b.durSum + e.duration, b.durN + 1
			end
		else
			winner.woWins = winner.woWins + 1
			loser.woLosses = loser.woLosses + 1
		end
		e.aAfter, e.bAfter = a.rating, b.rating
		log[#log + 1] = e
		a.log[#a.log + 1] = e
		b.log[#b.log + 1] = e
	end
	return { fighters = fighters, log = log, skipped = skipped }
end

---------------------------------------------------------------------------
-- Seasons: the carry-over
---------------------------------------------------------------------------

-- Halfway back to START, rounded down (the design): 1700 -> 1600, 1301 -> 1400, 1299 -> 1399.
function ArenaRating.CarryOver(r)
	if not Finite(r) then return ArenaRating.START end
	return ArenaRating.START + floor((r - ArenaRating.START) / 2)
end

local function Fighters(built) return type(built) == "table" and type(built.fighters) == "table" and built.fighters or {} end

-- A fighter with NEW_FIGHTS rated fights this season starts the next out of the provisional
-- K. Everyone carries his latest class and race, so the class and race tables know him
-- before his first fight of the new season.
function ArenaRating.Carry(built)
	local out = {}
	for key, p in pairs(Fighters(built)) do
		out[key] = { rating = ArenaRating.CarryOver(p.rating), settled = p.fights >= ArenaRating.NEW_FIGHTS,
			class = p.class, race = p.race }
	end
	return out
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

function ArenaRating.Rating(built, key)
	local p = Fighters(built)[key]
	if not p then return ArenaRating.START, 0 end
	return p.rating, p.fights
end

function ArenaRating.Record(built, key)
	local p = Fighters(built)[key] or NewFighter(key)
	return {
		key = key, rating = p.rating, peak = p.peak, fights = p.fights,
		wins = p.wins, losses = p.losses, fled = p.fled, streak = p.streak,
		koWins = p.koWins, koRate = p.wins > 0 and floor(100 * p.koWins / p.wins + 0.5) or nil,
		avgDuration = p.durN > 0 and floor(p.durSum / p.durN + 0.5) or nil,
		woWins = p.woWins, woLosses = p.woLosses, class = p.class, race = p.race, last = p.last,
		lastRated = p.lastRated, settled = p.settled == true,
	}
end

-- One fight as key saw it.
local function View(e, key)
	local mine = e.a == key
	return {
		id = e.id, t = e.t, opponent = mine and e.b or e.a, won = e.winner == key, method = e.method,
		duration = e.duration, title = e.title, rated = e.rated, halvings = e.halvings,
		delta = mine and e.aDelta or e.bDelta, rating = mine and e.aAfter or e.bAfter,
		opponentRating = mine and e.bBefore or e.aBefore,
	}
end

function ArenaRating.Recent(built, key, n)
	local p, out = Fighters(built)[key], {}
	if not p then return out end
	n = floor(tonumber(n) or ArenaRating.RECENT)
	for i = #p.log, 1, -1 do
		if #out >= n then break end
		out[#out + 1] = View(p.log[i], key)
	end
	return out
end

function ArenaRating.HeadToHead(built, x, y)
	local out = { fights = 0, walkovers = 0, wins = {}, knockouts = {}, list = {} }
	if x == nil or y == nil then return out end
	out.wins[x], out.knockouts[x], out.wins[y], out.knockouts[y] = 0, 0, 0, 0
	if x == y then return out end
	local p = Fighters(built)[x]
	if not p then return out end
	for i = #p.log, 1, -1 do
		local e = p.log[i]
		if (e.a == x and e.b == y) or (e.a == y and e.b == x) then
			if e.rated then
				out.fights = out.fights + 1
				out.wins[e.winner] = out.wins[e.winner] + 1
				if e.method == "knockout" then out.knockouts[e.winner] = out.knockouts[e.winner] + 1 end
			else
				out.walkovers = out.walkovers + 1
			end
			out.list[#out.list + 1] = View(e, x)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Categories, rankings and tiers
---------------------------------------------------------------------------

function ArenaRating.ClassCategory(class) return Fact(class) and "C" .. tostring(class) or nil end
function ArenaRating.RaceCategory(race) return Fact(race) and "R" .. tostring(race) or nil end

function ArenaRating.ParseCategory(cat)
	if cat == GLOBAL then return "global" end
	if type(cat) ~= "string" or #cat < 2 then return nil end
	local kind, value = cat:sub(1, 1), cat:sub(2)
	if kind == "C" then return "class", value end
	if kind == "R" then return "race", value end
	return nil
end

local function Member(p, cat)
	local kind, value = ArenaRating.ParseCategory(cat)
	if kind == "global" then return true end
	if kind == "class" then return p.class ~= nil and tostring(p.class) == value end
	if kind == "race" then return p.race ~= nil and tostring(p.race) == value end
	return false
end

function ArenaRating.InCategory(built, key, cat)
	local p = Fighters(built)[key]
	return p ~= nil and Member(p, cat)
end

local function CategoryBefore(x, y)
	local kx, ky = KIND_ORDER[ArenaRating.ParseCategory(x) or ""] or 9, KIND_ORDER[ArenaRating.ParseCategory(y) or ""] or 9
	if kx ~= ky then return kx < ky end
	return x < y
end

function ArenaRating.Categories(built)
	local seen, out = {}, {}
	for _, p in pairs(Fighters(built)) do
		seen[GLOBAL] = true
		local c, r = ArenaRating.ClassCategory(p.class), ArenaRating.RaceCategory(p.race)
		if c then seen[c] = true end
		if r then seen[r] = true end
	end
	for cat in pairs(seen) do out[#out + 1] = cat end
	table.sort(out, CategoryBefore)
	return out
end

function ArenaRating.Ranking(built, cat, least)
	cat, least = cat or GLOBAL, least or ArenaRating.RANKED_MIN
	local out = {}
	for key, p in pairs(Fighters(built)) do
		if p.fights >= least and Member(p, cat) then
			out[#out + 1] = { key = key, rating = p.rating, fights = p.fights }
		end
	end
	table.sort(out, function(x, y)
		if x.rating ~= y.rating then return x.rating > y.rating end
		if x.fights ~= y.fights then return x.fights > y.fights end
		return x.key < y.key
	end)
	for i, r in ipairs(out) do
		r.rank = (i > 1 and out[i - 1].rating == r.rating) and out[i - 1].rank or i
	end
	return out
end

local TIER_RANK = { gold = 1, silver = 2, bronze = 3 }

-- The small ranking badge. Among the fighters with RANKED_MIN rated fights, best first, the
-- top 10% are gold, the next 20% silver, the next 30% bronze, the rest have none. Each share
-- is of the whole count, added up (10%, 30%, 60%) and rounded to the nearest fighter (halves
-- up), so together they hold 60% of the ranked, to the nearest fighter, however few there are:
--   1 ranked: bronze. 2: silver, none. 3 or 4: silver, bronze, the rest none.
--   5: gold, silver, bronze, none, none (gold needs 5 ranked: 10% of 5 rounds to 1).
--   10: 1 gold, 2 silver, 3 bronze, 4 none.
-- Equal ratings share a place, the better one (Ranking's rank), so two fighters tied on the
-- last gold place are both gold: a tier can hold more than its share, never less by a tie.
-- A walkover is no fight in the ring, so it never counts toward the RANKED_MIN.
-- The belts raise their holders (the design): the global belt is gold, a class or race belt at
-- least silver, whatever the holder's fights and place; that takes no place from anyone. In a
-- class or race table only the holders who belong to it show.
function ArenaRating.Tiers(built, cat, belts)
	cat = cat or GLOBAL
	local ranked = ArenaRating.Ranking(built, cat, ArenaRating.RANKED_MIN)
	local n, cuts, total, out = #ranked, {}, 0, {}
	for _, tier in ipairs(ArenaRating.TIERS) do
		total = total + ArenaRating.TIER_SHARE[tier]
		cuts[#cuts + 1] = { tier = tier, last = floor((n * total + 50) / 100) }
	end
	for _, r in ipairs(ranked) do
		for _, cut in ipairs(cuts) do
			if r.rank <= cut.last then out[r.key] = cut.tier; break end
		end
	end
	local held = type(belts) == "table" and type(belts.belts) == "table" and belts.belts or {}
	for bcat in pairs(held) do
		local holder = ArenaRating.Holder(belts, bcat)
		local kind = ArenaRating.ParseCategory(bcat)
		if holder and kind and (cat == GLOBAL or ArenaRating.InCategory(built, holder, cat)) then
			local want = kind == "global" and "gold" or "silver"
			local have = out[holder]
			if not have or TIER_RANK[want] < TIER_RANK[have] then out[holder] = want end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Belts
---------------------------------------------------------------------------
-- One belt per category: global, each class, each race. Belts works every belt out from
-- scratch, from the title fights and the words it is given, so a title fight or a word heard
-- late (a backfill from the clerk after a night offline) lands where it belongs, and every
-- client holding the same ones ends with the same belts. A reign in the lineage:
--   { holder, since, fight (the id won in), from (the holder beaten, nil if vacant),
--     defences, last (the time of the latest title fight won), vacates, wins, ends, how, to,
--     lostIn, word }
-- The rules (the design; everything in (time, fights before words, id) order):
--   - Only a title fight CheckTitle passes touches a belt: `belt` = true from the ledger, in
--     the ring (a walkover never: a belt is won and defended in the ring, and a holder who
--     stays away loses it to the inactivity below), both fighters in the category by the
--     fight's own weigh-in (a class belt is fought between two of that class). Whether it
--     was rated has no say: a 12 s knockout or a pair's 4th fight of the week takes the belt.
--   - A vacant belt goes to the winner of such a fight.
--   - A held belt changes hands only when its holder loses one ("lost"); when he wins, it is
--     a defence. A title fight without the holder leaves the belt alone (it may still be rated).
--   - A holder who has won no title fight for the vacancy setting in force at his latest
--     title win (since he took the belt or last defended it) loses it at that very second
--     ("inactive"). Only title fights count (see the header).
--   - S and V end the reign of the holder they name at their time ("stripped", "vacated");
--     a word naming someone who doesn't hold the belt then changes nothing.
--   - C names the number-one contender for CONTENDER_DAYS, until he fights a title fight
--     that touches the belt (he had his shot); a later C replaces it.
--   - 2 and 3 are the clerk's silver and bronze: the latest of each place counts, never for
--     the holder, and a word naming the fighter who held the other place takes him off it
--     (one fighter never shows as both, when the clerk's other word is lost or late).
--   - U cancels an earlier word as if it had never been given: the King's cancels anyone's,
--     anyone else's only his own. An undo can itself be undone.

local function VacantAfter(weeks)
	if not Finite(weeks) or weeks <= 0 then weeks = ArenaRating.VACANT_WEEKS end
	if not Finite(weeks) or weeks <= 0 then weeks = 6 end
	return floor(weeks * WEEK + 0.5)
end

-- vacWeeks as Belts takes it (see the header), as a function of time: the seconds a reign
-- lasts without a title win when that win came at t (no time: the latest setting).
local function Schedule(vacWeeks)
	if type(vacWeeks) ~= "table" then
		local vac = VacantAfter(vacWeeks)
		return function() return vac end
	end
	local steps = {}
	for _, s in pairs(vacWeeks) do
		if type(s) == "table" and Finite(s.from) and Finite(s.weeks) and s.weeks > 0 then
			steps[#steps + 1] = { from = s.from, vac = VacantAfter(s.weeks) }
		end
	end
	-- By time; at the same time the shorter last, so it is the one in force.
	table.sort(steps, function(x, y)
		if x.from ~= y.from then return x.from < y.from end
		return x.vac > y.vac
	end)
	local default = VacantAfter(nil)
	return function(t)
		if not Finite(t) then return steps[#steps] and steps[#steps].vac or default end
		local vac = default
		for _, s in ipairs(steps) do
			if s.from > t then break end
			vac = s.vac
		end
		return vac
	end
end

local function WordKind(k)
	if k == 2 or k == 3 then k = tostring(k) end
	return WORD_KINDS[k] and k or nil
end

function ArenaRating.CheckWord(w)
	if type(w) ~= "table" then return false, "not a word" end
	if not ValidId(w.id) then return false, "id" end
	local kind = WordKind(w.kind)
	if not kind then return false, "kind" end
	if not Finite(w.t) then return false, "time" end
	if kind == "U" then
		if not ValidId(w.ref) then return false, "ref" end
		return true
	end
	if not ArenaRating.ParseCategory(w.cat) then return false, "category" end
	if kind == "2" or kind == "3" then
		if w.gk ~= nil and type(w.gk) ~= "string" then return false, "fighter" end
	elseif not Key(w.gk) then
		return false, "fighter"
	end
	return true
end

local function WordSignature(w)
	return table.concat({ Text(WordKind(w.kind)), Text(w.cat), Text(w.gk), Text(w.ref), Text(w.by),
		w.king == true and "1" or "0" }, "~")
end

-- A reign as Belts writes it. Anything else in a saved copy is a hand edit or a bug.
local function SoundReign(r)
	return type(r) == "table" and r.holder ~= nil and Finite(r.since) and Finite(r.last)
		and type(r.defences) == "number" and (r.ends == nil or Finite(r.ends))
		and (r.vacates == nil or Finite(r.vacates))
end

local function SoundBelt(belt)
	if type(belt) ~= "table" or type(belt.reigns) ~= "table" then return false end
	for _, r in pairs(belt.reigns) do
		if not SoundReign(r) then return false end
	end
	return true
end

-- The queries' view of a belt: a broken one reads as nothing to show.
local function BeltOf(belts, cat)
	local belt = type(belts) == "table" and type(belts.belts) == "table" and belts.belts[cat] or nil
	return SoundBelt(belt) and belt or nil
end

local function Current(belt)
	local r = belt and belt.reigns[#belt.reigns]
	if r and r.ends == nil then return r end
	return nil
end

-- Whether the reign is over by inactivity at second t (no number: no clock, nothing lapses).
local function Lapse(belt, t)
	local r = Current(belt)
	if r and Finite(t) and r.vacates <= t then r.ends, r.how = r.vacates, "inactive" end
end

local function Loser(f) return f.winner == f.a and f.b or f.a end

local function Crown(belt, f, from, sched)
	belt.reigns[#belt.reigns + 1] = { holder = f.winner, since = f.t, fight = f.id, from = from, defences = 0,
		last = f.t, vacates = f.t + sched(f.t), wins = { { t = f.t, fight = f.id, beat = Loser(f) } } }
	while #belt.reigns > ArenaRating.LINEAGE_MAX do table.remove(belt.reigns, 1) end
end

local function BothIn(f, cat)
	local kind, value = ArenaRating.ParseCategory(cat)
	if kind == "global" then return true end
	if kind == "class" then
		local a, b = Fact(f.aClass), Fact(f.bClass)
		return a ~= nil and b ~= nil and tostring(a) == value and tostring(b) == value
	end
	if kind == "race" then
		local a, b = Fact(f.aRace), Fact(f.bRace)
		return a ~= nil and b ~= nil and tostring(a) == value and tostring(b) == value
	end
	return false
end

function ArenaRating.CheckTitle(f)
	if type(f) ~= "table" then return false, "not a fight" end
	if f.rehearsal then return false, "rehearsal" end
	if f.title == nil then return false, "no title" end
	if f.belt ~= true then return false, "no belt" end
	local ok, why = Sound(f)
	if not ok then return false, why end
	if f.method == "walkover" then return false, "walkover" end
	if not BothIn(f, f.title) then return false, "category" end
	return true
end

-- One title fight on its belt; true when it touched the belt (won vacant, defended, lost).
local function Fight(belt, f, sched)
	local r = Current(belt)
	if not r then
		Crown(belt, f, nil, sched)
	elseif r.holder == f.a or r.holder == f.b then
		if f.winner == r.holder then
			r.defences, r.last, r.vacates = r.defences + 1, f.t, f.t + sched(f.t)
			r.wins[#r.wins + 1] = { t = f.t, fight = f.id, beat = Loser(f) }
		else
			r.ends, r.how, r.to, r.lostIn = f.t, "lost", f.winner, f.id
			Crown(belt, f, r.holder, sched)
		end
	else
		return false
	end
	return true
end

-- Which words an undo cancels. From the latest back: an undo is live unless a later live
-- undo cancelled it, so undoing an undo gives the word back. An undo names a word before it.
local function Undone(list, ignored)
	local index, undone = {}, {}
	for i, w in ipairs(list) do index[tostring(w.id)] = i end
	for i = #list, 1, -1 do
		local u = list[i]
		if u.kind == "U" and not undone[i] then
			local j = index[tostring(u.ref)]
			local target = j and list[j]
			if not target then
				ignored[#ignored + 1] = { id = u.id, why = "unknown word" }
			elseif j >= i then
				ignored[#ignored + 1] = { id = u.id, why = "not before" }
			elseif not (u.king or (u.by ~= nil and u.by == target.by)) then
				ignored[#ignored + 1] = { id = u.id, why = "not his" }
			else
				undone[j] = true
			end
		end
	end
	for j in pairs(undone) do ignored[#ignored + 1] = { id = list[j].id, why = "undone" } end
	return undone
end

-- The words CheckWord passes, one per id, in order and in one shape, and which are undone.
local function Words(words, ignored)
	local list = Collect(words, ArenaRating.CheckWord, WordSignature, ignored)
	for i, w in ipairs(list) do
		list[i] = { id = w.id, kind = WordKind(w.kind), cat = w.cat, gk = Key(w.gk) and w.gk or nil, t = w.t,
			ref = w.ref, by = w.by, king = w.king == true }
	end
	return list, Undone(list, ignored)
end

-- Title fights before words in the same second, then by id.
local function EventBefore(x, y)
	if x.t ~= y.t then return x.t < y.t end
	if x.rank ~= y.rank then return x.rank < y.rank end
	return tostring(x.id) < tostring(y.id)
end

function ArenaRating.Belts(fights, words, now, vacWeeks)
	local sched, ignored = Schedule(vacWeeks), {}
	if not Finite(now) then now = nil end
	local events = {}
	local function Add(cat, ev)
		events[cat] = events[cat] or {}
		events[cat][#events[cat] + 1] = ev
	end
	for _, f in ipairs(Collect(fights, ArenaRating.CheckTitle, Signature, {})) do
		Add(f.title, { t = f.t, id = f.id, rank = 0, f = f })
	end
	local list, undone = Words(words, ignored)
	for i, w in ipairs(list) do
		if not undone[i] and w.kind ~= "U" then Add(w.cat, { t = w.t, id = w.id, rank = 1, w = w }) end
	end
	local out = { now = now, vac = sched(now), belts = {}, ignored = ignored }
	for cat, evs in pairs(events) do
		table.sort(evs, EventBefore)
		local belt = { cat = cat, reigns = {}, podium = {} }
		for _, ev in ipairs(evs) do
			Lapse(belt, ev.t)
			local f, w = ev.f, ev.w
			if f then
				local c = belt.contender
				if Fight(belt, f, sched) and c and (f.a == c.key or f.b == c.key) then belt.contender = nil end
			elseif ENDS[w.kind] then
				local r = Current(belt)
				if r and r.holder == w.gk then
					r.ends, r.how, r.word = w.t, ENDS[w.kind], w.id
				else
					ignored[#ignored + 1] = { id = w.id, why = "not the holder" }
				end
			elseif w.kind == "C" then
				belt.contender = { key = w.gk, t = w.t, ends = w.t + ArenaRating.CONTENDER_DAYS * DAY, word = w.id }
			else
				local place = tonumber(w.kind)
				belt.podium[place] = w.gk
				if w.gk ~= nil and belt.podium[5 - place] == w.gk then belt.podium[5 - place] = nil end
			end
		end
		Lapse(belt, now)
		local r, c = Current(belt), belt.contender
		if c and ((now and now >= c.ends) or (r and r.holder == c.key)) then belt.contender = nil end
		for place = 2, 3 do
			if r and belt.podium[place] == r.holder then belt.podium[place] = nil end
		end
		if #belt.reigns > 0 or belt.contender or next(belt.podium) then out.belts[cat] = belt end
	end
	SortSkipped(ignored)
	return out
end

-- What a store may drop (see "What the ledger must keep" in the header). An undo goes with
-- its word, so a word that stays keeps its undos and one that comes back can't return.
function ArenaRating.Prunable(words, now)
	local list, undone = Words(words, {})
	local latest = {} -- the latest live word of each place: [cat .. "~" .. place] = its index
	for i, w in ipairs(list) do
		if (w.kind == "2" or w.kind == "3") and not undone[i] then latest[w.cat .. "~" .. w.kind] = i end
	end
	local index, drop = {}, {}
	for i, w in ipairs(list) do
		index[tostring(w.id)] = i
		if w.kind == "C" then
			drop[i] = Finite(now) and w.t + ArenaRating.CONTENDER_DAYS * DAY <= now
		elseif w.kind == "2" or w.kind == "3" then
			local j = latest[w.cat .. "~" .. w.kind]
			drop[i] = j ~= nil and j > i
		elseif w.kind == "U" then
			-- Oldest first, and an undo only counts over a word before it: its word is decided.
			local j = index[tostring(w.ref)]
			drop[i] = j ~= nil and j < i and drop[j] == true
		end
	end
	local out = {}
	for i, w in ipairs(list) do
		if drop[i] then out[tostring(w.id)] = true end
	end
	return out
end

local function Vac(belts)
	local vac = type(belts) == "table" and belts.vac
	if Finite(vac) and vac > 0 then return vac end
	return VacantAfter(nil)
end

function ArenaRating.Holder(belts, cat)
	local r = Current(BeltOf(belts, cat))
	if not r then return nil end
	return r.holder, Copy(r)
end

function ArenaRating.Belt(belts, cat)
	local belt = BeltOf(belts, cat)
	if not belt then return nil end
	local out = { cat = cat, count = #belt.reigns, podium = {} }
	local r = Current(belt)
	if r then
		out.holder, out.since, out.defences, out.last = r.holder, r.since, r.defences, r.last
		out.vacatesAt, out.fight, out.from = r.vacates or r.last + Vac(belts), r.fight, r.from
	elseif #belt.reigns > 0 then
		out.vacantSince = belt.reigns[#belt.reigns].ends
	end
	local c = belt.contender
	if type(c) == "table" and Key(c.key) then
		out.contender, out.contenderUntil, out.contenderWord = c.key, c.ends, c.word
	end
	local podium = type(belt.podium) == "table" and belt.podium or {}
	for place = 2, 3 do
		if Key(podium[place]) then out.podium[place] = podium[place] end
	end
	return out
end

function ArenaRating.Lineage(belts, cat)
	local belt = BeltOf(belts, cat)
	return belt and Copy(belt.reigns) or {}
end

function ArenaRating.BeltsOf(belts, key)
	local out = {}
	if type(belts) ~= "table" or type(belts.belts) ~= "table" or key == nil then return out end
	for cat in pairs(belts.belts) do
		if type(cat) == "string" and ArenaRating.Holder(belts, cat) == key then out[#out + 1] = cat end
	end
	table.sort(out, CategoryBefore)
	return out
end

---------------------------------------------------------------------------
-- The number-one contender and the podium
---------------------------------------------------------------------------
-- Contender status (the design): in the category, CONTENDER_MIN rated fights this season with
-- one of them within ACTIVE_DAYS, and not excluded by the caller (a debtor, net-off). The
-- podium's silver and bronze are the two best such fighters but the holder, by the table
-- (the 2nd loses his silver as soon as someone overtakes him; a vacant belt still gives
-- both). The number-one contender is a C word's while it stands, else the best such
-- fighter, passing over one the holder beat within REMATCH_DAYS in a title fight that
-- touched this belt (the lineage's wins: last season's too, and not a walkover or a title
-- fight that moved nothing) unless nobody else has the status. The checks that need a clock
-- are skipped without one.

local function Clock(o, belts)
	if Finite(o.now) then return o.now end
	local now = type(belts) == "table" and belts.now
	return Finite(now) and now or nil
end

local function Excluded(o, key)
	local ex = o.exclude
	if type(ex) == "table" then return ex[key] and true or false end
	if type(ex) == "function" then return ex(key) and true or false end
	return false
end

function ArenaRating.Eligible(built, key, cat, o)
	cat, o = cat or GLOBAL, type(o) == "table" and o or {}
	local p = Fighters(built)[key]
	if not p or not Member(p, cat) then return false, "category" end
	if p.fights < ArenaRating.CONTENDER_MIN then return false, "fights" end
	if Finite(o.now) and not (p.lastRated and o.now - p.lastRated < ArenaRating.ACTIVE_DAYS * DAY) then
		return false, "inactive"
	end
	if Excluded(o, key) then return false, "excluded" end
	return true
end

-- The fighters with contender status but the holder, best first.
local function Pool(built, cat, holder, now, o)
	local check, out = { now = now, exclude = o.exclude }, {}
	for _, r in ipairs(ArenaRating.Ranking(built, cat, ArenaRating.CONTENDER_MIN)) do
		if r.key ~= holder and ArenaRating.Eligible(built, r.key, cat, check) then out[#out + 1] = r end
	end
	return out
end

-- Whether the holder beat key within REMATCH_DAYS of now in a title fight that touched this
-- belt: won it from him, or defended it against him, in this reign or an earlier one of his.
local function Beaten(belts, holder, key, cat, now)
	local belt = holder and now and BeltOf(belts, cat)
	if not belt then return false end
	local window = ArenaRating.REMATCH_DAYS * DAY
	for i = #belt.reigns, 1, -1 do
		local r = belt.reigns[i]
		if r.ends ~= nil and now - r.ends >= window then break end -- that reign and every older one
		if r.holder == holder and type(r.wins) == "table" then
			for _, w in pairs(r.wins) do
				if type(w) == "table" and w.beat == key and Finite(w.t) and now - w.t < window then return true end
			end
		end
	end
	return false
end

function ArenaRating.Contender(built, belts, cat, o)
	cat, o = cat or GLOBAL, type(o) == "table" and o or {}
	local now, holder = Clock(o, belts), ArenaRating.Holder(belts, cat)
	local view = ArenaRating.Belt(belts, cat)
	local word = view and view.contender
	if word and word ~= holder and not Excluded(o, word)
		and not (now and Finite(view.contenderUntil) and now >= view.contenderUntil) then
		return word, (ArenaRating.Rating(built, word)), "word"
	end
	local pool = Pool(built, cat, holder, now, o)
	for _, r in ipairs(pool) do
		if not Beaten(belts, holder, r.key, cat, now) then return r.key, r.rating, "table" end
	end
	if pool[1] then return pool[1].key, pool[1].rating, "table" end
	return nil
end

function ArenaRating.Podium(built, belts, cat, o)
	cat, o = cat or GLOBAL, type(o) == "table" and o or {}
	local holder = ArenaRating.Holder(belts, cat)
	local pool = Pool(built, cat, holder, Clock(o, belts), o)
	local out = {}
	out[1], out[2], out[3] = holder, pool[1] and pool[1].key, pool[2] and pool[2].key
	return out
end
