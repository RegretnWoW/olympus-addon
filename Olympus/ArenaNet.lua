local ADDON, ns = ...
local L = ns.L

-- The Blood Arena's core network (1.2): every arena message goes out and comes in through here.
--
-- The envelope. Every arena message is <type>~<mode><proto>~<body>: "AF~L1~...". The mode is L
-- (live) or T (a rehearsal, a test build); the protocol is 1, and a client drops any other. The
-- King's arena words are not enveloped: they are kinds of the King's T1 (ArenaRoles.lua).
--
-- The weight rule (the design). Until something involves this client (Arena.Involve: a duty, a
-- fight, a table, a ticket, a rehearsal, the open window), the arena creates no frame, registers
-- no WoW event and runs no timer: Arena.Every and Arena.After wait, the one arena ticker (1 s) is
-- stopped. The only cost of an idle client is its Comm.Handle entries, the small verification sets
-- and one PLAYER_LOGOUT handler that writes the persistence sentinel (Arena.Persists). Events a
-- send needs (the not-found system line, the lockdown recheck) are registered on first use, and
-- their handlers return at once when nothing expects them.
--
-- What this file owns (ns.Arena, the design): modes and stores (Mode, NewMode, Store, Heavy, Counts,
-- Lane, RealmOf), sending (Send, pieces over 255 bytes with their own assembler, the low lane, the
-- must-deliver retries (a refused piece again alone, else the whole payload again), the urgent
-- share, the per-target whisper outbox, a must-deliver whisper to a target offline kept until he
-- is back, the lockdown hold, the net-off hold on the whole payload),
-- receiving (Handle, Inject), the signature queue (Verify), parse helpers, involvement and its
-- ticker (Involve, Every, After, Changed), actions (Action, Can, Do), the /oly arena router (Slash,
-- RunSlash), the companion (LoadUI and its handoff), the test build, the kill switch, the sim switch,
-- the rules' yes, the persistence gate, the King's view and the stream delay, and the events
-- registry (Events.Register, EventOf). No arena file names the author (the design).

local Arena = {}
ns.Arena = Arena -- (replaces Core.lua's stand-in)

Arena.PROTO = 1
Arena.ROOM = 2                -- the low lane sends while Comm's queue holds this many or fewer
Arena.URGENT_SHARE = 8        -- arena items urgent in Comm's queue at once; the rest wait here
Arena.PIECE = 220             -- bytes of a payload in one EP piece
Arena.PIECES_MAX = 30         -- pieces of one payload at most (6,600 bytes)
Arena.OPEN_PER_SENDER = 4     -- payloads being put together from one sender at once
Arena.OPEN_MAX = 64           -- ...and from everyone
Arena.PIECE_TTL = 60          -- seconds a payload has to arrive whole
Arena.PIECE_SLACK = 5         -- ...of which a piece sent again alone leaves this much spare (else the whole goes again)
Arena.PACE = 1.2              -- seconds between two of Comm's sends (Comm.lua's SEND_INTERVAL)
Arena.TICK = 1                -- the arena ticker's period, while anything is involved
Arena.BACKOFF = { 2, 4, 8, 16, 32, 60 } -- must-deliver retries (then every 60 s)
Arena.RETRIES_MAX = 20        -- a must-deliver message given up after this many tries
Arena.BACKLOG_MAX = 400       -- messages held here (lockdown, the urgent share) at most
Arena.LOW_MAX = 400           -- messages waiting on the low lane at most
Arena.CHANGED_GAP = 1         -- ARENA_CHANGED at most once a second
Arena.DELAY_MAX = 900         -- the King's stream delay, seconds
Arena.RULES_VERSION = 1
Arena.TEST_DAYS_MAX = 60      -- a test build lives this long at most (the design)
Arena.COMPANION = "Olympus_Arena"
Arena.VERIFY_BUSY = 40        -- signature jobs fed to Ed25519.lua only below its limit
Arena.VERIFY_QUEUE = 200      -- claims waiting at most
Arena.GONE_FOR = 60           -- a target the server did not find: its whispers dropped this long
Arena.PARK_PROBE = { 60, 120, 300, 600 } -- a must-deliver whisper to a target offline: tried again this far apart (then every 600 s)
Arena.PARK_TRIES = 36         -- ...this many times at most (about six hours)

