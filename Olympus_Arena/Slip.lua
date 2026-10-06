local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Slip.lua. A stub the arena's core created for the screens to
-- fill. The bet slip (OlympusArenaSlip).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome

-- The small windows where the player commits something, each its own pop-up on parchment:
-- - the bet slip (OlympusArenaSlip, 360 x 330): every number it shows is the markets' own quote
--   (Markets.Quote, through ArenaHome.Data), never worked out here;
-- - the wallet (OlympusArenaWallet): the one balance of the Arena, Bones and the Lottery
--   (the design), deposits and withdrawals (every trade and mail the player's own click, the
--   gamepad UI told what to send), the ledger, the open bets;
-- - the challenge (OlympusArenaChallengeDialog, ArenaUI.Challenge(name, prefill)): the opponent,
--   casual or staked, the stake, direct or with an arbiter (Find an arbiter: name, online, zone,
--   free or busy, never an amount), best of 1, 3 or 5; a matched partner's stake and match id
--   come in the prefill (the design);
-- - the Find dialog (OlympusArenaFind, ArenaUI.OpenFind(game), the design), over ArenaMatch.View() and
--   ArenaMatch.Start(opts).
-- Amounts with +/- and Min/Max (the gamepad needs no typing); choices remembered. A bet sent, and
-- each open bet in My bets, has Watch live: where its event happens now (ArenaUI.WatchRoute).

local function Now() return ns.Arena.Now() end
local function Cur() local R = ns.ArenaRoles return R and R.Currency and R.Currency() or "g" end
local function ModeNow() return Home.ViewMode() end

-- Beside the betting window (past its side tabs), else in the middle.
local function PlaceBeside(f)
	local main = ArenaUI.Frame and ArenaUI.Frame()
	f:ClearAllPoints()
	if main and main:IsShown() then
		f:SetPoint("TOPLEFT", main, "TOPRIGHT", 46, -20)
	else
		f:SetPoint("CENTER", 0, 40)
	end
end

---------------------------------------------------------------------------
-- Watch live: where a bet's event can be watched now
---------------------------------------------------------------------------

-- { kind, eid } for a bet's event not over: "lottery" (the Lottery's board, where the day's draw
-- shows as it is rolled), "bones" (the Bones table's watch pane), "fight" (the fight's card, its
-- clock and its result as they come), "event" (a Fight Night's or a tournament's own pane); nil for
-- an event that is over or that this client does not know.
local WATCH = { lottery = "lottery", farkle = "bones", fight = "fight", card = "event", tourney = "event" }
function ArenaUI.WatchRoute(eid)
	if type(eid) ~= "string" or eid == "" then return nil end
	local ev = Data.Event(eid)
	if type(ev) ~= "table" or ev.over then return nil end
	local kind = WATCH[ev.kind or ""]
	return kind and { kind = kind, eid = eid } or nil
end
-- Opens it (the slip's button, My bets' line): true and the route's kind, or false.
function ArenaUI.WatchLive(eid)
	local r = ArenaUI.WatchRoute(eid)
	if not r then return false end
	if r.kind == "lottery" then Home.Open("lottery")
	elseif r.kind == "bones" then Home.Open("bone.live", eid)
	elseif r.kind == "fight" and ArenaUI.Card then ArenaUI.Card.Open(eid)
	else Home.Open("events", eid) end
	return true, r.kind
end

-- The crowd's bets on a Bones table (its MW market, 2026-10-04): a pick per player, { idx, o,
-- label, odds, open, pool, count, cur }, open while the market takes bets; nil when this client
-- heard none.
function ArenaUI.CrowdBets(eid)
	if type(eid) ~= "string" or eid == "" then return nil end
	local view = Data.Markets(eid)
	for _, mk in ipairs(type(view) == "table" and view.markets or {}) do
		if mk.type == "MW" then
			local out = {}
			local open = ArenaUI.MarketOpen(mk)
			for _, o in ipairs(mk.outcomes or {}) do
				out[#out + 1] = { idx = mk.idx, o = o.o, label = ns.Codec.Plain(tostring(o.label or o.o)), odds = tonumber(o.odds), open = open,
					pool = tonumber(o.pool) or 0, count = tonumber(o.count) or 0, cur = view.cur }
			end
			return #out > 0 and out or nil
		end
	end
	return nil
end
-- A market row takes bets: Markets.View's "O" (the sample data's "o"), or no state given.
function ArenaUI.MarketOpen(mk)
	local st = type(mk) == "table" and mk.state or nil
	return st == nil or st == "O" or st == "o"
end

---------------------------------------------------------------------------
-- The bet slip
---------------------------------------------------------------------------

local slip
local ss = {} -- the slip's state: eid, idx, o, sent
local function MakeSlip()
	local f = Kit.Frame("OlympusArenaSlip", 360, 380, { title = L.ARENA_SLIP_TITLE })
	f.head = Kit.Text(f, nil, "CENTER")
	f.head:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
	f.head:SetWidth(312)
	f.head:SetHeight(32) -- (two lines at most: the event, then the market and the pick)
	f.amount = Kit.Stepper(f, { width = 320, min = 1000, max = 1000, steps = Kit.STEPS, onChange = function() if f:IsShown() then ArenaUI.SlipRefresh() end end })
	f.amount:SetPoint("TOP", f.head, "BOTTOM", 0, -8)
	f.quote = Kit.Text(f, nil, "LEFT")
	f.quote:SetPoint("TOP", f.amount, "BOTTOM", 0, -12)
	f.quote:SetWidth(312)
	if f.quote.SetJustifyV then f.quote:SetJustifyV("TOP") end
	f.why = Kit.Text(f, nil, "LEFT")
	f.why:SetPoint("TOPLEFT", f.quote, "BOTTOMLEFT", 0, -6)
	f.why:SetWidth(312)
	f.rules = Kit.Text(f, "small", "LEFT")
	f.rules:SetPoint("BOTTOMLEFT", 24, 48)
	f.rules:SetWidth(312)
	f.rules:SetText(Kit.C("grey", L.ARENA_SLIP_RULES))
	f.place = Kit.Button(f, 150, 26, L.ARENA_SLIP_PLACE, nil)
	f.place:SetPoint("BOTTOMLEFT", 24, 14)
	f.cancel = Kit.Button(f, 150, 26, L.ARENA_CANCEL, function() f:Hide() end)
	f.cancel:SetPoint("BOTTOMRIGHT", -24, 14)
	return f
end

