-- The Menagerie Lottery's versioned five-position settlement contract. Run by tests/run.lua.
local H = ...
local test, eq = H.test, H.eq

local ns = {
	L = setmetatable({}, { __index = function(_, key) return key end }),
	Comm = { Handle = function() end },
	Arena = {
		Handle = function(_, fn) return fn end,
		Events = { Register = function() return true end },
		Action = function() return true end,
		Slash = function() return true end,
		B36 = function(n) return tostring(n) end,
		N = function(s, lo, hi)
			local n = tonumber(s)
			return n and n >= (lo or 0) and (not hi or n <= hi) and n or nil
		end,
	},
	On = function() end,
}
assert(loadfile(H.ADDON_DIR .. "ArenaMath.lua"))("Olympus", ns)
assert(loadfile(H.ADDON_DIR .. "Lottery.lua"))("Olympus", ns)
local L, M = ns.Lottery, ns.ArenaMath

local function Ticket(id, animal, stake, who)
	return { id = id, animal = animal, stake = stake, who = who }
end

local function Settle(tickets, draw, carry, feeBp)
	return assert(L.Settle({ version = L.SETTLEMENT_VERSION, tickets = tickets, draw = draw,
		carry = carry or 0, feeBp = feeBp }))
end

local function Sum(list)
	local n = 0
	for _, v in ipairs(list) do n = n + v end
	return n
end

test("Lottery settlement: the contract is explicit and incompatible versions are refused", function()
	eq(L.SETTLEMENT_VERSION, 2)
	local c = { tickets = {}, draw = { 1, 2, 3, 4, 5 }, carry = 0 }
	eq(select(2, L.Settle(c)), "version", "a missing version")
	c.version = 1
	eq(select(2, L.Settle(c)), "version", "the one-head prototype")
	c.version = L.SETTLEMENT_VERSION
	local r = assert(L.Settle(c))
	eq(r.nextCarry, 0); eq(r.fee, 0)
	local wire = assert(L.EncodeResult({ 1, 2, 3, 4, 5 }, 12345))
	assert(wire:find("^L2%.") and not wire:find("^[%w+]+$"), "the old wallet grammar must reject v2")
	local decoded = assert(L.DecodeResult(wire))
	eq(table.concat(decoded.draw, ","), "1,2,3,4,5"); eq(decoded.nextCarry, 12345)
end)

test("Lottery settlement: duplicate animals claim every tranche but every winning stake is refunded once", function()
	local r = Settle({
		Ticket("a", 1, 100, "A"), Ticket("b", 1, 100, "B"), Ticket("c", 2, 100, "C"),
		Ticket("d", 5, 100, "D"), Ticket("z", 9, 600, "Z"),
	}, { 1, 1, 2, 3, 5 })
	eq(r.pool, 1000); eq(r.refunds, 400); eq(r.profitPool, 600)
	eq(r.tranches[1].gross, 300); eq(r.tranches[2].gross, 150)
	eq(r.tranches[3].gross, 90); eq(r.tranches[4].gross, 60); eq(r.tranches[5].gross, 0)
	eq(r.grossProfit, 540); eq(r.fee, 32); eq(r.netProfit, 508); eq(r.nextCarry, 60)
	eq(r.tranches[1].fee, 18); eq(r.tranches[2].fee, 9); eq(r.tranches[3].fee, 5)
	eq(r.refundByTicket[1], 100); eq(r.refundByTicket[2], 100, "the duplicate does not refund twice")
	eq(r.refundByTicket[4], 100, "fifth position refunds")
	eq(r.profitByTicket[4], 0, "fifth position is refund-only")
	eq(r.payouts[1], 312); eq(r.payouts[2], 311, "equal remainder goes to immutable id a")
	eq(r.payouts[3], 185); eq(r.payouts[4], 100); eq(r.payouts[5], 0)
	eq(Sum(r.payouts) + r.fee + r.nextCarry, r.pool)
end)

