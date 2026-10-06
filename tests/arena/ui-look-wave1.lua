-- Wave 1's companion-only presentation contracts. Every assertion exercises the loaded addon;
-- central chat/game modules are stubbed only at their published adapter boundary.
local H = ...
local test, eq, World = H.test, H.eq, H.World
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local function BonesReady(w, c)
	FW.Extend(w, c)
	w:Stand(c.name, FW.INN, true)
	-- These presentation scenarios are returning players, not the first innkeeper lesson.
	w:As(c, function()
		c.ns.FarkleTable.Opts().innkeeperLearned = true
		assert(c.ns.FarkleTable.CanOpen() and c.ns.FarkleTable.TrainingComplete())
	end)
end

local function Keys(entries)
	local out = {}
	for _, entry in ipairs(entries or {}) do out[#out + 1] = entry.key end
	return table.concat(out, ",")
end

test("1.2 profile polish: Kit.RoundPortrait keeps one guarded circular mask (the bracket's small plaques)", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Kit = own.ArenaUI.Kit
	local made, added = 0, 0
	local mask = {
		SetAllPoints = function(self, target) self.target = target end,
		SetTexture = function(self, file, horizontal, vertical) self.file, self.horizontal, self.vertical = file, horizontal, vertical end,
	}
	local parent = { CreateMaskTexture = function() made = made + 1 return mask end }
	local tex = {
		GetParent = function() return parent end,
		AddMaskTexture = function(_, value) added = added + 1 eq(value, mask) end,
	}
	eq(Kit.RoundPortrait(tex), true)
	eq(Kit.RoundPortrait(tex), true, "idempotent")
	eq(made, 1); eq(added, 1); eq(mask.target, tex); eq(mask.file, Kit.PORTRAIT_MASK)
	local fallback
	eq(Kit.RoundPortrait({ SetMask = function(_, file) fallback = file end }), true)
	eq(fallback, Kit.PORTRAIT_MASK, "older clients use Texture:SetMask")
end)

-- The owner's ask (1.2, test build 33): the Arena's portraits looked nothing like the player's own
-- on his unit frame (a crop of the classic UI-TargetingFrame and a rank ring 1.55 times the
-- portrait, centred). They are Borders.NewPortrait's now: the same copy of his frame's portrait,
-- mask and ring, and the very rig of Olympus art Borders puts round his own portrait.
test("1.2 profile polish: an arena portrait is the player's own portrait again (Borders.NewPortrait): his frame's rig, a name's tier or verified honour on it, his own picture square from SetPortraitTexture", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	-- Borders.lua as the game loads it (the test world keeps Core.lua's stand-in otherwise).
	w:As(a, function()
		rawset(a.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", a.ns)
	end)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Kit, Data, Card, B = own.ArenaUI, own.ArenaUI.Kit, own.ArenaUI.Data, own.ArenaUI.Card, a.ns.Borders
	local pictures = {}
	local saved = { verified = Data.Verified, mark = B.MarkOfName, event = Data.Event, profile = Data.Profile, markets = Data.Markets }
	a.globals.SetPortraitTexture = function(tex, unit, disableMasking) pictures[#pictures + 1] = { tex = tex, unit = unit, square = disableMasking } end
	local ok, err = pcall(w.As, w, a, function()
		local rig = Kit.NewPortrait(CreateFrame("Frame"), 64)
		assert(rig.container and rig.box and rig.underlay and not rig.plain, "Borders.NewPortrait's rig, not a drawing of the Arena's own")
		for _, t in ipairs(B.TIERS) do assert(rig.tex[t.name], t.name .. "'s art on it, as round the player's own portrait") end
		-- A guild master (the trust rules of the marks by his name): 1.1.5's bronze wings, alone, over its metal.
		Data.Verified = function() return { frame = "rank" } end
		B.MarkOfName = function(name, guild)
			eq(name, "Parric Stowe"); eq(guild, "Olympus Ember")
			return "silver", { who = name, guild = guild, olympus = true, leader = true }
		end
		local framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember")
		eq(framed.kind, "rank"); eq(framed.key, "bronze-elite")
		eq(rig.shown, "bronze-elite"); eq(rig.shownTex, rig.tex["bronze-elite"]); eq(rig.tex["bronze-elite"].shown, true); eq(rig.underlay.shown, true)
		for name, tex in pairs(rig.tex) do if name ~= "bronze-elite" then eq(tex.shown, false, name .. " hidden") end end
		-- His verified honour: its frame on the rig's own texture for its shape.
		Data.Verified = function() return { frame = "arena-champion" } end
		framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember")
		eq(framed.kind, "honour"); eq(framed.key, "arena-champion"); eq(rig.shown, "arena-champion")
		eq(rig.honor.winged.texture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold"); eq(rig.honor.winged.shown, true)
		eq(rig.tex["bronze-elite"].shown, false)
		-- The podium's spelling of a first place ("arena-champion-1"): the same honour.
		Data.Verified = function() return { frame = "rank" } end
		framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember", "arena-champion-1")
		eq(framed.kind, "honour"); eq(framed.key, "arena-champion")
		-- A verified honour this client has no art for: his rank's tier, as on a unit frame.
		Data.Verified = function() return { frame = "no-such-honour" } end
		framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember")
		eq(framed.kind, "rank"); eq(framed.key, "bronze-elite"); eq(rig.shown, "bronze-elite"); eq(rig.honor.winged.shown, false)
		-- "none": no frame at all.
		Data.Verified = function() return { frame = "none" } end
		framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember")
		eq(framed.kind, nil); eq(rig.shown, nil); eq(rig.tex["bronze-elite"].shown, false); eq(rig.underlay.shown, false)
		-- The author's border preview (/oly borders test) on his own, as round his own portrait.
		Data.Verified = function() return { frame = "rank" } end
		local W = a.ns.Workshop
		local visible = W.Visible
		W.Visible = function() return true end
		B.SetPreview("gold-elite")
		framed = Kit.SetPortraitFrame(rig, "Lida Fenn", "Olympus Ember")
		eq(framed.kind, "rank"); eq(framed.key, "gold-elite"); eq(rig.shown, "gold-elite")
		framed = Kit.SetPortraitFrame(rig, "Parric Stowe", "Olympus Ember")
		eq(framed.key, "bronze-elite", "anyone else's: his own")
		-- ...but never as others see him (his preview is his screen's alone): "Preview as others see
		-- me" shows his own frame (none: he holds no rank).
		local lord = B.MarkOfName
		B.MarkOfName = function(name, guild) return nil, { who = name, guild = guild } end
		framed = Kit.SetPortraitFrame(rig, "Lida Fenn", "Olympus Ember", nil, true)
		eq(framed.key, nil, "as others see him: no preview"); eq(rig.shown, nil)
		local seen = UI.PreviewMe()
		assert(seen.rig and seen.rig.container and not seen.rig.plain, "the preview's portrait is Borders'")
		eq(seen.rig.shown, nil, "the Arena's 'Preview as others see me': no preview either")
		B.MarkOfName = lord
		B.SetPreview("off")
		W.Visible = visible
		-- His own portrait: the live one ("player"), square as his unit frame asks for it, on the
		-- rig's portrait (its mask makes it round).
		local kind = Kit.DrawPortrait(rig, "Lida Fenn", { class = "MAGE" })
		eq(kind, "live"); eq(pictures[#pictures].unit, "player"); eq(pictures[#pictures].square, true); eq(pictures[#pictures].tex, rig.portrait)
		-- The screens draw theirs so: the tale of the tape (each side's square placed, its rig sized)...
		local V = function(v, src) return { v = v, src = src } end
		Data.Event = function(id) return id == "Fown" and { id = id, kind = "fight", A = "Lida Fenn", B = "Wenna Crale", state = "O", mode = "L" } or nil end
		Data.Profile = function(name)
			if name == "Wenna Crale" then return { name = V(name, "own"), class = V("MAGE", "own") } end
			return { name = V(name, "own"), class = V("PRIEST", "own") }
		end
		Data.Markets = function() return nil end
		local frame = CreateFrame("Frame")
		assert(Card.Build(frame, "Fown", "window"), "the card")
		local c = rawget(frame, "arenaCard")
		for _, side in ipairs({ c.A, c.B }) do
			assert(side.rig and side.rig.container and not side.rig.plain, "a side's portrait is Borders'")
			eq(side.portrait, side.rig.slot, "the square the card places")
			eq(side.rig.size, 72, "the tale's portraits, 72 across")
		end
		-- (his side live, square; hers a token: nobody shows her here)
		eq(pictures[#pictures].tex, c.A.rig.portrait); eq(pictures[#pictures].unit, "player"); eq(pictures[#pictures].square, true)
		-- ...and the Profile (his own: the live portrait).
		local canvas = CreateFrame("Frame")
		UI.Pane("arena.profile").detail(canvas, { key = "arena.profile" })
		local p = rawget(canvas, "profile")
		assert(p.rig and p.rig.container and not p.rig.plain, "the Profile's portrait is Borders'")
		eq(p.portrait, p.rig.slot); eq(p.rig.size, 96)
		eq(pictures[#pictures].tex, p.rig.portrait); eq(pictures[#pictures].unit, "player"); eq(pictures[#pictures].square, true)
	end)
	Data.Verified, B.MarkOfName, Data.Event, Data.Profile, Data.Markets = saved.verified, saved.mark, saved.event, saved.profile, saved.markets
	if not ok then error(err, 0) end
end)

-- The review of the portraits (1.2): "Preview as others see me" drew his own live portrait (his
-- "player" unit, first in Card.Tokens), never the emblem a viewer who has him as no unit sees; and
-- an Arena already open kept the author's old border preview (or none) until something redrew it,
-- while his unit frame changed at once.
test("1.2 profile polish: 'Preview as others see me' shows his emblem as viewers do, never his live portrait; his Arena portraits follow his border preview at once, as his unit frame", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	w:As(a, function()
		rawset(a.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", a.ns)
	end)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Kit, Data, B, W = own.ArenaUI, own.ArenaUI.Kit, own.ArenaUI.Data, a.ns.Borders, a.ns.Workshop
	local pictures = {}
	a.globals.SetPortraitTexture = function(tex, unit, disableMasking) pictures[#pictures + 1] = { tex = tex, unit = unit, square = disableMasking } end
	local saved = { verified = Data.Verified, mark = B.MarkOfName, pe = rawget(a.ns, "ProfileEdit"), visible = W.Visible }
	local ok, err = pcall(w.As, w, a, function()
		Data.Verified = function() return { frame = "rank" } end
		-- (he holds no rank; Parric Stowe is a Lord: the gold tier)
		B.MarkOfName = function(name, guild)
			if name == "Parric Stowe" then return "silver", { who = name, guild = guild, olympus = true, leader = true } end
			return nil, { who = name, guild = guild }
		end
		-- His emblem picked in the profile's Edit: the preview shows it, as a viewer without him as a
		-- unit of his own sees it, and asks no live portrait for it (his own would be "player").
		a.ns.ProfileEdit = { Preview = function() return { emblem = "INV_Misc_Head_Dragon_01" } end }
		local seen = UI.PreviewMe()
		eq(seen.rig.portrait.texture, "Interface\\Icons\\INV_Misc_Head_Dragon_01", "his emblem, as others see him")
		for _, p in ipairs(pictures) do assert(p.tex ~= seen.rig.portrait, "no live portrait (" .. tostring(p.unit) .. ") as others see him") end
		-- His own portraits elsewhere stay live, as on his unit frame.
		local rig, other = Kit.NewPortrait(CreateFrame("Frame"), 64), Kit.NewPortrait(CreateFrame("Frame"), 64)
		eq(Kit.DrawPortrait(rig, "Lida Fenn", { class = "MAGE", guild = "Olympus Ember" }), "live")
		eq(pictures[#pictures].tex, rig.portrait); eq(pictures[#pictures].unit, "player")
		Kit.DrawPortrait(other, "Parric Stowe", { class = "WARRIOR", guild = "Olympus Ember" })
		eq(rig.shown, nil, "his own frame: none"); eq(other.shown, "bronze-elite")
		-- His border preview: on his portraits already drawn at once, as round his unit frame's (the
		-- Borders tests), nothing redrawn by the screen; never on anyone else's, nor "as others see me".
		W.Visible = function() return true end
		B.SetPreview("bronze-elite")
		eq(rig.shown, "bronze-elite", "his Arena portrait already drawn, at once"); eq(rig.tex["bronze-elite"].shown, true)
		eq(other.shown, "bronze-elite", "anyone else's: his own"); eq(seen.rig.shown, nil, "as others see him: never")
		B.SetPreview("gold-elite")
		eq(rig.shown, "gold-elite"); eq(rig.tex["bronze-elite"].shown, false)
		-- Borders off: none round his unit frame, so none here (the two always match), and back on.
		B.SetEnabled(false)
		eq(rig.shown, nil, "borders off: no preview on his Arena portrait either")
		eq(other.shown, "bronze-elite", "anyone else's Arena portrait as before")
		B.SetEnabled(true)
		eq(rig.shown, "gold-elite")
		B.SetPreview("off")
		eq(rig.shown, nil, "off: his own frame again, at once"); eq(other.shown, "bronze-elite")
	end)
	Data.Verified, B.MarkOfName, a.ns.ProfileEdit, W.Visible = saved.verified, saved.mark, saved.pe, saved.visible
	if not ok then error(err, 0) end
end)

test("1.2 profile polish: the tale of the tape keeps the full real-field comparison", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local Card = own.ArenaUI.Card
	local fighter = { title = "Champion", titleSrc = "verified", class = "WARRIOR", classSrc = "seen", level = 60,
		levelSrc = "seen", race = 2, raceSrc = "seen", record = "14-5", recordSrc = "ledger", last5 = "W W L W W",
		ko = 64, avgDur = 91, tier = "gold", odds = 1.75, pool = 320000, count = 18,
		rating = 1612, ratingSrc = "ledger", peak = 1700, fled = 2, streak = 3, guildRank = "Knight", guildRankSrc = "seen" }
	-- The owner's UFC card (2026-10-04): the rating with its peak, the duels he fled, his streak and his
	-- guild rank too, on the Tale of the tape and the overlay alike.
	for _, size in ipairs({ "window", "overlay" }) do
		local rows = w:As(a, function() return Card.Rows(fighter, "g", size) end)
		local found = {}
		for _, row in ipairs(rows) do found[row.label] = row.value end
		for _, key in ipairs({ "title", "rank", "class", "race", "rating", "record", "fled", "streak", "last5", "ko", "dur", "tier", "odds" }) do
			assert(found[key] ~= nil, size .. ": missing real tale-of-the-tape field " .. key)
		end
		eq(found.rank, "Knight", size)
		assert(found.rating:find("1612", 1, true) and found.rating:find("1700", 1, true), size .. " rating: " .. found.rating)
		eq(found.fled, "2", size)
		assert(found.streak:find("W3", 1, true), size .. " streak: " .. found.streak)
	end
	-- A losing streak reads as defeats; at his peak the rating stands alone; no fled duel, no row.
	local rows = w:As(a, function()
		return Card.Rows({ class = "WARRIOR", record = "3-4", rating = 1480, peak = 1480, fled = 0, streak = -2 }, "g", "window")
	end)
	local found = {}
	for _, row in ipairs(rows) do found[row.label] = row.value end
	eq(found.rating, "1480"); eq(found.fled, nil)
	assert(found.streak:find("L2", 1, true), found.streak)
	-- The event pane's compact card keeps its three facts.
	local compact = w:As(a, function() return Card.Rows(fighter, "g", "compact") end)
	for _, row in ipairs(compact) do
		assert(row.label ~= "rating" and row.label ~= "rank" and row.label ~= "fled" and row.label ~= "streak", "compact: " .. row.label)
	end
end)

-- The Tale of the tape put each side's rows under the labels of whichever side had more, so a
-- fighter without a title (or a rank) showed his class on the Title line. Each value now sits on
-- its own label's line, the missing one a dash.
test("1.2 the tale of the tape: each side's value sits on its own label's line when only one fighter has a title or a rank", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	local Card, Data = UI.Card, UI.Data
	local L = a.ns.L
	local saved = { event = Data.Event, profile = Data.Profile, markets = Data.Markets }
	local function V(v, src) return { v = v, src = src } end
	local profiles = {
		["Parric Stowe"] = { name = V("Parric Stowe", "own"), title = V("Champion", "verified"), guildRank = V("Knight", "seen"), class = V("WARRIOR", "own"),
			level = V(60, "own"), race = V(2, "own"), rating = V(1650, "ledger"), record = V({ wins = 9, losses = 2, fled = 1, streak = 4 }, "ledger") },
		["Wenna Crale"] = { name = V("Wenna Crale", "own"), class = V("MAGE", "own"), level = V(58, "own"), race = V(1, "own"),
			rating = V(1490, "ledger"), record = V({ wins = 4, losses = 5, fled = 0, streak = -1 }, "ledger") },
	}
	Data.Event = function(id) return id == "Ftape1" and { id = id, kind = "fight", A = "Parric Stowe", B = "Wenna Crale", state = "O", mode = "L" } or nil end
	Data.Profile = function(name) return profiles[name] end
	Data.Markets = function() return nil end
	local ok, err = pcall(w.As, w, a, function()
		local frame = CreateFrame("Frame")
		local m = Card.Build(frame, "Ftape1", "window")
		assert(m and m.A and m.B, "the card's model")
		local c = rawget(frame, "arenaCard")
		local function Line(label)
			for i, fs in ipairs(c.labels) do if fs:GetText() == label then return i end end
			return nil
		end
		local title, rank, class = Line(L.ARENA_CARD_TITLE_ROW), Line(L.ARENA_CARD_GUILD_RANK), Line(L.ARENA_CARD_CLASS)
		assert(title and rank and class, "the labels: title, rank, class")
		assert(c.A.values[title]:GetText():find("Champion", 1, true), c.A.values[title]:GetText())
		eq(UI.Kit.Plain(c.B.values[title]:GetText()), "-", "no title: a dash on the Title line")
		assert(c.A.values[rank]:GetText():find("Knight", 1, true), c.A.values[rank]:GetText())
		assert(c.B.values[class]:GetText():find("58", 1, true), "her class and level on the Class line: " .. c.B.values[class]:GetText())
		assert(c.A.values[class]:GetText():find("60", 1, true), c.A.values[class]:GetText())
		local fled, streak = Line(L.ARENA_CARD_FLED), Line(L.ARENA_PROF_STREAK)
		assert(fled and streak, "the fled and streak lines")
		eq(c.A.values[fled]:GetText(), "1")
		assert(c.B.values[streak]:GetText():find("L1", 1, true), c.B.values[streak]:GetText())
		-- Both columns as long as the labels: a value on every labelled line.
		for i, fs in ipairs(c.labels) do
			if fs:GetText() ~= "" then assert(c.A.values[i]:GetText() ~= "" and c.B.values[i]:GetText() ~= "", "line " .. i .. " has both sides") end
		end
	end)
	Data.Event, Data.Profile, Data.Markets = saved.event, saved.profile, saved.markets
	if not ok then error(err, 0) end
end)

test("1.2 UI: fight chat is a stable-id deep link to the main Chat page, never an embedded frame", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local seen
	a.ns.Arena.ChatRoom = function(id) return { key = "arena:" .. id, id = id, kind = "fight", audience = "duel" } end
	a.ns.Arena.OpenChatRoom = function(id) seen = id return true end
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	local spec = UI.FightChatRoom("F42")
	eq(spec.key, "arena:F42"); eq(spec.id, "F42"); eq(spec.audience, "duel")
	eq(UI.OpenFightChat("F42"), true); eq(seen, "F42")
	eq(UI.ChatPanel.Open("F43"), true); eq(seen, "F43")
	eq(UI.ChatPanel.Frame(), nil, "no companion chat surface")
	eq(UI.OpenFightChat(""), false, "no unstable/empty id"); eq(UI.ChatPanel.Room(), nil)
	a.ns.Arena.OpenChatRoom = function(id)
		if id == "F44" then return false, { key = "arena:F44", id = id } end
		return false, nil
	end
	local opened, fallback = UI.OpenFightChat("F44")
	eq(opened, false); eq(fallback.key, "arena:F44"); eq(UI.ChatPanel.Room(), "F44")
	eq(UI.OpenFightChat("unknown"), false); eq(UI.ChatPanel.Room(), nil)
end)

test("1.2 profile polish: fight history lives inside Profile and has no second pane or top-level tab", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Data, L = own.ArenaUI, own.ArenaUI.Data, a.ns.L
	eq(UI.Pane("arena.history"), nil, "there is no hidden/legacy third profile surface")
	assert(not Keys(UI.SectionPanes("arena")):find("arena.history", 1, true), Keys(UI.SectionPanes("arena")))
	assert(Keys(UI.SectionPanes("arena")):find("arena.profile", 1, true), Keys(UI.SectionPanes("arena")))
	local oldProfile, oldMine, oldHistory = Data.Profile, Data.MyProfile, Data.History
	local scopes = {}
	Data.Profile = function() return { name = a.name, pub = true } end
	Data.MyProfile = function() return { pub = true } end
	Data.History = function(filter)
		scopes[#scopes + 1] = filter and filter.mine
		return { { fid = "F1", t = 1000, A = a.name, B = "Parric Stowe", opponent = "Parric Stowe", winner = a.name, won = true, dur = 72 } }
	end
	local lines = UI.Pane("arena.profile").lines({ key = "arena.profile" })
	local historyHeader, fightRow, contradicted
	for _, line in ipairs(lines) do
		if line.header and tostring(line.text or ""):find(L.ARENA_HISTORY_TITLE, 1, true) then historyHeader = line end
		if not line.header and tostring(line.text or ""):find(L.ARENA_WON, 1, true) then fightRow = line break end
		if tostring(line.text or ""):find(L.ARENA_PROF_NO_FIGHTS, 1, true) then contradicted = true end
	end
	assert(historyHeader and historyHeader.onClick, "History is a visible, interactive section inside Profile")
	assert(fightRow and tostring(fightRow.text):find("Parric", 1, true), "the recent fight is in Profile")
	assert(fightRow.onClick, "a Profile history row opens that fight's details")
	fightRow.onClick()
	local selected = UI.Selected("arena.profile.history")
	eq(selected.fid, "F1"); eq(selected.profile, a.name)
	historyHeader.onClick()
	UI.Pane("arena.profile").lines({ key = "arena.profile" })
	eq(scopes[#scopes], false, "History's in-Profile control changes from mine to recent public fights")
	eq(contradicted, nil, "real history never appears beside the no-fights empty state")
	Data.Profile, Data.MyProfile, Data.History = oldProfile, oldMine, oldHistory
end)

test("1.2 profile polish: Arena and normal profiles keep canonical independent routes and Back returns to the ranking", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI = own.ArenaUI
	UI.ShowPane("arena.rankings", "rank-row-7")
	UI.ShowProfile("  Parric Stowe  ")
	eq(UI.state.pane.arena, "arena.profile")
	eq(UI.Selected("arena.profile"), "Parric Stowe-Emberfall", "Arena stores a canonical full identity")

	-- The normal Olympus page delegates only to its own full-window router and does not alter the
	-- Arena route or consume its Back destination.
	local oldNormalUI, normalCalls = a.ns.UI, 0
	a.ns.UI = { OpenPlayerProfile = function(person)
		normalCalls = normalCalls + 1
		eq(person.name, "Parric Stowe")
		return "normal-page"
	end }
	eq(a.ns.PlayerProfile.Open({ name = "Parric Stowe" }), "normal-page")
	eq(normalCalls, 1); eq(UI.state.pane.arena, "arena.profile")
	a.ns.UI = oldNormalUI

	local buttons = UI.Pane("arena.profile").buttons({ key = "arena.profile", sel = UI.Selected("arena.profile") })
	eq(buttons[2][1], a.ns.L.ARENA_BACK)
	eq(buttons[2][2](), true)
	eq(UI.state.pane.arena, "arena.rankings")
	eq(UI.Selected("arena.rankings"), "rank-row-7", "Back restores the ranking and its selected row")

	UI.ShowProfile(a.short)
	eq(UI.state.pane.arena, "arena.profile")
	eq(UI.Selected("arena.profile"), false, "the player's canonical identity opens their own Arena Profile")
end)

test("1.2 profile polish: Arena and tale windows fit a smaller viewport and refit after display changes", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	a.K = BoardUI.New(function() return w.clock end, { screen = { 640, 480 } })
	a.K.Install(a.globals)
	-- Window.lua's list only needs ScrollFrame's ordinary frame geometry in this focused stand-in;
	-- its optional scroll-child method is already feature-detected by Kit.List.
	local createFrame = a.globals.CreateFrame
	a.globals.CreateFrame = function(kind, ...)
		local frame = createFrame(kind == "ScrollFrame" and "Frame" or kind, ...)
		if kind == "Button" then frame.SetHighlightTexture = function() end end
		return frame
	end
	a.db.arenaRules = { yes = true }
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:As(a, function()
		local UI, Kit, Card = own.ArenaUI, own.ArenaUI.Kit, own.ArenaUI.Card
		local function close(aValue, bValue, label)
			assert(math.abs(aValue - bValue) < 0.000001, (label or "values") .. ": " .. aValue .. " ~= " .. bValue)
		end
		local main = UI.Open("rankings")
		local mainScale = Kit.WindowScale(UI.W, UI.H, 1, 640, 480)
		close(main:GetScale(), mainScale, "Arena scale")
		assert(UI.W * mainScale <= 640 - Kit.WINDOW_MARGIN * 2 + 0.001)
		assert(UI.H * mainScale <= 480 - Kit.WINDOW_MARGIN * 2 + 0.001)

		local tale = Card.Open("no-sample-event")
		-- (The tale window's own size: 660 x 580 since the fuller card, 2026-10-04.)
		local TW, TH = Card.WINDOW_W, Card.WINDOW_H
		eq(TW, 660); eq(TH, 580)
		local taleScale = Kit.WindowScale(TW, TH, 1, 640, 480)
		close(tale:GetScale(), taleScale, "tale scale")
		assert(TW * taleScale <= 640 - Kit.WINDOW_MARGIN * 2 + 0.001)
		assert(TH * taleScale <= 480 - Kit.WINDOW_MARGIN * 2 + 0.001)
		eq(UI.lastCard, nil, "responsive empty state does not invent a fight")

		a.K.screen[1], a.K.screen[2] = 800, 600
		w:Fire(a, "DISPLAY_SIZE_CHANGED")
		close(main:GetScale(), Kit.WindowScale(UI.W, UI.H, 1, 800, 600), "refitted Arena scale")
		close(tale:GetScale(), Kit.WindowScale(TW, TH, 1, 800, 600), "refitted tale scale")
		assert(tale:GetScale() > taleScale, "the larger screen fits it larger")
	end)
end)

test("1.2 UI: a partial profile identity never puts nil into its class-race-level line", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Data = own.ArenaUI, own.ArenaUI.Data
	local old = Data.Profile
	for _, partial in ipairs({ { class = "WARRIOR" }, { race = 2 }, { level = 60 } }) do
		Data.Profile = function() return { name = "Parric Stowe", class = partial.class, race = partial.race, level = partial.level } end
		local ok, model = pcall(UI.ProfileModel, "Parric Stowe")
		assert(ok and model and #model.lines == 1, "partial identity must render one safe line")
	end
	Data.Profile = old
end)

test("1.2 UI: Bones has a real landing/history/practice presentation and live board controls", function()
	local w = FW.New()
	local a = w:Client("Lida Fenn")
	BonesReady(w, a)
	-- The real game has its own border without a title strip; exercise the live frame rather
	-- than the world's data-only frame stub.
	a.K = BoardUI.New(function() return w.clock end, { screen = { 1280, 960 } })
	a.K.Install(a.globals)
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, L = own.ArenaUI, a.ns.L
	eq(Keys(UI.SectionPanes("farkle")), "bone.play,bone.live,bone.history")
	eq(UI.BoneAvailable(), true, "the production companion supplies the Bone Throw board")
	-- Eligibility reads real client position/rest APIs; evaluate in this client's context.
	local buttons = w:As(a, function() return UI.Pane("bone.play").buttons({ key = "bone.play" }) end)
	eq(buttons[2][1], L.ARENA_BONE_NEW); eq(buttons[2].enabled, true)
	-- (1.2.0, the owner's call: no Practice button; practice is the innkeeper's.)
	eq(buttons[3][1], L.ARENA_PANE_BONE_HISTORY)
	buttons[3][2](); eq(UI.state.pane.farkle, "bone.history")
	-- Rules can be read without starting a practice game. Training begins with an innkeeper;
	-- the old local lab cannot replace this stateful multiplayer surface.
	w:As(a, function() UI.BoneBoard("guide") end)
	local parts = UI.FarkleBoard and UI.FarkleBoard._.parts() or {}
	assert(parts.help and parts.help:IsShown(), "How to play opens the actual Bones guide")
	eq(a.ns.FarkleTable.Live(), nil, "reading the rules starts no game")
	eq(UI.OpenGame("farkle"), false)
end)

test("1.2 UI: Lottery exposes its real board, History and local Practice without sample data", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, L = own.ArenaUI, a.ns.L
	eq(Keys(UI.SectionPanes("lottery")), "lottery,lottery.history,lottery.practice")
	local pane = UI.Pane("lottery")
	assert(pane and pane.build and pane.refresh, "the unified production board owns the Lottery section")
	local empty = UI.LotteryModel()
	eq(empty.state, "none", "a normal client gets an honest empty state")
	eq(#empty.cards, 25); eq(#empty.rows, 5); eq(empty.bet.can, false)
	eq(empty.instructions, L.LOTTERY_BOARD_RULES, "the live table carries the concise real betting rule")

	local bets = {}
	for i = 1, 25 do bets[i] = { pool = 0, count = 0 } end
	local drawn = UI.LotteryModel({ eid = "L42", state = "settled", drawAt = w.clock - 30,
		cur = "g", pot = 420000, carry = 0, bets = bets, mine = {}, prizes = { 1, 5, 9, 13, 17 } })
	eq(drawn.banner.sub, L.LOTTERY_FIVE_PLACE_SUMMARY)
	for i = 1, 5 do eq(drawn.rows[i].number, a.ns.Lottery.Text(drawn.slip.day.prizes[i])) end
	eq(#drawn.cards[1].positions, 1); eq(drawn.cards[1].positions[1], 1)
	-- Lottery's production route is the pane above; the made-up local lab stays test-only.
	eq(UI.OpenGame("lottery"), false)
end)

test("1.2 UI: Lottery History puts today's real tickets first, then known prior results, and opens the canonical Wallet", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Lt, L = own.ArenaUI, a.ns.Lottery, a.ns.L
	local oldToday, oldDays, oldDay, oldHistory, oldOffset = Lt.Today, Lt.Days, Lt.Day, Lt.History, Lt.RealmOffset
	local oldDate, dateCalls = date, {}
	Lt.RealmOffset = function(now)
		eq(now, nil, "history asks for the current realm offset, not one inferred from an old draw")
		return 180
	end
	date = function(format, at) dateCalls[#dateCalls + 1] = { format, at }; return "realm:" .. tostring(at) end
	Lt.Today = function() return { eid = "L3", state = "open", drawAt = w.clock + 300, cur = "g", mine = {
		{ o = 2, s = 10000, state = "accepted" }, { o = 7, s = 20000, state = "accepted" },
	} } end
	Lt.Days = function() return {
		{ eid = "L0", lockAt = w.clock - 259200 }, { eid = "L1", lockAt = w.clock - 172800 },
		{ eid = "L2", lockAt = w.clock - 86400 }, { eid = "L3", lockAt = w.clock + 300 },
	} end
	Lt.History = function() return { { eid = "L0", lockAt = w.clock - 259200, cur = "g", prizes = { 41, 45, 49, 53, 57 } } } end
	Lt.Day = function(eid)
		if eid == "L0" then return nil end
		if eid == "L2" then return { eid = eid, state = "settled", drawAt = w.clock - 86400, cur = "g",
			prizes = { 1, 5, 9, 13, 17 }, mine = {
				{ o = 2, s = 10000, payout = 24000 },
				{ o = 3, s = 10000, state = "settled" },
			} } end
		return { eid = eid, state = "settled", drawAt = w.clock - 172800, cur = "g",
			prizes = { 21, 25, 29, 33, 37 }, mine = {} }
	end
	local ok, err = pcall(function()
		local model = UI.LotteryHistoryModel()
		eq(model.today.eid, "L3"); eq(#model.today.tickets, 2)
		eq(model.today.when, "realm:" .. tostring(w.clock + 300 + 180 * 60))
		eq(dateCalls[1][1], "!%d %b %H:%M", "history formats the shifted realm clock through UTC")
		eq(model.rows[1].kind, "today"); eq(model.rows[2].kind, "today", "all of today's tickets precede old days")
		eq(model.prior[1].eid, "L2", "prior draws are newest first"); eq(model.rows[3].kind, "prior")
		eq(model.prior[3].eid, "L0"); eq(model.prior[3].result, Lt.PrizesText({ 41, 45, 49, 53, 57 }),
			"the caller's bounded saved result remains visible when its public market was evicted")
		eq(model.prior[1].tickets[1].status, L.LOTTERY_HISTORY_PAID:format(Lt.Money(24000, "g")))
		eq(model.prior[1].tickets[2].status, L.LOTTERY_HISTORY_PENDING,
			"a settled ticket whose payout cannot yet be computed is not falsely called a loss")
		local lines = UI.Pane("lottery.history").lines({ key = "lottery.history" })
		local todayAt, priorAt, ticketAt
		for i, line in ipairs(lines) do
			if line.header and line.text == L.LOTTERY_HISTORY_TODAY then todayAt = i end
			if line.header and line.text == L.LOTTERY_HISTORY_PREVIOUS then priorAt = i end
			if not line.header and tostring(line.text):find(Lt.Label(2), 1, true) then ticketAt = ticketAt or i end
		end
		assert(todayAt and ticketAt and priorAt and todayAt < ticketAt and ticketAt < priorAt, "today's tickets render before prior results")

		local selected
		local oldUI = a.ns.UI
		a.ns.UI = { SelectTab = function(key) selected = key end }
		eq(UI.LotteryOpenWallet(), true)
		a.ns.UI = oldUI
		eq(a.ns.Treasury.mode, "wallet"); eq(selected, "treasury", "History routes to the canonical main-window Wallet")
	end)
	Lt.Today, Lt.Days, Lt.Day, Lt.History, Lt.RealmOffset, date = oldToday, oldDays, oldDay, oldHistory, oldOffset, oldDate
	if not ok then error(err, 0) end
end)

-- (1.1.6: a practice ticket is free, so no stake is chosen any more, and each draw is a game of the
-- games' ledger, ArenaLedger.Played: the player's own list, and a whisper to the auditors heard,
-- none here; still no Arena.Do, no market, no message without an auditor, nothing in ns.db.)
test("1.2 UI: Lottery Practice requires a choice and simulates five local rolls with no production side effect", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	local UI, Lt = own.ArenaUI, a.ns.Lottery
	local oldDo, oldBet, oldSend = a.ns.Arena.Do, a.ns.Markets.Bet, a.ns.Arena.Send
	local calls = 0
	a.ns.Arena.Do = function() calls = calls + 1 error("practice called Arena.Do") end
	a.ns.Markets.Bet = function() calls = calls + 1 error("practice called Markets.Bet") end
	a.ns.Arena.Send = function() calls = calls + 1 error("practice sent a network message") end
	local sent, timers = #w.sent, #w.timers
	local ok, err = pcall(function()
		UI.LotteryPracticeReset()
		local empty = UI.LotteryPracticeModel()
		eq(empty.pick, nil); eq(#empty.prizes, 0); eq(empty.localOnly, true)
		eq(UI.LotteryPracticeDraw(), false, "a draw cannot happen before the player's choice")
		eq(UI.LotteryPracticePick(26), false, "only a real beast can be picked")
		local lines = UI.Pane("lottery.practice").lines({ key = "lottery.practice" })
		assert(lines[3] and lines[3].onClick, "the second beast is an actual choice")
		lines[3].onClick()
		eq(UI.LotteryPracticeModel().pick, 2)
		eq(UI.LotteryPracticeModel().free, true, "a free practice ticket: no stake to choose")
		local result = UI.LotteryPracticeDraw({ 1, 5, 9, 13, 17 })
		eq(result.pick, 2); eq(result.stake, nil); eq(#result.rows, 5); eq(result.rows[2].hit, true)
		eq(#result.positions, 1); eq(result.positions[1], a.ns.L.LOTTERY_PRIZE_2)
		eq(result.result, Lt.PrizesText({ 1, 5, 9, 13, 17 }))
		assert(result.outcome:find(result.positions[1], 1, true), "the player sees how the chosen beast did")
		eq(UI.LotteryPracticeDraw({ 1, 2 }), false, "an incomplete local draw is refused")
		eq(UI.LotteryPracticeModel().result, result.result, "a refused draw does not replace the visible result")
		eq(calls, 0); eq(#w.sent, sent); eq(#w.timers, timers)
		eq(a.ns.db.lotteryPractice, nil, "practice creates no persistent production result")
		local games = a.ns.ArenaLedger.MyGames()
		eq(#games, 1, "the draw is a game of his own (the games' ledger)"); eq(games[1].g, "o")
	end)
	a.ns.Arena.Do, a.ns.Markets.Bet, a.ns.Arena.Send = oldDo, oldBet, oldSend
	if not ok then error(err, 0) end
end)

test("1.2 UI: even the author's normal client receives no automatic showcase data", function()
	local w = World.New()
	local author = w:Role("author")
	author.ns.Workshop.Visible = function() return true end
	local own = w:As(author, function() return H.LoadCompanion(author.ns) end)
	local rankings = w:As(author, function() return author.ns.ArenaHome.Data.Rankings("all", "A", 1) end)
	eq(#((rankings or {}).rows or {}), 0)
	eq(#(w:As(author, function() return author.ns.ArenaHome.Data.Events() end) or {}), 0)
	eq(own.ArenaUI.OpenGame("games"), false)
end)

---------------------------------------------------------------------------
-- The Lottery's surfaces (Lane 6): the games' bar under the board, How to play's three pages on
-- the games' pop-up, the result card. A client with the game's frames stood in (board-ui.lua: their
-- anchors resolve, so where a button is can be asked) and the companion loaded.
---------------------------------------------------------------------------

local function LotteryClient(w, name, locale)
	local a = w:Client(name)
	if locale then
		a.globals.GetLocale = function() return locale end
		w:As(a, function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaLotteryText.lua"))("Olympus", a.ns) end)
	end
	a.K = BoardUI.New(function() return w.clock end, { screen = { 1280, 960 } })
	a.K.Install(a.globals)
	-- (as the profile test above: a plain frame for Window.lua's list, the highlight its buttons set)
	local createFrame = a.globals.CreateFrame
	a.globals.CreateFrame = function(kind, ...)
		local frame = createFrame(kind == "ScrollFrame" and "Frame" or kind, ...)
		if kind == "Button" then frame.SetHighlightTexture = function() end end
		frame.SetID = function(self, id) self.frameID = id end
		return frame
	end
	a.db.arenaRules = { yes = true }
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	return a, own
end
-- Fields of t replaced for fn's call (the Lottery's days, a wallet's statement), put back after.
local function WithStubs(t, stubs, fn)
	local saved = {}
	for k, v in pairs(stubs) do saved[k] = rawget(t, k); t[k] = v end
	local ok, err = pcall(fn)
	for k in pairs(stubs) do t[k] = saved[k] end
	if not ok then error(err, 0) end
end
local function OpenDay(w, eid, extra)
	local day = { eid = eid, state = "open", drawAt = w.clock + 600, lockAt = w.clock + 600, cur = "g", pot = 0, carry = 0, bets = {}, mine = {} }
	for i = 1, 25 do day.bets[i] = { pool = 0, count = 0 } end
	for k, v in pairs(extra or {}) do day[k] = v end
	return day
end
-- Every text of a frame's subtree, for "is it on the page".
local function Texts(frame, out)
	out = out or {}
	for _, r in ipairs(frame.regions or {}) do if r.text then out[#out + 1] = r.text end end
	for _, c in ipairs(frame.children or {}) do
		if c.label and c.label.text then out[#out + 1] = c.label.text end
		Texts(c, out)
	end
	return out
end
local function Has(list, text) for _, t in ipairs(list) do if t == text then return true end end return false end

test("Page header: Arena destinations reuse the shared tabs above the dark list", function()
	local w = FW.New({ compliance = "shipped" })
	local a, own = LotteryClient(w, "Lida Fenn")
	BonesReady(w, a)
	w:As(a, function()
		assert(loadfile(H.ADDON_DIR .. "Views.lua"))("Olympus", a.ns)
		local UI = own.ArenaUI
		UI.Open("bone")
		local f = UI.Frame()
		assert(f.paneBar.nav and #f.paneBar.nav > 1, "uses Views.DrawNav, not a second tab style")
		eq(f.paneButtons, f.paneBar.nav)
		local _, top, _, height = a.K.Within(f.paneBar, f.listPanel)
		local _, darkTop = a.K.Within(f.listPanel.shade, f.listPanel)
		assert(top + height < darkTop, "dark list starts below tabs")
		eq(f.listPanel.header:GetHeight(), darkTop)
		local last = f.paneBar.nav[#f.paneBar.nav]
		local expected = UI.Model().panes[#f.paneBar.nav].key
		assert(a.K.UserClick(last))
		eq(UI.Model().pane, expected)
	end)
	for _, err in ipairs(a.K.errors) do error(err) end
end)

test("1.1.6 games presentation: free Lottery uses the animal grid in its own window and preserves the local draw", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Lida Fenn")
	w:As(a, function()
		local UI = own.ArenaUI
		assert(type(UI.LotteryPracticeWindow) == "function", "the free practice has its own window")
		a.ns.Compliance.Allows = function() return false end
		eq(Keys(UI.SectionPanes("lottery")), "lottery.history,lottery.practice", "no closed betting board or its gold animals")
		UI.Open("lottery")
		eq(UI.IsShown(), false, "Play opens the cards directly, not the consultation page")
		local f = UI.LotteryPracticeWindow(true)
		eq(UI.IsShown(), false, "opening play closes the viewing window")
		eq(f.metal, true); eq(#f.cards, 25)
		eq(f.cards[1].art.tex, "Interface\\Icons\\Ability_Mount_MechaStrider")
		eq(f.cards[25].art.tex, "Interface\\Icons\\Ability_Mount_Kodo_01")
		eq(f.draw:IsEnabled(), false, "choose before drawing")
		local sent = #w.sent
		assert(a.K.UserClick(f.cards[2]), "the second animal is clickable")
		eq(UI.LotteryPracticeModel().pick, 2); eq(f.draw:IsEnabled(), true)
		local result = UI.LotteryPracticeDraw({ 1, 5, 9, 13, 17 })
		eq(#result.rows, 5); eq(result.rows[2].hit, true)
		assert(f.result:IsVisible() and not f.grid:IsVisible(), "five results replace the grid")
		-- The original odometer reveals five prizes in sequence before Again is enabled.
		w:Run(10)
		eq(f.prizes[2].number:GetText(), "0005")
		eq(f.prizes[2].art.tex, f.cards[2].art.tex)
		eq(#w.sent, sent, "no betting messages")
		eq(#a.ns.ArenaLedger.MyGames(), 1, "the practice remains in personal history")
		assert(a.K.UserClick(f.draw), "next draw returns to the animal grid")
		assert(f.grid:IsVisible() and not f.result:IsVisible())
		eq(UI.LotteryPracticeModel().pick, nil)
		UI.LotteryPracticeWindow(false)
		eq(f:IsShown(), false)
	end)
	for _, err in ipairs(a.K.errors) do error(err) end
end)

test("1.1.6 Lottery table: original animal cards keep their icon frames, numbered corner and separate footer without a duplicate title", function()
	local w = World.New({ compliance = "shipped" })
	local a, own = LotteryClient(w, "Lida Fenn")
	w:As(a, function()
		local UI = own.ArenaUI
		local f = UI.Open("lottery")
		eq(f, UI.LotteryPracticeWindow(true), "the entry point is the playable grid")
		eq(f.titleText, nil, "the page has its own title, not another one in the frame")
		eq(f.paper.tex, "Interface\\QuestFrame\\QuestBG")
		eq(f.paper:GetParent(), f.title:GetParent(), "the background cannot cover the title through an opaque child frame")
		eq(f.paper:GetParent(), f.intro:GetParent()); eq(f.paper:GetParent(), f.note:GetParent()); eq(f.paper:GetParent(), f.pick:GetParent())
		eq(#f.cards, 25)
		for i, c in ipairs(f.cards) do
			eq(c.num:GetText(), ("%02d"):format(i))
			eq(c.art:GetWidth(), 60); eq(c.art:GetHeight(), 60)
			eq(c.art.points[1].point, "TOPLEFT"); eq(c.art.points[1].x, 10); eq(c.art.points[1].y, -29)
			eq(c.iconFrame.tex, "Interface\\Common\\WhiteIconFrame")
			eq(c.slot.tex, "Interface\\Buttons\\UI-Quickslot2")
			eq(c.wash:IsShown(), false)
		end
		eq(f.cards[1].points[1].y, -118); eq(f.cards[25].points[1].y, -518)
		eq(f.foot.y, 618, "the footer stays below all five rows")
		eq(f.draw:IsEnabled(), false, "a beast is required before the draw")
		assert(a.K.UserClick(f.cards[7]))
		assert(f.cards[7].mark:IsShown()); eq(#f.cards[7].mark.parts, 8)
		for _, t in ipairs(f.cards[7].mark.parts) do eq(t.tex, "Interface\\ContainerFrame\\UI-Icon-QuestBorder") end
		assert(a.K.UserClick(f.cards[25]))
		eq(f.cards[7].mark:IsShown(), false); eq(f.cards[7].wash:IsShown(), false)
		eq(f.cards[25].mark:IsShown(), true); eq(f.draw:IsEnabled(), true)
	end)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("1.1.6 Lottery table: free How to play shows only the playable rules and five-number result in English and Portuguese", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local w = World.New({ compliance = "shipped" })
		local a, own = LotteryClient(w, "Lida Fenn", locale)
		w:As(a, function()
			local UI, L = own.ArenaUI, a.ns.L
			local f = UI.Open("lottery")
			local sent = #w.sent
			assert(a.K.UserClick(f.help))
			local g = UI.LotteryGuide()
			assert(g:IsShown()); eq(#g.tabs, 2); eq(g.model.free, true); eq(g.model.example, nil)
			eq(g.tabs[1].text:GetText(), L.LOTTERY_GUIDE_RULES); eq(g.tabs[2].text:GetText(), L.LOTTERY_GUIDE_DRAW)
			local said = table.concat(Texts(g), "\n"):lower()
			for _, word in ipairs({ "bet", "stake", "wallet", "profit", "payout", "fee", "aposta", "carteira", "lucro", "taxa", "pagamento", "6%" }) do
				assert(not said:find(word, 1, true), locale .. ": financial instructions visible: " .. word)
			end
			assert(Has(Texts(g.pages[1]), L.LOTTERY_FREE_GUIDE_DRAW))
			assert(a.K.UserClick(g.tabs[2])); eq(g.page, 2)
			assert(Has(Texts(g.pages[2]), L.LOTTERY_FREE_GUIDE_PLACES))
			eq(UI.LotteryHowToPlay(3), g); eq(g.page, 2, "an old payout page index opens a valid free page")
			assert(a.K.UserClick(g.ok)); eq(g:IsShown(), false)
			assert(a.K.UserClick(f.help)); assert(g:IsShown())
			UI.LotteryPracticeWindow(false); eq(g:IsShown(), false, "closing the game also closes its guide")
			eq(#w.sent, sent, "reading the free rules creates no wager message")
		end)
		eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
		eq(#a.errors, 0, table.concat(a.errors, "; "))
	end
end)

test("1.1.6 Lottery table: revoking permission puts away a cached financial guide and restores the cached free guide", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Lida Fenn")
	w:As(a, function()
		local UI = own.ArenaUI
		local old = UI.LotteryHowToPlay(3)
		eq(#old.tabs, 3); eq(old.page, 3)
		a.ns.Compliance.Declared = function() return nil, nil end
		local free = UI.LotteryHowToPlay(3)
		assert(free ~= old); eq(old:IsShown(), false)
		eq(#free.tabs, 2); eq(free.model.example, nil); eq(free.page, 2)
		old.tabs[3]:GetScript("OnClick")()
		eq(old:IsShown(), false); eq(free.page, 2, "a stale financial callback cannot reveal its old page")
		eq(UI.LotteryHowToPlay(1), free, "the free guide is reused, not rebuilt on every open")
	end)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("1.1.6 games presentation: Bones Play is a letter and empty live tables have a readable detail", function()
	local w = FW.New()
	local a, own = LotteryClient(w, "Lida Fenn")
	BonesReady(w, a)
	w:As(a, function()
		local UI = own.ArenaUI
		UI.Open("bone")
		assert(UI.IsShown(), "the viewing page opens")
		UI.FarkleBoard.Show(false)
		eq(UI.IsShown(), false, "the Bones table closes the viewing page")
		UI.Open("bone")
		UI.FarkleBoard.Show(false)
		eq(UI.IsShown(), false, "returning to a table already open closes the viewer too")
		UI.FarkleBoard.Close()
		local canvas = CreateFrame("Frame", nil, UIParent)
		canvas:SetSize(UI.DETAIL_W, 430)
		UI.Pane("bone.play").detail(canvas)
		assert(canvas.letterTitle and canvas.letterBody and canvas.find, "explanation and Find action")
		eq(canvas.letterTitle:GetText(), a.ns.L.FARKLE_INTRO_TITLE)
		assert(canvas.letterBody:GetText():find(a.ns.L.FARKLE_INTRO_TEXT, 1, true))
		assert(canvas.letterBody:GetWidth() > 450, "words use the page width")
		local called
		UI.FindOpponent = function(game) called = game return true end
		assert(a.K.UserClick(canvas.find)); eq(called, "b")
		local detail = CreateFrame("Frame", nil, UIParent)
		UI.Pane("bone.live").detail(detail, { sel = "expired-table" })
		assert(detail.empty and detail.empty:IsShown(), "empty state on the detail side too")
		eq(detail.empty:GetText(), a.ns.L.ARENA_BONE_LIVE_NONE)
	end)
end)

test("1.2 UI: the Lottery's Bet and Roll sit on the games' bar under the board, its coin and How to play on the left, 56 px as in Bones", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Lida Fenn")
	local UI, Lt, G, K = own.ArenaUI, a.ns.Lottery, own.Games, a.K
	a.ns.db.lotteryIntro = Lt.INTRO -- (How to play by itself is the next test's)
	local day = OpenDay(w, "L7")
	WithStubs(Lt, { Today = function() return day end, LastDrawn = function() return nil end, CanBet = function() return true end }, function()
		w:As(a, function()
			UI.Open("lottery")
			local f, board, B = UI.Frame(), UI.LotteryBoard(), G.BAR
			assert(board and board.frame:IsVisible(), "the real board is the Lottery section")
			eq(B.H, UI.FOOT_H, "the arena window's bar is the games' one, Bones' height")
			-- Bet on the bar's right, the arena's and Bones' action slot, the bar's button height.
			local x, y, bw, bh = K.Within(board.bet, f)
			assert(board.bet:IsVisible(), "a bettor's Bet shows")
			eq(bh, B.BUTTON_H)
			assert(y >= UI.FOOT_Y and y + bh <= UI.FOOT_Y + UI.FOOT_H, "Bet inside the bar: " .. y)
			eq(x + bw, UI.W - 10 - B.PAD, "Bet at the bar's right edge")
			for _, b in ipairs(f.buttons) do eq(b:IsShown(), false, "the window adds no buttons of its own here") end
			-- The coin and the balance, then How to play, on the bar's left.
			local cx, cy = K.Within(f.bar.wallet.coin, f)
			local hx, hy = K.Within(f.bar.help, f)
			assert(cy >= UI.FOOT_Y and hy >= UI.FOOT_Y and cx < hx and hx < x, "coin, How to play, then Bet, left to right")
			-- The counter (the pick and the stake) on the parchment above the bar, no bar of its own.
			local _, ky, _, kh = K.Within(board.counter, f)
			assert(ky + kh <= UI.FOOT_Y, "the counter is above the bar")
			local mx, _, mw = K.Within(board.counter.max, f)
			local _, _, cw = K.Within(board.counter, f)
			eq(mx + mw, K.Within(board.counter, f) + cw - 4, "the stake's steppers end at the counter's right")
			-- Bet needs a pick; Roll is the caller's.
			eq(board.bet.enabled, false)
			assert(K.UserClick(board.cards[7]))
			eq(board.bet.enabled, true, "a beast picked: Bet can be pressed")
			eq(board.roll:IsShown(), false)
		end)
	end)
	-- The caller: Roll where Bet was, Bet gone.
	local due = OpenDay(w, "L8", { state = "closed", isCaller = true, canDraw = true, roller = "king", schedule = { on = true, at = 1260 } })
	WithStubs(Lt, { Today = function() return due end, LastDrawn = function() return nil end }, function()
		w:As(a, function()
			UI.LotteryRefresh()
			local f, board, B = UI.Frame(), UI.LotteryBoard(), G.BAR
			eq(board.bet:IsShown(), false); eq(board.roll:IsShown(), true)
			eq(board.roll:GetText(), a.ns.L.LOTTERY_BOARD_ROLL:format(1)); eq(board.roll.enabled, true)
			local x, y, bw, bh = K.Within(board.roll, f)
			assert(y >= UI.FOOT_Y and y + bh <= UI.FOOT_Y + UI.FOOT_H, "Roll inside the bar")
			eq(x + bw, UI.W - 10 - B.PAD, "Roll at the bar's right edge")
		end)
	end)
	-- The board's own window (no betting window in the build): its own games' bar, the same parts.
	WithStubs(Lt, { Today = function() return day end, LastDrawn = function() return nil end, CanBet = function() return true end }, function()
		w:As(a, function()
			UI.Hide()
			local win = UI.LotteryWindow(true)
			local board, B = UI.LotteryBoard(), G.BAR
			eq(board.frame:GetParent(), win.body)
			assert(win.bar and win.bar.wallet and win.bar.help, "its bar: the coin, the balance, How to play")
			local ww, wh = win:GetWidth(), win:GetHeight()
			local x, y, bw, bh = K.Within(board.bet, win)
			assert(y >= wh - 10 - B.H and y + bh <= wh - 10, "Bet inside the window's bar")
			eq(x + bw, ww - 10 - B.PAD)
			local _, by, _, bodyH = K.Within(win.body, win)
			eq(by + bodyH, wh - 10 - B.H, "the board ends where the bar begins")
			eq(board.help:IsShown(), false, "How to play is the bar's here")
			assert(K.UserClick(win.bar.help))
			assert(UI.LotteryGuide():IsShown(), "the bar's How to play opens the Lottery's")
			UI.LotteryGuide():Hide()
			-- Back to the arena window: the one board is its pane again, Bet on that bar.
			UI.LotteryWindow(false)
			UI.Open("lottery")
			local f = UI.Frame()
			assert(board.frame:IsVisible(), "the board is back in the arena window")
			local _, fy = K.Within(board.bet, f)
			assert(fy >= UI.FOOT_Y, "Bet on the arena window's bar again")
			eq(board.help:IsShown(), true, "up top while the arena window's bar opens the arena's guide")
		end)
	end)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("1.2 UI: the Lottery's How to play is the lab's three pages on the games' pop-up, by itself the first time, on The deal", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Parric Stowe")
	local UI, Lt, L, K = own.ArenaUI, a.ns.Lottery, a.ns.L, a.K
	w:As(a, function()
		UI.Open("lottery")
		local guide = UI.LotteryGuide()
		assert(guide and guide:IsShown(), "the first open shows How to play by itself")
		eq(guide:GetName(), "OlympusArenaLotteryGuide")
		eq(guide:GetFrameStrata(), "FULLSCREEN_DIALOG", "the games' pop-up, a strata above the windows")
		eq(a.ns.db.lotteryIntro, Lt.INTRO)
		eq(#guide.tabs, 3)
		eq(guide.tabs[1].text:GetText(), L.LOTTERY_GUIDE_DEAL); eq(guide.tabs[2].text:GetText(), L.LOTTERY_GUIDE_RULES)
		eq(guide.tabs[3].text:GetText(), L.LOTTERY_GUIDE_PAYOUT)
		eq(guide.page, 1); eq(guide.pages[1]:IsShown(), true); eq(guide.pages[2]:IsShown(), false)
		-- The deal is the first-use explanation: unsigned, no King's letter.
		local deal = Texts(guide.pages[1])
		for i = 1, 4 do assert(Has(deal, L["LOTTERY_INTRO_" .. i]), "the deal's paragraph " .. i) end
		guide:Hide()
		UI.Hide()
		UI.Open("lottery")
		eq(guide:IsShown(), false, "by itself only the first time")
		-- The board's How to play opens it again, on the page it was left at; the tabs turn the pages.
		local board = UI.LotteryBoard()
		assert(K.UserClick(board.help)); eq(guide:IsShown(), true); eq(guide.page, 1)
		assert(K.UserClick(guide.tabs[3]))
		eq(guide.page, 3); eq(guide.pages[3]:IsShown(), true); eq(guide.pages[1]:IsShown(), false)
		eq(guide.tabs[3].selected, true); eq(guide.tabs[1].selected, false)
		-- The payout's example is the real contract's settlement of its book, to the copper.
		local ex = UI.LotteryGuideModel().example
		eq(ex.pot, 10000000); eq(ex.onHead, 1000000); eq(ex.refunds, 1000000); eq(ex.profit, 9000000)
		eq(ex.first, 4500000); eq(ex.fee, 270000); eq(ex.share, 1692000); eq(ex.back, 400000)
		eq(ex.get, 2092000); eq(ex.carry, 4500000); eq(ex.percent, 40)
		local payout = Texts(guide.pages[3])
		assert(Has(payout, Lt.Money(2092000, "g")), "what you get, on the page")
		assert(Has(payout, "-" .. Lt.Money(270000, "g")), "the guild's 6%, on the page")
		assert(Has(payout, Lt.Money(4500000, "g")), "the unclaimed places roll over")
		-- Got it puts it away; so does the board's How to play, pressed again.
		assert(K.UserClick(board.help)); eq(guide:IsShown(), false)
		assert(K.UserClick(board.help)); assert(K.UserClick(guide.ok)); eq(guide:IsShown(), false)
	end)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("1.2 UI: the Lottery's How to play and result card open by themselves and, with the gamepad UI on, write nothing to UISpecialFrames; with mouse and keyboard Escape closes them", function()
	local function Ours(list)
		local out = {}
		for _, name in ipairs(list or {}) do if tostring(name):find("^OlympusArenaLottery") then out[#out + 1] = name end end
		table.sort(out)
		return table.concat(out, ",")
	end
	for _, gamepad in ipairs({ true, false }) do
		local w = World.New()
		local a, own = LotteryClient(w, gamepad and "Orrin Vale" or "Mira Thorne")
		local UI, Lt = own.ArenaUI, a.ns.Lottery
		-- (Yesterday's draw settled with a winning ticket of this player's, today's open.)
		local settled = { eid = "L41", state = "settled", drawAt = w.clock - 7200, lockAt = w.clock - 7200, cur = "g",
			prizes = { 1, 5, 9, 13, 17 }, bank = World.NAMES.bank, mine = { { o = 1, s = 100000, payout = 340000 } }, bets = {}, pot = 0, carry = 0 }
		for i = 1, 25 do settled.bets[i] = { pool = 0, count = 0 } end
		local today = OpenDay(w, "L42")
		H.WithGamepadUI(gamepad, function()
			WithStubs(Lt, { Today = function() return today end, LastDrawn = function() return "L41" end,
				Day = function(eid) return eid == "L41" and settled or today end }, function()
				w:As(a, function()
					eq(a.ns.GamepadUI(), gamepad)
					UI.Open("lottery")
					local guide, card = UI.LotteryGuide(), UI.LotteryCard()
					assert(guide and guide:IsShown(), "How to play, by itself the first time")
					assert(card and card:IsShown(), "the settled day's card, by itself")
					if gamepad then
						-- (Blizzard's menus close every window on that list, and read it unprotected.)
						eq(Ours(a.globals.UISpecialFrames), "", "nothing of the Lottery's in the list")
						assert(a.K.UserClick(guide.ok)); eq(guide:IsShown(), false, "its own button closes it")
						assert(a.K.UserClick(card.buttons[3])); eq(card:IsShown(), false)
					else
						eq(Ours(a.globals.UISpecialFrames), "OlympusArenaLotteryGuide,OlympusArenaLotteryResult")
						a.K.Escape()
						eq(guide:IsShown(), false, "Escape closes How to play"); eq(card:IsShown(), false, "and the card")
					end
				end)
			end)
		end)
		eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
		eq(#a.errors, 0, table.concat(a.errors, "; "))
	end
end)

-- (Reviewer, the 1.1.6 base: the gamepad audit scanned Olympus/ alone, and two of the companion's
-- reaches got through: Games.Popup put its name in UISpecialFrames as it was built, whatever the
-- input style, and ArenaUI.Menu opened Blizzard's context menu with the gamepad UI on.)
test("1.2 UI: with the gamepad UI on, the Arena's How to play writes nothing to UISpecialFrames and its button menus are Olympus's own (no Blizzard menu); with mouse and keyboard, Escape and the client's menu as before", function()
	for _, gamepad in ipairs({ true, false }) do
		local w = World.New()
		local a, own = LotteryClient(w, gamepad and "Orrin Vale" or "Mira Thorne")
		local UI, L = own.ArenaUI, a.ns.L
		local menus = {}
		a.globals.MenuUtil = { CreateContextMenu = function(owner, fn)
			local root = { lines = {} }
			function root:CreateButton(text, onClick) self.lines[#self.lines + 1] = { text, onClick } return { SetEnabled = function() end } end
			fn(owner, root)
			menus[#menus + 1] = root
		end }
		local function Listed(name)
			for _, n in ipairs(a.globals.UISpecialFrames or {}) do if n == name then return true end end
			return false
		end
		H.WithGamepadUI(gamepad, function()
			w:As(a, function()
				eq(a.ns.GamepadUI(), gamepad)
				UI.Open("arena")
				local howto = UI.HowToPlay(1)
				assert(howto and howto:IsShown(), "How to play")
				eq(Listed("OlympusArenaHowTo"), not gamepad, "on the escape list with mouse and keyboard only")
				if gamepad then
					assert(a.K.UserClick(howto.ok)); eq(howto:IsShown(), false, "its own button closes it")
				else
					a.K.Escape(); eq(howto:IsShown(), false, "Escape closes it")
					UI.Open("arena") -- (the client's Escape closes every window on the list at once)
				end
				-- New fight: its two lines, in the client's menu or, with the gamepad UI, in Olympus's.
				local found, opened
				for _, b in ipairs(UI.frame.buttons or {}) do if b:IsShown() and b:GetText() == L.ARENA_NEW_FIGHT then found = b end end
				assert(found, "the New fight button")
				local was = UI.Challenge
				UI.Challenge = function() opened = true end
				assert(a.K.UserClick(found))
				if gamepad then
					eq(#menus, 0, "no Blizzard menu with the gamepad UI")
					local menu = UI.OwnMenu()
					assert(menu and menu:IsShown(), "Olympus's own menu")
					eq(Listed("OlympusArenaMenu"), false, "nothing on the escape list")
					local texts = {}
					for _, b in ipairs(menu.buttons) do if b:IsShown() then texts[#texts + 1] = b:GetText() end end
					eq(table.concat(texts, ","), L.ARENA_FIND_OPPONENT .. "," .. L.ARENA_CHALLENGE_SOMEONE)
					assert(a.K.UserClick(menu.buttons[2]))
					eq(menu:IsShown(), false, "a pick closes it")
				else
					eq(#menus, 1, "the client's own context menu")
					eq(UI.OwnMenu(), nil, "none of Olympus's")
					eq(menus[1].lines[2][1], L.ARENA_CHALLENGE_SOMEONE)
					menus[1].lines[2][2]()
				end
				UI.Challenge = was
				eq(opened, true, "the line picked is done")
			end)
		end)
		eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
		eq(#a.errors, 0, table.concat(a.errors, "; "))
	end
end)

test("1.2 UI: the Lottery's new words are in English and pt-BR, with the same format arguments", function()
	local function Words(locale)
		local saved, host = GetLocale, { L = {} }
		GetLocale = function() return locale end
		local ok, err = pcall(function() assert(loadfile(H.ARENA_DIR .. "Locales/LotteryText.lua"))("Olympus_Arena", { host = host }) end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return host.L
	end
	local en, pt = Words("enUS"), Words("ptBR")
	local function Args(s) local out = {} for spec in s:gmatch("%%[%-%d%.]*[sd%%]") do out[#out + 1] = spec end return table.concat(out, " ") end
	local n = 0
	for key, text in pairs(en) do
		if key:find("^LOTTERY_GUIDE_") or key:find("^LOTTERY_CARD_") then
			n = n + 1
			assert(type(pt[key]) == "string" and pt[key] ~= text, key .. " has its pt-BR words")
			eq(Args(pt[key]), Args(text), key .. ": the same format arguments")
		end
	end
	assert(n >= 45, "the guide's and the card's words: " .. n)
end)

test("1.2 UI: the Lottery's counter shows, before a bet, about what the stake brings back if the pick comes 1st alone; the draw on its clock; a day not drawn in its hour says so", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Tamsin Reyl")
	local UI, Lt, L, K = own.ArenaUI, a.ns.Lottery, a.ns.L, a.K
	a.ns.db.lotteryIntro = Lt.INTRO
	local g = 10000
	local day = OpenDay(w, "L9", { pot = 960 * g })
	day.bets[7], day.bets[14] = { pool = 60 * g, count = 3 }, { pool = 500 * g, count = 9 }
	day.bets[2], day.bets[25] = { pool = 250 * g, count = 4 }, { pool = 150 * g, count = 2 }
	WithStubs(Lt, { Today = function() return day end, LastDrawn = function() return nil end, CanBet = function() return true end }, function()
		w:As(a, function()
			UI.Open("lottery")
			local board = UI.LotteryBoard()
			eq(board.counter.preview:GetText(), "", "nothing before a pick")
			assert(K.UserClick(board.cards[7]))
			-- The stake it starts on, 1g, on the Sheep: 961g on the table, the Sheep's 61g back, a 900g
			-- profit pool, 1st place's 450g less 6% is 423g, 1/61 of it 6g 93s 44c, plus the 1g back.
			eq(board.model.bet.silver, 100)
			eq(board.model.bet.estimate.payout, 79344, "to the copper underneath")
			eq(board.counter.preview:GetText(), L.LOTTERY_BOARD_PREVIEW:format(Lt.Label(7), Lt.Money(79300, "g")), "shown to the silver")
			-- Another beast, nobody on it yet: 960g of profit, 1st place's 480g less 6%, all the stake's.
			assert(K.UserClick(board.cards[9]))
			eq(board.model.bet.estimate.payout, 10000 + 4800000 - 288000)
			-- The draw's time on the draw's clock, with its name.
			assert(tostring(board.line:GetText()):find(L.LOTTERY_BOARD_DRAW_AT:format(Lt.WhenText(day.drawAt)), 1, true), "the draw's clock")
		end)
	end)
	local late = UI.LotteryModel(OpenDay(w, "L10", { state = "closed", late = true, drawAt = w.clock - 3700, lockAt = w.clock - 3700 }))
	assert(late.line:find(L.LOTTERY_BOARD_LATE, 1, true), "void, every stake back")
	eq(late.line:find(L.LOTTERY_BOARD_CLOSED, 1, true), nil)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)

test("1.2 UI: the Lottery's result card: tickets, staked, refunded, won or lost to the copper, the balance and the Wallet, once a day", function()
	local w = World.New()
	local a, own = LotteryClient(w, "Wenna Crale")
	local UI, Lt, L, K = own.ArenaUI, a.ns.Lottery, a.ns.L, a.K
	a.ns.db.lotteryIntro = Lt.INTRO
	local bank = World.NAMES.bank
	local function Day(mine, extra)
		-- (Yesterday's draw, settled: beasts 1 to 5 drawn.)
		local d = { eid = "L41", state = "settled", drawAt = w.clock - 7200, lockAt = w.clock - 7200, cur = "g", prizes = { 1, 5, 9, 13, 17 },
			bank = bank, mine = mine, bets = {}, pot = 0, carry = 0 }
		for i = 1, 25 do d.bets[i] = { pool = 0, count = 0 } end
		for k, v in pairs(extra or {}) do d[k] = v end
		return d
	end
	local statement = { g = { bal = 1234500 }, p = { bal = 0 } }
	WithStubs(a.ns.Wallet, { Statement = function(b) eq(b, bank) return statement end }, function()
		w:As(a, function()
			local function M(c) return Lt.Money(c, "g") end
			-- Won: a ticket on the 1st beast paid its stake and profit, one on an undrawn beast lost.
			local won = UI.LotteryCardSpec(Day({ { o = 1, s = 100000, payout = 340000 }, { o = 9, s = 50000, payout = 0 } }))
			eq(won.verdict, "won"); eq(won.title, L.LOTTERY_CARD_WON_TITLE)
			eq(won.staked, 150000); eq(won.refunded, 100000); eq(won.won, 240000); eq(won.lost, 50000); eq(won.net, 190000)
			local rows = {}
			for i, r in ipairs(won.rows) do rows[i] = r[1] .. "=" .. r[2] end
			eq(table.concat(rows, "|"), table.concat({ L.LOTTERY_CARD_TICKETS .. "=2", L.LOTTERY_CARD_STAKED .. "=" .. M(150000),
				L.LOTTERY_CARD_REFUNDED .. "=" .. M(100000), L.LOTTERY_CARD_WON .. "=+" .. M(240000), L.LOTTERY_CARD_LOST .. "=-" .. M(50000),
				L.LOTTERY_CARD_BALANCE .. "=" .. M(1234500) }, "|"))
			eq(won.note, L.LOTTERY_CARD_FEE)
			-- Stakes back: a fifth-place ticket is refunded, nothing won, no fee said.
			local back = UI.LotteryCardSpec(Day({ { o = 5, s = 100000, payout = 100000 } }))
			eq(back.verdict, "back"); eq(back.refunded, 100000); eq(back.won, 0); eq(back.note, nil)
			local lost = UI.LotteryCardSpec(Day({ { o = 9, s = 100000, payout = 0 } }))
			eq(lost.verdict, "lost"); eq(lost.lost, 100000); eq(lost.title, L.LOTTERY_CARD_LOST_TITLE)
			-- No card: a ticket the bank has not paid yet, no ticket, the rolls seen but not declared.
			eq(UI.LotteryCardSpec(Day({ { o = 1, s = 100000 } })), nil)
			eq(UI.LotteryCardSpec(Day({})), nil)
			eq(UI.LotteryCardSpec(Day({ { o = 1, s = 1, payout = 1 } }, { live = true })), nil)
			-- A void day: every stake back; a rehearsal says so.
			local void = UI.LotteryCardSpec(Day({ { o = 9, s = 100000 } }, { state = "void", prizes = false }))
			eq(void.verdict, "back"); eq(void.refunded, 100000); eq(void.note, L.LOTTERY_CARD_VOID)
			eq(UI.LotteryCardSpec(Day({ { o = 1, s = 100000, payout = 340000 } }, { mode = "T" })).note, L.LOTTERY_CARD_REHEARSAL)
		end)
		-- On the board: yesterday's settled day on the slip while today's takes bets, its card in front.
		local today = OpenDay(w, "L42")
		local settled = Day({ { o = 1, s = 100000, payout = 340000 }, { o = 9, s = 50000, payout = 0 } })
		local opened = 0
		WithStubs(Lt, { Today = function() return today end, LastDrawn = function() return "L41" end,
			Day = function(eid) return eid == "L41" and settled or today end }, function()
			WithStubs(a.ns.Treasury, { OpenMoney = function() opened = opened + 1 end }, function()
				w:As(a, function()
					UI.Open("lottery")
					local card = UI.LotteryCard()
					assert(card and card:IsShown(), "the settled day's card")
					eq(card:GetName(), "OlympusArenaLotteryResult"); eq(card:GetFrameStrata(), "FULLSCREEN_DIALOG")
					eq(card.verdict:GetText(), L.LOTTERY_CARD_WON_TITLE)
					eq(card.rows[4].r:GetText(), "+" .. Lt.Money(240000, "g"))
					eq(card.rows[6].l:GetText(), L.LOTTERY_CARD_BALANCE); eq(card.rows[6].r:GetText(), Lt.Money(1234500, "g"))
					eq(card.buttons[1]:GetText(), L.LOTTERY_HISTORY_WALLET)
					-- Its Wallet button opens the one Wallet and puts the card away.
					assert(K.UserClick(card.buttons[1]))
					eq(opened, 1); eq(card:IsShown(), false)
					-- Once a day: the board opened again shows no card for it.
					UI.Hide()
					UI.Open("lottery")
					eq(card:IsShown(), false, "a day's card comes once")
					eq(UI.Kit.Recall("lottery:card"), "L41")
				end)
			end)
		end)
	end)
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	eq(#a.errors, 0, table.concat(a.errors, "; "))
end)
