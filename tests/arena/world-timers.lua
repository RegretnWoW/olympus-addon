local H = ...
local test, eq, World = H.test, H.eq, H.World

test("Timer world: long one-shot chains retire storage without skipping callbacks or same-time order", function()
	local w = World.New()
	local c = w:Client("Lark Fenn")
	local n, peak, order = 0, 0, {}
	w:As(c, function()
		local function Tick()
			n = n + 1
			peak = math.max(peak, #w.timers)
			if n < 2048 then C_Timer.After(0.001, Tick)
			else
				C_Timer.After(0.001, function() order[#order + 1] = "first" end)
				C_Timer.After(0.001, function() order[#order + 1] = "second" end)
			end
		end
		C_Timer.After(0.001, Tick)
		local cancelled = C_Timer.NewTimer(1, function() error("cancelled timer fired") end)
		cancelled:Cancel()
	end)
	w:Run(3)
	eq(n, 2048)
	eq(table.concat(order, ","), "first,second")
	assert(peak < 512, "retired timers grew with the chain: " .. peak)
	for _, err in ipairs(c.errors) do error(err) end
end)

test("Timer world: cleanup preserves offline timers and rejects an obsolete session", function()
	local w = World.New()
	local c = w:Client("Lark Fenn")
	local called = 0
	w:As(c, function() C_Timer.After(1, function() called = called + 1 end) end)
	c.online = false
	w:Run(2)
	eq(called, 0)
	c.online = true
	w:Run(0)
	eq(called, 1, "offline timer survives until its client returns")
	w:As(c, function() C_Timer.After(1, function() called = called + 1 end) end)
	c.session = c.session + 1
	w:Run(2)
	eq(called, 1, "the old session's timer never fires")
end)
