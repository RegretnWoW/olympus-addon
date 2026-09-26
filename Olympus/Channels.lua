local ADDON, ns = ...
local L = ns.L

-- Chat channels of the federation, carried as M1 messages on the hidden Olympus channel:
--   [Olympus]  /ol   every member of every Olympus guild
--   [Captains] /olc  rank 0-1 of any Olympus guild
--   [Lords]    /oll  the Crown: guild masters and the officers of <Olympus>
-- Higher ranks also use the channels below theirs. Every addon client receives every line
-- (nothing is encrypted): each client shows a line only when its own rank is high enough
-- and the sender's rank is verified, never taken from the message. No WoW channel number.

local Channels = {}
ns.Channels = Channels
local Codec = ns.Codec

local SEND_GAP = 1.5             -- we send at most one line every 1.5 s
local BUCKET_SIZE = 6            -- per sender: a burst of 6 parts, then one every 1.2 s
local BUCKET_REFILL = 1.2        -- (an unmodified client never goes faster than that)
local MAX_SHOWN_PER_MINUTE = 60  -- flood guard per channel
local FAIR_SHARE = 10            -- once a channel is half full, no sender gets more lines than this a minute
local DEDUPE_WINDOW = 120
local HISTORY = 100              -- lines kept per channel
local LOG_GAP = 60               -- at most one "dropped" log line per sender per minute
local NOTICE_GAP = 60            -- at most one flood guard notice a minute...
local NOTICE_WAIT = 10           -- ...a few seconds after the first line held, to count the burst

-- Gold, teal and royal purple: none of them is a colour Blizzard's chat already uses.
local TIERS = {
	A = { level = 1, label = "CHAN_ALL",      slash = "/ol",  word = "olympus",  deny = "MEMBERS_ONLY",       color = { 0.90, 0.77, 0.36 } },
	C = { level = 2, label = "CHAN_CAPTAINS", slash = "/olc", word = "captains", deny = "CHAN_ONLY_CAPTAINS", color = { 0.35, 0.85, 0.85 } },
	L = { level = 3, label = "CHAN_LORDS",    slash = "/oll", word = "lords",    deny = "CHAN_ONLY_LORDS",    color = { 0.75, 0.50, 1.00 } },
}
Channels.TIERS, Channels.ORDER = TIERS, { "A", "C", "L" }
Channels.HISTORY = HISTORY

local stats = { sent = 0, shown = 0, hidden = 0, bad = 0, dup = 0, rate = 0, flood = 0, forged = 0, unverified = 0, rank = 0, ignored = 0 }
local seen = {}      -- "sender#id#text" -> time: every part is shown once
local buckets = {}   -- sender -> { tokens, t }
local recent = {}    -- tier -> { { t, sender } } of the lines shown in the last minute
local lastLog = {}   -- sender -> time of the last drop we logged
local lastSend = -math.huge
local mine = {}      -- "id#text" -> time: our own lines, shown when sent (their echo is not shown again)
local nextId = math.random(0, 9999)
local held = {}      -- tier -> lines the flood guard kept off the chat since its last notice
local heldSince      -- when the first of them was held
local lastNotice = -math.huge
local noticeTimer = false
local gone = {}      -- chosen window name (lower case) -> true once we said it is gone

local function Label(tier)
	return L[TIERS[tier].label]
end

local function Muted()
	ns.db.chatMute = ns.db.chatMute or {}
	return ns.db.chatMute
end

-- The channels whose warning the player accepted before their first line there. Account-wide.
local function Warned()
	ns.db.chatWarned = ns.db.chatWarned or {}
	return ns.db.chatWarned
end

-- History is per realm, like the census.
local function Store(tier)
	ns.rdb.chat = ns.rdb.chat or {}
	local list = ns.rdb.chat[tier]
	if not list then
		list = {}
		ns.rdb.chat[tier] = list
	end
	return list
end

local function NextId()
	nextId = (nextId + 1) % 10000
	return nextId
end

---------------------------------------------------------------------------
-- Who may read and write what. Levels: 0 outside Olympus, 1 member, 2 Captain, 3 Lord.
---------------------------------------------------------------------------

