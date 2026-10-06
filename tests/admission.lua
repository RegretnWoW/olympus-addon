-- Token-bucket admission under a full sender table: observable limits and registry work.
local ns, test, eq = ...
local C = ns.Comm
local function WithAdmission(capacity, fn)
	local saved = C.ADMIT_SENDERS
	C.ResetAdmission()
	C.ADMIT_SENDERS = capacity
	local ok, err = pcall(fn)
	C.ADMIT_SENDERS = saved
	C.ResetAdmission()
	if not ok then error(err, 0) end
end

-- Count actual registry traversal steps, not elapsed CPU time. This catches the original
-- pairs(admit) scan on every unknown sender while leaving the admission function unchanged.
local function Visits(fn)
	local saved, visits = pairs, 0
	pairs = function(t)
		local iter, state, key = saved(t)
		return function(s, k)
			local nextKey, value = iter(s, k)
			if nextKey ~= nil then visits = visits + 1 end
			return nextKey, value
		end, state, key
	end
	local ok, err = pcall(fn)
	pairs = saved
	if not ok then error(err, 0) end
	return visits
end

test("admission: burst 60 and refill 2 per second survive activity touches", function()
	WithAdmission(3, function()
		for _ = 1, 60 do assert(C.Admit("A", 0)) end
		eq(C.Admit("A", 0), false)
		eq(C.Admit("A", 0.25), false)
		eq(C.Admit("A", 0.5), true)
		eq(C.Admit("A", 0.5), false)
		for _ = 1, 60 do assert(C.Admit("A", 60)) end
		eq(C.Admit("A", 60), false, "refill remains capped at the burst")
	end)
end)

test("admission: only senders idle strictly longer than 60 seconds yield their slots", function()
	WithAdmission(3, function()
		assert(C.Admit("A", 0)); assert(C.Admit("B", 0)); assert(C.Admit("C", 0))
		assert(C.Admit("A", 59), "touch the oldest sender")
		eq(C.Admit("D", 60), false, "exactly 60 seconds is still active")
		assert(C.Admit("D", 61)); assert(C.Admit("E", 62))
		eq(C.Admit("F", 62), false, "three recent senders fill the capacity")
		eq(C.Admit("B", 62), false, "the recycled slot no longer resolves the old sender")
		assert(C.Admit("A", 63))
		assert(C.Admit("G", 122), "D is now idle")
		eq(C.Admit("H", 122), false, "E has exactly 60 seconds of quiet")
		assert(C.Admit("H", 123))
	end)
end)

test("admission: throttled messages also update the last-activity order", function()
	WithAdmission(2, function()
		for _ = 1, 60 do assert(C.Admit("A", 0)) end
		assert(C.Admit("B", 0))
		eq(C.Admit("A", 0.25), false, "still active even when its bucket is empty")
		assert(C.Admit("C", 60.125), "B is idle, but A is not")
		eq(C.Admit("D", 60.125), false, "A's rejected message kept its slot active")
	end)
end)

test("admission: a saturated table rejects unknown senders without registry traversal", function()
	WithAdmission(3000, function()
		for i = 1, 3000 do assert(C.Admit("Member" .. i, 0)) end
		local visits = Visits(function()
			for i = 1, 200 do eq(C.Admit("Unknown" .. i, 1), false) end
		end)
		eq(visits, 0, "200 rejected senders must not scan 3000 live entries each")
		assert(C.Admit("Member1500", 1), "known senders retain their budget")
	end)
end)

test("admission: idle slots are reused one at a time without sweeping or growing the table", function()
	WithAdmission(3000, function()
		for i = 1, 3000 do assert(C.Admit("Old" .. i, 0)) end
		local visits = Visits(function()
			for i = 1, 3000 do assert(C.Admit("New" .. i, 61)) end
		end)
		eq(visits, 0, "recycling touches one expired slot per admission")
		eq(C.Admit("Extra", 61), false, "the capacity has not grown")
		eq(C.Admit("Old1500", 61), false, "expired identities were removed")
		C.ResetAdmission()
		for i = 1, 3000 do assert(C.Admit("Reset" .. i, 61)) end
		eq(C.Admit("Extra", 61), false, "reset clears the list as well as the lookup")
	end)
end)

test("admission: receive budgets follow elapsed time across wall-clock jumps", function()
	local saved = GetTime
	local wall, mono, read = 100000, 10, 0
	local cns = setmetatable({ db = { blocked = {} }, Now = function() return wall end,
		On = function() end, After = function() end, Every = function() end,
		RegisterEvent = function() end, Fire = function() end }, { __index = ns })
	cns.Codec = setmetatable({ Feed = function(...)
		read = read + 1
		return ns.Codec.Feed(...)
	end }, { __index = ns.Codec })
	local ok, err = pcall(function()
		GetTime = function() return mono end
		local root = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"
		assert(loadfile(root .. "Olympus/Comm.lua"))("Olympus", cns)
		for _ = 1, 60 do cns.Comm.Outsider("Member-Realm", "Cadmit:1:2:x") end
		eq(read, 60)
		wall = wall + 86400
		cns.Comm.Outsider("Member-Realm", "Cadmit:1:2:x")
		eq(read, 60, "a forward clock jump grants no extra messages")
		mono = mono + 0.5
		cns.Comm.Outsider("Member-Realm", "Cadmit:1:2:x")
		eq(read, 61, "half a second refills one token")
		wall, mono = wall - 172800, mono + 0.5
		cns.Comm.Outsider("Member-Realm", "Cadmit:1:2:x")
		eq(read, 62, "a backward clock jump cannot freeze the sender's budget")
	end)
	GetTime = saved
	if not ok then error(err, 0) end
end)
