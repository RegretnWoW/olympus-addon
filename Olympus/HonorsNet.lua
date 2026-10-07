local ADDON, ns = ...

-- 1.2, the Blood Arena: HonorsNet.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Level-race claims (IL), the donor holders' word (ID, also on GUILD from the Treasurer's own
-- client), the Oracle's (IO), the belt podium, and verification of a pick for any viewer through
-- Honors. Registers IL ID IO (sent in L whatever the live switch: Arena.LIVE_EXEMPT). The honours
-- exemption of the weight rule: PLAYER_LEVEL_UP (acting at a multiple of 10) and one AP timer while
-- the pick is not the default, through ns.On/ns.Every.
-- API (the design): Verified(name) -> { frame, title, mark, chat }, Holdings(name), FrameTexture(key),
--   MarkTexture(key), ChatMark(key), TitleText(key), Levels(), Donors(), Oracle(), Podium(cat);
--   NewPortrait(parent, size) and DressPortrait(rig, key): the player's own portrait with a frame.
-- The King's letter (the design) when an honour is earned: a popup of Olympus's own, queued.
local HonorsNet = {}
ns.HonorsNet = HonorsNet

-- One honours system for frames, nameplate marks, chat marks and titles (the design).
-- Every viewer works out what a player holds from his own facts (Honors.Holdings over the belts
-- and podium words, the level race's book, the Treasurer's donor word, a bank's Oracle word and the
-- census's best guild) and shows a player's pick only when it holds (Honors.Shown), else the rank's
-- frame: nobody can make another client show an honour he does not hold.
--
-- The words (the design, with its later changes):
--   IL gk~level~t                 the character itself, at PLAYER_LEVEL_UP to 20, 40 or 60 (the
--                                 design's level race: the FIRST to each), again 10 minutes and an
--                                 hour later, never once that milestone's place is known here. Each
--                                 client keeps the claim (timed when it first heard it) and counts it
--                                 vouched once a census report of another sender lists him at or
--                                 above that level (within 24 hours); only vouched claims take the
--                                 place, which never changes once recorded (Honors.LevelRace).
--   ID t~monthKey~m1,m2,m3~a1,a2,a3   names only: the month's top 3 donors and all time's (the
--                                 the design dropped the week's), from the Treasurer's characters'
--                                 client (or the King's), on the channel and on GUILD; the newest
--                                 wins; sent whatever the Treasury's ranking switches say.
--   IO monthKey~t~n1,n2,n3        the Oracle's gold, silver and bronze for that month, from a bank of
--                                 this realm's T1~B (the first open bank by sorted name); IO R~month~
--                                 rows by whisper: another bank's top 10 for it (name:profit:staked:
--                                 markets:first;...). The newest word for a month wins.
-- The podium (the belts' silver and bronze) is the clerk's AV 2 and 3 (ArenaLedger); the best guild
-- is the census's (Honors.GuildTop, its leader vouched by two senders).
--
-- A newly earned honour switches on by itself (Honors.Update, unless the player locked his pick),
-- and the King's letter tells him: a parchment of Olympus's own naming the honour and its title,
-- the new frame on his own portrait, "Wear it" and "Later"; queued when several come, re-readable
-- from the profile's Edit (ProfileEdit). Honours count only in the live arena (Arena.Counts).

local L = ns.L
local H = HonorsNet
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

H.MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
H.IL_AFTER = { 60, 600, 3600 }  -- IL this long after the level-up (and on AQ~H)
H.VOUCH_WINDOW = 86400          -- a census report this close to the claim vouches for it
H.CLAIMS_MAX = 200
H.CLAIM_DAYS = 7
H.DONOR_EVERY = 1800            -- the Treasurer's client says the donors again every 30 minutes
H.ORACLE_EVERY = 1800
H.LETTERS_MAX = 20
H.LETTER_PORTRAIT = 60          -- the letter's portrait: the size of his own on his unit frame
H.REFRESH_DELAY = 60            -- after login, the own honours looked at once the words came in
-- The start of the level race: the 1.2 release (a claim timed before it counts for nothing).
H.RACE_START = 1790812800

local stats = { refused = {}, claims = 0, vouched = 0, places = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function H.Stats() return stats end

local function Now() return Arena.Now() end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Short(name) return type(name) == "string" and ns.ShortName(ns.FullName(ns.Normal and ns.Normal(name) or name)):lower() or nil end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end
-- A GUID as Honors compares it: the game's form (a gk turned back).
local function GameGuid(g)
	if type(g) ~= "string" then return nil end
	if g:find("^Player%-") then return g end
	return Arena.GuidOf(g)
end
H.GameGuid = GameGuid

---------------------------------------------------------------------------
-- The core's honours store (this realm's live store: honours count only in L)
---------------------------------------------------------------------------

function H.Store(make)
	local s = Arena.Store("L")
	if not s then return nil end
	if type(s.honors) ~= "table" then
		if not make then return nil end
		s.honors = {}
	end
	local h = s.honors
	if make then
		h.levels = type(h.levels) == "table" and h.levels or {}
		h.claims = type(h.claims) == "table" and h.claims or {}
		h.oracle = type(h.oracle) == "table" and h.oracle or {}
	end
	return h
end

local gen = 0
local function Changed(name)
	gen = gen + 1
	ns.Fire("HONORS_CHANGED", name)
	Arena.Changed()
end
H.Changed = Changed
ns.On("DATA_CHANGED", function() gen = gen + 1 end)
ns.On("HONORS_CHANGED", function() gen = gen + 1 end)

---------------------------------------------------------------------------
-- What a player holds, and what his pick shows
---------------------------------------------------------------------------

-- The census's best guild, its leader vouched (two senders naming him guild master, Data.KnownRank;
-- our own guild: our roster).
local function BestGuild()
	local rows = ns.rdb and ns.rdb.guilds
	if type(rows) ~= "table" then return nil end
	local M = ns.Moderation
	local top = ns.Honors.GuildTop(rows, { faction = ns.faction or "Alliance", now = ns.Now(), skip = function(guild)
		if not ns.IsFederation(guild) then return true end
		return type(M) == "table" and not M.missing and M.Guild and M.Guild(guild) ~= nil
	end })
	if not top then return nil end
	local D = ns.Data
	local leader = ns.FullName(top.leader, rows[top.guild] and rows[top.guild].realm or nil)
	if type(D) == "table" and type(D.KnownRank) == "function" then
		local ok, rank, named = pcall(D.KnownRank, leader, top.guild)
		local mine = GetGuildInfo and GetGuildInfo("player")
		if not ok or rank ~= 0 or ((named or 0) < 2 and top.guild ~= mine) then return nil end
	end
	return top
end

local inputs, inputsGen, inputsAt
-- The facts every Holdings call takes (kept while nothing changed, a minute at most).
function H.Inputs()
	local now = Now()
	if inputs and inputsGen == gen and inputsAt == math.floor(now / 60) then return inputs end
	local LG = ns.ArenaLedger
	local store = H.Store()
	local donors = store and store.donors
	local oracle = store and store.oracle
	local lastMonth = ns.Honors.MonthOf(now) - 1
	local ow = oracle and oracle[lastMonth]
	local function Places(names)
		local out = {}
		for i, name in ipairs(names or {}) do out[i] = { name = name, place = i } end
		return out
	end
	local tiers = {}
	for gk, tier in pairs(LG and LG.Tiers and LG.Tiers("L") or {}) do
		tiers[gk] = tier
		local g = Arena.GuidOf(gk)
		if g then tiers[g] = tier end
	end
	inputs = {
		belts = LG and LG.Holders and LG.Holders("L") or {},
		podium = LG and LG.PodiumWords and LG.PodiumWords("L") or {},
		tiers = tiers,
		donors = donors and { all = Places(donors.all), month = Places(donors.month), monthNo = donors.monthNo } or nil,
		levels = store and store.levels or {},
		guild = BestGuild(),
		oracle = ow and { month = Places(ow.names), monthNo = lastMonth } or nil,
		now = now,
	}
	inputsGen, inputsAt = gen, math.floor(now / 60)
	return inputs
end

-- The player's guild as this client knows it: his unit's, our own's, the census's word on him.
local function GuildOf(name)
	if Same(name, ns.me) then return GetGuildInfo and GetGuildInfo("player") or nil end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.GuildOf then
		local ok, g = pcall(M.GuildOf, name)
		if ok and type(g) == "string" then return g end
	end
	return nil
end

-- Every honour `name` holds as this client sees it (guid: the game's or the arena's form, only
-- when known for sure: a unit's, or a verified profile's).
function H.Holdings(name, guid)
	if type(name) ~= "string" then return {} end
	return ns.Honors.Holdings({ name = name, guid = GameGuid(guid), guild = GuildOf(name) }, H.Inputs())
end

-- A player's pick as heard (or ours), and a GUID for him we are sure of.
local function PickOf(name)
	local P = ns.ArenaProfile
	if Same(name, ns.me) then return P.Pick(), P.MyGk() end
	local p = P.Of(name)
	if not p then return nil, nil end
	return { frame = p.frame or "rank", title = p.title }, p.verified and p.gk or nil
end

local cache, cacheGen, cacheHour = {}, -1, -1
-- What a player's pick shows to this client (the design): { frame (an honour key, "rank" or "none"),
-- title (an honour key or nil), mark (the honour's art, or "rank"), chat (the honour's art for a
-- chat mark, or nil), honour (the honour shown), art, shape, metal, milestone }.
-- guid: a unit's GUID (the Borders' and Nameplates'), which beats a profile's.
function H.Verified(name, guid)
	if type(name) ~= "string" or name == "" then return { frame = "rank", mark = "rank" } end
	local key = ns.FullName(name):lower() .. "|" .. tostring(guid)
	-- Kept while nothing changed, and never past the hour: the month's koi and ravens turn over with
	-- the clock alone (no word comes when a month ends).
	local hour = math.floor(Now() / 3600)
	if cacheGen ~= gen or cacheHour ~= hour then cache, cacheGen, cacheHour = {}, gen, hour end
	if cache[key] then return cache[key] end
	local pick, known = PickOf(name)
	local v = { frame = "rank", mark = "rank" }
	if pick then
		local held = H.Holdings(name, guid or known)
		local frame, mark, title, h = ns.Honors.Shown(pick, held)
		v.frame, v.mark, v.title, v.honour = frame, mark, title, h
		if h then v.art, v.shape, v.metal, v.milestone, v.chat = h.art, h.shape, h.metal, h.milestone, h.art end
	end
	cache[key] = v
	return v
end

-- The textures: a frame's (its shape too), its nameplate mark, its chat mark ("|T...|t", never a %).
function H.FrameTexture(key)
	local art, shape = ns.Honors.ArtOf(key)
	if not art then return nil end
	return H.MEDIA .. art, shape
end
function H.MarkTexture(key)
	local art = ns.Honors.ArtOf(key) or (type(key) == "string" and key:match("^[%l%-]+%-%l+$") and key) or nil
	if not art then return nil end
	return H.MEDIA .. art .. "-mark"
end
function H.ChatMark(key)
	local tex = H.MarkTexture(key)
	if not tex or tex:find("%", 1, true) then return nil end
	return "|T" .. tex .. ":0|t"
end

-- The player's own portrait with a frame on it, in the core's windows (the King's letter, the
-- profile's Edit, the Arena's own letter): Borders.NewPortrait, the builder of the Arena's
-- portraits too (1.2, the owner's ask: every Olympus portrait identical to his own on his unit
-- frame: the same picture, mask and ring, and the same art at the same offsets, turned round as
-- his own). `size` across; its slot is the square the window places, its reach how far its art
-- may reach past it (Borders.SizePortrait), for the window's words to keep clear. Where
-- Borders.lua is the core's stand-in, the picture alone, square, and no frame.
function H.NewPortrait(parent, size)
	local B = ns.Borders
	local rig = B.missing ~= true and B.NewPortrait(parent, size) or nil
	if type(rig) == "table" then return rig end
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetSize(size, size)
	return { slot = tex, portrait = tex, plain = true, reach = { left = 0, right = 0, top = 0, bottom = 0 } }
end
-- It filled: his live picture (square, as his unit frame asks SetPortraitTexture for it: the
-- rig's mask rounds it) and the frame `key` names: an honour's (its art, as round his own
-- portrait, Borders.ShowHonour; none where this client has no art for it), "rank" his rank's
-- border as his own frame works it out (Borders.TierOf), "none" or nil none. What shows:
-- "honour", "rank" or nil.
function H.DressPortrait(rig, key)
	if SetPortraitTexture then pcall(SetPortraitTexture, rig.portrait, "player", not rig.plain) end
	if rig.plain then return nil end
	local B = ns.Borders
	if type(key) == "string" and key ~= "rank" and key ~= "none" then
		if B.ShowHonour(rig, key) then return "honour" end
		B.ShowTier(rig, nil)
		return nil
	end
	local tier = key == "rank" and B.TierOf("player") or nil
	B.ShowTier(rig, tier)
	return tier and "rank" or nil
end
-- The arena division's crossed swords (a tier's badge): the game's icon and the metal's colour.
H.BADGE_ICONS = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Sword_27" }
H.METAL_COLOR = { gold = { 1, 0.82, 0 }, silver = { 0.78, 0.8, 0.85 }, bronze = { 0.62, 0.46, 0.34 } }
function H.BadgeTexture(tier)
	local UI = ns.UI
	local tex = type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(H.BADGE_ICONS) or H.BADGE_ICONS[1]
	return tex, H.METAL_COLOR[tier]
end

-- A title's words (the design; one locale table so the moderators can edit them).
local CLASS_FILE = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST", shaman = "SHAMAN",
	mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }
local RACE_ID = { human = 1, orc = 2, dwarf = 3, nightelf = 4, undead = 5, tauren = 6, gnome = 7, troll = 8 }
function H.TitleText(key)
	if type(key) ~= "string" then return nil end
	local fixed = L.HONOR_TITLES and L.HONOR_TITLES[key]
	if fixed then return fixed end
	local base, place = key:match("^(.-)%-([23])$")
	if not base then base, place = key, "1" end
	place = tonumber(place)
	local class = base:match("^arena%-class%-(%l+)$")
	if class then
		local names = LOCALIZED_CLASS_NAMES_MALE
		local name = (type(names) == "table" and names[CLASS_FILE[class] or ""]) or (L.HONOR_CLASS_NAMES and L.HONOR_CLASS_NAMES[class]) or class
		return (L.HONOR_CLASS_TITLE[place] or L.HONOR_CLASS_TITLE[1]):format(name)
	end
	local race = base:match("^arena%-race%-(%l+)$")
	if race then
		local name = L.HONOR_RACE_NAMES and L.HONOR_RACE_NAMES[race] or race
		local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
		if type(info) == "function" and RACE_ID[race] then
			local ok, r = pcall(info, RACE_ID[race])
			if ok and type(r) == "table" and type(r.raceName) == "string" then name = r.raceName end
		end
		return (L.HONOR_RACE_TITLE[place] or L.HONOR_RACE_TITLE[1]):format(name)
	end
	return nil
end
-- The honour's name in the list (the title, with its metal and what it is for).
function H.Label(key)
	local title = H.TitleText(key)
	local _, _, metal = ns.Honors.ArtOf(key)
	return title, metal
end

function H.Levels()
	local s = H.Store()
	return s and s.levels or {}
end
function H.Donors()
	local s = H.Store()
	return s and s.donors or nil
end
function H.Oracle(month)
	local s = H.Store()
	month = month or (ns.Honors.MonthOf(Now()) - 1)
	return s and s.oracle and s.oracle[month] or nil
end
-- A belt category's podium as this client holds it: { [2] = { gk, name }, [3] = ... }.
function H.Podium(cat)
	local out = {}
	local LG = ns.ArenaLedger
	for _, p in ipairs(LG and LG.PodiumWords and LG.PodiumWords("L") or {}) do
		if p.cat == cat then out[p.place] = { gk = p.gk, name = p.name } end
	end
	return out
end

---------------------------------------------------------------------------
-- The level race (IL, and the clerk's AB~H)
---------------------------------------------------------------------------

local function Placed(m)
	local s = H.Store()
	local list = s and s.levels and s.levels[m]
	return type(list) == "table" and list[1] ~= nil
end
H.Placed = Placed

-- Our own claim: sent at the level-up's moments, never once the place is known.
local claimed = {} -- [level] = t
function H.SendClaim(level)
	if Placed(level) then return false, "placed" end
	local gk = ns.ArenaProfile.MyGk()
	if not gk then return false, "gk" end
	local t = claimed[level] or Now()
	claimed[level] = t
	return Arena.Send("IL", "L", table.concat({ gk, B36(level), B36(t) }, "~"))
end
function H.OnLevelUp(level)
	level = tonumber(level)
	if not level or not ns.Honors.LEVEL_METAL[level] or Placed(level) then return end
	claimed[level] = claimed[level] or Now()
	for _, after in ipairs(H.IL_AFTER) do
		ns.After(after, "arena level claim", function() H.SendClaim(level) end)
	end
end

-- The honours exemption (the design): PLAYER_LEVEL_UP only on a character that can still
-- reach a milestone whose place is not known here.
local levelHooked = false
function H.WatchLevels()
	if levelHooked then return true end
	local level = UnitLevel and tonumber(UnitLevel("player")) or 60
	local open = false
	for _, m in ipairs(ns.Honors.MILESTONES) do if m > level and not Placed(m) then open = true end end
	if not open then return false end
	levelHooked = true
	ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel) ns.SafeCall("arena level up", H.OnLevelUp, newLevel) end)
	return true
