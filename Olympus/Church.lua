local ADDON, ns = ...
local L = ns.L

-- The Missionary Church of Olympus (1.1.6): the Head of the Church, the Twelve Apostles, the
-- missionaries of their networks and each guild's Church correspondent. This file keeps the book
-- of who holds which place, the acts that change it, presence, the book's sync and the Church's
-- chat room. Counting the people they bring in is ChurchCount.lua's; the tab is ChurchView.lua's.
--
-- Who is who, as every client works it out from what it holds itself, never from a message:
-- - The roots: the author (Workshop.IsAuthorName) and Asmongold, the King and immutable Head of
--   the Church (ns.IsKingCharacter, with the existing faction and realm identity guards).
-- - The Twelve Apostles: the author's signed titles list names them in an entry of its own, one
--   per faction, with three "^" as the Steward's, so older clients leave it out unread:
--     ^apostles^<Alliance|Horde>^[*]<First Surname-Realm>,...     (Church.APOSTLES_MAX at most;
--   historical '*' remains readable but grants no Head authority)
--   It is the whole list as of its time: a root's acts in game change it only when newer.
-- - Missionaries: each under one parent, an Apostle or another missionary; the Apostle at the top
--   of his chain is his network. An Apostle or a missionary names missionaries under himself; a
--   root names one under the Apostle or missionary he picks. A parent names NAMES_PER at most (the
--   ones he adopted not counted), DEPTH_MAX levels below the Apostle, MISSIONARIES_MAX in all.
-- - One Church correspondent per Olympus guild, answering to the Head: named by that guild's guild
--   master or by a root; a new naming replaces the old one.
-- - The audience (the room, the tab, the numbers): the roots, the Apostles, the missionaries, the
--   correspondents and the High Council. The keepers (they serve the book and keep the ledger):
--   the Head, the Apostles and the author. The King's client does no background work beyond
--   handing his own acts to the keepers who were away (Church.DeliverActs).
--
-- A removal leaves a tombstone with the parent the person had. A missionary whose parent is a
-- tombstone climbs to that tombstone's parent; one whose parent holds no place and left no
-- tombstone (an Apostle a newer signed list left out, one this client never heard) is an orphan
-- under the Head. Both are marked for the Head's review. A cycle, a level past DEPTH_MAX or a
-- parent's quota or the total overflowed makes an entry invalid: it grants nothing (the Head's
-- own slot, where orphans and the ones he keeps sit, has no quota: the total bounds it). Every
-- client derives the same tree from the same entries, whatever order they came in (Church.State).
--
-- The wire. Every message is whole (never in pieces), at most 255 bytes, version 1. Clients before
-- 1.1.6 have no handler for these types and drop them unread (Comm.lua); a 1.1.6 client drops
-- any other version, kind or number of fields (Church.Stats().dropped).
--   NB~1~a~<op>~<role>~<target|->~<under|->~<guild|->~<at36>
--       an act, sent by the actor's own client on CHANNEL and GUILD, logged (his own word).
--       op: + names, - removes, k (a root) keeps an entry marked for review, m (a root) moves a
--       missionary under another parent. role: A (Apostle), M (missionary), C (correspondent; the
--       guild says which). under: the parent a root names or moves a missionary under. at36: the
--       server's clock, base 36. Each receiver checks the sender's power in its own book.
--       The same text again by WHISPER, from the actor's own client to each keeper it hears later
--       who was not heard when the act went out (OWN_ACT_KEEP at most, the newest act per place):
--       only a keeper takes it, as the act itself, with the same checks (Church.DeliverActs).
--   NB~1~s~<0|1>~<at36>      an authorized publisher's public ranking switch, CHANNEL/GUILD, logged
--   NB~1~q~<d1,...,d9>       an audience client asks one keeper (WHISPER) for the pages whose digest
--                            differs: P0..P7 (places and their tombstones by name), then C
--   NB~1~p~<kind>~<f1>~<f2>~<f3>~<f4>~<f5>~<at36>   one entry of a page, keeper -> asker (WHISPER):
--       A|M  <name>~<under|->~<actor>~<actor's role>~<since36|->  a place (since: when a kept or
--            moved missionary first held his place; "-" for any other)
--       X    <name>~<A|M>~<actor>~<actor's role>~<parent|->       a removal (tombstone)
--       C    <guild>~<name>~<actor>~<actor's role>~-              a correspondent
--       Y    <guild>~-~<actor>~<actor's role>~-                   a correspondent's removal
--       Entries on Apostles (A, X of an Apostle, and any entry for a name that is an Apostle in the
--       receiver's book) come only from a root's client (the author's or the Head's): an Apostle
--       can relay missionaries and correspondents, never change an Apostle's place.
--   NK~1~p~<role>~<book digest|->~<guild>~<switch|->   presence, CHANNEL and GUILD: role W K H A M
--       C N (N: a High Councillor); digests from keepers only; switches from keepers/publishers
--       (0 or 1 then its time, base 36). Only for whom to
--       whisper (the room, the desk) and who brought guildmates in: each receiver checks the role
--       in its own book. Actual publishers' switches are taken either way, and a closed one
--       from any keeper (closing is the private direction): a client that missed the publisher's
--       close learns it from the first keeper who heard it.

local Church = {}
ns.Church = Church

Church.PROTOCOL = 1
Church.APOSTLES_MAX = 12
Church.MISSIONARIES_MAX = 300
Church.NAMES_PER = 10          -- direct nominees of one parent (adopted ones not counted)
Church.DEPTH_MAX = 5           -- missionary levels below the Apostle
Church.CORRESPONDENTS_MAX = 64
Church.TOMBS_MAX = 200
Church.TOMB_KEEP = 30 * 86400  -- a tombstone no entry points to goes after this long
Church.DATE_AHEAD = 60         -- an act or entry dated later than this ahead of our clock is refused
Church.ACT_AGE = 86400         -- an act older than this is history: it comes with a page, not live
Church.ACTS_PER_MIN, Church.ACTS_PER_DAY = 6, 60
Church.PENDING_MAX, Church.PENDING_KEEP = 20, 30 * 60
Church.HEARD_MAX = 500
Church.KEEPER_EVERY, Church.MEMBER_EVERY = 300, 600 -- presence
Church.FRESH_FACTOR = 2.2
Church.ASK_GAP = 600           -- an audience client asks for pages this often at most
Church.ASK_AFTER, Church.ASK_SPREAD = 40, 40
Church.ASKED_WINDOW = 600      -- pages are taken from a keeper this long after we asked him
Church.ANSWER_GAP = 120        -- a keeper answers one asker this often at most
Church.TRANSFER_MAX = 150      -- entries one answer sends
Church.SEND_ROOM = 20          -- background sends leave this much room in Comm's queue
Church.ROOM_FANOUT = 30
Church.SWITCH_EVERY = 1800     -- the author's client repeats an open switch this often
Church.TICK = 30
Church.OWN_ACTS_MAX = 20       -- this client's own acts kept for the keepers who were away
Church.OWN_ACT_KEEP = 7 * 86400 -- for this long (well under TOMB_KEEP: an act never outlives a removal)
Church.DELIVER_PER_TICK = 2    -- own acts whispered to one keeper a tick (under his ACTS_PER_MIN)

Church.after = function(seconds, where, fn) ns.After(seconds, where, fn) end
Church.random = function(a, b) return math.random(a, b) end
Church.chance = function() return math.random() end

local ROLE_RANK = { W = 6, K = 5, H = 4, N = 4, A = 3, M = 2, G = 1 }
local AUDIENCE_ROLES = { W = true, K = true, H = true, A = true, M = true, C = true, N = true }
local KEEPER_ROLES = { W = true, H = true, A = true }
local PAGES = { "P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "C" }

local stats = { acts = 0, applied = 0, pages = 0, sent = 0, dropped = {} }
local rev = 0
local derived
local heard = {}         -- key -> { name, role, dig, guild, t }
local heardCount = 0
local actSeen = {}       -- sender|message -> t (an act heard on both lanes)
local actRate = {}       -- sender key -> { minute = {t...}, day, dayN }
local pending = {}       -- acts this client could not check yet
local asked = {}         -- keeper key -> when we asked him for pages
local answered = {}      -- asker key -> when we last answered him
local outgoing           -- the page entries on their way to one asker: { target, list, i }
local lastPresence, lastAsk, loginAt, lastSwitch = -math.huge, -math.huge, nil, -math.huge
local lastPrune = -math.huge
local sessionAt          -- this session's login (the LOGIN event), nil before it

local function Now() return ns.Now() end
-- The server's clock (the same second on every realm), else this computer's.
local function Clock()
	local D = ns.Data
	local t = D and D.ServerTime and D.ServerTime()
	return t or ns.Now()
end
Church.Clock = Clock

local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A person however a name reaches us: folded, no realm (Forever's names are one across a group).
local function Key(name)
	if type(name) ~= "string" or name == "" or name == "-" then return nil end
	local short = ns.ShortName(ns.Normal(name))
	if not short or short == "" then return nil end
	return ns.Fold(short)
end
Church.Key = Key

local B36 = function(n) return ns.Codec.Base36(n) end
local function UnB36(s)
	if type(s) ~= "string" or #s > 8 or not s:find("^[0-9a-z]+$") then return nil end
	return tonumber(s, 36)
end
Church.B36, Church.UnB36 = B36, UnB36

-- "First Surname-Realm" as it may travel: a character's name (letters, one space at most, 30 bytes)
-- and a realm of letters and digits (40 bytes); nil for anything else. A name without its realm is
-- ours.
local function WireName(s)
	s = Trim(s)
	if s == "" or s == "-" then return nil end
	s = ns.Normal(s)
	local short, realm = s:match("^([^%-]+)%-([^%-]+)$")
	short = short or s
	if #short > 30 or not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	if realm and (#realm > 40 or not realm:match("^[%w\128-\255]+$")) then return nil end
	return ns.FullName(short, realm)
end
Church.WireName = WireName

local function CleanGuild(s)
	s = Trim(tostring(s or ""):gsub("[~|%c]", ""))
	if s == "" or s == "-" or #s > 48 then return nil end
	return s
end
Church.CleanGuild = CleanGuild

local function OwnGuild()
	if not (IsInGuild and IsInGuild()) then return nil end
	local guild = GetGuildInfo and GetGuildInfo("player")
	return type(guild) == "string" and guild ~= "" and guild or nil
end
Church.OwnGuild = OwnGuild

local function Same(a, b) return Key(a) ~= nil and Key(a) == Key(b) end

---------------------------------------------------------------------------
-- Saved data (ns.rdb.church, one per realm group)
---------------------------------------------------------------------------

local function Store()
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	if type(r.church) ~= "table" then r.church = {} end
	return r.church
end
Church.Store = Store

local function Book()
	local c = Store()
	if not c then return nil end
	local b = c.book
	if type(b) ~= "table" or b.v ~= 1 or type(b.p) ~= "table" or type(b.x) ~= "table" or type(b.c) ~= "table" or type(b.cx) ~= "table" then
		b = { v = 1, p = {}, x = {}, c = {}, cx = {} }
		c.book = b
	end
	return b
end
Church.Book = Book

local function Changed()
	rev = rev + 1
	derived = nil
	ns.Fire("CHURCH_CHANGED")
end
Church.Changed = Changed

---------------------------------------------------------------------------
-- The roots and the signed Apostles
---------------------------------------------------------------------------

function Church.IsAuthor(name)
	local W = ns.Workshop
	return type(name) == "string" and type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(ns.FullName(name)) == true
end
function Church.IsKing(name)
	return type(name) == "string" and ns.IsKingCharacter and ns.IsKingCharacter(ns.FullName(name)) == true or false
end

-- Asmongold himself heads the Church. Resolve his actual character through the existing
-- faction/realm-qualified Crown identity, never through an Apostle marker or a display label.
-- Old signed Apostle lists remain readable, but their '*' cannot delegate the Head's powers.
function Church.HeadName()
	return type(ns.KingCharacter) == "function" and ns.KingCharacter() or nil
end
function Church.IsHead(name)
	return Church.IsKing(name)
end

-- W, K or H for a root, else nil.
function Church.RootCode(name)
	if type(name) ~= "string" or name == "" then return nil end
	if Church.IsAuthor(name) then return "W" end
	if Church.IsKing(name) then return "K" end
	if Church.IsHead(name) then return "H" end
	return nil
end

-- Naming an Apostle belongs to the King, the author and the signed High Council.
-- Being the Head alone does not grant a council seat.
function Church.MayNameApostle(name)
	if type(name) ~= "string" or name == "" then return false end
	return Church.IsAuthor(name) or Church.IsKing(name) or ns.IsHighCouncillor(ns.FullName(name)) == true
end

-- The Apostles a titles list's departments field names: { Alliance = { { key, n }, ... }, ... }.
function Church.ReadApostles(text)
	local out = {}
	for entry in tostring(text or ""):gmatch("[^;]+") do
		local faction, list = entry:match("^%^apostles%^(%a+)%^([^%^]*)$")
		if faction == "Alliance" or faction == "Horde" then
			local names, seen = out[faction] or {}, {}
			for _, e in ipairs(names) do seen[e.key] = true end
			for n in list:gmatch("[^,]+") do
				local head = n:match("^%s*%*") ~= nil
				local name = WireName((n:gsub("^%s*%*", "")))
				local key = name and Key(name)
				if key and not seen[key] and #names < Church.APOSTLES_MAX then
					seen[key] = true
					names[#names + 1] = { key = key, n = name, head = head or nil }
				end
			end
			out[faction] = names
		end
	end
	return out
end

local signedMemo
-- The signed Apostles of the titles list we hold (checked when it was taken: Workshop.TakeTitles),
-- for our faction, and that list's time.
function Church.SignedApostles()
	local t = ns.CouncilTitles and ns.CouncilTitles()
	if type(t) ~= "table" or type(t.blob) ~= "string" then return {}, 0 end
	local m = signedMemo
	if m and m.blob == t.blob and m.faction == ns.faction then return m.list, m.at end
	local field = t.blob:match("^HT1~%d+~[^~]*~[01]~([^~]*)~%x+$") or ""
	local list = Church.ReadApostles(field)[ns.faction or "Alliance"] or {}
	signedMemo = { blob = t.blob, faction = ns.faction, list = list, at = tonumber(t.at) or 0 }
	return list, signedMemo.at
end

---------------------------------------------------------------------------
-- The tree (derived from the book and the signed list, never saved)
---------------------------------------------------------------------------

local function PageOf(key)
	local sum = 0
	for i = 1, #key do sum = sum + key:byte(i) end
	return "P" .. (sum % 8)
end
Church.PageOf = PageOf

local function Derive()
	local b = Book() or { p = {}, x = {}, c = {}, cx = {} }
	local signed, listAt = Church.SignedApostles()
	local S = { rev = rev, listAt = listAt, apostle = {}, order = {}, miss = {}, corr = {}, corrOf = {}, named = {},
		children = {}, invalid = {}, valid = 0, apostles = 0, signed = {} }
	for _, s in ipairs(signed) do S.signed[s.key] = true end
	local cands = {}
	for i, s in ipairs(signed) do
		local p, x = b.p[s.key], b.x[s.key]
		if not ((p and p.at > listAt) or (x and x.at > listAt)) then
			cands[#cands + 1] = { key = s.key, n = s.n, at = listAt, signed = true, i = i }
		end
	end
	for key, p in pairs(b.p) do
		if p.role == "A" and p.at > listAt then
			cands[#cands + 1] = { key = key, n = p.n, at = p.at, ac = p.ac, ar = p.ar, via = p.via, i = 1000 }
		end
	end
	table.sort(cands, function(a, c)
		if a.i ~= c.i then return a.i < c.i end
		if a.at ~= c.at then return a.at < c.at end
		return a.key < c.key
	end)
	for _, c in ipairs(cands) do
		if S.apostles < Church.APOSTLES_MAX then
			S.apostle[c.key], S.apostles = c, S.apostles + 1
			S.order[#S.order + 1] = c.key
		else
			S.invalid[#S.invalid + 1] = { key = c.key, n = c.n, role = "A", why = "full" }
		end
	end
	-- Missionaries: every place of role M (a signed Apostle's older M place is the list's past).
	local nodes = {}
	for key, p in pairs(b.p) do
		if p.role == "M" and not S.apostle[key] and not (S.signed[key] and p.at <= listAt) then nodes[key] = p end
	end
	local function Resolve(p)
		local par, adopted, steps = p.by, false, 0
		while par do
			if S.apostle[par] or nodes[par] then return par, adopted, false end
			local x = b.x[par]
			if not x then return nil, true, true end
			adopted, par, steps = true, x.by, steps + 1
			if steps > Church.DEPTH_MAX + 2 then return nil, true, true end
		end
		return nil, adopted, adopted
	end
	for key, p in pairs(nodes) do
		local eff, adopted, orphan = Resolve(p)
		local info = { key = key, n = p.n, p = p, eff = eff, adopted = adopted or nil, orphan = orphan or nil, at = p.at, valid = false }
		S.miss[key] = info
		local slot = eff or ""
		S.children[slot] = S.children[slot] or {}
		table.insert(S.children[slot], info)
		if p.by then S.named[p.by] = (S.named[p.by] or 0) + 1 end
	end
	-- From the anchors (the Head, the Apostles) down, in a fixed order: the oldest first.
	local depth, net, queue, head = { [""] = 0 }, {}, { "" }, 1
	for _, k in ipairs(S.order) do depth[k], net[k], queue[#queue + 1] = 0, k, k end
	while head <= #queue do
		local parent = queue[head]
		head = head + 1
		local kids = S.children[parent]
		if kids then
			table.sort(kids, function(a, c)
				if (a.adopted and 1 or 0) ~= (c.adopted and 1 or 0) then return not a.adopted end
				if a.at ~= c.at then return a.at < c.at end
				return a.key < c.key
			end)
			local own = 0
			for _, info in ipairs(kids) do
				local d = depth[parent] + 1
				local why
				if d > Church.DEPTH_MAX then why = "deep" end
				if not why and not info.adopted and parent ~= "" then
					own = own + 1
					if own > Church.NAMES_PER then why = "quota" end
				end
				if not why and S.valid >= Church.MISSIONARIES_MAX then why = "full" end
				if why then
					info.why = why
				else
					info.valid, info.depth = true, d
					info.net = S.apostle[parent] and parent or net[parent]
					depth[info.key], net[info.key] = d, info.net
					S.valid = S.valid + 1
					queue[#queue + 1] = info.key
				end
			end
		end
	end
	for _, info in pairs(S.miss) do
		if not info.valid then
			info.why = info.why or "chain"
			S.invalid[#S.invalid + 1] = { key = info.key, n = info.n, role = "M", why = info.why }
		end
	end
	-- Correspondents: one per Olympus guild.
	for gkey, c in pairs(b.c) do
		if type(c.g) == "string" and ns.IsFederation(c.g) then
			S.corr[gkey] = c
			local k = Key(c.n)
			if k then S.corrOf[k] = S.corrOf[k] or gkey end
		end
	end
	return S
end

-- The tree as this client holds it now (cached until the book or the signed list changes).
function Church.State()
	local _, listAt = Church.SignedApostles()
	if not derived or derived.rev ~= rev or derived.listAt ~= listAt or derived.blob ~= (signedMemo and signedMemo.blob) then
		derived = Derive()
		derived.blob = signedMemo and signedMemo.blob
	end
	return derived
end

-- A person's role code: W K H A M C N, or nil.
function Church.Role(name)
	if type(name) ~= "string" or name == "" then return nil end
	local root = Church.RootCode(name)
	if root then return root end
	local S, k = Church.State(), Key(name)
	if S.apostle[k] then return "A" end
	local m = S.miss[k]
	if m and m.valid then return "M" end
	if S.corrOf[k] then return "C" end
	if ns.IsHighCouncillor(ns.FullName(name)) then return "N" end
	return nil
end

function Church.InAudience(name) return AUDIENCE_ROLES[Church.Role(name or ns.me) or ""] == true end
function Church.IsKeeper(name) return KEEPER_ROLES[Church.Role(name or ns.me) or ""] == true end
-- A Church person: one who holds a place and whose recruits count (the Head, an Apostle, a
-- missionary, a correspondent).
function Church.IsPerson(name)
	local r = Church.Role(name or ns.me)
	if r == "H" or r == "A" or r == "M" or r == "C" then return true end
	local k = Key(name or ns.me)
	return k ~= nil and (Church.State().corrOf[k] ~= nil)
end

-- What a person holds: { role, n, parent (key), net (the Apostle's key), depth, adopted, orphan,
-- at, since (when he first held it: a keep or a move re-dates the entry, never this), ac (who
-- named him) } for an Apostle or a missionary, nil otherwise.
function Church.Place(name)
	local S, k = Church.State(), Key(name)
	if not k then return nil end
	local a = S.apostle[k]
	if a then return { role = "A", n = a.n, net = k, depth = 0, at = a.at, since = a.at, signed = a.signed, ac = a.ac } end
	local m = S.miss[k]
	if m then
		return { role = "M", n = m.n, parent = m.eff, net = m.net, depth = m.depth, adopted = m.adopted, orphan = m.orphan,
			valid = m.valid, why = m.why, at = m.at, since = m.p.since or m.at, ac = m.p.ac, via = m.p.via }
	end
	return nil
end

-- Is `above` (a key) up the effective chain of the missionary `key`?
function Church.Above(above, key)
	local S = Church.State()
	local steps, k = 0, key
	while k and steps <= Church.DEPTH_MAX + 2 do
		local m = S.miss[k]
		if not m then return false end
		if m.eff == above then return true end
		k, steps = m.eff, steps + 1
	end
	return false
end

-- The valid missionaries directly under a key (an Apostle's or a missionary's), oldest first.
function Church.Children(key)
	local out = {}
	for _, info in ipairs(Church.State().children[key or ""] or {}) do
		if info.valid then out[#out + 1] = info end
	end
	return out
end

-- The guild master of `guild`: true, false, or nil while this client can't tell (another guild's
-- census not fresh yet). Our own guild from the server's roster; another from Data.AuthorizedRank.
function Church.IsGuildMaster(name, guild)
	if type(name) ~= "string" or type(guild) ~= "string" then return false end
	local mine = OwnGuild()
	if mine and ns.Fold(mine) == ns.Fold(guild) then
		if Same(name, ns.me) then
			local _, _, rank = GetGuildInfo("player")
			return rank == 0
		end
		local R = ns.Roster
		local fresh = R and R.Fresh and R.Fresh()
		if not fresh then return nil end
		local rank = R.RankOf(ns.FullName(name))
		return rank == 0
	end
	local D = ns.Data
	if not (D and D.AuthorizedRank) then return nil end
	local rank = D.AuthorizedRank(ns.FullName(name), guild)
	if rank == nil then return nil end
	return rank == 0
end

---------------------------------------------------------------------------
-- Who may do what (the actor's own client and every receiver run the same check)
---------------------------------------------------------------------------

-- ok, why. why "unknown": this client can't tell yet (the act waits, Church.pending).
function Church.MayAct(op, role, target, under, guild, actor)
	local S = Church.State()
	local ak = Key(actor)
	if not ak then return false, "shape" end
	local root = Church.RootCode(actor)
	if role == "A" then
		local tk = Key(target)
		if not tk then return false, "shape" end
		if op == "+" then
			if not Church.MayNameApostle(actor) then return false, "rights" end
			if S.apostle[tk] then return false, "holds" end
			if Church.RootCode(target) then return false, "root" end
			if S.apostles >= Church.APOSTLES_MAX then return false, "full" end
			return true
		elseif op == "-" then
			if not S.apostle[tk] then return false, "none" end
			-- (The Head's place is the signed list's: only a newer one ends it.)
			if Church.IsHead(target) then return false, "root" end
			if root or ak == tk then return true end
			return false, "rights"
		end
		return false, "op"
	elseif role == "M" then
		local tk = Key(target)
		if not tk then return false, "shape" end
		local m = S.miss[tk]
		if op == "+" then
			if Church.RootCode(target) then return false, "root" end
			if S.apostle[tk] or m then return false, "holds" end
			if tk == ak then return false, "self" end
			local pk
			if root then
				pk = Key(under)
				if not pk then return false, "under" end
			else
				pk = ak
				if under and under ~= "-" and Key(under) ~= ak then return false, "under" end
			end
			local pm = S.miss[pk]
			if not S.apostle[pk] and not (pm and pm.valid) then return false, root and "under" or "rights" end
			if pm and pm.depth >= Church.DEPTH_MAX then return false, "deep" end
			if (S.named[pk] or 0) >= Church.NAMES_PER then return false, "quota" end
			if S.valid >= Church.MISSIONARIES_MAX then return false, "full" end
			return true
		elseif op == "-" then
			if not m then return false, "none" end
			if root or ak == tk or ak == Key(m.p.ac) or Church.Above(ak, tk) then return true end
			return false, "rights"
		elseif op == "k" then
			if not m then return false, "none" end
			if not root then return false, "rights" end
			if not (m.adopted or m.orphan) then return false, "unmarked" end
			-- Kept, he becomes one of his new parent's own: not past that parent's quota (the Head
			-- moves him instead). The Head's own slot (an orphan's) has none.
			if m.eff and (S.named[m.eff] or 0) >= Church.NAMES_PER then return false, "quota" end
			return true
		elseif op == "m" then
			if not m then return false, "none" end
			if not root then return false, "rights" end
			local pk = Key(under)
			if not pk or pk == tk then return false, "under" end
			local pm = S.miss[pk]
			if not S.apostle[pk] and not (pm and pm.valid) then return false, "under" end
			if pm and (pm.depth >= Church.DEPTH_MAX or Church.Above(tk, pk)) then return false, "under" end
			if (S.named[pk] or 0) >= Church.NAMES_PER then return false, "quota" end
			return true
		end
		return false, "op"
	elseif role == "C" then
		guild = CleanGuild(guild)
		if not guild or not ns.IsFederation(guild) then return false, "guild" end
		local gm = Church.IsGuildMaster(actor, guild)
		if op == "+" then
			if not WireName(target) then return false, "shape" end
			if root or gm == true then return true end
			if gm == nil then return false, "unknown" end
			return false, "rights"
		elseif op == "-" then
			local c = S.corr[ns.Fold(guild)]
			if not c then return false, "none" end
			if root or gm == true or Key(c.n) == ak then return true end
			if gm == nil then return false, "unknown" end
			return false, "rights"
		end
		return false, "op"
	end
	return false, "role"
end

---------------------------------------------------------------------------
-- Entries and their merge: per name (or guild), the newest time wins
---------------------------------------------------------------------------

-- The newest state already held for an entry's slot, and its time.
local function Held(kind, slot)
	local b = Book()
	if not b then return nil end
	if kind == "C" or kind == "Y" then
		local c, x = b.c[slot], b.cx[slot]
		return c or x, (c or x) and (c or x).at or nil
	end
	local p, x = b.p[slot], b.x[slot]
	return p or x, (p or x) and (p or x).at or nil
end

-- Does a new state at `at` by `ar` take the slot over? (Equal times: the higher actor, then a
-- removal over a place, then the byte-wise smaller text: every client decides the same.)
local function Removal(text) local k = tostring(text or ""):sub(1, 1) return k == "X" or k == "Y" end
local function Newer(old, at, ar, text)
	if not old then return true end
	if at ~= old.at then return at > old.at end
	local ro, rn = ROLE_RANK[old.ar or "G"] or 0, ROLE_RANK[ar or "G"] or 0
	if ro ~= rn then return rn > ro end
	if Removal(old.wire) ~= Removal(text) then return Removal(text) end
	return (old.wire or "") > (text or "")
end

-- An entry's page line (NB p's fields after the kind), the same on every client.
local function EntryWire(kind, slot, e)
	if kind == "A" or kind == "M" then
		return ("%s~%s~%s~%s~%s~%s~%s"):format(kind, e.n, e.bn or "-", e.ac or "-", e.ar or "-", e.k and B36(e.since or e.at) or "-", B36(e.at))
	elseif kind == "X" then
		return ("X~%s~%s~%s~%s~%s~%s"):format(e.n or slot, e.role or "M", e.ac or "-", e.ar or "-", e.bn or "-", B36(e.at))
	elseif kind == "C" then
		return ("C~%s~%s~%s~%s~-~%s"):format(e.g, e.n, e.ac or "-", e.ar or "-", B36(e.at))
	end
	return ("Y~%s~-~%s~%s~-~%s"):format(e.g or slot, e.ac or "-", e.ar or "-", B36(e.at))
end

-- Puts a state in its slot when it is newer than what is held. True when it changed anything.
local function Put(kind, slot, e)
	local b = Book()
	if not b then return false end
	local old = Held(kind, slot)
	e.wire = EntryWire(kind, slot, e)
	if not Newer(old, e.at, e.ar, e.wire) then return false end
	if kind == "A" or kind == "M" then
		b.p[slot], b.x[slot] = e, nil
	elseif kind == "X" then
		b.x[slot], b.p[slot] = e, nil
	elseif kind == "C" then
		b.c[slot], b.cx[slot] = e, nil
	else
		b.cx[slot], b.c[slot] = e, nil
	end
	return true
end
Church.Put = Put

---------------------------------------------------------------------------
-- Acts
---------------------------------------------------------------------------

-- What an act becomes in the book, after Church.MayAct agreed. True when it changed anything.
local function Apply(op, role, target, under, guild, at, actor)
	local ac, ar = ns.FullName(actor), Church.RootCode(actor) or (ns.IsHighCouncillor(ns.FullName(actor)) and "N")
		or (Church.Role(actor) == "A" and "A") or (Church.Role(actor) == "M" and "M") or "G"
	local S = Church.State()
	if role == "C" then
		guild = CleanGuild(guild)
		local slot = ns.Fold(guild)
		if op == "+" then return Put("C", slot, { n = WireName(target), g = guild, ac = ac, ar = ar, at = at }) end
		return Put("Y", slot, { g = guild, ac = ac, ar = ar, at = at })
	end
	local tk, name = Key(target), WireName(target)
	if role == "A" then
		if op == "+" then return Put("A", tk, { role = "A", n = name, ac = ac, ar = ar, at = at }) end
		return Put("X", tk, { role = "A", n = (S.apostle[tk] and S.apostle[tk].n) or name, ac = ac, ar = ar, at = at })
	end
	local m = S.miss[tk]
	if op == "+" then
		local pk = (Church.RootCode(actor) and Key(under)) or Key(actor)
		local pn = (Church.RootCode(actor) and WireName(under)) or ns.FullName(actor)
		return Put("M", tk, { role = "M", n = name, by = pk, bn = pn, ac = ac, ar = ar, at = at })
	elseif op == "-" then
		local parent = m and m.eff
		local pn = parent and ((S.apostle[parent] and S.apostle[parent].n) or (S.miss[parent] and S.miss[parent].n)) or nil
		return Put("X", tk, { role = "M", n = m and m.n or name, by = parent, bn = pn, ac = ac, ar = ar, at = at })
	elseif op == "k" or op == "m" then
		local pk = op == "k" and m.eff or Key(under)
		local pn = op == "k" and (pk and ((S.apostle[pk] and S.apostle[pk].n) or (S.miss[pk] and S.miss[pk].n))) or WireName(under)
		-- (The entry takes the act's time, for the merge; since keeps when he first held his place,
		-- so his invites from then on still count: ChurchCount's PlacedBy.)
		return Put("M", tk, { role = "M", n = m.n, by = pk, bn = pn, ac = m.p.ac, ar = m.p.ar, at = at, k = true,
			since = math.min(m.p.since or m.p.at, at) })
	end
	return false
end

-- The parts of an act's message, checked for shape: op, role, target, under, guild, at.
local OPS = { ["+"] = true, ["-"] = true, k = true, m = true }
local function ParseAct(text)
	local op, role, target, under, guild, at = tostring(text or ""):match("^NB~1~a~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
	if not op or not OPS[op] or (role ~= "A" and role ~= "M" and role ~= "C") then return nil end
	at = UnB36(at)
	if not at then return nil end
	if role == "C" then
		guild = CleanGuild(guild)
		if not guild or (op ~= "+" and op ~= "-") then return nil end
		if op == "+" then target = WireName(target) if not target then return nil end else target = nil end
		return op, role, target, nil, guild, at
	end
	target = WireName(target)
	if not target or guild ~= "-" then return nil end
	if role == "A" and ((op ~= "+" and op ~= "-") or under ~= "-") then return nil end
	if under == "-" then under = nil else under = WireName(under) if not under then return nil end end
	if (op == "m" and not under) or ((op == "k" or op == "-") and under) then return nil end
	return op, role, target, under, nil, at
end
Church.ParseAct = ParseAct

local function ActText(op, role, target, under, guild, at)
	return ("NB~1~a~%s~%s~%s~%s~%s~%s"):format(op, role, target or "-", under or "-", guild or "-", B36(at))
end
Church.ActText = ActText

-- A word of mine that changed my own place: told once, as the King's Hands are.
local function TellMine(before)
	local after = Church.Role(ns.me)
	if before == after then return end
	if after == "A" then ns.Print(L.CHURCH_YOU_APOSTLE)
	elseif after == "M" then
		local p = Church.Place(ns.me)
		local S = Church.State()
		local net = p and p.net and S.apostle[p.net] and S.apostle[p.net].n
		ns.Print(L.CHURCH_YOU_MISSIONARY:format(net and ns.DisplayName(net) or L.CHURCH_HEAD))
	elseif after == "C" then ns.Print(L.CHURCH_YOU_CORRESPONDENT)
	elseif before == "A" or before == "M" or before == "C" then ns.Print(L.CHURCH_YOU_NO_LONGER) end
	if ns.PlayAlert and (after == "A" or after == "M" or after == "C") then ns.PlayAlert("soft", "update") end
end

local function AfterChange(before, wasAudience)
	Changed()
	TellMine(before)
	if wasAudience ~= Church.InAudience(ns.me) and ns.ChatRooms and ns.ChatRooms.RefreshAuthority then
		ns.ChatRooms.RefreshAuthority()
	end
end

-- A session table keyed by sender, emptied past `max` keys (a flood of names costs nothing lasting).
local function Capped(t, max)
	local n = 0
	for _ in pairs(t) do n = n + 1 if n > max then wipe(t) return t end end
	return t
end
Church.Capped = Capped

local function RateOK(sender, now)
	local k = Key(sender)
	local r = actRate[k]
	if not r then Capped(actRate, Church.HEARD_MAX) end
	if not r then
		r = { minute = {}, day = math.floor(now / 86400), dayN = 0 }
		actRate[k] = r
	end
	local d = math.floor(now / 86400)
	if r.day ~= d then r.day, r.dayN = d, 0 end
	for i = #r.minute, 1, -1 do if now - r.minute[i] >= 60 then table.remove(r.minute, i) end end
	if #r.minute >= Church.ACTS_PER_MIN or r.dayN >= Church.ACTS_PER_DAY then return false end
	r.minute[#r.minute + 1] = now
	r.dayN = r.dayN + 1
	return true
end

local function Hold(op, role, target, under, guild, at, sender)
	for i = #pending, 1, -1 do if Now() - pending[i].heard > Church.PENDING_KEEP then table.remove(pending, i) end end
	if #pending >= Church.PENDING_MAX then table.remove(pending, 1) end
	pending[#pending + 1] = { op = op, role = role, target = target, under = under, guild = guild, at = at, sender = sender, heard = Now() }
end

-- One act from its actor (the server stamps the sender). True when it was taken. maxAge: how old
-- it may be (ACT_AGE live; OWN_ACT_KEEP for one its actor's client hands a keeper later).
function Church.TakeAct(sender, text, quiet, maxAge)
	local op, role, target, under, guild, at = ParseAct(text)
	if not op then return Drop("shape") end
	local now = Clock()
	if at > now + Church.DATE_AHEAD then return Drop("ahead") end
	if at < now - (maxAge or Church.ACT_AGE) then return Drop("old") end
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, nil) then return Drop("netoff") end
	local slot = role == "C" and ns.Fold(guild) or Key(target)
	local old = Held(role == "C" and "C" or "A", slot)
	if old and old.at > at then return Drop("stale") end
	local ok, why = Church.MayAct(op, role, target, under, guild, sender)
	if not ok then
		if why == "unknown" or why == "rights" or why == "under" then Hold(op, role, target, under, guild, at, sender) end
		return Drop(why)
	end
	local before, wasAudience = Church.Role(ns.me), Church.InAudience(ns.me)
	if not Apply(op, role, target, under, guild, at, sender) then return Drop("same") end
	stats.applied = stats.applied + 1
	AfterChange(before, wasAudience)
	if not quiet then Church.RetryPending() end
	return true
end

-- The acts this client could not check when they came (an actor's place not heard yet, another
-- guild's census not fresh): tried again after each change, oldest first.
function Church.RetryPending()
	if #pending == 0 then return end
	table.sort(pending, function(a, b) return a.at < b.at end)
	local progress = true
	while progress do
		progress = false
		for i = #pending, 1, -1 do
			local p = pending[i]
			if Now() - p.heard > Church.PENDING_KEEP then
				table.remove(pending, i)
			else
				local ok = Church.MayAct(p.op, p.role, p.target, p.under, p.guild, p.sender)
				if ok then
					table.remove(pending, i)
					local before, wasAudience = Church.Role(ns.me), Church.InAudience(ns.me)
					if Apply(p.op, p.role, p.target, p.under, p.guild, p.at, p.sender) then
						stats.applied = stats.applied + 1
						AfterChange(before, wasAudience)
						progress = true
					end
				end
			end
		end
	end
end

local function Off()
	local M = ns.Moderation
	return M and M.SelfOff and M.SelfOff() or nil
end

-- This client's own acts, for the keepers who did not hear them (saved: a keeper may come only in
-- a later session): { text, slot, at, to = { [keeper key] = true } }, oldest first, the newest
-- act per place only (an older one for the same place would only be refused or undone).
local function OwnActs()
	local c = Store()
	if not c then return nil end
	if type(c.acts) ~= "table" then c.acts = {} end
	return c.acts
end
Church.OwnActs = OwnActs

local function ActSlot(role, target, guild)
	if role == "C" then return "c:" .. ns.Fold(CleanGuild(guild) or "") end
	return Key(target)
end

local function KeepOwn(text, slot, at)
	local acts = OwnActs()
	if not acts or not slot then return end
	for i = #acts, 1, -1 do if type(acts[i]) ~= "table" or acts[i].slot == slot then table.remove(acts, i) end end
	-- The keepers heard online now take it from the channel or the guild.
	local to = {}
	for _, k in ipairs(Church.KeepersOnline(false)) do to[Key(k.name)] = true end
	acts[#acts + 1] = { text = text, slot = slot, at = at, to = to }
	while #acts > Church.OWN_ACTS_MAX do table.remove(acts, 1) end
end

-- Each tick: our own acts to each keeper heard online who has not had them (a logged whisper
-- each, DELIVER_PER_TICK a keeper, oldest first); each keeper checks one as the act it is.
-- The number sent.
function Church.DeliverActs()
	local acts = OwnActs()
	if not acts or #acts == 0 or Off() or (ns.ChatLocked and ns.ChatLocked()) then return 0 end
	local now = Clock()
	for i = #acts, 1, -1 do
		local a = acts[i]
		if type(a) ~= "table" or type(a.text) ~= "string" or now - (tonumber(a.at) or 0) > Church.OWN_ACT_KEEP then table.remove(acts, i) end
	end
	local sent = 0
	for _, k in ipairs(Church.KeepersOnline(false)) do
		local kk, n = Key(k.name), 0
		for _, a in ipairs(acts) do
			if n >= Church.DELIVER_PER_TICK or ns.Comm.QueueRoom() <= Church.SEND_ROOM then break end
			if type(a.to) ~= "table" then a.to = {} end
			if kk and not a.to[kk] then
				a.to[kk] = true
				ns.Comm.Whisper(k.name, a.text, nil, false, true, nil, { owner = Church })
				n, sent = n + 1, sent + 1
			end
		end
	end
	stats.delivered = (stats.delivered or 0) + sent
	return sent
end

-- Sends an act of ours (after the same checks every receiver runs) on CHANNEL and GUILD, and
-- takes it here. True when it went.
function Church.SendAct(op, role, target, under, guild)
	local off = Off()
	if off then ns.Print(ns.Moderation.YouText(off)) return false, "netoff" end
	if ns.ChatLocked and ns.ChatLocked() then ns.Print(L.CHAN_LOCKDOWN) return false, "lockdown" end
	if role ~= "C" then
		target = WireName(target)
		if not target then ns.Print(L.CHURCH_WHO) return false, "name" end
	end
	if under then under = WireName(under) end
	local at = Clock()
	local text = ActText(op, role, target, under, guild, at)
	if #text > 255 then return false, "size" end
	local ok, why = Church.MayAct(op, role, target, under, guild, ns.me)
	if not ok then
		ns.Print(rawget(L, "CHURCH_NO_" .. tostring(why):upper()) or L.CHURCH_NO_RIGHTS)
		return false, why
	end
	local before, wasAudience = Church.Role(ns.me), Church.InAudience(ns.me)
	Apply(op, role, target, under, guild, at, ns.me)
	AfterChange(before, wasAudience)
	KeepOwn(text, ActSlot(role, target, guild), at)
	ns.Comm.Send("CHANNEL", text, nil, false, true)
	if OwnGuild() then ns.Comm.Send("GUILD", text, nil, false, true) end
	stats.sent = stats.sent + 1
	return true
end

-- The player's own words (the Name page, the dialogs, /oly church): who and under whom.
function Church.NameApostle(input)
	local name = Church.InputName(input)
	if not name then return ns.Print(L.CHURCH_WHO) end
	local ok = Church.SendAct("+", "A", name)
	if ok then ns.Print(L.CHURCH_NAMED_APOSTLE:format(ns.DisplayName(name))) end
	return ok
end
function Church.NameMissionary(input, under)
	local name = Church.InputName(input)
	if not name then return ns.Print(L.CHURCH_WHO) end
	local ok = Church.SendAct("+", "M", name, under)
	if ok then ns.Print(L.CHURCH_NAMED_MISSIONARY:format(ns.DisplayName(name))) end
	return ok
end
function Church.Remove(role, name)
	local ok = Church.SendAct("-", role, name)
	if ok then ns.Print(L.CHURCH_REMOVED:format(ns.DisplayName(WireName(name) or name))) end
	return ok
end
function Church.Keep(name) return Church.SendAct("k", "M", name) end
function Church.Move(name, under) return Church.SendAct("m", "M", name, under) end
function Church.NameCorrespondent(input, guild)
	local name = Church.InputName(input)
	if not name then return ns.Print(L.CHURCH_WHO) end
	guild = guild or OwnGuild()
	local ok = Church.SendAct("+", "C", name, nil, guild)
	if ok then ns.Print(L.CHURCH_NAMED_CORRESPONDENT:format(ns.DisplayName(name), guild)) end
	return ok
end
function Church.RemoveCorrespondent(guild) return Church.SendAct("-", "C", nil, nil, guild) end

-- A name typed, or the player targeted when nothing was: as the server writes it, or nil.
function Church.InputName(input)
	local name = Trim(input)
	if name == "" then
		name = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName and ns.UnitFullName("target") or ""
	end
	return WireName(name)
end

-- What this player may name now (the Name page, the player menus): { apostle, missionary (left),
-- correspondent (a guild), register }.
function Church.Rights()
	local S = Church.State()
	local me, k = ns.me, Key(ns.me)
	local root = Church.RootCode(me)
	local out = { root = root }
	if Church.MayNameApostle(me) then out.apostle = Church.APOSTLES_MAX - S.apostles end
	local m = S.miss[k]
	if S.apostle[k] or (m and m.valid and m.depth < Church.DEPTH_MAX) then
		out.missionary = math.max(0, Church.NAMES_PER - (S.named[k] or 0))
	end
	local guild = OwnGuild()
	if guild and ns.IsFederation(guild) and (root or Church.IsGuildMaster(me, guild) == true) then out.correspondent = guild end
	return out
end

---------------------------------------------------------------------------
-- Public ranking: the author, the King and the actual signed High Council. A claimed wire
-- role, Church title or role preview grants no authority. The desk still publishes opted-in rows.

function Church.MayPublish(name)
	if type(name) ~= "string" or name == "" then return false end
	return Church.IsAuthor(name) or Church.IsKing(name)
		or (type(ns.IsHighCouncillor) == "function" and ns.IsHighCouncillor(ns.FullName(name)) == true)
end

local function SwitchAllowed(name)
	local M = ns.Moderation
	return Church.MayPublish(name) and not (M and M.Hides and M.Hides(name, nil))
end
---------------------------------------------------------------------------

function Church.Public()
	local c = Store()
	local p = c and c.pub
	if type(p) ~= "table" then return false, 0 end
	return p.on == true, tonumber(p.at) or 0
end

local function TakeSwitch(on, at)
	local c = Store()
	if not c then return false end
	local _, held = Church.Public()
	-- Multiple publishers may act in the same server second. Closing wins an equal stamp,
	-- irrespective of arrival order; an equal/stale opening cannot undo a privacy close.
	local wasOpen = Church.Public()
	if at < held or (at == held and (on or not wasOpen)) then return false end
	c.pub = { on = on, at = at }
	Changed()
	ns.Fire("CHURCH_PUBLIC_CHANGED", on)
	return true
end

function Church.SetPublic(on)
	if not ns.IsMember() or not Church.MayPublish(ns.me) then ns.Print(L.CHURCH_NO_RIGHTS); return false end
	local off = Off()
	if off then ns.Print(ns.Moderation.YouText(off)) return false end
	if not SwitchAllowed(ns.me) then return false end
	local _, held = Church.Public()
	local at = math.max(Clock(), held + 1)
	TakeSwitch(on == true, at)
	Church.SendSwitch()
	ns.Print(on and L.CHURCH_PUBLIC_OPENED or L.CHURCH_PUBLIC_CLOSED)
	return true
end

function Church.SendSwitch()
	if not ns.IsMember() or not SwitchAllowed(ns.me) or Off() then return false end
	local on, at = Church.Public()
	if at == 0 then return end
	lastSwitch = Now()
	local text = ("NB~1~s~%s~%s"):format(on and "1" or "0", B36(at))
	ns.Comm.Send("CHANNEL", text, "church-switch", false, true)
	if OwnGuild() then ns.Comm.Send("GUILD", text, "church-switch-guild", false, true) end
end

---------------------------------------------------------------------------
-- Pages: late clients get the book from the keepers
---------------------------------------------------------------------------

-- Each page's lines, sorted, and its digest (8 base-36 digits; "-" when empty).
function Church.PageLines(page)
	local b = Book()
	local lines = {}
	if not b then return lines end
	if page == "C" then
		for slot, e in pairs(b.c) do lines[#lines + 1] = e.wire or EntryWire("C", slot, e) end
		for slot, e in pairs(b.cx) do lines[#lines + 1] = e.wire or EntryWire("Y", slot, e) end
	else
		for slot, e in pairs(b.p) do if PageOf(slot) == page then lines[#lines + 1] = e.wire or EntryWire(e.role, slot, e) end end
		for slot, e in pairs(b.x) do if PageOf(slot) == page then lines[#lines + 1] = e.wire or EntryWire("X", slot, e) end end
	end
	table.sort(lines)
	return lines
end

function Church.Digests()
	local out = {}
	for i, page in ipairs(PAGES) do
		local lines = Church.PageLines(page)
		out[i] = #lines == 0 and "-" or ns.Comm.Hash36(table.concat(lines, "\n"))
	end
	return out
end
function Church.BookDigest()
	local d = Church.Digests()
	return ns.Comm.Hash36(table.concat(d, ","))
end

-- One page entry from a keeper: its slot, kind and state, or nil.
local function ParseEntry(text)
	local kind, f1, f2, f3, f4, f5, at = tostring(text or ""):match("^NB~1~p~([AMXCY])~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
	at = UnB36(at)
	if not kind or not at then return nil end
	local ac = f3 ~= "-" and WireName(f3) or nil
	local ar = ROLE_RANK[f4] and f4 or nil
	if f3 ~= "-" and not ac then return nil end
	if kind == "A" or kind == "M" then
		local n = WireName(f1)
		local since = f5 ~= "-" and UnB36(f5) or nil
		if not n or (f5 ~= "-" and (kind == "A" or not since or since > at)) then return nil end
		local bn = f2 ~= "-" and WireName(f2) or nil
		if (f2 ~= "-" and not bn) or (kind == "A" and bn) then return nil end
		return kind, Key(n), { role = kind, n = n, by = bn and Key(bn), bn = bn, ac = ac, ar = ar, at = at, k = since and true or nil, since = since }
	elseif kind == "X" then
		local n = WireName(f1)
		if not n or (f2 ~= "A" and f2 ~= "M") then return nil end
		local bn = f5 ~= "-" and WireName(f5) or nil
		if f5 ~= "-" and not bn then return nil end
		return kind, Key(n), { role = f2, n = n, by = bn and Key(bn), bn = bn, ac = ac, ar = ar, at = at }
	elseif kind == "C" then
		local g, n = CleanGuild(f1), WireName(f2)
		if not g or not n or f5 ~= "-" then return nil end
		return kind, ns.Fold(g), { n = n, g = g, ac = ac, ar = ar, at = at }
	end
	local g = CleanGuild(f1)
	if not g or f2 ~= "-" or f5 ~= "-" then return nil end
	return kind, ns.Fold(g), { g = g, ac = ac, ar = ar, at = at }
end
Church.ParseEntry = ParseEntry

-- An entry from a keeper we asked. Entries on Apostles only from a root's client: an A entry, an
-- Apostle's removal, and any entry for a name that is an Apostle here (a missionary's entry or
-- removal under an Apostle's name would put him out of his place: the slot is one per name).
function Church.TakeEntry(sender, text)
	local kind, slot, e = ParseEntry(text)
	if not kind then return Drop("shape") end
	if not Church.IsKeeper(sender) then return Drop("keeper") end
	local t = asked[Key(sender)]
	if not t or Now() - t > Church.ASKED_WINDOW then return Drop("unasked") end
	if e.at > Clock() + Church.DATE_AHEAD then return Drop("ahead") end
	local root = Church.RootCode(sender)
	local onApostle = kind == "A" or (kind == "X" and e.role == "A")
	if not onApostle and (kind == "M" or kind == "X") then
		local held = (Book() or { p = {} }).p[slot]
		onApostle = Church.State().apostle[slot] ~= nil or (held ~= nil and held.role == "A")
	end
	if onApostle and root ~= "W" and root ~= "H" then return Drop("apostle page") end
	if kind == "C" and not ns.IsFederation(e.g) then return Drop("guild") end
	e.via = Key(sender) ~= Key(e.ac) and ns.FullName(sender) or nil
	local before, wasAudience = Church.Role(ns.me), Church.InAudience(ns.me)
	if not Put(kind, slot, e) then return false, "same" end
	stats.pages = stats.pages + 1
	AfterChange(before, wasAudience)
	Church.RetryPending()
	return true
end

-- Asks one keeper (whose presence advertised another book) for the pages that differ.
function Church.AskPages(keeper)
	if not Church.InAudience(ns.me) or not keeper or Off() then return false end
	local now = Now()
	if now - lastAsk < Church.ASK_GAP then return false end
	lastAsk = now
	asked[Key(keeper)] = now
	ns.Comm.Whisper(keeper, "NB~1~q~" .. table.concat(Church.Digests(), ","), nil, false, false, nil, { owner = Church })
	return true
end

local function Pump()
	local o = outgoing
	if not o then return end
	while o.i <= #o.list and ns.Comm.QueueRoom() > Church.SEND_ROOM do
		ns.Comm.Whisper(o.target, o.list[o.i], nil, false, false, nil, { owner = Church })
		o.i = o.i + 1
	end
	if o.i > #o.list then outgoing = nil return end
	Church.after(3, "church pages", Pump)
end
Church.Pump = Pump

-- A keeper answers an audience asker: the entries of the pages whose digest differs.
function Church.AnswerAsk(sender, text)
	local list = tostring(text or ""):match("^NB~1~q~([%w%-,]+)$")
	if not list then return Drop("shape") end
	if not Church.IsKeeper(ns.me) or Church.IsKing(ns.me) or Off() then return Drop("not keeper") end
	if not Church.InAudience(sender) then return Drop("asker") end
	local now = Now()
	local k = Key(sender)
	if answered[k] and now - answered[k] < Church.ANSWER_GAP then return Drop("gap") end
	if not answered[k] then Capped(answered, Church.HEARD_MAX) end
	if outgoing then return Drop("busy") end
	local theirs = {}
	for d in list:gmatch("[^,]+") do theirs[#theirs + 1] = d end
	if #theirs ~= #PAGES then return Drop("shape") end
	local mine, out = Church.Digests(), {}
	for i, page in ipairs(PAGES) do
		if theirs[i] ~= mine[i] then
			for _, line in ipairs(Church.PageLines(page)) do
				if #out < Church.TRANSFER_MAX then out[#out + 1] = "NB~1~p~" .. line end
			end
		end
	end
	answered[k] = now
	if #out == 0 then return true end
	outgoing = { target = sender, list = out, i = 1 }
	Pump()
	return true
end

---------------------------------------------------------------------------
-- Presence and the desk
---------------------------------------------------------------------------

function Church.PresenceEvery(role) return KEEPER_ROLES[role or ""] and Church.KEEPER_EVERY or Church.MEMBER_EVERY end

function Church.SendPresence(force)
	if not ns.IsMember() then return false end
	local role = Church.Role(ns.me)
	if not AUDIENCE_ROLES[role or ""] or Off() then return false end
	local now = Now()
	if not force and now - lastPresence < Church.PresenceEvery(role) then return false end
	lastPresence = now
	local guild = OwnGuild() or "-"
	local keeper = KEEPER_ROLES[role] and not Church.IsKing(ns.me)
	local dig = keeper and Church.BookDigest() or "-"
	local on, at = Church.Public()
	local switch = (keeper or SwitchAllowed(ns.me)) and at > 0 and ((on and "1" or "0") .. B36(at)) or "-"
	local text = ("NK~1~p~%s~%s~%s~%s"):format(role, dig, CleanGuild(guild) or "-", switch)
	ns.Comm.Send("CHANNEL", text, "church-presence", false, false)
	if OwnGuild() then ns.Comm.Send("GUILD", text, "church-presence-guild", false, false) end
	return true
end

function Church.TakePresence(dist, sender, text)
	local role, dig, guild, switch = tostring(text or ""):match("^NK~1~p~(%u)~([%w%-]+)~([^~]*)~([^~]+)$")
	if not role then
		-- (The switch field may be left out: the same as "-".)
		role, dig, guild = tostring(text or ""):match("^NK~1~p~(%u)~([%w%-]+)~([^~]*)$")
		switch = "-"
	end
	if not role or not AUDIENCE_ROLES[role] or (dig ~= "-" and #dig > 8) then return Drop("shape") end
	if switch ~= "-" and not switch:match("^[01][0-9a-z]+$") then return Drop("shape") end
	local k = Key(sender)
	if not k then return Drop("shape") end
	-- Actual publishers may carry either switch; a keeper may relay only a close. The
	-- sender's authority comes from our signed book, never the presence's claimed role.
	if switch ~= "-" then
		local on, at = switch:sub(1, 1) == "1", UnB36(switch:sub(2))
		local M = ns.Moderation
		local hidden = M and M.Hides and M.Hides(sender, nil)
		if at and at <= Clock() + Church.DATE_AHEAD and not hidden
			and (SwitchAllowed(sender) or (not on and KEEPER_ROLES[role] and Church.IsKeeper(sender))) then
			TakeSwitch(on, at)
		end
	end
	if not heard[k] then
		heardCount = heardCount + 1
		if heardCount > Church.HEARD_MAX then
			local oldest, at
			for key, h in pairs(heard) do if not at or h.t < at then oldest, at = key, h.t end end
			if oldest then heard[oldest], heardCount = nil, heardCount - 1 end
		end
	end
	heard[k] = { name = ns.FullName(sender), role = role, dig = dig ~= "-" and dig or nil, guild = CleanGuild(guild), t = Now(), dist = dist }
	if ns.ChurchCount and ns.ChurchCount.HeardPresence then ns.ChurchCount.HeardPresence(dist, sender, role, guild) end
	-- A keeper (in our own book) whose book differs: ask him, a little later, at most every ASK_GAP.
	if dig ~= "-" and KEEPER_ROLES[role] and Church.IsKeeper(sender) and Church.InAudience(ns.me) and dig ~= Church.BookDigest()
		and Now() - lastAsk >= Church.ASK_GAP then
		local who = ns.FullName(sender)
		Church.after(Church.random(3, 20), "church ask", function() Church.AskPages(who) end)
	end
	return true
end

-- Heard lately with a role this client's book confirms (presence alone grants nothing).
function Church.Online(name)
	local h = heard[Key(name) or ""]
	if not h then return false end
	local role = Church.Role(h.name)
	if not AUDIENCE_ROLES[role or ""] then return false end
	return Now() - h.t <= Church.PresenceEvery(role) * Church.FRESH_FACTOR, h
end

-- Every name heard, as kept (ChurchCount's witnesses, /oly church status).
function Church.Heard() return heard end

-- The keepers online (by their presence) and this client when it is one, in the desk's order:
-- the Head, the Apostles by name, the author. Never the King's client.
function Church.KeepersOnline(withSelf)
	local out = {}
	local function Order(role) return role == "H" and 1 or (role == "A" and 2 or 3) end
	for _, h in pairs(heard) do
		local ok = Church.Online(h.name)
		local role = ok and Church.Role(h.name)
		if ok and KEEPER_ROLES[role or ""] and not Church.IsKing(h.name) and not Same(h.name, ns.me) then
			out[#out + 1] = { name = h.name, role = role }
		end
	end
	local mine = Church.Role(ns.me)
	if withSelf ~= false and KEEPER_ROLES[mine or ""] and not Church.IsKing(ns.me) then out[#out + 1] = { name = ns.me, role = mine, self = true } end
	table.sort(out, function(a, b)
		if Order(a.role) ~= Order(b.role) then return Order(a.role) < Order(b.role) end
		return Key(a.name) < Key(b.name)
	end)
	return out
end

-- The desk: the first keeper online. It alone sends the seen-checks and the public summary.
function Church.Desk()
	local k = Church.KeepersOnline(true)[1]
	return k and k.name or nil
end
function Church.IsDesk() local d = Church.Desk() return d ~= nil and Same(d, ns.me) end

-- The room's recipients: audience members heard online (this character left out), ROOM_FANOUT at
-- most, the Church's own people before the High Council: the roots and the Head, then the sender's
-- own network (his Apostle and its missionaries), the other Apostles, the correspondents, the other
-- missionaries, then the High Council; the most recently heard first within each. Also how many
-- members heard online were left out (the sender is told: the room's line says so).
function Church.RoomRecipients()
	local order = { W = 1, K = 1, H = 1, A = 3, C = 4, M = 5, N = 6 }
	local mine = Church.Place(ns.me)
	local net = mine and mine.net
	local list = {}
	for _, h in pairs(heard) do
		local ok = Church.Online(h.name)
		if ok and not Same(h.name, ns.me) then
			local o = order[Church.Role(h.name)] or 9
			if net and (o == 3 or o == 5) then
				local p = Church.Place(h.name)
				if p and p.net == net then o = 2 end
			end
			list[#list + 1] = { name = h.name, o = o, t = h.t }
		end
	end
	table.sort(list, function(a, b)
		if a.o ~= b.o then return a.o < b.o end
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	local out = {}
	for i = 1, math.min(#list, Church.ROOM_FANOUT) do out[i] = list[i].name end
	return out, math.max(0, #list - Church.ROOM_FANOUT)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

function Church.Receive(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return end
	local version, kind = text:match("^NB~([^~]+)~([^~]+)~")
	if version ~= "1" then return Drop("version") end
	sender = ns.FullName(sender)
	if kind == "a" then
		-- (By whisper: an act its actor's client hands a keeper who was away. Only a keeper takes it.)
		local later = dist == "WHISPER"
		if dist ~= "CHANNEL" and dist ~= "GUILD" and not later then return Drop("lane") end
		if later and (not Church.IsKeeper(ns.me) or Church.IsKing(ns.me)) then return Drop("lane") end
		local seen = Key(sender) .. ":" .. text
		local now = Now()
		if actSeen[seen] and now - actSeen[seen] < 600 then return false, "seen" end
		if not actSeen[seen] then Capped(actSeen, Church.HEARD_MAX) end
		if not RateOK(sender, now) then return Drop("rate") end
		actSeen[seen] = now
		stats.acts = stats.acts + 1
		return Church.TakeAct(sender, text, nil, later and Church.OWN_ACT_KEEP or nil)
	elseif kind == "s" then
		if dist ~= "CHANNEL" and dist ~= "GUILD" then return Drop("lane") end
		local on, at = text:match("^NB~1~s~([01])~([0-9a-z]+)$")
		at = UnB36(at)
		if not on or not at then return Drop("shape") end
		if not SwitchAllowed(sender) then return Drop("rights") end
		if at > Clock() + Church.DATE_AHEAD then return Drop("ahead") end
		return TakeSwitch(on == "1", at)
	elseif kind == "q" then
		if dist ~= "WHISPER" then return Drop("lane") end
		return Church.AnswerAsk(sender, text)
	elseif kind == "p" then
		if dist ~= "WHISPER" then return Drop("lane") end
		return Church.TakeEntry(sender, text)
	end
	return Drop("kind")
end

function Church.ReceivePresence(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return end
	if text:match("^NK~([^~]+)~") ~= "1" then return Drop("version") end
	if dist ~= "CHANNEL" and dist ~= "GUILD" then return Drop("lane") end
	return Church.TakePresence(dist, ns.FullName(sender), text)
end

ns.Comm.Handle("NB", function(dist, sender, text) Church.Receive(dist, sender, text) end)
ns.Comm.Handle("NK", function(dist, sender, text) Church.ReceivePresence(dist, sender, text) end)

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------

-- Tombstones no entry points to, past TOMB_KEEP; the oldest past TOMBS_MAX. Places past their
-- bounds (the oldest invalid ones first).
function Church.Prune()
	local b = Book()
	if not b then return end
	local now = Clock()
	local used = {}
	for _, p in pairs(b.p) do if p.by then used[p.by] = true end end
	for _, x in pairs(b.x) do if x.by then used[x.by] = true end end
	local tombs = {}
	for slot, x in pairs(b.x) do
		if not used[slot] and now - x.at > Church.TOMB_KEEP then b.x[slot] = nil else tombs[#tombs + 1] = { slot = slot, at = x.at } end
	end
	if #tombs > Church.TOMBS_MAX then
		table.sort(tombs, function(a, c) return a.at < c.at end)
		for i = 1, #tombs - Church.TOMBS_MAX do b.x[tombs[i].slot] = nil end
	end
	for slot, x in pairs(b.cx) do if now - x.at > Church.TOMB_KEEP then b.cx[slot] = nil end end
	local places = {}
	for slot, p in pairs(b.p) do places[#places + 1] = { slot = slot, at = p.at } end
	local cap = Church.MISSIONARIES_MAX + Church.APOSTLES_MAX * 2
	if #places > cap then
		table.sort(places, function(a, c) return a.at > c.at end)
		for i = cap + 1, #places do b.p[places[i].slot] = nil end
	end
	local corr = {}
	for slot, c in pairs(b.c) do corr[#corr + 1] = { slot = slot, at = c.at } end
	if #corr > Church.CORRESPONDENTS_MAX then
		table.sort(corr, function(a, c) return a.at > c.at end)
		for i = Church.CORRESPONDENTS_MAX + 1, #corr do b.c[corr[i].slot] = nil end
	end
	Changed()
end

-- A saved book whose entries don't read as entries is dropped whole (one malformed entry could
-- only come from a modified file); the book comes back from the keepers.
function Church.CheckSaved()
	local c = Store()
	if not c then return end
	if ns.Codec.Dirty(c) then wipe(c) return end
	local b = c.book
	if b == nil then return end
	local function Good(kind, slot, e)
		if type(e) ~= "table" or type(e.at) ~= "number" then return false end
		local line = EntryWire(kind, slot, e)
		local k2, s2 = ParseEntry("NB~1~p~" .. line)
		e.wire = line
		return k2 ~= nil and s2 == slot
	end
	local ok = type(b) == "table" and b.v == 1 and type(b.p) == "table" and type(b.x) == "table" and type(b.c) == "table" and type(b.cx) == "table"
	if ok then
		for slot, e in pairs(b.p) do if not Good(e.role == "A" and "A" or "M", slot, e) then ok = false end end
		for slot, e in pairs(b.x) do if not Good("X", slot, e) then ok = false end end
		for slot, e in pairs(b.c) do if not Good("C", slot, e) then ok = false end end
		for slot, e in pairs(b.cx) do if not Good("Y", slot, e) then ok = false end end
	end
	if not ok then c.book = nil end
	if type(c.pub) ~= "table" or type(c.pub.at) ~= "number" then c.pub = nil end
	-- Our own acts kept for the keepers: each one an act's text, its place and time.
	if c.acts ~= nil then
		local good = type(c.acts) == "table" and #c.acts <= Church.OWN_ACTS_MAX
		for _, a in ipairs(good and c.acts or {}) do
			if type(a) ~= "table" or not ParseAct(a.text) or type(a.slot) ~= "string" or type(a.at) ~= "number" or type(a.to) ~= "table" then good = false end
		end
		if not good then c.acts = nil end
	end
	Changed()
end

function Church.Tick()
	if not ns.IsMember() then return end
	local now = Now()
	loginAt = loginAt or now
	if Off() then return end
	Church.SendPresence(false)
	-- Our own acts to the keepers who were away when they went out.
	Church.DeliverActs()
	-- A late audience client with no book yet asks a keeper heard online once, ASK_AFTER after login.
	if Church.InAudience(ns.me) and now - loginAt >= Church.ASK_AFTER and lastAsk == -math.huge then
		local k = Church.KeepersOnline(false)[1]
		if k then Church.AskPages(k.name) end
	end
	-- Repeat the held stamp, never mint a newer opening during catch-up. A revoked or
	-- moderated publisher stops immediately; an older cached opening cannot undo a close.
	local open = Church.Public()
	if open and SwitchAllowed(ns.me) and now - lastSwitch >= Church.SWITCH_EVERY then Church.SendSwitch() end
	if now - lastPrune >= 3600 then lastPrune = now; Church.Prune() end
	Church.RetryPending()
	if ns.ChurchCount and ns.ChurchCount.Tick then ns.SafeCall("church count", ns.ChurchCount.Tick, now) end
end

-- How long this session has been logged in (nil before the LOGIN event): the desk waits a
-- while after a login before it speaks for the switch it saved (ChurchCount.SendPublic).
function Church.OnlineFor()
	return sessionAt and Now() - sessionAt or nil
end

function Church.Stats()
	local S = Church.State()
	return { acts = stats.acts, applied = stats.applied, pages = stats.pages, sent = stats.sent, delivered = stats.delivered or 0, dropped = stats.dropped,
		pending = #pending, heard = heardCount, apostles = S.apostles, missionaries = S.valid, invalid = #S.invalid }
end
function Church.Pending() return pending end

-- /oly church [status | name <Name> | apostle <Name> | register <Name> | remove <Name>]
function Church.Slash(rest)
	local verb, arg = Trim(rest):match("^(%S*)%s*(.-)$")
	verb = ns.Fold(verb or "")
	if verb == "" or verb == "open" or verb == "abrir" then
		if ns.ChurchView and ns.ChurchView.Open then return ns.ChurchView.Open() end
		return
	elseif verb == "status" then
		local lines = Church.StatusLines()
		if ns.UI and ns.UI.ShowCopy then return ns.UI.ShowCopy(L.CHURCH_TITLE, table.concat(lines, "\n")) end
		for _, line in ipairs(lines) do ns.Print(line) end
		return
	elseif verb == "name" or verb == "nomear" then
		return Church.NameMissionary(arg)
	elseif verb == "apostle" or verb == "apostolo" or verb == "apóstolo" then
		return Church.NameApostle(arg)
	elseif verb == "register" or verb == "registrar" then
		if ns.ChurchCount and ns.ChurchCount.Register then return ns.ChurchCount.Register(arg) end
		return
	elseif verb == "remove" or verb == "remover" then
		local p = Church.Place(arg)
		if p then return Church.Remove(p.role, arg) end
		return ns.Print(L.CHURCH_WHO)
	end
	ns.Print(L.CHURCH_USAGE)
end

function Church.StatusLines()
	local S, st = Church.State(), Church.Stats()
	local lines = {
		L.CHURCH_TITLE,
		("role %s, head %s, apostles %d, missionaries %d, invalid %d, correspondents %d"):format(tostring(Church.Role(ns.me) or "-"),
			tostring(Church.HeadName() or "-"), S.apostles, S.valid, #S.invalid, (function() local n = 0 for _ in pairs(S.corr) do n = n + 1 end return n end)()),
		("desk %s, keepers online %d, heard %d, pending acts %d, book %s"):format(tostring(Church.Desk() or "-"), #Church.KeepersOnline(false),
			st.heard, st.pending, Church.BookDigest()),
		("acts %d (applied %d), page entries %d, sent %d (kept for keepers %d, handed later %d), public %s"):format(st.acts, st.applied,
			st.pages, st.sent, #(OwnActs() or {}), st.delivered, tostring((Church.Public()))),
	}
	local dropped = {}
	for why, n in pairs(st.dropped) do dropped[#dropped + 1] = why .. "=" .. n end
	table.sort(dropped)
	lines[#lines + 1] = "dropped: " .. (#dropped > 0 and table.concat(dropped, ", ") or "-")
	if ns.ChurchCount and ns.ChurchCount.StatusLines then
		for _, line in ipairs(ns.ChurchCount.StatusLines()) do lines[#lines + 1] = line end
	end
	return lines
end

---------------------------------------------------------------------------
-- The Church's room (ChatRooms.lua's private-audience path: one logged whisper to each
-- recipient, checked again before it leaves; never a broadcast)
---------------------------------------------------------------------------

if ns.ChatRooms and ns.ChatRooms.RegisterAudience then
	ns.ChatRooms.RegisterAudience("church", {
		label = function() return L.CHURCH_ROOM end,
		CanAccess = function(name) return Church.InAudience(name or ns.me) end,
		Recipients = function()
			local list, left = Church.RoomRecipients()
			if left > 0 then ns.Print(L.CHURCH_ROOM_NOT_REACHED:format(left)) end
			return list
		end,
	})
end

ns.On("INIT", function() Church.CheckSaved() end)
ns.On("DATA_CHANGED", function()
	derived = nil
	Church.RetryPending()
end)
ns.On("LOGIN", function()
	loginAt = Now()
	sessionAt = loginAt
	if ns.Every then ns.Every(Church.TICK, "church tick", Church.Tick) end
end)
