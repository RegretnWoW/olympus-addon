local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): FarkleBoard.lua, Bones's window (the rules'
-- "Farkle": the code keeps its Farkle names, the screens say Bones). the Bones tables, the design, the
-- farkle section's page (11) as the design change it, built after the owner's
-- playable lab preview (the tavern table seen from above, the bone dice, the "How to play" guide).
--
-- What it draws (each thing in its own area, nothing overlapping):
--   - the table: the parchment tavern table (media/farkle/table.tga) in two halves, the other
--     player's row on the top plank and this player's on the bottom one (his name, a small line
--     under it, his tray of dice set aside, his points on the right; a mug on a hiccup table),
--     the game's column on the right (name, target and round, How to play and Sit down, what to do,
--     the buttons, the last two lines of the log);
--   - the dice: six bone dice a player (faces.tga 6 faces x 4 turns, tumble.tga 16 frames, drawn at
--     twice the die's edge, never rotated: the shadow is baked in), each in its own lane: thrown
--     from the player's edge forward into its own slot in about a second (the tumble a FlipBook),
--     a picked die lifted and lit on itself (no ring), the dice set aside moving to the tray and
--     shrinking there, the points counting up; the game's own sounds (SND), feature-detected;
--   - the steps: the "Play to" setup (dark ink straight on the table), the create panel (the
--     opponent, the target, the stake, the mode, the turn timer, spectators, a sober table), the
--     invitation and the arbiter's pop-ups, the waiting lines (the party, the tavern, the opening
--     rolls, the stakes), the game, the result card (the design);
--   - How to play: a pop-up of its own, centred on the screen above the table's strata, on the
--     game's parchment, four pages (Rules, Scores, Examples, Drink), every number and example from
--     FarkleRules; shown by itself the first time the table opens, and on "How to play";
--   - the lesson (1.1.6): an innkeeper practice game with Show tips checked says,
--     in the column, what the rules make of the dice in front of the player: which dice of a throw
--     score and for how much, what is at stake, the chance of BONES! with the dice left, hot dice,
--     a bust and a bank (Board.Lesson, Board.BustChance: FarkleRules alone).
-- Everything the table does goes through ns.FarkleTable (the core: the protocol, the witnessing,
-- the clocks, the stakes) and its actions (Arena.Can/Do "farkle.*"); this file only draws,
-- animates, sounds and asks. It reads FarkleTable.View(id) and animates FARKLE_EVENT (id, info) and
-- FARKLE_TABLE (id, state).
--
-- The rules every companion file keeps: frames named OlympusArena... (so /oly photo keeps them);
-- animation with AnimationGroup and FlipBook only (a short C_Timer ticker counts numbers up and
-- steps the tumble where the client has no FlipBook); no game popup; Escape only through
-- ns.EscapeCloses; no edit box; closes in combat and comes back after it while a table is live.
--
-- API (the hub's and the core's way in, the screens' panes call it):
--   ArenaUI.Farkle(what, id, extra)   what: "board" (the table, or the setup when there is none),
--     "practice" (extra.target: start at once), "guide", "create" (extra: the prefill, below),
--     "invite" and "arbiter" (the pop-ups for table id), "watch" (a watched table), "sim"
--     (the practice setup), "result" (the result card of table id)
--   ArenaUI.FarkleCreate(prefill)     the create panel; prefill = { guest, stake (copper), target,
--     practice (true: no stake; with no guest, the practice setup against the House), from (the
--     match id, the design), mode, arbiter, src, secs, spectators, hic (false: a sober table) }
--   ArenaUI.FarkleBoard               this file's table (Open, Close, IsOpen, Busy; _ for tests)
-- One game's window at a time (the design): opening it fires ns.Fire("ARENA_GAME_SHOWN", "farkle"),
-- and an ARENA_GAME_SHOWN with another game's key (the Lottery's window fires "lottery") closes it.
-- It sets ns.FarkleTable.busy(id) (the House waits while the dice move).
-- The result card (the design) is the UI kit's where the screens builds one: ArenaUI.ResultCard(spec) with
--   spec = { game = "farkle", verdict = "won"|"lost"|"back", line, bet, won, lost, feeLine,
--   balanceLine, points = { mine, theirs } (practice and unstaked games), buttons = { { label, fn } },
--   onClose }; until then this file shows the same card itself.
local ArenaUI = own.ArenaUI
local L = ns.L

local Board = {}
ArenaUI.FarkleBoard = Board

local function FT() return ns.FarkleTable end
local function FR() return ns.FarkleRules end
local function A() return ns.Arena end

local abs, floor, min, max, random = math.abs, math.floor, math.min, math.max, math.random

local MEDIA = "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"
local W, H = 800, 400             -- the table: 1024 x 512 shown at 800 x 400
local ACTION_H = 56              -- shared Games.Bar below the unchanged 400px table
local SPLIT = 197                 -- the line between the far half (above) and the near one
local COLX = 606                  -- the column's left edge
local CX, LANE = 300, 84          -- the lanes' centre and spacing: a die never leaves its lane
local D, K, SW = 44, 22, 24       -- a die's edge in play, in the tray, and on its way there
local EDGE = { 292, 102 }         -- a side's hand, where its throws start (1 = near, 2 = far)
local REST = { 240, 156 }         -- where its dice come to rest
local BAND = { 306, 88 }          -- the band its dice set aside cross on their way to the tray
local TRAY = { 366, 31 }          -- its tray and its points, in its row
local TRAYX, TRAYSTEP = 318, 30   -- the tray's first slot and the step between slots
local ROW = { 332, 0 }            -- the top of its row
local HAND = 1.1                  -- a die in the hand is drawn this much bigger (it is in the air)
local GATHER = { slide = 0.16, appear = 0.12, fade = 0.24 }
local FLIGHT = 0.8                -- a throw's flight (plus up to 0.06, and its start's stagger)
-- Where each thing may be (x, y, right, bottom), for the layout and for the offline tests.
local AREAS = {
	farRow = { 0, 0, COLX, 62 }, nearRow = { 0, 332, COLX, H },
	farHalf = { 0, 62, COLX, SPLIT }, nearHalf = { 0, SPLIT, COLX, 332 }, column = { COLX, 0, W, H },
	footer = { 0, H, W, H + ACTION_H },
}
-- Ink on the wood: dark, with a light edge under it so small text stands off the grain.
local INK, SOFT = { 0.15, 0.07, 0.02 }, { 0.27, 0.15, 0.05 }
local RED, AMBER, GREEN = { 0.66, 0.07, 0.04 }, { 0.78, 0.38, 0.02 }, { 0.16, 0.34, 0.06 }
local GOOD, BAD = "|cff175208", "|cff8c0c04"

-- The table's sounds: SoundKits this client's own tables list (checked against the 1.60.1.70124
-- SoundKit and SoundKitEntry tables and the community listfile). The first three are Forever's
-- dice (the Crapshoot spell's); a client without them plays nothing (PlaySound says no).
local SND = {
	shake = 349216,  -- sound/spell/crapshoot_precaststart_loop (5 takes, repeats until stopped): dice in the hand
	throw = 349217,  -- fx_whoosh_small_revamp (10 takes): the toss
	hit = 349221,    -- 10.0_magic_earth_small_stone_impact (9 takes): a die striking the table
	pick = 1204,     -- interface/pickup/putdowngems: a die picked
	unpick = 1221,   -- interface/pickup/pickupgems: a die put back
	tally = 120,     -- interface/lootcoinsmall (LOOT_WINDOW_COIN_SOUND): points counted
	bank = 287276,   -- interface/lootcoinlarge: a turn banked
	farkle = 847,    -- interface/igquestfailed: BONES! (nothing scored), a foul
	win = 878,       -- interface/iquestcomplete: you win
	lose = 846,      -- interface/igquestfailed, the quieter kit: the other player wins
}
-- The mug of a hiccup table (the design): the game's own ale icons, the first this client has.
local MUGS = { "Interface\\Icons\\INV_Drink_04", "Interface\\Icons\\INV_Drink_05", "Interface\\Icons\\INV_Misc_QuestionMark" }
local FILL = { [0] = 0, 0.25, 0.5, 1 } -- the mug's fill by level: empty, a quarter, half, full

-- The board's state: the table shown (id), which seat sits on the near side, the dice of each
-- side, the event queue, and what the column says.
local S = { gen = 0, target = 5000, practiceTips = false, sel = {}, last = {}, hits = { 0, 0 }, shake = {}, flying = { 0, 0 }, hand = { 0, 0 }, ready = { 0, 0 },
	queue = {}, sound = true, mode = "setup", near = 1, logs = {} }
local win, shell, banner, help, setup, create, info, primary, bankBtn, extraBtn, ask, card, esc
local rows, targets, tallies = {}, {}, {}
local sides = {}      -- [side] = { dice = { six dice }, play = { die index by roll position }, kept = { die index }, fresh = bool }
local counters = {}
local Refresh, Pump, Sync, ShowCard -- (below)

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Num(n)
	local s, k = tostring(floor(tonumber(n) or 0)), 0
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
local function Money(c)
	local F = FT()
	if F and F.Money then return F.Money(c) end
	return tostring(c)
end
local function Name(n) return n and (ns.DisplayName(n) or n) or "?" end
local function Call(mod, fn, ...)
	local m = rawget(ns, mod) or ns[mod]
	local f = type(m) == "table" and m[fn]
	if type(f) ~= "function" then return nil end
	local ok, a, b, c = pcall(f, ...)
	if not ok then return nil end
	return a, b, c
end
-- Whether a game between players is for points only (1.1.6: the compliance gate allows no stake):
-- its words then say points, never a stake (the create panel, the invitation, the result card).
local function ForPoints() return Call("Compliance", "Waits", "stake", "bones", true) ~= nil end
local function Now() return GetTime and GetTime() or 0 end
local function Say(text) if text then ns.Print(text) end end
local function T(key, ...)
	local fmt = L[key] or key
	if select("#", ...) == 0 then return fmt end
	local ok, text = pcall(string.format, fmt, ...)
	return ok and text or fmt
end

-- Morpheus has Latin letters only: another script (a Cyrillic or an Asian name) gets the game's
-- own font for it, or the text would show empty boxes.
local function FontFor(text)
	if type(text) == "string" and text:find("[\198-\255]") then
		if text:find("[\208\209]") and GetLocale and GetLocale() == "ruRU" then return "Fonts\\MORPHEUS_CYR.TTF" end
		return STANDARD_TEXT_FONT
	end
	return MORPHEUS
end
local function SetFont(fs, font, size, flags)
	if not fs:SetFont(font, size, flags or "") then fs:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end
local function Text(parent, size, color, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	SetFont(fs, font or STANDARD_TEXT_FONT, size)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowColor(1, 0.94, 0.8, 0.6); fs:SetShadowOffset(1, -1)   -- pressed into the wood
	if justify then fs:SetJustifyH(justify) end
	return fs
end
local function Place(region, x, y, point)
	region:ClearAllPoints()
	region:SetPoint(point or "TOPLEFT", win, "TOPLEFT", x, -y)
end
local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h); b:SetText(label)
	b:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
	b:SetScript("OnClick", fn)
	return b
end
local function Set(b, label, on)
	b:SetText(label)
	if on then b:Enable() else b:Disable() end
end
-- A tick box of the board's own (the game's templates differ between clients): a small button
-- with the game's check art and its label in dark ink.
local function Check(parent, label, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(210, 32)
	b.box = b:CreateTexture(nil, "ARTWORK")
	b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up"); b.box:SetSize(26, 26); b.box:SetPoint("LEFT", 0, 0)
	b.tick = b:CreateTexture(nil, "OVERLAY")
	b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); b.tick:SetSize(26, 26); b.tick:SetPoint("LEFT", 0, 0)
	b.label = Text(b, 13, INK, nil, "LEFT")
	b.label:SetPoint("LEFT", b, "LEFT", 30, 0); b.label:SetWidth(178); b.label:SetWordWrap(false)
	b.label:SetText(label)
	b.checked = false
	b.tick:Hide()
	function b.SetOn(self, on) self.checked = on and true or false; self.tick:SetShown(self.checked) end
	b:SetScript("OnClick", function(self) self:SetOn(not self.checked); if fn then fn(self.checked) end end)
	return b
end

---------------------------------------------------------------------------
-- Sound: the SFX channel, one of a kind at a time, never more than three at once
---------------------------------------------------------------------------

local played = {}
local function Sound(key)
	if not S.sound or type(PlaySound) ~= "function" or not SND[key] then return nil end
	local now, busy = Now(), 0
	if played[key] and now - played[key] < 0.07 then return nil end
	for _, t in pairs(played) do if now - t < 0.12 then busy = busy + 1 end end
	if busy >= 3 then return nil end
	played[key] = now
	local ok, willPlay, handle = pcall(PlaySound, SND[key], "SFX")
	if ok and willPlay then return handle end
	return nil
end
local function StopShake(side)
	local h = S.shake[side]
	S.shake[side] = nil
	if h and type(StopSound) == "function" then pcall(StopSound, h, 150) end
end
-- The dice rattle in the hand until the throw (at most a few seconds: the loop never outlives it).
local function StartShake(side)
	if S.shake[side] or type(StopSound) ~= "function" then return end
	local h = Sound("shake")
	if not h then return end
	S.shake[side] = h
	C_Timer.After(4, function() if S.shake[side] == h then StopShake(side) end end)
end

-- fn after t seconds, unless the table shown changed or the window closed meanwhile.
local function After(t, fn)
	local gen = S.gen
	C_Timer.After(max(0, t), function() if gen == S.gen and win and win:IsShown() then fn() end end)
end

---------------------------------------------------------------------------
-- The bone sprite dice (media/farkle): faces.tga (6 faces x 4 turns), tumble.tga (16 frames), drawn
-- at twice the die's edge. The tumble is a FlipBook where the client has one, else a ticker steps
-- its cells while a die tumbles. A die picked lights up on itself: the same face cell again, added
-- in a warm colour, and it lifts a little. No ring.
---------------------------------------------------------------------------

local flipBook   -- true, false: whether the client made a FlipBook
local tumbling = {} -- dice tumbling without a FlipBook: the ticker steps them
local tumbleTicker
local function TumbleStep()
	local any = false
	for d in pairs(tumbling) do
		if d.air and d.f:IsShown() then
			any = true
			d.frame = ((d.frame or d.i * 5) + 1) % 16
			local c, r = d.frame % 4, floor(d.frame / 4)
			d.f.tumble:SetTexCoord(c / 4, (c + 1) / 4, r / 4, (r + 1) / 4)
		else
			tumbling[d] = nil
		end
	end
	if not any and tumbleTicker then tumbleTicker:Cancel(); tumbleTicker = nil end
end
local function Tumble(d, on)
	local f = d.f
	if on then
		f.face:Hide(); f.lit:Hide(); f.tumble:Show()
		if f.flip then
			if not f.flip:IsPlaying() then f.flip:Play() end
		else
			tumbling[d] = true
			if not tumbleTicker then tumbleTicker = C_Timer.NewTicker(0.04, TumbleStep) end
		end
	else
		if f.flip then f.flip:Stop() end
		tumbling[d] = nil
		f.tumble:Hide(); f.face:Show()
	end
end

local function NewSprite(parent)
	local f = CreateFrame("Button", nil, parent)
	f.face = f:CreateTexture(nil, "ARTWORK"); f.face:SetAllPoints(); f.face:SetTexture(MEDIA .. "faces")
	f.lit = f:CreateTexture(nil, "ARTWORK", nil, 1); f.lit:SetAllPoints(); f.lit:SetTexture(MEDIA .. "faces")
	f.lit:SetBlendMode("ADD"); f.lit:SetVertexColor(1, 0.74, 0.4); f.lit:Hide()
	f.tumble = f:CreateTexture(nil, "ARTWORK"); f.tumble:SetAllPoints(); f.tumble:SetTexture(MEDIA .. "tumble"); f.tumble:Hide()
	local ok = pcall(function()
		local ag = f.tumble:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local fb = ag:CreateAnimation("FlipBook")
		fb:SetFlipBookRows(4); fb:SetFlipBookColumns(4); fb:SetFlipBookFrames(16)
		fb:SetFlipBookFrameWidth(0); fb:SetFlipBookFrameHeight(0)
		fb:SetDuration(0.56 + random() * 0.12)
		f.flip = ag
	end)
	if flipBook == nil then flipBook = ok end
	if not ok then f.flip = nil end
	-- The moves: one group, reconfigured for each leg (a Translation, a Scale and an Alpha).
	pcall(function()
		local g = f:CreateAnimationGroup()
		local m = { g = g, tr = g:CreateAnimation("Translation"), sc = g:CreateAnimation("Scale"), al = g:CreateAnimation("Alpha") }
		f.move = m
		local p = f:CreateAnimationGroup()
		local s = p:CreateAnimation("Scale")
		f.pop = { g = p, sc = s }
	end)
	f:EnableMouse(false)
	f:Hide()
	return f
end

