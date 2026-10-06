local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Sim.lua. A stub the arena's core created for the screens to
-- fill. The solo simulation's scenes (1-31) with sample data; sets ArenaUI.Sim(args).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Home = ns.ArenaHome

-- The solo simulation (the design): every screen filled with invented fighters and a
-- crowd that bets on a timer, so one person can see and photograph them all. Who: the author's
-- Workshop or any test build (Arena.MaySim). While it runs, Arena.Send sends nothing, the stores
-- are the sim's memory (Arena.Store), the screens read this file's sample data (ArenaHome.SetSource)
-- and every choice the screens remember goes to the sim's own table (Kit.Settings): ns.db and
-- ns.rdb stay as they were. A purple banner says so; the overlay always carries SAMPLE DATA.
-- The bar (OlympusArenaSimBar): Prev, Next, the scene's name, the crowd's speed (1-10), the King
-- view, the gamepad view, Exit. Scenes 1-31 (the design) and 32, the bank's
-- crash drill (the design, through Wallet.Drill where the bank is on duty, else its sample).
local Sim = {}
ArenaUI.SimModule = Sim

-- About forty invented names (never the census, the roster or any real player): Sim.NAMES.
Sim.NAMES = {
	"Torvin Hale", "Selka Drummond", "Oswin Marrow", "Coffrey Vault", "Lida Fenn", "Parric Stowe", "Wenna Crale", "Doran Ashpeak",
	"Mirelle Thorne", "Hollis Brandt", "Ilka Stonefield", "Sabine Harrow", "Tomas Reedwater", "Garrick Vole", "Anneth Brisk", "Corwin Slate",
	"Elspeth Moor", "Fenwick Tarn", "Gilda Rook", "Harlan Quest", "Isolde Wren", "Jorund Pike", "Kestrel Dunn", "Lorne Ashby",
	"Maeve Holloway", "Niles Barrow", "Odile Frost", "Pell Garner", "Quenby Lark", "Rowan Tull", "Saskia Venn", "Tobin Marsh",
	"Ulla Crane", "Varric Dole", "Wilma Hask", "Xander Pell", "Yorick Fane", "Zelda Morrow", "Brannic Ode", "Cassia Lune",
}
Sim.CLASSES = { "WA", "PA", "HU", "RO", "PR", "SH", "MA", "WL", "DR" }
Sim.RACES = { 1, 3, 4, 7, 2, 5, 6, 8 }
local REALM = "Emberfall"

---------------------------------------------------------------------------
-- The seeded random numbers: the same scene gives the same numbers (screenshots can be repeated)
---------------------------------------------------------------------------

local seed = 1
local function Seed(n) seed = (tonumber(n) or 1) * 7919 % 2147483647 if seed <= 0 then seed = seed + 2147483646 end end
local function Rand(lo, hi)
	seed = seed * 16807 % 2147483647
	return lo + seed % (hi - lo + 1)
end
Sim.Seed, Sim.Rand = Seed, Rand

---------------------------------------------------------------------------
-- The sample world
---------------------------------------------------------------------------

local W -- the scene's world (below), rebuilt at each scene
local function Full(name) return ns.FullName(name, REALM) end
local function Now() return ns.Arena.Now() end

local function Fighters()
	local out = {}
	for i, n in ipairs(Sim.NAMES) do
		local wins, losses = Rand(0, 20), Rand(0, 12)
		out[#out + 1] = { name = Full(n), gk = ("1q.%08x"):format(0x10000 + i * 331), class = Sim.CLASSES[(i - 1) % #Sim.CLASSES + 1], race = Sim.RACES[(i - 1) % #Sim.RACES + 1],
			level = 60, rating = 1500 + Rand(-150, 260), wins = wins, losses = losses, ko = math.floor(wins * Rand(20, 90) / 100), emblem = nil,
			tier = nil, delta = Rand(-40, 60) }
	end
	table.sort(out, function(a, b) return a.rating > b.rating end)
	for i, f in ipairs(out) do
		f.rank = i
		f.tier = i <= 4 and "gold" or (i <= 12 and "silver" or (i <= 24 and "bronze" or nil))
	end
	return out
end
local function ByName(name)
	for _, f in ipairs(W.fighters) do if f.name:lower() == ns.FullName(name):lower() then return f end end
	return nil
end
Sim.ByName = function(name) return W and ByName(name) end

-- A market as Markets.View gives it: the winner market, and the duration's.
local function Market(ev, pools)
	local a, b = pools[1], pools[2]
	local total = a + b
	local function Odds(p) return p > 0 and math.floor(total * 94 / p + 0.5) / 100 or 0 end
	return {
		lockAt = ev.lockAt, bank = Full("Coffrey Vault"), cur = W.cur, fee = 600, recent = W.recent,
		markets = {
			{ idx = 1, type = "MW", label = L.ARENA_SIM_MARKET_WINNER, state = ev.closed and "z" or "o", outcomes = {
				{ o = "A", label = Kit.Name(ev.A), pool = a, count = W.counts[1], odds = Odds(a) },
				{ o = "B", label = Kit.Name(ev.B), pool = b, count = W.counts[2], odds = Odds(b) } } },
			{ idx = 2, type = "DR", label = L.ARENA_SIM_MARKET_DURATION, state = ev.closed and "z" or "o", outcomes = {
				{ o = "U", label = L.ARENA_SIM_UNDER, pool = math.floor(total / 3), count = 9, odds = 1.9 },
				{ o = "O", label = L.ARENA_SIM_OVER, pool = math.floor(total / 4), count = 7, odds = 2.1 } } },
		},
		payouts = ev.payouts,
	}
