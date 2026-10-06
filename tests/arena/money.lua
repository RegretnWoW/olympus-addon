-- 1.2, the money part (money): the watcher and the fills (ArenaMoney.lua), the bank's ledger and the player's
-- wallet (Wallet.lua), debts, receipts and standing (Debts.lua), the arbiter's stakes and direct
-- mode (Stakes.lua), and the treasury's and the dues' changes. On the test world, each client its
-- own; every money figure below is worked out by hand, never by the function under test. Every
-- name is invented (World.NAMES).
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES
local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
local NoErrors = M.NoErrors

local G, S = 10000, 100 -- a gold, a silver, in copper

local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end
local function Count(list, fn)
	local n = 0
	for _, v in ipairs(list) do if fn(v) then n = n + 1 end end
	return n
end

print("ArenaMoney: the watcher, the fills, the subjects")

test("1.2 the money part: the subjects: written and read back; TEST anywhere after the kind; a deposit; a player's own subject is none", function()
	local w = World.New()
	local a = M.Client(w, "Lida Fenn")
	local Mn = a.Money
	eq(Mn.Subject("fee", "B1-2k"), "Arena fee B1-2k")
	eq(Mn.Subject("fee", "B1-2k", true), "Arena fee TEST B1-2k")
	eq(Mn.Subject("wallet", "3k9w 1f"), "Arena wallet 3k9w 1f")
	eq(Mn.Subject("deposit"), "Arena wallet deposit"); eq(Mn.Subject("deposit", nil, true), "Arena wallet deposit TEST")
	local k, ref, t = Mn.ReadSubject("Arena fee B1-2k")
	eq(k, "fee"); eq(ref, "B1-2k"); eq(t, false)
	k, ref, t = Mn.ReadSubject("Arena fee TEST A7x")
	eq(k, "fee"); eq(ref, "A7x"); eq(t, true)
	k, ref = Mn.ReadSubject("Arena wallet 3k9w 1f")
	eq(k, "wallet"); eq(ref, "3k9w 1f")
	k, ref, t = Mn.ReadSubject("Arena wallet deposit TEST")
	eq(k, "deposit"); eq(ref, nil); eq(t, true)
	for _, kind in ipairs({ "payout", "refund", "stake", "remit" }) do eq((Mn.ReadSubject("Arena " .. kind .. " F1")), kind) end
	eq(Mn.ReadSubject("For the treasury"), nil); eq(Mn.ReadSubject("Olympus arena fee x"), nil); eq(Mn.ReadSubject("Arena dues"), nil)
	eq(Mn.ReadSubject(nil), nil)
	NoErrors(w)
end)

