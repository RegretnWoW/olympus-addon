local ADDON, ns = ...
local L = ns.L

-- Net-off (1.1, Fern's requests #32 and #33): the King, his Steward, a Hand (the King's list or a
-- Steward's) or a High Councillor of the author's signed list gives a word, with a reason and the
-- time, on one of two things:
--   a character (c): every honest client hides that character on every addon surface: the chats
--     (and their history), the pinned line (Channels.Pin), decrees, layers and hop offers, Vox Populi (questions and votes), the
--     court's queue, and (1.1, Konig's review) the King's week (entries, sheets and signups), the
--     Board (flags and camps), the crafters' board (listings, answers and recipe lists), and the
--     elite borders and nameplate marks (Borders.lua). The names that character's player linked
--     as alts (Alts.lua, confirmed on each character) are hidden with it. The rest of the guild,
--     and the census, stay.
--   a guild (g): while it is off, honest clients stop sending and showing that guild's census,
--     map, hop, decrees, Vox and addon channels, and the rest above: its members' own clients
--     send none of them, and every client drops what still comes. Blizzard's guild chat and Guild
--     window stay up (the guild's own addon messages over GUILD too, but its master's pinned line,
--     hidden with its chats: Channels.Pin). One guild at a time: there
--     is no switch for the whole realm, and never the King's guild.
-- The same people put either back on.
--   O1~<c|g>~<1 off|0 on>~<server time>~<Name-Realm or Guild>~<by Name-Realm>~<reason>
-- Its words travel with the logged API, as a chat line's do (the server keeps them, so abuse
-- can be reported), one word per message. Every client keeps, on each name, the word from
-- highest up (its weight: its giver's rank, the King 3, a Steward 2, a Hand or a councillor 1;
-- no word replaces one from higher up, whatever its date: Konig's review of 1.1), and among
-- words of the same weight the newest (by the server's clock; on the same second the King's
-- own, else the one taking the name off, else by its giver's name: every client keeps the same
-- one), and takes a word only from someone who may give one now, as this client knows them (the
-- server stamps every sender's name): the King by his pinned name, a Steward of the signed titles
-- list, a Hand of the King's list or a Steward's, a councillor of the signed council list; never
-- a name that is off itself. A word one of them passes on for another (only a modified client
-- does: an honest one repeats its own words alone) is taken only while its giver may give one
-- too, weighs no more than whoever passed it on, and shows who did (the server's name): nobody
-- writes a word in someone else's name unseen. Each giver's client repeats his own words for
-- late logins, never anyone else's (1.1 review: a word passed on in the King's name went out
-- from his client as his own), every REPEAT (longer when the list is long: the army repeats
-- REPEATS_A_MINUTE words a minute at most), and not once he may no longer give one (it lapses;
-- so does a word whose giver was not online to repeat it for STALE). A word taking a name off
-- lapses OFF_KEEP after it was given (given again, it starts over); one putting a name back on
-- is kept and repeated for ON_KEEP, so an older word never comes back.
-- Among those who give words, only a word from higher up reaches one of them (the King above a
-- Steward, a Steward above the Hands and councillors): a Hand or a councillor never hides the
-- Steward, another Hand or another councillor. And no word replaces one from higher up (Take):
-- a Hand or a councillor never puts back one the King or a Steward hid, nor hides again one the
-- King showed again; nor does a Steward undo the King's word. Nor does a word push one from
-- higher up out of a full list (MakeRoom), nor hide a name through another name of its player
-- (a linked alt, or the same name on another realm of the group) when the name's own word
-- weighs more, or as much and is newer (Hidden, Character): 1.1, Konig's review.
-- What it is not: /oly block stays one client's and one player's, and nothing here uninvites,
-- demotes, or writes Blizzard's ignore list. It never aims at the pinned King (his name in any
-- case) or his guild. It knows nothing of the treasury or of payments, and no treasury code
-- calls it (tests/run.lua proves it). A modified client can ignore it.
-- 1.1.6: a guild's word with notice (exile). The same people give it, on one guild:
--   O2~<1 given|0 cancelled>~<server time>~<its time>~<Guild>~<by Name-Realm>~<reason>
-- its time 30 or 60 minutes after it was given (EXILE_MIN to EXILE_MAX taken). Until then that
-- guild's members see a parchment with the countdown: leave the guild, or it is taken off the
-- network at that time. At its time every client that holds it takes it as its giver's own guild
-- word (O1, dated its time), whether or not he is online then, and his client sends that word too,
-- for the clients before 1.1.6 (they know no O2 and leave it alone, so they follow only once his
-- client is online; nor does a client that logs in while he is away hear it: only his client
-- repeats it). Its giver, or someone from higher up, cancels it before its time (the same
-- message, 0, naming that time): it then never applies, and where it applied before the cancel
-- came it is taken back. The canceller's client repeats its cancel until the word goes from every
-- list (EXILE_KEEP after its time), and answers the word whenever it hears it: a giver who was
-- away when it came may log in after its time. His client waits WARMUP online before it applies
-- a word it held from an earlier session, so the cancel finds it first; and every client that
-- holds the cancel refuses the word it would have become (O1). A timed word is taken only from
-- its giver's own client (or its canceller's: the server stamps the sender), never passed on; it
-- weighs its giver's rank, never replaces one from higher up nor applies over one, and among
-- words of the same weight the newest wins. One per guild. It is the net-off word its giver
-- chose, at the time he chose, and nothing more: nobody leaves the guild by it.

local Moderation = {}
ns.Moderation = Moderation

Moderation.KINDS = { c = true, g = true } -- what a word may aim at: a character, a guild (no third)
Moderation.MAX = { c = 500, g = 200 }     -- words kept per kind (full: the oldest "on" word goes; for the
                                          -- King's own word, the oldest word not his; never one from
                                          -- higher up than the new word: MakeRoom)
