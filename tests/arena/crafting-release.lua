local H = ...
local test, eq, World = H.test, H.eq, H.World
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)

local function Nav(lines)
	for _, line in ipairs(lines) do if line.nav then return line.nav end end
	return {}
end
local function HasLabel(lines, label)
	for _, line in ipairs(lines) do
		if tostring(line.text or ""):find(label, 1, true) then return true end
		for _, choice in ipairs(line.nav or {}) do if choice.text == label then return true end end
	end
	return false
end

test("1.1.6 crafting visibility: the common switch hides fees and stale navigation and keeps requests before history", function()
	local w = World.New({ compliance = "shipped" })
	local a = K.Client(w, World.NAMES.king)
	local R, L = a.Craft, a.ns.L
	local labels = {}
	for _, choice in ipairs(Nav(R.BoardLines())) do labels[#labels + 1] = choice.text end
	eq(table.concat(labels, "|"), table.concat({ L.CRAFT_BOARD_OPEN, L.CRAFT_BOARD_MINE, L.CRAFT_BOARD_ACCEPTED, L.CRAFT_BOARD_HISTORY }, "|"))
	R.SetPage("fees")
	local lines = R.BoardLines()
	eq(Nav(lines)[1].selected, true, "a remembered fee page falls back to requests")
	eq(HasLabel(lines, L.CRAFT_BOARD_FEES), false)
	local buyer = K.Client(w, "Lark Stone")
	local request = K.Request(w, buyer, 14342, "Mooncloth", 1)
	local held = assert(K.Rec(w, a, request.id))
	-- A received custody record keeps its live desk ahead of finished work.
	held.settlement = { rail = "guild", custodian = a.name, state = "awaiting_funds" }
	labels = {}
	for _, choice in ipairs(Nav(R.BoardLines())) do labels[#labels + 1] = choice.text end
	eq(table.concat(labels, "|"), table.concat({ L.CRAFT_BOARD_OPEN, L.CRAFT_BOARD_MINE, L.CRAFT_BOARD_ACCEPTED, L.CRAFT_BOARD_DUTY, L.CRAFT_BOARD_HISTORY }, "|"))
	a.ns.Compliance.WALLET_ENABLED = true
	eq(HasLabel(R.BoardLines(), L.CRAFT_BOARD_FEES), true, "the same switch restores the fee desk for its reader")
end)

test("Page header: crafting marks only its destination strip as fixed window navigation", function()
	local w = World.New({ compliance = "shipped" })
	local a = K.Client(w, "Lark Stone")
	local lines, count = a.Craft.BoardLines(), 0
	for _, line in ipairs(lines) do
		if line.pageNav then
			count = count + 1
			eq(line.id, "craft-navigation"); assert(#line.nav >= 4)
		end
	end
	eq(count, 1)
	a.Craft.OpenComposer()
	for _, line in ipairs(a.Craft.ComposerLines()) do eq(line.pageNav, nil, "item filters are not page tabs") end
end)

test("1.1.6 crafting visibility: an accepted request offers trade and mail without the hidden payment rail", function()
	local w = World.New({ compliance = "shipped" })
	local a, b = K.Client(w, "Lark Stone"), K.Client(w, "Fern Reed")
	K.Recipes(w, b, { [14342] = "Mooncloth" })
	local r = K.Request(w, a, 14342, "Mooncloth", 2)
	assert(b.Craft.Accept(r.id))
	w:Run(0)
	b.Craft.SetPage("accepted")
	b.Craft.Open(r.id)
	local lines = b.Craft.BoardLines()
	eq(HasLabel(lines, b.ns.L.CRAFT_RAIL_WALLET), false)
	eq(HasLabel(lines, b.ns.L.CRAFT_RAIL_DIRECT_TRADE), true)
	eq(HasLabel(lines, b.ns.L.CRAFT_RAIL_DIRECT_MAIL), true)
	b.ns.Compliance.WALLET_ENABLED = true
	eq(HasLabel(b.Craft.BoardLines(), b.ns.L.CRAFT_RAIL_WALLET), true, "the kept payment option returns with its switch")
end)
