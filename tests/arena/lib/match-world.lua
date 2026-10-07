-- 1.2, matchmaking: the test world for matchmaking (the design), composed over the arena's foundation's World
-- (tests/arena/lib/world.lua, frozen): what a client needs besides it to search and be found.
--   * where it stands: UnitPosition (the first value to the north, the second to the west, the
--     continent last, nil in an instance), C_Map's best map, map names, area names and its map
--     position, IsResting and CheckInteractDistance, UnitClass;
--   * the game's side of a match, each spied: C_ChatInfo.SendChatMessage and SendChatMessage
--     (whispers), C_PartyInfo.InviteUnit and C_FriendList.AddIgnore, which fail the test when
--     called outside MW.Click (the harness's click helper: the design, a whisper only inside a click);
--     AcceptGroup, which fails it whenever it is called; LeaveParty (leaves the world's group);
--     the game's popup (StaticPopup_Show / Hide, recorded, and its first frame StaticPopup1
--     shown and hidden with them), UISpecialFrames, and the anchors frames are given;
--   * the shared modules the world does not load per client, as that client's (rawset on its
--     namespace): Layers (sharing as the real one reads it, our layer, the zone's layers), the
--     Roster (the world's guildmates), Hop (its real GroupState, Trusted and Ask as this client's),
--     Data (the census summary), UI (the whisper window, the copy pop-up). Standing.Cap,
--     Debts.SameOwner, the stake checks (Arena.Can's "fights.challenge" and "farkle.create") and
--     the companion's ArenaUI.Challenge, BoneInvite, CreateTable and OpenFind are stand-ins a test
--     sets when it needs them.
-- Every name is invented.
local H = ...
local World = H.World
local MW = {}

-- The package's words, into the harness's L (every client of the world reads that one), before
-- any client loads ArenaMatch.lua (its dialog's buttons are read then).
assert(loadfile(H.ADDON_DIR .. "Locales/ArenaMatchText.lua"))("Olympus", { L = H.ns.L })

MW.MAPS = { [1434] = "Stranglethorn Vale", [1429] = "Elwynn Forest", [1453] = "Stormwind City", [1413] = "The Barrens",
	[1426] = "Dun Morogh", [1444] = "Feralas", [1436] = "Westfall", [1446] = "Tanaris" }
MW.CLASSES = { WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
	PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 } }
-- The places the tests stand at (world positions as UnitPosition gives them).
MW.STV = { cont = 0, mapID = 1434 }

local function Dist(a, b)
	if not a or not b or a.cont ~= b.cont then return nil end
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end
MW.Dist = Dist

-- The game functions a match may only call inside the player's click.
local function Spy(w, c, what, fn)
	return function(...)
		c.calls[#c.calls + 1] = what
		if w.clicking ~= c then
			w.unclicked[#w.unclicked + 1] = c.short .. ": " .. what
			error(what .. " outside a click", 2)
		end
		return fn(...)
	end
end

-- The client's own stand-ins of the shared modules (again after each login: a new namespace).
function MW.Apply(w, c)
	local cns = c.ns
	local function Full(name) return type(name) == "string" and cns.FullName(name) or name end
	rawset(cns, "Layers", {
		-- (As Layers.lua reads it: the King's crown, else the player's answer.)
		Sharing = function()
			local K = cns.King
			if K and K.IsKing and K.IsKing() then return K.SharingLocation() == true end
			return cns.db.shareLocation == true
		end,
		SetSharing = function(on)
			cns.db.shareLocation = on and true or false
			c.sharingSet[#c.sharingSet + 1] = on and true or false
		end,
		Mine = function() return c.layer end,
		ForMap = function(mapID) return c.zoneLayers[mapID] or {} end,
		CurrentMap = function() return c.mapID end,
	})
	rawset(cns, "Roster", setmetatable({
		RankOf = function(name)
			if c.rosterless then return nil end
			local o = w:Find(Full(name))
			if o and o.guild and o.guild == c.guild and not o.notInRoster then return o.rank end
			return nil
		end,
	}, { __index = H.ns.Roster }))
	rawset(cns, "Hop", setmetatable({
		Trusted = function(name) return c.trusted[Full(name)] == true end,
		Ask = function(mapID, zoneUID, label) c.hopAsks[#c.hopAsks + 1] = { mapID = mapID, zoneUID = zoneUID, label = label } end,
	}, { __index = H.ns.Hop }))
	rawset(cns, "Data", setmetatable({
		Summary = function() return c.summary end,
	}, { __index = H.ns.Data }))
	rawset(cns, "UI", setmetatable({
		WhisperWindow = function(name) c.whisperWindow[#c.whisperWindow + 1] = name end,
		-- (The copy pop-up: what it was given.)
		ShowCopy = function(title, text) c.copied[#c.copied + 1] = { title = title, text = text } end,
	}, { __index = H.ns.UI }))
	c.Match = setmetatable({}, { __index = function(_, k)
		local v = cns.ArenaMatch[k]
		if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
		return v
	end, __newindex = function(_, k, v) cns.ArenaMatch[k] = v end })
	-- The draws: random() gives c.draw (0: every chance passes, the shortest answer delay);
	-- random(a, b) gives a + c.qid (an ask's id).
	cns.ArenaMatch.random = function(a, b)
		if a ~= nil then return math.min(b, a + c.qid) end
		return c.draw
	end
	return c
end

-- A client that can search and be found: where = World:Client's, plus pos = { cont, wx, wy },
-- mapID, class ("WARRIOR"), sharing (true by default), findable (the privacy line's yes).
function MW.Client(w, name, where)
	where = where or {}
	w.unclicked = w.unclicked or {}
	local c = w:Client(name, where)
	-- Match scenarios model trained players unless testing the first-game prerequisite.
	if where.bonesTrained ~= false then w:As(c, function() c.ns.FarkleTable.Opts().innkeeperLearned = true end) end
	c.pos = where.pos or { cont = 0, wx = -13000, wy = 300 }
	c.mapID = where.mapID or 1434
	c.mapPos = where.mapPos
	c.classFile = where.class or "WARRIOR"
	c.ignored, c.said, c.invited, c.calls, c.sharingSet, c.hopAsks, c.whisperWindow, c.copied = {}, {}, {}, {}, {}, {}, {}, {}
	c.trusted, c.zoneLayers, c.areaNames = {}, {}, {}
	c.summary = { guilds = {} }
	c.qid, c.draw = 12345, 0
	c.left = 0
	local g = c.globals
	g.UnitPosition = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		if not o or not o.pos or o.instance then return nil end
		return o.pos.wx, o.pos.wy, 0, o.pos.cont
	end
	g.UnitClass = function(unit)
		local o = unit == "player" and c or w:UnitClient(c, unit)
		local cl = o and MW.CLASSES[o.classFile]
		if not cl then return nil end
		return cl[1], o.classFile, cl[2]
	end
	local names = {}
	for file, cl in pairs(MW.CLASSES) do names[file] = cl[1] end
	g.LOCALIZED_CLASS_NAMES_MALE = names
	g.C_Map = {
		GetBestMapForUnit = function(unit) if unit ~= "player" or c.instance then return nil end return c.mapID end,
		GetMapInfo = function(id) local n = MW.MAPS[id] return n and { mapID = id, name = n } or nil end,
		GetAreaInfo = function(id) return c.areaNames[id] end,
		GetPlayerMapPosition = function(mapID)
			if not c.mapPos or mapID ~= c.mapID then return nil end
			local x, y = c.mapPos[1], c.mapPos[2]
			return { GetXY = function() return x, y end }
		end,
	}
	g.C_FriendList = {
		IsIgnored = function(name) return c.ignored[name] == true end,
		AddIgnore = Spy(w, c, "AddIgnore", function(name)
			if c.ignoreFull then return false end
			c.ignored[name] = true
			return true
		end),
	}
	g.C_PartyInfo = {
		InviteUnit = Spy(w, c, "InviteUnit", function(name) c.invited[#c.invited + 1] = name end),
		LeaveParty = function() c.left = c.left + 1 MW.Leave(w, c) end,
	}
	g.C_ChatInfo.SendChatMessage = Spy(w, c, "C_ChatInfo.SendChatMessage", function(text, kind, _, to)
		c.said[#c.said + 1] = { text = text, kind = kind, to = to }
	end)
	g.SendChatMessage = Spy(w, c, "SendChatMessage", function(text, kind, _, to)
		c.said[#c.said + 1] = { text = text, kind = kind, to = to, global = true }
	end)
	g.AcceptGroup = function()
		c.calls[#c.calls + 1] = "AcceptGroup"
		error("AcceptGroup: the addon never accepts an invite")
	end
	g.UnitIsGroupLeader = function(unit)
		local grp = c.groupId and w.groups[c.groupId]
		return grp ~= nil and unit == "player" and grp.members[1] == c
	end
	g.UnitIsGroupAssistant = function() return false end
	g.CheckInteractDistance = function(unit, index)
		local o = w:UnitClient(c, unit)
		local d = o and Dist(c.pos, o.pos)
		return index == 3 and d ~= nil and d <= 10 or false
	end
	g.UISpecialFrames = {}
	-- The world's frames, with what the card reads back: its template, whether a button is
	-- greyed out, a font's size (13 px at least, the owner's rule).
	local make = g.CreateFrame
	local function Font(fs)
		fs.font = { "Fonts\\FRIZQT__.TTF", 12, "" }
		fs.GetFont = function(self) return self.font[1], self.font[2], self.font[3] end
		fs.SetFont = function(self, path, size, flags) self.font = { path, size, flags } end
		fs.SetTextColor = function(self, r, g2, b) self.color = { r, g2, b } end
		return fs
	end
	-- A frame's anchors, as set: { point, relativeTo, relativePoint, x, y } (ClearAllPoints empties).
	local function Anchors(f)
		f.points = {}
		f.SetPoint = function(self, point, rel, relPoint, x, y)
			if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
			self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
		end
		f.ClearAllPoints = function(self) self.points = {} end
		return f
	end
	g.CreateFrame = function(kind, name, parent, template)
		local f = Anchors(make(kind, name, parent))
		f.template = template
		f.SetEnabled = function(self, on) self.enabled = on and true or false end
		f.IsEnabled = function(self) return self.enabled ~= false end
		f.SetHeight = function(self, h) self.height = h end
		f.SetWidth = function(self, wd) self.width = wd end
		f.CreateFontString = function(self) return Font(World.NewFrame("FontString", nil, self)) end
		if kind == "Button" then
			local label = Font(World.NewFrame("FontString", nil, f))
			f.GetFontString = function() return label end
			f.SetText = function(self, t) self.text = t label.text = t end
		end
		-- (1.1.5: ns.Window's metal, Forever's DefaultPanelTemplate: its NineSlice and its title in the
		-- TitleContainer, as the fixture's template keys give them.)
		if template == "DefaultPanelTemplate" then
			rawset(f, "NineSlice", g.CreateFrame("Frame", nil, f))
			local bar = g.CreateFrame("Frame", nil, f)
			rawset(bar, "TitleText", bar:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
			rawset(f, "TitleContainer", bar)
		end
		return f
	end
	g.UIParent = g.UIParent or World.NewFrame("Frame", "UIParent")
	c.shown, c.hidden = {}, {}
	-- The game's first popup frame: shown with StaticPopup_Show, hidden by StaticPopup_Hide or an
	-- answer (MW.Answer), as the game's is.
	g.StaticPopup1 = World.NewFrame("Frame", "StaticPopup1")
	g.StaticPopup1.shown = false
	g.StaticPopup_Show = function(which, a, b, data)
		c.shown[#c.shown + 1] = { which = which, a = a, b = b, data = data }
		g.StaticPopup1.shown = true
		return c.shown[#c.shown]
	end
	g.StaticPopup_Hide = function(which, data)
		c.hidden[#c.hidden + 1] = { which = which, data = data }
		local s = c.shown[#c.shown]
		if s and s.which == which and (data == nil or s.data == data) then g.StaticPopup1.shown = false end
	end
	if where.sharing ~= false then c.db.shareLocation = true end
	MW.Apply(w, c)
	if where.findable then c.Match.SetFindable(true) end
	return c
end

-- A new session for that client (a /reload): its saved data kept where it persists.
function MW.Reload(w, c)
	w:Logout(c)
	w:Login(c)
	return MW.Apply(w, c)
end

-- fn(...) as that client, inside the player's click.
function MW.Click(w, c, fn, ...)
	local was = w.clicking
	w.clicking = c
	local res = { pcall(w.As, w, c, fn, ...) }
	w.clicking = was
	if not res[1] then error(res[2], 0) end
	return unpack(res, 2, table.maxn(res))
end

-- The popup on that client's screen (the last one shown, still up), or nil.
function MW.Popup(c)
	local s = c.shown[#c.shown]
	if not s or s.which ~= "OLYMPUS_ARENA_MATCH" then return nil end
	for _, h in ipairs(c.hidden) do if h.which == s.which and (h.data == nil or h.data == s.data) then return nil end end
	if s.answered then return nil end
	return s
end
-- A click on the popup's button: "yes" (Let's go), "no" (Not now), "block"; or its own timeout.
function MW.Answer(w, c, how)
	local s = assert(MW.Popup(c), c.short .. ": no popup up")
	local def = assert(c.popups.OLYMPUS_ARENA_MATCH, "the dialog's definition")
	s.answered = true
	-- (The game's popup goes on any answer, its own timeout too.)
	if c.globals.StaticPopup1 then c.globals.StaticPopup1.shown = false end
	local self = { data = s.data }
	if how == "timeout" then return w:As(c, def.OnCancel, self, s.data, "timeout") end
	return MW.Click(w, c, function()
		if how == "yes" then return def.OnAccept(self, s.data) end
		if how == "no" then return def.OnCancel(self, s.data, "clicked") end
		if how == "block" then return def.OnAlt(self, s.data, "clicked") end
		error("no such button " .. tostring(how))
	end)
end

-- The card's buttons and rows now (keys shown), and a click on one.
function MW.Card(c)
	local card = c.Match.Card()
	if not card or not card.shown then return nil end
	return card
end
function MW.Buttons(c)
	local card = MW.Card(c)
	local out = {}
	if not card then return out end
	for key, b in pairs(card.buttons) do if b.shown then out[#out + 1] = key end end
	table.sort(out)
	return table.concat(out, " ")
end
function MW.Press(w, c, key)
	local card = assert(MW.Card(c), c.short .. ": no card")
	local b = assert(card.buttons[key], "no button " .. key)
	assert(b.shown, "button " .. key .. " hidden")
	assert(b.enabled ~= false, "button " .. key .. " greyed out")
	return MW.Click(w, c, b.scripts.OnClick, b)
end
function MW.Row(w, c, i)
	local card = assert(MW.Card(c), c.short .. ": no card")
	local r = assert(card.rows[i], "no row " .. i)
	assert(r.shown, "row " .. i .. " hidden")
	return MW.Click(w, c, r.scripts.OnClick, r)
end
function MW.Lines(c)
	local card = MW.Card(c)
	local out = {}
	if not card then return out end
	for _, fs in ipairs(card.lines) do if fs.shown and fs.text ~= "" then out[#out + 1] = fs.text end end
	return out
end
function MW.HasLine(c, text)
	for _, l in ipairs(MW.Lines(c)) do if l == text then return true end end
	return false
end

-- The world's group: that client leaves it (the last two: it is gone).
function MW.Leave(w, c)
	local id = c.groupId
	local grp = id and w.groups[id]
	if not grp then return end
	for i, m in ipairs(grp.members) do if m == c then table.remove(grp.members, i) break end end
	c.groupId = nil
	if #grp.members < 2 then
		for _, m in ipairs(grp.members) do m.groupId = nil end
		w.groups[id] = nil
	end
end

-- The AM messages sent, as "sub~body" (the envelope off), from a client (and to a name).
function MW.AM(w, from, to)
	local out = {}
	for _, s in ipairs(w:Sent{ from = from, type = "AM" }) do
		if not to or (s.target or ""):lower() == to:lower() then out[#out + 1] = s.msg:sub(7) end
	end
	return out
end
function MW.Last(w, from, sub)
	local list = MW.AM(w, from)
	for i = #list, 1, -1 do if list[i]:sub(1, 2) == sub .. "~" then return list[i] end end
	return nil
end

-- No handler, timer or event of any client raised, and nothing the click rule forbids happened.
function MW.NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
		-- (A stake check's stand-in called in a shape its package does not take: tests/arena/match.lua.)
		for _, e in ipairs(c.badChecks or {}) do error(c.name .. ": " .. e, 2) end
	end
	if w.unclicked and w.unclicked[1] then error("outside a click: " .. table.concat(w.unclicked, ", "), 2) end
end

return MW
