local _, own = ...; local ns = own.host; if not ns then return end

-- The Frame Lab's games inside the arena (the owner's call, 2026-09-30: "the lab versions inside
-- the arena"): Bones (Games/Farkle.lua) and the Lottery (Games/Bicho.lua) are the lab's
-- practice windows, with the practice wallet they share (Games/Games.lua). Only an explicit test
-- build or solo simulation may replace the arena window's real-data Bones and Lottery
-- sections with them. Nothing there is sent or saved.
local ArenaUI = own.ArenaUI
local L = ns.L

-- The games' window's Arena row opens the arena window (and never closes it).
own.ArenaWindow = { Open = function() if ArenaUI.Show then ArenaUI.Show() end end }

local OPEN = {
	farkle = function() return own.Farkle and own.Farkle.Open() end,
	lottery = function() return own.Bicho and own.Bicho.Open() end,
	games = function() return own.Games and own.Games.Hub(true) end,
}
local function LabAllowed()
	if not (ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()) then return false end
	return (ns.Arena.Sim and ns.Arena.Sim() == true)
		or (ns.Arena.TestBuild and ns.Arena.TestBuild() ~= nil)
end
-- Opens a game's window: "farkle" (Bones), "lottery" or "games" (the games' window). False
-- when there is none (the arena window's own section shows then).
function ArenaUI.OpenGame(which)
	if not LabAllowed() then return false end
	local fn = OPEN[which]
	if not fn then return false end
	ns.SafeCall("arena games " .. which, fn)
	return true
end

-- Compatibility for the lab's My money page and coin buttons. The real wallet remains the core's;
-- this practice balance is visible only in a lab session (or after that lab recorded movement).
ns.Arena.MyMoney = function()
	local W = own.Wallet
	if type(W) ~= "table" then return nil end
	-- The lab starts with practice gold. Never surface that made-up balance on a normal client;
	-- an explicit lab/test session (or a session that actually recorded lab moves) may inspect it.
	if not LabAllowed() and #(W.history or {}) == 0 then return nil end
	local history = {}
	for _, e in ipairs(W.history or {}) do
		history[#history + 1] = { when = e.when, what = e.what, amount = e.amount, after = e.after }
	end
	return { balance = W.balance, history = history }
end
if own.Games then
	own.Games.OnMoney = function()
		if ns.Treasury and ns.Treasury.OpenMoney then return ns.Treasury.OpenMoney() end
		return own.Games.ShowWallet()
	end
end

---------------------------------------------------------------------------
-- /oly games photos (the owner's slides, 2026-09-30; a test build and the author's own client
-- only): the game's own screenshot (Screenshot()) of everything that is not the arena, in turn,
-- about 5 s apart: the Olympus window on the Games tab and on Treasury > My money; Bones' setup,
-- a game with a scripted throw (1 5 3 3 6 2, the 1 and the 5 picked) and its four How to play
-- pages; the Lottery's grid with a beast picked and a stake, its three How to play pages and a
-- practice draw's result (the odometer done); the arena's four How to play pages. The rolls are
-- scripted: while the tour runs RandomRoll hands its line straight to the game's own reader, so
-- nothing is rolled in chat; nothing is sent or saved. Each window closes after its shots.
---------------------------------------------------------------------------
local BONES_THROW = 14785 -- /roll 1-46656 read as 1 5 3 3 6 2 (FarkleRules.Decode)
local LOTTERY_ROLLS = { 4827, 1203, 7777, 350, 9061 }
local tour, rolls, feed
local realRoll
local function RollLine(value, low, high)
	local fmt = type(_G.RANDOM_ROLL_RESULT) == "string" and _G.RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
	local me = UnitName and UnitName("player") or "?"
	return fmt:format(me, value, low, high)
end
local function ScriptedRoll(low, high)
	local value = table.remove(rolls, 1)
	if not value or not feed then return end
	local line = RollLine(value, tonumber(low) or 1, tonumber(high) or 100)
	C_Timer.After(0.4, function() if feed then ns.SafeCall("games photos roll", feed, line) end end)
end
local function Restore()
	if realRoll then RandomRoll = realRoll; realRoll = nil end
	feed, rolls = nil, nil
end
local function Shot()
	if not ns.Gate.Allowed("photo") then return end -- (switched to the gamepad UI: no shot)
	local bar = _G.OlympusArenaSimBar
	local hid = bar and bar:IsShown()
	if hid then bar:Hide() end
	if type(Screenshot) == "function" then Screenshot() end -- gp:photo
	if hid then C_Timer.After(1, function() if bar then bar:Show() end end) end
end
local function CloseAll()
	if own.Farkle then
		local p = own.Farkle._ and own.Farkle._.parts and own.Farkle._.parts()
		if p and p.help then p.help:Hide() end
		own.Farkle.Close()
	end
	if own.Bicho then
		local p = own.Bicho._ and own.Bicho._.parts and own.Bicho._.parts()
		if p and p.guide then p.guide:Hide() end
		own.Bicho.Close()
	end
	local how = _G.OlympusArenaHowTo
	if how then how:Hide() end
	if ns.UI and ns.UI.IsShown and ns.UI.IsShown() and ns.UI.Toggle then ns.UI.Toggle() end
end
local function Click(b) if b and b.Click then b:Click() end end
local function Steps()
	local F, B = own.Farkle, own.Bicho
	local FP = function() return F._.parts() end
	local BP = function() return B._.parts() end
	local steps = {
		{ function() if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("arena") end end },
		{ function() if ns.Treasury and ns.Treasury.OpenMoney then ns.Treasury.OpenMoney() end end },
		{ function()
			CloseAll()
			F._.S.rulesSeen, F._.S.first = true, 1
			-- The public Bones entry is now its introduction and matcher. The photo tour asks
			-- explicitly for the retained local practice table it is meant to document.
			F.Open("practice")
		end },
		-- a game: Start, then the throw, scripted; the 1 and the 5 picked once they land
		{ function()
			feed, rolls = F._.line, { BONES_THROW }
			Click(FP().primary)
			C_Timer.After(0.6, function() Click(FP().primary) end)
			C_Timer.After(4.5, function()
				for _, d in ipairs(F._.sides[1].dice) do
					if (d.value == 1 or d.value == 5) and d.f and d.f:IsShown() and not d.lit then Click(d.f) end
				end
			end)
		end, 6 },
	}
	for k = 1, 4 do
		steps[#steps + 1] = { function()
			local help = FP().help
			if help then help:Show() Click(help.tabs and help.tabs[k]) end
		end }
	end
	steps[#steps + 1] = { function()
		CloseAll()
		B._.S.letterSeen = true
		B.Open()
		B.Pick(7)
		B.Step(1) B.Step(1)
	end }
	for k = 1, 3 do
		steps[#steps + 1] = { function()
			local guide = BP().guide
			if guide then guide:Show() Click(guide.tabs and guide.tabs[k]) end
		end }
	end
	-- a practice draw, its five rolls scripted, the result when the odometer is done
	steps[#steps + 1] = { function()
		local guide = BP().guide
		if guide then guide:Hide() end
		B.Bet()
		feed, rolls = B._.line, { unpack(LOTTERY_ROLLS) }
		B.Draw()
		for i = 1, 5 do C_Timer.After(0.8 + i * 2.6, function() Click(BP().bar and BP().bar.draw) end) end
	end, 18 }
	for k = 1, 4 do
		steps[#steps + 1] = { function()
			if k == 1 then CloseAll() end
			if ArenaUI.HowToPlay then ArenaUI.HowToPlay(k) end
		end }
	end
	return steps
end
local function Step(i)
	if not tour then return end
	local steps = tour.steps
	local s = steps[i]
	if not s then
		CloseAll()
		Restore()
		tour = nil
		ArenaUI.Kit.PhotoStage(false)
		ns.Print(L.ARENA_GAMES_PHOTOS_DONE:format(#steps))
		return
	end
	-- (a step that fails ends the tour, the screen given back)
	local ok, err = pcall(s[1])
	if not ok then
		if ns.CaptureError then ns.CaptureError("games photos step", err) end
		ArenaUI.lastPhotosError = err
		tour = nil
		Restore()
		CloseAll()
		ArenaUI.Kit.PhotoStage(false)
		return
	end
	C_Timer.After(s[2] or 3, function()
		if not tour then return end
		Shot()
		C_Timer.After(2, function() Step(i + 1) end)
	end)
end
function ArenaUI.GamesPhotos()
	local test = ns.Arena.TestBuild and ns.Arena.TestBuild()
	local author = ns.Workshop ~= nil and type(ns.Workshop.Visible) == "function" and ns.Workshop.Visible() == true
	if not (test or author) then ns.Print(L.ARENA_GAMES_PHOTOS_REFUSED) return false end
	if InCombatLockdown and InCombatLockdown() then ns.Print(L.ARENA_GAMES_PHOTOS_COMBAT) return false end
	-- (the gamepad gate's "photo": the author's photo modes are refused with the gamepad UI)
	if not ns.Gate.Allowed("photo") then ns.Print(L.PHOTO_GAMEPAD) return false end
	if tour or not (own.Farkle and own.Bicho) then return false end
	realRoll = RandomRoll -- gp:photo
	RandomRoll = ScriptedRoll
	tour = { steps = Steps() }
	-- (only the windows, on black: the stage; Escape ends the tour)
	ArenaUI.Kit.PhotoStage(true, function() tour = nil Restore() CloseAll() end)
	ns.Print(L.ARENA_GAMES_PHOTOS_START:format(#tour.steps))
	Step(1)
	return true
end
