local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): BracketView.lua. A stub the arena's core created for the screens to
-- fill. The bracket (OlympusArenaBracket).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data

-- Two halves meeting at the final in the centre (the World Martial Arts Tournament's look): the
-- left half's rounds go left to right, the right half's right to left. 8 fighters make 5 columns,
-- 16 make 7, 32 show by halves (a Left half / Right half switch, the final always there); more
-- are refused. The owner's look (2026-09-30): the bracket fills its parchment. A slot (up to 170 x
-- 40 in the large window): the fighter's class icon, the tier medallion, the whole name in its
-- class colour, the score and the seed right-aligned; an empty future slot "TBD" in grey; a lost
-- fighter greyed; gold connector lines between each pair and the next round; the round's title
-- over each column (Round of 16, Quarter-finals, Semi-finals, Final); the final's slots bigger in
-- the centre with the champion above them, lit once decided; the bout being fought outlined in
-- gold and pulsing (an AnimationGroup). A click opens the fighter's profile; for the tournament's
-- promoter, a click on a finished match advances it (confirmed).
local Bracket = {}
ArenaUI.Bracket = Bracket

-- gap: between columns (room for the connectors); vgap: between slots; head: the round titles'
-- row; grow: how much taller the final's slots are.
Bracket.SIZES = {
	pane = { w = 434, h = 250, slotW = 96, slotH = 22, gap = 8, vgap = 4, head = 14, grow = 4 },
	large = { w = 960, h = 500, slotW = 170, slotH = 40, gap = 16, vgap = 10, head = 28, grow = 0 },
	overlay = { w = 860, h = 380, slotW = 150, slotH = 34, gap = 12, vgap = 8, head = 24, grow = 0 },
}
Bracket.MAX = 32

-- The bracket's size for n fighters: the power of two that holds them (byes against the top seeds).
function Bracket.SizeFor(n)
	n = tonumber(n)
	if not n or n < 2 or n > Bracket.MAX then return nil end
	local s = 4
	while s < n do s = s * 2 end
	return s
end