-- Every arena type and the file that registers it (the design, Comm.lua's list). 5 E, 19 Z, 6 B,
-- 15 A, 3 I, 16 K (the design adds KL), matchmaking's AM (the design), the Lottery's
-- winners, LW (its bank's word for the Games tab's rankings), and the games' rankings'
-- publish word AU (ArenaRoles, 2026-10-04), and the games' ledger AY (ArenaLedger, 1.1.6): 68.
-- Arena.Send refuses any other type.
Arena.TYPES = {
	EP = "ArenaNet", EC = "ArenaChat", EM = "ArenaChat", ER = "ArenaTest", EH = "ArenaTest",
	ZH = "Wallet", ZE = "Wallet", ZN = "Wallet", ZG = "Wallet", ZD = "Wallet", ZK = "Wallet", ZC = "Wallet",
	ZW = "Wallet", ZS = "Wallet", ZQ = "Wallet", ZL = "Wallet", ZJ = "Wallet",
	ZT = "Debts", ZX = "Debts", ZY = "Debts", ZR = "Debts", ZF = "Debts", ZA = "Stakes", ZV = "Stakes",
	BM = "Markets", BO = "Markets", BS = "Markets", BK = "Markets", BV = "Markets", BF = "MarketBank",
	AF = "ArenaFights", AG = "ArenaFights", AC = "ArenaFights", AW = "ArenaFights", AR = "ArenaFights",
	AS = "ArenaFights", AN = "ArenaFights", AE = "ArenaLedger", AB = "ArenaLedger", AQ = "ArenaLedger",
	AV = "ArenaLedger", AH = "ArenaLedger", AT = "ArenaTourney", AD = "ArenaTourney", AP = "ArenaProfile",
	IL = "HonorsNet", ID = "HonorsNet", IO = "HonorsNet",
	KI = "FarkleTable", KA = "FarkleTable", KO = "FarkleTable", KP = "FarkleTable", KG = "FarkleTable",
	KY = "FarkleTable", KH = "FarkleTable", KK = "FarkleTable", KT = "FarkleTable", KE = "FarkleTable",
	KQ = "FarkleTable", KR = "FarkleTable", KS = "FarkleTable", KN = "FarkleTable", KD = "FarkleTable",
	KL = "FarkleTable", -- (the design: the arbiter's floor under a drunk level)
	AY = "ArenaLedger", -- (1.1.6: a finished game's record to the auditors, the games' ledger)
	AM = "ArenaMatch",
	LW = "Lottery",
	AU = "ArenaRoles",
}
-- A player's own obligations go out even with the arena turned off, and in L while the live switch
-- is off (the design): receipts, key claims, Farkle's payments; a debt mark about himself (ZX) and a
-- signed result (AW) when the caller says so (o.obligation).
Arena.OBLIGATIONS = { ZR = true, ZF = true, KD = true, ZT = true }
-- Honours are not bets: they go out in L whatever the live switch says (a donor's frame, the level
-- race, the frame and title pick, the design: a pick is sent with live = 0). Nor is a match (AM,
-- the design): it moves nothing; the challenge or table it hands off to fixes its own mode.
-- Nor is the games' ledger (AY, 1.1.6): a game's record to the auditors, whatever its mode.
Arena.LIVE_EXEMPT = { AP = true, IL = true, ID = true, IO = true, AM = true, AU = true, AY = true }
-- The types a sender may mark as his own obligation (o.obligation: ZX about himself, a staked AW,
-- the Wallet's hello): taken in L whatever the switch, their handlers check the rest.
Arena.MAY_OBLIGE = { ZX = true, ZQ = true, AW = true }
-- Only ID rides GUILD (the Treasurer's own client, the design); nothing else is relayed there.
Arena.GUILD_TYPES = { ID = true }
-- The letters of Arena.NewId: a fight, a card (Fight Night), a tournament, a Farkle table, a
-- Lottery day (the design), a match (matchmaking, the design), a game played alone in the
-- games' ledger (the House, the Lottery's practice: ArenaLedger.SoloId, 1.1.6).
Arena.ID_LETTERS = { F = true, N = true, T = true, K = true, L = true, M = true, G = true }

local stats = { refused = {}, dropped = {}, sent = 0, pieces = 0, assembled = 0, retried = 0, held = 0, parked = 0 }
local function Count(t, why) t[why] = (t[why] or 0) + 1 end
function Arena.Stats()
	return { refused = stats.refused, dropped = stats.dropped, sent = stats.sent, pieces = stats.pieces, assembled = stats.assembled,
		retried = stats.retried, held = stats.held, urgentOut = Arena.UrgentOut(), backlog = Arena.BacklogSize(), low = Arena.LowSize(),
		retries = Arena.RetrySize(), ticker = Arena.Ticking(), producers = Arena.ProducerCount(), parked = Arena.ParkedSize(), everParked = stats.parked }
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
-- A whole number of 0 or more in base 36 (lower case), as every arena body writes numbers.
function Arena.B36(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return "0" end
	local out = {}
	while n > 0 do
		local d = n % 36
		out[#out + 1] = B36:sub(d + 1, d + 1)
		n = (n - d) / 36
	end
	return table.concat(out):reverse()
end
-- A base-36 number between lo and hi (inclusive), or nil.
function Arena.N(s, lo, hi)
	if type(s) ~= "string" or s == "" or #s > 12 or not s:find("^[0-9a-z]+$") then return nil end
	local n = tonumber(s, 36)
	if not n or (lo and n < lo) or (hi and n > hi) then return nil end
	return n
end
-- Copper in base 36: a whole amount a stake or a pool can be (at most 2^31 - 1, ArenaMath's bound).
Arena.COPPER_MAX = 2147483647
function Arena.Copper(s) return Arena.N(s, 0, Arena.COPPER_MAX) end

-- The fields of a body split on "~": exactly n of them (the last keeps any "~" after it), returned
-- as n values; nothing when there are fewer.
function Arena.Fields(body, n)
	if type(body) ~= "string" then return end
	local out, from = {}, 1
	n = math.max(1, math.floor(tonumber(n) or 1))
	for _ = 1, n - 1 do
		local at = body:find("~", from, true)
		if not at then return end
		out[#out + 1] = body:sub(from, at - 1)
		from = at + 1
	end
	out[#out + 1] = body:sub(from)
	return unpack(out, 1, n)
end

-- A character's name as another player sends it: through King.CleanName (a first name and a
-- surname, no free text), with its realm when it gives a plausible one: "Name-Realm", or nil.
function Arena.Name(s)
	if type(s) ~= "string" or s == "" or #s > 80 then return nil end
	local name = ns.Normal and ns.Normal(s) or s
	local K = ns.King
	local short = K and K.CleanName and K.CleanName(name)
	if not short then return nil end
	local realm = ns.RealmOf(name)
	if realm and (#realm > 40 or not realm:find("^[%w\128-\255]+$")) then return nil end
	return ns.FullName(short, realm)
end

-- A player's GUID as the arena writes it: "Player-<server>-<8 hex>" becomes "<server in base
-- 36>.<hex lower case>" (GuidOf turns it back). nil for anything else.
function Arena.GK(guid)
	if type(guid) ~= "string" then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	if not server or #server > 6 or #id < 6 or #id > 12 then return nil end
	return Arena.B36(tonumber(server)) .. "." .. id:lower()
end
function Arena.GuidOf(gk)
	if type(gk) ~= "string" then return nil end
	local server, id = gk:match("^([0-9a-z]+)%.(%x+)$")
	server = server and Arena.N(server, 1, 999999)
	if not server or #id < 6 or #id > 12 or id:find("[A-F]") then return nil end
	return ("Player-%d-%s"):format(server, id:upper())
end

-- The server's clock (every arena time is server time); tests and the sim may swap it.
function Arena.Now()
	if type(GetServerTime) == "function" then
		local ok, t = pcall(GetServerTime)
		if ok and type(t) == "number" then return t end
	end
	return ns.Now()
end

-- Two base-36 characters of a name (Comm's Hash36 style): the writer's mark in an id.
local function Hash36(text, len)
	local h1, h2 = 5381, 52711
	for i = 1, #text do
		local c = text:byte(i)
		h1 = (h1 * 33 + c) % 2147483647
		h2 = (h2 * 31 + c * 7) % 2147483647
	end
	local n, out = (h1 * 1000 + (h2 % 1000)) % 2147483647, {}
	for _ = 1, len or 2 do
		local d = n % 36
		out[#out + 1] = B36:sub(d + 1, d + 1)
		n = (n - d) / 36
	end
	return table.concat(out)
end
Arena.Hash36 = Hash36

-- A new object id: <letter><server second in base 36><a per-session counter in base 36><two
-- characters of the writer's name>. Two writers never collide (the mark), one writer never twice
-- (the counter). exists(id): an id already in the store is passed over.
local idCounter = 0
function Arena.NewId(letter, exists)
	if not Arena.ID_LETTERS[letter] then return nil end
	local mark = Hash36(tostring(ns.me or ""):lower(), 2)
	local sec = Arena.B36(Arena.Now())
	for _ = 1, 50 do
		idCounter = idCounter + 1
		local id = letter .. sec .. Arena.B36(idCounter) .. mark
		if not (type(exists) == "function" and exists(id)) then return id end
	end
	return nil
end

-- The realm an object belongs to: its server-stamped sender's (the design).
function Arena.RealmOf(sender)
	return ns.RealmOf(ns.FullName(sender)) or ns.realm
end

-- A name as the arena shows it: whole (the owner's call, 2026-09-30), cut short only where the
-- King's stream view asks for it: on the King's own screen while the council's names are hidden
-- there, and in the sim while its King view is on (Arena.SimKingsView, the companion's Kit.lua).
-- The author's preview of the King's view (King.Preview) shows names whole.
function Arena.Mask(name)
	if not ns.MaskName then return name end
	local masked
	if Arena.Sim and Arena.Sim() then
		masked = type(Arena.SimKingsView) == "function" and Arena.SimKingsView() == true
			and not (ns.CouncilNamesShown and ns.CouncilNamesShown())
	else
		masked = ns.King and type(ns.King.IsKing) == "function" and ns.King.IsKing() == true
			and ns.CouncilMasked and ns.CouncilMasked() == true
	end
	if masked then return ns.MaskName(name) end
	return name
end

local told = {}
local function SayOnce(key, text)
	if told[key] then return end
	told[key] = true
	ns.Print(text)
end

---------------------------------------------------------------------------
-- Switches: the test build, the kill switch, the sim, the rules' yes
---------------------------------------------------------------------------

-- The test build (scripts/package.sh --test N writes TestBuild.lua, never committed): its table
-- when it has the right shape, else nil. { n = 1-999, base = "x.y.z", built, expires (after built,
-- at most TEST_DAYS_MAX days later), commit, lane }.
function Arena.TestBuild()
	local t = rawget(ns, "TEST_BUILD")
	if type(t) ~= "table" then return nil end
	local n, built, expires = t.n, t.built, t.expires
	if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > 999 then return nil end
	if type(t.base) ~= "string" or not t.base:find("^%d+%.%d+%.%d+$") then return nil end
	if type(built) ~= "number" or type(expires) ~= "number" or expires <= built then return nil end
	if expires - built > Arena.TEST_DAYS_MAX * 86400 then return nil end
	if t.commit ~= nil and (type(t.commit) ~= "string" or #t.commit > 24 or not t.commit:find("^[%w%-]+$")) then return nil end
	return t
end

-- The Workshop's line, /oly status and /oly bug: which test build this is.
function Arena.TestBuildLine()
	local t = Arena.TestBuild()
	if not t then return nil end
	local function Day(s) return date and date("%m-%d", s) or tostring(s) end
	return L.ARENA_TEST_LINE:format(t.n, t.base, Day(t.built), Day(t.expires), tostring(t.lane or "group"), tostring(t.commit or "?"))
end

-- An expired test build turns the arena off for the session at login (the rest of Olympus goes
-- on); checked at login only, so a rehearsal is never cut in the middle.
local expired = false
function Arena.Expired() return expired end

-- The kill switch: no arena handler acts, nothing is sent or shown (a player's own obligations
-- still go out, the design). Refused while this character owes anything (Debts.Open).
function Arena.Off()
	return expired or (ns.db ~= nil and ns.db.arenaOff == true)
end
function Arena.SetOff(on)
	if not ns.db then return false, "db" end
	if on then
		local D = ns.Debts
		local open = type(D) == "table" and type(D.Open) == "function" and D.Open() or nil
		if type(open) == "table" and next(open) ~= nil then
			ns.Print(L.ARENA_OFF_REFUSED)
			return false, "obligations"
		end
		ns.db.arenaOff = true
		Arena.DropQueued("off")
		ns.Print(L.ARENA_OFF)
	else
		ns.db.arenaOff = nil
		ns.Print(expired and L.ARENA_TEST_EXPIRED or L.ARENA_ON)
	end
	Arena.Recompute() -- (the other packages' producers wait while it is off, and go on after)
	Arena.Changed()
	return true
end

-- The solo simulation: nothing is sent or saved while it runs; the stores are its own, in memory.
local sim -- { L = store, T = store, heavy = { L, T } } while running
function Arena.Sim() return sim ~= nil end
-- Who may run it: the author's Workshop (Workshop.Visible, which takes no sender) or a test build.
function Arena.MaySim()
	local W = ns.Workshop
	return Arena.TestBuild() ~= nil or (type(W) == "table" and type(W.Visible) == "function" and W.Visible() == true)
end
function Arena.SetSim(on)
	if on then
		if not Arena.MaySim() then ns.Print(L.ARENA_SIM_REFUSED) return false, "who" end
		if not sim then
			sim = { L = { v = 1 }, T = { v = 1 }, heavy = { L = { v = 1 }, T = { v = 1 } } }
			Arena.DropQueued("sim")
		end
	else
		sim = nil
	end
	Arena.Recompute()
	Arena.Changed()
	return true
end

-- The arena's rules, accepted once per account (ns.db.arenaRules = { v, yes, at }); the page
-- itself is the companion's (the screens). A new RULES_VERSION asks again.
function Arena.RulesAccepted()
	local r = ns.db and ns.db.arenaRules
	return type(r) == "table" and r.v == Arena.RULES_VERSION and r.yes == true
end
function Arena.SetRules(yes)
	if not ns.db then return false end
	ns.db.arenaRules = { v = Arena.RULES_VERSION, yes = yes == true, at = Arena.Now() }
	Arena.Changed()
	return true
end

---------------------------------------------------------------------------
-- The persistence gate (the design): the Forever beta writes saved variables but never
-- loads them back. The logout writes a sentinel; it came back from an earlier session only where
-- saved data survives. Anything that moves or owes gold is refused where it did not.
---------------------------------------------------------------------------

local persists = false
local function ReadSentinel()
	local db = ns.db
	local s = db and db.arenaSaved
	local n = type(s) == "table" and tonumber(s.n) or nil
	local sessions = db and tonumber(db.sessions) or nil
	persists = n ~= nil and sessions ~= nil and n < sessions
end
function Arena.Persists() return persists end
ns.On("INIT", ReadSentinel)
-- The one event an idle client registers (the weight rule's exemption): one table write.
ns.RegisterEvent("PLAYER_LOGOUT", function()
	if ns.db then ns.db.arenaSaved = { n = ns.db.sessions, at = Arena.Now() } end
end)

---------------------------------------------------------------------------
-- Lockdown (the design): chat messaging lockdown, or an instance. Arena messages wait here, never
-- handed to Comm, until a recheck clears it. A state word the design sends while blocked (a bank's
-- ZH "p", an arbiter's ZV "b": o.evenBlocked) still goes from an instance, never in chat lockdown,
-- where the game sends nothing.
---------------------------------------------------------------------------

function Arena.Lockdown()
	local C = C_ChatInfo
	if C and C.InChatMessagingLockdown then
		local ok, lock = pcall(C.InChatMessagingLockdown)
		if ok and lock == true then return true end
	end
	return false
end
function Arena.InInstance()
	if IsInInstance then
		local ok, inside = pcall(IsInInstance)
		if ok and inside == true then return true end
	end
	return false
end
function Arena.Blocked() return Arena.Lockdown() or Arena.InInstance() end
-- Whether this message waits now.
local function HeldBack(item)
	if Arena.Lockdown() then return true end
	return not item.evenBlocked and Arena.InInstance()
end

---------------------------------------------------------------------------
-- Modes and stores
---------------------------------------------------------------------------

local function Roles() return ns.ArenaRoles end

-- An object's mode: T on a test build, or when the object says T; else L.
function Arena.Mode(obj)
	if Arena.TestBuild() then return "T" end
	if obj == "T" or (type(obj) == "table" and obj.mode == "T") then return "T" end
	return "L"
end
-- A new object's mode: T when it is a rehearsal, on a test build, or while this realm's live switch
-- is off (the King's T1~O).
function Arena.NewMode(rehearsal)
	if rehearsal or Arena.TestBuild() then return "T" end
	local R = Roles()
	if not (R and R.Live and R.Live()) then return "T" end
	return "L"
end
-- Does it count (rankings, belts, history, debts, standing, the treasury, honours)? L outside the sim.
function Arena.Counts(mode) return mode == "L" and not Arena.Sim() end

-- The live store of a realm (ours by default): ns.rdb.arena.realms[realm], made on first use.
function Arena.RealmStore(realm)
	if sim then return sim.L end
	if type(ns.rdb) ~= "table" then return nil end
	local a = ns.rdb.arena
	if type(a) ~= "table" then a = {} ns.rdb.arena = a end
	if type(a.realms) ~= "table" then a.realms = {} end
	realm = realm or ns.realm or "?"
	local r = a.realms[realm]
	if type(r) ~= "table" then r = { v = 1 } a.realms[realm] = r end
	return r
end
-- Every read or write of arena state (the design): this realm's live store, the rehearsal
-- store, or the sim's memory store while it runs.
function Arena.Store(mode)
	if sim then return sim[mode == "T" and "T" or "L"] end
	if mode == "T" then
		if type(ns.rdb) ~= "table" then return nil end
		if type(ns.rdb.arenaTest) ~= "table" then ns.rdb.arenaTest = { v = 1 } end
		return ns.rdb.arenaTest
	end
	return Arena.RealmStore(ns.realm)
end

-- The bulky tables (the design "heavy"): the same keys in the companion's OlympusArenaDB, reached
-- only while the companion is loaded; nil until then (a handler that would store bulky data drops
-- it, and the companion catches up when it opens).
local heavy -- OlympusArenaDB, once the companion handed it over (AttachHeavy)
function Arena.AttachHeavy(db)
	if type(db) ~= "table" then return false end
	db.v = db.v or 1
	if type(db.stores) ~= "table" then db.stores = {} end
	heavy = db
	Arena.Changed()
	return true
end
function Arena.Heavy(mode)
	if sim then return sim.heavy[mode == "T" and "T" or "L"] end
	if not heavy then return nil end
	local key = tostring(ns.faction or "Alliance") .. ":" .. tostring(ns.group or ns.realm or "?")
	local s = heavy.stores[key]
	if type(s) ~= "table" then s = { realms = {}, test = { v = 1 } } heavy.stores[key] = s end
	if mode == "T" then
		if type(s.test) ~= "table" then s.test = { v = 1 } end
		return s.test
	end
	if type(s.realms) ~= "table" then s.realms = {} end
	local realm = ns.realm or "?"
	if type(s.realms[realm]) ~= "table" then s.realms[realm] = { v = 1 } end
	return s.realms[realm]
end

-- The lane of a rehearsal this client is in: "group" or "army" (ArenaTest.Running), else nil.
local function RehearsalLane()
	local T = ns.ArenaTest
	if type(T) ~= "table" or type(T.Running) ~= "function" then return nil end
	local ok, r = pcall(T.Running)
	if not ok or type(r) ~= "table" then return nil end
	return r.lane == "group" and "group" or (r.lane == "army" and "army" or nil)
end
local function GroupDist()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end
-- The lane of a public object (the design): CHANNEL in L and army rehearsals; RAID or PARTY in a
-- group rehearsal and always on a test build (nil there outside a group); WHISPER when public is
-- false (one-to-one traffic).
function Arena.Lane(mode, public)
	if public == false then return "WHISPER" end
	if Arena.TestBuild() then
		if mode ~= "T" then return nil end
		return GroupDist()
	end
	if mode == "T" and RehearsalLane() == "group" then return GroupDist() end
	return "CHANNEL"
end

---------------------------------------------------------------------------
-- Involvement and the one ticker (the design)
---------------------------------------------------------------------------

local involved = {}   -- [key] = true: what this client has live
local everies = {}    -- [key] = { every, next, fn }: run by the ticker, only while it runs
local afters = {}     -- [key] = { at, fn }: one-shot; each keeps the ticker going until it ran
local ticker          -- the C_Timer ticker while anything is involved
local Tick            -- (below)
local work            -- fn() -> true while internal work waits (below)

local function Recompute()
	local busy = next(involved) ~= nil or next(afters) ~= nil or (work and work())
	if busy and not ticker then
		if C_Timer and C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(Arena.TICK, function() ns.SafeCall("arena tick", Tick) end)
			if ticker == nil then ticker = false end
		end
	elseif not busy and ticker then
		if ticker.Cancel then ticker:Cancel() end
		ticker = nil
	end
end
Arena.Recompute = Recompute
function Arena.Ticking() return ticker ~= nil and ticker ~= false end

-- Marks (on) or clears what this client has live, by key: "bank", "arbiter", "fight:<fid>",
-- "table:<id>", "tickets", "rehearsal", "window"...
function Arena.Involve(key, on)
	if type(key) ~= "string" then return end
	involved[key] = on and true or nil
	Recompute()
end
function Arena.Involved()
	local out = {}
	for k in pairs(involved) do out[#out + 1] = k end
	table.sort(out)
	return out
end
-- fn every `sec` seconds while the ticker runs (while anything is involved); fn nil removes it.
function Arena.Every(sec, key, fn)
	if type(key) ~= "string" then return end
	if type(fn) ~= "function" then everies[key] = nil return end
	sec = math.max(Arena.TICK, tonumber(sec) or 60)
	everies[key] = { every = sec, next = Arena.Now() + sec, fn = fn }
end
-- fn once, `sec` seconds from now (the ticker runs until it did); a new one under the same key
-- replaces it; fn nil cancels.
function Arena.After(sec, key, fn)
	if type(key) ~= "string" then return end
	if type(fn) ~= "function" then afters[key] = nil Recompute() return end
	afters[key] = { at = Arena.Now() + math.max(0, tonumber(sec) or 0), fn = fn }
	Recompute()
end

-- ARENA_CHANGED for the screens, at most once a second.
local lastChanged, changedDue = -math.huge, false
function Arena.Changed()
	local now = Arena.Now()
	if now - lastChanged >= Arena.CHANGED_GAP then
		lastChanged = now
		ns.Fire("ARENA_CHANGED")
		return
	end
	if changedDue then return end
	changedDue = true
	Arena.After(Arena.CHANGED_GAP, "~changed", function()
		changedDue = false
		lastChanged = Arena.Now()
		ns.Fire("ARENA_CHANGED")
	end)
end

-- A bank on duty never reports the census (Comm.BankOnDuty reads this; the hello's "b" flag).
local duty = {}
function Arena.OnDuty(role) return duty[role] == true end
function Arena.SetDuty(role, on)
	if type(role) ~= "string" then return end
	local was = duty[role] == true
	duty[role] = on and true or nil
	Arena.Involve("duty:" .. role, on)
	if role == "bank" and was ~= (on == true) and ns.Comm and ns.Comm.Hello then ns.SafeCall("arena hello", ns.Comm.Hello, true) end
	Arena.Changed()
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local backlog = {}     -- items held: lockdown, or over the urgent share
local retries = {}     -- { at, item }: must-deliver items (or one piece of theirs) waiting to be offered again
local lowq = {}        -- the low lane: items (and pieces) sent while Comm's queue has room
local producers, order, rr = {}, {}, 0 -- Arena.Later's producers, their round robin
local sticky           -- the producer whose payload is going out: its turn lasts until its last piece
local keyed = {}       -- [key] = the newest version of a long keyed payload not started yet
local keyedCur = {}    -- [key] = { item, pieces }: the version of it whose pieces are going out
local urgentOut = 0    -- arena items urgent in Comm's queue now
local inflight = {}    -- [Comm key] = record of the keyed item Comm holds (its done may be replaced)
local outbox = {}      -- [target, lower case] = { list = { item, ... }, busy = item }
local gone = {}        -- [target, lower case] = when the server said it was not found
local parked = {}      -- [target, lower case] = { list, tries, next }: must-deliver whispers to a target offline
local pid = math.random and math.random(0, 36 ^ 3) or 0 -- this sender's piece ids (base 36)
local seq = 0          -- the order messages were sent in (a parked one keeps its place)

local function TargetKey(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or "" end

function Arena.UrgentOut() return urgentOut end
function Arena.BacklogSize() return #backlog end
function Arena.LowSize() return #lowq end
function Arena.RetrySize() return #retries end
function Arena.ProducerCount() return #order end
-- Must-deliver whispers waiting for their target to come back (to one target, or in all).
function Arena.ParkedSize(target)
	if target then
		local p = parked[TargetKey(target)]
		return p and #p.list or 0
	end
	local n = 0
	for _, p in pairs(parked) do n = n + #p.list end
	return n
end
-- The producers wait while the arena is off here or the sim runs: none is dropped (each is its
-- package's, the clerk's carousel or a bank's entries), they go on after.
local function Paused() return Arena.Off() or Arena.Sim() end
work = function()
	return backlog[1] ~= nil or retries[1] ~= nil or lowq[1] ~= nil or (order[1] ~= nil and not Paused()) or next(outbox) ~= nil
		or next(parked) ~= nil
end

-- The sender's done, once for a message (a piece's goes to its payload, below).
local function Done(item, sent, why)
	if not item.parent then
		if item.doneCalled then return end
		item.doneCalled = true
	end
	if item.onDone then ns.SafeCall("arena send done", item.onDone, sent, why) end
end

-- The compliance gate (Compliance.lua) on the wire: a type that carries nothing but a wager goes
-- out and comes in only where it allows one (1.1.6: nowhere). Without the gate, no arena type.
local function Compliant(kind)
	local C = ns.Compliance
	return type(C) == "table" and type(C.Wire) == "function" and C.Wire(kind) == true
end

-- Why an item may not go out now, or nil (the design): the compliance gate, the sim, the kill switch
-- (a player's own obligations excepted), a test build's L or channel, L while this realm's live
-- switch is off, outside an Olympus guild.
local function Refusal(kind, mode, o)
	if not Arena.TYPES[kind] then return "type" end
	if mode ~= "L" and mode ~= "T" then return "mode" end
	if not Compliant(kind) then return "compliance" end
	if Arena.Sim() then return "sim" end
	if ns.IsMember and not ns.IsMember() then return "guild" end
	local obligation = Arena.OBLIGATIONS[kind] or o.obligation == true
	if Arena.Off() and not obligation then return "off" end
	if Arena.TestBuild() then
		if mode == "L" then return "test-live" end
		if o.dist == "CHANNEL" or o.dist == "GUILD" then return "test-channel" end
	end
	if mode == "L" and not obligation and not Arena.LIVE_EXEMPT[kind] then
		local R = Roles()
		if not (R and R.Live and R.Live()) then return "live-off" end
	end
	if o.dist == "GUILD" and not Arena.GUILD_TYPES[kind] then return "guild-lane" end
	return nil
end
Arena.Refusal = function(kind, mode, o) return Refusal(kind, mode, o or {}) end

local Offer, Settled, PumpBox, Queue, SendPieces, MakePieces -- (below)

local function Hold(item)
	-- (Full: as if Comm had dropped it; a must-deliver one comes back later, Settled.)
	if #backlog >= Arena.BACKLOG_MAX then return Settled(item, false, "backlog") end
	backlog[#backlog + 1] = item
	stats.held = stats.held + 1
	Arena.WatchLockdown()
	Recompute()
end

-- A must-deliver item offered again later (2, 4, 8 ... 60 s), up to RETRIES_MAX tries. The game's
-- throttles (3, 8), its general error (9), the lockdown (11), Comm's full queue, a call that
-- raised, and this file's full backlog.
local RETRYABLE = { [3] = true, [8] = true, [9] = true, [11] = true, dropped = true, error = true, backlog = true }
local function Retry(item, why)
	item.tries = (item.tries or 0) + 1
	if item.tries > Arena.RETRIES_MAX then
		Count(stats.dropped, "retries")
		return Done(item, false, why)
	end
	local wait = Arena.BACKOFF[math.min(item.tries, #Arena.BACKOFF)]
	retries[#retries + 1] = { at = Arena.Now() + wait, item = item }
	stats.retried = stats.retried + 1
	Recompute()
end

-- A must-deliver whisper to a target the server says is offline (result 12, or its not-found
-- line): kept, in the order it was sent, until the target is heard again (any arena message from
-- it), a whisper to it leaves, or a probe (one whisper, PARK_PROBE apart) gets through; given up
-- after PARK_TRIES probes. Ordinary whispers to it are dropped instead (DropTarget).
local function Park(item)
	local key = TargetKey(item.target)
	local p = parked[key]
	if not p then
		p = { list = {}, tries = 0, next = Arena.Now() + Arena.PARK_PROBE[1] }
		parked[key] = p
	end
	local at = #p.list + 1
	for i, w in ipairs(p.list) do
		if (w.seq or 0) > (item.seq or 0) then at = i break end
	end
	table.insert(p.list, at, item)
	stats.parked = stats.parked + 1
	Recompute()
end
-- The target is back: its parked whispers go first, in their order. probe: only the first (the
-- others wait for it to get through; the entry keeps its tries).
local function Unpark(key, probe)
	local p = parked[key]
	if not p then return end
	local list
	if probe then
		local first = table.remove(p.list, 1)
		if not first then parked[key] = nil return end
		list = { first }
	else
		list = p.list
		parked[key] = nil
	end
	gone[key] = nil
	local box = outbox[key]
	if not box then box = { list = {} } outbox[key] = box end
	-- (A long one again in new pieces, in its place.)
	local out = {}
	for _, item in ipairs(list) do
		if #item.text > 255 then
			local pieces = MakePieces(item)
			if pieces then
				for _, piece in ipairs(pieces) do out[#out + 1] = piece end
			else
				Done(item, false, "long")
			end
		else
			out[#out + 1] = item
		end
	end
	for i = #out, 1, -1 do table.insert(box.list, 1, out[i]) end
	PumpBox(key)
	Recompute()
end
-- Heard from someone (Arena.Handle): a target that answers is online again.
local function Heard(sender)
	if next(parked) == nil and next(gone) == nil then return end
	local key = TargetKey(sender)
	gone[key] = nil
	if parked[key] then Unpark(key) end
end

-- The server said the target is offline or not found: its ordinary whispers still waiting are
-- dropped, the must-deliver ones parked.
local function DropTarget(key, why)
	local now = Arena.Now()
	for k, t in pairs(gone) do
		if now - t >= Arena.GONE_FOR then gone[k] = nil end
	end
	gone[key] = now
	local box = outbox[key]
	if not box then return end
	local list = box.list
	box.list = {}
	if not box.busy then outbox[key] = nil end
	for _, item in ipairs(list) do
		if item.must then
			Park(item)
		else
			Count(stats.dropped, "offline")
			Done(item, false, why)
		end
	end
end

Settled = function(item, sent, why)
	if sent then
		stats.sent = stats.sent + 1
		if item.target then
			-- A whisper that left: its target is online (what waited for it follows).
			local key = TargetKey(item.target)
			gone[key] = nil
			if parked[key] then Unpark(key) end
		end
		return Done(item, true)
	end
	-- (A piece's failure is its payload's to count, PieceDone.)
	if why == 12 and item.target then
		DropTarget(TargetKey(item.target), 12)
		if item.must then return Park(item) end
		if not item.parent then Count(stats.dropped, "offline") end
		return Done(item, false, 12)
	end
	if item.must and RETRYABLE[why] then return Retry(item, why) end
	if not item.parent then Count(stats.dropped, tostring(why)) end
	return Done(item, false, why)
end

-- The key Comm dedupes an item by (never a whisper's: the outbox keeps one per target at a time).
local function CommKey(item)
	if item.dist == "WHISPER" or item.chat then return nil end
	return item.key
end

-- Handed to Comm, with a done that keeps the urgent share and the retries. after() runs whatever
-- came of it (the outbox's next whisper).
local function Hand(item, after)
	local C = ns.Comm
	local key = CommKey(item)
	local rec = { item = item }
	local was = key and inflight[key]
	if was and not was.fired and not was.over then
		-- Comm replaces the waiting message of that key, and its done, in the same place: its
		-- share of the urgent ones is the same; the older one is told it was replaced.
		was.over = true
		rec.counted, was.counted = was.counted, false
		Done(was.item, false, "replaced")
	elseif item.urgent then
		urgentOut = urgentOut + 1
		rec.counted = true
	end
	if key then inflight[key] = rec end
	local function done(sent, why)
		if rec.fired then return end
		rec.fired = true
		if rec.counted then urgentOut = math.max(0, urgentOut - 1) rec.counted = false end
		if key and inflight[key] == rec then inflight[key] = nil end
		if not rec.over then Settled(item, sent, why) end
		if after then after() end
		Recompute()
	end
	if item.chat and item.dist == "CHANNEL" and C.SendChat then
		if not C.SendChat(item.text, done) then done(false, "chat") end
	elseif item.dist == "WHISPER" then
		C.Whisper(item.target, item.text, nil, item.urgent, item.logged, done)
	else
		C.Send(item.dist, item.text, key, item.urgent, item.logged, done)
	end
end

-- A fight-room line typed while blocked is dropped at once, never sent late (Comm's chat lane
-- drops its own after CHAT_TTL; this file keeps no age).
local function DropChat(item)
	Count(stats.dropped, "lockdown")
	return Done(item, false, "lockdown")
end

-- Whispers go one at a time per target (the design): the next leaves when Comm says the last one did.
PumpBox = function(key)
	local box = outbox[key]
	if not box or box.busy then return end
	local item = table.remove(box.list, 1)
	if not item then outbox[key] = nil return end
	if HeldBack(item) then
		if item.chat then
			DropChat(item)
			return PumpBox(key)
		end
		table.insert(box.list, 1, item)
		Arena.WatchLockdown()
		Recompute()
		return
	end
	if item.urgent and urgentOut >= Arena.URGENT_SHARE then
		table.insert(box.list, 1, item)
		Recompute()
		return
	end
	box.busy = item
	Hand(item, function()
		box.busy = nil
		PumpBox(key)
	end)
end
local function PumpBoxes()
	local keys = {}
	for key in pairs(outbox) do keys[#keys + 1] = key end
	for _, key in ipairs(keys) do PumpBox(key) end
end
local function ToOutbox(item)
	local key = TargetKey(item.target)
	-- (Behind the ones parked for that target: they were sent first.)
	if item.must and parked[key] then return Park(item) end
	local lost = gone[key]
	if lost and Arena.Now() - lost < Arena.GONE_FOR then
		if item.must then return Park(item) end
		Count(stats.dropped, "offline")
		Done(item, false, 12)
		return
	end
	gone[key] = nil
	local box = outbox[key]
	if not box then box = { list = {} } outbox[key] = box end
	if item.key then
		for i, w in ipairs(box.list) do
			if w.key == item.key then
				box.list[i] = item
				Done(w, false, "replaced")
				return
			end
		end
	end
	box.list[#box.list + 1] = item
	Arena.WatchNotFound()
	PumpBox(key)
end
function Arena.OutboxSize(target)
	local box = outbox[TargetKey(target)]
	if not box then return 0 end
	return #box.list + (box.busy and 1 or 0)
end

-- A piece of a payload no longer going out (its payload was given up, or went again whole).
local function Stale(item)
	local att = item.parent and item.att
	return att ~= nil and (att.over or item.parent.att ~= att)
end

Offer = function(item)
	if Stale(item) then return end
	-- (A whole payload again, after a retry: new pieces.)
	if #item.text > 255 then return SendPieces(item) end
	if HeldBack(item) then
		if item.chat then return DropChat(item) end
		return Hold(item)
	end
	if item.dist == "WHISPER" then return ToOutbox(item) end
	local key = CommKey(item)
	local replacing = key and inflight[key] and not inflight[key].fired and not inflight[key].over
	if item.urgent and urgentOut >= Arena.URGENT_SHARE and not replacing then return Hold(item) end
	Hand(item)
end

-- A payload over 255 bytes in EP pieces under a new piece id (the design): the list of piece items,
-- each queued as its payload would be (its lane, its urgency, the lockdown), or nil when too long.
-- Receivers keep a payload's pieces PIECE_TTL from the first one. A piece the game refused is
-- offered again alone, under the same piece id, while the whole can still arrive within that
-- time (PIECE_TTL less PIECE_SLACK, counting Comm's queue at Arena.PACE); after that the whole
-- payload goes again under a new piece id (must-deliver), or is given up. Its done once its last
-- piece left.
local PieceDone -- (below)
MakePieces = function(item)
	local text, n = item.text, math.ceil(#item.text / Arena.PIECE)
	if n > Arena.PIECES_MAX then return nil end
	pid = (pid + 1) % (36 ^ 4)
	local id = Arena.B36(pid)
	local att = { left = n, at = Arena.Now() }
	item.att = att
	local out = {}
	for i = 1, n do
		local chunk = text:sub((i - 1) * Arena.PIECE + 1, i * Arena.PIECE)
		local p = { kind = "EP", mode = item.mode, dist = item.dist, target = item.target, urgent = item.urgent, logged = item.logged,
			low = item.low, obligation = item.obligation, evenBlocked = item.evenBlocked, parent = item, att = att, seq = item.seq,
			text = ("EP~%s%d~%s~%s~%s~%s"):format(item.mode, Arena.PROTO, id, Arena.B36(i), Arena.B36(n), chunk) }
		p.onDone = function(sent, why) PieceDone(p, sent, why) end
		out[i] = p
	end
	stats.pieces = stats.pieces + n
	return out
end
SendPieces = function(item)
	local pieces = MakePieces(item)
	if not pieces then
		Count(stats.dropped, "long")
		return Done(item, false, "long")
	end
	for _, p in ipairs(pieces) do Queue(p) end
end

local function QueueSize()
	local C = ns.Comm
	return C and C.QueueSize and C.QueueSize() or 0
end

PieceDone = function(p, sent, why)
	local item, att = p.parent, p.att
	if item.att ~= att or att.over then return end
	if sent then
		att.left = att.left - 1
		if att.left == 0 then
			att.over, item.att = true, nil
			Done(item, true)
		end
		return
	end
	if item.must and item.target and (why == 12 or why == "notfound") then
		att.over = true
		return Park(item)
	end
	if item.must and RETRYABLE[why] then
		p.tries = (p.tries or 0) + 1
		local wait = Arena.BACKOFF[math.min(p.tries, #Arena.BACKOFF)]
		-- (When it would arrive: behind Comm's queue, and on the low lane behind the pieces not handed yet.)
		local arrives = Arena.Now() + wait + (QueueSize() + (item.low and att.left or 0)) * Arena.PACE
		if arrives - att.at <= Arena.PIECE_TTL - Arena.PIECE_SLACK then
			retries[#retries + 1] = { at = Arena.Now() + wait, item = p }
			stats.retried = stats.retried + 1
			Recompute()
			return
		end
		att.over = true
		return Retry(item, why)
	end
	att.over = true
	Count(stats.dropped, tostring(why))
	Done(item, false, why)
end

Queue = function(item)
	if item.low then
		if #lowq >= Arena.LOW_MAX then
			Count(stats.dropped, "low")
			return Done(item, false, "low")
		end
		lowq[#lowq + 1] = item
		Recompute()
		return
	end
	Offer(item)
end

-- A long keyed payload (a market's sheet, its pools, a tournament): the newest version waits
-- under its key; a producer rebuilds its pieces when its turn comes, unkeyed, under a new piece id
-- (Comm would let each piece overwrite the one before, the design). A version in flight finishes
-- (its producer keeps the turn until its last piece, so receivers put one together at a time);
-- the next turn takes the newest.
local function KeyedProducer(key)
	return function()
		local cur = keyedCur[key]
		if not cur or not cur.pieces[1] then
			keyedCur[key] = nil
			local item = keyed[key]
			if not item then return nil end
			keyed[key] = nil
			local pieces = MakePieces(item)
			if not pieces then
				Done(item, false, "long")
				return nil
			end
			cur = { item = item, pieces = pieces }
			keyedCur[key] = cur
		end
		local p = table.remove(cur.pieces, 1)
		return p, cur.pieces[1] ~= nil
	end
end

-- Arena.Send(kind, mode, body, o): builds kind~<mode>1~body and sends it (the design).
--   o.to       a whisper to this character (else the public lane: o.dist, or Arena.Lane)
--   o.dist     "CHANNEL", "RAID", "PARTY" (or "GUILD" for ID alone)
--   o.key      Comm's dedupe key (a newer message replaces the one waiting, whose done says "replaced")
--   o.urgent   ahead of what waits (8 arena items at most: the rest wait here)
--   o.logged   the logged API (a player's own words)
--   o.low      the low lane: only while Comm's queue has room (Arena.ROOM)
--   o.must     re-offered when Comm could not send it (2, 4 ... 60 s); a whisper to a target
--              offline waits for it (parked) instead of being dropped
--   o.chat     a chat line on the channel's chat lane (Comm.SendChat: EC); dropped, never sent
--              late, while blocked
--   o.obligation  a player's own obligation (ZX about himself, a signed AW): sent even while off
--   o.evenBlocked a state word that goes from an instance too (a bank's ZH "p", an arbiter's ZV
--              "b"); never in chat lockdown
--   o.done     fn(sent, why) once it left, or was given up
-- Returns true when taken (sent, queued or held), else false and why (done is not called then):
-- a refusal (Refusal), "held" (net-off: Moderation.BLOCKED, the whole payload before any piece),
-- "group" (a test build outside a group), "long".
function Arena.Send(kind, mode, body, o)
	o = o or {}
	local why = Refusal(kind, mode, o)
	if why then
		Count(stats.refused, why)
		ns.Log("arena %s not sent: %s", tostring(kind), why)
		return false, why
	end
	local dist, target = o.dist, nil
	if type(o.to) == "string" and o.to ~= "" then
		dist, target = "WHISPER", ns.FullName(o.to)
	elseif not dist then
		dist = Arena.Lane(mode, true)
	end
	if not dist then
		Count(stats.refused, "group")
		SayOnce("group", L.ARENA_TEST_NO_GROUP)
		return false, "group"
	end
	if Arena.TestBuild() and (dist == "CHANNEL" or dist == "GUILD") then
		Count(stats.refused, "test-channel")
		return false, "test-channel"
	end
	local text = ("%s~%s%d~%s"):format(kind, mode, Arena.PROTO, tostring(body or ""))
	-- A net-off client sends none of what the moderators hide (Moderation.BLOCKED): checked here on
	-- the whole message, long or not (its EP pieces carry no type Comm's own check knows).
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Blocks) == "function" and M.Blocks(text) == true then
		Count(stats.refused, "held")
		ns.Log("arena %s not sent: held (net-off)", tostring(kind))
		return false, "held"
	end
	if #text > 255 and o.chat then Count(stats.refused, "long") return false, "long" end
	if math.ceil(#text / Arena.PIECE) > Arena.PIECES_MAX then
		Count(stats.refused, "long")
		ns.Log("arena %s not sent: %d bytes", kind, #text)
		return false, "long"
	end
	seq = seq + 1
	local item = { kind = kind, mode = mode, text = text, dist = dist, target = target, key = o.key, urgent = o.urgent and true or nil,
		logged = o.logged and true or nil, must = o.must and true or nil, low = o.low and true or nil, chat = o.chat and true or nil,
		obligation = (Arena.OBLIGATIONS[kind] or o.obligation == true) or nil, evenBlocked = o.evenBlocked and true or nil, seq = seq,
		onDone = type(o.done) == "function" and o.done or nil }
	-- (A newer version replaces a long one of that key still waiting to start, long or not.)
	local waiting = item.key and keyed[item.key]
	if waiting then
		keyed[item.key] = nil
		Done(waiting, false, "replaced")
	end
	if #text <= 255 then
		Queue(item)
		return true
	end
	if item.key and not item.urgent then
		keyed[item.key] = item
		if not producers["~k:" .. item.key] then Arena.Later("~k:" .. item.key, KeyedProducer(item.key)) end
		return true
	end
	SendPieces(item)
	return true
end

-- The low lane (the design): producer() returns its next message (kind, mode, body, o, or a table
-- { kind, mode, body, o }), or nil when it has none (it is then dropped). One message leaves per
-- tick while Comm's queue holds Arena.ROOM or fewer, round robin between producers. A producer
-- may also return a ready piece item and whether more of that payload follow (the keyed payloads
-- above): it keeps the turn until the last. Producers wait while the arena is off or the sim runs.
function Arena.Later(key, producer)
	if type(key) ~= "string" then return end
	if type(producer) ~= "function" then
		if producers[key] then
			producers[key] = nil
			for i, k in ipairs(order) do if k == key then table.remove(order, i) break end end
		end
		if sticky == key then sticky = nil end
		Recompute()
		return
	end
	if not producers[key] then order[#order + 1] = key end
	producers[key] = producer
	Recompute()
end

-- One producer's turn: true when it put something on the low lane; removed (second value) when
-- it had nothing (or failed).
local function Produce(key)
	local ok, a, b, c, d = pcall(producers[key])
	if ok and type(a) == "table" and a.text then
		lowq[#lowq + 1] = a
		sticky = b == true and key or nil
		return true
	elseif ok and type(a) == "table" then
		a, b, c, d = a[1], a[2], a[3], a[4]
	end
	if ok and type(a) == "string" then
		local o = type(d) == "table" and d or {}
		o.low = true
		Arena.Send(a, b, c, o)
		return lowq[1] ~= nil
	end
	if not ok or a == nil then
		if not ok then ns.Log("arena producer %s failed: %s", tostring(key), tostring(a)) end
		Arena.Later(key, nil)
		return false, true
	end
	return false
end

local function LowTick()
	if QueueSize() > Arena.ROOM then return end
	if not lowq[1] and not Paused() then
		if sticky and producers[sticky] then
			Produce(sticky)
		else
			sticky = nil
			-- The next producer with something to send.
			for _ = 1, #order do
				rr = rr % #order + 1
				local sent, removed = Produce(order[rr])
				if sent then break end
				if removed then
					rr = rr - 1
					if not order[1] then break end
				end
			end
		end
	end
	local item = table.remove(lowq, 1)
	if item then Offer(item) end
end

-- Held messages go on once the lockdown is over (in order, within the urgent share); from an
-- instance, only the ones sent even there.
function Arena.Flush()
	if not backlog[1] or Arena.Lockdown() then return end
	local list = backlog
	backlog = {}
	for _, item in ipairs(list) do
		if HeldBack(item) or (item.urgent and urgentOut >= Arena.URGENT_SHARE and item.dist ~= "WHISPER") then
			backlog[#backlog + 1] = item
		else
			Offer(item)
		end
	end
	PumpBoxes()
	Recompute()
end

-- Everything waiting is dropped (the kill switch: why "off", the sim: "sim"), but a player's own
-- obligations (and their pieces); each dropped message's done says why. The other packages'
-- producers stay (they wait while the arena is off or the sim runs); the long keyed payloads
-- waiting to go out are this file's own, and go.
function Arena.DropQueued(why)
	why = why or "off"
	local function Keep(item) return item.obligation == true end
	local function Filter(list)
		local kept = {}
		for _, item in ipairs(list) do
			if Keep(item) then kept[#kept + 1] = item else Done(item, false, why) end
		end
		return kept
	end
	backlog, lowq = Filter(backlog), Filter(lowq)
	local kept = {}
	for _, r in ipairs(retries) do
		if Keep(r.item) then kept[#kept + 1] = r else Done(r.item, false, why) end
	end
	retries = kept
	for _, box in pairs(outbox) do box.list = Filter(box.list) end
	for key, p in pairs(parked) do
		p.list = Filter(p.list)
		if not p.list[1] then parked[key] = nil end
	end
	for key, item in pairs(keyed) do
		if not Keep(item) then
			keyed[key] = nil
			Done(item, false, why)
		end
	end
	for key, cur in pairs(keyedCur) do
		if not Keep(cur.item) then
			keyedCur[key] = nil
			if cur.item.att then cur.item.att.over = true end
			Done(cur.item, false, why)
		end
	end
	for key in pairs(producers) do
		local k = key:match("^~k:(.+)$")
		if k and not keyed[k] and not keyedCur[k] then Arena.Later(key, nil) end
	end
	Recompute()
end

-- The events a waiting message needs, registered the first time one waits (the weight rule).
local watchingLockdown, watchingNotFound = false, false
function Arena.WatchLockdown()
	if watchingLockdown then return end
	watchingLockdown = true
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(ns.RegisterEvent, event, function()
			if backlog[1] then ns.SafeCall("arena flush", Arena.Flush) end
		end)
	end
end
local notFound
-- The server's "No player named ... is currently playing" (ERR_CHAT_PLAYER_NOT_FOUND_S, as
-- Treasury.NotFound reads it): that target's arena whispers still waiting are dropped (the
-- must-deliver ones parked).
function Arena.NotFound(text)
	if type(text) ~= "string" or next(outbox) == nil then return end
	if issecretvalue and issecretvalue(text) then return end
	if not notFound then
		local f = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S or nil
		if not f then return end
		notFound = "^" .. (f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)")) .. "$"
	end
	local who = text:match(notFound)
	if not who then return end
	who = who:lower()
	local keys = {}
	for key, box in pairs(outbox) do
		local target = (box.busy and box.busy.target) or (box.list[1] and box.list[1].target) or key
		if (ns.TellName(target) or ""):lower() == who or (ns.DisplayName(target) or ""):lower() == who or key == who then
			keys[#keys + 1] = key
		end
	end
	for _, key in ipairs(keys) do DropTarget(key, "notfound") end
end
function Arena.WatchNotFound()
	if watchingNotFound then return end
	watchingNotFound = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("arena not found", Arena.NotFound, text) end)
end

-- The ticker's share of the sending: retries due, the parked whispers' probes.
local function SendTick(now)
	if retries[1] then
		local due, kept = {}, {}
		for _, r in ipairs(retries) do
			if r.at <= now then due[#due + 1] = r.item else kept[#kept + 1] = r end
		end
		retries = kept
		for _, item in ipairs(due) do Offer(item) end
	end
	if next(parked) then
		local probes = {}
		for key, p in pairs(parked) do if p.next <= now then probes[#probes + 1] = key end end
		table.sort(probes)
		for _, key in ipairs(probes) do
			local p = parked[key]
			if p then
				p.tries = p.tries + 1
				if p.tries > Arena.PARK_TRIES then
					parked[key] = nil
					for _, item in ipairs(p.list) do
						Count(stats.dropped, "parked")
						Done(item, false, 12)
					end
				else
					p.next = now + Arena.PARK_PROBE[math.min(p.tries + 1, #Arena.PARK_PROBE)]
					Unpark(key, true)
				end
			end
		end
	end
	if backlog[1] then Arena.Flush() end
	PumpBoxes()
	if lowq[1] or order[1] then LowTick() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local wrappers = {}   -- [type] = the wrapper Arena.Handle returned
local injecting = false

-- Which lanes take which mode (the design): a test build takes T on RAID, PARTY or WHISPER alone; a
-- release takes L on CHANNEL and WHISPER (and ID on GUILD), and T on any lane but GUILD.
local function Accepts(kind, mode, dist)
	if dist == "GUILD" then return mode == "L" and Arena.GUILD_TYPES[kind] == true and not Arena.TestBuild() end
	if Arena.TestBuild() then
		return mode == "T" and (dist == "RAID" or dist == "PARTY" or dist == "WHISPER")
	end
	if mode == "L" then return dist == "CHANNEL" or dist == "WHISPER" end
	return dist == "CHANNEL" or dist == "RAID" or dist == "PARTY" or dist == "WHISPER"
end

-- The wrapper each file registers with a literal: ns.Comm.Handle("AF", ns.Arena.Handle("AF", OnFight)).
-- fn(dist, sender, mode, body) runs only after the envelope, the mode and the lane were checked.
function Arena.Handle(kind, fn)
	local function wrapper(dist, sender, text)
		if type(text) ~= "string" or type(sender) ~= "string" then return end
		local k, mode, proto, body = text:match("^(%w%w)~([^~]?)(%d*)~(.*)$")
		if k ~= kind then Count(stats.dropped, "envelope") return end
		-- (Whatever comes of it: the sender is online, and what waits for him goes.)
		Heard(sender)
		if mode ~= "L" and mode ~= "T" then Count(stats.dropped, "mode") return end
		if proto ~= tostring(Arena.PROTO) then Count(stats.dropped, "proto") return end
		-- (A wager's type from anyone, a modified client's too: never taken while the gate says no.)
		if not Compliant(kind) then Count(stats.dropped, "compliance") return end
		if Arena.Off() then Count(stats.dropped, "off") return end
		if Arena.Sim() and not injecting then Count(stats.dropped, "sim") return end
		if not Accepts(kind, mode, dist) then Count(stats.dropped, Arena.TestBuild() and "live-in-test" or "lane") return end
		-- (L while this realm's live switch is off: refused here as Refusal refuses it going out, a
		-- modified client's too. The switch itself is the King's T1, not an arena type.)
		if mode == "L" and not (Arena.OBLIGATIONS[kind] or Arena.LIVE_EXEMPT[kind] or Arena.MAY_OBLIGE[kind]) then
			local R = Roles()
			if not (R and R.Live and R.Live()) then Count(stats.dropped, "live-off") return end
		end
		ns.SafeCall("arena " .. kind, fn, dist, sender, mode, body)
	end
	wrappers[kind] = wrapper
	return wrapper
end
function Arena.Handles(kind) return wrappers[kind] ~= nil end

-- A message handed to our own handlers (the sim, tests), as if heard from sender on dist.
function Arena.Inject(dist, sender, text)
	local w = type(text) == "string" and wrappers[text:sub(1, 2)]
	if not w then return false end
	local was = injecting
	injecting = true
	local ok, err = pcall(w, dist, sender, text)
	injecting = was
	if not ok then error(err, 0) end
	return true
end

-- EP pieces, put together per (sender, piece id) with their own counters (the design): 4 open per
-- sender, 64 in all, 60 s to finish. A whole payload must start with a registered arena type in
-- the same mode; it goes to that type's handler with the pieces' dist.
local asm, openCount = {}, 0
local function Gc(now)
	for sender, list in pairs(asm) do
		for id, e in pairs(list) do
			if now - e.t > Arena.PIECE_TTL then
				list[id] = nil
				openCount = openCount - 1
				Count(stats.dropped, "pieces-late")
			end
		end
		if next(list) == nil then asm[sender] = nil end
	end
end
function Arena.OpenPieces(sender)
	if sender then
		local n = 0
		for _ in pairs(asm[sender] or {}) do n = n + 1 end
		return n
	end
	return openCount
end
local function OnPiece(dist, sender, mode, body)
	local id, i, n, chunk = body:match("^([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~(.+)$")
	i, n = Arena.N(i, 1, Arena.PIECES_MAX), Arena.N(n, 1, Arena.PIECES_MAX)
	if not id or #id > 6 or not i or not n or i > n or #chunk > Arena.PIECE then Count(stats.dropped, "piece") return end
	local now = Arena.Now()
	Gc(now)
	local list = asm[sender]
	local e = list and list[id]
	if not e then
		local mine = 0
		for _ in pairs(list or {}) do mine = mine + 1 end
		if mine >= Arena.OPEN_PER_SENDER or openCount >= Arena.OPEN_MAX then Count(stats.dropped, "pieces-open") return end
		if not list then list = {} asm[sender] = list end
		e = { n = n, mode = mode, parts = {}, got = 0, t = now }
		list[id] = e
		openCount = openCount + 1
	end
	if e.n ~= n or e.mode ~= mode then Count(stats.dropped, "piece") return end
	if not e.parts[i] then
		e.parts[i] = chunk
		e.got = e.got + 1
	end
	if e.got < n then return end
	list[id] = nil
	openCount = openCount - 1
	if next(list) == nil then asm[sender] = nil end
	local whole = table.concat(e.parts, "", 1, n)
	local kind = whole:sub(1, 2)
	local w = wrappers[kind]
	if kind == "EP" or not w or whole:match("^%w%w~([LT])%d") ~= mode then Count(stats.dropped, "inner") return end
	stats.assembled = stats.assembled + 1
	w(dist, sender, whole)
end
ns.Comm.Handle("EP", Arena.Handle("EP", OnPiece))

---------------------------------------------------------------------------
-- The signature queue (the design): one claim per sender and session, deduplicated, failures
-- kept; Ed25519.lua's jobs fed only below its limit.
---------------------------------------------------------------------------

local claims = {}    -- [sender] = { key, ok (nil while pending), cbs }
local vqueue = {}
local function Finish(rec, ok)
	rec.ok = ok == true
	local cbs = rec.cbs
	rec.cbs = {}
	for _, cb in ipairs(cbs) do ns.SafeCall("arena verify", cb, rec.ok) end
end
local function PumpVerify()
	local Ed = ns.Ed25519
	while vqueue[1] and Ed and Ed.Busy() < Arena.VERIFY_BUSY do
		local job = table.remove(vqueue, 1)
		local c = job.claim
		local started = Ed.Run(function() return Ed.Verify(c.pk, c.msg, c.sig) end,
			function(ok, res) Finish(job.rec, ok and res == true) end)
		if not started then table.insert(vqueue, 1, job) break end
	end
	Arena.Involve("~verify", vqueue[1] ~= nil)
end
-- claim = { pk (32 bytes), msg, sig (64 bytes), key (what makes it the same claim: gk and pk) }.
-- cb(ok) once known. Returns the answer when already known, else nil.
function Arena.Verify(sender, claim, cb)
	cb = type(cb) == "function" and cb or function() end
	if type(sender) ~= "string" or type(claim) ~= "table" then cb(false) return false end
	sender = ns.FullName(sender)
	local key = tostring(claim.key or ((claim.gk or "") .. "|" .. tostring(claim.pk)))
	local rec = claims[sender]
	if rec then
		if rec.key ~= key then cb(false) return false end
		if rec.ok ~= nil then cb(rec.ok) return rec.ok end
		rec.cbs[#rec.cbs + 1] = cb
		return nil
	end
	if #vqueue >= Arena.VERIFY_QUEUE then cb(false) return false end
	rec = { key = key, cbs = { cb } }
	claims[sender] = rec
	vqueue[#vqueue + 1] = { claim = claim, rec = rec }
	PumpVerify()
	return nil
end
function Arena.VerifyQueue() return #vqueue end

---------------------------------------------------------------------------
-- The ticker's work
---------------------------------------------------------------------------

Tick = function()
	local now = Arena.Now()
	-- (Collected first: a callback may add or cancel others.)
	local due = {}
	for key, a in pairs(afters) do if a.at <= now then due[#due + 1] = key end end
	table.sort(due)
	for _, key in ipairs(due) do
		local a = afters[key]
		if a and a.at <= now then
			afters[key] = nil
			ns.SafeCall("arena after " .. key, a.fn)
		end
	end
	due = {}
	for key, e in pairs(everies) do if e.next <= now then due[#due + 1] = key end end
	table.sort(due)
	for _, key in ipairs(due) do
		local e = everies[key]
		if e and e.next <= now then
			e.next = now + e.every
			ns.SafeCall("arena every " .. key, e.fn)
		end
	end
	SendTick(now)
	if vqueue[1] then PumpVerify() end
	Recompute()
end
Arena.Tick = function() return Tick() end -- (tests)

---------------------------------------------------------------------------
-- Actions: every screen button goes through these (the design); each package registers its own.
---------------------------------------------------------------------------

local actions = {}
function Arena.Action(name, can, act)
	if type(name) ~= "string" or type(act) ~= "function" then return false end
	actions[name] = { can = type(can) == "function" and can or nil, act = act }
	return true
end
-- 1.1.6: the actions that are Olympus's games (their prefix before "."): a sanctioned player
-- (WatchChat.Barred: a moderator's timeout, a hold while his case is decided, a net-off word)
-- plays none while it lasts: no fight, card, matchmaking, tournament, lottery, bet or stake, no
-- arbiter's duty. His profile, honours, ledger words and a debt's fee stay his.
Arena.GAMES = { fights = true, card = true, match = true, tourney = true, lottery = true, bet = true, overrule = true,
	closebets = true, arbiter = true, stakes = true, farkle = true }
function Arena.Sanctioned(name)
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and type(WC.Barred) == "function" and WC.Barred("games", name) or nil
end
-- Whether it may be done now, and why not: the kill switch, the compliance gate for an action that
-- only makes or pays a wager (Compliance.ACTIONS), the sim for actions that send, then the action's
-- own rule.
function Arena.Can(name, ...)
	local a = actions[name]
	if not a then return false, "unknown" end
	if Arena.Off() then return false, "off" end
	local C = ns.Compliance
	if not (type(C) == "table" and type(C.Action) == "function" and C.Action(name) == true) then return false, "compliance" end
	if Arena.GAMES[(tostring(name):match("^([^%.]+)"))] and Arena.Sanctioned() then return false, "sanction" end
	if not a.can then return true end
	local ok, yes, why = pcall(a.can, ...)
	if not ok then ns.Log("arena can %s failed: %s", name, tostring(yes)) return false, "error" end
	return yes == true, why
end
function Arena.Do(name, ...)
	local ok, why = Arena.Can(name, ...)
	if not ok then return false, why end
	local okDo, a, b = pcall(actions[name].act, ...)
	if not okDo then
		if ns.CaptureError then ns.CaptureError("arena do " .. name, a) end
		return false, "error"
	end
	return a == nil and true or a, b
end

---------------------------------------------------------------------------
-- The companion (the design): Olympus_Arena, load on demand. An addon's private table is not shared,
-- so the namespace is handed over for one synchronous call (OlympusArenaHandoff).
---------------------------------------------------------------------------

Arena.companionReady = false -- Handoff.lua sets it, after a real handoff only
local uiLoaded = false
function Arena.UILoaded() return uiLoaded end

local REASONS = { DISABLED = "ARENA_UI_DISABLED", MISSING = "ARENA_UI_MISSING", INTERFACE_VERSION = "ARENA_UI_OUTDATED" }
local function ReasonLine(why)
	why = tostring(why or "?")
	if REASONS[why] then return L[REASONS[why]] end
	if why:find("^DEP_") then return L.ARENA_UI_DEP end
	return L.ARENA_UI_REASON:format(why)
end
local function Early()
	SayOnce("early", L.ARENA_UI_EARLY)
	return false, "early"
end

-- Loads the companion (once): refused in combat; every reason the game gives gets one clear line.
function Arena.LoadUI()
	if uiLoaded then return true end
	if InCombatLockdown and InCombatLockdown() then
		ns.Print(L.ARENA_UI_COMBAT)
		return false, "combat"
	end
	local AO = C_AddOns
	if type(AO) ~= "table" or type(AO.LoadAddOn) ~= "function" then return false, "api" end -- gp:load-companion
	-- Files from two installs refused once: the same reason again (a /reload does not mend it).
	if Arena.companionRefused == "version" then
		SayOnce("version", L.ARENA_UI_VERSION)
		return false, "version"
	end
	if AO.IsAddOnLoaded and AO.IsAddOnLoaded(Arena.COMPANION) and not Arena.companionReady then return Early() end
	Arena.companionRefused = nil
	OlympusArenaHandoff = ns
	local ok, loaded, why = pcall(AO.LoadAddOn, Arena.COMPANION) -- gp:load-companion
	OlympusArenaHandoff = nil
	if not ok then
		ns.Print(L.ARENA_UI_REASON:format(tostring(loaded)))
		return false, "error"
	end
	if not loaded then
		ns.Print(ReasonLine(why))
		return false, why or "?"
	end
	if Arena.companionRefused == "version" then
		SayOnce("version", L.ARENA_UI_VERSION)
		return false, "version"
	end
	if not Arena.companionReady then return Early() end
	uiLoaded = true
	ns.Fire("ARENA_UI_LOADED")
	Arena.Changed()
	return true
end

-- The Arena window (the companion's, the screens): opened or closed on a tab.
function Arena.Toggle(tab)
	local ok, why = Arena.LoadUI()
	if not ok then return false, why end
	local ui = Arena.ui
	if type(ui) == "table" and type(ui.Toggle) == "function" then
		ns.SafeCall("arena window", ui.Toggle, tab)
		return true
	end
	ns.Print(L.ARENA_NO_WINDOW)
	return false, "window"
end

---------------------------------------------------------------------------
-- The King's view and the stream delay (the design)
---------------------------------------------------------------------------

-- The King's own screen (or the author's preview of it, King.Preview), or the King's stand-in in a rehearsal.
function Arena.KingsView(mode)
	if ns.KingsScreen and ns.KingsScreen() then return true end
	if mode == "T" then
		local R = Roles()
		return R ~= nil and type(R.standIn) == "function" and R.standIn(ns.me, "k", "T") == true
	end
	return false
end
local function OwnDelay()
	local ui = ns.db and ns.db.arenaUI
	local d = type(ui) == "table" and tonumber(ui.delay) or 0
	return math.max(0, math.min(Arena.DELAY_MAX, math.floor(d)))
end
-- The delay a window keeps: the King's own in his view, and for a public event the delay his last
-- T1~L published (so a public event a High Councillor opens while the King streams keeps it too).
function Arena.Delay(public)
	local own = Arena.KingsView() and OwnDelay() or 0
	local king = 0
	local R = Roles()
	if public and R and R.KingDelay then king = R.KingDelay() or 0 end
	return math.max(own, king)
end
function Arena.LastCall(public) return math.max(20, Arena.Delay(public) + 20) end
function Arena.OpenMin(public) return math.max(120, Arena.Delay(public) + 75) end
-- The King (or the author's view) types it: kept, and the King's client publishes it (T1~L).
function Arena.SetDelay(s)
	if s == "off" then s = 0 end
	s = tonumber(s)
	if not s or s < 0 or s > Arena.DELAY_MAX or s ~= math.floor(s) then return false, "range" end
	if not Arena.KingsView() then return false, "king" end
	ns.db.arenaUI = type(ns.db.arenaUI) == "table" and ns.db.arenaUI or {}
	ns.db.arenaUI.delay = s
	local R = Roles()
	local K = ns.King
	if R and R.SendDelay and K and K.IsKing and K.IsKing() then R.SendDelay(s) end
	Arena.Changed()
	return true
end

---------------------------------------------------------------------------
-- Rehearsal directors (the design): who may send ER. The word itself is ArenaTest's;
-- this is the rule every client applies to it.
--   word = { lane = "g"|"a", money = "c"|"p", roles = { [Name-Realm] = letter } }
--   current = the director's word this client holds now (for a co-director), or nil
---------------------------------------------------------------------------

local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
function Arena.MayDirect(sender, word, current)
	if type(sender) ~= "string" or type(word) ~= "table" then return false, "shape" end
	local R = Roles()
	local roles = type(word.roles) == "table" and word.roles or {}
	-- Copper mode: the bank and the fee stand-ins are named by the director, never himself.
	if word.money == "p" then
		for name, letter in pairs(roles) do
			if (letter == "b" or letter == "t") and Same(name, sender) then return false, "self" end
		end
	end
	local function CoDirector()
		if type(current) ~= "table" or type(current.roles) ~= "table" or not ns.IsSignedArbiter(tostring(current.director)) then return false end
		for name, letter in pairs(current.roles) do
			if letter == "d" and Same(name, sender) then return true end
		end
		return false
	end
	if Arena.TestBuild() then
		if ns.IsSignedArbiter(sender) or CoDirector() then return true end
		return false, "director"
	end
	local lead = R and R.IsKing(sender) or (ns.King and ns.King.IsStewardName and ns.King.IsStewardName(sender))
		or ns.IsHighCouncillor(sender) or ns.IsSignedArbiter(sender)
	if lead or CoDirector() then return true end
	-- A listed arbiter may run a group rehearsal, without public-arbiter or King stand-ins.
	if word.lane == "g" and R and R.IsArbiter(sender, "L") then
		for _, letter in pairs(roles) do
			if letter == "p" or letter == "k" then return false, "stand-in" end
		end
		return true
	end
	return false, "director"
end

---------------------------------------------------------------------------
-- The events registry (the design): how Markets learns about an event without the fights part or the Bones tables.
--   Arena.Events.Register(letter, fn): fn(eid) returns { kind = "fight"|"tourney"|"farkle"|"lottery",
--   opener, fighters = { A = { name, gk }, B = ... }, slots, entrants, category, public, mode, lockAt }
---------------------------------------------------------------------------

Arena.Events = {}
local sources = {}
function Arena.Events.Register(letter, fn)
	if type(letter) ~= "string" or #letter ~= 1 or type(fn) ~= "function" then return false end
	sources[letter] = fn
	return true
end
function Arena.EventOf(eid)
	if type(eid) ~= "string" or eid == "" then return nil end
	local fn = sources[eid:sub(1, 1)]
	if not fn then return nil end
	local ok, ev = pcall(fn, eid)
	return ok and type(ev) == "table" and ev or nil
end

---------------------------------------------------------------------------
-- /oly arena (the design): each package registers its own sub-commands; everything is also a
-- click (the gamepad UI needs no command).
---------------------------------------------------------------------------

local subs, subOrder = {}, {}
function Arena.Slash(sub, fn, usage)
	if type(sub) ~= "string" or type(fn) ~= "function" then return false end
	sub = sub:lower()
	if not subs[sub] then subOrder[#subOrder + 1] = sub end
	subs[sub] = { fn = fn, usage = usage }
	return true
end
local function Help()
	ns.Print(L.ARENA_HELP)
	for _, sub in ipairs(subOrder) do
		local s = subs[sub]
		if s.usage then print("  " .. s.usage) end
	end
end
function Arena.RunSlash(rest)
	rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then return Arena.Toggle() end
	if sub == "help" then return Help() end
	local s = subs[sub]
	if not s then return Help() end
	return s.fn(args or "")
end

-- The lines of /oly status and /oly bug (Diagnostics.lua: ns.statusLines), and of /oly arena status.
function Arena.StatusLines(lines)
	local R = Roles()
	local t = Arena.TestBuild()
	lines[#lines + 1] = t and L.ARENA_STATUS_TEST:format(t.n, t.base, tostring(t.lane or "group")) or L.ARENA_STATUS_BUILD:format(ns.VERSION)
	local live = R and R.Live and R.Live()
	lines[#lines + 1] = L.ARENA_STATUS_REALM:format(tostring(ns.realm), live and L.ARENA_LIVE_ON or L.ARENA_LIVE_OFF,
		tostring(R and R.Currency and R.Currency() or "g"))
	lines[#lines + 1] = Arena.Off() and L.ARENA_STATUS_OFF or (Arena.Sim() and L.ARENA_STATUS_SIM or L.ARENA_STATUS_ON)
	lines[#lines + 1] = persists and L.ARENA_SAVED_KEPT or L.ARENA_SAVED_LOST
	local keys = {}
	for _, k in ipairs(Arena.Involved()) do if k:sub(1, 1) ~= "~" then keys[#keys + 1] = k end end
	lines[#lines + 1] = L.ARENA_STATUS_INVOLVED:format(#keys > 0 and table.concat(keys, ", ") or L.ARENA_NOTHING,
		#backlog, #lowq, #retries, urgentOut)
	local memory = type(GetAddOnMemoryUsage) == "function" and GetAddOnMemoryUsage or nil
	local function Kb(name)
		if not memory then return 0 end
		local ok, v = pcall(memory, name)
		return ok and tonumber(v) or 0
	end
	lines[#lines + 1] = L.ARENA_STATUS_MEMORY:format(Kb("Olympus"), Kb(Arena.COMPANION), uiLoaded and L.ARENA_UI_OPEN or L.ARENA_UI_CLOSED)
end
if type(ns.statusLines) == "table" then
	table.insert(ns.statusLines, function(lines) Arena.StatusLines(lines) end)
end

Arena.Slash("status", function()
	if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
	local lines = {}
	Arena.StatusLines(lines)
	for _, line in ipairs(lines) do print("  " .. line) end
end, L.ARENA_HELP_STATUS)
Arena.Slash("off", function() Arena.SetOff(true) end, L.ARENA_HELP_OFF)
Arena.Slash("on", function() Arena.SetOff(false) end)
-- The sim opens in the companion: loaded first (refused in combat...: the sim stays off), then
-- switched on, then its screens (Arena.ui, there once the companion is).
Arena.Slash("sim", function(args)
	if tostring(args):lower() == "off" then return Arena.SetSim(false) end
	if not Arena.MaySim() then ns.Print(L.ARENA_SIM_REFUSED) return end
	if not Arena.LoadUI() then return end
	if not Arena.SetSim(true) then return end
	local ui = Arena.ui
	if type(ui) == "table" and type(ui.Sim) == "function" then ns.SafeCall("arena sim", ui.Sim, args) end
end, L.ARENA_HELP_SIM)
Arena.Slash("delay", function(args)
	local ok, why = Arena.SetDelay(tostring(args):lower() == "off" and "off" or args)
	if ok then ns.Print(L.ARENA_DELAY_SET:format(OwnDelay()))
	elseif why == "king" then ns.Print(L.THRONE_ONLY_KING)
	else ns.Print(L.ARENA_DELAY_USAGE) end
end, L.ARENA_HELP_DELAY)

-- At login: the test build's line (once a session), or its expiry.
ns.On("LOGIN", function()
	local t = Arena.TestBuild()
	if not t then return end
	if Arena.Now() > t.expires then
		expired = true
		ns.Print(L.ARENA_TEST_EXPIRED)
	else
		ns.Print(L.ARENA_TEST_LOGIN:format(t.n))
	end
end)