function Channels.LevelOf(guild, rankIndex)
	if not ns.IsFederation(guild) then return 0 end
	-- To keep [Lords] for guild masters only, use rankIndex == 0 here instead of the Crown.
	if rankIndex and ns.IsCrownRank(guild, rankIndex) then return 3 end
	if rankIndex and rankIndex <= ns.CAPTAIN_RANK then return 2 end
	return 1
end

-- Our own rank always comes from the server.
function Channels.MyLevel()
	if not ns.IsMember() then return 0 end
	return Channels.LevelOf(GetGuildInfo("player"), ns.Roster.MyRank())
end

function Channels.CanUse(tier)
	local t = TIERS[tier]
	return t ~= nil and Channels.MyLevel() >= t.level
end

-- The level a sender really has, and whether it was verified. Our own guild: from our
-- roster. Other guilds: from that guild's fresh report (leader or officer), and a sender
-- speaks for one guild only (Data.ClaimGuild). Returns 0 when the guild claim is false.
function Channels.VerifiedLevel(sender, guild)
	local who = ns.FullName(sender)
	local rank = ns.Roster.RankOf(who)
	local mine = GetGuildInfo("player")
	if mine and guild:lower() == mine:lower() then
		if guild ~= mine then return 0, false end -- our name spelled another way (names ignore case)
		if rank then return Channels.LevelOf(guild, rank), true end
		if ns.Roster.byName == nil then return 1, false end -- roster not read yet
		return 0, false -- not in our roster: not one of us
	end
	if rank then return 0, false end -- a guildmate of ours speaking for another guild
	if not ns.Data.ClaimGuild(who, guild) then return 0, false end
	local known = ns.Data.KnownRank(who, guild)
	if known == nil then return 1, false end
	return Channels.LevelOf(guild, known), true
end

---------------------------------------------------------------------------
-- Display and history
---------------------------------------------------------------------------

-- "[Captains] [Name] <Guild>: text". The name is a player link, like in any chat line, so a
-- click opens the usual whisper and menu (to the name the server finds, ns.TellName). The
-- text is sanitized again here: history comes from the SavedVariables too.
function Channels.FormatLine(tier, sender, guild, class, text)
	local name = ns.DisplayName(sender) or "?"
	local file = class and ns.CLASS_FILES[class]
	local color = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	if color and color.colorStr then name = "|c" .. color.colorStr .. name .. "|r" end
	-- The High Council (the moderators, Core.lua): a skull and their colour.
	if ns.IsHighCouncillor(sender) then name = ns.HIGH_COUNCIL_ICON .. "|c" .. ns.HIGH_COUNCIL_COLOR .. ns.DisplayName(sender) .. "|r" end
	return "[" .. Label(tier) .. "] |Hplayer:" .. (ns.TellName(sender) or "?") .. "|h[" .. name .. "]|h <"
		.. tostring(guild or "?"):gsub("|", "||") .. ">: " .. Codec.SanitizeChat(text)
end

