local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]squads%.lua$") or "./"
local function World(fn)
	local saved = { GetGuildInfo, IsInGuild, GetServerTime, GetTime, C_ChatInfo, StaticPopupDialogs }
	local w = { guild = "Olympus II", now = 1800000000, fresh = true, jobs = {}, council = {}, ranks = {}, events = {} }
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild end
		IsInGuild = function() return w.guild ~= nil end
		GetServerTime = function() return w.now end
		GetTime = function() return w.now end
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		StaticPopupDialogs = {}
		local c = setmetatable({ me = "Officer-Realm", db = { chatRooms = true }, rdb = { war = { centuries = { old = "preserved" } } },
			CAPTAIN_RANK = 1, Roster = { byName = {} }, ViewAs = {}, War = {}, ChatRooms = {}, Comm = {}, Nominees = {} }, { __index = ns })
		w.c = c
		c.Fold = string.lower
		c.FullName = function(name) return name:find("-", 1, true) and name or name .. "-Realm" end
		c.ShortName = function(name) return name:match("^[^-]+") end
		c.DisplayName = c.ShortName
		c.Normal = function(s) return s end
		c.Holds = function(q, ...) for _, text in ipairs({ ... }) do if text:lower():find(q:lower(), 1, true) then return true end end return false end
		c.ShowDialog = function(...) w.dialog = { ... }; return true end
		c.CouncilMasked = function() return w.masked == true end
		c.Now = function() return w.now end
		c.IsMember = function() return w.member ~= false end
		c.IsFederation = function(guild) return guild == "Olympus II" or guild == "Olympus" end
		c.IsKingGuild = function(guild) return guild == "Olympus" end
		c.IsHighCouncillor = function(name) return w.council[name] == true end
		c.ChatLocked = function() return w.locked == true end
		c.ViewAs.Previewing = function() return w.preview == true end
		c.Roster.Fresh = function() return w.fresh and c.Roster or nil end
		c.Roster.RankOf = function(name) return w.ranks[name] end
		c.Roster.IsOfficer = function() return (w.ranks[c.me] or 9) <= 1 end
		for _, name in ipairs({ "Officer", "Leader", "OtherLeader", "Outsider" }) do
			c.Roster.byName[name .. "-Realm"] = {}; w.ranks[name .. "-Realm"] = name == "Officer" and 0 or 9
		end
		for i = 1, 100 do c.Roster.byName["Soldier" .. i .. "-Realm"] = {}; w.ranks["Soldier" .. i .. "-Realm"] = 9 end
		w.list = { by = c.me, entries = { { name = "Leader-Realm", role = "centurion" }, { name = "OtherLeader-Realm", role = "centurion" } } }
		c.Nominees.ListOf = function() return w.list end
		c.Nominees.Proven = function(name) return name == "Officer-Realm" and w.proven ~= false end
		c.Nominees.RoleOf = function(name) for _, e in ipairs(w.list.entries) do if e.name == name then return e.role end end end
		c.Nominees.IsCorrespondent = function() return false end
		c.War.IsWarCouncillor = function() return false end
		c.Fire = function(...) w.events[#w.events + 1] = { ... } end
		c.On = function() end
		c.Consent = {}; c.L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
		c.RealmPages = {}
		c.ChatRooms.RegisterProvider = function(p) w.provider = p end
		c.Comm.Handle = function() end
		c.Comm.DeliveredLogged = function() return w.logged ~= false end
		c.Comm.Send = function(dist, msg, key, _, _, _, options)
			assert(options.owner and options.key and type(options.permit) == "function", "actual Comm capability contract")
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, key = options.key or key, options = options }; return true
		end
		c.Comm.SendChunked = function(msg, _, dist, _, options) return c.Comm.Send(dist, msg, options.key, nil, nil, nil, options) end
		c.Comm.Whisper = function(to, msg, key, _, logged, done, options)
			w.jobs[#w.jobs + 1] = { to = to, msg = msg, key = key, logged = logged, done = done, options = options }; return true
		end
		c.Channels = { Admit = function() return not w.filtered, "filtered" end }
		c.Moderation = { Hides = function() return w.hidden == true end, Blocks = function() return false end }
		assert(loadfile(ROOT .. "Olympus/WarSquads.lua"))("Olympus", c)
		fn(w, c.WarSquads)
	end)
	GetGuildInfo, IsInGuild, GetServerTime, GetTime, C_ChatInfo, StaticPopupDialogs = unpack(saved, 1, 6)
	if not ok then error(err, 0) end