end

local function NewWorld(scene)
	Seed(scene)
	W = { scene = scene, cur = "g", recent = {}, counts = { Rand(12, 30), Rand(8, 24) }, pools = { Rand(300, 900) * 10000, Rand(200, 700) * 10000 },
		events = {}, markets = {}, tickets = {}, chat = {}, openBet = {}, tables = {}, hist = {}, bone = {}, roster = {}, challenges = {} }
	W.fighters = Fighters()
	local F = W.fighters
	local now = Now()
	-- Fight Night's main bout (scene 1: fighter A is the player himself, with his own portrait).
	local main = { id = "Fsim1", kind = "fight", public = true, mode = "L", state = "O", A = scene == 1 and ns.me or F[1].name, B = F[2].name,
		gkA = F[1].gk, gkB = F[2].gk, arbiter = Full("Oswin Marrow"), lockAt = now + 250, t = now + 250, cat = "A", sim = true }
	W.events[#W.events + 1] = main
	W.events[#W.events + 1] = { id = "Fsim2", kind = "fight", public = true, mode = "L", state = "A", A = F[3].name, B = F[4].name, gkA = F[3].gk, gkB = F[4].gk,
		arbiter = Full("Oswin Marrow"), lockAt = now + 1800, t = now + 1800, sim = true }
	W.events[#W.events + 1] = { id = "Nsim1", kind = "card", public = true, mode = "L", state = "P", title = L.ARENA_SIM_CARD, bouts = { "Fsim1", "Fsim2" },
		promoter = Full("Oswin Marrow"), t = now + 200, sim = true }
	W.events[#W.events + 1] = { id = "Fsim9", kind = "fight", public = false, mode = "L", state = "A", A = ns.me, B = F[7].name, arbiter = Full("Hollis Brandt"), t = now + 600, sim = true }
	W.events[#W.events + 1] = { id = "Fsim0", kind = "fight", public = true, mode = "L", state = "F", A = F[5].name, B = F[6].name, winner = F[5].name, method = "k",
		dur = 72, t = now - 3600, over = true, sim = true }
	W.main = main
	-- The tournament of 16, half way (scene 10), or before its draw (9, 27).
	local entrants = {}
	for i = 1, 16 do entrants[i] = { n = i, name = F[i].name, gk = F[i].gk } end
	W.tourney = { tid = "Tsim1", title = L.ARENA_SIM_TOURNEY, st = "L", size = 16, rounds = 4, entrants = entrants, matches = {}, promoter = Full("Oswin Marrow"), mode = "L" }
	local order = { 1, 16, 8, 9, 5, 12, 4, 13, 3, 14, 6, 11, 7, 10, 2, 15 }
	for m = 1, 8 do
		local a, b = entrants[order[2 * m - 1]], entrants[order[2 * m]]
		W.tourney.matches[#W.tourney.matches + 1] = { key = "1." .. m, round = 1, index = m, a = { gk = a.gk, name = a.name, n = a.n }, b = { gk = b.gk, name = b.name, n = b.n },
			winner = "a", state = "F", score = "1:0" }
	end
	for m = 1, 4 do
		local a = W.tourney.matches[2 * m - 1].a
		local b = W.tourney.matches[2 * m].a
		W.tourney.matches[#W.tourney.matches + 1] = { key = "2." .. m, round = 2, index = m, a = a, b = b, winner = m <= 2 and "a" or nil, state = m == 3 and "L" or (m <= 2 and "F" or nil),
			score = m <= 2 and "1:0" or "0:0" }
	end
	W.tourney.matches[#W.tourney.matches + 1] = { key = "3.1", round = 3, index = 1, a = W.tourney.matches[9].a, b = W.tourney.matches[10].a, state = nil, score = "0:0" }
	W.tourney.matches[#W.tourney.matches + 1] = { key = "4.1", round = 4, index = 1, state = nil, score = "0:0" }
	W.events[#W.events + 1] = { id = "Tsim1", kind = "tourney", public = true, mode = "L", state = W.tourney.st, title = W.tourney.title, size = 16, entrants = entrants, t = now + 900,
		promoter = W.tourney.promoter, sim = true }
	-- The crowd's last bets (amount and side only).
	for i = 1, 8 do W.recent[i] = { copper = Rand(1, 50) * 10000, o = Rand(0, 1) == 0 and "A" or "B" } end
	-- The player's own bets and wallet.
	W.tickets[#W.tickets + 1] = { eid = "Fsim1", idx = 1, o = "A", label = Kit.Name(main.A), copper = 100000, state = "ok", mine = true }
	W.wallet = { cur = "g", g = { bal = 2450000, escrow = 600000, reserved = 0 }, p = { bal = 0, escrow = 0 }, pending = 50000,
		banks = { { name = Full("Coffrey Vault"), online = true } }, debts = {}, receipts = {
			{ kind = "deposit", copper = 500000, state = "credited", t = now - 7200 }, { kind = "bet", copper = 100000, state = "held", t = now - 600 },
			{ kind = "won", copper = 194000, state = "credited", t = now - 3000 }, { kind = "withdrawal", copper = 300000, state = "mailed", t = now - 1500 },
			{ kind = "deposit", copper = 50000, state = "pending", t = now - 60 } } }
	-- The fight chat's rooms.
	W.chat.Fsim1 = {
		{ t = now - 50, sender = F[8].name, guild = "Olympus Ember", class = "WA", text = L.ARENA_SIM_CHAT_1 },
		{ t = now - 40, sender = F[9].name, guild = "Olympus Ember", class = "MA", text = L.ARENA_SIM_CHAT_2 },
		{ t = now - 20, sender = F[10].name, guild = "Olympus Ember", class = "PR", text = L.ARENA_SIM_CHAT_3 },
	}
	W.chat.Fsim9 = { { t = now - 30, sender = F[7].name, guild = "Olympus Ember", class = "RO", text = L.ARENA_SIM_CHAT_4 } }
	-- Bones.
	W.tables = { { id = "Ksim1", p1 = F[11].name, p2 = F[12].name, stake = 50000, cur = "g", official = true, mode = "L" },
		{ id = "Ksim2", p1 = F[13].name, p2 = F[14].name, stake = 0, mode = "L" } }
	W.myTable = { id = "Ksim3", players = { ns.me, F[15].name }, stake = 20000, cur = "g", state = "play", scores = { 2350, 1800 } }
	for i = 1, 6 do W.bone[i] = { t = now - i * 5000, opp = F[15 + i].name, won = i % 2 == 1, score = ("%d-%d"):format(Rand(2, 5) * 1000, Rand(1, 4) * 1000), stake = i * 10000, cur = "g" } end
	-- The history (his own fights).
	-- (eleven fights, their stakes too: his own profile and History tab look lived in, 2026-09-30)
	for i = 1, 11 do
		local opp = F[((18 + i) % #F) + 1].name
		W.hist[i] = { fid = "Fh" .. i, t = now - i * 86400 + Rand(0, 20000), A = ns.me, B = opp, opponent = opp, won = i % 3 ~= 0, method = i % 4 == 0 and "f" or "k",
			dur = Rand(40, 180), delta = i % 3 ~= 0 and Rand(8, 24) or -Rand(8, 24), winner = i % 3 ~= 0 and ns.me or opp, cat = "A",
			stake = i % 2 == 0 and Rand(1, 10) * 10000 or nil, cur = "g" }
	end
	-- The roster of a rehearsal (the Director's tab), a challenge waiting.
	for i = 1, 6 do W.roster[i] = { name = F[i + 2].name, build = 3, base = ns.VERSION, flags = i == 2 and "gr" or "r", at = now - i * 30, gone = i == 6, role = ({ "b", "a", "p", nil, "k" })[i] } end
	W.challenges = { { oid = "Fsim7", A = F[16].name, B = ns.me, stake = 50000, how = "a", arbiter = Full("Hollis Brandt"), cur = "g", bo = 1, t = now, mode = "L" } }
	W.arbiters = { { name = Full("Hollis Brandt"), online = true, free = true }, { name = Full("Oswin Marrow"), online = true, free = false },
		{ name = F[30].name, online = false, free = false } }
	W.lottery = { eid = "Lsim1", drawAt = now + 5400, pool = 1250000, rollover = 0, cur = "g" }
	W.match = nil
	return W
end
Sim.World = function() return W end

-- A fighter's card (ArenaProfile.Card's shape: each value { v, src }).
local function ProfileOf(name)
	local f = ByName(name)
	if not f and name and ns.FullName(name):lower() == tostring(ns.me):lower() then f = { name = ns.me, class = "WA", race = 1, level = 60, rating = 1612, wins = 14, losses = 5, ko = 9, tier = "silver" } end
	if not f then return nil end
	local function V(v, src) if v == nil then return nil end return { v = v, src = src } end
	-- (a duel or two of his defeats fled, as the ledger counts them apart: his record stays the rankings')
	local fled = math.min(f.losses or 0, (f.wins or 0) % 3)
	local p = { name = V(f.name, "own"), gk = f.gk, class = V(f.class, "own"), race = V(f.race, "own"), level = V(f.level, "own"),
		record = V({ wins = f.wins, losses = (f.losses or 0) - fled, fled = fled, ko = f.ko, last5 = "W W L W W", avgDur = 84 }, "ledger"), rating = V(f.rating, "ledger"),
		peak = V(f.rating and (f.rating + (f.wins or 0) % 7 * 9), "ledger"),
		tier = V(f.tier, "ledger"), pub = (f.rank or 1) % 2 == 1, verified = true, emblem = V(f.emblem, "own") }
	if W.champion and W.champion == f.name then
		p.title = V(L.ARENA_TITLE_CHAMPION, "verified")
		p.belts = V({ "A" }, "ledger")
		p.honour = V("arena-champion-1", "verified")
	end
	-- (the profile page's sample blocks: invented numbers)
	local n = (f.rating or 1500) % 17
	p.guild, p.guildRank = V("Olympus Sample", "own"), V(n % 2 == 0 and "Knight" or "Squire", "own")
	p.stats = V({ streak = n % 5 - 2, bones = { games = 20 + n, won = 10 + n % 9, best = 1500 + n * 150 },
		lottery = { days = 5 + n, wins = n % 4, biggest = (n + 1) * 25000 }, donations = { all = (n + 3) * 110000, month = (n % 6) * 20000, place = 3 + n },
		places = { global = 1 + n % 9, class = 1 + n % 3, race = 1 + n % 5 }, tabard = { wears = n % 3 ~= 0, src = "own", checked = true },
		online = "19:00-23:00 Texas time" }, "own")
	if not p.honour and n % 4 == 0 then p.honour = V("arena-champion-" .. (1 + n % 3), "verified") end
	return p
end

-- The sample data, shaped as ArenaHome.Data's answers (its source while the sim runs).
local source = {}
function source.Events()
	local out = {}
	for _, e in ipairs(W.events) do out[#out + 1] = Home.Data.Normal(e, e.kind) end
	return out
end
function source.Event(id)
	for _, e in ipairs(W.events) do if e.id == id then return Home.Data.Normal(e, e.kind) end end
	return nil
end
function source.Markets(id)
	local ev
	for _, e in ipairs(W.events) do if e.id == id then ev = e end end
	if not ev or ev.kind ~= "fight" or not ev.public then return nil end
	return Market(ev, id == "Fsim1" and W.pools or { 2000000, 1500000 })
end
function source.Quote(eid, idx, o, silver)
	silver = tonumber(silver) or 0
	local copper = silver * 100
	local pools = W.pools
	local mine = o == "B" and pools[2] or pools[1]
	local other = o == "B" and pools[1] or pools[2]
	local won = mine + copper > 0 and math.floor(other * copper / (mine + copper)) or 0
	local fee = math.floor(won * 6 / 100)
	local q = { ok = true, odds = math.floor((mine + other + copper) * 100 / (mine + copper)) / 100, payout = copper + won - fee,
		fee = { g = math.floor(won * 4 / 100), a = fee - math.floor(won * 4 / 100) }, cap = 200000, after = (W.wallet.g.bal or 0) - copper, cur = W.cur }
	if W.scene == 2 and silver > 2000 then q.ok, q.why = false, "cap" end
	if W.scene == 28 then q.ok, q.why = false, "debtor" end
	return q
end
function source.Tickets(filter)
	local out = {}
	for _, t in ipairs(W.tickets) do
		if not (type(filter) == "table" and filter.eid and filter.eid ~= t.eid) then out[#out + 1] = t end
	end
	return out
end
function source.Wallet() return W.wallet end
function source.Receipts() return W.wallet.receipts end
function source.Rankings(period, cat, page)
	local rows = {}
	for _, f in ipairs(W.fighters) do
		local inCat = cat == "A" or cat == nil or cat == "C" .. f.class or cat == "R" .. tostring(f.race)
		if inCat then rows[#rows + 1] = { rank = #rows + 1, name = f.name, gk = f.gk, rating = f.rating, wins = f.wins, losses = f.losses, tier = f.tier, delta = f.delta } end
	end
	local v = { period = period or "week", cat = cat or "A", periods = {}, categories = {}, rows = {}, loaded = true }
	v.total = #rows
	v.pages = math.max(1, math.ceil(#rows / Home.PAGE))
	v.page = math.max(1, math.min(tonumber(page) or 1, v.pages))
	for i = (v.page - 1) * Home.PAGE + 1, math.min(#rows, v.page * Home.PAGE) do v.rows[#v.rows + 1] = rows[i] end
	v.mine = { rank = 12, rating = 1612, gk = "me" }
	return v
end
function source.Belts()
	return { { cat = "A", holder = W.champion or W.fighters[1].name, defences = 3 }, { cat = "CWA", holder = W.fighters[1].name, defences = 1 } }
end
function source.History(filter)
	if type(filter) == "table" and filter.mine then return W.hist end
	local out = {}
	for i, h in ipairs(W.hist) do out[i] = { fid = h.fid, t = h.t, A = W.fighters[i].name, B = W.fighters[i + 1].name, winner = W.fighters[i].name, method = h.method, dur = h.dur, public = true } end
	return out
end
function source.Profile(name) return ProfileOf(name) end
function source.MyProfile() return { pub = true, emblem = nil } end
function source.Verified(name)
	if W.champion and name and ns.FullName(name):lower() == ns.FullName(W.champion):lower() then return { frame = "arena-champion", title = "arena-champion", mark = "arena-champion" } end
	return { frame = "rank", mark = "rank" }
end
function source.Tier(gk)
	for _, f in ipairs(W.fighters) do if f.gk == gk then return f.tier end end
	return nil
end
-- (the Games tab's rankings: invented Bones players and Lottery winners)
function source.GamesRanking(game)
	if game == "bones" then
		local out = {}
		for i = 1, 8 do local f = W.fighters[i] out[i] = { name = f.name, games = 30 - i * 2, won = 22 - i * 2 } end
		return out
	end
	local beasts = { "the Gryphon", "the Kodo", "the Raptor", "the Owl", "the Boar" }
	local latest, biggest = {}, {}
	for i = 1, 5 do
		latest[i] = { name = W.fighters[10 + i].name, day = date and date("%m-%d", Now() - i * 86400) or "", beast = beasts[i], amount = (6 - i) * 180000 }
		biggest[i] = { name = W.fighters[i * 3].name, amount = (6 - i) * 520000 }
	end
	return { latest = latest, biggest = biggest }
end
function source.Tourney(tid) if tid == "Tsim1" then return W.tourney end return nil end
function source.Oracle() return { W.fighters[20].name, W.fighters[21].name, W.fighters[22].name } end
function source.Tables() return W.tables end
function source.MyTable() return W.myTable end
function source.BoneHistory() return W.bone end
function source.Lottery() return W.lottery end
function source.Match() return W.match end
function source.Arbiters() return W.arbiters end
function source.Challenges() return W.challenges end
function source.Cap() return 200000 end
function source.OpenBet(name) return W.openBet[ns.FullName(name or ""):lower()] == true end
function source.ChatLines(room) return W.chat[room] or {} end
function source.Roster() return W.roster end
function source.BankConsole()
	if not W.bank then return nil end
	return W.bank
end
function source.ArbiterConsole()
	return { cap = 5000000, held = 3000000, onDuty = true, persists = true, fees = { owed = 60000, late = W.scene == 17 }, matches = {} }
end
function source.Ledgers()
	local F = W.fighters
	return { banks = { { name = Full("Coffrey Vault"), seq = 412, liabilities = { g = 18400000 }, verified = true, reserve = { copper = 19000000 }, attest = { copper = 19000000 } } },
		arbiters = { { name = Full("Oswin Marrow"), held = 3000000, matches = 12, owed = 0 }, { name = Full("Hollis Brandt"), held = 500000, matches = 3, owed = 40000 } },
		debts = { { name = F[33].name, copper = 120000, creditor = F[34].name, state = "o" }, { name = F[35].name, copper = 6000, creditor = "G", state = "m" } } }
end
Sim.source = source

---------------------------------------------------------------------------
-- The scenes
---------------------------------------------------------------------------

local function Pane(key, sel) ArenaUI.Show() if sel ~= nil then ArenaUI.ShowPane(key, sel) else ArenaUI.ShowPane(key) end end
local function Staff(key) ArenaUI.Show() ArenaUI.ShowStaff(key) end
local function Close(...)
	for _, fn in ipairs({ ... }) do if type(fn) == "function" then pcall(fn) end end
end

-- Each scene: its name's key and what it sets up and opens.
Sim.SCENES = {
	{ "OPEN", function() Pane("arena.events", "Fsim1") end },
	{ "SLIP", function() Pane("arena.events", "Fsim1") ArenaUI.Slip("Fsim1", 1, "A") end },
	{ "CLOSING", function()
		W.main.lockAt, W.main.state = Now() + 45, "Z"
		Pane("arena.events", "Fsim1")
		Home.ShowCall({ title = L.ARENA_ALERT_CLOSING:format(Home.EventTitle(Home.Data.Normal(W.main))), who = Home.EventTitle(Home.Data.Normal(W.main)), lockAt = W.main.lockAt })
	end },
	{ "CLOSED", function()
		W.main.lockAt, W.main.state, W.main.closed = Now() - 5, "L", true
		Pane("arena.events", "Fsim1")
		if ArenaUI.Overlay then ArenaUI.Overlay.Show("Fsim1") end
	end },
	{ "RESULT", function()
		W.main.state, W.main.winner, W.main.method, W.main.dur, W.main.graceEnd = "R", W.main.A, "k", 72, Now() + 252
		W.main.arbiter = ns.me
		Pane("arena.events", "Fsim1")
		Staff("staff.arbiter")
		Home.ShowCall({ title = L.ARENA_ALERT_RESULT:format(Home.EventTitle(Home.Data.Normal(W.main)), Kit.Name(W.main.A)), who = Home.EventTitle(Home.Data.Normal(W.main)) })
	end },
	{ "PAYOUTS", function()
		W.main.state, W.main.winner, W.main.over = "F", W.main.A, true
		W.main.payouts = { paid = 38, due = 4, copperPaid = 11800000, copperDue = 600000, late = 0 }
		if ArenaUI.Overlay then ArenaUI.Overlay.Show("Fsim1") end
		Home.Toast(L.ARENA_TOAST_PAID:format(Kit.Name(Full("Coffrey Vault")), Kit.Money(194000)))
		Home.Toast(L.ARENA_SIM_TOAST_LATE)
	end },
	{ "VOID", function()
		W.main.state, W.main.over = "V", true
		Pane("arena.events", "Fsim1")
		Home.Toast(L.ARENA_SIM_TOAST_REFUND:format(Kit.Money(100000)))
	end },
	{ "CHALLENGE", function()
		Pane("arena.events", "Fsim9")
		Home.ShowChallenge(W.challenges[1])
		ArenaUI.Challenge(W.fighters[7].name, { stake = 50000, how = "a" })
	end },
	{ "TOURNEY", function()
		W.tourney.st = "R"
		for _, e in ipairs(W.events) do if e.id == "Tsim1" then e.state = "R" end end
		Pane("arena.events", "Tsim1")
	end },
	{ "BRACKET", function()
		Pane("arena.events", "Tsim1")
		if ArenaUI.Bracket then ArenaUI.Bracket.Open("Tsim1") end
	end },
	{ "CHAMPION", function()
		W.champion = W.fighters[1].name
		Pane("arena.profile", W.champion)
	end },
	{ "BONE", function()
		ArenaUI.Show()
		ArenaUI.ShowSection("farkle")
		ArenaUI.ShowPane("bone.play")
		if type(ArenaUI.Farkle) == "function" then pcall(ArenaUI.Farkle, "sim") end
	end },
	{ "WALLET", function()
		W.wallet.debts = { { copper = 120000, paid = 0, creditor = W.fighters[5].name, kind = "bet" } }
		ArenaUI.Show()
		ArenaUI.Wallet("ledger")
	end },
	{ "RANKING", function()
		Kit.Remember("rank.kind", "class")
		Kit.Remember("rank.class", 7)
		Pane("arena.rankings")
	end },
	{ "PROFILE", function()
		Pane("arena.profile", false)
		ArenaUI.PreviewMe()
	end },
	{ "BANK", function()
		W.bank = { mode = "L", name = Full("Coffrey Vault"), currency = "g", paused = false,
			queue = { { name = W.fighters[8].name, copper = 500000, called = true }, { name = W.fighters[9].name, copper = 100000 } },
			inbox = { { i = 1, sender = W.fighters[10].name, money = 250000, verdict = "take" }, { i = 2, sender = W.fighters[11].name, money = 3000000, verdict = "return" } },
			withdrawals = { queue = { { name = W.fighters[12].name, copper = 300000, state = "q" } } }, fees = { owed = 40000, receiver = Full(Sim.NAMES[33]) },
			health = { queue = 3, lastSent = Now() - 40 } }
		Staff("staff.bank")
	end },
	{ "ARBITER", function()
		W.main.arbiter, W.main.state = ns.me, "L"
		Staff("staff.arbiter")
	end },
	{ "OVERLAY", function()
		ArenaUI.simKing = true
		Kit.Settings().delay = 120
		if ArenaUI.Overlay then ArenaUI.Overlay.Show("Fsim1") end
	end },
	{ "RULES", function() ArenaUI.Show() ArenaUI.ShowRules() end },
	{ "REHEARSAL", function()
		for _, e in ipairs(W.events) do e.mode = "T" end
		Staff("director")
	end },
	{ "FAR", function()
		W.fighters[2].emblem = "INV_Sword_27"
		if ArenaUI.Card then ArenaUI.Card.Open("Fsim1") end
	end },
	{ "LEDGERS", function() Staff("staff.ledgers") end },
	{ "CHAT", function()
		Pane("arena.events", "Fsim1")
		if ArenaUI.ChatPanel then ArenaUI.ChatPanel.Open("Fsim1", true) end
	end },
	{ "ALERT", function()
		W.main.lockAt = Now() + 180
		Home.ShowCall({ title = L.ARENA_ALERT_OPEN:format(Home.EventTitle(Home.Data.Normal(W.main))), who = Home.EventTitle(Home.Data.Normal(W.main)), lockAt = W.main.lockAt })
	end },
	{ "EDIT", function()
		Pane("arena.profile", false)
		ArenaUI.PreviewMe()
		ArenaUI.LettersPopup()
	end },
	{ "BONE_LIFE", function()
		ArenaUI.Show()
		ArenaUI.ShowPane("bone.live", "Ksim1")
	end },
	{ "ENTRY", function()
		W.tourney.st = "K"
		for _, e in ipairs(W.events) do if e.id == "Tsim1" then e.state = "K" end end
		Pane("arena.events", "Tsim1")
	end },
	{ "DEBTOR", function()
		W.openBet[W.fighters[2].name:lower()] = true
		Pane("arena.events", "Fsim1")
		ArenaUI.Slip("Fsim1", 1, "B")
	end },
	{ "RECORDS", function()
		W.champion = W.fighters[1].name
		Pane("arena.rankings")
		Sim.Records()
	end },
	{ "OLYMPUS", function()
		local UI = ns.UI
		if type(UI) == "table" and type(UI.SelectTab) == "function" then
			if not (UI.IsShown and UI.IsShown()) then pcall(UI.Toggle) end
			pcall(UI.SelectTab, "arena")
		end
	end },
	{ "HONOURS", function()
		W.champion = ns.me
		local B = ns.Borders
		if type(B) == "table" and type(B.SetPreview) == "function" and type(B.Preview) == "function" then
			pcall(B.SetPreview, "arena-champion-2")
			Sim.previewSet = B.Preview() ~= nil
		end
		Home.Letter("arena-champion-2")
	end },
	-- The champion's letter (the owner's slides, 2026-09-30): the King's letter with the arena
	-- champion's gold gryphon frame round the portrait, to an invented champion.
	{ "LETTER", function()
		W.champion = W.fighters[1].name
		if Home.ResetLetters then Home.ResetLetters() end
		local shown = Home.LetterFrame and Home.LetterFrame()
		if shown and shown:IsShown() then shown:Hide() end
		local e = Home.Letter("arena-champion-1")
		if type(e) == "table" then e.to = W.fighters[1].name end
		local f = Home.LetterFrame and Home.LetterFrame()
		if f and f.to then f.to:SetText(L.ARENA_LETTER_TO:format(Kit.Name(W.fighters[1].name))) end
	end },
	{ "DRILL", function()
		local lost
		local Wl = ns.Wallet
		if type(Wl) == "table" and type(Wl.Drill) == "function" then
			local ok, n = pcall(Wl.Drill)
			if ok and tonumber(n) then lost = n end
		end
		W.drill = { lost = lost or 3, replicas = 2, equal = true }
		W.bank = { mode = "L", name = Full("Coffrey Vault"), currency = "g", queue = {}, inbox = {}, withdrawals = { queue = {} }, fees = {},
			health = { queue = 0, lastSent = Now() - 400 } }
		Staff("staff.bank")
		Sim.DrillPopup()
	end },
}
if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then
	for i = #Sim.SCENES, 1, -1 do
		if Sim.SCENES[i][1] == "WALLET" then table.remove(Sim.SCENES, i) end
	end
end
Sim.COUNT = #Sim.SCENES

-- The records (scene 29): the Hall, the level race, a belt's lineage, sample lines in a pop-up.
local records
function Sim.Records()
	records = records or Kit.Frame("OlympusArenaRecords", 420, 360, { title = L.ARENA_SIM_RECORDS })
	records.list = rawget(records, "list") or Kit.List(records, 370, 270)
	records.list:SetPoint("TOPLEFT", 24, -56)
	local F = W.fighters
	records.list:SetLines({
		{ header = true, text = L.ARENA_SIM_HALL }, { text = L.ARENA_SIM_HALL_LINE:format(1, Kit.Name(F[1].name)), indent = 1 },
		{ header = true, text = L.ARENA_SIM_LEVEL_RACE }, { text = L.ARENA_TITLE_FIRST_TO:format(60) .. ": " .. Kit.Name(F[3].name), indent = 1 },
		{ header = true, text = L.ARENA_SIM_LINEAGE }, { text = Kit.Name(F[4].name) .. " > " .. Kit.Name(F[1].name), indent = 1 },
	})
	records:Show()
	return records
end
-- The crash drill's result (scene 32).
local drill
function Sim.DrillPopup()
	drill = drill or Kit.Frame("OlympusArenaDrill", 420, 220, { title = L.ARENA_SIM_DRILL })
	drill.text = rawget(drill, "text") or Kit.Text(drill, nil, "LEFT")
	drill.text:SetPoint("TOPLEFT", 28, -58)
	drill.text:SetWidth(364)
	drill.text:SetText(L.ARENA_SIM_DRILL_TEXT:format(W.drill.lost, W.drill.replicas))
	drill:Show()
	return drill
end

---------------------------------------------------------------------------
-- The crowd: 1 to 10 bets a second on the main bout (the pools, the odds and the ticker move)
---------------------------------------------------------------------------

local crowd
function Sim.Crowd()
	if not W then return end
	local n = Rand(1, math.max(1, Sim.speed or 3))
	for _ = 1, n do
		local side = Rand(1, 2)
		local copper = Rand(1, 20) * 10000
		W.pools[side] = W.pools[side] + copper
		W.counts[side] = W.counts[side] + 1
		table.insert(W.recent, { copper = copper, o = side == 1 and "A" or "B" })
		while #W.recent > 8 do table.remove(W.recent, 1) end
	end
	if ArenaUI.IsShown and ArenaUI.IsShown() then ArenaUI.Refresh() end
	local O = ArenaUI.Overlay
	if O and O.Frame and O.Frame() and O.Frame():IsShown() then O.Refresh() end
end
local function StartCrowd()
	if crowd or not (C_Timer and C_Timer.NewTicker) then return end
	crowd = C_Timer.NewTicker(1, function()
		if not ns.Arena.Sim() then Sim.Stop() return end
		ns.SafeCall("arena sim crowd", Sim.Crowd)
	end)
end
local function StopCrowd()
	if crowd and crowd.Cancel then crowd:Cancel() end
	crowd = nil
end

---------------------------------------------------------------------------
-- The bar and the running
---------------------------------------------------------------------------

local bar
local function Bar()
	if bar then return bar end
	bar = CreateFrame("Frame", "OlympusArenaSimBar", UIParent)
	bar:SetSize(760, 40)
	bar:SetPoint("TOP", 0, -8)
	bar:SetFrameStrata("HIGH")
	bar:EnableMouse(true)
	bar:SetMovable(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
	bar:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.30, 0.10, 0.45, 0.92)
	local x = 8
	local function B(w, text, fn)
		local b = Kit.Button(bar, w, 24, text, fn)
		b:SetPoint("LEFT", x, 0)
		x = x + w + 4
		return b
	end
	bar.prev = B(60, L.ARENA_SIM_PREV, function() Sim.Go((Sim.scene or 1) - 1) end)
	bar.next = B(60, L.ARENA_SIM_NEXT, function() Sim.Go((Sim.scene or 1) + 1) end)
	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.label:SetPoint("LEFT", x, 0)
	bar.label:SetWidth(230)
	bar.label:SetJustifyH("LEFT")
	x = x + 234
	bar.slower = B(24, "-", function() Sim.Speed((Sim.speed or 3) - 1) end)
	bar.speedText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.speedText:SetPoint("LEFT", x, 0)
	bar.speedText:SetWidth(64)
	x = x + 68
	bar.faster = B(24, "+", function() Sim.Speed((Sim.speed or 3) + 1) end)
	bar.king = B(80, L.ARENA_SIM_KING, function() ArenaUI.simKing = not ArenaUI.simKing Sim.Refresh() end)
	bar.pad = B(80, L.ARENA_SIM_GAMEPAD, function() ArenaUI.simGamepad = not ArenaUI.simGamepad Sim.Refresh() end)
	bar.exit = B(60, L.ARENA_SIM_EXIT, function() Sim.Stop() end)
	return bar
end
function Sim.Refresh()
	if not bar then return end
	bar.label:SetText(L.ARENA_SIM_SCENE:format(Sim.scene or 1, Sim.COUNT, L["ARENA_SIM_" .. Sim.SCENES[Sim.scene or 1][1]] or Sim.SCENES[Sim.scene or 1][1]))
	bar.speedText:SetText(L.ARENA_SIM_SPEED:format(Sim.speed or 3))
	if ArenaUI.simKing then bar.king:LockHighlight() else bar.king:UnlockHighlight() end
	if ArenaUI.simGamepad then bar.pad:LockHighlight() else bar.pad:UnlockHighlight() end
	if ArenaUI.IsShown and ArenaUI.IsShown() then ArenaUI.Refresh() end
end

-- The windows a scene may have opened: closed before the next one.
local function CloseAll()
	local fns = {}
	for _, get in ipairs({ ArenaUI.SlipFrame, ArenaUI.WalletFrame, ArenaUI.ChallengeFrame, ArenaUI.FindFrame, ArenaUI.RulesFrame, ArenaUI.HelpFrame,
		Home.CallFrame, Home.ChallengeFrame, Home.LetterFrame }) do
		local okGet, fr = pcall(get)
		if okGet and fr and fr.Hide then fns[#fns + 1] = function() fr:Hide() end end
	end
	if ArenaUI.Overlay then fns[#fns + 1] = ArenaUI.Overlay.Hide end
	if ArenaUI.ChatPanel then fns[#fns + 1] = ArenaUI.ChatPanel.Close end
	if ArenaUI.Card and ArenaUI.Card.Window then local w = ArenaUI.Card.Window() if w then fns[#fns + 1] = function() w:Hide() end end end
	if ArenaUI.Bracket and ArenaUI.Bracket.Window then local w = ArenaUI.Bracket.Window() if w then fns[#fns + 1] = function() w:Hide() end end end
	for _, fr in ipairs({ records, drill }) do if fr then fns[#fns + 1] = function() fr:Hide() end end end
	-- (A border preview the honours scene showed goes too.)
	if Sim.previewSet then
		Sim.previewSet = nil
		local B = ns.Borders
		if type(B) == "table" and type(B.SetPreview) == "function" then fns[#fns + 1] = function() B.SetPreview("off") end end
	end
	Close(unpack(fns))
end

-- Goes to scene n (wrapping round), with its seeded data.
function Sim.Go(n)
	if not ns.Arena.Sim() then return false end
	n = math.floor(tonumber(n) or 1)
	if n < 1 then n = Sim.COUNT elseif n > Sim.COUNT then n = 1 end
	Sim.scene = n
	CloseAll()
	ArenaUI.simKing, ArenaUI.simGamepad = false, false
	NewWorld(n)
	Home.SetSource(source)
	Bar():Show()
	local ok, err = pcall(Sim.SCENES[n][2])
	if not ok and ns.CaptureError then ns.CaptureError("arena sim scene " .. n, err) end
	Sim.Refresh()
	return ok
end
function Sim.Speed(n)
	Sim.speed = math.max(1, math.min(10, math.floor(tonumber(n) or 3)))
	Sim.Refresh()
end

-- /oly arena sim photos: every scene in turn and the game's own screenshot of each (Screenshot(),
-- into the client's Screenshots folder), so the owner can review every screen without a render:
-- 3 s for the scene to settle (the crowd moves its bets), the shot, then 2 s more so the game's
-- "Screen Captured" line has gone before the next one. Any other sim command, or leaving the sim,
-- stops it.
local photos
local function PhotoStep()
	if not photos or not ns.Arena.Sim() then photos = nil return end
	photos = photos + 1
	if photos > Sim.COUNT then
		photos = nil
		Kit.PhotoStage(false)
		ns.Print(L.ARENA_SIM_PHOTOS_DONE:format(Sim.COUNT))
		return
	end
	Sim.Go(photos)
	ns.Arena.After(3, "simphoto", function()
		if not photos then return end
		-- (switched to the gamepad UI since: the tour ends, no shot)
		if not ns.Gate.Allowed("photo") then photos = nil Kit.PhotoStage(false) return end
		-- (The sim's bar is hidden for the shot and comes back a second later: no mock-data label
		-- in the pictures, 2026-09-30.)
		if bar then bar:Hide() end
		if type(Screenshot) == "function" then Screenshot() end -- gp:photo
		ns.Arena.After(1, "simphotobar", function() if bar and ns.Arena.Sim() then bar:Show() end end)
		ns.Arena.After(2, "simphoto", PhotoStep)
	end)
end
local function StopPhotos()
	if not photos then return end
	photos = nil
	ns.Arena.After(0, "simphoto", nil)
	Kit.PhotoStage(false)
end
function Sim.Photos()
	StopPhotos()
	-- (the gamepad gate's "photo": the author's photo modes are refused with the gamepad UI)
	if not ns.Gate.Allowed("photo") then ns.Print(L.PHOTO_GAMEPAD) return false end
	photos = 0
	-- (only the windows, on black: the stage; Escape ends the tour)
	Kit.PhotoStage(true, function() StopPhotos() end)
	ns.Print(L.ARENA_SIM_PHOTOS:format(Sim.COUNT, Sim.COUNT * 5))
	PhotoStep()
	return true
end

-- Starts (or moves) the sim: /oly arena sim [scene|next|prev|speed n|photos]; the Workshop's button.
-- ArenaNet switched the sim on before (Arena.SetSim), and refuses anyone the sim is not for.
function ArenaUI.Sim(args)
	if not ns.Arena.Sim() then return false end
	local word, rest = tostring(args or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	Kit.ResetSimSettings()
	if word == "photos" then StartCrowd() return Sim.Photos() end
	StopPhotos()
	if word == "next" then return Sim.Go((Sim.scene or 0) + 1) end
	if word == "prev" then return Sim.Go((Sim.scene or 2) - 1) end
	if word == "speed" then Sim.Speed(rest) return true end
	StartCrowd()
	return Sim.Go(tonumber(word) or Sim.scene or 1)
end
-- Leaves the sim: its data and windows go; the stores and settings were never the player's.
function Sim.Stop()
	StopPhotos()
	StopCrowd()
	CloseAll()
	if bar then bar:Hide() end
	ArenaUI.simKing, ArenaUI.simGamepad = false, false
	if Home.Source() == source then Home.SetSource(nil) end
	W = nil
	-- (the showcase keeps a world of its own after the sim: Sim.Showcase)
	if Sim.showcase then W = NewWorld(1) end
	Sim.scene = nil
	Kit.ResetSimSettings()
	if ns.Arena.Sim() then ns.Arena.SetSim(false) end
	if ArenaUI.IsShown and ArenaUI.IsShown() then ArenaUI.Hide() end
	return true
end
-- /oly arena sim off (ArenaNet turns it off): the screens follow.
ns.On("ARENA_CHANGED", function()
	if not ns.Arena.Sim() and Home.Source() == source then ns.SafeCall("arena sim stop", Sim.Stop) end
end)

-- The showcase (ArenaHome.SetShowcase): on an explicit test build only, the sim's world answers
-- the screens' reads wherever the real modules have nothing, without the sim's bar. A normal
-- production client never receives invented fighters, results or balances.
function Sim.Showcase()
	local test = ns.Arena.TestBuild and ns.Arena.TestBuild()
	if not test or not Home.SetShowcase then return false end
	Sim.showcase = true
	if not W then W = NewWorld(1) end
	Home.SetShowcase(source)
	return true
end
ns.SafeCall("arena showcase", Sim.Showcase)
