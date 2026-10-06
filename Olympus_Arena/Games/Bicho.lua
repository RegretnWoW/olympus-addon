local _, own = ...; local ns = own.host; if not ns then return end
local host = ns; ns = own -- (the lab's tables stay the companion's own: Olympus has its own ns.Wallet and ns.FarkleRules)
-- (Ported from the Olympus Frame Lab, 2026-09-30: the practice preview, inside the arena.)
-- The Menagerie Lottery (Olympus's own animal-lottery rules, not an official jogo-do-bicho rule)
-- for the Olympus Frame Lab: a playable
-- preview with practice gold. Nothing is saved. The draw's five /roll go to the server like any
-- /roll: your party or raid sees the lines (and players near you may, when you are alone).
--   /oly lottery  (or /lab bicho)   open or close the table
--   /oly lottery draw               draw now (the table's own button does the same)
--   /oly lottery letter             the first-use letter again
--   /oly lottery sound              the sound effects on or off
-- The table is a 5x5 card of the 25 beasts in the classic order (beast n owns the endings
-- n*4-3 .. n*4, the Kodo 97-00). Click a card, type a stake (Enter bets) or step it with - and +,
-- Bet: the gold comes out of the practice wallet the games share (ns.Wallet, Games.lua; its
-- button in the footer opens it, each bet and payout a line of its history). Practice bettors bet
-- too, so the pools
-- move. "Draw now" closes the bets and throws your own five /roll 1-10000, one after another
-- (RandomRoll; each is read back from the game's roll line, so a typed /roll 10000 counts the
-- same; 10000 reads as 0000). The five prizes fill the result. Every ticket on any drawn beast
-- gets its stake back once. The profit pool then pays 50%, 25%, 15% and 10% to the first four
-- positions; the fifth is refund-only. Unclaimed tranches roll over. The guild's 6% is only of
-- gross profit actually paid, never of refunds or rollover. Bicho.Settle is a thin adapter over
-- Olympus/Lottery.lua, the one settlement implementation used by the real wallet too.
--
-- The window, centred on the screen, parchment only (no title bar, no portrait), each thing in its
-- own area: the header (the name, the pot, your bets), the grid of cards filling the rest (the
-- pick's card in the quest item's gold border), and the footer compartment (as Bones's): the
-- counter (your pick, the stake, Bet; during the draw what is being drawn; after it the
-- announcement), then How to play and the wallet on the left, Draw now (Next draw) on the right.
-- The draw happens inside the window: the grid gives its place to the result (the five prizes
-- revealed one by one, the head's card big with who shares it, your bets and your day) until Next
-- draw. The window is the Lottery's alone: no tabs to the other games (the lab's games window,
-- /oly games, is the way between them). The letter, How to play and the wallet are the lab's one
-- pop-up (Games.lua's Games.Popup, as Bones's How to play), centred over the window, a strata
-- above it.
local AP = host.ArenaParse
local floor, min, max, random = math.floor, math.min, math.max, math.random
local CoreLottery = host.Lottery

local Bicho = {}
ns.Bicho = Bicho

local ICONS = "Interface\\Icons\\"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"
-- Olympus's writ parchment (Acts.lua): QuestBG's page, 296 x 331 of its 512 x 512.
local PARCHMENT, PAGE = "Interface\\QuestFrame\\QuestBG", { 0, 296 / 512, 0, 331 / 512 }

-- The 25 in the classic order, each of ours where the real one has its match (Avestruz 1 -> the
-- Mechanostrider, Aguia 2 -> the Gryphon, Cachorro 5 -> the Wolf, Carneiro 7 -> the Sheep, Gato
-- 14 -> the Nightsaber, Jacare 15 -> the Crocolisk, Porco 18 -> the Boar, Tigre 22 -> the
-- Cheetah, Veado 24 -> the Stag, Vaca 25 -> the Kodo). The images are the game's own icons, one
-- painted style for all 25 (every file is in Forever 1.60.1.70124's ManifestInterfaceData):
-- hunter pets and mounts, Polymorph's sheep, the Felhunter's summon, Aspect of the Cheetah's cat.
local BEASTS = {
	{ "Mechanostrider", "Ability_Mount_MechaStrider" },
	{ "Gryphon", "Ability_Mount_Gryphon_01" },
	{ "Turtle", "Ability_Hunter_Pet_Turtle" },
	{ "Bat", "Ability_Hunter_Pet_Bat" },
	{ "Wolf", "Ability_Hunter_Pet_Wolf" },
	{ "Raptor", "Ability_Hunter_Pet_Raptor" },
	{ "Sheep", "Spell_Nature_Polymorph" },
	{ "Spider", "Ability_Hunter_Pet_Spider" },
	{ "Cobra", "Ability_Hunter_CobraStrikes" },
	{ "Koi", "INV_Misc_Fish_36" },
	{ "Horse", "Ability_Mount_RidingHorse" },
	{ "Dragon", "Ability_Mount_Drake_Red" },
	{ "Raven", "INV_PetRaven2" },
	{ "Nightsaber", "Ability_Mount_BlackPanther" },
	{ "Crocolisk", "Ability_Hunter_Pet_Crocolisk" },
	{ "Lion", "INV_Mount_AllianceLionG" },
	{ "Murloc", "INV_Misc_Head_Murloc_01" },
	{ "Boar", "Ability_Hunter_Pet_Boar" },
	{ "Owl", "Ability_Hunter_Pet_Owl" },
	{ "Felhunter", "Spell_Shadow_SummonFelHunter" },
	{ "Tentacle", "Spell_Priest_VoidTendrils" },
	{ "Cheetah", "Ability_Mount_JungleTiger" },
	{ "Bear", "Ability_Hunter_Pet_Bear" },
	{ "Stag", "Achievement_WorldEvent_Reindeer" },
	{ "Kodo", "Ability_Mount_Kodo_01" },
}
for _, b in ipairs(BEASTS) do b.name, b.icon = b[1], ICONS .. b[2] end
-- an icon's own dark rim, left out (the card's frame is drawn round it)
local CROP = { 0.07, 0.93, 0.07, 0.93 }

local FEE_BP = 600                         -- the guild's 6%, of the money won only (the design)
local GOLD, SILVER = 10000, 100            -- copper
local WALLET = 100 * GOLD                  -- the practice wallet
local STEPS = { 1, 2, 5, 10, 20, 50 }      -- what - and + step through, in gold (any whole gold can be typed)
local MAX_STAKE = 9999                     -- gold: what the stake box takes (four digits)
local LOW, HIGH = 1, 10000                 -- your /roll for a prize (10000 reads 0000; 0-9999 counts too)
local PRIZES = 5
local LINE_WAIT = 6                        -- seconds a roll's line is waited for
local CROWD_MAX, CROWD_START = 40, 10      -- practice bettors' bets a day, and those already in at the start
-- The table (inside a 1024 x 768 screen at UI scale 1): the header, the 5x5 grid of cards (the
-- draw's result in its place from the draw on), the counter at the bottom.
local W, H = 816, 734
local HEAD_H = 92                          -- the header, above the grid: the name, the pot, your bets
local GX, GY, CW, CH, GAP = 21, 94, 150, 94, 6 -- (CH 94: room for the games' one bar, 2026-09-30)
local ICON = 60                            -- a card's image
-- The footer compartment, under the grid: the counter (your pick, the stake, Bet; during the draw
-- what is being drawn; after it the announcement), then the window's buttons as Bones has
-- them: How to play and the wallet on the left, the main action (Draw now, Next draw) on the right.
local FOOT_Y = GY + 5 * CH + 4 * GAP + 6
local ROW_A, ROW_B = FOOT_Y + 12, FOOT_Y + 76
-- Where each thing may be (x, y, right, bottom), for the layout and the offline tests. The draw's
-- result has the grid's area.
local AREAS = {
	header = { 0, 0, W, HEAD_H }, grid = { GX - 6, GY - 2, W - GX + 6, FOOT_Y }, foot = { 0, FOOT_Y, W, H },
}
local NAMES = { "1st", "2nd", "3rd", "4th", "5th" }

---------------------------------------------------------------------------
-- The game's rules and money (pure: no frames, no state)
---------------------------------------------------------------------------

-- The four endings a beast owns, as two-digit strings: 1 -> 01 02 03 04 ... 25 -> 97 98 99 00.
function Bicho.Dezenas(n)
	local out = {}
	for i = 1, 4 do out[i] = ("%02d"):format(((n - 1) * 4 + i) % 100) end
	return out
end

-- The beast of a four-digit number: its last two digits' group (01-04 -> 1 ... 97-00 -> 25).
function Bicho.BeastOf(milhar)
	local d = milhar % 100
	if d == 0 then return 25 end
	return floor((d - 1) / 4) + 1
end

-- A /roll's number as the four digits of a prize: 1-10000 with 10000 as 0000, or 0-9999 as is.
-- nil for any other range.
function Bicho.Milhar(value, low, high)
	if low == 1 and high == 10000 then return value % 10000 end
	if low == 0 and high == 9999 then return value end
	return nil
end

function Bicho.MulDiv(a, b, c)
	return host.ArenaMath and host.ArenaMath.MulDiv(a, b, c) or nil
end

-- bets: { { who, beast, stake (copper), immutableTicketId? }, ... }; draw: five beasts in order.
-- The adapter keeps the practice view's older field names, but does no settlement arithmetic.
function Bicho.Settle(bets, draw, carried, feeBp)
	if not (CoreLottery and type(CoreLottery.Settle) == "function") then return nil, "contract" end
	local tickets, onHead = {}, 0
	for i, b in ipairs(type(bets) == "table" and bets or {}) do
		local id = type(b[4]) == "string" and b[4] or ("practice.%08d"):format(i)
		tickets[i] = { id = id, who = b[1], animal = b[2], stake = b[3] }
		if type(draw) == "table" and b[2] == draw[1] then onHead = onHead + b[3] end
	end
	local r, why, at = CoreLottery.Settle({ version = CoreLottery.SETTLEMENT_VERSION, tickets = tickets,
		draw = draw, carry = carried or 0, feeBp = feeBp or FEE_BP })
	if not r then return nil, why, at end
	r.pot, r.onHead, r.won, r.share, r.rounding, r.guild = r.available, onHead, r.profitPool, r.netProfit, 0, r.fee
	return r
end

-- Money as the game writes it, the lab's (Games.lua): Money 12g 40s 5c, Coins with the game's
-- coins, Signed a gain or a loss.
Bicho.Money, Bicho.Coins, Bicho.Signed = ns.Games.Money, ns.Games.Coins, ns.Games.Signed
local Money, Coins, Signed = Bicho.Money, Bicho.Coins, Bicho.Signed
local COINS = ns.Games.COINS

---------------------------------------------------------------------------
-- The table's state (memory only: a /reload starts over)
---------------------------------------------------------------------------

-- S.wallet is the lab's shared practice wallet (ns.Wallet, Games.lua): read it for its balance;
-- the table moves it with Wallet.Move (each bet, each payout), so its history adds up.
local Wallet = ns.Wallet
local S = setmetatable({
	day = 1, carried = 0, bets = {}, ticketSeq = 0, sel = nil, stake = 10,
	phase = "bet",          -- "bet", "draw" (bets closed, the prizes being drawn), "result"
	prizes = {},            -- [k] = { value, milhar, beast, shown }
	reqs = {},              -- the rolls asked and not answered yet: { prize, at }, oldest first (never
	                        -- given up: a line can come late, and it answers the oldest)
	want = nil,             -- the prize whose roll line is awaited
	stalled = nil,          -- the prize to roll again (no line in time, or the table was closed)
	round = 0,              -- a new day or a closed table drops the timers of the old one
	sound = true, letterSeen = false, page = 1, crowd = 0, feed = nil, hint = nil, result = nil,
}, {
	__index = function(_, k) if k == "wallet" then return Wallet.balance end end,
	-- (a set by hand, the tests': a line of its own in the history)
	__newindex = function(t, k, v) if k == "wallet" then Wallet.Set(v) else rawset(t, k, v) end end,
})

local win, driver, events, letter, guide, res
local header, bar, cards = {}, {}, {}
local anims = {}
local Refresh, NextPrize

-- Ink on the parchment: dark, with a light edge under it (Bones's). Light text only on the
-- game's own dark tabs (the guide's) and its input box.
local INK, SOFT = { 0.15, 0.07, 0.02 }, { 0.3, 0.18, 0.07 }
local RED, GREEN, NUMBER = { 0.55, 0.08, 0.03 }, { 0.1, 0.36, 0.04 }, { 0.46, 0.13, 0.03 }
local HEX = { red = "ff8c1408", green = "ff1a5c0a", number = "ff752108", soft = "ff4d2e12" }
local FRAME = { 0.86, 0.66, 0.3 }          -- an icon's frame (the game's white frame, tinted)
local EDGE = { 0.62, 0.44, 0.22, 1 }       -- a card's edge (the tooltip's border, tinted brown)
local LIT = { 1, 0.68, 0.08, 1 }           -- the pick's and the head's gold
local GOLDTXT, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe6c35cLottery:|r " .. msg) end
local function Color(hex, text) return "|c" .. hex .. text .. "|r" end

local function SetFont(fs, font, size, flags)
	if not fs:SetFont(font, size, flags or "") then fs:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end

-- Text on the parchment (Friz Quadrata unless a font is given; Morpheus only for titles, headings
-- and the beasts' names, never with digits in it: its s reads as an 8 next to them).
local function Text(parent, size, color, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	SetFont(fs, font or STANDARD_TEXT_FONT, size)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowColor(1, 0.94, 0.8, 0.6); fs:SetShadowOffset(1, -1)   -- pressed into the page
	fs:SetJustifyH(justify or "LEFT")
	return fs
end
-- Light text on the game's dark tabs, with the game's black shadow.
local function DarkText(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	SetFont(fs, STANDARD_TEXT_FONT, size)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
	fs:SetJustifyH(justify or "CENTER")
	fs.onDark = true
	return fs
end
-- A line of text: its top left at (x, y) of `rel` (y down), in a box w wide, never wrapped.
local function Line(parent, rel, x, y, w, size, color, font, justify)
	local fs = Text(parent, size, color, font, justify)
	fs:SetPoint("TOPLEFT", rel, "TOPLEFT", x, -y)
	fs:SetWidth(w); fs:SetWordWrap(false)
	return fs
end
-- The first of the texts that fits the line's box with 5% to spare (the last one whatever it
-- measures): the client's rendering can come out a little wider than the font's advances.
local function Fit(fs, ...)
	local n, w = select("#", ...), fs:GetWidth()
	for i = 1, n do
		local t = select(i, ...)
		fs:SetText(t)
		local sw = fs:GetStringWidth()
		if i == n or (type(sw) == "number" and sw <= w * 0.95) then return end
	end
end
local function Ink(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Tex(parent, layer, sub)
	return parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
end
local function Box(parent, rel, x, y, w, h, color, layer, sub)
	local t = Tex(parent, layer or "BORDER", sub)
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	t:SetPoint("TOPLEFT", rel, "TOPLEFT", x, -y); t:SetSize(w, h)
	return t
end
-- The quest frame's ornamental break (UI-HorizontalBreak: its swirl is 23..232 x 7..25 of the
-- 256 x 32 file): the two curls at their own shape, the waves between them stretched to the width.
local BREAK = "Interface\\QuestFrame\\UI-HorizontalBreak"
local function Break(parent, rel, x, y, w, h)
	h = h or 14
	local cap = floor(40 * h / 18 + 0.5)
	for _, p in ipairs({ { 23, 63, 0, cap }, { 63, 192, cap, w - 2 * cap }, { 192, 232, w - cap, cap } }) do
		local t = Tex(parent, "BORDER", 1)
		t:SetTexture(BREAK); t:SetTexCoord(p[1] / 256, p[2] / 256, 7 / 32, 25 / 32)
		t:SetPoint("TOPLEFT", rel, "TOPLEFT", x + p[3], -y); t:SetSize(p[4], h)
	end
end

local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h); b:SetText(label)
	b:SetFrameLevel(parent:GetFrameLevel() + 5)
	b:SetScript("OnClick", fn)
	return b
end
local function Set(b, label, on)
	b:SetText(label)
	if on then b:Enable() else b:Disable() end
end

-- The game's tab (the character frame's, 128 x 32), upside down so it stands on what is under it,
-- in three slices: its bevelled ends at their own width, the middle stretched (the guide's pages).
-- A tab's state: "on" (the page shown), "off", or "soon" (greyed).
local TAB_H = 32
local TAB_ON, TAB_OFF = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab", "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab"
local function TabArt(f, w)
	f.art = {}
	for i, cut in ipairs({ { 0, 20, 0, 20 }, { 20, 108, 20, w - 40 }, { 108, 128, w - 20, 20 } }) do
		local t = f:CreateTexture(nil, "BACKGROUND")
		t:SetPoint("TOPLEFT", f, "TOPLEFT", cut[3], 0); t:SetSize(cut[4], TAB_H)
		t.cut = cut
		f.art[i] = t
	end
end
local function TabState(f, state)
	for _, t in ipairs(f.art) do
		t:SetTexture(state == "on" and TAB_ON or TAB_OFF)
		t:SetTexCoord(t.cut[1] / 128, t.cut[2] / 128, 1, 0)
	end
	if f.label then
		local c = state == "on" and WHITE or state == "soon" and GREY or GOLDTXT
		f.label:SetTextColor(c[1], c[2], c[3])
	end
	f.state = state
end
local function Tab(parent, label, w, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, TAB_H)
	b:SetFrameLevel(parent:GetFrameLevel() + 8)
	TabArt(b, w)
	b.label = DarkText(b, 13, GOLDTXT)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.label:SetText(label)
	b:SetScript("OnClick", fn)
	TabState(b, "off")
	return b
end

---------------------------------------------------------------------------
-- Sound: the game's own kits on the SFX channel (each checked in Forever 1.60.1.70124's SoundKit
-- and SoundKitEntry tables); a client without one, or without PlaySound, plays nothing.
---------------------------------------------------------------------------

local SND = {
	open = 875,      -- interface/iquestlogopena: a parchment opens
	close = 876,     -- interface/iquestlogclosea
	page = 836,      -- interface/iabilitiesturnpagec: the guide's page
	pick = 856,      -- interface/uchatscrollbutton: a card picked, the stake stepped
	bet = 120,       -- interface/lootcoinsmall (LOOT_WINDOW_COIN_SOUND): a bet placed
	start = 31579,   -- interface/ui_bonuslootroll_start_01: the bets close, the draw starts
	spin = 31580,    -- interface/ui_bonuslootroll_loop: the digits spin (stopped when they settle)
	settle = 31581,  -- interface/ui_bonuslootroll_end_01: a prize's number settles
	head = 31578,    -- interface/ui_epicloot_toast_01: the head is out
	announce = 50893, -- interface/ui_raid_loot_banner_01: the winner is announced
	win = 878,       -- interface/iquestcomplete: you won
	coins = 287276,  -- interface/lootcoinlarge: your winnings counted in
	lose = 846,      -- interface/igquestfailed: you lost, or it rolls over
}

local played = {}
local function Sound(key)
	if not S.sound or type(PlaySound) ~= "function" or not SND[key] then return nil end
	local now = GetTime()
	if played[key] and now - played[key] < 0.07 then return nil end
	played[key] = now
	local ok, willPlay, handle = pcall(PlaySound, SND[key], "SFX")
	if ok and willPlay then return handle end
	return nil
end

-- The spin's loop sound: one at a time, stopped when the digits settle (never past 4 s).
local spinHandle
local function StopSpin()
	local h = spinHandle
	spinHandle = nil
	if h and type(StopSound) == "function" then pcall(StopSound, h, 120) end
end
local function StartSpin()
	if spinHandle or type(StopSound) ~= "function" then return end
	local h = Sound("spin")
	if not h then return end
	spinHandle = h
	C_Timer.After(4, function() if spinHandle == h then StopSpin() end end)
end

---------------------------------------------------------------------------
-- Animation: one OnUpdate while something moves, removed when nothing does
---------------------------------------------------------------------------

local function Step()
	local now, fired = GetTime(), {}
	for key, a in pairs(anims) do
		if a.loop then a.fn(now - a.t0)
		else
			local u = a.dur > 0 and min(1, (now - a.t0) / a.dur) or 1
			a.fn(u)
			if u >= 1 then
				anims[key] = nil
				if a.done then fired[#fired + 1] = a.done end
			end
		end
	end
	for _, fn in ipairs(fired) do fn() end
	if not next(anims) then driver:SetScript("OnUpdate", nil) end
end
local function Animate(key, dur, fn, done)
	anims[key] = { t0 = GetTime(), dur = dur, fn = fn, done = done }
	fn(0)
	driver:SetScript("OnUpdate", Step)
end
local function Loop(key, fn)
	anims[key] = { t0 = GetTime(), loop = true, fn = fn }
	fn(0)
	driver:SetScript("OnUpdate", Step)
end
local function Stop(key) anims[key] = nil end
local function Ease(u) return 1 - (1 - u) ^ 3 end

-- A number that counts to its new value (the pot, the wallet).
local shown = {}
local function Count(key, fs, to, fmt)
	local from = shown[key]
	shown[key] = to
	if not from or from == to or not (win and win:IsShown()) then fs:SetText(fmt(to)); return end
	Animate("count" .. key, 0.6, function(u) fs:SetText(fmt(floor(from + (to - from) * Ease(u) + 0.5))) end)
end

-- fn after t seconds, unless the day has moved on or the table has been closed.
local function Later(t, fn)
	local round = S.round
	C_Timer.After(t, function() if S.round == round and win and win:IsShown() then fn() end end)
end

---------------------------------------------------------------------------
-- Your roll lines (Bones's reader): WoW: Forever's names are "First Surname", and its
-- UnitName("player") hands the surname back where other clients give the realm, so a second
-- value that isn't this realm is a surname. A line with "-Realm" is yours only for this realm.
---------------------------------------------------------------------------

local function Realm()
	local r = GetNormalizedRealmName and GetNormalizedRealmName()
	if type(r) ~= "string" or r == "" then r = ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "") end
	return r:lower()
end
local function MyName()
	local first, second = UnitName("player")
	if type(first) ~= "string" or first == "" then return nil end
	if first:find(" ", 1, true) then return first end
	if type(second) == "string" and second ~= "" and second:gsub("[%s%-]", ""):lower() ~= Realm() then
		return first .. " " .. second
	end
	return first
end
local function Mine(name)
	local me = MyName()
	if not me then return false end
	me, name = me:lower(), name:lower()
	if name == me then return true end
	local base, realm = name:match("^(.-)%-([^%-]+)$")
	return base == me and realm:gsub("%s", "") == Realm() and Realm() ~= ""
end

---------------------------------------------------------------------------
-- The day's pools
---------------------------------------------------------------------------

local function Pools()
	local pool, mine, total, people, myBets, myTotal, myBeasts = {}, {}, 0, {}, 0, 0, 0
	for n = 1, #BEASTS do pool[n], mine[n] = 0, 0 end
	for _, b in ipairs(S.bets) do
		pool[b[2]] = pool[b[2]] + b[3]
		total = total + b[3]
		people[b[1]] = true
		if b[1] == "you" then
			if mine[b[2]] == 0 then myBeasts = myBeasts + 1 end
			mine[b[2]] = mine[b[2]] + b[3]; myBets = myBets + 1; myTotal = myTotal + b[3]
		end
	end
	local n = 0
	for who in pairs(people) do if who ~= "you" then n = n + 1 end end
	return pool, mine, total, n, myBets, myTotal, myBeasts
end

-- Your bets by beast, in the order you first bet on each: { n, stake, back, bets } (back: what
-- the settlement pays you on it).
local function MyBeasts(r)
	local list, at = {}, {}
	for i, b in ipairs(S.bets) do
		if b[1] == "you" then
			local e = at[b[2]]
			if not e then e = { n = b[2], stake = 0, back = 0, bets = 0 }; at[b[2]] = e; list[#list + 1] = e end
			e.stake, e.bets = e.stake + b[3], e.bets + 1
			if r then e.back = e.back + r.payouts[i] end
		end
	end
	return list
end

-- Your day once drawn: what came back, what was lost (the stakes on the other beasts), the gain.
local function MyResult(r)
	local back, lost, staked = 0, 0, 0
	for _, b in ipairs(MyBeasts(r)) do
		back, staked = back + b.back, staked + b.stake
		if b.back == 0 then lost = lost + b.stake end
	end
	return back, lost, back - staked, staked
end

local function Stake() return S.stake * GOLD end

---------------------------------------------------------------------------
-- Pop-ups (the letter, How to play): the lab's one pop-up (Games.lua's Games.Popup, Bones's How
-- to play: QuestBG's page in a thin dark frame, the X, Escape), on UIParent a strata above the
-- table, centred over it; one at a time. The draw's result is in the table itself.
---------------------------------------------------------------------------

local PW = 384      -- the letter's width, about the guild window's
local GUIDE_W, GUIDE_H = 680, 590          -- How to play: Bones's size (Farkle.lua's GW, GH)
local popups = {}
local Show

-- Escape closes what is on top: a pop-up, then the table (Games.lua's Games.Escape names the table
-- in UISpecialFrames only while none of its pop-ups shows).
local function EscapeSync()
	if win and ns.Games and ns.Games.Escape then ns.Games.Escape("OlympusArenaGamesLottery", win, popups) end
end

-- The game's dialog border, without its own dark tile: the template's Bg sits on the border's
-- frame, drawn over this frame's parchment and ink (Blizzard hides it the same way on its own
-- custom backgrounds, Blizzard_DelvesDifficultyPicker.lua). The table's.
local function Border(f)
	local ok, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if not ok or not border then return nil end
	border:SetAllPoints()
	if rawget(border, "Bg") then border.Bg:Hide() end
	return border
end

local function Parchment(name, w, h)
	local f = ns.Games.Popup(name, w, h, win)
	f:HookScript("OnShow", function() Sound("open"); EscapeSync() end)
	f:HookScript("OnHide", function() Sound("close"); EscapeSync() end)
	popups[#popups + 1] = f
	return f
end

function Show(f)
	for _, p in ipairs(popups) do if p ~= f then p:Hide() end end
	ns.Games.HideWallet(win)
	f:Show()
end

-- A column of text on a page: headings and wrapped paragraphs, one under the other, each as tall
-- as the game makes it (GetStringHeight), from the cursor y down. Headings are Morpheus 18, as the
-- quest frame's (QuestTitleFont).
local function Flow(page, x, w)
	local c = { y = 0, x = x, w = w, parts = {} }
	function c.Head(text, size, color, w)
		local fs = Line(page, page, c.x, c.y, w or c.w, size or 18, color or INK, MORPHEUS)
		fs:SetText(text)
		c.parts[#c.parts + 1] = fs
		c.y = c.y + (size or 18) + 5
		return fs
	end
	function c.Para(text, size, color, gap)
		local fs = Text(page, size or 13, color or INK)
		fs:SetPoint("TOPLEFT", page, "TOPLEFT", c.x, -c.y)
		fs:SetWidth(c.w); fs:SetWordWrap(true); fs:SetJustifyV("TOP")
		fs:SetSpacing(2)
		fs:SetText(text)
		local h = fs:GetStringHeight()
		-- (a client that can't measure it yet: a generous guess, 0.6 of the size a letter)
		if type(h) ~= "number" or h < (size or 13) then h = math.ceil(#text * (size or 13) * 0.6 / c.w) * ((size or 13) * 1.2 + 2) end
		h = floor(h + 0.99)
		fs:SetHeight(h)
		c.parts[#c.parts + 1] = fs
		c.y = c.y + h + (gap or 10)
		return fs
	end
	return c
end

-- An icon with the game's frame round it (the white icon frame, tinted bronze-gold).
local function Icon(parent, rel, x, y, size, beast, point)
	local t = Tex(parent, "ARTWORK")
	t:SetTexture(BEASTS[beast].icon); t:SetTexCoord(CROP[1], CROP[2], CROP[3], CROP[4])
	t:SetSize(size, size); t:SetPoint(point or "TOPLEFT", rel, "TOPLEFT", x, -y)
	local fr = Tex(parent, "ARTWORK", 2)
	fr:SetTexture("Interface\\Common\\WhiteIconFrame"); fr:SetVertexColor(FRAME[1], FRAME[2], FRAME[3])
	fr:SetAllPoints(t)
	t.frame = fr
	return t
end
-- The action bar's slot under an icon: UI-Quickslot2's dark ring (39 of its 64 px) just round it.
local function Slot(parent, icon, size)
	local s = Tex(parent, "BORDER", 3)
	s:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	local k = size * 64 / 39
	s:SetSize(k, k); s:SetPoint("CENTER", icon, "CENTER", 0, 0)
	return s
end
-- The game's proc glow round an icon (IconAlert's gold ring, as the commentator's spell icons use
-- it: 0.0078-0.5078 x 0.2773-0.5273, less 4 px of its faint outer fade), its ring on the icon's edge.
local ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local function Glow(parent, icon, size, pulse)
	local pad = 9 * (size + 2) / 38 - 1
	local g = Tex(parent, "OVERLAY", 1)
	g:SetTexture(ALERT); g:SetTexCoord(5 / 128, 61 / 128, 75 / 256, 131 / 256)
	g:SetBlendMode("ADD")
	g:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad); g:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
	g:Hide()
	if pulse then
		g.pulse = g:CreateAnimationGroup()
		g.pulse:SetLooping("BOUNCE")
		local a = g.pulse:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.8)
	end
	return g
end
local function Lit(g, on)
	g:SetShown(on)
	local pulse = rawget(g, "pulse")
	if pulse then if on then pulse:Play() else pulse:Stop() end end
end

-- The tooltip's border round a card (a BackdropTemplate frame over it), tinted; a client without
-- BackdropTemplate gets thin carved lines instead.
local function Edge(parent, w, h)
	local ok, e = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
	if ok and e and e.SetBackdrop then
		e:SetAllPoints()
		e:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		e:SetFrameLevel(parent:GetFrameLevel() + 1)
		return function(c) e:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1) end, e
	end
	local lines = {}
	for _, r in ipairs({ { 0, 0, w, 2 }, { 0, h - 2, w, 2 }, { 0, 0, 2, h }, { w - 2, 0, 2, h } }) do
		lines[#lines + 1] = Box(parent, parent, r[1], r[2], r[3], r[4], EDGE, "BORDER", 4)
	end
	return function(c) for _, t in ipairs(lines) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end end
end

---------------------------------------------------------------------------
-- The letter: the first time the table opens in a session (and /oly lottery letter). Not the
-- King's: nobody signs it.
---------------------------------------------------------------------------

local LETTER_TITLE = "The Menagerie Lottery"
local LETTER = {
	"Okay, listen. Every day there are 25 beasts on the table, from the Mechanostrider to the Kodo. You pick one. You put gold on it from your wallet. That's it, that's the whole skill part.",
	"At the draw, five numbers get rolled in front of everyone. Each one is four digits, and the last two digits say which beast it is. Every winning ticket gets its stake back once. The first four places pay 50%, 25%, 15% and 10% of the profit pool; fifth place is refund-only.",
	"A profit share nobody claimed stays for tomorrow. The guild keeps 6% only of profit actually paid, never of a returned stake or rollover. These are Olympus's table rules, not official jogo-do-bicho rules.",
	"Good luck. You'll need it.",
}
Bicho.LETTER_TITLE, Bicho.LETTER = LETTER_TITLE, LETTER

local function BuildLetter()
	letter = Parchment("OlympusArenaGamesLotteryLetter", PW, 400)
	letter.title = Line(letter, letter, 44, 26, PW - 88, 24, INK, MORPHEUS, "CENTER")
	letter.title:SetText(LETTER_TITLE)
	-- three of the beasts it names, small, under the title
	letter.icons = {}
	for i, n in ipairs({ 1, 17, 25 }) do letter.icons[i] = Icon(letter, letter, PW / 2 - 51 + (i - 1) * 36, 60, 30, n) end
	Break(letter, letter, 34, 96, PW - 68, 12)
	local c = Flow(letter, 34, PW - 68)
	c.y = 116
	letter.paras = {}
	for i, p in ipairs(LETTER) do letter.paras[i] = c.Para(p, 14, INK, i < #LETTER and 11 or 14) end
	letter.ok = Button(letter, "To the table", 150, 32, function() letter:Hide() end)
	letter.ok:SetPoint("TOP", letter, "TOPLEFT", PW / 2, -c.y)
	letter:SetHeight(c.y + 32 + 22)
end

---------------------------------------------------------------------------
-- How to play: the lab's one pop-up at Bones's How to play's size, centred over the table, a
-- strata above it; two pages (the rules, the payout) behind the game's tabs, each in two columns,
-- with a worked example that Bicho.Settle computes. Got it, the X or Escape close it; it opens
-- again on the page it was left at.
---------------------------------------------------------------------------

-- The worked example: 1,000g on the table, 100g of it on the Sheep (yours 40g, a practice
-- bettor's 60g), and the head's last two digits the Sheep's.
local EXAMPLE = {
	draw = { 7, 1, 3, 4, 6 }, milhar = 4827,
	bets = { { "you", 7, 40 * GOLD, "example.a" }, { "Practice bettor 3", 7, 60 * GOLD, "example.b" },
		{ "Practice bettor 5", 14, 500 * GOLD, "example.c" }, { "Practice bettor 8", 2, 250 * GOLD, "example.d" },
		{ "Practice bettor 9", 25, 150 * GOLD, "example.e" } },
}
function Bicho.Example()
	local head = EXAMPLE.draw[1]
	local r = assert(Bicho.Settle(EXAMPLE.bets, EXAMPLE.draw, 0, FEE_BP))
	local yours = EXAMPLE.bets[1][3]
	return {
		milhar = ("%04d"):format(EXAMPLE.milhar), ending = ("%02d"):format(EXAMPLE.milhar % 100), beast = head,
		pot = r.pot, onHead = r.onHead, lost = r.won, fee = r.fee, share = r.share, yours = yours,
		percent = floor(yours * 100 / r.onHead + 0.5), gain = r.payouts[1] - yours, back = r.payouts[1], r = r,
	}
end

local function GuidePage(k)
	for i, pg in ipairs(guide.pages) do
		pg:SetShown(i == k)
		guide.tabs[i]:SetSelected(i == k)
	end
	if S.page ~= k then Sound("page") end
	S.page = k
end

-- The two columns, inside the parchment's torn rims (Bones's: 32 in from the left, 40 from
-- the right), and the pages' top.
local LX, LW, RX, RW, TOP = 40, 262, 324, 312, 108

local function BuildGuide()
	local GW, GH = GUIDE_W, GUIDE_H
	guide = Parchment("OlympusArenaGamesLotteryGuide", GW, GH)
	guide.title = Line(guide, guide, 60, 18, GW - 120, 24, INK, MORPHEUS, "CENTER")
	guide.title:SetText("How to play the Lottery")
	guide.tabs, guide.pages = {}, {}
	-- (The deal first: the first-use letter is How to play's first tab now, the owner's call
	-- 2026-09-30; then the rules and the payout.)
	local names = { "The deal", "The rules", "The payout" }
	for k, name in ipairs(names) do
		guide.tabs[k] = ns.Games.InkTab(guide, name, 132, function() GuidePage(k) end) -- (the games' one tab)
		guide.tabs[k]:SetPoint("TOPLEFT", guide, "TOPLEFT", GW / 2 - (#names * 136 - 4) / 2 + (k - 1) * 136, -50)
		local pg = CreateFrame("Frame", nil, guide)
		pg:SetPoint("TOPLEFT", 0, 0); pg:SetSize(GW, GH)
		guide.pages[k] = pg
	end
	Break(guide, guide, 36, 84, GW - 80, 12)
	local ex = Bicho.Example()
	local sheep = BEASTS[ex.beast]
	-- The rules: the goal and a day at the table on the left; the draw, with its example, and the
	-- head on the right
	-- The deal: the letter's words, three of its beasts over them.
	local deal = guide.pages[1]
	deal.icons = {}
	for i, n in ipairs({ 1, 17, 25 }) do deal.icons[i] = Icon(deal, deal, GW / 2 - 51 + (i - 1) * 36, 100, 30, n) end
	local dc = Flow(deal, 60, GW - 120)
	dc.y = 146
	deal.paras = {}
	for i, para in ipairs(LETTER) do deal.paras[i] = dc.Para(para, 14, INK, i < #LETTER and 11 or 14) end
	local pg = guide.pages[2]
	local c = Flow(pg, LX, LW)
	c.y = TOP
	c.Head("The goal", 20)
	c.Para("Pick beasts that may appear in any of the five places. Bet on as many as you like, from the practice wallet the games share.", 14, INK, 14)
	c.Head("A day at the table", 20)
	pg.steps = {}
	for i, step in ipairs({
		"Click a beast's card: it wears a gold border.",
		"Type a stake and press Enter, or step it with - and + and press Bet.",
		"Draw now closes the bets: your five /roll, one by one, right here.",
		"Next draw starts a new day, with a new pot.",
	}) do
		pg.steps[i] = Line(pg, pg, LX, c.y, 18, 14, NUMBER)
		pg.steps[i]:SetText(i .. ".")
		c.x, c.w = LX + 20, LW - 20
		c.Para(step, 14, INK, 8)
		c.x, c.w = LX, LW
	end
	local h1 = c.y
	c = Flow(pg, RX, RW)
	c.y = TOP
	c.Head("The draw", 20)
	c.Para("Five prizes, each your own /roll 1-10000 (10000 reads 0000). The last two digits give the beast:", 14, INK, 8)
	-- the example: the number (its last two digits red) » the ending » the beast that owns it
	local y = c.y
	pg.example = {
		number = Line(pg, pg, RX, y + 7, 76, 28, INK),
		arrow1 = Line(pg, pg, RX + 80, y + 14, 14, 18, SOFT),
		ending = Line(pg, pg, RX + 96, y + 10, 30, 22, RED),
		arrow2 = Line(pg, pg, RX + 128, y + 14, 14, 18, SOFT),
		icon = Icon(pg, pg, RX + 146, y + 2, 40, ex.beast),
		num = Line(pg, pg, RX + 194, y + 3, 22, 16, NUMBER),
		name = Line(pg, pg, RX + 218, y + 3, RW - 218, 16, INK, MORPHEUS),
		owns = Line(pg, pg, RX + 194, y + 25, RW - 194, 13, SOFT),
	}
	pg.example.number:SetText(ex.milhar:sub(1, 2) .. Color(HEX.red, ex.milhar:sub(3, 4)))
	pg.example.arrow1:SetText("\194\187"); pg.example.arrow2:SetText("\194\187")
	pg.example.ending:SetText(ex.ending)
	pg.example.num:SetText(("%02d"):format(ex.beast))
	pg.example.name:SetText(sheep.name)
	local dz = Bicho.Dezenas(ex.beast)
	for i, d in ipairs(dz) do if d == ex.ending then dz[i] = Color(HEX.red, d) end end
	pg.example.owns:SetText("owns " .. table.concat(dz, " "))
	c.y = y + 54
	pg.kodo = Icon(pg, pg, RX, c.y, 32, 25)
	c.x, c.w = RX + 42, RW - 42
	c.y = c.y + 8
	c.Para("The Kodo (25th) owns 97, 98, 99 and 00.", 14, SOFT, 18)
	c.x, c.w = RX, RW
	c.Head("Five places", 20)
	c.Para("Winning tickets get their stake back once. Profit is split by place: 50%, 25%, 15%, 10%; fifth is refund-only.", 14, INK, 0)
	h1 = max(h1, c.y)
	-- The payout: who gets what, and nobody on the head, on the left; the example's ledger on the right
	pg = guide.pages[3]
	c = Flow(pg, LX, LW)
	c.y = TOP
	c.Head("Who gets what", 20)
	c.Para("Each winning ticket gets its stake back once. Each claimed place's net profit is split by stake. Duplicate beasts may claim several places without a second refund.", 14, INK, 14)
	c.Head("An unclaimed place?", 20)
	c.Para("That place's gross profit rolls over. The 6% applies once to aggregate profit paid, never to refunds or rollover.", 14, INK, 0)
	local h2 = c.y
	c = Flow(pg, RX, RW)
	c.y = TOP
	c.Head("An example", 20, nil, 110)
	pg.exIcon = Icon(pg, pg, RX + 116, c.y - 28, 24, ex.beast)
	-- a small ledger: what each step is, its amount at the right
	local rows = {
		{ "On the table", Coins(ex.pot) },
		{ ("On the %s (yours %s)"):format(sheep.name, Coins(ex.yours)), Coins(ex.onHead) },
		{ "Profit pool", Coins(ex.lost) },
		{ "Claimed first-place half", Coins(ex.r.grossProfit) },
		{ "The guild's 6% of that", "-" .. Coins(ex.fee) },
		{ ("Your %d%% of it"):format(ex.percent), Coins(ex.gain) },
		{ "Your stake back", Coins(ex.yours) },
		{ "You get", Coins(ex.back) },
	}
	pg.ledger = {}
	for i, row in ipairs(rows) do
		local last = i == #rows
		local ry = c.y + (i - 1) * 20 + (last and 5 or 0)
		if last then Box(pg, pg, RX, ry - 4, RW, 1, { 0.25, 0.13, 0.04, 0.4 }) end
		local color = last and GREEN or i == 4 and RED or INK
		local l = Line(pg, pg, RX + 4, ry, RW - 128, last and 15 or 14, color)
		local a = Line(pg, pg, RX + RW - 124, ry, 120, last and 15 or 14, color, nil, "RIGHT")
		l:SetText(row[1]); a:SetText(row[2])
		pg.ledger[i] = { label = l, amount = a }
	end
	c.y = c.y + #rows * 20 + 12
	c.Para("Largest remainders assign every copper deterministically.", 14, SOFT, 0)
	h2 = max(h2, c.y)
	guide.heights = { h1, h2 }
	-- the pages' text in the middle of the parchment, between the tabs and Got it
	local off = max(0, floor((GH - 84 - max(h1, h2)) / 2))
	for _, page in ipairs(guide.pages) do page:ClearAllPoints(); page:SetPoint("TOPLEFT", guide, "TOPLEFT", 0, -off) end
	guide.offset = off
	-- Got it at the bottom, as Bones's
	Break(guide, guide, 36, GH - 70, GW - 80, 12)
	guide.ok = Button(guide, "Got it", 140, 32, function() guide:Hide() end)
	guide.ok:SetPoint("TOP", guide, "TOPLEFT", GW / 2, -(GH - 52))
	GuidePage(S.page)
end

---------------------------------------------------------------------------
-- The draw, inside the table: from Draw now to Next draw the grid gives its place to the result.
-- On the left the five prizes as the real slip lists them (position, the four digits on their
-- tiles, the beast), filled one at a time; on the right the head's card, big, and who shares it;
-- under them your bets (one line a beast: what each paid or lost) and your day (what you bet, what
-- you won or lost to the copper, the wallet after it counting, the guild's 6%).
---------------------------------------------------------------------------

-- Where each part is (from the window's top left, y down), all in the grid's area.
local RY = GY + 4                                   -- the view's top
local PROW0, PROWH, PRW = RY + 60, 58, 404          -- the first prize's row, a row, its width
local TILE, TSTEP, TX = 36, 40, 60                  -- a digit's tile, the step between tiles, the first tile's x
local PICON, PIX = 44, 226                          -- a prize's image and its x in the row
local HX = GX + PRW + 16                            -- the head's card: its x, its width to the grid's right
local HW = W - GX - HX
local HH = PROW0 + 5 * PROWH - 4 - RY               -- its height, level with the last prize
local BIG = 104                                     -- the head's image on its card
local LOW_Y = PROW0 + 5 * PROWH + 6                 -- the break over your bets and your day
local LINES = 4                                     -- your bets, a line a beast (the last one sums the rest)
local HLINES = 5                                    -- who shares the head, a line each (the last one sums the rest)

local function BuildResult()
	res = CreateFrame("Frame", nil, win)
	res:SetAllPoints(); res:SetFrameLevel(win:GetFrameLevel() + 2)
	res.title = Line(res, win, GX, RY, 220, 24, INK, MORPHEUS)
	res.title:SetText("The Draw")
	res.sub = Line(res, win, GX, RY + 34, PRW, 13, SOFT)
	-- the five prizes
	res.rows = {}
	for k = 1, PRIZES do
		local row = CreateFrame("Frame", nil, res)
		row:SetPoint("TOPLEFT", win, "TOPLEFT", GX, -(PROW0 + (k - 1) * PROWH)); row:SetSize(PRW, PROWH - 4)
		-- the head: a gold band and a red bar at its left
		row.band = row:CreateTexture(nil, "BORDER"); row.band:SetAllPoints(); row.band:SetColorTexture(1, 0.78, 0.28, 0.34)
		row.mark = Box(row, row, 0, 0, 5, PROWH - 4, { RED[1], RED[2], RED[3], 0.9 }, "BORDER", 1)
		row.band:Hide(); row.mark:Hide()
		row.pos = Line(row, row, 12, 6, 44, 20, INK)
		row.pos:SetText(NAMES[k])
		row.tag = Line(row, row, 12, 32, 44, 13, RED)
		row.tile, row.digit, row.flash = {}, {}, {}
		for d = 1, 4 do
			local x = TX + (d - 1) * TSTEP
			-- the last two digits (the ones that give the beast) on warmer tiles
			row.tile[d] = Box(row, row, x, 3, TILE, 46, d >= 3 and { 0.55, 0.16, 0.05, 0.2 } or { 0.35, 0.2, 0.07, 0.16 }, "BORDER", 2)
			Box(row, row, x, 3, TILE, 1, { 0.25, 0.13, 0.04, 0.35 }, "BORDER", 3)
			Box(row, row, x, 48, TILE, 1, { 1, 0.94, 0.78, 0.5 }, "BORDER", 3)
			row.flash[d] = Box(row, row, x, 3, TILE, 46, { 1, 0.85, 0.45, 0.8 }, "ARTWORK", 1)
			row.flash[d]:SetBlendMode("ADD"); row.flash[d]:Hide()
			row.digit[d] = Line(row, row, x, 10, TILE, 30, INK, nil, "CENTER")
			row.digit[d]:SetText("-")
		end
		row.icon = Icon(row, row, PIX, 5, PICON, 1)
		row.icon:Hide(); row.icon.frame:Hide()
		row.glow = Glow(row, row.icon, PICON)
		row.name = Line(row, row, PIX + PICON + 10, 7, PRW - PIX - PICON - 14, 16, INK, MORPHEUS)
		row.group = Line(row, row, PIX + PICON + 10, 31, PRW - PIX - PICON - 14, 13, SOFT)
		res.rows[k] = row
	end
	-- the head's card: a card of the grid, big (its leaf, the tooltip's border, the warm wash, the
	-- image in its slot with the proc glow); who shares it under a break
	local card = CreateFrame("Frame", nil, res)
	card:SetPoint("TOPLEFT", win, "TOPLEFT", HX, -RY); card:SetSize(HW, HH)
	card:SetFrameLevel(res:GetFrameLevel() + 1)
	card.bg = Box(card, card, 3, 3, HW - 6, HH - 6, { 1, 0.96, 0.84, 0.4 }, "BACKGROUND", 1)
	card.wash = Box(card, card, 3, 3, HW - 6, HH - 6, { 1, 0.76, 0.3, 0.34 }, "BACKGROUND", 2)
	card.flash = Box(card, card, 3, 3, HW - 6, HH - 6, { 1, 0.85, 0.45, 1 }, "ARTWORK", 3)
	card.flash:SetBlendMode("ADD"); card.flash:SetAlpha(0)
	card.edge = Edge(card, HW, HH)
	card.num = Line(card, card, 16, 14, 36, 22, NUMBER)
	card.name = Line(card, card, 56, 12, HW - 72, 26, INK, MORPHEUS)
	card.icon = Icon(card, card, 18, 54, BIG, 1)
	card.slot = Slot(card, card.icon, BIG)
	card.glow = Glow(card, card.icon, BIG, true)
	local tx = 18 + BIG + 20
	card.l1 = Line(card, card, tx, 58, HW - tx - 14, 22, RED)
	card.l2 = Line(card, card, tx, 90, HW - tx - 14, 15, SOFT)
	card.l3 = Line(card, card, tx, 114, HW - tx - 14, 15, INK)
	card.l4 = Line(card, card, tx, 138, HW - tx - 14, 13, SOFT)
	Break(card, card, 16, 176, HW - 32, 12)
	card.who = Line(card, card, 16, 192, HW - 32, 18, INK, MORPHEUS)
	card.lines = {}
	for i = 1, HLINES do
		local y = 218 + (i - 1) * 22
		card.lines[i] = { left = Line(card, card, 16, y, HW - 32 - 146, 14, INK), right = Line(card, card, HW - 16 - 142, y, 142, 14, GREEN, nil, "RIGHT") }
	end
	res.card = card
	-- your bets and your day, under a break across the view
	Break(res, win, GX, LOW_Y, W - 2 * GX, 12)
	res.betsHead = Line(res, win, GX, LOW_Y + 16, PRW, 18, INK, MORPHEUS)
	res.betsHead:SetText("Your bets")
	res.lines = {}
	for i = 1, LINES do
		local y = LOW_Y + 44 + (i - 1) * 24
		local e = {}
		e.icon = Tex(res, "ARTWORK"); e.icon:SetSize(18, 18); e.icon:SetPoint("TOPLEFT", win, "TOPLEFT", GX, -y)
		e.icon:SetTexCoord(CROP[1], CROP[2], CROP[3], CROP[4])
		e.left = Line(res, win, GX + 24, y + 1, 226, 14, INK)
		e.right = Line(res, win, GX + 254, y + 1, PRW - 254, 14, INK, nil, "RIGHT")
		res.lines[i] = e
	end
	res.dayHead = Line(res, win, HX, LOW_Y + 16, HW, 18, INK, MORPHEUS)
	res.dayHead:SetText("Your day")
	res.bet = Line(res, win, HX, LOW_Y + 45, HW, 14, INK)
	res.won = Line(res, win, HX, LOW_Y + 67, HW, 24, INK)
	res.wallet = Line(res, win, HX, LOW_Y + 102, HW, 16, INK)
	res.guild = Line(res, win, HX, LOW_Y + 128, HW, 13, SOFT)
	res:Hide()
end

local function RowBeast(row, n, milhar)
	row.icon:SetTexture(BEASTS[n].icon); row.icon:Show(); row.icon.frame:Show()
	row.name:SetText(BEASTS[n].name)
	row.group:SetText(("%02d \194\183 group %02d"):format(milhar % 100, n))
end
local function RowDigits(row, milhar)
	local digits = ("%04d"):format(milhar)
	for d = 1, 4 do
		row.digit[d]:SetText(digits:sub(d, d)); row.digit[d]:SetAlpha(1); row.flash[d]:Hide()
		Ink(row.digit[d], d >= 3 and RED or INK)
	end
end
local function RowIcon(row)
	row.icon:SetSize(PICON, PICON); row.icon:SetAlpha(1)
	row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", PIX, -5)
end
local function RowHead(row)
	row.band:Show(); row.mark:Show(); row.tag:SetText("1st")
	Lit(row.glow, true)
end

-- A prize drawn but not shown yet (the table was closed while it was being revealed): at once.
local function Settled(k)
	local row, p = res.rows[k], S.prizes[k]
	if not p or p.shown then return end
	Stop("spin" .. k); Stop("settle" .. k); Stop("pop" .. k)
	RowDigits(row, p.milhar)
	RowBeast(row, p.beast, p.milhar)
	RowIcon(row)
	p.shown = true
	if k == 1 then RowHead(row) end
end

-- A new draw: the five rows empty, the head's card waiting.
local function ClearResult()
	for k, row in ipairs(res.rows) do
		Stop("spin" .. k); Stop("settle" .. k); Stop("pop" .. k)
		row.band:Hide(); row.mark:Hide(); row.tag:SetText(""); Lit(row.glow, false)
		for d = 1, 4 do row.digit[d]:SetText("-"); row.digit[d]:SetAlpha(0.45); Ink(row.digit[d], INK); row.flash[d]:Hide() end
		row.icon:Hide(); row.icon.frame:Hide(); RowIcon(row)
		row.name:SetText(""); row.group:SetText("")
	end
	Stop("headIn"); res.card.flash:SetAlpha(0)
end

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------

-- The pick's mark on its card: the quest item's gold border (TEXTURE_ITEM_QUEST_BORDER, as the
-- bags draw it round a quest item: a gold line on its edge and a soft glow inside it) round the
-- whole card, cut in nine so its corners keep their shape and its sides stretch, over the card's
-- edge; on it the same border added in light (ADD), breathing: the pick shines while it is the
-- pick. The mouse's highlight is something else, the game's pale ButtonHilight-Square over the
-- whole card, and it leaves the mark as it is. Made for a card the first time it is picked.
local QUEST_BORDER = "Interface\\ContainerFrame\\UI-Icon-QuestBorder"
local QB, QC = 64, 16                      -- the file's size, and a corner's
local function NineSlice(f, w, h, blend, sub)
	local xs, ys = { { 0, QC }, { QC, w - 2 * QC }, { w - QC, QC } }, { { 0, QC }, { QC, h - 2 * QC }, { h - QC, QC } }
	local cut = { { 0, QC }, { QC, QB - QC }, { QB - QC, QB } }
	local parts = {}
	for i = 1, 3 do
		for j = 1, 3 do
			if i ~= 2 or j ~= 2 then     -- (the middle is empty: the card shows through)
				local t = f:CreateTexture(nil, "OVERLAY", nil, sub)
				t:SetTexture(QUEST_BORDER)
				t:SetTexCoord(cut[i][1] / QB, cut[i][2] / QB, cut[j][1] / QB, cut[j][2] / QB)
				t:SetBlendMode(blend)
				t:SetPoint("TOPLEFT", f, "TOPLEFT", xs[i][1], -ys[j][1]); t:SetSize(xs[i][2], ys[j][2])
				parts[#parts + 1] = t
			end
		end
	end
	return parts
end
local function PickMark(c)
	local f = CreateFrame("Frame", nil, c)
	f:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0); f:SetSize(CW, CH)
	f:SetFrameLevel(c:GetFrameLevel() + 3)   -- over the card's edge (+1)
	f.border = NineSlice(f, CW, CH, "BLEND", 1)
	f.shine = CreateFrame("Frame", nil, f)
	f.shine:SetAllPoints()
	f.shine.parts = NineSlice(f.shine, CW, CH, "ADD", 2)
	f.pulse = f.shine:CreateAnimationGroup()
	f.pulse:SetLooping("BOUNCE")
	local a = f.pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(0.9); a:SetToAlpha(0.15); a:SetDuration(0.9)
	f:Hide()
	return f
end
-- The mark on the pick's card only: shown (its shine breathing) or hidden.
local function Marked(c, on)
	if on and not rawget(c, "mark") then c.mark = PickMark(c) end
	if not rawget(c, "mark") or rawget(c, "marked") == on then return end
	c.marked = on
	c.mark:SetShown(on)
	if on then c.mark.pulse:Play() else c.mark.pulse:Stop() end
end

-- A card: the number in its corner, the name, the image in the game's slot and icon frame, the
-- four endings two by two, the pool on it and your stake on it.
local function Card(n)
	local col, row = (n - 1) % 5, floor((n - 1) / 5)
	local c = CreateFrame("Button", nil, win)
	c:SetSize(CW, CH)
	c:SetPoint("TOPLEFT", win, "TOPLEFT", GX + col * (CW + GAP), -(GY + row * (CH + GAP)))
	c:SetFrameLevel(win:GetFrameLevel() + 2)
	c.n = n
	-- the card: a lighter leaf on the page in the tooltip's border; picked: a warm wash
	c.bg = Box(c, c, 3, 3, CW - 6, CH - 6, { 1, 0.96, 0.84, 0.4 }, "BACKGROUND", 1)
	c.wash = Box(c, c, 3, 3, CW - 6, CH - 6, { 1, 0.76, 0.3, 0.34 }, "BACKGROUND", 2)
	c.wash:Hide()
	c.edge = Edge(c, CW, CH)
	c.edge(EDGE)
	c.num = Line(c, c, 11, 8, 24, 15, NUMBER)
	c.num:SetText(("%02d"):format(n))
	c.name = Line(c, c, 35, 8, CW - 42, 15, INK, MORPHEUS)
	c.name:SetText(BEASTS[n].name)
	c.icon = Icon(c, c, 10, 29, ICON, n)
	c.slot = Slot(c, c.icon, ICON)
	c.dz = { Line(c, c, 76, 28, CW - 80, 14, SOFT), Line(c, c, 76, 45, CW - 80, 14, SOFT) }
	c.pool = Line(c, c, 76, 62, CW - 80, 13, INK)
	c.you = Line(c, c, 76, 78, CW - 80, 13, GREEN)
	c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	c:SetScript("OnClick", function() Bicho.Pick(n) end)
	return c
end

-- A pool that moved lights up a moment (green, then back to ink).
local function Flash(n)
	local fs = cards[n].pool
	Animate("flash" .. n, 0.9, function(u)
		local k = 1 - u
		fs:SetTextColor(INK[1] + (GREEN[1] - INK[1]) * k, INK[2] + (GREEN[2] - INK[2]) * k, INK[3] + (GREEN[3] - INK[3]) * k)
	end)
end

local function BuildHeader()
	header.title = Line(win, win, GX, 14, 220, 30, INK, MORPHEUS)
	header.title:SetText("Lottery")
	header.sub = Line(win, win, GX + 1, 55, 236, 13, SOFT)
	-- the pot
	header.potLabel = Line(win, win, 264, 12, 276, 13, SOFT, nil, "CENTER")
	header.pot = Line(win, win, 264, 28, 276, 22, INK, nil, "CENTER")
	header.carried = Line(win, win, 264, 55, 276, 14, SOFT, nil, "CENTER")
	-- your bets today; after the draw, your result
	header.mineLabel = Line(win, win, 548, 12, 222, 13, SOFT, nil, "RIGHT")
	header.mine = Line(win, win, 548, 28, 222, 22, INK, nil, "RIGHT")
	header.mineSub = Line(win, win, 548, 55, 222, 13, SOFT, nil, "RIGHT")
	Break(win, win, GX, 76, W - 2 * GX, 12)
end

local function StakeBox(x, y)
	local ok, box = pcall(CreateFrame, "EditBox", nil, win, "InputBoxTemplate")
	if not ok or not box then return nil end
	box:SetSize(50, 22)
	box:SetPoint("TOPLEFT", win, "TOPLEFT", x, -y)
	box:SetFrameLevel(win:GetFrameLevel() + 5)
	box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(4); box:SetJustifyH("CENTER")
	-- Enter bets (the design); typing sets the stake
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Bicho.Bet() end)
	box:SetScript("OnTextChanged", function(self, typed) if typed then Bicho.SetStake(tonumber(self:GetText()) or 0) end end)
	box:HookScript("OnEditFocusLost", function() Refresh() end)
	return box
end

local function BuildBar()
	-- the footer's compartment: its line and wash (the lab's, as Bones's)
	win.foot = ns.Games.Footer(win, FOOT_Y, H - 10 - FOOT_Y, 10)
	local y = ROW_A
	-- the counter: your pick, the stake, Bet
	bar.icon = Icon(win, win, GX, y, 36, 1)
	bar.num = Line(win, win, GX + 44, y, 26, 17, NUMBER)
	bar.pick = Line(win, win, GX + 70, y, 170, 17, INK, MORPHEUS)
	bar.pickNone = Line(win, win, GX + 44, y + 1, 196, 15, INK)
	bar.pickSub = Line(win, win, GX + 44, y + 21, 196, 13, SOFT)
	bar.minus = Button(win, "-", 32, 32, function() Bicho.Step(-1) end)
	bar.minus:SetPoint("TOPLEFT", win, "TOPLEFT", 268, -(y + 2))
	bar.box = StakeBox(311, y + 7)
	bar.stake = Line(win, win, 306, y + 9, 56, 15, INK, nil, "CENTER")      -- (a client without an EditBox)
	bar.coin = Tex(win, "ARTWORK"); bar.coin:SetTexture(COINS[1]); bar.coin:SetSize(14, 14)
	bar.coin:SetPoint("TOPLEFT", win, "TOPLEFT", 366, -(y + 11))
	bar.plus = Button(win, "+", 32, 32, function() Bicho.Step(1) end)
	bar.plus:SetPoint("TOPLEFT", win, "TOPLEFT", 386, -(y + 2))
	-- (Bet: the bar's right side, by the draw's button, below: the arena's rule for every game.)
	bar.bet = Button(win, "Bet", 150, 32, function() Bicho.Bet() end)
	-- under it: a hint on the left, the practice bettors on the right
	-- (8 px at least above the games' bar, 2026-09-30)
	bar.hint = Line(win, win, GX, y + 40, 330, 13, SOFT)
	bar.feed = Line(win, win, W - GX - 400, y + 40, 400, 13, SOFT, nil, "RIGHT")
	-- the draw and the announcement, on a warm band in the counter's place: the head's image in
	-- the game's proc glow, what came out, who shares what
	bar.band = Box(win, win, GX - 4, FOOT_Y + 6, W - 2 * GX + 8, ROW_B - FOOT_Y - 20, { 1, 0.78, 0.3, 0.26 }, "BORDER", 2)
	bar.flash = Box(win, win, GX - 4, FOOT_Y + 6, W - 2 * GX + 8, ROW_B - FOOT_Y - 20, { 1, 0.85, 0.45, 1 }, "BORDER", 3)
	bar.flash:SetBlendMode("ADD"); bar.flash:SetAlpha(0)
	bar.band:Hide(); bar.flash:Hide()
	bar.headIcon = Icon(win, win, GX + 6, FOOT_Y + 14, 44, 1)
	bar.headGlow = Glow(win, bar.headIcon, 44, true)
	bar.title = Line(win, win, GX, FOOT_Y + 14, 400, 19, RED)
	bar.titleSub = Line(win, win, GX, FOOT_Y + 40, 400, 14, INK)
	bar.title.oy, bar.titleSub.oy = FOOT_Y + 14, FOOT_Y + 40
	-- the window's buttons, as Bones's: How to play and the wallet on the left, the main
	-- action on the right
	local F = ns.Games.FOOT
	-- The games' one bar (Games.Bar, 2026-09-30): the coin and the balance, How to play; on the
	-- right Bet and the draw's button (Draw now, Next draw).
	bar.draw = Button(win, "Draw now (practice)", 200, 32, function()
		if S.phase == "result" then Bicho.NextDay() elseif S.phase == "draw" then NextPrize() else Bicho.Draw() end
	end)
	win.bar = ns.Games.Bar(win, { y = H - 10 - ns.Games.BAR.H, inset = 10,
		help = function() if guide:IsShown() then guide:Hide() else Show(guide) end end })
	win.walletButton, bar.help = win.bar.wallet, win.bar.help
	win.bar.Place({ bar.draw, bar.bet })
end

local function PoolText(fs, p)
	if p <= 0 then fs:SetText(""); return end
	Fit(fs, "Pool " .. Coins(p), Coins(p))
end

-- The announcement's words: the head's four digits and its beast (a shorter form when a long name
-- would run past the line).
local function Announce(fs, milhar, name)
	Fit(fs, ("First place: %04d, the %s!"):format(milhar, name), ("1st %04d: the %s!"):format(milhar, name))
end

-- Who bet on a beast, one entry a bettor (all his bets on it together): you first, then the biggest
-- stakes. back: what the settlement pays him (once drawn).
local function Bettors(n, r)
	local list, at = {}, {}
	for i, b in ipairs(S.bets) do
		if b[2] == n then
			local e = at[b[1]]
			if not e then e = { who = b[1], stake = 0, back = r and 0 or nil }; at[b[1]] = e; list[#list + 1] = e end
			e.stake = e.stake + b[3]
			if r then e.back = e.back + (r.payouts[i] or 0) end
		end
	end
	table.sort(list, function(a, b)
		if (a.who == "you") ~= (b.who == "you") then return a.who == "you" end
		if a.stake ~= b.stake then return a.stake > b.stake end
		return a.who < b.who
	end)
	return list
end

-- The first-place card: waiting for the first draw, then its beast, tickets and settlement. A
-- missing first-place winner carries only that place's 50% profit tranche, not the whole pot.
local function HeadCard(head, p1, r, pool)
	local card = res.card
	local out = head ~= nil
	card.edge(out and LIT or EDGE)
	card.wash:SetShown(out)
	card.num:SetShown(out)
	card.icon.frame:SetShown(out)
	for _, l in ipairs(card.lines) do l.left:SetText(""); l.right:SetText("") end
	if not out then
		card.name:SetText("Five-place draw")
		card.icon:SetTexture(ICONS .. "INV_Misc_QuestionMark"); card.icon:SetAlpha(0.55)
		card.l1:SetText("The 1st prize"); Ink(card.l1, INK)
		card.l2:SetText("claims the 50% tranche.")
		card.l3:SetText("All five drawn beasts")
		card.l4:SetText("refund tickets once.")
		card.who:SetText("")
	else
		card.num:SetText(("%02d"):format(head))
		card.name:SetText(BEASTS[head].name)
		card.icon:SetTexture(BEASTS[head].icon); card.icon:SetAlpha(1)
		card.l1:SetText(("1st prize %04d"):format(p1.milhar)); Ink(card.l1, RED)
		local ending, dz = ("%02d"):format(p1.milhar % 100), Bicho.Dezenas(head)
		for i, d in ipairs(dz) do if d == ending then dz[i] = Color(HEX.red, d) end end
		card.l2:SetText("owns " .. table.concat(dz, " "))
		local list = Bettors(head, r)
		card.l3:SetText(pool[head] > 0 and ("Pool " .. Coins(pool[head])) or "No gold on it")
		card.l4:SetText(#list > 0 and ("%d bettor%s"):format(#list, #list == 1 and "" or "s") or "nobody on it")
		if #list == 0 then
			card.who:SetText("No first-place tickets")
			card.lines[1].left:SetText("Its 50% profit tranche rolls over"); Ink(card.lines[1].left, INK)
			card.lines[2].left:SetText(r and ("to day %d:"):format(S.day + 1) or "to the next day."); Ink(card.lines[2].left, INK)
			if r then card.lines[2].right:SetText(Coins(r.tranches[1].carry)) end
		else
			card.who:SetText("Tickets on this beast")
			if #list > HLINES then
				local rest = { more = #list - HLINES + 1, stake = 0, back = r and 0 or nil }
				for i = HLINES, #list do rest.stake = rest.stake + list[i].stake; if r then rest.back = rest.back + list[i].back end end
				for i = #list, HLINES, -1 do list[i] = nil end
				list[HLINES] = rest
			end
			for i, e in ipairs(list) do
				local l = card.lines[i]
				if e.more then l.left:SetText(("%d more \194\183 %s"):format(e.more, Coins(e.stake)))
				elseif e.who == "you" then l.left:SetText("You \194\183 " .. Coins(e.stake))
				else Fit(l.left, ("%s \194\183 %s"):format(e.who, Coins(e.stake)), ("%s \194\183 %s"):format(e.who:gsub("^Practice b", "B"), Coins(e.stake))) end
				Ink(l.left, e.who == "you" and GREEN or INK)
				if e.back then l.right:SetText(Coins(e.back)) end
			end
		end
	end
	if out ~= card.lit then card.lit = out; Lit(card.glow, out) end
end

-- Under the prizes: your bets, one line a beast (the head's first, then the biggest), what each
-- paid or lost; your day: what you bet, what you won or lost (to the copper), the wallet (counting
-- to what it holds after the draw), the guild's cut.
local function YourDay(head, r)
	local list = MyBeasts(r)
	table.sort(list, function(a, b)
		if (a.n == head) ~= (b.n == head) then return a.n == head end
		if a.stake ~= b.stake then return a.stake > b.stake end
		return a.n < b.n
	end)
	local beasts = #list
	if #list > LINES then
		local rest = { more = #list - LINES + 1, stake = 0, back = 0 }
		for i = LINES, #list do rest.stake, rest.back = rest.stake + list[i].stake, rest.back + list[i].back end
		for i = #list, LINES, -1 do list[i] = nil end
		list[LINES] = rest
	end
	for i, e in ipairs(res.lines) do
		local b = list[i]
		e.icon:SetShown(b ~= nil and b.n ~= nil); e.left:SetText(""); e.right:SetText("")
		if b then
			if b.n then e.icon:SetTexture(BEASTS[b.n].icon); Fit(e.left, ("%s \194\183 %s"):format(BEASTS[b.n].name, Coins(b.stake)), ("%02d \194\183 %s"):format(b.n, Coins(b.stake)))
			else e.left:SetText(("%d more beasts \194\183 %s"):format(b.more, Coins(b.stake))) end
			Ink(e.left, INK)
			if r then
				if b.back > 0 then Fit(e.right, "back " .. Coins(b.back), Coins(b.back)); Ink(e.right, GREEN)
				else e.right:SetText("lost"); Ink(e.right, RED) end
			end
		elseif i == 1 then
			e.left:SetText(r and "You had no bets today." or "No bets of yours today: just watch.")
			Ink(e.left, SOFT)
		end
	end
	local _, _, _, _, myBets, myTotal = Pools()
	res.bet:SetText(myTotal > 0 and ("Bet today %s on %d beast%s"):format(Coins(myTotal), beasts, beasts == 1 and "" or "s") or "No bets today")
	if r and myTotal > 0 then
		local _, _, gain = MyResult(r)
		-- (the result counts up from nothing the first time it shows for a draw, the dice's count-up)
		if S.countedRound ~= S.round then S.countedRound = S.round; shown.resWon = 0 end
		Count("resWon", res.won, gain, function(c) return c > 0 and ("Won " .. Signed(c)) or c < 0 and ("Lost " .. Signed(c)) or ("Even: " .. Coins(0)) end)
		Ink(res.won, gain > 0 and GREEN or gain < 0 and RED or INK)
	elseif r then
		res.won:SetText("Nothing won, nothing lost"); Ink(res.won, SOFT)
	else
		res.won:SetText("")
	end
	Count("resWallet", res.wallet, S.wallet, function(c) return (r and "Wallet now " or "Wallet ") .. Coins(c) end)
	if r and r.grossProfit > 0 then
		Fit(res.guild, ("The guild's 6%% of paid profit %s: %s; %s rolls over"):format(Coins(r.grossProfit), Coins(r.fee), Coins(r.rollover)),
			("Guild fee %s; carry %s"):format(Coins(r.fee), Coins(r.rollover)))
	elseif r then
		res.guild:SetText(("No paid profit, no fee: %s rolls over."):format(Coins(r.rollover)))
	else
		res.guild:SetText("")
	end
end

function Refresh()
	if not win then return end
	local pool, mine, total, people, myBets, myTotal, myBeasts = Pools()
	local betting, drawing, over = S.phase == "bet", S.phase == "draw", S.phase == "result"
	local r = over and S.result
	-- (the head's card fills in once its row shows the head)
	local p1 = S.prizes[1]
	local head = p1 and p1.shown and p1.beast
	-- the shared wallet, on its button in the footer
	win.walletButton.Refresh()
	-- the header: the day, the pot, your bets (your result once drawn)
	header.sub:SetText(("The Menagerie Lottery, day %d"):format(S.day))
	header.potLabel:SetText(over and "Today's pot (drawn)" or drawing and "Today's pot (bets closed)" or "Today's pot")
	Count("pot", header.pot, total + S.carried, Coins)
	local bettors = ("%d practice bettor%s"):format(people, people == 1 and "" or "s")
	if r and r.rollover > 0 then
		header.carried:SetText(Color(HEX.green, ("%s unclaimed profit rolls to day %d"):format(Coins(r.rollover), S.day + 1)))
	elseif r then
		header.carried:SetText(("paid out to %d winner%s"):format(r.winners, r.winners == 1 and "" or "s"))
	elseif S.carried > 0 then
		header.carried:SetText(Color(HEX.green, "+" .. Coins(S.carried) .. " rolled over") .. " \194\183 " .. bettors)
	else
		header.carried:SetText(bettors .. " \194\183 nothing rolled over")
	end
	SetFont(header.carried, STANDARD_TEXT_FONT, (S.carried > 0 or (r and r.rollover > 0)) and 14 or 13)
	if r then
		local back, lost, gain = MyResult(r)
		header.mineLabel:SetText("Your result today")
		header.mine:SetText(myTotal > 0 and Signed(gain) or Coins(0))
		Ink(header.mine, gain > 0 and GREEN or gain < 0 and RED or INK)
		local parts = {}
		if back > 0 then parts[#parts + 1] = "back " .. Coins(back) end
		if lost > 0 then parts[#parts + 1] = "lost " .. Coins(lost) end
		header.mineSub:SetText(myTotal > 0 and table.concat(parts, " \194\183 ") or "no bets today")
	else
		header.mineLabel:SetText("Your bets today")
		header.mine:SetText(Coins(myTotal))
		Ink(header.mine, INK)
		header.mineSub:SetText(myBets > 0 and ("on %d beast%s (%d bet%s)"):format(myBeasts, myBeasts == 1 and "" or "s", myBets, myBets == 1 and "" or "s")
			or "none yet")
	end
	-- the grid while the bets are open; the draw's result in its place from the draw on
	for n, c in ipairs(cards) do
		c:SetShown(betting)
		local dz = Bicho.Dezenas(n)
		c.dz[1]:SetText(dz[1] .. " " .. dz[2]); c.dz[2]:SetText(dz[3] .. " " .. dz[4])
		PoolText(c.pool, pool[n])
		if not anims["flash" .. n] then Ink(c.pool, INK) end
		if mine[n] > 0 then c.you:SetText("You " .. Coins(mine[n])) else c.you:SetText("") end
		local picked = betting and S.sel == n
		c.edge(picked and LIT or EDGE)
		c.wash:SetShown(picked)
		Marked(c, picked)
		c:EnableMouse(betting)
	end
	res:SetShown(not betting)
	if not betting then
		res.sub:SetText(("Day %d \194\183 your five /roll 1-10000, in order"):format(S.day))
		HeadCard(head, p1, r, pool)
		YourDay(head, r)
	end
	-- the counter
	local picking = betting
	for _, x in ipairs({ bar.icon, bar.icon.frame, bar.num, bar.pick, bar.pickNone, bar.pickSub, bar.minus, bar.plus, bar.bet, bar.coin, bar.hint, bar.feed }) do x:SetShown(picking) end
	if win.bar then win.bar.Relayout() end
	if bar.box then bar.box:SetShown(picking); bar.stake:Hide() else bar.stake:SetShown(picking) end
	bar.headIcon:SetShown(over and head ~= nil); bar.headIcon.frame:SetShown(over and head ~= nil)
	if (over and head ~= nil) ~= bar.lit then bar.lit = over and head ~= nil; Lit(bar.headGlow, bar.lit) end
	bar.band:SetShown(not picking); bar.flash:SetShown(over)
	bar.title:SetShown(not picking); bar.titleSub:SetShown(not picking)
	-- (the announcement beside the head's image; the draw's line where the pick was)
	local tx = over and GX + 62 or GX + 4
	for _, fs in ipairs({ bar.title, bar.titleSub }) do
		fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", win, "TOPLEFT", tx, -fs.oy); fs:SetWidth(W - GX - tx)
	end
	if picking then
		S.stake = max(0, min(S.stake, floor(S.wallet / GOLD)))
		local n = S.sel
		bar.num:SetShown(n ~= nil); bar.pick:SetShown(n ~= nil); bar.pickNone:SetShown(n == nil)
		if n then
			bar.icon:SetTexture(BEASTS[n].icon)
			bar.num:SetText(("%02d"):format(n))
			bar.pick:SetText(BEASTS[n].name)
			bar.pickSub:SetText(table.concat(Bicho.Dezenas(n), " ") .. " \194\183 pool " .. Coins(pool[n]))
			bar.hint:SetText("Type a stake and press Enter, or use - and +.")
		else
			bar.icon:SetTexture(ICONS .. "INV_Misc_QuestionMark")
			bar.pickNone:SetText("Pick a beast")
			bar.pickSub:SetText("Click its card above.")
			bar.hint:SetText("Bet on as many beasts as you like, then Draw.")
		end
		local stake = Stake()
		if bar.box and not bar.box:HasFocus() then bar.box:SetText(tostring(S.stake)) end
		bar.stake:SetText(tostring(S.stake))
		local up
		for _, g in ipairs(STEPS) do if g > S.stake then up = g; break end end
		Set(bar.minus, "-", S.stake > 1)
		Set(bar.plus, "+", up ~= nil and up * GOLD <= S.wallet)
		if not n then Set(bar.bet, "Bet", false)
		elseif stake <= 0 then Set(bar.bet, "Set a stake", false)
		elseif stake > S.wallet then Set(bar.bet, "Not enough gold", false)
		else Set(bar.bet, "Bet " .. Money(stake), true) end
		Set(bar.draw, "Draw now (practice)", true)
		bar.feed:SetText(S.feed or "")
	elseif drawing then
		-- (the prize being drawn stays named until its beast is out)
		local k = S.stalled or S.current or (#S.prizes + 1)
		Ink(bar.title, INK)
		bar.title:SetText(k <= PRIZES and ("Drawing the %s prize..."):format(NAMES[k]) or "The draw is done.")
		bar.titleSub:SetText(S.hint or (S.group and "Your group sees these /roll lines in its chat." or "Each prize is one /roll 1-10000 of your own."))
		if S.stalled then Set(bar.draw, ("Roll the %s prize"):format(NAMES[S.stalled]), true)
		else Set(bar.draw, "Drawing...", false) end
	else
		Ink(bar.title, RED)
		if head then
			bar.headIcon:SetTexture(BEASTS[head].icon)
			Announce(bar.title, p1.milhar, BEASTS[head].name)
		end
		if r and r.winningTickets > 0 then
			bar.titleSub:SetText(("%d winning ticket%s receive%s %s; %s rolls over."):format(r.winningTickets, r.winningTickets == 1 and "" or "s", r.winningTickets == 1 and "s" or "", Coins(r.paid), Coins(r.nextCarry)))
		elseif r then
			bar.titleSub:SetText(("No drawn beast was picked: %s rolls over to day %d."):format(Coins(r.nextCarry), S.day + 1))
		end
		Set(bar.draw, "Next draw", true)
	end
end

---------------------------------------------------------------------------
-- Betting
---------------------------------------------------------------------------

function Bicho.Pick(n)
	if S.phase ~= "bet" or not BEASTS[n] then return end
	S.sel = n
	Sound("pick")
	Refresh()
end

-- The stake: typed (any whole gold, up to what the wallet holds) or stepped through STEPS.
function Bicho.SetStake(g)
	if S.phase ~= "bet" then return end
	S.stake = max(0, min(floor(tonumber(g) or 0), MAX_STAKE))
	Refresh()
end

function Bicho.Step(d)
	if S.phase ~= "bet" then return end
	local to
	if d > 0 then
		for _, g in ipairs(STEPS) do if g > S.stake then to = g; break end end
		if to and to * GOLD > S.wallet then to = nil end
	else
		for i = #STEPS, 1, -1 do if STEPS[i] < S.stake then to = STEPS[i]; break end end
	end
	if to and to ~= S.stake then S.stake = to; Sound("pick") end
	Refresh()
end

function Bicho.Bet()
	if S.phase ~= "bet" or not S.sel then return end
	local stake = Stake()
	if stake <= 0 or stake > S.wallet then return end
	local n = S.sel
	local name = BEASTS[n].name
	Wallet.Move(-stake, ("Lottery day %d: bet on the %s"):format(S.day, name), { ("Lottery day %d: bet, %02d %s"):format(S.day, n, name),
		("Lottery: bet, %02d %s"):format(n, name), ("Bet, %02d %s"):format(n, name) }, "lottery")
	S.ticketSeq = S.ticketSeq + 1
	S.bets[#S.bets + 1] = { "you", n, stake, ("practice.%d.%08d"):format(S.day, S.ticketSeq) }
	Sound("bet")
	Flash(S.sel)
	Refresh()
end

-- The practice bettors: a bet every few seconds while the table is open and the bets are, each
-- on a beast of the day's favourites or any other, 1g to 25g.
local CROWD_STAKES = { 1, 1, 2, 2, 3, 5, 5, 5, 10, 10, 15, 20, 25 }
local function CrowdBet(quiet)
	if S.crowd >= CROWD_MAX then return end
	local n = random() < 0.35 and S.favourites[random(#S.favourites)] or random(#BEASTS)
	local g = CROWD_STAKES[random(#CROWD_STAKES)]
	local who = "Practice bettor " .. random(1, 12)
	S.ticketSeq = S.ticketSeq + 1
	S.bets[#S.bets + 1] = { who, n, g * GOLD, ("practice.%d.%08d"):format(S.day, S.ticketSeq) }
	S.crowd = S.crowd + 1
	S.feed = ("%s: %s on %02d %s"):format(who, Money(g * GOLD), n, BEASTS[n].name)
	if not quiet then Flash(n) end
end

local function Crowd()
	local round = S.round
	C_Timer.After(1.5 + random() * 2.5, function()
		if S.round ~= round or S.phase ~= "bet" or not (win and win:IsShown()) then return end
		CrowdBet()
		Refresh()
		Crowd()
	end)
end

---------------------------------------------------------------------------
-- The draw: your five rolls, one after another, each prize revealed in the table like the real slip
---------------------------------------------------------------------------

local function Spin(k)
	local row, last = res.rows[k], -1
	for d = 1, 4 do row.digit[d]:SetAlpha(1); Ink(row.digit[d], INK) end
	Loop("spin" .. k, function(t)
		local tick = floor(t / 0.06)
		if tick == last then return end
		last = tick
		for d = 1, 4 do row.digit[d]:SetText(tostring(random(0, 9))) end
	end)
	StartSpin()
end

-- The four digits settle left to right like an odometer (the owner's call, 2026-09-30): about a
-- second a prize, each digit still turning slower and slower until it lands, with a click and a
-- flash on its tile (the last two turn red: they give the beast); then the beast comes in with its
-- glow. One driver (Step's OnUpdate) runs it all.
local SETTLE, LAND = 1.0, 0.22
local function Reveal(k, done)
	local row, p = res.rows[k], S.prizes[k]
	local digits = ("%04d"):format(p.milhar)
	Stop("spin" .. k)
	local settled, lastTick = 0, {}
	Animate("settle" .. k, SETTLE, function(u)
		local t = u * SETTLE
		for d = 1, 4 do
			local lands = LAND * d
			if t >= lands then
				if d > settled then
					settled = d
					row.digit[d]:SetText(digits:sub(d, d)); Ink(row.digit[d], d >= 3 and RED or INK); row.flash[d]:Show()
					Sound("pick")
				end
				row.flash[d]:SetAlpha(max(0, 0.8 - (t - lands) * 2.6))
			else
				-- (turning slower as it nears its landing: a new digit every 0.04 s at first, 0.16 s last)
				local step = 0.04 + 0.12 * (t / lands)
				local tick = floor(t / step)
				if tick ~= lastTick[d] then lastTick[d] = tick; row.digit[d]:SetText(tostring(random(0, 9))) end
			end
		end
	end, function()
		RowDigits(row, p.milhar)
		StopSpin()
		Sound("settle")
		RowBeast(row, p.beast, p.milhar)
		local icon = row.icon
		Animate("pop" .. k, 0.28, function(u)
			local s = PICON * (1.35 - 0.35 * Ease(u))
			icon:SetSize(s, s); icon:SetAlpha(min(1, u * 2.5))
			icon:ClearAllPoints(); icon:SetPoint("CENTER", row, "TOPLEFT", PIX + PICON / 2, -(5 + PICON / 2))
		end, function()
			RowIcon(row)
			p.shown = true
			if k == 1 then
				RowHead(row)
				Sound("head")
			else
				-- (each prize's beast glows as it comes in; the head's glow stays)
				Lit(row.glow, true)
				Later(0.9, function() if row.glow and not (k == 1) then Lit(row.glow, false) end end)
			end
			Refresh()
			-- the head's card fills in with a flash
			if k == 1 then Animate("headIn", 0.5, function(u) res.card.flash:SetAlpha(0.5 * math.sin(math.pi * u)) end) end
			done()
		end)
	end)
end

-- Rolls the next prize: RandomRoll(1, 10000), read back from the roll line. No line in 6 s (or a
-- roll the game refused): the counter offers to roll it again, and a typed /roll 10000 counts.
function NextPrize()
	if S.phase ~= "draw" then return end
	local k = #S.prizes + 1
	if k > PRIZES then return end
	S.want, S.stalled, S.hint, S.current = k, nil, nil, k
	S.spinFrom = GetTime()
	Spin(k)
	S.reqs[#S.reqs + 1] = { prize = k, at = GetTime() }
	if not pcall(RandomRoll, LOW, HIGH) then -- gp:arena-clicks
		S.reqs[#S.reqs] = nil
		S.hint = "The game refused the roll: type /roll 10000."
	end
	local round = S.round
	C_Timer.After(LINE_WAIT, function()
		if S.round ~= round or S.want ~= k then return end
		S.want, S.stalled = nil, k
		Stop("spin" .. k); StopSpin()
		for d = 1, 4 do res.rows[k].digit[d]:SetText("-"); res.rows[k].digit[d]:SetAlpha(0.45) end
		S.hint = "No roll line in 6 seconds. Roll again, or type /roll 10000."
		Refresh()
	end)
	Refresh()
end

local Finish
local function OnLine(msg)
	if S.phase ~= "draw" then return end
	local name, value, low, high = AP.Roll(msg)
	if not name then
		if value == "secret" then S.hint = "Rolls can't be read here (chat lockdown)."; Refresh() end
		return
	end
	if not Mine(name) then return end
	local milhar = Bicho.Milhar(value, low, high)
	if not milhar then return end                 -- another /roll (1-100, a Bones...): not a prize
	local k = #S.prizes + 1
	if k > PRIZES then return end
	-- Which roll is this line? The server answers in order: the oldest roll asked and not answered
	-- yet. An answer to a prize already drawn (a roll asked again whose first line came late after
	-- all) is dropped, never carried into the next prize. A line nobody asked for counts only for a
	-- prize waiting for its Roll button: a typed /roll 10000. (A line that never comes leaves its
	-- roll counted as asked: the next prize then waits for its Roll button once. Slower, never wrong.)
	local req = table.remove(S.reqs, 1)
	if req then
		if req.prize ~= k then return end
	elseif S.stalled ~= k then
		return
	end
	S.want, S.stalled, S.hint = nil, nil, nil
	S.prizes[k] = { value = value, milhar = milhar, beast = Bicho.BeastOf(milhar) }
	if not anims["spin" .. k] then Spin(k); S.spinFrom = GetTime() end
	local round = S.round
	-- the digits spin a little before they settle (at once when the line was slow)
	local wait = max(0, (S.spinFrom or 0) + 0.55 - GetTime())
	C_Timer.After(wait, function()
		if S.round ~= round then return end
		Reveal(k, function()
			if S.round ~= round then return end
			if k < PRIZES then Later(0.45, NextPrize) else Later(0.5, Finish) end
		end)
	end)
	Refresh()
end

-- The draw is over: all five positions settle through the shared contract, the wallet takes your
-- ticket payouts (it counts up in your day), and the result is announced in one chat line.
function Finish()
	if S.phase ~= "draw" or #S.prizes < PRIZES then return end
	S.phase = "result"
	local head, milhar = S.prizes[1].beast, S.prizes[1].milhar
	local draw, won = {}, {}
	for i = 1, PRIZES do draw[i] = S.prizes[i].beast; won[draw[i]] = true end
	local r = assert(Bicho.Settle(S.bets, draw, S.carried, FEE_BP))
	S.result = r
	local back, staked, wonAny = 0, 0, false
	for i, b in ipairs(S.bets) do
		if b[1] == "you" then
			staked = staked + b[3]
			back = back + r.payouts[i]
			if won[b[2]] then wonAny = true end
		end
	end
	local name = BEASTS[head].name
	if back > 0 then
		Wallet.Move(back, ("Lottery day %d: five-place settlement"):format(S.day), { ("Lottery day %d: five places settled; first %02d %s"):format(S.day, head, name),
			("Lottery: five places settled; first %02d %s"):format(head, name), ("Five places settled; first %02d %s"):format(head, name) }, "lottery")
	end
	-- the table's announcement comes in: the band fades in and flashes once
	Refresh()
	Animate("announce", 0.35, function(u)
		for _, x in ipairs({ bar.title, bar.titleSub, bar.headIcon, bar.headIcon.frame, bar.band }) do x:SetAlpha(u) end
		bar.flash:SetAlpha(0.45 * math.sin(math.pi * u))
	end)
	Sound("announce")
	if staked > 0 then
		local round = S.round
		C_Timer.After(0.9, function()
			if S.round ~= round then return end
			if wonAny then Sound("win"); Sound("coins") else Sound("lose") end
		end)
	elseif r.winners == 0 then Sound("lose") end
	local line = ("day %d (practice): first place is %04d, the %s (%02d)."):format(S.day, milhar, name, milhar % 100)
	if r.winners > 0 then
		line = line .. (" %d winning bettor%s receive%s %s; %s rolls over."):format(r.winners, r.winners == 1 and "" or "s",
			r.winners == 1 and "s" or "", Money(r.paid), Money(r.rollover))
	else
		line = line .. (" Nobody picked any drawn beast: %s rolls over."):format(Money(r.rollover))
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cffe6c35cMenagerie Lottery|r, " .. line)
end

function Bicho.Draw()
	if S.phase ~= "bet" then return end
	S.phase, S.prizes, S.reqs, S.want, S.stalled, S.hint, S.current = "draw", {}, {}, nil, nil, nil, nil
	S.round = S.round + 1         -- the practice bettors stop
	S.group = type(IsInGroup) == "function" and IsInGroup() or false
	if bar.box then bar.box:ClearFocus() end
	Sound("start")
	-- the grid gives its place to the draw (your wallet in it shown as it is, not counted to)
	ClearResult()
	shown.resWallet = nil
	Refresh()
	Later(0.6, NextPrize)
end

-- Next draw, a new day: back to the grid; the unclaimed profit opens the pot; new
-- practice bettors; your wallet as it is (refilled with practice gold when it is empty).
function Bicho.NextDay()
	if S.phase ~= "result" then return end
	S.day = S.day + 1
	S.carried = S.result and S.result.rollover or 0
	S.bets, S.prizes, S.reqs, S.result = {}, {}, {}, nil
	S.phase, S.want, S.stalled, S.hint, S.sel = "bet", nil, nil, nil, nil
	S.round, S.crowd = S.round + 1, 0
	if S.wallet < GOLD then
		Wallet.Move(WALLET - S.wallet, "Practice wallet refilled to " .. Money(WALLET), "Practice gold: refilled", "lottery")
		Say("your practice wallet is refilled: " .. Money(WALLET) .. ".")
	end
	S.stake = max(1, min(S.stake, floor(S.wallet / GOLD)))
	S.favourites = { random(#BEASTS), random(#BEASTS), random(#BEASTS) }
	for _ = 1, CROWD_START do CrowdBet(true) end
	for _, a in ipairs({ bar.title, bar.titleSub, bar.headIcon, bar.headIcon.frame, bar.band }) do a:SetAlpha(1) end
	-- back to the grid
	Refresh()
	if win and win:IsShown() then Crowd() end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Build()
	win = CreateFrame("Frame", "OlympusArenaGamesLottery", UIParent)
	win:SetSize(W, H)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)     -- centred, as every game window
	win:SetFrameStrata("DIALOG"); win:SetToplevel(true)
	win:SetMovable(true); win:SetClampedToScreen(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
	local bg = win:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(PARCHMENT); bg:SetTexCoord(8 / 512, 284 / 512, 6 / 512, 318 / 512)
	bg:SetPoint("TOPLEFT", 10, -10); bg:SetPoint("BOTTOMRIGHT", -10, 10)
	win.border = Border(win)
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4); close:SetFrameLevel(win:GetFrameLevel() + 10)
	win.close = close
	driver = CreateFrame("Frame", nil, win)
	BuildHeader()
	for n = 1, #BEASTS do cards[n] = Card(n) end
	BuildBar()
	BuildResult()
	BuildLetter()
	BuildGuide()
	S.favourites = { random(#BEASTS), random(#BEASTS), random(#BEASTS) }
	for _ = 1, CROWD_START do CrowdBet(true) end
	win:SetScript("OnShow", function()
		-- one game's window at a time: Bones's closes, the lab's hub hides
		if ns.Games and ns.Games.Shown then ns.Games.Shown("lottery") end
		EscapeSync()
		events:RegisterEvent("CHAT_MSG_SYSTEM")
		Sound("open")
		Refresh()
		if S.phase == "bet" then Crowd() end
		if S.phase == "draw" then
			for k = 1, #S.prizes do Settled(k) end
			if not S.want and not S.stalled and #S.prizes < PRIZES then S.stalled = #S.prizes + 1 end
			-- (all five drawn but the table closed before the settlement: settle now)
			if #S.prizes == PRIZES and not S.want then C_Timer.After(0, function() Finish() end) end
			Refresh()
		end
	end)
	win:SetScript("OnHide", function()
		events:UnregisterEvent("CHAT_MSG_SYSTEM")
		for _, p in ipairs(popups) do p:Hide() end
		ns.Games.HideWallet(win)
		S.round = S.round + 1
		StopSpin()
		-- a prize waiting for its roll waits for the Roll button when the table opens again (its
		-- line isn't read while the table is closed)
		if S.phase == "draw" and #S.prizes < PRIZES then
			if S.want then Stop("spin" .. S.want) end
			S.want, S.stalled = nil, #S.prizes + 1
		end
		S.reqs = {}
		-- what was moving ends where it was going (a prize still being revealed is finished by
		-- Settled when the table opens again)
		for key, a in pairs(anims) do
			if not a.loop then a.fn(1) end
			anims[key] = nil
		end
		driver:SetScript("OnUpdate", nil)
		-- the client stops a hidden frame's animation groups: the pulses start again on the next Refresh
		for _, c in ipairs(cards) do c.marked = nil end
		bar.lit, res.card.lit = nil, nil
		EscapeSync()
	end)
	Refresh()
	win:Hide()
end

-- (Made with the table, not at load: the arena's companion keeps no frame of its own while idle.)
local function Events()
	if events then return end
	events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function(_, event, msg)
		if event == "CHAT_MSG_SYSTEM" then return OnLine(msg) end
		if win and win:IsShown() then win:Hide(); Say("closed: you entered combat.") end
	end)
end

function Bicho.Command(arg)
	arg = strtrim(arg or ""):lower()
	if InCombatLockdown() then return Say("not in combat.") end
	if arg == "sound" then
		S.sound = not S.sound
		if not S.sound then StopSpin() end
		return Say("sound effects " .. (S.sound and "on." or "off."))
	end
	if arg ~= "" and arg ~= "draw" and arg ~= "letter" then
		return Say("/oly lottery opens the table; /oly lottery draw draws now; /oly lottery letter shows the letter again; /oly lottery sound turns its sounds on or off.")
	end
	if arg == "" and win and win:IsShown() then return win:Hide() end
	return Bicho.Open(arg)
end

-- Opens the table (never closes it; the lab's hub and /oly lottery come here): the letter first,
-- once a session (and on asking), before any draw. Bones's window closes (the table's OnShow).
function Bicho.Open(arg)
	if InCombatLockdown() then return Say("not in combat.") end
	if not win then Events(); Build() end
	win:Show()
	if arg == "letter" or not S.letterSeen then
		S.letterSeen = true
		-- (the deal: How to play's first tab)
		S.page = 1
		Show(guide)
		GuidePage(1)
		if arg == "draw" then Say("read the letter first, then draw with the table's Draw now button (or /oly lottery draw).") end
		return
	end
	if arg == "draw" then return Bicho.Draw() end
end
-- Closes the table (its pop-ups with it); its X and Escape do the same.
function Bicho.Close() if win and win:IsShown() then win:Hide() end end
function Bicho.IsOpen() return win ~= nil and win:IsShown() end
function Bicho.Window() return win end
-- (the old mock's entry points)
Bicho.Toggle = function() Bicho.Command("") end

-- For the offline tests: the table's parts, state and geometry (read only).
Bicho._ = { S = S, SND = SND, AREAS = AREAS, BEASTS = BEASTS, STEPS = STEPS, mine = Mine, step = Step, anims = anims, line = function(msg) OnLine(msg) end,
	refresh = function() Refresh() end, myBeasts = MyBeasts,
	geo = { W = W, H = H, GX = GX, GY = GY, CW = CW, CH = CH, GAP = GAP, FOOT_Y = FOOT_Y, ROW_A = ROW_A, ROW_B = ROW_B, PW = PW, ICON = ICON,
		GUIDE_W = GUIDE_W, GUIDE_H = GUIDE_H, QUEST_BORDER = QUEST_BORDER, PICON = PICON, BIG = BIG, LINES = LINES, HLINES = HLINES },
	parts = function() return { win = win, header = header, bar = bar, cards = cards, letter = letter, guide = guide,
		res = res, driver = driver, popups = popups } end }
