local H = ...
local test, eq = H.test, H.eq

print("Comm.lua: guarded queue cancellation")

-- Comm.lua itself, with its real bounded queue and Pump.  The fake game records only calls
-- that reached SendAddonMessage, so these tests exercise the gap between enqueue and send.
local function RealComm(fn)
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = H.ns })
	cns.RegisterEvent = function(event, f) events[event] = events[event] or {}; table.insert(events[event], f) end
	cns.On = function(name, f) if name == "LOGIN" then login[#login + 1] = f end end
	cns.After, cns.Every, cns.Log = function() end, function() end, function() end
	cns.clock = 100000
	cns.Now = function() return cns.clock end
	local results, sent = {}, {}
	local saved = { C_ChatInfo = C_ChatInfo, IsInGuild = IsInGuild, GetGuildInfo = GetGuildInfo }
	local function Send(prefix, msg, dist, target)
		local r = table.remove(results, 1) or 0
		sent[#sent + 1] = { prefix = prefix, msg = msg, dist = dist, target = target, result = r }
		return r
	end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send }
	IsInGuild = function() return true end
	GetGuildInfo = function() return "Olympus II" end
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		for _, f in ipairs(login) do f() end
		fn(cns.Comm, cns, results, sent)
	end)
	C_ChatInfo, IsInGuild, GetGuildInfo = saved.C_ChatInfo, saved.IsInGuild, saved.GetGuildInfo
	if not ok then error(err, 0) end
end