---------------------------------------------------------------------------
-- The chat window each channel shows in (/oly chatwindow). Output only: Olympus adds its lines
-- to the window the player chose as it adds them to the main one, and never touches a window's
-- edit box, tabs or dock. (Replacing the chat box's scripts, or opening a window from addon
-- code, runs Blizzard's chat code tainted: /cast, /use or /target typed there get blocked.)
-- The player makes the tab in the game and picks it here. The choice is the window's name, per
-- character like the game's own chat windows, looked up each time a line is shown: a window
-- closed or renamed sends its lines back to the main window, with one notice. (Checking the
-- window at print time and falling back to the main one comes from RoyLeviGit's pull request
-- #20, "native chat tabs".)
---------------------------------------------------------------------------

local function MaxWindows()
	local c = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows
	return tonumber(NUM_CHAT_WINDOWS) or tonumber(c) or 10
end

-- Chat window i: its frame, its name, whether it is open (shown, or docked behind another tab:
-- the game counts a docked tab not selected as not shown) and whether it is the combat log,
-- which clears and refills itself (a line of ours there would vanish).
local function WindowAt(i)
	local f = _G["ChatFrame" .. i]
	if type(f) ~= "table" or type(f.AddMessage) ~= "function" then return nil end
	local info = GetChatWindowInfo or FCF_GetChatWindowInfo
	local name, shown
	if type(info) == "function" then
		local ok, n, _, _, _, _, _, s = pcall(info, i)
		if ok then name, shown = n, s end
	end
	if type(name) ~= "string" or name == "" then name = type(f.name) == "string" and f.name ~= "" and f.name or nil end
	local combat = false
	if type(IsCombatLog) == "function" then
		local ok, res = pcall(IsCombatLog, f)
		combat = ok and res and true or false
	end
	return f, name, (shown or f.isDocked) and true or false, combat
end

-- The open chat window called `name` (in any case): its frame, number and name as the game has it.
function Channels.FindWindow(name)
	if type(name) ~= "string" or name == "" then return nil end
	local want = name:lower()
	for i = 1, MaxWindows() do
		local f, wname, open, combat = WindowAt(i)
		if f and open and not combat and wname and wname:lower() == want then return f, i, wname end
	end
	return nil
end

local function Quoted(name)
	return '"' .. tostring(name):gsub("|", "||") .. '"'
end

-- This character's choices: tier -> window name.
local function Chosen()
	local all = ns.db and ns.db.chatWindows
	local list = type(all) == "table" and ns.me and all[ns.me]
	return type(list) == "table" and list or nil
end

-- The frame a channel's lines go to: its chosen window while it is open, else the main one.
function Channels.Frame(tier)
	local chosen = Chosen()
	local name = chosen and chosen[tier]
	if type(name) == "string" then
		local f = Channels.FindWindow(name)
		local key = name:lower()
		if f then
			gone[key] = nil
			return f
		end
		if not gone[key] then
			gone[key] = true
			ns.Print(L.CHATWIN_GONE:format(Quoted(name)))
		end
	end
	return DEFAULT_CHAT_FRAME
end

-- A line of ours ("Olympus: ...") in frame f, what ns.Print writes in the main window.
local function Say(f, msg)
	if not f or f == DEFAULT_CHAT_FRAME then return ns.Print(msg) end
	f:AddMessage("|c" .. ns.COLOR .. "Olympus:|r " .. tostring(msg))
end

-- "[Olympus] main window, [Captains] "Olympus"" for /oly chatwindow and /oly status.
function Channels.WindowStatus()
	local chosen = Chosen() or {}
	local parts = {}
	for _, tier in ipairs(Channels.ORDER) do
		local name = chosen[tier]
		local where = L.CHATWIN_MAIN_NAME
		if type(name) == "string" then
			where = Quoted(name) .. (Channels.FindWindow(name) and "" or " " .. L.CHATWIN_GONE_TAG)
		end
		parts[#parts + 1] = "[" .. Label(tier) .. "] " .. where
	end
	return table.concat(parts, ", ")
end

-- A window by number or by name: frame, name, or nil and why ("combat").
local function PickWindow(word)
	local n = tonumber(word)
	if n and n == math.floor(n) and n >= 1 and n <= MaxWindows() then
		local f, name, open, combat = WindowAt(n)
		if f and open and name then
			if combat then return nil, nil, "combat" end
			return f, name
		end
		return nil
	end
	local f, _, name = Channels.FindWindow(word)
	if f then return f, name end
	-- (The combat log is left out of FindWindow: say why rather than "not found".)
	for k = 1, MaxWindows() do
		local cf, cname, open, combat = WindowAt(k)
		if cf and open and combat and cname and cname:lower() == tostring(word):lower() then return nil, nil, "combat" end
	end
	return nil
end

local MAIN_WORDS = { main = true, default = true, principal = true }
local ALL_WORDS = { all = true, todos = true }

-- /oly chatwindow <number | name | main> [olympus | captains | lords]
function Channels.ChooseWindow(input)
	input = tostring(input or ""):match("^%s*(.-)%s*$")
	if input == "" then
		ns.Print(L.CHATWIN_NOW:format(Channels.WindowStatus()))
		ns.Print(L.CHATWIN_USAGE)
		return false
	end
	if not ns.me then return false end
	-- The whole text first (a window may be called "Olympus Lords"), then a channel at its end.
	local target, tiers = input, Channels.ORDER
	if not MAIN_WORDS[input:lower()] and not PickWindow(input) then
		local head, last = input:match("^(.-)%s+(%S+)$")
		if head and head ~= "" then
			if ALL_WORDS[last:lower()] then
				target = head
			elseif Channels.TierForWord(last) then
				target, tiers = head, { Channels.TierForWord(last) }
			end
		end
	end
	local f, name, why
	if not MAIN_WORDS[target:lower()] then
		f, name, why = PickWindow(target)
		if not f then
			if why == "combat" then
				ns.Print(L.CHATWIN_COMBATLOG)
			else
				local open = {}
				for i = 1, MaxWindows() do
					local wf, wname, isOpen, combat = WindowAt(i)
					if wf and isOpen and not combat and wname then open[#open + 1] = i .. " " .. Quoted(wname) end
				end
				local menu = type(NEW_CHAT_WINDOW) == "string" and NEW_CHAT_WINDOW ~= "" and NEW_CHAT_WINDOW or L.CHATWIN_NEW
				ns.Print(L.CHATWIN_NOT_FOUND:format(Quoted(target), #open > 0 and table.concat(open, ", ") or "-", menu))
			end
			return false
		end
		if f == DEFAULT_CHAT_FRAME then name = nil end -- the main window: nothing to remember
	end
	ns.db.chatWindows = type(ns.db.chatWindows) == "table" and ns.db.chatWindows or {}
	local list = type(ns.db.chatWindows[ns.me]) == "table" and ns.db.chatWindows[ns.me] or {}
	ns.db.chatWindows[ns.me] = list
	local labels = {}
	for _, tier in ipairs(tiers) do
		list[tier] = name
		labels[#labels + 1] = "[" .. Label(tier) .. "]"
	end
	if next(list) == nil then ns.db.chatWindows[ns.me] = nil end
	if next(ns.db.chatWindows) == nil then ns.db.chatWindows = nil end
	wipe(gone)
	if not name then
		ns.Print(L.CHATWIN_MAIN:format(table.concat(labels, ", ")))
		return true
	end
	local msg = L.CHATWIN_SET:format(table.concat(labels, ", "), Quoted(name))
	ns.Print(msg)
	Say(f, msg) -- and in that window, to show where they land
	return true
end

-- A plain AddMessage on the channel's chat window (what print does on the main one): nothing
-- of Blizzard's is replaced or hooked.
local function Show(tier, sender, guild, class, text)
	local f = Channels.Frame(tier)
	if not f then return end
	local c = TIERS[tier].color
	f:AddMessage(Channels.FormatLine(tier, sender, guild, class, text), c[1], c[2], c[3])
end

local function AddHistory(tier, e)
	local list = Store(tier)
	list[#list + 1] = { t = ns.Now(), sender = e.sender, guild = e.guild, class = e.class, text = e.text, mine = e.mine }
	while #list > HISTORY do table.remove(list, 1) end
end

local function Accept(tier, sender, guild, class, text, mine)
	AddHistory(tier, { sender = sender, guild = guild, class = class, text = text, mine = mine or nil })
	ns.Fire("CHAT_CHANGED", tier)
	if Muted()[tier] then return false, "muted" end
	Show(tier, sender, guild, class, text)
	stats.shown = stats.shown + 1
	return true, "ok"
end

-- The lines of a channel we may read (for a future Channels view, with CHAT_CHANGED).
function Channels.History(tier)
	if not Channels.CanUse(tier) then return {} end
	return Store(tier)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

-- Returns ok, reason. Every refusal tells the player why.
function Channels.Send(tier, text, now)
	local t = TIERS[tier]
	if not t then return false, "tier" end
	if not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return false, "member"
	end
	if not Channels.CanUse(tier) then
		ns.Print(L[t.deny]:format(Label(tier)))
		return false, "rank"
	end
	text = Codec.SanitizeChat(text)
	if text == "" then
		ns.Print(L.CHAN_USAGE:format(t.slash, Label(tier)))
		return false, "empty"
	end
	if Locked() then
		ns.Print(L.CHAN_LOCKDOWN)
		return false, "lockdown"
	end
	now = now or GetTime()
	if now - lastSend < SEND_GAP then
		ns.Print(L.CHAN_TOO_FAST)
		return false, "fast"
	end
	if not ns.Comm.ChannelReady() then
		ns.Print(L.CHAN_NOT_READY)
		return false, "ready"
	end
	-- The first line in each channel waits for the player's OK: nothing is private there, and
	-- they are told so before anything leaves (Channels.Confirm sends it).
	if not Warned()[tier] then
		ns.ShowDialog("OLYMPUS_CHAT_PRIVACY", Label(tier), ns.Comm.Audience(), { tier = tier, text = text })
		return false, "confirm"
	end
	local guild = GetGuildInfo("player")
	local class = ns.Roster.ClassCode(UnitClass and select(2, UnitClass("player")))
	-- Classes without a 2 letter code travel without a class (the decoder only takes 2 letters).
	if not class:match("^%u%u$") then class = "" end
	local parts, cut = Codec.SplitChat(text, Codec.ChatBudget(guild, class), Codec.CHAT_PARTS)
	if ns.Comm.ChatRoom() < #parts then
		ns.Print(L.CHAN_BUSY)
		return false, "busy"
	end
	if cut then ns.Print(L.CHAN_TRUNCATED) end
	if Muted()[tier] then
		Muted()[tier] = nil
		ns.Print(L.CHAN_UNMUTED:format(Label(tier)))
	end
	lastSend = now
	local failed = false
	for _, part in ipairs(parts) do
		local function done(sent)
			if not sent then
				if not failed then ns.Print(L.CHAN_SEND_FAILED:format(Label(tier))) end
				failed = true
				return
			end
			stats.sent = stats.sent + 1
			Accept(tier, ns.me, guild, class ~= "" and class or nil, part, true) -- our echo: exactly what the others see
		end
		local id = NextId()
		-- Kept a while: when this line comes back from the channel it is ours, whatever form
		-- the server gave our name in (a line shown twice to its author otherwise).
		mine[id .. "#" .. Codec.SanitizeChat(part)] = now
		local msg = Codec.EncodeChat(tier, guild, id, class, part)
		if not msg or ns.Comm.SendChat(msg, done) == false then done(false) end
	end
	return true, "ok"
end

-- The warning's answer, with the line it held (with the gamepad UI too: it rides in the
-- window's data). Send: that channel counts as warned and the line goes through Channels.Send
-- again, every check with it. Cancel, Escape or another window taking its place: not sent.
function Channels.Confirm(data, send)
	if type(data) ~= "table" or not TIERS[data.tier] or data.answered then return end
	data.answered = true
	if not send then
		ns.Print(L.CHAN_WARN_NOT_SENT)
		return
	end
	Warned()[data.tier] = true
	return Channels.Send(data.tier, data.text)
end

StaticPopupDialogs["OLYMPUS_CHAT_PRIVACY"] = {
	text = L.CHAN_WARN_ASK,
	button1 = SEND_LABEL or "Send",
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("chat warning", Channels.Confirm, data or (self and self.data), true) end,
	OnCancel = function(self, data) ns.SafeCall("chat warning", Channels.Confirm, data or (self and self.data), false) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function LogDrop(sender, m, reason, now)
	if lastLog[sender] and now - lastLog[sender] < LOG_GAP then return end
	lastLog[sender] = now
	ns.Log("chat [%s] from %s <%s> dropped: %s", m.tier, sender, m.guild, reason)
end

local function Ignored(sender)
	local api = C_FriendList and C_FriendList.IsIgnored
	if not api then return false end
	local ok, res = pcall(api, ns.DisplayName(sender))
	return ok and res == true
end

-- Flood guard per channel, so [Olympus] traffic never silences [Captains] or [Lords]. Once a
-- channel is half full, a sender who already had FAIR_SHARE lines in it waits: one or two
-- spammers can't take the whole minute from everyone else.
local function Flooded(tier, sender, now)
	local list = recent[tier] or {}
	recent[tier] = list
	local mine = 0
	for i = #list, 1, -1 do
		if now - list[i].t > 60 then
			table.remove(list, i)
		elseif list[i].sender == sender then
			mine = mine + 1
		end
	end
	if #list >= MAX_SHOWN_PER_MINUTE or (#list >= MAX_SHOWN_PER_MINUTE / 2 and mine >= FAIR_SHARE) then return true end
	list[#list + 1] = { t = now, sender = sender }
	return false
end

-- What the flood guard kept off the chat is said, never silent: at most one line a minute,
-- "[Olympus] 12, [Captains] 3", where most of those lines would have shown, telling where they
-- are and how many lines the history keeps. Called on each line held, by a timer once the
-- notice is due, and by the housekeeping. Returns true when it printed.
function Channels.FloodNotice(now)
	now = now or GetTime()
	if not heldSince then return false end
	local due = math.max(heldSince + NOTICE_WAIT, lastNotice + NOTICE_GAP)
	if now < due then
		if not noticeTimer then
			noticeTimer = true
			ns.After(due - now + 0.1, "flood notice", function()
				Channels.FloodNotice()
				noticeTimer = false
			end)
		end
		return false
	end
	local parts, most, where = {}, 0, nil
	for _, tier in ipairs(Channels.ORDER) do
		local n = held[tier]
		if n then
			parts[#parts + 1] = "[" .. Label(tier) .. "] " .. n
			if n > most then most, where = n, tier end
		end
	end
	wipe(held)
	heldSince, lastNotice = nil, now
	if not where then return false end
	Say(Channels.Frame(where), L.CHAN_FLOOD_NOTICE:format(table.concat(parts, ", "), HISTORY))
	return true
end

local function Held(tier, now)
	held[tier] = (held[tier] or 0) + 1
	heldSince = heldSince or now
	Channels.FloodNotice(now)
end

-- Returns shown, reason.
function Channels.Receive(dist, sender, text, now)
	if dist ~= "CHANNEL" then return false, "dist" end
	now = now or GetTime()
	sender = ns.FullName(sender)
	local m = Codec.DecodeChat(text)
	if not m or not ns.IsFederation(m.guild) then
		stats.bad = stats.bad + 1
		return false, "bad"
	end
	local level = TIERS[m.tier].level
	-- Above our rank: not shown, not kept, not logged.
	if Channels.MyLevel() < level then
		stats.hidden = stats.hidden + 1
		return false, "tier"
	end
	if Ignored(sender) then
		stats.ignored = stats.ignored + 1
		return false, "ignored"
	end
	-- The server stamps the sender, so this key can't be forged. The text is part of it: ids
	-- start again at random after a /reload, and a reused id must not hide a new line.
	local key = sender .. "#" .. m.id .. "#" .. m.text
	-- Our own line coming back (already shown when sent): the same id and text, from a name
	-- that is ours however it is written ("First-Surname", "First Surname", with a realm or not).
	local own = mine[m.id .. "#" .. m.text]
	if own and now - own < DEDUPE_WINDOW and Channels.IsMe(sender) then
		stats.dup = stats.dup + 1
		return false, "own"
	end
	if seen[key] and now - seen[key] < DEDUPE_WINDOW then
		stats.dup = stats.dup + 1
		return false, "dup"
	end
	seen[key] = now
	local b = buckets[sender]
	if not b then
		b = { tokens = BUCKET_SIZE, t = now }
		buckets[sender] = b
	end
	b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.t) / BUCKET_REFILL)
	b.t = now
	if b.tokens + 1e-6 < 1 then -- (tolerance: a sender exactly on time must not lose to rounding)
		stats.rate = stats.rate + 1
		LogDrop(sender, m, "rate", now)
		return false, "rate"
	end
	b.tokens = b.tokens - 1
	local have, verified = Channels.VerifiedLevel(sender, m.guild)
	if have < level then
		local reason = have == 0 and "forged" or (verified and "rank" or "unverified")
		stats[reason] = stats[reason] + 1
		LogDrop(sender, m, reason, now)
		return false, reason
	end
	-- A muted channel only goes to history, so it takes nothing from the flood guard. A line
	-- the guard keeps off the chat frame still goes to the history (the Realm tab's chats stay
	-- whole for everyone), and the player is told (Channels.FloodNotice).
	if not Muted()[m.tier] and Flooded(m.tier, sender, now) then
		stats.flood = stats.flood + 1
		AddHistory(m.tier, { sender = sender, guild = m.guild, class = m.class, text = m.text })
		ns.Fire("CHAT_CHANGED", m.tier)
		Held(m.tier, now)
		return false, "flood"
	end
	return Accept(m.tier, sender, m.guild, m.class, m.text, false)
end

-- Our name however the server writes it: lower case, our realm left out (a namesake on a
-- connected realm is another player), a hyphen between first name and surname read as the
-- space it stands for ("Faladori Elskylance" stays another).
local function Letters(name)
	name = tostring(name or "")
	local base, realm = name:match("^(.+)%-([^%-]+)$")
	if realm and (realm == ns.realm or realm == ns.CurrentRealm()) then name = base end
	name = name:lower():gsub("'", ""):gsub("[%s%-]+", " ")
	return (name:match("^%s*(.-)%s*$"))
end
function Channels.IsMe(sender)
	if not ns.me or not sender then return false end
	return sender == ns.me or Letters(ns.Normal(sender)) == Letters(ns.me)
end

-- Players' text must come through the logged API (the server keeps it, so abuse can be
-- reported): a line sent with the plain one is dropped, where the client has both.
ns.Comm.Handle("M1", function(dist, sender, text)
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.unlogged = (stats.unlogged or 0) + 1
		return
	end
	Channels.Receive(dist, sender, text)
end)

---------------------------------------------------------------------------
-- Mute, housekeeping, commands
---------------------------------------------------------------------------

local WORDS = {
	all = "A", a = "A", olympus = "A", todos = "A",
	captains = "C", captain = "C", c = "C", capitaes = "C", ["capitães"] = "C",
	lords = "L", lord = "L", l = "L", lordes = "L",
}
function Channels.TierForWord(w)
	return WORDS[(tostring(w or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))]
end

-- A muted channel stays out of chat but keeps its history. Account-wide.
function Channels.ToggleMute(word)
	local tier = Channels.TierForWord(word)
	if not tier then
		ns.Print(L.CHAN_MUTE_USAGE)
		return
	end
	local muted = Muted()
	if muted[tier] then
		muted[tier] = nil
		ns.Print(L.CHAN_UNMUTED:format(Label(tier)))
	else
		muted[tier] = true
		ns.Print(L.CHAN_MUTED:format(Label(tier), TIERS[tier].word))
	end
end

function Channels.Prune(now)
	now = now or GetTime()
	local n = 0
	for k, t in pairs(seen) do
		if now - t > DEDUPE_WINDOW then seen[k] = nil else n = n + 1 end
	end
	if n > 1000 then wipe(seen) end
	for k, t in pairs(mine) do
		if now - t > DEDUPE_WINDOW then mine[k] = nil end
	end
	for k, b in pairs(buckets) do
		if now - b.t > 60 then buckets[k] = nil end
	end
	for k, t in pairs(lastLog) do
		if now - t > LOG_GAP then lastLog[k] = nil end
	end
	Channels.FloodNotice(now) -- (in case its timer never came)
end

function Channels.Stats()
	local out = {}
	for k, v in pairs(stats) do out[k] = v end
	local muted, warned = {}, {}
	for _, tier in ipairs(Channels.ORDER) do
		if Muted()[tier] then muted[#muted + 1] = tier end
		if Warned()[tier] then warned[#warned + 1] = tier end
	end
	out.muted, out.warned = muted, warned
	return out
end

ns.On("INIT", function()
	-- (0.9.1: the warning comes before the first line in each channel, Channels.Confirm.)
	ns.db.chatNoticeShown = nil
	local chat = ns.rdb.chat
	if chat == nil then return end
	if type(chat) ~= "table" then
		ns.rdb.chat = nil
		return
	end
	for tier, list in pairs(chat) do
		if not TIERS[tier] or type(list) ~= "table" then
			chat[tier] = nil
		else
			while #list > HISTORY do table.remove(list, 1) end
		end
	end
end)

ns.On("LOGIN", function()
	ns.Every(60, "chat housekeeping", Channels.Prune)
end)

SLASH_OLYMPUSALL1, SLASH_OLYMPUSCAPTAINS1, SLASH_OLYMPUSLORDS1 = "/ol", "/olc", "/oll"
SlashCmdList.OLYMPUSALL = function(msg) ns.SafeCall("slash /ol", Channels.Send, "A", msg) end
SlashCmdList.OLYMPUSCAPTAINS = function(msg) ns.SafeCall("slash /olc", Channels.Send, "C", msg) end
SlashCmdList.OLYMPUSLORDS = function(msg) ns.SafeCall("slash /oll", Channels.Send, "L", msg) end
