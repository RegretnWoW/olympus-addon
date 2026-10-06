-- 1.2, the markets: the markets' test world, over the arena's foundation's World by composition (the design: lib/world.lua is
-- frozen). It gives each client stand-ins of what the money part and the fights part build in parallel, shaped as their
-- documented interfaces (the design), so the markets run end to end:
--   * a Wallet: the bank's ledger (accounts per currency, n/b/z/x entries, settlement through
--     ArenaMath.Settle and ArenaMath.Pickem, voids, the Lottery's rollover), and every entry heard
--     by every client's Wallet.OnEntry (as ZE carries it: no name, no account), at once or held
--     back (w.hold: the bank's backlog) until w:Publish();
--   * Debts and Standing: verified keys (w.keys), debtors (w.debtors), one owner's characters
--     (w.owners), standing caps (w.caps), key claims sent (w.claims);
--   * the events registry: w.events[eid], for the letters F, T, K and L.
-- Every name is invented (World.NAMES).
local H = ...
local World = H.World
local MW = {}

local function Lower(name) return name and name:lower() or nil end

local methods = {}

-- A client, with the stand-ins installed (and again after each login: w:Relog).
function methods:Player(name, where)
	local c = self:Client(name, where)
	self:Install(c)
	return c
end
function methods:Cast(role, where)
	local c = self:Role(role, where)
	self:Install(c)
	return c
end

local function Proxy(w, c, t)
	return setmetatable({}, {
		__index = function(_, k)
			local v = t[k]
			if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
			return v
		end,
		__newindex = function(_, k, v) t[k] = v end,
	})
end

-- The bank's ledger (one per bank character, kept by the world: it survives the bank's logins,
-- as the money part's ledger survives through its replicas).
function methods:Ledger(bank)
	local key = Lower(type(bank) == "table" and bank.name or bank)
	local l = self.ledgers[key]
	if not l then
		l = { seq = 0, entries = {}, accounts = {}, markets = {}, pending = {}, guild = 0, arbiter = {}, pots = {} }
		self.ledgers[key] = l
	end
	return l
end

-- The channel form of an entry: no name, no account (the code is blinded per entry, the design).
local function Public(e)
	local out = {}
	for k, v in pairs(e) do if k ~= "who" and k ~= "acct" then out[k] = v end end
	out.code = "c" .. tostring(e.seq or 0)
	return out
end

function methods:Deliver(bankName, seq, entry)
	for _, c in ipairs(self.clients) do
		if c.online and c.subs then
			for _, fn in ipairs(c.subs) do
				local ok, err = pcall(self.As, self, c, fn, bankName, seq, Public(entry))
				if not ok then c.errors[#c.errors + 1] = "entry: " .. tostring(err) end
			end
		end
	end
end
-- The bank's backlog goes out (n entries, or all).
function methods:Publish(n)
	for _, l in pairs(self.ledgers) do
		local k = 0
		while l.pending[1] and (not n or k < n) do
			local p = table.remove(l.pending, 1)
			self:Deliver(p.bank, p.seq, p.entry)
			k = k + 1
		end
	end
end

local function Write(w, c, entry)
	local l = w:Ledger(c)
	l.seq = l.seq + 1
	entry.seq = l.seq
	l.entries[#l.entries + 1] = entry
	if w.hold then
		l.pending[#l.pending + 1] = { bank = c.name, seq = l.seq, entry = entry }
	else
		w:Deliver(c.name, l.seq, entry)
	end
	return l.seq
end

-- An account at a bank: copper in gold (and points), the facts a deposit's trade gave.
function methods:Deposit(bank, who, copper, points, facts)
	local l = self:Ledger(bank)
	local c = type(who) == "table" and who or self:Find(who)
	local name = c and c.name or who
	local k = self.keys[Lower(name)]
	local a = l.accounts[Lower(name)]
	if not a then
		a = { name = name, g = 0, p = 0, guild = c and c.guild or World.GUILD, level = c and c.level or 60, gk = k and k.gk, fp = k and k.fp, bound = true }
		l.accounts[Lower(name)] = a
	end
	a.g = a.g + (copper or 0)
	a.p = a.p + (points or 0)
	for key, v in pairs(facts or {}) do a[key] = v end
	return a
end
function methods:Balance(bank, who, cur)
	local a = self:Ledger(bank).accounts[Lower(type(who) == "table" and who.name or who)]
	return a and a[cur or "g"] or 0
end

local function MarketKey(eid, idx, B36) return eid .. "." .. B36(idx) end

-- The stand-ins on one client.
function methods:Install(c)
	local w = self
	local ns = c.ns
	c.subs = {}
	local W = ns.Wallet
	local function IsBank() return w:Ledger(c) end
	function W.OnEntry(fn) c.subs[#c.subs + 1] = fn end
	function W.Listen(key, on) c.listening = c.listening or {} c.listening[key] = on and true or nil end
	function W.Online(bank)
		local b = w:Find(bank)
		return b ~= nil and b.online == true
	end
	function W.Statement(bank)
		local a = w:Ledger(bank).accounts[Lower(c.name)]
		if not a then return nil end
		return { g = { bal = a.g, escrow = 0, reserved = 0 }, p = { bal = a.p, escrow = 0 } }
	end
	function W.Account(name)
		local a = IsBank().accounts[Lower(ns.FullName(name))]
		return a and Lower(a.name) or nil
	end
	function W.Facts(acct)
		local a = IsBank().accounts[acct]
		if not a then return nil end
		return { gk = a.gk, guild = a.guild, level = a.level, fp = a.fp, frozen = a.frozen, bound = a.bound, name = a.name }
	end
	function W.Available(acct, cur)
		local a = IsBank().accounts[acct]
		return a and a[cur == "p" and "p" or "g"] or 0
	end
	function W.Register(eid, idx, spec)
		local l = IsBank()
		local key = MarketKey(eid, idx, ns.Arena.B36)
		l.markets[key] = { spec = spec, bets = {}, eid = eid, idx = idx }
		w.registered = (w.registered or 0) + 1
		Write(w, c, { k = "n", eid = eid, idx = idx, market = key })
	end
	function W.Hold(acct, copper, ref)
		local l = IsBank()
		local a = l.accounts[acct]
		local cur = ref.cur == "p" and "p" or "g"
		if not a or a[cur] < copper then return nil, "funds" end
		if w.bankCap and copper > w.bankCap then return nil, "cap" end
		a[cur] = a[cur] - copper
		local mk = l.markets[ref.market] or { bets = {} }
		l.markets[ref.market] = mk
		local e = { k = "b", eid = ref.eid, idx = ref.idx, o = ref.o, copper = copper, nonce = ref.nonce, t = ref.t, who = a.name, acct = acct, cur = cur, i = 1 }
		mk.bets[#mk.bets + 1] = e
		return Write(w, c, e)
	end
	function W.Close(eid, idx)
		w.closed = w.closed or {}
		w.closed[#w.closed + 1] = { eid = eid, idx = idx, t = w.clock }
		Write(w, c, { k = "z", eid = eid, idx = idx })
	end
	local function Credit(l, name, cur, copper)
		local a = l.accounts[Lower(name)]
		if a then a[cur] = a[cur] + copper end
	end
	-- (As the money part's Wallet.Settle: a pot the market carries in, l.pots, joins the money won as a stake
	-- nobody backs; what of it comes back, a refund, stays the market's pot.)
	function W.Settle(eid, idx, winners, scratched)
		local l = IsBank()
		local M = ns.ArenaMath
		local key = MarketKey(eid, idx, ns.Arena.B36)
		local mk = l.markets[key]
		if not mk then return nil, "market" end
		if mk.settledWith or mk.voided or mk.rolled then return nil, "settled" end
		local spec = mk.spec or {}
		local fee = { feeBp = spec.feeBp or 600, arbBp = spec.arbBp or 200, to = spec.to }
		local bets = {}
		for _, b in ipairs(mk.bets) do bets[#bets + 1] = { o = b.o, s = b.copper, who = b.who } end
		local r
		if type(winners) == "string" then
			local rounds = 0
			while 2 ^ rounds < (spec.n or 2) do rounds = rounds + 1 end
			r = assert(M.Pickem(bets, winners, rounds, fee))
		else
			local pot = l.pots[key] or 0
			if pot > 0 then bets[#bets + 1] = { o = "~", s = pot } end
			r = assert(M.Settle(bets, winners, fee, scratched))
			if pot > 0 then l.pots[key] = (r.payouts[#bets] or 0) > 0 and r.payouts[#bets] or nil end
		end
		for i, b in ipairs(mk.bets) do Credit(l, b.who, b.cur, r.payouts[i]) end
		l.guild = l.guild + r.guildFee
		if spec.arbiter then l.arbiter[Lower(spec.arbiter)] = (l.arbiter[Lower(spec.arbiter)] or 0) + r.arbFee end
		mk.result = r
		mk.settledWith = { winners = winners, scratched = scratched }
		Write(w, c, { k = "x", eid = eid, idx = idx, result = type(winners) == "string" and winners or table.concat(winners, "+") })
		return r
	end
	function W.SettleLottery(eid, idx, draw)
		local l = IsBank()
		local key = MarketKey(eid, idx, ns.Arena.B36)
		local mk = l.markets[key]
		if not mk then return nil, "market" end
		if mk.settledWith or mk.voided or mk.rolled then return nil, "settled" end
		local tickets = {}
		for i, bet in ipairs(mk.bets) do
			local id = ns.Lottery.TicketId(bet.seq, bet.i or 1, bet.nonce)
			tickets[i] = { id = id, animal = tonumber(bet.o), stake = bet.copper, who = bet.who }
		end
		local r = assert(ns.Lottery.Settle({ version = ns.Lottery.SETTLEMENT_VERSION, tickets = tickets,
			draw = draw, carry = l.pots[key] or 0, feeBp = 600 }))
		r.wire, r.carried = assert(ns.Lottery.EncodeResult(draw, r.nextCarry)), r.nextCarry
		for i, bet in ipairs(mk.bets) do Credit(l, bet.who, bet.cur, r.payouts[i]) end
		l.pots[key] = r.nextCarry > 0 and r.nextCarry or nil
		l.guild = l.guild + r.fee
		mk.result, mk.settledWith = r, { lottery = r.wire }
		Write(w, c, { k = "x", eid = eid, idx = idx, result = r.wire })
		return r
	end
	-- (Every stake back; a pot carried in stays the market's, as the money part keeps it.)
	function W.Void(eid, idx, code)
		local l = IsBank()
		local mk = l.markets[MarketKey(eid, idx, ns.Arena.B36)]
		if not mk then return nil, "market" end
		if mk.settledWith or mk.voided or mk.rolled then return nil, "settled" end
		for _, b in ipairs(mk.bets) do Credit(l, b.who, b.cur, b.copper) end
		mk.voided = code
		Write(w, c, { k = "x", eid = eid, idx = idx, result = "V", code = code })
		return true
	end
	-- the money part's Wallet.Carry: every stake and the pot go to the later market's pot (x C<market>); on a
	-- void market only its pot (what the markets asks of the money part at merge).
	function W.Carry(eid, idx, toEid, toIdx)
		local l = IsBank()
		local key, to = MarketKey(eid, idx, ns.Arena.B36), MarketKey(toEid, toIdx, ns.Arena.B36)
		local mk = l.markets[key]
		if not mk then return nil, "market" end
		if to == key then return nil, "carry" end
		w.carries = w.carries or {}
		w.carries[#w.carries + 1] = { from = key, to = to }
		if mk.voided or (mk.settledWith and mk.settledWith.lottery) then
			local pot = l.pots[key] or 0
			l.pots[key] = nil
			l.pots[to] = (l.pots[to] or 0) + pot
			mk.carriedTo = to
			Write(w, c, { k = "x", eid = eid, idx = idx, result = "C" .. to })
			return pot
		end
		if mk.settledWith or mk.rolled then return nil, "settled" end
		local pot = l.pots[key] or 0
		for _, b in ipairs(mk.bets) do pot = pot + b.copper end
		l.pots[key] = nil
		l.pots[to] = (l.pots[to] or 0) + pot
		mk.rolled = to
		Write(w, c, { k = "x", eid = eid, idx = idx, result = "C" .. to })
		return pot
	end
	function W.Pot(eid, idx) return IsBank().pots[MarketKey(eid, idx, ns.Arena.B36)] or 0 end
	function W.Scratch(eid, entrant)
		w.scratchCalls = (w.scratchCalls or 0) + 1
	end
	function W.Entries(fn)
		for _, e in ipairs(IsBank().entries) do fn(e.seq, e) end
	end
	-- (the money part's other way to read a market back: its bets and its state.)
	function W.Bets(eid, idx)
		local mk = IsBank().markets[MarketKey(eid, idx, ns.Arena.B36)]
		if not mk then return nil end
		local out = {}
		for _, b in ipairs(mk.bets) do out[#out + 1] = { acct = b.acct, o = b.o, s = b.copper, nonce = b.nonce, seq = b.seq, t = b.t } end
		return out
	end
	function W.Market(eid, idx)
		local l = IsBank()
		local mk = l.markets[MarketKey(eid, idx, ns.Arena.B36)]
		if not mk then return nil end
		local closed = false
		for _, e in ipairs(l.entries) do if e.k == "z" and e.eid == eid and e.idx == idx then closed = true end end
		local result = mk.voided and "V" or (mk.settledWith and mk.settledWith.lottery)
			or (mk.rolled and ("C" .. mk.rolled)) or (mk.settledWith and (type(mk.settledWith.winners) == "string" and mk.settledWith.winners
			or table.concat(mk.settledWith.winners, "+"))) or nil
		-- (the money part's also carries the settlement's result, res: its payouts in the bets' order.)
		return { closed = closed, settled = result ~= nil, result = result, res = mk.result }
	end
	function W.Backlog() return #IsBank().pending end
	-- Every copper the bank holds for its accounts: balances, stakes in play, the guild's and the
	-- arbiters' fees and the pots carried (the stand-in's check that nothing appears or vanishes).
	function W.Total()
		local l = IsBank()
		local t = l.guild
		for _, a in pairs(l.accounts) do t = t + a.g end
		for _, v in pairs(l.arbiter) do t = t + v end
		for _, v in pairs(l.pots) do t = t + v end
		for _, mk in pairs(l.markets) do
			if not (mk.settledWith or mk.voided or mk.rolled) then
				for _, b in ipairs(mk.bets) do if b.cur == "g" then t = t + b.copper end end
			end
		end
		return t
	end
	-- Debts and Standing (the money part's, the design).
	local D, St = ns.Debts, ns.Standing
	function D.Verified(name)
		local k = w.keys[Lower(ns.FullName(name))]
		if not k then return nil end
		return k.gk, k.fp, "unit"
	end
	function D.Blocked(name) return w.debtors[Lower(ns.FullName(name))] == true, "debt" end
	function D.SameOwner(a, b)
		if type(a) ~= "string" or type(b) ~= "string" then return false end
		local x, y = w.owners[Lower(ns.FullName(a))], w.owners[Lower(ns.FullName(b))]
		return x ~= nil and x == y
	end
	function D.SendClaim(to)
		w.claims[#w.claims + 1] = { from = c.name, to = to }
		if w.autoKey then w:Key(c) end
	end
	function D.Open() return {} end
	function St.Cap(kind, name)
		if kind ~= "bet" then return nil end
		return w.caps[Lower(ns.FullName(name or ns.me))]
	end
	-- The events (the fights part's and the Bone Throw tables' registry rows, the Lottery's).
	for _, letter in ipairs({ "F", "T", "K", "L", "N" }) do
		ns.Arena.Events.Register(letter, function(eid) return w.events[eid] end)
	end
	c.M = Proxy(w, c, ns.Markets)
	c.MB = Proxy(w, c, ns.MarketBank)
	w:As(c, function() ns.Markets.Subscribe() end)
end

-- A verified key (as the money part's ZT gives the bank): gk and fingerprint, one per character, or shared.
function methods:Key(c, fp)
	local name = type(c) == "table" and c.name or c
	self.keySeq = (self.keySeq or 0) + 1
	self.keys[Lower(name)] = { gk = "3j.a" .. (0x100000 + self.keySeq), fp = fp or ("fp" .. self.keySeq) }
	return self.keys[Lower(name)]
end

-- A new event id (the id's shape Arena.NewId gives).
function methods:Eid(letter)
	self.eidSeq = (self.eidSeq or 0) + 1
	return (letter or "F") .. "t" .. string.format("%05d", self.eidSeq) .. "zz"
end
local function NameOf(w, c) return type(c) == "table" and c.name or (w:Find(c) and w:Find(c).name) or c end
local function Person(w, c)
	local name = NameOf(w, c)
	local k = w.keys[Lower(name)]
	local cl = w:Find(name)
	return { name = name, gk = k and k.gk, fp = k and k.fp, guild = cl and cl.guild, class = cl and cl.class }
end
-- A fight: { opener, A, B, public (default true), bo, mode, arbiter, lockAt }.
function methods:Fight(o)
	local eid = o.eid or self:Eid("F")
	self.events[eid] = { kind = "fight", opener = NameOf(self, o.opener), fighters = { A = Person(self, o.A), B = Person(self, o.B) },
		public = o.public ~= false, bo = o.bo or 1, mode = o.mode or "L", lockAt = o.lockAt, promoter = o.promoter and NameOf(self, o.promoter) or nil }
	return eid, self.events[eid]
end
-- A tournament: { opener, entrants = { c, ... }, category, size, drawn (its bracket drawn: PK opens), mode }.
function methods:Tourney(o)
	local eid = o.eid or self:Eid("T")
	local entrants = {}
	for i, c in ipairs(o.entrants or {}) do
		local p = Person(self, c)
		p.class = (type(o.classes) == "table" and o.classes[i]) or p.class or "WARRIOR"
		entrants[i] = p
	end
	self.events[eid] = { kind = "tourney", opener = NameOf(self, o.opener), entrants = entrants, public = true, category = o.category,
		size = o.size, drawn = o.drawn, mode = o.mode or "L", lockAt = o.lockAt }
	return eid, self.events[eid]
end
function methods:Farkle(o)
	local eid = o.eid or self:Eid("K")
	self.events[eid] = { kind = "farkle", opener = NameOf(self, o.opener), fighters = { A = Person(self, o.A), B = Person(self, o.B) },
		public = false, mode = o.mode or "L" }
	return eid, self.events[eid]
end
function methods:LotteryDay(o)
	local eid = o.eid or self:Eid("L")
	self.events[eid] = { kind = "lottery", opener = NameOf(self, o.opener), public = true, mode = o.mode or "L", lockAt = o.drawAt, excluded = o.excluded }
	return eid, self.events[eid]
end

-- The client logs out and in (its saved data kept or lost); the stand-ins go in again.
function methods:Relog(c)
	self:Logout(c)
	self:Login(c)
	self:Install(c)
	return c
end

-- Every client's errors, raised.
function methods:NoErrors()
	for _, c in ipairs(self.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

MW.FIGHTER_GUILD = "Olympus Ashvale"

function MW.New(opts)
	local w = World.New(opts)
	w.events, w.ledgers, w.keys, w.debtors, w.owners, w.caps, w.claims = {}, {}, {}, {}, {}, {}, {}
	for k, f in pairs(methods) do w[k] = f end
	return w
end

-- The usual cast: the King, a Steward, a High Councillor, the signed arbiter and auditor, the
-- bank, two fighters and three bettors, all with verified keys; the King names the bank and turns
-- the live switch on (gold, the Treasurer's realm group), and the bettors deposit 100 g each.
-- opts.live = false leaves the switch off; opts.money: each bettor's gold.
function MW.Standard(opts)
	opts = opts or {}
	local w = MW.New(opts)
	local N = World.NAMES
	local t = {}
	t.king = w:Cast("king")
	t.steward = w:Cast("steward")
	t.hc = w:Cast("councillor")
	t.hc2 = w:Cast("councillor2")
	t.arbiter = w:Cast("arbiter")
	t.auditor = w:Cast("auditor")
	t.bank = w:Cast("bank")
	-- The fighters' guild is not the bettors' (KO and B3 refuse a fighter's guildmate).
	t.A = w:Cast("fighterA", { guild = MW.FIGHTER_GUILD })
	t.B = w:Cast("fighterB", { guild = MW.FIGHTER_GUILD })
	t.b1 = w:Cast("bettor1")
	t.b2 = w:Cast("bettor2")
	t.b3 = w:Cast("bettor3")
	for _, extra in ipairs(opts.extra or {}) do t[extra[1]] = w:Player(extra[2], extra[3]) end
	for _, c in ipairs(w.clients) do w:Key(c) end
	-- The bank's saved data has survived a logout (Arena.Persists: gold is refused otherwise).
	if opts.bankPersists ~= false then w:Relog(t.bank) end
	assert(t.king.Roles.SetBanks({ N.bank }))
	if opts.live ~= false then assert(t.king.Roles.SetSettings(opts.settings or { live = 1 })) end
	w:Run(opts.paced and 5 or 0) -- (at the game's pace the words take a few seconds)
	for _, c in ipairs({ t.b1, t.b2, t.b3, t.A, t.B, t.hc, t.hc2, t.steward, t.arbiter, t.auditor, t.king }) do
		w:Deposit(t.bank, c, opts.money or 1000000, opts.points or 0)
	end
	for _, c in ipairs(w.clients) do
		w:As(c, function() c.ns.Arena.SetRules(true) end)
	end
	return w, t
end

return MW
