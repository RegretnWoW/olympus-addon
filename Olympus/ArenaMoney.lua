local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaMoney.lua. A stub the arena's core created for the money part (money) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- One trade and mail watcher for any player (generalised from Treasury.lua's), the fill helpers
-- (trade and mail, gamepad-aware: with the gamepad UI they only print what to send) and the mail
-- subject reader. No gold moves by itself: every trade and mail is the player's own click.
-- API (the design):
--   Money.Expect(key, spec), Money.Forget(key): install the watcher lazily (the weight rule);
--     spec = { partner, dir = "in"|"out"|"both", subjectPrefix }
--   Money.Subscribe(fn): fn(r), r = { kind = "trade"|"mailSent"|"mailTaken"|"mailReturned",
--     partner, guid, level, guild, got, gave, items, subject, cod, t }
--   Money.FillTrade(copper, partner), Money.FillMail(to, subject, copper): "filled"|"said"|
--     "gamepad"|"closed"|"combat"|"partner" (the open trade is with someone else than partner)|
--     "copperfull" (a copper rehearsal's record is full: nothing more moves until it is cleared),
--     and the line printed. FillTrade reads GetPlayerTradeMoney() after pcall(SetTradeMoney, c):
--     unchanged means "said" (shares Dues' duesTradeBlocked flag).
--   Money.ReadSubject(s): kind (fee, payout, refund, stake, wallet, deposit, remit), ref, test
--   Money.Flow(name, out, o): answers Treasury.Record (an Arena mail on a keeper's client is
--     excluded only when it matches an open obligation of this keeper for that amount, the design)
--
-- the money part's additions to that contract (the names the other packages and the screens use):
--   spec also takes { copper = exact amount, upTo = at most this much, amounts = { [copper] =
--     true } (any of these), mode = "L"|"T", ref }: what the obligation expects to move; Flow
--     matches on it (partner, direction and an amount: a watch with no amount excludes nothing).
--   Money.Expects(key) -> the spec, or nil; Money.Active() -> true while anything is expected.
--   Money.TakePending() -> true while a mail take waits for the inbox to confirm it. One take is
--     pending at a time: the fills answer "wait" meanwhile (the player's next click waits for the
--     game), the design.
--   Money.Subject(kind, ref, test) -> the mail subject the arena writes (the design):
--     "Arena fee <ref>", "Arena fee TEST <ref>", "Arena payout <ref>", "Arena refund <ref>",
--     "Arena stake <ref>", "Arena wallet <code> <qseq>" (ref "<code> <qseq>"), "Arena wallet deposit",
--     "Arena remit <day>" (an arbiter's daily remit to the bank, the design).
--   Money.Postage() -> copper a mail costs (GetSendMailPrice, else 30).
--   Money.Coins(copper) -> "1g 2s 3c" (Treasury.Coins when there).
--   Money.Copper(r, mode, extra): the copper-mode record (the design): a gold movement of a copper
--     rehearsal as a line of db.arenaCopper, { rid, from, to, copper, how = t|m, dir = in|out, at,
--     state = open|refunded|written, by }; returns its id. Money.CopperRefunded(id, by) marks it
--     refunded (the recipient's refund receipt), Money.CopperOpen(rid) lists the open lines.
--     Money.CopperMode() -> the running copper rehearsal's rid, or nil (ArenaTest.Running, the screens).
--     Money.CopperFull() -> true when the record holds COPPER_MAX lines: a copper rehearsal's
--     deposits and fills are refused before any gold moves, so no movement goes unrecorded.
--     Money.COPPER_FEE_MAX: an "Arena fee TEST" mail a keeper excludes during a copper rehearsal,
--     at most (6% of the 50 g its bank may hold); a bigger one, or one outside a rehearsal, counts.
--   Money.KeeperLine(name, copper, how, out): a keeper's excluded "arena" line (Treasury.Record),
--     whispered to the online auditors as a receipt (ZR, ref "K") so a keeper never hides the
--     treasury's gold as the arena's without their seeing it (the design, Treasury row).
--   Money.Net(r) -> out, copper (a trade netted, a mail sent or taken); r also carries out,
--     copper and keys (the expectations it matches). A flow of kind "tradeView" (the window's gold
--     while an auditor attests a bank's reserve, spec.attest) completes nothing.
--   Money.Match(name, out, copper, subject) -> keys; Money.Installed(); Money.Full(name).
--   Money.CopperBack(partner, copper, rid): an open "out" line of that partner and amount refunded.
-- Events it fires: none of its own; each flow goes to the subscribers (Wallet, Debts, Stakes).

local L = ns.L
local ArenaMoney = {}
ns.ArenaMoney = ArenaMoney
local Money = ArenaMoney

Money.TAKE_FOR = 30           -- seconds a mail take may wait for the inbox to confirm it
Money.POSTAGE = 30            -- copper a mail costs when the game can't say (Classic's)
Money.SUBJECT_MAX = 64        -- a mail subject's length at most

local function Now() return ns.Arena and ns.Arena.Now() or ns.Now() end
local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or nil end
-- A name as the game gives it (a unit, a mail's sender, a typed recipient), as the server writes it.
local function Full(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(ns.Normal(name))
end
Money.Full = Full

function Money.Coins(copper)
	local T = ns.Treasury
	if type(T) == "table" and type(T.Coins) == "function" then return T.Coins(copper) end
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Subjects (the design): the arena's mails say what they are, so the treasury and the bank
-- can tell a fee from a deposit, and a returned withdrawal from a gift.
---------------------------------------------------------------------------

local KINDS = { fee = true, payout = true, refund = true, stake = true, wallet = true, remit = true }

function Money.Subject(kind, ref, test)
	local out = "Arena " .. tostring(kind)
	if kind == "deposit" then out = "Arena wallet deposit" end
	if test then out = out .. " TEST" end
	if ref ~= nil and tostring(ref) ~= "" and kind ~= "deposit" then out = out .. " " .. tostring(ref) end
	return out:sub(1, Money.SUBJECT_MAX)
end

-- kind, ref, test: "Arena fee B1-2k" -> "fee", "B1-2k", false; "Arena wallet deposit" -> "deposit";
-- "Arena wallet 1a2b3c4d 1f" -> "wallet", "1a2b3c4d 1f". TEST anywhere after the kind. nil for
-- anything else (a player's own subject, 1.1's "Olympus arena ...").
function Money.ReadSubject(s)
	if type(s) ~= "string" then return nil end
	if issecretvalue and issecretvalue(s) then return nil end
	local kind, rest = s:match("^%s*Arena%s+(%a+)(.*)$")
	if not kind then return nil end
	kind = kind:lower()
	if not KINDS[kind] then return nil end
	local words, test = {}, false
	for w in rest:gmatch("%S+") do
		if w == "TEST" then test = true else words[#words + 1] = w end
	end
	if kind == "wallet" and words[1] and words[1]:lower() == "deposit" then
		table.remove(words, 1)
		kind = "deposit"
	end
	local ref = #words > 0 and table.concat(words, " ") or nil
	return kind, ref, test
end

function Money.Postage()
	if GetSendMailPrice then
		local ok, p = pcall(GetSendMailPrice)
		if ok and type(p) == "number" and p >= 0 then return math.floor(p) end
	end
	return Money.POSTAGE
end

---------------------------------------------------------------------------
-- What this client expects to move (the weight rule: nothing is watched until something is)
---------------------------------------------------------------------------

local expects = {}   -- [key] = spec
local subs = {}      -- fn(r)
local installed = false
local Install        -- (below)

function Money.Active() return next(expects) ~= nil end
function Money.Expects(key) return expects[key] end

function Money.Expect(key, spec)
	if type(key) ~= "string" or type(spec) ~= "table" then return false end
	local s = {}
	for k, v in pairs(spec) do s[k] = v end
	s.partner = s.partner and Full(s.partner) or nil
	s.dir = (s.dir == "in" or s.dir == "out") and s.dir or "both"
	s.at = s.at or Now()
	expects[key] = s
	Install()
	return true
end
function Money.Forget(key)
	if type(key) == "string" then expects[key] = nil end
end
-- Every expectation whose key starts with prefix goes (a match's, a bank's duty).
function Money.ForgetAll(prefix)
	for key in pairs(expects) do
		if type(prefix) ~= "string" or key:sub(1, #prefix) == prefix then expects[key] = nil end
	end
end

function Money.Subscribe(fn)
	if type(fn) == "function" then subs[#subs + 1] = fn end
end

-- Whether a spec wants a flow: its partner (any when none), its direction, its amount, its subject.
local function Wants(spec, name, out, copper, subject)
	if spec.partner and Lower(spec.partner) ~= Lower(name) then return false end
	if spec.dir == "in" and out then return false end
	if spec.dir == "out" and not out then return false end
	copper = tonumber(copper) or 0
	if spec.copper and copper ~= spec.copper then return false end
	if spec.upTo and copper > spec.upTo then return false end
	if type(spec.amounts) == "table" and not spec.amounts[copper] then return false end
	if spec.subjectPrefix then
		if type(subject) ~= "string" or subject:sub(1, #spec.subjectPrefix) ~= spec.subjectPrefix then return false end
	end
	return true
end
-- The keys of the expectations a flow matches.
function Money.Match(name, out, copper, subject)
	local keys = {}
	for key, spec in pairs(expects) do
		if Wants(spec, name, out, copper, subject) then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

-- Treasury.Record's question on a keeper's client (the design): is this line the arena's, one of
-- this keeper's own open obligations (gold to or from a bank, a stake to or from an arbiter for an
-- open match, a direct bet's payment) for that amount? Then it is excluded, kind "arena". Anything
-- else is recorded as it always was: a keeper's "Arena payout" to someone he owes nothing counts.
-- Only a watch that names its amount answers (the design: "for that amount"): a watch on a partner
-- alone (whatever may come back from an arbiter, a bank's mail) would hide any gold from him.
function Money.Flow(name, out, o)
	if type(name) ~= "string" or name == "" then return nil end
	o = type(o) == "table" and o or {}
	if o.item then return nil end
	local copper = tonumber(o.copper or o.money)
	if not copper then return nil end
	for _, spec in pairs(expects) do
		-- (A subject-only watch, the fee receiver's, is no obligation of his.)
		local amount = spec.copper or spec.upTo or type(spec.amounts) == "table"
		if amount and Wants(spec, name, out, copper, spec.subjectPrefix and o.note or nil) then
			return true, "arena"
		end
	end
	return nil
end

-- The keeper's excluded arena line goes to the auditors (Debts sends it as a receipt).
function Money.KeeperLine(name, copper, how, out)
	local D = ns.Debts
	if type(D) == "table" and type(D.KeeperReceipt) == "function" then
		ns.SafeCall("arena keeper line", D.KeeperReceipt, name, copper, how, out)
	end
end

-- A flow's direction and amount: a trade netted (gold both ways is one deal), a mail sent out, a
-- mail taken in.
function Money.Net(r)
	if type(r) ~= "table" then return false, 0 end
	if r.kind == "trade" then
		local net = (tonumber(r.got) or 0) - (tonumber(r.gave) or 0)
		return net < 0, math.abs(net)
	elseif r.kind == "mailSent" then
		return true, tonumber(r.gave) or 0
	end
	return false, tonumber(r.got) or 0
end

local function Emit(r)
	r.t = r.t or Now()
	local out, copper = Money.Net(r)
	r.out, r.copper = out, copper
	r.keys = Money.Match(r.partner, out, copper, r.subject)
	-- A copper rehearsal's gold (the design): every movement the arena expected in T is written
	-- down, account-wide, before anything else looks at it.
	if r.kind ~= "tradeView" and copper > 0 and Money.CopperMode() then
		for _, key in ipairs(r.keys) do
			local spec = expects[key]
			if spec and spec.mode == "T" then Money.Copper(r) break end
		end
	end
	for _, fn in ipairs(subs) do ns.SafeCall("arena money", fn, r) end
end
Money.Emit = Emit -- (tests and the sim: a flow as the watcher would give it)

---------------------------------------------------------------------------
-- Trades (as Treasury.lua reads them): the partner, his GUID, level and guild from the unit
-- "NPC" when the window opens; the gold and the items as the window last showed them; counted
-- only when the game says the trade is complete.
---------------------------------------------------------------------------

local trade -- { partner, guid, level, guild, got, gave, gotItems, gaveItems }

local function Items(info, first, last)
	local n = 0
	if not info then return 0 end
	for i = first, last do
		local ok, name = pcall(info, i)
		if ok and name and name ~= "" then n = n + 1 end
	end
	return n
end

local function TradeShow()
	if not Money.Active() then trade = nil return end
	local partner = ns.UnitFullName and ns.UnitFullName("NPC") or nil
	if not partner then trade = nil return end
	local guid = UnitGUID and UnitGUID("NPC") or nil
	if issecretvalue and guid ~= nil and issecretvalue(guid) then guid = nil end
	local okG, guild = pcall(GetGuildInfo, "NPC")
	local level = UnitLevel and UnitLevel("NPC") or nil
	trade = { partner = Full(partner), guid = type(guid) == "string" and guid or nil, level = tonumber(level),
		guild = okG and type(guild) == "string" and guild ~= "" and guild or nil, got = 0, gave = 0, gotItems = 0, gaveItems = 0 }
end
local function TradeMoney()
	if not trade then return end
	if GetTargetTradeMoney then trade.got = tonumber(GetTargetTradeMoney()) or trade.got end
	if GetPlayerTradeMoney then trade.gave = tonumber(GetPlayerTradeMoney()) or trade.gave end
	trade.gotItems = Items(GetTradeTargetItemInfo, 1, 6)
	trade.gaveItems = Items(GetTradePlayerItemInfo, 1, 6)
	-- An auditor's reserve attestation reads the bank's gold in the window (nothing completes).
	for _, spec in pairs(expects) do
		if spec.attest and spec.partner and Lower(spec.partner) == Lower(trade.partner) and trade.got > 0 then
			Emit({ kind = "tradeView", partner = trade.partner, got = trade.got, gave = trade.gave })
			break
		end
	end
end
local function TradeInfo(a, b)
	local msg = type(b) == "string" and b or a
	if not trade or msg ~= ERR_TRADE_COMPLETE then return end
	local done = trade
	trade = nil
	Emit({ kind = "trade", partner = done.partner, guid = done.guid, level = done.level, guild = done.guild, got = done.got, gave = done.gave,
		items = { got = done.gotItems, gave = done.gaveItems } })
end
Money.TradeState = function() return trade end -- (tests)

---------------------------------------------------------------------------
-- Mail sent: the recipient, the subject and the gold at SendMail, counted at MAIL_SEND_SUCCESS
-- (a money mail to a stranger may bring up the game's own confirmation first: a cancelled send
-- records nothing).
---------------------------------------------------------------------------

local mailOut -- { to, subject, money, cod, items }

local function MailSending(to, subject)
	if not Money.Active() then mailOut = nil return end
	local money = GetSendMailMoney and tonumber(GetSendMailMoney()) or 0
	local cod = GetSendMailCOD and tonumber(GetSendMailCOD()) or 0
	local items = 0
	if GetSendMailItem then
		for i = 1, tonumber(ATTACHMENTS_MAX_SEND) or 12 do
			local ok, name = pcall(GetSendMailItem, i)
			if ok and name and name ~= "" then items = items + 1 end
		end
	end
	mailOut = { to = Full(to), subject = type(subject) == "string" and subject or "", money = money, cod = cod, items = items }
end
local function MailSent()
	local m = mailOut
	mailOut = nil
	if not m or not m.to then return end
	Emit({ kind = "mailSent", partner = m.to, gave = m.money, subject = m.subject, cod = m.cod, items = { gave = m.items, got = 0 } })
end

---------------------------------------------------------------------------
-- Mail taken (the design): read from the inbox when the player asks for its gold, and counted only
-- once the inbox itself shows it taken (the matched mail's gold at 0, or the mail gone), never by
-- the character's money going up, which another take or a trade could explain. One take waits at
-- a time; a returned mail is flagged as such and is never a deposit.
---------------------------------------------------------------------------

local takes = {} -- { { i, sender, subject, money, returned, cod, days, matching, t } }

local function Header(i)
	local T = ns.Treasury
	if type(T) == "table" and type(T.PlayerMail) == "function" then
		local m = T.PlayerMail(i)
		if not m then return nil end
		local days = select(7, GetInboxHeaderInfo(i))
		m.days = tonumber(days)
		return m
	end
	local _, _, sender, subject, money, cod, days, _, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(i)
	if type(sender) ~= "string" or sender == "" or isGM then return nil end
	return { sender = sender, subject = subject, money = tonumber(money) or 0, returned = wasReturned or nil, cod = tonumber(cod) or 0,
		days = tonumber(days) }
end

-- How many mails in the inbox match a take (its sender, subject and gold): the take is confirmed
-- once fewer do.
local function Matching(p)
	local n = 0
	local count = GetInboxNumItems and tonumber((GetInboxNumItems())) or 0
	for i = 1, count do
		local _, _, sender, subject, money, _, _, _, _, wasReturned = GetInboxHeaderInfo(i)
		if sender == p.rawSender and (subject or "") == (p.subject or "") and tonumber(money) == p.money and (wasReturned and true or false) == p.returned then
			n = n + 1
		end
	end
	return n
end

function Money.TakePending()
	local now = GetTime and GetTime() or ns.Now()
	for i = #takes, 1, -1 do if now - takes[i].t >= Money.TAKE_FOR then table.remove(takes, i) end end
	return takes[1] ~= nil
end

local function MailTaking(i)
	if not Money.Active() or type(i) ~= "number" or not GetInboxHeaderInfo then return end
	local m = Header(i)
	if not m or (m.money or 0) <= 0 or (m.cod or 0) > 0 then return end
	local rawSender = select(3, GetInboxHeaderInfo(i))
	local p = { i = i, rawSender = rawSender, sender = Full(m.sender), subject = m.subject or "", money = m.money, returned = m.returned == true,
		cod = m.cod, days = m.days, t = GetTime and GetTime() or ns.Now() }
	for _, q in ipairs(takes) do
		if q.i == p.i and q.rawSender == p.rawSender and q.subject == p.subject and q.money == p.money then return end
	end
	p.matching = Matching(p)
	if takes[1] then ns.Log("arena money: a take while another waits (%s)", tostring(p.sender)) end
	takes[#takes + 1] = p
end
local function InboxUpdate()
	if not takes[1] then return end
	Money.TakePending()
	local i = 1
	while takes[i] do
		local p = takes[i]
		if Matching(p) < p.matching then
			table.remove(takes, i)
			-- Another take of an identical mail still waiting counts from one mail fewer: one mail
			-- gone confirms one take, never two.
			for _, q in ipairs(takes) do
				if q.rawSender == p.rawSender and q.subject == p.subject and q.money == p.money and q.returned == p.returned then q.matching = q.matching - 1 end
			end
			Emit({ kind = p.returned and "mailReturned" or "mailTaken", partner = p.sender, got = p.money, subject = p.subject, cod = p.cod })
		else
			i = i + 1
		end
	end
end
local function MailFailed(itemID)
	if itemID then return end
	mailOut = nil
	table.remove(takes)
end

---------------------------------------------------------------------------
-- The watcher, installed the first time something is expected (the weight rule: an idle client
-- registers none of this). A hook can't be undone: once installed, each handler returns at once
-- while nothing is expected.
---------------------------------------------------------------------------

Install = function()
	if installed then return end
	installed = true
	local R = ns.RegisterEvent
	R("TRADE_SHOW", function() ns.SafeCall("arena trade", TradeShow) end)
	for _, event in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED" }) do
		R(event, function() ns.SafeCall("arena trade", TradeMoney) end)
	end
	R("UI_INFO_MESSAGE", function(a, b) ns.SafeCall("arena trade", TradeInfo, a, b) end)
	R("TRADE_CLOSED", function()
		local closing = trade
		ns.After(2, "arena trade", function() if trade == closing then trade = nil end end)
	end)
	R("MAIL_SEND_SUCCESS", function() ns.SafeCall("arena mail", MailSent) end)
	R("MAIL_FAILED", function(itemID) ns.SafeCall("arena mail", MailFailed, itemID) end)
	R("MAIL_INBOX_UPDATE", function() ns.SafeCall("arena mail", InboxUpdate) end)
	if hooksecurefunc then -- gp:mail-hooks
		if SendMail then hooksecurefunc("SendMail", function(to, subject) ns.SafeCall("arena mail", MailSending, to, subject) end) end -- gp:mail-hooks
		if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) ns.SafeCall("arena mail", MailTaking, i) end) end -- gp:mail-hooks
		if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) ns.SafeCall("arena mail", MailTaking, i) end) end -- gp:mail-hooks
	end
end
function Money.Installed() return installed end

---------------------------------------------------------------------------
-- Fills (the Dues.SendDues pattern): the addon fills a trade's gold or a mail, the player presses
-- Trade or Send. With the gamepad UI nothing of the game's windows is touched: the line says what
-- to send. Nothing opens by itself.
---------------------------------------------------------------------------

local function Shown(frame) return type(frame) == "table" and frame.IsShown and frame:IsShown() and true or false end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- The trade's gold: the game's own call where it lets the addon make it (SetTradeMoney is
-- HasRestrictions on this client and may be ignored without a word), read back from the window.
-- partner: whom it is for; an open trade with anyone else is left untouched ("partner").
function Money.FillTrade(copper, partner) -- gp:mail-trade-fill
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local who = trade and trade.partner or (ns.UnitFullName and ns.UnitFullName("NPC")) or "?"
	if not ns.Gate.Allowed("mail-trade-fill") then
		ns.Print(L.MONEY_TELL_TRADE:format(Money.Coins(copper), ns.DisplayName(partner or who) or "?"))
		return "gamepad"
	end
	if InCombat() then ns.Print(L.MONEY_COMBAT) return "combat" end
	if Money.TakePending() then ns.Print(L.MONEY_WAIT_TAKE) return "wait" end
	if Money.CopperMode() and Money.CopperFull() then ns.Print(L.MONEY_COPPER_FULL) return "copperfull" end
	if not Shown(TradeFrame) then
		ns.Print(L.MONEY_OPEN_TRADE:format(Money.Coins(copper)))
		return "closed"
	end
	if type(partner) == "string" and partner ~= "" and who ~= "?" and Lower(Full(partner)) ~= Lower(who) then
		ns.Print(L.MONEY_TRADE_PARTNER:format(ns.DisplayName(who) or "?", ns.DisplayName(partner) or "?"))
		return "partner"
	end
	local set = C_TradeInfo and C_TradeInfo.SetTradeMoney or SetTradeMoney
	if not set or (ns.db and ns.db.duesTradeBlocked) then
		ns.Print(L.MONEY_TYPE_TRADE:format(Money.Coins(copper), ns.DisplayName(who) or "?"))
		return "said"
	end
	local ok = pcall(set, copper)
	local after = GetPlayerTradeMoney and tonumber(GetPlayerTradeMoney()) or nil
	if not ok or after ~= copper then
		ns.Print(L.MONEY_TYPE_TRADE:format(Money.Coins(copper), ns.DisplayName(who) or "?"))
		return "said"
	end
	ns.Print(L.MONEY_TRADE_FILLED:format(Money.Coins(copper), ns.DisplayName(who) or "?"))
	return "filled"
end

-- The mail being written: recipient, subject and gold (money, never cash on delivery). The player
-- presses Send; the postage is the game's, on top.
function Money.FillMail(to, subject, copper) -- gp:mail-trade-fill
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	to = Full(to) or to
	subject = tostring(subject or "")
	if not ns.Gate.Allowed("mail-trade-fill") then
		ns.Print(L.MONEY_TELL_MAIL:format(Money.Coins(copper), ns.DisplayName(to) or "?", subject))
		return "gamepad"
	end
	if InCombat() then ns.Print(L.MONEY_COMBAT) return "combat" end
	if Money.TakePending() then ns.Print(L.MONEY_WAIT_TAKE) return "wait" end
	if Money.CopperMode() and Money.CopperFull() then ns.Print(L.MONEY_COPPER_FULL) return "copperfull" end
	if Shown(SendMailFrame) and SendMailNameEditBox and SendMailMoney and MoneyInputFrame_SetCopper then
		SendMailNameEditBox:SetText(ns.TellName(to))
		if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject) end
		if SendMailRadioButton_OnClick then
			pcall(SendMailRadioButton_OnClick, 1)
		elseif SendMailSendMoneyButton and SendMailCODButton then
			SendMailSendMoneyButton:SetChecked(true)
			SendMailCODButton:SetChecked(false)
		end
		local ok = pcall(MoneyInputFrame_SetCopper, SendMailMoney, copper)
		if not ok then
			ns.Print(L.MONEY_TELL_MAIL:format(Money.Coins(copper), ns.DisplayName(to) or "?", subject))
			return "said"
		end
		ns.Print(L.MONEY_MAIL_FILLED:format(ns.DisplayName(to) or "?", Money.Coins(copper), subject))
		return "filled"
	end
	if Shown(MailFrame) then ns.Print(L.MONEY_OPEN_TAB) return "closed" end
	ns.Print(L.MONEY_OPEN_MAIL:format(Money.Coins(copper), ns.DisplayName(to) or "?", subject))
	return "closed"
end

---------------------------------------------------------------------------
-- The copper rehearsal's record (the design): real gold, however small, is written down where the
-- account keeps it (db.arenaCopper, backed up, never dropped by itself), whichever store the
-- rehearsal's objects live in. A line clears only on the recipient's refund receipt or an
-- auditor's write-off.
---------------------------------------------------------------------------

Money.COPPER_MAX = 500
Money.COPPER_FEE_MAX = 30000

function Money.CopperMode()
	local T = ns.ArenaTest
	if type(T) ~= "table" or type(T.Running) ~= "function" then return nil end
	local ok, r = pcall(T.Running)
	if ok and type(r) == "table" and r.money == "p" then return r.rid or "?" end
	return nil
end

function Money.CopperFull()
	local lines = ns.db and ns.db.arenaCopper
	if type(lines) ~= "table" then return false end
	local n = 0
	for _ in pairs(lines) do n = n + 1 end
	return n >= Money.COPPER_MAX
end

local copperSeq = 0
function Money.Copper(r, rid, extra)
	if not ns.db then return nil end
	rid = rid or Money.CopperMode()
	if not rid or type(r) ~= "table" then return nil end
	local out, copper = Money.Net(r)
	if copper <= 0 then return nil end
	local lines = ns.db.arenaCopper
	if type(lines) ~= "table" then lines = {} ns.db.arenaCopper = lines end
	local n = 0
	for _ in pairs(lines) do n = n + 1 end
	-- (At the cap nothing is dropped: an open line never goes by itself. The deposits and fills are
	-- refused before the gold moves once it is full, Money.CopperFull: this is a last guard.)
	if n >= Money.COPPER_MAX then ns.Log("arena copper record full") return nil end
	copperSeq = copperSeq + 1
	local id = ns.Arena.B36(Now()) .. ns.Arena.B36(copperSeq)
	lines[id] = { rid = rid, from = out and ns.me or r.partner, to = out and r.partner or ns.me, copper = copper,
		how = r.kind == "trade" and "t" or "m", dir = out and "out" or "in", at = Now(), state = "open", by = nil,
		what = type(extra) == "table" and extra.what or nil }
	return id
end
function Money.CopperRefunded(id, by)
	local line = ns.db and type(ns.db.arenaCopper) == "table" and ns.db.arenaCopper[id]
	if type(line) ~= "table" or line.state ~= "open" then return false end
	line.state, line.by, line.closed = "refunded", by, Now()
	return true
end
-- An open "out" line to that partner of that amount (a refund came back): refunded.
function Money.CopperBack(partner, copper, rid)
	local lines = ns.db and ns.db.arenaCopper
	if type(lines) ~= "table" then return false end
	local key = Lower(partner)
	local ids = {}
	for id in pairs(lines) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local line = lines[id]
		if type(line) == "table" and line.state == "open" and line.dir == "out" and Lower(line.to) == key and line.copper == copper
			and (rid == nil or line.rid == rid) then
			return Money.CopperRefunded(id, partner)
		end
	end
	return false
end
function Money.CopperOpen(rid)
	local out = {}
	local lines = ns.db and ns.db.arenaCopper
	for id, line in pairs(type(lines) == "table" and lines or {}) do
		if type(line) == "table" and line.state == "open" and (rid == nil or line.rid == rid) then out[#out + 1] = { id = id, line = line } end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end
