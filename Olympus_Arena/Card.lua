local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Card.lua. A stub the arena's core created for the screens to
-- fill. The fighter card, the tale of the tape (OlympusArenaCard).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome
local V = Kit.V

-- One builder, three sizes (the design): compact (434 x 150, the Events pane), the window (596 x
-- 440, Tale of the tape) and the overlay (900 x 460 at scale 1, Overlay.lua). What it shows is
-- worked out first, without frames (Card.Model, the tests read it): each fighter's name, his
-- verified title, guild rank, class and level, race, rating and peak, record, the duels he fled,
-- his streak, last five, tier medallion, wins by knockout, average duration, and on a public
-- fight the odds, pool and bettors of his side; each value
-- that can be checked with "seen", "self-reported" or "arbiter" beside it. The portrait comes
-- first from a live unit, then his emblem, his class, the arena emblem (Card.Portrait), drawn as
-- the player's own portrait with the frame his client picked once this client verified it, else
-- his guild rank's (Kit.NewPortrait, Kit.SetPortraitFrame).
-- Names, numbers and fixed words only: nothing another player typed.
local Card = {}
ArenaUI.Card = Card

-- (The window's card is 440 high, 2026-10-04: the fuller tale of the tape, up to 14 rows.)
Card.SIZES = { compact = { ArenaUI.CARD_W or 428, 150, 44 }, window = { 596, 440, 96 }, overlay = { 900, 460, 128 } }

---------------------------------------------------------------------------
-- The portrait (the design): a live unit, the emblem, the class icon, the arena emblem
---------------------------------------------------------------------------

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
-- The unit tokens a fighter may be under now, in order: the player himself first (his own
-- portrait, as on his unit frame), then whoever he sees.
function Card.Tokens()
	local out = { "player", "target", "focus", "mouseover" }
	for i = 1, 4 do out[#out + 1] = "party" .. i end
	for i = 1, 40 do out[#out + 1] = "raid" .. i end
	for i = 1, 40 do out[#out + 1] = "nameplate" .. i end
	return out
end
-- A unit showing `name` now, or nil (never a secret value compared).
function Card.FindUnit(name)
	if type(name) ~= "string" or not UnitExists then return nil end
	local want = ns.FullName(name):lower()
	for _, unit in ipairs(Card.Tokens()) do
		local okE, exists = pcall(UnitExists, unit)
		if okE and exists and not Secret(exists) then
			local okN, who = pcall(ns.UnitFullName, unit)
			if okN and type(who) == "string" and not Secret(who) and who:lower() == want then return unit end
		end
	end
	return nil
end

-- The class icon's coordinates (the client's CLASS_ICON_TCOORDS, else the classic grid).
local CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local GRID = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 }, DRUID = { 0.75, 1, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 } }
local function ClassCoords(file)
	local t = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[file] or nil
	return t or GRID[file]
end
-- An emblem as the player picked it: a game icon only, never a path (ns.CouncilIconValue).
local function EmblemTexture(emblem)
	if emblem == nil or emblem == "" then return nil end
	local ok, v = pcall(ns.CouncilIconValue, emblem)
	if not ok or v == nil then return nil end
	if type(v) == "number" then return v end
	if type(v) == "string" then return v:find("\\", 1, true) and v or ("Interface\\Icons\\" .. v) end
	return nil
end
Card.EmblemTexture = EmblemTexture
-- Where a fighter's portrait comes from: "live" (a unit), "emblem", "class" or "arena", with what
-- to draw: { kind, unit, texture, coords }.
function Card.Portrait(name, emblem, classFile)
	local unit = Card.FindUnit(name)
	if unit then return { kind = "live", unit = unit } end
	local tex = EmblemTexture(emblem)
	if tex then return { kind = "emblem", texture = tex } end
	local coords = classFile and ClassCoords(classFile)
	if coords then return { kind = "class", texture = CIRCLES, coords = coords } end
	return { kind = "arena", texture = Kit.Emblem() }
end
-- square: the unit's picture without the client's own rounding (SetPortraitTexture's
-- disableMasking, as the player's frame asks it), for a portrait masked as his (Kit.DrawPortrait).
function Card.SetPortrait(tex, name, emblem, classFile, square)
	if not tex then return nil end
	local p = Card.Portrait(name, emblem, classFile)
	-- (A live portrait follows its unit from now on: the events, the first time one shows.)
	if p.kind == "live" then Card.Watch() end
	if p.kind == "live" and SetPortraitTexture then
		local ok = pcall(SetPortraitTexture, tex, p.unit, square == true)
		if ok then
			if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
			return p
		end
		p = Card.Portrait(nil, emblem, classFile)
	end
	tex:SetTexture(p.texture)
	if tex.SetTexCoord then
		if p.coords then tex:SetTexCoord(unpack(p.coords)) else tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	end
	return p
end

-- The small grey word beside a value that can be checked.
local TAGS = { seen = "ARENA_SRC_SEEN", own = "ARENA_SRC_OWN", arbiter = "ARENA_SRC_ARBITER", ledger = "ARENA_SRC_LEDGER", verified = "ARENA_SRC_VERIFIED" }
function Card.ValueTag(field, source)
	local key = TAGS[source or ""]
	if not key then return "" end
	return L[key]
end

---------------------------------------------------------------------------
-- The model
---------------------------------------------------------------------------

-- The winner market of an event and each side's outcome in it (odds, pool, bettors).
local function Sides(id, ev)
	local view = Data.Markets(id)
	if type(view) ~= "table" then return nil end
	for _, mk in ipairs(view.markets or {}) do
		if mk.type == "MW" or mk.type == "winner" or mk.idx == 1 then
			local out = { cur = view.cur }
			for _, o in ipairs(mk.outcomes or {}) do
				local side = (o.o == "A" or o.o == 1 or o.o == "1") and "A" or ((o.o == "B" or o.o == 2 or o.o == "2") and "B" or nil)
				if not side and o.label then
					if ev.A and ns.Codec.Plain(tostring(o.label)) == Kit.Name(ev.A) then side = "A" end
					if ev.B and ns.Codec.Plain(tostring(o.label)) == Kit.Name(ev.B) then side = "B" end
				end
				if side then out[side] = { odds = tonumber(o.odds), pool = tonumber(o.pool) or 0, count = tonumber(o.count) or 0 } end
			end
			return out
		end
	end
	return nil
end

local function LastFive(gk)
	if not gk then return nil, nil, nil end
	local LG = ns.ArenaLedger
	local rows
	if Data.History and Home.Source() then rows = nil
	elseif type(LG) == "table" and type(LG.History) == "function" then
		local ok, r = pcall(LG.History, { gk = gk, limit = 20 })
		rows = ok and r or nil
	end
	if type(rows) ~= "table" then return nil, nil, nil end
	local marks, durs, n = {}, 0, 0
	for i, r in ipairs(rows) do
		if i <= 5 then marks[#marks + 1] = r.won and "W" or "L" end
		if tonumber(r.dur) then durs, n = durs + r.dur, n + 1 end
	end
	return #marks > 0 and table.concat(marks, " ") or nil, n > 0 and math.floor(durs / n + 0.5) or nil
end

-- One fighter: every value the card shows, with its source.
function Card.Fighter(name, gk)
	if type(name) ~= "string" then return nil end
	local p = Data.Profile(name) or {}
	local f = { name = name, gk = gk or p.gk }
	f.title = V(p.title)
	f.titleSrc = type(p.title) == "table" and p.title.src or nil
	f.class, f.classSrc = V(p.class), type(p.class) == "table" and p.class.src or nil
	f.race, f.raceSrc = V(p.race), type(p.race) == "table" and p.race.src or nil
	f.level, f.levelSrc = V(p.level), type(p.level) == "table" and p.level.src or nil
	-- Level, class and race are "seen" only where this client has a unit for him (claims c01-c06).
	local unit = Card.FindUnit(name)
	if unit then
		local okL, lvl = pcall(UnitLevel, unit)
		if okL and tonumber(lvl) and not Secret(lvl) and lvl > 0 then f.level, f.levelSrc = lvl, "seen" end
		if UnitClass then
			local okC, _, file = pcall(UnitClass, unit)
			if okC and type(file) == "string" and not Secret(file) then f.class, f.classSrc = file, "seen" end
		end
	end
	local rec = V(p.record)
	if type(rec) == "table" then
		f.record = ArenaUI.RecordText and ArenaUI.RecordText(rec) or ("%d-%d"):format(tonumber(rec.wins) or 0, tonumber(rec.losses) or 0)
		local wins = tonumber(rec.wins) or 0
		if wins > 0 and tonumber(rec.ko) then f.ko = math.floor(100 * rec.ko / wins + 0.5) end
		f.last5, f.avgDur = rec.last5, rec.avgDur
		-- (The duels he left and his streak, ArenaRating.Record's: +3 three wins in a row, -2 two defeats.)
		f.fled, f.streak = tonumber(rec.fled), tonumber(rec.streak)
	end
	f.recordSrc = type(p.record) == "table" and p.record.src or nil
	-- The rating now and the best it reached (the ledger's); the streak where only the profile's
	-- own block has it.
	f.rating, f.ratingSrc = tonumber(V(p.rating)), type(p.rating) == "table" and p.rating.src or nil
	f.peak = tonumber(V(p.peak))
	if f.streak == nil and type(V(p.stats)) == "table" then f.streak = tonumber(V(p.stats).streak) end
	if not f.last5 then
		local last, avg = LastFive(f.gk)
		f.last5, f.avgDur = f.last5 or last, f.avgDur or avg
	end
	f.tier = V(p.tier) or (f.gk and Data.Tier(f.gk)) or nil
	f.emblem = V(p.emblem)
	f.guild, f.guildRank = V(p.guild), V(p.guildRank)
	f.guildRankSrc = type(p.guildRank) == "table" and p.guildRank.src or nil
	f.honour, f.gender = V(p.honour), V(p.gender)
	f.classFile = ArenaUI.ClassFile and ArenaUI.ClassFile(f.class) or f.class
	f.portrait = Card.Portrait(name, f.emblem, f.classFile).kind
	f.openBet = Data.OpenBet(name)
	return f
end

function Card.Model(id)
	local ev = id and Data.Event(id)
	if not ev then return nil end
	local m = { id = id, ev = ev, title = Home.EventTitle(ev), state = Home.StateWord(ev), mode = ev.mode, public = ev.public == true }
	m.A = Card.Fighter(ev.A, ev.gkA)
	m.B = Card.Fighter(ev.B, ev.gkB)
	local sides = ev.public and Sides(id, ev) or nil
	if sides then
		m.cur = sides.cur
		if m.A and sides.A then m.A.odds, m.A.pool, m.A.count = sides.A.odds, sides.A.pool, sides.A.count end
		if m.B and sides.B then m.B.odds, m.B.pool, m.B.count = sides.B.odds, sides.B.pool, sides.B.count end
	end
	local view = Data.Markets(id)
	m.lockAt = type(view) == "table" and tonumber(view.lockAt) or ev.lockAt
	-- The stream delay line: on the King's screen only (the design).
	if Kit.KingsView(ev.mode) and ev.public then m.delay = ArenaUI.DelayLine and ArenaUI.DelayLine() or nil end
	return m
end

-- A fighter's rows, as the card shows them: { label, value, tag }.
local function Rows(f, cur, size)
	if not f then return {} end
	local rows = {}
	local function Add(label, value, src)
		if value == nil or value == "" then return end
		rows[#rows + 1] = { label = label, value = value, tag = Card.ValueTag(label, src) }
	end
	-- The event pane's card (compact, the owner's call 2026-09-30): one fact a line, words that
	-- fit its column, no source word after them: class · level, the record, the division.
	if size == "compact" then
		local cl = {}
		if f.class then cl[#cl + 1] = ArenaUI.ClassWord and ArenaUI.ClassWord(f.class) or f.class end
		if f.level then cl[#cl + 1] = tostring(f.level) end
		if #cl > 0 then rows[#rows + 1] = { label = "class", value = table.concat(cl, " · "), tag = "" } end
		if f.record then rows[#rows + 1] = { label = "record", value = (L.ARENA_CARD_RECORD or "Record") .. " " .. f.record, tag = "" } end
		if f.tier then rows[#rows + 1] = { label = "tier", value = L["ARENA_TIER_" .. tostring(f.tier):upper()] or tostring(f.tier), tag = "" } end
		if f.openBet then rows[#rows + 1] = { label = "debt", value = L.ARENA_OPEN_BET, tag = "" } end
		return rows
	end
	Add("title", f.title and ns.Codec.Plain(f.title) or nil, f.titleSrc)
	-- (His guild rank as his roster names it, the patent of the owner's UFC card: plain, cut short.)
	Add("rank", f.guildRank and ns.Cut(ns.Codec.Plain(f.guildRank), 24) or nil, f.guildRankSrc)
	local classLevel = {}
	if f.class then classLevel[#classLevel + 1] = ArenaUI.ClassWord and ArenaUI.ClassWord(f.class) or f.class end
	if f.level then classLevel[#classLevel + 1] = tostring(f.level) end
	Add("class", #classLevel > 0 and table.concat(classLevel, " · ") or nil, f.classSrc or f.levelSrc)
	if size ~= "compact" then Add("race", ArenaUI.RaceWord and ArenaUI.RaceWord(f.race) or f.race, f.raceSrc) end
	if f.rating then
		local now, peak = math.floor(f.rating + 0.5), f.peak and math.floor(f.peak + 0.5) or nil
		Add("rating", peak and peak > now and L.ARENA_CARD_RATING_PEAK:format(now, peak) or tostring(now), f.ratingSrc)
	end
	Add("record", f.record, f.recordSrc)
	if size ~= "compact" then
		-- (Fled and the streak only when there is one: a zero is no fact to compare.)
		Add("fled", f.fled and f.fled > 0 and tostring(f.fled) or nil, nil)
		if f.streak and f.streak ~= 0 then
			Add("streak", f.streak > 0 and Kit.C("green", "W" .. f.streak) or Kit.C("red", "L" .. -f.streak), nil)
		end
		Add("last5", f.last5, nil)
		Add("ko", f.ko and (f.ko .. "%") or nil, nil)
		Add("dur", f.avgDur and Home.Clock(f.avgDur) or nil, nil)
	end
	if f.tier then Add("tier", Kit.TierMark(f.tier, size == "compact" and 13 or 16) .. " " .. (L["ARENA_TIER_" .. tostring(f.tier):upper()] or f.tier), "ledger") end
	if f.odds then Add("odds", ("%.2fx · %s · %d"):format(f.odds, Kit.Money(f.pool or 0, cur), f.count or 0), nil) end
	if f.openBet then Add("debt", L.ARENA_OPEN_BET, nil) end
	return rows
end
Card.Rows = Rows
Card.LABELS = { title = "ARENA_CARD_TITLE_ROW", rank = "ARENA_CARD_GUILD_RANK", class = "ARENA_CARD_CLASS", race = "ARENA_CARD_RACE", rating = "ARENA_CARD_RATING",
	record = "ARENA_CARD_RECORD", fled = "ARENA_CARD_FLED", streak = "ARENA_PROF_STREAK", last5 = "ARENA_CARD_LAST5", ko = "ARENA_CARD_KO", dur = "ARENA_CARD_DUR",
	tier = "ARENA_CARD_TIER", odds = "ARENA_CARD_ODDS", debt = "ARENA_CARD_DEBT" }
-- The window's and the overlay's lines, in Rows' order: one a label.
Card.ORDER = { "title", "rank", "class", "race", "rating", "record", "fled", "streak", "last5", "ko", "dur", "tier", "odds", "debt" }

-- The two sides' rows line by line: { label, A = row or nil, B = row or nil }. Compact: each side's
-- own rows one under the other (it has no labels). The window and the overlay: one line a label,
-- wherever either side has a value, so each value sits on its own label's line even when the
-- other fighter lacks one (a title, a rank, the fled duels); the missing side shows a dash.
function Card.Lines(rowsA, rowsB, size)
	local out = {}
	rowsA, rowsB = rowsA or {}, rowsB or {}
	if size == "compact" then
		for i = 1, math.max(#rowsA, #rowsB) do out[i] = { A = rowsA[i], B = rowsB[i] } end
		return out
	end
	local byA, byB = {}, {}
	for _, r in ipairs(rowsA) do byA[r.label] = r end
	for _, r in ipairs(rowsB) do byB[r.label] = r end
	for _, label in ipairs(Card.ORDER) do
		if byA[label] or byB[label] then out[#out + 1] = { label = label, A = byA[label], B = byB[label] } end
	end
	return out
end

---------------------------------------------------------------------------
-- Drawing, at any of the three sizes
---------------------------------------------------------------------------

local ROWS_MAX = #Card.ORDER
local function Side(frame, left, px)
	local s = {}
	-- The portrait drawn as the player's own (Kit.NewPortrait); s.portrait is its square, placed below.
	s.rig = Kit.NewPortrait(frame, px)
	s.portrait = s.rig.slot
	s.source = Kit.Text(frame, "small", "CENTER")
	s.source:SetPoint("TOP", s.portrait, "BOTTOM", 0, -2)
	s.name = Kit.Text(frame, "title", left and "LEFT" or "RIGHT")
	if s.name.SetWordWrap then s.name:SetWordWrap(false) end
	s.values = {}
	for i = 1, ROWS_MAX do
		-- (One line each, cut at the column's edge: never a second line over the next row.)
		s.values[i] = Kit.Text(frame, nil, left and "LEFT" or "RIGHT")
		if s.values[i].SetWordWrap then s.values[i]:SetWordWrap(false) end
	end
	return s
end

-- The window's and the overlay's rows: the step that fits `n` lines between the names and the
-- clock (its two lines at the bottom), never more than the size's own step; anchored again only
-- when it changes.
local function PlaceRows(c, frame, n)
	local room = Card.SIZES[c.size][2] + c.rowsTop - 50
	local step = math.max(14, math.min(c.maxStep, math.floor(room / math.max(1, n))))
	if rawget(c, "step") == step then return step end
	c.step = step
	for i = 1, ROWS_MAX do
		local y = c.rowsTop - (i - 1) * step
		local a, b, l = c.A.values[i], c.B.values[i], c.labels[i]
		a:ClearAllPoints(); b:ClearAllPoints(); l:ClearAllPoints()
		a:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y); a:SetHeight(step)
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y); b:SetHeight(step)
		l:SetPoint("TOP", frame, "TOP", 0, y); l:SetHeight(step)
	end
	return step
end
Card.PlaceRows = PlaceRows

-- Builds (once) and fills `frame` with the card of event `id` at `size` ("compact", "window",
-- "overlay"). Returns the model it drew (nil: an empty card with its reason).
function Card.Build(frame, id, size)
	if not frame then return nil end
	size = Card.SIZES[size] and size or "compact"
	local w, h, px = unpack(Card.SIZES[size])
	local c = rawget(frame, "arenaCard")
	if not c or c.size ~= size then
		c = { size = size }
		frame.arenaCard = c
		c.bg = frame:CreateTexture(nil, "BACKGROUND")
		c.bg:SetAllPoints(frame)
		c.bg:SetColorTexture(0, 0, 0, 0)
		c.head = Kit.Text(frame, size == "compact" and "title" or "big", "CENTER")
		c.head:SetPoint("TOP", 0, size == "compact" and -4 or -10)
		c.vs = Kit.Text(frame, "big", "CENTER")
		c.vs:SetPoint("TOP", 0, size == "compact" and -60 or -90)
		c.labels = {}
		for i = 1, ROWS_MAX do
			c.labels[i] = Kit.Text(frame, "small", "CENTER")
			c.labels[i]:SetWidth(size == "compact" and 90 or 160)
		end
		c.A = Side(frame, true, px)
		c.B = Side(frame, false, px)
		local top = size == "compact" and -26 or -8
		-- (How far each portrait's art reaches past its square: kept inside the card and clear of
		-- the words. It is turned round as the player's own, so it reaches furthest to the left.)
		if size == "compact" then
			-- Two columns of a fixed width, one each side of the VS (4 + the art's reach + 44 + 8 in).
			local reach = Kit.PortraitReach(px)
			local outL, outR = reach.left, reach.right
			c.A.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 4 + outL, top)
			c.B.portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(4 + outR), top)
			c.A.name:SetPoint("TOPLEFT", c.A.portrait, "TOPRIGHT", 8 + outR, 0)
			c.B.name:SetPoint("TOPRIGHT", c.B.portrait, "TOPLEFT", -(8 + outL), 0)
			local colW = math.floor(w / 2 - 12 - (4 + outL + px + 8 + outR))
			c.A.name:SetWidth(colW)
			c.B.name:SetWidth(colW)
			for i = 1, ROWS_MAX do
				c.A.values[i]:SetPoint("TOPLEFT", c.A.name, "BOTTOMLEFT", 0, -4 - (i - 1) * 16)
				c.A.values[i]:SetWidth(colW); c.A.values[i]:SetHeight(16)
				c.B.values[i]:SetPoint("TOPRIGHT", c.B.name, "BOTTOMRIGHT", 0, -4 - (i - 1) * 16)
				c.B.values[i]:SetWidth(colW); c.B.values[i]:SetHeight(16)
				c.labels[i]:SetPoint("TOP", frame, "TOP", 0, top - 20 - (i - 1) * 16)
			end
		else
			-- The Tale of the tape and the overlay (the owner's fix, 2026-09-30: no text over text):
			-- three fixed columns from the inner width, the left fighter, the labels in the centre,
			-- the right fighter; each fighter's portrait at the top of his column and his name under
			-- it, one line, cut to the column (the whole name in the tooltip); a row a fact, the
			-- labels on the same lines.
			local gap, labelW = 12, size == "window" and 150 or 200
			local colW = math.floor((w - labelW - 2 * gap) / 2)
			local px2 = math.min(px, size == "window" and 72 or 96)
			local reach = Kit.PortraitReach(px2)
			local up, down = reach.top, reach.bottom
			Kit.SizePortrait(c.A.rig, px2); Kit.SizePortrait(c.B.rig, px2)
			c.A.portrait:SetPoint("TOP", frame, "TOPLEFT", colW / 2, top - up)
			c.B.portrait:SetPoint("TOP", frame, "TOPRIGHT", -colW / 2, top - up)
			c.A.name:SetPoint("TOP", c.A.portrait, "BOTTOM", 0, -(8 + down))
			c.B.name:SetPoint("TOP", c.B.portrait, "BOTTOM", 0, -(8 + down))
			c.A.name:SetWidth(colW); c.B.name:SetWidth(colW)
			c.A.name:SetJustifyH("CENTER"); c.B.name:SetJustifyH("CENTER")
			-- (The rows' step is set as each card fills, from how many lines it has: PlaceRows.)
			c.maxStep = size == "window" and 22 or 30
			c.rowsTop = top - up - px2 - (8 + down) - 28 - 8
			for i = 1, ROWS_MAX do
				c.A.values[i]:SetWidth(colW)
				c.B.values[i]:SetWidth(colW)
				c.labels[i]:SetWidth(labelW)
				if c.labels[i].SetWordWrap then c.labels[i]:SetWordWrap(false) end
			end
			-- (the whole name in a tooltip over it)
			for _, side in ipairs({ c.A, c.B }) do
				local hit = CreateFrame("Frame", nil, frame)
				hit:SetAllPoints(side.name)
				hit:EnableMouse(true)
				hit:SetScript("OnEnter", function(self)
					local who = rawget(side, "who")
					if not (GameTooltip and who) then return end
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:AddLine(Kit.Name(who), 1, 0.82, 0)
					GameTooltip:Show()
				end)
				hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			end
		end
		c.clock = Kit.Text(frame, size == "compact" and nil or "title", "CENTER")
		c.clock:SetPoint("BOTTOM", 0, size == "compact" and 2 or 30)
		c.delay = Kit.Text(frame, "small", "CENTER")
		c.delay:SetPoint("BOTTOM", 0, size == "compact" and -12 or 10)
		c.delay:SetWidth(w - 40)
	end
	local m = Card.Model(id)
	ArenaUI.lastCard = m
	if not m then
		c.head:SetText(Kit.C and Kit.C("grey", L.ARENA_CARD_EMPTY) or L.ARENA_CARD_EMPTY)
		c.vs:SetText("")
		for _, side in ipairs({ c.A, c.B }) do
			side.portrait:Hide()
			side.source:SetText("")
			side.name:SetText("")
			for _, v in ipairs(side.values) do v:SetText("") end
		end
		for _, l in ipairs(c.labels) do l:SetText("") end
		c.clock:SetText("")
		c.delay:SetText("")
		Kit.StopCountdown(c.clock)
		return nil
	end
	-- (the Tale of the tape's title is its frame's, once; the overlay's head is the state)
	c.head:SetText(size == "compact" and m.state or (size == "overlay" and m.state or ""))
	c.vs:SetText(size == "compact" and L.ARENA_VS_WORD or "")
	-- The labels down the middle (the window and overlay), each side's value on its label's line.
	local lines = Card.Lines(Rows(m.A, m.cur, size), Rows(m.B, m.cur, size), size)
	if size ~= "compact" then PlaceRows(c, frame, #lines) end
	for i, l in ipairs(c.labels) do
		local line = lines[i]
		l:SetText(size ~= "compact" and line and (L[Card.LABELS[line.label]] or line.label) or "")
	end
	for key, side in pairs({ A = c.A, B = c.B }) do
		local f = m[key]
		if f then
			side.portrait:Show()
			Card.SetPortrait(side.rig.portrait, f.name, f.emblem, f.classFile, Kit.Square(side.rig))
			Kit.SetPortraitFrame(side.rig, f.name, f.guild, f.honour)
			side.source:SetText("")
			side.who = f.name
			side.name:SetText(Kit.Colored(f.name, f.classFile))
			for i, v in ipairs(side.values) do
				local line = lines[i]
				local r = line and line[key]
				if r then v:SetText(r.value .. (r.tag ~= "" and (" " .. (Kit.C and Kit.C("grey", r.tag) or r.tag)) or ""))
				else v:SetText(line and size ~= "compact" and Kit.C("grey", "-") or "") end
			end
		else
			side.portrait:Hide()
			side.source:SetText("")
			side.name:SetText(L.ARENA_CARD_OPEN_SLOT)
			for _, v in ipairs(side.values) do v:SetText("") end
		end
	end
	if m.lockAt and m.lockAt > ns.Arena.Now() and not m.ev.over then
		Kit.Countdown(c.clock, m.lockAt, L.ARENA_BETS_CLOSE_IN, L.ARENA_BETS_CLOSED)
	else
		Kit.StopCountdown(c.clock)
		c.clock:SetText(m.ev.winner and L.ARENA_RESULT_WINS:format(Kit.Name(m.ev.winner)) or "")
	end
	c.delay:SetText(m.delay or "")
	return m
end

---------------------------------------------------------------------------
-- The window: Tale of the tape (660 x 580)
---------------------------------------------------------------------------

local window
-- (580 high with the fuller card, 2026-10-04: the panel 24 px over the card, the Copy row below.)
local WINDOW_W, WINDOW_H = 660, 580
Card.WINDOW_W, Card.WINDOW_H = WINDOW_W, WINDOW_H
function Card.ApplyWindowScale()
	if not window then return nil end
	return Kit.FitWindow(window, WINDOW_W, WINDOW_H, 1)
end
function Card.Open(id)
	if not window then
		-- (The card in the same inset panel as in the event pane, 12 px inside it, 2026-09-30.)
		window = Kit.Frame("OlympusArenaCard", WINDOW_W, WINDOW_H, { title = L.ARENA_TALE_TITLE, point = { "CENTER", 0, 30 } })
		window.onShow = Card.ApplyWindowScale
		local panel = CreateFrame("Frame", nil, window)
		panel:SetPoint("TOPLEFT", 20, -52)
		panel:SetSize(620, Card.SIZES.window[2] + 24)
		window.inset = Kit.Inset(panel)
		window.body = CreateFrame("Frame", nil, panel)
		window.body:SetPoint("TOPLEFT", 12, -12)
		window.body:SetSize(Card.SIZES.window[1], Card.SIZES.window[2])
		window.copy = Kit.Button(window, 110, 24, L.ARENA_BTN_COPY, function() Kit.Copy(L.ARENA_TALE_TITLE, Card.CopyText(window.id)) end)
		window.copy:SetPoint("BOTTOMRIGHT", -16, 14)
		ns.On("ARENA_CHANGED", function() if window:IsShown() then ns.SafeCall("arena card", Card.Build, window.body, window.id, "window") end end)
		local function DisplayChanged() if window then Card.ApplyWindowScale() end end
		for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
			pcall(ns.RegisterEvent, event, DisplayChanged)
		end
	end
	window.id = id
	window:Show()
	Card.ApplyWindowScale()
	Card.Build(window.body, id, "window")
	return window
end
function Card.Window() return window end

-- The card as text (its Copy): names, numbers and fixed words.
function Card.CopyText(id)
	local m = Card.Model(id)
	if not m then return "" end
	local out = { m.title }
	for _, key in ipairs({ "A", "B" }) do
		local f = m[key]
		if f then
			local parts = {}
			for _, r in ipairs(Rows(f, m.cur, "window")) do parts[#parts + 1] = (L[Card.LABELS[r.label]] or r.label) .. ": " .. r.value end
			out[#out + 1] = Kit.Name(f.name) .. " | " .. table.concat(parts, " | ")
		end
	end
	return Kit.Plain(table.concat(out, "\n"))
end

-- Portraits follow their units (at most once a second): the events registered the first time a
-- card with a live portrait shows.
local watching, soon = false, false
function Card.Watch()
	if watching then return end
	watching = true
	local function Again()
		if soon then return end
		soon = true
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				soon = false
				if window and window:IsShown() then ns.SafeCall("arena card", Card.Build, window.body, window.id, "window") end
				if ArenaUI.IsShown and ArenaUI.IsShown() then ArenaUI.Refresh() end
			end)
		else
			soon = false
		end
	end
	for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
		pcall(ns.RegisterEvent, event, Again)
	end
end
