local ADDON, ns = ...
local L = ns.L

-- The guild bank of <Olympus>, as its Treasury tab shows it: whoever of that guild opens the
-- bank with the addon on (the Treasurer, the King, an officer who may see it) takes a
-- snapshot of what it holds, tab by tab (item and count, the bank's gold), kept in the saved
-- variables with when it was taken. A keeper of the treasury's client (the Treasurer, the
-- King, a character the King named: Treasury.lua) sends its snapshot on the channel (T9, in
-- pieces), once he said yes to sharing, so the King and the army see the bank as a keeper
-- last saw it (the newest); anyone else's snapshot stays on their own screen. Nothing is ever
-- moved or touched in the bank.
--   T9~<guild>~<time>~<copper>~<tab name>;<id>x<count>,.<empty slots>,<id>x<count>...~<tab name>;...
-- (items in slot order; ".3" is three empty slots before the next one: the tab is drawn as
-- the bank shows it, slot by slot)
-- The bank's window opens on GUILDBANKFRAME_OPENED on older clients, and through the game's
-- interaction manager on the newer ones (WoW: Forever: PLAYER_INTERACTION_MANAGER_FRAME_SHOW
-- with the guild banker's type, 1.0): both are heard. Clients without a guild bank (Classic
-- Era) have none of the API: this file then only shows what a keeper sends, and the tab says
-- this client has no guild bank.

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
Bank.HasAPI = HasBank

-- Our own snapshot (this character's guild's bank), and a keeper's as it reached us (while he
-- is one: a character the King took off the treasury no longer shows the bank).
function Bank.Own() return ns.rdb and ns.rdb.bank or nil end
function Bank.Report()
	local r = ns.rdb and ns.rdb.bankReport
	if type(r) ~= "table" then return nil end
	if ns.Now() - (tonumber(r.t) or 0) > Bank.REPORT_KEPT then
		ns.rdb.bankReport = nil
		return nil
	end
	if ns.Treasury and ns.Treasury.IsKeeperName and not ns.Treasury.IsKeeperName(r.by, r.guild) then return nil end
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

-- Only a real keeper's client sends (never the author's view), with his yes (0.9.3).
local function CanSend() return ns.Treasury and ns.Treasury.CanSend and ns.Treasury.CanSend() end