end
local function RealTransport(w)
	local c, events, login = w.c, {}, {}
	c.PREFIX = ns.PREFIX or "Olympus"
	c.db.blocked = {}
	c.RegisterEvent = function(event, callback) events[event] = callback end
	c.On = function(event, callback) if event == "LOGIN" then login[#login + 1] = callback end end
	c.After, c.Every, c.Log = function() end, function() end, function() end
	c.SafeCall = function(_, fn, ...) return fn(...) end
	w.native = {}
	local function Send(prefix, msg, dist, target) w.native[#w.native + 1] = { prefix = prefix, msg = msg, dist = dist, target = target }; return 0 end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send }
	assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c)
	for _, callback in ipairs(login) do callback() end
	c.Comm.Handle("WU", c.WarSquads.Handle)
	c.Comm.Handle("SC", c.WarSquads.ReceiveChat)
	return events
end

test("Squads: bounded assignments preserve Centuries and require current officer authority", function()
	World(function(w, s)
		eq(#s.Leaders(), 2); eq(s.Get("Leader").count, 0)
		local soldiers = {}; for i = 1, 99 do soldiers[i] = "Soldier" .. i end
		eq(s.Replace("Leader", soldiers), true); eq(s.Get("Leader").count, 99)
		local oldJob = w.jobs[#w.jobs]
		eq(s.Assign("Leader", "Soldier100"), false); eq(s.Get("Leader").count, 99)
		soldiers[100] = "Soldier100"; eq(s.Replace("Leader", soldiers), false); eq(s.Get("Leader").count, 99)
		eq(s.Replace("Leader", { "Leader" }), false)
		eq(s.Replace("Leader", { "Soldier1", "Soldier1" }), false)
		eq(s.Replace("Leader", { "Unknown" }), false)
		eq(s.Remove("Leader", "Soldier10"), true)
		eq(oldJob.options.permit(nil, oldJob.key, "GUILD", nil, oldJob.msg), false)
		eq(s.Assign("Leader", "Soldier10"), true)
		w.preview = true; eq(s.Replace("Leader", {}), false); w.preview = false
		eq(s.Request(), true); eq(s.Request(), false)
		local query = w.jobs[#w.jobs]
		eq(query.options.permit(nil, query.key, "GUILD", nil, query.msg), true)
		w.c.me = "Leader-Realm"; eq(s.Replace("Leader", {}), false)
		w.c.me = "Officer-Realm"; w.fresh = false; eq(s.Replace("Leader", {}), false)
		eq(w.c.rdb.war.centuries.old, "preserved")
	end)
end)
test("Squads: actual Realm tree inserts only own-guild hierarchy when that guild is expanded", function()
	World(function(w, s)
		local c = w.c
		c.UI = { Refresh = function() end }
		c.CouncilVisible = function() return false end
		c.Court, c.Hop, c.Board, c.Members, c.Treasury, c.Who = {}, {}, {}, {}, {}, {}
		c.Hop.State = function() return nil end
		c.Layers = { CurrentMap = function() return nil end }
		c.King = { CanCommand = function() return false end, Preview = function() return false end }
		c.Acts = { Gates = function() return nil end }
		c.FormatNumber = tostring
		c.Roster.online = {}
		c.Data = { Dispute = function() return nil end, Summary = function() return { guilds = {
			{ name = w.guild, fresh = true, g = { leader = "Officer", total = 15, online = 0, mine = true } },
			{ name = "Olympus III", fresh = true, g = { leader = "Foreign", total = 15, online = 0 } },
		} } end }
		assert(loadfile(ROOT .. "Olympus/Views.lua"))("Olympus", c)
		local function Count(lines) local count = 0; for _, line in ipairs(lines) do if line.squadLeader then count = count + 1 end end return count end
		eq(Count(c.Views.RealmLines()), 0)
		local header
		for _, line in ipairs(c.Views.RealmLines()) do if line.id == c.Views.GuildId(w.guild) then header = line end end
		eq(header ~= nil, true); header.onClick()
		eq(Count(c.Views.RealmLines()), 2)
		header.onClick(); eq(Count(c.Views.RealmLines()), 0)
	end)
end)
test("Squads: discoverable leader hierarchy includes zero squads, capped officer dialog/actions and masked/search views", function()
	World(function(w, s)
		local lines = s.Lines()
		local empty, add = 0, nil
		for _, line in ipairs(lines) do if line.text == "No soldiers assigned" then empty = empty + 1 end; if line.text == "Assign soldier" then add = line end end
		eq(empty, 2); eq(add ~= nil, true); eq(add.onClick(), true)
		eq(w.dialog[1], "OLYMPUS_WAR_INPUT"); eq(w.dialog[4].prefix, "squadadd OtherLeader-Realm|")
		assert(loadfile(ROOT .. "Olympus/War.lua"))("Olympus", w.c)
		local seen = false; for _, line in ipairs(w.c.War.Lines("OtherLeader")) do if line.squadLeader == "OtherLeader-Realm" then seen = true end end
		eq(seen, true)
		eq(w.c.War.Slash(w.dialog[4].prefix .. "Soldier1"), true)
		eq(s.Get("OtherLeader").count, 1)
		local remove
		for _, line in ipairs(s.Lines("Soldier1")) do if line.text == "Remove soldier" then remove = line end end
		eq(remove ~= nil, true)
		w.c.me = "Outsider-Realm"; eq(remove.onClick(), false); eq(s.Get("OtherLeader").count, 1)
		w.c.me = "Officer-Realm"; eq(remove.onClick(), true); eq(s.Get("OtherLeader").count, 0)
		eq(#s.Lines("not found"), 0)
		w.guild = "Olympus"; w.c.rdb.council = { blob = "HS1~1~Alliance~Leader~abcd" }; w.council["Leader-Realm"] = true; w.masked = true
		for _, line in ipairs(s.Lines()) do eq(line.text:find("Leader", 1, true), nil); eq(line.player, nil); eq(line.squadLeader, nil); eq(line.onClick, nil) end
		eq(#s.Lines("Leader"), 0)
	end)
end)
test("Squads: actual ChatRooms dynamic Roles menu discovers only authorized private squad rooms", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room
		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", w.c)
		local r = w.c.ChatRooms; eq(r.RegisterProvider(s.ChatProvider), true)
		w.c.me = "Soldier1-Realm"
		local found = false; for _, info in ipairs(r.Options("role")) do if info.id == room then found = true end end
		eq(found, true); eq(r.Select(room), true)
		found = false; for _, tab in ipairs(r.Tabs()) do if tab.kind == "role" then found = true end end
		eq(found, true)
		w.c.me = "Outsider-Realm"
		for _, info in ipairs(r.Options("role")) do eq(info.id == room, false) end
		eq(r.Select(room), false)
	end)
end)
test("Squads: actual hierarchy chat callback and OpenMatter route select only the authenticated room", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room; w.c.me = "Soldier1-Realm"
		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", w.c)
		local rooms = w.c.ChatRooms; eq(rooms.RegisterProvider(s.ChatProvider), true)
		-- Only the native window boundary is simulated; both the row callback and
		-- logical room/opening dispatcher are the actual addon functions.
		local pane, opened, raised, selected = {}, 0, 0, nil
		w.c.ChatWindow = {
			Open = function() opened = opened + 1; return pane end,
			SelectLogical = function(id) selected = id; return rooms.Select(id) end,
			Window = function() return { Raise = function() raised = raised + 1 end } end,
		}
		local action
		for _, line in ipairs(s.Lines()) do if line.text == (rawget(w.c.L, "SQUAD_OPEN_CHAT") or "Open private squad chat") then action = line.onClick end end
		eq(type(action), "function"); eq(action(), pane); eq(selected, room); eq(opened, 1); eq(raised, 1)
		w.c.me = "Outsider-Realm"; eq(action(), false); eq(rooms.OpenMatter({ room = room }), false); eq(opened, 1)
	end)
end)
test("Squads: main leaders follow held signed order without invented identities or foreign roster authority", function()
	World(function(w, s)
		w.guild = "Olympus"; w.c.council = nil
		w.c.rdb.council = { blob = "HS1~1~Alliance~OtherLeader,Missing,Leader~abcd" }
		w.council["OtherLeader-Realm"], w.council["Leader-Realm"] = true, true
		local leaders = s.Leaders(); eq(#leaders, 2); eq(leaders[1].name, "OtherLeader-Realm"); eq(leaders[2].name, "Leader-Realm")
		w.council["Leader-Realm"] = nil; eq(#s.Leaders(), 1)
		w.guild = "Olympus II"; w.proven = false; eq(#s.Leaders(), 0)
		w.proven = true; w.ranks["Officer-Realm"] = 1; eq(#s.Leaders(), 0)
	end)
end)
test("Squads: guild-local authenticated snapshots reject malformed, stale and unauthorized input", function()
	World(function(w, s)
		local msg = "WU~1~S~Leader-Realm~1800000000~Soldier1-Realm"
		eq(s.Handle("WHISPER", "Officer-Realm", msg), false)
		eq(s.Handle("GUILD", "Outsider-Realm", msg), false)
		eq(s.Handle("GUILD", "Officer-Realm", msg), true); eq(s.Get("Leader").count, 1)
		eq(s.Handle("GUILD", "Officer-Realm", msg), false)
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000301~"), false)
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000001~,Soldier2-Realm"), false)
		eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true)
		local job = w.jobs[#w.jobs]; eq(job.options.permit(nil, job.key, "GUILD", nil, job.msg), true)
		eq(job.options.permit(nil, job.key, "WHISPER", nil, job.msg), false)
		w.ranks["Officer-Realm"] = 9; eq(job.options.permit(nil, job.key, "GUILD", nil, job.msg), false)
	end)
end)
test("Squads: private chat excludes implicit royal/officer access and revalidates queued recipients and history", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room
		eq(s.CanAccess(room), false); eq(s.CanAccess(room, "Leader"), true)
		w.c.me = "Leader-Realm"; eq(#w.provider.Options("role"), 1)
		eq(s.ChatSend(room, "hello"), true)
		local job = w.jobs[#w.jobs]; eq(job.logged, true); eq(job.options.guard(), true)
		w.c.Roster.byName["Soldier1-Realm"] = nil; eq(job.options.guard(), false)
		job.done(true); eq(#s.ChatHistory(room), 0)
		w.c.Roster.byName["Soldier1-Realm"] = {}
		eq(s.ChatSend(room, "second"), true); w.jobs[#w.jobs].done(true); eq(#s.ChatHistory(room), 1)
		w.hidden = true; eq(#s.ChatHistory(room), 0); w.hidden = false
		w.preview = true; eq(#s.ChatHistory(room), 0); eq(s.ChatSend(room, "no"), false); w.preview = false
		w.c.me = "Outsider-Realm"; eq(#s.ChatHistory(room), 0); eq(#w.provider.Options("role"), 0)
		w.c.me = "Soldier1-Realm"; eq(#s.ChatHistory(room), 1)
		w.c.Roster.byName["Soldier1-Realm"] = nil; eq(#s.ChatHistory(room), 0)
	end)
end)
test("Squads: live private receive validates both participants, logged transport, replay and actual filter", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room; w.c.me = "Soldier1-Realm"
		local msg = "SC~1~" .. room:sub(7) .. "~1~hello"
		eq(s.ReceiveChat("GUILD", "Leader", msg), false)
		w.logged = false; eq(s.ReceiveChat("WHISPER", "Leader", msg), false); w.logged = true
		eq(s.ReceiveChat("WHISPER", "Outsider", msg), false)
		w.filtered = true; eq(s.ReceiveChat("WHISPER", "Leader", msg), false); w.filtered = false
		eq(s.ReceiveChat("WHISPER", "Leader", msg), true); eq(#s.ChatHistory(room), 1)
		eq(s.ReceiveChat("WHISPER", "Leader", msg), false)
		w.list.entries = {}; eq(s.ReceiveChat("WHISPER", "Leader", msg:gsub("~1~hello", "~2~later")), false); eq(#s.ChatHistory(room), 0)
	end)
end)
test("Squads: two actual clients converge complete assignments and exchange only private logged chat", function()
	World(function(a, sa)
		eq(sa.Replace("Leader", { "Soldier1" }), true)
		local assignment, room = a.jobs[1].msg, sa.Get("Leader").room
		a.c.me = "Leader-Realm"; eq(sa.ChatSend(room, "private"), true)
		local whisper = a.jobs[#a.jobs]; eq(whisper.to, "Soldier1-Realm")
		World(function(b, sb)
			b.c.me = "Soldier1-Realm"
			eq(sb.Handle("GUILD", "Officer-Realm", assignment), true)
			eq(sb.Get("Leader").room, room); eq(sb.Get("Leader").count, 1)
			eq(sb.ReceiveChat("WHISPER", "Leader-Realm", whisper.msg), true)
			eq(sb.ChatHistory(room)[1].text, "private")
			local first = "WU~1~S~Leader-Realm~1800000001~Soldier1-Realm"
			local second = "WU~1~S~Leader-Realm~1800000001~Soldier2-Realm"
			eq(sb.Handle("GUILD", "Officer-Realm", second), true)
			eq(sb.Handle("GUILD", "Officer-Realm", first), false)
			eq(sa.Handle("GUILD", "Officer-Realm", first), true)
			eq(sa.Handle("GUILD", "Officer-Realm", second), true)
			eq(sa.Get("Leader").soldiers[1], sb.Get("Leader").soldiers[1])
			eq(sb.CanAccess(room), false); eq(#sb.ChatHistory(room), 0)
		end)
	end)
end)
test("Squads: real SendChunked pump and GUILD reassembly deliver 99 maximum-length full names end to end", function()
	local names = {}
	local leader = "Leader" .. string.rep("a", 58) .. "AA-Realm"
	for i = 1, 99 do names[i] = "Soldier" .. string.rep("a", 57) .. string.char(65 + math.floor((i - 1) / 26), 65 + (i - 1) % 26) .. "-Realm" end
	World(function(a, sa)
		a.c.Roster.byName[leader], a.ranks[leader] = {}, 9; a.list.entries[1].name = leader
		for _, name in ipairs(names) do a.c.Roster.byName[name], a.ranks[name] = {}, 9 end
		RealTransport(a)
		eq(sa.Replace(leader, names), true)
		eq(#leader, 72); eq(#names[1], 72)
		eq(99 * 72 + 98 + 72 + 10 + 9 <= a.c.Codec.CHUNK * a.c.Codec.MAX_CHUNKS, true, "worst-case full header and members fit")
		eq(a.c.Comm.QueueSize() > 1, true, "the actual queue must contain a multipart transfer")
		for _ = 1, 40 do a.c.Comm.Pump(); a.now = a.now + 2 end
		eq(a.c.Comm.QueueSize(), 0); eq(#a.native, 34, "the inclusive worst-case wire uses exactly the new bound")
		for _, piece in ipairs(a.native) do eq(piece.dist, "GUILD"); eq(#piece.msg <= 255, true) end
		World(function(b, sb)
			b.c.me = names[1]
			b.c.Roster.byName[leader], b.ranks[leader] = {}, 9; b.list.entries[1].name = leader
			for _, name in ipairs(names) do b.c.Roster.byName[name], b.ranks[name] = {}, 9 end
			local events = RealTransport(b)
			for i = #a.native, 1, -1 do
				local piece = a.native[i]
				events.CHAT_MSG_ADDON(piece.prefix, piece.msg, piece.dist, "Officer-Realm")
			end
			eq(sb.Get(leader).count, 99, "the actual guild assembler must dispatch WU to the actual model")
			for i, name in ipairs(sa.Get(leader).soldiers) do eq(sb.Get(leader).soldiers[i], name) end
			eq(sb.CanAccess(sb.Get(leader).room), true)
			local asm = b.c.Codec.NewAssembler()
			eq(b.c.Codec.Feed(asm, "Officer-Realm", "Coversize:1:35:WU~1~Q", b.now), nil)
			eq(asm.open, 0, "35 parts are refused before allocating an assembly")
		end)
	end)
end)
test("Squads: only transfers above 30 parts receive the bounded 70 second assembly lifetime", function()
	World(function(w)
		RealTransport(w)
		local codec, asm = w.c.Codec, w.c.Codec.NewAssembler()
		eq(codec.Feed(asm, "Officer-Realm", "Csmall:1:30:WU~1~Q", w.now), nil)
		eq(codec.Feed(asm, "Officer-Realm", "Clarge:1:34:WU~1~Q", w.now), nil)
		eq(asm.open, 2)
		eq(codec.Gc(asm, w.now + 61), 1); eq(asm.open, 1)
		eq(codec.Gc(asm, w.now + 70), 0); eq(asm.open, 1)
		eq(codec.Gc(asm, w.now + 71), 1); eq(asm.open, 0)
	end)
end)
test("Squads: malformed saved containers fail closed without replacing existing data", function()
	World(function(w, s)
		for _, bad in ipairs({ false, "broken", 12 }) do
			w.c.rdb.warSquads = bad; eq(s.Replace("Leader", {}), false); eq(w.c.rdb.warSquads, bad)
			w.c.rdb.warSquads = { ["olympus ii"] = bad }; eq(s.Replace("Leader", {}), false); eq(w.c.rdb.warSquads["olympus ii"], bad)
		end
	end)
end)
test("Squads: malformed saved rows reject rendering, mutation, replay and unsafe query serialization", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local store = w.c.rdb.warSquads["olympus ii"]
		for _, members in ipairs({ { false }, { [2] = "Soldier1-Realm" }, { "Soldier1-Realm", "Soldier1-Realm" }, { "Leader-Realm" }, { junk = "Soldier1-Realm" } }) do
			local row = { leader = "Leader-Realm", rev = w.now, members = members }; store.rows["leader-realm"] = row
			eq(s.Get("Leader").count, 0); eq(s.Replace("Leader", {}), false); eq(store.rows["leader-realm"], row)
			eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000000~"), false)
		end
		store.rows["leader-realm"] = { leader = "Leader-Realm", rev = w.now, members = { "Soldier1-Realm" } }
		store.rows.bad = false
		eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true); eq(store.rows.bad, false)
	end)
end)
test("Squads: malformed saved chat lines and seen maps fail closed without overwriting history", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local store, room = w.c.rdb.warSquads["olympus ii"], s.Get("Leader").room
		w.c.me = "Leader-Realm"
		local badChats = { false, "broken", { seq = 0, lines = {}, seen = false }, { seq = 0, lines = { false }, seen = {} },
			{ seq = 0, lines = { [2] = { sender = "Leader-Realm", text = "old", t = w.now, id = 1 } }, seen = {} },
			{ seq = 0, lines = {}, seen = { [false] = 1 } }, { seq = 0, lines = {}, seen = { ["Soldier1-Realm"] = "bad" } } }
		local tooManyLines, tooManySeen = {}, {}
		for i = 1, s.CHAT_MAX + 1 do tooManyLines[i] = { sender = "Leader-Realm", text = "old", t = w.now, id = i } end
		for i = 1, s.SEEN_MAX + 1 do tooManySeen["Old" .. i .. "-Realm"] = i end
		badChats[#badChats + 1] = { seq = 0, lines = tooManyLines, seen = {} }
		badChats[#badChats + 1] = { seq = 0, lines = {}, seen = tooManySeen }
		local msg = "SC~1~" .. room:sub(7) .. "~1~hello"
		for _, bad in ipairs(badChats) do
			store.chats[room] = bad
			eq(s.ChatSend(room, "new"), false); eq(#s.ChatHistory(room), 0)
			eq(s.ReceiveChat("WHISPER", "Soldier1-Realm", msg), false); eq(store.chats[room], bad)
		end
	end)
end)
