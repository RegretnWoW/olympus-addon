-- 1.2, the markets: the markets (Markets.lua, MarketBank.lua) on the test world, with the money part's wallet and
-- debts and the fights part's events as stand-ins shaped like their documented interfaces
-- (tests/arena/lib/markets-world.lua). Every copper figure is worked out by hand from markets
-- The design's formula in the comment beside it, never by calling the code under test. Every name is
-- invented (World.NAMES).
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/markets-world.lua"))(H)
local N = World.NAMES
local G, S = 10000, 100

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function B36(n)
	if n <= 0 then return "0" end
	local out = ""
	while n > 0 do
		local d = n % 36
		out = DIGITS:sub(d + 1, d + 1) .. out
		n = (n - d) / 36
	end
	return out
end

-- A slip as a (maybe modified) client sends it, straight to the bank: the bank's answer (the last
-- BK whispered back), or nil when it said nothing.
local function Slip(w, from, bank, eid, idx, o, silver, nonce, mode)
	local before = #w:Sent{ type = "BK", to = from.name }
	w:As(from, function()
		from.ns.Arena.Send("BS", mode or "L", ("%s~%s~%s~%s~%s"):format(eid, B36(idx), tostring(o), B36(silver), nonce), { to = bank.name })
	end)
	w:Run(0)
	local list = w:Sent{ type = "BK", to = from.name }
	if #list == before then return nil end
	return list[#list].msg:match("~([^~]+)$")
end
local nonces = 0
local function Nonce()
	nonces = nonces + 1
	return ("n%05d"):format(nonces)
end
local function Bal(w, t, c, cur) return w:Balance(t.bank, c, cur) end
-- A long wait, in steps (the world fires at most so many timers in one Run).
local function Wait(w, sec)
	while sec > 1800 do
		w:Run(1800)
		sec = sec - 1800
	end
	w:Run(sec)
end
-- A public fight opened by the signed arbiter (or `by`), its markets open until now + 300 s.
local function PublicFight(w, t, markets, o)
	o = o or {}
	local eid = w:Fight{ opener = o.by or t.arbiter, A = t.A, B = t.B, bo = o.bo, mode = o.mode, public = o.public }
	local ok, why = (o.by or t.arbiter).M.Open(eid, { markets = markets or { { type = "MW" } }, lockAt = o.lockAt or (w.clock + 300), cur = o.cur })
	assert(ok, "open: " .. tostring(why))
	w:Run(0)
	return eid
end

print("Markets: a public fight from the sheet to the payout")

test("1.2 the markets: a public fight's winner market: opened by its arbiter, bet by slips, locked by the bank's clock, settled after the grace to the copper", function()
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	eq(t.arbiter.M.Open(eid, { markets = { { type = "MW" } } }), true)
	w:Run(0)
	eq(t.b1.M.Has(eid), true, "every client heard the sheet")
	eq(t.bank.M.Has(eid), true)
	eq(w.registered, 1, "the bank registered the market (the ledger's n)")
	local ta = assert(t.b1.M.Bet(eid, 1, 1, 1000))
	local tb = assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(0)
	eq(ta.state, "accepted", "the ledger's b entry is the acknowledgement")
	eq(tb.state, "accepted")
	eq(#w:Sent{ type = "BK" }, 0, "no whisper per accepted bet")
	eq(Bal(w, t, t.b1), 1000000 - 100000)
	w:Run(15)
	local v = t.b3.M.View(eid)
	eq(v.markets[1].outcomes[1].pool, 100000); eq(v.markets[1].outcomes[2].count, 1)
	w:Run(200)
	eq(t.b1.M.View(eid).markets[1].state, "L")
	eq(ta.state, "locked")
	eq(t.arbiter.M.Declare(eid, { winner = "A" }), true)
	w:Run(299)
	eq(Bal(w, t, t.b1), 900000, "the grace: nothing paid yet")
	w:Run(2)
	-- 10 g on A and 10 g on B, A wins: L = 100,000; cut = 6,000 (arbiter 2,000, guild 4,000);
	-- D = 94,000; Lida is paid 100,000 + 94,000 = 194,000 (19 g 40 s).
	eq(Bal(w, t, t.b1), 900000 + 194000)
	eq(Bal(w, t, t.b2), 900000)
	eq(w:Ledger(t.bank).guild, 4000); eq(w:Ledger(t.bank).arbiter[N.arbiter:lower()], 2000)
	w:Run(15)
	eq(ta.state, "won"); eq(ta.payout, 194000); eq(tb.state, "lost"); eq(tb.payout, 0)
	eq(t.b3.M.View(eid).markets[1].state, "S")
	w:NoErrors()
end)

test("1.2 the markets: the King as arbiter holds no gold: the whole 6% to the guild (his sheet says so, a sheet of his that pays an arbiter is refused)", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t, nil, { by = t.king })
	eq(t.b1.M.Sheet(eid).fee.to, "g")
	assert(t.b1.M.Bet(eid, 1, 1, 1000))
	assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(301)
	assert(t.king.M.Declare(eid, { winner = "A" }))
	w:Run(301)
	-- The same market, the King judging: Lida 194,000; the guild 6,000; the arbiter 0.
	eq(Bal(w, t, t.b1), 900000 + 194000)
	eq(w:Ledger(t.bank).guild, 6000); eq(w:Ledger(t.bank).arbiter[N.king:lower()], 0)
	-- A forged sheet of his paying an arbiter is refused by every client.
	local eid2 = w:Fight{ opener = t.king, A = t.A, B = t.B }
	w:As(t.king, function()
		t.king.ns.Arena.Send("BM", "L", ("%s~1~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O"):format(eid2, N.bank, B36(w.clock + 600)))
	end)
	w:Run(0)
	eq(t.b1.M.Has(eid2), false)
	w:NoErrors()
end)

test("1.2 the markets: an uneven pool pays each ticket its exact part, the rounding copper to the guild; credits plus fees equal the stakes", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 300))
	assert(t.b2.M.Bet(eid, 1, 1, 400))
	assert(t.b3.M.Bet(eid, 1, 2, 1000))
	w:Run(301)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(301)
	-- T = 170,000, W = 70,000, L = 100,000: cut 6,000 (arbiter 2,000), D = 94,000.
	-- Lida: 30,000 + floor(94,000 x 30,000 / 70,000) = 30,000 + 40,285 = 70,285.
	-- Parric: 40,000 + floor(94,000 x 40,000 / 70,000) = 40,000 + 53,714 = 93,714.
	-- Paid 163,999: one copper of rounding, the guild's 4,000 + 1 = 4,001.
	eq(Bal(w, t, t.b1), 1000000 - 30000 + 70285)
	eq(Bal(w, t, t.b2), 1000000 - 40000 + 93714)
	eq(Bal(w, t, t.b3), 1000000 - 100000)
	local l = w:Ledger(t.bank)
	eq(l.guild, 4001); eq(l.arbiter[N.arbiter:lower()], 2000)
	eq(70285 + 93714 + 4001 + 2000, 170000, "(in equals out)")
	w:Run(15)
	eq(t.b1.M.Tickets{ eid = eid }[1].payout, 70285, "each bettor's client works out his own payout from the public pools")
	eq(t.b2.M.Tickets{ eid = eid }[1].payout, 93714)
	w:NoErrors()
end)

test("1.2 the markets: odds, the slip's quote and the view: truncated odds (1.62 and 2.41), the payout if it wins, the fee's two parts, the cap, the balance after", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	-- 60 g on A (three bettors at the 20 g cap), 40 g on B (two).
	for _, c in ipairs({ t.b1, t.b2, t.hc }) do assert(c.M.Bet(eid, 1, 1, 2000)) end
	w:Run(3)
	for _, c in ipairs({ t.b3, t.steward }) do assert(c.M.Bet(eid, 1, 2, 2000)) end
	w:Run(15)
	local v = t.hc2.M.View(eid)
	-- B: 100 + floor(564,000 x 100 / 400,000) = 241; A: 100 + floor(376,000 x 100 / 600,000) = 162.
	eq(v.markets[1].outcomes[1].odds, 162); eq(v.markets[1].outcomes[2].odds, 241)
	eq(v.markets[1].outcomes[1].pool, 600000); eq(v.markets[1].outcomes[1].count, 3)
	eq(v.markets[1].label, t.hc2.ns.L.MARKETS_KIND_MW); eq(v.markets[1].outcomes[1].label, "Torvin Hale")
	eq(v.bank, N.bank); eq(v.cur, "g"); eq(v.fee.g, 400); eq(v.fee.a, 200); eq(v.fee.to, "a")
	local q = t.hc2.M.Quote(eid, 1, 2, 1000)
	eq(q.ok, true); eq(q.odds, 241)
	-- 10 g more on B: its pool 500,000; D' = 600,000 - 36,000 = 564,000;
	-- payout 100,000 + floor(564,000 x 100,000 / 500,000) = 212,800. Without a fee 220,000: the fee
	-- is 7,200; with the guild's part alone (24,000 cut) 215,200: the arbiter's part 2,400, the
	-- guild's 4,800.
	eq(q.payout, 212800); eq(q.fee.g, 4800); eq(q.fee.a, 2400)
	eq(q.cap, 20 * G); eq(q.after, 1000000 - 100000)
	-- Over the cap: said before anything goes.
	local q2 = t.b1.M.Quote(eid, 1, 1, 100)
	eq(q2.ok, false); eq(q2.why, "cap"); eq(q2.cap, 0)
	-- An outcome nobody backed shows no odds ("the first bet sets the odds").
	local eid2 = PublicFight(w, t)
	eq(t.hc2.M.View(eid2).markets[1].outcomes[1].odds, nil)
	local listed = {}
	for _, p in ipairs(t.b1.M.Public()) do listed[p.eid] = p.open end
	eq(listed[eid], true); eq(listed[eid2], true)
	w:NoErrors()
end)

print("Markets: the slip's checks at the bank, one code each")

test("1.2 the markets: every refusal code at the bank (U K E r C O M R W N D A X P F), each leaving the wallet untouched; an accepted slip holds exactly its stake", function()
	local w, t = MW.Standard({ extra = { { "nobody", "Brisa Tamm" }, { "poor", "Corin Vale" } } })
	w:Key(t.nobody); w:Key(t.poor)
	w:Deposit(t.bank, t.poor, 15000)
	local eid = PublicFight(w, t)
	local bank = t.bank
	local function Check(c, idx, o, silver, want, what)
		local before = Bal(w, t, c)
		local code = Slip(w, c, bank, eid, idx, o, silver, Nonce())
		eq(code, want, what)
		if want ~= nil then eq(Bal(w, t, c), before, what .. ": the wallet untouched") end
		w:Run(3)
	end
	Check(t.b1, 9, 1, 100, "U", "no such market")
	Check(t.b1, 1, 3, 100, "O", "no such outcome")
	Check(t.b1, 1, 1, 5, "M", "under minBet (10 s)")
	Check(t.nobody, 1, 1, 100, "W", "no wallet at this bank")
	Check(t.b1, 1, 1, 2001, "X", "over the King's 20 g")
	Check(t.poor, 1, 1, 200, "F", "2 g with 1 g 50 s in the wallet")
	w.debtors[t.b3.name:lower()] = true
	Check(t.b3, 1, 1, 100, "D", "an open debt")
	w.debtors[t.b3.name:lower()] = nil
	Check(t.arbiter, 1, 1, 100, "A", "the event's arbiter")
	Check(t.B, 1, 1, 100, "A", "a fighter on his opponent")
	-- Net-off, as the bank's moderation sees it.
	local hidden = t.bank.ns.Moderation.Hidden
	t.bank.ns.Moderation.Hidden = function(name) if name == t.b2.name then return { level = 1 }, name end return hidden(name) end
	Check(t.b2, 1, 1, 100, "N", "net-off")
	t.bank.ns.Moderation.Hidden = hidden
	-- No verified key: E, first of the account's checks.
	local key = w.keys[t.b2.name:lower()]
	w.keys[t.b2.name:lower()] = nil
	Check(t.b2, 1, 1, 100, "E", "no verified key")
	w.keys[t.b2.name:lower()] = key
	-- Not eligible at deposit: frozen, no bound GUID, under minLevel, no Olympus guild.
	for _, f in ipairs({ { frozen = true }, { bound = false }, { level = 5 }, { guild = "Moonwhisper Kin" } }) do
		local a = w:Ledger(t.bank).accounts[t.b2.name:lower()]
		local saved = { frozen = a.frozen, bound = a.bound, level = a.level, guild = a.guild }
		for k, v in pairs(f) do a[k] = v end
		Check(t.b2, 1, 1, 100, "E", "not eligible")
		for k, v in pairs(saved) do a[k] = v end
	end
	-- The room: the King's maxPool (1 g for this check).
	assert(t.king.Roles.SetSettings({ maxPool = G }))
	w:Run(0)
	Check(t.hc, 1, 1, 200, "P", "the pool would pass maxPool")
	assert(t.king.Roles.SetSettings({ maxPool = 1000 * G }))
	w:Run(0)
	-- Accepted: exactly its stake held; the same nonce again says K (once every 20 s: the bettor's
	-- client sends it again no sooner) and holds nothing more.
	local n = Nonce()
	eq(Slip(w, t.hc, bank, eid, 1, 1, 150, n), nil, "an accepted bet is its ledger entry: no whisper")
	eq(Bal(w, t, t.hc), 1000000 - 15000)
	eq(Slip(w, t.hc, bank, eid, 1, 1, 150, n), "K", "the same slip again")
	eq(Slip(w, t.hc, bank, eid, 1, 1, 150, n), nil, "again at once: not answered twice in 20 s")
	w:Run(20)
	eq(Slip(w, t.hc, bank, eid, 1, 1, 150, n), "K", "20 s later: K again")
	eq(Bal(w, t, t.hc), 1000000 - 15000, "held once")
	local bs = 0
	for _, e in ipairs(w:Ledger(t.bank).entries) do if e.k == "b" and e.nonce == n then bs = bs + 1 end end
	eq(bs, 1, "one b entry")
	w:Run(3)
	eq(Slip(w, t.hc, bank, eid, 1, 1, 200, n), "U", "that nonce with another stake")
	-- R: two slips within 2 s from one sender.
	eq(Slip(w, t.hc2, bank, eid, 1, 2, 100, Nonce()), nil)
	eq(Slip(w, t.hc2, bank, eid, 1, 2, 100, Nonce()), "R", "1 slip per 2 s")
	-- r: the bank's publishing rate (a minute's worth taken).
	t.bank.ns.MarketBank.BANK_RATE = 2
	w:Run(3)
	eq(Slip(w, t.steward, bank, eid, 1, 2, 100, Nonce()), "r" .. B36(t.bank.ns.MarketBank.BUSY_WAIT), "the bank busy")
	t.bank.ns.MarketBank.BANK_RATE = 150
	-- C: at lockAt, by the bank's clock: nothing said, nothing held.
	w:Run(400)
	Check(t.auditor, 1, 1, 100, nil, "a late slip hears nothing")
	eq(Bal(w, t, t.auditor), 1000000)
	w:NoErrors()