-- A die: where it is (x, y from the table's top left, y down), its edge (size), alpha, the value
-- it shows, where it lies ("hand", "air", "lane", "tray", "hidden"). The moves are AnimationGroups
-- (Leg), the frame re-anchored where each leg ends.
local function Draw(d)
	local f = d.f
	if d.alpha <= 0.01 and not d.moving then f:Hide() return end
	local still = not d.moving and d.where == "lane"
	local up = still and (d.lit and 4 or d.hover and 2) or 0
	local grow = still and (d.lit and 1.06 or d.hover and 1.03) or 1
	local s = d.size * grow
	f:ClearAllPoints()
	f:SetPoint("CENTER", win, "TOPLEFT", d.x, -(d.y - up))
	f:SetSize(2 * s, 2 * s)
	f:SetHitRectInsets(s / 2, s / 2, s / 2, s / 2)   -- the die itself, not its shadow
	f:SetAlpha(max(0, min(1, d.alpha)))
	f:Show()
	if d.air then
		if not f.air then f.air = true; Tumble(d, true) end
		return
	end
	if f.air ~= false then f.air = false; Tumble(d, false) end
	local l, r, t, b = (d.value - 1) / 8, d.value / 8, (d.variant - 1) / 4, d.variant / 4
	f.face:SetTexCoord(l, r, t, b)
	local glow = (not d.dull) and (d.lit and 0.42 or d.hover and 0.2) or 0
	if glow > 0 then f.lit:SetTexCoord(l, r, t, b); f.lit:SetAlpha(glow); f.lit:Show() else f.lit:Hide() end
	-- a bust's dice go dull (grey bone), the red is for the banner
	local dull = d.dull and true or false
	if f.dull ~= dull then
		f.dull = dull
		f.face:SetDesaturated(dull)
		if dull then f.face:SetVertexColor(0.74, 0.69, 0.63) else f.face:SetVertexColor(1, 1, 1) end
	end
end

-- Plays one leg of a die's way: from where it is drawn now to (x, y), its edge `size` and `alpha`,
-- over `dur` seconds after `delay`, then done(). The frame stays anchored where the leg starts
-- while the group plays and is anchored where it ends once it finished, so every leg ends exactly
-- in its place whatever the client does between the animations of a group.
local function Leg(d, o, done)
	local x0, y0, s0, a0 = d.x, d.y, d.size, d.alpha
	local x1, y1, s1, a1 = o.x or x0, o.y or y0, o.size or s0, o.alpha or a0
	d.leg = (d.leg or 0) + 1
	local token, gen = d.leg, S.gen
	local finished = false
	local function Finish()
		if finished or d.leg ~= token or gen ~= S.gen then return end
		finished = true
		d.moving = nil
		d.x, d.y, d.size, d.alpha = x1, y1, s1, a1
		Draw(d)
		if done and gen == S.gen then done() end
	end
	d.moving = true
	Draw(d)
	local m = d.f.move
	local dur, delay = o.dur or 0, o.delay or 0
	if not m or dur + delay <= 0 then return Finish() end
	local ok = pcall(function()
		m.g:Stop()
		m.tr:SetOffset(x1 - x0, -(y1 - y0))
		m.tr:SetDuration(dur); m.tr:SetStartDelay(delay); m.tr:SetSmoothing(o.smooth or "NONE")
		local r = s0 > 0 and s1 / s0 or 1
		if m.sc.SetScaleFrom then m.sc:SetScaleFrom(1, 1); m.sc:SetScaleTo(r, r) else m.sc:SetScale(r, r) end
		m.sc:SetDuration(o.sdur or dur); m.sc:SetStartDelay(delay); m.sc:SetSmoothing(o.smooth or "NONE")
		m.al:SetFromAlpha(a0); m.al:SetToAlpha(a1)
		m.al:SetDuration(dur); m.al:SetStartDelay(delay)
		m.g:SetScript("OnFinished", Finish)
		m.g:Play()
	end)
	if not ok then
		-- (no animations on this client: it jumps there when the leg would have ended)
		C_Timer.After(dur + delay, Finish)
	else
		-- A lost OnFinished must not leave the dice flying and the table busy forever.
		C_Timer.After(dur + delay + 0.1, function()
			if finished or d.leg ~= token or gen ~= S.gen then return end
			pcall(m.g.Stop, m.g)
			Finish()
		end)
	end
end
-- Stops a die where its leg is going (a new plan replaces it).
local function Still(d)
	d.leg = (d.leg or 0) + 1
	d.moving, d.gathering = nil, nil
	if d.f.move then pcall(function() d.f.move.g:Stop() end) end
end
-- A small settle when a die comes to rest (1.06 to 1), where the client scales from a value.
local function Pop(d)
	local p = d.f.pop
	if not p or not p.sc.SetScaleFrom then return end
	pcall(function()
		p.g:Stop()
		p.sc:SetScaleFrom(1.06, 1.06); p.sc:SetScaleTo(1, 1); p.sc:SetDuration(0.12)
		p.g:Play()
	end)
end

---------------------------------------------------------------------------
-- Numbers that count, the points over the dice, the banner
---------------------------------------------------------------------------

local function Ease(u) return 1 - (1 - u) ^ 3 end

-- Numbers on the table count up (or down) to their new value: a ticker of its own for that count,
-- gone when it arrives.
local function Count(key, fs, to, fmt, dur)
	local c = counters[key]
	if c and c.fs == fs and c.to == to then
		c.fmt = fmt
		if not c.ticker then fs:SetText(fmt(c.now)) end
		return
	end
	if c and c.ticker then c.ticker:Cancel() end
	local from = c and c.fs == fs and c.now or to
	if from == to or not dur or not (win and win:IsShown()) then
		counters[key] = { fs = fs, to = to, now = to, fmt = fmt }
		fs:SetText(fmt(to))
		return
	end
	c = { fs = fs, from = from, to = to, now = from, fmt = fmt, t0 = Now(), dur = dur }
	counters[key] = c
	fs:SetText(fmt(from))
	local steps = max(1, floor(dur / 0.04 + 0.5))
	c.ticker = C_Timer.NewTicker(0.04, function()
		local u = min(1, (Now() - c.t0) / c.dur)
		c.now = floor((c.from + (c.to - c.from) * Ease(u)) / 10 + 0.5) * 10
		if u >= 1 then c.now = c.to end
		c.fs:SetText(c.fmt(c.now))
		if c.now == c.to and c.ticker then c.ticker:Cancel(); c.ticker = nil end
	end, steps + 2)
end

-- The points of the dice set aside, over them: "+0" counting up, rising and fading.
local function Tally(pts, list)
	if not list[1] then return end
	local mx = 0
	for _, d in ipairs(list) do mx = mx + d.x end
	mx = mx / #list
	local at
	for _, d in ipairs(list) do if not at or abs(d.x - mx) < abs(at.x - mx) then at = d end end
	local t
	for _, e in ipairs(tallies) do if not e.busy then t = e break end end
	t = t or tallies[1]
	t.busy = true
	t.fs:ClearAllPoints()
	t.fs:SetPoint("CENTER", win, "TOPLEFT", at.x, -(at.y - 4))
	t.fs:SetAlpha(1); t.fs:Show()
	local key, fmt = "tally" .. tostring(t.k), function(n) return "+" .. Num(n) end
	counters[key] = nil
	Count(key, t.fs, 0, fmt)
	Count(key, t.fs, pts, fmt, 0.4)
	if t.anim then pcall(function() t.anim.g:Stop(); t.anim.g:Play() end) end
	local gen = S.gen
	C_Timer.After(1.1, function() t.busy = nil; if gen == S.gen then t.fs:Hide() end end)
	Sound("tally")
end

local function Banner(text, color, stay, duration, subtitle, subtitleColor)
	banner.text:SetText(text); banner.text:SetTextColor(color[1], color[2], color[3])
	banner.subtitle:SetText(subtitle or "")
	banner.subtitle:SetShown(subtitle ~= nil)
	local subColor = subtitleColor or SOFT
	banner.subtitle:SetTextColor(subColor[1], subColor[2], subColor[3])
	banner:SetAlpha(1); banner:Show()
	banner.stay = stay and true or false
	banner.shownAt = Now()
	local a = banner.anim
	if a then pcall(function() a.fade:Stop(); a.show:Stop(); a.show:Play() end) end
	if not stay then
		duration = duration or 1.6
		local gen, at = S.gen, banner.shownAt
		C_Timer.After(max(0, duration - 0.42), function()
			if gen ~= S.gen or banner.shownAt ~= at or banner.stay then return end
			if a then pcall(function() a.fade:Play() end) end
		end)
		C_Timer.After(duration, function() if gen == S.gen and banner.shownAt == at and not banner.stay then banner:Hide() end end)
	end
end

local function Log(text)
	if not text or text == "" then return end
	S.logs[2] = S.logs[1]
	S.logs[1] = text
	if win then
		win.logs[1]:SetText(S.logs[1] or "")
		win.logs[2]:SetText(S.logs[2] or "")
	end
end

---------------------------------------------------------------------------
-- Seats and sides: this player sits on the near side (a watcher or the arbiter sees the host there)
---------------------------------------------------------------------------

local function View() return S.id and FT() and FT().View(S.id) or nil end
local function SideOf(seat) return seat == S.near and 1 or 2 end
local function SeatOf(side) return side == 1 and S.near or (3 - S.near) end
local function LaneX(i) return CX + (i - 3.5) * LANE end

local function Vanish(d)
	Still(d)
	d.where, d.alpha, d.lit, d.hover, d.dull, d.air = "hidden", 0, nil, nil, nil, nil
	Draw(d)
end

-- A side's turn starts afresh: all six dice in play, none set aside.
local function Fresh(side)
	local sd = sides[side]
	sd.play, sd.kept, sd.fresh = { 1, 2, 3, 4, 5, 6 }, {}, nil
	if side == 1 then S.sel = {} end
end

---------------------------------------------------------------------------
-- Throws and dice set aside
---------------------------------------------------------------------------

-- A die goes into its side's hand at the start of its lane: from its lane it slides there, from
-- the tray it fades out and appears there, a hidden one appears there. Returns when it is there.
local function Hand(d, delay, done)
	local side = d.side
	local hx, hy = LaneX(d.i), EDGE[side]
	local via = d.where == "tray" and "fade" or ((d.where == "lane" and d.alpha > 0.05) and "slide" or "appear")
	d.lit, d.hover, d.dull = nil, nil, nil
	Still(d)
	d.gathering = true
	local function InHand()
		d.gathering = nil
		d.where, d.air = "hand", true
		Draw(d)
		-- shaken there until the throw: a small jiggle of its own
		if d.f.shake then pcall(function() d.f.shake:Play() end) end
		if done then done() end
	end
	if via == "slide" then
		d.air = false
		Leg(d, { x = hx, y = hy, size = D * HAND, dur = GATHER.slide, delay = delay, smooth = "IN_OUT" }, InHand)
	elseif via == "fade" then
		Leg(d, { alpha = 0, dur = GATHER.fade / 2, delay = delay }, function()
			d.x, d.y, d.size, d.air = hx, hy, D * HAND, true
			Leg(d, { alpha = 1, dur = GATHER.fade / 2 }, InHand)
		end)
	else
		d.x, d.y, d.size, d.alpha, d.air = hx, hy, D * HAND, 0, true
		Leg(d, { alpha = 1, dur = GATHER.appear, delay = delay }, InHand)
	end
	return delay + GATHER[via]
end

-- The jiggle in the hand: a looping group of its own on each die.
local function Jiggle(d)
	if d.f.shake ~= nil then return end
	d.f.shake = false
	pcall(function()
		local g = d.f:CreateAnimationGroup()
		g:SetLooping("BOUNCE")
		local j = g:CreateAnimation("Translation")
		j:SetOffset(1.5, 1.5); j:SetDuration(0.05 + d.i * 0.006)
		d.f.shake = g
	end)
end
local function Unjiggle(d) if d.f.shake then pcall(function() d.f.shake:Stop() end) end end

-- A side's dice in play into the hand, shaken there until the throw.
local function Shake(side)
	local sd = sides[side]
	if sd.fresh then Fresh(side) end
	local wait = max(0, (S.ready[side] or 0) - Now())
	local ready = Now() + wait
	for _, i in ipairs(sd.play) do
		local d = sd.dice[i]
		if d.where ~= "hand" then
			Jiggle(d)
			ready = max(ready, Now() + Hand(d, wait))
		end
	end
	S.hand[side] = ready
	After(ready - Now(), function() if S.hand[side] == ready then StartShake(side) end end)
end

-- Its dice back to the cup (they fade where they are).
local function Collect(d)
	Unjiggle(d)
	if d.alpha <= 0.01 then Vanish(d) return end
	Leg(d, { alpha = 0, dur = 0.2 }, function() d.where = "hidden"; d.alpha = 0; Draw(d) end)
end

-- The throw: the dice leave the hand one after another along their own lanes, fly forward and
-- land in their own slots, showing the faces the server's roll gave. done() once all have landed.
local function Throw(side, dice, done)
	local sd = sides[side]
	if sd.fresh then Fresh(side) end
	-- the dice in play must be the roll's count (a table that skipped a step: the rest go back)
	if #sd.play ~= #dice then
		if #dice == 6 then Fresh(side) else
			local list = {}
			for _, i in ipairs(sd.play) do if #list < #dice then list[#list + 1] = i end end
			for i = 1, 6 do
				if #list >= #dice then break end
				local taken = false
				for _, j in ipairs(list) do if j == i then taken = true end end
				for _, j in ipairs(sd.kept) do if j == i then taken = true end end
				if not taken then list[#list + 1] = i end
			end
			sd.play = list
		end
	end
	local base = Now()
	for _, i in ipairs(sd.play) do
		local d = sd.dice[i]
		-- (a die already on its way into the hand goes on there: the throw waits for it)
		if d.where ~= "hand" and not d.gathering then Jiggle(d); base = max(base, Now() + Hand(d, 0)) end
	end
	base = max(base, S.hand[side] or 0)
	S.flying[side], S.hits[side] = #dice, 0
	local gen = S.gen
	After(base - Now(), function() StopShake(side); Sound("throw") end)
	for j, v in ipairs(dice) do
		local d = sd.dice[sd.play[j]]
		d.value, d.variant = v, random(4)
		local delay = (base - Now()) + (j - 1) * 0.035 + random() * 0.015
		local dur = FLIGHT + random() * 0.06
		local tx, ty = LaneX(d.i) + random(-4, 4), REST[side] + random(-3, 3)
		local function Fly()
			if gen ~= S.gen then return end
			Unjiggle(d)
			d.where, d.air = "air", true
			-- the dice strike the table at a third of the flight (three click at most), and show
			-- their faces at three quarters
			C_Timer.After(0.34 * dur, function()
				if gen ~= S.gen then return end
				if S.hits[side] < 3 and Sound("hit") then S.hits[side] = S.hits[side] + 1 end
			end)
			C_Timer.After(0.78 * dur, function()
				if gen ~= S.gen or d.where ~= "air" then return end
				d.air = false
				Draw(d)
			end)
			Leg(d, { x = tx, y = ty, size = D, dur = dur, smooth = "OUT" }, function()
				d.where, d.air = "lane", false
				Draw(d)
				Pop(d)
				S.flying[side] = S.flying[side] - 1
				if S.flying[side] == 0 and done then done() end
			end)
		end
		if d.where == "hand" and not d.moving then
			C_Timer.After(max(0, delay), Fly)
		else
			-- (still on its way into the hand: it throws once there)
			local wait = max(0, delay)
			C_Timer.After(wait, function()
				if d.moving then
					local tries = 0
					local function Try()
						tries = tries + 1
						if not d.moving or tries > 20 then return Fly() end
						C_Timer.After(0.05, Try)
					end
					return Try()
				end
				Fly()
			end)
		end
	end
	if #dice == 0 and done then done() end
end

-- Dice set aside (positions of the last roll): they light up where they lie, the points count up
-- over them, and they move to their side's tray and shrink there (the leftmost first, so they
-- never cross). done() once they are there.
local function SetAside(side, pos, pts, done)
	local sd = sides[side]
	local take, rest, moving = {}, {}, {}
	for _, p in ipairs(pos) do if sd.play[p] then take[sd.play[p]] = true end end
	for _, i in ipairs(sd.play) do
		if take[i] then moving[#moving + 1] = sd.dice[i] else rest[#rest + 1] = i end
	end
	table.sort(moving, function(a, b) return a.x < b.x end)
	if pts and pts > 0 then Tally(pts, moving) end
	local left = #moving
	for _, d in ipairs(moving) do
		sd.kept[#sd.kept + 1] = d.i
		d.lit, d.hover, d.dull = true, nil, nil
		Still(d)
		d.where = "sweep"
		local slot = #sd.kept
		local tx, ty = TRAYX + (slot - 1) * TRAYSTEP, TRAY[side]
		-- out of its lane to the band, along it to the slot's column, down into the slot
		Leg(d, { y = BAND[side], size = SW, dur = 0.12, smooth = "IN_OUT" }, function()
			Leg(d, { x = tx, dur = 0.18, smooth = "IN_OUT" }, function()
				Leg(d, { y = ty, size = K, dur = 0.1, smooth = "OUT" }, function()
					d.where, d.lit = "tray", nil
					Draw(d)
					left = left - 1
					if left == 0 and done then done() end
				end)
			end)
		end)
	end
	sd.play = rest
	S.ready[side] = Now() + 0.4       -- the next throw's dice wait for these to clear the band
	if side == 1 then S.sel = {} end
	if #moving == 0 and done then done() end
end

---------------------------------------------------------------------------
-- The events of the table, animated one after another
---------------------------------------------------------------------------

local function RowName(seat)
	local v = View()
	local p = v and v.players and v.players[seat]
	return Name(p)
end
local function IsHouse(seat) local v = View() return v and v.practice and seat == 2 end
local function Mine(seat) local v = View() return v and v.seat ~= nil and v.seat == seat and not v.watching end

local function RowLine(side, text)
	counters["turn" .. side] = nil
	if rows[side] then rows[side].line:SetText(text or "") end
end

-- The words for a seat: "You" / the other player's name.
local function Who(seat)
	if Mine(seat) then return L.FARKLE_B_YOU end
	return RowName(seat)
end

local function LevelName(lvl) return L["FARKLE_B_LEVEL_" .. tostring(lvl or 0)] or "" end
local function OneIn(pct)
	pct = tonumber(pct) or 0
	if pct <= 0 then return nil end
	return floor(100 / pct + 0.5)
end

local busyUntil = 0
-- A pause on the table (a banner being read, a bank's sound): the buttons, and the House, wait
-- for it; the column is redrawn when it ends.
local function Hold(sec)
	busyUntil = max(busyUntil, Now() + sec)
	After(sec, function() if Refresh then Refresh() end end)
end
local function Busy()
	if S.animating or #S.queue > 0 then return true end
	if S.flying[1] > 0 or S.flying[2] > 0 then return true end
	for side = 1, 2 do
		for _, d in ipairs(sides[side] and sides[side].dice or {}) do if d.moving and d.where ~= "hand" then return true end end
	end
	return Now() < busyUntil
end
Board.Busy = function(id) return win ~= nil and win:IsShown() and S.id == id and Busy() end

do -- (the events' own locals)
local Handlers = {}

-- A turn ended for that seat: its dice stay where they are until its next throw, which starts afresh.
local function TurnOver(seat)
	sides[SideOf(seat)].fresh = true
	S.hic = nil
end

local function WinnerBanner(v)
	if not v or not v.over then return end
	if v.winner and v.seat and not v.watching then
		local won = v.winner == v.seat
		Banner(won and L.FARKLE_B_VICTORY or T("FARKLE_B_OPPONENT_WINS", Who(v.winner)), won and GREEN or RED, true)
		Sound(won and "win" or "lose")
	elseif v.winner then
		Banner(T("FARKLE_B_WINS", RowName(v.winner)), GREEN, true)
		Sound("win")
	else
		Banner(L.FARKLE_B_VOID, AMBER, true)
	end
	local how = v.reason == "cap" and L.FARKLE_B_AT_CAP or ""
	if v.winner and v.scores then
		local a, b = Num(v.scores[v.winner]), Num(v.scores[3 - v.winner])
		Log(Mine(v.winner) and T("FARKLE_B_LOG_WON_ME", how, a, b) or T("FARKLE_B_LOG_WON", Who(v.winner), how, a, b))
	end
	Hold(1.4)
	After(1.5, function() if ShowCard then ShowCard(S.id) end end)
end

-- After an event: the final round and sudden death said once each, and the end.
local function Notes(info)
	local v = View()
	if not v or not v.game then return end
	local g = v.game
	if g.over then return end
	if g.sudden and S.note ~= "sudden" then
		S.note = "sudden"
		Log(L.FARKLE_B_LOG_SUDDEN)
	elseif g.final and not S.note then
		S.note = "final"
		if g.capped then Log(L.FARKLE_B_LOG_CAP)
		elseif Mine(3 - g.final) then Log(T("FARKLE_B_LOG_FINAL_ME", Num(g.target), Who(g.final)))
		elseif Mine(g.final) then Log(T("FARKLE_B_LOG_FINAL_THEM", Who(3 - g.final), Num(g.target)))
		else Log(T("FARKLE_B_LOG_FINAL", Who(3 - g.final), Num(g.target), Who(g.final))) end
	end
end


-- A roll: thrown, landed; a bust dulls the dice (and waits for HIC! on a drunk table).
function Handlers.R(info, done)
	local seat, side = info.seat, SideOf(info.seat)
	local dice = info.dice or {}
	S.rolling = nil
	if seat == S.near then S.hint = nil end
	local how = info.relayed and T("FARKLE_B_RELAYED", "") or (IsHouse(seat) and L.FARKLE_B_SIMULATED or ("(/roll %s)"):format(tostring(info.value)))
	local said = Mine(seat) and T("FARKLE_B_LOG_THROW_ME", table.concat(dice, " "), how) or T("FARKLE_B_LOG_THROW", Who(seat), table.concat(dice, " "), how)
	if Mine(seat) then S.lesson = nil end
	Throw(side, dice, function()
		Log(said)
		if info.farkle then
			local sd = sides[side]
			for _, i in ipairs(sd.play) do local d = sd.dice[i]; d.dull = true; Draw(d) end
			if info.shaken == seat then
				S.hic = nil
				Banner(L.FARKLE_B_BONES, RED, nil, 0.9, L.FARKLE_B_HIC_SUCCESS, GREEN); Sound("tally")
				S.last[side] = L.FARKLE_B_SHAKEN
				Log(T("FARKLE_B_LOG_REUSE", Who(seat)))
				for _, i in ipairs(sd.play) do local d = sd.dice[i]; d.dull = nil; Draw(d) end
				Hold(0.9)
			elseif info.hiccupDue or (info.last and info.hiccupDue) then
				S.hic = { seat = seat, at = Now() }
				Log(Mine(seat) and L.FARKLE_B_LOG_HIC_DUE_ME or T("FARKLE_B_LOG_HIC_DUE", Who(seat)))
			else
				local lost = info.lost or (info.lastTurn and info.lastTurn.lost) or 0
				S.last[side] = lost > 0 and T("FARKLE_B_ROW_BONES_LOST", Num(lost)) or L.FARKLE_B_ROW_BONES
				Banner(L.FARKLE_B_BONES, RED, nil, nil, info.hicAttempted and L.FARKLE_B_HIC_FAIL or nil, RED)
				Sound("farkle")
				if Mine(seat) then Log(lost > 0 and T("FARKLE_B_LOG_BONES_ME_LOST", Num(lost)) or L.FARKLE_B_LOG_BONES_ME)
				else Log(lost > 0 and T("FARKLE_B_LOG_BONES_LOST", Who(seat), Num(lost)) or T("FARKLE_B_LOG_BONES", Who(seat))) end
				if Mine(seat) then S.lesson = { kind = "bust", lost = lost } end
				TurnOver(seat)
				Hold(1.2)
			end
		end
		Notes(info)
		done()
	end)
end

-- Dice set aside, then a roll on or a bank.
function Handlers.K(info, done)
	local seat, side = info.seat, SideOf(info.seat)
	local pts = info.points or 0
	local faces = table.concat(info.faces or {}, " ")
	Log(Mine(seat) and T("FARKLE_B_LOG_KEEP_ME", faces, Num(pts)) or T("FARKLE_B_LOG_KEEP", Who(seat), faces, Num(pts)))
	SetAside(side, info.mask or {}, pts, function()
		local sd = sides[side]
		if info.act == "b" then
			local banked = info.banked or (info.lastTurn and info.lastTurn.points) or pts
			S.last[side] = T("FARKLE_B_ROW_BANKED", Num(banked))
			local total = info.scores and info.scores[seat] or 0
			Log(Mine(seat) and T("FARKLE_B_LOG_BANK_ME", Num(banked), Num(total)) or T("FARKLE_B_LOG_BANK", Who(seat), Num(banked), Num(total)))
			if Mine(seat) then S.lesson = { kind = "bank", banked = banked, total = total } end
			Sound("bank")
			TurnOver(seat)
			Hold(0.85)
		elseif #sd.kept >= 6 then
			Fresh(side)
			Banner(L.FARKLE_B_HOT, AMBER)
			Log(Mine(seat) and L.FARKLE_B_LOG_HOT_ME or T("FARKLE_B_LOG_HOT", Who(seat)))
		end
		Notes(info)
		done()
	end)
end

-- The hiccup's 1-100: shaken off (the dice go back into the cup for the same throw) or the bust stands.
function Handlers.H(info, done)
	local seat, side = info.seat, SideOf(info.seat)
	local sd = sides[side]
	local shaken = info.shaken == seat
	S.hic = nil
	if shaken then
		Banner(L.FARKLE_B_SHAKEN, AMBER)
		Sound("tally")
		S.last[side] = T("FARKLE_B_ROW_SHAKEN", tostring(info.value))
		Log(T("FARKLE_B_LOG_SHAKEN", Who(seat), tostring(info.value)))
		for _, i in ipairs(sd.play) do local d = sd.dice[i]; d.dull = nil; Draw(d) end
		Hold(0.9)
	else
		local lost = info.lost or (info.lastTurn and info.lastTurn.lost) or 0
		S.last[side] = lost > 0 and T("FARKLE_B_ROW_BONES_LOST", Num(lost)) or L.FARKLE_B_ROW_BONES
		Banner(L.FARKLE_B_BONES, RED)
		Sound("farkle")
		Log(T("FARKLE_B_LOG_HIC_STANDS", Who(seat), tostring(info.value)))
		TurnOver(seat)
		Hold(1.2)
	end
	done()
end

-- The opening roll (1-100): who throws first.
function Handlers.O(info, done)
	local side = SideOf(info.seat)
	S.last[side] = T("FARKLE_B_ROW_OPENING", tostring(info.value))
	Log(T("FARKLE_B_LOG_OPENING", Who(info.seat), tostring(info.value)))
	if info.current then Log(Mine(info.current) and L.FARKLE_B_LOG_FIRST_ME or T("FARKLE_B_LOG_FIRST", Who(info.current))) end
	done()
end

local function Lost(key)
	return function(info, done)
		local seat, side = info.seat, SideOf(info.seat or 1)
		if seat then
			S.last[side] = L["FARKLE_B_ROW_" .. key]
			Log(T("FARKLE_B_LOG_" .. key, Who(seat)))
			local sd = sides[side]
			for _, i in ipairs(sd.play) do if sd.dice[i].where == "hand" then Collect(sd.dice[i]) end end
			StopShake(side)
			TurnOver(seat)
		end
		if key == "FOUL" then Banner(L.FARKLE_B_FOUL, RED); Sound("farkle") end
		done()
	end
end
Handlers.T = Lost("TIMEOUT")
Handlers.F = Lost("FOUL")
Handlers.A = Lost("FORFEIT")
Handlers.C = Lost("CONCEDE")
function Handlers.V(info, done) Log(L.FARKLE_B_LOG_VOID) done() end
function Handlers.L(info, done) done() end

-- The House lights the dice it will keep a moment before it keeps them.
function Handlers.consider(info, done)
	local sd = sides[SideOf(info.seat)]
	for _, p in ipairs(info.mask or {}) do
		local d = sd.dice[sd.play[p] or 0]
		if d then d.lit = true; Draw(d) end
	end
	done()
end

-- A throw asked for (this player's Roll, the House's): the dice go into the hand and shake there.
function Handlers.rolling(info, done)
	local seat = info.seat
	local v = View()
	-- (this player's own line may have come already: nothing to wait for)
	if Mine(seat) and not (v and v.rolling) then return done() end
	if v and v.expect and v.expect.phase == "open" then return done() end
	if v and v.expect and v.expect.phase == "hiccup" then return done() end
	S.rolling = Mine(seat) and { at = Now(), hi = info.hi } or S.rolling
	if info.refused and Mine(seat) then S.hint = T("FARKLE_B_HINT_REFUSED", info.hi or 0) end
	Shake(SideOf(seat))
	done()
end

-- A watcher's relayed state (the design): the dice thrown when they changed, the scores counted.
function Handlers.state(info, done)
	local s, p = info.state, info.prev
	if not s then return done() end
	local side = SideOf(s.cur == 0 and 1 or s.cur)
	local changed = not p or p.step ~= s.step
	local same = p and table.concat(p.dice or {}, "") == table.concat(s.dice or {}, "") and p.cur == s.cur
	if changed and not same and #s.dice > 0 and (s.phase == "keep" or s.phase == "hiccup" or s.phase == "decide") then
		if p and p.cur ~= s.cur then Fresh(side) end
		local sd = sides[side]
		local n = #s.dice
		if #sd.play ~= n then
			sd.play, sd.kept = {}, {}
			for i = 1, 6 do if i <= n then sd.play[#sd.play + 1] = i else sd.kept[#sd.kept + 1] = i end end
			for _, i in ipairs(sd.kept) do local d = sd.dice[i]; d.x, d.y, d.size, d.alpha, d.where = TRAYX + (i - n - 1) * TRAYSTEP, TRAY[side], K, 1, "tray"; Draw(d) end
		end
		return Throw(side, s.dice, function()
			if s.phase == "hiccup" or FR().Farkle(s.dice) then
				for _, i in ipairs(sd.play) do local d = sd.dice[i]; d.dull = true; Draw(d) end
			end
			done()
		end)
	end
	done()
end

local QUIET = { drunk = true, lower = true, away = true, back = true, combat = true, rebuild = true, L = true }

-- Queues an event; the queue plays them one after another. A queue that fell far behind (the
-- window was hidden, a resync) is dropped and the table redrawn from the view.
local function Enqueue(info)
	if QUIET[info.t] then
		if info.t == "rebuild" then S.queue = {}; if not S.animating then Sync() end end
		Refresh()
		return
	end
	if not Handlers[info.t] then return end
	S.queue[#S.queue + 1] = info
	if #S.queue > 8 then
		S.queue = {}
		S.animating = nil
		S.gen = S.gen + 1
		return Sync()
	end
	Pump()
end
Pump = function()
	if S.animating then return end
	local info = table.remove(S.queue, 1)
	if not info then return Refresh() end
	S.animating = info
	local gen = S.gen
	local finished = false
	local function Done()
		if finished or gen ~= S.gen then return end
		finished = true
		S.animating = nil
		if info.last and info.over then
			Refresh()
			WinnerBanner(View())
		end
		Refresh()
		Pump()
	end
	-- (a step never holds the queue for long: a lost callback is let go after a few seconds)
	C_Timer.After(4, function() if S.animating == info and gen == S.gen then Done() end end)
	Handlers[info.t](info, Done)
	Refresh()
end

Board.Enqueue, Board.Handlers = Enqueue, Handlers
end

---------------------------------------------------------------------------
-- The table redrawn from the view (the window opened on a table in play, a resync, a watcher's
-- first state): scores, the current turn's dice set aside in its tray, its last roll in the lanes.
---------------------------------------------------------------------------

do -- (the redraw's own locals)
-- The current turn so far, read from its events: the faces set aside, the last roll's faces and
-- which of them were set aside after it.
local function TurnSoFar(g)
	local out = { aside = {}, dice = nil, kept = nil }
	if not g or not g.events then return out end
	local from = (g.handed or 0) + 1
	local dice
	for i = from, g.step or #g.events do
		local ev = FR().Event(g.events[i] or "")
		if ev and ev.p == g.current then
			if ev.t == "R" then
				dice = FR().Decode(ev.value, ev.k)
				out.dice, out.kept = dice, nil
			elseif ev.t == "K" and dice then
				local _, list = FR().Mask(ev.mask)
				for _, p in ipairs(list or {}) do out.aside[#out.aside + 1] = dice[p] end
				out.kept = list
				if #out.aside >= 6 then out.aside = {} end
				dice = nil
				out.dice = nil
			end
		end
	end
	return out
end

Sync = function()
	local v = View()
	S.gen = S.gen + 1
	S.queue, S.animating, S.hic, S.rolling = {}, nil, nil, nil
	S.flying, S.hand, S.ready = { 0, 0 }, { 0, 0 }, { 0, 0 }
	StopShake(1); StopShake(2)
	for side = 1, 2 do
		Fresh(side)
		for _, d in ipairs(sides[side].dice) do Vanish(d); d.value, d.variant = d.i, random(4) end
	end
	if banner then banner:Hide() end
	if not v then return Refresh() end
	if v.watching and v.snap then
		local s = v.snap
		local side = SideOf(s.cur == 0 and 1 or s.cur)
		local sd = sides[side]
		local n = #s.dice
		sd.play, sd.kept = {}, {}
		for i = 1, 6 do if i <= n then sd.play[#sd.play + 1] = i elseif n > 0 then sd.kept[#sd.kept + 1] = i end end
		for j, i in ipairs(sd.play) do
			local d = sd.dice[i]
			d.value, d.x, d.y, d.size, d.alpha, d.where = s.dice[j], LaneX(i), REST[side], D, 1, "lane"
			Draw(d)
		end
		for slot, i in ipairs(sd.kept) do
			local d = sd.dice[i]
			d.x, d.y, d.size, d.alpha, d.where = TRAYX + (slot - 1) * TRAYSTEP, TRAY[side], K, 1, "tray"
			Draw(d)
		end
		return Refresh()
	end
	local g = v.game
	if g and g.over then
		local won = v.winner and v.seat and v.winner == v.seat
		local text = not v.winner and L.FARKLE_B_VOID or (v.seat and (won and L.FARKLE_B_YOU_WIN or (v.practice and L.FARKLE_B_HOUSE_WINS or L.FARKLE_B_THEY_WIN)) or T("FARKLE_B_WINS", RowName(v.winner)))
		Banner(text, (not v.winner and AMBER) or ((won or not v.seat) and GREEN or RED), true)
	end
	if not g or g.over or g.open or not g.current then return Refresh() end
	local side = SideOf(g.current)
	local sd = sides[side]
	local so = TurnSoFar(g)
	sd.play, sd.kept = {}, {}
	for slot, face in ipairs(so.aside) do
		local d = sd.dice[slot]
		sd.kept[#sd.kept + 1] = slot
		d.value, d.x, d.y, d.size, d.alpha, d.where = face, TRAYX + (slot - 1) * TRAYSTEP, TRAY[side], K, 1, "tray"
		Draw(d)
	end
	local nextFree = #so.aside + 1
	if so.dice then
		for j, face in ipairs(so.dice) do
			local i = nextFree + j - 1
			if i <= 6 then
				local d = sd.dice[i]
				sd.play[#sd.play + 1] = i
				d.value, d.x, d.y, d.size, d.alpha, d.where = face, LaneX(i), REST[side], D, 1, "lane"
				d.dull = g.turn and g.turn.phase == "hiccup" or nil
				Draw(d)
			end
		end
	else
		for i = nextFree, 6 do sd.play[#sd.play + 1] = i end
	end
	Refresh()
end

Board.TurnSoFar = TurnSoFar
end

---------------------------------------------------------------------------
-- This player's moves
---------------------------------------------------------------------------

-- The chosen dice: their positions in the last roll, and their faces.
local function Chosen()
	local v = View()
	local pos, faces = {}, {}
	local dice = v and v.turn and v.turn.dice or {}
	for j, i in ipairs(sides[1].play) do
		if S.sel[i] then pos[#pos + 1] = j; faces[#faces + 1] = dice[j] end
	end
	return pos, faces
end

-- Why a choice doesn't score: the faces whose dice score nothing by themselves (FarkleRules.Score).
local function Dead(faces)
	local count, out, plural = {}, {}, false
	for _, f in ipairs(faces) do count[f] = (count[f] or 0) + 1 end
	for f = 1, 6 do
		local c = count[f]
		if c then
			local same = {}
			for i = 1, c do same[i] = f end
			if not FR().Score(same) then
				out[#out + 1] = c == 1 and T("FARKLE_B_DEAD_ONE", f) or T("FARKLE_B_DEAD_MANY", f)
				plural = plural or c > 1
			end
		end
	end
	if #out == 0 then return L.FARKLE_B_DEAD_TOGETHER end
	return T((plural or #out > 1) and "FARKLE_B_DEAD_PLURAL" or "FARKLE_B_DEAD_SINGULAR", table.concat(out, L.FARKLE_B_AND))
end

-- May this player act now (his turn, the table still, nothing moving)?
local function MyTurn(v)
	v = v or View()
	if not v or v.watching or not v.seat or not v.game or v.over then return false end
	local why = v.actWhy
	if why then return false end
	return not Busy()
end

---------------------------------------------------------------------------
-- The lesson (1.1.6): a practice game against the House with the rules' hints
---------------------------------------------------------------------------

-- The chance, in whole percent, that n dice score nothing (BONES!): FarkleRules.Farkle over every
-- throw of n dice (each set of faces once, weighed by the orders it can come in), worked out once.
local bustCache = {}
function Board.BustChance(n)
	n = floor(tonumber(n) or 0)
	if n < 1 or n > 6 then return nil end
	if bustCache[n] then return bustCache[n] end
	local fact = { [0] = 1 }
	for i = 1, 6 do fact[i] = fact[i - 1] * i end
	local bust, total = 0, 0
	local dice, counts = {}, { 0, 0, 0, 0, 0, 0 }
	local function Walk(face, left)
		if left == 0 then
			local ways = fact[n]
			for f = 1, 6 do ways = ways / fact[counts[f]] end
			total = total + ways
			if FR().Farkle(dice) == true then bust = bust + ways end
			return
		end
		for f = face, 6 do
			dice[#dice + 1] = f
			counts[f] = counts[f] + 1
			Walk(f, left - 1)
			counts[f] = counts[f] - 1
			dice[#dice] = nil
		end
	end
	Walk(1, n)
	bustCache[n] = total > 0 and floor(bust * 100 / total + 0.5) or 0
	return bustCache[n]
end

-- What the column says in a lesson, or nil (the table's own words then): the opening; this
-- player's throw (the scores), the dice that score in it and their points, what is at stake with
-- the chance of BONES! on the dice left, hot dice; while the House plays, the last bust or bank
-- of his and what it meant. S.lesson keeps his last bust or bank (the event handlers).
function Board.Lesson(v)
	if type(v) ~= "table" or not v.practice or not v.learn or not v.game or v.watching then return nil end
	local g = v.game
	if g.over then return nil end
	if g.open then return L.FARKLE_L_OPENING end
	local who, phase, left = v.expect and v.expect.who, v.expect and v.expect.phase, v.expect and v.expect.left
	if who ~= v.seat then
		local last = S.lesson
		if last and last.kind == "bust" then return T("FARKLE_L_BUST", Num(last.lost or 0)) end
		if last and last.kind == "bank" then return T("FARKLE_L_BANKED", Num(last.banked or 0), Num(last.total or 0), Num(v.target or 0)) end
		return L.FARKLE_L_HOUSE
	end
	local turn = g.turn or {}
	if phase == "roll" then
		local n = left or 6
		if (turn.points or 0) == 0 then return T("FARKLE_L_ROLL", n) end
		return T("FARKLE_L_ROLL_ON", Num(turn.points), n, Board.BustChance(n) or 0)
	end
	if phase == "keep" then
		local _, faces = Chosen()
		local dice = turn.dice or {}
		if #faces == 0 then
			local best, pos = FR().Best(dice)
			if not best or best <= 0 then return nil end
			local show = {}
			for _, p in ipairs(pos or {}) do show[#show + 1] = tostring(dice[p]) end
			return T("FARKLE_L_KEEP", table.concat(show, " "), Num(best))
		end
		local pts = FR().Score(faces)
		if not pts then return nil end
		local rest = #dice - #faces
		local total = (turn.points or 0) + pts
		if rest == 0 then return T("FARKLE_L_HOT", Num(total)) end
		return T("FARKLE_L_DECIDE", Num(total), rest, Board.BustChance(rest) or 0)
	end
	return nil
end

local function Pickable(d)
	if d.side ~= 1 or d.moving or d.where ~= "lane" then return false end
	local v = View()
	if not MyTurn(v) or not v.expect or v.expect.phase ~= "keep" then return false end
	for _, i in ipairs(sides[1].play) do if i == d.i then return true end end
	return false
end

local function Pick(d)
	if not Pickable(d) then return end
	S.sel[d.i] = (not S.sel[d.i]) or nil
	d.lit = S.sel[d.i]
	Sound(d.lit and "pick" or "unpick")
	S.hint = nil
	Draw(d)
	Refresh()
end

-- Roll (the dice left, the opening's 1-100, or HIC!'s 1-100): the player's own /roll.
local function DoRoll()
	S.hint = nil
	local ok, why = A().Do("farkle.roll", S.id)
	if not ok then
		S.hint = T("FARKLE_B_HINT_CANT", tostring(why))
		return Refresh()
	end
	local gen = S.gen
	local wait = (FT().ROLL_WAIT or 6) + 0.1
	C_Timer.After(wait, function()
		if gen ~= S.gen then return end
		local v = View()
		if v and v.rolling and Now() - (v.rolling.at or Now()) >= wait - 0.2 then
			S.hint = T("FARKLE_B_HINT_NO_LINE", v.rolling.hi or 0)
			S.rolling = nil
			for _, i in ipairs(sides[1].play) do
				local d = sides[1].dice[i]
				if d.where == "hand" then Collect(d) end
			end
			StopShake(1)
			Refresh()
		end
	end)
	Refresh()
end

local function OnPrimary()
	local v = View()
	if S.mode == "setup" or not v then return end
	if v.over then
		if Busy() then return end
		if v.practice then
			S.mode, S.id, S.target = "setup", nil, v.target or S.target
			S.hint, S.lesson = nil, nil
			S.gen = S.gen + 1
			return Refresh()
		end
		return Board.Rematch(v)
	end
	if not MyTurn(v) then return end
	local phase = v.expect and v.expect.phase
	if phase == "keep" then
		local pos = Chosen()
		local ok, why = A().Do("farkle.keep", pos, "r", S.id)
		if not ok then S.hint = T("FARKLE_B_HINT_CANT", tostring(why)); return Refresh() end
		S.sel = {}
		return DoRoll()
	end
	return DoRoll()
end

local function OnBank()
	local v = View()
	if not MyTurn(v) or not v.expect or v.expect.phase ~= "keep" then return end
	local pos = Chosen()
	local ok, why = A().Do("farkle.keep", pos, "b", S.id)
	if not ok then S.hint = T("FARKLE_B_HINT_CANT", tostring(why)) end
	S.sel = {}
	Refresh()
end

-- The contextual button under the notes: Invite (the party), Pay stake, Concede (twice), Void (the
-- arbiter, twice), Stop watching, New table.
local function OnExtra()
	local what = extraBtn.what
	local v = View()
	if what == "invite" and v then
		local other = v.players[3 - (v.seat or 1)]
		A().Do("farkle.invite", other)
	elseif what == "answer" and v then
		Board.ShowAsk(v.role == "arbiter" and "arbiter" or "invite", S.id)
		return
	elseif what == "paystake" then
		A().Do("farkle.paystake", S.id)
	elseif what == "concede" or what == "void" then
		if S.sure ~= what then
			S.sure = what
			local gen = S.gen
			C_Timer.After(3, function() if S.sure == what and gen == S.gen then S.sure = nil; Refresh() end end)
			return Refresh()
		end
		S.sure = nil
		A().Do(what == "concede" and "farkle.concede" or "farkle.void", S.id)
	elseif what == "stop" then
		A().Do("farkle.stopwatching", S.id)
		Board.Close()
		return
	elseif what == "new" then
		Board.OpenCreate({})
		return
	end
	Refresh()
end

---------------------------------------------------------------------------
-- The table's texts and buttons, from the view
---------------------------------------------------------------------------


do -- (the texts' own locals)
-- A row's mug (the design): empty, a quarter, half or full; its tooltip says the rule for that level.
local function Mug(side, lvl, pct, shakes, show, wins, total)
	local p = rows[side]
	if not p or not p.mug then return end
	p.mug:SetShown(show)
	if not show then return end
	local f = FILL[lvl or 0] or 0
	p.mug.fill:SetShown(f > 0)
	if f > 0 then
		p.mug.fill:SetHeight(26 * f)
		p.mug.fill:SetTexCoord(0.08, 0.92, 0.92 - 0.84 * f, 0.92)
	end
	p.mug.level, p.mug.pct, p.mug.shakes = lvl, pct, shakes
	p.mug.wins, p.mug.total = wins, total
end

-- The phase clock in short ("42 s", "paused"), for the stage line (none in practice: the House
-- claims no time).
local function Clock(v)
	local c = v and v.clock
	if not c or v.practice then return nil end
	if c.paused then return L.FARKLE_B_PAUSED end
	local limit = Mine(c.seat) and c.click or c.claim
	local left = max(0, floor((limit or 0) - (c.used or 0) + 0.5))
	return T("FARKLE_B_CLOCK", left)
end
-- Why the clock stands still, and for whom (the tavern rule of the design, combat).
local function PauseText(v)
	local c = v and v.clock
	if not c or not c.paused then return nil end
	local list = c.paused == "tavern" and v.away or v.combat
	local who
	for seat, since in pairs(type(list) == "table" and list or {}) do if since then who = seat end end
	if c.paused == "tavern" then
		if v.awayLeft ~= nil then return T("FARKLE_B_AWAY_CLOCK", v.awayLeft) end
		if who and Mine(who) then return L.FARKLE_B_PAUSE_TAVERN_ME end
		return T("FARKLE_B_PAUSE_TAVERN", who and Who(who) or "?")
	end
	return T("FARKLE_B_PAUSE_COMBAT", who and Who(who) or "?")
end

local WAITING = { invite = true, asked = true, agreed = true }

-- What the column says and which buttons work, for a table in play.
local function PlayTexts(v)
	local g = v.game
	local who, phase, left = v.expect and v.expect.who, v.expect and v.expect.phase, v.expect and v.expect.left
	local flying = (S.flying[1] > 0 and SeatOf(1)) or (S.flying[2] > 0 and SeatOf(2)) or nil
	local mine = MyTurn(v)
	local text
	local p, b = { L.FARKLE_B_ROLL_N:format(6), false }, { L.FARKLE_B_BANK, false }
	if v.blind then text = L.FARKLE_B_BLIND end
	if flying then
		p[1] = Mine(flying) and L.FARKLE_B_ROLLING or T("FARKLE_B_THEY_PLAY", Who(flying))
		text = text or (Mine(flying) and L.FARKLE_B_YOUR_DICE_ROLL or T("FARKLE_B_THEY_THROW", Who(flying)))
	elseif v.watching then
		p[1] = L.FARKLE_B_WATCHING
		text = text or T("FARKLE_B_WATCH_TEXT", Name(v.relayer))
	elseif v.role == "arbiter" then
		p[1] = L.FARKLE_B_ARBITRATING
		text = text or (who and who > 0 and T("FARKLE_B_ARB_TURN", Who(who)) or L.FARKLE_B_ARB_TEXT)
	elseif g.open then
		local rolled = v.seat and g.opening and g.opening[v.seat]
		if rolled then
			p[1] = L.FARKLE_B_OPENING_WAIT
			text = text or T("FARKLE_B_OPENING_WAIT_TEXT", Who(3 - v.seat))
		else
			p = { L.FARKLE_B_OPENING, mine }
			text = text or L.FARKLE_B_OPENING_TEXT
		end
	elseif who ~= v.seat then
		p[1] = T("FARKLE_B_THEY_PLAY", Who(who))
		if S.hic and S.hic.seat == who then
			local _, pct = FR().Level(g, who)
			text = text or T("FARKLE_B_HIC_THEIRS", Who(who), OneIn(pct) or 0)
		else
			text = text or T("FARKLE_B_THEY_PLAYING", Who(who))
		end
	elseif S.rolling or (v.rolling and not v.rolling.refused and Now() - (v.rolling.at or 0) < (FT().ROLL_WAIT or 6)) then
		p[1] = L.FARKLE_B_ROLLING
		text = text or L.FARKLE_B_WAIT_LINE
	elseif phase == "hiccup" then
		local _, pct = FR().Level(g, v.seat)
		local c = v.clock
		local secs = c and max(0, floor((c.click or 0) - (c.used or 0) + 0.5))
		p = { secs and T("FARKLE_B_HIC_N", secs) or L.FARKLE_B_HIC, mine }
		text = text or T("FARKLE_B_HIC_MINE", pct or 0)
	elseif phase == "roll" then
		p = { T("FARKLE_B_ROLL_N", left or 6), mine }
		if g.turn.points > 0 then
			text = text or T("FARKLE_B_ROLL_ON", Num(g.turn.points), left or 6)
		else
			text = text or L.FARKLE_B_YOUR_TURN
		end
	elseif phase == "keep" then
		local _, faces = Chosen()
		local pts = #faces > 0 and FR().Score(faces)
		if pts then
			local rest = #(g.turn.dice or {}) - #faces
			p = { rest == 0 and L.FARKLE_B_KEEP_HOT or T("FARKLE_B_KEEP_N", rest), mine }
			b = { T("FARKLE_B_BANK_N", Num(g.turn.points + pts)), mine }
			text = text or T("FARKLE_B_SELECTED", table.concat(faces, " "), GOOD, Num(pts))
		else
			p = { L.FARKLE_B_KEEP, false }
			text = text or (#faces == 0 and L.FARKLE_B_CLICK_DICE or T("FARKLE_B_SELECTED_DEAD", table.concat(faces, " "), BAD, Dead(faces)))
		end
	end
	-- (a lesson: the rules' hint over the turn's words, while nothing moves)
	if v.learn and not flying and not S.rolling then text = Board.Lesson(v) or text end
	local pause = PauseText(v)
	if pause then text = pause end
	return text, p, b
end

-- The notes about drinking this player sees (the design): his own "You feel", a level that counts from
-- his next turn, a disputed turn.
local function DrinkNote(v)
	if not v.levels or not v.seat or v.watching then return nil end
	local mine = v.levels[v.seat]
	if v.lower then return L.FARKLE_B_LOWER end
	if v.feel and mine and v.feel ~= mine.level then
		return T("FARKLE_B_FEEL_NEXT", LevelName(v.feel))
	end
	if v.feel and v.feel > 0 then return T("FARKLE_B_FEEL", LevelName(v.feel):lower()) end
	return nil
end

local function SettleTexts(v)
	local parts = {}
	for _, l in ipairs(v.lines or {}) do
		if l.kind == "pay" then parts[#parts + 1] = T("FARKLE_B_OWE", Name(l.to), Money(l.copper - (l.paid or 0)))
		elseif l.kind == "fee" then parts[#parts + 1] = T("FARKLE_B_FEE_DUE", Money(FT().DirectFee(v.stake or 0))) end
	end
	if v.holdWhy == "disagree" then parts[#parts + 1] = L.FARKLE_B_HELD end
	return table.concat(parts, " ")
end

-- The extra button's job now (nil: hidden).
local function ExtraFor(v)
	if not v then return nil end
	if v.watching then return "stop", L.FARKLE_B_STOP_WATCHING end
	local state = v.state
	-- an invitation, or a request to arbitrate, waiting for this player's answer: its pop-up again
	if (v.role == "guest" and state == "invite") or (v.role == "arbiter" and state == "asked") then return "answer", L.FARKLE_B_ANSWER end
	if v.role == "host" or v.role == "guest" then
		if v.needGroup or (WAITING[state] and v.role == "host" and FT().InGroup and not FT().InGroup(v.players[2])) then
			return "invite", T("FARKLE_B_INVITE", Name(v.players[3 - (v.seat or 1)]))
		end
		-- (no stake to pay while only the crowd's bets hold the table: a rehearsal trades none)
		if state == "stakes" and not v.crowdWait and v.src and v.src[v.seat or 0] == "t" and not (v.held and v.held[v.seat]) then
			return "paystake", L.FARKLE_B_PAY_STAKE
		end
		if (state == "play" or state == "open") and v.game and not v.over then
			return "concede", S.sure == "concede" and L.FARKLE_B_SURE_CONCEDE or L.FARKLE_B_CONCEDE
		end
		if not WAITING[state] and not (v.game and not v.over) then return "new", L.FARKLE_B_NEW end
	elseif v.role == "arbiter" then
		if (state == "play" or state == "open") and v.game and not v.over then
			return "void", S.sure == "void" and L.FARKLE_B_SURE_VOID or L.FARKLE_B_VOID_BTN
		end
	end
	return nil
end

-- A waiting table's words (the invitation, the arbiter, the party, the tavern, the stakes).
local function WaitText(v)
	local state = v.state
	local other = Name(v.players[3 - (v.seat or 1)])
	if v.tavernWhy then return L["FARKLE_LOG_TAVERN_" .. tostring(v.tavernWhy):upper()] or "" end
	if v.needGroup then return T("FARKLE_B_NEED_GROUP", other) end
	if state == "invite" then return v.role == "host" and T("FARKLE_B_WAIT_ANSWER", other) or T("FARKLE_B_INVITED_BY", other) end
	if state == "asked" then return T("FARKLE_B_WAIT_ARBITER", Name(v.arbiter)) end
	if state == "agreed" then return v.role == "guest" and T("FARKLE_B_WAIT_OPEN", other) or T("FARKLE_B_OPENING_TABLE", other) end
	if state == "stakes" then
		if v.crowdWait then return v.crowdLeft and T("FARKLE_B_CROWD_WAIT", v.crowdLeft) or L.FARKLE_B_CROWD_WAIT_SOON end
		local held = v.held or {}
		if v.src and v.src[1] == "w" then return L.FARKLE_B_STAKES_WALLET end
		return T("FARKLE_B_STAKES", Name(v.players[1]), held[1] and L.FARKLE_B_HELD_WORD or L.FARKLE_B_WAITING_WORD,
			Name(v.players[2]), held[2] and L.FARKLE_B_HELD_WORD or L.FARKLE_B_WAITING_WORD)
	end
	if state == "declined" or state == "expired" or state == "aborted" then
		local lastLog = v.log and v.log[#v.log]
		return lastLog and lastLog.text or L.FARKLE_B_CLOSED
	end
	return nil
end

local function SubLine(v)
	if not v then return L.FARKLE_B_PRACTICE_GAME end
	local parts = { T("FARKLE_B_PLAY_TO", Num(v.target or 5000)) }
	if (v.stake or 0) > 0 then parts[#parts + 1] = Money(v.stake) end
	if v.learn then parts[#parts + 1] = L.FARKLE_B_LESSON end
	-- a rehearsal says so on every participant's table (the design)
	if v.rehearsal then parts[#parts + 1] = "|cffa81208" .. L.FARKLE_B_REHEARSAL .. "|r" end
	return table.concat(parts, " · ")
end

Refresh = function()
	if not win or not win:IsShown() then return end
	local v = View()
	local first = FT() and not FT().CanPlayPlayers()
	if first then S.target = FR().TARGETS[1] end
	for i, b in ipairs(targets) do
		if FR().TARGETS[i] == S.target then b:LockHighlight() else b:UnlockHighlight() end
		b:SetEnabled(not first or i == 1)
	end
	setup:SetShown(S.mode == "setup")
	setup.intro:SetText(first and L.FARKLE_INTRO_TEXT or L.FARKLE_B_SETUP_NOTE)
	setup.note:SetShown(first)
	setup.tips:SetOn(first or S.practiceTips)
	setup.tips:SetEnabled(not first)
	create:SetShown(S.mode == "create")
	if create:IsShown() then Board.CreateRefresh() end
	local playing = S.mode == "table" and v ~= nil
	for _, p in ipairs(rows) do
		for _, part in ipairs({ p.name, p.line, p.total, p.tray }) do part:SetShown(playing) end
	end
	for _, t in ipairs(win.midline) do t:SetShown(playing) end
	win.sit:SetShown(playing and not v.watching)
	for side = 1, 2 do rows[side].hl:Hide() end
	if not playing then
		primary:Hide(); bankBtn:Hide(); extraBtn:Hide()
		win.sub:SetText(S.mode == "create" and L.FARKLE_B_NEW_TABLE or L.FARKLE_B_PRACTICE_GAME)
		win.stage:SetText("")
		info:SetText(S.hint or (S.mode == "create" and (ForPoints() and L.FARKLE_B_CREATE_HINT_POINTS or L.FARKLE_B_CREATE_HINT) or L.FARKLE_B_SETUP_HINT))
		for side = 1, 2 do
			local p = rows[side]
			Count("total" .. side, p.total, 0, Num)
			p.name:SetText(side == 1 and Name(ns.me) or (S.mode == "create" and Name(S.guest) or L.FARKLE_HOUSE))
			RowLine(side, side == 1 and L.FARKLE_B_ROW_YOURS or (S.mode == "create" and L.FARKLE_B_ROW_OPPONENT or L.FARKLE_B_ROW_HOUSE))
			Mug(side, 0, 0, 0, false)
			p.name:ClearAllPoints(); Place(p.name, 22, ROW[side] + 7)
			p.line:ClearAllPoints(); Place(p.line, 23, ROW[side] + (side == 2 and 33 or 32))
		end
		for side = 1, 2 do for _, d in ipairs(sides[side].dice) do d.f:EnableMouse(false) end end
		if win.bar and win.bar.Relayout then win.bar.Relayout() end
		return
	end
	primary:Show(); bankBtn:Show()
	local g = v.game
	-- the rows: the name, the small line, the points; the mug on a hiccup table
	local drink = v.levels ~= nil
	for side = 1, 2 do
		local seat = SeatOf(side)
		local p = rows[side]
		SetFont(p.name, FontFor(v.players[seat]), 20)
		p.name:SetText(Name(v.players[seat]))
		local nx = drink and 50 or 22
		p.name:ClearAllPoints(); Place(p.name, nx, ROW[side] + 7)
		p.line:ClearAllPoints(); Place(p.line, nx + 1, ROW[side] + (side == 2 and 33 or 32))
		p.name:SetWidth(drink and 242 or 270); p.line:SetWidth(drink and 242 or 270)
		local lv = drink and v.levels[seat]
		local mugLevel = lv and lv.level or 0
		-- Practice shows your observed drinking immediately; odds still use the recorded turn.
		if v.practice and seat == v.seat and v.feel ~= nil then mugLevel = v.feel end
		Mug(side, mugLevel, lv and lv.pct or 0, lv and lv.shakes or 0, drink, lv and lv.wins, lv and lv.total)
		local score = (v.watching and v.snap and (seat == 1 and v.snap.s1 or v.snap.s2)) or (v.scores and v.scores[seat]) or 0
		Count("total" .. side, p.total, score, Num, 0.7)
	end
	local acting
	if g and not g.over and not g.open then acting = g.current end
	if v.watching and v.snap then acting = v.snap.cur ~= 0 and v.snap.cur or nil end
	local flying = (S.flying[1] > 0 and SeatOf(1)) or (S.flying[2] > 0 and SeatOf(2)) or nil
	acting = flying or acting
	for side = 1, 2 do
		local seat = SeatOf(side)
		local p = rows[side]
		p.hl:SetShown(acting == seat)
		local lv = drink and v.levels[seat]
		local saves = lv and lv.level > 0 and not (g and g.over) and T("FARKLE_B_ROW_SAVES", lv.shakes) or nil
		local function WithSaves(text) return saves and (text .. " · " .. saves) or text end
		local turnPts = g and g.turn and g.turn.points or 0
		if v.watching and v.snap then turnPts = v.snap.turnPts or 0 end
		if acting == seat and not (g and g.over) then
			local base = Mine(seat) and L.FARKLE_B_ROW_YOUR_TURN or (IsHouse(seat) and L.FARKLE_B_ROW_ITS_TURN or L.FARKLE_B_ROW_THEIR_TURN)
			if S.hic and S.hic.seat == seat then base = L.FARKLE_B_ROW_HIC end
			Count("turn" .. side, p.line, turnPts, function(n) return WithSaves(n > 0 and T("FARKLE_B_ROW_THIS_TURN", Num(n)) or base) end, 0.45)
		else
			local lv = drink and v.levels[seat]
			local idle = IsHouse(seat) and L.FARKLE_B_ROW_HOUSE or (Mine(seat) and L.FARKLE_B_ROW_YOURS or L.FARKLE_B_ROW_THEIRS)
			if lv and lv.level > 0 then
				if lv.total then idle = T("FARKLE_B_ROW_REUSE", lv.wins, lv.total, lv.shakes)
				elseif lv.pct > 0 then idle = T("FARKLE_B_ROW_DRUNK", OneIn(lv.pct), lv.shakes) end
			end
			RowLine(side, S.last[side] and WithSaves(S.last[side]) or idle)
		end
	end
	-- the column: the target and the stake, the round and the clock
	win.sub:SetText(SubLine(v))
	local stage
	if not g then stage = ""
	elseif g.over then stage = L.FARKLE_B_OVER
	elseif g.open then stage = L.FARKLE_B_STAGE_OPENING
	elseif g.sudden then stage = L.FARKLE_B_SUDDEN
	elseif g.final then stage = L.FARKLE_B_LAST_ROUND
	else stage = T("FARKLE_B_ROUND", v.round or 1) end
	local clock = Clock(v)
	if clock and not (g and g.over) then stage = stage .. " · " .. clock end
	if v.watching then stage = v.snap and T("FARKLE_B_ROUND_WATCH", Name(v.relayer)) or L.FARKLE_B_WATCH_WAIT end
	win.stage:SetText(stage)
	local text, p, b
	if not g and not v.watching then
		text = WaitText(v) or ""
		p = { L.FARKLE_B_WAITING, false }
		b = { L.FARKLE_B_BANK, false }
	elseif g and g.over then
		text = L.FARKLE_B_GAME_OVER .. (v.lines and (" " .. SettleTexts(v)) or "")
		p = { v.practice and L.FARKLE_B_PLAY_AGAIN or L.FARKLE_B_REMATCH, not Busy() and (v.practice or (v.seat ~= nil and not v.watching)) }
		b = { L.FARKLE_B_BANK, false }
	else
		text, p, b = PlayTexts(v)
		-- (the crowd's bets hold the first throw: said over the turn's words)
		if v.crowdWait or (not text and v.state == "stakes") then text = WaitText(v) end
	end
	local note = DrinkNote(v)
	if note and not S.hint then text = (text and text ~= "" and (text .. " ") or "") .. note end
	Set(primary, p[1], p[2])
	Set(bankBtn, b[1], b[2])
	bankBtn:SetShown(not v.watching and v.role ~= "arbiter")
	info:SetText(S.hint or text or "")
	local what, label = ExtraFor(v)
	extraBtn.what = what
	extraBtn:SetShown(what ~= nil)
	if what then Set(extraBtn, label, true) end
	if win.bar and win.bar.Relayout then win.bar.Relayout() end
	-- this player's dice in play can be picked only while he chooses (not the ones set aside)
	for _, d in ipairs(sides[1].dice) do
		local on = Pickable(d)
		d.f:EnableMouse(on)
		if not on and (d.hover or (d.lit and not d.moving and not S.sel[d.i] and d.where == "lane")) then d.hover = nil; d.lit = nil; Draw(d) end
	end
	for _, d in ipairs(sides[2].dice) do d.f:EnableMouse(false) end
	-- a clock on screen: one ticker while it shows
	local want = clock ~= nil and not (g and g.over)
	if want and not S.clockTicker then
		S.clockTicker = C_Timer.NewTicker(0.5, function()
			if not win or not win:IsShown() then if S.clockTicker then S.clockTicker:Cancel(); S.clockTicker = nil end return end
			Refresh()
		end)
	elseif not want and S.clockTicker then
		S.clockTicker:Cancel(); S.clockTicker = nil
	end
	-- the drinker's HIC! ring on his mug (the design's own clock)
	for side = 1, 2 do
		local ring = rows[side].ring
		if ring then
			local seat = SeatOf(side)
			local c = v.clock
			if c and c.phase == "hiccup" and c.seat == seat and ring.SetCooldown then
				local limit = Mine(seat) and c.click or c.claim
				if rows[side].ringFor ~= (v.id .. (g and g.step or 0)) then
					rows[side].ringFor = v.id .. (g and g.step or 0)
					pcall(ring.SetCooldown, ring, Now() - (c.used or 0), limit or 10)
				end
				ring:Show()
			else
				rows[side].ringFor = nil
				ring:Hide()
			end
		end
	end
end
Board.Refresh = function() if win then Refresh() end end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function NewDie(side, i)
	local d = { side = side, i = i, x = LaneX(i), y = REST[side], size = D, alpha = 0, value = i, variant = 1, where = "hidden" }
	d.f = NewSprite(win)
	d.f:SetFrameLevel((win:GetFrameLevel() or 0) + 3)
	d.f:SetScript("OnClick", function() Pick(d) end)
	if side == 1 then
		d.f:SetScript("OnEnter", function() if Pickable(d) and not d.lit then d.hover = true; Draw(d) end end)
		d.f:SetScript("OnLeave", function() if d.hover then d.hover = nil; Draw(d) end end)
	end
	return d
end

-- A thin carved line: dark, with a light edge under it (or to its right).
local function Groove(x, y, w, h)
	local dark = win:CreateTexture(nil, "BORDER")
	dark:SetColorTexture(0.2, 0.1, 0.03, 0.42)
	dark:SetPoint("TOPLEFT", win, "TOPLEFT", x, -y); dark:SetSize(w, h)
	local lit = win:CreateTexture(nil, "BORDER")
	lit:SetColorTexture(1, 0.92, 0.72, 0.3)
	if w > h then lit:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(y + h)); lit:SetSize(w, 1)
	else lit:SetPoint("TOPLEFT", win, "TOPLEFT", x + w, -y); lit:SetSize(1, h) end
	return { dark, lit }
end

local function Row(side)
	local top, p = ROW[side], {}
	p.hl = win:CreateTexture(nil, "BORDER")
	p.hl:SetColorTexture(1, 0.86, 0.5, 0.2)
	p.hl:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -(top + (side == 2 and 8 or 5)))
	p.hl:SetSize(COLX - 18, 50)
	p.hl:Hide()
	p.tray = win:CreateTexture(nil, "BORDER")   -- the tray: a shallow hollow in the plank
	p.tray:SetColorTexture(0.36, 0.2, 0.06, 0.1)
	p.tray:SetPoint("CENTER", win, "TOPLEFT", TRAYX + 2.5 * TRAYSTEP, -TRAY[side]); p.tray:SetSize(6 * TRAYSTEP + 8, 36)
	p.name = Text(win, 20, INK, MORPHEUS, "LEFT"); Place(p.name, 22, top + 7)
	p.name:SetWidth(270); p.name:SetWordWrap(false)
	p.line = Text(win, 13, SOFT, nil, "LEFT"); Place(p.line, 23, top + (side == 2 and 33 or 32))
	p.line:SetWidth(270); p.line:SetWordWrap(false)
	p.total = Text(win, 30, INK, MORPHEUS, "RIGHT"); Place(p.total, COLX - 14, TRAY[side] + (side == 2 and 2 or -2), "RIGHT")
	-- the mug (a hiccup table): the game's ale icon dim, its liquid in colour up to the level
	local mug = CreateFrame("Frame", nil, win)
	mug:SetSize(26, 26)
	mug:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -(top + (side == 2 and 18 or 18)))
	local icon = (ns.UI and ns.UI.FirstTexture) and ns.UI.FirstTexture(MUGS) or MUGS[1]
	mug.base = mug:CreateTexture(nil, "ARTWORK")
	mug.base:SetAllPoints(); mug.base:SetTexture(icon); mug.base:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	mug.base:SetDesaturated(true); mug.base:SetVertexColor(0.6, 0.56, 0.5)
	mug.fill = mug:CreateTexture(nil, "ARTWORK", nil, 1)
	mug.fill:SetTexture(icon); mug.fill:SetPoint("BOTTOMLEFT"); mug.fill:SetPoint("BOTTOMRIGHT"); mug.fill:SetHeight(1)
	mug.fill:Hide()
	mug:EnableMouse(true)
	mug:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(LevelName(self.level))
		local n = OneIn(self.pct)
		GameTooltip:AddLine(self.total and T("FARKLE_B_MUG_REUSE", self.wins, self.total) or (n and T("FARKLE_B_MUG_TIP", n) or L.FARKLE_B_MUG_SOBER), 1, 1, 1, true)
		GameTooltip:AddLine(T("FARKLE_B_MUG_SHAKES", self.shakes or 0), 1, 1, 1)
		GameTooltip:Show()
	end)
	mug:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	mug:Hide()
	p.mug = mug
	-- HIC!'s own clock (the design): a ring over the mug while the hiccup is due
	local okRing, ring = pcall(CreateFrame, "Cooldown", nil, mug, "CooldownFrameTemplate")
	if okRing and ring then ring:SetAllPoints(mug); ring:Hide(); p.ring = ring end
	rows[side] = p
end

-- Innkeeper training: choose the target and optional lesson tips, then Start. Player matches
-- use the Bones lobby's own entries; repeating practice stays with the innkeeper.
local function Setup()
	setup = CreateFrame("Frame", nil, win)
	setup:SetFrameLevel((win:GetFrameLevel() or 0) + 13)
	setup:SetPoint("TOPLEFT", win, "TOPLEFT", 25, -16); setup:SetSize(556, 368)
	setup.heading = Text(setup, 28, INK, MORPHEUS)
	setup.heading:SetPoint("TOP", 0, 0); setup.heading:SetText(L.FARKLE_INTRO_TITLE)
	setup.intro = Text(setup, 13, INK, STANDARD_TEXT_FONT, "CENTER")
	setup.intro:SetPoint("TOP", 0, -42); setup.intro:SetSize(530, 74); setup.intro:SetJustifyV("TOP")
	setup.intro:SetText(L.FARKLE_INTRO_TEXT)
	local title = Text(setup, 20, INK, MORPHEUS)
	title:SetPoint("TOP", 0, -128); title:SetText(L.FARKLE_B_PLAY_TO_TITLE)
	setup.title = title
	local sub = { L.FARKLE_B_QUICK, L.FARKLE_B_STANDARD, L.FARKLE_B_LONG }
	for k, target in ipairs(FR().TARGETS) do
		local b = Button(setup, Num(target), 104, 32, function() S.target = target; Refresh() end)
		b:SetPoint("TOPLEFT", setup, "TOPLEFT", 110 + (k - 1) * 116, -158)
		local fs = Text(setup, 13, SOFT)
		fs:SetPoint("TOP", b, "BOTTOM", 0, -4); fs:SetText(sub[k] or "")
		targets[k] = b
	end
	setup.tips = Check(setup, L.FARKLE_B_TIPS, function(on) S.practiceTips = on end)
	setup.tips:SetPoint("TOP", setup, "TOP", 0, -224)
	local start = Button(setup, L.FARKLE_B_START, 150, 32, function() Board.StartPractice(S.target, setup.tips.checked) end)
	start:SetPoint("TOP", setup, "TOP", 0, -272)
	setup.start = start
	setup.note = Text(setup, 13, SOFT)
	setup.note:SetPoint("TOP", setup, "TOP", 0, -324); setup.note:SetWidth(530); setup.note:SetWordWrap(false)
	setup.note:SetText(L.FARKLE_B_SETUP_NOTE)
end

---------------------------------------------------------------------------
-- The create panel (the host): the opponent, the target, the stake and, with a stake, how it is
-- held; the timer, spectators, a sober table. Dark ink on the table, buttons only (no edit box).
---------------------------------------------------------------------------

local function Settings() return Call("ArenaRoles", "Settings") or {} end
local function WhyText(why)
	if not why then return "" end
	why = tostring(why)
	local key = "FARKLE_B_WHY_" .. why:upper():gsub("%-", "_")
	return L[key] or L["FARKLE_WHY_" .. why:upper()] or T("FARKLE_B_WHY_OTHER", why)
end
Board.WhyText = WhyText

do -- (the create panel's own locals)
-- (watchers are allowed unless the host says no, the owner's call 2026-10-04)
local C = { target = 5000, stake = 0, mode = "d", src = nil, secs = 60, spectators = true, sober = false, rehearsal = false, crowd = true }
Board.C = C

-- The crowd's bets (2026-10-04): offered with a public arbiter, watchers let in and the stakes not
-- in the wallet (FarkleTable.CanCreate's rule); on by default there.
local function CrowdOffered()
	return C.stake > 0 and C.mode == "a" and C.arbiter ~= nil and (C.src or "t") ~= "w" and C.spectators == true
		and Call("ArenaRoles", "IsPublicArbiter", C.arbiter, A().NewMode(C.rehearsal)) == true
end
Board.CrowdOffered = CrowdOffered

local function Candidates(prefer)
	local out, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		local full = ns.FullName and ns.FullName(ns.Normal(name)) or name
		if FT().Same(full, ns.me) or seen[full:lower()] then return end
		seen[full:lower()] = true
		out[#out + 1] = full
	end
	Add(prefer)
	if UnitExists and UnitExists("target") and (not UnitIsPlayer or UnitIsPlayer("target")) then Add(ns.UnitFullName("target")) end
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	for i = 1, raid and n or (n - 1) do Add(ns.UnitFullName((raid and "raid" or "party") .. i)) end
	return out
end
local function Arbiters()
	local out = {}
	local found = Call("Stakes", "Search")
	if type(found) == "table" then
		for _, a in ipairs(found) do if type(a) == "table" and a.name and a.online ~= false and a.free ~= false then out[#out + 1] = a.name end end
	end
	if #out == 0 then
		for _, a in ipairs(Call("ArenaRoles", "Arbiters") or {}) do if type(a) == "table" and a.name then out[#out + 1] = a.name end end
	end
	return out
end
local function StakeStep(c, up)
	if up then
		if c < 10000 then return 1000 end
		if c < 100000 then return 10000 end
		return 100000
	end
	if c <= 10000 then return 1000 end
	if c <= 100000 then return 10000 end
	return 100000
end

function Board.CreateOpts()
	return { guest = C.guest, target = C.target, stake = C.stake, mode = C.stake > 0 and C.mode or "d", arbiter = C.stake > 0 and C.mode == "a" and C.arbiter or nil,
		src = C.stake > 0 and (C.mode == "a" and (C.src or "t") or "o") or nil, secs = C.secs, spectators = C.spectators, hic = not C.sober,
		rehearsal = C.rehearsal or nil, from = C.from, crowd = CrowdOffered() and C.crowd or nil }
end

local function CreatePanel()
	create = CreateFrame("Frame", nil, win)
	create:SetFrameLevel((win:GetFrameLevel() or 0) + 13)
	create:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -64); create:SetSize(COLX - 32, 266)
	local function Label(text, x, y)
		local fs = Text(create, 13, SOFT, nil, "LEFT")
		fs:SetPoint("TOPLEFT", create, "TOPLEFT", x, -y); fs:SetWidth(90); fs:SetWordWrap(false); fs:SetText(text)
		return fs
	end
	local function At(b, x, y) b:ClearAllPoints(); b:SetPoint("TOPLEFT", create, "TOPLEFT", x, -y) return b end
	-- 1: the opponent
	create.oppLabel = Label(L.FARKLE_B_C_OPPONENT, 8, 8)
	create.opp = Text(create, 18, INK, MORPHEUS, "LEFT")
	create.opp:SetPoint("TOPLEFT", create, "TOPLEFT", 100, -4); create.opp:SetWidth(250); create.opp:SetWordWrap(false)
	create.next = At(Button(create, L.FARKLE_B_C_NEXT, 90, 32, function()
		local list = Candidates()
		if #list == 0 then return end
		local at = 0
		for i, n in ipairs(list) do if C.guest and FT().Same(n, C.guest) then at = i end end
		C.guest = list[at % #list + 1]
		Refresh()
	end), 360, 0)
	create.invite = At(Button(create, L.FARKLE_B_C_INVITE, 140, 32, function() if C.guest then A().Do("farkle.invite", C.guest) end end), 426, 0)
	-- 2: the target
	Label(L.FARKLE_B_C_TARGET, 8, 50)
	create.targets = {}
	for k, target in ipairs(FR().TARGETS) do
		create.targets[k] = At(Button(create, Num(target), 96, 32, function() C.target = target; Refresh() end), 100 + (k - 1) * 102, 42)
	end
	-- 3: the stake (1.1.6, for points only: "Playing for: points")
	create.stakeLabel = Label(L.FARKLE_B_C_STAKE, 8, 92)
	create.minus = At(Button(create, "-", 40, 32, function()
		local s = C.stake
		local minBet = Settings().minBet or 1000
		if s <= minBet then C.stake = 0 else C.stake = max(minBet, s - StakeStep(s, false)) end
		Refresh()
	end), 100, 84)
	create.amount = Text(create, 18, INK, MORPHEUS)
	create.amount:SetPoint("TOPLEFT", create, "TOPLEFT", 142, -90); create.amount:SetWidth(116); create.amount:SetWordWrap(false)
	create.plus = At(Button(create, "+", 40, 32, function()
		local s = C.stake
		local minBet = Settings().minBet or 1000
		local cap = Call("Standing", "Cap", "bet", ns.me) or Settings().maxBet or 200000
		if s < minBet then C.stake = minBet else C.stake = min(tonumber(cap) or s, s + StakeStep(s, true)) end
		Refresh()
	end), 260, 84)
	create.none = At(Button(create, L.FARKLE_B_C_NO_STAKE, 110, 32, function() C.stake = 0; Refresh() end), 306, 84)
	create.crowd = At(Check(create, L.ARENA_BONE_CROWD, function(on) C.crowd = on; Refresh() end), 424, 84)
	create.crowd:SetWidth(150)
	create.crowd.label:SetWidth(120)
	-- 4: with a stake, how it is held
	create.modeLabel = Label(L.FARKLE_B_C_HELD, 8, 134)
	create.direct = At(Button(create, L.FARKLE_B_C_DIRECT, 110, 32, function() C.mode = "d"; Refresh() end), 100, 126)
	create.arb = At(Button(create, L.FARKLE_B_C_ARBITER, 110, 32, function()
		C.mode = "a"
		if not C.arbiter then C.arbiter = Arbiters()[1] end
		Refresh()
	end), 214, 126)
	create.arbName = Text(create, 13, INK, nil, "LEFT")
	create.arbName:SetPoint("TOPLEFT", create, "TOPLEFT", 330, -136); create.arbName:SetWidth(130); create.arbName:SetWordWrap(false)
	create.arbNext = At(Button(create, L.FARKLE_B_C_NEXT_ARB, 100, 32, function()
		local list = Arbiters()
		if #list == 0 then return end
		local at = 0
		for i, n in ipairs(list) do if C.arbiter and FT().Same(n, C.arbiter) then at = i end end
		C.arbiter = list[at % #list + 1]
		Refresh()
	end), 466, 126)
	create.wallet = Check(create, L.FARKLE_B_C_WALLET, function(on) C.src = on and "w" or "t"; Refresh() end)
	At(create.wallet, 100, 164)
	-- 5: the timer, spectators, a sober table, a rehearsal
	Label(L.FARKLE_B_C_TIMER, 8, 210)
	create.slower = At(Button(create, "-", 36, 32, function() C.secs = max(FT().SECS_MIN, C.secs - 15); Refresh() end), 100, 202)
	create.secs = Text(create, 13, INK)
	create.secs:SetPoint("TOPLEFT", create, "TOPLEFT", 138, -212); create.secs:SetWidth(50); create.secs:SetWordWrap(false)
	create.faster = At(Button(create, "+", 36, 32, function() C.secs = min(FT().SECS_MAX, C.secs + 15); Refresh() end), 190, 202)
	create.spec = At(Check(create, L.FARKLE_B_C_SPECTATORS, function(on) C.spectators = on; Refresh() end), 340, 164)
	create.sober = At(Check(create, L.FARKLE_B_C_SOBER, function(on) C.sober = on; Refresh() end), 236, 202)
	create.rehearsal = At(Check(create, L.FARKLE_B_C_REHEARSAL, function(on) C.rehearsal = on; Refresh() end), 452, 202)
	create.rehearsal:SetWidth(120)
	create.rehearsal.label:SetWidth(90)
	-- 6: why not yet, and Send
	create.why = Text(create, 13, RED, nil, "LEFT")
	create.why:SetPoint("TOPLEFT", create, "TOPLEFT", 8, -242); create.why:SetWidth(380); create.why:SetWordWrap(false)
	create.cancel = At(Button(create, L.FARKLE_B_C_CANCEL, 80, 32, function() S.mode = "setup"; S.hint = nil; Refresh() end), 390, 232)
	create.send = At(Button(create, L.FARKLE_B_C_SEND, 100, 32, function() Board.SendInvite() end), 474, 232)
end


function Board.CreateRefresh()
	local list = Candidates(C.guest)
	if not C.guest then C.guest = list[1] end
	S.guest = C.guest
	SetFont(create.opp, FontFor(C.guest), 18)
	create.opp:SetText(C.guest and Name(C.guest) or L.FARKLE_B_C_NOBODY)
	create.next:SetShown(#list > 1 or (#list == 1 and not C.guest))
	create.invite:SetShown(C.guest ~= nil and not FT().InGroup(C.guest))
	for k, b in ipairs(create.targets) do if FR().TARGETS[k] == C.target then b:LockHighlight() else b:UnlockHighlight() end end
	-- (1.1.6: a stake waits for the compliance gate: the game is for fun, the reason row says why.)
	local wait = Call("Compliance", "Waits", "stake", "bones", true)
	if wait then C.stake = 0 end
	create.minus:SetShown(not wait); create.plus:SetShown(not wait)
	create.stakeLabel:SetText(wait and L.FARKLE_B_C_PLAYS_FOR or L.FARKLE_B_C_STAKE)
	create.amount:SetText(C.stake > 0 and Money(C.stake) or (wait and L.FARKLE_B_C_POINTS or L.FARKLE_B_C_FOR_FUN))
	local staked = C.stake > 0
	for _, x in ipairs({ create.modeLabel, create.direct, create.arb }) do x:SetShown(staked) end
	create.none:SetShown(staked)
	if staked then
		if C.mode == "d" then create.direct:LockHighlight(); create.arb:UnlockHighlight() else create.arb:LockHighlight(); create.direct:UnlockHighlight() end
	end
	local withArb = staked and C.mode == "a"
	create.arbName:SetShown(withArb); create.arbNext:SetShown(withArb); create.wallet:SetShown(withArb and Call("Compliance", "Wallet") == true)
	if withArb then
		create.arbName:SetText(C.arbiter and Name(C.arbiter) or L.FARKLE_B_C_NO_ARBITER)
		if C.arbiter and Call("ArenaRoles", "IsKing", C.arbiter) then C.src = "w" end
		create.wallet:SetOn((C.src or "t") == "w")
	end
	create.secs:SetText(T("FARKLE_B_C_SECS", C.secs))
	create.sober:SetShown(FT().DrunkReadable())
	create.sober:SetOn(C.sober)
	create.spec:SetOn(C.spectators)
	create.crowd:SetShown(CrowdOffered())
	create.crowd:SetOn(C.crowd)
	local live = A().NewMode(false) == "L"
	create.rehearsal:SetShown(live)
	if not live then C.rehearsal = false end
	create.rehearsal:SetOn(C.rehearsal)
	local ok, why = A().Can("farkle.create", Board.CreateOpts())
	-- (1.2.0, the owner's call: a free game shows no bets notice; "Plays for: points" says it.)
	create.why:SetText(ok and (C.from and L.FARKLE_B_C_MATCHED or "") or WhyText(why))
	if ok then create.send:Enable() else create.send:Disable() end
end

-- Sends the invitation, then shows the table waiting for the answer.
function Board.SendInvite()
	local id, why = A().Do("farkle.create", Board.CreateOpts())
	if type(id) ~= "string" then S.hint = WhyText(why or "error"); return Refresh() end
	S.hint = nil
	return Board.Show(id)
end

Board.CreatePanel = CreatePanel
end

-- A dark frame round a window, bronze at its outer edge.
local function Frame(f, list)
	for _, e in ipairs({ { 3, 0.07, 0.04, 0.02, 0.95 }, { 4, 0.45, 0.28, 0.12, 0.7 } }) do
		local w, r, g, b, a = e[1], e[2], e[3], e[4], e[5]
		for _, sd in ipairs({
			{ "TOPLEFT", -w, w, "TOPRIGHT", w, 0 }, { "BOTTOMLEFT", -w, 0, "BOTTOMRIGHT", w, -w },
			{ "TOPLEFT", -w, 0, "BOTTOMLEFT", 0, 0 }, { "TOPRIGHT", 0, 0, "BOTTOMRIGHT", w, 0 },
		}) do
			local t = f:CreateTexture(nil, "BACKGROUND", nil, w == 3 and 2 or 1)
			t:SetColorTexture(r, g, b, a)
			t:SetPoint(sd[1], f, sd[1], sd[2], sd[3]); t:SetPoint(sd[4], f, sd[4], sd[5], sd[6])
			if list then list[#list + 1] = t end
		end
	end
end
-- The game's parchment behind a pop-up.
local function Parchment(f)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetTexture("Interface\\QuestFrame\\QuestBG"); f.bg:SetTexCoord(0, 300 / 512, 0, 336 / 512); f.bg:SetAllPoints()
	f.frame = {}
	Frame(f, f.frame)
end
local function Movable(f)
	f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

local EscSync -- (below)
local held     -- the window holding the table now (Board.SetHost, below), or nil: its own window
local under    -- that window's own part over the table (Board.EscapeUnder, below): Escape's first

---------------------------------------------------------------------------
-- How to play: a pop-up of its own in the middle of the screen, over the table (a strata above it,
-- so none of the table's buttons draws on top of it), on the game's parchment in dark ink, in four
-- pages: Rules (the goal and a turn, step by step), Scores (every combination as its dice and its
-- points), Examples (two turns of two throws, the dice to keep lit) and Drink (the hiccup, the
-- design). The dice are the table's bone die. Every number and every example on it comes from
-- FarkleRules, so a change to its constants changes the guide with it. It opens by itself the
-- first time the table opens, and on "How to play"; "Got it", the X and Escape close it, and it
-- opens again on the page it was left at.
---------------------------------------------------------------------------

do -- (the guide's own locals end with it: the file's main chunk keeps under 200)
local GW, GH = 680, 590            -- inside a 1024 x 768 screen at UI scale 1
local GL, GR = 32, GW - 40         -- the pages' left and right edges, clear of the parchment's torn rims
local SAFE = { 28, 10, GW - 38, GH - 16 }   -- where anything may be (x, y, right, bottom): inside the rims
local PAGES = { "FARKLE_G_RULES", "FARKLE_G_SCORES", "FARKLE_G_EXAMPLES", "FARKLE_G_DRINK" }
-- A die icon is one cell of icons.tga (the table's bone die rendered with each face square to the
-- frame, face v in column v of 8), never rotated: the shadow is baked in. A die `size` px wide is
-- drawn 2 x size wide; the die itself reaches 33.5/128 of that from its centre, the rest is its
-- shadow.
local ICONS = MEDIA .. "icons"
local REACH = 34 / 128 * 2
local HOT = { 0.58, 0.26, 0.0 }    -- HOT DICE on the parchment: the table's amber, darker
local PTS = { 0.42, 0.12, 0.03 }   -- the points on the parchment
local OFF = { 0.37, 0.23, 0.09 }   -- a tab not shown
local NUMBER = { "one", "two", "three", "four", "five", "six" }
-- The worked examples' throws: for each, the first of these that does what the example shows
-- under FarkleRules.SCORES, else the first throw of that many dice that does.
local PICKS = {
	first = { { 1, 3, 5, 2, 6, 2 }, { 1, 3, 4, 2, 6, 2 }, { 5, 3, 4, 2, 6, 2 } },  -- six dice, some score
	farkle = { { 2, 3, 4, 6 }, { 2, 3, 4, 6, 6 }, { 2, 3, 6 }, { 2, 6 }, { 3 } },  -- the rest: nothing scores
	triple = { { 4, 1, 4, 2, 4, 6 }, { 4, 2, 4, 3, 4, 6 }, { 3, 1, 3, 2, 3, 6 } }, -- three of a kind among them
	hot = { { 1, 5 }, { 1, 1 }, { 5, 5 } },                                         -- the rest: every die scores
}

local function NewPage(parent)
	local pg = CreateFrame("Frame", nil, parent)
	pg:SetAllPoints()
	pg.icons, pg.texts = {}, {}
	return pg
end

-- One line of text on a page, never wrapped: its top left at (x, y) from the page's top left, in a
-- box w wide (the points are right-justified in theirs).
local function Ink(pg, x, y, w, text, size, color, font, justify)
	local fs = Text(pg, size or 13, color or INK, font, justify or "LEFT")
	fs:SetPoint("TOPLEFT", pg, "TOPLEFT", x, -y)
	fs:SetWidth(w); fs:SetWordWrap(false); fs:SetText(text)
	pg.texts[#pg.texts + 1] = fs
	return fs
end

-- A faint ruled line across a page (or down it: Down).
local function Rule(pg, x, y, w, a)
	local t = pg:CreateTexture(nil, "BORDER")
	t:SetColorTexture(0.25, 0.13, 0.04, a or 0.16)
	t:SetPoint("TOPLEFT", pg, "TOPLEFT", x, -y); t:SetSize(w, 1)
	return t
end
local function Down(pg, x, y, h, a)
	local t = Rule(pg, x, y, 1, a)
	t:SetSize(1, h)
	return t
end

-- A die icon: face `value`, its centre at (x, y) from the page's top left (on a whole pixel), `size`
-- its edge. look: "kept" (lit on itself, like a die picked on the table), "dim" (a die not kept),
-- "dull" (a bust's grey bone) or nil. order: its place in its row, left to right: each die is drawn
-- over the one before it (whose shadow falls to the right), its light over itself only.
local function Icon(pg, value, x, y, size, look, order)
	local l, r = (value - 1) / 8, value / 8
	local sub = min(6, -8 + 2 * ((order or 1) - 1))
	local face = pg:CreateTexture(nil, "ARTWORK", nil, sub)
	face:SetTexture(ICONS); face:SetTexCoord(l, r, 0, 1)
	face:SetSize(2 * size, 2 * size)
	face:SetPoint("CENTER", pg, "TOPLEFT", floor(x + 0.5), -floor(y + 0.5))
	face.value, face.size, face.look = value, size, look
	if look == "kept" then
		local lit = pg:CreateTexture(nil, "ARTWORK", nil, sub + 1)
		lit:SetTexture(ICONS); lit:SetTexCoord(l, r, 0, 1); lit:SetBlendMode("ADD")
		lit:SetVertexColor(1, 0.74, 0.4); lit:SetAlpha(0.42); lit:SetAllPoints(face)
		face.lit = lit
	elseif look == "dim" then
		face:SetAlpha(0.5)
	elseif look == "dull" then
		face:SetDesaturated(true); face:SetVertexColor(0.74, 0.69, 0.63)
	end
	pg.icons[#pg.icons + 1] = face
	return face
end

-- A row of dice, the first die's left edge at x, their centres on y, `step` apart. items: { face,
-- look } each; a false item is a gap (between the dice set aside earlier and a throw).
local function Gap(step) return floor(step * 0.4 + 0.5) end
local function Dice(pg, items, x, y, size, step)
	local out, cx = {}, x + REACH * size
	for _, it in ipairs(items) do
		if it then out[#out + 1] = Icon(pg, it[1], cx, y, size, it[2], #out + 1); cx = cx + step
		else cx = cx + Gap(step) end
	end
	return out
end

local function Keys(list) local s = {}; for _, p in ipairs(list) do s[p] = true end; return s end
-- faces as row items: those at the positions in `kept` lit and the rest dimmed, or all one look
local function Items(faces, kept, look)
	local out = {}
	for i, v in ipairs(faces) do out[i] = { v, look or (kept and (kept[i] and "kept" or "dim")) or nil } end
	return out
end
-- the dice set aside earlier in the turn (lit), a gap, then a throw
local function AfterItems(before, throw)
	local out = Items(before, nil, "kept")
	out[#out + 1] = false
	for _, it in ipairs(throw) do out[#out + 1] = it end
	return out
end

-- Dice in words, most first: "a 1 and a 5", "three 4s and a 1"; with the: "the 1 and the 5". Also
-- the faces in that order and how many of each.
local function Words(faces, the)
	local count, order = {}, {}
	for _, f in ipairs(faces) do
		if not count[f] then order[#order + 1] = f end
		count[f] = (count[f] or 0) + 1
	end
	table.sort(order, function(a, b) if count[a] ~= count[b] then return count[a] > count[b] end return a < b end)
	local out = {}
	for i, f in ipairs(order) do
		local n = count[f]
		out[i] = (the and "the " or (n == 1 and "a " or "")) .. (n == 1 and tostring(f) or (NUMBER[n] .. " " .. f .. "s"))
	end
	local text = #out > 1 and (table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]) or out[1] or ""
	return text, order, count
end

-- What each face's dice score on their own, when that adds up to `points`: "Three 4s score 400,
-- and the 1 adds 100"; nil when it doesn't (a combination of all six dice).
local function Parts(faces, points)
	local _, order, count = Words(faces)
	local out, sum = {}, 0
	for i, f in ipairs(order) do
		local group = {}
		for k = 1, count[f] do group[k] = f end
		local s = FR().Score(group)
		if not s then return nil end
		sum = sum + s
		local one = count[f] == 1
		out[i] = (Words(group, i > 1)) .. (i == 1 and (one and " scores " or " score ") or (one and " adds " or " add ")) .. Num(s)
	end
	if sum ~= points or #out == 0 then return nil end
	out[1] = (out[1]:gsub("^%l", string.upper))
	return #out > 1 and (table.concat(out, ", ", 1, #out - 1) .. ", and " .. out[#out]) or out[1]
end

-- The first of `list` (of n dice, when n is given) that `ok` takes, else the first throw of n dice,
-- in the order of the server's roll, that it takes; nil when none does.
local function Find(list, n, ok)
	for _, dice in ipairs(list) do if (not n or #dice == n) and ok(dice) then return dice end end
	if n and FR().RANGES[n] then
		for roll = 1, FR().RANGES[n] do
			local dice = FR().Decode(roll, n)
			if dice and ok(dice) then return dice end
		end
	end
	return nil
end

-- The faces a worked throw keeps, in the order thrown.
local function KeptOf(t) local out = {}; for i, p in ipairs(t.kept) do out[i] = t.dice[p] end; return out end

-- The worked examples as FarkleRules plays them, two turns of two throws. first: six dice, some
-- score; farkle: the rest of them thrown, and nothing scores; triple: six dice, three of a kind
-- among those that score; hot: the rest of them thrown, and every one scores. Each is { dice,
-- points, kept (positions: Best's), before (the faces set aside earlier in the turn), turn (the
-- turn's points before this throw) }, or nil when FarkleRules.SCORES leaves no throw that shows it.
local function Worked()
	local R = FR()
	local function Throw1(dice, before, turn)
		local points, kept = R.Best(dice)
		return { dice = dice, points = points or 0, kept = kept or {}, before = before or {}, turn = turn or 0 }
	end
	local function Some(d) local p, k = R.Best(d); return p and p > 0 and #k < #d end
	local function All(d) local p, k = R.Best(d); return p and p > 0 and #k == #d end
	local function Three(d)
		if not Some(d) then return false end
		local _, k = R.Best(d)
		local c = {}
		for _, p in ipairs(k) do
			c[d[p]] = (c[d[p]] or 0) + 1
			if c[d[p]] >= 3 then return true end
		end
		return false
	end
	local ex = {}
	local d = Find(PICKS.first, nil, Some)
	if d then
		ex.first = Throw1(d)
		local set = KeptOf(ex.first)
		d = Find(PICKS.farkle, R.DICE - #set, R.Farkle)
		if d then ex.farkle = Throw1(d, set, ex.first.points) end
	end
	d = Find(PICKS.triple, nil, Three)
	if d then
		ex.triple = Throw1(d)
		local set = KeptOf(ex.triple)
		d = Find(PICKS.hot, R.DICE - #set, All)
		if d then ex.hot = Throw1(d, set, ex.triple.points) end
	end
	return ex
end

-- The combinations in four groups, with the points FarkleRules.Score gives the dice shown. A
-- combination set to false in SCORES is left out; four 1s get a row of their own when they score
-- other than four of another face. Runs come from SCORES.run rather than an older hard-coded
-- six-dice bonus list, so the guide cannot quietly disagree with the rules being played.
local function Combos()
	local R = FR()
	local Cs = R.SCORES
	local function On(v) return type(v) == "number" and v > 0 end
	local single, triple, kind = Cs.single or {}, Cs.triple or {}, Cs.kind or {}
	local groups = {
		{ key = "single", title = L.FARKLE_G_SINGLE, rows = {} },
		{ key = "triple", title = L.FARKLE_G_TRIPLE, rows = {} },
		{ key = "kind", title = L.FARKLE_G_KIND, rows = {} },
		{ key = "run", title = type(Cs.run) == "table" and L.FARKLE_G_RUNS or L.FARKLE_G_SIX, rows = {} },
	}
	local function Add(gi, on, dice, name)
		local points = on and R.Score(dice)
		local list = groups[gi].rows
		if points then list[#list + 1] = { dice = dice, name = name, points = points } end
	end
	Add(1, On(single[1]), { 1 }, L.FARKLE_G_EACH_1)
	Add(1, On(single[5]), { 5 }, L.FARKLE_G_EACH_5)
	for f = 1, 6 do Add(2, On(triple[f]), { f, f, f }, T("FARKLE_G_THREE_N", f)) end
	Add(3, On(kind[4]), { 3, 3, 3, 3 }, L.FARKLE_G_FOUR)
	if R.Score({ 1, 1, 1, 1 }) ~= R.Score({ 3, 3, 3, 3 }) then Add(3, true, { 1, 1, 1, 1 }, L.FARKLE_G_FOUR_1S) end
	Add(3, On(kind[5]), { 6, 6, 6, 6, 6 }, L.FARKLE_G_FIVE)
	Add(3, On(kind[6]), { 2, 2, 2, 2, 2, 2 }, L.FARKLE_G_SIX_KIND)
	if type(Cs.run) == "table" then
		local runs = {}
		for faces, points in pairs(Cs.run) do
			if On(points) and type(faces) == "string" and faces ~= "" and not faces:find("[^1-6]") then
				runs[#runs + 1] = faces
			end
		end
		table.sort(runs)
		for _, faces in ipairs(runs) do
			local dice, label = {}, {}
			for i = 1, #faces do
				dice[i] = tonumber(faces:sub(i, i)); label[i] = faces:sub(i, i)
			end
			Add(4, true, dice, faces == "123456" and L.FARKLE_G_STRAIGHT or T("FARKLE_G_RUN_N", table.concat(label, "-")))
		end
	else
		-- Backwards-compatible rows for a custom/older rule table.
		Add(4, On(Cs.straight), { 1, 2, 3, 4, 5, 6 }, L.FARKLE_G_STRAIGHT)
		Add(4, On(Cs.threePairs), { 2, 2, 4, 4, 6, 6 }, L.FARKLE_G_PAIRS)
		Add(4, On(Cs.fourAndPair), { 3, 3, 3, 3, 6, 6 }, L.FARKLE_G_FOUR_PAIR)
		Add(4, On(Cs.twoTriplets), { 2, 2, 2, 4, 4, 4 }, L.FARKLE_G_TRIPLETS)
	end
	return groups
end

-- A picture of one of the table's buttons, as it reads there (it can't be clicked): its left edge
-- at x, centred on y.
local function Picture(pg, label, x, y, w)
	local b = CreateFrame("Button", nil, pg, "UIPanelButtonTemplate")
	b:SetSize(w, 24); b:SetText(label); b:EnableMouse(false)
	b:SetPoint("LEFT", pg, "TOPLEFT", x, -y)
	return b
end

local function List(l) return #l > 1 and (table.concat(l, ", ", 1, #l - 1) .. " or " .. l[#l]) or (l[1] or "") end

-- Rules: the goal, then a turn in five steps, each with its picture on the right (the dice of the
-- worked examples, or the table's buttons).
local function RulesPage(pg, ex)
	local R = FR()
	local tl, caps = {}, {}
	for i, v in ipairs(R.TARGETS) do
		tl[i] = Num(v)
		if R.TURN_CAP and R.TURN_CAP[v] then caps[#caps + 1] = tostring(R.TURN_CAP[v]) end
	end
	Ink(pg, GL, 104, 300, L.FARKLE_G_GOAL, 18, INK, MORPHEUS)
	local goal = {
		T("FARKLE_G_GOAL_1", List(tl)),
		L.FARKLE_G_GOAL_2,
		L.FARKLE_G_GOAL_3,
	}
	if #caps == #tl and #caps > 0 then goal[4] = T("FARKLE_G_GOAL_4", List(caps)) end
	pg.goal = {}
	for i, s in ipairs(goal) do pg.goal[i] = Ink(pg, GL, 128 + (i - 1) * 18, GR - GL, s) end
	local top = 128 + #goal * 18 + 8
	Ink(pg, GL, top, 300, L.FARKLE_G_YOUR_TURN, 18, INK, MORPHEUS)
	local a, b, d = ex.first, ex.farkle, ex.hot
	-- each: { title, line, line, its dice, its buttons, the title's ink, how many of its dice were
	-- set aside before the throw }
	local steps = {
		{ L.FARKLE_G_S_ROLL, T("FARKLE_G_S_ROLL_1", R.DICE), L.FARKLE_G_S_ROLL_2, a and Items(a.dice) },
		{ L.FARKLE_G_S_KEEP, L.FARKLE_G_S_KEEP_1, L.FARKLE_G_S_KEEP_2, a and Items(a.dice, Keys(a.kept)) },
		{ L.FARKLE_G_S_CHOOSE, L.FARKLE_G_S_CHOOSE_1, L.FARKLE_G_S_CHOOSE_2, nil,
			a and { T("FARKLE_B_KEEP_N", #a.dice - #a.kept), T("FARKLE_B_BANK_N", Num(a.points)) } },
		{ L.FARKLE_B_BONES, L.FARKLE_G_S_BONES_1, L.FARKLE_G_S_BONES_2,
			b and AfterItems(b.before, Items(b.dice, nil, "dull")), nil, RED, b and #b.before },
		{ L.FARKLE_B_HOT, L.FARKLE_G_S_HOT_1, L.FARKLE_G_S_HOT_2,
			d and AfterItems(d.before, Items(d.dice, Keys(d.kept))), nil, HOT, d and #d.before },
	}
	-- the pictures in a column of their own, its left edge where the widest fits
	local dx = GR - 170
	pg.steps = {}
	for i, s in ipairs(steps) do
		local y = top + 32 + (i - 1) * 54
		if i > 1 then Rule(pg, GL, y - 10, GR - GL, 0.12) end
		local step = {
			n = Ink(pg, GL, y - 2, 18, tostring(i), 18, PTS, MORPHEUS),
			title = Ink(pg, 52, y - 1, 104, s[1], 16, s[6] or INK, MORPHEUS),
			lines = { Ink(pg, 160, y, dx - 14 - 160, s[2]), Ink(pg, 160, y + 17, dx - 14 - 160, s[3]) },
		}
		if s[4] then step.icons, step.before = Dice(pg, s[4], dx, y + 16, 22, 27), s[7] or 0 end
		if s[5] then step.buttons = { Picture(pg, s[5][1], dx, y + 16, 100), Picture(pg, s[5][2], dx + 104, y + 16, 64) } end
		pg.steps[i] = step
	end
end

-- Scores: every combination as its dice and its points, in two columns of two groups, a line
-- between the columns; then how dice combine.
local function ScoresPage(pg)
	local R = FR()
	local groups = Combos()
	pg.rows, pg.heads = {}, {}
	local mid = 276
	local bottom = 104
	for _, col in ipairs({ { groups[1], groups[2], x = GL, r = mid - 20 }, { groups[3], groups[4], x = mid + 20, r = GR } }) do
		local most = 0
		for _, g in ipairs(col) do for _, row in ipairs(g.rows) do most = max(most, #row.dice) end end
		local nameX = floor(col.x + (most - 1) * 27 + 2 * REACH * 22 + 14)   -- (clear of the last die's shadow)
		local y = 104
		for gi, g in ipairs(col) do
			if #g.rows > 0 then
				if gi > 1 then y = y + 8 end
				local head = Ink(pg, col.x, y, col.r - col.x, g.title, 16, INK, MORPHEUS)
				pg.heads[#pg.heads + 1] = head
				y = y + 28
				for _, row in ipairs(g.rows) do
					pg.rows[#pg.rows + 1] = {
						combo = row, group = g.key, head = head,
						icons = Dice(pg, Items(row.dice), col.x, y + 17, 22, 27),
						name = Ink(pg, nameX, y + 10, col.r - 64 - nameX, row.name),
						points = Ink(pg, col.r - 60, y + 8, 60, Num(row.points), 16, PTS, MORPHEUS, "RIGHT"),
					}
					Rule(pg, col.x, y + 35, col.r - col.x)
					y = y + 36
				end
			end
		end
		bottom = max(bottom, y)
	end
	pg.divider = Down(pg, mid, 108, bottom - 112, 0.2)
	-- how dice combine: within one throw, adding up (1 1 5 as dice), and why four 1s score more
	local y = bottom + 12
	pg.notes = { Ink(pg, GL, y, GR - GL, L.FARKLE_G_NOTE_ONE_THROW, 13, SOFT) }
	local four, three, one = R.Score({ 1, 1, 1, 1 }), R.Score({ 1, 1, 1 }), R.Score({ 1 })
	local fours
	for _, row in ipairs(pg.rows) do if row.combo.name == L.FARKLE_G_FOUR_1S then fours = three and one and four == three + one end end
	local add = R.Score({ 1, 1, 5 })
	y = y + 24
	if add then
		pg.notes[2] = Ink(pg, GL, y, 140, L.FARKLE_G_NOTE_ADD, 13, SOFT)
		pg.addUp = Dice(pg, Items({ 1, 1, 5 }), GL + 144, y + 8, 22, 27)
		pg.notes[3] = Ink(pg, GL + 230, y, GR - GL - 230, T(fours and "FARKLE_G_NOTE_IS_FOURS" or "FARKLE_G_NOTE_IS", Num(add)), 13, SOFT)
	elseif fours then
		pg.notes[2] = Ink(pg, GL, y, GR - GL, L.FARKLE_G_NOTE_FOURS, 13, SOFT)
	end
end

-- Examples: two turns of two throws, the dice set aside earlier lit before a gap, the dice to keep
-- lit, what happens and the points.
local function ExamplesPage(pg, ex)
	local a, b, c, d = ex.first, ex.farkle, ex.triple, ex.hot
	local list = {}
	if a then
		local kept, left = KeptOf(a), #a.dice - #a.kept
		list[#list + 1] = { e = a, turn = 1, title = "Keep " .. (Words(kept)), label = "+" .. Num(a.points), lines = {
			("You throw %s. Only %s score%s."):format(table.concat(a.dice, " "), (Words(kept, true)), #kept == 1 and "s" or ""),
			("Keep %s for %s, then roll the other %s or bank."):format(#kept == 1 and "it" or "them", Num(a.points), NUMBER[left] or left) } }
	end
	if b then
		list[#list + 1] = { e = b, turn = 1, title = L.FARKLE_B_BONES, color = RED, label = Num(b.turn) .. " lost", lost = true, lines = {
			("Then you roll the other %s: %s."):format(NUMBER[#b.dice] or #b.dice, table.concat(b.dice, " ")),
			("Nothing scores: the turn ends, and its %s is lost."):format(Num(b.turn)) } }
	end
	if c then
		local kept, left = KeptOf(c), #c.dice - #c.kept
		local parts = Parts(kept, c.points)
		list[#list + 1] = { e = c, turn = 2, title = "Keep " .. (Words(kept)), label = "+" .. Num(c.points), lines = {
			parts and (parts .. ".") or ("You throw %s: the lit dice score %s."):format(table.concat(c.dice, " "), Num(c.points)),
			("Keep %s for %s, then roll the last %s or bank."):format(#kept == 1 and "it" or ("all " .. NUMBER[#kept]), Num(c.points), NUMBER[left] or left) } }
	end
	if d then
		local n, roll = #d.dice, table.concat(d.dice, " ")
		local what = n == 1 and ("Then you roll the last die, a %s: it scores."):format(roll)
			or n == 2 and ("Then you roll the last two, %d and %d: both score."):format(d.dice[1], d.dice[2])
			or ("Then you roll the last %s, %s: all score."):format(NUMBER[n] or n, roll)
		list[#list + 1] = { e = d, turn = 2, title = L.FARKLE_B_HOT, color = HOT, label = "+" .. Num(d.points), lines = {
			what, ("All six dice have scored: roll six again, %s kept."):format(Num(d.turn + d.points)) } }
	end
	Ink(pg, GL, 104, GR - GL, #list == 4 and L.FARKLE_G_EX_INTRO or L.FARKLE_G_EX_INTRO_SHORT, 13, SOFT)
	local tx = GL + 222
	pg.examples = {}
	for i, x in ipairs(list) do
		local y, e = 136 + (i - 1) * 98, x.e
		-- a firmer line between the turns
		if i > 1 then Rule(pg, GL, y - 19, GR - GL, x.turn ~= list[i - 1].turn and 0.3 or 0.12) end
		local throw = Items(e.dice, e.points > 0 and Keys(e.kept) or nil, e.points == 0 and "dull" or nil)
		local icons = Dice(pg, #e.before > 0 and AfterItems(e.before, throw) or throw, GL, y + 30, 26, 32)
		local before, thrown = {}, {}
		for k, t in ipairs(icons) do if k <= #e.before then before[k] = t else thrown[#thrown + 1] = t end end
		pg.examples[i] = {
			example = e, farkle = e.points == 0, before = before, icons = thrown,
			title = Ink(pg, tx, y, GR - 116 - tx, x.title, 17, x.color or INK, MORPHEUS),
			points = Ink(pg, GR - 110, y - 2, 110, x.label, 20, x.lost and RED or PTS, MORPHEUS, "RIGHT"),
			lines = { Ink(pg, tx, y + 26, GR - tx, x.lines[1]), Ink(pg, tx, y + 44, GR - tx, x.lines[2]) },
		}
	end
end

-- The game's own drunk line for a level, read live from the client's globals (every locale shows
-- its own words): DRUNK_MESSAGE_SELF1 (sober) to SELF4 (completely smashed).
local function DrunkLine(lvl)
	local s = rawget(_G, "DRUNK_MESSAGE_SELF" .. (lvl + 1))
	if type(s) ~= "string" or s == "" then return nil end
	return (s:gsub("%s%s+", " "))
end
Board.DrunkLine = DrunkLine

-- Drink (the design): the four levels as the board's mugs, each with the game's line and what it gives
-- (FarkleRules.HICCUP, SHAKES); how it works in three steps; one worked bust shaken off, with the
-- dice icons; the price.
local function DrinkPage(pg)
	local R = FR()
	Ink(pg, GL, 104, GR - GL, T("FARKLE_G_DRINK_INTRO"), 13, SOFT)
	local icon = (ns.UI and ns.UI.FirstTexture) and ns.UI.FirstTexture(MUGS) or MUGS[1]
	pg.levels = {}
	for lvl = 0, 3 do
		local y = 128 + lvl * 42
		if lvl > 0 then Rule(pg, GL, y - 6, GR - GL, 0.12) end
		local mug = pg:CreateTexture(nil, "ARTWORK")
		mug:SetTexture(icon); mug:SetTexCoord(0.08, 0.92, 0.08, 0.92); mug:SetSize(28, 28)
		mug:SetPoint("TOPLEFT", pg, "TOPLEFT", GL, -(y + 2))
		mug:SetDesaturated(true); mug:SetVertexColor(0.6, 0.56, 0.5)
		local f = FILL[lvl]
		local fill
		if f > 0 then
			fill = pg:CreateTexture(nil, "ARTWORK", nil, 1)
			fill:SetTexture(icon); fill:SetTexCoord(0.08, 0.92, 0.92 - 0.84 * f, 0.92)
			fill:SetSize(28, 28 * f); fill:SetPoint("BOTTOMLEFT", mug, "BOTTOMLEFT", 0, 0)
			fill.fillOf = mug
		end
		local wins, total, pct = R.HiccupOdds(6, lvl)
		local n = OneIn(pct)
		local row = {
			level = lvl, mug = mug, fill = fill, pct = pct, wins = wins, total = total,
			name = Ink(pg, GL + 40, y, 220, LevelName(lvl), 16, INK, MORPHEUS),
			line = Ink(pg, GL + 40, y + 20, 360, DrunkLine(lvl) or "", 13, SOFT),
			gives = Ink(pg, GR - 200, y, 200, n and T("FARKLE_G_DRINK_GIVES", wins, total) or L.FARKLE_G_DRINK_NONE, 16, n and PTS or SOFT, MORPHEUS, "RIGHT"),
			shakes = n and Ink(pg, GR - 200, y + 20, 200, T("FARKLE_G_DRINK_SHAKES", R.SHAKES), 13, SOFT, nil, "RIGHT") or nil,
		}
		pg.levels[#pg.levels + 1] = row
	end
	local y = 128 + 4 * 42 + 4
	Ink(pg, GL, y, 300, L.FARKLE_G_DRINK_HOW, 16, INK, MORPHEUS)
	pg.steps = {
		Ink(pg, GL, y + 24, GR - GL, L.FARKLE_G_DRINK_STEP_1),
		Ink(pg, GL, y + 54, GR - GL, L.FARKLE_G_DRINK_STEP_2),
		Ink(pg, GL, y + 84, GR - GL, L.FARKLE_G_DRINK_STEP_3),
		Ink(pg, GL, y + 114, GR - GL, L.FARKLE_G_DRINK_ARRIVED),
	}
	-- The original ordered four-dice throw itself decides HIC!, with no second roll.
	local top = y + 146
	Rule(pg, GL, top - 6, GR - GL, 0.3)
	local bust = Find({ { 2, 2, 3, 3 }, { 2, 3, 4, 6 }, { 2, 2, 3, 6 } }, 4, R.Farkle)
	local wins, total, pct = R.HiccupOdds(4, 3)
	local saved, rank = R.HiccupReuse(bust, 3)
	pg.example = { dice = bust, rank = rank, saved = saved, wins = wins, total = total, pct = pct }
	if bust then
		pg.example.icons = Dice(pg, Items(bust, nil, "dull"), GL, top + 30, 22, 27)
	end
	pg.example.title = Ink(pg, GL + 140, top, GR - GL - 140, L.FARKLE_G_DRINK_EX_TITLE, 16, HOT, MORPHEUS)
	pg.example.lines = {
		Ink(pg, GL + 140, top + 22, GR - GL - 140, T("FARKLE_G_DRINK_EX_1", wins, total)),
		Ink(pg, GL + 140, top + 40, GR - GL - 140, T("FARKLE_G_DRINK_EX_2", rank or 0)),
	}
	pg.price = Ink(pg, GL, top + 66, GR - GL, L.FARKLE_G_DRINK_PRICE, 13, SOFT)
end

-- The page shown: its tab in dark ink with a bar under it, Back and Next where there is a page to
-- go to.
local function Page(k)
	k = max(1, min(#PAGES, k or 1))
	S.page = k
	for i, pg in ipairs(help.pages) do
		pg:SetShown(i == k)
		local tab, c = help.tabs[i], i == k and INK or OFF
		tab.text:SetTextColor(c[1], c[2], c[3])
		tab.bar:SetAlpha(0.9); tab.bar:SetShown(i == k)
	end
	help.back:SetShown(k > 1)
	help.next:SetShown(k < #PAGES)
end
Board.Page = Page

local function Help()
	help = CreateFrame("Frame", "OlympusArenaBoneThrowRules", UIParent)
	help:SetSize(GW, GH)
	-- centred on the screen, over the table: "Got it", the X or Escape go back to the game
	help:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	help:SetFrameStrata("FULLSCREEN_DIALOG"); help:SetToplevel(true)
	Movable(help)
	Parchment(help)
	-- Match the framed game pop-ups. Keep the thin parchment frame if this client lacks the template.
	local okBorder, border = pcall(CreateFrame, "Frame", nil, help, "DialogBorderTemplate")
	if okBorder and border then
		border:SetPoint("TOPLEFT", help, "TOPLEFT", -10, 10)
		border:SetPoint("BOTTOMRIGHT", help, "BOTTOMRIGHT", 10, -10)
		if rawget(border, "Bg") then border.Bg:Hide() end
		help.border = border
		for _, texture in ipairs(help.frame) do texture:Hide() end
	end
	local x = CreateFrame("Button", nil, help, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", help, "TOPRIGHT", help.border and 6 or 2, help.border and 6 or 2)
	x:SetScript("OnClick", function() help:Hide() end)
	help.close = x
	help.title = Text(help, 24, INK, MORPHEUS); help.title:SetPoint("TOP", 0, -16)
	help.title:SetText(L.FARKLE_G_TITLE)
	-- the pages, and a tab for each: its name in Morpheus (not a button like Back, Got it and Next),
	-- a bar of ink under it when shown, a faint one while the mouse is on another
	help.pages, help.tabs = {}, {}
	local tw, gap = 120, 16
	local tx = (GW - #PAGES * tw - (#PAGES - 1) * gap) / 2
	for k, key in ipairs(PAGES) do
		help.pages[k] = NewPage(help)
		help.pages[k].name = L[key]
		local tab = CreateFrame("Button", nil, help)
		tab:SetSize(tw, 28); tab:SetPoint("TOPLEFT", help, "TOPLEFT", tx + (k - 1) * (tw + gap), -52)
		tab.text = Text(tab, 18, OFF, MORPHEUS)
		tab.text:SetPoint("CENTER", 0, 0); tab.text:SetWidth(tw); tab.text:SetWordWrap(false); tab.text:SetText(L[key])
		tab.bar = tab:CreateTexture(nil, "ARTWORK")
		tab.bar:SetColorTexture(PTS[1], PTS[2], PTS[3], 1); tab.bar:SetSize(tw - 36, 3)
		tab.bar:SetPoint("TOP", tab, "BOTTOM", 0, -2); tab.bar:Hide()
		tab:SetScript("OnClick", function() Page(k) end)
		tab:SetScript("OnEnter", function() if S.page ~= k then tab.bar:SetAlpha(0.35); tab.bar:Show() end end)
		tab:SetScript("OnLeave", function() if S.page ~= k then tab.bar:Hide() end end)
		help.tabs[k] = tab
	end
	local ex = Worked()
	help.worked = ex
	RulesPage(help.pages[1], ex)
	ScoresPage(help.pages[2])
	ExamplesPage(help.pages[3], ex)
	DrinkPage(help.pages[4])
	Rule(help, GL, 92, GR - GL, 0.3)
	Rule(help, GL, GH - 60, GR - GL, 0.3)
	help.back = Button(help, L.FARKLE_G_BACK, 110, 32, function() Page(S.page - 1) end)
	help.back:SetPoint("TOPLEFT", help, "TOPLEFT", GL, -(GH - 50))
	help.ok = Button(help, L.FARKLE_G_GOT_IT, 140, 32, function() help:Hide() end)
	help.ok:SetPoint("TOP", help, "TOPLEFT", GW / 2, -(GH - 50))
	help.next = Button(help, L.FARKLE_G_NEXT, 110, 32, function() Page(S.page + 1) end)
	help.next:SetPoint("TOPRIGHT", help, "TOPLEFT", GR, -(GH - 50))
	Page(S.page or 1)
	help:Hide()
	help:SetScript("OnShow", function() if EscSync then EscSync() end end)
	help:SetScript("OnHide", function() if EscSync then EscSync() end end)
end

Board.guide = { W = GW, H = GH, SAFE = SAFE, PAGES = PAGES, MORPHEUS = MORPHEUS, ICONS = ICONS, INK = INK, OFF = OFF, REACH = REACH }

-- Shows the guide (built the first time), on the page it was left at.
function Board.ShowGuide()
	if not help then Help() end
	help:Show()
	help:Raise()
	return help
end
end

-- The guide shows by itself the first time the table opens (kept with this character's Bone
-- Throw options; on the beta, whose saved data is forgotten, once a session).
local function FirstUse()
	local o = FT().Opts and FT().Opts() or {}
	if S.guideSeen or o.guideSeen then return end
	S.guideSeen = true
	o.guideSeen = true
	Board.ShowGuide()
end

---------------------------------------------------------------------------
-- The invitation and the arbiter's pop-ups (Olympus's own, never the game's): what the table is,
-- the hiccup's line (the design), and Accept or Decline. The invitation lasts a minute.
---------------------------------------------------------------------------

do -- (the pop-ups' own locals)
local function StakeLine(t)
	if (t.stake or 0) <= 0 then return ForPoints() and L.FARKLE_B_POINTS_FUN or L.FARKLE_B_ASK_NO_STAKE end
	if t.kind == "d" then return T("FARKLE_B_ASK_DIRECT", Money(t.stake)) end
	local src = t.src and t.src[1]
	return T(src == "w" and "FARKLE_B_ASK_WALLET" or "FARKLE_B_ASK_TRADE", Money(t.stake), Name(t.arbiter))
end
local function HiccupLines(t)
	local R = FR()
	if t.hic then
		if t.hiccupRule == "bones2" then return L.FARKLE_B_HIC_ON, L.FARKLE_G_DRINK_STEP_2 end
		return L.FARKLE_B_HIC_ON, T("FARKLE_B_HIC_RULE", R.HICCUP[1] or 0, R.HICCUP[2] or 0, R.HICCUP[3] or 0, R.SHAKES or 0)
	end
	if not FT().DrunkReadable() then return L.FARKLE_B_SOBER_MINE, "" end
	return T("FARKLE_B_SOBER_ASKED", Name(t.host)), ""
end

local function Ask()
	ask = CreateFrame("Frame", "OlympusArenaBoneThrowAsk", UIParent)
	ask:SetSize(460, 300)
	ask:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	ask:SetFrameStrata("FULLSCREEN_DIALOG"); ask:SetToplevel(true)
	Movable(ask)
	Parchment(ask)
	ask.title = Text(ask, 22, INK, MORPHEUS); ask.title:SetPoint("TOP", 0, -16); ask.title:SetWidth(420); ask.title:SetWordWrap(false)
	ask.lines = {}
	for i = 1, 6 do
		local fs = Text(ask, 13, i == 1 and INK or SOFT, nil, "LEFT")
		fs:SetPoint("TOPLEFT", ask, "TOPLEFT", 26, -(56 + (i - 1) * 20)); fs:SetWidth(408); fs:SetWordWrap(false)
		ask.lines[i] = fs
	end
	ask.sober = Check(ask, L.FARKLE_B_ASK_SOBER)
	ask.sober:SetPoint("TOPLEFT", ask, "TOPLEFT", 24, -178)
	ask.spec = Check(ask, L.FARKLE_B_C_SPECTATORS)
	ask.spec:SetPoint("TOPLEFT", ask, "TOPLEFT", 240, -178)
	ask.clock = Text(ask, 13, SOFT, nil, "LEFT")
	ask.clock:SetPoint("TOPLEFT", ask, "TOPLEFT", 26, -218); ask.clock:SetWidth(408); ask.clock:SetWordWrap(false)
	ask.yes = Button(ask, L.FARKLE_B_ACCEPT, 140, 32, function() Board.Answer(true) end)
	ask.yes:SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -10, 20)
	ask.no = Button(ask, L.FARKLE_B_DECLINE, 140, 32, function() Board.Answer(false) end)
	ask.no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 10, 20)
	local x = CreateFrame("Button", nil, ask, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", ask, "TOPRIGHT", 2, 2)
	x:SetScript("OnClick", function() ask:Hide() end)
	ask.close = x
	ask:SetScript("OnHide", function() if ask.ticker then ask.ticker:Cancel(); ask.ticker = nil end; if EscSync then EscSync() end end)
	ask:SetScript("OnShow", function() if EscSync then EscSync() end end)
	ask:Hide()
end

local function AskRefresh()
	local t = ask.id and FT().Get(ask.id)
	if not t or (ask.kind == "invite" and t.state ~= "invite") or (ask.kind == "arbiter" and t.state ~= "asked") then
		ask:Hide()
		return
	end
	local left = max(0, floor((FT().INVITE_TTL or 60) - (Now() - ((ask.kind == "invite" and t.invitedAt) or t.askedAt or Now())) + 0.5))
	ask.clock:SetText(T("FARKLE_B_ASK_CLOCK", left))
	local ok, why = true, nil
	if ask.kind == "invite" then ok, why = A().Can("farkle.answer", ask.id, true) end
	if ok then ask.yes:Enable() else ask.yes:Disable(); ask.clock:SetText(WhyText(why)) end
end

-- The pop-up for an invitation (kind "invite") or a request to arbitrate (kind "arbiter").
function Board.ShowAsk(kind, id)
	local t = FT().Get(id)
	if not t then return nil end
	if not ask then Ask() end
	ask.kind, ask.id = kind, id
	local h1, h2 = HiccupLines(t)
	if kind == "invite" then
		ask.title:SetText(L.FARKLE_B_ASK_TITLE)
		ask.lines[1]:SetText(T("FARKLE_B_ASK_INVITES", Name(t.host)))
		ask.lines[2]:SetText(T("FARKLE_B_ASK_TERMS", Num(t.target), t.secs or 60))
		ask.lines[3]:SetText(StakeLine(t))
		ask.lines[4]:SetText(t.mode == "T" and L.FARKLE_B_ASK_REHEARSAL or L.FARKLE_B_ASK_TAVERN) -- (every game that counts: a tavern or a camp)
		ask.lines[5]:SetText(h1); ask.lines[6]:SetText(h2)
		ask.sober:SetShown(t.hic == true); ask.sober:SetOn(false)
		ask.spec:Show(); ask.spec:SetOn(true)
	else
		ask.title:SetText(L.FARKLE_B_ARB_TITLE)
		ask.lines[1]:SetText(T("FARKLE_B_ARB_ASKS", Name(t.host), Name(t.guest)))
		ask.lines[2]:SetText(T("FARKLE_B_ASK_TERMS", Num(t.target), t.secs or 60))
		ask.lines[3]:SetText(T((t.src and t.src[1] == "w") and "FARKLE_B_ARB_WALLET" or "FARKLE_B_ARB_TRADE", Money(t.stake or 0)))
		local settings = Settings()
		ask.lines[4]:SetText(T("FARKLE_B_ARB_FEE", floor((settings.arbBp or 200) / 100)))
		ask.lines[5]:SetText(h1); ask.lines[6]:SetText(h2)
		ask.sober:Hide(); ask.spec:Hide()
	end
	if ask.ticker then ask.ticker:Cancel() end
	ask.ticker = C_Timer.NewTicker(0.5, function() if ask:IsShown() then AskRefresh() end end)
	AskRefresh()
	ask:Show()
	ask:Raise()
	return ask
end

function Board.Answer(yes)
	if not ask or not ask.id then return end
	local id, kind = ask.id, ask.kind
	local ok, why
	if kind == "invite" then
		ok, why = A().Do("farkle.answer", id, yes, nil, { hic = not ask.sober.checked, spectators = ask.spec.checked })
	else
		ok, why = A().Do("farkle.arbitrate", id, yes)
	end
	if not ok then ask.clock:SetText(WhyText(why)) return end
	ask:Hide()
	if yes then Board.Show(id) end
end

Board.AskRefresh = AskRefresh
end

---------------------------------------------------------------------------
-- The result card (the design): once the game's money is settled for this player (a practice or
-- an unstaked game: at its end), in front, a strata above the table. The UI kit's card where the
-- build has one (ArenaUI.ResultCard), else this one: the verdict big and coloured, the game and
-- the opponent in one line, then Bet, Won or Lost, and the balance or what to pay, in exact copper.
---------------------------------------------------------------------------

do -- (the card's own locals)
local function Card()
	card = ns.Window("OlympusArenaBoneThrowResult", UIParent, { inset = false, close = false, escape = false, title = L.FARKLE_NAME })
	card:SetSize(500, 310)
	card:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	card:SetFrameStrata("FULLSCREEN_DIALOG"); card:SetToplevel(true)
	Movable(card)
	local kit = ArenaUI.Kit
	if kit and kit.Parchment then card.bg = kit.Parchment(card, 10) else Parchment(card) end
	card.verdict = Text(card, 30, GREEN, MORPHEUS); card.verdict:SetPoint("TOP", 0, -40); card.verdict:SetWidth(440); card.verdict:SetWordWrap(false)
	card.line = Text(card, 13, SOFT); card.line:SetPoint("TOP", 0, -79); card.line:SetWidth(440); card.line:SetWordWrap(false)
	card.tagline = Text(card, 14, INK); card.tagline:SetPoint("TOP", 0, -105); card.tagline:SetWidth(440)
	card.rows = {}
	for i = 1, 3 do
		local l = Text(card, 13, INK, nil, "LEFT")
		l:SetPoint("TOPLEFT", card, "TOPLEFT", 30, -(139 + (i - 1) * 24)); l:SetWidth(210); l:SetWordWrap(false)
		local r = Text(card, 13, INK, nil, "RIGHT")
		r:SetPoint("TOPRIGHT", card, "TOPRIGHT", -30, -(139 + (i - 1) * 24)); r:SetWidth(210); r:SetWordWrap(false)
		card.rows[i] = { l = l, r = r }
	end
	card.note = Text(card, 13, SOFT, nil, "LEFT")
	card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 30, -210); card.note:SetSize(440, 38)
	card.note:SetJustifyV("TOP"); card.note:SetMaxLines(2)
	card.buttons = {}
	for i = 1, 3 do
		local b = Button(card, "", 138, 32, function(self) if self.fn then self.fn() end end)
		b:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 30 + (i - 1) * 151, 18)
		card.buttons[i] = b
	end
	local x = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", card, "TOPRIGHT", 2, 2)
	x:SetScript("OnClick", function() card:Hide() end)
	card:SetScript("OnShow", function() if EscSync then EscSync() end end)
	card:SetScript("OnHide", function() if EscSync then EscSync() end end)
	card:Hide()
end

-- The card's content for a finished table: { verdict, line, rows = { { label, amount } }, note,
-- buttons = { { label, fn } }, bet, won, lost, points }.
function Board.CardSpec(id)
	local v = FT().View(id)
	if not v or not v.over then return nil end
	local spec = { game = "farkle", rows = {}, buttons = {} }
	if v.watching then return nil end
	local mine = v.seat and v.seat or nil
	if v.winner and mine then spec.verdict = v.winner == mine and "won" or "lost"
	elseif v.winner then spec.verdict = "done"
	else spec.verdict = "back" end
	local other = mine and Name(v.players[3 - mine]) or nil
	spec.line = v.practice and T("FARKLE_B_CARD_PRACTICE", other or L.FARKLE_HOUSE) or (other and T("FARKLE_B_CARD_VS", other) or T("FARKLE_B_CARD_TABLE", Name(v.players[1]), Name(v.players[2])))
	spec.tagline = spec.verdict == "won" and L.FARKLE_B_CARD_VICTORY_LINE or spec.verdict == "lost" and L.FARKLE_B_CARD_DEFEAT_LINE or ""
	local s = v.scores or { 0, 0 }
	local stake = v.stake or 0
	if stake <= 0 or v.practice or v.rehearsal or not mine then
		spec.points = mine and { s[mine], s[3 - mine] } or { s[1], s[2] }
		spec.rows[1] = { L.FARKLE_B_CARD_YOUR_POINTS, Num(spec.points[1]) }
		spec.rows[2] = { other and T("FARKLE_B_CARD_THEIR_POINTS", other) or L.FARKLE_B_CARD_POINTS, Num(spec.points[2]) }
		if v.rehearsal then spec.note = L.FARKLE_B_CARD_REHEARSAL
		elseif not v.practice then spec.note = ForPoints() and L.FARKLE_B_POINTS_FUN or L.FARKLE_B_CARD_NO_STAKE end
	else
		local settings = Settings()
		spec.bet = stake
		spec.rows[1] = { L.FARKLE_B_CARD_BET, Money(stake) }
		if spec.verdict == "won" then
			local guild, arb, net
			if v.kind == "a" then guild, arb, net = Call("ArenaMath", "Fees", stake, settings.feeBp, settings.arbBp, "arbiter")
			else guild, arb, net = Call("ArenaMath", "Fees", stake, settings.feeBp, 0, "direct") end
			net = net or (stake - FT().DirectFee(stake))
			spec.won = net
			spec.rows[2] = { L.FARKLE_B_CARD_WON, "+" .. Money(net) }
			spec.feeLine = v.kind == "a" and T("FARKLE_B_CARD_FEE_ARB", floor((settings.feeBp or 600) / 100), floor(((settings.feeBp or 600) - (settings.arbBp or 200)) / 100), floor((settings.arbBp or 200) / 100))
				or T("FARKLE_B_CARD_FEE", floor((settings.feeBp or 600) / 100))
			spec.note = spec.feeLine
		elseif spec.verdict == "lost" then
			spec.lost = stake
			spec.rows[2] = { L.FARKLE_B_CARD_LOST, "-" .. Money(stake) }
		else
			spec.rows[2] = { L.FARKLE_B_CARD_BACK, Money(stake) }
		end
		-- what is still to do, or where the gold is
		local src = v.src and v.src[mine]
		for _, l in ipairs(v.lines or {}) do
			if l.kind == "pay" then
				spec.rows[3] = { L.FARKLE_B_CARD_TO_PAY, T("FARKLE_B_CARD_OWE", Name(l.to), Money(l.copper - (l.paid or 0))) }
				spec.buttons[#spec.buttons + 1] = { L.FARKLE_B_PAY, function() A().Do("farkle.pay", id) end }
			elseif l.kind == "fee" then
				spec.rows[3] = { L.FARKLE_B_CARD_FEE_ROW, Money(FT().DirectFee(stake)) }
				spec.buttons[#spec.buttons + 1] = { L.FARKLE_B_PAY_FEE, function() A().Do("farkle.payfee", id) end }
			end
		end
		if not spec.rows[3] then
			if src == "w" and Call("Compliance", "Wallet") == true then
				local w = ns.ArenaHome and ns.ArenaHome.Data and ns.ArenaHome.Data.Wallet and ns.ArenaHome.Data.Wallet()
				local bal = type(w) == "table" and type(w.g) == "table" and w.g.bal
				spec.rows[3] = { L.FARKLE_B_CARD_BALANCE, bal and Money(bal) or L.FARKLE_B_CARD_IN_WALLET }
			elseif src == "t" then
				spec.rows[3] = { L.FARKLE_B_CARD_BALANCE, v.settled and T("FARKLE_B_CARD_PAID_BY", Name(v.arbiter)) or L.FARKLE_B_CARD_GRACE }
			end
		end
	end
	if v.role == "arbiter" then
		for _, l in ipairs(type(v.lines) == "table" and v.lines or {}) do
			local act = ({ payout = "farkle.payout", refund = "farkle.refund", change = "farkle.change" })[l.kind]
			if act then spec.buttons[#spec.buttons + 1] = { L["FARKLE_B_ARB_" .. l.kind:upper()] or l.kind, function() A().Do(act, id) end } end
		end
	end
	spec.buttons[#spec.buttons + 1] = { L.FARKLE_B_OK, nil }
	if mine then
		spec.buttons[#spec.buttons + 1] = { v.practice and L.FARKLE_B_PLAY_AGAIN or L.FARKLE_B_REMATCH, function()
			if v.practice then
				S.mode, S.id, S.target = "setup", nil, v.target or S.target
				S.hint, S.lesson = nil, nil
				S.gen = S.gen + 1
				Board.Open(false)
			else Board.Rematch(v) end
		end }
	end
	return spec
end

local VERDICT = { won = { "FARKLE_B_CARD_WON_TITLE", GREEN }, lost = { "FARKLE_B_CARD_LOST_TITLE", RED }, back = { "FARKLE_B_CARD_BACK_TITLE", { 0.35, 0.33, 0.3 } },
	done = { "FARKLE_B_CARD_DONE_TITLE", INK } }

ShowCard = function(id)
	if not id then return nil end
	local spec = Board.CardSpec(id)
	if not spec then return nil end
	S.cardFor = id
	if type(ArenaUI.ResultCard) == "function" then
		local ok = pcall(ArenaUI.ResultCard, spec)
		if ok then return true end
	end
	if not card then Card() end
	local vd = VERDICT[spec.verdict]
	card.verdict:SetText(L[vd[1]]); card.verdict:SetTextColor(vd[2][1], vd[2][2], vd[2][3])
	card.line:SetText(spec.line or "")
	card.tagline:SetText(spec.tagline or "")
	for i, r in ipairs(card.rows) do
		local row = spec.rows[i]
		r.l:SetText(row and row[1] or ""); r.r:SetText(row and row[2] or "")
	end
	card.note:SetText(spec.note or "")
	-- OK closes; the rest does what it says (the card sends nothing by itself)
	local list = {}
	for _, b in ipairs(spec.buttons) do list[#list + 1] = b end
	while #list > 3 do table.remove(list, #list - 1) end
	for i, b in ipairs(card.buttons) do
		local e = list[i]
		b:SetShown(e ~= nil)
		if e then
			b:SetText(e[1])
			b.fn = function() card:Hide(); if e[2] then e[2]() end end
		end
	end
	card.spec = spec
	local kit = ArenaUI.Kit
	if kit and kit.FitWindow then kit.FitWindow(card, 500, 310, 1) end
	card:Show()
	card:Raise()
	return card
end
Board.ShowCard = function(id) return ShowCard(id) end
end

---------------------------------------------------------------------------
-- Escape closes what is on top: a pop-up (the guide, the card, the invitation), then the table.
-- One stand-in frame is on the game's Escape list (ns.EscapeCloses); when Escape hides it, it hides
-- the top one and shows itself again while something else of ours is still open.
---------------------------------------------------------------------------

EscSync = function()
	if not esc then return end
	-- (the table itself not while a part of the window holding it is over it: that closes first)
	local any = (win and win:IsShown() and not under) or (help and help:IsShown()) or (ask and ask:IsShown()) or (card and card:IsShown())
	if any then
		ns.EscapeCloses("OlympusArenaBoneThrowEscape")
		if not esc:IsShown() then esc.quiet = true; esc:Show(); esc.quiet = nil end
	elseif esc:IsShown() then
		esc.quiet = true; esc:Hide(); esc.quiet = nil
	end
end
local function Escape()
	esc = CreateFrame("Frame", "OlympusArenaBoneThrowEscape", UIParent)
	esc:SetSize(1, 1); esc:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	esc:SetScript("OnHide", function(self)
		if self.quiet then return end
		-- (the pop-ups first, then the table; some may not exist yet)
		local order = { card or false, help or false, ask or false, win or false }
		for i = 1, #order do
			local f = order[i]
			if f and f:IsShown() then f:Hide() break end
		end
		EscSync()
	end)
	esc.quiet = true
	esc:Hide()
	esc.quiet = nil
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Build()
	-- Keep the table's animation coordinates; the standard metal window gives them a larger,
	-- screen-fitted canvas. The old hosted lab may still borrow the same content at its own scale.
	shell = CreateFrame("Frame", "OlympusArenaBoneThrowWindow", UIParent)
	shell:SetSize(W * 1.1 + 24, (H + ACTION_H) * 1.1 + 24); shell:SetPoint("CENTER", 0, 30); shell:SetFrameStrata("DIALOG")
	local framed, border = pcall(CreateFrame, "Frame", nil, shell, "DialogBorderTemplate")
	if framed and border then
		border:SetAllPoints(shell)
		if rawget(border, "Bg") then border.Bg:Hide() end
		shell.border = border
	end
	Movable(shell)
	win = CreateFrame("Frame", "OlympusArenaBoneThrow", shell)
	win:SetSize(W, H + ACTION_H); win:SetScale(1.1); win:SetPoint("TOPLEFT", shell, "TOPLEFT", 10, -10); win:SetFrameStrata("DIALOG")
	Movable(win)
	-- (held by another window, a drag moves that window, the table with it)
	win:SetScript("OnDragStart", function() local h = held or shell if h.StartMoving then h:StartMoving() end end)
	win:SetScript("OnDragStop", function() local h = held or shell if h.StopMovingOrSizing then h:StopMovingOrSizing() end end)
	-- The original table in two halves, omitting texture rows 251-259 so the seam is not drawn.
	local top = win:CreateTexture(nil, "BACKGROUND"); top:SetTexture(MEDIA .. "table")
	top:SetTexCoord(0, 1, 0, 250 / 512)
	top:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0); top:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -SPLIT)
	local bottom = win:CreateTexture(nil, "BACKGROUND"); bottom:SetTexture(MEDIA .. "table")
	bottom:SetTexCoord(0, 1, 260 / 512, 1)
	bottom:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -SPLIT); bottom:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -H)
	win.table = { top, bottom }
	win.frame = {}
	-- the column, the line between the halves
	local wash = win:CreateTexture(nil, "BORDER"); wash:SetColorTexture(0.3, 0.16, 0.04, 0.1)
	wash:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 1, -8); wash:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -8, -(H - 8))
	Groove(COLX, 10, 1, H - 20)
	win.midline = Groove(16, SPLIT - 1, COLX - 32, 1)   -- hidden under the setup, which sits across it

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -2, -2); close:SetFrameLevel((win:GetFrameLevel() or 0) + 50)
	close:SetScript("OnClick", function() Board.Close() end)
	win.close = close

	-- the column: the game's name, target and round; How to play and Sit down; what to do; the
	-- buttons; the log
	win.sub = Text(win, 13, SOFT, nil, "LEFT"); Place(win.sub, COLX + 17, 68); win.sub:SetWidth(W - COLX - 26); win.sub:SetWordWrap(false)
	win.stage = Text(win, 13, SOFT, nil, "LEFT"); Place(win.stage, COLX + 17, 88); win.stage:SetWidth(W - COLX - 26); win.stage:SetWordWrap(false)
	local sit = Button(win, L.FARKLE_B_SIT, 68, 32, function() A().Do("farkle.sit") end)
	sit:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 114, -12)
	win.sit = sit
	info = Text(win, 13, INK, nil, "LEFT"); Place(info, COLX + 17, 116); info:SetSize(W - COLX - 30, 80)
	info:SetJustifyV("TOP"); info:SetMaxLines(5)
	extraBtn = Button(win, "", 168, 32, OnExtra); extraBtn:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 14, -206); extraBtn:Hide()
	primary = Button(win, L.FARKLE_B_ROLL_N:format(6), 168, 32, OnPrimary); primary:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 14, -250)
	bankBtn = Button(win, L.FARKLE_B_BANK, 168, 32, OnBank); bankBtn:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 14, -290)
	-- Help/sit stay in the upper band. Playing actions share the bottom band, leaving the
	-- darkened side column for the lesson/status text instead of stacking buttons over it.
	local function GuideClick() if help and help:IsShown() then help:Hide() else Board.ShowGuide() end end
	local G = own.Games
	if G and G.Bar then
		win.bar = G.Bar(win, { y = H, inset = 0, helpText = L.FARKLE_B_HOW, help = GuideClick })
		win.helpButton = win.bar.help
		win.bar.Place({ primary, bankBtn, extraBtn })
	else
		-- Older companion without Games.Bar: keep actions reachable, never repeat the table art.
		local actionBar = CreateFrame("Frame", nil, win)
		actionBar:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -H); actionBar:SetSize(W, ACTION_H)
		win.actionBar = actionBar
		win.helpButton = Button(win, L.FARKLE_B_HOW, 96, 32, GuideClick)
		win.helpButton:SetPoint("LEFT", actionBar, "LEFT", 10, 0)
		primary:ClearAllPoints(); primary:SetPoint("RIGHT", actionBar, "RIGHT", -10, 0)
		bankBtn:ClearAllPoints(); bankBtn:SetPoint("RIGHT", primary, "LEFT", -8, 0)
		extraBtn:ClearAllPoints(); extraBtn:SetPoint("RIGHT", bankBtn, "LEFT", -8, 0)
	end
	win.logs = {}
	win.logs[1] = Text(win, 13, INK, nil, "LEFT"); Place(win.logs[1], COLX + 10, 284); win.logs[1]:SetSize(W - COLX - 20, 48)
	win.logs[2] = Text(win, 13, SOFT, nil, "LEFT"); Place(win.logs[2], COLX + 10, 344); win.logs[2]:SetSize(W - COLX - 20, 48)
	for _, l in ipairs(win.logs) do l:SetJustifyV("TOP"); l:SetWordWrap(true); l:SetMaxLines(3) end

	Row(2)
	Row(1)

	local overlay = CreateFrame("Frame", nil, win)
	overlay:SetAllPoints(); overlay:SetFrameLevel((win:GetFrameLevel() or 0) + 8)
	for k = 1, 3 do
		local fs = Text(overlay, 22, GREEN, MORPHEUS)
		fs:Hide()
		local t = { fs = fs, k = k }
		pcall(function()
			local g = fs:CreateAnimationGroup()
			local up = g:CreateAnimation("Translation"); up:SetOffset(0, 12); up:SetDuration(1.1)
			local fade = g:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetStartDelay(0.75); fade:SetDuration(0.35)
			t.anim = { g = g }
		end)
		tallies[k] = t
	end
	local hold = CreateFrame("Frame", nil, win)
	hold:SetSize(1, 1); hold:SetPoint("CENTER", win, "TOPLEFT", COLX / 2, -SPLIT); hold:SetFrameLevel((win:GetFrameLevel() or 0) + 12)
	banner = CreateFrame("Frame", nil, hold)
	banner:SetSize(420, 60); banner:SetPoint("CENTER")
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	SetFont(banner.text, MORPHEUS, 46, "OUTLINE"); banner.text:SetPoint("CENTER")
	banner.text:SetShadowColor(0, 0, 0, 0.6); banner.text:SetShadowOffset(2, -2)
	banner.subtitle = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	SetFont(banner.subtitle, FontFor(ns.me), 18, "OUTLINE")
	banner.subtitle:SetPoint("TOP", banner.text, "BOTTOM", 0, -3)
	banner.subtitle:SetWidth(420); banner.subtitle:SetText(""); banner.subtitle:Hide()
	-- it lands (from 1.6 times its size, fading in over 0.22 s) and, unless it stays, fades out
	pcall(function()
		local g = banner:CreateAnimationGroup()
		local grow = g:CreateAnimation("Scale")
		if grow.SetScaleFrom then grow:SetScaleFrom(1.6, 1.6); grow:SetScaleTo(1, 1) else grow:SetScale(1, 1) end
		grow:SetDuration(0.22)
		local show = g:CreateAnimation("Alpha"); show:SetFromAlpha(0); show:SetToAlpha(1); show:SetDuration(0.22)
		local f = banner:CreateAnimationGroup()
		local fade = f:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.4)
		f:SetToFinalAlpha(true)
		banner.anim = { show = g, fade = f }
	end)
	banner:Hide()
	Setup()
	Board.CreatePanel()

	for side = 1, 2 do
		sides[side] = { dice = {}, play = { 1, 2, 3, 4, 5, 6 }, kept = {} }
		for i = 1, 6 do sides[side].dice[i] = NewDie(side, i) end
	end
	Escape()

	win:SetScript("OnShow", function()
		if not held then
			ArenaUI.Kit.FitWindow(shell, W * 1.1 + 24, H * 1.1 + 44, 1)
			shell:Show()
			if ArenaUI.HideForGame then ArenaUI.HideForGame() end
		end
		EscSync()
		-- one game's window at a time (the design): the others close when this one opens
		ns.Fire("ARENA_GAME_SHOWN", "farkle")
		Board.Told(held, true)
		Sync()
	end)
	win:SetScript("OnHide", function()
		if not held then shell:Hide() end
		if help then help:Hide() end
		EscSync()
		Board.Told(held, false)
		S.gen = S.gen + 1
		S.queue, S.animating, S.rolling = {}, nil, nil
		StopShake(1); StopShake(2)
		if S.clockTicker then S.clockTicker:Cancel(); S.clockTicker = nil end
		for _, c in pairs(counters) do if c.ticker then c.ticker:Cancel(); c.ticker = nil end end
		counters = {}
	end)
	shell:SetScript("OnHide", function() if not held then win:Hide() end end)
	win:Hide()
end

---------------------------------------------------------------------------
-- Opening, closing, the events
---------------------------------------------------------------------------

-- Held by another window (in a test build the Bones window, Games/Farkle.lua; the owner on test 32:
-- the table shows in the same window as the search and the match, never in another one):
-- Board.SetHost(fn), fn() -> that window and the level above it, or nil. Held, the table is one of
-- that window's components: parented to it, at its top left over its table, its own dark frame off,
-- a drag moving that window; its X and Escape give that window back. Not held (that window closed),
-- it is its own window again. The table, its state and its actions are the same either way.
do
local hostFn, hostOpen
-- The window holding it hears when it shows or hides there (its Escape and its other parts).
function Board.Told(h, shown)
	local fn = type(h) == "table" and rawget(h, "hostChanged")
	if type(fn) == "function" then ns.SafeCall("bones board host", fn, win, shown) end
end
-- open (optional): opens that window again, for a table combat closed while it held it (it comes
-- back after combat where it was, Board.WatchCombat).
function Board.SetHost(fn, open)
	hostFn = type(fn) == "function" and fn or nil
	hostOpen = hostFn and type(open) == "function" and open or nil
	return Board.Rehost()
end
function Board.OpenHost()
	if hostOpen then ns.SafeCall("bones board host open", hostOpen) end
end
-- The window holding it shows a part of its own over the table (the match's card the room asked
-- for): Escape closes that part and leaves the table, which the next Escape closes. The table
-- leaves the game's Escape list at once, and comes back on it a frame after that part went, never
-- while the client walks the list (the walk that hid that part would hide the table too).
local underGen = 0
function Board.EscapeUnder(on)
	underGen = underGen + 1
	if on then
		under = true
		return EscSync()
	end
	if not under then return end
	local gen = underGen
	C_Timer.After(0, function()
		if gen ~= underGen then return end
		under = nil
		EscSync()
	end)
end
function Board.Rehost()
	if not win then return nil end
	local h, level
	if hostFn then
		local ok, f, l = pcall(hostFn)
		if ok and type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() then h, level = f, tonumber(l) or 70 end
	end
	if h == held then return h end
	local old = held
	held = h
	if h then
		win:SetParent(h)
		win:SetScale(1)
		shell:Hide()
		local strata = h.GetFrameStrata and h:GetFrameStrata()
		if strata then win:SetFrameStrata(strata) end
		win:SetFrameLevel((tonumber(h:GetFrameLevel()) or 0) + level)
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
	else
		win:SetParent(shell)
		win:SetScale(1.1)
		win:SetFrameStrata("DIALOG")
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", shell, "TOPLEFT", 10, -10)
		if win:IsShown() then shell:Show() end
	end
	for _, t in ipairs(win.frame or {}) do t:SetShown(h == nil) end
	-- (its X exactly over the holding window's own, Games/Farkle.lua's: one X in the corner)
	if win.close then
		win.close:ClearAllPoints()
		win.close:SetPoint("TOPRIGHT", h and win or shell, "TOPRIGHT", h and 6 or -2, h and 6 or -2)
	end
	if win:IsShown() then
		if old then Board.Told(old, false) end
		if h then Board.Told(h, true) end
	end
	return h
end
function Board.Window() return win end
function Board.Host() return held end
end

local function Ensure()
	if not win then Build(); Board.WatchCombat() end
	Board.Rehost()
	if not held then
		shell:Show()
		if ArenaUI.HideForGame then ArenaUI.HideForGame() end
	end
	return win
end

-- The table this player sits at, or plays against the House, or watches: the one to show.
local function Current()
	local F = FT()
	local t = F.Live()
	if t then return t.id end
	for _, x in ipairs(F.Tables()) do
		if (x.role == "practice" and not x.closed) or (x.role == "arbiter" and x.state ~= "closed") or x.role == "watch" then return x.id end
	end
	return nil
end

-- Shows a table (id), or this player's current one; the setup when there is none (or when id is
-- false: the practice setup whatever else is live).
function Board.Show(id)
	if FT() and not FT().CanOpen() then Say(L.FARKLE_LOG_TAVERN_REST); return nil end
	if InCombatLockdown and InCombatLockdown() then Say(L.FARKLE_B_NOT_IN_COMBAT) return nil end
	Ensure()
	if id == nil then id = Current() end
	local v = id and FT().View(id) or nil
	if v then
		S.id = id
		S.mode = "table"
		S.near = (v.seat and not v.watching) and v.seat or 1
		S.last, S.note, S.hint, S.sel = {}, nil, nil, {}
	elseif S.mode ~= "create" then
		S.id = nil
		S.mode = "setup"
	end
	if win:IsShown() then Sync() else win:Show() end
	FirstUse()
	return win
end
Board.Open = function(id) return Board.Show(id) end

function Board.Close()
	if win and win:IsShown() then win:Hide() end
	if card and card:IsShown() then card:Hide() end
end
function Board.IsOpen() return win ~= nil and win:IsShown() end

-- A departure warning is independent of the board and its dice animations. Acknowledging
-- it only hides the warning: it never moves the player, resumes play or resets the grace.
function Board.RefreshDeparture()
	local f = Board.departure
	if not f or not f.id then return false end
	local v = FT().View(f.id)
	if not v or v.state ~= "play" or v.over or v.practice or v.rehearsal or v.watching
		or not v.seat or v.awayLeft == nil then
		f:Hide()
		return false
	end
	f.clock:SetText(T("FARKLE_B_AWAY_CLOCK", v.awayLeft))
	f.clock:SetTextColor(1, v.awayLeft <= 10 and 0.25 or 0.85, v.awayLeft <= 10 and 0.2 or 0.25)
	return true
end

function Board.ShowDeparture(id)
	local v = FT().View(id)
	if not v or v.state ~= "play" or v.over or v.practice or v.rehearsal or v.watching
		or not v.seat or v.awayLeft == nil then return nil end
	local f = Board.departure
	if not f then
		f = ns.Window("OlympusArenaBonesDeparture", UIParent, { title = L.FARKLE_B_AWAY_TITLE, close = false, escape = false })
		Board.departure = f
		f:SetSize(440, 210)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
		f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true)
		-- The inset is a child frame: its opaque background must not cover the text.
		local content = f.Inset or f
		f.body = Text(content, 16, { 1, 1, 1 }, nil, "CENTER")
		f.body:SetShadowColor(0, 0, 0, 0.8)
		f.body:SetPoint("TOP", f, "TOP", 0, -42); f.body:SetWidth(396)
		f.body:SetText(L.FARKLE_B_AWAY_BODY)
		f.clock = Text(content, 22, { 1, 0.85, 0.25 }, nil, "CENTER")
		f.clock:SetShadowColor(0, 0, 0, 0.8)
		f.clock:SetPoint("TOP", f, "TOP", 0, -122); f.clock:SetWidth(396)
		f.ok = Button(f, L.FARKLE_B_AWAY_OK, 210, 30, function() f:Hide() end)
		f.ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
		f:SetScript("OnHide", function()
			if f.ticker then f.ticker:Cancel(); f.ticker = nil end
			f.id = nil
		end)
		f:Hide()
	end
	if f.ticker then f.ticker:Cancel() end
	f.id = id
	if not Board.RefreshDeparture() then return nil end
	f.ticker = C_Timer.NewTicker(0.25, function() Board.RefreshDeparture() end)
	f:Show(); f:Raise()
	return f
end

-- A practice game against the House, to `target` (the setup's Start, /oly farkle practice N);
-- learn: the lesson's hints on (the training setup's Show tips checkbox).
function Board.StartPractice(target, learn)
	local id, why = A().Do("farkle.practice", { target = target or S.target, learn = learn == true or nil })
	if type(id) ~= "string" then S.hint = WhyText(why or "error"); return Refresh() end
	S.hint, S.lesson = nil, nil
	return Board.Show(id)
end

-- The create panel, with a prefill (the hub's New table, the right-click menu, a match's hand-off).
function Board.OpenCreate(prefill)
	prefill = type(prefill) == "table" and prefill or {}
	-- (practice with nobody named: the House; a match's "practice" is a game with no stake)
	if prefill.practice and not prefill.guest then
		S.mode, S.id = "setup", nil
		return Board.Show(false)
	end
	local C = Board.C
	C.guest = prefill.guest and (ns.FullName and ns.FullName(ns.Normal(prefill.guest)) or prefill.guest) or nil
	C.stake = prefill.practice and 0 or floor(tonumber(prefill.stake) or 0)
	C.target = tonumber(prefill.target) or C.target or 5000
	C.mode = prefill.mode == "a" and "a" or "d"
	C.arbiter, C.src = prefill.arbiter, prefill.src
	C.secs = tonumber(prefill.secs) or C.secs or 60
	C.from = prefill.from
	C.spectators, C.sober = prefill.spectators ~= false, prefill.hic == false
	C.crowd = prefill.crowd ~= false
	C.rehearsal = prefill.rehearsal == true
	S.mode = "create"
	S.id = nil
	S.hint = nil
	Ensure()
	if win:IsShown() then Refresh() else win:Show() end
	FirstUse()
	return win
end

-- Play again with the same opponent and terms (asked to him: a new invitation).
function Board.Rematch(v)
	if not v or not v.seat then return end
	local other = v.players[3 - v.seat]
	local prefill = { guest = other, stake = v.stake, target = v.target, mode = v.kind, arbiter = v.arbiter,
		src = v.src and v.src[v.seat] ~= "-" and v.src[v.seat] or nil, secs = v.secs, rehearsal = v.rehearsal or nil,
		spectators = not (v.spec and v.spec[v.seat] == false) and not v.noWatch, hic = v.hic, crowd = v.crowd or nil }
	-- asked to him at once when nothing stands in the way; else the create panel says why
	if A().Can("farkle.create", prefill) then
		local id = A().Do("farkle.create", prefill)
		if type(id) == "string" then return Board.Show(id) end
	end
	return Board.OpenCreate(prefill)
end

ns.On("FARKLE_EVENT", function(id, info)
	if not win or not win:IsShown() or S.id ~= id or type(info) ~= "table" then return end
	Board.Enqueue(info)
end)
ns.On("FARKLE_TABLE", function(id, state)
	if not win then return end
	-- a table this player hosts or joins becomes the one shown
	if win:IsShown() and S.mode ~= "table" and id and FT().View(id) then
		local v = FT().View(id)
		local settled = v.state ~= "invite" and v.state ~= "declined" and v.state ~= "expired" and v.state ~= "aborted"
		if (v.role == "host" or v.role == "guest") and settled then return Board.Show(id) end
	end
	if S.id == id and win:IsShown() and not S.animating and #S.queue == 0 then Refresh() end
	if ask and ask:IsShown() and ask.id == id then Board.AskRefresh() end
	if card and card:IsShown() and S.cardFor == id and (state == "closed") then ShowCard(id) end
end)
ns.On("ARENA_CHANGED", function() if win and win:IsShown() and not S.animating then Refresh() end end)
-- Another game's window opened (ARENA_GAME_SHOWN with its key: "lottery"...): this one closes.
ns.On("ARENA_GAME_SHOWN", function(key) if key ~= "farkle" and win and win:IsShown() then win:Hide() end end)

-- Combat (the design): the table closes in combat and comes back after it while a table is live.
-- Held by another window (the Bones window), it comes back in that window, which opens again.
-- The window holding it closes in combat too, and calls this first (Games/Farkle.lua's
-- Here.Combat): whichever hears PLAYER_REGEN_DISABLED first, the table is remembered the same.
function Board.CombatClose()
	if not (win and win:IsShown()) then return false end
	S.reopen = S.id or true
	S.reopenHeld = held ~= nil
	win:Hide()
	if ask and ask:IsShown() then ask:Hide() end
	if card and card:IsShown() then card:Hide() end
	Say(L.FARKLE_B_CLOSED_COMBAT)
	return true
end
-- (Registered when the table is first built: loading the companion alone registers nothing.)
function Board.WatchCombat()
	if Board.watching then return end
	Board.watching = true
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() Board.CombatClose() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local again, wasHeld = S.reopen, S.reopenHeld
	S.reopen, S.reopenHeld = nil, nil
	if not again then return end
	local id = type(again) == "string" and again or nil
	local v = id and FT().View(id)
	if v and not (v.over and (v.practice or v.state == "closed")) then
		if wasHeld then Board.OpenHost() end
		Board.Show(id)
	end
end)
end

-- The House waits while the dice move (the core asks before each of its moves).
if FT() then FT().busy = function(id) return Board.Busy(id) end end

---------------------------------------------------------------------------
-- The way in (the core's FarkleTable.ShowUI, the hub's panes, the sim)
---------------------------------------------------------------------------

function ArenaUI.Farkle(what, id, extra)
	what = what or "board"
	if what == "away" then return Board.ShowDeparture(id) end
	if what == "guide" or what == "rules" then return Board.ShowGuide() end
	if what == "invite" or what == "arbiter" then return Board.ShowAsk(what, id) end
	if what == "create" then return Board.OpenCreate(extra) end
	if what == "result" then return ShowCard(id) end
	if what == "watch" and id then
		-- (the hub's Watch, the right-click's: watching starts here when it hasn't yet)
		local t = FT().Get(id)
		if not t or t.role ~= "watch" then
			local ok, why = A().Do("farkle.watch", id)
			if not ok then Say(WhyText(why)) return nil end
		end
		return Board.Show(id)
	end
	if what == "practice" or what == "sim" then
		local target = type(extra) == "table" and tonumber(extra.target) or nil
		if target and FR().TARGET_CODE[target] then
			S.target = target
			Ensure()
			return Board.StartPractice(target, type(extra) == "table" and extra.learn == true)
		end
		S.mode = "setup"
		S.id = nil
		S.hint = nil
		return Board.Show(false)
	end
	return Board.Show(id)
end
function ArenaUI.FarkleCreate(prefill) return Board.OpenCreate(prefill) end

-- For the offline tests: the table's parts, state and geometry (read only).
Board._ = { S = S, C = Board.C, sides = sides, SND = SND, AREAS = AREAS, Handlers = Board.Handlers, TurnSoFar = Board.TurnSoFar,
	geo = { W = W, H = H, D = D, K = K, SW = SW, EDGE = EDGE, REST = REST, BAND = BAND, TRAY = TRAY, TRAYX = TRAYX, TRAYSTEP = TRAYSTEP,
		LANE = LANE, LaneX = LaneX, SPLIT = SPLIT, COLX = COLX, HAND = HAND, FLIGHT = FLIGHT },
	guide = Board.guide,
	parts = function() return { win = win, shell = shell, primary = primary, bank = bankBtn, extra = extraBtn, info = info, logs = win and win.logs,
		banner = banner, rows = rows, targets = targets, help = help, setup = setup, create = create, tallies = tallies, ask = ask, card = card, esc = esc, departure = Board.departure } end,
	flipBook = function() return flipBook end }
