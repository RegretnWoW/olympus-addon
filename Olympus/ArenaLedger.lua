local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaLedger.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The results ledger (AE), clerk sync (AB, AQ), ratings and tiers through ArenaRating, belts and
-- their words (AV), seasons (AH), the Hall, and the games' ledger (AY, 1.1.6: every game played,
-- for the auditors and each player's own). Registers AE AB AQ AV AH AY. The ledger lives in
-- Arena.Heavy (the companion's saved variables); the clerk is never the King's character.
-- API (the design): Table(cat), Rating(gk), Record(gk), Tier(gk), Belts(), BeltOf(gk), Lineage(cat),
--   Season(), Hall(n), Clerk()
--   The games' ledger (1.1.6): Played(mode, record), MyGames(), AllGames(), GamesView(opts),
--   GamesCount(), GamesHello(name), GamesClerk(except), TakeGame(sender, mode, body),
--   GamesAuditor(name), SoloId()
local ArenaLedger = {}
ns.ArenaLedger = ArenaLedger

-- One ledger per realm (the design): the FINAL results of rated fights, keyed by the fighters'
-- GUIDs (gk). Every client works Elo, tiers and belts out of it with ArenaRating, so two clients
-- holding the same entries agree to the point (the design).
--
-- An entry (AE, the design): season~fid~t~cat~bo~gkA~A~fA~gkB~B~fB~sc~w~m~dur~gkArb~fl
--   fA / fB: the weigh-in's <class2><raceID>.<level> ("MA4.60"), "-" when the arbiter saw none;
--   sc "2:1"; w "A"|"B"; m K (knockout) R (fled) D (disqualified); dur the rounds' seconds in all;
--   fl the fight's flags (r rated by its arbiter, t title, b may move its belt, p public, k, c).
-- Taken from its arbiter (the sender, a listed arbiter), or in the clerk's carousel (AB~P) from a
-- public arbiter. Refused: a time ahead of the clock, an arbiter who is one of its fighters, a fid
-- already held with other content (the first kept, the conflict counted).
--
-- Where it lives (the design): the entries in the companion's heavy tables only (dropped while it is
-- not loaded: the clerk's carousel refills them); the title fights (titles), the belt and podium
-- words (beltWords) and the season word in the core, enough to verify a belt frame without the
-- ledger.
--
-- What counts (the design), worked out from the ledger alone so every client agrees:
-- the arbiter's r; never a rehearsal; the rounds at least MIN_RATED_DUR on average; a fighter's
-- 11th rated fight of a day (the UTC day of the server's clock, GetServerTime: one boundary every
-- client computes alike) and later are unrated; a pair's 4th in 7 days and later too.
-- The rest (the pair weights, K, the tiers) is ArenaRating's.
--
-- The rankings, the history and the events for the Arena window's one switchable view (the owner's
-- ask, 2026-09-30): ArenaLedger.RankingView(period, cat, page) with the periods (today, this week,
-- this month, all time) and categories (global, each class, each race) to switch between, and
-- ArenaLedger.History(opts); the events list is ArenaFights.Events.

local L = ns.L
local LG = ArenaLedger
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

LG.MIN_RATED_DUR = 15       -- seconds a round must last on average to be rated
LG.DAY_MAX = 10             -- rated fights of a fighter in a server day
LG.PAIR_MAX = 3             -- rated fights of a pair in PAIR_DAYS
LG.PAIR_DAYS = 7
LG.ENTRIES_MAX = 5000       -- per season
LG.TITLES_MAX = 500
LG.WORDS_MAX = 200
LG.HALL_MAX = 20
LG.AHEAD = 60
LG.DIGEST_EVERY = 900       -- the clerk's digest, every 15 minutes...
LG.DIGEST_JITTER = 90       -- ...give or take 90 s
LG.CLERK_HEARD = 600        -- a clerk heard this recently is the clerk...
LG.CLERK_SILENT = 1200      -- ...until silent this long, when the next takes over
LG.CLERK_WAIT = 120         -- a candidate waits this long after it could clerk before its first word
LG.PIECE = 240              -- bytes of an AB~P piece at most
LG.CAROUSEL_GAP = 300       -- a full turn of the carousel, then this pause
LG.WORD_REPEAT = 1800       -- belt words again every 30 minutes...
LG.WORD_DAYS = 7            -- ...for 7 days
LG.PODIUM_REPEAT = 3600     -- the podium words every 60 minutes
LG.SEASON_REPEAT = 1800
LG.ASK_GAP = 600            -- an ask of a kind at most every 10 minutes (AQ~F every 10 s)
LG.ASK_F_GAP = 10
LG.ANSWERS_MAX = 3          -- asks answered a minute
LG.WEEK = 7 * 86400
LG.DAY = 86400
-- Season 1 until a season word arrives: from the 1.2 release, 8 weeks, vacate after 6, defend 4,
-- brackets off (the design, an open question).
LG.RELEASE = 1790812800     -- 2026-10-01 00:00 UTC
LG.DEFAULT = { n = 1, start = LG.RELEASE, stop = LG.RELEASE + 8 * 7 * 86400, vac = 6, def = 4, brackets = 0 }
LG.PERIODS = { "today", "week", "month", "all" }
LG.PAGE = 10

