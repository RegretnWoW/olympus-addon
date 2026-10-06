local H = ...
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
H.test("Lottery selection: original card typography, icon tint and contained quest border", function()
	local w = H.World.New({ compliance = "shipped" })
	local c = w:Client(H.World.NAMES.fighterA)
	c.K = BoardUI.New(function() return w.clock end, { screen = { 1280, 960 } }); c.K.Install(c.globals)
	c.db.arenaRules = { yes = true }
	local own = w:As(c, function() return H.LoadCompanion(c.ns) end)
	local UI = own.ArenaUI
	local f = w:As(c, UI.LotteryPracticeWindow, true)
	H.eq(#f.cards, 25)
	for i, card in ipairs(f.cards) do
		H.eq(card:GetWidth(), 150); H.eq(card:GetHeight(), 94)
		H.eq(card.art:GetWidth(), 60); H.eq(card.art.coords[1], 0.07)
		H.eq(card.iconFrame.vertex[1], 0.86, "original gold icon frame")
		H.eq(card.num.size, 15); H.eq(card.num.font, c.globals.STANDARD_TEXT_FONT)
		H.eq(card.num.textColor[1], 0.46)
		H.eq(card.name.size, 15); H.eq(card.name.font, "Fonts\\MORPHEUS.TTF")
		local endings = c.ns.Lottery.Dezenas(i)
		H.eq(card.dz[1]:GetText(), endings[1] .. " " .. endings[2])
		H.eq(card.dz[2]:GetText(), endings[3] .. " " .. endings[4])
		H.eq(card.dz[1].size, 14)
	end
	w:As(c, function() assert(c.K.UserClick(f.cards[25])) end)
	local mark = f.cards[25].mark
	H.eq(#mark.parts, 8)
	for _, part in ipairs(mark.parts) do
		assert(part.points[1].x + part:GetWidth() <= 150, "quest border must remain inside 150px card")
		assert(-part.points[1].y + part:GetHeight() <= 94, "quest border must remain inside 94px card")
	end
	H.eq(f.cards[25].mark:IsShown(), true)
	w:As(c, function() assert(c.K.UserClick(f.cards[1])) end)
	H.eq(mark:IsShown(), false); H.eq(f.cards[1].mark:IsShown(), true)
	H.eq(#c.errors, 0); H.eq(#c.K.errors, 0)
end)