Moderation.REPEAT = 300           -- an issuer's client repeats each word this long after it was last heard
Moderation.JITTER = 90            -- ...and up to this much later, its own draw (the others' repeat first)
Moderation.PER_TICK = 3           -- words one client repeats a minute at most
Moderation.REPEATS_A_MINUTE = 20  -- the army's repeats of the list a minute at most: a longer list is repeated less often
Moderation.OFF_KEEP = 30 * 86400  -- a word taking a name off lapses this long after it was given, on every client
Moderation.ON_KEEP = 30 * 86400   -- a word putting a name back on is kept (and repeated) this long (never less than OFF_KEEP)
Moderation.ON_EVERY = 1800        -- ...repeated this often
Moderation.STALE = 3 * 86400      -- an "off" word nobody repeated for this long lapses on a client that
                                  -- gives none (an issuer's own client keeps it; it repeats it after WARMUP)
Moderation.WARMUP = 600           -- an issuer's client online this long before it repeats a word it held unheard
Moderation.DATE_AHEAD = 60        -- a word dated further ahead of the server's clock is not taken
Moderation.REASON_MAX = 80        -- bytes of a reason
Moderation.GUILDS_KNOWN = 3000    -- senders whose guild this client remembers (the hop's whispers name none)
-- 1.1.6: a guild's word with notice (O2).
Moderation.EXILE_DELAYS = { 1800, 3600 } -- the notice its giver picks: 30 or 60 minutes
Moderation.EXILE_MIN = 1800       -- the notice a timed word gives, at least...
Moderation.EXILE_MAX = 3600       -- ...and at most (any between is taken: a later version may offer another)
Moderation.EXILE_LATE = 300       -- a timed word first heard this long after its time is not taken (by then it is an O1 word)
Moderation.EXILE_KEEP = 86400     -- a timed word, or its cancel, is kept this long after its time (its repeats find it)
Moderation.EXILE_REPEAT = 300     -- its giver's client repeats it this often until its time; its canceller's, the cancel until it goes
Moderation.EXILE_MAX_KEPT = 50    -- timed words kept, one per guild
-- What a client whose own character or guild is off stops sending (the receivers drop it anyway):
-- chat lines, decrees, layer announcements, hop asks, offers and answers, Vox votes; and (1.1,
-- Konig's review) its signups to the King's week (Y2), its flags and camps on the Board (G1), its
-- crafter's listing, answers and recipe lists (W1, WA, WL), and the Throne's calls to the army,
-- the week's entries among them (T1 of a kind in King.HIDDEN_CALLS: its lists still go, and so
-- does a setter's cancel of his own entry on the week, 1.1 review). (Its
-- census report: Comm.Broadcast.) The guild's own hello and key over GUILD go on, but (1.1.6) not
-- a guild master's Vox question to his guild nor its results (Y3, as the Throne's T1~V and T1~E
-- in HIDDEN_CALLS).
Moderation.BLOCKED = { M1 = true, D1 = true, L1 = true, LQ = true, LO = true, LR = true, LN = true, LX = true, LY = true, Y1 = true, Y2 = true, G1 = true,
	Y3 = true,
	W1 = true, WA = true, WL = true,
	-- A removed client neither asks for nor relays signed write authority. Existing clients still
	-- fail closed from the one-way boundary they already accepted.
	H2 = true, H3 = true,
	-- The Watch's guild-private moderation actions, and (1.1.6) the players' reports to it, and its
	-- chat moderation (WatchChat.lua: deletions, timeouts, the Watchers' and moderators' lists).
	MW = true, MR = true, MD = true,
	-- 1.2, the Blood Arena: its fight-room lines, bet slips, deposits, sign-ups and challenges, its
	-- profile, its level-race claims, and Farkle's invitations, arbiter asks and public tables; and
	-- matchmaking's asks, offers and answers (AM, the design: a net-off player sends none).
	-- Never a player's own obligations (AW, ZX, ZR, ZT, ZF, KD): a net-off player's result, debt
	-- marks and receipts still go out, and receivers ignore a net-off witness's AW (Moderation.Hides).
	EC = true, BS = true, ZD = true, AS = true, AP = true, IL = true, KI = true, KO = true, KN = true, KS = true,
	AM = true }

Moderation.random = math.random -- tests

local stats = { taken = 0, older = 0, same = 0, refused = 0, unlogged = 0, dropped = 0, blocked = 0, reports = 0 }
local toldMe = {}      -- [kind .. key .. at] = true: the notice about us was printed
local toldExile = {}   -- [guild key .. at] = true: the parchment about our guild's timed word was shown
local sentNow = {}     -- [guild key .. at] = true: a timed word this client repeated this session
local exileFrame       -- the parchment (built on first use)
local loginAt = nil
local guildOf, guildsKnown = {}, 0 -- [Name-Realm] = the guild its messages last named

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Red(s) return "|cffff6060" .. s .. "|r" end

-- The server's clock, the same second on every client (the words are dated by it).
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end

-- A reason as it travels and shows: no "~", "|" or control byte, at most REASON_MAX bytes.
local function Clean(s)
	s = tostring(s or ""):gsub("[~|%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, Moderation.REASON_MAX)
end

-- A character's name as the server writes it ("First Surname-Realm"); nil if it can't be one.
-- target: an empty input takes the player's target (the dialog, the slash command).
local function CharName(input, target)
	local name = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" and target then
		name = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target") or ""
	end
	if name == "" then return nil end
	name = ns.Normal(name)
	local short = ns.King and ns.King.CleanName and ns.King.CleanName(name)
	if not short then return nil end
	local realm = ns.RealmOf(name)
	if realm then realm = realm:gsub("[%s%-]", "") end
	return ns.FullName(short, realm ~= "" and realm or nil)
end
Moderation.CharName = CharName

-- An Olympus guild's name as the census writes it; nil for anything else. target: an empty input
-- takes the guild of the player's target.
local function GuildName(input, target)
	local name = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^<(.*)>$", "%1")
	if name == "" and target and GetGuildInfo then name = GetGuildInfo("target") or "" end
	if name == "" then return nil end
	local clean = ns.King and ns.King.CleanGuild and ns.King.CleanGuild(name)
	-- 1.1.5: a guild the High Council removed is no Olympus guild here any more, but the word that
	-- takes it off the network still matters to the 1.1-1.1.4 addons: it is given, kept and
	-- repeated as before (it changes nothing on this client).
	if not clean and ns.IsRemovedGuild and ns.IsRemovedGuild(name) then
		local s = name:gsub("[%c|]", "")
		if #s <= 24 and s:match("^[%w\128-\255 ]+$") then clean = s end
	end
	if not clean then return nil end
	-- The spelling the census keeps (a guild is one whatever its case).
	return ns.Data and ns.Data.GuildKey and ns.Data.GuildKey(clean) or clean
end
Moderation.GuildName = GuildName

local function Key(kind, name) return tostring(name or ""):lower() end

-- The pinned King, whatever the case his name is written in and whatever realm it names: a
-- word's target travels as free text (only its sender is the server's spelling), and every
-- list here is kept in lower case. Never a word's target, never hidden, never told he is.
local function IsKing(name)
	if type(name) ~= "string" or name == "" then return false end
	if ns.IsKingCharacter(name) then return true end
	local pin = ns.KingCharacter()
	return pin ~= nil and ns.ShortName(name):lower() == pin:lower()
end
Moderation.IsKing = IsKing

-- How high a name stands among those who give words, whether or not a word hides it now: the
-- King (by his pinned name, as the server writes it) 3, a Steward 2, a Hand or a High
-- Councillor 1, anyone else 0.
local function Rank(name)
	if type(name) ~= "string" or name == "" then return 0 end
	if ns.IsKingCharacter(name) then return 3 end
	local K = ns.King
	if type(K) == "table" and not K.missing then
		if K.IsStewardName(name) then return 2 end
		if K.IsHandName(name) then return 1 end
	end
	return ns.IsHighCouncillor(name) == true and 1 or 0
end
Moderation.Rank = Rank

-- A word's weight: its giver's rank, no more than the rank of whoever passed it on (via). A
-- word only reaches one who gives words from higher up.
local function Weight(e)
	local w = Rank(e.by)
	if e.via then w = math.min(w, Rank(e.via)) end
	return w
end
local function Reaches(e, rank) return e ~= nil and (rank == 0 or Weight(e) > rank) end

-- The King's own word: heard from him (not passed on), or given on his own client.
local function KingsOwn(e) return type(e) == "table" and not e.via and ns.IsKingCharacter(e.by) end

-- A word this client's own player gave (on this client: never one passed on in his name).
local function Given(e)
	return type(e) == "table" and not e.via and type(ns.me) == "string" and tostring(e.by):lower() == ns.me:lower()
end

---------------------------------------------------------------------------
-- The words kept (ns.rdb.netoff, per realm group like the census) and who they hide
---------------------------------------------------------------------------

local function Store()
	local rdb = ns.rdb
	local s = rdb and rdb.netoff
	if type(s) ~= "table" then
		s = {}
		if rdb then rdb.netoff = s end
	end
	for kind in pairs(Moderation.MAX) do
		if type(s[kind]) ~= "table" then s[kind] = {} end
	end
	return s
end

-- Who is off now, looked up fast (every chat line asks): rebuilt after any change.
local index
local function Index()
	local s = Store()
	if index and index.store == s then return index end
	index = { store = s, c = {}, g = {}, short = {}, n = { c = 0, g = 0 } }
	for key, e in pairs(s.c) do
		if type(e) == "table" and e.off then
			index.c[key] = e
			local short = ns.ShortName(e.name):lower()
			index.short[short] = index.short[short] or {}
			table.insert(index.short[short], e)
			index.n.c = index.n.c + 1
		end
	end
	for key, e in pairs(s.g) do
		if type(e) == "table" and e.off then
			index.g[key] = e
			index.n.g = index.n.g + 1
		end
	end
	return index
end
local function Dirty() index = nil end

-- A name's own word, "on" words included (the index holds "off" words alone), or nil.
local function OwnWord(full) return Store().c[Key("c", full)] end

-- Does a name's own word stand above a word found on another name of its player (the same name
-- on another realm of the group, or a name its player linked)? It does when it weighs more, or
-- as much and is newer: then that word doesn't hide it (1.1, Konig's review: a rogue Hand's word
-- on the victim's alt, or on his name on the group's other realm, hid again one the King had
-- shown again).
local function Overrides(own, e)
	if type(own) ~= "table" or own == e then return false end
	local a, b = Weight(own), Weight(e)
	return a > b or (a == b and own.at > e.at)
end

-- The word taking this character itself off, or nil. On WoW: Forever a name is one across its
-- realm group (ns.splitNames): the same name on another realm of the group is the same player,
-- unless the name's own word stands above that one (Overrides).
function Moderation.Character(name)
	if type(name) ~= "string" or name == "" or IsKing(name) then return nil end
	local x = Index()
	if x.n.c == 0 then return nil end
	local full = ns.FullName(ns.Normal(name))
	local e = x.c[Key("c", full)]
	if e or not ns.splitNames then return e end
	local group = ns.GroupOf(ns.RealmOf(full) or ns.realm or "")
	local own = OwnWord(full)
	for _, y in ipairs(x.short[ns.ShortName(full):lower()] or {}) do
		if ns.GroupOf(ns.RealmOf(y.name) or ns.realm or "") == group and not Overrides(own, y) then return y end
	end
	return nil
end

-- The word taking this guild off, or nil (whatever the case it is spelled in).
function Moderation.Guild(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	local x = Index()
	if x.n.g == 0 then return nil end
	return x.g[Key("g", guild)]
end

-- The word hiding this name: its own, or one on a name its player linked (Alts.lua), and the
-- name it is on; nil for anyone else, and always for the pinned King. One who gives words is
-- hidden only by a word from higher up (a councillor's word on a Steward's alt hides no Steward).
-- A word on a linked name doesn't hide one whose own word stands above it (Overrides: the King
-- showed him again, and a Hand's word on his alt doesn't hide him again).
function Moderation.Hidden(name)
	if type(name) ~= "string" or name == "" or IsKing(name) then return nil end
	if Index().n.c == 0 then return nil end
	local rank
	local function Counts(e)
		if not e then return false end
		rank = rank or Rank(name)
		return Reaches(e, rank)
	end
	local e = Moderation.Character(name)
	if Counts(e) then return e, e.name end
	local linked = ns.Alts and ns.Alts.Linked and ns.Alts.Linked(name)
	local own
	for _, other in ipairs(type(linked) == "table" and linked or {}) do
		e = Moderation.Character(other)
		if Counts(e) then
			if own == nil then own = OwnWord(ns.FullName(ns.Normal(name))) or false end
			if not Overrides(own, e) then return e, other end
		end
	end
	return nil
end

-- The guild a sender's own messages named last (a chat line, a layer, a decree, a vote, his own
-- census report): what the hop's whispers, which name none, are checked against. Only the
-- server's sender name: never a name written inside someone else's message.
function Moderation.NoteGuild(sender, guild)
	if type(sender) ~= "string" or sender == "" or type(guild) ~= "string" or guild == "" then return end
	local who = ns.FullName(sender)
	if guildOf[who] == guild then return end
	if guildOf[who] == nil then
		if guildsKnown >= Moderation.GUILDS_KNOWN then wipe(guildOf); guildsKnown = 0 end
		guildsKnown = guildsKnown + 1
	end
	guildOf[who] = guild
end
function Moderation.GuildOf(sender)
	if type(sender) ~= "string" or sender == "" then return nil end
	local who = ns.FullName(sender)
	if ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(who) then return GetGuildInfo("player") end
	return guildOf[who]
end

-- For every surface: does a word hide what this sender sends (in the name of `guild`)? The word
-- and the name or guild it is on. Never the pinned King; one who gives words, only from higher up.
-- look (1.1.5): a lookup with a guild that is not one his own message named (the game's chat
-- marks, Borders.MarkOfName, try the guilds he may be proven in): the same answer, nothing noted.
function Moderation.Hides(sender, guild, look)
	if type(sender) == "string" and IsKing(sender) then return nil end
	local e, on = Moderation.Hidden(sender)
	if e then return e, on end
	if guild and not look then Moderation.NoteGuild(sender, guild) end
	if Index().n.g == 0 then return nil end
	local rank
	local function Counts(w)
		if not w then return false end
		rank = rank or Rank(sender)
		return Reaches(w, rank)
	end
	e = Moderation.Guild(guild)
	if Counts(e) then return e, guild end
	local known = Moderation.GuildOf(sender)
	e = known and Moderation.Guild(known)
	if Counts(e) then return e, known end
	return nil
