-- 1.2, the Bone Throw tables: Bone Throw's board (Olympus_Arena/FarkleBoard.lua), the companion's table over the core's
-- FarkleTable: the practice setup and the create panel, the dice thrown along their lanes, picked,
-- set aside to the tray and banked, BONES, hot dice, the hiccup's HIC!, the rows and the column,
-- the result card, the invitation's pop-up, a watcher's table, combat, Escape, and the "How to play"
-- guide against FarkleRules. On the test world with the table's additions
-- (tests/arena/lib/farkle-world.lua) and a stand-in of the game's frames whose animations run on
-- the world's clock (tests/arena/lib/board-ui.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local N = H.World.NAMES
local P1, P2, ARB, WATCHER = N.fighterA, N.fighterB, N.arbiter, N.bettor1

local function check(cond, msg, ...) if not cond then error((msg or "check failed"):format(...), 2) end end

-- A client with the board's stand-in frames (its companion loads when asked).
local function Seat(w, name, where, screen)
	where = where or {}
	where.companion = where.companion or {}
	local c = w:Player(name, where)
	c.K = BoardUI.New(function() return w.clock end, { screen = screen })
	c.K.Install(c.globals)
	c.w = w
	return c
end
local function Board(c) return c.ns.Arena.ui.FarkleBoard end
local function X(c) return Board(c)._ end
local function P(c) return X(c).parts() end
local function R(c) return c.ns.FarkleRules end
local function Show(w, c, what, id, extra) return w:As(c, function() return c.ns.FarkleTable.ShowUI(what, id, extra) end) end
local function Click(w, c, b) return w:As(c, function() return c.K.UserClick(b) end) end
local function View(w, c, id) return w:As(c, function() return c.ns.FarkleTable.View(id) end) end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
		if c.K then for _, e in ipairs(c.K.errors) do error(c.name .. " (a script): " .. e, 2) end end
	end
end
local function Roll(c, dice) return (R(c).Encode(dice)) end
local function Num(n)
	local s, k = tostring(n), 0
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
local function InPlay(c, side)
	local sd, out = X(c).sides[side or 1], {}
	for j, i in ipairs(sd.play) do out[j] = sd.dice[i] end
	return out
end
local function Values(list) local v = {} for i, d in ipairs(list) do v[i] = d.value end return v end
-- a die's centre and edge on the table (from its top left, y down), its animations applied
local function Center(c, d)
	local x, y, w = c.K.Within(d.f, P(c).win)
	return x + w / 2, y + w / 2, w / 2
end
-- A die's body (x, y, right, bottom): the sprite is drawn at twice the die's edge; a tumbling die
-- reaches 50/128 of its sprite from the centre, a resting one 38/128.
local function Body(c, d)
	local cx, cy, half = Center(c, d)
	local r = (d.f.tumble:IsShown() and 50 / 128 or 38 / 128) * 2 * half
	return { cx - r, cy - r, cx + r, cy + r }
end
local function Inside(r, a) return r[1] >= a[1] - 0.01 and r[2] >= a[2] - 0.01 and r[3] <= a[3] + 0.01 and r[4] <= a[4] + 0.01 end
local function Overlap(a, b) return a[1] < b[3] - 0.01 and b[1] < a[3] - 0.01 and a[2] < b[4] - 0.01 and b[2] < a[4] - 0.01 end
local function Str(r) return ("%.1f,%.1f-%.1f,%.1f"):format(r[1], r[2], r[3], r[4]) end

-- The world's clock moves in small steps; watch(t) sees every step (the throws' geometry).
local function Step(w, seconds, watch, dt)
	dt = dt or 0.02
	local stop = w.clock + seconds
	while w.clock < stop - 1e-9 do
		w:Run(math.min(dt, stop - w.clock))
		if watch then watch() end
	end
end
-- Runs until pred() (or fails after `limit` seconds).
local function Until(w, pred, limit, watch)
	local t0 = w.clock
	while not pred() do
		check(w.clock - t0 <= (limit or 30), "waited %.1f s", w.clock - t0)
		Step(w, 0.05, watch)
	end
end
-- Nothing moving on the table, and no pause being read (a banner): what the board itself waits for.
local function Idle(c)
	local S = X(c).S
	if S.animating or #S.queue > 0 or S.flying[1] > 0 or S.flying[2] > 0 then return false end
	return not c.w:As(c, function() return Board(c).Busy(S.id) end)
end