-- The slip's words (the tests read them): head, the quote's lines, the refusal.
function ArenaUI.SlipModel(eid, idx, o, silver)
	local m = { eid = eid, idx = idx, o = o, silver = silver }
	local ev = Data.Event(eid)
	local view = Data.Markets(eid)
	local mk
	for _, x in ipairs(type(view) == "table" and view.markets or {}) do if x.idx == idx then mk = x end end
	local label = o
	for _, oc in ipairs(mk and mk.outcomes or {}) do if oc.o == o then label = oc.label or oc.o end end
	m.cur = type(view) == "table" and view.cur or Cur()
	local who = ns.Codec.Plain(tostring(label or "?"))
	m.head = L.ARENA_SLIP_HEAD:format(ev and Home.EventTitle(ev) or "?", ns.Codec.Plain(tostring(mk and (mk.label or mk.type) or "?")), who)
	local q = Data.Quote(eid, idx, o, silver)
	m.quote = q
	local lines = {}
	if mk and mk.type == "LO" then lines[#lines + 1] = L.ARENA_LOTTERY_SLIP_RULES end
	if type(q) == "table" then
		if q.odds then lines[#lines + 1] = L.ARENA_SLIP_ODDS:format(("%.2fx"):format(q.odds)) end
		if q.payout then lines[#lines + 1] = L.ARENA_SLIP_PAYS:format(Kit.Money(q.payout, m.cur), who) end
		if type(q.fee) == "table" and (q.fee.g or q.fee.a) then
			lines[#lines + 1] = L.ARENA_SLIP_FEE:format(Kit.Money(q.fee.g or 0, m.cur), Kit.Money(q.fee.a or 0, m.cur))
		end
		if q.cap then lines[#lines + 1] = L.ARENA_SLIP_CAP:format(Kit.Money(q.cap, m.cur)) end
		if q.after then lines[#lines + 1] = L.ARENA_SLIP_AFTER:format(Kit.Money(q.after, m.cur)) end
	end
	m.lines = lines
	local ok, why = ns.Arena.Can("bet", eid, idx, o, silver)
	if why == "unknown" then ok, why = false, "missing" end
	if type(q) == "table" and q.ok == false and ok then ok, why = false, q.why end
	-- (The rules' yes is asked on the click: never a reason to grey the button.)
	m.ok, m.why = ok or why == "rules", why
	m.whyText = why and Kit.Why(why) or nil
	m.max = type(q) == "table" and tonumber(q.cap) or nil
	return m
end

function ArenaUI.SlipRefresh()
	local f = slip
	if not f or not ss.eid then return nil end
	local silver = math.floor((f.amount:Get() or 0) / 100)
	local m = ArenaUI.SlipModel(ss.eid, ss.idx, ss.o, silver)
	ArenaUI.lastSlip = m
	f.head:SetText((tostring(m.head or ""):gsub(" · ", "\n", 1))) -- (the event, then the market and the pick)
	f.quote:SetText(table.concat(m.lines, "\n"))
	f.why:SetText(m.whyText and not m.ok and Kit.C("red", m.whyText) or (ss.sent and Kit.C("green", ss.sent) or ""))
	-- (the slip as tall as its words: the head, the stepper, the quote, the reason, the rules line
	-- and the footer; never text under the footer, the owner's audit)
	local qh = tonumber(f.quote.GetStringHeight and f.quote:GetStringHeight() or 0) or 0
	local wh = tonumber(f.why.GetStringHeight and f.why:GetStringHeight() or 0) or 0
	local rh = tonumber(f.rules.GetStringHeight and f.rules:GetStringHeight() or 0) or 0
	if qh > 0 then f:SetHeight(math.max(380, math.ceil(184 + qh + 6 + wh + 12 + rh + 48 + 8))) end
	-- Sent: the button watches the event live instead (while it is not over).
	m.watch = ss.sent and ArenaUI.WatchRoute(ss.eid) or nil
	if m.watch then
		Kit.SetButton(f.place, L.ARENA_WATCH_LIVE, true)
		f.place:SetScript("OnClick", function() ArenaUI.WatchLive(ss.eid) end)
		return m
	end
	Kit.SetButton(f.place, L.ARENA_SLIP_PLACE, m.ok and not ss.sent, m.whyText)
	f.place:SetScript("OnClick", function()
		Kit.Sound("IG_MAINMENU_OPTION")
		local s = math.floor((f.amount:Get() or 0) / 100)
		local ok, why = ArenaUI.Commit("bet", ss.eid, ss.idx, ss.o, s)
		if ok then
			-- The bank's queue decides the wait: its length times Comm's pace.
			local C = ns.Comm
			local queue = C and C.QueueSize and C.QueueSize() or 0
			ss.sent = L.ARENA_SLIP_SENT:format(math.max(2, math.ceil((queue + 1) * 1.2)))
			ArenaUI.SlipRefresh()
		elseif why and why ~= "rules" then
			f.why:SetText(Kit.C("red", Kit.Why(why)))
		end
	end)
	return m
end

-- Opens the slip on a market's outcome (a Bet button).
function ArenaUI.Slip(eid, idx, o)
	slip = slip or MakeSlip()
	ss.eid, ss.idx, ss.o, ss.sent = eid, idx, o, nil
	PlaceBeside(slip)
	local q = Data.Quote(eid, idx, o, 10)
	local w = Data.Wallet() or {}
	local bal = type(w.g) == "table" and tonumber(w.g.bal) or 0
	local cap = type(q) == "table" and tonumber(q.cap) or nil
	local hi = math.max(1000, math.min(cap or bal, bal > 0 and bal or (cap or 1000)))
	slip.amount:SetRange(100, hi, type(q) == "table" and q.cur or Cur())
	slip:Show()
	ArenaUI.SlipRefresh()
	return slip
end
function ArenaUI.SlipFrame() return slip end

---------------------------------------------------------------------------
-- The wallet
---------------------------------------------------------------------------

local wallet
local ws = { part = "deposit" } -- the wallet's state: the part in view
local PARTS = { { "deposit", "ARENA_WALLET_DEPOSIT" }, { "withdraw", "ARENA_WALLET_WITHDRAW" }, { "ledger", "ARENA_WALLET_LEDGER" }, { "bets", "ARENA_WALLET_BETS" } }
local function WalletBank(w)
	local wanted = type(w) == "table" and w.recommended
	if type(wanted) == "string" then
		for _, b in ipairs(type(w.banks) == "table" and w.banks or {}) do
			if b.name and ns.FullName(b.name):lower() == ns.FullName(wanted):lower() then return b end
		end
	end
	for _, b in ipairs(type(w) == "table" and w.banks or {}) do if b.online then return b end end
	return type(w) == "table" and w.banks and w.banks[1] or nil
end
-- The wallet's words (the tests read them): { summary, bank, debts, ledger, bets }.
function ArenaUI.WalletModel()
	local w = Data.Wallet() or {}
	local m = { cur = w.cur or Cur() }
	local g = type(w.g) == "table" and w.g or {}
	m.summary = L.ARENA_WALLET_SUMMARY:format(Kit.Money(g.bal or 0, m.cur), Kit.Money(g.escrow or 0, m.cur), Kit.Money(w.pending or 0, m.cur))
	local p = type(w.p) == "table" and w.p or {}
	if (tonumber(p.bal) or 0) > 0 then m.summary = m.summary .. " · " .. Kit.Money(p.bal, "p") end
	local b = WalletBank(w)
	m.bankName = b and b.name
	if not b then
		m.bank = L.ARENA_WALLET_NO_BANK
	elseif b.online then
		m.bank = L.ARENA_WALLET_BANK_ON:format(Kit.Name(b.name), b.paused and L.ARENA_WALLET_PAUSED or L.ARENA_WALLET_ACCEPTING)
	else
		m.bank = L.ARENA_WALLET_BANK_OFF:format(Kit.Name(b.name))
	end
	m.debts = {}
	for _, d in ipairs(w.debts or {}) do
		local owed = (tonumber(d.copper) or 0) - (tonumber(d.paid) or 0)
		m.debts[#m.debts + 1] = L.ARENA_WALLET_DEBT:format(Kit.Money(owed, m.cur), Kit.Name(d.creditor == "G" and L.ARENA_THE_GUILD or d.creditor))
	end
	if w.blocked then m.debts[#m.debts + 1] = L.ARENA_WALLET_BLOCKED end
	m.ledger = {}
	for i = #(w.receipts or {}), 1, -1 do
		local r = w.receipts[i]
		if type(r) == "table" and #m.ledger < 30 then
			local when = r.t and date and date("%m-%d %H:%M", r.t) or ""
			m.ledger[#m.ledger + 1] = ("%s  %s %s  %s"):format(when, L["ARENA_RECEIPT_" .. tostring(r.kind or r.how or "x"):upper()] or tostring(r.kind or ""),
				Kit.Money(tonumber(r.copper) or 0, m.cur), L["ARENA_RECEIPT_STATE_" .. tostring(r.state or ""):upper()] or tostring(r.state or ""))
		end
	end
	-- My bets, each line's open bet with its Watch live (m.watch[i]: its route, or nil).
	m.bets, m.watch = {}, {}
	local open = {}
	for _, t in ipairs(Data.Tickets({ open = true }) or {}) do if type(t) == "table" and t.id then open[t.id] = true end end
	for _, t in ipairs(Data.Tickets({ mine = true }) or {}) do
		if type(t) == "table" then
			local ev = t.eid and Data.Event(t.eid)
			m.bets[#m.bets + 1] = ("%s  %s  %s"):format(ev and Home.EventTitle(ev) or tostring(t.eid or "?"), ns.Codec.Plain(tostring(t.label or t.o or "")),
				Kit.Money(tonumber(t.copper) or (tonumber(t.silver) or 0) * 100, m.cur))
			m.watch[#m.bets] = t.id and open[t.id] and not t.settled and ArenaUI.WatchRoute(t.eid) or nil
		end
	end
	m.balance = tonumber(g.bal) or 0
	return m
end

local function MakeWallet()
	local f = Kit.Frame("OlympusArenaWallet", 460, 470, { title = L.ARENA_WALLET_TITLE })
	f.summary = Kit.Text(f, nil, "CENTER")
	f.summary:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
	f.summary:SetWidth(420)
	f.bank = Kit.Text(f, nil, "CENTER")
	f.bank:SetPoint("TOP", f.summary, "BOTTOM", 0, -4)
	f.bank:SetWidth(420)
	f.debts = Kit.Text(f, nil, "CENTER")
	f.debts:SetPoint("TOP", f.bank, "BOTTOM", 0, -4)
	f.debts:SetWidth(420)
	local labels = {}
	for _, p in ipairs(PARTS) do labels[#labels + 1] = { p[1], L[p[2]] } end
	f.parts = Kit.Choices(f, labels, 100, function(key) ws.part = key Kit.Remember("wallet.part", key) ArenaUI.WalletRefresh() end)
	f.parts:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -118)
	-- Deposit and withdraw: the amount, then the ways.
	f.amount = Kit.Stepper(f, { width = 400, min = 1000, max = 1000000 })
	f.amount:SetPoint("TOP", f, "TOP", 0, -156)
	f.trade = Kit.Button(f, 130, 26, L.ARENA_WALLET_BY_TRADE, nil)
	f.trade:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -246)
	f.mail = Kit.Button(f, 130, 26, L.ARENA_WALLET_BY_MAIL, nil)
	f.mail:SetPoint("LEFT", f.trade, "RIGHT", 8, 0)
	f.fill = Kit.Button(f, 130, 26, Kit.FillLabel(), nil)
	f.fill:SetPoint("LEFT", f.mail, "RIGHT", 8, 0)
	f.withdraw = Kit.Button(f, 150, 26, L.ARENA_WALLET_WITHDRAW, nil)
	f.withdraw:SetPoint("TOP", f, "TOP", 0, -246)
	f.how = Kit.Text(f, nil, "LEFT")
	f.how:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -282)
	f.how:SetWidth(388)
	if f.how.SetJustifyV then f.how:SetJustifyV("TOP") end
	f.list = Kit.List(f, 400, 250)
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -152)
	return f
end

-- A deposit started (its id, from the wallet's action): Fill fills the trade or the mail.
local deposit
function ArenaUI.WalletRefresh()
	local f = wallet
	if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then
		if f then f:Hide() end
		return
	end
	if not f then return nil end
	local m = ArenaUI.WalletModel()
	ArenaUI.lastWallet = m
	f.summary:SetText(m.summary)
	f.bank:SetText(m.bank)
	f.debts:SetText(#m.debts > 0 and Kit.C("red", table.concat(m.debts, "\n")) or "")
	local part = ws.part or "deposit"
	f.parts:Select(part)
	local money = part == "deposit" or part == "withdraw"
	f.amount:SetShown(money)
	f.trade:SetShown(part == "deposit")
	f.mail:SetShown(part == "deposit")
	f.fill:SetShown(part == "deposit")
	f.withdraw:SetShown(part == "withdraw")
	f.how:SetShown(money)
	f.list:SetShown(not money)
	local mode = ModeNow()
	local bank = m.bankName
	if part == "deposit" then
		f.amount:SetRange(100, 10000000, m.cur ~= "c" and m.cur or nil)
		for _, way in ipairs({ { f.trade, "t" }, { f.mail, "m" } }) do
			local button, how = way[1], way[2]
			local ok, why = ns.Arena.Can("wallet.deposit", bank, how, f.amount:Get(), mode)
			if why == "unknown" then ok, why = false, "missing" end
			Kit.SetButton(button, nil, ok or why == "rules", Kit.Why(why))
			button:SetScript("OnClick", function()
				local id, w = ArenaUI.Commit("wallet.deposit", bank, how, f.amount:Get(), mode)
				if id then
					deposit = { id = id, how = how, bank = bank, copper = f.amount:Get() }
					f.how:SetText(how == "t" and L.ARENA_WALLET_TRADE_HOW:format(Kit.Name(bank)) or L.ARENA_WALLET_MAIL_HOW)
				elseif w and w ~= "rules" then
					f.how:SetText(Kit.C("red", Kit.Why(w)))
				end
				ArenaUI.WalletRefresh()
			end)
		end
		Kit.SetButton(f.fill, Kit.FillLabel(), deposit ~= nil, L.ARENA_WALLET_FILL_FIRST)
		f.fill:SetScript("OnClick", function()
			if not deposit then return end
			local ok, why = ns.Arena.Do("wallet.fill", deposit.id, mode)
			if not ok and why then f.how:SetText(Kit.C("red", Kit.Why(why))) end
		end)
		if not deposit then f.how:SetText(L.ARENA_WALLET_DEPOSIT_HOW) end
	elseif part == "withdraw" then
		f.amount:SetRange(100, math.max(100, m.balance), m.cur ~= "c" and m.cur or nil)
		local ok, why = ns.Arena.Can("wallet.withdraw", bank, f.amount:Get(), mode)
		if why == "unknown" then ok, why = false, "missing" end
		Kit.SetButton(f.withdraw, L.ARENA_WALLET_WITHDRAW, ok and m.cur ~= "c", Kit.Why(m.cur == "c" and "chips" or why))
		f.withdraw:SetScript("OnClick", function()
			local copper = f.amount:Get()
			Kit.Confirm(L.ARENA_WALLET_WITHDRAW_ASK:format(Kit.Money(copper, m.cur), Kit.Name(bank)), function()
				local done, w = ArenaUI.Commit("wallet.withdraw", bank, copper, mode)
				f.how:SetText(done and L.ARENA_WALLET_WITHDRAW_SENT or Kit.C("red", Kit.Why(w)))
			end)
		end)
		f.how:SetText(L.ARENA_WALLET_WITHDRAW_HOW)
	elseif part == "ledger" then
		local lines = {}
		if #m.ledger == 0 then lines[1] = { text = Kit.C("grey", L.ARENA_WALLET_LEDGER_NONE) } end
		for _, l in ipairs(m.ledger) do lines[#lines + 1] = { text = l } end
		f.list:SetLines(lines)
	else
		local lines = {}
		if #m.bets == 0 then lines[1] = { text = Kit.C("grey", L.ARENA_WALLET_BETS_NONE) } end
		for i, l in ipairs(m.bets) do
			local route = m.watch[i]
			local eid = route and route.eid
			lines[#lines + 1] = { text = l, right = route and Kit.C("gold", L.ARENA_WATCH_LIVE) or nil,
				onClick = route and function() ArenaUI.WatchLive(eid) end or nil }
		end
		f.list:SetLines(lines)
		m.lines = lines
	end
	return m
end

-- Opens the wallet (on its bets with "bets").
function ArenaUI.Wallet(part)
	if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then
		if wallet then wallet:Hide() end
		return false
	end
	wallet = wallet or MakeWallet()
	ws.part = part or Kit.Recall("wallet.part", "deposit")
	PlaceBeside(wallet)
	wallet:Show()
	ArenaUI.WalletRefresh()
	return wallet
end
function ArenaUI.WalletFrame() return wallet end
ns.On("ARENA_CHANGED", function() if wallet and wallet:IsShown() then ns.SafeCall("arena wallet", ArenaUI.WalletRefresh) end end)

---------------------------------------------------------------------------
-- The challenge
---------------------------------------------------------------------------

local challenge
local cs = {} -- the challenge's state: name, from, kind, how, bo, arbiter
local function MakeChallenge()
	local f = Kit.Frame("OlympusArenaChallengeDialog", 440, 500, { title = L.ARENA_CHALLENGE_DIALOG })
	f.who = Kit.Text(f, "title", "CENTER")
	f.who:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
	f.who:SetWidth(400)
	f.target = Kit.Button(f, 130, 24, L.ARENA_USE_TARGET, function()
		if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
			cs.name = ns.UnitFullName("target")
			ArenaUI.ChallengeRefresh()
		else
			ArenaUI.Say(L.ARENA_NO_TARGET)
		end
	end)
	f.target:SetPoint("TOP", f.who, "BOTTOM", 0, -6)
	f.kind = Kit.Choices(f, { { "c", L.ARENA_KIND_CASUAL }, { "s", L.ARENA_KIND_STAKED } }, 120, function(k) cs.kind = k Kit.Remember("challenge.kind", k) ArenaUI.ChallengeRefresh() end)
	f.kind:SetPoint("TOPLEFT", f, "TOPLEFT", 90, -110)
	f.amount = Kit.Stepper(f, { width = 400, min = 1000, max = 1000, onChange = function() if f:IsShown() then ArenaUI.ChallengeRefresh(true) end end })
	f.amount:SetPoint("TOP", f, "TOP", 0, -142)
	f.how = Kit.Choices(f, { { "d", L.ARENA_HOW_DIRECT }, { "a", L.ARENA_HOW_ARBITER } }, 150, function(k) cs.how = k Kit.Remember("challenge.how", k) ArenaUI.ChallengeRefresh() end)
	f.how:SetPoint("TOPLEFT", f, "TOPLEFT", 66, -230)
	f.bo = Kit.Choices(f, { { 1, L.ARENA_BO_1 }, { 3, L.ARENA_BO_3 }, { 5, L.ARENA_BO_5 } }, 80, function(k) cs.bo = k Kit.Remember("challenge.bo", k) ArenaUI.ChallengeRefresh() end)
	f.bo:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -260)
	f.list = Kit.List(f, 390, 100)
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -290)
	f.note = Kit.Text(f, "small", "LEFT")
	f.note:SetPoint("BOTTOMLEFT", 26, 50)
	f.note:SetWidth(390)
	f.send = Kit.Button(f, 160, 26, L.ARENA_CHALLENGE_SEND, nil)
	f.send:SetPoint("BOTTOMLEFT", 26, 14)
	f.cancel = Kit.Button(f, 160, 26, L.ARENA_CANCEL, function() f:Hide() end)
	f.cancel:SetPoint("BOTTOMRIGHT", -26, 14)
	return f
end

-- The challenge as it would go (the tests read it): { name, stake, how, arbiter, bo, from, cur,
-- ok, why, arbiters }.
function ArenaUI.ChallengeModel()
	local f = challenge
	if not f then return nil end
	local staked = cs.kind == "s"
	-- (No arbiters while no wager may happen, ArenaHome.ArbitersOn: a challenge is direct then.)
	local how = Home.ArbitersOn() and cs.how or "d"
	local m = { name = cs.name, stake = staked and f.amount:Get() or 0, how = how or "d", arbiter = how == "a" and cs.arbiter or nil,
		bo = tonumber(cs.bo) or 1, from = cs.from, cur = Cur() }
	local opts = { stake = m.stake, how = m.how, arbiter = m.arbiter, bo = m.bo, from = m.from, cur = m.cur }
	m.opts = opts
	if not m.name then
		m.ok, m.why = false, "opponent"
	else
		local ok, why = ns.Arena.Can("fights.challenge", m.name, opts)
		if why == "unknown" then ok, why = false, "missing" end
		if staked and m.how == "a" and not m.arbiter then ok, why = false, "arbiter" end
		m.ok, m.why = ok or why == "rules", why
	end
	m.arbiters = Data.Arbiters() or {}
	return m
end

function ArenaUI.ChallengeRefresh(amountOnly)
	local f = challenge
	if not f then return nil end
	local m = ArenaUI.ChallengeModel()
	ArenaUI.lastChallenge = m
	f.who:SetText(m.name and L.ARENA_CHALLENGE_WHO:format(Kit.Name(m.name)) or L.ARENA_CHALLENGE_PICK)
	local staked = cs.kind == "s"
	-- The free challenge has no hidden wager-sized gaps. Keep the supported staked sheet intact.
	f:SetHeight(staked and 500 or 310)
	f.bo:SetPoint("TOPLEFT", f, "TOPLEFT", 100, staked and -260 or -160)
	-- (1.1.6: Staked waits for the compliance gate: greyed, its line in the tooltip and the note.)
	local C = ns.Compliance
	local wait = type(C) == "table" and type(C.Waits) == "function" and C.Waits("stake", "fight") or nil
	if not amountOnly then
		Kit.SetButton(f.kind.buttons[2], nil, wait == nil, wait)
		f.kind:Select(cs.kind or "c")
		f.how:Select(cs.how or "d")
		f.bo:Select(cs.bo or 1)
		f.amount:SetShown(staked)
		f.how:SetShown(staked and Home.ArbitersOn())
		local cap = Data.Cap(m.how == "d" and "direct" or "bet")
		f.amount:SetRange(1000, math.max(1000, cap or 1000000), m.cur)
		local lines = {}
		if staked and m.how == "a" then
			lines[#lines + 1] = { header = true, text = L.ARENA_FIND_ARBITER }
			if #m.arbiters == 0 then lines[#lines + 1] = { text = Kit.C("grey", L.ARENA_NO_ARBITERS) } end
			for _, a in ipairs(m.arbiters) do
				local name = a.name
				local state = not a.online and L.ARENA_OFFLINE or (a.free and L.ARENA_FREE or L.ARENA_BUSY)
				local zone = a.zone and (C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, a.zone)) or nil)
				local zoneName = type(zone) == "table" and zone.name or nil
				local text = Kit.Name(name) .. (zoneName and (" · " .. zoneName) or "")
				if cs.arbiter and ns.FullName(cs.arbiter):lower() == ns.FullName(name):lower() then text = Kit.C("blue", "> ") .. text end
				lines[#lines + 1] = { text = text, right = state, indent = 1, onClick = a.online and a.free and function()
					cs.arbiter = name
					ArenaUI.ChallengeRefresh()
				end or nil }
			end
		end
		f.list:SetShown(#lines > 0)
		f.list:SetLines(lines)
	end
	local note = {}
	if wait then note[#note + 1] = Kit.C("grey", wait) end
	if staked then note[#note + 1] = L.ARENA_CHALLENGE_CUR:format(L["ARENA_CUR_" .. tostring(m.cur):upper()] or m.cur) end
	if staked and m.how == "d" then note[#note + 1] = L.ARENA_DIRECT_NOTE end
	if m.from then note[#note + 1] = L.ARENA_MATCHED_NOTE end
	if not m.ok and m.why then note[#note + 1] = Kit.C("red", Kit.Why(m.why)) end
	f.note:SetText(table.concat(note, "\n"))
	Kit.SetButton(f.send, L.ARENA_CHALLENGE_SEND, m.ok, Kit.Why(m.why))
	f.send:SetScript("OnClick", function()
		local cur = ArenaUI.ChallengeModel()
		local ok, why = ArenaUI.Commit("fights.challenge", cur.name, cur.opts)
		if ok then
			f:Hide()
			Home.Toast(L.ARENA_CHALLENGE_SENT:format(Kit.Name(cur.name)))
		elseif why and why ~= "rules" then
			f.note:SetText(Kit.C("red", Kit.Why(why)))
		end
	end)
	return m
end

-- Opens the challenge on a name (the menu, the person card, a match's hand-off: prefill = { stake,
-- from, how, arbiter }); with none, the target's (Use target) or a name to pick.
function ArenaUI.Challenge(name, prefill)
	challenge = challenge or MakeChallenge()
	local f = challenge
	prefill = type(prefill) == "table" and prefill or {}
	if (not name or name == "") and UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") and not (UnitIsUnit and UnitIsUnit("target", "player")) then
		name = ns.UnitFullName("target")
	end
	cs.name = name and name ~= "" and ns.FullName(name) or nil
	cs.from = prefill.from
	local stake = tonumber(prefill.stake) or 0
	cs.kind = stake > 0 and "s" or Kit.Recall("challenge.kind", "c")
	-- (A stake waits for the compliance gate: the challenge opens casual.)
	local C = ns.Compliance
	if type(C) == "table" and type(C.Waits) == "function" and C.Waits("stake", "fight") then cs.kind, stake = "c", 0 end
	cs.how = prefill.how or Kit.Recall("challenge.how", "d")
	cs.bo = Kit.Recall("challenge.bo", 1)
	cs.arbiter = prefill.arbiter
	PlaceBeside(f)
	f:Show()
	ArenaUI.ChallengeRefresh()
	if stake > 0 then f.amount:Set(stake) end
	return f
end
function ArenaUI.ChallengeFrame() return challenge end

---------------------------------------------------------------------------
-- Find an opponent (the design)
---------------------------------------------------------------------------

local find
local function Match() return ns.ArenaMatch end
-- A window holding the sheet hears when the sheet shows or hides there (the Bones window's Escape
-- and its other parts): its OnShow and OnHide, and a sheet already shown that changes window (Host).
local function FindTold(h, f, shown)
	local fn = type(h) == "table" and rawget(h, "hostChanged")
	if type(fn) == "function" then ns.SafeCall("arena find host", fn, f, shown) end
end
local FIND_W, FIND_H = 460, 476
local function MakeFind()
	local f = Kit.Frame("OlympusArenaFind", FIND_W, FIND_H, { title = L.ARENA_FIND_TITLE })
	-- (y down from the sheet's top; from the level row on, from its mark f.below, below)
	local y, base, by = -54, f, 0
	local function Row(label, choices, width, key)
		local t = Kit.Text(f, nil, "LEFT")
		t:SetPoint("TOPLEFT", base, "TOPLEFT", 26, y - by - 4)
		t:SetWidth(90)
		t:SetText(label)
		local row = Kit.Choices(f, choices, width, function(k) f.opts[key] = k Kit.Remember("find." .. key, k) ArenaUI.FindRefresh() end)
		row.label = t
		row:SetPoint("TOPLEFT", base, "TOPLEFT", 120, y - by)
		y = y - 30
		return row
	end
	f.opts = {}
	f.kind = Row(L.ARENA_FIND_KIND, { { "c", L.ARENA_KIND_CASUAL }, { "s", L.ARENA_KIND_STAKED }, { "e", L.ARENA_FIND_EITHER } }, 100, "kind")
	f.lo = Kit.Stepper(f, { width = 200, min = 0, max = 0, box = false, steps = { 1000, 10000, 100000 } })
	f.lo:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y - 2)
	f.hi = Kit.Stepper(f, { width = 200, min = 0, max = 0, box = false, steps = { 1000, 10000, 100000 } })
	f.hi:SetPoint("TOPLEFT", f, "TOPLEFT", 236, y - 2)
	y = y - (Kit.STEPPER_H + 6)
	-- What comes under the amounts hangs from this mark: in a window that holds the sheet (the
	-- Bones window's, shorter than the sheet on its own) it moves up while the amounts are hidden,
	-- so the words keep their room above the buttons (FindRefresh).
	f.below = CreateFrame("Frame", nil, f)
	f.below:SetSize(1, 1)
	f.below:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	f.belowY = y
	base, by = f.below, y
	f.level = Row(L.ARENA_FIND_LEVEL, { { 0, L.ARENA_FIND_ANY }, { 5, L.ARENA_FIND_PM5 }, { 10, L.ARENA_FIND_PM10 } }, 100, "level")
	f.reach = Row(L.ARENA_FIND_REACH, { { "z", L.ARENA_FIND_NEARBY }, { "c", L.ARENA_FIND_CONTINENT } }, 150, "reach")
	-- Let others find me: the switch and what for.
	f.findable = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.findable:SetSize(24, 24)
	f.findable:SetPoint("TOPLEFT", base, "TOPLEFT", 22, y - by - 4)
	f.findableText = Kit.Text(f, nil, "LEFT")
	f.findableText:SetPoint("LEFT", f.findable, "RIGHT", 4, 0)
	f.findableText:SetText(L.ARENA_FIND_ME)
	f.findable:SetScript("OnClick", function(self) ArenaUI.SetFindable(self:GetChecked() and true or false) end)
	y = y - 28
	f.prefs = {}
	local prev
	for i, p in ipairs({ { "d", L.ARENA_FIND_DUELS }, { "b", L.ARENA_SECTION_BONE }, { "staked", L.ARENA_FIND_STAKED_TOO } }) do
		local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		if prev then cb:SetPoint("LEFT", prev.text, "RIGHT", 12, 0) else cb:SetPoint("TOPLEFT", base, "TOPLEFT", 44, y - by) end
		cb.text = Kit.Text(f, "small", "LEFT")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetText(p[2])
		cb.key = p[1]
		cb:SetScript("OnClick", function() ArenaUI.SetFindable(f.findable:GetChecked() and true or false) end)
		f.prefs[i] = cb
		prev = cb
	end
	y = y - 30
	f.line = Kit.Text(f, "small", "LEFT")
	f.lineAt = { 26, y - by } -- (under the rows, from the mark; beside them on a wide sheet: Words)
	f.line:SetPoint("TOPLEFT", base, "TOPLEFT", f.lineAt[1], f.lineAt[2])
	f.line:SetWidth(FIND_W - 52)
	if f.line.SetJustifyV then f.line:SetJustifyV("TOP") end
	f.share = Kit.Button(f, 200, 24, L.ARENA_FIND_SHARE_WHILE, function() f.opts.share = true ArenaUI.FindRefresh() end)
	f.share:SetPoint("BOTTOMLEFT", 26, 46)
	f.sharing = Kit.Button(f, 200, 24, L.ARENA_FIND_SHARE_ON, function()
		local Ly = ns.Layers
		if Ly and Ly.SetSharing then pcall(Ly.SetSharing, true) end
		ArenaUI.FindRefresh()
	end)
	f.sharing:SetPoint("LEFT", f.share, "RIGHT", 8, 0)
	f.go = Kit.Button(f, 170, 26, L.ARENA_FIND_SEARCH, nil)
	f.go:SetPoint("BOTTOMLEFT", 26, 14)
	f.stop = Kit.Button(f, 170, 26, L.ARENA_FIND_STOP, function()
		-- (in the Bones window with nothing to stop: Cancel, the window back as it was)
		if rawget(f, "cancels") then f:Hide() return end
		local AM = Match()
		if AM and AM.Stop then AM.Stop() end
		ArenaUI.FindRefresh()
	end)
	f.stop:SetPoint("BOTTOMRIGHT", -26, 14)
	-- Its host hears when it shows or hides (the Bones window's Escape and components).
	f:HookScript("OnShow", function(self) FindTold(rawget(self, "host"), self, true) end)
	f:HookScript("OnHide", function(self) FindTold(rawget(self, "host"), self, false) end)
	return f
end

-- The Bones window's own Find (the owner on test 32: "instead of opening over the window, as a
-- component, it leaves the window"): opened from that window (its Start Playing; any Bones Find
-- while it is open, ArenaUI.BonesHost), the sheet is one of its components: parented to it, centred
-- in it, a level above its introduction, as tall as fits inside it. Its X, Cancel and Escape give
-- the window back as it was; a search that goes out hands over to the match's card, there too.
-- Opened from anywhere else it is the arena's own pop-up again, beside the betting window.
-- In a window as wide as the Bones window (800 px) it is wider (FIND_WIDE, clear of the window's
-- corners, where its X is), and its words go beside the rows in a column of their own (Words):
-- shorter than on its own (432 of 476 px), the sheet has no room under the rows for the longest
-- of them (a staked search's, the first one, location sharing off), which ran under Share while
-- searching and Search. The rows end 436 px from the sheet's left (the higher amount's stepper).
local HOST_GAP, FIND_WIDE, CORNER, WORDS_X, WORDS_TOP = 12, 720, 40, 450, -54
local function Words(f, beside)
	f.wordsBeside = beside
	f.line:ClearAllPoints()
	if beside then
		f.line:SetPoint("TOPLEFT", f, "TOPLEFT", WORDS_X, WORDS_TOP)
		f.line:SetWidth((tonumber(f:GetWidth()) or FIND_WIDE) - WORDS_X - 26)
	else
		f.line:SetPoint("TOPLEFT", f.below, "TOPLEFT", f.lineAt[1], f.lineAt[2] + (f.opts.game == "b" and 30 or 0))
		f.line:SetWidth(FIND_W - 52)
	end
end
local function Host(f, host, level)
	local old = rawget(f, "host")
	if host then
		f.host = host
		f:SetParent(host)
		local strata = host.GetFrameStrata and host:GetFrameStrata()
		if strata then f:SetFrameStrata(strata) end
		f:SetFrameLevel((tonumber(host:GetFrameLevel()) or 0) + (tonumber(level) or 60))
		local hh, hw = tonumber(host:GetHeight()) or 0, tonumber(host:GetWidth()) or 0
		f:SetHeight(hh >= 300 + 2 * HOST_GAP and math.min(FIND_H, hh - 2 * HOST_GAP) or FIND_H)
		local wide = hw >= FIND_WIDE + 2 * CORNER
		f:SetWidth(wide and FIND_WIDE or FIND_W)
		Words(f, wide)
		f:ClearAllPoints()
		f:SetPoint("CENTER", host, "CENTER", 0, 0)
	else
		if old then
			f.host = nil
			f:SetParent(UIParent)
			f:SetFrameStrata("DIALOG")
		end
		f:SetSize(FIND_W, FIND_H)
		Words(f, false)
		PlaceBeside(f)
	end
	f.fullHeight = f:GetHeight()
	-- A sheet already shown that changes window: its Show() next fires no OnShow, so each window
	-- hears it here (the one it left, then the one it is in now).
	if old ~= host and f:IsShown() then
		FindTold(old, f, false)
		FindTold(host, f, true)
	end
end

-- The terms as ArenaMatch.Start takes them.
function ArenaUI.FindOpts()
	local f = find
	local o = f and f.opts or {}
	return { game = o.game or "d", kind = o.kind or "c", lo = f and f.lo:Get() or 0, hi = f and f.hi:Get() or 0, level = o.game == "b" and 0 or (tonumber(o.level) or 5),
		reach = o.reach or "z", share = o.share == true }
end
function ArenaUI.SetFindable(on)
	local f = find
	local AM = Match()
	if not (f and AM and AM.SetFindable) then return false end
	local prefs = {}
	for _, cb in ipairs(f.prefs) do prefs[cb.key] = cb:GetChecked() and true or false end
	AM.SetFindable(on, prefs)
	ArenaUI.FindRefresh()
	return true
end
-- The dialog's words (the tests read them): { view, line, ok, why, stakedOk }.
function ArenaUI.FindRefresh()
	local f = find
	if not f then return nil end
	local AM = Match()
	local view = AM and AM.View and select(2, pcall(AM.View)) or nil
	if type(view) ~= "table" then view = {} end
	local o = ArenaUI.FindOpts()
	f.kind:Select(o.kind)
	f.level:Select(o.level)
	f.level:SetShown(o.game ~= "b")
	f.level.label:SetShown(o.game ~= "b")
	f.reach:Select(o.reach)
	-- Staked: offered only when the challenge's or the table's own check says yes (the design).
	local stakedOk, stakedWhy = false, nil
	for _, g in ipairs(o.game == "e" and { "d", "b" } or { o.game }) do
		local s = type(view.staked) == "table" and view.staked[g]
		if s and s.ok then stakedOk = true elseif s then stakedWhy = stakedWhy or s.text end
	end
	local staked = o.kind ~= "c"
	local max = tonumber(view.stakeMax) or 1000000
	f.lo:SetShown(staked)
	f.hi:SetShown(staked)
	-- Hidden amounts and Bones' hidden level filter leave no reserved blank rows, including
	-- the standalone search opened from the main Games lobby.
	local up = not staked and (Kit.STEPPER_H + 6) or 0
	local levelUp = o.game == "b" and 30 or 0
	f.below:ClearAllPoints()
	f.below:SetPoint("TOPLEFT", f, "TOPLEFT", 0, f.belowY + up)
	f.reach.buttons[1]:ClearAllPoints()
	f.reach:SetPoint("TOPLEFT", f.below, "TOPLEFT", 120, -30 + levelUp)
	f.reach.label:ClearAllPoints()
	f.reach.label:SetPoint("TOPLEFT", f.below, "TOPLEFT", 26, -34 + levelUp)
	f.findable:ClearAllPoints()
	f.findable:SetPoint("TOPLEFT", f.below, "TOPLEFT", 22, -64 + levelUp)
	f.prefs[1]:ClearAllPoints()
	f.prefs[1]:SetPoint("TOPLEFT", f.below, "TOPLEFT", 44, -88 + levelUp)
	Words(f, f.wordsBeside == true)
	if staked then
		f.lo:SetRange(0, max)
		f.hi:SetRange(0, max)
	end
	local fs = type(view.findable) == "table" and view.findable or {}
	f.findable:SetChecked(fs.on == true)
	for _, cb in ipairs(f.prefs) do
		if cb.key == "staked" then cb:SetChecked(fs.staked == true) else cb:SetChecked(not (type(fs.games) == "table" and fs.games[cb.key] == false)) end
	end
	local lines = {}
	if view.firstTime and view.firstLine then lines[#lines + 1] = ns.Codec.Plain(view.firstLine) end
	if view.rehearsal then lines[#lines + 1] = ns.Codec.Plain(view.rehearsal) end
	if staked and not stakedOk and stakedWhy then lines[#lines + 1] = Kit.C("red", ns.Codec.Plain(stakedWhy)) end
	if view.line then lines[#lines + 1] = Kit.C("blue", ns.Codec.Plain(view.line)) end
	if not AM then lines[#lines + 1] = Kit.C("red", L.ARENA_FIND_MISSING) end
	local can = type(view.can) == "table" and view.can or {}
	if can.ok == false and can.text then lines[#lines + 1] = Kit.C("red", ns.Codec.Plain(can.text)) end
	f.line:SetText(table.concat(lines, "\n"))
	local notSharing = view.sharing == false
	f.share:SetShown(notSharing and not o.share)
	f.sharing:SetShown(notSharing)
	if not staked then
		local rowsBottom = -(f.belowY + up) + 88 - levelUp + 22
		local wordsTop = f.wordsBeside and -WORDS_TOP or -(f.belowY + up + f.lineAt[2] + levelUp)
		local wordsHeight = tonumber(f.line:GetStringHeight()) or 0
		-- One row of actions, plus the optional sharing row. Wrapped privacy/reason text
		-- decides the height; the old 476 px was mostly empty when filters were hidden.
		f:SetHeight(math.ceil(math.max(rowsBottom, wordsTop + wordsHeight) + (notSharing and 86 or 54)))
	else
		f:SetHeight(f.fullHeight or FIND_H)
	end
	local busy = view.state == "search" or view.state == "match" or view.state == "popup"
	local ok = AM ~= nil and (can.ok ~= false or (notSharing and o.share)) and not busy and (not staked or stakedOk or o.kind == "e")
	Kit.SetButton(f.go, L.ARENA_FIND_SEARCH, ok, can.text or stakedWhy or (AM and nil or L.ARENA_FIND_MISSING))
	f.go:SetScript("OnClick", function()
		if f.opts.game == "b" and ns.FarkleTable then
			if not ns.FarkleTable.CanPlayPlayers() then f.line:SetText(L.FARKLE_LOBBY_FIRST); return false end
			if not ns.FarkleTable.CanOpen() then f.line:SetText(L.FARKLE_LOG_TAVERN_REST); return false end
		end
		local okStart, why = AM.Start(ArenaUI.FindOpts())
		if not okStart and why then
			local text = AM.WhyText and AM.WhyText(why) or Kit.Why(why)
			f.line:SetText(Kit.C("red", ns.Codec.Plain(tostring(text))))
		elseif okStart and rawget(f, "host") then
			-- (the search's card, in the same window, carries it from here)
			f:Hide()
		else
			ArenaUI.FindRefresh()
		end
	end)
	f.cancels = rawget(f, "host") ~= nil and not busy or nil
	Kit.SetButton(f.stop, f.cancels and L.ARENA_CANCEL or L.ARENA_FIND_STOP, busy or f.cancels == true)
	local m = { view = view, line = f.line:GetText(), ok = ok, stakedOk = stakedOk, opts = o }
	ArenaUI.lastFind = m
	return m
end

-- Arena and Bones each open their own compact, fixed-game search. The wire can still match
-- older clients' "either" searches, but this entry does not mix two different challenge flows.
-- host: the window to show it in (the Bones window's Start Playing passes its own); none: the
-- Bones window while it is open, for a Bones search (ArenaUI.BonesHost), else its own place.
function ArenaUI.OpenFind(game, host)
	if game == "b" and ns.FarkleTable then
		if not ns.FarkleTable.CanPlayPlayers() then ArenaUI.Say(L.FARKLE_LOBBY_FIRST); return false, "training" end
		if not ns.FarkleTable.CanOpen() then ArenaUI.Say(L.FARKLE_LOG_TAVERN_REST); return false, "tavern-rest" end
	end
	find = find or MakeFind()
	local f = find
	f.opts.game = game == "b" and "b" or "d"
	f.title:SetText(f.opts.game == "b" and (L.MATCH_FIND_BONE_TITLE or L.ARENA_FIND_TITLE)
		or (L.MATCH_FIND_DUEL_TITLE or L.ARENA_FIND_TITLE))
	f.opts.kind = Kit.Recall("find.kind", "c")
	f.opts.level = Kit.Recall("find.level", 5)
	f.opts.reach = Kit.Recall("find.reach", "z")
	f.opts.share = nil
	local level
	if type(ArenaUI.BonesHost) == "function" then
		local bones, at = ArenaUI.BonesHost(f.opts.game)
		if bones and (host == nil or host == bones) then host, level = bones, at end
	end
	if type(host) ~= "table" or type(host.IsShown) ~= "function" or not host:IsShown() then host = nil end
	Host(f, host, level)
	f:Show()
	ArenaUI.FindRefresh()
	return f
end
ArenaUI.Find = ArenaUI.OpenFind
function ArenaUI.FindFrame() return find end
ns.On("ARENA_CHANGED", function() if find and find:IsShown() then ns.SafeCall("arena find", ArenaUI.FindRefresh) end end)
-- The match it found, on its own tab in the Olympus window brought to the front
-- (ChatRooms.OpenMatter, the owner's pattern for every pending conversation): the sheet of its own
-- place, up while it searched, has done its work and goes, as the sheet a window holds goes at
-- Search; the match's card carries it on. (It is a pop-up a strata above that window: Raise alone
-- left it on top.)
ns.On("CHAT_MATTER_SHOWN", function(key)
	local f = find
	if not (f and f:IsShown()) or rawget(f, "host") then return end
	local AM = Match()
	local ok, view = false, nil
	if AM and AM.View then ok, view = pcall(AM.View) end
	local mm = ok and type(view) == "table" and view.match or nil
	if type(mm) == "table" and type(mm.mid) == "string" and key == "arena:" .. mm.mid then f:Hide() end
end)
