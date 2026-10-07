-- Logical Chat destinations: explicit topic choices, scoped transports, and revocable audiences.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-rooms%.lua$")) or "./"

local function WithRooms(fn)
	local globals = { "GetTime", "GetGuildInfo", "UnitClass", "UnitRace", "C_ChatInfo", "C_CreatureInfo", "LOCALIZED_CLASS_NAMES_MALE" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local w = { mono = 1000, epoch = 1800000000, guild = "Olympus II", channel = "OlympusNet",
		jobs = {}, events = {}, nativeEvents = {}, nativeSent = {}, listeners = {}, asked = {}, cancelled = 0, logged = true, attempts = 0,
		council = {}, stewards = {}, departments = {}, king = "The King-Realm" }
	local ok, err = pcall(function()
		GetTime = function() return w.mono end
		GetGuildInfo = function() return w.guild end
		UnitClass = function() return "Warrior", "WARRIOR" end
		UnitRace = function() return "Human", "Human", 1 end
		C_ChatInfo = { SendAddonMessageLogged = function() end, InChatMessagingLockdown = function() return false end }
		-- Verified native API/event in fixtures/forever-api.lua:605,669,690; no addon-message echo.
		C_ChatInfo.SendChatMessage = function(text, lane) w.nativeSent[#w.nativeSent + 1] = { text, lane } end
		C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE = nil, nil

		local c = setmetatable({ db = { chatRooms = true, addonChat = true }, rdb = { council = { names = {} } },
			me = "Member-Realm", realm = "Realm", faction = "Alliance" }, { __index = ns })
		c.Now = function() return w.epoch end
		c.FullName = function(name)
			if type(name) ~= "string" then return "" end
			return name:find("-", 1, true) and name or (name .. "-Realm")
		end
		c.ShortName = function(name) return tostring(name or ""):match("^([^%-]+)") or "" end
		c.IsMember = function() return w.member ~= false end
		c.IsHighCouncillor = function(name) return w.council[c.FullName(name or c.me):lower()] == true end
		c.CouncilTitle = function(name)
			local who = c.FullName(name or c.me):lower()
			return c.IsHighCouncillor(name or c.me) and w.departments[who] and { dept = w.departments[who] } or nil
		end
		c.CouncilTitles = function()
			local grouped, order = {}, {}
			for who, dept in pairs(w.departments) do
				if w.council[who] then
					if not grouped[dept] then grouped[dept], order[#order + 1] = {}, dept end
					grouped[dept][#grouped[dept] + 1] = { name = c.ShortName(who) }
				end
			end
			local depts = {}
			for _, dept in ipairs(order) do depts[#depts + 1] = { name = dept, members = grouped[dept] } end
			return { depts = depts }
		end
		c.KingCharacter = function() return w.king end
		c.IsKingCharacter = function(name) return c.FullName(name):lower() == w.king:lower() end
		c.Stewards = function()
			local out = {}
			for who in pairs(w.stewards) do out[#out + 1] = who end
			return out
		end
		c.IsSteward = function(name) return w.stewards[c.FullName(name):lower()] == true end
		c.Roster = { members = {}, ClassCode = function(file)
			local codes = { WARRIOR = "WA", MAGE = "MA", PALADIN = "PA" }
			return codes[file] or ""
		end }
		c.Workshop = { IsAuthor = function() return w.author == true end, Visible = function() return w.preview == true end }
		c.Moderation = {
			SelfOff = function() return nil end, YouText = function() return "off" end,
			Hides = function() return false end, Any = function() return false end,
		}
		c.Channels = {
			IsMe = function(name) return c.FullName(name):lower() == c.me:lower() end,
			Admit = function() if w.filtered then return false, "filtered" end return true, "ok" end,
		}
		c.Fire = function(name, ...) w.events[#w.events + 1] = { name, ... } end
		c.On = function(name, call) w.listeners[name] = call end
		c.RegisterEvent = function(name, call) w.nativeEvents[name] = call end
		c.Print = function(message) w.printed = tostring(message) end
		c.ShowDialog = function(which, a, b, data) w.dialog = { which = which, a = a, b = b, data = data } end
		c.Consent = {
			Register = function(spec) w.consent = spec end,
			Ask = function(key) w.asked[#w.asked + 1] = key end,
		}

		local function Queue(dist, msg, target, logged, done, options)
			w.attempts = w.attempts + 1
			if w.rejectAt == w.attempts then
				if done then done(false, "full") end
				return false
			end
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, target = target, logged = logged,
				done = done, options = options }
			return true
		end
		c.Comm = {
			Handle = function(kind, call) w.handlerKind, w.handler = kind, call end,
			QueueRoom = function() return 60 - #w.jobs end,
			ChannelReady = function() return w.channel ~= nil end,
			ChannelName = function() return w.channel end,
			DeliveredLogged = function() return w.logged end,
			Send = function(dist, msg, _, _, logged, done, options) return Queue(dist, msg, nil, logged, done, options) end,
			Whisper = function(target, msg, _, _, logged, done, options) return Queue("WHISPER", msg, target, logged, done, options) end,
			Cancel = function(owner)
				local kept = {}
				for _, job in ipairs(w.jobs) do
					if job.options and job.options.owner == owner then
						w.cancelled = w.cancelled + 1
						if job.done then job.done(false, "cancelled") end
					else kept[#kept + 1] = job end
				end
				w.jobs = kept
			end,
			CancelQueued = function(owner, key, why)
				local dropped, kept = {}, {}
				for _, job in ipairs(w.jobs) do
					if job.options and job.options.owner == owner and job.options.key == key then dropped[#dropped + 1] = job
					else kept[#kept + 1] = job end
				end
				w.jobs = kept
				for _, job in ipairs(dropped) do if job.done then job.done(false, why) end end
				return #dropped
			end,
		}
		function w.finish(job, sent, why)
			local permitted, permitWhy = true, nil
			if job.options and job.options.permit then
				permitted, permitWhy = job.options.permit(job.options.owner, job.options.key, job.dist, job.target, job.msg)
			end
			if job.done then job.done(permitted and sent ~= false, permitWhy or why) end
			return permitted, permitWhy
		end
		function w.clearJobs() w.jobs, w.attempts, w.rejectAt = {}, 0, nil end
		function w.advance(seconds) w.mono, w.epoch = w.mono + seconds, w.epoch + seconds end

		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
		w.ns, w.Rooms = c, c.ChatRooms
		w.Rooms.Reset()
		fn(w, w.Rooms, c)
	end)
	for _, name in ipairs(globals) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

local function RoomMessage(id, line, words, version, guild, class)
	return ("M2~%s~%s~%d~%s~%s~%s"):format(version or "1", id, line, class == nil and "WA" or class, guild or "Olympus II", words)
end

test("chat Artisanry department: canonical label and signed legacy aliases preserve the room id", function()
	WithRooms(function(w, R, c)
		eq(R.Info("dept:citizenry").label, "Association of Artisanry")
		w.council[c.me:lower()] = true
		for _, title in ipairs({ "Association of Artisanry", "Association of Citizenry", "Artisanship" }) do
			w.departments[c.me:lower()] = title
			eq(R.CanAccess("dept:citizenry"), true, title)
		end
		w.council[c.me:lower()] = nil
		eq(R.CanAccess("dept:citizenry"), false, "a title without signed membership grants nothing")
	end)
end)

test("chat rooms: race and class are explicit open-topic choices with independent bounded histories", function()
	WithRooms(function(w, R, c)
		UnitClass = function() error("room discovery must not inspect the character's class") end
		C_CreatureInfo = { GetRaceInfo = function() error("room discovery must not inspect the character's race") end }
		local tabs = R.Tabs()
		eq(#tabs, 3); eq(tabs[1].id, "guild"); eq(tabs[2].kind, "race"); eq(tabs[2].id, nil)
		eq(tabs[3].kind, "class"); eq(tabs[3].id, nil)
		eq(R.Selected("race"), nil); eq(R.Selected("class"), nil)
		-- (1.2.1: only our faction's races: an Alliance character gets no Orc room, a Horde one no Human
		-- room; every class for both, Forever's Alliance having Shamans too.)
		local faction = c.faction
		c.faction = "Alliance"
		eq(#R.Options("race"), 5); eq(#R.Options("class"), 9)
		for _, o in ipairs(R.Options("race")) do assert(o.id ~= "race:2", "no Orc room for the Alliance") end
		eq(R.Options("race")[5].id, "race:95", "the Skyborn's room"); eq(R.Options("race")[5].raceName, "Skyborn")
		c.faction = "Horde"
		eq(#R.Options("race"), 4); eq(R.Options("race")[1].id, "race:2"); eq(#R.Options("class"), 9)
		c.faction = faction

		assert(R.Select("race:1")); assert(R.Select("class:MA"))
		eq(R.Selected("race"), "race:1"); eq(R.Selected("class"), "class:MA")
		eq(R.Receive("CHANNEL", "Peer One-Realm", RoomMessage("race:2", 1, "not selected"), 1000), false)
		eq(R.Receive("CHANNEL", "Peer One-Realm", RoomMessage("race:1", 2, "race one"), 1001), true)
		eq(R.Receive("CHANNEL", "Peer Two-Realm", RoomMessage("class:MA", 3, "class one"), 1002), true)
		eq(#R.History("race:1"), 1); eq(R.History("race:1")[1].text, "race one")
		eq(#R.History("class:MA"), 1); eq(R.History("class:MA")[1].text, "class one")

		R.HISTORY = 3
		for i = 4, 7 do assert(R.Receive("CHANNEL", "Peer " .. i .. "-Realm", RoomMessage("race:1", i, "line " .. i), 1000 + i)) end
		local history = R.History("race:1")
		eq(#history, 3); eq(history[1].text, "line 5"); eq(history[3].text, "line 7")
		eq(#R.History("class:MA"), 1, "another logical room is untouched")
	end)
end)

test("chat rooms: the new audiences have separate consent and old or malformed wires fail closed", function()
	WithRooms(function(w, R, c)
		c.db.chatRooms = nil
		local sent, why = R.Send("guild", "hello")
		eq(sent, false); eq(why, "off"); eq(w.asked[1], "chatrooms")
		eq(c.db.addonChat, true, "the existing Olympus chat consent is independent")
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 1, "old", "0"), 1000), false)
		c.db.chatRooms = true
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 1, "old", "0"), 1000), false)
		eq(R.Receive("CHANNEL", "Peer-Realm", RoomMessage("guild", 2, "wrong lane"), 1001), false)
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 3, "wrong guild", "1", "Olympus III"), 1002), false)
		w.logged = false
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 4, "not logged"), 1003), false)
		w.logged = true
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 5, "good"), 1004), true)
		eq(R.History("guild")[1].text, "good")
	end)
end)

test("chat rooms: Guild uses native chat and open topics retain their scoped logged transports", function()
	WithRooms(function(w, R)
		UnitClass = function() error("M2 must not inspect or publish the character's class") end
		assert(R.Send("guild", "guild line"))
		eq(#w.jobs, 0, "never a hidden addon guild message")
		eq(w.nativeSent[1][1], "guild line"); eq(w.nativeSent[1][2], "GUILD")
		eq(#R.History("guild"), 0, "wait for the server's native echo")
		assert(w.nativeEvents.CHAT_MSG_GUILD("guild line", "Member-Realm"))
		eq(R.History("guild")[1].text, "guild line")
		local roomChanged, roomLine = 0, 0
		for _, event in ipairs(w.events) do
			if event[1] == "CHAT_ROOM_CHANGED" then roomChanged = roomChanged + 1 end
			if event[1] == "CHAT_ROOM_LINE" then roomLine = roomLine + 1 end
		end
		eq(roomChanged, 1); eq(roomLine, 0, "a local echo must not create unread state")

		UnitClass = function() return "Warrior", "WARRIOR" end
		R.Reset(); w.clearJobs(); w.advance(2); assert(R.Select("class:WA"))
		assert(R.Send("class:WA", "topic line"))
		eq(#w.jobs, 1); eq(w.jobs[1].dist, "CHANNEL"); eq(w.jobs[1].logged, true)
		w.channel = "A different channel"
		local permitted, why = w.finish(w.jobs[1], true)
		eq(permitted, false); eq(why, "moved"); eq(#R.History("class:WA"), 0, "never rerouted or echoed")
	end)
end)

test("native Guild destination: actual server event, identical messages, bounded history and consent", function()
	WithRooms(function(w, R, c)
		local receive = assert(w.nativeEvents.CHAT_MSG_GUILD)
		assert(receive("same words", "Guildmate-Realm"))
		assert(receive("same words", "Guildmate-Realm"))
		eq(#R.History("guild"), 2, "intentional identical sequential guild lines remain distinct")
		eq(#w.jobs, 0); eq(#w.nativeSent, 0, "receive never republishes")
		c.db.chatRooms = false; eq(receive("hidden", "Guildmate-Realm"), false)
		c.db.chatRooms = true; w.member = false; eq(receive("outside", "Guildmate-Realm"), false)
		w.member = true; w.guild = "Another guild"; eq(#R.History("guild"), 0, "prior guild history cannot leak into a new guild")
		assert(receive("new guild", "Guildmate-Realm")); eq(#R.History("guild"), 1)
		R.HISTORY = 2
		assert(receive("second", "Guildmate-Realm")); assert(receive("third", "Guildmate-Realm"))
		eq(#R.History("guild"), 2); eq(R.History("guild")[1].text, "second")
		C_ChatInfo.SendChatMessage = function() error("native send rejected") end
		local ok, why = R.Send("guild", "not echoed"); eq(ok, false); eq(why, "failed")
		eq(#R.History("guild"), 2, "failed native send adds no optimistic line")
	end)
end)

test("chat rooms: topic members send normally while outsiders need a warning and both request gates", function()
	WithRooms(function(w, R)
		assert(R.Select("class:WA"))
		assert(R.Send("class:WA", "member line"), "a member sends without a warning")
		eq(w.dialog, nil)
		assert(w.jobs[1].msg:match("^M2~1~class:WA~%d+~~Olympus II~member line$"), w.jobs[1].msg)
		w.finish(w.jobs[1], true)

		R.Reset(); w.clearJobs(); w.advance(2); assert(R.Select("class:MA"))
		local status = R.RequestStatus("class:MA")
		eq(status.member, false); eq(status.outsider, true); eq(status.canSend, true)
		assert(R.StatusText("class:MA"):find("not a member", 1, true), R.StatusText("class:MA"))
		local ok, why = R.Send("class:MA", "please invite me")
		eq(ok, false); eq(why, "confirm"); eq(#w.jobs, 0)
		assert(w.dialog and w.dialog.which == "OLYMPUS_CHATROOM_REQUEST", "explicit pre-send warning")
		assert(w.dialog.data.text == "please invite me" and w.dialog.data.id == "class:MA")
		assert(R.ConfirmRequest(w.dialog.data, true))
		eq(#w.jobs, 1); assert(w.jobs[1].msg:match("^M2~1~class:MA~%d+~RQ~Olympus II~please invite me$"), w.jobs[1].msg)
		eq(R.RequestStatus("class:MA").pending, true, "no second request races a queued one")
		w.finish(w.jobs[1], true)
		status = R.RequestStatus("class:MA")
		eq(status.canSend, false); eq(status.replied, false); eq(status.wait, R.REQUEST_WAIT)
		eq(R.History("class:MA")[1].request, true)

		w.advance(2)
		eq(R.Receive("CHANNEL", "Mage Member-Realm", RoomMessage("class:MA", 91, "I can help", "1", nil, "MA"), w.mono), true)
		status = R.RequestStatus("class:MA")
		eq(status.replied, true); eq(status.canSend, false, "a reply alone does not open the timer gate")
		assert(R.StatusText("class:MA"):find("wait", 1, true))
		w.advance(R.REQUEST_WAIT)
		status = R.RequestStatus("class:MA")
		eq(status.wait, 0); eq(status.replied, true); eq(status.canSend, true, "both gates open")
		R.Reset()
		eq(R.RequestStatus("class:MA").canSend, true, "the successful request record survives a session reset")
		w.dialog = nil
		eq(select(2, R.Send("class:MA", "second request")), "confirm", "every permitted request warns")
		assert(w.dialog and w.dialog.data.text == "second request")
		R.ConfirmRequest(w.dialog.data, false)

		R.Reset(); w.clearJobs(); w.dialog = nil; w.advance(2); assert(R.Select("race:2"))
		status = R.RequestStatus("race:2")
		eq(status.member, false); eq(status.outsider, true, "the same outsider rule covers race rooms")
		eq(select(2, R.Send("race:2", "orc request")), "confirm")
		assert(w.dialog and w.dialog.data.id == "race:2")
	end)
end)

test("chat rooms: King, signed councillor and real author are exempt from outsider request limits", function()
	WithRooms(function(w, R, c)
		local function SendAs(label, set)
			R.Reset(); w.clearJobs(); w.dialog = nil; w.advance(2)
			w.council, w.author = {}, false
			c.me = "Member-Realm"
			set()
			assert(R.Select("class:MA"), label)
			assert(R.Send("class:MA", label), label)
			eq(w.dialog, nil, label .. ": no outsider popup")
			assert(w.jobs[1].msg:match("^M2~1~class:MA~%d+~~Olympus II~"), label .. ": no RQ marker")
		end
		SendAs("king", function() c.me = w.king end)
		SendAs("councillor", function() w.council[c.me:lower()] = true end)
		SendAs("author", function() w.author = true end)
		w.author, w.preview = false, true
		R.Reset(); w.clearJobs(); w.dialog = nil; w.advance(2); assert(R.Select("class:MA"))
		eq(select(2, R.Send("class:MA", "preview is not authority")), "confirm", "Preview/ViewAs is not an exemption")
	end)
end)

test("chat rooms: receivers throttle marked or known outsider requests until time and a member reply", function()
	WithRooms(function(w, R, c)
		assert(R.Select("class:MA"))
		local function Receive(sender, line, words, class)
			return R.Receive("CHANNEL", sender, RoomMessage("class:MA", line, words, "1", nil, class), w.mono)
		end
		eq(Receive("Outsider-Realm", 1, "first request", "RQ"), true)
		w.advance(2)
		eq(Receive("Outsider-Realm", 2, "too soon", "RQ"), false)
		c.Roster.members = { { full = "Mage-Realm", class = "MA" }, { full = "Warrior-Realm", class = "WA" } }
		eq(Receive("Warrior-Realm", 3, "not a member reply", "WA"), true, "a known mismatch is itself one outsider request")
		eq(Receive("Mage-Realm", 4, "member reply", ""), true)
		w.advance(R.REQUEST_WAIT)
		eq(Receive("Outsider-Realm", 5, "after both gates", "RQ"), true)
		eq(Receive("Outsider-Realm", 6, "blocked again", "RQ"), false)
		eq(Receive("No Reply-Realm", 7, "request without reply", "RQ"), true)
		w.advance(R.REQUEST_WAIT)
		eq(Receive("No Reply-Realm", 8, "time alone is not enough", "RQ"), false)
		eq(Receive("Mage-Realm", 9, "later member reply", ""), true)
		eq(Receive("No Reply-Realm", 10, "now both gates", "RQ"), true)
	end)
end)

test("chat rooms: restricted tabs and recipients come only from current shared authority", function()
	WithRooms(function(w, R, c)
		eq(#R.Tabs(), 3, "ordinary members get no restricted destination")
		local me = c.me:lower()
		w.council[me] = true
		c.rdb.council.names[me] = true -- an older retained signed-list representation
		c.rdb.council.names["other councillor"] = "Other Councillor"
		w.council["other councillor-realm"] = true
		local tabs = R.Tabs()
		eq(tabs[4].kind, "role"); eq(tabs[4].dropdown, true)
		eq(R.Options("role")[1].id, "council")
		local recipients = R.Recipients("council")
		eq(#recipients, 3)
		local expected = { [c.FullName(w.king)] = true, [c.FullName(c.TREASURER)] = true, ["Other Councillor-Realm"] = true }
		for _, recipient in ipairs(recipients) do eq(expected[recipient], true, "Council includes the actual crown and federal treasurer") end

		local names = {
			["Federal Treasury"] = "Federal Treasury", ["Department of War"] = "Department of War",
			["Artisanship"] = "Association of Artisanry", ["Heraldry"] = "Department of Heritage",
			["Justice"] = "Council of Justice",
		}
		for signed, canonical in pairs(names) do
			w.departments[me] = signed
			local options = R.Options("department")
			eq(#options, 1); eq(options[1].label, canonical, signed)
		end
		w.council[me] = nil
		eq(#R.Options("department"), 0, "a department string without signed Council authority grants nothing")
	end)
end)

test("chat rooms: a restricted room whispers no one the server says is offline (the roster's offline members, a name just not found)", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me] = true
		w.council["alpha-realm"], w.council["beta-realm"], w.council["gamma-realm"] = true, true, true
		c.rdb.council.names = { [me] = "Member", alpha = "Alpha", beta = "Beta", gamma = "Gamma" }
		c.Roster.members = { { name = "Alpha", online = true }, { name = "Beta", online = false } }
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		assert(R.Send("council", "first line"))
		local function Targets()
			local out = {}
			for _, job in ipairs(w.jobs) do out[job.target] = true end
			return out
		end
		local t = Targets()
		eq(t["Alpha-Realm"], true); eq(t["Beta-Realm"], nil, "offline in the roster"); eq(t["Gamma-Realm"], true, "not in the roster: tried")
		eq(#w.jobs, 4, "the King, the Treasurer, Alpha and Gamma")
		-- The server answers Gamma is not playing: the next line leaves him out, until GONE_FOR passes.
		w.nativeEvents.CHAT_MSG_SYSTEM("No player named 'Gamma-Realm' is currently playing.")
		w.clearJobs(); w.advance(10)
		assert(R.Send("council", "second line"))
		eq(Targets()["Gamma-Realm"], nil); eq(#w.jobs, 3)
		w.clearJobs(); w.advance(R.GONE_FOR)
		assert(R.Send("council", "third line"))
		eq(Targets()["Gamma-Realm"], true)
		ERR_CHAT_PLAYER_NOT_FOUND_S = nil
	end)
end)

test("chat rooms: a race or class room gives each sender a fair share of its minute (PER_MINUTE), so one sender cannot crowd the others out", function()
	WithRooms(function(w, R, c)
		assert(R.Select("race:1"))
		for i = 1, R.PER_MINUTE do eq(R.Receive("CHANNEL", "Loud One-Realm", RoomMessage("race:1", i, "line " .. i), 1000 + i), true) end
		eq(R.Receive("CHANNEL", "Loud One-Realm", RoomMessage("race:1", 50, "one too many"), 1010), false, "past his share")
		eq(R.Receive("CHANNEL", "Quiet Two-Realm", RoomMessage("race:1", 51, "still heard"), 1011), true, "another sender")
		eq(R.Receive("CHANNEL", "Loud One-Realm", RoomMessage("race:1", 52, "a minute later"), 1062), true)
	end)
end)

assert(loadfile(ROOT .. "tests/chat-role-rooms.lua"))(ns, test, eq, WithRooms, RoomMessage)

test("chat rooms: restricted delivery is whisper-only, all-or-none on admission, and revocable in queue", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me] = true
		w.council["alpha-realm"], w.council["beta-realm"] = true, true
		c.rdb.council.names = { [me] = "Member", alpha = true, beta = "Beta" }
		assert(R.Send("council", "private line"))
		eq(#w.jobs, 4)
		local expected = { [c.FullName(w.king)] = true, [c.FullName(c.TREASURER)] = true, ["alpha-Realm"] = true, ["Beta-Realm"] = true }
		for _, job in ipairs(w.jobs) do eq(job.dist, "WHISPER"); eq(job.logged, true); eq(expected[job.target], true, "only the current Council audience") end
		w.council["alpha-realm"] = nil
		for _, job in ipairs(w.jobs) do
			local permitted = w.finish(job, true)
			if job.target:lower() == "alpha-realm" then eq(permitted, false) else eq(permitted, true) end
		end
		eq(#R.History("council"), 1, "a successful recipient produces one local echo")

		R.Reset(); w.clearJobs(); w.advance(2)
		w.council["alpha-realm"] = true
		w.rejectAt = 2
		local admitted = R.Send("council", "must be whole")
		eq(admitted, false); eq(#w.jobs, 0, "an admitted prefix is cancelled after a synchronous refusal")
		eq(#R.History("council"), 0)

		R.Reset(); w.clearJobs(); w.advance(2); w.rejectAt = nil
		assert(R.Send("council", "sender can be revoked"))
		w.council[me] = nil
		for _, job in ipairs(w.jobs) do eq((w.finish(job, true)), false, "sender authority checked at final send") end
		eq(#R.History("council"), 0)
	end)
end)

test("chat rooms: spoofed restricted senders are dropped and revocation erases retained history", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.council["peer-realm"] = true, true
		c.rdb.council.names = { [me] = "Member", peer = "Peer" }
		local msg = RoomMessage("council", 1, "classified")
		eq(R.Receive("CHANNEL", "Peer-Realm", msg, 1000), false, "wrong transport")
		eq(R.Receive("WHISPER", "Outsider-Realm", msg, 1001), false, "not in the signed audience")
		eq(R.Receive("WHISPER", "Peer-Realm", msg, 1002), true)
		eq(#R.History("council"), 1)
		w.council[me] = nil
		eq(R.RefreshAuthority(), true)
		w.council[me] = true
		eq(#R.History("council"), 0, "revoked restricted history is discarded, not merely hidden")
	end)
end)

-- 1.2 (CraftRequests.lua's private request rooms): a later file can own private rooms. The provider
-- alone answers for them; nothing of them goes over M2, and the rooms' own consent is untouched.
test("chat rooms: a provider's private rooms answer for themselves, never ride M2, and leave the rooms' consent alone", function()
	WithRooms(function(w, R, c)
		local sent, heard = {}, { { sender = "Wren Thistle-Realm", text = "context" } }
		local p = {
			Info = function(id) if id == "craft:abc1" then return { id = id, kind = id, label = "Mooncloth", scope = "private" } end end,
			CanAccess = function(id, name) return id == "craft:abc1" and (name == "Member-Realm" or name == "Wren Thistle-Realm") end,
			History = function() return heard end,
			Send = function(id, text) sent[#sent + 1] = text return true, "ok" end,
			Tabs = function() return { { kind = "craft:abc1", id = "craft:abc1", label = "Mooncloth" } } end,
			IsOpen = function() return true end,
			ChatOn = function() return true end,
		}
		eq(R.RegisterProvider({ Info = function() end }), false, "an incomplete provider is refused")
		eq(R.RegisterProvider(p), true); eq(R.RegisterProvider(p), true, "once")
		local tabs = R.Tabs()
		eq(tabs[#tabs].id, "craft:abc1")
		eq(R.Info("craft:abc1").scope, "private")
		eq(R.CanAccess("craft:abc1"), true); eq(R.CanAccess("craft:abc1", "Stranger-Realm"), false)
		c.db.chatRooms = false
		eq(R.ChatOn(), false, "the rooms' consent is the player's")
		eq(R.ChatOn("guild"), false)
		eq(R.ChatOn("craft:abc1"), true, "the provider's room answers for itself")
		eq(R.Select("craft:abc1"), true)
		eq(R.History("craft:abc1")[1].text, "context")
		eq(R.Send("craft:abc1", "a fellow-member price?"), true)
		eq(sent[1], "a fellow-member price?"); eq(#w.jobs, 0, "nothing queued by the rooms themselves")
		c.db.chatRooms = true
		eq(R.Receive("WHISPER", "Wren Thistle-Realm", RoomMessage("craft:abc1", 1, "over M2"), 1000), false, "an M2 line never lands in a provider's room")
		eq(R.RequestStatus("craft:abc1").canSend, true)
	end)
end)
