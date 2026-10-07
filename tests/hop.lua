-- Hop response clocks and cancellation, through the real paced communication queue.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]hop%.lua$")) or "./"

local function WithHop(fn)
	local names = { "GetTime", "GetChannelName", "GetGuildInfo", "IsInGroup", "IsInRaid", "UnitFullName", "UnitName",
		"GetNumGroupMembers", "GetServerTime", "C_ChatInfo", "AcceptGroup", "StaticPopup_Hide", "StaticPopup_FindVisible" }
	local saved, dialogs = {}, {}
	for _, key in ipairs(names) do saved[key] = _G[key] end
	for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local w = { clock = 1800000000, mono = 1000, guild = "Olympus II", map = 1453, group = 0,
		party = {}, sent = {}, errors = {}, accepted = 0, id = 0 }
	local ok, err = pcall(function()
		GetTime = function() return w.mono end
		GetServerTime = function() return w.clock end
		GetChannelName = function() return 5, "OlympusNet" end
		GetGuildInfo = function() return w.guild, "Member", 3 end
		IsInGroup = function() return w.group > 0 end
		IsInRaid = function() return false end
		GetNumGroupMembers = function() return w.group end
		UnitFullName = function(unit) if unit == "player" then return "Tester", "Realm" end return w.party[unit] end
		UnitName = function(unit) return w.party[unit] end
		AcceptGroup = function() w.accepted = w.accepted + 1 end
		StaticPopup_Hide, StaticPopup_FindVisible = function() end, function() end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(_, msg, dist, target)
			w.sent[#w.sent + 1] = { msg = msg, dist = dist, target = target, at = w.clock }
			return not w.fail
		end }
		local c = setmetatable({ me = "Tester-Realm", realm = "Realm", db = { layerHelp = false }, rdb = { guilds = {} } }, { __index = ns })
		c.Now = function() return w.clock end
		c.On, c.RegisterEvent, c.After, c.Every, c.Fire, c.Print, c.Log = function() end, function() end, function() end,
			function() end, function() end, function() end, function() end
		c.SafeCall = function(label, f, ...)
			local called, why = pcall(f, ...)
			if not called then w.errors[#w.errors + 1] = label .. ": " .. tostring(why) end
		end
		c.Data = {} -- this scene does not share or mutate the outer harness census
		c.GamepadUI = function() return w.manual end
		c.PlayAlert = function() end
		c.Moderation = { Blocks = function() return false end, Hides = function() return false end, SelfOff = function() return w.off end }
		c.Layers = { CurrentMap = function() return w.map end, Sharing = function() return true end,
			Mine = function() return { mapID = w.map, zoneUID = 7, t = w.clock } end }
		assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/Hop.lua"))("Olympus", c)
		c.Comm.JoinChannel()
		c.Hop.random = function(a) if a then w.id = w.id + 1; return w.id end return 0 end
		c.Hop.Trusted = function() return true end
		function w.advance(seconds)
			w.clock, w.mono = w.clock + seconds, w.mono + seconds
			c.Hop.Tick()
		end
		function w.step(n)
			for _ = 1, n or 1 do
				w.clock, w.mono = w.clock + 1.2, w.mono + 1.2
				c.Comm.Pump()
				c.Hop.Tick()
			end
		end
		function w.busy(n)
			for i = 1, n do assert(c.Comm.Whisper("Busy-Realm", "Q1~" .. i, nil, true)) end
		end
		function w.count(prefix, target)
			local count = 0
			for _, entry in ipairs(w.sent) do
				if entry.msg:sub(1, #prefix) == prefix and (not target or target == entry.target) then count = count + 1 end
			end
			return count
		end
		function w.offer(name)
			c.Hop.HandleOffer("WHISPER", name .. "-Realm", "LO~" .. c.Hop.State().id .. "~0~0")
		end
		fn(w, c.Hop, c.Comm)
		eq(#w.errors, 0, table.concat(w.errors, "\n"))
		c.Hop.Reset()
	end)
	for _, key in ipairs(names) do _G[key] = saved[key] end
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = dialogs[key] end
	if not ok then error(err, 0) end
end

test("hop: twenty urgent messages cannot consume the ask's fifteen-second response window", function()
	WithHop(function(w, H)
		w.busy(20)
		H.Ask(1453, 8, "target")
		local request = H.State()
		eq(request.phase, "sending"); eq(request.t, nil)
		w.offer("Tooearly")
		eq(request.count, 0, "no offer before the ask left")
		w.step(20)
		eq(w.count("LQ~"), 0); eq(request.phase, "sending", "24 seconds queued")
		w.step()
		eq(w.count("LQ~"), 1); eq(request.phase, "asking"); eq(request.t, w.clock)
		w.advance(H.NOBODY - 0.01)
		eq(request.phase, "asking")
		w.advance(0.02)
		eq(request.phase, "done", "the whole response window follows transmission")
	end)
end)

test("hop: a helper's thirty-second response window starts after LR transmission", function()
	WithHop(function(w, H)
		H.Ask(1453, 8, "target"); w.step()
		w.offer("Aaa")
		w.busy(30)
		w.advance(H.WINDOW)
		local request = H.State()
		eq(request.phase, "requesting"); eq(request.asked, nil)
		eq(request.tried["Aaa-Realm"], nil, "queued is not sent")
		w.step(30)
		eq(w.count("LR~"), 0); eq(request.phase, "requesting", "36 seconds queued")
		w.step()
		eq(w.count("LR~"), 1); eq(request.phase, "requested"); eq(request.asked, w.clock)
		eq(request.tried["Aaa-Realm"], true)
		w.advance(H.WAIT - 0.01)
		eq(request.phase, "requested")
		w.advance(0.02)
		eq(request.phase, "done")
	end)
end)

test("hop: changed zone, guild, group or moderation cancels an unsent ask", function()
	for _, change in ipairs({ "map", "guild", "group", "off" }) do
		WithHop(function(w, H, C)
			H.Ask(1453, 8, "target")
			if change == "map" then w.map = 1429
			elseif change == "guild" then w.guild = "Olympus New"
			elseif change == "group" then w.group, w.party.party1 = 2, "Friend"
			else w.off = true end
			-- No Hop tick/event first: the final transport guard observes the changed context.
			C.Pump()
			eq(w.count("LQ~"), 0, change); eq(H.State().phase, "done", change)
			eq(C.QueueSize(), 0)
		end)
	end
end)

test("hop: joining a friend's group cancels a queued helper request", function()
	WithHop(function(w, H, C)
		H.Ask(1453, 8, "target"); w.step(); w.offer("Aaa"); w.advance(H.WINDOW)
		eq(H.State().phase, "requesting")
		w.group, w.party.party1 = 2, "Friend"
		H.OnRoster()
		eq(H.State().phase, "done"); eq(C.QueueSize(), 0)
		w.step(); eq(w.count("LR~"), 0)
	end)
end)

test("hop: a late invite from a sent helper cancels the next queued LR, with automatic or manual acceptance", function()
	for _, manual in ipairs({ false, true }) do
		WithHop(function(w, H, C)
			w.manual = manual
			H.Ask(1453, 8, "target"); w.step()
			w.offer("Aaa"); w.offer("Bbb"); w.advance(H.WINDOW); w.step()
			eq(w.count("LR~", "Aaa"), 1)
			w.advance(H.WAIT)
			eq(H.State().phase, "requesting"); eq(H.State().helper, "Bbb-Realm")
			H.OnInvite("Bbb")
			eq(w.accepted, 0, "an unsent request authorizes no automatic invite acceptance")
			eq(H.State().phase, "requesting")
			H.OnInvite("Aaa")
			eq(H.State().phase, manual and "requested" or "accepted")
			eq(w.accepted, manual and 0 or 1); eq(C.QueueSize(), 0)
			w.group, w.party.party1 = 2, "Aaa"
			H.OnRoster(); eq(H.State().phase, "joined")
			w.step(); eq(w.count("LR~", "Bbb"), 0)
		end)
	end
end)

test("hop: reset cancels only the old ask and an obsolete completion cannot advance the next ask", function()
	WithHop(function(w, H, C)
		local send, obsolete = C.Send
		C.Send = function(dist, msg, key, urgent, logged, done, options)
			obsolete = obsolete or done
			return send(dist, msg, key, urgent, logged, done, options)
		end
		H.Ask(1453, 8, "old")
		local old = H.State()
		H.Reset()
		eq(C.QueueSize(), 0)
		H.Ask(1453, 9, "new")
		local current = H.State()
		assert(current ~= old)
		obsolete(true)
		eq(current.phase, "sending"); eq(current.t, nil)
		w.step()
		eq(w.count("LQ~"), 1); eq(current.phase, "asking")
		assert(w.sent[1].msg:match("~1453~9$"), "only the current target left")
	end)
end)

test("hop: immediate queue rejection and failed transmission end without a response timeout", function()
	WithHop(function(w, H)
		w.busy(60)
		H.Ask(1453, 8, "full")
		eq(H.State().phase, "done"); eq(H.State().t, nil); eq(w.count("LQ~"), 0)
	end)
	WithHop(function(w, H)
		w.fail = true
		H.Ask(1453, 8, "failed"); w.step()
		eq(H.State().phase, "done"); eq(H.State().t, nil)
	end)
end)