test("Lottery settlement: largest remainders use draw position and immutable ticket id", function()
	-- Five copper split 50/25/15/10 has tied remainders at positions 1 and 4. Position 1 wins it.
	local none = Settle({ Ticket("z", 9, 5) }, { 1, 2, 3, 4, 5 })
	eq(none.tranches[1].gross, 3); eq(none.tranches[2].gross, 1)
	eq(none.tranches[3].gross, 1); eq(none.tranches[4].gross, 0)
	eq(none.nextCarry, 5, "all four unclaimed tranches roll")

	-- One copper of first-place profit over equal tickets: id a wins it, regardless of input order.
	local draw = { 1, 2, 3, 4, 5 }
	local one = Settle({ Ticket("b", 1, 1), Ticket("a", 1, 1), Ticket("z", 9, 2) }, draw)
	local two = Settle({ Ticket("z", 9, 2), Ticket("a", 1, 1), Ticket("b", 1, 1) }, draw)
	eq(one.tranches[1].gross, 1); eq(one.nextCarry, 1)
	eq(one.byId.a, 2); eq(one.byId.b, 1)
	eq(two.byId.a, 2); eq(two.byId.b, 1, "ledger order cannot change a tied award")
end)

test("Lottery settlement: the 6 percent fee is rounded once, then apportioned across tranches", function()
	local r = Settle({
		Ticket("a", 1, 1), Ticket("b", 2, 1), Ticket("c", 3, 1), Ticket("d", 4, 1), Ticket("z", 9, 100),
	}, { 1, 2, 3, 4, 5 })
	eq(r.refunds, 4); eq(r.profitPool, 100); eq(r.grossProfit, 100)
	eq(r.fee, 6, "floor(100 * 6%) once")
	eq(r.tranches[1].fee, 3); eq(r.tranches[2].fee, 1)
	eq(r.tranches[3].fee, 1); eq(r.tranches[4].fee, 1,
		"the two fee coppers left by floors go to the largest remainders")
	eq(r.netProfit, 94); eq(r.nextCarry, 0)
	eq(r.refunds + r.netProfit + r.fee + r.nextCarry, r.pool)
end)

test("Lottery settlement: fifth-only winners get refunds, and no winners roll every eligible copper", function()
	local fifth = Settle({ Ticket("fifth", 5, 1), Ticket("lost", 9, 99) }, { 1, 2, 3, 4, 5 })
	eq(fifth.payouts[1], 1); eq(fifth.profitByTicket[1], 0)
	eq(fifth.refunds, 1); eq(fifth.fee, 0); eq(fifth.nextCarry, 99)
	local none = Settle({ Ticket("a", 6, 40), Ticket("b", 7, 60) }, { 1, 2, 3, 4, 5 }, 25)
	eq(none.refunds, 0); eq(none.netProfit, 0); eq(none.fee, 0)
	eq(none.nextCarry, 125); eq(Sum(none.payouts), 0)
end)

test("Lottery settlement: malformed tickets and ambiguous ids are refused whole", function()
	local base = { version = L.SETTLEMENT_VERSION, draw = { 1, 2, 3, 4, 5 }, carry = 0 }
	base.tickets = { Ticket("same", 1, 1), Ticket("same", 2, 1) }
	local r, why, at = L.Settle(base)
	eq(r, nil); eq(why, "id"); eq(at, 2)
	base.tickets = { Ticket("ok", 0, 1) }
	r, why, at = L.Settle(base)
	eq(r, nil); eq(why, "ticket"); eq(at, 1)
	base.tickets = { Ticket("ok", 1, 1) }; base.draw = { 1, 2, 3, 4 }
	eq(select(2, L.Settle(base)), "draw")
	base.draw = { 1, 2, 3, 4, 5 }; base.feeBp = 599
	eq(select(2, L.Settle(base)), "fee", "the contract fee is frozen at 6 percent")
	base.feeBp = 601
	eq(select(2, L.Settle(base)), "fee")
end)

