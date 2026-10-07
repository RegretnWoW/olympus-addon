local ADDON, ns = ...
local L = ns.L

-- The Blood Arena's roles (1.2, the design): who is a bank, an arbiter, a leader, an auditor, the fee
-- receiver, and the King's settings, from the King's words. They are kinds of the King's T1 (not
-- enveloped), taken on the channel from the King or his Steward (King.Authorized), per realm of the
-- server-stamped sender (the design: a realm whose King or Steward never sends T1~O stays in
-- rehearsal). The newest word wins, the King's own on the same second; a word dated more than
-- King.DATE_AHEAD ahead of the server's clock is not taken.
--   T1~B~<id>~<guild>~<time>~Name-Realm:o|c,...          up to 3 banks, open or closing
--   T1~M~<id>~<guild>~<time>~Name-Realm:capGold,...      up to 40 arbiters and their holding caps
--   T1~O~<id>~<guild>~<time>~live~cur~feeBp~arbBp~minBet~maxBet~maxDay~maxPool~bankCap~directMax~scalePct~minLevel~feeTo
--   T1~L~<id>~<guild>~<time>~<delay>                     the King's stream delay (his alone)
--   T1~J~<id>~<guild>~<time>~Short Name:abl,...          up to 12 High Councillors who publish the games'
--                                                        rankings, and which (a the Arena, b Bones, l the Lottery)
-- T1~O's money: minBet in copper, the others in whole gold (Settings() gives every amount in copper).
--
-- Who is who (the design): leaders send words (the King's character, a Steward, a High
-- Councillor, a signed arbiter); auditors receive ledgers (the King's character, a High Councillor,
-- a signed arbiter with "+a"). Stewards are no auditors (the owner's answer).
-- No arena file names the author: his power is the signed ^arbiter^ entry (ns.IsSignedArbiter).
-- A test build gives no word and repeats none (the design: it never touches live and sends
-- nothing on OlympusNet); it still takes the words it hears.

local Roles = {}
ns.ArenaRoles = Roles

Roles.BANKS_MAX = 3
Roles.ARBITERS_MAX = 40
Roles.REPEAT = 300          -- the giver's client repeats his words this often, for late logins
Roles.ANSWER_GAP = 30       -- an older word heard is answered with ours at most this often
Roles.DELAY_LAPSE = 900     -- the King's delay lapses this long after his last T1~L
Roles.DELAY_MAX = 900
Roles.GOLD = 10000
Roles.CAP_LOW = 100         -- gold: an arbiter's cap when the word gives none (the lowest tier)
Roles.CAP_MAX = 50000       -- gold
Roles.WORD_MAX = 2600       -- bytes of a word's body at most
Roles.PUBLISHERS_MAX = 12   -- councillors the King names to publish the games' rankings
Roles.PUBLISH_LOG_MAX = 20  -- publish words kept, newest last
-- The games whose rankings are published one by one (the owner's answer, 2026-10-04), by letter.
Roles.RANK_GAMES = { "arena", "bones", "lottery" }
Roles.GAME_LETTER = { arena = "a", bones = "b", lottery = "l" }
Roles.LETTER_GAME = { a = "arena", b = "bones", l = "lottery" }

Roles.DEFAULTS = { live = 0, cur = "g", feeBp = 600, arbBp = 200, minBet = 1000, maxBet = 20 * Roles.GOLD,
	maxDay = 60 * Roles.GOLD, maxPool = 1000 * Roles.GOLD, bankCap = 5000 * Roles.GOLD, directMax = 50 * Roles.GOLD,
	scalePct = 100, minLevel = 10, feeTo = nil, rankPub = 0 }
-- T1~O's fields in their order: name, unit on the wire ("n" a number, "c" copper, "g" whole gold,
-- "cur" g|p, "name" - or Name-Realm), bounds (in the wire's unit).
Roles.FIELDS = {
	{ "live", "n", 0, 1 }, { "cur", "cur" }, { "feeBp", "n", 0, 1000 }, { "arbBp", "n", 0, 1000 },
	{ "minBet", "c", 100, 100000 }, { "maxBet", "g", 1, 500 }, { "maxDay", "g", 1, 2000 }, { "maxPool", "g", 1, 20000 },
	{ "bankCap", "g", 1, 50000 }, { "directMax", "g", 1, 100 }, { "scalePct", "n", 25, 300 }, { "minLevel", "n", 1, 60 },
	{ "feeTo", "name" },
	-- (1.2 test build, 2026-09-30: the games' rankings shown to everyone on the Games tab, 1, or to
	-- the staff alone, 0; a word from a build before it lacks the field and reads as 0)
	{ "rankPub", "n", 0, 1 },
}

-- The King lends these kinds to his Steward, as Week.lua lends his week (King.lua is not changed):
-- banks, arbiters, settings. The delay (L) and the rankings' publishers (J: the owner's answer,
-- 2026-10-04, the King and the councillors he names) are the King's alone; no Hand sends any of them.
ns.King.STEWARD_MAY.B = true
ns.King.STEWARD_MAY.M = true
ns.King.STEWARD_MAY.O = true

-- Hooks other packages set (false or empty by default):
-- Roles.standIn(name, letter, mode): a rehearsal's stand-in (ArenaTest, the screens): "b" bank, "a"
-- arbiter, "p" public arbiter, "k" King, "t" fee receiver, "d" co-director. T only.
Roles.standIn = function() return false end
-- Roles.standIns(letter, mode): the stand-ins of a letter, { "Name-Realm", ... }.
Roles.standIns = function() return {} end
-- Roles.stillOwing(name): a bank a newer word left out still shows liabilities (Wallet, the money part: its ZH
-- flag "L" or the replicas): it stays, closing ("c"), until a checkpoint shows zero (the design).
Roles.stillOwing = function() return false end

local function Now() return ns.Arena.Now() end
local function Lower(name) return type(name) == "string" and ns.FullName(name):lower() or nil end
local function Same(a, b) return Lower(a) ~= nil and Lower(a) == Lower(b) end

---------------------------------------------------------------------------
-- The words, per realm (the live store only: ns.rdb.arena.realms[realm].roles, never the sim's)
---------------------------------------------------------------------------

local function WordsOf(realm)
	if type(ns.rdb) ~= "table" then return {} end
	local a = ns.rdb.arena
	if type(a) ~= "table" then a = {} ns.rdb.arena = a end
	if type(a.realms) ~= "table" then a.realms = {} end
	realm = realm or ns.realm or "?"
	local r = a.realms[realm]
	if type(r) ~= "table" then r = { v = 1 } a.realms[realm] = r end
	if type(r.roles) ~= "table" then r.roles = {} end
	return r.roles
end
Roles.WordsOf = WordsOf

-- A word dated `at` from `sender` replaces the one kept: newer, or the King's own of the same second
-- over anyone else's (Treasury.Replaces' rule).
local function Replaces(kept, at, sender)
	local was = type(kept) == "table" and tonumber(kept.at) or nil
	if not was or at ~= was then return was == nil or at > was end
	return ns.IsKingCharacter(sender) and not ns.IsKingCharacter(kept.from)
end

---------------------------------------------------------------------------
-- Who is who
---------------------------------------------------------------------------

function Roles.IsKing(name) return type(name) == "string" and ns.IsKingCharacter(ns.FullName(name)) == true end
local function IsSteward(name) return ns.King and ns.King.IsStewardName and ns.King.IsStewardName(ns.FullName(name)) == true end
-- 1.1.6: a player under a moderator's sanction (WatchChat.PowersBarred: a timeout, a hold, a
-- net-off word; never the King) has none of the arena's powers while it lasts: no leader's word,
-- no ledger as an auditor, no ranking published, no promotion; a bank of his is closing (it pays
-- out and settles, it takes nothing new), so nothing it holds is stuck. An arbiter's duty is a
-- game (Arena.GAMES): his own client takes none, and the stakes he holds are settled as ever.
local function Barred(name)
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and type(WC.PowersBarred) == "function" and WC.PowersBarred(ns.FullName(name)) ~= nil
end
Roles.Barred = Barred