end

-- Vouched: a census report of another sender lists him at or above that level, near the claim.
function H.Vouched(c)
	local rows = ns.rdb and ns.rdb.guilds
	if type(rows) ~= "table" then return false end
	local who = Short(c.name)
	for _, r in pairs(rows) do
		if type(r) == "table" and type(r.top) == "table" and type(r.reporterFull) == "string" and not Same(r.reporterFull, c.name)
			and math.abs((r.t or 0) - (c.heardLocal or 0)) <= H.VOUCH_WINDOW then
			for _, x in ipairs(r.top) do
				if type(x) == "table" and Short(x.name) == who and (tonumber(x.level) or 0) >= c.level then return true end
			end
		end
	end
	return false
end

-- The book again: the claims (vouched where they are) through Honors.LevelRace; a new place said.
-- A claim that can no longer be vouched (unvouched past VOUCH_WINDOW) stops holding the race up
-- (it stays until CLAIM_DAYS, so its sender can't claim that milestone again meanwhile); a gk that
-- several senders claim counts only for the one the game pairs it with (VerifyGk), else only
-- vouched claims of it count.
function H.RunRace()
	local s = H.Store(true)
	local claims = {}
	local now = Now()
	local P = ns.ArenaProfile
	local senders = {}
	for key, c in pairs(s.claims) do
		if now - (c.t or 0) > H.CLAIM_DAYS * 86400 then s.claims[key] = nil
		else
			if not c.vouched and H.Vouched(c) then c.vouched = true stats.vouched = stats.vouched + 1 end
			if c.vouched or ns.Now() - (c.heardLocal or 0) <= H.VOUCH_WINDOW then
				claims[#claims + 1] = { name = c.name, gk = c.gk, guid = GameGuid(c.gk), level = c.level, t = c.t, vouched = c.vouched }
				senders[c.gk] = senders[c.gk] or {}
				senders[c.gk][ns.FullName(c.name):lower()] = true
			end
		end
	end
	local kept = {}
	for _, c in ipairs(claims) do
		local n = 0
		for _ in pairs(senders[c.gk] or {}) do n = n + 1 end
		local ok = n <= 1
		if not ok then
			local verified = P and P.VerifyGk and P.VerifyGk(c.name, c.gk)
			if verified == true then ok = true
			elseif verified == nil then
				ok = c.vouched == true
				for other in pairs(senders[c.gk]) do
					if other ~= ns.FullName(c.name):lower() and P and P.VerifyGk and P.VerifyGk(other, c.gk) == true then ok = false end
				end
			end
		end
		if ok then kept[#kept + 1] = c end
	end
	claims = kept
	local book, fresh, pending = ns.Honors.LevelRace(s.levels, claims, now, { start = H.RACE_START })
	s.levels = book
	for _, p in ipairs(fresh) do
		stats.places = stats.places + 1
		Changed(p.name)
	end
	-- A vouched claim waits CONFIRM_AFTER: looked at again then.
	for _, list in pairs(pending or {}) do
		for _, c in ipairs(list) do
			if c.vouched then ns.After(ns.Honors.CONFIRM_AFTER + 1, "arena level race", H.RunRace) return fresh end
		end
	end
	return fresh
end

local function OnLevel(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	local gk, level, t = Arena.Fields(body, 3)
	if not t then return Count("shape") end
	gk, level = Gk(gk), N(level, 1, 60)
	if not gk or not level or not ns.Honors.LEVEL_METAL[level] then return Count("level") end
	if Placed(level) then return Count("placed") end
	local P = ns.ArenaProfile
	local ok = P.VerifyGk(sender, gk)
	if ok == false then return Count("gk") end
	local s = H.Store(true)
	-- One claim per sender and milestone, in his own name (never another's slot, nor a book filled
	-- by one sender); the book full, its oldest unvouched claim goes.
	local key = ns.FullName(sender):lower() .. ":" .. level
	local c = s.claims[key]
	if not c then
		local n, oldest = 0, nil
		for k, x in pairs(s.claims) do
			n = n + 1
			if not x.vouched and (not oldest or (x.t or 0) < (s.claims[oldest].t or 0)) then oldest = k end
		end
		if n >= H.CLAIMS_MAX then
			if not oldest then return Count("full") end
			s.claims[oldest] = nil
			Count("evicted")
		end
		-- Timed when this client first heard it (its clock, never the player's word).
		c = { gk = gk, name = ns.FullName(sender), level = level, t = Now(), heardLocal = ns.Now(), vouched = false }
		s.claims[key] = c
		stats.claims = stats.claims + 1
	end
	H.RunRace()
end
ns.Comm.Handle("IL", ns.Arena.Handle("IL", OnLevel))

-- A census report came in: the claims waiting are looked at again.
ns.On("DATA_CHANGED", function()
	local s = H.Store()
	if s and s.claims and next(s.claims) then
		for _, c in pairs(s.claims) do if not c.vouched then ns.SafeCall("arena level vouch", H.RunRace) return end end
	end
end)

-- The clerk's AB~H: the places this clerk holds (m:gk:name:t), taken for a milestone with no
-- place here (a place never changes once recorded).
function H.RecordsBody()
	local s = H.Store()
	local parts = {}
	for _, m in ipairs(ns.Honors.MILESTONES) do
		local p = s and s.levels and s.levels[m] and s.levels[m][1]
		local gk = p and Arena.GK(p.guid)
		if gk then parts[#parts + 1] = table.concat({ B36(m), gk, ns.ArenaFights.Wire(p.name), B36(p.t or 0) }, ":") end
	end
	return #parts > 0 and ("H~" .. table.concat(parts, ",")) or nil
end
function H.SendRecords()
	local body = H.RecordsBody()
	if body then Arena.Send("AB", "L", body, { key = "ab h", low = true }) end
end
function H.TakeRecords(sender, mode, rest)
	if mode ~= "L" then return end
	local s = H.Store(true)
	local any = false
	for part in tostring(rest):gmatch("[^,]+") do
		local m, gk, name, t = part:match("^([0-9a-z]+):([^:]+):([^:]+):([0-9a-z]+)$")
		m = N(m, 1, 60)
		if m and ns.Honors.LEVEL_METAL[m] and Gk(gk) and not Placed(m) then
			local full = ns.ArenaFights.Unwire(name, sender)
			if full then
				s.levels[m] = { { guid = Arena.GuidOf(gk), name = full, t = N(t, 0, 4294967295) or Now(), place = 1 } }
				any = true
				Changed(full)
			end
		end
	end
	return any
end
-- AQ~H: the clerk says the places; a claimant says his claim again.
function H.Answer(sender)
	local LG = ns.ArenaLedger
	if LG and LG.IsClerk and LG.IsClerk() then H.SendRecords() return true end
	for level in pairs(claimed) do if not Placed(level) then H.SendClaim(level) return true end end
	return false
end

---------------------------------------------------------------------------
-- The donors (ID)
---------------------------------------------------------------------------

-- The Treasurer's client works the donors out of his book (Treasury.DonationRecords, the money part's), by
-- Honors.Donors, and says the names.
function H.DonorWord()
	local T = ns.Treasury
	if type(T) ~= "table" or T.missing or type(T.DonationRecords) ~= "function" then return nil end
	local ok, records = pcall(T.DonationRecords)
	if not ok or type(records) ~= "table" then return nil end
	local s = H.Store(true)
	local D = ns.Dues
	local opts = { kept = s.donorsKept }
	if type(D) == "table" and not D.missing and type(D.Anchor) == "function" then
		local okA, a = pcall(D.Anchor)
		if okA then opts.anchor = a end
	end
	local r = ns.Honors.Donors(records, Now(), opts)
	s.donorsKept = { monthNo = r.monthNo, month = r.month, weekNo = r.weekNo, week = r.week }
	local function Names(list)
		local out = {}
		for i, d in ipairs(list or {}) do out[i] = ns.ArenaFights.Wire(d.name) end
		return out
	end
	return { monthNo = r.monthNo, month = Names(r.month), all = Names(r.all) }
end
local function IdBody(w, t)
	return table.concat({ B36(t), B36(w.monthNo), #w.month > 0 and table.concat(w.month, ",") or "-", #w.all > 0 and table.concat(w.all, ",") or "-" }, "~")
end
local lastId
function H.SendDonors(force)
	if not (ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)) and not ns.ArenaRoles.IsKing(ns.me) then return false, "who" end
	local w = H.DonorWord()
	if not w then return false, "book" end
	local sig = w.monthNo .. "|" .. table.concat(w.month, ",") .. "|" .. table.concat(w.all, ",")
	if sig == lastId and not force then return false, "same" end
	lastId = sig
	local body = IdBody(w, Now())
	H.TakeDonors(ns.me, body)
	Arena.Send("ID", "L", body, { key = "id" })
	if GetGuildInfo and GetGuildInfo("player") then Arena.Send("ID", "L", body, { dist = "GUILD", key = "id guild" }) end
	return true
end
function H.TakeDonors(sender, body)
	if not (ns.IsTreasurerCharacter(ns.FullName(sender)) or ns.ArenaRoles.IsKing(sender)) then return Count("sender") end
	local t, month, m, a = Arena.Fields(body, 4)
	if not a then return Count("shape") end
	t, month = N(t, 0, 4294967295), N(month, 0, 99999)
	if not t or not month or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	if s.donors and (s.donors.t or 0) >= t and not Same(sender, ns.me) then return Count("older") end
	local function Names(list)
		local out = {}
		if list ~= "-" then
			for name in list:gmatch("[^,]+") do
				local full = ns.ArenaFights.Unwire(name, sender)
				if full and #out < 3 then out[#out + 1] = full end
			end
		end
		return out
	end
	s.donors = { t = t, monthNo = month, month = Names(m), all = Names(a), from = ns.FullName(sender) }
	Changed()
	return true
end
local function OnDonors(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeDonors(sender, body)
end
ns.Comm.Handle("ID", ns.Arena.Handle("ID", OnDonors))

---------------------------------------------------------------------------
-- The Oracle (IO)
---------------------------------------------------------------------------

-- A bank's rows for a month (the markets' markets over its ledger: Honors.OracleScores' rows): a hook the
-- markets fill; none, and a bank says nothing.
H.oracleSource = function() return nil end
local whispered = {} -- [month] = { [bank] = rows }

function H.OracleBanks()
	local out = {}
	for _, b in ipairs(ns.ArenaRoles.Banks("L")) do if b.state == "o" then out[#out + 1] = b.name end end
	table.sort(out, function(x, y) return x:lower() < y:lower() end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, r in ipairs(rows) do
		if i > 10 then break end
		out[#out + 1] = table.concat({ ns.ArenaFights.Wire(r.name), tostring(r.profit), tostring(r.staked), tostring(r.markets), B36(r.first or 0) }, ":")
	end
	return table.concat(out, ";")
end

-- On a bank's client at the month's end: the first open bank publishes; the others whisper it
-- their top 10.
function H.OracleTick()
	if not ns.ArenaRoles.IsBank(ns.me, "L") then return false end
	local month = ns.Honors.MonthOf(Now()) - 1
	local ok, rows = pcall(H.oracleSource, month)
	if not ok or type(rows) ~= "table" then return false end
	local banks = H.OracleBanks()
	local first = banks[1]
	if not first then return false end
	local cur = ns.ArenaRoles.Currency()
	if not Same(first, ns.me) then
		local _, ranked = ns.Honors.Oracle(rows, { cur = cur })
		Arena.Send("IO", "L", "R~" .. B36(month) .. "~" .. RowsText(ranked or {}), { to = first })
		return true
	end
	local all = {}
	for _, r in ipairs(rows) do r.bank = ns.me all[#all + 1] = r end
	for bank, list in pairs(whispered[month] or {}) do
		for _, r in ipairs(list) do r.bank = bank all[#all + 1] = r end
	end
	local top = ns.Honors.Oracle(all, { cur = cur })
	local names = {}
	for i, r in ipairs(top) do names[i] = ns.ArenaFights.Wire(r.name) end
	local body = table.concat({ B36(month), B36(Now()), #names > 0 and table.concat(names, ",") or "-" }, "~")
	H.TakeOracle(ns.me, "CHANNEL", body)
	Arena.Send("IO", "L", body, { key = "io" })
	return true
end

function H.TakeOracle(sender, dist, body)
	if not ns.ArenaRoles.IsBank(sender, "L") then return Count("sender") end
	if dist == "WHISPER" then
		local kind, month, rows = Arena.Fields(body, 3)
		if kind ~= "R" or not rows then return Count("shape") end
		month = N(month, 0, 99999)
		if not month or not ns.ArenaRoles.IsBank(ns.me, "L") then return Count("bank") end
		local list = {}
		for part in rows:gmatch("[^;]+") do
			local name, profit, staked, markets, first = part:match("^([^:]+):(%-?%d+):(%d+):(%d+):([0-9a-z]+)$")
			local full = name and ns.ArenaFights.Unwire(name, sender)
			if full and #list < 10 then
				list[#list + 1] = { name = full, profit = tonumber(profit), staked = tonumber(staked), markets = tonumber(markets), first = N(first, 0, 4294967295) }
			end
		end
		whispered[month] = whispered[month] or {}
		whispered[month][ns.FullName(sender)] = list
		return true
	end
	local month, t, names = Arena.Fields(body, 3)
	if not names then return Count("shape") end
	month, t = N(month, 0, 99999), N(t, 0, 4294967295)
	if not month or not t or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	local had = s.oracle[month]
	if had and (had.t or 0) >= t and not Same(sender, ns.me) then return Count("older") end
	local list = {}
	if names ~= "-" then
		for name in names:gmatch("[^,]+") do
			local full = ns.ArenaFights.Unwire(name, sender)
			if full and #list < 3 then list[#list + 1] = full end
		end
	end
	s.oracle[month] = { t = t, names = list, from = ns.FullName(sender) }
	-- Two months kept.
	for m in pairs(s.oracle) do if type(m) == "number" and m < month - 1 then s.oracle[m] = nil end end
	Changed()
	return true
end
local function OnOracle(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeOracle(sender, dist, body)
end
ns.Comm.Handle("IO", ns.Arena.Handle("IO", OnOracle))

---------------------------------------------------------------------------
-- Our own honours: the automatic switch-on and the King's letter
---------------------------------------------------------------------------

-- The sources loaded (Honors.Update's known): a family is forgotten only once its source is here.
function H.Known()
	local LG = ns.ArenaLedger
	local s = H.Store()
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	local words = LG and LG.CoreT and LG.CoreT("L", "beltWords")
	local guilds = ns.rdb and ns.rdb.guilds
	local fresh = false
	for _, r in pairs(type(guilds) == "table" and guilds or {}) do
		if type(r) == "table" and r.t and ns.Now() - r.t <= ns.Honors.GUILD_MAX_AGE then fresh = true break end
	end
	return {
		belt = (titles and next(titles) ~= nil) or (words and next(words) ~= nil) or Arena.Heavy("L") ~= nil,
		tier = Arena.Heavy("L") ~= nil,
		donor = s ~= nil and s.donors ~= nil,
		level = s ~= nil and s.levels ~= nil and next(s.levels) ~= nil,
		guild = fresh,
		oracle = s ~= nil and s.oracle ~= nil and next(s.oracle) ~= nil,
	}
end

local refreshing = false
local letters = {} -- the queue shown now: { key, t }
-- Our honours looked at again: what is new switches on (unless locked) and gets its letter.
function H.Refresh()
	if refreshing or not ns.db or not ns.IsMember() then return end
	refreshing = true
	local P = ns.ArenaProfile
	local ok, err = pcall(function()
		local held = H.Holdings(ns.me, P.MyGk())
		local before = P.Pick()
		local first = before.seen == nil
		local pick, earned, lost = ns.Honors.Update(before, held, H.Known())
		-- Kept only when something is to remember (an idle client writes no profile).
		local same = pick.frame == before.frame and pick.title == before.title and #earned == 0 and #lost == 0
		if not same or (first and next(pick.seen or {}) ~= nil) then P.SavePick(pick) end
		local sent = false
		if pick.frame ~= before.frame or pick.title ~= before.title then
			P.Send(true)
			sent = true
		end
		for _, h in ipairs(earned) do
			if h.frame or h.title then H.QueueLetter(h.key) end
		end
		if sent or #earned > 0 then
			gen = gen + 1
			ns.Fire("HONORS_CHANGED", ns.me)
		end
		return first
	end)
	refreshing = false
	if not ok then error(err, 0) end
end

-- A letter queued (and kept, re-readable): shown now, or after the one open.
function H.QueueLetter(key)
	local P = ns.ArenaProfile
	local m = P.Mine(true)
	m.letters = type(m.letters) == "table" and m.letters or {}
	for _, x in ipairs(m.letters) do if x.key == key and not x.read then return end end
	m.letters[#m.letters + 1] = { key = key, t = Now() }
	while #m.letters > H.LETTERS_MAX do table.remove(m.letters, 1) end
	letters[#letters + 1] = { key = key, t = Now() }
	H.ShowLetter()
end
function H.Letters()
	local m = ns.ArenaProfile.Mine()
	return type(m.letters) == "table" and m.letters or {}
end

-- The family a letter speaks for (its text in L.HONOR_LETTER).
function H.LetterFamily(key)
	if type(key) ~= "string" then return nil end
	if key:find("^arena%-champion") then return "arena" end
	if key:find("^arena%-class%-") then return "class" end
	if key:find("^arena%-race%-") then return "race" end
	if key:find("^donor%-top%-") then return "donor-top" end
	if key:find("^donor%-month%-") then return "donor-month" end
	if key:find("^level%-race%-") then return "level" end
	if key:find("^oracle%-") then return "oracle" end
	if key == "guild-top-leader" then return "guild" end
	return nil
end
-- The letter's words: the King's, naming the honour and its title (never a real name).
function H.LetterText(key)
	local family = H.LetterFamily(key)
	local fmt = family and L.HONOR_LETTER and L.HONOR_LETTER[family]
	if not fmt then return nil end
	local title = H.TitleText(key) or key
	local _, _, metal = ns.Honors.ArtOf(key)
	local milestone = tonumber(key:match("^level%-race%-(%d+)$"))
	return fmt:format(title, milestone or (metal and L["HONOR_METAL_" .. metal:upper()] or "")), title
end

-- Under the gamepad UI nothing of Olympus opens by itself (the design: focus only on a
-- click): a letter waits for the player's own click, the next time the Olympus window
-- (H.WindowShown) or his profile's Edit opens (ProfileEdit.Open), and chat says once that one is
-- waiting.
function H.WaitForWindow()
	if not H.toldWaiting then
		H.toldWaiting = true
		ns.Print(L.HONOR_LETTER_WAITING)
	end
end
-- The Olympus window opened (UI.lua, its OnShow: the window is made on its first open, in either
-- look and either template, so nothing here can hook it beforehand): the letter waiting shows.
function H.WindowShown()
	if letters[1] then return H.ShowLetter(nil, true) end
	return false
end

local frame
-- The letter: a parchment of Olympus's own (the game's QuestBG), a wax seal, the new frame on the
-- player's own portrait, "Wear it" and "Later". Built on first use; never the game's popups.
-- key: a letter asked for (a click: shown at once); prompted: the player's click opened it.
function H.ShowLetter(key, prompted)
	if key then letters[#letters + 1] = { key = key, t = Now() } end
	local nextLetter = letters[1]
	if not nextLetter then return false end
	if frame and frame:IsShown() then return true end
	if not key and not prompted and ns.GamepadUI() then
		H.WaitForWindow()
		return false
	end
	H.toldWaiting = nil
	if InCombatLockdown and InCombatLockdown() then
		ns.After(5, "kings letter", function() H.ShowLetter(nil, prompted) end)
		return false
	end
	if not frame then
		frame = CreateFrame("Frame", "OlympusKingsLetter", UIParent)
		frame:SetSize(360, 300)
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		frame:SetFrameStrata("DIALOG")
		frame:EnableMouse(true)
		frame.bg = frame:CreateTexture(nil, "BACKGROUND")
		frame.bg:SetAllPoints()
		local UI = ns.UI
		frame.bg:SetTexture(type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(UI.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG" })
			or "Interface\\QuestFrame\\QuestBG")
		frame.head = frame:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
		frame.head:SetPoint("TOP", 0, -18)
		frame.head:SetText(L.HONOR_LETTER_HEAD)
		-- His own portrait with the honour's frame, as round his unit frame's (H.NewPortrait: 60, his
		-- frame's own size), its art clear of the edge, the head and the words.
		local rig = H.NewPortrait(frame, H.LETTER_PORTRAIT)
		local reach = rig.reach
		rig.slot:SetPoint("TOPLEFT", 16 + reach.left, -(38 + reach.top))
		frame.rig, frame.portrait = rig, rig.portrait
		frame.body = frame:CreateFontString(nil, "OVERLAY", "QuestFont")
		frame.body:SetPoint("TOPLEFT", 16 + reach.left + H.LETTER_PORTRAIT + reach.right + 10, -52)
		frame.body:SetPoint("RIGHT", -24, 0)
		frame.body:SetJustifyH("LEFT")
		frame.sign = frame:CreateFontString(nil, "OVERLAY", "QuestFont")
		frame.sign:SetPoint("BOTTOMRIGHT", -30, 52)
		frame.sign:SetText(L.HONOR_LETTER_SIGN)
		frame.seal = frame:CreateTexture(nil, "OVERLAY")
		frame.seal:SetSize(40, 40)
		frame.seal:SetPoint("BOTTOMLEFT", 26, 40)
		-- The game's own wax seal (its quest letters from the King, QuestInfo.lua), the faction's.
		local atlas = ns.faction == "Horde" and "Quest-Horde-WaxSeal" or "Quest-Alliance-WaxSeal"
		local info = C_Texture and C_Texture.GetAtlasInfo
		local okA, has = false, nil
		if type(info) == "function" then okA, has = pcall(info, atlas) end
		if okA and has then frame.seal:SetAtlas(atlas) else frame.seal:SetTexture("Interface\\Icons\\Spell_Holy_SealOfSacrifice") end
		local function Btn(label, x, fn)
			local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			b:SetSize(110, 24)
			b:SetPoint("BOTTOM", x, 14)
			b:SetText(label)
			b:SetScript("OnClick", fn)
			return b
		end
		frame.wear = Btn(L.HONOR_LETTER_WEAR, -60, function() H.CloseLetter(true) end)
		frame.later = Btn(L.HONOR_LETTER_LATER, 60, function() H.CloseLetter(false) end)
		ns.EscapeCloses("OlympusKingsLetter")
	end
	local text = H.LetterText(nextLetter.key)
	frame.key = nextLetter.key
	frame.body:SetText(text or "")
	H.DressPortrait(frame.rig, nextLetter.key)
	frame:Show()
	return true
end
-- "Wear it" (its frame and title picked) or "Later"; the next letter after it.
function H.CloseLetter(wear)
	local cur = table.remove(letters, 1)
	if frame then frame:Hide() end
	if cur then
		for _, x in ipairs(H.Letters()) do if x.key == cur.key then x.read = true end end
		if wear then
			local held = H.Holdings(ns.me, ns.ArenaProfile.MyGk())
			local frameKey, titleKey
			for _, h in ipairs(held) do
				if h.key == cur.key then frameKey, titleKey = h.frame, h.title end
			end
			if frameKey or titleKey then ns.ArenaProfile.SetPick(frameKey or ns.ArenaProfile.Pick().frame, titleKey) end
		end
	end
	-- (The next one after this click: the player's own.)
	if letters[1] then H.ShowLetter(nil, true) end
	return true
end
function H.LetterFrame() return frame end
function H.QueuedLetters() return letters end

---------------------------------------------------------------------------
-- The role clients' timers (the Treasurer's donors, a bank's Oracle), our own refresh
---------------------------------------------------------------------------

local donorTicker, oracleTicker
function H.WatchRoles()
	local treasurer = ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)
	if treasurer and not donorTicker then
		donorTicker = ns.Every(H.DONOR_EVERY, "arena donors", function() H.SendDonors(true) end)
		ns.After(60, "arena donors login", function() H.SendDonors(true) end)
	end
	local bank = ns.ArenaRoles.IsBank(ns.me, "L")
	if bank and not oracleTicker then
		oracleTicker = ns.Every(H.ORACLE_EVERY, "arena oracle", function() H.OracleTick() end)
	elseif not bank and oracleTicker then
		if oracleTicker.Cancel then oracleTicker:Cancel() end
		oracleTicker = nil
	end
end

ns.On("LOGIN", function()
	H.WatchLevels()
	H.WatchRoles()
	-- Our own honours whenever the realm's words change (HONORS_CHANGED, below); at login only where
	-- saved data already holds some (an idle client starts no timer: the weight rule).
	local LG = ns.ArenaLedger
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	if H.Store() or (titles and next(titles)) then
		ns.After(H.REFRESH_DELAY, "arena honours refresh", function() H.Refresh() end)
	end
end)
-- Our honours looked at again a moment after a change that may be ours (the realm's words, the
-- belts, our own), once for a burst.
local refreshDue = false
function H.RefreshSoon()
	if refreshDue or refreshing then return end
	refreshDue = true
	ns.After(2, "arena honours refresh", function() refreshDue = false H.Refresh() end)
end
ns.On("HONORS_CHANGED", function(name)
	if name == nil or Same(name, ns.me) then H.RefreshSoon() end
end)
ns.On("ARENA_CHANGED", function() H.WatchRoles() end)

Arena.Action("honors.letter", nil, function(key) return H.ShowLetter(key) end)
Arena.Action("honors.refresh", nil, function() return H.Refresh() end)
