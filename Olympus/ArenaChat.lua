local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaChat.lua. A stub the arena's core created for the screens (UI and test) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Fight rooms (EC, EM) through a shared Channels.Admit. Registers EC EM; /ola goes through
-- Arena.RunSlash("say ...") (Core.lua).
-- API (the design): Open(room), Send(room, text), Lines(room), Mute(room, name, on), MayWrite(room, name)
local ArenaChat = {}
ns.ArenaChat = ArenaChat

local L = ns.L

-- One room per event (the design): its id is the event's (a fight, a card, a
-- tournament, a Farkle table), and it lives in memory only (10 rooms of 100 lines, dropped 30
-- minutes after the event ended). Nothing is encrypted: anyone on the lane receives the bytes, as
-- for the Olympus chats (Channels.lua). What this client does with them:
-- - Who may write, checked by every receiver against the name the server stamps: a public room,
--   any verified member of an Olympus guild (level 2 or more while a bout of it is live); a 1v1
--   room (a private or direct fight, a Farkle table), its two players and its arbiter only. The
--   sender's own client refuses before the rules' yes, while net-off, and while the room is not
--   open there (the player opened it, or takes part in the event).
-- - A line shows only in a room open on this client, through Channels.Admit (the Olympus chats'
--   own checks, one code: net-off, ignore list, duplicates, a rate bucket per sender, the
--   sender's verified rank, the block terms), and never from a name the room's arbiter muted
--   (EM). A line not delivered with the logged API is dropped, as M1's is.
-- - Slow mode on the sender's side: each client keeps its own gap between two lines at
--   max(1.5 s, the room's active writers x 1 s), and 6 lines a minute at most, so a busy room stays
--   near 60 lines a minute in all.
-- - The text goes as plain text: a link typed in a room goes out as its bracketed name (Comm strips
--   every "|" from anything but M1), 180 bytes at most.
-- Wire (the whole message 255 bytes at most, never in pieces):
--   EC~<M>1~room~line~class2~guild~text   (the guild the sender speaks for: Channels.Admit checks
--                                           his rank in it, as M1 carries it)
--   EM~<M>1~room~Name-Realm~1|0           (the room's arbiter, or the card's promoter)
-- Lanes: a public room on the event's public lane (the channel's chat lane, logged; the group in a
-- group rehearsal), a 1v1 room by whisper (logged) to the other two.

ArenaChat.ROOMS_MAX = 10
ArenaChat.LINES_MAX = 100
ArenaChat.TEXT_MAX = 180
ArenaChat.KEEP_AFTER = 1800   -- a room is dropped this long after its event ended
ArenaChat.GAP_MIN = 1.5       -- seconds between two of our lines, at least...
ArenaChat.GAP_PER_WRITER = 1  -- ...and one per writer heard in the room in the last minute
ArenaChat.PER_MINUTE = 6      -- our lines a minute in one room, at most
ArenaChat.FLOOD = 60          -- lines a minute a room shows, at most (the rest: a notice)
ArenaChat.WRITER_WINDOW = 60

local rooms = {}   -- [room] = the room (below)
local current      -- the room /ola speaks in (the last one opened)
local nextLine = math.random and math.random(0, 9999) or 0

local function Now() return GetTime and GetTime() or ns.Now() end
local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or "" end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Lower(a) == Lower(b) end

-- The event behind a room (Arena.EventOf: a fight, a card, a tournament, a Farkle table), or nil.
local function Event(room)
	local A = ns.Arena
	if type(room) ~= "string" or not A or not A.EventOf then return nil end
	return A.EventOf(room)
end
ArenaChat.Event = Event

-- Its state letter where the event's owner gives one (ev.state, or the fight's own st).
local function State(room, ev)
	if type(ev) == "table" and type(ev.state) == "string" then return ev.state end
	local F = ns.ArenaFights
	if type(F) == "table" and type(F.Fight) == "function" then
		local ok, f = pcall(F.Fight, room)
		if ok and type(f) == "table" then return f.st or f.state end
	end
	return nil
end
local OVER = { F = true, V = true, N = true, W = true, over = true, done = true }
local function Over(room, ev) return (type(ev) == "table" and ev.over == true) or OVER[State(room, ev) or ""] == true end
local function Live(room, ev) return (type(ev) == "table" and ev.live == true) or State(room, ev) == "L" end

