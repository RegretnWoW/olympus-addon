local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): PagesStaff.lua. A stub the arena's core created for the screens to
-- fill. Arbiter (with the King's block: banks, arbiters, settings, the delay line), Bank,
-- Ledgers (auditors only), Director: each an ArenaUI.RegisterStaffTab(key, spec).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome
local C = Kit.C

-- The staff's side tabs, each shown only to its role (the design):
-- - Arbiter: a listed arbiter, a public one, the King's view, a councillor, and in a rehearsal the
--   a, p and k stand-ins. His cap meter, his fights (open, close, the Bell, declare with the
--   game's own duel line as a hint, correct and void in the grace), a new fight; the King's block
--   on the King's screen (Show on screen, the stream delay with its presets, the delay line).
-- - Bank: the bank character on the signed list on its duty, or the b stand-in. What it has now
--   (a trade's intent, mails to take), withdrawals and fees to send (Fill next, or what to send
--   with the gamepad UI), its health, the rehearsal's refunds.
-- - Ledgers: auditors only (the King's character, a High Councillor, a signed arbiter with the
--   audit flag): the banks' replicas, the arbiters' books, the debts with their amounts.
-- - Director: a test build, or whoever directs a rehearsal or may: the roster, the roles, Start
--   and Stop, the checklist and its report.
-- The view models are the other packages' (the money part's consoles and ledgers, the fights part's fights, ArenaTest's
-- roster), read through ArenaHome.Data; every button goes through Arena.Can/Do.

local function Me() return ns.me end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Roles() return ns.ArenaRoles end
local function RoleIn(fn, ...)
	local R = Roles()
	if type(R) ~= "table" or type(R[fn]) ~= "function" then return false end
	local ok, yes = pcall(R[fn], ...)
	return ok and yes == true
end
local function StandIn(letter)
	local T = ns.ArenaTest
	return type(T) == "table" and type(T.RoleOf) == "function" and T.RoleOf(Me()) == letter
end
local function Sim() return ns.Arena.Sim() end

---------------------------------------------------------------------------
-- Arbiter
---------------------------------------------------------------------------

function ArenaUI.ArbiterVisible()
	if not Home.ArbitersOn() then return false end -- (1.1.6: no arbiters without a wager)
	if Sim() then return true end
	return RoleIn("IsArbiter", Me(), "L") or RoleIn("IsArbiter", Me(), "T") or Kit.KingsView("L") or Kit.KingsView("T")
		or (ns.IsHighCouncillor and ns.IsHighCouncillor(Me()) == true) or StandIn("a") or StandIn("p") or StandIn("k")
end

-- The fights this client judges (its own writer's), the one in view first.
local function MyFights()
	local out = {}
	for _, ev in ipairs(Data.Events() or {}) do
		if ev.kind == "fight" and Same(ev.arbiter, Me()) then out[#out + 1] = ev end
	end
	return out
end
local function ArbiterFight(st)
	local list = MyFights()
	for _, ev in ipairs(list) do if ev.id == st.sel then return ev end end
	for _, ev in ipairs(list) do if not ev.over then st.sel = ev.id return ev end end
	return nil
end

-- The stream delay presets (the gamepad needs no typing), seconds.
ArenaUI.DELAYS = { 0, 5, 15, 30, 60, 120, 300, 900 }
function ArenaUI.SetDelay(s)
	if Sim() then Kit.Settings().delay = s ArenaUI.Refresh() return true end
	local ok, why = ns.Arena.SetDelay(s)
	if not ok then ArenaUI.Say(Kit.Why(why)) end
	ArenaUI.Refresh()
	return ok
end

local function ArbiterLines(st)
	local lines = {}
	local con = Data.ArbiterConsole()
	lines[#lines + 1] = { header = true, text = L.ARENA_ARB_HEAD }
	if type(con) == "table" then
		local cap, held = tonumber(con.cap) or 0, tonumber(con.held) or 0
		lines[#lines + 1] = { text = L.ARENA_ARB_CAP:format(Kit.Money(held), Kit.Money(cap)), indent = 1 }
		local fees = type(con.fees) == "table" and con.fees or {}
		if (tonumber(fees.owed) or 0) > 0 then
			local text = L.ARENA_ARB_FEES:format(Kit.Money(fees.owed))
			lines[#lines + 1] = { text = fees.late and C("red", text) or text, indent = 1 }
		end
		lines[#lines + 1] = { text = con.onDuty and C("green", L.ARENA_ARB_ON) or C("grey", L.ARENA_ARB_OFF), indent = 1 }
		if con.persists == false then lines[#lines + 1] = { text = C("red", L.ARENA_REFUSE_PERSIST), indent = 1 } end
		for _, mt in ipairs(con.matches or {}) do
			lines[#lines + 1] = { text = L.ARENA_ARB_STAKES:format(Kit.Name(mt.A and mt.A.name), Kit.Name(mt.B and mt.B.name)), right = tostring(mt.state or ""), indent = 1 }
		end
	else
		lines[#lines + 1] = { text = C("grey", L.ARENA_ARB_NO_CONSOLE), indent = 1 }
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_ARB_FIGHTS }
	local list = MyFights()
	if #list == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_ARB_NONE), indent = 1 } end
	local cur = ArbiterFight(st)
	for _, ev in ipairs(list) do
		local id = ev.id
		local text = Home.EventTitle(ev)
		if cur and cur.id == id then text = C("blue", "> ") .. text end
		lines[#lines + 1] = { text = text, right = Home.StateWord(ev), indent = 1, onClick = function() ArenaUI.Select("staff.arbiter", id) end }
	end
	lines[#lines + 1] = { text = C("gold", L.ARENA_ARB_NEW), indent = 1, onClick = function() ArenaUI.NewFight() end }
	-- The King's block (his screen, or the author's view of it).
	if Kit.KingsView("L") or Kit.KingsView("T") then
		lines[#lines + 1] = { header = true, text = L.ARENA_KING_BLOCK }
		lines[#lines + 1] = { text = C("gold", L.ARENA_KING_SHOW), indent = 1, onClick = function() if ArenaUI.Overlay then ArenaUI.Overlay.Show() end end }
		local line = ArenaUI.DelayLine and ArenaUI.DelayLine()
		if line then lines[#lines + 1] = { text = C("grey", line), indent = 1 } end
	end
	return lines
end

-- The fight in view: its controls on the canvas (open, close, the Bell; declare A, B or void with
-- the game's duel line as a hint; the grace with Correct and Void).
local function ArbiterDetail(canvas, st)
	local ev = ArbiterFight(st)
	if not rawget(canvas, "built") then
		canvas.built = true
		canvas.title = Kit.Text(canvas, "title", "LEFT")
		canvas.title:SetPoint("TOPLEFT", 8, -6)
		canvas.title:SetWidth(418)
		canvas.hint = Kit.Text(canvas, nil, "LEFT")
		canvas.hint:SetPoint("TOPLEFT", 8, -32)
		canvas.hint:SetWidth(418)
		canvas.clock = Kit.Text(canvas, nil, "LEFT")
		canvas.clock:SetPoint("TOPLEFT", 8, -52)
		canvas.buttons = {}
		for i = 1, 6 do
			local b = Kit.Button(canvas, 136, 26, "", nil)
			b:SetPoint("TOPLEFT", 8 + ((i - 1) % 3) * 142, -78 - math.floor((i - 1) / 3) * 32)
			canvas.buttons[i] = b
		end
		canvas.delays = {}
		for i, s in ipairs(ArenaUI.DELAYS) do
			local b = Kit.Button(canvas, 50, 24, tostring(s), function() ArenaUI.SetDelay(s) end)
			b:SetPoint("TOPLEFT", 8 + (i - 1) * 52, -176)
			canvas.delays[i] = b
		end
		canvas.delayText = Kit.Text(canvas, "small", "LEFT")
		canvas.delayText:SetPoint("TOPLEFT", 8, -204)
		canvas.delayText:SetWidth(418)
	end
	local king = Kit.KingsView("L") or Kit.KingsView("T")
	for _, b in ipairs(canvas.delays) do b:SetShown(king) end
	canvas.delayText:SetText(king and (L.ARENA_KING_DELAY .. " " .. C("grey", ArenaUI.DelayLine and ArenaUI.DelayLine() or "")) or "")
	for _, b in ipairs(canvas.buttons) do b:Hide() end
	if not ev then
		canvas.title:SetText(C("grey", L.ARENA_ARB_PICK))
		canvas.hint:SetText("")
		canvas.clock:SetText("")
		Kit.StopCountdown(canvas.clock)
		return
	end
	canvas.title:SetText(Home.EventTitle(ev) .. "  " .. C("grey", Home.StateWord(ev)))
	-- The game's own duel line, when this client heard it: a hint, never the declaration.
	local F = ns.ArenaFights
	local raw = type(F) == "table" and type(F.Fight) == "function" and select(2, pcall(F.Fight, ev.id)) or nil
	local heard = type(raw) == "table" and (raw.heard or raw.duel) or ev.heard
	canvas.hint:SetText(type(heard) == "table" and heard.winner and C("green", L.ARENA_ARB_GAME_SAYS:format(Kit.Name(heard.winner), Kit.Name(heard.loser))) or "")
	if ev.graceUntil and ev.graceUntil > ns.Arena.Now() then
		Kit.Countdown(canvas.clock, ev.graceUntil, L.ARENA_ARB_GRACE, "")
	elseif ev.lockAt and ev.lockAt > ns.Arena.Now() then
		Kit.Countdown(canvas.clock, ev.lockAt, L.ARENA_BETS_CLOSE_IN, L.ARENA_BETS_CLOSED)
	else
		Kit.StopCountdown(canvas.clock)
		canvas.clock:SetText("")
	end
	local id = ev.id
	local defs = {}
	if ev.state == "A" or ev.state == "S" or ev.state == "O" then
		defs[#defs + 1] = { text = L.ARENA_ARB_CALL, action = "fights.call", args = { id } }
		defs[#defs + 1] = { text = L.ARENA_ARB_BELL, action = "fights.bell", args = { id } }
	elseif ev.state == "C" or ev.state == "Y" or ev.state == "Z" then
		defs[#defs + 1] = { text = L.ARENA_ARB_BELL, action = "fights.bell", args = { id } }
	end
	if ev.live or ev.state == "L" or ev.state == "B" then
		for _, side in ipairs({ "A", "B" }) do
			local who = ev[side]
			defs[#defs + 1] = { text = L.ARENA_ARB_WINS:format(ns.Cut(Kit.Name(who), 12)), confirm = L.ARENA_ARB_WINS_ASK:format(Kit.Name(who)), action = "fights.rule", args = { id, side, "k" } }
		end
	end
	if ev.state == "R" then
		for _, side in ipairs({ "A", "B" }) do
			local who = ev[side]
			defs[#defs + 1] = { text = L.ARENA_ARB_CORRECT:format(ns.Cut(Kit.Name(who), 10)), confirm = L.ARENA_ARB_CORRECT_ASK:format(Kit.Name(who)), action = "fights.correct", args = { id, tonumber(ev.round) or 1, side, "k" } }
		end
	end
	if not ev.over then defs[#defs + 1] = { text = L.ARENA_ARB_VOID, confirm = L.ARENA_ARB_VOID_ASK, action = "fights.void", args = { id, "a" } } end
	for i, d in ipairs(defs) do
		local b = canvas.buttons[i]
		if b then
			if d.confirm then
				local ok, why = ns.Arena.Can(d.action, unpack(d.args))
				if why == "unknown" then ok, why = false, "missing" end
				Kit.SetButton(b, d.text, ok, Kit.Why(why))
				b:SetScript("OnClick", function() Kit.Confirm(d.confirm, function() ArenaUI.DoAction(d.action, unpack(d.args)) end) end)
			else
				Kit.ActionButton(b, d)
			end
			b:Show()
		end
	end
end

ArenaUI.RegisterStaffTab("staff.arbiter", { label = L.ARENA_STAFF_ARBITER, tip = L.ARENA_STAFF_ARBITER_TIP, order = 1,
	icon = { "Interface\\Icons\\INV_Hammer_07", "Interface\\Icons\\Ability_Warrior_BattleShout" }, visible = ArenaUI.ArbiterVisible,
	lines = ArbiterLines, detail = ArbiterDetail,
	text = function() return L.ARENA_STAFF_ARBITER, L.ARENA_ARB_TEXT end,
	buttons = function()
		local con = Data.ArbiterConsole()
		local on = type(con) == "table" and con.onDuty == true
		local okDuty, why = ns.Arena.Can("arbiter.duty", not on, Home.ViewMode())
		if why == "unknown" then okDuty, why = false, "missing" end
		return {
			{ on and L.ARENA_ARB_GO_OFF or L.ARENA_ARB_GO_ON, function() ArenaUI.DoAction("arbiter.duty", not on, Home.ViewMode()) ArenaUI.Refresh() end, enabled = okDuty, why = Kit.Why(why) },
			{ L.ARENA_ARB_NEW, function() ArenaUI.NewFight() end },
			{ L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end },
		}
	end })

-- A new fight (the arbiter's pop-up): the two fighters (Use target for each), public or private,
-- the crowd's bets on a public one (on by default, 2026-10-04: off sends markets = false, so the
-- fight opens no winner market), best of; the markets and the close time are the fight's owner's
-- defaults (the fights part, the markets), the shortest window the King's delay allows (Arena.OpenMin).
local newFight
function ArenaUI.NewFight()
	if not newFight then
		local f = Kit.Frame("OlympusArenaNewFight", 420, 352, { title = L.ARENA_ARB_NEW })
		f.names = {}
		for i, side in ipairs({ "A", "B" }) do
			local t = Kit.Text(f, "title", "LEFT")
			t:SetPoint("TOPLEFT", 30, -56 - (i - 1) * 40)
			t:SetWidth(230)
			local b = Kit.Button(f, 120, 24, L.ARENA_USE_TARGET, function()
				if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then f.names[side] = ns.UnitFullName("target") end
				ArenaUI.NewFightRefresh()
			end)
			b:SetPoint("TOPRIGHT", -30, -54 - (i - 1) * 40)
			f["name" .. side] = t
		end
		f.public = Kit.Choices(f, { { true, L.ARENA_NEW_PUBLIC }, { false, L.ARENA_NEW_PRIVATE } }, 120, function(k) f.isPublic = k ArenaUI.NewFightRefresh() end)
		f.public:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -146)
		f.crowd = Kit.Choices(f, { { true, L.ARENA_NEW_CROWD_ON }, { false, L.ARENA_NEW_CROWD_OFF } }, 150, function(k) f.crowdOn = k ArenaUI.NewFightRefresh() end)
		f.crowd:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -178)
		f.bo = Kit.Choices(f, { { 1, L.ARENA_BO_1 }, { 3, L.ARENA_BO_3 }, { 5, L.ARENA_BO_5 } }, 80, function(k) f.boKey = k ArenaUI.NewFightRefresh() end)
		f.bo:SetPoint("TOPLEFT", f, "TOPLEFT", 90, -210)
		f.note = Kit.Text(f, "small", "LEFT")
		f.note:SetPoint("TOPLEFT", 30, -246)
		f.note:SetWidth(360)
		f.go = Kit.Button(f, 150, 26, L.ARENA_NEW_CREATE, nil)
		f.go:SetPoint("BOTTOMLEFT", 30, 16)
		f.cancel = Kit.Button(f, 150, 26, L.ARENA_CANCEL, function() f:Hide() end)
		f.cancel:SetPoint("BOTTOMRIGHT", -30, 16)
		newFight = f
	end
	newFight.isPublic = rawget(newFight, "isPublic") ~= false
	newFight.crowdOn = rawget(newFight, "crowdOn") ~= false
	newFight.boKey = rawget(newFight, "boKey") or 1
	newFight:Show()
	ArenaUI.NewFightRefresh()
	return newFight
end
-- What the pop-up would send (fights.new's opts): a private fight, or the crowd's bets off, opens
-- no market (markets = false).
function ArenaUI.NewFightOpts()
	local f = newFight
	if not f then return nil end
	local T = ns.ArenaTest
	local opts = { A = f.names.A, B = f.names.B, public = f.isPublic, bo = f.boKey, rehearsal = type(T) == "table" and T.Running and T.Running() ~= nil or nil }
	if f.isPublic and f.crowdOn == false then opts.markets = false end
	return opts
end
function ArenaUI.NewFightRefresh()
	local f = newFight
	if not f then return end
	f.nameA:SetText(f.names.A and Kit.Name(f.names.A) or C("grey", L.ARENA_NEW_PICK_A))
	f.nameB:SetText(f.names.B and Kit.Name(f.names.B) or C("grey", L.ARENA_NEW_PICK_B))
	f.public:Select(f.isPublic)
	f.crowd:SetShown(f.isPublic == true)
	f.crowd:Select(f.crowdOn)
	f.bo:Select(f.boKey)
	local opts = ArenaUI.NewFightOpts()
	local open = ns.Arena.OpenMin(f.isPublic)
	f.note:SetText(L.ARENA_NEW_WINDOW:format(Home.Clock(open)) .. (ArenaUI.DelayLine and ArenaUI.DelayLine() and ("\n" .. C("grey", ArenaUI.DelayLine())) or ""))
	Kit.ActionButton(f.go, { text = L.ARENA_NEW_CREATE, action = "fights.new", args = { opts }, after = function(ok) if ok then f:Hide() end end })
	if not (f.names.A and f.names.B) then Kit.SetButton(f.go, nil, false, L.ARENA_NEW_PICK_BOTH) end
end

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------

function ArenaUI.BankVisible()
	if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then return false end
	if Sim() then return true end
	local W = ns.Wallet
	local duty = type(W) == "table" and type(W.OnDuty) == "function" and W.OnDuty()
	return duty ~= nil and duty ~= false or RoleIn("IsBank", Me(), "L") or RoleIn("IsBank", Me(), "T") or StandIn("b")
end

local function BankLines()
	local lines = {}
	local con = Data.BankConsole()
	if type(con) ~= "table" then
		lines[1] = { header = true, text = L.ARENA_BANK_HEAD_OFF }
		lines[2] = { text = C("grey", L.ARENA_BANK_OFF_DUTY), indent = 1 }
		lines[3] = { text = C("grey", L.ARENA_BANK_SAVE_NOTE), indent = 1 }
		return lines
	end
	local cur = con.currency
	lines[#lines + 1] = { header = true, text = L.ARENA_BANK_HEAD:format(con.mode == "T" and L.ARENA_BANK_REHEARSAL or L.ARENA_BANK_LIVE) }
	if con.paused then lines[#lines + 1] = { text = C("red", L.ARENA_BANK_PAUSED), indent = 1 } end
	lines[#lines + 1] = { header = true, text = L.ARENA_BANK_NOW }
	local now = 0
	for _, q in ipairs(con.queue or {}) do
		now = now + 1
		lines[#lines + 1] = { text = L.ARENA_BANK_DEPOSIT_LINE:format(Kit.Name(q.name), Kit.Money(q.copper or 0, cur)), right = q.called and L.ARENA_BANK_CALLED or "", indent = 1 }
	end
	for _, m in ipairs(con.inbox or {}) do
		now = now + 1
		local verdict = m.verdict == "take" and C("green", L.ARENA_BANK_TAKE) or (m.verdict == "return" and C("red", L.ARENA_BANK_RETURN) or C("grey", L.ARENA_BANK_RETURNED))
		lines[#lines + 1] = { text = L.ARENA_BANK_MAIL_LINE:format(Kit.Name(m.sender), Kit.Money(m.money or 0, cur)), right = verdict, indent = 1 }
	end
	if now == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_BANK_NOTHING), indent = 1 } end
	local wd = type(con.withdrawals) == "table" and con.withdrawals or {}
	if #(wd.queue or {}) > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_BANK_WITHDRAWALS }
		for _, x in ipairs(wd.queue) do
			lines[#lines + 1] = { text = L.ARENA_BANK_PAY_LINE:format(Kit.Name(x.name or x.code), Kit.Money(x.copper or 0, cur)), right = x.blocked and C("red", L.ARENA_BANK_BLOCKED) or tostring(x.state or ""), indent = 1 }
		end
	end
	local fees = type(con.fees) == "table" and con.fees or {}
	if (tonumber(fees.owed) or 0) > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_BANK_FEES }
		lines[#lines + 1] = { text = L.ARENA_BANK_FEE_LINE:format(Kit.Money(fees.owed, cur), Kit.Name(fees.receiver or "?")), indent = 1 }
	end
	-- A copper rehearsal's refunds (ArenaTest's record): each depositor's net, sent back by Fill next.
	local T = ns.ArenaTest
	local run = type(T) == "table" and T.Running and T.Running() or nil
	local refunds = run and T.Refunds and T.Refunds(run.rid) or {}
	if #refunds > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_BANK_REFUNDS }
		for _, r in ipairs(refunds) do lines[#lines + 1] = { text = L.ARENA_BANK_PAY_LINE:format(Kit.Name(r.name), Kit.Money(r.copper)), indent = 1 } end
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_BANK_HEALTH }
	local h = type(con.health) == "table" and con.health or {}
	local q = tonumber(h.queue) or 0
	lines[#lines + 1] = { text = L.ARENA_BANK_LANE:format(q, math.ceil(q * 1.2)), indent = 1 }
	if h.lastSent then lines[#lines + 1] = { text = L.ARENA_BANK_LAST_SENT:format(Home.Clock(math.max(0, ns.Arena.Now() - h.lastSent))), indent = 1 } end
	lines[#lines + 1] = { text = C("grey", L.ARENA_BANK_SAVE_NOTE), indent = 1 }
	return lines
end
ArenaUI.RegisterStaffTab("staff.bank", { label = L.ARENA_STAFF_BANK, tip = L.ARENA_STAFF_BANK_TIP, order = 2,
	icon = { "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\INV_Misc_Coin_01" }, visible = ArenaUI.BankVisible,
	lines = BankLines,
	text = function() return L.ARENA_STAFF_BANK, L.ARENA_BANK_TEXT end,
	buttons = function()
		local con = Data.BankConsole()
		local on = type(con) == "table"
		local mode = Home.ViewMode()
		local list = {}
		local okDuty, whyDuty = ns.Arena.Can("bank.duty", not on, mode)
		if whyDuty == "unknown" then okDuty, whyDuty = false, "missing" end
		list[1] = { on and L.ARENA_BANK_GO_OFF or L.ARENA_BANK_GO_ON, function() ArenaUI.DoAction("bank.duty", not on, mode) ArenaUI.Refresh() end, enabled = okDuty, why = Kit.Why(whyDuty) }
		local okPay, whyPay = ns.Arena.Can("bank.pay")
		if whyPay == "unknown" then okPay, whyPay = false, "missing" end
		list[2] = { Kit.Gamepad() and L.ARENA_FILL_TELL or L.ARENA_BANK_FILL_NEXT, function() ArenaUI.DoAction("bank.pay") end, enabled = on and okPay, why = Kit.Why(whyPay) }
		local paused = on and con.paused
		list[3] = { paused and L.ARENA_BANK_RESUME or L.ARENA_BANK_PAUSE, function() ArenaUI.DoAction("bank.pause", not paused) ArenaUI.Refresh() end, enabled = on }
		return list
	end })

---------------------------------------------------------------------------
-- Ledgers (auditors only)
---------------------------------------------------------------------------

function ArenaUI.LedgersVisible()
	if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then return false end
	if Sim() then return true end
	return RoleIn("Auditor", Me(), "L") or RoleIn("Auditor", Me(), "T")
end
local function LedgerLines()
	local lines = {}
	local led = Data.Ledgers()
	if type(led) ~= "table" then return { { text = C("grey", L.ARENA_LEDGERS_NONE) } } end
	lines[#lines + 1] = { header = true, text = L.ARENA_LEDGERS_BANKS }
	for _, b in ipairs(led.banks or {}) do
		local liab = type(b.liabilities) == "table" and b.liabilities.g or b.liabilities
		lines[#lines + 1] = { text = L.ARENA_LEDGERS_BANK:format(Kit.Name(b.name), Kit.Money(tonumber(liab) or 0), tonumber(b.seq) or 0),
			right = b.gap and C("red", L.ARENA_LEDGERS_GAP) or (b.verified and C("green", L.ARENA_LEDGERS_OK) or ""), indent = 1 }
		if b.reserve then lines[#lines + 1] = { text = L.ARENA_LEDGERS_RESERVE:format(Kit.Money(tonumber(type(b.reserve) == "table" and b.reserve.copper or b.reserve) or 0)), indent = 2 } end
		if type(b.attest) == "table" then lines[#lines + 1] = { text = L.ARENA_LEDGERS_ATTEST:format(Kit.Money(b.attest.copper or 0)), indent = 2 } end
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_LEDGERS_ARBITERS }
	for _, a in ipairs(led.arbiters or {}) do
		lines[#lines + 1] = { text = L.ARENA_LEDGERS_ARBITER:format(Kit.Name(a.name), Kit.Money(tonumber(a.held) or 0), tonumber(a.matches) or 0),
			right = (tonumber(a.owed) or 0) > 0 and C("red", Kit.Money(a.owed)) or "", indent = 1 }
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_LEDGERS_DEBTS }
	local debts = type(led.debts) == "table" and (led.debts.marks or led.debts) or {}
	if #debts == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_LEDGERS_NO_DEBTS), indent = 1 } end
	for _, d in ipairs(debts) do
		if type(d) == "table" then
			lines[#lines + 1] = { text = L.ARENA_LEDGERS_DEBT:format(Kit.Name(d.name), Kit.Money(tonumber(d.copper) or 0), Kit.Name(d.creditor == "G" and L.ARENA_THE_GUILD or d.creditor)),
				right = tostring(d.state or ""), indent = 1 }
		end
	end
	return lines
end
ArenaUI.RegisterStaffTab("staff.ledgers", { label = L.ARENA_STAFF_LEDGERS, tip = L.ARENA_STAFF_LEDGERS_TIP, order = 3,
	icon = { "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Book_11" }, visible = ArenaUI.LedgersVisible,
	lines = LedgerLines,
	text = function() return L.ARENA_STAFF_LEDGERS, L.ARENA_LEDGERS_TEXT end,
	buttons = function() return { { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end } } end })

---------------------------------------------------------------------------
-- Director (rehearsals, the checklist)
---------------------------------------------------------------------------

function ArenaUI.DirectorVisible()
	if Sim() or ns.Arena.TestBuild() then return true end
	local T = ns.ArenaTest
	if type(T) == "table" and type(T.IsDirector) == "function" and T.IsDirector(Me()) then return true end
	local ok = ns.Arena.MayDirect(Me(), { lane = "g", money = "c", roles = {} })
	return ok == true
end

local ROLE_BUTTONS = { { "b", "ARENA_ROLE_B" }, { "a", "ARENA_ROLE_A" }, { "p", "ARENA_ROLE_P" }, { "k", "ARENA_ROLE_K" }, { "t", "ARENA_ROLE_T" },
	{ "d", "ARENA_ROLE_D" }, { "s", "ARENA_ROLE_S" }, { false, "ARENA_ROLE_NONE" } }
local MARK_WORDS = { p = "ARENA_MARK_PASS", f = "ARENA_MARK_FAIL", k = "ARENA_MARK_SKIP" }

local function DirectorBuild(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:SetAllPoints(parent)
	d.part = Kit.Choices(d, { { "roster", L.ARENA_DIR_ROSTER }, { "rehearsal", L.ARENA_DIR_REHEARSAL }, { "checklist", L.ARENA_DIR_CHECKLIST } }, 120,
		function(k) Kit.Remember("director.part", k) ArenaUI.Refresh() end)
	d.part:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
	d.list = Kit.List(d, 420, 250)
	d.list:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -30)
	d.side = CreateFrame("Frame", nil, d)
	d.side:SetPoint("TOPLEFT", d, "TOPLEFT", 428, -30)
	d.side:SetSize(252, 250)
	d.sideText = Kit.Text(d.side, nil, "LEFT")
	d.sideText:SetPoint("TOPLEFT", 4, 0)
	d.sideText:SetWidth(244)
	if d.sideText.SetJustifyV then d.sideText:SetJustifyV("TOP") end
	d.sideButtons = {}
	for i = 1, 8 do
		local b = Kit.Button(d.side, 120, 24, "", nil)
		b:SetPoint("TOPLEFT", ((i - 1) % 2) * 124, -96 - math.floor((i - 1) / 2) * 28)
		d.sideButtons[i] = b
	end
	d.lane = Kit.Choices(d.side, { { "group", L.ARENA_DIR_GROUP }, { "army", L.ARENA_DIR_ARMY } }, 120, function(k) Kit.Remember("director.lane", k) ArenaUI.Refresh() end)
	d.lane:SetPoint("TOPLEFT", d.side, "TOPLEFT", 0, -40)
	d.money = Kit.Choices(d.side, { { "chips", L.ARENA_DIR_CHIPS }, { "copper", L.ARENA_DIR_COPPER } }, 120, function(k) Kit.Remember("director.money", k) ArenaUI.Refresh() end)
	d.money:SetPoint("TOPLEFT", d.side, "TOPLEFT", 0, -68)
	d.chips = Kit.Stepper(d.side, { width = 250, min = 1, max = 100000, value = 1000, box = false, steps = { 100, 1000, 10000 }, cur = "c" })
	d.chips:SetPoint("TOPLEFT", d.side, "TOPLEFT", 0, -100)
	local ok, eb = pcall(CreateFrame, "EditBox", nil, d.side, "InputBoxTemplate")
	if not ok or not eb then eb = CreateFrame("EditBox", nil, d.side) end
	eb:SetAutoFocus(false)
	eb:SetSize(236, 22)
	eb:SetMaxBytes(81)
	eb:SetPoint("TOPLEFT", d.side, "TOPLEFT", 8, -70)
	eb.olympusBox = true
	eb:SetScript("OnMouseDown", function(self) ns.Focus(self) end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	d.note = eb
	return d
end

-- The Director's picks: the tester in view (roster), the item in view (checklist).
local pick = { tester = nil, item = nil }
local function DirectorRefresh(d)
	local T = ns.ArenaTest
	local part = Kit.Recall("director.part", "roster")
	d.part:Select(part)
	-- (Each part places the buttons it uses; back in their grid first.)
	for i, b in ipairs(d.sideButtons) do
		b:Hide()
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", d.side, "TOPLEFT", ((i - 1) % 2) * 124, -96 - math.floor((i - 1) / 2) * 28)
		b:SetWidth(120)
	end
	d.lane:SetShown(part == "rehearsal")
	d.money:SetShown(part == "rehearsal")
	d.chips:SetShown(part == "rehearsal" and Kit.Recall("director.money", "chips") == "chips")
	d.note:SetShown(part == "checklist" and pick.item ~= nil)
	local lines = {}
	if part == "roster" then
		lines[1] = { header = true, text = L.ARENA_DIR_ROSTER_HEAD }
		local roster = Data.Roster() or {}
		if #roster == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_DIR_ROSTER_NONE), indent = 1 } end
		for _, r in ipairs(roster) do
			local name = r.name
			local flags = {}
			for c in tostring(r.flags or ""):gmatch(".") do flags[#flags + 1] = L["ARENA_FLAG_" .. c:upper()] or c end
			local text = Kit.Name(name) .. "  " .. C("grey", L.ARENA_DIR_BUILD:format(tonumber(r.build) or 0, tostring(r.base or "?")))
			if pick.tester and Same(pick.tester, name) then text = C("blue", "> ") .. text end
			if r.gone then text = C("grey", text .. " " .. L.ARENA_DIR_GONE) end
			lines[#lines + 1] = { text = text, right = (r.role and (L["ARENA_ROLE_" .. r.role:upper()] or r.role) or "") .. (#flags > 0 and (" · " .. table.concat(flags, ", ")) or ""),
				indent = 1, onClick = function() pick.tester = name ArenaUI.Refresh() end }
		end
		d.sideText:SetText(pick.tester and L.ARENA_DIR_ROLE_FOR:format(Kit.Name(pick.tester)) or C("grey", L.ARENA_DIR_PICK_TESTER))
		if pick.tester then
			for i, rb in ipairs(ROLE_BUTTONS) do
				local b = d.sideButtons[i]
				local letter = rb[1]
				Kit.SetButton(b, L[rb[2]], true)
				b:SetScript("OnClick", function()
					local okRole, why = T.SetRole(pick.tester, letter or nil)
					if not okRole then ArenaUI.Say(Kit.Why(why)) end
					ArenaUI.Refresh()
				end)
				b:Show()
			end
		end
	elseif part == "rehearsal" then
		local run = type(T) == "table" and T.Running and T.Running() or nil
		lines[1] = { header = true, text = L.ARENA_DIR_REHEARSAL }
		if run then
			lines[#lines + 1] = { text = L.ARENA_DIR_RUNNING:format(run.rid, run.lane == "army" and L.ARENA_DIR_ARMY or L.ARENA_DIR_GROUP,
				run.money == "p" and L.ARENA_DIR_COPPER or L.ARENA_DIR_CHIPS, Kit.Name(run.director)), indent = 1 }
			for _, r in ipairs(T.Roles and T.Roles() or {}) do
				lines[#lines + 1] = { text = Kit.Name(r.name), right = L["ARENA_ROLE_" .. tostring(r.role):upper()] or r.role, indent = 2 }
			end
			if T.DirectorAway and T.DirectorAway() then lines[#lines + 1] = { text = C("red", L.ARENA_DIR_AWAY), indent = 1 } end
		else
			lines[#lines + 1] = { text = C("grey", L.ARENA_DIR_NONE), indent = 1 }
		end
		local open = type(T) == "table" and T.CopperOpen and T.CopperOpen() or {}
		if #open > 0 then lines[#lines + 1] = { text = C("red", L.ARENA_DIR_COPPER_OPEN:format(#open)), indent = 1 } end
		d.lane:Select(Kit.Recall("director.lane", "group"))
		d.money:Select(Kit.Recall("director.money", "chips"))
		d.sideText:SetText(L.ARENA_DIR_START_HOW)
		local start, stop = d.sideButtons[7], d.sideButtons[8]
		start:ClearAllPoints()
		start:SetPoint("BOTTOMLEFT", d.side, "BOTTOMLEFT", 0, 0)
		stop:ClearAllPoints()
		stop:SetPoint("LEFT", start, "RIGHT", 4, 0)
		Kit.SetButton(start, L.ARENA_DIR_START, not Sim())
		start:SetScript("OnClick", function()
			T.Start(Kit.Recall("director.lane", "group"), Kit.Recall("director.money", "chips"), d.chips:Get())
			ArenaUI.Refresh()
		end)
		start:Show()
		Kit.SetButton(stop, L.ARENA_DIR_STOP, run ~= nil and not Sim())
		stop:SetScript("OnClick", function() Kit.Confirm(L.ARENA_DIR_STOP_ASK, function() T.Stop() ArenaUI.Refresh() end) end)
		stop:Show()
	else
		lines[1] = { header = true, text = L.ARENA_DIR_CHECKLIST }
		for _, item in ipairs(type(T) == "table" and T.CHECKLIST or {}) do
			local m = T.MarkOf and T.MarkOf(item.id)
			local id = item.id
			local mark = m and (m.s == "p" and C("green", L.ARENA_MARK_PASS) or (m.s == "f" and C("red", L.ARENA_MARK_FAIL) or C("grey", L.ARENA_MARK_SKIP))) or C("grey", L.ARENA_MARK_OPEN)
			local text = item.id .. " " .. item.what
			if pick.item == id then text = C("blue", "> ") .. text end
			lines[#lines + 1] = { text = text, right = mark, indent = 1, onClick = function() pick.item = id ArenaUI.Refresh() end }
		end
		local item = pick.item and T.CheckItem and T.CheckItem(pick.item)
		if item then
			local m = T.MarkOf(item.id)
			d.sideText:SetText(C("gold", item.id .. " (" .. item.stage .. ")") .. "\n" .. item.what .. "\n" .. C("grey", item.expect))
			d.note:SetText(m and m.note or "")
			for i, s in ipairs({ "p", "f", "k" }) do
				local b = d.sideButtons[i]
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", d.side, "BOTTOMLEFT", (i - 1) * 82, 0)
				b:SetWidth(80)
				Kit.SetButton(b, L[MARK_WORDS[s]], true)
				b:SetScript("OnClick", function()
					T.Mark(item.id, s, d.note:GetText())
					ArenaUI.Refresh()
				end)
				b:Show()
			end
			d.note:ClearAllPoints()
			d.note:SetPoint("BOTTOMLEFT", d.side, "BOTTOMLEFT", 8, 30)
		else
			d.sideText:SetText(C("grey", L.ARENA_DIR_PICK_ITEM))
		end
	end
	d.list:SetLines(lines)
	ArenaUI.lastDirector = { part = part, lines = lines }
end
ArenaUI.RegisterStaffTab("director", { label = L.ARENA_STAFF_DIRECTOR, tip = L.ARENA_STAFF_DIRECTOR_TIP, order = 4, full = true,
	icon = { "Interface\\Icons\\INV_Misc_Spyglass_02", "Interface\\Icons\\INV_Misc_Note_01" }, visible = ArenaUI.DirectorVisible,
	build = DirectorBuild, refresh = DirectorRefresh,
	text = function() return L.ARENA_STAFF_DIRECTOR, L.ARENA_DIR_TEXT end,
	copy = function() local T = ns.ArenaTest return T and T.Report and T.Report() or "" end,
	buttons = function()
		return { { L.ARENA_DIR_REPORT, function() local T = ns.ArenaTest if T and T.Report then Kit.Copy(L.ARENA_DIR_REPORT, T.Report()) end end } }
	end })