test("1.2: a queued guarded whisper rechecks permission immediately before the real send", function()
	RealComm(function(C, cns, results, sent)
		local owner, lease = {}, { allowed = true, recipient = "Old-Realm" }
		local checked, done = {}, {}
		local guard = {
			owner = owner,
			key = "direct",
			permit = function(gotOwner, key, dist, target, msg)
				checked[#checked + 1] = { owner = gotOwner, key = key, dist = dist, target = target, msg = msg }
				if not lease.allowed then return false, "revoked" end
				if target ~= lease.recipient then return false, "recipient-changed" end
				return true
			end,
		}
		C.Send("GUILD", "ZZ~ahead")
		C.Whisper("Old-Realm", "ZZ~private", nil, nil, nil, function(ok, why)
			done[#done + 1] = tostring(ok) .. ":" .. tostring(why)
		end, guard)
		eq(C.QueueSize(), 2); eq(#checked, 0, "enqueue does not stand in for the send-time check")
		C.Pump()
		eq(#sent, 1); eq(sent[1].msg, "ZZ~ahead"); eq(#checked, 0, "still waiting")
		lease.allowed = false
		C.Pump()
		eq(#sent, 1, "revocation before its turn prevents the game API call")
		eq(table.concat(done, ","), "false:revoked")
		eq(#checked, 1); eq(checked[1].owner, owner); eq(checked[1].key, "direct")
		eq(checked[1].dist, "WHISPER"); eq(checked[1].target, "Old-Realm"); eq(checked[1].msg, "ZZ~private")
		eq(C.QueueSize(), 0)

		-- A changed destination fails the same last-moment check; a game failure after a permitted
		-- check still preserves its numeric result for ArenaNet's retry policy.
		lease.allowed, lease.recipient = true, "New-Realm"
		C.Whisper("Old-Realm", "ZZ~stale", nil, nil, nil, function(ok, why)
			done[#done + 1] = tostring(ok) .. ":" .. tostring(why)
		end, guard)
		C.Pump()
		eq(#sent, 1); eq(done[2], "false:recipient-changed")
		lease.recipient = "Old-Realm"
		results[1] = 8
		C.Whisper("Old-Realm", "ZZ~retry", nil, nil, nil, function(ok, why)
			done[#done + 1] = tostring(ok) .. ":" .. tostring(why)
		end, guard)
		C.Pump()
		eq(sent[#sent].msg, "ZZ~retry"); eq(done[3], "false:8")
	end)
end)

test("1.2: guarded queue identities cancel only their bounded owner/key set and notify each sender", function()
	RealComm(function(C, cns, results, sent)
		local owner, other = {}, {}
		local done = {}
		local function D(tag)
			return function(ok, why) done[#done + 1] = tag .. ":" .. tostring(ok) .. ":" .. tostring(why) end
		end
		local function G(who, key)
			return { owner = who, key = key, permit = function() return true end }
		end
		C.Send("GUILD", "ZZ~one", nil, nil, nil, D("one"), G(owner, "report"))
		C.Whisper("A-Realm", "ZZ~two", nil, nil, nil, D("two"), G(owner, "report"))
		C.Send("GUILD", "ZZ~three", nil, nil, nil, D("three"), G(owner, "other"))
		C.Send("GUILD", "ZZ~four", nil, nil, nil, D("four"), G(other, "report"))
		eq(C.CancelQueued(owner, "report", "revoked"), 2)
		eq(table.concat(done, ","), "one:false:revoked,two:false:revoked")
		eq(C.QueueSize(), 2); eq(C.CancelQueued(owner, "missing", "revoked"), 0)
		C.Pump(); C.Pump()
		eq(#sent, 2); eq(sent[1].msg, "ZZ~three"); eq(sent[2].msg, "ZZ~four")
		eq(done[3], "three:true:nil"); eq(done[4], "four:true:nil")

		-- A malformed guard fails closed before enqueueing, instead of silently becoming unguarded.
		C.Send("GUILD", "ZZ~bad", nil, nil, nil, D("bad"), { owner = owner, key = "bad" })
		eq(done[5], "bad:false:guard"); eq(C.QueueSize(), 0); eq(#sent, 2)
	end)
end)

test("1.2: keyed replacement replaces its guard too, and a failing permit is fail-closed", function()
	RealComm(function(C, cns, results, sent)
		local oldOwner, newOwner, done = {}, {}, {}
		local function D(tag)
			return function(ok, why) done[#done + 1] = tag .. ":" .. tostring(ok) .. ":" .. tostring(why) end
		end
		C.Send("GUILD", "ZZ~old", "same", nil, nil, D("old"), {
			owner = oldOwner, key = "old", permit = function() return true end,
		})
		C.Send("GUILD", "ZZ~new", "same", nil, nil, D("new"), {
			owner = newOwner, key = "new", permit = function() return false, "recipient-changed" end,
		})
		eq(C.QueueSize(), 1); eq(C.CancelQueued(oldOwner, "old", "wrong"), 0, "the old identity was replaced")
		C.Pump()
		eq(#sent, 0); eq(table.concat(done, ","), "new:false:recipient-changed")

		C.Send("GUILD", "ZZ~error", nil, nil, nil, D("error"), {
			owner = newOwner, key = "error", permit = function() error("permit broke") end,
		})
		C.Pump()
		eq(#sent, 0, "a permit error never opens the guard")
		eq(done[2], "error:false:guard-error")
	end)
end)

test("1.2: chunked sends retain the current capability guard for every fragment", function()
	RealComm(function(C, cns, results, sent)
		local owner, allowed, done = {}, true, {}
		local guard = {
			owner = owner,
			key = "chunked",
			permit = function(gotOwner, key)
				eq(gotOwner, owner); eq(key, "chunked")
				return allowed, "revoked"
			end,
		}
		C.SendChunked("ZZ~" .. ("x"):rep(500), nil, "GUILD", function(ok, why)
			done[#done + 1] = tostring(ok) .. ":" .. tostring(why)
		end, guard)
		C.Pump()
		eq(#sent, 1, "the first fragment leaves while authorized")
		allowed = false
		C.Pump()
		eq(#sent, 1, "revocation stops the remaining fragments")
		eq(table.concat(done, ","), "false:revoked")
		eq(C.QueueSize(), 0)
	end)
end)
