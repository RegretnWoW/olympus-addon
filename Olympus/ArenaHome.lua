local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaHome.lua. A stub the arena's core created for the screens (UI and test) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The Arena tab in the Olympus window (UI.AddTab, after "chat", through the side column's overflow
-- rule: canonical right column, then the left from bottom to top), the census line, and every arena alert (ns.Alert("arena", ...)). The tab
-- shows whenever the player is a member and the arena is not off. Its window has three sections
-- (the design): Arena (duels, Fight Nights, tournaments), Farkle, Lottery, over one wallet.
-- The design: the right-click menu on a player (Menu.ModifyMenu, tags MENU_UNIT_<which>): "Invite
-- to Farkle", "Challenge to the Blood Arena", "Watch Farkle" (when that table allows spectators),
-- "Arena profile".
local ArenaHome = {}
ns.ArenaHome = ArenaHome

local L = ns.L

-- What lives here, in the core (the companion Olympus_Arena holds the heavy screens and loads only
-- when the player opens the arena, the design):
-- - ArenaHome.Data: the one way every screen reads the other packages' view models (the design),
--   each call guarded (a package not merged yet reads as empty), and swapped for the solo
--   simulation's sample data while it runs (ArenaHome.SetSource), so the Olympus window's tab and
--   the Arena window show the same thing.
-- - The Arena tab of the Olympus window, and the census line (ArenaHome.CensusLine, for the Census
--   and the Realm while a public event takes bets).
-- - Every arena alert, from the events of the design, under the sound kind "arena": the public ones
--   reach every member with the arena on and its alerts on, whatever the rules' answer (viewing
--   needs none, the design), and never load the companion; a 1v1 match only its three
--   people; a rehearsal its participants. Held in an instance or while Busy (ns.Alert).
-- - Small windows of Olympus's own a player may need before the companion is loaded: the alert
--   window (OlympusArenaCall), the toasts (OlympusArenaToast) and the King's letters for honours
--   (OlympusArenaLetter, the design). Each is made the first time it shows (the weight rule), goes
--   on the escape list only through ns.EscapeCloses, and never takes the keyboard.
-- - The right-click lines on a player (the design) through PlayerMenu.lua's shared hook when this
--   build has it (1.1.2), else Blizzard's Menu.ModifyMenu directly, and the arena's privacy line.

local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or "" end
local function WalletShown() return ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet() == true end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Lower(a) == Lower(b) end
local function Now() return ns.Arena.Now() end

-- A call into another package, guarded: nil when the module or the function is missing, or fails.
local function Call(mod, fn, ...)
	local m = ns[mod]
	if type(m) ~= "table" or type(m[fn]) ~= "function" then return nil end
	local ok, a, b, c = pcall(m[fn], ...)
	if not ok then
		ns.Log("arena %s.%s failed: %s", mod, fn, tostring(a))
		return nil
	end
	return a, b, c
end
ArenaHome.Call = Call

---------------------------------------------------------------------------
-- Money and small words
---------------------------------------------------------------------------

-- Copper in words: "245g", "7g 2s 85c", "40s 1c", "0c". Never rounded.
function ArenaHome.Money(copper, cur)
	copper = math.floor(tonumber(copper) or 0)
	if cur == "c" then return L.ARENA_CHIPS_N:format(ns.FormatNumber(copper)) end
	if cur == "p" then return L.ARENA_POINTS_N:format(ns.FormatNumber(copper)) end
	local neg = copper < 0
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = ns.FormatNumber(g) .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return (neg and "-" or "") .. table.concat(parts, " ")
end
local Money = ArenaHome.Money

-- A countdown in words: "4:10", "0:09", "1:02:03".
function ArenaHome.Clock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end

-- A name as the screens show it: plain, King.CleanName'd, masked on the King's screen.
function ArenaHome.Name(name)
	if type(name) ~= "string" or name == "" then return "?" end
	local shown = ns.DisplayName(name) or name
	shown = ns.Codec and ns.Codec.Plain(shown) or shown
	return ns.Arena.Mask(shown)
end

---------------------------------------------------------------------------
-- The view models (the design), read through here by every screen
---------------------------------------------------------------------------

local Data = {}
ArenaHome.Data = Data
local source -- the sim's sample data while it runs (a table of functions shaped as below)
function ArenaHome.SetSource(src)
	source = type(src) == "table" and src or nil
	ns.Arena.Changed()
end
function ArenaHome.Source() return source end
local function From(name, ...)
	if source then
		local fn = source[name]
		if type(fn) == "function" then
			local ok, a, b, c = pcall(fn, ...)
			if ok then return a, b, c end
			ns.Log("arena sim %s failed: %s", name, tostring(a))
			return nil
		end
		-- (The sim leaves nothing to the real modules: an empty answer.)
		return nil
	end
	return false
end

local function NameOf(v)
	if type(v) == "table" then return v.name end
	if type(v) == "string" then return v end
	return nil
end
-- A value a view model tags with its source ({ v, src }, ArenaProfile.Card), or the value itself.
local function V(x)
	if type(x) == "table" and x.v ~= nil and x.src ~= nil then return x.v end
	return x
end
ArenaHome.V = V
local function Has(fl, c) return type(fl) == "string" and fl:find(c, 1, true) ~= nil end

-- The mode the player's own things are read in now: T in a rehearsal he is part of, on a test
-- build, or while this realm's live switch is off; else L (Arena.NewMode's rule).
function ArenaHome.ViewMode()
	local T = ns.ArenaTest
	local running = type(T) == "table" and type(T.Running) == "function" and T.Running() ~= nil
	return ns.Arena.NewMode(running)
end
local ViewMode = ArenaHome.ViewMode

