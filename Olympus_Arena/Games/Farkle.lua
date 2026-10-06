local _, own = ...; local ns = own.host; if not ns then return end
local host = ns; ns = own -- (the lab's tables stay the companion's own: Olympus has its own ns.Wallet and ns.FarkleRules)
local L = host.L
-- (Ported from the Olympus Frame Lab, 2026-09-30: the practice preview, inside the arena.)
-- Bones (Farkle) for the Olympus Frame Lab: a playable preview on the tavern table, you
-- against a practice opponent. Nothing is sent and nothing is saved.
--   /lab farkle          open or close the introduction; Start Playing opens the real Bones
--                        opponent finder inside this window, and the match's card and the real
--                        table show here too (below: the window's components). /oly bones and
--                        the lab's games window are the same. Opening it closes the Lottery's
--                        window: each game has its own window, no tabs.
--   /lab farkle sound    the sound effects on or off
-- Your dice come from your own /roll: Roll calls RandomRoll(1, 6^n), and the dice are read from
-- the server's line (ArenaParse.Roll, then FarkleRules), so a typed /roll counts the same. The
-- House, the practice opponent, throws math.random numbers, marked as simulated. Every move goes
-- through FarkleRules (the 1.2 rules module); this file only draws, animates, sounds and asks.
--
-- The table, each thing in its own area: the innkeeper's row on the top plank (its name, a line under
-- it, its tray of dice set aside, its points on the right), yours on the bottom plank, the game's
-- column on the right (name, target and round, help, what to do, the buttons, the log). Between
-- the rows each side has its half: its dice are thrown from its edge, each along its own lane,
-- into a slot in the half; the dice set aside move to its tray and shrink there. Under the table,
-- the footer compartment (the Lottery's too): How to play and the wallet on the left, Roll and
-- Bank on the right.
-- A practice stake (none, 10g, 50g or 100g, from the wallet the games share, ns.Wallet):
-- the innkeeper matches it; the winner takes both less the guild's 6% of the one won (FEE_BP). The
-- stake and the result are lines in the wallet's history.
local FR, AP = ns.GamesRules, host.ArenaParse
local pi, sin, abs, floor, min, max, random = math.pi, math.sin, math.abs, math.floor, math.min, math.max, math.random

local Farkle = {}
ns.Farkle = Farkle

local MEDIA = "Interface\\AddOns\\Olympus_Arena\\media\\games\\"
local DICE = MEDIA .. "dice\\"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"
local W, H = 800, 400             -- the table: 1024 x 512 shown at 800 x 400
local FOOT_H = 56                 -- the footer compartment, under the table
local WIN_H = H + FOOT_H          -- the window
local GOLD, FEE_BP = 10000, 600   -- copper; the guild's 6% of the stake won
local STAKES = { 0, 10 * GOLD, 50 * GOLD, 100 * GOLD }
local SPLIT = 197                 -- the line between the innkeeper's half (above) and yours
local COLX = 606                  -- the column's left edge
local CX, LANE = 300, 84          -- the lanes' centre and spacing: a die never leaves its lane
local D, K, SW = 44, 22, 24       -- a die's edge in play, in the tray, and on its way there
local EDGE = { 292, 102 }         -- a seat's hand, where its throws start (1 = you, 2 = the innkeeper)
local REST = { 240, 156 }         -- where its dice come to rest
local BAND = { 306, 88 }          -- the band its dice set aside cross on their way to the tray
local TRAY = { 366, 31 }          -- its tray and its points, in its row
local TRAYX, TRAYSTEP = 318, 30   -- the tray's first slot and the step between slots
local ROW = { 332, 0 }            -- the top of its row
local HAND_H = 0.55               -- a die's height in the hand (0 on the table)
local GATHER = { slide = 0.16, appear = 0.12, fade = 0.24 }
-- Where each thing may be (x, y, right, bottom), for the layout and for the offline tests.
local AREAS = {
	houseRow = { 0, 0, COLX, 62 }, yourRow = { 0, 332, COLX, H },
	houseHalf = { 0, 62, COLX, SPLIT }, yourHalf = { 0, SPLIT, COLX, 332 }, column = { COLX, 0, W, H },
	foot = { 0, H, W, WIN_H },
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
	lose = 846,      -- interface/igquestfailed, the quieter kit: the innkeeper wins
}

local S = { target = 5000, stake = 10 * GOLD, first = 1, gen = 0, flying = { 0, 0 }, ready = { 0, 0 }, hand = { 0, 0 },
	sel = {}, last = {}, sound = true, setup = true, hits = { 0, 0 }, shake = {} }
local win, driver, events, banner, help, setup, intro, info, primary, bankBtn, overlay, stakeInfo
local rows, logs, targets, stakes, tallies = {}, {}, {}, {}, {}
local Wallet, Money, Coins = ns.Wallet, ns.Games.Money, ns.Games.Coins
local sides = {}      -- [seat] = { dice = { six dice }, play = { die index by roll position }, kept = { die index } }
local active = {}     -- dice with a plan: the OnUpdate runs while this, a counter, a tally or the banner has something
local counters = {}
local Refresh, NextTurn, HouseStep

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe6c35cBones:|r " .. msg) end

local function Num(n)
	local s, k = tostring(floor(n or 0)), 0
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

local function LaneX(i) return CX + (i - 3.5) * LANE end

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

local function Place(region, x, y, point) region:ClearAllPoints(); region:SetPoint(point or "TOPLEFT", win, "TOPLEFT", x, -y) end

---------------------------------------------------------------------------
-- Sound: the SFX channel, one of a kind at a time, never more than three at once
---------------------------------------------------------------------------

local played = {}
local function Sound(key)
	if not S.sound or type(PlaySound) ~= "function" or not SND[key] then return nil end
	local now, busy = GetTime(), 0
	if played[key] and now - played[key] < 0.07 then return nil end
	for _, t in pairs(played) do if now - t < 0.12 then busy = busy + 1 end end
	if busy >= 3 then return nil end
	played[key] = now
	local ok, willPlay, handle = pcall(PlaySound, SND[key], "SFX")
	if ok and willPlay then return handle end
	return nil
end

local function StopShake(seat)
	local h = S.shake[seat]
	S.shake[seat] = nil
	if h and type(StopSound) == "function" then pcall(StopSound, h, 150) end
end

-- The dice rattle in the hand until the throw (at most a few seconds: the loop never outlives it).
local function StartShake(seat)
	if S.shake[seat] or type(StopSound) ~= "function" then return end
	local h = Sound("shake")
	if not h then return end
	S.shake[seat] = h
	C_Timer.After(4, function() if S.shake[seat] == h then StopShake(seat) end end)
end

-- fn at time t (now, or later in this game: a new game or a closed table drops it)
local function At(t, fn)
	local wait, gen = t - GetTime(), S.gen
	if wait <= 0.001 then return fn() end
	C_Timer.After(wait, function() if gen == S.gen and win and win:IsShown() then fn() end end)
end

---------------------------------------------------------------------------
-- The bone sprite dice (dice/final): faces.tga (6 faces x 4 turns), tumble.tga (16 frames),
-- drawn at twice the die's edge. The tumble plays with FlipBook where the client has it, else
-- by SetTexCoord from the dice's own OnUpdate. A die picked lights up on itself: the same face
-- cell again, added in a warm colour, and it lifts a little. No ring.
---------------------------------------------------------------------------

local flipBook   -- true, false: whether the client made a FlipBook
local function NewSprite(parent)
	local f = CreateFrame("Button", nil, parent)
	f.face = f:CreateTexture(nil, "ARTWORK"); f.face:SetAllPoints(); f.face:SetTexture(DICE .. "faces")
	f.lit = f:CreateTexture(nil, "ARTWORK", nil, 1); f.lit:SetAllPoints(); f.lit:SetTexture(DICE .. "faces")
	f.lit:SetBlendMode("ADD"); f.lit:SetVertexColor(1, 0.74, 0.4); f.lit:Hide()
	f.tumble = f:CreateTexture(nil, "ARTWORK"); f.tumble:SetAllPoints(); f.tumble:SetTexture(DICE .. "tumble"); f.tumble:Hide()
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
	f:EnableMouse(false)
	f:Hide()
	return f
end

-- A die: where it is (x, y from the table's top left, y down), its edge (size), height (h: 0 on
-- the table; the table is seen from above, so a die in the air only looks bigger), alpha, the
-- value it shows, where it lies ("lane", "tray", "hidden") and a plan the OnUpdate carries out.
-- (A die not on the table or in a tray is hidden whole, its frame and every texture of it, and
-- never drawn under 2 px: the owner saw slivers of dice waiting in the hands, 2026-09-30.)
local function HideDie(f)
	f:Hide(); f.face:Hide(); f.lit:Hide(); f.tumble:Hide()
	if f.flip and f.flip.Stop then f.flip:Stop() end
	f.air = nil
end
local function Draw(d)
	local f = d.f
	if d.alpha <= 0.01 or d.where == "hidden" and not d.plan then HideDie(f); return end
	local still = not d.plan
	local up = still and (d.lit and 4 or d.hover and 2) or 0
	local grow = still and (d.lit and 1.06 or d.hover and 1.03) or 1
	local s = d.size * (1 + 0.18 * (d.h or 0)) * (d.pop or 1) * grow
	if s < 1 then HideDie(f); return end
	f:ClearAllPoints()
	f:SetPoint("CENTER", win, "TOPLEFT", d.x, -(d.y - up))
	f:SetSize(2 * s, 2 * s)
	f:SetHitRectInsets(s / 2, s / 2, s / 2, s / 2)   -- the die itself, not its shadow
	f:SetAlpha(d.alpha)
	f:Show()
	if d.air then
		if not f.air then f.air = true; f.face:Hide(); f.lit:Hide(); f.tumble:Show(); if f.flip then f.flip:Play() end end
		if not f.flip then
			local i = (d.i * 5 + d.seat * 3 + floor(GetTime() * 25)) % 16
			local c, r = i % 4, floor(i / 4)
			f.tumble:SetTexCoord(c / 4, (c + 1) / 4, r / 4, (r + 1) / 4)
		end
		return
	end
	if f.air ~= false or not f.face:IsShown() then f.air = false; if f.flip then f.flip:Stop() end; f.tumble:Hide(); f.face:Show() end
	local l, r, t, b = (d.value - 1) / 8, d.value / 8, (d.variant - 1) / 4, d.variant / 4
	f.face:SetTexCoord(l, r, t, b)
	local glow = (not d.farkle) and (d.lit and 0.42 or d.hover and 0.2) or 0
	if glow > 0 then f.lit:SetTexCoord(l, r, t, b); f.lit:SetAlpha(glow); f.lit:Show() else f.lit:Hide() end
	-- a Farkle's dice go dull (grey bone), the red is for the banner
	local dull = d.farkle and true or false
	if f.dull ~= dull then
		f.dull = dull
		f.face:SetDesaturated(dull)
		if dull then f.face:SetVertexColor(0.74, 0.69, 0.63) else f.face:SetVertexColor(1, 1, 1) end
	end
end

local function Ease(u) return 1 - (1 - u) ^ 3 end
local function Smooth(u) u = max(0, min(1, u)); return u * u * (3 - 2 * u) end

-- A throw's height: off the hand, down on the table at 0.34, two smaller bounces, then it rolls
-- to a stop (from 0.78 it shows its face).
local function Height(u)
	if u < 0.34 then local v = u / 0.34; return HAND_H * (1 - v) + 0.3 * sin(pi * v) end
	if u < 0.6 then return 0.2 * sin(pi * (u - 0.34) / 0.26) end
	if u < 0.78 then return 0.06 * sin(pi * (u - 0.6) / 0.18) end
	return 0
end

-- The first dice to strike the table click on it (three at most a throw).
local function Hit(seat)
	if S.hits[seat] >= 3 then return end
	if Sound("hit") then S.hits[seat] = S.hits[seat] + 1 end
end

-- A die set aside on its way: out of its lane toward its edge, across the band, down into its
-- tray slot, shrinking. Returns how far it has come (1: in the slot).
local function Sweep(d, p, now)
	local u = min(1, (now - p.t0) / p.dur)
	if u < 0.3 then
		local v = Smooth(u / 0.3)
		d.x, d.y, d.size = p.fx, p.fy + (p.by - p.fy) * v, p.fs + (SW - p.fs) * v
	elseif u < 0.75 then
		d.x, d.y, d.size = p.fx + (p.tx - p.fx) * Smooth((u - 0.3) / 0.45), p.by, SW
	else
		local v = Smooth((u - 0.75) / 0.25)
		d.x, d.y, d.size = p.tx, p.by + (p.ty - p.by) * v, SW + (K - SW) * v
	end
	d.h, d.air, d.alpha, d.pop = 0, false, 1, nil
	return u
end

-- One frame of a die's plan; true when it has nothing left to do. A plan's onEnd is handed back
-- in `fired` so it runs after every die has moved.
local function Tick(d, now, fired)
	local p = d.plan
	if not p then return true end
	if p.kind == "roll" then
		local lx, ly = LaneX(d.i), EDGE[d.seat]
		if p.pre and now >= p.g0 then p.pre, d.lit, d.where = nil, nil, "tray" end
		if now < p.g0 then
			-- (waits where it is while the dice set aside reach the tray; a hot die set aside a
			-- moment ago goes on to its own tray slot first)
			if p.pre then Sweep(d, p.pre, now) end
		elseif now < p.t0 then
			-- into the hand at the start of its lane, then shaken there until the throw
			local u = min(1, (now - p.g0) / p.gd)
			if p.via == "fade" and u < 0.5 then
				d.x, d.y, d.size, d.h, d.air = p.gx, p.gy, p.gs, 0, false
				d.alpha = p.ga * (1 - 2 * u)
			else
				local v = p.via == "fade" and (u - 0.5) * 2 or u
				if p.via == "slide" then
					d.x, d.y = p.gx + (lx - p.gx) * Smooth(v), p.gy + (ly - p.gy) * Smooth(v)
					d.size, d.alpha, d.air = p.gs + (D - p.gs) * v, 1, v > 0.5
				else
					d.x, d.y, d.size, d.alpha, d.air = lx, ly, D, v, true
				end
				d.h = HAND_H * v
				if u >= 1 then
					d.x = lx + 1.5 * sin(now * 23 + d.i * 1.7)
					d.y = ly + 1.5 * sin(now * 19 + d.i * 2.9)
				end
			end
		else
			local u = (now - p.t0) / p.dur
			if u >= 1 then
				d.x, d.y, d.h, d.size, d.alpha, d.pop, d.air = p.tx, p.ty, 0, D, 1, nil, false
				d.where, d.plan = "lane", nil
			else
				-- forward along its lane, slowing, with a little sideways wobble that dies out
				local e = 1 - (1 - u) ^ 2
				d.x = lx + (p.tx - lx) * e + 2 * sin(p.phase + u * 7) * (1 - u)
				d.y = ly + (p.ty - ly) * e
				d.h, d.size, d.alpha = Height(u), D, 1
				d.air = u < 0.78
				d.pop = (not d.air) and (1 + 0.05 * (1 - (u - 0.78) / 0.22)) or nil
				if not p.struck and u >= 0.34 then p.struck = true; Hit(d.seat) end
			end
		end
	elseif p.kind == "sweep" then
		if Sweep(d, p, now) >= 1 then d.plan, d.where, d.lit = nil, "tray", nil end
	elseif p.kind == "fade" then
		local u = min(1, (now - p.t0) / p.dur)
		d.alpha, d.air, d.h = p.a0 * (1 - u), false, 0
		if u >= 1 then d.plan, d.where, d.alpha = nil, "hidden", 0 end
	end
	if not d.plan and p.onEnd then fired[#fired + 1] = p.onEnd end
	Draw(d)
	return d.plan == nil
end

local function Busy() return S.setup or S.pending or S.flying[1] > 0 or S.flying[2] > 0 or S.timer end

local function Step()
	local now, fired = GetTime(), {}
	for d in pairs(active) do
		if Tick(d, now, fired) then active[d] = nil end
	end
	local moving = next(active) ~= nil
	for _, c in pairs(counters) do
		if c.run then
			local u = min(1, (now - c.t0) / c.dur)
			c.now = floor((c.from + (c.to - c.from) * Ease(u)) / 10 + 0.5) * 10
			if u >= 1 then c.now, c.run = c.to, nil else moving = true end
			c.fs:SetText(c.fmt(c.now))
		end
	end
	for _, t in ipairs(tallies) do
		if t.t0 then
			local u = now - t.t0
			if u >= 1.1 then t.t0 = nil; t.fs:Hide()
			else
				moving = true
				t.fs:SetText("+" .. Num(floor(t.to * min(1, u / 0.4) / 10 + 0.5) * 10))
				Place(t.fs, t.x, t.y - 12 * min(1, u / 1.1), "CENTER")
				t.fs:SetAlpha(u < 0.75 and 1 or max(0, 1 - (u - 0.75) / 0.35))
			end
		end
	end
	local bn = S.bn
	if bn then
		local u = now - bn.t0
		if u < 0.22 then banner:SetScale(1.6 - 0.6 * u / 0.22); banner:SetAlpha(u / 0.22)
		elseif bn.stay or u < 1.4 then banner:SetScale(1); banner:SetAlpha(1); if bn.stay then S.bn = nil end
		elseif u < 1.8 then banner:SetAlpha(1 - (u - 1.4) / 0.4)
		else banner:Hide(); S.bn = nil end
		if S.bn then moving = true end
	end
	for _, fn in ipairs(fired) do fn() end
	-- (a landing may have started a banner, a tally or a count just now)
	if moving or next(active) or S.bn then return end
	for _, c in pairs(counters) do if c.run then return end end
	for _, t in ipairs(tallies) do if t.t0 then return end end
	driver:SetScript("OnUpdate", nil)
end
local function Run() driver:SetScript("OnUpdate", Step) end

local function Fmt(n) return Num(n) end

-- Numbers on the table count up (or down) to their new value.
local function Count(key, fs, to, fmt, dur)
	local c = counters[key]
	if c and c.fs == fs and c.to == to then
		c.fmt = fmt
		if not c.run then fs:SetText(fmt(c.now)) end
		return
	end
	local from = c and c.fs == fs and c.now or to
	if from == to or not dur then
		counters[key] = { fs = fs, to = to, now = to, fmt = fmt }
		fs:SetText(fmt(to))
		return
	end
	counters[key] = { fs = fs, from = from, to = to, now = from, fmt = fmt, t0 = GetTime(), dur = dur, run = true }
	fs:SetText(fmt(from))
	Run()
end

local function Plan(d, p)
	d.plan = p
	active[d] = true
	Run()
end

local function Still(d)
	d.plan = nil
	active[d] = nil
end

local function Banner(text, color, stay)
	banner.text:SetText(text); banner.text:SetTextColor(color[1], color[2], color[3])
	banner:SetAlpha(0); banner:Show()
	S.bn = { t0 = GetTime(), stay = stay }
	Run()
end

local function Log(text)
	logs[2]:SetText(logs[1]:GetText() or "")
	logs[1]:SetText(text)
end

-- One timer for the innkeeper and the pauses between turns; a new game or a closed table drops it.
-- Your buttons wait while it runs, so the table is refreshed when it starts and when it ends.
local function Later(t, fn)
	local gen = S.gen
	S.wait = (S.wait or 0) + 1
	local id = S.wait
	S.timer = id
	C_Timer.After(t, function()
		if gen ~= S.gen or S.timer ~= id or not win:IsShown() then return end
		S.timer = nil
		fn()
		Refresh()
	end)
	Refresh()
end

---------------------------------------------------------------------------
-- Throws and dice set aside
---------------------------------------------------------------------------

-- A die goes into its seat's hand at the start of its lane: from its lane it slides there, from
-- the tray it fades out and appears there, a hidden one appears there. A die still on its way to
-- the tray (hot dice: all six set aside, then thrown again) reaches its slot first and leaves it
-- like one lying there.
local function Hand(d, g0)
	local sw = d.plan
	if sw and sw.kind == "sweep" then
		local g = max(g0, sw.t0 + sw.dur)
		d.hover, d.farkle = nil, nil
		Plan(d, { kind = "roll", pre = sw, g0 = g, gd = GATHER.fade, via = "fade", gx = sw.tx, gy = sw.ty, gs = K, ga = 1, t0 = math.huge })
		return g + GATHER.fade
	end
	local via = d.where == "tray" and "fade" or ((d.where == "lane" and d.alpha > 0.05) and "slide" or "appear")
	d.lit, d.hover, d.farkle = nil, nil, nil
	Plan(d, { kind = "roll", g0 = g0, gd = GATHER[via], via = via, gx = d.x, gy = d.y, gs = d.size, ga = d.alpha, t0 = math.huge })
	return g0 + GATHER[via]
end

-- A seat's dice in play into the hand, shaken until the throw.
local function Shake(seat)
	local side, now = sides[seat], GetTime()
	local g0 = max(now, S.ready[seat])
	local ready = g0
	for _, i in ipairs(side.play) do
		local d = side.dice[i]
		local p = d.plan
		if p and p.kind == "roll" and p.t0 == math.huge then ready = max(ready, p.g0 + p.gd)
		else ready = max(ready, Hand(d, g0)) end
	end
	S.hand[seat] = ready
	At(g0, function() if S.hand[seat] == ready then StartShake(seat) end end)
end

-- A seat's dice back to the cup (they fade where they are).
local function Collect(d)
	if d.alpha <= 0.01 then Still(d); d.where, d.alpha = "hidden", 0; Draw(d); return end
	Plan(d, { kind = "fade", t0 = GetTime(), dur = 0.2, a0 = d.alpha })
end

local AfterThrow
local function Throw(seat, dice, farkle, said)
	local side, now, gen = sides[seat], GetTime(), S.gen
	for _, i in ipairs(side.play) do
		local p = side.dice[i].plan
		if not (p and p.kind == "roll" and p.t0 == math.huge) then Shake(seat); break end
	end
	-- the throw starts the moment the dice are in the hand (at once when the line was slow)
	local base = max(now, S.hand[seat])
	S.flying[seat], S.hits[seat] = #dice, 0
	for j, v in ipairs(dice) do
		local d = side.dice[side.play[j]]
		local p = d.plan
		d.value, d.variant = v, random(4)
		p.t0 = base + (j - 1) * 0.035 + random() * 0.015
		p.dur = 0.8 + random() * 0.06
		p.tx, p.ty = LaneX(d.i) + random(-4, 4), REST[seat] + random(-3, 3)
		p.phase = random() * 2 * pi
		p.onEnd = function()
			if gen ~= S.gen then return end
			S.flying[seat] = S.flying[seat] - 1
			if S.flying[seat] == 0 then AfterThrow(seat, farkle, said) end
		end
	end
	At(base, function() StopShake(seat); Sound("throw") end)
end

-- Dice set aside: they light up where they lie, the points count up over them, and they move to
-- their seat's tray and shrink there (the leftmost first, so they never cross).
local function Tally(pts, list)
	local mx = 0
	for _, d in ipairs(list) do mx = mx + d.x end
	mx = mx / #list
	local at
	for _, d in ipairs(list) do if not at or abs(d.x - mx) < abs(at.x - mx) then at = d end end
	local t
	for _, e in ipairs(tallies) do if not e.t0 then t = e; break end end
	t = t or tallies[1]
	t.to, t.x, t.y, t.t0 = pts, at.x, at.y - 4, GetTime()
	t.fs:SetText("+0"); t.fs:SetAlpha(1); t.fs:Show()
	Place(t.fs, t.x, t.y, "CENTER")
	Run()
	Sound("tally")
end

local function SetAside(seat, pos, pts)
	local side, now = sides[seat], GetTime()
	local take, rest, moving = {}, {}, {}
	for _, p in ipairs(pos) do take[side.play[p]] = true end
	for _, i in ipairs(side.play) do
		if take[i] then moving[#moving + 1] = side.dice[i] else rest[#rest + 1] = i end
	end
	table.sort(moving, function(a, b) return a.x < b.x end)
	Tally(pts, moving)
	for _, d in ipairs(moving) do
		side.kept[#side.kept + 1] = d.i
		d.lit, d.hover = true, nil
		Plan(d, { kind = "sweep", t0 = now, dur = 0.4, fx = d.x, fy = d.y, fs = d.size, by = BAND[seat],
			tx = TRAYX + (#side.kept - 1) * TRAYSTEP, ty = TRAY[seat] })
	end
	side.play = rest
	S.ready[seat] = now + 0.4       -- the next throw's dice wait for these to clear the band
	if seat == 1 then S.sel = {} end
end

local function Faces(dice, pos)
	local out = {}
	for i, p in ipairs(pos) do out[i] = dice[p] end
	return table.concat(out, " ")
end

-- The final round and sudden death, said once each.
local function Notes()
	local g = S.game
	if g.over then return end
	if g.sudden and S.note ~= "sudden" then
		S.note = "sudden"
		Log("Level after the last turn: sudden death, a turn each.")
	elseif g.final and not S.note then
		S.note = "final"
		if g.capped then Log("The turn cap is reached: the higher score wins.")
		else Log((g.final == 2 and "You reached %s: the innkeeper gets one last turn." or "The innkeeper reached %s: you get one last turn."):format(Num(g.target))) end
	end
end

function AfterThrow(seat, farkle, said)
	local g, side = S.game, sides[seat]
	if said then Log(said) end
	if farkle then
		for _, i in ipairs(side.play) do local d = side.dice[i]; d.farkle = true; Draw(d) end
		local lost = g.last and g.last.lost or 0
		S.last[seat] = lost > 0 and ("Bones: lost " .. Num(lost)) or "Bones"
		Banner("BONES!", RED)
		Sound("farkle")
		Log(seat == 1 and (lost > 0 and ("BONES: you lose " .. Num(lost) .. ".") or "BONES: nothing scores.")
			or (lost > 0 and ("BONES for the innkeeper: it loses " .. Num(lost) .. ".") or "BONES for the innkeeper."))
		Notes()
		Later(1.6, NextTurn)
	elseif seat == 2 then
		Later(0.45, HouseStep)
	end
	Refresh()
end

---------------------------------------------------------------------------
-- Turns
---------------------------------------------------------------------------

-- A stake's result: the winner takes both stakes less the guild's 6% of the one won.
function Farkle.Payout(stake)
	local fee = floor(stake * FEE_BP / 10000)
	return 2 * stake - fee, fee
end

local function Winner()
	local g = S.game
	local won = g.winner == 1
	Banner(won and "YOU WIN" or "THE INNKEEPER WINS", won and GREEN or RED, true)
	Sound(won and "win" or "lose")
	local how = g.reason == "cap" and " at the turn cap" or ""
	Log(("%s%s, %s to %s."):format(won and "You win" or "The innkeeper wins", how, Num(g.scores[g.winner]), Num(g.scores[3 - g.winner])))
	-- the stake: a line in the wallet's history either way
	if (g.stake or 0) > 0 and not g.paid then
		g.paid = true
		if won then
			local back, fee = Farkle.Payout(g.stake)
			g.back = back
			Wallet.Move(back, ("Bones: won against the innkeeper, the guild's 6%%: %s"):format(Money(fee)),
				{ ("Bones: won, guild %s"):format(Money(fee)), "Bones: won" }, "bonethrow")
		else
			g.back = 0
			Wallet.Move(0, "Bones: lost to the innkeeper, nothing back", { "Bones: lost, nothing back", "Bones: lost" }, "bonethrow")
		end
	end
	Refresh()
end

-- A seat's first throw of a turn: all six dice in play, none set aside.
local function Fresh(seat)
	local who, phase = FR.Expect(S.game)
	if who == seat and phase == "roll" and S.game.turn.rolls == 0 then
		sides[seat].play, sides[seat].kept = { 1, 2, 3, 4, 5, 6 }, {}
		if seat == 1 then S.sel = {} end
	end
end

function NextTurn()
	local who = FR.Expect(S.game)
	if not who then return Winner() end
	Fresh(who)
	Refresh()
	if who == 2 then Later(0.35, HouseStep) end
end

-- The innkeeper's bank (the design): keep every scoring die; bank at 1,000 or more, at 550 or more
-- with three dice or fewer left, at 300 or more with two or fewer, or when it reaches the target.
-- Its last turn (the final round, or its last turn at the cap) it banks only for the lead.
local function HouseBanks()
	local g = S.game
	local t = g.turn
	local mine = g.scores[2] + t.points
	local last = g.final == 2 or (g.cap and not g.final and g.turns[2] + 1 >= g.cap and g.turns[1] >= g.cap)
	if last then return mine > g.scores[1] end
	if mine >= g.target then return true end
	return t.points >= 1000 or (t.points >= 550 and t.left <= 3) or (t.points >= 300 and t.left <= 2)
end

function HouseStep()
	local g = S.game
	if S.setup or not g then return end
	local who, phase = FR.Expect(g)
	if who ~= 2 or S.flying[2] > 0 then return end
	local side, t = sides[2], g.turn
	if phase == "keep" then
		-- it sets aside every scoring die: the roll's best, lit a moment first
		local points, pos = FR.Best(t.dice)
		for _, p in ipairs(pos) do local d = side.dice[side.play[p]]; d.lit = true; Draw(d) end
		Log(("The innkeeper keeps %s: +%s."):format(Faces(t.dice, pos), Num(points)))
		return Later(0.6, function()
			local pts, hot = FR.Keep(S.game, 2, pos)
			if not pts then return end
			SetAside(2, pos, pts)
			if hot then
				side.play, side.kept = { 1, 2, 3, 4, 5, 6 }, {}
				Banner("HOT DICE!", AMBER)
				Log("Hot dice: the innkeeper throws all six again.")
			end
			Refresh()
			Later(0.5, HouseStep)
		end)
	end
	if phase == "decide" and HouseBanks() then
		local pts = FR.Bank(g, 2)
		if not pts then return end
		S.last[2] = "Banked " .. Num(pts)
		Log(("The innkeeper banks %s. Total: %s."):format(Num(pts), Num(g.scores[2])))
		Sound("bank")
		Notes()
		Refresh()
		return Later(0.85, NextTurn)
	end
	Fresh(2)
	Shake(2)
	Refresh()
	Later(max(0.3, S.hand[2] - GetTime() + 0.2), function()
		local _, _, n = FR.Expect(S.game)
		if not n then return end
		local roll = random(1, FR.RANGES[n])
		local dice, farkle = FR.Roll(S.game, 2, roll)
		if not dice then return end
		Throw(2, dice, farkle, ("The innkeeper throws %s  (simulated)"):format(table.concat(dice, " ")))
		Refresh()
	end)
end

local function Vanish(d) Still(d); d.where, d.alpha, d.lit, d.hover, d.farkle = "hidden", 0, nil, nil, nil; Draw(d) end

local function StartGame()
	S.gen = S.gen + 1
	S.setup, S.timer, S.pending, S.hint, S.note, S.bn = nil, nil, nil, nil, nil, nil
	S.sel, S.last, S.flying, S.ready, S.hand = {}, {}, { 0, 0 }, { 0, 0 }, { 0, 0 }
	S.turnSeat, S.turnPts = nil, 0
	StopShake(1); StopShake(2)
	S.game = FR.New({ target = S.target, first = S.first })
	-- the practice stake comes out of the shared wallet (none if it holds less)
	if S.stake > Wallet.balance then S.stake = 0 end
	if S.stake > 0 then
		S.game.stake = S.stake
		Wallet.Move(-S.stake, ("Bones: stake on a game to %s"):format(Num(S.target)),
			{ ("Bones: stake, to %s"):format(Num(S.target)), "Bones: stake" }, "bonethrow")
	end
	counters = {}
	for seat = 1, 2 do
		local side = sides[seat]
		side.play, side.kept = { 1, 2, 3, 4, 5, 6 }, {}
		for i, d in ipairs(side.dice) do Vanish(d); d.value, d.variant = i, random(4) end
	end
	banner:Hide()
	logs[2]:SetText(""); logs[1]:SetText("")
	Log(("A game to %s%s. %s."):format(Num(S.target), S.game.stake and (", " .. Money(S.game.stake) .. " on it") or "",
		S.first == 1 and "You throw first" or "The innkeeper throws first"))
	NextTurn()
end

-- The setup step: the target, then Start (a new game, and Play again after one).
local function ToSetup()
	S.gen = S.gen + 1
	S.setup, S.timer, S.pending, S.hint, S.bn = true, nil, nil, nil, nil
	S.flying = { 0, 0 }
	StopShake(1); StopShake(2)
	for seat = 1, 2 do for _, d in ipairs(sides[seat].dice) do d.lit, d.hover = nil, nil; Collect(d) end end
	banner:Hide()
	Refresh()
end

---------------------------------------------------------------------------
-- Your moves
---------------------------------------------------------------------------

-- Your chosen dice: their positions in the last roll, and their faces.
local function Chosen()
	local pos, faces = {}, {}
	local dice = S.game.turn.dice or {}
	for j, i in ipairs(sides[1].play) do
		if S.sel[i] then pos[#pos + 1] = j; faces[#faces + 1] = dice[j] end
	end
	return pos, faces
end

-- Why a choice doesn't score: the dice left over once the most of them that score together are set
-- apart (FarkleRules.Score; the most dice, then the most points). A 2, 3, 4 or 6 can score inside
-- a run (KCD2), so from 2-3-4-5-6-6 only one 6 is left over, not every face but the 5. All of a
-- face left over reads "the 6" or "the 6s"; some of it, "one 6" or "two 6s".
local COUNT = { "one", "two", "three", "four", "five", "six" }
local function Dead(faces)
	local n, keep, most, top = #faces, 0, 0, 0
	for mask = 1, 2 ^ n - 1 do
		local sel, m = {}, mask
		for i = 1, n do
			if m % 2 == 1 then sel[#sel + 1] = faces[i] end
			m = floor(m / 2)
		end
		local points = FR.Score(sel)
		if points and (#sel > most or (#sel == most and points > top)) then keep, most, top = mask, #sel, points end
	end
	local total, left, m = {}, {}, keep
	for i = 1, n do
		local f = faces[i]
		total[f] = (total[f] or 0) + 1
		if m % 2 == 0 then left[f] = (left[f] or 0) + 1 end
		m = floor(m / 2)
	end
	local out, plural = {}, false
	for f = 1, 6 do
		local c = left[f]
		if c then
			local name = c > 1 and (f .. "s") or tostring(f)
			out[#out + 1] = (c == total[f] and "the " or (COUNT[c] .. " ")) .. name
			plural = plural or c > 1
		end
	end
	if #out == 0 then return "these don't score together" end
	return table.concat(out, " and ") .. ((plural or #out > 1) and " don't score" or " doesn't score")
end

local function AskRoll(n)
	local p = { n = n }
	S.pending, S.hint = p, nil
	Fresh(1)
	Shake(1)
	local ok = pcall(RandomRoll, 1, FR.RANGES[n]) -- gp:arena-clicks
	if not ok then S.hint = ("The game refused the roll: type /roll %d."):format(FR.RANGES[n]) end
	C_Timer.After(6, function()
		if S.pending ~= p then return end
		S.pending = nil
		StopShake(1)
		for _, i in ipairs(sides[1].play) do
			local d = sides[1].dice[i]
			if d.plan and d.plan.kind == "roll" then Collect(d) end
		end
		S.hint = ("No /roll line in 6 seconds. Roll again, or type /roll %d."):format(FR.RANGES[n])
		Refresh()
	end)
	Refresh()
end

-- Sets your chosen dice aside (Keep & roll, and Bank from the "keep" phase). Hot dice are
-- announced only when all six are thrown again, not when the turn is banked.
local function KeepChosen(banking)
	local pos, faces = Chosen()
	local pts, hot = FR.Keep(S.game, 1, pos)
	if not pts then return nil end
	SetAside(1, pos, pts)
	Log(("You keep %s: +%s."):format(table.concat(faces, " "), Num(pts)))
	if hot then
		sides[1].play, sides[1].kept = { 1, 2, 3, 4, 5, 6 }, {}
		if not banking then
			Banner("HOT DICE!", AMBER)
			Log("HOT DICE: throw all six again.")
		end
	end
	return pts
end

local function OnPrimary()
	-- (Start is the bar's right button while the setup shows: the owner's call, 2026-09-30.)
	if S.setup or not S.game then return StartGame() end
	local g = S.game
	if g.over then
		if Busy() then return end
		S.first = 3 - S.first
		return ToSetup()
	end
	local who, phase = FR.Expect(g)
	if who ~= 1 or Busy() then return end
	if phase == "keep" and not KeepChosen(false) then return Refresh() end
	local _, _, left = FR.Expect(g)
	if left then AskRoll(left) end
end

local function OnBank()
	local g = S.game
	if S.setup or not g then return end
	local who, phase = FR.Expect(g)
	if who ~= 1 or Busy() then return end
	if phase == "keep" and not KeepChosen(true) then return Refresh() end
	local pts = FR.Bank(g, 1)
	if not pts then return Refresh() end
	S.last[1] = "Banked " .. Num(pts)
	Log(("You bank %s. Total: %s."):format(Num(pts), Num(g.scores[1])))
	Sound("bank")
	Notes()
	Refresh()
	Later(0.85, NextTurn)
end

local function Pickable(d)
	if d.seat ~= 1 or S.setup or not S.game or d.plan then return false end
	local who, phase = FR.Expect(S.game)
	if who ~= 1 or phase ~= "keep" or Busy() then return false end
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

-- The realm as the server writes it after a name ("Name-Realm": no spaces or dashes).
local function Realm()
	local r = GetNormalizedRealmName and GetNormalizedRealmName()
	if type(r) ~= "string" or r == "" then r = ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "") end
	return r:lower()
end

-- Your name as the server writes it in a roll line. WoW: Forever's names are "First Surname", and
-- its UnitName("player") hands the surname back where other clients give the realm (nil for
-- your own), so a second value that is not this realm is a surname (forever-src
-- Blizzard_FrameXMLUtil/Camelot/NameUtil.lua). With regional unique names the first value may
-- hold both already.
local function MyName()
	local first, second = UnitName("player")
	if type(first) ~= "string" or first == "" then return nil end
	if first:find(" ", 1, true) then return first end
	if type(second) == "string" and second ~= "" and second:gsub("[%s%-]", ""):lower() ~= Realm() then
		return first .. " " .. second
	end
	return first
end

-- The game's roll line is yours: your name, alone or with this realm after it ("-Realm" is how
-- a line names someone from elsewhere, so another realm's namesake is not you).
local function Mine(name)
	local me = MyName()
	if not me then return false end
	me, name = me:lower(), name:lower()
	if name == me then return true end
	local base, realm = name:match("^(.-)%-([^%-]+)$")
	return base == me and realm:gsub("%s", "") == Realm() and Realm() ~= ""
end

local function OnLine(msg)
	if S.setup or not S.game or S.game.over then return end
	local name, value, low, high = AP.Roll(msg)
	if not name then
		if value == "secret" then S.hint = "Rolls can't be read here (chat lockdown)."; Refresh() end
		return
	end
	if not Mine(name) then return end
	local n = FR.RangeDice(low, high)
	if not n then return end                                   -- a /roll that throws no dice (1-100 ...)
	local who, phase, left = FR.Expect(S.game)
	-- a throw still in the air belongs to its thrower's turn: yours starts when the innkeeper's dice land
	if who ~= 1 or (phase ~= "roll" and phase ~= "decide") or S.flying[1] > 0 or S.flying[2] > 0 then
		S.hint = ("Your /roll %d-%d came when no throw was due: not counted."):format(low, high)
		return Refresh()
	end
	Fresh(1)
	if n ~= left then
		-- W2: a roll of the wrong number of dice is a foul, the turn ends as a Farkle
		if not FR.Foul(S.game, 1) then return end
		S.pending = nil
		StopShake(1)
		for _, i in ipairs(sides[1].play) do local d = sides[1].dice[i]; if d.plan and d.plan.kind == "roll" then Collect(d) end end
		S.last[1] = "Foul: turn lost"
		S.hint = nil
		Banner("FOUL", RED)
		Sound("farkle")
		Log(("Foul: %d %s thrown, %d in play. Turn lost."):format(n, n == 1 and "die" or "dice", left))
		Notes()
		Refresh()
		return Later(1.6, NextTurn)
	end
	local dice, farkle = FR.Roll(S.game, 1, value)
	if not dice then return end
	S.pending, S.hint = nil, nil
	Throw(1, dice, farkle, ("You throw %s  (/roll %s)"):format(table.concat(dice, " "), value))
	Refresh()
end

---------------------------------------------------------------------------
-- The table's texts and buttons, from the game's state
---------------------------------------------------------------------------

local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h); b:SetText(label)
	b:SetFrameLevel(parent:GetFrameLevel() + 10)
	b:SetScript("OnClick", fn)
	return b
end

local function Set(b, label, on)
	b:SetText(label)
	if on then b:Enable() else b:Disable() end
end

local function RowLine(seat, text)
	counters["turn" .. seat] = nil
	rows[seat].line:SetText(text)
end

function Refresh()
	if not win then return end
	local g = S.game
	for i, b in ipairs(targets) do if FR.TARGETS[i] == S.target then b:LockHighlight() else b:UnlockHighlight() end end
	-- the stake: what the wallet can pay (the choice falls back to none)
	if S.stake > Wallet.balance then S.stake = 0 end
	for i, b in ipairs(stakes) do
		if STAKES[i] == S.stake then b:LockHighlight() else b:UnlockHighlight() end
		if STAKES[i] <= Wallet.balance then b:Enable() else b:Disable() end
	end
	win.walletButton.Refresh()
	if S.setup or not g then
		stakeInfo:SetText(S.stake > 0 and ("Stake %s. The innkeeper matches it; a win pays %s back."):format(Money(S.stake), Money((Farkle.Payout(S.stake))))
			or "No stake: a game for the points.")
		setup:Show(); bankBtn:Hide()
		primary:Show(); Set(primary, "Start", true)
		if win.bar then win.bar.Relayout() end
		for _, t in ipairs(win.midline) do t:Hide() end
		win.sub:SetText("A practice game"); win.stage:SetText("")
		info:SetText(S.hint or "Choose the target, then Start.")
		for seat = 1, 2 do
			local p = rows[seat]
			p.hl:Hide()
			Count("total" .. seat, p.total, 0, Fmt)
			RowLine(seat, seat == 2 and "Practice opponent" or "Your own /roll")
		end
		for seat = 1, 2 do for _, d in ipairs(sides[seat].dice) do d.f:EnableMouse(false); HideDie(d.f) end end
		return
	end
	setup:Hide(); primary:Show(); bankBtn:Show()
	if win.bar then win.bar.Relayout() end
	for _, t in ipairs(win.midline) do t:Show() end
	local who, phase, left = FR.Expect(g)
	-- a throw in the air is still its thrower's (a Farkle has ended the turn in the rules already)
	local flying = (S.flying[1] > 0 and 1) or (S.flying[2] > 0 and 2) or nil
	local acting = flying or who
	if not flying then S.turnSeat, S.turnPts = who, g.turn.points end
	for seat = 1, 2 do
		local p = rows[seat]
		p.hl:SetShown(acting == seat)
		Count("total" .. seat, p.total, g.scores[seat], Fmt, 0.7)
		if acting == seat and S.turnSeat == seat and not g.over then
			local base = seat == 1 and "Your turn" or "Its turn"
			Count("turn" .. seat, p.line, S.turnPts or 0, function(n) return n > 0 and ("This turn: " .. Num(n)) or base end, 0.45)
		else
			RowLine(seat, S.last[seat] or (seat == 2 and "Practice opponent" or "Your own /roll"))
		end
	end
	local round = min(g.turns[1], g.turns[2]) + 1
	-- the target and the stage on lines of their own ("Play to 10,000 · sudden death" is wider
	-- than the column)
	win.sub:SetText("Play to " .. Num(g.target))
	local st = g.stake or 0
	if st == 0 then stakeInfo:SetText("No stake: a game for the points.")
	elseif g.back and g.back > 0 then stakeInfo:SetText(("You won %s: your %s back and the innkeeper's, less the guild's %s."):format(Money(g.back), Money(st), Money(st - (g.back - st))))
	elseif g.back then stakeInfo:SetText(("The innkeeper won your %s stake."):format(Money(st)))
	else stakeInfo:SetText(("%s on it, the innkeeper's %s against it. A win pays %s back."):format(Money(st), Money(st), Money((Farkle.Payout(st))))) end
	win.stage:SetText(g.over and "Game over" or g.sudden and "Sudden death" or g.final and "Last round" or ("Round " .. round))
	local text
	if flying == 1 then
		Set(primary, "Rolling...", false); Set(bankBtn, "Bank", false)
		text = "Your dice are rolling."
	elseif flying == 2 then
		Set(primary, "The innkeeper plays", false); Set(bankBtn, "Bank", false)
		text = "The innkeeper is throwing (simulated dice)."
	elseif g.over then
		Set(primary, "Play again", not S.timer); Set(bankBtn, "Bank", false)
		text = "The game is over."
	elseif who == 2 then
		Set(primary, "The innkeeper plays", false); Set(bankBtn, "Bank", false)
		text = "The innkeeper is playing."
	elseif S.pending then
		Set(primary, "Rolling...", false); Set(bankBtn, "Bank", false)
		text = "Rolling: waiting for your /roll line."
	elseif phase == "roll" then
		-- (a pause between turns still running: the buttons wait for it)
		Set(primary, ("Roll %d dice"):format(left), not S.timer); Set(bankBtn, "Bank", false)
		text = "Your turn: roll the dice."
	elseif phase == "decide" then
		Set(primary, ("Roll %d dice"):format(left), not S.timer)
		Set(bankBtn, "Bank " .. Num(g.turn.points), g.turn.points > 0 and not S.timer)
		text = ("%s this turn. Roll %d, or bank."):format(Num(g.turn.points), left)
	else -- keep
		local pos, faces = Chosen()
		local pts = #faces > 0 and FR.Score(faces)
		if pts then
			local rest = #g.turn.dice - #faces
			Set(primary, rest == 0 and "Keep & roll 6 (hot)" or ("Keep & roll %d"):format(rest), not S.timer)
			Set(bankBtn, "Bank " .. Num(g.turn.points + pts), not S.timer)
			text = ("Selected %s: %s+%s|r"):format(table.concat(faces, " "), GOOD, Num(pts))
		else
			Set(primary, "Keep & roll", false); Set(bankBtn, "Bank", false)
			text = #faces == 0 and "Click the dice that score to keep them."
				or ("Selected %s: %s%s.|r"):format(table.concat(faces, " "), BAD, Dead(faces))
		end
	end
	info:SetText(S.hint or text or "")
	-- your dice in play can be picked only while you choose (not the ones set aside)
	for _, d in ipairs(sides[1].dice) do
		local on = Pickable(d)
		d.f:EnableMouse(on)
		if not on and (d.hover or (d.lit and not d.plan and not S.sel[d.i])) then d.hover = nil; Draw(d) end
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function NewDie(seat, i)
	local d = { seat = seat, i = i, x = LaneX(i), y = REST[seat], h = 0, size = D, alpha = 0, value = i, variant = 1, where = "hidden" }
	d.f = NewSprite(win)
	d.f:SetFrameLevel(win:GetFrameLevel() + 3)
	d.f:SetScript("OnClick", function() Pick(d) end)
	if seat == 1 then
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

local function Row(seat, name)
	local top, p = ROW[seat], {}
	p.hl = win:CreateTexture(nil, "BORDER")
	p.hl:SetColorTexture(1, 0.86, 0.5, 0.2)
	p.hl:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -(top + (seat == 2 and 8 or 5)))
	p.hl:SetSize(COLX - 18, 50)
	p.hl:Hide()
	p.tray = win:CreateTexture(nil, "BORDER")   -- the tray: a shallow hollow in the plank
	p.tray:SetColorTexture(0.36, 0.2, 0.06, 0.1)
	p.tray:SetPoint("CENTER", win, "TOPLEFT", TRAYX + 2.5 * TRAYSTEP, -TRAY[seat]); p.tray:SetSize(6 * TRAYSTEP + 8, 36)
	p.name = Text(win, 20, INK, FontFor(name), "LEFT"); Place(p.name, 22, top + (seat == 2 and 11 or 7))
	p.name:SetWidth(270); p.name:SetWordWrap(false); p.name:SetText(name)
	p.line = Text(win, 13, SOFT, nil, "LEFT"); Place(p.line, 23, top + (seat == 2 and 37 or 32))
	p.line:SetWidth(270); p.line:SetWordWrap(false)
	p.total = Text(win, 30, INK, MORPHEUS, "RIGHT"); Place(p.total, COLX - 14, TRAY[seat] + (seat == 2 and 2 or -2), "RIGHT")
	rows[seat] = p
end

---------------------------------------------------------------------------
-- How to play: the lab's one pop-up (Games.lua's Games.Popup, the Lottery's too), centred over the
-- table (the same centre; the table itself opens centred on the screen), a strata above it so
-- none of the table's buttons draws on top of it, on the game's parchment in dark ink, in three pages: Rules (the goal and a turn, step by
-- step), Scores (every combination as its dice and its points) and Examples (two turns of two
-- throws, the dice to keep lit). The dice are the table's bone die. Every number and every
-- example on it comes from FarkleRules, so a change to FR.SCORES changes the guide with it. It
-- opens from "How to play" on the retained practice preview; "Got it", the X and Escape close it,
-- and it opens again on the page it was left at.
---------------------------------------------------------------------------

local GW, GH = 680, 590            -- inside a 1024 x 768 screen at UI scale 1
local GL, GR = 32, GW - 40         -- the pages' left and right edges, clear of the parchment's torn rims
local SAFE = { 28, 10, GW - 38, GH - 16 }   -- where anything may be (x, y, right, bottom): inside the rims
local PAGES = { "Rules", "Scores", "Examples", "Drink" }
-- A die icon is one cell of icons.tga (dice/guide/icons: the table's bone die rendered with each
-- face square to the frame, face v in column v of 8), never rotated: the shadow is baked in. A die
-- `size` px wide is drawn 2 x size wide; the die itself reaches 33.5/128 of that from its centre
-- (icons/meta.json), the rest is its shadow.
local ICONS = DICE .. "icons"
local REACH = 34 / 128 * 2
local HOT = { 0.58, 0.26, 0.0 }    -- HOT DICE on the parchment: the table's amber, darker
local PTS = { 0.42, 0.12, 0.03 }   -- the points on the parchment
local OFF = { 0.37, 0.23, 0.09 }   -- a tab not shown
local NUMBER = { "one", "two", "three", "four", "five", "six" }
-- The worked examples' throws: for each, the first of these that does what the example shows
-- under FR.SCORES, else the first throw of that many dice that does.
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

-- One line of text on a page, never wrapped: its top left at (x, y) from the page's top left,
-- in a box w wide (the points are right-justified in theirs).
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
-- "dull" (a Farkle's grey bone) or nil. order: its place in its row, left to right: each die is
-- drawn over the one before it (whose shadow falls to the right), its light over itself only.
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
local function RowWidth(items, size, step)
	local n, gaps = 0, 0
	for _, it in ipairs(items) do if it then n = n + 1 else gaps = gaps + 1 end end
	return (n - 1) * step + gaps * Gap(step) + 2 * REACH * size
end

local function Keys(list) local s = {}; for _, p in ipairs(list) do s[p] = true end; return s end
-- faces as row items: those at the positions in `kept` lit and the rest dimmed, or all one look
local function Items(faces, kept, look)
	local out = {}
	for i, v in ipairs(faces) do out[i] = { v, look or (kept and (kept[i] and "kept" or "dim")) or nil } end
	return out
end
-- the dice set aside earlier in the turn (lit), a gap, then a throw
local function After(before, throw)
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
		local s = FR.Score(group)
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
	if n and FR.RANGES[n] then
		for roll = 1, FR.RANGES[n] do
			local dice = FR.Decode(roll, n)
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
-- points, kept (positions: FR.Best's), before (the faces set aside earlier in the turn), turn (the
-- turn's points before this throw) }, or nil when FR.SCORES leaves no throw that shows it.
local function Worked()
	local function Throw(dice, before, turn)
		local points, kept = FR.Best(dice)
		return { dice = dice, points = points or 0, kept = kept or {}, before = before or {}, turn = turn or 0 }
	end
	local function Some(d) local p, k = FR.Best(d); return p and p > 0 and #k < #d end
	local function All(d) local p, k = FR.Best(d); return p and p > 0 and #k == #d end
	local function Three(d)
		if not Some(d) then return false end
		local _, k = FR.Best(d)
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
		ex.first = Throw(d)
		local set = KeptOf(ex.first)
		d = Find(PICKS.farkle, FR.DICE - #set, FR.Farkle)
		if d then ex.farkle = Throw(d, set, ex.first.points) end
	end
	d = Find(PICKS.triple, nil, Three)
	if d then
		ex.triple = Throw(d)
		local set = KeptOf(ex.triple)
		d = Find(PICKS.hot, FR.DICE - #set, All)
		if d then ex.hot = Throw(d, set, ex.triple.points) end
	end
	return ex
end

-- The combinations in four groups, with the points FarkleRules.Score gives the dice shown. A
-- combination set to false in FR.SCORES is left out. KCD2's points (2026-09-30): four, five and six
-- of a kind double the face's three of a kind per die, so their rows name a face (3s, and four
-- 1s); the runs are 1-2-3-4-5, 2-3-4-5-6 and 1-2-3-4-5-6.
local function Combos()
	local C = FR.SCORES
	local function On(v) return type(v) == "number" and v > 0 end
	local function Table(v) return type(v) == "table" and v or {} end
	local single, triple, kind, run = Table(C.single), Table(C.triple), Table(C.kind), Table(C.run)
	local groups = {
		{ key = "single", title = "Single dice", rows = {} },
		{ key = "triple", title = "Three of a kind", rows = {} },
		{ key = "kind", title = "Four, five or six of a kind", rows = {} },
		{ key = "run", title = "Runs", rows = {} },
	}
	local function Add(g, on, dice, name)
		local points = on and FR.Score(dice)
		local rows = groups[g].rows
		if points then rows[#rows + 1] = { dice = dice, name = name, points = points } end
	end
	Add(1, On(single[1]), { 1 }, "Each 1")
	Add(1, On(single[5]), { 5 }, "Each 5")
	for f = 1, 6 do Add(2, On(triple[f]), { f, f, f }, "Three " .. f .. "s") end
	Add(3, On(kind[4]), { 3, 3, 3, 3 }, "Four 3s")
	Add(3, On(kind[5]), { 3, 3, 3, 3, 3 }, "Five 3s")
	Add(3, On(kind[6]), { 3, 3, 3, 3, 3, 3 }, "Six 3s")
	Add(3, true, { 1, 1, 1, 1 }, "Four 1s")
	Add(4, On(run["12345"]), { 1, 2, 3, 4, 5 }, "Run 1-5")
	Add(4, On(run["23456"]), { 2, 3, 4, 5, 6 }, "Run 2-6")
	Add(4, On(run["123456"]), { 1, 2, 3, 4, 5, 6 }, "Run 1-6")
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
	local targets, caps = {}, {}
	for i, v in ipairs(FR.TARGETS) do
		targets[i] = Num(v)
		if FR.TURN_CAP and FR.TURN_CAP[v] then caps[#caps + 1] = tostring(FR.TURN_CAP[v]) end
	end
	Ink(pg, GL, 104, 300, "The goal", 18, INK, MORPHEUS)
	local goal = {
		("Be the first to reach the target chosen at the start (%s)."):format(List(targets)),
		"Reach it, and the other player gets one last turn to pass you.",
		"A tie goes on, a turn each, until one player is ahead.",
	}
	if #caps == #targets and #caps > 0 then
		goal[4] = ("After %s turns each (by target), the higher score wins."):format(List(caps))
	end
	pg.goal = {}
	for i, s in ipairs(goal) do pg.goal[i] = Ink(pg, GL, 128 + (i - 1) * 18, GR - GL, s) end
	local top = 128 + #goal * 18 + 8
	Ink(pg, GL, top, 300, "Your turn", 18, INK, MORPHEUS)
	local a, b, d = ex.first, ex.farkle, ex.hot
	-- each: { title, line, line, its dice, its buttons, the title's ink, how many of its dice were set
	-- aside before the throw }
	local steps = {
		{ "Roll", ("Press Roll %d dice: your own /roll throws"):format(FR.DICE), "them, so the server rolls every die.",
			a and Items(a.dice) },
		{ "Keep", "Click the dice that score to keep them:", "every die kept must score (see Scores).",
			a and Items(a.dice, Keys(a.kept)) },
		{ "Choose", "Keep & roll: throw the rest for more.", "Bank: the turn's points go to your total.", nil,
			a and { ("Keep & roll %d"):format(#a.dice - #a.kept), "Bank " .. Num(a.points) } },
		{ "BONES!", "Nothing in a throw scores: the turn ends,", "and the points it made are lost.",
			b and After(b.before, Items(b.dice, nil, "dull")), nil, RED, b and #b.before },
		{ "HOT DICE", "All six dice have scored: roll all six", "again, and the turn's points stay.",
			d and After(d.before, Items(d.dice, Keys(d.kept))), nil, HOT, d and #d.before },
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
-- Each die past three doubles the three of a kind, for every face that has one (KCD2's rule),
-- true in FarkleRules.
local function Doubles()
	local any = false
	for f = 1, 6 do
		local base = FR.Score({ f, f, f })
		if base then
			for m = 4, 6 do
				local dice = {}
				for i = 1, m do dice[i] = f end
				if FR.Score(dice) ~= base * 2 ^ (m - 3) then return false end
			end
			any = true
		end
	end
	return any
end

local function ScoresPage(pg)
	local groups = Combos()
	local doubles = Doubles()
	pg.rows, pg.heads, pg.notes = {}, {}, {}
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
				-- under four, five and six of a kind: how they score, when FarkleRules says so
				if g.key == "kind" and doubles then
					pg.notes[#pg.notes + 1] = Ink(pg, col.x, y + 4, col.r - col.x, "Each die past the third doubles the points.", 13, SOFT)
					y = y + 24
				end
			end
		end
		bottom = max(bottom, y)
	end
	pg.divider = Down(pg, mid, 108, bottom - 112, 0.2)
	-- how dice combine: within one throw, adding up (1 1 5 as dice), and why four 1s score as they
	-- do when four of a kind is left out (three 1s and a 1)
	local y = bottom + 12
	pg.notes[#pg.notes + 1] = Ink(pg, GL, y, GR - GL, "Only dice from one throw combine, and every die you keep must score.", 13, SOFT)
	local four, three, one = FR.Score({ 1, 1, 1, 1 }), FR.Score({ 1, 1, 1 }), FR.Score({ 1 })
	local fours = four and three and one and four == three + one
	local add = FR.Score({ 1, 1, 5 })
	y = y + 24
	if add then
		pg.notes[#pg.notes + 1] = Ink(pg, GL, y, 140, "Combinations add up:", 13, SOFT)
		pg.addUp = Dice(pg, Items({ 1, 1, 5 }), GL + 144, y + 8, 22, 27)
		pg.notes[#pg.notes + 1] = Ink(pg, GL + 230, y, GR - GL - 230,
			("is %s%s"):format(Num(add), fours and ", and four 1s are three 1s and a 1." or "."), 13, SOFT)
	elseif fours then
		pg.notes[#pg.notes + 1] = Ink(pg, GL, y, GR - GL, "Four 1s are three 1s and a 1.", 13, SOFT)
	end
end

-- Examples: two turns of two throws, the dice set aside earlier lit before a gap, the dice to
-- keep lit, what happens and the points.
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
		list[#list + 1] = { e = b, turn = 1, title = "BONES!", color = RED, label = Num(b.turn) .. " lost", lost = true, lines = {
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
		list[#list + 1] = { e = d, turn = 2, title = "HOT DICE", color = HOT, label = "+" .. Num(d.points), lines = {
			what, ("All six dice have scored: roll six again, %s kept."):format(Num(d.turn + d.points)) } }
	end
	Ink(pg, GL, 104, GR - GL, #list == 4 and "Two turns of two throws each: the lit dice are the ones to keep."
		or "The lit dice are the ones to keep.", 13, SOFT)
	local tx = GL + 222
	pg.examples = {}
	for i, x in ipairs(list) do
		local y, e = 136 + (i - 1) * 98, x.e
		-- a firmer line between the turns
		if i > 1 then Rule(pg, GL, y - 19, GR - GL, x.turn ~= list[i - 1].turn and 0.3 or 0.12) end
		local throw = Items(e.dice, e.points > 0 and Keys(e.kept) or nil, e.points == 0 and "dull" or nil)
		local icons = Dice(pg, #e.before > 0 and After(e.before, throw) or throw, GL, y + 30, 26, 32)
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

-- The page shown: its tab in dark ink with a bar under it, Back and Next where there is a page to
-- go to.
-- Drink (the owner's text, 2026-09-30, in the King's own voice): a row a level with its mugs (0 to
-- 3, like stars), the game's own line for it (DRUNK_MESSAGE_SELF1-4, each locale's words), and
-- what it does; how it works in three steps; an example with the dice; the catch. The numbers come
-- from FR.HICCUP and FR.SHAKES.
local MUGS = { "Interface\\Icons\\INV_Drink_05", "Interface\\Icons\\INV_Drink_04", "Interface\\Icons\\INV_Drink_08" }
local function OneIn(p) return floor(100 / p + 0.5) end
local function DrinkPage(pg)
	local H = FR.HICCUP or { 10, 20, 33 }
	local mug = ns.Games.FirstTexture(MUGS)
	Ink(pg, GL, 104, 300, "Drink", 18, INK, MORPHEUS)
	Ink(pg, GL + 90, 108, GR - GL - 90, "In games against other players; practice plays sober.", 12, SOFT, nil, "RIGHT")
	Ink(pg, GL, 134, GR - GL, "Okay, here's the deal. Drinking makes you better at dice. Yes, really. Don't ask.")
	local rows = {
		{ 0, "Sober", "-", "No buff. Boring." },
		{ 1, "Tipsy", _G.DRUNK_MESSAGE_SELF2 or "You feel tipsy. Whee!", ("Bust? 1 in %d you shake it off."):format(OneIn(H[1])) },
		{ 2, "Drunk", _G.DRUNK_MESSAGE_SELF3 or "You feel drunk. Woah!", ("1 in %d."):format(OneIn(H[2])) },
		{ 3, "Completely smashed", _G.DRUNK_MESSAGE_SELF4 or "You feel completely smashed.", ("1 in %d. This is the good stuff."):format(OneIn(H[3])) },
	}
	-- the columns: the mugs (3 x 22 px), the level, the game's line, the buff
	local cx = { GL, GL + 84, GL + 244, GL + 440 }
	pg.drink = {}
	for i, r in ipairs(rows) do
		local y = 162 + (i - 1) * 32
		if i > 1 then Rule(pg, GL, y - 6, GR - GL, 0.12) end
		local icons = {}
		for m = 1, math.max(1, r[1]) do
			local t = pg:CreateTexture(nil, "ARTWORK")
			t:SetTexture(mug); t:SetTexCoord(0.07, 0.93, 0.07, 0.93); t:SetSize(22, 22)
			t:SetPoint("TOPLEFT", pg, "TOPLEFT", cx[1] + (m - 1) * 25, -y)
			-- (sober: one faded, empty mug)
			if r[1] == 0 then t:SetDesaturated(true); t:SetAlpha(0.35) end
			icons[#icons + 1] = t
		end
		pg.drink[i] = { icons = icons,
			level = Ink(pg, cx[2], y + 3, cx[3] - cx[2] - 8, r[2], 15, INK, MORPHEUS),
			line = Ink(pg, cx[3], y + 4, cx[4] - cx[3] - 8, r[3], 12, SOFT),
			buff = Ink(pg, cx[4], y + 4, GR - cx[4], r[4], 12, INK) }
	end
	local top = 162 + 4 * 32 + 4
	Ink(pg, GL, top, 300, "How it works", 16, INK, MORPHEUS)
	local shakes = FR.SHAKES or 2
	local times = shakes == 2 and "Twice" or (shakes == 1 and "Once" or ("%d times"):format(shakes))
	local steps = {
		{ "1. Drink at the table. Your opponent's game has to see it, so no pre-gaming in Stormwind", "and walking in hammered. It counts from your next turn." },
		{ "2. You bust? Hit HIC! That's a /roll 1-100." },
		{ "3. Roll your number or lower and the bust never happened: you keep the turn's points and", ("throw the same dice again. %s a game, max. After that you're just drunk."):format(times) },
	}
	local y = top + 24
	for _, s in ipairs(steps) do
		for _, line in ipairs(s) do Ink(pg, GL, y, GR - GL, line); y = y + 17 end
		y = y + 3
	end
	-- the example: the throw that busts, as the table's dice, then the words
	local roll = math.min(27, H[3] - 1)
	y = y + 4
	Dice(pg, Items({ 2, 3, 4, 6 }, nil, "dull"), GL, y + 14, 22, 27)
	local ex = {
		"Smashed, 850 on the table, you throw these. Nothing scores. HIC!",
		("You roll %d. That's under %d, so the bust is gone: you still have"):format(roll, H[3]),
		"your 850, throw those four dice again.",
	}
	for i, line in ipairs(ex) do Ink(pg, GL + 128, y + (i - 1) * 16, GR - GL - 128, line, 12) end
	y = y + #ex * 16 + 8
	Ink(pg, GL, y, 120, "The catch", 14, INK, MORPHEUS)
	Ink(pg, GL + 90, y + 1, GR - GL - 90, "The game still does its thing. Blurry screen, slurred chat. You don't pass out,", 12, SOFT)
	Ink(pg, GL + 90, y + 17, GR - GL - 90, "you just look like an idiot. Worth it.", 12, SOFT)
end

local function Page(k)
	k = max(1, min(#PAGES, k or 1))
	S.page = k
	for i, pg in ipairs(help.pages) do
		pg:SetShown(i == k)
		help.tabs[i]:SetSelected(i == k)
	end
	help.back:SetShown(k > 1)
	help.next:SetShown(k < #PAGES)
end

---------------------------------------------------------------------------
-- The window's components (the owner on test 32): opponent search never leaves this window. The
-- Find sheet (Slip.lua), the match's card (ArenaMatch.lua) and the real table (FarkleBoard.lua)
-- each show inside it, over its introduction, while it is open; closing one (its X, Cancel,
-- Escape) gives the window back as it was. Closing the window takes them with it: the Find sheet
-- and the table close, a live search's or match's card goes back to its own place above.
-- While one shows, the introduction's words and Start Playing give way to it (its wood stays):
-- the component is the window's panel, never pasted over the words, and nothing under it acts.
---------------------------------------------------------------------------

local Here = {} -- the window's components and its introduction's layout (two blocks below)
do
-- Each a level above the introduction (+30), its button (+40) and the window's X (+50, Build).
-- The table covers the Find sheet; the match's card waits under the table opened over it (hidden,
-- back when the table closes), and a card that comes while the table is there shows over it.
local HOSTED = { find = 60, board = 70, card = 76 }
local function AUI() return ns.ArenaUI end
local function Board() local u = AUI() return type(u) == "table" and u.FarkleBoard or nil end
local function BoardWin() local B = Board() return B and B.Window and B.Window() or nil end
local function FindWin() local u = AUI() return type(u) == "table" and u.FindFrame and u.FindFrame() or nil end
local function CardWin() local M = host.ArenaMatch return type(M) == "table" and M.Card and M.Card() or nil end
local function Ours(f) return f ~= nil and f:GetParent() == win end
local function BoardHere() local b = BoardWin() return Ours(b) and b:IsShown() end
local function CardRehost() local M = host.ArenaMatch if type(M) == "table" and M.PlaceCard then M.PlaceCard() end end
-- (a search, an offer or a match going on: ArenaMatch's own view says so)
local function MatchLive()
	local M = host.ArenaMatch
	if type(M) ~= "table" or type(M.View) ~= "function" then return false end
	local ok, v = pcall(M.View)
	return ok and type(v) == "table" and v.state ~= nil and v.state ~= "idle"
end

-- Escape closes what is on top: how to play or a component, then the table (Games.lua's
-- Games.Escape names the table in UISpecialFrames only while none of them shows).
function Here.EscapeSync()
	if not (win and help and ns.Games and ns.Games.Escape) then return end
	local over = { help }
	for _, f in ipairs({ FindWin() or false, CardWin() or false, BoardWin() or false }) do
		if f and Ours(f) then over[#over + 1] = f end
	end
	ns.Games.Escape("OlympusArenaGamesBoneThrow", win, over)
	-- (the match's card over the table, the room's Details: Escape closes the card, then the table)
	local B, c = Board(), CardWin()
	if B and B.EscapeUnder then B.EscapeUnder(BoardHere() and Ours(c) and c:IsShown()) end
end

-- The introduction's words and its button, shown only while no component of ours is.
local function Cover()
	if not intro then return end
	local covered = false
	for _, f in ipairs({ FindWin() or false, CardWin() or false, BoardWin() or false }) do
		if f and Ours(f) and f:IsShown() then covered = true end
	end
	for _, r in ipairs({ intro.kicker, intro.title, intro.body, intro.start }) do
		if r then r:SetShown(not covered) end
	end
end

-- The match's card the table was opened over ([Open the table]): it waits under the table, hidden,
-- and comes back, as it is then, when the table closes (while there is a card to show).
local under = false
local function CardBack()
	if not under then return end
	under = false
	local M = host.ArenaMatch
	if type(M) == "table" and M.ShowCard then M.ShowCard() end
end

-- A component showed or hid here (each calls win.hostChanged).
local function HostChanged(child, shown)
	local board = BoardWin()
	if child == board then
		if shown then
			-- The table is the window's now: the Find sheet goes, the card waits under it, the
			-- introduction stays under it (so the strip below the table is the window's own wood,
			-- never the practice bar).
			local f, c = FindWin(), CardWin()
			if Ours(f) and f:IsShown() then f:Hide() end
			if Ours(c) and c:IsShown() then under = true c:Hide() end
			if intro then intro:Show() end
		else
			CardBack()
		end
	elseif shown and child == FindWin() then
		-- (A match's ended card under a new Find sheet: the sheet's search brings the card back. A
		-- live search's or match's card stays, over the sheet: hidden, nothing would bring it back.)
		local c = CardWin()
		if Ours(c) and c:IsShown() and not MatchLive() then c:Hide() end
	elseif shown and child == CardWin() then
		-- (the card shown while it waited under the table, the player asking for it: it waits no more)
		under = false
	end
	CardRehost()
	Cover()
	Here.EscapeSync()
end
-- Where a component of ours goes now: this window while it is open (the card and the Find sheet
-- for Bones only; the Find sheet never while the table covers the window), else nil (its own
-- place).
local function HostFor(kind, game)
	if not (win and win:IsShown()) then return nil end
	if kind ~= "board" and game ~= "b" then return nil end
	if kind == "find" and BoardHere() then return nil end
	return win, HOSTED[kind]
end
function Here.Hosting()
	win.hostChanged = HostChanged
	local u = AUI()
	if type(u) == "table" then u.BonesHost = function(game) return HostFor("find", game) end end
	local M = host.ArenaMatch
	if type(M) == "table" and M.SetCardHost then M.SetCardHost(function(game) return HostFor("card", game) end) end
	local B = Board()
	-- (and when combat closed the table here, the table comes back here after it: this window opens)
	if B and B.SetHost then B.SetHost(function() return HostFor("board") end, function() Farkle.Open() end) end
end
-- The window opened: a live search's card comes in; a table already open elsewhere, or the live
-- one this player sits at, shows here, over the card (which waits under it). It closed: the
-- components go with it.
function Here.Adopt()
	CardRehost()
	local B = Board()
	if B and B.Rehost then B.Rehost() end
	local FT = host.FarkleTable
	if B and B.Show and not BoardHere() and type(FT) == "table" and FT.Live and FT.Live() then B.Show() end
	Cover()
end
function Here.Release()
	local f = FindWin()
	if Ours(f) and f:IsShown() then f:Hide() end
	local B = Board()
	if B and BoardHere() and B.Close then B.Close() end
	if B and B.Rehost then B.Rehost() end
	-- (a card waiting under the table goes back above: the table's own OnHide may not come while
	-- the window hides, its parent hidden first)
	CardBack()
	CardRehost()
	Cover()
end
-- Combat closes this window (Events, below): the table in it closes first as combat closes it on
-- its own (FarkleBoard's Board.CombatClose: it comes back after combat, in this window), whichever
-- of the two hears PLAYER_REGEN_DISABLED first; never as the window's X closes it (for good).
function Here.Combat()
	local B = Board()
	if B and BoardHere() and B.CombatClose then B.CombatClose() end
end
end
local function EscapeSync() return Here.EscapeSync() end

local function Help()
	-- the lab's one pop-up (Games.lua's Games.Popup, made from this one): the parchment in its thin
	-- dark frame, centred over the table, a strata above it, the X and Escape
	help = ns.Games.Popup("OlympusArenaGamesBoneThrowRules", GW, GH, win)
	help.title = Text(help, 24, INK, MORPHEUS); help.title:SetPoint("TOP", 0, -16)
	help.title:SetText("How to play Bones")
	-- the pages, and a tab for each: its name in Morpheus (not a button like Back, Got it and Next),
	-- a bar of ink under it when shown, a faint one while the mouse is on another
	help.pages, help.tabs = {}, {}
	local tw, gap = 120, 16
	local tx = (GW - #PAGES * tw - (#PAGES - 1) * gap) / 2
	for k, name in ipairs(PAGES) do
		help.pages[k] = NewPage(help)
		help.pages[k].name = name
		-- (the games' one tab, Games.InkTab, made from these)
		local tab = ns.Games.InkTab(help, name, tw, function() Page(k) end)
		tab:SetPoint("TOPLEFT", help, "TOPLEFT", tx + (k - 1) * (tw + gap), -52)
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
	help.back = Button(help, "Back", 110, 30, function() Page(S.page - 1) end)
	help.back:SetPoint("TOPLEFT", help, "TOPLEFT", GL, -(GH - 50))
	help.ok = Button(help, "Got it", 140, 30, function() help:Hide() end)
	help.ok:SetPoint("TOP", help, "TOPLEFT", GW / 2, -(GH - 50))
	help.next = Button(help, "Next", 110, 30, function() Page(S.page + 1) end)
	help.next:SetPoint("TOPRIGHT", help, "TOPLEFT", GR, -(GH - 50))
	Page(S.page)
	-- Escape closes what is on top: this pop-up, then the table
	help:HookScript("OnShow", function() EscapeSync() end)
	help:HookScript("OnHide", function() EscapeSync() end)
end

-- The setup step, in the middle of the table: the target, then Start, in dark ink straight on
-- the table (no panel behind it; the line between the halves hides while it shows).
local function Setup()
	setup = CreateFrame("Frame", nil, win)
	setup:SetFrameLevel(win:GetFrameLevel() + 13)
	setup:SetPoint("TOPLEFT", win, "TOPLEFT", 118, -70); setup:SetSize(370, 256)
	local title = Text(setup, 26, INK, MORPHEUS)
	title:SetPoint("TOP", 0, -4); title:SetText("Play to")
	local sub = { "quick", "standard", "long" }
	for k, target in ipairs(FR.TARGETS) do
		local b = Button(setup, Num(target), 104, 32, function() S.target = target; Refresh() end)
		b:SetPoint("TOPLEFT", setup, "TOPLEFT", 18 + (k - 1) * 116, -42)
		local fs = Text(setup, 13, SOFT)
		fs:SetPoint("TOP", b, "BOTTOM", 0, -4); fs:SetText(sub[k] or "")
		targets[k] = b
	end
	-- the practice stake, from the shared wallet
	local st = Text(setup, 22, INK, MORPHEUS)
	st:SetPoint("TOP", 0, -104); st:SetText("Stake")
	setup.stakeTitle = st
	for k, v in ipairs(STAKES) do
		local b = Button(setup, v == 0 and "None" or Money(v), 82, 32, function() S.stake = v; Refresh() end)
		b:SetPoint("TOPLEFT", setup, "TOPLEFT", 6 + (k - 1) * 92, -138)
		stakes[k] = b
	end
	-- (Start: the footer bar's right button, the arena's rule for every game, 2026-09-30.)
end

-- The Bones section is an invitation into the game, not a pre-filled practice table. In a test
-- build this lab window is the section's first surface, so cover the entire table with one opaque
-- in-world introduction. Its only action opens the production matcher inside this window (the
-- owner on test 32: the window stays, the Find sheet is its component); no opponent, stake, House
-- seat or player identity is rendered until the player deliberately starts that flow.
local function StartPlaying()
	local UI = own.ArenaUI
	local FT = host.FarkleTable
	if FT and not FT.CanPlayPlayers() then Say(L.FARKLE_LOBBY_FIRST); return false, "training" end
	if FT and not FT.CanOpen() then Say(L.FARKLE_LOG_TAVERN_REST); return false, "tavern-rest" end
	if type(UI) ~= "table" then
		Say(L.FARKLE_INTRO_UNAVAILABLE or "opponent search is not available in this build.")
		return false, "missing"
	end
	-- This button is the pre-search transition, so open the existing fixed-game filter sheet
	-- directly, hosted here. Its Search action still enters ArenaMatch.Start and all of its
	-- consent/privacy gates; this call itself sends nothing and owns no matching state. A live
	-- search or match shows its card instead (match.open), hosted here too (ArenaMatch.SetCardHost).
	local M = host.ArenaMatch
	local view = type(M) == "table" and type(M.View) == "function" and M.View() or nil
	local busy = type(view) == "table" and view.state ~= "idle"
	local open = not busy and type(UI.OpenFind) == "function" and UI.OpenFind or UI.FindOpponent
	if type(open) ~= "function" then
		Say(L.FARKLE_INTRO_UNAVAILABLE or "opponent search is not available in this build.")
		return false, "missing"
	end
	local ok, result, why = pcall(open, "b", win)
	if not ok then
		if host.CaptureError then host.CaptureError("bones start playing", result) end
		return false, "error"
	end
	return result == nil and true or result, why
end

-- The introduction's words, one group centred in the space above its button: the button's band
-- is not part of the group, and the button stays at the bottom (the owner on test 32), whatever
-- the window's size or the words' length (another language, another font).
Here.INTRO_W, Here.INTRO_GAPS = 620, { 12, 24 } -- the group's width; kicker to title, title to body
do
local function TextHeight(fs)
	local h = fs.GetStringHeight and tonumber(fs:GetStringHeight()) or 0
	if h > 0 then return h end
	local _, size = fs:GetFont()
	return (tonumber(size) or 14) * 1.2
end
function Here.IntroLayout()
	if not intro then return end
	local gaps = Here.INTRO_GAPS
	local h = TextHeight(intro.kicker) + gaps[1] + TextHeight(intro.title) + gaps[2] + TextHeight(intro.body)
	intro.block:SetHeight(math.ceil(h))
end
end

local function Intro()
	intro = CreateFrame("Frame", nil, win)
	intro:SetAllPoints(win)
	intro:SetFrameLevel(win:GetFrameLevel() + 30)
	intro:EnableMouse(true)

	-- The same tavern wood as the table, fully opaque, keeps the surface in-world while ensuring
	-- none of the setup underneath (including its names and stakes) can show through.
	intro.bg = intro:CreateTexture(nil, "BACKGROUND")
	intro.bg:SetAllPoints()
	intro.bg:SetTexture(MEDIA .. "farkle-table")
	intro.bg:SetTexCoord(4 / 1024, 1020 / 1024, 4 / 512, 508 / 512)
	intro.shade = intro:CreateTexture(nil, "BORDER")
	intro.shade:SetAllPoints()
	intro.shade:SetColorTexture(0.08, 0.035, 0.01, 0.82)

	-- The button at the bottom; above it the content area (the window's top to the button's
	-- top), and the words' group in its middle.
	intro.start = Button(intro, L.FARKLE_START_PLAYING or "Start Playing", 190, 36, StartPlaying)
	intro.start:SetPoint("BOTTOM", intro, "BOTTOM", 0, 58)
	intro.actions = { intro.start }
	intro.content = CreateFrame("Frame", nil, intro)
	intro.content:SetPoint("TOPLEFT", intro, "TOPLEFT", 0, 0)
	intro.content:SetPoint("TOPRIGHT", intro, "TOPRIGHT", 0, 0)
	intro.content:SetPoint("BOTTOM", intro.start, "TOP", 0, 0)
	intro.block = CreateFrame("Frame", nil, intro.content)
	intro.block:SetPoint("CENTER", intro.content, "CENTER", 0, 0)
	intro.block:SetSize(Here.INTRO_W, 1)

	local pale, soft = { 1, 0.84, 0.52 }, { 0.92, 0.84, 0.70 }
	intro.kicker = Text(intro, 14, soft, MORPHEUS, "CENTER")
	intro.kicker:SetPoint("TOP", intro.block, "TOP", 0, 0)
	intro.kicker:SetWidth(Here.INTRO_W)
	intro.kicker:SetText(L.FARKLE_INTRO_KICKER or "A TAVERN GAME OF NERVE AND LUCK")
	intro.title = Text(intro, 36, pale, MORPHEUS, "CENTER")
	intro.title:SetPoint("TOP", intro.kicker, "BOTTOM", 0, -Here.INTRO_GAPS[1])
	intro.title:SetWidth(Here.INTRO_W)
	intro.title:SetText(L.FARKLE_INTRO_TITLE or "Bones")
	intro.body = Text(intro, 16, soft, nil, "CENTER")
	intro.body:SetPoint("TOP", intro.title, "BOTTOM", 0, -Here.INTRO_GAPS[2])
	intro.body:SetWidth(570)
	intro.body:SetJustifyV("TOP")
	intro.body:SetWordWrap(true)
	intro.body:SetText(L.FARKLE_INTRO_TEXT or "Cast six bones, keep what scores, and decide whether to bank your points or risk another throw. Olympus will find another player nearby; once you both accept, your private match room opens so you can agree on the tavern and meet there.")
	Here.IntroLayout()
	-- (measured again each time it shows: the client lays a font out once it has drawn it)
	intro:SetScript("OnShow", function() Here.IntroLayout() end)
	intro:Show()
end

local function Build()
	win = CreateFrame("Frame", "OlympusArenaGamesBoneThrow", UIParent)
	win:SetSize(W, WIN_H); win:SetPoint("CENTER", 0, 0); win:SetFrameStrata("DIALOG")   -- centred, as every game window
	win:SetMovable(true); win:SetClampedToScreen(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
	-- The table in two halves that leave out the texture's rows 251-259 (a faint seam across its
	-- middle), which the client drew as a broken line of coloured dashes. 247/512 and 263/512 meet
	-- at SPLIT (the seam repainted and the edges cleaned by scripts/make-table-texture.py).
	local top = win:CreateTexture(nil, "BACKGROUND"); top:SetTexture(MEDIA .. "farkle-table")
	-- (4 texels or more from any seam or edge, 2026-09-30: the texture itself is cleaned too,
	-- scripts/make-table-texture.py)
	top:SetTexCoord(4 / 1024, 1020 / 1024, 4 / 512, 247 / 512)
	top:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0); top:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -SPLIT)
	local bottom = win:CreateTexture(nil, "BACKGROUND"); bottom:SetTexture(MEDIA .. "farkle-table")
	bottom:SetTexCoord(4 / 1024, 1020 / 1024, 263 / 512, 508 / 512)
	bottom:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -SPLIT); bottom:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -H)
	win.table = { top, bottom }
	-- (the footer's wood: the games' one bar draws it, Games.Bar, below)
	-- The parchment game windows' frame round the table (the Lottery's: DialogBorderTemplate, the
	-- owner's call 2026-09-30, one frame for the three games), 10 px outside the table's edge so
	-- none of the table is covered.
	local okB, border = pcall(CreateFrame, "Frame", nil, win, "DialogBorderTemplate")
	if okB and border then
		border:SetPoint("TOPLEFT", win, "TOPLEFT", -10, 10)
		border:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 10, -10)
		if rawget(border, "Bg") then border.Bg:Hide() end
		win.border = border
	end
	-- the column, the line between the halves
	local wash = win:CreateTexture(nil, "BORDER"); wash:SetColorTexture(0.3, 0.16, 0.04, 0.1)
	wash:SetPoint("TOPLEFT", win, "TOPLEFT", COLX + 1, -8); wash:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -8, -(H - 8))
	Groove(COLX, 10, 1, H - 20)
	win.midline = Groove(16, SPLIT - 1, COLX - 32, 1)   -- hidden under the setup, which sits across it

	driver = CreateFrame("Frame", nil, win)
	-- The window's X, over its introduction (+30) and Start Playing (+40), under its components
	-- (Here, from +60): with the gamepad UI nothing of ours is on the Escape list, and the window
	-- closes with this X there.
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 6, 6); close:SetFrameLevel(win:GetFrameLevel() + 50)
	win.close = close

	-- the column: the game's name, target and round; help; what to do; the buttons; the log
	local title = Text(win, 20, INK, MORPHEUS, "LEFT"); Place(title, COLX + 16, 10); title:SetText("Bones")
	win.title = title
	win.sub = Text(win, 13, SOFT, nil, "LEFT"); Place(win.sub, COLX + 17, 34); win.sub:SetWidth(W - COLX - 26); win.sub:SetWordWrap(false)
	win.stage = Text(win, 13, SOFT, nil, "LEFT"); Place(win.stage, COLX + 17, 50); win.stage:SetWidth(W - COLX - 26); win.stage:SetWordWrap(false)
	info = Text(win, 13, INK, nil, "LEFT"); Place(info, COLX + 17, 76); info:SetSize(W - COLX - 30, 100)
	info:SetJustifyV("TOP"); info:SetMaxLines(5)
	-- the stake: what is on the game, what a win pays, what came of it
	stakeInfo = Text(win, 13, SOFT, nil, "LEFT"); Place(stakeInfo, COLX + 17, 196); stakeInfo:SetSize(W - COLX - 30, 70)
	stakeInfo:SetJustifyV("TOP"); stakeInfo:SetMaxLines(4)
	-- The games' one bar (Games.Bar, 2026-09-30): the coin and the balance, How to play; on the
	-- right the table's actions (Start, Roll, Keep & roll, Play again; Bank).
	win.bar = ns.Games.Bar(win, { y = H, h = FOOT_H, inset = 0,
		help = function()
			local board = own.ArenaUI and own.ArenaUI.FarkleBoard
			if board and board.ShowGuide then return board.ShowGuide() end
			if help:IsShown() then help:Hide() else ns.Games.HideWallet(win); help:Show() end
		end })
	win.foot, win.walletButton, win.helpButton = win.bar.foot, win.bar.wallet, win.bar.help
	bankBtn = Button(win, "Bank", 150, 32, OnBank)
	primary = Button(win, "Roll 6 dice", 168, 32, OnPrimary)
	win.bar.Place({ bankBtn, primary })
	logs[1] = Text(win, 12, INK, nil, "LEFT"); Place(logs[1], COLX + 17, 338); logs[1]:SetSize(W - COLX - 30, 30)
	logs[2] = Text(win, 12, SOFT, nil, "LEFT"); Place(logs[2], COLX + 17, 369); logs[2]:SetSize(W - COLX - 30, 16)
	for _, l in ipairs(logs) do l:SetJustifyV("TOP") end
	logs[1]:SetMaxLines(2); logs[2]:SetMaxLines(1)

	Row(2, "The innkeeper")
	Row(1, MyName() or "You")

	overlay = CreateFrame("Frame", nil, win)
	overlay:SetAllPoints(); overlay:SetFrameLevel(win:GetFrameLevel() + 8)
	for k = 1, 3 do
		local fs = Text(overlay, 22, GREEN, MORPHEUS)
		fs:Hide()
		tallies[k] = { fs = fs }
	end
	local hold = CreateFrame("Frame", nil, win)
	hold:SetSize(1, 1); hold:SetPoint("CENTER", win, "TOPLEFT", COLX / 2, -SPLIT); hold:SetFrameLevel(win:GetFrameLevel() + 12)
	banner = CreateFrame("Frame", nil, hold)
	banner:SetSize(420, 60); banner:SetPoint("CENTER")
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	SetFont(banner.text, MORPHEUS, 46, "OUTLINE"); banner.text:SetPoint("CENTER")
	banner.text:SetShadowColor(0, 0, 0, 0.6); banner.text:SetShadowOffset(2, -2)
	banner:Hide()
	Help()
	Setup()
	Intro()
	Here.Hosting()

	for seat = 1, 2 do
		sides[seat] = { dice = {}, play = { 1, 2, 3, 4, 5, 6 }, kept = {} }
		for i = 1, 6 do sides[seat].dice[i] = NewDie(seat, i) end
	end

	win:SetScript("OnShow", function()
		-- one game's window at a time: the Lottery's closes, the lab's hub hides
		if ns.Games and ns.Games.Shown then ns.Games.Shown("bonethrow") end
		Here.Adopt()
		EscapeSync()
		events:RegisterEvent("CHAT_MSG_SYSTEM")
		if S.setup or not S.game then return Refresh() end
		Refresh()
		if not (S.game.over or S.timer or S.flying[1] > 0 or S.flying[2] > 0) then NextTurn() end
	end)
	win:SetScript("OnHide", function()
		if help then help:Hide() end
		ns.Games.HideWallet(win)
		Here.Release()
		EscapeSync()
		events:UnregisterEvent("CHAT_MSG_SYSTEM")
		S.timer, S.pending = nil, nil
		StopShake(1); StopShake(2)
		for seat = 1, 2 do
			for _, d in ipairs(sides[seat].dice) do
				if d.plan and d.plan.kind == "roll" and d.plan.t0 == math.huge then Still(d); d.where, d.alpha = "hidden", 0; Draw(d) end
			end
		end
	end)
	win:Hide()
end

---------------------------------------------------------------------------
-- The command and the events
---------------------------------------------------------------------------

-- (Made with the table, not at load: the arena's companion keeps no frame of its own while idle.)
local function Events()
	if events then return end
	events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function(_, event, msg)
		if event == "CHAT_MSG_SYSTEM" then return OnLine(msg) end
		if win and win:IsShown() then Here.Combat(); win:Hide(); Say("closed: you entered combat.") end
	end)
end

function Farkle.Command(arg)
	arg = strtrim(arg or ""):lower()
	if InCombatLockdown() then return Say("not in combat.") end
	if arg == "sound" then
		S.sound = not S.sound
		if not S.sound then StopShake(1); StopShake(2) end
		return Say("sound effects " .. (S.sound and "on." or "off."))
	end
	if arg ~= "" then return Say("/oly bones opens the table; /oly bones sound turns its sounds on or off.") end
	if win and win:IsShown() then return win:Hide() end
	return Farkle.Open()
end

-- Opens the table (never closes it; the lab's hub and /oly bones come here) on its introduction.
-- The photo tour alone asks for mode "practice". The Lottery's window closes (the table's OnShow).
function Farkle.Open(mode)
	if mode == "practice" and host.FarkleTable and not host.FarkleTable.CanOpen() then Say(L.FARKLE_LOG_TAVERN_REST); return false end
	if InCombatLockdown() then return Say("not in combat.") end
	if not win then Events(); Build() end
	win:Show()
	if mode == "practice" then
		intro:Hide()
		Refresh()
	else
		if help then help:Hide() end
		ns.Games.HideWallet(win)
		intro:Show()
	end
end
-- Closes the table (how to play with it); its X and Escape do the same.
function Farkle.Close() if win and win:IsShown() then win:Hide() end end
function Farkle.IsOpen() return win ~= nil and win:IsShown() end
function Farkle.Window() return win end

-- For the offline tests: the table's parts, state and geometry (read only).
Farkle._ = { S = S, sides = sides, SND = SND, AREAS = AREAS, HouseBanks = HouseBanks, mine = Mine, step = Step, line = function(msg) OnLine(msg) end,
	startPlaying = StartPlaying,
	STAKES = STAKES, FEE_BP = FEE_BP,
	geo = { W = W, H = H, FOOT_H = FOOT_H, WIN_H = WIN_H, D = D, K = K, SW = SW, EDGE = EDGE, REST = REST, BAND = BAND, TRAY = TRAY, TRAYX = TRAYX, TRAYSTEP = TRAYSTEP,
		LANE = LANE, LaneX = LaneX, SPLIT = SPLIT, COLX = COLX, HAND_H = HAND_H },
	guide = { W = GW, H = GH, SAFE = SAFE, PAGES = PAGES, MORPHEUS = MORPHEUS, ICONS = ICONS, INK = INK, OFF = OFF },
	parts = function() return { win = win, driver = driver, primary = primary, bank = bankBtn, info = info, logs = logs,
		banner = banner, rows = rows, targets = targets, stakes = stakes, stakeInfo = stakeInfo, help = help, setup = setup, intro = intro, tallies = tallies,
		close = win and win.close } end,
	flipBook = function() return flipBook end }