-- Every step: no two dice overlap; a die in play stays in its side's half, a die at rest in the
-- tray in its row (sweeping dice and fading ones are checked for overlaps only).
local function Watcher(c, list)
	local A = X(c).AREAS
	local HALF, ROW = { A.nearHalf, A.farHalf }, { A.nearRow, A.farRow }
	return function()
		if not P(c).win:IsVisible() then return end
		local shown = {}
		for side = 1, 2 do
			for _, d in ipairs(X(c).sides[side].dice) do
				if d.f:IsShown() and c.K.Alpha(d.f) > 0.05 then
					local b = Body(c, d)
					shown[#shown + 1] = { d = d, b = b }
					if (d.where == "lane" or d.where == "air" or d.where == "hand") and not Inside(b, HALF[side]) then
						list[#list + 1] = ("die %d.%d (%s) out of its half: %s"):format(side, d.i, d.where, Str(b))
					elseif d.where == "tray" and not d.moving and not Inside(b, ROW[side]) then
						list[#list + 1] = ("die %d.%d out of its row: %s"):format(side, d.i, Str(b))
					end
				end
			end
		end
		for a = 1, #shown do
			for b = a + 1, #shown do
				if Overlap(shown[a].b, shown[b].b) then
					list[#list + 1] = ("dice %d.%d and %d.%d overlap: %s / %s"):format(shown[a].d.side, shown[a].d.i, shown[b].d.side, shown[b].d.i,
						Str(shown[a].b), Str(shown[b].b))
				end
			end
		end
	end
end
local function Clean(list) if #list > 0 then error(#list .. " violations, the first: " .. list[1], 2) end end

-- A practice game against the House: the board opened, the guide closed, Start to `target`.
local function Practice(o)
	o = o or {}
	local w = FW.New({ seed = o.seed or 5 })
	local a = Seat(w, P1, nil, o.screen)
	Show(w, a, "practice")
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	if o.target then
		for i, t in ipairs(R(a).TARGETS) do if t == o.target then Click(w, a, P(a).targets[i]) end end
	end
	if not o.noStart then
		check(Click(w, a, P(a).setup.start), "Start")
		w:Run(0)
	end
	return w, a
end
-- The practice table shown.
local function Id(c) return X(c).S.id end
local function Game(w, c) return View(w, c, Id(c)).game end
-- The House's turn played out (its dice thrown, kept, banked or busted), until this player's move.
local function HouseDone(w, c, watch)
	Until(w, function()
		local v = View(w, c, Id(c))
		return v.over or (v.expect and v.expect.who == 1 and Idle(c))
	end, 60, watch)
	Step(w, 0.05, watch)
end

print("FarkleBoard: the practice table, the dice, the column")

test("1.1.6 games presentation: Bones has a framed headerless window with the original wooden table and an innkeeper training setup", function()
	local w, a = Practice({ noStart = true })
	local p = P(a)
	check(p.shell and p.shell.border and p.shell:IsShown(), "the game border without a title strip")
	eq(p.shell.TitleContainer, nil); eq(p.win.title, nil)
	check(p.shell:GetWidth() > 880, "a larger table")
	check(p.win.table and #p.win.table == 2, "the original wooden table")
	for _, half in ipairs(p.win.table) do eq(half.tex, "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\table") end
	check(p.setup.intro and p.setup.tips, "the setup explains training and offers its tips checkbox")
	eq(p.setup.intro:GetText(), a.ns.L.FARKLE_B_SETUP_NOTE, "a trained player gets the innkeeper practice explanation")
	eq(p.setup.find, nil); eq(p.setup.someone, nil); eq(p.setup.learn, nil)
	for _, row in ipairs(p.rows) do
		check(not row.name:IsShown() and not row.line:IsShown() and not row.total:IsShown(), "no seats before play")
	end
	Board(a).Close()
	check(not p.shell:IsShown(), "closing the game closes its shell")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the companion loads with no frame of its own; /oly farkle practice opens the setup, and the guide shows first on first use", function()
	local w = FW.New()
	local a = Seat(w, P1)
	eq(w:As(a, function() return a.ns.Arena.LoadUI() end), true)
	local B = Board(a)
	check(type(B) == "table" and type(a.ns.Arena.ui.Farkle) == "function" and type(a.ns.Arena.ui.FarkleCreate) == "function", "the board's way in")
	eq(#a.K.frames, 2, "no frame of the board's before it opens (UIParent and the tooltip are the stand-in's)")
	eq(w:As(a, function() return a.ns.FarkleTable.busy("x") end), false, "the House asks the board")
	w:As(a, function() a.slashes.OLYMPUS("farkle practice") end)
	local p = P(a)
	check(p.win:IsShown() and p.setup:IsShown() and not p.create:IsShown(), "the setup on the table")
	eq(p.setup.title:GetText(), "Play to")
	for i, t in ipairs(R(a).TARGETS) do eq(p.targets[i]:GetText(), Num(t)) end
	check(p.targets[2].locked and not p.targets[1].locked, "5,000 marked")
	check(p.help:IsShown(), "How to play first")
	eq(Board(a).Page and X(a).S.page, 1, "on its Rules page")
	check(p.help:GetFrameStrata() == "FULLSCREEN_DIALOG" and p.win:GetFrameStrata() == "DIALOG", "the guide above the table's strata")
	Click(w, a, p.help.ok)
	check(not p.help:IsShown(), "Got it closes it")
	Board(a).Close()
	Show(w, a, "board")
	check(not p.help:IsShown(), "not again: shown once")
	Click(w, a, p.win.helpButton)
	check(p.help:IsShown(), "How to play opens it")
	Click(w, a, p.win.helpButton)
	check(not p.help:IsShown(), "and closes it")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: Roll throws your own /roll 1-46656: six dice, each along its own lane into its slot in about a second, the faces of the server's roll, the table's sounds", function()
	local w, a = Practice({ target = 2000 })
	local v = View(w, a, Id(a))
	eq(v.expect.who, 1, "the player throws first in his first practice")
	eq(P(a).primary:GetText(), "Roll 6 dice")
	local dice = { 5, 3, 1, 2, 1, 5 }
	w:QueueRoll(a.name, Roll(a, dice))
	local bad = {}
	local watch = Watcher(a, bad)
	-- the lanes: every die in its own, all the way
	local lanes = {}
	local laneWatch = function()
		watch()
		for _, d in ipairs(X(a).sides[1].dice) do
			if d.f:IsShown() and (d.where == "air" or d.where == "hand") then
				local cx = Center(a, d)
				local lx = X(a).geo.LaneX(d.i)
				lanes[#lanes + 1] = math.abs(cx - lx)
			end
		end
	end
	local t0 = w.clock
	check(Click(w, a, P(a).primary), "Roll")
	eq(a.asked[#a.asked].lo, 1); eq(a.asked[#a.asked].hi, 46656)
	local landed
	Until(w, function() return X(a).S.flying[1] == 0 and Idle(a) and InPlay(a)[1].where == "lane" end, 5, laneWatch)
	landed = w.clock - t0
	check(landed >= 0.8 and landed <= 1.3, "the throw took %.2f s", landed)
	Clean(bad)
	local worst = 0
	for _, dx in ipairs(lanes) do worst = math.max(worst, dx) end
	check(#lanes > 20 and worst <= 5, "a die left its lane by %.1f px", worst)
	-- at rest: the faces, each in its slot, a face cell (no tumble)
	local geo = X(a).geo
	for j, d in ipairs(InPlay(a)) do
		eq(d.value, dice[j])
		local cx, cy = Center(a, d)
		check(math.abs(cx - geo.LaneX(d.i)) <= 4.5 and math.abs(cy - geo.REST[1]) <= 3.5, "die %d at rest at %.1f,%.1f", j, cx, cy)
		local c = d.f.face.coords
		check(d.f.face:IsShown() and not d.f.tumble:IsShown(), "die %d shows its face", j)
		eq(c[1], (d.value - 1) / 8); eq(c[2], d.value / 8)
	end
	-- the sounds, from the table's list: the rattle, the toss, a few hits (three at most)
	local SND, heard = X(a).SND, {}
	for _, k in ipairs(a.sounds or {}) do heard[k] = (heard[k] or 0) + 1 end
	check(heard[SND.throw] == 1 and (heard[SND.hit] or 0) >= 1 and (heard[SND.hit] or 0) <= 3, "the toss and the hits")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: a slow roll line: the dice shake in the hand until it comes, then the throw; a quick one during the gather: no die jumps", function()
	local w, a = Practice({ target = 2000 })
	w.lineDelay = function() return 1.2 end
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Step(w, 0.9)
	for _, d in ipairs(InPlay(a)) do
		eq(d.where, "hand")
		check(d.f.tumble:IsShown() and d.f.flip:IsPlaying(), "tumbling in the hand")
		check(d.f.shake and d.f.shake:IsPlaying(), "shaken")
	end
	eq(P(a).primary:GetText(), "Rolling...")
	check(P(a).info:GetText():find("waiting for your /roll line", 1, true), "said: %s", P(a).info:GetText())
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	eq(table.concat(Values(InPlay(a)), " "), "1 2 3 4 6 2")
	-- next turn's throw: the line 0.1 s after the click, while the dice slide into the hand
	Click(w, a, InPlay(a)[1].f)
	w.lineDelay = function() return 0.1 end
	w:QueueRoll(a.name, Roll(a, { 5, 5, 3, 4, 6 }))
	local last, worst, where = {}, 0, ""
	local function Look()
		for _, d in ipairs(X(a).sides[1].dice) do
			-- (a die in play seen in two steps in a row: one fading out of the tray reappears in the
			-- hand, and one swept to the tray is quick along the band)
			if d.f:IsShown() and a.K.Alpha(d.f) > 0.05 and (d.where == "lane" or d.where == "hand" or d.where == "air") then
				local cx, cy = Center(a, d)
				local l = last[d]
				if l then
					local jump = math.abs(cx - l[1]) + math.abs(cy - l[2])
					if jump > worst then worst, where = jump, ("die %d (%s) %.1f,%.1f -> %.1f,%.1f"):format(d.i, d.where, l[1], l[2], cx, cy) end
				end
				last[d] = { cx, cy }
			else
				last[d] = nil
			end
		end
	end
	Click(w, a, P(a).primary)
	Until(w, function() Look() return Idle(a) and #InPlay(a) == 5 and InPlay(a)[1].where == "lane" end, 6, Look)
	check(worst <= 16, "a die jumped %.1f px in one step: %s", worst, where)
	eq(table.concat(Values(InPlay(a)), " "), "5 5 3 4 6")
	NoErrors(w)
end)

test("1.2.0 Bones selection: deselecting a non-scoring die immediately restores Keep and roll", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	local one, two = InPlay(a)[1], InPlay(a)[2]
	check(Click(w, a, one.f), "select the scoring one")
	eq(P(a).primary:GetText(), "Keep & roll 5")
	check(P(a).primary.enabled, "the one alone can be kept")
	check(Click(w, a, two.f), "select the non-scoring two")
	check(not P(a).primary.enabled and not P(a).bank.enabled, "one plus two cannot be kept")
	check(Click(w, a, two.f), "deselect the non-scoring two")
	check(one.lit and not two.lit, "only the scoring one remains selected")
	eq(P(a).primary:GetText(), "Keep & roll 5")
	check(P(a).primary.enabled and P(a).bank.enabled, "actions restore on that same deselection")
	eq(P(a).bank:GetText(), "Bank 100")
	w:QueueRoll(a.name, Roll(a, { 5, 2, 3, 4, 6 }))
	check(Click(w, a, P(a).primary), "Keep and roll works without another die click")
	Until(w, function() return Idle(a) and #InPlay(a) == 5 and InPlay(a)[1].where == "lane" end, 5)
	eq(Game(w, a).turn.points, 100, "only the scoring one was kept")
	eq(table.concat(Values(InPlay(a)), " "), "5 2 3 4 6")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: a picked die lifts and lights on itself (no ring), the column shows its points, a die that doesn't score is explained", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 5, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	local d1, d3 = InPlay(a)[1], InPlay(a)[3]
	local _, y0 = Center(a, d1)
	check(d1.f:IsMouseEnabled(), "a die of the roll can be picked")
	Click(w, a, d1.f)
	local _, y1 = Center(a, d1)
	check(d1.lit and d1.f.lit:IsShown() and d1.f.lit.blend == "ADD", "lit on itself")
	check(y1 < y0 - 3, "lifted (%.1f -> %.1f)", y0, y1)
	for _, r in ipairs(d1.f.regions) do check(r.tex ~= "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\glow", "no ring") end
	check(P(a).info:GetText():find("+100", 1, true), "the points: %s", P(a).info:GetText())
	eq(P(a).primary:GetText(), "Keep & roll 5"); check(P(a).primary.enabled, "Keep & roll")
	eq(P(a).bank:GetText(), "Bank 100"); check(P(a).bank.enabled, "Bank")
	Click(w, a, d3.f)
	check(P(a).info:GetText():find("the 3 doesn't score", 1, true), "explained: %s", P(a).info:GetText())
	check(not P(a).primary.enabled and not P(a).bank.enabled, "nothing to keep")
	Click(w, a, d3.f)
	check(not d3.lit, "put back")
	local kits = {}
	for _, k in ipairs(a.sounds) do kits[k] = true end
	check(kits[X(a).SND.pick] and kits[X(a).SND.unpick], "the pick and put-back sounds")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: Keep & roll: the kept dice move to your tray and shrink, the points count up over them, the rest are thrown again", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 5, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	local keep = { InPlay(a)[1], InPlay(a)[2] }
	Click(w, a, keep[1].f); Click(w, a, keep[2].f)
	w:QueueRoll(a.name, Roll(a, { 2, 2, 3, 6 }))
	local bad = {}
	local watch = Watcher(a, bad)
	local tallied
	local function Look()
		watch()
		for _, t in ipairs(P(a).tallies) do if t.fs:IsShown() then tallied = tallied or {}; tallied[#tallied + 1] = t.fs:GetText() end end
	end
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and #InPlay(a) == 4 and InPlay(a)[1].where == "lane" end, 6, Look)
	Clean(bad)
	local geo = X(a).geo
	for slot, d in ipairs(keep) do
		eq(d.where, "tray")
		local cx, cy, half = Center(a, d)
		check(math.abs(cx - (geo.TRAYX + (slot - 1) * geo.TRAYSTEP)) < 0.5 and math.abs(cy - geo.TRAY[1]) < 0.5, "in tray slot %d: %.1f,%.1f", slot, cx, cy)
		check(math.abs(half - geo.K) < 0.01, "shrunk to %d px: %.1f", geo.K, half)
	end
	check(tallied and tallied[1] == "+0" and tallied[#tallied] == "+150", "the points counted up: %s", table.concat(tallied or {}, " "))
	eq(table.concat(Values(InPlay(a)), " "), "2 2 3 6")
	-- (nothing scores: BONES, the turn's 150 lost, the dice dull)
	Step(w, 0.3)
	check(P(a).banner:IsShown() and P(a).banner.text:GetText() == "BONES!", "the BONES! banner")
	for _, d in ipairs(InPlay(a)) do check(d.dull and d.f.face.desat, "a bust's dice go dull") end
	eq(P(a).rows[1].line:GetText(), "Bones: lost 150")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: Bank: your total counts up to the new score, the row says what was banked, the House plays on its side", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 1, 1, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	for i = 1, 3 do Click(w, a, InPlay(a)[i].f) end
	eq(P(a).bank:GetText(), "Bank 1,000")
	local counts = {}
	local total = P(a).rows[1].total
	Click(w, a, P(a).bank)
	Until(w, function() counts[#counts + 1] = total:GetText(); return total:GetText() == "1,000" end, 3)
	check(#counts > 3 and counts[1] ~= "1,000", "counted up: %s", table.concat(counts, " "))
	eq(P(a).rows[1].line:GetText(), "Banked 1,000")
	local kits = {}
	for _, k in ipairs(a.sounds) do kits[k] = true end
	check(kits[X(a).SND.bank], "the bank's sound")
	-- the House's turn: its dice on the far side, simulated, and Roll waits
	local bad = {}
	Until(w, function() return X(a).S.flying[2] > 0 or (View(w, a, Id(a)).expect or {}).who == 1 end, 10, Watcher(a, bad))
	check(not P(a).primary.enabled, "Roll waits while the House plays")
	HouseDone(w, a, Watcher(a, bad))
	Clean(bad)
	check(P(a).logs[1]:GetText() ~= "" and P(a).logs[2]:GetText() ~= "", "the log's last two lines")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: hot dice: all six set aside go to the tray, come back to the hand and roll again, the points kept", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 1, 1, 5, 5, 3 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	for i = 1, 5 do Click(w, a, InPlay(a)[i].f) end
	w:QueueRoll(a.name, Roll(a, { 5 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and #InPlay(a) == 1 and InPlay(a)[1].where == "lane" end, 6)
	Click(w, a, InPlay(a)[1].f)
	eq(P(a).primary:GetText(), "Keep & roll 6 (hot)")
	w:QueueRoll(a.name, Roll(a, { 2, 3, 4, 6, 2, 3 }))
	local bad = {}
	local sawHot
	Click(w, a, P(a).primary)
	Until(w, function()
		sawHot = sawHot or (P(a).banner:IsShown() and P(a).banner.text:GetText() == "HOT DICE!")
		return Idle(a) and #InPlay(a) == 6 and InPlay(a)[6].where == "lane"
	end, 8, Watcher(a, bad))
	Clean(bad)
	check(sawHot, "the HOT DICE! banner")
	eq(#X(a).sides[1].kept, 0, "the tray emptied into the hand")
	eq(table.concat(Values(InPlay(a)), " "), "2 3 4 6 2 3")
	NoErrors(w)
end)

-- A whole game: this player plays by clicking (the best dice of each throw, banking at `bankAt`),
-- the House plays itself; every step watched. Returns the view at the end.
local function PlayGame(w, a, bankAt, bad, stats)
	local watch = Watcher(a, bad)
	for _ = 1, 400 do
		local v = View(w, a, Id(a))
		if v.over then return v end
		if v.expect.who ~= 1 or not Idle(a) then
			Step(w, 0.1, watch)
		else
			local phase = v.expect.phase
			if phase == "roll" then
				check(P(a).primary.enabled, "Roll enabled on my turn (%s)", P(a).primary:GetText())
				Click(w, a, P(a).primary)
				stats.throws = stats.throws + 1
				Until(w, function() local x = View(w, a, Id(a)) return x.over or (Idle(a) and not x.rolling) end, 10, watch)
			elseif phase == "keep" then
				local dice = v.turn.dice
				local pts, pos = R(a).Best(dice)
				local play = InPlay(a)
				for _, p in ipairs(pos) do Click(w, a, play[p].f) end
				local left = #dice - #pos
				if v.turn.points + pts >= bankAt or (left > 0 and left <= 2) then
					check(P(a).bank.enabled, "Bank enabled")
					Click(w, a, P(a).bank)
					stats.banks = stats.banks + 1
				else
					check(P(a).primary.enabled, "Keep & roll enabled")
					if left == 0 then stats.hot = stats.hot + 1 end
					Click(w, a, P(a).primary)
					stats.throws = stats.throws + 1
				end
				Until(w, function() local x = View(w, a, Id(a)) return x.over or (Idle(a) and not x.rolling) end, 10, watch)
			else
				error("phase " .. tostring(phase))
			end
		end
	end
	error("the game never ended")
end

test("1.2 the Bone Throw tables board: whole games against the House: the dice never overlap nor leave their areas, the winner's banner, then the result card; Play again goes back to the setup", function()
	local stats = { throws = 0, banks = 0, hot = 0, wins = { 0, 0 } }
	for seed = 1, 3 do
		local w, a = Practice({ seed = seed * 7, target = 2000 })
		local bad = {}
		local v = PlayGame(w, a, seed == 2 and 300 or 600, bad, stats)
		Clean(bad)
		stats.wins[v.winner] = stats.wins[v.winner] + 1
		Until(w, function() return P(a).banner:IsShown() and P(a).banner.stay end, 5)
		eq(P(a).banner.text:GetText(), v.winner == 1 and "The table is yours" or "Innkeeper Farley takes the table")
		Step(w, 2)
		local card = P(a).card
		check(card and card:IsShown(), "the result card after the banner")
		eq(card.verdict:GetText(), v.winner == 1 and "You won" or "You lost")
		eq(card.line:GetText(), "Bones · Practice against Innkeeper Farley")
		eq(card.rows[1].r:GetText(), Num(v.scores[1]))
		check(card:GetFrameStrata() == "FULLSCREEN_DIALOG", "in front of the table")
		eq(P(a).primary:GetText(), "Play again")
		Click(w, a, P(a).primary)
		check(P(a).setup:IsShown(), "Play again: the setup")
		NoErrors(w)
	end
	check(stats.throws > 10 and stats.banks >= 3, "games played: %d throws, %d banks", stats.throws, stats.banks)
end)

test("1.2 the Bone Throw tables board: the House's BONES: its dice dull on its side, its row says so, and your turn follows", function()
	local w, a = Practice({ target = 2000 })
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	Click(w, a, InPlay(a)[1].f)
	Click(w, a, P(a).bank)
	-- the House's throw: a bust (its dice come from math.random: the test's stand-in picks it)
	local real = math.random
	local fixed = false
	math.random = function(lo, hi)
		if lo == 1 and hi == 46656 and not fixed then fixed = true return R(a).Encode({ 2, 3, 4, 6, 2, 3 }) end
		if lo == nil then return real() end
		if hi == nil then return real(lo) end
		return real(lo, hi)
	end
	local ok, err = pcall(function()
		HouseDone(w, a)
	end)
	math.random = real
	if not ok then error(err, 0) end
	check(fixed, "the House threw")
	for _, d in ipairs(InPlay(a, 2)) do check(d.dull, "its dice dull") end
	eq(P(a).rows[2].line:GetText(), "Bones")
	check(P(a).primary.enabled and P(a).primary:GetText() == "Roll 6 dice", "your turn: %s %s %s", P(a).primary:GetText(), tostring(P(a).primary.enabled), tostring(P(a).info:GetText()))
	NoErrors(w)
end)

print("FarkleBoard: the layout (each thing in its own area), the guide")

-- Every visible text, button, tray and mug under `root` (skipping `skip`), with its rect (x, y,
-- right, bottom) from `base`'s top left.
local function Parts(c, root, base, skip)
	local out = {}
	local function Add(kind, o, label)
		local x, y, w, h = c.K.Within(o, base)
		if x and w > 0 and h > 0 then out[#out + 1] = { kind = kind, o = o, label = label, r = { x, y, x + w, y + h } } end
	end
	local function Walk(f)
		if not f:IsVisible() or (skip and skip[f]) then return end
		if f.template == "UIPanelButtonTemplate" then Add("button", f, f:GetText()) end
		if f.checked ~= nil and f.box then Add("check", f, f.label:GetText()) end
		for _, r in ipairs(f.regions) do
			if r.otype == "FontString" and r:IsShown() and r.text and r.text ~= "" and not (f.template and r == f.label) and not (f.box and r == f.label) then Add("text", r, r.text) end
		end
		for _, ch in ipairs(f.children) do Walk(ch) end
	end
	Walk(root)
	return out
end
local function CheckParts(parts, when, areas, overlapsOk)
	for _, p in ipairs(parts) do
		if areas then
			local home
			for name, a in pairs(areas) do if Inside(p.r, a) then home = name end end
			check(home, "%s: %s '%s' at %s is in no area (or across two)", when, p.kind, tostring(p.label), Str(p.r))
			p.home = home
		end
		if p.kind == "button" then check(p.r[4] - p.r[2] >= 32 - 0.01, "%s: button '%s' is %.0f px tall", when, tostring(p.label), p.r[4] - p.r[2]) end
		if p.kind == "text" then
			check(p.o.size >= 13, "%s: '%s' is %d px", when, p.label, p.o.size)
			if p.o.wrap == false and p.o.w then check(p.o:GetStringWidth() <= p.o.w + 0.01, "%s: '%s' is %.0f px wide in a %.0f px box", when, p.label, p.o:GetStringWidth(), p.o.w) end
		end
	end
	for a = 1, #parts do
		for b = a + 1, #parts do
			local pa, pb = parts[a], parts[b]
			local rel = pa.o.parent == pb.o or pb.o.parent == pa.o
			check(rel or (overlapsOk and overlapsOk(pa, pb)) or not Overlap(pa.r, pb.r), "%s: %s '%s' (%s) overlaps %s '%s' (%s)", when, pa.kind, tostring(pa.label), Str(pa.r), pb.kind,
				tostring(pb.label), Str(pb.r))
		end
	end
	return parts
end
local function TableParts(c)
	local p = P(c)
	local parts = Parts(c, p.win, p.win, { [p.setup] = true, [p.create] = true })
	for side = 1, 2 do
		local x, y, w, h = c.K.Within(p.rows[side].tray, p.win)
		parts[#parts + 1] = { kind = "tray", o = p.rows[side].tray, label = "tray " .. side, r = { x, y, x + w, y + h } }
		if p.rows[side].mug:IsShown() then
			x, y, w, h = c.K.Within(p.rows[side].mug, p.win)
			parts[#parts + 1] = { kind = "mug", o = p.rows[side].mug, label = "mug " .. side, r = { x, y, x + w, y + h } }
		end
	end
	return parts
end

test("1.2 the Bone Throw tables board: layout: each thing in its own area, nothing overlapping, 13 px text and 32 px buttons; rows: name and line on the left, points on the right, the mug first on a hiccup table", function()
	local w, a = Practice({ noStart = true })
	local A = X(a).AREAS
	CheckParts(TableParts(a), "setup", A)
	-- the setup: inside the table's halves, its own parts apart
	CheckParts(Parts(a, P(a).setup, P(a).win), "setup's own")
	-- a game with the hiccup (the player's own drunk lines count in practice): mugs on the rows
	Click(w, a, P(a).setup.start)
	w:Run(0)
	w:QueueRoll(a.name, Roll(a, { 1, 5, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
	Click(w, a, InPlay(a)[1].f)
	X(a).S.hint = "No /roll line in 6 seconds. Roll again, or type /roll 46656."
	Board(a).Refresh()
	local parts = CheckParts(TableParts(a), "in a game", A)
	X(a).S.hint = nil
	local of = {}
	for _, p in ipairs(parts) do of[p.o] = p end
	local rows = P(a).rows
	for side, area in ipairs({ "nearRow", "farRow" }) do
		local name, line, total, mug = of[rows[side].name], of[rows[side].line], of[rows[side].total], of[rows[side].mug]
		check(name and name.home == area and line and line.home == area and total and total.home == area, "row %d's parts out of the row", side)
		check(line.r[2] >= name.r[4] - 1, "row %d: the line isn't under the name", side)
		check(total.r[1] > name.r[3] + 100 and total.r[3] > A[area][3] - 30, "row %d: the points aren't on the right", side)
		check(mug and mug.home == area and mug.r[3] <= name.r[1], "row %d: the mug before the name", side)
	end
	local _, iy, _, ih = a.K.Within(P(a).info, P(a).win)
	local _, py = a.K.Within(P(a).primary, P(a).win)
	check(iy + ih <= py, "the info box runs into the buttons")
	check(P(a).info.maxLines and P(a).info.maxLines <= 5, "the info box has no line limit")
	-- the create panel: its controls inside it, none over another
	Board(a).OpenCreate({ guest = P2, stake = 50000, mode = "a" })
	w:Run(0)
	local cp = P(a).create
	local cx, cy, cw, ch = a.K.Within(cp, P(a).win)
	local box = { cx, cy, cx + cw, cy + ch }
	check(Inside(box, { A.farHalf[1], A.farHalf[2], A.nearHalf[3], A.nearHalf[4] }), "the create panel within the halves: %s", Str(box))
	for _, p in ipairs(CheckParts(Parts(a, cp, P(a).win), "create panel")) do check(Inside(p.r, box), "create panel: '%s' out of it", tostring(p.label)) end
	CheckParts(TableParts(a), "create", A)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the original wooden halves cover the play canvas without the texture seam; parchment stays on the guide", function()
	local w, a = Practice()
	local win = P(a).win
	check(win.table and #win.table == 2, "the play canvas uses the original two wooden halves")
	local top, bottom = win.table[1], win.table[2]
	local wood = "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\table"
	eq(top.tex, wood); eq(bottom.tex, wood)
	eq(table.concat(top.coords, ","), table.concat({ 0, 1, 0, 250 / 512 }, ","))
	eq(table.concat(bottom.coords, ","), table.concat({ 0, 1, 260 / 512, 1 }, ","), "neither half samples the seam")
	eq(top.parent, win); eq(bottom.parent, win)
	eq(top.points[1].point, "TOPLEFT"); eq(top.points[1].relPoint, "TOPLEFT"); eq(top.points[1].y, 0)
	eq(top.points[2].point, "BOTTOMRIGHT"); eq(top.points[2].relPoint, "TOPRIGHT")
	eq(bottom.points[1].point, "TOPLEFT"); eq(bottom.points[1].relPoint, "TOPLEFT")
	eq(top.points[2].y, -197); eq(bottom.points[1].y, top.points[2].y, "both halves meet without a gap")
	eq(bottom.points[2].point, "BOTTOMRIGHT"); eq(bottom.points[2].relPoint, "TOPRIGHT"); eq(bottom.points[2].y, -400)
	for _, half in ipairs(win.table) do
		for _, point in ipairs(half.points) do eq(point.rel, win); eq(point.x, 0, "the wood covers the full canvas width") end
	end
	eq(win:GetWidth(), 800); eq(win:GetHeight(), 456); eq(win:GetScale(), 1.1, "the 400px table and its scale stay; the shared games footer is 56px")
	eq(P(a).help.bg.tex, "Interface\\QuestFrame\\QuestBG", "the rules remain parchment")
	check(P(a).shell.border, "the game border stays"); eq(P(a).shell.TitleContainer, nil, "no header over the X")
	for name in pairs(a.K.named) do check(name:find("^OlympusArena"), "a frame named %s", name) end
	check(a.K.named.OlympusArenaBoneThrow == P(a).win, "the table")
	-- the dice's art: the bone die's faces and its tumble, from the companion's media
	local d = X(a).sides[1].dice[1]
	eq(d.f.face.tex, "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\faces")
	eq(d.f.tumble.tex, "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\tumble")
	check(d.f.flip and d.f.flip.anims[1].kind == "FlipBook" and d.f.flip.anims[1].FlipBookFrames == 16, "the tumble a 16-frame FlipBook")
	NoErrors(w)
end)

-- The face an icons.tga cell shows (from its texcoords: column v is face v, one row); nil for
-- anything else.
local function Cell(c)
	if type(c) ~= "table" or #c ~= 4 then return nil end
	local v = c[2] * 8
	if v % 1 ~= 0 or v < 1 or v > 6 or c[1] ~= (v - 1) / 8 or c[3] ~= 0 or c[4] ~= 1 then return nil end
	return v
end
local function Faces(icons) local out = {} for i, t in ipairs(icons or {}) do out[i] = Cell(t.coords) or 0 end return out end
local function Amount(fs) return tonumber((fs:GetText():gsub("[+,]", ""))) end
local function Lit(icons) local out = {} for i, t in ipairs(icons) do if t.lit then out[#out + 1] = i end end return out end
local function Same(a, b, msg)
	local sa, sb = table.concat(a, " "), table.concat(b, " ")
	if sa ~= sb then error(("%s: got {%s}, want {%s}"):format(msg or "lists differ", sa, sb), 2) end
end
local function Guide(o)
	local w, a = Practice({ noStart = true, screen = o and o.screen })
	Board(a).ShowGuide()
	return w, a, P(a).help
end

test("1.2 the Bone Throw tables board: the guide's pages: four tabs (Rules, Scores, Examples, Drink) in Morpheus, not buttons; Next and Back switch them; it reopens where it was left", function()
	local w, a, h = Guide()
	local geo = X(a).guide
	local names = {}
	for k, tab in ipairs(h.tabs) do
		names[k] = tab.text:GetText()
		check(tab.template == nil and tab.text.font == geo.MORPHEUS, "tab %d looks like Back and Next", k)
	end
	Same(names, { "Rules", "Scores", "Examples", "Drink" }, "tabs")
	local function On(k)
		for i, pg in ipairs(h.pages) do
			check(pg:IsVisible() == (i == k), "page %d on page %d", i, k)
			check(h.tabs[i].bar:IsVisible() == (i == k), "tab %d's bar on page %d", i, k)
		end
		check(h.back:IsVisible() == (k > 1) and h.next:IsVisible() == (k < 4), "Back/Next on page %d", k)
	end
	On(1)
	Click(w, a, h.next); On(2)
	Click(w, a, h.next); On(3)
	Click(w, a, h.next); On(4)
	Click(w, a, h.back); On(3)
	Click(w, a, h.tabs[4]); On(4)
	Click(w, a, h.ok)
	check(not h:IsShown(), "Got it")
	Board(a).ShowGuide()
	On(4)
	eq(h.title:GetText(), "How to play Bones")
	eq(h.bg.tex, "Interface\\QuestFrame\\QuestBG", "the game's parchment")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the guide's scores: every combination under its heading, its dice scoring its points in FarkleRules; the notes are true", function()
	local w, a, h = Guide()
	local rules, C = R(a), R(a).SCORES
	local pg = h.pages[2]
	Click(w, a, h.tabs[2])
	local want = {
		["Each 1"] = { C.single[1], "single" }, ["Each 5"] = { C.single[5], "single" },
		["Four of a kind"] = { rules.Score({ 3, 3, 3, 3 }), "kind" },
		["Five of a kind"] = { rules.Score({ 6, 6, 6, 6, 6 }), "kind" },
		["Six of a kind"] = { rules.Score({ 2, 2, 2, 2, 2, 2 }), "kind" },
		["Four 1s"] = { rules.Score({ 1, 1, 1, 1 }), "kind" },
		["Run 1-2-3-4-5"] = { C.run["12345"], "run" },
		["Run 2-3-4-5-6"] = { C.run["23456"], "run" },
		["Straight 1-6"] = { C.run["123456"], "run" },
	}
	for f = 1, 6 do want["Three " .. f .. "s"] = { C.triple[f], "triple" } end
	local seen, n = {}, 0
	for _, row in ipairs(pg.rows) do
		local name = row.name:GetText()
		local wnt = want[name]
		check(wnt and not seen[name], "an unexpected row '%s'", name)
		seen[name], n = true, n + 1
		local faces = Faces(row.icons)
		check(rules.Score(faces) == Amount(row.points), "'%s': %s scores %s, the row says %s", name, table.concat(faces, " "), tostring(rules.Score(faces)), row.points:GetText())
		check(Amount(row.points) == wnt[1] and row.points:GetText() == Num(wnt[1]), "'%s' shows %s, FarkleRules %s", name, row.points:GetText(), tostring(wnt[1]))
		eq(row.group, wnt[2], name)
		if wnt[2] == "run" then check(#faces == 5 or #faces == 6, name) end
	end
	eq(n, 15)
	local notes = {}
	for i, fs in ipairs(pg.notes) do notes[i] = fs:GetText() end
	local all = table.concat(notes, " ")
	check(all:find("Only dice from one throw combine", 1, true), "the notes: %s", all)
	Same(Faces(pg.addUp), { 1, 1, 5 }, "the dice that add up")
	check(all:find("is " .. Num(rules.Score({ 1, 1, 5 })), 1, true), "1 1 5: %s", all)
	check(not all:find("four 1s are three 1s and a 1", 1, true), "KCD2 four of a kind is multiplicative: %s", all)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the guide's examples: two turns of two throws; the dice lit are FarkleRules.Best's, the points its Score's; BONES dull, HOT DICE all lit", function()
	local w, a, h = Guide()
	local rules = R(a)
	local ex = h.pages[3].examples
	local titles = {}
	for i, e in ipairs(ex) do titles[i] = e.title:GetText() end
	eq(#ex, 4, table.concat(titles, " | "))
	eq(titles[2], "BONES!"); eq(titles[4], "HOT DICE!")
	for i, e in ipairs(ex) do
		local faces = Faces(e.icons)
		local pts, pos = rules.Best(faces)
		for j, t in ipairs(e.before) do check(t.lit, "example %d: die %d set aside isn't lit", i, j) end
		if pts > 0 then
			Same(Lit(e.icons), pos, "example " .. i .. "'s dice lit")
			eq(e.points:GetText(), "+" .. Num(pts), "example " .. i)
		else
			check(rules.Farkle(faces), "example %d scores nothing but isn't a bust", i)
			for j, t in ipairs(e.icons) do check(t.desat, "the bust's die %d isn't dull", j) end
			eq(e.points:GetText(), Num(ex[i - 1].example.points) .. " lost")
		end
	end
	-- the hot dice: every die of the last throw scores, and six were set aside in all
	eq(#ex[4].before + #ex[4].icons, 6)
	eq(#Lit(ex[4].icons), #ex[4].icons)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the guide's Drink page: exact eligible-throw fractions, mugs, shake-offs and the original-throw example", function()
	local w, a, h = Guide()
	local rules = R(a)
	Click(w, a, h.tabs[4])
	local pg = h.pages[4]
	check(pg:IsVisible(), "the Drink page")
	eq(#pg.levels, 4)
	local S = FW.DRUNK.enUS
	for i, row in ipairs(pg.levels) do
		local lvl = i - 1
		eq(row.name:GetText(), ({ "Sober", "Tipsy", "Drunk", "Completely smashed" })[i])
		eq(row.line:GetText(), (S["DRUNK_MESSAGE_SELF" .. i]:gsub("%s%s+", " ")), "the game's own line for level " .. lvl)
		local wins, total, pct = rules.HiccupOdds(6, lvl)
		if pct > 0 then
			eq(row.gives:GetText(), ("HIC! %d/%d"):format(wins, total))
			eq(row.shakes:GetText(), ("%d shake-offs a game"):format(rules.SHAKES))
			check(row.fill and math.abs(row.fill.h - 28 * ({ 0.25, 0.5, 1 })[lvl]) < 0.01, "level %d's mug filled to its level", lvl)
		else
			eq(row.gives:GetText(), "a bust is a bust"); check(row.fill == nil, "the sober mug is empty")
		end
	end
	check(pg.steps[4]:GetText():find("Arrived drunk?", 1, true), "arrived drunk")
	Same(Faces(pg.example.icons), pg.example.dice, "the example's dice")
	check(rules.Farkle(pg.example.dice), "the example is a bust")
	local saved, rank, wins, total = rules.HiccupReuse(pg.example.dice, 3)
	check(pg.example.lines[1]:GetText():find(("%d of %d"):format(wins, total), 1, true), "the example's exact chance")
	eq(pg.example.rank, rank); check(saved and rank <= wins, "the original throw shakes it off")
	eq(pg.example.roll, nil, "no invented percentile roll")
	check(pg.price:GetText():find("BONES ends your turn and loses its points", 1, true), "a failed HIC ends the turn and loses its points")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the guide follows FarkleRules: a combination set to false has no row, and a changed hiccup table changes the Drink page", function()
	local w = FW.New()
	local a = Seat(w, P1)
	w:As(a, function() a.ns.Arena.LoadUI() end)
	local rules = R(a)
	local saved, hic = rules.SCORES.run["12345"], rules.HICCUP[1]
	rules.SCORES.run["12345"], rules.HICCUP[1] = false, 25
	local ok, err = pcall(function()
		w:As(a, function() Board(a).ShowGuide() end)
		local h = P(a).help
		for _, row in ipairs(h.pages[2].rows) do check(row.name:GetText() ~= "Run 1-2-3-4-5", "a row for the disabled run") end
		local wins, total = rules.HiccupOdds(6, 1)
		eq(h.pages[4].levels[2].gives:GetText(), ("HIC! %d/%d"):format(wins, total))
	end)
	rules.SCORES.run["12345"], rules.HICCUP[1] = saved, hic
	if not ok then error(err, 0) end
	NoErrors(w)
end)

-- Every visible region of the guide (texts, dice icons, lines), with its rect from its top left.
local function GuideRegions(c, h)
	local out = {}
	local function Walk(f)
		if not f:IsVisible() then return end
		if f.template == "UIPanelButtonTemplate" or f.template == "UIPanelCloseButton" then
			local x, y, wd, ht = c.K.Within(f, h)
			out[#out + 1] = { kind = "button", o = f, label = f:GetText() or "X", r = { x, y, x + wd, y + ht } }
		end
		for _, r in ipairs(f.regions) do
			if r:IsShown() and not (f.template and r == f.label) then
				local x, y, wd, ht = c.K.Within(r, h)
				if x and wd > 0 and ht > 0 then
					if r.otype == "FontString" and r.text and r.text ~= "" then out[#out + 1] = { kind = "text", o = r, label = r.text, r = { x, y, x + wd, y + ht } }
					elseif r.otype == "Texture" and (r.tex or r.color) then out[#out + 1] = { kind = "texture", o = r, label = tostring(r.tex or "line"), r = { x, y, x + wd, y + ht } } end
				end
			end
		end
		for _, ch in ipairs(f.children) do Walk(ch) end
	end
	Walk(h)
	return out
end

test("1.2 the Bone Throw tables board: the guide's layout: on every page nothing overlaps or leaves the parchment, 13 px+ dark ink, Morpheus titles, inside a 1024 x 768 screen", function()
	local w, a, h = Guide({ screen = { 1024, 768 } })
	local geo = X(a).guide
	local SAFE = geo.SAFE
	eq(h:GetWidth(), geo.W); eq(h:GetHeight(), geo.H)
	local l, b, r, t = a.K.Rect(h)
	check(l >= 0 and b >= 0 and r <= 1024 and t <= 768, "off a 1024 x 768 screen")
	local skip = { [h.bg] = true }
	for _, x in ipairs(h.frame) do skip[x] = true end
	for k in ipairs(h.pages) do
		Click(w, a, h.tabs[k])
		local parts, heads = {}, 0
		for _, e in ipairs(GuideRegions(a, h)) do
			local o = e.o
			local keep = not skip[o] and not (e.kind == "texture" and o.blend == "ADD")
			if keep and e.kind == "texture" and o.tex == geo.ICONS then
				local cx, cy = (e.r[1] + e.r[3]) / 2, (e.r[2] + e.r[4]) / 2
				local rr = 34 / 128 * (e.r[3] - e.r[1])
				e.r = { cx - rr, cy - rr, cx + rr, cy + rr }
			elseif keep and e.kind == "texture" and o.color then
				check(e.r[4] - e.r[2] <= 3 or e.r[3] - e.r[1] <= 3, "page %d: an unexpected texture", k)
			elseif keep and e.kind == "text" then
				check(o.size >= 13, "page %d: '%s' is %d px", k, e.label, o.size)
				local col = o.textColor
				check(0.2126 * col[1] + 0.7152 * col[2] + 0.0722 * col[3] <= 0.35, "page %d: '%s' isn't dark ink", k, e.label)
				if o.size >= 16 then check(o.font == geo.MORPHEUS, "page %d: the title '%s' isn't in Morpheus", k, e.label) end
				if o.font == geo.MORPHEUS and o.size >= 16 and o ~= h.title then heads = heads + 1 end
				check(o.wrap == false or o == h.title, "page %d: '%s' may wrap", k, e.label)
				if o.w then check(o:GetStringWidth() <= o.w + 0.01, "page %d: '%s' is %.0f px wide in a %.0f px box", k, e.label, o:GetStringWidth(), o.w) end
			end
			if keep then
				parts[#parts + 1] = e
				if o ~= h.close then check(Inside(e.r, SAFE), "page %d: %s '%s' at %s leaves the parchment", k, e.kind, e.label, Str(e.r)) end
			end
		end
		check(heads >= 2, "page %d has %d headings in Morpheus", k, heads)
		for x = 1, #parts do
			for y = x + 1, #parts do
				local pa, pb = parts[x], parts[y]
				local lines = pa.o.color or pb.o.color
				local mug = pa.o.fillOf == pb.o or pb.o.fillOf == pa.o
				check(lines or mug or not Overlap(pa.r, pb.r), "page %d: '%s' (%s) overlaps '%s' (%s)", k, pa.label, Str(pa.r), pb.label, Str(pb.r))
			end
		end
	end
	NoErrors(w)
end)

print("FarkleBoard: the hiccup (the design), the live table, watchers, combat, Escape")

-- math.random as the House's dice: `rolls` first (its /roll 1-6^n), then the real one.
local function HouseRolls(rolls, fn)
	local real = math.random
	math.random = function(lo, hi)
		if lo == 1 and hi and hi >= 6 and hi ~= 100 and #rolls > 0 and ({ [6] = 1, [36] = 1, [216] = 1, [1296] = 1, [7776] = 1, [46656] = 1 })[hi] then
			return table.remove(rolls, 1)
		end
		if lo == nil then return real() end
		if hi == nil then return real(lo) end
		return real(lo, hi)
	end
	local ok, err = pcall(fn)
	math.random = real
	if not ok then error(err, 0) end
end

test("1.2 the Bone Throw tables board: drunk at the table: recorded level, exact mug odds and immediate original-throw HIC success or failure", function()
	local w, a = Practice({ target = 10000 })
	local rules = R(a)
	eq(View(w, a, Id(a)).hic, true, "a hiccup table (the client reads the drunk lines)")
	check(P(a).rows[1].mug:IsShown() and P(a).rows[2].mug:IsShown(), "a mug on each row")
	-- you drink: completely smashed; your own board says so, the level counts once the House decides
	w:Drink(a.name, 3)
	w:As(a, function() Board(a).Refresh() end)
	check(P(a).rows[1].mug.fill:IsShown() and math.abs(P(a).rows[1].mug.fill.h - 26) < 0.01, "practice mug immediately shows the observed drunk level")
	eq(Game(w, a).level[1], 0, "the current turn's recorded level is unchanged until the House decides")
	eq(P(a).rows[2].mug.level, 0, "the innkeeper never inherits the player's drinking")
	check(P(a).info:GetText():find("Completely smashed: counts from your next turn", 1, true), "your own board: %s", P(a).info:GetText())
	HouseRolls({ R(a).Encode({ 1, 1, 1, 2, 3, 4 }) }, function()
		w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 2 }))
		Click(w, a, P(a).primary)
		Until(w, function() return Idle(a) and InPlay(a)[1].where == "lane" end, 5)
		Click(w, a, InPlay(a)[1].f)
		Click(w, a, P(a).bank)
		HouseDone(w, a)
	end)
	local lvl, pct, shakes = rules.Level(Game(w, a), 1)
	eq(lvl, 3, "recorded by the House's keep: " .. table.concat(Game(w, a).events, " ")); eq(pct, rules.HICCUP[3]); eq(shakes, rules.SHAKES)
	local mug = P(a).rows[1].mug
	check(mug.fill:IsShown() and math.abs(mug.fill.h - 26) < 0.01, "the mug full")
	eq(P(a).rows[1].line:GetText(), "Your turn · HIC saves left: 2")
	-- The selected zero-score throw itself saves the turn; no percentile button or timer.
	local asked = #a.asked
	w:QueueRoll(a.name, Roll(a, { 2, 2, 3, 3, 4, 4 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and (View(w, a, Id(a)).expect or {}).phase == "roll" end, 5)
	eq(#a.asked, asked + 1); eq(a.asked[#a.asked].hi, rules.RANGES[6], "only the original six-dice throw")
	eq(Game(w, a).shakes[1], 1)
	check(not P(a).banner:IsShown(), "HIC success clears before the next roll is enabled")
	check(P(a).primary.enabled, "the next roll is enabled after HIC success")
	eq(P(a).rows[1].line:GetText(), "Your turn · HIC saves left: 1")
	local wins, total = rules.HiccupTurnOdds(Game(w, a), 1)
	eq(mug.wins, wins); eq(mug.total, total)
	check(P(a).logs[1]:GetText():find("saved the original throw", 1, true) or P(a).logs[2]:GetText():find("saved the original throw", 1, true), "the original-throw save is logged")
	eq(P(a).primary:GetText(), "Roll 6 dice")
	local ring = P(a).rows[1].ring
	check(ring and not ring:IsShown(), "no separate HIC timer")
	for _, code in ipairs(Game(w, a).events) do check(not code:find("^H"), "no separate H event") end
	-- A different eligible ordered throw fails; failed saves consume no shake-off.
	w:QueueRoll(a.name, Roll(a, { 6, 6, 4, 4, 3, 3 }))
	Click(w, a, P(a).primary)
	Until(w, function() return (View(w, a, Id(a)).expect or {}).who == 2 and P(a).banner.text:GetText() == "BONES!" end, 5)
	Step(w, 0.3)
	check(P(a).banner.text:GetText() == "BONES!", "the bust stands: %s", tostring(P(a).banner.text:GetText()))
	eq(select(3, rules.Level(Game(w, a), 1)), 1, "one shake-off left")
	check(P(a).rows[1].line:GetText():find("HIC saves left: 1", 1, true), "BONES keeps the remaining HIC saves visible: %s", P(a).rows[1].line:GetText())
	NoErrors(w)
end)

-- Two players, grouped, each with the board's frames: the host's create panel sends the
-- invitation; the guest's pop-up. Returns the world, the host, the guest, the table's id.
-- (Allow spectators is ticked by default since 2026-10-04; the host unticks it here, as these
-- tables had it before, unless o.spectators.)
local function Invited(o)
	o = o or {}
	local w = FW.New({ seed = o.seed or 11 })
	local a, b = Seat(w, P1), Seat(w, P2)
	w:Group({ a, b })
	Show(w, a, "create", nil, { guest = b.name, target = 2000 })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(P(a).create.spec.checked, "Allow spectators ticked by default")
	if not o.spectators then Click(w, a, P(a).create.spec) end
	check(P(a).create:IsShown(), "the create panel")
	check(Click(w, a, P(a).create.send), "Invite")
	w:Run(0)
	local id = X(a).S.id
	check(id and View(w, a, id).role == "host", "the host's table shown")
	check(P(b).ask and P(b).ask:IsShown(), "the guest's pop-up")
	return w, a, b, id
end

test("1.2 the Bone Throw tables board: a table with another player: the create panel's invitation, the guest's pop-up (the hiccup's line, a sober table), both boards, the opening rolls, the other's dice on the far side, the result cards", function()
	local w, a, b, id = Invited()
	local rules = R(a)
	-- the create panel said who and what
	local ask = P(b).ask
	eq(ask.lines[1]:GetText(), "Torvin Hale invites you to Bones.")
	eq(ask.lines[2]:GetText(), "Play to 2,000 · 60 seconds a turn")
	eq(ask.lines[3]:GetText(), "No stake: for fun.")
	eq(ask.lines[4]:GetText(), "A rehearsal: nothing counts.")
	eq(ask.lines[5]:GetText(), "Hiccup on: drinking during the game counts.")
	eq(ask.lines[6]:GetText(), a.ns.L.FARKLE_G_DRINK_STEP_2, "the invitation describes reuse, not an extra percentile roll")
	check(ask.sober:IsShown(), "a sober table may be asked")
	check(ask.clock:GetText():find("Answer within", 1, true), "the minute")
	check(Click(w, b, ask.yes), "Accept")
	w:Run(0)
	check(not ask:IsShown(), "the pop-up closed")
	-- both boards on the table, each with his own row near
	for _, c in ipairs({ a, b }) do
		check(P(c).win:IsShown() and X(c).S.id == id and X(c).S.mode == "table", "%s's board on the table", c.short)
		if P(c).help:IsShown() then Click(w, c, P(c).help.ok) end
	end
	eq(X(a).S.near, 1); eq(X(b).S.near, 2)
	eq(P(a).rows[1].name:GetText(), "Torvin Hale"); eq(P(a).rows[2].name:GetText(), "Selka Drummond")
	eq(P(b).rows[1].name:GetText(), "Selka Drummond"); eq(P(b).rows[2].name:GetText(), "Torvin Hale")
	-- the opening: each rolls for first turn
	eq(P(a).primary:GetText(), "Roll for first turn"); check(P(a).primary.enabled, "the host's opening roll")
	eq(P(b).primary:GetText(), "Roll for first turn"); check(P(b).primary.enabled, "the guest's")
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Click(w, a, P(a).primary); Click(w, b, P(b).primary)
	eq(a.asked[#a.asked].hi, 100)
	Step(w, 0.5)
	eq(View(w, a, id).state, "play")
	check(P(a).primary.enabled and P(a).primary:GetText() == "Roll 6 dice", "the host throws first: %s", P(a).primary:GetText())
	check(not P(b).primary.enabled and P(b).primary:GetText() == "Torvin Hale plays", "the guest waits: %s", P(b).primary:GetText())
	-- the host's throw: on his near side, on the guest's far side, the same faces
	local dice = { 1, 5, 3, 4, 6, 2 }
	w:QueueRoll(a.name, Roll(a, dice))
	local bad = {}
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(a) and Idle(b) and InPlay(b, 2)[1].where == "lane" and InPlay(a, 1)[1].where == "lane" end, 6, Watcher(b, bad))
	Clean(bad)
	eq(table.concat(Values(InPlay(a, 1)), " "), "1 5 3 4 6 2")
	eq(table.concat(Values(InPlay(b, 2)), " "), "1 5 3 4 6 2")
	for _, d in ipairs(InPlay(b, 2)) do check(not d.f:IsMouseEnabled(), "the other's dice can't be picked") end
	-- he keeps the 1 and the 5 and banks: the guest sees them go to the far tray
	Click(w, a, InPlay(a)[1].f); Click(w, a, InPlay(a)[2].f)
	Click(w, a, P(a).bank)
	Until(w, function() return Idle(b) and #X(b).sides[2].kept == 2 end, 6)
	eq(P(b).rows[2].line:GetText(), "Banked 150")
	Until(w, function() return P(b).rows[2].total:GetText() == "150" end, 3)
	check(P(b).primary.enabled and P(b).primary:GetText() == "Roll 6 dice", "the guest's turn: %s", P(b).primary:GetText())
	-- the host concedes (twice: Concede, then Sure?): the result cards
	eq(P(a).extra:GetText(), "Concede")
	Click(w, a, P(a).extra)
	eq(P(a).extra:GetText(), "Sure? Concede")
	Click(w, a, P(a).extra)
	w:Run(0)
	Step(w, 3)
	check(P(b).card and P(b).card:IsShown() and P(b).card.verdict:GetText() == "You won", "the guest's card")
	check(P(a).card and P(a).card:IsShown() and P(a).card.verdict:GetText() == "You lost", "the host's card")
	eq(P(b).card.line:GetText(), "Bones · against Torvin Hale")
	eq(P(b).card.note:GetText(), "No stake: for fun.")
	eq(P(a).primary:GetText(), "Play again")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: an invitation's pop-up closed unanswered: the table shows it waiting, and Answer brings the pop-up back", function()
	local w, a, b, id = Invited()
	Click(w, b, P(b).ask.close)
	check(not P(b).ask:IsShown(), "closed with its X")
	Show(w, b, "board")
	if P(b).help:IsShown() then Click(w, b, P(b).help.ok) end
	eq(X(b).S.id, id)
	check(P(b).info:GetText():find("Torvin Hale invited you", 1, true), "waiting: %s", P(b).info:GetText())
	eq(P(b).extra:GetText(), "Answer")
	Click(w, b, P(b).extra)
	check(P(b).ask:IsShown() and P(b).ask.id == id, "the pop-up again")
	Click(w, b, P(b).ask.yes)
	w:Run(0)
	eq(View(w, a, id).state, "open")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the guest's 'Ask for a sober table' makes it sober on both sides; his 'Allow spectators' (ticked by default) announces the table", function()
	local w, a, b, id = Invited({ spectators = true })
	local ask = P(b).ask
	check(ask.spec.checked, "Allow spectators ticked by default")
	Click(w, b, ask.sober)
	check(ask.sober.checked and ask.spec.checked, "ticked")
	Click(w, b, ask.yes)
	w:Run(0)
	eq(View(w, a, id).hic, false); eq(View(w, b, id).hic, false)
	check(not P(a).rows[1].mug:IsShown(), "no mug on a sober table")
	eq(#w:Sent({ from = b, type = "KN" }) >= 1, true, "announced by the guest who allows watchers")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the host's 'Allow spectators' unticked keeps watchers out, though his guest's stays ticked", function()
	local w, a, b, id = Invited()
	check(P(b).ask.spec.checked, "the guest's ticked")
	Click(w, b, P(b).ask.yes)
	w:Run(0)
	eq(View(w, b, id).noWatch, true)
	eq(#w:Sent({ type = "KN" }), 0, "announced by nobody")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: a watcher's table (the players allow it): read-only, relayed by a player, the thrower's dice on his side with the relayed faces; Stop watching", function()
	local w, a, b, id = Invited({ spectators = true })
	local c = Seat(w, WATCHER)
	Click(w, b, P(b).ask.spec) -- (the guest relays nothing: the host is the relayer)
	Click(w, b, P(b).ask.yes)
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	for _, c in ipairs({ a, b }) do if P(c).help:IsShown() then Click(w, c, P(c).help.ok) end end
	Click(w, a, P(a).primary); Click(w, b, P(b).primary)
	Step(w, 0.5)
	eq(w:As(c, function() return c.ns.FarkleTable.Watchable(a.name) end), id)
	Show(w, c, "watch", id)
	w:Run(0)
	if P(c).help:IsShown() then Click(w, c, P(c).help.ok) end
	check(P(c).win:IsShown() and X(c).S.id == id, "the watcher's board")
	eq(View(w, c, id).role, "watch")
	eq(P(c).rows[1].name:GetText(), "Torvin Hale"); eq(P(c).rows[2].name:GetText(), "Selka Drummond")
	eq(P(c).primary:GetText(), "Watching"); check(not P(c).primary.enabled, "read-only")
	check(not P(c).bank:IsShown(), "no Bank")
	eq(P(c).extra:GetText(), "Stop watching")
	eq(P(c).win.stage:GetText(), "Relayed by Torvin Hale")
	w:QueueRoll(a.name, Roll(a, { 1, 5, 3, 4, 6, 2 }))
	Click(w, a, P(a).primary)
	Until(w, function() return Idle(c) and #InPlay(c, 1) == 6 and InPlay(c, 1)[1].where == "lane" and InPlay(c, 1)[1].value == 1 end, 8)
	eq(table.concat(Values(InPlay(c, 1)), " "), "1 5 3 4 6 2")
	check(P(c).info:GetText():find("relayed by Torvin Hale", 1, true), "the relayer named: %s", P(c).info:GetText())
	for _, d in ipairs(X(c).sides[1].dice) do check(not d.f:IsMouseEnabled(), "a watcher picks nothing") end
	Click(w, c, P(c).extra)
	check(not P(c).win:IsShown(), "Stop watching closes the table")
	eq(w:As(c, function() return c.ns.FarkleTable.Get(id) end), nil)
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: combat closes the table and brings it back after, while the table is live; it won't open in combat", function()
	local w, a = Practice({ target = 2000 })
	a.combat = true
	w:Fire(a, "PLAYER_REGEN_DISABLED")
	check(not P(a).win:IsShown(), "closed in combat")
	check(#a.printed > 0 and a.printed[#a.printed]:find("entered combat", 1, true), "said why")
	Show(w, a, "board")
	check(not P(a).win:IsShown(), "it won't open in combat")
	check(a.printed[#a.printed]:find("doesn't open in combat", 1, true), "said why: %s", a.printed[#a.printed])
	a.combat = false
	w:Fire(a, "PLAYER_REGEN_ENABLED")
	check(P(a).win:IsShown() and X(a).S.mode == "table", "back after combat, on the table")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: one game's window at a time: opening the table says so (ARENA_GAME_SHOWN 'farkle'), another game's window opening closes it", function()
	local w = FW.New()
	local a = Seat(w, P1)
	w:As(a, function() a.ns.Arena.LoadUI() end)
	local heard = {}
	a.ns.On("ARENA_GAME_SHOWN", function(key) heard[#heard + 1] = key end)
	Show(w, a, "practice")
	eq(heard[1], "farkle")
	w:As(a, function() a.ns.Fire("ARENA_GAME_SHOWN", "farkle") end)
	check(P(a).win:IsShown(), "its own key keeps it")
	w:As(a, function() a.ns.Fire("ARENA_GAME_SHOWN", "lottery") end)
	check(not P(a).win:IsShown() and not P(a).help:IsShown(), "the Lottery's window closes it, the guide with it")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: Escape closes what is on top: the guide first, then the table (one stand-in frame on the game's Escape list)", function()
	local w, a = Practice()
	Click(w, a, P(a).win.helpButton)
	check(P(a).help:IsShown() and P(a).win:IsShown(), "both open")
	eq(#a.K.special, 1); eq(a.K.special[1], "OlympusArenaBoneThrowEscape")
	w:As(a, function() a.K.Escape() end)
	check(not P(a).help:IsShown() and P(a).win:IsShown(), "the guide first")
	w:As(a, function() a.K.Escape() end)
	check(not P(a).win:IsShown(), "then the table")
	check(not P(a).esc:IsShown(), "nothing left open: the stand-in hidden")
	eq(w:As(a, function() return a.K.Escape() end), nil, "nothing more to close")
	NoErrors(w)
end)

print("FarkleBoard: the result card's money, the create panel, the arbiter, the details")

-- The card of a finished table as FarkleTable.View gives it (the core's documented model), with
-- this client's other views untouched: a stand-in for a staked game's end.
local function WithView(c, id, v, fn)
	local FTc = c.ns.FarkleTable
	local real = FTc.View
	FTc.View = function(x) if x == id then return v end return real(x) end
	local ok, err = pcall(fn)
	FTc.View = real
	if not ok then error(err, 0) end
end

test("1.2 the Bone Throw tables board: the result card in exact copper: a direct win is the stake less the guild's 6% of it; a loss is the stake, with Pay; an arbiter's win less 4% + 2%; a void gives the stakes back", function()
	local w, a = Practice()
	local S = 123400 -- 12g 34s
	local base = { id = "Kx", role = "host", seat = 1, players = { a.name, P2 }, over = true, scores = { 2100, 900 }, stake = S, target = 2000,
		src = { "o", "o" }, kind = "d", state = "end", game = { over = true } }
	local function Card(v)
		local spec
		WithView(a, "Kx", v, function() spec = w:As(a, function() return Board(a).CardSpec("Kx") end) end)
		return spec
	end
	local function With(t) local v = {} for k, x in pairs(base) do v[k] = x end for k, x in pairs(t) do v[k] = x end return v end
	-- a direct win: +S less floor(S * 6 / 100), and the fee to mail
	local fee = math.floor(S * 600 / 10000)
	local spec = Card(With({ winner = 1, lines = { { kind = "fee", copper = fee, action = "PayFee" } } }))
	eq(spec.verdict, "won"); eq(spec.bet, S); eq(spec.won, S - fee)
	eq(spec.rows[2][2], "+" .. a.ns.FarkleTable.Money(S - fee))
	eq(spec.rows[3][2], a.ns.FarkleTable.Money(fee))
	eq(spec.buttons[1][1], "Pay fee")
	check(spec.note:find("6%", 1, true), "the fee's line: %s", spec.note)
	-- a direct loss: -S, and what to pay him (the rest after a partial payment)
	spec = Card(With({ winner = 2, lines = { { kind = "pay", to = P2, copper = S, paid = 3400, action = "Pay" } } }))
	eq(spec.verdict, "lost"); eq(spec.lost, S); eq(spec.rows[2][2], "-" .. a.ns.FarkleTable.Money(S))
	eq(spec.rows[3][2], "Selka Drummond: " .. a.ns.FarkleTable.Money(S - 3400))
	eq(spec.buttons[1][1], "Pay")
	-- an arbiter's table, held by trade: the winner's net is S - g - a, and it says who pays him
	local g, arb = math.floor(S * 400 / 10000), math.floor(S * 200 / 10000)
	spec = Card(With({ winner = 1, kind = "a", arbiter = ARB, src = { "t", "t" }, settled = true }))
	eq(spec.won, S - g - arb)
	check(spec.note:find("6% (4% + the arbiter's 2%)", 1, true), "the split: %s", spec.note)
	eq(spec.rows[3][2], "paid by Oswin Marrow")
	-- a void: the stakes back
	spec = Card(With({ winner = nil }))
	eq(spec.verdict, "back"); eq(spec.rows[2][1], "Back to you")
	-- shown: the verdict big and coloured, OK and Play again
	WithView(a, "Kx", With({ winner = 2, lines = {} }), function() w:As(a, function() Board(a).ShowCard("Kx") end) end)
	local card = P(a).card
	eq(card.verdict:GetText(), "You lost"); eq(card.verdict.size, 30)
	check(card.verdict.textColor[1] > 0.5 and card.verdict.textColor[2] < 0.2, "red")
	local labels = {}
	for i, b in ipairs(card.buttons) do if b:IsShown() then labels[#labels + 1] = b:GetText() end end
	eq(table.concat(labels, ","), "OK,Play again")
	Click(w, a, card.buttons[1])
	check(not card:IsShown(), "OK closes it")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the create panel: the prefill (a match's opponent, stake and id), the stake's options only with a stake, why it can't go yet, a sober table asked in the invitation", function()
	local w = FW.New()
	local a, b = Seat(w, P1), Seat(w, P2)
	w:Group({ a, b })
	Show(w, a, "create", nil, { guest = b.name, stake = 50000, from = "M1" })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	local cp = P(a).create
	eq(cp.opp:GetText(), "Selka Drummond"); eq(cp.amount:GetText(), "5g")
	check(cp.direct:IsShown() and cp.arb:IsShown(), "a stake: how it is held")
	check(not cp.arbName:IsShown(), "direct: no arbiter")
	check(not cp.send.enabled and cp.why:GetText() == "accept the arena's rules first (the Arena tab)", "why not yet: %s", cp.why:GetText())
	w:As(a, function() a.ns.Arena.SetRules(true) end)
	w:As(a, function() Board(a).Refresh() end)
	check(not cp.send.enabled and cp.why:GetText() == "this client doesn't keep its saved data: no gold owed or traded", "the persistence gate: %s", cp.why:GetText())
	Click(w, a, cp.arb)
	check(cp.arbName:IsShown() and cp.wallet:IsShown(), "an arbiter: who, and the wallet")
	Click(w, a, cp.none)
	check(not cp.direct:IsShown() and not cp.arbName:IsShown(), "no stake: nothing to hold")
	eq(cp.amount:GetText(), "none: for fun")
	Click(w, a, cp.plus)
	eq(cp.amount:GetText(), "10s", "the smallest stake")
	Click(w, a, cp.minus)
	eq(cp.amount:GetText(), "none: for fun")
	check(cp.send.enabled, "for fun it may go: %s", cp.why:GetText())
	eq(cp.why:GetText(), "Matched by Olympus: the terms you both chose.")
	Click(w, a, cp.sober)
	Click(w, a, cp.send)
	w:Run(0)
	local ki = w:Sent({ from = a, type = "KI" })
	eq(#ki, 1)
	local f = {}
	for part in (ki[1].msg:match("^KI~T1~(.*)$") .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	eq(f[8], "0", "the host asked for a sober table")
	eq(View(w, a, X(a).S.id).state, "invite")
	check(P(a).info:GetText():find("Waiting for Selka Drummond to answer", 1, true), "waiting: %s", P(a).info:GetText())
	NoErrors(w)
end)

-- The crowd's bets (2026-10-04): the create panel offers Crowd bets, ticked, only where
-- FarkleTable takes them: a public arbiter, watchers let in, the stakes not in the wallet. It sits
-- in the stake's row, inside the panel and over nothing.
test("1.2 the Bone Throw tables board: the create panel's Crowd bets: offered (ticked) with a public arbiter, watchers and no wallet stakes; it goes in the invitation's options; laid out apart", function()
	local w = FW.New()
	local a, b = Seat(w, P1), Seat(w, P2)
	local arb = w:Player(ARB)
	w:Group({ a, b, arb })
	-- (the rules said yes to, saved data proven kept: the stake may go)
	w:Logout(a); w:Login(a)
	w:As(a, function() a.ns.Arena.SetRules(true) end)
	Show(w, a, "create", nil, { guest = b.name, stake = 50000, mode = "a", arbiter = arb.name, src = "t", rehearsal = true })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	local cp = P(a).create
	check(cp.crowd:IsShown() and cp.crowd.checked, "offered, ticked")
	eq(cp.crowd.label:GetText(), a.ns.L.ARENA_BONE_CROWD)
	eq(w:As(a, Board(a).CreateOpts).crowd, true)
	local cx, cy, cw, ch = a.K.Within(cp, P(a).win)
	local box = { cx, cy, cx + cw, cy + ch }
	-- (only the pairs with the crowd's check in them: the rest of the panel is the layout test's)
	local function Crowd(p) return p.o == cp.crowd or p.o.parent == cp.crowd end
	local parts = CheckParts(Parts(a, cp, P(a).win), "create panel with the crowd", nil, function(pa, pb) return not Crowd(pa) and not Crowd(pb) end)
	local seen = false
	for _, p in ipairs(parts) do
		if Crowd(p) then seen = true check(Inside(p.r, box), "create panel: '%s' out of it", tostring(p.label)) end
	end
	check(seen, "the crowd's check among the panel's parts")
	-- Unticked: the invitation carries no crowd.
	Click(w, a, cp.crowd)
	eq(w:As(a, Board(a).CreateOpts).crowd, nil)
	Click(w, a, cp.crowd)
	-- Spectators kept out, or the wallet's stakes: not offered, never sent.
	Click(w, a, cp.spec)
	check(not cp.crowd:IsShown(), "no watchers: no crowd")
	eq(w:As(a, Board(a).CreateOpts).crowd, nil)
	Click(w, a, cp.spec)
	check(cp.crowd:IsShown(), "watchers again")
	Click(w, a, cp.wallet)
	check(not cp.crowd:IsShown(), "the wallet's stakes: no crowd")
	eq(w:As(a, Board(a).CreateOpts).crowd, nil)
	Click(w, a, cp.wallet)
	-- Sent: the table carries it to its arbiter (KO's trailing 1).
	check(cp.send.enabled, "it may go: %s", cp.why:GetText())
	Click(w, a, cp.send)
	w:Run(0)
	eq(View(w, a, X(a).S.id).crowd, true)
	NoErrors(w)
	-- An arbiter who is not public: not offered.
	w = FW.New()
	a = Seat(w, P1)
	local c = Seat(w, P2)
	w:Group({ a, c })
	Show(w, a, "create", nil, { guest = c.name, stake = 50000, mode = "a", arbiter = WATCHER, src = "t", rehearsal = true })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(not P(a).create.crowd:IsShown(), "no public arbiter: no crowd")
	eq(w:As(a, Board(a).CreateOpts).crowd, nil)
	NoErrors(w)
end)

-- A rehearsal with a stake and the crowd's bets (the create panel offers it ticked there): its
-- stake is never traded, so the table waits for the bets' lock alone. It used to wait for both
-- stakes in the arbiter's book, which never came, and closed on "stakes"; its board said both
-- stakes were waiting and offered Pay stake for a stake nobody trades.
test("1.2 the Bone Throw tables board: a rehearsal with a stake and the crowd's bets: the wait says the crowd is betting, no Pay stake; then the game", function()
	local w = FW.New()
	local a, b = Seat(w, P1), Seat(w, P2)
	local arb = w:Player(ARB)
	for _, c in ipairs({ a, b }) do
		w:Logout(c); w:Login(c)
		w:As(c, function() c.ns.Arena.SetRules(true) end)
	end
	w:Group({ a, b, arb })
	-- (this world has no bank: the arbiter's market is taken as opened, its lock his own)
	arb.ns.Markets.Open = function() return true end
	Show(w, a, "create", nil, { guest = b.name, stake = 50000, mode = "a", arbiter = arb.name, src = "t", rehearsal = true })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(P(a).create.crowd.checked, "Crowd bets ticked")
	check(Click(w, a, P(a).create.send), "Invite")
	w:Run(0)
	local id = X(a).S.id
	assert(w:As(b, b.ns.FarkleTable.Answer, id, true, "t"))
	w:Run(0)
	assert(w:As(arb, arb.ns.FarkleTable.AnswerArbiter, id, true))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, a.ns.FarkleTable.Roll, id); w:As(b, b.ns.FarkleTable.Roll, id)
	w:Run(2)
	eq(View(w, a, id).state, "stakes")
	eq(View(w, a, id).crowdWait, true)
	Show(w, a, "board", id)
	local L = a.ns.L
	local text = P(a).info:GetText()
	check(text:find(L.FARKLE_B_CROWD_WAIT:match("^[^:]+"), 1, true) ~= nil, "the crowd's wait: %s", text)
	check(not (P(a).extra:IsShown() and P(a).extra:GetText() == L.FARKLE_B_PAY_STAKE), "no Pay stake")
	w:Run(w:As(arb, arb.ns.Arena.OpenMin, true) + 2)
	eq(View(w, a, id).state, "play", "the bets closed: the game")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: a match's hand-off (the design): practice with a matched player is a game with no stake, the match's id carried; practice with nobody is the House", function()
	local w = FW.New()
	local a, b = Seat(w, P1), Seat(w, P2)
	w:Group({ a, b })
	Show(w, a, "create", nil, { guest = b.name, stake = 30000, practice = true, from = "M7" })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(P(a).create:IsShown(), "the create panel")
	eq(P(a).create.amount:GetText(), "none: for fun")
	eq(Board(a)._.C.from, "M7")
	Click(w, a, P(a).create.send)
	w:Run(0)
	eq(w:As(a, function() return a.ns.FarkleTable.Get(X(a).S.id).from end), "M7")
	local c = Seat(w, WATCHER)
	Show(w, c, "create", nil, { practice = true })
	check(P(c).setup:IsShown() and not P(c).create:IsShown(), "the House's setup")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: the arbiter's pop-up (both players, the stake held by trade, his fee), then his read-only table with Void", function()
	local w = FW.New()
	local a, b, arb = Seat(w, P1), Seat(w, P2), Seat(w, ARB)
	w:Group({ a, b, arb })
	local id = assert(w:As(a, function() return a.ns.FarkleTable.Create({ guest = b.name, target = 2000, rehearsal = true, mode = "a", arbiter = arb.name }) end))
	w:Run(0)
	Click(w, b, P(b).ask.yes)
	w:Run(0)
	local ask = P(arb).ask
	check(ask and ask:IsShown(), "the arbiter's pop-up")
	eq(ask.title:GetText(), "Arbitrate Bones")
	eq(ask.lines[1]:GetText(), "Torvin Hale and Selka Drummond ask you to arbitrate.")
	check(ask.lines[4]:GetText():find("Your fee: 2% of the money won", 1, true), "his fee: %s", ask.lines[4]:GetText())
	check(not ask.sober:IsShown(), "no sober switch for the arbiter")
	Click(w, arb, ask.yes)
	w:Run(0)
	if P(arb).help:IsShown() then Click(w, arb, P(arb).help.ok) end
	check(P(arb).win:IsShown() and X(arb).S.id == id, "his table")
	eq(P(arb).primary:GetText(), "Arbitrating")
	check(not P(arb).bank:IsShown(), "no Bank")
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, function() a.ns.FarkleTable.Roll(id) end); w:As(b, function() b.ns.FarkleTable.Roll(id) end)
	Step(w, 0.5)
	eq(P(arb).extra:GetText(), "Void the game")
	Click(w, arb, P(arb).extra); Click(w, arb, P(arb).extra)
	w:Run(0)
	eq(View(w, a, id).over, true); eq(View(w, a, id).winner, nil, "void")
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: a client without FlipBook tumbles the dice by stepping their cells; the throw still lands on the faces", function()
	local w = FW.New({ seed = 5 })
	local a = Seat(w, P1)
	a.K.noFlipBook = true
	Show(w, a, "practice")
	Click(w, a, P(a).help.ok)
	Click(w, a, P(a).setup.start)
	w:Run(0)
	eq(X(a).flipBook(), false)
	w:QueueRoll(a.name, Roll(a, { 6, 6, 1, 2, 3, 4 }))
	Click(w, a, P(a).primary)
	local stepped = {}
	Until(w, function()
		for _, d in ipairs(InPlay(a)) do if d.f.tumble:IsShown() and d.f.tumble.coords then stepped[table.concat(d.f.tumble.coords, ",")] = true end end
		return Idle(a) and InPlay(a)[1].where == "lane"
	end, 5)
	local n = 0
	for _ in pairs(stepped) do n = n + 1 end
	check(n >= 4, "the tumble's cells stepped (%d)", n)
	eq(table.concat(Values(InPlay(a)), " "), "6 6 1 2 3 4")
	for _, d in ipairs(InPlay(a)) do check(d.f.face:IsShown() and not d.f.tumble:IsShown(), "at rest on its face") end
	NoErrors(w)
end)

test("1.2 the Bone Throw tables board: Sit does the game's /sit (flavour, never required); a pause at the tavern or in combat is said with the player's name", function()
	local w, a = Practice()
	Click(w, a, P(a).win.sit)
	eq(a.emotes and a.emotes[1], "SIT")
	local id = Id(a)
	local v = View(w, a, id)
	local paused = {}
	for k, x in pairs(v) do paused[k] = x end
	paused.practice = false
	paused.clock = { seat = 1, phase = "roll", used = 10, click = 55, claim = 65, paused = "tavern" }
	paused.away = { [2] = 1 }
	WithView(a, id, paused, function()
		w:As(a, function() Board(a).Refresh() end)
		eq(P(a).info:GetText(), "Innkeeper Farley left the table: the game waits. Back within a minute, or it's a forfeit.")
		check(P(a).win.stage:GetText():find("paused", 1, true), "the stage says paused: %s", P(a).win.stage:GetText())
		paused.clock.paused, paused.away, paused.combat = "combat", nil, { [2] = 1 }
		w:As(a, function() Board(a).Refresh() end)
		eq(P(a).info:GetText(), "Innkeeper Farley is in combat: the clock waits (two minutes a game at most).")
	end)
	NoErrors(w)
end)

---------------------------------------------------------------------------
-- The Bones window (Olympus_Arena/Games/Farkle.lua, a test build's Bones section), the owner on
-- test 32: its introduction's words centred above Start Playing, and opponent search, the match
-- and the table as components of that window, never another window.
---------------------------------------------------------------------------

-- Real counted games and movement drive the departure warning, including with the board hidden.
local function DepartureGame(camp, rehearsal)
	local w = FW.New()
	local king = w:Role("king", { companion = { state = "missing" } })
	local a, b = Seat(w, P1), Seat(w, P2)
	assert(king.Roles.SetSettings({ live = 1 }))
	w:Run(0)
	a.Arena.SetRules(true); b.Arena.SetRules(true)
	w:Group({ a, b }); w:AtInn(a.name, b.name)
	if camp then
		w:Stand(a.name, FW.ROAD, false)
		w:Stand(b.name, { cont = 0, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
		for _, c in ipairs({ a, b }) do
			rawset(c.ns, "Board", { CampOf = function(name)
				if c.ns.FarkleTable.Same(name, a.name) then return { zone = 1429, raisedAt = w.clock } end
			end })
		end
	end
	local id = assert(w:As(a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, secs = 120, rehearsal = rehearsal }))
	w:Run(0)
	assert(w:As(b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, a.ns.FarkleTable.Roll, id); w:As(b, b.ns.FarkleTable.Roll, id)
	w:Run(0)
	eq(View(w, a, id).state, "play")
	Show(w, a, "board", id)
	w:As(a, function() Board(a).Close() end)
	return w, a, b, id
end

test("1.1.6 Bones departure warning: inn and camp warn with the board closed; acknowledgment keeps the deadline; return and expiry clear it", function()
	for _, camp in ipairs({ false, true }) do
		local w, a, b, id = DepartureGame(camp)
		local home = { cont = a.pos.cont, wx = a.pos.wx, wy = a.pos.wy }
		local off = { cont = home.cont, wx = home.wx + 65, wy = home.wy }
		local showUI, requests = a.ns.FarkleTable.ShowUI, 0
		a.ns.FarkleTable.ShowUI = function(what, ...)
			if what == "away" then requests = requests + 1 end
			return showUI(what, ...)
		end
		w:Stand(a.name, off, false); Step(w, 2)
		local d = P(a).departure
		check(d and d:IsShown(), "departure warns without the board")
		check(d.Inset, "the warning's metal supplies its inset")
		for _, label in ipairs({ d.body, d.clock }) do
			eq(label:GetParent(), d.Inset, "warning text belongs to the inset, above its opaque background")
			eq(label:GetDrawLayer(), "OVERLAY", "warning text draws above the inset background")
		end
		eq(d.id, id); eq(P(a).win:IsShown(), false)
		local left = View(w, a, id).awayLeft
		local text = d.clock:GetText()
		check(text:find(tostring(left), 1, true), "the warning shows the remaining seconds: %s", text)
		Step(w, 3)
		eq(View(w, a, id).awayLeft, left - 3)
		check(d.clock:GetText() ~= text, "the independent countdown updates")
		eq(requests, 1, "one request despite repeated ticks")
		w:Stand(a.name, home, not camp); Step(w, 2)
		eq(d:IsShown(), false, "return hides a visible warning")
		eq(d.ticker, nil, "return cancels the warning's ticker")
		eq(View(w, a, id).awayLeft, nil)
		w:Stand(a.name, off, false); Step(w, 2)
		check(d:IsShown(), "the next departure warns again")
		eq(requests, 2)
		local since = a.ns.FarkleTable.Get(id).away[1]
		Click(w, a, d.ok); Step(w, 3)
		eq(d:IsShown(), false, "acknowledgment stays closed during this departure")
		eq(requests, 2, "acknowledgment does not trigger a repeat request")
		eq(a.ns.FarkleTable.Get(id).away[1], since, "acknowledgment preserves the deadline")
		eq(View(w, a, id).clock.paused, "tavern", "acknowledgment never resumes the game")
		eq(a.pos.wx, off.wx, "acknowledgment never moves the player")
		w:Stand(a.name, home, not camp); Step(w, 2)
		eq(View(w, a, id).awayLeft, nil); eq(d:IsShown(), false)
		w:Stand(a.name, off, false); Step(w, 2)
		eq(P(a).departure, d, "reuse one warning window")
		check(d:IsShown(), "a later departure warns again")
		eq(requests, 3)
		Step(w, 62)
		eq(View(w, a, id).over, true); eq(View(w, a, id).winner, 2)
		eq(View(w, a, id).awayLeft, nil); eq(d:IsShown(), false, "expiry clears the warning")
		NoErrors(w)
	end
end)

test("1.1.6 Bones departure warning: an unavailable companion retries without restarting the departure deadline", function()
	local w, a, b, id = DepartureGame(false)
	-- Simulate a failed companion load at its published boundary; keep the actual core and board.
	local loadUI, unavailable, attempts = a.ns.Arena.LoadUI, true, 0
	a.ns.Arena.LoadUI = function()
		attempts = attempts + 1
		if unavailable then return false end
		return loadUI()
	end
	w:Stand(a.name, FW.ROAD, false); Step(w, 3)
	check(attempts >= 2, "a failed load is retried")
	check(not P(a).departure or not P(a).departure:IsShown(), "no warning before a successful load")
	local since = a.ns.FarkleTable.Get(id).away[1]
	local left = View(w, a, id).awayLeft
	unavailable = false; Step(w, 2)
	check(P(a).departure and P(a).departure:IsShown(), "the successful retry shows the warning")
	eq(a.ns.FarkleTable.Get(id).away[1], since)
	eq(View(w, a, id).awayLeft, left - 2, "retry preserves the time already away")
	local loadedAttempts = attempts
	Step(w, 2); eq(attempts, loadedAttempts, "successful departure warning is requested only once")
	NoErrors(w)
end)

test("1.1.6 Bones departure warning: combat defers opening; practice and spectators are excluded, ordinary rehearsals keep venue rules", function()
	local w, a, b, id = DepartureGame(false)
	w:Combat(a, true); w:Stand(a.name, FW.ROAD, false); Step(w, 3)
	check(not P(a).departure or not P(a).departure:IsShown(), "no warning opens in combat")
	w:Combat(a, false); Step(w, 2)
	check(P(a).departure and P(a).departure:IsShown(), "the pending departure warns after combat")
	local d = P(a).departure
	Click(w, a, d.ok); Step(w, 3); eq(d:IsShown(), false)
	NoErrors(w)
	local pw, p = Practice()
	pw:As(p, function() Board(p).ShowDeparture(Id(p)) end)
	check(not P(p).departure or not P(p).departure:IsShown(), "practice never warns")
	NoErrors(pw)
	local rw, r, other, rid = DepartureGame(false, true)
	rw:Stand(r.name, FW.ROAD, false); Step(rw, 3)
	rw:As(r, function() Board(r).ShowDeparture(rid) end)
	check(P(r).departure and P(r).departure:IsShown(), "an ordinary free rehearsal still warns on departure")
	check(View(rw, r, rid).awayLeft > 0 and View(rw, r, rid).awayLeft < 60, "the existing grace is running")
	NoErrors(rw)
	local v = View(w, a, id)
	v.role, v.watching, v.seat = "watch", true, nil
	WithView(a, id, v, function() w:As(a, function() Board(a).ShowDeparture(id) end) end)
	eq(d:IsShown(), false, "a spectator cannot open a departure warning")
end)

print("The Bones window: its introduction, and Find, the match and the table inside it")

local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/match-world.lua"))(H)
local CH = assert(loadfile(H.ROOT .. "tests/arena/lib/chat-host.lua"))(H)
local DAY = 86400
local function TestBuild(w) return { n = 32, base = "1.2.0", built = w.clock - 100, expires = w.clock + 21 * DAY, commit = "abc1234", lane = "group" } end
local function Lab(c) return c.companion.own.Farkle end
local function LabParts(c) return Lab(c)._.parts() end
local function Named(c, name)
	for _, n in ipairs(c.K.special) do if n == name then return true end end
	return false
end
-- The introduction's words as drawn (y down from the window's top): the kicker's top to the
-- body's last line, against the content area (the window's top to Start Playing's top).
local function Words(c)
	local p = LabParts(c)
	local win, intro = p.win, p.intro
	local _, kickerTop = c.K.Within(intro.kicker, win)
	local _, bodyTop = c.K.Within(intro.body, win)
	local bodyBottom = bodyTop + intro.body:GetStringHeight()
	local _, buttonTop, _, buttonH = c.K.Within(intro.start, win)
	return { top = kickerTop, bottom = bodyBottom, mid = (kickerTop + bodyBottom) / 2, area = buttonTop / 2,
		buttonTop = buttonTop, buttonBottom = buttonTop + buttonH, winH = win:GetHeight() }
end
local function Centred(c, what)
	local m = Words(c)
	check(math.abs(m.mid - m.area) <= 1, "%s: the words' middle at %.1f, the space above the button's at %.1f (words %.1f-%.1f, button top %.1f)",
		what, m.mid, m.area, m.top, m.bottom, m.buttonTop)
	check(m.bottom <= m.buttonTop and m.top >= 0, "%s: the words inside the space above the button", what)
	eq(m.buttonBottom, m.winH - 58, what .. ": Start Playing stays at the bottom")
	return m
end

test("1.2 Bones window (test 32): the introduction's words are one group centred in the space above Start Playing, which stays at the bottom; at each window and screen size, in each state that shows it", function()
	for _, screen in ipairs({ { 1024, 768 }, { 1920, 1080 } }) do
		local w = FW.New()
		local a = Seat(w, P1, { testBuild = TestBuild(w) }, screen)
		-- The canonical entry now opens the lobby. Exercise this legacy lab's geometry directly.
		w:As(a, function() assert(a.ns.Arena.LoadUI()); Lab(a).Open() end)
		check(Lab(a) and Lab(a).IsOpen(), "the Bones window opened")
		local p = LabParts(a)
		check(p.intro:IsVisible() and p.intro.start:IsVisible(), "on its introduction")
		local first = Centred(a, "first use")
		-- (not merely moved down: the space above the words and below them are the same)
		check(math.abs(first.top - (first.buttonTop - first.bottom)) <= 2, "the same space above and below the words")
		-- a larger and a smaller window: the group stays in the middle of what is above the button
		for _, size in ipairs({ { 1000, 600 }, { 720, 420 } }) do
			p.win:SetSize(size[1], size[2])
			Centred(a, ("a %dx%d window"):format(size[1], size[2]))
		end
		p.win:SetSize(800, 456)
		-- longer words (another language): measured again when it shows, still centred
		local was = p.intro.body:GetText()
		p.intro.body:SetText(was .. " " .. was)
		w:As(a, function() p.intro:Hide() p.intro:Show() end)
		Centred(a, "twice the words")
		p.intro.body:SetText(was)
		-- after the practice table (the photo tour's) and after the window was closed: the same
		w:As(a, function() Lab(a).Open("practice") end)
		check(not p.intro:IsShown(), "the practice table")
		w:As(a, function() Lab(a).Open() end)
		Centred(a, "after a practice")
		w:As(a, function() Lab(a).Close() Lab(a).Open() end)
		Centred(a, "opened again")
		NoErrors(w)
	end
end)

-- The seeker in Stranglethorn (match.lua's places): a findable Bones player 400 yd away.
local SEEKER, OTHER = { cont = 0, wx = -13000, wy = 300 }, { cont = 0, wx = -13400, wy = 250 }
local function Finders(where)
	local w = H.World.New()
	local mine = { pos = SEEKER }
	for k, v in pairs(where or {}) do mine[k] = v end
	local a = MW.Client(w, "Wenna Crale", mine)
	local b = MW.Client(w, "Idris Vane", { pos = OTHER, findable = true, class = "MAGE" })
	b.Match.SetFindable(true, { d = false, b = true })
	-- (the seeker draws with the board's stand-in frames: anchors, sizes, OnShow and OnHide)
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	a.w = w
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	-- Navigation scenarios start after training, at a real inn, not the search world's road.
	for i, c in ipairs({ a, b }) do
		c.pos = { cont = FW.INN.cont, wx = FW.INN.wx + (i - 1) * 3, wy = FW.INN.wy }
		c.resting, c.mapID = true, 1429
		w:As(c, function()
			local tableRules = c.ns.FarkleTable
			check(tableRules.CanOpen() and tableRules.CanPlayPlayers(), "trained navigation player at the inn")
		end)
	end
	w:As(a, function() Lab(a).Open() end)
	return w, a, b
end
local function InWindow(c, f, base, what)
	check(f:IsVisible(), "%s: visible", what)
	eq(f:GetParent(), base, what .. ": the Bones window's component")
	local x, y, wd, ht = c.K.Within(f, base)
	check(x and x >= -0.01 and y >= -0.01 and x + wd <= base:GetWidth() + 0.01 and y + ht <= base:GetHeight() + 0.01,
		"%s: inside the window (%s %s %s %s)", what, tostring(x), tostring(y), tostring(wd), tostring(ht))
end
-- Olympus's windows on the screen now: its named frames of UIParent's that are drawn (not the
-- table's 1 px Escape proxy, FarkleBoard.lua's Escape, kept off the screen).
local function Windows(c)
	local out = {}
	for _, f in ipairs(c.K.frames) do
		if f.parent == c.K.UIParent and type(f.name) == "string" and f.name:find("^Olympus") and f:IsVisible()
			and (f.w or 0) > 1 and (f.h or 0) > 1 then out[#out + 1] = f.name end
	end
	table.sort(out)
	return table.concat(out, " ")
end
-- The client's hit test: of the drawn frames that take the mouse at a point of the screen (y up),
-- the one of the highest strata, then of the highest level.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function TopAt(c, x, y)
	local best, bs, bl
	for _, f in ipairs(c.K.frames) do
		if f.mouse and f:IsVisible() then
			local l, b, r, t = c.K.Rect(f)
			if l and x >= l and x <= r and y >= b and y <= t then
				local s, lv = STRATA[f:GetFrameStrata()] or 3, f:GetFrameLevel()
				if not best or s > bs or (s == bs and lv >= bl) then best, bs, bl = f, s, lv end
			end
		end
	end
	return best
end
-- The introduction's words and Start Playing: drawn (and Start Playing takes a click), or not.
local function IntroWords(c, on, what)
	local intro = LabParts(c).intro
	for k, r in pairs({ kicker = intro.kicker, title = intro.title, body = intro.body, start = intro.start }) do
		check(r:IsVisible() == on, "%s: the introduction's %s %s", what, k, on and "drawn" or "hidden")
	end
	if not on then check(not c.w:As(c, function() return c.K.UserClick(intro.start) end), "%s: Start Playing takes no click", what) end
end

test("1.2 Bones window (test 32): Start Playing opens Find inside the window, which stays; Cancel, its X and Escape give the introduction back; a search, its match and the table show in the same window", function()
	local w, a, b = Finders()
	local L = a.ns.L
	local p = LabParts(a)
	local win, intro = p.win, p.intro
	local UI = a.ns.Arena.ui
	check(win:IsShown() and intro:IsVisible(), "the Bones window on its introduction")
	Click(w, a, intro.start)
	local find = assert(UI.FindFrame(), "the Find sheet")
	check(win:IsShown(), "the Bones window stays open")
	InWindow(a, find, win, "the Find sheet")
	check(find:GetFrameLevel() > intro.start:GetFrameLevel(), "over the introduction and its button")
	eq(find.opts.game, "b", "the fixed Bones search")
	-- Cancel: with nothing searched, the sheet's right button gives the window back
	eq(find.stop:GetText(), L.ARENA_CANCEL)
	Click(w, a, find.stop)
	check(not find:IsShown() and win:IsShown() and intro:IsVisible(), "Cancel: the introduction again")
	-- its X
	Click(w, a, intro.start)
	check(find:IsVisible(), "again")
	Click(w, a, find.close)
	check(not find:IsShown() and win:IsShown() and intro:IsVisible(), "its X: the introduction again")
	-- Escape (mouse and keyboard): the sheet first, the window stays; the next Escape closes it
	Click(w, a, intro.start)
	w:Run(0)
	check(Named(a, "OlympusArenaFind") and not Named(a, "OlympusArenaGamesBoneThrow"), "on the Escape list: the sheet, not the window under it")
	w:As(a, function() a.K.Escape() end)
	check(not find:IsShown() and win:IsShown() and intro:IsVisible(), "Escape: the introduction again")
	w:Run(0)
	check(Named(a, "OlympusArenaGamesBoneThrow"), "the window back on the list")
	w:As(a, function() a.K.Escape() end)
	check(not win:IsShown(), "a second Escape closes the window")
	w:As(a, function() Lab(a).Open() end)

	-- Search: the sheet hands over to the search's card, in the same window
	Click(w, a, intro.start)
	Click(w, a, find.go)
	eq(a.Match.View().state, "search")
	check(not find:IsShown(), "the sheet gave way to the search's card")
	local card = assert(a.Match.Card(), "the search's card")
	check(win:IsShown(), "the Bones window still open")
	InWindow(a, card, win, "the search's card")
	-- the match: Idris says Let's go; the matched card shows in the same window
	w:Run(6)
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(a.Match.View().state, "match")
	check(win:IsShown(), "the Bones window still open")
	InWindow(a, card, win, "the match's card")
	w:Run(0)
	check(Named(a, "OlympusArenaMatchCard") and not Named(a, "OlympusArenaGamesBoneThrow"), "Escape: the card first")
	-- [Open the table]: the real table, pre-filled from the match, in the same window too
	MW.Press(w, a, "table")
	local B = UI.FarkleBoard
	local board = assert(B.Window(), "the table")
	check(win:IsShown(), "the Bones window still open")
	InWindow(a, board, win, "the table")
	eq(B._.S.mode, "create", "the create panel")
	eq(B._.C.guest, b.name, "with the matched partner")
	-- (the table's first use: How to play, its pop-up over it, read and closed)
	if B._.parts().help:IsShown() then Click(w, a, B._.parts().help.ok) end
	-- (one window: the card waits under the table, still the window's, never one of its own above
	-- it; until the review of test 32's lane this allowed the card off to UIParent, where it was
	-- drawn at the top of the screen over the window)
	eq(card:GetParent(), win, "the card still the window's")
	check(not card:IsVisible(), "the card waits under the table")
	eq(Windows(a), "OlympusArenaGamesBoneThrow", "one window on the screen")
	-- its X gives the window back, the match's card in it again
	Click(w, a, board.close)
	check(not board:IsShown() and win:IsShown(), "the table closed, the window stays")
	InWindow(a, card, win, "the match's card, back")
	-- (and under the card, the introduction's wood: its words and Start Playing give way to it)
	check(intro:IsShown(), "the introduction under it")
	IntroWords(a, false, "under the card")
	Centred(a, "after the table")
	-- closing the window: the card of a live match goes back to its own place, above
	w:As(a, function() Lab(a).Close() end)
	check(card:IsVisible() and card:GetParent() ~= win, "the live match's card above, on its own")
	MW.NoErrors(w)
	NoErrors(w)
end)

test("1.2 Bones window (test 32): with the gamepad UI nothing of ours goes on the Escape list; the sheet's X and Cancel still give the window back", function()
	H.WithGamepadUI(true, function()
		local w, a = Finders()
		local p = LabParts(a)
		w:Run(0)
		local before = #a.K.special
		check(not Named(a, "OlympusArenaGamesBoneThrow"), "the window alone: not on the Escape list")
		Click(w, a, p.intro.start)
		w:Run(0)
		local find = a.ns.Arena.ui.FindFrame()
		InWindow(a, find, p.win, "the Find sheet")
		local function Off(what)
			for _, name in ipairs({ "OlympusArenaFind", "OlympusArenaGamesBoneThrow", "OlympusArenaMatchCard" }) do
				check(not Named(a, name), "%s: %s is not on the Escape list", what, name)
			end
			eq(#a.K.special, before, what .. ": nothing written to UISpecialFrames")
		end
		Off("the sheet open")
		Click(w, a, find.close)
		w:Run(0)
		check(not find:IsShown() and p.win:IsShown() and p.intro:IsVisible(), "its X: the introduction again")
		Off("the sheet closed")
		Click(w, a, p.intro.start)
		Click(w, a, find.stop)
		w:Run(0)
		check(not find:IsShown() and p.win:IsShown(), "Cancel: the introduction again")
		Off("cancelled")
		NoErrors(w)
	end)
end)

test("1.2 Bones window (test 32): no other way bounces between windows: an invitation accepted, a practice, a table already open and the live table on reopening all show inside it; Escape closes the table, then the window", function()
	local w = FW.New({ seed = 11 })
	local a, b, c = Seat(w, P1), Seat(w, P2), Seat(w, WATCHER)
	w:Group({ a, b })
	for _, x in ipairs({ a, b, c }) do w:As(x, function() assert(x.ns.Arena.LoadUI()) end) end
	-- Selka has the Bones window open when Torvin's invitation comes: Accept shows the table there
	w:As(b, function() Lab(b).Open() end)
	local lb = LabParts(b).win
	Show(w, a, "create", nil, { guest = b.name, target = 2000 })
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(Click(w, a, P(a).create.send), "Invite")
	w:Run(0)
	local id = X(a).S.id
	check(P(b).ask and P(b).ask:IsShown(), "the guest's pop-up")
	check(Click(w, b, P(b).ask.yes), "Accept")
	w:Run(0)
	eq(X(b).S.id, id, "his table")
	InWindow(b, P(b).win, lb, "the accepted table")
	check(lb:IsShown(), "the Bones window still open")
	-- Escape: the guide first, then the table, the window back on its introduction; then the window
	if P(b).help:IsShown() then w:As(b, function() b.K.Escape() end) end
	check(not P(b).help:IsShown() and P(b).win:IsShown(), "the guide first")
	w:Run(0)
	check(not Named(b, "OlympusArenaGamesBoneThrow"), "the window off the list while the table covers it")
	w:As(b, function() b.K.Escape() end)
	check(not P(b).win:IsShown() and lb:IsShown() and LabParts(b).intro:IsVisible(), "Escape: the table, the window stays")
	w:Run(0)
	w:As(b, function() b.K.Escape() end)
	check(not lb:IsShown(), "then the window")
	-- opened again: the live table he sits at, in it
	w:As(b, function() Lab(b).Open() end)
	check(P(b).win:IsShown() and X(b).S.id == id, "the live table, back")
	InWindow(b, P(b).win, lb, "the live table on reopening")
	-- closing the window closes the table with it: no table left on its own
	w:As(b, function() Lab(b).Close() end)
	check(not P(b).win:IsShown(), "closed with the window")
	-- Torvin's table was open on its own: opening the Bones window takes it in
	check(P(a).win:IsShown() and P(a).win:GetParent() ~= (Lab(a).Window() or false), "his table on its own")
	w:As(a, function() Lab(a).Open() end)
	InWindow(a, P(a).win, Lab(a).Window(), "the table already open")
	-- Lida practises with the Bones window open: the practice table is in it
	w:As(c, function() Lab(c).Open() end)
	Show(w, c, "practice")
	if P(c).help:IsShown() then Click(w, c, P(c).help.ok) end
	InWindow(c, P(c).win, Lab(c).Window(), "the practice setup")
	check(Click(w, c, P(c).setup.start), "Start")
	w:Run(0)
	check(View(w, c, Id(c)).practice, "a practice table")
	InWindow(c, P(c).win, Lab(c).Window(), "the practice table")
	NoErrors(w)
end)

-- The words in the sheet as drawn (x and y from its top left, y down; as tall as their lines),
-- checked against every control of the sheet drawn now: inside the sheet, over none of them.
local function SheetClear(c, find, what)
	local x, y, wd = c.K.Within(find.line, find)
	local words = { x, y, x + wd, y + find.line:GetStringHeight() }
	check(words[1] >= 0 and words[2] >= 0 and words[3] <= find:GetWidth() and words[4] <= find:GetHeight(),
		"%s: the words (%s) inside the sheet (%sx%s)", what, Str(words), tostring(find:GetWidth()), tostring(find:GetHeight()))
	local controls = { find.lo, find.hi, find.findable, find.findableText, find.share, find.sharing, find.go, find.stop, find.close }
	for _, row in ipairs({ find.kind, find.level, find.reach }) do
		for _, b in ipairs(row.buttons) do controls[#controls + 1] = b end
	end
	for _, cb in ipairs(find.prefs) do controls[#controls + 1] = cb controls[#controls + 1] = cb.text end
	local n = 0
	for _, o in ipairs(controls) do
		if o:IsVisible() then
			local ox, oy, ow, oh = c.K.Within(o, find)
			local r = { ox, oy, ox + ow, oy + oh }
			check(not Overlap(words, r), "%s: the words (%s) over a control (%s)", what, Str(words), Str(r))
			n = n + 1
		end
	end
	check(n >= 12, "%s: the controls looked at (%d)", what, n)
	return words
end

test("1.2 Bones window (test 32): the Find sheet in the window is shorter and wider than on its own, its words in a column beside its rows, clear of every row and button: casual, staked and either, the first search with location sharing off", function()
	-- (a first search, location sharing off: the privacy line, the rehearsal's, then why the zone is
	-- needed, with Share while searching and Turn sharing on under them; staked, also why stakes are
	-- off here: the longest words the sheet has)
	local w, a = Finders({ sharing = false })
	local L = a.ns.L
	local p = LabParts(a)
	Click(w, a, p.intro.start)
	local find = a.ns.Arena.ui.FindFrame()
	InWindow(a, find, p.win, "the Find sheet")
	check(find:GetHeight() < 476, "shorter than the sheet on its own (%s)", tostring(find:GetHeight()))
	check(find:GetWidth() > 460, "wider than the sheet on its own (%s)", tostring(find:GetWidth()))
	check(find.share:IsShown() and find.sharing:IsShown(), "Share while searching and Turn sharing on")
	check(find.line:GetText():find(L.MATCH_FIRST_LINE, 1, true), "the privacy line")
	eq(find.opts.kind, "c", "a casual search: no amounts")
	check(not find.lo:IsShown() and not find.hi:IsShown(), "the amounts hidden")
	SheetClear(a, find, "casual")
	-- with stakes (and either) the amounts come back, the rows under them in their place again (not
	-- over them), and the words, a line longer, still clear of everything (before the review of
	-- test 32's lane they ran from 288.0 to 417.6, Share while searching at 362.0)
	for i, kind in ipairs({ "s", "e" }) do
		Click(w, a, find.kind.buttons[i + 1])
		eq(find.opts.kind, kind)
		check(find.lo:IsShown() and find.hi:IsShown(), "the amounts")
		local _, loTop, _, loH = a.K.Within(find.lo, find)
		local _, levelTop = a.K.Within(find.level.buttons[1], find)
		check(levelTop >= loTop + loH, "the level row under the amounts (%.1f, %.1f)", levelTop, loTop + loH)
		local _, lines = find.line:GetText():gsub("\n", "")
		check(lines >= 3, "%s: the four lines (%d breaks)", kind, lines)
		SheetClear(a, find, kind == "s" and "staked" or "either")
	end
	Click(w, a, find.kind.buttons[1])
	SheetClear(a, find, "casual again")
	-- Cancel; the same sheet opened on its own (Find from anywhere else): its own size, its rows
	-- where they always were, its words under them again
	Click(w, a, find.stop)
	check(not find:IsShown() and p.win:IsShown(), "Cancel: the window back")
	w:As(a, function() Lab(a).Close() end)
	w:As(a, function() a.ns.Arena.ui.OpenFind("b") end)
	check(find:IsShown() and find:GetParent() ~= p.win, "on its own")
	check(find:GetHeight() < 476, "casual standalone search no longer reserves hidden filters")
	eq(find:GetWidth(), 460, "its own width")
	local _, own = a.K.Within(find.level.buttons[1], find)
	eq(own, 84, "hidden amounts no longer reserve 86 pixels")
	check(not find.level.buttons[1]:IsShown(), "Bones does not display a level filter")
	local lx, ly, lw = a.K.Within(find.line, find)
	eq(lx, 26, "its words at the left again")
	eq(lw, 408, "as wide as they were")
	local _, prefsTop, _, prefsH = a.K.Within(find.prefs[1], find)
	check(ly >= prefsTop + prefsH, "under the rows (%.1f, %.1f)", ly, prefsTop + prefsH)
	SheetClear(a, find, "on its own, casual")
	NoErrors(w)
end)

test("1.2 Bones window (test 32): a live search's card is never lost under the Find sheet: Start Playing shows the card, and the sheet opened over it anyway leaves it there", function()
	local w, a = Finders()
	local p = LabParts(a)
	local UI = a.ns.Arena.ui
	Click(w, a, p.intro.start)
	local find = UI.FindFrame()
	Click(w, a, find.go)
	eq(a.Match.View().state, "search")
	local card = assert(a.Match.Card(), "the search's card")
	InWindow(a, card, p.win, "the search's card")
	-- its X: the window's introduction; Start Playing again brings the live search's card back,
	-- never a second search
	Click(w, a, card.close)
	check(not card:IsShown() and p.intro:IsVisible(), "the card closed, the search goes on")
	eq(a.Match.View().state, "search")
	Click(w, a, p.intro.start)
	check(card:IsShown() and not find:IsShown(), "Start Playing: the live search's card, not the sheet")
	InWindow(a, card, p.win, "the card again")
	-- the sheet opened directly over it (ArenaUI.OpenFind, as ArenaUI.Open("find") calls it):
	-- the card stays shown, in the window, over the sheet; closing the sheet leaves it there
	w:As(a, function() UI.OpenFind("b") end)
	InWindow(a, find, p.win, "the sheet")
	check(card:IsShown(), "the live card not hidden under the sheet")
	check(card:GetFrameLevel() > find:GetFrameLevel(), "over the sheet")
	eq(find.stop:GetText(), a.ns.L.ARENA_FIND_STOP, "the sheet's right button stops the search")
	Click(w, a, find.close)
	InWindow(a, card, p.win, "the live card, still there")
	eq(a.Match.View().state, "search")
	MW.NoErrors(w)
	NoErrors(w)
end)

-- (Review of the pending-conversation door, ChatRooms.OpenMatter: Raise orders the Olympus window
-- among the windows of its own strata alone. The Find sheet on its own place is a pop-up a strata
-- above them, up while it searches, and it stayed over the window brought to the front on the
-- match's tab.)
test("1.2 Bones window (review): the Find sheet on its own place, up while it searches, goes once the match it found is on its own tab in the Olympus window; another matter's tab leaves it", function()
	local w, a, b = Finders()
	CH.WithRooms(w, a)
	local h = CH.Host(a)
	local UI = a.ns.Arena.ui
	w:As(a, function() Lab(a).Close() end)
	w:As(a, function() UI.OpenFind("b") end)
	local find = UI.FindFrame()
	check(find:IsShown() and rawget(find, "host") == nil, "the sheet on its own place")
	Click(w, a, find.go)
	eq(a.Match.View().state, "search")
	check(find:IsShown(), "up while it searches")
	w:As(a, function() a.ns.Fire("CHAT_MATTER_SHOWN", "craft:0dd") end)
	check(find:IsShown(), "another matter's tab leaves it")
	w:Run(6)
	MW.Answer(w, b, "yes")
	w:Run(0)
	local view = a.Match.View()
	eq(view.state, "match")
	local key = "arena:" .. view.match.mid
	eq(table.concat(h.calls, ","), ("open %s,pin %s,raise"):format(key, key), "the match's tab, the window in front")
	check(not find:IsShown(), "the sheet gave way to it")
	check(a.Match.Card():IsShown(), "the match's card carries it on")
	MW.NoErrors(w)
	NoErrors(w)
end)

---------------------------------------------------------------------------
-- The Bones window, the review of test 32's lane: one window on a match ([Open the table]), the
-- window's X with the gamepad UI, a Find sheet already shown that changes window, the
-- introduction under a component, and combat with the table in the window.
---------------------------------------------------------------------------

print("The Bones window: one window on a match, its X, Escape, its words under a component, combat")

-- A match with Idris through the window's own Start Playing and Search; its id.
local function Matched(w, a, b)
	Click(w, a, LabParts(a).intro.start)
	Click(w, a, a.ns.Arena.ui.FindFrame().go)
	w:Run(6)
	local r = assert(MW.Last(w, a, "R"), "a request")
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(a.Match.View().state, "match")
	return (r:match("^R~(M[0-9a-z]+)~"))
end

test("1.2 Bones window (review): [Open the table] on a match leaves one window: the card waits under the table and comes back when it closes (its X, Escape, the window closing); a card asked for while the table is there shows over it, in the window, and Escape closes it before the table", function()
	local w, a, b = Finders()
	local L = a.ns.L
	local win = LabParts(a).win
	local mid = assert(Matched(w, a, b), "the match's id")
	local card = a.Match.Card()
	InWindow(a, card, win, "the match's card")
	eq(Windows(a), "OlympusArenaGamesBoneThrow", "one window: the card in it")
	local B = a.ns.Arena.ui.FarkleBoard
	local function Table(what)
		MW.Press(w, a, "table")
		if B._.parts().help:IsShown() then Click(w, a, B._.parts().help.ok) end
		InWindow(a, B.Window(), win, what)
		check(not card:IsShown() and card:GetParent() == win, "%s: the card waits under it, the window's", what)
		eq(Windows(a), "OlympusArenaGamesBoneThrow", what .. ": one window, no card above")
		return B.Window()
	end
	local board = Table("the table")
	-- Escape (mouse and keyboard): the table alone; the card back in the window, the match on
	w:Run(0)
	w:As(a, function() a.K.Escape() end)
	check(not board:IsShown() and win:IsShown(), "Escape: the table, the window stays")
	InWindow(a, card, win, "Escape: the card back")
	eq(a.Match.View().state, "match", "the match goes on")
	-- the match's room asks for its card (Details) while the table is there: over the table, inside
	-- the window; its X gives the table back, and the card the player closed stays closed
	Table("the table again")
	check(w:As(a, function() return a.Match.RoomAction(mid, "details") end), "Details")
	InWindow(a, card, win, "the card asked for")
	check(card:GetFrameLevel() > board:GetFrameLevel(), "over the table")
	eq(Windows(a), "OlympusArenaGamesBoneThrow", "one window still")
	Click(w, a, card.close)
	check(board:IsVisible() and not card:IsShown(), "the card's X: the table")
	Click(w, a, board.close)
	check(not card:IsShown() and win:IsShown(), "closed by its X, it stays closed")
	-- the same with Escape (mouse and keyboard): the card asked for alone, the table at the next
	-- one, the window at the third (before: one Escape closed the card and the table together)
	Click(w, a, LabParts(a).intro.start)
	InWindow(a, card, win, "Start Playing: the live card again")
	Table("the table, for Escape")
	check(w:As(a, function() return a.Match.RoomAction(mid, "details") end), "Details again")
	InWindow(a, card, win, "the card asked for again")
	w:Run(0)
	w:As(a, function() a.K.Escape() end)
	check(not card:IsShown() and board:IsVisible(), "Escape: the card alone, the table stays")
	w:Run(0)
	w:As(a, function() a.K.Escape() end)
	check(not board:IsShown() and not card:IsShown() and win:IsShown(), "Escape again: the table, the window stays")
	w:Run(0)
	w:As(a, function() a.K.Escape() end)
	check(not win:IsShown(), "Escape a third time: the window")
	w:As(a, function() Lab(a).Open() end)
	check(win:IsShown() and not card:IsShown(), "opened again: the card the player closed stays closed")
	-- Start Playing brings the live card back; the table over it; the window closed: the table with
	-- it, the live card above, the only window; opened again: the card in it, alone
	Click(w, a, LabParts(a).intro.start)
	InWindow(a, card, win, "Start Playing: the live card")
	Table("the table, a third time")
	w:As(a, function() Lab(a).Close() end)
	check(not board:IsShown() and not win:IsShown(), "the window closed, the table with it")
	check(card:IsVisible() and card:GetParent() ~= win, "the live card above, on its own")
	eq(Windows(a), "OlympusArenaMatchCard", "one window: the card")
	w:As(a, function() Lab(a).Open() end)
	InWindow(a, card, win, "opened again: the card in it")
	eq(Windows(a), "OlympusArenaGamesBoneThrow", "one window again")
	-- the match ends while its card waits under the table: closing the table shows how it ended
	Table("the table, a fourth time")
	MW.Press(w, b, "cancel")
	w:Run(0)
	check(a.Match.View().state ~= "match", "the match over")
	check(not card:IsShown(), "its end waits under the table too")
	Click(w, a, board.close)
	InWindow(a, card, win, "how it ended")
	eq(card.title:GetText(), L.MATCH_CARD_OVER)
	eq(Windows(a), "OlympusArenaGamesBoneThrow", "one window to the end")
	MW.NoErrors(w)
	NoErrors(w)
end)

test("1.2 Bones window (review): with the gamepad UI the window's X is drawn over its introduction and takes the click, with the Find sheet and after Cancel, and closes the window (the sheet with it)", function()
	H.WithGamepadUI(true, function()
		local w, a = Finders()
		local p = LabParts(a)
		local x = assert(p.close, "the window's X")
		local find
		local function Free(what)
			check(x:IsVisible(), "%s: the window's X drawn", what)
			local l, b2, r, t = a.K.Rect(x)
			local top = TopAt(a, (l + r) / 2, (b2 + t) / 2)
			check(top == x, "%s: the window's X takes the click (the introduction's %s)", what, tostring(top == p.intro))
			local xl, xt, xw, xh = a.K.Within(x, p.win)
			for _, f in ipairs({ find or false, a.Match.Card() or false }) do
				if f and f:IsVisible() then
					local fl, ft, fw, fh = a.K.Within(f, p.win)
					check(not Overlap({ xl, xt, xl + xw, xt + xh }, { fl, ft, fl + fw, ft + fh }), "%s: nothing of the window's over its X", what)
				end
			end
		end
		Free("the introduction")
		Click(w, a, p.intro.start)
		find = a.ns.Arena.ui.FindFrame()
		InWindow(a, find, p.win, "the Find sheet")
		Free("the Find sheet")
		Click(w, a, find.stop)
		check(not find:IsShown() and p.win:IsShown() and p.intro:IsVisible(), "Cancel: the introduction")
		Free("after Cancel")
		w:Run(0)
		check(not Named(a, "OlympusArenaGamesBoneThrow"), "nothing of ours on the Escape list")
		Click(w, a, x)
		check(not p.win:IsShown(), "the X closes the window")
		-- with the sheet open: the window's X closes the window and the sheet with it
		w:As(a, function() Lab(a).Open() end)
		Click(w, a, p.intro.start)
		check(find:IsVisible(), "the sheet again")
		Free("the sheet again")
		Click(w, a, x)
		check(not p.win:IsShown() and not find:IsShown(), "the window and its sheet closed")
		NoErrors(w)
	end)
end)

test("1.2 Bones window (review): a Find sheet already shown that moves into the Bones window, or out of it, tells the window: its Escape entry and its words follow", function()
	local w, a = Finders()
	local p = LabParts(a)
	local UI = a.ns.Arena.ui
	-- (a) the duel Find on its own (the arena window's Find opponent), then the Bones window and
	-- its Start Playing: the sheet moves in; Escape closes it alone, then the window
	w:As(a, function() Lab(a).Close() end)
	w:As(a, function() UI.OpenFind("d") end)
	local find = UI.FindFrame()
	check(find:IsShown() and find:GetParent() ~= p.win, "the duel sheet on its own")
	w:As(a, function() Lab(a).Open() end)
	check(p.win:IsShown() and find:IsShown(), "the Bones window, the duel sheet still open")
	Click(w, a, p.intro.start)
	InWindow(a, find, p.win, "the sheet moved in")
	eq(find.opts.game, "b", "a Bones search now")
	w:Run(0)
	check(Named(a, "OlympusArenaFind") and not Named(a, "OlympusArenaGamesBoneThrow"), "on the Escape list: the sheet, not the window under it")
	IntroWords(a, false, "the sheet moved in")
	w:As(a, function() a.K.Escape() end)
	check(not find:IsShown() and p.win:IsShown(), "Escape: the sheet alone")
	IntroWords(a, true, "the sheet gone")
	w:Run(0)
	check(Named(a, "OlympusArenaGamesBoneThrow"), "the window back on the list")
	-- (b) the sheet in the window, then the duel Find (the arena window's, /oly arena find): the
	-- sheet leaves the window; the window gets its Escape and its words back
	Click(w, a, p.intro.start)
	InWindow(a, find, p.win, "the Bones sheet")
	w:Run(0)
	check(not Named(a, "OlympusArenaGamesBoneThrow"), "the window off the list")
	w:As(a, function() UI.OpenFind("d") end)
	check(find:IsShown() and find:GetParent() ~= p.win, "the duel sheet on its own again")
	w:Run(0)
	check(Named(a, "OlympusArenaGamesBoneThrow"), "the window back on the list")
	IntroWords(a, true, "the sheet left")
	Click(w, a, find.close)
	check(not find:IsShown() and p.win:IsShown(), "the duel sheet closed")
	w:Run(0)
	w:As(a, function() a.K.Escape() end)
	check(not p.win:IsShown(), "Escape closes the Bones window")
	NoErrors(w)
end)

test("1.2 Bones window (review): while the Find sheet, the search's or the match's card shows in the window, the introduction's words and Start Playing give way to it, its wood under it; they come back, centred, when it closes", function()
	local w, a, b = Finders()
	local p = LabParts(a)
	IntroWords(a, true, "the introduction")
	Click(w, a, p.intro.start)
	local find = a.ns.Arena.ui.FindFrame()
	IntroWords(a, false, "the Find sheet")
	check(p.intro:IsVisible(), "the introduction's wood under the sheet")
	Click(w, a, find.close)
	IntroWords(a, true, "the sheet closed")
	Centred(a, "the sheet closed")
	Click(w, a, p.intro.start)
	Click(w, a, find.go)
	local card = assert(a.Match.Card(), "the search's card")
	InWindow(a, card, p.win, "the search's card")
	IntroWords(a, false, "the search's card")
	Click(w, a, card.close)
	IntroWords(a, true, "the search's card closed")
	Click(w, a, p.intro.start)
	InWindow(a, card, p.win, "Start Playing: the search's card")
	IntroWords(a, false, "the search's card again")
	w:Run(6)
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(a.Match.View().state, "match")
	IntroWords(a, false, "the match's card")
	-- the window closed (the live card above) and opened again: the card comes in, the words give way
	w:As(a, function() Lab(a).Close() end)
	check(card:IsVisible() and card:GetParent() ~= p.win, "the card above")
	w:As(a, function() Lab(a).Open() end)
	InWindow(a, card, p.win, "the card back in")
	IntroWords(a, false, "the card on reopening")
	Click(w, a, card.close)
	IntroWords(a, true, "nothing over the introduction")
	Centred(a, "the card closed")
	MW.NoErrors(w)
	NoErrors(w)
end)

-- An event on the stand-in's frames that registered it (the Bones window's own events frame,
-- Games/Farkle.lua's Events): their OnEvent, as the client calls it. (w:Fire reaches only the
-- core's ns.RegisterEvent handlers, where FarkleBoard's are.)
local function FrameEvent(c, event)
	local n = 0
	for _, f in ipairs(c.K.frames) do
		if f.events and f.events[event] and f.scripts.OnEvent then
			c.w:As(c, function() f.scripts.OnEvent(f, event) end)
			n = n + 1
		end
	end
	return n
end

test("1.2 Bones window (review): combat with the table in the Bones window closes both, and after it the live table comes back in that window, whichever of the two heard combat first", function()
	for _, first in ipairs({ "the table", "the window" }) do
		local w = FW.New({ seed = 11 })
		local c = Seat(w, WATCHER)
		w:As(c, function() assert(c.ns.Arena.LoadUI()) end)
		w:As(c, function() Lab(c).Open() end)
		local lab = Lab(c).Window()
		Show(w, c, "practice")
		if P(c).help:IsShown() then Click(w, c, P(c).help.ok) end
		check(Click(w, c, P(c).setup.start), "Start")
		w:Run(0)
		local id = X(c).S.id
		check(View(w, c, id).practice, "a practice table")
		InWindow(c, P(c).win, lab, "the practice table")
		c.combat = true
		if first == "the table" then
			w:Fire(c, "PLAYER_REGEN_DISABLED")
			check(FrameEvent(c, "PLAYER_REGEN_DISABLED") >= 1, "the window's own frame heard it")
		else
			check(FrameEvent(c, "PLAYER_REGEN_DISABLED") >= 1, "the window's own frame heard it")
			w:Fire(c, "PLAYER_REGEN_DISABLED")
		end
		check(not P(c).win:IsShown() and not lab:IsShown(), "%s first: both closed", first)
		Show(w, c, "board")
		check(not P(c).win:IsShown(), "%s first: the table won't open in combat", first)
		c.combat = false
		w:Fire(c, "PLAYER_REGEN_ENABLED")
		check(lab:IsShown(), "%s first: the Bones window back after combat", first)
		InWindow(c, P(c).win, lab, first .. " first: the table back, in it")
		eq(X(c).S.id, id, first .. " first: the same table")
		eq(Windows(c), "OlympusArenaGamesBoneThrow", first .. " first: one window")
		NoErrors(w)
	end
end)
