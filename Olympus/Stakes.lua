local ADDON, ns = ...

-- 1.2, the Blood Arena: Stakes.lua. A stub the arena's core created for the money part (money) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The arbiter-held stake book, direct-mode settlement, the arbiter book to auditors (ZA),
-- availability and search (ZV), exposure from the parties' receipts. Registers ZA ZV.
-- API (the design):
--   Stakes.Open{ id, kind = "fight"|"farkle", A = { name, gk }, B = ..., stake = { A, B }, arbiter }
--     -> ok, why (refuses the King's character, past the arbiter's T1~M cap, a debtor, and a client
--     where Arena.Persists() is false)
--   Stakes.Held(id) -> { A, B }; Stakes.Result(id, "A"|"B"|"V"); Stakes.Lines(id)
--   Stakes.Direct{ id, loser, winner, copper }
--   Stakes.OnDuty(on), Stakes.Search() -> { name, online, zone, free }, Stakes.Room()
--
-- the money part's full contract:
--   Stakes.Open(t) runs on each party's client and on the arbiter's (each refuses on its own): t
--     also takes mode ("L" default; "T" a rehearsal's) and returns ok, why ("king", "persist",
--     "debt", "cap", "busy", "party", "shape", "known"). On a party's client it watches his stake's
--     trade to the arbiter (his receipt, ZR "S<id>", goes to the arbiter and the auditors: the
--     arbiter's exposure comes from those, never from his own book); on the arbiter's it keeps the
--     book: each stake in (line s), an over-stake owed back (a debt of kind change, 24 h), items
--     owed back (kind item, 72 h).
--   Stakes.Held(id) -> { A = copper, B = copper, both = true|false } (the arbiter's book, or a
--     party's own receipt for his side).
--   Stakes.Result(id, side): on the arbiter's client, after the fight's grace (the fights part/the Bones tables decide the
--     side): "A"|"B" pays the winner (ArenaMath: his stake back plus the other's less 6%, of which
--     4% owed to the guild, 2% kept), "V" refunds each stake held. Each owed line is one of the
--     arbiter's own obligations (payout 600 s, refund 24 h, the guild's fee 48 h, ref "A<id>").
--     Returns the lines.
--   Stakes.Lines(id) -> { { kind = "payout"|"fee"|"keep"|"refund"|"change"|"item", name, copper,
--     subject, state = "owed"|"sent"|"done", fill = fn() -> the fill's result } }.
--   Stakes.Direct(t): t = { id, loser, winner, copper, mode, iou = { commit, sig } (the loser's),
--     result = { fid, round, sig } (the loser's signed result), due }: on the loser's client his
--     debt (kind bet, 600 s, ref "D<id>"); on the winner's his credit, the proof he publishes if
--     it is late, and the guild's 6% owed only on what he received (the design).
--   Stakes.OnDuty(on, mode) -> ok, why; Stakes.Search(mode) -> { { name, online, zone, free } }
--     (no amounts); Stakes.Room(name) -> copper under the T1~M cap; Stakes.Console() -> the
--     Arbiter tab's model: { cap, held, room, meter, matches, lines, fees = { owed, late },
--     onDuty, wallet = true when a stake is past 10 g (the wallet is recommended) };
--     Stakes.Books(mode) (auditors) -> { [arbiter] = { header, lines, exposure, cap, busy, at } }.
--   Stakes.Hello(auditor, mode): an auditor's hello heard: the book goes to him.
--   Stakes.SendAvail() (ZV now), Stakes.SendBook(mode, to) (ZA now), Stakes.ExposureOf(arbiter,
--     mode) (an auditor's count from the parties' receipts), Stakes.Book(mode) (the arbiter's own).
--   Buttons: "arbiter.duty" (on, mode), "stakes.fill" (id, i, mode). Events: STAKES_HELD (id: both
--     stakes in).

local L = ns.L
local Stakes = {}
ns.Stakes = Stakes

Stakes.ZV_EVERY = 120
Stakes.ZA_EVERY = 600
Stakes.LINES_MAX = 1000
Stakes.ZA_LINES = 40
Stakes.FRESH = 300            -- an arbiter's availability heard this recently counts
Stakes.WALLET_ABOVE = 10 * 10000
Stakes.PAYOUT_DUE = 600
Stakes.REFUND_DUE = 24 * 3600
Stakes.FEE_DUE = 48 * 3600

local function Now() return ns.Arena.Now() end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end
local function B36(n) return ns.Arena.B36(n) end
local function R() return ns.ArenaRoles end
local function D() return ns.Debts end
local function Mode(mode) return mode == "T" and "T" or "L" end
local function Store(mode) return ns.Arena.Store(Mode(mode)) end

-- The compliance gate (Compliance.lua): whether a wager of this kind may happen here (1.1.6: none).
local function Wagers(kind, game)
	local C = ns.Compliance
	return type(C) == "table" and type(C.Allows) == "function" and C.Allows(kind, game) == true
end
Stakes.Wagers = Wagers
local GAME = { fight = "fight", farkle = "bones" }

local function Book(mode, create)
	local s = create and Store(mode) or ns.Debts.Peek(Mode(mode))
	if not s then return nil end
	if type(s.stakes) ~= "table" then
		if not create then return nil end
		s.stakes = { matches = {}, lines = {}, held = 0, accrued = 0, sent = 0, kept = 0, done = 0, disputes = 0, late = 0 }
	end
	local b = s.stakes
	b.matches = type(b.matches) == "table" and b.matches or {}
	b.lines = type(b.lines) == "table" and b.lines or {}
	return b
end
Stakes.Book = Book

local function Line(b, kind, id, name, copper, how)
	b.lines[#b.lines + 1] = { kind = kind, id = id, name = ns.FullName(name), copper = copper, how = how or "t", t = Now() }
	while #b.lines > Stakes.LINES_MAX do table.remove(b.lines, 1) end
end

-- The copper held now: every stake of the matches not yet paid out or refunded.
local function Held(b)
	local n = 0
	for _, m in pairs(b.matches) do
		if m.state == "open" or m.state == "held" then n = n + (m.A.got or 0) + (m.B.got or 0) end
	end
	return n
end

function Stakes.Room(name)
	local R0 = R()
	name = name or ns.me
	local cap = R0 and R0.ArbiterCap(name) or 0
	if not Same(name, ns.me) then return cap end
	local b = Book("L")
	return ns.ArenaMath.Room(cap, b and Held(b) or 0)
end

---------------------------------------------------------------------------
-- Opening a match's stakes (on each party's client and on the arbiter's)
---------------------------------------------------------------------------

local function Party(t, side)
	local p = type(t[side]) == "table" and t[side] or nil
	local name = p and ns.Arena.Name(p.name)
	local stake = type(t.stake) == "table" and math.floor(tonumber(t.stake[side]) or 0) or 0
	if not name or stake <= 0 then return nil end
	return { name = name, gk = p.gk, need = stake, got = 0, over = 0 }
end

function Stakes.Open(t)
	if type(t) ~= "table" or type(t.id) ~= "string" or not t.id:find("^[%w%-]+$") then return false, "shape" end
	if not Wagers("stake", GAME[t.kind]) then return false, "compliance" end
	local mode = Mode(t.mode)
	local A, B = Party(t, "A"), Party(t, "B")
	local arbiter = ns.Arena.Name(t.arbiter)
	if not A or not B or not arbiter then return false, "shape" end
	local R0 = R()
	-- The King never holds gold: a match he judges runs on a bank's stake market (the design).
	if R0 and R0.IsKing(arbiter) then return false, "king" end
	if mode == "L" and not ns.Arena.Persists() then return false, "persist" end
	local Db = D()
	if Db.SameOwner(arbiter, A.name) or Db.SameOwner(arbiter, B.name) then return false, "party" end
	-- 1.1.6: a party or an arbiter under a moderator's sanction (WatchChat.Barred "games"): no new
	-- match held, on each client that knows it (stakes already held are settled as ever).
	local Sanctioned = ns.Arena.Sanctioned
	if Sanctioned then
		for _, name in ipairs({ A.name, B.name, arbiter }) do
			if Sanctioned(Same(name, ns.me) and nil or name) then return false, "sanction" end
		end
	end
	for _, name in ipairs({ A.name, B.name, arbiter }) do
		if Db.Blocked(name, nil, nil, mode) then return false, "debt" end
	end
	-- The King's cap for this arbiter (T1~M): every party refuses a match past it; an auditor's
	-- "h" mark says he is at it already.
	local cap = R0 and R0.ArbiterCap(arbiter) or 0
	if A.need + B.need > cap then return false, "cap" end
	if Db.Busy(arbiter, mode) and not Same(arbiter, ns.me) then return false, "busy" end
	if Same(ns.me, arbiter) then
		local b = Book(mode, true)
		if b.matches[t.id] then return false, "known" end
		if Held(b) + A.need + B.need > cap then return false, "cap" end
		local s = R0 and R0.Settings() or {}
		b.matches[t.id] = { id = t.id, kind = t.kind == "farkle" and "farkle" or "fight", A = A, B = B, arbiter = arbiter, state = "open", created = Now(), mode = mode,
			feeBp = s.feeBp or 600, arbBp = s.arbBp or 200, lines = {} }
		for _, p in ipairs({ A, B }) do
			ns.ArenaMoney.Expect("held:" .. t.id .. ":" .. Lower(p.name), { partner = p.name, dir = "in", copper = p.need, mode = mode, ref = "S" .. t.id })
		end
		ns.Arena.Involve("stakes", true)
		if Stakes.onDuty then Stakes.SendAvail() end
		ns.Arena.Changed()
		return true
	end
	local mine = Same(ns.me, A.name) and A or (Same(ns.me, B.name) and B or nil)
	if mine then
		local m = D().Mine(mode, true)
		m.stakes = type(m.stakes) == "table" and m.stakes or {}
		m.stakes[t.id] = { id = t.id, arbiter = arbiter, copper = mine.need, sent = 0, t = Now(), side = mine == A and "A" or "B" }
		ns.ArenaMoney.Expect("stake:" .. t.id, { partner = arbiter, dir = "out", copper = mine.need, mode = mode, ref = "S" .. t.id })
		-- What comes back from him (a payout, a refund, change): seen here, so this side confirms it.
		ns.ArenaMoney.Expect("back:" .. t.id, { partner = arbiter, dir = "in", mode = mode })
		ns.Arena.Involve("stakes", true)
	end
	return true
end

function Stakes.Held(id, mode)
	local b = Book(mode)
	local m = b and b.matches[id]
	if m then return { A = m.A.got, B = m.B.got, both = m.A.got >= m.A.need and m.B.got >= m.B.need } end
	local mine = D().Mine(Mode(mode))
	local s = mine and type(mine.stakes) == "table" and mine.stakes[id]
	if s then return { [s.side] = s.sent, both = false } end
	return nil
end

---------------------------------------------------------------------------
-- The trades (ArenaMoney's watcher): stakes in on the arbiter's client, a party's stake out on his
-- own, and anything the arbiter sends back.
---------------------------------------------------------------------------

local function OnFlow(r)
	local Mn = ns.ArenaMoney
	local out, copper = Mn.Net(r)
	for _, mode in ipairs({ "L", "T" }) do
		local b = Book(mode) or { matches = {}, lines = {} }
		-- The arbiter's book: a party's trade fills his stake in each of his open matches with this
		-- arbiter (oldest first); what is left over is owed back, once, as are any items.
		if r.kind == "trade" and not out then
			local mine = {}
			for _, m in pairs(b.matches) do
				if m.state == "open" or m.state == "held" then
					for _, side in ipairs({ "A", "B" }) do
						if Same(m[side].name, r.partner) then mine[#mine + 1] = { m = m, p = m[side] } end
					end
				end
			end
			table.sort(mine, function(x, y)
				if (x.m.created or 0) ~= (y.m.created or 0) then return (x.m.created or 0) < (y.m.created or 0) end
				return x.m.id < y.m.id
			end)
			for _, e in ipairs(mine) do
				local m, p = e.m, e.p
				local take = math.min(copper, p.need - p.got)
				if take > 0 then
					p.got = p.got + take
					Line(b, "s", m.id, p.name, take, "t")
					copper = copper - take
				end
				if m.A.got >= m.A.need and m.B.got >= m.B.need and m.state == "open" then
					m.state = "held"
					ns.Fire("STAKES_HELD", m.id)
				end
			end
			local first = mine[1]
			if first and copper > 0 then
				-- An over-stake: owed back (the design, kind change), created at the event.
				first.p.over = first.p.over + copper
				D().Owe({ kind = "change", creditor = first.p.name, copper = copper, ref = "N" .. first.m.id, due = Now() + Stakes.REFUND_DUE, mode = mode })
				Line(b, "n", first.m.id, first.p.name, copper, "t")
				copper = 0
			end
			if first and (r.items and r.items.got or 0) > 0 then
				D().Owe({ kind = "item", creditor = first.p.name, copper = r.items.got, ref = "I" .. first.m.id, due = Now() + 72 * 3600, mode = mode })
				Line(b, "i", first.m.id, first.p.name, r.items.got, "t")
			end
		end
		-- A line the arbiter paid (a payout, a refund, change): marked sent; the obligation's own
		-- receipt goes through Debts.
		if out and copper > 0 then
			for _, m in pairs(b.matches) do
				for _, line in ipairs(m.lines or {}) do
					if line.state == "owed" and line.kind ~= "keep" and line.kind ~= "fee" and Same(line.name, r.partner) and line.copper == copper then
						line.state, line.sent = "sent", Now()
						Line(b, line.kind == "payout" and "p" or "r", m.id, line.name, copper, r.kind == "trade" and "t" or "m")
						b.sent = (b.sent or 0) + copper
						copper = 0
						break
					end
				end
			end
		end
		-- A party's stake to the arbiter: his receipt to the arbiter and the auditors (the design).
		local mine = D().Mine(mode) or {}
		for id, s in pairs(type(mine.stakes) == "table" and mine.stakes or {}) do
			if r.kind == "trade" and out and Same(s.arbiter, r.partner) and s.sent < s.copper then
				local part = math.min(copper, s.copper - s.sent)
				if part > 0 then
					s.sent = s.sent + part
					D().Receipt({ ref = "S" .. id, payer = ns.me, payee = s.arbiter, copper = part, how = "t", mode = mode, to = { s.arbiter } })
					if s.sent >= s.copper then Mn.Forget("stake:" .. id) end
				end
			end
		end
	end
end
ns.ArenaMoney.Subscribe(function(r) OnFlow(r) end)

---------------------------------------------------------------------------
-- The result (on the arbiter's client): the lines to pay, each one of his obligations
---------------------------------------------------------------------------

local function Subject(kind, id, test)
	local Mn = ns.ArenaMoney
	if kind == "payout" then return Mn.Subject("payout", "A" .. id, test) end
	if kind == "refund" or kind == "change" then return Mn.Subject("refund", "A" .. id, test) end
	if kind == "fee" then return Mn.Subject("fee", "A" .. id, test) end
	return nil
end

function Stakes.Result(id, side, mode)
	mode = Mode(mode)
	local b = Book(mode)
	local m = b and b.matches[id]
	if not m then return nil, "match" end
	if m.state ~= "open" and m.state ~= "held" then return m.lines end
	local Db = D()
	local lines = {}
	local both = m.A.got >= m.A.need and m.B.got >= m.B.need
	-- (A winner is paid only where the gate allows a payout; a void's refunds always go.)
	if (side == "A" or side == "B") and both and not Wagers("payout", GAME[m.kind]) then return nil, "compliance" end
	if side ~= "A" and side ~= "B" or not both then
		-- Void, or a stake missing: every stake held goes back (a refund debt, 24 h).
		for _, s in ipairs({ "A", "B" }) do
			local p = m[s]
			if p.got > 0 then
				lines[#lines + 1] = { kind = "refund", name = p.name, copper = p.got, state = "owed" }
				local o = Db.Owe({ kind = "refund", creditor = p.name, copper = p.got, ref = "R" .. id, due = Now() + Stakes.REFUND_DUE, mode = mode })
				lines[#lines].obligation = o and o.id
			end
		end
		m.state, m.result = "void", "V"
	else
		local M = ns.ArenaMath
		local res = M.Settle({ { o = "A", s = m.A.got }, { o = "B", s = m.B.got } }, side, { m.feeBp, m.arbBp })
		if not res then return nil, "settle" end
		local winner = m[side]
		local payout = res.payouts[side == "A" and 1 or 2]
		lines[#lines + 1] = { kind = "payout", name = winner.name, copper = payout, state = "owed" }
		local o = Db.Owe({ kind = "payout", creditor = winner.name, copper = payout, ref = "P" .. id, due = Now() + Stakes.PAYOUT_DUE, mode = mode })
		lines[#lines].obligation = o and o.id
		if res.guildFee > 0 then
			lines[#lines + 1] = { kind = "fee", name = R() and R().FeeReceiver() or "?", copper = res.guildFee, state = "owed" }
			if mode == "L" then
				local f = Db.Owe({ kind = "fee", copper = res.guildFee, ref = "A" .. id, due = Now() + Stakes.FEE_DUE, mode = mode })
				lines[#lines].obligation = f and f.id
			end
		end
		if res.arbFee > 0 then
			lines[#lines + 1] = { kind = "keep", name = ns.me, copper = res.arbFee, state = "done" }
			b.kept = (b.kept or 0) + res.arbFee
			Line(b, "k", id, ns.me, res.arbFee, "t")
		end
		b.accrued = (b.accrued or 0) + res.guildFee
		m.state, m.result, m.res = "result", side, { payout = payout, guildFee = res.guildFee, arbFee = res.arbFee }
	end
	m.lines = lines
	for _, p in ipairs({ m.A, m.B }) do ns.ArenaMoney.Forget("held:" .. id .. ":" .. Lower(p.name)) end
	b.done = (b.done or 0) + 1
	Stakes.SendBook(mode)
	if Stakes.onDuty then Stakes.SendAvail() end
	ns.Arena.Changed()
	return lines
end

function Stakes.Lines(id, mode)
	mode = Mode(mode)
	local b = Book(mode)
	local m = b and b.matches[id]
	if not m then return nil end
	local out = {}
	for _, line in ipairs(m.lines or {}) do
		local o = line.obligation and D().Find(line.obligation)
		if o and o.state == "c" then line.state = "done" elseif o and o.state == "m" then line.state = "sent" end
		local copy = { kind = line.kind, name = line.name, copper = line.copper, state = line.state, subject = Subject(line.kind, id, mode == "T") }
		if line.kind ~= "keep" and line.state == "owed" then
			copy.fill = function()
				if line.kind == "fee" then
					local W = ns.Wallet
					if mode == "L" and W and W.ReceiverUpdated and not W.ReceiverUpdated() then ns.Print(L.WALLET_RECEIVER_OLD) return "updated" end
					return ns.ArenaMoney.FillMail(line.name, copy.subject, line.copper)
				end
				-- In person by trade, or by mail with the arena's subject.
				if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then return ns.ArenaMoney.FillTrade(line.copper, line.name) end
				return ns.ArenaMoney.FillMail(line.name, copy.subject, line.copper)
			end
		end
		out[#out + 1] = copy
	end
	return out
end

---------------------------------------------------------------------------
-- Direct mode (no arbiter, the design, as amended)
---------------------------------------------------------------------------

function Stakes.Direct(t)
	if type(t) ~= "table" or type(t.id) ~= "string" then return nil, "shape" end
	if not Wagers("payout", GAME[t.kind]) then return nil, "compliance" end
	local mode = Mode(t.mode)
	local loser, winner = ns.Arena.Name(t.loser), ns.Arena.Name(t.winner)
	local copper = math.floor(tonumber(t.copper) or 0)
	if not loser or not winner or copper <= 0 then return nil, "shape" end
	if mode == "L" and not ns.Arena.Persists() then return nil, "persist" end
	local mine = D().Mine(mode, true)
	mine.direct[t.id] = { id = t.id, loser = loser, winner = winner, copper = copper, t = Now() }
	local n, oldest = 0, nil
	for k, v in pairs(mine.direct) do
		n = n + 1
		if not oldest or (v.t or 0) < (mine.direct[oldest].t or 0) then oldest = k end
	end
	if n > 20 then mine.direct[oldest] = nil end
	local due = tonumber(t.due) or (Now() + D().DUE.b)
	if Same(ns.me, loser) then
		return D().Owe({ kind = "bet", creditor = winner, copper = copper, ref = "D" .. t.id, due = due, mode = mode })
	elseif Same(ns.me, winner) then
		local s = R() and R().Settings() or {}
		return D().Credit({ debtor = loser, copper = copper, ref = "D" .. t.id, mid = t.id, due = due, mode = mode, iou = t.iou, result = t.result,
			feeBp = mode == "L" and (s.feeBp or 600) or 0, claim = t.claim })
	end
	return nil, "party"
end

---------------------------------------------------------------------------
-- The book to the auditors (ZA): a header and its last 40 lines, checked whole on arrival.
---------------------------------------------------------------------------

local function Header(b, mode)
	local late, disputes = 0, 0
	for _, o in ipairs(D().Open(mode)) do if o.state == "l" or o.state == "o" then late = late + 1 elseif o.state == "d" then disputes = disputes + 1 end end
	local matches = 0
	for _ in pairs(b.matches) do matches = matches + 1 end
	return ("%s~%s~%s~%s~%s~%s~%s~%s"):format(B36(Now()), B36(Held(b)), B36(b.accrued or 0), B36(b.sent or 0), B36(b.kept or 0), B36(matches), B36(disputes), B36(late))
end
local function BookBody(b, mode)
	local lines = {}
	for i = math.max(1, #b.lines - Stakes.ZA_LINES + 1), #b.lines do
		local l = b.lines[i]
		lines[#lines + 1] = ("%s:%s:%s:%s:%s:%s"):format(l.kind, l.id, ns.FullName(l.name), B36(l.copper), l.how or "t", B36(l.t))
	end
	return Header(b, mode) .. "~" .. table.concat(lines, ";")
end
function Stakes.SendBook(mode, to)
	mode = Mode(mode)
	local b = Book(mode)
	if not b then return 0 end
	local R0 = R()
	if not (R0 and R0.IsArbiter(ns.me, mode)) then return 0 end
	local body = BookBody(b, mode)
	local n = 0
	for _, name in ipairs(to and { to } or D().Auditors(mode)) do
		if ns.Arena.Send("ZA", mode, body, { to = name, low = true }) then n = n + 1 end
	end
	return n
end
function Stakes.Hello(auditor, mode)
	if Stakes.onDuty then Stakes.SendBook(mode, auditor) end
end

local function OnBook(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local R0 = R()
	if not (R0 and R0.Auditor(ns.me, mode) and R0.IsArbiter(sender, mode)) then return end
	local time, held, accrued, sent, kept, matches, disputes, late, rest = ns.Arena.Fields(body, 9)
	local h = { time = ns.Arena.N(time, 0), held = ns.Arena.Copper(held), accrued = ns.Arena.Copper(accrued), sent = ns.Arena.Copper(sent),
		kept = ns.Arena.Copper(kept), matches = ns.Arena.N(matches, 0), disputes = ns.Arena.N(disputes, 0), late = ns.Arena.N(late, 0) }
	for _, v in pairs({ "time", "held", "accrued", "sent", "kept", "matches", "disputes", "late" }) do if h[v] == nil then return end end
	-- Checked whole: every line well formed, and no line past the header's totals.
	local lines, sums = {}, { s = 0, p = 0, r = 0, k = 0, f = 0, n = 0, i = 0 }
	for part in tostring(rest or ""):gmatch("[^;]+") do
		local kind, id, name, copper, how, t = part:match("^([sprkfni]):([%w%-]+):([^:]+):([0-9a-z]+):([tm]):([0-9a-z]+)$")
		name, copper = name and ns.Arena.Name(name), copper and ns.Arena.Copper(copper)
		if not kind or not name or not copper then return end
		lines[#lines + 1] = { kind = kind, id = id, name = name, copper = copper, how = how, t = ns.Arena.N(t, 0) }
		sums[kind] = sums[kind] + copper
	end
	if #lines > Stakes.ZA_LINES or sums.k > h.kept then return end
	local s = Store(mode)
	s.books = type(s.books) == "table" and s.books or {}
	s.books[Lower(sender)] = { name = ns.FullName(sender), header = h, lines = lines, at = Now() }
	ns.Arena.Changed()
end
ns.Comm.Handle("ZA", ns.Arena.Handle("ZA", OnBook))

---------------------------------------------------------------------------
-- Exposure (the design): the auditors' own count of what each arbiter holds, from the parties'
-- receipts; at or over his cap, a "h" mark (no amount) shows him busy in every search.
---------------------------------------------------------------------------

local function Exposure(mode)
	local s = Store(mode)
	s.exposure = type(s.exposure) == "table" and s.exposure or {}
	return s.exposure
end
function Stakes.ExposureOf(arbiter, mode)
	local e = Exposure(mode)[Lower(arbiter) or ""]
	local n = 0
	for _, c in pairs(e and e.matches or {}) do n = n + c end
	return n
end

table.insert(ns.Debts.receiptHooks, function(r, sender, mode)
	local R0 = R()
	if not (R0 and R0.Auditor(ns.me, mode)) then return end
	local id = r.ref:sub(2)
	local kind = r.ref:sub(1, 1)
	local exp = Exposure(mode)
	local arbiter
	if kind == "S" and R0.IsArbiter(r.payee, mode) and Same(sender, r.payer) then
		arbiter = r.payee
		local e = exp[Lower(arbiter)] or { name = ns.FullName(arbiter), matches = {} }
		exp[Lower(arbiter)] = e
		e.matches[id] = (e.matches[id] or 0) + r.copper
	elseif (kind == "P" or kind == "R" or kind == "N") and R0.IsArbiter(r.payer, mode) then
		arbiter = r.payer
		local e = exp[Lower(arbiter)]
		if e then e.matches[id] = nil end
	end
	if not arbiter then return end
	local held = Stakes.ExposureOf(arbiter, mode)
	local cap = R0.ArbiterCap(arbiter)
	local e = exp[Lower(arbiter)]
	local id2 = D().Id("h", "busy", arbiter, "h")
	if held >= cap and cap > 0 and not e.busy then
		e.busy = true
		D().LeaderMark({ id = id2, debtor = arbiter, kind = "h", state = "o" }, mode)
	elseif held < cap and e.busy then
		e.busy = nil
		D().LeaderMark({ id = id2, debtor = arbiter, kind = "h", state = "c" }, mode)
	end
end)

function Stakes.Books(mode)
	mode = Mode(mode)
	local R0 = R()
	if not (R0 and R0.Auditor(ns.me, mode)) then return nil end
	local s = Store(mode)
	local out = {}
	for key, bk in pairs(type(s.books) == "table" and s.books or {}) do
		out[key] = { name = ns.Arena.Mask(bk.name), header = bk.header, lines = bk.lines, at = bk.at, exposure = Stakes.ExposureOf(bk.name, mode),
			cap = R0.ArbiterCap(bk.name), busy = D().Busy(bk.name, mode) }
	end
	for key, e in pairs(Exposure(mode)) do
		if not out[key] then out[key] = { name = ns.Arena.Mask(e.name), exposure = Stakes.ExposureOf(e.name, mode), cap = R0.ArbiterCap(e.name), busy = e.busy == true } end
	end
	return out
end

---------------------------------------------------------------------------
-- Availability (ZV) and the search: free, busy or off, the zone when shared; nothing else.
---------------------------------------------------------------------------

local dutyMode
local function State(mode)
	local b = Book(mode) or { matches = {} }
	if ns.Arena.Blocked() then return "b" end
	for _, m in pairs(b.matches) do
		if m.state == "open" or m.state == "held" then return "b" end
	end
	-- Free only with room for a minimum match, no fee overdue, no debt, not net-off.
	local s = R() and R().Settings() or {}
	if Stakes.Room() < 2 * (s.minBet or 1000) then return "b" end
	if D().Blocked(ns.me, nil, nil, mode) then return "b" end
	for _, o in ipairs(D().Open(mode)) do if o.kind == "f" and (o.state == "l" or o.state == "o") then return "b" end end
	local M = ns.Moderation
	if M and M.SelfOff and M.SelfOff() then return "b" end
	if ns.Arena.Sanctioned and ns.Arena.Sanctioned() then return "b" end -- (1.1.6: WatchChat.Barred)
	return "f"
end
local function SendAvail()
	if not dutyMode then return end
	local mapID = "-"
	local Layers = ns.Layers
	if Layers and Layers.Sharing and Layers.Sharing() and C_Map and C_Map.GetBestMapForUnit then
		local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
		if ok and tonumber(id) then mapID = B36(id) end
	end
	local st = Stakes.onDuty and State(dutyMode) or "o"
	ns.Arena.Send("ZV", dutyMode, st .. "~" .. mapID, { key = "zv", evenBlocked = st == "b" })
end
Stakes.SendAvail = SendAvail

function Stakes.OnDuty(on, mode)
	mode = Mode(mode)
	local R0 = R()
	if on then
		if not (R0 and R0.IsArbiter(ns.me, mode)) then return false, "unlisted" end
		if R0.IsKing(ns.me) then return false, "king" end
		if mode == "L" and not ns.Arena.Persists() then return false, "persist" end
		Stakes.onDuty, dutyMode = true, mode
		ns.Arena.Involve("arbiter", true)
		ns.Arena.Every(Stakes.ZV_EVERY, "stakes zv", SendAvail)
		ns.Arena.Every(Stakes.ZA_EVERY, "stakes za", function() Stakes.SendBook(mode) end)
		SendAvail()
		return true
	end
	if Stakes.onDuty then
		Stakes.onDuty = false
		SendAvail()
	end
	dutyMode = nil
	ns.Arena.Every(Stakes.ZV_EVERY, "stakes zv", nil)
	ns.Arena.Every(Stakes.ZA_EVERY, "stakes za", nil)
	ns.Arena.Involve("arbiter", false)
	return true
end

local function OnAvail(dist, sender, mode, body)
	if dist == "WHISPER" then return end
	if ns.Arena.RealmOf(sender) ~= ns.realm then return end
	local R0 = R()
	if not (R0 and R0.IsArbiter(sender, mode)) then return end
	local st, mapID = ns.Arena.Fields(body, 2)
	if st ~= "f" and st ~= "b" and st ~= "o" then return end
	local s = Store(mode)
	s.avail = type(s.avail) == "table" and s.avail or {}
	s.avail[Lower(sender)] = { name = ns.FullName(sender), state = st, mapID = mapID ~= "-" and ns.Arena.N(mapID, 0) or nil, heardAt = Now() }
	ns.Arena.Changed()
end
ns.Comm.Handle("ZV", ns.Arena.Handle("ZV", OnAvail))

function Stakes.Search(mode)
	mode = Mode(mode)
	local s = Store(mode)
	local out = {}
	for _, a in pairs(type(s.avail) == "table" and s.avail or {}) do
		local online = Now() - (a.heardAt or 0) <= Stakes.FRESH and a.state ~= "o"
		out[#out + 1] = { name = a.name, online = online, zone = a.mapID, free = online and a.state == "f" and not D().Busy(a.name, mode) and not D().Mark(a.name, mode) }
	end
	table.sort(out, function(x, y)
		if x.free ~= y.free then return x.free end
		return x.name < y.name
	end)
	return out
end

function Stakes.Console(mode)
	mode = Mode(mode)
	local R0 = R()
	local b = Book(mode) or { matches = {}, lines = {} }
	local cap = R0 and R0.ArbiterCap(ns.me) or 0
	local held = Held(b)
	local matches, lines, big = {}, {}, false
	for id, m in pairs(b.matches) do
		matches[#matches + 1] = { id = id, kind = m.kind, A = { name = m.A.name, need = m.A.need, got = m.A.got }, B = { name = m.B.name, need = m.B.need, got = m.B.got },
			state = m.state, result = m.result, lines = Stakes.Lines(id, mode) }
		if m.A.need > Stakes.WALLET_ABOVE or m.B.need > Stakes.WALLET_ABOVE then big = true end
	end
	table.sort(matches, function(x, y) return x.id < y.id end)
	for i = math.max(1, #b.lines - 40), #b.lines do lines[#lines + 1] = b.lines[i] end
	local owed, late = 0, false
	for _, o in ipairs(D().Open(mode)) do
		if o.kind == "f" then
			owed = owed + (o.copper - (o.paid or 0))
			if o.state == "l" or o.state == "o" then late = true end
		end
	end
	return { cap = cap, held = held, room = ns.ArenaMath.Room(cap, held), meter = cap > 0 and held / cap or 0, matches = matches, lines = lines,
		fees = { owed = owed, late = late }, onDuty = Stakes.onDuty == true, wallet = big, persists = ns.Arena.Persists() }
end

---------------------------------------------------------------------------
-- The buttons (the design): "arbiter.duty" (on, mode); "stakes.fill" (id, i, mode): line i of a
-- match's, filled (a trade with the party open, else the mail).
---------------------------------------------------------------------------

ns.Arena.Action("arbiter.duty", function(on, mode)
	if not on then return true end
	local R0 = R()
	if not (R0 and R0.IsArbiter(ns.me, Mode(mode))) then return false, "unlisted" end
	if Mode(mode) == "L" and not ns.Arena.Persists() then return false, "persist" end
	return true
end, function(on, mode) return Stakes.OnDuty(on, mode) end)
ns.Arena.Action("stakes.fill", function(id, i, mode)
	local lines = Stakes.Lines(id, mode)
	local l = lines and lines[i]
	if not l or not l.fill then return false, "line" end
	return true
end, function(id, i, mode) return Stakes.Lines(id, mode)[i].fill() end)
