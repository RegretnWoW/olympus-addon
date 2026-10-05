local ADDON, ns = ...
local L = ns.L

-- The guild masters' nominees (1.1.5, the author's ask after the High Council's yes): the guild
-- master of an Olympus guild names, from Olympus, up to MAX_CENTURIONS centurions and one
-- correspondent per department of the High Council (the named departments of the council's signed
-- titles list, MAX_DEPTS at most): MAX people in all, members of his own guild. The addon holds the
-- caps (an eleventh centurion, a second correspondent for a department, someone named twice, a
-- name outside his roster: each refused with its reason), so nobody has to count them by hand.
-- Each wears Max's bronze border without wings (Borders.lua's "bronze"), and the bronze mark of a
-- guild master on nameplates and in the game's chat, only while the server gives him that guild
-- (GetGuildInfo): nobody outside it can borrow it.
--
-- Where (1.1.5, the author's call on seeing the page): a tab of its own, in the Throne's place
-- (King.lua's Build; UI.lua's "throne" key). A guild master of an Olympus guild (not the King's)
-- has it as his Guild tab, his guild's page: the King's Hands page's look and flow (King.lua's HandsLines, the
-- Throne's parchment and ink), a title, a one-line hint, "+ Name a centurion (your target, or type
-- a name)", his list with a click that takes the title back (asked first), the departments'
-- correspondents (the role picker: a line per department, a click names its correspondent) and the
-- note on how the army learns his list. And
-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]` (alone: the tab).
--
-- The King's own guild (1.1.5, the author's call): no guild master's Guild tab (its master is the King),
-- but its centurions, up to MAX_CENTURIONS, on the Throne's page (the King, his Steward, his Hands
-- and the High Council see it there). The King or a High Councillor names them (the same page, the
-- same caps); a Steward or a Hand who is not a councillor reads the list. No correspondents for it:
-- its department heads come in 1.1.6. One shared list: each naming makes a newer one (its <rev>),
-- every client keeps the newest it heard, and the King's and the councillors' clients take it as
-- their own (to name on from it) and repeat it every EVERY seconds unless another of them just did.
-- Every client takes it only from the King's character or a signed High Councillor (ns.IsKingCharacter,
-- ns.IsHighCouncillor: the name the server stamps), never an older one over a newer one, and ends it
-- when its sender is neither any more. A councillor of another guild can't read the King's guild's
-- roster: the name he types is taken as it is, and its bronze shows only while the server gives that
-- character the King's guild (Borders.lua's Facts, as for every nominee).
--
-- How it travels, as the King's list of Hands (King.lua): the guild master's own client keeps his
-- list (ns.rdb.nominees, under his character) and sends it on the Olympus channel a few seconds
-- after each change and every EVERY seconds while he is online. Every client takes it only from
-- that guild's master as the census proves him, the very proof the borders ask for a guild
-- master's bronze (Borders.lua's Facts): our own guild's from our roster (the server's word),
-- another guild's from its census report, two senders naming him guild master, one of them
-- someone else (Data.KnownRank). The sender is the name the server stamps, so nobody can send it
-- for him. A list from anyone else is refused, and never takes the place of the real one. Each
-- client keeps the last list it heard from each guild's master, in memory only (heard this
-- session), for FRESH after his client stopped repeating it, and drops it at once when the census
-- or our roster shows he is no longer that guild's master (another one proven, or his own rank
-- below it), or when his new list names nobody.
--   NM~1~<guild>~<rev>~<i>~<n>~<entry>;<entry>;...
-- One list in n parts (i of n), each one addon message of PART bytes at most, put together by
-- their <rev> (the time of his last change); an entry is c=<Name[-Realm]> (a centurion) or
-- d=<department>=<Name[-Realm]> (that department's correspondent), a name without a realm his
-- own realm's. Bounded on every side: MAX_PARTS parts, the caps above (the first ones kept), each
-- name and each department once, a department's name of DEPT_LEN bytes. No part is ever chunked:
-- clients before 1.1.5 have no handler for NM and leave each part unread, nothing counted bad
-- (Comm.lua). Version 1: a client takes the parts of its own version alone.
-- The gamepad UI: the borders and marks it gives are off there, as every border (Borders.lua), and
-- its name boxes are Olympus's own dialogs (ns.ShowDialog), never the game's popups.
-- /oly status: his own list, and the lists held here (Nominees.StatusLine).

local Nominees = {}
ns.Nominees = Nominees

Nominees.MAX_CENTURIONS = 10
Nominees.MAX_DEPTS = 6
Nominees.MAX = Nominees.MAX_CENTURIONS + Nominees.MAX_DEPTS
Nominees.EVERY = 300          -- his client repeats the list for late logins
Nominees.FRESH = 6 * 60 * 60  -- a list he stopped repeating (he logged off) counts this long after
Nominees.SEND_AFTER = 3       -- several changes in a row go out as one list
Nominees.PART = 250           -- bytes in one part (one addon message)
Nominees.MAX_PARTS = Nominees.MAX
Nominees.PART_WAIT = 60       -- the parts of one list wait this long for the rest
Nominees.DEPT_LEN = 40
Nominees.WIRE = "1"           -- the message's version

local lists = {}   -- [guild, lower case] = { guild, by, rev, at, entries = { { role, dept, name } }, set = { [name, lower case] = entry } }
local pending = {} -- [sender] = { guild, rev, n, parts = { [i] = body }, got, t }: a list's parts as they come
local version = 0  -- one more at each change of what any list counts for (Borders.Changed)
local lastSent, sendPending = -math.huge, false
local sentOnce = false -- his list went out this session (then an empty one goes out too)
-- The King's guild's list (1.1.5), on the King's and the councillors' clients: when this client last
-- sent it, and last heard another of them send the newest one (then it waits its turn to repeat it).
local lastMainSent, mainHeardAt, mainSendPending, mainSentOnce = -math.huge, -math.huge, false, false

function Nominees.Version() return version end
local function Bump() version = version + 1 end

---------------------------------------------------------------------------
-- Names, guilds, departments
---------------------------------------------------------------------------

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A character's name as the server writes it ("First Surname-Realm"; a name without a realm is
-- `realm`'s, ours when none), or nil if it can't be one: letters only (Forever's first name and
-- surname), the realm letters and digits.
local function Person(s, realm)
	s = Trim(ns.Normal(Trim(s)))
	local short, theirs = s:match("^([^%-]+)%-([^%-]+)$")
	short = short or s
	if #short > 30 or not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	if theirs and (#theirs > 40 or not theirs:match("^[%w\128-\255]+$")) then return nil end
	return ns.FullName(short, theirs or realm)
end
Nominees.Person = Person

-- A name typed, as our roster spells it (the server's): whatever its case, and (anyRealm: typed
-- without one) on another realm when only one member carries it. nil when our roster has nobody
-- of that name.
local function RosterName(name, anyRealm)
	if type(name) ~= "string" then return nil end
	if ns.Roster.RankOf(name) ~= nil then return name end
	local byName = ns.Roster.byName
	if type(byName) ~= "table" then return nil end
	local low, short = name:lower(), ns.ShortName(name):lower()
	local found, twice
	for full in pairs(byName) do
		if type(full) == "string" then
			if full:lower() == low then return full end
			if anyRealm and ns.ShortName(full):lower() == short then
				twice = found ~= nil
				found = found or full
			end
		end
	end
	return not twice and found or nil
end

-- An Olympus guild's name as a list may give it, or nil.
local function GuildName(s)
	s = tostring(s or ""):gsub("[%c|]", "")
	if s == "" or #s > 24 or not s:match("^[%w\128-\255 ]+$") or not ns.IsFederation(s) then return nil end
	return s
end

-- A department's name as the lists carry it: no separator of theirs, DEPT_LEN bytes at most.
local function DeptName(s)
	s = Trim(tostring(s or ""):gsub("[%c|~;=]", ""))
	if s == "" or #s > Nominees.DEPT_LEN then return nil end
	return s
end

-- The High Council's six departments (the author's names, 1.1.5): the correspondents' roles, one
-- each per guild. (The signed titles list names only the departments that have councillors.)
Nominees.DEPARTMENTS = { "Federal Treasury", "Department of War", "Council of Justice", "Association of Citizenry",
	"Department of Heritage", "The Missionary Church of Olympus" }
Nominees.SHIPPED_DEPARTMENTS = Nominees.DEPARTMENTS
function Nominees.Departments()
	local out = {}
	for i, name in ipairs(Nominees.DEPARTMENTS) do
		if i <= Nominees.MAX_DEPTS then out[#out + 1] = name end
	end
	return out
end
local function IsDept(dept)
	if type(dept) ~= "string" then return nil end
	for _, d in ipairs(Nominees.Departments()) do
		if d:lower() == dept:lower() then return d end
	end
	return nil
end

-- A role as a line says it: "centurion", "correspondent for Events".
function Nominees.RoleLabel(role, dept)
	if role == "correspondent" then return L.NOMINEE_ROLE_CORRESPONDENT:format(dept or "?") end
	return L.NOMINEE_ROLE_CENTURION
end

---------------------------------------------------------------------------
-- Who is the guild's master
---------------------------------------------------------------------------

-- This character is the guild master of an Olympus guild (the server's rank), and that guild.
local function RealMaster()
	if ns.IsMember() ~= true then return false end
	local guild, _, rank = GetGuildInfo("player")
	-- (The King's own guild has no centurions or correspondents: the author's call.)
	if type(guild) == "string" and ns.IsKingGuild and ns.IsKingGuild(guild) then return false end
	return rank == 0 and type(guild) == "string", guild
end

-- The author's "guild master's view" (1.1.5, his ask: his character is no guild master): from the
-- Workshop, his section shows as a guild master's would, to see and try it. Nothing it does is
-- sent (Nominees.Send refuses it): what he names stays on his screen.
function Nominees.DevView()
	return ns.db ~= nil and ns.db.devGMView == true and ns.Workshop ~= nil and ns.Workshop.Visible ~= nil
		and ns.Workshop.Visible() == true and not RealMaster()
end
function Nominees.SetDevView(on)
	ns.db.devGMView = on and true or false
	ns.Print(on and ns.L.DEV_GM_VIEW_NOW_ON or ns.L.DEV_GM_VIEW_NOW_OFF)
	ns.Fire("DATA_CHANGED")
end

function Nominees.IsMaster()
	local real, guild = RealMaster()
	if real then return real, guild end
	if Nominees.DevView() then return true, GetGuildInfo("player") or "Olympus" end
	return false
end

-- The King's own guild (1.1.5): its centurions are the King's and the High Council's to name.
local function IsMain(guild) return type(guild) == "string" and ns.IsKingGuild(guild) == true end
Nominees.IsMain = IsMain
function Nominees.MainGuild() return ns.KingGuildName() end

-- `sender` is `guild`'s master as Borders proves the bronze: our own guild's from our roster (the
-- server's), another guild's from its census (two senders naming him, one of them someone else).
-- The King's guild's list (1.1.5): the King's character or a signed High Councillor.
local function Proven(sender, guild)
	if IsMain(guild) then return ns.IsKingCharacter(sender) == true or ns.IsHighCouncillor(sender) == true end
	local mine = GetGuildInfo("player")
	if mine and guild == mine then return ns.Roster.RankOf(sender) == 0 end
	if mine and guild:lower() == mine:lower() then return false end -- (our guild spelled another way)
	local rank, named = ns.Data.KnownRank(sender, guild)
	return rank == 0 and (named or 0) >= 2
end
Nominees.Proven = Proven

-- He is no longer that guild's master, as far as this client can tell: our roster gives him
-- another rank or names another guild master; another guild's census proves another one, or gives
-- him another rank. Nothing known (a census gone quiet): not that.
local function Deposed(l)
	-- The King's guild's (1.1.5): its sender neither the King's character nor a councillor any more.
	if l.main then return not (ns.IsKingCharacter(l.by) == true or ns.IsHighCouncillor(l.by) == true) end
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then
		local rank = ns.Roster.RankOf(l.by)
		if rank ~= nil then return rank ~= 0 end
		local stats = ns.Roster.lastStats
		local lead = ns.Roster.guild == mine and type(stats) == "table" and stats.leader or nil
		return type(lead) == "string" and ns.FullName(lead):lower() ~= l.by:lower()
	end
	local rank = ns.Data.KnownRank(l.by, l.guild)
	if rank ~= nil and rank ~= 0 then return true end
	local g = ns.Data.Guild(l.guild)
	if type(g) == "table" and type(g.leader) == "string" then
		local lead = ns.FullName(g.leader, g.realm)
		if lead:lower() ~= l.by:lower() then
			local other, named = ns.Data.KnownRank(lead, l.guild)
			if other == 0 and (named or 0) >= 2 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The guild master's own list (his client's alone)
---------------------------------------------------------------------------

-- His saved list for the guild he leads now, made when `make` (nil when he leads none).
-- { guild, rev, list = { { r = "c" | "d", d = department, n = "Name-Realm" }, ... } }
local function Saved(make)
	local master, guild = Nominees.IsMaster()
	if not master or not ns.rdb or not ns.me then return nil end
	local all = ns.rdb.nominees
	local s = type(all) == "table" and all[ns.me] or nil
	if type(s) ~= "table" or s.guild ~= guild or type(s.list) ~= "table" then
		if not make then return nil end
		if type(all) ~= "table" then all = {}; ns.rdb.nominees = all end
		s = { guild = guild, rev = ns.Now(), list = {} }
		all[ns.me] = s
	end
	return s
end

-- His entries as they count (a correspondent's department still one of the council's), in
-- order: { { role, dept, name } }; and the ones that do not (their department gone).
local function OwnEntries(s)
	local out, stale, c, depts = {}, {}, 0, {}
	for _, e in ipairs(s and s.list or {}) do
		if type(e) == "table" and type(e.n) == "string" then
			if e.r == "c" and c < Nominees.MAX_CENTURIONS then
				c = c + 1
				out[#out + 1] = { role = "centurion", name = e.n }
			elseif e.r == "d" then
				local dept = IsDept(e.d)
				if dept and not depts[dept:lower()] then
					depts[dept:lower()] = true
					out[#out + 1] = { role = "correspondent", dept = dept, name = e.n }
				else
					stale[#stale + 1] = { role = "correspondent", dept = tostring(e.d or "?"), name = e.n }
				end
			end
		end
	end
	return out, stale
end

---------------------------------------------------------------------------
-- The King's guild's centurions (1.1.5): the King's and the High Council's list
---------------------------------------------------------------------------

-- The King's character, or a signed High Councillor: they name the King's guild's centurions, and
-- their clients send its list. Not under the author's Asmon's view (King.Preview: his preview's own).
function Nominees.MainEditor()
	if ns.IsMember() ~= true then return false end
	local K = ns.King
	if type(K) ~= "table" or (K.Preview and K.Preview()) then return false end
	return (K.IsKing and K.IsKing() == true) or ns.IsHighCouncillor(ns.me) == true
end
-- The author's Asmon's view names them too, on his screen alone (nothing sent).
function Nominees.MainPreview() return ns.King ~= nil and ns.King.Preview ~= nil and ns.King.Preview() == true end
function Nominees.MainNames() return Nominees.MainEditor() or Nominees.MainPreview() end

-- The list this client names on: the King's and each councillor's (ns.rdb.mainNominees, the newest
-- heard taken as theirs), the Asmon's view's own (ns.db.previewMainNominees, gone with the view).
-- { rev, by, list = { { r = "c", n = "Name-Realm" }, ... } }; made when `make`.
local function MainStore(make)
	local preview = Nominees.MainPreview()
	local db = preview and ns.db or (Nominees.MainEditor() and ns.rdb) or nil
	if not db then return nil end
	local field = preview and "previewMainNominees" or "mainNominees"
	local s = db[field]
	if type(s) ~= "table" or type(s.list) ~= "table" then
		if not make then return nil end
		s = { rev = 0, list = {} }
		db[field] = s
	end
	return s, preview
end

-- Its centurions as they count (MAX_CENTURIONS at most), in order: { { role, name } }.
local function MainEntries(s)
	local out = {}
	for _, e in ipairs(s and s.list or {}) do
		if type(e) == "table" and e.r == "c" and type(e.n) == "string" and #out < Nominees.MAX_CENTURIONS then
			out[#out + 1] = { role = "centurion", name = e.n }
		end
	end
	return out
end

-- The list that counts for `guild` here: his own on the guild master's client; else the one
-- heard from its master, while fresh. nil for none. The King's guild's (1.1.5): the King's and a
-- councillor's own (the newest heard among it), else the newest heard while fresh.
local function ListOf(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	if IsMain(guild) then
		local s = MainStore(false)
		if s then
			local entries, set = MainEntries(s), {}
			for _, e in ipairs(entries) do set[e.name:lower()] = e end
			return { guild = guild, by = s.by or ns.me, rev = s.rev, entries = entries, set = set, own = true, main = true }
		end
	end
	local master, mine = Nominees.IsMaster()
	if master and mine == guild then
		local entries = OwnEntries(Saved(false))
		local set = {}
		for _, e in ipairs(entries) do set[e.name:lower()] = e end
		return { guild = guild, by = ns.me, entries = entries, set = set, own = true }
	end
	local l = lists[guild:lower()]
	if not l or ns.Now() - l.at > Nominees.FRESH then return nil end
	return l
end
Nominees.ListOf = ListOf

-- Whom `guild`'s master named `who` (Borders.lua): "centurion", or "correspondent" and its
-- department; nil for nobody. A lookup.
function Nominees.RoleOf(who, guild)
	if type(who) ~= "string" or who == "" then return nil end
	local l = ListOf(guild)
	local e = l and l.set[ns.FullName(who):lower()]
	if not e then return nil end
	return e.role, e.dept
end

-- Its parts, each one addon message: NM~1~<guild>~<rev>~<i>~<n>~<entries>.
local function Wire(name)
	return ns.RealmOf(name) == ns.realm and ns.ShortName(name) or name
end
function Nominees.Parts(guild, rev, entries)
	local head = ("NM~%s~%s~%d~"):format(Nominees.WIRE, guild, rev)
	local room = Nominees.PART - #head - #("16~16~")
	local bodies, body = {}, ""
	for _, e in ipairs(entries) do
		local text = e.role == "centurion" and ("c=" .. Wire(e.name)) or ("d=" .. e.dept .. "=" .. Wire(e.name))
		if body ~= "" and #body + 1 + #text > room then
			bodies[#bodies + 1], body = body, ""
		end
		body = body == "" and text or (body .. ";" .. text)
	end
	if body ~= "" or #bodies == 0 then bodies[#bodies + 1] = body end
	local out = {}
	for i, b in ipairs(bodies) do out[i] = ("%s%d~%d~%s"):format(head, i, #bodies, b) end
	return out
end

-- His list goes out (force: now; else once EVERY), from the guild master's client alone. Nobody
-- named yet, nothing sent; named and then all removed, the empty list (everyone drops it).
function Nominees.Send(force)
	if not RealMaster() then return false end -- (the author's view sends nothing)
	local s = Saved(false)
	if not s then return false end
	local now = ns.Now()
	if not force and now - lastSent < Nominees.EVERY then return false end
	local entries = OwnEntries(s)
	if #entries == 0 and not sentOnce then return false end
	lastSent, sentOnce = now, true
	for i, part in ipairs(Nominees.Parts(s.guild, tonumber(s.rev) or now, entries)) do
		ns.Comm.Send("CHANNEL", part, "nominees" .. i)
	end
	return true
end

local function SendSoon()
	if sendPending then return end
	sendPending = true
	ns.After(Nominees.SEND_AFTER, "nominees send", function()
		sendPending = false
		Nominees.Send(true)
	end)
end

local function Changed()
	Bump()
	ns.Fire("DATA_CHANGED")
end

-- The guild master names someone: role "centurion", or "correspondent" with a department.
-- Refused, with its reason, past the caps, outside his roster, twice, or for himself.
function Nominees.Name(role, input, dept)
	local s = Saved(false)
	local master, guild = Nominees.IsMaster()
	if not master then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	if raw == "" and UnitIsPlayer and UnitIsPlayer("target") then raw = ns.UnitFullName("target") or "" end
	local name = Person(raw)
	if not name then return false, ns.Print(L.NOMINEES_WHO) end
	-- His own guild's members alone, as his roster has them (the server's), in its spelling.
	local member = ns.Roster.guild == guild and RosterName(name, not ns.RealmOf(Trim(ns.Normal(raw)))) or nil
	if name:lower() == tostring(ns.me):lower() or (member and member:lower() == tostring(ns.me):lower()) then
		return false, ns.Print(L.NOMINEES_SELF)
	end
	if not member then return false, ns.Print(L.NOMINEES_NOT_MEMBER:format(ns.DisplayName(name))) end
	name = member
	local entries = OwnEntries(s)
	for _, e in ipairs(entries) do
		if e.name:lower() == name:lower() then
			return false, ns.Print(L.NOMINEES_ALREADY:format(ns.DisplayName(name), Nominees.RoleLabel(e.role, e.dept)))
		end
	end
	local entry
	if role == "centurion" then
		local c = 0
		for _, e in ipairs(entries) do if e.role == "centurion" then c = c + 1 end end
		if c >= Nominees.MAX_CENTURIONS then return false, ns.Print(L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS)) end
		entry = { r = "c", n = name }
	elseif role == "correspondent" then
		local d = IsDept(dept)
		if not d then return false, ns.Print(L.NOMINEES_NO_DEPT:format(tostring(dept or "?"))) end
		for _, e in ipairs(entries) do
			if e.role == "correspondent" and e.dept:lower() == d:lower() then
				return false, ns.Print(L.NOMINEES_DEPT_TAKEN:format(d, ns.DisplayName(e.name)))
			end
		end
		entry = { r = "d", d = d, n = name }
	else
		return false
	end
	s = Saved(true)
	-- (A correspondent whose department is gone gives his place up to the new one.)
	local _, stale = OwnEntries(s)
	if entry.r == "d" and #stale > 0 then
		local kept = {}
		for _, e in ipairs(s.list) do
			if not (e.r == "d" and not IsDept(e.d)) then kept[#kept + 1] = e end
		end
		s.list = kept
	end
	s.list[#s.list + 1] = entry
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_ADDED:format(ns.DisplayName(name), Nominees.RoleLabel(role, entry.d)))
	ns.Log("nominees: %s named %s (%s)", tostring(ns.me), name, role .. (entry.d and (" " .. entry.d) or ""))
	SendSoon()
	Changed()
	return true
end

-- The guild master removes one of his own (by name; typed without a realm, the one he named of
-- that name on another realm too, when only one).
function Nominees.Remove(input)
	local s = Saved(false)
	if not s then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	local name = Person(raw)
	local at, short, others = nil, name and ns.ShortName(name):lower(), {}
	for i, e in ipairs(s.list) do
		if type(e) == "table" and type(e.n) == "string" and name then
			if e.n:lower() == name:lower() then at = i break end
			if ns.ShortName(e.n):lower() == short then others[#others + 1] = i end
		end
	end
	if not at and #others == 1 and not ns.RealmOf(Trim(ns.Normal(raw))) then at = others[1] end
	local e = at and s.list[at]
	if not e then return false, ns.Print(L.NOMINEES_NOT_NAMED:format(ns.DisplayName(name) or raw)) end
	table.remove(s.list, at)
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	local dept = e.r == "d" and tostring(e.d or "?") or nil
	ns.Print(L.NOMINEES_REMOVED:format(ns.DisplayName(e.n), Nominees.RoleLabel(dept and "correspondent" or "centurion", dept)))
	ns.Log("nominees: %s removed %s", tostring(ns.me), e.n)
	SendSoon()
	Changed()
	return true
end

-- The King's guild's list goes out (force: now; else once EVERY, unless another of its namers sent
-- the newest one meanwhile), from the King's or a councillor's client alone: never the Asmon's
-- view's. Nobody named yet, nothing sent; named and then all removed, the empty list (it ends).
function Nominees.SendMain(force)
	if not Nominees.MainEditor() then return false end
	local s = MainStore(false)
	if not s or (tonumber(s.rev) or 0) <= 0 then return false end
	local now = ns.Now()
	if not force and now - math.max(lastMainSent, mainHeardAt) < Nominees.EVERY then return false end
	local entries = MainEntries(s)
	if #entries == 0 and not force and not mainSentOnce then return false end
	lastMainSent, mainSentOnce = now, true
	for i, part in ipairs(Nominees.Parts(Nominees.MainGuild(), tonumber(s.rev), entries)) do
		ns.Comm.Send("CHANNEL", part, "mainnominees" .. i)
	end
	return true
end

local function SendMainSoon()
	if mainSendPending then return end
	mainSendPending = true
	ns.After(Nominees.SEND_AFTER, "main nominees send", function()
		mainSendPending = false
		Nominees.SendMain(true)
	end)
end

-- The King or a High Councillor names a centurion of the King's guild (the Asmon's view on his
-- screen alone). Refused, with its reason, past the cap, twice, for himself, or (where our roster
-- is the King's guild's) outside it.
function Nominees.NameMain(input)
	if not Nominees.MainNames() then return false, ns.Print(L.NOMINEES_ONLY_MAIN) end
	local guild = Nominees.MainGuild()
	local raw = Trim(input)
	if raw == "" and UnitIsPlayer and UnitIsPlayer("target") then raw = ns.UnitFullName("target") or "" end
	local name = Person(raw)
	if not name then return false, ns.Print(L.NOMINEES_WHO) end
	if IsMain(ns.Roster.guild) then
		local member = RosterName(name, not ns.RealmOf(Trim(ns.Normal(raw))))
		if not member then return false, ns.Print(L.NOMINEES_MAIN_NOT_MEMBER:format(ns.DisplayName(name), guild)) end
		name = member
	end
	if name:lower() == tostring(ns.me):lower() then return false, ns.Print(L.NOMINEES_MAIN_SELF) end
	local entries = MainEntries(MainStore(false))
	for _, e in ipairs(entries) do
		if e.name:lower() == name:lower() then return false, ns.Print(L.NOMINEES_MAIN_ALREADY:format(ns.DisplayName(name), guild)) end
	end
	if #entries >= Nominees.MAX_CENTURIONS then return false, ns.Print(L.NOMINEES_MAIN_FULL:format(guild, Nominees.MAX_CENTURIONS)) end
	local s, preview = MainStore(true)
	local kept = {}
	for _, e in ipairs(entries) do kept[#kept + 1] = { r = "c", n = e.name } end
	kept[#kept + 1] = { r = "c", n = name }
	s.list, s.by = kept, ns.me
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_MAIN_ADDED:format(ns.DisplayName(name), guild))
	ns.Log("nominees: %s named %s centurion of <%s>%s", tostring(ns.me), name, guild, preview and " (preview)" or "")
	if not preview then SendMainSoon() end
	Changed()
	return true
end

-- The King or a High Councillor takes a centurion's title back (by name; typed without a realm,
-- the one of that name on another realm too, when only one).
function Nominees.RemoveMain(input)
	if not Nominees.MainNames() then return false, ns.Print(L.NOMINEES_ONLY_MAIN) end
	local guild = Nominees.MainGuild()
	local s, preview = MainStore(false)
	local raw = Trim(input)
	local name = Person(raw)
	local entries = MainEntries(s)
	local at, short, others = nil, name and ns.ShortName(name):lower(), {}
	for i, e in ipairs(entries) do
		if name and e.name:lower() == name:lower() then at = i break end
		if short and ns.ShortName(e.name):lower() == short then others[#others + 1] = i end
	end
	if not at and #others == 1 and not ns.RealmOf(Trim(ns.Normal(raw))) then at = others[1] end
	if not at then return false, ns.Print(L.NOMINEES_MAIN_NOT_NAMED:format(ns.DisplayName(name) or raw, guild)) end
	local gone = entries[at].name
	local kept = {}
	for i, e in ipairs(entries) do if i ~= at then kept[#kept + 1] = { r = "c", n = e.name } end end
	s.list, s.by = kept, ns.me
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_MAIN_REMOVED:format(ns.DisplayName(gone), guild))
	ns.Log("nominees: %s removed %s from <%s>'s centurions%s", tostring(ns.me), gone, guild, preview and " (preview)" or "")
	if not preview then SendMainSoon() end
	Changed()
	return true
end

---------------------------------------------------------------------------
-- Heard: a guild master's list
---------------------------------------------------------------------------

-- A list's entries from its parts, its caps held (the first ones kept), or nil when it can't be one.
local function Read(parts, n, realm, main)
	local entries, set, c, depts = {}, {}, 0, {}
	for i = 1, n do
		for entry in tostring(parts[i] or ""):gmatch("[^;]+") do
			local kind, a, b = entry:match("^(%a)=([^=]*)=?([^=]*)$")
			local e
			if kind == "c" and b == "" and c < Nominees.MAX_CENTURIONS then
				local name = Person(a, realm)
				if name and not set[name:lower()] then
					c = c + 1
					e = { role = "centurion", name = name }
				end
			elseif kind == "d" and b ~= "" and not main then -- (none for the King's guild: 1.1.5)
				local dept, name = DeptName(a), Person(b, realm)
				local count = 0
				for _ in pairs(depts) do count = count + 1 end
				if dept and name and not set[name:lower()] and not depts[dept:lower()] and count < Nominees.MAX_DEPTS then
					depts[dept:lower()] = true
					e = { role = "correspondent", dept = dept, name = name }
				end
			end
			if e then
				entries[#entries + 1] = e
				set[e.name:lower()] = e
			end
		end
	end
	return entries, set
end

-- What a list names, as text, to tell a new one from a repeat.
local function Signature(l)
	local out = { l.main and "" or l.by:lower() }
	for _, e in ipairs(l.entries) do out[#out + 1] = (e.dept or "") .. "=" .. e.name:lower() end
	return table.concat(out, ";")
end

-- A whole list from a proven guild master: kept (a repeat refreshes it), or dropped when it names
-- nobody. This client is told when it is named, or no longer.
local function Take(sender, guild, rev, entries, set)
	local key = guild:lower()
	local old = lists[key]
	if old and ns.Now() - old.at > Nominees.FRESH then old = nil end -- (gone quiet: as if none)
	if old and old.by == sender and rev < (old.rev or 0) then return end -- (an older one, late)
	local mine = GetGuildInfo("player")
	local was = old and old.set[tostring(ns.me):lower()]
	local l = { guild = guild, by = sender, rev = rev, at = ns.Now(), entries = entries, set = set }
	if #entries == 0 then
		lists[key] = nil
	else
		lists[key] = l
	end
	local now = #entries > 0 and set[tostring(ns.me):lower()] or nil
	if mine and guild == mine then
		if now and not (was and was.role == now.role and was.dept == now.dept) then
			ns.Print(L.NOMINEES_YOU:format(ns.DisplayName(sender) or "?", Nominees.RoleLabel(now.role, now.dept), guild))
		elseif was and not now then
			ns.Print(L.NOMINEES_NO_LONGER:format(Nominees.RoleLabel(was.role, was.dept), guild))
		end
	end
	if not old or #entries == 0 or Signature(old) ~= Signature(l) then
		ns.Log("nominees: <%s>'s list from %s, %d named", guild, sender, #entries)
		Changed()
	end
end

-- The King's guild's list (1.1.5), from the King or a councillor: the newest kept, whoever sent
-- it (an older one never over it; an empty one kept too, so an older one can't come back). The
-- King's and the councillors' clients take a newer one as their own, and count a repeat of the
-- newest as their turn to repeat it; theirs newer, they send it again soon.
local function TakeMain(sender, guild, rev, entries, set)
	local key = guild:lower()
	local own = Nominees.MainEditor() and ns.rdb and ns.rdb.mainNominees or nil
	local ownRev = type(own) == "table" and tonumber(own.rev) or nil
	if ownRev and rev < ownRev then return SendMainSoon() end
	local old = lists[key]
	if old and ns.Now() - old.at > Nominees.FRESH then old = nil end
	if old and rev < (old.rev or 0) then return end
	if ownRev and rev == ownRev then mainHeardAt = ns.Now() end
	local mine = GetGuildInfo("player")
	local before = ListOf(guild)
	local was = before and before.set[tostring(ns.me):lower()]
	local l = { guild = guild, by = sender, rev = rev, at = ns.Now(), entries = entries, set = set, main = true }
	lists[key] = l
	if Nominees.MainEditor() and ns.rdb and (not ownRev or rev > ownRev) then
		local list = {}
		for _, e in ipairs(entries) do list[#list + 1] = { r = "c", n = e.name } end
		ns.rdb.mainNominees = { rev = rev, by = sender, list = list }
		mainHeardAt = ns.Now()
	end
	local now = #entries > 0 and set[tostring(ns.me):lower()] or nil
	if mine and IsMain(mine) then
		if now and not was then
			ns.Print(L.NOMINEES_YOU:format(ns.DisplayName(sender) or "?", L.NOMINEE_ROLE_CENTURION, guild))
		elseif was and not now then
			ns.Print(L.NOMINEES_NO_LONGER:format(L.NOMINEE_ROLE_CENTURION, guild))
		end
	end
	if not before or Signature(before) ~= Signature(l) then
		ns.Log("nominees: <%s>'s list from %s, %d named", guild, sender, #entries)
		Changed()
	end
end

-- A part of a list, from the channel: only from that guild's master (Proven), put together with
-- the rest of its parts.
function Nominees.Handle(dist, sender, text)
	if dist ~= "CHANNEL" or type(sender) ~= "string" or type(text) ~= "string" or #text > 255 then return end
	local wire, guild, rev, i, n, body = text:match("^NM~(%d+)~([^~]*)~(%d+)~(%d+)~(%d+)~([^~]*)$")
	if wire ~= Nominees.WIRE then return end -- (another version's: not ours to read)
	guild, rev, i, n = GuildName(guild), tonumber(rev), tonumber(i), tonumber(n)
	if not guild or not rev or not i or not n or i < 1 or n < 1 or i > n or n > Nominees.MAX_PARTS then return end
	sender = ns.FullName(sender)
	if not Proven(sender, guild) then
		return ns.Log("nominees: <%s>'s list from %s refused: not its guild master here", guild, sender)
	end
	local now = ns.Now()
	local p = pending[sender]
	if not p or p.guild ~= guild or p.rev ~= rev or p.n ~= n or now - p.t > Nominees.PART_WAIT then
		p = { guild = guild, rev = rev, n = n, parts = {}, got = 0, t = now }
		pending[sender] = p
	end
	if not p.parts[i] then
		p.parts[i], p.got = body, p.got + 1
	end
	if p.got < n then return end
	pending[sender] = nil
	local main = IsMain(guild)
	local entries, set = Read(p.parts, n, ns.RealmOf(sender), main)
	if main then return TakeMain(sender, guild, rev, entries, set) end
	Take(sender, guild, rev, entries, set)
end
ns.Comm.Handle("NM", function(...) Nominees.Handle(...) end)

-- What Deposed reads for a list: our roster for our own guild; another guild's census row as it
-- stands (its time and votes, as Borders.Changed reads them). Asked again only when these change
-- (DATA_CHANGED comes with every census report heard).
local function DeposedInputs(l)
	if l.main then
		local c = ns.rdb and ns.rdb.council
		return c, type(c) == "table" and c.names or nil, ns.KingCharacter()
	end
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then return ns.Roster.byName, ns.Roster.lastStats, mine end
	local guilds = ns.rdb and ns.rdb.guilds
	local g = type(guilds) == "table" and guilds[l.guild] or nil
	return g, type(g) == "table" and g.t or nil, type(g) == "table" and g.vouch or nil
end

-- Lists whose master is no longer that guild's master, or that went quiet past FRESH, and parts
-- left waiting: dropped. Returns whether a list went.
function Nominees.Prune()
	local now, gone = ns.Now(), false
	for key, l in pairs(lists) do
		local a, b, c = DeposedInputs(l)
		local fresh = l.ia ~= a or l.ib ~= b or l.ic ~= c or not l.asked
		if fresh then l.ia, l.ib, l.ic, l.asked = a, b, c, true end
		if now - l.at > Nominees.FRESH then
			lists[key], gone = nil, true
		elseif fresh and Deposed(l) then
			lists[key], gone = nil, true
			ns.Log("nominees: <%s>'s list dropped: %s is no longer its guild master", l.guild, l.by)
		end
	end
	for sender, p in pairs(pending) do
		if now - p.t > Nominees.PART_WAIT then pending[sender] = nil end
	end
	if gone then Bump() end
	return gone
end

---------------------------------------------------------------------------
-- The pages: a guild master's Guild tab, the King's guild's centurions on the Throne (King.lua), and
-- the command
---------------------------------------------------------------------------

-- The guild master's own list, as his Guild tab shows it: { entries, stale }; nil for anyone else
-- (the Guild tab is his alone).
function Nominees.Ours()
	if not Nominees.IsMaster() then return nil end
	local entries, stale = OwnEntries(Saved(false))
	return { entries = entries, stale = stale }
end

-- How many he has named.
function Nominees.Count()
	local o = Nominees.Ours()
	return o and #o.entries or 0
end

-- The name box: a centurion or a department's correspondent of his guild; main: a centurion of
-- the King's guild (1.1.5, the King's or a councillor's).
function Nominees.Prompt(role, dept, main)
	if main then
		if not Nominees.MainNames() then return ns.Print(L.NOMINEES_ONLY_MAIN) end
		return ns.ShowDialog("OLYMPUS_NOMINEE", L.NOMINEE_ROLE_CENTURION, Nominees.MainGuild(), { role = "centurion", main = true })
	end
	local master, guild = Nominees.IsMaster()
	if not master then return ns.Print(L.NOMINEES_ONLY_MASTER) end
	return ns.ShowDialog("OLYMPUS_NOMINEE", Nominees.RoleLabel(role, dept), guild, { role = role, dept = dept })
end
-- Asked before a title is taken back (the box's data: his own's name; the King's guild's, a table).
function Nominees.AskRemove(e, main)
	if type(e) ~= "table" then return nil end
	if main then
		if not Nominees.MainNames() then return nil end
		return ns.ShowDialog("OLYMPUS_NOMINEE_REMOVE", ns.DisplayName(e.name), L.NOMINEES_MAIN_ROLE:format(Nominees.MainGuild()),
			{ name = e.name, main = true })
	end
	if not Nominees.IsMaster() then return nil end
	return ns.ShowDialog("OLYMPUS_NOMINEE_REMOVE", ns.DisplayName(e.name), Nominees.RoleLabel(e.role, e.dept), e.name)
end
local function Taken(data, text)
	data = type(data) == "table" and data or {}
	if data.main then return Nominees.NameMain(text) end
	return Nominees.Name(data.role, text, data.dept)
end
local function TakenBack(data)
	if type(data) == "table" then return data.main and Nominees.RemoveMain(data.name) or false end
	return Nominees.Remove(data)
end

-- The Throne's look (King.lua's Line, Para: dark ink on the parchment), as the Hands page's.
local function Ink() local K = ns.King return K.Line, K.INK, K.TITLE, K.Para end

-- A named one's line: a click takes the title back (asked first), when this client may.
local function Row(e, text, main, editable, roster)
	local Line, INK = Ink()
	local name = ns.DisplayName(e.name)
	return Line(text or name, INK, {
		key = name, indent = 1,
		right = roster and ns.Roster.RankOf(e.name) == nil and ns.Views.Grey(L.NOMINEES_NOT_IN_ROSTER) or nil,
		onClick = editable and function() Nominees.AskRemove(e, main) end or nil,
		tooltip = function(tt)
			tt:AddLine(name, 1, 0.82, 0)
			tt:AddLine(main and L.NOMINEES_MAIN_ROLE:format(Nominees.MainGuild()) or Nominees.RoleLabel(e.role, e.dept), 1, 1, 1, true)
			if editable then tt:AddLine(L.NOMINEES_CLICK_REMOVE, 0.6, 0.6, 0.6, true) end
		end,
	})
end

-- "+ Name a centurion (your target, or type a name)", its count; greyed when full (its click says why).
local function AddLine(count, main)
	local Line, _, TITLE = Ink()
	local full = count >= Nominees.MAX_CENTURIONS
	local add = "+ " .. L.NOMINEES_ADD_CENTURION
	local function Full()
		return main and L.NOMINEES_MAIN_FULL:format(Nominees.MainGuild(), Nominees.MAX_CENTURIONS) or L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS)
	end
	return Line(full and ns.Views.Grey(add) or add, TITLE, {
		right = ("%d/%d"):format(count, Nominees.MAX_CENTURIONS),
		onClick = function()
			if full then return ns.Print(Full()) end
			Nominees.Prompt("centurion", nil, main)
		end,
		tooltip = function(tt)
			tt:AddLine(L.NOMINEES_ADD_CENTURION, 1, 0.82, 0)
			tt:AddLine(full and Full() or L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
		end,
	})
end

-- The guild master's section, as the King's Hands page (King.lua's HandsLines): a title, a
-- one-line hint, "+ Name a centurion (your target, or type a name)", his centurions (a click takes
-- the title back, asked first), then the correspondents' departments, one line each (the role
-- picker: a click names that department's correspondent, or takes the title back), and the note
-- on how the army learns his list. Nothing for anyone but him.
function Nominees.PageLines(lines)
	local o = Nominees.Ours()
	if not o then return lines end
	local Line, INK, TITLE, Para = Ink()
	lines[#lines + 1] = Line(L.NOMINEES_TITLE, TITLE)
	Para(lines, L.NOMINEES_HINT, INK, { gapAfter = true })
	-- The centurions.
	local centurions = {}
	for _, e in ipairs(o.entries) do if e.role == "centurion" then centurions[#centurions + 1] = e end end
	lines[#lines + 1] = AddLine(#centurions)
	for _, e in ipairs(centurions) do lines[#lines + 1] = Row(e, nil, false, true, true) end
	if #centurions == 0 then lines[#lines + 1] = Line(L.NOMINEES_NONE, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	-- The correspondents: a line per department, its correspondent or a click to name one.
	local depts = Nominees.Departments()
	local byDept, named = {}, 0
	for _, e in ipairs(o.entries) do
		if e.role == "correspondent" then
			byDept[e.dept:lower()] = e
			named = named + 1
		end
	end
	lines[#lines + 1] = Line(L.NOMINEES_CORRESPONDENTS, TITLE, { right = ("%d/%d"):format(named, #depts) })
	for _, d in ipairs(depts) do
		local e = byDept[d:lower()]
		if e then
			lines[#lines + 1] = Row(e, d .. ": " .. ns.DisplayName(e.name), false, true, true)
		else
			lines[#lines + 1] = Line(d .. ": " .. L.NOMINEES_ADD_CORRESPONDENT, INK, { indent = 1,
				onClick = function() Nominees.Prompt("correspondent", d) end,
				tooltip = function(tt)
					tt:AddLine(Nominees.RoleLabel("correspondent", d), 1, 0.82, 0)
					tt:AddLine(L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
				end })
		end
	end
	-- (His own whose department the council's list no longer has: they count for nothing, sent to nobody.)
	for _, e in ipairs(o.stale) do
		local row = Row(e, e.dept .. ": " .. ns.DisplayName(e.name), false, true, true)
		row.right = ns.Views.Grey(L.NOMINEES_DEPT_GONE)
		lines[#lines + 1] = row
	end
	if #depts == 0 then lines[#lines + 1] = Line(L.NOMINEES_NO_DEPTS, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	return Para(lines, L.NOMINEES_NOTE:format(math.floor(Nominees.FRESH / 3600)), INK)
end

-- A guild master's Guild tab (1.1.5): the tab in the Throne's place, his guild's page (King.Build).
function Nominees.GuildLines()
	local master, guild = Nominees.IsMaster()
	if not master then return {} end
	local Line, _, TITLE = Ink()
	return Nominees.PageLines({ Line(L.GUILD_TAB_TITLE:format(tostring(guild)), TITLE, { gapAfter = true }) })
end

-- The King's guild's centurions (1.1.5), on the Throne's page: a title, a hint, then for the King
-- or a councillor "+ Name a centurion" and the list a click takes back from; for his Steward or a
-- Hand, the list to read; the note. (Its department heads come in 1.1.6: no correspondents here.)
function Nominees.MainLines(lines)
	local Line, INK, TITLE, Para = Ink()
	local guild = Nominees.MainGuild()
	local editable = Nominees.MainNames()
	local l = ListOf(guild)
	local entries = l and l.entries or {}
	lines[#lines + 1] = Line(L.NOMINEES_MAIN_TITLE:format(guild), TITLE)
	Para(lines, L.NOMINEES_MAIN_HINT, INK, { gapAfter = true })
	if editable then lines[#lines + 1] = AddLine(#entries, true) end
	for _, e in ipairs(entries) do lines[#lines + 1] = Row(e, nil, true, editable, IsMain(ns.Roster.guild)) end
	if #entries == 0 then lines[#lines + 1] = Line(L.NOMINEES_NONE, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	return Para(lines, L.NOMINEES_MAIN_NOTE:format(math.floor(Nominees.FRESH / 3600)), INK)
end

-- /oly status: a guild master's own list, and the lists this client holds, each its master's
-- (five named, the rest counted).
function Nominees.StatusLine()
	local out, held, now = {}, {}, ns.Now()
	local o = Nominees.Ours()
	if o then out[1] = ("yours %d of %d"):format(#o.entries, Nominees.MAX) end
	-- (1.1.5: the King's guild's, on the King's or a councillor's client: theirs to name.)
	local s, preview = MainStore(false)
	if s then out[#out + 1] = ("<%s>'s %d of %d (%s)"):format(Nominees.MainGuild(), #MainEntries(s), Nominees.MAX_CENTURIONS, preview and "preview" or "yours to name") end
	for _, l in pairs(lists) do
		if now - l.at <= Nominees.FRESH then held[#held + 1] = l end
	end
	table.sort(held, function(a, b) return a.guild < b.guild end)
	for i, l in ipairs(held) do
		if i > 5 then out[#out + 1] = ("and %d more"):format(#held - 5) break end
		out[#out + 1] = ("<%s> %d by %s (heard %s)"):format(l.guild, #l.entries, ns.DisplayName(l.by) or "?", ns.Ago(l.at))
	end
	return #out > 0 and table.concat(out, ", ") or "none"
end

-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]`: alone, the tab
-- (a guild master's Guild tab; the Throne, with the King's guild's centurions, for the King's people).
-- A guild master names in his own guild; the King or a councillor, the King's guild's centurions
-- (no correspondents there). Anyone else is told whose it is.
function Nominees.Slash(rest)
	rest = Trim(rest)
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	-- The author's guild master's view (his alone: anyone else gets the usual answer below).
	if verb == "view" and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() then
		Nominees.SetDevView(not Nominees.DevView())
		if Nominees.DevView() then verb = "" else return end
	end
	local master, main = Nominees.IsMaster(), not Nominees.IsMaster() and Nominees.MainNames()
	if verb == "" then
		local K = ns.King
		if not (K and K.TabVisible and K.TabVisible()) then return ns.Print(L.NOMINEES_ONLY_MASTER) end
		K.mode = "home" -- (the Throne Room, or his Guild tab: never the King's Hands page)
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("throne") end
		return
	end
	local centurion = verb == "centurion" or verb == "centuriao" or verb == "centurião"
	local remove = verb == "remove" or verb == "remover"
	if main and centurion then return Nominees.NameMain(arg) end
	if main and remove then return Nominees.RemoveMain(arg) end
	if centurion then return Nominees.Name("centurion", arg) end
	if (verb == "correspondent" or verb == "correspondente") and (master or not main) then
		local n, name = arg:match("^(%d+)%s*(.-)$")
		local d = n and Nominees.Departments()[tonumber(n)]
		if not d then
			local list = {}
			for i, dept in ipairs(Nominees.Departments()) do list[#list + 1] = ("%d %s"):format(i, dept) end
			return ns.Print(L.NOMINEES_DEPTS:format(#list > 0 and table.concat(list, ", ") or L.NOMINEES_NONE))
		end
		return Nominees.Name("correspondent", name, d)
	end
	if remove then return Nominees.Remove(arg) end
	ns.Print(L.NOMINEES_USAGE)
end

StaticPopupDialogs["OLYMPUS_NOMINEE"] = {
	text = L.NOMINEES_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 60,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
			eb:SetText(target and ns.DisplayName(target) or "")
			ns.Focus(eb)
		end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("name nominee", Taken, data or (self and self.data), eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("name nominee", Taken, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_NOMINEE_REMOVE"] = {
	text = L.NOMINEES_REMOVE_CONFIRM,
	button1 = L.NOMINEES_REMOVE_BTN,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("remove nominee", TakenBack, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Before Borders.lua's and Nameplates.lua's (this file loads first): a list whose master was
-- deposed by the census or roster just heard is gone when they work their borders out again.
ns.On("DATA_CHANGED", function() Nominees.Prune() end)
ns.On("LOGIN", function()
	ns.Every(60, "nominees", function()
		Nominees.Send()
		Nominees.SendMain()
		if Nominees.Prune() then ns.Fire("DATA_CHANGED") end
	end)
end)

-- Tests start from a clean state.
function Nominees.Reset()
	wipe(lists); wipe(pending)
	lastSent, sendPending, sentOnce = -math.huge, false, false
	lastMainSent, mainHeardAt, mainSendPending, mainSentOnce = -math.huge, -math.huge, false, false
	Bump()
end