-- The slots' places (pure: the tests read it). n fighters, size "pane"|"large", half "L"|"R" (32
-- only; the left by default). Returns { S, rounds, columns, slots = { { round, index, slot (1|2),
-- half ("L"|"R"|"F"), col, x, y, w, h } }, width, height }, or nil and why ("size": over 32).
-- round is counted from the first (R1 = 1); the final is round `rounds`, in the centre column.
function Bracket.Layout(n, size, half)
	local S = Bracket.SizeFor(n)
	if not S then return nil, "size" end
	local geo = Bracket.SIZES[size] or Bracket.SIZES.pane
	local rounds = math.floor(math.log(S) / math.log(2) + 0.5)
	local byHalves = S >= 32
	half = half == "R" and "R" or "L"
	-- The columns: each half's rounds 1 .. rounds-1, and the final; by halves, one half's only.
	local cols = {}
	if byHalves then
		if half == "L" then
			for r = 1, rounds - 1 do cols[#cols + 1] = { half = "L", round = r } end
			cols[#cols + 1] = { half = "F", round = rounds }
		else
			cols[#cols + 1] = { half = "F", round = rounds }
			for r = rounds - 1, 1, -1 do cols[#cols + 1] = { half = "R", round = r } end
		end
	else
		for r = 1, rounds - 1 do cols[#cols + 1] = { half = "L", round = r } end
		cols[#cols + 1] = { half = "F", round = rounds }
		for r = rounds - 1, 1, -1 do cols[#cols + 1] = { half = "R", round = r } end
	end
	local gap, vgap, head, grow = geo.gap, geo.vgap or geo.gap, geo.head or 0, geo.grow or 0
	local slotW = math.min(geo.slotW, math.floor((geo.w - (#cols - 1) * gap) / #cols))
	-- The first round's slots of a half, stacked under the titles' row: as tall as they may be.
	local firstCount = S / 2
	local pitch = math.floor((geo.h - head) / firstCount)
	local slotH = math.min(geo.slotH, pitch - vgap)
	if slotH < 8 then return nil, "room" end
	pitch = slotH + vgap
	local height = head + firstCount * pitch - vgap
	local out = { S = S, rounds = rounds, columns = #cols, slots = {}, width = #cols * slotW + (#cols - 1) * gap, height = height, half = byHalves and half or nil,
		slotW = slotW, slotH = slotH, head = head, gap = gap, cols = {} }
	for ci, col in ipairs(cols) do
		local x = (ci - 1) * (slotW + gap)
		-- (The players the round starts with: 2 in the final, 4 in the semi-finals ...)
		out.cols[ci] = { x = x, w = slotW, round = col.round, half = col.half, players = S / (2 ^ (col.round - 1)) }
		if col.half == "F" then
			-- The final: one box of its two finalists, one above the other, centred exactly on the
			-- bracket's middle (where both semi-finals' connectors come in).
			local mid = head + (height - head) / 2
			local h = slotH + grow
			out.mid = mid
			out.slots[#out.slots + 1] = { round = rounds, index = 1, slot = 1, half = "F", col = ci, x = x, y = mid - h, w = slotW, h = h }
			out.slots[#out.slots + 1] = { round = rounds, index = 1, slot = 2, half = "F", col = ci, x = x, y = mid, w = slotW, h = h }
		else
			local r = col.round
			-- Round r has S / 2^(r-1) slots in the whole bracket (two a match), half of them in each
			-- half; a slot sits half way down its two feeders of the round before.
			local count = S / (2 ^ r)
			local span = 2 ^ (r - 1)
			for k = 0, count - 1 do
				local y = head + math.floor((span * k + (span - 1) / 2) * pitch)
				local matchInHalf = math.floor(k / 2) + 1
				local matchesPerHalf = count / 2
				local index = col.half == "L" and matchInHalf or (matchesPerHalf + matchInHalf)
				out.slots[#out.slots + 1] = { round = r, index = index, slot = k % 2 + 1, half = col.half, col = ci, x = x, y = y, w = slotW, h = slotH }
			end
		end
	end
	return out
end

-- Two slots overlap? (The tests' check; the layout never makes one.)
function Bracket.Overlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

---------------------------------------------------------------------------
-- The model: who is in each slot (Data.Tourney, ArenaTourney.View)
---------------------------------------------------------------------------

local function MatchAt(view, round, index)
	for _, m in ipairs(type(view) == "table" and view.matches or {}) do
		if m.round == round and m.index == index and not m.third then return m end
	end
	return nil
end
-- The fighter in a slot: { name, gk, n (seed), lost, won, current, bye }.
function Bracket.SlotFighter(view, s)
	local m = MatchAt(view, s.round, s.index)
	if not m then return nil end
	local side = s.slot == 1 and m.a or m.b
	if type(side) ~= "table" then return nil end
	if side.bye then return { bye = true } end
	local winner = m.winner
	local key = s.slot == 1 and "a" or "b"
	local won = winner ~= nil and (winner == key or winner == side.gk or winner == (s.slot == 1 and "A" or "B"))
	local lost = winner ~= nil and not won
	local current = m.state == "L" or m.state == "B" or m.state == "C" or m.state == "Y"
	return { name = side.name, gk = side.gk, n = side.n, won = won, lost = lost, current = current and not winner, fid = m.fid, match = m }
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Slot(parent)
	local b = CreateFrame("Button", nil, parent)
	-- The gold outline (the bout being fought, the champion), behind the cell.
	b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.glow:SetPoint("TOPLEFT", -2, 2)
	b.glow:SetPoint("BOTTOMRIGHT", 2, -2)
	b.glow:SetColorTexture(1, 0.78, 0.2, 0.95)
	b.glow:Hide()
	-- A small wooden plaque (the owner's call, 2026-09-30): a strip of Bones' tavern wood, as the
	-- games' bar (Games.WOOD), in a thin bronze border; light words on it.
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	local wood = own.Games and own.Games.WOOD
	if wood then
		b.bg:SetTexture(wood.file)
		b.bg:SetTexCoord(0.1, 0.9, 300 / 512, 340 / 512)
		b.bg:SetVertexColor(0.78, 0.66, 0.52)
	else
		b.bg:SetColorTexture(0.36, 0.22, 0.10, 1)
	end
	b.edge = {}
	for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = b:CreateTexture(nil, "BORDER")
		t:SetPoint(side[1]); t:SetPoint(side[2])
		if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
		b.edge[i] = t
	end
	-- (bronze; gold on the winner's path and the champion)
	function b:Edge(r, g, bl) for _, t in ipairs(self.edge) do t:SetColorTexture(r, g, bl, 1) end end
	b:Edge(0.55, 0.36, 0.16)
	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetPoint("LEFT", 3, 0)
	-- One line, centred on the cell's middle (the owner's call on build 4): the class icon, the
	-- seed (small, grey), the first name (the whole in the tooltip), the score in a fixed right
	-- column.
	b.seed = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	b.seed:SetPoint("LEFT", b.portrait, "RIGHT", 3, 0)
	b.seed:SetWidth(16)
	b.seed:SetJustifyH("RIGHT")
	b.score = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	b.score:SetPoint("RIGHT", -6, 0)
	b.score:SetWidth(26)
	b.score:SetJustifyH("RIGHT")
	b.name = b:CreateFontString(nil, "ARTWORK", Kit.Font("light"))
	b.name:SetTextColor(0.96, 0.90, 0.76)
	b.name:SetJustifyH("LEFT")
	if b.name.SetWordWrap then b.name:SetWordWrap(false) end
	b:SetScript("OnEnter", function(self)
		local who, seedN = rawget(self, "who"), rawget(self, "seedN")
		if not (GameTooltip and who) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Kit.Name(who), 1, 0.82, 0)
		if seedN then GameTooltip:AddLine(L.ARENA_BRACKET_SEED:format(seedN), 1, 1, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	-- The match being fought pulses: alpha 0.6 to 1 (an AnimationGroup, never OnUpdate).
	local ag = b.CreateAnimationGroup and b:CreateAnimationGroup()
	if ag and ag.CreateAnimation then
		local a = ag:CreateAnimation("Alpha")
		if a and a.SetFromAlpha then
			a:SetFromAlpha(1)
			a:SetToAlpha(0.6)
			a:SetDuration(0.8)
			if ag.SetLooping then ag:SetLooping("BOUNCE") end
			b.pulse = ag
		end
	end
	return b
end

-- A fighter's class file, from his profile (the class icon and the name's colour).
local function ClassOf(name)
	local p = Data.Profile and Data.Profile(name)
	local class = type(p) == "table" and Kit.V(p.class) or nil
	return ArenaUI.ClassFile and ArenaUI.ClassFile(class) or class
end

-- A gold line (a connector), from the pool of the frame's lines.
local function Line(frame, d, n, x, y, w, h, lit)
	local l = d.lines[n]
	if not l then
		l = frame:CreateTexture(nil, "BORDER")
		d.lines[n] = l
	end
	if lit then l:SetColorTexture(1, 0.82, 0.2, 1) else l:SetColorTexture(0.72, 0.55, 0.18, 0.75) end
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
	l:SetSize(math.max(1, w), math.max(1, h))
	l:Show()
end

-- Draws the bracket of tournament `tid` on `frame` (size "pane"|"large", half "L"|"R").
function Bracket.Draw(frame, tid, size, half)
	if not frame then return nil end
	local view = Data.Tourney(tid)
	local n = type(view) == "table" and (tonumber(view.size) or (view.entrants and #view.entrants)) or nil
	local layout = n and Bracket.Layout(n, size, half)
	local large = size ~= "pane"
	local d = rawget(frame, "arenaBracket")
	if not d then
		d = { slots = {}, lines = {}, titles = {} }
		frame.arenaBracket = d
		d.note = Kit.Text(frame, nil, "CENTER")
		d.note:SetPoint("CENTER")
		d.champLabel = Kit.Text(frame, "small", "CENTER")
		d.champ = Kit.Text(frame, "title", "CENTER")
	end
	for _, s in ipairs(d.slots) do s:Hide() end
	for _, l in ipairs(d.lines) do l:Hide() end
	for _, t in ipairs(d.titles) do t:SetText("") end
	d.champ:SetText("")
	d.champLabel:SetText("")
	if not layout then
		d.note:SetText(Kit.C and Kit.C("grey", L.ARENA_BRACKET_NONE) or L.ARENA_BRACKET_NONE)
		return nil
	end
	d.note:SetText("")
	local geo = Bracket.SIZES[size] or Bracket.SIZES.pane
	local ox = math.floor((geo.w - layout.width) / 2)
	-- The round's title over each column.
	for ci, col in ipairs(layout.cols) do
		local t = d.titles[ci]
		if not t then
			t = Kit.Text(frame, large and "title" or "small", "CENTER")
			d.titles[ci] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOP", frame, "TOPLEFT", ox + col.x + col.w / 2, 0)
		t:SetWidth(col.w + layout.gap)
		local key = (large and "ARENA_ROUND_" or "ARENA_ROUND_SHORT_") .. tostring(col.players)
		t:SetText(L[key] or ("R" .. tostring(col.round)))
	end
	local lines, bySlot = 0, {}
	local icon = math.max(12, layout.slotH - 6)
	for i, s in ipairs(layout.slots) do
		local b = d.slots[i] or Slot(frame)
		d.slots[i] = b
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", ox + s.x, -s.y)
		b:SetSize(s.w, s.h)
		b.portrait:SetSize(math.min(icon, s.h - 8, 26), math.min(icon, s.h - 8, 26))
		b.name:ClearAllPoints()
		b.name:SetPoint("LEFT", b.seed, "RIGHT", 4, 0)
		b.name:SetPoint("RIGHT", b.score, "LEFT", -4, 0)
		b.glow:Hide()
		local who = Bracket.SlotFighter(view, s)
		bySlot[i] = who
		b.who, b.seedN = who and who.name, who and who.n
		if who and who.name then
			local classFile = ClassOf(who.name)
			-- (The first name: before a space or a realm's hyphen; cut at the cell's edge if longer.)
			local shown = Kit.Name(who.name)
			b.name:SetText(Kit.Colored(shown:match("^([^%s%-]+)") or shown, classFile))
			b.seed:SetText(who.n and tostring(who.n) or "")
			b.score:SetText(who.won and who.match and who.match.score and tostring(who.match.score) or "")
			Kit.Portrait(b.portrait, who.name, { class = classFile })
			Kit.RoundPortrait(b.portrait, b)
			b.portrait:Show()
			b:SetAlpha(who.lost and 0.5 or 1)
			b.glow:SetShown(who.current == true or (s.half == "F" and who.won == true))
			-- (the bout being fought: a darker plaque)
			if who.current then b.bg:SetVertexColor(0.56, 0.46, 0.36) else b.bg:SetVertexColor(0.78, 0.66, 0.52) end
			if who.won then b:Edge(1, 0.82, 0.2) else b:Edge(0.55, 0.36, 0.16) end
			local pulse = rawget(b, "pulse")
			if pulse then if who.current then pulse:Play() elseif pulse.Stop then pulse:Stop() end end
			b:SetScript("OnClick", function()
				if who.match and who.won and ArenaUI.MayAdvance and ArenaUI.MayAdvance(tid) then
					Kit.Confirm(L.ARENA_BRACKET_ADVANCE:format(Kit.Name(who.name)), function() ns.ArenaHome.Call("ArenaTourney", "Advance", tid) end)
					return
				end
				if ArenaUI.ShowProfile then ArenaUI.ShowProfile(who.name) end
			end)
			if s.half == "F" and who.won then
				d.champLabel:SetText(Kit.C and Kit.C("gold", L.ARENA_BRACKET_CHAMPION) or L.ARENA_BRACKET_CHAMPION)
				d.champ:SetText(Kit.Colored(Kit.Name(who.name), classFile))
			end
		else
			local word = who and who.bye and L.ARENA_BRACKET_BYE or L.ARENA_BRACKET_TBD
			b.name:SetText("|cffd8ccb0" .. word .. "|r") -- (faded parchment on the wood)
			b:Edge(0.55, 0.36, 0.16)
			b.seed:SetText("")
			b.score:SetText("")
			b.portrait:SetTexture(nil)
			b.portrait:Hide()
			b:SetAlpha(0.45) -- (a faded plaque)
			local pulse = rawget(b, "pulse")
			if pulse and pulse.Stop then pulse:Stop() end
			b:SetScript("OnClick", nil)
		end
		b:Show()
	end
	-- The connectors: from each pair of a round to the slot it feeds in the next (gold where the
	-- winner went on), and the final's pair joined.
	local half = math.floor(layout.gap / 2)
	for i, s in ipairs(layout.slots) do
		local mate = layout.slots[i + 1]
		if s.half ~= "F" and s.slot == 1 and mate and mate.col == s.col and mate.index == s.index then
			local wa, wb = bySlot[i], bySlot[i + 1]
			local litA, litB = wa and wa.won, wb and wb.won
			local cy1, cy2 = s.y + math.floor(s.h / 2), mate.y + math.floor(mate.h / 2)
			local left = s.half == "L"
			local edge = ox + (left and (s.x + s.w) or s.x)
			local stubX = left and edge or (edge - half)
			lines = lines + 1; Line(frame, d, lines, stubX, cy1, half, 2, litA)
			lines = lines + 1; Line(frame, d, lines, stubX, cy2, half, 2, litB)
			local vx = left and (edge + half) or (edge - half)
			lines = lines + 1; Line(frame, d, lines, vx, cy1, 2, cy2 - cy1 + 2, litA or litB)
			local outX = left and vx or (vx - (layout.gap - half))
			lines = lines + 1; Line(frame, d, lines, outX, math.floor((cy1 + cy2) / 2), layout.gap - half, 2, litA or litB)
		end
	end
	-- The champion over the final's slots.
	for _, s in ipairs(layout.slots) do
		if s.half == "F" and s.slot == 1 then
			d.champ:ClearAllPoints()
			d.champ:SetPoint("BOTTOM", frame, "TOPLEFT", ox + s.x + s.w / 2, -(s.y - 6))
			d.champ:SetWidth(s.w + layout.gap)
			d.champLabel:ClearAllPoints()
			d.champLabel:SetPoint("BOTTOM", d.champ, "TOP", 0, 2)
			if d.champ:GetText() == "" or d.champ:GetText() == nil then
				d.champLabel:SetText(L.ARENA_BRACKET_CHAMPION)
				d.champ:SetText(Kit.C and Kit.C("grey", L.ARENA_BRACKET_TBD) or L.ARENA_BRACKET_TBD)
			end
		end
	end
	return layout
end

-- The promoter of a tournament advances it from the bracket.
function ArenaUI.MayAdvance(tid)
	local view = Data.Tourney(tid)
	return type(view) == "table" and view.promoter ~= nil and ns.FullName(view.promoter):lower() == tostring(ns.me):lower()
end

-- The bracket as text: "R1: Torvin Hale def. Selka Drummond (1:12, KO) | ...".
function Bracket.CopyText(tid)
	local view = Data.Tourney(tid)
	if type(view) ~= "table" then return "" end
	local byRound = {}
	for _, m in ipairs(view.matches or {}) do
		local a = type(m.a) == "table" and m.a.name or "-"
		local b = type(m.b) == "table" and m.b.name or "-"
		local text
		if m.winner then
			local aWon = m.winner == "a" or m.winner == "A" or (type(m.a) == "table" and m.winner == m.a.gk)
			text = L.ARENA_DEFEATED:format(Kit.Name(aWon and a or b), Kit.Name(aWon and b or a)) .. (m.score and (" (" .. m.score .. ")") or "")
		else
			text = L.ARENA_VS:format(Kit.Name(a), Kit.Name(b))
		end
		local key = m.third and "3rd" or ("R" .. tostring(m.round))
		byRound[key] = byRound[key] or {}
		table.insert(byRound[key], text)
	end
	local out = {}
	for r = 1, tonumber(view.rounds) or 5 do
		if byRound["R" .. r] then out[#out + 1] = "R" .. r .. ": " .. table.concat(byRound["R" .. r], " | ") end
	end
	if byRound["3rd"] then out[#out + 1] = "3rd: " .. table.concat(byRound["3rd"], " | ") end
	return Kit.Plain(table.concat(out, "\n"))
end

---------------------------------------------------------------------------
-- The large window (900 x 560, movable; also one of the overlay's modes)
---------------------------------------------------------------------------

local window
function Bracket.Open(tid)
	if not window then
		-- (1000 x 620: the columns fit inside, under the title, 20 px in.)
		window = Kit.Frame("OlympusArenaBracket", 1000, 620, { title = L.ARENA_BRACKET, point = { "CENTER", 0, 0 } })
		window.body = CreateFrame("Frame", nil, window)
		window.body:SetPoint("TOPLEFT", 20, -56)
		window.body:SetSize(960, 500)
		window.half = "L"
		window.left = Kit.Button(window, 110, 24, L.ARENA_BRACKET_LEFT, function() window.half = "L" Bracket.Draw(window.body, window.tid, "large", "L") end)
		window.left:SetPoint("BOTTOMLEFT", 20, 12)
		window.right = Kit.Button(window, 110, 24, L.ARENA_BRACKET_RIGHT, function() window.half = "R" Bracket.Draw(window.body, window.tid, "large", "R") end)
		window.right:SetPoint("LEFT", window.left, "RIGHT", 6, 0)
		window.copy = Kit.Button(window, 110, 24, L.ARENA_BTN_COPY, function() Kit.Copy(L.ARENA_BRACKET, Bracket.CopyText(window.tid)) end)
		window.copy:SetPoint("BOTTOMRIGHT", -20, 12)
		ns.On("ARENA_CHANGED", function() if window:IsShown() then ns.SafeCall("arena bracket", Bracket.Draw, window.body, window.tid, "large", window.half) end end)
	end
	window.tid = tid
	window:Show()
	local layout = Bracket.Draw(window.body, tid, "large", window.half)
	local halves = layout and layout.half ~= nil
	window.left:SetShown(halves)
	window.right:SetShown(halves)
	return window
end
function Bracket.Window() return window end
