local ADDON, ns = ...
local L = ns.L

-- 1.1.6: lighter punishments in Olympus's own chats (The Watch): a moderator deletes a
-- player's line, or all his recent lines, and gives him a timeout (5 or 30 minutes, the High
-- Council's ladder of 1 hour, 24 hours and 7 days, or until lifted: his account held while a case
-- about him is decided). Every 1.1.6 client replaces a deleted line with "[deleted by a moderator]"
-- (the name stays, greyed) in the Chat tab and its saved history, in the rooms, and, where the
-- game's source shows a safe way (WatchChat.ReplacePrinted), in the game's own chat windows; a late
-- copy of it is dropped (a tombstone), and a report never carries it. A timed-out player's new
-- lines are dropped on every 1.1.6 client (Channels.Admit: the three chats, the rooms and the
-- arena's fight rooms) and his own client refuses to send, telling him in an Olympus pop-up who
-- (the role, never the name), until when and why.
-- A sanction is more than the chat: while a timeout, a hold or a net-off word
-- (Moderation.lua, exile included) is on a player, for the same window his own client and every
-- 1.1.6 client that knows it bar him (WatchChat.Barred) from the powers Olympus gives him (The
-- Watch, net-off words, pins, the Throne's calls, the shared block terms), the Olympus games, the
-- map's positions with the King's position and whether the King is online, and the Crafting tab;
-- during a hold his wallet is frozen too (no bet, no withdrawal).
--
-- Who may act, worked out on every client from the name the server stamps (never from a message):
--   a Watcher (his guild's officers, the people its guild master names, a signed moderator:
--     Watch.IsAuthorized) on a member of his own guild below him (Watch.TargetAllowed), over GUILD;
--   the author (7), the King (6), a High Councillor (4) or an Olympus moderator one of them named
--     (3) on anyone in Olympus whose level is lower (WatchChat.ProtectLevel: a Steward 5, a Hand 4,
--     a guild master 3), on the Olympus channel.
-- Nobody acts on himself, on the pinned King, or through a linked alt on someone he may not reach.
--
--   MD~1~<D|P|T|U>~<G|O>~<seq>~<at>~<guild>~<Name-Realm>~<arg>~<refs>~<by>~<reason>   an action
--       D: delete lines (refs: up to 3 "<chat>.<id|->.<hash>"), P: delete his recent lines (arg: the
--       window in seconds), T: a timeout (arg: when it ends, 0 until lifted), U: lift it.
--       by: "-", or (a timeout or lift passed on for a silent actor) the original actor's name.
--   MD~1~S~<D|P|T|U>~<seq>~<at>~<guild>~<actor>~<arg>~<refs>~   the target's own client: what his
--       guild's Watcher did, verified in its roster, on the channel (his own lines only); its last
--       field (a reason) is sent empty: a guild's reason stays with that guild and the player.
--   A timeout passed on (by: its actor) is taken only from a relay whose own weight reaches the
--   actor's, and then weighs the actor's on every client.
--   MD~1~W~<at>~<guild>~<page>~<pages>~<justice>~<Name-Realm,...>   a guild master's Watchers
--   MD~1~O~<at>~<page>~<pages>~<Name-Realm,...>                     a namer's Olympus moderators
--   MD~1~A~<at>~<actor>~<seq>~<T|D|P>~<text>  the punished player's appeal to the High Council
--   MD~1~R~<at>~<Name-Realm>~<actor>~<seq>~<K|L>~<reason>   a councillor's answer to an appeal (L on
--       a timeout comes with his lift, U, sent first)
--   MD~1~J~<at>~<guild>~<Name-Realm>~<jid>~<U|D>   the King's word on a case, told to the player
-- Every one is logged (the server keeps it), at most 255 bytes, rate-limited per sender. Clients
-- before 1.1.6 know no MD and leave it alone; they keep showing a deleted line and a timed-out
-- player's lines (the README says so).
-- Rooms that register a surface (WatchChat.RegisterSurface) take deletions too; the Church's room,
-- the crafting requests' private rooms and the fight rooms are the seam for later.

local WC = {}
ns.WatchChat = WC

WC.PROTOCOL = 1
WC.MESSAGE_MAX = 255
WC.REASON_MAX = 80
WC.APPEAL_MAX = 80
WC.REFS_MAX = 3
WC.WATCHERS_MAX = 10          -- a guild master names this many Watchers at most
WC.MODS_MAX = 10              -- and each namer this many Olympus moderators
WC.PAGES_MAX = 3
WC.TOMB_KEEP = 86400          -- a deleted line's tombstone (its late copies are dropped)
WC.TOMB_LOOSE = 120           -- ...one without the line's id (its words alone): only this long, for a copy in flight
WC.TOMB_MAX = 500
WC.PURGE_GRACE = 30           -- a purged player's lines still in flight this long after it
WC.PURGE_MIN, WC.PURGE_MAX = 60, 86400
WC.PURGE_WINDOW = 86400       -- "his recent lines": the last day
WC.DELETE_REPEAT_FOR = 7200   -- the actor's client repeats a deletion this long...
WC.DELETE_REPEAT_EVERY = 600  -- ...this often (a client offline at the time gets it)
WC.REPEAT = 300               -- an active timeout or lift is repeated this often (Moderation.REPEAT)...
WC.JITTER = 90                -- ...plus up to this much, this client's own draw
WC.PER_TICK = 3               -- MD messages one client repeats a minute at most
WC.PASS_ON_AFTER = 600        -- a timeout nobody repeated this long is passed on by another moderator
WC.HOLD_MAX = 30 * 86400      -- "until lifted" lapses this long after it was given (Moderation.OFF_KEEP)
WC.DATE_AHEAD = 60
WC.KEEP = 30 * 86400          -- records, audits and appeals
-- A minute: from one sender; from all senders with standing for what they sent (a moderator's
-- action, a namer's list, a guild master's: a flood from anyone else spends his own budget alone);
-- a target's own S from one sender, and from all.
WC.RATE, WC.RATE_ALL, WC.RATE_SELF, WC.RATE_SELF_ALL = 10, 60, 3, 60
WC.MAX_TARGETS = 300          -- names with a timeout or a lift kept
WC.MAX_PER_TARGET = 6
WC.AUDIT_MAX = 300
WC.RECORD_MAX = 20
WC.APPEALS_MAX = 50
WC.APPEALS_EACH = 3         -- appeals kept from one player at most
WC.SELF_AUDIT_MAX = 5       -- a player's own words (S) in the council's audit at most
WC.ACTIONS_MAX = 50           -- the actor's own actions it repeats
WC.APPLIED_MAX = 1000
WC.LISTS_MAX = 40             -- namers' lists kept
WC.LIST_EVERY = 300           -- a list is repeated this often (King.HANDS_EVERY)...
WC.LIST_FRESH = 20 * 60       -- ...and an Olympus moderators' list lapses this long after its last (King.HANDS_FRESH)
-- A guild master's Watchers lapse on another client this long after it last heard his list (he
-- repeats it every LIST_EVERY while on): a removal that client missed counts no longer than this.
WC.WATCHERS_FRESH = 3 * 86400
WC.VERDICTS_MAX = 30          -- the King's words on this guild's cases a Watcher's client keeps
WC.HELD_MAX = 20              -- guild actions waiting for a fresh roster
WC.HELD_KEEP = 600
WC.PRINTED_MAX = 300          -- lines this session printed in the game's chat windows
WC.PART_GAP = 3               -- a long line's parts: sent within this
WC.POPUP_GAP = 60             -- the timed-out player's pop-up on a refused send, at most this often
WC.BLOCKED_DAYS = 7           -- blocked lines are counted, per sender and category, this many days
WC.BLOCKED_SENDERS = 200
WC.DECISION_FOR = 3 * 86400   -- a case's decision is told to its player for this long...
WC.DECISION_EVERY = 1800      -- ...this often
WC.DECISIONS_MAX = 30
WC.SEQ_EPOCH = 1767225600
WC.MAX_SEQ = 2147483647
-- The game's own chat windows: off this switch and nothing of the game's is ever touched (the
-- in-game taint check decides; the README then says the game's window keeps what it showed).
WC.GAME_CHAT = true
-- Severe insults blocked at send: EMPTY until an approved word list is supplied.
-- Each entry: [folded word] = category. Nothing is blocked while it is empty.
WC.SEVERE = {}
WC.CATEGORIES = { "filtered", "timeout", "deleted", "severe" }

local LADDER = ns.Watch and not ns.Watch.missing and ns.Watch.TIMEOUTS or { 0, 3600, 86400, 604800 }
-- What a moderator picks: 5 and 30 minutes (light, off the ladder), the High Council's ladder's
-- steps, or until lifted (0).
WC.DURATIONS = { 300, 1800, LADDER[2], LADDER[3], LADDER[4], 0 }
WC.MAX_TIMEOUT = LADDER[#LADDER]

WC.LEVEL = { self = 1, guild = 2, mod = 3, council = 4, steward = 5, king = 6, author = 7 }
local LEVEL = WC.LEVEL

WC.random = math.random -- (tests)
WC.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local stats = { taken = 0, repeats = 0, refused = 0, sent = 0, rate = 0, held = 0, replaced = 0 }
local rates, rateAll, rateSelf = {}, {}, {} -- [sender key] = { times }; the shared budgets' { times }
local purgeGrace = {}              -- [sender key] = Now() until which his lines are dropped
local held = {}                    -- guild actions waiting for a fresh roster
local pages = {}                   -- lists coming in pages: [key] = { n, got, parts, t }
local printed, printedOrder = {}, {} -- lines printed in the game's chat windows this session
local lastPopup, toldLogin = -math.huge, false
local surfaces = {}
local jitter

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Now() return ns.Now() end
local function Key(s) return ns.Fold(tostring(s or "")) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and a ~= "" and Key(a) == Key(b) end
local function Live(t) return type(t) == "table" and not t.missing and t or nil end
local function TheWatch() return Live(ns.Watch) end
local function Mod() return Live(ns.Moderation) end

local function CleanReason(s, max)
	s = tostring(s or ""):gsub("[~|%^%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max or WC.REASON_MAX)
end
WC.CleanReason = CleanReason

-- A character's name as the server writes it ("Name-Realm"); nil when it can't be one.
local function CharName(input, target)
	local M = Mod()
	local name = M and M.CharName and M.CharName(input, target)
	if type(name) ~= "string" or name == "" or #name > 72 or name:find("[~%^,%c]") then return nil end
	return name
end
WC.CharName = CharName

local function Linked(name)
	local A = Live(ns.Alts)
	local list = A and A.Linked and A.Linked(name)
	return type(list) == "table" and list or {}
end

-- The same player: the name, or a name his player linked (Alts.lua, confirmed on both).
local function SamePerson(a, b)
	if Same(a, b) then return true end
	for _, other in ipairs(Linked(a)) do if Same(other, b) then return true end end
	return false
end

local function OwnGuild()
	local W = TheWatch()
	return W and W.OwnGuild and W.OwnGuild() or nil
end

-- Split on "~" (empty fields kept); nil past `max` fields.
local function Split(s, max)
	local out, from = {}, 1
	while true do
		local at = s:find("~", from, true)
		if not at then out[#out + 1] = s:sub(from) return out end
		out[#out + 1] = s:sub(from, at - 1)
		from = at + 1
		if #out >= max then return nil end
	end
end

local function Int(s, low, high)
	local n = tonumber(s)
	if not n or n ~= math.floor(n) or n < low or n > high or not tostring(s):match("^%d+$") then return nil end
	return n
end

local function Span(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds <= 0 then return L.WATCHCHAT_D_HOLD end
	if seconds % 86400 == 0 then return seconds == 86400 and L.WATCHCHAT_D_24H or L.WATCHCHAT_SPAN_DAYS:format(seconds / 86400) end
	if seconds % 3600 == 0 then return seconds == 3600 and L.WATCHCHAT_D_1H or L.WATCHCHAT_SPAN_HOURS:format(seconds / 3600) end
	return L.WATCHCHAT_SPAN_MIN:format(math.max(1, math.ceil(seconds / 60)))
end
WC.Span = Span

local function Hour(t) return date and date("%H:%M", t) or tostring(t) end
local function Stamp(t) return date and date("%Y-%m-%d %H:%M", t) or tostring(t) end

-- 6 base-36 characters over a line's canonical text (The Watch's report form: no colour, link or
-- texture codes, 140 bytes), so a moderator deleting from a report names the line he never saw.
local function Canonical(text)
	local W = TheWatch()
	if W and W.CleanLine then return W.CleanLine(text, W.REPORT_LINE_MAX) end
	return tostring(text or "")
end
local function Hash(text)
	local s = Canonical(text)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 2176782336 end
	local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", {}
	for i = 6, 1, -1 do
		local d = h % 36
		out[i] = digits:sub(d + 1, d + 1)
		h = math.floor(h / 36)
	end
	return table.concat(out)
end
WC.Hash = Hash

---------------------------------------------------------------------------
-- What this client keeps (ns.rdb.chatMod: per realm group and faction, like the net-off words)
---------------------------------------------------------------------------

local FIELDS = { "timeouts", "lifts", "tombs", "applied", "guildLists", "modLists", "myMods", "myWatchers",
	"actions", "audit", "record", "appeals", "decisions", "toldJ", "blocked", "sentS", "verdicts" }

local function Store()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return nil end
	local s = rdb.chatMod
	if type(s) ~= "table" or s.v ~= 1 then
		s = { v = 1 }
		rdb.chatMod = s
	end
	for _, f in ipairs(FIELDS) do if type(s[f]) ~= "table" then s[f] = {} end end
	s.seq = math.max(0, math.floor(tonumber(s.seq) or 0))
	return s
end
WC.Store = Store

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function Trim(list, max) while #list > max do table.remove(list, 1) end end

---------------------------------------------------------------------------
-- Who is who (every client the same way, from its own facts)
---------------------------------------------------------------------------

local function IsAuthor(name)
	local Wk = Live(ns.Workshop)
	return type(name) == "string" and Wk ~= nil and type(Wk.IsAuthorName) == "function" and Wk.IsAuthorName(name) == true
end
local function IsKing(name)
	if type(name) ~= "string" or name == "" then return false end
	if type(ns.IsKingCharacter) == "function" and ns.IsKingCharacter(name) == true then return true end
	local M = Mod()
	return M ~= nil and type(M.IsKing) == "function" and M.IsKing(name) == true
end
local function IsCouncillor(name) return type(name) == "string" and type(ns.IsHighCouncillor) == "function" and ns.IsHighCouncillor(name) == true end
local function IsSteward(name) return type(name) == "string" and type(ns.IsSteward) == "function" and ns.IsSteward(name) == true end
local function IsHand(name)
	local K = Live(ns.King)
	return K ~= nil and type(K.IsHandName) == "function" and K.IsHandName(name) == true
end

-- Who names Olympus moderators: the author, the King, a councillor (the author always).
local function NamerLevel(name)
	if IsAuthor(name) then return LEVEL.author end
	if IsKing(name) then return LEVEL.king end
	if IsCouncillor(name) then return LEVEL.council end
	return 0
end
WC.NamerLevel = NamerLevel

local function Named(list, key)
	for _, n in ipairs(type(list) == "table" and list or {}) do if Key(n) == key then return true end end
	return false
end

-- The sanction this client knows on `name` (nil: this character): a timeout, a hold, or a net-off
-- word (the exile included). Never on the pinned King.
local function TimeoutOf(name, now) return WC.TimeoutOf(name, now) end

function WC.Sanction(name)
	local me = name == nil
	name = me and ns.me or name
	if type(name) ~= "string" or name == "" or IsKing(name) then return nil end
	local t = TimeoutOf(name)
	if t then return { kind = (tonumber(t.untilAt) or 0) == 0 and "hold" or "timeout", entry = t, ends = WC.EndOf(t) } end
	local M = Mod()
	local off
	if me then off = M and M.SelfOff and M.SelfOff()
	else off = M and M.Hides and M.Hides(name) end
	if off then return { kind = "netoff", entry = off } end
	local exiled = WC.Exiled(name)
	if exiled then return { kind = "exile", entry = exiled } end
	return nil
end

-- The signed exile list that does not lapse in 30 days: the seam. Nil today.
function WC.Exiled(name) return nil end

-- What a sanction bars, for `name` (nil: this character): "powers", "games", "locations",
-- "crafting" for every sanction; "wallet" during a hold alone (his account blocked while a case
-- is decided). The sanction, or nil.
function WC.Barred(what, name)
	local s = WC.Sanction(name)
	if not s then return nil end
	if what == "wallet" then return s.kind == "hold" and s or nil end
	return s
end

-- The powers a role gives (Judgment's votes, Link's confirmations, the arena's words, ledgers,
-- rankings and banks: each module asks with the name it checks, its own player's or a sender's):
-- the sanction on him, or nil. This character's own name is asked as this character (his own
-- net-off word included, Moderation.SelfOff).
function WC.PowersBarred(name)
	if type(name) ~= "string" or name == "" then return nil end
	return WC.Barred("powers", Same(name, ns.me) and nil or name)
end

-- Is `name` on a namer's list that counts here: its namer still the author, the King or on the
-- signed council list, not sanctioned himself, and (another client's list) repeated lately.
function WC.IsMod(name)
	if type(name) ~= "string" or name == "" then return false end
	local s = Store()
	if not s then return false end
	local key, now = Key(ns.FullName(name)), Now()
	if ns.me and NamerLevel(ns.me) >= LEVEL.council and Named(s.myMods, key) and not WC.Barred("powers") then return true end
	for _, list in pairs(s.modLists) do
		if type(list) == "table" and type(list.set) == "table" and list.set[key] and not Same(list.by, ns.me)
			and NamerLevel(list.by) >= LEVEL.council and not WC.Barred("powers", list.by)
			and now - (tonumber(list.heard) or -math.huge) <= WC.LIST_FRESH then return true end
	end
	return false
end

-- The level an actor acts with in Olympus scope: 7 the author, 6 the King, 4 a councillor, 3 an
-- Olympus moderator, 0 anyone else (or anyone sanctioned: a net-off'd or timed-out moderator gives
-- nothing). Stewards and Hands are protected, not actors.
function WC.ActorLevel(name)
	if type(name) ~= "string" or name == "" then return 0 end
	local who = name
	if Same(name, ns.me) then who = nil end
	if WC.Barred("powers", who) then return 0 end
	local n = NamerLevel(name)
	if n > 0 then return n end
	return WC.IsMod(name) and LEVEL.mod or 0
end

local function GuildMaster(name)
	local W = TheWatch()
	if W and W.RosterRank and W.RosterRank(name) == 0 then return true end
	-- A census-known guild master: protection only (a false report can only cause a refusal).
	local M = Mod()
	local guild = M and M.GuildOf and M.GuildOf(name)
	return guild ~= nil and ns.Data ~= nil and type(ns.Data.AuthorizedRank) == "function" and ns.Data.AuthorizedRank(name, guild) == 0
end

local function OwnProtect(name)
	if IsAuthor(name) then return LEVEL.author end
	if IsKing(name) then return LEVEL.king end
	if IsSteward(name) then return LEVEL.steward end
	if IsCouncillor(name) or IsHand(name) then return LEVEL.council end
	if WC.IsMod(name) or GuildMaster(name) then return LEVEL.mod end
	return 0
end

-- How high a target stands: the highest over him and the names his player linked.
function WC.ProtectLevel(name)
	local lvl = OwnProtect(name)
	for _, other in ipairs(Linked(name)) do lvl = math.max(lvl, OwnProtect(other)) end
	return lvl
end

-- A guild master's named Watchers, as this client heard them over GUILD (or its own list): they
-- count while their namer is still rank 0 in this client's fresh roster, and for WATCHERS_FRESH
-- after this client last heard his list (his client repeats it every LIST_EVERY while he is on):
-- a removal this client missed, or a list whose guild master stopped playing, lapses then.
local function GuildList()
	local guild = OwnGuild()
	local s = Store()
	if not guild or not s then return nil end
	local W = TheWatch()
	local list = s.guildLists[Key(guild)]
	if ns.me and W and W.RosterRank and W.RosterRank(ns.me) == 0 then
		local mine = s.myWatchers[Key(guild)]
		if type(mine) == "table" then return { by = ns.me, names = mine.names or {}, justice = mine.justice, own = true } end
		return { by = ns.me, names = {}, own = true }
	end
	if type(list) ~= "table" or not (W and W.FreshRoster and W.FreshRoster()) or W.RosterRank(list.by) ~= 0 then return nil end
	if Now() - (tonumber(list.heard) or -math.huge) > WC.WATCHERS_FRESH then return nil end
	return list
end
WC.GuildList = GuildList

-- Named by this guild's master (and still in the roster, below the officers' ranks: an officer is
-- a Watcher anyway). Watch.IsAuthorized asks this: a named Watcher has the whole desk.
function WC.IsNamedWatcher(name)
	local N = ns.Nominees
	if N and not N.missing and N.IsCorrespondent and N.IsCorrespondent(name, OwnGuild(), "Council of Justice") then return true end
	local list = GuildList()
	if not list or type(name) ~= "string" then return false end
	local key = Key(ns.FullName(name))
	return Named(list.names, key) or (type(list.justice) == "string" and Key(list.justice) == key)
end

-- The guild's Justice correspondent: the one his guild master named, or nil.
function WC.Justice()
	local N = ns.Nominees
	local nominee = N and not N.missing and N.Correspondent and N.Correspondent(OwnGuild(), "Council of Justice")
	if nominee then return nominee end
	local list = GuildList()
	return list and type(list.justice) == "string" and list.justice ~= "" and list.justice or nil
end

-- May `actor` act on `target` in his guild, as this client sees its roster?
local function GuildAllowed(actor, target)
	local W = TheWatch()
	if not W or not W.IsAuthorized then return false, "watch" end
	if not OwnGuild() then return false, "guild" end
	if not (W.FreshRoster and W.FreshRoster()) then return false, "roster" end
	if SamePerson(actor, target) or SamePerson(target, actor) then return false, "self" end
	if IsKing(target) then return false, "rank" end
	if not W.IsAuthorized(actor) then return false, "actor" end
	if not (W.RosterRank and W.RosterRank(target) ~= nil) then return false, "member" end
	if W.TargetAllowed then
		local ok, why = W.TargetAllowed(actor, target)
		if not ok then return false, why or "rank" end
	end
	if WC.ProtectLevel(target) >= LEVEL.mod then return false, "rank" end
	return true
end

-- May `actor` act on `target` anywhere in Olympus? Its weight too.
local function OlympusAllowed(actor, target)
	if SamePerson(actor, target) or SamePerson(target, actor) then return false, "self" end
	local a = WC.ActorLevel(actor)
	if a < LEVEL.mod then return false, "actor" end
	if IsKing(target) and not IsAuthor(actor) then return false, "rank" end
	if WC.ProtectLevel(target) >= a then return false, "rank" end
	return true, nil, a
end

-- ok, why, weight for an action of `actor` on `target` in `scope` ("G" or "O").
function WC.Authority(actor, target, scope)
	if scope == "G" then
		local ok, why = GuildAllowed(actor, target)
		return ok, why, ok and LEVEL.guild or nil
	elseif scope == "O" then
		return OlympusAllowed(actor, target)
	end
	return false, "scope"
end

-- Does this client moderate anyone at all (the Chat tab keeps room for its button then)?
function WC.CanModerateAny()
	if not ns.me or not ns.IsMember() or WC.Barred("powers") then return false end
	if WC.ActorLevel(ns.me) >= LEVEL.mod then return true end
	local W = TheWatch()
	return W ~= nil and type(W.IsAuthorized) == "function" and OwnGuild() ~= nil and W.IsAuthorized(ns.me) == true
end

-- How this client may act on `target`: the scope ("O" first: it reaches every guild) and the
-- weight, or nil and why.
function WC.CanModerate(target)
	if not ns.me or not ns.IsMember() then return nil, "member" end
	target = CharName(target)
	if not target then return nil, "name" end
	if WC.Barred("powers") then return nil, "sanction" end
	local ok, why, weight = OlympusAllowed(ns.me, target)
	if ok then return "O", weight end
	local gok, gwhy = GuildAllowed(ns.me, target)
	if gok then return "G", LEVEL.guild end
	if why == "actor" then return nil, gwhy end
	return nil, why
end

---------------------------------------------------------------------------
-- Timeouts and lifts as kept
---------------------------------------------------------------------------

function WC.EndOf(e)
	local untilAt = tonumber(e and e.untilAt) or 0
	if untilAt > 0 then return untilAt end
	return (tonumber(e and e.at) or 0) + WC.HOLD_MAX
end

-- A guild timeout applies on a client while it is in that guild (the target's own included); an
-- Olympus one and a target's own word about himself anywhere.
local function Applies(e, guild)
	if e.scope ~= "G" then return true end
	return guild ~= nil and Key(e.guild) == Key(guild)
end

-- Which of two timeouts in force stands: the higher weight (what a lift must reach), and among
-- equals the one that ends last (two Watchers' timeouts: the longer binds, and the player is told
-- that one's end, never a shorter one given after it).
local function Before(e, best)
	if not best then return true end
	if e.weight ~= best.weight then return e.weight > best.weight end
	local a, b = WC.EndOf(e), WC.EndOf(best)
	if a ~= b then return a > b end
	return e.at > best.at
end

local function ActiveOn(key, now, guild)
	local s = Store()
	local best
	for _, e in ipairs(s and type(s.timeouts[key]) == "table" and s.timeouts[key] or {}) do
		if type(e) == "table" and WC.EndOf(e) > now and Applies(e, guild) and Before(e, best) then best = e end
	end
	return best
end

-- The timeout in force on `name` or a name his player linked: the highest weight, the one that
-- ends last among equals; nil when none.
function WC.TimeoutOf(name, now)
	if type(name) ~= "string" or name == "" or IsKing(name) then return nil end
	now = tonumber(now) or Clock()
	local guild = OwnGuild()
	local best = ActiveOn(Key(ns.FullName(name)), now, guild)
	for _, other in ipairs(Linked(name)) do
		local e = ActiveOn(Key(ns.FullName(other)), now, guild)
		if e and Before(e, best) then best = e end
	end
	return best
end

function WC.TimeoutEnd(name)
	local e = WC.TimeoutOf(name)
	return e and WC.EndOf(e) or nil
end

-- This character's own timeout, or nil.
function WC.SelfTimeout() return ns.me and WC.TimeoutOf(ns.me) or nil end

-- Channels.Admit: drop a timed-out sender's new lines (every 1.1.6 client, moderators' too).
function WC.Silenced(sender, guild)
	return WC.TimeoutOf(sender) ~= nil
end

local function Lifted(key, e)
	local s = Store()
	for _, lift in ipairs(s and type(s.lifts[key]) == "table" and s.lifts[key] or {}) do
		if type(lift) == "table" and lift.at >= e.at and lift.weight >= e.weight
			and (lift.scope ~= "G" or e.scope ~= "G" or Key(lift.guild) == Key(e.guild)) then return true end
	end
	return false
end

local function MakeRoom(s, key)
	if s.timeouts[key] or s.lifts[key] then return true end
	local n = Count(s.timeouts) + Count(s.lifts)
	if n < WC.MAX_TARGETS then return true end
	-- The oldest of the lowest weight goes; never one weighing more than a guild's.
	local drop, at, w
	for k, list in pairs(s.timeouts) do
		local top, newest = 0, 0
		for _, e in ipairs(list) do top, newest = math.max(top, e.weight or 0), math.max(newest, e.at or 0) end
		if top <= LEVEL.guild and (not w or top < w or (top == w and newest < at)) then drop, at, w = k, newest, top end
	end
	if not drop then
		for k, list in pairs(s.lifts) do
			local newest = 0
			for _, e in ipairs(list) do newest = math.max(newest, e.at or 0) end
			if not at or newest < at then drop, at = k, newest end
		end
		if drop then s.lifts[drop] = nil return true end
		return false
	end
	s.timeouts[drop] = nil
	return true
end

-- Keep a timeout; false and why when it can't be ("lifted": a late repeat of one lifted since).
local function KeepTimeout(a)
	local s = Store()
	if not s then return false, "store" end
	local key = Key(a.target)
	local e = { name = a.target, by = a.by, via = a.via or a.relay, scope = a.scope, weight = a.weight, seq = a.seq, at = a.at,
		untilAt = a.untilAt or 0, reason = a.reason, guild = a.guild, heard = Now(), role = a.role, named = a.named }
	if Lifted(key, e) then return false, "lifted" end
	if WC.EndOf(e) <= Clock() then return false, "ended" end
	if not MakeRoom(s, key) then return false, "full" end
	local list = s.timeouts[key] or {}
	s.timeouts[key] = list
	for i = #list, 1, -1 do
		local old = list[i]
		-- The same actor's newer word replaces his older one (on the same scope and guild; a
		-- target's own words, by the actor each names: two Watchers' timeouts stay two).
		if Same(old.by, e.by) and old.scope == e.scope and Key(old.guild) == Key(e.guild)
			and (e.scope ~= "S" or Key(old.named) == Key(e.named)) then
			if old.seq == e.seq then
				old.heard = Now()
				-- The actor's own word over a relay's account of it: its end and reason are his.
				if old.via and not e.via then
					old.via, old.untilAt, old.reason, old.weight, old.role = nil, e.untilAt, e.reason, math.max(old.weight, e.weight), e.role
				end
				return true, "repeat"
			end
			if old.seq > e.seq then return false, "older" end
			table.remove(list, i)
		end
	end
	list[#list + 1] = e
	Trim(list, WC.MAX_PER_TARGET)
	return true
end

-- A lift ends every timeout on that name its weight reaches (a guild's lift: that guild's alone),
-- and is kept until the latest planned end of what it lifted.
local function KeepLift(a)
	local s = Store()
	if not s then return 0 end
	local key = Key(a.target)
	local ended, keep = 0, Clock() + WC.REPEAT
	local list = s.timeouts[key] or {}
	for i = #list, 1, -1 do
		local e = list[i]
		local reach = e.weight <= a.weight and e.at <= a.at
			and (a.scope ~= "G" or e.scope ~= "G" or Key(e.guild) == Key(a.guild))
			and (a.scope ~= "S" or e.scope == "S")
		if reach then
			keep = math.max(keep, WC.EndOf(e))
			table.remove(list, i)
			ended = ended + 1
		end
	end
	if #list == 0 then s.timeouts[key] = nil end
	if MakeRoom(s, key) then
		local lifts = s.lifts[key] or {}
		s.lifts[key] = lifts
		lifts[#lifts + 1] = { at = a.at, weight = a.weight, scope = a.scope, guild = a.guild, by = a.by, keep = keep }
		Trim(lifts, WC.MAX_PER_TARGET)
	end
	return ended
end

---------------------------------------------------------------------------
-- The lines: surfaces (each chat stays the only authority over its own lines), deletion, tombstones
---------------------------------------------------------------------------

-- surface = { key, Chats = fn() -> { chat keys }, Lines = fn(chat) -> entries, Changed = fn(chat) }
-- entries: { sender, guild, id, text, t, mine, del, delAt }. Channels (A, C, L) and ChatRooms'
-- own rooms register below; the Church's room, the crafting requests' rooms and the fight rooms
-- are the seam (each registers itself; MD's chat field already takes their keys).
function WC.RegisterSurface(sf)
	if type(sf) ~= "table" or type(sf.key) ~= "string" or type(sf.Chats) ~= "function" or type(sf.Lines) ~= "function" then return false end
	for i, old in ipairs(surfaces) do if old.key == sf.key then surfaces[i] = sf return true end end
	surfaces[#surfaces + 1] = sf
	return true
end

local function EachChat(fn)
	for _, sf in ipairs(surfaces) do
		local ok, chats = pcall(sf.Chats)
		for _, chat in ipairs(ok and type(chats) == "table" and chats or {}) do
			local okLines, lines = pcall(sf.Lines, chat)
			if okLines and type(lines) == "table" then fn(sf, chat, lines) end
		end
	end
end

local function Changed(sf, chat)
	if type(sf.Changed) == "function" then pcall(sf.Changed, chat) end
end

local function Ref(chat, id, hash)
	return tostring(chat) .. "." .. (id ~= nil and tostring(id) or "-") .. "." .. hash
end

local function ParseRefs(s)
	if s == "-" or s == "" then return nil end
	local out = {}
	for part in (s .. ","):gmatch("([^,]*),") do
		local chat, id, hash = part:match("^([%w:_]+)%.([%d%-]+)%.([0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z])$")
		if not chat or #chat > 24 then return nil end
		if id ~= "-" then
			id = Int(id, 0, 9999)
			if not id then return nil end
		else
			id = nil
		end
		out[#out + 1] = { chat = chat, id = id, hash = hash }
		if #out > WC.REFS_MAX then return nil end
	end
	return #out > 0 and out or nil
end
WC.ParseRefs = ParseRefs

local function RefsText(refs)
	local out = {}
	for _, r in ipairs(refs or {}) do out[#out + 1] = Ref(r.chat, r.id, r.hash) end
	return #out > 0 and table.concat(out, ",") or "-"
end

local function Matches(e, sender, ref)
	if type(e) ~= "table" or e.del or not Same(e.sender, sender) then return false end
	if ref.id ~= nil and e.id ~= nil and tonumber(e.id) ~= ref.id then return false end
	return Hash(e.text) == ref.hash
end

-- Mark an entry deleted. The words go: kept (cut to 140 bytes) only where `keep` asks (an audit
-- this client keeps), never back into the history.
local function Erase(e, at, role)
	local words = Canonical(e.text)
	e.text, e.del, e.delAt, e.delRole = "", true, at, role
	return words
end

-- A tombstone: a late copy of the line is dropped (Tombstoned). With the line's id it is that line
-- alone, for TOMB_KEEP; without one (a report's line its actor's client never held, a history
-- from before 1.1.6) its words would match every later line of his saying the same ("lol", "gg"):
-- such a tomb drops a copy still in flight for TOMB_LOOSE only.
local function Tomb(chat, sender, id, hash)
	local s = Store()
	if not s then return end
	for _, t in ipairs(s.tombs) do
		if t.chat == chat and t.sender == Key(sender) and t.id == id and t.hash == hash then t.t = Now() return end
	end
	s.tombs[#s.tombs + 1] = { chat = chat, sender = Key(sender), id = id, hash = hash, t = Now() }
	Trim(s.tombs, WC.TOMB_MAX)
end

-- Delete the lines `refs` names, of `sender`, on every surface this client holds; the game's chat
-- windows too where it may (ReplacePrinted). Returns how many and the words (canonical) deleted.
-- A ref without an id takes the id of the line this client finds by its words (the sender's id
-- for that line, the same on every client), so its tombstone is that line's alone.
local function ApplyDelete(sender, refs, at, role)
	local n, words, found = 0, {}, {}
	EachChat(function(sf, chat, lines)
		local hit = false
		for i, ref in ipairs(refs) do
			if ref.chat == chat then
				for _, e in ipairs(lines) do
					if Matches(e, sender, ref) then
						local id = ref.id or tonumber(e.id)
						WC.ReplacePrinted(chat, sender, id, ref.hash)
						if id then Tomb(chat, sender, id, ref.hash) found[i] = true end
						words[#words + 1] = Erase(e, at, role)
						n, hit = n + 1, true
					end
				end
			end
		end
		if hit then Changed(sf, chat) end
	end)
	for i, ref in ipairs(refs) do
		if not found[i] then
			Tomb(ref.chat, sender, ref.id, ref.hash)
			WC.ReplacePrinted(ref.chat, sender, ref.id, ref.hash)
		end
	end
	return n, words
end

-- Delete every line of `sender` from the `window` seconds before the purge (`at`, server time) on
-- every surface; and drop his lines still in flight for PURGE_GRACE. Heard later (the actor's
-- repeat to a client that was away), it takes only what he wrote before it: never his later lines.
local function ApplyPurge(sender, window, at, role)
	local shift = Now() - Clock() -- (the history's times are this client's clock; `at` the server's)
	local since, upto, n, words = at + shift - window, at + shift + WC.PURGE_GRACE, 0, {}
	if Clock() - at <= WC.PURGE_GRACE then purgeGrace[Key(sender)] = Now() + WC.PURGE_GRACE end
	EachChat(function(sf, chat, lines)
		local hit = false
		for _, e in ipairs(lines) do
			local t = tonumber(e and e.t) or 0
			if type(e) == "table" and not e.del and Same(e.sender, sender) and t >= since and t <= upto then
				local hash = Hash(e.text)
				WC.ReplacePrinted(chat, sender, tonumber(e.id), hash)
				Tomb(chat, sender, tonumber(e.id), hash)
				words[#words + 1] = Erase(e, at, role)
				n, hit = n + 1, true
			end
		end
		if hit then Changed(sf, chat) end
	end)
	return n, words
end

-- Channels.Admit: a late copy of a deleted line (or a purged player's line still in flight).
function WC.Tombstoned(chat, sender, id, text)
	local key = Key(sender)
	if (purgeGrace[key] or -math.huge) > Now() then return true end
	local s = Store()
	if not s or #s.tombs == 0 then return false end
	local hash
	local now = Now()
	for i = #s.tombs, 1, -1 do
		local t = s.tombs[i]
		if t.sender == key and (chat == nil or t.chat == chat) then
			hash = hash or Hash(text)
			if t.hash == hash then
				-- Its own line (the id) for a day; by its words alone, a copy in flight only.
				if t.id ~= nil and id ~= nil then
					if t.id == tonumber(id) then return true end
				elseif now - (tonumber(t.t) or 0) <= WC.TOMB_LOOSE then
					return true
				end
			end
		end
	end
	return false
end

-- A part of an army chat's line that another part follows: Codec.SplitChat cuts a long line at its
-- budget (at a space at most 40 bytes back), so only a part that long has a next part. Two short
-- lines said quickly one after the other stay two lines.
local function Cut(e)
	local Codec = ns.Codec
	if type(e) ~= "table" or type(e.text) ~= "string" or not (Codec and Codec.ChatBudget) then return false end
	return #e.text >= Codec.ChatBudget(e.guild or "", e.class or "") - 41
end

-- The refs for a line of the Chat tab: it and, of a long line, its parts right next to it (the
-- same sender, consecutive ids, sent within PART_GAP, each part before the last cut full), 3 at
-- most. A room's line is one message: no parts.
function WC.RefsFor(chat, entry)
	local lines
	for _, sf in ipairs(surfaces) do
		local ok, chats = pcall(sf.Chats)
		for _, c in ipairs(ok and chats or {}) do
			if c == chat then
				local okLines, got = pcall(sf.Lines, chat)
				if okLines and type(got) == "table" then lines = got end
			end
		end
	end
	if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.del then return nil end
	local refs = { { chat = chat, id = tonumber(entry.id), hash = Hash(entry.text) } }
	local C = Live(ns.Channels)
	if not lines or entry.id == nil or not (C and C.TIERS and C.TIERS[chat]) then return refs end
	local at
	for i, e in ipairs(lines) do if e == entry then at = i end end
	if not at then return refs end
	local function Part(e, prev, step)
		return type(e) == "table" and not e.del and Same(e.sender, entry.sender) and e.id ~= nil and prev.id ~= nil
			and (tonumber(e.id) - tonumber(prev.id)) % 10000 == step % 10000
			and math.abs((tonumber(e.t) or 0) - (tonumber(prev.t) or 0)) <= WC.PART_GAP
	end
	local prev = entry
	for i = at - 1, 1, -1 do
		if #refs >= WC.REFS_MAX or not Part(lines[i], prev, -1) or not Cut(lines[i]) then break end
		table.insert(refs, 1, { chat = chat, id = tonumber(lines[i].id), hash = Hash(lines[i].text) })
		prev = lines[i]
	end
	prev = entry
	for i = at + 1, #lines do
		if #refs >= WC.REFS_MAX or not Cut(prev) or not Part(lines[i], prev, 1) then break end
		refs[#refs + 1] = { chat = chat, id = tonumber(lines[i].id), hash = Hash(lines[i].text) }
		prev = lines[i]
	end
	return refs
end

---------------------------------------------------------------------------
-- The game's own chat windows (Forever's source, Blizzard_SharedXML/ScrollingMessageFrame.lua):
-- TransformMessages is the call Blizzard itself uses on every chat frame to rewrite a censored
-- line (ChatFrameUtil.lua, ItemRefHandlersShared.lua). It goes through the frame's secure mixin,
-- as the AddMessage Olympus already makes for each of its lines, and touches no edit box, chat
-- focus, LAST_ACTIVE_CHAT_EDIT_BOX or CHAT_FOCUS_OVERRIDE (the 0.8.5 freeze). Used only: off the
-- gamepad UI (ns.GamepadUI: nothing of the game's is touched there), on a window Olympus printed
-- the line into this session (never the combat log, never Chattynator's tabs: its API can't change
-- a line), on an entry whose text is byte for byte what Olympus printed (another addon's rewrite
-- makes it differ: nothing happens), never on a secret value, inside pcall, and while GAME_CHAT is
-- on. Wherever it does not apply, the game's chat window keeps what it already showed (the
-- README says so); the Chat tab and the saved history are replaced all the same.
---------------------------------------------------------------------------

local function PrintedKey(chat, sender, id, hash) return tostring(chat) .. "#" .. Key(sender) .. "#" .. tostring(id or "-") .. "#" .. hash end

-- Channels.Show: what it printed, where.
function WC.NotePrinted(chat, sender, guild, id, text, frame, line, deleted)
	if type(frame) ~= "table" or type(line) ~= "string" or type(deleted) ~= "string" then return end
	local key = PrintedKey(chat, sender, id, Hash(text))
	if not printed[key] then printedOrder[#printedOrder + 1] = key end
	printed[key] = { chat = chat, sender = sender, id = id, hash = Hash(text), frame = frame, line = line, deleted = deleted }
	while #printedOrder > WC.PRINTED_MAX do printed[table.remove(printedOrder, 1)] = nil end
end

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

local function Replaceable(f)
	if type(f) ~= "table" or type(f.TransformMessages) ~= "function" then return false end
	local C = Live(ns.Channels)
	if C and type(C.IsChattyTarget) == "function" and C.IsChattyTarget(f) then return false end
	if type(IsCombatLog) == "function" then
		local ok, combat = pcall(IsCombatLog, f)
		if not ok or combat then return false end
	end
	return true
end

function WC.ReplacePrinted(chat, sender, id, hash)
	-- The kill switch and the gamepad UI: the game's window keeps what it showed.
	if not WC.GAME_CHAT or (ns.GamepadUI and ns.GamepadUI()) then return 0 end
	local n = 0
	for i = #printedOrder, 1, -1 do
		local key = printedOrder[i]
		local p = printed[key]
		if p and p.chat == chat and Same(p.sender, sender) and p.hash == hash and (id == nil or p.id == nil or tonumber(p.id) == id) then
			if Replaceable(p.frame) then
				local old, new = p.line, p.deleted
				local ok = pcall(p.frame.TransformMessages, p.frame,
					function(message) return not Secret(message) and message == old end,
					function(_, r, g, b, ...) return new, r, g, b, ... end)
				if ok then n = n + 1 end
			end
			printed[key] = nil
			table.remove(printedOrder, i)
		end
	end
	stats.replaced = stats.replaced + n
	return n
end

---------------------------------------------------------------------------
-- Records: The Watch's audit (that guild's Watch), the council's (the High Council, the King and
-- the author), the punished player's own ("Your record": roles only)
---------------------------------------------------------------------------

local function Entitled()
	local W = TheWatch()
	return W ~= nil and W.CanRead and W.CanRead() == true
end
local function CouncilSide() return ns.me ~= nil and NamerLevel(ns.me) >= LEVEL.council end
WC.CouncilSide = CouncilSide

local function RoleOf(scope, weight)
	if scope == "G" then return "G" end
	if scope == "S" then return "S" end
	return tostring(weight or 0)
end

-- The role as the punished player (or anyone) is told it: never the name.
function WC.RoleText(role, mine)
	if role == "G" then return mine and L.WATCHCHAT_ROLE_G or L.WATCHCHAT_ROLE_G_OTHER end
	local text = L["WATCHCHAT_ROLE_" .. tostring(role)]
	if type(text) == "string" and text ~= "WATCHCHAT_ROLE_" .. tostring(role) then return text end
	return L.WATCHCHAT_ROLE_ANY
end

local function Record(a, words)
	local s = Store()
	if not s then return end
	local op = a.op == "U" and "L" or a.op
	-- That guild's Watch: its own audit (who, whom, what, why, when, the words this client kept).
	-- Never a target's own word (S): it names an actor only as his client says, and the guild's
	-- Watch heard the action itself, over GUILD, from the one who gave it.
	local W = TheWatch()
	if a.scope ~= "S" and Entitled() and W and W.ApplyChat and (a.scope == "G" or (W.RosterRank and W.RosterRank(a.target) ~= nil)) then
		W.ApplyChat({ op = op, name = a.target, by = a.by, via = a.relay, at = a.at, seq = a.seq, untilAt = a.untilAt or 0,
			reason = a.reason or "", text = words and words[1] or nil, scope = a.scope })
	end
	-- The High Council, the King and the author: every Olympus action, every guild one a target's
	-- own client confirmed.
	if CouncilSide() and (a.scope == "O" or a.scope == "S") then
		-- (1.2.0: a player's own words, a few each: his flood never pushes anyone else's out.)
		if a.scope == "S" then
			local mine, first = 0, nil
			for i, e in ipairs(s.audit) do
				if e.scope == "S" and Same(e.name, a.target) then mine = mine + 1 first = first or i end
			end
			if mine >= WC.SELF_AUDIT_MAX and first then table.remove(s.audit, first) end
		end
		s.audit[#s.audit + 1] = { op = op, scope = a.scope, name = a.target, by = a.by, via = a.relay, at = a.at, seq = a.seq,
			untilAt = a.untilAt or 0, reason = a.reason or "", text = words and words[1] or nil, guild = a.guild }
		Trim(s.audit, WC.AUDIT_MAX)
	end
	-- The punished player: his own record, roles only.
	if ns.me and Same(a.target, ns.me) and a.scope ~= "S" then
		s.record[#s.record + 1] = { op = op, role = a.role, at = a.at, untilAt = a.untilAt or 0, reason = a.reason or "",
			words = words and words[1] or nil, by = a.by, seq = a.seq }
		Trim(s.record, WC.RECORD_MAX)
	end
	ns.Fire("WATCH_CHANGED")
end

---------------------------------------------------------------------------
-- The timed-out player is told (an Olympus pop-up: ns.ShowDialog, its own window under the gamepad UI)
---------------------------------------------------------------------------

local function ReasonPart(reason)
	reason = CleanReason(reason)
	return reason ~= "" and L.WATCHCHAT_REASON_PART:format(reason) or ""
end

function WC.TimeoutText(e)
	if not e then return "" end
	local role = WC.RoleText(e.role, true)
	if (tonumber(e.untilAt) or 0) == 0 then
		local wallet = ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()
		return (wallet and L.WATCHCHAT_YOU_HELD or L.WATCHCHAT_YOU_HELD_FREE):format(role, ReasonPart(e.reason))
	end
	local when = L.WATCHCHAT_FOR_UNTIL:format(Span(e.untilAt - e.at), Hour(e.untilAt))
	return L.WATCHCHAT_YOU_TIMED_OUT:format(role, when, ReasonPart(e.reason))
end

function WC.TellTimeout(e, force)
	if not e then return false end
	if not force and Now() - lastPopup < WC.POPUP_GAP then
		ns.Print(Red(L.WATCHCHAT_REFUSED_LINE:format((tonumber(e.untilAt) or 0) == 0 and L.WATCHCHAT_UNTIL_LIFTED or Hour(e.untilAt),
			WC.RoleText(e.role, true))))
		return false
	end
	lastPopup = Now()
	ns.ShowDialog("OLYMPUS_WATCHCHAT_TIMED_OUT", WC.TimeoutText(e), nil, { by = e.by, seq = e.seq, role = e.role })
	if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	return true
end

-- Channels.Send, ChatRooms.Send, ArenaChat.Send: refused while timed out, and told why.
function WC.RefuseSend()
	local e = WC.SelfTimeout()
	if not e then return nil end
	WC.TellTimeout(e)
	return e
end

-- Every other surface a sanction bars (WatchChat.Barred): what he cannot do, and until when.
function WC.BarredText(s)
	if type(s) ~= "table" then return "" end
	local untilText = s.kind == "netoff" and L.WATCHCHAT_NETOFF
		or ((s.kind == "hold" or s.kind == "exile") and L.WATCHCHAT_UNTIL_LIFTED or Hour(s.ends))
	return L.WATCHCHAT_BARRED:format(untilText)
end
-- ...told in one line.
function WC.TellBarred(s)
	if not s then return end
	ns.Print(Red(WC.BarredText(s)))
	return s
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------

-- A budget of `max` a minute: false (counted) once it is spent.
local function Budget(list, max)
	local now = Now()
	for i = #list, 1, -1 do if now - list[i] >= 60 then table.remove(list, i) end end
	if #list >= max then stats.rate = stats.rate + 1 return false end
	list[#list + 1] = now
	return true
end

-- One sender's own budget (every MD he sends spends it, whatever it is).
local function Rate(sender, max)
	local key = Key(sender)
	local list = rates[key] or {}
	rates[key] = list
	return Budget(list, max or WC.RATE)
end

-- The budget all senders share, spent only once the sender has standing for what he sent (his
-- client's facts: a Watcher in this roster, a moderator, a namer, a guild master), so junk from
-- anyone else never crowds out a real action. `retry`: a held action, counted when it came.
local function Shared(retry)
	if retry then return true end
	return Budget(rateAll, WC.RATE_ALL)
end

local function Refuse(why, sender)
	stats.refused = stats.refused + 1
	if sender then ns.Log("chat moderation from %s refused: %s", tostring(sender), tostring(why)) end
	return false, why
end

local function Arg(a)
	if a.op == "P" then return tostring(a.window or WC.PURGE_WINDOW) end
	if a.op == "T" then return tostring(a.untilAt or 0) end
	return "-"
end

local function ActionWire(a, passOn)
	local guild = a.scope == "G" and a.guild or (type(a.guild) == "string" and a.guild ~= "" and a.guild:gsub("[~|%^%c]", "") or "-")
	local head = table.concat({ "MD", "1", a.op, a.scope, tostring(a.seq), tostring(a.at), guild, a.target, Arg(a),
		a.op == "D" and RefsText(a.refs) or "-", passOn and a.by or "-" }, "~")
	if #head + 1 > WC.MESSAGE_MAX then return nil end
	return head .. "~" .. ns.Cut(CleanReason(a.reason), math.min(WC.REASON_MAX, WC.MESSAGE_MAX - #head - 1))
end
WC.ActionWire = ActionWire

-- The target's own word on the channel: what, when, until when, by which Watcher (so the High
-- Council sees guild actions), never the reason. A guild's reason stays with that guild (over
-- GUILD) and the player; the channel reaches every Olympus client.
local function SelfWire(a)
	local head = table.concat({ "MD", "1", "S", a.op, tostring(a.seq), tostring(a.at), a.guild or "-", a.by, Arg(a),
		a.op == "D" and RefsText(a.refs) or "-" }, "~")
	if #head + 1 > WC.MESSAGE_MAX then return nil end
	return head .. "~"
end

local function Send(dist, msg, key, permit)
	local C = ns.Comm
	if type(msg) ~= "string" or #msg > WC.MESSAGE_MAX or type(C) ~= "table" or type(C.Send) ~= "function" then return false end
	stats.sent = stats.sent + 1
	return C.Send(dist, msg, key, false, true, nil, permit and { owner = WC, key = key, permit = permit } or nil) ~= false
end

-- At the game send: the actor may still give it (rank, guild, sanction), else it never leaves.
local function ActionPermit(a, msg, scope, dist)
	return function(owner, key, d, _, payload)
		if owner ~= WC or d ~= dist or payload ~= msg then return false, "guard" end
		if scope == "G" and OwnGuild() ~= a.guild then return false, "revoked" end
		local ok = WC.Authority(ns.me, a.target, scope)
		if not ok then return false, "revoked" end
		return true
	end
end

-- An action this client applies: its own (given here) or one it took.
local function Apply(a)
	local s = Store()
	if not s then return false, "store" end
	local id = Key(a.by) .. "#" .. tostring(a.seq)
	local seen = s.applied[id]
	if seen and (a.op == "D" or a.op == "P") then return true, "repeat" end
	local n, words
	if a.op == "D" then
		n, words = ApplyDelete(a.target, a.refs, a.at, a.role)
	elseif a.op == "P" then
		n, words = ApplyPurge(a.target, a.window or WC.PURGE_WINDOW, a.at, a.role)
	elseif a.op == "T" then
		local ok, why = KeepTimeout(a)
		if not ok then return false, why end
		if why == "repeat" or seen then return true, "repeat" end
	elseif a.op == "U" then
		if seen then return true, "repeat" end
		KeepLift(a)
		-- A lift from someone else that reaches this client's own timeout on him: its repeats stop
		-- (a client that comes on later never hears it again from here).
		if not Same(a.by, ns.me) then
			for i = #s.actions, 1, -1 do
				local o = s.actions[i]
				if o.op == "T" and Same(o.target, a.target) and (o.weight or 0) <= a.weight and (o.at or 0) <= a.at
					and (a.scope ~= "G" or o.scope ~= "G" or Key(o.guild) == Key(a.guild)) then table.remove(s.actions, i) end
			end
		end
	end
	s.applied[id] = a.at
	if Count(s.applied) > WC.APPLIED_MAX then
		local oldest, at
		for k, t in pairs(s.applied) do if not at or t < at then oldest, at = k, t end end
		if oldest then s.applied[oldest] = nil end
	end
	Record(a, words)
	-- The punished player's own client: told; and, of a guild action, his own word on the channel.
	if ns.me and Same(a.target, ns.me) and a.scope ~= "S" then
		if a.op == "T" then
			local e = WC.SelfTimeout()
			if e then WC.TellTimeout(e, true) end
		elseif a.op == "U" then
			if not WC.SelfTimeout() then ns.Print(Green(L.WATCHCHAT_LIFTED_YOU:format(WC.RoleText(a.role, true)))) end
		elseif a.op == "D" then
			ns.Print(Gold(L.WATCHCHAT_DELETED_YOURS:format(WC.RoleText(a.role, true), ReasonPart(a.reason))))
		elseif a.op == "P" then
			ns.Print(Gold(L.WATCHCHAT_PURGED_YOURS:format(WC.RoleText(a.role, true), ReasonPart(a.reason))))
		end
		if a.scope == "G" and not s.sentS[id] then
			s.sentS[id] = a.at
			local msg = SelfWire(a)
			if msg then Send("CHANNEL", msg, "mds:" .. id) end
		end
	end
	ns.Fire("WATCHCHAT_CHANGED", a.op, a.target)
	ns.Fire("WATCH_CHANGED")
	return true
end

local function Remember(a)
	local s = Store()
	if not s then return end
	-- A lift ends the actor's own repeats of what it lifted.
	if a.op == "U" then
		for i = #s.actions, 1, -1 do
			local o = s.actions[i]
			if o.op == "T" and Same(o.target, a.target) and o.weight <= a.weight then table.remove(s.actions, i) end
		end
	end
	if a.op == "T" then
		for i = #s.actions, 1, -1 do
			local o = s.actions[i]
			if (o.op == "T" or o.op == "U") and Same(o.target, a.target) and o.scope == a.scope then table.remove(s.actions, i) end
		end
	end
	a.sent = Now()
	s.actions[#s.actions + 1] = a
	Trim(s.actions, WC.ACTIONS_MAX)
end

-- This client acts. op: "D" (opts.refs), "P", "T" (opts.seconds: 0 until lifted, or opts.untilAt),
-- "U" (opts.blind: an appeal's lift, sent though this client holds no timeout on him: the
-- council's answer reaches whatever his own and his guild's clients hold, up to its weight).
-- opts.reason optional (80 bytes). True and the scope, or false and why.
function WC.Act(op, target, opts)
	opts = opts or {}
	if op ~= "D" and op ~= "P" and op ~= "T" and op ~= "U" then return false, "op" end
	target = CharName(target, true)
	if not target then return false, "name" end
	-- The pinned King is never timed out (no client would hold it: WC.TimeoutOf): the author may
	-- delete his lines, nobody gives him a timeout.
	if (op == "T" or op == "U") and IsKing(target) then return false, "king" end
	local scope, weight = WC.CanModerate(target)
	if not scope then return false, weight end
	local s = Store()
	if not s then return false, "store" end
	local now = math.floor(Clock())
	local a = { op = op, scope = scope, target = target, by = ns.me, weight = weight, role = RoleOf(scope, weight),
		reason = CleanReason(opts.reason), at = now }
	if scope == "G" then a.guild = OwnGuild()
	else
		local M = Mod()
		a.guild = M and M.GuildOf and M.GuildOf(target) or nil
	end
	if op == "D" then
		if type(opts.refs) ~= "table" or #opts.refs == 0 or #opts.refs > WC.REFS_MAX then return false, "refs" end
		a.refs = opts.refs
	elseif op == "P" then
		a.window = math.max(WC.PURGE_MIN, math.min(WC.PURGE_MAX, math.floor(tonumber(opts.window) or WC.PURGE_WINDOW)))
	elseif op == "T" then
		local untilAt = tonumber(opts.untilAt)
		if not untilAt then
			local seconds = math.floor(tonumber(opts.seconds) or -1)
			if seconds < 0 then return false, "duration" end
			untilAt = seconds == 0 and 0 or now + seconds
		end
		if untilAt ~= 0 and (untilAt <= now or untilAt - now > WC.MAX_TIMEOUT) then return false, "duration" end
		a.untilAt = untilAt
	elseif op == "U" then
		-- Something this lift reaches (and its repeats last until what it lifted would have ended).
		local e = WC.TimeoutOf(target)
		if e and e.weight > weight then return false, "rank" end
		if not e and not opts.blind then return false, "none" end
		-- (Blind: repeated as long as any timeout it may reach could last, a hold's 30 days.)
		a.keep = e and WC.EndOf(e) or now + WC.HOLD_MAX
	end
	local seq = math.max(1, now - WC.SEQ_EPOCH, s.seq + 1)
	if seq > WC.MAX_SEQ then return false, "sequence" end
	s.seq, a.seq = seq, seq
	local msg = ActionWire(a)
	if not msg then return false, "size" end
	local dist = scope == "G" and "GUILD" or "CHANNEL"
	Apply(a)
	Send(dist, msg, "md:" .. seq, ActionPermit(a, msg, scope, dist))
	Remember(a)
	return true, scope
end

function WC.Delete(chat, entry, reason)
	if type(entry) ~= "table" then return false, "line" end
	local refs = WC.RefsFor(chat, entry)
	if not refs then return false, "line" end
	return WC.Act("D", entry.sender, { refs = refs, reason = reason })
end
function WC.Purge(name, reason) return WC.Act("P", name, { reason = reason }) end
function WC.Timeout(name, seconds, reason) return WC.Act("T", name, { seconds = seconds, reason = reason }) end
function WC.Lift(name, reason) return WC.Act("U", name, { reason = reason }) end

-- A report's evidence lines (The Watch's case page): canonical text, so the line is found by its
-- hash on every client that kept it (this client's own id where it has the line).
-- Without the id here (the line said while this client was away, or a history from before 1.1.6),
-- each client that holds the line finds it by its words and tombs it by its own id (ApplyDelete).
function WC.DeleteReported(name, lines, reason)
	local refs, ownIds = {}, {}
	local C = Live(ns.Channels)
	for _, line in ipairs(type(lines) == "table" and lines or {}) do
		if #refs >= WC.REFS_MAX then break end
		if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
			local chat = (C and C.TIERS and C.TIERS[line.tier]) and line.tier or "A"
			if not ownIds[chat] then
				ownIds[chat] = {}
				for _, e in ipairs(C and C.RawHistory and C.RawHistory(chat) or {}) do
					if type(e) == "table" and not e.del and Same(e.sender, name) and e.id ~= nil then ownIds[chat][Hash(e.text)] = tonumber(e.id) end
				end
			end
			local hash = Hash(line.text)
			refs[#refs + 1] = { chat = chat, id = ownIds[chat][hash], hash = hash }
		end
	end
	if #refs == 0 then return false, "line" end
	return WC.Act("D", name, { refs = refs, reason = reason })
end

-- Holds a guild action whose roster was stale, for the next scan.
local function Hold(dist, sender, text)
	for i = #held, 1, -1 do if Now() - held[i].t > WC.HELD_KEEP then table.remove(held, i) end end
	if #held >= WC.HELD_MAX then return false end
	held[#held + 1] = { dist = dist, sender = sender, text = text, t = Now() }
	stats.held = stats.held + 1
	return true
end

function WC.RetryHeld()
	local list = held
	held = {}
	for _, h in ipairs(list) do WC.Handle(h.dist, h.sender, h.text, true) end
end

-- Has the server-stamped sender any standing for a moderator's action in this scope (whoever he
-- names as its actor, he gives it or passes it on himself)? Cheap, before the shared budget. A
-- roster not fresh yet decides nothing here: the action waits for it (Hold), then is checked whole.
local function Standing(scope, sender)
	if scope == "G" then
		local W = TheWatch()
		if not (W and W.FreshRoster and W.FreshRoster()) then return true end
		return W.IsAuthorized ~= nil and W.IsAuthorized(sender) == true
	end
	return WC.ActorLevel(sender) >= LEVEL.mod
end

local function TakeAction(dist, sender, f, retry)
	if #f ~= 12 then return Refuse("shape", sender) end
	local op, scope = f[3], f[4]
	if (scope == "G" and dist ~= "GUILD") or (scope == "O" and dist ~= "CHANNEL") or (scope ~= "G" and scope ~= "O") then return Refuse("lane", sender) end
	if not retry and not Standing(scope, sender) then return Refuse("actor", sender) end
	if not Shared(retry) then return false, "rate" end
	local seq, at = Int(f[5], 1, WC.MAX_SEQ), Int(f[6], 1, WC.MAX_SEQ)
	if not seq or not at then return Refuse("shape", sender) end
	local now = Clock()
	if at > now + WC.DATE_AHEAD or now - at > WC.KEEP then return Refuse("time", sender) end
	local target = CharName(f[8])
	if not target or target ~= f[8] then return Refuse("name", sender) end
	if (op == "T" or op == "U") and IsKing(target) then return Refuse("king", sender) end
	local reason = f[12]
	if CleanReason(reason) ~= reason then return Refuse("reason", sender) end
	local by = f[11]
	if by ~= "-" then
		by = CharName(by)
		if not by or by ~= f[11] or (op ~= "T" and op ~= "U") or Same(by, sender) then return Refuse("by", sender) end
	end
	local actor = by ~= "-" and by or sender
	-- Our own action coming back: applied when given.
	if Same(actor, ns.me) then return false, "own" end
	local a = { op = op, scope = scope, seq = seq, at = at, target = target, by = actor, relay = by ~= "-" and sender or nil, reason = reason }
	if op == "D" then
		a.refs = ParseRefs(f[10])
		if not a.refs or f[9] ~= "-" then return Refuse("refs", sender) end
	elseif f[10] ~= "-" then
		return Refuse("refs", sender)
	end
	if op == "P" then
		a.window = Int(f[9], WC.PURGE_MIN, WC.PURGE_MAX)
		if not a.window then return Refuse("window", sender) end
	elseif op == "T" then
		local untilAt = Int(f[9], 0, WC.MAX_SEQ)
		if not untilAt or (untilAt ~= 0 and (untilAt <= at or untilAt - at > WC.MAX_TIMEOUT)) then return Refuse("duration", sender) end
		a.untilAt = untilAt
	elseif f[9] ~= "-" then
		return Refuse("arg", sender)
	end
	if scope == "G" then
		local guild = OwnGuild()
		if not guild or f[7] ~= guild then return Refuse("guild", sender) end
		a.guild = guild
	else
		a.guild = f[7] ~= "-" and f[7] or nil
	end
	-- Who may: from this client's own facts, the actor and (passed on) whoever passed it both. A
	-- relay carries only a word no higher than his own (a moderator never the King's, a councillor
	-- never the author's): it then weighs its actor's, the same on every client however it came,
	-- and no word above the relay's can be made up, shortened or replaced in its actor's name.
	local ok, why, weight = WC.Authority(actor, target, scope)
	if ok and a.relay then
		local rok, rwhy, rweight = WC.Authority(a.relay, target, scope)
		if not rok then ok, why = false, rwhy
		elseif (rweight or 0) < (weight or 0) then ok, why = false, "rank" end
	end
	if not ok then
		if why == "roster" and not retry then
			Hold(dist, sender, table.concat(f, "~"))
			return false, "held"
		end
		return Refuse(why, sender)
	end
	a.weight, a.role = weight, RoleOf(scope, weight)
	local applied, aw = Apply(a)
	if applied then
		if aw == "repeat" then stats.repeats = stats.repeats + 1 else stats.taken = stats.taken + 1 end
		return true, aw
	end
	return Refuse(aw, sender)
end

-- The target's own client, on the channel: about his own lines and timeout only (the server
-- stamps the sender: nobody else's lines can be withdrawn this way). A word of his own can only
-- restrict him, so every client takes it, with the lowest weight.
local function TakeSelf(dist, sender, f)
	if dist ~= "CHANNEL" or #f ~= 11 then return Refuse("shape", sender) end
	if Same(sender, ns.me) then return false, "own" end
	-- (Its own budgets: these never spend the moderators' shared one. 1.2.0: the shared S budget
	-- only once the sender has standing for it, a member of the Olympus guild his word names.)
	if not Rate(sender .. "#S", WC.RATE_SELF) then return false, "rate" end
	local op = f[4]
	local seq, at = Int(f[5], 1, WC.MAX_SEQ), Int(f[6], 1, WC.MAX_SEQ)
	local actor = CharName(f[8])
	local reason = f[11]
	if not seq or not at or not actor or actor ~= f[8] or CleanReason(reason) ~= reason then return Refuse("shape", sender) end
	local guild = f[7] ~= "-" and f[7] or nil
	local C = ns.Channels
	if not guild or not ns.IsFederation(guild) or not (C and C.VerifiedLevel and C.VerifiedLevel(sender, guild) >= 1) then
		return Refuse("guild", sender)
	end
	if not Budget(rateSelf, WC.RATE_SELF_ALL) then return false, "rate" end
	local now = Clock()
	if at > now + WC.DATE_AHEAD or now - at > WC.KEEP then return Refuse("time", sender) end
	local a = { op = op, scope = "S", seq = seq, at = at, target = sender, by = actor, reason = reason, weight = LEVEL.self, role = "S",
		guild = f[7] ~= "-" and f[7] or nil, confirmed = true, named = actor }
	if op == "D" then
		a.refs = ParseRefs(f[10])
		if not a.refs then return Refuse("refs", sender) end
	elseif op == "P" then
		a.window = Int(f[9], WC.PURGE_MIN, WC.PURGE_MAX)
		if not a.window then return Refuse("window", sender) end
	elseif op == "T" then
		local untilAt = Int(f[9], 0, WC.MAX_SEQ)
		if not untilAt or (untilAt ~= 0 and (untilAt <= at or untilAt - at > WC.MAX_TIMEOUT)) then return Refuse("duration", sender) end
		a.untilAt = untilAt
	elseif op ~= "U" then
		return Refuse("op", sender)
	end
	-- (His guild's own clients have the guild action already; the S entry under it is harmless.)
	local s = Store()
	local id = "S#" .. Key(sender) .. "#" .. Key(actor) .. "#" .. seq
	if s.applied[id] then return true, "repeat" end
	if op == "D" then ApplyDelete(sender, a.refs, at, "S")
	elseif op == "P" then ApplyPurge(sender, a.window, at, "S")
	elseif op == "T" then
		a.by = sender -- (kept as his own word; the actor named is shown, never trusted)
		a.named = actor
		KeepTimeout(a)
	elseif op == "U" then
		a.by = sender
		KeepLift(a)
	end
	s.applied[id] = at
	a.by = actor
	Record(a)
	ns.Fire("WATCHCHAT_CHANGED", op, sender)
	return true
end

-- Pages of a list: complete when every page of the same `at` from the same sender arrived.
local function Assemble(key, at, page, n, names, extra)
	local p = pages[key]
	if not p or p.at ~= at or p.n ~= n then p = { at = at, n = n, parts = {}, got = 0, t = Now() } pages[key] = p end
	if not p.parts[page] then p.parts[page], p.got = names, p.got + 1 end
	if extra ~= nil then p.extra = extra end
	if p.got < n then return nil end
	pages[key] = nil
	local out = {}
	for i = 1, n do
		for _, name in ipairs(p.parts[i]) do out[#out + 1] = name end
	end
	return out, p.extra
end

local function Names(s)
	if s == "" or s == "-" then return {} end
	local out = {}
	for part in (s .. ","):gmatch("([^,]*),") do
		local name = CharName(part)
		if not name or name ~= part then return nil end
		out[#out + 1] = name
	end
	return out
end

local function TakeWatchers(dist, sender, f)
	if dist ~= "GUILD" or #f ~= 9 then return Refuse("shape", sender) end
	local at, page, n = Int(f[4], 1, WC.MAX_SEQ), Int(f[6], 1, WC.PAGES_MAX), Int(f[7], 1, WC.PAGES_MAX)
	local guild = OwnGuild()
	if not at or not page or not n or page > n or not guild or f[5] ~= guild then return Refuse("shape", sender) end
	if at > Clock() + WC.DATE_AHEAD then return Refuse("time", sender) end
	-- Only the guild master's own client (his rank in this client's fresh roster, the server's word).
	local W = TheWatch()
	if not (W and W.FreshRoster and W.FreshRoster() and W.RosterRank and W.RosterRank(sender) == 0) then return Refuse("rank", sender) end
	if Same(sender, ns.me) then return false, "own" end
	if not Shared() then return false, "rate" end
	local justice = f[8]
	if justice ~= "-" then
		justice = CharName(justice)
		if not justice or justice ~= f[8] then return Refuse("justice", sender) end
	else
		justice = false
	end
	local names = Names(f[9])
	if not names then return Refuse("names", sender) end
	local all, j = Assemble("W#" .. Key(sender), at, page, n, names, justice)
	if not all then return true, "page" end
	if #all > WC.WATCHERS_MAX then return Refuse("full", sender) end
	local s = Store()
	local gk = Key(guild)
	local old = s.guildLists[gk]
	if type(old) == "table" and Same(old.by, sender) and (tonumber(old.at) or 0) > at then return false, "older" end
	s.guildLists[gk] = { by = sender, at = at, names = all, justice = j or nil, heard = Now() }
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeMods(dist, sender, f)
	if dist ~= "CHANNEL" or #f ~= 7 then return Refuse("shape", sender) end
	local at, page, n = Int(f[4], 1, WC.MAX_SEQ), Int(f[5], 1, WC.PAGES_MAX), Int(f[6], 1, WC.PAGES_MAX)
	if not at or not page or not n or page > n then return Refuse("shape", sender) end
	if at > Clock() + WC.DATE_AHEAD then return Refuse("time", sender) end
	if NamerLevel(sender) < LEVEL.council or WC.Barred("powers", sender) then return Refuse("namer", sender) end
	if Same(sender, ns.me) then return false, "own" end
	if not Shared() then return false, "rate" end
	local names = Names(f[7])
	if not names then return Refuse("names", sender) end
	local all = Assemble("O#" .. Key(sender), at, page, n, names)
	if not all then return true, "page" end
	if #all > WC.MODS_MAX then return Refuse("full", sender) end
	local s = Store()
	local key = Key(sender)
	local old = s.modLists[key]
	if type(old) == "table" and (tonumber(old.at) or 0) > at then old.heard = Now() return false, "older" end
	if type(old) ~= "table" and Count(s.modLists) >= WC.LISTS_MAX then
		local oldest, t
		for k, l in pairs(s.modLists) do if not t or (tonumber(l.heard) or 0) < t then oldest, t = k, tonumber(l.heard) or 0 end end
		if oldest then s.modLists[oldest] = nil end
	end
	local set = {}
	for _, name in ipairs(all) do set[Key(name)] = true end
	s.modLists[key] = { by = sender, at = at, names = all, set = set, heard = Now() }
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeAppeal(dist, sender, f)
	if dist ~= "CHANNEL" or #f ~= 8 then return Refuse("shape", sender) end
	if not CouncilSide() then return false, "audience" end
	local at, seq, actor, op, text = Int(f[4], 1, WC.MAX_SEQ), Int(f[6], 1, WC.MAX_SEQ), CharName(f[5]), f[7], f[8]
	if not at or not seq or not actor or actor ~= f[5] or (op ~= "T" and op ~= "D" and op ~= "P")
		or CleanReason(text, WC.APPEAL_MAX) ~= text then return Refuse("shape", sender) end
	if at > Clock() + WC.DATE_AHEAD or Clock() - at > WC.KEEP then return Refuse("time", sender) end
	if not Rate(sender .. "#A", 2) then return false, "rate" end
	local s = Store()
	local key = Key(sender) .. "#" .. Key(actor) .. "#" .. seq
	if s.appeals[key] then return true, "repeat" end
	-- (1.2.0: a few of his own at most; and an appeal about a sanction this client holds against
	-- him, by that actor and sequence, is never pushed out by one about nothing it holds. A
	-- councillor who logged in later still takes one about a sanction he never heard.)
	local mine = 0
	for _, e in pairs(s.appeals) do if Same(e.name, sender) then mine = mine + 1 end end
	if mine >= WC.APPEALS_EACH then return false, "full" end
	local held = false
	for _, e in ipairs(s.audit) do
		if e.op ~= "L" and e.seq == seq and Same(e.name, sender) and Same(e.by, actor) then held = true break end
	end
	if Count(s.appeals) >= WC.APPEALS_MAX then
		local function Oldest(ok)
			local k0, t
			for k, e in pairs(s.appeals) do if ok(e) and (not t or e.at < t) then k0, t = k, e.at end end
			return k0
		end
		local oldest = Oldest(function(e) return e.answer ~= nil end) or Oldest(function(e) return not e.held end)
			or (held and Oldest(function() return true end)) or nil
		if not oldest then return false, "full" end
		s.appeals[oldest] = nil
	end
	s.appeals[key] = { name = sender, actor = actor, seq = seq, at = at, op = op, text = text, held = held or nil }
	ns.Print(Gold(L.WATCHCHAT_APPEAL_IN:format(ns.DisplayName(sender) or sender)))
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeAnswer(dist, sender, f)
	if dist ~= "CHANNEL" or #f ~= 9 then return Refuse("shape", sender) end
	if NamerLevel(sender) < LEVEL.council or WC.Barred("powers", sender) then return Refuse("namer", sender) end
	if not Shared() then return false, "rate" end
	local at, target, actor, seq, verdict, reason = Int(f[4], 1, WC.MAX_SEQ), CharName(f[5]), CharName(f[6]), Int(f[7], 1, WC.MAX_SEQ), f[8], f[9]
	if not at or not target or not actor or not seq or (verdict ~= "K" and verdict ~= "L") or CleanReason(reason) ~= reason then return Refuse("shape", sender) end
	local s = Store()
	local key = Key(target) .. "#" .. Key(actor) .. "#" .. seq
	local appeal = s.appeals[key]
	if appeal then appeal.answer, appeal.answeredBy, appeal.answeredAt = verdict, sender, at end
	if ns.me and Same(target, ns.me) then
		local mine, op = s.record, nil
		for _, r in ipairs(mine) do if Same(r.by, actor) and r.seq == seq then r.appeal, op = verdict, r.op end end
		local role = WC.RoleText(RoleOf("O", NamerLevel(sender)), true)
		-- Told what is so on this client: a lift that did not reach his timeout (one from higher
		-- up, or his lift not here yet) is never told as lifted; a deleted line does not come back.
		local still = WC.SelfTimeout()
		local text
		if verdict ~= "L" then text = L.WATCHCHAT_APPEAL_KEPT_YOU:format(role, ReasonPart(reason))
		elseif op == "D" or op == "P" then text = L.WATCHCHAT_APPEAL_GRANTED_YOU:format(role, ReasonPart(reason))
		elseif still then text = L.WATCHCHAT_APPEAL_LIFTED_STILL:format(role, ReasonPart(reason), WC.TimeoutText(still))
		else text = L.WATCHCHAT_APPEAL_LIFTED_YOU:format(role, ReasonPart(reason)) end
		WC.TellDecision(text)
	end
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeDecision(dist, sender, f)
	if dist ~= "GUILD" or #f ~= 8 then return Refuse("shape", sender) end
	local at, target, jid, verdict = Int(f[4], 1, WC.MAX_SEQ), CharName(f[6]), Int(f[7], 1, WC.MAX_SEQ), f[8]
	local guild = OwnGuild()
	if not at or not target or not jid or (verdict ~= "U" and verdict ~= "D") or not guild or f[5] ~= guild then return Refuse("shape", sender) end
	local W = TheWatch()
	if not (W and W.IsAuthorized and W.IsAuthorized(sender)) then return Refuse("sender", sender) end
	if not Shared() then return false, "rate" end
	local s = Store()
	-- This guild's Watch (its Justice correspondent, its guild master, every Watcher): the King's
	-- word on the case, so whoever applies it finds "Apply the King's judgment" on the case's page
	-- for any authorized Watcher, not only the officer who sent the case. Kept for the case's 30 days at most.
	if ns.me and not Same(target, ns.me) and W.IsAuthorized(ns.me) then
		local vk = Key(guild) .. "#" .. jid
		if not s.verdicts[vk] then
			if Count(s.verdicts) >= WC.VERDICTS_MAX then
				local oldest, t
				for k, v in pairs(s.verdicts) do if not t or (tonumber(v.at) or 0) < t then oldest, t = k, tonumber(v.at) or 0 end end
				if oldest then s.verdicts[oldest] = nil end
			end
			s.verdicts[vk] = { target = target, jid = jid, verdict = verdict, at = at, guild = guild }
			ns.Fire("WATCH_CHANGED")
		end
		return true, "kept"
	end
	if not (ns.me and Same(target, ns.me)) then return false, "audience" end
	local key = Key(guild) .. "#" .. jid
	if s.toldJ[key] then return true, "repeat" end
	s.toldJ[key] = at
	s.record[#s.record + 1] = { op = "J", role = "G", at = at, untilAt = 0, reason = verdict == "U" and L.JUDGMENT_UPHELD or L.JUDGMENT_NOT_UPHELD, seq = jid }
	Trim(s.record, WC.RECORD_MAX)
	WC.TellDecision(verdict == "U" and L.WATCHCHAT_DECISION_UP or L.WATCHCHAT_DECISION_DOWN)
	return true
end

function WC.Handle(dist, sender, text, retry)
	if type(text) ~= "string" or #text > WC.MESSAGE_MAX then return Refuse("size") end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged()
		and not retry then return Refuse("unlogged", sender) end
	if dist ~= "GUILD" and dist ~= "CHANNEL" then return Refuse("lane", sender) end
	sender = CharName(sender)
	if not sender then return Refuse("sender") end
	local f = Split(text, 13)
	if not f or f[1] ~= "MD" or f[2] ~= "1" then return Refuse("shape", sender) end
	if not retry and not Rate(sender) then return false, "rate" end
	-- One who gives nothing (net-off, a timeout) sends nothing but his own word about himself.
	local op = f[3]
	if op == "D" or op == "P" or op == "T" or op == "U" then return TakeAction(dist, sender, f, retry) end
	if op == "S" then return TakeSelf(dist, sender, f) end
	if op == "W" then return TakeWatchers(dist, sender, f) end
	if op == "O" then return TakeMods(dist, sender, f) end
	if op == "A" then return TakeAppeal(dist, sender, f) end
	if op == "R" then return TakeAnswer(dist, sender, f) end
	if op == "J" then return TakeDecision(dist, sender, f) end
	return Refuse("op", sender)
end

if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("MD", function(dist, sender, text) WC.Handle(dist, sender, text) end) end

---------------------------------------------------------------------------
-- Lists: a guild master's Watchers (and his Justice correspondent), each namer's Olympus moderators
---------------------------------------------------------------------------

local function ListPages(prefix, names, budget)
	local out, cur = {}, {}
	local function Flush() out[#out + 1] = table.concat(cur, ",") cur = {} end
	for _, name in ipairs(names) do
		local trial = #cur > 0 and (table.concat(cur, ",") .. "," .. name) or name
		if #prefix + #trial > budget and #cur > 0 then Flush() end
		cur[#cur + 1] = name
	end
	if #cur > 0 or #out == 0 then Flush() end
	return out
end

local listsPending = false
function WC.SendWatchers(force)
	local s, guild, W = Store(), OwnGuild(), TheWatch()
	if not s or not guild or not (W and W.RosterRank and W.RosterRank(ns.me) == 0) then return false end
	local mine = s.myWatchers[Key(guild)]
	if type(mine) ~= "table" then return false end
	if not force and Now() - (tonumber(mine.sent) or -math.huge) < WC.LIST_EVERY then return false end
	mine.sent = Now()
	local at = math.max(math.floor(Clock()), (tonumber(mine.at) or 0))
	mine.at = at
	local justice = type(mine.justice) == "string" and mine.justice or "-"
	local parts = ListPages("MD~1~W~" .. at .. "~" .. guild .. "~1~1~" .. justice .. "~", mine.names or {}, WC.MESSAGE_MAX)
	if #parts > WC.PAGES_MAX then return false end
	for i, names in ipairs(parts) do
		Send("GUILD", "MD~1~W~" .. at .. "~" .. guild .. "~" .. i .. "~" .. #parts .. "~" .. justice .. "~" .. names, "mdw:" .. i)
	end
	return true
end

function WC.SendMods(force)
	local s = Store()
	if not s or not ns.me or NamerLevel(ns.me) < LEVEL.council or WC.Barred("powers") then return false end
	if not force and Now() - (tonumber(s.modsSent) or -math.huge) < WC.LIST_EVERY then return false end
	if #s.myMods == 0 and not s.modsAt then return false end -- nobody named yet
	s.modsSent = Now()
	local at = math.max(math.floor(Clock()), tonumber(s.modsAt) or 0)
	s.modsAt = at
	local parts = ListPages("MD~1~O~" .. at .. "~1~1~", s.myMods, WC.MESSAGE_MAX)
	if #parts > WC.PAGES_MAX then return false end
	for i, names in ipairs(parts) do Send("CHANNEL", "MD~1~O~" .. at .. "~" .. i .. "~" .. #parts .. "~" .. names, "mdo:" .. i) end
	return true
end

local function SendListsSoon()
	if listsPending then return end
	listsPending = true
	WC.after(3, "chat moderation lists", function()
		listsPending = false
		WC.SendWatchers(true)
		WC.SendMods(true)
	end)
end

-- The guild master names (or removes) a Watcher; `justice`: as his guild's Justice correspondent.
function WC.SetWatcher(input, on, justice)
	local guild, W, s = OwnGuild(), TheWatch(), Store()
	if not guild or not s or not (W and W.RosterRank and W.RosterRank(ns.me) == 0) then return false, "gm" end
	if WC.Barred("powers") then return false, "sanction" end
	local mine = s.myWatchers[Key(guild)] or { names = {} }
	s.myWatchers[Key(guild)] = mine
	mine.names = type(mine.names) == "table" and mine.names or {}
	if justice then
		if on == false or input == nil or input == "" or tostring(input):lower() == "none" then mine.justice = nil
		else
			local name = CharName(input, true)
			if not name then return false, "name" end
			if W.RosterRank(name) == nil then return false, "member" end
			if Same(name, ns.me) then return false, "self" end
			mine.justice = name
		end
		mine.at = math.floor(Clock())
		SendListsSoon()
		ns.Fire("WATCH_CHANGED")
		return true
	end
	local name = CharName(input, true)
	if not name then return false, "name" end
	local key = Key(name)
	for i, n in ipairs(mine.names) do
		if Key(n) == key then
			if on then return true, "already" end
			table.remove(mine.names, i)
			mine.at = math.floor(Clock())
			SendListsSoon()
			ns.Fire("WATCH_CHANGED")
			return true
		end
	end
	if not on then return false, "absent" end
	if Same(name, ns.me) then return false, "self" end
	if W.RosterRank(name) == nil then return false, "member" end
	if #mine.names >= WC.WATCHERS_MAX then return false, "full" end
	mine.names[#mine.names + 1] = name
	mine.at = math.floor(Clock())
	SendListsSoon()
	ns.Fire("WATCH_CHANGED")
	return true
end

-- The author, the King or a councillor names (or removes) an Olympus moderator in his own list.
function WC.SetMod(input, on)
	local s = Store()
	if not s or not ns.me or NamerLevel(ns.me) < LEVEL.council then return false, "namer" end
	if WC.Barred("powers") then return false, "sanction" end
	local name = CharName(input, true)
	if not name then return false, "name" end
	local key = Key(name)
	for i, n in ipairs(s.myMods) do
		if Key(n) == key then
			if on then return true, "already" end
			table.remove(s.myMods, i)
			s.modsAt = math.floor(Clock())
			SendListsSoon()
			ns.Fire("WATCH_CHANGED")
			return true
		end
	end
	if not on then return false, "absent" end
	if Same(name, ns.me) then return false, "self" end
	if #s.myMods >= WC.MODS_MAX then return false, "full" end
	s.myMods[#s.myMods + 1] = name
	s.modsAt = math.floor(Clock())
	SendListsSoon()
	ns.Fire("WATCH_CHANGED")
	return true
end

-- Every namer's list that counts here: { { by, names, own } }.
function WC.ModLists()
	local s, out = Store(), {}
	if not s then return out end
	if ns.me and NamerLevel(ns.me) >= LEVEL.council then out[#out + 1] = { by = ns.me, names = s.myMods, own = true } end
	local now = Now()
	for _, list in pairs(s.modLists) do
		if type(list) == "table" and not Same(list.by, ns.me) and NamerLevel(list.by) >= LEVEL.council
			and now - (tonumber(list.heard) or -math.huge) <= WC.LIST_FRESH then out[#out + 1] = { by = list.by, names = list.names } end
	end
	return out
end

---------------------------------------------------------------------------
-- Appeals and decisions: an appeal to the High Council; the person is told
-- the decision of a case in a pop-up.
---------------------------------------------------------------------------

-- An Olympus pop-up with a decision (an appeal's answer, the King's word on a case; and, later,
-- Hold Court's petitions: the seam).
function WC.TellDecision(text)
	ns.ShowDialog("OLYMPUS_WATCHCHAT_DECISION", text)
	if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	return true
end

-- The punished player appeals the sanction (by its actor and sequence) to the High Council.
function WC.Appeal(by, seq, text)
	local s = Store()
	if not s or not ns.me then return false, "member" end
	by, seq = CharName(by), tonumber(seq)
	text = CleanReason(text, WC.APPEAL_MAX)
	if not by or not seq or text == "" then return false, "text" end
	local found
	for _, r in ipairs(s.record) do if Same(r.by, by) and r.seq == seq then found = r end end
	if not found then return false, "record" end
	if found.op ~= "T" and found.op ~= "D" and found.op ~= "P" then return false, "record" end
	if found.appealed then return false, "already" end
	local msg = ("MD~1~A~%d~%s~%d~%s~%s"):format(math.floor(Clock()), by, seq, found.op, text)
	if #msg > WC.MESSAGE_MAX then return false, "size" end
	found.appealed = math.floor(Clock())
	Send("CHANNEL", msg, "mda:" .. seq)
	ns.Fire("WATCH_CHANGED")
	return true
end

-- A councillor answers an appeal: "K" keep, "L" lift. On a timeout his own lift goes first, with
-- his weight, even when this client holds none (a Watcher's timeout reached only that guild and
-- the player's own client): it ends there whatever his rank reaches, and a timeout from higher up
-- than his is refused here ("rank") before any answer goes. On a deleted line "L" is the council
-- finding for him (the words do not come back).
function WC.Answer(key, verdict, reason)
	local s = Store()
	local appeal = s and s.appeals[key]
	if not appeal or not CouncilSide() then return false, "appeal" end
	if WC.Barred("powers") then return false, "sanction" end
	if verdict ~= "K" and verdict ~= "L" then return false, "verdict" end
	if verdict == "L" and (appeal.op or "T") == "T" then
		local ok, why = WC.Act("U", appeal.name, { reason = reason, blind = true })
		if not ok then return false, why end
	end
	reason = CleanReason(reason)
	local msg = ("MD~1~R~%d~%s~%s~%d~%s~%s"):format(math.floor(Clock()), appeal.name, appeal.actor, appeal.seq, verdict, reason)
	if #msg > WC.MESSAGE_MAX then return false, "size" end
	appeal.answer, appeal.answeredBy, appeal.answeredAt = verdict, ns.me, math.floor(Clock())
	Send("CHANNEL", msg, "mdr:" .. key)
	ns.Fire("WATCH_CHANGED")
	return true
end

-- Judgment.lua: the King's final word on a case reached the officer's client that sent it. The
-- player is told over GUILD (his own client checks the sender in its roster), repeated for
-- DECISION_FOR while he may be away.
function WC.TellCase(target, jid, verdict)
	local s, guild = Store(), OwnGuild()
	target = CharName(target)
	if not s or not guild or not target or not tonumber(jid) or (verdict ~= "U" and verdict ~= "D") then return false end
	local key = Key(guild) .. "#" .. tostring(jid)
	if s.decisions[key] then return true end
	s.decisions[key] = { target = target, jid = tonumber(jid), verdict = verdict, guild = guild, at = math.floor(Clock()), sent = -math.huge }
	-- (This client's own copy of the King's word, as the guild's Watchers keep it from the message.)
	if not s.verdicts[key] then s.verdicts[key] = { target = target, jid = tonumber(jid), verdict = verdict, at = math.floor(Clock()), guild = guild } end
	if Count(s.decisions) > WC.DECISIONS_MAX then
		local oldest, t
		for k, d in pairs(s.decisions) do if not t or d.at < t then oldest, t = k, d.at end end
		if oldest then s.decisions[oldest] = nil end
	end
	if Same(target, ns.me) then return true end
	WC.SendDecision(key)
	return true
end

function WC.SendDecision(key)
	local s = Store()
	local d = s and s.decisions[key]
	if not d or OwnGuild() ~= d.guild then return false end
	d.sent = Now()
	return Send("GUILD", ("MD~1~J~%d~%s~%s~%d~%s"):format(d.at, d.guild, d.target, d.jid, d.verdict), "mdj:" .. key)
end

---------------------------------------------------------------------------
-- Blocked lines, counted per category for 7 days, never the text.
---------------------------------------------------------------------------

local function Day(t) return math.floor((tonumber(t) or Clock()) / 86400) end

function WC.CountBlocked(sender, cat)
	if type(sender) ~= "string" or sender == "" then return end
	local s = Store()
	if not s then return end
	local key = Key(sender)
	local e = s.blocked[key]
	if type(e) ~= "table" then
		if Count(s.blocked) >= WC.BLOCKED_SENDERS then
			local oldest, t
			for k, b in pairs(s.blocked) do if not t or (tonumber(b.last) or 0) < t then oldest, t = k, tonumber(b.last) or 0 end end
			if oldest then s.blocked[oldest] = nil end
		end
		e = { name = sender, c = {} }
		s.blocked[key] = e
	end
	e.last = math.floor(Clock())
	local day = Day()
	local c = e.c[cat] or {}
	e.c[cat] = c
	c[day] = (c[day] or 0) + 1
	for d in pairs(c) do if day - d >= WC.BLOCKED_DAYS then c[d] = nil end end
end

-- { [category] = n } over the last BLOCKED_DAYS for `name`, and the total.
function WC.BlockedCounts(name)
	local s = Store()
	local e = s and s.blocked[Key(name)]
	local out, total, today = {}, 0, Day()
	for cat, days in pairs(type(e) == "table" and e.c or {}) do
		for d, n in pairs(days) do
			if today - d < WC.BLOCKED_DAYS then out[cat] = (out[cat] or 0) + n total = total + n end
		end
	end
	return out, total
end

-- The severe-insult block at send (empty until a word list is approved): whole
-- words, folded as the block terms fold them (Filter.WordsOf). Its category, or nil.
function WC.Severe(text)
	if next(WC.SEVERE) == nil then return nil end
	local F = Live(ns.Filter)
	for _, w in ipairs(F and F.WordsOf and F.WordsOf(text) or {}) do
		if WC.SEVERE[w] then return WC.SEVERE[w] end
	end
	return nil
end

-- Channels.Send, ChatRooms.Send: such a line is refused, the player told, and it is counted.
function WC.RefuseSevere(text)
	local cat = WC.Severe(text)
	if not cat then return nil end
	if ns.me then WC.CountBlocked(ns.me, "severe") end
	ns.Print(Red(L.WATCHCHAT_SEVERE_REFUSED))
	return cat
end

---------------------------------------------------------------------------
-- Housekeeping: repeats (late logins), passing on, prune
---------------------------------------------------------------------------

function WC.Prune()
	local s = Store()
	if not s then return end
	local now, mono = Clock(), Now()
	for key, list in pairs(s.timeouts) do
		if type(list) ~= "table" then s.timeouts[key] = nil else
			for i = #list, 1, -1 do
				local e = list[i]
				if type(e) ~= "table" or not CharName(e.name) or type(e.at) ~= "number" or type(e.weight) ~= "number"
					or WC.EndOf(e) <= now then table.remove(list, i) end
			end
			if #list == 0 then s.timeouts[key] = nil end
		end
	end
	for key, list in pairs(s.lifts) do
		if type(list) ~= "table" then s.lifts[key] = nil else
			for i = #list, 1, -1 do
				local e = list[i]
				if type(e) ~= "table" or (tonumber(e.keep) or 0) <= now then table.remove(list, i) end
			end
			if #list == 0 then s.lifts[key] = nil end
		end
	end
	for i = #s.tombs, 1, -1 do
		local t = s.tombs[i]
		if type(t) ~= "table" or mono - (tonumber(t.t) or 0) > WC.TOMB_KEEP then table.remove(s.tombs, i) end
	end
	for k, at in pairs(s.applied) do if type(at) ~= "number" or now - at > WC.KEEP then s.applied[k] = nil end end
	for k, at in pairs(s.sentS) do if type(at) ~= "number" or now - at > WC.KEEP then s.sentS[k] = nil end end
	for k, at in pairs(s.toldJ) do if type(at) ~= "number" or now - at > WC.KEEP then s.toldJ[k] = nil end end
	for k, e in pairs(s.appeals) do if type(e) ~= "table" or now - (tonumber(e.at) or 0) > WC.KEEP then s.appeals[k] = nil end end
	for k, d in pairs(s.decisions) do if type(d) ~= "table" or now - (tonumber(d.at) or 0) > WC.DECISION_FOR then s.decisions[k] = nil end end
	for k, v in pairs(s.verdicts) do if type(v) ~= "table" or now - (tonumber(v.at) or 0) > WC.KEEP then s.verdicts[k] = nil end end
	for k, list in pairs(rates) do
		local live = false
		for _, t in ipairs(list) do if mono - t < 60 then live = true break end end
		if not live then rates[k] = nil end
	end
	for k, l in pairs(s.modLists) do
		if type(l) ~= "table" or type(l.set) ~= "table" or mono - (tonumber(l.heard) or 0) > WC.LIST_FRESH then s.modLists[k] = nil end
	end
	for _, list in ipairs({ s.audit, s.record }) do
		for i = #list, 1, -1 do if type(list[i]) ~= "table" or now - (tonumber(list[i].at) or 0) > WC.KEEP then table.remove(list, i) end end
	end
	for i = #s.actions, 1, -1 do
		local a = s.actions[i]
		local live = type(a) == "table" and type(a.at) == "number"
		if live and a.op == "T" then live = WC.EndOf(a) > now
		elseif live and a.op == "U" then live = (tonumber(a.keep) or a.at + WC.REPEAT) > now
		elseif live then live = now - a.at <= WC.DELETE_REPEAT_FOR end
		if not live then table.remove(s.actions, i) end
	end
	for k, p in pairs(pages) do if mono - p.t > 60 then pages[k] = nil end end
	for k, t in pairs(purgeGrace) do if t <= mono then purgeGrace[k] = nil end end
end

-- Another moderator's timeout nobody repeated for PASS_ON_AFTER: this client passes it on (with
-- `by`), when its player could give it himself in that scope; a deletion is never passed on.
local function PassOn(budget)
	local s = Store()
	local now, mono = Clock(), Now()
	for key, list in pairs(s.timeouts) do
		for _, e in ipairs(list) do
			if budget <= 0 then return budget end
			-- (Only a word no higher than this client's own: a moderator never carries the King's.)
			local may, _, mine = false, nil, nil
			if e.scope ~= "S" and not Same(e.by, ns.me) and mono - (tonumber(e.heard) or 0) >= WC.PASS_ON_AFTER + 2 * (jitter or 0) and WC.EndOf(e) > now
				and (e.scope ~= "G" or OwnGuild() == e.guild) then
				may, _, mine = WC.Authority(ns.me, e.name, e.scope)
			end
			if may and (mine or 0) >= (e.weight or 0) then
				local a = { op = "T", scope = e.scope, seq = e.seq, at = e.at, guild = e.guild, target = e.name, untilAt = e.untilAt,
					by = e.by, reason = e.reason }
				local msg = ActionWire(a, true)
				if msg then
					e.heard = mono
					Send(e.scope == "G" and "GUILD" or "CHANNEL", msg, "mdp:" .. key, ActionPermit(a, msg, e.scope, e.scope == "G" and "GUILD" or "CHANNEL"))
					budget = budget - 1
				end
			end
		end
	end
	return budget
end

function WC.Tick()
	WC.Prune()
	local s = Store()
	if not s or not ns.me or not ns.IsMember() then return end
	jitter = jitter or (WC.random(0, WC.JITTER))
	local budget, mono = WC.PER_TICK, Now()
	for _, a in ipairs(s.actions) do
		if budget <= 0 then break end
		local every = (a.op == "D" or a.op == "P") and WC.DELETE_REPEAT_EVERY or (WC.REPEAT + jitter)
		if mono - (tonumber(a.sent) or -math.huge) >= every and (a.scope ~= "G" or OwnGuild() == a.guild) and WC.Authority(ns.me, a.target, a.scope) then
			local msg = ActionWire(a)
			local dist = a.scope == "G" and "GUILD" or "CHANNEL"
			if msg then
				a.sent = mono
				Send(dist, msg, "md:" .. a.seq, ActionPermit(a, msg, a.scope, dist))
				budget = budget - 1
			end
		end
	end
	if budget > 0 then budget = PassOn(budget) end
	WC.SendWatchers(false)
	WC.SendMods(false)
	for key, d in pairs(s.decisions) do
		if not Same(d.target, ns.me) and mono - (tonumber(d.sent) or -math.huge) >= WC.DECISION_EVERY then WC.SendDecision(key) end
	end
	-- A guild timeout on this character: said again on the channel once a session (others abroad).
	local e = WC.SelfTimeout()
	if e and e.scope == "G" and not toldLogin then
		toldLogin = true
		local msg = SelfWire({ op = "T", seq = e.seq, at = e.at, guild = e.guild, by = e.by, untilAt = e.untilAt, reason = e.reason })
		if msg then Send("CHANNEL", msg, "mdst") end
	end
end

---------------------------------------------------------------------------
-- The Chat tab (ChatWindow.lua calls these: that file is at Lua's limit of locals)
---------------------------------------------------------------------------

-- A deleted line's body and its tooltip.
function WC.DeletedBody() return Grey(L.WATCHCHAT_DELETED) end
function WC.DeletedTip(tt, e)
	tt:AddLine(L.WATCHCHAT_DELETED, 0.7, 0.7, 0.7)
	tt:AddLine(L.WATCHCHAT_DELETED_TIP:format(Hour(tonumber(e.delAt) or 0), WC.RoleText(e.delRole, false)), 1, 1, 1, true)
end

-- Does a registered surface hold this chat (an army chat, a ChatRooms room this session kept)? A
-- provider's room (the crafting requests', later the Church's) or a fight room is the seam: its
-- lines are not this file's to delete yet.
function WC.HoldsChat(chat)
	for _, sf in ipairs(surfaces) do
		local ok, chats = pcall(sf.Chats)
		for _, c in ipairs(ok and type(chats) == "table" and chats or {}) do if c == chat then return true end end
	end
	return false
end

-- May this client act on the line (another player's, not deleted, one it may reach, in a chat
-- whose lines it may delete)?
function WC.CanModerateEntry(e, chat)
	if type(e) ~= "table" or e.del or e.mine or type(e.sender) ~= "string" then return false end
	if chat ~= nil and not WC.HoldsChat(chat) then return false end
	local C = Live(ns.Channels)
	if C and C.IsMe and C.IsMe(e.sender) then return false end
	return WC.CanModerate(e.sender) ~= nil
end

-- The dialogs, from a line (the Chat tab: the hover button or a right-click).
function WC.AskEntry(e, chat)
	if not WC.CanModerateEntry(e, chat) then return false end
	local preview = ns.Cut(Canonical(e.text), 90)
	ns.ShowDialog("OLYMPUS_WATCHCHAT_ACT", ns.DisplayName(e.sender) or e.sender, preview,
		{ name = CharName(e.sender), entry = e, chat = chat })
	return true
end

-- By name (a case page, the slash command): the timeout and lines' dialogs without a line.
function WC.AskName(name, what)
	name = CharName(name, true)
	if not name then return ns.Print(L.WATCH_BAD_NAME) end
	if not WC.CanModerate(name) then return ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(select(2, WC.CanModerate(name))))) end
	local data = { name = name }
	if what == "timeout" then return ns.ShowDialog("OLYMPUS_WATCHCHAT_TIME", ns.DisplayName(name) or name, nil, data) end
	if what == "purge" then data.op = "P"
	elseif what == "lift" then data.op = "U"
	else return false end
	return ns.ShowDialog("OLYMPUS_WATCHCHAT_WHY", WC.ConfirmText(data), nil, data)
end

function WC.WhyText(why)
	local key = "WATCHCHAT_WHY_" .. tostring(why or "?"):upper()
	local text = L[key]
	return type(text) == "string" and text ~= key and text or tostring(why or "?")
end

function WC.ConfirmText(data)
	local who = ns.DisplayName(data.name) or data.name or "?"
	if data.op == "D" then return L.WATCHCHAT_CONFIRM_D:format(who) end
	if data.op == "P" then return L.WATCHCHAT_CONFIRM_P:format(who) end
	if data.op == "U" then return L.WATCHCHAT_CONFIRM_U:format(who) end
	if data.op == "R" then return (data.verdict == "L" and L.WATCHCHAT_CONFIRM_RL or L.WATCHCHAT_CONFIRM_RK):format(who) end
	return L.WATCHCHAT_CONFIRM_T:format(who, Span(data.seconds))
end

-- The last step: checked again, sent.
function WC.Confirm(data, reason)
	if type(data) ~= "table" or not data.name then return false end
	local ok, why
	if data.op == "D" then
		if data.lines then ok, why = WC.DeleteReported(data.name, data.lines, reason)
		else ok, why = WC.Delete(data.chat, data.entry, reason) end
	elseif data.op == "P" then ok, why = WC.Purge(data.name, reason)
	elseif data.op == "T" then ok, why = WC.Timeout(data.name, data.seconds, reason)
	elseif data.op == "U" then ok, why = WC.Lift(data.name, reason)
	elseif data.op == "R" then ok, why = WC.Answer(data.key, data.verdict, reason)
	else return false end
	local who = ns.DisplayName(data.name) or data.name
	if not ok then ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(why))) return false end
	if data.op == "D" then ns.Print(Green(L.WATCHCHAT_DONE_D))
	elseif data.op == "P" then ns.Print(Green(L.WATCHCHAT_DONE_P:format(who)))
	elseif data.op == "T" then ns.Print(Green(L.WATCHCHAT_DONE_T:format(who, Span(data.seconds))))
	elseif data.op == "U" then ns.Print(Green(L.WATCHCHAT_DONE_U:format(who))) end
	return true
end

local function Why(data, op, seconds)
	if type(data) ~= "table" then return end
	data.op, data.seconds = op, seconds
	ns.ShowDialog("OLYMPUS_WATCHCHAT_WHY", WC.ConfirmText(data), nil, data)
end
WC.AskWhy = Why

local function Dialog(spec)
	spec.timeout, spec.whileDead, spec.hideOnEscape, spec.preferredIndex = 0, true, true, 3
	return spec
end
local function Clicked(fn)
	return function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("chat moderation", fn, data or (self and self.data)) end
	end
end
local function OK(fn)
	return function(self, data) ns.SafeCall("chat moderation", fn, data or (self and self.data)) end
end

if StaticPopupDialogs then
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_ACT"] = Dialog({
		text = L.WATCHCHAT_ACT_PROMPT,
		button1 = L.WATCHCHAT_DELETE_LINE, button2 = L.WATCHCHAT_TIMEOUT_BTN, button3 = L.WATCHCHAT_MORE,
		OnAccept = OK(function(data) Why(data, "D") end),
		OnCancel = Clicked(function(data) ns.ShowDialog("OLYMPUS_WATCHCHAT_TIME", ns.DisplayName(data.name) or data.name, nil, data) end),
		OnAlt = OK(function(data) ns.ShowDialog("OLYMPUS_WATCHCHAT_MORE", ns.DisplayName(data.name) or data.name, nil, data) end),
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_MORE"] = Dialog({
		text = L.WATCHCHAT_MORE_PROMPT,
		button1 = L.WATCHCHAT_PURGE_BTN, button2 = L.WATCHCHAT_LIFT_BTN, button3 = CANCEL or "Cancel",
		OnAccept = OK(function(data) Why(data, "P") end),
		OnCancel = Clicked(function(data) Why(data, "U") end),
		OnAlt = function() end,
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_TIME"] = Dialog({
		text = L.WATCHCHAT_TIME_PROMPT,
		button1 = L.WATCHCHAT_D_5M, button2 = L.WATCHCHAT_D_30M, button3 = L.WATCHCHAT_MORE,
		OnAccept = OK(function(data) Why(data, "T", WC.DURATIONS[1]) end),
		OnCancel = Clicked(function(data) Why(data, "T", WC.DURATIONS[2]) end),
		OnAlt = OK(function(data) ns.ShowDialog("OLYMPUS_WATCHCHAT_TIME2", ns.DisplayName(data.name) or data.name, nil, data) end),
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_TIME2"] = Dialog({
		text = L.WATCHCHAT_TIME_LADDER_PROMPT,
		button1 = L.WATCHCHAT_D_1H, button2 = L.WATCHCHAT_D_24H, button3 = L.WATCHCHAT_MORE,
		OnAccept = OK(function(data) Why(data, "T", WC.DURATIONS[3]) end),
		OnCancel = Clicked(function(data) Why(data, "T", WC.DURATIONS[4]) end),
		OnAlt = OK(function(data) ns.ShowDialog("OLYMPUS_WATCHCHAT_TIME3", ns.DisplayName(data.name) or data.name, nil, data) end),
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_TIME3"] = Dialog({
		text = L.WATCHCHAT_TIME_LONG_PROMPT,
		button1 = L.WATCHCHAT_D_7D, button2 = L.WATCHCHAT_D_HOLD, button3 = CANCEL or "Cancel",
		OnAccept = OK(function(data) Why(data, "T", WC.DURATIONS[5]) end),
		OnCancel = Clicked(function(data) Why(data, "T", WC.DURATIONS[6]) end),
		OnAlt = function() end,
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_WHY"] = Dialog({
		text = L.WATCHCHAT_WHY_PROMPT,
		button1 = L.WATCHCHAT_CONFIRM, button2 = CANCEL or "Cancel",
		hasEditBox = true, editBoxWidth = 320, maxLetters = WC.REASON_MAX,
		OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("") end end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			ns.SafeCall("chat moderation", WC.Confirm, data or self.data, eb and eb:GetText())
		end,
		EditBoxOnEnterPressed = function(self, data)
			local parent = self:GetParent()
			ns.SafeCall("chat moderation", WC.Confirm, data or (parent and parent.data), self:GetText())
			parent:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	})
	-- The timed-out player: what, by whom (the role), until when, why; and his appeal.
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_TIMED_OUT"] = Dialog({
		text = "%s",
		button1 = OKAY or "OK", button2 = L.WATCHCHAT_APPEAL_BTN,
		OnAccept = function() end,
		OnCancel = Clicked(function(data) ns.ShowDialog("OLYMPUS_WATCHCHAT_APPEAL", nil, nil, data) end),
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_APPEAL"] = Dialog({
		text = L.WATCHCHAT_APPEAL_PROMPT,
		button1 = SEND_LABEL or "Send", button2 = CANCEL or "Cancel",
		hasEditBox = true, editBoxWidth = 320, maxLetters = WC.APPEAL_MAX,
		OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("") end end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			data = data or self.data
			local ok, why = WC.Appeal(data and data.by, data and data.seq, eb and eb:GetText())
			ns.Print(ok and L.WATCHCHAT_APPEAL_SENT or L.WATCHCHAT_FAILED:format(WC.WhyText(why)))
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	})
	-- A councillor answers an appeal: lift it (his own lift goes with it) or keep it.
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_ANSWER"] = Dialog({
		text = L.WATCHCHAT_ANSWER_PROMPT,
		button1 = L.WATCHCHAT_APPEAL_LIFT, button2 = L.WATCHCHAT_APPEAL_KEEP, button3 = CANCEL or "Cancel",
		OnAccept = OK(function(data) data.verdict = "L" Why(data, "R") end),
		OnCancel = Clicked(function(data) data.verdict = "K" Why(data, "R") end),
		OnAlt = function() end,
		noCancelOnEscape = true,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_DECISION"] = Dialog({ text = "%s", button1 = OKAY or "OK", OnAccept = function() end })
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_NAME"] = Dialog({
		text = L.WATCHCHAT_NAME_PROMPT,
		button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
		hasEditBox = true, editBoxWidth = 240, maxLetters = 72,
		OnShow = function(self)
			local eb = self.editBox or self.EditBox
			if eb then
				local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
				eb:SetText(target and (ns.DisplayName(target) or target) or "")
			end
		end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			ns.SafeCall("chat moderation", WC.Named, data or self.data, eb and eb:GetText())
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	})
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_REMOVE"] = Dialog({
		text = L.WATCHCHAT_REMOVE_CONFIRM,
		button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = OK(function(data) WC.Named(data, data.name, false) end),
	})
end

-- The name dialog's answer: a Watcher, the Justice correspondent, or an Olympus moderator.
function WC.Named(data, input, on)
	if type(data) ~= "table" then return false end
	if on == nil then on = true end
	local ok, why
	if data.kind == "watcher" then ok, why = WC.SetWatcher(input, on)
	elseif data.kind == "justice" then ok, why = WC.SetWatcher(input, on, true)
	elseif data.kind == "mod" then ok, why = WC.SetMod(input, on)
	else return false end
	if not ok then ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(why))) return false end
	ns.Print(Green(on and L.WATCHCHAT_LIST_ADDED or L.WATCHCHAT_LIST_REMOVED))
	return true
end

-- The Chat tab's input hint and strip while timed out.
function WC.StripText()
	local e = WC.SelfTimeout()
	if not e then return nil end
	if (tonumber(e.untilAt) or 0) == 0 then return L.WATCHCHAT_STRIP_HOLD:format(WC.RoleText(e.role, true)) end
	return L.WATCHCHAT_STRIP:format(Hour(e.untilAt), WC.RoleText(e.role, true))
end

-- "Your moderation record" (the Chat tab's settings): roles only, and his own deleted words.
function WC.RecordLines()
	local s, out = Store(), {}
	if not s or #s.record == 0 then return out end
	out[#out + 1] = { header = true, text = Gold(L.WATCHCHAT_RECORD_TITLE) }
	for i = #s.record, math.max(1, #s.record - 9), -1 do
		local r = s.record[i]
		local what = L["WATCHCHAT_REC_" .. tostring(r.op)] or r.op
		if r.op == "T" then what = what:format((tonumber(r.untilAt) or 0) == 0 and L.WATCHCHAT_D_HOLD or Span(r.untilAt - r.at)) end
		local text = what .. "  " .. Grey(Stamp(r.at)) .. "  " .. Grey(WC.RoleText(r.role, true))
		local canAppeal = (r.op == "T" or r.op == "D" or r.op == "P") and not r.appealed and r.by ~= nil
		out[#out + 1] = { indent = true, text = text,
			onClick = canAppeal and function() ns.ShowDialog("OLYMPUS_WATCHCHAT_APPEAL", nil, nil, { by = r.by, seq = r.seq }) end or nil,
			tip = function(tt)
				tt:AddLine(what, 1, 0.82, 0)
				tt:AddLine(L.WATCHCHAT_REC_BY:format(WC.RoleText(r.role, true)), 1, 1, 1, true)
				if r.reason ~= "" then tt:AddLine(L.WATCH_REASON:format(r.reason), 1, 1, 1, true) end
				if r.words then tt:AddLine(L.WATCHCHAT_REC_WORDS:format(r.words), 0.7, 0.7, 0.7, true) end
				if r.appeal then tt:AddLine(r.appeal == "L" and L.WATCHCHAT_APPEAL_WAS_LIFTED or L.WATCHCHAT_APPEAL_WAS_KEPT, 1, 0.82, 0, true)
				elseif r.appealed then tt:AddLine(L.WATCHCHAT_APPEAL_WAITING, 0.7, 0.7, 0.7, true)
				elseif canAppeal then tt:AddLine(L.WATCHCHAT_APPEAL_CLICK, 0.6, 0.6, 0.6, true) end
			end }
	end
	out[#out].gap = true
	return out
end

---------------------------------------------------------------------------
-- The Watch's Chat moderation page (Watch.lua's "chat" section) and a case page's lines
---------------------------------------------------------------------------

local function ShownBy(name)
	local W = TheWatch()
	return W and W.ShownBy and W.ShownBy(name) or (ns.DisplayName(name) or "?")
end
local function Masked() return ns.CouncilMasked and ns.CouncilMasked() == true end

-- The author previewing a role (ViewAs.lua): the page as that role sees it, nothing on it acting.
local function Preview()
	local V = Live(ns.ViewAs)
	if V and type(V.Available) == "function" and V.Available() == true and type(V.Role) == "function" and V.Role() ~= "my" then return V end
	return nil
end

function WC.PageShown()
	local W = TheWatch()
	local V = Preview()
	if V then return (W ~= nil and W.DeskShown and W.DeskShown() == true) or (V.Allows and V.Allows("judgments") == true) or false end
	if not ns.IsMember() or WC.Barred("powers") then return false end
	return (W ~= nil and W.DeskShown and W.DeskShown() == true) or CouncilSide()
end

local function TimeoutRows(lines)
	local s = Store()
	local rows, now = {}, Clock()
	for _, list in pairs(s.timeouts) do
		for _, e in ipairs(list) do
			if WC.EndOf(e) > now and Applies(e, OwnGuild()) then rows[#rows + 1] = e end
		end
	end
	table.sort(rows, function(a, b) return WC.EndOf(a) < WC.EndOf(b) end)
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_TIMEOUTS_TITLE, right = Grey(tostring(#rows)) }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCHCHAT_TIMEOUTS_EMPTY) } end
	for i = 1, math.min(20, #rows) do
		local e = rows[i]
		local who = ns.DisplayName(e.name) or e.name
		local mayLift = WC.CanModerate(e.name) ~= nil
		lines[#lines + 1] = { indent = 1,
			text = Red(who) .. "  " .. Grey((tonumber(e.untilAt) or 0) == 0 and L.WATCHCHAT_D_HOLD or L.WATCHCHAT_UNTIL:format(Stamp(e.untilAt))),
			right = Grey(WC.RoleText(e.role, false)),
			onClick = mayLift and function() Why({ name = e.name }, "U") end or nil,
			tooltip = function(tt)
				tt:AddLine(who, 1, 0.82, 0)
				if e.scope == "S" then tt:AddLine(L.WATCHCHAT_CONFIRMED:format(who), 0.7, 0.7, 0.7, true)
				else tt:AddLine(L.WATCH_BY:format(ShownBy(e.by)), 0.7, 0.7, 0.7) end
				if e.via then tt:AddLine(L.WATCH_RECOVERED_VIA:format(ShownBy(e.via)), 0.7, 0.7, 0.7) end
				local reason = Masked() and L.NETOFF_REASON_HIDDEN or (e.reason ~= "" and e.reason or "-")
				tt:AddLine(L.WATCH_REASON:format(reason), 1, 1, 1, true)
				if mayLift then tt:AddLine(L.WATCHCHAT_CLICK_LIFT, 0.6, 0.6, 0.6, true) end
			end }
	end
	lines[#lines].gapAfter = true
end

local function WatcherRows(lines)
	local list = GuildList()
	local W = TheWatch()
	local gm = ns.me and W and W.RosterRank and W.RosterRank(ns.me) == 0
	local names = list and list.names or {}
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_WATCHERS_TITLE:format(#names, WC.WATCHERS_MAX),
		tooltip = function(tt) tt:AddLine(L.WATCHCHAT_WATCHERS_TITLE:format(#names, WC.WATCHERS_MAX), 1, 0.82, 0); tt:AddLine(L.WATCHCHAT_WATCHERS_TIP, 1, 1, 1, true) end }
	for _, name in ipairs(names) do
		lines[#lines + 1] = { indent = 1, text = ShownBy(name),
			onClick = gm and function() ns.ShowDialog("OLYMPUS_WATCHCHAT_REMOVE", ns.DisplayName(name) or name, nil, { kind = "watcher", name = name }) end or nil }
	end
	local justice = list and list.justice
	lines[#lines + 1] = { indent = 1, text = L.WATCHCHAT_JUSTICE:format(justice and ShownBy(justice) or Grey(L.WATCHCHAT_JUSTICE_NONE)),
		onClick = gm and function() ns.ShowDialog("OLYMPUS_WATCHCHAT_NAME", L.WATCHCHAT_JUSTICE_SET, nil, { kind = "justice" }) end or nil,
		tooltip = function(tt) tt:AddLine(L.WATCHCHAT_JUSTICE_SET, 1, 0.82, 0); tt:AddLine(L.WATCHCHAT_JUSTICE_TIP, 1, 1, 1, true) end }
	if gm and #names < WC.WATCHERS_MAX then
		lines[#lines + 1] = { indent = 1, text = Green(L.WATCHCHAT_WATCHERS_ADD),
			onClick = function() ns.ShowDialog("OLYMPUS_WATCHCHAT_NAME", L.WATCHCHAT_WATCHERS_ADD, nil, { kind = "watcher" }) end }
	end
	lines[#lines].gapAfter = true
end

local function ModRows(lines)
	for _, list in ipairs(WC.ModLists()) do
		lines[#lines + 1] = { header = true, text = list.own and L.WATCHCHAT_MODS_TITLE:format(#list.names, WC.MODS_MAX)
			or L.WATCHCHAT_MODS_OTHERS:format(ShownBy(list.by)),
			tooltip = function(tt) tt:AddLine(L.WATCHCHAT_MODS_TIP, 1, 1, 1, true) end }
		for _, name in ipairs(list.names) do
			lines[#lines + 1] = { indent = 1, text = ns.DisplayName(name) or name,
				onClick = list.own and function() ns.ShowDialog("OLYMPUS_WATCHCHAT_REMOVE", ns.DisplayName(name) or name, nil, { kind = "mod", name = name }) end or nil }
		end
		if list.own and #list.names < WC.MODS_MAX then
			lines[#lines + 1] = { indent = 1, text = Green(L.WATCHCHAT_MODS_ADD),
				onClick = function() ns.ShowDialog("OLYMPUS_WATCHCHAT_NAME", L.WATCHCHAT_MODS_ADD, nil, { kind = "mod" }) end }
		end
		lines[#lines].gapAfter = true
	end
end

local function AppealRows(lines)
	local s = Store()
	local list = {}
	for key, e in pairs(s.appeals) do list[#list + 1] = { key = key, e = e } end
	table.sort(list, function(a, b) return a.e.at > b.e.at end)
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_APPEALS_TITLE, right = Grey(tostring(#list)) }
	if #list == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCHCHAT_APPEALS_EMPTY) } end
	for i = 1, math.min(10, #list) do
		local key, e = list[i].key, list[i].e
		local who = ShownBy(e.name)
		local state = e.answer == "L" and Green(L.WATCHCHAT_APPEAL_WAS_LIFTED) or e.answer == "K" and Grey(L.WATCHCHAT_APPEAL_WAS_KEPT) or Gold(L.WATCHCHAT_APPEAL_OPEN)
		lines[#lines + 1] = { indent = 1, text = who .. "  " .. state, right = Grey(ns.Ago(e.at)),
			onClick = not e.answer and function() ns.ShowDialog("OLYMPUS_WATCHCHAT_ANSWER", who, nil, { key = key, name = e.name }) end or nil,
			tooltip = function(tt)
				tt:AddLine(L.WATCHCHAT_APPEAL_FROM:format(who), 1, 0.82, 0)
				tt:AddLine(L.WATCH_BY:format(ShownBy(e.actor)), 0.7, 0.7, 0.7)
				tt:AddLine(Masked() and L.NETOFF_REASON_HIDDEN or e.text, 1, 1, 1, true)
				if not e.answer then tt:AddLine(L.WATCHCHAT_APPEAL_ANSWER_TIP, 0.6, 0.6, 0.6, true) end
			end }
	end
	lines[#lines].gapAfter = true
end

local function BlockedRows(lines)
	local s = Store()
	local list = {}
	for _, e in pairs(s.blocked) do
		local counts, total = WC.BlockedCounts(e.name)
		if total > 0 then list[#list + 1] = { name = e.name, counts = counts, total = total } end
	end
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.total > b.total end)
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_BLOCKED_TITLE, right = Grey(tostring(#list)),
		tooltip = function(tt) tt:AddLine(L.WATCHCHAT_BLOCKED_TITLE, 1, 0.82, 0); tt:AddLine(L.WATCHCHAT_BLOCKED_TIP, 1, 1, 1, true) end }
	for i = 1, math.min(10, #list) do
		local parts = {}
		for _, cat in ipairs(WC.CATEGORIES) do
			if list[i].counts[cat] then parts[#parts + 1] = L["WATCHCHAT_CAT_" .. cat:upper()] .. " " .. list[i].counts[cat] end
		end
		lines[#lines + 1] = { indent = 1, text = ShownBy(list[i].name), right = Grey(table.concat(parts, ", ")) }
	end
	lines[#lines].gapAfter = true
end

local function AuditRows(lines)
	local s = Store()
	local rows = {}
	if CouncilSide() then for _, e in ipairs(s.audit) do rows[#rows + 1] = e end end
	local W = TheWatch()
	if W and W.CanRead and W.CanRead() and W.Audit then
		for _, e in ipairs(W.Audit()) do if WC.AUDIT_OPS[e.op] then rows[#rows + 1] = e end end
	end
	table.sort(rows, function(a, b) return (a.at or 0) > (b.at or 0) end)
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_AUDIT_TITLE, right = Grey(tostring(#rows)) }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCHCHAT_AUDIT_EMPTY) } end
	for i = 1, math.min(15, #rows) do
		local e = rows[i]
		local label = (L["WATCHCHAT_OP_" .. tostring(e.op)] or "%s"):format(ShownBy(e.name))
		lines[#lines + 1] = { indent = 1, text = label, right = Grey(ns.Ago(e.at)),
			tooltip = function(tt)
				tt:AddLine(label, 1, 0.82, 0)
				if e.scope == "S" then tt:AddLine(L.WATCHCHAT_CONFIRMED:format(ShownBy(e.name)), 0.7, 0.7, 0.7, true) end
				tt:AddLine(L.WATCH_BY:format(ShownBy(e.by)), 0.7, 0.7, 0.7)
				if e.via then tt:AddLine(L.WATCH_RECOVERED_VIA:format(ShownBy(e.via)), 0.7, 0.7, 0.7) end
				if e.op == "T" then tt:AddLine((tonumber(e.untilAt) or 0) == 0 and L.WATCHCHAT_D_HOLD or L.WATCHCHAT_UNTIL:format(Stamp(e.untilAt)), 1, 0.35, 0.35) end
				tt:AddLine(L.WATCH_REASON:format(Masked() and L.NETOFF_REASON_HIDDEN or ((e.reason or "") ~= "" and e.reason or "-")), 1, 1, 1, true)
				-- The words deleted, as this client kept them: never on the King's stream, through the block terms.
				if e.text and e.text ~= "" and not Masked() then
					local shown = W and W.FilterText and W.FilterText(e.text) or e.text
					tt:AddLine(L.WATCHCHAT_REC_WORDS:format(shown), 0.7, 0.7, 0.7, true)
				end
			end }
	end
end
WC.AUDIT_OPS = { D = true, P = true, T = true, L = true }

function WC.PageLines()
	local lines = {}
	if not WC.PageShown() then return lines end
	local W = TheWatch()
	local desk = W ~= nil and W.DeskShown and W.DeskShown() == true
	lines[#lines + 1] = { header = true, text = "|TInterface\\Icons\\INV_Misc_Eye_01:0|t " .. L.WATCHCHAT_PAGE }
	lines[#lines + 1] = { text = Grey(L.WATCHCHAT_PAGE_SCOPE), gapAfter = true }
	TimeoutRows(lines)
	if desk and OwnGuild() then WatcherRows(lines) end
	if CouncilSide() then
		ModRows(lines)
		AppealRows(lines)
	end
	BlockedRows(lines)
	AuditRows(lines)
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { indent = 1, text = Grey(L.WATCHCHAT_LIMITS) }
	local V = Preview()
	if V and type(V.Inert) == "function" then return V.Inert(lines) end
	return lines
end

-- A case page's action lines (The Watch's CaseLines): delete the reported lines, his recent lines,
-- a timeout, a lift; and, on a case the King upheld, the Justice correspondent's "apply".
function WC.CaseLines(c)
	local out = {}
	if type(c) ~= "table" or not c.target then return out end
	local target = c.target
	if not WC.CanModerate(target) then return out end
	local reported = {}
	for _, r in ipairs(c.reports or {}) do
		for i = 1, tonumber(r.n) or 0 do if r.lines and r.lines[i] then reported[#reported + 1] = r.lines[i] end end
	end
	if #reported > 0 then
		out[#out + 1] = { indent = 1, text = Gold(L.WATCHCHAT_CASE_DELETE:format(math.min(#reported, WC.REFS_MAX))),
			onClick = function() Why({ name = target, lines = reported }, "D") end }
	end
	out[#out + 1] = { indent = 1, text = Gold(L.WATCHCHAT_PURGE_BTN), onClick = function() Why({ name = target }, "P") end }
	if IsKing(target) then return out end -- (never a timeout on the King: WC.Act)
	out[#out + 1] = { indent = 1, text = Gold(L.WATCHCHAT_TIMEOUT_BTN), onClick = function() WC.AskName(target, "timeout") end }
	if WC.TimeoutOf(target) then out[#out + 1] = { indent = 1, text = Gold(L.WATCHCHAT_LIFT_BTN), onClick = function() Why({ name = target }, "U") end } end
	return out
end

-- The King's upheld word on a case about `target` in this guild, as this client heard it (its own
-- case's escalation, Judgment.lua, or the officer's word to the player over GUILD, MD~1~J), not
-- applied yet: { jid, at } or nil.
function WC.KingUpheld(target)
	local s, guild = Store(), OwnGuild()
	if not s or not guild or type(target) ~= "string" then return nil end
	local best
	for _, v in pairs(s.verdicts) do
		if type(v) == "table" and v.verdict == "U" and not v.applied and Same(v.target, target) and Key(v.guild) == Key(guild)
			and (not best or (tonumber(v.at) or 0) > (tonumber(best.at) or 0)) then best = v end
	end
	return best
end

-- The King's judgment on `target` applied (Watch.lua: a warning given on him after it): the line
-- goes from the case's page on this client.
function WC.JudgmentApplied(target)
	local s = Store()
	if not s or type(target) ~= "string" then return end
	for _, v in pairs(s.verdicts) do if type(v) == "table" and Same(v.target, target) then v.applied = true end end
end

-- May this client apply the King's upheld judgment on a case (the guild's Justice
-- correspondent; with none named, its guild master; the author always)?
function WC.MayApplyJudgment()
	if not ns.me then return false end
	if IsAuthor(ns.me) then return true end
	local justice = WC.Justice()
	if justice then return Same(justice, ns.me) end
	local W = TheWatch()
	return W ~= nil and W.RosterRank and W.RosterRank(ns.me) == 0
end

---------------------------------------------------------------------------
-- Commands: /oly watch timeout|purge|watchers|justice|mods|chat
---------------------------------------------------------------------------

local SECONDS = { ["5m"] = 300, ["30m"] = 1800, ["1h"] = LADDER[2], ["24h"] = LADDER[3], ["1d"] = LADDER[3], ["7d"] = LADDER[4], hold = 0, forever = 0 }

function WC.Slash(verb, rest)
	rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if verb == "timeout" then
		local body, reason = rest:match("^([^:]*):%s*(.*)$")
		body, reason = body or rest, reason or ""
		local name, span = body:match("^(.-)%s+(%S+)%s*$")
		if not name then return ns.Print(L.WATCHCHAT_USAGE) end
		span = span:lower()
		if span == "lift" then
			local ok, why = WC.Lift(name, reason)
			return ok and ns.Print(Green(L.WATCHCHAT_DONE_U:format(name))) or ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(why)))
		end
		local seconds = SECONDS[span]
		if not seconds then return ns.Print(L.WATCHCHAT_USAGE) end
		local ok, why = WC.Timeout(name, seconds, reason)
		return ok and ns.Print(Green(L.WATCHCHAT_DONE_T:format(name, Span(seconds)))) or ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(why)))
	elseif verb == "purge" then
		local name, reason = rest:match("^([^:]*):%s*(.*)$")
		local ok, why = WC.Purge(name or rest, reason or "")
		return ok and ns.Print(Green(L.WATCHCHAT_DONE_P:format(name or rest))) or ns.Print(L.WATCHCHAT_FAILED:format(WC.WhyText(why)))
	elseif verb == "watchers" or verb == "mods" then
		local sub, name = rest:match("^(%S+)%s*(.-)$")
		sub = (sub or ""):lower()
		if sub ~= "add" and sub ~= "remove" then return ns.Print(L.WATCHCHAT_USAGE) end
		return WC.Named({ kind = verb == "watchers" and "watcher" or "mod" }, name, sub == "add")
	elseif verb == "justice" then
		return WC.Named({ kind = "justice" }, rest, rest:lower() ~= "none" and rest ~= "")
	end
	ns.Print(L.WATCHCHAT_USAGE)
	return false
end

---------------------------------------------------------------------------
-- The surfaces of 1.1.6: the three Olympus chats and ChatRooms' own rooms
---------------------------------------------------------------------------

WC.RegisterSurface({
	key = "channels",
	Chats = function() return { "A", "C", "L" } end,
	Lines = function(tier)
		local C = Live(ns.Channels)
		return C and C.RawHistory and C.RawHistory(tier) or {}
	end,
	Changed = function(tier) ns.Fire("CHAT_CHANGED", tier) end,
})
WC.RegisterSurface({
	key = "rooms",
	Chats = function()
		local R = Live(ns.ChatRooms)
		return R and R.KeptRooms and R.KeptRooms() or {}
	end,
	Lines = function(id)
		local R = Live(ns.ChatRooms)
		return R and R.RawHistory and R.RawHistory(id) or {}
	end,
	Changed = function(id) ns.Fire("CHAT_ROOM_CHANGED", id) end,
})

function WC.Stats() return stats end

function WC.ResetForTests()
	wipe(rates); wipe(rateAll); wipe(rateSelf); wipe(purgeGrace); wipe(held); wipe(pages); wipe(printed); wipe(printedOrder)
	lastPopup, toldLogin, listsPending, jitter = -math.huge, false, false, nil
	for k in pairs(stats) do stats[k] = 0 end
end

ns.On("DATA_CHANGED", function() if #held > 0 then WC.RetryHeld() end end)
ns.On("LOGIN", function()
	WC.Prune()
	if ns.Every then ns.Every(60, "chat moderation", function() WC.Tick() end) end
	-- Told at login while a timeout is on him (once the guild and the lists are known).
	WC.after(30, "chat moderation notice", function()
		local e = WC.SelfTimeout()
		if e then WC.TellTimeout(e, true) end
	end)
end)