-- The people of a 1v1 room: its two players and its arbiter (the opener, or ev.arbiter).
local function Party(ev)
	local out = {}
	if type(ev) ~= "table" then return out end
	local f = type(ev.fighters) == "table" and ev.fighters or {}
	for _, side in ipairs({ "A", "B" }) do
		local p = f[side]
		local name = type(p) == "table" and p.name or p
		if type(name) == "string" and name ~= "" then out[#out + 1] = ns.FullName(name) end
	end
	for _, who in ipairs({ ev.arbiter, ev.opener }) do
		if type(who) == "string" and who ~= "" then
			local dup = false
			for _, n in ipairs(out) do if Same(n, who) then dup = true end end
			if not dup then out[#out + 1] = ns.FullName(who) end
		end
	end
	return out
end
ArenaChat.Party = Party
local function InParty(ev, name)
	for _, n in ipairs(Party(ev)) do if Same(n, name) then return true end end
	return false
end
-- Whether this client takes part in the event (a player of it, or its arbiter).
function ArenaChat.TakesPart(room)
	local ev = Event(room)
	return ev ~= nil and InParty(ev, ns.me)
end

---------------------------------------------------------------------------
-- Rooms (memory only)
---------------------------------------------------------------------------

local function Prune()
	local now = Now()
	local list = {}
	for id, r in pairs(rooms) do
		local ev = Event(id)
		if not ev then
			r.endedAt = r.endedAt or now
		elseif Over(id, ev) then
			r.endedAt = r.endedAt or now
		else
			r.endedAt = nil
		end
		if r.endedAt and now - r.endedAt >= ArenaChat.KEEP_AFTER then
			rooms[id] = nil
			if current == id then current = nil end
		else
			list[#list + 1] = r
		end
	end
	-- Past the cap: the least recently used go first.
	if #list > ArenaChat.ROOMS_MAX then
		table.sort(list, function(a, b) return (a.used or 0) < (b.used or 0) end)
		for i = 1, #list - ArenaChat.ROOMS_MAX do
			rooms[list[i].id] = nil
			if current == list[i].id then current = nil end
		end
	end
end
ArenaChat.Prune = Prune

local function Room(id, make)
	local r = rooms[id]
	if r or not make then return r end
	r = { id = id, lines = {}, muted = {}, buckets = {}, seen = {}, mine = {}, heard = {}, sent = {}, stats = {}, used = Now() }
	rooms[id] = r
	Prune()
	return rooms[id]
end
ArenaChat.Room = function(id) return rooms[id] end

-- Whether a room shows here: the player opened it, or takes part in its event.
function ArenaChat.IsOpen(room)
	local r = rooms[room]
	if r and r.open then return true end
	return ArenaChat.TakesPart(room)
end

-- Opens a room on this client (the Fight chat button): its lines are taken and shown from now on,
-- and /ola speaks in it. Returns the room, or nil for an event this client does not know.
function ArenaChat.Open(room)
	if not Event(room) then return nil end
	local r = Room(room, true)
	if not r then return nil end
	r.open, r.used = true, Now()
	current = room
	ns.Fire("ARENA_CHAT", room)
	return r
end
function ArenaChat.Close(room)
	local r = rooms[room]
	if r then r.open = nil end
	if current == room then current = nil end
end
function ArenaChat.Current() return current end
function ArenaChat.Rooms()
	local out = {}
	for id in pairs(rooms) do out[#out + 1] = id end
	table.sort(out)
	return out
end

-- The writers heard in a room in the last minute (ourselves included when we wrote).
local function Writers(r, now)
	local n = 0
	for _, t in pairs(r.heard) do
		if now - t <= ArenaChat.WRITER_WINDOW then n = n + 1 end
	end
	return n
end
-- Our own gap in that room now: max(1.5 s, active writers x 1 s).
function ArenaChat.Gap(room)
	local r = rooms[room]
	if not r then return ArenaChat.GAP_MIN end
	return math.max(ArenaChat.GAP_MIN, Writers(r, Now()) * ArenaChat.GAP_PER_WRITER)
end

-- The lines of a room as they show now: a muted name's and a net-off name's leave the view.
function ArenaChat.Lines(room)
	local r = rooms[room]
	if not r then return {} end
	local M = ns.Moderation
	local out = {}
	for _, e in ipairs(r.lines) do
		local hidden = r.muted[Lower(e.sender)] or (M and M.Hides and M.Hides(e.sender, e.guild))
		if not hidden then out[#out + 1] = e end
	end
	return out
end

---------------------------------------------------------------------------
-- Who may write
---------------------------------------------------------------------------

-- Whether `name` may write in `room` (every receiver asks it of the sender the server stamps):
-- public rooms, any member (Channels.Admit checks his verified rank on arrival); 1v1 rooms, the
-- two players and the arbiter. Never a name the room's arbiter muted. Returns ok, why.
function ArenaChat.MayWrite(room, name)
	local ev = Event(room)
	if not ev then return false, "room" end
	local r = rooms[room]
	if r and r.muted[Lower(name)] then return false, "muted" end
	if ev.public == true then return true end
	if InParty(ev, name) then return true end
	return false, "party"
end

-- The sender's own checks before a line leaves (Arena.Can("chat", room)).
local function MaySend(room)
	if not ns.IsMember() then return false, "member" end
	local A = ns.Arena
	if A and A.RulesAccepted and not A.RulesAccepted() then return false, "rules" end
	local M = ns.Moderation
	local off = M and M.SelfOff and M.SelfOff()
	if off then return false, "netoff" end
	-- 1.1.6: a moderator's timeout (WatchChat.lua) covers the fight rooms too (ArenaChat.Send tells why).
	local WC = ns.WatchChat
	if WC and WC.SelfTimeout and WC.SelfTimeout() then return false, "timeout" end
	local ev = Event(room)
	if not ev then return false, "room" end
	if not ArenaChat.IsOpen(room) then return false, "closed" end
	local ok, why = ArenaChat.MayWrite(room, ns.me)
	if not ok then return false, why end
	-- A live bout of a public event: members of level 2 and more only.
	if ev.public == true and Live(room, ev) and ns.Channels and ns.Channels.MyLevel and ns.Channels.MyLevel() < 2 then return false, "level" end
	if A and A.Blocked and A.Blocked() then return false, "blocked" end
	return true
end
ArenaChat.MaySend = MaySend

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- A line as it goes out: a link keeps its bracketed name, every other escape and control byte
-- goes, spaces are folded, cut at TEXT_MAX bytes (never inside a character).
function ArenaChat.Clean(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
	text = text:gsub("|H[^|]*|h(%b[])|h", "%1")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("[|%c]", "")
	text = text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #text > ArenaChat.TEXT_MAX then
		local cut = ArenaChat.TEXT_MAX
		while cut > 1 do
			local b = text:byte(cut + 1)
			if not b or b < 128 or b >= 192 then break end
			cut = cut - 1
		end
		text = text:sub(1, cut):gsub("%s+$", "")
	end
	return text
end

local function ClassCode()
	local R = ns.Roster
	local class = R and R.ClassCode and R.ClassCode(UnitClass and select(2, UnitClass("player"))) or ""
	if type(class) ~= "string" or not class:match("^%u%u$") then class = "" end
	return class
end
local function GuildWord(g) return (tostring(g or ""):gsub("[~|%c]", "")) end

local function Keep(r, e)
	r.lines[#r.lines + 1] = e
	while #r.lines > ArenaChat.LINES_MAX do table.remove(r.lines, 1) end
	r.used = Now()
end
local function AlsoInChat(room, e)
	local ui = ns.db and ns.db.arenaUI
	local chat = type(ui) == "table" and type(ui.chat) == "table" and ui.chat
	if not (chat and chat.alsoInChat == true) or not DEFAULT_CHAT_FRAME then return end
	pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, L.ARENA_CHAT_LINE:format(room, ns.DisplayName(e.sender) or "?", e.text), 0.95, 0.55, 0.45)
end

-- Says a line in a room (the panel's box, /ola). Returns true, or false and why (said to the player).
function ArenaChat.Send(room, text)
	room = room or current
	if not room then
		ns.Print(L.ARENA_CHAT_NO_ROOM)
		return false, "room"
	end
	local A = ns.Arena
	local ok, why = A.Can("chat", room)
	if not ok then
		-- 1.1.6: a moderator's timeout: its own pop-up (who, until when, why).
		local WC = ns.WatchChat
		if why == "timeout" and WC and WC.RefuseSend and WC.RefuseSend() then return false, why end
		local key = "ARENA_CHAT_WHY_" .. tostring(why):upper()
		ns.Print(rawget(L, key) or L.ARENA_CHAT_REFUSED)
		return false, why
	end
	text = ArenaChat.Clean(text)
	if text == "" then return false, "empty" end
	local r = Room(room, true)
	local now = Now()
	local gap = ArenaChat.Gap(room)
	if r.lastSent and now - r.lastSent < gap then
		ns.Print(L.ARENA_CHAT_WAIT:format(math.ceil(gap - (now - r.lastSent))))
		return false, "fast"
	end
	local recent = {}
	for _, t in ipairs(r.sent) do if now - t < 60 then recent[#recent + 1] = t end end
	r.sent = recent
	if #recent >= ArenaChat.PER_MINUTE then
		ns.Print(L.ARENA_CHAT_MINUTE)
		return false, "minute"
	end
	local ev = Event(room)
	local mode = A.Mode(ev)
	nextLine = (nextLine + 1) % 10000
	local guild = GetGuildInfo and GetGuildInfo("player") or ""
	local class = ClassCode()
	local body = ("%s~%d~%s~%s~%s"):format(room, nextLine, class, GuildWord(guild), text)
	local sent
	if ev.public == true then
		sent, why = A.Send("EC", mode, body, { chat = true, logged = true })
	else
		for _, name in ipairs(Party(ev)) do
			if not Same(name, ns.me) then
				local one, w = A.Send("EC", mode, body, { to = name, logged = true })
				sent = sent or one
				why = why or w
			end
		end
	end
	if not sent then
		ns.Print(L.ARENA_CHAT_NOT_SENT)
		return false, why or "send"
	end
	r.lastSent = now
	r.sent[#r.sent + 1] = now
	r.heard[Lower(ns.me)] = now
	r.mine[nextLine .. "#" .. text] = now
	local e = { t = ns.Now(), sender = ns.me, guild = guild, class = class ~= "" and class or nil, text = text, id = nextLine, mine = true }
	Keep(r, e)
	AlsoInChat(room, e)
	ns.Fire("ARENA_CHAT", room)
	return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local stats = { shown = 0, dropped = {} }
local function Drop(why) stats.dropped[why] = (stats.dropped[why] or 0) + 1 return false, why end
function ArenaChat.Stats() return stats end

-- EC: a line of a room. Returns shown, why (the tests read it).
local function OnChat(dist, sender, mode, body)
	local room, id, class, guild, text = ns.Arena.Fields(body, 5)
	if not room or not text then return Drop("shape") end
	id = tonumber(id)
	if not id or id < 0 or id > 9999 or id ~= math.floor(id) then return Drop("shape") end
	if class ~= "" and not class:match("^%u%u$") then return Drop("shape") end
	if guild == "" or not ns.IsFederation(guild) then return Drop("guild") end
	sender = ns.FullName(sender)
	if Same(sender, ns.me) then return Drop("own") end
	local ev = Event(room)
	if not ev then return Drop("room") end
	if ns.Arena.Mode(ev) ~= mode then return Drop("mode") end
	-- A player's words come with the logged API (the server keeps them, so abuse can be reported).
	local C = ns.Comm
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and C.DeliveredLogged and not C.DeliveredLogged() then return Drop("unlogged") end
	-- 1v1 rooms by whisper, public ones on their public lane.
	if ev.public == true and dist == "WHISPER" then return Drop("lane") end
	if ev.public ~= true and dist ~= "WHISPER" then return Drop("lane") end
	if not ArenaChat.IsOpen(room) then return Drop("closed") end
	local ok, why = ArenaChat.MayWrite(room, sender)
	if not ok then return Drop(why) end
	text = ArenaChat.Clean(text)
	if text == "" then return Drop("empty") end
	local r = Room(room, true)
	local level = ev.public == true and (Live(room, ev) and 2 or 1) or 0
	local now = Now()
	local admitted, reason = ns.Channels.Admit(sender, guild, text, now,
		{ id = id, level = level, buckets = r.buckets, seen = r.seen, mine = r.mine, stats = r.stats, where = room })
	if not admitted then
		-- (A line the player's block terms hide is kept, marked, as the Chat tab keeps it.)
		if reason == "filtered" then Keep(r, { t = ns.Now(), sender = sender, guild = guild, class = class ~= "" and class or nil, text = text, id = id, hidden = true }) end
		return Drop(reason)
	end
	r.heard[Lower(sender)] = now
	-- The room's flood guard: 60 lines a minute shown; past it the lines wait for the notice.
	local shown = 0
	r.times = r.times or {}
	local keep = {}
	for _, t in ipairs(r.times) do if now - t < 60 then keep[#keep + 1] = t end end
	r.times = keep
	shown = #keep
	if shown >= ArenaChat.FLOOD then
		r.flooded = (r.flooded or 0) + 1
		ns.Fire("ARENA_CHAT", room)
		return Drop("flood")
	end
	r.times[#r.times + 1] = now
	local e = { t = ns.Now(), sender = sender, guild = guild, class = class ~= "" and class or nil, text = text, id = id }
	Keep(r, e)
	stats.shown = stats.shown + 1
	AlsoInChat(room, e)
	ns.Fire("ARENA_CHAT", room)
	return true
end
ArenaChat.OnChat = OnChat

-- How many lines the flood guard kept off since the player last looked (the panel's notice).
function ArenaChat.TakeFlood(room)
	local r = rooms[room]
	local n = r and r.flooded or 0
	if r then r.flooded = nil end
	return n
end

---------------------------------------------------------------------------
-- Mutes (EM): the room's arbiter or the card's promoter hides a name's lines in that room for as
-- long as it lives. That is all a mute does (it is no net-off).
---------------------------------------------------------------------------

local function MayMute(ev, name)
	return type(ev) == "table" and (Same(ev.opener, name) or Same(ev.arbiter, name) or Same(ev.promoter, name))
end
function ArenaChat.MayMute(room, name) return MayMute(Event(room), name or ns.me) end

function ArenaChat.Mute(room, name, on)
	local ev = Event(room)
	if not ev then return false, "room" end
	if not MayMute(ev, ns.me) then return false, "who" end
	name = ns.Arena.Name(name)
	if not name then return false, "name" end
	local r = Room(room, true)
	r.muted[Lower(name)] = on and true or nil
	local body = ("%s~%s~%s"):format(room, name, on and "1" or "0")
	local A = ns.Arena
	local mode = A.Mode(ev)
	if ev.public == true then
		A.Send("EM", mode, body, {})
	else
		for _, who in ipairs(Party(ev)) do
			if not Same(who, ns.me) then A.Send("EM", mode, body, { to = who }) end
		end
	end
	ns.Fire("ARENA_CHAT", room)
	return true
end

local function OnMute(dist, sender, mode, body)
	local room, name, flag = ns.Arena.Fields(body, 3)
	if not room or (flag ~= "1" and flag ~= "0") then return Drop("shape") end
	local ev = Event(room)
	if not ev or ns.Arena.Mode(ev) ~= mode then return Drop("room") end
	if not MayMute(ev, sender) then return Drop("who") end
	name = ns.Arena.Name(name)
	if not name then return Drop("name") end
	local r = Room(room, true)
	r.muted[Lower(name)] = flag == "1" or nil
	ns.Fire("ARENA_CHAT", room)
	return true
end
ArenaChat.OnMute = OnMute

ns.Comm.Handle("EC", ns.Arena.Handle("EC", OnChat))
ns.Comm.Handle("EM", ns.Arena.Handle("EM", OnMute))

-- The action every screen's box goes through (Arena.Can/Do): the rules' yes, not net-off, the room
-- open here, a writer there.
ns.Arena.Action("chat", function(room) return MaySend(room) end, function(room, text) return ArenaChat.Send(room, text) end)

-- /ola <text> (Core.lua routes it here as "say") and /oly arena chat [room].
ns.Arena.Slash("say", function(args)
	if tostring(args or ""):match("^%s*$") then
		ns.Print(L.ARENA_CHAT_USAGE)
		return
	end
	ArenaChat.Send(nil, args)
end, L.ARENA_HELP_SAY)
ns.Arena.Slash("chat", function(args)
	local room = tostring(args or ""):match("^%s*(%S+)") or current
	if not room then ns.Print(L.ARENA_CHAT_NO_ROOM) return end
	if not ArenaChat.Open(room) then ns.Print(L.ARENA_CHAT_UNKNOWN) return end
	if not ns.Arena.LoadUI() then return end
	local ui = ns.Arena.ui
	if type(ui) == "table" and type(ui.ChatPanel) == "table" and type(ui.ChatPanel.Open) == "function" then
		ns.SafeCall("arena chat panel", ui.ChatPanel.Open, room, true)
	end
end, L.ARENA_HELP_CHAT)

function ArenaChat.Reset() rooms, current = {}, nil end -- (tests)