local stats = { refused = {}, conflicts = 0, taken = 0, pieces = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function LG.Stats() return stats end

local function Now() return Arena.Now() end
local function F() return ns.ArenaFights end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Me(name) return Same(name, ns.me) end
local function Has(fl, c) return type(fl) == "string" and fl:find(c, 1, true) ~= nil end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end

---------------------------------------------------------------------------
-- Stores
---------------------------------------------------------------------------

local function CoreT(mode, key, make)
	if mode == "T" and not make and not Arena.Sim() and not (type(ns.rdb) == "table" and type(ns.rdb.arenaTest) == "table") then return nil end
	local s = Arena.Store(mode)
	if not s then return nil end
	if type(s[key]) ~= "table" then
		if not make then return nil end
		s[key] = {}
	end
	return s[key]
end
LG.CoreT = CoreT

-- This realm's (or the rehearsal's) ledger of a season: { list = { [fid] = entry }, n }, heavy only.
local function Book(mode, season, make)
	local h = Arena.Heavy(mode)
	if not h then return nil end
	if type(h.ledger) ~= "table" then
		if not make then return nil end
		h.ledger = {}
	end
	local b = h.ledger[season]
	if type(b) ~= "table" then
		if not make then return nil end
		b = { list = {}, n = 0 }
		h.ledger[season] = b
		-- Two seasons kept: the current and the last.
		local seasons = {}
		for k in pairs(h.ledger) do if type(k) == "number" then seasons[#seasons + 1] = k end end
		table.sort(seasons)
		for i = 1, #seasons - 2 do h.ledger[seasons[i]] = nil end
	end
	return b
end
LG.Book = Book

-- The generation of what the ratings were worked out from: anything new starts again.
local gen, built, builtGen = 0, {}, {}
local behind = {} -- [week] = true: the clerk's digest differs for it here (the carousel will fill it)
local digestHeard -- { season, hash }: the clerk's last digest (AB~D)
-- HONORS_CHANGED at most once per HONORS_GAP (the first at once, a burst's last after it): every
-- listener (Borders, Nameplates, the honours' inputs, the ratings' rebuild) runs once for a
-- carousel's pieces, not once per entry. The generation moves at once (the caches read it).
LG.HONORS_GAP = 2
local lastHonors, honorsDue = -math.huge, false
local function Honours()
	local now = Now()
	if now - lastHonors >= LG.HONORS_GAP then
		lastHonors = now
		ns.Fire("HONORS_CHANGED")
		return
	end
	if honorsDue then return end
	honorsDue = true
	Arena.After(LG.HONORS_GAP - (now - lastHonors), "ledger honours", function()
		honorsDue = false
		lastHonors = Now()
		ns.Fire("HONORS_CHANGED")
	end)
end
local function Bump()
	gen = gen + 1
	Honours()
	Arena.Changed()
end
LG.Bump = Bump

---------------------------------------------------------------------------
-- Seasons (AH, the design)
---------------------------------------------------------------------------

function LG.Season(mode)
	local s = CoreT(mode or "L", "season")
	if type(s) == "table" and tonumber(s.n) then return s end
	return LG.DEFAULT
end
-- The season a time falls in, by the season word in force (the default before any).
function LG.SeasonOf(t, mode)
	local s = LG.Season(mode)
	if t >= (s.start or 0) then return s.n end
	return math.max(1, (s.n or 1) - 1)
end

-- A season word: refused unless it starts no earlier than 7 days before the last one ends and lasts
-- 4 to 16 weeks. The newest counts; on the same second the King's.
function LG.TakeSeason(sender, mode, n, start, stop, vac, def, brackets, t)
	local R = ns.ArenaRoles
	if not (R.IsKing(sender) or R.IsPublicArbiter(sender, mode)) then return Count("sender") end
	if not (n and start and stop and vac and def and t) then return Count("shape") end
	if t > Now() + LG.AHEAD then return Count("time") end
	local len = stop - start
	if len < 4 * LG.WEEK or len > 16 * LG.WEEK then return Count("length") end
	local kept = LG.Season(mode)
	if n == kept.n then
		if kept.at and (t < kept.at or (t == kept.at and not R.IsKing(sender))) then return Count("older") end
	elseif n < kept.n then
		return Count("older")
	elseif n > kept.n + 1 + math.floor(math.max(0, Now() - (tonumber(kept.start) or Now())) / (4 * LG.WEEK)) then
		-- (1.2.0: no more seasons than could have passed since the one held began, 4 weeks being the
		-- shortest: one word cannot pin the season at 999 for good.)
		return Count("jump")
	elseif kept ~= LG.DEFAULT and start < (kept.stop or 0) - LG.WEEK then
		return Count("start")
	end
	local s = Arena.Store(mode)
	local was = s.season
	s.season = { n = n, start = start, stop = stop, vac = vac, def = def, brackets = brackets or 0, by = ns.FullName(sender), at = t }
	if not (type(was) == "table" and was.n == n) then
		local C = ns.Chronicle
		if C and not C.missing and C.Add then C.Add("arena", sender, L.ARENA_CHRONICLE_SEASON:format(n)) end
		-- The season before is over: its Hall entry (the design), from this client's own ledger; the
		-- launch season (LG.DEFAULT, no word ever said) too, when the first word opens a later one.
		if type(was) == "table" and tonumber(was.n) then LG.CloseSeason(was.n, mode)
		elseif n > LG.DEFAULT.n then LG.CloseSeason(LG.DEFAULT.n, mode) end
	end
	Bump()
	return true
end

-- The King or a public arbiter gives a season word (and his client repeats it every 30 minutes).
function LG.SetSeason(n, start, weeks, vac, def, brackets)
	local mode = "L"
	local t = Now()
	start = tonumber(start) or t
	local stop = start + (tonumber(weeks) or 8) * LG.WEEK
	local ok, why = LG.TakeSeason(ns.me, mode, tonumber(n), start, stop, tonumber(vac) or 6, tonumber(def) or 4, tonumber(brackets) or 0, t)
	if not ok then return false, why end
	LG.SendSeason()
	return true
end
function LG.SendSeason()
	local s = LG.Season("L")
	if s == LG.DEFAULT or not Me(s.by) then return end
	s.sentAt = Now()
	Arena.Send("AH", "L", table.concat({ B36(s.n), B36(s.start), B36(s.stop), B36(s.vac), B36(s.def), B36(s.brackets), B36(s.at) }, "~"), { key = "ah" })
end

local function OnSeason(dist, sender, mode, body)
	local n, start, stop, vac, def, brackets, t = Arena.Fields(body, 7)
	if not t then return Count("shape") end
	LG.TakeSeason(sender, mode, N(n, 1, 999), N(start, 0, 4294967295), N(stop, 0, 4294967295), N(vac, 1, 52), N(def, 1, 52),
		N(brackets, 0, 1), N(t, 0, 4294967295))
end
ns.Comm.Handle("AH", ns.Arena.Handle("AH", OnSeason))

---------------------------------------------------------------------------
-- Entries (AE)
---------------------------------------------------------------------------

local function Facts(s)
	if type(s) ~= "string" or s == "-" then return nil end
	local class, race, level = s:match("^(%u%u)(%d+)%.(%d+)$")
	if not class then return nil end
	return { class = class, race = tonumber(race), level = tonumber(level) }
end
local function FactsText(x)
	if type(x) ~= "table" or not (x.class and x.race and x.level) then return "-" end
	return ("%s%d.%d"):format(x.class, x.race, x.level)
end
LG.FactsText = FactsText

local function Encode(e)
	local W = F().Wire
	return table.concat({ B36(e.season), e.fid, B36(e.t), e.cat, tostring(e.bo), e.gkA, W(e.A), FactsText(e.fA), e.gkB, W(e.B), FactsText(e.fB),
		e.sc, e.w, e.m, B36(e.dur), e.gkArb or "-", e.fl ~= "" and e.fl or "-" }, "~")
end
LG.Encode = Encode

-- An entry from its fields (AE's body without the type, or a piece's entry): the table, or nil and why.
local function Decode(body, sender)
	local season, fid, t, cat, bo, gkA, A, fA, gkB, B, fB, sc, w, m, dur, gkArb, fl = Arena.Fields(body, 17)
	if not fl then return nil, "shape" end
	local Unwire = F().Unwire
	local e = { season = N(season, 1, 999), fid = fid, t = N(t, 0, 4294967295), cat = cat, bo = tonumber(bo), gkA = Gk(gkA), A = Unwire(A, sender),
		fA = Facts(fA), gkB = Gk(gkB), B = Unwire(B, sender), fB = Facts(fB), sc = sc, w = w, m = m, dur = N(dur, 0, 86400), gkArb = Gk(gkArb),
		fl = fl ~= "-" and fl or "" }
	if not (e.season and e.t and e.gkA and e.gkB and e.A and e.B and e.dur) then return nil, "shape" end
	if not fid:find("^F[0-9a-z]+$") or #fid > 20 then return nil, "fid" end
	if not tostring(cat):find("^[ACRB][%w]*$") or #cat > 4 then return nil, "cat" end
	if e.bo ~= 1 and e.bo ~= 3 and e.bo ~= 5 then return nil, "bo" end
	if not tostring(sc):find("^%d:%d$") or (w ~= "A" and w ~= "B") or not (m == "K" or m == "R" or m == "D") then return nil, "result" end
	if not e.fl:find("^[ptmokdcsrb]*$") then return nil, "flags" end
	if e.t > Now() + LG.AHEAD then return nil, "time" end
	if e.gkA == e.gkB or (e.gkArb and (e.gkArb == e.gkA or e.gkArb == e.gkB)) then return nil, "arbiter" end
	return e
end
LG.Decode = Decode

local function Content(e) return Encode(e) end

-- An entry taken (the arbiter's own AE, or the clerk's relay): kept in the heavy ledger (the title
-- fights in the core too). True when new. A fid already held with other content is a conflict: the
-- first kept, unless the new one is the fight's own arbiter's (e.auth: its AF held here names him,
-- or this is his own) and the held one is not: his replaces it (the design, the review's rule).
local function Keep(e, mode, via)
	if not Arena.Counts(mode) then return Count("rehearsal") end
	local season = LG.Season(mode)
	if e.season ~= season.n and e.season ~= season.n - 1 then return Count("season") end
	local book = Book(mode, e.season, true)
	local held = (book and book.list[e.fid]) or (CoreT(mode, "titles") or {})[e.fid]
	if held and Content(held) ~= Content(e) then
		stats.conflicts = stats.conflicts + 1
		if not (e.auth and not held.auth) then return Count("conflict") end
		-- The fight's own arbiter's entry replaces one somebody else put first.
		local titles = CoreT(mode, "titles")
		if titles then titles[e.fid] = nil end
		if book and book.list[e.fid] then book.list[e.fid] = nil book.n = math.max(0, book.n - 1) end
		Count("replaced")
	end
	-- A title fight: in the core whatever else (enough to verify a belt without the ledger).
	local fresh = false
	if Has(e.fl, "t") then
		local titles = CoreT(mode, "titles", true)
		local had = titles[e.fid]
		if had and Content(had) ~= Content(e) then stats.conflicts = stats.conflicts + 1 return Count("conflict") end
		if not had then
			titles[e.fid] = e
			fresh = true
			local n, list = 0, {}
			for fid, x in pairs(titles) do n = n + 1 list[#list + 1] = { fid = fid, t = x.t or 0 } end
			if n > LG.TITLES_MAX then
				table.sort(list, function(a, b) return a.t < b.t end)
				for i = 1, n - LG.TITLES_MAX do titles[list[i].fid] = nil end
			end
		end
	end
	if book then
		local had = book.list[e.fid]
		if had and Content(had) ~= Content(e) then stats.conflicts = stats.conflicts + 1 return Count("conflict") end
		if not had then
			if book.n >= LG.ENTRIES_MAX then return Count("full") end
			e.via = via
			book.list[e.fid] = e
			book.n = book.n + 1
			fresh = true
		end
	end
	if fresh then
		stats.taken = stats.taken + 1
		Bump()
		LG.ClerkChanged()
	end
	return fresh
end
LG.Keep = Keep

-- The arbiter writes the entry of a rated fight at FINAL (F.Finalize): sent once, must-deliver, and
-- kept here. (The fight's flags, all but x: whether it was open to betting stays on the fight.)
function LG.Write(f)
	local e = { season = LG.SeasonOf(f.graceEnd or Now(), f.mode), fid = f.fid, t = f.graceEnd or Now(), cat = f.cat, bo = f.bo,
		gkA = f.A.gk, A = f.A.name, fA = f.facts.A, gkB = f.B.gk, B = f.B.name, fB = f.facts.B,
		sc = (f.sc[1] or 0) .. ":" .. (f.sc[2] or 0), w = f.w, m = f.m, dur = f.dur or 0, gkArb = F().MyGk(), fl = ((f.fl or ""):gsub("x", "")),
		auth = true }
	if not (e.gkA and e.gkB) then return false, "gk" end
	if not (e.m == "K" or e.m == "R" or e.m == "D") then return false, "method" end
	Keep(e, f.mode, "own")
	-- (Kept with the fight, the arbiter's own record: an AQ~F is answered with it, the ledger loaded or not.)
	f.entry = Encode(e)
	Arena.Send("AE", f.mode, f.entry, { must = true })
	return true
end

local asked = {} -- [fid] = time: our own AQ~F (its AE by whisper is taken)
-- An AE from `sender`: the entry's own arbiter only (the design). The fight held here: its AF's
-- arbiter, nobody else (e.auth). Not held here: an arbiter who made its id (Arena.NewId's mark: a
-- challenge's private fight) or a public arbiter (a card's or a tournament's bout, whose id is its
-- promoter's); never one whose gkArb the game gives another character.
local function OnEntry(dist, sender, mode, body)
	local e, why = Decode(body, sender)
	if not e then return Count(why) end
	if dist == "WHISPER" and not asked[e.fid] then return Count("unasked") end
	local R = ns.ArenaRoles
	if not R.IsArbiter(sender, mode) then return Count("arbiter") end
	local f = F().Find("fights", e.fid)
	if f then
		if not f.arb or Has(f.fl, "d") then return Count("direct") end
		if not Same(sender, f.arb) then return Count("not-arbiter") end
		e.auth = true
	elseif not (F().MadeBy(e.fid, sender) or R.IsPublicArbiter(sender, mode)) then
		return Count("not-arbiter")
	end
	local P = ns.ArenaProfile
	if e.gkArb and P and P.VerifyGk and P.VerifyGk(sender, e.gkArb) == false then return Count("gk") end
	e.arbName = ns.FullName(sender)
	-- A title fight moves a belt only from a public arbiter.
	if Has(e.fl, "b") and not R.IsPublicArbiter(sender, mode) then e.fl = e.fl:gsub("b", "") end
	Keep(e, mode, "arbiter")
end
ns.Comm.Handle("AE", ns.Arena.Handle("AE", OnEntry))

-- Every entry held, of a season (the current by default), as a list.
function LG.Entries(season, mode)
	mode = mode or "L"
	season = season or LG.Season(mode).n
	local out = {}
	local book = Book(mode, season)
	for _, e in pairs(book and book.list or {}) do out[#out + 1] = e end
	table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.fid < b.fid end)
	return out
end

---------------------------------------------------------------------------
-- What counts, and the ratings (ArenaRating)
---------------------------------------------------------------------------

-- Each entry's `counts`, from the ledger alone (sorted by time, then fid).
function LG.Counted(list)
	local day, pairs_ = {}, {}
	local out = {}
	for _, e in ipairs(list) do
		local ok = Has(e.fl, "r")
		local a, b = e.sc:match("^(%d):(%d)$")
		local rounds = math.max(1, (tonumber(a) or 0) + (tonumber(b) or 0))
		if ok and (e.dur or 0) < LG.MIN_RATED_DUR * rounds then ok = false end
		local d = math.floor(e.t / LG.DAY)
		if ok then
			for _, gk in ipairs({ e.gkA, e.gkB }) do
				local k = gk .. "|" .. d
				if (day[k] or 0) >= LG.DAY_MAX then ok = false end
			end
		end
		local pk = e.gkA < e.gkB and (e.gkA .. "|" .. e.gkB) or (e.gkB .. "|" .. e.gkA)
		if ok then
			local recent = 0
			for _, t in ipairs(pairs_[pk] or {}) do if e.t - t < LG.PAIR_DAYS * LG.DAY then recent = recent + 1 end end
			if recent >= LG.PAIR_MAX then ok = false end
		end
		if ok then
			for _, gk in ipairs({ e.gkA, e.gkB }) do day[gk .. "|" .. d] = (day[gk .. "|" .. d] or 0) + 1 end
			pairs_[pk] = pairs_[pk] or {}
			table.insert(pairs_[pk], e.t)
		end
		out[e.fid] = ok
	end
	return out
end

local METHOD = { K = "knockout", R = "fled", D = "knockout" }
-- An entry as ArenaRating takes a fight.
local function Fight(e, counts)
	return { id = e.fid, a = e.gkA, b = e.gkB, winner = e.w == "A" and e.gkA or e.gkB, method = METHOD[e.m] or "knockout", t = e.t,
		duration = e.dur, arbiter = e.gkArb, aClass = e.fA and e.fA.class, bClass = e.fB and e.fB.class,
		aRace = e.fA and e.fA.race and tostring(e.fA.race), bRace = e.fB and e.fB.race and tostring(e.fB.race),
		aLevel = e.fA and e.fA.level, bLevel = e.fB and e.fB.level, -- (the weigh-in's levels: the level factor)
		title = Has(e.fl, "t") and e.cat or nil, counts = counts, belt = Has(e.fl, "b") and Has(e.fl, "t") }
end
LG.Fight = Fight

-- The season's ratings (ArenaRating.Build), from the last season's carry-over; kept until anything
-- changes (a generation), or nil while the companion is not loaded (no ledger here).
function LG.Built(mode, season)
	mode = mode or "L"
	local s = LG.Season(mode)
	season = season or s.n
	local key = mode .. ":" .. season
	if built[key] and builtGen[key] == gen then return built[key] end
	local R = ns.ArenaRating
	if not R or not Arena.Heavy(mode) then return nil end
	local start
	if season > 1 then
		local prev = LG.Built(mode, season - 1)
		if prev then start = R.Carry(prev) end
	end
	local list = LG.Entries(season, mode)
	local counts = LG.Counted(list)
	local fights = {}
	for _, e in ipairs(list) do fights[#fights + 1] = Fight(e, counts[e.fid]) end
	built[key] = R.Build(fights, start)
	builtGen[key] = gen
	return built[key]
end

function LG.Table(cat, mode) local b = LG.Built(mode) return b and ns.ArenaRating.Ranking(b, cat or "A") or {} end
function LG.Rating(gk, mode)
	local b = LG.Built(mode)
	if not b then return nil end
	return ns.ArenaRating.Rating(b, gk)
end
function LG.Record(gk, mode) local b = LG.Built(mode) return b and ns.ArenaRating.Record(b, gk) or nil end
-- A's expected score against B, per mille (the biggest upset's award), or nil.
function LG.Expected(gkA, gkB, mode)
	local b = LG.Built(mode)
	if not b or not gkA or not gkB then return nil end
	local R = ns.ArenaRating
	return R.Expected((R.Rating(b, gkA)), (R.Rating(b, gkB)))
end

-- The tiers (the arena division: bronze, silver, gold), with the belt holders' floors.
function LG.Tiers(mode)
	local b = LG.Built(mode)
	if not b then return {} end
	return ns.ArenaRating.Tiers(b, "A", LG.BeltState(mode))
end
function LG.Tier(gk, mode) return LG.Tiers(mode)[gk] end

---------------------------------------------------------------------------
-- Belts and their words (AV, the design)
---------------------------------------------------------------------------

-- The season words in force as ArenaRating's vacWeeks schedule.
local function VacSchedule(mode)
	local s = LG.Season(mode)
	return { { from = 0, weeks = LG.DEFAULT.vac }, { from = s.start or 0, weeks = s.vac or LG.DEFAULT.vac } }
end

local beltCache, beltGen = {}, {}
-- ArenaRating.Belts over the core's title fights and belt words (every client can: no ledger needed).
function LG.BeltState(mode)
	mode = mode or "L"
	if beltCache[mode] and beltGen[mode] == gen and beltCache[mode].at == math.floor(Now() / 60) then return beltCache[mode].belts end
	local R = ns.ArenaRating
	local fights, words = {}, {}
	for _, e in pairs(CoreT(mode, "titles") or {}) do fights[#fights + 1] = Fight(e, Has(e.fl, "r")) end
	for _, w in pairs(CoreT(mode, "beltWords") or {}) do words[#words + 1] = w end
	local belts = R.Belts(fights, words, Now(), VacSchedule(mode))
	beltCache[mode] = { belts = belts, at = math.floor(Now() / 60) }
	beltGen[mode] = gen
	return belts
end

-- { [cat] = ArenaRating.Belt(...) } for every belt with something to show.
function LG.Belts(mode)
	local belts = LG.BeltState(mode)
	local out = {}
	for cat in pairs(belts and belts.belts or {}) do out[cat] = ns.ArenaRating.Belt(belts, cat) end
	return out
end
function LG.BeltOf(gk, mode) return ns.ArenaRating.BeltsOf(LG.BeltState(mode), gk) end
function LG.Lineage(cat, mode) return ns.ArenaRating.Lineage(LG.BeltState(mode), cat) end

-- The belt holders and the clerk's podium words, as Honors takes them: { cat, guid, name } lists.
function LG.Holders(mode)
	local out = {}
	local belts = LG.BeltState(mode)
	for cat in pairs(belts and belts.belts or {}) do
		local gk = ns.ArenaRating.Holder(belts, cat)
		if gk then out[#out + 1] = { cat = cat, guid = Arena.GuidOf(gk) or gk, gk = gk, name = LG.NameOf(gk, mode) } end
	end
	return out
end
function LG.PodiumWords(mode)
	local out = {}
	local belts = LG.BeltState(mode)
	for cat in pairs(belts and belts.belts or {}) do
		local b = ns.ArenaRating.Belt(belts, cat)
		for place = 2, 3 do
			local gk = b and b.podium and b.podium[place]
			if gk and gk ~= "" then out[#out + 1] = { cat = cat, place = place, guid = Arena.GuidOf(gk) or gk, gk = gk, name = LG.NameOf(gk, mode) } end
		end
	end
	return out
end

-- The name the ledger (or a word) last gave a gk, or nil.
function LG.NameOf(gk, mode)
	for _, e in pairs(CoreT(mode or "L", "titles") or {}) do
		if e.gkA == gk then return e.A end
		if e.gkB == gk then return e.B end
	end
	for _, w in pairs(CoreT(mode or "L", "beltWords") or {}) do if w.gk == gk and w.name then return w.name end end
	for _, e in ipairs(LG.Entries(nil, mode or "L")) do
		if e.gkA == gk then return e.A end
		if e.gkB == gk then return e.B end
	end
	return nil
end

local wordNo = 0
local function WordId()
	wordNo = wordNo + 1
	return "V" .. B36(Now()) .. Arena.Hash36(tostring(ns.me):lower(), 2) .. B36(wordNo)
end

local function EncodeWord(w)
	return table.concat({ w.id, w.cat or "-", w.kind, w.gk or "-", B36(w.t), w.reason or "-", w.ref or "-" }, "~")
end

-- A belt word taken: from a public arbiter (the clerk for 2 and 3); U per the design (ArenaRating).
function LG.TakeWord(sender, mode, w)
	local R = ns.ArenaRoles
	if not R.IsPublicArbiter(sender, mode) then return Count("sender") end
	if not Arena.Counts(mode) then return Count("rehearsal") end
	if w.t > Now() + LG.AHEAD then return Count("time") end
	local ok, why = ns.ArenaRating.CheckWord(w)
	if not ok then return Count(why) end
	-- The podium (2, 3) is the clerk's word; a client holding the whole ledger (the clerk's last
	-- digest heard matches its own: LG.Synced) checks it against its own table, the others take
	-- the public arbiter's word.
	if (w.kind == "2" or w.kind == "3") and LG.Synced(mode) and not ns.ArenaRoles.IsKing(sender) then
		local b = LG.Built(mode)
		if b and b.log and b.log[1] then
			local own = ns.ArenaRating.Podium(b, LG.BeltState(mode), w.cat, { now = Now() })
			local mine = own and own[tonumber(w.kind)] or ""
			if (mine or "") ~= (w.gk or "") then return Count("podium") end
		end
	end
	local words = CoreT(mode, "beltWords", true)
	local had = words[w.id]
	if had and EncodeWord(had) == EncodeWord(w) then return false, "again" end
	if had then return Count("conflict") end
	w.by = ns.FullName(sender):lower()
	w.king = R.IsKing(sender) or nil
	-- A podium word replaces the older one of its category and place (Prunable's rule).
	words[w.id] = w
	local n = 0
	for _ in pairs(words) do n = n + 1 end
	if n > LG.WORDS_MAX then
		local drop = ns.ArenaRating.Prunable((function() local l = {} for _, x in pairs(words) do l[#l + 1] = x end return l end)(), Now())
		for id in pairs(drop) do if n > LG.WORDS_MAX then words[id] = nil n = n - 1 end end
	end
	if w.kind ~= "2" and w.kind ~= "3" then
		local C = ns.Chronicle
		if C and not C.missing and C.Add then C.Add("arena", sender, L.ARENA_CHRONICLE_WORD:format(w.kind, w.cat or "-")) end
	end
	Bump()
	return true
end

local function OnWord(dist, sender, mode, body)
	local id, cat, kind, gk, t, reason, ref = Arena.Fields(body, 7)
	if not ref then return Count("shape") end
	if not id:find("^V[0-9a-z]+$") or #id > 24 then return Count("id") end
	local w = { id = id, cat = cat ~= "-" and cat or nil, kind = kind, gk = gk ~= "-" and Gk(gk) or (kind == "2" or kind == "3") and "" or nil,
		t = N(t, 0, 4294967295) or 0, reason = reason ~= "-" and reason:sub(1, 16) or nil, ref = ref ~= "-" and ref or nil }
	LG.TakeWord(sender, mode, w)
end
ns.Comm.Handle("AV", ns.Arena.Handle("AV", OnWord))

-- A public arbiter's word: S strip, V vacate, C contender, U undo (ref), 2 and 3 the podium.
local ownWords = {} -- [id] = { t (first sent), sent }
function LG.Word(kind, cat, gk, reason, ref)
	local mode = "L"
	local w = { id = WordId(), cat = cat, kind = kind, gk = gk or ((kind == "2" or kind == "3") and "" or nil), t = Now(), reason = reason, ref = ref }
	local ok, why = LG.TakeWord(ns.me, mode, w)
	if not ok then return nil, why end
	ownWords[w.id] = { at = Now(), sent = Now() }
	Arena.Send("AV", mode, EncodeWord(w), { key = "av " .. w.id })
	return w.id
end

---------------------------------------------------------------------------
-- The clerk (AB, AQ): digests, the carousel, the podium and the level race's places
---------------------------------------------------------------------------

local clerks = {}    -- [name lower] = last heard (a public arbiter's AB)
local candidateSince -- when this client could first clerk
local clerking = false

-- Whether this client may clerk: a public arbiter or a High Councillor, never the King's character,
-- with the companion loaded (the ledger), on a release (a test build sends nothing on the channel).
function LG.MayClerk()
	local R = ns.ArenaRoles
	if R.IsKing(ns.me) or Arena.TestBuild() then return false end
	if not (R.IsPublicArbiter(ns.me, "L") or ns.IsHighCouncillor(ns.me)) then return false end
	return Arena.Heavy("L") ~= nil
end

-- The clerk: the first by sorted name among the candidates heard in the last CLERK_HEARD, this
-- client included when it may. Returns the name, or nil.
function LG.Clerk()
	local now = Now()
	local list = {}
	for name, t in pairs(clerks) do if now - t <= LG.CLERK_HEARD then list[#list + 1] = name end end
	if LG.MayClerk() and candidateSince and now - candidateSince >= LG.CLERK_WAIT then list[#list + 1] = ns.me:lower() end
	table.sort(list)
	return list[1]
end
function LG.IsClerk() return LG.MayClerk() and LG.Clerk() == ns.me:lower() end

-- The digest: this season's count and hash, and each week's (8 at most).
local function Hash(list)
	local parts = {}
	for _, e in ipairs(list) do parts[#parts + 1] = e.fid .. e.w end
	table.sort(parts)
	local S = ns.Sign
	local h = S and S.SHA256 and S.SHA256(table.concat(parts, ","))
	if not h then return "0" end
	return (h:sub(1, 4):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end
local digests = {} -- [mode] = { gen, d }
function LG.Digest(mode)
	mode = mode or "L"
	local cached = digests[mode]
	if cached and cached.gen == gen and Arena.Heavy(mode) then return cached.d end
	local d = LG.MakeDigest(mode)
	digests[mode] = { gen = gen, d = d }
	return d
end
function LG.MakeDigest(mode)
	local s = LG.Season(mode)
	local list = LG.Entries(s.n, mode)
	local weeks = {}
	for _, e in ipairs(list) do
		local w = math.max(0, math.floor((e.t - (s.start or 0)) / LG.WEEK))
		weeks[w] = weeks[w] or {}
		table.insert(weeks[w], e)
	end
	local ws = {}
	for w in pairs(weeks) do ws[#ws + 1] = w end
	table.sort(ws)
	local parts = {}
	for i = math.max(1, #ws - 7), #ws do
		local w = ws[i]
		parts[#parts + 1] = B36(w) .. ":" .. B36(#weeks[w]) .. ":" .. Hash(weeks[w])
	end
	return { season = s.n, n = #list, hash = Hash(list), weeks = parts, byWeek = weeks }
end

-- (behind: declared with the stores, above)
local function OnDigest(sender, mode, season, n, hash, weeks)
	local d = LG.Digest(mode)
	if tonumber(season) ~= d.season then return end
	behind = {}
	digestHeard = { season = d.season, hash = hash }
	if hash == d.hash then return end
	for part in (weeks or ""):gmatch("[^,]+") do
		local w, cnt, h = part:match("^([0-9a-z]+):([0-9a-z]+):(%x+)$")
		local week = N(w, 0, 99)
		if week then
			local mine = d.byWeek[week] or {}
			if #mine ~= N(cnt, 0, 99999) or Hash(mine) ~= h then behind[week] = true end
		end
	end
end
function LG.Behind() return behind end
-- Whether this client holds the whole ledger: the clerk's last digest heard names this season and
-- matches this client's own entries now. Before any digest, never (a part of the ledger held here
-- must not refuse the clerk's podium words).
function LG.Synced(mode)
	if not digestHeard or not Arena.Heavy(mode or "L") then return false end
	local d = LG.Digest(mode or "L")
	return digestHeard.season == d.season and digestHeard.hash == d.hash and next(behind) == nil
end

-- The carousel (the design): the current and the previous week's entries, a piece at a time on the
-- low lane, so each piece serves every listener with the companion loaded.
local turn -- { pieces, i }
local function Pieces(mode)
	local d = LG.Digest(mode)
	local ws = {}
	for w in pairs(d.byWeek) do ws[#ws + 1] = w end
	table.sort(ws)
	local out = {}
	for i = math.max(1, #ws - 1), #ws do
		local w = ws[i]
		local cur, chunks = {}, {}
		for _, e in ipairs(d.byWeek[w]) do
			local text = Encode(e):gsub("^[^~]*~", "", 1) -- (the season is the piece's)
			local size = #table.concat(cur, ";") + #text + 1
			if #cur > 0 and size > LG.PIECE - 20 then chunks[#chunks + 1] = cur cur = {} end
			cur[#cur + 1] = text
		end
		if #cur > 0 then chunks[#chunks + 1] = cur end
		for j, chunk in ipairs(chunks) do
			out[#out + 1] = table.concat({ "P", B36(d.season), B36(w), B36(j), B36(#chunks), table.concat(chunk, ";") }, "~")
		end
	end
	return out
end
local nextTurn = 0
local function Producer()
	if not LG.IsClerk() then turn = nil return nil end
	if not turn then
		if Now() < nextTurn then return nil end
		turn = { pieces = Pieces("L"), i = 0 }
	end
	turn.i = turn.i + 1
	local body = turn.pieces[turn.i]
	if not body then
		turn, nextTurn = nil, Now() + LG.CAROUSEL_GAP
		return nil
	end
	stats.pieces = stats.pieces + 1
	return "AB", "L", body, { low = true }
end
LG.Producer = Producer

local lastDigest, lastPodium, lastLevels = -math.huge, -math.huge, -math.huge
function LG.ClerkTick()
	local now = Now()
	if LG.MayClerk() then candidateSince = candidateSince or now else candidateSince = nil end
	local was = clerking
	clerking = LG.IsClerk()
	Arena.Involve("clerk", (clerking or candidateSince ~= nil) or nil)
	if not clerking then
		if was then Arena.Later("clerk", nil) end
		return
	end
	-- The carousel: a turn, CAROUSEL_GAP's pause, the next (the low lane drops a producer that has
	-- nothing, so it is given again once the pause is over).
	if not was or (not turn and now >= nextTurn) then Arena.Later("clerk", Producer) end
	if now - lastDigest >= LG.DIGEST_EVERY + (math.random(-LG.DIGEST_JITTER, LG.DIGEST_JITTER)) then
		lastDigest = now
		local d = LG.Digest("L")
		Arena.Send("AB", "L", table.concat({ "D", B36(d.season), B36(d.n), d.hash, #d.weeks > 0 and table.concat(d.weeks, ",") or "-" }, "~"), { key = "ab d" })
	end
	if now - lastPodium >= LG.PODIUM_REPEAT then
		lastPodium = now
		LG.PodiumTick(true)
	end
	if now - lastLevels >= 3600 then
		lastLevels = now
		local H = ns.HonorsNet
		if H and H.SendRecords then H.SendRecords() end
	end
end

-- The ledger changed: a clerk looks at the podium again (AV 2 and 3 on change).
function LG.ClerkChanged()
	if clerking then Arena.After(2, "ledger podium", function() LG.PodiumTick(false) end) end
end

-- The clerk's podium words: each belt category's silver and bronze from the table (ArenaRating.Podium),
-- sent when they change (and all of them every hour).
local sentPodium = {} -- [cat .. place] = gk sent
function LG.PodiumTick(all)
	if not LG.IsClerk() then return end
	local b = LG.Built("L")
	if not b then return end
	local belts = LG.BeltState("L")
	local cats = ns.ArenaRating.Categories(b)
	local exclude = function(gk)
		local blocked = F().Hook("Debts", "Blocked")
		local name = LG.NameOf(gk)
		if blocked and name then local ok, yes = pcall(blocked, name, gk) if ok and yes then return true end end
		local M = ns.Moderation
		return name ~= nil and type(M) == "table" and not M.missing and M.Hides and M.Hides(name) ~= nil
	end
	for _, cat in ipairs(cats) do
		local p = ns.ArenaRating.Podium(b, belts, cat, { now = Now(), exclude = exclude })
		for place = 2, 3 do
			local gk = p and p[place] or ""
			local k = cat .. place
			if all or sentPodium[k] ~= gk then
				local had = sentPodium[k]
				sentPodium[k] = gk
				if all or had ~= nil or gk ~= "" then LG.Word(tostring(place), cat, gk) end
			end
		end
	end
end

local function OnBook(dist, sender, mode, body)
	local kind, rest = Arena.Fields(body, 2)
	if not rest then return Count("shape") end
	local R = ns.ArenaRoles
	if not R.IsPublicArbiter(sender, mode) and not ns.IsHighCouncillor(ns.FullName(sender)) then return Count("sender") end
	if R.IsKing(sender) then return Count("king") end
	clerks[ns.FullName(sender):lower()] = Now()
	if kind == "D" then
		local season, n, hash, weeks = Arena.Fields(rest, 4)
		if not weeks then return Count("shape") end
		OnDigest(sender, mode, N(season, 1, 999), N(n, 0, 99999), hash, weeks ~= "-" and weeks or "")
	elseif kind == "P" then
		if not Arena.Heavy(mode) then return Count("light") end
		local season, week, i, of, entries = Arena.Fields(rest, 5)
		if not entries then return Count("shape") end
		season = N(season, 1, 999)
		for text in (entries .. ";"):gmatch("([^;]*);") do
			if text ~= "" then
				local e, why = Decode(B36(season or 0) .. "~" .. text, sender)
				if e then Keep(e, mode, "clerk") else Count(why) end
			end
		end
	elseif kind == "H" then
		local H = ns.HonorsNet
		if H and H.TakeRecords then H.TakeRecords(sender, mode, rest) end
	end
end
ns.Comm.Handle("AB", ns.Arena.Handle("AB", OnBook))

-- AQ: single asks, by whisper. F~fid (a fight: its AF, and its AE when final), G~fid (the weigh-in),
-- P~gk (a profile), T~tid (a tournament), H (the level race's places).
local answered = {} -- times of the answers this minute
local lastAsk = {}  -- [kind .. target] = time
function LG.Ask(kind, target, arg)
	local key = kind .. ":" .. tostring(target) .. ":" .. tostring(arg)
	local gap = kind == "F" and LG.ASK_F_GAP or (kind == "P" and 30 or LG.ASK_GAP)
	if lastAsk[key] and Now() - lastAsk[key] < gap then return false, "rate" end
	lastAsk[key] = Now()
	if kind == "F" and arg then asked[arg] = Now() end
	return Arena.Send("AQ", "L", kind .. (arg and ("~" .. arg) or ""), { to = target })
end
local function OnAsk(dist, sender, mode, body)
	if dist ~= "WHISPER" then return Count("lane") end
	local now = Now()
	local kept = {}
	for _, t in ipairs(answered) do if now - t < 60 then kept[#kept + 1] = t end end
	answered = kept
	if #answered >= LG.ANSWERS_MAX then return Count("busy") end
	local kind, arg = Arena.Fields(body, 2)
	kind = kind or body
	local done = false
	if kind == "F" or kind == "G" then
		local f = F().Find("fights", arg)
		-- A private or direct fight (no p): only to its fighters, its arbiter and its promoter.
		local may = f and (Has(f.fl, "p") or Same(sender, f.A and f.A.name) or Same(sender, f.B and f.B.name) or Same(sender, f.arb)
			or Same(sender, F().Promoter(f)))
		if f and (Me(f.writer) or Me(f.arb)) and not may then Count("private") end
		if f and may and (Me(f.writer) or Me(f.arb)) then
			if kind == "F" then
				Arena.Send("AF", f.mode, F().Encode(f), { to = sender })
				local book = Book(f.mode, LG.Season(f.mode).n)
				local e = book and book.list[f.fid]
				local text = f.entry or (e and Encode(e))
				if text then Arena.Send("AE", f.mode, text, { to = sender }) end
			end
			done = true
		end
	elseif kind == "P" then
		local P = ns.ArenaProfile
		if P and P.Answer then done = P.Answer(sender, arg) end
	elseif kind == "T" then
		local T = ns.ArenaTourney
		if T and T.Answer then done = T.Answer(sender, arg) end
	elseif kind == "H" then
		local H = ns.HonorsNet
		if H and H.Answer then done = H.Answer(sender) end
	end
	if done then answered[#answered + 1] = now end
end
ns.Comm.Handle("AQ", ns.Arena.Handle("AQ", OnAsk))

---------------------------------------------------------------------------
-- The Hall (the design)
---------------------------------------------------------------------------

-- At a season's end, from this client's own ledger: the belt holders, the top 10 per category, the
-- tournament champions and the awards.
function LG.CloseSeason(n, mode)
	mode = mode or "L"
	local h = Arena.Heavy(mode)
	if not h then return nil end
	local b = LG.Built(mode, n)
	if not b then return nil end
	h.hall = type(h.hall) == "table" and h.hall or {}
	local entry = { n = n, belts = {}, top = {}, tourneys = {}, awards = {} }
	for _, x in ipairs(LG.Holders(mode)) do entry.belts[x.cat] = { gk = x.gk, name = x.name } end
	for _, cat in ipairs(ns.ArenaRating.Categories(b)) do
		local rows = {}
		-- (Every rated fighter of the season: the Hall keeps its best ten, however few fights they had.)
		for i, r in ipairs(ns.ArenaRating.Ranking(b, cat, 1)) do
			if i > 10 then break end
			rows[i] = { gk = r.key, rating = r.rating, fights = r.fights, name = LG.NameOf(r.key, mode) }
		end
		entry.top[cat] = rows
	end
	local T = ns.ArenaTourney
	for _, t in ipairs(T and T.All and T.All() or {}) do
		if t.st == "F" and t.mode == mode then
			local w = T.Winner(t.tid)
			if w then entry.tourneys[#entry.tourneys + 1] = { tid = t.tid, title = t.title, winner = w } end
		end
	end
	for _, c in ipairs(F().All("cards")) do
		if c.st == "D" and c.mode == mode then
			for award, fid in pairs(c.awards or {}) do
				local f = F().Find("fights", fid)
				local wgk = f and f.w and f[f.w].gk
				if wgk then
					entry.awards[wgk] = entry.awards[wgk] or {}
					entry.awards[wgk][award] = (entry.awards[wgk][award] or 0) + 1
				end
			end
		end
	end
	h.hall[n] = entry
	local seasons = {}
	for k in pairs(h.hall) do if type(k) == "number" then seasons[#seasons + 1] = k end end
	table.sort(seasons)
	for i = 1, #seasons - LG.HALL_MAX do h.hall[seasons[i]] = nil end
	return entry
end
function LG.Hall(n, mode)
	local h = Arena.Heavy(mode or "L")
	local hall = h and type(h.hall) == "table" and h.hall or {}
	if n then return hall[n] end
	return hall
end

---------------------------------------------------------------------------
-- The rankings, the history (the view models of the Arena window's one switchable view)
---------------------------------------------------------------------------

-- The start of a period at `now` on the server's clock: today (the UTC day of GetServerTime, the
-- same boundary the daily cap counts in, LG.Counted, so every client agrees; not the realm's daily
-- reset), this week (the weekly reset, Honors.WeekOf), this month (the calendar month,
-- Honors.MonthOf), all time (the season's ratings).
function LG.PeriodStart(period, now)
	now = now or Now()
	local H = ns.Honors
	if period == "today" then return math.floor(now / LG.DAY) * LG.DAY end
	if period == "week" then
		local anchor = H and H.RESET_US or 486000
		local D = ns.Dues
		if type(D) == "table" and not D.missing and type(D.Anchor) == "function" then
			local ok, a = pcall(D.Anchor)
			if ok and tonumber(a) then anchor = tonumber(a) end
		end
		local w = H.WeekOf(now, anchor)
		return w * LG.WEEK + anchor
	end
	if period == "month" then
		local m = H.MonthOf(now)
		local y, mo = H.MonthDate(m)
		-- Day 1 of that month (days from 1970, Howard Hinnant's days_from_civil).
		local yy = mo <= 2 and y - 1 or y
		local era = math.floor(yy / 400)
		local yoe = yy - era * 400
		local mp = (mo + 9) % 12
		local doy = math.floor((153 * mp + 2) / 5)
		local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
		return (era * 146097 + doe - 719468) * LG.DAY
	end
	return 0
end

-- The categories to switch between: global, then each class and each race someone was rated in.
function LG.Categories(mode)
	local out = { { cat = "A", kind = "global", label = L.ARENA_CAT_GLOBAL } }
	local b = LG.Built(mode)
	if not b then return out end
	local R = ns.ArenaRating
	for _, cat in ipairs(R.Categories(b)) do
		if cat ~= "A" then out[#out + 1] = { cat = cat, kind = cat:sub(1, 1) == "C" and "class" or "race", label = LG.CatLabel(cat) } end
	end
	return out
end
local RACES = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Scourge", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }
local CLASS_FILE = { WA = "WARRIOR", PA = "PALADIN", HU = "HUNTER", RO = "ROGUE", PR = "PRIEST", SH = "SHAMAN", MA = "MAGE", WL = "WARLOCK", DR = "DRUID" }
function LG.CatLabel(cat)
	if cat == "A" then return L.ARENA_CAT_GLOBAL end
	local class = tostring(cat):match("^C(%u%u)$")
	if class then
		local file = CLASS_FILE[class]
		local names = LOCALIZED_CLASS_NAMES_MALE
		return (file and type(names) == "table" and names[file]) or (L.ARENA_CLASS_NAMES and L.ARENA_CLASS_NAMES[class]) or class
	end
	local race = tonumber(tostring(cat):match("^R(%d+)$"))
	if race then
		local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
		if type(info) == "function" then
			local ok, r = pcall(info, race)
			if ok and type(r) == "table" and type(r.raceName) == "string" then return r.raceName end
		end
		return (L.ARENA_RACE_NAMES and L.ARENA_RACE_NAMES[race]) or RACES[race] or tostring(race)
	end
	return tostring(cat)
end

-- A ranking: for "all", the season's Elo table of the category; for a period, the fighters who
-- fought in it, by the rating they gained there (ArenaRating's own changes), then wins, then fewer
-- losses, then the rating. Each row: { rank, gk, name, rating, delta, wins, losses, fights, tier,
-- streak }. opts: { mode, now }
function LG.Ranking(period, cat, opts)
	opts = opts or {}
	local mode = opts.mode or "L"
	cat = cat or "A"
	local b = LG.Built(mode)
	local rows = {}
	if not b then return rows end
	local R = ns.ArenaRating
	local tiers = LG.Tiers(mode)
	if period == "all" or period == nil then
		for _, r in ipairs(R.Ranking(b, cat, 1)) do
			local rec = R.Record(b, r.key)
			rows[#rows + 1] = { rank = r.rank, gk = r.key, name = LG.NameOf(r.key, mode), rating = r.rating, delta = rec.rating - R.START,
				wins = rec.wins, losses = rec.losses + rec.fled, fights = rec.fights, tier = tiers[r.key], streak = rec.streak }
		end
		return rows
	end
	local from = LG.PeriodStart(period, opts.now)
	local by = {}
	for _, x in ipairs(b.log or {}) do
		if (x.t or 0) >= from then
			for _, side in ipairs({ "a", "b" }) do
				local gk = x[side]
				if gk and R.InCategory(b, gk, cat) then
					local r = by[gk] or { gk = gk, delta = 0, wins = 0, losses = 0, fights = 0 }
					by[gk] = r
					local d = side == "a" and x.aDelta or x.bDelta
					r.delta = r.delta + (tonumber(d) or 0)
					r.fights = r.fights + 1
					if x.winner == gk then r.wins = r.wins + 1 else r.losses = r.losses + 1 end
				end
			end
		end
	end
	for gk, r in pairs(by) do
		local rating = R.Rating(b, gk)
		r.rating, r.name, r.tier = rating, LG.NameOf(gk, mode), tiers[gk]
		rows[#rows + 1] = r
	end
	table.sort(rows, function(x, y)
		if x.delta ~= y.delta then return x.delta > y.delta end
		if x.wins ~= y.wins then return x.wins > y.wins end
		if x.losses ~= y.losses then return x.losses < y.losses end
		if x.rating ~= y.rating then return x.rating > y.rating end
		return x.gk < y.gk
	end)
	for i, r in ipairs(rows) do r.rank = i end
	return rows
end

-- The one compact view (the owner's ask): the period and category switches with the chosen ones
-- marked, and one page of rows. period: "today"|"week"|"month"|"all" (default "all"); cat: a
-- category (default "A"); page: 1-based (LG.PAGE rows). Returns { period, cat, label, periods =
-- { { key, label, selected } }, categories = { { cat, kind, label, selected } }, rows, page, pages,
-- total, mine (this character's row, wherever it is), loaded (false while the companion is not) }.
function LG.RankingView(period, cat, page, opts)
	opts = opts or {}
	period = (period == "today" or period == "week" or period == "month") and period or "all"
	cat = cat or "A"
	local view = { period = period, cat = cat, label = LG.CatLabel(cat), periods = {}, categories = {}, rows = {}, loaded = Arena.Heavy(opts.mode or "L") ~= nil }
	for _, p in ipairs(LG.PERIODS) do
		view.periods[#view.periods + 1] = { key = p, label = L["ARENA_PERIOD_" .. p:upper()], selected = p == period }
	end
	for _, c in ipairs(LG.Categories(opts.mode)) do
		c.selected = c.cat == cat
		view.categories[#view.categories + 1] = c
	end
	local rows = LG.Ranking(period, cat, opts)
	view.total = #rows
	view.pages = math.max(1, math.ceil(#rows / LG.PAGE))
	view.page = math.max(1, math.min(tonumber(page) or 1, view.pages))
	for i = (view.page - 1) * LG.PAGE + 1, math.min(#rows, view.page * LG.PAGE) do view.rows[#view.rows + 1] = rows[i] end
	local me = F().MyGk()
	for _, r in ipairs(rows) do if me and r.gk == me then view.mine = r end end
	return view
end

-- Whether a fight shows on a fighter's profile (the design): public events always; a private one only
-- when he shows his list (and on the opponent's as "a private fighter" unless both do).
function LG.ShowsFight(gk, e, public)
	if Has(e.fl, "p") or Has(e.fl, "c") or Has(e.fl, "k") then return true end
	return public(gk) == true
end

-- The fight history: one fighter's (opts.gk: newest first, as his history switch allows) or the
-- recent ones overall (public events only). The rated fights come from the ledger; the others
-- from the fights this client holds (a public fight unrated: a walkover, a catchweight, a
-- disqualification for the wrong character) and, for this character's own history, from its own
-- list (ArenaFights.MyFights: direct and private fights too, the design). Each row: { fid, t, A, B,
-- gkA, gkB, winner (the name), w, method, dur, cat, title, rated, public, direct, sc, delta (for
-- opts.gk: his change), opponent, won, private (the opponent hidden) }. opts: { gk, mode, limit
-- (default 20), season, own (default: opts.gk is this character's: nothing hidden from himself) }
function LG.History(opts)
	opts = opts or {}
	local mode = opts.mode or "L"
	local P = ns.ArenaProfile
	local function Public(gk) return P and P.IsPublic and P.IsPublic(gk) or false end
	local myGk = F().MyGk()
	local own = opts.own
	if own == nil then own = opts.gk ~= nil and opts.gk == myGk end
	local b = LG.Built(mode)
	local deltas = {}
	for _, x in ipairs(b and b.log or {}) do deltas[x.id] = x end
	local rows, seen = {}, {}
	local function Side(gkA, gkB) if opts.gk == gkA then return "A" elseif opts.gk == gkB then return "B" end end
	local function Add(row, side, publicEvent)
		if seen[row.fid] then return end
		seen[row.fid] = true
		if opts.gk then
			local other = side == "A" and "B" or "A"
			row.opponent, row.won = row[other], row.w == side
			local x = deltas[row.fid]
			if x then row.delta = side == "A" and x.aDelta or x.bDelta end
			if not own and not publicEvent and not (Public(opts.gk) and Public(side == "A" and row.gkB or row.gkA)) then
				row.private, row.opponent = true, nil
			end
		end
		rows[#rows + 1] = row
	end
	-- The ledger's rated fights.
	for _, e in ipairs(LG.Entries(opts.season, mode)) do
		local side = opts.gk and Side(e.gkA, e.gkB)
		local show
		if opts.gk then show = side ~= nil and (own or LG.ShowsFight(opts.gk, e, Public))
		else show = Has(e.fl, "p") end
		if show then
			Add({ fid = e.fid, t = e.t, A = e.A, B = e.B, gkA = e.gkA, gkB = e.gkB, w = e.w, winner = e.w == "A" and e.A or e.B,
				method = e.m, dur = e.dur, cat = e.cat, title = Has(e.fl, "t"), rated = Has(e.fl, "r"), public = Has(e.fl, "p"), sc = e.sc },
				side, Has(e.fl, "p") or Has(e.fl, "c") or Has(e.fl, "k"))
		end
	end
	-- The fights held here, ended with a winner, not (yet) in the ledger: public ones for anyone,
	-- the others only in this character's own history.
	local Fi = F()
	for _, f in ipairs(Fi.All("fights")) do
		local st = Fi.State(f)
		if f.mode == mode and (st == "F" or st == "W") and f.w and f.A and f.B and not seen[f.fid] then
			local public = Has(f.fl, "p")
			local side = opts.gk and Side(f.A.gk, f.B.gk)
			if opts.gk and not side and own then side = Fi.SideOf(f, ns.me) end
			local show
			if opts.gk then show = side ~= nil and (public or own)
			else show = public end
			if show then
				Add({ fid = f.fid, t = f.graceEnd or f.endedAt or f.heardAt or 0, A = f.A.name, B = f.B.name, gkA = f.A.gk, gkB = f.B.gk, w = f.w,
					winner = f[f.w].name, method = f.m, dur = f.dur, cat = f.cat, title = Has(f.fl, "t"), rated = Has(f.fl, "r"), public = public,
					direct = Has(f.fl, "d"), sc = (f.sc and f.sc[1] or 0) .. ":" .. (f.sc and f.sc[2] or 0) }, side, public)
			end
		end
	end
	-- This character's own list: what it fought once the records themselves are gone.
	if own then
		for _, e in ipairs(Fi.MyFights and Fi.MyFights(mode) or {}) do
			if not seen[e.fid] and (e.w == "W" or e.w == "L") then
				local side = e.side == "B" and "B" or "A"
				local other = side == "A" and "B" or "A"
				local row = { fid = e.fid, t = e.t or 0, w = e.w == "W" and side or other, method = e.m, dur = e.dur, cat = e.cat, title = e.title,
					rated = e.rated, public = e.public, direct = e.direct, sc = e.sc }
				row[side], row[other] = ns.me, e.opp
				row["gk" .. side], row["gk" .. other] = myGk, e.oppGk
				row.winner = row[row.w]
				Add(row, side, e.public)
			end
		end
	end
	table.sort(rows, function(x, y) if (x.t or 0) ~= (y.t or 0) then return (x.t or 0) > (y.t or 0) end return x.fid > y.fid end)
	local limit = tonumber(opts.limit) or 20
	for i = #rows, limit + 1, -1 do rows[i] = nil end
	return rows
end

---------------------------------------------------------------------------
-- The games' ledger (AY; 1.1.6, the owner's ask of 2026-10-05: "a ledger of every game, for me,
-- the council and the King to see, besides each player seeing his own")
---------------------------------------------------------------------------
-- Every game a player plays, whatever its kind (LG.GAMES): Bones against a player (b),
-- against the House (h), against the House with the rules' hints (p, the learning mode), a duel
-- (d), a Fight Night's bout (n), a tournament's bout (t), a Lottery practice draw (o). No bet plays
-- a part: a record says when, who, the kind, how long, the result and the score (and a Bones
-- table's stake, 0 while the compliance gate allows none).
-- Who sees what: each player his own games (LG.MyGames: his own list in the core's store, whether
-- or not anyone is told); the auditors everyone's (LG.AllGames): ArenaRoles.Auditor in L, the
-- real roles only whatever the game's mode (never a rehearsal's stand-in): the King's character,
-- a High Councillor, a signed arbiter with "+a", which is how the author's own character is one.
-- Nobody else: a record goes only by whisper to an auditor, a client that is no auditor refuses
-- it, and nothing of it is said on the channel.
-- How it travels (this ledger's clerk, by whisper and between auditors only: the results' carousel
-- goes on the channel, which every member hears, so it is not used here): each participant (both
-- players, the arbiter) whispers the record at the game's end to every auditor heard lately
-- (Debts.Auditors: their hello, ZQ~H), and to an auditor heard later at his hello
-- (LG.GamesHello, from Wallet.lua): the games of the last GAMES_RESEND_DAYS days not told to him
-- yet. And the games' clerk (as the results' clerk: the first by sorted name of the auditors heard
-- lately, this one included, never the King's character, never the auditor saying hello) passes on
-- to an auditor, at his hello, the words it holds that he was not given (the relay names whose
-- word it is), so the King gets a game a councillor was told even when none of its players is
-- online with him. GAMES_RESEND_MAX whispers a hello, on the low lane.
-- An auditor keeps each participant's word (the result, the scores, how it ended, the detail), so
-- the screens say whether the words agree, differ, or only one came.
-- Body (AY): id~g~t~dur~p1~p2|-~arb|-~w~s1~s2~how~x~by|-   (numbers in base 36)
--   id: the game's own (a fight's fid, a table's id, G... for a game played alone); t its end
--   (server time), dur its seconds; w the seat that won, 1 or 2 (against the House, the House is 2;
--   a Lottery ticket that hit is 1, one that missed 2), or v (void); s1, s2 by seat (a fight's
--   rounds, Bones's points; the Lottery: the places hit, the beast picked); how one letter
--   (Bones t c o f v, a fight K R D W N V, the Lottery d); x the detail (Bones between
--   players kind.stake.target.steps.hash, against the House the target, a fight cat.bo[.tid], the
--   Lottery the five numbers); by: whose word a relaying auditor passes on ("-": the sender's own).
-- Refused: anything but a whisper; a client that is no auditor; a sender (or the word's author)
-- moderation hides; a word whose author the record does not seat (a player, or the arbiter it
-- names); a relay from anyone but an auditor; a field out of shape; a time ahead of the clock or
-- past GAMES_DAYS; an id held with other players; one who opened GAMES_FIRST_MAX games between
-- players of the ledger in a day, or GAMES_SOLO_DAY games played alone (the House, the lesson, the
-- Lottery's practice: a free draw takes a click). Kept: GAMES_MAX games between players a mode and
-- GAMES_SOLO_MAX played alone, each for GAMES_DAYS, the oldest out first, so practice never pushes
-- a game between players out; each player's own list GAMES_MINE_MAX and GAMES_MINE_SOLO_MAX a
-- mode. A player tells the auditors GAMES_SOLO_DAY games played alone a day (the rest stay in his
-- own list, never told: no whisper an auditor would refuse). Per realm group, as every arena store
-- (GamesT: T's in a store of its own, which no rehearsal empties).

LG.GAMES = { "b", "h", "p", "d", "n", "t", "o" } -- (the screens' order)
LG.GAME_OF = { b = "bones", h = "bones", p = "bones", d = "arena", n = "arena", t = "arena", o = "lottery" }
LG.GAME_GROUPS = { "bones", "arena", "lottery" }
local SOLO = { h = true, p = true, o = true } -- played alone: no second player, no arbiter
LG.GAMES_MAX = 2000          -- games between players an auditor's ledger keeps of a mode (the newest)...
LG.GAMES_SOLO_MAX = 1000     -- ...and games played alone, apart...
LG.GAMES_DAYS = 90           -- ...for this long at most
LG.GAMES_FIRST_MAX = 100     -- games between players one player may be the first to report in it, in a day
LG.GAMES_SOLO_DAY = 20       -- games played alone one player tells (and an auditor takes from him) in a day
LG.GAMES_RESEND_DAYS = 30    -- an auditor heard later is told this far back...
LG.GAMES_RESEND_MAX = 25     -- ...this many whispers at each of his hellos
LG.GAMES_MINE_MAX = 200      -- a player's own list, a mode: games between players...
LG.GAMES_MINE_SOLO_MAX = 100 -- ...and games played alone, apart
LG.GAMES_AHEAD = 60
LG.GAMES_PAGE = 20           -- rows a page of the screens
LG.GAMES_PLAYERS = 30        -- names the player filter offers

local gstats = { taken = 0, told = 0, refused = {} }
function LG.GamesStats() return gstats end
-- The screens read the lists many times a refresh: kept until a game is taken or played.
local gamesGen, gamesCache = 0, {}
local function GamesChanged()
	gamesGen = gamesGen + 1
	Arena.Changed()
end
local function GRefused(why)
	gstats.refused[why] = (gstats.refused[why] or 0) + 1
	return false, why
end

local function Full(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(ns.Normal and ns.Normal(name) or name)
end
local function Low(name)
	local f = Full(name)
	return f and f:lower() or nil
end

-- The games' ledger's auditors: the real roles (ArenaRoles.Auditor in L), whatever the game's mode,
-- so a rehearsal's stand-in King never gets a real player's game.
function LG.GamesAuditor(name)
	local R = ns.ArenaRoles
	return type(name) == "string" and type(R) == "table" and type(R.Auditor) == "function" and R.Auditor(name, "L") == true
end
local IsAud = LG.GamesAuditor

local function GHides(name)
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" and M.Hides(name) then return true end
	local blocked = ns.db and ns.db.blocked
	return type(blocked) == "table" and blocked[Low(name) or ""] ~= nil
end

local function GameId(id) return type(id) == "string" and #id <= 20 and id:find("^[FKG][0-9a-z]+$") ~= nil end
local function Num36(n)
	n = math.floor(tonumber(n) or 0)
	return B36(n > 0 and n or 0)
end
local function Detail(x) return type(x) == "string" and x ~= "" and #x <= 60 and x:find("^[%w%.%-]+$") ~= nil end

-- What a participant says of a game: the body without its last field (by), or nil.
local function GameBody(r)
	if type(r) ~= "table" or not GameId(r.id) or not LG.GAME_OF[r.g] then return nil end
	local Wire = F().Wire
	local p1 = Full(r.p1)
	local p2 = not SOLO[r.g] and Full(r.p2) or nil
	if not p1 or (not SOLO[r.g] and not p2) then return nil end
	local arb = not SOLO[r.g] and Full(r.arb) or nil
	local w = (r.w == "1" or r.w == "2") and r.w or "v"
	local how = type(r.how) == "string" and r.how:find("^%a$") and r.how or "v"
	return table.concat({ r.id, r.g, Num36(r.t or Now()), Num36(math.min(LG.DAY, tonumber(r.dur) or 0)), Wire(p1), p2 and Wire(p2) or "-",
		arb and Wire(arb) or "-", w, Num36(r.s1), Num36(r.s2), how, Detail(r.x) and r.x or "-" }, "~")
end

-- A body (all 13 fields) as a record, or nil and why.
local function DecodeGame(body, sender)
	local f = {}
	for part in (tostring(body) .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	if #f ~= 13 then return nil, "shape" end
	local Unwire = F().Unwire
	local g = f[2]
	if not GameId(f[1]) or not LG.GAME_OF[g] then return nil, "shape" end
	local r = { id = f[1], g = g, t = N(f[3], 0, 4294967295), dur = N(f[4], 0, LG.DAY), p1 = Unwire(f[5], sender),
		p2 = f[6] ~= "-" and Unwire(f[6], sender) or nil, arb = f[7] ~= "-" and Unwire(f[7], sender) or nil,
		w = f[8], s1 = N(f[9], 0, 1000000), s2 = N(f[10], 0, 1000000), how = f[11], x = f[12], by = f[13] ~= "-" and Unwire(f[13], sender) or nil }
	if not (r.t and r.dur and r.p1 and r.s1 and r.s2) then return nil, "shape" end
	if (f[6] ~= "-" and not r.p2) or (f[7] ~= "-" and not r.arb) or (f[13] ~= "-" and not r.by) then return nil, "shape" end
	if SOLO[g] then
		if r.p2 or r.arb then return nil, "shape" end
	elseif not r.p2 or Same(r.p1, r.p2) or (r.arb and (Same(r.arb, r.p1) or Same(r.arb, r.p2))) then
		return nil, "shape"
	end
	if (r.w ~= "1" and r.w ~= "2" and r.w ~= "v") or not r.how:find("^%a$") or not Detail(r.x) then return nil, "shape" end
	return r
end

-- The games' ledger's own store of a mode (a read never makes it). L: this realm's live store. T
-- (every game while the King's live switch is off, as in 1.1.6): ns.rdb.arenaGames, never the
-- rehearsal store, which a new rehearsal's word, its end KEEP_DAYS on and `test clear` empty
-- (ArenaTest.lua). The sim's memory store while it runs.
local function GamesT(mode, key, make)
	if mode ~= "T" or Arena.Sim() then return CoreT(mode, key, make) end
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.arenaGames
	if type(s) ~= "table" then
		if not make then return nil end
		s = { v = 1 }
		ns.rdb.arenaGames = s
	end
	if type(s[key]) ~= "table" then
		if not make then return nil end
		s[key] = {}
	end
	return s[key]
end

-- The auditor's book of a mode: { games = { [id] = rec }, n }, made only to keep a game.
local function GamesBook(mode, make)
	local b = GamesT(mode, "gamesLedger", make)
	if type(b) ~= "table" then return nil end
	if type(b.games) ~= "table" then
		if not make then return nil end
		b.games, b.n = {}, 0
	end
	return b
end
-- (games played alone and games between players each kept to their own cap)
local function PruneGames(b)
	local cut = Now() - LG.GAMES_DAYS * LG.DAY
	local lists = { solo = {}, duo = {} }
	for id, rec in pairs(b.games) do
		if type(rec) ~= "table" or (tonumber(rec.t) or 0) < cut then b.games[id] = nil
		else
			local list = SOLO[rec.g] and lists.solo or lists.duo
			list[#list + 1] = { id = id, t = tonumber(rec.t) or 0 }
		end
	end
	b.n = 0
	for class, list in pairs(lists) do
		local max = class == "solo" and LG.GAMES_SOLO_MAX or LG.GAMES_MAX
		table.sort(list, function(x, y) if x.t ~= y.t then return x.t > y.t end return x.id > y.id end)
		for i = max + 1, #list do b.games[list[i].id] = nil end
		b.n = b.n + math.min(#list, max)
	end
end
local function Seats(rec, name)
	return Same(name, rec.p1) or (rec.p2 ~= nil and Same(name, rec.p2)) or (rec.arb ~= nil and Same(name, rec.arb))
end
local function SameName(a, b) return (a == nil and b == nil) or (a ~= nil and b ~= nil and Same(a, b)) end

-- A word on a game (an auditor's copy of an AY): true when kept (or held already), else false and why.
function LG.TakeGame(sender, mode, body)
	if mode ~= "L" and mode ~= "T" then return GRefused("mode") end
	if not IsAud(ns.me) then return GRefused("auditor") end
	local from = Full(sender)
	if not from then return GRefused("sender") end
	if GHides(from) then return GRefused("hidden") end
	local r, why = DecodeGame(body, from)
	if not r then return GRefused(why) end
	if r.t > Now() + LG.GAMES_AHEAD then return GRefused("time") end
	if r.t < Now() - LG.GAMES_DAYS * LG.DAY then return GRefused("old") end
	local author = from
	if r.by then
		-- (an auditor passing on another's word: an auditor alone may)
		if not IsAud(from) then return GRefused("relay") end
		author = r.by
		if GHides(author) then return GRefused("hidden") end
	end
	if not Seats(r, author) then return GRefused("sender") end
	local book = GamesBook(mode, true)
	if not book then return GRefused("store") end
	local who = Low(author)
	local word = table.concat({ r.w, B36(r.s1), B36(r.s2), r.how, r.x }, ":")
	local rec = book.games[r.id]
	if type(rec) == "table" then
		if not (rec.g == r.g and Same(rec.p1, r.p1) and SameName(rec.p2, r.p2) and SameName(rec.arb, r.arb)) then return GRefused("conflict") end
		if type(rec.by) ~= "table" then rec.by = {} end
		if rec.by[who] == word then return true, "again" end
		rec.by[who] = word
	else
		local opened, day, solo = 0, Now() - LG.DAY, SOLO[r.g] == true
		for _, x in pairs(book.games) do
			if type(x) == "table" and x.first == who and (tonumber(x.got) or 0) >= day and (SOLO[x.g] == true) == solo then opened = opened + 1 end
		end
		if opened >= (solo and LG.GAMES_SOLO_DAY or LG.GAMES_FIRST_MAX) then return GRefused("flood") end
		book.games[r.id] = { id = r.id, g = r.g, t = r.t, dur = r.dur, p1 = r.p1, p2 = r.p2, arb = r.arb, got = Now(), first = who, by = { [who] = word } }
		PruneGames(book)
	end
	gstats.taken = gstats.taken + 1
	GamesChanged()
	return true
end
local function OnGame(dist, sender, mode, body)
	if dist ~= "WHISPER" then return GRefused("lane") end
	LG.TakeGame(sender, mode, body)
end
ns.Comm.Handle("AY", ns.Arena.Handle("AY", OnGame))

-- This character's own list of a mode (newest first): { { id, g, t, body, told = { [auditor] } } }.
local function MineList(mode, make)
	local s = GamesT(mode, "gamesMine", make)
	if type(s) ~= "table" then return nil end
	local k = Low(ns.me) or "?"
	if type(s[k]) ~= "table" then
		if not make then return nil end
		s[k] = {}
	end
	return s[k]
end

-- One word to one auditor (mark(auditor) once it went).
local sendingGame = {} -- [id|author|auditor] = true while its whisper waits (a hello meanwhile does not repeat it)
local function TellGame(mode, body, by, name, mark)
	local k = Low(name)
	if not k then return false end
	local key = tostring(body:match("^[^~]*")) .. "|" .. tostring(by or "-") .. "|" .. k
	if sendingGame[key] then return false end
	sendingGame[key] = true
	local ok = Arena.Send("AY", mode, body .. "~" .. (by and F().Wire(by) or "-"), { to = name, low = true, done = function(sent)
		sendingGame[key] = nil
		if sent then
			gstats.told = gstats.told + 1
			if mark then mark(k) end
		end
	end })
	if ok ~= true then sendingGame[key] = nil end
	return ok == true
end

-- The times this character told the auditors a game played alone in the last day, a mode (kept
-- apart from his list, which its caps prune).
local function SoloTold(mode)
	local s = GamesT(mode, "gamesSoloTold", true)
	if type(s) ~= "table" then return nil end
	local k = Low(ns.me) or "?"
	if type(s[k]) ~= "table" then s[k] = {} end
	local list, day = s[k], Now() - LG.DAY
	for i = #list, 1, -1 do if (tonumber(list[i]) or 0) < day then table.remove(list, i) end end
	return list
end

-- A player's own list kept to its caps (games played alone apart) and GAMES_DAYS, newest first.
local function PruneMine(list)
	local cut = Now() - LG.GAMES_DAYS * LG.DAY
	local solo, duo, keep = 0, 0, {}
	for i = 1, #list do
		local x = list[i]
		local ok = type(x) == "table" and (tonumber(x.t) or 0) >= cut
		if ok and SOLO[x.g] then
			solo = solo + 1
			ok = solo <= LG.GAMES_MINE_SOLO_MAX
		elseif ok then
			duo = duo + 1
			ok = duo <= LG.GAMES_MINE_MAX
		end
		keep[i] = ok
	end
	for i = #list, 1, -1 do if not keep[i] then table.remove(list, i) end end
end

-- A game this character played (or judged) ended: r = { id, g, t, dur, p1, p2, arb, w, s1, s2, how,
-- x }. Kept in his own list, his own word kept at once when he is an auditor, every auditor heard
-- lately told; a game played alone past GAMES_SOLO_DAY of them in a day is his own list's only
-- (quiet: never told, nor at a hello). Returns the own entry, or nil and why ("again": an id he
-- holds already).
function LG.Played(mode, r)
	mode = mode == "T" and "T" or "L"
	if type(r) ~= "table" then return nil, "shape" end
	r.t = tonumber(r.t) or Now()
	local body = GameBody(r)
	if not body then return nil, "shape" end
	local list = MineList(mode, true)
	if not list then return nil, "store" end
	for _, e in ipairs(list) do if type(e) == "table" and e.id == r.id then return nil, "again" end end
	local e = { id = r.id, g = r.g, t = r.t, body = body, told = {} }
	if SOLO[r.g] then
		local told = SoloTold(mode)
		if not told or #told >= LG.GAMES_SOLO_DAY then e.quiet = true else told[#told + 1] = Now() end
	end
	table.insert(list, 1, e)
	PruneMine(list)
	if e.quiet then
		GamesChanged()
		return e
	end
	if IsAud(ns.me) then LG.TakeGame(ns.me, mode, body .. "~-") end
	local D = ns.Debts
	local heard = type(D) == "table" and type(D.Auditors) == "function" and D.Auditors("L") or {}
	for _, name in ipairs(heard) do
		if IsAud(name) then TellGame(mode, body, nil, name, function(k) e.told[k] = true end) end
	end
	GamesChanged()
	return e
end

-- A word an auditor holds, as a body again (for the relay).
local function WordParts(word)
	local w, s1, s2, how, x = tostring(word or ""):match("^([12v]):([0-9a-z]+):([0-9a-z]+):(%a):([%w%.%-]+)$")
	if not w then return nil end
	return { w = w, s1 = N(s1, 0) or 0, s2 = N(s2, 0) or 0, how = how, x = x }
end
local function RelayBody(rec, word)
	local p = WordParts(word)
	if not p then return nil end
	return GameBody({ id = rec.id, g = rec.g, t = rec.t, dur = rec.dur, p1 = rec.p1, p2 = rec.p2, arb = rec.arb, w = p.w, s1 = p.s1, s2 = p.s2,
		how = p.how, x = p.x })
end

-- The games' clerk for an auditor's hello: the first by sorted name of the auditors heard lately
-- (Debts.Auditors) and this one, never the King's character nor `except` (the one saying hello);
-- nil when none.
function LG.GamesClerk(except)
	local R = ns.ArenaRoles
	local D = ns.Debts
	local list = {}
	local function Add(name)
		if IsAud(name) and not (except and Same(name, except)) and not (R and R.IsKing and R.IsKing(name)) then list[#list + 1] = Low(name) end
	end
	for _, name in ipairs(type(D) == "table" and type(D.Auditors) == "function" and D.Auditors("L") or {}) do Add(name) end
	Add(ns.me)
	table.sort(list)
	return list[1]
end

-- An auditor's hello (Wallet.lua's ZQ~H): this character's own games of the last GAMES_RESEND_DAYS
-- not told to him yet, newest first; then, on the games' clerk's client, the words it holds that
-- he was not given (never his own). GAMES_RESEND_MAX whispers at most. Returns how many went.
function LG.GamesHello(name)
	name = Full(name)
	if not name or Me(name) or not IsAud(name) then return 0 end
	local k = name:lower()
	local mine = Low(ns.me)
	local cut = Now() - LG.GAMES_RESEND_DAYS * LG.DAY
	local n = 0
	for _, mode in ipairs({ "L", "T" }) do
		for _, e in ipairs(MineList(mode, false) or {}) do
			if n >= LG.GAMES_RESEND_MAX then return n end
			if type(e) == "table" and type(e.body) == "string" and not e.quiet and (tonumber(e.t) or 0) >= cut then
				if type(e.told) ~= "table" then e.told = {} end
				if not e.told[k] and TellGame(mode, e.body, nil, name, function(x) e.told[x] = true end) then n = n + 1 end
			end
		end
	end
	if not IsAud(ns.me) or LG.GamesClerk(name) ~= mine then return n end
	for _, mode in ipairs({ "L", "T" }) do
		local b = GamesBook(mode, false)
		local list = {}
		for _, rec in pairs(b and b.games or {}) do
			if type(rec) == "table" and type(rec.by) == "table" and (tonumber(rec.t) or 0) >= cut then list[#list + 1] = rec end
		end
		table.sort(list, function(x, y) if x.t ~= y.t then return x.t > y.t end return x.id > y.id end)
		for _, rec in ipairs(list) do
			if type(rec.relay) ~= "table" then rec.relay = {} end
			local done = type(rec.relay[k]) == "table" and rec.relay[k] or {}
			local authors = {}
			for who in pairs(rec.by) do authors[#authors + 1] = who end
			table.sort(authors)
			for _, who in ipairs(authors) do
				if who ~= k and who ~= mine and not done[who] then
					if n >= LG.GAMES_RESEND_MAX then return n end
					local body = RelayBody(rec, rec.by[who])
					if body and TellGame(mode, body, who, name, function(x)
						if type(rec.relay[x]) ~= "table" then rec.relay[x] = {} end
						rec.relay[x][who] = true
					end) then n = n + 1 end
				end
			end
		end
	end
	return n
end

-- A record as the screens read it: { id, mode, g, game, t, dur, p1, p2, arb, w, winner, s1, s2,
-- how, x } (winner nil when void, or the House's or a missed ticket's).
local function GameRow(rec, mode, p)
	local row = { id = rec.id, mode = mode, g = rec.g, game = LG.GAME_OF[rec.g], t = tonumber(rec.t) or 0, dur = tonumber(rec.dur) or 0,
		p1 = rec.p1, p2 = rec.p2, arb = rec.arb, w = p.w, s1 = tonumber(p.s1) or 0, s2 = tonumber(p.s2) or 0, how = p.how,
		x = p.x ~= "-" and p.x or nil }
	if p.w == "1" then row.winner = rec.p1 elseif p.w == "2" then row.winner = rec.p2 end
	return row
end
local function Newest(list)
	table.sort(list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		if a.mode ~= b.mode then return a.mode < b.mode end
		if (a.i or 0) ~= (b.i or 0) then return (a.i or 0) < (b.i or 0) end
		return a.id > b.id
	end)
	return list
end

-- This character's own games, both modes, newest first: GameRow's fields, with side (1, 2 or
-- "arb") and result ("W" won, "L" lost, "V" void, "J" judged).
function LG.MyGames()
	local key = "mine:" .. tostring(ns.me) .. (Arena.Sim() and ":sim" or "")
	local c = gamesCache[key]
	if c and c.gen == gamesGen then return c.list end
	local out = {}
	for _, mode in ipairs({ "L", "T" }) do
		for i, e in ipairs(MineList(mode, false) or {}) do
			local r = type(e) == "table" and type(e.body) == "string" and DecodeGame(e.body .. "~-", ns.me) or nil
			if r then
				local row = GameRow(r, mode, r)
				row.i = i
				row.side = Same(r.p1, ns.me) and 1 or ((r.p2 and Same(r.p2, ns.me)) and 2 or ((r.arb and Same(r.arb, ns.me)) and "arb" or nil))
				if row.side == "arb" then row.result = "J"
				elseif r.w == "v" then row.result = "V"
				elseif row.side then row.result = tostring(row.side) == r.w and "W" or "L" end
				out[#out + 1] = row
			end
		end
	end
	gamesCache[key] = { gen = gamesGen, list = Newest(out) }
	return gamesCache[key].list
end

-- Every game the auditors were told, both modes, newest first (on an auditor's client only):
-- GameRow's fields with reports (how many words) and state ("agreed": two or more, the same;
-- "differ"; "one": a single word). The first player's word is shown where it came, else the
-- second's, else the arbiter's.
function LG.AllGames()
	if not IsAud(ns.me) then return {} end
	local c = gamesCache.all
	local sim = Arena.Sim() and true or false
	if c and c.gen == gamesGen and c.me == ns.me and c.sim == sim then return c.list end
	local out = {}
	for _, mode in ipairs({ "L", "T" }) do
		local b = GamesBook(mode, false)
		for _, rec in pairs(b and b.games or {}) do
			if type(rec) == "table" and type(rec.by) == "table" and type(rec.p1) == "string" then
				local n, first, differ = 0, nil, false
				for _, x in pairs(rec.by) do
					n = n + 1
					if first == nil then first = x elseif x ~= first then differ = true end
				end
				local word = rec.by[Low(rec.p1)] or (rec.p2 and rec.by[Low(rec.p2)]) or (rec.arb and rec.by[Low(rec.arb)]) or first
				local p = WordParts(word)
				if p then
					local row = GameRow(rec, mode, p)
					row.reports, row.state = n, differ and "differ" or (n >= 2 and "agreed" or "one")
					out[#out + 1] = row
				end
			end
		end
	end
	gamesCache.all = { gen = gamesGen, me = ns.me, sim = sim, list = Newest(out) }
	return gamesCache.all.list
end

-- How many games this client shows: every one an auditor holds, else this character's own.
function LG.GamesCount()
	if not IsAud(ns.me) then return #LG.MyGames() end
	local n = 0
	for _, mode in ipairs({ "L", "T" }) do
		local b = GamesBook(mode, false)
		n = n + (b and tonumber(b.n) or 0)
	end
	return n
end

local function Matches(row, q)
	for _, name in ipairs({ row.p1, row.p2 or false, row.arb or false }) do
		if name and ns.FullName(name):lower():find(q, 1, true) then return true end
	end
	return false
end
-- The screens' view: opts = { scope = "all" (an auditor's every game; anyone else gets his own) |
-- "mine", game = a group of GAME_GROUPS or a code of GAMES (nil: all), period = "today" | "week" |
-- "month" (nil: all time, LG.PeriodStart), player = text a name contains, page }. Returns { scope,
-- may (an auditor), game, period, player, rows (the page), list (every row matching), total, page,
-- pages, players (the names of the games matching the game and the period, the most games first,
-- GAMES_PLAYERS of them) }.
function LG.GamesView(opts)
	opts = opts or {}
	local may = IsAud(ns.me)
	local scope = (opts.scope == "all" and may) and "all" or "mine"
	local game = (LG.GAME_OF[opts.game or ""] or opts.game == "bones" or opts.game == "arena" or opts.game == "lottery") and opts.game or nil
	local period = (opts.period == "today" or opts.period == "week" or opts.period == "month") and opts.period or nil
	local from = period and LG.PeriodStart(period) or nil
	local q = type(opts.player) == "string" and opts.player:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	local view = { scope = scope, may = may, game = game, period = period, player = q ~= "" and q or nil, rows = {}, list = {}, players = {} }
	local counts = {}
	for _, r in ipairs(scope == "all" and LG.AllGames() or LG.MyGames()) do
		if (not game or r.game == game or r.g == game) and (not from or r.t >= from) then
			for _, name in ipairs({ r.p1, r.p2 or false, r.arb or false }) do
				if name then
					local k = name:lower()
					counts[k] = counts[k] or { name = name, n = 0 }
					counts[k].n = counts[k].n + 1
				end
			end
			if q == "" or Matches(r, q) then view.list[#view.list + 1] = r end
		end
	end
	for _, c in pairs(counts) do view.players[#view.players + 1] = c end
	table.sort(view.players, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name:lower() < b.name:lower() end)
	for i = #view.players, LG.GAMES_PLAYERS + 1, -1 do view.players[i] = nil end
	view.total = #view.list
	view.pages = math.max(1, math.ceil(view.total / LG.GAMES_PAGE))
	view.page = math.max(1, math.min(math.floor(tonumber(opts.page) or 1), view.pages))
	for i = (view.page - 1) * LG.GAMES_PAGE + 1, math.min(view.total, view.page * LG.GAMES_PAGE) do view.rows[#view.rows + 1] = view.list[i] end
	return view
end

-- A new id for a game played alone (the House, the Lottery's practice): G<second><counter><mark>.
function LG.SoloId() return Arena.NewId("G") end

---------------------------------------------------------------------------
-- Ticks and actions
---------------------------------------------------------------------------

-- A giver's own words again for late logins: belt words every 30 minutes for 7 days, the season
-- every 30 minutes.
function LG.RepeatTick()
	local now = Now()
	local words = CoreT("L", "beltWords") or {}
	for id, own in pairs(ownWords) do
		local w = words[id]
		if not w or now - own.at > LG.WORD_DAYS * LG.DAY then
			ownWords[id] = nil
		elseif w.kind ~= "2" and w.kind ~= "3" and now - own.sent >= LG.WORD_REPEAT then
			own.sent = now
			Arena.Send("AV", "L", EncodeWord(w), { key = "av " .. id, low = true })
		end
	end
	local s = LG.Season("L")
	if s ~= LG.DEFAULT and Me(s.by) and now - (s.sentAt or 0) >= LG.SEASON_REPEAT then LG.SendSeason() end
end

local function Tick()
	LG.ClerkTick()
	LG.RepeatTick()
end
LG.Tick = Tick

-- Involved only while it has something to do: a clerk candidate (the companion loaded), or its own
-- words to repeat.
local function Watch()
	local any = LG.MayClerk() or next(ownWords) ~= nil or (LG.Season("L") ~= LG.DEFAULT and Me(LG.Season("L").by))
	Arena.Involve("ledger", any or nil)
	Arena.Every(30, "ledger", any and Tick or nil)
end
LG.Watch = Watch
ns.On("ARENA_UI_LOADED", function() Bump() Watch() end)
ns.On("LOGIN", Watch)

Arena.Action("ledger.word", function() return ns.ArenaRoles.IsPublicArbiter(ns.me, "L") end,
	function(kind, cat, gk, reason, ref) local id = LG.Word(kind, cat, gk, reason, ref) Watch() return id end)
Arena.Action("ledger.season", function() return ns.ArenaRoles.IsKing(ns.me) or ns.ArenaRoles.IsPublicArbiter(ns.me, "L") end,
	function(...) local ok, why = LG.SetSeason(...) Watch() return ok, why end)