end

-- Our own guild is off: the word, or nil.
function Moderation.OwnGuildOff()
	return Moderation.Guild(GetGuildInfo and GetGuildInfo("player") or nil)
end

-- This client's own character (or a name its player linked), or its guild, is off: the word, or
-- nil. (A guild's word from lower down leaves one who gives words speaking, as Hides does.)
function Moderation.SelfOff()
	if ns.me and IsKing(ns.me) then return nil end
	local e = ns.me and Moderation.Hidden(ns.me)
	if e then return e end
	e = Moderation.OwnGuildOff()
	if e and ns.me and not Reaches(e, Rank(ns.me)) then return nil end
	return e
end

-- Anything off at all (cheap): the chats' history is only copied when so.
function Moderation.Any()
	local x = Index()
	return x.n.c + x.n.g > 0
end

---------------------------------------------------------------------------
-- Who may give a word
---------------------------------------------------------------------------

-- The King by his pinned name, a Steward of the signed titles list, a Hand of the King's list
-- or a Steward's, a councillor of the signed council list: as this client knows them now. A
-- name that is off gives no word (nor can it put itself back on); only a word from higher up
-- takes one of them off (Hidden).
function Moderation.IsIssuer(name)
	local rank = Rank(name)
	if rank == 0 then return false end
	-- 1.1.6: a player under a moderator's timeout or hold (WatchChat.Barred) has none of the powers
	-- Olympus gives while it lasts (never the King: nobody times him out).
	local WC = ns.WatchChat
	if rank < 3 and WC and WC.Barred and WC.Barred("powers", name) then return false end
	return rank == 3 or Moderation.Hidden(name) == nil
end

function Moderation.CanIssue()
	return ns.me ~= nil and ns.IsMember() and Moderation.IsIssuer(ns.me)
end

---------------------------------------------------------------------------
-- Taking a word
---------------------------------------------------------------------------

local function Count(list)
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	return n
end

-- Room for one more: the oldest word putting a name back on goes; none, no room, except for the
-- King's own word (king), for which the oldest word taking a name off that is not his own goes:
-- a list filled by anyone never shuts the King out. Never a word that weighs more than the new
-- one (weight: 1.1, Konig's review: a rogue Hand who filled the list pushed out the King's word
-- showing a name again, then hid that name anyway).
local function MakeRoom(list, kind, king, weight)
	if Count(list) < Moderation.MAX[kind] then return true end
	local oldest, oldestOff
	for key, e in pairs(list) do
		if not e.off then
			if (not oldest or e.at < list[oldest].at) and Weight(e) <= weight then oldest = key end
		elseif king and not KingsOwn(e) and (not oldestOff or e.at < list[oldestOff].at) and Weight(e) <= weight then
			oldestOff = key
		end
	end
	local drop = oldest or oldestOff
	if not drop then return false end
	list[drop] = nil
	return true
end

-- A word as it is kept, checked: nil and why when it can't be one.
function Moderation.Entry(kind, name, off, at, by, reason)
	if not Moderation.KINDS[kind] then return nil, "kind" end
	if kind == "c" then
		name = CharName(name)
		if not name then return nil, "name" end
		if IsKing(name) then return nil, "the pinned King" end
	else
		name = GuildName(name)
		if not name then return nil, "not an Olympus guild" end
		if ns.IsKingGuild(name) then return nil, "the King's guild" end
	end
	by = CharName(by)
	if not by then return nil, "issuer" end
	at = tonumber(at)
	if not at or at < 1 or at ~= math.floor(at) or at > Clock() + Moderation.DATE_AHEAD then return nil, "time" end
	reason = Clean(reason)
	if off and reason == "" then return nil, "no reason" end
	return { kind = kind, name = name, off = off and true or false, at = at, by = by, reason = reason }
end

local function Label(e)
	if e.kind == "g" then return "<" .. e.name .. ">" end
	return ns.DisplayName(e.name) or e.name
end

-- Is this word about our own character, a name our player linked, or our guild? Never on the
-- King's own client (nothing hides him, and no other's reason reaches his screen that way).
local function AboutMe(e)
	if ns.me and IsKing(ns.me) then return false end
	if e.kind == "g" then
		local mine = GetGuildInfo and GetGuildInfo("player")
		return type(mine) == "string" and Key("g", mine) == Key("g", e.name)
	end
	if not ns.me then return false end
	local key = Key("c", e.name)
	if Key("c", ns.me) == key then return true end
	local linked = ns.Alts and ns.Alts.Linked and ns.Alts.Linked(ns.me)
	for _, other in ipairs(type(linked) == "table" and linked or {}) do
		if Key("c", ns.FullName(other)) == key then return true end
	end
	return false
end

-- The date of a word, by the server's clock ("2026-09-29 21:04").
local function When(e) return date and date("%Y-%m-%d %H:%M", e.at) or tostring(e.at) end
Moderation.When = When
-- 1.1.6: a timed word's time of day ("21:34"), as the player's clock shows it.
local function Hour(t) return date and date("%H:%M", t) or tostring(t) end