end)

-- 1.1.6 (WatchChat.Barred): the review's findings: the bank took a timed-out player's slip (only
-- net-off and a frozen wallet were refused there), and a sanctioned player kept the arena's powers.
-- WatchChat.lua is not loaded in this world: each client's stand-in answers what it knows.
test("watch: chat moderation: a sanctioned player bets on nothing (the bank refuses N, his own client says so first) and holds no stake; a sanctioned bank is closing; a sanctioned councillor has no arena power", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	local bank = t.bank
	local function Knows(c, names)
		c.ns.WatchChat = {
			Barred = function(what, name)
				name = name or c.name
				if names[name] and what ~= "wallet" then return { kind = "timeout" } end
			end,
			PowersBarred = function(name) if names[c.ns.FullName(name)] then return { kind = "timeout" } end end,
		}
	end
	Knows(bank, { [t.b2.name] = true })
	local before = Bal(w, t, t.b2)
	eq(Slip(w, t.b2, bank, eid, 1, 1, 100, Nonce()), "N", "the bank refuses a sanctioned bettor")
	eq(Bal(w, t, t.b2), before, "his wallet untouched")
	eq(Slip(w, t.b1, bank, eid, 1, 1, 100, Nonce()), nil, "another bettor's slip is taken")
	-- His own client says so before anything goes (a queued bet is checked here again).
	Knows(t.b2, { [t.b2.name] = true })
	local q = t.b2.M.Quote(eid, 1, 2, 100)
	eq(q.ok, false); eq(q.why, "sanction")
	assert(t.b2.ns.L.MARKETS_WHY_SANCTION ~= "MARKETS_WHY_SANCTION", "its words")
	-- A bank its clients know sanctioned is closing there: it pays out and settles, takes nothing new.
	Knows(t.b3, { [bank.name] = true })
	eq(t.b3.Roles.BankState(bank.name), "c", "closing")
	eq(t.b1.Roles.BankState(bank.name), "o", "open where nobody knows it")
	-- A sanctioned councillor sends no leader's word, takes no ledger, promotes nothing.
	Knows(t.b3, { [t.hc.name] = true })
	eq(t.b1.Roles.Leader(t.hc.name), true, "a leader where nobody knows it")
	eq(t.b3.Roles.Leader(t.hc.name), false); eq(t.b3.Roles.Auditor(t.hc.name), false)
	eq(t.b3.Roles.MayPromote(t.hc.name), false)
	eq(t.b3.Roles.Leader(t.king.name), true, "never the King")
	-- No stake held for a sanctioned party, on the arbiter's client.
	Knows(t.arbiter, { [t.A.name] = true })
	local ok, why = w:As(t.arbiter, function()
		return t.arbiter.ns.Stakes.Open({ id = "wm1", mode = "T", A = { name = t.A.name }, B = { name = t.B.name },
			stake = { A = 1000, B = 1000 }, arbiter = t.arbiter.name })
	end)
	eq(ok, false); eq(why, "sanction")
	w:NoErrors()
end)