test("1.2 the money part: the watcher is installed only when something is expected (the weight rule), and counts a trade at ERR_TRADE_COMPLETE only", function()
	local w = World.New()
	local a, b = M.Client(w, "Lida Fenn", { money = 90000 }), M.Client(w, "Parric Stowe", { money = 90000 })
	local seen = {}
	w:As(a, function() a.ns.ArenaMoney.Subscribe(function(r) seen[#seen + 1] = r end) end)
	w:Trade(a, b, { aGives = 5000 })
	eq(#seen, 0, "nothing expected: nothing watched")
	eq(a.Money.Installed(), false)
	eq(table.concat(w:ArenaWeight(a).events, ","), "GOSSIP_SHOW,PLAYER_LOGOUT", "only keeper gossip and the logout sentinel")
	eq(#w:ArenaWeight(a).events, 2)
	a.Money.Expect("x", { partner = b.name, dir = "out", copper = 7000 })
	eq(a.Money.Installed(), true)
	-- A trade closed without completing moves nothing.
	w:Trade(a, b, { aGives = 7000, complete = false })
	eq(#seen, 0, "never completed")
	w:Trade(a, b, { aGives = 7000, bGives = 1000, bItems = { { name = "Linen Cloth", count = 2 } } })
	eq(#seen, 1)
	local r = seen[1]
	eq(r.kind, "trade"); eq(r.partner, b.name); eq(r.gave, 7000); eq(r.got, 1000); eq(r.out, true); eq(r.copper, 6000, "netted")
	eq(r.guid, b.guid, "the partner's GUID from the unit"); eq(r.level, 60); eq(r.guild, World.GUILD); eq(r.items.got, 1)
	eq(#r.keys, 0, "6000 is not the 7000 expected")
	-- Forgotten: the handlers return at once.
	a.Money.Forget("x")
	w:Trade(a, b, { aGives = 100 })
	eq(#seen, 1)
	NoErrors(w)
end)

test("1.2 the money part: a mail taken counts once the inbox shows it taken (never on the money alone); cash on delivery and the game's mail are no flow; a returned mail says so", function()
	local w = World.New()
	local bank, d = M.Client(w, "Coffrey Vault"), M.Client(w, "Wenna Crale", { money = 90000 })
	local seen = {}
	w:As(bank, function() bank.ns.ArenaMoney.Subscribe(function(r) seen[#seen + 1] = r end) end)
	bank.Money.Expect("bank", { dir = "both" })
	w:Mail(d, bank, 20000, "Arena wallet deposit")
	eq(#seen, 0, "arrived is not taken")
	w:Take(bank, 1)
	eq(#seen, 1); eq(seen[1].kind, "mailTaken"); eq(seen[1].partner, d.name); eq(seen[1].got, 20000); eq(seen[1].subject, "Arena wallet deposit")
	eq(bank.Money.TakePending(), false)
	-- A take the inbox never confirms (the server refused it): nothing, and it is dropped after 30 s.
	w:Mail(d, bank, 3000, "x")
	w:As(bank, function() TakeInboxMoney(2) end)
	eq(bank.Money.TakePending(), true, "one take waits")
	eq(#seen, 1)
	w:Run(31)
	eq(bank.Money.TakePending(), false)
	-- Cash on delivery: no flow.
	w:Mail(d, bank, 5000, "Wares", 100)
	local n = #bank.inbox
	w:Take(bank, n)
	eq(#seen, 1, "COD is a sale")
	-- The bank's own mail: sent (counted at MAIL_SEND_SUCCESS), then back: returned.
	w:Mail(bank, d, 4000, "Arena wallet 1a 2")
	eq(#seen, 2); eq(seen[2].kind, "mailSent"); eq(seen[2].gave, 4000); eq(seen[2].subject, "Arena wallet 1a 2"); eq(seen[2].out, true)
	w:Return(d, #d.inbox)
	w:Take(bank, #bank.inbox)
	eq(#seen, 3); eq(seen[3].kind, "mailReturned"); eq(seen[3].got, 4000)
	NoErrors(w)
end)

test("1.2 the money part: the fills: a mail filled (recipient, subject, gold), the trade's gold read back ('said' when the game ignored it), the gamepad UI touches nothing, combat and a pending take wait", function()
	local w = World.New()
	local a, b = M.Client(w, "Lida Fenn", { money = 90000 }), M.Client(w, "Parric Stowe")
	local Mn = a.Money
	eq(Mn.FillMail(b.name, "Arena fee B1-3", 400), "closed", "no mailbox open")
	assert(Printed(a, "At a mailbox"), "says what to send")
	a.globals.SendMailFrame:Show()
	eq(Mn.FillMail(b.name, "Arena fee B1-3", 400), "filled")
	eq(a.globals.SendMailNameEditBox.text, "Parric Stowe"); eq(a.globals.SendMailSubjectEditBox.text, "Arena fee B1-3"); eq(a.globals.SendMailMoney.copper, 400)
	-- The trade: filled when the window shows the gold, "said" when the game ignored the call.
	a.trade = { with = b, gave = 0, got = 0 }
	a.globals.TradeFrame:Show()
	eq(Mn.FillTrade(5000), "filled"); eq(a.trade.gave, 5000)
	a.trade.gave = 0
	a.tradeIgnored = true
	eq(Mn.FillTrade(5000), "said", "unchanged: said"); eq(a.trade.gave, 0)
	assert(Printed(a, "Type 50s in the trade window"), "the amount to type (5,000 copper: 50 s)")
	-- A fill bound to its intended recipient never writes into another player's open trade.
	a.tradeIgnored = nil
	eq(Mn.FillTrade(5000, "Wenna Crale-Emberfall"), "partner")
	eq(a.trade.gave, 0, "the wrong partner's trade is untouched")
	a.tradeIgnored, a.trade = nil, nil
	-- Combat.
	a.combat = true
	eq(Mn.FillMail(b.name, "x", 1), "combat"); eq(Mn.FillTrade(1), "combat")
	a.combat = nil
	-- The gamepad UI: printed, nothing written.
	local calls = #a.win.calls
	H.WithGamepadUI(true, function()
		eq(w:As(a, a.ns.ArenaMoney.FillMail, b.name, "Arena fee B1-4", 700), "gamepad")
		eq(w:As(a, a.ns.ArenaMoney.FillTrade, 700), "gamepad")
	end)
	eq(#a.win.calls, calls, "the game's windows untouched")
	assert(Printed(a, "Mail 7s to Parric Stowe"), "says what to send")
	-- A take pending: the fills wait for it.
	a.Money.Expect("y", { dir = "in" })
	w:Mail(b, a, 100, "z")
	w:As(a, function() TakeInboxMoney(1) end)
	eq(Mn.FillMail(b.name, "x", 1), "wait")
	NoErrors(w)
end)

test("1.2 the money part: Money.Flow answers a keeper's line: the arena's only when one of his own open obligations expects that partner, direction and amount", function()
	local w = World.New()
	local a = M.Client(w, "Lida Fenn")
	local Mn = a.Money
	eq(Mn.Flow(N.bank, true, { copper = 5000 }), nil)
	Mn.Expect("dep:1", { partner = N.bank, dir = "out", copper = 5000 })
	eq(Mn.Flow(N.bank, true, { copper = 5000 }), true)
	eq(select(2, Mn.Flow(N.bank, true, { copper = 5000 })), "arena")
	eq(Mn.Flow(N.bank, true, { copper = 5001 }), nil, "another amount")
	eq(Mn.Flow(N.bank, false, { copper = 5000 }), nil, "the other way")
	eq(Mn.Flow(N.bettor2, true, { copper = 5000 }), nil, "someone else")
	Mn.Expect("fees", { dir = "in", subjectPrefix = "Arena fee" })
	eq(Mn.Flow(N.bettor2, false, { copper = 900, note = "Arena fee B1-2" }), nil, "a subject-only watch is nobody's obligation")
	Mn.Expect("partner-only", { partner = N.bettor2, dir = "in" })
	eq(Mn.Flow(N.bettor2, false, { copper = 900 }), nil, "a partner-only watch hides no amount")
	Mn.Expect("several", { partner = N.bettor2, dir = "in", amounts = { [700] = true, [900] = true } })
	eq(Mn.Flow(N.bettor2, false, { copper = 700 }), true)
	eq(Mn.Flow(N.bettor2, false, { copper = 900 }), true)
	eq(Mn.Flow(N.bettor2, false, { copper = 800 }), nil, "only a listed amount")
	NoErrors(w)
end)

test("1.2 the money part: two identical mailbox takes confirm one at a time", function()
	local w = World.New()
	local bank, sender = M.Client(w, "Coffrey Vault"), M.Client(w, "Wenna Crale", { money = 90000 })
	local seen = {}
	w:As(bank, function() bank.ns.ArenaMoney.Subscribe(function(r) seen[#seen + 1] = r end) end)
	bank.Money.Expect("bank", { dir = "in", copper = 2000 })
	w:Mail(sender, bank, 2000, "Arena wallet deposit")
	w:Mail(sender, bank, 2000, "Arena wallet deposit")
	w:As(bank, function() TakeInboxMoney(1) TakeInboxMoney(2) end)
	bank.inbox[1].money = 0
	w:Fire(bank, "PLAYER_MONEY"); w:Fire(bank, "MAIL_INBOX_UPDATE")
	eq(#seen, 1, "one vanished mail confirms one take")
	bank.inbox[2].money = 0
	w:Fire(bank, "PLAYER_MONEY"); w:Fire(bank, "MAIL_INBOX_UPDATE")
	eq(#seen, 2, "the second take waits for the second mail")
	NoErrors(w)
end)

test("1.2 the money part: a full copper-rehearsal record blocks fills before any gold is written", function()
	local w = World.New()
	local a, b = M.Client(w, "Lida Fenn"), M.Client(w, "Parric Stowe")
	a.ns.ArenaTest.Running = function() return { rid = 7, lane = "army", money = "p" } end
	a.db.arenaCopper = {}
	for i = 1, a.Money.COPPER_MAX do a.db.arenaCopper[i] = { id = i } end
	a.trade = { with = b, gave = 0, got = 0 }
	a.globals.TradeFrame:Show()
	local calls = #a.win.calls
	eq(a.Money.FillTrade(5000, b.name), "copperfull")
	eq(a.trade.gave, 0); eq(#a.win.calls, calls, "no trade write")
	a.globals.SendMailFrame:Show()
	eq(a.Money.FillMail(b.name, "Arena wallet deposit TEST", 5000), "copperfull")
	eq(#a.win.calls, calls, "no mail write")
	NoErrors(w)
end)

print("Wallet: the bank's duty and deposits")

test("1.2 Wallet: a deposit receiver is an online, open, persistent designated character; assignments rotate by pending work and track assigned/received counts", function()
	local w = World.New()
	local a = M.Client(w, "Lida Fenn")
	local banks = {
		{ name = N.bank, state = "o", online = true, persists = true },
		{ name = N.treasurerMail, state = "o", online = true, persists = true },
		{ name = N.feeReceiver, state = "o", online = false, persists = true },
		{ name = N.auditor, state = "o", online = true, persists = true, full = true },
	}
	local receipts = {
		{ bank = N.bank, state = "credited" }, { bank = N.bank, state = "sent" },
		{ bank = N.treasurerMail, state = "credited" },
	}
	local pick, rows = a.Wallet.RecipientPlan(banks, receipts)
	eq(pick, N.treasurerMail, "the receiver with no pending assignment")
	local by = {}; for _, row in ipairs(rows) do by[row.name] = row end
	eq(by[N.bank].assigned, 2); eq(by[N.bank].received, 1); eq(by[N.bank].pendingCount, 1)
	eq(by[N.treasurerMail].assigned, 1); eq(by[N.treasurerMail].received, 1); eq(by[N.treasurerMail].pendingCount, 0)
	eq(by[N.feeReceiver].eligible, false, "offline")
	eq(by[N.auditor].eligible, false, "full")
	eq(banks[1].assigned, nil, "the caller's rows are not changed")
	receipts[#receipts + 1] = { bank = N.treasurerMail, state = "mail" }
	pick = a.Wallet.RecipientPlan(banks, receipts)
	eq(pick, N.bank, "equal loads have a deterministic full-name tie break")
	banks[1].trading, banks[2].paused = true, true
	eq(a.Wallet.RecipientPlan(banks, receipts), nil, "a busy receiver is not assigned more work")
	eq(select(2, a.Wallet.DepositRecipient("L")), "live", "the planner never enables real gold")
	NoErrors(w)
end)

test("1.2 Wallet: the main Treasury page uses the real ledger, recommends the designated receiver, and copies its exact full name", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { N.bettor2 } })
	local a = cast[N.bettor2]
	w:As(a, function()
		local view = a.ns.Wallet.View("L")
		eq(view.recommended, N.bank)
		eq(view.live, true); eq(view.rehearsal, false)
		local copied, selected = nil, nil
		local wasUI = a.ns.UI
		-- This test intercepts navigation and copy; it does not need another test to build UI.lua.
		a.ns.UI = { ShowCopy = function(_, text) copied = text end, SelectTab = function(key) selected = key end }
		a.ns.Treasury.OpenMoney()
		eq(a.ns.Treasury.mode, "wallet"); eq(selected, "treasury")
		local lines = a.ns.Treasury.Build()
		local recipient, scope
		for _, line in ipairs(lines) do
			if line.key == "wallet-recipient:" .. N.bank then recipient = line end
			if line.key == "wallet-scope" then scope = line end
		end
		assert(scope and scope.text:find(a.ns.L.MONEY_WALLET_SCOPE, 1, true), "the game wallet is explicitly separate from Treasury money")
		assert(recipient and recipient.onClick, "the designated receiver is actionable")
		recipient.onClick()
		eq(copied, N.bank, "the copy box receives the exact full character name")
		a.ns.UI = wasUI
	end)
	NoErrors(w)
end)

test("1.2 the money part: the bank's duty: listed, its yes on the privacy page, its account clean, the live switch on, and gold only where saved data survives", function()
	local w = World.New()
	local king = M.Role(w, "king")
	local bank = M.Role(w, "bank", { money = 100000 })
	eq(select(2, bank.Wallet.Duty(true, "L")), "unlisted")
	M.GoLive(w, king, nil, { N.bank })
	eq(select(2, bank.Wallet.Duty(true, "L")), "persist", "a first login: saved data not proven")
	M.Relog(w, bank)
	eq(select(2, bank.Wallet.Duty(true, "L")), "consent")
	local item
	w:As(bank, function() for _, it in ipairs(bank.ns.Consent.Items()) do if it.key == "arenabank" then item = it end end end)
	assert(item, "the bank's line on the privacy page")
	w:As(bank, item.set, true)
	eq(bank.Wallet.Duty(true, "L"), true)
	eq(bank.Wallet.OnDuty(), "L"); eq(bank.Arena.OnDuty("bank"), true)
	w:Run(0)
	local zh = w:Sent{ from = bank, type = "ZH" }
	eq(#zh, 1); eq(zh[1].dist, "CHANNEL")
	local ep, seq, _, head, state, _, fp, flags = zh[1].msg:match("^ZH~L1~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)$")
	eq(ep, bank.Wallet.BankStore().epoch); eq(ep, bank.Arena.B36(w.clock), "its epoch: the server's second (unique after a wipe)")
	eq(seq, "1", "the float's entry"); eq(#head, 16); eq(state, "o"); eq(flags, "s", "persists; nothing owed")
	eq(fp, select(3, bank.Debts.MyKey()), "its key's fingerprint")
	w:Run(2)
	local zeText = w:ChannelText()
	-- (The float: 100,000 copper is "255s" in base 36.)
	assert(zeText:find("ZE~L1~" .. ep .. "~1~o:255s:s~", 1, true), "the float on the channel, on the low lane: " .. zeText)
	-- Off: its duty ends, nothing more.
	bank.Wallet.Duty(false)
	eq(bank.Arena.OnDuty("bank"), false)
	-- A bank the King's word leaves out: refused.
	local other = M.Client(w, "Lida Fenn")
	eq(select(2, other.Wallet.Duty(true, "L")), "unlisted")
	NoErrors(w)
end)

test("1.2 the money part: a deposit by trade: the queue, the call, credited at ERR_TRADE_COMPLETE, the GUID bound from the trade, the statement and the receipt", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local r = lida.Wallet.Deposit(N.bank, "t", 15 * G)
	assert(r, "asked")
	w:Run(0)
	local zd = w:Sent{ from = lida, type = "ZD" }
	eq(#zd, 1); eq(zd[1].dist, "WHISPER"); eq(zd[1].target, N.bank)
	eq(#w:Sent{ from = lida, type = "ZT" }, 1, "the key claim with it")
	eq(lida.Wallet.Receipts()[1].state, "queued"); eq(lida.Wallet.Receipts()[1].place, 1)
	eq(#bank.Wallet.Console().queue, 1)
	bank.Wallet.CallNext()
	w:Run(0)
	eq(lida.Wallet.Receipts()[1].state, "called")
	assert(Printed(lida, "The bank is ready"), "told")
	-- The deposit fill carries its assigned bank into ArenaMoney's partner guard.
	local wrong = M.Client(w, "Wenna Crale")
	lida.trade = { with = wrong, gave = 0, got = 0 }
	lida.globals.TradeFrame:Show()
	eq(lida.Wallet.FillDeposit(r.id), "partner")
	eq(lida.trade.gave, 0, "another player's trade is untouched")
	lida.trade = nil
	lida.globals.TradeFrame:Hide()
	w:Trade(lida, bank, { aGives = 15 * G })
	w:Run(5)
	eq(lida.Wallet.Receipts()[1].state, "credited")
	local st = lida.Wallet.Statement(N.bank)
	eq(st.g.bal, 15 * G); eq(st.g.escrow, 0); eq(st.g.reserved, 0)
	assert(st.code, "its code (ZC)")
	local acct = bank.Wallet.Account(lida.name)
	local facts = bank.Wallet.Facts(acct)
	eq(facts.bound, true, "bound from the trade's unit"); eq(facts.gk, lida.Arena.GK(lida.guid)); eq(facts.frozen, false)
	eq(bank.Wallet.Available(acct), 15 * G)
	eq(#bank.Wallet.Console().queue, 0, "served")
	-- The ledger: a d under a blinded code; nobody's name on the channel.
	local d = M.Entries(bank)[2]
	-- (150,000 copper is "37qo" in base 36.)
	assert(d:find("^d:[0-9a-z]+:37qo:t$"), d)
	assert(not w:ChannelText():find("Lida", 1, true), "no name on the channel")
	NoErrors(w)
end)

test("1.2 the money part: a deposit by mail: credited when the bank takes it, never when it is sent; a mail from a client that never spoke is his, frozen for bets until it does", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	local r = lida.Wallet.Deposit(N.bank, "m", 12 * G)
	w:Run(0)
	eq(lida.Wallet.Receipts()[1].state, "queued", "the bank said yes")
	lida.globals.SendMailFrame:Show()
	eq(lida.Wallet.FillDeposit(r.id), "filled")
	eq(lida.globals.SendMailSubjectEditBox.text, "Arena wallet deposit")
	w:Mail(lida, bank, 12 * G, "Arena wallet deposit")
	eq(lida.Wallet.Receipts()[1].state, "mail", "in the mail")
	eq(bank.Wallet.Available(bank.Wallet.Account(lida.name) or "?"), 0, "not credited on send")
	w:Run(1)
	w:Take(bank, 1)
	w:Run(5)
	eq(lida.Wallet.Receipts()[1].state, "credited")
	eq(lida.Wallet.Statement(N.bank).g.bal, 12 * G)
	local facts = bank.Wallet.Facts(bank.Wallet.Account(lida.name))
	eq(facts.frozen, false)
	eq(facts.bound, true, "bound from his verified claim (the game's lookup of his GUID)")
	-- Parric mails gold without his client ever speaking to the bank: his, frozen for bets.
	w:Mail(parric, bank, 3 * G, "for Coffrey")
	w:Take(bank, 2)
	local pf = bank.Wallet.Facts(bank.Wallet.Account(parric.name))
	eq(bank.Wallet.Available(bank.Wallet.Account(parric.name)), 3 * G, "credited: his")
	eq(pf.frozen, true)
	NoErrors(w)
end)

test("1.2 the money part: the bank's checks: refused before the gold lands (below the level, net-off, the bank's cap, the day's); landed anyway, credited but frozen and listed to give back", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" }, settings = { minLevel = 20 } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local low = M.Client(w, "Wenna Crale", { level = 12, money = 90000 })
	M.Relog(w, low)
	w:Run(301) -- (a late login: the King's words and the bank's head come again)
	eq(low.Wallet.Deposit(N.bank, "t", 5 * G) ~= nil, true)
	w:Run(0)
	local rec = low.Wallet.Receipts()[1]
	eq(rec.state, "refused"); eq(rec.why, "lvl")
	assert(Printed(low, "below the level"), "told why")
	-- Over the day's deposits (tier 0: 25 g a day).
	lida.Wallet.Deposit(N.bank, "t", 26 * G)
	w:Run(0)
	eq(lida.Wallet.Receipts()[1].why, "day")
	-- He trades anyway: his gold, credited, frozen, and on the give-back list.
	w:Trade(lida, bank, { aGives = 26 * G })
	w:Run(5)
	local facts = bank.Wallet.Facts(bank.Wallet.Account(lida.name))
	eq(facts.frozen, true)
	eq(bank.Wallet.Available(bank.Wallet.Account(lida.name)), 26 * G)
	local gb = bank.Wallet.Console().giveBack
	eq(#gb, 1); eq(gb[1].copper, 26 * G); eq(gb[1].why, "day")
	-- The give-back is a normal withdrawal: queued (q), paid by the operator.
	eq(type(bank.Wallet.GiveBack(lida.name:lower())), "number")
	eq(#bank.Wallet.Console().withdrawals.queue, 1)
	NoErrors(w)
end)

test("1.2 the money part: gold from the bank's own characters is its float (o), never a wallet; items are never credited", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local alt = M.Client(w, "Coffrey Vaultson", { money = 90000 })
	bank.db.myCharacters[alt.name:lower()] = true
	w:Trade(alt, bank, { aGives = 4 * G })
	w:Run(5)
	eq(bank.Wallet.Account(alt.name), nil, "no wallet")
	eq(bank.Wallet.Liabilities().float, 100000 + 4 * G, "the float: its gold at the start and its own character's")
	-- Items in a trade: the operator is told to give them back; no credit.
	w:Trade(lida, bank, { aItems = { { name = "Linen Cloth", count = 5 } } })
	eq(#bank.Wallet.Console().items, 1)
	assert(Printed(bank, "never credits items"), "told")
	eq(bank.Wallet.Account(lida.name), nil)
	NoErrors(w)
end)

print("Wallet: bets, settlement, withdrawals, fees, points")

-- A deposit by trade, served at once: the bank calls, the player trades.
-- (One deposit ask per bank every 10 s, the design: a second in a row waits that out first.)
local function Fund(w, cast, c, copper)
	local r, why = c.Wallet.Deposit(N.bank, "t", copper)
	if why == "rate" then
		w:Run(c.ns.Wallet.ASK_GAP)
		r = c.Wallet.Deposit(N.bank, "t", copper)
	end
	assert(r, why)
	w:Run(0)
	cast.bank.Wallet.CallNext()
	w:Run(0)
	w:Trade(c, cast.bank, { aGives = copper })
	w:Run(5)
	return r
end

test("1.2 the money part: settlement from the ledger, to the copper: 10 g on each side (the arbiter's 2% his, the guild's 4% owed), the King judging (all 6% the guild's), and an uneven pool (the rounding the guild's)", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" } })
	local bank, lida, parric, wenna = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"]
	for _, c in ipairs({ lida, parric, wenna }) do Fund(w, cast, c, 25 * G) end
	local W = bank.Wallet
	local la, pa, wa = W.Account(lida.name), W.Account(parric.name), W.Account(wenna.name)
	eq(W.Available(la), 250000); eq(W.Available(pa), 250000); eq(W.Available(wa), 250000)
	local closes = w.clock + 600
	-- 10 g on A (Lida), 10 g on B (Parric), A wins; the arbiter is paid his part.
	assert(W.Register("F1a", 1, { nsel = 2, closes = closes, cur = "g", arbiter = N.arbiter }))
	assert(W.Hold(la, 10 * G, { eid = "F1a", idx = 1, o = "A", nonce = "n1" }))
	assert(W.Hold(pa, 10 * G, { eid = "F1a", idx = 1, o = "B", nonce = "n2" }))
	eq(W.Available(la), 150000, "held")
	W.Settle("F1a", 1, "A")
	-- Lida: 150,000 + 194,000 (her 10 g and the other 10 g less 6%); the guild 4,000; the arbiter 2,000.
	eq(W.Available(la), 344000); eq(W.Available(pa), 150000)
	eq(W.Owed(), 4000)
	local arb = W.Account(N.arbiter)
	eq(W.Available(arb), 2000)
	-- The same with the King judging: he holds no gold, all 6% goes to the guild.
	assert(W.Register("F2a", 1, { nsel = 2, closes = closes, cur = "g", to = "g" }))
	W.Hold(la, 10 * G, { eid = "F2a", idx = 1, o = "A", nonce = "n3" })
	W.Hold(pa, 10 * G, { eid = "F2a", idx = 1, o = "B", nonce = "n4" })
	W.Settle("F2a", 1, "A")
	eq(W.Available(la), 438000); eq(W.Available(pa), 50000)
	eq(W.Owed(), 10000, "4,000 + 6,000"); eq(W.Available(arb), 2000, "nothing to the arbiter")
	-- Uneven: Lida 3 g and Parric 4 g on A, Wenna 10 g on B; A wins. The money won is 100,000:
	-- the fee 6,000 (arbiter 2,000), 94,000 shared: Lida 30,000 + floor(94,000 x 3/7) = 70,285,
	-- Parric 40,000 + floor(94,000 x 4/7) = 93,714; the guild 4,000 and the copper left, 4,001.
	assert(W.Register("F3a", 1, { nsel = 2, closes = closes, cur = "g", arbiter = N.arbiter }))
	local s1 = W.Hold(la, 3 * G, { eid = "F3a", idx = 1, o = "A", nonce = "n5" })
	local s2, i2 = W.Hold(pa, 4 * G, { eid = "F3a", idx = 1, o = "A", nonce = "n6" })
	eq(s1, s2, "one grouped entry (one market, outcome and second)"); eq(i2, 2)
	W.Hold(wa, 10 * G, { eid = "F3a", idx = 1, o = "B", nonce = "n7" })
	W.Settle("F3a", 1, "A")
	eq(W.Available(la), 408000 + 70285); eq(W.Available(pa), 10000 + 93714); eq(W.Available(wa), 150000)
	eq(W.Owed(), 10000 + 4001); eq(W.Available(arb), 4000)
	-- The ledger's own grouped entry, and in equals out over the entries written.
	local grouped
	for _, e in ipairs(M.Entries(bank)) do if e:find("^BF3a%.1%.A%.") then grouped = e end end
	assert(grouped, "the grouped entry")
	local _, commas = grouped:gsub(",", "")
	eq(commas, 1, "two bets in it")
	w:Run(10)
	local rep = cast.auditor.Wallet.Replica(N.bank)
	eq(rep.matches, true, "the replica's head is the bank's")
	local byName = {}
	for _, a in ipairs(rep.accounts) do if a.name then byName[a.name] = a end end
	eq(byName[lida.name].g.bal, 478285); eq(byName[parric.name].g.bal, 103714); eq(byName[N.arbiter].g.bal, 4000)
	eq(rep.owed, 14001)
	NoErrors(w)
end)

test("1.2 the money part: Hold: the same nonce and tuple again holds nothing twice; another tuple under it is refused (U); funds, a closed market, a late one, whole silver", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	Fund(w, cast, lida, 20 * G)
	local W = bank.Wallet
	local la = W.Account(lida.name)
	assert(W.Register("F7a", 2, { nsel = 2, closes = w.clock + 100, cur = "g" }))
	local seq, i = W.Hold(la, 5 * G, { eid = "F7a", idx = 2, o = "A", nonce = "abc123" })
	assert(seq)
	local seq2, i2 = W.Hold(la, 5 * G, { eid = "F7a", idx = 2, o = "A", nonce = "abc123" })
	eq(seq2, seq); eq(i2, i); eq(W.Available(la), 15 * G, "held once")
	eq(select(2, W.Hold(la, 6 * G, { eid = "F7a", idx = 2, o = "A", nonce = "abc123" })), "U")
	eq(select(2, W.Hold(la, 5 * G, { eid = "F7a", idx = 2, o = "B", nonce = "abc123" })), "U")
	eq(select(2, W.Hold(la, 30 * G, { eid = "F7a", idx = 2, o = "A", nonce = "zz1" })), "funds")
	eq(select(2, W.Hold(la, 5050, { eid = "F7a", idx = 2, o = "A", nonce = "zz2" })), "silver")
	eq(select(2, W.Hold(la, 1 * G, { eid = "F9x", idx = 1, o = "A", nonce = "zz3" })), "market")
	W.Close("F7a", 2)
	eq(select(2, W.Hold(la, 1 * G, { eid = "F7a", idx = 2, o = "A", nonce = "zz4" })), "closed")
	assert(W.Register("F8a", 1, { nsel = 2, closes = w.clock + 5, cur = "g" }))
	w:Run(6)
	eq(select(2, W.Hold(la, 1 * G, { eid = "F8a", idx = 1, o = "A", nonce = "zz5" })), "late", "the bank's own clock")
	-- The bettor's client hears his acceptance (Wallet.Listen, OnEntry): the full tuple.
	local heard = {}
	lida.Wallet.Listen("tickets", true)
	w:As(lida, function() lida.ns.Wallet.OnEntry(function(b, s, e) if e.k == "b" then heard[#heard + 1] = e end end) end)
	assert(W.Register("F9a", 1, { nsel = 2, closes = w.clock + 100, cur = "g" }))
	W.Hold(la, 2 * G, { eid = "F9a", idx = 1, o = "B", nonce = "k9k9k9" })
	w:Run(5)
	eq(#heard, 1); eq(heard[1].eid, "F9a"); eq(heard[1].idx, 1); eq(heard[1].o, "B"); eq(heard[1].s, 2 * G); eq(heard[1].nonce, "k9k9k9")
	eq(heard[1].code, nil, "the code stays blinded for him")
	NoErrors(w)
end)

test("1.2 the money part: a withdrawal: q reserves; Pay next sends the W intent before it fills; w at the send, c once he took it; a returned one is re-credited, never a deposit", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	Fund(w, cast, lida, 20 * G)
	local W = bank.Wallet
	local la = W.Account(lida.name)
	assert(lida.Wallet.Withdraw(N.bank, 5 * G))
	w:Run(0)
	local it = lida.Wallet.View().intents[1]
	eq(it.state, "queued"); assert(it.qseq)
	eq(W.Available(la), 15 * G, "reserved")
	bank.globals.SendMailFrame:Show()
	local sentBefore = #w:Sent{ from = bank, type = "ZE" }
	local pay = W.PayNext()
	eq(pay.fill, "filled"); eq(pay.copper, 5 * G)
	eq(bank.globals.SendMailMoney.copper, 5 * G - World.POSTAGE, "the postage from the withdrawal")
	eq(bank.globals.SendMailSubjectEditBox.text, pay.subject)
	-- (50,000 copper is "12kw" in base 36.) Out before the mail is sent: queued urgently at the fill.
	w:Run(0)
	eq(#lida.inbox, 0, "no mail yet")
	local ze = w:Sent{ from = bank, type = "ZE" }
	assert(#ze > sentBefore and ze[#ze].msg:find("W:[0-9a-z]+:12kw:" .. bank.Arena.B36(it.qseq)), "the W went out before the fill")
	w:Mail(bank, lida, 5 * G - World.POSTAGE, pay.subject)
	local b = bank.Wallet.BankStore()
	assert(b.entries[b.seq]:find("^w:[0-9a-z]+:12kw:u:m:"), "w: 50,000 gross (12kw), 30 postage (u): " .. b.entries[b.seq])
	w:Take(lida, #lida.inbox)
	w:Run(5)
	eq(lida.Wallet.View().intents[1].state, "taken")
	assert(b.entries[b.seq]:find("^c:"), "confirmed: " .. b.entries[b.seq])
	-- A second one comes back: re-credited what came back (the postage is spent), never a deposit.
	-- (Asked 10 s after the first at least: one withdrawal ask per 10 s, the design.)
	w:Run(5)
	assert(lida.Wallet.Withdraw(N.bank, 2 * G))
	w:Run(0)
	local pay2 = W.PayNext()
	w:Mail(bank, lida, 2 * G - World.POSTAGE, pay2.subject)
	w:Return(lida, #lida.inbox)
	w:Take(bank, #bank.inbox)
	eq(W.Available(la), 15 * G - World.POSTAGE)
	assert(b.entries[b.seq]:find("^r:"), "r: " .. b.entries[b.seq])
	local d = Count(M.Entries(bank), function(e) return e:find("^d:") ~= nil end)
	eq(d, 1, "the one deposit")
	NoErrors(w)
end)

test("1.2 the money part: the guild's fee: exactly what is owed mailed to the fee receiver (postage on top, from the float); the treasury counts it in the balance, never a gift or dues; its receipt (ZF) clears the bank's fee by ref; a 1.1 client still reads the book", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric, fee = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast.fee
	Fund(w, cast, lida, 20 * G); Fund(w, cast, parric, 20 * G)
	local W = bank.Wallet
	assert(W.Register("F1a", 1, { nsel = 2, closes = w.clock + 600, cur = "g", arbiter = N.arbiter }))
	W.Hold(W.Account(lida.name), 10 * G, { eid = "F1a", idx = 1, o = "A", nonce = "n1" })
	W.Hold(W.Account(parric.name), 10 * G, { eid = "F1a", idx = 1, o = "B", nonce = "n2" })
	W.Settle("F1a", 1, "A")
	eq(W.Owed(), 4000)
	local open = bank.Debts.Open()
	eq(#open, 1); eq(open[1].kind, "f"); eq(open[1].copper, 4000)
	assert(open[1].due - w.clock <= 72 * 3600 and open[1].due - w.clock > 71 * 3600, "due 72 h after the settlement")
	bank.globals.SendMailFrame:Show()
	local pay = W.PayGuild()
	eq(pay.to, N.treasurerMail, "the fee receiver: the Treasurer's mail character"); eq(pay.copper, 4000)
	eq(bank.globals.SendMailMoney.copper, 4000, "exactly what is owed")
	assert(pay.subject:find("^Arena fee B" .. bank.Wallet.BankStore().epoch .. "%-[0-9a-z]+$"), pay.subject)
	local float = W.Liabilities().float
	w:Mail(bank, fee, 4000, pay.subject)
	eq(W.Owed(), 0); eq(W.Liabilities().float, float - World.POSTAGE, "the postage from the float")
	eq(bank.Debts.Open()[1].state, "m", "sent, awaiting receipt: the clock stopped")
	w:Take(fee, #fee.inbox)
	w:Run(5)
	local book = w:As(fee, fee.ns.Treasury.Book)
	local line = book.lines[#book.lines]
	eq(line.kind, "fee"); eq(line.excluded, nil); eq(line.money, 4000)
	local sums = w:As(fee, fee.ns.Treasury.SumsOf, book)
	eq(sums.allIn, 4000, "in the balance"); eq(sums.byDonor[line.name], nil, "never a gift")
	eq(next(sums.weeks or {}), nil, "never dues")
	eq(#bank.Debts.Open(), 0, "cleared by its ref")
	eq(#w:Sent{ from = fee, type = "ZF", to = N.bank }, 1)
	-- Its book as the channel carries it: no fee line, and a 1.1 client's reader takes it.
	local msg = w:As(fee, fee.ns.Treasury.Message, book)
	assert(not msg:find("Coffrey", 1, true), "never a line")
	w:As(lida, lida.ns.Treasury.HandleReport, "CHANNEL", fee.name, msg)
	eq(type(lida.rdb.treasuryReports[fee.name]), "table", "read")
	NoErrors(w)
end)

test("1.2 the money part: the fee waits for a receiver running 1.2: none heard in 7 days, the fill says so and the fee is owed without turning late", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 20 * G); Fund(w, cast, parric, 20 * G)
	local W = bank.Wallet
	W.Register("F1a", 1, { nsel = 2, closes = w.clock + 600, cur = "g" })
	W.Hold(W.Account(lida.name), 10 * G, { eid = "F1a", idx = 1, o = "A", nonce = "n1" })
	W.Hold(W.Account(parric.name), 10 * G, { eid = "F1a", idx = 1, o = "B", nonce = "n2" })
	W.Settle("F1a", 1, "B")
	-- (The fee receiver's client logs out: no hello for 8 days.)
	w:Logout(cast.fee)
	w:Run(8 * 86400)
	eq(W.ReceiverUpdated(), false, "its hello is 8 days old")
	eq(select(2, W.PayGuild()), "updated")
	assert(Printed(bank, "receiver not updated"))
	eq(bank.Debts.Open()[1].state, "open", "past its 72 h, not late: the receiver never heard")
	NoErrors(w)
end)

test("1.2 the money part: glory points and gold apart: 1,000 points a week in the points balance only, no fee on a points market; after a switch to gold, ZW all returns exactly the gold deposited", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" }, settings = { cur = "p" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	local W = bank.Wallet
	eq(select(2, lida.Wallet.Deposit(N.bank, "t", 5 * G)), "cur", "no gold in points")
	local la, pa = W.Account(lida.name, true), W.Account(parric.name, true)
	assert(W.Register("F5a", 1, { nsel = 2, closes = w.clock + 600, cur = "p" }))
	assert(W.Hold(la, 300 * 100, { eid = "F5a", idx = 1, o = "A", nonce = "p1" }))
	assert(W.Hold(pa, 200 * 100, { eid = "F5a", idx = 1, o = "B", nonce = "p2" }))
	eq(W.Available(la, "p"), 100000 - 30000, "the week's 1,000 points, less the stake")
	W.Settle("F5a", 1, "A")
	eq(W.Available(la, "p"), 100000 + 20000, "the whole of the other side: points pay no fee")
	eq(W.Owed(), 0)
	-- The grant once a week.
	assert(W.Register("F5b", 1, { nsel = 2, closes = w.clock + 600, cur = "p" }))
	W.Hold(la, 100, { eid = "F5b", idx = 1, o = "A", nonce = "p3" })
	eq(W.Available(la, "p"), 120000 - 100)
	-- The King switches to gold: points are never turned into gold.
	M.GoLive(w, cast.king, { cur = "g" })
	w:Run(1)
	Fund(w, cast, lida, 5 * G)
	eq(W.Available(la, "g"), 5 * G)
	lida.Wallet.Withdraw(N.bank, "all")
	w:Run(0)
	local it = lida.Wallet.View().intents[1]
	eq(it.state, "queued")
	local b = bank.Wallet.BankStore()
	eq(b.st.wd[it.qseq].copper, 5 * G, "exactly the gold deposited")
	eq(W.Available(la, "p"), 120000 - 100, "the points untouched")
	NoErrors(w)
end)

print("Wallet: replication, recovery, reconciliation")

test("1.2 the money part: the auditors' replica: balances rebuilt from the channel's entries (unblinded with the bank's key), its hash chain reaching the head in ZH; no bettor's name on the channel, one account's entries unlinkable; ZE only from the bank itself", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric, aud = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast.auditor
	Fund(w, cast, lida, 10 * G); Fund(w, cast, lida, 12 * G); Fund(w, cast, parric, 5 * G)
	w:Run(70)
	local rep = aud.Wallet.Replica(N.bank)
	local b = bank.Wallet.BankStore()
	eq(rep.seq, b.seq); eq(rep.matches, true, "its head is the ZH's"); eq(rep.kb, true)
	local byName = {}
	for _, a in ipairs(rep.accounts) do if a.name then byName[a.name] = a end end
	eq(byName[lida.name].g.bal, 22 * G); eq(byName[parric.name].g.bal, 5 * G)
	eq(rep.liabilities.g, 27 * G)
	-- Lida's two deposits carry two different codes on the channel.
	local codes = {}
	for _, e in ipairs(M.Entries(bank)) do
		local c = e:match("^d:([0-9a-z]+):")
		if c then codes[#codes + 1] = c end
	end
	eq(#codes, 3); assert(codes[1] ~= codes[2] and codes[1] ~= codes[3] and codes[2] ~= codes[3], "blinded per entry")
	local text = w:ChannelText()
	for _, n in ipairs({ "Lida", "Parric" }) do assert(not text:find(n, 1, true), "a bettor's name on the channel: " .. n) end
	-- A ledger from anyone but the bank is no ledger; a non-auditor keeps no replica.
	w:As(aud, function() aud.ns.Arena.Inject("CHANNEL", lida.name, ("ZE~L1~%s~%s~d:abc:1:t~0"):format(rep.epoch, aud.Arena.B36(rep.seq + 1))) end)
	eq(aud.Wallet.Replica(N.bank).seq, rep.seq)
	eq(lida.Wallet.Replica(N.bank), nil)
	-- A bet written at or after its market's lock is flagged (the design: late bets are visible).
	local ep, seq = rep.epoch, rep.seq
	local inject = ("ZE~L1~%s~%s~n:F4a.1:2:%s:gm:5k:p:g:a;BF4a.1.A.%s:1a.a.zzzzzz~0"):format(ep, aud.Arena.B36(seq + 1), aud.Arena.B36(w.clock + 10),
		aud.Arena.B36(w.clock + 10))
	w:As(aud, function() aud.ns.Arena.Inject("CHANNEL", N.bank, inject) end)
	local flags = aud.Wallet.Replica(N.bank).flags
	eq(Count(flags, function(f) return f.what == "late" end), 1)
	NoErrors(w)
end)

test("1.2 the money part: the crash drill: a bank that lost its unsaved ledger takes back from an auditor only entries whose MAC chains under its secret; a W with no w blocks that account's payouts until the operator says whether the mail went", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	Fund(w, cast, lida, 20 * G)
	lida.Wallet.Withdraw(N.bank, 5 * G)
	w:Run(5)
	local qseq = lida.Wallet.View().intents[1].qseq
	-- The last save: before Pay next.
	local saved = World.Copy(bank.db)
	local savedSeq = bank.Wallet.BankStore().seq
	bank.globals.SendMailFrame:Show()
	local pay = bank.Wallet.PayNext()
	w:Run(0)
	-- The chat lockdown holds its w back; the mail itself goes; then the game crashes.
	bank.lockdown = true
	w:Mail(bank, lida, 5 * G - World.POSTAGE, pay.subject)
	bank.lockdown = nil
	M.Crash(w, bank, saved)
	eq(bank.Wallet.BankStore().seq, savedSeq, "back to its last save")
	w:Run(10)
	local b = bank.Wallet.BankStore()
	eq(bank.Wallet.OnDuty(), "L", "its duty resumed")
	eq(b.seq, savedSeq + 1, "the W taken back from the auditor's copy")
	eq(b.st.wd[qseq].state, "W")
	local q = bank.Wallet.Console().withdrawals.queue
	eq(#q, 1); eq(q[1].blocked, true)
	eq(select(2, bank.Wallet.PayNext()), "empty", "no second payout")
	-- A forged chunk never checks: its MAC is the bank's secret's.
	local before = b.seq
	w:As(bank, function() bank.ns.Wallet.TakeReplay(b, N.auditor, b.epoch, b.seq + 1, "d:1a:2bi:t", "0") end)
	eq(b.seq, before)
	-- The operator: the mail went.
	eq(bank.Wallet.Reconcile(qseq, true), true)
	eq(b.st.wd[qseq].state, "w"); eq(bank.Wallet.Console().withdrawals.queue[1], nil)
	NoErrors(w)
end)

test("1.2 the money part: reconciliation: gold nothing explains is the reserve's surplus; a lost-receipt claim (ZL) is credited only from it and consumes it, so a second claim on the same gold is refused", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	Fund(w, cast, lida, 10 * G)
	w:Run(5) -- (one deposit ask per 10 s, the design)
	local r = assert(lida.Wallet.Deposit(N.bank, "t", 5 * G))
	w:Run(0)
	-- The bank off duty when the trade lands: nothing records it.
	bank.Wallet.Duty(false)
	w:Trade(lida, bank, { aGives = 5 * G })
	assert(bank.Wallet.Duty(true, "L"))
	w:Run(700)
	local rec = lida.Wallet.Receipts()[1]
	eq(rec.state, "sent"); eq(rec.claim, true, "10 minutes on: Tell the bank")
	eq(bank.Wallet.Reserve().unexplained, 5 * G)
	assert(lida.Wallet.Claim(N.bank, r.id))
	w:Run(0)
	local claims = bank.Wallet.Console().claims
	eq(#claims, 1); eq(claims[1].copper, 5 * G); eq(claims[1].name, lida.name)
	eq(bank.Wallet.Accept(claims[1].nonce), true)
	eq(bank.Wallet.Available(bank.Wallet.Account(lida.name)), 15 * G)
	eq(bank.Wallet.Reserve().unexplained, 0, "consumed")
	-- The same gold claimed again: refused.
	w:As(lida, function() lida.ns.Arena.Send("ZL", "L", ("%s~other1~t~%s~%s"):format(bank.Wallet.BankStore().epoch, lida.Arena.B36(5 * G), lida.Arena.B36(w.clock)), { to = N.bank }) end)
	w:Run(0)
	eq(select(2, bank.Wallet.Accept("other1")), "surplus")
	NoErrors(w)
end)

test("1.2 the money part: a leader's order (ZJ) waits for the operator's click; never from a sender whose key is the bank's own", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida, aud, king = cast.bank, cast["Lida Fenn"], cast.auditor, cast.king
	Fund(w, cast, lida, 10 * G)
	w:Run(70)
	local rep = aud.Wallet.Replica(N.bank)
	local code
	for _, a in ipairs(rep.accounts) do if a.name == lida.name then code = a.code end end
	assert(code)
	aud.Wallet.Order(N.bank, code, "+", 1 * G, "J", "fix")
	w:Run(0)
	local orders = bank.Wallet.Console().orders
	eq(#orders, 1); eq(orders[1].from, aud.name)
	eq(bank.Wallet.Available(bank.Wallet.Account(lida.name)), 10 * G, "not applied by itself")
	assert(bank.Wallet.ApplyOrder(orders[1].nonce))
	eq(bank.Wallet.Available(bank.Wallet.Account(lida.name)), 11 * G)
	-- The King's client with the bank's own account key: its order is refused.
	king.db.arenaKey = World.Copy(bank.db.arenaKey)
	king.Debts.SendClaim(N.bank)
	w:Run(0)
	eq(select(2, bank.Debts.Verified(king.name)), select(3, bank.Debts.MyKey()), "the same key")
	king.Wallet.Order(N.bank, code, "+", 5 * G, "J", "mine")
	w:Run(0)
	eq(#bank.Wallet.Console().orders, 1, "refused")
	NoErrors(w)
end)

test("1.2 the money part: an account opened by mail with no GUID bound can't bet or withdraw gold; a trade binds it", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Parric Stowe" } })
	local bank, parric = cast.bank, cast["Parric Stowe"]
	bank.infoOff = true -- (the game's lookup of his GUID answers nothing here)
	parric.Wallet.Deposit(N.bank, "m", 5 * G)
	w:Run(0)
	w:Mail(parric, bank, 5 * G, "Arena wallet deposit")
	w:Take(bank, 1)
	w:Run(5)
	local W = bank.Wallet
	local pa = W.Account(parric.name)
	eq(W.Available(pa), 5 * G); eq(W.Facts(pa).bound, false); eq(W.Facts(pa).frozen, false)
	assert(W.Register("F6a", 1, { nsel = 2, closes = w.clock + 600, cur = "g" }))
	eq(select(2, W.Hold(pa, 1 * G, { eid = "F6a", idx = 1, o = "A", nonce = "b1" })), "bound")
	parric.Wallet.Withdraw(N.bank, 1 * G)
	w:Run(0)
	eq(parric.Wallet.View().intents[1].why, "b")
	-- In person: the trade's unit binds it.
	w:Trade(parric, bank, { aGives = 1 * G })
	w:Run(5)
	eq(W.Facts(pa).bound, true)
	assert(W.Hold(pa, 1 * G, { eid = "F6a", idx = 1, o = "A", nonce = "b2" }))
	NoErrors(w)
end)

test("1.2 the money part: snapshots: a checkpoint's balances checked by two auditors from their own entries; the entries before it go only then", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	local aud2 = M.Role(w, "councillor2")
	M.Relog(w, aud2)
	w:Run(301) -- (a late login: the King's words come again, the bank among them)
	aud2.Wallet.Hello()
	w:Run(0)
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 7 * G)
	w:Run(70)
	eq(aud2.Wallet.Replica(N.bank).kb, true, "the second auditor has the key")
	local seq = assert(bank.Wallet.Checkpoint())
	local b = bank.Wallet.BankStore()
	w:Run(10)
	eq(cast.auditor.Wallet.Replica(N.bank).verified.ok, true); eq(aud2.Wallet.Replica(N.bank).verified.ok, true)
	-- (Two accounts: two v lines before the k; the prune keeps them, the snapshot's own.)
	eq(b.firstSeq, seq - 2, "pruned once both said so")
	eq(b.entries[seq - 3], nil); assert(b.entries[seq - 2]:find("^v:") and b.entries[seq]:find("^k:"), "the checkpoint kept")
	-- One auditor's check alone prunes nothing (the King's client is an auditor's too: gone as well).
	w:Logout(aud2)
	w:Logout(cast.king)
	Fund(w, cast, lida, 2 * G)
	w:Run(70)
	local seq2 = assert(bank.Wallet.Checkpoint())
	w:Run(10)
	eq(b.firstSeq, seq - 2, "not the second one's")
	NoErrors(w)
end)

test("1.2 the money part: a re-seat (the bank's saved data gone, no backup): balances only from two auditors' replicas that agree and reach the last ZH; a tampered one is refused, one alone is not enough", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	local aud2 = M.Role(w, "councillor2")
	M.Relog(w, aud2)
	w:Run(301) -- (a late login: the King's words come again, the bank among them)
	aud2.Wallet.Hello()
	w:Run(0)
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 7 * G)
	w:Run(70)
	local oldEp = bank.Wallet.BankStore().epoch
	local head = lida.Wallet.Banks()[1]
	-- Wiped: a new ledger on duty, then the ask.
	bank.db.realms[World.GROUP].arena.realms.Emberfall.bank = nil
	M.Relog(w, bank)
	w:Run(10)
	eq(bank.Wallet.OnDuty(), nil, "no ledger: no duty by itself")
	w:Run(1)
	assert(bank.Wallet.Duty(true, "L"))
	assert(bank.Wallet.ReseatAsk(oldEp))
	w:Run(10)
	-- One alone: not enough.
	eq(select(2, bank.Wallet.Reseat(cast.auditor.name, cast.auditor.name)), "second")
	-- A tampered copy: its head no longer reaches the last ZH.
	local got = bank.Wallet.BankStore().reseat.from
	local a1, a2 = got[cast.auditor.name:lower()], got[aud2.name:lower()]
	assert(a1 and a2, "both replicas came")
	local tampered = World.Copy(a2)
	for s, e in pairs(tampered.entries) do
		if e:find("^d:") then tampered.entries[s] = e:gsub(":([0-9a-z]+):t$", ":zzzz:t") break end
	end
	eq(select(2, bank.Wallet.Reseat(a1, tampered, a1.zh)), "second")
	eq(select(2, bank.Wallet.Reseat(tampered, a1, a1.zh)), "head")
	-- Both honest: the new epoch opens with each balance carried over by name.
	local ep = assert(bank.Wallet.Reseat(cast.auditor.name, aud2.name))
	assert(ep ~= oldEp)
	local W = bank.Wallet
	eq(W.Available(W.Account(lida.name)), 10 * G); eq(W.Available(W.Account(parric.name)), 7 * G)
	NoErrors(w)
end)

print("Debts: the account key, marks, direct mode, fees owed")

test("1.2 the money part: the account key's claim (ZT): verified from a unit or the game's lookup of the GUID, with its signature; one per peer and session; a claim copied from another character is refused", function()
	local w = World.New()
	local a, b, x = M.Client(w, "Lida Fenn"), M.Client(w, "Parric Stowe"), M.Client(w, "Wenna Crale")
	eq(b.Debts.SendClaim(a.name), true)
	w:Run(0)
	local gk, fp, how = a.Debts.Verified(b.name)
	eq(gk, a.Arena.GK(b.guid)); eq(fp, select(3, b.Debts.MyKey())); eq(how, "info")
	eq(b.Debts.SendClaim(a.name), false, "once per peer and session")
	-- The game's lookup answers nothing: kept pending until a unit shows him (the target).
	a.infoOff = true
	x.Debts.SendClaim(a.name)
	w:Run(0)
	eq(a.Debts.Verified(x.name), nil); eq(a.Debts.Pending(x.name), true)
	a.target = x.name
	eq(select(3, a.Debts.Verified(x.name)), "unit")
	a.target, a.infoOff = nil, nil
	-- Wenna sends Parric's claim as her own: its signature names Parric; refused.
	local c = M.Client(w, "Torvin Hale")
	local gkP, pkP, sigP = w:As(b, b.ns.Debts.ClaimParts)
	w:As(x, function() x.ns.Arena.Send("ZT", "L", ("%s~%s~%s~1o"):format(gkP, pkP, sigP), { to = c.name }) end)
	w:Run(0)
	eq(c.Debts.Verified(x.name), nil, "a copied claim")
	-- Nor can she sign Parric's GUID with her own key: the game says that GUID is Parric.
	local d = M.Client(w, "Selka Drummond")
	local k = x.db.arenaKey
	local seed, pk = x.ns.Ed25519.FromB64(k.seed), x.ns.Ed25519.FromB64(k.pk)
	local sig = x.ns.Ed25519.ToB64(x.ns.Ed25519.Sign(seed, "OLYA1|" .. b.guid .. "|" .. x.name, pk))
	w:As(x, function() x.ns.Arena.Send("ZT", "L", ("%s~%s~%s~1o"):format(x.Arena.GK(b.guid), k.pk, sig), { to = d.name }) end)
	w:Run(0)
	eq(d.Debts.Verified(x.name), nil, "never bound: that GUID is someone else's")
	NoErrors(w)
end)

test("1.2 the money part: debt marks (ZX): a debtor's own only from him; an auditor's only from an auditor; no amount ever; an open mark never lapses; a self mark naming another's GUID blocks by name alone", function()
	local w = World.New()
	local king = M.Role(w, "king")
	M.GoLive(w, king)
	local aud = M.Role(w, "auditor")
	local lida, parric, wenna = M.Client(w, "Lida Fenn"), M.Client(w, "Parric Stowe"), M.Client(w, "Wenna Crale")
	for _, c in ipairs({ aud, lida, parric, wenna }) do M.Relog(w, c) end
	w:Run(301) -- (logged in after the King's word: they hear it at its next repeat)
	-- Parric says Lida owes: a self mark from someone else is nothing.
	local body = ("id000001~o~-~%s~b~%s~-~s"):format(lida.name, wenna.Arena.B36(w.clock))
	w:As(wenna, function() wenna.ns.Arena.Inject("CHANNEL", parric.name, "ZX~L1~" .. body) end)
	eq(wenna.Debts.Mark(lida.name), nil)
	-- Lida's own obligation turns late: her own mark goes out, with no amount in it.
	assert(lida.Debts.Owe({ kind = "bet", creditor = parric.name, copper = 5 * G, ref = "DF9", due = w.clock + 10 }))
	w:Run(40)
	eq(wenna.Debts.Mark(lida.name), "open")
	local zx = w:Sent{ from = lida, type = "ZX" }
	eq(#zx, 1); eq(zx[1].dist, "CHANNEL")
	assert(not zx[1].msg:find(lida.Arena.B36(5 * G), 1, true), "no amount: " .. zx[1].msg)
	-- An auditor's mark: only from an auditor.
	local lbody = ("id000002~o~-~%s~b~%s~-~l"):format(wenna.name, wenna.Arena.B36(w.clock))
	w:As(lida, function() lida.ns.Arena.Inject("CHANNEL", parric.name, "ZX~L1~" .. lbody) end)
	eq(lida.Debts.Mark(wenna.name), nil, "Parric is no auditor")
	assert(aud.Debts.LeaderMark({ debtor = wenna.name, kind = "b", state = "o" }))
	w:Run(0)
	eq(lida.Debts.Mark(wenna.name), "open")
	-- Open marks never lapse.
	w:Run(40 * 86400)
	eq(parric.Debts.Mark(lida.name), "open"); eq(parric.Debts.Mark(wenna.name), "open")
	-- Nobody clears her own mark with another source's word ("c", a creditor's, is his own mark's only).
	local sid = zx[1].msg:match("^ZX~L1~([0-9a-z]+)~")
	local clear = ("%s~c~-~%s~b~%s~-~c"):format(sid, lida.name, wenna.Arena.B36(w.clock + 1))
	w:As(wenna, function() wenna.ns.Arena.Inject("CHANNEL", parric.name, "ZX~L1~" .. clear) end)
	eq(wenna.Debts.Mark(lida.name), "open", "a stranger's 'paid' clears nothing")
	-- Framing: Lida's own mark carrying Parric's GUID blocks by her name alone.
	local frame = ("id000003~l~%s~%s~b~%s~-~s"):format(lida.Arena.GK(parric.guid), lida.name, wenna.Arena.B36(w.clock))
	w:As(wenna, function() wenna.ns.Arena.Inject("CHANNEL", lida.name, "ZX~L1~" .. frame) end)
	eq((wenna.Debts.Blocked(parric.name, wenna.Arena.GK(parric.guid))), false, "Parric is not framed")
	eq((wenna.Debts.Blocked(lida.name)), true)
	NoErrors(w)
end)

test("1.2 the money part: a direct 1v1 whose loser does not pay: his IOU and signed result let the creditor mark him, any client checks it and blocks him and his key's alt; his links freeze; the winner owes the guild 6% only of what he received; the creditor's receipt clears it", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local torvin, selka, lida = M.Client(w, "Torvin Hale", { money = 100000 }), M.Client(w, "Selka Drummond"), M.Client(w, "Lida Fenn")
	for _, c in ipairs({ torvin, selka, lida }) do M.Relog(w, c) end
	w:Run(0)
	-- At contact they gave each other their keys (with the challenge, the fights part).
	torvin.Debts.SendClaim(selka.name); selka.Debts.SendClaim(torvin.name)
	w:Run(0)
	local tGk, sGk = torvin.Debts.MyKey(), selka.Debts.MyKey()
	eq(selka.Debts.Verified(torvin.name), tGk)
	-- The loser's IOU (a salted commitment: no amount readable) and his signed result.
	local iou = torvin.Debts.Iou("F1d", selka.name, 5 * G, "s4lt")
	eq(iou.payeeGk, sGk); eq(#iou.commit, 16)
	assert(not iou.text:find("50000", 1, true))
	eq(selka.Debts.CheckIou(iou.text, iou.sig, selka.Debts.KeyOf(torvin.name)), true)
	eq(selka.Debts.CheckIou(iou.text:gsub("F1d", "F2d"), iou.sig, selka.Debts.KeyOf(torvin.name)), false)
	local rsig = torvin.Debts.SignResult("F1d", 1, sGk, tGk)
	eq(selka.Debts.CheckResult("F1d", 1, sGk, tGk, rsig, selka.Debts.KeyOf(torvin.name)), true)
	assert(torvin.Stakes.Direct({ id = "F1d", loser = torvin.name, winner = selka.name, copper = 5 * G }))
	assert(selka.Stakes.Direct({ id = "F1d", loser = torvin.name, winner = selka.name, copper = 5 * G, iou = { commit = iou.commit, sig = iou.sig },
		result = { fid = "F1d", round = 1, sig = rsig } }))
	eq(select(2, torvin.Arena.SetOff(true)), "obligations", "the kill switch refused while he owes")
	eq(#selka.Debts.Open(), 0, "no fee yet: nothing received")
	-- His alt on the same account (the same key), and a link of his own.
	local alt = M.Client(w, "Torvin Halewood")
	alt.db.arenaKey = World.Copy(torvin.db.arenaKey)
	torvin.db.alts = { links = { [alt.name:lower()] = { name = alt.name, main = torvin.name, at = w.clock } } }
	-- He quits without paying.
	w:Logout(torvin)
	w:Run(700)
	eq(lida.Debts.Mark(torvin.name), "open", "the creditor's proof, checked by a third client")
	w:Run(5)
	eq(lida.Arena.Ticking(), false, "the proof checked: nothing kept going on her client")
	local zx = w:Sent{ from = selka, type = "EP" }
	assert(#zx > 0, "the proof in pieces")
	alt.Debts.SendClaim(lida.name)
	w:Run(0)
	eq(select(2, lida.Debts.Blocked(alt.name)), "key", "his alt on the same key")
	-- Back: late (halved standing), his link frozen.
	w:Login(torvin)
	w:Run(60)
	eq(torvin.Debts.Open()[1].state, "l")
	w:As(torvin, function() torvin.ns.Alts.Remove(alt.name) end)
	eq(type(torvin.db.alts.links[alt.name:lower()]), "table", "/oly alt remove keeps the link")
	-- He pays: the winner's receipt clears it; the winner now owes 6% of what he received.
	w:Trade(torvin, selka, { aGives = 5 * G })
	w:Run(5)
	eq(#torvin.Debts.Open(), 0, "cleared by the creditor's receipt")
	local fee = selka.Debts.Open()
	eq(#fee, 1); eq(fee[1].kind, "f"); eq(fee[1].copper, 3000, "6% of 50,000"); eq(fee[1].ref, "DF1d")
	eq(lida.Debts.Mark(torvin.name), nil, "the creditor cleared his mark")
	NoErrors(w)
end)

test("1.2 the money part: nothing hides an obligation: a debt mark still goes out with the arena off; a fee mailed stops its clock (m) and a returned one starts it again", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local lida, parric = M.Client(w, "Lida Fenn"), M.Client(w, "Parric Stowe")
	for _, c in ipairs({ lida, parric }) do M.Relog(w, c) end
	w:Run(0)
	assert(lida.Debts.Owe({ kind = "bet", creditor = parric.name, copper = 2 * G, ref = "DF3", due = w.clock + 10 }))
	lida.db.arenaOff = true -- (turned off before: SetOff itself is refused while she owes)
	w:Run(40)
	eq(#w:Sent{ from = lida, type = "ZX" }, 1, "her own mark goes all the same")
	eq(parric.Debts.Mark(lida.name), "open")
	lida.db.arenaOff = nil
	-- A direct winner's fee: mailed, the clock stops; returned, it runs again.
	local f = assert(parric.Debts.Owe({ kind = "fee", copper = 1200, ref = "DF3", due = w.clock + 100 }))
	parric.globals.SendMailFrame:Show()
	local pay = parric.Debts.PayFee(f.id)
	eq(pay.to, N.treasurerMail); eq(pay.copper, 1200); eq(pay.subject, "Arena fee DF3"); eq(pay.fill, "filled")
	w:Mail(parric, cast.fee, 1200, pay.subject)
	eq(parric.Debts.Find(f.id).state, "m")
	w:Run(200)
	eq(parric.Debts.Find(f.id).state, "m", "past due, not late: sent, awaiting receipt")
	w:Return(cast.fee, #cast.fee.inbox)
	w:Take(parric, #parric.inbox)
	eq(parric.Debts.Find(f.id).state, "open", "came back: owed again")
	w:Run(40)
	eq(parric.Debts.Find(f.id).state, "l")
	NoErrors(w)
end)

print("Standing: points, caps, the token")

test("1.2 the money part: standing: a settled stake earns a point only at a quarter of the tier's cap and the minimum; 3 a day; a late payment halves the points and a tier goes on probation 7 days", function()
	local w = World.New()
	local bank = M.Role(w, "bank")
	local S = bank.Standing
	local who = "Lida Fenn-Emberfall"
	eq(S.Earn(who, "wallet", nil, 1 * G), false, "tier 0's bet cap is 5 g: a quarter is 1 g 25 s")
	for _ = 1, 3 do eq(S.Earn(who, "wallet", nil, 2 * G), true) end
	eq(select(2, S.Earn(who, "wallet", nil, 2 * G)), "day")
	eq(S.Points(who), 3)
	w:Run(86400)
	S.Earn(who, "wallet", nil, 2 * G); S.Earn(who, "wallet", nil, 2 * G)
	eq(S.Points(who), 5)
	eq(S.Cap("bet", who), 10 * G, "tier 1: 10 g")
	eq(S.Cap("balance", who), 100 * G)
	eq(select(2, S.Earn(who, "wallet", nil, 2 * G)), "small", "tier 1: a quarter is 2 g 50 s")
	-- Direct: against a different key each, none of his own.
	eq(S.Earn(who, "direct", "k1", 3 * G), true); eq(select(2, S.Earn(who, "direct", "k1", 3 * G)), "peer")
	-- Late: halved, and a tier lower for 7 days.
	S.Late(who)
	eq(S.Points(who), 3)
	eq(S.Cap("bet", who), 5 * G, "tier 0 (on probation)")
	w:Run(7 * 86400 + 1)
	eq(S.Cap("bet", who), 5 * G, "3 points: tier 0 anyway")
	-- The arbiter's cap is the King's (T1~M), never points.
	eq(S.Cap("hold", who), 0)
	NoErrors(w)
end)

test("1.2 the money part: the standing token: the bank signs it for the account's key in its statement; another client checks it against the bank's fingerprint; an edited one is refused; a direct cap only from it", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 5 * G)
	local tok = lida.Standing.Token()
	assert(tok, "in the statement")
	eq(tok.tier, -1, "no history: no direct bets"); eq(tok.bank, N.bank)
	lida.Debts.SendClaim(parric.name)
	w:Run(0)
	local wire = lida.Standing.TokenWire()
	local t = parric.Standing.CheckWire(wire, lida.name)
	eq(t.tier, -1)
	eq(parric.Standing.Cap("direct", lida.name), 0)
	eq(select(2, parric.Standing.CheckWire(wire:gsub("%.x%.", ".5.", 1), lida.name)), "signature", "edited")
	-- Three points on the bank's record: tier 0, 1 g (twice the largest paid on time, 1 g before any).
	for _ = 1, 3 do bank.Standing.Earn(lida.name, "wallet", nil, 2 * G) end
	local b = bank.Wallet.BankStore()
	b.accounts[lida.name:lower()].token = nil
	lida.Wallet.AskStatement(N.bank)
	w:Run(5)
	eq(lida.Standing.Token().tier, 0)
	parric.Standing.CheckWire(lida.Standing.TokenWire(), lida.name)
	eq(parric.Standing.Cap("direct", lida.name), 1 * G)
	-- A restored "mine" never raises it: the backup drops its tokens.
	local mine = World.Copy(lida.rdb.arena.realms.Emberfall.mine[lida.name])
	local checked = w:As(lida, lida.ns.Debts.BackupChecks.mine, mine)
	for _, bk in pairs(checked.banks) do eq(bk.token, nil) end
	NoErrors(w)
end)

print("Stakes: the arbiter's book, availability, exposure")

test("1.2 the money part: an arbiter's stakes: refused for the King, past the T1~M cap, for a debtor and where saved data does not survive; the stake held, an over-stake owed back; the result pays 1 g 94 s, owes the guild 4 s, keeps 2 s; receipts give the auditors his exposure, and at his cap he shows busy", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local king, aud = cast.king, cast.auditor
	local arb = M.Role(w, "arbiter")
	local torvin, selka, lida = M.Client(w, "Torvin Hale", { money = 50000 }), M.Client(w, "Selka Drummond", { money = 50000 }), M.Client(w, "Lida Fenn")
	for _, c in ipairs({ arb, torvin, selka, lida }) do M.Relog(w, c) end
	assert(king.Roles.SetArbiters({ { name = N.arbiter, cap = 2 } }))
	w:Run(301) -- (logged in after the King's words: they hear them at their next repeat)
	aud.Wallet.Hello() -- (and the auditor's hello, every 15 minutes)
	w:Run(0)
	local function T(stake, arbiter)
		return { id = "F1s", kind = "fight", A = { name = torvin.name }, B = { name = selka.name }, stake = { A = stake, B = stake }, arbiter = arbiter or N.arbiter }
	end
	eq(select(2, arb.Stakes.Open(T(1 * G, N.king))), "king")
	eq(select(2, torvin.Stakes.Open(T(15000))), "cap", "3 g past his 2 g")
	local beta = M.Client(w, "Wenna Crale", { persists = false })
	eq(select(2, beta.Stakes.Open(T(1 * G))), "persist")
	eq(arb.Stakes.OnDuty(true), true)
	w:Run(0)
	local found = lida.Stakes.Search()
	eq(#found, 1); eq(found[1].name, N.arbiter); eq(found[1].free, true)
	for _, c in ipairs({ arb, torvin, selka }) do assert(c.Stakes.Open(T(1 * G))) end
	w:Trade(torvin, arb, { aGives = 1 * G })
	w:Trade(selka, arb, { aGives = 15000 })
	w:Run(5)
	local held = arb.Stakes.Held("F1s")
	eq(held.A, 1 * G); eq(held.B, 1 * G); eq(held.both, true)
	local change = arb.Debts.Open()
	eq(#change, 1); eq(change[1].kind, "n"); eq(change[1].copper, 5000); eq(change[1].creditor, selka.name)
	eq(aud.Stakes.ExposureOf(N.arbiter), 2 * G, "from the parties' receipts")
	eq(lida.Stakes.Search()[1].free, false, "busy: at his cap (the auditor's mark) and in a match")
	eq(lida.Debts.Busy(N.arbiter), true)
	local lines = arb.Stakes.Result("F1s", "A")
	eq(lines[1].kind, "payout"); eq(lines[1].copper, 19400); eq(lines[1].name, torvin.name)
	eq(lines[2].kind, "fee"); eq(lines[2].copper, 400)
	eq(lines[3].kind, "keep"); eq(lines[3].copper, 200)
	local owed = {}
	for _, o in ipairs(arb.Debts.Open()) do owed[o.kind] = o end
	eq(owed.p.copper, 19400); eq(owed.p.ref, "PF1s"); eq(owed.f.copper, 400); eq(owed.f.ref, "AF1s")
	assert(owed.f.due - w.clock > 47 * 3600, "the arbiter's fee: 48 h")
	-- The book to the auditors only (the low lane: one message a second, the details first).
	w:Run(20)
	-- (Over 255 bytes: in EP pieces, whispered.)
	eq(#w:Sent{ from = arb, type = "EP", to = aud.name } + #w:Sent{ from = arb, type = "ZA", to = aud.name } > 0, true)
	eq(#w:Sent{ from = arb, type = "EP", to = torvin.name } + #w:Sent{ from = arb, type = "ZA", to = torvin.name }, 0, "never to a fighter")
	local books = aud.Stakes.Books()
	eq(books[N.arbiter:lower()].header.kept, 200); eq(books[N.arbiter:lower()].header.accrued, 400)
	eq(torvin.Stakes.Books(), nil, "a fighter is no auditor")
	-- The payout by trade: the winner's receipt clears it; the auditors' exposure falls; free again.
	arb.trade = nil
	w:Trade(arb, torvin, { aGives = 19400 })
	w:Run(5)
	eq(owed.p.state, "c")
	eq(aud.Stakes.ExposureOf(N.arbiter), 0)
	eq(lida.Debts.Busy(N.arbiter), false)
	NoErrors(w)
end)

print("The treasury's and the dues' changes")

test("1.2 the money part: a keeper's arena money is his only when it is one of his open obligations for that amount: a keeper's 'Arena payout' to someone he owes nothing is recorded as always", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local keeper, lida = cast.fee, cast["Lida Fenn"]
	keeper.money = 100000
	-- Nothing owed: an ordinary payment of the treasury, counted.
	w:Mail(keeper, lida, 2000, "Arena payout F1")
	local book = w:As(keeper, keeper.ns.Treasury.Book)
	local e = book.lines[#book.lines]
	eq(e.out, true); eq(e.excluded, nil); eq(e.kind, nil)
	-- His own stake to an arbiter for an open match: his, excluded, and the auditors hear of it.
	keeper.Money.Expect("stake:F2", { partner = N.arbiter, dir = "out", copper = 3000 })
	local arb = M.Role(w, "arbiter")
	w:Trade(keeper, arb, { aGives = 3000 })
	e = book.lines[#book.lines]
	eq(e.excluded, true); eq(e.kind, "arena")
	eq(#w:Sent{ from = keeper, type = "ZR", to = cast.auditor.name } >= 1, true)
	-- A TEST-looking fee outside a copper rehearsal is ordinary treasury money: a forged subject
	-- cannot hide it. During a copper rehearsal, only a plausible test fee is excluded.
	w:Mail(lida, keeper, 700, "Arena fee TEST B1-1")
	w:Take(keeper, #keeper.inbox)
	e = book.lines[#book.lines]
	eq(e.kind, nil); eq(e.excluded, nil, "outside rehearsal: counted normally")
	keeper.ns.ArenaTest.Running = function() return { rid = 7, lane = "army", money = "p" } end
	w:Mail(lida, keeper, 700, "Arena fee TEST B1-2")
	w:Take(keeper, #keeper.inbox)
	e = book.lines[#book.lines]
	eq(e.kind, "fee"); eq(e.excluded, true, "plausible rehearsal fee")
	w:Mail(lida, keeper, keeper.Money.COPPER_FEE_MAX + 1, "Arena fee TEST B1-3")
	w:Take(keeper, #keeper.inbox)
	e = book.lines[#book.lines]
	eq(e.kind, nil); eq(e.excluded, nil, "an impossible rehearsal fee is counted normally")
	NoErrors(w)
end)

test("1.2 the money part: donors: a month's sums whatever the book keeps (600 lines), the dues taken off as the public ranking takes them (a donor who paid only dues never ranks), fees never; Dues.Backfill counts no fee", function()
	local w = World.New()
	local keeper = M.Role(w, "treasurerMail")
	w:Run(10)
	local T = keeper.ns.Treasury
	local function Gift(name, copper, note)
		w:As(keeper, T.Record, name, copper, "mail", nil, { note = note })
	end
	-- 600 lines this week: 590 members paying the dues (1 g, the amount), and three donors.
	local amount = keeper.ns.Dues.AMOUNT
	for i = 1, 590 do Gift(("Payer%d Dues-Emberfall"):format(i), amount) end
	Gift("Lida Fenn-Emberfall", 9 * G); Gift("Parric Stowe-Emberfall", 7 * G); Gift("Wenna Crale-Emberfall", 5 * G)
	Gift("Torvin Hale-Emberfall", 4 * G); Gift("Selka Drummond-Emberfall", 3 * G)
	Gift("Coffrey Vault-Emberfall", 4000, "Arena fee B1-9")
	Gift("Payer1 Dues-Emberfall", 0) -- (nothing)
	local book = w:As(keeper, T.Book)
	eq(#book.lines, 500, "the book keeps 500 lines")
	local month = {}
	for _, g in ipairs(w:As(keeper, T.DonationRecords)) do if g.window == "month" then month[g.name] = g.money end end
	-- The Treasurer's book: each giver's week counts above the dues' amount (1 g).
	eq(month["Lida Fenn"], 8 * G); eq(month["Parric Stowe"], 6 * G); eq(month["Wenna Crale"], 4 * G)
	eq(month["Payer1 Dues"], nil, "only dues: never ranks"); eq(month["Coffrey Vault"], nil, "a fee: never a gift")
	local s = w:As(keeper, T.SumsOf, book)
	eq(s.allIn, 590 * amount + 28 * G + 4000, "every line in the balance, the fee too")
	-- Dues.Backfill over fee lines counts none of them.
	local fresh = {}
	w:As(keeper, keeper.ns.Dues.Backfill, fresh, { { name = "Coffrey Vault", money = 4000, kind = "fee", t = w.clock }, { name = "Lida Fenn", money = 2000, kind = "arena", t = w.clock, excluded = nil } })
	eq(next(fresh.weeks), nil)
	NoErrors(w)
end)

print("The weight rule")

test("1.2 the money part: an idle client with the money's files loaded: no arena timer or frame, only keeper gossip and logout events, no rehearsal store, after login and an hour", function()
	local w = World.New()
	local a = M.Client(w, "Lida Fenn")
	M.Relog(w, a)
	w:Run(3600)
	local weight = w:ArenaWeight(a)
	eq(weight.timers, 0); eq(weight.frames, 0); eq(table.concat(weight.events, ","), "GOSSIP_SHOW,PLAYER_LOGOUT")
	eq(a.rdb.arenaTest, nil)
	eq(a.Money.Installed(), false)
	-- A role client is involved (the bank's duty), and stops when it ends.
	local king = M.Role(w, "king")
	local bank = M.Role(w, "bank")
	M.GoLive(w, king, nil, { N.bank })
	M.Relog(w, bank)
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "L"))
	eq(bank.Arena.Ticking(), true)
	bank.Wallet.Duty(false)
	w:Run(5)
	eq(bank.Arena.Ticking(), false)
	NoErrors(w)
end)

print("The review's other cases")

test("1.2 the money part: a snapshot rebuilds every balance after pruning: an auditor who joins later gets the kept entries from the checkpoint's v lines on, and its replica equals the bank's", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 7 * G)
	lida.Wallet.Withdraw(N.bank, 2 * G)
	w:Run(70)
	local seq = assert(bank.Wallet.Checkpoint())
	w:Run(10)
	local b = bank.Wallet.BankStore()
	assert(b.firstSeq < seq and b.firstSeq > 1, "pruned to the checkpoint's first v line: " .. b.firstSeq)
	-- A third auditor, later: his replica starts where the bank's entries do.
	local late = M.Role(w, "councillor")
	M.Relog(w, late)
	w:Run(301)
	late.Wallet.Hello()
	w:Run(5)
	Fund(w, cast, parric, 3 * G)
	w:Run(130)
	local rep = late.Wallet.Replica(N.bank)
	eq(rep.seq, b.seq); eq(rep.matches, true)
	local byName = {}
	for _, a in ipairs(rep.accounts) do if a.name then byName[a.name] = a end end
	eq(byName[lida.name].g.bal, 8 * G); eq(byName[lida.name].g.reserved, 2 * G); eq(byName[parric.name].g.bal, 10 * G)
	-- The request from before the snapshot, paid now, lands in the late replica too.
	bank.globals.SendMailFrame:Show()
	local pay = bank.Wallet.PayNext()
	w:Mail(bank, lida, 2 * G - World.POSTAGE, pay.subject)
	w:Run(10)
	rep = late.Wallet.Replica(N.bank)
	for _, a in ipairs(rep.accounts) do if a.name == lida.name then eq(a.g.reserved, 0) end end
	eq(Count(rep.flags, function(f) return true end), 0, "nothing flagged")
	NoErrors(w)
end)

test("1.2 the money part: a bracket pool (PK) and a two-winner market (RF) settle from the ledger to the copper, the same after the bank reloaded in the middle", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" } })
	local bank, lida, parric, wenna = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"]
	for _, c in ipairs({ lida, parric, wenna }) do Fund(w, cast, c, 10 * G) end
	local W = bank.Wallet
	local la, pa, wa = W.Account(lida.name), W.Account(parric.name), W.Account(wenna.name)
	-- PK: 8 slots (3 rounds, 7 picks, "00": every upper slot; "fe": every lower one), 1 g each.
	assert(W.Register("T1pk", 9, { nsel = 8, closes = w.clock + 900, cur = "g", to = "g" }))
	W.Hold(la, 1 * G, { eid = "T1pk", idx = 9, o = "p00", nonce = "pk1" })
	W.Hold(pa, 1 * G, { eid = "T1pk", idx = 9, o = "pfe", nonce = "pk2" })
	-- RF: outcomes 1-4, two reach the final; Lida 2 g on 1, Parric 2 g on 3, Wenna 1 g on 2.
	assert(W.Register("T1pk", 3, { nsel = 4, closes = w.clock + 900, cur = "g", to = "g" }))
	W.Hold(la, 2 * G, { eid = "T1pk", idx = 3, o = "1", nonce = "rf1" })
	W.Hold(pa, 2 * G, { eid = "T1pk", idx = 3, o = "3", nonce = "rf2" })
	W.Hold(wa, 1 * G, { eid = "T1pk", idx = 3, o = "2", nonce = "rf3" })
	-- The bank reloads in the middle of the tournament.
	M.Relog(w, bank)
	w:Run(10)
	eq(bank.Wallet.OnDuty(), "L")
	eq(#W.Bets("T1pk", 9), 2); eq(#W.Bets("T1pk", 3), 3)
	W.Settle("T1pk", 9, "P00")
	-- PK: the best score (Lida, every pick right) takes the pool less 6%: 10,000 + 9,400.
	eq(W.Available(la), 10 * G - 3 * G + 19400); eq(W.Available(pa), 10 * G - 3 * G)
	W.Settle("T1pk", 3, { "1", "2" })
	-- RF: the money won is Parric's 20,000: 1,200 the guild's, 18,800 split 9,400 to each winning
	-- outcome; Lida 20,000 + 9,400, Wenna 10,000 + 9,400.
	eq(W.Available(la), 7 * G + 19400 + 29400); eq(W.Available(wa), 9 * G + 19400); eq(W.Available(pa), 7 * G)
	eq(W.Owed(), 600 + 1200)
	-- Every auditor's replica gets the same.
	w:Run(10)
	local rep = cast.auditor.Wallet.Replica(N.bank)
	local byName = {}
	for _, a in ipairs(rep.accounts) do if a.name then byName[a.name] = a end end
	eq(byName[lida.name].g.bal, 7 * G + 19400 + 29400); eq(rep.owed, 1800); eq(rep.matches, true)
	NoErrors(w)
end)

test("1.2 the money part: an arbiter's void refunds every stake held (a refund debt, 24 h, at the event); items put in a stake's trade are owed back (72 h)", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local king = cast.king
	local arb = M.Role(w, "arbiter")
	local torvin, selka = M.Client(w, "Torvin Hale", { money = 50000 }), M.Client(w, "Selka Drummond", { money = 50000 })
	for _, c in ipairs({ arb, torvin, selka }) do M.Relog(w, c) end
	w:Run(301)
	local t = { id = "F2s", kind = "farkle", A = { name = torvin.name }, B = { name = selka.name }, stake = { A = 1 * G, B = 1 * G }, arbiter = N.arbiter }
	for _, c in ipairs({ arb, torvin, selka }) do assert(c.Stakes.Open(t)) end
	w:Trade(torvin, arb, { aGives = 1 * G, aItems = { { name = "Silk Cloth", count = 3 } } })
	-- Selka never pays in: the match voids.
	local lines = arb.Stakes.Result("F2s", "V")
	eq(#lines, 1); eq(lines[1].kind, "refund"); eq(lines[1].copper, 1 * G); eq(lines[1].name, torvin.name)
	local kinds = {}
	for _, o in ipairs(arb.Debts.Open()) do kinds[o.kind] = o end
	eq(kinds.r.copper, 1 * G); eq(kinds.r.creditor, torvin.name)
	assert(kinds.r.due - w.clock > 23 * 3600, "24 h")
	eq(kinds.i.creditor, torvin.name); assert(kinds.i.due - w.clock > 71 * 3600, "72 h")
	-- The refund by mail: its line fills with the arena's subject.
	arb.globals.SendMailFrame:Show()
	local l = arb.Stakes.Lines("F2s")[1]
	eq(l.subject, "Arena refund AF2s"); eq(w:As(arb, l.fill), "filled"); eq(arb.globals.SendMailMoney.copper, 1 * G)
	NoErrors(w)
end)

test("1.2 the money part: fees where there is no Treasurer: on the Horde a named receiver (feeTo) takes the fee's mail and his receipt clears the bank's fee by ref", function()
	local w = World.New()
	local H2 = { faction = "Horde", guild = World.KING_GUILD_HORDE }
	local king = M.Role(w, "kingHorde")
	local bank = M.Role(w, "bank", H2)
	local fee = M.Role(w, "feeReceiver", H2)
	local lida, parric = M.Client(w, "Lida Fenn", { faction = "Horde", guild = World.KING_GUILD_HORDE, money = 500000 }),
		M.Client(w, "Parric Stowe", { faction = "Horde", guild = World.KING_GUILD_HORDE, money = 500000 })
	eq(select(2, king.Roles.SetSettings({ live = 1 })), "receiver", "gold with nobody to take the fees: refused")
	M.GoLive(w, king, { feeTo = N.feeReceiver }, { N.bank })
	for _, c in ipairs({ bank, fee, lida, parric }) do M.Relog(w, c) end
	w:Run(0)
	eq(fee.Roles.IsFeeReceiver(fee.name), true)
	fee.Wallet.Hello()
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "L"))
	w:Run(0)
	local cast = { bank = bank }
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	local W = bank.Wallet
	W.Register("F1h", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" })
	W.Hold(W.Account(lida.name), 5 * G, { eid = "F1h", idx = 1, o = "A", nonce = "h1" })
	W.Hold(W.Account(parric.name), 5 * G, { eid = "F1h", idx = 1, o = "B", nonce = "h2" })
	W.Settle("F1h", 1, "B")
	eq(W.Owed(), 3000)
	bank.globals.SendMailFrame:Show()
	local pay = W.PayGuild()
	eq(pay.to, N.feeReceiver)
	w:Mail(bank, fee, 3000, pay.subject)
	w:Take(fee, #fee.inbox)
	w:Run(5)
	eq(#w:Sent{ from = fee, type = "ZF", to = N.bank }, 1)
	eq(#bank.Debts.Open(), 0, "cleared through its ZF")
	NoErrors(w)
end)

test("1.2 the money part: a returned fee mail restores what is owed (G) and its clock, never a deposit; gold out that matches nothing is u", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric, fee = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast.fee
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	local W = bank.Wallet
	W.Register("F1r", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" })
	W.Hold(W.Account(lida.name), 5 * G, { eid = "F1r", idx = 1, o = "A", nonce = "r1" })
	W.Hold(W.Account(parric.name), 5 * G, { eid = "F1r", idx = 1, o = "B", nonce = "r2" })
	W.Settle("F1r", 1, "A")
	bank.globals.SendMailFrame:Show()
	local pay = W.PayGuild()
	w:Mail(bank, fee, 3000, pay.subject)
	eq(W.Owed(), 0)
	w:Return(fee, #fee.inbox)
	w:Take(bank, #bank.inbox)
	eq(W.Owed(), 3000, "owed again")
	eq(bank.Debts.Open()[1].state, "open")
	local b = W.BankStore()
	assert(b.entries[b.seq]:find("^G:2bc:"), "G: " .. b.entries[b.seq])
	eq(Count(M.Entries(bank), function(e) return e:find("^d:") ~= nil end), 2, "the two deposits only")
	-- Gold the bank mails that matches nothing: u, shown to the auditors.
	w:Mail(bank, lida, 700, "hello")
	assert(b.entries[b.seq]:find("^u:jg:o:m$"), b.entries[b.seq])
	NoErrors(w)
end)

test("1.2 the money part: the reserve attestation: an auditor reads the bank's gold in a trade window and the trade is cancelled; nothing moves", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, aud = cast.bank, cast.auditor
	w:Run(70)
	assert(aud.Wallet.Attest(N.bank))
	local money = bank.money
	w:Trade(aud, bank, { bGives = 12345, complete = false })
	local rep = aud.Wallet.Replica(N.bank)
	eq(rep.attest.copper, 12345)
	eq(bank.money, money, "nothing moved")
	NoErrors(w)
end)

test("1.2 the money part: a copper rehearsal writes every gold movement in the account's db.arenaCopper (1 g a deposit at most); chips in a rehearsal pay no fee; nothing reaches the live store", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" }, duty = false })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	local copper = true
	for _, c in ipairs(w.clients) do
		c.ns.ArenaTest.Running = function() return { rid = 7, lane = "army", money = copper and "p" or "c" } end
		-- The full rehearsal implementation grants chips only to participants. This focused wallet
		-- fixture replaces Running(), so it must provide the matching participation answer too.
		c.ns.ArenaTest.Participant = function() return true end
		c.ns.ArenaRoles.standIn = function(name, letter, mode) return mode == "T" and letter == "b" and name:lower() == N.bank:lower() end
		c.ns.ArenaRoles.standIns = function(letter) return letter == "b" and { N.bank } or {} end
		w:As(c, function() c.ns.Arena.Store("T") end)
	end
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "T"))
	w:Run(0)
	eq(select(2, lida.Wallet.Deposit(N.bank, "t", 2 * G, "T")), "cap", "1 g a deposit at most")
	assert(lida.Wallet.Deposit(N.bank, "t", 50 * S, "T"))
	w:Run(0)
	bank.Wallet.CallNext()
	w:Run(0)
	w:Trade(lida, bank, { aGives = 50 * S })
	w:Run(5)
	eq(lida.Wallet.Statement(N.bank, "T").g.bal, 50 * S)
	local function Lines(c)
		local out = {}
		for _, l in pairs(c.db.arenaCopper or {}) do out[#out + 1] = l end
		return out
	end
	local ll, bl = Lines(lida), Lines(bank)
	eq(#ll, 1); eq(ll[1].dir, "out"); eq(ll[1].copper, 5000); eq(ll[1].to, N.bank); eq(ll[1].rid, 7); eq(ll[1].state, "open"); eq(ll[1].how, "t")
	eq(#bl, 1); eq(bl[1].dir, "in"); eq(bl[1].from, lida.name)
	eq(#lida.Money.CopperOpen(7), 1)
	eq(lida.Money.CopperBack(N.bank, 5000, 7), true, "a refund of it clears the line")
	eq(#lida.Money.CopperOpen(7), 0)
	-- Nothing of it in the live store.
	eq(bank.Arena.Store("L").bank, nil)
	-- Chips: granted, bet, settled with no fee.
	copper = false
	local W = bank.Wallet
	local pa, la = W.Account(parric.name, true), W.Account(lida.name)
	W.Grant(pa, "c", 1000 * 100, "J", "rehearse")
	W.Grant(la, "c", 1000 * 100, "J", "rehearse")
	W.Register("R1c", 1, { nsel = 2, closes = w.clock + 600, cur = "c" })
	W.Hold(la, 100 * 100, { eid = "R1c", idx = 1, o = "A", nonce = "c1" })
	W.Hold(pa, 100 * 100, { eid = "R1c", idx = 1, o = "B", nonce = "c2" })
	W.Settle("R1c", 1, "A")
	-- (Her 1,000 from the operator and the rehearsal's own 1,000 on her first bet, the
	-- design; then the other side's 100 chips, no fee.)
	eq(W.Available(la, "c"), 2100 * 100, "the other side's 100 chips, no fee"); eq(W.Owed(), 0)
	NoErrors(w)
end)

test("1.2 the money part: the beta (saved data lost at every login): direct stakes and held stakes refused, a glory-points market still runs", function()
	local w = World.New()
	local king = M.Role(w, "king")
	local bank = M.Role(w, "bank", { persists = false })
	local lida = M.Client(w, "Lida Fenn", { persists = false })
	M.GoLive(w, king, { cur = "p" }, { N.bank })
	M.Relog(w, lida)
	M.Relog(w, bank)
	eq(bank.Arena.Persists(), false)
	eq(select(2, lida.Stakes.Direct({ id = "F1b", loser = lida.name, winner = N.bettor2, copper = 1 * G })), "persist")
	eq(select(2, lida.Stakes.Open({ id = "F1b", A = { name = lida.name }, B = { name = N.bettor2 }, stake = { A = 1 * G, B = 1 * G }, arbiter = N.arbiter })), "persist")
	-- (The King's words and the bank's yes, again: the beta forgot them.)
	M.GoLive(w, king, { cur = "p" }, { N.bank })
	w:Run(1)
	bank.Wallet.SetBankYes(true)
	eq(bank.Wallet.Duty(true, "L"), true, "points need no saved gold")
	local W = bank.Wallet
	local la = W.Account(lida.name, true)
	assert(W.Register("F1p", 1, { nsel = 2, closes = w.clock + 600, cur = "p" }))
	assert(W.Hold(la, 1000, { eid = "F1p", idx = 1, o = "A", nonce = "q1" }))
	eq(W.Available(la, "p"), 99000)
	NoErrors(w)
end)

test("1.2 the money part: auditors repeat the open marks they hold (a debtor who quit stays marked for clients that come later); the debtor's own clearing still clears the relayed mark", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local aud = cast.auditor
	local lida, parric = M.Client(w, "Lida Fenn", { money = 50000 }), M.Client(w, "Parric Stowe")
	for _, c in ipairs({ lida, parric }) do M.Relog(w, c) end
	w:Run(301)
	assert(lida.Debts.Owe({ kind = "bet", creditor = parric.name, copper = 2 * G, ref = "DF7", due = w.clock + 10 }))
	w:Run(40)
	eq(aud.Debts.Mark(lida.name), "open")
	w:Logout(lida)
	-- Someone new, after the mark went round.
	local wenna = M.Client(w, "Wenna Crale")
	M.Relog(w, wenna)
	eq(wenna.Debts.Mark(lida.name), nil)
	w:Run(1900)
	eq(wenna.Debts.Mark(lida.name), "open", "the auditor's repeat")
	-- (Each auditor: the King's client is one too.) At most once in 30 minutes each.
	for _, c in ipairs({ aud, cast.king }) do
		local relays = Count(w:Sent{ from = c, type = "ZX" }, function(s) return s.msg:find(lida.name, 1, true) ~= nil end)
		assert(relays <= 2, c.name .. " repeated it " .. relays .. " times")
	end
	local all = Count(w:Sent{ type = "ZX" }, function(s) return s.client ~= lida and s.msg:find(lida.name, 1, true) ~= nil end)
	assert(all >= 1, "repeated")
	-- She comes back and pays: the creditor's receipt, her own clearing, and it clears everywhere.
	w:Login(lida)
	w:Run(60)
	parric.Debts.Credit({ debtor = lida.name, copper = 2 * G, ref = "DF7", mid = "F7", due = w.clock + 600 })
	w:Trade(lida, parric, { aGives = 2 * G })
	w:Run(5)
	eq(#lida.Debts.Open(), 0)
	eq(wenna.Debts.Mark(lida.name), nil, "cleared")
	NoErrors(w)
end)

test("1.2 the money part: a direct bet paid on time reaches the bank's record (the payee's receipt): both earn a point, the payer's largest paid, the token's history", function()
	local w = World.New()
	local cast = M.Cast(w)
	local bank = cast.bank
	local torvin, selka = M.Client(w, "Torvin Hale", { money = 100000 }), M.Client(w, "Selka Drummond")
	for _, c in ipairs({ torvin, selka }) do M.Relog(w, c) end
	w:Run(301)
	torvin.Debts.SendClaim(selka.name); selka.Debts.SendClaim(torvin.name)
	w:Run(0)
	torvin.Stakes.Direct({ id = "F3d", loser = torvin.name, winner = selka.name, copper = 5 * G })
	selka.Stakes.Direct({ id = "F3d", loser = torvin.name, winner = selka.name, copper = 5 * G })
	w:Trade(torvin, selka, { aGives = 5 * G })
	w:Run(10)
	local rec = bank.Standing.Record(torvin.name)
	eq(rec.points, 1); eq(rec.paidMax, 5 * G)
	eq(bank.Standing.Points(selka.name), 1)
	-- Once: the payer's receipt counts nothing, the same ref again neither.
	w:As(selka, function() selka.ns.Debts.Receipt({ ref = "DF3d", payer = torvin.name, payee = selka.name, copper = 5 * G, to = {} }) end)
	w:Run(10)
	eq(bank.Standing.Points(torvin.name), 1)
	NoErrors(w)
end)

test("1.2 the money part: a closing bank (the King's word 'c') takes no deposit and no bet: withdrawals only", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida, king = cast.bank, cast["Lida Fenn"], cast.king
	Fund(w, cast, lida, 5 * G)
	assert(king.Roles.SetBanks({ { name = N.bank, state = "c" } }))
	w:Run(60)
	eq(select(2, lida.Wallet.Deposit(N.bank, "t", 1 * G)), "closed")
	local W = bank.Wallet
	eq(select(2, W.Register("F1c", 1, { nsel = 2, closes = w.clock + 600, cur = "g" })), "closing")
	assert(lida.Wallet.Withdraw(N.bank, 2 * G))
	w:Run(0)
	eq(lida.Wallet.View().intents[1].state, "queued", "withdrawals still")
	NoErrors(w)
end)

test("1.2 the money part: the money's buttons go through Arena.Can and Arena.Do: a bank's buttons only on its duty, a deposit refused with its reason", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" }, duty = false })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	eq(select(2, bank.Arena.Can("bank.pay")), "duty")
	eq(select(2, lida.Arena.Can("wallet.deposit", N.bank, "t", 1 * G)), "offline")
	eq(select(2, lida.Arena.Can("bank.duty", true, "L")), "unlisted")
	bank.Wallet.SetBankYes(true)
	eq(bank.Arena.Do("bank.duty", true, "L"), true)
	w:Run(0)
	eq(bank.Arena.Can("bank.pay"), true)
	local r = lida.Arena.Do("wallet.deposit", N.bank, "t", 1 * G)
	eq(type(r), "table"); eq(r.copper, 1 * G)
	eq(bank.Arena.Can("bank.payguild"), true, "a receiver heard lately")
	eq(select(2, lida.Arena.Can("debt.payfee", "nope")), "fee")
	NoErrors(w)
end)

test("1.2 the money part review: with no arbiter to credit (none named, or the King) the whole 6% is the guild's, never lost; the bank's calls need its duty; a mail depositor frozen as unknown is his to bet with once his client speaks", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 20 * G); Fund(w, cast, parric, 20 * G)
	local W = bank.Wallet
	local la, pa = W.Account(lida.name), W.Account(parric.name)
	-- No arbiter named: 10 g against 10 g pays 19 g 40 s, and the guild is owed all of the 6%: 60 s.
	assert(W.Register("F1n", 1, { nsel = 2, closes = w.clock + 600, cur = "g" }))
	W.Hold(la, 10 * G, { eid = "F1n", idx = 1, o = "A", nonce = "a1" }); W.Hold(pa, 10 * G, { eid = "F1n", idx = 1, o = "B", nonce = "a2" })
	W.Settle("F1n", 1, "A")
	eq(W.Available(la), 10 * G + 194000); eq(W.Owed(), 6000, "all of it the guild's")
	-- The King named as the arbiter: the same.
	assert(W.Register("F2n", 1, { nsel = 2, closes = w.clock + 600, cur = "g", arbiter = N.king }))
	W.Hold(la, 5 * G, { eid = "F2n", idx = 1, o = "A", nonce = "a3" }); W.Hold(pa, 5 * G, { eid = "F2n", idx = 1, o = "B", nonce = "a4" })
	W.Settle("F2n", 1, "B")
	eq(W.Owed(), 6000 + 3000); eq(W.Account(N.king), nil, "no wallet for him")
	w:Run(10)
	local rep = cast.auditor.Wallet.Replica(N.bank)
	eq(rep.owed, 9000); eq(Count(rep.flags, function() return true end), 0)
	-- Off duty: nothing written, nothing whispered as the bank.
	W.Duty(false)
	eq(select(2, W.Register("F3n", 1, { nsel = 2, closes = w.clock + 600 })), "duty")
	eq(select(2, W.Hold(la, 1 * G, { eid = "F1n", idx = 1, o = "A", nonce = "a5" })), "duty")
	eq(W.Account("Torvin Hale-Emberfall", true), nil, "no account opened off duty")
	assert(W.Duty(true, "L"))
	-- A mail from a client that never spoke: frozen; once it does (a deposit's intent), his.
	local wenna = M.Client(w, "Wenna Crale", { money = 90000 })
	M.Relog(w, wenna)
	w:Run(301)
	w:Mail(wenna, bank, 3 * G, "for the arena")
	w:Take(bank, #bank.inbox)
	eq(W.Facts(W.Account(wenna.name)).frozen, true)
	wenna.Wallet.Deposit(N.bank, "m", 1 * G)
	w:Run(0)
	eq(W.Facts(W.Account(wenna.name)).frozen, false, "his client spoke")
	NoErrors(w)
end)

test("1.2 the money part review: a bank holding only glory points owes no gold: its head says so (no 'L'), and a word may drop it", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" }, settings = { cur = "p" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local W = bank.Wallet
	local la = W.Account(lida.name, true)
	W.Register("F1q", 1, { nsel = 2, closes = w.clock + 600, cur = "p" })
	W.Hold(la, 1000, { eid = "F1q", idx = 1, o = "A", nonce = "q1" })
	W.SendHead()
	w:Run(0)
	local zh = w:Sent{ from = bank, type = "ZH" }
	local flags = zh[#zh].msg:match("~([^~]+)$")
	eq(flags, "s", "saved data kept; no gold owed")
	eq(lida.Roles.stillOwing(N.bank), false)
	NoErrors(w)
end)

test("1.2 the money part review: a party with two matches open with one arbiter pays both stakes in one trade: each held, nothing owed back but what is over both", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local king = cast.king
	local arb = M.Role(w, "arbiter")
	local torvin, selka, wenna = M.Client(w, "Torvin Hale", { money = 90000 }), M.Client(w, "Selka Drummond", { money = 90000 }), M.Client(w, "Wenna Crale", { money = 90000 })
	for _, c in ipairs({ arb, torvin, selka, wenna }) do M.Relog(w, c) end
	assert(king.Roles.SetArbiters({ { name = N.arbiter, cap = 10 } }))
	w:Run(301)
	local t1 = { id = "F1m", A = { name = torvin.name }, B = { name = selka.name }, stake = { A = 1 * G, B = 1 * G }, arbiter = N.arbiter }
	local t2 = { id = "F2m", A = { name = torvin.name }, B = { name = wenna.name }, stake = { A = 2 * G, B = 2 * G }, arbiter = N.arbiter }
	assert(arb.Stakes.Open(t1)); w:Run(1); assert(arb.Stakes.Open(t2))
	w:Trade(torvin, arb, { aGives = 3 * G + 500 })
	eq(arb.Stakes.Held("F1m").A, 1 * G); eq(arb.Stakes.Held("F2m").A, 2 * G)
	local open = arb.Debts.Open()
	eq(#open, 1); eq(open[1].kind, "n"); eq(open[1].copper, 500, "only what is over both stakes")
	NoErrors(w)
end)

test("1.2 the money part: Lottery v2 settles before carry, rolls only unclaimed profit, and every replica agrees", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	local W = bank.Wallet
	local la, pa = W.Account(lida.name), W.Account(parric.name)
	eq(select(2, W.Register("Lold", 1, { nsel = 25, closes = w.clock + 600, cur = "g" })), "version",
		"a versionless lottery ledger market is rejected")
	-- Day 1: no drawn animal has a ticket. The whole 2 g profit pool is retained, with no fee.
	assert(W.Register("L1day", 1, { kind = "l", nsel = 25, closes = w.clock + 600, cur = "g" }))
	W.Hold(la, 1 * G, { eid = "L1day", idx = 1, o = "3", nonce = "d1" }); W.Hold(pa, 1 * G, { eid = "L1day", idx = 1, o = "7", nonce = "d2" })
	local d1 = assert(W.SettleLottery("L1day", 1, { 12, 13, 14, 15, 16 }))
	eq(d1.refunds, 0); eq(d1.fee, 0); eq(d1.nextCarry, 2 * G)
	eq(W.Carry("L1day", 1, "L2day", 1), 2 * G)
	eq(W.Available(la), 9 * G); eq(W.Owed(), 0, "no fee on a pool nobody won")
	eq(W.Liabilities().g, 20 * G, "the pot still owed: to the next day's winners")
	eq(select(2, W.Checkpoint()), "pot")
	-- Day 2: beast 5 is first. Its ticket gets 1 g back and claims the 1.5 g first tranche;
	-- the aggregate fee is 900 copper, and the other 1.5 g remains as unclaimed carry.
	assert(W.Register("L2day", 1, { kind = "l", nsel = 25, closes = w.clock + 600, cur = "g" }))
	eq(W.Pot("L2day", 1), 2 * G)
	W.Hold(la, 1 * G, { eid = "L2day", idx = 1, o = "5", nonce = "d3" }); W.Hold(pa, 1 * G, { eid = "L2day", idx = 1, o = "9", nonce = "d4" })
	local d2 = assert(W.SettleLottery("L2day", 1, { 5, 1, 2, 4, 6 }))
	eq(d2.refunds, 1 * G); eq(d2.grossProfit, 15000); eq(d2.fee, 900); eq(d2.nextCarry, 15000)
	eq(W.Available(la), 8 * G + 24100); eq(W.Available(pa), 8 * G); eq(W.Owed(), 900)
	eq(W.Pot("L2day", 1), 15000)
	eq(W.Liabilities().g + W.Owed(), 20 * G, "in equals out")
	w:Run(10)
	local rep = cast.auditor.Wallet.Replica(N.bank)
	eq(rep.owed, 900); eq(rep.liabilities.g, 20 * G - 900); eq(Count(rep.flags, function() return true end), 0)
	NoErrors(w)
end)

test("1.2 integration: a void Lottery day rolls only its retained pot; its refunded stakes never enter the next day", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	local W = bank.Wallet
	local la, pa = W.Account(lida.name), W.Account(parric.name)

	-- An earlier day supplies a 2 g pot to the day that will later be voided.
	assert(W.Register("L0pot", 1, { kind = "l", nsel = 25, closes = w.clock + 600, cur = "g" }))
	assert(W.Hold(la, 1 * G, { eid = "L0pot", idx = 1, o = "3", nonce = "v0a" }))
	assert(W.Hold(pa, 1 * G, { eid = "L0pot", idx = 1, o = "7", nonce = "v0b" }))
	assert(W.SettleLottery("L0pot", 1, { 12, 13, 14, 15, 16 }))
	eq(W.Carry("L0pot", 1, "L1void", 1), 2 * G)

	-- This day's own 2 g is refunded by the void.  The earlier 2 g remains as its retained pot.
	assert(W.Register("L1void", 1, { kind = "l", nsel = 25, closes = w.clock + 600, cur = "g" }))
	assert(W.Hold(la, 1 * G, { eid = "L1void", idx = 1, o = "4", nonce = "v1a" }))
	assert(W.Hold(pa, 1 * G, { eid = "L1void", idx = 1, o = "8", nonce = "v1b" }))
	assert(W.Void("L1void", 1, "X"))
	eq(W.Available(la), 9 * G); eq(W.Available(pa), 9 * G, "the void refunded this day's stakes")
	eq(W.Pot("L1void", 1), 2 * G, "the pot carried into the void stays there")

	-- A later claim moves only that retained pot.  Retrying the same claim is idempotent; another
	-- destination cannot take it, and the source remains a void in the ledger's public state.
	eq(W.Carry("L1void", 1, "L2next", 1), 2 * G)
	eq(W.Pot("L1void", 1), 0); eq(W.Pot("L2next", 1), 2 * G)
	eq(W.Carry("L1void", 1, "L2next", 1), 2 * G, "the same claim may be retried")
	eq(select(2, W.Carry("L1void", 1, "L3other", 1)), "settled", "a second destination is refused")
	eq(W.Market("L1void", 1).result, "V", "a carry does not rewrite the void result")
	eq(W.Available(la), 9 * G); eq(W.Available(pa), 9 * G, "no refunded stake was carried")
	eq(W.Liabilities().g, 20 * G, "nothing appeared or vanished")
	w:Run(10)
	local rep = cast.auditor.Wallet.Replica(N.bank)
	eq(rep.liabilities.g, 20 * G); eq(Count(rep.flags, function() return true end), 0, "the replica applies both x entries")
	NoErrors(w)
end)

test("1.2 the money part: the head says 'd' (taking trades now) from Call next until the called depositor is served; a full bank stays 'f'", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local function LastState()
		local zh = w:Sent{ from = bank, type = "ZH" }
		return (zh[#zh].msg:match("^ZH~L1~[^~]+~[^~]+~[^~]+~[^~]+~([^~]+)~"))
	end
	w:Run(61)
	eq(LastState(), "o")
	assert(lida.Wallet.Deposit(N.bank, "t", 5 * G))
	w:Run(0)
	local before = #w:Sent{ from = bank, type = "ZH" }
	assert(bank.Wallet.CallNext())
	w:Run(0)
	eq(#w:Sent{ from = bank, type = "ZH" }, before + 1, "a head at once: the state changed")
	eq(LastState(), "d")
	w:Run(1)
	eq(lida.Wallet.Banks()[1].trading, true, "the player's row says so")
	w:Trade(lida, bank, { aGives = 5 * G })
	w:Run(61)
	eq(LastState(), "o", "served: taking bets again")
	eq(lida.Wallet.Banks()[1].trading, false)
	-- At the bank's cap (the King's word after this depositor queued), full wins over a call.
	assert(lida.Wallet.Deposit(N.bank, "t", 1 * G))
	w:Run(0)
	M.GoLive(w, cast.king, { bankCap = 5 * G })
	assert(bank.Wallet.CallNext())
	w:Run(0)
	eq(LastState(), "f")
	NoErrors(w)
end)

test("1.2 the money part: the acknowledgement lag (BO's lag) counts the bets waiting at 150 a minute, grouped or not, and is 0 once they went out", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" } })
	local bank, lida, parric, wenna = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"]
	for _, c in ipairs({ lida, parric, wenna }) do Fund(w, cast, c, 10 * G) end
	local W = bank.Wallet
	local la, pa, wa = W.Account(lida.name), W.Account(parric.name), W.Account(wenna.name)
	assert(W.Register("F9a", 1, { nsel = 2, closes = w.clock + 600, cur = "g" }))
	w:Run(10)
	eq(W.Lag(), 0, "nothing waiting")
	-- Three bets on A share one entry; two on B are the open group: five bets, two minutes of
	-- 150 bets make 2 s (two entries would have made 1 s).
	W.Hold(la, 1 * G, { eid = "F9a", idx = 1, o = "A", nonce = "g1" })
	W.Hold(pa, 1 * G, { eid = "F9a", idx = 1, o = "A", nonce = "g2" })
	W.Hold(wa, 1 * G, { eid = "F9a", idx = 1, o = "A", nonce = "g3" })
	W.Hold(la, 1 * G, { eid = "F9a", idx = 1, o = "B", nonce = "g4" })
	W.Hold(pa, 1 * G, { eid = "F9a", idx = 1, o = "B", nonce = "g5" })
	eq(W.Lag(), 2)
	w:Run(10)
	eq(W.Lag(), 0, "all out")
	eq(lida.Wallet.Lag(), 0, "not a bank: nothing")
	NoErrors(w)
end)

test("1.2 the money part: 'send my winnings after each event': a player who ticked it sends ZW all when a market he bet on settles; the mail waits for the operator; one who did not sends nothing", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	eq(lida.Wallet.View().autoWithdraw, false)
	assert(lida.Arena.Do("wallet.autowithdraw", true))
	eq(lida.Wallet.View().autoWithdraw, true)
	local W = bank.Wallet
	local la, pa = W.Account(lida.name), W.Account(parric.name)
	assert(W.Register("F8a", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" }))
	W.Hold(la, 2 * G, { eid = "F8a", idx = 1, o = "A", nonce = "a1" })
	W.Hold(pa, 2 * G, { eid = "F8a", idx = 1, o = "B", nonce = "a2" })
	w:Run(10)
	eq(lida.Wallet.Statement(N.bank).g.escrow, 2 * G, "her statement shows the bet")
	eq(#w:Sent{ from = lida, type = "ZW" }, 0, "a bet held is no event")
	-- A wins: the money won is 20,000, 6% (1,200) the guild's: Lida 80,000 + 38,800.
	W.Settle("F8a", 1, "A")
	w:Run(10)
	local zw = w:Sent{ from = lida, type = "ZW" }
	eq(#zw, 1)
	assert(zw[1].msg:find("~all~m$"), zw[1].msg)
	eq(#w:Sent{ from = parric, type = "ZW" }, 0, "he did not tick it")
	eq(W.Available(la), 0, "all of it reserved for the mail")
	eq(lida.Wallet.View().intents[1].state, "queued")
	eq(#lida.inbox, 0, "no mail until the operator's click")
	local pay = W.PayNext()
	eq(pay.copper, 118800)
	-- Another statement with nothing leaving the bets sends nothing more.
	lida.Wallet.AskStatement(N.bank)
	w:Run(10)
	eq(#w:Sent{ from = lida, type = "ZW" }, 1)
	NoErrors(w)
end)

test("1.2 the money part: the Oracle's inputs from the ledger: net profit, total staked and markets per account over the public gold pool markets settled in the window; a void, a private event's market and the Lottery's never count", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 20 * G); Fund(w, cast, parric, 20 * G)
	local W = bank.Wallet
	local la, pa = W.Account(lida.name), W.Account(parric.name)
	local t0 = w.clock
	-- 10 g each side, A (Lida) wins, the arbiter named: Lida is paid 194,000.
	assert(W.Register("F7a", 1, { nsel = 2, closes = w.clock + 600, cur = "g", arbiter = N.arbiter, public = true }))
	assert(W.Hold(la, 10 * G, { eid = "F7a", idx = 1, o = "A", nonce = "o1" }))
	assert(W.Hold(pa, 10 * G, { eid = "F7a", idx = 1, o = "B", nonce = "o2" }))
	W.Settle("F7a", 1, "A")
	w:Run(100)
	local t1 = w.clock
	-- 5 g each side, B (Parric) wins, the guild's 6%: Parric is paid 97,000. Its event is public by
	-- the events registry (the spec says nothing).
	bank.ns.Arena.Events.Register("F", function(eid) return eid == "F7b" and { kind = "fight", public = true } or nil end)
	assert(W.Register("F7b", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" }))
	assert(W.Hold(la, 5 * G, { eid = "F7b", idx = 1, o = "A", nonce = "o3" }))
	assert(W.Hold(pa, 5 * G, { eid = "F7b", idx = 1, o = "B", nonce = "o4" }))
	W.Settle("F7b", 1, "B")
	-- A void: never a prediction.
	assert(W.Register("F7c", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g", public = true }))
	assert(W.Hold(la, 3 * G, { eid = "F7c", idx = 1, o = "A", nonce = "o5" }))
	assert(W.Hold(pa, 3 * G, { eid = "F7c", idx = 1, o = "B", nonce = "o6" }))
	W.Void("F7c", 1)
	-- A private event's market (friends could farm it) and the Lottery's (luck): never counted.
	assert(W.Register("F7d", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" }))
	assert(W.Hold(la, 1 * G, { eid = "F7d", idx = 1, o = "A", nonce = "o7" }))
	assert(W.Hold(pa, 1 * G, { eid = "F7d", idx = 1, o = "B", nonce = "o8" }))
	W.Settle("F7d", 1, "A")
	assert(W.Register("L7e", 1, { kind = "l", nsel = 25, closes = w.clock + 600, cur = "g", to = "g", public = true }))
	assert(W.Hold(la, 1 * G, { eid = "L7e", idx = 1, o = "3", nonce = "o9" }))
	assert(W.Hold(pa, 1 * G, { eid = "L7e", idx = 1, o = "7", nonce = "oa" }))
	W.SettleLottery("L7e", 1, { 3, 1, 2, 4, 5 })
	local all = W.Oracle(t0, w.clock + 1)
	eq(#all, 2)
	eq(all[1].name, lida.name); eq(all[1].profit, 94000 - 50000); eq(all[1].staked, 150000); eq(all[1].markets, 2)
	eq(all[2].name, parric.name); eq(all[2].profit, -100000 + 47000); eq(all[2].staked, 150000); eq(all[2].markets, 2)
	local first = W.Oracle(t0, t1)
	eq(first[1].profit, 94000); eq(first[1].markets, 1); eq(first[2].profit, -100000)
	eq(#W.Oracle(w.clock + 1, w.clock + 99), 0, "nothing settled then")
	eq(#W.Oracle(t0, w.clock + 1, "p"), 0, "no points market")
	eq(#lida.Wallet.Oracle(t0, w.clock + 1), 0, "only the bank's ledger answers")
	NoErrors(w)
end)

test("1.2 the money part: a deposit mail the bank has not taken after 24 hours shows 'not taken yet'", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local r = lida.Wallet.Deposit(N.bank, "m", 2 * G)
	w:Run(0)
	lida.globals.SendMailFrame:Show()
	lida.Wallet.FillDeposit(r.id)
	w:Mail(lida, bank, 2 * G, "Arena wallet deposit")
	eq(lida.Wallet.Receipts()[1].state, "mail")
	eq(lida.Wallet.Receipts()[1].notTaken, nil)
	w:Run(86400)
	eq(lida.Wallet.Receipts()[1].notTaken, true)
	w:Take(bank, 1)
	w:Run(5)
	eq(lida.Wallet.Receipts()[1].state, "credited"); eq(lida.Wallet.Receipts()[1].notTaken, nil)
	NoErrors(w)
end)

-- A rehearsal's stand-ins (the screens' ArenaTest and the bank stand-in), on every client of the world.
local function Rehearse(w, run, participant)
	for _, c in ipairs(w.clients) do
		c.ns.ArenaTest.Running = function() return run() end
		c.ns.ArenaTest.Participant = participant
		c.ns.ArenaRoles.standIn = function(name, letter, mode) return mode == "T" and letter == "b" and name:lower() == N.bank:lower() end
		c.ns.ArenaRoles.standIns = function(letter) return letter == "b" and { N.bank } or {} end
		w:As(c, function() c.ns.Arena.Store("T") end)
	end
end

test("1.2 Wallet view: points and chips use their stored p slot and 100-unit scale; a copper rehearsal remains gold", function()
	-- Live glory points: the first bet grants 1,000 points and stakes 100.  The Wallet model and
	-- Treasury page must expose 900 points, not 90,000 raw ledger units.
	local wp = World.New()
	local cp = M.Cast(wp, { bettors = { "Lida Fenn" }, settings = { cur = "p" } })
	local lp, Wp = cp["Lida Fenn"], cp.bank.Wallet
	local ap = Wp.Account(lp.name, true)
	assert(Wp.Register("F1pts", 1, { nsel = 2, closes = wp.clock + 600, cur = "p" }))
	assert(Wp.Hold(ap, 100 * 100, { eid = "F1pts", idx = 1, o = "A", nonce = "pts1" }))
	wp:Run(5)
	local pv = lp.Wallet.View("L")
	eq(pv.currency, "p"); eq(pv.slot, "p"); eq(pv.unit, 100)
	wp:As(lp, function()
		local balance
		for _, line in ipairs(lp.ns.Treasury.WalletLines()) do if line.text == lp.ns.L.MONEY_WALLET_BALANCE then balance = line.right end end
		eq(balance, lp.ns.L.MONEY_WALLET_UNITS:format(lp.ns.FormatNumber(900), lp.ns.L.MONEY_WALLET_POINTS))
	end)
	NoErrors(wp)

	-- Rehearsal chips occupy that same physical p slot, but are a distinct currency and label.
	local wc = World.New()
	local cc = M.Cast(wc, { bettors = { "Lida Fenn" }, duty = false })
	local bank, lida = cc.bank, cc["Lida Fenn"]
	local run = { rid = 31, lane = "army", money = "c", chips = 500 }
	Rehearse(wc, function() return run end, function() return true end)
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "T"))
	wc:Run(0) -- hear the rehearsal bank's head (and its epoch) before asking for a statement
	lida.Wallet.AskStatement(N.bank, "T")
	wc:Run(5)
	local cv = lida.Wallet.View("T")
	eq(cv.currency, "c"); eq(cv.slot, "p"); eq(cv.unit, 100); eq(cv.copper, false)
	eq(#cv.banks, 1); eq(cv.banks[1].p.bal, 500 * 100, "the rehearsal statement is in the p slot")
	wc:As(lida, function()
		local balance
		for _, line in ipairs(lida.ns.Treasury.WalletLines()) do if line.text == lida.ns.L.MONEY_WALLET_BALANCE then balance = line.right end end
		eq(balance, lida.ns.L.MONEY_WALLET_UNITS:format(lida.ns.FormatNumber(500), lida.ns.L.MONEY_WALLET_CHIPS))
	end)

	-- The other rehearsal kind uses actual copper in the g slot; it must never be labelled chips.
	run.money = "p"
	local gv = lida.Wallet.View("T")
	eq(gv.currency, "g"); eq(gv.slot, "g"); eq(gv.unit, 1); eq(gv.copper, true)
	NoErrors(wc)
end)

test("1.2 the money part: a chips rehearsal: the bank credits each participant the rehearsal's chips on his first action, once; a tester's top up adds 100 chips once an hour; none outside it or in a copper rehearsal", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" }, duty = false })
	local bank, lida, parric, wenna = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"]
	local run = { rid = 9, lane = "army", money = "c", chips = 500 }
	Rehearse(w, function() return run end, function(name) return name:lower() ~= wenna.name:lower() end)
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "T"))
	w:Run(0)
	-- Asking for a statement is a first action: the director's 500 chips, in the points balance.
	lida.Wallet.AskStatement(N.bank, "T")
	w:Run(5)
	eq(lida.Wallet.Statement(N.bank, "T").p.bal, 500 * 100)
	-- A bet is one too (Parric never asked); a second grants nothing more.
	local W = bank.Wallet
	assert(W.Register("R2a", 1, { nsel = 2, closes = w.clock + 600, cur = "c" }))
	local pa = W.Account(parric.name, true)
	assert(W.Hold(pa, 100 * 100, { eid = "R2a", idx = 1, o = "B", nonce = "k1" }))
	eq(W.Available(pa, "c"), 400 * 100)
	assert(W.Hold(pa, 100 * 100, { eid = "R2a", idx = 1, o = "B", nonce = "k2" }))
	eq(W.Available(pa, "c"), 300 * 100, "once per rehearsal")
	-- Someone outside the rehearsal gets none.
	local wa = W.Account(wenna.name, true)
	eq(select(2, W.Hold(wa, 100 * 100, { eid = "R2a", idx = 1, o = "A", nonce = "k3" })), "funds")
	eq(W.Available(wa, "c"), 0)
	-- The top up: 100 chips; within the hour her own client says wait, and the bank refuses it too.
	assert(lida.Wallet.TopUp(N.bank))
	w:Run(5)
	eq(lida.Wallet.Statement(N.bank, "T").p.bal, 600 * 100)
	eq(select(2, lida.Wallet.TopUp(N.bank)), "rate")
	local ep = lida.Wallet.Statement(N.bank, "T").epoch
	w:As(lida, function() lida.ns.Arena.Send("ZQ", "T", ("T~%s~0"):format(ep), { to = N.bank }) end)
	w:Run(5)
	local zk = w:Sent{ from = bank, type = "ZK" }
	assert(zk[#zk].msg:find("~T~rate~", 1, true), zk[#zk].msg)
	eq(W.Available(W.Account(lida.name), "c"), 600 * 100, "nothing more")
	eq(select(2, wenna.Wallet.TopUp(N.bank)), nil, "her client may ask...")
	w:Run(5)
	eq(W.Available(wa, "c"), 0, "...the bank gives someone outside it nothing")
	-- An hour later: granted again. No gold, no fee, no mail anywhere.
	w:Run(3600)
	assert(lida.Wallet.TopUp(N.bank))
	w:Run(5)
	eq(lida.Wallet.Statement(N.bank, "T").p.bal, 700 * 100)
	eq(W.Owed(), 0); eq(#bank.inbox, 0)
	-- A copper rehearsal (real copper) has no chips: no top up, nothing granted.
	run = { rid = 10, lane = "army", money = "p" }
	eq(select(2, lida.Wallet.TopUp(N.bank)), "topup")
	local before = W.Available(pa, "c")
	w:As(parric, function() parric.ns.Arena.Send("ZQ", "T", ("T~%s~0"):format(ep), { to = N.bank }) end)
	w:Run(5)
	eq(W.Available(pa, "c"), before)
	NoErrors(w)
end)

test("1.2 the money part: 'Save now' is offered only while no market is open and nothing waits to be sent; the operator's click reloads", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 5 * G); Fund(w, cast, parric, 5 * G)
	w:Run(10)
	local W = bank.Wallet
	eq(W.Console().saveNow, true)
	assert(W.Register("F6a", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" }))
	eq(W.Console().saveNow, false)
	eq(select(2, bank.Arena.Can("bank.save")), "open")
	assert(W.Hold(W.Account(lida.name), 1 * G, { eid = "F6a", idx = 1, o = "A", nonce = "s1" }))
	assert(W.Hold(W.Account(parric.name), 1 * G, { eid = "F6a", idx = 1, o = "B", nonce = "s2" }))
	W.Settle("F6a", 1, "A")
	w:Run(10)
	eq(W.Console().saveNow, true)
	-- A deposit lands: its entry waits for the channel a moment, and "Save now" with it.
	assert(lida.Wallet.Deposit(N.bank, "t", 1 * G))
	w:Run(0)
	W.CallNext()
	w:Run(0)
	w:Trade(lida, bank, { aGives = 1 * G })
	eq(select(2, W.SaveReady()), "backlog", "its entry still waits for the channel")
	w:Run(10)
	eq(W.Console().saveNow, true)
	local reloads = 0
	bank.globals.ReloadUI = function() reloads = reloads + 1 end
	assert(bank.Arena.Do("bank.save"))
	eq(reloads, 1)
	eq(select(2, lida.Arena.Can("bank.save")), "duty", "a bank's button only")
	NoErrors(w)
end)

test("1.2 the money part: no gold market where nobody receives the guild's fee: a Horde realm on glory points with no feeTo refuses a gold sheet, a points one runs", function()
	local w = World.New()
	local H2 = { faction = "Horde", guild = World.KING_GUILD_HORDE }
	local king = M.Role(w, "kingHorde")
	local bank = M.Role(w, "bank", H2)
	M.GoLive(w, king, { cur = "p" }, { N.bank })
	M.Relog(w, bank)
	w:Run(0)
	eq(bank.Roles.FeeReceiver(), nil)
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "L"))
	local W = bank.Wallet
	eq(select(2, W.Register("F5g", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" })), "receiver")
	eq(W.Market("F5g", 1), nil)
	assert(W.Register("F5p", 1, { nsel = 2, closes = w.clock + 600 }), "the realm's points")
	eq(W.Market("F5p", 1).cur, "p")
	NoErrors(w)
end)

test("1.2 the money part: a copper rehearsal moves no gold where saved data does not survive (its record of the copper would be lost): the deposit is refused there", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" }, duty = false })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local beta = M.Client(w, "Parric Stowe", { persists = false, money = 500000 })
	Rehearse(w, function() return { rid = 11, lane = "army", money = "p" } end)
	bank.Wallet.SetBankYes(true)
	assert(bank.Wallet.Duty(true, "T"))
	w:Run(0)
	eq(beta.Arena.Persists(), false)
	eq(select(2, beta.Wallet.Deposit(N.bank, "t", 50 * S, "T")), "persist")
	assert(lida.Wallet.Deposit(N.bank, "t", 50 * S, "T"), "a client that keeps its data may")
	NoErrors(w)
end)

test("1.2 the money part: an auditor's view of one market from its replica: the pools per outcome (the L book is compared with them at x), closed and settled, and the bet entries flagged late", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" } })
	local bank, lida, parric, wenna, aud = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"], cast.auditor
	for _, c in ipairs({ lida, parric, wenna }) do Fund(w, cast, c, 5 * G) end
	local W = bank.Wallet
	assert(W.Register("F4m", 1, { nsel = 2, closes = w.clock + 600, cur = "g", arbiter = N.arbiter }))
	assert(W.Hold(W.Account(lida.name), 2 * G, { eid = "F4m", idx = 1, o = "A", nonce = "m1" }))
	assert(W.Hold(W.Account(wenna.name), 1 * G, { eid = "F4m", idx = 1, o = "A", nonce = "m2" }))
	assert(W.Hold(W.Account(parric.name), 3 * G, { eid = "F4m", idx = 1, o = "B", nonce = "m3" }))
	w:Run(10)
	local v = aud.Wallet.ReplicaMarket(N.bank, "F4m", 1)
	eq(v.pools.A, 3 * G); eq(v.pools.B, 3 * G); eq(v.pool, 6 * G); eq(v.bets, 3); eq(v.cur, "g"); eq(v.kind, "p")
	eq(v.closed, false); eq(v.settled, false); eq(v.late, 0)
	W.Close("F4m", 1)
	W.Settle("F4m", 1, "B")
	w:Run(10)
	v = aud.Wallet.ReplicaMarket(N.bank, "F4m", 1)
	eq(v.closed, true); eq(v.settled, true); eq(v.result, "B")
	eq(lida.Wallet.ReplicaMarket(N.bank, "F4m", 1), nil, "auditors only")
	eq(aud.Wallet.ReplicaMarket(N.bank, "F4x", 1), nil, "no such market")
	-- A bet entry dated at its market's lock is counted late.
	local rep = aud.Wallet.Replica(N.bank)
	local inject = ("ZE~L1~%s~%s~n:F4n.1:2:%s:gm:5k:p:g:a;BF4n.1.A.%s:1a.a.zzzzzz~0"):format(rep.epoch, aud.Arena.B36(rep.seq + 1), aud.Arena.B36(w.clock + 10),
		aud.Arena.B36(w.clock + 10))
	w:As(aud, function() aud.ns.Arena.Inject("CHANNEL", N.bank, inject) end)
	eq(aud.Wallet.ReplicaMarket(N.bank, "F4n", 1).late, 1)
	NoErrors(w)
end)

test("1.2 the money part: a deposit mail the bank never took and the game sent back shows 'returned to you' (watched again after a relog), never pending, never credited", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	local r = lida.Wallet.Deposit(N.bank, "m", 2 * G)
	w:Run(0)
	lida.globals.SendMailFrame:Show()
	lida.Wallet.FillDeposit(r.id)
	w:Mail(lida, bank, 2 * G, "Arena wallet deposit")
	eq(lida.Wallet.Receipts()[1].state, "mail")
	eq(lida.Wallet.Statement(N.bank).pending, 2 * G)
	M.Relog(w, lida)
	w:Run(0)
	-- (The game's return after 30 days, as the world models it: back to her, marked returned.)
	w:Return(bank, 1)
	w:Take(lida, #lida.inbox)
	w:Run(5)
	eq(lida.Wallet.Receipts()[1].state, "returned")
	eq(lida.Wallet.Statement(N.bank).pending, 0)
	eq(lida.Money.Expects("back:" .. r.id), nil, "no longer watched")
	eq(bank.Wallet.Liabilities().g, 0, "the bank credited nothing")
	NoErrors(w)
end)

test("1.2 the money part: a bank's ledger in a backup is checked before it is restored: its shape and every kept entry's MAC under its own secret; an edited copy is left out (Backup.lua loads before Wallet.lua, so the check is in place)", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 5 * G); Fund(w, cast, parric, 5 * G)
	local W = bank.Wallet
	-- A stake market's entries are opaque on the channel: their MAC covers the full text.
	assert(W.Register("F3s", 1, { nsel = 2, closes = w.clock + 600, cur = "g", kind = "s", to = "g", parties = { A = lida.name, B = parric.name },
		stakes = { A = 1 * G, B = 1 * G } }))
	assert(W.Hold(W.Account(lida.name), 1 * G, { eid = "F3s", idx = 1, o = "A", nonce = "b1" }))
	assert(W.Hold(W.Account(parric.name), 1 * G, { eid = "F3s", idx = 1, o = "B", nonce = "b2" }))
	w:Run(10)
	eq(Count(M.Entries(bank), function(e) return e:find("^h:") ~= nil end), 3, "three opaque entries")
	local good = World.Copy(W.BankStore())
	assert(W.CheckBackup(good), "the ledger as saved")
	local function Edited(fn)
		local v = World.Copy(good)
		fn(v)
		return W.CheckBackup(v)
	end
	assert(Edited(function(v) v.entries[2] = v.entries[2]:gsub("t$", "m") end) == nil, "an entry changed")
	assert(Edited(function(v) v.macs[3] = "zzzz" end) == nil, "a MAC changed")
	assert(Edited(function(v)
		local seq = next(v.full)
		v.full[seq] = v.full[seq] .. "0"
	end) == nil, "an opaque entry's text changed")
	assert(Edited(function(v) v.mac = "zzzz" end) == nil, "the last MAC is not the chain's")
	assert(Edited(function(v) v.secret = ("0"):rep(64) end) == nil, "another secret")
	assert(Edited(function(v) v.st = nil end) == nil, "its balances missing")
	assert(Edited(function(v) v.seq = -1 end) == nil)
	-- Pruned entries (before a verified snapshot) leave the rest to check.
	assert(Edited(function(v) v.entries[1], v.macs[1] = nil, nil end))
	local toc = assert(io.open(H.ADDON_DIR .. "Olympus.toc")):read("*a")
	assert(toc:find("\nBackup%.lua") < toc:find("\nWallet%.lua"), "Backup.lua before Wallet.lua")
	NoErrors(w)
end)

test("1.2 the money part: a stake market (the King's fight, a Bone Throw game from the wallets): only its two parties, each exactly his stake on himself, once; opaque on the channel, whole on the auditors' replicas; settled with the King's 2% the guild's, or an arbiter's 2% his", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe", "Wenna Crale" } })
	local bank, lida, parric, wenna, aud = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"], cast["Wenna Crale"], cast.auditor
	for _, c in ipairs({ lida, parric, wenna }) do Fund(w, cast, c, 10 * G) end
	w:Run(10)
	local W = bank.Wallet
	local la, pa, wa = W.Account(lida.name), W.Account(parric.name), W.Account(wenna.name)
	local P = { A = lida.name, B = parric.name }
	eq(select(2, W.Register("F2x", 1, { kind = "s", cur = "g", arbiter = N.king, parties = { A = lida.name } , stakes = { A = 5 * G, B = 5 * G } })), "parties")
	eq(select(2, W.Register("F2y", 1, { kind = "s", cur = "g", arbiter = bank.name, parties = P, stakes = { A = 5 * G, B = 5 * G } })), "arbiter",
		"never the bank's own character")
	-- The King judges: 5 g a side.
	assert(W.Register("F2k", 1, { kind = "s", cur = "g", arbiter = N.king, parties = P, stakes = { A = 5 * G, B = 5 * G }, closes = w.clock + 600 }))
	eq(select(2, W.Hold(wa, 5 * G, { eid = "F2k", idx = 1, o = "A", nonce = "p1" })), "party", "a spectator")
	eq(select(2, W.Hold(la, 5 * G, { eid = "F2k", idx = 1, o = "B", nonce = "p2" })), "party", "on the other side")
	eq(select(2, W.Hold(la, 4 * G, { eid = "F2k", idx = 1, o = "A", nonce = "p3" })), "stake", "not his stake")
	assert(W.Hold(la, 5 * G, { eid = "F2k", idx = 1, o = "A", nonce = "p4" }))
	eq(select(2, W.Hold(la, 5 * G, { eid = "F2k", idx = 1, o = "A", nonce = "p5" })), "held", "once")
	assert(W.Hold(pa, 5 * G, { eid = "F2k", idx = 1, o = "B", nonce = "p6" }))
	w:Run(10)
	local text = w:ChannelText()
	assert(not text:find("n:F2k", 1, true) and not text:find("BF2k", 1, true), "a stake market's entries go on the channel as digests")
	assert(text:find("~h:", 1, true) or text:find(";h:", 1, true), "its digests")
	local rep = aud.Wallet.Replica(N.bank)
	eq(rep.matches, true)
	eq(aud.Wallet.ReplicaMarket(N.bank, "F2k", 1).pools.A, 5 * G, "the auditor has its whole text")
	-- A wins: the money won is 5 g, 6% (3,000) all the guild's; Lida 50,000 + 97,000.
	W.Settle("F2k", 1, "A")
	eq(W.Available(la), 147000); eq(W.Available(pa), 50000); eq(W.Owed(), 3000)
	-- A Bone Throw game with an arbiter, 2 g against 3 g, B wins: the money won is 2 g, 1,200 of fee,
	-- 400 the arbiter's (in his wallet here) and 800 the guild's; Parric 20,000 + 48,800.
	assert(W.Register("K2f", 1, { kind = "s", cur = "g", arbiter = N.arbiter, parties = P, stakes = { A = 2 * G, B = 3 * G }, closes = w.clock + 600 }))
	assert(W.Hold(la, 2 * G, { eid = "K2f", idx = 1, o = "A", nonce = "q1" }))
	assert(W.Hold(pa, 3 * G, { eid = "K2f", idx = 1, o = "B", nonce = "q2" }))
	W.Settle("K2f", 1, "B")
	eq(W.Available(pa), 20000 + 48800); eq(W.Available(la), 147000 - 20000); eq(W.Owed(), 3000 + 800)
	eq(W.Available(W.Account(N.arbiter)), 400)
	-- A void gives each stake back.
	assert(W.Register("K2v", 1, { kind = "s", cur = "g", arbiter = N.arbiter, parties = P, stakes = { A = 1 * G, B = 1 * G }, closes = w.clock + 600 }))
	assert(W.Hold(la, 1 * G, { eid = "K2v", idx = 1, o = "A", nonce = "r1" }))
	assert(W.Hold(pa, 1 * G, { eid = "K2v", idx = 1, o = "B", nonce = "r2" }))
	W.Void("K2v", 1)
	eq(W.Available(pa), 68800); eq(W.Available(la), 127000)
	w:Run(10)
	rep = aud.Wallet.Replica(N.bank)
	eq(rep.matches, true); eq(rep.liabilities.g, W.Liabilities().g, "every replica agrees"); eq(rep.owed, 3800)
	NoErrors(w)
end)

test("1.2 the money part: one deposit ask and one new withdrawal per bank every 10 s: the client waits itself, the bank drops more unanswered, a resent withdrawal nonce is still answered", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn" } })
	local bank, lida = cast.bank, cast["Lida Fenn"]
	Fund(w, cast, lida, 10 * G)
	w:Run(10)
	assert(lida.Wallet.Deposit(N.bank, "m", 1 * G))
	eq(select(2, lida.Wallet.Deposit(N.bank, "m", 1 * G)), "rate")
	w:Run(0)
	local ep = bank.Wallet.BankStore().epoch
	local before = #w:Sent{ from = bank, type = "ZK" }
	w:As(lida, function() lida.ns.Arena.Send("ZD", "L", ("%s~m~%s~%s"):format(ep, lida.Arena.B36(1 * G), lida.Arena.B36(60)), { to = N.bank }) end)
	w:Run(0)
	eq(#w:Sent{ from = bank, type = "ZK" }, before, "a second ask within 10 s: no answer")
	local it = assert(lida.Wallet.Withdraw(N.bank, 1 * G))
	w:Run(0)
	eq(select(2, lida.Wallet.Withdraw(N.bank, 1 * G)), "rate")
	-- Its nonce again (a lost answer): the same request, answered; another nonce: dropped.
	before = #w:Sent{ from = bank, type = "ZK" }
	w:As(lida, function() lida.ns.Arena.Send("ZW", "L", ("%s~%s~%s~m"):format(ep, it.nonce, lida.Arena.B36(1 * G)), { to = N.bank }) end)
	w:As(lida, function() lida.ns.Arena.Send("ZW", "L", ("%s~zzzz01~%s~m"):format(ep, lida.Arena.B36(1 * G)), { to = N.bank }) end)
	w:Run(0)
	eq(#w:Sent{ from = bank, type = "ZK" }, before + 1)
	eq(#bank.Wallet.Console().withdrawals.queue, 1, "one request")
	w:Run(10)
	assert(lida.Wallet.Withdraw(N.bank, 1 * G), "10 s on")
	w:Run(0)
	eq(#bank.Wallet.Console().withdrawals.queue, 2)
	NoErrors(w)
end)

test("1.2 the money part: 'send my winnings after each event' right after a withdrawal asked by hand (refused): it goes once the 10 s have passed", function()
	local w = World.New()
	local cast = M.Cast(w, { bettors = { "Lida Fenn", "Parric Stowe" } })
	local bank, lida, parric = cast.bank, cast["Lida Fenn"], cast["Parric Stowe"]
	Fund(w, cast, lida, 10 * G); Fund(w, cast, parric, 10 * G)
	assert(lida.Arena.Do("wallet.autowithdraw", true))
	local W = bank.Wallet
	assert(W.Register("F8b", 1, { nsel = 2, closes = w.clock + 600, cur = "g", to = "g" }))
	W.Hold(W.Account(lida.name), 2 * G, { eid = "F8b", idx = 1, o = "A", nonce = "b1" })
	W.Hold(W.Account(parric.name), 2 * G, { eid = "F8b", idx = 1, o = "B", nonce = "b2" })
	w:Run(10)
	-- 50 s asked by hand (below the smallest withdrawal: refused); the market settles a moment later.
	assert(lida.Wallet.Withdraw(N.bank, 50 * S))
	w:Run(0)
	eq(lida.Wallet.View().intents[1].state, "refused")
	W.Settle("F8b", 1, "A")
	w:Run(3)
	eq(#w:Sent{ from = lida, type = "ZW" }, 1, "only her own, so far")
	w:Run(10)
	local zw = w:Sent{ from = lida, type = "ZW" }
	eq(#zw, 2)
	assert(zw[2].msg:find("~all~m$"), zw[2].msg)
	NoErrors(w)
end)
