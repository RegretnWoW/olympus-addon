-- Most Wanted sightings: what a member's client saw, on its own map and whispered to the
-- reviewers who take them. A small world of clients in one Lua state, each with its own namespace,
-- saved data, units, map spot, layer, recording pin library and Wanted.lua; a Comm that queues as
-- the game's does (each send's permit or guard checked again when its turn comes; a whisper to the
-- client it names, or the server's "No player named" to its sender when that one is offline; the
-- channel to every other online client; each stamped with its sender's name), and timers on the
-- world's clock. A client may run the real Comm.lua, Consent.lua or Backup.lua instead (realComm,
-- realConsent, realBackup): their own queue, page and restore with Wanted.lua. The names are made up.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]wanted%-sightings%.lua$")) or "./"
local L = ns.L

local DIALOGS = { "OLYMPUS_WANTED_ADD", "OLYMPUS_WANTED_REMOVE", "OLYMPUS_WANTED_SEND", "OLYMPUS_WANTED_REVIEW",
	"OLYMPUS_WANTED_WITHDRAW", "OLYMPUS_WANTED_PUBLISH", "OLYMPUS_WANTED_REVOKE", "OLYMPUS_WANTED_CORRECT", "OLYMPUS_BACKUP_RESTORE" }
local GLOBALS = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "UnitCanAttack", "UnitIsPVP", "GetGuildInfo", "IsInInstance",
	"C_Map", "CreateFrame", "UIParent", "GameTooltip", "C_InputInterfaceStyle", "issecretvalue", "GetRealZoneText",
	"UnitIsDeadOrGhost", "C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "GetFileIDFromPath", "C_ChatInfo", "ChatFrameUtil",
	"ChatFrame_AddMessageEventFilter", "GetTime", "InCombatLockdown" }
local NOT_FOUND = "No player named '%s' is currently playing."
-- What the game hands an addon where a value is secret (issecretvalue says so).
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local GROM, THRALL, REXXAR, GARROSH = "Player-1-0A000001", "Player-1-0A000002", "Player-1-0A000003", "Player-1-0A000004"
-- On every client's Wanted list (world:Client, unless o.wanted == false): only the wanted are sighted.
local WANTED = { { "Grom-Realm", GROM }, { "Thrall-Realm", THRALL }, { "Rexxar-Realm", REXXAR }, { "Garrosh-Realm", GARROSH },
	{ "Stale-Realm", "Player-1-0A000019" } }

-- A Horde player as this client's unit functions see him: hostile and flagged for PvP unless told.
local function Horde(name, guid, o)
	o = o or {}
	return { name = name, guid = guid, faction = o.faction or "Horde", hostile = o.hostile ~= false, pvp = o.pvp ~= false,
		guild = o.guild, player = o.player }
end

