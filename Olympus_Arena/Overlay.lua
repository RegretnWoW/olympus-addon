local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Overlay.lua. A stub the arena's core created for the screens to
-- fill. The King's overlay and the stream-delay notice (open in combat).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome

-- "Show on screen" (the way the Vox Populi chart is): OlympusArenaOverlay, 900 x 460 at scale 1
-- (0.6 to 1.6, kept), HIGH strata, movable, top centre by default. The King opens it (his own
-- view, or the author's view of it), and a councillor or a public arbiter too, without the delay
-- line. It stays open in combat (an insecure frame, allowed there). Its mode follows the event
-- (the King may pin one): TAPE (the tale of the tape, the pool split by side, the odds, the
-- bettors, "BETS CLOSE IN", a ticker of the last 8 bets as amount and side), LAST CALL, LIVE (bets
-- closed, the final odds), RESULT, PAYOUTS (the bank or arbiter named, never a player), CARD (a
-- Fight Night's bouts) and BRACKET. It never shows free text, a bettor's name or a chat line; a
-- rehearsal carries a REHEARSAL watermark, the sim SAMPLE DATA, neither of which can be turned off.
-- The stream-delay line shows on the King's screen only. While the compliance gate allows no bet
-- (1.1.6, ArenaUI.BetsShown), nothing of the bets shows: no "BETS CLOSE IN" nor "BETS CLOSED", no
-- LAST CALL (the bets' last call: the tape until the fight goes live), no PAYOUTS (a result is
-- RESULT), no pool or ticker (there are none).
local Overlay = {}
ArenaUI.Overlay = Overlay

Overlay.W, Overlay.H = 900, 460
Overlay.MODES = { "TAPE", "LASTCALL", "LIVE", "RESULT", "PAYOUTS", "CARD", "BRACKET" }
Overlay.TICKER = 8

-- The stream-delay line (the design): on the King's screen only, always there (the addon cannot
-- tell whether he streams).
function ArenaUI.DelayLine(mode)
	if not Kit.KingsView(mode) then return nil end
	local d = ns.Arena.Sim() and (Kit.Settings().delay or 0) or ns.Arena.Delay(true)
	return L.ARENA_DELAY_LINE:format(tonumber(d) or 0)
end
-- The shortest betting window now (the King's delay counted): Arena.OpenMin.
function Overlay.MinWindow(public) return ns.Arena.OpenMin(public ~= false) end

-- Who may open it: the King's view, a councillor, a public arbiter (the sim: anyone running it).
function Overlay.Allowed()
	if ns.Arena.Sim() then return true end
	if Kit.KingsView("L") or Kit.KingsView("T") then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(ns.me) then return true end
	local R = ns.ArenaRoles
	return type(R) == "table" and type(R.IsPublicArbiter) == "function" and (R.IsPublicArbiter(ns.me, "L") or R.IsPublicArbiter(ns.me, "T")) or false
end

-- The mode an event is in now (unless pinned).
function Overlay.ModeOf(ev, view)
	if type(ev) ~= "table" then return nil end
	if ev.kind == "tourney" then return "BRACKET" end
	if ev.kind == "card" then return "CARD" end
	local payouts = type(ev.payouts) == "table" and ev.payouts or (type(view) == "table" and view.payouts)
	if ev.over or ev.winner or ev.state == "R" or ev.state == "F" then
		local bets = type(ArenaUI.BetsShown) ~= "function" or ArenaUI.BetsShown("fight")
		if bets and type(payouts) == "table" and (tonumber(payouts.due) or 0) > 0 then return "PAYOUTS" end
		return "RESULT"
	end
	local now = ns.Arena.Now()
	local lockAt = (type(view) == "table" and tonumber(view.lockAt)) or ev.lockAt
	if ev.live or (lockAt and lockAt <= now) then return "LIVE" end
	local bets = type(ArenaUI.BetsShown) ~= "function" or ArenaUI.BetsShown("fight")
	if bets and (ev.state == "Z" or (lockAt and lockAt - now <= ns.Arena.LastCall(ev.public))) then return "LASTCALL" end
	return "TAPE"
end

-- Names, numbers and fixed words: a fighter's name as the overlay writes it.
local function Fighter(name) return Kit.Name(name) end

-- The overlay's model: { id, mode, big, lines, ticker, watermark, delay, closesAt }. Everything in
-- it is a fighter's name, a number or a fixed string.
function Overlay.Model(id, pinned)
	local ev = id and Data.Event(id) or ArenaUI.BestEvent and ArenaUI.BestEvent()
	local m = { lines = {}, ticker = {} }
	-- (The sim stamps nothing on the overlay, 2026-09-30: its own bar says so.)
	if ns.Arena.Sim() then m.watermark = nil
	elseif (ev and ev.mode == "T") or ns.Arena.TestBuild() then m.watermark = L.ARENA_WATERMARK_TEST end
	if not ev then
		m.mode, m.big = "TAPE", L.ARENA_OVERLAY_NOTHING
		return m
	end
	m.id = ev.id
	local view = Data.Markets(ev.id)
	-- (the King's pin on PAYOUTS or LAST CALL: the result or the tape instead while the gate allows no bet)
	if type(ArenaUI.BetsShown) == "function" and not ArenaUI.BetsShown("fight") then
		if pinned == "PAYOUTS" then pinned = "RESULT" elseif pinned == "LASTCALL" then pinned = "TAPE" end
	end
	m.mode = pinned or Overlay.ModeOf(ev, view)
	m.title = Home.EventTitle(ev)
	m.delay = ev.public and ArenaUI.DelayLine(ev.mode) or nil
	local cur = type(view) == "table" and view.cur or nil
	local sides
	local mk = type(view) == "table" and view.markets and view.markets[1]
	if mk then
		sides = {}
		local total = 0
		for _, o in ipairs(mk.outcomes or {}) do total = total + (tonumber(o.pool) or 0) end
		for _, o in ipairs(mk.outcomes or {}) do
			local label = (o.o == "A" and ev.A and Fighter(ev.A)) or (o.o == "B" and ev.B and Fighter(ev.B)) or ns.Codec.Plain(tostring(o.label or o.o))
			sides[#sides + 1] = { label = label, odds = tonumber(o.odds), pool = tonumber(o.pool) or 0, count = tonumber(o.count) or 0,
				share = total > 0 and (tonumber(o.pool) or 0) / total or 0 }
		end
		m.total = total
	end
	m.sides = sides or {}
	m.cur = cur
	local lockAt = type(view) == "table" and tonumber(view.lockAt) or ev.lockAt
	local bets = type(ArenaUI.BetsShown) ~= "function" or ArenaUI.BetsShown("fight")
	m.closesAt = bets and lockAt or nil
	if m.mode == "TAPE" or m.mode == "LASTCALL" or m.mode == "LIVE" then
		m.big = m.title
		for _, s in ipairs(m.sides) do
			m.lines[#m.lines + 1] = L.ARENA_OVERLAY_SIDE:format(s.label, s.odds and ("%.2fx"):format(s.odds) or "-", Kit.Money(s.pool, cur), s.count)
		end
		if m.mode == "LIVE" then m.stamp = bets and L.ARENA_OVERLAY_CLOSED or nil
		elseif m.mode == "LASTCALL" then m.stamp = L.ARENA_OVERLAY_LASTCALL end
		-- The ticker: the last bets as amount and side, never a bettor.
		local recent = type(view) == "table" and view.recent or nil
		for i = math.max(1, #(recent or {}) - Overlay.TICKER + 1), #(recent or {}) do
			local b = recent[i]
			if type(b) == "table" and tonumber(b.copper) then
				local side = (b.o == "A" and ev.A and Fighter(ev.A)) or (b.o == "B" and ev.B and Fighter(ev.B)) or nil
				for _, s in ipairs(m.sides) do if not side and tostring(b.o) == tostring(s.label) then side = s.label end end
				m.ticker[#m.ticker + 1] = ("+%s %s"):format(Kit.Money(b.copper, cur), side or "?")
			end
		end
	elseif m.mode == "RESULT" then
		m.big = L.ARENA_OVERLAY_RESULT:format(ev.winner and Fighter(ev.winner) or "?")
		local method = ev.method == "k" and L.ARENA_METHOD_KO or (ev.method == "f" and L.ARENA_METHOD_FLED or nil)
		if method then m.lines[#m.lines + 1] = method end
		if tonumber(ev.dur) then m.lines[#m.lines + 1] = L.ARENA_OVERLAY_DURATION:format(Home.Clock(ev.dur)) end
		for _, s in ipairs(m.sides) do
			if ev.winner and s.label == Fighter(ev.winner) and s.odds then m.lines[#m.lines + 1] = L.ARENA_OVERLAY_PAID:format(s.label, ("%.2fx"):format(s.odds), s.count) end
		end
	elseif m.mode == "PAYOUTS" then
		local p = type(ev.payouts) == "table" and ev.payouts or (type(view) == "table" and view.payouts) or {}
		m.big = L.ARENA_OVERLAY_PAYOUTS
		local who = type(view) == "table" and view.bank or ev.arbiter
		if (tonumber(p.late) or 0) > 0 then
			m.lines[#m.lines + 1] = L.ARENA_OVERLAY_OWES:format(Kit.Name(who), Kit.Money(p.copperDue or 0, cur), tonumber(p.due) or 0)
		else
			m.lines[#m.lines + 1] = L.ARENA_OVERLAY_PAYOUT_LINE:format(tonumber(p.paid) or 0, (tonumber(p.paid) or 0) + (tonumber(p.due) or 0),
				Kit.Money(p.copperPaid or 0, cur), Kit.Money((p.copperPaid or 0) + (p.copperDue or 0), cur))
		end
	elseif m.mode == "CARD" then
		m.big = m.title
		for i, fid in ipairs(type(ev.bouts) == "table" and ev.bouts or {}) do
			local bout = Data.Event(fid)
			if bout and i <= 8 then m.lines[#m.lines + 1] = ("%d. %s  %s"):format(i, Home.EventTitle(bout), Home.StateWord(bout)) end
		end
	elseif m.mode == "BRACKET" then
		m.big = m.title
	end
	return m
end

-- Every word the overlay would show now, in one string (the tests' check that nothing but names,
-- numbers and fixed words is there).
function Overlay.Text(m)
	m = m or Overlay.lastModel
	if not m then return "" end
	local parts = { m.big or "", m.stamp or "", m.watermark or "", m.delay or "" }
	for _, l in ipairs(m.lines or {}) do parts[#parts + 1] = l end
	for _, t in ipairs(m.ticker or {}) do parts[#parts + 1] = t end
	return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local f
local pinned
local function Settings()
	local s = Kit.Settings()
	if type(s.overlay) ~= "table" then s.overlay = {} end
	return s.overlay
end
local function Build()
	if f then return f end
	f = CreateFrame("Frame", "OlympusArenaOverlay", UIParent)
	f:SetSize(Overlay.W, Overlay.H)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		if self.StopMovingOrSizing then self:StopMovingOrSizing() end
		if ns.Arena.Sim() then return end
		local point, _, rel, x, y = self:GetPoint(1)
		if type(point) == "string" then Settings().point = { point, rel, x, y } end
	end)
	local p = Settings().point
	if type(p) == "table" and type(p[1]) == "string" then
		f:SetPoint(p[1], UIParent, type(p[2]) == "string" and p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
	else
		f:SetPoint("TOP", 0, -60)
	end
	f:SetScale(math.max(0.6, math.min(1.6, tonumber(Settings().scale) or 1)))
	-- On parchment inside the dialog border, in dark ink (the owner's call, 2026-09-30: no dark
	-- see-through sheet over the window).
	local okBorder, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if okBorder and border and border.SetAllPoints then border:SetAllPoints() end
	f.bg = Kit.Parchment(f, 0)
	f.bg:ClearAllPoints()
	f.bg:SetPoint("TOPLEFT", 10, -10)
	f.bg:SetPoint("BOTTOMRIGHT", -10, 10)
	f.card = CreateFrame("Frame", nil, f)
	f.card:SetAllPoints(f)
	f.bracket = CreateFrame("Frame", nil, f)
	f.bracket:SetPoint("TOPLEFT", 20, -48)
	f.bracket:SetSize(860, 380)
	local INK, RED = Kit.INK, { 0.50, 0.06, 0.03 }
	f.big = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.big:SetPoint("TOP", 0, -20)
	f.big:SetTextColor(RED[1], RED[2], RED[3])
	f.stamp = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.stamp:SetPoint("CENTER", 0, 30)
	f.stamp:SetTextColor(RED[1], RED[2], RED[3])
	f.lines = {}
	for i = 1, 8 do
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		fs:SetPoint("TOP", f.big, "BOTTOM", 0, -12 - (i - 1) * 28)
		fs:SetTextColor(INK[1], INK[2], INK[3])
		f.lines[i] = fs
	end
	f.clock = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.clock:SetPoint("BOTTOM", 0, 44)
	f.clock:SetTextColor(INK[1], INK[2], INK[3])
	f.ticker = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.ticker:SetPoint("BOTTOMLEFT", 16, 14)
	f.ticker:SetWidth(600)
	f.ticker:SetJustifyH("LEFT")
	f.ticker:SetTextColor(INK[1], INK[2], INK[3])
	f.watermark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.watermark:SetPoint("TOPRIGHT", -14, -10)
	f.watermark:SetTextColor(RED[1], RED[2], RED[3])
	f.delay = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.delay:SetPoint("BOTTOMRIGHT", -14, 14)
	f.delay:SetWidth(420)
	f.delay:SetJustifyH("RIGHT")
	f.delay:SetTextColor(INK[1], INK[2], INK[3], 0.8)
	f.pool = CreateFrame("Frame", nil, f)
	f.pool:SetPoint("BOTTOM", 0, 90)
	f.pool:SetSize(600, 14)
	f.pool.a = f.pool:CreateTexture(nil, "ARTWORK")
	f.pool.a:SetPoint("LEFT")
	f.pool.a:SetHeight(14)
	f.pool.a:SetColorTexture(0.75, 0.15, 0.1, 0.9)
	f.pool.b = f.pool:CreateTexture(nil, "ARTWORK")
	f.pool.b:SetPoint("RIGHT")
	f.pool.b:SetHeight(14)
	f.pool.b:SetColorTexture(0.15, 0.35, 0.75, 0.9)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	-- The King's pins: one mode kept whatever the event does (Auto follows it again).
	f.modes = {}
	local prev
	for i, mode in ipairs({ "AUTO", "TAPE", "LIVE", "RESULT", "PAYOUTS", "BRACKET" }) do
		local b = Kit.Button(f, 70, 24, L["ARENA_OVERLAY_MODE_" .. mode] or mode, function()
			pinned = mode ~= "AUTO" and mode or nil
			Settings().mode = pinned
			Overlay.Refresh()
		end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2) end
		f.modes[i] = b
		prev = b
	end
	f:SetScript("OnShow", function() ns.EscapeCloses("OlympusArenaOverlay") ns.Arena.Involve("overlay", true) end)
	f:SetScript("OnHide", function() ns.Arena.Involve("overlay", false) end)
	ns.On("ARENA_CHANGED", function() if f:IsShown() then ns.SafeCall("arena overlay", Overlay.Refresh) end end)
	pinned = Settings().mode
	return f
end

function Overlay.Refresh()
	if not f then return nil end
	local m = Overlay.Model(rawget(f, "id"), pinned)
	Overlay.lastModel = m
	f.big:SetText(m.big or "")
	f.stamp:SetText(m.stamp or "")
	for i, fs in ipairs(f.lines) do fs:SetText(m.lines[i] or "") end
	f.ticker:SetText(table.concat(m.ticker, "   "))
	-- (Neither watermark can be turned off.)
	f.watermark:SetText(m.watermark or "")
	f.watermark:SetShown(m.watermark ~= nil)
	f.delay:SetText(m.delay or "")
	if m.closesAt and (m.mode == "TAPE" or m.mode == "LASTCALL") then
		Kit.Countdown(f.clock, m.closesAt, L.ARENA_OVERLAY_CLOSES, L.ARENA_OVERLAY_CLOSED)
	else
		Kit.StopCountdown(f.clock)
		f.clock:SetText("")
	end
	local a, b = m.sides[1], m.sides[2]
	local showPool = a and b and (m.total or 0) > 0 and (m.mode == "TAPE" or m.mode == "LASTCALL" or m.mode == "LIVE")
	f.pool:SetShown(showPool and true or false)
	if showPool then
		f.pool.a:SetWidth(math.max(1, 600 * a.share))
		f.pool.b:SetWidth(math.max(1, 600 * b.share))
	end
	if m.mode == "BRACKET" and m.id and ArenaUI.Bracket then
		f.bracket:Show()
		ArenaUI.Bracket.Draw(f.bracket, m.id, "overlay")
	else
		f.bracket:Hide()
	end
	return m
end

-- Opens it on an event (the one that matters now by default).
function Overlay.Show(id)
	if not Overlay.Allowed() then
		ArenaUI.Say(L.ARENA_OVERLAY_REFUSED)
		return nil
	end
	Build()
	f.id = id
	-- In the sim, a pop-up centred over the arena window (the King's own keeps its place).
	local win = ArenaUI.frame
	if ns.Arena.Sim() and win and win:IsShown() then
		f:ClearAllPoints()
		f:SetPoint("CENTER", win, "CENTER", 0, 0)
	end
	f:Show()
	Overlay.Refresh()
	return f
end
function Overlay.Hide() if f then f:Hide() end end
function Overlay.Frame() return f end
function Overlay.Pin(mode) pinned = mode Overlay.Refresh() end
-- The scale (0.6 to 1.6), kept.
function Overlay.SetScale(s)
	s = math.max(0.6, math.min(1.6, tonumber(s) or 1))
	Settings().scale = s
	if f then f:SetScale(s) end
	return s
end
