local ADDON, ns = ...
local L = ns.L

-- 1.2, the Blood Arena: finding an opponent (the design). A player who wants a duel or a Bone
-- Throw game asks the Olympus channel; players who let themselves be found (the privacy page's
-- "arenaFind" line) or who search too answer him alone, a handful however crowded the zone; he
-- asks the nearest one; that player's popup says who, where and how far; on Let's go both get a
-- card (OlympusArenaMatchCard) that guides them to a fair meeting place and hands off to the
-- duel, the challenge dialog or the Bones table. A match moves nothing and counts nothing.
--
-- One message type, AM (the design), numbers in base 36, positions as 400-yd cells (the design):
--   AM~<M>1~Q~qid~game~kind~guild~cont~mapID~zuid~lvl~lo~hi~scope~pct     (channel) who can play?
--   AM~<M>1~O~qid~s|f~guild~same~lvl~class~games~kinds~grp[~cx~cy]        (whisper) I can
--   AM~<M>1~R~mid~qid~game~kind~lo~hi~lvl~class~cx~cy~grp                 (whisper) let's meet
--   AM~<M>1~A~mid~Y~place~cx~cy~mapID~zuid~lo~hi~grp | A~mid~N            (whisper, urgent) yes / no
--   AM~<M>1~P~mid~rev~place~P|A                                           (whisper) a spot, or yes to it
--   AM~<M>1~H~mid~1|0~zuid                                                (whisper) I'm there, or not
--   AM~<M>1~C~mid~c|t|i|d                                                 (whisper) over: cancelled,
--                                                                          a clock, an instance, done
-- A release sends L, a test build T (its Q on its group's lane). game d|b (e: either), kind c|s
-- (e: either), Q's lo~hi a level range, the others' lo~hi a stake range in whole silver; grp 0 (no
-- group), 1 (in a group I can invite into), 2 (one I cannot); place a places.lua id, "=" (close
-- by) or "@x.y" (a point to 25 yd). No message carries free text but a guild's name.
--
-- Whispers to the other player are real game whispers (ns.SayTo), each a fixed line, and each
-- inside the player's click (Let's go, On my way, Other spot, Cancel); the addon never reads
-- CHAT_MSG_WHISPER. Invites are clicks too; the addon never accepts one. Nothing about positions
-- is saved; blocks go to ns.db.blocked (as /oly block) and the game's ignore list, declines (30
-- min) and lies (24 h) to ns.db.arenaMatch.
--
-- The weight rule (the design): an idle client holds the AM handler alone, and a Q returns after one
-- flag lookup unless the player is findable or searching. A search, a popup or a match is
-- Arena.Involve("match", true), with one 1-s Arena.Every; an answer's delay is an Arena.After.
-- The card is built on first use (its OnUpdate, which keeps it clear of the popups, runs only
-- while it shows); no WoW event is registered.
--
-- API (for the fights part, the Bones tables and the screens):
--   ArenaMatch.Start(opts) -> true | false, why: opts = { game = "d"|"b"|"e", kind = "c"|"s"|"e",
--     lo, hi (a stake range in copper, whole silver kept, at most Standing.Cap("bet")), level =
--     0 (any) | 5 | 10, reach = "z" (my zone) | "c" (this continent), share = true (share my
--     zone while I search) }; Staked where it cannot be: false and the check's reason; Either:
--     casual then.
--   ArenaMatch.Stop(), ArenaMatch.View() (the Find dialog's and the tab's view model: state,
--     line, findable, can, sharing, staked[d|b], stakeMax, firstTime, firstLine, rehearsal,
--     search, offers (the King's), match, ended),
--   ArenaMatch.SetFindable(on, { d, b, staked }), ArenaMatch.Findable() -> on, why,
--   ArenaMatch.CanSearch(opts) -> ok, why, ArenaMatch.WhyText(why),
--   ArenaMatch.Vet(sender, game "d"|"b", stake in copper) -> true | false, "m": the fights part and the Bones tables,
--     before showing a challenge or a table invite from a matched partner (the design). Outside the
--     range both agreed (a casual match agreed none; another game only without a stake): no.
--     A yes hands the match over on the receiver's side too (its clocks stop) and returns the
--     exact match id as its second value so the local fight/table can retain it without a wire,
--   ArenaMatch.Ended(mid): the fights part and the Bones tables, when the fight or table a match handed off to ends (the
--     group the match formed goes then),
--   ArenaMatch.Pick(id): the King picks one of his offers (View().offers), ArenaMatch.Card(),
--   the action "match.open" (Arena.Do("match.open", "d"|"b")), /oly arena find.
-- The hand-off (the design): [Challenge] or [Open the table] opens the screens' or the Bones tables' panel pre-filled
--   ({ stake = the lowest agreed, from = mid }); the match is then handed over: its clocks stop,
--   the card keeps Done, and it ends with Ended, Done, Cancel or after HANDED_MAX. (Neither
--   panel tells this file when its challenge or invitation left, so the match is not ended at
--   that moment itself.) Vet holds the agreed stake only while the match lives here.
-- Stand-ins it calls when there: ArenaUI.OpenFind(game) (the screens' Find dialog), ArenaUI.Challenge(
--   name, { stake, from }) (the screens, a staked duel), ArenaUI.BoneInvite({ guest, stake, practice,
--   from }) (the screens' way to the Bones tables' create panel; else ArenaUI.CreateTable, the same table),
--   Debts.SameOwner, Standing.Cap("bet"), and for Staked the two checks in their own shapes:
--     Arena.Can("fights.challenge", opponent, { stake, match = true })   (the fights part's F.CanChallenge)
--     Arena.Can("farkle.create", { guest, stake, match = true })          (the Bones tables' FT.CanCreate)
--   stake: the lower end of the range in copper (1 silver while none is chosen); opponent and
--   guest: the other player once one is known, nil before (the search, the Find dialog). For the
--   integrator: the fights part's and the Bones tables' checks should accept opts.match with no opponent or guest (today
--   they answer "opponent" and "guest" first), and skip the design's inn rule for it (the Bones tables applies it
--   when the table is created). Until then this file takes those answers as "not known yet": a
--   search starts, and the check with the other player's name decides each request.

local ArenaMatch = {}
ns.ArenaMatch = ArenaMatch
local Arena = ns.Arena
local Places = ns.Places

ArenaMatch.SEARCH_TIME = 600      -- a search lives 10 min, its findable tail included
ArenaMatch.ASK_GAP = 20           -- the second ask, 20 s after the first
ArenaMatch.WINDOW = { z = 4, c = 5 } -- seconds an ask collects answers before the first request
ArenaMatch.WANTED = 6             -- answers wanted per ask, however crowded
ArenaMatch.PCT_MIN = 5
ArenaMatch.SEARCHES = 3           -- searches in SEARCH_SPAN at most
ArenaMatch.SEARCH_SPAN = 900
ArenaMatch.Q_MAX = 6              -- a sender's asks heard in Q_SPAN; more are dropped
ArenaMatch.Q_SPAN = 900
ArenaMatch.ANSWER_GAP = 600       -- one answer per asker per 10 min
ArenaMatch.OFFER_TTL = 120        -- a request answers one of our offers within 2 min
ArenaMatch.REQUESTS = 3           -- requests per search
ArenaMatch.REQUEST_WAIT = 32      -- no answer this long: the next offer
ArenaMatch.RETRY_TARGET = 600     -- the same target once per 10 min
ArenaMatch.POPUP_TIME = 30
ArenaMatch.PLACE_TIME = 180       -- agreeing on the place
ArenaMatch.HERE_TIME = 600        -- after both arrived
ArenaMatch.TRAVEL_BASE = 300      -- the travel clock: 5 min plus the longer walk...
ArenaMatch.TRAVEL_SPEED = 7       -- ...at 7 yd/s...
ArenaMatch.TRAVEL_SLACK = 1.5     -- ...times 1.5...
ArenaMatch.TRAVEL_MAX = 1800      -- ...at most 30 min
ArenaMatch.TRAVEL_MORE = 600      -- "10 more minutes"
ArenaMatch.STILL_WAIT = 300       -- "Still coming?" unanswered this long: the match ends
ArenaMatch.HANDED_MAX = 1800      -- a hand-off's card and its Vet, at most
ArenaMatch.INSTANCE_END = 120     -- 2 min in an instance ends a match
ArenaMatch.DECLINE_TIME = 1800
ArenaMatch.LIE_TIME = 86400
ArenaMatch.PAUSE_TIME = 1800      -- two unanswered popups in a row: not findable for 30 min
ArenaMatch.NOES = 2
ArenaMatch.LIE_SPEED = 15         -- yd/s a searcher's cell may move between its O and its A
ArenaMatch.NEAR = 300             -- "=" chosen under 300 yd...
ArenaMatch.NEAR_OK = 900          -- ...and accepted under 900 yd between the cells
ArenaMatch.ARRIVE = 40            -- arrived: within 40 yd of a spot, a point or the partner...
ArenaMatch.ARRIVE_ARENA = 60      -- ...or 60 of an arena
ArenaMatch.BANDS = { 500, 1500, 4000 }
ArenaMatch.P_GAP = 3
ArenaMatch.P_MAX = 10
ArenaMatch.H_GAP = 5
ArenaMatch.CARD_EVERY = 2         -- the card's line, while travelling
ArenaMatch.OTHER_SPOTS = 5
ArenaMatch.LEVEL_ANY = { 1, 100 }
-- Staked is offered only when the challenge's (the fights part) or the table's (the Bones tables) own check says yes.
ArenaMatch.STAKE_CHECK = { d = "fights.challenge", b = "farkle.create" }
-- [Show on map] stays hidden until in-game check 21 passes (the design), with the gamepad UI too.
ArenaMatch.SHOW_ON_MAP = false
ArenaMatch.random = math.random -- tests
ArenaMatch.CARD_WIDTH = 400
ArenaMatch.ROOM_KEEP_AFTER = 1800 -- a private match room may be resumed for 30 min after it ends
ArenaMatch.ROOM_HISTORY_MAX = 4   -- session-only metadata; matchmaking still has one live state

local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER" }
local GAMES = { d = true, b = true }
local KINDS = { c = true, s = true }
local END_CODES = { c = "cancel", t = "time", i = "instance", d = "done" }

local search      -- my search: { opts, started, untilT, asks, offers, count, tried, requests, current, phase, ... }
local match       -- the live match
local popup       -- the request on screen
local handed = {} -- [mid] = { name, game, lo, hi, formed, t }: matches handed to a fight or a table
local offered = {} -- [qid|sender] = what we offered on (a request must answer one)
local answered = {} -- [sender] = when we last answered him
local heardQ = {}  -- [sender] = { times }: his asks heard lately
local sentMids = {} -- [mid] = { key, t }: the name we requested and when (a late yes gets one C~t)
local requested = {} -- [name] = when we last requested him
local searches = {} -- when our searches started
local lastOffer = -math.huge
local ended       -- the last match's end, for the card: { name, why, role, game, opts }
local roomEnded = {} -- [mid] = bounded, session-only metadata for a recently ended private room
local sheet       -- the quick Find sheet on the card (no Find dialog in the companion): { game }
local showOther = false
local ticking, lastTick = false, nil
local card
local stats = { asks = 0, offers = 0, heard = 0, requests = 0, popups = 0, matches = 0, lies = 0, dropped = 0 }

-- (Below, used before they are defined.)
local Next, Request, End, RefreshCard, ShowCard, PlaceCard, Involvement, StopSearch, NewMatch, Tick, Open

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Now() return Arena.Now() end
local function Lower(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function SameName(a, b) local x = Lower(a) return x ~= nil and x == Lower(b) end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local B36, N = Arena.B36, Arena.N
local floor, max, min, huge = math.floor, math.max, math.min, math.huge

-- Text with {key} filled from t (a translation may put the values in any order).
local function Fill(text, t)
	return (tostring(text or ""):gsub("{(%w+)}", function(k)
		local v = t and t[k]
		if v == nil then return "{" .. k .. "}" end
		return tostring(v)
	end))
end
ArenaMatch.Fill = Fill

local function Mode() return Arena.TestBuild() and "T" or "L" end
local function Log(fmt, ...) ns.Log("match: " .. fmt, ...) end
-- A line the card carries: in chat only while the player has the card closed.
local function Note(text)
	if not (card and card:IsShown()) then ns.Print(text) end
end

local function Round(n, step) step = step or 10 return floor((tonumber(n) or 0) / step + 0.5) * step end
local function About(n) return max(50, Round(n, 50)) end

-- The world position UnitPosition gives (the first value grows to the north, the second to the
-- west) and the continent: cont, wx, wy, or nil (an instance, a secret value, no API).
local function Pos()
	if type(UnitPosition) ~= "function" or Arena.InInstance() then return nil end
	local ok, y, x, _, inst = pcall(UnitPosition, "player")
	if not ok or Secret(y) or Secret(x) or Secret(inst) then return nil end
	if type(y) ~= "number" or type(x) ~= "number" or (inst ~= 0 and inst ~= 1) then return nil end
	return inst, y, x
end
ArenaMatch.Position = Pos
local function Here()
	local cont, wx, wy = Pos()
	if not cont then return nil end
	return { cont = cont, wx = wx, wy = wy }
end

local function MapNow()
	local C = C_Map
	if not (C and C.GetBestMapForUnit) then return nil end
	local ok, id = pcall(C.GetBestMapForUnit, "player")
	if ok and type(id) == "number" and not Secret(id) then return id end
	return nil
end
local function ZoneName(mapID, fallback)
	local C = C_Map
	if mapID and C and C.GetMapInfo then
		local ok, info = pcall(C.GetMapInfo, mapID)
		if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
	end
	return fallback or "?"
end
-- Our layer's zone UID in that zone while it is fresh (Hop.LAYER_FRESH), else 0.
local function Zuid(mapID)
	local Ly = ns.Layers
	local mine = Ly and Ly.Mine and Ly.Mine()
	local fresh = ns.Hop and ns.Hop.LAYER_FRESH or 600
	if type(mine) == "table" and mapID and mine.mapID == mapID and tonumber(mine.zoneUID) and ns.Now() - (mine.t or 0) <= fresh then
		return floor(mine.zoneUID)
	end
	return 0
end
local function Level() return UnitLevel and tonumber(UnitLevel("player")) or 0 end
local function ClassID()
	if not UnitClass then return 0 end
	local _, _, id = UnitClass("player")
	return tonumber(id) or 0
end
local function ClassName(id)
	local file = CLASS_FILES[id or 0]
	if file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] then return LOCALIZED_CLASS_NAMES_MALE[file] end
	if GetClassInfo and id then
		local ok, name = pcall(GetClassInfo, id)
		if ok and type(name) == "string" then return name end
	end
	return file and (file:sub(1, 1) .. file:sub(2):lower()) or "?"
end
local function Guild() return (GetGuildInfo and GetGuildInfo("player")) or "" end

-- 0 no group, 1 a group I can invite into (leader or assistant, with room), 2 one I cannot.
local function Grp()
	local H = ns.Hop
	if not (H and H.GroupState) then return (IsInGroup and IsInGroup()) and 2 or 0 end
	local n, room = H.GroupState()
	if (n or 0) == 0 then return 0 end
	return room and 1 or 2
end
-- Who invites (the design): neither in a group, the partner; one in a group he can invite into, that
-- one; else nobody (a group is not possible).
local function Inviter(seekerGrp, partnerGrp)
	if seekerGrp == 0 and partnerGrp == 0 then return "partner" end
	if seekerGrp == 0 and partnerGrp == 1 then return "partner" end
	if seekerGrp == 1 and partnerGrp == 0 then return "seeker" end
	return nil
end
local function GroupPossible(a, b) return Inviter(a, b) ~= nil end
ArenaMatch.Inviter = Inviter

-- A cell (400 yd) or a point (25 yd) of a world coordinate, and back.
local function Cell(w) return Places.Cell(w) end
local function Centre(c) return Places.Centre(c) end
local function CellPoint(cont, cx, cy) return { cont = cont, wx = Centre(cx), wy = Centre(cy) } end
-- The least distance two players in these two cells can be apart (neighbouring cells: 0).
local function CellGap(a, b)
	local dx = max(0, math.abs(a[1] - b[1]) - 1) * Places.CELL
	local dy = max(0, math.abs(a[2] - b[2]) - 1) * Places.CELL
	return math.sqrt(dx * dx + dy * dy)
end

local function Channel() return ns.Comm and ns.Comm.ChannelReady and ns.Comm.ChannelReady() ~= false end

local function Send(body)
	return Arena.Send("AM", Mode(), body, {})
end
local function SendTo(name, body, o)
	o = o or {}
	return Arena.Send("AM", Mode(), body, { to = name, urgent = o.urgent, done = o.done })
end
-- The server says the other player is offline (the outbox's result 12, or its not-found line,
-- the design): t (a request or a match) is marked, and the next tick acts on it (a done may run
-- inside Arena.Send itself).
local function Offline(t)
	return function(sent, why)
		if not sent and (why == 12 or why == "notfound") then t.offline = true end
	end
end

-- A fixed line whispered to the other player, inside the player's click (ns.SayTo).
local function Say(name, text)
	if Arena.Blocked() or type(ns.SayTo) ~= "function" then return false end
	return ns.SayTo(ns.TellName(name), ns.Cut(text, 255))
end
-- (The match's group: the invite inside the player's click, the leave from code at its end or his
-- click: neither is protected, as the layer hop's group, gp:hop-group.)
local function Invite(name) -- gp:hop-group
	local target = ns.TellName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end
end
local function LeaveGroup() -- gp:hop-group
	if C_PartyInfo and C_PartyInfo.LeaveParty then C_PartyInfo.LeaveParty() elseif LeaveParty then LeaveParty() end
end

local function DB()
	local db = ns.db
	if type(db) ~= "table" then return { declined = {}, lied = {} } end
	local m = db.arenaMatch
	if type(m) ~= "table" then m = {} db.arenaMatch = m end
	if type(m.declined) ~= "table" then m.declined = {} end
	if type(m.lied) ~= "table" then m.lied = {} end
	return m
end

---------------------------------------------------------------------------
-- Who may search, who is found, who never meets (the design)
---------------------------------------------------------------------------

local function IsKing() return ns.King ~= nil and ns.King.IsKing ~= nil and ns.King.IsKing() == true end
-- A character of the King's account: his pinned character, here or among the account's names.
local function KingAccount()
	if ns.IsKingCharacter(ns.me) then return true end
	local mine = ns.db and ns.db.myCharacters
	if type(mine) == "table" then
		local R = ns.ArenaRoles
		for key in pairs(mine) do
			local name = R and R.ProperName and R.ProperName(key) or key
			if type(name) == "string" and ns.IsKingCharacter(name) then return true end
		end
	end
	return false
end
ArenaMatch.KingAccount = KingAccount
local function CrownOn() return ns.King ~= nil and ns.King.SharingLocation ~= nil and ns.King.SharingLocation() == true end

-- The arena's tab shows: the companion's rule once it is loaded (ArenaUI.TabVisible), else
-- ArenaHome's when it has one (the usual case at login: the companion is not loaded), else the
-- stub's documented one (a member, the arena not off).
local function TabVisible()
	local ui, home = Arena.ui, ns.ArenaHome
	local t
	if type(ui) == "table" and type(ui.TabVisible) == "function" then t = ui
	elseif type(home) == "table" and type(home.TabVisible) == "function" then t = home end
	if t then
		local ok, yes = pcall(t.TabVisible)
		return ok and yes == true
	end
	return ns.IsMember() == true and not Arena.Off()
end

local function MinLevel()
	local R = ns.ArenaRoles
	local s = R and R.Settings and R.Settings()
	return type(s) == "table" and tonumber(s.minLevel) or 10
end

-- What anyone needs to search or be found: a member at the arena's level, on the network, the
-- arena on, no instance, lockdown or combat, a position.
local function Able()
	if not ns.IsMember() then return false, "guild" end
	if Level() < MinLevel() then return false, "level" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.SelfOff and M.SelfOff() then return false, "netoff" end
	if Arena.Off() then return false, "arena" end
	if Arena.Blocked() then return false, "blocked" end
	if InCombatLockdown and InCombatLockdown() then return false, "combat" end
	if not Pos() then return false, "position" end
	return true
end

-- Findable now: the player's yes (or a search of his own), location shared, not paused, not
-- quiet, never the King's account.
function ArenaMatch.Findable()
	local m = ns.db and ns.db.arenaMatch
	if not search and not (type(m) == "table" and m.find == true) then return false, "off" end
	if KingAccount() then return false, "king" end
	if not search then
		if not ns.Layers.Sharing() then return false, "location" end
		if m.pausedUntil and Now() < m.pausedUntil then return false, "paused" end
	end
	if ns.Quiet() then return false, "quiet" end
	return Able()
end

local function Ignored(name)
	local F = C_FriendList
	if not (F and F.IsIgnored) then return false end
	local ok, yes = pcall(F.IsIgnored, ns.TellName(name))
	return ok and yes == true
end

-- Never matched, whatever else: ourselves, a block or the ignore list, our own alts, a decline
-- (30 min) or a lie (24 h), another realm.
local function Barred(sender)
	local key = Lower(sender)
	if not key or key == Lower(ns.me) then return "self" end
	if Arena.RealmOf(sender) ~= ns.realm then return "realm" end
	local db = ns.db
	if db and type(db.blocked) == "table" and db.blocked[key] then return "blocked" end
	if Ignored(sender) then return "ignored" end
	local D = ns.Debts
	if type(D) == "table" and type(D.SameOwner) == "function" then
		local ok, same = pcall(D.SameOwner, ns.me, sender)
		if ok and same == true then return "alt" end
	end
	local m = db and db.arenaMatch
	if type(m) == "table" then
		local t = type(m.declined) == "table" and m.declined[key]
		if t and Now() - t < ArenaMatch.DECLINE_TIME then return "declined" end
		t = type(m.lied) == "table" and m.lied[key]
		if t and Now() - t < ArenaMatch.LIE_TIME then return "lied" end
	end
	return nil
end
ArenaMatch.Barred = Barred

-- The member check (the design), as Board.HandlePost: an Olympus guild; our own guild's name only from
-- our roster; another one only once Channels vouches for the sender (one guild per sender); and
-- never a name the moderators hide.
local function MemberOK(sender, guild)
	if type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild) then return false end
	local own = GetGuildInfo and GetGuildInfo("player")
	if own and guild == own then
		if not (ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(sender)) then return false end
	else
		local C = ns.Channels
		local level = C and C.VerifiedLevel and C.VerifiedLevel(sender, guild)
		if not level or level < 1 then return false end
	end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.Hides and M.Hides(sender, guild) then return false end
	-- (1.1.6: a sanctioned player, WatchChat.Barred, is matched with nobody while it lasts.)
	if ns.Arena.Sanctioned and ns.Arena.Sanctioned(sender) then return false end
	return true
end
ArenaMatch.MemberOK = MemberOK

-- The answers a stake check gives only for what matchmaking cannot know yet: who the other player
-- is (the fights part's "opponent", the Bones tables' "guest") before anyone is matched, and the design's inn rule ("tavern-..."),
-- which the Bones tables applies when the table is created, the two not at the inn yet (the design).
local function NotYet(why, name)
	why = tostring(why or "")
	if why:find("^tavern") then return true end
	return name == nil and (why == "opponent" or why == "guest")
end

-- Staked for a game: never where saved data is lost (the design), else as the challenge's (the fights part) or the
-- table's (the Bones tables) own check says, in its own call shape (rules, caps, a debtor, alts...: matchmaking
-- adds no money rule of its own). stake: copper (the lower end of the range; 1 silver while none
-- is chosen); name: the other player, once known.
local function StakedFor(game, stake, name)
	-- (The compliance gate first: no staked search, offer or answer while it allows no stake.)
	local C = ns.Compliance
	if not (type(C) == "table" and type(C.Allows) == "function" and C.Allows("stake", game == "d" and "fight" or "bones") == true) then
		return false, "compliance"
	end
	if not Arena.Persists() then return false, "persists" end
	local action = ArenaMatch.STAKE_CHECK[game]
	if not action then return false, "unknown" end
	stake = max(100, floor((tonumber(stake) or 0) / 100) * 100)
	local ok, why
	if game == "d" then
		ok, why = Arena.Can(action, name, { stake = stake, match = true })
	else
		ok, why = Arena.Can(action, { guest = name, stake = stake, match = true })
	end
	if ok or NotYet(why, name) then return true end
	return false, why or "unknown"
end
ArenaMatch.StakedFor = StakedFor

-- The bet cap (the money part's Standing.Cap("bet")) in whole silver, or nil where there is none.
local function CapSilver()
	local S = ns.Standing
	if type(S) ~= "table" or type(S.Cap) ~= "function" then return nil end
	local ok, cap = pcall(S.Cap, "bet", ns.me)
	if ok and tonumber(cap) then return floor(tonumber(cap) / 100) end
	return nil
end

local function LevelRange(level, lvl)
	if level == 5 or level == 10 then return max(1, lvl - level), lvl + level end
	return ArenaMatch.LEVEL_ANY[1], ArenaMatch.LEVEL_ANY[2]
end

local function Recent(list, span, now)
	local kept = {}
	for _, t in ipairs(list) do if now - t < span then kept[#kept + 1] = t end end
	return kept
end

function ArenaMatch.CanSearch(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.game == "b" and ns.FarkleTable and not ns.FarkleTable.CanPlayPlayers() then return false, "training" end
	local ok, why = Able()
	if not ok then return false, why end
	if KingAccount() then
		if not ns.IsKingCharacter(ns.me) then return false, "king" end
		if not CrownOn() then return false, "crown" end
	elseif not ns.Layers.Sharing() and not opts.share then
		return false, "location"
	end
	if search then return false, "searching" end
	if match or popup then return false, "busy" end
	searches = Recent(searches, ArenaMatch.SEARCH_SPAN, Now())
	if #searches >= ArenaMatch.SEARCHES then return false, "rate" end
	if not Channel() then return false, "channel" end
	return true
end

-- A reason in words: ours, else a stake check's own code (the fights part's, the Bones tables') in a plain line.
function ArenaMatch.WhyText(why)
	if why == "level" then return Fill(L.MATCH_WHY_LEVEL, { n = MinLevel() }) end
	local s = rawget(L, "MATCH_WHY_" .. tostring(why):upper())
	if type(s) == "string" then return s end
	return Fill(L.MATCH_WHY_STAKED, { why = tostring(why) })
end

---------------------------------------------------------------------------
-- Places: names, points, the fair choice (the design)
---------------------------------------------------------------------------

-- The place's name for the player: the client's own (C_Map.GetAreaInfo) where the table's name
-- is its area's name, else the table's (English) name.
local function AreaName(areaID)
	local C = C_Map
	if not (areaID and C and C.GetAreaInfo) then return nil end
	local ok, name = pcall(C.GetAreaInfo, areaID)
	if ok and type(name) == "string" and name ~= "" then return name end
	return nil
end
local function PlaceName(row)
	if row.areaID and row.name == row.subzone then return AreaName(row.areaID) or row.name end
	if row.insideAreaID and row.name == row.inside then return AreaName(row.insideAreaID) or row.name end
	return row.name
end
ArenaMatch.PlaceName = function(id) local row = Places.byId[id] return row and PlaceName(row) or nil end

local function Coord(v) return ("%.1f"):format(floor((tonumber(v) or 0) * 1000 + 0.5) / 10) end

-- Where the player stands, as map coordinates of his zone: mapID, x, y (0-1).
local function MapPos()
	local mapID = MapNow()
	local C = C_Map
	if not (mapID and C and C.GetPlayerMapPosition) then return mapID end
	local ok, pos = pcall(C.GetPlayerMapPosition, mapID, "player")
	if not ok or type(pos) ~= "table" or not pos.GetXY then return mapID end
	local okXY, x, y = pcall(pos.GetXY, pos)
	if not okXY or Secret(x) or Secret(y) or type(x) ~= "number" or type(y) ~= "number" then return mapID end
	return mapID, x, y
end

-- A "@x.y" point: its 25-yd steps.
local function ParsePoint(place)
	if type(place) ~= "string" then return nil end
	local a, b = place:match("^@([0-9a-z]+)%.([0-9a-z]+)$")
	local max25 = 2 * Places.OFFSET / Places.POINT - 1
	a, b = N(a, 0, max25), N(b, 0, max25)
	if not a or not b then return nil end
	return a, b
end
local function PointOf(place, cont)
	local a, b = ParsePoint(place)
	if not a then return nil end
	return { cont = cont, wx = Places.Centre(a, Places.POINT), wy = Places.Centre(b, Places.POINT) }
end

-- The words a whisper or a line takes for a place: { place, zone, x, y }. A "Where I am" point
-- is named from the speaker's side: in a whisper (to the partner) "My spot" is ours and "Your
-- spot" theirs; on the card and the status line (to the player, card = true) ours is "Your spot"
-- and theirs "{name}'s spot".
local function PlaceWords(place, mm, card)
	local row = Places.byId[place]
	if row then return { place = PlaceName(row), zone = ZoneName(row.mapID, row.zone), x = Coord(row.x), y = Coord(row.y) } end
	if place == "=" then return { place = L.MATCH_PLACE_HERE } end
	local mine = mm and mm.pointBy == "me"
	local name
	if card then
		name = mine and L.MATCH_CARD_POINT_MINE or Fill(L.MATCH_CARD_POINT_THEIRS, { name = mm and Arena.Mask(ns.DisplayName(mm.name)) or "?" })
	else
		name = mine and L.MATCH_PLACE_MINE or L.MATCH_PLACE_YOURS
	end
	return { place = name, zone = mm and mm.pointZone or "?", x = mm and mm.pointX or "?", y = mm and mm.pointY or "?" }
end

local function Casual(game, kind) return kind == "c" and (game == "d" or game == "b") end

-- The places Fair lists for this game and the two cells (the numbers as they went on the wire).
local function FairList(game, kind, cont, a, b, level)
	return Places.Fair(CellPoint(cont, a[1], a[2]), CellPoint(cont, b[1], b[2]),
		{ game = game, staked = kind == "s", faction = ns.faction, level = level })
end

-- "=" holds (the seeker's check, the design): a casual game, both maps outside the capitals, the cells'
-- centres under 900 yd apart.
local function CloseByOK(game, kind, cont, a, b, mapA, mapB)
	if not Casual(game, kind) then return false end
	if (mapA and Places.Capital(mapA)) or (mapB and Places.Capital(mapB)) then return false end
	local d = Places.Dist(CellPoint(cont, a[1], a[2]), CellPoint(cont, b[1], b[2]))
	return d ~= nil and d < ArenaMatch.NEAR_OK
end

-- A place the match may take: a Fair place, a valid "=", a point on the continent.
local function PlaceOK(mm, place)
	if place == "=" then return CloseByOK(mm.game, mm.kind, mm.cont, mm.myCell, mm.theirCell, mm.myMap, mm.theirMap) end
	if ParsePoint(place) then return true end
	if not Places.byId[place] then return false end
	for _, e in ipairs(FairList(mm.game, mm.kind, mm.cont, mm.myCell, mm.theirCell, mm.level)) do
		if e.id == place then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Searching: the ask (Q), the answers (O), the requests (R)
---------------------------------------------------------------------------

-- The addon users an ask reaches (the design): for a zone ask, Hop's count for every layer of the zone
-- and the census's users there; for a continent ask, the census's online users on this realm,
-- halved.
local function Crowd(scope, mapID)
	local H = ns.Hop or {}
	local okS, s = pcall(function() return ns.Data.Summary() end)
	local guilds = okS and type(s) == "table" and type(s.guilds) == "table" and s.guilds or {}
	local users = 0
	if scope == "z" then
		local count = 0
		local okL, layers = pcall(ns.Layers.ForMap, mapID)
		for _, layer in ipairs(okL and type(layers) == "table" and layers or {}) do count = count + (tonumber(layer.count) or 0) end
		local crowd = max(1, count) * 4
		for _, e in ipairs(guilds) do
			local g = type(e) == "table" and e.g
			local here = type(g) == "table" and e.fresh and not g.conflict and type(g.zones) == "table" and g.zones["m" .. tostring(mapID)]
			if here and (tonumber(g.online) or 0) > 0 then users = users + here * min(1, (tonumber(g.users) or 0) / g.online) end
		end
		if users > 0 then crowd = max(crowd, min(users, crowd * (H.CENSUS_REACH or 2) + 8)) end
		return crowd
	end
	for _, e in ipairs(guilds) do
		local g = type(e) == "table" and e.g
		if type(g) == "table" and e.fresh and not g.conflict and (g.realm == nil or g.realm == ns.realm) then users = users + (tonumber(g.users) or 0) end
	end
	return max(1, users / 2)
end
-- The answer chance an ask carries: about WANTED answers, 5-100.
function ArenaMatch.Pct(scope, mapID)
	return max(ArenaMatch.PCT_MIN, min(100, floor(ArenaMatch.WANTED * 100 / Crowd(scope, mapID))))
end

local function Games(game)
	local games = game == "e" and "db" or game
	if ns.FarkleTable and not ns.FarkleTable.CanPlayPlayers() then games = games:gsub("b", "") end
	return games
end
local function Kinds(kind) return kind == "e" and "cs" or kind end
local function Both(a, b)
	local out = ""
	for c in a:gmatch(".") do if b:find(c, 1, true) then out = out .. c end end
	return out ~= "" and out or nil
end

-- What this client plays when found (by `asker`): its search's terms, or the "Let others find me"
-- switch's (Duels, Bones, Staked too), Staked only when its check says yes for that player.
local function MyTerms(asker)
	local games, kinds
	local stake
	if search then
		games, kinds = Games(search.opts.game), Kinds(search.opts.kind)
		stake = search.opts.lo * 100
	else
		local m = ns.db and ns.db.arenaMatch or {}
		games = (m.games == nil or m.games.d ~= false) and "d" or ""
		games = games .. ((m.games == nil or m.games.b ~= false) and "b" or "")
		kinds = m.staked == true and "cs" or "c"
	end
	if ns.FarkleTable and not ns.FarkleTable.CanPlayPlayers() then games = games:gsub("b", "") end
	if kinds:find("s", 1, true) then
		local keep = ""
		for g in games:gmatch(".") do if StakedFor(g, stake, asker) then keep = keep .. g end end
		if keep == "" then kinds = kinds:gsub("s", "") end
	end
	return games ~= "" and games or nil, kinds ~= "" and kinds or nil
end

-- What this client remembers of other players' asks and answers stays small: past MEMORY
-- senders, the ones older than their rule's span go (15 min for asks, 10 min for answers and
-- requests, 2 min for our offers).
ArenaMatch.MEMORY = 256
local heardN = 0
local function Forget(now)
	local n = 0
	for key, list in pairs(heardQ) do
		if now - (list[#list] or -huge) >= ArenaMatch.Q_SPAN then heardQ[key] = nil else n = n + 1 end
	end
	heardN = n
	for key, t in pairs(answered) do if now - t >= ArenaMatch.ANSWER_GAP then answered[key] = nil end end
	for key, t in pairs(requested) do if now - t >= ArenaMatch.DECLINE_TIME then requested[key] = nil end end
	for key, o in pairs(offered) do if now - o.t > ArenaMatch.OFFER_TTL then offered[key] = nil end end
	for mid, r in pairs(sentMids) do if now - r.t >= ArenaMatch.RETRY_TARGET then sentMids[mid] = nil end end
end

-- How many senders each of those tables holds (tests, /oly bug).
function ArenaMatch.Memory()
	local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	return { heard = Count(heardQ), answered = Count(answered), offered = Count(offered), requested = Count(requested) }
end

-- A sender's asks heard in the last 15 min: past Q_MAX, dropped.
local function Heard(key, now)
	if not heardQ[key] then
		heardN = heardN + 1
		if heardN > ArenaMatch.MEMORY then Forget(now) end
	end
	local list = Recent(heardQ[key] or {}, ArenaMatch.Q_SPAN, now)
	list[#list + 1] = now
	heardQ[key] = list
	return #list <= ArenaMatch.Q_MAX
end

local function PublicLane(dist)
	if Arena.TestBuild() then return dist == "RAID" or dist == "PARTY" end
	return dist == "CHANNEL"
end

local SUBS = {}

-- Q: someone asks who can play (the channel).
function SUBS.Q(dist, sender, rest)
	if not PublicLane(dist) then return end
	local qid, game, kind, guild, cont, mapID, zuid, lvl, lo, hi, scope, pct = Arena.Fields(rest, 12)
	if not pct or not qid:find("^[0-9a-z]+$") or #qid > 8 or not (game == "d" or game == "b" or game == "e")
		or not (kind == "c" or kind == "s" or kind == "e") or #guild > 48 or (scope ~= "z" and scope ~= "c") then return end
	cont, mapID, zuid, lvl = N(cont, 0, 1), N(mapID, 1, 999999), N(zuid, 0, 2147483647), N(lvl, 1, 100)
	lo, hi, pct = N(lo, 1, 200), N(hi, 1, 200), N(pct, 1, 100)
	if not (cont and mapID and zuid and lvl and lo and hi and pct) or lo > hi then return end
	local now = Now()
	local key = Lower(sender)
	stats.heard = stats.heard + 1
	if not Heard(key, now) then stats.dropped = stats.dropped + 1 return end
	-- The King's account never answers, searching or not.
	if KingAccount() then return end
	if popup or match or (search and (search.paused or search.current)) then return end
	if not ArenaMatch.Findable() then return end
	if Barred(sender) or not MemberOK(sender, guild) then return end
	local myCont = Pos()
	local myMap = MapNow()
	if myCont ~= cont or (scope == "z" and myMap ~= mapID) then return end
	local myLvl = Level()
	if game ~= "b" and (myLvl < lo or myLvl > hi) then return end
	if search and search.opts.game ~= "b" then
		local slo, shi = LevelRange(search.opts.level, myLvl)
		if lvl < slo or lvl > shi then return end
	end
	local myGames, myKinds = MyTerms(sender)
	local games = myGames and Both(myGames, Games(game))
	local kinds = myKinds and Both(myKinds, Kinds(kind))
	if not games or not kinds then return end
	if answered[key] and now - answered[key] < ArenaMatch.ANSWER_GAP then return end
	local gap = ns.Hop and ns.Hop.OFFER_GAP or 10
	if now - lastOffer < gap then return end
	local chance = min(100, pct * (search and 2 or 1))
	if ArenaMatch.random() * 100 >= chance then return end
	answered[key], lastOffer = now, now
	-- A random pause spreads a crowd's answers (a second more outside the asker's zone).
	local delay = 0.2 + ArenaMatch.random() * 2.3 + (myMap ~= mapID and 1 or 0)
	local q = { qid = qid, game = game, kind = kind, mapID = mapID, zuid = zuid, lvl = lvl, cont = cont, scope = scope }
	-- (One key per ask: a later one never replaces an answer still waiting.)
	Arena.After(delay, "match:offer:" .. qid .. "|" .. key, function()
		if popup or match or not ArenaMatch.Findable() then return end
		local c2, wx, wy = Pos()
		if c2 ~= cont then return end
		local here = MapNow()
		local same = 0
		if here == mapID then
			same = 1
			local z = Zuid(here)
			if zuid ~= 0 and z ~= 0 and z == zuid then same = 2 end
		end
		local grp = Grp()
		local body = { "O", qid, search and "s" or "f", Guild(), same, B36(Level()), B36(ClassID()), games, kinds, grp }
		local cell
		if search then
			cell = { Cell(wx), Cell(wy) }
			if not cell[1] or not cell[2] then return end
			body[#body + 1] = B36(cell[1])
			body[#body + 1] = B36(cell[2])
		end
		offered[qid .. "|" .. key] = { t = Now(), q = q, games = games, kinds = kinds, cell = cell }
		stats.offers = stats.offers + 1
		SendTo(sender, table.concat(body, "~"))
	end)
end

-- The resolved game and kind of a request to this offer: the seeker's pick, else the one the other
-- player offers, else a duel and casual (the design). Staked only where the check says yes for that
-- player and the lower end of our range.
local function Resolve(opts, o)
	local game = opts.game ~= "e" and opts.game or (#o.games == 1 and o.games) or "d"
	local kind
	if opts.kind ~= "e" then kind = opts.kind
	elseif o.kinds == "s" then kind = "s"
	else kind = "c" end
	if not o.games:find(game, 1, true) or not o.kinds:find(kind, 1, true) then return nil end
	if kind == "s" and not StakedFor(game, opts.lo * 100, o.name) then return nil end
	return game, kind
end

-- O: an answer to our ask (a whisper).
function SUBS.O(dist, sender, rest)
	if dist ~= "WHISPER" or not search then return end
	local n = select(2, rest:gsub("~", "")) + 1
	if n ~= 9 and n ~= 11 then return end
	local qid, sf, guild, same, lvl, class, games, kinds, grp, cx, cy = Arena.Fields(rest, n)
	local ask
	for _, a in ipairs(search.asks) do if a.qid == qid then ask = a end end
	if not ask or (sf ~= "s" and sf ~= "f") or (sf == "s") ~= (n == 11) then return end
	same, lvl, class, grp = N(same, 0, 2), N(lvl, 1, 100), N(class, 0, 20), N(grp, 0, 2)
	local maxCell = 2 * Places.OFFSET / Places.CELL - 1
	cx, cy = cx and N(cx, 0, maxCell), cy and N(cy, 0, maxCell)
	if not (same and lvl and class and grp) or (sf == "s" and not (cx and cy)) then return end
	if not (games == "d" or games == "b" or games == "db") or not (kinds == "c" or kinds == "s" or kinds == "cs") then return end
	local key = Lower(sender)
	if search.offers[key] or search.count >= (ns.Hop and ns.Hop.MAX_OFFERS or 30) then return end
	if Barred(sender) or not MemberOK(sender, guild) then return end
	local lo, hi = LevelRange(search.opts.level, search.lvl)
	if search.opts.game ~= "b" and (lvl < lo or lvl > hi) then return end
	local trusted = false
	if ns.Hop and ns.Hop.Trusted then
		local ok, yes = pcall(ns.Hop.Trusted, sender)
		trusted = ok and yes == true
	end
	-- The King's search lists only names the addon can vouch for.
	if search.king and not trusted then return end
	search.seq = (search.seq or 0) + 1
	search.offers[key] = { id = search.seq, key = key, name = sender, qid = qid, searcher = sf == "s", same = same, lvl = lvl, class = class,
		games = games, kinds = kinds, grp = grp, cell = sf == "s" and { cx, cy } or nil, t = Now(), trusted = trusted, guild = guild,
		scope = ask.scope }
	search.count = search.count + 1
	Arena.Changed()
	-- A late answer (the window closed, nothing asked since): the next request may take it.
	if search.phase == "open" then Next() end
	RefreshCard()
end

-- The band of an offer (the design): a searcher by its cell's distance from where the seeker stands
-- (where he started when the game gives no position now), a findable player by its zone.
local function Band(o, here)
	if o.cell then
		here = here or { cont = search.cont, wx = search.wx, wy = search.wy }
		local d = Places.Dist(here, CellPoint(search.cont, o.cell[1], o.cell[2])) or huge
		for i, limit in ipairs(ArenaMatch.BANDS) do if d < limit then return i end end
		return #ArenaMatch.BANDS + 1
	end
	return o.same >= 1 and 2 or 4
end

-- The usable offers, best first: band, searchers, the same layer, the smaller level gap; the
-- first ones alike are drawn by weight (outside a group x2, one the addon vouches for x3).
local function Ranked()
	local list = {}
	local now = Now()
	local here = Here()
	if here and here.cont ~= search.cont then here = nil end
	for key, o in pairs(search.offers) do
		local usable = not search.tried[key] and not Barred(o.name) and not (requested[key] and now - requested[key] < ArenaMatch.RETRY_TARGET)
		local game, kind
		if usable then game, kind = Resolve(search.opts, o) end
		if game and (game ~= "b" or GroupPossible(search.grp, o.grp)) then
			list[#list + 1] = { o = o, band = Band(o, here), s = o.searcher and 0 or 1, layer = o.same == 2 and 0 or 1, gap = math.abs(o.lvl - search.lvl),
				game = game, kind = kind }
		end
	end
	table.sort(list, function(a, b)
		if a.band ~= b.band then return a.band < b.band end
		if a.s ~= b.s then return a.s < b.s end
		if a.layer ~= b.layer then return a.layer < b.layer end
		if a.gap ~= b.gap then return a.gap < b.gap end
		return a.o.key < b.o.key
	end)
	return list
end
local function Draw(list)
	local first = list[1]
	if not first then return nil end
	local pool, total = {}, 0
	for _, e in ipairs(list) do
		if e.band == first.band and e.s == first.s and e.layer == first.layer and e.gap == first.gap then
			local w = (e.o.grp == 0 and 2 or 1) * (e.o.trusted and 3 or 1)
			pool[#pool + 1] = { e = e, w = w }
			total = total + w
		end
	end
	local r = ArenaMatch.random() * total
	for _, p in ipairs(pool) do
		r = r - p.w
		if r < 0 then return p.e end
	end
	return pool[#pool].e
end
ArenaMatch.Ranked = function() return search and Ranked() or {} end

local function Tail()
	if not search or search.tail then return end
	search.tail = true
	Note(search.king and L.MATCH_NOBODY_KING or L.MATCH_NOBODY)
	Arena.Changed()
	RefreshCard()
end

Next = function()
	local s = search
	if not s or s.paused or s.current or match or popup or s.phase ~= "open" then return end
	if s.requests >= ArenaMatch.REQUESTS then return Tail() end
	local list = Ranked()
	-- The King picks among his offers himself (nobody is asked for him); with none after the
	-- second ask, he is told so like anyone.
	if s.king then
		if not list[1] and #s.asks >= 2 then Tail() end
		return
	end
	local e = Draw(list)
	if not e then
		if #s.asks >= 2 then Tail() end
		return
	end
	Request(e)
end

Request = function(e)
	local s = search
	local o = e.o
	local cont, wx, wy = Pos()
	if cont ~= s.cont then return StopSearch("position") end
	local mid = Arena.NewId("M")
	if not mid then return end
	local cell = { Cell(wx), Cell(wy) }
	if not cell[1] or not cell[2] then return end
	local lo, hi = 0, 0
	if e.kind == "s" then lo, hi = s.opts.lo, s.opts.hi end
	local grp = Grp()
	local lvl = Level()
	local body = { "R", mid, o.qid, e.game, e.kind, B36(lo), B36(hi), B36(lvl), B36(ClassID()), B36(cell[1]), B36(cell[2]), grp }
	s.tried[o.key] = true
	s.requests = s.requests + 1
	s.current = { mid = mid, name = o.name, key = o.key, t = Now(), offer = o, game = e.game, kind = e.kind, lo = lo, hi = hi, cell = cell,
		lvl = lvl, grp = grp, mapID = MapNow(), cont = cont }
	requested[o.key] = Now()
	for old, r in pairs(sentMids) do if Now() - r.t >= ArenaMatch.RETRY_TARGET then sentMids[old] = nil end end
	sentMids[mid] = { key = o.key, t = Now() }
	stats.requests = stats.requests + 1
	SendTo(o.name, table.concat(body, "~"), { done = Offline(s.current) })
	-- (Masked on the King's screen, the design.)
	Note(Fill(L.MATCH_ASKING, { name = Arena.Mask(ns.DisplayName(o.name)) }))
	Arena.Changed()
	RefreshCard()
end

local function Ask(n)
	local s = search
	local o = s.opts
	local scope = (n == 1 or o.reach ~= "c") and "z" or "c"
	local mapID = MapNow()
	local cont = Pos()
	if not mapID or cont ~= s.cont then return StopSearch("position") end
	-- A continent ask counts its own crowd; the zone asked again, three times the first chance.
	local pct = ArenaMatch.Pct(scope, mapID)
	if n > 1 and scope == "z" and s.asks[1] then pct = min(100, s.asks[1].pct * 3) end
	local lvl = Level()
	local lo, hi = LevelRange(o.level, lvl)
	local qid = B36(ArenaMatch.random(0, 36 ^ 5 - 1))
	local zuid = Zuid(mapID)
	local body = { "Q", qid, o.game, o.kind, Guild(), B36(cont), B36(mapID), B36(zuid), B36(lvl), B36(lo), B36(hi), scope, B36(pct) }
	s.asks[n] = { qid = qid, t = Now(), scope = scope, pct = pct, mapID = mapID, zuid = zuid }
	s.phase = "asking"
	s.lvl = lvl
	stats.asks = stats.asks + 1
	Send(table.concat(body, "~"))
	Log("ask %d (%s, %d%%)", n, scope, pct)
end

-- Normalized search terms.
local function Terms(opts)
	local o = {}
	o.game = (opts.game == "d" or opts.game == "b") and opts.game or (opts.game == "e" and "e" or "d")
	o.kind = (opts.kind == "s" or opts.kind == "e") and opts.kind or "c"
	o.level = o.game == "b" and 0 or ((opts.level == 0 or opts.level == 10) and opts.level or 5)
	o.reach = opts.reach == "c" and "c" or "z"
	o.share = opts.share == true
	local lo = floor((tonumber(opts.lo) or 0) / 100)
	local hi = floor((tonumber(opts.hi) or 0) / 100)
	local cap = CapSilver()
	if cap then hi = min(hi, cap) end
	o.lo, o.hi = max(0, lo), max(0, hi)
	if o.lo > o.hi then o.lo = o.hi end
	return o
end

function ArenaMatch.Start(opts)
	opts = type(opts) == "table" and opts or {}
	local o = Terms(opts)
	local ok, why = ArenaMatch.CanSearch(o)
	if not ok then return false, why end
	if o.kind ~= "c" then
		local sok = false
		local swhy
		for g in Games(o.game):gmatch(".") do
			local yes, w = StakedFor(g, o.lo * 100)
			if yes then sok = true else swhy = swhy or w end
		end
		if sok and o.hi <= 0 then sok, swhy = false, "stake" end
		if not sok then
			if o.kind == "s" then return false, swhy end
			o.kind = "c"
		end
	end
	if o.kind == "c" then o.lo, o.hi = 0, 0 end
	local cont, wx, wy = Pos()
	local now = Now()
	search = { opts = o, started = now, untilT = now + ArenaMatch.SEARCH_TIME, asks = {}, offers = {}, count = 0, tried = {}, requests = 0,
		cont = cont, wx = wx, wy = wy, lvl = Level(), grp = Grp(), king = KingAccount() or nil }
	if not ns.Layers.Sharing() and o.share then
		search.shared = { was = ns.db.shareLocation }
		ns.Layers.SetSharing(true)
	end
	searches[#searches + 1] = now
	DB().seen = true
	sheet, ended, showOther = nil, nil, false
	Ask(1)
	if not search then return false, "position" end
	-- (No chat line: the card, shown now, says it.)
	Involvement()
	ShowCard()
	Arena.Changed()
	return true
end

-- The search ends (and the request still out is withdrawn); sharing turned on for it goes back.
-- The player is told when he did not end it himself (its 10 minutes, an instance, no position,
-- the crown): the card goes with the search.
local TOLD_END = { time = true, instance = true, position = true, crown = true }
StopSearch = function(why)
	local s = search
	if not s then return end
	search = nil
	if s.current and why ~= "matched" then SendTo(s.current.name, "C~" .. s.current.mid .. "~c") end
	if s.shared then
		ns.Layers.SetSharing(false)
		if ns.db then ns.db.shareLocation = s.shared.was end
	end
	if TOLD_END[why] then ns.Print(why == "instance" and L.MATCH_SEARCH_ENDED_INSTANCE or L.MATCH_SEARCH_ENDED) end
	Log("search over: %s", tostring(why))
	Involvement()
	Arena.Changed()
	RefreshCard()
end
function ArenaMatch.Stop() StopSearch("stopped") end

-- The King picks one of the offers he was shown (View().offers).
function ArenaMatch.Pick(id)
	local s = search
	if not s or not s.king or s.current or match or popup then return false end
	for _, e in ipairs(Ranked()) do
		if e.o.id == id then
			if s.requests >= ArenaMatch.REQUESTS then return false end
			Request(e)
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The request on this side: the place, the popup, the answer (the design)
---------------------------------------------------------------------------

-- The partner's choice (the design): "=" when a casual game allows it and we stand close, else the
-- fairest place for the two cells as they go on the wire.
local function Choose(r, q, me)
	local sc = CellPoint(me.cont, r.cell[1], r.cell[2])
	local nearOK = Casual(r.game, r.kind) and (r.game == "d" or q.mapID == me.mapID)
	if nearOK and not Places.Capital(q.mapID) and not (me.mapID and Places.Capital(me.mapID)) and GroupPossible(r.grp, me.grp) then
		local d = Places.Dist({ cont = me.cont, wx = me.wx, wy = me.wy }, sc)
		if d and d < ArenaMatch.NEAR then return "=" end
	end
	local list = FairList(r.game, r.kind, me.cont, r.cell, me.cell, min(r.lvl, me.lvl))
	return list[1] and list[1].id or nil
end

local function Say255(text) return ns.Cut(text, 255) end
local function RangeText(lo, hi)
	local T = ns.Treasury
	local function C(s) return T and T.Coins and T.Coins(s * 100) or (tostring(s) .. "s") end
	if lo == hi then return C(lo) end
	return C(lo) .. "-" .. C(hi)
end
local function WhatText(game, kind, lo, hi)
	if game == "d" then return kind == "s" and Fill(L.MATCH_WHAT_DUEL_STAKED, { range = RangeText(lo, hi) }) or L.MATCH_WHAT_DUEL end
	return kind == "s" and Fill(L.MATCH_WHAT_BONE_STAKED, { range = RangeText(lo, hi) }) or L.MATCH_WHAT_BONE
end

-- The popup's text (the design).
local function PopupText(p)
	local me = { cont = p.me.cont, wx = p.me.wx, wy = p.me.wy }
	local sc = CellPoint(p.me.cont, p.cell[1], p.cell[2])
	local t = { name = ns.DisplayName(p.name), level = p.lvl, class = ClassName(p.class), what = WhatText(p.game, p.kind, p.lo, p.hi),
		far = About(Places.Dist(me, sc) or 0) }
	if p.place == "=" then return Fill(L.MATCH_POPUP_NEAR, t) end
	local row = Places.byId[p.place]
	local w = PlaceWords(p.place)
	t.place, t.zone, t.x, t.y = w.place, w.zone, w.x, w.y
	t.mine = About(Places.Dist(me, row) or 0)
	t.theirs = About(Places.Dist(sc, row) or 0)
	return Fill(L.MATCH_POPUP, t)
end
ArenaMatch.PopupText = PopupText

local function No(name, mid) SendTo(name, "A~" .. mid .. "~N", { urgent = true }) end

-- R: a request to meet (a whisper), answering one of our offers.
function SUBS.R(dist, sender, rest)
	if dist ~= "WHISPER" then return end
	if KingAccount() then return end
	local mid, qid, game, kind, lo, hi, lvl, class, cx, cy, grp = Arena.Fields(rest, 11)
	if not grp or not mid:find("^M[0-9a-z]+$") or #mid > 16 then return end
	local maxCell = 2 * Places.OFFSET / Places.CELL - 1
	lo, hi, lvl, class = N(lo, 0, 21474836), N(hi, 0, 21474836), N(lvl, 1, 100), N(class, 0, 20)
	cx, cy, grp = N(cx, 0, maxCell), N(cy, 0, maxCell), N(grp, 0, 2)
	if not (GAMES[game] and KINDS[kind] and lo and hi and lvl and class and cx and cy and grp) then return end
	local key = Lower(sender)
	local o = offered[qid .. "|" .. key]
	if not o or Now() - o.t > ArenaMatch.OFFER_TTL then return end
	offered[qid .. "|" .. key] = nil
	-- Two requests crossing: the name that sorts first keeps its own; the other sees the popup.
	if search and search.current and search.current.key == key then
		if Lower(ns.me) < key then return No(sender, mid) end
		sentMids[search.current.mid] = nil
		search.requests = max(0, search.requests - 1)
		search.current = nil
	end
	if popup or match or (search and search.current) then return No(sender, mid) end
	if Barred(sender) or not ArenaMatch.Findable() then return No(sender, mid) end
	if not o.games:find(game, 1, true) or not o.kinds:find(kind, 1, true) then return No(sender, mid) end
	-- The stake range: none for a casual game; for a staked one, the part of it within our own bet
	-- cap (Standing.Cap, as the seeker's own range is) and, when we search, our range too; then
	-- the stake check for this player and its lower end.
	if kind == "c" then
		if lo ~= 0 or hi ~= 0 then return No(sender, mid) end
	else
		if lo < 1 or lo > hi then return No(sender, mid) end
		local cap = CapSilver()
		if cap then hi = min(hi, cap) end
		if search and search.opts.kind ~= "c" then
			lo, hi = max(lo, search.opts.lo), min(hi, search.opts.hi)
		end
		if lo > hi or not StakedFor(game, lo * 100, sender) then return No(sender, mid) end
	end
	local myGrp = Grp()
	if game == "b" and not GroupPossible(grp, myGrp) then return No(sender, mid) end
	local cont, wx, wy = Pos()
	if cont ~= o.q.cont then return No(sender, mid) end
	local myLvl = Level()
	local myCell = o.cell or { Cell(wx), Cell(wy) }
	local me = { cont = cont, wx = wx, wy = wy, cell = myCell, mapID = MapNow(), lvl = myLvl, grp = myGrp }
	local r = { game = game, kind = kind, cell = { cx, cy }, lvl = lvl, grp = grp }
	local place = Choose(r, o.q, me)
	if not place then return No(sender, mid) end
	local p = { mid = mid, name = sender, key = key, qid = qid, game = game, kind = kind, lo = lo, hi = hi, lvl = lvl, class = class, cell = { cx, cy },
		grp = grp, place = place, me = me, seekerMap = o.q.mapID, seekerZuid = o.q.zuid, t = Now() }
	popup = p
	if search then search.paused = true end
	stats.popups = stats.popups + 1
	Involvement()
	local text = PopupText(p)
	ns.Alert("arena", "soft", { what = Fill(L.MATCH_HELD, { name = ns.DisplayName(sender) }), key = "match:" .. mid,
		open = function() return popup == p and Now() - p.t <= ArenaMatch.POPUP_TIME end,
		show = function()
			if popup ~= p then return end
			ns.ShowDialog("OLYMPUS_ARENA_MATCH", text, nil, p)
			-- (A searcher's card goes under the popup at once, not over it.)
			RefreshCard()
		end })
	Arena.Changed()
end

-- Two Not now or unanswered popups in a row: nobody finds this player for 30 min.
local function Noes()
	local m = DB()
	m.noes = (m.noes or 0) + 1
	if m.noes >= ArenaMatch.NOES then
		m.noes = 0
		m.pausedUntil = Now() + ArenaMatch.PAUSE_TIME
		ns.Print(L.MATCH_PAUSED)
	end
end
local function Declined(name) DB().declined[Lower(name)] = Now() end

-- A block (one click): ns.db.blocked under /oly block's key, then the game's ignore list.
local function Block(name) -- gp:arena-clicks
	local key = Lower(name)
	if not key or not ns.db then return end
	ns.db.blocked = type(ns.db.blocked) == "table" and ns.db.blocked or {}
	ns.db.blocked[key] = true
	local F = C_FriendList
	if F and F.AddIgnore then
		local ok, added = pcall(F.AddIgnore, ns.TellName(name))
		if ok and added == false then ns.Print(L.MATCH_IGNORE_FULL) end
	end
	ns.Print(Fill(L.MATCH_END_BLOCKED, { name = Arena.Mask(ns.DisplayName(name)) }))
end
ArenaMatch.Block = Block

local function Resume()
	if search then
		search.paused = nil
		Next()
	end
	Involvement()
	Arena.Changed()
end

-- The opening whisper (the design).
local function OpeningText(mm)
	if mm.place == "=" then
		return Fill(L.MATCH_SAY_CLOSE, { game = mm.game == "d" and L.MATCH_SAY_GAME_DUEL or L.MATCH_SAY_GAME_BONE })
	end
	local key
	if mm.game == "d" then key = mm.kind == "s" and "MATCH_SAY_DUEL_STAKED" or "MATCH_SAY_DUEL_CASUAL"
	else key = mm.kind == "s" and "MATCH_SAY_BONE_GOLD" or "MATCH_SAY_BONE_PRACTICE" end
	return Say255(Fill(L[key], PlaceWords(mm.place, mm)))
end
ArenaMatch.OpeningText = OpeningText

-- Whether Let's go can go through now: not while chat is locked down or in an instance (the
-- answer would wait in the hold and the whisper cannot go), off the network or with the arena
-- off, with location sharing turned off since the popup came (a searcher shares while he
-- searches), or with no position. Combat is no reason: whispers and invites work there, and the
-- match's clocks wait for it.
local function CanGo()
	if Arena.Blocked() then return false, "blocked" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.SelfOff and M.SelfOff() then return false, "netoff" end
	if Arena.Off() then return false, "arena" end
	if not search and not ns.Layers.Sharing() then return false, "location" end
	if not Pos() then return false, "position" end
	return true
end

-- Let's go (inside the click): the answer, the opening whisper, and the invite when it is ours.
local function LetsGo(p)
	local grp = Grp()
	local zuid = Zuid(p.me.mapID)
	DB().noes = 0
	if search then StopSearch("matched") end
	local mm = NewMatch({ role = "partner", mid = p.mid, name = p.name, game = p.game, kind = p.kind, lo = p.lo, hi = p.hi, place = p.place,
		mine = true, theirs = false, cont = p.me.cont, myCell = p.me.cell, theirCell = p.cell, myMap = p.me.mapID, theirMap = p.seekerMap,
		theirZuid = p.seekerZuid, myGrp = grp, theirGrp = p.grp, level = min(p.lvl, p.me.lvl), theirLvl = p.lvl, theirClass = p.class })
	SendTo(p.name, table.concat({ "A", p.mid, "Y", p.place, B36(p.me.cell[1]), B36(p.me.cell[2]), B36(p.me.mapID or 0), B36(zuid),
		B36(p.lo), B36(p.hi), grp }, "~"), { urgent = true, done = Offline(mm) })
	Say(p.name, OpeningText(mm))
	if Inviter(p.grp, grp) == "partner" then Invite(p.name) end
end

local function Answer(p, how)
	if not p or popup ~= p then return end
	popup = nil
	-- (Our own clock ran out before the dialog's: it goes too.)
	if how == "expired" then ns.HideDialog("OLYMPUS_ARENA_MATCH", p) end
	if how == "yes" then
		local ok, why = CanGo()
		if ok then
			LetsGo(p)
			Involvement()
			Arena.Changed()
			return
		end
		-- The player said yes and it cannot go through: a plain no to the seeker, with the reason
		-- here, and neither a decline of the seeker nor a strike towards the 30-min pause.
		No(p.name, p.mid)
		ns.Print(ArenaMatch.WhyText(why))
		Resume()
		return
	end
	No(p.name, p.mid)
	if how == "block" then Block(p.name) else Declined(p.name) Noes() end
	Resume()
end
ArenaMatch.Answer = Answer

StaticPopupDialogs["OLYMPUS_ARENA_MATCH"] = {
	text = "%s",
	button1 = L.MATCH_LETS_GO,
	button2 = L.MATCH_NOT_NOW,
	button3 = L.MATCH_BLOCK,
	OnAccept = function(self, data) ns.SafeCall("arena match yes", Answer, data or (self and self.data), "yes") end,
	-- Not now, Escape, another popup's place or the 30 s: a no.
	OnCancel = function(self, data, reason)
		ns.SafeCall("arena match no", Answer, data or (self and self.data), reason == "clicked" and "no" or "timeout")
	end,
	OnAlt = function(self, data) ns.SafeCall("arena match block", Answer, data or (self and self.data), "block") end,
	timeout = ArenaMatch.POPUP_TIME,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	-- Olympus's own dialog (the gamepad UI, Dialog.lua): buttons 24 px tall (the design) and the text at
	-- 14 px (the owner's 13 px or more). The game's popup ignores both.
	buttonHeight = 24,
	textFont = "GameFontHighlightMed2",
}

---------------------------------------------------------------------------
-- The match (the design)
---------------------------------------------------------------------------

local function PlaceRow(mm) return Places.byId[mm.place] end
local function SetPoint(mm)
	local row = PlaceRow(mm)
	if row then mm.point = { cont = row.cont, wx = row.wx, wy = row.wy }
	elseif mm.place == "=" then mm.point = nil
	else mm.point = PointOf(mm.place, mm.cont) end
end

-- The longer of the two walks to the place, from the two cells.
local function LongerWalk(mm)
	if not mm.point then return 0 end
	local a = Places.Dist(CellPoint(mm.cont, mm.myCell[1], mm.myCell[2]), mm.point) or 0
	local b = Places.Dist(CellPoint(mm.cont, mm.theirCell[1], mm.theirCell[2]), mm.point) or 0
	return max(a, b)
end
function ArenaMatch.TravelTime(walk)
	return min(ArenaMatch.TRAVEL_MAX, ArenaMatch.TRAVEL_BASE + (tonumber(walk) or 0) / ArenaMatch.TRAVEL_SPEED * ArenaMatch.TRAVEL_SLACK)
end

-- The pins: a minimap pin (and a world-map one only where ns.WorldMapIcons allows it: never with
-- the gamepad UI), gone when the match ends.
local pinFrames
local function PinFrames()
	if pinFrames then return pinFrames end
	local function Pin(size)
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(size, size)
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetTexture("Interface\\Icons\\Ability_DualWield")
		f.icon = t
		return f
	end
	pinFrames = { mini = Pin(14), world = Pin(18) }
	return pinFrames
end
local function Pins(mm)
	local P = ns.Pins and ns.Pins()
	if not P then return end
	if P.RemoveAllMinimapIcons then P:RemoveAllMinimapIcons(ArenaMatch) end
	if P.RemoveAllWorldMapIcons then P:RemoveAllWorldMapIcons(ArenaMatch) end
	if not mm or not mm.point then return end
	local f = PinFrames()
	local row = PlaceRow(mm)
	local world = ns.WorldMapIcons(P, ArenaMatch)
	if row then
		P:AddMinimapIconMap(ArenaMatch, f.mini, row.mapID, row.x, row.y, true, true)
		if world and P.AddWorldMapIconMap then P:AddWorldMapIconMap(ArenaMatch, f.world, row.mapID, row.x, row.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1) end
	elseif P.AddMinimapIconWorld then
		-- (HereBeDragons takes UnitPosition's two values swapped: Places.HBDWorld.)
		local inst, x, y = Places.HBDWorld(mm.point.cont, mm.point.wx, mm.point.wy)
		if inst then
			P:AddMinimapIconWorld(ArenaMatch, f.mini, inst, x, y, true)
			if world and P.AddWorldMapIconWorld then P:AddWorldMapIconWorld(ArenaMatch, f.world, inst, x, y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1) end
		end
	end
end

---------------------------------------------------------------------------
-- The private room which follows one accepted match
---------------------------------------------------------------------------

-- This is presentation metadata for the one matchmaking state above, not another match state.
-- It is never saved and carries no position. Keeping a few ended identities in memory lets a
-- player close and reopen the Olympus chat tab without losing that room's bounded history.
local function RoomSides(rec)
	local me, them = ns.FullName(ns.me), ns.FullName(rec.name)
	if rec.role == "seeker" then return me, them end
	return them, me
end

local function RoomRecord(mid)
	if match and match.mid == mid then return match, true end
	return roomEnded[mid], false
end

local function KeepRoom(mm, why)
	if type(mm) ~= "table" or type(mm.mid) ~= "string" then return end
	local now = Now()
	roomEnded[mm.mid] = {
		mid = mm.mid, name = mm.name, role = mm.role, game = mm.game, kind = mm.kind,
		why = why, endedAt = now,
	}
	local list = {}
	for id, rec in pairs(roomEnded) do list[#list + 1] = { id = id, at = tonumber(rec.endedAt) or 0 } end
	table.sort(list, function(a, b) return a.at > b.at end)
	for i = ArenaMatch.ROOM_HISTORY_MAX + 1, #list do
		local id, old = list[i].id, roomEnded[list[i].id]
		-- Tell an open Chat host that the bounded archive evicted this identity before forgetting
		-- its participant names. This never opens a room and sends no network message.
		if old then
			old.endedAt = now - ArenaMatch.ROOM_KEEP_AFTER
			if ArenaMatch.ChatRoomChanged then ArenaMatch.ChatRoomChanged(id) end
		end
		roomEnded[id] = nil
	end
end

local function RoomTitle(rec)
	local a, b = RoomSides(rec)
	local key = rec.game == "b" and "MATCH_ROOM_BONE_TITLE" or "MATCH_ROOM_DUEL_TITLE"
	return Fill(rawget(L, key) or "{a} vs {b}", {
		a = ns.ShortName(a), b = ns.ShortName(b),
	})
end

-- ArenaChat consumes this event exactly as it consumes a private 1v1 fight: only both matched
-- players are participants, and its EC messages therefore use logged whispers rather than the
-- public Olympus lane. The room adds no authority and opening it sends no network word.
function ArenaMatch.RoomEvent(mid)
	local rec, active = RoomRecord(mid)
	if not rec then return nil end
	local a, b = RoomSides(rec)
	return {
		kind = "match", opener = a, fighters = { A = { name = a }, B = { name = b } },
		public = false, mode = Mode(), state = active and "L" or "F",
		live = active, over = not active,
	}
end

function ArenaMatch.ChatRoom(mid)
	local rec, active = RoomRecord(mid)
	if not rec then return nil end
	local endedAt = not active and tonumber(rec.endedAt) or nil
	local retainUntil = endedAt and (endedAt + ArenaMatch.ROOM_KEEP_AFTER) or nil
	local recoverable = active or (retainUntil ~= nil and Now() < retainUntil)
	local a, b = RoomSides(rec)
	return {
		key = "arena:" .. mid, id = mid, kind = "match", eventKind = "match",
		audience = "duel", access = "participants", title = RoomTitle(rec),
		state = active and "L" or "F", phase = active and "meeting" or "complete",
		active = active, completedAt = endedAt, retainFor = ArenaMatch.ROOM_KEEP_AFTER,
		retainUntil = retainUntil, recoverable = recoverable,
		opener = a, fighters = { A = { name = a }, B = { name = b } },
		participants = { a, b }, supportsBets = false, supportsComments = true,
	}
end

function ArenaMatch.ChatRoomChanged(mid)
	local spec = ArenaMatch.ChatRoom(mid)
	if not spec then return false end
	ns.Fire("ARENA_CHAT_ROOM", spec)
	return spec
end

if Arena.Events and Arena.Events.Register then
	Arena.Events.Register("M", ArenaMatch.RoomEvent)
end

local lastRoomState
ns.On("ARENA_CHANGED", function()
	local mm = match
	if not mm then return end
	local state = table.concat({ mm.mid, mm.place or "", mm.rev or 0, mm.mine and 1 or 0,
		mm.theirs and 1 or 0, mm.fixed and 1 or 0, mm.here and 1 or 0, mm.them and 1 or 0,
		mm.handed and 1 or 0, mm.still and 1 or 0 }, ":")
	if state == lastRoomState then return end
	lastRoomState = state
	ArenaMatch.ChatRoomChanged(mm.mid)
end)

NewMatch = function(t)
	local now = Now()
	t.started, t.agreeBy, t.rev = now, now + ArenaMatch.PLACE_TIME, 0
	t.formed = t.myGrp == 0 and t.theirGrp == 0
	t.pOut, t.pIn = 0, 0
	SetPoint(t)
	match = t
	ended, sheet, showOther = nil, nil, false
	stats.matches = stats.matches + 1
	Pins(t)
	Involvement()
	ShowCard()
	ns.PlayAlert("soft", "arena", true)
	ArenaMatch.ChatRoomChanged(t.mid)
	Arena.Changed()
	-- On a real client the Chat host is loaded before a player can accept. Test worlds and older
	-- builds may not have it; the card remains the visible, resumable fallback in that case.
	if rawget(ns, "ChatWindow") then ArenaMatch.OpenRoom(t.mid, true) end
	return t
end

-- Both agreed on one place: the travel clock starts.
local function Fix(mm)
	if mm.fixed or not (mm.mine and mm.theirs) then return end
	mm.fixed = true
	mm.travelBy = Now() + ArenaMatch.TravelTime(LongerWalk(mm))
	mm.still = nil
	Arena.Changed()
	RefreshCard()
end

local function SetPlace(mm, place, rev)
	mm.place, mm.rev = place, rev
	mm.fixed, mm.travelBy, mm.still = false, nil, nil
	mm.agreeBy = Now() + ArenaMatch.PLACE_TIME
	SetPoint(mm)
	Pins(mm)
end

-- A contradicts the offer (the design), on the seeker's side, each test on its own: a searcher whose cell
-- moved faster than 15 yd/s since its O; a zone answer (to a zone ask, or one that said it was in
-- the asker's zone), a searcher's too, whose A names another zone.
local function Lie(cur, a, now)
	local o = cur.offer
	if o.cell then
		local moved = CellGap(o.cell, a.cell)
		if moved > ArenaMatch.LIE_SPEED * max(1, now - o.t) then return true end
	end
	if o.same >= 1 or o.scope == "z" then
		local ask
		for _, x in ipairs(search.asks) do if x.qid == o.qid then ask = x end end
		if ask and a.mapID ~= ask.mapID then return true end
	end
	return false
end

-- A: the answer to our request (a whisper).
function SUBS.A(dist, sender, rest)
	if dist ~= "WHISPER" then return end
	local mid, yes = Arena.Fields(rest, 2)
	if not yes then return end
	if yes ~= "N" then mid, yes = Arena.Fields(rest, 10) end
	local cur = search and search.current
	local key = Lower(sender)
	if not cur or cur.mid ~= mid or cur.key ~= key then
		-- A yes to a request we gave up on: its match ends there at once (one C~t, however often
		-- that yes comes again).
		local sm = type(mid) == "string" and sentMids[mid]
		if sm and sm.key == key and rest:find("^[^~]+~Y~") then
			sentMids[mid] = nil
			SendTo(sender, "C~" .. mid .. "~t")
		end
		return
	end
	-- (Answered: this request is no longer one given up on, whatever comes of the answer.)
	sentMids[mid] = nil
	if yes == "N" then
		Declined(sender)
		search.current = nil
		Next()
		Arena.Changed()
		RefreshCard()
		return
	end
	local _, _, place, cx, cy, mapID, zuid, lo, hi, grp = Arena.Fields(rest, 10)
	local maxCell = 2 * Places.OFFSET / Places.CELL - 1
	cx, cy, mapID, zuid = N(cx, 0, maxCell), N(cy, 0, maxCell), N(mapID, 0, 999999), N(zuid, 0, 2147483647)
	lo, hi, grp = N(lo, 0, 21474836), N(hi, 0, 21474836), N(grp, 0, 2)
	if yes ~= "Y" or not (cx and cy and mapID and zuid and lo and hi and grp) or type(place) ~= "string" then return end
	local now = Now()
	local a = { place = place, cell = { cx, cy }, mapID = mapID, zuid = zuid, lo = lo, hi = hi, grp = grp }
	local function Refuse(why, lie)
		SendTo(sender, "C~" .. mid .. "~c")
		search.current = nil
		if lie then
			DB().lied[key] = now
			search.requests = max(0, search.requests - 1)
			stats.lies = stats.lies + 1
		end
		Log("answer from %s refused: %s", tostring(sender), why)
		Next()
		Arena.Changed()
		RefreshCard()
	end
	if Lie(cur, a, now) then return Refuse("lie", true) end
	-- The range both agreed: inside ours, casual none.
	if cur.kind == "c" then
		if lo ~= 0 or hi ~= 0 then return Refuse("range") end
	elseif lo < cur.lo or hi > cur.hi or lo > hi or lo < 1 then
		return Refuse("range")
	end
	local level = min(cur.lvl, cur.offer.lvl)
	if place == "=" then
		if not CloseByOK(cur.game, cur.kind, cur.cont, cur.cell, a.cell, cur.mapID, mapID) then return Refuse("place") end
	else
		local list = FairList(cur.game, cur.kind, cur.cont, cur.cell, a.cell, level)
		local found = false
		for _, e in ipairs(list) do if e.id == place then found = true end end
		if not found then return Refuse("place") end
		if list[1].id ~= place then Log("answer from %s: %s, not the top pick %s", tostring(sender), place, list[1].id) end
	end
	local o = cur.offer
	StopSearch("matched")
	NewMatch({ role = "seeker", mid = mid, name = cur.name, game = cur.game, kind = cur.kind, lo = lo, hi = hi, place = place, mine = false,
		theirs = true, cont = cur.cont, myCell = cur.cell, theirCell = a.cell, myMap = cur.mapID, theirMap = mapID, theirZuid = zuid,
		myGrp = cur.grp, theirGrp = grp, level = level, theirLvl = o.lvl, theirClass = o.class })
end

local function Partner(sender, mid)
	return match and match.mid == mid and SameName(sender, match.name) and match or nil
end

-- A proposal (P~P) or a yes to the place (P~A), each the player's click.
local function SendP(mm, how)
	local now = Now()
	if mm.pOut >= ArenaMatch.P_MAX or now - (mm.pAt or -huge) < ArenaMatch.P_GAP then return false end
	mm.pOut, mm.pAt = mm.pOut + 1, now
	SendTo(mm.name, table.concat({ "P", mm.mid, B36(mm.rev), mm.place, how }, "~"), { done = Offline(mm) })
	return true
end

-- On my way, or Agree (the click): our yes to the place, and its whisper.
function ArenaMatch.Agree()
	local mm = match
	if not mm or mm.mine or Arena.Blocked() then return false end
	if not SendP(mm, "A") then return false end
	mm.mine = true
	Say(mm.name, Fill(L.MATCH_SAY_ONWAY, PlaceWords(mm.place, mm)))
	Fix(mm)
	RefreshCard()
	return true
end

-- Another spot (the click): the proposal counts as our yes and clears theirs.
function ArenaMatch.Propose(place)
	local mm = match
	if not mm or Arena.Blocked() or place == mm.place then return false end
	local text
	if place == "@" then
		local cont, wx, wy = Pos()
		if cont ~= mm.cont then return false end
		local a, b = Places.Cell(wx, Places.POINT), Places.Cell(wy, Places.POINT)
		if not a or not b then return false end
		place = "@" .. B36(a) .. "." .. B36(b)
		local mapID, x, y = MapPos()
		mm.nextPoint = { by = "me", zone = ZoneName(mapID), x = Coord(x), y = Coord(y) }
		text = Fill(L.MATCH_SAY_WHERE, { zone = mm.nextPoint.zone, x = mm.nextPoint.x, y = mm.nextPoint.y })
	elseif place == "=" then
		if not PlaceOK(mm, "=") then return false end
		text = L.MATCH_SAY_CLOSEBY
	else
		if not PlaceOK(mm, place) then return false end
		text = Fill(L.MATCH_SAY_OTHER, PlaceWords(place))
	end
	local rev = mm.rev + 1
	local was = { place = mm.place, rev = mm.rev }
	mm.place, mm.rev = place, rev
	if not SendP(mm, "P") then mm.place, mm.rev = was.place, was.rev return false end
	SetPlace(mm, place, rev)
	if mm.nextPoint then
		mm.pointBy, mm.pointZone, mm.pointX, mm.pointY = mm.nextPoint.by, mm.nextPoint.zone, mm.nextPoint.x, mm.nextPoint.y
		mm.nextPoint = nil
	end
	mm.mine, mm.theirs = true, false
	showOther = false
	Say(mm.name, text)
	Arena.Changed()
	RefreshCard()
	return true
end

function SUBS.P(dist, sender, rest)
	if dist ~= "WHISPER" then return end
	local mid, rev, place, how = Arena.Fields(rest, 4)
	local mm = Partner(sender, mid)
	if not mm then return end
	rev = N(rev, 0, 1000)
	if not rev or (how ~= "P" and how ~= "A") then return end
	mm.pIn = mm.pIn + 1
	if mm.pIn > 2 * ArenaMatch.P_MAX then return end
	if place ~= mm.place and not PlaceOK(mm, place) then return end
	if how == "A" then
		if rev == mm.rev and place == mm.place then
			mm.theirs = true
			Fix(mm)
		end
	elseif rev > mm.rev or (rev == mm.rev and place ~= mm.place and Lower(sender) < Lower(ns.me)) then
		-- Theirs wins (newer, or crossed with ours and their name sorts first): our yes is cleared.
		SetPlace(mm, place, rev)
		if ParsePoint(place) then mm.pointBy, mm.pointZone, mm.pointX, mm.pointY = "them", nil, nil, nil end
		mm.theirs, mm.mine = true, false
	elseif rev == mm.rev and place == mm.place then
		mm.theirs = true
		Fix(mm)
	end
	Arena.Changed()
	RefreshCard()
end

-- The partner's group token, once grouped. Never inside an instance, where a unit's name may be a
-- secret value (UnitFullName is SecretWhenUnitIdentityRestricted); a secret or unreadable name is
-- no match.
local function PartnerUnit(name)
	if Arena.InInstance() or not (IsInGroup and IsInGroup()) then return nil end
	local raid = IsInRaid and IsInRaid()
	local n = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
	for i = 1, n do
		local unit = (raid and "raid" or "party") .. i
		local ok, who = pcall(ns.UnitFullName, unit)
		if ok and not Secret(who) and type(who) == "string" and SameName(who, name) then return unit end
	end
	return nil
end
local function UnitPoint(unit)
	if type(UnitPosition) ~= "function" then return nil end
	local ok, y, x, _, inst = pcall(UnitPosition, unit)
	if not ok or Secret(y) or Secret(x) or Secret(inst) or type(y) ~= "number" or type(x) ~= "number" then return nil end
	return { cont = inst, wx = y, wy = x }
end
local function InDuelRange(unit)
	if not CheckInteractDistance then return false end
	local ok, yes = pcall(CheckInteractDistance, unit, 3)
	return ok and not Secret(yes) and yes == true
end

-- Arrived (the design): within 40 yd of a spot or a point, 60 of an arena, inside the inn's rest area and
-- resting, within 40 yd of the partner for "=".
local function Arrived(mm)
	local here = Here()
	if not here then return false end
	if mm.place == "=" then
		local unit = PartnerUnit(mm.name)
		local them = unit and UnitPoint(unit)
		local d = them and Places.Dist(here, them)
		return d ~= nil and d <= ArenaMatch.ARRIVE
	end
	if not mm.point then return false end
	local row = PlaceRow(mm)
	if row and row.kind == "inn" then
		local inn = Places.InnAt(here.cont, here.wx, here.wy)
		return inn ~= nil and inn.id == row.id and IsResting ~= nil and IsResting() == true
	end
	local d = Places.Dist(here, mm.point)
	return d ~= nil and d <= ((row and row.kind == "arena") and ArenaMatch.ARRIVE_ARENA or ArenaMatch.ARRIVE)
end
ArenaMatch.Arrived = function() return match and Arrived(match) or false end

local function SendHere(mm, now)
	if mm.hWant == nil then return end
	if now - (mm.hAt or -huge) < ArenaMatch.H_GAP then return end
	local v = mm.hWant
	mm.hWant, mm.hSent, mm.hAt = nil, v, now
	SendTo(mm.name, table.concat({ "H", mm.mid, v and "1" or "0", B36(Zuid(MapNow())) }, "~"), { done = Offline(mm) })
end

function SUBS.H(dist, sender, rest)
	if dist ~= "WHISPER" then return end
	local mid, v, zuid = Arena.Fields(rest, 3)
	local mm = Partner(sender, mid)
	zuid = N(zuid, 0, 2147483647)
	if not mm or (v ~= "1" and v ~= "0") or not zuid then return end
	local now = Now()
	if now - (mm.hIn or -huge) < ArenaMatch.H_GAP - 1 then return end
	mm.hIn = now
	mm.them = v == "1"
	mm.theirZuid = zuid
	if mm.them and mm.here and not mm.bothAt then
		mm.bothAt = now
		ns.PlayAlert("soft", "arena", true)
	end
	Arena.Changed()
	RefreshCard()
end

function SUBS.C(dist, sender, rest)
	if dist ~= "WHISPER" then return end
	local mid, code = Arena.Fields(rest, 2)
	if not END_CODES[code] then return end
	if popup and popup.mid == mid and SameName(sender, popup.name) then
		local p = popup
		popup = nil
		ns.HideDialog("OLYMPUS_ARENA_MATCH", p)
		Resume()
		return
	end
	if Partner(sender, mid) then End(code == "c" and "cancel" or END_CODES[code], nil, sender) end
end

-- The group the match's invite formed (two of us, nobody else) is left from code at the end,
-- unless a fight or a table from the match still runs (then at ArenaMatch.Ended). Never inside an
-- instance: the two may be in a dungeon in that group, and leaving it there would take the player
-- out of it; the ended card's [Leave group] is his to click.
local function LeaveFormed(rec)
	if not rec or not rec.formed or Arena.InInstance() then return false end
	if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return false end
	if (GetNumGroupMembers and GetNumGroupMembers() or 0) ~= 2 or not PartnerUnit(rec.name) then return false end
	LeaveGroup()
	return true
end

-- The match ends: why ("cancel", "time", "instance", "done", "place", "lie", "crown", "offline",
-- "blocked", "you"), send: the C code to the partner (nil: none).
End = function(why, send, by)
	local mm = match
	if not mm then return end
	match = nil
	KeepRoom(mm, why)
	ArenaMatch.ChatRoomChanged(mm.mid)
	if send then SendTo(mm.name, "C~" .. mm.mid .. "~" .. send) end
	-- (A fight or a table it handed off to may still run: its end leaves the group the match formed,
	-- ArenaMatch.Ended, so that record stays for it; Vet no longer holds the agreed stake. With no
	-- such group there is nothing left to keep.)
	if mm.handed then
		local h = handed[mm.mid]
		if h and h.formed then h.matchOver = true else handed[mm.mid] = nil end
	else
		handed[mm.mid] = nil
		LeaveFormed(mm)
	end
	Pins(nil)
	-- (Our own waypoint alone, and only where the gate allows: with the gamepad UI it stays.)
	if mm.waypoint and ns.Gate.Allowed("map-waypoint") and C_Map and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint then -- gp:map-waypoint
		local ok, w = pcall(C_Map.GetUserWaypoint)
		local p = ok and type(w) == "table" and w.position
		if p and w.uiMapID == mm.waypoint[1] and math.abs((p.x or 0) - mm.waypoint[2]) < 1e-4 and math.abs((p.y or 0) - mm.waypoint[3]) < 1e-4 then
			C_Map.ClearUserWaypoint() -- gp:map-waypoint
		end
	end
	ended = { name = mm.name, why = why, role = mm.role, game = mm.game, by = by, mid = mm.mid }
	Log("match %s over: %s", mm.mid, tostring(why))
	Involvement()
	Arena.Changed()
	RefreshCard()
end

-- Cancel (a click): C~c and the Cancel whisper.
function ArenaMatch.Cancel()
	local mm = match
	if not mm then return false end
	if not Arena.Blocked() then Say(mm.name, L.MATCH_SAY_CANCEL) end
	End("you", "c")
	return true
end
-- Block on the card (one click): the block, then the match ends with C~c.
function ArenaMatch.BlockPartner()
	local mm = match
	if not mm then return false end
	Block(mm.name)
	End("blocked", "c")
	return true
end
function ArenaMatch.Done()
	if not match then return false end
	End("done", "d")
	return true
end
function ArenaMatch.More()
	local mm = match
	if not mm or not mm.still then return false end
	mm.still = nil
	mm.travelBy = Now() + ArenaMatch.TRAVEL_MORE
	RefreshCard()
	return true
end
function ArenaMatch.InviteNow()
	local mm = match
	if not mm then return false end
	Invite(mm.name)
	return true
end
-- [Join their layer]: Hop's ask for the partner's layer, only outside a group.
function ArenaMatch.JoinLayer()
	local mm = match
	if not mm or (IsInGroup and IsInGroup()) or not mm.theirZuid or mm.theirZuid == 0 then return false end
	local mapID = MapNow()
	if not mapID or not (ns.Hop and ns.Hop.Ask) then return false end
	ns.Hop.Ask(mapID, mm.theirZuid, Fill(L.MATCH_CARD_MEET, { name = ns.DisplayName(mm.name) }))
	return true
end
-- [Show on map] (hidden until in-game check 21): the player's own waypoint, our place.
function ArenaMatch.ShowOnMap() -- gp:map-waypoint
	if not ns.Gate.Allowed("map-waypoint") then return false end
	local mm = match
	local row = mm and PlaceRow(mm)
	local C = C_Map
	if not row or not (C and C.CanSetUserWaypointOnMap and C.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if not C.CanSetUserWaypointOnMap(row.mapID) then return false end
	C.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(row.mapID, row.x, row.y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	mm.waypoint = { row.mapID, row.x, row.y }
	return true
end

-- The hand-off (the design): a staked duel's challenge dialog (the screens), a Bones table's create panel
-- (the Bones tables, through the screens' ArenaUI.BoneInvite, which finds it under its names; else CreateTable),
-- pre-filled with the lowest stake both ranges allow and the match's id.
function ArenaMatch.HandOff()
	local mm = match
	if not mm or (mm.game == "d" and mm.kind ~= "s") then return false end
	local ok, why = Arena.LoadUI()
	if not ok then return false, why end
	local ui = Arena.ui
	local stake = mm.kind == "s" and mm.lo * 100 or 0
	if mm.game == "d" then
		if type(ui) ~= "table" or type(ui.Challenge) ~= "function" then ns.Print(L.ARENA_NO_WINDOW) return false, "window" end
		ns.SafeCall("arena match challenge", ui.Challenge, mm.name, { stake = stake, from = mm.mid })
	else
		local open = type(ui) == "table" and ((type(ui.BoneInvite) == "function" and ui.BoneInvite)
			or (type(ui.CreateTable) == "function" and ui.CreateTable)) or nil
		if not open then ns.Print(L.ARENA_NO_WINDOW) return false, "window" end
		ns.SafeCall("arena match table", open, { guest = mm.name, stake = stake, practice = mm.kind ~= "s", from = mm.mid })
	end
	mm.handed = mm.handed or Now()
	handed[mm.mid] = { name = mm.name, game = mm.game, lo = mm.lo, hi = mm.hi, formed = mm.formed, t = Now() }
	Arena.Changed()
	RefreshCard()
	return true
end

-- the fights part and the Bones tables, before showing a challenge or a table invite from a matched partner: the agreed
-- stake holds (copper; a casual match agreed none), while the match lives here (its hand-off
-- included, HANDED_MAX at most). Once it is over (Done, Cancel, a clock, Ended), a challenge from
-- that player is an ordinary one: not ours to say.
function ArenaMatch.Vet(sender, game, stake)
	local key = Lower(sender)
	if not key then return true end
	local rec
	if match and Lower(match.name) == key then rec = match end
	-- (What Ended still needs of matches gone, and not longer than that.)
	local now = Now()
	for mid, h in pairs(handed) do
		if now - h.t > ArenaMatch.HANDED_MAX * 4 then handed[mid] = nil end
	end
	if not rec then return true end
	stake = floor(tonumber(stake) or 0)
	if game ~= rec.game then
		if stake > 0 then return false, "m" end
		return true
	end
	if stake < rec.lo * 100 or stake > rec.hi * 100 then return false, "m" end
	-- The partner's challenge or invitation for this match: on this side too the match is handed
	-- over (its clocks stop; the group it formed waits for Ended).
	if rec == match and not match.handed then
		match.handed = Now()
		handed[match.mid] = { name = match.name, game = match.game, lo = match.lo, hi = match.hi, formed = match.formed, t = Now() }
		Arena.Changed()
		RefreshCard()
	end
	return true, rec.mid
end

-- the fights part and the Bones tables, when the fight or the table a match handed off to ends: the group it formed goes.
function ArenaMatch.Ended(mid)
	if type(mid) ~= "string" or mid == "" then return false end
	local h = handed[mid]
	if match and match.mid == mid then
		local rec = h or match
		-- This is the subsystem's end, not the card's Done button: tell the partner too. End keeps
		-- a formed-group record just long enough for us to release it below.
		End("done", "d")
		handed[mid] = nil
		LeaveFormed(rec)
		return true
	end
	if not h then return false end
	-- If the card ended first, it already sent its C and marked this retained hand-off. Otherwise
	-- one side knowing the id is enough to end the other side's card on mixed-version clients.
	if not h.matchOver then SendTo(h.name, "C~" .. mid .. "~d") end
	handed[mid] = nil
	LeaveFormed(h)
	return true
end

-- The ticker's share while a match lives: instance, clocks, arrival, the card's line.
local function MatchTick(mm, now)
	-- The partner is offline (the server said so for one of our whispers to him).
	if mm.offline then return End("offline", nil) end
	if Arena.InInstance() then
		mm.inside = mm.inside or now
		if now - mm.inside >= ArenaMatch.INSTANCE_END then return End("instance", "i") end
		return
	end
	mm.inside = nil
	if mm.handed then
		if now - mm.handed >= ArenaMatch.HANDED_MAX then return End("done", nil) end
		return
	end
	if not mm.fixed and now >= mm.agreeBy then return End("time", "t") end
	if mm.fixed and not mm.bothAt and mm.travelBy and now >= mm.travelBy and not mm.still then
		mm.still = now
		ns.PlayAlert("soft", "arena", true)
	end
	if mm.still and now - mm.still >= ArenaMatch.STILL_WAIT then return End("time", "t") end
	local here = Arrived(mm)
	if here ~= (mm.here == true) then
		mm.here = here
		mm.hWant = here
	end
	SendHere(mm, now)
	if mm.here and mm.them and not mm.bothAt then
		mm.bothAt = now
		ns.PlayAlert("soft", "arena", true)
	end
	if mm.bothAt and now - mm.bothAt >= ArenaMatch.HERE_TIME then return End("done", "d") end
end

-- Combat pauses every clock: the search's (its asks' windows and the request out too), the
-- place's, the travel's, after both arrived. So does a chat lockdown, where our messages wait.
-- An instance does not (the design): a search ends there, a match after 2 min.
local function Paused()
	return (InCombatLockdown and InCombatLockdown()) or Arena.Lockdown()
end
local function Shift(dt)
	if search then
		search.untilT = search.untilT + dt
		for _, ask in ipairs(search.asks) do ask.t = ask.t + dt end
		if search.current then search.current.t = search.current.t + dt end
	end
	local mm = match
	if mm then
		if mm.agreeBy then mm.agreeBy = mm.agreeBy + dt end
		if mm.travelBy then mm.travelBy = mm.travelBy + dt end
		if mm.still then mm.still = mm.still + dt end
		if mm.bothAt then mm.bothAt = mm.bothAt + dt end
		if mm.handed then mm.handed = mm.handed + dt end
	end
end

local function SearchTick(s, now)
	if now >= s.untilT then return StopSearch("time") end
	-- No search in an instance (the design): it ends there (and sharing turned on for it goes back).
	if Arena.InInstance() then return StopSearch("instance") end
	-- (Nothing new while locked down: an ask or a request would only wait in the hold.)
	if s.paused or Arena.Lockdown() then return end
	-- The request out: 32 s without an answer, the next offer.
	if s.current and now - s.current.t >= ArenaMatch.REQUEST_WAIT then
		s.current = nil
		Next()
	end
	-- The server says the one we asked is offline: the next offer at once.
	if s.current and s.current.offline then
		s.current = nil
		Next()
	end
	local ask = s.asks[#s.asks]
	-- The window (4 s for a zone ask, 5 s for a continent ask, both ends in).
	if s.phase == "asking" and ask and now - ask.t > ArenaMatch.WINDOW[ask.scope] then
		s.phase = "open"
		Next()
	end
	-- Nobody has accepted: once more, 20 s after the first (not once its requests are spent), the
	-- King's search too (the design, step 2).
	if s.phase == "open" and #s.asks == 1 and not s.current and not s.tail and now - s.asks[1].t >= ArenaMatch.ASK_GAP then
		Ask(2)
	end
end

Tick = function()
	local now = Now()
	local dt = lastTick and max(0, now - lastTick) or 0
	lastTick = now
	if dt > 0 and Paused() then Shift(dt) end
	-- The King's crown off: his search and his match end (and the group his match formed goes).
	if (search and search.king or match and KingAccount()) and not CrownOn() then
		if search then StopSearch("crown") end
		if match then End("crown", "c") end
	end
	if search then SearchTick(search, now) end
	if popup and now - popup.t > ArenaMatch.POPUP_TIME + 5 then Answer(popup, "expired") end
	if match then MatchTick(match, now) end
	if card and card:IsShown() and now - (card.refreshed or -huge) >= ArenaMatch.CARD_EVERY then RefreshCard() end
	Involvement()
end
ArenaMatch.Tick = function() return Tick() end -- (tests)

Involvement = function()
	local live = search ~= nil or match ~= nil or popup ~= nil
	Arena.Involve("match", live)
	if live and not ticking then
		ticking, lastTick = true, Now()
		Arena.Every(1, "match", function() ns.SafeCall("arena match tick", Tick) end)
	elseif not live and ticking then
		ticking = false
		Arena.Every(1, "match", nil)
	end
end

---------------------------------------------------------------------------
-- The messages
---------------------------------------------------------------------------

local function OnMatch(dist, sender, mode, body)
	-- (The weight rule: an ask returns after one flag lookup unless we are findable or searching.)
	if body:byte(1) == 81 and not search then
		local m = ns.db and ns.db.arenaMatch
		if not (m and m.find == true) then return end
	end
	if mode ~= Mode() or type(sender) ~= "string" then return end
	local sub, rest = body:match("^(%u)~(.*)$")
	local fn = sub and SUBS[sub]
	if fn then fn(dist, ns.FullName(sender), rest) end
end
ns.Comm.Handle("AM", ns.Arena.Handle("AM", OnMatch))

---------------------------------------------------------------------------
-- Being found: the switch and the privacy page's line (the design)
---------------------------------------------------------------------------

-- on: the player's answer; prefs: { d, b, staked } (Duels, Bones, Staked too).
function ArenaMatch.SetFindable(on, prefs)
	local m = DB()
	m.find = on and true or false
	if type(prefs) == "table" then
		m.games = { d = prefs.d ~= false, b = prefs.b ~= false }
		m.staked = prefs.staked == true
	end
	if on then m.pausedUntil, m.noes = nil, 0 end
	ns.Print(on and L.MATCH_FINDABLE_ON or L.MATCH_FINDABLE_OFF)
	Arena.Changed()
	return true
end

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "arenaFind", label = "CONSENT_ARENAFIND", text = "CONSENT_ARENAFIND_TEXT",
		-- Once the arena's tab shows, never on the King's account.
		shown = function() return TabVisible() and not KingAccount() end,
		get = function()
			local m = ns.db and ns.db.arenaMatch
			if type(m) ~= "table" then return nil end
			return m.find
		end,
		set = function(on) ArenaMatch.SetFindable(on) end,
		note = function() return not ns.Layers.Sharing() and L.CONSENT_NEEDS_LOCATION or nil end,
		-- (It never opens the privacy page by itself.)
		pending = function() return false end,
	})
end

---------------------------------------------------------------------------
-- The view (the Find dialog, the tab's status line)
---------------------------------------------------------------------------

local function PlaceView(mm)
	if not mm then return nil end
	local w = PlaceWords(mm.place, mm, true)
	return { id = mm.place, name = w.place, zone = w.zone, x = w.x, y = w.y }
end

local function StatusLine()
	if match then
		return Fill(L.MATCH_MEETING, { name = Arena.Mask(ns.DisplayName(match.name)), place = PlaceWords(match.place, match, true).place })
	end
	if search then return search.opts.reach == "c" and L.MATCH_SEARCHING_CONT or L.MATCH_SEARCHING end
	return nil
end

function ArenaMatch.View()
	local m = ns.db and ns.db.arenaMatch or {}
	local v = { state = match and "match" or (popup and "popup" or (search and "search" or "idle")), line = StatusLine() }
	local fOK, fWhy = ArenaMatch.Findable()
	v.findable = { on = m.find == true, games = { d = not (m.games and m.games.d == false), b = not (m.games and m.games.b == false) },
		staked = m.staked == true, now = fOK, why = not fOK and fWhy or nil, paused = m.pausedUntil and Now() < m.pausedUntil or false }
	local cOK, cWhy = ArenaMatch.CanSearch()
	v.can = { ok = cOK, why = cWhy, text = not cOK and ArenaMatch.WhyText(cWhy) or nil }
	v.sharing = ns.Layers.Sharing() == true
	v.staked = {}
	for g in ("db"):gmatch(".") do
		local ok, why = StakedFor(g)
		v.staked[g] = { ok = ok, why = why, text = not ok and ArenaMatch.WhyText(why) or nil }
	end
	local S = ns.Standing
	if type(S) == "table" and type(S.Cap) == "function" then
		local ok, cap = pcall(S.Cap, "bet", ns.me)
		v.stakeMax = ok and tonumber(cap) or nil
	end
	v.firstTime = m.seen ~= true
	v.firstLine = L.MATCH_FIRST_LINE
	local R = ns.ArenaRoles
	v.rehearsal = not (R and R.Live and R.Live()) and L.MATCH_REHEARSAL or nil
	if search then
		local s = search
		v.search = { game = s.opts.game, kind = s.opts.kind, lo = s.opts.lo * 100, hi = s.opts.hi * 100, level = s.opts.level, reach = s.opts.reach,
			started = s.started, left = max(0, floor(s.untilT - Now())), answers = s.count, requests = s.requests, tail = s.tail == true,
			paused = s.paused == true, asking = s.current and Arena.Mask(ns.DisplayName(s.current.name)) or nil }
		if s.king then
			v.offers = {}
			for _, e in ipairs(Ranked()) do
				v.offers[#v.offers + 1] = { id = e.o.id, name = Arena.Mask(ns.DisplayName(e.o.name)), band = e.band, level = e.o.lvl,
					class = ClassName(e.o.class), game = e.game, kind = e.kind }
			end
		end
	end
	if match then
		local mm = match
		v.match = { mid = mm.mid, name = Arena.Mask(ns.DisplayName(mm.name)), role = mm.role, game = mm.game, kind = mm.kind, lo = mm.lo * 100,
			hi = mm.hi * 100, place = PlaceView(mm), fixed = mm.fixed == true, mine = mm.mine == true, theirs = mm.theirs == true,
			here = mm.here == true, them = mm.them == true, both = mm.bothAt ~= nil, handed = mm.handed ~= nil, still = mm.still ~= nil }
	end
	if ended then v.ended = { name = Arena.Mask(ns.DisplayName(ended.name)), why = ended.why } end
	return v
end

---------------------------------------------------------------------------
-- The card (OlympusArenaMatchCard): Olympus's own frame, parchment and dark ink, built on first
-- use (the partner may never have loaded the companion). Every button is its own click, 24 px or
-- taller; Escape closes it only through ns.EscapeCloses; no edit box; Reply opens Olympus's
-- whisper dialog (UI.WhisperWindow), never the chat box.
---------------------------------------------------------------------------

local function DirWord(word) return word and rawget(L, "MATCH_DIR_" .. word:upper():gsub("%-", "_")) or word or "" end

-- Standing on free-for-all ground where duels are allowed (the Gurubashi floor): within an arena's
-- arrival distance of such a place.
local function FreeForAll(here)
	if not here then return false end
	local near = Places.Near(here.cont, here.wx, here.wy, function(p, d) return p.ffa == true and p.duel == true and d <= ArenaMatch.ARRIVE_ARENA end)
	return near[1] ~= nil
end

-- The card's content now: { title, lines = { text... }, rows = { { text, act } }, buttons = { key... } }.
local function Model()
	local out = { lines = {}, rows = {}, buttons = {} }
	local function Line(text) if text and text ~= "" then out.lines[#out.lines + 1] = text end end
	local function Btn(key) out.buttons[#out.buttons + 1] = key end
	if sheet then
		out.title = L.MATCH_FIND_TITLE
		Line(L.MATCH_FIRST_LINE)
		local R = ns.ArenaRoles
		if not (R and R.Live and R.Live()) then Line(L.MATCH_REHEARSAL) end
		if not ns.Layers.Sharing() and not KingAccount() then
			Line(L.MATCH_NEEDS_LOCATION)
			Btn("sharewhile") Btn("shareon")
		else
			Btn("search")
		end
		Btn("notnow")
		return out
	end
	if match then
		local mm = match
		local name = Arena.Mask(ns.DisplayName(mm.name))
		out.title = Fill(mm.role == "seeker" and L.MATCH_CARD_IN or L.MATCH_CARD_MEET, { name = name })
		local here = Here()
		local w = PlaceWords(mm.place, mm, true)
		if mm.place == "=" then
			Line(Fill(L.MATCH_CARD_NEAR, { name = name }))
		elseif mm.point and here then
			local d = Places.Dist(here, mm.point)
			if mm.here then Line(Fill(L.MATCH_CARD_PLACE_AT, { place = w.place }))
			elseif d then Line(Fill(L.MATCH_CARD_PLACE, { place = w.place, yd = Round(d), dir = DirWord(Places.Bearing(here, mm.point)) })) end
		end
		local unit = PartnerUnit(mm.name)
		if mm.bothAt then
			Line(L.MATCH_CARD_BOTH .. ((unit and mm.game == "d" and InDuelRange(unit)) and (" " .. L.MATCH_CARD_RANGE) or ""))
		elseif mm.fixed then
			Line(L.MATCH_CARD_FIXED)
		elseif mm.mine then
			Line(Fill(L.MATCH_CARD_WAIT_THEM, { name = name }))
		elseif mm.theirs then
			Line(Fill(L.MATCH_CARD_WAIT_YOU, { name = name }))
		end
		if unit then
			local them = UnitPoint(unit)
			local d = here and them and Places.Dist(here, them)
			if d then Line(Fill(L.MATCH_CARD_THEM, { yd = Round(d) })) end
		else
			local inviter = mm.role == "seeker" and Inviter(mm.myGrp, mm.theirGrp) or Inviter(mm.theirGrp, mm.myGrp)
			if inviter == mm.role then
				if mm.role == "seeker" then Line(Fill(L.MATCH_CARD_INVITE, { name = name })) end
			elseif inviter then
				Line(Fill(L.MATCH_CARD_ACCEPT, { name = name }))
			elseif mm.game == "b" then
				Line(L.MATCH_CARD_LEAVE_FIRST)
			end
			if mm.here and mm.them and mm.theirZuid and mm.theirZuid ~= 0 then
				local z = Zuid(MapNow())
				if z ~= 0 and z ~= mm.theirZuid then Line(L.MATCH_CARD_LAYER) end
			end
		end
		if mm.game == "d" and mm.kind == "c" then Line(Fill(L.MATCH_CARD_DUEL, { name = name })) end
		local row = PlaceRow(mm)
		-- A staked duel on free-for-all ground: never suggested (the design), but the place is only a
		-- suggestion and the two may duel there (the design): the card says so while the player stands on it.
		if mm.game == "d" and mm.kind == "s" and FreeForAll(here) then Line(L.MATCH_CARD_FFA) end
		if mm.kind == "s" then Line(L.MATCH_CARD_SAFE) end
		if mm.handed then Line(L.MATCH_CARD_HANDED) end
		if mm.still then Line(L.MATCH_CARD_STILL) end
		-- Other spots: the next five, where I am, close by.
		if showOther then
			Line(L.MATCH_CARD_OTHER)
			local n = 0
			for _, e in ipairs(FairList(mm.game, mm.kind, mm.cont, mm.myCell, mm.theirCell, mm.level)) do
				if e.id ~= mm.place and n < ArenaMatch.OTHER_SPOTS then
					n = n + 1
					out.rows[#out.rows + 1] = { text = Fill(L.MATCH_CARD_ROW, { place = PlaceName(e.place), mine = Round(e.a), theirs = Round(e.b) }), place = e.id }
				end
			end
			out.rows[#out.rows + 1] = { text = L.MATCH_BTN_WHERE, place = "@" }
			if mm.place ~= "=" and PlaceOK(mm, "=") then out.rows[#out.rows + 1] = { text = L.MATCH_BTN_CLOSEBY, place = "=" } end
		end
		if mm.still then Btn("more") end
		if mm.theirs and not mm.mine then Btn((mm.role == "seeker" and mm.rev == 0) and "onway" or "agree") end
		if not mm.handed then Btn("other") end
		if (mm.kind == "s" and mm.game == "d") then Btn("challenge") elseif mm.game == "b" then Btn("table") end
		if not unit and (mm.role == "seeker" and Inviter(mm.myGrp, mm.theirGrp) == "seeker") then Btn("invite") end
		if mm.here and mm.them and not unit and mm.theirZuid and mm.theirZuid ~= 0 then
			local z = Zuid(MapNow())
			if z ~= 0 and z ~= mm.theirZuid and not (IsInGroup and IsInGroup()) then Btn("join") end
		end
		if ArenaMatch.SHOW_ON_MAP and row then Btn("map") end
		Btn("room")
		Btn("reply")
		if mm.game == "d" and mm.kind == "c" or mm.handed then Btn("done") end
		Btn("cancel")
		Btn("block")
		return out
	end
	if search then
		local s = search
		out.title = L.MATCH_CARD_SEARCH
		Line(s.opts.reach == "c" and #s.asks > 1 and L.MATCH_SEARCHING_CONT or L.MATCH_SEARCHING)
		if s.count > 0 then Line(Fill(L.MATCH_ANSWERS, { n = s.count })) end
		if s.current then Line(Fill(L.MATCH_ASKING, { name = Arena.Mask(ns.DisplayName(s.current.name)) })) end
		if s.tail then Line(s.king and L.MATCH_NOBODY_KING or L.MATCH_NOBODY) end
		if s.king and not s.current then
			local list = Ranked()
			if #list > 0 then Line(L.MATCH_KING_OFFERS) elseif not s.tail then Line(L.MATCH_KING_NONE) end
			for i, e in ipairs(list) do
				if i > 5 then break end
				out.rows[#out.rows + 1] = { text = ("%s (%d %s)"):format(Arena.Mask(ns.DisplayName(e.o.name)), e.o.lvl, ClassName(e.o.class)), pick = e.o.id }
			end
		end
		Btn("stopsearch")
		return out
	end
	if ended then
		local name = Arena.Mask(ns.DisplayName(ended.name))
		out.title = L.MATCH_CARD_OVER
		local texts = { cancel = L.MATCH_END_CANCEL, you = L.MATCH_END_YOU, time = L.MATCH_END_TIME, instance = L.MATCH_END_INSTANCE,
			done = L.MATCH_END_DONE, place = L.MATCH_END_PLACE, lie = L.MATCH_END_LIE, crown = L.MATCH_END_CROWN, offline = L.MATCH_END_OFFLINE,
			blocked = L.MATCH_END_BLOCKED }
		Line(Fill(texts[ended.why] or L.MATCH_END_DONE, { name = name }))
		local room = ended.mid and ArenaMatch.ChatRoom(ended.mid)
		if room and room.recoverable then Btn("room") end
		if ended.why ~= "done" and ended.why ~= "crown" then Btn("again") end
		if IsInGroup and IsInGroup() then Btn("leave") end
		Btn("close")
		return out
	end
	return nil
end
ArenaMatch.CardModel = Model

-- The buttons that send a whisper: greyed out while chat is locked down or in an instance.
local WHISPERS = { onway = true, agree = true, other = true, reply = true, cancel = true }
local LABELS = { onway = "MATCH_BTN_ONWAY", agree = "MATCH_BTN_AGREE", other = "MATCH_BTN_OTHER", reply = "MATCH_BTN_REPLY",
	cancel = "MATCH_BTN_CANCEL", block = "MATCH_BTN_BLOCK", challenge = "MATCH_BTN_CHALLENGE", table = "MATCH_BTN_TABLE",
	invite = "MATCH_BTN_INVITE", done = "MATCH_BTN_DONE", more = "MATCH_BTN_MORE", join = "MATCH_BTN_JOIN", map = "MATCH_BTN_MAP",
	leave = "MATCH_BTN_LEAVE", again = "MATCH_BTN_AGAIN", close = "MATCH_BTN_CLOSE", search = "MATCH_BTN_SEARCH",
	room = "MATCH_BTN_ROOM", newfind = "MATCH_BTN_AGAIN", details = "MATCH_BTN_DETAILS",
	sharewhile = "MATCH_BTN_SHARE_WHILE", shareon = "MATCH_BTN_SHARE_ON", notnow = "MATCH_BTN_NOT_NOW", stopsearch = "MATCH_BTN_CANCEL" }

local lastOpts
local function QuickStart(share)
	local game = sheet and sheet.game or "d"
	sheet = nil
	local ok, why = ArenaMatch.Start({ game = game, kind = "c", level = 5, reach = "z", share = share })
	if not ok then
		ns.Print(ArenaMatch.WhyText(why))
		RefreshCard()
	end
	return ok, why
end

local ACTIONS = {
	onway = function() ArenaMatch.Agree() end,
	agree = function() ArenaMatch.Agree() end,
	other = function() showOther = not showOther RefreshCard() end,
	reply = function()
		if match and ns.UI and ns.UI.WhisperWindow then ns.UI.WhisperWindow(ns.TellName(match.name)) end
		-- (The whisper dialog takes the top of the column: the card goes under it.)
		PlaceCard()
	end,
	cancel = function() ArenaMatch.Cancel() end,
	block = function() ArenaMatch.BlockPartner() end,
	challenge = function() ArenaMatch.HandOff() end,
	table = function() ArenaMatch.HandOff() end,
	invite = function() ArenaMatch.InviteNow() end,
	done = function() ArenaMatch.Done() end,
	more = function() ArenaMatch.More() end,
	join = function() ArenaMatch.JoinLayer() end,
	map = function() ArenaMatch.ShowOnMap() end,
	room = function()
		local mid = match and match.mid or ended and ended.mid
		return ArenaMatch.OpenRoom(mid)
	end,
	leave = function() LeaveGroup() RefreshCard() end,
	again = function()
		local game = ended and ended.game or "d"
		ended = nil
		local ok, why = ArenaMatch.Start(lastOpts or { game = game })
		if not ok then ns.Print(ArenaMatch.WhyText(why)) RefreshCard() end
	end,
	close = function() ended = nil if card then card:Hide() end end,
	search = function() QuickStart(false) end,
	sharewhile = function() QuickStart(true) end,
	shareon = function()
		local C = ns.Consent
		if C and C.Choose and C.Choose("location", true) then QuickStart(false) return end
		ns.Layers.SetSharing(true)
		QuickStart(false)
	end,
	notnow = function() sheet = nil if card then card:Hide() end end,
	stopsearch = function() ArenaMatch.Stop() end,
}

-- A font string or a button's label at 13 px at least.
local function AtLeast(fs, px)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and type(path) == "string" and type(size) == "number" and size < px then fs:SetFont(path, px, flags) end
end
local INK = { 0.20, 0.12, 0.04 }

-- Where the card sits (the owner's rule: nothing overlapping): in the column the game's popups and
-- Olympus's own dialogs (Dialog.lua) stack in from the top, under the lowest one up, or where the
-- first of them would sit when none is: neither ever covers the other (the Let's go popup over a
-- searcher's card, the whisper dialog of [Reply], the game's own group invite). It moves there
-- again when one comes or goes (each refresh, and a quarter-second look while it shows), until
-- the player drags it somewhere of his own.
ArenaMatch.CARD_TOP = -135 -- the game's first popup's place (Dialog.TOP)
ArenaMatch.CARD_GAP = 8
local function Lowest()
	local low, order
	for i = 1, 4 do
		local p = _G["StaticPopup" .. i] -- gp:lookups
		if type(p) == "table" and p.IsShown and p:IsShown() then low = p end
	end
	-- (Olympus's dialogs stack under the game's popups, in the order they came.)
	for i = 1, 3 do
		local d = _G["OlympusDialog" .. i] -- gp:lookups
		if type(d) == "table" and d.IsShown and d:IsShown() and (order == nil or (tonumber(d.order) or 0) > order) then
			low, order = d, tonumber(d.order) or 0
		end
	end
	return low
end
-- (Its state in a table of its own, not in fields of the frame.)
local placed = { done = false, below = nil, moved = false, look = 0, host = nil }

-- A game's own window may hold the card (the companion's Bones window, the owner on test 32: the
-- search and the match show inside it, never in another window): ArenaMatch.SetCardHost(fn), fn(game)
-- -> that window and the level above it, or nil. While it answers, the card is a component of that
-- window: parented to it, centred in it; when it stops (the window closed, a duel search), the card
-- goes back to its own place, above. Only where it is shown changes: its content, its buttons and
-- the match itself are the same. (The window may hide it under another of its parts, and give it
-- back with ArenaMatch.ShowCard.)
local cardHost
function ArenaMatch.SetCardHost(fn) cardHost = type(fn) == "function" and fn or nil end
local function GameNow()
	return (match and match.game) or (search and search.opts.game) or (popup and popup.game) or (sheet and sheet.game) or (ended and ended.game)
end
local function HostNow()
	if not cardHost then return nil end
	local ok, f, level = pcall(cardHost, GameNow())
	if not ok or type(f) ~= "table" or type(f.IsShown) ~= "function" or not f:IsShown() then return nil end
	return f, tonumber(level) or 60
end
-- The window holding it hears when it shows or hides there (its Escape and its other parts).
local function Told(h, shown)
	local fn = type(h) == "table" and rawget(h, "hostChanged")
	if type(fn) == "function" then ns.SafeCall("arena match host", fn, card, shown) end
end
PlaceCard = function()
	if not card then return end
	local host, level = HostNow()
	if host then
		if placed.host == host then return end
		-- (the window's place replaces one the player dragged it to; back above, it starts over)
		placed.host, placed.done, placed.moved = host, false, false
		card:SetParent(host)
		local strata = host.GetFrameStrata and host:GetFrameStrata()
		if strata then card:SetFrameStrata(strata) end
		card:SetFrameLevel((tonumber(host:GetFrameLevel()) or 0) + level)
		card:ClearAllPoints()
		card:SetPoint("CENTER", host, "CENTER", 0, 0)
		if card:IsShown() then Told(host, true) end
		return
	end
	if placed.host then
		local old = placed.host
		placed.host, placed.done = nil, false
		card:SetParent(UIParent)
		card:SetFrameStrata("DIALOG")
		if card:IsShown() then Told(old, false) end
	end
	if placed.moved then return end
	local low = Lowest()
	if placed.done and placed.below == low then return end
	placed.done, placed.below = true, low
	card:ClearAllPoints()
	if low then
		card:SetPoint("TOP", low, "BOTTOM", 0, -ArenaMatch.CARD_GAP)
	else
		card:SetPoint("TOP", UIParent, "TOP", 0, ArenaMatch.CARD_TOP)
	end
end

local function MakeCard()
	local f = ns.Window("OlympusArenaMatchCard", UIParent, { inset = false, close = false, escape = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	-- (Inside a window that holds it, a drag moves that window.)
	f:SetScript("OnDragStart", function(self)
		local h = placed.host
		if h then if h.StartMoving then h:StartMoving() end return end
		self:StartMoving()
	end)
	f:SetScript("OnDragStop", function(self)
		local h = placed.host
		if h then if h.StopMovingOrSizing then h:StopMovingOrSizing() end return end
		self:StopMovingOrSizing()
		placed.moved = true -- where the player puts it, it stays
	end)
	f:SetWidth(ArenaMatch.CARD_WIDTH)
	-- (A look at the popups four times a second while it shows: OnUpdate runs only then.)
	f:SetScript("OnUpdate", function(_, elapsed)
		placed.look = placed.look + (tonumber(elapsed) or 0)
		if placed.look < 0.25 then return end
		placed.look = 0
		PlaceCard()
	end)
	-- (1.1.5: every window in the Olympus window's bronze metal, ns.Window; the parchment inside it.)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", f.inner[1], f.inner[2])
	bg:SetPoint("BOTTOMRIGHT", f.inner[3], f.inner[4])
	local UI = ns.UI
	local file = UI and UI.FirstTexture and UI.PARCHMENTS and UI.FirstTexture(UI.PARCHMENTS) or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	-- Morpheus for the title (the quest title's font), dark ink for the rest.
	f.title = f:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.title:SetJustifyH("CENTER")
	AtLeast(f.title, 16)
	f.lines, f.buttons, f.rows = {}, {}, {}
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	-- A short fade in (an AnimationGroup, never OnUpdate).
	if f.CreateAnimationGroup then
		local g = f:CreateAnimationGroup()
		local a = g and g.CreateAnimation and g:CreateAnimation("Alpha")
		if a and a.SetFromAlpha then
			a:SetFromAlpha(0)
			a:SetToAlpha(1)
			a:SetDuration(0.2)
			f.fade = g
		end
	end
	ns.EscapeCloses("OlympusArenaMatchCard")
	f:HookScript("OnShow", function(self)
		ns.EscapeCloses(self:GetName())
		if self.fade and self.fade.Play then self.fade:Play() end
		Told(placed.host, true)
	end)
	f:HookScript("OnHide", function() Told(placed.host, false) end)
	f:Hide()
	return f
end

local function TextLine(f, i)
	local fs = f.lines[i]
	if fs then return fs end
	fs = f:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	if not _G.QuestFont and fs.SetTextColor then fs:SetTextColor(INK[1], INK[2], INK[3]) end
	AtLeast(fs, 13)
	f.lines[i] = fs
	return fs
end
local function Button(f, key)
	local b = f.buttons[key]
	if b then return b end
	b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetHeight(26)
	b.key = key
	b:SetText(L[LABELS[key]])
	AtLeast(b.GetFontString and b:GetFontString(), 13)
	b:SetScript("OnClick", function() ns.SafeCall("arena match " .. key, ACTIONS[key]) end)
	f.buttons[key] = b
	return b
end
local function Row(f, i)
	local b = f.rows[i]
	if b then return b end
	b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetHeight(24)
	AtLeast(b.GetFontString and b:GetFontString(), 13)
	-- (What the row does lives in a table of its own: b.row = { place } or { pick }.)
	b:SetScript("OnClick", function(self)
		ns.SafeCall("arena match row", function()
			local r = type(self.row) == "table" and self.row or {}
			if r.place then ArenaMatch.Propose(r.place) elseif r.pick then ArenaMatch.Pick(r.pick) end
		end)
	end)
	f.rows[i] = b
	return b
end
local function Height(fs, width)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if type(h) == "number" and h > 0 then return h end
	local per = max(1, floor(width / 7))
	return max(1, math.ceil(#(fs:GetText() or "") / per)) * 16
end
local function Width(b, label)
	local fs = b.GetFontString and b:GetFontString()
	local w = fs and fs.GetStringWidth and fs:GetStringWidth()
	if type(w) ~= "number" or w <= 0 then w = #tostring(label or "") * 7 end
	return max(84, math.ceil(w) + 28)
end

-- Lays the card out again: each thing in its own place, top to bottom, nothing overlapping.
RefreshCard = function()
	if not card then return end
	card.refreshed = Now()
	local m = Model()
	if not m then card:Hide() return end
	local W = ArenaMatch.CARD_WIDTH
	local inner = W - 48
	local y = -26
	card.title:ClearAllPoints()
	card.title:SetPoint("TOP", card, "TOP", 0, y)
	-- (Clear of the close button in the corner.)
	card.title:SetWidth(W - 88)
	card.title:SetText(m.title or "")
	y = y - Height(card.title, W - 88) - 12
	for i, text in ipairs(m.lines) do
		local fs = TextLine(card, i)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", 24, y)
		fs:SetWidth(inner)
		fs:SetText(text)
		fs:Show()
		y = y - Height(fs, inner) - 6
	end
	for i = #m.lines + 1, #card.lines do card.lines[i]:SetText("") card.lines[i]:Hide() end
	for i, r in ipairs(m.rows) do
		local b = Row(card, i)
		b.row = { place = r.place, pick = r.pick }
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", card, "TOPLEFT", 24, y)
		b:SetWidth(inner)
		b:SetText(r.text)
		b:SetEnabled(r.pick ~= nil or not Arena.Blocked())
		b:Show()
		y = y - 28
	end
	for i = #m.rows + 1, #card.rows do card.rows[i]:Hide() end
	y = y - 6
	local shown = {}
	local x, rowY = 24, y
	for _, key in ipairs(m.buttons) do
		local b = Button(card, key)
		shown[key] = true
		local w = Width(b, L[LABELS[key]])
		if x > 24 and x + w > W - 24 then x, rowY = 24, rowY - 32 end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", card, "TOPLEFT", x, rowY)
		b:SetWidth(w)
		b:SetEnabled(not (WHISPERS[key] and Arena.Blocked()))
		b:Show()
		x = x + w + 8
	end
	for key, b in pairs(card.buttons) do if not shown[key] then b:Hide() end end
	card:SetHeight(-(rowY - 26 - 22))
	PlaceCard()
end

ShowCard = function()
	card = card or MakeCard()
	RefreshCard()
	if Model() then card:Show() end
end
function ArenaMatch.Card() return card end
-- The card to its place again now (a window that may hold it opened, closed, or covered it).
function ArenaMatch.PlaceCard() if card then PlaceCard() end end
-- The card again, its content as it is now, while there is one to show (a search, an offer, a
-- match or its end): the window that held it under another of its parts gives it back. True when
-- it shows.
function ArenaMatch.ShowCard()
	if not Model() then return false end
	ShowCard()
	return card ~= nil and card:IsShown()
end

---------------------------------------------------------------------------
-- Opening it: the action (the arena's buttons), and /oly arena find
---------------------------------------------------------------------------

-- match.open: the live search's or match's card first (closed with X or Escape, it comes back);
-- else the screens' Find dialog when the companion has it; else the card's short sheet (its first time,
-- or when a choice is needed), else a search at once on the defaults.
Open = function(game)
	game = game == "b" and "b" or "d"
	if match or search or popup then ShowCard() return true end
	local ok = Arena.LoadUI()
	local ui = Arena.ui
	if ok and type(ui) == "table" and type(ui.OpenFind) == "function" then
		ui.OpenFind(game)
		return true
	end
	local m = ns.db and ns.db.arenaMatch
	if not (m and m.seen) or (not ns.Layers.Sharing() and not KingAccount()) then
		sheet, ended = { game = game }, nil
		ShowCard()
		return true
	end
	sheet = { game = game }
	return QuickStart(false)
end

-- A match room is a view of the live card's existing actions. Advanced location choices still
-- open that card, so the room never grows a competing proposal or readiness state machine.
local ROOM_ACTION = { onway = true, agree = true, other = true, challenge = true, table = true,
	invite = true, join = true, map = true, done = true, cancel = true, more = true }

local function EndLine(rec)
	local texts = { cancel = L.MATCH_END_CANCEL, you = L.MATCH_END_YOU, time = L.MATCH_END_TIME,
		instance = L.MATCH_END_INSTANCE, done = L.MATCH_END_DONE, place = L.MATCH_END_PLACE,
		lie = L.MATCH_END_LIE, crown = L.MATCH_END_CROWN, offline = L.MATCH_END_OFFLINE,
		blocked = L.MATCH_END_BLOCKED }
	return Fill(texts[rec.why] or L.MATCH_END_DONE, { name = Arena.Mask(ns.DisplayName(rec.name)) })
end

function ArenaMatch.RoomView(mid)
	local rec, active = RoomRecord(mid)
	local spec = rec and ArenaMatch.ChatRoom(mid) or nil
	if not spec or not spec.recoverable then return nil, "expired" end
	local out = { id = mid, title = spec.title, active = active, phase = spec.phase, lines = {}, actions = {} }
	if active and match and match.mid == mid then
		local model = Model()
		for i = 1, math.min(3, #(model and model.lines or {})) do out.lines[#out.lines + 1] = model.lines[i] end
		for _, key in ipairs(model and model.buttons or {}) do
			if ROOM_ACTION[key] then out.actions[#out.actions + 1] = { key = key, label = L[LABELS[key]] } end
		end
		out.actions[#out.actions + 1] = { key = "details", label = L.MATCH_BTN_DETAILS }
	else
		out.lines[1] = EndLine(rec)
		-- An old room never displaces a live match or search. Its identity/history remains intact
		-- while the ordinary fixed-game Find dialog is offered only when matchmaking is idle.
		if not match and not search and not popup then
			out.actions[1] = { key = "newfind", label = L.MATCH_BTN_AGAIN }
		end
	end
	return out
end

function ArenaMatch.RoomAction(mid, key)
	local rec, active = RoomRecord(mid)
	local spec = rec and ArenaMatch.ChatRoom(mid) or nil
	if not spec or not spec.recoverable then return false, "expired" end
	if key == "newfind" then
		if active or match or search or popup then return false, "busy" end
		return Open(rec.game)
	end
	if not active or not match or match.mid ~= mid then return false, "over" end
	if key == "details" then ShowCard() return true end
	local fn = ROOM_ACTION[key] and ACTIONS[key] or nil
	if not fn then return false, "action" end
	if key == "other" then ShowCard() end
	local result, why = fn()
	if result == false then return false, why end
	return true
end

function ArenaMatch.RoomWhyText(why)
	if why == "expired" then return L.MATCH_ROOM_EXPIRED end
	if why == "over" then return L.MATCH_ROOM_OVER end
	if why == "busy" then return L.MATCH_WHY_BUSY end
	return L.MATCH_ROOM_UNAVAILABLE
end

-- The match's room, as every pending conversation opens (ChatRooms.OpenMatter): its tab on the
-- Chat page with the Olympus window in front, pinned while the match lives. `auto`: the match
-- found, not the card's click (in an instance or Busy, a fight, or while the player writes in the
-- Chat page's box, it waits; its sound, the "arena" switch's).
function ArenaMatch.OpenRoom(mid, auto)
	local spec = type(mid) == "string" and ArenaMatch.ChatRoom(mid) or nil
	if not spec or not spec.recoverable then return false, "expired" end
	local R = rawget(ns, "ChatRooms")
	if type(R) ~= "table" or type(R.OpenMatter) ~= "function" then return false, "window" end
	return R.OpenMatter({ spec = function() return ArenaMatch.ChatRoom(mid) end, auto = auto == true, kind = "arena" })
end

Arena.Action("match.open", function() if not ns.IsMember() then return false, "guild" end return true end, function(game) return Open(game) end)

-- Every search from a click or the Find dialog keeps its terms for [Find someone else].
local startRaw = ArenaMatch.Start
function ArenaMatch.Start(opts)
	local ok, why = startRaw(opts)
	if ok then lastOpts = opts end
	return ok, why
end

Arena.Slash("find", function(args)
	local word = tostring(args or ""):lower():match("^%s*(%S*)")
	-- (Counts to copy into a report: the copy pop-up, never chat.)
	if word == "status" then
		if ns.UI and ns.UI.ShowCopy then return ns.UI.ShowCopy(L.MATCH_STATUS_TITLE, ArenaMatch.StatusLine()) end
		return ns.Print(ArenaMatch.StatusLine())
	end
	if word == "cancel" or word == "stop" then
		if match then return ArenaMatch.Cancel() end
		return ArenaMatch.Stop()
	end
	local ok, why = Arena.Do("match.open", (word == "bone" or word == "b") and "b" or "d")
	if not ok and why then ns.Print(ArenaMatch.WhyText(why)) end
end, L.MATCH_HELP_FIND)

-- One line of counts: /oly arena find status, in the copy pop-up. (Not in ns.statusLines: the arena's foundation
-- keeps /oly status to ArenaNet's own lines.)
function ArenaMatch.StatusLine()
	local m = ns.db and ns.db.arenaMatch or {}
	return ("match: findable=%s %s  |  asks=%d heard=%d offers=%d requests=%d popups=%d matches=%d lies=%d dropped=%d"):format(
		tostring(m.find == true), tostring(select(2, ArenaMatch.Findable()) or "now"), stats.asks, stats.heard, stats.offers, stats.requests,
		stats.popups, stats.matches, stats.lies, stats.dropped)
end
function ArenaMatch.Stats() return stats end