-- A frame as Wanted.lua uses one: its scripts kept, shown or not, any other call a no-op.
local function Frame(kind)
	local f = { kind = kind, scripts = {}, shown = false }
	function f:SetScript(event, fn) self.scripts[event] = fn end
	function f:GetScript(event) return self.scripts[event] end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:CreateFontString() return Frame("fontstring") end -- (the privacy page's, Consent.lua)
	function f:CreateTexture()
		local t = {}
		function t:SetTexture(path) self.texture = path end
		return setmetatable(t, { __index = function() return function() end end })
	end
	return setmetatable(f, { __index = function() return function() end end })
end

local function Tooltip()
	local tt = { lines = {} }
	function tt:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
	function tt:SetOwner() end
	function tt:Show() end
	function tt:Hide() end
	return tt
end

-- HereBeDragons-Pins as Wanted.lua calls it, each call written down (sorted: the order a table's
-- pairs come in is not the code's).
local function PinLib(cl)
	local lib = { log = {} }
	local function Note(text) lib.log[#lib.log + 1] = text end
	local function Ref(ref) assert(ref == cl.W, "the icons are Wanted's own") end
	local function At(mapID, x, y) return ("%d %.3f %.3f"):format(mapID, x, y) end
	function lib:AddWorldMapIconMap(ref, _, mapID, x, y) Ref(ref) Note("world+ " .. At(mapID, x, y)) return true end
	function lib:RemoveWorldMapIcon(ref) Ref(ref) Note("world-") end
	function lib:RemoveAllWorldMapIcons(ref) Ref(ref) Note("worldAll") end
	function lib:AddMinimapIconMap(ref, _, mapID, x, y, parent, edge)
		Ref(ref)
		assert(parent == false and edge == false, "a sighting floats on no edge, nor shows on the zone above")
		Note("mini+ " .. At(mapID, x, y))
		return true
	end
	function lib:RemoveMinimapIcon(ref) Ref(ref) Note("mini-") end
	function lib:Take()
		local out = self.log
		self.log = {}
		table.sort(out)
		return table.concat(out, ", ")
	end
	return lib
end

local function WithSightings(fn)
	local saved = {}
	for _, name in ipairs(GLOBALS) do saved[name] = rawget(_G, name) end
	local savedInput = Enum.InputDeviceInterfaceType
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end
	local mapInfo = C_Map.GetMapInfo
	local world = { epoch = 1800000000, clients = {}, queue = {}, delivered = {}, dropped = {}, timers = {},
		authorities = {}, olympians = {}, hidden = {}, gamepad = false, wire = {}, positions = 0, mapInfos = 0 }
	local current
	local ok, err = pcall(function()
		local function U(unit) return current and current.units[unit] end
		UnitGUID = function(unit) return U(unit) and U(unit).guid end
		UnitIsPlayer = function(unit) local u = U(unit) return u ~= nil and u.player ~= false end
		UnitFactionGroup = function(unit) return U(unit) and U(unit).faction end
		UnitCanAttack = function(_, unit) local u = U(unit) return u ~= nil and u.hostile == true end
		UnitIsPVP = function(unit) local u = U(unit) return u ~= nil and u.pvp == true end
		GetGuildInfo = function(unit) local u = U(unit or "player") return u and u.guild end
		IsInInstance = function()
			local inside = current ~= nil and current.instance == true
			return inside, inside and "pvp" or "none"
		end
		GetRealZoneText = function() return "Elwynn Forest" end
		UnitIsDeadOrGhost = function() return false end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = 2026, month = 10 } end }
		C_DeathInfo, C_DeathRecap = nil, nil
		GetFileIDFromPath = function() return nil end
		issecretvalue = function(v) return v == SECRET end
		-- (Each map lookup and position counted: what a repeat or a full intake must not ask for.)
		C_Map = {
			GetMapInfo = function(...) world.mapInfos = world.mapInfos + 1 return mapInfo(...) end,
			GetBestMapForUnit = function(unit) return unit == "player" and current and current.map or nil end,
			GetPlayerMapPosition = function(mapID, unit)
				world.positions = world.positions + 1
				if unit ~= "player" or not current or current.map ~= mapID or not current.x then return nil end
				local x, y = current.x, current.y
				return { GetXY = function() return x, y end }
			end,
		}
		CreateFrame = function(kind) return Frame(kind) end
		UIParent = Frame("UIParent")
		Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
		C_InputInterfaceStyle = { GetCurrentStyle = function() return world.gamepad and 1 or 0 end }
		GameTooltip = Tooltip()
		-- The chat frames' filters (Forever's ChatFrameUtil), each client's own; the deprecated name absent.
		ChatFrameUtil = { AddMessageEventFilter = function(event, fn)
			assert(current, "a filter is added by a client")
			current.filters[event] = fn
		end }
		ChatFrame_AddMessageEventFilter = nil
		GetTime = function() return world.epoch end
		InCombatLockdown = function() return false end
		-- The game's send API, for a client running the real Comm.lua: what it puts on the wire.
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		function C_ChatInfo.SendAddonMessage(_, msg, dist, target)
			world.wire[#world.wire + 1] = { from = current, msg = msg, dist = dist, target = target }
			return true
		end
		C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage
		local function Fold(name) return ns.Fold(ns.FullName(name)) end
		world.Fold = Fold

		function world:As(cl, f, ...)
			local was = current
			current = cl
			local res = { pcall(f, ...) }
			current = was
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2)
		end
		function world:Load(cl)
			local c = setmetatable({ L = ns.L, db = cl.db, rdb = cl.rdb, realm = "Realm", group = "RealmGroup",
				faction = "Alliance" }, { __index = function(_, key) if key ~= "me" then return ns[key] end end })
			c.Now = function() return world.epoch end
			c.Data = { ServerTime = function() return world.epoch end }
			c.IsMember = function() return cl.member end
			c.Moderation = { CanIssue = function() return cl.manager == true end, SelfOff = function() return cl.netoff end,
				Hides = function(sender) return world.hidden[Fold(sender)] end, Blocks = function() return false end }
			local function Role(name) return world.authorities[Fold(name)] end
			c.Workshop = { IsAuthor = function() return false end, IsAuthorName = function(name) return Role(name) == "author" end }
			c.IsKingCharacter = function(name) return Role(name) == "king" end
			c.IsHighCouncillor = function(name) return Role(name) == "council" end
			-- King.lua as Wanted.lua asks it: this character is the King, and his crown shows (cl.crown).
			c.King = { IsKing = function() return cl.member and Role(cl.name) == "king" end, SharingLocation = function() return cl.crown == true end }
			local function Queue(m) world.queue[#world.queue + 1] = m return true end
			if not cl.realComm then c.Comm = {
				Handle = function(kind, call) cl.handlers[kind] = call end,
				Whisper = function(target, msg, _, _, _, done, options)
					return Queue({ from = cl, dist = "WHISPER", to = target, msg = msg, done = done, options = options })
				end,
				Send = function(dist, msg, _, _, _, done, options)
					return Queue({ from = cl, dist = dist, msg = msg, done = done, options = options })
				end,
				SendChunked = function(msg) return Queue({ from = cl, dist = "CHANNEL", msg = msg }) end,
				CancelQueued = function(owner, key, why)
					local n = 0
					for i = #world.queue, 1, -1 do
						local m = world.queue[i]
						if m.from == cl and m.options and m.options.owner == owner and m.options.key == key then
							table.remove(world.queue, i)
							n = n + 1
							world.dropped[#world.dropped + 1] = { m = m, why = why }
							if m.done then m.done(false, why) end
						end
					end
					return n
				end,
			} end
			c.UnitFullName = function(unit) return U(unit) and U(unit).name end
			c.Roster = { RankOf = function(name) return world.olympians[Fold(name)] and 3 or nil end }
			c.Channels = { VerifiedLevel = function(sender) if world.olympians[Fold(sender)] then return 1, true end return 0, false end }
			c.Layers = { Mine = function() return cl.layer end, Sharing = function() return cl.private ~= true end }
			c.Pins = function() return cl.lib end
			c.Map = {
				Badge = function(size, round) local a = Frame("anchor") a.badge, a.size, a.round = Frame("badge"), size, round return a end,
				SetBadge = function(a, texture, r, g, b) a.badge.texture, a.badge.color = texture, { r, g, b } end,
			}
			if not cl.realConsent then c.Consent = { Register = function(item) cl.consent = item return true end } end
			c.Treasury = { NotFoundPattern = function() return "^No player named '(.+)' is currently playing%.$" end }
			c.RegisterEvent = function(event, call) cl.events[event] = call end
			c.On = function(event, call) cl.listeners[event] = call end
			c.Fire = function() end
			c.Print = function(message) cl.prints[#cl.prints + 1] = tostring(message) end
			c.Ago = function(at) return tostring(world.epoch - (tonumber(at) or 0)) .. "s" end
			c.ShowDialog = function() return true end
			c.After = function(seconds, _, f) world.timers[#world.timers + 1] = { at = world.epoch + seconds, cl = cl, owner = c, fn = f } end
			c.Every = function() end
			-- (A failure surfaces here; the game's SafeCall would only log it.)
			c.SafeCall = function(where, f, ...)
				local good, why = pcall(f, ...)
				if not good then error(where .. ": " .. tostring(why), 0) end
				return good
			end
			c.UI = { Refresh = function() end, RefreshSoon = function() end, AddTab = function() end,
				FirstTexture = function(paths) return paths[#paths] end }
			c.Log = function() end
			c.EscapeCloses = function() end
			cl.handlers, cl.listeners, cl.events, cl.ns, cl.lib, cl.filters = {}, {}, {}, c, PinLib(cl), {}
			world:As(cl, function()
				-- (In the TOC's order: Comm.lua, Backup.lua and Consent.lua before Wanted.lua.)
				if cl.realComm then assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c) end
				if cl.realBackup then assert(loadfile(ROOT .. "Olympus/Backup.lua"))("Olympus", c) end
				if cl.realConsent then assert(loadfile(ROOT .. "Olympus/Consent.lua"))("Olympus", c) end
				assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
			end)
			cl.W = c.Wanted
			if cl.realConsent then
				for _, item in ipairs(c.Consent.Items()) do if item.key == "wantedsightings" then cl.consent = item end end
			end
			c.me = cl.name
			-- 1.2.0: only the wanted are sighted; the Horde players these tests see are on each list.
			if cl.wanted ~= false then for _, h in ipairs(WANTED) do world:List(cl, h[1], h[2]) end end
			if cl.listeners.LOGIN then world:As(cl, cl.listeners.LOGIN) end
			return cl
		end
		-- A Horde player put on a client's Wanted list (as its manager would).
		function world:List(cl, name, guid)
			local W = cl.W
			local can = W.CanManage
			W.CanManage = function() return true end
			pcall(world.As, world, cl, W.AddTarget, name, guid)
			W.CanManage = can
		end
		function world:Client(name, guid, o)
			o = o or {}
			name = ns.FullName(name)
			-- (1.2.0: sightings are off until a Yes; these members said Yes unless a test gives its own db.)
			local cl = { name = name, guid = guid, member = o.member ~= false, manager = o.manager, db = o.db or { wantedSightings = true }, rdb = {}, prints = {},
				realComm = o.realComm, realConsent = o.realConsent, realBackup = o.realBackup, crown = o.crown, wanted = o.wanted,
				units = { player = { name = name, guid = guid, faction = "Alliance", guild = o.guild or "Olympus II" } },
				map = 1429, x = 0.4123, y = 0.6789, online = true }
			world.olympians[Fold(name)] = true
			if o.role then world.authorities[Fold(name)] = o.role end
			world.clients[#world.clients + 1] = cl
			return world:Load(cl)
		end
		function world:Find(to)
			local key = Fold(to)
			for _, o in ipairs(world.clients) do if Fold(o.name) == key then return o end end
			return nil
		end
		-- Comm's turn for each queued message: its permit (or guard) again, then the game's send.
		function world:Pump()
			local guard = 0
			while #world.queue > 0 do
				guard = guard + 1
				assert(guard < 1000, "the world settles")
				local m = table.remove(world.queue, 1)
				local o = m.options
				local okSend, why = true, nil
				world:As(m.from, function()
					if o and o.permit then okSend, why = o.permit(o.owner, o.key, m.dist, m.to, m.msg)
					elseif o and o.guard then okSend, why = o.guard() end
				end)
				if okSend ~= true then
					world.dropped[#world.dropped + 1] = { m = m, why = why }
					if m.done then world:As(m.from, m.done, false, why) end
				elseif m.dist == "WHISPER" then
					local to = world:Find(m.to)
					if m.done then world:As(m.from, m.done, true) end
					if to and to.online then
						world.delivered[#world.delivered + 1] = m
						local h = to.handlers[m.msg:sub(1, 2)]
						if h then world:As(to, h, "WHISPER", m.from.name, m.msg) end
					elseif m.from.events.CHAT_MSG_SYSTEM then
						world:As(m.from, m.from.events.CHAT_MSG_SYSTEM, NOT_FOUND:format(m.to))
					end
				else
					world.delivered[#world.delivered + 1] = m
					if m.done then world:As(m.from, m.done, true) end
					for _, other in ipairs(world.clients) do
						local h = other.handlers[m.msg:sub(1, 2)]
						if other ~= m.from and other.online and h then world:As(other, h, m.dist, m.from.name, m.msg) end
					end
				end
			end
		end
		function world:Run(seconds)
			local stop = world.epoch + seconds
			world:Pump()
			while true do
				table.sort(world.timers, function(a, b) return a.at < b.at end)
				local t = world.timers[1]
				if not t or t.at > stop then break end
				table.remove(world.timers, 1)
				world.epoch = math.max(world.epoch, t.at)
				if t.cl.online and t.cl.ns == t.owner then world:As(t.cl, t.fn) end
				world:Pump()
			end
			world.epoch = stop
		end
		function world:Advance(seconds) world.epoch = world.epoch + seconds end
		-- cl's client sees u as `unit` (a nameplate, its target, the mouse's).
		function world:See(cl, unit, u)
			cl.units[unit] = u
			return world:As(cl, cl.W.ObserveUnit, unit)
		end
		function world:Lease(...)
			for _, r in ipairs({ ... }) do assert(world:As(r, r.W.AnnounceReviewer), r.name .. "'s lease") end
			world:Pump()
		end
		function world:Pins(cl) return world:As(cl, cl.W.Sightings) end
		function world:Waiting(cl)
			local out = {}
			for _, m in ipairs(world.queue) do if m.from == cl and m.msg:sub(1, 5) == "WS~S~" then out[#out + 1] = m end end
			return out
		end
		-- What a pin's hover says (its frame's OnEnter, through the game's tooltip).
		function world:Hover(cl, frame)
			GameTooltip = Tooltip()
			world:As(cl, frame:GetScript("OnEnter"), frame)
			return table.concat(GameTooltip.lines, "\n")
		end
		function world:Recipients(cl) return table.concat(world:As(cl, cl.W.SightingRecipients), ",") end
		-- The reviewer cl sends his evidence to (as Wanted.SendEvidence keeps him).
		function world:Choose(cl, reviewer)
			if type(cl.rdb.wanted) ~= "table" then cl.rdb.wanted = { version = 1, group = "RealmGroup", faction = "Alliance" } end
			cl.rdb.wanted.reviewer = reviewer and reviewer.name or nil
		end
		-- What cl's chat frames would show of a system line (its filters, as the game runs them).
		function world:Shows(cl, text)
			local f = cl.filters.CHAT_MSG_SYSTEM
			return not (f and world:As(cl, f, nil, "CHAT_MSG_SYSTEM", text) == true)
		end
		fn(world)
	end)
	for _, name in ipairs(GLOBALS) do rawset(_G, name, saved[name]) end
	Enum.InputDeviceInterfaceType = savedInput
	for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = dialogs[which] end
	if not ok then error(err, 0) end
end

local function Dropped(world, why)
	local n = 0
	for _, d in ipairs(world.dropped) do if d.why == why and d.m.msg:sub(1, 5) == "WS~S~" then n = n + 1 end end
	return n
end

local function PtLocale()
	local pt, savedLocale = {}, GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt) end)
	GetLocale = savedLocale
	assert(ok, err)
	return pt.L
end


-- A backup text as a made one would carry it (Backup.lua's own writer and checksum).
local function MadeBackup(data)
	local payload = ns.Backup.Write(data)
	return ("OLYB1:%d:%s:%s"):format(#payload, ns.Backup.Sum(payload), payload)
end

test("wanted sightings (1.2.0): off until the member's own Yes, a line of its own on the privacy page that says what goes and to whom, asked until answered; its No, or /oly sightings off, stops collecting at once", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001", { db = {} })
		local W = o.W
		eq(o.db.wantedSightings, nil, "never answered")
		eq(world:As(o, W.SightingsOn), false, "off until a Yes")
		local item = assert(o.consent, "its line on the privacy page")
		eq(item.key, "wantedsightings")
		eq(world:As(o, item.get), false, "the page shows it off")
		eq(item.explicit, true, "its own Yes only")
		-- (Review: with pending always false the page never opened for it, so a member who had
		-- answered every other line was never shown it. It waits for an answer like the others,
		-- off meanwhile: tests below run the real page.)
		eq(world:As(o, item.pending), true, "asked until answered, off meanwhile")
		local ok = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		eq(ok, false, "nothing collected before a Yes")
		world:As(o, item.set, true)
		eq(world:As(o, item.shown), true, "a member's line")
		o.member = false
		eq(world:As(o, item.shown), false, "nobody else's")
		o.member = true
		local text = L[item.text]
		for _, part in ipairs({ "Horde player", "name and GUID", "your own map position (rounded) and layer", "the time, your name and your guild",
			"15 minutes", "whispered to one reviewer", "the one you send your Most Wanted evidence to", "the King, a High Councillor or the author",
			"until you have sent evidence to one, nobody gets it", "seen nearby", "Nothing goes while you keep your zone and layer private",
			"the King's only while his crown shows on the map", "Never anyone off the list", "never on the Olympus channel", "never in an instance", "nothing saved",
			"Accept all does not turn it on",
			"No stops it at once", "take your pins off his map", "before you logged out stays there until its 15 minutes are up",
			"/oly sightings on|off" }) do
			assert(text:find(part, 1, true), "the page says: " .. part)
		end
		-- (Review: what reached a reviewer outlives a logout; the page no longer says it does not.)
		assert(not text:find("after you log out", 1, true) and not text:find("two at most", 1, true), "no claim it cannot keep")
		assert(L[item.label]:find("off until you say Yes", 1, true), L[item.label])
		assert(not L.CONSENT_OPTIONAL:find("on until you say No", 1, true), "no line is on until a No any more")

		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)), "collected with no question asked")
		eq(#world:Pins(o), 1)
		-- The page's No.
		world:As(o, item.set, false)
		eq(o.db.wantedSightings, false); eq(world:As(o, item.get), false)
		eq(world:As(o, item.pending), false, "answered")
		eq(o.prints[#o.prints], L.WANTED_SIGHTINGS_OFF)
		eq(#world:Pins(o), 0, "its sightings leave its map")
		world:Advance(W.SIGHT_GAP + 1)
		local ok, why = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		eq(ok, false); eq(why, "off")
		-- /oly sightings on | off, and alone.
		world:As(o, W.SightingsSlash, "on")
		eq(o.db.wantedSightings, true); eq(o.prints[#o.prints], L.WANTED_SIGHTINGS_ON)
		eq(world:As(o, item.pending), false, "a yes is an answer too")
		assert(world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL)))
		world:As(o, W.SightingsSlash, "")
		eq(o.prints[#o.prints], L.WANTED_SIGHTINGS_ON, "alone, it says which")
		world:As(o, W.SightingsSlash, " OFF ")
		eq(o.db.wantedSightings, false)
		ok, why = world:See(o, "nameplate3", Horde("Rexxar-Realm", REXXAR))
		eq(ok, false); eq(why, "off")
		world:As(o, W.SightingsSlash, "status")
		eq(o.prints[#o.prints], L.WANTED_SIGHTINGS_OFF)
	end)
	-- /oly sightings reaches Wanted.lua; a client updated without a restart (no Wanted.lua yet) is told to restart.
	local savedPrint, printed = ns.Print, nil
	ns.Print = function(message) printed = message end
	local ok, err = pcall(SlashCmdList.OLYMPUS, "sightings off")
	ns.Print = savedPrint
	if not ok then error(err, 0) end
	eq(ns.Wanted.missing, true, "the harness's own namespace runs Core's stand-in")
	eq(printed, L.RESTART_NEEDED)
	-- Both languages.
	local pt = PtLocale()
	for _, key in ipairs({ "CONSENT_WANTED_SIGHTINGS", "CONSENT_WANTED_SIGHTINGS_TEXT", "WANTED_SIGHTINGS_ON", "WANTED_SIGHTINGS_OFF",
		"WANTED_SIGHT_UNLISTED", "WANTED_SIGHT_REMOVED", "WANTED_SIGHT_SEEN", "WANTED_SIGHT_BY_YOU", "WANTED_SIGHT_YOUR_LAYER",
		"WANTED_SIGHT_OTHER_LAYER", "WANTED_SIGHT_NEARBY", "HELP_SIGHTINGS", "CONSENT_OPTIONAL" }) do
		local en, br = rawget(L, key), rawget(pt, key)
		assert(type(en) == "string" and en ~= "", "English " .. key)
		assert(type(br) == "string" and br ~= "" and br ~= en, "pt-BR " .. key)
		local function Args(s) local out = {} for a in s:gmatch("%%%a") do out[#out + 1] = a end return table.concat(out) end
		eq(Args(br), Args(en), key .. ": format arguments")
		assert(not en:find("|[cTHrt]") and not br:find("|[cTHrt]"), key .. ": no escape codes")
	end
	local lines, savedOut = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	SlashCmdList.OLYMPUS("help")
	print = savedOut
	assert(table.concat(lines, "\n"):find(L.HELP_SIGHTINGS, 1, true), "in /oly help")
end)

test("wanted sightings on the real privacy page (Consent.lua): it opens by itself for a member who answered every other line, once a session; the bulk Yes never turns it on (1.2.0); its own Yes does; answered, it opens no more", function()
	WithSightings(function(world)
		-- A 1.1 member who answered every line the page had before this one.
		local db = { shareLocation = false, layerHelp = false, royalInspection = false, rollCall = true, addonChat = true }
		local o = world:Client("Aldric-Realm", "Player-1-AB000001", { realConsent = true, db = db })
		local P = o.ns.Consent
		assert(o.consent, "Wanted.lua's line on the real page")
		local function Waiting()
			local keys = {}
			for _, item in ipairs(world:As(o, P.Pending)) do keys[#keys + 1] = item.key end
			return table.concat(keys, ",")
		end
		eq(Waiting(), "wantedsightings", "this line alone waits")
		eq(world:As(o, P.Answer, "wantedsightings"), false, "off while it waits")
		eq(world:As(o, P.Ask, "login"), true, "the page opens by itself for it")
		eq(P.Frame():IsShown(), true)
		P.Hide()
		eq(world:As(o, P.Ask, "login"), false, "once a session")
		-- Its main button, nothing chosen: authorize all leaves it unanswered and off.
		world:As(o, P.Show)
		world:As(o, P.AuthorizePending)
		eq(o.db.wantedSightings, nil, "the bulk Yes never answers it"); eq(Waiting(), "wantedsightings")
		-- Its own Yes turns it on.
		eq(world:As(o, P.Choose, "wantedsightings", true), true)
		eq(o.db.wantedSightings, true, "a yes, recorded"); eq(Waiting(), "")
		-- A No, then the bulk Yes again: the No stands.
		eq(world:As(o, P.Choose, "wantedsightings", false), true)
		eq(o.db.wantedSightings, false)
		eq(world:As(o, P.AuthorizePending), true)
		eq(o.db.wantedSightings, false, "never over a No")
		-- Another session: answered, the page does not open for it.
		P.Reset()
		eq(world:As(o, P.Ask, "login"), false)
	end)
end)

test("wanted sightings: only a listed Horde player (1.2.0: never just a hostile one flagged for PvP), as the game gives him, where this player stands (rounded) and his layer; never an Olympus guild's, a friendly one, a pet, ourselves, a secret value, nor in an instance, net-off or off a zone's map", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001", { manager = true })
		o.layer = { mapID = 1429, zoneUID = 4242, t = world.epoch - 30 }
		local ok, e = world:See(o, "nameplate1", Horde("Grom-Realm", GROM, { guild = "Bloodfang" }))
		assert(ok, e)
		eq(e.name, "Grom-Realm"); eq(e.guid, GROM); eq(e.mapID, 1429)
		eq(e.x, 410, "0.4123 of the map: its nearest half percent"); eq(e.y, 680)
		eq(e.layer, 4242, "this player's layer, Layers saw it 30 seconds ago")
		eq(e.observer, "Aldric-Realm"); eq(e.own, true); eq(e.listed, true); eq(e.at, world.epoch)
		eq(#e.id, 16)
		local cases = {
			{ "unlisted", Horde("Calm-Realm", "Player-1-0A000011", { pvp = false }) },
			{ "unlisted", Horde("Friendly-Realm", "Player-1-0A000012", { hostile = false }) },
			{ "unlisted", Horde("Hordeolympian-Realm", "Player-1-0A000013", { guild = "Olympus Horde" }) },
			-- 1.2.0: hostile and flagged for PvP is not enough; only the wanted are sighted.
			{ "unlisted", Horde("Flagged-Realm", "Player-1-0A00001A", { guild = "Bloodfang" }) },
			{ "faction", Horde("Ally-Realm", "Player-1-0A000014", { faction = "Alliance" }) },
			{ "faction", Horde("Masked-Realm", "Player-1-0A000015", { faction = SECRET }) },
			{ "player", Horde("Wolf", "Creature-0-1-2-3-4-0000000001", { player = false }) },
			{ "identity", Horde(SECRET, "Player-1-0A000016") },
			{ "identity", Horde("Hidden-Realm", SECRET) },
			{ "identity", Horde("Noguid-Realm", nil) },
			{ "unlisted", Horde("Veiled-Realm", "Player-1-0A000017", { guild = SECRET }) },
			{ "self", Horde("Aldric-Realm", "Player-1-AB000001") },
		}
		for i, case in ipairs(cases) do
			local okCase, why = world:See(o, "nameplate" .. (i + 1), case[2])
			eq(okCase, false, case[1]); eq(why, case[1], case[1])
		end
		-- A Horde player this client's own list names counts, flagged or not.
		assert(world:As(o, o.W.AddTarget, "Listed-Realm", "Player-1-0A000018"))
		local okListed, listed = world:See(o, "target", Horde("Listed-Realm", "Player-1-0A000018", { pvp = false, hostile = false }))
		assert(okListed, listed); eq(listed.listed, true)
		-- A layer seen too long ago is not known (0).
		o.layer.t = world.epoch - o.W.SIGHT_LAYER_FRESH - 1
		local _, stale = world:See(o, "mouseover", Horde("Stale-Realm", "Player-1-0A000019"))
		eq(stale.layer, 0)
		-- Where nothing is collected.
		local function Not(why, unit, guid)
			world:List(o, "Nobody-Realm", guid)
			local okNot, said = world:See(o, unit, Horde("Nobody-Realm", guid))
			eq(okNot, false, why); eq(said, why, why)
		end
		o.instance = true; Not("instance", "nameplate20", "Player-1-0A000020"); o.instance = false
		o.netoff = { by = "Moderator-Realm" }; Not("netoff", "nameplate20", "Player-1-0A000020"); o.netoff = nil
		o.map = 1415; Not("position", "nameplate20", "Player-1-0A000020")
		o.map = 947; Not("position", "nameplate20", "Player-1-0A000020")
		o.map = nil; Not("position", "nameplate20", "Player-1-0A000020")
		o.map, o.x = 1429, nil; Not("position", "nameplate20", "Player-1-0A000020")
		o.x = 0.5; o.member = false; Not("member", "nameplate20", "Player-1-0A000020"); o.member = true
		eq(#world:Pins(o), 3, "Grom, the listed one and the one whose layer was not known")
		eq(world:As(o, o.W.Stats).sightSeen, 3)
	end)
end)

test("wanted sightings: each Horde player once per gap on one map (nothing more asked of the game); three a minute leave this client, the rest stay on its map; only to the reviewer this member sends his evidence to, while he takes them; whispers waiting are bounded", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		local c1 = world:Client("Councilone-Realm", "Player-1-AB0000F2", { role = "council" })
		local c2 = world:Client("Counciltwo-Realm", "Player-1-AB0000F3", { role = "council" })
		local plain = world:Client("Plainmember-Realm", "Player-1-AB0000F4")
		eq(world:As(plain, plain.W.AnnounceReviewer), false, "a member who reviews nothing takes no sightings")
		world:Lease(c2); world:Advance(1); world:Lease(king); world:Advance(1); world:Lease(c1)
		-- (Review: they went to two reviewers, the King first among those the member never chose,
		-- while his evidence goes to the one he chose alone. Now to that one alone.)
		eq(world:Recipients(o), "", "a member who sent evidence to nobody sends his sightings to nobody")
		local ok, e = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 0, "it stays on his own map"); eq(#world:Pins(o), 1)
		world:Pump()
		eq(#world:Pins(king), 0); eq(#world:Pins(c1), 0); eq(#world:Pins(c2), 0)
		world:Choose(o, c2)
		eq(world:Recipients(o), "Counciltwo-Realm", "the reviewer he sends his evidence to, and nobody else")
		world:Choose(king, king)
		eq(world:Recipients(king), "", "never himself")
		world:Choose(o, plain)
		eq(world:Recipients(o), "", "nobody who reviews nothing")
		world.authorities[world.Fold("Councilthree-Realm")] = "council"
		world:Choose(o, { name = "Councilthree-Realm" })
		eq(world:Recipients(o), "", "nobody whose client did not say it takes them")
		world:Choose(o, c2)

		world:Advance(o.W.SIGHT_GAP)
		ok, e = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 1)
		eq(#world:Waiting(o), 1)
		world:Pump()
		local m = world.delivered[#world.delivered]
		eq(m.dist, "WHISPER"); eq(world:Find(m.to), c2)
		eq(m.msg, ("WS~S~1~Olympus II~%s~%d~1429~410~680~0~1.0a000001~Grom-Realm"):format(e.id, e.at),
			"his name and GUID, the observer's spot and layer, the time, the guild: nothing else")
		eq(#world:Pins(c2), 1)
		eq(#world:Pins(king), 0, "the King gets none he was not chosen for"); eq(#world:Pins(c1), 0); eq(#world:Pins(plain), 0)
		for _, d in ipairs(world.delivered) do assert(not (d.dist == "CHANNEL" and d.msg:find("^WS~S~")), "never on the channel") end
		local got = world:Pins(c2)[1]
		eq(got.observer, "Aldric-Realm"); eq(got.own, false); eq(got.x, 410); eq(got.y, 680); eq(got.guild, "Olympus II")

		-- The same Horde player again on this map within the gap: nothing new, and not even his
		-- position asked again (review: nameplates come and go all through a fight).
		world:Advance(30)
		local positions, repeats = world.positions, world:As(o, o.W.Stats).sightRepeat
		local again, why = world:See(o, "nameplate2", Horde("Grom-Realm", GROM))
		eq(again, false); eq(why, "repeat")
		eq(world.positions, positions, "no position asked of the game"); eq(world:As(o, o.W.Stats).sightRepeat, repeats + 1)
		-- On another map: a sighting.
		o.map = 1436
		ok, e = world:See(o, "nameplate2", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 1)
		ok, e = world:See(o, "nameplate3", Horde("Thrall-Realm", THRALL))
		eq(e.sent, 1, "the third this minute")
		ok, e = world:See(o, "nameplate4", Horde("Rexxar-Realm", REXXAR))
		assert(ok, e); eq(e.sent, 0, "the fourth stays on this map")
		eq(world:As(o, o.W.Stats).sightRate, 1)
		eq(#world:Pins(o), 3, "Grom (once: his newest), Thrall, Rexxar")
		world:Pump()
		eq(#world:Pins(c2), 2, "Grom where he was seen last, and Thrall")
		for _, p in ipairs(world:Pins(c2)) do eq(p.mapID, 1436) end
		-- The window over: they go again.
		world:Advance(o.W.SIGHT_WINDOW + 1)
		ok, e = world:See(o, "nameplate5", Horde("Garrosh-Realm", GARROSH))
		eq(e.sent, 1)
		world:Pump()
		-- Whispers waiting in Comm (nothing pumps them): SIGHT_QUEUE_MAX at most.
		local sent = {}
		for window = 1, 3 do
			world:Advance(o.W.SIGHT_WINDOW + 1)
			for i = 1, 3 do
				local n = (window - 1) * 3 + i
				world:List(o, "Waitone" .. n .. "-Realm", ("Player-1-0B0000%02d"):format(n))
				local _, w = world:See(o, "nameplate1" .. n, Horde("Waitone" .. n .. "-Realm", ("Player-1-0B0000%02d"):format(n)))
				sent[#sent + 1] = w.sent
			end
		end
		eq(table.concat(sent, ","), "1,1,1,1,1,1,1,1,0", "eight wait at most")
		eq(#world:Waiting(o), o.W.SIGHT_QUEUE_MAX)
		world:Pump()
		eq(Dropped(world, "stale"), 6, "the ones that waited past their 30 seconds never go")
	end)
end)

test("wanted sightings: the No cancels every sighting still waiting in Comm at once; Comm's own check stops one that waits past the No, net-off, its age or its reviewer's role", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		local c1 = world:Client("Councilone-Realm", "Player-1-AB0000F2", { role = "council" })
		world:Lease(king, c1)
		world:Choose(o, king)
		local item = o.consent
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		eq(#world:Waiting(o), 1)
		world:As(o, item.set, false) -- the privacy page's No
		eq(#world:Waiting(o), 0, "cancelled at once, not when its turn comes")
		eq(Dropped(world, "off"), 1)
		eq(world:As(o, o.W.Stats).sightCancelled, 1)
		for _, m in ipairs(world.queue) do assert(m.msg ~= "WS~X~1", "nothing reached anyone: nothing to take back") end
		world:Pump()
		eq(#world:Pins(king), 0); eq(#world:Pins(c1), 0)
		world:As(o, item.set, true)

		-- What Comm checks when each one's turn comes.
		local function Next(name, guid)
			world:Advance(o.W.SIGHT_WINDOW + 1)
			for _, cl in ipairs(world.clients) do world:List(cl, name, guid) end
			local ok, e = world:See(o, "nameplate1", Horde(name, guid))
			assert(ok, e); eq(e.sent, 1, name)
		end
		Next("Thrall-Realm", THRALL)
		o.netoff = { by = "Moderator-Realm" }
		world:Pump()
		eq(Dropped(world, "netoff"), 1, "the moderators took this client off meanwhile")
		o.netoff = nil
		Next("Rexxar-Realm", REXXAR)
		o.db.wantedSightings = false
		world:Pump()
		eq(Dropped(world, "off"), 2, "a No that reached the saved answer some other way")
		o.db.wantedSightings = true -- (the Yes again; 1.2.0: no answer is off)
		Next("Garrosh-Realm", GARROSH)
		world:Advance(o.W.SIGHT_QUEUE_TTL + 1)
		world:Pump()
		eq(Dropped(world, "stale"), 1, "too old to go")
		world:Choose(o, c1)
		Next("Lateone-Realm", "Player-1-0A000021")
		world.authorities[world.Fold(c1.name)] = nil
		world:Pump()
		eq(Dropped(world, "reviewer"), 1, "a councillor no more")
		eq(#world:Pins(king), 0); eq(#world:Pins(c1), 0)
		eq(#world:Pins(o), 4, "this client's own map keeps those after the No (which took Grom off it)")
		-- And one that may go, goes.
		world:Choose(o, king)
		Next("Goesthrough-Realm", "Player-1-0A000022")
		world:Pump()
		eq(#world:Pins(king), 1)
	end)
end)

test("wanted sightings: the King's client sends none while his crown is hidden (his own map still shows them); Comm's check stops one waiting when he hides it, and hiding it cancels what waits and takes back what went", function()
	WithSightings(function(world)
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		local c1 = world:Client("Councilone-Realm", "Player-1-AB0000F2", { role = "council" })
		world:Lease(c1)
		world:Choose(king, c1)
		-- (Review: a King whose crown was hidden whispered his own spot and layer with each sighting.)
		local ok, e = world:See(king, "nameplate1", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 0, "crown hidden: nothing goes"); eq(#world:Pins(king), 1, "his own map shows it")
		world:Pump()
		eq(#world:Pins(c1), 0)
		king.crown = true
		ok, e = world:See(king, "nameplate2", Horde("Thrall-Realm", THRALL))
		eq(e.sent, 1, "crown shown: to his reviewer")
		world:Pump()
		eq(#world:Pins(c1), 1)
		-- One waits when he hides it: Comm's own check stops it at its turn.
		ok, e = world:See(king, "nameplate3", Horde("Rexxar-Realm", REXXAR))
		eq(e.sent, 1)
		king.crown = false
		world:Pump()
		eq(Dropped(world, "crown"), 1)
		-- Shown again, one waits, and he hides it with the Throne's switch (King.lua's event): it is
		-- cancelled at once, and what went is taken off the councillor's map.
		king.crown = true
		world:Advance(king.W.SIGHT_WINDOW + 1)
		ok, e = world:See(king, "nameplate4", Horde("Garrosh-Realm", GARROSH))
		eq(e.sent, 1)
		king.crown = false
		world:As(king, king.listeners.KING_LOCATION_CHANGED, "hide", king.name, 7)
		eq(#world:Waiting(king), 0, "cancelled at once")
		eq(Dropped(world, "crown"), 2)
		world:Pump()
		eq(#world:Pins(c1), 0, "Thrall taken off the councillor's map")
		eq(#world:Pins(king), 4, "the King's own map keeps his")
		-- Another crown heard (or his hidden again): nothing more to take back.
		local before = #world.delivered
		world:As(king, king.listeners.KING_LOCATION_CHANGED, "show", "Otherking-Realm", 9)
		world:Pump()
		eq(#world.delivered, before)
	end)
end)

test("wanted sightings: a reviewer takes a sighting only by whisper, fresh, from an Olympian the moderators did not take off, once, three a minute from one sender and thirty from all (counted before anything is parsed); what a modified client may send is kept nowhere", function()
	WithSightings(function(world)
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		local plain = world:Client("Plainmember-Realm", "Player-1-AB0000F4")
		local serial = 0
		local function Body(o)
			o = o or {}
			serial = serial + 1
			return ("WS~S~%s~%s~%s~%s~%s~%s~%s~%s~%s~%s"):format(o.v or "1", o.guild or "Olympus II", o.id or ("%016x"):format(serial),
				o.at or world.epoch, o.map or 1429, o.x or 410, o.y or 680, o.layer or 0, o.guid or "1.0a000001", o.name or "Grom-Realm")
		end
		local function Take(sender, body, dist, cl)
			cl = cl or king
			return world:As(cl, cl.W.HandleSighting, dist or "WHISPER", sender, body)
		end
		local function Why(...) return select(2, Take(...)) end
		world.olympians[world.Fold("Watcher-Realm")] = true
		local ok, e = Take("Watcher-Realm", Body({ id = "00000000000000aa" }))
		assert(ok, e)
		eq(e.observer, "Watcher-Realm"); eq(e.guid, GROM); eq(e.name, "Grom-Realm"); eq(e.guild, "Olympus II"); eq(e.own, false)
		eq(Why("Watcher-Realm", Body({ id = "00000000000000aa" })), "replay", "once")
		eq(Why("Stranger-Realm", Body()), "olympus", "nobody the Olympus chats would take")
		eq(Why("Watcher-Realm", Body({ guid = "1.0a00001a", name = "Flagged-Realm" })), "unlisted", "1.2.0: only the wanted")
		world.olympians[world.Fold("Hiddenone-Realm")] = true
		world.hidden[world.Fold("Hiddenone-Realm")] = { by = "Moderator-Realm" }
		eq(Why("Hiddenone-Realm", Body()), "olympus", "a name the moderators took off")
		eq(Why("Watcher-Realm", Body({ at = world.epoch - king.W.SIGHT_TTL - 1 })), "stale")
		eq(Why("Watcher-Realm", Body({ at = world.epoch + 121 })), "stale")
		for _, bad in ipairs({ Body({ v = "2" }), Body({ id = "abc" }), Body({ guid = "1.ZZ" }), Body({ guid = "Player-1-0A000001" }),
			Body({ x = 1001 }), Body({ y = "-5" }), Body({ map = 1415 }), Body({ map = 947 }), Body({ map = 0 }), Body({ guild = "Bloodfang" }),
			Body({ name = "" }), Body({ layer = "x" }), Body() .. "~more", "WS~S~1", "WS~S~1~" .. ("x"):rep(250) }) do
			eq(Why("Watcher-Realm", bad), "shape", bad)
		end
		eq(Why("Watcher-Realm", Body(), "CHANNEL"), "lane", "never off the channel")
		eq(Why("Watcher-Realm", Body(), "GUILD"), "lane")
		eq(Why("Watcher-Realm", Body(), "WHISPER", plain), "reviewer", "a member who reviews nothing keeps none")
		eq(Why("Kingly-Realm", Body()), "sender", "his own")
		eq(#world:Pins(plain), 0)
		-- One sender: three a window; the fourth refused before it is even read (review: the
		-- reviewer's client parsed and checked every whisper before counting it).
		assert(Take("Watcher-Realm", Body()))
		assert(Take("Watcher-Realm", Body()))
		local infos = world.mapInfos
		eq(Why("Watcher-Realm", Body()), "rate", "the fourth this minute")
		eq(Why("Watcher-Realm", "WS~S~1~unread"), "rate", "not parsed")
		eq(world.mapInfos, infos, "no map looked up for it")
		world:Advance(king.W.SIGHT_WINDOW)
		assert(Take("Watcher-Realm", Body()), "a new window")
		-- Everyone: thirty a window.
		world:Advance(king.W.SIGHT_WINDOW)
		for i = 1, king.W.SIGHT_INTAKE_MAX do
			local name = "Watcher" .. i .. "-Realm"
			world.olympians[world.Fold(name)] = true
			world:List(king, "Horde" .. i .. "-Realm", ("Player-1-0C%06X"):format(i))
			assert(Take(name, Body({ guid = ("1.0c%06x"):format(i), name = "Horde" .. i .. "-Realm" })), name)
		end
		world.olympians[world.Fold("Watcher99-Realm")] = true
		infos = world.mapInfos
		eq(Why("Watcher99-Realm", Body()), "rate", "the reviewer's intake is full this minute")
		eq(world.mapInfos, infos, "nothing looked up for it")
		eq(#world:Pins(king), 31, "one pin per Horde player")
		-- Leases: a reviewer's, on the channel, in its two shapes.
		eq(Why("Plainmember-Realm", "WS~R~1", "CHANNEL", plain), "authority", "only a reviewer says he takes them")
		eq(Why("Kingly-Realm", "WS~R~1", "WHISPER", plain), "shape")
		eq(Why("Kingly-Realm", "WS~R~0", "WHISPER", plain), "shape")
		eq(Why("Kingly-Realm", "WS~R~2", "CHANNEL", plain), "shape")
		eq(Why("Kingly-Realm", "WS~Q~1", "CHANNEL", plain), "shape")
		eq(Why("Kingly-Realm", "WS~R~0", "CHANNEL", plain), "unknown", "no lease to end")
		assert(Take("Kingly-Realm", "WS~R~1", "CHANNEL", plain))
		world:Choose(plain, king)
		eq(world:Recipients(plain), "Kingly-Realm")
		-- Taking back: by whisper, in its one shape.
		eq(Why("Watcher-Realm", "WS~X~1", "CHANNEL"), "shape")
		eq(Why("Watcher-Realm", "WS~X~2"), "shape")
	end)
end)

test("wanted sightings: a pin per Horde player where he was seen last, on the minimap and (mouse and keyboard) the world map; its hover his name, his kills by the ledger, how long ago and who saw him, the layer; a target taken off the list keeps his kills and no bounty; gone after 15 minutes; 48 at most", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local o2 = world:Client("Brenna-Realm", "Player-1-AB000002")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king", manager = true })
		-- The King's ledger: Grom killed two Olympians.
		world:As(king, function()
			king.W.AddTarget("Grom-Realm", GROM) -- (already listed: world:Client)
			assert(king.W.CaptureCombatLog(1, "PARTY_KILL", false, GROM, "Grom-Realm", 0, 0, o.guid, o.name))
		end)
		world:Advance(6)
		world:As(king, function() assert(king.W.CaptureCombatLog(2, "PARTY_KILL", false, GROM, "Grom-Realm", 0, 0, o2.guid, o2.name)) end)
		eq(world:As(king, king.W.Target, "Grom-Realm").lifetimeKills, 2)
		world:Lease(king)
		world:Choose(o, king); world:Choose(o2, king)
		o.layer = { mapID = 1429, zoneUID = 4242, t = world.epoch }
		king.layer = { mapID = 1429, zoneUID = 4242, t = world.epoch }
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		eq(o.lib:Take(), "mini+ 1429 0.410 0.680, world+ 1429 0.410 0.680", "on the observer's own maps")
		world:Pump()
		eq(king.lib:Take(), "mini+ 1429 0.410 0.680, world+ 1429 0.410 0.680", "on the King's, at the observer's spot")
		local f = assert(world:As(king, king.W.PinFrames)[GROM])
		eq(f.world.badge.texture, king.W.ICON_PATHS[#king.W.ICON_PATHS], "the Most Wanted banner")
		eq(f.world.size, king.W.SIGHT_BADGE); eq(f.world.round, true)
		local tip = world:Hover(king, f.world.badge)
		eq(tip, table.concat({ "Grom", L.WANTED_LIFETIME:format(2), L.WANTED_BOUNTY:format(2), L.WANTED_SIGHT_SEEN:format("0s", "Aldric"),
			L.WANTED_SIGHT_YOUR_LAYER, L.WANTED_SIGHT_NEARBY }, "\n"))
		eq(world:Hover(king, f.mini), tip, "the minimap's says the same")
		local mine = world:As(o, o.W.PinFrames)[GROM]
		-- (1.2.0: only the wanted are sighted, so he is on the observer's own list too, no kills counted there.)
		eq(world:Hover(o, mine.world.badge), table.concat({ "Grom", L.WANTED_LIFETIME:format(0), L.WANTED_BOUNTY:format(0), L.WANTED_SIGHT_SEEN:format("0s", L.WANTED_SIGHT_BY_YOU),
			L.WANTED_SIGHT_YOUR_LAYER, L.WANTED_SIGHT_NEARBY }, "\n"), "on the observer's own: his list, his own sighting")
		-- Two minutes later another Olympian sees him elsewhere, on another layer: the one pin moves there.
		world:Advance(120)
		o2.x, o2.y = 0.2, 0.3
		o2.layer = { mapID = 1429, zoneUID = 5151, t = world.epoch }
		king.layer.t = world.epoch
		assert(world:See(o2, "target", Horde("Grom-Realm", GROM)))
		world:Pump()
		eq(#world:Pins(king), 1, "one pin per Horde player")
		eq(king.lib:Take(), "mini+ 1429 0.200 0.300, world+ 1429 0.200 0.300")
		eq(world:As(king, king.W.PinFrames)[GROM], f, "its frames kept")
		tip = world:Hover(king, f.world.badge)
		assert(tip:find(L.WANTED_SIGHT_SEEN:format("0s", "Brenna"), 1, true), tip)
		assert(tip:find(L.WANTED_SIGHT_OTHER_LAYER, 1, true), tip)
		world:Advance(60)
		assert(world:Hover(king, f.world.badge):find(L.WANTED_SIGHT_SEEN:format("60s", "Brenna"), 1, true), "its age")
		-- The manager takes him off the list (review: the hover still gave his bounty, as if wanted).
		assert(world:As(king, king.W.RemoveTarget, "Grom-Realm", GROM))
		tip = world:Hover(king, f.world.badge)
		eq(select(2, tip:gsub("\n", "\n")) + 1, 6, tip)
		assert(tip:find(L.WANTED_LIFETIME:format(2), 1, true) and tip:find(L.WANTED_SIGHT_REMOVED, 1, true), tip)
		assert(not tip:find(L.WANTED_BOUNTY:format(2), 1, true) and not tip:find(L.WANTED_SIGHT_UNLISTED, 1, true), "no bounty, and not 'never listed'")
		-- An older sighting arriving late does not move it back.
		local late = ("WS~S~1~Olympus II~00000000000000bb~%d~1429~900~900~0~1.0a000001~Grom-Realm"):format(world.epoch - 300)
		world:As(king, king.W.HandleSighting, "WHISPER", o.name, late)
		eq(world:Pins(king)[1].x, 200)
		-- Fifteen minutes after the newest: gone, from both maps.
		world:Advance(king.W.SIGHT_TTL - 60)
		world:As(king, king.W.RefreshPins)
		eq(king.lib:Take(), "", "still fresh")
		world:Advance(1)
		world:As(king, king.W.RefreshPins)
		eq(king.lib:Take(), "mini-, world-")
		eq(#world:Pins(king), 0); eq(rawget(f.world.badge, "sighting"), nil)
		-- 48 at most: the oldest go first.
		local o3 = world:Client("Cedric-Realm", "Player-1-AB000003")
		for i = 1, o3.W.SIGHT_PINS + 1 do
			world:List(o3, "Many" .. i .. "-Realm", ("Player-1-0D%06x"):format(i))
			assert(world:See(o3, "nameplate1", Horde("Many" .. i .. "-Realm", ("Player-1-0D%06x"):format(i))))
			world:Advance(1)
		end
		local held = world:Pins(o3)
		eq(#held, o3.W.SIGHT_PINS)
		eq(held[#held].name, "Many2-Realm", "the first one left")
	end)
end)

test("wanted sightings: with the gamepad UI none of these pins goes on the world map (those there are taken off once), the minimap's stay; back to mouse and keyboard they return", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		eq(o.lib:Take(), "mini+ 1429 0.410 0.680, world+ 1429 0.410 0.680")
		world.gamepad = true
		world:As(o, o.W.RefreshPins)
		eq(o.lib:Take(), "worldAll", "taken off the world map once")
		world:As(o, o.W.RefreshPins)
		eq(o.lib:Take(), "", "and the world map never touched again")
		o.x, o.y = 0.25, 0.75
		assert(world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL)))
		eq(o.lib:Take(), "mini+ 1429 0.250 0.750", "the minimap's alone")
		world.gamepad = false
		world:As(o, o.W.RefreshPins)
		eq(o.lib:Take(), "world+ 1429 0.250 0.750, world+ 1429 0.410 0.680", "back on the world map, the minimap's untouched")
		world:As(o, o.W.RefreshPins)
		eq(o.lib:Take(), "", "nothing drawn twice")
	end)
end)

test("wanted sightings: none of these pins while this player is in an instance, back outside while fresh; none for a player outside Olympus; nothing collected inside", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		world:Lease(king)
		world:Choose(o, king)
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		o.lib:Take(); king.lib:Take()
		king.instance = true
		world:Pump() -- (taken while he is inside: kept, not drawn)
		eq(king.lib:Take(), "", "not drawn inside")
		eq(#world:Pins(king), 1, "kept")
		world:As(king, king.events.PLAYER_ENTERING_WORLD)
		eq(king.lib:Take(), "")
		king.instance = false
		world:As(king, king.events.PLAYER_ENTERING_WORLD)
		eq(king.lib:Take(), "mini+ 1429 0.410 0.680, world+ 1429 0.410 0.680", "back outside")
		king.instance = true
		world:As(king, king.events.ZONE_CHANGED_NEW_AREA)
		eq(king.lib:Take(), "mini-, world-", "taken off on the way in")
		local ok, why = world:See(king, "nameplate1", Horde("Thrall-Realm", THRALL))
		eq(ok, false); eq(why, "instance", "nothing collected inside")
		king.instance = false
		world:As(king, king.W.RefreshPins)
		king.lib:Take()
		o.member = false
		world:As(o, o.W.RefreshPins)
		eq(o.lib:Take(), "mini-, world-", "no pins outside Olympus")
		world:Advance(king.W.SIGHT_TTL + 1)
		world:As(king, king.W.RefreshPins)
		eq(king.lib:Take(), "mini-, world-")
		king.instance = true
		world:As(king, king.W.RefreshPins)
		king.instance = false
		world:As(king, king.W.RefreshPins)
		eq(king.lib:Take(), "", "an expired one never comes back")
	end)
end)

test("wanted sightings: a reviewer says he takes them 45 seconds after login and every 5 minutes while he holds the role, at once when the role comes mid-session; a lapsed role, an old lease or the server's 'no player named' stops the whispers to him, and that line is kept out of the member's chat a moment", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local plain = world:Client("Plainmember-Realm", "Player-1-AB0000F4")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		world:Choose(o, king)
		local function Leases(from)
			local n = 0
			for _, m in ipairs(world.delivered) do
				if m.msg == "WS~R~1" and m.from == (from or king) then n = n + 1 eq(m.dist, "CHANNEL") end
			end
			return n
		end
		world:Run(king.W.REVIEWER_FIRST - 1)
		eq(Leases(), 0); eq(world:Recipients(o), "")
		world:Run(1)
		eq(Leases(), 1, "45 seconds after his login"); eq(world:Recipients(o), "Kingly-Realm")
		world:Run(king.W.REVIEWER_EVERY)
		eq(Leases(), 2, "then on his beat")
		-- The role is checked each time: lost, his lease counts no more and he sends none.
		world.authorities[world.Fold(king.name)] = nil
		eq(world:Recipients(o), "")
		world:Run(king.W.REVIEWER_EVERY)
		eq(Leases(), 2)
		world.authorities[world.Fold(king.name)] = "king"
		world:Run(king.W.REVIEWER_EVERY)
		eq(Leases(), 3)
		-- A role that comes mid-session (the council's list: DATA_CHANGED) says so at once.
		eq(Leases(plain), 0)
		world.authorities[world.Fold(plain.name)] = "council"
		world:As(plain, plain.listeners.DATA_CHANGED)
		world:Pump()
		eq(Leases(plain), 1, "a councillor now: at once, not at the next beat")
		world:As(plain, plain.listeners.DATA_CHANGED)
		world:Pump()
		eq(Leases(plain), 1, "and not again on every change")
		world.authorities[world.Fold(plain.name)] = nil
		-- A lease not heard for 11 minutes: lapsed.
		king.online = false
		world:Run(king.W.REVIEWER_FOR + 1)
		eq(world:Recipients(o), "", "lapsed")
		-- Back: he logs in again; then logs out without a word. The server's "No player named" for
		-- the first whisper drops him, and what still waits for him.
		king.online = true
		world:Load(king)
		world:Run(king.W.REVIEWER_FIRST)
		eq(world:Recipients(o), "Kingly-Realm")
		king.online = false
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		assert(world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL)))
		local waiting = world:Waiting(o)
		eq(#waiting, 2)
		local line = NOT_FOUND:format(waiting[1].to)
		world:Pump()
		eq(Dropped(world, "offline"), 1, "the second never goes")
		eq(world:Recipients(o), "")
		-- (Review: each member then saw that line, naming the King, with no idea why. The addon sent
		-- it on its own: the line is kept out of his chat frames a moment, any other shows.)
		eq(world:Shows(o, line), false, "not in his chat")
		eq(world:Shows(o, NOT_FOUND:format("Someoneelse")), true, "another name's shows")
		eq(world:Shows(o, "Grom has come online."), true)
		world:Advance(o.W.SIGHT_QUIET + 1)
		eq(world:Shows(o, line), true, "later, one he typed himself shows")
		local ok, e = world:See(o, "nameplate3", Horde("Rexxar-Realm", REXXAR))
		assert(ok, e); eq(e.sent, 0, "nobody to send it to: it stays on this map")
		eq(#world:Pins(o), 3)
		for _, m in ipairs(world.delivered) do assert(not (m.from == plain and m.msg ~= "WS~R~1"), "nothing else from a plain member") end
	end)
end)

test("wanted sightings: a reviewer's own No stops what he takes too: his lease goes off on the channel, members stop whispering him and cancel what waits for him, his map is cleared; his Yes says at once that he takes them again", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		world:Lease(king)
		world:Choose(o, king)
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		world:Pump()
		eq(#world:Pins(king), 1)
		-- (Review: his No stopped only his own collecting; he kept announcing, and taking them.)
		world:As(king, king.consent.set, false)
		eq(#world:Pins(king), 0, "his map cleared")
		local last = world.queue[#world.queue]
		eq(last.msg, "WS~R~0"); eq(last.dist, "CHANNEL"); eq(last.from, king)
		assert(world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL)), "the member, before he hears it")
		eq(#world:Waiting(o), 1)
		world:Pump()
		eq(Dropped(world, "reviewer"), 1, "what waited for him cancelled when his No was heard")
		eq(world:Recipients(o), "")
		eq(#world:Pins(king), 0)
		local ok, why = world:As(king, king.W.HandleSighting, "WHISPER", o.name,
			("WS~S~1~Olympus II~00000000000000cc~%d~1429~410~680~0~1.0a000003~Rexxar-Realm"):format(world.epoch))
		eq(ok, false); eq(why, "reviewer", "he takes none")
		eq(world:As(king, king.W.AnnounceReviewer), false)
		local before = #world.delivered
		world:Run(king.W.REVIEWER_EVERY + king.W.REVIEWER_FIRST)
		for i = before + 1, #world.delivered do assert(world.delivered[i].msg ~= "WS~R~1", "no lease on his beat") end
		-- His Yes: at once.
		world:As(king, king.consent.set, true)
		world:Pump()
		eq(world:Recipients(o), "Kingly-Realm")
	end)
end)

test("wanted sightings: a member's No takes what reached his reviewer off that reviewer's map at once (other members' stay); nobody else can take them back", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local o2 = world:Client("Brenna-Realm", "Player-1-AB000002")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		world:Lease(king)
		world:Choose(o, king); world:Choose(o2, king)
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		assert(world:See(o2, "nameplate1", Horde("Thrall-Realm", THRALL)))
		world:Pump()
		eq(#world:Pins(king), 2)
		-- A modified client cannot take another's back: the server stamps the sender.
		local ok, n = world:As(king, king.W.HandleSighting, "WHISPER", "Brenna-Realm", "WS~X~1")
		assert(ok); eq(n, 1, "Brenna's own only")
		eq(#world:Pins(king), 1)
		eq(world:Pins(king)[1].observer, "Aldric-Realm")
		-- (Review: the page said No stops it at once, while the reviewer kept the pin 15 minutes.)
		world:As(o, o.consent.set, false)
		local back = world.queue[#world.queue]
		eq(back.msg, "WS~X~1"); eq(back.dist, "WHISPER"); eq(world:Find(back.to), king)
		world:Pump()
		eq(#world:Pins(king), 0, "off the King's map")
		eq(world:As(king, king.W.Stats).sightWithdrawn, 2)
		-- Nothing reached anyone since: a second No asks nobody.
		world:As(o, o.consent.set, true)
		world:As(o, o.consent.set, false)
		eq(#world.queue, 0)
	end)
end)

test("wanted sightings: a backup carries the No, and only a No: after a wipe it comes back off and drops what waits at once; a yes in a text is never taken", function()
	-- (Review: a wiped SavedVariables file turned sightings back on, and /oly restore could not
	-- bring the No back.)
	local Bk = ns.Backup
	local saved, savedPrint = ns.db.wantedSightings, ns.Print
	local d
	local ok, err = pcall(function()
		local said = {}
		ns.Print = function(message) said[#said + 1] = message end
		ns.db.wantedSightings = false
		local text = Bk.Export()
		ns.db.wantedSightings = nil -- the wipe
		local back = assert(Bk.Read(text))
		eq(back.settings.wantedSightings, false)
		Bk.Apply(back)
		eq(ns.db.wantedSightings, false, "the No, back")
		eq(said[#said], L.BACKUP_DONE)
		ns.db.wantedSightings = true
		eq(Bk.Data().settings.wantedSightings, nil, "a yes is not written")
		ns.db.wantedSightings = nil
		eq(Bk.Data().settings.wantedSightings, nil, "nor no answer")
		local made = assert(Bk.Read(MadeBackup({ v = 1, char = ns.me, faction = ns.faction, settings = { wantedSightings = true } })))
		eq(made.settings.wantedSightings, nil, "a made text's yes is left out")
		d = assert(Bk.Read(MadeBackup({ v = 1, char = ns.me, faction = ns.faction, settings = { wantedSightings = false } })))
	end)
	ns.db.wantedSightings, ns.Print = saved, savedPrint
	if not ok then error(err, 0) end
	-- A client running Backup.lua with Wanted.lua: the restored No cancels what waits, at once.
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001", { realBackup = true })
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		world:Lease(king)
		world:Choose(o, king)
		assert(world:See(o, "nameplate1", Horde("Grom-Realm", GROM)))
		eq(#world:Waiting(o), 1)
		world:As(o, o.ns.Backup.Apply, d)
		eq(o.db.wantedSightings, false)
		eq(#world:Waiting(o), 0); eq(Dropped(world, "off"), 1)
		eq(#world:Pins(o), 0)
		local seen, why = world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL))
		eq(seen, false); eq(why, "off")
	end)
end)

test("wanted sightings through the real Comm.lua: a sighting waits in its queue under Wanted's own key; the No cancels it there at once; Comm's permit stops one whose No came another way; one let through goes as a whisper to the reviewer", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001", { realComm = true })
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king" })
		local C = o.ns.Comm
		assert(C ~= ns.Comm and C.CancelQueued, "its own Comm")
		-- The King's lease, as that Comm hands it to Wanted.lua.
		assert(world:As(o, o.W.HandleSighting, "CHANNEL", king.name, "WS~R~1"))
		world:Choose(o, king)
		local function Pump() for _ = 1, 3 do world:Advance(2) world:As(o, C.Pump) end end
		local ok, e = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 1)
		eq(C.QueueSize(), 1, "in Comm's own queue")
		world:As(o, o.consent.set, false)
		eq(C.QueueSize(), 0, "cancelled there at once (Comm.CancelQueued, by its key)")
		Pump()
		eq(#world.wire, 0)
		world:As(o, o.consent.set, true)
		ok, e = world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL))
		eq(e.sent, 1)
		o.db.wantedSightings = false
		Pump()
		eq(#world.wire, 0, "Comm's permit, at its turn"); eq(C.QueueSize(), 0)
		o.db.wantedSightings = true -- (the Yes again; 1.2.0: no answer is off)
		ok, e = world:See(o, "nameplate3", Horde("Rexxar-Realm", REXXAR))
		eq(e.sent, 1)
		Pump()
		eq(#world.wire, 1)
		local w = world.wire[1]
		eq(w.dist, "WHISPER"); eq(world:Find(w.target), king)
		eq(w.msg, ("WS~S~1~Olympus II~%s~%d~1429~410~680~0~1.0a000003~Rexxar-Realm"):format(e.id, e.at))
		eq(world:As(o, o.W.Stats).sightSent, 1)
		-- Its No now takes that one back, through the same Comm.
		world:As(o, o.consent.set, false)
		Pump()
		eq(#world.wire, 2); eq(world.wire[2].msg, "WS~X~1"); eq(world:Find(world.wire[2].target), king)
	end)
end)

test("wanted sightings mixed versions: 1.1.4's Comm (what live clients run) ignores the lease, its No, the sighting and taking back", function()
	local saved = rawget(_G, "C_ChatInfo")
	local ok, err = pcall(function()
		local events, login = {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then login[#login + 1] = fn end end
		cns.After, cns.Every = function() end, function() end
		cns.Now = function() return 100000 end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		-- (tests/fixtures/comm-1.1.4.lua: `git show v1.1.4:Olympus/Comm.lua`, unchanged.)
		assert(loadfile(ROOT .. "tests/fixtures/comm-1.1.4.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		-- The types 1.1.4 handles (Wanted is 1.2's: none of them).
		local heard = {}
		for _, kind in ipairs({ "WX", "WY", "W1", "S1", "T1", "L1" }) do
			cns.Comm.Handle(kind, function() heard[#heard + 1] = kind end)
		end
		local function Deliver(dist, sender, text)
			for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, text, dist, sender) end
		end
		Deliver("CHANNEL", "Kingly-Realm", "WS~R~1")
		Deliver("CHANNEL", "Kingly-Realm", "WS~R~0")
		Deliver("WHISPER", "Aldric-Realm", "WS~S~1~Olympus II~0123456789abcdef~1800000000~1429~410~680~0~1.0a000001~Grom-Realm")
		Deliver("WHISPER", "Aldric-Realm", "WS~X~1")
		eq(#heard, 0, "no handler runs")
		local stats = cns.Comm.Stats()
		eq(stats.recv, 4, "heard by the old transport")
		eq(stats.bad, 0, "none misread as a census report")
	end)
	C_ChatInfo = saved
	if not ok then error(err, 0) end
	-- Comm.lua's list of types names the new one (the 1.1 message-type test reads it).
	local f = assert(io.open(ROOT .. "Olympus/Comm.lua"))
	local src = f:read("*a")
	f:close()
	assert(src:find("Wanted WS WX WY", 1, true))
end)

test("wanted sightings (1.2.0): a member who keeps his zone and layer private sends none (his own map still shows them)", function()
	WithSightings(function(world)
		local o = world:Client("Aldric-Realm", "Player-1-AB000001")
		local king = world:Client("Kingly-Realm", "Player-1-AB0000F1", { role = "king", manager = true })
		world:Lease(king)
		world:Choose(o, king)
		o.private = true
		local ok, e = world:See(o, "nameplate1", Horde("Grom-Realm", GROM))
		assert(ok, e); eq(e.sent, 0, "nothing goes while private"); eq(#world:Pins(o), 1, "his own map")
		world:Pump(); eq(#world:Pins(king), 0)
		o.private = nil
		world:Advance(o.W.SIGHT_GAP + 1)
		ok, e = world:See(o, "nameplate2", Horde("Thrall-Realm", THRALL))
		assert(ok, e); eq(e.sent, 1, "sharing again: it goes")
	end)
end)