local function StandIn(name, letter, mode)
	if mode ~= "T" then return false end
	local ok, yes = pcall(Roles.standIn, name, letter, mode)
	return ok and yes == true
end

-- The King's character, a High Councillor or a signed arbiter (and in T the stand-ins "p", "k").
function Roles.IsPublicArbiter(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	if Roles.IsKing(name) or ns.IsHighCouncillor(ns.FullName(name)) or ns.IsSignedArbiter(name) then return true end
	return StandIn(name, "p", mode) or StandIn(name, "k", mode)
end

-- The arbiters the King's T1~M names for this realm: { { name, cap (gold) }, ... }.
function Roles.Arbiters(realm)
	local w = WordsOf(realm).arbiters
	local out = {}
	for _, a in ipairs(type(w) == "table" and type(w.list) == "table" and w.list or {}) do
		if type(a) == "table" and type(a.name) == "string" then out[#out + 1] = { name = a.name, cap = tonumber(a.cap) or Roles.CAP_LOW } end
	end
	return out
end
local function Listed(list, name)
	for _, e in ipairs(list) do if Same(e.name, name) then return e end end
	return nil
end
-- Listed by T1~M, or a public arbiter (and in T the stand-ins "a").
function Roles.IsArbiter(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	if Listed(Roles.Arbiters(), name) or Roles.IsPublicArbiter(name, mode) then return true end
	return StandIn(name, "a", mode)
end
-- An arbiter's holding cap in copper, from T1~M (a public arbiter the word leaves out holds the
-- lowest tier's); 0 for anyone else. It never rises by itself (the design).
function Roles.ArbiterCap(name)
	local e = type(name) == "string" and Listed(Roles.Arbiters(), name)
	if e then return math.floor(e.cap) * Roles.GOLD end
	if Roles.IsPublicArbiter(name) then return Roles.CAP_LOW * Roles.GOLD end
	return 0
end

-- May send words: the King's character, a Steward, a High Councillor, a signed arbiter.
function Roles.Leader(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	if Roles.IsKing(name) then return true end
	if Barred(name) then return false end
	if IsSteward(name) or ns.IsHighCouncillor(ns.FullName(name)) or ns.IsSignedArbiter(name) then return true end
	return StandIn(name, "k", mode)
end
-- Receives ledgers: the King's character, a High Councillor, a signed arbiter with "+a". Never a
-- Steward alone.
function Roles.Auditor(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	if Roles.IsKing(name) then return true end
	if Barred(name) then return false end
	if ns.IsHighCouncillor(ns.FullName(name)) or ns.IsSignedAuditor(name) then return true end
	return StandIn(name, "k", mode)
end
-- May promote a Fight Night or a tournament (the owner's answer): the King, his
-- Stewards and his Hands, and every public arbiter.
function Roles.MayPromote(name, mode)
	if type(name) ~= "string" or name == "" then return false end
	if not Roles.IsKing(name) and Barred(name) then return false end
	local K = ns.King
	if IsSteward(name) or (K and K.IsHandName and K.IsHandName(ns.FullName(name))) then return true end
	return Roles.IsPublicArbiter(name, mode)
end

-- A treasury keeper or one of the Treasurer's pinned characters (Treasury.IsKeeperName; a keeper
-- is listed by name, whatever his guild, so it is asked with an Olympus guild's name).
local KEEPER_GUILD = "Olympus"
local function IsKeeper(name)
	if ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(name) then return true end
	local T = ns.Treasury
	if type(T) == "table" and type(T.IsKeeperName) == "function" then
		local ok, yes = pcall(T.IsKeeperName, name, KEEPER_GUILD)
		return ok and yes == true
	end
	return false
end

-- Why a character may not be a bank (the design): the King's character, a Steward, a High
-- Councillor, a treasury keeper or a pinned Treasurer character, or an arbiter. nil when he may.
local function Excluded(name)
	if Roles.IsKing(name) then return "king" end
	if IsSteward(name) then return "steward" end
	if ns.IsHighCouncillor(ns.FullName(name)) then return "councillor" end
	if IsKeeper(name) then return "keeper" end
	if Roles.IsArbiter(name, "L") then return "arbiter" end
	return nil
end
Roles.Excluded = Excluded

-- The banks of this realm: { { name, state = "o"|"c", dropped }, ... }. A bank a newer word left out
-- while it still owes stays, closing (the design). In T the rehearsal's "b" stand-ins come too.
function Roles.Banks(mode)
	local w = WordsOf(ns.realm).banks
	local out = {}
	for _, b in ipairs(type(w) == "table" and type(w.list) == "table" and w.list or {}) do
		if type(b) == "table" and type(b.name) == "string" and not Excluded(b.name) then
			out[#out + 1] = { name = b.name, state = (b.state == "c" or Barred(b.name)) and "c" or "o" }
		end
	end
	for _, b in ipairs(type(w) == "table" and type(w.dropped) == "table" and w.dropped or {}) do
		if type(b) == "table" and not Listed(out, b.name) then
			local ok, owing = pcall(Roles.stillOwing, b.name)
			if ok and owing == true then out[#out + 1] = { name = b.name, state = "c", dropped = true } end
		end
	end
	if mode == "T" then
		local ok, list = pcall(Roles.standIns, "b", "T")
		for _, name in ipairs(ok and type(list) == "table" and list or {}) do
			if type(name) == "string" and not Listed(out, name) then out[#out + 1] = { name = name, state = "o", standIn = true } end
		end
	end
	return out
end
function Roles.IsBank(name, mode)
	if type(name) ~= "string" then return false end
	return Listed(Roles.Banks(mode), name) ~= nil
end
-- "o" (open), "c" (closing: withdrawals only), or nil (no bank of this realm).
function Roles.BankState(name)
	local e = type(name) == "string" and Listed(Roles.Banks("L"), name)
	return e and e.state or nil
end

-- The reason a role is refused, or nil: role "bank", "arbiter", "public", "auditor", "leader".
function Roles.Why(name, role)
	if type(name) ~= "string" or name == "" then return "name" end
	if role == "bank" then
		local why = Excluded(name)
		if why then return why end
		return Roles.IsBank(name, "L") and nil or "unlisted"
	elseif role == "arbiter" then
		return Roles.IsArbiter(name, "L") and nil or "unlisted"
	elseif role == "public" then
		return Roles.IsPublicArbiter(name, "L") and nil or "public"
	elseif role == "auditor" then
		return Roles.Auditor(name, "L") and nil or "auditor"
	elseif role == "leader" then
		return Roles.Leader(name, "L") and nil or "leader"
	end
	return "role"
end
function Roles.WhyText(why) return L["ARENA_WHY_" .. tostring(why):upper()] end

-- The account's characters (Treasury keeps them in ns.db.myCharacters, in lower case) as the server
-- writes them: each word of a name capitalised, the realm one this client knows.
local function KnownRealm(lower)
	local candidates = { ns.realm, ns.CurrentRealm and ns.CurrentRealm(), ns.KingRealm and ns.KingRealm(), ns.TREASURER_REALM }
	for _, r in ipairs(ns.GroupRealms(ns.group or ns.realm)) do candidates[#candidates + 1] = r end
	for _, r in ipairs(candidates) do
		if type(r) == "string" and r:lower() == lower then return r end
	end
	return nil
end
function Roles.ProperName(key)
	if type(key) ~= "string" or key == "" then return nil end
	local short, realm = key:match("^(.-)%-(.+)$")
	short = (short or key):gsub("(%S)(%S*)", function(a, b) return a:upper() .. b:lower() end)
	if realm then realm = KnownRealm(realm:lower()) or realm end
	return ns.FullName(short, realm)
end
-- On the bank's own client: the role is refused while any character of its account is one of those
-- (the design). Returns true, or false, why, the character.
function Roles.MayBank()
	local names = { ns.me }
	local mine = ns.db and ns.db.myCharacters
	if type(mine) == "table" then
		for key in pairs(mine) do names[#names + 1] = Roles.ProperName(key) end
	end
	for _, name in ipairs(names) do
		local why = type(name) == "string" and Excluded(name)
		if why then return false, why, name end
	end
	return true
end

---------------------------------------------------------------------------
-- The settings (T1~O)
---------------------------------------------------------------------------

-- The fee receiver of a realm's group and faction: on the Alliance of the Treasurer's realm group
-- his pinned characters (the mail goes to Dues.MailTo()); elsewhere the character T1~O names
-- (feeTo); else nil, and gold is refused there (the owner's answer).
local function TreasurerGroup(realm)
	return ns.faction ~= "Horde" and type(ns.TREASURER_REALM) == "string" and ns.GroupOf(realm or ns.realm) == ns.GroupOf(ns.TREASURER_REALM)
end
function Roles.FeeReceiver(realm)
	realm = realm or ns.realm
	if TreasurerGroup(realm) then
		local D = ns.Dues
		local to = type(D) == "table" and type(D.MailTo) == "function" and D.MailTo() or nil
		return to or ns.FullName(ns.TREASURER, ns.TREASURER_REALM), "treasurer"
	end
	local feeTo = Roles.Settings(realm).feeTo
	if feeTo then return feeTo, "named" end
	return nil
end
-- Whether a sender is that receiver (a fee receipt, ZF): a pinned Treasurer character, or feeTo.
function Roles.IsFeeReceiver(name, realm)
	if type(name) ~= "string" or name == "" then return false end
	realm = realm or ns.realm
	if TreasurerGroup(realm) then return ns.IsTreasurerCharacter(ns.FullName(name)) == true end
	local feeTo = Roles.Settings(realm).feeTo
	return feeTo ~= nil and Same(feeTo, name)
end

-- The settings of a word's body: the table (amounts in copper), or nil and why. `realm`: the
-- sender's (the fee receiver's group). Any value out of bounds refuses the whole word; so does gold
-- with no fee receiver there, and a fee receiver who is a bank or an arbiter.
function Roles.ReadSettings(body, realm)
	if type(body) ~= "string" or #body > 200 then return nil, "shape" end
	local parts = {}
	for part in (body .. "~"):gmatch("([^~]*)~") do parts[#parts + 1] = part end
	if #parts == #Roles.FIELDS - 1 then parts[#parts + 1] = "0" end -- (rankPub, from an older build)
	if #parts ~= #Roles.FIELDS then return nil, "shape" end
	local t = {}
	for i, f in ipairs(Roles.FIELDS) do
		local key, unit, lo, hi, v = f[1], f[2], f[3], f[4], parts[i]
		if unit == "cur" then
			if v ~= "g" and v ~= "p" then return nil, key end
			t[key] = v
		elseif unit == "name" then
			if v == "-" then
				t[key] = nil
			else
				local name = ns.Arena.Name(v)
				if not name then return nil, key end
				t[key] = name
			end
		else
			if not v:find("^%d+$") or #v > 7 then return nil, key end
			local n = tonumber(v)
			if n < lo or n > hi then return nil, key end
			t[key] = unit == "g" and n * Roles.GOLD or n
		end
	end
	if t.arbBp > t.feeBp then return nil, "arbBp" end
	if t.maxBet < t.minBet then return nil, "maxBet" end
	if t.feeTo and (Roles.IsArbiter(t.feeTo, "L") or Roles.IsBank(t.feeTo, "L")) then return nil, "feeTo" end
	if t.cur == "g" and not TreasurerGroup(realm) and not t.feeTo then return nil, "receiver" end
	return t
end
function Roles.SettingsText(t)
	local out = {}
	for i, f in ipairs(Roles.FIELDS) do
		local key, unit, v = f[1], f[2], t[f[1]]
		if unit == "name" then out[i] = v and ns.FullName(v) or "-"
		elseif unit == "cur" then out[i] = v == nil and "g" or tostring(v)
		elseif unit == "g" then out[i] = tostring(math.floor((tonumber(v) or 0) / Roles.GOLD))
		else out[i] = tostring(math.floor(tonumber(v) or 0)) end
	end
	return table.concat(out, "~")
end

-- This realm's settings (the defaults where no word came), a copy.
function Roles.Settings(realm)
	local w = WordsOf(realm or ns.realm).settings
	local out = {}
	for k, v in pairs(Roles.DEFAULTS) do out[k] = v end
	if type(w) == "table" and type(w.values) == "table" then
		for k, v in pairs(w.values) do out[k] = v end
		out.at, out.from = w.at, w.from
	end
	return out
end
-- The live switch of this realm (a test build is never live: Arena.Mode gives T there anyway).
function Roles.Live(realm) return Roles.Settings(realm).live == 1 end
function Roles.Currency(realm) return Roles.Settings(realm).cur == "p" and "p" or "g" end
-- The King's published stream delay for this realm, while fresh (it lapses DELAY_LAPSE after his
-- last T1~L), else 0.
function Roles.KingDelay(realm)
	local d = WordsOf(realm or ns.realm).kingDelay
	if type(d) ~= "table" or Now() - (tonumber(d.heard) or 0) > Roles.DELAY_LAPSE then return 0 end
	return math.max(0, math.min(Roles.DELAY_MAX, tonumber(d.delay) or 0))
end

---------------------------------------------------------------------------
-- Taking the words
---------------------------------------------------------------------------

local function ReadBanks(body, realm)
	local list, seen = {}, {}
	if body ~= "" then
		for entry in (body .. ","):gmatch("([^,]*),") do
			local raw, state = entry:match("^(.+):([oc])$")
			local name = raw and ns.Arena.Name(raw:find("-", 1, true) and raw or ns.FullName(raw, realm))
			if not name or seen[name:lower()] then return nil, "entry" end
			seen[name:lower()] = true
			list[#list + 1] = { name = name, state = state }
		end
	end
	if #list > Roles.BANKS_MAX then return nil, "count" end
	return { list = list }
end
local function ReadArbiters(body, realm)
	local list, seen = {}, {}
	if body ~= "" then
		for entry in (body .. ","):gmatch("([^,]*),") do
			local raw, cap = entry:match("^([^:]+):?(%d*)$")
			local name = raw and ns.Arena.Name(raw:find("-", 1, true) and raw or ns.FullName(raw, realm))
			if not name or seen[name:lower()] or #cap > 6 then return nil, "entry" end
			seen[name:lower()] = true
			cap = tonumber(cap)
			if cap and (cap < 1 or cap > Roles.CAP_MAX) then return nil, "cap" end
			list[#list + 1] = { name = name, cap = cap or Roles.CAP_LOW }
		end
	end
	if #list > Roles.ARBITERS_MAX then return nil, "count" end
	return { list = list }
end

-- "Short Name:abl,...": councillors are named per realm group (ns.IsHighCouncillor), so by their
-- short name; each with the games he publishes.
local function ReadPublishers(body)
	local list, seen = {}, {}
	if body ~= "" then
		for entry in (body .. ","):gmatch("([^,]*),") do
			local name, games = entry:match("^([^:~]+):([abl]+)$")
			if not name or #name > 48 or #games > 3 or seen[name:lower()] then return nil, "entry" end
			seen[name:lower()] = true
			local set = {}
			for g in games:gmatch(".") do
				if set[Roles.LETTER_GAME[g]] then return nil, "entry" end
				set[Roles.LETTER_GAME[g]] = true
			end
			list[#list + 1] = { name = name, games = set }
		end
	end
	if #list > Roles.PUBLISHERS_MAX then return nil, "count" end
	return { list = list }
end

local lastAnswer = -math.huge
local Resend -- (below)

-- A word of `kind` ("banks", "arbiters", "settings") from `sender`, dated `at`. Returns true when
-- taken, else false and why.
local function Take(kind, sender, at, value)
	local realm = ns.Arena.RealmOf(sender)
	local words = WordsOf(realm)
	local kept = words[kind]
	if not Replaces(kept, at, sender) then
		-- An older word heard on the giver's side: answered with the newer one (for late logins).
		if type(kept) == "table" and at < (tonumber(kept.at) or 0) and realm == ns.realm and ns.King.SetsLists()
			and Now() - lastAnswer >= Roles.ANSWER_GAP then
			lastAnswer = Now()
			Resend(kind)
		end
		return false, "older"
	end
	if kind == "banks" then
		-- A bank the new word leaves out while it still owes stays, closing (the design).
		local dropped = {}
		local was = type(kept) == "table" and kept or {}
		for _, list in ipairs({ was.list or {}, was.dropped or {} }) do
			for _, b in ipairs(list) do
				if type(b) == "table" and not Listed(value.list, b.name) and not Listed(dropped, b.name) then
					local ok, owing = pcall(Roles.stillOwing, b.name)
					if ok and owing == true then dropped[#dropped + 1] = { name = b.name } end
				end
			end
		end
		value.dropped = dropped
	end
	value.at, value.from, value.t = at, ns.FullName(sender), Now()
	words[kind] = value
	-- (Who is an arbiter decides whose ledger entries count: the ratings are worked out again.)
	if kind == "arbiters" and ns.ArenaLedger and ns.ArenaLedger.Bump then ns.ArenaLedger.Bump() end
	if ns.King.IsKing() and ns.King.IsStewardName(sender) then
		ns.Print(L.ARENA_STEWARD_SET:format(ns.King.StewardLabel(sender), L["ARENA_WORD_" .. kind:upper()]))
	end
	ns.Arena.Changed()
	return true
end

-- "<time>~<body>": the time and the body, or nil (a time ahead of the server's clock by more than a
-- minute is not taken).
local function Dated(rest)
	rest = tostring(rest or "")
	if #rest > Roles.WORD_MAX then return nil end
	local at, body = rest:match("^(%d+)~?(.*)$")
	at = at and #at <= 12 and tonumber(at)
	if not at or at > Now() + ns.King.DATE_AHEAD then return nil end
	return at, body
end

function Roles.TakeBanks(sender, rest)
	if ns.Arena.Off() then return false, "off" end
	local at, body = Dated(rest)
	if not at then return false, "time" end
	local value, why = ReadBanks(body, ns.Arena.RealmOf(sender))
	if not value then return false, why end
	return Take("banks", sender, at, value)
end
function Roles.TakeArbiters(sender, rest)
	if ns.Arena.Off() then return false, "off" end
	local at, body = Dated(rest)
	if not at then return false, "time" end
	local value, why = ReadArbiters(body, ns.Arena.RealmOf(sender))
	if not value then return false, why end
	return Take("arbiters", sender, at, value)
end
function Roles.TakeSettings(sender, rest)
	if ns.Arena.Off() then return false, "off" end
	local at, body = Dated(rest)
	if not at then return false, "time" end
	local values, why = Roles.ReadSettings(body, ns.Arena.RealmOf(sender))
	if not values then return false, why end
	return Take("settings", sender, at, { values = values })
end
function Roles.TakePublishers(sender, rest)
	if ns.Arena.Off() then return false, "off" end
	local at, body = Dated(rest)
	if not at then return false, "time" end
	local value, why = ReadPublishers(body)
	if not value then return false, why end
	return Take("publishers", sender, at, value)
end
-- The King's delay: from his character alone; kept with the time it was heard (it lapses).
function Roles.TakeDelay(sender, rest, guild)
	if ns.Arena.Off() then return false, "off" end
	if not ns.King.FromKing(sender, guild) then return false, "king" end
	local at, body = Dated(rest)
	local delay = at and body:find("^%d+$") and #body <= 4 and tonumber(body)
	if not delay or delay > Roles.DELAY_MAX then return false, "delay" end
	local words = WordsOf(ns.Arena.RealmOf(sender))
	local kept = words.kingDelay
	if type(kept) == "table" and at < (tonumber(kept.at) or 0) then return false, "older" end
	words.kingDelay = { at = at, delay = delay, heard = Now(), from = ns.FullName(sender) }
	ns.Arena.Changed()
	return true
end

ns.King.Register("B", function(sender, id, rest) Roles.TakeBanks(sender, rest) end)
ns.King.Register("M", function(sender, id, rest) Roles.TakeArbiters(sender, rest) end)
ns.King.Register("O", function(sender, id, rest) Roles.TakeSettings(sender, rest) end)
ns.King.Register("L", function(sender, id, rest, guild) Roles.TakeDelay(sender, rest, guild) end)
ns.King.Register("J", function(sender, id, rest) Roles.TakePublishers(sender, rest) end)

---------------------------------------------------------------------------
-- Giving the words (the King's client or his Steward's; the Throne's composers, the screens, call these)
---------------------------------------------------------------------------

local LETTER = { banks = "B", arbiters = "M", settings = "O", publishers = "J" }
local function Body(kind, w)
	if kind == "banks" then
		local out = {}
		for _, b in ipairs(w.list or {}) do out[#out + 1] = ns.FullName(b.name) .. ":" .. (b.state == "c" and "c" or "o") end
		return table.concat(out, ",")
	elseif kind == "arbiters" then
		local out = {}
		for _, a in ipairs(w.list or {}) do out[#out + 1] = ns.FullName(a.name) .. ":" .. math.floor(tonumber(a.cap) or Roles.CAP_LOW) end
		return table.concat(out, ",")
	elseif kind == "publishers" then
		local out = {}
		for _, e in ipairs(w.list or {}) do
			local letters = ""
			for _, g in ipairs(Roles.RANK_GAMES) do if type(e.games) == "table" and e.games[g] then letters = letters .. Roles.GAME_LETTER[g] end end
			if letters ~= "" then out[#out + 1] = e.name .. ":" .. letters end
		end
		return table.concat(out, ",")
	end
	return Roles.SettingsText(w.values or {})
end
local function Guild() return (GetGuildInfo and GetGuildInfo("player")) or "" end
-- A test build sends no word on the channel (Arena.TestBuild): nil and why, else true.
local function MaySend()
	if ns.Arena.TestBuild() then return nil, "test-channel" end
	return true
end
local function Send(kind, w)
	if not MaySend() then return end
	local text = ("T1~%s~%d~%s~%d~%s"):format(LETTER[kind], ns.King.NewId(), Guild(), math.floor(w.at), Body(kind, w))
	if (kind == "arbiters" or kind == "publishers") and #text > 250 then
		ns.Comm.SendChunked(text, false, "CHANNEL")
	else
		ns.Comm.Send("CHANNEL", text, "arena word " .. kind)
	end
end
-- Our realm's word of that kind, sent again as it was given (its time kept).
Resend = function(kind)
	local w = WordsOf(ns.realm)[kind]
	if type(w) == "table" and tonumber(w.at) then Send(kind, w) end
end

-- Given here: kept as heard from ourselves (our own message never comes back), sent, and repeated.
local function Give(kind, value)
	local may, why0 = MaySend()
	if not may then return false, why0 end
	if not ns.King.SetsLists() then ns.Print(L.THRONE_ONLY_KING) return false, "king" end
	local kept = WordsOf(ns.realm)[kind]
	local at = math.max(Now(), (type(kept) == "table" and tonumber(kept.at) or 0) + 1)
	local ok, why = Take(kind, ns.me, at, value)
	if not ok then return false, why end
	Send(kind, WordsOf(ns.realm)[kind])
	Roles.Repeating()
	return true
end

-- list: { "Name-Realm" | { name, state = "o"|"c" }, ... }, 3 at most. Refused for a character who
-- may not be a bank, and for a word that drops a bank still owing (the design).
function Roles.SetBanks(list)
	if type(list) ~= "table" or #list > Roles.BANKS_MAX then return false, "count" end
	local out = {}
	for _, e in ipairs(list) do
		local name = ns.Arena.Name(type(e) == "table" and e.name or e)
		if not name or Listed(out, name) then return false, "name" end
		local why = Excluded(name)
		if why then return false, why, name end
		out[#out + 1] = { name = name, state = type(e) == "table" and e.state == "c" and "c" or "o" }
	end
	for _, b in ipairs(Roles.Banks("L")) do
		local ok, owing = pcall(Roles.stillOwing, b.name)
		if not Listed(out, b.name) and ok and owing == true then return false, "owing", b.name end
	end
	return Give("banks", { list = out })
end
-- list: { { name, cap (gold) }, ... }, 40 at most; never a bank.
function Roles.SetArbiters(list)
	if type(list) ~= "table" or #list > Roles.ARBITERS_MAX then return false, "count" end
	local out = {}
	for _, e in ipairs(list) do
		local name = ns.Arena.Name(type(e) == "table" and e.name or e)
		local cap = type(e) == "table" and tonumber(e.cap) or Roles.CAP_LOW
		if not name or Listed(out, name) then return false, "name" end
		if not cap or cap < 1 or cap > Roles.CAP_MAX or cap ~= math.floor(cap) then return false, "cap", name end
		if Roles.IsBank(name, "L") then return false, "bank", name end
		out[#out + 1] = { name = name, cap = cap }
	end
	return Give("arbiters", { list = out })
end
-- t: the settings to change (amounts in copper), over the ones in force. Checked as every client
-- checks the word.
function Roles.SetSettings(t)
	if type(t) ~= "table" then return false, "shape" end
	local s = Roles.Settings(ns.realm)
	for _, f in ipairs(Roles.FIELDS) do
		local k = f[1]
		if t[k] ~= nil then s[k] = t[k] end
	end
	if t.feeTo == false or t.feeTo == "-" then s.feeTo = nil end
	local values, why = Roles.ReadSettings(Roles.SettingsText(s), ns.realm)
	if not values then return false, why end
	return Give("settings", { values = values })
end
-- list: { { name (a High Councillor), games = { arena = true, bones = true, lottery = true } }, ... },
-- 12 at most: who publishes which game's ranking beside the King. A councillor left out (or a game
-- left out of his set) no longer publishes it, and his words for it stop counting. The King's
-- character alone names them (never his Steward: T1~J is not lent).
function Roles.SetPublishers(list)
	if not ns.King.IsKing() then ns.Print(L.THRONE_ONLY_KING) return false, "king" end
	if type(list) ~= "table" or #list > Roles.PUBLISHERS_MAX then return false, "count" end
	local out, seen = {}, {}
	for _, e in ipairs(list) do
		local name = type(e) == "table" and type(e.name) == "string" and ns.ShortName(e.name) or nil
		if not name or name == "" or #name > 48 or name:find("[:,~]") or seen[name:lower()] then return false, "name" end
		if not ns.IsHighCouncillor(name) then return false, "councillor", name end
		seen[name:lower()] = true
		local set, any = {}, false
		for _, g in ipairs(Roles.RANK_GAMES) do if type(e.games) == "table" and e.games[g] then set[g], any = true, true end end
		if any then out[#out + 1] = { name = name, games = set } end
	end
	return Give("publishers", { list = out })
end
-- The King's client publishes his delay (Arena.SetDelay), and repeats it while it is on.
local function SendDelayWord(d)
	if not MaySend() then return end
	ns.Comm.Send("CHANNEL", ("T1~L~%d~%s~%d~%d"):format(ns.King.NewId(), Guild(), math.floor(d.at), d.delay), "arena word delay")
end
function Roles.SendDelay(s)
	local may, why = MaySend()
	if not may then return false, why end
	if not ns.King.IsKing() then return false, "king" end
	s = math.max(0, math.min(Roles.DELAY_MAX, math.floor(tonumber(s) or 0)))
	local words = WordsOf(ns.realm)
	local kept = words.kingDelay
	local at = math.max(Now(), (type(kept) == "table" and tonumber(kept.at) or 0) + 1)
	words.kingDelay = { at = at, delay = s, heard = Now(), from = ns.me }
	SendDelayWord(words.kingDelay)
	Roles.Repeating()
	return true
end

---------------------------------------------------------------------------
-- The games' rankings, published one by one (the owner's answer, 2026-10-04: the King and the
-- councillors he names, per game)
---------------------------------------------------------------------------
-- AU~L1~<a|b|l>~<1|0>~<time>: that game's ranking shown to everyone (1) or to the staff alone (0),
-- on the channel, from the King's character or a High Councillor that the King's T1~J names for
-- that game (MayPublish; a Steward only when named so, as a councillor). The newest word per game stands, the King's own on the
-- same second (the words' rule). Each word taken is logged (rankLog, newest last), and the client
-- whose word stands repeats it every REPEAT while it may still publish. The King revokes by naming
-- a councillor no more: his words stop counting at once on every client, and that game falls back
-- to the settings' rankPub (all three at once, the switch from before).

local function PublishersOf(realm)
	local w = WordsOf(realm).publishers
	return type(w) == "table" and type(w.list) == "table" and w.list or {}
end
-- The King's named publishers: { { name (short), games = { arena = true, ... } }, ... }, a copy.
function Roles.Publishers(realm)
	local out = {}
	for _, e in ipairs(PublishersOf(realm)) do
		if type(e) == "table" and type(e.name) == "string" and type(e.games) == "table" then
			local games = {}
			for g in pairs(e.games) do games[g] = true end
			out[#out + 1] = { name = e.name, games = games }
		end
	end
	return out
end
-- The High Council's names (the signed list's), sorted: whom the King may name.
function Roles.Councillors()
	local c = ns.rdb and ns.rdb.council
	local out = {}
	for _, name in pairs(type(c) == "table" and type(c.names) == "table" and c.names or {}) do
		if type(name) == "string" and ns.IsHighCouncillor(name) then out[#out + 1] = name end
	end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end
-- Whether name may publish game's ranking: the King's character, or a High Councillor named for
-- that game (the owner's answer, 2026-10-04: not "the King and his Stewards").
function Roles.MayPublish(name, game, realm)
	if type(name) ~= "string" or name == "" or not Roles.GAME_LETTER[game] then return false end
	if Roles.IsKing(name) then return true end
	if not ns.IsHighCouncillor(ns.FullName(name)) or Barred(name) then return false end
	local short = ns.ShortName(ns.FullName(name)):lower()
	for _, e in ipairs(PublishersOf(realm)) do
		if type(e) == "table" and type(e.name) == "string" and e.name:lower() == short then return type(e.games) == "table" and e.games[game] == true end
	end
	return false
end
-- The word standing for game, while its giver may still publish it; nil otherwise.
local function Standing(game, realm)
	local w = WordsOf(realm or ns.realm).rankPub
	local e = type(w) == "table" and w[game]
	if type(e) ~= "table" or not Roles.MayPublish(e.from, game, realm) then return nil end
	return e
end
function Roles.PublishWord(game, realm)
	local e = Standing(game, realm)
	return e and { on = e.on == true, at = e.at, from = e.from } or nil
end
-- Whether game's ranking shows to everyone: its standing word, else the settings' rankPub.
function Roles.RankPublic(game, realm)
	local e = Standing(game, realm)
	if e then return e.on == true end
	return Roles.Settings(realm).rankPub == 1
end
-- The publish words taken, newest last: { { game, on, at, from }, ... }.
function Roles.PublishLog(realm)
	local log = WordsOf(realm or ns.realm).rankLog
	local out = {}
	for i, e in ipairs(type(log) == "table" and log or {}) do out[i] = { game = e.game, on = e.on == true, at = e.at, from = e.from } end
	return out
end

local function TakePublish(sender, game, on, at, realm)
	local words = WordsOf(realm)
	if type(words.rankPub) ~= "table" then words.rankPub = {} end
	if not Replaces(words.rankPub[game], at, sender) then return false, "older" end
	local from = ns.FullName(sender)
	words.rankPub[game] = { on = on, at = at, from = from, t = Now() }
	if type(words.rankLog) ~= "table" then words.rankLog = {} end
	local log = words.rankLog
	log[#log + 1] = { game = game, on = on, at = at, from = from }
	while #log > Roles.PUBLISH_LOG_MAX do table.remove(log, 1) end
	ns.Log("rankings: %s %s by %s", game, on and "shown" or "hidden", from)
	ns.Arena.Changed()
	return true
end
local function SendPublish(game, e)
	if not MaySend() or type(e) ~= "table" then return end
	ns.Arena.Send("AU", "L", ("%s~%d~%d"):format(Roles.GAME_LETTER[game], e.on and 1 or 0, math.floor(e.at)), { dist = "CHANNEL", key = "rankpub " .. game })
end
-- The games whose standing word this client gave, and may still give.
local function OwnPublish()
	local out = {}
	local w = WordsOf(ns.realm).rankPub
	for _, g in ipairs(Roles.RANK_GAMES) do
		local e = type(w) == "table" and w[g]
		if type(e) == "table" and Same(e.from, ns.me) and Roles.MayPublish(ns.me, g) then out[#out + 1] = g end
	end
	return out
end
function Roles.PublishRepeating()
	local on = MaySend() and OwnPublish()[1] ~= nil or false
	ns.Arena.Involve("rankpub", on)
	ns.Arena.Every(Roles.REPEAT, "rankings repeat", on and Roles.PublishRepeat or nil)
	return on
end
function Roles.PublishRepeat()
	if MaySend() then
		local w = WordsOf(ns.realm).rankPub
		for _, g in ipairs(OwnPublish()) do SendPublish(g, w[g]) end
	end
	return Roles.PublishRepeating()
end
-- Given here (the Games tab's switch): game's ranking to everyone (on) or to the staff alone.
-- True, or false and why ("publisher": not the King nor a councillor named for it).
-- A test build keeps it here and sends nothing (MaySend).
function Roles.Publish(game, on)
	if not Roles.GAME_LETTER[game] then return false, "game" end
	if not Roles.MayPublish(ns.me, game) then return false, "publisher" end
	local w = WordsOf(ns.realm).rankPub
	local kept = type(w) == "table" and w[game] or nil
	local at = math.max(Now(), (type(kept) == "table" and tonumber(kept.at) or 0) + 1)
	local ok, why = TakePublish(ns.me, game, on == true, at, ns.realm)
	if not ok then return false, why end
	SendPublish(game, WordsOf(ns.realm).rankPub[game])
	Roles.PublishRepeating()
	return true
end

local function OnPublish(dist, sender, mode, body)
	if dist ~= "CHANNEL" or mode ~= "L" then return end
	local letter, on, at = tostring(body or ""):match("^([abl])~([01])~(%d+)$")
	local game = letter and Roles.LETTER_GAME[letter]
	at = at and #at <= 12 and tonumber(at) or nil
	if not game or not at or at > Now() + ns.King.DATE_AHEAD then return end
	local M = ns.Moderation
	if M and not M.missing and M.Hides and M.Hides(sender) then return end
	local realm = ns.Arena.RealmOf(sender)
	if not Roles.MayPublish(sender, game, realm) then
		return ns.Log("rankings: %s's word for %s ignored: not a publisher", tostring(sender), game)
	end
	TakePublish(sender, game, on == "1", at, realm)
end
ns.Comm.Handle("AU", ns.Arena.Handle("AU", OnPublish))

-- The giver's client repeats its own words for late logins (every REPEAT), and the King his delay
-- while it is on: that client is involved (the weight rule), nobody else's.
local function Own()
	local words, out = WordsOf(ns.realm), {}
	for kind in pairs(LETTER) do
		local w = words[kind]
		if type(w) == "table" and Same(w.from, ns.me) then out[#out + 1] = kind end
	end
	table.sort(out)
	return out
end
-- The delay the King typed on this account (Arena.SetDelay keeps it in ns.db.arenaUI), 0 when none.
local function StoredDelay()
	local ui = ns.db and ns.db.arenaUI
	local d = type(ui) == "table" and tonumber(ui.delay) or 0
	return math.max(0, math.min(Roles.DELAY_MAX, math.floor(d)))
end
-- The delay word this client gave, while on (at login the guild may not say yet that it is the King's).
local function OwnDelayWord()
	local d = WordsOf(ns.realm).kingDelay
	return type(d) == "table" and Same(d.from, ns.me) and (tonumber(d.delay) or 0) > 0
end
local function KingDelayOn()
	return ns.King.IsKing() and (OwnDelayWord() or StoredDelay() > 0)
end
function Roles.Repeat()
	if not MaySend() then return Roles.Repeating() end
	if not ns.King.SetsLists() then return Roles.Repeating() end
	for _, kind in ipairs(Own()) do Resend(kind) end
	if ns.King.IsKing() then
		local want, d = StoredDelay(), WordsOf(ns.realm).kingDelay
		if want > 0 and not (OwnDelayWord() and tonumber(d.delay) == want) then
			-- The word itself was lost (or another delay kept): published again from what he typed.
			Roles.SendDelay(want)
		elseif OwnDelayWord() then
			d.heard = Now()
			SendDelayWord(d)
		end
	end
	return Roles.Repeating()
end
-- force: at login, before the guild says whether this is still the King's or a Steward's client
-- (the next repeat asks again).
function Roles.Repeating(force)
	local on = MaySend() and (force or ns.King.SetsLists()) and (Own()[1] ~= nil or KingDelayOn()
		or (force and (OwnDelayWord() or StoredDelay() > 0))) or false
	ns.Arena.Involve("roles", on)
	ns.Arena.Every(Roles.REPEAT, "roles repeat", on and Roles.Repeat or nil)
	return on
end
Roles.LOGIN_REPEAT = 60     -- a client that gives words says them this long after login, then every REPEAT

ns.On("LOGIN", function()
	-- Only a client holding words it gave itself (a King's or a Steward's), or the King's delay he
	-- typed (kept on his account), repeats them: first a minute after login, when the guild says
	-- whose client this is.
	if Roles.Repeating(true) then ns.Arena.After(Roles.LOGIN_REPEAT, "roles login repeat", Roles.Repeat) end
	-- A client whose publish word stands repeats it too, once the guild says who it is.
	local w = WordsOf(ns.realm).rankPub
	for _, g in ipairs(Roles.RANK_GAMES) do
		local e = type(w) == "table" and w[g]
		if type(e) == "table" and Same(e.from, ns.me) then
			ns.Arena.After(Roles.LOGIN_REPEAT, "rankings login repeat", Roles.PublishRepeat)
			break
		end
	end
end)
