local ADDON, ns = ...

-- 1.2, the Blood Arena: ArenaProfile.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Profiles (AP), nicknames from fixed lists, emblem, the history switch, follows, the frame and
-- title pick. Registers AP (sent in L whatever the live switch: Arena.LIVE_EXEMPT).
-- API (the design): Mine(), SetNick(a, n), SetEmblem(icon), SetPublic(on), SetPick(frame, title),
--   Of(gk|name), Card(gk|name) (the fighter card's view model, each value with its source tag),
--   NickText(nick), Follow(gk, on)
-- The person card's rows go through UI.personRows (the title, "Arena profile").
local ArenaProfile = {}
ns.ArenaProfile = ArenaProfile

-- A fighter's profile (the design): only public-safe fields. The nickname comes from two
-- fixed lists (32 x 32 epithets: nobody can put words of his choosing on the King's screen), the
-- emblem from the game's icons (ns.CouncilIconValue), the history public or private (a Consent
-- line), and the honour pick (one frame and one title besides the Olympus rank), which every
-- viewer checks himself (HonorsNet.Verified): a pick is only a wish.
--   AP: gk~class~raceID~sex~level~nick a.n~emblem~pub~frame~title~t
-- Sent by the character itself on the channel: at login and every hour only with a pick that is
-- not the default or arena activity (the design), on a change, and on AQ~P. Taken when the
-- server-stamped sender is the character its gk names (a unit token, or GetPlayerInfoByGUID once
-- it answers: the design); until then "unverified": its name-based honours only, never a belt by
-- GUID. Kept in the companion's heavy tables (the full profile) and, in the core, only the pick.

local L = ns.L
local P = ArenaProfile
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

P.RATE = 300               -- an AP taken from a sender at most every 5 minutes...
P.RATE_CHANGED = 60        -- ...or a minute after the last when it says something new
P.REPEAT = 3600            -- a pick not the default goes out again every hour
P.LOGIN_DELAY = 60
P.PICKS_MAX = 500          -- the verified picks the core keeps
P.PROFILES_MAX = 3000      -- the heavy profiles
P.FOLLOW_MAX = 50
P.EPITHETS = 32
P.FORMERLY = 3

local stats = { refused = {}, taken = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function P.Stats() return stats end

local function Now() return Arena.Now() end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Key(name) return type(name) == "string" and name ~= "" and ns.FullName(name):lower() or nil end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end
local function Secret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end
local function Gender(v)
	v = tonumber(v)
	return (v == 2 or v == 3) and v or nil
end

---------------------------------------------------------------------------
-- Nicknames and emblems
---------------------------------------------------------------------------

-- "a.n" (1-32 each; "0.0" none) as this client's own lists write it, or nil.
function P.NickText(nick)
	if type(nick) ~= "string" then return nil end
	local a, n = nick:match("^(%d+)%.(%d+)$")
	a, n = tonumber(a), tonumber(n)
	if not a or not n or a < 1 or n < 1 or a > P.EPITHETS or n > P.EPITHETS then return nil end
	local listA, listN = rawget(L, "ARENA_EPI_A"), rawget(L, "ARENA_EPI_N")
	local A, Nn = type(listA) == "table" and listA[a], type(listN) == "table" and listN[n]
	if type(A) ~= "string" or type(Nn) ~= "string" then return nil end
	local fmt = rawget(L, "ARENA_EPI_FMT") or "the %s %s"
	-- (The language's word order: Lua's format takes no positional %2$s.)
	if rawget(L, "ARENA_EPI_ORDER") == "na" then return fmt:format(Nn, A) end
	return fmt:format(A, Nn)
end
local function Nick(s)
	if s == "0.0" or s == "-" then return nil end
	return P.NickText(s) and s or nil
end

---------------------------------------------------------------------------
-- This character's own profile (ns.db.arenaProfile, account-wide, per character)
---------------------------------------------------------------------------

-- make: made when missing (a setter's); a read never writes saved data (an idle client keeps none).
function P.Mine(make)
	local db = ns.db
	if not db then return {} end
	if type(db.arenaProfile) ~= "table" then
		if not make then return {} end
		db.arenaProfile = {}
	end
	local mine = db.arenaProfile[ns.me]
	if type(mine) ~= "table" then
		if not make then return {} end
		mine = {}
		db.arenaProfile[ns.me] = mine
		-- 50 characters at most: the one heard of least recently goes.
		local n, oldest, at = 0, nil, math.huge
		for name, x in pairs(db.arenaProfile) do
			n = n + 1
			local t = type(x) == "table" and tonumber(x.at) or 0
			if name ~= ns.me and t < at then oldest, at = name, t end
		end
		if n > 50 and oldest then db.arenaProfile[oldest] = nil end
	end
	return mine
end

-- The pick as Honors takes it: { frame, title, seen, locked }.
function P.Pick()
	local m = P.Mine()
	return { frame = m.frame or "rank", title = m.title, seen = m.seen, locked = m.locked }
end
local function SavePick(pick)
	local m = P.Mine(true)
	m.frame = pick.frame ~= "rank" and pick.frame or nil
	m.title = pick.title
	m.seen = pick.seen
	m.locked = pick.locked or nil
	m.at = Now()
end
P.SavePick = SavePick

-- Whether the pick is the default (the rank's frame, no title): an idle client's case.
function P.DefaultPick()
	local m = P.Mine()
	return (m.frame == nil or m.frame == "rank") and m.title == nil
end

local Send -- (below)

function P.SetNick(a, n)
	a, n = tonumber(a), tonumber(n)
	local m = P.Mine(true)
	if a == 0 and n == 0 then m.nick = nil
	elseif not P.NickText(("%d.%d"):format(a or -1, n or -1)) then return false, "nick"
	else m.nick = ("%d.%d"):format(a, n) end
	m.at = Now()
	Send(true)
	Arena.Changed()
	return true
end

function P.SetEmblem(icon)
	local m = P.Mine(true)
	if icon == nil or icon == false then m.emblem = nil
	else
		local v = ns.CouncilIconValue(icon)
		if not v then return false, "emblem" end
		m.emblem = v
	end
	m.at = Now()
	Send(true)
	Arena.Changed()
	return true
end

-- The history switch (the design): public or private; unanswered is private.
function P.SetPublic(on)
	local m = P.Mine(true)
	m.pub = on and true or false
	m.at = Now()
	Send(true)
	ns.Fire("CONSENT_CHANGED", "arenaHistory", m.pub)
	Arena.Changed()
	return true
end

-- The frame and title picked (checked against the honours held here: Honors.Choose), sent.
function P.SetPick(frame, title)
	local H = ns.HonorsNet
	local held = H and H.Holdings and H.Holdings(ns.me, P.MyGk()) or {}
	local pick, why = ns.Honors.Choose(P.Pick(), held, frame or "rank", title)
	if not pick then return false, why end
	SavePick(pick)
	Send(true)
	ns.Fire("HONORS_CHANGED", ns.me)
	Arena.Changed()
	return true
end
function P.SetLocked(on)
	local m = P.Mine(true)
	m.locked = on and true or nil
	Arena.Changed()
	return true
end

-- Follow a fighter (the design): 50 at most, account-wide.
function P.Follow(gk, on, name)
	if not Gk(gk) then return false, "gk" end
	local db = ns.db
	db.arenaFollow = type(db.arenaFollow) == "table" and db.arenaFollow or {}
	if on then
		local n = 0
		for _ in pairs(db.arenaFollow) do n = n + 1 end
		if not db.arenaFollow[gk] and n >= P.FOLLOW_MAX then return false, "full" end
		db.arenaFollow[gk] = name or (P.Of(gk) or {}).name or true
	else
		db.arenaFollow[gk] = nil
	end
	Arena.Changed()
	return true
end
function P.Following(gk)
	local f = ns.db and ns.db.arenaFollow
	if gk then return type(f) == "table" and f[gk] ~= nil end
	return type(f) == "table" and f or {}
end

function P.MyGk()
	local g = UnitGUID and UnitGUID("player")
	if Secret(g) then return nil end
	return Arena.GK(g)
end

---------------------------------------------------------------------------
-- The wire: AP
---------------------------------------------------------------------------

-- (1.2.0: a secret value counts as unknown, never a table key or a number.)
local function Plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function Facts()
	local classFile
	if UnitClass then classFile = Plain(select(2, UnitClass("player"))) end
	local raceID
	if UnitRace then raceID = Plain(select(3, UnitRace("player"))) end
	local R = ns.Roster
	local sex = UnitSex and Plain(UnitSex("player"))
	return (type(classFile) == "string" and R and R.ClassCode and R.ClassCode(classFile)) or "-", tonumber(raceID), sex and Gender(sex) or nil,
		UnitLevel and tonumber(Plain(UnitLevel("player"))) or nil
end

function P.Body()
	local m = P.Mine()
	local class, race, sex, level = Facts()
	return table.concat({ P.MyGk() or "-", class ~= "" and class or "-", race and tostring(race) or "-", sex and tostring(sex) or "-",
		level and tostring(level) or "-", m.nick or "0.0", m.emblem and tostring(m.emblem) or "-", m.pub and "1" or "0",
		m.frame or "-", m.title or "-", B36(Now()) }, "~")
end

local lastSent = -math.huge
Send = function(force, to)
	if not ns.IsMember() then return false, "guild" end
	if not force and Now() - lastSent < P.RATE then return false, "rate" end
	lastSent = Now()
	return Arena.Send("AP", "L", P.Body(), { to = to, key = to and nil or "ap" })
end
P.Send = function(force, to) return Send(force, to) end

-- A sender is the character a gk names: a unit token for that GUID gives his name, or the game's
-- GetPlayerInfoByGUID once it answers (it may give nothing yet: nil, ask again later).
-- true, false (another character), or nil (not known yet).
function P.VerifyGk(sender, gk)
	local guid = Arena.GuidOf(gk or "")
	if not guid then return false end
	local who = ns.FullName(sender):lower()
	if type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and token and not Secret(token) then
			local name = ns.UnitFullName(token)
			if type(name) == "string" and not Secret(name) then return ns.FullName(name):lower() == who end
		end
	end
	if type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) and not Secret(realm) then
			-- (The name rebuilt as ns.UnitFullName does: the realm the game gives, ours when none.)
			local full = ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)
			return full:lower() == who
		end
	end
	return nil
end

local function Picks(make)
	local s = Arena.Store("L")
	if not s then return nil end
	if type(s.picks) ~= "table" then
		if not make then return nil end
		s.picks = {}
	end
	return s.picks
end
local function Profiles()
	local h = Arena.Heavy("L")
	if not h then return nil end
	if type(h.profiles) ~= "table" then h.profiles = {} end
	return h.profiles
end

-- An AP heard (or our own, kept as a viewer keeps it).
function P.Take(sender, body)
	local gk, class, race, sex, level, nick, emblem, pub, frame, title, t = Arena.Fields(body, 11)
	if not t then return Count("shape") end
	gk = Gk(gk)
	local key = Key(sender)
	local now = Now()
	local picks = Picks(true)
	local had = picks and picks[key]
	local p = { name = ns.FullName(sender), gk = gk, class = class ~= "-" and class:sub(1, 2) or nil, race = tonumber(race), sex = Gender(sex),
		level = tonumber(level), nick = Nick(nick), emblem = emblem ~= "-" and ns.CouncilIconValue(emblem) or nil, pub = pub == "1",
		frame = frame ~= "-" and frame:match("^[%l%d%-]+$") and #frame <= 40 and frame or "rank", title = title ~= "-" and title:match("^[%l%d%-]+$")
		and #title <= 40 and title or nil, t = N(t, 0, 4294967295) or now, heard = now }
	if p.t > now + 60 then return Count("time") end
	if had and had.heard then
		local changed = had.frame ~= p.frame or had.title ~= p.title or had.nick ~= p.nick or had.emblem ~= p.emblem or had.pub ~= p.pub
		local gap = now - had.heard
		if gap < P.RATE and not (changed and gap >= P.RATE_CHANGED) then return Count("rate") end
	end
	local verified = gk and P.VerifyGk(sender, gk)
	if verified == false then return Count("gk") end
	p.verified = verified == true
	-- A name the ledger ties to another gk is refused unless the game confirms a rename.
	if not p.verified then p.gk = nil end
	if picks then
		picks[key] = { name = p.name, gk = p.gk, frame = p.frame, title = p.title, pub = p.pub, nick = p.nick, emblem = p.emblem, t = p.t,
			heard = now, verified = p.verified or nil, class = p.class, race = p.race, sex = p.sex, level = p.level }
		local n, oldest, at = 0, nil, math.huge
		for k, x in pairs(picks) do n = n + 1 if (x.heard or 0) < at then oldest, at = k, x.heard or 0 end end
		if n > P.PICKS_MAX and oldest then picks[oldest] = nil end
	end
	local profiles = Profiles()
	if profiles then
		local pk = p.gk or key
		local old = profiles[pk]
		if old and old.name and not Same(old.name, p.name) then
			p.formerly = old.formerly or {}
			table.insert(p.formerly, 1, old.name)
			while #p.formerly > P.FORMERLY do table.remove(p.formerly) end
		elseif old then
			p.formerly = old.formerly
		end
		profiles[pk] = p
	end
	stats.taken = stats.taken + 1
	ns.Fire("HONORS_CHANGED", p.name)
	Arena.Changed()
	return true
end

local function OnProfile(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	P.Take(sender, body)
end
ns.Comm.Handle("AP", ns.Arena.Handle("AP", OnProfile))

-- AQ~P: our own profile again, to whoever opened it.
function P.Answer(sender, gk)
	if gk ~= P.MyGk() then return false end
	Send(true, sender)
	return true
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- A profile by gk or name: the heavy one when the companion is loaded, else the core's pick.
function P.Of(x)
	if type(x) ~= "string" then return nil end
	if Same(x, ns.me) then
		local m = P.Mine()
		local class, race, sex, level = Facts()
		return { name = ns.me, gk = P.MyGk(), nick = m.nick, emblem = m.emblem, pub = m.pub == true, frame = m.frame or "rank", title = m.title,
			class = class, race = race, sex = sex, level = level, verified = true, own = true }
	end
	local profiles = Profiles()
	if Gk(x) then
		if profiles and profiles[x] then return profiles[x] end
		for _, p in pairs(Picks() or {}) do if p.gk == x then return p end end
		return nil
	end
	local key = Key(x)
	local picks = Picks()
	local p = picks and picks[key]
	if profiles then
		if p and p.gk and profiles[p.gk] then return profiles[p.gk] end
		if profiles[key] then return profiles[key] end
	end
	return p
end
function P.IsPublic(gk)
	if gk == P.MyGk() then return P.Mine().pub == true end
	local p = P.Of(gk)
	return p ~= nil and p.pub == true
end

-- The fighter card's view model (the design): each value { v, src }, src "seen" (a unit, a
-- weigh-in), "arbiter" (the arbiter's), "ledger", "own" (the fighter's own word, grey).
local function GuildFacts(name)
	if type(name) ~= "string" or name == "" then return nil, nil end
	if Same(name, ns.me) and type(GetGuildInfo) == "function" then
		local ok, guild, rank = pcall(GetGuildInfo, "player")
		if ok and not Secret(guild) and not Secret(rank) then
			return type(guild) == "string" and guild ~= "" and guild or nil,
				type(rank) == "string" and rank ~= "" and rank or nil
		end
	end
	local guild
	local M = ns.Moderation
	if type(M) == "table" and type(M.GuildOf) == "function" then
		local ok, value = pcall(M.GuildOf, name)
		if ok and not Secret(value) and type(value) == "string" and value ~= "" then guild = value end
	end
	-- A rank name is available for another character only in our server roster. A numeric census
	-- rank cannot be turned back into a name without guessing, so it deliberately stays unknown.
	local R = ns.Roster
	for _, row in ipairs(type(R) == "table" and type(R.members) == "table" and R.members or {}) do
		local rowName = row.full or row.name
		if Same(rowName, name) then
			if not guild and type(R.guild) == "string" and R.guild ~= "" then guild = R.guild end
			local rank = not Secret(row.rank) and type(row.rank) == "string" and row.rank ~= "" and row.rank or nil
			return guild, rank
		end
	end
	return guild, nil
end

function P.Card(x)
	local p = P.Of(x)
	local name = p and p.name or (not Gk(x) and x) or nil
	local gk = p and p.gk or (Gk(x) and x) or nil
	if not name and not gk then return nil end
	local LG = ns.ArenaLedger
	local H = ns.HonorsNet
	local function V(v, src) if v == nil then return nil end return { v = v, src = src } end
	local gender = p and Gender(p.sex)
	local card = { name = V(name, "own"), gk = gk, nick = V(p and P.NickText(p.nick), "own"), emblem = V(p and p.emblem, "own"),
		class = V(p and p.class, "own"), race = V(p and p.race, "own"), gender = V(gender, "own"), sex = V(gender, "own"),
		level = V(p and p.level, "own"), formerly = p and p.formerly,
		pub = p and p.pub == true, verified = p and p.verified == true }
	local guild, guildRank = GuildFacts(name)
	card.guild, card.guildRank = V(guild, "seen"), V(guildRank, "seen")
	if gk and LG then
		local rec = LG.Record and LG.Record(gk)
		if rec and rec.fights and (rec.fights > 0 or rec.woWins > 0) then
			card.record = V({ wins = rec.wins, losses = rec.losses, fled = rec.fled, ko = rec.koWins, wo = rec.woWins, streak = rec.streak }, "ledger")
			card.rating = V(rec.rating, "ledger")
			card.peak = V(rec.peak, "ledger")
			if rec.class then card.class = V(rec.class, "ledger") end
			if rec.race then card.race = V(tonumber(rec.race) or rec.race, "ledger") end
		end
		card.tier = V(LG.Tier and LG.Tier(gk), "ledger")
		card.belts = V(LG.BeltOf and LG.BeltOf(gk), "ledger")
	end
	if H and H.Verified and name then
		local v = H.Verified(name, gk and Arena.GuidOf(gk))
		if type(v) == "table" then
			card.frame, card.title, card.mark = V(v.frame, "verified"), V(v.title and H.TitleText(v.title), "verified"), V(v.mark, "verified")
			card.honour = V(type(v.honour) == "table" and v.honour.key or nil, "verified")
		end
	end
	card.following = gk and P.Following(gk) or false
	return card
end

-- Whether this client should say its profile: a pick that is not the default, or arena activity
-- this season (a fight of its own).
function P.Active()
	if not P.DefaultPick() then return true end
	local s = Arena.Store("L")
	local mine = s and type(s.myFights) == "table" and s.myFights[ns.me]
	local LG = ns.ArenaLedger
	local start = LG and LG.Season and LG.Season("L").start or 0
	for _, e in ipairs(mine or {}) do if (e.t or 0) >= start then return true end end
	return false
end

-- The honours exemption of the weight rule (the design): one AP timer while the pick is not
-- the default (ns.Every: no arena ticker), none otherwise.
local repeater
function P.Repeating()
	local on = ns.IsMember() and P.Active()
	if on and not repeater then
		repeater = ns.Every(P.REPEAT, "arena profile", function() Send(true) end)
	elseif not on and repeater then
		if repeater.Cancel then repeater:Cancel() end
		repeater = nil
	end
	return on
end
ns.On("LOGIN", function()
	if P.Repeating() then ns.After(P.LOGIN_DELAY, "arena profile login", function() Send(true) end) end
end)
ns.On("HONORS_CHANGED", function(name) if name == nil or Same(name, ns.me) then P.Repeating() end end)

---------------------------------------------------------------------------
-- The history's Consent line, and the person card's rows
---------------------------------------------------------------------------

do
	local C = rawget(ns, "Consent")
	if type(C) == "table" and type(C.Register) == "function" then
		C.Register({
			key = "arenaPresentation", section = "profile", focusOnly = true, readonly = true,
			label = "CONSENT_PROFILE_PRESENTATION", text = "CONSENT_PROFILE_PRESENTATION_TEXT",
			shown = function() return not Arena.Off() and Arena.companionRefused ~= "version" end,
			status = function() return P.Active() and "shared" or "local" end,
		})
		C.Register({
			key = "arenaHistory", section = "profile", label = "ARENA_CONSENT_HISTORY", text = "ARENA_CONSENT_HISTORY_TEXT",
			get = function()
				local m = ns.db and ns.db.arenaProfile and ns.db.arenaProfile[ns.me]
				if type(m) ~= "table" or m.pub == nil then return nil end
				return m.pub == true
			end,
			set = function(on) P.SetPublic(on) end,
			-- It never opens the privacy page by itself; it shows once the arena does.
			pending = function() return false end,
			shown = function() return ns.IsMember() and not Arena.Off() end,
		})
	end
end

-- The person card (UI.ShowPerson): the honour title after the rank ("Rank · Title"), and a line
-- for the arena when the ledger or a profile knows the name; on the player's own card, "Edit my
-- profile" (ProfileEdit, in this window).
function P.PersonRows(p, rows)
	if type(p) ~= "table" or type(p.name) ~= "string" then return end
	if Arena.Off() or Arena.companionRefused == "version" then return end
	local full = ns.FullName(p.name, p.realm)
	local H = ns.HonorsNet
	local v = H and H.Verified and H.Verified(full)
	local title = v and v.title and H.TitleText(v.title)
	if title then
		local rankRow = p.rank and #rows
		if rankRow and rankRow > 0 and type(rows[rankRow]) == "string" and rows[rankRow]:find(ns.Codec.Plain(p.rank), 1, true) then
			rows[rankRow] = "|cffffd200" .. ns.Codec.Plain(p.rank) .. " · " .. title .. "|r"
		else
			rows[#rows + 1] = "|cffffd200" .. title .. "|r"
		end
	end
	local prof = P.Of(full)
	local gk = prof and prof.gk
	local LG = ns.ArenaLedger
	local rec = gk and LG and LG.Record and LG.Record(gk)
	if rec and rec.fights and rec.fights > 0 then
		rows[#rows + 1] = L.ARENA_PERSON_LINE:format(rec.rating, rec.wins, rec.losses + rec.fled)
	elseif prof and not Same(full, ns.me) then
		rows[#rows + 1] = L.ARENA_PERSON_PROFILE
	end
end
do
	local UI = rawget(ns, "UI")
	if type(UI) == "table" and type(UI.personRows) == "table" then
		table.insert(UI.personRows, function(p, rows) P.PersonRows(p, rows) end)
	end
	if type(UI) == "table" and type(UI.profileEditors) == "table" then
		table.insert(UI.profileEditors, function(p, rows)
			if Arena.Off() or Arena.companionRefused == "version" then return nil end
			local PE = ns.ProfileEdit
			if type(PE) ~= "table" or type(PE.Open) ~= "function" then return nil end
			return function() PE.Open() end
		end)
	end
end

Arena.Action("profile.nick", nil, function(a, n) return P.SetNick(a, n) end)
Arena.Action("profile.emblem", nil, function(icon) return P.SetEmblem(icon) end)
Arena.Action("profile.public", nil, function(on) return P.SetPublic(on) end)
Arena.Action("profile.pick", nil, function(frame, title) return P.SetPick(frame, title) end)
Arena.Action("profile.lock", nil, function(on) return P.SetLocked(on) end)
Arena.Action("profile.follow", nil, function(gk, on, name) return P.Follow(gk, on, name) end)
Arena.Action("profile.ask", nil, function(name, gk) local LG = ns.ArenaLedger return LG and LG.Ask and LG.Ask("P", name, gk) end)
