local ADDON, ns = ...
local L = ns.L

-- The Treasury of Olympus, kept by the Treasurer (ns.TREASURER of the guild OLYMPUS, see
-- ns.IsTreasurer). His client keeps the book: gold he receives by trade or mail is a donation,
-- gold he gives by trade or mail a payment. What he earns playing is his: the treasury is the
-- book (an opening balance, plus what came in, less what went out), never his character's
-- gold. A trade where he gave items (or his work: an enchant, a lock) for the gold is a sale,
-- one where he got them for his gold a purchase, gold with his own characters his own: they go
-- in the book as not counted, and a click on a line counts it (or stops counting it). The
-- auction house's and the game's mail is no donation.
-- His addon sends the treasury on the channel by itself (every few minutes and after a change):
-- the balance, the totals, the ranking of donors and the latest lines of the book. The King
-- sees all of it; what the rest of the army sees is the King's choice, three switches (the
-- balance, the ranking, the book), and with any of them on the Treasury tab appears for every
-- member with the addon. (The channel is readable by anyone on it: the switches choose what
-- the addon shows, they don't hide the numbers.) The King's word carries the time he gave it,
-- and the Treasurer's treasury repeats it: members who never meet the King online still get
-- his latest word.
--   T8~<guild>~<balance>~<all in>~<all out>~<week in>~<donors this week>~<switches@time|->~<Name:copper,...>~<i|o:copper:Name:m|t:time,...>
--   T1~T~<id>~<guild>~<balance 0|1><ranking 0|1><book 0|1>~<time>        the King's switches (King.lua)
-- (T7 was 0.8.3's treasury: its clients would read this one as theirs, and show it to all.)

local Treasury = {}
ns.Treasury = Treasury

Treasury.MAX = 500           -- lines kept in the book (the sums are kept apart)
Treasury.DAYS_KEPT = 8       -- days of sums kept (today and the week)
Treasury.SHARE_EVERY = 300   -- the Treasurer's client repeats the treasury for late logins
Treasury.SHARE_GAP = 60      -- and sends a change once a minute at most
Treasury.FLAGS_EVERY = 300   -- the King's client repeats his switches
Treasury.REPORT_KEPT = 7 * 86400 -- a treasury not heard of for a week is dropped
Treasury.RANK_SENT = 10      -- donors in the ranking sent
Treasury.BOOK_SENT = 15      -- latest lines of the book sent
Treasury.BOOK_SHOWN = 40     -- lines of his own book the Treasurer sees, 40 more a click
Treasury.PENDING_FOR = 30    -- seconds a mail's gold may take to arrive once asked for
Treasury.MAX_COPPER = 2147483647

Treasury.mode = "summary"    -- what the tab shows: summary or book

local trade                  -- the trade window open: { name, got, gave, gotItems, gaveItems }
local mailOut                -- a mail with gold on its way: { to, money }
local report                 -- the Treasurer's last treasury: { balance, allIn, allOut, week, donors, rank, book, t, from }
local lastShare, sharePending = -math.huge, false
local lastFlagsSent = -math.huge
local pending = {}           -- mail gold asked for, until it arrives: { key, sender, money, returned, t }
local lastMoney              -- the character's gold as last seen while takes wait
local bookShown = Treasury.BOOK_SHOWN

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff6060" .. s .. "|r" end

local function Book()
	ns.rdb.treasury = ns.rdb.treasury or {}
	return ns.rdb.treasury
end
local function DayKey(t) return date and date("%Y-%m-%d", t) or tostring(math.floor(t / 86400)) end
-- Today and the 6 days before, by the calendar (a day of 23 or 25 hours is still one day).
local function WeekKeys(now)
	local keys, d = {}, date and date("*t", now)
	for back = 0, 6 do
		keys[#keys + 1] = d and DayKey(time({ year = d.year, month = d.month, day = d.day - back, hour = 12 })) or DayKey(now - back * 86400)
	end
	return keys
end
-- The clock the King's switches are dated by: the server's, the same on every client.
local function Clock() return GetServerTime and GetServerTime() or ns.Now() end

-- 12g 30s 5c, with the coin icons when the client has them (a minus sign when negative).
function Treasury.Coins(copper)
	copper = math.floor(tonumber(copper) or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	if GetCoinTextureString then
		local ok, s = pcall(GetCoinTextureString, copper)
		if ok and s then return sign .. s end
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return sign .. table.concat(parts, " ")
end
-- Gold alone, for the big numbers: "12,345g" (under a gold piece, the silver too).
function Treasury.GoldText(copper)
	copper = math.floor(tonumber(copper) or 0)
	if math.abs(copper) < 10000 then return Treasury.Coins(copper) end
	return (copper < 0 and "-" or "") .. ns.FormatNumber(math.floor(math.abs(copper) / 10000)) .. "g"
end
-- For Discord: plain text.
local function Plain(copper)
	copper = math.floor(tonumber(copper) or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	return sign .. (g > 0 and ("%sg %ds"):format(ns.FormatNumber(g), s) or ("%ds %dc"):format(s, copper % 100))
end

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------

-- The Treasurer himself (or the author's "Treasurer's view", from the Workshop).
function Treasury.IsTreasurer()
	if ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) then return true end
	return Treasury.DevView()
end
function Treasury.DevView()
	return ns.db and ns.db.devTreasurerView == true and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() or false
end
function Treasury.SetDevView(on)
	ns.db.devTreasurerView = on and true or nil
	ns.Print(on and L.DEV_TREASURER_VIEW_NOW_ON or L.DEV_TREASURER_VIEW_NOW_OFF)
	ns.Fire("DATA_CHANGED")
end

local function IsKingView() return ns.King.IsKing() or ns.King.Preview() end

-- The King's switches: what the army sees (every client keeps the King's last word). The
-- author's Asmond's view keeps its own, on his screen only: the real King's word stays as it is.
local FLAGS = { "balance", "ranking", "book" }
function Treasury.Flags()
	local f
	if ns.King.Preview() then f = ns.db and ns.db.previewTreasuryFlags else f = ns.rdb and ns.rdb.treasuryFlags end
	return type(f) == "table" and f or {}
end
function Treasury.Shows(what) return Treasury.Flags()[what] == true end
local function FlagDigits(f)
	local d = {}
	for i, k in ipairs(FLAGS) do d[i] = f[k] and "1" or "0" end
	return table.concat(d)
end
function Treasury.AnyShown()
	for _, k in ipairs(FLAGS) do if Treasury.Shows(k) then return true end end
	return false
end

-- Who has the tab: the Treasurer, the King (where a Treasurer can be, or once a treasury came;
-- the author's view always), and every member once the King shows the army something.
function Treasury.Visible()
	if Treasury.IsTreasurer() or ns.King.Preview() then return true end
	if ns.King.IsKing() then return (ns.splitNames and ns.faction ~= "Horde") or Treasury.Report() ~= nil end
	return ns.IsMember() and Treasury.AnyShown() and Treasury.Report() ~= nil
end

---------------------------------------------------------------------------
-- The book (the Treasurer's client)
---------------------------------------------------------------------------

-- A line's copper into its day (copper < 0: out of it), while the day is in the week kept.
local function DayCount(s, e, copper, now)
	local key = DayKey(e.t)
	local day = s.days[key]
	if not day and copper > 0 and now - e.t <= Treasury.DAYS_KEPT * 86400 then
		day = { inn = 0, out = 0, by = {} }
		s.days[key] = day
	end
	if not day then return end
	if e.out then
		day.out = math.max(0, day.out + copper)
	else
		day.inn = math.max(0, day.inn + copper)
		day.by[e.name] = (day.by[e.name] or 0) + copper
		if day.by[e.name] <= 0 then day.by[e.name] = nil end
	end
end

-- The sums, whatever the book keeps: all time (in, out, each donor's), and per day (in, out,
-- each donor's) for today and the week. Rebuilt from the book once (0.8.3 kept no donors):
-- the days too, so a line counted then comes out of the day it went into.
local function Sums()
	local s = ns.rdb.treasurySums
	if type(s) ~= "table" or s.version ~= 2 then
		s = { version = 2, allIn = 0, allOut = 0, byDonor = {}, days = {} }
		ns.rdb.treasurySums = s
		local now = ns.Now()
		for _, e in ipairs(Book()) do
			if not e.excluded then
				if e.out then s.allOut = s.allOut + e.money else
					s.allIn = s.allIn + e.money
					s.byDonor[e.name] = (s.byDonor[e.name] or 0) + e.money
				end
				DayCount(s, e, e.money, now)
			end
		end
	end
	return s
end

-- An entry into the sums (sign 1) or out of them (sign -1).
local function Count(e, sign)
	local s = Sums()
	local copper = e.money * sign
	local now = ns.Now()
	if e.out then
		s.allOut = math.max(0, s.allOut + copper)
	else
		s.allIn = math.max(0, s.allIn + copper)
		s.byDonor[e.name] = (s.byDonor[e.name] or 0) + copper
		if s.byDonor[e.name] <= 0 then s.byDonor[e.name] = nil end
	end
	DayCount(s, e, copper, now)
	local oldest = DayKey(now - Treasury.DAYS_KEPT * 86400)
	for k in pairs(s.days) do if k < oldest then s.days[k] = nil end end
end

-- The account's characters (the Treasurer's alts): gold between them is his own.
local function OwnKey(name) return tostring(ns.FullName(ns.Normal(name)) or name):lower() end
function Treasury.IsOwnCharacter(name)
	local mine = ns.db and ns.db.myCharacters
	return type(name) == "string" and type(mine) == "table" and mine[OwnKey(name)] == true
end

function Treasury.Opening() return tonumber(ns.rdb and ns.rdb.treasuryOpening) or 0 end

-- The treasury: the opening balance, plus what came in, less what went out (counted lines).
function Treasury.Balance()
	local s = Sums()
	return Treasury.Opening() + s.allIn - s.allOut
end

-- out: a payment. o: { excluded = true, kind = "sale"|"purchase"|"own", quiet = true }.
function Treasury.Record(name, copper, how, out, o)
	o = o or {}
	copper = math.floor(tonumber(copper) or 0)
	if copper <= 0 or type(name) ~= "string" or name == "" then return end
	if Treasury.IsOwnCharacter(name) then o = { excluded = true, kind = "own", quiet = o.quiet } end
	local book = Book()
	Sums() -- (built from the book as it was, before this line joins it)
	local who = ns.DisplayName(ns.Normal(name)) or name
	local e = { name = who, money = copper, how = how, t = ns.Now(), out = out or nil, excluded = o.excluded or nil, kind = o.kind }
	book[#book + 1] = e
	while #book > Treasury.MAX do table.remove(book, 1) end
	if not e.excluded then Count(e, 1) end
	-- The King (and the army) see it soon (once a minute at most).
	Treasury.Share()
	if not o.quiet then
		if e.excluded then
			local say = e.kind == "sale" and L.TREASURY_SALE or e.kind == "own" and L.TREASURY_OWN or L.TREASURY_PURCHASE
			ns.Print(say:format(who, Treasury.Coins(copper)))
		else
			local line = (out and L.TREASURY_PAID or L.TREASURY_DONATION):format(who, Treasury.Coins(copper))
			-- A donation says what the donor gave in all, this one included (0.9.6, the Treasurer's idea).
			if not out then
				for _, g in ipairs(Treasury.Totals().ranking) do
					if g.name == who then line = line .. " " .. L.TREASURY_IN_ALL:format(Treasury.Coins(g.money)) break end
				end
			end
			ns.Print(line)
			if not out then ns.PlayAlert("soft") end
		end
	end
	ns.Fire("TREASURY_CHANGED")
	return e
end

-- A line of the book counted, or no longer (the Treasurer's click: a sale that was a
-- donation, a payment that was his own).
function Treasury.Toggle(e)
	if not Treasury.IsTreasurer() or type(e) ~= "table" then return end
	e.excluded = not e.excluded or nil
	Count(e, e.excluded and -1 or 1)
	Treasury.Share()
	ns.Fire("TREASURY_CHANGED")
end

-- "12345", "12,345", "12345g", "12345g 50s", "50s 20c", "1500.5" (1500g 50s): copper, or nil.
function Treasury.ParseGold(text)
	text = tostring(text or ""):lower()
	-- Thousands: a "." or "," before exactly three digits ("1.500", "1,500,000").
	local n
	repeat text, n = text:gsub("(%d)[.,](%d%d%d)%f[%D]", "%1%2") until n == 0
	-- A decimal part is silver ("1500.5", "1500,50").
	local whole, frac = text:match("^%s*(%d+)[.,](%d%d?)%s*g?%s*$")
	if whole then
		if #frac == 1 then frac = frac .. "0" end
		return math.min(tonumber(whole) * 10000 + tonumber(frac) * 100, Treasury.MAX_COPPER)
	end
	if text:find("[.,]") then return nil end
	local g = tonumber(text:match("(%d+)%s*g")) or 0
	local s = tonumber(text:match("(%d+)%s*s")) or 0
	local c = tonumber(text:match("(%d+)%s*c")) or 0
	if g == 0 and s == 0 and c == 0 then
		local plain = tonumber(text:match("^%s*(%d+)%s*$"))
		if not plain then return nil end
		g = plain
	end
	return math.min(g * 10000 + s * 100 + c, Treasury.MAX_COPPER)
end

function Treasury.SetOpening(input)
	if not Treasury.IsTreasurer() then return ns.Print(L.TREASURY_ONLY) end
	local copper = Treasury.ParseGold(input)
	if not copper then return ns.Print(L.TREASURY_OPENING_USAGE) end
	ns.rdb.treasuryOpening = copper
	ns.Print(L.TREASURY_OPENING_SET:format(Treasury.Coins(copper)))
	Treasury.Share()
	ns.Fire("TREASURY_CHANGED")
end

-- Trades: what each side put in, as the window last showed it (read again once complete, it
-- can say 0), counted when the game says the trade is complete.
local function AnyItem(info, first, last)
	if not info then return false end
	for i = first, last do
		local name = info(i)
		if name and name ~= "" then return true end
	end
	return false
end
function Treasury.TradeMoney()
	if not trade then return end
	if GetTargetTradeMoney then trade.got = tonumber(GetTargetTradeMoney()) or trade.got end
	if GetPlayerTradeMoney then trade.gave = tonumber(GetPlayerTradeMoney()) or trade.gave end
	-- Slot 7 is the one not traded: an item enchanted or a lock opened there. His work on
	-- their item is a sale (a service), theirs on his a purchase.
	trade.gaveItems = AnyItem(GetTradePlayerItemInfo, 1, 6) or AnyItem(GetTradeTargetItemInfo, 7, 7)
	trade.gotItems = AnyItem(GetTradeTargetItemInfo, 1, 6) or AnyItem(GetTradePlayerItemInfo, 7, 7)
end

function Treasury.TradeShow()
	if not Treasury.IsTreasurer() then return end
	local name = ns.UnitFullName and ns.UnitFullName("NPC") or (UnitName and UnitName("NPC"))
	trade = name and { name = name, got = 0, gave = 0 } or nil
end

function Treasury.Info(a, b)
	-- Classic passes (type, message), older clients the message alone.
	local msg = type(b) == "string" and b or a
	if not trade or msg ~= ERR_TRADE_COMPLETE then return end
	local done = trade
	trade = nil
	-- One line, the gold both ways netted (change given back is part of the deal). Gold for
	-- his items: a sale, his. His gold for items: a purchase, his. Not counted unless he says
	-- so (a click on the line).
	local net = done.got - done.gave
	if net > 0 then
		Treasury.Record(done.name, net, "trade", nil, done.gaveItems and { excluded = true, kind = "sale" } or nil)
	elseif net < 0 then
		Treasury.Record(done.name, -net, "trade", true, done.gotItems and { excluded = true, kind = "purchase" } or nil)
	end
end

-- Mail sent with gold: counted once the game says it went.
function Treasury.MailSending(to)
	if not Treasury.IsTreasurer() then return end
	local money = GetSendMailMoney and tonumber(GetSendMailMoney()) or 0
	mailOut = money > 0 and type(to) == "string" and to ~= "" and { to = to, money = money } or nil
end
function Treasury.MailSent()
	local m = mailOut
	mailOut = nil
	if m then Treasury.Record(m.to, m.money, "mail", true) end
end

-- The game's own mail (the auction house, cash on delivery): not from a player. Their
-- subjects are the client's format strings, "%s" standing for the item.
local SYSTEM_SUBJECTS = { "AUCTION_OUTBID_MAIL_SUBJECT", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
	"AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "COD_PAYMENT" }
local systemPatterns
local function SystemMail(subject)
	if type(subject) ~= "string" then return false end
	if not systemPatterns or #systemPatterns == 0 then
		systemPatterns = {}
		for _, key in ipairs(SYSTEM_SUBJECTS) do
			local f = _G[key]
			if type(f) == "string" and f ~= "" then
				local p = f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
				systemPatterns[#systemPatterns + 1] = "^" .. p .. "$"
			end
		end
	end
	for _, p in ipairs(systemPatterns) do
		if subject:find(p) then return true end
	end
	return false
end

-- A payment by mail that came back (returned, or never opened): no longer counted.
local function Returned(sender, money)
	local who = ns.DisplayName(ns.Normal(sender)) or sender
	local book = Book()
	for i = #book, 1, -1 do
		local e = book[i]
		if e.out and e.how == "mail" and not e.excluded and e.money == money and OwnKey(e.name) == OwnKey(sender) then
			e.returned = true
			Treasury.Toggle(e)
			return ns.Print(L.TREASURY_RETURNED:format(who, Treasury.Coins(money)))
		end
	end
end

local function MailClock() return GetTime and GetTime() or ns.Now() end
local function Settle(p)
	if p.returned then return Returned(p.sender, p.money) end
	Treasury.Record(p.sender, p.money, "mail")
end
local function DropStale(now)
	for i = #pending, 1, -1 do if now - pending[i].t >= Treasury.PENDING_FOR then table.remove(pending, i) end end
end

-- A donation by mail is counted when its gold arrives. The take is read from the mail when the
-- Treasurer asks for its gold (the money button, or a mail addon's "open all": TakeInboxMoney,
-- AutoLootMailItem), just before the game empties it, and waits for the gold (PLAYER_MONEY,
-- Treasury.MoneyChanged). A second click on that mail meanwhile counts nothing; a take the
-- server refuses (MAIL_FAILED) is dropped, its gold still in the mail; the mail that moves up
-- into its place once it is gone is another.
function Treasury.MailTaking(i)
	if not Treasury.IsTreasurer() or not GetInboxHeaderInfo or type(i) ~= "number" then return end
	local _, _, sender, subject, money, _, _, _, _, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(i)
	money = tonumber(money) or 0
	local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
	if money <= 0 or type(sender) ~= "string" or sender == "" or isGM or invoice or SystemMail(subject) then return end
	if not wasReturned and canReply == false then return end
	if not GetMoney then return Settle({ sender = sender, money = money, returned = wasReturned }) end
	local now = MailClock()
	DropStale(now)
	local key = ("%d|%s|%s|%d"):format(i, sender, tostring(subject or ""), money)
	for _, p in ipairs(pending) do if p.key == key then return end end
	if #pending == 0 then lastMoney = GetMoney() end
	pending[#pending + 1] = { key = key, sender = sender, money = money, returned = wasReturned or nil, t = now }
end

-- The character's gold went up: the takes it pays for are counted (the one of that exact
-- amount first, else in order while the gold covers them; gold from anywhere else is not).
function Treasury.MoneyChanged()
	if #pending == 0 or not GetMoney then return end
	local money = GetMoney()
	local gained = money - (lastMoney or money)
	lastMoney = money
	DropStale(MailClock())
	if gained <= 0 then return end
	for i, p in ipairs(pending) do
		if p.money == gained then
			table.remove(pending, i)
			return Settle(p)
		end
	end
	local i = 1
	while pending[i] do
		if pending[i].money <= gained then
			gained = gained - pending[i].money
			Settle(table.remove(pending, i))
		else
			i = i + 1
		end
	end
end
-- A take the server refused (the latest): its gold is still in the mail, nothing counted.
function Treasury.MailFailed() table.remove(pending) end

-- The sums: today, this week (today and the 6 days before), all time; the givers of the
-- week and of all time, most generous first.
function Treasury.Totals()
	local now = ns.Now()
	local s = Sums()
	local t = { todayIn = 0, todayOut = 0, weekIn = 0, weekOut = 0, allIn = s.allIn, allOut = s.allOut, givers = {}, ranking = {} }
	local by = {}
	for back, key in ipairs(WeekKeys(now)) do
		local day = s.days[key]
		if day then
			t.weekIn, t.weekOut = t.weekIn + day.inn, t.weekOut + day.out
			if back == 1 then t.todayIn, t.todayOut = day.inn, day.out end
			for name, copper in pairs(day.by) do
				local g = by[name]
				if not g then
					g = { name = name, money = 0 }
					by[name] = g
					t.givers[#t.givers + 1] = g
				end
				g.money = g.money + copper
			end
		end
	end
	for name, copper in pairs(s.byDonor) do t.ranking[#t.ranking + 1] = { name = name, money = copper } end
	local function Most(a, b)
		if a.money ~= b.money then return a.money > b.money end
		return a.name < b.name
	end
	table.sort(t.givers, Most)
	table.sort(t.ranking, Most)
	return t
end

---------------------------------------------------------------------------
-- Sharing: the Treasurer's treasury, and everyone's copy of it
---------------------------------------------------------------------------

-- The Treasurer's yes (0.9.3): his book and the guild bank go out only once he chose to share
-- them (ns.db.treasurerShares, nil until he answers). They go on the Olympus channel, where
-- every client receives the bytes; the addon shows them to the King, and to the army only
-- with the King's switches. Turned off, they are withdrawn (TX) from 0.9.3 screens at once.
function Treasury.Consent() return ns.db and ns.db.treasurerShares end
function Treasury.IsTreasurer() return ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) end

-- Only the real Treasurer's client sends (never the author's view), and only with his yes.
local function CanSend() return Treasury.IsTreasurer() and Treasury.Consent() == true end
Treasury.CanSend = CanSend

function Treasury.SetConsent(on)
	if not Treasury.IsTreasurer() then return ns.Print(L.TREASURER_ONLY) end
	ns.db.treasurerShares = on and true or false
	ns.Print(on and L.TREASURER_SHARE_ON or L.TREASURER_SHARE_OFF)
	if on then
		Treasury.Share(true)
		if ns.Bank and ns.Bank.Share then ns.Bank.Share(true) end
	else
		ns.Comm.Send("CHANNEL", "TX~" .. (GetGuildInfo("player") or ""), "treasury")
	end
	ns.Fire("TREASURY_CHANGED")
end

-- The Treasurer withdrew his book and the bank: gone from our screen (his word, his name).
function Treasury.HandleWithdraw(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guild = text:match("^TX~(.*)$")
	if not guild or not ns.IsTreasurer(sender, guild) or not ns.IsKingGuild(guild) then return end
	report = nil
	if ns.rdb then ns.rdb.treasuryReport, ns.rdb.bankReport = nil, nil end
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end
ns.Comm.Handle("TX", function(...) Treasury.HandleWithdraw(...) end)

-- Asked once a session until he answers: what goes out and who reads it is in the question.
local asked = false
StaticPopupDialogs["OLYMPUS_TREASURER_SHARE"] = {
	text = L.TREASURER_SHARE_ASK,
	button1 = L.TREASURER_SHARE_YES,
	button2 = L.TREASURER_SHARE_NO,
	OnAccept = function() ns.SafeCall("treasurer share", Treasury.SetConsent, true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("treasurer share", Treasury.SetConsent, false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	noCancelOnEscape = true, -- Escape is no answer: asked again next session
	preferredIndex = 3,
}
function Treasury.AskConsent()
	if asked or not Treasury.IsTreasurer() or Treasury.Consent() ~= nil then return false end
	if (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) then return false end
	asked = true
	ns.ShowDialog("OLYMPUS_TREASURER_SHARE", ns.Comm.Audience and ns.Comm.Audience() or "")
	return true
end

local function Clean(name) return (tostring(name or ""):gsub("[~:,|%c]", "")) end

function Treasury.Message()
	local t = Treasury.Totals()
	local rank = {}
	for i = 1, math.min(Treasury.RANK_SENT, #t.ranking) do
		rank[#rank + 1] = ("%s:%d"):format(Clean(t.ranking[i].name), math.min(t.ranking[i].money, Treasury.MAX_COPPER))
	end
	local lines, book = {}, Book()
	for i = #book, 1, -1 do
		local e = book[i]
		if not e.excluded then
			lines[#lines + 1] = ("%s:%d:%s:%s:%d"):format(e.out and "o" or "i", math.min(e.money, Treasury.MAX_COPPER), Clean(e.name),
				e.how == "mail" and "m" or "t", e.t or 0)
			if #lines >= Treasury.BOOK_SENT then break end
		end
	end
	local balance = math.max(-Treasury.MAX_COPPER, math.min(Treasury.Balance(), Treasury.MAX_COPPER))
	local function U(n) return math.max(0, math.min(math.floor(tonumber(n) or 0), Treasury.MAX_COPPER)) end
	-- The King's word as the Treasurer's client last heard it, with its time.
	local f = ns.rdb.treasuryFlags
	local word = type(f) == "table" and tonumber(f.at) and (FlagDigits(f) .. "@" .. math.floor(f.at)) or "-"
	return ("T8~%s~%d~%d~%d~%d~%d~%s~%s~%s"):format(GetGuildInfo("player") or "", balance, U(t.allIn), U(t.allOut), U(t.weekIn),
		#t.givers, word, table.concat(rank, ","), table.concat(lines, ","))
end

function Treasury.Share(force)
	if not CanSend() then return end
	local now = ns.Now()
	-- A change inside the gap goes out once the gap is over, not never.
	if not force and now - lastShare < Treasury.SHARE_GAP then
		if not sharePending then
			sharePending = true
			ns.After(lastShare + Treasury.SHARE_GAP - now, "treasury share", function()
				sharePending = false
				Treasury.Share(true)
			end)
		end
		return
	end
	lastShare = now
	local msg = Treasury.Message()
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "treasury") else ns.Comm.SendChunked(msg) end
end

local function Num(s)
	local n = tonumber(s) or 0
	return math.max(-Treasury.MAX_COPPER, math.min(n, Treasury.MAX_COPPER))
end

function Treasury.HandleReport(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guild, rest = text:match("^T8~([^~]*)~(.*)$")
	if not guild then return end
	-- The Treasurer himself: that name (the server sets it), speaking for the King's guild
	-- OLYMPUS. No census vote is asked for: it proves nothing more about him, and forged votes
	-- could have silenced him.
	if not ns.IsTreasurer(sender, guild) or not ns.IsKingGuild(guild) then return end
	local balance, allIn, allOut, week, donors, word, rank, book = rest:match("^(%-?%d+)~(%-?%d+)~(%-?%d+)~(%-?%d+)~(%d+)~([^~]*)~([^~]*)~(.*)$")
	if not balance then return end
	local function U(n) return math.max(0, Num(n)) end
	local r = { balance = Num(balance), allIn = U(allIn), allOut = U(allOut), week = U(week),
		donors = math.min(tonumber(donors) or 0, 9999), rank = {}, book = {}, t = ns.Now(), from = ns.FullName(sender) }
	for name, copper in rank:gmatch("([^,:]+):(%d+)") do
		local clean = ns.King.CleanName(name)
		if clean and #r.rank < Treasury.RANK_SENT then r.rank[#r.rank + 1] = { name = clean, money = Num(copper) } end
	end
	for kind, copper, name, how, when in book:gmatch("([io]):(%d+):([^:,]+):([mt]):(%d+)") do
		local clean = ns.King.CleanName(name)
		if clean and #r.book < Treasury.BOOK_SENT then
			r.book[#r.book + 1] = { out = kind == "o" or nil, money = Num(copper), name = clean, how = how == "m" and "mail" or "trade",
				t = math.min(tonumber(when) or 0, ns.Now()) }
		end
	end
	report = r
	-- Kept across sessions: the army sees the treasury as last heard.
	ns.rdb.treasuryReport = r
	-- The King's word it repeats, if newer than ours.
	local b, k, o, at = word:match("^([01])([01])([01])@(%d+)$")
	if b then Treasury.TakeFlags(b .. k .. o, tonumber(at), sender) end
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED") -- the tab may appear
end
ns.Comm.Handle("T8", function(...) Treasury.HandleReport(...) end)

function Treasury.Report()
	if not report and type(ns.rdb and ns.rdb.treasuryReport) == "table" and ns.rdb.treasuryReport.rank then report = ns.rdb.treasuryReport end
	if report and ns.Now() - (tonumber(report.t) or 0) > Treasury.REPORT_KEPT then
		report = nil
		if ns.rdb then ns.rdb.treasuryReport = nil end
	end
	return report
end

---------------------------------------------------------------------------
-- The King's switches: what the army sees
---------------------------------------------------------------------------

-- The King's client repeats his word, with the time he gave it (a client that never heard it
-- from him sends nothing: it takes his word as the Treasurer repeats it).
function Treasury.SendFlags(force)
	local f = ns.rdb and ns.rdb.treasuryFlags
	if not ns.King.IsKing() or type(f) ~= "table" or not tonumber(f.at) then return end
	local now = ns.Now()
	if not force and now - lastFlagsSent < Treasury.FLAGS_EVERY then return end
	lastFlagsSent = now
	ns.Comm.Send("CHANNEL", ("T1~T~%d~%s~%s~%d"):format(ns.King.NewId(), GetGuildInfo("player") or "", FlagDigits(f), math.floor(f.at)), "treasuryflags")
end

-- The King's switch (the author's Asmond's view: its own switches, on his screen only).
function Treasury.SetFlag(what, on)
	if not IsKingView() then return ns.Print(L.THRONE_ONLY_KING) end
	local f = {}
	for _, k in ipairs(FLAGS) do f[k] = Treasury.Shows(k) end
	f[what] = on and true or false
	-- Each word newer than the last, two clicks in one second too (the army takes the newest).
	local prev = ns.King.Preview() and ns.db.previewTreasuryFlags or ns.rdb.treasuryFlags
	f.t, f.at = ns.Now(), math.max(Clock(), (type(prev) == "table" and tonumber(prev.at) or 0) + 1)
	ns.Print(L["TREASURY_FLAG_" .. what:upper() .. (on and "_ON" or "_OFF")])
	if ns.King.Preview() then
		ns.db.previewTreasuryFlags = f
		ns.Print(L.THRONE_PREVIEW_NOTE)
	else
		ns.rdb.treasuryFlags = f
		Treasury.SendFlags(true)
	end
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end

-- The King's word ("101" and the time he gave it), from him or repeated by the Treasurer:
-- taken when newer than the one kept (a time a little ahead of ours at most).
function Treasury.TakeFlags(digits, at, sender)
	local b, r, k = tostring(digits or ""):match("^([01])([01])([01])$")
	at = tonumber(at)
	if not b or not at or at > Clock() + 600 then return end
	local kept = ns.rdb.treasuryFlags
	if type(kept) == "table" and (tonumber(kept.at) or 0) >= at then return end
	local was = type(kept) == "table" and FlagDigits(kept) or "000"
	local f = { balance = b == "1", ranking = r == "1", book = k == "1", at = at, t = ns.Now(), from = ns.FullName(sender) }
	ns.rdb.treasuryFlags = f
	if FlagDigits(f) ~= was then
		-- The Treasurer is told who sees his treasury now.
		if CanSend() then ns.Print(Treasury.WhoSees()) end
		ns.Fire("TREASURY_CHANGED")
		ns.Fire("DATA_CHANGED") -- the tab appears or goes
	end
end
ns.King.Register("T", function(sender, id, rest)
	local digits, at = tostring(rest or ""):match("^([01][01][01])~(%d+)$")
	Treasury.TakeFlags(digits, at, sender)
end)

ns.On("LOGIN", function()
	-- The Treasurer's question (his yes to sharing), once the guild is known; tried again later
	-- while he is busy (combat, an instance).
	ns.Every(60, "treasurer question", function() ns.SafeCall("treasurer question", Treasury.AskConsent) end)
	-- The account's characters, for the Treasurer's gold between his own.
	if ns.db and ns.me then
		ns.db.myCharacters = ns.db.myCharacters or {}
		ns.db.myCharacters[OwnKey(ns.me)] = true
	end
	ns.RegisterEvent("TRADE_SHOW", function() ns.SafeCall("treasury trade", Treasury.TradeShow) end)
	for _, event in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED" }) do
		ns.RegisterEvent(event, function() ns.SafeCall("treasury trade", Treasury.TradeMoney) end)
	end
	ns.RegisterEvent("UI_INFO_MESSAGE", function(a, b) ns.SafeCall("treasury trade", Treasury.Info, a, b) end)
	-- The window closes before or after the "trade complete" message, depending on the client:
	-- this trade is forgotten a little later (not the next one, opened meanwhile).
	ns.RegisterEvent("TRADE_CLOSED", function()
		local closing = trade
		ns.After(2, "treasury trade", function() if trade == closing then trade = nil end end)
	end)
	if hooksecurefunc then
		if SendMail then hooksecurefunc("SendMail", function(to) ns.SafeCall("treasury mail", Treasury.MailSending, to) end) end
		if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) ns.SafeCall("treasury mail", Treasury.MailTaking, i) end) end
		if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) ns.SafeCall("treasury mail", Treasury.MailTaking, i) end) end
	end
	ns.RegisterEvent("MAIL_SEND_SUCCESS", function() ns.SafeCall("treasury mail", Treasury.MailSent) end)
	ns.RegisterEvent("MAIL_FAILED", function() mailOut = nil; Treasury.MailFailed() end)
	ns.RegisterEvent("PLAYER_MONEY", function() ns.SafeCall("treasury mail", Treasury.MoneyChanged) end)
	-- The treasury and the King's switches, repeated for late logins.
	ns.Every(60, "treasury share", function()
		if ns.Now() - lastShare >= Treasury.SHARE_EVERY then Treasury.Share(true) end
		Treasury.SendFlags()
	end)
	ns.After(30, "treasury share", function()
		Treasury.Share(true)
		Treasury.SendFlags(true)
		-- The Treasurer is told once who sees his treasury (and again when the King changes it).
		if CanSend() and not ns.rdb.treasuryToldWho then
			ns.rdb.treasuryToldWho = true
			ns.Print(Treasury.WhoSees())
		end
	end)
end)

---------------------------------------------------------------------------
-- What the tab shows
---------------------------------------------------------------------------

-- A paragraph in short rows, grey unless said (the list's rows are one line each).
local function Para(lines, text, color)
	color = color or Grey
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > 58 then
			lines[#lines + 1] = { text = color(row) }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = color(row) } end
	return lines
end

-- What the King shows the army now ("the balance, the book").
local function ShownParts()
	local shown = {}
	for _, k in ipairs(FLAGS) do if Treasury.Shows(k) then shown[#shown + 1] = L["TREASURY_PART_" .. k:upper()] end end
	return shown
end
-- Who sees the treasury, told to the Treasurer: he and the King, and what the King shows the army.
function Treasury.WhoSees()
	local shown = ShownParts()
	return #shown > 0 and L.TREASURY_YOU_AND_KING_BUT:format(table.concat(shown, ", ")) or L.TREASURY_YOU_AND_KING
end
-- The book's way back to the summary: what the viewer will find there.
function Treasury.SummaryTip()
	local parts = {}
	for _, k in ipairs({ "balance", "ranking" }) do
		if Treasury.MaySee(k) then parts[#parts + 1] = L["TREASURY_PART_" .. k:upper()] end
	end
	return #parts > 0 and L.TREASURY_SUMMARY_BTN_TIP:format(table.concat(parts, ", ")) or L.TREASURY_SUMMARY_BTN_TIP_PLAIN
end

function Treasury.Show(mode)
	Treasury.mode = mode
	bookShown = Treasury.BOOK_SHOWN
	ns.Fire("TREASURY_CHANGED")
end

-- Who looks at the tab: the Treasurer (his book), the King (the treasury, all of it), a member
-- (what the King shows).
function Treasury.Role()
	if Treasury.IsTreasurer() then return "treasurer" end
	if IsKingView() then return "king" end
	return "member"
end

-- What a role may see: everything for the Treasurer and the King, the King's switches for
-- the army.
function Treasury.MaySee(what)
	local role = Treasury.Role()
	return role ~= "member" or Treasury.Shows(what)
end

local function RankLines(lines, rank)
	lines[#lines + 1] = { header = true, text = L.TREASURY_RANKING }
	if #rank == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for i, g in ipairs(rank) do
		if i > Treasury.RANK_SENT then break end
		lines[#lines + 1] = { indent = 1, text = (i <= 3 and Gold or tostring)(("%d. %s"):format(i, g.name)), right = Treasury.Coins(g.money) }
	end
end

local KIND_NOTE = { sale = "TREASURY_KIND_SALE", purchase = "TREASURY_KIND_PURCHASE", own = "TREASURY_KIND_OWN" }

-- A line of the book: why it is not counted first (the row is cut at its end), in the
-- tooltip too.
local function BookRow(e, clickable)
	local how = e.how == "mail" and L.TREASURY_MAIL or L.TREASURY_TRADE
	local label = (e.out and L.TREASURY_TO or L.TREASURY_FROM):format(e.name)
	local note = e.excluded and (e.returned and L.TREASURY_KIND_RETURNED or L[KIND_NOTE[e.kind] or "TREASURY_NOT_COUNTED"]) or nil
	local amount = Treasury.Coins(e.money)
	local when = how .. ", " .. ns.Ago(e.t)
	return {
		indent = 1,
		text = (e.excluded and Grey(label) or label) .. "  " .. Grey("(" .. (note and (note .. ", ") or "") .. when .. ")"),
		right = e.excluded and Grey(amount) or (e.out and Red("-" .. amount) or Green("+" .. amount)),
		onClick = clickable and function() Treasury.Toggle(e) end or nil,
		tooltip = clickable and function(tt)
			tt:AddLine(label .. "  " .. amount, 1, 0.82, 0)
			tt:AddLine(note and (note .. ", " .. when) or when, 0.8, 0.8, 0.8, true)
			tt:AddLine(e.excluded and L.TREASURY_CLICK_COUNT or L.TREASURY_CLICK_UNCOUNT, 1, 1, 1, true)
		end or nil,
	}
end

-- The book: in and out, newest first. The Treasurer's own (every line, a click counts it or
-- not), or the lines his treasury last carried.
local function BookLines(role)
	local lines = { { text = Gold("< " .. L.TREASURY_TITLE), onClick = function() Treasury.Show("summary") end, gapAfter = true } }
	lines[#lines + 1] = { header = true, text = L.TREASURY_BOOK }
	if role == "treasurer" then
		Para(lines, L.TREASURY_BOOK_HOW)
		lines[#lines].gapAfter = true
		local book = Book()
		if #book == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
		local last = math.max(1, #book - bookShown + 1)
		for i = #book, last, -1 do lines[#lines + 1] = BookRow(book[i], true) end
		-- Every line within reach, 40 more a click.
		if last > 1 then
			lines[#lines + 1] = { text = Gold("> " .. L.TREASURY_OLDER:format(last - 1)), onClick = function()
				bookShown = bookShown + Treasury.BOOK_SHOWN
				ns.Fire("TREASURY_CHANGED")
			end }
		end
		return lines
	end
	local r = Treasury.Report()
	if not r or #r.book == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for _, e in ipairs(r and r.book or {}) do lines[#lines + 1] = BookRow(e, false) end
	return lines
end

-- The guild bank of <Olympus> as last seen (Bank.lua): its gold, then each tab's items in a
-- grid. The Treasurer and the King always; the army with the King's "book" switch.
local function BankLines(lines, role)
	if role == "member" and not Treasury.Shows("book") then return end
	local b = ns.Bank and ns.Bank.Current and ns.Bank.Current()
	lines[#lines + 1] = { header = true, text = L.TREASURY_BANK, tooltip = function(tt) tt:AddLine(L.TREASURY_BANK_TIP, 1, 1, 1, true) end }
	if not b then
		Para(lines, L.TREASURY_BANK_NONE)
		return
	end
	lines[#lines + 1] = { text = Grey(L.TREASURY_BANK_AS_OF:format(ns.DisplayName(b.by) or "?", ns.Ago(b.t))) }
	lines[#lines + 1] = { text = L.TREASURY_BANK_GOLD, right = Treasury.Coins(b.money or 0) }
	-- One tab open at a time, as the bank shows them: its slots, every one, items where they sit.
	local open = Treasury.bankTab
	if not (open and b.tabs[open]) then
		open = 1
		for i, tab in ipairs(b.tabs or {}) do if #tab.items > 0 then open = i break end end
	end
	for i, tab in ipairs(b.tabs or {}) do
		local count = #tab.items > 0 and L.TREASURY_BANK_ITEMS:format(#tab.items) or L.TREASURY_BANK_EMPTY
		lines[#lines + 1] = { text = (i == open and Gold or tostring)((i == open and "[-] " or "[+] ") .. (tab.name or "?")), right = Grey(count),
			key = "banktab" .. i, onClick = function() Treasury.bankTab = i; ns.Fire("TREASURY_CHANGED") end }
		if i == open then lines[#lines + 1] = { items = tab.items, slots = ns.Bank.SLOTS, columns = 7 } end
	end
	lines[#lines].gapAfter = true
end

local function SummaryLines(role)
	local lines = { { header = true, text = L.TREASURY_TITLE } }
	local balance, allIn, allOut, week, donors, rank, asOf
	if role == "treasurer" then
		Para(lines, Treasury.WhoSees(), tostring)
		lines[#lines].gapAfter = true
		Para(lines, L.TREASURY_HOW)
		lines[#lines].gapAfter = true
		local t = Treasury.Totals()
		balance, allIn, allOut, week, donors, rank = Treasury.Balance(), t.allIn, t.allOut, t.weekIn, #t.givers, t.ranking
	else
		local r = Treasury.Report()
		if not r then
			-- Nothing from the Treasurer yet: the King sees the sections waiting (the ranking
			-- empty), and the bank if anyone has seen it.
			Para(lines, L.TREASURY_WAIT:format(ns.TREASURER))
			lines[#lines].gapAfter = true
			if role == "king" then
				RankLines(lines, {})
				lines[#lines].gapAfter = true
			end
			BankLines(lines, role)
			return lines
		end
		balance, allIn, allOut, week, donors, rank, asOf = r.balance, r.allIn, r.allOut, r.week, r.donors, r.rank, r.t
	end
	if Treasury.MaySee("balance") then
		lines[#lines + 1] = { text = Gold(L.TREASURY_BALANCE), right = Treasury.Coins(balance) }
		lines[#lines + 1] = { text = L.TREASURY_IN_OUT, right = Green("+" .. Treasury.Coins(allIn)) .. "  " .. Red("-" .. Treasury.Coins(allOut)) }
		lines[#lines + 1] = { text = L.TREASURY_WEEK:format(donors), right = Green("+" .. Treasury.Coins(week)) }
		if role == "treasurer" then
			lines[#lines + 1] = { text = Grey(L.TREASURY_OPENING:format(Treasury.Coins(Treasury.Opening()))),
				onClick = function() ns.ShowDialog("OLYMPUS_TREASURY_OPENING") end,
				tooltip = function(tt) tt:AddLine(L.TREASURY_OPENING_TIP, 1, 1, 1, true) end }
		end
		if asOf then lines[#lines + 1] = { text = Grey(L.TREASURY_AS_OF:format(ns.TREASURER, ns.Ago(asOf))) } end
		lines[#lines].gapAfter = true
	end
	if Treasury.MaySee("ranking") then
		RankLines(lines, rank)
		lines[#lines].gapAfter = true
	end
	if Treasury.MaySee("book") then
		lines[#lines + 1] = { text = Gold("> " .. L.TREASURY_BOOK), onClick = function() Treasury.Show("book") end, gapAfter = true }
	end
	BankLines(lines, role)
	-- The King: what the army sees now (the switches are the buttons in the box).
	if role == "king" then
		local shown = ShownParts()
		lines[#lines + 1] = { text = Grey(#shown > 0 and L.TREASURY_ARMY_SEES:format(table.concat(shown, ", ")) or L.TREASURY_ARMY_SEES_NOTHING) }
	end
	return lines
end

function Treasury.Build()
	local role = Treasury.Role()
	if Treasury.mode == "book" and not Treasury.MaySee("book") then Treasury.mode = "summary" end
	local lines = Treasury.mode == "book" and BookLines(role) or SummaryLines(role)
	local detail = role == "treasurer" and L.TREASURY_DETAIL_TREASURER or role == "king" and L.TREASURY_DETAIL_KING or L.TREASURY_DETAIL_MEMBER
	return lines, L.TAB_TREASURY, detail
end

-- For Discord.
function Treasury.DiscordText()
	local out = { ("**%s**"):format(L.TREASURY_TITLE) }
	local balance, week, donors, rank
	if Treasury.IsTreasurer() then
		local t = Treasury.Totals()
		balance, week, donors, rank = Treasury.Balance(), t.weekIn, #t.givers, t.ranking
	else
		local r = Treasury.Report()
		if not r then return "" end
		balance, week, donors, rank = r.balance, r.week, r.donors, r.rank
	end
	if Treasury.MaySee("balance") then
		out[#out + 1] = L.TREASURY_BALANCE .. ": " .. Plain(balance)
		out[#out + 1] = L.TREASURY_WEEK:format(donors) .. ": +" .. Plain(week)
	end
	if Treasury.MaySee("ranking") then
		for i = 1, math.min(Treasury.RANK_SENT, #rank) do out[#out + 1] = ("%d. %s - %s"):format(i, rank[i].name, Plain(rank[i].money)) end
	end
	return table.concat(out, "\n")
end

-- The King's Throne Room: the treasury as the Treasurer last sent it, a click from its tab.
function Treasury.ThroneLines()
	local Line, INK, TITLE = ns.King.Line, ns.King.INK, ns.King.TITLE
	local lines = { Line(L.TREASURY_TITLE, TITLE) }
	local open = function() if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("treasury") end end
	local r = Treasury.Report()
	if r then
		lines[#lines + 1] = Line(L.TREASURY_BALANCE .. ": " .. Treasury.Coins(r.balance), INK)
		lines[#lines + 1] = Line(L.TREASURY_WEEK:format(r.donors) .. ": +" .. Treasury.Coins(r.week), INK)
		lines[#lines + 1] = Line(L.TREASURY_AS_OF:format(ns.TREASURER, ns.Ago(r.t)), INK)
	else
		ns.King.Para(lines, L.TREASURY_WAIT:format(ns.TREASURER), INK)
	end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = Line("> " .. L.TREASURY_OPEN, INK, { onClick = open })
	return lines
end

-- Next to the soldiers on top of the window (the Throne and the Treasury tabs): the treasury's
-- balance, for the Treasurer, the King, and the army when the King shows it.
function Treasury.HeaderText()
	local copper
	if Treasury.IsTreasurer() then copper = Treasury.Balance()
	elseif IsKingView() or Treasury.Shows("balance") then
		local r = Treasury.Report()
		copper = r and r.balance
	end
	if not copper then return nil end
	return "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t " .. Treasury.GoldText(copper)
end

-- Under the Treasurer in the Realm, for everyone, when the King shows the balance.
function Treasury.RealmText()
	if not Treasury.Shows("balance") then return nil end
	if CanSend() then return L.TREASURY_REALM:format(Treasury.GoldText(Treasury.Balance()), ns.Ago(ns.Now())) end
	local r = Treasury.Report()
	if not r then return nil end
	return L.TREASURY_REALM:format(Treasury.GoldText(r.balance), ns.Ago(r.t))
end

StaticPopupDialogs["OLYMPUS_TREASURY_OPENING"] = {
	text = L.TREASURY_OPENING_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 200,
	maxLetters = 24,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("treasury opening", Treasury.SetOpening, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("treasury opening", Treasury.SetOpening, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Tests start from a clean state.
function Treasury.Reset()
	trade, mailOut, report, lastShare, sharePending, lastFlagsSent = nil, nil, nil, -math.huge, false, -math.huge
	asked = false
	wipe(pending)
	lastMoney = nil
	bookShown = Treasury.BOOK_SHOWN
	Treasury.mode = "summary"
	if ns.rdb then ns.rdb.treasuryReport = nil end
end