test("Lottery public rules describe the versioned algorithm and no head-only rule remains visible", function()
	local function UIText(locale)
		local saved, host = GetLocale, { L = {} }
		GetLocale = function() return locale end
		local ok, err = pcall(function()
			assert(loadfile(H.ARENA_DIR .. "Locales/UIText.lua"))("Olympus_Arena", { host = host })
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return host.L
	end
	local en, pt = UIText("enUS"), UIText("ptBR")
	for i = 1, 4 do
		local percent = tostring(L.TRANCHE_BP[i] / 100) .. "%"
		assert(en.ARENA_LOTTERY_TUTORIAL_TEXT:find(percent, 1, true), "English position " .. i)
		assert(pt.ARENA_LOTTERY_TUTORIAL_TEXT:find(percent, 1, true), "pt-BR position " .. i)
	end
	for _, phrase in ipairs({ "five places", "stake back once", "fifth place is refund-only", "repeated beast",
		"6%", "calculated once", "aggregate claimed gross profit", "unclaimed tranche", "not an official jogo-do-bicho rule" }) do
		assert(en.ARENA_LOTTERY_TUTORIAL_TEXT:lower():find(phrase, 1, true), "English public rule: " .. phrase)
	end
	for _, phrase in ipairs({ "cinco posições", "aposta de volta uma vez", "quinta só devolve", "bicho repetido",
		"6%", "uma única vez", "lucro bruto agregado efetivamente pago", "parcela sem vencedor", "não uma regra oficial do jogo do bicho" }) do
		assert(pt.ARENA_LOTTERY_TUTORIAL_TEXT:lower():find(phrase, 1, true), "pt-BR public rule: " .. phrase)
	end
	assert(en.ARENA_LOTTERY_TEXT:find("50%, 25%, 15%, 10%", 1, true))
	assert(pt.ARENA_LOTTERY_TEXT:find("50%, 25%, 15%, 10%", 1, true))
	assert(en.ARENA_LOTTERY_SLIP_RULES:find("stake back once", 1, true)
		and en.ARENA_LOTTERY_SLIP_RULES:find("6% fee is only on profit paid", 1, true))
	assert(pt.ARENA_LOTTERY_SLIP_RULES:find("devolvida uma vez", 1, true)
		and pt.ARENA_LOTTERY_SLIP_RULES:find("6% incide apenas sobre o lucro pago", 1, true))

	local f = assert(io.open(H.ARENA_DIR .. "Games/Bicho.lua", "rb"))
	local source = f:read("*a"); f:close()
	for _, phrase in ipairs({ "gets its stake back once", "50%, 25%, 15% and 10%", "fifth is refund-only",
		"aggregate profit paid", "not official jogo-do-bicho rules" }) do
		assert(source:find(phrase, 1, true), "practice table public rule: " .. phrase)
	end
	assert(source:find("CoreLottery.Settle", 1, true), "the practice table delegates to the core contract")
	assert(source:find("r.winningTickets > 0", 1, true), "the visible ticket count uses tickets, not bettor names")
	for _, old in ipairs({ "The whole pot rolls over", "Nobody picked it:", "the head of the draw pays",
		"the beast of the first prize wins", "decides the day", "The head is" }) do
		assert(not source:find(old, 1, true), "obsolete public rule remains: " .. old)
	end
end)

-- A wallet's ledger parser, loaded alone into a namespace of its own: the current Olympus/Wallet.lua,
-- or tests/fixtures/wallet-1.2-pre-l2.lua, the integration's Wallet.lua just before the five-place
-- settlement (be25776^), the parser a client on the head-only Lottery (the f5d44c8 era) still runs.
-- Only what the file touches while it loads is stood in for; Parse itself is the file's own.
local function WalletOf(path)
	local wns = {
		L = setmetatable({}, { __index = function(_, key) return key end }),
		Comm = { Handle = function() end },
		Arena = { Handle = function(_, fn) return fn end, Action = function() end, B36 = ns.Arena.B36, N = ns.Arena.N },
		ArenaMoney = { Subscribe = function() end },
		ArenaRoles = {},
		Debts = { receiptHooks = {} },
		On = function() end,
	}
	assert(loadfile(path))("Olympus", wns)
	return wns.Wallet
end

test("Lottery old clients: the pre-v2 wallet parser refuses the L2 market and result its bank writes", function()
	local new = WalletOf(H.ADDON_DIR .. "Wallet.lua")
	local old = WalletOf(H.ROOT .. "tests/fixtures/wallet-1.2-pre-l2.lua")
	local market = new.MarketId("Lt00042zz", 1)
	-- The entries a v2 bank writes for a day, rendered by the current wallet: its n (kind "l") and
	-- its x, whose result is Lottery.EncodeResult's (all five places and the retained carry).
	local wire = assert(L.EncodeResult({ 7, 7, 2, 25, 13 }, 98765))
	local x = assert(new.Render({ k = "x", market = market, result = wire, t = 1790000600 }, 9))
	local n = assert(new.Render({ k = "n", market = market, nsel = 25, closes = 1790000000, feeBp = 600, arbBp = 0,
		kind = "l", cur = "g", to = "g" }, 8))
	local parsed = assert(new.Parse(x, 9), "the current wallet reads its own L2 result")
	eq(parsed.result, wire); eq(assert(L.DecodeResult(parsed.result)).nextCarry, 98765)
	eq(assert(new.Parse(n, 8)).kind, "l")
	-- The old client's own parser refuses both, so it never pays five places as five equal heads.
	eq(old.Parse(x, 9), nil, "the old wallet refuses the L2 result: " .. x)
	eq(old.Parse(n, 8), nil, "the old wallet refuses a kind-l market: " .. n)
	-- (Not a parser that refuses everything: the head-only day it was written for still reads.)
	local head = assert(old.Parse(new.Render({ k = "x", market = market, result = "7", t = 1790000600 }, 9), 9))
	eq(head.result, "7")
	eq(assert(old.Parse(new.Render({ k = "n", market = market, nsel = 25, closes = 1790000000, feeBp = 600, arbBp = 0,
		kind = "p", cur = "g", to = "g" }, 8), 8)).kind, "p")
end)

test("Lottery beasts: every card's art is a game icon or a 32 x 32 TGA the companion ships", function()
	eq(#L.BEASTS, 25)
	local files, icons = 0, 0
	for n, b in ipairs(L.BEASTS) do
		local what = ("beast %d (%s)"):format(n, tostring(b.key))
		assert(type(b.art) == "string" and b.art ~= "", what .. " has art")
		if b.icon then
			-- (The game's own icons: the client has them, nothing of ours to ship.)
			assert(b.art:find("^Interface\\Icons\\[%w_]+$"), what .. ": an icon path, " .. b.art)
			icons = icons + 1
		else
			-- A texture path the client resolves inside the companion's folder, as <key>.tga there.
			local rest = b.art:match("^Interface\\AddOns\\Olympus_Arena\\(.+)$")
			assert(rest, what .. ": inside Olympus_Arena, " .. b.art)
			eq(rest, "media\\lottery\\" .. b.key, what .. ": named by its key")
			local path = H.ARENA_DIR .. rest:gsub("\\", "/") .. ".tga"
			local f = io.open(path, "rb")
			assert(f, what .. ": its file is missing, " .. path)
			local head = f:read(18)
			f:close()
			-- The TGA header: uncompressed true colour (type 2), 32 x 32, 32 bits a pixel.
			assert(head and #head == 18, what .. ": a TGA header")
			eq(head:byte(3), 2, what .. ": uncompressed true colour")
			eq(head:byte(13) + head:byte(14) * 256, 32, what .. ": width")
			eq(head:byte(15) + head:byte(16) * 256, 32, what .. ": height")
			eq(head:byte(17), 32, what .. ": bits a pixel")
			files = files + 1
		end
	end
	eq(files, 19, "the nineteen gold marks"); eq(icons, 6, "the six game icons")
end)

-- Park-Miller: exact and reproducible in Lua's double range.
local seed = 912367
local function Rand(n)
	seed = seed * 16807 % 2147483647
	return seed % n + 1
end

test("Lottery settlement: 2,000 randomized books preserve every copper and ticket-order independence", function()
	for round = 1, 2000 do
		local tickets, reversed, count = {}, {}, Rand(40) - 1
		for i = 1, count do
			tickets[i] = Ticket(("t%04d"):format(i), Rand(25), Rand(100000), "P" .. Rand(12))
		end
		for i = 1, count do reversed[i] = tickets[count - i + 1] end
		local draw = { Rand(25), Rand(25), Rand(25), Rand(25), Rand(25) }
		local carry = Rand(1000000) - 1
		local r = Settle(tickets, draw, carry)
		local rr = Settle(reversed, draw, carry)
		eq(r.refunds + r.netProfit + r.fee + r.nextCarry, r.incomingCarry + r.newStakes,
			"invariant round " .. round)
		eq(Sum(r.payouts), r.refunds + r.netProfit, "payout sum round " .. round)
		eq(r.fee, M.MulDiv(r.grossProfit, 600, 10000), "aggregate fee round " .. round)
		local gross = 0
		for position, tranche in ipairs(r.tranches) do
			gross = gross + tranche.gross
			eq(tranche.position, position)
			eq(tranche.paid + tranche.fee + tranche.carry, tranche.gross,
				"tranche invariant round " .. round .. " position " .. position)
		end
		eq(gross, r.profitPool, "all tranches round " .. round)
		for id, payout in pairs(r.byId) do eq(rr.byId[id], payout, "id " .. id .. " round " .. round) end
	end
end)

-- The draw's clock (the owner's call, 2026-10-04): 21:00 US Central. The realm's clock is the game's
-- (GetGameTime) against server time; a realm on Central draws by it, any other by a fixed UTC-5.
local function OnRealmClock(offset, fn)
	local saved, savedNow = rawget(_G, "GetGameTime"), ns.Arena.Now
	local now
	GetGameTime = function()
		local here = (now + offset * 60) % 86400
		return math.floor(here / 3600), math.floor(here % 3600 / 60)
	end
	ns.Arena.Now = function() return now end -- (the server's clock, GetServerTime's)
	local ok, err = pcall(fn, function(t) now = t end)
	GetGameTime, ns.Arena.Now = saved, savedNow
	if not ok then error(err, 0) end
end

test("Lottery's clock: US Central's daylight saving by the US rule, Central's realms by their own clock, others a fixed UTC-5", function()
	-- CDT from the second Sunday of March at 08:00 UTC to the first Sunday of November at 07:00 UTC.
	for _, edge in ipairs({ { 1772956800, 1793516400 }, { 1710057600, 1730617200 }, { 1805011200, 1825570800 } }) do
		eq(L.CentralOffset(edge[1] - 1), -360, "before the spring change " .. edge[1])
		eq(L.CentralOffset(edge[1]), -300, "the spring change " .. edge[1])
		eq(L.CentralOffset(edge[2] - 1), -300, "before the autumn change " .. edge[2])
		eq(L.CentralOffset(edge[2]), -360, "the autumn change " .. edge[2])
	end
	local july, january = 1784116800, 1768478400 -- 2026-07-15 and 2026-01-15, 12:00 UTC
	local function ZoneAt(offset, t)
		local zone
		OnRealmClock(offset, function(set) set(t) zone = L.Zone(t) end)
		return zone
	end
	eq(ZoneAt(-300, july), "central", "Central's summer (CDT)")
	eq(ZoneAt(-360, january), "central", "Central's winter (CST)")
	eq(ZoneAt(-360, july), "fixed", "UTC-6 in July is Mountain's summer, not Central")
	eq(ZoneAt(-240, july), "fixed", "Eastern's summer")
	eq(ZoneAt(0, july), "fixed", "a realm on UTC")
	eq(L.Zone(july), "fixed", "no game clock: the offset reads 0")
	-- The next 21:00: Central's in July and January; UTC-5's in January is 20:00 in Texas.
	eq(L.DrawAt(july, 21 * 60, 120, "central"), 1784167200)
	eq(L.DrawAt(july, 21 * 60, 120, "fixed"), 1784167200)
	eq(L.DrawAt(january, 21 * 60, 120, "central"), 1768532400)
	eq(L.DrawAt(january, 21 * 60, 120, "fixed"), 1768528800)
	-- Saturday 22:00 CST before the spring change: Sunday's draw is 21:00 CDT, 02:00 UTC (at the
	-- offset of the moment it would be 03:00).
	local saturday = 1772942400
	eq(L.NextDraw(saturday, 21 * 60, -360, 120), 1773025200)
	eq(L.DrawAt(saturday, 21 * 60, 120, "central"), 1773021600)
	-- Its time as the board shows it, on the draw's clock with the clock's name.
	OnRealmClock(-300, function(set)
		set(july)
		eq(L.ClockText(1784167200), "21:00"); eq(L.WhenText(1784167200), "21:00 LOTTERY_ZONE_CENTRAL")
	end)
	OnRealmClock(-240, function(set)
		set(july)
		eq(L.ClockText(1784167200), "21:00"); eq(L.WhenText(1784167200), "21:00 LOTTERY_ZONE_FIXED")
	end)
end)

test("Lottery's winners: each day's date is its draw's, on the draw's clock, whatever clock the realm runs", function()
	-- 21:00 UTC-5 on 2026-10-04 is 02:00 UTC on 10-05: the day of that draw is 10-04 everywhere.
	local at = 1791165600
	local saved = ns.db
	ns.db = { lotteryWinners = { L = { L1x = { t = at + 600, at = at, bank = "Coffrey Vault-Emberfall",
		rows = { { name = "Parric Stowe-Emberfall", beast = 1, amount = 23500 } } } } } }
	local ok, err = pcall(function()
		for _, offset in ipairs({ 0, 120, -300 }) do -- a realm on UTC, on Central Europe's summer, on Central's (CDT)
			OnRealmClock(offset, function(set)
				set(at + 3600)
				local list = L.Winners("L")
				eq(list.latest[1].day, "10-04", "realm at " .. offset)
				eq(list.biggest[1].day, "10-04", "realm at " .. offset)
			end)
		end
	end)
	ns.db = saved
	if not ok then error(err, 0) end
end)

-- The illustration before a bet (the owner's call, 2026-10-04): the pick 1st and nowhere else.
local function OpenBook(pools, carry)
	local day = { state = "open", bets = {}, carry = carry or 0 }
	for o = 1, 25 do day.bets[o] = { pool = pools[o] or 0, count = pools[o] and 1 or 0 } end
	return day
end

test("Lottery's preview: about what a stake brings back if its beast comes 1st alone, the table as it is now", function()
	-- The guide's worked example: 960g on the table, 60g of it on the Sheep; 40g more on it. The
	-- profit pool is 900g, 1st place's half 450g, less 6% 423g, 40% of it 169.2g, plus the 40g back.
	local g = 10000
	local day = OpenBook({ [7] = 60 * g, [14] = 500 * g, [2] = 250 * g, [25] = 150 * g })
	local p = assert(L.Preview(day, 7, 4000))
	eq(p.stake, 40 * g); eq(p.payout, 2092000); eq(p.profit, 2092000 - 40 * g)
	-- Every beast backed (10g each): the four other places go to the least-backed, here the lowest
	-- numbers, and their stakes come back. 10g more on the Mechanostrider: 260g on the table, 60g
	-- back, a 200g profit pool, 100g for 1st, less 6% 94g, half of it 47g, plus 10g back.
	local all = {}
	for o = 1, 25 do all[o] = 10 * g end
	eq(L.Preview(OpenBook(all), 1, 1000).payout, 57 * g)
	-- Nobody else on the table, 100g rolled in: 50g for 1st, less 6%, 47g, all of it the bettor's.
	eq(L.Preview(OpenBook({}, 100 * g), 9, 1000).payout, 57 * g)
	-- A day that takes no bets, a beast or a stake that is not one: no illustration.
	local closed = OpenBook({})
	closed.state = "closed"
	eq(L.Preview(closed, 7, 100), nil)
	eq(L.Preview(OpenBook({}), 0, 100), nil); eq(L.Preview(OpenBook({}), 26, 100), nil)
	eq(L.Preview(OpenBook({}), 7, 0), nil); eq(L.Preview(OpenBook({}), 7, 1.5), nil)
	eq(L.Preview(nil, 7, 100), nil)
end)

print("Lottery: versioned five-position settlement, exact fees, refunds and rollover")
