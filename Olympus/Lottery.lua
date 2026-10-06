local ADDON, ns = ...

-- 1.2, the Blood Arena: Lottery.lua. A stub the arena's core created for the Lottery's package (the design) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The Menagerie Lottery ("Lottery" in the betting window, the full name once it is open): a daily
-- pari-mutuel market with 25 outcomes, the beasts, and no house (the bank never risks its own
-- gold). Stakes come from the one wallet. Bets close at the draw time the King sets.
--
-- The draw: five public server rolls, /roll 1-10000 (10000 reads 0000; a typed /roll 0-9999 counts
-- the same), by the King or by the lottery's bank, read from the server's roll lines of that
-- character with that range. Each prize is a four-digit number and its beast, the group of its
-- last two digits (01-04 = 1 ... 97-00 = 25). A ticket whose beast appears gets its stake back
-- once. The remaining profit is split into 50%, 25%, 15% and 10% tranches for positions 1-4;
-- fifth place is refund-only. A repeated beast may claim several tranches without receiving a
-- second refund. Six percent is charged once on the aggregate gross profit actually claimed, and
-- an unclaimed tranche remains in the source ledger for a later compatible day.
--
-- Who writes what (one writer per object, the design). A day needs no message type of its
-- own: it is a market sheet (Markets, the markets) with an eid from Arena.NewId("L") and one market, type
-- "LO", 25 outcomes. The lottery's one type, LW, is a settled day's winners from its bank (the
-- Games tab's rankings, below).
--   - The King's client is the lottery's caller: it opens each day (Markets.Open; the sheet's lockAt
--     is the draw time he set, so the schedule travels in the sheets), reads the five rolls (his
--     own, or the bank's when he lets the bank roll: the bank /rolls in his group, where his client
--     sees its lines) and declares them (Markets.DeclareDraw) within the hour after the draw time
--     (else the day is void, every stake back), then opens the next day once the bank has settled
--     it (its client on: the winners are paid by the next day) or it is void, carrying only
--     unclaimed profit. The draw time is 21:00 on the draw's clock (US Central, Lottery.Zone). The
--     King is a public arbiter, so the sheet passes the markets' rule for public sheets as it is. In
--     a rehearsal (T) a King's stand-in calls it.
--   - The sheet's bank is the lottery's bank: the first open bank of this realm by sorted name
--     (Lottery.Bank), deterministic on every client. It takes the slips, holds the stakes in the
--     wallet and settles with Lottery.Settle (the one formula here, over ArenaMath.Settle).
--   - Every other client reads the day from Markets.View and says the result once (the chat line
--     here; the King's overlay reads Lottery.OverlayView and the LOTTERY_DRAW / LOTTERY_RESULT events).
-- What this asks of the markets (the markets) and the wallet (the money part), for the integrator (the tests use a
-- stand-in with exactly this shape, tests/arena/lib/lottery-markets.lua):
--   Markets.OpenLottery(eid, { drawAt, bank, cur, mode, carry = { from, copper } | nil }) opens
--     one LO market whose immutable param explicitly names settlement version 2. The bank checks
--     a carry against the settled source book and Wallet.Carry moves that retained profit once.
--   Markets.DeclareDraw(eid, { n1, n2, n3, n4, n5 }) writes all five prizes. The bank settles it
--     with Lottery.Settle({ version = 2, tickets, draw, carry, feeBp = 600 }).
--   Markets.View(eid) -> { lockAt, bank, cur, fee, mode, carry = { from, copper },
--     markets = { { idx = 1, type = "LO", state = O|L|R|S|V|H, result, param,
--     outcomes = { { o, pool (copper), count } } } } }; Markets.Public() -> the public eids (or
--     tables with .eid); Markets.Bet(eid, 1, beast, silver) -> ticket; Markets.Tickets({ eid }) ->
--     this character's { o, stake (copper) or silver, state }; Markets.Void(eid, 1, code); Markets.Has(eid).
--   The bank refuses a slip from Arena.EventOf(eid).excluded (the caller and the bank, and their
--     alts): the markets' anti-fix check 11.
-- API (for the companion's LotteryBoard.lua and the screens' overlay):
--   Lottery.BEASTS: the 25 in the classic order, each { n, key, name, art, icon }
--   Lottery.BeastOf(n): the beast (1-25) of a four-digit number (0-9999; 10000 reads 0000)
--   Lottery.Milhar(n), Lottery.Text(n), Lottery.Dezenas(beast), Lottery.ResultText(prizes),
--     Lottery.ReadResult(text), Lottery.Settle(contract), Lottery.PayoutOf(...),
--     Lottery.Preview(day, beast, silver) (the illustration before a bet), Lottery.NextDraw(now, at,
--     offset, ahead), Lottery.DrawAt(now, at, ahead), Lottery.Zone(), Lottery.ClockText(t, offset),
--     Lottery.WhenText(t), Lottery.Remind(eid, mark) (a reminder, as its timer says it)
--   Lottery.Today() -> { eid, drawAt, pool, rollover (the pot rolled in), pot, bets = { [beast] =
--     { pool, count } }, prizes, head, state, mine, myPayout, ... }
--   Lottery.Bet(beast, silver) -> ticket (through Markets.Bet); Lottery.Draw() (the King's or the
--     bank's roll, one prize a click); Lottery.FirstUse() (the full name and the explanation, once:
--     not a King's letter); Lottery.Intro(); Lottery.SetSchedule{ on, at, roller }; Lottery.Open()
--   Actions: lottery.open, lottery.bet, lottery.draw, lottery.schedule. /oly arena lottery.
-- Behind the King's gold switch: gold only with the live switch on in gold (Roles.Live, Currency)
-- on a client whose saved data persists; points with the switch on in points; a rehearsal (T)
-- otherwise, the beta included. Off until the King sets a draw time.
-- The weight rule: an idle client holds only the events registry, its actions and its ns.On
-- callbacks (the result said once; a bank's winners, nothing elsewhere), and, while it knows a day
-- that takes bets, one C_Timer.NewTimer for that day's next reminder; the caller's client is
-- involved (one Arena.Every) while his lottery is on; the roll lines are read (CHAT_MSG_SYSTEM,
-- registered on first use) only while a draw is due here.

local L = ns.L
local Arena = ns.Arena

local Lottery = {}
ns.Lottery = Lottery

local floor, max = math.floor, math.max

Lottery.OUTCOMES = 25
Lottery.PRIZES = 5
Lottery.IDX = 1                -- the day's one market, on its sheet
Lottery.TYPE = "LO"            -- its type (Markets, the markets)
Lottery.ROLL = { 1, 10000 }    -- the Roll button's /roll
Lottery.TICK = 15              -- the caller's cycle, while his lottery is on
Lottery.ROLL_WAIT = 6          -- seconds after the button before "type /roll 10000"
Lottery.EXTRA_FOR = 600        -- a roll after the five is told as extra this long after the draw's end
Lottery.FRESH = 12 * 3600      -- a result is said in the chat at most this long after its draw time
Lottery.HEARD_MAX = 10         -- results said, remembered across a login (not said twice)
Lottery.HISTORY_MAX = 7        -- past draws the caller keeps
Lottery.INTRO = 2              -- the first-use explanation's version (v2 five-place rules)
Lottery.DEFAULT_AT = 21 * 60   -- the draw time a new schedule starts from (the draw's clock, minutes: 21:00 US Central)
Lottery.FIXED_OFFSET = -300    -- the draw's clock on a realm not on US Central: a fixed UTC-5, in minutes
Lottery.DRAW_WINDOW = 3600     -- a day not drawn this long after its draw time is void, every stake back
Lottery.VOID_SLACK = 300       -- ...and the bank voids it this much later (a declaration made at the hour's end reaches it)
Lottery.REMIND = { 3600, 900, 300 } -- the reminders before a draw, in seconds (60, 15 and 5 minutes)

Lottery.SETTLEMENT_VERSION = 2
Lottery.CONTRACT_VERSION = Lottery.SETTLEMENT_VERSION
Lottery.WIRE_PREFIX = "L2"
Lottery.DEFAULT_FEE_BP = 600
Lottery.FEE_BP = Lottery.DEFAULT_FEE_BP
Lottery.POSITIONS = 5
Lottery.ANIMALS = 25
Lottery.TRANCHE_BP = { 5000, 2500, 1500, 1000, 0 }
Lottery.OUTCOMES = Lottery.ANIMALS
Lottery.PRIZES = Lottery.POSITIONS

local MEDIA = "Interface\\AddOns\\Olympus_Arena\\media\\lottery\\"
local ICONS = "Interface\\Icons\\"

-- The 25 in the classic order, each of ours where the real game has its match (Avestruz 1 -> the
-- Mechanostrider, Aguia 2 -> the Gryphon, Cachorro 5 -> the Wolf, Carneiro 7 -> the Sheep, Cobra 9,
-- Cavalo 11 -> the Horse, Gato 14 -> the Nightsaber, Jacare 15 -> the Crocolisk, Leao 16, Porco 18 ->
-- the Boar, Tigre 22 -> the Cheetah, Urso 23, Veado 24 -> the Stag, Vaca 25 -> the Kodo). Nineteen
-- wear the honours' gold marks (the preview's choice, copied into the companion's media by
-- scripts/make-lottery-art.py; the Dragon is the game's gold elite mark); the six new ones the
-- game's icons for now (all in Forever's icon list).
Lottery.BEASTS = {
	{ key = "mechanostrider", art = MEDIA .. "mechanostrider" },
	{ key = "gryphon", art = MEDIA .. "gryphon" },
	{ key = "turtle", art = ICONS .. "Ability_Hunter_Pet_Turtle", icon = true },
	{ key = "bat", art = ICONS .. "Ability_Hunter_Pet_Bat", icon = true },
	{ key = "wolf", art = MEDIA .. "wolf" },
	{ key = "raptor", art = MEDIA .. "raptor" },
	{ key = "sheep", art = MEDIA .. "sheep" },
	{ key = "spider", art = ICONS .. "Ability_Hunter_Pet_Spider", icon = true },
	{ key = "cobra", art = MEDIA .. "cobra" },
	{ key = "koi", art = MEDIA .. "koi" },
	{ key = "horse", art = MEDIA .. "horse" },
	{ key = "dragon", art = MEDIA .. "dragon" },
	{ key = "raven", art = MEDIA .. "raven" },
	{ key = "nightsaber", art = MEDIA .. "nightsaber" },
	{ key = "crocolisk", art = ICONS .. "Ability_Hunter_Pet_Crocolisk", icon = true },
	{ key = "lion", art = MEDIA .. "lion" },
	{ key = "murloc", art = ICONS .. "INV_Misc_Head_Murloc_01", icon = true },
	{ key = "boar", art = MEDIA .. "boar" },
	{ key = "owl", art = MEDIA .. "owl" },
	{ key = "felhunter", art = MEDIA .. "felhunter" },
	{ key = "tentacle", art = MEDIA .. "tentacle" },
	{ key = "cheetah", art = MEDIA .. "cheetah" },
	{ key = "bear", art = ICONS .. "Ability_Racial_BearForm", icon = true },
	{ key = "stag", art = MEDIA .. "stag" },
	{ key = "kodo", art = MEDIA .. "kodo" },
}
for n, b in ipairs(Lottery.BEASTS) do
	b.n = n
	b.name = L["LOTTERY_BEAST_" .. b.key:upper()]
end

---------------------------------------------------------------------------
-- The numbers (pure)
---------------------------------------------------------------------------

local function Whole(v) return type(v) == "number" and v == floor(v) and v >= 0 and v < 2 ^ 53 end

-- A prize as the draw reads it: 0-9999, with 10000 (the top of /roll 1-10000) read as 0000; nil
-- for anything else.
function Lottery.Milhar(n)
	n = tonumber(n)
	if not n or not Whole(n) or n > 10000 then return nil end
	return n % 10000
end
-- "0427".
function Lottery.Text(n)
	local m = Lottery.Milhar(n)
	return m and ("%04d"):format(m) or nil
end
-- The beast of a prize: its last two digits' group, 01-04 -> 1 ... 97-00 -> 25.
function Lottery.BeastOf(n)
	local m = Lottery.Milhar(n)
	if not m then return nil end
	local d = m % 100
	if d == 0 then return Lottery.OUTCOMES end
	return floor((d - 1) / 4) + 1
end
-- A beast's four endings (its dezenas): { "01", "02", "03", "04" } ... { "97", "98", "99", "00" }.
function Lottery.Dezenas(beast)
	beast = tonumber(beast)
	if not beast or beast ~= floor(beast) or beast < 1 or beast > Lottery.OUTCOMES then return nil end
	local out = {}
	for i = 1, 4 do out[i] = ("%02d"):format(((beast - 1) * 4 + i) % 100) end
	return out
end
function Lottery.DezenasText(beast)
	local d = Lottery.Dezenas(beast)
	return d and table.concat(d, " ") or ""
end
function Lottery.Beast(n)
	return Lottery.BEASTS[tonumber(n) or 0]
end
-- "07 Sheep".
function Lottery.Label(beast)
	local b = Lottery.Beast(beast)
	return b and ("%02d %s"):format(b.n, b.name) or ""
end

-- The five prizes as the sheet's result carries them: "0427.9981.1200.0033.5555".
function Lottery.ResultText(prizes)
	if type(prizes) ~= "table" or #prizes ~= Lottery.PRIZES then return nil end
	local out = {}
	for i = 1, Lottery.PRIZES do
		out[i] = Lottery.Text(prizes[i])
		if not out[i] then return nil end
	end
	return table.concat(out, ".")
end
-- The other way: exactly five groups of four digits, or a { prizes } table; nil for anything else.
function Lottery.ReadResult(r)
	if type(r) == "table" then
		local p = type(r.prizes) == "table" and r.prizes or (type(r.lottery) == "table" and r.lottery.prizes) or r.text or (r.lottery and r.lottery.text)
		if type(p) == "string" then return Lottery.ReadResult(p) end
		if type(p) ~= "table" or #p ~= Lottery.PRIZES then return nil end
		local out = {}
		for i = 1, Lottery.PRIZES do
			out[i] = Lottery.Milhar(p[i])
			if not out[i] or p[i] == 10000 then return nil end
		end
		return out
	end
	if type(r) ~= "string" then return nil end
	local a, b, c, d, e = r:match("^(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)%.(%d%d%d%d)$")
	if not a then return nil end
	return { tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e) }
end
function Lottery.Head(prizes)
	return type(prizes) == "table" and prizes[1] ~= nil and Lottery.BeastOf(prizes[1]) or nil
end

-- The draw time: the next moment the realm's clock shows `at` (minutes after its midnight),
-- `ahead` seconds or more from `now` (server time). offset: the realm's clock less UTC, in minutes.
function Lottery.NextDraw(now, at, offset, ahead)
	now, at, offset, ahead = tonumber(now), tonumber(at), tonumber(offset) or 0, max(0, tonumber(ahead) or 0)
	if not now or not at or at ~= floor(at) or at < 0 or at >= 1440 then return nil end
	local shift = floor(offset) * 60
	local here = now + shift
	local t = here - here % 86400 + at * 60 - shift
	while t < now + ahead do t = t + 86400 end
	return t
end
-- The realm's clock less UTC in minutes (a multiple of 15), from the game's clock; 0 without it.
function Lottery.RealmOffset(now)
	now = tonumber(now) or Arena.Now()
	if type(GetGameTime) ~= "function" then return 0 end
	local ok, h, m = pcall(GetGameTime)
	if not ok or type(h) ~= "number" or type(m) ~= "number" then return 0 end
	local d = (h * 60 + m - floor(now / 60) % 1440) % 1440
	if d > 720 then d = d - 1440 end
	return floor(d / 15 + 0.5) * 15
end

-- The draw's clock (the owner's call, 2026-10-04): 21:00 US Central, Texas time. A realm whose own
-- clock runs on US Central (the realm's offset is Central's at that moment, daylight saving included)
-- draws by it, so the draw is at 21:00 on the clock its players see; any other realm by a fixed
-- UTC-5 (21:00 in Texas' summer, 20:00 in its winter), with no daylight-saving rule of its own to
-- get wrong. Every client of a realm reads the same clock, so all of them agree on the zone.
-- Days since 1970-01-01 of a civil date, and the civil year of such a day (proleptic Gregorian).
local function DaysOf(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = floor(y / 400)
	local yoe = y - era * 400
	local doy = floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	return era * 146097 + yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy - 719468
end
local function YearOf(days)
	days = days + 719468
	local era = floor(days / 146097)
	local doe = days - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local m = floor((5 * doy + 2) / 153)
	return yoe + era * 400 + (m >= 10 and 1 or 0)
end
-- The day of a month's nth Sunday.
local function Sunday(y, m, n)
	local first = DaysOf(y, m, 1)
	return first + (7 - (first + 4) % 7) % 7 + (n - 1) * 7
end
-- US Central's offset from UTC at server time t, in minutes: -300 (CDT) from the second Sunday of
-- March at 2:00 CST to the first Sunday of November at 2:00 CDT, -360 (CST) otherwise (the US rule
-- since 2007).
function Lottery.CentralOffset(t)
	t = tonumber(t) or Arena.Now()
	local y = YearOf(floor(t / 86400))
	local from, to = Sunday(y, 3, 2) * 86400 + 8 * 3600, Sunday(y, 11, 1) * 86400 + 7 * 3600
	return (t >= from and t < to) and -300 or -360
end
-- "central" when this realm's clock runs on US Central, else "fixed" (UTC-5).
function Lottery.Zone(now)
	now = tonumber(now) or Arena.Now()
	return Lottery.RealmOffset(now) == Lottery.CentralOffset(now) and "central" or "fixed"
end
-- The draw's clock less UTC at server time t, in minutes.
function Lottery.ZoneOffset(t, zone)
	if (zone or Lottery.Zone()) == "central" then return Lottery.CentralOffset(t) end
	return Lottery.FIXED_OFFSET
end
function Lottery.ZoneText(zone)
	return (zone or Lottery.Zone()) == "central" and L.LOTTERY_ZONE_CENTRAL or L.LOTTERY_ZONE_FIXED
end
-- The next draw: the next moment the draw's clock shows `at`, `ahead` seconds or more from `now`
-- (on Central, a daylight-saving change before it counted).
function Lottery.DrawAt(now, at, ahead, zone)
	now = tonumber(now) or Arena.Now()
	zone = zone or Lottery.Zone(now)
	local off = Lottery.ZoneOffset(now, zone)
	local t = Lottery.NextDraw(now, at, off, ahead)
	if t and zone == "central" and Lottery.CentralOffset(t) ~= off then t = Lottery.NextDraw(now, at, Lottery.CentralOffset(t), ahead) end
	return t
end
-- "21:00" on the draw's clock (or with that offset, in minutes).
function Lottery.ClockText(t, offset)
	t = tonumber(t)
	if not t then return "" end
	local here = (t + floor(tonumber(offset) or Lottery.ZoneOffset(t)) * 60) % 86400
	return ("%02d:%02d"):format(floor(here / 3600), floor(here % 3600 / 60))
end
-- "21:00 US Central" (or "21:00 UTC-5").
function Lottery.WhenText(t) return t and (Lottery.ClockText(t) .. " " .. Lottery.ZoneText()) or "" end
function Lottery.MinutesText(at)
	at = tonumber(at) or 0
	return ("%02d:%02d"):format(floor(at / 60) % 24, at % 60)
end
-- "21:00" (or "21h", "9:30") as minutes after midnight, or nil.
function Lottery.ReadTime(s)
	if type(s) ~= "string" then return nil end
	local h, m = s:match("^%s*(%d%d?)[:h%.]?(%d?%d?)%s*$")
	h, m = tonumber(h), tonumber(m ~= "" and m or "0")
	if not h or not m or h > 23 or m > 59 then return nil end
	return h * 60 + m
end

---------------------------------------------------------------------------
-- The settlement (pure): the versioned five-position contract shared by the wallet, market
-- replicas and the practice table. The daily controller below owns scheduling and witnessed rolls;
-- it never implements a second ledger or a second payout formula.
---------------------------------------------------------------------------

local Math = ns.ArenaMath
local MAX_POOL = Math and Math.MAX_POOL or 2 ^ 43
local MAX_STAKE = Math and Math.MAX_COPPER or 2147483647
local TWO53 = 2 ^ 53

local function Whole(n)
	return type(n) == "number" and n == floor(n) and n >= 0 and n < TWO53
end

local function List(t)
	if type(t) ~= "table" then return nil end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do if t[i] == nil then return nil end end
	return n
end

local function Animal(n)
	return Whole(n) and n >= 1 and n <= Lottery.ANIMALS
end

-- Exact (a * b) modulo m for the contract's ranges. The quotient comes from ArenaMath.MulDiv;
-- this supplies the exact remainder used by Hamilton's largest-remainder method without ever
-- making the (possibly > 2^53) product in a Lua number.
local function MulMod(a, b, m)
	if m == 1 then return 0 end
	a, b = a % m, b
	local r = 0
	while b > 0 do
		if b % 2 == 1 then
			if r >= m - a then r = r - (m - a) else r = r + a end
		end
		b = floor(b / 2)
		if b > 0 then
			if a >= m - a then a = a - (m - a) else a = a + a end
		end
	end
	return r
end

-- Allocate amount in proportion to rows[i].weight. The returned values sum to amount. `less` is
-- the deterministic tie-break after a remainder (draw position, then ticket id).
local function Allocate(amount, rows, less)
	local out, ranked, total, paid = {}, {}, 0, 0
	for _, row in ipairs(rows) do total = total + row.weight end
	if amount == 0 or total == 0 then
		for i in ipairs(rows) do out[i] = 0 end
		return out
	end
	for i, row in ipairs(rows) do
		local q = Math and Math.MulDiv(amount, row.weight, total)
		if q == nil then return nil end
		out[i], paid = q, paid + q
		ranked[i] = { i = i, rem = MulMod(amount, row.weight, total), row = row }
	end
	table.sort(ranked, function(a, b)
		if a.rem ~= b.rem then return a.rem > b.rem end
		return less(a.row, b.row)
	end)
	local left = amount - paid
	for i = 1, left do
		local at = ranked[i]
		if not at then return nil end
		out[at.i] = out[at.i] + 1
	end
	return out
end

local function TicketLess(a, b)
	if a.position ~= b.position then return a.position < b.position end
	return a.id < b.id
end

local function PositionLess(a, b) return a.position < b.position end

-- A stable id for a ticket in the wallet ledger. Sequence and position are immutable parts of
-- the entry; the nonce makes diagnostics readable but does not decide uniqueness by itself.
function Lottery.TicketId(seq, place, nonce)
	seq, place = tonumber(seq), tonumber(place)
	if not Whole(seq) or seq < 1 or not Whole(place) or place < 1 then return nil end
	return ("%014d.%06d.%s"):format(seq, place, tostring(nonce or ""))
end

function Lottery.Settle(contract)
	if type(contract) ~= "table" then return nil, "contract" end
	if contract.version ~= Lottery.SETTLEMENT_VERSION then return nil, "version" end
	local n = List(contract.tickets)
	if not n then return nil, "tickets" end
	if List(contract.draw) ~= Lottery.POSITIONS then return nil, "draw" end
	local draw, drawn = {}, {}
	for position = 1, Lottery.POSITIONS do
		local animal = contract.draw[position]
		if not Animal(animal) then return nil, "draw", position end
		draw[position] = animal
		drawn[animal] = true
	end
	local carry = contract.carry == nil and 0 or contract.carry
	if not Whole(carry) or carry > MAX_POOL then return nil, "carry" end
	local feeBp = contract.feeBp == nil and Lottery.DEFAULT_FEE_BP or contract.feeBp
	if feeBp ~= Lottery.DEFAULT_FEE_BP then return nil, "fee" end

	local ids, tickets, byAnimal = {}, {}, {}
	local newStakes, refunds = 0, 0
	for i = 1, n do
		local source = contract.tickets[i]
		if type(source) ~= "table" or type(source.id) ~= "string" or source.id == "" or #source.id > 128
			or not Animal(source.animal) or not Whole(source.stake) or source.stake < 1 or source.stake > MAX_STAKE
			or not (source.who == nil or (type(source.who) == "string" and source.who ~= "")) then
			return nil, "ticket", i
		end
		if ids[source.id] then return nil, "id", i end
		ids[source.id] = true
		newStakes = newStakes + source.stake
		if newStakes + carry > MAX_POOL then return nil, "pool" end
		local ticket = { id = source.id, animal = source.animal, stake = source.stake, who = source.who, index = i,
			winning = drawn[source.animal] == true }
		tickets[i] = ticket
		local list = byAnimal[ticket.animal]
		if not list then list = {}; byAnimal[ticket.animal] = list end
		list[#list + 1] = ticket
		if ticket.winning then refunds = refunds + ticket.stake end
	end

	local available = carry + newStakes
	local profitPool = available - refunds
	local trancheRows = {}
	for position = 1, 4 do
		trancheRows[position] = { position = position, weight = Lottery.TRANCHE_BP[position] }
	end
	local gross = Allocate(profitPool, trancheRows, PositionLess)
	if not gross then return nil, "pool" end

	local tranches, claimedRows, claimedGross, nextCarry = {}, {}, 0, 0
	for position = 1, Lottery.POSITIONS do
		local animal = draw[position]
		local hasTickets = byAnimal[animal] ~= nil
		local amount = position <= 4 and gross[position] or 0
		local row = { position = position, animal = animal, weightBp = Lottery.TRANCHE_BP[position], gross = amount,
			hasTickets = hasTickets, claimed = hasTickets and amount > 0, fee = 0, net = 0, paid = 0, carry = 0 }
		tranches[position] = row
		if row.claimed then
			claimedGross = claimedGross + amount
			claimedRows[#claimedRows + 1] = { position = position, weight = amount, tranche = row }
		elseif amount > 0 then
			row.carry = amount
			nextCarry = nextCarry + amount
		end
	end

	local fee = Math and Math.MulDiv(claimedGross, feeBp, 10000)
	if fee == nil then return nil, "fee" end
	local feeParts = Allocate(fee, claimedRows, PositionLess)
	if not feeParts then return nil, "fee" end
	for i, claim in ipairs(claimedRows) do
		claim.tranche.fee = feeParts[i]
		claim.tranche.net = claim.tranche.gross - feeParts[i]
	end

	local payouts, refundByTicket, profitByTicket, byId, byWho = {}, {}, {}, {}, {}
	for i, ticket in ipairs(tickets) do
		local refund = ticket.winning and ticket.stake or 0
		refundByTicket[i], profitByTicket[i], payouts[i] = refund, 0, refund
	end
	for _, claim in ipairs(claimedRows) do
		local position, tranche = claim.position, claim.tranche
		local animalTickets, rows = byAnimal[tranche.animal], {}
		for i, ticket in ipairs(animalTickets) do
			rows[i] = { position = position, id = ticket.id, weight = ticket.stake, ticket = ticket }
		end
		local shares = Allocate(tranche.net, rows, TicketLess)
		if not shares then return nil, "pool" end
		for i, row in ipairs(rows) do
			local index, share = row.ticket.index, shares[i]
			profitByTicket[index] = profitByTicket[index] + share
			payouts[index] = payouts[index] + share
			tranche.paid = tranche.paid + share
		end
	end

	local netProfit, paid = 0, 0
	local winningTickets, winnerNames = 0, {}
	for i, ticket in ipairs(tickets) do
		netProfit = netProfit + profitByTicket[i]
		paid = paid + payouts[i]
		byId[ticket.id] = payouts[i]
		if ticket.winning then winningTickets = winningTickets + 1 end
		if ticket.who then
			byWho[ticket.who] = (byWho[ticket.who] or 0) + payouts[i]
			if ticket.winning then winnerNames[ticket.who] = true end
		end
	end
	local winners = 0
	for _ in pairs(winnerNames) do winners = winners + 1 end
	assert(refunds + netProfit + fee + nextCarry == available,
		"Lottery.Settle: refunds + net profit + fee + carry must equal carry in + stakes")
	assert(netProfit + fee == claimedGross, "Lottery.Settle: claimed gross profit must be paid or charged")

	return {
		version = Lottery.SETTLEMENT_VERSION, draw = draw, tickets = tickets, tranches = tranches,
		incomingCarry = carry, carryIn = carry, newStakes = newStakes, stakes = newStakes,
		available = available, pool = available, refunds = refunds, profitPool = profitPool,
		grossProfit = claimedGross, netProfit = netProfit, fee = fee, guildFee = fee, arbFee = 0,
		nextCarry = nextCarry, rollover = nextCarry, paid = paid, payouts = payouts,
		refundByTicket = refundByTicket, profitByTicket = profitByTicket, byId = byId, byWho = byWho,
		winningTickets = winningTickets, winners = winners,
	}
end

-- The settlement written in the wallet's x entry and the market book. Dots are intentional: the
-- head-only wallet parser accepted only [%w+], so a pre-v2 client rejects this entry instead of
-- interpreting all five animals as equal winners. The final field is the retained carry.
function Lottery.EncodeResult(draw, nextCarry)
	if List(draw) ~= Lottery.POSITIONS or not Whole(nextCarry) or nextCarry > MAX_POOL then return nil end
	local parts = { Lottery.WIRE_PREFIX }
	for i = 1, Lottery.POSITIONS do
		if not Animal(draw[i]) then return nil end
		parts[#parts + 1] = tostring(draw[i])
	end
	local Arena = ns.Arena
	parts[#parts + 1] = Arena and Arena.B36 and Arena.B36(nextCarry) or tostring(nextCarry)
	return table.concat(parts, ".")
end

function Lottery.DecodeResult(text)
	if type(text) ~= "string" then return nil, "result" end
	local a, b, c, d, e, carry = text:match("^L2%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.([0-9a-z]+)$")
	if not carry then return nil, "version" end
	local draw = { tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e) }
	for i = 1, Lottery.POSITIONS do if not Animal(draw[i]) then return nil, "result", i end end
	local n
	if ns.Arena and ns.Arena.N then n = ns.Arena.N(carry, 0, MAX_POOL) else n = tonumber(carry) end
	if not Whole(n) or n > MAX_POOL then return nil, "result" end
	return { version = Lottery.SETTLEMENT_VERSION, draw = draw, nextCarry = n, wire = text }
end

-- An exact return cannot be quoted before the draw (the same beast may come up in several places,
-- other beasts' stakes come back, more bets come), so the board shows an illustration before a bet
-- (the owner's call, 2026-10-04): what `silver` more on `beast` would get back if that beast came
-- 1st and nowhere else, with the table as it is now (its pools and the pot rolled in) and the other
-- four places on the least-backed beasts (on most days beasts nobody backed: no other stake back).
-- It is Lottery.Settle itself over one ticket per beast's pool, as the markets recompute a declared
-- day (Markets.LotterySettlement); the bank settles the exact copper by the real tickets.
-- { payout, stake, profit } in copper, or nil (no open day; a beast or a stake it cannot take).
function Lottery.Preview(day, beast, silver)
	if type(day) ~= "table" or day.state ~= "open" or type(day.bets) ~= "table" then return nil end
	beast, silver = tonumber(beast), tonumber(silver)
	if not Animal(beast) or not Whole(silver) or silver < 1 or silver * 100 > MAX_STAKE then return nil end
	local stake = silver * 100
	local tickets, others = {}, {}
	for o = 1, Lottery.ANIMALS do
		local pool = floor(tonumber(type(day.bets[o]) == "table" and day.bets[o].pool) or 0)
		if pool > 0 then tickets[#tickets + 1] = { id = ("pool.%02d"):format(o), animal = o, stake = pool } end
		if o ~= beast then others[#others + 1] = { o = o, pool = pool } end
	end
	tickets[#tickets + 1] = { id = "preview", animal = beast, stake = stake }
	table.sort(others, function(a, b) if a.pool ~= b.pool then return a.pool < b.pool end return a.o < b.o end)
	local draw = { beast }
	for i = 1, Lottery.POSITIONS - 1 do draw[i + 1] = others[i].o end
	local r = Lottery.Settle({ version = Lottery.SETTLEMENT_VERSION, tickets = tickets, draw = draw,
		carry = floor(tonumber(day.carry) or 0), feeBp = Lottery.DEFAULT_FEE_BP })
	if not r then return nil end
	local payout = r.payouts[#tickets]
	return { payout = payout, stake = stake, profit = payout - stake }
end
function Lottery.PayoutOf(mine)
	local paid, known = 0, false
	for _, ticket in ipairs(type(mine) == "table" and mine or {}) do
		if type(ticket.payout) == "number" then paid, known = paid + ticket.payout, true end
	end
	return known and paid or nil
end

-- An amount in the day's currency: gold, glory points or rehearsal chips.
function Lottery.Money(copper, cur)
	copper = floor(tonumber(copper) or 0)
	if cur == "p" then return L.LOTTERY_POINTS:format(ns.FormatNumber(floor(copper / 100))) end
	if cur == "c" then return L.LOTTERY_CHIPS:format(ns.FormatNumber(floor(copper / 100))) end
	-- (To the copper: a bettor checks his payout against his wallet.)
	local T = ns.Treasury
	if type(T) == "table" and type(T.Coins) == "function" then return T.Coins(copper) end
	return ns.FormatNumber(floor(copper / 10000)) .. "g"
end

---------------------------------------------------------------------------
-- Who calls it, who holds it
---------------------------------------------------------------------------

local function Roles() return ns.ArenaRoles end
local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end
-- The compliance gate (Compliance.lua): a ticket, the day's market and its draw only where it allows
-- the Lottery (1.1.6: nowhere; the companion's practice table moves nothing and asks nobody).
local function Wagers(kind)
	local C = ns.Compliance
	return type(C) == "table" and type(C.Allows) == "function" and C.Allows(kind or "lottery", "lottery") == true
end
Lottery.Wagers = function() return Wagers("lottery") end

-- The King's character as the server stamps it, or nil (none named on this side).
local function KingName()
	local short = ns.KingCharacter and ns.KingCharacter()
	if type(short) ~= "string" or short == "" then return nil end
	local realm = ns.KingRealm and ns.KingRealm() or nil
	return ns.FullName(short, realm)
end

-- The lottery's caller: the King's character; in a rehearsal (T), a King's stand-in too.
function Lottery.IsCaller(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	local R = Roles()
	if R and R.IsKing(name) then return true end
	if mode == "T" and R and type(R.standIn) == "function" then
		local ok, yes = pcall(R.standIn, ns.FullName(name), "k", "T")
		return ok and yes == true
	end
	return false
end
-- Every name an L eid's writer mark may stand for, in a mode.
function Lottery.Callers(mode)
	local out = {}
	local king = KingName()
	if king then out[1] = king end
	local R = Roles()
	if mode == "T" and R and type(R.standIns) == "function" then
		local ok, list = pcall(R.standIns, "k", "T")
		for _, name in ipairs(ok and type(list) == "table" and list or {}) do
			if type(name) == "string" then out[#out + 1] = ns.FullName(name) end
		end
	end
	return out
end

-- The lottery's bank: the first open bank of this realm by sorted name (every client picks the
-- same one); nil when there is none.
function Lottery.Bank(mode)
	local R = Roles()
	if not (R and type(R.Banks) == "function") then return nil end
	local list = {}
	for _, b in ipairs(R.Banks(mode or "L")) do
		if b.state == "o" and type(b.name) == "string" then list[#list + 1] = ns.FullName(b.name) end
	end
	table.sort(list, function(a, b) return a:lower() < b:lower() end)
	return list[1]
end

-- Who may not bet on a day: its caller and its bank, and their other characters.
local function Excluded(name, day)
	if type(name) ~= "string" then return true end
	local mode = day and day.mode or "L"
	if Lottery.IsCaller(name, mode) then return true end
	local bank = day and day.bank or Lottery.Bank(mode)
	local list = { bank }
	if day and day.caller then list[#list + 1] = day.caller end
	for _, other in ipairs(Lottery.Callers(mode)) do list[#list + 1] = other end
	local D = ns.Debts
	for _, other in pairs(list) do
		if Same(name, other) then return true end
		if type(D) == "table" and type(D.SameOwner) == "function" then
			local ok, yes = pcall(D.SameOwner, name, other)
			if ok and yes == true then return true end
		end
	end
	return false
end
function Lottery.MayBet(name, day) return not Excluded(name, day) end

-- The terms a new day opens on (the King's gold switch): mode, currency, and a note.
--   live off (or a test build): a rehearsal, "T", in its chips (or capped copper in a copper rehearsal);
--   live on in points: "L", "p"; live on in gold: "L", "g" where this client's saved data persists,
--   else a rehearsal (the beta: gold stays off there, the design).
function Lottery.Terms()
	local mode = Arena.NewMode(false)
	if mode == "L" then
		local R = Roles()
		local cur = R and R.Currency and R.Currency() or "g"
		if cur == "p" then return "L", "p" end
		if Arena.Persists() then return "L", "g" end
		return "T", "c", "beta"
	end
	local T = ns.ArenaTest
	local ok, r = pcall(function() return type(T) == "table" and type(T.Running) == "function" and T.Running() or nil end)
	if ok and type(r) == "table" and r.money == "p" then return "T", "g" end
	return "T", "c"
end
-- The fee of a day: the King's whole fee (feeBp, 600 by default) in gold, all the guild's; none
-- in points or a rehearsal.
function Lottery.FeeBp(mode, cur)
	if mode ~= "L" or cur ~= "g" then return 0 end
	local R = Roles()
	local s = R and R.Settings and R.Settings() or {}
	return floor(tonumber(s.feeBp) or ns.ArenaMath.DEFAULT_FEE)
end
-- The smallest stake, in silver.
function Lottery.MinSilver()
	local R = Roles()
	local s = R and R.Settings and R.Settings() or {}
	return max(1, math.ceil((tonumber(s.minBet) or ns.ArenaMath.MIN_BET) / 100))
end
function Lottery.MaxSilver()
	local R = Roles()
	local s = R and R.Settings and R.Settings() or {}
	return max(Lottery.MinSilver(), floor((tonumber(s.maxBet) or 20 * 10000) / 100))
end

---------------------------------------------------------------------------
-- The events registry: what an L eid is (Markets asks before it takes a sheet)
---------------------------------------------------------------------------

local known = {} -- [eid] = { mode, lockAt, bank }: days this client opened or read

local function EventOf(eid)
	if type(eid) ~= "string" or #eid < 5 or #eid > 24 or not eid:find("^L[0-9a-z]+$") then return nil end
	local mark = eid:sub(-2)
	local seen = {}
	for _, mode in ipairs({ "L", "T" }) do
		for _, name in ipairs(Lottery.Callers(mode)) do
			if not seen[name:lower()] then
				seen[name:lower()] = true
				if Arena.Hash36(name:lower(), 2) == mark then
					local day = known[eid] or {}
					local tmode = day.mode or (mode == "T" and "T" or nil)
					local bank = day.bank or Lottery.Bank(tmode or "L")
					-- (noResult: a bank online since the draw time voids a day with no declared draw this
					-- long after it; one that came on later waits for the declaration, MarketBank.Tick.)
					return { kind = "lottery", opener = name, public = true, category = "lottery", market = Lottery.TYPE,
						outcomes = Lottery.OUTCOMES, mode = tmode, lockAt = day.lockAt, bank = bank,
						excluded = { name, bank }, drawers = { name, bank }, noResult = Lottery.DRAW_WINDOW + Lottery.VOID_SLACK }
				end
			end
		end
	end
	return nil
end
Lottery.EventOf = EventOf
Arena.Events.Register("L", EventOf)

---------------------------------------------------------------------------
-- The day, as the markets show it
---------------------------------------------------------------------------

local function FeeBpOf(fee)
	if type(fee) == "number" then return floor(fee) end
	if type(fee) == "table" then return floor((tonumber(fee.g or fee.feeBp or fee[1]) or 0) + (tonumber(fee.a or fee.arbBp or fee[2]) or 0)) end
	return 0
end
local STATE = { O = "open", L = "closed", R = "drawn", S = "settled", V = "void", H = "held" }
-- The pot rolled in, from the v2 sheet's param "2.<from>.<copper b36>".
function Lottery.Param(from, copper)
	if not from or not copper or copper <= 0 then return "2" end
	return "2." .. from .. "." .. Arena.B36(copper)
end
function Lottery.ReadParam(p)
	if type(p) ~= "string" then return nil end
	local from, c = p:match("^2%.(L[0-9a-z]+)%.([0-9a-z]+)$")
	c = c and Arena.N(c, 1)
	if not from or not c then return nil end
	return from, c
end

-- The day eid as Markets.View gives it, in the lottery's words (nil when the markets don't know it).
function Lottery.Read(eid)
	local M = ns.Markets
	if type(eid) ~= "string" or type(M) ~= "table" or type(M.View) ~= "function" then return nil end
	local ok, v = pcall(M.View, eid)
	if not ok or type(v) ~= "table" or type(v.markets) ~= "table" then return nil end
	local m
	for _, x in ipairs(v.markets) do
		if type(x) == "table" and (x.idx == nil or tonumber(x.idx) == Lottery.IDX) and (x.type == nil or x.type == Lottery.TYPE) then m = x break end
	end
	if not m then return nil end
	local day = { eid = eid, lockAt = tonumber(v.lockAt), bank = v.bank, cur = v.cur or "g", mode = v.mode or Arena.Mode(v),
		fee = FeeBpOf(v.fee), bets = {}, pool = 0, count = 0, carry = 0, sheet = m.state }
	for o = 1, Lottery.OUTCOMES do day.bets[o] = { pool = 0, count = 0 } end
	for _, oc in ipairs(type(m.outcomes) == "table" and m.outcomes or {}) do
		local o = tonumber(oc.o)
		if o and day.bets[o] then
			local p, c = floor(tonumber(oc.pool) or 0), floor(tonumber(oc.count) or 0)
			day.bets[o] = { pool = p, count = c }
			day.pool, day.count = day.pool + p, day.count + c
		end
	end
	if type(v.carry) == "table" then
		day.from, day.carry = v.carry.from, floor(tonumber(v.carry.copper) or 0)
	else
		local from, c = Lottery.ReadParam(m.param)
		if from then day.from, day.carry = from, c end
	end
	day.pot = day.pool + day.carry
	day.state = STATE[m.state] or "open"
	if day.state == "open" and day.lockAt and Arena.Now() >= day.lockAt then day.state = "closed" end
	day.prizes = Lottery.ReadResult(m.result) or Lottery.ReadResult(v.lottery)
	local ev = EventOf(eid)
	day.caller = ev and ev.opener
	known[eid] = known[eid] or {}
	known[eid].mode, known[eid].lockAt, known[eid].bank = day.mode, day.lockAt, day.bank
	return day
end

---------------------------------------------------------------------------
-- The caller's book (the King's client, or a stand-in's in a rehearsal)
---------------------------------------------------------------------------

-- Where this client keeps the lottery it calls: the King's in his realm's live store, a stand-in's
-- in the rehearsal store; nil for everyone else.
local function Book()
	local R = Roles()
	local store
	if R and R.IsKing(ns.me) then
		store = Arena.Store("L")
	elseif Lottery.IsCaller(ns.me, "T") then
		store = Arena.Store("T")
	end
	if type(store) ~= "table" then return nil end
	if type(store.lottery) ~= "table" then store.lottery = { v = 1 } end
	return store.lottery
end
Lottery.Book = Book
function Lottery.Schedule()
	local lot = Book()
	local s = lot and lot.schedule
	return { on = type(s) == "table" and s.on == true, at = type(s) == "table" and tonumber(s.at) or Lottery.DEFAULT_AT,
		roller = lot and lot.roller == "bank" and "bank" or "king" }
end

local told = {}
local function SayOnce(key, text)
	if told[key] then return end
	told[key] = true
	ns.Print(text)
end

-- The witness (any client): the rolls of the current due draw it saw, before the result comes.
local witness -- { eid, drawer, prizes }

local watching = false
local function Due()
	-- (Read at each roll line: nothing here while no draw is due on this client. The caller's day
	-- stays due after its five prizes until the next one opens, so an extra roll is told.)
	local lot = Book()
	local day = lot and lot.day
	local now = Arena.Now()
	if day and now >= (day.lockAt or math.huge) and not (day.declared and now - (day.declaredAt or 0) > Lottery.EXTRA_FOR) then return true end
	return witness ~= nil
end
local function Watch()
	if watching then return end
	watching = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text)
		if not Due() then return end
		ns.SafeCall("lottery roll", Lottery.OnRoll, text)
	end)
end

local Cycle -- (below)
local function Involve()
	local lot = Book()
	local day = lot and lot.day
	local on = lot ~= nil and not Arena.Off() and ((lot.schedule and lot.schedule.on == true) or (day ~= nil and not day.declared))
	Arena.Involve("lottery", on and true or false)
	Arena.Every(Lottery.TICK, "lottery", on and function() Cycle() end or nil)
	return on
end
Lottery.Involve = Involve

-- The range a draw's roll may have: /roll 1-10000 (the button's) or /roll 0-9999.
function Lottery.RangeOK(low, high)
	return (low == 1 and high == 10000) or (low == 0 and high == 9999)
end

local Declare -- (below)

-- A roll line (CHAT_MSG_SYSTEM). On the caller's client: the next prize of his due draw when it
-- is the roller's (his own, or the bank's when he let it roll), in the range, after the draw
-- time; the five first count, any later one is left out. Elsewhere, a witness's view of the draw.
function Lottery.OnRoll(text)
	local P = ns.ArenaParse
	local name, value, low, high = P.Roll(text)
	if not name or not Lottery.RangeOK(low, high) then return false end
	name = ns.FullName(ns.Normal(name))
	local now = Arena.Now()
	local lot = Book()
	local day = lot and lot.day
	if day and now >= (day.lockAt or math.huge) and not day.void and not (day.declared and now - (day.declaredAt or 0) > Lottery.EXTRA_FOR) then
		local roller = day.rolledBy or (lot.roller == "bank" and day.bank or ns.me)
		if not Same(name, roller) then return false end
		-- (The draw's hour is over: no roll counts any more, and the day goes void.)
		if not day.declared and now >= day.lockAt + Lottery.DRAW_WINDOW then return false end
		day.prizes = day.prizes or {}
		if #day.prizes >= Lottery.PRIZES then
			day.extra = (day.extra or 0) + 1
			ns.Print(L.LOTTERY_EXTRA_ROLL)
			return false
		end
		local prize = Lottery.Milhar(value)
		day.prizes[#day.prizes + 1] = prize
		day.rolledBy = roller
		ns.Fire("LOTTERY_DRAW", day.eid, #day.prizes, prize, Lottery.BeastOf(prize))
		if #day.prizes == Lottery.PRIZES then Declare(day) end
		Arena.Changed()
		return true
	end
	-- A witness: the latest day, due and not drawn yet; the first of the King and the bank to roll
	-- is the roller here (the declared result replaces what was seen).
	local eid = Lottery.Current()
	local d = eid and Lottery.Read(eid)
	if not d or d.prizes or not d.lockAt or now < d.lockAt or now >= d.lockAt + Lottery.DRAW_WINDOW then return false end
	if not witness or witness.eid ~= eid then witness = { eid = eid, prizes = {} } end
	if witness.drawer then
		if not Same(name, witness.drawer) then return false end
	elseif not (Same(name, d.caller) or Same(name, d.bank)) then
		return false
	end
	if #witness.prizes >= Lottery.PRIZES then return false end
	witness.drawer = witness.drawer or name
	local prize = Lottery.Milhar(value)
	witness.prizes[#witness.prizes + 1] = prize
	ns.Fire("LOTTERY_DRAW", eid, #witness.prizes, prize, Lottery.BeastOf(prize))
	Arena.Changed()
	return true
end

-- The five prizes, on the caller's client: the sheet's result.
Declare = function(day)
	local M = ns.Markets
	if type(M) ~= "table" or type(M.DeclareDraw) ~= "function" then return false, "markets" end
	if not day.prizes or #day.prizes ~= Lottery.PRIZES then return false, "prizes" end
	local head = Lottery.BeastOf(day.prizes[1])
	local prizes = {}
	for i, p in ipairs(day.prizes) do prizes[i] = p end
	local ok, a, b = pcall(M.DeclareDraw, day.eid, prizes)
	if not ok or a == false then
		ns.Log("lottery %s not declared: %s", tostring(day.eid), tostring(ok and b or a))
		return false, ok and b or a
	end
	day.declared, day.head, day.declaredAt = true, head, Arena.Now()
	-- The bank computes retained carry from the same v2 settlement as every replica. OpenNext waits
	-- for its settled book before moving that carry, so a late book cannot silently lose a tranche.
	day.rollover = nil
	ns.Print(L.LOTTERY_DECLARED:format(Lottery.PrizesText(prizes)))
	ns.Fire("LOTTERY_RESULT", day.eid)
	Arena.Changed()
	Involve()
	return true
end
Lottery.Declare = function() local lot = Book() return lot and lot.day and Declare(lot.day) end

-- "1st 0427 10 Koi · 2nd ...".
function Lottery.PrizesText(prizes)
	local out = {}
	for i, p in ipairs(type(prizes) == "table" and prizes or {}) do
		out[i] = ("%s %s %s"):format(L["LOTTERY_PRIZE_" .. i], Lottery.Text(p) or "----", Lottery.Label(Lottery.BeastOf(p)))
	end
	return table.concat(out, " · ")
end

-- The next day, on the caller's client: its sheet (Markets.OpenLottery), carrying the previous
-- day's unclaimed profit only after the bank has settled it (or it is void). A day's winners are
-- paid by the next day (the owner's call, 2026-10-04: the bank settles when its client is on), and
-- the next day waits for that settlement: a day naming a pot its bank does not hold settled yet
-- voids (C, MarketBank's TakeCarry), and every day after it would name that void day's pot again.
-- A carry never crosses currencies or live/rehearsal modes; it remains in the source ledger until
-- compatible terms return.
local function OpenNext(lot)
	if not Wagers() then
		SayOnce("compliance", L.COMPLIANCE_WAIT)
		return false, "compliance"
	end
	local M = ns.Markets
	if type(M) ~= "table" or type(M.OpenLottery) ~= "function" then
		SayOnce("markets", L.LOTTERY_NO_MARKETS)
		return false, "markets"
	end
	local mode, cur, note = Lottery.Terms()
	local bank = Lottery.Bank(mode)
	if not bank then
		SayOnce("bank", L.LOTTERY_NO_BANK)
		return false, "bank"
	end
	if note == "beta" then SayOnce("beta", L.LOTTERY_BETA) end
	local now = Arena.Now()
	local lockAt = Lottery.DrawAt(now, lot.schedule.at, Arena.OpenMin(true))
	local prev = lot.day
	local carry, from = 0, nil
	if prev then
		local settled = Lottery.Read(prev.eid)
		if not settled or (settled.state ~= "settled" and settled.state ~= "void") then return false, "settling" end
		-- Markets.Carry also returns the source id. Capture its first result before tonumber:
		-- in Lua a call in the last argument position forwards every result, and the source id
		-- would otherwise be mistaken for tonumber's numeric base.
		local carried = type(M.Carry) == "function" and M.Carry(prev.eid) or nil
		carry = tonumber(carried)
		if carry == nil or carry < 0 then return false, "carry" end
		prev.rollover = carry
		if carry > 0 then
			if prev.mode == mode and prev.cur == cur then
				from = prev.eid
			else
				SayOnce("terms:" .. prev.eid, L.LOTTERY_TERMS_REFUND)
				return false, "terms"
			end
		end
	end
	local eid = Arena.NewId("L", function(id) return type(M.Has) == "function" and M.Has(id) == true end)
	if not eid then return false, "id" end
	local fee = Lottery.FeeBp(mode, cur)
	local spec = { drawAt = lockAt, bank = bank, cur = cur, mode = mode,
		carry = from and { from = from, copper = carry } or nil }
	known[eid] = { mode = mode, lockAt = lockAt, bank = bank }
	local ok, a, b = pcall(M.OpenLottery, eid, spec)
	if not ok or a == false then
		known[eid] = nil
		ns.Log("lottery day not opened: %s", tostring(ok and b or a))
		return false, ok and b or a
	end
	if prev then
		lot.history = type(lot.history) == "table" and lot.history or {}
		table.insert(lot.history, 1, { eid = prev.eid, lockAt = prev.lockAt, prizes = prev.prizes, head = prev.head, pot = prev.pot,
			rollover = prev.rollover, void = prev.void, mode = prev.mode, cur = prev.cur })
		while #lot.history > Lottery.HISTORY_MAX do table.remove(lot.history) end
	end
	lot.day = { eid = eid, lockAt = lockAt, mode = mode, cur = cur, fee = fee, bank = bank, carry = carry, from = from, opened = now,
		caller = ns.me }
	-- (The roll lines are read from here on, so the first roll after the draw time is never missed.)
	Watch()
	ns.Print(L.LOTTERY_OPENED:format(Lottery.WhenText(lockAt)))
	ns.Fire("LOTTERY_OPEN", eid)
	Arena.Changed()
	return true
end

-- A day whose draw's hour went by with no draw declared (the owner's call, 2026-10-04): void, every
-- stake back to its wallet. Voided here once (at the hour's end, or at this client's next login);
-- a bank online since the draw time voids it as well VOID_SLACK later (its event's noResult),
-- should this client be away by then.
local function Late(day)
	if day.voidAsked then return false end
	day.voidAsked = true
	local M = ns.Markets
	local ok, a, b = pcall(M.Void, day.eid, Lottery.IDX, "G")
	if not ok or a == false then
		ns.Log("lottery %s not voided: %s", tostring(day.eid), tostring(ok and b or a))
		return false
	end
	day.declared, day.void, day.declaredAt = true, true, Arena.Now()
	ns.Print(L.LOTTERY_VOID_LATE)
	Arena.Changed()
	return true
end

-- The caller's cycle (every TICK while his lottery is on or a day of his is not drawn yet).
Cycle = function()
	if Arena.Off() then return Involve() end
	local lot = Book()
	if not lot then return Involve() end
	local day = lot.day
	local now = Arena.Now()
	if day and not day.declared then
		local v = Lottery.Read(day.eid)
		if v and v.state == "void" then
			day.declared, day.void, day.declaredAt = true, true, now
		elseif now >= (day.lockAt or math.huge) then
			if not day.due then
				day.due = now
				Watch()
				local text = lot.roller == "bank" and L.LOTTERY_DRAW_DUE_BANK or L.LOTTERY_DRAW_DUE
				ns.Print(text)
				ns.Alert("arena", "loud", { text = text, key = "arena:lottery:" .. day.eid,
					open = function() return not day.declared end, show = function() Lottery.Open() end })
			end
			-- (A declaration the markets refused before: again.)
			if day.prizes and #day.prizes == Lottery.PRIZES then Declare(day) end
			if not day.declared and now >= day.lockAt + Lottery.DRAW_WINDOW then Late(day) end
			return Involve()
		else
			return Involve()
		end
	end
	if lot.schedule and lot.schedule.on == true then OpenNext(lot) end
	return Involve()
end
Lottery.Cycle = function() return Cycle() end

-- The King's schedule: t = { on = bool, at = minutes after midnight on the draw's clock (Lottery.Zone),
-- roller = "king" | "bank" }.
function Lottery.SetSchedule(t)
	if type(t) ~= "table" then return false, "shape" end
	local lot = Book()
	if not lot then return false, "king" end
	-- (The day's market never opens while the gate says no: the schedule is not turned on.)
	if t.on == true and not Wagers() then
		ns.Print(L.COMPLIANCE_WAIT)
		return false, "compliance"
	end
	local s = type(lot.schedule) == "table" and lot.schedule or { on = false, at = Lottery.DEFAULT_AT }
	if t.at ~= nil then
		local at = tonumber(t.at)
		if not at or at ~= floor(at) or at < 0 or at >= 1440 then return false, "time" end
		s.at = at
	end
	if t.on ~= nil then s.on = t.on == true end
	if t.roller ~= nil then lot.roller = t.roller == "bank" and "bank" or "king" end
	s.by, s.t = ns.me, Arena.Now()
	lot.schedule = s
	if t.on ~= nil or t.at ~= nil then
		if s.on then
			ns.Print(L.LOTTERY_SCHEDULE_ON:format(Lottery.MinutesText(s.at) .. " " .. Lottery.ZoneText(), lot.roller == "bank" and L.LOTTERY_ROLLER_BANK or L.LOTTERY_ROLLER_KING))
		else
			ns.Print(L.LOTTERY_SCHEDULE_OFF)
		end
	end
	Involve()
	if s.on then Cycle() end
	local day = lot.day
	if day and not day.declared then Watch() end
	Arena.Changed()
	return true
end

---------------------------------------------------------------------------
-- The draw: the Roll button
---------------------------------------------------------------------------

-- Whether this client may roll the current draw now: the caller's client (his draw is due and
-- he rolls it), or the lottery's bank's (a draw is due and it is the bank).
function Lottery.CanDraw()
	if Arena.Off() then return false, "off" end
	if not Wagers("payout") then return false, "compliance" end
	local lot = Book()
	local day = lot and lot.day
	local now = Arena.Now()
	if day and not day.declared then
		if now < (day.lockAt or math.huge) then return false, "due" end
		if day.prizes and #day.prizes >= Lottery.PRIZES then return false, "drawn" end
		if now >= day.lockAt + Lottery.DRAW_WINDOW then return false, "late" end
		-- (Who rolls is fixed by the first prize: the King's choice until then.)
		local roller = day.rolledBy or (lot.roller == "bank" and day.bank or ns.me)
		if not Same(roller, ns.me) then return false, "roller" end
		return true
	end
	local eid = Lottery.Current()
	local d = eid and Lottery.Read(eid)
	if not d then return false, lot and "none" or "king" end
	if d.prizes then return false, "drawn" end
	if not Same(ns.me, d.bank) then return false, "king" end
	if now < (d.lockAt or math.huge) then return false, "due" end
	if d.state == "void" or now >= d.lockAt + Lottery.DRAW_WINDOW then return false, "late" end
	return true
end

-- One prize: /roll 1-10000 from the player's own click (RandomRoll is not protected). A typed
-- /roll 10000 counts the same: the server's line is what is read. Told to type it when the game
-- showed no line soon after.
function Lottery.Draw()
	local ok, why = Lottery.CanDraw()
	if not ok then return false, why end
	local lot = Book()
	local day = lot and lot.day
	if day and day.declared then day = nil end
	-- (The bank's own board: its rolls, as a witness sees them.)
	if not day then Lottery.WatchDraw(true) end
	Watch()
	local before = day and day.prizes and #day.prizes or (witness and #witness.prizes or 0)
	local rolled = type(RandomRoll) == "function" and pcall(RandomRoll, Lottery.ROLL[1], Lottery.ROLL[2]) -- gp:arena-clicks
	if not rolled then
		ns.Print(L.LOTTERY_ROLL_TYPE)
		return false, "blocked"
	end
	Arena.After(Lottery.ROLL_WAIT, "lottery roll check", function()
		local now = day and day.prizes and #day.prizes or (witness and #witness.prizes or 0)
		if now <= before then ns.Print(L.LOTTERY_ROLL_TYPE) end
	end)
	return true
end

-- The board of a witness asks for the roll lines while a draw is due and not drawn.
function Lottery.WatchDraw(on)
	if not on then witness = nil return end
	local eid = Lottery.Current()
	local d = eid and Lottery.Read(eid)
	if d and not d.prizes and d.lockAt and Arena.Now() >= d.lockAt then
		if not witness or witness.eid ~= eid then witness = { eid = eid, prizes = {} } end
		Watch()
	end
end

---------------------------------------------------------------------------
-- The day for the screens
---------------------------------------------------------------------------

-- The latest day this client knows: the caller's own, or the markets' public ones.
function Lottery.Current()
	local days = Lottery.Days()
	local last = days[#days]
	return last and last.eid or nil
end

-- Every lottery day this client knows (the caller's own and the markets' public ones), oldest
-- draw first.
function Lottery.Days()
	local out, seen = {}, {}
	local lot = Book()
	local own = lot and lot.day
	if own and own.eid then
		out[1], seen[own.eid] = { eid = own.eid, lockAt = own.lockAt or 0 }, true
	end
	local M = ns.Markets
	if type(M) == "table" and type(M.Public) == "function" then
		local ok, list = pcall(M.Public)
		for _, e in ipairs(ok and type(list) == "table" and list or {}) do
			local eid = type(e) == "table" and e.eid or e
			if type(eid) == "string" and eid:sub(1, 1) == "L" and not seen[eid] and EventOf(eid) then
				seen[eid] = true
				local at = type(e) == "table" and tonumber(e.lockAt) or nil
				if not at then
					local d = Lottery.Read(eid)
					at = d and d.lockAt
				end
				if at then out[#out + 1] = { eid = eid, lockAt = at } end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.lockAt ~= b.lockAt then return a.lockAt < b.lockAt end
		return a.eid < b.eid
	end)
	return out
end

-- The latest day drawn (its five prizes declared) other than `except`: the board keeps the last
-- result in sight while the next day takes bets.
function Lottery.LastDrawn(except)
	local days = Lottery.Days()
	for i = #days, 1, -1 do
		local eid = days[i].eid
		if eid ~= except then
			local d = Lottery.Read(eid)
			if d and d.prizes then return eid end
		end
	end
	return nil
end

-- This character's tickets on a day, from the markets: { { o, s, state }, ... }.
function Lottery.Mine(eid)
	local M = ns.Markets
	local out = {}
	if type(eid) ~= "string" or type(M) ~= "table" or type(M.Tickets) ~= "function" then return out end
	local ok, list = pcall(M.Tickets, { eid = eid })
	for _, t in ipairs(ok and type(list) == "table" and list or {}) do
		if type(t) == "table" and (t.eid == nil or t.eid == eid) then
			local o = tonumber(t.o or t.outcome)
			local s = tonumber(t.stake) or (tonumber(t.silver) and tonumber(t.silver) * 100)
			if o and s and t.state ~= "refused" then
				out[#out + 1] = { o = o, s = floor(s), state = t.state,
					payout = type(t.payout) == "number" and floor(t.payout) or nil, id = t.id }
			end
		end
	end
	return out
end

-- Lottery.Today(): the day in view (the latest), everything the board and the overlay show.
--   { eid, name, drawAt (= lockAt), state = "none"|"open"|"closed"|"drawing"|"drawn"|"settled"|"void",
--     mode, cur, fee, bank, caller, pool (stakes), rollover (the pot rolled in), carry (the same),
--     pot, count, bets = { [beast] = { pool, count } }, prizes (so far), head, live (prizes seen
--     from the rolls, not declared yet), winners, passes (what it rolls on), refund, mine, myStake,
--     myPayout, caller view: isCaller, schedule, roller, canDraw, why }
function Lottery.Today() return Lottery.Day(Lottery.Current()) end
-- The same for one day, by its eid.
function Lottery.Day(eid)
	local lot = Book()
	local own = lot and lot.day
	local day = eid and Lottery.Read(eid)
	if not day and own and own.eid == eid then
		day = { eid = eid, lockAt = own.lockAt, bank = own.bank, cur = own.cur, mode = own.mode, fee = own.fee, bets = {}, pool = 0,
			count = 0, carry = own.carry or 0, from = own.from, state = own.declared and "drawn" or "open", caller = ns.me }
		for o = 1, Lottery.OUTCOMES do day.bets[o] = { pool = 0, count = 0 } end
		day.pot = day.carry
		if day.state == "open" and Arena.Now() >= (day.lockAt or math.huge) then day.state = "closed" end
	end
	if not day then
		return { state = "none", name = L.LOTTERY_NAME, bets = {}, mine = {}, isCaller = lot ~= nil, schedule = Lottery.Schedule() }
	end
	day.name, day.drawAt, day.rollover = L.LOTTERY_NAME, day.lockAt, day.carry
	if not day.prizes then
		local p = own and own.eid == eid and own.prizes or (witness and witness.eid == eid and witness.prizes) or nil
		if p and #p > 0 then
			day.prizes, day.live = {}, true
			for i, x in ipairs(p) do day.prizes[i] = x end
		end
	end
	if day.prizes and #day.prizes > 0 then
		day.head = Lottery.BeastOf(day.prizes[1])
		if day.live and #day.prizes < Lottery.PRIZES and (day.state == "open" or day.state == "closed") then day.state = "drawing" end
		if #day.prizes == Lottery.PRIZES and (day.state == "open" or day.state == "closed") then day.state = "drawn" end
		local drawn, winners = {}, 0
		for _, prize in ipairs(day.prizes) do drawn[Lottery.BeastOf(prize)] = true end
		for animal in pairs(drawn) do winners = winners + (day.bets[animal] and day.bets[animal].count or 0) end
		day.winners = winners
		if day.state == "settled" and ns.Markets and type(ns.Markets.Carry) == "function" then
			-- (Its first result alone: Markets.Carry also returns the source id, tonumber's base otherwise.)
			day.passes = tonumber((ns.Markets.Carry(eid))) or 0
		end
	end
	day.mine = Lottery.Mine(eid)
	day.myStake = 0
	for _, t in ipairs(day.mine) do day.myStake = day.myStake + t.s end
	if #day.mine > 0 then day.myPayout = Lottery.PayoutOf(day.mine) end
	day.isCaller = lot ~= nil and (own ~= nil and own.eid == eid or Lottery.IsCaller(ns.me, day.mode))
	day.schedule = lot and Lottery.Schedule() or nil
	day.roller = lot and lot.roller == "bank" and "bank" or "king"
	day.canDraw, day.why = Lottery.CanDraw()
	day.canBet, day.betWhy = Lottery.CanBet(1, Lottery.MinSilver(), day)
	-- (The draw's hour went by with no draw: void, every stake back, once the void is heard.)
	day.late = (day.state == "closed" or day.state == "drawing") and day.lockAt ~= nil and Arena.Now() >= day.lockAt + Lottery.DRAW_WINDOW
	return day
end

-- The past draws the caller keeps (newest first).
function Lottery.History()
	local lot = Book()
	return lot and type(lot.history) == "table" and lot.history or {}
end

-- The King's overlay (the screens' Overlay.lua): the slip and the head, fixed words and numbers only.
function Lottery.OverlayView()
	local d = Lottery.Today()
	local rows = {}
	for i = 1, Lottery.PRIZES do
		local p = d.prizes and d.prizes[i]
		local b = p and Lottery.Beast(Lottery.BeastOf(p))
		rows[i] = { place = L["LOTTERY_PRIZE_" .. i], number = p and Lottery.Text(p) or "----", beast = b and b.n or nil,
			label = b and Lottery.Label(b.n) or "", art = b and b.art or nil }
	end
	local head = d.head and Lottery.Beast(d.head)
	return { title = L.LOTTERY_NAME, eid = d.eid, state = d.state, drawAt = d.drawAt, pot = d.pot, carry = d.carry, cur = d.cur,
		rows = rows, head = head and head.n or nil, headLabel = head and Lottery.Label(head.n) or nil, headArt = head and head.art or nil,
		winners = d.winners, passes = d.passes, rehearsal = d.mode == "T" }
end

---------------------------------------------------------------------------
-- Betting
---------------------------------------------------------------------------

-- Whether this character may bet `silver` on `beast` now, and why not.
function Lottery.CanBet(beast, silver, day)
	if Arena.Off() then return false, "off" end
	if not Wagers() then return false, "compliance" end
	local M = ns.Markets
	if type(M) ~= "table" or type(M.Bet) ~= "function" then return false, "markets" end
	if not day then
		local eid = Lottery.Current()
		day = eid and (Lottery.Read(eid) or nil)
	end
	if not day or not day.eid then return false, "none" end
	if day.state ~= "open" or Arena.Now() >= (day.lockAt or 0) then return false, "closed" end
	beast = tonumber(beast)
	if not beast or beast ~= floor(beast) or beast < 1 or beast > Lottery.OUTCOMES then return false, "beast" end
	silver = tonumber(silver)
	if not silver or silver ~= floor(silver) or silver < Lottery.MinSilver() or silver * 100 > ns.ArenaMath.MAX_COPPER then return false, "stake" end
	if Excluded(ns.me, day) then return false, "caller" end
	if not Arena.RulesAccepted() then return false, "rules" end
	return true
end

-- A bet from the wallet: the slip goes to the lottery's bank (Markets.Bet). The ticket, or nil, why.
function Lottery.Bet(beast, silver)
	local eid = Lottery.Current()
	local day = eid and Lottery.Read(eid)
	local ok, why = Lottery.CanBet(beast, silver, day)
	if not ok then return nil, why end
	local okBet, t, why2 = pcall(ns.Markets.Bet, day.eid, Lottery.IDX, floor(beast), floor(silver))
	if not okBet then return nil, "error" end
	if not t then return nil, why2 or "refused" end
	Arena.Changed()
	return t
end

function Lottery.WhyText(why) return L["LOTTERY_WHY_" .. tostring(why):upper()] end

---------------------------------------------------------------------------
-- The winners: the Games tab's Lottery rankings (latest and biggest)
---------------------------------------------------------------------------

-- Only a day's bank knows whose tickets they are (the ledger on the channel carries blinded codes),
-- so its bank publishes the day's winners once the day is settled: LW, its eid, its time and up to
-- WINNERS_DAY rows "name:beast:copper b36", each an account that came out ahead that day, by its
-- net gain over its tickets (paid less staked), with the beast of its best-paying ticket, the
-- biggest first. Every client keeps the last WINNERS_DAYS days it heard, from that day's own bank
-- only, and Lottery.Winners() reads them; the Games tab shows them (ArenaHome's RankingLines).
-- A name next to an amount is what the markets otherwise never put on the channel, so a bank
-- publishes only while the King's rankings switch is on (rankPub, ArenaHome.RankingsPublic): the
-- days it settled with the switch off go out when he turns it on, and before that nobody, his
-- staff included, sees a Lottery winner.
Lottery.WINNERS_DAY = 5     -- rows a day publishes
Lottery.WINNERS_DAYS = 30   -- days a client keeps
Lottery.WINNERS_SHOWN = 5   -- rows of each list
Lottery.WINNERS_SENT_KEEP = Lottery.WINNERS_DAYS * 86400 -- a bank remembers a day it published this long after its draw

-- A settled day's winners, on its bank's client: { { name, beast, amount } }, the biggest first;
-- nil when this client cannot say (not the bank, the wallet does not have it settled).
function Lottery.DayWinners(eid)
	local W = ns.Wallet
	if type(W) ~= "table" or type(W.Market) ~= "function" or type(W.Bets) ~= "function" or type(W.Facts) ~= "function" then return nil end
	local okM, m = pcall(W.Market, eid, Lottery.IDX)
	if not okM or type(m) ~= "table" or not m.settled or m.result == "V" or type(m.res) ~= "table" or type(m.res.payouts) ~= "table" then return nil end
	local okB, bets = pcall(W.Bets, eid, Lottery.IDX)
	if not okB or type(bets) ~= "table" then return nil end
	local by, order = {}, {}
	for i, bet in ipairs(bets) do
		local paid, stake, acct = tonumber(m.res.payouts[i]) or 0, tonumber(bet.s) or 0, bet.acct
		if acct ~= nil then
			local r = by[acct]
			if not r then r = { paid = 0, stake = 0, best = -1 }; by[acct] = r; order[#order + 1] = acct end
			r.paid, r.stake = r.paid + paid, r.stake + stake
			if paid > r.best then r.best, r.beast = paid, tonumber(bet.o) end
		end
	end
	local out = {}
	for _, acct in ipairs(order) do
		local r = by[acct]
		local okF, facts = pcall(W.Facts, acct)
		local name = okF and type(facts) == "table" and facts.name or nil
		if r.paid > r.stake and type(name) == "string" and name ~= "" and Animal(r.beast) then
			out[#out + 1] = { name = ns.FullName(name), beast = r.beast, amount = floor(r.paid - r.stake) }
		end
	end
	table.sort(out, function(a, b)
		if a.amount ~= b.amount then return a.amount > b.amount end
		return a.name:lower() < b.name:lower()
	end)
	while #out > Lottery.WINNERS_DAY do table.remove(out) end
	return out
end

local function WinnersStore(mode, make)
	local db = ns.db
	if type(db) ~= "table" then return nil end
	if type(db.lotteryWinners) ~= "table" then
		if not make then return nil end
		db.lotteryWinners = {}
	end
	mode = mode == "T" and "T" or "L"
	if type(db.lotteryWinners[mode]) ~= "table" then
		if not make then return nil end
		db.lotteryWinners[mode] = {}
	end
	return db.lotteryWinners[mode]
end

local function WinnersBody(eid, t, rows)
	local parts = {}
	for i, r in ipairs(rows) do
		if i > Lottery.WINNERS_DAY then break end
		parts[i] = ("%s:%d:%s"):format(ns.ArenaFights.Wire(r.name), r.beast, Arena.B36(r.amount))
	end
	return table.concat({ eid, Arena.B36(t), #parts > 0 and table.concat(parts, ";") or "-" }, "~")
end

-- A day's winners heard (LW), or this bank's own: kept when it comes from that day's bank, for a
-- day this client knows drawn, every row a beast of that draw and no more than the day's pot.
function Lottery.TakeWinners(sender, mode, body)
	local eid, t, rows = Arena.Fields(body, 3)
	if not rows then return false, "shape" end
	t = Arena.N(t, 0, 4294967295)
	if not t or t > Arena.Now() + 60 then return false, "time" end
	if not EventOf(eid) then return false, "day" end
	local day = Lottery.Read(eid)
	if not day or not day.prizes then return false, "day" end
	if (day.mode or "L") ~= mode then return false, "mode" end
	if not Same(sender, day.bank) then return false, "sender" end
	local drawn = {}
	for _, p in ipairs(day.prizes) do drawn[Lottery.BeastOf(p)] = true end
	local list = {}
	if rows ~= "-" then
		for part in rows:gmatch("[^;]+") do
			local name, beast, amount = part:match("^([^:]+):(%d+):([0-9a-z]+)$")
			local full = name and ns.ArenaFights.Unwire(name, sender)
			beast, amount = tonumber(beast), amount and Arena.N(amount, 1, MAX_POOL)
			if not full or not beast or not drawn[beast] or not amount or amount > (day.pot or 0) then return false, "row" end
			if #list >= Lottery.WINNERS_DAY then return false, "rows" end
			list[#list + 1] = { name = full, beast = beast, amount = amount }
		end
	end
	local s = WinnersStore(mode, true)
	if not s then return false, "db" end
	local had = s[eid]
	if type(had) == "table" and (tonumber(had.t) or 0) >= t then return false, "older" end
	s[eid] = { t = t, at = day.lockAt, bank = ns.FullName(sender), rows = list }
	-- (The newest WINNERS_DAYS days kept.)
	local days = {}
	for id, d in pairs(s) do if type(d) == "table" then days[#days + 1] = { id = id, at = tonumber(d.at) or 0 } end end
	table.sort(days, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.id > b.id end)
	for i = Lottery.WINNERS_DAYS + 1, #days do s[days[i].id] = nil end
	Arena.Changed()
	return true
end
local function OnWinners(dist, sender, mode, body)
	local ok, why = Lottery.TakeWinners(sender, mode, body)
	if not ok then ns.Log("lottery winners from %s refused: %s", tostring(sender), tostring(why)) end
end
ns.Comm.Handle("LW", ns.Arena.Handle("LW", OnWinners))

-- On a bank's client, while the King's rankings switch is on: each of its days its wallet has
-- settled and not published yet goes out once (and is taken here as everyone takes it), when the
-- bank settles it (MARKETS_SETTLED) or at a later change (the switch turned on, a send refused
-- before). Nothing on any other client. What went out is remembered by the day's draw time,
-- WINNERS_SENT_KEEP, never by a count: the markets keep a day a week after it was last heard,
-- however many there are, and a day still known but no longer remembered would go out again at
-- every change. A day drawn longer ago than that is not published.
local function PublishWinners(days)
	local R = Roles()
	if not (R and type(R.IsBank) == "function") or not (R.IsBank(ns.me, "L") or R.IsBank(ns.me, "T")) then return end
	local s = type(R.Settings) == "function" and R.Settings() or nil
	if type(s) ~= "table" or s.rankPub ~= 1 then return end
	local now = Arena.Now()
	local since = now - Lottery.WINNERS_SENT_KEEP
	for _, item in ipairs(days) do
		local day = Lottery.Read(item.eid)
		local mode = day and (day.mode or "L")
		-- (Settled is the wallet's word, Lottery.DayWinners: the bank's own book may say so later.)
		if day and day.prizes and (day.lockAt or 0) > since and Same(ns.me, day.bank) and R.IsBank(ns.me, mode) then
			local store = Arena.Store(mode)
			local sent = type(store) == "table" and (type(store.lotteryWinnersSent) == "table" and store.lotteryWinnersSent or {}) or nil
			if sent and not sent[day.eid] then
				local rows = Lottery.DayWinners(day.eid)
				if rows then
					local body = WinnersBody(day.eid, Arena.Now(), rows)
					local okSend = Arena.Send("LW", mode, body, { key = "lw:" .. day.eid })
					if okSend then
						store.lotteryWinnersSent = sent
						sent[day.eid] = day.lockAt
						-- (The days drawn within WINNERS_SENT_KEEP remembered.)
						for id, at in pairs(sent) do
							if (tonumber(at) or 0) <= since then sent[id] = nil end
						end
						Lottery.TakeWinners(ns.me, mode, body)
					end
				end
			end
		end
	end
end
Lottery.PublishWinners = function() return PublishWinners(Lottery.Days()) end
ns.On("MARKETS_SETTLED", function(eid)
	if type(eid) ~= "string" or eid:sub(1, 1) ~= "L" or Arena.Off() then return end
	ns.SafeCall("lottery winners", PublishWinners, { { eid = eid } })
end)

-- The Games tab's lists (ArenaHome's Data.GamesRanking("lottery")): { latest = { { name, day,
-- beast, amount } } (the newest days' winners, newest first), biggest = { { name, amount, day,
-- beast } } (the biggest single-draw wins of the days kept) }. mode: "L" (a test build's "T").
function Lottery.Winners(mode)
	mode = mode or (Arena.TestBuild() and "T" or "L")
	local s = WinnersStore(mode, false)
	local days, latest, all = {}, {}, {}
	for eid, d in pairs(s or {}) do
		if type(d) == "table" and type(d.rows) == "table" then days[#days + 1] = { eid = eid, at = tonumber(d.at) or 0, rows = d.rows } end
	end
	table.sort(days, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.eid > b.eid end)
	for _, d in ipairs(days) do
		local when = ""
		if type(date) == "function" and d.at > 0 then
			-- (The day of the draw on the draw's clock, as every other line names its time.)
			local ok, v = pcall(date, "!%m-%d", d.at + floor(Lottery.ZoneOffset(d.at)) * 60)
			when = ok and type(v) == "string" and v or ""
		end
		for _, r in ipairs(d.rows) do
			local row = { name = r.name, day = when, beast = Lottery.Label(r.beast), amount = r.amount, eid = d.eid }
			if #latest < Lottery.WINNERS_SHOWN then latest[#latest + 1] = row end
			all[#all + 1] = row
		end
	end
	-- (Ties: the newer day first, then the name; the list is the same on every client that heard the same days.)
	local rank = {}
	for i, d in ipairs(days) do rank[d.eid] = i end
	table.sort(all, function(a, b)
		if a.amount ~= b.amount then return a.amount > b.amount end
		if rank[a.eid] ~= rank[b.eid] then return rank[a.eid] < rank[b.eid] end
		return a.name:lower() < b.name:lower()
	end)
	local biggest = {}
	for i = 1, math.min(Lottery.WINNERS_SHOWN, #all) do biggest[i] = all[i] end
	return { latest = latest, biggest = biggest }
end

---------------------------------------------------------------------------
-- The result, said once on every client that hears it
---------------------------------------------------------------------------

local said = {}
local function Heard(eid)
	if said[eid] then return true end
	local db = ns.db
	local list = db and type(db.lotteryHeard) == "table" and db.lotteryHeard or nil
	for _, e in ipairs(list or {}) do if e == eid then said[eid] = true return true end end
	return false
end
local function Remember(eid)
	said[eid] = true
	local db = ns.db
	if not db then return end
	if type(db.lotteryHeard) ~= "table" then db.lotteryHeard = {} end
	table.insert(db.lotteryHeard, 1, eid)
	while #db.lotteryHeard > Lottery.HEARD_MAX do table.remove(db.lotteryHeard) end
end

-- The compact settlement rule shown beside the five drawn positions. Exact personal payouts come
-- from the wallet ticket after settlement; public pools alone cannot reproduce ticket-id rounding.
function Lottery.ShareText(day)
	if not day or not day.prizes or #day.prizes ~= Lottery.PRIZES then return nil end
	return L.LOTTERY_FIVE_PLACE_SUMMARY
end

-- The lines for a drawn day (nil until its five prizes are declared): the head and the pot (totals
-- only, no name), the five prizes, and this player's own line.
function Lottery.ResultLines(day)
	if not day or not day.prizes or #day.prizes ~= Lottery.PRIZES or day.live then return nil end
	local lines = { L.LOTTERY_ANNOUNCE_FIVE:format(L.LOTTERY_NAME) }
	lines[2] = L.LOTTERY_PRIZES_LINE:format(Lottery.PrizesText(day.prizes))
	if day.mine and #day.mine > 0 then
		if day.myPayout and day.myPayout > 0 then
			lines[3] = L.LOTTERY_YOURS_WON:format(Lottery.Money(day.myPayout, day.cur))
		elseif day.myPayout ~= nil then
			lines[3] = L.LOTTERY_YOURS_LOST
		else
			local drawn, hit = {}, false
			for _, prize in ipairs(day.prizes) do drawn[Lottery.BeastOf(prize)] = true end
			for _, ticket in ipairs(day.mine) do if drawn[ticket.o] then hit = true break end end
			lines[3] = hit and L.LOTTERY_YOURS_PENDING or L.LOTTERY_YOURS_LOST
		end
	end
	if day.mode == "T" then
		for i, line in ipairs(lines) do lines[i] = L.LOTTERY_REHEARSAL:format(line) end
	end
	return lines
end

-- Every ARENA_CHANGED: each day drawn and not said yet here is said once, oldest first (a result
-- and the next day's sheet may arrive together); a player with a ticket on it gets an alert. A
-- result heard long after its draw is only shown on the board.
local function Say(eid)
	local day = Lottery.Day(eid)
	local lines = day.eid == eid and Lottery.ResultLines(day)
	if not lines then return end
	Remember(eid)
	if witness and witness.eid == eid then
		-- (What this client saw of the rolls, against what was declared: kept in the log for an audit.)
		local seen = Lottery.ResultText(witness.prizes)
		if seen and seen ~= Lottery.ResultText(day.prizes) then
			ns.Log("lottery %s: declared %s, rolls seen here %s", eid, tostring(Lottery.ResultText(day.prizes)), seen)
		end
		witness = nil
	end
	if day.lockAt and Arena.Now() - day.lockAt > Lottery.FRESH then return end
	for _, line in ipairs(lines) do ns.Print(line) end
	if day.mine and #day.mine > 0 then
		ns.Alert("arena", "soft", { text = lines[3], key = "arena:lottery:result:" .. eid, what = lines[1] })
	end
	ns.Fire("LOTTERY_RESULT", eid)
end
-- A void day with this player's tickets (its draw's hour went by, or the bank voided it): said
-- once, as a result is; every stake goes back to the wallet.
local function SayVoid(day)
	Remember(day.eid)
	if day.lockAt and Arena.Now() - day.lockAt > Lottery.FRESH then return end
	if #Lottery.Mine(day.eid) == 0 then return end
	local text = L.LOTTERY_VOID_MINE:format(Lottery.WhenText(day.lockAt))
	if day.mode == "T" then text = L.LOTTERY_REHEARSAL:format(text) end
	ns.Print(text)
	ns.Alert("arena", "soft", { text = text, key = "arena:lottery:result:" .. day.eid, what = text })
end

---------------------------------------------------------------------------
-- The reminders (the owner's call, 2026-10-04): 60, 15 and 5 minutes before a draw, and at its time
---------------------------------------------------------------------------

-- Every member who knows the day that takes bets hears each once: whoever has no ticket on it, the
-- last bets; a bettor, the draw coming; its caller and its bank, the roll coming (and the 5 minutes'
-- as an alert); at the draw time a bettor hears that the results come out now (an alert). Never one
-- that is past: a login 18 minutes before the draw hears the 15 and the 5. One C_Timer.NewTimer for
-- the next of them, armed again at each change (the draw time travels in the day's sheet).
local REMIND_LATE = 30 -- seconds a reminder may still be said after its moment
local remind      -- { eid, at, mark, timer }: the one armed
local reminded = {} -- ["<eid>:<mark>"] = true: said, or past, this session
local function Disarm()
	if remind and remind.timer and remind.timer.Cancel then remind.timer:Cancel() end
	remind = nil
end
local Arm -- (below)

-- The reminder `mark` seconds before the draw of eid (0: the draw time), said now: its line, or nil.
function Lottery.Remind(eid, mark)
	mark = tonumber(mark) or 0
	reminded[tostring(eid) .. ":" .. mark] = true
	if remind and remind.eid == eid and remind.mark == mark then remind = nil end
	local d = not Arena.Off() and Lottery.Read(eid) or nil
	local text, alert
	if d and d.lockAt and not d.prizes and d.state ~= "void" then
		local left = d.lockAt - Arena.Now()
		local roller = Lottery.IsCaller(ns.me, d.mode) or Same(ns.me, d.bank)
		local mine = #Lottery.Mine(eid) > 0
		if mark > 0 and left > 0 then
			local minutes, when = max(1, math.ceil(left / 60)), Lottery.WhenText(d.lockAt)
			if roller then
				text, alert = L.LOTTERY_REMIND_ROLL:format(minutes, when), mark == Lottery.REMIND[#Lottery.REMIND]
			elseif mine then
				text = L.LOTTERY_REMIND_MINE:format(minutes, when)
			elseif not Excluded(ns.me, d) then
				text = L.LOTTERY_REMIND_BET:format(minutes, when)
			end
		elseif mark == 0 and left <= 0 and left > -Lottery.DRAW_WINDOW and mine and not roller then
			text, alert = L.LOTTERY_REMIND_NOW, true
		end
	end
	if text then
		if d.mode == "T" then text = L.LOTTERY_REHEARSAL:format(text) end
		ns.Print(text)
		if alert then
			-- (A raid warning and its sound, never a window opened by itself.)
			ns.Alert("arena", "soft", { text = text, what = text, key = "arena:lottery:remind:" .. eid,
				open = function() local v = Lottery.Read(eid) return v ~= nil and not v.prizes and v.state ~= "void" end })
		end
		ns.Fire("LOTTERY_REMIND", eid, mark)
	end
	Arm()
	return text
end

-- The next reminder of the latest day, armed (or nothing, with no day taking bets).
Arm = function(days)
	if Arena.Off() or (ns.IsMember and not ns.IsMember()) then return Disarm() end
	days = days or Lottery.Days()
	local last = days[#days]
	local d = last and Lottery.Read(last.eid)
	local now = Arena.Now()
	local at, mark
	-- (The draw time's own a minute on: the sheet may say closed a moment before its timer runs.)
	-- (A reminder due this very moment is still armed, at once: a change heard the same second as
	-- its timer would otherwise put it by.)
	if d and d.lockAt and not d.prizes and (d.state == "open" or (d.state == "closed" and now < d.lockAt + REMIND_LATE)) then
		for _, s in ipairs(Lottery.REMIND) do
			if d.lockAt - s > now - REMIND_LATE and not reminded[d.eid .. ":" .. s] then at, mark = d.lockAt - s, s break end
		end
		if not at and not reminded[d.eid .. ":0"] then at, mark = d.lockAt, 0 end
	end
	if not at then return Disarm() end
	if remind and remind.eid == d.eid and remind.at == at and remind.mark == mark then return end
	Disarm()
	if not (C_Timer and type(C_Timer.NewTimer) == "function") then return end
	local eid = d.eid
	remind = { eid = eid, at = at, mark = mark }
	remind.timer = C_Timer.NewTimer(max(0, at - now), function() ns.SafeCall("lottery reminder", Lottery.Remind, eid, mark) end)
end
Lottery.ArmReminder = function() return Arm() end
function Lottery.Reminder() return remind and { eid = remind.eid, at = remind.at, mark = remind.mark } or nil end

local function OnChanged()
	if Arena.Off() or (ns.IsMember and not ns.IsMember()) then return Disarm() end
	local days = Lottery.Days()
	-- (A bank's own settled days: their winners go out once.)
	PublishWinners(days)
	Arm(days)
	for _, d in ipairs(days) do
		-- (A day with no result yet costs one look at the markets.)
		if not Heard(d.eid) then
			local v = Lottery.Read(d.eid)
			if v and v.prizes then Say(d.eid) elseif v and v.state == "void" then SayVoid(v) end
		end
	end
end
Lottery.OnChanged = OnChanged
ns.On("ARENA_CHANGED", function() ns.SafeCall("lottery changed", OnChanged) end)

---------------------------------------------------------------------------
-- The first use, the screens, the actions and /oly arena lottery
---------------------------------------------------------------------------

-- The explanation's paragraphs (the How to play panel shows them any time).
function Lottery.Intro()
	return { title = L.LOTTERY_NAME, paragraphs = { L.LOTTERY_INTRO_1, L.LOTTERY_INTRO_2, L.LOTTERY_INTRO_3, L.LOTTERY_INTRO_4 } }
end
-- The first time the Lottery opens on this account: the full name and the explanation (a pop-up
-- of the board's own, in a casual tone: no King's letter, signed by nobody); nil after.
function Lottery.FirstUse()
	local db = ns.db
	if not db or db.lotteryIntro == Lottery.INTRO then return nil end
	db.lotteryIntro = Lottery.INTRO
	return Lottery.Intro()
end

-- The Lottery's screen: the betting window's Lottery section (the screens' window), or the board's own
-- window while that one is not there.
function Lottery.Open()
	local ok, why = Arena.LoadUI()
	if not ok then return false, why end
	local ui = Arena.ui
	if type(ui) ~= "table" then return false, "window" end
	if type(ui.Toggle) == "function" then
		ns.SafeCall("lottery open", ui.Toggle, "lottery")
		return true
	end
	if type(ui.LotteryWindow) == "function" then
		ns.SafeCall("lottery open", ui.LotteryWindow, true)
		return true
	end
	ns.Print(L.ARENA_NO_WINDOW)
	return false, "window"
end

Arena.Action("lottery.open", nil, function() return Lottery.Open() end)
Arena.Action("lottery.bet", function(beast, silver) return Lottery.CanBet(beast, silver) end,
	function(beast, silver) return Lottery.Bet(beast, silver) end)
Arena.Action("lottery.draw", function() return Lottery.CanDraw() end, function() return Lottery.Draw() end)
Arena.Action("lottery.schedule", function() if Book() then return true end return false, "king" end,
	function(t) return Lottery.SetSchedule(t) end)

Arena.Slash("lottery", function(args)
	args = tostring(args or ""):lower()
	local word, rest = args:match("^(%S*)%s*(.-)%s*$")
	if word == "" then return Lottery.Open() end
	if word == "draw" then
		local ok, why = Arena.Do("lottery.draw")
		if not ok then ns.Print(Lottery.WhyText(why) or tostring(why)) end
		return
	end
	if not Book() then return ns.Print(L.LOTTERY_WHY_KING) end
	if word == "on" then
		local at = rest ~= "" and Lottery.ReadTime(rest) or Lottery.Schedule().at
		if not at then return ns.Print(L.LOTTERY_WHY_TIME) end
		return Lottery.SetSchedule({ on = true, at = at })
	elseif word == "off" then
		return Lottery.SetSchedule({ on = false })
	elseif word == "bank" or word == "me" then
		return Lottery.SetSchedule({ roller = word == "bank" and "bank" or "king" })
	end
	ns.Print(L.LOTTERY_USAGE)
end, L.LOTTERY_HELP)

-- The caller's cycle goes on after a login or a /reload (his schedule is in his realm's store).
ns.On("LOGIN", function()
	ns.SafeCall("lottery reminder", Arm)
	if Involve() then
		local lot = Book()
		local day = lot and lot.day
		if day and not day.declared then Watch() end
	end
end)