-- One event as every screen reads it: { id, kind = "fight"|"card"|"tourney"|"farkle"|"lottery",
-- public, state (the owner's letter), A, B (names), arbiter, lockAt, mode, title, t, round, bo,
-- winner, method, dur, cat, card, realm, over, live, upcoming, count }.
local OVER = { F = true, V = true, N = true, W = true, D = false, X = true }
local LIVE_STATES = { L = true, B = true }
local function Normal(e, kind)
	if type(e) ~= "table" then return nil end
	local id = e.id or e.fid or e.cid or e.tid or e.eid
	if type(id) ~= "string" then return nil end
	local f = type(e.fighters) == "table" and e.fighters or {}
	local state = e.state or e.st
	kind = e.kind or kind or "fight"
	local out = {
		id = id, kind = kind, public = e.public == true or Has(e.fl, "p") or (kind == "card") or nil,
		state = state, A = NameOf(e.A) or NameOf(f.A), B = NameOf(e.B) or NameOf(f.B),
		arbiter = NameOf(e.arbiter) or NameOf(e.arb) or e.writer or e.opener or e.promoter,
		lockAt = tonumber(e.lockAt), mode = e.mode == "T" and "T" or "L", title = type(e.title) == "string" and e.title or nil,
		t = tonumber(e.t or e.at or e.lockAt or e.tCall or e.tAnn or e.t0 or e.tStart), round = e.round, bo = e.bo, winner = NameOf(e.winner),
		method = e.method or e.m, dur = e.dur, cat = e.cat or e.category, card = e.card, tid = e.tid, realm = e.realm,
		gkA = e.gkA or (type(e.A) == "table" and e.A.gk) or (type(f.A) == "table" and f.A.gk) or nil,
		gkB = e.gkB or (type(e.B) == "table" and e.B.gk) or (type(f.B) == "table" and f.B.gk) or nil,
		entrants = e.entrants, size = e.size, stage = e.stage, count = tonumber(e.count), promoter = e.promoter, bouts = e.bouts,
		graceUntil = tonumber(e.graceEnd or e.graceUntil), result = e.result, payouts = e.payouts, pool = e.pool, bettors = e.bettors,
		stake = tonumber(e.stake), cur = e.cur, sim = e.sim,
	}
	if not out.winner and (e.w == "A" or e.w == "B") then out.winner = e.w == "A" and out.A or out.B end
	out.over = e.over == true or e.ended == true or OVER[state or ""] == true
	out.live = e.live == true or LIVE_STATES[state or ""] == true
	out.upcoming = e.upcoming == true or (not out.over and not out.live)
	return out
end
Data.Normal = Normal

local function Mine(ev)
	return type(ev) == "table" and (Same(ev.A, ns.me) or Same(ev.B, ns.me) or Same(ev.arbiter, ns.me))
end
ArenaHome.Mine = Mine

-- Every event this client knows (Fight Nights, tournaments and public fights, then this player's
-- own 1v1 matches), live first, then upcoming by time, then the ended ones newest first.
function Data.Events()
	local sim = From("Events")
	if sim ~= false then return sim or {} end
	local out, seen = {}, {}
	local function Add(e, kind)
		local n = Normal(e, kind)
		if n and not seen[n.id] then
			seen[n.id] = true
			out[#out + 1] = n
		end
	end
	local listed = Call("ArenaFights", "Events", { limit = 40 })
	if type(listed) == "table" then
		for _, e in ipairs(listed) do Add(e) end
	else
		for _, f in ipairs(Call("ArenaFights", "List", { public = true }) or {}) do Add(f, "fight") end
		for _, t in ipairs(Call("ArenaTourney", "All") or Call("ArenaTourney", "List") or {}) do Add(t, "tourney") end
	end
	-- This player's own matches (a 1v1 shows only to its duelists and its arbiter).
	for _, f in ipairs(Call("ArenaFights", "List", { mine = true }) or {}) do Add(f, "fight") end
	local function Rank(e) return e.live and 1 or (e.over and 3 or 2) end
	table.sort(out, function(a, b)
		local ra, rb = Rank(a), Rank(b)
		if ra ~= rb then return ra < rb end
		if ra == 3 then return (a.t or 0) > (b.t or 0) end
		if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
		return a.id < b.id
	end)
	return out
end
local KIND_OF = { F = "fight", N = "card", T = "tourney", K = "farkle", L = "lottery" }
function Data.Event(id)
	local sim = From("Event", id)
	if sim ~= false then return sim end
	if type(id) ~= "string" or id == "" then return nil end
	local kind = KIND_OF[id:sub(1, 1)]
	local e
	if kind == "fight" then e = Call("ArenaFights", "Fight", id)
	elseif kind == "card" then
		local F = ns.ArenaFights
		local C = type(F) == "table" and type(F.Card) == "table" and F.Card or nil
		if C and type(C.Get) == "function" then
			local ok, c = pcall(C.Get, id)
			if ok and type(c) == "table" then
				local okT, title = false, nil
				if type(C.ScreenTitle) == "function" then okT, title = pcall(C.ScreenTitle, id) end
				e = { id = id, kind = "card", st = c.st, title = okT and type(title) == "string" and title or nil, t0 = c.t0,
					promoter = c.promoter, bouts = c.fids, mode = c.mode, public = true }
			end
		end
	elseif kind == "tourney" then e = Call("ArenaTourney", "View", id)
		if type(e) == "table" then e.kind = "tourney" end
	elseif kind == "farkle" then e = Call("FarkleTable", "View", id) end
	local n = Normal(e, kind)
	if n then return n end
	local ev = ns.Arena.EventOf(id)
	if type(ev) == "table" then
		local copy = {}
		for k, v in pairs(ev) do copy[k] = v end
		copy.id = id
		return Normal(copy, ev.kind or kind)
	end
	return nil
end
-- The markets of an event (Markets.View): { lockAt, bank, cur, fee, markets = { ... } }, or nil.
function Data.Markets(id)
	local sim = From("Markets", id)
	if sim ~= false then return sim end
	return Call("Markets", "View", id)
end
function Data.Quote(eid, idx, o, silver)
	local sim = From("Quote", eid, idx, o, silver)
	if sim ~= false then return sim end
	return Call("Markets", "Quote", eid, idx, o, silver)
end
function Data.Tickets(filter)
	local sim = From("Tickets", filter)
	if sim ~= false then return sim or {} end
	return Call("Markets", "Tickets", filter) or {}
end
-- The one wallet (the design: one balance for the Arena, Bones and the Lottery), summed over
-- this realm's banks: { cur, g = { bal, escrow, reserved }, p = { bal, escrow }, pending, banks,
-- debts, receipts, intents, persists, rehearsal }.
function Data.Wallet()
	local sim = From("Wallet")
	if sim ~= false then return sim end
	local mode = ViewMode()
	local w = { g = { bal = 0, escrow = 0, reserved = 0 }, p = { bal = 0, escrow = 0 }, pending = 0, banks = {}, debts = {}, receipts = {}, intents = {} }
	local R = ns.ArenaRoles
	w.cur = R and R.Currency and R.Currency() or "g"
	local view = Call("Wallet", "View", mode)
	local banks = type(view) == "table" and view.banks or Call("Wallet", "Banks", mode) or {}
	for _, bank in ipairs(banks) do
		local name = NameOf(bank)
		local st = type(view) == "table" and bank or (name and Call("Wallet", "Statement", name, mode))
		if type(st) == "table" then
			for _, cur in ipairs({ "g", "p" }) do
				local part = type(st[cur]) == "table" and st[cur] or {}
				for k, v in pairs(part) do
					if tonumber(v) then w[cur][k] = (w[cur][k] or 0) + tonumber(v) end
				end
			end
			w.pending = w.pending + (tonumber(st.pending) or 0)
		end
		w.banks[#w.banks + 1] = { name = name, online = type(bank) == "table" and bank.online == true or Call("Wallet", "Online", name, mode) == true,
			state = type(bank) == "table" and bank.state or nil, paused = type(bank) == "table" and bank.paused or nil,
			closing = type(bank) == "table" and bank.closing or nil, heardAt = type(bank) == "table" and bank.heardAt or nil }
	end
	if type(view) == "table" then
		w.persists, w.rehearsal, w.copper = view.persists, view.rehearsal, view.copper
		w.recommended, w.receiverWhy, w.receivers = view.recommended, view.receiverWhy, view.receivers or {}
		if view.rehearsal and not view.copper then w.cur = "c" end
		if type(view.debts) == "table" then
			for _, d in ipairs(view.debts.obligations or {}) do w.debts[#w.debts + 1] = d end
			w.blocked = view.debts.blocked
		end
		w.receipts = view.receipts or {}
		w.intents = view.intents or {}
	else
		for _, d in ipairs(Call("Debts", "Open", mode) or {}) do w.debts[#w.debts + 1] = d end
		w.receipts = Call("Wallet", "Receipts", mode) or {}
	end
	return w
end
function Data.Receipts()
	local sim = From("Receipts")
	if sim ~= false then return sim or {} end
	return Call("Wallet", "Receipts", ViewMode()) or {}
end
-- The rankings, one compact view (the owner's order, 2026-09-30): a period ("today", "week",
-- "month", "all") and a category ("A" global, "C<class2>", "R<raceID>"), a page at a time:
-- { period, cat, label, periods = { { key, label, selected } }, categories = { { cat, kind, label,
-- selected } }, rows = { { rank, name, rating, delta, wins, losses, tier, gk } }, page, pages,
-- total, mine }.
ArenaHome.PERIODS = { "today", "week", "month", "all" }
ArenaHome.PAGE = 10
function Data.Rankings(period, cat, page)
	local sim = From("Rankings", period, cat, page)
	if sim ~= false then return sim or { rows = {}, periods = {}, categories = {} } end
	local view = Call("ArenaLedger", "RankingView", period, cat, page, { mode = "L" })
	if type(view) == "table" then return view end
	-- (An older ledger: its table alone, all time.)
	cat = cat or "A"
	local rows = Call("ArenaLedger", "Table", cat) or {}
	local v = { period = "all", cat = cat, label = cat == "A" and L.ARENA_CAT_GLOBAL or cat, periods = {}, categories = { { cat = "A", kind = "global", label = L.ARENA_CAT_GLOBAL, selected = cat == "A" } }, rows = {} }
	for _, p in ipairs(ArenaHome.PERIODS) do v.periods[#v.periods + 1] = { key = p, label = L["ARENA_PERIOD_" .. p:upper()], selected = p == "all" } end
	v.total = #rows
	v.pages = math.max(1, math.ceil(#rows / ArenaHome.PAGE))
	v.page = math.max(1, math.min(tonumber(page) or 1, v.pages))
	for i = (v.page - 1) * ArenaHome.PAGE + 1, math.min(#rows, v.page * ArenaHome.PAGE) do
		local r = rows[i]
		v.rows[#v.rows + 1] = { rank = r.rank or i, name = r.name, rating = r.rating, wins = r.wins, losses = r.losses, tier = r.tier, gk = r.gk or r.key }
	end
	return v
end
function Data.Belts()
	local sim = From("Belts")
	if sim ~= false then return sim or {} end
	return Call("ArenaLedger", "Belts", "L") or {}
end
-- The fight history: this player's own (filter.mine: through his gk), else the recent public ones.
-- Rows: { fid, t, A, B, winner, method, dur, cat, opponent, won, delta, private, public }.
function Data.History(filter)
	local sim = From("History", filter)
	if sim ~= false then return sim or {} end
	filter = filter or {}
	local opts = { limit = filter.limit or 20, mode = "L" }
	if filter.mine then
		opts.gk = Call("ArenaProfile", "MyGk")
		if not opts.gk then return {} end
	end
	local list = Call("ArenaLedger", "History", opts)
	if type(list) == "table" then return list end
	local out = {}
	for _, e in ipairs(Call("ArenaFights", "List", { mine = filter.mine or nil, st = { F = true } }) or {}) do out[#out + 1] = Normal(e, "fight") or e end
	return out
end
function Data.Profile(name)
	local sim = From("Profile", name)
	if sim ~= false then return sim end
	return Call("ArenaProfile", "Card", name) or Call("ArenaProfile", "Of", name)
end
function Data.MyProfile()
	local sim = From("MyProfile")
	if sim ~= false then return sim end
	return Call("ProfileEdit", "ViewModel") or Call("ArenaProfile", "Mine")
end
function Data.Verified(name)
	local sim = From("Verified", name)
	if sim ~= false then return sim end
	return Call("HonorsNet", "Verified", name)
end
function Data.Tier(gk)
	local sim = From("Tier", gk)
	if sim ~= false then return sim end
	return gk and Call("ArenaLedger", "Tier", gk) or nil
end
function Data.Tourney(tid)
	local sim = From("Tourney", tid)
	if sim ~= false then return sim end
	return Call("ArenaTourney", "View", tid)
end
function Data.Oracle()
	local sim = From("Oracle")
	if sim ~= false then return sim end
	return Call("HonorsNet", "Oracle")
end
-- Bones: the live tables one may watch, this player's own table, his match history.
function Data.Tables()
	local sim = From("Tables")
	if sim ~= false then return sim or {} end
	return Call("FarkleTable", "LiveTables") or Call("FarkleTable", "Public") or {}
end
function Data.MyTable()
	local sim = From("MyTable")
	if sim ~= false then return sim end
	local t = Call("FarkleTable", "Live")
	if type(t) == "table" and t.id then return Call("FarkleTable", "View", t.id) or t end
	return t
end
-- This player's own games, both modes, newest first (while the King's live switch is off, as in
-- 1.1.6, every game is a rehearsal's).
function Data.BoneHistory()
	local sim = From("BoneHistory")
	if sim ~= false then return sim or {} end
	return Call("FarkleTable", "MyGames") or {}
end
-- The games' ledger (1.1.6, ArenaLedger.GamesView): this player's own games of every kind, or on
-- an auditor's client every game he was told (opts.scope "all"), with its filters.
function Data.Games(opts)
	local sim = From("Games", opts)
	if sim ~= false then return sim or { rows = {}, list = {}, players = {}, total = 0, page = 1, pages = 1 } end
	return Call("ArenaLedger", "GamesView", opts) or { rows = {}, list = {}, players = {}, total = 0, page = 1, pages = 1 }
end
-- Whether this client sees every game (an auditor: ArenaLedger.GamesAuditor).
function Data.GamesAuditor()
	return Call("ArenaLedger", "GamesAuditor", ns.me) == true
end
function Data.Lottery()
	local sim = From("Lottery")
	if sim ~= false then return sim end
	return Call("Lottery", "Today")
end
function Data.Match()
	local sim = From("Match")
	if sim ~= false then return sim end
	return Call("ArenaMatch", "View")
end
-- The games' rankings beyond the arena's (the Games tab, 2026-09-30): Bones' best players
-- ({ { name, games, won } } most wins first) and the Lottery's winners ({ latest = { { name, day,
-- beast, amount } }, biggest = { { name, amount } } }), from their modules when the build has them.
function Data.GamesRanking(game)
	local sim = From("GamesRanking", game)
	if sim ~= false then return sim or {} end
	if game == "bones" then return Call("FarkleTable", "Best", "L") or {} end
	if game == "lottery" then return Call("Lottery", "Winners") or {} end
	return {}
end
function Data.Arbiters()
	local sim = From("Arbiters")
	if sim ~= false then return sim or {} end
	return Call("Stakes", "Search", ViewMode()) or {}
end
function Data.Ledgers()
	local sim = From("Ledgers")
	if sim ~= false then return sim end
	return Call("Wallet", "Ledgers", ViewMode())
end
function Data.BankConsole()
	local sim = From("BankConsole")
	if sim ~= false then return sim end
	return Call("Wallet", "Console")
end
function Data.ArbiterConsole()
	local sim = From("ArbiterConsole")
	if sim ~= false then return sim end
	return Call("Stakes", "Console", ViewMode())
end
function Data.Roster()
	local sim = From("Roster")
	if sim ~= false then return sim or {} end
	return Call("ArenaTest", "Roster") or {}
end
function Data.ChatLines(room)
	local sim = From("ChatLines", room)
	if sim ~= false then return sim or {} end
	return Call("ArenaChat", "Lines", room) or {}
end
-- The challenges waiting for this player's answer (a duel asked of him, a match asked of him as
-- its arbiter): { oid, A, B, stake, how, arbiter, cur, bo, judge, t, mode }.
function Data.Challenges()
	local sim = From("Challenges")
	if sim ~= false then return sim or {} end
	local F = ns.ArenaFights
	local list = type(F) == "table" and type(F.challenges) == "table" and F.challenges or {}
	local out = {}
	for oid, c in pairs(list) do
		if type(c) == "table" and c.incoming and (c.state == "asked" or c.state == "judge") then
			out[#out + 1] = { oid = c.oid or oid, A = c.A, B = c.B, stake = c.stake, how = c.how, arbiter = c.arbiter, cur = c.cur, bo = c.bo,
				judge = c.judge == true, t = c.t, mode = c.mode }
		end
	end
	table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
	return out
end
function Data.Cap(kind)
	local sim = From("Cap", kind)
	if sim ~= false then return sim end
	local S = ns.Standing
	if type(S) == "table" and type(S.Cap) == "function" then
		local ok, v = pcall(S.Cap, kind, ns.me)
		if ok then return tonumber(v) end
	end
	return nil
end
-- Whether a name has an open bet (the only debt mark players see, the design).
function Data.OpenBet(name)
	local sim = From("OpenBet", name)
	if sim ~= false then return sim == true end
	return Call("Debts", "Mark", name) == "open"
end

-- The showcase (the owner's call, 2026-09-30: "the mock data is missing"): on a test build, and on
-- the author's own client, the screens read the sim's sample data (its world, without its bar)
-- wherever the real modules have nothing yet, so every screen shows populated; real data, when
-- there, wins. It only answers reads: nothing is sent from it (an action on a sample event is
-- refused by the real modules, which never heard of it). Olympus_Arena's Sim.lua gives it.
local showcase
function ArenaHome.SetShowcase(src)
	showcase = type(src) == "table" and src or nil
	ns.Arena.Changed()
end
function ArenaHome.ShowcaseOn()
	if not showcase or source then return false end
	if ns.Arena.TestBuild and ns.Arena.TestBuild() then return true end
	return ns.Workshop ~= nil and type(ns.Workshop.Visible) == "function" and ns.Workshop.Visible() == true
end
local function Empty(x)
	if x == nil or x == false then return true end
	if type(x) ~= "table" then return false end
	if type(x.rows) == "table" then return #x.rows == 0 end
	return next(x) == nil
end
for _, name in ipairs({ "Events", "Event", "Markets", "Rankings", "History", "Profile", "MyProfile", "Tourney", "Belts", "ChatLines",
	"GamesRanking", "Arbiters", "Tier", "Challenges", "Tables", "Lottery", "BoneHistory" }) do
	local real = Data[name]
	if type(real) == "function" then
		Data[name] = function(...)
			local a, b, c = real(...)
			local empty = Empty(a)
			-- An identity-only card is real and useful to players, but it must not suppress the
			-- populated own-profile showcase on an author's/test build.
			if name == "Profile" and type(a) == "table" then empty = a.record == nil and a.rating == nil and a.stats == nil end
			if empty and ArenaHome.ShowcaseOn() then
				local fn = showcase[name]
				if type(fn) == "function" then
					local ok, x, y, z = pcall(fn, ...)
					if ok and x ~= nil then return x, y, z end
				end
			end
			return a, b, c
		end
	end
end

---------------------------------------------------------------------------
-- The rules' yes, and the tab's visibility (the design: one rule, here)
---------------------------------------------------------------------------

function ArenaHome.TabVisible()
	return ns.IsMember() and not ns.Arena.Off()
end

-- The live switch in words, the test build and the sim for the banners.
function ArenaHome.Banner()
	local A = ns.Arena
	-- (The sim: no strip on the windows, the owner's call 2026-09-30: its own bar at the top of
	-- the screen says so, and the screens are shown to the guild.)
	if A.Sim() then return nil end
	local t = A.TestBuild()
	if t then return "test", L.ARENA_BANNER_TEST:format(t.n) end
	local T = ns.ArenaTest
	if T and T.Running and T.Running() then return "rehearsal", L.ARENA_BANNER_REHEARSAL end
	return nil
end

---------------------------------------------------------------------------
-- ns.db.arenaUI (the design): 12 fields, checked at load (numbers clamped, unknown keys dropped)
---------------------------------------------------------------------------

local UI_FIELDS = {
	tab = function(v) return type(v) == "string" and #v <= 40 and v or nil end,
	point = function(v) return type(v) == "table" and v or nil end,
	scale = function(v) v = tonumber(v) return v and math.max(0.7, math.min(1.3, v)) or nil end,
	chat = function(v) return type(v) == "table" and v or nil end,
	overlay = function(v) return type(v) == "table" and v or nil end,
	alerts = function(v) return type(v) == "boolean" and v or nil end,
	rehearsals = function(v) return v == true or nil end,
	delay = function(v) v = tonumber(v) return v and math.max(0, math.min(900, math.floor(v))) or nil end,
	ranking = function(v) return type(v) == "table" and v or nil end,
	find = function(v) return type(v) == "table" and v or nil end,
	sounds = function(v) return type(v) == "boolean" and v or nil end,
	seen = function(v) return type(v) == "table" and v or nil end,
}
function ArenaHome.CheckUI()
	if not ns.db then return end
	local ui = ns.db.arenaUI
	if type(ui) ~= "table" then
		ns.db.arenaUI = nil
		return
	end
	for k, v in pairs(ui) do
		local check = UI_FIELDS[k]
		ui[k] = check and check(v) or nil
	end
end
-- The settings table (made on first write).
function ArenaHome.UI()
	if not ns.db then return {} end
	if type(ns.db.arenaUI) ~= "table" then ns.db.arenaUI = {} end
	return ns.db.arenaUI
end
-- Army alerts for public events: on unless the player turned them off.
function ArenaHome.AlertsOn()
	local ui = ns.db and ns.db.arenaUI
	return not (type(ui) == "table" and ui.alerts == false)
end
ns.On("INIT", function() ns.SafeCall("arena ui settings", ArenaHome.CheckUI) end)

---------------------------------------------------------------------------
-- Sounds: the game's own, feature-detected, and the player's switch
---------------------------------------------------------------------------

function ArenaHome.Sound(key)
	local ui = ns.db and ns.db.arenaUI
	if type(ui) == "table" and ui.sounds == false then return false end
	if not (PlaySound and SOUNDKIT) then return false end
	local id = SOUNDKIT[key]
	if not id then return false end
	return pcall(PlaySound, id) and true or false
end

---------------------------------------------------------------------------
-- The Arena tab (Olympus window) and the census line
---------------------------------------------------------------------------

local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Red(s) return "|cffff5050" .. s .. "|r" end

-- Opens the Arena window on a place: "events", "rankings", "history", "profile", "bone",
-- "bone.live", "lottery", "wallet", "director", "games.mine" and "games.all" (the games' ledger's
-- page, 1.1.6) ... with an argument (an event, a name).
function ArenaHome.Open(where, arg)
	if (where == "wallet" or where == "bets" or where == "bank" or where == "ledgers") and not WalletShown() then return false end
	local A = ns.Arena
	local ok = A.LoadUI()
	if not ok then return false end
	local ui = A.ui
	if type(ui) == "table" and type(ui.Open) == "function" then
		ns.SafeCall("arena open", ui.Open, where, arg)
		return true
	end
	ns.Print(L.ARENA_NO_WINDOW)
	return false
end

-- The wallet in one line: "Wallet: 245g · 60g in bets", in chips on a chips rehearsal.
function ArenaHome.WalletLine(w)
	if not WalletShown() then return nil end
	w = w or Data.Wallet()
	if type(w) ~= "table" then return nil end
	local g = type(w.g) == "table" and w.g or {}
	local cur = w.cur or "g"
	local parts = { L.ARENA_WALLET_LINE:format(Money(g.bal or 0, cur)) }
	if (g.escrow or 0) > 0 then parts[#parts + 1] = L.ARENA_WALLET_IN_BETS:format(Money(g.escrow, cur)) end
	if (w.pending or 0) > 0 then parts[#parts + 1] = L.ARENA_WALLET_PENDING:format(w.pending) end
	local p = type(w.p) == "table" and w.p or {}
	if (p.bal or 0) > 0 then parts[#parts + 1] = Money(p.bal, "p") end
	return table.concat(parts, " · ")
end

-- The state of an event in one word (the list's right-hand tag).
local STATE_WORDS = { A = "ARENA_ST_ANNOUNCED", O = "ARENA_ST_OPEN", S = "ARENA_ST_SET", C = "ARENA_ST_CALLED", Y = "ARENA_ST_READY", Z = "ARENA_ST_CLOSING",
	L = "ARENA_ST_LIVE", B = "ARENA_ST_LIVE", R = "ARENA_ST_RESULT", F = "ARENA_ST_FINAL", V = "ARENA_ST_VOID", N = "ARENA_ST_VOID", W = "ARENA_ST_FINAL" }
-- A tournament's letters (ArenaTourney): registration, closed for check-in, the draw, live, final,
-- cancelled; a card's: planned, live, done, cancelled.
local TOURNEY_WORDS = { R = "ARENA_ST_REGISTRATION", K = "ARENA_ST_CHECKIN", D = "ARENA_ST_DRAW", L = "ARENA_ST_LIVE", F = "ARENA_ST_FINAL", X = "ARENA_ST_VOID" }
local CARD_WORDS = { P = "ARENA_ST_ANNOUNCED", L = "ARENA_ST_LIVE", D = "ARENA_ST_FINAL", X = "ARENA_ST_VOID" }
function ArenaHome.StateWord(ev)
	if type(ev) ~= "table" then return "" end
	local words = ev.kind == "tourney" and TOURNEY_WORDS or (ev.kind == "card" and CARD_WORDS or STATE_WORDS)
	local key = words[ev.state or ""]
	return key and L[key] or (ev.over and L.ARENA_ST_FINAL or L.ARENA_ST_ANNOUNCED)
end

-- An event's title: "Torvin Hale vs Selka Drummond", a card's or tournament's own words.
function ArenaHome.EventTitle(ev)
	if type(ev) ~= "table" then return "?" end
	if ev.A and ev.B then return L.ARENA_VS:format(ArenaHome.Name(ev.A), ArenaHome.Name(ev.B)) end
	-- (A card's or a tournament's own title is the one its owner shows on the King's screen: the
	-- King's own words, else the plain word, ArenaFights.Events.)
	if (ev.kind == "tourney" or ev.kind == "card") and type(ev.title) == "string" and ev.title ~= "" then return ns.Codec.Plain(ev.title) end
	if ev.kind == "tourney" then return L.ARENA_TOURNEY_TITLE:format(ev.size or ev.count or "?") end
	if ev.kind == "card" then return L.ARENA_CARD_TITLE end
	if ev.A then return L.ARENA_VS:format(ArenaHome.Name(ev.A), "?") end
	return L.ARENA_EVENT
end

-- The public event taking bets now, with its lock: the census line's and the tab's gold line.
function ArenaHome.OpenPublic()
	local best
	for _, ev in ipairs(Data.Events()) do
		if ev.public and not ev.over and ev.lockAt and ev.lockAt > Now() and (not best or ev.lockAt < best.lockAt) then best = ev end
	end
	return best
end

-- The line on top of the Census and the Realm while a public event takes bets (as the court's
-- line, Court.Line): a click opens the Arena window on it. nil otherwise.
function ArenaHome.CensusLine()
	if not ArenaHome.TabVisible() then return nil end
	local ev = ArenaHome.OpenPublic()
	if not ev then return nil end
	local id = ev.id
	return {
		text = "|TInterface\\Icons\\Ability_DualWield:14:14|t " .. Gold(L.ARENA_CENSUS_LINE:format(ArenaHome.EventTitle(ev), ArenaHome.Clock(ev.lockAt - Now()))),
		onClick = function() ArenaHome.Open("events", id) end,
		tooltip = function(tt)
			tt:AddLine(L.ARENA_CENSUS_TIP_TITLE, 1, 0.82, 0)
			tt:AddLine(L.ARENA_CENSUS_TIP, 1, 1, 1, true)
		end,
		gapAfter = true,
	}
end

-- A live search or match in one line (the design: ArenaMatch.View().line), and its game.
function ArenaHome.MatchLine()
	local m = Data.Match()
	if type(m) ~= "table" then return nil end
	local text = m.line or m.text
	if type(text) ~= "string" or text == "" then return nil end
	local game = type(m.match) == "table" and m.match.game or (type(m.search) == "table" and m.search.game) or m.game
	return ns.Codec.Plain(text), game
end

-- The Arena tab's lines (Views.Register): a summary, each line a click into the Arena window.
function ArenaHome.TabLines()
	local lines = {}
	local kind, banner = ArenaHome.Banner()
	if banner then lines[#lines + 1] = { text = (kind == "sim" and "|cffc080ff" or "|cffff6060") .. banner .. "|r", gapAfter = true } end
	local R = ns.ArenaRoles
	if not (R and R.Live and R.Live()) and not ns.Arena.TestBuild() then
		lines[#lines + 1] = { text = Grey(L.ARENA_TAB_LIVE_OFF), gapAfter = true }
	end
	-- The games, one row each (the owner's call, 2026-09-30): the lab's games window's rows, a
	-- click opens the game; the same four as the tab's buttons.
	lines[#lines + 1] = { header = true, text = L.ARENA_TAB_GAMES }
	-- (test33: the row's icon and name keep their room, Views.Render cutting a description too long
	-- for the rest; the tooltip says it whole.)
	for _, g in ipairs(ArenaHome.GAMES) do
		if not g.shown or g.shown() then
		local open, name, desc = g.open, L[g.label], L[g.desc]
		lines[#lines + 1] = { indent = 1, text = "|T" .. ArenaHome.GameIcon(g) .. ":18:18|t  " .. Gold(name),
			right = Grey(desc), onClick = function() ns.SafeCall("games " .. g.label, open) end,
			tooltip = function(tt)
				tt:AddLine(name, 1, 0.82, 0)
				tt:AddLine(desc, 1, 1, 1, true)
			end }
		end
	end
	-- (the games' ledger, 1.1.6: his own games of every kind, newest first)
	lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_MINE), right = Grey(L.ARENA_GAMES_MINE_DESC),
		onClick = function() ArenaHome.Open("games.mine") end,
		tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_MINE, 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_MINE_TIP, 1, 1, 1, true) end }
	lines[#lines].gapAfter = true
	-- The games' rankings (the staff always; everyone once the King switches them on), then the
	-- staff's own section.
	local staff = ArenaHome.GamesStaff()
	if staff or ArenaHome.RankingsPublic() then ArenaHome.RankingLines(lines) end
	if staff then ArenaHome.StaffLines(lines) end
	ArenaHome.ArbiterLines(lines)
	local census = ArenaHome.CensusLine()
	if census then lines[#lines + 1] = census end
	-- Tonight: the events not over, public first.
	local events, mine = {}, {}
	for _, ev in ipairs(Data.Events()) do
		if not ev.over then
			if ev.public then events[#events + 1] = ev
			elseif Same(ev.A, ns.me) or Same(ev.B, ns.me) or Same(ev.arbiter, ns.me) then mine[#mine + 1] = ev end
		end
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_TAB_TONIGHT }
	if #events == 0 then lines[#lines + 1] = { text = Grey(L.ARENA_TAB_NOTHING), indent = 1 } end
	for i, ev in ipairs(events) do
		if i > 5 then break end
		local id = ev.id
		lines[#lines + 1] = { text = ArenaHome.EventTitle(ev), right = ArenaHome.StateWord(ev), indent = 1, onClick = function() ArenaHome.Open("events", id) end }
	end
	if #mine > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_TAB_MINE }
		for _, ev in ipairs(mine) do
			local id = ev.id
			lines[#lines + 1] = { text = ArenaHome.EventTitle(ev), right = ArenaHome.StateWord(ev), indent = 1, onClick = function() ArenaHome.Open("events", id) end }
		end
	end
	-- (Bones and the Lottery: their rows above open their own windows.)
	-- The wallet, the bets, the bank.
	if WalletShown() then
	lines[#lines + 1] = { header = true, text = L.ARENA_TAB_WALLET }
	local w = Data.Wallet()
	lines[#lines + 1] = { text = ArenaHome.WalletLine(w) or Grey(L.ARENA_TAB_NO_WALLET), indent = 1, onClick = function() ArenaHome.Open("wallet") end }
	for _, d in ipairs(type(w) == "table" and w.debts or {}) do
		lines[#lines + 1] = { text = Red(L.ARENA_TAB_DEBT), indent = 1, onClick = function() ArenaHome.Open("wallet") end }
		break
	end
	local open = 0
	for _, t in ipairs(Data.Tickets({ open = true })) do if not t.settled then open = open + 1 end end
	if open > 0 then lines[#lines + 1] = { text = L.ARENA_TAB_BETS:format(open), indent = 1, onClick = function() ArenaHome.Open("bets") end } end
	for _, b in ipairs(type(w) == "table" and w.banks or {}) do
		lines[#lines + 1] = { text = L.ARENA_TAB_BANK:format(ArenaHome.Name(b.name), b.online and L.ARENA_ONLINE or L.ARENA_OFFLINE), indent = 1 }
	end
	end
	-- A live search or match (the design: ArenaMatch.View()).
	local line, game = ArenaHome.MatchLine()
	if line then
		lines[#lines + 1] = { text = Gold(line), indent = 1, onClick = function() ArenaHome.Open(game == "b" and "bone" or "events") end }
	end
	return lines, L.ARENA_TAB_TITLE, WalletShown() and L.ARENA_TAB_TEXT or L.ARENA_TAB_TEXT_FREE
end

-- The Games tab's staff (the owner's call, 2026-09-30): the King (his Stewards, the author's
-- view of his), the High Council, and the author's own client (its Workshop). They see the games'
-- rankings always and the section "Games & bets": the Director, the Ledgers, the arbiters.
function ArenaHome.GamesStaff()
	-- 1.2: under the author's View as, the role's (ViewAs.lua): presentation alone, and never more
	-- than the author's own staff view below shows him.
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Previewing) == "function" and V.Previewing() then return V.Allows("games-staff") == true end
	if ns.KingsScreen and ns.KingsScreen() then return true end
	if ns.King and ns.King.IsSteward and ns.King.IsSteward() then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(ns.me) then return true end
	return ns.Workshop ~= nil and type(ns.Workshop.Visible) == "function" and ns.Workshop.Visible() == true
end
ArenaHome.rankGame = "arena"
local RANK_GAMES = { "arena", "bones", "lottery" }
local RANK_WORDS = { arena = "ARENA_SECTION_ARENA", bones = "ARENA_SECTION_BONE", lottery = "ARENA_SECTION_LOTTERY" }
-- The games' rankings for everyone, one game at a time (the owner's answer, 2026-10-04: the King
-- and the councillors he names publish, per game): each game's publish word (ArenaRoles.RankPublic),
-- else the King's settings' rankPub. game nil: any of them.
function ArenaHome.RankingsPublic(game)
	local R = ns.ArenaRoles
	if type(R) ~= "table" or type(R.RankPublic) ~= "function" then return false end
	if game then return R.RankPublic(game) == true end
	for _, g in ipairs(RANK_GAMES) do if R.RankPublic(g) == true then return true end end
	return false
end
-- Who may flip a game's switch (the shown one by default): the King, or a councillor the King names
-- for that game (ArenaRoles.MayPublish). The rest of the staff see it read-only.
function ArenaHome.MaySetRankings(game)
	local R = ns.ArenaRoles
	return type(R) == "table" and type(R.MayPublish) == "function" and R.MayPublish(ns.me, game or ArenaHome.rankGame) == true
end
function ArenaHome.SetRankingsPublic(on, game)
	local ok, why = Call("ArenaRoles", "Publish", game or ArenaHome.rankGame, on)
	if not ok then ns.Print(L.ARENA_GAMES_SWITCH_REFUSED:format(tostring(why or "?"))) end
	ns.Fire("ARENA_CHANGED")
	return ok
end
-- Whether this client names the publishers (the King's word T1~J: his character alone).
function ArenaHome.NamesPublishers()
	return ns.King ~= nil and type(ns.King.IsKing) == "function" and ns.King.IsKing() == true
end
-- The King names a councillor for game, or no more (on false): his T1~J again, that one changed.
function ArenaHome.SetPublisher(name, game, on)
	local R = ns.ArenaRoles
	if type(R) ~= "table" or type(R.Publishers) ~= "function" then return false end
	local list, found = {}, false
	for _, e in ipairs(R.Publishers()) do
		if Same(e.name, name) or e.name:lower() == tostring(name):lower() then
			found = true
			e.games[game] = on and true or nil
		end
		list[#list + 1] = e
	end
	if not found and on then list[#list + 1] = { name = name, games = { [game] = true } } end
	local ok, why = Call("ArenaRoles", "SetPublishers", list)
	if not ok then ns.Print(L.ARENA_GAMES_PUBLISHERS_REFUSED:format(tostring(why or "?"))) end
	ns.Fire("ARENA_CHANGED")
	return ok
end
-- The Throne's "Games & bets": the Olympus window on the Games tab, its staff section.
function ArenaHome.OpenStaff()
	ArenaHome.staffShown = true
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("arena") end
end
-- The games whose ranking this player sees: every one for the staff, the published ones for the rest.
function ArenaHome.RankGames()
	local staff = ArenaHome.GamesStaff()
	local out = {}
	for _, g in ipairs(RANK_GAMES) do if staff or ArenaHome.RankingsPublic(g) then out[#out + 1] = g end end
	return out
end
-- The games' rankings, one switchable view: the arena's overall, Bones' best players, the
-- Lottery's latest and biggest winners (only the games this player may see).
local function RankingLines(lines)
	local shown = ArenaHome.RankGames()
	if #shown == 0 then return end
	local game = ArenaHome.rankGame
	local seen = false
	for _, g in ipairs(shown) do if g == game then seen = true end end
	if not seen then game = shown[1] ArenaHome.rankGame = game end
	local words = {}
	for _, g in ipairs(shown) do words[#words + 1] = g == game and Gold(L[RANK_WORDS[g]]) or Grey(L[RANK_WORDS[g]]) end
	lines[#lines + 1] = { header = true, text = L.ARENA_GAMES_RANKINGS, right = table.concat(words, "  ·  "),
		onClick = function()
			local list = ArenaHome.RankGames()
			for i, g in ipairs(list) do if g == ArenaHome.rankGame then ArenaHome.rankGame = list[i % #list + 1] break end end
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
		end,
		tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_RANKINGS, 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_RANKINGS_TIP, 1, 1, 1, true) end }
	local n0 = #lines
	if game == "arena" then
		local view = Data.Rankings("all", "A", 1) or {}
		for i, x in ipairs(view.rows or {}) do
			lines[#lines + 1] = { indent = 1, text = ("#%d  %s"):format(tonumber(x.rank) or i, ArenaHome.Name(x.name or x.gk or "?")),
				right = (x.rating and tostring(math.floor(x.rating + 0.5)) or "-") .. "  " .. Grey(("%d-%d"):format(tonumber(x.wins) or 0, tonumber(x.losses) or 0)) }
		end
	elseif game == "bones" then
		for i, x in ipairs(Data.GamesRanking("bones") or {}) do
			if i > 10 then break end
			local games, won = tonumber(x.games) or 0, tonumber(x.won) or 0
			lines[#lines + 1] = { indent = 1, text = ("#%d  %s"):format(i, ArenaHome.Name(x.name or "?")),
				right = L.ARENA_GAMES_BONES_ROW:format(won, games > 0 and math.floor(won * 100 / games + 0.5) or 0, games) }
		end
	else
		local lot = Data.GamesRanking("lottery") or {}
		if type(lot.latest) == "table" and #lot.latest > 0 then
			lines[#lines + 1] = { indent = 1, text = Gold(L.ARENA_GAMES_LOTTERY_LATEST) }
			for i, x in ipairs(lot.latest) do
				if i > 5 then break end
				lines[#lines + 1] = { indent = 2, text = ("%s  %s"):format(Grey(tostring(x.day or "")), ArenaHome.Name(x.name or "?")),
					right = tostring(x.beast or "") .. "  " .. Money(tonumber(x.amount) or 0) }
			end
		end
		if type(lot.biggest) == "table" and #lot.biggest > 0 then
			lines[#lines + 1] = { indent = 1, text = Gold(L.ARENA_GAMES_LOTTERY_BIGGEST) }
			for i, x in ipairs(lot.biggest) do
				if i > 5 then break end
				lines[#lines + 1] = { indent = 2, text = ("#%d  %s"):format(i, ArenaHome.Name(x.name or "?")), right = Money(tonumber(x.amount) or 0) }
			end
		end
	end
	if #lines == n0 then lines[#lines + 1] = { indent = 1, text = Grey(L.ARENA_GAMES_RANK_EMPTY) } end
	lines[#lines].gapAfter = true
end
-- A publish word in words: "shown by Name, 5 min ago".
local function ChangeText(e)
	return L.ARENA_GAMES_LAST_CHANGE:format(e.on and L.ARENA_GAMES_SHOWN or L.ARENA_GAMES_HIDDEN, ArenaHome.Name(e.from or "?"), ns.Ago(tonumber(e.at)))
end
ArenaHome.ChangeText = ChangeText
-- The King's lines: the High Council, each named or not for the shown game; a click names him,
-- or no more.
local function PublisherLines(lines, game)
	local R = ns.ArenaRoles
	local gameWord = L[RANK_WORDS[game]]
	lines[#lines + 1] = { indent = 1, text = Gold(L.ARENA_GAMES_PUBLISHERS:format(gameWord)),
		tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_PUBLISHERS:format(gameWord), 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_PUBLISHERS_TIP, 1, 1, 1, true) end }
	local named = {}
	for _, e in ipairs(type(R) == "table" and type(R.Publishers) == "function" and R.Publishers() or {}) do
		if e.games[game] then named[e.name:lower()] = true end
	end
	local council = type(R) == "table" and type(R.Councillors) == "function" and R.Councillors() or {}
	if #council == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.ARENA_GAMES_NO_COUNCIL) } end
	for _, name in ipairs(council) do
		local on = named[name:lower()] == true
		lines[#lines + 1] = { indent = 2, text = ArenaHome.Name(name), right = on and Gold(L.ARENA_YES) or Grey(L.ARENA_NO),
			onClick = function() ArenaHome.SetPublisher(name, game, not on) end }
	end
end
-- The staff's section: the shown game's switch (the King's and the councillors he names for it to
-- flip, read-only to the rest; its last change and the log in its tooltip), whom the King names,
-- the Director, the Ledgers, the arbiters.
local function StaffLines(lines)
	lines[#lines + 1] = { header = true, text = L.ARENA_GAMES_STAFF }
	local game = ArenaHome.rankGame
	local gameWord = L[RANK_WORDS[game]] or tostring(game)
	local pub = ArenaHome.RankingsPublic(game)
	local may = ArenaHome.MaySetRankings(game)
	local R = ns.ArenaRoles
	local word = type(R) == "table" and type(R.PublishWord) == "function" and R.PublishWord(game) or nil
	local label = L.ARENA_GAMES_SHOW_GAME:format(gameWord)
	lines[#lines + 1] = { indent = 1, text = may and label or Grey(label),
		right = (pub and Gold(L.ARENA_YES) or Grey(L.ARENA_NO)) .. (may and "" or ("  " .. Grey(L.ARENA_GAMES_READ_ONLY))),
		onClick = may and function() ArenaHome.SetRankingsPublic(not ArenaHome.RankingsPublic(game), game) end or nil,
		tooltip = function(tt)
			tt:AddLine(label, 1, 0.82, 0)
			tt:AddLine(L.ARENA_GAMES_SHOW_ALL_TIP, 1, 1, 1, true)
			if word then tt:AddLine(ChangeText(word), 1, 1, 1, true) end
			local log, shown = type(R) == "table" and type(R.PublishLog) == "function" and R.PublishLog() or {}, 0
			for i = #log, 1, -1 do
				if log[i].game == game and shown < 5 then
					if shown == 0 then tt:AddLine(L.ARENA_GAMES_LOG, 1, 0.82, 0) end
					shown = shown + 1
					tt:AddLine(ChangeText(log[i]), 0.8, 0.8, 0.8, true)
				end
			end
			if not may then tt:AddLine(L.ARENA_GAMES_READ_ONLY_TIP, 0.62, 0.62, 0.62, true) end
			-- (a test build keeps the word on this client: ArenaRoles' MaySend sends no T1 nor AU)
			if ns.Arena and type(ns.Arena.TestBuild) == "function" and ns.Arena.TestBuild() then
				tt:AddLine(L.ARENA_GAMES_TEST_BUILD_TIP, 0.62, 0.62, 0.62, true)
			end
		end }
	if ArenaHome.NamesPublishers() then PublisherLines(lines, game) end
	lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_DIRECTOR), onClick = function() ArenaHome.Open("director") end }
	if WalletShown() then
	lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_LEDGERS), onClick = function() ArenaHome.Open("ledgers") end,
		tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_LEDGERS, 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_LEDGERS_TIP, 1, 1, 1, true) end }
	end
	-- (the games' ledger, 1.1.6: on an auditor's client, every game its players told him)
	if Data.GamesAuditor() then
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_EVERY_GAME:format(tonumber(Call("ArenaLedger", "GamesCount")) or 0)),
			onClick = function() ArenaHome.Open("games.all") end,
			tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_EVERY_GAME:format(tonumber(Call("ArenaLedger", "GamesCount")) or 0), 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_EVERY_GAME_TIP, 1, 1, 1, true) end }
	end
	-- (No arbiters while no wager may happen, ArenaHome.ArbitersOn: no list of them.)
	local list = ArenaHome.ArbitersOn() and Data.Arbiters() or nil
	if list then lines[#lines + 1] = { indent = 1, text = Gold(L.ARENA_GAMES_ARBITERS:format(#list)) } end
	for _, a in ipairs(list or {}) do
		local cap = R and R.ArbiterCap and R.ArbiterCap(a.name)
		lines[#lines + 1] = { indent = 2, text = ArenaHome.Name(a.name) .. (a.online and "" or ("  " .. Grey(L.ARENA_OFFLINE))),
			right = (cap and L.ARENA_GAMES_CAP:format(Money(cap)) or "") .. (a.holds and ("  " .. L.ARENA_GAMES_HOLDS:format(Money(a.holds))) or "") }
	end
	lines[#lines].gapAfter = true
end
-- Whether arbiters exist here (Compliance.Arbiters): only where a wager may happen. 1.1.6: never,
-- so no screen asks for, shows or waits on one (an arbiter is there for the money).
function ArenaHome.ArbitersOn()
	local C = ns.Compliance
	return type(C) == "table" and type(C.Arbiters) == "function" and C.Arbiters() == true
end
-- A listed arbiter (staff or not, ArenaRoles.IsArbiter): his console in the Arena window.
function ArenaHome.IsArbiterHere()
	local R = ns.ArenaRoles
	if type(R) ~= "table" or type(R.IsArbiter) ~= "function" then return false end
	return R.IsArbiter(ns.me, "L") == true or R.IsArbiter(ns.me, "T") == true
end
-- The console's new fight pop-up, over the console.
function ArenaHome.OpenNewFight()
	if not ArenaHome.Open("arbiter") then return false end
	local ui = ns.Arena.ui
	if type(ui) ~= "table" or type(ui.NewFight) ~= "function" then return false end
	ns.SafeCall("arena new fight", ui.NewFight)
	return true
end
-- His lines show: a listed arbiter's; under the author's View as, the Arbiter's preview's alone
-- (ViewAs.lua), whatever the author's own character is.
function ArenaHome.ArbiterShown()
	if not ArenaHome.ArbitersOn() then return false end
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Previewing) == "function" and V.Previewing() then return V.Allows("arbiter") == true end
	return ArenaHome.IsArbiterHere()
end
-- His lines: on duty or off, the console, the fights he judges that are not over, a new fight.
-- (The Arbiter's preview for an author who is no listed arbiter: shown as they are, none acting,
-- ViewAs.Inert: the console's switches would send for real.)
local function ArbiterLines(lines)
	if not ArenaHome.ArbiterShown() then return end
	local own = {}
	local con = Data.ArbiterConsole()
	local onDuty = type(con) == "table" and con.onDuty == true
	local mine = 0
	for _, ev in ipairs(Data.Events()) do
		if ev.kind == "fight" and not ev.over and Same(ev.arbiter, ns.me) then mine = mine + 1 end
	end
	local function Console() ArenaHome.Open("arbiter") end
	own[#own + 1] = { header = true, text = L.ARENA_GAMES_ARBITER, right = onDuty and Gold(L.ARENA_GAMES_ON_DUTY) or Grey(L.ARENA_GAMES_OFF_DUTY) }
	own[#own + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_CONSOLE), onClick = Console,
		tooltip = function(tt) tt:AddLine(L.ARENA_GAMES_CONSOLE, 1, 0.82, 0) tt:AddLine(L.ARENA_GAMES_CONSOLE_TIP, 1, 1, 1, true) end }
	own[#own + 1] = { indent = 1, text = L.ARENA_GAMES_MY_FIGHTS, right = tostring(mine), onClick = Console }
	own[#own + 1] = { indent = 1, text = Gold("> " .. L.ARENA_GAMES_NEW_FIGHT), onClick = function() ArenaHome.OpenNewFight() end }
	own[#own].gapAfter = true
	if not ArenaHome.IsArbiterHere() then own = ns.ViewAs.Inert(own) end
	for _, line in ipairs(own) do lines[#lines + 1] = line end
end
ArenaHome.RankingLines, ArenaHome.StaffLines, ArenaHome.ArbiterLines = RankingLines, StaffLines, ArbiterLines

-- The games (the Games tab's rows and buttons, the owner's call 2026-09-30): Arena, Bones, the
-- Lottery, and the Wallet (Treasury > My money, the design). Icons as the lab's games window's,
-- the first the client has (UI.FirstTexture, ArenaHome.GameIcon); each list ends with a file
-- Forever is known to have (test33): the bone and the Darkmoon ticket its Games tab drew, the coin
-- of its own UI (Blizzard_ObjectiveTracker's bonus objectives, Blizzard_FrameXML's
-- PVPHonorSystem), and for the Arena the honor icon of the player's faction (`lastIcon`) that
-- Forever's own Character window draws on its Honor tab (Blizzard_UIPanels_Game/Camelot/
-- CharacterFrame.lua). (The review of test33: the Arena's sword and dual-wield icons are named by
-- no file Forever loads, Blizzard_ChallengesUI not being one.)
local function OpenMoney()
	if ns.Treasury and ns.Treasury.OpenMoney then return ns.Treasury.OpenMoney() end
	return ArenaHome.Open("wallet")
end
function ArenaHome.HonorIcon()
	local faction = ns.faction or (UnitFactionGroup and UnitFactionGroup("player"))
	return faction == "Horde" and "Interface\\Icons\\INV_SideTab_Honor_Horde_c60" or "Interface\\Icons\\INV_SideTab_Honor_Alliance_c60"
end
ArenaHome.GAMES = {
	{ label = "ARENA_SECTION_ARENA", desc = "ARENA_GAME_ARENA_DESC", icons = { "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\Ability_DualWield" }, lastIcon = ArenaHome.HonorIcon, open = function() ArenaHome.Open() end },
	{ label = "ARENA_SECTION_BONE", desc = "ARENA_GAME_BONE_DESC", icons = { "Interface\\Icons\\INV_Misc_Bone_10" }, open = function() ArenaHome.Open("bone") end },
	{ label = "ARENA_SECTION_LOTTERY", desc = "ARENA_GAME_LOTTERY_DESC", icons = { "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Coin_02" }, open = function() ArenaHome.Open("lottery") end },
	{ label = "ARENA_GAME_WALLET", desc = "ARENA_GAME_WALLET_DESC", icons = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\Icons\\INV_Misc_Coin_01" }, open = OpenMoney, shown = WalletShown },
}
-- A game's icon: the first of its files the client has, its `lastIcon` after them, else the last.
function ArenaHome.GameIcon(g)
	local list = g.icons
	if g.lastIcon then
		list = {}
		for i, path in ipairs(g.icons) do list[i] = path end
		list[#list + 1] = g.lastIcon()
	end
	return ns.UI and ns.UI.FirstTexture and ns.UI.FirstTexture(list) or list[#list]
end
ArenaHome.BUTTONS = {}
for i, g in ipairs(ArenaHome.GAMES) do
	local open = g.open
	ArenaHome.BUTTONS[i] = { g.label, function() open() end, shown = g.shown }
end

-- Copy text: no colour, texture or link codes (the design).
function ArenaHome.Plain(s)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
	return (s:gsub("|", ""))
end

local registered = false
-- The tab, before the window is built (UI.AddTab): after the Chat tab, through the side column's
-- overflow rule (the design). True once it is there.
function ArenaHome.Register()
	if registered then return true end
	local UI = ns.UI
	if type(UI) ~= "table" or type(UI.AddTab) ~= "function" then return false end
	local ok = UI.AddTab({
		-- The tab of all three games, the Arena, Bones and the Lottery (the owner's call,
		-- 2026-09-30): "Games", a die for its icon where the client has one, else the Darkmoon Faire
		-- prize ticket; the crossed swords are the Arena's alone.
		key = "arena", label = "TAB_ARENA", after = "chat",
		icon = function()
			local list = { "Interface\\Icons\\INV_Misc_Dice_01", "Interface\\Icons\\INV_Misc_Dice_02", "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01" }
			return UI.FirstTexture and UI.FirstTexture(list) or list[#list]
		end,
		visible = ArenaHome.TabVisible,
		build = ArenaHome.TabLines,
		buttons = ArenaHome.BUTTONS,
	})
	registered = ok == true
	return registered
end
ArenaHome.Register()

---------------------------------------------------------------------------
-- Small windows of the core: the alert window, the toasts
---------------------------------------------------------------------------

-- (1.1.5: a window's parchment inside ns.Window's metal, f.inner; else `inset` px in.)
local function Parchment(f, inset)
	inset = inset or 8
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	local inner = rawget(f, "inner")
	if type(inner) == "table" then
		bg:SetPoint("TOPLEFT", inner[1], inner[2])
		bg:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
	else
		bg:SetPoint("TOPLEFT", inset, -inset)
		bg:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
	local UI = ns.UI
	local file = UI and UI.FirstTexture and UI.PARCHMENTS and UI.FirstTexture(UI.PARCHMENTS) or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	return bg
end
ArenaHome.Parchment = Parchment
-- The dark ink on parchment (the game's quest fonts, 13 px and more; Morpheus for titles).
function ArenaHome.InkFont(title) if title then return _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge" end return _G.QuestFont and "QuestFont" or "GameFontHighlight" end
-- A short fade in (AnimationGroup only, the design): shown at once where the client has none.
function ArenaHome.FadeIn(f)
	if not (f and f.CreateAnimationGroup) then return end
	-- (A frame's own fields are read with rawget: one never set is nil, whatever the frame's type.)
	if rawget(f, "fadeIn") == nil then
		local ag = f:CreateAnimationGroup()
		local a = ag and ag.CreateAnimation and ag:CreateAnimation("Alpha")
		if a and a.SetFromAlpha then
			a:SetFromAlpha(0)
			a:SetToAlpha(1)
			a:SetDuration(0.18)
			if a.SetSmoothing then a:SetSmoothing("OUT") end
			f.fadeIn = ag
		else
			f.fadeIn = false
		end
	end
	local fade = rawget(f, "fadeIn")
	if fade and fade.Play then
		if fade.Stop then fade:Stop() end
		fade:Play()
	end
end
-- A window of Olympus's own (1.1.5: the Olympus window's bronze metal, ns.Window), its X and the
-- escape list left to the code that shows it, as before.
local function Window(name) return ns.Window(name, UIParent, { inset = false, close = false, escape = false }) end
local function Button(parent, w, h, text, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h or 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- The alert window (OlympusArenaCall, the design): a title, the fighters, a countdown, "Open the
-- Arena" and "Not now". Its countdown ticks on a 0.5 s timer that runs only while it shows.
local call
local function MakeCall()
	local f = Window("OlympusArenaCall")
	f:SetSize(360, 150)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetPoint("TOP", 0, -190)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Parchment(f, 10)
	f.title = f.TitleText -- (its title in the metal's title bar)
	f.who = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont())
	f.who:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
	f.clock = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont())
	f.clock:SetPoint("TOP", f.who, "BOTTOM", 0, -6)
	f.open = Button(f, 150, 24, L.ARENA_BTN_OPEN, function()
		f:Hide()
		local fn = rawget(f, "onOpen")
		if fn then ns.SafeCall("arena alert open", fn) end
	end)
	f.open:SetPoint("BOTTOMLEFT", 22, 18)
	f.later = Button(f, 150, 24, L.ARENA_NOT_NOW, function() f:Hide() end)
	f.later:SetPoint("BOTTOMRIGHT", -22, 18)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnHide", function(self)
		local t = rawget(self, "ticker")
		if t and t.Cancel then t:Cancel() end
		self.ticker = nil
	end)
	ns.EscapeCloses("OlympusArenaCall")
	return f
end
local function Tick()
	local f = call
	if not f or not f:IsShown() then return end
	local lockAt = rawget(f, "lockAt")
	if lockAt then
		local left = lockAt - Now()
		f.clock:SetText(left > 0 and L.ARENA_BETS_CLOSE_IN:format(ArenaHome.Clock(left)) or L.ARENA_BETS_CLOSED)
	else
		f.clock:SetText("")
	end
end
-- spec = { title, who, lockAt, open = fn }
function ArenaHome.ShowCall(spec)
	call = call or MakeCall()
	local f = call
	f.title:SetText(spec.title or "")
	f.who:SetText(spec.who or "")
	f.lockAt = tonumber(spec.lockAt)
	f.onOpen = spec.open
	f.shownSpec = spec
	Tick()
	f:Show()
	ArenaHome.FadeIn(f)
	ArenaHome.Sound("READY_CHECK")
	if rawget(f, "lockAt") and C_Timer and C_Timer.NewTicker and not rawget(f, "ticker") then
		f.ticker = C_Timer.NewTicker(0.5, function() ns.SafeCall("arena alert clock", Tick) end)
	end
	ns.EscapeCloses("OlympusArenaCall")
	return f
end
function ArenaHome.CallFrame() return call end

-- Toasts (OlympusArenaToast): 300 x 56, bottom centre, 4 s each, 3 at most stacked; never a raid
-- warning. For a bet validated, a deposit credited, a payout mailed, a refund.
local toasts = {}
local function Place()
	local y = 150
	for _, t in ipairs(toasts) do
		if t:IsShown() then
			t:ClearAllPoints()
			t:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, y)
			y = y + 62
		end
	end
end
function ArenaHome.Toast(text)
	if type(text) ~= "string" or text == "" then return nil end
	local f
	for _, t in ipairs(toasts) do if not t:IsShown() then f = t break end end
	if not f then
		if #toasts >= 3 then
			f = table.remove(toasts, 1)
			local t = rawget(f, "timer")
			if t and t.Cancel then t:Cancel() end
		else
			f = Window("OlympusArenaToast" .. (#toasts + 1))
			f:SetSize(300, 72)
			f:SetFrameStrata("DIALOG")
			ns.SetWindowTitle(f, L.TAB_ARENA)
			Parchment(f, 8)
			f.text = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont())
			f.text:SetPoint("TOPLEFT", 16, -28)
			f.text:SetPoint("BOTTOMRIGHT", -16, 10)
		end
		toasts[#toasts + 1] = f
	end
	f.text:SetText(text)
	f:Show()
	ArenaHome.FadeIn(f)
	Place()
	if C_Timer and C_Timer.NewTimer then
		local t = rawget(f, "timer")
		if t and t.Cancel then t:Cancel() end
		f.timer = C_Timer.NewTimer(4, function()
			f:Hide()
			Place()
		end)
	end
	return f
end
function ArenaHome.Toasts()
	local out = {}
	for _, t in ipairs(toasts) do if t:IsShown() then out[#out + 1] = t.text:GetText() end end
	return out
end

---------------------------------------------------------------------------
-- A challenge to this player (OlympusArenaChallenge, the design): a duel another player asks of
-- him, or a match he is asked to judge. Accept or Decline, 60 s; a core frame, because the player
-- asked may never have opened the arena. Every answer is his click (Arena.Do): the rules' yes
-- first when he never gave it (the rules pop-up, then the answer).
---------------------------------------------------------------------------

ArenaHome.CHALLENGE_TIME = 60
local challenge
local function StakeWords(c)
	local stake = tonumber(c.stake) or 0
	if stake <= 0 then return L.ARENA_CHALLENGE_CASUAL end
	local how = c.how == "a" and L.ARENA_CHALLENGE_WITH_ARBITER:format(ArenaHome.Name(c.arbiter)) or L.ARENA_CHALLENGE_DIRECT
	return L.ARENA_CHALLENGE_STAKE:format(Money(stake, c.cur), how)
end
function ArenaHome.ChallengeText(c)
	if type(c) ~= "table" then return "", "" end
	local title = c.judge and L.ARENA_CHALLENGE_JUDGE_TITLE or L.ARENA_CHALLENGE_TITLE
	local who = c.judge and L.ARENA_CHALLENGE_JUDGE:format(ArenaHome.Name(c.A), ArenaHome.Name(c.B)) or L.ARENA_CHALLENGE_FROM:format(ArenaHome.Name(c.A))
	local bo = tonumber(c.bo) or 1
	local extra = StakeWords(c) .. (bo > 1 and (" · " .. L.ARENA_CHALLENGE_BO:format(bo)) or "")
	return (c.mode == "T" and L.ARENA_REHEARSAL_PREFIX or "") .. title, who .. "\n" .. extra
end
-- The answer (the window's buttons): the rules' yes first, then Arena.Do.
function ArenaHome.AnswerChallenge(c, yes)
	if type(c) ~= "table" or not c.oid then return false end
	local action = c.judge and "fights.judge" or "fights.answer"
	if yes and not ns.Arena.RulesAccepted() then
		ArenaHome.Open("rules", function() ArenaHome.AnswerChallenge(c, true) end)
		return false, "rules"
	end
	local ok, why = ns.Arena.Do(action, c.oid, yes and true or false)
	if not ok and why then ns.Print(L.ARENA_CHALLENGE_FAILED:format(tostring(why))) end
	return ok, why
end
local function MakeChallenge()
	local f = Window("OlympusArenaChallenge")
	f:SetSize(380, 180)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetPoint("TOP", 0, -240)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Parchment(f, 10)
	f.title = f.TitleText -- (its title in the metal's title bar)
	f.text = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont())
	f.text:SetPoint("TOPLEFT", 28, -54)
	f.text:SetPoint("RIGHT", -28, 0)
	f.clock = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont())
	f.clock:SetPoint("BOTTOM", 0, 52)
	f.yes = Button(f, 150, 26, L.ARENA_ACCEPT, function()
		local c = f.c
		f:Hide()
		ArenaHome.AnswerChallenge(c, true)
	end)
	f.yes:SetPoint("BOTTOMLEFT", 26, 18)
	f.no = Button(f, 150, 26, L.ARENA_DECLINE, function()
		local c = f.c
		f:Hide()
		ArenaHome.AnswerChallenge(c, false)
	end)
	f.no:SetPoint("BOTTOMRIGHT", -26, 18)
	f:SetScript("OnHide", function(self)
		local t = rawget(self, "timer")
		if t and t.Cancel then t:Cancel() end
		self.timer = nil
	end)
	ns.EscapeCloses("OlympusArenaChallenge")
	return f
end
local sounded = {} -- [challenger] = true once his challenge sounded
function ArenaHome.ShowChallenge(c)
	if type(c) ~= "table" then return nil end
	challenge = challenge or MakeChallenge()
	local f = challenge
	f.c = c
	local title, text = ArenaHome.ChallengeText(c)
	f.title:SetText(title)
	f.text:SetText(text)
	f.clock:SetText(L.ARENA_CHALLENGE_CLOCK:format(ArenaHome.CHALLENGE_TIME))
	f:Show()
	ArenaHome.FadeIn(f)
	-- The sound only for a challenger's first challenge in the session.
	local who = type(c.A) == "string" and c.A:lower() or "?"
	if not sounded[who] then sounded[who] = true; ArenaHome.Sound("READY_CHECK") end
	if C_Timer and C_Timer.NewTimer then
		local t = rawget(f, "timer")
		if t and t.Cancel then t:Cancel() end
		f.timer = C_Timer.NewTimer(ArenaHome.CHALLENGE_TIME, function() if f.c == c then f:Hide() end end)
	end
	ns.EscapeCloses("OlympusArenaChallenge")
	return f
end
function ArenaHome.ChallengeFrame() return challenge end
-- ARENA_CHALLENGE (the fights part): one asked of this player shows (held in an instance or while Busy, as
-- every alert); an answer to one of his own is a toast.
local answered = {}
local function OnChallenge(oid)
	if not ArenaHome.TabVisible() or type(oid) ~= "string" then return false end
	for _, c in ipairs(Data.Challenges()) do
		if c.oid == oid then
			local title, text = ArenaHome.ChallengeText(c)
			ns.Print(title .. ": " .. text:gsub("\n", " · "))
			return ns.Alert("arena", "soft", { key = "arena:1v1:" .. oid, what = title,
				open = function()
					for _, x in ipairs(Data.Challenges()) do if x.oid == oid then return true end end
					return false
				end,
				show = function() ArenaHome.ShowChallenge(c) end })
		end
	end
	local F = ns.ArenaFights
	local mine = type(F) == "table" and type(F.challenges) == "table" and F.challenges[oid] or nil
	if type(mine) == "table" and not mine.incoming and mine.state ~= "asked" and answered[oid] ~= mine.state then
		answered[oid] = mine.state
		local key = ({ no = "ARENA_CHALLENGE_NO", yes = "ARENA_CHALLENGE_YES", set = "ARENA_CHALLENGE_SET", ["arbiter-no"] = "ARENA_CHALLENGE_ARBITER_NO" })[mine.state]
		if key then ArenaHome.Toast(L[key]:format(ArenaHome.Name(mine.state == "arbiter-no" and mine.arbiter or mine.B))) end
	end
	return false
end
ArenaHome.OnChallenge = OnChallenge
ns.On("ARENA_CHALLENGE", function(oid) ns.SafeCall("arena challenge", OnChallenge, oid) end)

---------------------------------------------------------------------------
-- The alerts (the design, as amended), from the events of the design
---------------------------------------------------------------------------

local raised = {} -- [key] = true: an alert raised once a session
local opened = {} -- [event id] = true: events this player opened in the Arena window
function ArenaHome.Opened(id) if type(id) == "string" then opened[id] = true end end

-- Whether this player may get a rehearsal's alert: its participants (the group in a group
-- rehearsal; the roster and those with "/oly arena rehearsals on" in an army one).
local function RehearsalAudience()
	local T = ns.ArenaTest
	local r = T and T.Running and T.Running()
	if r then return true end
	local ui = ns.db and ns.db.arenaUI
	return type(ui) == "table" and ui.rehearsals == true
end
-- Who gets an event's alert, and how its text starts ("[Rehearsal] " for T).
local function Audience(ev)
	if not ArenaHome.TabVisible() then return false end
	if ev.mode == "T" and not ns.Arena.TestBuild() and not RehearsalAudience() then return false end
	if ev.mode == "T" and ns.Arena.TestBuild() and not RehearsalAudience() then return false end
	return true
end
local function Prefix(ev) return ev.mode == "T" and L.ARENA_REHEARSAL_PREFIX or "" end
local function Party(ev) return Same(ev.A, ns.me) or Same(ev.B, ns.me) or Same(ev.arbiter, ns.me) end
local function HasTicket(id)
	for _, t in ipairs(Data.Tickets({ eid = id })) do
		if t.eid == id or t.eid == nil then return true end
	end
	return false
end
-- One alert (ns.Alert): its key raised once when once; its window while still current.
local function Raise(tone, key, text, ev, once, window)
	if once then
		if raised[key] then return false end
		raised[key] = true
	end
	local id = ev.id
	ns.Print(text)
	return ns.Alert("arena", tone, {
		text = window ~= false and text or nil, key = key, what = text, own = window == "own" or nil,
		open = function()
			local cur = Data.Event(id)
			return cur ~= nil and not cur.over
		end,
		show = window ~= false and function()
			local cur = Data.Event(id) or ev
			ArenaHome.ShowCall({ title = text, who = ArenaHome.EventTitle(cur), lockAt = cur.lockAt, open = function() ArenaHome.Open("events", id) end })
		end or nil,
	})
end
ArenaHome.Raise = Raise

-- Bets open on an event (MARKETS_OPEN): a public one to every member with alerts on (loud, once);
-- a 1v1 match's to its three people (soft); a rehearsal's to its participants.
local function OnOpen(id)
	local ev = Data.Event(id)
	if not ev or ev.over or not Audience(ev) then return false end
	if ev.public then
		if not ArenaHome.AlertsOn() then return false end
		local key = (ev.mode == "T" and "arena:T:" or "arena:open:") .. id
		return Raise(ev.mode == "T" and "soft" or "loud", key, Prefix(ev) .. L.ARENA_ALERT_OPEN:format(ArenaHome.EventTitle(ev)), ev, true)
	end
	if not Party(ev) then return false end
	return Raise("soft", "arena:1v1:" .. id, Prefix(ev) .. L.ARENA_ALERT_1V1:format(ArenaHome.EventTitle(ev)), ev, true)
end
ArenaHome.OnOpen = OnOpen
-- A fight's state changed (ARENA_FIGHT): a 1v1 match's to its three people only (any state).
local lastState = {}
local function OnFight(id, state)
	local ev = Data.Event(id)
	if not ev or ev.public or not Party(ev) or not Audience(ev) then return false end
	state = state or ev.state
	if lastState[id] == state then return false end
	lastState[id] = state
	return Raise("soft", "arena:1v1:" .. id, Prefix(ev) .. L.ARENA_ALERT_1V1_STATE:format(ArenaHome.EventTitle(ev), ArenaHome.StateWord(ev)), ev, false)
end
-- Bets close in 60 s (MARKETS_CLOSING): players with a bet on it, or its card open here.
local function OnClosing(id)
	local ev = Data.Event(id)
	if not ev or not Audience(ev) then return false end
	if not (HasTicket(id) or opened[id]) then return false end
	return Raise("soft", "arena:closing:" .. id, Prefix(ev) .. L.ARENA_ALERT_CLOSING:format(ArenaHome.EventTitle(ev)), ev, true)
end
-- My fight is called (ARENA_CALLED): the fighter, loud (held, as every alert, under /dnd or in an
-- instance).
local function OnCalled(id)
	local ev = Data.Event(id) or { id = id }
	if not Audience(ev) then return false end
	raised["arena:call:" .. id] = nil -- (a call again is a new one)
	local text = Prefix(ev) .. L.ARENA_ALERT_CALLED:format(ArenaHome.EventTitle(ev))
	ns.Print(text)
	return ns.Alert("arena", "loud", {
		text = text, key = "arena:call:" .. id, what = text,
		open = function() local cur = Data.Event(id) return cur ~= nil and not cur.over and not cur.live end,
		show = function()
			ArenaHome.ShowCall({ title = text, who = L.ARENA_ALERT_CALLED_HOW, open = function()
				Call("ArenaFights", "Here", id)
				ArenaHome.Open("events", id)
			end })
		end,
	})
end
-- A result (ARENA_RESULT): bettors and participants get the window; others who opened it a line.
local function OnResult(id)
	local ev = Data.Event(id)
	if not ev or not Audience(ev) then return false end
	local text = Prefix(ev) .. L.ARENA_ALERT_RESULT:format(ArenaHome.EventTitle(ev), ev.winner and ArenaHome.Name(ev.winner) or "?")
	if HasTicket(id) or Party(ev) then return Raise("soft", "arena:result:" .. id, text, ev, true) end
	if opened[id] and not raised["arena:result:" .. id] then
		raised["arena:result:" .. id] = true
		ns.Print(text)
	end
	return false
end
-- A tournament's registration opening or its start (ARENA_TOURNEY): every member, loud.
local function OnTourney(id, stage)
	local ev = Data.Event(id) or Normal({ id = id, kind = "tourney", public = true }, "tourney")
	if not ev or not Audience(ev) or not ArenaHome.AlertsOn() then return false end
	if stage ~= "R" and stage ~= "L" and stage ~= "open" and stage ~= "start" then return false end
	local text = Prefix(ev) .. ((stage == "R" or stage == "open") and L.ARENA_ALERT_TOURNEY_OPEN or L.ARENA_ALERT_TOURNEY_START)
	return Raise(ev.mode == "T" and "soft" or "loud", "arena:tour:" .. id .. ":" .. tostring(stage), text, ev, true)
end
-- A belt changing hands (ARENA_BELT): a chat line only.
local function OnBelt(cat, holder)
	if not ArenaHome.TabVisible() or type(holder) ~= "string" then return end
	ns.Print(L.ARENA_BELT_LINE:format(ArenaHome.Name(holder)))
end
-- A public Bones table (FARKLE_PUBLIC): soft, once.
local function OnPublicTable(id, state)
	local ev = Data.Event(id) or Normal({ id = id, kind = "farkle", public = true }, "farkle")
	if not ev or not Audience(ev) or not ArenaHome.AlertsOn() or state == "over" then return false end
	return Raise("soft", "arena:farkle:" .. id, Prefix(ev) .. L.ARENA_ALERT_TABLE:format(ArenaHome.EventTitle(ev)), ev, true)
end
-- The wallet's news (WALLET_CREDITED, WALLET_PAID, WALLET_REFUSED): toasts.
local function OnWallet(kind, bank, what)
	if not WalletShown() or not ArenaHome.TabVisible() then return end
	local key = ({ credited = "ARENA_TOAST_CREDITED", paid = "ARENA_TOAST_PAID", refused = "ARENA_TOAST_REFUSED" })[kind]
	local text = L[key]:format(ArenaHome.Name(bank), type(what) == "number" and Money(what) or ns.Codec.Plain(tostring(what or "")))
	ArenaHome.Toast(text)
end

ns.On("MARKETS_OPEN", function(id) ns.SafeCall("arena alert open", OnOpen, id) end)
ns.On("MARKETS_CLOSING", function(id) ns.SafeCall("arena alert closing", OnClosing, id) end)
ns.On("ARENA_LAST_CALL", function(id) ns.SafeCall("arena alert closing", OnClosing, id) end)
ns.On("ARENA_FIGHT", function(id, state) ns.SafeCall("arena alert fight", OnFight, id, state) end)
ns.On("ARENA_CALLED", function(id) ns.SafeCall("arena alert called", OnCalled, id) end)
ns.On("ARENA_RESULT", function(id) ns.SafeCall("arena alert result", OnResult, id) end)
ns.On("ARENA_TOURNEY", function(id, stage) ns.SafeCall("arena alert tourney", OnTourney, id, stage) end)
ns.On("ARENA_BELT", function(cat, holder) ns.SafeCall("arena belt line", OnBelt, cat, holder) end)
ns.On("FARKLE_PUBLIC", function(id, state) ns.SafeCall("arena alert table", OnPublicTable, id, state) end)
ns.On("WALLET_CREDITED", function(bank, what) ns.SafeCall("arena toast", OnWallet, "credited", bank, what) end)
ns.On("WALLET_PAID", function(bank, what) ns.SafeCall("arena toast", OnWallet, "paid", bank, what) end)
ns.On("WALLET_REFUSED", function(bank, what) ns.SafeCall("arena toast", OnWallet, "refused", bank, what) end)
function ArenaHome.ResetAlerts() raised, opened, lastState = {}, {}, {} end -- (tests)

---------------------------------------------------------------------------
-- The King's letters (the design): when this player earns an honour, a letter on parchment from
-- the King naming it and its title, the new frame on the player's own portrait, "Wear it" and
-- "Later". Queued when several come; kept to read again (the profile). Signed "The King", never a
-- name. Its words are one locale table (L.ARENA_LETTER_*), so the moderators can edit them.
---------------------------------------------------------------------------

ArenaHome.LETTERS_KEPT = 40
-- The family of an honour key (the branch's spelling, the design), and its place (1-3).
function ArenaHome.Family(key)
	if type(key) ~= "string" then return nil end
	local place = tonumber(key:match("%-(%d)$")) or 1
	if key:find("^arena%-champion") then return "arena", place end
	if key:find("^arena%-class%-") then return "class", place, key:match("^arena%-class%-(%a+)") end
	if key:find("^arena%-race%-") then return "race", place, key:match("^arena%-race%-(%a+)") end
	if key:find("^donor%-top%-") then return "donorTop", tonumber(key:match("(%d)$")) or 1 end
	if key:find("^donor%-month%-") then return "donorMonth", tonumber(key:match("(%d)$")) or 1 end
	if key:find("^level%-race%-") then return "level", 1, key:match("(%d+)$") end
	if key == "guild-top-leader" then return "guild", 1 end
	if key:find("^oracle%-") then return "oracle", tonumber(key:match("(%d)$")) or 1 end
	return nil
end
local TITLES = {
	arena = { "ARENA_TITLE_CHAMPION", "ARENA_TITLE_CONTENDER", "ARENA_TITLE_CHALLENGER" },
	class = { "ARENA_TITLE_CLASS_1", "ARENA_TITLE_CLASS_2", "ARENA_TITLE_CLASS_3" },
	race = { "ARENA_TITLE_RACE_1", "ARENA_TITLE_RACE_2", "ARENA_TITLE_RACE_3" },
	donorTop = { "ARENA_TITLE_PATRON", "ARENA_TITLE_BENEFACTOR", "ARENA_TITLE_FRIEND" },
	donorMonth = { "ARENA_TITLE_GOLDEN_HAND", "ARENA_TITLE_SILVER_HAND", "ARENA_TITLE_BRONZE_HAND" },
	oracle = { "ARENA_TITLE_ORACLE", "ARENA_TITLE_SEER", "ARENA_TITLE_SOOTHSAYER" },
}
-- The title an honour carries: HonorsNet's words where they are (the fights part), else the fixed patterns of
-- the design.
function ArenaHome.TitleOf(key)
	local t = Call("HonorsNet", "TitleText", key)
	if type(t) == "string" and t ~= "" then return ns.Codec.Plain(t) end
	local family, place, extra = ArenaHome.Family(key)
	if not family then return nil end
	if family == "level" then return L.ARENA_TITLE_FIRST_TO:format(tonumber(extra) or 60) end
	if family == "guild" then return L.ARENA_TITLE_WISEST end
	local keys = TITLES[family]
	local word = keys and L[keys[math.max(1, math.min(3, place))]]
	if not word then return nil end
	if family == "class" then
		local file = tostring(extra or ""):upper()
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or (extra or ""):gsub("^%l", string.upper)
		return word:format(name)
	end
	if family == "race" then return word:format((tostring(extra or ""):gsub("^%l", string.upper))) end
	return word
end

local function Letters()
	if not ns.db then return nil end
	local s = ns.db.arenaLetters
	if type(s) ~= "table" then
		s = { list = {}, seen = {} }
		ns.db.arenaLetters = s
	end
	if type(s.list) ~= "table" then s.list = {} end
	if type(s.seen) ~= "table" then s.seen = {} end
	return s
end
local queue = {}
local letter -- the frame
local ShowNext -- (below)

-- The letter (the owner's look, 2026-09-30): letter paper, the game's own letter font, "To <name>,"
-- then his portrait inside the frame he won, big and centred, the title under it, the King's
-- words, his signature and a seal; Wear it and Later in the footer.
local LETTER_W, LETTER_H, LETTER_PORTRAIT = 460, 580, 96
local INK_R, INK_G, INK_B = 0.18, 0.10, 0.02
local function LetterFont() return _G.MailTextFontNormal and "MailTextFontNormal" or ArenaHome.InkFont() end
local function MakeLetter()
	local f = Window("OlympusArenaLetter")
	f:SetSize(LETTER_W, LETTER_H)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetPoint("CENTER", 0, 20)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Parchment(f, 10)
	f.title = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont(true))
	f.title:SetPoint("TOP", 0, -32)
	f.title:SetText(L.ARENA_LETTER_TITLE)
	f.to = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.to:SetPoint("TOPLEFT", 44, -70)
	f.to:SetTextColor(INK_R, INK_G, INK_B)
	-- The player's own portrait, and the honour's frame round it as round his own on his unit
	-- frame (HonorsNet.NewPortrait: the builder of every Olympus portrait), its art clear of the
	-- lines above and below.
	local H, rig = ns.HonorsNet, nil
	if type(H) == "table" and type(H.NewPortrait) == "function" then
		local okRig, made = pcall(H.NewPortrait, f, LETTER_PORTRAIT)
		if okRig then rig = made else ns.Log("arena HonorsNet portrait failed: %s", tostring(made)) end
	end
	if type(rig) ~= "table" then
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetSize(LETTER_PORTRAIT, LETTER_PORTRAIT)
		rig = { slot = tex, portrait = tex, plain = true, reach = { top = 0, bottom = 0 } }
	end
	local top = 84 + rig.reach.top -- (below "To <name>,")
	local below = top + LETTER_PORTRAIT + rig.reach.bottom
	rig.slot:SetPoint("TOP", 0, -top)
	f.rig, f.portrait = rig, rig.portrait
	f.honour = f:CreateFontString(nil, "ARTWORK", ArenaHome.InkFont(true))
	f.honour:SetPoint("TOP", f, "TOP", 0, -(below + 10))
	f.body = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.body:SetPoint("TOPLEFT", 44, -(below + 50))
	f.body:SetWidth(LETTER_W - 88)
	f.body:SetHeight(130)
	if f.body.SetWordWrap then f.body:SetWordWrap(true) end
	if f.body.SetNonSpaceWrap then f.body:SetNonSpaceWrap(true) end
	f.body:SetJustifyH("LEFT")
	f.body:SetTextColor(INK_R, INK_G, INK_B)
	if f.body.SetJustifyV then f.body:SetJustifyV("TOP") end
	f.sign = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.sign:SetPoint("BOTTOMRIGHT", -48, 88)
	f.sign:SetTextColor(INK_R, INK_G, INK_B)
	f.sign:SetText(L.ARENA_LETTER_SIGNED)
	f.seal = f:CreateTexture(nil, "OVERLAY")
	f.seal:SetSize(44, 44)
	f.seal:SetPoint("BOTTOMLEFT", 44, 72)
	local UI = ns.UI
	f.seal:SetTexture(UI and UI.FirstTexture and UI.FirstTexture({ "Interface\\Icons\\Spell_Holy_SealOfWrath", "Interface\\Icons\\Spell_Holy_SealOfMight" }) or "Interface\\Icons\\Spell_Holy_SealOfMight")
	-- The footer: a line, then Wear it and Later.
	local line = f:CreateTexture(nil, "BORDER")
	line:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	line:SetPoint("BOTTOMLEFT", 16, 56)
	line:SetPoint("BOTTOMRIGHT", -16, 56)
	line:SetHeight(1)
	f.wear = Button(f, 140, 26, L.ARENA_LETTER_WEAR, function()
		local e = f.entry
		if e then
			local family = ArenaHome.Family(e.key)
			local frame = family and e.key or nil
			Call("ArenaProfile", "SetPick", frame, e.key)
			e.worn = true
		end
		f:Hide()
	end)
	f.wear:SetPoint("BOTTOM", -76, 18)
	f.later = Button(f, 140, 26, L.ARENA_LETTER_LATER, function() f:Hide() end)
	f.later:SetPoint("BOTTOM", 76, 18)
	f:SetScript("OnHide", function() ns.SafeCall("arena letters", ShowNext) end)
	ns.EscapeCloses("OlympusArenaLetter")
	return f
end

local function Fill(e)
	letter = letter or MakeLetter()
	local f = letter
	f.entry = e
	local title = ArenaHome.TitleOf(e.key) or e.key
	local family = ArenaHome.Family(e.key) or "arena"
	local text = rawget(L, "ARENA_LETTER_" .. family:upper()) or L.ARENA_LETTER_ARENA
	local who = e.to or (ns.DisplayName and ns.DisplayName(ns.me)) or ns.me or "?"
	f.to:SetText(L.ARENA_LETTER_TO:format(ns.Codec and ns.Codec.Plain(who) or who))
	f.honour:SetText(title)
	f.body:SetText(text:format(title))
	-- The frame he won, on his own portrait (HonorsNet.DressPortrait: none where this client has
	-- no art for it); without HonorsNet, the picture alone.
	if type(ns.HonorsNet) == "table" then
		local H = ns.HonorsNet
		if type(H.DressPortrait) == "function" then ns.SafeCall("arena letter", H.DressPortrait, f.rig, e.key) end
	elseif SetPortraitTexture then
		pcall(SetPortraitTexture, f.portrait, "player")
	end
	f.wear:SetShown(ns.ArenaProfile ~= nil and type(ns.ArenaProfile.SetPick) == "function")
	e.read = true
	-- Centred over the arena window while it is open, as every pop-up of the games.
	local win = _G.OlympusArenaFrame
	if win and win.IsShown and win:IsShown() then
		f:ClearAllPoints()
		f:SetPoint("CENTER", win, "CENTER", 0, 0)
	end
	f:Show()
	ArenaHome.FadeIn(f)
	ArenaHome.Sound("IG_QUEST_LIST_OPEN")
end
ShowNext = function()
	if letter and letter:IsShown() then return end
	local e = table.remove(queue, 1)
	if e then Fill(e) end
end

-- HonorsNet's own letters (the fights part: QueueLetter, ShowLetter, Letters) when this build has them: the
-- letters are then its, and these below stand aside (one letter per honour, never two).
local function HonorsLetters()
	local H = ns.HonorsNet
	return type(H) == "table" and type(H.QueueLetter) == "function" and type(H.ShowLetter) == "function"
end
ArenaHome.HonorsLetters = HonorsLetters

-- A letter for an honour this player earned (HONORS_CHANGED finds them). Queued; shown at once
-- when nothing else is, never in combat (then after it). Returns the entry.
function ArenaHome.Letter(key)
	if type(key) ~= "string" or not ArenaHome.Family(key) then return nil end
	if HonorsLetters() and not ns.Arena.Sim() then return Call("HonorsNet", "QueueLetter", key) end
	local s = Letters()
	if not s then return nil end
	if ns.Arena.Sim() then
		-- (The sim's letter: shown, never kept.)
		local e = { key = key, at = Now(), sim = true }
		queue[#queue + 1] = e
		ShowNext()
		return e
	end
	s.seen[key] = true
	local e = { key = key, at = Now() }
	s.list[#s.list + 1] = e
	while #s.list > ArenaHome.LETTERS_KEPT do table.remove(s.list, 1) end
	queue[#queue + 1] = e
	if not (InCombatLockdown and InCombatLockdown()) then ShowNext() end
	return e
end
-- The letters kept, newest first (the profile's "Letters from the King", to read again).
function ArenaHome.Letters()
	if HonorsLetters() and type(ns.HonorsNet.Letters) == "function" then
		local ok, list = pcall(ns.HonorsNet.Letters)
		local out = {}
		if ok and type(list) == "table" then
			for i = #list, 1, -1 do
				local x = list[i]
				if type(x) == "table" and x.key then out[#out + 1] = { key = x.key, at = x.t or x.at, read = x.read } end
			end
		end
		return out
	end
	local s = Letters()
	local out = {}
	for i = #(s and s.list or {}), 1, -1 do out[#out + 1] = s.list[i] end
	return out
end
function ArenaHome.ReadLetter(e)
	if type(e) ~= "table" or not e.key then return end
	if HonorsLetters() and not ns.Arena.Sim() then return Call("HonorsNet", "ShowLetter", e.key) end
	Fill(e)
end
function ArenaHome.LetterFrame() return letter end
function ArenaHome.LetterQueue() return #queue end

-- The honours this player holds (HonorsNet.Holdings), as a list of keys.
local function Holdings()
	local h = Call("HonorsNet", "Holdings", ns.me)
	local out = {}
	if type(h) ~= "table" then return out end
	for k, v in pairs(h) do
		local key = type(v) == "string" and v or (type(v) == "table" and v.key) or (type(k) == "string" and v and k) or nil
		if type(key) == "string" and ArenaHome.Family(key) then out[#out + 1] = key end
	end
	table.sort(out)
	return out
end
-- HONORS_CHANGED for this player: a letter for each honour not seen before.
local function OnHonours(name)
	if not Same(name, ns.me) or not ArenaHome.TabVisible() or HonorsLetters() then return end
	local s = Letters()
	if not s then return end
	for _, key in ipairs(Holdings()) do
		if not s.seen[key] then ArenaHome.Letter(key) end
	end
end
ns.On("HONORS_CHANGED", function(name) ns.SafeCall("arena letters", OnHonours, name) end)
function ArenaHome.ResetLetters() queue = {} end -- (tests)

---------------------------------------------------------------------------
-- The right-click lines on a player (the design): "Challenge to a duel", "Invite to Bones",
-- "Watch" (when his table lets spectators in), "Arena profile". Through PlayerMenu.lua's shared
-- hook where this build has it (1.1.2), with its target and its menu helper; else through
-- Blizzard's Menu.ModifyMenu directly, with the same checks. Opening a menu sends nothing.
---------------------------------------------------------------------------

function ArenaHome.MenuLines(target, menu)
	if type(target) ~= "table" or type(target.name) ~= "string" or not ArenaHome.TabVisible() then return 0 end
	local name = target.name
	local n = 0
	local off = target.locked == true or ns.Arena.Blocked()
	menu.Button(L.ARENA_MENU_CHALLENGE, function() ArenaHome.Challenge(name) end, L.ARENA_MENU_CHALLENGE, off and L.ARENA_MENU_LOCKED or (ArenaHome.ArbitersOn() and L.ARENA_MENU_CHALLENGE_TIP or L.ARENA_MENU_CHALLENGE_TIP_POINTS), not off)
	n = n + 1
	menu.Button(L.ARENA_MENU_BONE, function() ArenaHome.Open("bone.invite", name) end, L.ARENA_MENU_BONE, off and L.ARENA_MENU_LOCKED or L.ARENA_MENU_BONE_TIP, not off)
	n = n + 1
	local table_ = ArenaHome.WatchableTable(name)
	if table_ then
		menu.Button(L.ARENA_MENU_WATCH, function() ArenaHome.Open("bone.live", table_) end, L.ARENA_MENU_WATCH, L.ARENA_MENU_WATCH_TIP, true)
		n = n + 1
	end
	menu.Button(L.ARENA_MENU_PROFILE, function() ArenaHome.Open("profile", name) end, L.ARENA_MENU_PROFILE, L.ARENA_MENU_PROFILE_TIP, true)
	n = n + 1
	return n
end
-- The live table a player sits at that this client may watch (his table lets spectators in: it
-- is in Bones's live list), or nil.
function ArenaHome.WatchableTable(name)
	if type(name) ~= "string" then return nil end
	local id = Call("FarkleTable", "Watchable", name)
	if type(id) == "string" then return id end
	for _, t in ipairs(Data.Tables()) do
		if type(t) == "table" and t.id then
			for _, who in ipairs({ t.p1, t.p2, NameOf(t.A), NameOf(t.B), type(t.players) == "table" and t.players[1] or nil, type(t.players) == "table" and t.players[2] or nil }) do
				if Same(who, name) then return t.id end
			end
		end
	end
	return nil
end
-- The challenge dialog on a name (the menu, the person card, /oly arena challenge): the companion's.
function ArenaHome.Challenge(name, prefill)
	if not ns.Arena.LoadUI() then return false end
	local ui = ns.Arena.ui
	if type(ui) == "table" and type(ui.Challenge) == "function" then
		ns.SafeCall("arena challenge", ui.Challenge, name, prefill)
		return true
	end
	return false
end

-- Without PlayerMenu.lua (a 1.1.1 base): Blizzard's hook, our own lines, the same rules as its
-- (never ourselves, an offline name, a Battle.net account, a secret value).
ArenaHome.MENUS = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "GUILD", "CHAT_ROSTER" }
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end
function ArenaHome.MenuTarget(which, ctx)
	if type(ctx) ~= "table" then return nil end
	if Secret(ctx.name, ctx.server, ctx.unit, ctx.isSelf, ctx.isOffline, ctx.bnetIDAccount) then return nil end
	if ctx.isSelf or ctx.isOffline or ctx.bnetIDAccount then return nil end
	local name
	local unit = type(ctx.unit) == "string" and ctx.unit ~= "" and ctx.unit or nil
	if unit then
		local isPlayer = not UnitIsPlayer or UnitIsPlayer(unit)
		local isMe = UnitIsUnit and UnitIsUnit(unit, "player")
		if Secret(isPlayer, isMe) or not isPlayer or isMe then return nil end
		name = ns.UnitFullName and ns.UnitFullName(unit)
	elseif type(ctx.name) == "string" and ctx.name ~= "" then
		name = ns.FullName(ns.Normal(ctx.server and ctx.server ~= "" and (ctx.name .. "-" .. ctx.server) or ctx.name))
	end
	if type(name) ~= "string" or name == "" or Same(name, ns.me) then return nil end
	return { name = name, which = which, unit = unit, locked = ns.ChatLocked and ns.ChatLocked() or false }
end
local function OwnMenu(which, root, ctx)
	if not ns.IsMember() then return 0 end
	local target = ArenaHome.MenuTarget(which, ctx)
	if not target then return 0 end
	local count = 0
	local menu = {}
	function menu.Button(text, fn, tipTitle, tipText, enabled)
		if count == 0 then
			if root.CreateDivider then root:CreateDivider() end
			if root.CreateTitle then root:CreateTitle(L.ARENA_MENU_TITLE) end
		end
		count = count + 1
		local d = root:CreateButton(text, function() ns.SafeCall("arena menu", fn) end)
		if d and d.SetTooltip and (tipTitle or tipText) then
			d:SetTooltip(function(tt)
				if tipTitle then tt:AddLine(tipTitle, 1, 0.82, 0) end
				if tipText then tt:AddLine(tipText, 1, 1, 1, true) end
			end)
		end
		if enabled == false and d and d.SetEnabled then d:SetEnabled(false) end
		return d
	end
	ArenaHome.MenuLines(target, menu)
	return count
end
ArenaHome.OwnMenu = OwnMenu
local hooked = false
function ArenaHome.HookMenus()
	if hooked then return hooked end
	local P = ns.PlayerMenu
	if type(P) == "table" and type(P.Add) == "function" then
		hooked = P.Add("arena", ArenaHome.MenuLines, 60) and "shared" or false
		return hooked
	end
	-- (A client without PlayerMenu.lua's list: Blizzard's menus with mouse and keyboard alone.)
	if not ns.Gate.Allowed("player-menu") then return false end
	if not (Menu and type(Menu.ModifyMenu) == "function") then return false end -- gp:player-menu
	for _, which in ipairs(ArenaHome.MENUS) do
		local w = which
		pcall(Menu.ModifyMenu, "MENU_UNIT_" .. w, function(_, root, ctx) -- gp:player-menu
			if not ns.Gate.Allowed("player-menu") then return end
			ns.SafeCall("arena menu", OwnMenu, w, root, ctx)
		end)
	end
	hooked = "own"
	return hooked
end
-- (PlayerMenu.lua's entries take a line at any time; Blizzard's menus exist from login.)
if type(ns.PlayerMenu) == "table" then ArenaHome.HookMenus() end
ns.On("LOGIN", function() ns.SafeCall("arena menus", ArenaHome.HookMenus) end)

---------------------------------------------------------------------------
-- The privacy line (the design): "Your arena fight history", the same switch as the profile's.
-- Off until answered (nil is private), and it never opens the page by itself.
---------------------------------------------------------------------------

local function HistoryPublic()
	local mine = Call("ArenaProfile", "Mine")
	if type(mine) ~= "table" then return nil end
	if mine.pub == nil then return nil end
	return mine.pub == true or mine.pub == 1
end
-- Compatibility storage retained for older installs. There is no protocol/setter for sharing
-- these two blocks: the privacy page reports their real status instead of presenting switches
-- whose booleans were never consumed by a sender or receiver.
local function ProfileShares(make)
	if not ns.db then return {} end
	if type(ns.db.arenaProfile) ~= "table" then
		if not make then return {} end
		ns.db.arenaProfile = {}
	end
	return ns.db.arenaProfile
end
function ArenaHome.ProfileShares(make) return ProfileShares(make) end
function ArenaHome.RegisterConsent()
	local C = ns.Consent
	if type(C) ~= "table" or type(C.Register) ~= "function" then return false end
	local shown = function() return ArenaHome.TabVisible() and not (ns.IsKingCharacter and ns.IsKingCharacter(ns.me)) end
	C.Register({ key = "arenaProfileStats", section = "profile", label = "ARENA_CONSENT_PROFILE_STATS", text = "ARENA_CONSENT_PROFILE_STATS_TEXT", shown = shown,
		readonly = true, status = function() return "derived" end })
	C.Register({ key = "arenaProfileHours", section = "profile", label = "ARENA_CONSENT_PROFILE_HOURS", text = "ARENA_CONSENT_PROFILE_HOURS_TEXT", shown = shown,
		readonly = true, status = function() return "unavailable" end })
	return C.Register({
		key = "arenaHistory", section = "profile", label = "ARENA_CONSENT_HISTORY", text = "ARENA_CONSENT_HISTORY_TEXT",
		shown = function() return ArenaHome.TabVisible() and not (ns.IsKingCharacter and ns.IsKingCharacter(ns.me)) end,
		get = HistoryPublic,
		set = function(on) Call("ArenaProfile", "SetPublic", on and true or false) end,
		pending = function() return false end,
	})
end
ArenaHome.RegisterConsent()

---------------------------------------------------------------------------
-- /oly arena ... (the design): the rest of the sub-commands, each also a click
---------------------------------------------------------------------------

local A = ns.Arena
for _, sub in ipairs({ { "fight", "events" }, { "events", "events" }, { "tournament", "events" }, { "ranking", "rankings" }, { "history", "history" },
	{ "profile", "profile" }, { "wallet", "wallet" }, { "bets", "bets" }, { "bone", "bone" }, { "bones", "bone" }, { "lottery", "lottery" },
	{ "games", "games" }, { "arbiter", "arbiter" }, { "bank", "bank" }, { "ledgers", "ledgers" }, { "director", "director" } }) do
	local where = sub[2]
	A.Slash(sub[1], function(args)
		if sub[1] == "history" and (args == "public" or args == "private") then
			Call("ArenaProfile", "SetPublic", args == "public")
			ns.Print(args == "public" and L.ARENA_HISTORY_PUBLIC or L.ARENA_HISTORY_PRIVATE)
			return
		end
		ArenaHome.Open(where, args ~= "" and args or nil)
	end, sub[1] == "fight" and (WalletShown() and L.ARENA_HELP_OPEN or L.ARENA_HELP_OPEN_FREE) or (sub[1] == "history" and L.ARENA_HELP_HISTORY or nil))
end
A.Slash("challenge", function(args)
	local name = tostring(args or ""):match("^%s*(.-)%s*$")
	if name == "" and UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then name = ns.UnitFullName("target") end
	ArenaHome.Challenge(name ~= "" and name or nil)
end, L.ARENA_HELP_CHALLENGE)
A.Slash("rules", function() ArenaHome.Open("rules") end, L.ARENA_HELP_RULES)
A.Slash("emblem", function() if not Call("ProfileEdit", "Open", "emblem") then ArenaHome.Open("profile") end end)
A.Slash("overlay", function() ArenaHome.Open("overlay") end, L.ARENA_HELP_OVERLAY)
A.Slash("copy", function() ArenaHome.Open("copy") end)
A.Slash("alerts", function(args)
	local on = tostring(args or ""):lower():match("^%s*(%a+)")
	if on ~= "on" and on ~= "off" then ns.Print(L.ARENA_HELP_ALERTS) return end
	ArenaHome.UI().alerts = on == "off" and false or nil
	ns.Print(on == "on" and L.ARENA_ALERTS_ON or L.ARENA_ALERTS_OFF)
end, L.ARENA_HELP_ALERTS)
