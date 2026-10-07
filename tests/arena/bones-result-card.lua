local H = ...
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

H.test("Bones result card: larger framed parchment, actual keeper and quiet victory words", function()
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local c = w:Player(H.World.NAMES.fighterA, { companion = {} })
	w:Stand(c.name, FW.INN, true)
	c.K = BoardUI.New(function() return w.clock end, { screen = { 1920, 1080 } })
	c.K.Install(c.globals)
	w:As(c, function()
		assert(c.ns.FarkleTable.ShowUI("practice"))
		local board = c.ns.Arena.ui.FarkleBoard
		local original = c.ns.FarkleTable.View
		c.ns.FarkleTable.View = function()
			return { over = true, winner = 1, seat = 1, role = "practice", practice = true,
				players = { c.name, "Localized Keeper" }, scores = { 5000, 1200 }, stake = 0, lines = {} }
		end
		local ok, err = pcall(function()
			local card = board.ShowCard("Presult")
			H.eq(type(card), "table")
			H.eq(card:GetWidth(), 500); H.eq(card:GetHeight(), 310)
			assert(card.NineSlice, "real Olympus window border")
			H.eq(card.TitleText:GetText(), c.ns.L.FARKLE_NAME)
			assert(card.line:GetText():find("Localized Keeper", 1, true), "the actual opponent, not The House")
			H.eq(card.tagline:GetText(), c.ns.L.FARKLE_B_CARD_VICTORY_LINE)
			assert(card.bg.tex or card.bg.texture, "existing parchment artwork")
			H.eq(card.rows[1].r:GetText(), "5,000")
			H.eq(card.buttons[1]:GetText(), c.ns.L.FARKLE_B_OK)
			local before = #w.sent
			c.K.UserClick(card.buttons[1]); H.eq(card:IsShown(), false); H.eq(#w.sent, before)
		end)
		c.ns.FarkleTable.View = original
		if not ok then error(err, 0) end
	end)
	for _, err in ipairs(c.errors) do error(err, 0) end
	for _, err in ipairs(c.K.errors) do error(err, 0) end
end)