test("1.2 the markets: the acknowledgement is the ledger's entry, matched on the full tuple: another bettor's entry for the same market, outcome and stake changes nothing", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	w.hold = true -- the bank's entries wait in its backlog
	local ta = assert(t.b1.M.Bet(eid, 1, 1, 500))
	w:Run(3)
	local tb = assert(t.b2.M.Bet(eid, 1, 1, 500))
	w:Run(1)
	eq(ta.state, "sent"); eq(tb.state, "sent")
	eq(#w:Ledger(t.bank).pending, 2, "both taken by the bank")
	eq(t.b1.listening.markets, true, "the wallet reads the ledger for her (Wallet.Listen)")
	eq(t.b3.listening, nil, "and for nobody who waits for nothing")
	w:Publish(1)
	eq(ta.state, "accepted", "Lida's entry"); eq(tb.state, "sent", "Parric's ticket is not hers")
	eq(t.b1.listening.markets, nil, "acknowledged: no more")
	w:Publish()
	eq(tb.state, "accepted")
	-- An entry that is not ours in any field: a stake, a nonce or an outcome apart.
	local tc = assert(t.b3.M.Bet(eid, 1, 2, 500))
	w:Run(0)
	local l = w:Ledger(t.bank)
	local e = l.pending[1].entry
	for _, field in ipairs({ { "copper", 50100 }, { "nonce", "zzzzzz" }, { "o", "1" }, { "idx", 2 } }) do
		local copy = {}
		for k, v in pairs(e) do copy[k] = v end
		copy[field[1]] = field[2]
		w:Deliver(t.bank.name, 99, copy)
		eq(tc.state, "sent", field[1])
	end
	-- From another sender: never ours.
	w:Deliver(t.b2.name, 98, e)
	eq(tc.state, "sent", "another sender's entry")
	w:Publish()
	eq(tc.state, "accepted")
	w:NoErrors()
end)

test("1.2 the markets: no answer: the same slip again (same nonce) after the bank's lag, three sends at most, then unconfirmed; never after the lock", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	-- The bank takes nothing (a modified or overloaded bank that stays silent).
	local handle = t.bank.ns.MarketBank.HandleSlip
	t.bank.ns.MarketBank.HandleSlip = function() end
	local tk = assert(t.b1.M.Bet(eid, 1, 1, 500))
	w:Run(0)
	eq(#w:Sent{ type = "BS", from = t.b1 }, 1)
	w:Run(19)
	eq(#w:Sent{ type = "BS", from = t.b1 }, 1, "not before ACK_WAIT")
	w:Run(2)
	eq(#w:Sent{ type = "BS", from = t.b1 }, 2)
	local sent = w:Sent{ type = "BS", from = t.b1 }
	eq(sent[1].msg, sent[2].msg, "the same slip, the same nonce")
	w:Run(21)
	eq(#w:Sent{ type = "BS", from = t.b1 }, 3)
	w:Run(21)
	eq(tk.state, "unconfirmed"); eq(#w:Sent{ type = "BS", from = t.b1 }, 3, "three sends at most")
	-- The bank back: a resend of a slip it had taken is answered K.
	t.bank.ns.MarketBank.HandleSlip = handle
	w.hold = true
	local tk2 = assert(t.b2.M.Bet(eid, 1, 1, 500))
	w:Run(0)
	eq(tk2.state, "sent")
	w:Run(21)
	eq(tk2.state, "accepted", "the bank's K for the nonce it holds")
	eq(Bal(w, t, t.b2), 1000000 - 50000, "held once")
	-- After the lock nothing goes again.
	w.hold = false
	t.bank.ns.MarketBank.HandleSlip = function() end
	local tk3 = assert(t.b3.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	local n = #w:Sent{ type = "BS", from = t.b3 }
	w:Run(200)
	eq(#w:Sent{ type = "BS", from = t.b3 }, n)
	-- (Only Parric's bet was taken: one-sided at the lock, the market is void, and the ticket
	-- never taken says so too.)
	eq(tk3.state, "void"); eq(tk3.code, "1")
	w:NoErrors()
end)

test("1.2 the markets: a slip from an account without a verified key gets E: the bettor's client sends its key claim, and the slip goes once more", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	w.keys[t.b1.name:lower()] = nil
	w.autoKey = true -- the bank verifies the claim (the money part's ZT)
	local tk = assert(t.b1.M.Bet(eid, 1, 1, 500))
	w:Run(0)
	eq(tk.state, "key"); eq(#w.claims, 1); eq(w.claims[1].to, N.bank)
	w:Run(10)
	eq(tk.state, "accepted")
	eq(Bal(w, t, t.b1), 1000000 - 50000)
	-- Without a key the second time: refused.
	w.autoKey = false
	w.keys[t.b2.name:lower()] = nil
	local tk2 = assert(t.b2.M.Bet(eid, 1, 1, 500))
	w:Run(11)
	eq(tk2.state, "refused"); eq(tk2.code, "E")
	w:NoErrors()
end)

test("1.2 the markets: a ticket queued while the bank is offline goes when its next book is heard, before the lock; a realm's bettor never slips another realm's bank", function()
	local w, t = MW.Standard({ extra = { { "far", "Maro Quell-Emberfall2" } } })
	local eid = PublicFight(w, t, nil, { lockAt = w.clock + 3600 * 3 })
	w:Logout(t.bank)
	w:Run(200)
	eq(t.b1.M.View(eid).bankOnline, false)
	local tk = assert(t.b1.M.Bet(eid, 1, 1, 500, true))
	eq(tk.state, "queued"); eq(#w:Sent{ type = "BS", from = t.b1 }, 0)
	w:Login(t.bank)
	w:Install(t.bank)
	w:Run(700)
	eq(tk.state, "accepted", "sent when the bank's book came")
	-- Another realm: the channel never carried the sheet there, and nothing goes.
	eq(t.far.M.Has(eid), false)
	local none, why = t.far.M.Bet(eid, 1, 1, 500)
	eq(none, nil); eq(why, "unknown")
	eq(#w:Sent{ type = "BS", from = t.far }, 0)
	w:NoErrors()
end)

print("Markets: the lock, voids, the grace, holds and overrules")

local function Last(w, f)
	local list = w:Sent(f)
	return list[#list]
end

test("1.2 the markets: the lock is the bank's clock: its z at lockAt, the locked book urgently; a slip at lockAt is refused; 'Fight!' waits for that book or 30 s", function()
	local w, t = MW.Standard()
	local lockAt = w.clock + 300
	local eid = PublicFight(w, t, nil, { lockAt = lockAt })
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(0)
	eq(t.arbiter.M.FightReady(eid), false)
	w:Run(lockAt - w.clock - 1)
	eq(w.closed, nil, "open until lockAt")
	-- A slip that reaches the bank at lockAt exactly: refused, nothing held, nothing said.
	w.clock = lockAt
	eq(Slip(w, t.b3, t.bank, eid, 1, 1, 100, Nonce()), nil)
	eq(Bal(w, t, t.b3), 1000000)
	w:Run(1)
	eq(#w.closed, 1); eq(w.closed[1].t <= lockAt + 1, true, "the z at lockAt, by the bank's ticker")
	local bo = Last(w, { from = t.bank, type = "BO" })
	eq(bo.urgent, true); eq(bo.msg:find(":L:", 1, true) ~= nil, true)
	eq(t.arbiter.M.FightReady(eid), true, "the locked book heard")
	-- The bank offline at the lock: 'Fight!' 30 s after lockAt anyway (it locks by its own clock).
	local eid2 = PublicFight(w, t, nil, { lockAt = w.clock + 300 })
	w:Logout(t.bank)
	w:Run(300)
	eq(t.arbiter.M.FightReady(eid2), false)
	w:Run(30)
	eq(t.arbiter.M.FightReady(eid2), true)
	w:NoErrors()
end)

-- A sheet as its opener (or someone else) sends it, raw.
local function RawSheet(w, from, body, mode, to)
	w:As(from, function() from.ns.Arena.Send("BM", mode or "L", body, to and { to = to } or nil) end)
	w:Run(0)
end
local function SheetText(c, eid) return c.ns.Markets.SheetBody(c.ns.Markets.Sheet(eid)) end

test("1.2 the markets: voids: a result while bets are open (E), no result after the lock (G), one side only (1), cancelled (X); each refunds everything, no fee; a void is final", function()
	local w, t = MW.Standard()
	-- E: the arbiter's result reaches the bank while the market is still open.
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(0)
	local text = SheetText(t.arbiter, eid):gsub("^([^~]+)~1~", "%1~2~"):gsub(":O$", ":R:1:" .. B36(w.clock))
	RawSheet(w, t.arbiter, text)
	eq(Bal(w, t, t.b1), 1000000); eq(Bal(w, t, t.b2), 1000000)
	w:Run(15)
	eq(t.b3.M.View(eid).markets[1].state, "V"); eq(t.b3.M.View(eid).markets[1].result, "E")
	eq(w:Ledger(t.bank).guild, 0)
	-- G: nobody declares within 30 minutes of the lock.
	local eid2 = PublicFight(w, t)
	assert(t.b1.M.Bet(eid2, 1, 1, 500))
	w:Run(3)
	assert(t.b2.M.Bet(eid2, 1, 2, 500))
	w:Run(297 + 1799)
	eq(Bal(w, t, t.b1), 950000)
	w:Run(2)
	eq(Bal(w, t, t.b1), 1000000); eq(Bal(w, t, t.b2), 1000000)
	w:Run(15)
	eq(t.b1.M.View(eid2).markets[1].result, "G")
	-- 1: bets on one side only at the lock.
	local eid3 = PublicFight(w, t)
	local tk = assert(t.b1.M.Bet(eid3, 1, 1, 500))
	w:Run(301)
	eq(Bal(w, t, t.b1), 1000000)
	w:Run(15)
	eq(tk.state, "void"); eq(tk.code, "1"); eq(tk.payout, 50000)
	-- X: the opener cancels before the lock; a later declaration of that market is refused.
	local eid4 = PublicFight(w, t)
	assert(t.b1.M.Bet(eid4, 1, 1, 500))
	w:Run(3)
	assert(t.b2.M.Bet(eid4, 1, 2, 500))
	w:Run(0)
	eq(t.arbiter.M.Void(eid4, "*", "X"), true)
	w:Run(0)
	eq(Bal(w, t, t.b1), 1000000)
	local rev = t.b3.M.Sheet(eid4).rev
	local undo = SheetText(t.arbiter, eid4):gsub("^([^~]+)~" .. B36(rev) .. "~", "%1~" .. B36(rev + 1) .. "~"):gsub(":V:X:[0-9a-z]+$", ":R:1:" .. B36(w.clock))
	RawSheet(w, t.arbiter, undo)
	eq(t.b3.M.Sheet(eid4).rev, rev, "no rev undoes a void")
	w:NoErrors()
end)

test("1.2 the markets: the grace: paid at the declaration + 300 s by the bank's clock; a correction starts it again", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(0)
	local declared = w.clock
	w:Run(200)
	-- The arbiter corrects it: B won. The grace runs again from the correction.
	local ok, n = t.arbiter.M.Declare(eid, { winner = "B" })
	eq(ok, true); eq(n, 1)
	w:Run(0)
	local corrected = w.clock
	w:Run(declared + 300 - w.clock + 5)
	eq(Bal(w, t, t.b2), 950000, "not at the first declaration's end")
	w:Run(corrected + 300 - w.clock - 1)
	eq(Bal(w, t, t.b2), 950000)
	w:Run(1)
	-- 5 g against 5 g: Parric 50,000 + 47,000 = 97,000.
	eq(Bal(w, t, t.b2), 950000 + 97000)
	eq(Bal(w, t, t.b1), 950000)
	w:NoErrors()
end)

test("1.2 the markets: holds: the arbiter against the game's duel line holds the event; after 24 h it pays by the duel line when the arbiter's client or two witnesses saw it, else voids", function()
	local w, t = MW.Standard()
	-- 24 hours on the bank's clock are 600 s here (the world fires every client's ticker each second).
	eq(t.bank.ns.Markets.HOLD_MAX, 86400)
	t.bank.ns.Markets.HOLD_MAX = 600
	local eid = PublicFight(w, t, { { type = "MW" }, { type = "KO" } })
	local ev = w.events[eid]
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(3)
	assert(t.b3.M.Bet(eid, 2, 1, 300))
	assert(t.hc.M.Bet(eid, 2, 2, 300))
	w:Run(300)
	-- He declares B although the game said A.
	assert(t.arbiter.M.Declare(eid, { winner = "B", method = "K", against = true }))
	w:Run(0)
	local heldAt = w.clock
	w:Run(301)
	eq(Bal(w, t, t.b2), 950000, "held: not paid after the grace")
	w:Run(15)
	eq(t.b1.M.View(eid).markets[1].state, "H"); eq(t.b1.M.View(eid).markets[2].state, "H", "the whole event")
	-- The arbiter's client saw the duel line: A by knockout.
	ev.duel = { winner = "A", method = "K", arbiter = true }
	w:Run(heldAt + 600 - w.clock - 2)
	eq(Bal(w, t, t.b1), 950000, "held until HOLD_MAX")
	w:Run(3)
	eq(Bal(w, t, t.b1), 950000 + 97000, "paid by the game's line, not the suspect word")
	eq(Bal(w, t, t.b3), 970000 + 58200, "3 g against 3 g on the knockout: 30,000 + 28,200")
	-- Another: nobody saw the line (one witness is not enough): void.
	local eid2 = PublicFight(w, t)
	w.events[eid2].duel = { winner = "A", method = "K", witnesses = 1 }
	assert(t.b1.M.Bet(eid2, 1, 1, 500))
	assert(t.b2.M.Bet(eid2, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid2, { winner = "B", against = true }))
	local before1, before2 = Bal(w, t, t.b1), Bal(w, t, t.b2)
	w:Run(605)
	eq(Bal(w, t, t.b1), before1 + 50000); eq(Bal(w, t, t.b2), before2 + 50000)
	w:Run(15)
	eq(t.b1.M.View(eid2).markets[1].result, "G")
	w:NoErrors()
end)

test("1.2 the markets: BV: the King's H stops the payout, a Steward's P does not undo it, the King's P pays; a hold from a word alone pays the declared result after 24 h", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(10)
	eq(t.king.M.Overrule(eid, 1, "H"), true)
	w:Run(0)
	eq(Last(w, { from = t.king, type = "BV" }).dist, "CHANNEL")
	w:Run(15)
	eq(t.b3.M.View(eid).markets[1].state, "H")
	eq(t.steward.M.Overrule(eid, 1, "P"), true)
	w:Run(400)
	eq(Bal(w, t, t.b1), 950000, "a Steward's word never undoes the King's")
	eq(t.king.M.Overrule(eid, 1, "P"), true)
	w:Run(1)
	eq(Bal(w, t, t.b1), 950000 + 97000, "released: paid by the declared result")
	-- The King's word repeats every 120 s until settled, then for 30 minutes.
	local n = #w:Sent{ from = t.king, type = "BV" }
	w:Run(125)
	eq(#w:Sent{ from = t.king, type = "BV" } > n, true)
	Wait(w, 3600)
	n = #w:Sent{ from = t.king, type = "BV" }
	w:Run(600)
	eq(#w:Sent{ from = t.king, type = "BV" }, n, "stopped")
	-- A word's hold nobody rules on: after 24 h (600 s here) the declared result pays.
	t.bank.ns.Markets.HOLD_MAX = 600
	local eid2 = PublicFight(w, t)
	assert(t.b1.M.Bet(eid2, 1, 1, 500))
	assert(t.b2.M.Bet(eid2, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid2, { winner = "B" }))
	w:Run(5)
	assert(t.steward.M.Overrule(eid2, 1, "H"))
	w:Run(0)
	local b2 = Bal(w, t, t.b2)
	w:Run(600 - 3)
	eq(Bal(w, t, t.b2), b2)
	w:Run(5)
	eq(Bal(w, t, t.b2), b2 + 97000)
	w:NoErrors()
end)

test("1.2 the markets: BV weights: one High Councillor's V holds until a second, independent one confirms it (an alt's never does); a Steward's V is final alone", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(0)
	assert(t.hc.M.Overrule(eid, 1, "V"))
	w:Run(15)
	eq(t.b3.M.View(eid).markets[1].state, "H", "one weight-1 V is a hold")
	-- The same player's other character (the same owner) confirms nothing.
	w.owners[t.hc.name:lower()], w.owners[t.hc2.name:lower()] = "one", "one"
	assert(t.hc2.M.Overrule(eid, 1, "V"))
	w:Run(400)
	eq(Bal(w, t, t.b1), 950000); eq(t.b3.M.View(eid).markets[1].state, "H")
	-- Another person's V: void (L), everything back.
	w.owners[t.hc2.name:lower()] = "two"
	w:Run(3)
	assert(t.hc2.M.Overrule(eid, 1, "V"))
	w:Run(1)
	eq(Bal(w, t, t.b1), 1000000); eq(Bal(w, t, t.b2), 1000000)
	w:Run(15)
	eq(t.b3.M.View(eid).markets[1].result, "L")
	-- A Steward's V alone is final.
	local eid2 = PublicFight(w, t)
	assert(t.b1.M.Bet(eid2, 1, 1, 500))
	assert(t.b2.M.Bet(eid2, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid2, { winner = "A" }))
	assert(t.steward.M.Overrule(eid2, "*", "V"))
	w:Run(0)
	eq(Bal(w, t, t.b1), 1000000)
	w:NoErrors()
end)

test("1.2 the markets: BV is refused from anyone with an interest: the event's arbiter, its fighters, the bank, a ticket holder and his alt", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.hc.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(0)
	eq(select(2, t.arbiter.M.Overrule(eid, 1, "V")), "conflict", "his own client refuses")
	eq(select(2, t.hc.M.Overrule(eid, 1, "V")), "conflict", "a ticket of his own")
	eq(select(2, t.b1.M.Overrule(eid, 1, "V")), "leader")
	-- Sent anyway (modified clients): the bank ignores them all.
	local function Word(c)
		w:As(c, function() c.ns.Arena.Send("BV", "L", ("%s~1~V~%s"):format(eid, B36(w.clock))) end)
	end
	Word(t.arbiter); Word(t.hc); Word(t.bank)
	-- The other councillor holds no ticket himself, but his other character does.
	w.owners[t.hc.name:lower()], w.owners[t.hc2.name:lower()] = "one", "one"
	Word(t.hc2)
	w:Run(301)
	eq(Bal(w, t, t.b1), 950000 + 97000, "paid: no word counted")
	w:NoErrors()
end)

print("Markets: the anti-fix rules, KO and B3, the props, flags, privacy, rates")

test("1.2 the markets: anti-fix: a fighter bets only the winner on himself; his alt and his key are him; the arbiter and the bank bet nothing", function()
	local w, t = MW.Standard({ extra = { { "alt", "Dorn Hale" }, { "twin", "Eska Hale" } } })
	w:Deposit(t.bank, t.alt, 1000000); w:Deposit(t.bank, t.twin, 1000000)
	w:Key(t.alt); w:Key(t.twin, w.keys[t.A.name:lower()].fp) -- the same account key as Torvin
	w.owners[t.alt.name:lower()], w.owners[t.A.name:lower()] = "torvin", "torvin"
	local eid = PublicFight(w, t, { { type = "MW" }, { type = "KO" } })
	eq(Slip(w, t.A, t.bank, eid, 1, 1, 100, Nonce()), nil, "the winner on himself")
	w:Run(3)
	eq(Slip(w, t.A, t.bank, eid, 1, 2, 100, Nonce()), "A", "on his opponent")
	w:Run(3)
	eq(Slip(w, t.A, t.bank, eid, 2, 1, 100, Nonce()), "A", "a prop of his own fight")
	eq(Slip(w, t.alt, t.bank, eid, 1, 2, 100, Nonce()), "A", "his alt on the opponent")
	eq(Slip(w, t.twin, t.bank, eid, 1, 2, 100, Nonce()), "A", "a character with his key")
	w:Run(3)
	eq(Slip(w, t.alt, t.bank, eid, 1, 1, 100, Nonce()), nil, "his alt on him: as he may")
	eq(Slip(w, t.arbiter, t.bank, eid, 1, 1, 100, Nonce()), "A")
	-- The bettor's own client says so first (Arena.Can("bet")).
	eq(select(2, t.A.M.CanBet(eid, 1, 2, 100)), "conflict")
	eq(select(2, t.arbiter.M.CanBet(eid, 1, 1, 100)), "conflict")
	eq(t.A.M.CanBet(eid, 1, 1, 100), true)
	w:NoErrors()
end)

test("1.2 the markets: KO and B3 run under smaller caps (5 g a bet, a tenth of the pool cap), refuse a fighter's guildmate; a flee in the first 20 s voids KO (N)", function()
	local w, t = MW.Standard({ extra = { { "mate", "Dorla Venn", { guild = MW.FIGHTER_GUILD } } } })
	w:Key(t.mate); w:Deposit(t.bank, t.mate, 1000000)
	local eid = PublicFight(w, t, { { type = "MW" }, { type = "KO" }, { type = "B3" } }, { bo = 3 })
	eq(Slip(w, t.b1, t.bank, eid, 2, 1, 501, Nonce()), "X", "over 5 g")
	w:Run(3)
	eq(Slip(w, t.b1, t.bank, eid, 2, 1, 500, Nonce()), nil)
	w:Run(3)
	eq(Slip(w, t.b1, t.bank, eid, 1, 1, 2000, Nonce()), nil, "the winner market keeps the King's 20 g")
	eq(Slip(w, t.mate, t.bank, eid, 2, 1, 100, Nonce()), "A", "a fighter's guildmate on KO")
	w:Run(3)
	eq(Slip(w, t.mate, t.bank, eid, 3, 1, 100, Nonce()), "A", "and on B3")
	w:Run(3)
	eq(Slip(w, t.mate, t.bank, eid, 1, 1, 100, Nonce()), nil, "the winner market is open to him")
	eq(select(2, t.mate.M.CanBet(eid, 2, 1, 100)), "conflict")
	-- The pool cap at 50 g: 5 g on KO and B3 (one tenth), 50 g on the winner market.
	assert(t.king.Roles.SetSettings({ maxPool = 50 * G }))
	w:Run(0)
	eq(Slip(w, t.b2, t.bank, eid, 2, 2, 200, Nonce()), "P", "5 g + 2 g passes 5 g")
	w:Run(3)
	eq(Slip(w, t.b2, t.bank, eid, 3, 2, 300, Nonce()), nil)
	eq(Slip(w, t.b3, t.bank, eid, 3, 1, 300, Nonce()), "P", "3 g + 3 g on B3 passes 5 g")
	w:Run(3)
	eq(Slip(w, t.b2, t.bank, eid, 1, 2, 100, Nonce()), nil)
	assert(t.king.Roles.SetSettings({ maxPool = 1000 * G }))
	w:Run(3)
	eq(Slip(w, t.b2, t.bank, eid, 2, 2, 400, Nonce()), nil)
	w:Run(300)
	-- He fled 15 s after the bell: the knockout market voids, the winner market pays.
	assert(t.arbiter.M.Declare(eid, { winner = "A", method = "R", dur = 15, rounds = "AA", final = true }))
	w:Run(0)
	eq(t.b3.M.Sheet(eid).markets[2].state, "V"); eq(t.b3.M.Sheet(eid).markets[2].result, "N")
	eq(t.b3.M.Sheet(eid).markets[1].state, "R")
	eq(t.b3.M.Sheet(eid).markets[3].result, "1", "A 2-0"); eq(t.b3.M.Sheet(eid).rounds, "AA", "the rounds on the sheet")
	w:NoErrors()
end)

test("1.2 the markets: duration, first blood and biggest hit are trials: refused in the live arena (LIVE_PROPS off), taken in a rehearsal and marked there", function()
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	eq(select(2, t.arbiter.M.Open(eid, { markets = { { type = "MW" }, { type = "DU", param = 90 } }, lockAt = w.clock + 300 })), "trial")
	-- A modified opener's sheet with one: every client refuses it.
	w:As(t.arbiter, function()
		t.arbiter.ns.Arena.Send("BM", "L", ("%s~1~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O;2:FB:-:2:O"):format(eid, N.bank, B36(w.clock + 300)))
	end)
	w:Run(0)
	eq(t.b1.M.Has(eid), false)
	-- In a rehearsal (T): taken, marked trial.
	local eidT = w:Fight{ opener = t.arbiter, A = t.A, B = t.B, mode = "T" }
	eq(t.arbiter.M.Open(eidT, { markets = { { type = "MW" }, { type = "DU", param = 90 }, { type = "FB" }, { type = "BH" } }, lockAt = w.clock + 300 }), true)
	w:Run(0)
	local v = t.b1.M.View(eidT)
	eq(v.rehearsal, true); eq(v.cur, "c", "chips by default in a rehearsal")
	eq(v.markets[2].trial, true); eq(v.markets[2].label, "Duration: over or under 90.5 s")
	eq(v.markets[2].outcomes[1].label, "Over 90.5 s")
	-- Settled from the arbiter's measures: 91 s is over (L + 1), no first blood seen voids FB, a tie in BH voids it (Z).
	w:Run(300)
	assert(t.arbiter.M.Declare(eidT, { winner = "A", method = "K", dur = 91, bh = "tie" }))
	w:Run(0)
	local s = t.b1.M.Sheet(eidT)
	eq(s.markets[2].result, "1"); eq(s.markets[3].result, "N"); eq(s.markets[4].result, "Z")
	-- LIVE_PROPS on (in-game check 3 passed): the live arena takes them.
	for _, c in ipairs(w.clients) do c.ns.Markets.LIVE_PROPS.DU = true end
	local eid2 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	eq(t.arbiter.M.Open(eid2, { markets = { { type = "DU", param = 60 } }, lockAt = w.clock + 300 }), true)
	w:Run(0)
	eq(t.b1.M.Has(eid2), true)
	w:NoErrors()
end)

-- The flags whispered (BF): { code = who }, from the bank.
local function Flags(w, t, eid)
	w:Run(6) -- (the low lane: one whisper a second, to each auditor)
	local out = {}
	for _, s in ipairs(w:Sent{ from = t.bank, type = "BF" }) do
		local e, _, code, who = s.msg:match("^BF~L1~([^~]+)~([^~]+)~(%a)~([^~]+)~")
		if e == eid then out[#out + 1] = { code = code, who = who, to = s.target } end
	end
	return out
end
local function Has(list, code, who)
	for _, f in ipairs(list) do if f.code == code and (not who or f.who == who) then return true end end
	return false
end

test("1.2 the markets: flags to auditors only, never the event's arbiter: an underdog spike (U) at its threshold and one silver under", function()
	local w, t = MW.Standard({ money = 1000000 })
	assert(t.king.Roles.SetSettings({ maxBet = 100 * G, maxDay = 500 * G }))
	w:Run(0)
	-- Before: A 40 g (20 + 20), B 10 g (5 + 5): T = 50 g, B 20% of it. The median stake is
	-- (5 g + 20 g) / 2 = 12 g 50 s: the spike needs max(3 x 12.5 g, 10% of 50 g, 20 g) = 37 g 50 s.
	local function Setup(opener)
		local eid = PublicFight(w, t, nil, { by = opener })
		assert(t.b1.M.Bet(eid, 1, 1, 2000)); assert(t.b2.M.Bet(eid, 1, 1, 2000))
		w:Run(3)
		assert(t.hc.M.Bet(eid, 1, 2, 500)); assert(t.hc2.M.Bet(eid, 1, 2, 500))
		w:Run(3)
		return eid
	end
	local eid = Setup(t.auditor)
	assert(t.b3.M.Bet(eid, 1, 2, 3749))
	w:Run(0)
	eq(#Flags(w, t, eid), 0, "one silver under")
	local eid2 = Setup(t.auditor)
	assert(t.b3.M.Bet(eid2, 1, 2, 3750))
	w:Run(0)
	local f = Flags(w, t, eid2)
	eq(Has(f, "U", N.bettor3), true)
	local to = {}
	for _, x in ipairs(f) do to[x.to] = true end
	eq(to[N.king], true); eq(to[N.councillor], true); eq(to[N.councillor2], true)
	eq(to[N.auditor], nil, "never the event's arbiter (she opened it)")
	eq(to[N.bettor3], nil)
	for _, s in ipairs(w:Sent{ type = "BF" }) do eq(s.dist, "WHISPER") end
	-- An auditor keeps it; a non-auditor ignores one.
	local a = t.king.ns.Arena.Store("L").audit[eid2]
	eq(a.flags[1].code, "U"); eq(a.flags[1].who, N.bettor3); eq(a.flags[1].silver, 3750)
	eq(t.b1.ns.Arena.Store("L").audit, nil)
	w:NoErrors()
end)

test("1.2 the markets: flags: both sides by one owner (T), against a fighter's guildmate at 20 g (G), a late surge (L) at 50 g and one step under", function()
	local w, t = MW.Standard({ extra = { { "mate", "Dorla Venn", { guild = MW.FIGHTER_GUILD } } } })
	w:Key(t.mate); w:Deposit(t.bank, t.mate, 1000000)
	w.owners[t.b1.name:lower()], w.owners[t.b2.name:lower()] = "one", "one"
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	w:Run(3)
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(3)
	eq(Has(Flags(w, t, eid), "T", N.bettor2), true, "one owner on both outcomes")
	assert(t.mate.M.Bet(eid, 1, 2, 1999))
	w:Run(3)
	eq(Has(Flags(w, t, eid), "G"), false, "19 g 99 s")
	local eidG = PublicFight(w, t)
	assert(t.mate.M.Bet(eidG, 1, 2, 2000))
	w:Run(0)
	eq(Has(Flags(w, t, eidG), "G", "Dorla Venn-Emberfall"), true)
	-- Late surge: at lockAt - 120 A holds 60 g, B 10 g (14%). Then B grows by 49 g, or by 50 g.
	local function Surge(last)
		local e = PublicFight(w, t, nil, { lockAt = w.clock + 400 })
		for _, c in ipairs({ t.b1, t.hc, t.hc2 }) do assert(c.M.Bet(e, 1, 1, 2000)) end
		w:Run(3)
		assert(t.b3.M.Bet(e, 1, 2, 1000))
		w:Run(400 - 3 - 100)
		assert(t.steward.M.Bet(e, 1, 2, 2000)); assert(t.auditor.M.Bet(e, 1, 2, 2000))
		w:Run(3)
		assert(t.king.M.Bet(e, 1, 2, last))
		w:Run(100)
		return e
	end
	local e1 = Surge(900)
	eq(Has(Flags(w, t, e1), "L"), false, "49 g")
	local e2 = Surge(1000)
	local f = Flags(w, t, e2)
	eq(Has(f, "L", N.steward), true); eq(Has(f, "L", N.king), true); eq(Has(f, "L", N.bettor3), false, "before the last 120 s")
	w:NoErrors()
end)

test("1.2 the markets: flags: a bettor flagged U in three settled markets of one fighter is flagged R", function()
	local w, t = MW.Standard({ money = 3000000 })
	assert(t.king.Roles.SetSettings({ maxBet = 100 * G, maxDay = 500 * G }))
	w:Run(0)
	for round = 1, 3 do
		local eid = PublicFight(w, t)
		assert(t.b1.M.Bet(eid, 1, 1, 2000)); assert(t.b2.M.Bet(eid, 1, 1, 2000))
		w:Run(3)
		assert(t.hc.M.Bet(eid, 1, 2, 500)); assert(t.hc2.M.Bet(eid, 1, 2, 500))
		w:Run(3)
		assert(t.b3.M.Bet(eid, 1, 2, 4000))
		w:Run(300)
		assert(t.arbiter.M.Declare(eid, { winner = "A" }))
		w:Run(301)
		eq(Has(Flags(w, t, eid), "U", N.bettor3), true)
		eq(Has(Flags(w, t, eid), "R", N.bettor3), round == 3, "round " .. round)
	end
	w:NoErrors()
end)

test("1.2 the markets: privacy: a market run to its payout puts no bettor's name on the channel, and no amount but the pools", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	local stakes = { [t.b1] = 1300, [t.b2] = 1700, [t.b3] = 900, [t.steward] = 1100 }
	for c, s in pairs(stakes) do
		assert(c.M.Bet(eid, 1, c == t.b3 and 2 or 1, s))
		w:Run(3)
	end
	w:Run(300)
	assert(t.arbiter.M.Declare(eid, { winner = "B" }))
	w:Run(400)
	local text = w:ChannelText()
	for _, name in ipairs({ N.bettor1, N.bettor2, N.bettor3, N.steward }) do
		local short = name:gsub("%-.*$", "")
		eq(text:find(short, 1, true), nil, short .. " on the channel")
	end
	-- On the channel only the sheet, the pools and the overrules: every BO reads back as pools and
	-- counts per outcome and nothing else; slips, answers and flags are whispers.
	for _, s in ipairs(w:Sent{ dist = "CHANNEL" }) do
		local kind = s.msg:sub(1, 2)
		eq(kind == "BS" or kind == "BK" or kind == "BF", false, kind .. " on the channel")
		if kind == "BO" then
			local book = assert(t.b1.ns.Markets.ReadBook(s.msg:sub(7)))
			eq(#book.markets[1].pools, 2); eq(#book.markets[1].counts, 2)
			eq(s.msg:match("^BO~L1~[^~]+~[^~]+~[^~]+~[^~]+~[^~]+~1:[OLSVH]:[0-9a-z.]+:[0-9a-z.]+:?[0-9a-z+]*$") ~= nil, true, s.msg)
		end
	end
	w:NoErrors()
end)

test("1.2 the markets: rates: 20 slips an event from one sender; an ordinary book at most every 10 s per event, the lock's at once", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t, nil, { lockAt = w.clock + 600 })
	for i = 1, 20 do
		eq(Slip(w, t.b1, t.bank, eid, 1, 1, 10, Nonce()), nil, "slip " .. i)
		w:Run(2)
	end
	eq(Slip(w, t.b1, t.bank, eid, 1, 1, 10, Nonce()), "R", "the 21st")
	-- The bettor's own client never sends a 21st.
	for i = 1, 20 do
		assert(t.b2.M.Bet(eid, 1, 2, 10))
		w:Run(2)
	end
	eq(select(2, t.b2.M.CanBet(eid, 1, 2, 10)), "rate")
	w:Run(600)
	local last, urgent = nil, 0
	for _, s in ipairs(w:Sent{ from = t.bank, type = "BO" }) do
		if s.urgent then
			urgent = urgent + 1
		else
			if last then eq(s.t - last >= 10, true, "10 s apart: " .. (s.t - last)) end
			last = s.t
		end
	end
	eq(urgent >= 1, true, "the lock's book")
	w:NoErrors()
end)

print("Markets: the lock and the King's delay, currencies, the sheet's and the book's checks")

test("1.2 the markets: the King's published delay sets the window (max(120, delay + 75)) and the Bell's last call (max(20, delay + 20)), to the second, whoever opens a public event", function()
	local w, t = MW.Standard()
	local function Try(by, ahead)
		local eid = w:Fight{ opener = by, A = t.A, B = t.B }
		local ok, why = by.M.Open(eid, { markets = { { type = "MW" } }, lockAt = w.clock + ahead })
		return ok, why, eid
	end
	-- (Every client has been online longer than a sheet's repeat and its slack: 90 s.)
	w:Run(100)
	-- No delay: 120 s at least; the Bell: 20 s. A non-King opener's own stored delay counts for
	-- nothing (only the King's view keeps its own): 120 and 20 still.
	t.arbiter.ns.db.arenaUI = { delay = 300 }
	eq(select(2, Try(t.arbiter, 119)), "window")
	local opened = w.clock
	local ok, _, eid = Try(t.arbiter, 300)
	eq(ok, true)
	w:Run(5)
	-- The Bell rung 5 s after the opening keeps the window: the bets stay open until opened + 120.
	eq(t.arbiter.M.CloseBets(eid), true)
	w:Run(0)
	eq(t.b1.M.Sheet(eid).lockAt, opened + 120, "rung early: the whole window from the opening")
	eq(t.bank.M.Sheet(eid).lockAt, opened + 120)
	-- Rung 200 s after the opening: the last call from now.
	opened = w.clock
	ok, _, eid = Try(t.arbiter, 600)
	eq(ok, true)
	w:Run(200)
	eq(t.arbiter.M.CloseBets(eid), true)
	w:Run(0)
	eq(t.b1.M.Sheet(eid).lockAt, w.clock + 20)
	-- The King streams with 30 s: 120 and 50.
	assert(t.king.Arena.SetDelay(30))
	w:Run(0)
	eq(select(2, Try(t.hc, 119)), "window")
	opened = w.clock
	ok, _, eid = Try(t.hc, 600)
	eq(ok, true)
	w:Run(1)
	-- One second in (the review's probe): SetLock and the Bell both keep the 120 s window.
	eq(select(2, t.hc.M.SetLock(eid, w.clock + 51)), "soon", "a 52 s window refused")
	eq(select(2, t.hc.M.SetLock(eid, opened + 119)), "soon")
	assert(t.hc.M.CloseBets(eid))
	w:Run(0)
	eq(t.b1.M.Sheet(eid).lockAt, opened + 120, "the Bell rung at once: still 120 s from the opening")
	eq(t.b1.M.Sheet(eid).rev, 2)
	opened = w.clock
	ok, _, eid = Try(t.hc, 600)
	w:Run(100)
	assert(t.hc.M.CloseBets(eid))
	w:Run(0)
	eq(t.b1.M.Sheet(eid).lockAt, w.clock + 50, "the Bell: lockAt = now + Arena.LastCall(), to the second")
	-- 120 s: 195 and 140, for a High Councillor's event too.
	assert(t.king.Arena.SetDelay(120))
	w:Run(0)
	eq(select(2, Try(t.hc, 194)), "window")
	opened = w.clock
	ok, _, eid = Try(t.hc, 195)
	eq(ok, true)
	w:Run(10)
	eq(t.hc.M.SetLock(eid, w.clock + 139), false, "under the last call")
	assert(t.hc.M.CloseBets(eid))
	w:Run(0)
	eq(t.b1.M.Sheet(eid).lockAt, opened + 195, "the window's 195 s, the later of the two")
	-- A modified opener's first rev with a shorter window: refused by every client.
	local function Raw(eidX, rev, lockAt)
		w:As(t.arbiter, function()
			t.arbiter.ns.Arena.Send("BM", "L", ("%s~%s~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O"):format(eidX, B36(rev), N.bank, B36(lockAt)))
		end)
		w:Run(0)
	end
	local eid2 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	Raw(eid2, 1, w.clock + 150)
	eq(t.b1.M.Has(eid2), false, "195 s at least, less the send's slack")
	-- ... or starting at rev 2 (the rev 1 rule is every first-heard rev's): refused too, the bank's
	-- client as well (it takes no slip on it).
	local eid3 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	Raw(eid3, 2, w.clock + 150)
	eq(t.b1.M.Has(eid3), false, "a first rev 2 with 150 s")
	eq(t.bank.M.Has(eid3), false)
	-- A later rev: its lockAt under the last call from now (140 s, less the slack) is refused; every
	-- client keeps the rev before it, the bank its lock.
	local eid4 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	opened = w.clock
	Raw(eid4, 1, w.clock + 600)
	eq(t.b1.M.Has(eid4), true)
	w:Run(30)
	Raw(eid4, 2, w.clock + 100)
	eq(t.b1.M.Sheet(eid4).rev, 1, "under the last call: refused")
	eq(t.bank.M.Sheet(eid4).lockAt, opened + 600, "the bank keeps its lock")
	Raw(eid4, 3, opened + 195)
	eq(t.b1.M.Sheet(eid4).rev, 3, "the honest Bell's lock: taken")
	eq(t.bank.M.Sheet(eid4).lockAt, opened + 195)
	-- Without a delay (120 and 20): one under the window from this client's first hearing, less
	-- the 90 s a rev 1 may have been out before it (its 60 s repeats and the send's slack), refused.
	assert(t.king.Arena.SetDelay(0))
	w:Run(0)
	local eid5 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	opened = w.clock
	Raw(eid5, 1, w.clock + 600)
	w:Run(5)
	Raw(eid5, 2, opened + 29)
	eq(t.b1.M.Sheet(eid5).rev, 1, "a 29 s window: refused")
	eq(t.bank.M.Sheet(eid5).lockAt, opened + 600)
	Raw(eid5, 3, opened + 120)
	eq(t.b1.M.Sheet(eid5).rev, 3); eq(t.bank.M.Sheet(eid5).lockAt, opened + 120)
	-- A member who logged in during the window never refuses the honest Bell (he cannot know when
	-- the sheet opened): only the last call applies to him.
	local late = w:Player("Mira Dune")
	-- Addon messages have no history: give the late client the bank and settings words before the
	-- market sheet whose window this assertion is measuring.
	t.king.Roles.Repeat()
	w:Run(3)
	local eid6 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	opened = w.clock
	Raw(eid6, 1, w.clock + 600)
	eq(late.M.Sheet(eid6).rev, 1)
	w:Run(5)
	Raw(eid6, 2, opened + 29)
	eq(late.M.Sheet(eid6).rev, 2, "online 5 s: the rev is taken")
	w:NoErrors()
end)

test("1.2 the markets: glory points (cur p): the book in points, no fee, gold untouched; chips (cur c) only in a rehearsal", function()
	local w, t = MW.Standard({ settings = { live = 1, cur = "p" }, points = 500000 })
	local eid = PublicFight(w, t)
	local s = t.b1.M.Sheet(eid)
	eq(s.cur, "p"); eq(s.fee.g, 0); eq(s.fee.a, 0)
	assert(t.b1.M.Bet(eid, 1, 1, 1000))
	assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(301)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(301)
	eq(Bal(w, t, t.b1, "p"), 500000 - 100000 + 200000, "all of it: no fee on points")
	eq(Bal(w, t, t.b1, "g"), 1000000, "gold untouched")
	eq(w:Ledger(t.bank).guild, 0)
	-- Chips are a rehearsal's: a live sheet in chips is refused, a rehearsal's is taken.
	local eidC = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	eq(select(2, t.arbiter.M.Open(eidC, { markets = { { type = "MW" } }, cur = "c", lockAt = w.clock + 300 })), "cur")
	local eidT = w:Fight{ opener = t.arbiter, A = t.A, B = t.B, mode = "T" }
	eq(t.arbiter.M.Open(eidT, { markets = { { type = "MW" } }, cur = "c", lockAt = w.clock + 300 }), true)
	w:Run(0)
	eq(t.b1.M.Sheet(eidT).cur, "c")
	eq(w:Sent{ type = "BM", from = t.arbiter }[#w:Sent{ type = "BM", from = t.arbiter }].msg:sub(1, 6), "BM~T1~")
	w:NoErrors()
end)

test("1.2 the markets: the sheet's checks: only its event's opener, a public arbiter for public markets, newer revs, the event known within 60 s, 14 days, 40 markets, the outcomes, the live switch, the fee", function()
	local w, t = MW.Standard({ extra = { { "promoter", "Petra Wick" } } })
	local function Body(eid, rev, lockAt, markets, fee, bank, cur)
		return ("%s~%s~%s~%s~%s~%s~-~-~%s"):format(eid, B36(rev), bank or N.bank, cur or "g", fee or "b4.5k.a", B36(lockAt or (w.clock + 600)), markets or "1:MW:-:2:O")
	end
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	RawSheet(w, t.b1, Body(eid, 1))
	eq(t.b2.M.Has(eid), false, "not the event's opener")
	RawSheet(w, t.arbiter, Body(eid, 1, nil, "1:MW:-:3:O"))
	eq(t.b2.M.Has(eid), false, "a winner market has two outcomes")
	RawSheet(w, t.arbiter, Body(eid, 1, w.clock + 15 * 86400))
	eq(t.b2.M.Has(eid), false, "past 14 days")
	RawSheet(w, t.arbiter, Body(eid, 1, nil, nil, "cw.5k.a"))
	eq(t.b2.M.Has(eid), false, "another fee than the King's")
	local many = {}
	for i = 1, 41 do many[i] = B36(i) .. ":MW:-:2:O" end
	RawSheet(w, t.arbiter, Body(eid, 1, nil, table.concat(many, ";")))
	eq(t.b2.M.Has(eid), false, "41 markets")
	RawSheet(w, t.arbiter, Body(eid, 1, nil, "1:QQ:-:2:O"))
	eq(t.b2.M.Has(eid), false, "an unknown kind")
	RawSheet(w, t.arbiter, Body(eid, 1, nil, "1:CH:-:2:O"))
	eq(t.b2.M.Has(eid), false, "a tournament's kind on a fight")
	RawSheet(w, t.arbiter, Body(eid, 1))
	eq(t.b2.M.Has(eid), true)
	-- An older or equal rev never replaces the kept one (the first kept on a clash).
	RawSheet(w, t.arbiter, Body(eid, 3, w.clock + 700))
	RawSheet(w, t.arbiter, Body(eid, 2, w.clock + 800))
	eq(t.b2.M.Sheet(eid).rev, 3); eq(t.b2.M.Sheet(eid).lockAt, w.clock + 700)
	RawSheet(w, t.arbiter, Body(eid, 3, w.clock + 900))
	eq(t.b2.M.Sheet(eid).lockAt, w.clock + 700, "same rev, other contents: the first kept")
	-- A public market needs a public arbiter.
	local eidP = w:Fight{ opener = t.promoter, A = t.A, B = t.B }
	eq(select(2, t.promoter.M.Open(eidP, { markets = { { type = "MW" } } })), "public")
	-- A sheet before its event: kept 60 s, taken when the event appears.
	local eidLate = w:Eid("F")
	RawSheet(w, t.arbiter, Body(eidLate, 1))
	eq(t.b2.M.Has(eidLate), false)
	w:Fight{ eid = eidLate, opener = t.arbiter, A = t.A, B = t.B }
	w:Run(30)
	w:As(t.b2, function() t.b2.ns.Arena.Changed() end)
	eq(t.b2.M.Has(eidLate), true, "taken once its event is known")
	local eidGone = w:Eid("F")
	RawSheet(w, t.arbiter, Body(eidGone, 1, w.clock + 600))
	w:Run(61)
	w:Fight{ eid = eidGone, opener = t.arbiter, A = t.A, B = t.B }
	w:As(t.b2, function() t.b2.ns.Arena.Changed() end)
	eq(t.b2.M.Has(eidGone), false, "dropped after 60 s")
	-- Gold in the live arena needs the live switch.
	local w2, t2 = MW.Standard({ live = false })
	local eidL = w2:Fight{ opener = t2.arbiter, A = t2.A, B = t2.B }
	eq(t2.arbiter.ns.Arena.NewMode(false), "T", "(new events are rehearsals)")
	w2:As(t2.king, function() t2.king.ns.ArenaRoles.SetSettings({ live = 1 }) end)
	w2:Run(0)
	w2:As(t2.king, function() t2.king.ns.ArenaRoles.SetSettings({ live = 0 }) end)
	w2:Run(0)
	w2:As(t2.arbiter, function() t2.arbiter.ns.Comm.Send("CHANNEL", "BM~L1~" .. ("%s~1~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O"):format(eidL, N.bank, B36(w2.clock + 600))) end)
	w2:Run(0)
	eq(t2.b1.M.Has(eidL), false, "live switch off")
	w:NoErrors()
end)

test("1.2 the markets: terms never change under bets: a new rev changing a market with bets is refused by every client and the bank voids the event (T)", function()
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B, mode = "T" }
	assert(t.arbiter.M.Open(eid, { markets = { { type = "MW" }, { type = "DU", param = 90 } }, lockAt = w.clock + 300 }))
	w:Run(0)
	assert(t.b1.M.Bet(eid, 2, 1, 500))
	assert(t.b2.M.Bet(eid, 2, 2, 500))
	w:Run(15)
	local text = SheetText(t.arbiter, eid):gsub("^([^~]+)~1~", "%1~2~"):gsub("2:DU:2i:", "2:DU:2s:")
	RawSheet(w, t.arbiter, text, "T")
	eq(t.b3.M.Sheet(eid, "T").rev, 1, "refused")
	eq(Bal(w, t, t.b1), 1000000, "the bank voided the event: every stake back")
	w:Run(15)
	eq(t.b3.M.View(eid).markets[2].result, "T")
	w:NoErrors()
end)

test("1.2 the markets: the book's checks: only the sheet's bank, pools and counts consistent, O only before the lock, S only after the sheet's R, a new session newer", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 700))
	w:Run(15)
	local kept = t.b3.M.Book(eid)
	eq(kept.markets[1].pools[1], 500); eq(kept.markets[1].pools[2], 700)
	local function Raw(from, body, dist)
		w:As(from, function() from.ns.Arena.Send("BO", "L", body, dist and { to = dist } or nil) end)
		w:Run(0)
	end
	local epoch = kept.epoch
	local function Body(n, rows, at)
		return ("%s~1~%s.%s~%s~0~%s"):format(eid, B36(epoch), B36(n), B36(at or w.clock), rows)
	end
	Raw(t.b1, Body(99, "1:O:dw.c:9.1"))
	eq(t.b3.M.Book(eid).markets[1].pools[1], 500, "not the bank")
	Raw(t.bank, Body(99, "1:O:dw.0:9.1"))
	eq(t.b3.M.Book(eid).markets[1].pools[1], 500, "a count without a pool")
	Raw(t.bank, Body(99, "1:O:5:1"))
	eq(t.b3.M.Book(eid).n, kept.n, "one pool for two outcomes")
	Raw(t.bank, Body(99, "1:S:dw.jg:1.1:1"))
	eq(t.b3.M.Book(eid).markets[1].state, "O", "settled before the sheet's result")
	Raw(t.bank, Body(99, "1:O:dw.jg:1.2"))
	eq(t.b3.M.Book(eid).markets[1].counts[2], 2, "a consistent book from the bank is taken")
	Raw(t.bank, Body(98, "1:O:dw.jg:1.3"))
	eq(t.b3.M.Book(eid).markets[1].counts[2], 2, "an older one is not")
	epoch = epoch + 1
	Raw(t.bank, Body(1, "1:O:dw.jg:1.4"))
	eq(t.b3.M.Book(eid).markets[1].counts[2], 4, "a new session's first book is newer")
	w:Run(310)
	epoch = epoch + 1
	Raw(t.bank, Body(1, "1:O:dw.jg:1.5"))
	eq(t.b3.M.Book(eid).markets[1].counts[2] ~= 5, true, "O after lockAt + 5")
	w:NoErrors()
end)

print("Markets: tournaments, stakes, Farkle, the Lottery, the bank's reload, the weight rule")

-- Ten entrants (eight and two on the waitlist, numbered as registration froze them): Torvin 1,
-- Selka 3, the rest invented names that never log in.
local function Entrants(t)
	return { t.A, "Ardo Venn", t.B, "Brisk Tallow", "Cael Morrow", "Dunn Asher", "Elsa Brant", "Fenn Oakes", "Galen Rhys", "Hilde Crane" },
		{ "WARRIOR", "MAGE", "ROGUE", "PRIEST", "WARRIOR", "MAGE", "HUNTER", "DRUID", "WARLOCK", "PALADIN" }
end

test("1.2 the markets: a tournament's markets open at registration close, keyed by entrant; a no-show is scratched (refunded, the pools shrink); entrants bet only on themselves; the bracket pool after the draw; paid per stage to the copper", function()
	local w, t = MW.Standard()
	local list, classes = Entrants(t)
	local eid = w:Tourney{ opener = t.arbiter, entrants = list, classes = classes }
	-- Registration closed: the outrights open, days before the first bell.
	eq(t.arbiter.M.Open(eid, { markets = { { type = "CH" }, { type = "RF" }, { type = "RS" }, { type = "RQ" }, { type = "ST", param = 3 },
		{ type = "ST", param = 4 }, { type = "WC" } }, lockAt = w.clock + 3 * 86400 }), true)
	w:Run(0)
	local s = t.b1.M.Sheet(eid)
	eq(s.markets[1].n, 10, "one outcome per entrant, the waitlist included")
	eq(select(2, t.arbiter.M.AddMarkets(eid, { { type = "PK", param = 10 } })), "draw", "the bracket pool waits for the draw")
	-- Bets by entrant number.
	assert(t.b1.M.Bet(eid, 2, 1, 1000)); assert(t.b2.M.Bet(eid, 2, 5, 1000))
	w:Run(3)
	assert(t.b3.M.Bet(eid, 2, 2, 2000)); assert(t.hc.M.Bet(eid, 2, 4, 1000))
	w:Run(3)
	assert(t.b1.M.Bet(eid, 1, 4, 1000)); assert(t.b2.M.Bet(eid, 1, 1, 1000))
	w:Run(3)
	assert(t.b3.M.Bet(eid, 1, 2, 1000)); assert(t.hc2.M.Bet(eid, 6, 2, 500))
	w:Run(3)
	assert(t.steward.M.Bet(eid, 4, 1, 1000)); assert(t.auditor.M.Bet(eid, 4, 10, 1000))
	w:Run(3)
	-- Entrants: the champion on themselves (and their own stage market's champion), nothing else.
	eq(Slip(w, t.A, t.bank, eid, 1, 1, 10, Nonce()), nil, "Torvin on himself to win it")
	eq(Slip(w, t.B, t.bank, eid, 5, 1, 100, Nonce()), nil, "Selka's own stage market: champion")
	w:Run(3)
	eq(Slip(w, t.B, t.bank, eid, 5, 5, 100, Nonce()), "A", "her own early exit")
	w:Run(3)
	eq(Slip(w, t.B, t.bank, eid, 2, 3, 100, Nonce()), "A", "reaching the final, on herself")
	w:Run(3)
	eq(Slip(w, t.A, t.bank, eid, 1, 2, 100, Nonce()), "A", "another entrant")
	eq(select(2, t.B.M.CanBet(eid, 5, 5, 100)), "conflict")
	-- Check-in: Brisk (4) never shows. His outcomes are scratched; his stage market is void.
	eq(t.arbiter.M.Scratch(eid, { 4 }), true)
	w:Run(0)
	eq(Bal(w, t, t.hc2), 1000000, "his stage market void at once: refunded")
	eq(Slip(w, t.b3, t.bank, eid, 1, 4, 100, Nonce()), "O", "no new bet on a scratched entrant")
	w:Run(15)
	local v = t.b3.M.View(eid)
	eq(v.markets[2].outcomes[4].scratched, true); eq(v.markets[2].outcomes[4].pool, 0, "the pools shrink")
	eq(v.markets[7].outcomes[5].scratched, true, "no priest left: the class is scratched")
	eq(v.markets[7].outcomes[1].scratched, nil)
	-- Check-in fixed the bracket at 8: a stage it cannot produce is scratched. The bracket pool waits
	-- for the draw itself (the design: PK after the draw), not the size alone.
	assert(t.arbiter.M.SetSize(eid, 8))
	w:Run(0)
	eq(t.b3.M.View(eid).markets[5].outcomes[5].scratched, true, "out earlier than the quarterfinal: none in 8")
	eq(select(2, t.arbiter.M.AddMarkets(eid, { { type = "PK", param = 10 } })), "draw", "the size known, the bracket not drawn yet")
	local early = t.b1.M.Sheet(eid)
	local body = SheetText(t.arbiter, eid):gsub("^([^~]+)~" .. B36(early.rev) .. "~", "%1~" .. B36(early.rev + 1) .. "~") .. ";8:PK:a:8:O"
	RawSheet(w, t.arbiter, body)
	eq(t.b1.M.Sheet(eid).rev, early.rev, "a modified opener's PK before the draw: refused by every client")
	w.events[eid].drawn = true
	eq(t.arbiter.M.AddMarkets(eid, { { type = "PK", param = 10 } }), true)
	w:Run(0)
	local pk = t.b1.M.Sheet(eid).markets[8]
	eq(pk.type, "PK"); eq(pk.n, 8)
	assert(t.b1.M.Bet(eid, 8, "p00", 10)); assert(t.b2.M.Bet(eid, 8, "pfe", 10))
	w:Run(3)
	eq(Slip(w, t.A, t.bank, eid, 8, "p00", 10, Nonce()), "A", "an entrant never enters the pool")
	eq(Slip(w, t.b3, t.bank, eid, 8, "p00", 20, Nonce()), "M", "the entry is 10 s")
	eq(Slip(w, t.b1, t.bank, eid, 8, "pfe", 10, Nonce()), "X", "one entry a character")
	-- A fresh sender isolates the outcome check from the bank's per-sender two-second slip gate.
	eq(Slip(w, t.steward, t.bank, eid, 8, "p0", 10, Nonce()), "O", "picks of the wrong length")
	-- The first bell locks every market (a few are void: bets on one side only).
	assert(t.arbiter.M.CloseBets(eid))
	-- The Bell keeps the full minimum betting window before a result may be declared.
	w:Run(t.arbiter.M.Sheet(eid).lockAt - w.clock + 1)
	-- Quarterfinals known first: that market alone is declared.
	local ok, n = t.arbiter.M.Declare(eid, { quarterfinalists = { 1, 2, 3, 5, 6, 7, 8, 9 } })
	eq(ok, true); eq(n, 1)
	w:Run(0)
	eq(t.b1.M.Sheet(eid).markets[4].state, "R")
	eq(t.b1.M.Sheet(eid).markets[2].state, "L", "the final not known yet")
	assert(t.arbiter.M.Declare(eid, { champion = 1, finalists = { 1, 5 }, semifinalists = { 1, 2, 5, 6 }, stages = { [3] = 4 }, class = "WARRIOR", bracket = "00" }))
	w:Run(301)
	-- RF (k = 2): pools without the scratched entrant: e1 10 g, e5 10 g, e2 20 g. W = 20 g, L = 20 g:
	-- cut 12,000 (arbiter 4,000, guild 8,000), D = 188,000, 94,000 an outcome: Lida 194,000, Parric
	-- 194,000; the councillor's 10 g on Brisk back.
	-- CH: e1 Parric 10 g + Torvin 10 s = 101,000, e2 Wenna 10 g; Lida's 10 g on Brisk back. L = 100,000,
	-- cut 6,000 (2,000 and 4,000), D = 94,000: Parric 100,000 + floor(94,000 x 100,000 / 101,000) =
	-- 193,069; Torvin 1,000 + floor(94,000 x 1,000 / 101,000) = 1,930; one copper left: the guild 4,001.
	-- PK: two entries of 10 s, Lida's picks perfect: L = 1,000, cut 60 (20 and 40): Lida 1,940.
	eq(Bal(w, t, t.b1), 1000000 - 100000 - 100000 - 1000 + 194000 + 100000 + 1940)
	eq(Bal(w, t, t.b2), 1000000 - 100000 - 100000 - 1000 + 194000 + 193069)
	eq(Bal(w, t, t.b3), 1000000 - 200000 - 100000)
	eq(Bal(w, t, t.hc), 1000000)
	eq(Bal(w, t, t.A), 1000000 - 1000 + 1930)
	-- RQ (eight places): the steward's 10 g on Torvin (in) against the auditor's 10 g on Hilde (out):
	-- one winning outcome with bets, L = 100,000: 194,000 to the steward.
	eq(Bal(w, t, t.steward), 1000000 + 94000)
	eq(w:Ledger(t.bank).guild, 8000 + 4001 + 40 + 4000); eq(w:Ledger(t.bank).arbiter[N.arbiter:lower()], 4000 + 2000 + 20 + 2000)
	w:Run(15)
	local pkTicket
	for _, tk in ipairs(t.b1.M.Tickets{ eid = eid }) do if tk.idx == 8 then pkTicket = tk end end
	eq(pkTicket.state, "won"); eq(pkTicket.payout, 1940, "the bracket pool's payout from the book's top score and winners")
	w:NoErrors()
end)

test("1.2 the markets: a 1v1's stakes through the wallet (CX): whispered to the parties and the bank only, each party exactly his own stake (K), a missing stake voids it (S); 14 g 70 s to the winner", function()
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.arbiter, A = t.A, B = t.B, public = false }
	eq(t.arbiter.M.Open(eid, { markets = { { type = "CX", param = { 1000, 500 } } }, lockAt = w.clock + 200 }), true)
	w:Run(0)
	eq(t.A.M.Has(eid), true); eq(t.B.M.Has(eid), true); eq(t.bank.M.Has(eid), true)
	eq(t.b1.M.Has(eid), false, "nobody else")
	eq(#w:Sent{ type = "BM", dist = "CHANNEL" }, 0)
	eq(select(2, t.A.M.CanBet(eid, 1, 1, 900)), "min", "his own stake exactly")
	eq(select(2, t.A.M.CanBet(eid, 1, 2, 500)), "conflict", "on himself only")
	local ta = assert(t.A.M.Bet(eid, 1, 1, 1000))
	w:Run(3)
	local tb = assert(t.B.M.Bet(eid, 1, 2, 500))
	w:Run(0)
	eq(ta.state, "accepted"); eq(tb.state, "accepted")
	eq(Last(w, { type = "BK", to = N.fighterA }).msg:match("~(%a)$"), "K", "the bank's K: the entry goes on the channel as a digest")
	eq(Slip(w, t.b1, t.bank, eid, 1, 1, 1000, Nonce()), "A", "a third party")
	w:Run(200)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(301)
	-- Torvin 10 g, Selka 5 g, Torvin wins: cut = 6% of 5 g = 3,000 (arbiter 1,000, guild 2,000);
	-- he gets 150,000 - 3,000 = 147,000.
	eq(Bal(w, t, t.A), 1000000 - 100000 + 147000)
	eq(w:Ledger(t.bank).guild, 2000); eq(w:Ledger(t.bank).arbiter[N.arbiter:lower()], 1000)
	for _, s in ipairs(w:Sent{ type = "BO", from = t.bank }) do
		eq(s.dist, "WHISPER")
		eq(s.target == N.fighterA or s.target == N.fighterB or s.target == N.arbiter, true, s.target)
	end
	-- Selka never stakes: at the lock the market voids (S), Torvin's stake back.
	local eid2 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B, public = false }
	assert(t.arbiter.M.Open(eid2, { markets = { { type = "CX", param = { 500, 500 } } }, lockAt = w.clock + 200 }))
	w:Run(3)
	assert(t.A.M.Bet(eid2, 1, 1, 500))
	w:Run(0)
	local bal = Bal(w, t, t.A)
	w:Run(201)
	eq(Bal(w, t, t.A), bal + 50000)
	w:Run(15)
	eq(t.A.M.View(eid2).markets[1].result, "S")
	w:NoErrors()
end)

test("1.2 the markets: a Farkle table's stakes (FK) settle only when the gate says so (the Bone Throw tables: the arbiter's KE agrees with a player's): wait, hold, then pay", function()
	local w, t = MW.Standard()
	local eid = w:Farkle{ opener = t.arbiter, A = t.A, B = t.B }
	assert(t.arbiter.M.Open(eid, { markets = { { type = "FK", param = { 500, 500 } } }, lockAt = w.clock + 200 }))
	w:Run(0)
	assert(t.A.M.Bet(eid, 1, 1, 500))
	w:Run(3)
	assert(t.B.M.Bet(eid, 1, 2, 500))
	w:Run(200)
	local verdict = false
	eq(t.bank.MB.SetGate("K", function(e, idx) return e == eid and verdict end), true)
	assert(t.arbiter.M.Declare(eid, { winner = "B" }))
	w:Run(301)
	eq(Bal(w, t, t.B), 950000, "no agreeing KE yet")
	verdict = "hold"
	w:Run(2)
	w:Run(15)
	eq(t.A.M.View(eid).markets[1].state, "H")
	-- A King's P rules on it (the auditors' ruling, the design); the gate agrees now.
	verdict = true
	assert(t.king.M.Overrule(eid, 1, "P"))
	w:Run(2)
	eq(Bal(w, t, t.B), 950000 + 97000)
	w:NoErrors()
end)

-- The crowd's bets at a Bone Throw table (2026-10-04): a public arbiter's table may carry the
-- crowd's winner market (MW), settled like a fight's; a private table never may, and the crowd's
-- sheet on the channel names neither stake nor bettor.
test("1.2 the crowd's winner market at a public Bone Throw table: bet by the crowd, settled to the copper; never at a private table; the sheet names no bettor", function()
	local w, t = MW.Standard()
	local eid = w:Farkle{ opener = t.arbiter, A = t.A, B = t.B }
	-- A private table (its stakes the players' own): no public market.
	eq(select(2, t.arbiter.M.Open(eid, { markets = { { type = "MW" } }, lockAt = w.clock + 300 })), "public")
	w.events[eid].public = true
	eq(t.arbiter.M.Open(eid, { markets = { { type = "MW" } }, lockAt = w.clock + 300 }), true)
	w:Run(0)
	eq(t.b1.M.Has(eid), true, "the crowd heard the sheet")
	local sheets = w:Sent{ type = "BM", dist = "CHANNEL" }
	local body = sheets[#sheets].msg
	assert(body:find(eid, 1, true) and body:find(":MW:-:2:O", 1, true), body)
	for _, who in ipairs({ N.bettor1, N.bettor2 }) do assert(not body:find(who, 1, true), "no bettor in the sheet: " .. body) end
	-- The arbiter never bets; a player only on himself.
	eq(select(2, t.arbiter.M.CanBet(eid, 1, 1, 1000)), "conflict")
	eq(select(2, t.A.M.CanBet(eid, 1, 2, 1000)), "conflict")
	eq(t.A.M.CanBet(eid, 1, 1, 1000), true)
	local ta = assert(t.b1.M.Bet(eid, 1, 1, 1000))
	local tb = assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(301)
	eq(t.b1.M.View(eid).markets[1].state, "L")
	-- The table's arbiter declares it as he settles (FarkleTable's explicit result: seat 1 won).
	assert(t.arbiter.M.Declare(eid, { [1] = "1" }))
	w:Run(301)
	-- As the fight's: 10 g on each side, seat 1 wins: Lida is paid 100,000 + 94,000 = 194,000.
	eq(Bal(w, t, t.b1), 900000 + 194000)
	eq(Bal(w, t, t.b2), 900000)
	eq(w:Ledger(t.bank).guild, 4000); eq(w:Ledger(t.bank).arbiter[N.arbiter:lower()], 2000)
	w:Run(15)
	eq(ta.state, "won"); eq(ta.payout, 194000); eq(tb.state, "lost")
	-- A void table's market: every stake back.
	local eid2 = w:Farkle{ opener = t.arbiter, A = t.A, B = t.B }
	w.events[eid2].public = true
	assert(t.arbiter.M.Open(eid2, { markets = { { type = "MW" } }, lockAt = w.clock + 300 }))
	w:Run(0)
	assert(t.b1.M.Bet(eid2, 1, 2, 1000))
	w:Run(301)
	eq(t.arbiter.M.Void(eid2, "*", "X"), true)
	w:Run(301)
	eq(Bal(w, t, t.b1), 900000 + 194000, "the 10 g came back")
	w:NoErrors()
end)

-- A Bones game lasts longer than a fight: the crowd's market locks at about the first throw and is
-- declared only after the game, the agreement and its grace. The bank voided any market still
-- locked NO_RESULT (30 minutes, sized for fights) after its lock, code G: a long game's crowd was
-- refunded and the arbiter's declaration refused (a void is final). A table's market waits
-- TABLE_MAX, then G as before.
test("1.2 the crowd's winner market at a Bone Throw table: a game longer than a fight's NO_RESULT is still paid; voided G only after TABLE_MAX", function()
	local w, t = MW.Standard()
	local M = t.bank.ns.Markets
	assert(M.TABLE_MAX > M.NO_RESULT, "a table waits longer than a fight")
	local eid = w:Farkle{ opener = t.arbiter, A = t.A, B = t.B }
	w.events[eid].public = true
	assert(t.arbiter.M.Open(eid, { markets = { { type = "MW" } }, lockAt = w.clock + 300 }))
	w:Run(0)
	local ta = assert(t.b1.M.Bet(eid, 1, 1, 1000))
	assert(t.b2.M.Bet(eid, 1, 2, 1000))
	w:Run(301)
	-- An hour's game, then the agreement and the grace: still locked, then declared and paid.
	Wait(w, 3600)
	eq(t.b1.M.View(eid).markets[1].state, "L", "not voided after a fight's 30 minutes")
	assert(t.arbiter.M.Declare(eid, { [1] = "1" }))
	w:Run(301)
	eq(Bal(w, t, t.b1), 900000 + 194000, "the winner paid")
	w:Run(15)
	eq(ta.state, "won")
	-- An arbiter who never declares: G once TABLE_MAX has passed since the lock.
	local eid2 = w:Farkle{ opener = t.arbiter, A = t.A, B = t.B }
	w.events[eid2].public = true
	assert(t.arbiter.M.Open(eid2, { markets = { { type = "MW" } }, lockAt = w.clock + 300 }))
	w:Run(0)
	assert(t.b1.M.Bet(eid2, 1, 2, 1000))
	assert(t.b2.M.Bet(eid2, 1, 1, 1000))
	w:Run(301)
	Wait(w, M.TABLE_MAX - 30)
	eq(t.b1.M.View(eid2).markets[1].state, "L", "still waiting")
	w:Run(60)
	w:Run(15)
	eq(t.b1.M.View(eid2).markets[1].result, "G")
	eq(Bal(w, t, t.b1), 900000 + 194000, "the stakes came back")
	eq(Bal(w, t, t.b2), 900000)
	w:NoErrors()
end)

test("1.2 the markets: the Menagerie Lottery settles five places, refunds once, charges 6% only on claimed profit, and carries unclaimed tranches", function()
	local w, t = MW.Standard()
	eq(t.b1.M.BeastOf(1234), 9); eq(t.b1.M.BeastOf(1), 1); eq(t.b1.M.BeastOf(4), 1); eq(t.b1.M.BeastOf(5), 2)
	eq(t.b1.M.BeastOf(0), 25); eq(t.b1.M.BeastOf(10000), 25); eq(t.b1.M.BeastOf(99), 25); eq(t.b1.M.BeastOf(97), 25)
	local function Day(carry)
		local eid = w:LotteryDay{ opener = t.king, drawAt = w.clock + 600 }
		local ok, why = t.king.M.OpenLottery(eid, { drawAt = w.clock + 600, carry = carry })
		assert(ok, tostring(why))
		w:Run(0)
		return eid
	end
	-- Day 1: the Cobra is first and the Turtle fourth; both stakes return. A third, losing ticket
	-- creates 10 g of profit: 5 g and 1 g are claimed, 4 g rolls over, and 6% of 6 g is the fee.
	local d1 = Day(0)
	eq(t.king.M.Sheet(d1).markets[1].param, "2", "the sheet names settlement contract v2")
	eq(t.king.M.ParseParam(t.king.M.KINDS.LO, "-"), nil, "a versionless one-head sheet is rejected")
	eq(t.b3.M.View(d1).markets[1].outcomes[25].o, 25)
	assert(t.b1.M.Bet(d1, 1, 9, 1000)); assert(t.b2.M.Bet(d1, 1, 3, 1000)); assert(t.b3.M.Bet(d1, 1, 2, 1000))
	w:Run(600)
	local old, oldWhy = t.king.M.Declare(d1, { [1] = { 9 }, draw = { 1234, 5555, 0, 1111, 2222 } })
	eq(old, false); eq(oldWhy, "version", "the old head-only declaration is rejected")
	eq(t.king.M.DeclareDraw(d1, { 1234, 5555, 0, 1111, 2222 }), true)
	w:Run(301)
	eq(Bal(w, t, t.b1), 1000000 + 47000); eq(Bal(w, t, t.b2), 1000000 + 9400)
	eq(w:Ledger(t.bank).guild, 3600)
	eq(t.b1.M.Carry(d1), 40000)
	-- Day 2: nobody picked any drawn beast, so all 20 g becomes unclaimed profit and carries.
	local d2 = Day(0)
	assert(t.b1.M.Bet(d2, 1, 5, 1000)); assert(t.b2.M.Bet(d2, 1, 6, 1000))
	w:Run(600)
	assert(t.king.M.DeclareDraw(d2, { 99, 1, 2, 3, 4 }))
	w:Run(316)
	eq(t.b1.M.Carry(d2), 200000); eq(t.b3.M.View(d2).markets[1].state, "S", "the day settles even while its carry waits")
	eq(Bal(w, t, t.b2), 1000000 + 9400 - 100000)
	-- Day 3 with 20 g carried: Sheep first and Spider third. Both stakes return. The 20 g profit
	-- pool claims 10 g + 3 g, pays a 78 s aggregate fee, and carries the unclaimed 5 g + 2 g.
	local carry, from = t.b1.M.Carry(d2)
	local d3 = Day({ from = from, copper = carry })
	w:Run(1) -- the bank's one-second pump moves the claimed retained pot
	eq(t.b3.M.View(d2).markets[1].state, "S")
	eq(t.b3.M.View(d3).markets[1].carry, 200000)
	assert(t.b3.M.Bet(d3, 1, 7, 1000)); assert(t.b1.M.Bet(d3, 1, 8, 1000))
	w:Run(600)
	assert(t.king.M.DeclareDraw(d3, { 25, 8000, 3131, 42, 7 }))
	w:Run(301)
	eq(Bal(w, t, t.b3), 1000000 - 200000 + 194000)
	eq(w:Ledger(t.bank).guild, 3600 + 7800)
	eq(t.b1.M.Carry(d3), 70000)
	w:Run(15)
	eq(t.b3.M.Tickets{ eid = d3 }[1].payout, 194000)
	w:NoErrors()
end)

for _, way in ipairs({ "Entries", "Bets" }) do
test("1.2 the markets: the bank's index is rebuilt from its ledger at load (Wallet." .. way .. "): after losing it mid-tournament, RF and the bracket pool settle to the same copper", function()
	local w, t = MW.Standard()
	if way == "Bets" then t.bank.ns.Wallet.Entries = nil end
	local list, classes = Entrants(t)
	local eid = w:Tourney{ opener = t.arbiter, entrants = list, classes = classes, size = 8, drawn = true }
	assert(t.arbiter.M.Open(eid, { markets = { { type = "RF" }, { type = "PK", param = 10 } }, lockAt = w.clock + 3600 }))
	w:Run(0)
	assert(t.b1.M.Bet(eid, 1, 1, 1000)); assert(t.b2.M.Bet(eid, 1, 5, 1000))
	w:Run(3)
	assert(t.b3.M.Bet(eid, 1, 2, 2000)); assert(t.b1.M.Bet(eid, 2, "p00", 10))
	w:Run(3)
	assert(t.b2.M.Bet(eid, 2, "pfe", 10))
	w:Run(0)
	-- The bank's index lost (a crash before it saved): rebuilt from the ledger.
	t.bank.ns.Arena.Store("L").bankEvents = nil
	eq(t.bank.MB.Rebuild("L"), true)
	eq(t.bank.MB.Count("L", eid, 1), 3); eq(t.bank.MB.Count("L", eid, 2), 2)
	eq(Slip(w, t.b1, t.bank, eid, 2, "pfe", 10, Nonce()), "X", "Lida's entry is known again")
	assert(t.arbiter.M.CloseBets(eid))
	w:Run(t.arbiter.M.Sheet(eid).lockAt - w.clock + 1)
	assert(t.arbiter.M.Declare(eid, { finalists = { 1, 5 }, bracket = "00" }))
	w:Run(301)
	-- RF as the tournament's test without the scratch: e1 10 g, e5 10 g, e2 20 g: Lida and Parric
	-- 194,000 each. PK: Lida 1,940.
	eq(Bal(w, t, t.b1), 1000000 - 100000 - 1000 + 194000 + 1940)
	eq(Bal(w, t, t.b2), 1000000 - 100000 - 1000 + 194000)
	w:NoErrors()
end)
end

test("1.2 the markets: the weight rule: a member who only hears a public market runs no timer, registers no event, makes no frame and saves nothing of it", function()
	local w, t = MW.Standard({ extra = { { "idle", "Mira Dune" } } })
	-- the screens deliberately opens the public-market alert window by default.  Turn that independent UI
	-- preference off so this remains a measurement of the markets' passive market machinery alone.
	t.idle.ns.db.arenaUI = { alerts = false }
	local before = w:ArenaWeight(t.idle)
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500)); assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(400)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(400)
	eq(t.idle.M.Has(eid), true, "it shows the market (memory)")
	local after = w:ArenaWeight(t.idle)
	eq(table.concat(after.events, ","), table.concat(before.events, ","))
	eq(after.timers, 0); eq(after.frames, 0)
	eq(t.idle.Arena.Ticking(), false)
	local r = t.idle.ns.rdb.arena and t.idle.ns.rdb.arena.realms and t.idle.ns.rdb.arena.realms[t.idle.realm]
	eq(r and r.markets, nil); eq(r and r.tickets, nil); eq(r and r.bankEvents, nil)
	eq(t.idle.ns.rdb.arenaTest, nil)
	-- The bettor keeps his own event and tickets (he is involved).
	local mine = t.b1.ns.Arena.Store("L")
	eq(mine.markets[eid] ~= nil, true); eq(mine.tickets[N.bettor1] ~= nil, true)
	w:NoErrors()
end)

test("1.2 the markets: every button through Arena.Can/Do: 'bet' says why not (the rules, closed, the cap) and places the ticket; 'overrule' and 'closebets' for their roles", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	w:As(t.b1, function() t.b1.ns.Arena.SetRules(false) end)
	eq(select(2, t.b1.Arena.Can("bet", eid, 1, 1, 500)), "rules")
	w:As(t.b1, function() t.b1.ns.Arena.SetRules(true) end)
	eq(t.b1.Arena.Can("bet", eid, 1, 1, 500), true)
	local ok, tk = t.b1.Arena.Do("bet", eid, 1, 1, 500)
	eq(ok, true); eq(tk.eid, eid)
	w:Run(3)
	eq(select(2, t.b1.Arena.Can("bet", eid, 1, 1, 1600)), "cap")
	eq(select(2, t.b1.Arena.Can("overrule", eid, 1, "H")), "leader")
	eq(t.king.Arena.Can("overrule", eid, 1, "H"), true)
	eq(select(2, t.b1.Arena.Can("closebets", eid)), "sheet")
	eq(t.arbiter.Arena.Can("closebets", eid), true)
	w:Run(300)
	eq(select(2, t.b2.Arena.Can("bet", eid, 1, 2, 500)), "closed")
	w:NoErrors()
end)

test("1.2 the markets: every word of the markets exists in English and pt-BR, the same keys; every word the code says is defined", function()
	local function Read(path)
		local f = assert(io.open(path, "rb"))
		local s = f:read("*a")
		f:close()
		return s
	end
	local src = Read(H.ADDON_DIR .. "Locales/ArenaMarketsText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	local en, pt = {}, {}
	for k in head:gmatch("\nL%.([%w_]+) =") do en[k] = true end
	for k in tail:gmatch("\n\tL%.([%w_]+) =") do pt[k] = true end
	for k in pairs(en) do assert(pt[k], "pt-BR lacks " .. k) end
	for k in pairs(pt) do assert(en[k], "English lacks " .. k) end
	local used = {}
	for _, f in ipairs({ "Markets.lua", "MarketBank.lua" }) do
		for k in Read(H.ADDON_DIR .. f):gmatch("L%.(MARKETS_[%w_]*%w)") do used[k] = true end
	end
	for typ in pairs(H.ns.Markets and H.ns.Markets.KINDS or {}) do used["MARKETS_KIND_" .. typ] = true end
	for _, why in ipairs({ "OFF", "RULES", "NETOFF", "UNKNOWN", "DIRECT", "TRIAL", "CLOSED", "BANK", "REALM", "OUTCOME", "MIN", "ONE", "CONFLICT", "CAP", "RATE", "CODE", "LEADER", "SHEET" }) do
		used["MARKETS_WHY_" .. why] = true
	end
	for code in ("UCOMRWENDAXPF"):gmatch(".") do used["MARKETS_CODE_" .. code] = true end
	for code in ("EWGI1STNZXL"):gmatch(".") do used["MARKETS_VOID_" .. code] = true end
	for i = 1, 5 do used["MARKETS_STAGE_" .. i] = true end
	for k in pairs(used) do assert(en[k], "not defined: " .. k) end
end)

print("Markets: the auditors' check, the fee's word, direct stakes, the screens' events")

test("1.2 the markets: auditors hold a market whose ledger has more than its locked book (a bet at or after lockAt, or one the pools hide), and flag the late entry", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500))
	assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(301)
	-- A b entry the locked book never counted, dated after the lock (a modified bank's).
	w:Deliver(t.bank.name, 900, { k = "b", eid = eid, idx = 1, o = "1", copper = 200000, nonce = "zz9zz9", t = w.clock, who = N.bettor3 })
	local a = t.king.ns.Arena.Store("L").audit[eid]
	eq(a.late, 1); eq(a.flags[#a.flags].code, "late")
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(2)
	eq(Last(w, { from = t.auditor, type = "BV" }).msg:match("~(%a)~[^~]+$"), "H", "the signed auditor's client holds it")
	eq(Last(w, { from = t.hc, type = "BV" }).msg:match("~(%a)~[^~]+$"), "H", "a High Councillor's too")
	-- The King's own client shows it and holds nothing by itself (a hold of his only he could lift).
	eq(Last(w, { from = t.king, type = "BV" }), nil)
	eq(t.king.MB.AuditOf("L", eid).mismatch["1"].kind, "over")
	w:Run(301)
	eq(Bal(w, t, t.b1), 950000, "held: not paid")
	-- An auditor who heard the market from its registration and finds it right says nothing.
	local eid2 = PublicFight(w, t)
	assert(t.b1.M.Bet(eid2, 1, 1, 500))
	assert(t.b2.M.Bet(eid2, 1, 2, 500))
	w:Run(301)
	local before = Bal(w, t, t.b1)
	assert(t.arbiter.M.Declare(eid2, { winner = "A" }))
	w:Run(301)
	for _, s in ipairs(w:Sent{ type = "BV" }) do eq(s.msg:find(eid2, 1, true), nil, "no word on it") end
	eq(Bal(w, t, t.b1), before + 97000, "paid")
	w:NoErrors()
end)

test("1.2 the markets: the fee a sheet freezes: the King's word, or the one before it within 10 minutes of a change; a later rev keeps its own", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t, nil, { lockAt = w.clock + 3600 })
	assert(t.b1.M.Bet(eid, 1, 1, 500)); assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(30)
	assert(t.king.Roles.SetSettings({ feeBp = 500, arbBp = 200 }))
	w:Run(0)
	-- A sheet opened under the old word reaches the others after the change: still taken.
	local eid2 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	RawSheet(w, t.arbiter, ("%s~1~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O"):format(eid2, N.bank, B36(w.clock + 600)))
	eq(t.b1.M.Has(eid2), true)
	w:Run(601)
	local eid3 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	RawSheet(w, t.arbiter, ("%s~1~%s~g~b4.5k.a~%s~-~-~1:MW:-:2:O"):format(eid3, N.bank, B36(w.clock + 600)))
	eq(t.b1.M.Has(eid3), false, "ten minutes later: refused")
	-- The first sheet's later revs keep its 6%.
	assert(t.arbiter.M.CloseBets(eid))
	w:Run(0)
	eq(t.b3.M.Sheet(eid).rev, 2); eq(t.b3.M.Sheet(eid).fee.g, 400)
	local eid4 = w:Fight{ opener = t.arbiter, A = t.A, B = t.B }
	assert(t.arbiter.M.Open(eid4, { markets = { { type = "MW" } } }))
	w:Run(0)
	eq(t.b3.M.Sheet(eid4).fee.g, 300, "a new sheet: the new word (5%, 2% of it the arbiter's)")
	w:NoErrors()
end)

test("1.2 the markets: direct stakes (DR): a record between the two fighters, no bank, no slip", function()
	local w, t = MW.Standard()
	local eid = w:Fight{ opener = t.A, A = t.A, B = t.B, public = false }
	eq(t.A.M.Open(eid, { markets = { { type = "DR", param = { 500, 500 } } }, lockAt = w.clock + 60 }), true)
	w:Run(0)
	eq(t.B.M.Has(eid), true); eq(t.bank.M.Has(eid), false); eq(t.b1.M.Has(eid), false)
	eq(t.B.M.Sheet(eid).bank, nil)
	eq(select(2, t.B.M.CanBet(eid, 1, 2, 500)), "direct")
	w:Run(61)
	assert(t.A.M.Declare(eid, { winner = "B" }))
	w:Run(0)
	eq(t.B.M.Sheet(eid).markets[1].result, "2")
	eq(#w:Sent{ type = "BS" }, 0); eq(#w:Sent{ type = "BO" }, 0)
	w:NoErrors()
end)

test("1.2 the markets: the screens' events: MARKETS_OPEN once for a public sheet, MARKETS_CLOSING at the Bell, MARKETS_SETTLED at the payout", function()
	local w, t = MW.Standard()
	local seen = {}
	w:As(t.b3, function()
		for _, ev in ipairs({ "MARKETS_OPEN", "MARKETS_CLOSING", "MARKETS_SETTLED" }) do
			t.b3.ns.On(ev, function(eid) seen[#seen + 1] = ev .. " " .. eid end)
		end
	end)
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500)); assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(130)
	assert(t.arbiter.M.CloseBets(eid))
	w:Run(21)
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(320)
	eq(seen[1], "MARKETS_OPEN " .. eid); eq(seen[2], "MARKETS_CLOSING " .. eid); eq(seen[3], "MARKETS_SETTLED " .. eid)
	eq(#seen, 3)
	w:NoErrors()
end)

test("1.2 the markets: a wallet that does not pay never shows a market settled: it holds, and a leader's P tries again", function()
	local w, t = MW.Standard()
	local eid = PublicFight(w, t)
	assert(t.b1.M.Bet(eid, 1, 1, 500)); assert(t.b2.M.Bet(eid, 1, 2, 500))
	w:Run(300)
	local settle = t.bank.ns.Wallet.Settle
	t.bank.ns.Wallet.Settle = function() return false, "busy" end
	assert(t.arbiter.M.Declare(eid, { winner = "A" }))
	w:Run(316)
	eq(Bal(w, t, t.b1), 950000)
	eq(t.b3.M.View(eid).markets[1].state, "H")
	eq(t.bank.MB.View("L")[1].markets[1].hold, "wallet")
	t.bank.ns.Wallet.Settle = settle
	assert(t.king.M.Overrule(eid, 1, "P"))
	w:Run(2)
	eq(Bal(w, t, t.b1), 950000 + 97000)
	w:NoErrors()
end)

test("1.2 the markets: the bank under a crowd, at the game's pace (one message every 1.2 s): its Comm queue stays within the urgent share, one book of an event waits at a time, and every slip is answered or taken", function()
	local names = { "Aven Holt", "Bram Oake", "Cyra Lent", "Doran Fell", "Edda Morn", "Finn Rowe", "Gale Birch", "Hana Voss", "Ivo Crane", "Jory Pike",
		"Kesh Ward", "Lorn Tace", "Mael Drew", "Nessa Quill", "Orin Vale", "Pell Ashe", "Quin Dorr", "Rhea Linn", "Sorn Kade", "Tova Reed" }
	local extra = {}
	for i, n in ipairs(names) do extra[i] = { "c" .. i, n } end
	local w, t = MW.Standard({ paced = true, extra = extra })
	for i = 1, #names do
		w:Key(t["c" .. i])
		w:Deposit(t.bank, t["c" .. i], 150000)
	end
	local eid = PublicFight(w, t, nil, { lockAt = w.clock + 400 })
	w:Run(3)
	local worst = 0
	local tickets = {}
	for i = 1, #names do
		local c = t["c" .. i]
		-- Half of them over their wallet (a refusal whispered back), half taken.
		tickets[i] = assert(c.M.Bet(eid, 1, i % 2 + 1, i % 2 == 0 and 2000 or 1000))
	end
	for _ = 1, 120 do
		w:Run(1)
		local q, books = t.bank.comm.queue, 0
		for _, item in ipairs(q) do if item.msg:sub(1, 2) == "BO" then books = books + 1 end end
		if #q > worst then worst = #q end
		eq(books <= 1, true, "one book of the event waits at most")
	end
	eq(worst <= t.bank.ns.Arena.URGENT_SHARE + 2, true, "the bank's queue at most " .. worst)
	for i, tk in ipairs(tickets) do
		if i % 2 == 0 then
			eq(tk.state, "refused", names[i]); eq(tk.code, "F")
		else
			eq(tk.state, "accepted", names[i])
		end
	end
	w:NoErrors()
end)
