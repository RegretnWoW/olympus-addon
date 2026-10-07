local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): LotteryBoard.lua. A stub the arena's core created for the Lottery's package to
-- fill. The Menagerie Lottery's table (the design): 5x5 cards (number, the beast's mark
-- or icon, name, its four dezenas), filling the window, parchment look, a bet row at the bottom
-- (Enter to bet), the result slip of the five prizes.
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
--
-- The screen follows the owner's playable preview (the lab's Bicho.lua): a bingo card of the 25
-- beasts filling the window, each card its number, its image (the gold marks the preview chose,
-- or the game's icon for the six new ones), its name and its four dezenas, with the tickets and
-- the gold on it; the result slip on the right, a jogo do bicho result revealed one prize at a
-- time (each number spins, then lands, with the game's sounds), every drawn beast lit in gold, a
-- banner with the five-place rule and the exact settled return; How to play, the lab's three pages
-- (The deal, The rules, The payout) on the games' one pop-up (Games.Popup, Games.InkTab), shown by
-- itself the first time on The deal (the full name and the explanation, Lottery.FirstUse: no
-- King's letter); once the bank settles a day with this player's tickets, a result card (Bones'
-- card's pattern: the tickets, staked, refunded, won or lost, the balance, the Wallet). The bottom
-- (Bones' bar, the owner's rule of 2026-09-30): the counter (the pick, the stake: steppers, no edit
-- box, so the gamepad UI works and nothing takes the chat's keyboard), and Bet (Enter bets too,
-- with the keyboard) or the draw's Roll on the right of the games' bar under the board (Games.Bar:
-- the arena window's, or the board's own window's with the coin, the balance and How to play).
-- The King's corner (his client alone): who rolls, the draw time and the switch.
--
-- It is the betting window's "Lottery" section (ArenaUI.RegisterPane, the screens' window hosts it). While
-- that window is not in the build, ArenaUI.LotteryWindow(show) is a window of its own
-- (OlympusArenaLottery) so the lottery can be played and tested. Everything it shows comes from
-- ns.Lottery (Today, Bet, Draw, SetSchedule through the arena's actions); ArenaUI.LotteryModel()
-- is that view as plain data, for the tests. ArenaUI.LotterySlip(parent) builds the result slip
-- for another screen (the King's overlay, the screens).
-- Animations are AnimationGroups; timing is C_Timer; the countdown is one C_Timer.NewTicker(1) that
-- runs only while the board is shown with a countdown on it.
local ArenaUI = own.ArenaUI
local L = ns.L
local function WalletShown() return ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet() == true end

local floor, max, min = math.floor, math.max, math.min

local MORPHEUS = "Fonts\\MORPHEUS.TTF"
local PARCHMENT = "Interface\\QuestFrame\\QuestBG"
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
-- Ink on parchment: dark, with a light edge under it so small text stands off the paper.
local INK, SOFT, LIGHT = { 0.15, 0.07, 0.02 }, { 0.3, 0.17, 0.06 }, { 0.98, 0.9, 0.72 }
local GOLD, RED, GREEN = { 1, 0.82, 0.25 }, { 0.62, 0.07, 0.04 }, { 0.12, 0.36, 0.05 }
local BRONZE = { 0.45, 0.3, 0.1 }

-- The game's sounds (SoundKit ids of the 1.60.1.70124 client, the lab's own list): a beast picked
-- or put back, a coin for a bet, the dice's toss and their stone as a prize spins and lands, the
-- quest-complete fanfare for a win, the quest-failed kits otherwise.
local SND = { pick = 1204, unpick = 1221, bet = 120, spin = 349217, land = 349221, win = 878, lose = 846, rollover = 847,
	practiceStart = 31579, practiceSpin = 31580, practiceSettle = 31581, practiceHead = 31578 }

local SPIN = 0.9       -- seconds a prize's number spins before it lands
local NEXT = 0.45      -- and before the next one starts
local FRESH = 900      -- a result younger than this is revealed one prize at a time when the board opens
local SIDE = 190       -- the slip's column
local HEADER = 64
local BOTTOM = 44      -- the counter (the pick and the stake), under the cards
local GAP = 4
local GUIDE_W, GUIDE_H = 680, 560 -- How to play: the arena's and Bones' size
local CARD_W = 380     -- the result card

local board          -- the board's frames: { frame, cards, slip, bet, caller, banner, ... }
local state = { pick = nil, stake = nil, revealed = {}, note = nil }
-- The tutorial is deliberately a companion-only, memory-only state. It never becomes an Arena
-- event, a Markets sheet, a Wallet entry or an honour. A /reload forgets it. (1.1.6: its tickets
-- are free practice tickets, no stake of play money; each draw goes into the player's games, the
-- games' ledger's, ArenaLedger.Played: when, the beast, the five numbers, the places hit.)
local practice = { pick = nil, prizes = nil }
local PracticeArt
local practiceWindow, RefreshPracticeWindow
local StartPracticeReveal, StopPracticeReveal
local sounds = {}

local function Lot() return ns.Lottery end

local function Sound(key)
	if type(PlaySound) ~= "function" or not SND[key] then return end
	local now = GetTime and GetTime() or 0
	if sounds[key] and now - sounds[key] < 0.07 then return end
	sounds[key] = now
	local ok, played, handle = pcall(PlaySound, SND[key], "SFX")
	return ok and played and handle or nil
end

local function SetFont(fs, font, size, flags)
	if not fs:SetFont(font or MORPHEUS, size, flags or "") then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "") end
end
local function Text(parent, size, color, font, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
	SetFont(fs, font, size)
	fs:SetTextColor(color[1], color[2], color[3])
	if color == LIGHT or color == GOLD then
		fs:SetShadowColor(0, 0, 0, 0.9)
	else
		fs:SetShadowColor(1, 0.94, 0.8, 0.6)   -- pressed into the paper
	end
	fs:SetShadowOffset(1, -1)
	if justify then fs:SetJustifyH(justify) end
	return fs
end
local function Edge(f, c, a, size, layer)
	local out = {}
	for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, size }, { "TOPLEFT", "BOTTOMLEFT", size, 0 },
		{ "TOPRIGHT", "BOTTOMRIGHT", size, 0 } }) do
		local t = f:CreateTexture(nil, layer or "BORDER")
		t:SetColorTexture(c[1], c[2], c[3], a)
		t:SetPoint(p[1]); t:SetPoint(p[2])
		if p[3] > 0 then t:SetWidth(p[3]) else t:SetHeight(p[4]) end
		out[#out + 1] = t
	end
	return out
end
local function Parchment(f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(PARCHMENT)
	bg:SetTexCoord(0, 300 / 512, 0, 336 / 512)
	return bg
end
local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, max(24, h))   -- (every button 24 px or taller: the gamepad UI)
	b:SetText(label)
	b:SetScript("OnClick", fn)
	return b
end
local function Enable(b, on)
	b.isOn = on and true or false   -- (what the board set: its tests read it)
	if on then b:Enable() else b:Disable() end
end
-- An animation, when the client gives one (a stand-in frame may not).
local function Anim(group, kind)
	local a = group and group.CreateAnimation and group:CreateAnimation(kind)
	return a
end

local function Money(copper, cur) return Lot().Money(copper, cur) end
-- A card's corner: whole gold (or silver under a gold piece), whole points or chips.
local function Short(copper, cur)
	copper = floor(tonumber(copper) or 0)
	if cur == "p" or cur == "c" then return ns.FormatNumber(floor(copper / 100)) end
	if copper >= 10000 then return ns.FormatNumber(floor(copper / 10000)) .. "g" end
	return floor(copper / 100) .. "s"
end
local function Clock(seconds)
	seconds = max(0, floor(seconds))
	local h, m, s = floor(seconds / 3600), floor(seconds % 3600 / 60), seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end
local function Now() return ns.Arena.Now() end

---------------------------------------------------------------------------
-- The view, as plain data (the tests read it; the frames are drawn from it)
---------------------------------------------------------------------------

-- The stake's steps: 10s under 1g, 1g under 10g, 5g above.
local function Step(silver, up)
	if up then
		if silver < 100 then return 10 end
		if silver < 1000 then return 100 end
		return 500
	end
	if silver <= 100 then return 10 end
	if silver <= 1000 then return 100 end
	return 500
end
local function Clamp(silver)
	local Lt = Lot()
	return min(Lt.MaxSilver(), max(Lt.MinSilver(), floor(silver)))
end
local function Stake()
	if not state.stake then state.stake = Clamp(max(Lot().MinSilver(), 100)) end
	return state.stake
end

function ArenaUI.LotteryModel(day)
	local Lt = Lot()
	day = day or Lt.Today()
	local m = { title = L.LOTTERY_NAME, day = day, state = day.state, eid = day.eid, cards = {}, rows = {},
		rehearsal = day.mode == "T", points = day.cur == "p", instructions = L.LOTTERY_BOARD_RULES }
	local cur = day.cur or "g"
	-- The line under the title: the draw time, the countdown, the pot.
	local parts = {}
	-- (1.1.6: no day opens while the compliance gate allows no ticket: the board says so, and the
	-- section's practice table plays.)
	m.compliance = type(Lt.Wagers) == "function" and not Lt.Wagers() and L.COMPLIANCE_LOTTERY_PRACTICE or nil
	if day.state == "none" then
		parts[1] = m.compliance or Lt.WhyText("none")
	else
		-- (On the draw's clock, with its name: US Central, or UTC-5 on a realm off it.)
		parts[#parts + 1] = L.LOTTERY_BOARD_DRAW_AT:format(Lt.WhenText(day.drawAt))
		if day.state == "open" then
			parts[#parts + 1] = L.LOTTERY_BOARD_CLOSES:format(Clock((day.drawAt or 0) - Now()))
		elseif day.late then
			parts[#parts + 1] = L.LOTTERY_BOARD_LATE
		elseif day.state == "closed" or day.state == "drawing" then
			parts[#parts + 1] = L.LOTTERY_BOARD_CLOSED
		else
			parts[#parts + 1] = L.LOTTERY_BOARD_DRAWN
		end
		local pot = L.LOTTERY_BOARD_POT:format(Money(day.pot, cur))
		if (day.carry or 0) > 0 then pot = pot .. " " .. L.LOTTERY_BOARD_CARRY:format(Money(day.carry, cur)) end
		parts[#parts + 1] = pot
	end
	m.line = table.concat(parts, "  ·  ")
	m.band = m.rehearsal and L.LOTTERY_BOARD_REHEARSAL or (m.points and L.LOTTERY_BOARD_POINTS or nil)
	-- The 25 cards.
	local mine = {}
	for _, t in ipairs(day.mine or {}) do mine[t.o] = (mine[t.o] or 0) + t.s end
	for i, b in ipairs(Lt.BEASTS) do
		local bet = day.bets and day.bets[i] or { pool = 0, count = 0 }
		m.cards[i] = { n = i, num = ("%02d"):format(i), name = b.name, art = b.art, icon = b.icon == true, dezenas = Lt.DezenasText(i),
			count = bet.count or 0, pool = bet.pool or 0,
			tickets = (bet.count or 0) > 0 and L.LOTTERY_BOARD_TICKETS:format(bet.count, Short(bet.pool, cur)) or "",
			mine = mine[i], picked = state.pick == i, positions = {} }
	end
	-- The slip: this day's draw once it is due; while this day still takes bets, the last draw's
	-- result (the next day opens right after a draw: the result stays in sight). As many prizes as
	-- are known; the board reveals them one at a time.
	local slipDay, slip = day, { current = true }
	if day.state == "open" and not (day.prizes and #day.prizes > 0) then
		local last = Lt.LastDrawn(day.eid)
		if last then slipDay, slip.current = Lt.Day(last), false end
	end
	slip.day, slip.eid = slipDay, slipDay.eid
	slip.fresh = slipDay.drawAt ~= nil and Now() - slipDay.drawAt <= FRESH
	local complete = slipDay.prizes and #slipDay.prizes == Lt.PRIZES and not slipDay.live
	slip.title = complete and (slip.current and L.LOTTERY_BOARD_RESULT or L.LOTTERY_BOARD_LAST) or L.LOTTERY_BOARD_WAITING
	slip.note = slipDay.live and L.LOTTERY_BOARD_LIVE or nil
	slip.rows = m.rows
	for p = 1, Lt.PRIZES do
		local v = slipDay.prizes and slipDay.prizes[p]
		local b = v and Lt.Beast(Lt.BeastOf(v))
		m.rows[p] = { place = L["LOTTERY_PRIZE_" .. p], number = v and Lt.Text(v) or "----", beast = b and b.n or nil,
			label = b and Lt.Label(b.n) or "", art = b and b.art or nil, icon = b and b.icon == true or false }
	end
	m.slip = slip
	-- This day's five positions on their cards (never the last draw's: the cards are this day's bets).
	-- A repeated beast keeps each position, but its card is lit only once.
	if slip.current and day.prizes and not day.live then
		for position, prize in ipairs(day.prizes) do
			local animal = Lt.BeastOf(prize)
			if m.cards[animal] then m.cards[animal].positions[#m.cards[animal].positions + 1] = position end
		end
	end
	-- The banner, once the five are declared: this day's, or the last draw's while it is fresh.
	if complete and (slip.current or slip.fresh) then
		local sd = slipDay
		local b = Lt.Beast(Lt.BeastOf(sd.prizes[1]))
		local scur = sd.cur or cur
		local sub = Lt.ShareText(sd) or ""
		m.banner = { title = L.LOTTERY_BOARD_HEAD, number = Lt.PrizesText(sd.prizes), art = b.art, icon = b.icon == true,
			sub = sub, won = (sd.myPayout or 0) > 0 and L.LOTTERY_BOARD_YOU_WON:format(Money(sd.myPayout, scur)) or nil,
			mine = #(sd.mine or {}) > 0 }
	end
	-- The bet row.
	local pick = state.pick and Lt.Beast(state.pick)
	local silver = Stake()
	m.bet = { pick = pick and L.LOTTERY_BOARD_YOUR_PICK:format(Lt.Label(pick.n), Lt.DezenasText(pick.n)) or L.LOTTERY_BOARD_PICK,
		stake = Money(silver * 100, cur), silver = silver }
	local ok, why = Lt.CanBet(state.pick or 1, silver, day)
	m.bet.can = ok and state.pick ~= nil
	m.bet.why = not ok and Lt.WhyText(why) or nil
	-- (Before a bet, an illustration: about what this stake brings back if the pick comes 1st and
	-- nowhere else, the table as it is now, Lottery.Preview; to the silver, as it is an estimate.)
	if pick then
		local p = Lt.Preview(day, pick.n, silver)
		m.bet.estimate = p
		m.bet.preview = p and L.LOTTERY_BOARD_PREVIEW:format(Lt.Label(pick.n), Money(p.payout - p.payout % 100, cur)) or L.LOTTERY_BOARD_RETURN
	end
	local W = ns.Wallet
	if WalletShown() and day.bank and type(W) == "table" and type(W.Statement) == "function" then
		local okS, st = pcall(W.Statement, day.bank)
		local side = okS and type(st) == "table" and (cur == "p" and st.p or st.g)
		if type(side) == "table" and side.bal then m.bet.wallet = L.LOTTERY_BOARD_WALLET:format(Money(side.bal, cur)) end
	end
	m.bet.note = state.note
	-- This player's tickets, by beast.
	m.mine = {}
	local list = {}
	for _, t in ipairs(day.mine or {}) do list[#list + 1] = t end
	table.sort(list, function(a, b) if a.o ~= b.o then return a.o < b.o end return a.s > b.s end)
	for _, t in ipairs(list) do m.mine[#m.mine + 1] = L.LOTTERY_BOARD_MINE_LINE:format(Lt.Label(t.o), Money(t.s, cur)) end
	-- The King's corner.
	if day.isCaller then
		local sch = day.schedule or Lt.Schedule()
		local done = day.prizes and #day.prizes or 0
		m.caller = { roll = L.LOTTERY_BOARD_ROLL:format(min(Lt.PRIZES, done + 1)), canRoll = day.canDraw == true,
			roller = day.roller == "bank" and L.LOTTERY_BOARD_ROLLER_BANK or L.LOTTERY_BOARD_ROLLER_KING,
			time = Lt.MinutesText(sch.at) .. " " .. Lt.ZoneText(), at = sch.at,
			on = sch.on and L.LOTTERY_BOARD_ON or L.LOTTERY_BOARD_OFF, isOn = sch.on }
	elseif day.canDraw then
		-- (The lottery's bank, when a draw is due: its own Roll button.)
		m.caller = { roll = L.LOTTERY_BOARD_ROLL:format(min(Lt.PRIZES, (day.prizes and #day.prizes or 0) + 1)), canRoll = true, bank = true }
	end
	return m
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

local Refresh -- (below)

local function Tip(owner, lines)
	if not GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	for i, line in ipairs(lines) do
		if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
	end
	GameTooltip:Show()
end
local function Untip() if GameTooltip then GameTooltip:Hide() end end

local function Pick(i)
	if state.pick == i then
		state.pick = nil
		Sound("unpick")
	else
		state.pick = i
		Sound("pick")
	end
	state.note = nil
	Refresh()
end

local function Bet()
	if not state.pick then return end
	local silver = Stake()
	local t, why = ns.Arena.Do("lottery.bet", state.pick, silver)
	local Lt = Lot()
	if t and t ~= true then
		Sound("bet")
		state.note = L.LOTTERY_BOARD_PLACED:format(Money(silver * 100, Lt.Today().cur), Lt.Label(state.pick))
	else
		state.note = Lt.WhyText(why) or tostring(why)
	end
	Refresh()
end
ArenaUI.LotteryBet = Bet

local function Card(parent, i)
	local c = CreateFrame("Button", nil, parent)
	c.bg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
	c.bg:SetAllPoints()
	c.bg:SetColorTexture(0.32, 0.2, 0.08, 0.16)
	c.edge = Edge(c, BRONZE, 0.9, 1)
	c.gold = Edge(c, GOLD, 1, 2, "OVERLAY")
	for _, t in ipairs(c.gold) do t:Hide() end
	c.num = Text(c, 15, INK, MORPHEUS, "LEFT")
	c.num:SetPoint("TOPLEFT", 5, -3)
	c.art = c:CreateTexture(nil, "ARTWORK")
	c.art:SetPoint("TOP", 0, -4)
	c.name = Text(c, 12, INK, MORPHEUS)
	c.dez = Text(c, 10, SOFT, STANDARD_TEXT_FONT)
	c.dez:SetPoint("BOTTOM", 0, 3)
	-- The tickets and the gold on it: a small dark pill in the top corner, over the image's edge.
	c.pill = CreateFrame("Frame", nil, c)
	c.pill:SetPoint("TOPRIGHT", -2, -2)
	c.pill:SetSize(40, 14)
	local pb = c.pill:CreateTexture(nil, "BACKGROUND")
	pb:SetAllPoints()
	pb:SetColorTexture(0.08, 0.04, 0.01, 0.6)
	c.badge = Text(c.pill, 10, LIGHT, STANDARD_TEXT_FONT, "RIGHT")
	c.badge:SetPoint("RIGHT", -3, 0)
	c.pill:Hide()
	c.coin = c:CreateTexture(nil, "OVERLAY")
	c.coin:SetSize(12, 12)
	c.coin:SetPoint("BOTTOMRIGHT", -3, 3)
	c.coin:SetTexture(COIN)
	c.coin:Hide()
	c.glow = c:CreateTexture(nil, "OVERLAY")
	c.glow:SetAllPoints()
	c.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	c.glow:SetBlendMode("ADD")
	c.glow:Hide()
	c.shine = c:CreateTexture(nil, "OVERLAY", nil, 2)
	c.shine:SetAllPoints()
	c.shine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
	c.shine:SetBlendMode("ADD")
	c.shine:Hide()
	c.pulse = c.shine:CreateAnimationGroup()
	local a = Anim(c.pulse, "Alpha")
	if a then a:SetFromAlpha(0.15); a:SetToAlpha(0.7); a:SetDuration(0.8); a:SetSmoothing("IN_OUT") end
	if c.pulse and c.pulse.SetLooping then c.pulse:SetLooping("BOUNCE") end
	c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	c:SetScript("OnClick", function() Pick(i) end)
	c:SetScript("OnEnter", function(self)
		local m = self.model
		if not m then return end
		local lines = { ("%s %s"):format(m.num, m.name), L.LOTTERY_BOARD_TIP_CARD:format(m.dezenas) }
		lines[3] = m.count > 0 and L.LOTTERY_BOARD_TIP_POOL:format(m.count, Money(m.pool, board.model and board.model.day.cur)) or L.LOTTERY_BOARD_TIP_EMPTY
		Tip(self, lines)
	end)
	c:SetScript("OnLeave", Untip)
	c.n, c.lit = i, false
	return c
end

local function Row(parent, p)
	local r = CreateFrame("Frame", nil, parent)
	r.place = Text(r, 12, GOLD, MORPHEUS, "LEFT")
	r.place:SetPoint("TOPLEFT", 6, -4)
	r.number = Text(r, 21, LIGHT, MORPHEUS, "LEFT")
	r.number:SetPoint("TOPLEFT", 36, -1)
	r.art = r:CreateTexture(nil, "ARTWORK")
	r.art:SetSize(32, 32)
	r.art:SetPoint("RIGHT", -6, 0)
	r.label = Text(r, 12, LIGHT, MORPHEUS, "LEFT")
	r.label:SetPoint("BOTTOMLEFT", 36, 4)
	r.label:SetPoint("RIGHT", r.art, "LEFT", -4, 0)
	r.line = r:CreateTexture(nil, "BORDER")
	r.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	r.line:SetHeight(1)
	r.line:SetPoint("BOTTOMLEFT", 6, 0); r.line:SetPoint("BOTTOMRIGHT", -6, 0)
	-- The spin: the number flickers through random digits (each loop a new one) until it lands.
	r.spin = r:CreateAnimationGroup()
	local a = Anim(r.spin, "Alpha")
	if a then a:SetFromAlpha(1); a:SetToAlpha(0.55); a:SetDuration(0.07) end
	if r.spin and r.spin.SetLooping then r.spin:SetLooping("REPEAT") end
	if r.spin and r.spin.SetScript then
		r.spin:SetScript("OnLoop", function() r.number:SetText(("%04d"):format(math.random(0, 9999))) end)
	end
	-- The landing: a stamp, larger then its size.
	r.land = r:CreateAnimationGroup()
	local s = Anim(r.land, "Scale")
	if s then s:SetScaleFrom(1.45, 1.45); s:SetScaleTo(1, 1); s:SetDuration(0.22); s:SetSmoothing("OUT") end
	local f = Anim(r.land, "Alpha")
	if f then f:SetFromAlpha(0.2); f:SetToAlpha(1); f:SetDuration(0.18) end
	r.p, r.spinning = p, false
	return r
end

-- The result slip: a dark card with a gold edge, its title, the five rows. Built for the board, and
-- for another screen that wants it (the King's overlay).
function ArenaUI.LotterySlip(parent)
	local slip = CreateFrame("Frame", nil, parent)
	local bg = slip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.06, 0.02, 0.88)
	Edge(slip, GOLD, 0.85, 2)
	slip.title = Text(slip, 16, GOLD, MORPHEUS)
	slip.title:SetPoint("TOP", 0, -8)
	slip.note = Text(slip, 10, LIGHT, STANDARD_TEXT_FONT)
	slip.note:SetPoint("TOP", slip.title, "BOTTOM", 0, -1)
	slip.rows = {}
	for p = 1, 5 do slip.rows[p] = Row(slip, p) end
	function slip.Layout(w, h)
		slip:SetSize(w, h)
		local top, rh = 36, floor((h - 42) / 5)
		for p, r in ipairs(slip.rows) do
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", slip, "TOPLEFT", 4, -(top + (p - 1) * rh))
			r:SetSize(w - 8, rh)
		end
	end
	-- Rows shown up to `upto` (the others still "----"); a row being revealed spins.
	function slip.Fill(rows, upto, title, note)
		slip.title:SetText(title or "")
		slip.note:SetText(note or "")
		for p, r in ipairs(slip.rows) do
			local m = rows[p]
			r.place:SetText(m.place)
			if p <= upto and m.beast then
				r.number:SetText(m.number)
				r.label:SetText(m.label)
				r.art:SetTexture(m.art)
				if m.icon then r.art:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.art:SetTexCoord(0, 1, 0, 1) end
				r.art:Show()
			elseif r.spinning ~= true then
				r.number:SetText("----")
				r.label:SetText("")
				r.art:Hide()
			end
		end
	end
	return slip
end

local function Banner(parent)
	local b = CreateFrame("Button", nil, parent)
	-- (Above the cards, which are its siblings.)
	b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.04, 0.01, 0.88)
	Edge(b, GOLD, 1, 2)
	b.art = b:CreateTexture(nil, "ARTWORK")
	b.art:SetSize(60, 60)
	b.art:SetPoint("LEFT", 16, 0)
	b.title = Text(b, 28, GOLD, MORPHEUS, "LEFT")
	SetFont(b.title, MORPHEUS, 28, "OUTLINE")
	b.title:SetPoint("TOPLEFT", b.art, "TOPRIGHT", 14, 2)
	b.sub = Text(b, 13, LIGHT, STANDARD_TEXT_FONT, "LEFT")
	b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
	b.won = Text(b, 16, { 0.55, 1, 0.35 }, MORPHEUS, "LEFT")
	b.won:SetPoint("TOPLEFT", b.sub, "BOTTOMLEFT", 0, -3)
	b.pop = b:CreateAnimationGroup()
	local s = Anim(b.pop, "Scale")
	if s then s:SetScaleFrom(0.6, 0.6); s:SetScaleTo(1, 1); s:SetDuration(0.3); s:SetSmoothing("OUT") end
	local a = Anim(b.pop, "Alpha")
	if a then a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.25) end
	-- A click puts it away (the card behind it stays lit).
	b:SetScript("OnClick", function(self) self:Hide() state.bannerHidden = board and board.model and board.model.slip.eid end)
	b:Hide()
	return b
end

-- The games' one pop-up (Games.Popup: the parchment in the game windows' frame, a strata above them,
-- the X, Escape) over the window the board is in; a plain parchment where the games are not loaded,
-- and when built with the gamepad UI on (How to play and the result card open by themselves).
-- Either way Escape goes through ns.EscapeCloses each time one shows: nothing written to
-- UISpecialFrames in the gamepad UI (0.9.8), and a name the list had before a switch to it leaves
-- it when it is the last one.
local function Popup(name, w, h, over)
	local G = own.Games
	if G and type(G.Popup) == "function" and not ns.GamepadUI() then
		local f = G.Popup(name, w, h, over)
		f:HookScript("OnShow", function() ns.EscapeCloses(name) end)
		return f
	end
	local f = CreateFrame("Frame", name, UIParent)
	f:Hide()
	f:SetSize(w, h)
	f:SetPoint("CENTER", over or UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	Parchment(f)
	Edge(f, { 0.07, 0.04, 0.02 }, 0.95, 3)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", 2, 2)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f.over = over
	f:SetScript("OnShow", function()
		ns.EscapeCloses(name)
		if f.over then f:ClearAllPoints() f:SetPoint("CENTER", f.over, "CENTER", 0, 0) end
	end)
	return f
end
-- The window the board is in: the arena window, or the board's own.
local function HostWindow()
	if practiceWindow and practiceWindow:IsShown() then return practiceWindow end
	local p = board and board.frame and board.frame:GetParent()
	while p do
		if p == ArenaUI.frame or rawget(p, "lotteryWindow") then return p end
		p = p:GetParent()
	end
	return ArenaUI.frame
end

---------------------------------------------------------------------------
-- How to play: the lab's three pages (The deal, The rules, The payout) behind the games' tabs, on
-- the games' pop-up; the deal is the first-use explanation, the payout's example is
-- Lottery.Settle's, every word en and pt-BR (Locales/LotteryText.lua)
---------------------------------------------------------------------------

-- The worked example: 1,000g on the table, 100g of it on the Sheep (yours 40g), the 1st prize 4827
-- (its 27 is the Sheep's), nobody on the four other beasts drawn. Settled by the real contract.
local EXAMPLE = { milhar = 4827, draw = { 7, 1, 3, 4, 6 }, yours = 1,
	bets = { { 7, 400000 }, { 7, 600000 }, { 14, 5000000 }, { 2, 2500000 }, { 25, 1500000 } } }
local function Example()
	local Lt = Lot()
	local tickets = {}
	for i, b in ipairs(EXAMPLE.bets) do tickets[i] = { id = ("example.%d"):format(i), animal = b[1], stake = b[2] } end
	local r = Lt.Settle({ version = Lt.SETTLEMENT_VERSION, tickets = tickets, draw = EXAMPLE.draw, carry = 0, feeBp = Lt.DEFAULT_FEE_BP })
	if not r then return nil end
	local beast = Lt.BeastOf(EXAMPLE.milhar)
	local i = EXAMPLE.yours
	local onHead = 0
	for _, b in ipairs(EXAMPLE.bets) do if b[1] == beast then onHead = onHead + b[2] end end
	return { milhar = Lt.Text(EXAMPLE.milhar), ending = ("%02d"):format(EXAMPLE.milhar % 100), beast = beast,
		pot = r.available, onHead = onHead, yours = EXAMPLE.bets[i][2], other = onHead - EXAMPLE.bets[i][2],
		refunds = r.refunds, profit = r.profitPool, first = r.tranches[1].gross, fee = r.tranches[1].fee,
		share = r.profitByTicket[i], back = r.refundByTicket[i], get = r.payouts[i], carry = r.nextCarry,
		percent = floor(EXAMPLE.bets[i][2] * 100 / onHead + 0.5) }
end

-- The guide as plain data (the tests read it; the pages are drawn from it): per page its blocks,
-- in a centred column or a left and a right one. A block: { head }, { para, icon }, { step, para },
-- { ledger = { { label, amount, color } } }.
function ArenaUI.LotteryGuideModel()
	local Lt = Lot()
	if not Lt.Wagers() then
		return { title = L.LOTTERY_GUIDE_TITLE, free = true,
			tabs = { L.LOTTERY_GUIDE_RULES, L.LOTTERY_GUIDE_DRAW }, pages = {
				{ icons = { 1, 17, Lt.OUTCOMES }, center = {
					{ head = L.LOTTERY_GUIDE_GOAL }, { para = L.LOTTERY_FREE_GUIDE_GOAL },
					{ head = L.LOTTERY_GUIDE_DAY }, { step = 1, para = L.LOTTERY_GUIDE_STEP_1 },
					{ step = 2, para = L.LOTTERY_FREE_GUIDE_DRAW }, { step = 3, para = L.LOTTERY_FREE_GUIDE_AGAIN },
				} },
				{ center = {
					{ head = L.LOTTERY_GUIDE_DRAW }, { para = L.LOTTERY_FREE_GUIDE_NUMBERS },
					{ para = L.LOTTERY_GUIDE_DRAW_TEXT:format("4827", "27", Lt.Label(7), Lt.DezenasText(7)), icon = 7 },
					{ para = L.LOTTERY_GUIDE_KODO:format(Lt.Label(Lt.OUTCOMES)), icon = Lt.OUTCOMES },
					{ head = L.LOTTERY_GUIDE_PLACES }, { para = L.LOTTERY_FREE_GUIDE_PLACES },
					{ para = L.LOTTERY_PRACTICE_RECORD, soft = true },
				} },
			} }
	end
	local intro = Lt.Intro()
	local deal = {}
	for i, p in ipairs(intro.paragraphs) do deal[i] = { para = p } end
	local ex = Example()
	local m = { title = L.LOTTERY_GUIDE_TITLE, tabs = { L.LOTTERY_GUIDE_DEAL, L.LOTTERY_GUIDE_RULES, L.LOTTERY_GUIDE_PAYOUT }, example = ex }
	local kodo = Lt.OUTCOMES
	m.pages = {
		{ icons = { 1, 17, kodo }, center = deal },
		{ left = {
			{ head = L.LOTTERY_GUIDE_GOAL }, { para = L.LOTTERY_GUIDE_GOAL_TEXT },
			{ head = L.LOTTERY_GUIDE_DAY }, { step = 1, para = L.LOTTERY_GUIDE_STEP_1 }, { step = 2, para = L.LOTTERY_GUIDE_STEP_2 },
			{ step = 3, para = L.LOTTERY_GUIDE_STEP_3 }, { step = 4, para = L.LOTTERY_GUIDE_STEP_4 },
		}, right = {
			{ head = L.LOTTERY_GUIDE_DRAW },
			{ para = ex and L.LOTTERY_GUIDE_DRAW_TEXT:format(ex.milhar, ex.ending, Lt.Label(ex.beast), Lt.DezenasText(ex.beast)) or "",
				icon = ex and ex.beast },
			{ para = L.LOTTERY_GUIDE_KODO:format(Lt.Label(kodo)), icon = kodo, soft = true },
			{ head = L.LOTTERY_GUIDE_PLACES }, { para = L.LOTTERY_GUIDE_PLACES_TEXT },
		} },
		{ left = {
			{ head = L.LOTTERY_GUIDE_WHO }, { para = L.LOTTERY_GUIDE_WHO_TEXT },
			{ head = L.LOTTERY_GUIDE_UNCLAIMED }, { para = L.LOTTERY_GUIDE_UNCLAIMED_TEXT },
			{ head = L.LOTTERY_GUIDE_PREVIEW }, { para = L.LOTTERY_GUIDE_PREVIEW_TEXT },
		}, right = { { head = L.LOTTERY_GUIDE_EXAMPLE } } },
	}
	if ex then
		local right = m.pages[3].right
		local g = function(c) return Money(c, "g") end
		right[#right + 1] = { para = L.LOTTERY_GUIDE_EXAMPLE_TEXT:format(g(ex.pot), g(ex.yours), Lt.Label(ex.beast), g(ex.other), ex.milhar), icon = ex.beast }
		right[#right + 1] = { ledger = {
			{ L.LOTTERY_GUIDE_ROW_POT, g(ex.pot) },
			{ L.LOTTERY_GUIDE_ROW_ON:format(Lt.Label(ex.beast), g(ex.yours)), g(ex.onHead) },
			{ L.LOTTERY_GUIDE_ROW_REFUND, g(ex.refunds) },
			{ L.LOTTERY_GUIDE_ROW_PROFIT, g(ex.profit) },
			{ L.LOTTERY_GUIDE_ROW_FIRST, g(ex.first) },
			{ L.LOTTERY_GUIDE_ROW_FEE, "-" .. g(ex.fee), RED },
			{ L.LOTTERY_GUIDE_ROW_SHARE:format(ex.percent), g(ex.share) },
			{ L.LOTTERY_GUIDE_ROW_BACK, g(ex.back) },
			{ L.LOTTERY_GUIDE_ROW_GET, g(ex.get), GREEN, total = true },
			{ L.LOTTERY_GUIDE_ROW_CARRY, g(ex.carry), SOFT },
		} }
		right[#right + 1] = { para = L.LOTTERY_GUIDE_COPPER, soft = true }
	end
	return m
end

local guide
local guideModes = {}
-- One column of blocks from y down: its last y.
local function Column(page, blocks, x, w, y, iconArt)
	-- (rawget, as Window.lua reads its canvases: a field of the frame's own, never a method's name.)
	page.parts = rawget(page, "parts") or {}
	local function Keep(o) page.parts[#page.parts + 1] = o return o end
	for _, b in ipairs(blocks) do
		if b.head then
			local fs = Keep(Text(page, 18, INK, MORPHEUS, "LEFT"))
			fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
			fs:SetWidth(w)
			fs:SetText(b.head)
			y = y + 25
		elseif b.ledger then
			for _, row in ipairs(b.ledger) do
				if row.total then
					local t = Keep(page:CreateTexture(nil, "BORDER"))
					t:SetColorTexture(0.25, 0.13, 0.04, 0.4)
					t:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(y + 1))
					t:SetSize(w, 1)
					y = y + 4
				end
				local c = row[3] or INK
				local l = Keep(Text(page, 13, c, STANDARD_TEXT_FONT, "LEFT"))
				l:SetPoint("TOPLEFT", page, "TOPLEFT", x + 2, -y)
				l:SetWidth(w - 110)
				l:SetWordWrap(false)
				l:SetText(row[1])
				local a = Keep(Text(page, 13, c, STANDARD_TEXT_FONT, "RIGHT"))
				a:SetPoint("TOPLEFT", page, "TOPLEFT", x + w - 108, -y)
				a:SetWidth(106)
				a:SetWordWrap(false)
				a:SetText(row[2])
				y = y + 19
			end
			y = y + 10
		else
			local px, pw = x, w
			if b.step then
				local n = Keep(Text(page, 14, RED, MORPHEUS, "LEFT"))
				n:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
				n:SetText(b.step .. ".")
				px, pw = x + 20, w - 20
			end
			local beast = b.icon and Lot().Beast(b.icon)
			if beast then
				local t = Keep(page:CreateTexture(nil, "ARTWORK"))
				t:SetSize(30, 30)
				t:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
				t:SetTexture(iconArt and iconArt(b.icon) or beast.art)
				if beast.icon then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
				px, pw = x + 38, w - 38
			end
			local fs = Keep(Text(page, 13, b.soft and SOFT or INK, STANDARD_TEXT_FONT, "LEFT"))
			fs:SetPoint("TOPLEFT", page, "TOPLEFT", px, -y)
			fs:SetWidth(pw)
			fs:SetWordWrap(true)
			fs:SetJustifyV("TOP")
			if fs.SetSpacing then fs:SetSpacing(2) end
			fs:SetText(b.para)
			local h = fs.GetStringHeight and tonumber(fs:GetStringHeight()) or 0
			-- (a client that cannot measure it yet: a generous guess, 0.6 of the size a letter)
			if h < 13 then h = math.ceil(#b.para * 13 * 0.6 / pw) * 17 end
			h = math.max(h, beast and 30 or 0)
			fs:SetHeight(floor(h + 0.99))
			y = y + floor(h + 0.99) + (b.step and 6 or 10)
		end
	end
	return y
end

local function GuidePage(k)
	k = max(1, min(#guide.pages, floor(tonumber(k) or 1)))
	for i, pg in ipairs(guide.pages) do
		pg:SetShown(i == k)
		if guide.tabs[i].SetSelected then guide.tabs[i]:SetSelected(i == k) end
	end
	guide.page = k
end

local function BuildGuide()
	local m = ArenaUI.LotteryGuideModel()
	local mode = m.free and "free" or "permitted"
	if guideModes[mode] then guide = guideModes[mode] return guide end
	local f = Popup(m.free and "OlympusArenaLotteryFreeGuide" or "OlympusArenaLotteryGuide", GUIDE_W, GUIDE_H, HostWindow())
	guide = f
	guideModes[mode] = f
	f.model = m
	f.title = Text(f, 24, INK, MORPHEUS)
	f.title:SetPoint("TOP", 0, -18)
	f.title:SetText(m.title)
	f.tabs, f.pages = {}, {}
	local G = own.Games
	local tw, gap = 150, 8
	local tx = (GUIDE_W - #m.tabs * tw - (#m.tabs - 1) * gap) / 2
	local TOP = 104
	local need = 0
	for k, name in ipairs(m.tabs) do
		local tab
		if G and type(G.InkTab) == "function" then
			tab = G.InkTab(f, name, tw, function() GuidePage(k) end, 16) -- (the games' one tab)
		else
			tab = Button(f, name, tw, 24, function() GuidePage(k) end)
		end
		tab:SetPoint("TOPLEFT", f, "TOPLEFT", tx + (k - 1) * (tw + gap), -52)
		f.tabs[k] = tab
		local pg = CreateFrame("Frame", nil, f)
		pg:SetAllPoints()
		local spec, h = m.pages[k], TOP
		if spec.center then
			local y = TOP
			if spec.icons then
				pg.icons = {}
				for i, n in ipairs(spec.icons) do
					local b = Lot().Beast(n)
					local t = pg:CreateTexture(nil, "ARTWORK")
					t:SetSize(30, 30)
					t:SetPoint("TOPLEFT", pg, "TOPLEFT", GUIDE_W / 2 - 51 + (i - 1) * 36, -y)
					t:SetTexture(m.free and PracticeArt(n) or b.art)
					if b.icon then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
					pg.icons[i] = t
				end
				y = y + 42
			end
			h = Column(pg, spec.center, 60, GUIDE_W - 120, y, m.free and PracticeArt or nil)
		else
			h = math.max(Column(pg, spec.left or {}, 40, 280, TOP, m.free and PracticeArt or nil), Column(pg, spec.right or {}, 344, 296, TOP, m.free and PracticeArt or nil))
		end
		need = math.max(need, h)
		f.pages[k] = pg
	end
	-- (tall enough for its longest page, and Got it under it)
	f:SetHeight(math.max(GUIDE_H, math.ceil(need + 70)))
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(0.25, 0.13, 0.04, 0.3)
	rule:SetPoint("TOPLEFT", 32, -90); rule:SetPoint("TOPRIGHT", -32, -90); rule:SetHeight(1)
	f.ok = Button(f, L.LOTTERY_BOARD_GOT_IT, 140, 32, function() f:Hide() end)
	f.ok:SetPoint("BOTTOM", 0, 18)
	GuidePage(1)
	return f
end

-- How to play, on its page (1 The deal, 2 The rules, 3 The payout; the one it was left at), over
-- the board's window; again: put away.
function ArenaUI.LotteryHowToPlay(page, toggle)
	if guide and (guide.model.free == true) ~= (not Lot().Wagers()) then guide:Hide(); guide = nil end
	if not guide then BuildGuide() end
	if toggle and guide:IsShown() and not page then guide:Hide() return guide end
	guide.over = HostWindow()
	GuidePage(page or guide.page or 1)
	guide:Show()
	if guide.Raise then guide:Raise() end
	return guide
end
function ArenaUI.LotteryGuide() return guide end

-- The King's corner: who rolls, the draw time, the switch (the Roll button is the bar's).
local function Caller(parent)
	local c = CreateFrame("Frame", nil, parent)
	local bg = c:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.32, 0.2, 0.08, 0.14)
	Edge(c, BRONZE, 0.8, 1)
	c.title = Text(c, 13, INK, MORPHEUS)
	c.title:SetPoint("TOP", 0, -5)
	local function Schedule(t)
		ns.Arena.Do("lottery.schedule", t)
		Refresh()
	end
	c.roller = Button(c, "", 188, 24, function()
		local m = board and board.model and board.model.caller
		Schedule({ roller = m and m.roller == L.LOTTERY_BOARD_ROLLER_BANK and "king" or "bank" })
	end)
	c.roller:SetPoint("TOP", 0, -24)
	c.minus = Button(c, "-", 26, 24, function()
		local m = board.model.caller
		Schedule({ at = ((m.at or 0) - 15) % 1440 })
	end)
	c.minus:SetPoint("TOPLEFT", c.roller, "BOTTOMLEFT", 0, -3)
	c.plus = Button(c, "+", 26, 24, function()
		local m = board.model.caller
		Schedule({ at = ((m.at or 0) + 15) % 1440 })
	end)
	c.plus:SetPoint("TOPRIGHT", c.roller, "BOTTOMRIGHT", 0, -3)
	c.time = Text(c, 13, INK, MORPHEUS)
	c.time:SetPoint("LEFT", c.minus, "RIGHT", 4, 0); c.time:SetPoint("RIGHT", c.plus, "LEFT", -4, 0)
	c.switch = Button(c, "", 188, 24, function()
		local m = board.model.caller
		Schedule({ on = not m.isOn })
	end)
	c.switch:SetPoint("TOP", c.roller, "BOTTOM", 0, -30)
	return c
end

-- The games' bar's button height (Games.BAR.BUTTON_H, Bones' and the arena's).
local function BarButtonH()
	local G = own.Games
	return G and G.BAR and G.BAR.BUTTON_H or 32
end

-- Bet: the board's own button, laid on the games' bar's right (PlaceActions). Enter bets too, while
-- the mouse is on it (the same as its click): the keyboard is the board's only then, so the chat's
-- Enter works everywhere else and no bet happens by chance. Never with the gamepad UI, never in
-- combat (EnableKeyboard is protected there).
local function BetButton(parent)
	local b = Button(parent, L.LOTTERY_BOARD_BET, 120, BarButtonH(), Bet)
	local function Keys(on)
		if on and (ns.GamepadUI() or (InCombatLockdown and InCombatLockdown())) then on = false end
		if (b.keys == true) == on or type(b.EnableKeyboard) ~= "function" then return end
		if not pcall(b.EnableKeyboard, b, on) then return end
		b.keys = on
		if on and not pcall(b.SetPropagateKeyboardInput, b, true) then Keys(false) end
	end
	b:SetScript("OnEnter", function(self)
		Keys(true)
		Tip(self, { L.LOTTERY_BOARD_BET, L.LOTTERY_BOARD_ENTER })
	end)
	b:SetScript("OnLeave", function() Keys(false) Untip() end)
	b:SetScript("OnHide", function() Keys(false) end)
	b:SetScript("OnKeyDown", function(self, key)
		local enter = key == "ENTER" or key == "NUMPADENTER"
		if not pcall(self.SetPropagateKeyboardInput, self, not enter) then return Keys(false) end
		if enter then Bet() end
	end)
	return b
end
-- Roll: one prize a click, for the caller (or the bank when a draw is due there), where Bet is.
local function RollButton(parent)
	return Button(parent, L.LOTTERY_BOARD_ROLL:format(1), 188, BarButtonH(), function()
		local ok, why = ns.Arena.Do("lottery.draw")
		if not ok then state.note = Lot().WhyText(why) end
		Sound("spin")
		Refresh()
	end)
end

-- The counter under the cards (the lab's, above its bar): the pick and what happened to the last
-- bet on the left, the stake's steppers on the right. Plain ink on the parchment: the bar under it
-- is the games' one.
local function Counter(parent)
	local r = CreateFrame("Frame", nil, parent)
	r.line = r:CreateTexture(nil, "BORDER")
	r.line:SetColorTexture(0.25, 0.13, 0.04, 0.3)
	r.line:SetPoint("TOPLEFT"); r.line:SetPoint("TOPRIGHT"); r.line:SetHeight(1)
	r.pick = Text(r, 15, INK, MORPHEUS, "LEFT")
	r.pick:SetPoint("TOPLEFT", 4, -5)
	r.note = Text(r, 11, SOFT, STANDARD_TEXT_FONT, "LEFT")
	r.note:SetPoint("BOTTOMLEFT", 4, 3)
	r.preview = Text(r, 11, SOFT, STANDARD_TEXT_FONT, "LEFT")
	r.preview:SetPoint("BOTTOMLEFT", 4, 3)
	local function Move(fn)
		state.stake = Clamp(fn(Stake()))
		state.note = nil
		Refresh()
	end
	r.max = Button(r, L.LOTTERY_BOARD_MAX, 44, 24, function() Move(function() return Lot().MaxSilver() end) end)
	r.min = Button(r, L.LOTTERY_BOARD_MIN, 44, 24, function() Move(function() return Lot().MinSilver() end) end)
	r.min:SetPoint("RIGHT", r.max, "LEFT", -2, 0)
	r.plus = Button(r, "+", 26, 24, function() Move(function(s) return s + Step(s, true) end) end)
	r.plus:SetPoint("RIGHT", r.min, "LEFT", -6, 0)
	r.stake = Text(r, 15, INK, MORPHEUS)
	r.stake:SetWidth(84)
	r.stake:SetPoint("RIGHT", r.plus, "LEFT", -2, 0)
	r.minus = Button(r, "-", 26, 24, function() Move(function(s) return s - Step(s, false) end) end)
	r.minus:SetPoint("RIGHT", r.stake, "LEFT", -2, 0)
	r.pick:SetPoint("RIGHT", r.minus, "LEFT", -8, 0)
	r.note:SetPoint("RIGHT", r.minus, "LEFT", -8, 0)
	r.preview:SetPoint("RIGHT", r.minus, "LEFT", -8, 0)
	return r
end

-- The games' bar the board's actions go on: its own window's, or the arena window's while the board
-- is that window's pane (Games.Bar: Place lays them from its right edge, its gaps and height); none
-- where the games are not loaded.
local function HostBar()
	if board.ownBar then return board.ownBar end
	local win = ArenaUI.frame
	local bar = win and rawget(win, "bar")
	if type(bar) ~= "table" or type(bar.Place) ~= "function" then return nil end
	local p = board.frame:GetParent()
	while p do
		if p == win then return bar end
		p = p:GetParent()
	end
	return nil
end
-- Bet and Roll on the bar's right, the counter's steppers at the counter's right end; with no bar,
-- the actions at the counter's right end and the steppers left of them.
local function PlaceActions()
	local c, bar = board.counter, HostBar()
	board.hostBar = bar
	c.max:ClearAllPoints()
	if bar then
		-- (Only while the board shows: a reveal's timer may refresh it behind another pane, whose
		-- buttons that bar holds then.)
		if board.frame:IsVisible() then bar.Place(board.actions) end
		c.max:SetPoint("RIGHT", c, "RIGHT", -4, 0)
		return
	end
	local prev
	for _, b in ipairs(board.actions) do
		b:ClearAllPoints()
		if b:IsShown() then
			if prev then b:SetPoint("RIGHT", prev, "LEFT", -8, 0) else b:SetPoint("RIGHT", c, "RIGHT", -4, 0) end
			prev = b
		end
	end
	if prev then c.max:SetPoint("RIGHT", prev, "LEFT", -12, 0) else c.max:SetPoint("RIGHT", c, "RIGHT", -4, 0) end
end

local function Layout(w, h)
	if not board then return end
	w, h = max(560, floor(tonumber(w) or 0)), max(380, floor(tonumber(h) or 0))
	if board.size and board.size[1] == w and board.size[2] == h then return end
	board.size = { w, h }
	local top = HEADER + 18   -- (the rehearsal's band, when it shows, sits in the last 18)
	local gridW, gridH = w - SIDE - 30, h - top - BOTTOM - 10
	local cw, ch = floor((gridW - 4 * GAP) / 5), floor((gridH - 4 * GAP) / 5)
	for i, c in ipairs(board.cards) do
		local col, row = (i - 1) % 5, floor((i - 1) / 5)
		c:ClearAllPoints()
		c:SetSize(cw, ch)
		c:SetPoint("TOPLEFT", board.frame, "TOPLEFT", 12 + col * (cw + GAP), -(top + row * (ch + GAP)))
		local art = max(24, min(cw - 24, ch - 38))
		c.art:SetSize(art, art)
		c.name:ClearAllPoints()
		c.name:SetPoint("TOP", c.art, "BOTTOM", 0, -1)
		c.name:SetWidth(cw - 6)
	end
	board.banner:ClearAllPoints()
	board.banner:SetSize(gridW - 40, 96)
	board.banner:SetPoint("TOPLEFT", board.frame, "TOPLEFT", 32, -(top + floor(gridH / 2) - 48))
	local slipH = min(gridH, 250)
	board.slip:ClearAllPoints()
	board.slip:SetPoint("TOPRIGHT", board.frame, "TOPRIGHT", -12, -top)
	board.slip.Layout(SIDE, slipH)
	board.side:ClearAllPoints()
	board.side:SetPoint("TOPLEFT", board.slip, "BOTTOMLEFT", 0, -6)
	board.side:SetSize(SIDE, max(40, gridH - slipH - 6))
	board.caller:ClearAllPoints()
	board.caller:SetPoint("BOTTOMLEFT", board.side, "BOTTOMLEFT", 0, 0)
	board.caller:SetSize(SIDE, 110)
	board.counter:ClearAllPoints()
	board.counter:SetPoint("BOTTOMLEFT", board.frame, "BOTTOMLEFT", 12, 4)
	board.counter:SetPoint("BOTTOMRIGHT", board.frame, "BOTTOMRIGHT", -12, 4)
	board.counter:SetHeight(BOTTOM - 6)
end

---------------------------------------------------------------------------
-- The result card (Bones' card's pattern, the design): once the bank has settled a day with this
-- player's tickets, in front, the games' pop-up over the board's window: the verdict, the day, the
-- tickets, what was staked, refunded, won or lost to the copper, the wallet's balance, and the way
-- to the Wallet and to History. Once a day (the last day carded is kept).
---------------------------------------------------------------------------

local GREY = { 0.35, 0.33, 0.3 }
local VERDICT = { won = { "LOTTERY_CARD_WON_TITLE", GREEN }, lost = { "LOTTERY_CARD_LOST_TITLE", RED }, back = { "LOTTERY_CARD_BACK_TITLE", GREY } }

-- The card of a day as plain data, or nil: no tickets of this player, the five not declared, or a
-- ticket the bank has not paid yet (its payout unknown). day: Lottery.Day's view.
function ArenaUI.LotteryCardSpec(day)
	local Lt = Lot()
	if type(day) ~= "table" or not day.eid or day.live then return nil end
	local void = day.state == "void"
	if not void and not (type(day.prizes) == "table" and #day.prizes == Lt.PRIZES) then return nil end
	local mine = type(day.mine) == "table" and day.mine or {}
	if #mine == 0 then return nil end
	local drawn = {}
	for _, p in ipairs(day.prizes or {}) do
		local b = Lt.BeastOf(p)
		if b then drawn[b] = true end
	end
	local staked, paid, refunded, lost = 0, 0, 0, 0
	for _, t in ipairs(mine) do
		local s, payout = floor(tonumber(t.s) or 0), tonumber(t.payout)
		if void then payout = payout or s end
		if not payout then return nil end
		staked, paid = staked + s, paid + payout
		-- (A ticket on a drawn beast gets its stake back once, then its places' profit; any other
		-- loses its stake.)
		if void or drawn[t.o] then refunded = refunded + min(s, payout) else lost = lost + s end
	end
	local cur = day.cur or "g"
	local won, net = paid - refunded, paid - staked
	local spec = { eid = day.eid, cur = cur, staked = staked, paid = paid, refunded = refunded, won = won, lost = lost, net = net,
		verdict = net > 0 and "won" or (net == 0 and "back" or "lost"), rows = {}, buttons = {} }
	spec.title = L[VERDICT[spec.verdict][1]]
	spec.line = L.LOTTERY_CARD_LINE:format(L.LOTTERY_NAME, ArenaUI.LotteryWhen(day.drawAt or day.lockAt))
	local rows = spec.rows
	rows[#rows + 1] = { L.LOTTERY_CARD_TICKETS, tostring(#mine) }
	rows[#rows + 1] = { L.LOTTERY_CARD_STAKED, Money(staked, cur) }
	if refunded > 0 then rows[#rows + 1] = { L.LOTTERY_CARD_REFUNDED, Money(refunded, cur) } end
	if won > 0 then rows[#rows + 1] = { L.LOTTERY_CARD_WON, "+" .. Money(won, cur), GREEN } end
	if lost > 0 then rows[#rows + 1] = { L.LOTTERY_CARD_LOST, "-" .. Money(lost, cur), RED } end
	local W = ns.Wallet
	if WalletShown() and day.bank and type(W) == "table" and type(W.Statement) == "function" then
		local ok, st = pcall(W.Statement, day.bank)
		local side = ok and type(st) == "table" and (cur == "p" and st.p or st.g)
		if type(side) == "table" and tonumber(side.bal) then
			spec.balance = floor(tonumber(side.bal))
			rows[#rows + 1] = { L.LOTTERY_CARD_BALANCE, Money(spec.balance, cur) }
		end
	end
	if void then spec.note = L.LOTTERY_CARD_VOID
	elseif day.mode == "T" then spec.note = L.LOTTERY_CARD_REHEARSAL
	elseif cur == "p" then spec.note = L.LOTTERY_CARD_POINTS
	elseif won > 0 then spec.note = L.LOTTERY_CARD_FEE end
	local eid = day.eid
	if WalletShown() then spec.buttons[#spec.buttons + 1] = { L.LOTTERY_HISTORY_WALLET, function() ArenaUI.LotteryOpenWallet() end } end
	spec.buttons[#spec.buttons + 1] = { L.LOTTERY_PANE_HISTORY, function() ArenaUI.ShowPane("lottery.history", eid) end }
	spec.buttons[#spec.buttons + 1] = { L.LOTTERY_CARD_OK, nil }
	return spec
end

local card
local CARD_ROWS, ROW_H, ROWS_Y = 6, 22, 84
local function BuildCard()
	card = Popup("OlympusArenaLotteryResult", CARD_W, 300, HostWindow())
	card.verdict = Text(card, 28, GREEN, MORPHEUS)
	card.verdict:SetPoint("TOP", 0, -18)
	card.verdict:SetWidth(CARD_W - 40)
	card.verdict:SetWordWrap(false)
	card.line = Text(card, 13, SOFT, STANDARD_TEXT_FONT)
	card.line:SetPoint("TOP", 0, -56)
	card.line:SetWidth(CARD_W - 40)
	card.line:SetWordWrap(false)
	card.rows = {}
	for i = 1, CARD_ROWS do
		local l = Text(card, 13, INK, STANDARD_TEXT_FONT, "LEFT")
		l:SetPoint("TOPLEFT", card, "TOPLEFT", 30, -(ROWS_Y + (i - 1) * ROW_H))
		l:SetWidth(170)
		l:SetWordWrap(false)
		local r = Text(card, 13, INK, STANDARD_TEXT_FONT, "RIGHT")
		r:SetPoint("TOPRIGHT", card, "TOPRIGHT", -30, -(ROWS_Y + (i - 1) * ROW_H))
		r:SetWidth(150)
		r:SetWordWrap(false)
		card.rows[i] = { l = l, r = r }
	end
	card.note = Text(card, 12, SOFT, STANDARD_TEXT_FONT, "LEFT")
	card.note:SetWidth(CARD_W - 60)
	card.note:SetJustifyV("TOP")
	card.buttons = {}
	for i = 1, 3 do
		local b = Button(card, "", 100, 32, function(self)
			card:Hide()
			local fn = rawget(self, "fn")
			if fn then ns.SafeCall("lottery card", fn) end
		end)
		card.buttons[i] = b
	end
	return card
end

-- The card of a day, in front of the board (nil: no card for it, ArenaUI.LotteryCardSpec).
function ArenaUI.LotteryShowCard(day)
	local spec = ArenaUI.LotteryCardSpec(day)
	if not spec then return nil end
	if not card then BuildCard() end
	local vd = VERDICT[spec.verdict]
	card.verdict:SetText(spec.title)
	card.verdict:SetTextColor(vd[2][1], vd[2][2], vd[2][3])
	card.line:SetText(spec.line)
	for i, r in ipairs(card.rows) do
		local row = spec.rows[i]
		local c = row and row[3] or INK
		r.l:SetText(row and row[1] or ""); r.r:SetText(row and row[2] or "")
		r.l:SetTextColor(INK[1], INK[2], INK[3]); r.r:SetTextColor(c[1], c[2], c[3])
	end
	local y = ROWS_Y + #spec.rows * ROW_H + 8
	card.note:ClearAllPoints()
	card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 30, -y)
	card.note:SetText(spec.note or "")
	if spec.note then y = y + 34 end
	local n = #spec.buttons
	local x = (CARD_W - (n * 100 + (n - 1) * 10)) / 2
	for i, b in ipairs(card.buttons) do
		local def = spec.buttons[i]
		b:SetShown(def ~= nil)
		if def then
			b:SetText(def[1])
			b.fn = def[2]
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", card, "TOPLEFT", x + (i - 1) * 110, -(y + 10))
		end
	end
	card:SetHeight(y + 10 + 32 + 20)
	card.spec = spec
	card.over = HostWindow()
	card:Show()
	if card.Raise then card:Raise() end
	return card
end
function ArenaUI.LotteryCard() return card end

-- Once a day: the last day carded is remembered (a /reload shows it no more).
local function MaybeCard(slip)
	local day = slip and slip.day
	local eid = day and day.eid
	if not eid or state.carded == eid or not (board and board.frame:IsVisible()) then return end
	local Kit = ArenaUI.Kit
	if Kit and Kit.Recall("lottery:card") == eid then state.carded = eid return end
	if ArenaUI.LotteryShowCard(day) then
		state.carded = eid
		if Kit then Kit.Remember("lottery:card", eid) end
	end
end

---------------------------------------------------------------------------
-- The reveal: one prize at a time
---------------------------------------------------------------------------

local Continue -- (below)
-- The slip's day on the board now, when it is `eid`.
local function SlipOf(eid)
	local m = board and board.model
	return m and m.slip and m.slip.eid == eid and m.slip or nil
end
local function Land(eid, p)
	if not SlipOf(eid) then state.revealing = nil return end
	local r = board.slip.rows[p]
	r.spinning = false
	if r.spin and r.spin.Stop then r.spin:Stop() end
	state.revealed[eid] = p
	Refresh()
	if r.land and r.land.Play then r.land:Play() end
	Sound("land")
	ns.SafeCall("lottery next", C_Timer.After, NEXT, function() Continue(eid) end)
end
local function Spin(eid, p)
	local r = board.slip.rows[p]
	r.spinning = true
	r.art:Hide()
	r.label:SetText("")
	r.number:SetText(("%04d"):format(math.random(0, 9999)))
	if r.spin and r.spin.Play then r.spin:Play() end
	Sound("spin")
	C_Timer.After(SPIN, function() Land(eid, p) end)
end
-- The next prize known and not shown yet spins; after the fifth, the banner.
Continue = function(eid)
	local slip = SlipOf(eid)
	if not slip then state.revealing = nil return end
	local known = slip.day.prizes and #slip.day.prizes or 0
	local shown = state.revealed[eid] or 0
	if shown < known then
		state.revealing = eid
		return Spin(eid, shown + 1)
	end
	state.revealing = nil
	local b = board.model.banner
	if shown >= Lot().PRIZES and b and state.bannerHidden ~= eid then
		Sound(b.won and "win" or ((slip.day.winners or 0) == 0 and "rollover" or (b.mine and "lose" or "land")))
		board.banner:Show()
		if board.banner.pop and board.banner.pop.Play then board.banner.pop:Play() end
	end
	Refresh()
end

---------------------------------------------------------------------------
-- Drawing the model
---------------------------------------------------------------------------

local ticker
local function StopTicker()
	if ticker and ticker.Cancel then ticker:Cancel() end
	ticker = nil
end
local function Tick()
	if not board or not board.frame:IsShown() then return StopTicker() end
	local m = board.model
	if not m or m.state ~= "open" then return StopTicker() end
	Refresh()
end

Refresh = function()
	if not board then return end
	local Lt = Lot()
	local m = ArenaUI.LotteryModel()
	local was = board.model
	board.model = m
	local eid = m.slip.eid
	board.title:SetText(m.title)
	board.line:SetText(m.line)
	board.rules:SetText(m.instructions)
	if m.band then board.band.text:SetText(m.band) board.band:Show() else board.band:Hide() end
	-- Another draw on the slip: its reveal starts from its first prize (an old result shows whole).
	if eid and (not was or was.slip.eid ~= eid) then
		local day = m.slip.day
		if day.prizes and not day.live and not m.slip.fresh then state.revealed[eid] = #day.prizes end
		board.banner:Hide()
	end
	for i, c in ipairs(board.cards) do
		local cm = m.cards[i]
		c.model = cm
		c.num:SetText(cm.num)
		c.name:SetText(cm.name)
		c.dez:SetText(cm.dezenas)
		c.badge:SetText(cm.tickets)
		c.pill:SetShown(cm.tickets ~= "")
		if cm.tickets ~= "" then c.pill:SetWidth(max(28, (c.badge:GetStringWidth() or 36) + 8)) end
		c.art:SetTexture(cm.art)
		if cm.icon then c.art:SetTexCoord(0.08, 0.92, 0.08, 0.92) else c.art:SetTexCoord(0, 1, 0, 1) end
		c.glow:SetShown(cm.picked)
		c.coin:SetShown(cm.mine ~= nil)
		local lit, revealed = false, state.revealed[eid] or 0
		for _, position in ipairs(cm.positions or {}) do
			if position <= revealed then lit = true break end
		end
		for _, t in ipairs(c.gold) do t:SetShown(lit) end
		c.shine:SetShown(lit)
		if lit and c.pulse and c.pulse.Play and not c.lit then c.pulse:Play() end
		if not lit and c.pulse and c.pulse.Stop then c.pulse:Stop() end
		c.lit = lit
	end
	local shown = eid and state.revealed[eid] or 0
	board.slip.Fill(m.rows, shown, m.slip.title, m.slip.note)
	if eid and state.revealing ~= eid and (m.slip.day.prizes and #m.slip.day.prizes or 0) > shown then Continue(eid) end
	if m.banner then
		board.banner.title:SetText(m.banner.title)
		board.banner.sub:SetText(m.banner.number .. "  ·  " .. m.banner.sub)
		board.banner.won:SetText(m.banner.won or "")
		board.banner.art:SetTexture(m.banner.art)
		if m.banner.icon then board.banner.art:SetTexCoord(0.08, 0.92, 0.08, 0.92) else board.banner.art:SetTexCoord(0, 1, 0, 1) end
	end
	-- (Shown once all five landed; a click puts it away for that draw.)
	board.banner:SetShown(m.banner ~= nil and shown >= Lt.PRIZES and not state.revealing and state.bannerHidden ~= eid)
	-- The side: this player's tickets.
	local lines = #m.mine > 0 and m.mine or { L.LOTTERY_BOARD_NO_TICKETS }
	board.side.title:SetText(L.LOTTERY_BOARD_MINE)
	-- (The caller never bets on it: his corner takes the place of the tickets.)
	board.side:SetShown(not (m.caller and not m.caller.bank))
	board.side.text:SetText(table.concat(lines, "\n"))
	-- The King's corner (the bank's, when a draw is due there, is its Roll alone).
	local c = board.caller
	local king = m.caller ~= nil and not m.caller.bank
	if king then
		c.title:SetText(L.LOTTERY_BOARD_CALLER)
		c.roller:SetText(m.caller.roller)
		c.time:SetText(m.caller.time)
		c.switch:SetText(m.caller.on)
	end
	c:SetShown(king)
	-- The bar's actions: Roll for the caller and the bank, Bet for everyone else.
	board.roll:SetShown(m.caller ~= nil)
	board.bet:SetShown(m.caller == nil)
	if m.caller then
		ArenaUI.Kit.SetButton(board.roll, m.caller.roll)
		Enable(board.roll, m.caller.canRoll)
	end
	Enable(board.bet, m.caller == nil and m.bet.can)
	PlaceActions()
	-- The countdown ticks while it shows.
	if m.state == "open" and board.frame:IsShown() and not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(1, function() ns.SafeCall("lottery clock", Tick) end)
	elseif m.state ~= "open" then
		StopTicker()
	end
	-- A due draw: the roll lines are read here too (a witness's reveal before the result).
	if m.state == "closed" or m.state == "drawing" then Lt.WatchDraw(true) end
	-- The result card, once all five landed on a settled day of this player's tickets.
	if m.slip.title ~= L.LOTTERY_BOARD_WAITING and shown >= Lt.PRIZES and not state.revealing then MaybeCard(m.slip) end
	-- The counter (the caller and the bank don't bet: it says so).
	local r = board.counter
	local bets = m.caller == nil
	for _, part in ipairs({ r.minus, r.plus, r.min, r.max, r.stake }) do part:SetShown(bets) end
	-- (The gold balance is the bar's coin; a points or chips day says its own here.)
	board.side.wallet:SetText(WalletShown() and bets and m.day.cur ~= "g" and m.bet.wallet or "")
	if not bets then
		r.pick:SetText(Lt.WhyText("caller"))
		r.note:SetText(state.note or "")
		r.preview:SetText("")
		return
	end
	r.pick:SetText(m.bet.pick)
	r.stake:SetText(m.bet.stake)
	-- (Under the pick: what happened to the last bet, or why not, else what this one would return.)
	local note = m.bet.note or (state.pick and m.bet.why) or nil
	r.note:SetText(note or "")
	r.preview:SetText(note and "" or (m.bet.preview or ""))
end
ArenaUI.LotteryRefresh = function() return Refresh() end

local function OnShow()
	Refresh()
	-- (The first time: How to play by itself, on The deal.)
	if Lot().FirstUse() then ArenaUI.LotteryHowToPlay(1) end
end
local function OnHide()
	StopTicker()
	Lot().WatchDraw(false)
	if guide and guide:IsShown() then guide:Hide() end
	if card and card:IsShown() then card:Hide() end
end

-- The board inside `parent` (the betting window's Lottery section, or the board's own window).
local function Build(parent)
	if board then
		board.frame:SetParent(parent)
		board.frame:ClearAllPoints()
		board.frame:SetAllPoints(parent)
		board.ownBar = rawget(parent, "lotteryBar")
		board.help:SetShown(board.ownBar == nil)
		Layout(parent:GetWidth(), parent:GetHeight())
		return board.frame
	end
	local f = CreateFrame("Frame", "OlympusArenaLotteryBoard", parent)
	f:SetAllPoints(parent)
	board = { frame = f, cards = {} }
	Parchment(f)
	board.title = Text(f, 22, INK, MORPHEUS, "LEFT")
	board.title:SetPoint("TOPLEFT", 14, -8)
	board.line = Text(f, 13, SOFT, STANDARD_TEXT_FONT, "LEFT")
	board.line:SetPoint("TOPLEFT", 15, -31)
	board.rules = Text(f, 11, SOFT, STANDARD_TEXT_FONT, "LEFT")
	board.rules:SetPoint("TOPLEFT", 15, -49)
	board.rules:SetPoint("RIGHT", f, "RIGHT", -15, 0)
	board.rules:SetWordWrap(false)
	-- (How to play: the bar's, in the board's own window; up here while the arena window's bar
	-- opens the arena's guide.)
	board.ownBar = rawget(parent, "lotteryBar")
	board.help = Button(f, L.LOTTERY_BOARD_HOW, 104, 24, function() ArenaUI.LotteryHowToPlay(nil, true) end)
	board.help:SetPoint("TOPRIGHT", -36, -10)
	board.help:SetShown(board.ownBar == nil)
	-- Full-board panes hide the window's left list (where its ordinary pane tabs live), so these
	-- two compact routes keep History and Practice reachable without shrinking the 5x5 table.
	board.history = Button(f, L.LOTTERY_PANE_HISTORY, 86, 24, function() ArenaUI.ShowPane("lottery.history") end)
	board.history:SetPoint("RIGHT", board.help, "LEFT", -4, 0)
	board.practice = Button(f, L.LOTTERY_PANE_PRACTICE, 86, 24, function() ArenaUI.ShowPane("lottery.practice") end)
	board.practice:SetPoint("RIGHT", board.history, "LEFT", -4, 0)
	board.band = CreateFrame("Frame", nil, f)
	board.band:SetPoint("TOPLEFT", 8, -HEADER + 4); board.band:SetPoint("TOPRIGHT", -8, -HEADER + 4)
	board.band:SetHeight(16)
	local bb = board.band:CreateTexture(nil, "BACKGROUND")
	bb:SetAllPoints()
	bb:SetColorTexture(RED[1], RED[2], RED[3], 0.85)
	board.band.text = Text(board.band, 11, LIGHT, STANDARD_TEXT_FONT)
	board.band.text:SetPoint("CENTER")
	board.band:Hide()
	for i = 1, 25 do board.cards[i] = Card(f, i) end
	board.slip = ArenaUI.LotterySlip(f)
	board.side = CreateFrame("Frame", nil, f)
	board.side.wallet = Text(board.side, 13, INK, MORPHEUS, "LEFT")
	board.side.wallet:SetPoint("TOPLEFT", 4, -2)
	board.side.title = Text(board.side, 13, INK, MORPHEUS, "LEFT")
	board.side.title:SetPoint("TOPLEFT", 4, -24)
	board.side.text = Text(board.side, 12, INK, STANDARD_TEXT_FONT, "LEFT")
	board.side.text:SetPoint("TOPLEFT", 6, -42)
	board.side.text:SetWidth(SIDE - 10)
	board.side.text:SetJustifyV("TOP")
	board.caller = Caller(f)
	board.banner = Banner(f)
	board.counter = Counter(f)
	board.bet, board.roll = BetButton(f), RollButton(f)
	board.actions = { board.bet, board.roll }   -- (the bar's right, from its edge)
	f:SetScript("OnShow", OnShow)
	f:SetScript("OnHide", OnHide)
	f:SetScript("OnSizeChanged", function(self, w, h) Layout(w, h) Refresh() end)
	Layout(parent:GetWidth(), parent:GetHeight())
	Refresh()
	if f:IsShown() then OnShow() end
	return f
end
ArenaUI.LotteryBuild = Build
function ArenaUI.LotteryBoard() return board end

---------------------------------------------------------------------------
-- History: today's real tickets first, then the real prior days known here
---------------------------------------------------------------------------

local function HistoryWhen(at)
	at = tonumber(at)
	if not at then return "?" end
	local lottery = Lot()
	if type(date) == "function" then
		-- `date` otherwise uses the computer's timezone, which can put a realm draw on a
		-- different day for a travelling player. Shift the epoch by the realm offset and format
		-- it through UTC so History agrees with the live board's realm clock.
		-- RealmOffset compares the realm's *current* clock with the current epoch. Passing this
		-- historical draw epoch would fold the draw's age into the timezone offset.
		local offset = type(lottery.RealmOffset) == "function" and lottery.RealmOffset() or 0
		local ok, value = pcall(date, "!%d %b %H:%M", at + math.floor(tonumber(offset) or 0) * 60)
		if ok and type(value) == "string" and value ~= "" then return value end
	end
	return lottery.ClockText(at)
end
ArenaUI.LotteryWhen = HistoryWhen

local function TicketView(day, ticket)
	local payout = tonumber(ticket.payout)
	local status
	if payout then
		status = payout > 0 and L.LOTTERY_HISTORY_PAID:format(Money(payout, day.cur)) or L.LOTTERY_HISTORY_LOST
	elseif ticket.state == "lost" then
		status = L.LOTTERY_HISTORY_LOST
	elseif ticket.state == "settled" or day.state == "settled" or day.state == "void"
		or (day.prizes and #day.prizes == Lot().PRIZES) then
		status = L.LOTTERY_HISTORY_PENDING
	else
		status = day.state == "open" and L.LOTTERY_HISTORY_OPEN or L.LOTTERY_HISTORY_WAITING
	end
	return { beast = ticket.o, label = Lot().Label(ticket.o), stake = tonumber(ticket.s) or 0,
		payout = payout, state = ticket.state, status = status }
end

local function HistoryDay(day)
	local out = { eid = day.eid, drawAt = day.drawAt or day.lockAt, state = day.state, cur = day.cur or "g",
		prizes = {}, tickets = {}, myPayout = tonumber(day.myPayout) }
	for i, prize in ipairs(day.prizes or {}) do out.prizes[i] = prize end
	for _, ticket in ipairs(day.mine or {}) do out.tickets[#out.tickets + 1] = TicketView(day, ticket) end
	out.when = HistoryWhen(out.drawAt)
	out.result = #out.prizes == Lot().PRIZES and Lot().PrizesText(out.prizes) or nil
	return out
end

-- Plain data for the pane and regressions. It intentionally reads the same Today/Days/Day view
-- models as the live board. The caller's bounded History is only a fallback after its old market
-- has left the public registry; no history is invented and an ordinary client sees only days it knows.
function ArenaUI.LotteryHistoryModel()
	local Lt = Lot()
	local current = Lt.Today()
	local out = { today = HistoryDay(current), prior = {}, rows = {} }
	out.today.current = true
	for _, ticket in ipairs(out.today.tickets) do
		out.rows[#out.rows + 1] = { kind = "today", eid = out.today.eid, ticket = ticket }
	end
	local candidates, byId = {}, {}
	for _, item in ipairs(Lt.Days()) do
		if item.eid and item.eid ~= out.today.eid and not byId[item.eid] then
			local candidate = { eid = item.eid, at = tonumber(item.lockAt) or 0 }
			byId[item.eid] = candidate
			candidates[#candidates + 1] = candidate
		end
	end
	local okHistory, saved = pcall(Lt.History)
	for _, item in ipairs(okHistory and type(saved) == "table" and saved or {}) do
		if type(item) == "table" and item.eid and item.eid ~= out.today.eid then
			local candidate = byId[item.eid]
			if candidate then
				candidate.saved = item
				if candidate.at == 0 then candidate.at = tonumber(item.lockAt) or 0 end
			else
				candidate = { eid = item.eid, at = tonumber(item.lockAt) or 0, saved = item }
				byId[item.eid] = candidate
				candidates[#candidates + 1] = candidate
			end
		end
	end
	table.sort(candidates, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.eid > b.eid end)
	for _, item in ipairs(candidates) do
		local ok, day = pcall(Lt.Day, item.eid)
		if not ok or type(day) ~= "table" or day.eid ~= item.eid then
			local savedDay = item.saved
			day = savedDay and { eid = savedDay.eid, drawAt = savedDay.lockAt, state = savedDay.void and "void" or "settled",
				cur = savedDay.cur, prizes = savedDay.prizes, mine = {} } or nil
		end
		if day then
			local h = HistoryDay(day)
			out.prior[#out.prior + 1] = h
			out.rows[#out.rows + 1] = { kind = "prior", eid = item.eid, day = h }
		end
	end
	return out
end

local function HistoryFind(model, eid)
	if eid and model.today.eid == eid then return model.today end
	for _, day in ipairs(model.prior) do if day.eid == eid then return day end end
	return model.today.eid and model.today or model.prior[1]
end

local function HistoryLines(st)
	local m = ArenaUI.LotteryHistoryModel()
	local lines = { { header = true, text = L.LOTTERY_HISTORY_TODAY } }
	if #m.today.tickets == 0 then lines[#lines + 1] = { text = L.LOTTERY_HISTORY_NONE_TODAY, indent = 1 } end
	for _, ticket in ipairs(m.today.tickets) do
		local eid = m.today.eid
		lines[#lines + 1] = { text = L.LOTTERY_HISTORY_TICKET:format(ticket.label, Money(ticket.stake, m.today.cur)),
			right = ticket.status, indent = 1, onClick = eid and function() ArenaUI.Select("lottery.history", eid) end or nil }
	end
	lines[#lines + 1] = { header = true, text = L.LOTTERY_HISTORY_PREVIOUS }
	if #m.prior == 0 then lines[#lines + 1] = { text = L.LOTTERY_HISTORY_NONE, indent = 1 } end
	for _, day in ipairs(m.prior) do
		local eid = day.eid
		local right = day.result or (day.state == "open" and L.LOTTERY_HISTORY_OPEN or L.LOTTERY_HISTORY_WAITING)
		lines[#lines + 1] = { text = L.LOTTERY_HISTORY_DRAW:format(day.when), right = right, indent = 1,
			onClick = function() ArenaUI.Select("lottery.history", eid) end }
	end
	return lines
end

local function HistoryDetail(canvas, st)
	if not rawget(canvas, "historyTitle") then
		canvas.historyTitle = ArenaUI.Kit.Text(canvas, "title", "LEFT")
		canvas.historyTitle:SetPoint("TOPLEFT", 12, -12)
		canvas.historyText = ArenaUI.Kit.Text(canvas, nil, "LEFT")
		canvas.historyText:SetPoint("TOPLEFT", canvas.historyTitle, "BOTTOMLEFT", 0, -12)
		canvas.historyText:SetWidth(530)
		canvas.historyText:SetJustifyV("TOP")
		canvas.historyText:SetSpacing(4)
	end
	local model = ArenaUI.LotteryHistoryModel()
	local day = HistoryFind(model, st.sel)
	if not day then
		canvas.historyTitle:SetText(L.LOTTERY_PANE_HISTORY)
		canvas.historyText:SetText(L.LOTTERY_HISTORY_NONE)
		return
	end
	canvas.historyTitle:SetText(day.current and L.LOTTERY_HISTORY_TODAY or L.LOTTERY_HISTORY_DRAW:format(day.when))
	local lines = { day.result and L.LOTTERY_HISTORY_RESULTS:format(day.result) or L.LOTTERY_HISTORY_NO_RESULTS }
	for _, ticket in ipairs(day.tickets) do
		lines[#lines + 1] = L.LOTTERY_HISTORY_TICKET:format(ticket.label, Money(ticket.stake, day.cur)) .. " · " .. ticket.status
	end
	if #day.tickets == 0 then
		lines[#lines + 1] = day.current and L.LOTTERY_HISTORY_NONE_TODAY or L.LOTTERY_HISTORY_NO_TICKETS
	end
	canvas.historyText:SetText(table.concat(lines, "\n\n"))
end

-- One route to the canonical Wallet. There is no Lottery-local balance or transaction log.
function ArenaUI.LotteryOpenWallet()
	if not WalletShown() then return false end
	if not (ns.Treasury and type(ns.Treasury.OpenMoney) == "function") then return false end
	ns.Treasury.OpenMoney()
	return true
end

---------------------------------------------------------------------------
-- Local interactive practice: generated only after the player makes a choice
---------------------------------------------------------------------------

local function PracticeRefresh()
	if practiceWindow and practiceWindow:IsShown() and RefreshPracticeWindow then RefreshPracticeWindow() end
	if ArenaUI.Refresh then ArenaUI.Refresh() end
end

function ArenaUI.LotteryPracticeReset()
	if StopPracticeReveal then StopPracticeReveal() end
	practice.pick, practice.prizes = nil, nil
	PracticeRefresh()
	return true
end

function ArenaUI.LotteryPracticePick(beast)
	beast = tonumber(beast)
	if not beast or beast ~= floor(beast) or not Lot().Beast(beast) then return false, "pick" end
	if StopPracticeReveal then StopPracticeReveal() end
	practice.pick, practice.prizes = beast, nil
	PracticeRefresh()
	return true
end

-- (1.1.6: a practice ticket is free: there is no stake to choose. Kept so a caller from before
-- still works: the amount is ignored.)
function ArenaUI.LotteryPracticeStake()
	return true
end

function ArenaUI.LotteryPracticeModel()
	local Lt = Lot()
	local m = { pick = practice.pick, free = true, prizes = {}, rows = {}, positions = {}, localOnly = true,
		instructions = L.LOTTERY_PRACTICE_INTRO, warning = L.LOTTERY_PRACTICE_LOCAL, future = L.LOTTERY_PRACTICE_FUTURE,
		compliance = type(Lt.Wagers) == "function" and not Lt.Wagers() and L.COMPLIANCE_LOTTERY_PRACTICE or nil }
	if practice.pick then m.label = Lt.Label(practice.pick) end
	for i, prize in ipairs(practice.prizes or {}) do
		local beast = Lt.BeastOf(prize)
		m.prizes[i] = prize
		m.rows[i] = { place = L["LOTTERY_PRIZE_" .. i], number = Lt.Text(prize), beast = beast,
			label = Lt.Label(beast), hit = beast == practice.pick }
		if beast == practice.pick then m.positions[#m.positions + 1] = L["LOTTERY_PRIZE_" .. i] end
	end
	if #m.prizes == Lt.PRIZES then
		m.result = Lt.PrizesText(m.prizes)
		m.outcome = #m.positions > 0 and L.LOTTERY_PRACTICE_HIT:format(table.concat(m.positions, ", ")) or L.LOTTERY_PRACTICE_MISS
	end
	return m
end

-- `rolls` is accepted by the offline regression harness; the UI passes none and generates all
-- five numbers only here, after a pick. Neither path calls Arena.Do, Markets, Wallet or ns.db; the
-- draw goes into the player's games (the games' ledger, ArenaLedger.Played: his own list, and the
-- auditors heard lately, by whisper).
function ArenaUI.LotteryPracticeDraw(rolls)
	if not practice.pick then return false, "pick" end
	if rolls ~= nil and (type(rolls) ~= "table" or #rolls ~= Lot().PRIZES) then return false, "draw" end
	local prizes = {}
	for i = 1, Lot().PRIZES do
		local value = rolls and rolls[i] or math.random(0, 9999)
		value = Lot().Milhar(value)
		if value == nil then return false, "draw" end
		prizes[i] = value
	end
	practice.prizes = prizes
	if StartPracticeReveal and practiceWindow and practiceWindow:IsShown() then StartPracticeReveal()
	elseif StopPracticeReveal then StopPracticeReveal() end
	local hits, numbers = 0, {}
	for i, prize in ipairs(prizes) do
		if Lot().BeastOf(prize) == practice.pick then hits = hits + 1 end
		numbers[i] = ("%04d"):format(prize)
	end
	local Lg = ns.ArenaLedger
	if type(Lg) == "table" and type(Lg.Played) == "function" and type(Lg.SoloId) == "function" then
		local id = Lg.SoloId()
		if id then
			ns.SafeCall("lottery practice ledger", Lg.Played, "T", { id = id, g = "o", t = ns.Arena.Now(), dur = 0, p1 = ns.me,
				w = hits > 0 and "1" or "2", s1 = hits, s2 = practice.pick, how = "d", x = table.concat(numbers, ".") })
		end
	end
	PracticeRefresh()
	return ArenaUI.LotteryPracticeModel()
end

local function PracticeLines()
	local m = ArenaUI.LotteryPracticeModel()
	local lines = { { header = true, text = L.LOTTERY_PRACTICE_PICK } }
	for i = 1, Lot().OUTCOMES do
		local n = i
		local selected = m.pick == i and "> " or ""
		lines[#lines + 1] = { text = selected .. Lot().Label(i), right = Lot().DezenasText(i), indent = 1,
			onClick = function() ArenaUI.LotteryPracticePick(n) ArenaUI.Select("lottery.practice", n) end }
	end
	return lines
end

local function PracticeDetail(canvas)
	if not rawget(canvas, "practiceTitle") then
		canvas.practiceTitle = ArenaUI.Kit.Text(canvas, "title", "LEFT")
		canvas.practiceTitle:SetPoint("TOPLEFT", 12, -12)
		canvas.practiceText = ArenaUI.Kit.Text(canvas, nil, "LEFT")
		canvas.practiceText:SetPoint("TOPLEFT", canvas.practiceTitle, "BOTTOMLEFT", 0, -12)
		canvas.practiceText:SetWidth(530)
		canvas.practiceText:SetJustifyV("TOP")
		canvas.practiceText:SetSpacing(4)
	end
	local m = ArenaUI.LotteryPracticeModel()
	canvas.practiceTitle:SetText(m.result and L.LOTTERY_PRACTICE_RESULT or L.LOTTERY_PANE_PRACTICE)
	local lines = { m.instructions, "", m.label and L.LOTTERY_PRACTICE_CHOSEN:format(m.label) or L.LOTTERY_PRACTICE_PICK,
		L.LOTTERY_PRACTICE_FREE }
	if m.result then
		lines[#lines + 1] = ""
		lines[#lines + 1] = L.LOTTERY_PRACTICE_RESULTS:format(m.result)
		for _, row in ipairs(m.rows) do lines[#lines + 1] = row.place .. "  " .. row.number .. "  " .. row.label end
		lines[#lines + 1] = ""
		lines[#lines + 1] = m.outcome
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = m.warning
	if m.compliance then lines[#lines + 1] = m.compliance end
	if m.future then lines[#lines + 1] = ""; lines[#lines + 1] = m.future end
	canvas.practiceText:SetText(table.concat(lines, "\n"))
end

-- The familiar animal cards, using the game's pet and mount icons. This is only presentation:
-- the free ticket and its five rolls stay in the production practice model above.
local PRACTICE_ICONS = {
	"Ability_Mount_MechaStrider", "Ability_Mount_Gryphon_01", "Ability_Hunter_Pet_Turtle", "Ability_Hunter_Pet_Bat",
	"Ability_Hunter_Pet_Wolf", "Ability_Hunter_Pet_Raptor", "Spell_Nature_Polymorph", "Ability_Hunter_Pet_Spider",
	"Ability_Hunter_CobraStrikes", "INV_Misc_Fish_36", "Ability_Mount_RidingHorse", "Ability_Mount_Drake_Red",
	"INV_PetRaven2", "Ability_Mount_BlackPanther", "Ability_Hunter_Pet_Crocolisk", "INV_Mount_AllianceLionG",
	"INV_Misc_Head_Murloc_01", "Ability_Hunter_Pet_Boar", "Ability_Hunter_Pet_Owl", "Spell_Shadow_SummonFelHunter",
	"Spell_Priest_VoidTendrils", "Ability_Mount_JungleTiger", "Ability_Hunter_Pet_Bear", "Achievement_WorldEvent_Reindeer",
	"Ability_Mount_Kodo_01",
}
local PRACTICE_W, PRACTICE_H = 816, 734
-- Bicho's original result geometry: five slip rows left, the head's large card right.
local PRY, PROW0, PROWH, PRW, PIX, PICON = 122, 182, 58, 404, 226, 44
local PHX, PHW, PHH = 441, 354, 346
local practiceSpinHandle
local function StopPracticeSound()
	local handle = practiceSpinHandle; practiceSpinHandle = nil
	if handle and type(StopSound) == "function" then pcall(StopSound, handle, 120) end
end
local function PracticeResultEdge(parent, color)
	color = color or BRONZE
	-- Original Bicho card border; clients without BackdropTemplate keep the carved fallback.
	local ok, edge = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
	if ok and edge and edge.SetBackdrop then
		edge:SetAllPoints(); edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		edge:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		edge:SetFrameLevel(parent:GetFrameLevel() + 1)
	else Edge(parent, color, 0.6, 1) end
end
PracticeArt = function(n) return "Interface\\Icons\\" .. (PRACTICE_ICONS[n] or "INV_Misc_QuestionMark") end
-- The original table's quest-item border, cut so its corners keep their shape.
local function PracticeMark(c, on)
	if on and not rawget(c, "mark") then
		local mark = CreateFrame("Frame", nil, c)
		mark:SetAllPoints(); mark:SetFrameLevel(c:GetFrameLevel() + 3)
		local xs, ys = { { 0, 16 }, { 16, 118 }, { 134, 16 } }, { { 0, 16 }, { 16, 62 }, { 78, 16 } }
		local cut = { { 0, 16 }, { 16, 48 }, { 48, 64 } }
		mark.parts = {}
		for i = 1, 3 do
			for j = 1, 3 do
				if i ~= 2 or j ~= 2 then
					local t = mark:CreateTexture(nil, "OVERLAY")
					t:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBorder")
					t:SetTexCoord(cut[i][1] / 64, cut[i][2] / 64, cut[j][1] / 64, cut[j][2] / 64)
					t:SetPoint("TOPLEFT", xs[i][1], -ys[j][1]); t:SetSize(xs[i][2], ys[j][2])
					mark.parts[#mark.parts + 1] = t
				end
			end
		end
		c.mark = mark
	end
	if rawget(c, "mark") then c.mark:SetShown(on) end
	c.wash:SetShown(on)
end
RefreshPracticeWindow = function()
	local f = practiceWindow
	if not f then return end
	local m = ArenaUI.LotteryPracticeModel()
	local done = #m.rows == Lot().PRIZES
	f.grid:SetShown(not done); f.result:SetShown(done)
	f.future:SetShown(not done) -- (its strip is the cards' bottom margin; the result fills it)
	f.note:SetText(m.compliance or L.LOTTERY_PRACTICE_FREE)
	f.pick:SetText(m.label and L.LOTTERY_PRACTICE_CHOSEN:format(m.label) or L.LOTTERY_BOARD_PICK)
	for i, c in ipairs(f.cards) do
		PracticeMark(c, m.pick == i)
	end
	for i, row in ipairs(m.rows) do
		local r = f.prizes[i]
		local shown = not practice.revealing or i <= (practice.shown or 0)
		if shown then
			r.number:SetText(row.number)
			for d = 1, 4 do
				r.digit[d]:SetText(row.number:sub(d, d)); r.digit[d]:SetTextColor(unpack(d >= 3 and RED or INK))
				r.flash[d]:Hide()
			end
			r.art:SetTexture(PracticeArt(row.beast)); r.art:Show(); r.rim:Show()
			r.name:SetText(row.label)
			r.group:SetText(Lot().DezenasText(row.beast))
			r.band:SetShown(i == 1); r.mark:SetShown(i == 1)
		elseif i ~= practice.active then
			r.number:SetText("----")
			for d = 1, 4 do r.digit[d]:SetText("-"); r.flash[d]:Hide() end
			r.art:Hide(); r.rim:Hide(); r.name:SetText(""); r.group:SetText(""); r.band:Hide(); r.mark:Hide()
		end
	end
	local head = f.head
	local headShown = done and (not practice.revealing or practice.headShown)
	head.content:SetShown(headShown)
	if headShown then
		local row = m.rows[1]
		head.art:SetTexture(PracticeArt(row.beast)); head.name:SetText(row.label)
		head.num:SetText(("%02d"):format(row.beast)); head.number:SetText(row.number)
		head.group:SetText(Lot().DezenasText(row.beast))
	end
	f.outcome:SetText(not practice.revealing and (m.outcome or "") or "")
	f.draw:SetText(done and L.LOTTERY_PRACTICE_AGAIN or L.LOTTERY_PRACTICE_DRAW)
	if m.pick and not practice.revealing then f.draw:Enable() else f.draw:Disable() end
end

-- Restore Bicho.lua's original four-tile odometer: digits land left to right, the last two red,
-- then the animal stamps in before the next prize. C_Timer replaces the lab's OnUpdate driver.
StopPracticeReveal = function()
	StopPracticeSound()
	practice.gen = (practice.gen or 0) + 1
	practice.revealing, practice.active = nil, nil
	practice.shown = practice.prizes and #practice.prizes or 0
	for _, r in ipairs(practiceWindow and practiceWindow.prizes or {}) do
		if r.pop and r.pop.Stop then r.pop:Stop() end
		for _, flash in ipairs(r.flash) do flash:Hide() end
	end
end
StartPracticeReveal = function()
	StopPracticeReveal()
	if not C_Timer or type(C_Timer.After) ~= "function" then return end
	local gen, f = practice.gen, practiceWindow
	practice.shown, practice.revealing = 0, true
	practice.headShown = false
	Sound("practiceStart")
	local function Current()
		return practice.gen == gen and practice.revealing and f:IsShown()
	end
	local NextPrize
	NextPrize = function(k)
		if not Current() then return end
		if k > Lot().PRIZES then
			practice.revealing, practice.active = nil, nil
			RefreshPracticeWindow(); Sound(#ArenaUI.LotteryPracticeModel().positions > 0 and "win" or "lose")
			return
		end
		local r, digits = f.prizes[k], Lot().Text(practice.prizes[k])
		practice.active = k
		r.art:Hide(); r.rim:Hide(); r.name:SetText("")
		local initial = {}
		for d = 1, 4 do
			initial[d] = tostring(math.random(0, 9)); r.digit[d]:SetText(initial[d])
			r.digit[d]:SetTextColor(unpack(INK)); r.flash[d]:Hide()
		end
		r.number:SetText(table.concat(initial))
		if type(StopSound) == "function" then practiceSpinHandle = Sound("practiceSpin") else Sound("spin") end
		local elapsed, settled, ticks = 0, 0, {}
		local function Step()
			if not Current() then return end
			if InCombatLockdown and InCombatLockdown() then f:Hide(); return end
			elapsed = elapsed + 0.06
			local text = {}
			for d = 1, 4 do
				-- Original local reveal: a short spin, then Bicho's 0.72s left-to-right settle.
				local lands = 0.36 + 0.72 * 0.18 * d
				if elapsed >= lands then
					if d > settled then
						settled = d; r.digit[d]:SetText(digits:sub(d, d))
						r.digit[d]:SetTextColor(unpack(d >= 3 and RED or INK)); r.flash[d]:Show(); Sound("pick")
					end
					r.flash[d]:SetAlpha(max(0, 0.8 - (elapsed - lands) * 2.6))
				else
					local tick = floor(elapsed / (0.04 + 0.12 * (elapsed / lands)))
					if tick ~= ticks[d] then ticks[d] = tick; r.digit[d]:SetText(tostring(math.random(0, 9))) end
				end
				text[d] = r.digit[d]:GetText()
			end
			r.number:SetText(table.concat(text))
			if elapsed < 1.08 then C_Timer.After(0.06, Step); return end
			StopPracticeSound(); practice.shown = k; RefreshPracticeWindow(); Sound("practiceSettle")
			if r.pop and r.pop.Play then r.pop:Play() end
			C_Timer.After(0.28, function()
				if not Current() then return end
				if k == 1 then practice.headShown = true; RefreshPracticeWindow(); Sound("practiceHead") end
				C_Timer.After(NEXT, function() NextPrize(k + 1) end)
			end)
		end
		RefreshPracticeWindow()
		C_Timer.After(0.06, Step)
	end
	NextPrize(1)
end

function ArenaUI.LotteryPracticeWindow(show)
	if InCombatLockdown and InCombatLockdown() then return false end
	local f = practiceWindow
	if not f then
		if show == false then return nil end
		f = ns.Window("OlympusArenaLotteryPractice", UIParent, { inset = false })
		practiceWindow = f
		f:Hide(); f:SetSize(PRACTICE_W, PRACTICE_H); f:SetPoint("CENTER", 0, 0); f:SetFrameStrata("DIALOG")
		f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local inner = f.inner
		f.paper = Parchment(f)
		f.paper:ClearAllPoints()
		f.paper:SetPoint("TOPLEFT", inner[1], inner[2]); f.paper:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
		f.title = Text(f, 28, INK, MORPHEUS, "LEFT"); f.title:SetPoint("TOPLEFT", 21, -38); f.title:SetText(L.LOTTERY_NAME)
		f.intro = Text(f, 13, INK, STANDARD_TEXT_FONT)
		f.intro:SetPoint("TOPRIGHT", -24, -44); f.intro:SetWidth(500)
		f.intro:SetText(L.LOTTERY_PRACTICE_GRID_INTRO)
		f.note = Text(f, 12, SOFT, STANDARD_TEXT_FONT, "LEFT")
		f.note:SetPoint("TOPLEFT", 22, -80); f.note:SetWidth(PRACTICE_W - 44)
		f.grid = CreateFrame("Frame", nil, f); f.grid:SetAllPoints(f)
		f.cards = {}
		for i = 1, 25 do
			local n, b = i, Lot().Beast(i)
			local c = CreateFrame("Button", nil, f.grid)
			c:SetSize(150, 94); c:SetPoint("TOPLEFT", 21 + ((i - 1) % 5) * 156, -118 - floor((i - 1) / 5) * 100)
			local leaf = c:CreateTexture(nil, "BACKGROUND", nil, 1); leaf:SetPoint("TOPLEFT", 3, -3); leaf:SetSize(144, 88); leaf:SetColorTexture(1, 0.96, 0.84, 0.4)
			c.wash = c:CreateTexture(nil, "BACKGROUND", nil, 2); c.wash:SetPoint("TOPLEFT", 3, -3); c.wash:SetSize(144, 88); c.wash:SetColorTexture(1, 0.76, 0.3, 0.34); c.wash:Hide()
			PracticeResultEdge(c, { 0.62, 0.44, 0.22 })
			c.art = c:CreateTexture(nil, "ARTWORK"); c.art:SetSize(60, 60); c.art:SetPoint("TOPLEFT", 10, -29)
			c.art:SetTexture(PracticeArt(i)); c.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			c.iconFrame = c:CreateTexture(nil, "ARTWORK", nil, 2); c.iconFrame:SetAllPoints(c.art)
			c.iconFrame:SetTexture("Interface\\Common\\WhiteIconFrame"); c.iconFrame:SetVertexColor(0.86, 0.66, 0.3)
			c.slot = c:CreateTexture(nil, "BORDER", nil, 3); c.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			c.slot:SetSize(60 * 64 / 39, 60 * 64 / 39); c.slot:SetPoint("CENTER", c.art, "CENTER", 0, 0)
			c.num = Text(c, 15, { 0.46, 0.13, 0.03 }, STANDARD_TEXT_FONT, "LEFT"); c.num:SetPoint("TOPLEFT", 11, -8); c.num:SetWidth(24); c.num:SetText(("%02d"):format(i))
			c.name = Text(c, 15, INK, MORPHEUS, "LEFT"); c.name:SetPoint("TOPLEFT", 35, -8); c.name:SetWidth(108); c.name:SetWordWrap(false); c.name:SetText(b.name)
			c.dz = {}
			local endings = Lot().Dezenas(i)
			for line = 1, 2 do
				local text = Text(c, 14, SOFT, STANDARD_TEXT_FONT, "LEFT")
				text:SetPoint("TOPLEFT", 76, -(28 + (line - 1) * 17)); text:SetWidth(70)
				text:SetText(endings[line * 2 - 1] .. " " .. endings[line * 2]); c.dz[line] = text
			end
			c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			c:SetScript("OnClick", function() ArenaUI.LotteryPracticePick(n); Sound("pick") end)
			f.cards[i] = c
		end
		f.result = CreateFrame("Frame", nil, f); f.result:SetAllPoints(f)
		f.resultTitle = Text(f.result, 24, INK, MORPHEUS, "LEFT"); f.resultTitle:SetPoint("TOPLEFT", 21, -PRY); f.resultTitle:SetText(L.LOTTERY_PRACTICE_RESULT)
		f.prizes = {}
		for i = 1, 5 do
			local r = CreateFrame("Frame", nil, f.result)
			r:SetSize(PRW, PROWH - 4); r:SetPoint("TOPLEFT", 21, -(PROW0 + (i - 1) * PROWH))
			r.band = r:CreateTexture(nil, "BORDER"); r.band:SetAllPoints(); r.band:SetColorTexture(1, 0.78, 0.28, 0.34); r.band:Hide()
			r.mark = r:CreateTexture(nil, "BORDER", nil, 1); r.mark:SetPoint("TOPLEFT", 0, 0); r.mark:SetSize(5, PROWH - 4); r.mark:SetColorTexture(RED[1], RED[2], RED[3], 0.9); r.mark:Hide()
			r.place = Text(r, 20, INK, STANDARD_TEXT_FONT, "LEFT"); r.place:SetPoint("TOPLEFT", 12, -6); r.place:SetWidth(44); r.place:SetText(L["LOTTERY_PRIZE_" .. i])
			r.art = r:CreateTexture(nil, "ARTWORK"); r.art:SetSize(PICON, PICON); r.art:SetPoint("TOPLEFT", PIX, -5)
			r.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			local rim = r:CreateTexture(nil, "ARTWORK", nil, 2); rim:SetAllPoints(r.art); rim:SetTexture("Interface\\Common\\WhiteIconFrame"); rim:SetVertexColor(unpack(BRONZE))
			r.rim = rim
			r.number = Text(r, 25, INK, MORPHEUS)
			-- Original Bicho digit tiles, including the warmer pair that identifies the animal.
			r.number:Hide() -- aggregate retained for callers; the four visible tiles replace it
			r.digit, r.flash = {}, {}
			for d = 1, 4 do
				local tile = r:CreateTexture(nil, "BORDER")
				tile:SetPoint("TOPLEFT", 60 + (d - 1) * 40, -3); tile:SetSize(36, 46)
				tile:SetColorTexture(unpack(d >= 3 and { 0.55, 0.16, 0.05, 0.2 } or { 0.35, 0.2, 0.07, 0.16 }))
				r.flash[d] = r:CreateTexture(nil, "ARTWORK", nil, 1); r.flash[d]:SetAllPoints(tile)
				r.flash[d]:SetColorTexture(1, 0.85, 0.45, 0.8); r.flash[d]:SetBlendMode("ADD"); r.flash[d]:Hide()
				r.digit[d] = Text(r, 30, INK, STANDARD_TEXT_FONT)
				r.digit[d]:SetPoint("TOPLEFT", 60 + (d - 1) * 40, -10); r.digit[d]:SetSize(36, 30)
				r.digit[d]:SetText("-")
			end
			if r.art.CreateAnimationGroup then
				r.pop = r.art:CreateAnimationGroup()
				local scale, alpha = Anim(r.pop, "Scale"), Anim(r.pop, "Alpha")
				if scale then scale:SetScaleFrom(1.35, 1.35); scale:SetScaleTo(1, 1); scale:SetDuration(0.28); scale:SetSmoothing("OUT") end
				if alpha then alpha:SetFromAlpha(0.2); alpha:SetToAlpha(1); alpha:SetDuration(0.28) end
			end
			r.name = Text(r, 16, INK, MORPHEUS, "LEFT"); r.name:SetPoint("TOPLEFT", PIX + PICON + 10, -7); r.name:SetWidth(PRW - PIX - PICON - 14)
			r.group = Text(r, 13, SOFT, STANDARD_TEXT_FONT, "LEFT"); r.group:SetPoint("TOPLEFT", PIX + PICON + 10, -31); r.group:SetWidth(PRW - PIX - PICON - 14)
			f.prizes[i] = r
		end
		local head = CreateFrame("Frame", nil, f.result); head:SetPoint("TOPLEFT", PHX, -PRY); head:SetSize(PHW, PHH)
		f.head = head
		local leaf = head:CreateTexture(nil, "BACKGROUND"); leaf:SetPoint("TOPLEFT", 3, -3); leaf:SetPoint("BOTTOMRIGHT", -3, 3); leaf:SetColorTexture(1, 0.96, 0.84, 0.4)
		local wash = head:CreateTexture(nil, "BACKGROUND", nil, 1); wash:SetAllPoints(leaf); wash:SetColorTexture(1, 0.76, 0.3, 0.34)
		PracticeResultEdge(head)
		head.content = CreateFrame("Frame", nil, head); head.content:SetAllPoints(head)
		head.num = Text(head.content, 22, INK, STANDARD_TEXT_FONT, "LEFT"); head.num:SetPoint("TOPLEFT", 16, -14)
		head.name = Text(head.content, 26, INK, MORPHEUS, "LEFT"); head.name:SetPoint("TOPLEFT", 56, -12); head.name:SetWidth(PHW - 72)
		head.art = head.content:CreateTexture(nil, "ARTWORK"); head.art:SetSize(104, 104); head.art:SetPoint("TOPLEFT", 18, -54); head.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local rim = head.content:CreateTexture(nil, "ARTWORK", nil, 2); rim:SetAllPoints(head.art); rim:SetTexture("Interface\\Common\\WhiteIconFrame"); rim:SetVertexColor(unpack(BRONZE))
		local slot = head.content:CreateTexture(nil, "BORDER"); slot:SetTexture("Interface\\Buttons\\UI-Quickslot2"); slot:SetSize(104 * 64 / 39, 104 * 64 / 39); slot:SetPoint("CENTER", head.art, "CENTER", 0, 0)
		local glow = head.content:CreateTexture(nil, "OVERLAY", nil, 1); glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		glow:SetTexCoord(5 / 128, 61 / 128, 75 / 256, 131 / 256); glow:SetBlendMode("ADD")
		local pad = 9 * (104 + 2) / 38 - 1
		glow:SetPoint("TOPLEFT", head.art, "TOPLEFT", -pad, pad); glow:SetPoint("BOTTOMRIGHT", head.art, "BOTTOMRIGHT", pad, -pad)
		head.number = Text(head.content, 22, RED, STANDARD_TEXT_FONT, "LEFT"); head.number:SetPoint("TOPLEFT", 142, -58); head.number:SetWidth(PHW - 156)
		head.group = Text(head.content, 15, SOFT, STANDARD_TEXT_FONT, "LEFT"); head.group:SetPoint("TOPLEFT", 142, -90); head.group:SetWidth(PHW - 156)
		f.outcome = Text(f.result, 18, INK, MORPHEUS); f.outcome:SetPoint("TOP", 0, -500); f.outcome:SetWidth(650)
		local record = Text(f.result, 13, SOFT, STANDARD_TEXT_FONT)
		record:SetPoint("TOP", f.outcome, "BOTTOM", 0, -28); record:SetWidth(650); record:SetText(L.LOTTERY_PRACTICE_RECORD)
		f.pick = Text(f, 14, INK, STANDARD_TEXT_FONT); f.pick:SetPoint("BOTTOM", 0, 72); f.pick:SetWidth(PRACTICE_W - 60)
		-- 1.2.0: what the Lottery may become, between the cards and the pick (two lines at most).
		f.future = Text(f, 12, INK, STANDARD_TEXT_FONT); f.future:SetPoint("BOTTOM", 0, 92); f.future:SetWidth(PRACTICE_W - 60)
		f.future:SetText(L.LOTTERY_PRACTICE_FUTURE)
		if own.Games and type(own.Games.Footer) == "function" then f.foot = own.Games.Footer(f, 618, 106, 10) end
		f.help = Button(f, L.LOTTERY_BOARD_HOW, 150, 32, function() ArenaUI.LotteryHowToPlay(nil, true) end)
		f.help:SetPoint("BOTTOMLEFT", 24, 26)
		f.history = Button(f, L.LOTTERY_PANE_HISTORY, 150, 32, function()
			f:Hide(); ArenaUI.Open("games.mine"); ArenaUI.SetGames("game", "lottery")
		end)
		f.history:SetPoint("LEFT", f.help, "RIGHT", 8, 0)
		f.draw = Button(f, L.LOTTERY_PRACTICE_DRAW, 190, 32, function()
			if #ArenaUI.LotteryPracticeModel().rows == Lot().PRIZES then ArenaUI.LotteryPracticeReset()
			else ArenaUI.LotteryPracticeDraw() end
		end)
		f.draw:SetPoint("BOTTOMRIGHT", -24, 26)
		f:SetScript("OnShow", function()
			if ArenaUI.HideForGame then ArenaUI.HideForGame() end
			ns.Fire("ARENA_GAME_SHOWN", "lottery")
			RefreshPracticeWindow()
		end)
		f:SetScript("OnHide", function() StopPracticeReveal(); if guide and guide.over == f then guide:Hide() end end)
		ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() f:Hide() end)
		ns.On("ARENA_GAME_SHOWN", function(key) if key ~= "lottery" then f:Hide() end end)
	end
	if show == false then f:Hide() return f end
	ArenaUI.Kit.FitWindow(f, PRACTICE_W, PRACTICE_H, 1)
	if ArenaUI.HideForGame then ArenaUI.HideForGame() end
	f:Show(); RefreshPracticeWindow()
	return f
end

-- The Lottery section of the betting window: one real board, then its real history and a local
-- tutorial. Practice is a teaching surface, never the old made-up showcase/lab.
-- (help: the section's How to play, for the window's bar to open in this section; the board's
-- own Bet and Roll sit on that bar, so the pane gives the window no buttons.)
local paneParent -- (the arena window's canvas for this pane: the one board comes back to it)
ArenaUI.RegisterPane("lottery", { section = "lottery", label = L.LOTTERY_PANE_PLAY, order = 1,
	visible = function() return Lot().Wagers() end,
	build = function(parent) paneParent = parent return Build(parent) end,
	refresh = function()
		if paneParent and board and board.frame:GetParent() ~= paneParent then Build(paneParent) end
		Refresh()
	end,
	help = function() return ArenaUI.LotteryHowToPlay() end })
ArenaUI.RegisterPane("lottery.history", { section = "lottery", label = L.LOTTERY_PANE_HISTORY, order = 2,
	lines = HistoryLines, detail = HistoryDetail,
	text = function() return L.LOTTERY_PANE_HISTORY, L.LOTTERY_HISTORY_PREVIOUS end,
	buttons = function()
		local buttons = { { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end } }
		if WalletShown() then table.insert(buttons, 1, { L.LOTTERY_HISTORY_WALLET, function() ArenaUI.LotteryOpenWallet() end }) end
		return buttons
	end })
-- (1.1.6: practice comes first while the compliance gate allows no ticket.)
ArenaUI.RegisterPane("lottery.practice", { section = "lottery", label = L.LOTTERY_PANE_PRACTICE,
	order = (type(Lot()) == "table" and type(Lot().Wagers) == "function" and not Lot().Wagers()) and 0 or 3,
	lines = PracticeLines, detail = PracticeDetail,
	text = function() return L.LOTTERY_PANE_PRACTICE, L.LOTTERY_PRACTICE_INTRO end,
	buttons = function()
		local m = ArenaUI.LotteryPracticeModel()
		return {
			{ L.LOTTERY_PRACTICE_OPEN, function() ArenaUI.LotteryPracticeWindow(true) end },
			{ m.result and L.LOTTERY_PRACTICE_AGAIN or L.LOTTERY_PRACTICE_DRAW,
				function() ArenaUI.LotteryPracticeDraw() end, enabled = m.pick ~= nil,
				why = not m.pick and L.LOTTERY_PRACTICE_PICK or nil },
			{ L.LOTTERY_PRACTICE_RESET, function() ArenaUI.LotteryPracticeReset() end, enabled = m.pick ~= nil },
		}
	end })

---------------------------------------------------------------------------
-- The board's own window, while the betting window is not in the build
---------------------------------------------------------------------------

local window
local WIN_W, WIN_H = 820, 600
-- The balance on the bar's coin: the canonical wallet's gold (the arena window's bar's source).
local function WalletBalance()
	local D = ArenaUI.Data
	local ok, w = pcall(function() return D and D.Wallet and D.Wallet() end)
	return ok and type(w) == "table" and type(w.g) == "table" and tonumber(w.g.bal) or 0
end
function ArenaUI.LotteryWindow(show)
	if not window then
		window = CreateFrame("Frame", "OlympusArenaLottery", UIParent)
		window.lotteryWindow = true
		window:SetSize(WIN_W, WIN_H)
		window:SetPoint("CENTER", 0, 30)
		window:SetFrameStrata("MEDIUM")
		window:SetToplevel(true)
		window:SetClampedToScreen(true)
		window:SetMovable(true)
		window:EnableMouse(true)
		window:RegisterForDrag("LeftButton")
		window:SetScript("OnDragStart", window.StartMoving)
		window:SetScript("OnDragStop", window.StopMovingOrSizing)
		Edge(window, { 0.07, 0.04, 0.02 }, 0.95, 3, "OVERLAY")
		local x = CreateFrame("Button", nil, window, "UIPanelCloseButton")
		x:SetPoint("TOPRIGHT", 2, 2)
		x:SetFrameLevel((window:GetFrameLevel() or 0) + 20)
		x:SetScript("OnClick", function() window:Hide() end)
		window:SetScript("OnShow", function() ns.Arena.Involve("lottery window", true) end)
		window:SetScript("OnHide", function() ns.Arena.Involve("lottery window", false) end)
		-- The games' bar across the bottom (Games.Bar, Bones' 56 px): the coin and the balance, How
		-- to play, then the board's Bet or Roll on the right; the board above it.
		local G = own.Games
		local body = CreateFrame("Frame", nil, window)
		body:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
		if G and type(G.Bar) == "function" then
			local bh = G.BAR and G.BAR.H or 56
			body:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, bh + 10)
			window.bar = G.Bar(window, { y = WIN_H - 10 - bh, inset = 10, balance = WalletBalance, tip = L.ARENA_WALLET_TITLE,
				helpText = L.LOTTERY_BOARD_HOW, help = function() ArenaUI.LotteryHowToPlay(nil, true) end })
			body.lotteryBar = window.bar
		else
			body:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
		end
		window.body = body
		Build(body)
		-- Closed in combat, as the betting window is (the design).
		ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() if window:IsShown() then window:Hide() end end)
	end
	ns.EscapeCloses("OlympusArenaLottery")
	if show == false or (show == nil and window:IsShown()) then
		window:Hide()
	else
		-- (The board may have been the arena window's pane: back in this window.)
		if board and board.frame:GetParent() ~= window.body then Build(window.body) end
		window:Show()
		ns.Arena.Involve("lottery window", true)
		if window.bar and window.bar.wallet and window.bar.wallet.Refresh then window.bar.wallet.Refresh() end
		OnShow()
	end
	return window
end

-- The board follows the lottery: the day's changes, each prize as it is rolled, the result.
local function Changed() if board and board.frame:IsShown() then Refresh() end end
ns.On("ARENA_CHANGED", Changed)
ns.On("LOTTERY_DRAW", Changed)
ns.On("LOTTERY_RESULT", Changed)
ns.On("LOTTERY_OPEN", function()
	state.pick, state.note = nil, nil
	Changed()
end)
