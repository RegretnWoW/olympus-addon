local ADDON, ns = ...
local L = ns.L

-- The guild bank of <Olympus>, as its Treasury tab shows it: whoever of that guild opens the
-- bank with the addon on (the Treasurer, the King, an officer who may see it) takes a
-- snapshot of what it holds, tab by tab (item and count, the bank's gold), kept in the saved
-- variables with when it was taken. The Treasurer's client sends its snapshot on the channel
-- (T9, in pieces), so the King and the army see the bank as he last saw it; anyone else's
-- snapshot stays on their own screen. Nothing is ever moved or touched in the bank.
--   T9~<guild>~<time>~<copper>~<tab name>;<id>x<count>,.<empty slots>,<id>x<count>...~<tab name>;...
-- (items in slot order; ".3" is three empty slots before the next one: the tab is drawn as
-- the bank shows it, slot by slot)
-- Clients without a guild bank (Classic Era) have none of the API: this file then only shows
-- what the Treasurer sends.

local Bank = {}
ns.Bank = Bank

Bank.SLOTS = 98            -- a guild bank tab (MAX_GUILDBANK_SLOTS_PER_TAB)
Bank.MAX_TABS = 8
Bank.MAX_ITEMS = 700       -- items sent or read, at most (6 full tabs are 588)
Bank.SHARE_GAP = 120       -- the Treasurer's client sends a changed bank this often at most
Bank.SHARE_REPEAT = 1800   -- and repeats it for late logins
Bank.REPORT_KEPT = 14 * 86400
Bank.SETTLE = 1.5          -- seconds after the last slot change before the bank is read
Bank.SETTLE_MAX = 6        -- ...but a bank that keeps changing is read this long after the first

local open = false
local queried = {}
local lastShare, lastSent = -math.huge, nil
local readPending = false
local firstChange, lastChange = 0, 0 -- the slot changes waiting to be read (GetTime)
local sharePending = false

-- (A tab's name ends at the first ";": only the message's separators and escapes go.)
local function Clean(s, n) return ns.Cut((tostring(s or ""):gsub("[~;|%c]", " ")), n) end
local function HasBank() return type(GetNumGuildBankTabs) == "function" and type(GetGuildBankItemInfo) == "function" end

-- Our own snapshot (this character's guild's bank), and the Treasurer's as it reached us.
function Bank.Own() return ns.rdb and ns.rdb.bank or nil end
function Bank.Report()
	local r = ns.rdb and ns.rdb.bankReport
	if type(r) ~= "table" then return nil end
	if ns.Now() - (tonumber(r.t) or 0) > Bank.REPORT_KEPT then
		ns.rdb.bankReport = nil
		return nil
	end
	return r
end
-- What the Treasury tab shows: the newest of the two, when ours is the King's guild's bank.
function Bank.Current()
	local own, report = Bank.Own(), Bank.Report()
	if own and not (own.guild and ns.IsKingGuild(own.guild)) then own = nil end
	if own and report then return (own.t or 0) >= (report.t or 0) and own or report end
	return own or report
end

-- The bank as the client holds it now, every tab we may see (once the server sent them).
function Bank.Read()
	if not HasBank() then return nil end
	local n = tonumber(GetNumGuildBankTabs()) or 0
	if n == 0 then return nil end
	local snap = { t = ns.Now(), guild = GetGuildInfo("player"), by = ns.me, money = GetGuildBankMoney and (tonumber(GetGuildBankMoney()) or 0) or 0, tabs = {} }
	local total = 0
	for tab = 1, math.min(n, Bank.MAX_TABS) do
		local name, icon, viewable = GetGuildBankTabInfo(tab)
		if viewable and queried[tab] then
			local items = {}
			for slot = 1, Bank.SLOTS do
				local texture, count = GetGuildBankItemInfo(tab, slot)
				count = tonumber(count) or 0
				if texture and count > 0 and total < Bank.MAX_ITEMS then
					local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
					local id = link and tonumber(link:match("item:(%d+)"))
					if id then
						items[#items + 1] = { id = id, n = count, icon = texture, link = link, s = slot }
						total = total + 1
					end
				end
			end
			snap.tabs[#snap.tabs + 1] = { name = Clean(name ~= "" and name or tostring(tab), 30), icon = icon, items = items, i = tab }
		end
	end
	if #snap.tabs == 0 then return nil end
	return snap, total
end

-- Only the real Treasurer's client sends (never the author's view).
local function CanSend() return ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) end

-- What one message may carry (the channel's pieces), a little short of it.
local function Room() return (ns.Codec.CHUNK or 220) * (ns.Codec.MAX_CHUNKS or 30) - 40 end

function Bank.Message(snap)
	snap = snap or Bank.Own()
	if not snap then return nil end
	local parts = { "T9", Clean(snap.guild, 40), tostring(math.floor(snap.t or ns.Now())), tostring(math.floor(snap.money or 0)) }
	local room, total = Room(), 0
	for _, tab in ipairs(snap.tabs) do
		local items, pos = {}, 1
		for k, it in ipairs(tab.items) do
			if total >= Bank.MAX_ITEMS then break end
			local slot = tonumber(it.s) or pos
			if slot > pos then items[#items + 1] = "." .. (slot - pos) end
			items[#items + 1] = ("%dx%d"):format(it.id, math.min(it.n, 99999))
			pos = slot + 1
			total = total + 1
		end
		parts[#parts + 1] = Clean(tab.name, 30) .. ";" .. table.concat(items, ",")
	end
	local msg = table.concat(parts, "~")
	-- Past what the channel carries in one go: the last tabs are left out (it is rare: six
	-- full tabs fit).
	while #msg > room and #parts > 5 do
		parts[#parts] = nil
		msg = table.concat(parts, "~")
	end
	return msg
end

function Bank.Share(force)
	if not CanSend() then return false end
	local snap = Bank.Own()
	if not snap or not (snap.guild and ns.IsKingGuild(snap.guild)) then return false end
	local now = ns.Now()
	local msg = Bank.Message(snap)
	if not msg then return false end
	if not force and msg == lastSent and now - lastShare < Bank.SHARE_REPEAT then return false end
	if not force and now - lastShare < Bank.SHARE_GAP then
		-- Changed within the gap: sent once it is over (the snapshot as it is then).
		if not sharePending then
			sharePending = true
			ns.After(Bank.SHARE_GAP - (now - lastShare) + 1, "bank share", function()
				sharePending = false
				Bank.Share()
			end)
		end
		return false
	end
	lastShare, lastSent = now, msg
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "bank") else ns.Comm.SendChunked(msg) end
	return true
end

-- The Treasurer's snapshot (from him alone, by his name, speaking for the King's guild: no
-- census vote, which forged ones could turn against him).
function Bank.HandleReport(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guild, when, money, rest = text:match("^T9~([^~]*)~(%d+)~(%d+)~(.*)$")
	if not guild or not ns.IsKingGuild(guild) then return end
	if not ns.IsTreasurer(sender, guild) then return end
	local now = ns.Now()
	local r = { t = math.min(tonumber(when) or now, now), guild = guild, by = ns.FullName(sender), money = math.min(tonumber(money) or 0, 2147483647), tabs = {} }
	local total = 0
	for part in (rest .. "~"):gmatch("([^~]*)~") do
		local name, items = part:match("^([^;]*);(.*)$")
		if name and #r.tabs < Bank.MAX_TABS then
			local tab, pos = { name = ns.Cut(name, 30), items = {} }, 1
			for entry in items:gmatch("[^,]+") do
				local gap = entry:match("^%.(%d+)$")
				local id, n = entry:match("^(%d+)x(%d+)$")
				if gap then
					pos = pos + tonumber(gap)
				elseif id and total < Bank.MAX_ITEMS and pos <= Bank.SLOTS then
					tab.items[#tab.items + 1] = { id = tonumber(id), n = tonumber(n), s = pos }
					pos = pos + 1
					total = total + 1
				end
			end
			r.tabs[#r.tabs + 1] = tab
		end
	end
	if #r.tabs == 0 then return end
	ns.rdb.bankReport = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end
ns.Comm.Handle("T9", function(...) Bank.HandleReport(...) end)

-- A tab asked for whose slots never arrived reads empty, just like a tab that is: an empty
-- read never replaces the items the last snapshot of that tab held (same guild, same tab),
-- unless the tab is the one on screen (the game loaded it, the player sees it empty), or that
-- tab was already kept once (empty twice in a row: it is). The kept tab is marked `kept`.
-- Each opening of the bank is a visit (0.9.2): a tab kept in this visit is kept again in it,
-- however many reads it takes; only a later visit that reads it empty again empties it (a tab
-- kept by 0.9.1, `kept == true`, counts as kept in an earlier visit).
local visit = 0
function Bank.Keep(snap, prev)
	if not snap or type(prev) ~= "table" or prev.guild ~= snap.guild or type(prev.tabs) ~= "table" then return snap end
	local shown = type(GetCurrentGuildBankTab) == "function" and tonumber((GetCurrentGuildBankTab())) or nil
	for k, tab in ipairs(snap.tabs) do
		if #tab.items == 0 and tab.i ~= shown then
			for _, old in ipairs(prev.tabs) do
				local same = (old.i and old.i == tab.i) or (not old.i and old.name == tab.name)
				if same and type(old.items) == "table" and #old.items > 0 and (not old.kept or old.kept == visit) then
					snap.tabs[k] = { name = tab.name, icon = tab.icon, i = tab.i, items = old.items, kept = visit }
					break
				end
			end
		end
	end
	return snap
end

local function ReadNow()
	if not open and not HasBank() then return end
	local snap = Bank.Keep(Bank.Read(), ns.rdb.bank)
	if not snap then return end
	ns.rdb.bank = snap
	ns.Fire("TREASURY_CHANGED")
	Bank.Share()
end

-- The bank open: every tab we may see is asked for (the game loads the one shown alone), and
-- once the slots settle (SETTLE after the last change, SETTLE_MAX after the first at most) the
-- snapshot is taken (and sent, the Treasurer's).
local function Settle()
	lastChange = GetTime()
	if readPending then return end
	readPending, firstChange = true, lastChange
	local function Check()
		local wait = math.min(lastChange + Bank.SETTLE, firstChange + Bank.SETTLE_MAX) - GetTime()
		if wait > 0.05 then return ns.After(wait, "bank read", Check) end
		readPending = false
		ReadNow()
	end
	ns.After(Bank.SETTLE, "bank read", Check)
end

function Bank.Opened()
	if not HasBank() or not ns.IsMember() then return end
	open = true
	visit = math.max(ns.Now(), visit + 1) -- (a number no earlier visit has: kept tabs carry theirs)
	wipe(queried)
	local n = tonumber(GetNumGuildBankTabs()) or 0
	for tab = 1, math.min(n, Bank.MAX_TABS) do
		local _, _, viewable = GetGuildBankTabInfo(tab)
		if viewable then
			queried[tab] = true
			if QueryGuildBankTab then pcall(QueryGuildBankTab, tab) end
		end
	end
	Settle()
end
function Bank.Changed() if open then Settle() end end
function Bank.Closed()
	if not open then return end
	Settle()
	open = false
end

ns.On("LOGIN", function()
	if not HasBank() then return end
	local events = {
		GUILDBANKFRAME_OPENED = Bank.Opened,
		GUILDBANKBAGSLOTS_CHANGED = Bank.Changed,
		GUILDBANK_UPDATE_TABS = Bank.Changed,
		GUILDBANK_UPDATE_MONEY = Bank.Changed,
		GUILDBANKFRAME_CLOSED = Bank.Closed,
	}
	for event, fn in pairs(events) do
		pcall(ns.RegisterEvent, event, function() ns.SafeCall("bank " .. event, fn) end)
	end
	-- Repeated for late logins (the Treasurer's), while the bank is not open.
	ns.Every(300, "bank share", function() if not open then Bank.Share() end end)
end)

-- Tests start from a clean state.
function Bank.Reset()
	open, readPending, lastShare, lastSent = false, false, -math.huge, nil
	firstChange, lastChange, sharePending = 0, 0, false
	wipe(queried)
	if ns.rdb then ns.rdb.bank, ns.rdb.bankReport = nil, nil end
end
function Bank.SetOpenForTest(on, tabs) open = on; wipe(queried); for _, t in ipairs(tabs or {}) do queried[t] = true end end