-- Who gave a word, and who passed it on when someone else did (the server's name for that one).
-- label: how a name shows (cut short on the King's stream).
local function ByText(e, label)
	label = label or function(name) return ns.DisplayName(name) or "?" end
	if e.via then return L.NETOFF_VIA:format(label(e.by), label(e.via)) end
	return label(e.by)
end

-- What our own client says when a word hides us (our character, or our guild).
function Moderation.YouText(e)
	local reason, by = e.reason ~= "" and e.reason or "-", ByText(e)
	if e.kind == "g" then return L.NETOFF_YOUR_GUILD:format(e.name, reason, by, When(e)) end
	return L.NETOFF_YOU:format(reason, by, When(e))
end

local function Notify(e, was)
	if not AboutMe(e) then return end
	-- Back on: only when this client had us off (a word it never held is no news).
	if not e.off and not (type(was) == "table" and was.off) then return end
	local mark = e.kind .. Key(e.kind, e.name) .. e.at
	if toldMe[mark] then return end
	toldMe[mark] = true
	if e.off then return ns.Print(Red(Moderation.YouText(e))) end
	ns.Print(e.kind == "g" and L.NETOFF_YOUR_GUILD_BACK or L.NETOFF_YOU_BACK)
end

-- The same word again (a repeat): its date, off or on, giver and reason all the same.
local function Same(a, b)
	return type(a) == "table" and type(b) == "table" and a.at == b.at and a.off == b.off
		and Key("c", a.by) == Key("c", b.by) and a.reason == b.reason
end

-- Two different words of the same second: which one every client keeps, whatever came first.
-- The King's own first; else the one taking the name off; else by its giver's name, then its
-- reason.
local function Outranks(e, kept)
	local a, b = KingsOwn(e), KingsOwn(kept)
	if a ~= b then return a end
	if e.off ~= kept.off then return e.off end
	local x, y = Key("c", e.by), Key("c", kept.by)
	if x ~= y then return x < y end
	return tostring(e.reason) < tostring(kept.reason)
end

-- "taken", "older" (ours is newer), "same" (the same word: a repeat), "tie", "outranked" (ours
-- comes from higher up) or "full".
-- 1.1 review (Konig): no word replaces one from higher up (Weight: the King's, then a Steward's,
-- then a Hand's or a councillor's), whatever its date, so a rogue Hand never wins an edit war with
-- the King's undo; a word from higher up replaces a lower one whatever its date, so every client
-- keeps the same word whatever came first. Between words of the same weight the newest wins.
local function Take(e)
	local list = Store()[e.kind]
	local key = Key(e.kind, e.name)
	local kept = list[key]
	if type(kept) == "table" then
		if Same(e, kept) then
			kept.heard = ns.Now()
			return "same", kept
		end
		local ours, held = Weight(e), Weight(kept)
		if ours < held then return "outranked", kept end
		if ours == held then
			if e.at < kept.at then return "older", kept end
			if e.at == kept.at and not Outranks(e, kept) then return "tie", kept end
		end
	elseif not MakeRoom(list, e.kind, KingsOwn(e), Weight(e)) then
		return "full"
	end
	e.heard = ns.Now()
	list[key] = e
	Dirty()
	ns.Log("net-off: %s %s %s by %s%s (%s)", e.kind, e.name, e.off and "off" or "back on", e.by,
		e.via and (", passed on by " .. e.via) or "", e.reason ~= "" and e.reason or "-")
	Notify(e, kept)
	ns.Fire("NETOFF_CHANGED", e)
	ns.Fire("DATA_CHANGED")
	ns.Fire("DECREES_CHANGED")
	return "taken", e
end

local function Word(e)
	local msg = ("O1~%s~%s~%d~%s~%s~%s"):format(e.kind, e.off and "1" or "0", e.at, e.name, e.by, e.reason or "")
	return #msg <= 250 and msg or msg:sub(1, 250)
end
Moderation.Word = Word

local function Send(e)
	e.heard = ns.Now()
	-- Logged (the issuer's own words: the server keeps them). One per name waits in the queue.
	ns.Comm.Send("CHANNEL", Word(e), "netoff:" .. e.kind .. ":" .. Key(e.kind, e.name), nil, true)
end

-- The highest rank among a character and the names its player linked: a word on an alt reaches
-- its main, so aiming at one who gives words through an alt needs the same rank.
local function TargetRank(name)
	local rank = Rank(name)
	local linked = ns.Alts and ns.Alts.Linked and ns.Alts.Linked(name)
	for _, other in ipairs(type(linked) == "table" and linked or {}) do rank = math.max(rank, Rank(other)) end
	return rank
end
Moderation.TargetRank = TargetRank

local function Refuse(sender, why)
	stats.refused = stats.refused + 1
	return ns.Log("net-off word from %s ignored: %s", sender, why)
end

function Moderation.Handle(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	-- An issuer's words come through the logged API, where this client has it (a chat line's rule).
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.unlogged = stats.unlogged + 1
		return
	end
	local kind, off, at, name, by, reason = tostring(text):match("^O1~(%a)~([01])~(%d+)~([^~]+)~([^~]+)~?(.*)$")
	if not kind or not Moderation.KINDS[kind] then return end
	sender = ns.FullName(sender)
	if not Moderation.IsIssuer(sender) then
		return Refuse(sender, "not the King, his Steward, a Hand or a High Councillor here")
	end
	local e, why = Moderation.Entry(kind, name, off == "1", at, by, reason)
	if not e then return Refuse(sender, tostring(why)) end
	local firstHand = Key("c", sender) == Key("c", e.by)
	-- Passed on for someone else: taken (or counted as a repeat) only while its giver may give one
	-- here too, so the words of one who no longer may fade whoever repeats them.
	if not firstHand and not Moderation.IsIssuer(e.by) then return Refuse(sender, "passed on for " .. e.by .. ", who gives no word here") end
	-- A repeat of the word held here: heard (its giver's own repeat shows it first-hand).
	local kept = Store()[kind][Key(kind, e.name)]
	if Same(e, kept) then
		kept.heard = ns.Now()
		if firstHand then kept.via = nil end
		stats.same = (stats.same or 0) + 1
		return
	end
	if firstHand then
		e.by = sender -- (the server's spelling)
	else
		e.via = sender -- who passed it on stays with it (shown; the server stamps that name)
	end
	-- Aimed at one who gives words (or at a name his player linked): only from higher up, its
	-- giver and whoever passed it on both.
	if kind == "c" then
		local target = TargetRank(e.name)
		if target > 0 and Weight(e) <= target then return Refuse(sender, "aimed at " .. e.name .. ", who ranks as high") end
	end
	-- 1.1.6: the word a timed word this client holds cancelled would have become (its giver's client
	-- never heard the cancel): refused, and the canceller's own client answers with its cancel.
	local cancelled = Moderation.CancelledHere(e)
	if cancelled then
		Moderation.AnswerCancel(cancelled)
		return Refuse(sender, "the word of a timed word cancelled before its time")
	end
	local result, held = Take(e)
	stats[result] = (stats[result] or 0) + 1
	-- Ours is newer, or from higher up, and our own player gave it: his client answers with it at
	-- its next round.
	if (result == "older" or result == "outranked") and Given(held) and Moderation.CanIssue() then held.heard = ns.Now() - Moderation.REPEAT - Moderation.JITTER end
end
ns.Comm.Handle("O1", function(...) Moderation.Handle(...) end)

-- A census report of a guild that is off: not taken (Data.Receive). Its reporter is remembered as
-- that guild's (the hop checks his whispers against it): the server stamps his name. The names
-- written inside it are anyone's word, and are not (a forged report would hide innocents).
function Moderation.Report(r, sender)
	if type(r) ~= "table" or type(r.guild) ~= "string" then return false end
	Moderation.NoteGuild(sender, r.guild)
	if not Moderation.Guild(r.guild) then return false end
	stats.reports = stats.reports + 1
	return true
end

---------------------------------------------------------------------------
-- Giving a word (the Decrees tab, /oly netoff, /oly neton)
---------------------------------------------------------------------------

-- Takes `input` off (off true, with a reason) or puts it back on: this client's word, kept and
-- sent at once. kind "c" a character (the target's by default), "g" an Olympus guild (the
-- target's by default). Returns true when given.
function Moderation.Set(kind, input, off, reason)
	if not ns.IsMember() then ns.Print(L.MEMBERS_ONLY) return false end
	if not Moderation.CanIssue() then ns.Print(L.NETOFF_ONLY) return false end
	if not Moderation.KINDS[kind] then return false end
	local name
	if kind == "g" then
		name = GuildName(input, true)
		if not name then ns.Print(L.NETOFF_GUILD_BAD) return false end
		if ns.IsKingGuild(name) then ns.Print(L.NETOFF_NOT_KING_GUILD) return false end
	else
		name = CharName(input, true)
		if not name then ns.Print(L.NETOFF_WHO_BAD) return false end
		if IsKing(name) then ns.Print(L.NETOFF_NOT_KING) return false end
		if Key("c", name) == Key("c", ns.me) then ns.Print(L.NETOFF_NOT_SELF) return false end
		-- One who gives words (or a name his player linked): only from higher up.
		local target = TargetRank(name)
		if target == 3 then ns.Print(L.NETOFF_NOT_KING) return false end -- (a name the King linked as his alt)
		if target > 0 and Rank(ns.me) <= target then ns.Print(L.NETOFF_OUTRANKED:format(Label({ kind = kind, name = name }))) return false end
	end
	reason = Clean(reason)
	if off and reason == "" then ns.Print(L.NETOFF_REASON_NEEDED) return false end
	local kept = Store()[kind][Key(kind, name)]
	local label = Label({ kind = kind, name = name })
	-- 1.1.6: /oly neton guild on a guild whose timed word still waits cancels that word.
	if not off and kind == "g" and not (type(kept) == "table" and kept.off) and Moderation.TimedFor(name) then
		return Moderation.CancelExile(name)
	end
	if not off and not (type(kept) == "table" and kept.off) then ns.Print(L.NETOFF_NOT_OFF:format(label)) return false end
	local at = Clock()
	if type(kept) == "table" and kept.at >= at then at = kept.at + 1 end
	local e = { kind = kind, name = name, off = off and true or false, at = at, by = ns.me, reason = reason }
	local result = Take(e)
	-- (1.1 review: a word from higher up holds that name; ours would not replace it anywhere.)
	if result == "outranked" then ns.Print(L.NETOFF_HELD_HIGHER:format(label)) return false end
	if result ~= "taken" then ns.Print(L.NETOFF_FULL) return false end
	Send(e)
	if kind == "g" then
		ns.Print(off and L.NETOFF_GUILD_DONE:format(label, reason) or L.NETOFF_GUILD_UNDONE:format(label))
	else
		ns.Print(off and L.NETOFF_DONE:format(label, reason) or L.NETOFF_UNDONE:format(label))
	end
	return true
end

-- /oly netoff [guild] [name[: reason]] and /oly neton [guild] <name>: with no reason yet, the
-- dialog asks.
function Moderation.Slash(off, rest)
	rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if off and rest == "" then return Moderation.PrintList() end
	local kind, target = "c", rest
	local word, after = rest:match("^(%S+)%s*(.*)$")
	if word and (word:lower() == "guild" or word:lower() == "guilda") then kind, target = "g", after end
	local name, reason = target:match("^([^:]*):%s*(.*)$")
	if not name then name, reason = target, nil end
	-- 1.1.6: /oly netoff guild <name> in 30|60[: reason], with notice (pt-BR: "em").
	local guild, minutes = name:match("^(.-)%s+in%s+(%d+)%s*$")
	if not guild then guild, minutes = name:match("^(.-)%s+em%s+(%d+)%s*$") end
	if off and kind == "g" and guild and guild ~= "" then
		local delay = tonumber(minutes) * 60
		if reason and reason ~= "" then return Moderation.Exile(guild, delay, reason) end
		return Moderation.AskExile(guild, delay)
	end
	if not off then return Moderation.Set(kind, name, false, reason or "") end
	if reason and reason ~= "" then return Moderation.Set(kind, name, true, reason) end
	return Moderation.Ask(kind, name)
end

-- The words that take a character or a guild off now, newest first.
function Moderation.List()
	local out = {}
	for kind in pairs(Moderation.KINDS) do
		for _, e in pairs(Store()[kind]) do
			if type(e) == "table" and e.off then out[#out + 1] = e end
		end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		if a.kind ~= b.kind then return a.kind < b.kind end
		return a.name < b.name
	end)
	return out
end

-- An issuer's name on the King's screen: cut short while the council's names are hidden there
-- (his stream), as every councillor's is. A reason that is not his own word (given on his
-- client, or heard from him: never one only written in his name) stays hidden there too until
-- he shows the council's names (the eye in the Realm): nothing another player writes reaches
-- his screen on its own.
local function IssuerLabel(by)
	local shown = ns.DisplayName(by) or "?"
	if ns.CouncilMasked() and not ns.IsKingCharacter(by) then return ns.MaskName(shown) end
	return shown
end
local function ReasonShown(e)
	if ns.CouncilMasked() and not KingsOwn(e) then return L.NETOFF_REASON_HIDDEN end
	return e.reason ~= "" and e.reason or "-"
end
Moderation.ReasonShown = ReasonShown

function Moderation.PrintList()
	local list = Moderation.List()
	ns.Print(L.NETOFF_LIST:format(#list))
	for _, e in ipairs(list) do
		print(("  %s  -  %s  (%s, %s)"):format(Label(e), ReasonShown(e), ByText(e, IssuerLabel), When(e)))
	end
	if Moderation.CanIssue() then print(L.HELP_NETOFF) end
end

-- The Decrees tab's section: who is hidden and which guilds are off, why, by whom and when; the
-- issuers' buttons.
function Moderation.Lines()
	local lines = {}
	local issuer = Moderation.CanIssue()
	local list = Moderation.List()
	local mine = Moderation.SelfOff()
	local timed, exile = Moderation.TimedList(), Moderation.ExileOfMine()
	if #list == 0 and #timed == 0 and not issuer and not mine then return lines end
	lines[#lines + 1] = { header = true, text = L.NETOFF_TITLE, right = #list > 0 and Grey(tostring(#list)) or nil,
		tooltip = function(tt)
			tt:AddLine(L.NETOFF_TITLE, 1, 0.82, 0)
			tt:AddLine(L.NETOFF_TIP, 1, 1, 1, true)
			tt:AddLine(L.NETOFF_GUILD_TIP, 1, 1, 1, true)
		end }
	if mine then
		lines[#lines + 1] = { indent = 1, text = Red(mine.kind == "g" and L.NETOFF_YOUR_GUILD_SHORT or L.NETOFF_YOU_SHORT),
			tooltip = function(tt) tt:AddLine(Moderation.YouText(mine), 1, 1, 1, true) end }
	elseif exile then
		-- 1.1.6: our guild's timed word waits: the parchment again, with a click.
		lines[#lines + 1] = { indent = 1, text = Red(L.NETOFF_EXILE_YOURS_SHORT:format(Hour(exile.when))),
			tooltip = function(tt) tt:AddLine(Moderation.ExileText(exile), 1, 1, 1, true) end,
			onClick = function() Moderation.ShowExileNotice(exile) end }
	end
	-- 1.1.6: the guilds whose timed word waits, their time first.
	for _, p in ipairs(timed) do
		local may = Moderation.MayCancel(p)
		lines[#lines + 1] = {
			indent = 1, text = Label({ kind = "g", name = p.name }) .. "  " .. Gold(L.NETOFF_EXILE_AT:format(Hour(p.when))),
			right = Grey(When(p)),
			tooltip = function(tt)
				tt:AddLine(Label({ kind = "g", name = p.name }), 1, 0.82, 0)
				tt:AddLine(L.NETOFF_EXILE_TIP:format(Hour(p.when)), 1, 0.5, 0.5, true)
				tt:AddLine(L.NETOFF_REASON:format(ReasonShown(p)), 1, 1, 1, true)
				tt:AddLine(L.NETOFF_BY:format(IssuerLabel(p.by), When(p)), 0.7, 0.7, 0.7)
				if may then tt:AddLine(L.NETOFF_EXILE_CLICK_CANCEL, 0.6, 0.6, 0.6, true) end
			end,
			onClick = may and function() ns.ShowDialog("OLYMPUS_EXILE_CANCEL", Label({ kind = "g", name = p.name }), nil, { name = p.name }) end or nil,
		}
	end
	for _, e in ipairs(list) do
		lines[#lines + 1] = {
			indent = 1, text = Label(e), right = Grey(When(e)),
			tooltip = function(tt)
				tt:AddLine(Label(e), 1, 0.82, 0)
				if e.kind == "g" then tt:AddLine(L.NETOFF_GUILD_OFF, 1, 0.5, 0.5, true) end
				tt:AddLine(L.NETOFF_REASON:format(ReasonShown(e)), 1, 1, 1, true)
				tt:AddLine(L.NETOFF_BY:format(ByText(e, IssuerLabel), When(e)), 0.7, 0.7, 0.7)
				tt:AddLine(L.NETOFF_LAPSES:format(date and date("%Y-%m-%d", e.at + Moderation.OFF_KEEP) or tostring(e.at + Moderation.OFF_KEEP)), 0.6, 0.6, 0.6, true)
				if issuer then tt:AddLine(L.NETOFF_CLICK_UNDO, 0.6, 0.6, 0.6, true) end
			end,
			onClick = issuer and function() ns.ShowDialog("OLYMPUS_NETOFF_UNDO", Label(e), nil, { kind = e.kind, name = e.name }) end or nil,
		}
	end
	if issuer then
		lines[#lines + 1] = { indent = 1, text = Gold("+ " .. L.NETOFF_ADD), onClick = function() Moderation.Ask("c") end }
		lines[#lines + 1] = { indent = 1, text = Gold("+ " .. L.NETOFF_ADD_GUILD), onClick = function() Moderation.Ask("g") end }
		lines[#lines + 1] = { indent = 1, text = Gold("+ " .. L.NETOFF_EXILE_ADD), onClick = function() Moderation.AskExile() end,
			tooltip = function(tt) tt:AddLine(L.NETOFF_EXILE_ADD, 1, 0.82, 0); tt:AddLine(L.NETOFF_EXILE_ADD_TIP, 1, 1, 1, true) end }
	end
	lines[#lines].gapAfter = true
	return lines
end

-- The dialogs: who (a name or the target; a guild or the target's), then why.
function Moderation.Ask(kind, name)
	if not Moderation.CanIssue() then return ns.Print(L.NETOFF_ONLY) end
	local pick = kind == "g" and GuildName or CharName
	local full = name and name ~= "" and pick(name) or nil
	if name and name ~= "" and not full then return ns.Print(kind == "g" and L.NETOFF_GUILD_BAD or L.NETOFF_WHO_BAD) end
	if full then return ns.ShowDialog("OLYMPUS_NETOFF_WHY", Label({ kind = kind, name = full }), nil, { kind = kind, name = full }) end
	ns.ShowDialog(kind == "g" and "OLYMPUS_NETOFF_GUILD" or "OLYMPUS_NETOFF_WHO", nil, nil, { kind = kind })
end

local function Next(data, text)
	local kind = type(data) == "table" and data.kind == "g" and "g" or "c"
	local full = kind == "g" and GuildName(text, true) or CharName(text, true)
	if not full then return ns.Print(kind == "g" and L.NETOFF_GUILD_BAD or L.NETOFF_WHO_BAD) end
	ns.ShowDialog("OLYMPUS_NETOFF_WHY", Label({ kind = kind, name = full }), nil, { kind = kind, name = full })
end
local function Give(data, text)
	if type(data) ~= "table" or not data.name then return end
	Moderation.Set(data.kind or "c", data.name, true, text)
end

-- Who (a character, or a guild): the name typed, or the target's. after(data, text): the next
-- step (1.1.6: the timed word's own; Next by default).
local function WhoDialog(prompt, width, letters, default, after)
	local step = after or Next
	return {
		text = prompt,
		button1 = L.WRIT_NEXT,
		button2 = CANCEL or "Cancel",
		hasEditBox = true,
		editBoxWidth = width,
		maxLetters = letters,
		OnShow = function(self)
			local eb = self.editBox or self.EditBox
			if eb then
				eb:SetText(default() or "")
				eb:SetFocus()
			end
		end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			ns.SafeCall("net-off who", step, data or self.data, eb and eb:GetText())
		end,
		EditBoxOnEnterPressed = function(self, data)
			local parent = self:GetParent()
			ns.SafeCall("net-off who", step, data or (parent and parent.data), self:GetText())
			parent:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end
StaticPopupDialogs["OLYMPUS_NETOFF_WHO"] = WhoDialog(L.NETOFF_WHO_PROMPT, 240, 60, function()
	local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
	return target and ns.DisplayName(target) or ""
end)
StaticPopupDialogs["OLYMPUS_NETOFF_GUILD"] = WhoDialog(L.NETOFF_GUILD_PROMPT, 240, 40, function()
	local guild = GetGuildInfo and GetGuildInfo("target")
	return guild and ns.IsFederation(guild) and guild or ""
end)

StaticPopupDialogs["OLYMPUS_NETOFF_WHY"] = {
	text = L.NETOFF_WHY_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = Moderation.REASON_MAX,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("net-off why", Give, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent()
		ns.SafeCall("net-off why", Give, data or (parent and parent.data), self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_NETOFF_UNDO"] = {
	text = L.NETOFF_UNDO_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) == "table" then ns.SafeCall("net-off undo", Moderation.Set, data.kind, data.name, false, "") end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- 1.1.6: a guild's word with notice (O2, see the top)
---------------------------------------------------------------------------

-- The timed words kept (ns.rdb.netoffTimed, per realm group like the rest), [guild key] =
-- { name, at, when, by, reason, heard, sent, cancel = { at, by, heard } once cancelled,
-- applied = true once its time came here, lapsed = true when its giver gave no words by then }.
-- Apart from the O1 lists, which Load clears of anything else.
local function Timed()
	local rdb = ns.rdb
	local s = rdb and rdb.netoffTimed
	if type(s) ~= "table" then
		s = {}
		if rdb then rdb.netoffTimed = s end
	end
	return s
end

-- A timed word as it is kept, checked: nil and why when it can't be one.
function Moderation.TimedEntry(name, at, when, by, reason)
	name = GuildName(name)
	if not name then return nil, "not an Olympus guild" end
	if ns.IsKingGuild(name) then return nil, "the King's guild" end
	by = CharName(by)
	if not by then return nil, "issuer" end
	at, when = tonumber(at), tonumber(when)
	if not at or at < 1 or at ~= math.floor(at) or at > Clock() + Moderation.DATE_AHEAD then return nil, "time" end
	if not when or when ~= math.floor(when) or when - at < Moderation.EXILE_MIN or when - at > Moderation.EXILE_MAX then return nil, "notice" end
	reason = Clean(reason)
	if reason == "" then return nil, "no reason" end
	return { name = name, at = at, when = when, by = by, reason = reason }
end

local function SameTimed(a, b)
	return type(a) == "table" and type(b) == "table" and a.at == b.at and a.when == b.when
		and Key("c", a.by) == Key("c", b.by) and a.reason == b.reason
end

-- Still to come: not cancelled, its time not come, and its giver still one who gives words.
local function Waiting(p, clock)
	return type(p) == "table" and not p.cancel and not p.applied and (clock or Clock()) < p.when and Moderation.IsIssuer(p.by)
end

-- The guild's word a timed word becomes at its time: its giver's, dated its time.
local function Applied(p) return { kind = "g", name = p.name, off = true, at = p.when, by = p.by, reason = p.reason } end
local function IsApplied(word, p)
	return type(word) == "table" and word.off and not word.via and word.at == p.when
		and Key("c", word.by) == Key("c", p.by) and word.reason == p.reason
end

-- A guild's word heard (O1) that is the word a timed word held cancelled here would have become:
-- that timed word, or nil. Its giver's client sends it when it never heard the cancel (he was
-- away when it came), so the cancel holds here whoever passed it on.
function Moderation.CancelledHere(word)
	if type(word) ~= "table" or word.kind ~= "g" or not word.off then return nil end
	local p = Timed()[Key("g", word.name)]
	if type(p) ~= "table" or not p.cancel or word.at ~= p.when or Key("c", word.by) ~= Key("c", p.by) or word.reason ~= p.reason then return nil end
	return p
end

-- The canceller's own client answers a word it holds cancelled at its next round (Tick), as an
-- O1 word newer or from higher up is answered (Handle): its giver's client then takes the cancel.
function Moderation.AnswerCancel(p)
	if type(p) ~= "table" or not p.cancel or Key("c", p.cancel.by) ~= Key("c", ns.me or "") or not Moderation.CanIssue() then return end
	p.sent = ns.Now() - Moderation.EXILE_REPEAT - Moderation.JITTER
end

-- Room for one more: a cancelled or applied word goes first (the oldest time first), else one
-- from lower down than the new word; never one from as high (as MakeRoom: a list a rogue
-- councillor filled never shuts out one from higher up).
local function TimedRoom(list, weight)
	if Count(list) < Moderation.EXILE_MAX_KEPT then return true end
	local drop, dropDone
	for key, p in pairs(list) do
		local done = type(p) ~= "table" or p.cancel ~= nil or p.applied == true
		if done or Rank(p.by) < weight then
			local older = drop and type(p) == "table" and type(list[drop]) == "table" and p.when < list[drop].when
			if not drop or (done and not dropDone) or (done == dropDone and older) then drop, dropDone = key, done end
		end
	end
	if not drop then return false end
	list[drop] = nil
	return true
end

local function TimedChanged()
	ns.Fire("NETOFF_TIMED_CHANGED")
	ns.Fire("DECREES_CHANGED")
end

-- What our guild's members read: leave it, or it is taken off at its time.
function Moderation.ExileText(p)
	return L.NETOFF_EXILE_YOURS:format(p.name, Hour(p.when), p.reason ~= "" and p.reason or "-")
end

-- The time left, as the parchment counts it ("12 min 05 s").
local function Left(p)
	local s = math.max(0, math.floor(p.when - Clock()))
	return L.NETOFF_EXILE_LEFT:format(math.floor(s / 60), s % 60)
end

-- The parchment (Olympus's own window, as the update letter's: no edit box and never one of the
-- game's popups, so it is safe with the gamepad UI), built on first use.
local function NoticeFrame()
	if exileFrame then return exileFrame end
	local f = ns.Window("OlympusExileNotice", UIParent, { inset = false, close = false, escape = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(420, 330) -- (room for the notice, its reason and its countdown)
	f:SetPoint("TOP", 0, -140)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	-- (1.1.5: every window in the Olympus window's bronze metal, ns.Window; the parchment inside it.)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", f.inner[1], f.inner[2])
	bg:SetPoint("BOTTOMRIGHT", f.inner[3], f.inner[4])
	local ui = ns.UI
	local parchments = ui and ui.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG", "Interface\\Stationery\\StationeryTest1" }
	local file = ui and ui.FirstTexture and ui.FirstTexture(parchments) or parchments[1]
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	f.title = f:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -28)
	f.title:SetText(L.NETOFF_EXILE_TITLE)
	f.body = f:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	f.body:SetPoint("TOPLEFT", 34, -64)
	f.body:SetPoint("RIGHT", -34, 0)
	f.body:SetJustifyH("LEFT")
	f.body:SetJustifyV("TOP")
	f.left = f:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.left:SetPoint("BOTTOM", 0, 58)
	f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.done:SetSize(110, 24)
	f.done:SetPoint("BOTTOM", 0, 24)
	f.done:SetText(OKAY or "OK")
	f.done:SetScript("OnClick", function() f:Hide() end)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnUpdate", function(self, elapsed)
		self.tick = (self.tick or 0) + (tonumber(elapsed) or 0)
		if self.tick < 1 then return end
		self.tick = 0
		ns.SafeCall("net-off countdown", Moderation.RefreshNotice)
	end)
	ns.EscapeCloses("OlympusExileNotice")
	if f.HookScript then f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end) end
	exileFrame = f
	return f
end

-- The countdown, each second; the parchment closes once its word no longer waits (cancelled,
-- applied, replaced or lapsed).
function Moderation.RefreshNotice()
	local f = exileFrame
	if not (f and f:IsShown() and f.word) then return end
	local p = f.word
	if Timed()[Key("g", p.name)] ~= p or not Waiting(p) then f:Hide() return end
	f.left:SetText(Left(p))
end

function Moderation.ShowExileNotice(p)
	if not Waiting(p) then return nil end
	local f = NoticeFrame()
	f.word = p
	f.body:SetText(Moderation.ExileText(p))
	f.left:SetText(Left(p))
	f:Show()
	return f
end
function Moderation.NoticeFrame() return exileFrame end

-- Our guild's members are told once per word: the chat line now, the parchment (and its raid
-- warning) now or, in an instance or on Busy, once out (ns.Alert), while the word still waits.
local function TellExile(p)
	if not AboutMe({ kind = "g", name = p.name }) then return end
	local mark = Key("g", p.name) .. p.at
	if toldExile[mark] then return end
	toldExile[mark] = true
	ns.Print(Red(Moderation.ExileText(p)))
	ns.Alert("watch", "loud", { text = L.NETOFF_EXILE_RAID:format(Hour(p.when)), what = L.NETOFF_EXILE_YOURS_SHORT:format(Hour(p.when)),
		key = "exile:" .. mark, open = function() return Waiting(p) end, show = function() ns.SafeCall("net-off notice", Moderation.ShowExileNotice, p) end })
end
local function TellCancel(p)
	if not AboutMe({ kind = "g", name = p.name }) or not toldExile[Key("g", p.name) .. p.at] then return end
	ns.Print(L.NETOFF_EXILE_YOURS_CANCELLED:format(p.name))
	if exileFrame and exileFrame.word == p then exileFrame:Hide() end
end

-- "taken", "same" (a repeat), "older", "tie", "outranked" (the guild's timed word comes from
-- higher up), "cancelled" (a cancel from as high or higher stands, and this word is no newer),
-- "held" (the guild's word now, O1, comes from higher up) or "full".
local function TakeTimed(e)
	local list = Timed()
	local key = Key("g", e.name)
	local kept = list[key]
	local ours = Rank(e.by)
	if type(kept) == "table" then
		if SameTimed(e, kept) then
			kept.heard = ns.Now()
			return "same", kept
		end
		if kept.cancel then
			if ours < Rank(kept.cancel.by) or e.at <= kept.cancel.at then return "cancelled", kept end
		else
			local held = Rank(kept.by)
			if ours < held then return "outranked", kept end
			if ours == held then
				if e.at < kept.at then return "older", kept end
				-- The same second: every client keeps the same one (its giver's name, its reason, its time).
				if e.at == kept.at then
					local a, b = Key("c", e.by), Key("c", kept.by)
					if a > b or (a == b and (e.reason > kept.reason or (e.reason == kept.reason and e.when >= kept.when))) then return "tie", kept end
				end
			end
		end
	end
	local word = Store().g[key]
	if type(word) == "table" and Weight(word) > ours then return "held", word end
	if type(kept) ~= "table" and not TimedRoom(list, ours) then return "full" end
	e.heard = ns.Now()
	list[key] = e
	ns.Log("net-off: %s off at %d by %s (%s)", e.name, e.when, e.by, e.reason)
	TimedChanged()
	TellExile(e)
	-- On the second where the client's timers allow (the minute's tick does it otherwise).
	ns.After(math.max(1, e.when - Clock() + 1), "net-off timed word", function() Moderation.ApplyDue() end)
	if Clock() >= e.when then Moderation.ApplyDue() end
	return "taken", e
end

-- A cancel given before the word's time that came after it applied here: the guild's word that
-- applied it goes (that very word: a newer one stays). Its giver's own client sent that word to
-- the clients before 1.1.6, so it puts the guild back on for the army instead, as /oly neton.
local function Unapply(p)
	local key = Key("g", p.name)
	local word = Store().g[key]
	if not IsApplied(word, p) then return end
	if Given(word) and Moderation.CanIssue() then
		local on = { kind = "g", name = word.name, off = false, at = math.max(Clock(), word.at + 1), by = ns.me, reason = "" }
		if Take(on) == "taken" then Send(on) end
		return
	end
	Store().g[key] = nil
	Dirty()
	Notify({ kind = "g", name = word.name, off = false, at = word.at + 1 }, word)
	ns.Fire("NETOFF_CHANGED", word)
	ns.Fire("DATA_CHANGED")
	ns.Fire("DECREES_CHANGED")
end

-- "taken", "same" (a repeat), "unknown" (no such timed word here), "cancelled" (a cancel from as
-- high stands already), "outranked" (neither its giver nor from higher up) or "late" (given
-- after its time, or before the word).
local function CancelTimed(c)
	local p = Timed()[Key("g", c.name)]
	if type(p) ~= "table" or p.when ~= c.when then return "unknown" end
	local old = p.cancel
	if old then
		if old.at == c.at and Key("c", old.by) == Key("c", c.by) then
			old.heard = ns.Now()
			return "same", p
		end
		-- Two cancels: the one from higher up stays, else the first (every client keeps the same).
		local a, b = Rank(c.by), Rank(old.by)
		if a < b or (a == b and c.at >= old.at) then return "cancelled", p end
	end
	if Key("c", c.by) ~= Key("c", p.by) and Rank(c.by) <= Rank(p.by) then return "outranked", p end
	if c.at < p.at or c.at >= p.when then return "late", p end
	p.cancel = { at = c.at, by = c.by, heard = ns.Now() }
	ns.Log("net-off: %s's timed word cancelled by %s", p.name, c.by)
	if p.applied then Unapply(p) end
	TimedChanged()
	TellCancel(p)
	return "taken", p
end

-- Every client, at a timed word's time: its giver's guild word (O1, dated its time), taken as
-- though heard from him, unless he gives no words by then (it lapses); his own client sends it
-- too, for the clients before 1.1.6. His client waits WARMUP online first for one it held from an
-- earlier session (he was away at its time, or since he gave it): a cancel that came while he was
-- away is repeated until the word goes (Tick), and finds it before it applies. True when one applied.
function Moderation.ApplyDue()
	local clock, changed = Clock(), false
	local warm = loginAt == nil or ns.Now() - loginAt >= Moderation.WARMUP
	for _, p in pairs(Timed()) do
		local waits = type(p) == "table" and not warm and Key("c", p.by) == Key("c", ns.me or "") and not sentNow[Key("g", p.name) .. p.at]
		if type(p) == "table" and not p.cancel and not p.applied and clock >= p.when and not waits then
			p.applied, changed = true, true
			if Moderation.IsIssuer(p.by) then
				local e = Applied(p)
				local result = Take(e)
				ns.Log("net-off: %s's timed word applied (%s)", p.name, result)
				if result == "taken" and Given(e) and Moderation.CanIssue() then Send(e) end
			else
				p.lapsed = true
				ns.Log("net-off: %s's timed word lapsed: %s gives no words now", p.name, p.by)
			end
		end
	end
	if changed then TimedChanged() end
	return changed
end

local function TimedWord(p)
	local msg
	if p.cancel then msg = ("O2~0~%d~%d~%s~%s~"):format(p.cancel.at, p.when, p.name, p.cancel.by)
	else msg = ("O2~1~%d~%d~%s~%s~%s"):format(p.at, p.when, p.name, p.by, p.reason or "") end
	return #msg <= 250 and msg or msg:sub(1, 250)
end
Moderation.TimedWord = TimedWord

local function SendTimed(p)
	p.sent = ns.Now()
	sentNow[Key("g", p.name) .. p.at] = true
	-- Logged (the issuer's own words), one per guild in the queue (a cancel takes its word's place).
	ns.Comm.Send("CHANNEL", TimedWord(p), "netoff:t:" .. Key("g", p.name), nil, true)
end

function Moderation.HandleTimed(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.unlogged = stats.unlogged + 1
		return
	end
	local flag, at, when, name, by, reason = tostring(text):match("^O2~([01])~(%d+)~(%d+)~([^~]+)~([^~]+)~?(.*)$")
	if not flag then return end
	sender = ns.FullName(sender)
	if not Moderation.IsIssuer(sender) then
		return Refuse(sender, "not the King, his Steward, a Hand or a High Councillor here")
	end
	-- From its giver's own client (or its canceller's) alone: never one passed on.
	if Key("c", CharName(by) or "?") ~= Key("c", sender) then return Refuse(sender, "a timed word passed on for " .. tostring(by)) end
	local result
	if flag == "0" then
		local guild = GuildName(name)
		at, when = tonumber(at), tonumber(when)
		if not guild or not at or at < 1 or at > Clock() + Moderation.DATE_AHEAD or not when then return Refuse(sender, "cancel") end
		result = CancelTimed({ name = guild, at = at, when = when, by = sender })
	else
		local e, why = Moderation.TimedEntry(name, at, when, sender, reason)
		if not e then return Refuse(sender, tostring(why)) end
		if Clock() - e.when > Moderation.EXILE_LATE then return Refuse(sender, "past its time") end
		local kept
		result, kept = TakeTimed(e)
		-- Its giver repeats a word cancelled here (he never heard the cancel): its canceller answers.
		if (result == "cancelled" or result == "same") and type(kept) == "table" and kept.cancel then Moderation.AnswerCancel(kept) end
	end
	stats.timed = (stats.timed or 0) + (result == "taken" and 1 or 0)
	if result ~= "taken" and result ~= "same" then ns.Log("net-off timed word from %s: %s", sender, result) end
end
ns.Comm.Handle("O2", function(...) Moderation.HandleTimed(...) end)

-- The timed word that waits on this guild, or nil.
function Moderation.TimedFor(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	local p = Timed()[Key("g", guild)]
	return Waiting(p) and p or nil
end

-- The timed words that wait, the soonest first.
function Moderation.TimedList()
	local out, clock = {}, Clock()
	for _, p in pairs(Timed()) do if Waiting(p, clock) then out[#out + 1] = p end end
	table.sort(out, function(a, b)
		if a.when ~= b.when then return a.when < b.when end
		return Key("g", a.name) < Key("g", b.name)
	end)
	return out
end

-- Our own guild's timed word while it waits (never on the King's client), or nil.
function Moderation.ExileOfMine()
	local p = Moderation.TimedFor(GetGuildInfo and GetGuildInfo("player") or nil)
	return p and AboutMe({ kind = "g", name = p.name }) and p or nil
end

-- May this client's player cancel it: its giver, or one from higher up.
function Moderation.MayCancel(p)
	if not (Waiting(p) and Moderation.CanIssue()) then return false end
	return Key("c", p.by) == Key("c", ns.me) or Rank(ns.me) > Rank(p.by)
end

-- A notice its giver may pick: one of EXILE_DELAYS (in seconds).
local function Offered(delay)
	delay = tonumber(delay)
	for _, d in ipairs(Moderation.EXILE_DELAYS) do if d == delay then return true end end
	return false
end

-- Exiles `input` (an Olympus guild; the target's by default) `delay` seconds from now (one of
-- EXILE_DELAYS), with a reason: this client's timed word, kept and sent at once. True when given.
function Moderation.Exile(input, delay, reason)
	if not ns.IsMember() then ns.Print(L.MEMBERS_ONLY) return false end
	if not Moderation.CanIssue() then ns.Print(L.NETOFF_ONLY) return false end
	local name = GuildName(input, true)
	if not name then ns.Print(L.NETOFF_GUILD_BAD) return false end
	if ns.IsKingGuild(name) then ns.Print(L.NETOFF_NOT_KING_GUILD) return false end
	if not Offered(delay) then ns.Print(L.NETOFF_EXILE_DELAY_BAD) return false end
	delay = tonumber(delay)
	reason = Clean(reason)
	if reason == "" then ns.Print(L.NETOFF_REASON_NEEDED) return false end
	local label = Label({ kind = "g", name = name })
	if Moderation.Guild(name) then ns.Print(L.NETOFF_EXILE_ALREADY_OFF:format(label)) return false end
	local at = Clock()
	local kept = Timed()[Key("g", name)]
	if type(kept) == "table" then at = math.max(at, kept.at + 1, kept.cancel and kept.cancel.at + 1 or 0) end
	local e = { name = name, at = at, when = at + delay, by = ns.me, reason = reason }
	local result = TakeTimed(e)
	if result == "outranked" or result == "held" or result == "cancelled" then ns.Print(L.NETOFF_HELD_HIGHER:format(label)) return false end
	if result ~= "taken" then ns.Print(L.NETOFF_FULL) return false end
	SendTimed(e)
	ns.Print(L.NETOFF_EXILE_DONE:format(label, Hour(e.when), reason))
	return true
end

-- Cancels the timed word that waits on `input` (its giver, or one from higher up). True when done.
function Moderation.CancelExile(input)
	if not ns.IsMember() then ns.Print(L.MEMBERS_ONLY) return false end
	if not Moderation.CanIssue() then ns.Print(L.NETOFF_ONLY) return false end
	local name = GuildName(input, true)
	if not name then ns.Print(L.NETOFF_GUILD_BAD) return false end
	local label = Label({ kind = "g", name = name })
	local p = Moderation.TimedFor(name)
	if not p then ns.Print(L.NETOFF_EXILE_NONE:format(label)) return false end
	if not Moderation.MayCancel(p) then ns.Print(L.NETOFF_HELD_HIGHER:format(label)) return false end
	local result = CancelTimed({ name = p.name, at = math.max(Clock(), p.at), when = p.when, by = ns.me })
	if result ~= "taken" then ns.Print(L.NETOFF_EXILE_NONE:format(label)) return false end
	SendTimed(p)
	ns.Print(L.NETOFF_EXILE_CANCELLED:format(label))
	return true
end

-- The dialogs: which guild (or the target's), then how long, then why, then a last yes.
function Moderation.AskExile(name, delay)
	if not Moderation.CanIssue() then return ns.Print(L.NETOFF_ONLY) end
	-- (A notice not offered, /oly netoff guild <name> in 45, is refused before any question.)
	if delay ~= nil and not Offered(delay) then return ns.Print(L.NETOFF_EXILE_DELAY_BAD) end
	local full = name and name ~= "" and GuildName(name) or nil
	if name and name ~= "" and not full then return ns.Print(L.NETOFF_GUILD_BAD) end
	if not full then return ns.ShowDialog("OLYMPUS_EXILE_GUILD", nil, nil, {}) end
	local label = Label({ kind = "g", name = full })
	if delay then return ns.ShowDialog("OLYMPUS_EXILE_WHY", label, nil, { name = full, delay = delay }) end
	return ns.ShowDialog("OLYMPUS_EXILE_WHEN", label, nil, { name = full })
end

local function ExileNext(_, text)
	local full = GuildName(text, true)
	if not full then return ns.Print(L.NETOFF_GUILD_BAD) end
	ns.ShowDialog("OLYMPUS_EXILE_WHEN", Label({ kind = "g", name = full }), nil, { name = full })
end
StaticPopupDialogs["OLYMPUS_EXILE_GUILD"] = WhoDialog(L.NETOFF_EXILE_GUILD_PROMPT, 240, 40, function()
	local guild = GetGuildInfo and GetGuildInfo("target")
	return guild and ns.IsFederation(guild) and guild or ""
end, ExileNext)

local function ExileWhy(data, delay)
	if type(data) ~= "table" or not data.name then return end
	ns.ShowDialog("OLYMPUS_EXILE_WHY", Label({ kind = "g", name = data.name }), nil, { name = data.name, delay = delay })
end
-- How long: two answers and Cancel (the writ's way: only a click counts, never Escape).
StaticPopupDialogs["OLYMPUS_EXILE_WHEN"] = {
	text = L.NETOFF_EXILE_WHEN_PROMPT,
	button1 = L.NETOFF_EXILE_IN:format(Moderation.EXILE_DELAYS[1] / 60),
	button2 = L.NETOFF_EXILE_IN:format(Moderation.EXILE_DELAYS[2] / 60),
	button3 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("net-off timed when", ExileWhy, data or (self and self.data), Moderation.EXILE_DELAYS[1]) end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("net-off timed when", ExileWhy, data or (self and self.data), Moderation.EXILE_DELAYS[2]) end
	end,
	OnAlt = function() end,
	noCancelOnEscape = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function ExileConfirm(data, text)
	if type(data) ~= "table" or not data.name then return end
	local reason = Clean(text)
	if reason == "" then return ns.Print(L.NETOFF_REASON_NEEDED) end
	ns.ShowDialog("OLYMPUS_EXILE_CONFIRM", Label({ kind = "g", name = data.name }), L.NETOFF_EXILE_MINUTES:format((tonumber(data.delay) or 0) / 60),
		{ name = data.name, delay = data.delay, reason = reason })
end
StaticPopupDialogs["OLYMPUS_EXILE_WHY"] = {
	text = L.NETOFF_EXILE_WHY_PROMPT,
	button1 = L.WRIT_NEXT,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = Moderation.REASON_MAX,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("net-off timed why", ExileConfirm, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent()
		ns.SafeCall("net-off timed why", ExileConfirm, data or (parent and parent.data), self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The last yes: nothing is given before it.
StaticPopupDialogs["OLYMPUS_EXILE_CONFIRM"] = {
	text = L.NETOFF_EXILE_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) == "table" then ns.SafeCall("net-off timed", Moderation.Exile, data.name, data.delay, data.reason) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_EXILE_CANCEL"] = {
	text = L.NETOFF_EXILE_CANCEL_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) == "table" then ns.SafeCall("net-off timed cancel", Moderation.CancelExile, data.name) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Keeping the list alive: prune, repeat
---------------------------------------------------------------------------

-- Does a word still live, by the server's clock? One taking a name off lapses OFF_KEEP after it
-- was given, one putting it back on ON_KEEP after (never sooner: an older word never comes back).
local function Live(e, clock)
	return clock - e.at <= (e.off and Moderation.OFF_KEEP or Moderation.ON_KEEP)
end

-- Words past their time go, on every client. An "off" word nobody repeated for STALE lapses here
-- too, unless this client's own player gave it and still may give words (it repeats it, after
-- WARMUP): the words of one who may no longer give any (hidden, or off the lists), or who has not
-- been online to repeat them, fade from the army.
function Moderation.Prune()
	local now, clock = ns.Now(), Clock()
	local issuer = Moderation.CanIssue()
	local drops = {}
	for kind in pairs(Moderation.MAX) do
		for key, e in pairs(Store()[kind]) do
			if type(e) ~= "table" or type(e.at) ~= "number" or type(e.name) ~= "string" or not Live(e, clock)
				or (e.off and now - (tonumber(e.heard) or 0) > Moderation.STALE and not (issuer and Given(e) and Moderation.IsIssuer(e.by))) then
				drops[#drops + 1] = { kind, key }
			end
		end
	end
	for _, d in ipairs(drops) do
		Store()[d[1]][d[2]] = nil
		stats.dropped = stats.dropped + 1
	end
	if #drops > 0 then
		Dirty()
		ns.Fire("DATA_CHANGED")
	end
	-- 1.1.6: a timed word, or its cancel, goes EXILE_KEEP after its time (a repeat of it is
	-- refused by then: EXILE_LATE).
	local timed = Timed()
	for key, p in pairs(timed) do
		if type(p) ~= "table" or type(p.when) ~= "number" or clock - p.when > Moderation.EXILE_KEEP then timed[key] = nil end
	end
end

-- Every minute: an issuer's client repeats the words due, a few at a time; a word it held unheard
-- waits until it has been online WARMUP (a newer word may come). The army repeats
-- REPEATS_A_MINUTE words a minute at most, however long the list: a longer one is repeated less
-- often. Only a word its own player gave (1.1 review, Konig: never one heard, whose giver it
-- names: a word passed on in the King's name went out from his client as his own, at his rank),
-- while he may still give words, and one the others would take from this client (a word aimed
-- at one who gives words, only from higher up).
function Moderation.Tick()
	Moderation.Prune()
	-- 1.1.6: on every client, the timed words whose time came (a timer does it on the second).
	Moderation.ApplyDue()
	if not Moderation.CanIssue() then return 0 end
	local now, clock, sent = ns.Now(), Clock(), 0
	local warm = loginAt == nil or now - loginAt >= Moderation.WARMUP
	-- 1.1.6: the timed words first (they wait an hour at most): its giver's own while it waits, or
	-- its canceller's cancel until it goes from the lists (EXILE_KEEP after its time: its giver,
	-- away when it came, may log in after its time). One held unheard from an earlier session waits
	-- WARMUP too (a cancel from higher up may come).
	for _, p in pairs(Timed()) do
		if sent >= Moderation.PER_TICK then return sent end
		local due
		if type(p) == "table" and p.cancel then due = Key("c", p.cancel.by) == Key("c", ns.me)
		elseif type(p) == "table" then due = not p.applied and clock < p.when and Key("c", p.by) == Key("c", ns.me) end
		if due and Moderation.IsIssuer(ns.me) then
			p.jitter = p.jitter or Moderation.random(0, Moderation.JITTER)
			local age = now - (tonumber(p.sent) or 0)
			if age >= Moderation.EXILE_REPEAT + p.jitter and (warm or sentNow[Key("g", p.name) .. p.at]) then
				SendTimed(p)
				sent = sent + 1
			end
		end
	end
	local words = 0
	for kind in pairs(Moderation.KINDS) do words = words + Count(Store()[kind]) end
	local spread = words * 60 / Moderation.REPEATS_A_MINUTE
	local mine = Rank(ns.me)
	for kind in pairs(Moderation.KINDS) do
		for _, e in pairs(Store()[kind]) do
			if sent >= Moderation.PER_TICK then return sent end
			if Given(e) then
				e.jitter = e.jitter or Moderation.random(0, Moderation.JITTER)
				local every = math.max(e.off and Moderation.REPEAT or Moderation.ON_EVERY, spread)
				local age = now - (tonumber(e.heard) or 0)
				if Live(e, clock) and age >= every + e.jitter and (warm or age <= Moderation.STALE) and Moderation.IsIssuer(e.by) then
					local target = e.kind == "c" and TargetRank(e.name) or 0
					if target == 0 or math.min(Rank(e.by), mine) > target then
						Send(e)
						sent = sent + 1
					end
				end
			end
		end
	end
	return sent
end

-- The backstop in Comm (1.1): a client whose own character or guild is off sends none of BLOCKED,
-- nor a call of the Throne's that every receiver would drop (King.HIDDEN_CALLS). Its setter's
-- cancel of an entry on the King's week (a D of 0 seconds; Week.Cancel sends one for his own
-- entry alone) still goes: every client takes it for his own entry (1.1 review: held, the entry
-- showed again everywhere once he was shown again).
local function HiddenCall(msg)
	local K = ns.King
	if msg:find("^T1~D~%d+~[^~]*~0~") then return false end
	return msg:sub(1, 3) == "T1~" and type(K) == "table" and type(K.HIDDEN_CALLS) == "table" and K.HIDDEN_CALLS[msg:sub(4, 4)] == true
end
function Moderation.Blocks(msg)
	if type(msg) ~= "string" or msg:sub(3, 3) ~= "~" then return false end
	-- A private LY withdrawal carries no location: it only invalidates this sender's answer to
	-- one still-active discovery request. Let it leave after a local opt-out/net-off, as the
	-- week lets a setter withdraw their own entry, so already delivered evidence fails closed.
	if msg:match("^LY~X~1~%d+~%d+$") then return false end
	if not Moderation.BLOCKED[msg:sub(1, 2)] and not HiddenCall(msg) then return false end
	if not Moderation.SelfOff() then return false end
	stats.blocked = stats.blocked + 1
	return true
end

function Moderation.Stats() return stats end

-- /oly status: what this client holds.
function Moderation.StatusLine()
	local x = Index()
	local own = Moderation.OwnGuildOff()
	return ("%d characters and %d guilds off here%s  |  you give words: %s  |  words taken %d, repeats %d, older %d, refused %d, unlogged %d, sends held %d, reports dropped %d  |  timed words waiting %d (taken %d)"):format(
		x.n.c, x.n.g, own and " (your guild among them)" or "", tostring(Moderation.CanIssue()), stats.taken or 0, stats.same or 0,
		stats.older or 0, stats.refused, stats.unlogged, stats.blocked, stats.reports, #Moderation.TimedList(), stats.timed or 0)
end

-- The words kept by this client in an earlier session: checked again (the SavedVariables can be
-- edited), at load.
function Moderation.Load()
	Dirty()
	local s = Store()
	for kind, list in pairs(s) do
		if not Moderation.MAX[kind] or type(list) ~= "table" then
			s[kind] = nil
		else
			for key, e in pairs(list) do
				local ok = type(e) == "table" and Moderation.Entry(kind, e.name, e.off, e.at, e.by, e.reason)
				if not ok or Key(kind, ok.name) ~= key then
					list[key] = nil
				else
					ok.heard = tonumber(e.heard) or 0
					-- Who passed it on, when someone did (the King's own word is one that was not).
					ok.via = e.via ~= nil and (CharName(e.via) or "?") or nil
					list[key] = ok
				end
			end
		end
	end
	Dirty()
	-- 1.1.6: the timed words, each checked as a heard one is; one whose cancel no longer reads
	-- goes whole (it never comes back to life without its cancel).
	local timed = Timed()
	for key, p in pairs(timed) do
		local ok = type(p) == "table" and Moderation.TimedEntry(p.name, p.at, p.when, p.by, p.reason)
		local c = ok and p.cancel
		local cancel = type(c) == "table" and CharName(c.by) and tonumber(c.at) and { at = tonumber(c.at), by = CharName(c.by), heard = tonumber(c.heard) or 0 }
		if not ok or Key("g", ok.name) ~= key or (c ~= nil and not (cancel and cancel.at >= ok.at and cancel.at < ok.when)) then
			timed[key] = nil
		else
			ok.heard, ok.sent = tonumber(p.heard) or 0, tonumber(p.sent) or 0
			ok.applied, ok.lapsed, ok.cancel = p.applied == true or nil, p.lapsed == true or nil, cancel or nil
			timed[key] = ok
		end
	end
end
ns.On("INIT", function() Moderation.Load() end)

ns.On("LOGIN", function()
	loginAt = ns.Now()
	ns.Every(60, "net-off", Moderation.Tick)
	-- Once the guild and the lists are known: tell the player if a word hides them.
	ns.After(30, "net-off notice", function()
		local e = Moderation.SelfOff()
		if e then Notify(e) end
		-- 1.1.6: our guild's timed word, heard before this login, while it still waits.
		local p = not e and Moderation.ExileOfMine()
		if p then TellExile(p) end
	end)
end)

-- Tests start from a clean state (login: a new session begun at that time, for WARMUP).
function Moderation.Reset(login)
	index, loginAt = nil, tonumber(login)
	wipe(toldMe)
	wipe(toldExile)
	wipe(sentNow)
	if exileFrame then exileFrame:Hide() end
	exileFrame = nil
	wipe(guildOf)
	guildsKnown = 0
	for k in pairs(stats) do stats[k] = 0 end
end
