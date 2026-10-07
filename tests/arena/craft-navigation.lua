-- The directory belongs to the public board; personal tabs show their own records.
local H = ...
local test, eq = H.test, H.eq
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)

local function Find(lines, text)
	for _, line in ipairs(lines) do
		if type(line.text) == "string" and line.text:find(text, 1, true) then return line end
	end
end

local function Select(client, label)
	local lines = client.Crafters.Lines()
	for _, line in ipairs(lines) do
		if line.id == "craft-navigation" then
			for _, item in ipairs(line.nav) do if item.text == label then item.onClick(); return end end
		end
	end
	error("missing crafting destination: " .. label)
end

test("Crafting destinations: empty personal pages identify their mode and omit the public directory", function()
	local w = H.World.New()
	local c = K.Client(w, "Sage Owl")
	local L = c.ns.L
	for _, label in ipairs({ L.CRAFT_BOARD_MINE, L.CRAFT_BOARD_ACCEPTED, L.CRAFT_BOARD_HISTORY }) do
		Select(c, label)
		local lines = c.Crafters.Lines()
		eq(Find(lines, L.CRAFTER_TITLE), nil, "personal view does not repeat the public directory")
		eq(lines[1].right, label, "empty page identifies the selected destination")
		assert(Find(lines, L.CRAFT_BOARD_EMPTY), "the request view explains its empty result")
	end
	Select(c, L.CRAFT_BOARD_OPEN)
	assert(Find(c.Crafters.Lines(), L.CRAFTER_TITLE), "Board still includes the directory")
	K.NoErrors(w)
end)

test("Crafting destinations: actual tab callbacks filter saved open, owned, accepted and completed requests", function()
	local w = H.World.New()
	local c = K.Client(w, "Sage Owl")
	local L, me, now = c.ns.L, c.name, w.clock
	-- Saved records in the four supported states, with invented identities.
	local records = {}
	local function Record(id, name, requester, crafter, state)
		records[id] = { id = id, itemID = 14342, itemName = name, quantity = 1,
			requester = requester, crafter = crafter, guild = H.World.GUILD,
			state = state, created = now, updated = now, expires = now + 3600 }
	end
	Record("public", "Public cloth", "Wren Thistle-Emberfall", nil, "open")
	Record("own", "Owned cloth", me, nil, "open")
	Record("accepted", "Accepted cloth", "Wren Thistle-Emberfall", me, "accepted")
	Record("history", "Completed cloth", me, "Wren Thistle-Emberfall", "completed")
	c.ns.rdb.craftRequests = { records = records, invites = {} }
	local cases = {
		{ L.CRAFT_BOARD_OPEN, { "Public cloth", "Owned cloth" } },
		{ L.CRAFT_BOARD_MINE, { "Owned cloth" } },
		{ L.CRAFT_BOARD_ACCEPTED, { "Accepted cloth" } },
		{ L.CRAFT_BOARD_HISTORY, { "Completed cloth" } },
	}
	for _, case in ipairs(cases) do
		Select(c, case[1])
		local lines, expected = c.Crafters.Lines(), {}
		for _, name in ipairs(case[2]) do expected[name] = true end
		for _, name in ipairs({ "Public cloth", "Owned cloth", "Accepted cloth", "Completed cloth" }) do
			eq(Find(lines, name) ~= nil, expected[name] == true, "selected view's actual request rows")
		end
		eq(lines[1].right, case[1])
	end
	Select(c, L.CRAFT_BOARD_MINE)
	assert(Find(c.Crafters.Lines("owned"), "Owned cloth"), "selected view retains matching search results")
	eq(Find(c.Crafters.Lines("public"), "Public cloth"), nil, "search cannot leak another view's records")
	K.NoErrors(w)
end)
