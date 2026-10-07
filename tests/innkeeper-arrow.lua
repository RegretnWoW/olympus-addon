local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]innkeeper%-arrow%.lua$") or "./"

local function WithArrow(fn)
	local keys = { "UnitPosition", "IsInInstance", "UnitLevel", "UnitFactionGroup", "IsResting", "Minimap", "CreateFrame", "C_Texture", "C_Timer" }
	local saved = {}; for _, k in ipairs(keys) do saved[k] = _G[k] end
	local w = { wx = -9400, wy = 16.8, cont = 0, level = 60, faction = "Alliance", member = true, timers = {}, adds = {}, removes = 0, logs = {} }
	w.events = {}
	local c = setmetatable({ On = function(event, call) w.events[event] = call end, IsMember = function() return w.member end }, { __index = ns })
	c.Log = function(fmt, ...) w.logs[#w.logs + 1] = string.format(fmt, ...) end
	assert(loadfile(ROOT .. "Olympus/ArenaPlaces.lua"))("Olympus", c)
	for _, p in ipairs(c.Places.list) do if p.id == "inn_goldshire" then w.inn = p end end
	assert(w.inn)
	UnitPosition = function() return w.wx, w.wy, 0, w.cont end
	IsInInstance = function() return w.instance == true end
	UnitLevel = function() return w.level end
	UnitFactionGroup = function() return w.faction end
	IsResting = function() return w.resting == true end
	Minimap = { GetCenter = function() return 100, 100 end, GetFrameLevel = function() return 3 end }
	CreateFrame = function(_, _, parent)
		local f = { parent = parent, scripts = {}, cx = 130, cy = 100 }
		function f:SetSize(a, b) self.size = { a, b } end
		function f:EnableMouse(v) self.mouse = v end
		function f:SetFrameLevel(v) self.level = v end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		function f:SetScript(k, v) self.scripts[k] = v end
		function f:GetCenter() return self.cx, self.cy end
		function f:CreateTexture()
			local t = {}
			function t:SetAtlas(v) self.atlas = v end
			function t:SetTexture(v) self.texture = v end
			function t:SetAlpha(v) self.alpha = v end
			function t:SetRotation(v) self.rotation = v end
			function t:SetAllPoints() end
			function t:SetBlendMode() end
			return t
		end
		return f
	end
	C_Texture = { GetAtlasInfo = function() return {} end }
	C_Timer = { NewTicker = function() end }
	c.Every = function(seconds, _, call)
		local t = { seconds = seconds, call = call, Cancel = function(self) self.cancelled = true end }
		w.timers[#w.timers + 1] = t; return t
	end
	local pins = {}
	function pins:AddMinimapIconWorld(ref, f, cont, x, y, edge)
		w.adds[#w.adds + 1] = { ref = ref, frame = f, cont = cont, x = x, y = y, edge = edge }
		return not w.pinFailure
	end
	function pins:RemoveMinimapIcon(ref, f) w.removes = w.removes + 1; w.removedRef, w.removedFrame = ref, f end
	c.Pins = function() return pins end
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/InnkeeperArrow.lua"))("Olympus", c)
		fn(c.InnkeeperArrow, w, c)
	end)
	if c.InnkeeperArrow then c.InnkeeperArrow.Cancel("fixture") end
	for _, k in ipairs(keys) do _G[k] = saved[k] end
	if not ok then error(err, 0) end
end

test("Innkeeper arrow: native pin, actual registry target and explicit lifecycle", function()
	WithArrow(function(a, w)
		eq(#w.timers, 0, "no idle ticker on module load")
		local target = a.Target(); eq(target.id, w.inn.id, "nearest eligible keeper from actual registry")
		eq(a.Start(), true)
		local s = a.State(); eq(s.frame.parent, Minimap); eq(s.frame.mouse, false)
		eq(s.frame.icon.atlas, a.NATIVE_ATLAS); eq(s.frame.icon.alpha, 1)
		assert(math.abs(s.frame.icon.rotation + math.pi / 2) < 0.000001, "screen vector points east")
		local pin = w.adds[1]; eq(pin.cont, w.inn.cont); eq(pin.x, w.inn.wy); eq(pin.y, w.inn.wx); eq(pin.edge, true)
		eq(#w.timers, 1); a.Refresh(); eq(#w.adds, 1, "unchanged target does not rebuild pin")
		a.Cancel("user"); eq(s.ticker.cancelled, true); eq(s.frame.scripts.OnUpdate, nil); eq(s.frame.shown, false)
		eq(w.removedRef, pin.ref, "only this guidance's pin is removed")
		eq(a.Refresh(), false); eq(#w.adds, 1)
		a.Start(); local restarted = a.State().ticker
		w.events.LOGOUT(); eq(restarted.cancelled, true); eq(a.State().active, false)
	end)
end)

test("Innkeeper arrow: thrown places and frame reads cancel startup, ticker and direction with diagnostics", function()
	for _, source in ipairs({ "places", "center" }) do
		for _, stage in ipairs({ "start", "timer", "direction" }) do
			WithArrow(function(a, w, c)
				local timer
				if stage ~= "start" then assert(a.Start()); timer = a.State().ticker end
				local failure = "fixture " .. source .. " read failed"
				if source == "places" then
					c.Places.Fair = function() error(failure) end
				else
					Minimap.GetCenter = function() error(failure) end
				end
				local ok, why
				if stage == "start" then ok, why = a.Start()
				elseif stage == "timer" then ok, why = timer.call()
				elseif source == "center" then ok, why = a.UpdateDirection()
				else ok, why = a.Refresh() end
				eq(ok, false); eq(why, "error")
				local state = a.State()
				eq(state.active, false); eq(state.ticker, nil); eq(state.target, nil)
				if timer then eq(timer.cancelled, true) end
				if state.frame then
					eq(state.frame.shown, false); eq(state.frame.icon.alpha, 0); eq(state.frame.scripts.OnUpdate, nil)
				end
				eq(#w.logs, 1); assert(w.logs[1]:find(failure, 1, true), "actual API error is retained")
			end)
		end
	end
end)

test("Innkeeper arrow: arrival, instances and membership revoke guidance", function()
	WithArrow(function(a, w)
		a.Start(); local timer = a.State().ticker
		w.wx, w.wy = w.inn.wx, w.inn.wy
		a.Refresh(); eq(a.State().active, true, "coordinates alone do not assert arrival")
		w.resting = true; timer.call(); eq(a.State().reason, "arrived"); eq(timer.cancelled, true)
		w.resting = false; a.Start(); timer = a.State().ticker
		w.instance = true; timer.call(); eq(a.State().reason, "instance"); eq(timer.cancelled, true)
		w.instance = false; a.Start(); timer = a.State().ticker
		w.member = false; timer.call(); eq(a.State().reason, "membership"); eq(timer.cancelled, true)
	end)
end)

test("Innkeeper arrow: fails closed for unknown world, faction, level and pin API", function()
	WithArrow(function(a, w)
		w.cont = 999; local ok, why = a.Start(); eq(ok, false); eq(why, "no-inn"); eq(#w.timers, 0)
		w.cont = 0; w.faction = nil; ok, why = a.Start(); eq(ok, false); eq(why, "faction")
		w.faction = "Alliance"; w.wx = 0 / 0; ok, why = a.Start(); eq(ok, false); eq(why, "position")
		w.wx = -9400
		w.faction = "Alliance"; w.level = -1; ok, why = a.Start(); eq(ok, false); eq(why, "level")
		w.level = 60; w.pinFailure = true; ok, why = a.Start(); eq(ok, false); eq(why, "pin-api")
		eq(a.State().frame.shown, false); assert(w.removes > 0, "partial pin registration cleaned")
		w.pinFailure = false; C_Timer.NewTicker = nil; ok, why = a.Start(); eq(ok, false); eq(why, "timer-api")
		eq(a.State().active, false); eq(#w.timers, 0)
	end)
end)

test("Innkeeper arrow: faction, level, screen direction and native fallback", function()
	WithArrow(function(a, w, c)
		w.faction = "Horde"; w.level = 1
		local inn = a.Target(); assert(inn, "an eligible keeper exists")
		assert(inn.faction == "H" or inn.faction == "N"); assert(inn.minLevel <= w.level); eq(inn.cont, w.cont)
		C_Texture.GetAtlasInfo = function() return nil end
		eq(a.Start(), true); local f = a.State().frame; eq(f.icon.texture, a.NATIVE_TEXTURE)
		f.cx, f.cy = 100, 130; a.UpdateDirection(); eq(f.icon.rotation, 0)
		f.cx, f.cy = 100, 100; a.UpdateDirection(); eq(f.icon.alpha, 0, "zero screen vector hidden")
		f.cx = 70; a.UpdateDirection(); assert(math.abs(f.icon.rotation - math.pi / 2) < 0.000001)
		c.Pins = function() return nil end; a.Refresh(); eq(a.State().reason, "pin-api"); eq(a.State().active, false)
	end)
end)
