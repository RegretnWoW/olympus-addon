local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local UI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local function Seat(w)
	local c = w:Player(H.World.NAMES.fighterA, { companion = {}, compliance = "shipped" })
	c.K = UI.New(function() return w.clock end); c.K.Install(c.globals)
	eq(w:As(c, function() return c.ns.Arena.LoadUI() end), true)
	return c
end
local function Open(w, c)
	w:As(c, function() c.ns.FarkleTable.ShowUI("practice", nil, { target = 2000 }) end)
	local parts = c.ns.Arena.ui.FarkleBoard._.parts()
	if parts.help:IsShown() then w:As(c, function() c.K.UserClick(parts.help.ok) end) end
	return parts
end
local function NoErrors(w, c)
	for _, err in ipairs(c.errors) do error(err, 2) end
	for _, err in ipairs(c.K.errors) do error(err, 2) end
end
test("Bones board layout: actual shared games footer replaces the repeated table crop with unchanged play geometry", function()
	local w = FW.New(); local c = Seat(w)
	local games = c.companion.own.Games
	local actual, built, calls = games.Bar, nil, 0
	games.Bar = function(...)
		calls = calls + 1; built = actual(...); return built
	end
	local p = Open(w, c)
	eq(calls, 1); eq(p.win.bar, built); eq(p.win.helpButton, built.help)
	eq(built.y, 400); eq(built.h, 56); eq(p.win:GetWidth(), 800); eq(p.win:GetHeight(), 456)
	eq(built.wood.tex, games.WOOD.file); eq(built.wood.h, games.BAR.H)
	eq(built.wallet.coin:IsShown(), false); eq(built.wallet.balance:IsShown(), false, "existing wallet gate stays closed")
	eq(p.win.table[1].tex, "Interface\\AddOns\\Olympus_Arena\\media\\farkle\\table")
	eq(p.win.table[2].points[2].y, -400); eq(#p.win.table, 2)
	local geo = c.ns.Arena.ui.FarkleBoard._.geo
	eq(geo.W, 800); eq(geo.H, 400); eq(geo.SPLIT, 197); eq(geo.TRAY[1], 366); eq(geo.TRAY[2], 31)
	for _, button in ipairs({ p.primary, p.bank }) do
		local _, y, _, height = c.K.Within(button, p.win)
		eq(y >= 400 + 10, true); eq(y + height <= 456 - 10, true)
	end
	w:As(c, function() c.K.UserClick(p.win.helpButton) end); eq(p.help:IsShown(), true)
	NoErrors(w, c)
end)
test("Bones board layout: target and round clear the top plank while opponent text moves up without moving the tray", function()
	local w = FW.New(); local c = Seat(w); local p = Open(w, c)
	local _, subY = c.K.Within(p.win.sub, p.win)
	local _, stageY = c.K.Within(p.win.stage, p.win)
	eq(subY >= 62 + 6, true); eq(stageY - subY >= 20, true)
	local _, nameY = c.K.Within(p.rows[2].name, p.win)
	local _, lineY = c.K.Within(p.rows[2].line, p.win)
	eq(nameY, 7); eq(lineY, 33)
	eq(c.ns.Arena.ui.FarkleBoard._.geo.TRAY[2], 31)
	NoErrors(w, c)
end)
test("Bones board layout: two wider wrapped log slots have breathing room and stop above the shared footer", function()
	local w = FW.New(); local c = Seat(w); local p = Open(w, c)
	local first, second = p.logs[1], p.logs[2]
	local x, y, width, height = c.K.Within(first, p.win)
	local x2, y2, width2, height2 = c.K.Within(second, p.win)
	eq(x >= 606 + 10, true); eq(x + width <= 800 - 10, true); eq(width >= 174, true)
	eq(x2, x); eq(width2, width); eq(y2 - (y + height) >= 12, true); eq(y2 + height2 <= 400 - 8, true)
	for _, log in ipairs({ first, second }) do
		eq(log.wrap, true); eq(log.maxLines >= 3, true)
		log:SetText("Innkeeper Allison banks 1,050. Total: 1,050.")
		eq(log:GetStringHeight() <= log:GetHeight(), true, "a representative wrapped event fits its allocated slot")
	end
	NoErrors(w, c)
end)
test("Bones board layout: absent shared bar keeps a headerless safe footer without duplicating wooden table art", function()
	local w = FW.New(); local c = Seat(w)
	c.companion.own.Games.Bar = nil
	local p = Open(w, c)
	eq(p.win.bar, nil); eq(p.win:GetHeight(), 456); eq(p.win.actionBar:GetHeight(), 56)
	for _, region in ipairs(c.K.all) do
		if region.parent == p.win.actionBar then eq(region.tex == p.win.table[1].tex, false) end
	end
	w:As(c, function() c.K.UserClick(p.win.helpButton) end); eq(p.help:IsShown(), true)
	NoErrors(w, c)
end)