-- What one message may carry (the channel's pieces), a little short of it.
local function Room() return (ns.Codec.CHUNK or 220) * (ns.Codec.MAX_CHUNKS or 30) - 40 end

-- kind: "T9" (a keeper's snapshot of the King's guild's bank) unless said; "TS" (1.1: a sister
-- guild's, for the Guild treasuries' audience alone) leaves the tabs' names out: 1.2 writes each
-- tab's number in the bank there instead (1.1 wrote nothing, and reads nothing there).
function Bank.Message(snap, kind)
	snap = snap or Bank.Own()
	if not snap then return nil end
	kind = kind or "T9"
	local parts = { kind, Clean(snap.guild, 40), tostring(math.floor(snap.t or ns.Now())), tostring(math.floor(snap.money or 0)) }
	local room, total = Room(), 0
	for _, tab in ipairs(snap.tabs) do
		-- (1.1: a tab read empty with nothing earlier to keep it from, Bank.Keep's `unread`, is
		-- not known to be empty: left out, so no client lists its last items as gone.)
		if not tab.unread then
			local items, pos = {}, 1
			for k, it in ipairs(tab.items) do
				if total >= Bank.MAX_ITEMS then break end
				local slot = tonumber(it.s) or pos
				if slot > pos then items[#items + 1] = "." .. (slot - pos) end
				items[#items + 1] = ("%dx%d"):format(it.id, math.min(it.n, 99999))
				pos = slot + 1
				total = total + 1
			end
			local label = Clean(tab.name, 30)
			if kind == "TS" or kind == "UG" then label = tonumber(tab.i) and tostring(math.floor(tonumber(tab.i))) or "" end
			parts[#parts + 1] = label .. ";" .. table.concat(items, ",")
		end
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

-- Our own snapshot of the King's guild's bank as a keeper's client whispers it (1.1), or nil.
function Bank.PrivateMessage()
	if not CanSend() then return nil end
	local snap = Bank.Own()
	if not snap or not (snap.guild and ns.IsKingGuild(snap.guild)) then return nil end
	return Bank.Message(snap)
end

-- 1.1: on the channel only while the King shows the army the book (the bank goes with it); by
-- whisper otherwise, to the King, his Stewards and the keepers heard online (Treasury.Private:
-- each gets a snapshot once, the next one when it changed).
function Bank.Share(force)
	if not CanSend() then return false end
	local snap = Bank.Own()
	if not snap or not (snap.guild and ns.IsKingGuild(snap.guild)) then return false end
	local now = ns.Now()
	local msg = Bank.Message(snap)
	if not msg then return false end
	if not ns.Treasury.PublicShows("book") then
		local n = 0
		for _, name in ipairs(ns.Treasury.Online()) do
			if ns.Treasury.Private(name, "T9", msg) then n = n + 1 end
		end
		return n > 0
	end
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
	ns.Treasury.SendPublic(msg, "bank", function() return ns.Treasury.PublicShows("book") end)
	return true
end

-- A keeper's snapshot (from a keeper alone, by his name, speaking for the King's guild: no
-- census vote, which forged ones could turn against him). The newest one is kept: a keeper
-- repeating an older snapshot doesn't replace a newer one of another's.
-- A snapshot's tabs as a message writes them ("<name>;<id>x<n>,.<gap>,...~..."): each item where it
-- sits, MAX_TABS and MAX_ITEMS at most. noNames: "Tab n" for each (a sister guild's: TS), n its
-- number in the bank where the message gives it (1.2: i), else its place in the message (1.1).
-- Returns the tabs, and (noNames) whether every tab came with its own number, none twice.
local function ReadTabs(rest, noNames)
	local tabs, total, seen, numbered = {}, 0, {}, noNames == true
	for part in (rest .. "~"):gmatch("([^~]*)~") do
		local name, items = part:match("^([^;]*);(.*)$")
		if name and #tabs < Bank.MAX_TABS then
			local tab, pos
			if noNames then
				local i = tonumber(name:match("^(%d+)$"))
				if not i or i < 1 or i > Bank.MAX_TABS or seen[i] then i, numbered = nil, false end
				if i then seen[i] = true end
				tab, pos = { name = ns.L.BANK_SISTER_TAB:format(i or (#tabs + 1)), i = i, items = {} }, 1
			else
				tab, pos = { name = ns.Cut(name, 30), items = {} }, 1
			end
			for entry in items:gmatch("[^,]+") do
				local gap = entry:match("^%.(%d+)$")
				local id, n = entry:match("^(%d+)x(%d+)$")
				if gap then
					pos = pos + tonumber(gap)
				elseif id and total < Bank.MAX_ITEMS and pos <= Bank.SLOTS then
					tab.items[#tab.items + 1] = { id = tonumber(id), n = math.min(tonumber(n), 99999), s = pos }
					pos = pos + 1
					total = total + 1
				end
			end
			tabs[#tabs + 1] = tab
		end
	end
	return tabs, numbered and #tabs > 0
end

function Bank.HandleReport(dist, sender, text)
	-- (1.1: by whisper too, put together by Treasury.HandlePrivate, to the King, a Steward or a keeper.)
	if dist ~= "CHANNEL" and not (dist == "WHISPER" and ns.Treasury.IsInsider()) then return end
	local guild, when, money, rest = text:match("^T9~([^~]*)~(%d+)~(%d+)~(.*)$")
	if not guild or not ns.IsKingGuild(guild) then return end
	if not (ns.Treasury and ns.Treasury.IsKeeperName and ns.Treasury.IsKeeperName(sender, guild)) then return end
	local now = ns.Now()
	local r = { t = math.min(tonumber(when) or now, now), guild = guild, by = ns.FullName(sender), money = math.min(tonumber(money) or 0, 2147483647), tabs = ReadTabs(rest) }
	if #r.tabs == 0 then return end
	local kept = ns.rdb.bankReport
	if type(kept) == "table" and (tonumber(kept.t) or 0) > r.t and not (ns.Treasury.SameChar and ns.Treasury.SameChar(kept.by, r.by)) then return end
	-- (1.1: the snapshot it replaces, of another visit, is what "gone since" compares with: only the
	-- same keeper's, Konig's review of 1.1. Another's stays where it was, for that keeper's next.)
	if type(kept) == "table" and tonumber(kept.t) ~= r.t and kept.guild == r.guild and ns.Treasury.SameChar(kept.by, r.by) then
		ns.rdb.bankReportPrev = kept
	end
	ns.rdb.bankReport = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end
ns.Comm.Handle("T9", function(...) Bank.HandleReport(...) end)
ns.Treasury.OnPrivate("T9", { from = function(s) return ns.Treasury.KeeperByName(s) end, to = function() return ns.Treasury.IsInsider() end,
	send = function(to) return CanSend() and ns.Treasury.InsiderName(to) end,
	handle = function(...) Bank.HandleReport(...) end })

-- A tab asked for whose slots never arrived reads empty, just like a tab that is: an empty
-- read never replaces the items the last snapshot of that tab held (same guild, same tab),
-- unless the tab is the one on screen (the game loaded it, the player sees it empty), or that
-- tab was already kept once (empty twice in a row: it is). The kept tab is marked `kept`.
-- Each opening of the bank is a visit (0.9.2): a tab kept in this visit is kept again in it,
-- however many reads it takes; only a later visit that reads it empty again empties it (a tab
-- kept by 0.9.1, `kept == true`, counts as kept in an earlier visit).
-- 1.1: an empty read of a tab not on screen with nothing earlier to keep it from (no snapshot of
-- that tab before: after a wipe of the saved variables, a newly named keeper's first visit) is
-- not known to be empty either: marked `unread` (this visit), it is drawn empty on this screen
-- as before but left out of what is sent (Bank.Message) and of "gone since" (Bank.Gone). Read
-- empty again in a later visit, it is empty.
local visit = 0
function Bank.Keep(snap, prev)
	if not snap then return snap end
	if type(prev) ~= "table" or prev.guild ~= snap.guild or type(prev.tabs) ~= "table" then prev = nil end
	local shown = type(GetCurrentGuildBankTab) == "function" and tonumber((GetCurrentGuildBankTab())) or nil
	for k, tab in ipairs(snap.tabs) do
		if #tab.items == 0 and tab.i ~= shown then
			local old
			for _, o in ipairs(prev and prev.tabs or {}) do
				if (o.i and o.i == tab.i) or (not o.i and o.name == tab.name) then old = o break end
			end
			if old and type(old.items) == "table" and #old.items > 0 and (not old.kept or old.kept == visit) then
				snap.tabs[k] = { name = tab.name, icon = tab.icon, i = tab.i, items = old.items, kept = visit }
			elseif not old or old.unread == visit then
				tab.unread = visit
			end
		end
	end
	return snap
end

local function ReadNow()
	if not open and not HasBank() then return end
	local old = ns.rdb.bank
	local snap = Bank.Keep(Bank.Read(), old)
	if not snap then return end
	-- (1.1: the last snapshot of an earlier visit is what "gone since" compares with.)
	snap.visit = visit
	if type(old) == "table" and old.visit ~= visit and old.guild == snap.guild then ns.rdb.bankPrev = old end
	ns.rdb.bank = snap
	ns.Fire("TREASURY_CHANGED")
	Bank.Share()
	Bank.ShareSister()
	Bank.ShareOwnGuild()
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
	-- (1.1: a sister guild's treasurer is asked once a session whether the King sees his bank.)
	Bank.AskSister()
end
function Bank.Changed() if open then Settle() end end
function Bank.Closed()
	if not open then return end
	Settle()
	open = false
end

-- The newer clients' interaction manager (WoW: Forever): the guild banker's window opens and
-- closes with the others; only its type is ours. A client that also says GUILDBANKFRAME_OPENED
-- opens one visit, not two (whichever came first).
local function GuildBanker(kind)
	local want = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
	return tonumber(kind) == want
end
local openedAt = -math.huge
local function OpenedOnce()
	local now = GetTime and GetTime() or 0
	if open and now - openedAt < 1 then return end
	openedAt = now
	Bank.Opened()
end
function Bank.InteractionShow(kind) if GuildBanker(kind) then OpenedOnce() end end
function Bank.InteractionHide(kind) if GuildBanker(kind) then Bank.Closed() end end

ns.On("LOGIN", function()
	if not HasBank() then return end
	local events = {
		GUILDBANKFRAME_OPENED = OpenedOnce,
		GUILDBANKBAGSLOTS_CHANGED = Bank.Changed,
		GUILDBANK_UPDATE_TABS = Bank.Changed,
		GUILDBANK_UPDATE_MONEY = Bank.Changed,
		GUILDBANKFRAME_CLOSED = Bank.Closed,
		PLAYER_INTERACTION_MANAGER_FRAME_SHOW = Bank.InteractionShow,
		PLAYER_INTERACTION_MANAGER_FRAME_HIDE = Bank.InteractionHide,
		-- 1.2: an item the Treasury's search asked the game for has arrived (Bank.ItemInfoReceived).
		GET_ITEM_INFO_RECEIVED = function(id) Bank.ItemInfoReceived(id) end,
	}
	for event, fn in pairs(events) do
		pcall(ns.RegisterEvent, event, function(...) ns.SafeCall("bank " .. event, fn, ...) end)
	end
	-- Repeated for late logins (a keeper's), while the bank is not open. (1.2: and the sister guilds'
	-- banks held here dropped once this character is no longer of their audience.)
	ns.Every(300, "bank share", function()
		if not open then Bank.Share() end
		if ns.Bank.Holding then ns.Bank.Holding() end
	end)
end)

---------------------------------------------------------------------------
-- 1.1: the bank's search, what left it since the last visit, and the sister guilds' banks
-- (asked by Fern, a moderator on Asmon's team: finding one item in eight tabs is slow, and a
-- missing stack is either a withdrawal nobody noted or theft). Counts only: the game's bank log
-- (who took what) is never read, and nothing in any bank is ever moved.
---------------------------------------------------------------------------

-- The snapshot before `cur` (the same guild's, older: of an earlier visit), which "gone since"
-- compares with; nil when none. Konig's review of 1.1: of the same source alone, this client's own
-- snapshots with each other, a keeper's with his own earlier one. Another keeper's snapshot (a
-- modified client's, or one of fewer tabs) never marks anything gone: a snapshot is its sender's
-- word, and "gone" reads as a theft.
function Bank.Previous(cur)
	if type(cur) ~= "table" then return nil end
	-- 1.2: a sister guild's (in memory): the one it replaced, of the same sender and older, both
	-- with their tabs' numbers (a 1.1 message's "Tab 2" is only its place: a tab left out unread
	-- would shift the others, and their stacks would read as gone).
	if cur.sister then
		local p = cur.prev
		if type(p) == "table" and cur.numbered and p.numbered and type(p.tabs) == "table" and (tonumber(p.t) or 0) < (tonumber(cur.t) or 0)
			and ns.Treasury.SameChar(p.by, cur.by) then
			return p
		end
		return nil
	end
	if not ns.rdb then return nil end
	local own = cur == ns.rdb.bank or cur == ns.rdb.bankPrev
	local best
	for _, key in ipairs(own and { "bankPrev", "bank" } or { "bankReportPrev", "bankReport" }) do
		local s = ns.rdb[key]
		if type(s) == "table" and s ~= cur and s.guild == cur.guild and type(s.tabs) == "table" and (tonumber(s.t) or 0) < (tonumber(cur.t) or 0)
			and (own or ns.Treasury.SameChar(s.by, cur.by))
			and (not best or (tonumber(s.t) or 0) > (tonumber(best.t) or 0)) then
			best = s
		end
	end
	return best
end

-- The stacks gone since `prev`: each item's count summed over the tabs both snapshots hold
-- (matched by the tab's number, by its name when one has none; a tab not seen is no theft). A
-- tab of `cur` kept from an earlier read, or not read (Bank.Keep: `kept`, `unread`), is left out
-- (its items were not seen now); a tab of `prev` kept from an earlier read counts, as that read
-- saw it (so a tab emptied between two visits shows once it reads empty again, a visit later
-- when it was not on screen). A stack moved to another tab both hold is not gone. { { id, n, tabs = { name, ... } }, ... }, the most first;
-- and ghosts[tab index in cur] = { { id, n, s, gone = true } }: the slots of `cur` those stacks
-- sat in, empty now (the grid shows them faded).
function Bank.Gone(cur, prev)
	local out, ghosts = {}, {}
	if type(cur) ~= "table" or type(prev) ~= "table" or type(cur.tabs) ~= "table" or type(prev.tabs) ~= "table" then return out, ghosts end
	local before, now, where = {}, {}, {}
	for ci, tab in ipairs(cur.tabs) do
		local old
		for _, o in ipairs(prev.tabs) do
			if (tab.i and o.i and o.i == tab.i) or ((not tab.i or not o.i) and o.name == tab.name) then old = o break end
		end
		if old and not tab.kept and not tab.unread and not old.unread and type(old.items) == "table" and type(tab.items) == "table" then
			local here = {}
			for _, it in ipairs(tab.items) do
				now[it.id] = (now[it.id] or 0) + (tonumber(it.n) or 0)
				if it.s then here[it.s] = true end
			end
			for _, it in ipairs(old.items) do
				before[it.id] = (before[it.id] or 0) + (tonumber(it.n) or 0)
				where[it.id] = where[it.id] or {}
				table.insert(where[it.id], { tab = ci, name = tab.name, s = it.s, n = tonumber(it.n) or 0, empty = it.s ~= nil and not here[it.s] })
			end
		end
	end
	for id, n in pairs(before) do
		local gone = n - (now[id] or 0)
		if gone > 0 then
			local tabs, seen, left = {}, {}, gone
			for _, w in ipairs(where[id]) do
				if not seen[w.name] then seen[w.name] = true tabs[#tabs + 1] = w.name end
				if w.empty and left > 0 then
					ghosts[w.tab] = ghosts[w.tab] or {}
					table.insert(ghosts[w.tab], { id = id, n = math.min(w.n, left), s = w.s, gone = true })
					left = left - math.min(w.n, left)
				end
			end
			out[#out + 1] = { id = id, n = gone, tabs = tabs }
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.id < b.id
	end)
	return out, ghosts
end

-- The stacks of a snapshot whose item (its name as this client knows it, or its number) holds
-- the search `q` (folded: Views.Query): { { id, n, tabs = { name, ... }, stacks }, ... }, the most
-- first. An item this client never saw finds by its number until the game names it.
function Bank.Find(snap, q)
	local out, byId = {}, {}
	if type(snap) ~= "table" or type(snap.tabs) ~= "table" or not q or q == "" then return out end
	local Name = ns.Treasury and ns.Treasury.ItemName or tostring
	for _, tab in ipairs(snap.tabs) do
		for _, it in ipairs(type(tab.items) == "table" and tab.items or {}) do
			if ns.Holds(q, Name(it.id), tostring(it.id)) then
				local x = byId[it.id]
				if not x then
					x = { id = it.id, n = 0, tabs = {}, stacks = 0, seen = {} }
					byId[it.id] = x
					out[#out + 1] = x
				end
				x.n, x.stacks = x.n + (tonumber(it.n) or 0), x.stacks + 1
				if not x.seen[tab.name] then x.seen[tab.name] = true x.tabs[#x.tabs + 1] = tab.name end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.id < b.id
	end)
	return out
end

---------------------------------------------------------------------------
-- 1.2: the Treasury's one search over every bank this client shows (<Olympus>'s and each sister
-- guild's: the Guild treasuries, Treasury.lua). Each snapshot is indexed once (a snapshot is never
-- changed once kept: a read of the bank, a message heard, is a new table), and the banks shown are
-- put together again only when one of them changes. A keystroke reads that: each item once (its
-- name folded once, when the client knows it), never a bank's slots. A hundred guilds of six full
-- tabs are some 60,000 slots; a keystroke reads their distinct items alone. Bank.indexBuilds and
-- Bank.unionBuilds count the builds (tests).
---------------------------------------------------------------------------
Bank.indexBuilds, Bank.unionBuilds = 0, 0
Bank.NAME_RETRY = 2   -- seconds before an item the client could not name yet is asked of it again
Bank.NAME_ASKS = 100  -- items the client holds no data of, asked of the game at most, a search
local EMPTY_INDEX = { ids = {}, order = {}, units = 0, stacks = 0 }
local indexed = setmetatable({}, { __mode = "k" }) -- [snapshot] = its index (gone with the snapshot)
local union = { idx = {}, ids = {}, list = {}, total = {} }
local foldedNames, nameMiss, nameAsked = {}, {}, {}
local asksLeft = 0 -- what this search may still ask of the game (Bank.Search sets it)
local namesSoon = false -- a redraw is coming for names that arrived (Bank.ItemInfoReceived)
Bank.NAMES_REDRAW = 0.5 -- seconds: items arriving together, one redraw

-- A snapshot's index: each item once, { id, n, stacks, tabs = { [tab] = n }, at = { tab, ... } },
-- in the order the bank holds them, and its units and stacks in all. Built once a snapshot (its
-- shape, its tabs and how many stacks each holds, is checked: a snapshot changed in place is
-- indexed again).
function Bank.Index(snap)
	if type(snap) ~= "table" or type(snap.tabs) ~= "table" then return nil end
	local shape = #snap.tabs
	for _, tab in ipairs(snap.tabs) do shape = shape * 1009 + #(type(tab.items) == "table" and tab.items or {}) end
	local x = indexed[snap]
	if x and x.shape == shape then return x end
	Bank.indexBuilds = Bank.indexBuilds + 1
	x = { shape = shape, ids = {}, order = {}, units = 0, stacks = 0 }
	for ti, tab in ipairs(snap.tabs) do
		for _, it in ipairs(type(tab.items) == "table" and tab.items or {}) do
			local id, n = tonumber(it.id), math.floor(tonumber(it.n) or 0)
			if id and n > 0 then
				local e = x.ids[id]
				if not e then
					e = { id = id, n = 0, stacks = 0, tabs = {}, at = {} }
					x.ids[id] = e
					x.order[#x.order + 1] = id
				end
				if not e.tabs[ti] then e.tabs[ti], e.at[#e.at + 1] = 0, ti end
				e.tabs[ti] = e.tabs[ti] + n
				e.n, e.stacks = e.n + n, e.stacks + 1
				x.units, x.stacks = x.units + n, x.stacks + 1
			end
		end
	end
	indexed[snap] = x
	return x
end

-- The banks shown (`banks`: { { snap = ... }, ... }, in the caller's order) put together: each
-- item once, the banks holding it (their places in `banks`), how many in all. The same banks (the
-- same indexes, in the same order) give the same one back.
local function Union(banks)
	local idx = {}
	for k, b in ipairs(banks) do idx[k] = Bank.Index(b.snap) or EMPTY_INDEX end
	local same = #idx == #union.idx
	for k = 1, same and #idx or 0 do
		if idx[k] ~= union.idx[k] then same = false break end
	end
	if same then return union end
	Bank.unionBuilds = Bank.unionBuilds + 1
	local u = { idx = idx, ids = {}, list = {}, total = {} }
	for k, x in ipairs(idx) do
		for _, id in ipairs(x.order) do
			local posts = u.ids[id]
			if not posts then
				posts = {}
				u.ids[id], u.list[#u.list + 1], u.total[id] = posts, id, 0
			end
			posts[#posts + 1] = k
			u.total[id] = u.total[id] + x.ids[id].n
		end
	end
	union = u
	return u
end

-- An item's name as the search reads it (folded: ns.Fold), once the client knows it; until then
-- nil, the game asked to load it once a session, and asked again for its name NAME_RETRY later.
-- Where the client says which items it holds data of, one it holds none of is not read (a read
-- asks the server), and at most NAME_ASKS of them are asked for in one search: a hundred guilds'
-- banks never send the game thousands of item queries at a keystroke (the others at the next ones).
local function FoldedName(id)
	local f = foldedNames[id]
	if f then return f end
	local now = GetTime and GetTime() or 0
	if nameMiss[id] and now - nameMiss[id] < Bank.NAME_RETRY then return nil end
	if type(C_Item) == "table" and type(C_Item.IsItemDataCachedByID) == "function" then
		local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
		if ok and cached == false and type(C_Item.RequestLoadItemDataByID) == "function" then
			if not nameAsked[id] then
				if asksLeft <= 0 then return nil end
				asksLeft = asksLeft - 1
				nameAsked[id] = true
				pcall(C_Item.RequestLoadItemDataByID, id)
			end
			nameMiss[id] = now
			return nil
		end
	end
	local name = ns.Treasury and ns.Treasury.ItemName and ns.Treasury.ItemName(id)
	if type(name) == "string" and name ~= "" and name ~= "#" .. tostring(id) then
		f = ns.Fold(name)
		foldedNames[id], nameMiss[id] = f, nil
		return f
	end
	nameMiss[id] = now
	if not nameAsked[id] and type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
		nameAsked[id] = true
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
	return nil
end

-- An item a search asked the game for arrived (GET_ITEM_INFO_RECEIVED): its name is read at the
-- next draw, and the Treasury is drawn again by itself (once for those arriving together), so the
-- results the search could not name yet show without another keystroke. Every other item the
-- client loads costs a look-up here and nothing else.
function Bank.ItemInfoReceived(id)
	id = tonumber(id)
	if not id or not nameAsked[id] or foldedNames[id] then return false end
	nameMiss[id] = nil
	if not namesSoon then
		namesSoon = true
		ns.After(Bank.NAMES_REDRAW, "bank names", function()
			namesSoon = false
			ns.Fire("TREASURY_CHANGED")
		end)
	end
	return true
end

-- The search as the box holds it (folded: Views.Query): an item's link pasted in finds that item
-- alone (its number, whatever the box did to its codes), its name between brackets (a link's text,
-- pasted as the chat shows it) that name alone; otherwise a number (an item's) or a piece of a
-- name. nil for nothing to look for.
function Bank.ReadQuery(q)
	if type(q) ~= "string" then return nil end
	local link = tonumber(q:match("item:(%d+)"))
	if link then return { id = link } end
	local inner = q:match("%[(.-)%]")
	q = (tostring(inner or q):gsub("^%s+", ""):gsub("%s+$", ""))
	if q == "" then return nil end
	return { text = q, number = not inner and q:match("^%d+$") or nil, exact = inner ~= nil }
end

-- How well item `id` matches `w` (Bank.ReadQuery): 0 the item itself (its link, its number, its
-- whole name), 1 its name's start, 2 a word's start in it, 3 anywhere in it (or in its number);
-- nil for none (a name in brackets: the whole name or none).
local function Rank(id, w)
	if w.id then return id == w.id and 0 or nil end
	if w.number then
		local s = tostring(id)
		if s == w.number then return 0 end
		if s:find(w.number, 1, true) then return 3 end
	end
	local name = FoldedName(id)
	if not name then return nil end
	if name == w.text then return 0 end
	if w.exact then return nil end
	local at = name:find(w.text, 1, true)
	if not at then return nil end
	if at == 1 then return 1 end
	if name:sub(at - 1, at - 1):match("[%s%-'%(]") then return 2 end
	return 3
end

-- The items of the banks shown (`banks`, as Union takes them) that the search `q` finds, the best
-- match first, then the most: { { id, n (in all), rank, banks = { place in `banks`, ... } }, ... }.
function Bank.Search(banks, q)
	local out = {}
	local w = Bank.ReadQuery(q)
	if not w or type(banks) ~= "table" or #banks == 0 then return out end
	local u = Union(banks)
	asksLeft = Bank.NAME_ASKS
	for _, id in ipairs(u.list) do
		local rank = Rank(id, w)
		if rank then out[#out + 1] = { id = id, n = u.total[id], rank = rank, banks = u.ids[id] } end
	end
	table.sort(out, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.n ~= b.n then return a.n > b.n end
		return a.id < b.id
	end)
	return out
end

-- Where a found item (Bank.Search's) sits: each tab of each bank holding it, the most first:
-- { { bank = place in `banks`, tab = its tab's place in that snapshot, n }, ... }.
function Bank.Places(banks, found)
	local out = {}
	for _, k in ipairs(type(found) == "table" and found.banks or {}) do
		local b = banks[k]
		local x = b and Bank.Index(b.snap)
		local e = x and x.ids[found.id]
		for _, ti in ipairs(e and e.at or {}) do out[#out + 1] = { bank = k, tab = ti, n = e.tabs[ti] } end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		if a.bank ~= b.bank then return a.bank < b.bank end
		return a.tab < b.tab
	end)
	return out
end

-- Own-guild bank snapshots are separate from the federal treasury and its directory. Only the
-- live roster's GM or that guild's Treasury correspondent supplies them. The GM's short-lived
-- visibility grant reaches GUILD; the stock itself is always a bounded private transfer.
Bank.OWN_GUILD_LEASE = 1800
Bank.OWN_GUILD_ASK_GAP = 180
Bank.OWN_GUILD_KEEP = 3 * 86400
local ownGuildGrant, ownGuildReport
local ownGuildReaders, ownGuildLastAsk, ownGuildLastGrant = {}, -math.huge, -math.huge
local ownGuildGrantPending = false
local function GuildPreview()
	local V = ns.ViewAs
	return (ns.King and ns.King.Preview and ns.King.Preview() == true)
		or (type(V) == "table" and not V.missing and type(V.Role) == "function" and V.Role() ~= "my")
		or (ns.db and ns.db.devGMView == true)
end
local function GuildRank(name)
	local R = ns.Roster
	if not ns.IsMember() or not R or not R.Fresh or not R.Fresh() then return nil end
	local rank = R.RankOf(ns.FullName(name))
	if ns.Treasury.SameChar(name, ns.me) then
		local _, _, live = GetGuildInfo("player")
		if rank ~= live then return nil end
	end
	return rank
end
function Bank.OwnGuildKeeper(name)
	name = name or ns.me
	local rank = GuildRank(name)
	if rank == nil then return false end
	if rank == 0 then return true end
	local N = ns.Nominees
	return N and N.IsCorrespondent and N.IsCorrespondent(name, GetGuildInfo("player"), "Federal Treasury") == true or false
end
function Bank.OwnGuildMaster() return not GuildPreview() and GuildRank(ns.me) == 0 end
function Bank.OwnGuildPublic()
	local g = ownGuildGrant
	if not g or g.guild ~= GetGuildInfo("player") or GuildRank(g.by) ~= 0
		or ns.Now() - g.at > Bank.OWN_GUILD_LEASE then return false end
	return g.on == true
end
function Bank.OwnGuildReader(name)
	return GuildRank(name or ns.me) ~= nil and (Bank.OwnGuildKeeper(name) or Bank.OwnGuildPublic()) or false
end
function Bank.OwnGuildView() return not GuildPreview() and Bank.OwnGuildReader() end
function Bank.OwnGuildSnapshot()
	if GuildPreview() then return nil end
	if not Bank.OwnGuildReader() then ownGuildReport = nil; return nil end
	local guild, now = GetGuildInfo("player"), ns.Now()
	local function Valid(s)
		return type(s) == "table" and s.guild == guild and type(s.t) == "number" and s.t <= now + 30
			and now - s.t <= Bank.OWN_GUILD_KEEP and Bank.OwnGuildKeeper(s.by)
	end
	if not Valid(ownGuildReport) then ownGuildReport = nil end
	local own = Bank.OwnGuildKeeper() and Bank.Own() or nil
	if not Valid(own) then own = nil end
	if own and (not ownGuildReport or own.t >= ownGuildReport.t) then return own end
	return ownGuildReport
end
local function GuildGrantSend(force)
	if not Bank.OwnGuildMaster() then return false end
	local saved = ns.rdb and ns.rdb.guildBankVisibility
	local guild = GetGuildInfo("player")
	if type(saved) ~= "table" or saved.guild ~= guild or not ns.Treasury.SameChar(saved.by, ns.me) then return false end
	if not force and ns.Now() - ownGuildLastGrant < 30 then
		if not ownGuildGrantPending then
			ownGuildGrantPending = true
			ns.After(30, "guild bank visibility", function()
				ownGuildGrantPending = false
				GuildGrantSend()
				Bank.ShareOwnGuild()
			end)
		end
		return false
	end
	local rev, at = saved.rev, math.floor(ns.Now())
	ownGuildLastGrant = ns.Now()
	ownGuildGrant = { guild = guild, by = ns.me, on = saved.on == true, rev = rev, at = at }
	local msg = ("UP~%s~%.0f~%d~%d"):format(Clean(guild, 40), rev, at, saved.on and 1 or 0)
	ns.Comm.Send("GUILD", msg, "guild bank visibility", nil, nil, nil, { guard = function()
		return Bank.OwnGuildMaster() and GetGuildInfo("player") == guild and ns.rdb.guildBankVisibility == saved and saved.rev == rev
	end })
	return true
end
function Bank.SetOwnGuildPublic(on)
	if not Bank.OwnGuildMaster() or not ns.rdb then return false end
	local old = ns.rdb.guildBankVisibility
	ns.rdb.guildBankVisibility = { guild = GetGuildInfo("player"), by = ns.me, on = on == true,
		rev = math.max(math.floor(ns.Now()) * 1000, ((type(old) == "table" and tonumber(old.rev)) or 0) + 1) }
	GuildGrantSend(true)
	ns.Treasury.PrunePrivate()
	Bank.ShareOwnGuild()
	ns.Fire("TREASURY_CHANGED")
	return true
end
function Bank.HandleGuildGrant(dist, sender, text)
	if dist ~= "GUILD" or type(text) ~= "string" or #text > 140 or GuildRank(sender) ~= 0 then return false end
	local guild, rev, at, on = text:match("^UP~([^~]+)~(%d+)~(%d+)~([01])$")
	rev, at = tonumber(rev), tonumber(at)
	if guild ~= GetGuildInfo("player") or not rev or not at or rev > (ns.Now() + 30) * 1000
		or at > ns.Now() + 30 or ns.Now() - at > Bank.OWN_GUILD_LEASE then return false end
	if ownGuildGrant and ownGuildGrant.guild == guild then
		if ownGuildGrant.rev > rev then return false end
		if ownGuildGrant.rev == rev and (ownGuildGrant.on ~= (on == "1") or ownGuildGrant.at >= at) then return false end
	end
	local wasPublic, previousRev = Bank.OwnGuildPublic(), ownGuildGrant and ownGuildGrant.rev
	ownGuildGrant = { guild = guild, by = ns.FullName(sender), rev = rev, at = at, on = on == "1" }
	if not Bank.OwnGuildReader() then ownGuildReport = nil end
	ns.Treasury.PrunePrivate()
	ns.Fire("TREASURY_CHANGED")
	-- A late joiner's first ask discovers the policy; ask for stock only after receiving it.
	if on == "1" and (not wasPublic or previousRev ~= rev) and ns.Now() - ownGuildLastAsk <= Bank.OWN_GUILD_LEASE then
		ownGuildLastAsk = -math.huge
		Bank.AskOwnGuild()
	end
	return true
end
local function GuildSnapshotMessage()
	if GuildPreview() or not Bank.OwnGuildKeeper() then return nil end
	local snap = Bank.Own()
	if type(snap) ~= "table" or snap.guild ~= GetGuildInfo("player") or not ns.Treasury.SameChar(snap.by, ns.me)
		or type(snap.t) ~= "number" or snap.t > ns.Now() + 30 or ns.Now() - snap.t > Bank.OWN_GUILD_KEEP then return nil end
	return Bank.Message(snap, "UG")
end
function Bank.ShareOwnGuild()
	local msg, now, n = GuildSnapshotMessage(), ns.Now(), 0
	if not msg then return n end
	for name, request in pairs(ownGuildReaders) do
		if now - request.at > Bank.OWN_GUILD_LEASE or GuildRank(name) == nil then ownGuildReaders[name] = nil
		elseif (Bank.OwnGuildKeeper(name) or (Bank.OwnGuildPublic() and request.rev == ownGuildGrant.rev))
			and ns.Treasury.Private(name, "UG", msg) then n = n + 1 end
	end
	return n
end
function Bank.AskOwnGuild()
	if GuildPreview() or GuildRank(ns.me) == nil or ns.Now() - ownGuildLastAsk < Bank.OWN_GUILD_ASK_GAP then return false end
	ownGuildLastAsk = ns.Now()
	local guild = GetGuildInfo("player")
	local rev = Bank.OwnGuildPublic() and ownGuildGrant.rev or 0
	ns.Comm.Send("GUILD", ("UQ~%s~%.0f"):format(Clean(guild, 40), rev), "guild bank ask", nil, nil, nil, { guard = function()
		return not GuildPreview() and GetGuildInfo("player") == guild and GuildRank(ns.me) ~= nil
	end })
	return true
end
function Bank.HandleGuildAsk(dist, sender, text)
	if GuildPreview() or dist ~= "GUILD" or type(text) ~= "string" or #text > 80 or GuildRank(sender) == nil then return false end
	local guild, rev = text:match("^UQ~([^~]+)~(%d+)$")
	rev = tonumber(rev)
	if guild ~= GetGuildInfo("player") or not rev or rev > (ns.Now() + 30) * 1000 then return false end
	local name, now, count, oldest = ns.FullName(sender), ns.Now(), 0
	local old = ownGuildReaders[name]
	if old and now - old.at < 30 and not (rev > old.rev and ownGuildGrant and rev == ownGuildGrant.rev) then return false end
	for who, request in pairs(ownGuildReaders) do
		if now - request.at > Bank.OWN_GUILD_LEASE or GuildRank(who) == nil then ownGuildReaders[who] = nil
		else count = count + 1; if not oldest or request.at < ownGuildReaders[oldest].at then oldest = who end end
	end
	if not ownGuildReaders[name] and count >= 64 then ownGuildReaders[oldest] = nil end
	ownGuildReaders[name] = { at = now, rev = rev }
	-- A reload, a missed transfer, or a withdrawn grant may have removed unchanged stock.
	-- Resend preserves the private transport's minimum gap; a request cannot flood it.
	ns.Treasury.Resend(name, "UG")
	GuildGrantSend()
	Bank.ShareOwnGuild()
	return true
end
function Bank.HandleOwnGuild(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > Room() or not Bank.OwnGuildReader()
		or not Bank.OwnGuildKeeper(sender) then return false end
	local guild, at, money, rest = text:match("^UG~([^~]+)~(%d+)~(%d+)~(.*)$")
	at, money = tonumber(at), tonumber(money)
	if guild ~= GetGuildInfo("player") or not at or at > ns.Now() + 30 or ns.Now() - at > Bank.OWN_GUILD_KEEP
		or not money or money > 2147483647 then return false end
	local tabs, numbered = ReadTabs(rest, true)
	if not numbered or #tabs == 0 then return false end
	for _, tab in ipairs(tabs) do
		for _, item in ipairs(tab.items) do
			if item.id < 1 or item.id > 2147483647 or item.n < 1 then return false end
		end
	end
	if ownGuildReport and ownGuildReport.guild == guild and ownGuildReport.t > at then return false end
	ownGuildReport = { guild = guild, by = ns.FullName(sender), t = at, money = money, tabs = tabs, numbered = true }
	ns.Fire("TREASURY_CHANGED")
	return true
end
ns.Comm.Handle("UP", Bank.HandleGuildGrant)
ns.Comm.Handle("UQ", Bank.HandleGuildAsk)
ns.Comm.Handle("UG", Bank.HandleOwnGuild)
ns.Treasury.OnPrivate("UG", { from = Bank.OwnGuildKeeper, to = Bank.OwnGuildReader,
	send = function(to, msg) return not GuildPreview() and Bank.OwnGuildKeeper() and Bank.OwnGuildReader(to)
		and (Bank.OwnGuildKeeper(to) or (ownGuildReaders[ns.FullName(to)] and ownGuildGrant
			and ownGuildReaders[ns.FullName(to)].rev == ownGuildGrant.rev))
		and msg == GuildSnapshotMessage() end,
	handle = Bank.HandleOwnGuild })

-- Sister guilds' banks: an Olympus guild other than the King's, whose treasurer (its guild
-- master or an officer, by the server's own roster) says yes, has its snapshot whispered to the
-- directory's audience alone, never on the channel (the whole army would see another guild's
-- stock), when their addon asks (TA, Treasury.lua) and when it changes. 1.2 (the Guild treasuries,
-- on the Treasury tab): that audience is the King, the High Council (the author's signed list; his
-- Stewards and his Hands count as of it), the federal Treasurer (his own character, ns.TREASURER)
-- and the author. A yes given to 1.1's question (the King, his Stewards and his Hands) still covers
-- those alone: its giver is asked once more whether the others see it too (OLYMPUS_SISTER_BANK_WIDER).
--   TS~<guild>~<time>~<copper>~<tab>;<id>x<count>,.<gap>,...~<tab>;...   in pieces (Treasury.Private):
--   the tabs' names left out (a name another guild typed never reaches a viewer's screen, his
--   stream: "Tab 1", "Tab 2"). 1.2: <tab> is the tab's number in the bank, so a viewer matches a tab
--   with the same tab of the snapshot before (what left it since, Bank.Gone) even when one went
--   unread and was left out; 1.1 sent nothing there and reads nothing there (its "Tab 1", "Tab 2"
--   are the message's order). TS~<guild>~0~0~ withdraws it (his no)
-- Taken only from a Lord or Captain of that guild as current authority confirms: the legacy
-- census until explicit signed enforcement, our roster or the manifest afterwards. Before
-- enforcement the census can be gamed; a snapshot is its sender's word, shown with his name.
-- It is kept in memory alone, SISTERS_MAX guilds at most, and dropped once this character is no
-- longer of the directory's audience (Bank.Sisters). A no is taken from them too, and from
-- whoever sent the snapshot held. Konig's review of 1.1: his no reaches every viewer holding his bank, at once
-- those whose addon asked within ASK_EVERY and NO_MARGIN (before a /reload of ours too: the names
-- and times are kept in ns.db.sisterHeard that long), the others (heard before that: we were
-- offline) at their next ask, once a session, for as long as it stands: a character whose snapshot
-- went out is remembered (ns.db.sisterBankSent). A viewer we never hear again keeps it until he
-- logs out (his client keeps it in memory alone).
-- Every viewer's addon asks every ASK_EVERY, and each holder of a yes answers each one (a whole
-- snapshot to one who holds none or an older one, Treasury.Private's pace and queue; the same one
-- again SISTER_REPEAT later at the soonest): its cost grows with the audience, a few dozen characters.
Bank.SISTERS_MAX = 128    -- (1.2: every Olympus guild, the signed authority's largest set; 1.1 kept 20)
Bank.SISTER_OLD = 3 * 86400 -- a snapshot taken longer ago shows as old (the bank not opened since)
-- The same snapshot whispered again to the same viewer this long after at most (Treasury.Private's
-- PRIVATE_REPEAT is half an hour): he keeps it until he logs out, and his addon's ask that says it
-- holds nothing (after a login or a /reload, its first of a session, its first back in the
-- audience: Treasury.Ask) has it sent again, at once or PRIVATE_GAP after the last one (inside
-- RESET_GAP: Treasury.Resend). A changed one goes as ever.
Bank.SISTER_REPEAT = 3 * 3600
Bank.CONSENT_ALL = 2      -- ns.db.sisterBankShares: 1.2's yes, to the directory's whole audience
Bank.CONSENT_KING = 1     -- ...asked that, he kept 1.1's yes (the King, his Stewards and his Hands)
Bank.NO_MARGIN = 180 -- a viewer heard within ASK_EVERY and this is told our no at once (his ask: on a minute's timer, queued)
function Bank.NoWithin() return ns.Treasury.ASK_EVERY + Bank.NO_MARGIN end
local sisters, sisterCount = {}, 0   -- [guild, lower case] = { guild, by, t, money, tabs, heard, sister, numbered, prev }
local sisterHeard = {}               -- [Name-Realm] = when one of the directory's audience asked
local sisterNoTold = {}              -- [Name-Realm] = true: he holds nothing of ours (told our no, or asked afresh)
local sisterAsked = false
local sisterSeen, sisterLapsed = false, false -- this client was of the audience; it left it since its last ask

-- 1.1's audience: the King, his Steward, his Hands (their names, which the server stamps).
local function CrownViewer(name)
	if type(name) ~= "string" or name == "" then return false end
	return ns.IsKingCharacter(name) or ns.King.IsStewardName(name) or ns.King.IsHandName(name)
end
-- 1.2's, the Guild treasuries': those, the High Council, the federal Treasurer and the author.
local function DirectoryViewer(name)
	if CrownViewer(name) then return true end
	if type(name) ~= "string" or name == "" then return false end
	if ns.IsHighCouncillor(name) or ns.Treasury.TreasurerPin(name) == 1 then return true end
	return ns.Workshop ~= nil and ns.Workshop.IsAuthorName ~= nil and ns.Workshop.IsAuthorName(name) == true
end
Bank.DirectoryViewer = DirectoryViewer
-- Who may hold a snapshot of ours, whatever our answer now: heard asking, told our no.
local SisterViewer = DirectoryViewer
-- This client is one of the directory's audience (never a preview: the author's views change
-- which pages are drawn alone, ViewAs.lua).
function Bank.SeesSisters()
	if ns.King.IsKing() or ns.King.IsSteward() or ns.King.IsHand() then return true end
	if type(ns.me) ~= "string" then return false end
	if ns.IsHighCouncillor(ns.me) then return true end
	if ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) then return true end
	return ns.Workshop ~= nil and ns.Workshop.IsAuthor ~= nil and ns.Workshop.IsAuthor() == true
end
-- Still of it: once this character no longer is (taken off the High Council, no longer a Hand),
-- what it held goes, at its next use or the share tick at the latest, and its next ask once it is
-- of it again says it holds nothing (Bank.Lapsed: its senders' 3 hours, SISTER_REPEAT, never wait).
local function Holding()
	if Bank.SeesSisters() then
		sisterSeen = true
		return true
	end
	if sisterSeen then sisterSeen, sisterLapsed = false, true end
	if sisterCount > 0 then wipe(sisters) sisterCount = 0 end
	return false
end
Bank.Holding = Holding
-- Its addon asks for them (TA): the King's, a Steward's and the Treasurer's ask anyway, as insiders.
function Bank.AsksSisters() return Bank.SeesSisters() end
-- Back in the audience after what it held was dropped: this ask says it holds nothing (once).
function Bank.Lapsed()
	if not sisterLapsed or not Bank.SeesSisters() then return false end
	sisterLapsed, sisterSeen = false, true
	return true
end

-- A Lord or Captain of `guild`: the legacy census until explicit enforcement, then our roster
-- for our guild and the author-signed leadership manifest for another.
function Bank.LordOrCaptain(sender, guild)
	if type(sender) ~= "string" or type(guild) ~= "string" or guild == "" then return false end
	local rank = ns.Data.AuthorizedRank(ns.FullName(sender), guild)
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

-- This character is its guild's treasurer for this: the guild master or an officer (the server's
-- rank), of an Olympus guild that is not the King's.
function Bank.SisterTreasurer()
	if not ns.IsMember() or not ns.me then return false end
	local guild, _, rank = GetGuildInfo("player")
	rank = tonumber(rank)
	return type(guild) == "string" and not ns.IsKingGuild(guild) and rank ~= nil and rank <= ns.CAPTAIN_RANK
end
local function SisterKey() return tostring(ns.FullName(ns.me) or ""):lower() end
-- This character's snapshot went out (`guild`'s), or the guild it last went out of (nil: never).
local function MarkSent(guild)
	if not ns.db or type(guild) ~= "string" or guild == "" then return end
	ns.db.sisterBankSent = type(ns.db.sisterBankSent) == "table" and ns.db.sisterBankSent or {}
	ns.db.sisterBankSent[SisterKey()] = guild
end
local function SentGuild()
	local t = ns.db and ns.db.sisterBankSent
	local g = type(t) == "table" and t[SisterKey()]
	return type(g) == "string" and g ~= "" and g or nil
end
-- The guild his answer was given for (ns.db.sisterBankFor, per character: its question named it).
local function AnsweredFor()
	local t = ns.db and ns.db.sisterBankFor
	local g = type(t) == "table" and t[SisterKey()]
	return type(g) == "string" and g ~= "" and g or nil
end
-- His answer as kept, per character: CONSENT_ALL (1.2's yes), CONSENT_KING or true (1.1's yes:
-- true until he is asked 1.2's question), false (his no), nil (never answered). (A 1.1 addon reads
-- a number there as no yes: an addon taken back to 1.1 shares nothing.) 1.2: a yes is for the guild
-- its question named, kept with it (sisterBankFor; 1.1's, which kept none: the guild its snapshot
-- went out of, when it did). An officer now of another Olympus guild has no answer there: nothing
-- of that bank goes anywhere until he is asked again, there. His no stands wherever he is.
local function Answer()
	local t = ns.db and ns.db.sisterBankShares
	if type(t) ~= "table" then return nil end
	local a = t[SisterKey()]
	if a == Bank.CONSENT_ALL or a == Bank.CONSENT_KING or a == true then
		local was, guild = AnsweredFor() or (a == true and SentGuild() or nil), GetGuildInfo("player")
		if a ~= true and not was then return nil end
		if was and (type(guild) ~= "string" or was:lower() ~= guild:lower()) then return nil end
	end
	return a
end
-- His yes (true: 1.2's or 1.1's), his no (false), or nil until he answers.
function Bank.SisterConsent()
	local a = Answer()
	if a == false then return false end
	if a == true or a == Bank.CONSENT_ALL or a == Bank.CONSENT_KING then return true end
	return nil
end
-- Whom his yes covers: "all" (1.2's: the directory's audience), "crown" (1.1's: the King, his
-- Stewards and his Hands), nil (no yes).
function Bank.SisterScope()
	local a = Answer()
	if a == Bank.CONSENT_ALL then return "all" end
	if a == true or a == Bank.CONSENT_KING then return "crown" end
	return nil
end
-- Whom our snapshot goes to now, by his yes (checked again for every piece: Treasury.Private).
local function Serves(name)
	local scope = Bank.SisterScope()
	if scope == "all" then return DirectoryViewer(name) end
	if scope == "crown" then return CrownViewer(name) end
	return false
end
Bank.Serves = Serves

-- The viewers heard asking, kept over a /reload of ours (ns.db.sisterHeard, by name: when) for as
-- long as our no goes to them at once (NO_WITHIN), older ones dropped. Konig's review of 1.1.
local function KeptHeard()
	if not ns.db then return {} end
	local t, now = type(ns.db.sisterHeard) == "table" and ns.db.sisterHeard or {}, ns.Now()
	ns.db.sisterHeard = t
	for name, at in pairs(t) do
		if type(name) ~= "string" or type(at) ~= "number" or now - at > Bank.NoWithin() then t[name] = nil end
	end
	return t
end
-- Our no, whispered to one viewer.
local function TellNo(name, guild)
	sisterNoTold[ns.FullName(name)] = true
	ns.Comm.Whisper(name, ("TS~%s~0~0~"):format(Clean(guild, 40)), "sisterbank " .. name)
end

-- Our own guild's snapshot as it is whispered (TS), with his yes; nil otherwise.
function Bank.SisterMessage()
	if not Bank.SisterTreasurer() or Bank.SisterConsent() ~= true then return nil end
	local snap, guild = Bank.Own(), GetGuildInfo("player")
	if type(snap) ~= "table" or snap.guild ~= guild then return nil end
	return Bank.Message(snap, "TS")
end

-- To each viewer his yes covers who asked within Treasury.AUDIENCE_FRESH (each gets a snapshot
-- once, the next when it changed).
function Bank.ShareSister()
	local msg = Bank.SisterMessage()
	if not msg then return 0 end
	local n, now = 0, ns.Now()
	for name, t in pairs(sisterHeard) do
		if now - t <= ns.Treasury.AUDIENCE_FRESH and Serves(name) and ns.Treasury.Private(name, "TS", msg) then n = n + 1 end
	end
	if n > 0 then MarkSent(GetGuildInfo("player")) end
	return n
end

-- One of the directory's audience asked (TA): our guild's bank goes to him if our yes covers him
-- (fresh: he holds none, RESET_GAP apart; empty: his ask says so, however soon: the same snapshot
-- again PRIVATE_GAP after the last at the soonest, Treasury.Resend). While our no stands, after our
-- snapshot went out: the no, once a session (Konig's review of 1.1).
function Bank.HeardAsk(sender, fresh, empty)
	if not SisterViewer(sender) then return end
	local name = ns.FullName(sender)
	sisterHeard[name] = ns.Now()
	KeptHeard()[name] = sisterHeard[name]
	if fresh then ns.Treasury.ForgetSent(sender, "TS") elseif empty then ns.Treasury.Resend(sender, "TS") end
	if Bank.SisterConsent() == false then
		local guild = SentGuild()
		if guild and not sisterNoTold[name] then
			if fresh then sisterNoTold[name] = true else TellNo(sender, guild) end
		end
		return
	end
	local msg = Bank.SisterMessage()
	if msg and Serves(sender) and ns.Treasury.Private(sender, "TS", msg) then MarkSent(GetGuildInfo("player")) end
end
function Bank.NotFound(Is)
	for name in pairs(sisterHeard) do if Is(name) then sisterHeard[name] = nil end end
	local kept = KeptHeard()
	for name in pairs(kept) do if Is(name) then kept[name] = nil end end
end

-- on: his yes, 1.2's (the directory's whole audience), or with kingOnly 1.1's kept (the King, his
-- Stewards and his Hands: his answer to OLYMPUS_SISTER_BANK_WIDER); otherwise his no.
function Bank.SetSisterConsent(on, kingOnly)
	if not Bank.SisterTreasurer() then return ns.Print(L.BANK_SISTER_ONLY) end
	ns.db.sisterBankShares = type(ns.db.sisterBankShares) == "table" and ns.db.sisterBankShares or {}
	ns.db.sisterBankShares[SisterKey()] = on and (kingOnly and Bank.CONSENT_KING or Bank.CONSENT_ALL) or false
	ns.db.sisterBankFor = type(ns.db.sisterBankFor) == "table" and ns.db.sisterBankFor or {}
	ns.db.sisterBankFor[SisterKey()] = GetGuildInfo("player") -- (the guild his question named: Answer)
	ns.Print(on and (kingOnly and L.BANK_SISTER_KING_KEPT or L.BANK_SISTER_ON) or L.BANK_SISTER_OFF)
	if on then
		wipe(sisterNoTold) -- (a later no goes to every viewer again)
		ns.Treasury.PrunePrivate() -- (whatever still waits for one his yes no longer covers)
		return Bank.ShareSister()
	end
	ns.Treasury.CancelPrivate(function(o) return o.kind == "TS" end)
	-- His no: taken back from the screens it reached, at once from every viewer whose addon asked
	-- within NO_WITHIN (they ask every ASK_EVERY: Konig's review of 1.1; AUDIENCE_FRESH, shorter,
	-- missed one who asked 12 minutes before), those heard before a /reload of ours too (KeptHeard);
	-- from the others at their next ask (HeardAsk). Whole snapshots still go only to those heard
	-- within AUDIENCE_FRESH (ShareSister).
	local guild, now = SentGuild() or GetGuildInfo("player"), ns.Now()
	local within = {}
	for name, t in pairs(KeptHeard()) do within[name] = t end
	for name, t in pairs(sisterHeard) do
		if t > (within[name] or -math.huge) then within[name] = t end
		ns.Treasury.ForgetSent(name, "TS")
	end
	for name, t in pairs(within) do
		if now - t <= Bank.NoWithin() then TellNo(name, guild) end
	end
end

StaticPopupDialogs["OLYMPUS_SISTER_BANK"] = {
	text = L.BANK_SISTER_ASK,
	button1 = L.BANK_SISTER_YES,
	button2 = L.BANK_SISTER_NO,
	OnAccept = function() ns.SafeCall("sister bank", Bank.SetSisterConsent, true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("sister bank", Bank.SetSisterConsent, false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	noCancelOnEscape = true, -- Escape is no answer: asked again next session
	preferredIndex = 3,
}
-- 1.2: whoever said yes to 1.1's question is asked this once: the directory's other viewers too?
-- Its no keeps 1.1's yes (the King, his Stewards and his Hands); /oly bank share off stays the no.
StaticPopupDialogs["OLYMPUS_SISTER_BANK_WIDER"] = {
	text = L.BANK_SISTER_WIDER,
	button1 = L.BANK_SISTER_WIDER_YES,
	button2 = L.BANK_SISTER_WIDER_NO,
	OnAccept = function() ns.SafeCall("sister bank", Bank.SetSisterConsent, true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("sister bank", Bank.SetSisterConsent, true, true) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	noCancelOnEscape = true, -- Escape is no answer: asked again next session
	preferredIndex = 3,
}
-- Asked once a session, when he opens his guild's bank, until he answers (never in combat): 1.2's
-- question if he never answered, whether the others see it too if he said yes to 1.1's.
function Bank.AskSister()
	if sisterAsked or not Bank.SisterTreasurer() then return false end
	local a = Answer()
	local which = a == nil and "OLYMPUS_SISTER_BANK" or a == true and "OLYMPUS_SISTER_BANK_WIDER" or nil
	if not which then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	sisterAsked = true
	ns.ShowDialog(which, GetGuildInfo("player") or "?")
	return true
end

-- A sister guild's snapshot (TS), on a client of the directory's audience: from a Lord or Captain
-- of that guild (the legacy census until enforcement, our roster or the signed manifest
-- afterwards), the newest kept, in memory alone. 1.2: the one it replaces, the same sender's and
-- older, is kept with it (prev: one, never a chain), for what left the bank since (Bank.Previous);
-- the same snapshot heard again (his addon repeats it) changes nothing.
function Bank.HandleSister(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or not Holding() then return end
	local guild, when, money, rest = text:match("^TS~([^~]*)~(%d+)~(%d+)~?(.*)$")
	guild = guild and ns.King.CleanGuild(guild)
	if not guild or ns.IsKingGuild(guild) then return end
	local key, now = guild:lower(), ns.Now()
	when = tonumber(when)
	-- (A no from whoever sent the snapshot held counts, whatever the census says of him now.)
	local own = when == 0 and sisters[key] and ns.Treasury.SameChar(sisters[key].by, ns.FullName(sender))
	if not own and not Bank.LordOrCaptain(sender, guild) then return end
	if when == 0 then
		if sisters[key] then sisters[key], sisterCount = nil, sisterCount - 1 end
		ns.Fire("TREASURY_CHANGED")
		return
	end
	local tabs, numbered = ReadTabs(rest, true)
	local r = { guild = guild, by = ns.FullName(sender), t = math.min(when, now), money = math.min(tonumber(money) or 0, 2147483647),
		tabs = tabs, heard = now, sister = true, numbered = numbered }
	if #r.tabs == 0 then return end
	local kept = sisters[key]
	if kept and kept.t > r.t then return end
	local same = kept and ns.Treasury.SameChar(kept.by, r.by)
	if same and kept.t == r.t and kept.money == r.money and kept.numbered == r.numbered and #kept.tabs == #r.tabs then
		kept.heard = now
		return
	end
	if same and kept.t < r.t then r.prev = kept elseif same then r.prev = kept.prev end
	if kept then kept.prev = nil end
	if not kept then
		if sisterCount >= Bank.SISTERS_MAX then
			local oldest
			for k, x in pairs(sisters) do if not oldest or x.heard < sisters[oldest].heard then oldest = k end end
			sisters[oldest], sisterCount = nil, sisterCount - 1
		end
		sisterCount = sisterCount + 1
	end
	sisters[key] = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED") -- (a viewer's tab may appear)
end
ns.Comm.Handle("TS", function(...) Bank.HandleSister(...) end)
ns.Treasury.OnPrivate("TS", { from = function() return true end, to = function() return Holding() end,
	send = function(to) return Bank.SisterTreasurer() and Serves(to) end, repeatAfter = Bank.SISTER_REPEAT,
	handle = function(...) Bank.HandleSister(...) end })

-- The sister guilds' banks this client holds, by guild name (one of the directory's audience).
-- Once this character is no longer of it (taken off the High Council, no longer a Hand), what it
-- held goes.
function Bank.Sisters()
	local out = {}
	if not Holding() then return out end
	local enforcing = ns.Authority and ns.Authority.Enforced and ns.Authority.Enforced()
	for key, x in pairs(sisters) do
		if not enforcing or Bank.LordOrCaptain(x.by, x.guild) then out[#out + 1] = x
		else sisters[key], sisterCount = nil, sisterCount - 1 end
	end
	table.sort(out, function(a, b) return a.guild:lower() < b.guild:lower() end)
	return out
end

---------------------------------------------------------------------------
-- 1.1: bank requests (Fern's): a Lord or a Captain asks the treasury for an item and a count
-- ("need 10 Ironwood"), shown next to the bank snapshot. The bank view shows what the treasury
-- holds, not what the raid is short: a request line stops five officers from buying the same
-- stack. Handing it over stays a normal trade or mail, the player's own click: the addon moves
-- nothing, and a request closes by itself when the keeper's book records that item given to that
-- player (Treasury.Record).
--   TN~<id>~<item>~<count>~<guild>   by whisper, from a Lord or a Captain to each keeper, the King
--                                     and his Stewards heard online (count 0: he cancels it); sent
--                                     again every REQUEST_AGAIN while it is open, and answered each time
--   TO~<id>~<o|d|x|c>[~<Name-Realm>]  by whisper, a keeper's (the King's, a Steward's) answer: open
--                                     (seen), done, declined, cancelled; with a name, to the other
--                                     keepers, the King and his Stewards: that player's request changed
--   TL~<guild>~<id>:<item>:<count>:<Name-Realm>:<Guild>,...   on the channel, a keeper's open
--                                     requests, only while the King shows the army the book (the bank
--                                     goes with it), for everyone who sees the bank; none: not sent
-- No text travels, only an item's number and a count; REQUEST_OPEN open per character at most, each
-- for REQUEST_DAYS. Whom it comes from is checked as a sister guild's bank is (Bank.LordOrCaptain).
-- Paced (Konig's review of 1.1: a request taken back and made again, or a modified client's new
-- ids, had every keeper print a line, answer and put his list on the channel each time): REQUEST_NEW
-- new requests a REQUEST_WINDOW per character (his own client says so; a keeper's takes no more from
-- one player, and keeps REQUESTS_EACH of his at most), one answer to the same open request unchanged
-- an ANSWER_GAP and none to a closed one he was told of (so REQUEST_OPEN of his a keeper answers
-- again at most), and a keeper's list on the channel once a PUBLIC_GAP (a change inside it goes then).
---------------------------------------------------------------------------
Bank.REQUEST_OPEN = 3
Bank.REQUEST_DAYS = 3
Bank.REQUEST_MAX_COUNT = 9999
Bank.REQUEST_AGAIN = 900
Bank.REQUESTS_KEPT = 60
Bank.REQUEST_NEW = 6        -- new requests of one character a REQUEST_WINDOW, at most
Bank.REQUEST_WINDOW = 3600
Bank.REQUESTS_EACH = 10     -- requests of one player a keeper's client keeps (his oldest closed one goes)
Bank.ANSWER_GAP = Bank.REQUEST_AGAIN / 2 -- an open request unchanged answered again this long after at the soonest
                            -- (a closed one, its state told, never again: Konig's review of 1.1)
Bank.PUBLIC_GAP = 60        -- a keeper's list goes on the channel this often at most
Bank.PUBLIC_KEPT = 1800   -- a keeper's list on the channel not repeated this long is dropped
Bank.PUBLIC_MSGS = 2      -- messages of it at most, each one of the channel's size

local lastAsked = {}      -- ["Name-Realm#id"] = when our request was last whispered to him
local publicLists = {}    -- [keeper's Name-Realm] = { t, list = { { id, item, n, from, guild } } }
local lastPublic          -- what our client last put on the channel ("" once it said none)
local lastPublicAt, publicPending = -math.huge, false
local CODE = { open = "o", done = "d", declined = "x", cancelled = "c" }
local STATE = { o = "open", d = "done", x = "declined", c = "cancelled" }

local function Fire()
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED") -- (the tab may appear)
end
local function Label(item, n) return ns.Treasury.ItemText(item, n) end
local function Field(s, n) return ns.Cut((tostring(s or ""):gsub("[~;:,|%c]", " ")), n) end
local function Open(state) return state == "sent" or state == "seen" or state == "open" end
local function Expired(e) return ns.Now() - (tonumber(e.t) or 0) > Bank.REQUEST_DAYS * 86400 end

-- A Lord or a Captain of an Olympus guild (the server's rank of this character); not the King, a
-- Steward or a keeper: the treasury is theirs already. (The treasury is the Alliance's <Olympus>'s.)
function Bank.MayRequest()
	if ns.faction == "Horde" or not ns.IsMember() or ns.Treasury.IsInsider() then return false end
	local _, _, rank = GetGuildInfo("player")
	rank = tonumber(rank)
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

-- This character's own requests (kept per character), and the requests a keeper's, the King's or
-- a Steward's client holds (["Name-Realm#id"]).
local function Mine()
	ns.rdb.bankAsks = type(ns.rdb.bankAsks) == "table" and ns.rdb.bankAsks or {}
	local key = tostring(ns.FullName(ns.me) or ""):lower()
	ns.rdb.bankAsks[key] = type(ns.rdb.bankAsks[key]) == "table" and ns.rdb.bankAsks[key] or {}
	return ns.rdb.bankAsks[key]
end
local function Held()
	ns.rdb.bankRequests = type(ns.rdb.bankRequests) == "table" and ns.rdb.bankRequests or {}
	return ns.rdb.bankRequests
end

-- Cross-guild permission remains binding while an answer waits in Comm's queue.  A newer
-- signed manifest, expiry, net-off or a local roster change cancels the actual send.
local function RequesterGuard(e)
	return function()
		if not (ns.Authority and ns.Authority.Enforced and ns.Authority.Enforced()) then return true end
		return type(e) == "table" and not Expired(e) and Bank.LordOrCaptain(e.from, e.guild)
	end
end

-- Our requests, newest first (the expired dropped).
function Bank.MyRequests()
	if not ns.rdb or not ns.me then return {} end
	local list, out = Mine(), {}
	for i = #list, 1, -1 do if Expired(list[i]) then table.remove(list, i) end end
	for i = #list, 1, -1 do out[#out + 1] = list[i] end
	return out
end

-- The requests this client holds for the treasury (a keeper's, the King's, a Steward's): the open
-- ones first, then the ones closed within a day, the newest first. { { key, from, guild, id, item,
-- n, t, state, by, at } }.
function Bank.Requests()
	if not ns.rdb or not ns.Treasury.IsInsider() then return {} end
	local out, held = {}, Held()
	for key, e in pairs(held) do
		if Expired(e) then held[key] = nil
		elseif Open(e.state) or ns.Now() - (tonumber(e.at) or 0) <= 86400 then e.key = key; out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		local x, y = Open(a.state), Open(b.state)
		if x ~= y then return x end
		return (tonumber(a.t) or 0) > (tonumber(b.t) or 0)
	end)
	return out
end

-- The open requests the keepers put on the channel (while the King shows the army the book),
-- each once: { { id, item, n, from, guild } }.
function Bank.PublicRequests()
	local out, seen, now = {}, {}, ns.Now()
	for keeper, x in pairs(publicLists) do
		if now - x.t > Bank.PUBLIC_KEPT or not ns.Treasury.KeeperByName(keeper) then
			publicLists[keeper] = nil
		else
			for _, e in ipairs(x.list) do
				local key = e.from .. "#" .. e.id
				if not seen[key] then seen[key] = true out[#out + 1] = e end
			end
		end
	end
	table.sort(out, function(a, b) return a.from < b.from or (a.from == b.from and a.id < b.id) end)
	return out
end

-- Our open requests go to each keeper, the King and his Stewards heard online (Treasury.Online),
-- at once for a new one (force), again every REQUEST_AGAIN while it is open: each answers with
-- where it stands. Returns how many whispers went.
function Bank.SendRequests(force)
	if not ns.rdb or not ns.me or not ns.IsMember() then return 0 end
	local n, now, guild = 0, ns.Now(), Clean(GetGuildInfo("player"), 40)
	for _, e in ipairs(Mine()) do
		local cancel = e.state == "cancel"
		if (Open(e.state) or cancel) and not Expired(e) then
			for _, to in ipairs(ns.Treasury.Online()) do
				local key = to .. "#" .. e.id
				if (force == e or force == true) or now - (lastAsked[key] or -math.huge) >= Bank.REQUEST_AGAIN then
					lastAsked[key] = now
					ns.Comm.Whisper(to, ("TN~%d~%d~%d~%s"):format(e.id, e.item, cancel and 0 or e.n, guild), "bankreq " .. key)
					n = n + 1
				end
			end
		end
	end
	return n
end

-- A Lord or a Captain asks the treasury for `count` of `item` (an item's number).
function Bank.Request(item, count)
	if not Bank.MayRequest() then return ns.Print(L.BANK_REQUEST_ONLY) end
	item, count = tonumber(item), math.floor(tonumber(count) or 0)
	if not item or item <= 0 or item >= 2147483647 or count < 1 or count > Bank.REQUEST_MAX_COUNT then return ns.Print(L.BANK_REQUEST_WHAT) end
	local list, open, recent, first, now = Mine(), 0, 0, nil, ns.Now()
	for _, e in ipairs(list) do
		if Open(e.state) and not Expired(e) then open = open + 1 end
		local t = tonumber(e.t) or 0
		if now - t < Bank.REQUEST_WINDOW then
			recent = recent + 1
			if not first or t < first then first = t end
		end
	end
	if open >= Bank.REQUEST_OPEN then return ns.Print(L.BANK_REQUEST_FULL:format(Bank.REQUEST_OPEN)) end
	if recent >= Bank.REQUEST_NEW then
		return ns.Print(L.BANK_REQUEST_PACED:format(recent, math.max(1, math.ceil((first + Bank.REQUEST_WINDOW - now) / 60))))
	end
	local e = { id = math.random(1, 99999), item = item, n = count, t = ns.Now(), state = "sent", seen = {} }
	list[#list + 1] = e
	while #list > 10 do table.remove(list, 1) end
	local sent = Bank.SendRequests(e)
	ns.Print((sent > 0 and L.BANK_REQUEST_SENT or L.BANK_REQUEST_WAITING):format(Label(item, count)))
	Fire()
	return e
end

-- "10 Ironwood", "10x [Ironwood]" (a link shift-clicked into the chat line), "10 12345" (its number),
-- or the item alone (one): a request.
function Bank.RequestText(text)
	text = tostring(text or "")
	local count, what = text:match("^%s*(%d+)%s*[xX]?%s+(.-)%s*$")
	if not count then count, what = 1, text:match("^%s*(.-)%s*$") end
	local id = tonumber(what:match("item:(%d+)")) or tonumber(what:match("^#?(%d+)$"))
	if not id and what ~= "" and GetItemInfo then
		local ok, _, link = pcall(GetItemInfo, what)
		id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	end
	if not id then return ns.Print(L.BANK_REQUEST_WHAT) end
	return Bank.Request(id, count)
end

-- He takes his request back.
function Bank.Cancel(id)
	for _, e in ipairs(Mine()) do
		if e.id == id and Open(e.state) then
			e.state, e.at = "cancel", ns.Now()
			Bank.SendRequests(e)
			ns.Print(L.BANK_REQUEST_CANCELLED:format(Label(e.item, e.n)))
			return Fire()
		end
	end
end

-- On a keeper's, the King's or a Steward's client: a request (TN) from a Lord or Captain of that
-- guild (our roster or its census), REQUEST_OPEN open each at most, REQUESTS_KEPT in all; answered
-- with where it stands (TO), each time he asks.
function Bank.HandleRequest(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or not ns.Treasury.IsInsider() then return end
	local id, item, count, guild = text:match("^TN~(%d+)~(%d+)~(%d+)~([^~]*)$")
	id, item, count = tonumber(id), tonumber(item), tonumber(count)
	guild = guild and ns.King.CleanGuild(guild)
	if not (id and item and item > 0 and item < 2147483647 and count and count <= Bank.REQUEST_MAX_COUNT and guild) then return end
	sender = ns.FullName(sender)
	if not Bank.LordOrCaptain(sender, guild) then return ns.Log("bank request from %s (%s) ignored: not its Lord or a Captain", sender, guild) end
	local held, key, now = Held(), sender .. "#" .. id, ns.Now()
	local e = held[key]
	if count == 0 then
		if e and Open(e.state) then e.state, e.at, e.by = "cancelled", now, nil end
	elseif not e then
		local open, n, closed, oldest, mine, recent, myClosed = 0, 0, nil, nil, 0, 0, nil
		for k, x in pairs(held) do
			n = n + 1
			if x.from == sender then
				mine = mine + 1
				if Open(x.state) and not Expired(x) then open = open + 1 end
				if now - (tonumber(x.t) or 0) < Bank.REQUEST_WINDOW then recent = recent + 1 end
				if not Open(x.state) and (not myClosed or (x.t or 0) < (held[myClosed].t or 0)) then myClosed = k end
			end
			if Open(x.state) then
				if not oldest or (x.t or 0) < (held[oldest].t or 0) then oldest = k end
			elseif not closed or (x.t or 0) < (held[closed].t or 0) then
				closed = k
			end
		end
		-- (Paced, Konig's review of 1.1: past REQUEST_NEW new ones in the window, nothing at all.)
		if open >= Bank.REQUEST_OPEN or recent >= Bank.REQUEST_NEW then return end
		-- His REQUESTS_EACH: his oldest closed one goes. Full: the oldest closed one goes, else the oldest.
		if mine >= Bank.REQUESTS_EACH and myClosed then
			held[myClosed] = nil
		elseif n >= Bank.REQUESTS_KEPT then
			held[closed or oldest] = nil
		end
		e = { from = sender, guild = guild, id = id, item = item, n = count, t = now, state = "open" }
		held[key] = e
		ns.Print(L.BANK_REQUEST_NEW:format(ns.DisplayName(sender), guild, Label(item, count)))
		Bank.SharePublic()
	end
	if not e then return end
	e.heard = now
	-- (A change at once. Unchanged: an open request once an ANSWER_GAP at most, half its asker's
	-- REQUEST_AGAIN, so each honest ask is answered; a closed one, its state told, never again.
	-- Konig's review of 1.1: paced per request id alone, a requester's REQUESTS_EACH ids asked about
	-- every minute drew as many whispers a minute from every keeper, the King and each Steward.)
	local code = CODE[e.state] or "o"
	if e.told ~= code or (Open(e.state) and now - (tonumber(e.toldAt) or 0) >= Bank.ANSWER_GAP) then
		e.told, e.toldAt = code, now
		ns.Comm.Whisper(sender, ("TO~%d~%s"):format(id, code), "bankans " .. key,
			nil, nil, nil, { owner = e, guard = RequesterGuard(e) })
	end
	Fire()
end
ns.Comm.Handle("TN", function(...) Bank.HandleRequest(...) end)

-- A keeper (the King, a Steward) marks a request done or declined: the requester is told (while
-- he was heard lately: otherwise his next ask gets it), and the others who hold it.
function Bank.Answer(key, state)
	local e = ns.Treasury.IsInsider() and ns.rdb and Held()[key]
	if not e or not CODE[state] or e.state == state then return end
	e.state, e.by, e.at = state, ns.me, ns.Now()
	-- (Not marked told: he may have logged off since he was heard, and a closed request he was told
	-- of is never answered again, HandleRequest. The answer to his own next ask marks it.)
	if ns.Now() - (e.heard or -math.huge) <= ns.Treasury.AUDIENCE_FRESH then
		ns.Comm.Whisper(e.from, ("TO~%d~%s"):format(e.id, CODE[state]), "bankans " .. key,
			nil, nil, nil, { owner = e, guard = RequesterGuard(e) })
	end
	for _, to in ipairs(ns.Treasury.Online()) do
		if not ns.Treasury.SameChar(to, e.from) then ns.Comm.Whisper(to, ("TO~%d~%s~%s"):format(e.id, CODE[state], e.from), "bankans " .. to .. key) end
	end
	Bank.SharePublic()
	Fire()
end

-- An answer (TO), from a keeper, the King or a Steward alone: about our own request, or (with a
-- name, on another keeper's client) about one he holds too.
function Bank.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" then return end
	local id, code, whose = text:match("^TO~(%d+)~([odxc])~?([^~]*)$")
	id = tonumber(id)
	sender = ns.FullName(sender)
	if not id or not ns.Treasury.InsiderName(sender) then return end
	local state = STATE[code]
	if whose ~= "" then
		local e = ns.Treasury.IsInsider() and Held()[ns.FullName(whose) .. "#" .. id]
		if e and e.state ~= state then
			e.state, e.by, e.at = state, sender, ns.Now()
			Fire()
		end
		return
	end
	for _, e in ipairs(Mine()) do
		if e.id == id then
			e.seen = type(e.seen) == "table" and e.seen or {}
			e.seen[sender] = true
			if state == "open" then
				if e.state == "sent" then e.state, e.by = "seen", sender end
			elseif state ~= "cancelled" and Open(e.state) then
				e.state, e.by, e.at = state, sender, ns.Now()
				ns.Print(L[state == "done" and "BANK_REQUEST_DONE" or "BANK_REQUEST_DECLINED"]:format(Label(e.item, e.n), ns.DisplayName(sender)))
			end
			return Fire()
		end
	end
end
ns.Comm.Handle("TO", function(...) Bank.HandleAnswer(...) end)

-- The keeper's book recorded an item given (a counted payment, Treasury.Record): the open request
-- of that player for that item closes once he got its count (done by this keeper).
function Bank.Paid(name, item, count)
	if not ns.rdb or not ns.Treasury.IsInsider() then return end
	for key, e in pairs(Held()) do
		if Open(e.state) and e.item == item and ns.Treasury.SameChar(e.from, name) then
			e.paid = (e.paid or 0) + (tonumber(count) or 0)
			if e.paid >= e.n then Bank.Answer(key, "done") end
			return
		end
	end
end

-- While the King shows the army the book, a keeper's client puts the open requests it holds on the
-- channel next to the bank (TL), when they change and with its book; a list it had put there and
-- that emptied, once more, empty. Once a PUBLIC_GAP at most: a change inside it goes once it ends.
function Bank.SharePublic(force)
	if not CanSend() or not ns.Treasury.PublicShows("book") then return false end
	local now = ns.Now()
	if now - lastPublicAt < Bank.PUBLIC_GAP then
		if not publicPending then
			publicPending = true
			ns.After(Bank.PUBLIC_GAP - (now - lastPublicAt) + 1, "bank list", function()
				publicPending = false
				Bank.SharePublic()
			end)
		end
		return false
	end
	local guild = Clean(GetGuildInfo("player"), 40)
	local entries = {}
	for _, e in ipairs(Bank.Requests()) do
		if Open(e.state) then entries[#entries + 1] = ("%d:%d:%d:%s:%s"):format(e.id, e.item, e.n, Field(e.from, 60), Field(e.guild, 24)) end
	end
	local msgs, cur = {}, ("TL~%s~"):format(guild)
	local head = cur
	for _, entry in ipairs(entries) do
		if #cur + #entry + 1 > 250 then
			if #msgs + 1 >= Bank.PUBLIC_MSGS then break end
			msgs[#msgs + 1] = cur
			cur = head
		end
		cur = cur .. (cur == head and "" or ",") .. entry
	end
	msgs[#msgs + 1] = cur
	local all = table.concat(msgs, "\n")
	-- (None, and none said: nothing. Unchanged: only with the book's repeat, force.)
	if #entries == 0 and (lastPublic == nil or lastPublic == "") then return false end
	if not force and all == lastPublic then return false end
	lastPublic, lastPublicAt = #entries == 0 and "" or all, now
	for i, m in ipairs(msgs) do
		ns.Treasury.SendPublic(m, "banklist" .. i, function() return ns.Treasury.PublicShows("book") end)
	end
	return true
end

-- A keeper's open requests (TL), on the channel, from a keeper alone: his list replaces his last.
function Bank.HandlePublic(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" then return end
	local guild, rest = text:match("^TL~([^~]*)~([^~]*)$")
	if not guild or not ns.Treasury.IsKeeperName(sender, guild) then return end
	sender = ns.FullName(sender)
	local list, x = {}, publicLists[sender]
	-- (His list in two messages at most: a first one starts it again, a second one adds to it.)
	if x and ns.Now() - x.t < 5 then list = x.list end
	for entry in rest:gmatch("[^,]+") do
		local id, item, n, from, g = entry:match("^(%d+):(%d+):(%d+):([^:]+):([^:]*)$")
		local who, gl = ns.King.CleanName(from), ns.King.CleanGuild(g)
		id, item, n = tonumber(id), tonumber(item), tonumber(n)
		if id and item and n and n >= 1 and n <= Bank.REQUEST_MAX_COUNT and who and gl and #list < 20 then
			list[#list + 1] = { id = id, item = item, n = n, from = ns.FullName(who, ns.RealmOf(from)), guild = gl }
		end
	end
	publicLists[sender] = { t = ns.Now(), list = list }
	Fire()
end
ns.Comm.Handle("TL", function(...) Bank.HandlePublic(...) end)

-- How many of an item the bank holds (the snapshot shown), or nil without one.
function Bank.Holds(item)
	local b = Bank.Current()
	if not b then return nil end
	local n = 0
	for _, tab in ipairs(b.tabs or {}) do
		for _, it in ipairs(tab.items or {}) do if it.id == item then n = n + (tonumber(it.n) or 0) end end
	end
	return n
end

-- The count asked for an item (a click on it in the bank's grid), or for any item (typed).
StaticPopupDialogs["OLYMPUS_BANK_REQUEST"] = {
	text = L.BANK_REQUEST_PROMPT,
	button1 = L.BANK_REQUEST_ASK,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 80,
	maxLetters = 4,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("1"); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("bank request", Bank.Request, data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self, data)
		ns.SafeCall("bank request", Bank.Request, data, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_BANK_REQUEST_ANY"] = {
	text = L.BANK_REQUEST_ANY_PROMPT,
	button1 = L.BANK_REQUEST_ASK,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 200,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("bank request", Bank.RequestText, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("bank request", Bank.RequestText, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
-- A keeper (the King, a Steward): done (handed over by trade or mail) or declined.
StaticPopupDialogs["OLYMPUS_BANK_REQUEST_ANSWER"] = {
	text = L.BANK_REQUEST_ANSWER,
	button1 = L.BANK_REQUEST_MARK_DONE,
	button2 = CANCEL or "Cancel",
	button3 = L.BANK_REQUEST_MARK_DECLINED,
	OnAccept = function(self, data) ns.SafeCall("bank request", Bank.Answer, data or (self and self.data), "done") end,
	OnAlt = function(self, data) ns.SafeCall("bank request", Bank.Answer, data or (self and self.data), "declined") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_BANK_REQUEST_CANCEL"] = {
	text = L.BANK_REQUEST_CANCEL_ASK,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data) ns.SafeCall("bank request", Bank.Cancel, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
function Bank.RequestPrompt(item)
	if not Bank.MayRequest() then return ns.Print(L.BANK_REQUEST_ONLY) end
	if item then return ns.ShowDialog("OLYMPUS_BANK_REQUEST", Label(item), nil, item) end
	ns.ShowDialog("OLYMPUS_BANK_REQUEST_ANY")
end

-- /oly need <count> <item>, or alone: our requests in the chat.
function Bank.Slash(rest)
	rest = tostring(rest or "")
	if rest:match("%S") then return Bank.RequestText(rest) end
	ns.Print(L.HELP_NEED)
	for _, e in ipairs(Bank.MyRequests()) do
		ns.Print(L.BANK_REQUEST_LINE:format(Label(e.item, e.n), Bank.StateText(e)))
	end
end

-- Where our request stands, as its line says it.
function Bank.StateText(e)
	local by = e.by and ns.DisplayName(e.by) or "?"
	if e.state == "done" then return L.BANK_REQUEST_STATE_DONE:format(by) end
	if e.state == "declined" then return L.BANK_REQUEST_STATE_DECLINED:format(by) end
	if e.state == "cancel" or e.state == "cancelled" then return L.BANK_REQUEST_STATE_CANCELLED end
	if e.state == "seen" then return L.BANK_REQUEST_STATE_SEEN:format(by) end
	return L.BANK_REQUEST_STATE_SENT
end

ns.On("LOGIN", function()
	-- Our open requests again, to the keepers heard since (and every REQUEST_AGAIN).
	ns.Every(60, "bank requests", function() Bank.SendRequests() end)
	ns.Every(300, "guild bank", function()
		GuildGrantSend()
		Bank.ShareOwnGuild()
		Bank.OwnGuildSnapshot()
	end)
end)

-- Tests start from a clean state.
function Bank.Reset()
	open, readPending, lastShare, lastSent = false, false, -math.huge, nil
	ownGuildGrant, ownGuildReport, ownGuildLastAsk, ownGuildLastGrant = nil, nil, -math.huge, -math.huge
	ownGuildGrantPending = false
	wipe(ownGuildReaders)
	firstChange, lastChange, sharePending, openedAt = 0, 0, false, -math.huge
	wipe(queried)
	wipe(sisters); wipe(sisterHeard); wipe(sisterNoTold)
	if ns.db then ns.db.sisterHeard = nil end
	sisterCount, sisterAsked, sisterSeen, sisterLapsed = 0, false, false, false
	wipe(indexed); wipe(foldedNames); wipe(nameMiss); wipe(nameAsked)
	namesSoon = false
	union = { idx = {}, ids = {}, list = {}, total = {} }
	Bank.indexBuilds, Bank.unionBuilds = 0, 0
	wipe(lastAsked); wipe(publicLists)
	lastPublic, lastPublicAt, publicPending = nil, -math.huge, false
	if ns.rdb then ns.rdb.bank, ns.rdb.bankReport, ns.rdb.bankPrev, ns.rdb.bankReportPrev = nil, nil, nil, nil end
	if ns.rdb then ns.rdb.bankAsks, ns.rdb.bankRequests = nil, nil end
end
function Bank.SetOpenForTest(on, tabs) open = on; wipe(queried); for _, t in ipairs(tabs or {}) do queried[t] = true end end
