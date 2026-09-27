local ADDON, ns = ...
local L = ns.L

-- The Workshop: the addon author's own tab (his character alone, ns.AUTHOR), to see how the
-- addon does across the army and to help the players who run it.
--   * Installs and versions per guild, from the reports every guild sends anyway (field 24:
--     the versions of the guild's addon users, counted by its reporter from their hellos).
--   * A roll call on demand: each addon answers with its version, client, window and what
--     works (V1/V2); when the army is large, only a share of them answers.
--   * A report to copy for Discord.
--   * "Please update", to a player on an old version: a fixed text, nothing else (V3).
--   * The author's presence (V4): players can send him their bug report from the Report a
--     bug window (V5), and nowhere else.
-- Only the character named ns.AUTHOR can send V1, V3 and V4, and only he receives V2 and V5.
-- Forever names (first name and surname) are unique across its realm group, and on the
-- Classic realms no name has a space: nobody else can carry his. Receivers answer a roll call
-- once per ROLL_GAP, and show "please update" once per UPDATE_GAP, only when really behind.
--   V1~<id>~<share 1-100>                                              (channel)
--   V2~<id>~<version>~<guild>~<client>~<window>~<flags>~<errors>~<level>~<class>   (whisper)
--   V3~<latest version>                                                (whisper)
--   V4~<version>                                                       (channel)
--   V5~<id>~<i>~<n>~<piece>                                            (whisper)
--   V6~<id>~<1|2>   the author got piece 1 (send the rest) | the whole report   (whisper)
-- A bug report goes out one piece first: only once the author answers (he is really online)
-- does the rest follow, so nothing is whispered to someone who logged off.

local Workshop = {}
ns.Workshop = Workshop

Workshop.ROLL_GAP = 4 * 60      -- a client answers one roll call in this long (the author asks every 5 min at most)
Workshop.ROLL_EVERY = 5 * 60    -- the author asks at most this often
Workshop.ROLL_OPEN = 5 * 60     -- answers count this long after the ask
Workshop.ROLL_SPREAD = 30       -- answers are spread over this many seconds
Workshop.ROLL_TARGET = 300      -- answers wanted, however large the army (the share)
Workshop.MAX_ANSWERS = 3000
Workshop.UPDATE_GAP = 10 * 60   -- "please update" at most this often, both ways
Workshop.PRESENCE_EVERY = 5 * 60
Workshop.PRESENCE_FRESH = 11 * 60
Workshop.ROLL_AFTER = 90        -- no roll call this soon after login: the census is still coming
Workshop.ASK_EVERY = 20         -- "Ask to update" at most this often (the send queue holds 60)
Workshop.BUG_ACK = 15           -- the author answers the first piece within this, or is offline
Workshop.BUG_GAP = 10 * 60      -- a player sends one bug report in this long
Workshop.BUG_MAX = 4800         -- bytes of a bug report (MAX_PIECES pieces)
Workshop.PIECE = 200
Workshop.MAX_PIECES = 25
Workshop.MAX_REPORTS = 30
Workshop.MAX_SHOWN = 30
Workshop.MAX_ASK = 15           -- "please update" whispers per click (the send queue holds 60)

-- Swappable in tests.
Workshop.random = math.random
Workshop.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local roll            -- the author's roll calls: { id, t, share, answers = { [sender] = answer }, count }
                      -- answers stay from one roll call to the next (a newer answer replaces)
local reports = {}    -- bug reports received: { from, t, text }, newest last
local pieces = {}     -- [sender#id] = { n, got, parts, t }
local bugsFrom = {}   -- [sender] = times of their reports this hour
local asked = {}      -- [sender] = when we last asked them to update
local lastRoll, lastRollAnswer, lastUpdateShown, lastBug = -math.huge, -math.huge, -math.huge, -math.huge
local lastAsk = -math.huge
local answeredRoll    -- the roll call id we answered last
local sending         -- our bug report waiting for the author's go: { id, pieces, to }
local authorAt, authorName -- the author's last presence, and his full name
local changePending = false

local function Changed()
	if changePending then return end
	changePending = true
	Workshop.after(1, "workshop changed", function()
		changePending = false
		ns.Fire("WORKSHOP_CHANGED")
	end)
end

---------------------------------------------------------------------------
-- Who is who
---------------------------------------------------------------------------

-- His name, on his realm group (Forever's PvP realms).
local function IsAuthorName(name)
	if type(name) ~= "string" or ns.ShortName(name) ~= ns.AUTHOR then return false end
	local realm = ns.RealmOf(ns.FullName(name))
	return realm ~= nil and ns.GroupOf(realm) == ns.GroupOf(ns.AUTHOR_REALM)
end

function Workshop.IsAuthor() return IsAuthorName(ns.me) end
Workshop.IsAuthorName = IsAuthorName

-- The author's test characters (Dev.lua, never published) see the tab too: nothing it sends
-- goes anywhere but the test bench's log (DevTest.lua), or is ignored by everyone.
function Workshop.Preview()
	local dev = ns.devWorkshop
	if type(dev) == "table" then dev = dev[UnitName and UnitName("player") or ""] == true or dev[ns.ShortName(ns.me or "")] == true end
	return dev == true and not Workshop.IsAuthor()
end

function Workshop.Visible() return Workshop.IsAuthor() or Workshop.Preview() end

-- The author is online (his presence was heard lately), and not us.
function Workshop.AuthorOnline()
	if Workshop.IsAuthor() or not authorAt then return false end
	return ns.Now() - authorAt <= Workshop.PRESENCE_FRESH
end
function Workshop.AuthorName() return authorName end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

-- "0.8.2" -> { 0, 8, 2 }; anything else -> nil.
local function Parts(v)
	local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	return { tonumber(a), tonumber(b), tonumber(c) }
end

-- a is newer than b.
function Workshop.Newer(a, b)
	local x, y = Parts(a), Parts(b)
	if not x or not y then return false end
	for i = 1, 3 do
		if x[i] ~= y[i] then return x[i] > y[i] end
	end
	return false
end

-- The newest version: the author's own, who runs the newest. What others claim never raises
-- it (anyone can send any number), so "please update" never names a version that is not out.
function Workshop.Latest() return ns.VERSION end

---------------------------------------------------------------------------
-- This client, as a roll call answer tells it
---------------------------------------------------------------------------

-- Plain text: no separators, escape codes, Discord markup (` @) or control characters.
local function Clean(s, max)
	return (tostring(s or ""):gsub("[~|`@%c]", "")):sub(1, max or 40)
end

-- Only values a real addon sends: anything else becomes "?".
local CLIENTS = { Forever = true, Era = true, Anniversary = true }
local WINDOWS = { hd = true, old = true }
local function Version(v) return (type(v) == "string" and v:match("^%d+%.%d+%.%d+$")) and v or "?" end

-- Which game: by the interface number (Forever 1.60, Era 1.15, Anniversary 2.5).
function Workshop.Client()
	local toc = select(4, GetBuildInfo())
	toc = tonumber(toc) or 0
	if toc >= 16000 and toc < 20000 then return "Forever" end
	if toc >= 20000 and toc < 30000 then return "Anniversary" end
	if toc >= 10000 and toc < 16000 then return "Era" end
	return tostring(toc)
end

-- Letters for what works here: c channel joined, r our guild's reporter, k sealed channel,
-- m map library, p map markers on.
function Workshop.Flags()
	local f = {}
	if ns.Comm.ChannelReady() then f[#f + 1] = "c" end
	if ns.Comm.isReporter then f[#f + 1] = "r" end
	if ns.rdb and ns.rdb.realmKey then f[#f + 1] = "k" end
	if ns.Pins and ns.Pins() then f[#f + 1] = "m" end
	if ns.db and ns.db.showMap then f[#f + 1] = "p" end
	return table.concat(f)
end

-- What a roll call gets (0.9.2): the addon's version, the game client, and the channel's state
-- (joined, our guild's reporter, sealed). Nothing about the character: no guild, level or class,
-- no window style, no error count (those fields stay, empty, for the author's older version).
local function Answer(id)
	local flags = Workshop.Flags():gsub("[^crk]", "")
	return ("V2~%d~%s~~%s~~%s~0~0~"):format(id, Clean(ns.VERSION, 12), Workshop.Client(), flags)
end

-- A player can refuse the author's roll calls and update notices: /oly rollcall off (0.9.2).
function Workshop.Answers() return not (ns.db and ns.db.rollCall == false) end
function Workshop.SetAnswers(on)
	ns.db.rollCall = on and true or false
	ns.Print(on and L.ROLLCALL_ON or L.ROLLCALL_OFF)
end

---------------------------------------------------------------------------
-- Roll call
---------------------------------------------------------------------------

-- How many of the army answer: all of it while small, a share of it once large.
function Workshop.Share(users)
	users = tonumber(users) or 0
	if users <= Workshop.ROLL_TARGET then return 100 end
	return math.max(5, math.min(100, math.ceil(Workshop.ROLL_TARGET * 100 / users)))
end

-- The addon users the reports count, over every fresh guild.
function Workshop.ReportedUsers()
	local n, now = 0, ns.Now()
	for name, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" and ns.IsFederation(name) and now - (g.t or 0) <= ns.Data.FRESH then n = n + (g.users or 0) end
	end
	return n
end

function Workshop.RollCall()
	if not Workshop.Visible() then return end
	local now = ns.Now()
	if now - lastRoll < Workshop.ROLL_EVERY then
		return ns.Print(L.WORKSHOP_ROLL_WAIT:format(math.ceil((Workshop.ROLL_EVERY - (now - lastRoll)) / 60)))
	end
	-- Before the census is in, the army's size is unknown: every addon would answer.
	local users = Workshop.ReportedUsers()
	if users == 0 or now - (ns.Comm.loginAt or 0) < Workshop.ROLL_AFTER then return ns.Print(L.WORKSHOP_ROLL_EARLY) end
	lastRoll = now
	local share = Workshop.Share(users)
	-- The answers so far stay: a newer one replaces a player's older one.
	local answers, count = roll and roll.answers or {}, roll and roll.count or 0
	roll = { id = Workshop.random(1, 99999), t = now, share = share, answers = answers, count = count }
	ns.Comm.Send("CHANNEL", ("V1~%d~%d"):format(roll.id, share), "rollcall")
	ns.Print(L.WORKSHOP_ROLL_SENT:format(share))
	Changed()
end

function Workshop.HandleRoll(dist, sender, text)
	if dist ~= "CHANNEL" or not IsAuthorName(sender) or Workshop.IsAuthor() or not Workshop.Answers() then return end
	local id, share = text:match("^V1~(%d+)~(%d+)$")
	id, share = tonumber(id), tonumber(share)
	if not id or not share then return end
	authorAt, authorName = ns.Now(), ns.FullName(sender)
	local now = ns.Now()
	if id == answeredRoll or now - lastRollAnswer < Workshop.ROLL_GAP then return end
	answeredRoll = id
	if Workshop.random(1, 100) > math.max(1, math.min(100, share)) then return end
	lastRollAnswer = now
	-- Spread over ROLL_SPREAD: a thousand answers do not arrive in the same second.
	Workshop.after(1 + Workshop.random() * Workshop.ROLL_SPREAD, "roll call answer", function()
		ns.Comm.Whisper(ns.FullName(sender), Answer(id), "rollanswer")
	end)
end

function Workshop.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" or not Workshop.Visible() or not roll then return end
	if ns.Now() - roll.t > Workshop.ROLL_OPEN then return end
	local id, version, guild, client, window, flags, errors, level, class =
		text:match("^V2~(%d+)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~(%d+)~(%d+)~([^~]*)$")
	if tonumber(id) ~= roll.id then return end
	sender = ns.FullName(sender)
	local before = roll.answers[sender]
	if before and before.roll == roll.id then return end
	if not before and roll.count >= Workshop.MAX_ANSWERS then return end
	if not before then roll.count = roll.count + 1 end
	roll.answers[sender] = {
		name = sender, roll = roll.id, version = Version(version), guild = Clean(guild, 40),
		client = CLIENTS[client] and client or "?", window = WINDOWS[window] and window or "?",
		flags = (flags or ""):gsub("[^crkmp]", ""):sub(1, 5), errors = math.min(tonumber(errors) or 0, 999),
		level = math.min(tonumber(level) or 0, 99), class = Clean(class, 2), t = ns.Now(),
	}
	Changed()
end

---------------------------------------------------------------------------
-- Please update
---------------------------------------------------------------------------

function Workshop.AskUpdate(name)
	if not Workshop.Visible() or type(name) ~= "string" then return false end
	local now = ns.Now()
	local key = ns.FullName(name)
	if now - (asked[key] or -math.huge) < Workshop.UPDATE_GAP then return false end
	asked[key] = now
	ns.Comm.Whisper(key, "V3~" .. Workshop.Latest(), "askupdate:" .. key) -- one queued per player
	return true
end

-- Every roll call answer on an old version, MAX_ASK at most per click.
function Workshop.AskOutdated()
	local now = ns.Now()
	if now - lastAsk < Workshop.ASK_EVERY then return end
	lastAsk = now
	local latest, n = Workshop.Latest(), 0
	for _, a in pairs(roll and roll.answers or {}) do
		if n >= Workshop.MAX_ASK then break end
		if Workshop.Newer(latest, a.version) and Workshop.AskUpdate(a.name) then n = n + 1 end
	end
	ns.Print(L.WORKSHOP_ASKED:format(n, latest))
	Changed()
end

function Workshop.HandleUpdate(dist, sender, text)
	if dist ~= "WHISPER" or not IsAuthorName(sender) or not Workshop.Answers() then return end
	local latest = text:match("^V3~(%d+%.%d+%.%d+)$")
	if not latest or not Workshop.Newer(latest, ns.VERSION) then return end
	local now = ns.Now()
	if now - lastUpdateShown < Workshop.UPDATE_GAP then return end
	lastUpdateShown = now
	ns.PlayAlert("soft")
	ns.ShowDialog("OLYMPUS_AUTHOR_UPDATE", ns.VERSION, latest)
end

StaticPopupDialogs["OLYMPUS_AUTHOR_UPDATE"] = {
	text = L.WORKSHOP_UPDATE_POPUP,
	button1 = OKAY or "OK",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The author's presence, and bug reports to him
---------------------------------------------------------------------------

function Workshop.SendPresence()
	if not Workshop.IsAuthor() then return end
	ns.Comm.Send("CHANNEL", "V4~" .. Clean(ns.VERSION, 12), "presence")
end

function Workshop.HandlePresence(dist, sender, text)
	if dist ~= "CHANNEL" or not IsAuthorName(sender) or Workshop.IsAuthor() then return end
	if not text:match("^V4~") then return end
	local was = Workshop.AuthorOnline()
	authorAt, authorName = ns.Now(), ns.FullName(sender)
	if not was then ns.Fire("DATA_CHANGED") end
end

-- The bug report as it travels: no newlines or pipes (they are put back as "\n" and "!").
local function Pack(text)
	text = tostring(text or ""):gsub("|", "!"):gsub("\r", ""):gsub("\n", "\\n")
	if #text > Workshop.BUG_MAX then text = text:sub(1, Workshop.BUG_MAX - 8) .. "\\n[cut]" end
	return text
end

-- The button the Report a bug window shows while the author is online, or nil.
function Workshop.BugAction(text)
	if not Workshop.AuthorOnline() or not authorName then return nil end
	return {
		label = L.WORKSHOP_SEND_BUG:format(ns.DisplayName(authorName)),
		fn = function() return Workshop.SendBug(text) end,
	}
end

-- Piece 1 now; the rest once the author answers it (Workshop.HandleAck). No answer within
-- BUG_ACK: he is gone, the player is told and may try again later.
function Workshop.SendBug(text)
	if not Workshop.AuthorOnline() or not authorName then return false end
	local now = ns.Now()
	if sending or now - lastBug < Workshop.BUG_GAP then
		ns.Print(L.WORKSHOP_BUG_WAIT:format(math.max(1, math.ceil((Workshop.BUG_GAP - (now - lastBug)) / 60))))
		return false
	end
	lastBug = now
	local body = Pack(text)
	local n = math.min(Workshop.MAX_PIECES, math.max(1, math.ceil(#body / Workshop.PIECE)))
	local id = Workshop.random(1, 99999)
	local list = {}
	for i = 1, n do
		list[i] = ("V5~%d~%d~%d~%s"):format(id, i, n, body:sub((i - 1) * Workshop.PIECE + 1, i * Workshop.PIECE))
	end
	sending = { id = id, pieces = list, to = authorName }
	ns.Comm.Whisper(authorName, list[1], "bug" .. id .. ":1")
	ns.Print(L.WORKSHOP_BUG_SENDING:format(ns.DisplayName(authorName)))
	Workshop.after(Workshop.BUG_ACK, "bug report ack", function()
		if sending and sending.id == id and not sending.go then
			sending, lastBug = nil, -math.huge
			ns.Print(L.WORKSHOP_BUG_NO_AUTHOR)
		end
	end)
	return true
end

function Workshop.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" or not IsAuthorName(sender) or not sending then return end
	local id, stage = text:match("^V6~(%d+)~([12])$")
	if tonumber(id) ~= sending.id then return end
	if stage == "1" and not sending.go then
		sending.go = true
		for i = 2, #sending.pieces do ns.Comm.Whisper(sending.to, sending.pieces[i], "bug" .. id .. ":" .. i) end
	elseif stage == "2" then
		sending = nil
		ns.Print(L.WORKSHOP_BUG_SENT:format(ns.DisplayName(ns.FullName(sender))))
	end
end

function Workshop.HandleBug(dist, sender, text)
	if dist ~= "WHISPER" or not Workshop.Visible() then return end
	local id, i, n, piece = text:match("^V5~(%d+)~(%d+)~(%d+)~(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not id or not i or not n or n < 1 or n > Workshop.MAX_PIECES or i < 1 or i > n then return end
	sender = ns.FullName(sender)
	local now = ns.Now()
	-- One report at a time per player (a newer one replaces it), three started an hour, ten
	-- players at a time; a report with no new piece for 60 s is dropped.
	for k, p in pairs(pieces) do
		if now - p.t > 60 then pieces[k] = nil end
	end
	local e = pieces[sender]
	if not e or e.id ~= id then
		if i ~= 1 then return end
		local times = bugsFrom[sender] or {}
		for k = #times, 1, -1 do if now - times[k] > 3600 then table.remove(times, k) end end
		if #times >= 3 then return end
		local open = 0
		for k in pairs(pieces) do if k ~= sender then open = open + 1 end end
		if open >= 10 then return end
		times[#times + 1] = now
		bugsFrom[sender] = times
		e = { id = id, n = n, got = 0, parts = {}, t = now }
		pieces[sender] = e
		-- Here: the rest may come.
		if n > 1 then ns.Comm.Whisper(sender, ("V6~%s~1"):format(id), "bugack:" .. sender) end
	end
	if e.n ~= n or e.parts[i] then return end
	e.parts[i], e.got, e.t = piece:sub(1, Workshop.PIECE):gsub("|", "!"), e.got + 1, now
	if e.got < n then return end
	pieces[sender] = nil
	ns.Comm.Whisper(sender, ("V6~%s~2"):format(id), "bugack:" .. sender)
	reports[#reports + 1] = { from = sender, t = now, text = (table.concat(e.parts):gsub("\\n", "\n")) }
	while #reports > Workshop.MAX_REPORTS do table.remove(reports, 1) end
	ns.PlayAlert("soft")
	ns.Print(L.WORKSHOP_BUG_IN:format(ns.DisplayName(sender)))
	Changed()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff4040" .. s .. "|r" end

-- "0.8.2 12  ·  0.8.1 3", newest first.
local function Versions(map)
	local list = {}
	for v, n in pairs(map or {}) do list[#list + 1] = { v = v, n = n } end
	table.sort(list, function(a, b)
		if a.v ~= b.v then return Workshop.Newer(a.v, b.v) end
		return a.n > b.n
	end)
	local latest, parts = Workshop.Latest(), {}
	for _, e in ipairs(list) do
		local label = e.v .. " " .. e.n
		parts[#parts + 1] = Workshop.Newer(latest, e.v) and Red(label) or Green(label)
	end
	return #parts > 0 and table.concat(parts, "  ·  ") or Grey("?")
end

local function Count(map, key) map[key] = (map[key] or 0) + 1 end

-- The reports' view: every guild's addon users and their versions.
local function InstallLines(lines)
	local now, rows, users, versions = ns.Now(), {}, 0, {}
	for name, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" and ns.IsFederation(name) and now - (g.t or 0) <= ns.Data.FRESH then
			rows[#rows + 1] = { name = name, g = g }
			users = users + (g.users or 0)
			for v, n in pairs(g.versions or {}) do versions[v] = (versions[v] or 0) + n end
		end
	end
	table.sort(rows, function(a, b)
		if (a.g.users or 0) ~= (b.g.users or 0) then return (a.g.users or 0) > (b.g.users or 0) end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_INSTALLS, right = Gold(L.WORKSHOP_USERS:format(users, #rows)) }
	lines[#lines + 1] = { text = L.WORKSHOP_VERSIONS .. ": " .. Versions(versions), gapAfter = #rows == 0 }
	if #rows == 0 then lines[#lines].text = Grey(L.EMPTY) end
	for i = 1, math.min(Workshop.MAX_SHOWN, #rows) do
		local e = rows[i]
		lines[#lines + 1] = {
			indent = 1, text = Green("<" .. e.name .. ">") .. "  " .. (next(e.g.versions or {}) and Versions(e.g.versions) or Grey(L.WORKSHOP_OLD_REPORTER)),
			right = L.WORKSHOP_OF_ONLINE:format(e.g.users or 0, e.g.online or 0),
		}
	end
	lines[#lines].gapAfter = true
end

local function Problems(a, latest)
	local out = {}
	if Workshop.Newer(latest, a.version) then out[#out + 1] = Red(a.version) end
	if a.errors > 0 then out[#out + 1] = Red(L.WORKSHOP_ERRORS:format(a.errors)) end
	if not a.flags:find("c", 1, true) then out[#out + 1] = Red(L.WORKSHOP_NO_CHANNEL) end
	return out
end

local function RollLines(lines)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_ROLL, right = roll and Grey(ns.Ago(roll.t)) or nil }
	if not roll then
		lines[#lines + 1] = { text = Grey(L.WORKSHOP_ROLL_NONE), gapAfter = true }
		return
	end
	local versions, clients, windows, noChannel, withErrors = {}, {}, {}, 0, 0
	local latest, list = Workshop.Latest(), {}
	for _, a in pairs(roll.answers) do
		Count(versions, a.version)
		Count(clients, a.client)
		Count(windows, a.window)
		if not a.flags:find("c", 1, true) then noChannel = noChannel + 1 end
		if a.errors > 0 then withErrors = withErrors + 1 end
		if #Problems(a, latest) > 0 then list[#list + 1] = a end
	end
	local function Join(map)
		local parts = {}
		for k, n in pairs(map) do parts[#parts + 1] = k .. " " .. n end
		table.sort(parts)
		return #parts > 0 and table.concat(parts, "  ·  ") or "-"
	end
	lines[#lines + 1] = { text = L.WORKSHOP_ANSWERS:format(roll.count, roll.share) }
	lines[#lines].right = Grey(L.WORKSHOP_LAST:format(ns.Ago(roll.t)))
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_VERSIONS .. ": " .. Versions(versions) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_CLIENTS .. ": " .. Join(clients) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_WINDOWS .. ": " .. Join(windows) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_HEALTH:format(noChannel, withErrors), gapAfter = true }
	table.sort(list, function(a, b)
		if a.errors ~= b.errors then return a.errors > b.errors end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_ATTENTION:format(#list) }
	if #list == 0 then lines[#lines + 1] = { text = Grey(L.WORKSHOP_ALL_GOOD) } end
	for i = 1, math.min(Workshop.MAX_SHOWN, #list) do
		local a = list[i]
		local outdated = Workshop.Newer(latest, a.version)
		lines[#lines + 1] = {
			key = a.name, indent = 1,
			text = ns.DisplayName(a.name) .. "  " .. Grey("<" .. (a.guild ~= "" and a.guild or "?") .. ">"),
			right = table.concat(Problems(a, latest), "  "),
			onClick = function()
				if outdated then
					ns.ShowDialog("OLYMPUS_WORKSHOP_ASK", ns.DisplayName(a.name), nil, a.name)
				else
					ns.UI.ShowPerson({ name = ns.DisplayName(a.name), level = a.level, class = a.class ~= "" and a.class or nil, guild = a.guild })
				end
			end,
			tooltip = function(tt)
				tt:AddLine(ns.DisplayName(a.name), 1, 0.82, 0)
				tt:AddLine(("%s  ·  %s  ·  %s  ·  %s"):format(a.version, a.client, a.window, a.flags ~= "" and a.flags or "-"), 1, 1, 1)
				if outdated then tt:AddLine(L.WORKSHOP_CLICK_ASK, 0.25, 1, 0.25, true) end
			end,
		}
	end
	if #list > Workshop.MAX_SHOWN then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#list - Workshop.MAX_SHOWN)) } end
	lines[#lines].gapAfter = true
end

StaticPopupDialogs["OLYMPUS_WORKSHOP_ASK"] = {
	text = L.WORKSHOP_ASK_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data)
		ns.SafeCall("workshop ask", function()
			local name = data or (self and self.data)
			if Workshop.AskUpdate(name) then ns.Print(L.WORKSHOP_ASKED:format(1, Workshop.Latest())) end
		end)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function BugLines(lines)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_BUGS:format(#reports) }
	if #reports == 0 then lines[#lines + 1] = { text = Grey(L.WORKSHOP_BUGS_NONE) } end
	for i = #reports, math.max(1, #reports - Workshop.MAX_SHOWN + 1), -1 do
		local r = reports[i]
		local first = r.text:match("[^\n`]+") or ""
		lines[#lines + 1] = {
			indent = 1, text = ns.DisplayName(r.from) .. "  " .. Grey(first:sub(1, 60)),
			right = Grey(ns.Ago(r.t)),
			onClick = function() ns.UI.ShowCopy(L.WORKSHOP_BUG_FROM:format(ns.DisplayName(r.from)), r.text) end,
		}
	end
end

function Workshop.Build()
	local lines = {}
	if Workshop.Preview() then lines[#lines + 1] = { text = Grey(L.WORKSHOP_PREVIEW), gapAfter = true } end
	InstallLines(lines)
	RollLines(lines)
	BugLines(lines)
	return lines, L.TAB_WORKSHOP, L.WORKSHOP_HINT
end

-- The copyable report for Discord.
function Workshop.ReportText()
	local out = { "```", L.WORKSHOP_REPORT_TITLE:format(ns.VERSION, date and date("%Y-%m-%d %H:%M") or "") }
	for _, line in ipairs((Workshop.Build())) do
		local text = (line.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local right = (line.right or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if line.header then out[#out + 1] = "" end
		out[#out + 1] = (" "):rep(2 * (line.indent or 0)) .. text .. (right ~= "" and ("  " .. right) or "")
	end
	out[#out + 1] = "```"
	return table.concat(out, "\n")
end

function Workshop.Reports() return reports end
function Workshop.State() return roll end

-- Tests start from a clean state.
function Workshop.Reset()
	roll, authorAt, authorName, answeredRoll, sending = nil, nil, nil, nil, nil
	wipe(reports); wipe(pieces); wipe(bugsFrom); wipe(asked)
	lastRoll, lastRollAnswer, lastUpdateShown, lastBug, lastAsk = -math.huge, -math.huge, -math.huge, -math.huge, -math.huge
	changePending = false
end

---------------------------------------------------------------------------
-- The High Council (the moderators): a list of character names signed by the author on his
-- own computer (scripts/council-sign.py; Sign.lua checks it), never written in the code. His
-- character loads it from a file that exists on his machine only and publishes it; every
-- client checks the signature, keeps the newest list and passes it along now and then, so
-- nobody needs to be online and nobody can forge or change it.
--   HS1~<time>~<realm group>~<First Surname>,...~<signature>   (signed: all before the last ~)
-- On the channel it travels as HS~<the signed list> (0.9.8): Comm hands a message to its
-- handler only when "~" follows the two letters of its type, and the list starts "HS1~".
-- Departments and titles (0.9.9, Max's) come in a second signed list, so 0.9.8 clients keep
-- the name list they know; it travels as HT~<the signed list>, taken and passed along the same
-- way, and shows titles for names on the name list only (Core.lua):
--   HT1~<time>~<realm group>~<public 0|1>~<departments>~<signature>
--   <departments>: <name>^<icon>^<First Surname>=<title>,...;<name>^<icon>^...
-- A department's name may be empty (councillors outside any department: the council's own);
-- its icon is what ns.CouncilIconValue takes, or nothing. "public" says whether the army sees
-- the council in the census yet (ns.CouncilVisible).
-- A client that lacks the lists asks for them (0.9.9, a moderator's report: a councillor's
-- client that never got the list had no "My council icon", and relays alone can take hours):
--   HQ~<time of the name list it holds, or 0>~<time of the titles list it holds, or 0>
-- A client holding a newer list answers as a relay sends (HS~, then HT~), with the lists newer
-- than the asker's only. 0.9.8 clients drop HQ unread (Comm hands a type it has no handler for
-- to nobody, and logs nothing).
---------------------------------------------------------------------------

Workshop.COUNCIL_MAX = 30
Workshop.RELAY_EVERY = 1800 -- a client passes the list along about every 30 minutes...
Workshop.RELAYS = 3         -- ...and about this many clients do, whatever the army's size
local lastCouncilSent = -math.huge

-- Asking: once LIST_ASK_AFTER to LIST_ASK_AFTER + LIST_ASK_SPREAD seconds after login, then,
-- while still without the name list (or holding a list older than one heard of), again
-- LIST_ASK_AGAIN after an ask nobody answered (no list newer than ours heard since), or
-- LIST_ASK_EVERY after one somebody did; LIST_ASKS times a session at most. An answer goes to
-- the whole channel: while someone else's ask for as much (or more) is under LIST_ASK_HOLD old
-- (its answer can still be on its way), ours waits.
Workshop.LIST_ASK_AFTER, Workshop.LIST_ASK_SPREAD, Workshop.LIST_ASK_HOLD = 45, 45, 40
Workshop.LIST_ASK_AGAIN, Workshop.LIST_ASK_EVERY, Workshop.LIST_ASKS = 150, 600, 3
-- Answering, each kind of list (names, titles) on its own: after LIST_ANSWER_MIN to
-- LIST_ANSWER_MIN + LIST_ANSWER_SPREAD seconds, left out when the same list went out from
-- someone else meanwhile; once per LIST_ANSWER_GAP after we sent it, whatever the number of
-- asks. About LIST_ANSWERS clients take an ask up, whatever the army's size: one draw per
-- LIST_DRAW_GAP (an ask that soon after the one we drew for is covered by its answer), none
-- while the census counts nobody but us (right after a server restart every client would
-- count itself alone, and all of them answer), and one sender's asks count once per
-- LIST_ASK_FROM (a client asks LIST_ASK_AGAIN apart at the soonest).
-- The author's client answers sooner, always, once per AUTHOR_ANSWER_GAP.
Workshop.LIST_ANSWER_MIN, Workshop.LIST_ANSWER_SPREAD, Workshop.LIST_ANSWER_GAP = 3, 12, 120
Workshop.LIST_DRAW_GAP, Workshop.LIST_ANSWERS, Workshop.LIST_ASK_FROM = 30, 3, 120
Workshop.AUTHOR_ANSWER_MIN, Workshop.AUTHOR_ANSWER_SPREAD, Workshop.AUTHOR_ANSWER_GAP = 1, 2, 60
local LIST_STORE = { HS = "council", HT = "councilTitles" }
local advertised = { HS = 0, HT = 0 } -- the newest list times heard of this session
local listAsks, lastListAsk, askArmed = 0, -math.huge, false
local listHeardAt = -math.huge -- the last list newer than ours heard on the channel
local heardAsk        -- someone else's asks heard lately: { names, titles, t }, the lowest times
local answering       -- our answer waiting: { names, titles, heard = { HS, HT }, mine }
local answeredAt = { HS = -math.huge, HT = -math.huge } -- our last answer of each list
local drawnAt = { HS = -math.huge, HT = -math.huge }    -- our last draw for each list, won or not
local askedFrom, askedFromCount = {}, 0                 -- sender -> when its ask last counted

-- The list of a kind ("HS" names, "HT" titles) we hold, as signed, and its time (0: none).
local function HeldList(kind)
	local l = ns.rdb and ns.rdb[LIST_STORE[kind]]
	if type(l) ~= "table" then return nil, 0 end
	return type(l.blob) == "string" and l.blob or nil, tonumber(l.at) or 0
end

-- A list of that kind newer than `than`, when we hold one.
local function NewerList(kind, than)
	local blob, at = HeldList(kind)
	return blob and at > than and blob or nil
end

-- A list time heard of (someone's ask, or a relay the signature budget left unchecked).
local function Advertise(kind, at)
	if at and at > advertised[kind] then advertised[kind] = at end
end

-- A list heard on the channel from someone else: the very one our answer would send, so the
-- asker has it (the author's answer goes anyway). Only the list we hold, byte for byte: a
-- forged one with the same time never silences anyone. One newer than ours (taken or not)
-- answers our ask: the next one waits LIST_ASK_EVERY.
local function HeardList(kind, blob)
	local at = tonumber(blob:match("^" .. kind .. "1~(%d+)~"))
	local _, held = HeldList(kind)
	if at and at > held then listHeardAt = ns.Now() end
	if answering and not answering.mine and blob == (HeldList(kind)) then answering.heard[kind] = true end
end

local function AuthorLists() return ns.COUNCIL_SIGNED ~= nil or ns.COUNCIL_TITLES ~= nil end

local function SendLists(names, titles)
	if names then ns.Comm.SendChunked("HS~" .. names) end
	if titles then ns.Comm.SendChunked("HT~" .. titles) end
end

local function CouncilNames()
	local c = ns.rdb and ns.rdb.council
	local out = {}
	for _, display in pairs(type(c) == "table" and c.names or {}) do out[#out + 1] = display end
	table.sort(out)
	return out
end
Workshop.CouncilNames = CouncilNames

-- A signed list (from the author's file, or heard on the channel): checked, kept if newer.
-- A signature check is the heaviest thing the addon does (0.9.8, Konig's review): lists heard on
-- the channel are checked at most once a minute per sender and VERIFY_MAX times a minute in all,
-- and a list already found false is not checked again. The author's own file is not limited.
-- Once a minute per sender and per kind of list (0.9.9): a relay sends the names and the titles
-- one after the other, and one gap for both would leave the titles unchecked at every relay.
Workshop.VERIFY_GAP, Workshop.VERIFY_MAX = 60, 6
local verifiedFrom, verifyTimes, falseLists, falseCount = {}, {}, {}, 0
local function MayVerify(sender, kind, blob, now)
	if falseLists[blob] then return false end
	local key = sender and (sender .. "~" .. kind)
	if key and now - (verifiedFrom[key] or -math.huge) < Workshop.VERIFY_GAP then return false end
	for i = #verifyTimes, 1, -1 do if now - verifyTimes[i] >= 60 then table.remove(verifyTimes, i) end end
	if #verifyTimes >= Workshop.VERIFY_MAX then return false end
	if key then verifiedFrom[key] = now end
	verifyTimes[#verifyTimes + 1] = now
	return true
end
local function RememberFalse(blob)
	if falseCount >= 100 then wipe(falseLists); falseCount = 0 end
	falseLists[blob], falseCount = true, falseCount + 1
end
function Workshop.ResetVerify() -- tests (the list times heard of go too)
	wipe(verifiedFrom); wipe(verifyTimes); wipe(falseLists); falseCount = 0
	if Workshop.ResetListAsk then Workshop.ResetListAsk() end
end

function Workshop.TakeCouncil(blob, sender)
	if type(blob) ~= "string" or #blob > 2000 then return false end
	local text, at, realm, list, sig = blob:match("^(HS1~(%d+)~([^~]*)~([^~]*))~(%x+)$")
	at = tonumber(at)
	if not at then return false end
	-- The list we hold (or an older one) is not checked again: each relay would cost every
	-- client a signature check for nothing (0.9.8).
	local c = ns.rdb.council
	if type(c) == "table" and (tonumber(c.at) or 0) >= at then return false end
	if sender and not MayVerify(sender, "HS", blob, ns.Now()) then
		if not falseLists[blob] then Advertise("HS", at) end -- (not checked: asked for later)
		return false
	end
	if not ns.Sign or not ns.Sign.Verify(text, sig) then
		if sender then
			RememberFalse(blob)
			ns.Log("High Council: a list from %s failed its signature", tostring(sender))
		end
		return false
	end
	local names, n = {}, 0
	for name in list:gmatch("[^,]+") do
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and #name <= 48 and n < Workshop.COUNCIL_MAX then names[name:lower()], n = name, n + 1 end
	end
	ns.rdb.council = { at = at, names = names, realm = realm ~= "" and realm or nil, blob = blob }
	ns.Log("High Council: a signed list of %d names (%s)", n, tostring(at))
	ns.Fire("DATA_CHANGED")
	return true
end

function Workshop.HandleCouncil(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" then return end
	local blob = text:match("^HS~(HS1~.*)$") or text
	Workshop.TakeCouncil(blob, ns.FullName(sender))
	HeardList("HS", blob)
end
ns.Comm.Handle("HS", function(...) Workshop.HandleCouncil(...) end)

-- The departments and titles (0.9.9): what the addon keeps of them, whatever the list says. A
-- signed list never breaks these (the signing script refuses it first); past them, the rest is
-- left out: TITLES_BLOB bytes in all (or none of it), COUNCIL_MAX councillors, DEPTS_MAX named
-- departments of DEPT_NAME bytes, titles of TITLE_MAX bytes; a councillor once, the first time.
Workshop.TITLES_BLOB, Workshop.DEPTS_MAX, Workshop.DEPT_NAME, Workshop.TITLE_MAX = 3000, 8, 40, 48
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function ReadDepartments(text)
	local depts, named, count, seen = {}, 0, 0, {}
	for entry in text:gmatch("[^;]+") do
		local name, icon, list = entry:match("^([^%^]*)%^([^%^]*)%^([^%^]*)$")
		name = name and Trim(name)
		if name and #name <= Workshop.DEPT_NAME and (name == "" or named < Workshop.DEPTS_MAX) then
			if name ~= "" then named = named + 1 end
			local d = { name = name, icon = ns.CouncilIconValue(icon), members = {} }
			for m in list:gmatch("[^,]+") do
				local who, title = m:match("^([^=]*)=([^=]*)$")
				who, title = who and Trim(who), title and Trim(title)
				if who and who ~= "" and #who <= 48 and #title <= Workshop.TITLE_MAX and not seen[who:lower()]
					and count < Workshop.COUNCIL_MAX then
					seen[who:lower()], count = true, count + 1
					d.members[#d.members + 1] = { name = who, title = title ~= "" and title or nil }
				end
			end
			depts[#depts + 1] = d
		end
	end
	return depts, count
end

-- A signed titles list, from the author's file or the channel: checked and kept like the names
-- (only a newer one; the same budget of signature checks).
function Workshop.TakeTitles(blob, sender)
	if type(blob) ~= "string" or #blob > Workshop.TITLES_BLOB then return false end
	local text, at, realm, public, list, sig = blob:match("^(HT1~(%d+)~([^~]*)~([01])~([^~]*))~(%x+)$")
	at = tonumber(at)
	if not at then return false end
	local t = ns.rdb.councilTitles
	if type(t) == "table" and (tonumber(t.at) or 0) >= at then return false end
	if sender and not MayVerify(sender, "HT", blob, ns.Now()) then
		if not falseLists[blob] then Advertise("HT", at) end
		return false
	end
	if not ns.Sign or not ns.Sign.Verify(text, sig) then
		if sender then
			RememberFalse(blob)
			ns.Log("High Council: a titles list from %s failed its signature", tostring(sender))
		end
		return false
	end
	local depts, n = ReadDepartments(list)
	ns.rdb.councilTitles = { at = at, public = public == "1", realm = realm ~= "" and realm or nil, depts = depts, blob = blob }
	ns.Log("High Council: a signed titles list of %d names in %d parts (%s)", n, #depts, tostring(at))
	ns.Fire("DATA_CHANGED")
	return true
end

function Workshop.HandleTitles(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" then return end
	local blob = text:match("^HT~(HT1~.*)$") or text
	Workshop.TakeTitles(blob, ns.FullName(sender))
	HeardList("HT", blob)
end
ns.Comm.Handle("HT", function(...) Workshop.HandleTitles(...) end)

-- Passing the lists along, the names and the titles together: the author's client each 10
-- minutes; any other one now and then, so about RELAYS clients a half hour, whatever the
-- army's size.
function Workshop.RelayCouncil(force)
	local c, t = ns.rdb and ns.rdb.council, ns.rdb and ns.rdb.councilTitles
	local names = type(c) == "table" and type(c.blob) == "string" and c.blob or nil
	local titles = type(t) == "table" and type(t.blob) == "string" and t.blob or nil
	if not names and not titles then return end
	local now = ns.Now()
	local mine = AuthorLists()
	local every = mine and 600 or Workshop.RELAY_EVERY
	if not force and now - lastCouncilSent < every then return end
	lastCouncilSent = now
	if not force and not mine then
		local users = ns.King and ns.King.AddonsOnline and ns.King.AddonsOnline() or 1
		if Workshop.random() > math.min(1, Workshop.RELAYS / users) then return end
	end
	SendLists(names, titles)
end

-- Whether we should ask: no name list at all, or one older than a list heard of.
function Workshop.NeedLists()
	if type(ns.rdb and ns.rdb.council) ~= "table" then return true end
	local _, names = HeldList("HS")
	local _, titles = HeldList("HT")
	return names < advertised.HS or titles < advertised.HT
end

-- Our ask, when due (the first one waits for its time after login: askArmed). It tries again
-- LIST_ASK_AGAIN later, for an ask nobody answers (the council's ticker tries each minute).
function Workshop.AskLists()
	if not askArmed or not Workshop.NeedLists() or listAsks >= Workshop.LIST_ASKS then return false end
	local now = ns.Now()
	local wait = listHeardAt > lastListAsk and Workshop.LIST_ASK_EVERY or Workshop.LIST_ASK_AGAIN
	if now - lastListAsk < wait then return false end
	local _, names = HeldList("HS")
	local _, titles = HeldList("HT")
	local h = heardAsk
	if h and now - h.t < Workshop.LIST_ASK_HOLD and h.names <= names and h.titles <= titles then return false end
	listAsks, lastListAsk = listAsks + 1, now
	ns.Comm.Send("CHANNEL", ("HQ~%s~%s"):format(names, titles), "councillists")
	if listAsks < Workshop.LIST_ASKS then
		Workshop.after(Workshop.LIST_ASK_AGAIN, "council lists", function() Workshop.AskLists() end)
	end
	return true
end

-- Someone's ask: taken up when we hold a newer list and it is our turn (see LIST_ANSWER_*).
-- An answer already waiting covers the asks that come meanwhile. Each list is drawn for and
-- sent on a clock of its own: an ask for the titles alone never holds the names back, and a
-- draw lost (or an answer left out) holds a client back LIST_DRAW_GAP only.
function Workshop.AnswerAsk(names, titles)
	if answering then
		answering.names, answering.titles = math.min(answering.names, names), math.min(answering.titles, titles)
		return false
	end
	local now, mine = ns.Now(), AuthorLists()
	local gap = mine and Workshop.AUTHOR_ANSWER_GAP or Workshop.LIST_ANSWER_GAP
	local kinds = {}
	for kind, than in pairs({ HS = names, HT = titles }) do
		if NewerList(kind, than) and now - answeredAt[kind] >= gap
			and (mine or now - drawnAt[kind] >= Workshop.LIST_DRAW_GAP) then
			kinds[#kinds + 1] = kind
		end
	end
	if #kinds == 0 then return false end
	if not mine then
		-- A census that counts nobody but us is not in yet (whoever asked is online too).
		local users = ns.King and ns.King.AddonsOnline and ns.King.AddonsOnline() or 1
		if users <= 1 then return false end
		for _, kind in ipairs(kinds) do drawnAt[kind] = now end
		if Workshop.random() > math.min(1, Workshop.LIST_ANSWERS / users) then return false end
	end
	local pending = { names = names, titles = titles, heard = {}, mine = mine }
	answering = pending
	local wait = mine and Workshop.AUTHOR_ANSWER_MIN + Workshop.random() * Workshop.AUTHOR_ANSWER_SPREAD
		or Workshop.LIST_ANSWER_MIN + Workshop.random() * Workshop.LIST_ANSWER_SPREAD
	Workshop.after(wait, "council answer", function()
		if answering ~= pending then return end
		answering = nil
		local at, send = ns.Now(), {}
		for kind, than in pairs({ HS = pending.names, HT = pending.titles }) do
			if not pending.heard[kind] and at - answeredAt[kind] >= gap then send[kind] = NewerList(kind, than) end
		end
		if send.HS then answeredAt.HS = at end
		if send.HT then answeredAt.HT = at end
		SendLists(send.HS, send.HT)
	end)
	return true
end

function Workshop.HandleListAsk(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > 40 then return end
	sender = ns.FullName(sender)
	if type(sender) ~= "string" or sender == ns.me then return end
	local names, titles = text:match("^HQ~(%d+)~(%d+)$")
	names, titles = tonumber(names), tonumber(titles)
	if not names or not titles then return end
	-- One sender's asks count once per LIST_ASK_FROM: a character sending asks without end
	-- brings no more draws than that (a client of ours asks LIST_ASK_AGAIN apart at the soonest).
	local now = ns.Now()
	if now - (askedFrom[sender] or -math.huge) < Workshop.LIST_ASK_FROM then return end
	if not askedFrom[sender] then
		if askedFromCount >= 200 then -- (the table stays small: the old ones go first)
			for name, t in pairs(askedFrom) do
				if now - t >= Workshop.LIST_ASK_FROM then askedFrom[name], askedFromCount = nil, askedFromCount - 1 end
			end
			if askedFromCount >= 200 then wipe(askedFrom); askedFromCount = 0 end
		end
		askedFromCount = askedFromCount + 1
	end
	askedFrom[sender] = now
	Advertise("HS", names)
	Advertise("HT", titles)
	local h = heardAsk
	if h and now - h.t < Workshop.LIST_ASK_HOLD then
		h.names, h.titles = math.min(h.names, names), math.min(h.titles, titles)
	else
		heardAsk = { names = names, titles = titles, t = now }
	end
	Workshop.AnswerAsk(names, titles)
end
ns.Comm.Handle("HQ", function(...) Workshop.HandleListAsk(...) end)

-- Tests start from a clean state.
function Workshop.ResetListAsk()
	advertised.HS, advertised.HT = 0, 0
	listAsks, lastListAsk, askArmed, heardAsk, listHeardAt = 0, -math.huge, false, nil, -math.huge
	answering = nil
	answeredAt.HS, answeredAt.HT, drawnAt.HS, drawnAt.HT = -math.huge, -math.huge, -math.huge, -math.huge
	wipe(askedFrom); askedFromCount = 0
end

function Workshop.EditCouncil(verb)
	local names = CouncilNames()
	ns.Print(L.COUNCIL_LIST:format(#names > 0 and table.concat(names, ", ") or "-"))
end

-- The council as the census shows it (0.9.9, Views.lua): the councillors outside any department
-- first (the titles list's own, then anyone on the name list it leaves out, by name), then each
-- department in the list's order with its councillors in theirs. Names on the name list only;
-- a department left with nobody is left out.
--   loose = { { name, title }, ... }, depts = { { name, icon, members = { { name, title }, ... } }, ... }
function Workshop.CouncilTree()
	local loose, depts, placed = {}, {}, {}
	local t = ns.CouncilTitles()
	for _, d in ipairs(t and t.depts or {}) do
		local own = type(d) == "table" and d.name == ""
		local into = own and loose or {}
		for _, m in ipairs(type(d) == "table" and type(d.members) == "table" and d.members or {}) do
			local key = type(m) == "table" and type(m.name) == "string" and m.name:lower()
			if key and not placed[key] and ns.IsHighCouncillor(m.name) then
				placed[key] = true
				into[#into + 1] = { name = m.name, title = type(m.title) == "string" and m.title ~= "" and m.title or nil }
			end
		end
		if not own and #into > 0 and type(d.name) == "string" then
			depts[#depts + 1] = { name = d.name, icon = ns.CouncilIconValue(d.icon), members = into }
		end
	end
	for _, name in ipairs(CouncilNames()) do
		if not placed[name:lower()] and ns.IsHighCouncillor(name) then loose[#loose + 1] = { name = name } end
	end
	return loose, depts
end

-- Asking a High Councillor for help (Max's): the councillors who opted in (/oly council help on)
-- say so on the channel every few minutes; a player's request goes by whisper to up to three
-- of them online, once every five minutes at most.
Workshop.HELP_EVERY, Workshop.HELP_FRESH, Workshop.HELP_GAP = 300, 700, 300
local available, lastHelpSent, lastAvailSent, helpFrom = {}, -math.huge, -math.huge, {}
local asking -- our request waiting for a councillor's "got it": { t, acked }
Workshop.ACK_WAIT = 10
function Workshop.SetCouncilHelp(on)
	if not ns.IsHighCouncillor(ns.me) then return ns.Print(L.COUNCIL_HELP_ONLY) end
	ns.db.councilHelp = on and true or false
	ns.Print(on and L.COUNCIL_HELP_ON or L.COUNCIL_HELP_OFF)
	lastAvailSent = -math.huge
	-- Off: said at once, so nobody's request goes to us meanwhile.
	if not on then ns.Comm.Send("CHANNEL", "HA~0", "counciladvert") end
	Workshop.SayAvailable()
end
function Workshop.SayAvailable()
	if not ns.db.councilHelp or not ns.IsHighCouncillor(ns.me) then return end
	local now = ns.Now()
	if now - lastAvailSent < Workshop.HELP_EVERY then return end
	lastAvailSent = now
	ns.Comm.Send("CHANNEL", "HA~1", "counciladvert")
end
function Workshop.HandleAvailable(dist, sender, text)
	if dist ~= "CHANNEL" or not ns.IsHighCouncillor(sender) then return end
	available[ns.FullName(sender)] = (text ~= "HA~0") and ns.Now() or nil
end
function Workshop.Available()
	local out, now = {}, ns.Now()
	for name, t in pairs(available) do if now - t <= Workshop.HELP_FRESH then out[#out + 1] = name end end
	table.sort(out)
	return out
end
function Workshop.AskCouncil(text)
	text = ns.Cut(ns.Codec.Plain(tostring(text or "")), 180) -- (never half a letter, 0.9.8)
	local now = ns.Now()
	if now - lastHelpSent < Workshop.HELP_GAP then return ns.Print(L.COUNCIL_ASK_WAIT) end
	local list = Workshop.Available()
	if #list == 0 then return ns.Print(L.COUNCIL_ASK_NOBODY) end
	lastHelpSent = now
	for i = 1, math.min(3, #list) do
		local k = Workshop.random(1, #list)
		ns.Comm.Whisper(list[k], "HR~" .. text, "councilask" .. i)
		table.remove(list, k)
	end
	-- Sent is not received (a councillor may have just logged off): told only when one of them
	-- says "got it"; none within ACK_WAIT, the player is told and may ask again at once.
	local mine = { t = now }
	asking = mine
	ns.After(Workshop.ACK_WAIT, "council ask", function()
		if asking ~= mine or mine.acked then return end
		asking, lastHelpSent = nil, -math.huge
		ns.Print(L.COUNCIL_ASK_NOBODY)
	end)
end
function Workshop.HandleCouncilAck(dist, sender)
	if dist ~= "WHISPER" or not asking or asking.acked or not ns.IsHighCouncillor(sender) then return end
	asking.acked = true
	ns.Print(L.COUNCIL_ASK_SENT)
end
function Workshop.HandleAsk(dist, sender, text)
	if dist ~= "WHISPER" or not ns.db.councilHelp or not ns.IsHighCouncillor(ns.me) then return end
	local now, who = ns.Now(), ns.FullName(sender)
	if now - (helpFrom[who] or -math.huge) < 60 then return end
	helpFrom[who] = now
	ns.Comm.Whisper(who, "HK~1", "councilack")
	local msg = ns.Codec.Plain(text:match("^HR~(.*)$") or "")
	ns.Print(L.COUNCIL_ASKED:format("|Hplayer:" .. ns.TellName(who) .. "|h[" .. ns.DisplayName(who) .. "]|h", msg))
	ns.PlayAlert("soft")
end
ns.Comm.Handle("HA", function(...) Workshop.HandleAvailable(...) end)
ns.Comm.Handle("HR", function(...) Workshop.HandleAsk(...) end)
ns.Comm.Handle("HK", function(...) Workshop.HandleCouncilAck(...) end)
function Workshop.ResetHelp() wipe(available); wipe(helpFrom); asking, lastHelpSent, lastAvailSent = nil, -math.huge, -math.huge end -- tests

StaticPopupDialogs["OLYMPUS_COUNCIL_ASK"] = {
	text = L.COUNCIL_ASK_PROMPT,
	button1 = L.COUNCIL_ASK_SEND,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 180,
	editBoxWidth = 260, -- (a sentence, not a name)
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("council ask", Workshop.AskCouncil, eb and eb:GetText() or "")
	end,
	-- Enter sends and Escape closes, as in our other boxes (0.9.8: Enter did nothing).
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("council ask", Workshop.AskCouncil, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The councillors' own icons (0.9.8, the High Council's wish): each councillor picks an icon
-- for their name in the Olympus chats from the game's icons, as the macro window does (in a
-- window of ours: Blizzard's macro icon window, opened from addon code, would run tainted). Their
-- client says which on the channel when it changes, then about every ICON_EVERY. Every client
-- keeps it for councillors only (ns.IsHighCouncillor of the sender the server stamped), and only
-- a file number or a plain icon name under Interface\Icons (ns.CouncilIconValue): nothing else
-- can reach the chat line. Since 0.9.9 it is optional flavour after the council's fixed mark
-- (Core.lua); none heard yet: the mark alone.
--   HI~<file number or icon name>   |   HI~0   (no icon: the mark alone)
---------------------------------------------------------------------------

Workshop.ICON_EVERY = 1200 -- about every 20 minutes (the council ticker runs once a minute)
Workshop.ICON_COLS, Workshop.ICON_ROWS = 8, 5
local ICON_CELL, ICON_GAP = 36, 4
local lastIconSent = -math.huge
local picker          -- the picker window, built the first time it opens
local gameIcons       -- the game's icons while it is open (let go when it closes, like Blizzard's)
local shownIcons      -- the ones the filter leaves
local iconPage, iconChoice = 1, nil

-- Our own icon (per character, like the council's names), or nil for none. False is "none"
-- chosen on purpose: it is still said ("0"), so the old one fades everywhere.
local function MyIcon()
	local mine = ns.db and ns.db.councilIcons
	return ns.CouncilIconValue(type(mine) == "table" and ns.me and mine[ns.me] or nil)
end
Workshop.MyIcon = MyIcon

-- Our icon on the channel: at once when forced (a change), else every ICON_EVERY. Only a
-- councillor's client says it, and only once they picked one (or none, on purpose).
function Workshop.SayIcon(force)
	if not ns.IsHighCouncillor(ns.me) then return false end
	local mine = ns.db and ns.db.councilIcons
	if not force and (type(mine) ~= "table" or mine[ns.me] == nil) then return false end
	local now = ns.Now()
	if not force and now - lastIconSent < Workshop.ICON_EVERY then return false end
	lastIconSent = now
	ns.Comm.Send("CHANNEL", "HI~" .. tostring(MyIcon() or 0), "councilicon")
	return true
end

-- A councillor's choice (the picker's OK): kept on this character and said at once; nil takes
-- the icon away (the mark stays).
function Workshop.SetCouncilIcon(v)
	if not ns.IsHighCouncillor(ns.me) then
		ns.Print(L.COUNCIL_ICON_ONLY)
		return false
	end
	local icon = ns.CouncilIconValue(v)
	if v ~= nil and not icon then return false end
	if type(ns.db.councilIcons) ~= "table" then ns.db.councilIcons = {} end
	ns.db.councilIcons[ns.me] = icon or false
	Workshop.SayIcon(true)
	ns.Print(icon and L.COUNCIL_ICON_SET:format("|T" .. ns.CouncilIconTexture(icon) .. ":0|t") or L.COUNCIL_ICON_RESET)
	return true
end

-- The icons heard, per realm group like the council's list (kept in the SavedVariables, so a
-- /reload shows them at once): councillor (Name-Realm) -> { icon, t }.
local function HeardIcons()
	if type(ns.rdb.councilIcons) ~= "table" then ns.rdb.councilIcons = {} end
	return ns.rdb.councilIcons
end

-- Councillors no longer on the list, and anything that is not an icon, go; past COUNCIL_MAX,
-- the ones heard longest ago.
local function PruneIcons(store)
	local n = 0
	for who, e in pairs(store) do
		if type(who) ~= "string" or type(e) ~= "table" or not ns.CouncilIconValue(e.icon) or not ns.IsHighCouncillor(who) then
			store[who] = nil
		else
			n = n + 1
		end
	end
	while n > Workshop.COUNCIL_MAX do
		local oldest, at = nil, math.huge
		for who, e in pairs(store) do
			local t = tonumber(e.t) or 0
			if t < at then oldest, at = who, t end
		end
		if not oldest then break end
		store[oldest], n = nil, n - 1
	end
end

function Workshop.HandleIcon(dist, sender, text)
	if dist ~= "CHANNEL" or not ns.IsHighCouncillor(sender) or type(text) ~= "string" then return end
	local v = text:match("^HI~([%w_]+)$")
	if not v then return end
	local store, who = HeardIcons(), ns.FullName(sender)
	if v == "0" then
		store[who] = nil
		return
	end
	local icon = ns.CouncilIconValue(v)
	if not icon then return end
	store[who] = { icon = icon, t = ns.Now() }
	PruneIcons(store)
end
ns.Comm.Handle("HI", function(...) Workshop.HandleIcon(...) end)

-- The game's icons, as the macro window lists them (Blizzard's IconDataProvider.lua): its loose
-- icons, then the spells' and the items' (file numbers or names: Blizzard's code takes either).
-- Each is a client function that fills a table; one a client lacks, or that fails, is skipped.
-- Repeats, and anything ns.CouncilIconValue refuses, are left out. Also: whether any is a name
-- (only names can be filtered; file numbers say nothing).
local ICON_LISTS = { "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }
function Workshop.GameIcons()
	local out, seen, names = {}, {}, false
	for _, api in ipairs(ICON_LISTS) do
		local fill = _G[api]
		local list = {}
		if type(fill) == "function" and pcall(fill, list) then
			for _, v in ipairs(list) do
				local icon = ns.CouncilIconValue(v)
				local key = icon and tostring(icon):lower()
				if key and not seen[key] then
					seen[key] = true
					out[#out + 1] = icon
					if type(icon) == "string" then names = true end
				end
			end
		end
	end
	return out, names
end

local function IconLabel(icon)
	return type(icon) == "number" and ("#" .. icon) or tostring(icon)
end

function Workshop.RefreshIconPicker()
	if not picker then return end
	local per = Workshop.ICON_COLS * Workshop.ICON_ROWS
	local list = shownIcons or {}
	local pages = math.max(1, math.ceil(#list / per))
	iconPage = math.max(1, math.min(iconPage, pages))
	for i, b in ipairs(picker.cells) do
		local icon = list[(iconPage - 1) * per + i]
		b.icon = icon
		if icon then
			b.art:SetTexture(ns.CouncilIconTexture(icon))
			b.chosen:SetShown(icon == iconChoice)
			b:Show()
		else
			b:Hide()
		end
	end
	picker.page:SetText(L.COUNCIL_ICON_PAGE:format(iconPage, pages))
	picker.prev:SetEnabled(iconPage > 1)
	picker.next:SetEnabled(iconPage < pages)
	picker.empty:SetShown(#list == 0)
	-- The preview: the icon large (the mark when none is picked), and our name as the chats will
	-- show it: the mark always, the icon after it (0.9.9).
	local texture = ns.CouncilIconTexture(iconChoice)
	picker.preview:SetTexture(texture or ns.HIGH_COUNCIL_SKULL)
	picker.sample:SetText("[" .. L.CHAN_ALL .. "] [" .. ns.HIGH_COUNCIL_MARK .. (texture and ("|T" .. texture .. ":0|t") or "")
		.. "|c" .. ns.HIGH_COUNCIL_COLOR .. (ns.DisplayName(ns.me) or "?") .. "|r]")
	picker.chosenName:SetText(iconChoice and IconLabel(iconChoice) or L.COUNCIL_ICON_MARK_ONLY)
end

-- A click on an icon (or No icon, nil): the preview only, until OK.
function Workshop.PickIcon(icon)
	iconChoice = ns.CouncilIconValue(icon)
	Workshop.RefreshIconPicker()
end

function Workshop.IconPage(n)
	iconPage = tonumber(n) or 1
	Workshop.RefreshIconPicker()
end

-- The filter: the names (and file numbers) that hold the text, any case.
function Workshop.FilterIcons(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		shownIcons = gameIcons
	else
		shownIcons = {}
		for _, icon in ipairs(gameIcons or {}) do
			if tostring(icon):lower():find(text, 1, true) then shownIcons[#shownIcons + 1] = icon end
		end
	end
	iconPage = 1
	Workshop.RefreshIconPicker()
end

local function PickerButton(f, label, width)
	local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	return b
end

-- Our own window on UIParent: movable, closed by its X (and by Escape with mouse and keyboard,
-- ns.EscapeCloses), no Blizzard frame touched. Its filter box never takes the keyboard by
-- itself: the player clicks into it (the gamepad UI's rule, ns.Focus).
local function MakePicker()
	local cols, rows = Workshop.ICON_COLS, Workshop.ICON_ROWS
	local gridW = cols * ICON_CELL + (cols - 1) * ICON_GAP
	local gridTop = -150
	local gridBottom = gridTop - (rows * ICON_CELL + (rows - 1) * ICON_GAP)
	local f = CreateFrame("Frame", "OlympusCouncilIconFrame", UIParent)
	f:SetSize(gridW + 56, -gridBottom + 96)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	local okBorder, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if not okBorder or not border then
		border = f:CreateTexture(nil, "BACKGROUND")
		border:SetColorTexture(0, 0, 0, 0.85)
	end
	border:SetAllPoints()
	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("TOP", 0, -18)
	f.title:SetText(L.COUNCIL_ICON_TITLE)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	-- The preview, and the hint.
	f.preview = f:CreateTexture(nil, "ARTWORK")
	f.preview:SetSize(40, 40)
	f.preview:SetPoint("TOPLEFT", 28, -40)
	f.sample = f:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
	f.sample:SetPoint("TOPLEFT", f.preview, "TOPRIGHT", 10, -3)
	f.sample:SetWidth(gridW - 50)
	f.sample:SetJustifyH("LEFT")
	f.sample:SetWordWrap(false)
	f.chosenName = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.chosenName:SetPoint("TOPLEFT", f.sample, "BOTTOMLEFT", 0, -6)
	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.hint:SetPoint("TOPLEFT", 28, -88)
	f.hint:SetWidth(gridW)
	f.hint:SetJustifyH("LEFT")
	f.hint:SetText(L.COUNCIL_ICON_HINT)
	-- The filter (only when the game lists names).
	f.filterLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.filterLabel:SetPoint("TOPLEFT", 28, -124)
	f.filterLabel:SetText(L.COUNCIL_ICON_FILTER)
	local okBox, eb = pcall(CreateFrame, "EditBox", "OlympusCouncilIconFilter", f, "InputBoxTemplate")
	if not okBox or not eb then eb = CreateFrame("EditBox", nil, f) end
	eb:SetSize(160, 20)
	eb:SetPoint("LEFT", f.filterLabel, "RIGHT", 12, 0)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(40)
	eb:SetFontObject("ChatFontNormal")
	eb.olympusBox = true
	eb:SetScript("OnTextChanged", function(self) ns.SafeCall("council icon filter", Workshop.FilterIcons, self:GetText()) end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.filter = eb
	-- The grid, a page at a time (the mouse wheel turns them too).
	f.cells = {}
	for i = 1, cols * rows do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(ICON_CELL, ICON_CELL)
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		b:SetPoint("TOPLEFT", 28 + col * (ICON_CELL + ICON_GAP), gridTop - row * (ICON_CELL + ICON_GAP))
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b.chosen = b:CreateTexture(nil, "OVERLAY")
		b.chosen:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		b.chosen:SetBlendMode("ADD")
		b.chosen:SetAllPoints()
		b.chosen:Hide()
		b:SetScript("OnClick", function(self) ns.SafeCall("council icon pick", Workshop.PickIcon, self.icon) end)
		b:SetScript("OnEnter", function(self)
			if not self.icon or not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(IconLabel(self.icon), 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		f.cells[i] = b
	end
	f.empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	f.empty:SetPoint("TOP", 0, gridTop - 20)
	f.empty:SetText(L.COUNCIL_ICON_NONE)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) ns.SafeCall("council icon page", Workshop.IconPage, iconPage - delta) end)
	f.prev = PickerButton(f, "<", 32)
	f.prev:SetPoint("TOPLEFT", 28, gridBottom - 8)
	f.prev:SetScript("OnClick", function() ns.SafeCall("council icon page", Workshop.IconPage, iconPage - 1) end)
	f.next = PickerButton(f, ">", 32)
	f.next:SetPoint("TOPRIGHT", -28, gridBottom - 8)
	f.next:SetScript("OnClick", function() ns.SafeCall("council icon page", Workshop.IconPage, iconPage + 1) end)
	f.page = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.page:SetPoint("TOP", 0, gridBottom - 13)
	-- No icon (the mark alone), Cancel and OK. OK with nothing changed only closes.
	f.default = PickerButton(f, L.COUNCIL_ICON_DEFAULT, 120)
	f.default:SetPoint("BOTTOMLEFT", 24, 18)
	f.default:SetScript("OnClick", function() ns.SafeCall("council icon pick", Workshop.PickIcon, nil) end)
	f.ok = PickerButton(f, OKAY or "OK", 90)
	f.ok:SetPoint("BOTTOMRIGHT", -24, 18)
	f.ok:SetScript("OnClick", function()
		ns.SafeCall("council icon ok", function()
			if iconChoice == MyIcon() or Workshop.SetCouncilIcon(iconChoice) then f:Hide() end
		end)
	end)
	f.cancel = PickerButton(f, CANCEL or "Cancel", 90)
	f.cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
	f.cancel:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnHide", function(self)
		if self:IsShown() then return end -- the whole interface hidden (Alt+Z): still open
		self.filter:ClearFocus()
		gameIcons, shownIcons = nil, nil
	end)
	return f
end

-- /oly council icon, and the Realm tab's button: a councillor's alone.
function Workshop.ShowIconPicker()
	if not ns.IsHighCouncillor(ns.me) then
		ns.Print(L.COUNCIL_ICON_ONLY)
		return false
	end
	picker = picker or MakePicker()
	local names
	gameIcons, names = Workshop.GameIcons()
	shownIcons, iconChoice = gameIcons, MyIcon()
	picker.filter:SetText("")
	picker.filter:SetShown(names)
	picker.filterLabel:SetShown(names)
	-- It opens at the page of the icon in use.
	iconPage = 1
	for i, icon in ipairs(gameIcons) do
		if icon == iconChoice then
			iconPage = math.floor((i - 1) / (Workshop.ICON_COLS * Workshop.ICON_ROWS)) + 1
			break
		end
	end
	Workshop.RefreshIconPicker()
	picker:Show()
	ns.EscapeCloses("OlympusCouncilIconFrame")
	return true
end

function Workshop.IconPicker() return picker end

-- Tests start from a clean state.
function Workshop.ResetIcons()
	if picker then picker:Hide() end
	picker, gameIcons, shownIcons, iconPage, iconChoice = nil, nil, nil, 1, nil
	lastIconSent = -math.huge
end

-- At login. The author's machine holds the signed lists (CouncilList.lua, never published: the
-- names, and the titles since 0.9.9): his client takes them and sends the newest it holds at
-- once. Any other client passes the lists along a whole RELAY_EVERY after login at the earliest
-- (0.9.8): until the census says how many addons are online, each would count itself alone and
-- relay for sure, the whole army at once after a server restart. A client without the lists
-- asks for them (0.9.9): first LIST_ASK_AFTER to LIST_ASK_AFTER + LIST_ASK_SPREAD after login,
-- then when due (Workshop.AskLists), the council's ticker trying too.
function Workshop.CouncilLogin()
	lastCouncilSent = ns.Now()
	if ns.COUNCIL_SIGNED then Workshop.TakeCouncil(ns.COUNCIL_SIGNED) end
	if ns.COUNCIL_TITLES then Workshop.TakeTitles(ns.COUNCIL_TITLES) end
	if ns.COUNCIL_SIGNED or ns.COUNCIL_TITLES then
		ns.After(15, "council", function() Workshop.RelayCouncil(true) end)
	end
	ns.After(Workshop.LIST_ASK_AFTER + Workshop.random() * Workshop.LIST_ASK_SPREAD, "council lists", function()
		askArmed = true
		Workshop.AskLists()
	end)
	ns.Every(60, "council", function()
		Workshop.RelayCouncil()
		Workshop.AskLists()
		Workshop.SayAvailable()
		Workshop.SayIcon()
	end)
end
ns.On("LOGIN", function() Workshop.CouncilLogin() end)

ns.Comm.Handle("V1", function(...) Workshop.HandleRoll(...) end)
ns.Comm.Handle("V2", function(...) Workshop.HandleAnswer(...) end)
ns.Comm.Handle("V3", function(...) Workshop.HandleUpdate(...) end)
ns.Comm.Handle("V4", function(...) Workshop.HandlePresence(...) end)
ns.Comm.Handle("V5", function(...) Workshop.HandleBug(...) end)
ns.Comm.Handle("V6", function(...) Workshop.HandleAck(...) end)

ns.On("LOGIN", function()
	-- The author says he is online once on the channel, then every PRESENCE_EVERY.
	ns.After(40, "author presence", Workshop.SendPresence)
	ns.Every(Workshop.PRESENCE_EVERY, "author presence", Workshop.SendPresence)
end)
