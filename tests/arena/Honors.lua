-- Olympus honours (Olympus/Honors.lua): the clocks, the donor rankings, the level race, the best
-- guild, what a player holds, and his pick. Run by tests/run.lua with its helpers (H).
local H = ...
local test, eq = H.test, H.eq

local ns = {}
assert(loadfile(H.ADDON_DIR .. "Honors.lua"))("Olympus", ns)
local SHIPPED = ns.Honors.FRAMES_SHIPPED -- (as Honors.lua ships it: the test of 1.2.0's frames below)
ns.Honors.FRAMES_SHIPPED = nil -- (every family's frame: the machinery's tests; 1.2.0 wears the donors' alone)
local Honors = ns.Honors

local GOLD = 10000
-- Server times (UTC). The US weekly reset is Tuesday 15:00 UTC: week 2960 starts on 2026-09-29.
local RESET_0929 = 1790694000     -- Tue 2026-09-29 15:00:00
local RESET_0922 = 1790089200     -- Tue 2026-09-22 15:00:00
local OCT_1 = 1790812800          -- Thu 2026-10-01 00:00:00
local SEP_1 = 1788220800          -- Tue 2026-09-01 00:00:00
local NOW = OCT_1 + 12 * 3600     -- Thu 2026-10-01 12:00: week 2960, October
local DAY = 86400
local HOUR = 3600
-- Invented names for the Treasurer's two characters (his own and his mail's), each with a book.
local BOOK_1, BOOK_2 = "Tovin Brasshand", "Tovin Mailrunner"

local function Keys(list, field)
	local out = {}
	for i, x in ipairs(list) do out[i] = tostring(x[field or "key"]) end
	return table.concat(out, ",")
end
local function Find(list, key, field)
	for _, x in ipairs(list) do if x[field or "key"] == key then return x end end
	return nil
end
local function Money(list, key) local d = Find(list, key) return d and d.money end
local function Gift(name, gold, t, extra)
	local g = { name = name, money = gold * GOLD, t = t, how = "trade" }
	for k, v in pairs(extra or {}) do g[k] = v end
	return g
end
local function Without(held, field, value)
	local out = {}
	for _, h in ipairs(held) do if h[field] ~= value then out[#out + 1] = h end end
	return out
end

---------------------------------------------------------------------------
-- Clocks and names
---------------------------------------------------------------------------

test("honours: the week turns at the weekly reset on the server's clock, as the dues' week does", function()
	eq(Honors.WeekOf(RESET_0929), 2960, "the reset's first second")
	eq(Honors.WeekOf(RESET_0929 - 1), 2959, "a second before the reset")
	eq(Honors.WeekOf(RESET_0922), 2959)
	-- Another region's reset (Dues.Anchor: seconds into a week), e.g. Wednesday 07:00 UTC.
	local eu = 6 * DAY + 7 * HOUR
	eq(Honors.WeekOf(RESET_0929, eu) + 1, Honors.WeekOf(RESET_0929 + DAY - 8 * HOUR, eu), "Wed 07:00 starts the next")
	eq(Honors.WeekOf(RESET_0929 + DAY - 8 * HOUR - 1, eu), Honors.WeekOf(RESET_0929, eu), "Wed 06:59:59 is still the week before")
end)

test("honours: the month is the calendar month of server time, whatever the client's time zone", function()
	local y, m = Honors.MonthDate(Honors.MonthOf(OCT_1))
	eq(y, 2026) eq(m, 10)
	y, m = Honors.MonthDate(Honors.MonthOf(OCT_1 - 1))
	eq(y, 2026) eq(m, 9, "Sep 30 23:59:59")
	eq(Honors.MonthOf(SEP_1) - Honors.MonthOf(SEP_1 - 1), 1, "Aug 31 23:59:59 is the month before")
	y, m = Honors.MonthDate(Honors.MonthOf(1798761599))
	eq(y, 2026) eq(m, 12, "Dec 31 23:59:59")
	y, m = Honors.MonthDate(Honors.MonthOf(1798761600))
	eq(y, 2027) eq(m, 1, "the new year")
	y, m = Honors.MonthDate(Honors.MonthOf(1835438400))
	eq(y, 2028) eq(m, 2, "a leap day is February")
	y, m = Honors.MonthDate(Honors.MonthOf(1835481600))
	eq(y, 2028) eq(m, 3)
	-- A realm seven hours behind UTC: 03:00 UTC on Oct 1 is still Sep 30 there.
	y, m = Honors.MonthDate(Honors.MonthOf(OCT_1 + 3 * HOUR, -7 * HOUR))
	eq(m, 9, "the realm's clock")
end)

test("honours: a realm with daylight saving gives its offset at each time, so a month turns at its own midnight", function()
	-- US Pacific: UTC-8 until 2027-03-14 10:00 UTC (02:00 PST), UTC-7 after.
	local MAR_1_2027 = 1803859200             -- Mon 2027-03-01 00:00 UTC
	local DST = MAR_1_2027 + 13 * DAY + 10 * HOUR
	local pacific = function(t) return t < DST and -8 * HOUR or -7 * HOUR end
	local _, m = Honors.MonthDate(Honors.MonthOf(MAR_1_2027 + 7 * HOUR + 1800, pacific))
	eq(m, 2, "07:30 UTC on Mar 1 is Feb 28 23:30 PST")
	_, m = Honors.MonthDate(Honors.MonthOf(MAR_1_2027 + 8 * HOUR, pacific))
	eq(m, 3, "08:00 UTC is midnight PST")
	local MAY_1_2027 = MAR_1_2027 + 61 * DAY  -- Sat 2027-05-01 00:00 UTC
	_, m = Honors.MonthDate(Honors.MonthOf(MAY_1_2027 + 7 * HOUR + 1800, pacific))
	eq(m, 5, "07:30 UTC on May 1 is 00:30 PDT")
	-- One offset, today's (April: PDT), would put the gift in March.
	_, m = Honors.MonthDate(Honors.MonthOf(MAR_1_2027 + 7 * HOUR + 1800, -7 * HOUR))
	eq(m, 3, "the fixed offset an hour off")
	-- The donors' month takes it the same way: in April, March's top donors leave out February's gift.
	local april = MAR_1_2027 + 31 * DAY + 12 * HOUR
	local gifts = { Gift("Aldric", 50, MAR_1_2027 + 7 * HOUR + 1800), Gift("Brenna", 20, MAR_1_2027 + 9 * HOUR) }
	eq(Keys(Honors.Donors(gifts, april, { offset = pacific }).month), "brenna")
	eq(Keys(Honors.Donors(gifts, april, { offset = -7 * HOUR }).month), "aldric,brenna")
end)

test("honours: names go through ns.Normal first (Forever's 'First-Surname' is 'First Surname'), as Dues.Key does", function()
	-- A stand-in for Core.lua's ns.Normal on a Forever client (ns.splitNames: the game's unit
	-- functions give "First-Surname", the server writes "First Surname-Realm"); this file loads
	-- Honors.lua alone, without Core.lua.
	ns.Normal = function(name)
		local first, rest = name:match("^([^%-]+)%-(.+)$")
		if not first or first:find(" ", 1, true) or rest == "ClassicBetaPvP" then return name end
		return first .. " " .. rest
	end
	local ok, err = pcall(function()
		eq(Honors.Key("Aerin-Duskbrook"), "aerin duskbrook")
		eq(Honors.Key("Aerin Duskbrook-ClassicBetaPvP"), "aerin duskbrook", "the server's form: the same player")
		eq(Honors.Key("Aerin-Stoneward"), "aerin stoneward", "another Aerin")
		-- Donors go by name: one Aerin's gifts make no other Aerin a top donor.
		local donors = Honors.Donors({ Gift("Aerin Duskbrook-ClassicBetaPvP", 50, SEP_1 + DAY) }, NOW)
		eq(#Honors.Holdings({ name = "Aerin-Stoneward" }, { donors = donors }), 0)
		eq(Keys(Honors.Holdings({ name = "Aerin-Duskbrook" }, { donors = donors })), "donor-top-1,donor-month-1")
	end)
	ns.Normal = nil
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Donors
---------------------------------------------------------------------------

test("honours: the top 3 donors of all time, most first; a tie goes to who reached the amount first; the 4th has nothing", function()
	local r = Honors.Donors({
		Gift("Aldric", 50, SEP_1 + DAY),
		Gift("Brenna", 10, SEP_1 + 2 * DAY),
		Gift("Cedric", 30, SEP_1 + 3 * DAY),
		Gift("Brenna", 20, SEP_1 + 5 * DAY), -- 30 in all, reached after Cedric's 30
		Gift("Dunstan", 20, SEP_1 + 4 * DAY),
	}, NOW)
	eq(Keys(r.all), "aldric,cedric,brenna")
	eq(Keys(r.all, "place"), "1,2,3")
	eq(r.all[3].money, 30 * GOLD)
	eq(r.all[3].at, SEP_1 + 5 * DAY, "when his total got there")
	eq(Find(r.all, "dunstan"), nil, "4th: no honour")
end)

test("honours: what counts is what the Treasury's ranking counts: never dues, arena money, transfers, excluded lines, items, payments or bad values", function()
	local t = SEP_1 + 3 * DAY
	local r = Honors.Donors({
		Gift("Aldric", 5, t),
		Gift("Esker", 100, t, { kind = "sale", excluded = true }),         -- as Treasury.Record keeps them
		Gift("Esker", 100, t, { kind = "own", excluded = true }),
		Gift("Esker", 100, t, { kind = "purchase", excluded = true }),
		Gift("Esker", 100, t, { kind = "transfer" }),
		Gift("Esker", 100, t, { kind = "fee" }),                           -- an arena fee (the design)
		Gift("Esker", 100, t, { kind = "arena" }),                         -- arena money on a keeper's client
		Gift("Esker", 100, t, { out = true }),
		Gift("Esker", 100, t, { excluded = true }),
		Gift("Esker", 100, t, { item = 2589, count = 20 }),
		Gift("Esker", 100, t, { note = "Arena fee #7" }),
		Gift("Esker", 100, t, { note = "  arena FEE (fight 12)" }),
		Gift("Esker", 100, t, { note = "Olympus arena fee 2026-10-01 e12" }), -- spec: markets
		Gift("Esker", 100, t, { note = "Arena payout F12" }),
		Gift("Esker", 100, t, { treasurer = true, noted = true }),          -- dues sent with the note
		Gift("Esker", 100, t, { treasurer = true, note = "Olympus fund 2026-09-22 <Olympus II>" }),
		{ name = "Esker", money = 1.5 * GOLD + 0.5, t = t },                  -- not whole copper
		{ name = "Esker", money = -500 * GOLD, t = t },
		{ name = "Esker", money = "lots", t = t },
		{ name = "Esker", money = 2 ^ 40, t = t },                            -- more than the game holds
		{ name = "", money = 100 * GOLD, t = t },
		{ money = 100 * GOLD, t = t },
		{ name = "Esker", money = 100 * GOLD },                               -- no time
		Gift("Esker", 100, NOW + HOUR),                                      -- timed an hour ahead
		"junk", 42,
	}, NOW)
	eq(Keys(r.all), "aldric")
	eq(Keys(r.month), "aldric")
	eq(Find(r.race.week, "esker"), nil)
	-- Counted back in by a keeper (Treasury.Toggle clears excluded and keeps the kind): the
	-- Treasury's ranking counts it (Treasury.lua's Add), and so do the honours. A subject that only
	-- starts like the arena's words is no arena money.
	r = Honors.Donors({
		Gift("Esker", 7, t, { kind = "sale" }),
		Gift("Esker", 2, t, { kind = "own" }),
		Gift("Esker", 1, t, { kind = "purchase" }),
		Gift("Esker", 1, t, { kind = "donation" }),
		Gift("Esker", 1, t, { note = "for the raid" }),
		Gift("Esker", 1, t, { note = "Arenas of glory" }),
	}, NOW)
	eq(Keys(r.all), "esker")
	eq(r.all[1].money, 13 * GOLD)
end)

test("honours: of a Treasurer's book, each giver's week counts only above what may be his dues, as the public ranking counts it", function()
	local w = RESET_0929 + HOUR   -- this week (the race lists every giver)
	local r = Honors.Donors({
		Gift("Fenwick", 1, w, { treasurer = true }),                     -- his dues, all of it
		Gift("Gareth", 5, w, { treasurer = true }),                      -- 1 dues + 4
		Gift("Halvard", 1, w, { treasurer = true, noted = true }),        -- dues with the note
		Gift("Halvard", 3, w + 60, { treasurer = true }),                 -- then 3 more: counts 3
		Gift("Ivo", 3, w - 7 * DAY, { treasurer = true }),                -- two weeks, 3 each: 2 + 2
		Gift("Ivo", 3, w + 30, { treasurer = true }),
		Gift("Jory", 3, w, { treasurer = true, noted = true }),           -- 3 with the note: all dues
		Gift("Kell", 1, w),                                               -- 1 to another keeper: a donation
		Gift("Nia", 2, w, { noted = true }),                              -- the dues' note to another keeper
	}, NOW)
	eq(Money(r.race.week, "fenwick"), nil, "his dues: nothing counts")
	eq(Money(r.race.week, "gareth"), 4 * GOLD)
	eq(Money(r.race.week, "halvard"), 3 * GOLD)
	eq(Money(r.race.week, "ivo"), 2 * GOLD, "this week's part")
	eq(Money(r.race.week, "jory"), nil, "noted gold is all dues")
	eq(Money(r.race.week, "kell"), 1 * GOLD)
	eq(Money(r.race.week, "nia"), 2 * GOLD, "no Treasurer's book: the ranking counts it (Treasury.PublicRanking)")
	eq(Money(r.all, "ivo"), 4 * GOLD, "each week above its own dues")
	eq(Keys(r.all), "gareth,ivo,halvard", "gareth reached 4g before ivo")
	eq(Keys(r.week), "ivo", "last week: ivo's 2g")
	-- The week's amount as the book kept it (Dues' s.amounts[week]): 3 gold this week.
	local this = Honors.WeekOf(w)
	r = Honors.Donors({ Gift("Gareth", 5, w, { treasurer = true }) }, NOW,
		{ duesAmount = function(week) return week == this and 3 * GOLD or GOLD end })
	eq(Money(r.race.week, "gareth"), 2 * GOLD)
	-- A week as the book stamped it (Dues.Stamp's wk: a noted mail for last week's dues) is the
	-- week its dues are counted in: this week's 2g still owe this week's own 1g.
	r = Honors.Donors({ Gift("Gareth", 1, w, { treasurer = true, noted = true, wk = this - 1 }),
		Gift("Gareth", 2, w, { treasurer = true }) }, NOW)
	eq(Money(r.all, "gareth"), 1 * GOLD)
end)

test("honours: each of the Treasurer's books takes off its own dues, as Treasury.PublicRanking does book by book", function()
	local w = RESET_0929 + HOUR
	-- 1g to each of his two characters in one week: each book's week is all dues.
	local r = Honors.Donors({ Gift("Odo", 1, w, { treasurer = BOOK_1 }), Gift("Odo", 1, w, { treasurer = BOOK_2 }),
		Gift("Pim", 1, w, { treasurer = BOOK_1 }), Gift("Pim", 3, w + 60, { treasurer = BOOK_2 }) }, NOW)
	eq(Money(r.race.week, "odo"), nil, "1g in each book: nothing")
	eq(Money(r.race.week, "pim"), 2 * GOLD, "3g in the second book: 2g above its dues")
	-- One book (treasurer = true): one week's dues in all.
	r = Honors.Donors({ Gift("Odo", 1, w, { treasurer = true }), Gift("Odo", 1, w + 60, { treasurer = true }) }, NOW)
	eq(Money(r.race.week, "odo"), 1 * GOLD)
	-- Each book's own amount (its kept s.amounts): the function is told the book's name.
	local asked = {}
	r = Honors.Donors({ Gift("Odo", 5, w, { treasurer = BOOK_1 }), Gift("Odo", 5, w + 60, { treasurer = BOOK_2 }) }, NOW,
		{ duesAmount = function(week, book)
			asked[#asked + 1] = tostring(book)
			return book == BOOK_2 and 3 * GOLD or GOLD
		end })
	eq(Money(r.race.week, "odo"), 6 * GOLD, "4g above the first book's 1g, 2g above the second's 3g")
	eq(asked[1], BOOK_1) eq(asked[2], BOOK_2)
end)

test("honours: the week's top donor is last week's, held through this week; this week is the race", function()
	local r = Honors.Donors({
		Gift("Joss", 10, RESET_0922 + 3 * DAY),
		Gift("Kestrel", 10, RESET_0922 + 2 * DAY),     -- the same 10g, sooner
		Gift("Lysander", 9, RESET_0929 - 1),            -- the last second of last week
		Gift("Lysander", 1, RESET_0929 - 1),
		Gift("Joss", 100, RESET_0929),                  -- this week's first second
		Gift("Mira", 4, RESET_0922 - 1),                -- the week before last
	}, NOW)
	eq(r.weekNo, 2959)
	eq(Keys(r.week), "kestrel", "a tie goes to who got there first")
	eq(Keys(r.race.week), "joss")
	eq(r.race.weekNo, 2960)
	eq(r.race.week[1].money, 100 * GOLD)
	eq(Keys(Honors.Donors({ Gift("Lysander", 10, RESET_0929 - 1) }, NOW).week), "lysander", "14:59:59 on reset day is last week")
	eq(Keys(Honors.Donors({ Gift("Lysander", 10, RESET_0929) }, NOW).week), "", "15:00:00 is this week")
	-- The minimum: a few coppers make no top donor.
	r = Honors.Donors({ { name = "Nell", money = 50, t = RESET_0922 + DAY } }, NOW)
	eq(#r.week, 0, "under DONOR_MIN")
	eq(Keys(r.race.week), "", "nothing this week")
end)

test("honours: the month's top 3 are last month's (1st to 3rd, the 4th nothing); this month is the race", function()
	local r = Honors.Donors({
		Gift("Aldric", 40, SEP_1 + DAY),
		Gift("Brenna", 30, SEP_1 + 2 * DAY),
		Gift("Cedric", 20, SEP_1 + 3 * DAY),
		Gift("Dunstan", 10, SEP_1 + 4 * DAY),
		Gift("Esker", 99, SEP_1 - 1),                  -- August
		Gift("Fenwick", 500, OCT_1),                   -- October: the race
	}, NOW)
	eq(Keys(r.month), "aldric,brenna,cedric")
	eq(Keys(r.month, "place"), "1,2,3")
	local y, m = Honors.MonthDate(r.monthNo)
	eq(y * 100 + m, 202609)
	eq(Keys(r.race.month), "fenwick")
	eq(Keys(r.all), "fenwick,esker,aldric")
	-- On a realm seven hours behind UTC, 03:00 UTC on Oct 1 is still September.
	r = Honors.Donors({ Gift("Gareth", 50, OCT_1 + 3 * HOUR), Gift("Aldric", 40, SEP_1 + DAY) }, NOW, { offset = -7 * HOUR })
	eq(Keys(r.month), "gareth,aldric")
	eq(Keys(r.race.month), "")
end)

test("honours: the closed week's and month's top donors are recorded once and kept while they are held", function()
	local first = Honors.Donors({ Gift("Kes", 10, RESET_0922 + DAY), Gift("Aldric", 40, SEP_1 + DAY) }, NOW)
	eq(Keys(first.week), "kes") eq(Keys(first.month), "aldric,kes")
	-- A day later a book relayed late adds last week's and September's biggest gifts.
	local later = { Gift("Kes", 10, RESET_0922 + DAY), Gift("Aldric", 40, SEP_1 + DAY),
		Gift("Lark", 20, RESET_0922 + 2 * DAY), Gift("Lark", 60, SEP_1 + 2 * DAY) }
	local again = Honors.Donors(later, NOW + DAY)
	eq(Keys(again.week), "lark", "worked out again, the held week's winner would change")
	eq(Keys(again.month), "lark,aldric,kes")
	local r = Honors.Donors(later, NOW + DAY, { kept = first })
	eq(Keys(r.week), "kes", "the week recorded at its close")
	eq(r.week[1].money, 10 * GOLD) eq(r.week[1].place, 1) eq(r.week[1].at, RESET_0922 + DAY)
	eq(Keys(r.month), "aldric,kes")
	eq(Keys(r.all), "lark,aldric,kes", "all time stays live")
	-- A noted mail stamped for last week (after the reset) changes nothing either.
	local noted = { Gift("Kes", 10, RESET_0922 + DAY), Gift("Mox", 11, RESET_0922 + 2 * DAY, { treasurer = true }) }
	local closed = Honors.Donors(noted, NOW)
	eq(Keys(closed.week), "kes", "Mox's 10g above his dues, and Kes got there first")
	noted[#noted + 1] = Gift("Mox", 2, RESET_0929 + DAY, { treasurer = true, noted = true, wk = 2959 })
	eq(Keys(Honors.Donors(noted, NOW + DAY).week), "mox", "worked out again: the noted 2g are his dues, his 11g all count")
	eq(Keys(Honors.Donors(noted, NOW + DAY, { kept = closed }).week), "kes")
	-- The next week closes: worked out once more.
	r = Honors.Donors(later, NOW + 7 * DAY, { kept = first })
	eq(r.weekNo, 2960) eq(Keys(r.week), "", "nobody gave in week 2960")
	eq(Keys(r.month), "aldric,kes", "September is still the month held")
	-- A kept list is taken as far as it is well formed: one per giver and per place.
	r = Honors.Donors({}, NOW, { kept = { weekNo = 2959, week = { "junk", { name = "Kes", money = 10 * GOLD, place = 1 },
		{ name = "Lark", money = 20 * GOLD, place = 1 } }, monthNo = first.monthNo,
		month = { { name = "Aldric", money = -3, place = 1 }, { name = "Brenna", money = GOLD, place = 2 }, { name = "Cedric", money = GOLD, place = 9 } } } })
	eq(Keys(r.week), "kes")
	eq(Keys(r.month), "brenna") eq(r.month[1].place, 2)
end)

test("honours: donor sums stay whole copper and never pass what the game holds", function()
	local gifts = {}
	for i = 1, 40 do gifts[i] = { name = "Oswin", money = 2147483647, t = SEP_1 + i } end
	gifts[#gifts + 1] = { name = "Pell", money = 12345, t = SEP_1 }
	gifts[#gifts + 1] = { name = "Pell", money = 67891, t = SEP_1 + 1 }
	local r = Honors.Donors(gifts, NOW)
	eq(r.all[1].money, 2147483647, "capped")
	eq(r.all[2].money, 80236)
	for _, d in ipairs(r.all) do eq(d.money, math.floor(d.money), "whole copper") end
end)

---------------------------------------------------------------------------
-- The level race
---------------------------------------------------------------------------

local function Up(name, guid, level, t, vouched, from, since)
	return { name = name, guid = guid, level = level, t = t, vouched = vouched, from = from, since = since }
end

-- (the design: the level race is the FIRST to 20, 40 and 60, one place each; the three places at
-- every 10 levels are gone. These tests were the three places' and now expect the first alone.)
test("honours: the level race takes the first vouched to each milestone (20, 40 and 60), by time", function()
	eq(table.concat(Honors.MILESTONES, ","), "20,40,60") eq(Honors.PLACES, 1)
	local book, fresh, pending = Honors.LevelRace({}, {
		Up("Aldric", "Player-1-A", 20, 400, true),
		Up("Brenna", "Player-1-B", 20, 200, true, 19),
		Up("Cedric", "Player-1-C", 20, 300, true),
		Up("Dunstan", "Player-1-D", 20, 100, true),
		Up("Esker", "Player-1-E", 19, 50, true),     -- not 20 yet
		Up("Fenn", "Player-1-F", 10, 10, true, 9),    -- 10 is no milestone any more
	}, 100000)
	eq(Keys(book[20], "name"), "Dunstan")
	eq(Keys(book[20], "place"), "1")
	eq(#fresh, 1)
	eq(fresh[1].milestone, 20) eq(fresh[1].place, 1) eq(fresh[1].guid, "Player-1-D")
	eq(#pending[20], 0, "the place is taken: nobody waits")
	eq(#book[40], 0) eq(#book[60], 0) eq(book[10], nil)
end)

test("honours: a claim counts only the milestones it was seen crossing: no sweep by a veteran, none for a first sight", function()
	local now = 100000
	local book = Honors.LevelRace({}, {
		Up("Vetra", "Player-1-V", 46, 5000, true, 45),  -- a veteran dings 46 the day 1.2 ships
		Up("Fenn", "Player-1-F", 20, 4000, true, 19),    -- a new character reaches 20
		Up("Joiner", "Player-1-J", 25, 3000, true),       -- 25, with nothing seen before it
	}, now)
	eq(Keys(book[20], "name"), "Fenn")
	for _, m in ipairs({ 40, 60 }) do eq(#book[m], 0, "milestone " .. m) end
	-- A jump seen (the census had him at 19, then saw 41): both milestones crossed, at the time
	-- it saw 41.
	book = Honors.LevelRace({}, { Up("Hopper", "Player-1-H", 41, 7000, true, 19, 6000) }, now)
	eq(Keys(book[20], "name"), "Hopper") eq(Keys(book[40], "name"), "Hopper")
	eq(book[40][1].t, 7000)
	eq(#book[60], 0)
	-- The level-up itself (no from): its own level, when a milestone.
	book = Honors.LevelRace({}, { Up("Dinger", "Player-1-D", 40, 7000, true) }, now)
	eq(Keys(book[40], "name"), "Dinger")
	eq(#book[20], 0) eq(#book[60], 0)
end)

test("honours: the race starts at opts.start: a crossing that may be earlier counts for nothing", function()
	local start, now = 50000, 100000
	local claims = {
		Up("Early", "Player-1-E", 20, 40000, true, 19),           -- before the start
		Up("Straddle", "Player-1-S", 40, 60000, true, 39, 45000), -- seen at 39 before it: 40 may be earlier
		Up("Onit", "Player-1-O", 20, start, true, 19),             -- at the start
		Up("Later", "Player-1-L", 40, 61000, true, 39, 55000),
	}
	local book = Honors.LevelRace({}, claims, now, { start = start })
	eq(Keys(book[20], "name"), "Onit")
	eq(Keys(book[40], "name"), "Later")
	book = Honors.LevelRace({}, claims, now)
	eq(Keys(book[20], "name"), "Early", "no start: every claim, the first takes the place")
	eq(Keys(book[40], "name"), "Straddle")
end)

test("honours: an unvouched claim never beats a vouched one, and never takes a place alone", function()
	local book, fresh, pending = Honors.LevelRace(nil, {
		Up("Ulric", "Player-1-U", 20, 50, false),    -- first, but only his own word
		Up("Vesna", "Player-1-V", 20, 500, true),
	}, 100000)
	eq(Keys(book[20], "name"), "Vesna")
	eq(Keys(pending[20], "name"), "", "the one place is taken: nobody waits for it")
	book, fresh, pending = Honors.LevelRace(nil, { Up("Ulric", "Player-1-U", 20, 50, false) }, 100000)
	eq(#book[20], 0, "alone and unvouched: no place")
	eq(#fresh, 0)
	eq(Keys(pending[20], "name"), "Ulric", "waits for a witness")
	eq(#pending[40], 0, "a level-up to 20 crosses 20 alone")
	-- His vouched claim of a later level (the census saw 19, then 22) stands for 20 at its own time.
	book = Honors.LevelRace(nil, { Up("Ulric", "Player-1-U", 20, 50, false), Up("Ulric", "Player-1-U", 22, 900, true, 19),
		Up("Vesna", "Player-1-V", 20, 500, true) }, 100000)
	eq(Keys(book[20], "name"), "Vesna", "his witnessed time is 900, after hers")
	book = Honors.LevelRace(nil, { Up("Ulric", "Player-1-U", 20, 50, false), Up("Ulric", "Player-1-U", 22, 900, true, 19) }, 100000)
	eq(Keys(book[20], "name"), "Ulric") eq(book[20][1].t, 900)
end)

test("honours: a place waits CONFIRM_AFTER, so a claim timed earlier and heard late still gets its turn", function()
	local now = 100000
	local claims = { Up("Wynn", "Player-1-W", 40, now - 100, true, 39) }
	local book, fresh, pending = Honors.LevelRace({}, claims, now)
	eq(#book[40], 0, "too fresh")
	eq(#fresh, 0)
	eq(Keys(pending[40], "name"), "Wynn")
	-- A rival's claim, timed before his, arrives meanwhile: it comes first, and takes the place.
	claims[#claims + 1] = Up("Xan", "Player-1-X", 40, now - 200, true, 39)
	book, fresh = Honors.LevelRace(book, claims, now + Honors.CONFIRM_AFTER)
	eq(Keys(book[40], "name"), "Xan")
	eq(Keys(fresh, "name"), "Xan")
	eq(Keys(fresh, "milestone"), "40")
	eq(Keys(fresh, "place"), "1")
end)

test("honours: once recorded, a level place never changes; a late earlier claim takes the next free place or none", function()
	local book = { [20] = { { guid = "Player-1-A", name = "Aldric", t = 400, place = 1 } } }
	local claims = { Up("Yara", "Player-1-Y", 20, 5, true), Up("Zed", "Player-1-Z", 20, 1, true),
		Up("Aldric", "Player-1-A", 20, 1, true) } -- Aldric again, earlier: he keeps his one place
	local out, fresh, pending = Honors.LevelRace(book, claims, 100000)
	eq(Keys(out[20], "name"), "Aldric", "the place recorded stays his, whatever earlier claim comes late")
	eq(out[20][1].t, 400, "his recorded time")
	eq(#fresh, 0, "nothing new")
	eq(#pending[20], 0)
	eq(#book[20], 1, "the book passed in is left alone")
	-- A milestone still free takes its first; the full one changes nothing, whatever it hears.
	local again, fresh2 = Honors.LevelRace(out, { Up("Yara", "Player-1-Y", 40, 0, true), Up("Zed", "Player-1-Z", 20, 0, true) }, 200000)
	eq(Keys(again[20], "name"), "Aldric") eq(Keys(again[40], "name"), "Yara")
	eq(#fresh2, 1)
	-- A malformed book keeps its first well-formed place.
	local messy = { [20] = { "junk", { guid = "Player-1-A", name = "Aldric" }, { guid = "Player-1-A", name = "Aldric" },
		{ name = "no guid" }, { guid = "Player-1-B" }, { guid = "Player-1-C", name = "Cedric" } } }
	local tidy = Honors.LevelRace(messy, {}, 100000)
	eq(Keys(tidy[20], "guid"), "Player-1-A")
end)

test("honours: malformed and future level claims are ignored", function()
	local now = 100000
	local book = Honors.LevelRace({}, {
		Up("Aldric", "Player-1-A", 60, 1000, true, 59),
		Up("Brenna", "Player-1-B", 61, 10, true),       -- past the level cap
		Up("Brenna", "Player-1-B", 0, 10, true),
		Up("Brenna", "Player-1-B", 20.5, 10, true),
		Up("Brenna", "Player-1-B", "twenty", 10, true),
		Up("Brenna", "Player-1-B", 20, 10, true, 20),   -- from: not below the level
		Up("Brenna", "Player-1-B", 20, 10, true, 22),
		Up("Brenna", "Player-1-B", 20, 10, true, 18.5),
		Up("Brenna", "Player-1-B", 20, 10, true, "nineteen"),
		Up("Brenna", "Player-1-B", 20, 10, true, 0),
		Up("Brenna", "Player-1-B", 20, 10, true, 19, 20), -- since after the level was seen
		Up("Brenna", "Player-1-B", 20, 10, true, 19, "x"),
		Up("Brenna", nil, 20, 10, true),                -- no GUID
		Up(nil, "Player-1-B", 20, 10, true),            -- no name
		Up("Cedric", "Player-1-C", 40, now + HOUR, true), -- an hour ahead of the clock
		"junk",
	}, now)
	eq(Keys(book[60], "name"), "Aldric")
	for _, m in ipairs({ 20, 40 }) do eq(#book[m], 0, "milestone " .. m) end
end)

---------------------------------------------------------------------------
-- The best guild
---------------------------------------------------------------------------

test("honours: the best guild is the highest average level; ties go to more members, then the name; small guilds can't win", function()
	local rows = {
		{ guild = "Olympus Aurora", leader = "Maelis", members = 120, avgLevel = 45.3 },
		{ guild = "Olympus Dawn", leader = "Quill", members = 200, avgLevel = 45.34 },   -- 45.3 to the tenth
		{ guild = "Olympus Borealis", leader = "Tovan", members = 200, avgLevel = 45.3 },
		{ guild = "Olympus Cinder", leader = "Rook", members = 2, avgLevel = 60 },         -- two players
		{ guild = "Olympus Ember", leader = "Sable", members = 300, avgLevel = 44.9 },
		{ guild = "Olympus Forged", leader = "Wren", members = 300, avgLevel = 75 },       -- impossible
		{ guild = "Olympus Gale", leader = "Ione", members = 300, avgLevel = 59, off = true }, -- net-off
		{ guild = "Olympus Hollow", members = 300, avgLevel = 58 },                       -- no leader known
		{ guild = "Olympus Iron", leader = "Pax", members = 30.5, avgLevel = 58 },
	}
	local list = Honors.GuildRanking(rows)
	eq(Keys(list, "guild"), "Olympus Borealis,Olympus Dawn,Olympus Aurora,Olympus Ember")
	eq(list[1].place, 1)
	local top = Honors.GuildTop(rows)
	eq(top.leader, "Tovan")
	eq(top.members, 200)
	-- A guild at the minimum can win; one under it can't.
	eq(Honors.GuildTop({ { guild = "Olympus Jade", leader = "Lark", members = Honors.GUILD_MIN_MEMBERS, avgLevel = 30 } }).leader, "Lark")
	eq(Honors.GuildTop({ { guild = "Olympus Jade", leader = "Lark", members = Honors.GUILD_MIN_MEMBERS - 1, avgLevel = 30 } }), nil)
	eq(Honors.GuildTop({}), nil)
	eq(Honors.GuildTop(nil), nil)
end)

test("honours: the best guild from the census as it is kept: one faction, the guilds the caller leaves out, and only fresh reports", function()
	local now = 1790000000
	local guilds = {
		["Olympus Aurora"] = { total = 400, leader = "Maelis", avgLevel = 31.2, faction = "Alliance", t = now - HOUR },
		["Olympus Kiln"] = { total = 400, leader = "Grom", avgLevel = 40.1, faction = "Horde", t = now - HOUR },
		["Olympus Nameless"] = { total = 400, leader = "Nox", avgLevel = 50, t = now - HOUR },  -- no faction said
	}
	eq(Honors.GuildTop(guilds, { faction = "Alliance" }).guild, "Olympus Aurora", "a row with no faction is no Alliance row")
	eq(Honors.GuildTop(guilds, { faction = "Horde" }).guild, "Olympus Kiln")
	eq(Honors.GuildTop(guilds).guild, "Olympus Nameless", "no faction asked: every row")
	-- The census's rows don't say net-off (Data.NetOff) or no longer Olympus (ns.IsFederation): skip.
	guilds["Olympus Gale"] = { total = 300, leader = "Ione", avgLevel = 59, faction = "Alliance", t = now - HOUR }
	guilds["Gale Remnant"] = { total = 300, leader = "Ilse", avgLevel = 58, faction = "Alliance", t = now - HOUR }
	local asked = {}
	local top = Honors.GuildTop(guilds, { faction = "Alliance", skip = function(guild, row)
		asked[guild] = row.leader
		return guild == "Olympus Gale" or guild == "Gale Remnant"
	end })
	eq(top.guild, "Olympus Aurora")
	eq(asked["Olympus Gale"], "Ione", "skip is given the guild and its row")
	eq(Honors.GuildTop(guilds, { faction = "Alliance" }).guild, "Olympus Gale", "not skipped: it wins")
	-- With now: a report older than GUILD_MAX_AGE (kept 7 days by the census), or with no time, can't win.
	local rows = {
		{ guild = "Olympus Aurora", leader = "Maelis", members = 100, avgLevel = 31.2, t = now - Honors.GUILD_MAX_AGE },
		{ guild = "Olympus Quiet", leader = "Hush", members = 100, avgLevel = 55, t = now - Honors.GUILD_MAX_AGE - 1 },
		{ guild = "Olympus Timeless", leader = "Ever", members = 100, avgLevel = 58 },
	}
	eq(Honors.GuildTop(rows, { now = now }).guild, "Olympus Aurora")
	eq(Honors.GuildTop(rows, { now = now, maxAge = 7 * DAY }).guild, "Olympus Quiet")
	eq(Honors.GuildTop(rows).guild, "Olympus Timeless", "no now: no age asked")
end)

---------------------------------------------------------------------------
-- Holdings
---------------------------------------------------------------------------

local ME = { name = "Aldric", guid = "Player-1-A" }
local function Everything()
	local donors = Honors.Donors({
		Gift("Aldric", 50, SEP_1 + DAY),                  -- 1st of all time and of September
		Gift("Brenna", 10, RESET_0922 + DAY),             -- 2nd of both
		Gift("Aldric", 15, RESET_0922 + 2 * DAY),          -- ...and last week's top donor
	}, NOW)
	-- Each milestone's ding seen: Brenna first to 20 and 40, Aldric first to 60.
	local claims = {}
	for _, m in ipairs(Honors.MILESTONES) do
		local first = m == 60 and "Aldric" or "Brenna"
		claims[#claims + 1] = Up(first, first == "Aldric" and "Player-1-A" or "Player-1-B", m, 100 * m, true, m - 1)
		claims[#claims + 1] = Up(first == "Aldric" and "Brenna" or "Aldric", first == "Aldric" and "Player-1-B" or "Player-1-A",
			m, 100 * m + 50, true, m - 1)
	end
	return {
		belts = {
			{ cat = "A", guid = "Player-1-A", name = "Aldric" },
			{ cat = "CMA", guid = "Player-1-A", name = "Aldric" },
			{ cat = "R4", guid = "Player-1-A", name = "Aldric" },
			{ cat = "CWA", guid = "Player-1-Q", name = "Aldric" },  -- a namesake's (another character)
			{ cat = "B29", guid = "Player-1-A", name = "Aldric" },  -- a level bracket: no honour
		},
		tiers = { ["Player-1-A"] = "gold" },
		donors = donors,
		levels = Honors.LevelRace({}, claims, 100000),
		guild = Honors.GuildTop({ { guild = "Olympus Aurora", leader = "Aldric", members = 100, avgLevel = 40 } }),
	}
end

test("1.2.0 honours: the release wears the all-time donors' frames alone; the level race's comet, the month's, the arena's and the rest wait (the owner's call)", function()
	local saved = Honors.FRAMES_SHIPPED
	local families = {}
	for family in pairs(SHIPPED or {}) do families[#families + 1] = family end
	eq(table.concat(families, ","), "donor-top", "Honors.lua ships the all-time donors' frames alone")
	Honors.FRAMES_SHIPPED = SHIPPED
	local ok, err = pcall(function()
		local held = Honors.Holdings(ME, Everything())
		-- Held as before: the honours themselves are untouched, only the frames worn.
		assert(Keys(held):find("level-race-60", 1, true) and Keys(held):find("donor-top-1", 1, true), Keys(held))
		eq((Honors.Shown({ frame = "donor-top-1" }, held)), "donor-top-1", "the all-time donors' frame is worn")
		for _, key in ipairs({ "level-race-60", "donor-month-1", "arena-champion", "arena-class-mage", "guild-top-leader" }) do
			eq((Honors.Shown({ frame = key }, held)), "rank", key .. ": his rank's frame instead")
			eq(select(2, Honors.Choose({}, held, key)), "frame", key .. ": not offered to pick")
		end
		assert(Honors.Choose({}, held, "donor-top-1"), "the donors' frame can be picked")
	end)
	Honors.FRAMES_SHIPPED = saved
	if not ok then error(err, 0) end
end)

test("honours: a player's holdings, each with its frame, mark and title, in ORDER", function()
	local held = Honors.Holdings(ME, Everything())
	-- (the design: no week's top donor, and the level race's first alone.)
	eq(Keys(held), "arena-champion,arena-class-mage,arena-race-nightelf,guild-top-leader,donor-top-1,level-race-60,"
		.. "donor-month-1,arena-tier-gold")
	local belt = held[1]
	eq(belt.kind, "belt") eq(belt.frame, "arena-champion") eq(belt.title, "arena-champion")
	eq(belt.art, "gryphon-gold", "the arena champion's gryphon") eq(belt.mark, "gryphon-gold") eq(belt.shape, "winged")
	eq(belt.metal, "gold")
	local tier = Find(held, "arena-tier-gold")
	eq(tier.badge, "arena-tier-gold") eq(tier.metal, "gold")
	eq(tier.frame, nil, "the tier badge is no frame")
	eq(tier.mark, nil) eq(tier.title, nil) eq(tier.art, nil)
	local lv = Find(held, "level-race-60")
	eq(lv.milestone, 60) eq(lv.place, 1) eq(lv.family, "level-60")
	eq(lv.art, "comet-gold", "the gold comet: first to 60; the addon writes 60 on it")
	eq(lv.frame, "level-race-60") eq(lv.mark, "comet-gold") eq(lv.title, "level-race-60") eq(lv.shape, "plain")
	eq(Find(held, "donor-week"), nil, "the week's top donor is gone")
	eq(Find(held, "guild-top-leader").guild, "Olympus Aurora")
	eq(Find(held, "guild-top-leader").art, "owl-gold") eq(Find(held, "guild-top-leader").shape, "winged")
	eq(Find(held, "donor-top-1").art, "cornucopia-gold") eq(Find(held, "donor-month-1").art, "koi-gold")
	eq(Find(held, "arena-class-mage").art, "mage-gold") eq(Find(held, "arena-race-nightelf").art, "nightsaber-gold")
	-- Brenna: first to 20 and 40, 2nd of all time and of September; nothing else.
	local brenna = Honors.Holdings({ name = "Brenna", guid = "Player-1-B" }, Everything())
	eq(Keys(brenna), "donor-top-2,level-race-40,level-race-20,donor-month-2")
	eq(Find(brenna, "level-race-20").art, "comet-bronze") eq(Find(brenna, "level-race-40").art, "comet-silver")
	eq(Find(brenna, "donor-top-2").art, "cornucopia-silver")
end)

test("honours: every honour's art is the design's beast in its metal (gold, silver, bronze), shipped in media/honors", function()
	-- The design's table: the arena champion's gryphon (winged), the class beasts, the racial
	-- mounts, the cornucopia, the koi, the comet, the owl (winged, gold only), the raven.
	local want = {
		["arena-champion"] = "gryphon-gold", ["arena-champion-2"] = "gryphon-silver", ["arena-champion-3"] = "gryphon-bronze",
		["arena-class-warrior"] = "boar-gold", ["arena-class-paladin"] = "paladin-gold", ["arena-class-hunter-2"] = "hunter-silver",
		["arena-class-rogue"] = "rogue-gold", ["arena-class-priest-3"] = "priest-bronze", ["arena-class-shaman"] = "shaman-gold",
		["arena-class-mage-2"] = "mage-silver", ["arena-class-warlock"] = "warlock-gold", ["arena-class-druid-3"] = "druid-bronze",
		["arena-race-human"] = "lion-gold", ["arena-race-dwarf-2"] = "ram-silver", ["arena-race-nightelf"] = "nightsaber-gold",
		["arena-race-gnome-3"] = "mechanostrider-bronze", ["arena-race-orc"] = "orc-wolf-gold",
		["arena-race-undead-2"] = "skeletal-horse-silver", ["arena-race-tauren"] = "kodo-gold", ["arena-race-troll-3"] = "raptor-bronze",
		["donor-top-1"] = "cornucopia-gold", ["donor-top-3"] = "cornucopia-bronze", ["donor-month-2"] = "koi-silver",
		["oracle-1"] = "raven-gold", ["oracle-3"] = "raven-bronze", ["guild-top-leader"] = "owl-gold",
		["wanted-slayer-1"] = "orc-wolf-gold", ["wanted-slayer-2"] = "orc-wolf-silver", ["wanted-slayer-3"] = "orc-wolf-bronze",
		["level-race-20"] = "comet-bronze", ["level-race-40"] = "comet-silver", ["level-race-60"] = "comet-gold",
	}
	for key, art in pairs(want) do
		local got, shape, metal = Honors.ArtOf(key)
		eq(got, art, key)
		eq(shape, (art:find("^gryphon") or art:find("^owl")) and "winged" or "plain", key .. "'s shape")
		eq(metal, art:match("%-(%a+)$"), key .. "'s metal")
	end
	for _, key in ipairs({ "rank", "none", "arena-tier-gold", "guild-top-member", "donor-week", "level-race-10", "level-race-1-60",
		"arena-class-deathknight", "arena-race-goblin", "donor-top-4", "oracle", "", "x" }) do
		eq(Honors.ArtOf(key), nil, "no art: " .. key)
	end
	-- Every file the honours can name: 3 gryphons, 9 classes and 8 races in three metals, three
	-- cornucopias, koi and ravens, three comets and the gold owl.
	local files = Honors.ArtFiles()
	eq(#files, 3 + 27 + 24 + 9 + 3 + 1)
	local listed = {}
	for _, f in ipairs(files) do listed[f] = true end
	for _, art in pairs(want) do eq(listed[art], true, art) end
	eq(listed["owl-silver"], nil, "the owl is gold only") eq(listed["phoenix-gold"], nil, "no phoenix")
	-- Everyone holding everything: each honour's art is one of those files, and each file is held.
	local belts, podium, players = {}, {}, {}
	local cats = { "A", "CWA", "CPA", "CHU", "CRO", "CPR", "CSH", "CMA", "CWL", "CDR", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8" }
	for i, cat in ipairs(cats) do
		belts[i] = { cat = cat, guid = "Player-9-" .. i, name = "Belt" .. i }
		players[#players + 1] = { name = "Belt" .. i, guid = "Player-9-" .. i }
		for place = 2, 3 do
			local guid = ("Player-%d-%d"):format(place, i)
			podium[#podium + 1] = { cat = cat, place = place, guid = guid, name = "Pod" .. place .. "x" .. i }
			players[#players + 1] = { name = "Pod" .. place .. "x" .. i, guid = guid }
		end
	end
	local names = { "Una", "Duo", "Tres" }
	local gifts, claims, oracle = {}, {}, {}
	for place, name in ipairs(names) do
		gifts[#gifts + 1] = Gift(name, 100 - place, RESET_0922 + DAY)
		claims[#claims + 1] = Up(name, "Player-8-" .. place, Honors.MILESTONES[place], 100 * place, true, Honors.MILESTONES[place] - 1)
		oracle[place] = { name = name, place = place }
		players[#players + 1] = { name = name, guid = "Player-8-" .. place }
	end
	local inputs = { belts = belts, podium = podium, donors = Honors.Donors(gifts, NOW),
		levels = Honors.LevelRace({}, claims, 100000), oracle = { month = oracle, monthNo = Honors.MonthOf(SEP_1) },
		guild = { guild = "Olympus Aurora", leader = "Una", members = 100, avgLevel = 40 } }
	local got = {}
	for _, p in ipairs(players) do
		for _, h in ipairs(Honors.Holdings(p, inputs)) do
			eq(listed[h.art], true, "a shipped file: " .. tostring(h.art) .. " (" .. h.key .. ")")
			got[h.art] = true
		end
	end
	for _, f in ipairs(files) do eq(got[f], true, "held: " .. f) end
end)

test("honours: belts and level places follow the GUID (a rename keeps them, a namesake gets none); names where there is no GUID", function()
	local inputs = Everything()
	local renamed = Honors.Holdings({ name = "Aldricus", guid = "Player-1-A" }, inputs)
	eq(Find(renamed, "arena-champion") ~= nil, true, "his belt under his new name")
	eq(Find(renamed, "level-race-60") ~= nil, true)
	eq(Find(renamed, "donor-top-1"), nil, "donations are by name")
	local namesake = Honors.Holdings({ name = "Aldric", guid = "Player-1-Q" }, inputs)
	eq(Keys(namesake), "arena-class-warrior,guild-top-leader,donor-top-1,donor-month-1", "his own belt, and what goes by name")
	local noGuid = Honors.Holdings({ name = "aldric-Realm" }, inputs)
	eq(Find(noGuid, "arena-champion") ~= nil, true, "by name, any case, without the realm")
	eq(#Honors.Holdings({}, inputs), 0)
	eq(#Honors.Holdings(ME, nil), 0)
end)

---------------------------------------------------------------------------
-- The pick
---------------------------------------------------------------------------

test("honours: Choose takes only honours held (and the rank's frame, or none)", function()
	local held = Honors.Holdings(ME, Everything())
	local pick = { frame = "rank", seen = { ["belt-A"] = { place = 1 } } }
	local p = Honors.Choose(pick, held, "donor-top-1", "level-race-60")
	eq(p.frame, "donor-top-1") eq(p.title, "level-race-60")
	eq(p.seen["belt-A"].place, 1, "what was seen is kept")
	eq(p.seen["donor-top"], nil, "a pick that has seen is not filled in")
	eq(pick.frame, "rank", "the pick passed in is left alone")
	p = Honors.Choose(pick, held, "none", "none")
	eq(p.frame, "none") eq(p.title, nil)
	p = Honors.Choose(pick, held, "rank")
	eq(p.frame, "rank") eq(p.title, nil)
	local bad, why = Honors.Choose(pick, held, "arena-race-orc", nil)
	eq(bad, nil) eq(why, "frame")
	bad, why = Honors.Choose(pick, held, "rank", "donor-top-2")
	eq(bad, nil) eq(why, "title")
	bad, why = Honors.Choose(pick, held, "arena-tier-gold", nil)
	eq(bad, nil, "the tier badge is no frame") eq(why, "frame")
	bad, why = Honors.Choose(pick, held, "comet-gold", nil)
	eq(bad, nil, "the art is no pick") eq(why, "frame")
	bad, why = Honors.Choose(pick, held, nil, nil)
	eq(bad, nil) eq(why, "frame")
end)

test("honours: a first choice, made before any Update, is not undone by the next Update", function()
	local held = Honors.Holdings(ME, Everything())
	local p = Honors.Choose(nil, held, "donor-top-1", "donor-top-1")
	eq(p.seen["belt-A"].place, 1, "what he holds is remembered")
	eq(p.seen["level-60"].place, 1)
	eq(p.seen["donor-top"].frame, "donor-top-1")
	local q, earned, lost = Honors.Update(p, held, true)
	eq(q.frame, "donor-top-1") eq(q.title, "donor-top-1")
	eq(#earned, 0) eq(#lost, 0)
	-- Something new after it still switches on.
	local fewer = Without(held, "key", "donor-month-1")
	p = Honors.Choose(nil, fewer, "donor-top-1", "donor-top-1")
	q, earned = Honors.Update(p, held, true)
	eq(Keys(earned), "donor-month-1")
	eq(q.frame, "donor-month-1")
end)

test("honours: a new honour switches on by itself; a pick no longer held stays, and shows the rank meanwhile", function()
	-- A new profile: the best held switches on.
	local held = Honors.Holdings(ME, Everything())
	local p, earned, lost = Honors.Update(nil, held, true)
	eq(p.frame, "arena-champion") eq(p.title, "arena-champion")
	eq(#earned, #held) eq(#lost, 0)
	-- He picks his donor frame and the race title; the same honours held again (the month's top
	-- donor once more, say): nothing is new, his pick stays.
	p = Honors.Choose(p, held, "donor-top-1", "level-race-60")
	local q
	q, earned = Honors.Update(p, held, true)
	eq(q.frame, "donor-top-1") eq(q.title, "level-race-60") eq(#earned, 0)
	-- Something newly earned (a lesser honour too) switches on.
	local fewer = Without(held, "key", "donor-month-1")
	q = Honors.Update(Honors.Choose(p, fewer, "donor-top-1", "level-race-60"), fewer, true)
	eq(q.frame, "donor-top-1")
	q, earned = Honors.Update(q, held, true)
	eq(q.frame, "donor-month-1") eq(q.title, "donor-month-1")
	eq(Keys(earned), "donor-month-1")
	-- The belt lost while picked: the pick stays, and shows the rank's frame and no title.
	p = Honors.Choose(q, held, "arena-champion", "arena-champion")
	local noBelt = Without(held, "key", "arena-champion")
	q, earned, lost = Honors.Update(p, noBelt, true)
	eq(q.frame, "arena-champion") eq(q.title, "arena-champion")
	local frame, mark, title = Honors.Shown(q, noBelt)
	eq(frame, "rank") eq(mark, "rank") eq(title, nil)
	eq(#earned, 0)
	eq(Keys(lost, "family"), "belt-A")
	-- Won back later: new again, switches on.
	q, earned = Honors.Update(q, held, true)
	eq(Keys(earned), "arena-champion")
	eq(q.frame, "arena-champion")
end)

test("honours: a gap in the inputs never undoes a pick; a family is forgotten only once its source is loaded", function()
	local held = Honors.Holdings(ME, Everything())
	local p = Honors.Choose(Honors.Update(nil, held, true), held, "donor-top-1", "level-race-60")
	-- A login before the belts, the donors, the level book and the census are in: nothing held yet.
	local q, earned, lost = Honors.Update(p, {}, nil)
	eq(q.frame, "donor-top-1", "the pick is kept") eq(q.title, "level-race-60")
	eq(#earned, 0) eq(#lost, 0, "nothing loaded: nothing forgotten")
	eq(q.seen["donor-top"].place, 1)
	local frame, _, title = Honors.Shown(q, {})
	eq(frame, "rank") eq(title, nil, "shown meanwhile: the rank")
	-- The belts arrive first, then the rest: nothing is new, the pick holds.
	local belts = {}
	for _, h in ipairs(held) do if h.kind == "belt" then belts[#belts + 1] = h end end
	q, earned, lost = Honors.Update(q, belts, { belt = true })
	eq(q.frame, "donor-top-1") eq(#earned, 0) eq(#lost, 0)
	q, earned, lost = Honors.Update(q, held, true)
	eq(q.frame, "donor-top-1") eq(q.title, "level-race-60") eq(#earned, 0) eq(#lost, 0)
	-- The donors loaded, and he is no longer among the top 3: that family is forgotten, the pick stays.
	local noTop = Without(held, "kind", "donor-top")
	q, earned, lost = Honors.Update(q, noTop, { donor = true })
	eq(Keys(lost, "family"), "donor-top")
	eq(q.frame, "donor-top-1")
	eq(Honors.Shown(q, noTop), "rank")
	-- Top donor again: new (it was forgotten), switches on.
	q, earned = Honors.Update(q, held, true)
	eq(Keys(earned), "donor-top-1")
	eq(q.frame, "donor-top-1")
end)

test("honours: 'none' stays none until something new; down a place in a family, a pick of the old place follows it", function()
	local held = Honors.Holdings(ME, Everything())
	local p = Honors.Update(nil, held, true)
	p = Honors.Choose(p, held, "none", "none")
	local q = Honors.Update(p, held, true)
	eq(q.frame, "none") eq(q.title, nil)
	-- 1st of all time down to 2nd, while picked: the pick follows, and nothing counts as new.
	p = Honors.Choose(q, held, "donor-top-1", "donor-top-1")
	local down = Without(held, "key", "donor-top-1")
	down[#down + 1] = { key = "donor-top-2", art = "donor-top-2", kind = "donor-top", family = "donor-top", place = 2,
		frame = "donor-top-2", mark = "donor-top-2", title = "donor-top-2", order = 1 }
	local earned
	q, earned = Honors.Update(p, down, true)
	eq(q.frame, "donor-top-2") eq(q.title, "donor-top-2") eq(#earned, 0)
	-- Down a place while wearing a belt: the belt stays.
	p = Honors.Choose(Honors.Update(nil, held, true), held, "arena-champion", "arena-class-mage")
	q = Honors.Update(p, down, true)
	eq(q.frame, "arena-champion") eq(q.title, "arena-class-mage")
	-- Up a place: new, switches on.
	q, earned = Honors.Update(Honors.Update(q, down, true), held, true)
	eq(Keys(earned), "donor-top-1")
	eq(q.frame, "donor-top-1")
end)

test("honours: Shown checks a pick against the honours held (a viewer never takes it on the player's word)", function()
	local held = Honors.Holdings(ME, Everything())
	local frame, mark, title, h = Honors.Shown({ frame = "arena-class-mage", title = "level-race-60" }, held)
	eq(frame, "arena-class-mage") eq(mark, "mage-gold", "the beast's mark") eq(title, "level-race-60")
	eq(h.key, "arena-class-mage")
	-- A level medallion: the frame names the milestone; the art and the mark its metal's comet.
	frame, mark, title, h = Honors.Shown({ frame = "level-race-60" }, held)
	eq(frame, "level-race-60") eq(mark, "comet-gold") eq(h.art, "comet-gold") eq(h.milestone, 60)
	-- A pick of something he doesn't hold (a forged or stale message): the rank's frame, no title.
	frame, mark, title, h = Honors.Shown({ frame = "arena-race-orc", title = "donor-top-3" }, held)
	eq(frame, "rank") eq(mark, "rank") eq(title, nil) eq(h, nil)
	frame, mark, title = Honors.Shown({ frame = "none", title = "guild-top-leader" }, held)
	eq(frame, "none") eq(mark, "rank", "no frame keeps the rank's mark") eq(title, "guild-top-leader")
	frame, mark, title = Honors.Shown(nil, held)
	eq(frame, "rank") eq(mark, "rank") eq(title, nil)
	frame = Honors.Shown({ frame = "arena-tier-gold" }, held)
	eq(frame, "rank", "the badge is no frame")
end)

---------------------------------------------------------------------------
-- Donors from the Treasury's per-giver sums (the design's Treasury row)
---------------------------------------------------------------------------

test("honours: a giver's sum for one window (the Treasury's per-month and per-week sums) counts there alone; a bad window is no gift", function()
	local w = RESET_0929 + HOUR
	local r = Honors.Donors({
		{ name = "Aldric", money = 40 * GOLD, t = SEP_1 + 20 * DAY, window = "month" },   -- September's sum
		{ name = "Brenna", money = 30 * GOLD, t = RESET_0922 + DAY, window = "week" },     -- week 2959's sum (in September too)
		{ name = "Cedric", money = 90 * GOLD, t = SEP_1 + DAY, window = "all" },           -- his all-time sum
		{ name = "Dunstan", money = 20 * GOLD, t = OCT_1 + HOUR, window = "month" },       -- October's: the race
		{ name = "Esker", money = 99 * GOLD, t = SEP_1 + DAY, window = "year" },           -- no such window
		{ name = "Esker", money = 99 * GOLD, t = SEP_1 + DAY, window = true },
		-- A sum has its dues taken off already: a Treasurer's book or the dues' note change nothing.
		{ name = "Fenwick", money = 5 * GOLD, t = w, window = "week", treasurer = true, noted = true },
		Gift("Gareth", 5, w, { treasurer = true }),                                        -- a line (Sep 29): 1g of dues off
	}, NOW)
	eq(Keys(r.month), "aldric,gareth", "a week's sum is no month's")
	eq(Money(r.month, "gareth"), 4 * GOLD, "a line counts in every window")
	eq(Keys(r.week), "brenna")
	eq(Keys(r.all), "cedric,gareth", "a month's or a week's sum is no all-time sum")
	eq(Money(r.all, "gareth"), 4 * GOLD)
	eq(Keys(r.race.month), "dunstan")
	eq(Money(r.race.week, "fenwick"), 5 * GOLD, "taken as it is")
	eq(Money(r.race.week, "gareth"), 4 * GOLD)
	eq(Find(r.all, "esker"), nil) eq(Find(r.month, "esker"), nil) eq(Find(r.race.month, "esker"), nil)
	-- A week's sum stamped with its week (wk) counts in that week.
	r = Honors.Donors({ { name = "Brenna", money = 30 * GOLD, t = w, wk = 2959, window = "week" } }, NOW)
	eq(Keys(r.week), "brenna")
end)

test("honours: 600 dues and donation lines in one month still rank the month's top 3, and a donor who paid only dues never ranks", function()
	local gifts = {}
	-- 100 members pay 1g of dues with the note, in each of four September weeks: 400 lines.
	for i = 1, 100 do
		for wk = 0, 3 do
			gifts[#gifts + 1] = Gift("Payer" .. i, 1, SEP_1 + 2 * DAY + wk * 7 * DAY + i, { treasurer = true, noted = true })
		end
	end
	-- 200 lines of gifts to another keeper: 100g, 60g, 39g, and one of 38g.
	for i = 1, 100 do gifts[#gifts + 1] = Gift("Aldric", 1, SEP_1 + DAY + i) end
	for i = 1, 60 do gifts[#gifts + 1] = Gift("Brenna", 1, SEP_1 + DAY + 200 + i) end
	for i = 1, 39 do gifts[#gifts + 1] = Gift("Cedric", 1, SEP_1 + DAY + 400 + i) end
	gifts[#gifts + 1] = Gift("Dunstan", 38, SEP_1 + 3 * DAY)
	eq(#gifts, 600)
	local r = Honors.Donors(gifts, NOW)
	eq(Keys(r.month), "aldric,brenna,cedric")
	eq(Money(r.month, "aldric"), 100 * GOLD)
	eq(Keys(r.all), "aldric,brenna,cedric")
	for i = 1, 100 do
		eq(Find(r.all, "payer" .. i), nil, "only dues")
		eq(#Honors.Holdings({ name = "Payer" .. i }, { donors = r }), 0)
	end
	eq(Keys(Honors.Holdings({ name = "Cedric" }, { donors = r })), "donor-top-3,donor-month-3")
	eq(#Honors.Holdings({ name = "Dunstan" }, { donors = r }), 0, "4th")
end)

test("honours: with now, the donors' month list holds only while it is the last one (the week's gives no honour: the design)", function()
	local donors = Honors.Donors({ Gift("Aldric", 50, SEP_1 + DAY), Gift("Kes", 10, RESET_0922 + DAY) }, NOW)
	-- Oct 1 (week 2960): September's and week 2959's lists hold.
	eq(Keys(Honors.Holdings({ name = "Aldric" }, { donors = donors, now = NOW })), "donor-top-1,donor-month-1")
	eq(Keys(Honors.Holdings({ name = "Kes" }, { donors = donors, now = NOW })), "donor-top-2,donor-month-2")
	-- A week later, before the Treasurer's new word: the week's list is stale; September's holds.
	eq(Keys(Honors.Holdings({ name = "Kes" }, { donors = donors, now = NOW + 7 * DAY })), "donor-top-2,donor-month-2")
	-- November: September's is stale too; all time stays.
	eq(Keys(Honors.Holdings({ name = "Aldric" }, { donors = donors, now = OCT_1 + 31 * DAY })), "donor-top-1")
	-- A list without its period can't be checked against now: nothing.
	eq(Keys(Honors.Holdings({ name = "Kes" }, { donors = { month = donors.month, week = donors.week }, now = NOW })), "")
	-- Without now: as given.
	eq(Keys(Honors.Holdings({ name = "Kes" }, { donors = donors })), "donor-top-2,donor-month-2")
end)

---------------------------------------------------------------------------
-- The belts' podium (the design)
---------------------------------------------------------------------------

-- A category's table as ArenaRating.Ranking gives it: best first, keyed by GUID.
local function Table(...)
	local out = {}
	for i, g in ipairs({ ... }) do out[i] = { key = g, rating = 1800 - 10 * i, fights = 20 } end
	return out
end
local TORVIN = { name = "Torvin Hale", guid = "Player-1-H" }
local SELKA = { name = "Selka Drummond", guid = "Player-1-S" }
local WENNA = { name = "Wenna Crale", guid = "Player-1-W" }

test("honours: the podium is the category table's first two eligible fighters other than the belt's holder; a vacant belt still gives both", function()
	local ranking = Table("Player-1-H", "Player-1-S", "Player-1-W", "Player-1-X")
	local p = Honors.Podium("A", ranking, "Player-1-H")
	eq(Keys(p, "guid"), "Player-1-S,Player-1-W")
	eq(Keys(p, "place"), "2,3")
	eq(p[1].cat, "A")
	-- The holder lower in the table (a belt changes hands only in a title fight): still left out.
	p = Honors.Podium("CMA", Table("Player-1-S", "Player-1-W", "Player-1-H"), "Player-1-H")
	eq(Keys(p, "guid"), "Player-1-S,Player-1-W")
	-- Vacant: the table's first two.
	p = Honors.Podium("R4", ranking, nil)
	eq(Keys(p, "guid"), "Player-1-H,Player-1-S")
	-- Contender status is the ledger's to say (fights, a recent one, no debt, not net-off).
	local out = { ["Player-1-S"] = true }
	p = Honors.Podium("A", ranking, "Player-1-H", function(r) return not out[r.key] end)
	eq(Keys(p, "guid"), "Player-1-W,Player-1-X")
	-- Fewer than two: what there is. A level bracket (or anything else) has no belt, so no podium.
	eq(Keys(Honors.Podium("A", Table("Player-1-H", "Player-1-S"), "Player-1-H"), "guid"), "Player-1-S")
	eq(#Honors.Podium("A", {}, nil), 0)
	eq(#Honors.Podium("A", nil, nil), 0)
	eq(#Honors.Podium("B29", ranking, nil), 0)
	eq(#Honors.Podium(nil, ranking, nil), 0)
	-- Malformed rows are skipped and a fighter twice counts once; a row may carry guid and name.
	p = Honors.Podium("A", { "junk", { rating = 1700 }, { guid = "Player-1-S", name = "Selka Drummond" }, { key = "Player-1-S" },
		{ key = "Player-1-W" } }, "Player-1-H")
	eq(Keys(p, "guid"), "Player-1-S,Player-1-W")
	eq(p[1].name, "Selka Drummond") eq(p[2].name, nil)
end)

test("honours: the podium's keys are the belt's with -2 (silver) and -3 (bronze), by GUID, and a belt beats a stale podium word", function()
	local inputs = { belts = { { cat = "A", guid = "Player-1-H", name = "Torvin Hale" } },
		podium = {
			{ cat = "A", place = 2, guid = "Player-1-S", name = "Selka Drummond" },
			{ cat = "A", place = 3, guid = "Player-1-W", name = "Wenna Crale" },
			{ cat = "CMA", place = 2, guid = "Player-1-W", name = "Wenna Crale" },
			{ cat = "R4", place = 3, guid = "Player-1-S", name = "Selka Drummond" },
			{ cat = "B29", place = 2, guid = "Player-1-S", name = "Selka Drummond" },  -- a bracket: no honour
			{ cat = "A", place = 1, guid = "Player-1-X", name = "Lida Fenn" },         -- 1st is the belt's, never a word's
			{ cat = "A", place = 4, guid = "Player-1-X", name = "Lida Fenn" },
			{ cat = "A", place = 2, guid = "Player-1-H", name = "Torvin Hale" },       -- stale: he holds the belt
			"junk",
		} }
	local s = Honors.Holdings(SELKA, inputs)
	eq(Keys(s), "arena-champion-2,arena-race-nightelf-3")
	local h = s[1]
	eq(h.kind, "podium") eq(h.family, "belt-A") eq(h.place, 2) eq(h.cat, "A")
	eq(h.frame, "arena-champion-2") eq(h.mark, "gryphon-silver") eq(h.title, "arena-champion-2") eq(h.art, "gryphon-silver")
	eq(Keys(Honors.Holdings(WENNA, inputs)), "arena-champion-3,arena-class-mage-2")
	eq(Keys(Honors.Holdings(TORVIN, inputs)), "arena-champion", "the belt beats the stale word")
	eq(#Honors.Holdings({ name = "Lida Fenn", guid = "Player-1-X" }, inputs), 0)
	-- A namesake (another character) gets nothing; without GUIDs, the name.
	eq(#Honors.Holdings({ name = "Selka Drummond", guid = "Player-1-Q" }, inputs), 0)
	eq(Keys(Honors.Holdings({ name = "selka drummond" }, { podium = { { cat = "A", place = 3, name = "Selka Drummond" } } })),
		"arena-champion-3")
	-- Two words for one category: the better place, in either order (not the last word heard).
	eq(Keys(Honors.Holdings(SELKA, { podium = { { cat = "A", place = 3, guid = "Player-1-S" },
		{ cat = "A", place = 2, guid = "Player-1-S" } } })), "arena-champion-2")
	eq(Keys(Honors.Holdings(SELKA, { podium = { { cat = "A", place = 2, guid = "Player-1-S" },
		{ cat = "A", place = 3, guid = "Player-1-S" } } })), "arena-champion-2", "silver heard first")
	-- Picked and shown like any frame: its own mark; another category's bronze is not his.
	local frame, mark = Honors.Shown({ frame = "arena-race-nightelf-3" }, s)
	eq(frame, "arena-race-nightelf-3") eq(mark, "nightsaber-bronze", "the bronze nightsaber's mark")
	eq(Honors.Choose(nil, s, "arena-champion-2", "arena-champion-2").frame, "arena-champion-2")
	local bad, why = Honors.Choose(nil, s, "arena-champion-3", nil)
	eq(bad, nil) eq(why, "frame")
end)

test("honours: the 2nd loses his silver when overtaken (his pick follows him to bronze) and the new 2nd's switches on; a vacant belt still gives silver and bronze", function()
	-- The clerk's words: the belt's holder and Podium over the category's table.
	local function Inputs(ranking, holder)
		return { belts = holder and { { cat = "A", guid = holder } } or {}, podium = Honors.Podium("A", ranking, holder) }
	end
	-- Torvin holds the global belt; Selka is 2nd, Wenna 3rd.
	local before = Inputs(Table("Player-1-H", "Player-1-S", "Player-1-W"), "Player-1-H")
	local pickS = Honors.Update(nil, Honors.Holdings(SELKA, before), true)
	local pickW = Honors.Update(nil, Honors.Holdings(WENNA, before), true)
	local pickT = Honors.Update(nil, Honors.Holdings(TORVIN, before), true)
	eq(pickS.frame, "arena-champion-2") eq(pickW.frame, "arena-champion-3") eq(pickT.frame, "arena-champion")
	-- Wenna overtakes Selka in the table.
	local after = Inputs(Table("Player-1-H", "Player-1-W", "Player-1-S"), "Player-1-H")
	local heldS = Honors.Holdings(SELKA, after)
	eq(Keys(heldS), "arena-champion-3", "Selka: bronze now")
	local q, earned, lost = Honors.Update(pickS, heldS, true)
	eq(q.frame, "arena-champion-3", "his pick follows him down") eq(q.title, "arena-champion-3")
	eq(#earned, 0) eq(#lost, 0)
	eq(Honors.Shown({ frame = "arena-champion-2" }, heldS), "rank", "the silver is no longer his")
	q, earned = Honors.Update(pickW, Honors.Holdings(WENNA, after), true)
	eq(Keys(earned), "arena-champion-2") eq(q.frame, "arena-champion-2", "the new silver switches on")
	-- Selka takes the belt from Torvin, who stays 2nd of the table: gold to silver follows too.
	local won = Inputs(Table("Player-1-S", "Player-1-H", "Player-1-W"), "Player-1-S")
	q, earned = Honors.Update(pickT, Honors.Holdings(TORVIN, won), true)
	eq(q.frame, "arena-champion-2") eq(#earned, 0)
	q, earned = Honors.Update(pickS, Honors.Holdings(SELKA, won), true)
	eq(Keys(earned), "arena-champion") eq(q.frame, "arena-champion", "silver to gold: new")
	-- The belt vacated (its holder idle): the table's first two keep silver and bronze.
	local vacant = Inputs(Table("Player-1-S", "Player-1-H", "Player-1-W"), nil)
	eq(Keys(Honors.Holdings(SELKA, vacant)), "arena-champion-2")
	eq(Keys(Honors.Holdings(TORVIN, vacant)), "arena-champion-3")
	eq(#Honors.Holdings(WENNA, vacant), 0)
end)

---------------------------------------------------------------------------
-- The Oracle (the design)
---------------------------------------------------------------------------

local SEP_15 = SEP_1 + 14 * DAY
-- A settled bet on a public market of the live arena, in gold (cur: the currency its market's
-- sheet froze, as the bank's ledger keeps it).
local function Bet(name, market, stake, payout, t, extra)
	local b = { name = name, market = market, stake = stake * GOLD, payout = payout * GOLD, t = t or SEP_15, mode = "L",
		public = true, cur = "g" }
	for k, v in pairs(extra or {}) do b[k] = v end
	return b
end
local function Row(name, profit, staked, markets, first)
	return { name = name, profit = profit, staked = staked, markets = markets, first = first }
end
-- The Oracle's top alone (Oracle returns the top and the whole ranking).
local function Top(rows) return (Honors.Oracle(rows)) end

test("honours: a bank's Oracle rows: profit and stake over the month's settled public markets of the live arena, each market once", function()
	local month = Honors.MonthOf(SEP_15)
	local bets = {
		Bet("Lida Fenn", "m1", 10, 19, SEP_15, { at = SEP_15 - 600 }),       -- won: +9
		Bet("Lida Fenn", "m1", 5, 0, SEP_15, { at = SEP_15 - 300 }),         -- a second bet on m1: -5, one market still
		Bet("Lida Fenn", "m2", 20, 0, SEP_15 + DAY, { at = SEP_15 - 900 }),  -- lost: -20; her first bet
		Bet("Parric Stowe", 7, 10, 30, SEP_15),                              -- a market id may be a number; at: t
		-- Left out:
		Bet("Lida Fenn", "m3", 10, 50, SEP_15, { mode = "T" }),              -- a rehearsal's
		Bet("Lida Fenn", "m4", 10, 50, SEP_15),                              -- (no mode: below)
		Bet("Lida Fenn", "m5", 10, 50, SEP_15, { public = false }),          -- a 1v1 stake
		Bet("Lida Fenn", "m6", 10, 50, SEP_15, { public = "yes" }),
		Bet("Lida Fenn", "m7", 10, 10, SEP_15, { void = true }),             -- refunded
		Bet("Lida Fenn", "m8", 10, 50, SEP_15, { cur = "p" }),               -- glory points
		Bet("Lida Fenn", "m9", 10, 50, SEP_1 - 1),                           -- August
		Bet("Lida Fenn", "m10", 10, 50, OCT_1),                              -- October
		Bet("Lida Fenn", "", 10, 50), Bet("Lida Fenn", nil, 10, 50),
		Bet("Lida Fenn", "m11", 0, 0), Bet("Lida Fenn", "m12", 1, 0, SEP_15, { stake = 10.5 }), Bet("Lida Fenn", "m13", 1, -1),
		Bet("Lida Fenn", "m14", 10, 50, SEP_15, { t = "soon" }), Bet("Lida Fenn", "m15", 10, 50, SEP_15, { at = "soon" }),
		Bet(nil, "m16", 10, 50), "junk", 42,
	}
	bets[6].mode = nil
	local G = { cur = "g" }
	local rows = Honors.OracleScores(bets, month, G)
	eq(Keys(rows), "lida fenn,parric stowe")
	eq(rows[1].profit, (9 - 5 - 20) * GOLD) eq(rows[1].staked, 35 * GOLD) eq(rows[1].markets, 2)
	eq(rows[1].first, SEP_15 - 900) eq(rows[1].name, "Lida Fenn")
	eq(rows[2].profit, 20 * GOLD) eq(rows[2].markets, 1) eq(rows[2].first, SEP_15)
	-- A rehearsal scores its own (mode T); a realm on glory points, in points.
	eq(Keys(Honors.OracleScores(bets, month, { mode = "T", cur = "g" })), "lida fenn")
	eq(Honors.OracleScores(bets, month, { cur = "p" })[1].profit, 40 * GOLD)
	-- The realm's clock: 03:00 UTC on Oct 1 is still September seven hours behind.
	local late = { Bet("Wenna Crale", "m1", 1, 2, OCT_1 + 3 * HOUR) }
	eq(Keys(Honors.OracleScores(late, month, { offset = -7 * HOUR, cur = "g" })), "wenna crale")
	eq(#Honors.OracleScores(late, month, G), 0)
	eq(#Honors.OracleScores(bets, nil, G), 0)
end)

test("honours: the Oracle ranks by profit over stake, exactly; ties by more markets, then the earlier first bet; ten markets at least", function()
	local top, ranked = Honors.Oracle({
		Row("Lida Fenn", 50, 100, 10, 5),       -- +50%
		Row("Parric Stowe", 30, 100, 12, 1),    -- +30%
		Row("Wenna Crale", 60, 200, 10, 2),     -- +30%, fewer markets than Parric
		Row("Oswin Marrow", 3, 10, 10, 3),      -- +30%, as many markets as Wenna, a later first bet
		Row("Selka Drummond", 90, 100, 9, 1),   -- +90% on 9 markets: not ranked
		Row("Torvin Hale", -10, 100, 40, 1),    -- lost money: ranked, last
	})
	eq(Keys(top), "lida fenn,parric stowe,wenna crale")
	eq(Keys(top, "place"), "1,2,3")
	eq(top[1].profit, 50) eq(top[1].staked, 100) eq(top[1].markets, 10) eq(top[1].first, 5) eq(top[1].name, "Lida Fenn")
	eq(Keys(ranked), "lida fenn,parric stowe,wenna crale,oswin marrow,torvin hale")
	eq(Keys(ranked, "place"), "1,2,3,4,5")
	eq(Find(ranked, "selka drummond"), nil, "9 markets")
	eq(#Honors.Oracle({ Row("Selka Drummond", 90, 100, Honors.ORACLE_MIN_MARKETS - 1, 1) }), 0)
	eq(Keys(Top({ Row("Selka Drummond", 90, 100, Honors.ORACLE_MIN_MARKETS, 1) })), "selka drummond")
	-- Two ratios a float can't tell apart (Fibonacci's: 1836311903/1134903170 and
	-- 1134903170/701408733 differ by 1/(1134903170 x 701408733), and the cross products pass
	-- 2^53): compared exactly, the second is higher. A float would call it a tie and give it to
	-- the one with more markets.
	local F44, F45, F46 = 701408733, 1134903170, 1836311903
	eq(F46 / F45 == F45 / F44, true, "a float ties them")
	eq(F46 * F44 == F45 * F45, true, "so do the float cross products")
	eq(Keys(Top({ Row("Lida Fenn", F46, F45, 30, 1), Row("Parric Stowe", F45, F44, 10, 1) })), "parric stowe,lida fenn")
	-- Below zero: 701408733/1134903170 < 1134903170/1836311903, so the first loses less.
	eq(-F44 / F45 == -F45 / F46, true, "a float ties these too")
	eq(Keys(Top({ Row("Lida Fenn", -F44, F45, 10, 1), Row("Parric Stowe", -F45, F46, 30, 1) })), "lida fenn,parric stowe",
		"below zero")
	-- Equal ratios in other terms tie: more markets, then the earlier first bet, then the name.
	eq(Keys(Top({ Row("Lida Fenn", 1, 3, 10, 9), Row("Parric Stowe", 2, 6, 10, 9) })), "lida fenn,parric stowe")
	eq(Keys(Top({ Row("Parric Stowe", 1, 3, 10, 9), Row("Lida Fenn", 2, 6, 11, 9) })), "lida fenn,parric stowe")
	-- Without a first bet's time: after one with it.
	eq(Keys(Top({ Row("Oswin Marrow", 1, 10, 10), Row("Parric Stowe", 1, 10, 10, 99) })), "parric stowe,oswin marrow")
	-- Each bank's rows add up (each market was held by one bank): 6 + 4 markets reach the minimum.
	top = Honors.Oracle({ Row("Lida Fenn", 10, 100, 6, 50), Row("Parric Stowe", 5, 100, 10, 1), Row("lida fenn", 30, 100, 4, 20) })
	eq(Keys(top), "lida fenn,parric stowe")
	eq(top[1].profit, 40) eq(top[1].staked, 200) eq(top[1].markets, 10) eq(top[1].first, 20)
	-- The 4th has nothing; malformed rows are left out.
	top, ranked = Honors.Oracle({ Row("A1", 4, 10, 10), Row("A2", 3, 10, 10), Row("A3", 2, 10, 10), Row("A4", 1, 10, 10),
		Row("Bad1", -11, 10, 10), Row("Bad2", 1, 0, 10), Row("Bad3", 1, 10, 10.5), Row("Bad4", 1, 10, 10, "x"),
		Row("Bad5", 0.5, 10, 10), Row(nil, 1, 10, 10), "junk", 42 })
	eq(Keys(top), "a1,a2,a3") eq(Keys(ranked), "a1,a2,a3,a4")
	eq(#Honors.Oracle(nil), 0)
	-- From a bank's ledger: ten markets make the minimum, nine do not.
	local bets = {}
	for i = 1, 10 do bets[#bets + 1] = Bet("Lida Fenn", "m" .. i, 10, i <= 6 and 20 or 0, SEP_15 + i) end
	for i = 1, 9 do bets[#bets + 1] = Bet("Parric Stowe", "m" .. i, 10, 30, SEP_15 + i) end
	top = Honors.Oracle(Honors.OracleScores(bets, Honors.MonthOf(SEP_15), { cur = "g" }))
	eq(Keys(top), "lida fenn") eq(top[1].profit, 20 * GOLD) eq(top[1].staked, 100 * GOLD)
end)

test("honours: on equal ratios, more markets come before the earlier first bet", function()
	-- The two rules disagree: Parric has more markets, Lida the earlier first bet (and the first key).
	local top = Top({ Row("Lida Fenn", 1, 10, 10, 1), Row("Parric Stowe", 1, 10, 11, 9) })
	eq(Keys(top), "parric stowe,lida fenn")
	-- Markets equal: the earlier first bet, against the key's order.
	eq(Keys(Top({ Row("Lida Fenn", 1, 10, 10, 9), Row("Parric Stowe", 1, 10, 10, 1) })), "parric stowe,lida fenn")
end)

test("honours: a bet counts in the month its market settled, not the month it was placed", function()
	-- Placed on Aug 31, on a market settled on Sep 1.
	local bets = { Bet("Lida Fenn", "m1", 10, 20, SEP_1 + HOUR, { at = SEP_1 - HOUR }) }
	local sept = Honors.OracleScores(bets, Honors.MonthOf(SEP_1), { cur = "g" })
	eq(Keys(sept), "lida fenn") eq(sept[1].markets, 1) eq(sept[1].first, SEP_1 - HOUR)
	eq(#Honors.OracleScores(bets, Honors.MonthOf(SEP_1 - HOUR), { cur = "g" }), 0, "not August")
end)

test("honours: the Oracle scores the currency the caller names: none without it, and gold, points and chips never add up", function()
	local month = Honors.MonthOf(SEP_15)
	local bets = {}
	for i = 1, 10 do
		bets[#bets + 1] = Bet("Lida Fenn", "g" .. i, 10, 20, SEP_15 + i)                     -- gold: +10 g each
		bets[#bets + 1] = Bet("Lida Fenn", "p" .. i, 10, 0, SEP_15 + i, { cur = "p" })       -- points: all lost
		bets[#bets + 1] = Bet("Parric Stowe", "c" .. i, 10, 30, SEP_15 + i, { mode = "T", cur = "c" }) -- chips
	end
	-- A bet without its currency counts for nothing.
	local bare = Bet("Wenna Crale", "g1", 10, 20, SEP_15)
	bare.cur = nil
	bets[#bets + 1] = bare
	-- No currency named: no rows (nothing defaults to gold).
	eq(#Honors.OracleScores(bets, month), 0)
	eq(#Honors.OracleScores(bets, month, {}), 0)
	eq(#Honors.OracleScores(bets, month, { cur = "" }), 0)
	eq(#Honors.OracleScores(bets, month, { cur = 1 }), 0)
	-- Each currency alone; a bet without one counts for nothing.
	local g = Honors.OracleScores(bets, month, { cur = "g", bank = "Coffer Vane" })
	eq(Keys(g), "lida fenn") eq(g[1].profit, 100 * GOLD) eq(g[1].markets, 10) eq(g[1].cur, "g") eq(g[1].bank, "Coffer Vane")
	local p = Honors.OracleScores(bets, month, { cur = "p" })
	eq(Keys(p), "lida fenn") eq(p[1].profit, -100 * GOLD) eq(p[1].cur, "p") eq(p[1].bank, nil)
	-- A glory-points realm and a chips rehearsal score their own (in-game check H08 runs on T).
	eq(Keys(Top(p)), "lida fenn")
	local c = Honors.OracleScores(bets, month, { mode = "T", cur = "c" })
	eq(Keys(c), "parric stowe") eq(Keys(Top(c)), "parric stowe")
	eq(#Honors.OracleScores(bets, month, { mode = "T", cur = "g" }), 0, "the rehearsal ran on chips")
	-- A month that switched currency: its rows never add up. Named, one currency ranks alone.
	local both = {}
	for _, r in ipairs(g) do both[#both + 1] = r end
	for _, r in ipairs(p) do both[#both + 1] = r end
	local top, ranked = Honors.Oracle(both)
	eq(#top, 0) eq(#ranked, 0)
	top, ranked = Honors.Oracle(both, { cur = "p" })
	eq(Keys(top), "lida fenn") eq(top[1].profit, -100 * GOLD) eq(top[1].markets, 10) eq(ranked[1].cur, "p")
	top = Honors.Oracle(both, { cur = "g" })
	eq(top[1].profit, 100 * GOLD) eq(top[1].markets, 10)
	-- Five gold markets and five in points are not ten.
	eq(#Top({ Row("Lida Fenn", 5, 10, 5, 1), { name = "Lida Fenn", profit = 5, staked = 10, markets = 5, first = 1, cur = "p" } }), 0)
	-- A row without a currency (a whisper that carries none) is taken as the one named; a bad one is no row.
	top = Honors.Oracle({ Row("Lida Fenn", 5, 10, 6, 1), { name = "Lida Fenn", profit = 5, staked = 10, markets = 4, first = 1,
		cur = "g" } }, { cur = "g" })
	eq(Keys(top), "lida fenn") eq(top[1].markets, 10)
	eq(#Top({ { name = "Lida Fenn", profit = 5, staked = 10, markets = 10, first = 1, cur = "" } }), 0)
	eq(#Top({ { name = "Lida Fenn", profit = 5, staked = 10, markets = 10, first = 1, cur = 7 } }), 0)
end)

test("honours: a bank's rows heard twice count once; its later row replaces the earlier", function()
	local function From(bank, name, profit, markets)
		return { name = name, profit = profit, staked = 100, markets = markets, first = 1, bank = bank }
	end
	-- Bank A's whisper heard twice: 5 markets, not 10.
	eq(#Top({ From("Coffer Vane", "Lida Fenn", 10, 5), From("Coffer Vane", "Lida Fenn", 10, 5) }), 0)
	-- Two banks: they add up.
	local top = Top({ From("Coffer Vane", "Lida Fenn", 10, 5), From("Strongbox Hale", "Lida Fenn", 20, 5) })
	eq(Keys(top), "lida fenn") eq(top[1].profit, 30) eq(top[1].staked, 200) eq(top[1].markets, 10)
	-- A bank's resend replaces what it said before (any case of its name); other bettors' rows stay.
	top = Top({ From("Coffer Vane", "Lida Fenn", 10, 5), From("Coffer Vane", "Parric Stowe", 1, 10),
		From("Strongbox Hale", "Lida Fenn", 20, 5), From("coffer vane", "Lida Fenn", 40, 6) })
	eq(Keys(top), "lida fenn,parric stowe") eq(top[1].profit, 60) eq(top[1].markets, 11)
	-- Under a named currency, a resend that names it replaces one that did not.
	local named = From("Coffer Vane", "Lida Fenn", 10, 5)
	named.cur = "g"
	eq(#Honors.Oracle({ From("Coffer Vane", "Lida Fenn", 10, 5), named }, { cur = "g" }), 0)
	-- A bad bank is no row.
	eq(#Top({ From("", "Lida Fenn", 10, 10) }), 0)
	eq(#Top({ From(42, "Lida Fenn", 10, 10) }), 0)
	-- From the ledger: one bank's rows, heard twice, count once.
	local bets = {}
	for i = 1, 5 do bets[#bets + 1] = Bet("Lida Fenn", "m" .. i, 10, 20, SEP_15 + i) end
	local rows = Honors.OracleScores(bets, Honors.MonthOf(SEP_15), { cur = "g", bank = "Coffer Vane" })
	local twice = { rows[1], rows[1] }
	eq(#Top(twice), 0, "5 markets, heard twice")
end)

test("honours: the Oracle's ravens are held through the month after the one scored, then dropped", function()
	local sept = Honors.MonthOf(SEP_15)
	local top = Honors.Oracle({ Row("Lida Fenn", 5, 10, 10, 1), Row("Parric Stowe", 4, 10, 10, 1), Row("Wenna Crale", 3, 10, 10, 1),
		Row("Oswin Marrow", 2, 10, 10, 1) })
	local oracle = { month = top, monthNo = sept }
	eq(Keys(Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle })), "oracle-1")
	eq(Keys(Honors.Holdings({ name = "Parric Stowe" }, { oracle = oracle })), "oracle-2")
	local h = Honors.Holdings({ name = "Wenna Crale" }, { oracle = oracle })[1]
	eq(h.key, "oracle-3") eq(h.art, "raven-bronze") eq(h.frame, "oracle-3") eq(h.mark, "raven-bronze") eq(h.title, "oracle-3")
	eq(h.kind, "oracle") eq(h.family, "oracle") eq(h.place, 3) eq(h.period, sept)
	eq(#Honors.Holdings({ name = "Oswin Marrow" }, { oracle = oracle }), 0, "4th: nothing")
	-- The bank's word carries names and places only.
	eq(Keys(Honors.Holdings({ name = "Lida Fenn" }, { oracle = { month = { { name = "Lida Fenn", place = 1 } }, monthNo = sept } })),
		"oracle-1")
	-- October, the month after: held. November: gone. September, the month being scored: not yet.
	eq(Keys(Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle, now = NOW })), "oracle-1")
	eq(#Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle, now = OCT_1 + 31 * DAY }), 0, "the month after that")
	eq(#Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle, now = SEP_15 }), 0, "the month being scored")
	eq(#Honors.Holdings({ name = "Lida Fenn" }, { oracle = { month = top }, now = NOW }), 0, "a word without its month")
	-- The realm's clock: at 03:00 UTC on Nov 1, a realm seven hours behind is still in October.
	eq(Keys(Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle, now = OCT_1 + 31 * DAY + 3 * HOUR, offset = -7 * HOUR })),
		"oracle-1")
	-- Picked, then dropped: forgotten once the Oracle's word is in, kept while it is not.
	local held = Honors.Holdings({ name = "Lida Fenn" }, { oracle = oracle })
	local p = Honors.Update(nil, held, true)
	eq(p.frame, "oracle-1") eq(p.title, "oracle-1")
	local _, _, lost = Honors.Update(p, {}, { donor = true })
	eq(#lost, 0, "the Oracle's source not loaded")
	_, _, lost = Honors.Update(p, {}, { oracle = true })
	eq(Keys(lost, "family"), "oracle")
end)

---------------------------------------------------------------------------
-- The best guild's members; the order; a locked pick
---------------------------------------------------------------------------

-- (the design: no members' title for the best guild, only its leader's owl. This test was the
-- members' title's and now expects nothing for them.)
test("honours: the best guild's leader holds its owl (frame and title); its members and another guild's hold nothing", function()
	local inputs = { guild = Honors.GuildTop({ { guild = "Olympus Aurora", leader = "Maelis", members = 100, avgLevel = 40 } }) }
	eq(#Honors.Holdings({ name = "Lida Fenn", guild = "Olympus Aurora" }, inputs), 0, "a member: nothing")
	eq(#Honors.Holdings({ name = "Lida Fenn", guild = "  olympus AURORA " }, inputs), 0)
	eq(#Honors.Holdings({ name = "Lida Fenn", guild = "Olympus Dawn" }, inputs), 0)
	eq(Keys(Honors.Holdings({ name = "Maelis", guild = "Olympus Aurora" }, inputs)), "guild-top-leader", "the leader: his owl")
	eq(Keys(Honors.Holdings({ name = "Maelis" }, inputs)), "guild-top-leader", "his guild unknown: the census's word")
	eq(#Honors.Holdings({ name = "Maelis", guild = "Olympus Dawn" }, inputs), 0, "gone to another guild: nothing")
	local lead = Honors.Holdings({ name = "Maelis", guild = "Olympus Aurora" }, inputs)
	eq(lead[1].frame, "guild-top-leader") eq(lead[1].title, "guild-top-leader") eq(lead[1].art, "owl-gold")
	-- He steps down: the owl is no longer his; his pick stays and shows the rank meanwhile.
	local q = Honors.Update(nil, lead, true)
	eq(q.frame, "guild-top-leader")
	local held = Honors.Holdings({ name = "Maelis", guild = "Olympus Aurora" },
		{ guild = Honors.GuildTop({ { guild = "Olympus Aurora", leader = "Tovan", members = 100, avgLevel = 40 } }) })
	local earned, lost
	q, earned, lost = Honors.Update(q, held, true)
	eq(#earned, 0) eq(Keys(lost, "family"), "guild")
	eq(Honors.Shown(q, held), "rank")
end)

test("honours: ORDER: belts, their podium, the guild's plaque, donors of all time, the level race, the Oracle, the month's donors, the tier", function()
	local donors = Honors.Donors({ Gift("Aldric", 50, SEP_1 + DAY), Gift("Aldric", 5, RESET_0922 + DAY) }, NOW)
	local inputs = {
		belts = { { cat = "R4", guid = "Player-1-A" } },
		podium = { { cat = "CMA", place = 3, guid = "Player-1-A" }, { cat = "A", place = 2, guid = "Player-1-A" } },
		tiers = { ["Player-1-A"] = "silver" },
		donors = donors,
		levels = Honors.LevelRace({}, { Up("Aldric", "Player-1-A", 20, 100, true, 19) }, 100000),
		oracle = { month = { { name = "Aldric", place = 2 } }, monthNo = donors.monthNo },
		guild = { guild = "Olympus Aurora", leader = "Maelis" },
	}
	local held = Honors.Holdings({ name = "Aldric", guid = "Player-1-A", guild = "Olympus Aurora" }, inputs)
	eq(Keys(held), "arena-race-nightelf,arena-champion-2,arena-class-mage-3,donor-top-1,level-race-20,oracle-2,"
		.. "donor-month-1,arena-tier-silver")
	-- All earned at once on a new profile: the first frame and the first title by ORDER.
	local p = Honors.Update(nil, held, true)
	eq(p.frame, "arena-race-nightelf") eq(p.title, "arena-race-nightelf")
end)

test("honours: a locked pick stays as the player set it when something new is earned; Choose and Update keep the lock", function()
	local held = Honors.Holdings(ME, Everything())
	local fewer = Without(held, "key", "donor-month-1")
	local p = Honors.Choose(nil, fewer, "donor-top-1", "level-race-60")
	p.locked = true
	local q, earned = Honors.Update(p, held, true)
	eq(Keys(earned), "donor-month-1", "still reported as new")
	eq(q.frame, "donor-top-1") eq(q.title, "level-race-60")
	eq(q.locked, true)
	eq(Honors.Choose(q, held, "rank", nil).locked, true, "Choose keeps it")
	-- A place down still moves a locked pick along: the same honour, not a new one.
	local silver = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 2, guid = "Player-1-S" } } })
	local bronze = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 3, guid = "Player-1-S" } } })
	local s = Honors.Choose(nil, silver, "arena-champion-2", "arena-champion-2")
	s.locked = true
	eq(Honors.Update(s, bronze, true).frame, "arena-champion-3")
	-- Anything but true is no lock.
	local r = Honors.Update({ frame = "rank", locked = "yes" }, held, true)
	eq(r.locked, nil) eq(r.frame, "arena-champion")
end)

test("honours: a locked pick follows its honour a place up too (bronze to silver to the belt)", function()
	-- The clerk's words for Selka: bronze, then silver, then the belt.
	local bronze = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 3, guid = "Player-1-S" } } })
	local silver = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 2, guid = "Player-1-S" } } })
	local belt = Honors.Holdings(SELKA, { belts = { { cat = "A", guid = "Player-1-S" } } })
	local p = Honors.Choose(nil, bronze, "arena-champion-3", "arena-champion-3")
	p.locked = true
	local q, earned = Honors.Update(p, silver, true)
	eq(Keys(earned), "arena-champion-2", "still new")
	eq(q.frame, "arena-champion-2") eq(q.title, "arena-champion-2") eq(q.locked, true)
	local frame, mark, title = Honors.Shown(q, silver)
	eq(frame, "arena-champion-2") eq(mark, "gryphon-silver") eq(title, "arena-champion-2")
	q = Honors.Update(q, belt, true)
	eq(q.frame, "arena-champion") eq(q.title, "arena-champion")
	eq(Honors.Shown(q, belt), "arena-champion")
	-- A locked pick of something else stays: only the old place's pick follows.
	local both = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 3, guid = "Player-1-S" } },
		belts = { { cat = "R4", guid = "Player-1-S" } } })
	local r = Honors.Choose(nil, both, "arena-race-nightelf", "arena-champion-3")
	r.locked = true
	local up = Honors.Holdings(SELKA, { podium = { { cat = "A", place = 2, guid = "Player-1-S" } },
		belts = { { cat = "R4", guid = "Player-1-S" } } })
	q = Honors.Update(r, up, true)
	eq(q.frame, "arena-race-nightelf", "his frame stays") eq(q.title, "arena-champion-2", "his title follows")
end)

test("honours: the game's GUID and the arena's short one (gk) are one character: belts, podium, tiers and level places", function()
	local FULL, GK = "Player-4395-0A1B2C3D", "4395-0A1B2C3D"
	local lida = { name = "Lida Fenn", guid = FULL }
	local inputs = {
		belts = { { cat = "CMA", guid = GK } },
		podium = { { cat = "A", place = 2, guid = "4395-0a1b2c3d" } },  -- hex in any case
		tiers = { [GK] = "silver" },
		levels = { [60] = { { guid = GK, name = "Lida Fenn", t = 1 } } },
	}
	eq(Keys(Honors.Holdings(lida, inputs)), "arena-class-mage,arena-champion-2,level-race-60,arena-tier-silver")
	eq(Keys(Honors.Holdings({ name = "Lida Fenn", guid = GK }, inputs)),
		"arena-class-mage,arena-champion-2,level-race-60,arena-tier-silver", "the short form on both sides")
	-- The words in the game's form and the player in the short one. (tiers is a map, looked up by
	-- the short form, then as the player's GUID is given: keyed by gk, as ArenaLedger.Tier's.)
	local full = { belts = { { cat = "CMA", guid = FULL } }, tiers = { [FULL] = "gold" } }
	eq(Keys(Honors.Holdings({ name = "Lida Fenn", guid = GK }, full)), "arena-class-mage")
	eq(Keys(Honors.Holdings(lida, full)), "arena-class-mage,arena-tier-gold", "tiers keyed as the player's GUID")
	-- Another character (a namesake) gets nothing; another server's the same.
	eq(#Honors.Holdings({ name = "Lida Fenn", guid = "Player-4395-0A1B2C3E" }, inputs), 0)
	eq(#Honors.Holdings({ name = "Lida Fenn", guid = "Player-4396-0A1B2C3D" }, inputs), 0)
	-- The podium leaves out the holder in either form, and returns each guid as the table gave it.
	local p = Honors.Podium("A", { { key = FULL }, { key = "Player-4395-0000000B" }, { key = "4395-0000000b" },
		{ key = "Player-4395-0000000C" } }, GK)
	eq(Keys(p, "guid"), "Player-4395-0000000B,Player-4395-0000000C", "the holder left out, a fighter twice once")
	-- The level race: a place recorded by gk is the same character's claim in the game's form.
	local book, fresh = Honors.LevelRace({ [40] = { { guid = GK, name = "Lida Fenn", t = 1 } } }, {
		Up("Lida Fenn", FULL, 40, 500, true),
		Up("Parric Stowe", "Player-4395-0000000B", 60, 600, true),
	}, 100000)
	eq(Keys(book[40], "name"), "Lida Fenn", "his own claim again: nothing new")
	eq(book[40][1].guid, GK, "kept as given")
	eq(#fresh, 1) eq(fresh[1].name, "Parric Stowe") eq(fresh[1].milestone, 60)
	-- ...and the other way round: a place recorded in the game's form, a claim by gk (any case).
	book, fresh = Honors.LevelRace({ [20] = { { guid = FULL, name = "Lida Fenn", t = 1 } } },
		{ Up("Lida Fenn", "4395-0a1b2c3d", 20, 500, true) }, 100000)
	eq(Keys(book[20], "name"), "Lida Fenn") eq(book[20][1].guid, FULL) eq(#fresh, 0)
end)
