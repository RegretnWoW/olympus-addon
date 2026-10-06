-- The Watch's chat moderation (1.1.6, WatchChat.lua): deleted lines, timeouts, the guild master's
-- Watchers, the Olympus moderators, the audit, a sanction's bars. A small world of clients, each
-- with the real Watch.lua, Channels.lua, ChatRooms.lua and WatchChat.lua loaded into a namespace
-- of its own, talks through a stand-in transport: the server stamps the sender, GUILD reaches the
-- sender's guild, CHANNEL everyone, a queued message's permit or guard runs when it "leaves".
-- Every test name starts with "watch: chat moderation:", so
--   OLYMPUS_TEST_WATCH_ONLY=1 luajit tests/run.lua "chat moderation"
-- runs them alone.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]watch%-chat%.lua$")) or "./"

local GLOBALS = { "GetGuildInfo", "IsInGuild", "UnitIsPlayer", "C_ChatInfo", "GetTime", "DEFAULT_CHAT_FRAME", "IsCombatLog",
	"issecretvalue", "UnitClass", "C_FriendList", "SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1", "SLASH_OLYMPUSLORDS1" }

local function Fold(s) return ns.Fold(tostring(s or "")) end
local function Full(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or name:find("-", 1, true) then return name end
	return name .. "-Realm"
end

-- A chat window of the game's: AddMessage keeps each line; TransformMessages calls the predicate
-- and the transform with (message, r, g, b) as Forever's CircularBuffer does
-- (Blizzard_SharedXML/ScrollingMessageFrame.lua, CircularBuffer.lua's TransformIf).
local function Frame(opts)
	local f = { lines = {}, calls = 0, combat = opts and opts.combat or nil }
	function f:AddMessage(text, r, g, b) self.lines[#self.lines + 1] = { message = text, r = r, g = g, b = b } end
	function f:TransformMessages(predicate, transform)
		self.calls = self.calls + 1
		for i, e in ipairs(self.lines) do
			if predicate(e.message, e.r, e.g, e.b) then
				local m, r, g, b = transform(e.message, e.r, e.g, e.b)
				self.lines[i] = { message = m, r = r, g = g, b = b }
			end
		end
	end
	return f
end

local function World(fn)
	local saved, dialogs, slash = {}, {}, {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for k, v in pairs(SlashCmdList) do slash[k] = v end
	local w = { epoch = 1800000000, clients = {}, wire = {}, sent = {}, guilds = {}, council = {}, stewards = {}, hands = {},
		off = {}, links = {}, logged = true }
	local ok, err = pcall(function()
		GetGuildInfo = function(unit)
			local c = w.current
			if c and (unit == nil or unit == "player") and c.guild then return c.guild, "Rank", c.rank end
		end
		IsInGuild = function() return w.current ~= nil and w.current.guild ~= nil end
		UnitIsPlayer = function() return false end
		C_ChatInfo = { SendAddonMessageLogged = function() return true end }
		GetTime = function() return w.epoch end
		IsCombatLog = function(f) return type(f) == "table" and f.combat == true end
		issecretvalue = function(v) return w.secret ~= nil and v == w.secret end
		UnitClass = function() return "Warrior", "WARRIOR" end
		C_FriendList = nil

		-- Runs fn as client cl: its guild for GetGuildInfo, its chat window for DEFAULT_CHAT_FRAME.
		function w.As(cl, f, ...)
			local was, frame = w.current, DEFAULT_CHAT_FRAME
			w.current, DEFAULT_CHAT_FRAME = cl, cl.frame
			local res = { pcall(f, ...) }
			w.current, DEFAULT_CHAT_FRAME = was, frame
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2, table.maxn(res))
		end

		-- The server's roster of each guild: [guild][Name-Realm] = rank.
		function w.SetRank(name, guild, rank)
			name = Full(name)
			for g, list in pairs(w.guilds) do if g ~= guild then list[name] = nil end end
			if guild then
				w.guilds[guild] = w.guilds[guild] or {}
				w.guilds[guild][name] = rank
			end
			for _, cl in ipairs(w.clients) do if cl.name == name then cl.guild, cl.rank = guild, rank end end
		end

		function w.Client(short, guild, rank, opts)
			opts = opts or {}
			local name = Full(short)
			local cl = { name = name, short = short, guild = guild, rank = rank, handlers = {}, events = {}, listeners = {},
				dialogs = {}, prints = {}, timers = {}, frame = Frame(), online = true }
			w.SetRank(name, guild, rank)
			local c = setmetatable({}, { __index = ns })
			cl.ns = c
			c.L = ns.L
			c.me, c.realm, c.group, c.faction = name, "Realm", "RealmGroup", "Alliance"
			c.CAPTAIN_RANK = 1
			c.db = { addonChat = true, chatRooms = true, chatWarned = { A = true, C = true, L = true }, blocked = {} }
			c.rdb = { guilds = {} }
			c.Now = function() return w.epoch end
			-- (The census: each guild's ranks as its reports name them.)
			c.Data = { ServerTime = function() return w.epoch end, ClaimGuild = function() return true end,
				AuthorizedRank = function(n, g) local list = g and w.guilds[g] return list and list[c.FullName(n)] or nil end, FRESH = 900 }
			c.FullName = function(n, realm)
				n = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" or n:find("-", 1, true) then return n end
				return n .. "-" .. (realm or "Realm")
			end
			c.DisplayName = function(n) return (tostring(n or ""):gsub("%-Realm$", "")) end
			c.IsMember = function() return cl.guild ~= nil and ns.IsFederation(cl.guild) end
			c.CouncilMasked = function() return cl.masked == true end
			c.GamepadUI = function() return w.gamepad == true end
			c.IsKingCharacter = function(n) return w.king ~= nil and type(n) == "string" and Fold(c.FullName(n)) == Fold(w.king) end
			c.KingCharacter = function() return w.king and (w.king:gsub("%-.*$", "")) or nil end
			c.IsHighCouncillor = function(n) return type(n) == "string" and w.council[Fold(c.FullName(n))] == true end
			c.IsSteward = function(n) return type(n) == "string" and w.stewards[Fold(c.FullName(n))] == true end
			c.Workshop = { IsAuthorName = function(n) return w.author ~= nil and type(n) == "string" and Fold(c.FullName(n)) == Fold(w.author) end }
			c.King = { IsHandName = function(n) return type(n) == "string" and w.hands[Fold(c.FullName(n))] == true end,
				IsStewardName = function(n) return c.IsSteward(n) end, IsKing = function() return c.IsKingCharacter(name) end,
				IsSteward = function() return false end, IsHand = function() return false end, Preview = function() return false end }
			local function CharName(input, target)
				local n = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" and target then n = tostring(cl.target or "") end
				if n == "" or n:find("[~|%c]") then return nil end
				return c.FullName(n)
			end
			c.Moderation = {
				CharName = CharName,
				Hidden = function(n) return w.off[Fold(c.FullName(n))] end,
				Hides = function(n) return w.off[Fold(c.FullName(n))] end,
				SelfOff = function() return w.off[Fold(name)] end,
				IsKing = function(n) return c.IsKingCharacter(n) end,
				GuildOf = function(n)
					for g, list in pairs(w.guilds) do if list[c.FullName(n)] ~= nil then return g end end
				end,
				Rank = function() return 0 end, TargetRank = function() return 0 end, IsIssuer = function() return false end,
				YouText = function() return "net-off" end, Any = function() return next(w.off) ~= nil end,
			}
			c.Alts = { Linked = function(n) return w.links[Fold(c.FullName(n))] or {} end }
			local roster = { byName = {}, complete = true, generation = 1, group = c.group, faction = c.faction, online = {} }
			setmetatable(roster, { __index = function(_, k)
				if k == "guild" then return cl.guild end
				if k == "snapshotAt" then return w.epoch end
			end })
			roster.RankOf = function(n) local list = cl.guild and w.guilds[cl.guild] return list and list[c.FullName(n)] or nil end
			roster.MyRank = function() return cl.rank end
			roster.IsOfficer = function() return cl.rank ~= nil and cl.rank <= 1 end
			roster.ClassCode = ns.Roster.ClassCode
			c.Roster = roster
			c.Fire = function(event, ...)
				cl.events[#cl.events + 1] = { event, ... }
				for _, f in ipairs(cl.listeners[event] or {}) do f(...) end
			end
			c.On = function(event, f) cl.listeners[event] = cl.listeners[event] or {}; table.insert(cl.listeners[event], f) end
			c.RegisterEvent = function() end
			c.Print = function(text) cl.prints[#cl.prints + 1] = tostring(text) end
			c.Log = function() end
			c.PlayAlert = function() end
			c.SafeCall = function(_, f, ...) return f(...) end
			c.After = function(seconds, _, f) cl.timers[#cl.timers + 1] = { at = w.epoch + (tonumber(seconds) or 0), fn = f } end
			c.Every = function() end
			c.ShowDialog = function(which, a, b, data) cl.dialogs[#cl.dialogs + 1] = { which = which, a = a, b = b, data = data } return true end
			c.UI = { TABS = {}, AddTab = function() return true end, SelectTab = function() end, ShowCopy = function() end }
			c.PlayerMenu = { Add = function() return true end }
			c.Court = { HomeLines = function() return {} end, Holding = function() return false end }
			c.Filter = { Hides = function(t) return w.filterWord ~= nil and tostring(t):find(w.filterWord, 1, true) ~= nil end,
				Hit = function() return nil end, SharedOn = function() return true end, WordsOf = ns.Filter.WordsOf }
			c.Authority = { Enforced = function() return false end }
			c.TabardsV2 = { SurfaceVisible = function() return false end }
			c.ViewAs = { Available = function() return false end }
			c.Consent = { Register = function() end, Ask = function() end }
			c.Comm = {
				Handle = function(kind, f) cl.handlers[kind] = f end,
				DeliveredLogged = function() return w.deliveredLogged ~= false end,
				QueueRoom = function() return 60 end, ChannelReady = function() return true end, ChatRoom = function() return 10 end,
				ChannelName = function() return "OlympusChannel" end, Audience = function() return "everyone" end,
				IsPublic = function() return true end, DropLine = function() end, PeerCount = function() return 1 end,
				CancelQueued = function() return 0 end,
				Send = function(dist, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = dist, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
				SendChat = function(msg, done, line, guard)
					w.wire[#w.wire + 1] = { from = cl, dist = "CHANNEL", msg = msg, logged = true, done = done, guard = guard }
					return true
				end,
				Whisper = function(target, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = "WHISPER", target = target, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
			}
			w.clients[#w.clients + 1] = cl
			w.As(cl, function()
				assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/Channels.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", c)
			end)
			cl.W, cl.C, cl.R, cl.WC = c.Watch, c.Channels, c.ChatRooms, c.WatchChat
			c.Watch.ResetForTests()
			c.WatchChat.ResetForTests()
			c.WatchChat.random = function() return 0 end
			return cl
		end

		-- The prefix a client's handler answers to ("MD", "M1", "M2").
		local function Deliver(r, job)
			local kind = job.msg:match("^(%w%w)~")
			local h = kind and r.handlers[kind]
			if not h or not r.online then return end
			w.deliveredLogged = job.logged == true
			w.As(r, h, job.dist, job.from.name, job.msg)
			w.deliveredLogged = nil
		end

		-- Everything queued leaves, in order (what it queues on the way too), and timers due run.
		function w.Run()
			local guard = 0
			while true do
				for _, cl in ipairs(w.clients) do
					for i = #cl.timers, 1, -1 do
						local t = cl.timers[i]
						if t.at <= w.epoch then table.remove(cl.timers, i); w.As(cl, t.fn) end
					end
				end
				local job = table.remove(w.wire, 1)
				if not job then return end
				guard = guard + 1
				assert(guard < 2000, "the world's wire never empties")
				local allowed = true
				if job.guard then allowed = w.As(job.from, job.guard) and true or false end
				if allowed and job.options and job.options.permit then
					allowed = w.As(job.from, job.options.permit, job.options.owner, job.options.key, job.dist, job.target, job.msg) == true
				end
				if job.done then w.As(job.from, job.done, allowed, allowed and nil or "guard") end
				if allowed then
					w.sent[#w.sent + 1] = { from = job.from.name, dist = job.dist, msg = job.msg, target = job.target }
					for _, r in ipairs(w.clients) do
						if r ~= job.from and ((job.dist == "CHANNEL")
							or (job.dist == "GUILD" and r.guild ~= nil and r.guild == job.from.guild)
							or (job.dist == "WHISPER" and Fold(r.name) == Fold(Full(job.target)))) then
							Deliver(r, job)
						end
					end
				end
			end
		end

		-- A message written by hand, as the server stamps `from` on it.
		function w.Inject(dist, from, to, msg, logged)
			w.deliveredLogged = logged ~= false
			-- (The module's own receiver, for its answer: the registered handler returns nothing.)
			local kind = msg:match("^(%w%w)~")
			local h = kind == "MD" and to.WC.Handle or kind == "M1" and to.C.Receive or kind == "M2" and to.R.Receive or to.handlers[kind or ""]
			local res = { w.As(to, h, dist, from, msg) }
			w.deliveredLogged = nil
			return unpack(res)
		end

		-- A line said in an Olympus chat, sent and delivered; returns the id it went with.
		function w.Say(cl, tier, text)
			w.epoch = w.epoch + 2
			local ok, why = w.As(cl, cl.C.Send, tier, text)
			assert(ok, "sent: " .. tostring(why))
			local msg = w.wire[#w.wire] and w.wire[#w.wire].msg
			w.Run()
			return tonumber(msg and msg:match("^M1~%a~[^~]*~(%d+)~"))
		end
		function w.Room(cl, text)
			w.epoch = w.epoch + 6
			local ok, why = w.As(cl, cl.R.Send, "guild", text)
			assert(ok, "sent to the room: " .. tostring(why))
			w.Run()
		end

		-- The line of `sender` with these words in a client's history of `tier` (nil when none).
		function w.Line(cl, tier, sender, text)
			for _, e in ipairs(cl.C.RawHistory(tier)) do
				if Fold(e.sender) == Fold(Full(sender)) and (text == nil or e.text == text) then return e end
			end
		end
		function w.Lines(cl, tier, sender)
			local out = {}
			for _, e in ipairs(cl.C.RawHistory(tier)) do if Fold(e.sender) == Fold(Full(sender)) then out[#out + 1] = e end end
			return out
		end
		function w.Dialog(cl, which)
			for i = #cl.dialogs, 1, -1 do if cl.dialogs[i].which == which then return cl.dialogs[i] end end
		end
		function w.Printed(cl, needle)
			for _, p in ipairs(cl.prints) do if p:find(needle, 1, true) then return p end end
		end
		function w.Sent(prefix)
			local out = {}
			for _, s in ipairs(w.sent) do if s.msg:sub(1, #prefix) == prefix then out[#out + 1] = s end end
			return out
		end

		fn(w)
	end)
	for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	for k in pairs(SlashCmdList) do SlashCmdList[k] = nil end
	for k, v in pairs(slash) do SlashCmdList[k] = v end
	if not ok then error(err, 0) end
end

-- Guild X: an officer (A), a member (B), another member (D) and its guild master (G); guild Y: a
-- member (Y1). The author, the King and a councillor are named but play only where a test says.
local X, Y = "Olympus II", "Olympus of Ash"
local function Standard(w)
	local G = w.Client("Grandmaster", X, 0)
	local A = w.Client("Officer", X, 1)
	local B = w.Client("Member", X, 3)
	local D = w.Client("Other", X, 3)
	local Y1 = w.Client("Stranger", Y, 3)
	return G, A, B, D, Y1
end

---------------------------------------------------------------------------
-- Deleting
---------------------------------------------------------------------------

test("watch: chat moderation: one line is deleted on every client: the Chat tab's history, the target's own, abroad through his own word; never relayed again", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local id = w.Say(B, "A", "first rude line")
		w.Say(B, "A", "a fine line")
		for _, cl in ipairs({ G, A, B, D, Y1 }) do assert(w.Line(cl, "A", B.name, "first rude line"), "kept on " .. cl.short) end
		local lineOnA = w.Line(A, "A", B.name, "first rude line")
		eq(lineOnA.id, id, "the line's id is kept with it (1.1.6)")
		-- A, an officer of B's guild, deletes it from his Chat tab.
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA), true, "A may act on B's line")
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA, "A"), true, "in an army chat")
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA, "craft:abc123"), false, "a provider's room is the seam: not yet")
		local ok, scope = w.As(A, A.WC.Delete, "A", lineOnA, "rude")
		eq(ok, true); eq(scope, "G", "a Watcher acts in his guild's scope")
		local beforeLines = 0
		for _, cl in ipairs({ D, Y1 }) do for _, e in ipairs(cl.events) do if e[1] == "CHAT_LINE" then beforeLines = beforeLines + 1 end end end
		w.Run()
		-- Over GUILD to X; the target's own client withdraws it on the channel (S): Y1 too.
		eq(#w.Sent("MD~1~D~G~"), 1, "one action, over guild")
		eq(w.Sent("MD~1~D~G~")[1].dist, "GUILD")
		local s = w.Sent("MD~1~S~D~")
		eq(#s, 1, "the target's own word"); eq(s[1].from, B.name); eq(s[1].dist, "CHANNEL")
		for _, cl in ipairs({ G, A, B, D, Y1 }) do
			local e
			for _, x in ipairs(cl.C.RawHistory("A")) do if x.id == id and Fold(x.sender) == Fold(B.name) then e = x end end
			assert(e, "still there, as a deleted line, on " .. cl.short)
			eq(e.del, true, "deleted on " .. cl.short); eq(e.text, "", "its words gone on " .. cl.short)
			assert(w.Line(cl, "A", B.name, "a fine line"), "his other line stays on " .. cl.short)
		end
		-- Not relayed again: no new CHAT_LINE anywhere (a companion hears nothing more), and a late
		-- copy of it is dropped.
		local after = 0
		for _, cl in ipairs({ D, Y1 }) do for _, e in ipairs(cl.events) do if e[1] == "CHAT_LINE" then after = after + 1 end end end
		eq(after, beforeLines, "nothing more to a companion")
		local late = ns.Codec.EncodeChat("A", X, id, "", "first rude line")
		local shown, why = w.Inject("CHANNEL", B.name, D, late)
		eq(why, "dup", "heard twice within two minutes: the duplicate check drops it first")
		w.epoch = w.epoch + 121 -- (past Channels' DEDUPE_WINDOW: only the tombstone knows it now)
		shown, why = w.Inject("CHANNEL", B.name, D, late)
		eq(shown, false); eq(why, "deleted", "a late copy is dropped")
		shown, why = w.Inject("CHANNEL", B.name, Y1, late)
		eq(why, "deleted", "abroad too")
		-- B was told, by role, never the officer's name.
		local told = w.Printed(B, ns.L.WATCHCHAT_ROLE_G)
		assert(told and not told:find("Officer", 1, true), tostring(told))
	end)
end)

test("watch: chat moderation: a long line's parts go together, another sender's look-alike stays", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		-- A line longer than one message goes in two parts (Codec.SplitChat), each with its id.
		local long = string.rep("word ", 60) .. "end"
		w.Say(B, "A", long)
		local parts = w.Lines(A, "A", B.name)
		eq(#parts, 2, "two parts")
		w.Say(B, "A", "a short one after")
		w.Say(D, "A", parts[1].text)
		local refs = w.As(A, A.WC.RefsFor, "A", parts[2])
		eq(#refs, 2, "from its last part: both parts, not the short line after")
		assert(w.As(A, A.WC.Delete, "A", parts[2], ""))
		w.Run()
		local onD = w.Lines(D, "A", B.name)
		eq(onD[1].del, true); eq(onD[2].del, true)
		eq(onD[3].del, nil, "his next short line stays")
		eq(w.Line(D, "A", D.name).del, nil, "D's own line with the same words stays")
	end)
end)

test("watch: chat moderation: his recent lines go on every surface (the three chats; the guild room is the game's own guild chat since 1.2.0); one heard later never takes a newer line", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "old one")
		local oldLine = w.Line(A, "A", B.name, "old one")
		for _, cl in ipairs({ G, A, D }) do local e = w.Line(cl, "A", B.name, "old one") e.t = e.t - 2 * 86400 end
		w.Say(B, "A", "recent one")
		w.Say(B, "A", "recent two")
		w.Say(D, "A", "someone else")
		assert(w.As(A, A.WC.Purge, B.name, "spam"))
		w.Run()
		for _, cl in ipairs({ G, A, D }) do
			eq(w.Line(cl, "A", B.name, "old one") ~= nil, true, "older than a day: stays on " .. cl.short)
			for _, e in ipairs(w.Lines(cl, "A", B.name)) do
				if e ~= w.Line(cl, "A", B.name, "old one") then eq(e.del, true, "deleted on " .. cl.short) end
			end
			eq(w.Line(cl, "A", D.name, "someone else").del, nil, "another sender's stays on " .. cl.short)
		end
		-- A line of his still in flight (sent before, heard within the grace) is dropped; one after shows.
		local inFlight = ns.Codec.EncodeChat("A", X, 4321, "", "sent before the purge")
		local _, why = w.Inject("CHANNEL", B.name, D, inFlight)
		eq(why, "deleted", "in flight")
		w.epoch = w.epoch + 31
		w.Say(B, "A", "after the purge")
		eq(w.Line(D, "A", B.name, "after the purge").del, nil, "his next line shows")
		-- The officer's client repeats it for clients that were away: one heard now takes only what
		-- was written before it.
		local P = w.Sent("MD~1~P~G~")[1].msg
		local late = w.Client("Late", X, 3)
		local list = w.As(late, late.C.RawHistory, "A")
		list[#list + 1] = { t = w.epoch - 40, sender = B.name, guild = X, text = "kept while away", id = 77 }
		list[#list + 1] = { t = w.epoch, sender = B.name, guild = X, text = "after the purge", id = 78 }
		w.Inject("GUILD", A.name, late, P)
		eq(w.Line(late, "A", B.name, "kept while away"), nil, "the line it kept while away is deleted")
		assert(w.Line(late, "A", B.name, "after the purge"), "his later line is not")
		eq(oldLine.del, nil)
	end)
end)

test("watch: chat moderation: late joiners never get the words; one away within two hours gets the repeat, after that its copy stays (the stated limit)", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "say it once")
		D.online = false
		local e = w.Line(A, "A", B.name, "say it once")
		assert(w.As(A, A.WC.Delete, "A", e, ""))
		w.Run()
		eq(w.Line(D, "A", B.name, "say it once").del, nil, "away: not yet")
		-- A new client: there is no backlog in Olympus, nothing to receive.
		local new = w.Client("Newcomer", X, 3)
		eq(#w.As(new, new.C.RawHistory, "A"), 0, "a late joiner has no copy of it")
		-- D back within the repeat window: the officer's client repeats it (DELETE_REPEAT_EVERY).
		D.online = true
		w.epoch = w.epoch + A.WC.DELETE_REPEAT_EVERY
		w.As(A, A.WC.Tick)
		w.Run()
		eq(w.Line(D, "A", B.name).del, true, "replaced in the history D kept")
		-- Past DELETE_REPEAT_FOR the actor's client stops repeating it.
		w.epoch = w.epoch + A.WC.DELETE_REPEAT_FOR + 1
		local before = #w.Sent("MD~1~D~")
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#w.Sent("MD~1~D~"), before, "no repeat past two hours")
	end)
end)

test("watch: chat moderation: from a report: a case's evidence line is found by its words on clients that never shared an id", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "reported words here")
		-- (History saved before 1.1.6 has no ids: D's copy loses its id.)
		w.Line(D, "A", B.name, "reported words here").id = nil
		local evidence = w.As(A, A.W.Evidence, B.name)
		eq(#evidence, 1)
		assert(w.As(A, A.WC.DeleteReported, B.name, evidence, "reported"))
		w.Run()
		eq(w.Line(D, "A", B.name).del, true, "deleted by its words")
		eq(#w.As(A, A.W.Evidence, B.name), 0, "a deleted line is never evidence again")
	end)
end)

test("watch: chat moderation: the game's chat window: the printed line replaced on its frame, never a look-alike, the combat log, Chattynator, a secret, with the switch off or under the gamepad UI", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "printed line")
		w.Say(D, "A", "printed line")
		local function Text(cl, i) return cl.frame.lines[i] and cl.frame.lines[i].message end
		local n = #Y1.frame.lines
		assert(Text(Y1, n - 1):find("printed line", 1, true))
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "printed line"), ""))
		w.Run()
		assert(Text(Y1, n - 1):find(ns.L.WATCHCHAT_DELETED, 1, true), Text(Y1, n - 1))
		assert(not Text(Y1, n - 1):find("printed line", 1, true), "the words are gone from the game's window")
		assert(Text(Y1, n - 1):find("|Hplayer:", 1, true), "the name stays a player link")
		assert(Text(Y1, n):find("printed line", 1, true), "D's look-alike stays")
		-- The combat log, a Chattynator tab: never asked.
		local combat = Frame({ combat = true })
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 900, "x", combat, "line", "gone")
		w.As(D, D.WC.ReplacePrinted, "A", B.name, 900, D.WC.Hash("x"))
		eq(combat.calls, 0, "never the combat log")
		-- A secret value is skipped without error.
		local f = Frame()
		f:AddMessage("secret", 1, 1, 1)
		w.secret = "secret"
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 901, "y", f, "secret", "gone")
		w.As(D, D.WC.ReplacePrinted, "A", B.name, 901, D.WC.Hash("y"))
		eq(f.lines[1].message, "secret", "a secret is never compared or changed")
		w.secret = nil
		-- The kill switch and the gamepad UI: nothing of the game's is touched.
		local g = Frame()
		g:AddMessage("line", 1, 1, 1)
		D.WC.GAME_CHAT = false
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 902, "z", g, "line", "gone")
		eq(w.As(D, D.WC.ReplacePrinted, "A", B.name, 902, D.WC.Hash("z")), 0)
		D.WC.GAME_CHAT = true
		w.gamepad = true
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 903, "z", g, "line", "gone")
		eq(w.As(D, D.WC.ReplacePrinted, "A", B.name, 903, D.WC.Hash("z")), 0)
		eq(g.calls, 0, "under the gamepad UI, never")
		w.gamepad = nil
		-- The code says so where it is read.
		local src = assert(io.open(ROOT .. "Olympus/WatchChat.lua", "rb")):read("*a")
		assert(src:find("the game's chat window keeps what it already showed", 1, true))
		assert(not src:find("StaticPopup_Show", 1, true), "every dialog goes through ns.ShowDialog")
	end)
end)

---------------------------------------------------------------------------
-- Timeouts
---------------------------------------------------------------------------

test("watch: chat moderation: a timeout drops his lines on every client; his own client refuses and tells him the role, until when and why, once a minute", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local ok, scope = w.As(A, A.WC.Timeout, B.name, 1800, "spam")
		eq(ok, true); eq(scope, "G")
		w.Run()
		-- B's own client: the pop-up names the role, never the officer.
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(d, "told in an Olympus pop-up")
		assert(d.a:find(ns.L.WATCHCHAT_ROLE_G, 1, true), d.a)
		assert(d.a:find("spam", 1, true) and d.a:find(date("%H:%M", w.epoch + 1800), 1, true), d.a)
		assert(not d.a:find("Officer", 1, true), "never the name")
		-- He cannot send: Channels and the rooms refuse, nothing is queued.
		local dialogs = #B.dialogs
		local wire = #w.wire
		eq(select(2, w.As(B, B.C.Send, "A", "let me talk")), "timeout")
		eq(select(2, w.As(B, B.R.Send, "guild", "let me talk")), "timeout")
		eq(#w.wire, wire, "nothing queued")
		eq(#B.dialogs, dialogs, "the pop-up again only once a minute: a line in between")
		assert(w.Printed(B, date("%H:%M", w.epoch + 1800)))
		w.epoch = w.epoch + 61
		w.As(B, B.C.Send, "A", "again")
		eq(#B.dialogs, dialogs + 1, "a minute later, the pop-up again")
		-- Abroad (Y1) through his own word on the channel; his guildmates through the action.
		local line = ns.Codec.EncodeChat("A", X, 55, "", "a line from a modified client")
		for _, cl in ipairs({ G, A, D, Y1 }) do
			local _, why = w.Inject("CHANNEL", B.name, cl, line)
			eq(why, "timeout", "dropped on " .. cl.short)
		end
		local room = ("M2~1~guild~12~~%s~in the room"):format(X)
		local _, why = w.Inject("GUILD", B.name, D, room)
		eq(why, "timeout", "a room's line too")
		-- Others still show.
		w.Say(D, "A", "still here")
		assert(w.Line(Y1, "A", D.name, "still here"))
	end)
end)

test("watch: chat moderation: a part still queued when the timeout comes never leaves; a linked alt is covered", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.epoch = w.epoch + 2
		assert(w.As(B, B.C.Send, "A", "queued before"))
		local queued = table.remove(w.wire) -- held back: the timeout comes first
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		w.wire[#w.wire + 1] = queued
		w.Run()
		eq(#w.Sent("M1~"), 0, "the part never left")
		-- A name his player linked (confirmed on both): covered too.
		w.links[Fold(B.name)] = { "Memberalt-Realm" }
		w.links[Fold("Memberalt-Realm")] = { B.name }
		w.SetRank("Memberalt", Y, 3)
		local _, why = w.Inject("CHANNEL", "Memberalt-Realm", D, ns.Codec.EncodeChat("A", Y, 66, "", "from the alt"))
		eq(why, "timeout")
	end)
end)

test("watch: chat moderation: expiry and early lift; a Watcher's lift never lifts a council timeout; a late repeat of a lifted one stays lifted; until-lifted lapses after 30 days", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		local T = w.Sent("MD~1~T~G~")[1].msg
		eq(w.As(D, D.WC.Silenced, B.name), true)
		w.epoch = w.epoch + 301
		eq(w.As(D, D.WC.Silenced, B.name), false, "a second after its end")
		eq(w.As(B, B.WC.SelfTimeout), nil)
		-- An early lift by another Watcher of the guild (G).
		assert(w.As(A, A.WC.Timeout, B.name, 1800, ""))
		w.Run()
		local T2 = w.Sent("MD~1~T~G~")
		T2 = T2[#T2].msg
		eq(w.As(B, B.WC.SelfTimeout) ~= nil, true)
		w.epoch = w.epoch + 5
		assert(w.As(G, G.WC.Lift, B.name, "sorry"))
		w.Run()
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted")
		eq(w.As(D, D.WC.Silenced, B.name), false)
		assert(w.Printed(B, ns.L.WATCHCHAT_LIFTED_YOU:format(ns.L.WATCHCHAT_ROLE_G)))
		-- A late repeat of the lifted one does not bring it back.
		w.Inject("GUILD", A.name, D, T2)
		eq(w.As(D, D.WC.Silenced, B.name), false, "a late repeat stays lifted")
		-- The author's timeout, and a Watcher's lift.
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(Au, Au.WC.Timeout, B.name, 0, "while his case is decided"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true)
		local okLift, whyLift = w.As(A, A.WC.Lift, B.name, "")
		eq(okLift, false); eq(whyLift, "rank", "a Watcher never lifts the author's")
		eq(w.As(B, B.WC.SelfTimeout).untilAt, 0, "until lifted")
		w.epoch = w.epoch + B.WC.HOLD_MAX + 1
		eq(w.As(B, B.WC.SelfTimeout), nil, "until lifted lapses after 30 days")
		eq(T ~= nil, true)
	end)
end)

test("watch: chat moderation: the giver repeats a timeout for late logins; another Watcher passes it on while both qualify, never once the giver is demoted", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, ""))
		w.Run()
		local n = #w.Sent("MD~1~T~G~")
		w.epoch = w.epoch + A.WC.REPEAT
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#w.Sent("MD~1~T~G~"), n + 1, "repeated every REPEAT (plus its own jitter)")
		-- A goes quiet; G (a Watcher too) passes it on with by = A.
		A.online = false
		w.epoch = w.epoch + G.WC.PASS_ON_AFTER + 1
		w.As(G, G.WC.Tick)
		w.Run()
		local passed = w.Sent("MD~1~T~G~")
		passed = passed[#passed]
		eq(passed.from, G.name)
		assert(passed.msg:find("~" .. A.name .. "~", 1, true), "by: the original actor")
		-- A late login hears it.
		local late = w.Client("Latecomer", X, 3)
		w.Inject("GUILD", G.name, late, passed.msg)
		eq(w.As(late, late.WC.Silenced, B.name), true)
		-- A demoted: G's pass-on is refused.
		local later = w.Client("Later", X, 3)
		w.SetRank(A.name, X, 3)
		local ok, why = w.Inject("GUILD", G.name, later, passed.msg)
		eq(ok, false); eq(why, "actor", "the original actor no longer qualifies")
	end)
end)

---------------------------------------------------------------------------
-- Who may act
---------------------------------------------------------------------------

test("watch: chat moderation: a Watcher only in his own guild: over GUILD, on a member of the receiver's roster, the guild named his own", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local okY, whyY = w.As(A, A.WC.Timeout, Y1.name, 300, "")
		eq(okY, false, "a Watcher never acts on another guild's member")
		-- Forged by hand.
		local function Wire(scope, guild, target)
			return ("MD~1~T~%s~%d~%d~%s~%s~%d~-~-~"):format(scope, 900, w.epoch, guild, target, w.epoch + 300)
		end
		local ok, why = w.Inject("CHANNEL", A.name, Y1, Wire("G", X, Y1.name))
		eq(why, "lane", "a guild action never on the channel")
		ok, why = w.Inject("GUILD", A.name, D, Wire("G", Y, B.name))
		eq(why, "guild", "not the receiver's guild")
		ok, why = w.Inject("GUILD", A.name, D, Wire("G", X, "Nobody-Realm"))
		eq(why, "member", "not in the receiver's roster")
		ok, why = w.Inject("GUILD", A.name, D, Wire("O", X, B.name))
		eq(why, "lane", "an Olympus action never over guild")
		ok = w.Inject("GUILD", A.name, D, Wire("G", X, B.name))
		eq(ok, true, "his own guild's member")
	end)
end)

test("watch: chat moderation: the council, the King and the author anywhere; never upward, never on himself, never through a linked alt, never while sanctioned", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.author, w.king = "Author-Realm", "Kingly-Realm"
		w.council[Fold("Councillor-Realm")] = true
		w.council[Fold("Peer-Realm")] = true
		w.stewards[Fold("Steward-Realm")] = true
		w.hands[Fold("Hand-Realm")] = true
		local K = w.Client("Kingly", "Olympus", 0)
		local Co = w.Client("Councillor", Y, 3)
		local Au = w.Client("Author", Y, 2)
		local Pe = w.Client("Peer", X, 3)
		local St = w.Client("Steward", "Olympus", 2)
		local Ha = w.Client("Hand", Y, 3)
		local function May(actor, target)
			local scope = w.As(actor, actor.WC.CanModerate, target)
			return scope
		end
		-- Anywhere: the councillor (guild Y) on B (guild X), the King, the author.
		eq(May(Co, B.name), "O"); eq(May(K, B.name), "O"); eq(May(Au, B.name), "O")
		eq(May(Co, G.name), "O", "a councillor on a guild master")
		-- Never upward or across.
		eq(May(Co, Pe.name), nil, "councillor on councillor")
		eq(May(Co, Ha.name), nil, "councillor on a Hand")
		eq(May(Co, St.name), nil, "councillor on a Steward")
		eq(May(Co, K.name), nil, "councillor on the King")
		eq(May(K, Au.name), nil, "the King on the author")
		eq(May(Au, K.name), "O", "the author on the King")
		eq(May(Co, Co.name), nil, "on himself")
		eq(May(A, G.name), nil, "a Watcher on the guild master")
		w.SetRank("Officer2", X, 1)
		eq(May(A, "Officer2-Realm"), nil, "an officer on an officer of his rank")
		-- Through a linked alt: B's alt is a councillor.
		w.links[Fold(D.name)] = { "Peer-Realm" }
		eq(May(A, D.name), nil, "a protected player through his linked alt")
		w.links[Fold(D.name)] = nil
		-- Sanctioned: a net-off'd councillor gives nothing, and his client sends no MD (BLOCKED).
		w.off[Fold(Co.name)] = { by = "x" }
		eq(May(Co, B.name), nil)
		w.off[Fold(Co.name)] = nil
		local src = assert(io.open(ROOT .. "Olympus/Moderation.lua", "rb")):read("*a")
		assert(src:find("MW = true, MR = true, MD = true", 1, true), "Moderation.BLOCKED.MD")
		-- An Olympus-scope action by the councillor reaches every guild.
		assert(w.As(Co, Co.WC.Timeout, B.name, 300, "flood"))
		w.Run()
		for _, cl in ipairs({ G, A, D, Y1 }) do eq(w.As(cl, cl.WC.Silenced, B.name), true, "on " .. cl.short) end
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(d.a:find(ns.L.WATCHCHAT_ROLE_4, 1, true), d.a)
	end)
end)

test("watch: chat moderation: forged and malformed actions are refused; a replay is applied once; a flood is cut", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local function Wire(op, arg, refs, by, at, reason)
			return ("MD~1~%s~G~%d~%d~%s~%s~%s~%s~%s~%s"):format(op, 777, at or w.epoch, X, B.name, arg or "-", refs or "-", by or "-", reason or "")
		end
		-- The stamped sender is no Watcher.
		local ok, why = w.Inject("GUILD", D.name, G, Wire("T", w.epoch + 300))
		eq(why, "actor")
		-- by names someone who could not give it.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300, "-", D.name))
		eq(why, "actor", "the original actor no Watcher")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", "A.1." .. G.WC.Hash("x"), D.name))
		eq(why, "by", "a deletion is never passed on")
		-- Unlogged; oversized; malformed refs; more than 3 refs.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300), false)
		eq(why, "unlogged")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300) .. string.rep("x", 255))
		eq(why, "size")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", "A.1.zz"))
		eq(why, "refs")
		local h = G.WC.Hash("x")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", ("A.1.%s,A.2.%s,A.3.%s,A.4.%s"):format(h, h, h, h)))
		eq(why, "refs", "4 refs")
		-- Durations: untilAt at or before at, past the 7 days; at more than 60 s ahead.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch))
		eq(why, "duration")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + G.WC.MAX_TIMEOUT + 1))
		eq(why, "duration", "past the ladder's 7 days")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 400, "-", "-", w.epoch + 61))
		eq(why, "time")
		-- A reason that is not clean.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300, "-", "-", nil, "a|cffff0000red"))
		eq(why, "reason")
		-- A target's own word naming someone else's line touches his own lines alone.
		w.Say(D, "A", "D's own words")
		local S = ("MD~1~S~D~5~%d~%s~%s~-~A.-.%s~"):format(w.epoch, X, A.name, G.WC.Hash("D's own words"))
		w.Inject("CHANNEL", B.name, Y1, S)
		eq(w.Line(Y1, "A", D.name, "D's own words").del, nil, "B can never withdraw D's line")
		-- A replay applies once.
		local good = Wire("T", w.epoch + 300)
		eq(w.Inject("GUILD", A.name, G, good), true)
		local _, again = w.Inject("GUILD", A.name, G, good)
		eq(again, "repeat")
		-- More than 10 a minute from one sender: dropped.
		local dropped = 0
		for i = 1, 12 do
			local _, r = w.Inject("GUILD", A.name, D, ("MD~1~T~G~%d~%d~%s~%s~%d~-~-~"):format(1000 + i, w.epoch, X, B.name, w.epoch + 300))
			if r == "rate" then dropped = dropped + 1 end
		end
		assert(dropped >= 1, "rate-limited")
	end)
end)

---------------------------------------------------------------------------
-- Watchers and Olympus moderators
---------------------------------------------------------------------------

test("watch: chat moderation: the guild master names and removes Watchers; only his list counts, while he is the guild master", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "a member is no Watcher")
		local ok, why = w.As(A, A.WC.SetWatcher, B.name, true)
		eq(ok, false); eq(why, "gm", "an officer names nobody")
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		local Wmsg = w.Sent("MD~1~W~")
		eq(#Wmsg, 1); eq(Wmsg[1].dist, "GUILD")
		eq(w.As(D, D.W.IsAuthorized, B.name), true, "a named Watcher has The Watch")
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), true)
		-- He acts on a member below him, never on an officer.
		eq(w.As(B, B.WC.CanModerate, D.name), "G")
		eq(w.As(B, B.WC.CanModerate, A.name), nil, "a named Watcher never on an officer")
		-- An officer relaying the list: refused.
		local relay = Wmsg[1].msg
		local _, rwhy = w.Inject("GUILD", A.name, D, relay)
		eq(rwhy, "rank", "only the guild master's own client")
		-- More than 10: refused.
		local names = {}
		for i = 1, 11 do names[i] = "Name" .. i .. "-Realm" end
		local _, fwhy = w.Inject("GUILD", G.name, D, ("MD~1~W~%d~%s~1~1~-~%s"):format(w.epoch + 1, X, table.concat(names, ",")))
		eq(fwhy, "full")
		-- Removed: the newer list without him.
		assert(w.As(G, G.WC.SetWatcher, B.name, false))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "removed")
		-- A new guild master: the old list counts for nobody.
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), true)
		w.SetRank(G.name, X, 1); w.SetRank(A.name, X, 0)
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), false, "rank 0 is another character now")
		w.SetRank(A.name, X, 1); w.SetRank(G.name, X, 0)
		-- He leaves the guild: no Watcher.
		w.SetRank(B.name, Y, 3)
		eq(w.As(D, D.WC.CanModerate, D.name), nil)
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "out of the roster")
		-- The Justice correspondent counts as a Watcher, and applies the King's judgment.
		w.SetRank(B.name, X, 3)
		assert(w.As(G, G.WC.SetWatcher, D.name, true, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(A, A.WC.Justice), D.name)
		eq(w.As(A, A.W.IsAuthorized, D.name), true)
		eq(w.As(D, D.WC.MayApplyJudgment), true)
		eq(w.As(A, A.WC.MayApplyJudgment), false, "another officer does not")
	end)
end)

test("watch: chat moderation: Olympus moderators: a councillor's list counts while fresh and while he is a councillor; never another's list", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(#w.Sent("MD~1~O~"), 1)
		eq(w.As(D, D.WC.IsMod, Mo.name), true)
		eq(w.As(Mo, Mo.WC.CanModerate, B.name), "O", "anywhere")
		eq(w.As(Mo, Mo.WC.CanModerate, G.name), nil, "never on a guild master")
		eq(w.As(Mo, Mo.WC.CanModerate, Co.name), nil, "never on his namer")
		-- A namer never changes another's list: Y1's word for Mo's list is not a namer's.
		local _, why = w.Inject("CHANNEL", Y1.name, D, ("MD~1~O~%d~1~1~"):format(w.epoch + 5))
		eq(why, "namer")
		eq(w.As(D, D.WC.IsMod, Mo.name), true)
		-- Lapses 20 minutes after its last repeat.
		w.epoch = w.epoch + D.WC.LIST_FRESH + 1
		eq(w.As(D, D.WC.IsMod, Mo.name), false, "stale")
		w.As(Co, Co.WC.SendMods, true)
		w.Run()
		eq(w.As(D, D.WC.IsMod, Mo.name), true, "repeated")
		-- At once when the namer leaves the council.
		w.council[Fold(Co.name)] = nil
		eq(w.As(D, D.WC.IsMod, Mo.name), false, "his title gone")
	end)
end)

---------------------------------------------------------------------------
-- Audit and records
---------------------------------------------------------------------------

test("watch: chat moderation: the audit's audience: the guild's Watch (with the words), the council's page (Olympus actions and confirmed guild ones), the player's own record by role only, nobody else", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		w.Say(B, "A", "the rude words")
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "the rude words"), "insult"))
		w.Run()
		-- The guild's Watch (G): its audit, who, whom, what, why, when, and the words.
		local found
		for _, e in ipairs(w.As(G, G.W.Audit)) do if e.op == "D" then found = e end end
		assert(found, "in The Watch's audit")
		eq(found.by, A.name); eq(found.name, B.name); eq(found.reason, "insult"); eq(found.text, "the rude words")
		-- A plain member keeps nothing of it but the deleted line.
		eq(#w.As(D, D.W.Audit), 0, "a member has no audit")
		eq(#D.WC.Store().audit, 0)
		-- The council's client: the guild action his own client confirmed (S).
		local s = Co.WC.Store()
		eq(#s.audit, 1); eq(s.audit[1].scope, "S"); eq(s.audit[1].by, A.name)
		-- The player: his own record, the role only (no name shown).
		local rec = B.WC.Store().record
		eq(#rec, 1); eq(rec[1].role, "G"); eq(rec[1].words, "the rude words")
		local lines = w.As(B, B.WC.RecordLines)
		local text = ""
		for _, l in ipairs(lines) do text = text .. l.text .. "\n" end
		assert(text:find(ns.L.WATCHCHAT_ROLE_G, 1, true) and not text:find("Officer", 1, true), text)
		-- Y1 (another guild, no council) keeps no reason.
		eq(#Y1.WC.Store().audit, 0)
		-- On the King's stream (masked) the page hides reasons and words.
		Co.masked = true
		local page = w.As(Co, Co.WC.PageLines)
		for _, l in ipairs(page) do
			if l.tooltip then
				local tt = { lines = {} }
				function tt:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
				l.tooltip(tt)
				local all = table.concat(tt.lines, "\n")
				assert(not all:find("insult", 1, true) and not all:find("the rude words", 1, true), all)
			end
		end
	end)
end)

test("watch: chat moderation: an appeal goes to the High Council; its answer lifts or keeps, and the player is told in a pop-up", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "insult"))
		w.Run()
		local r = B.WC.Store().record[1]
		-- The member's Watch page exposes only their record and its real appeal dialog.
		w.As(B, B.W.Show, "member")
		local rows = w.As(B, B.W.Build)
		local appealRow
		for _, row in ipairs(rows) do if row.tooltip and row.onClick then appealRow = row end end
		assert(appealRow, "own record has an appeal")
		w.As(B, appealRow.onClick)
		local dialog = w.Dialog(B, "OLYMPUS_WATCHCHAT_APPEAL")
		eq(dialog.data.by, r.by); eq(dialog.data.seq, r.seq)
		w.As(D, D.W.Show, "member")
		for _, row in ipairs(w.As(D, D.W.Build)) do
			assert(not (row.tooltip and row.onClick), "another member sees none of this record")
		end
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "I was quoting him"))
		w.Run()
		local key
		for k in pairs(Co.WC.Store().appeals) do key = k end
		assert(key, "kept on the councillor's client")
		eq(next(D.WC.Store().appeals), nil, "never on a member's")
		assert(w.As(Co, Co.WC.Answer, key, "L", "fair"))
		w.Run()
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted on appeal")
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		assert(d and d.a:find(ns.L.WATCHCHAT_ROLE_4, 1, true), d and d.a)
	end)
end)

test("watch: chat moderation: the King's word on a case reaches its player in a pop-up, over his guild, once", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.TellCase, B.name, 42, "U"))
		w.Run()
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		assert(d and d.a == ns.L.WATCHCHAT_DECISION_UP, d and d.a)
		eq(w.Dialog(D, "OLYMPUS_WATCHCHAT_DECISION"), nil, "only he is told")
		local n = #B.dialogs
		w.epoch = w.epoch + A.WC.DECISION_EVERY
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#B.dialogs, n, "once")
		local _, why = w.Inject("GUILD", D.name, B, ("MD~1~J~%d~%s~%s~43~D"):format(w.epoch, X, B.name))
		eq(why, "sender", "a member cannot tell him a decision")
	end)
end)

---------------------------------------------------------------------------
-- A sanction is more than the chat
---------------------------------------------------------------------------

test("watch: chat moderation: a sanction bars powers, games, locations and crafting for its window; the wallet only during a hold", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(w.As(B, B.WC.Barred, "games"), nil)
		assert(w.As(A, A.WC.Timeout, B.name, 3600, ""))
		w.Run()
		for _, what in ipairs({ "powers", "games", "locations", "crafting" }) do
			eq(w.As(B, B.WC.Barred, what) ~= nil, true, "his own client: " .. what)
			eq(w.As(D, D.WC.Barred, what, B.name) ~= nil, true, "another's client: " .. what)
		end
		eq(w.As(B, B.WC.Barred, "wallet"), nil, "a timeout freezes no wallet")
		-- A sanctioned officer loses The Watch while it lasts.
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(Au, Au.WC.Timeout, A.name, 0, "his case"))
		w.Run()
		eq(w.As(A, A.W.IsAuthorized, A.name), false, "no powers")
		eq(w.As(G, G.W.IsAuthorized, A.name), false, "on the others' clients too")
		eq(w.As(A, A.WC.Barred, "wallet") ~= nil, true, "a hold freezes the wallet")
		eq(w.As(A, A.WC.Timeout, D.name, 300, ""), false, "a sanctioned officer moderates nobody")
		-- The other modules ask the same: the King's position, a crafting card, a guildmate's dot.
		local saved = { WatchChat = rawget(ns, "WatchChat"), me = ns.me }
		local ok, err = pcall(function()
			rawset(ns, "WatchChat", D.WC)
			local s = w.As(D, ns.CraftRequests.Barred, B.name)
			eq(s ~= nil, true, "Crafting: his cards and words are dropped")
			eq(select(2, w.As(D, ns.CraftRequests.ReceiveSnapshot, "CHANNEL", B.name, "CQ~2" .. string.rep("~x", 16))), "sanction")
			eq(ns.Positions.Sanctioned(B.name), true, "his position is dropped")
		end)
		rawset(ns, "WatchChat", saved.WatchChat)
		if not ok then error(err, 0) end
		-- A net-off word counts as a sanction too (exile from the addon).
		w.off[Fold(Y1.name)] = { by = "x" }
		eq(w.As(D, D.WC.Barred, "games", Y1.name).kind, "netoff")
	end)
end)

test("watch: chat moderation: the severe-insult block: nothing is blocked while its approved list is empty; a listed word is refused at send and counted, never kept", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(next(B.WC.SEVERE), nil, "shipped empty")
		w.Say(B, "A", "a plainword here")
		assert(w.Line(D, "A", B.name, "a plainword here"))
		B.WC.SEVERE = { plainword = "slur" }
		w.epoch = w.epoch + 2
		eq(select(2, w.As(B, B.C.Send, "A", "a plainword again")), "severe")
		eq(select(2, w.As(B, B.R.Send, "guild", "a plainword again")), "severe")
		eq(#w.wire, 0, "nothing queued")
		local counts, total = w.As(B, B.WC.BlockedCounts, B.name)
		eq(counts.severe, 2); eq(total, 2)
		for _, e in pairs(B.WC.Store().blocked) do eq(e.text, nil, "never the words") end
	end)
end)

test("watch: chat moderation: the High Council's ladder: warn, 1 hour, 24 hours, 7 days; a warning's step is a real timeout", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(table.concat(A.W.TIMEOUTS, ","), "0,3600,86400,604800")
		eq(A.W.MAX_TIMEOUT, 604800)
		eq(A.WC.MAX_TIMEOUT, 604800)
		assert(w.As(A, A.W.Warn, B.name, "one"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), false, "a first warning is a warning")
		w.epoch = w.epoch + 5
		assert(w.As(A, A.W.Warn, B.name, "two"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the second: a real timeout")
		eq(w.As(B, B.WC.SelfTimeout).untilAt - w.As(B, B.WC.SelfTimeout).at, 3600)
	end)
end)

---------------------------------------------------------------------------
-- The review's findings (2026-10-05): each test fails on the code before its fix
---------------------------------------------------------------------------

test("watch: chat moderation: a timeout passed on weighs its actor's: a moderator never carries, shortens or replaces the King's, and no councillor lifts it anywhere", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.king, w.author = "Kingly-Realm", "Author-Realm"
		w.council[Fold("Councillor-Realm")] = true
		local K = w.Client("Kingly", "Olympus", 0)
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		local Au = w.Client("Author", Y, 2)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.WC.IsMod, Mo.name), true, "an Olympus moderator")
		assert(w.As(K, K.WC.Timeout, B.name, 604800, ""))
		w.Run()
		local T = w.Sent("MD~1~T~O~")[1].msg
		local seq = tonumber(T:match("^MD~1~T~O~(%d+)~"))
		eq(select(2, w.As(Mo, Mo.WC.Lift, B.name, "")), "rank", "the moderator may not lift the King's")
		-- His pass-on made up in the King's name: a newer sequence, a minute's end.
		local forged = ("MD~1~T~O~%d~%d~%s~%s~%d~-~%s~"):format(seq + 1, w.epoch, X, B.name, w.epoch + 60, K.name)
		for _, cl in ipairs({ G, D, Y1 }) do
			local ok, why = w.Inject("CHANNEL", Mo.name, cl, forged)
			eq(ok, false, "refused on " .. cl.short); eq(why, "rank", "on " .. cl.short)
		end
		w.epoch = w.epoch + 61
		for _, cl in ipairs({ G, D, Y1 }) do eq(w.As(cl, cl.WC.Silenced, B.name), true, "the King's 7 days stand on " .. cl.short) end
		local _, again = w.Inject("CHANNEL", K.name, D, T)
		eq(again, "repeat", "the King's own repeat is never refused as older")
		-- The King goes quiet: the moderator's client never passes his word on; the author's does.
		K.online = false
		w.epoch = w.epoch + Mo.WC.PASS_ON_AFTER + 1
		local before = #w.sent
		w.As(Mo, Mo.WC.Tick)
		w.Run()
		for i = before + 1, #w.sent do
			assert(not (w.sent[i].from == Mo.name and w.sent[i].msg:find("^MD~1~T~")), "the moderator carried it: " .. w.sent[i].msg)
		end
		w.As(Au, Au.WC.Tick)
		w.Run()
		local passed
		for i = before + 1, #w.sent do
			if w.sent[i].from == Au.name and w.sent[i].msg:find("^MD~1~T~O~") then passed = w.sent[i].msg end
		end
		assert(passed and passed:find("~" .. K.name .. "~", 1, true), "the author carries the King's word")
		-- A councillor whose client hears it only that way holds it with the King's weight: his lift
		-- is refused there as everywhere.
		local Late = w.Client("Latecouncil", Y, 3)
		w.council[Fold(Late.name)] = true
		eq(w.Inject("CHANNEL", Au.name, Late, passed), true)
		eq(w.As(Late, Late.WC.TimeoutOf, B.name).weight, 6, "the King's weight, however it came")
		eq(select(2, w.As(Late, Late.WC.Lift, B.name, "")), "rank")
	end)
end)

test("watch: chat moderation: an appeal's lift reaches a timeout the councillor's client never held; the player is never told lifted while still timed out", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "insult"))
		w.Run()
		-- The councillor logs in later: his client never heard it (B's own word went once).
		local Co = w.Client("Councillor", Y, 3)
		eq(w.As(Co, Co.WC.TimeoutOf, B.name), nil)
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "I was quoting him"))
		w.Run()
		local key
		for k in pairs(Co.WC.Store().appeals) do key = k end
		assert(key, "the appeal reached him")
		local lifts = #w.Sent("MD~1~U~O~")
		assert(w.As(Co, Co.WC.Answer, key, "L", "fair"))
		w.Run()
		eq(#w.Sent("MD~1~U~O~"), lifts + 1, "his lift went out")
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted on the player's own client")
		eq(w.As(D, D.WC.Silenced, B.name), false, "and on his guildmates'")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a,
			ns.L.WATCHCHAT_APPEAL_LIFTED_YOU:format(ns.L.WATCHCHAT_ROLE_4, ns.L.WATCHCHAT_REASON_PART:format("fair")))
		-- One from higher up (the King's, which the councillor's client never heard): his lift
		-- does not reach it, and the player is told so.
		w.king = "Kingly-Realm"
		local K = w.Client("Kingly", "Olympus", 0)
		Co.online = false
		w.epoch = w.epoch + 5
		assert(w.As(K, K.WC.Timeout, B.name, 3600, ""))
		w.Run()
		Co.online = true
		local rec = B.WC.Store().record
		local r2 = rec[#rec]
		eq(r2.by, K.name)
		assert(w.As(B, B.WC.Appeal, r2.by, r2.seq, "again"))
		w.Run()
		local key2
		for k, e in pairs(Co.WC.Store().appeals) do if e.seq == r2.seq then key2 = k end end
		assert(w.As(Co, Co.WC.Answer, key2, "L", ""))
		w.Run()
		local still = w.As(B, B.WC.SelfTimeout)
		assert(still and still.by == K.name, "still timed out by the King")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a,
			ns.L.WATCHCHAT_APPEAL_LIFTED_STILL:format(ns.L.WATCHCHAT_ROLE_4, "", w.As(B, B.WC.TimeoutText, still)))
		-- An appeal on a deleted line: "found for him", never a lift of anything.
		assert(w.As(K, K.WC.Lift, B.name, ""))
		w.Run()
		w.Say(B, "A", "a deleted one")
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "a deleted one"), ""))
		w.Run()
		local r3 = rec[#rec]
		eq(r3.op, "D")
		w.epoch = w.epoch + 61 -- (two appeals a minute from one player at most)
		assert(w.As(B, B.WC.Appeal, r3.by, r3.seq, "it was a joke"))
		w.Run()
		local key3
		for k, e in pairs(Co.WC.Store().appeals) do if e.seq == r3.seq then key3 = k end end
		local n = #w.Sent("MD~1~U~")
		assert(w.As(Co, Co.WC.Answer, key3, "L", ""))
		w.Run()
		eq(#w.Sent("MD~1~U~"), n, "no lift for a deleted line")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, ns.L.WATCHCHAT_APPEAL_GRANTED_YOU:format(ns.L.WATCHCHAT_ROLE_4, ""))
	end)
end)

test("watch: chat moderation: the desk's reason stays the desk's: the ladder's timeout goes without it, and the player's own word on the channel never carries a reason", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local private = "reported by Other for harassment"
		assert(w.As(A, A.W.Warn, B.name, private))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(A, A.W.Warn, B.name, private))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the step's timeout")
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true, "abroad too, through his own word")
		for _, s in ipairs(w.sent) do
			if s.dist == "GUILD" or s.dist == "CHANNEL" then assert(not s.msg:find("harassment", 1, true), s.dist .. ": " .. s.msg) end
		end
		-- A chat moderator's own reason: to the guild's clients and the player, never on the channel.
		w.epoch = w.epoch + 5
		assert(w.As(A, A.WC.Timeout, D.name, 300, "spam"))
		w.Run()
		local S = w.Sent("MD~1~S~T~")
		eq(S[#S].from, D.name)
		eq(S[#S].msg:match("~([^~]*)$"), "", "no reason on the channel")
		assert(w.Dialog(D, "OLYMPUS_WATCHCHAT_TIMED_OUT").a:find("spam", 1, true), "the player is told it")
	end)
end)

test("watch: chat moderation: a player's own word never writes his guild's audit: the officer it names is only his claim", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local forged = ("MD~1~S~T~12345~%d~%s~%s~%d~-~forged reason"):format(w.epoch, X, A.name, w.epoch + 600)
		for _, cl in ipairs({ G, D, Co, Y1 }) do w.Inject("CHANNEL", B.name, cl, forged) end
		for _, e in ipairs(w.As(G, G.W.Audit)) do
			assert(not (e.op == "T" and e.by == A.name), "in the guild's audit: " .. tostring(e.reason))
		end
		eq(#w.As(G, G.W.Audit), 0, "the guild master's audit holds nothing")
		-- The council keeps it as his own client's word, marked so; it restricts only him.
		local s = Co.WC.Store()
		eq(#s.audit, 1); eq(s.audit[1].scope, "S")
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true)
	end)
end)

test("watch: chat moderation: a line deleted from a report without its id: that line alone goes, the same words said later still show", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "lol")
		-- A was away when it was said: his client has no copy of it, so no id.
		local list = w.As(A, A.C.RawHistory, "A")
		for i = #list, 1, -1 do if list[i].text == "lol" then table.remove(list, i) end end
		assert(w.As(A, A.WC.DeleteReported, B.name, { { tier = "A", text = "lol" } }, ""))
		w.Run()
		eq(w.Lines(D, "A", B.name)[1].del, true, "deleted where it was kept")
		eq(w.Lines(Y1, "A", B.name)[1].del, true, "abroad too")
		w.epoch = w.epoch + 3600
		w.Say(B, "A", "lol")
		for _, cl in ipairs({ G, A, D, Y1 }) do assert(w.Line(cl, "A", B.name, "lol"), "his new 'lol' shows on " .. cl.short) end
	end)
end)

test("watch: chat moderation: a guild master's Watchers lapse on a client 3 days after it last heard his list: a removal it missed counts no longer", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(A, A.W.IsAuthorized, B.name), true)
		-- He is removed while A is away, and the guild master plays no more.
		A.online = false
		assert(w.As(G, G.WC.SetWatcher, B.name, false))
		w.epoch = w.epoch + 3
		w.Run()
		G.online, A.online = false, true
		eq(w.As(A, A.W.IsAuthorized, B.name), true, "A missed the removal: a Watcher there for now")
		w.epoch = w.epoch + 3 * 86400 + 1
		eq(w.As(A, A.W.IsAuthorized, B.name), false, "lapsed after 3 days")
		eq(A.WC.WATCHERS_FRESH, 3 * 86400)
		local ok = w.Inject("GUILD", B.name, A, ("MD~1~T~G~%d~%d~%s~%s~%d~-~-~"):format(5000, w.epoch, X, D.name, w.epoch + 300))
		eq(ok, false, "his timeout is refused there")
		-- While the guild master plays, his client's repeats keep his list alive.
		G.online = true
		assert(w.As(G, G.WC.SetWatcher, D.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		for _ = 1, 3 do
			w.epoch = w.epoch + 86400
			w.As(G, G.WC.Tick)
			w.Run()
		end
		eq(w.As(A, A.W.IsAuthorized, D.name), true, "repeated: fresh")
	end)
end)

test("watch: chat moderation: two Watchers' timeouts: the longer binds on every client, abroad too, and the player is told its end", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 604800, ""))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(G, G.WC.Timeout, B.name, 300, ""))
		w.Run()
		assert(w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT").a:find(ns.L.WATCHCHAT_SPAN_DAYS:format(7), 1, true),
			"told the 7 days, never the 5 minutes given after: " .. w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT").a)
		w.epoch = w.epoch + 301
		for _, cl in ipairs({ B, D, Y1 }) do eq(w.As(cl, cl.WC.Barred, "games", cl == B and nil or B.name) ~= nil, true, "the 7 days on " .. cl.short) end
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true, "abroad, his lines still dropped")
	end)
end)

test("watch: chat moderation: the King is never given a timeout (no client would hold it); the author may still delete his line", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.author, w.king = "Author-Realm", "Kingly-Realm"
		local K = w.Client("Kingly", "Olympus", 0)
		local Au = w.Client("Author", Y, 2)
		local ok, why = w.As(Au, Au.WC.Timeout, K.name, 300, "")
		eq(ok, false); eq(why, "king")
		eq(#w.wire, 0, "nothing sent")
		local _, fwhy = w.Inject("CHANNEL", Au.name, D, ("MD~1~T~O~%d~%d~Olympus~%s~%d~-~-~"):format(900, w.epoch, K.name, w.epoch + 300))
		eq(fwhy, "king", "nor taken")
		w.Say(K, "A", "a royal line")
		assert(w.As(Au, Au.WC.Delete, "A", w.Line(Au, "A", K.name, "a royal line"), ""))
		w.Run()
		eq(w.Line(D, "A", K.name).del, true, "his line deleted")
	end)
end)

test("watch: chat moderation: junk from players with no standing never spends the moderators' shared budget", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		for i = 1, 6 do
			local junk = "Junk" .. i .. "-Realm"
			for _ = 1, 10 do w.Inject("CHANNEL", junk, D, "MD~1~X~junk") end
			for j = 1, 10 do w.Inject("CHANNEL", junk, D, ("MD~1~T~O~%d~%d~%s~%s~%d~-~-~"):format(100 + j, w.epoch, X, B.name, w.epoch + 300)) end
			for j = 1, 10 do w.Inject("CHANNEL", junk, D, ("MD~1~S~T~%d~%d~%s~%s~%d~-~"):format(100 + j, w.epoch, X, A.name, w.epoch + 300)) end
		end
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the officer's timeout is taken")
	end)
end)

test("watch: chat moderation: the King's upheld word reaches the guild's Justice correspondent and its guild master, not only the officer who sent the case; a warning applies it", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local P = w.Client("Plain", X, 3)
		assert(w.As(G, G.WC.SetWatcher, D.name, true, true)) -- D: the Justice correspondent
		w.epoch = w.epoch + 3
		w.Run()
		-- The King's final word reached A's client, the officer who sent the case (Judgment.lua).
		assert(w.As(A, A.WC.TellCase, B.name, 42, "U"))
		w.Run()
		eq(w.As(D, D.WC.KingUpheld, B.name).jid, 42, "the Justice correspondent has it")
		eq(w.As(G, G.WC.KingUpheld, B.name) ~= nil, true, "the guild master too")
		eq(w.As(A, A.WC.KingUpheld, B.name) ~= nil, true, "the officer who sent it")
		eq(w.As(P, P.WC.KingUpheld, B.name), nil, "a member keeps nothing")
		eq(w.As(B, B.WC.KingUpheld, B.name), nil, "nor the player")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, ns.L.WATCHCHAT_DECISION_UP, "the player is told")
		eq(w.As(D, D.WC.MayApplyJudgment), true)
		-- A warning from him applies it: it leaves his case's page.
		assert(w.As(D, D.W.Warn, B.name, "the King's judgment"))
		w.Run()
		eq(w.As(D, D.WC.KingUpheld, B.name), nil, "applied")
		-- The case's page offers it while it waits (Watch.lua reads WatchChat.KingUpheld).
		local src = assert(io.open(ROOT .. "Olympus/Watch.lua", "rb")):read("*a")
		assert(src:find("WC.KingUpheld(target)", 1, true))
	end)
end)

---------------------------------------------------------------------------
-- Old clients, the gamepad UI, strings
---------------------------------------------------------------------------

test("watch: chat moderation: old clients: 1.1.4's Comm runs no handler for MD, without error; MD is in Comm.lua's list", function()
	local saved = rawget(_G, "C_ChatInfo")
	local ok, err = pcall(function()
		local events, login = {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then login[#login + 1] = fn end end
		cns.After, cns.Every = function() end, function() end
		cns.Now = function() return 100000 end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		assert(loadfile(ROOT .. "tests/fixtures/comm-1.1.4.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		local heard = 0
		for _, kind in ipairs({ "M1", "M2", "MW", "T1" }) do cns.Comm.Handle(kind, function() heard = heard + 1 end) end
		local function Deliver(dist, sender, text)
			for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, text, dist, sender) end
		end
		Deliver("GUILD", "Officer-Realm", "MD~1~T~G~900~1800000000~Olympus II~Member-Realm~1800000300~-~-~spam")
		Deliver("CHANNEL", "Member-Realm", "MD~1~S~D~900~1800000000~Olympus II~Officer-Realm~-~A.12.abcdef~")
		Deliver("GUILD", "Grandmaster-Realm", "MD~1~W~1800000000~Olympus II~1~1~-~Member-Realm")
		eq(heard, 0, "no handler runs")
		eq(cns.Comm.Stats().bad, 0, "none misread")
	end)
	C_ChatInfo = saved
	if not ok then error(err, 0) end
	local src = assert(io.open(ROOT .. "Olympus/Comm.lua", "rb")):read("*a")
	assert(src:find("WatchChat MD", 1, true))
end)

test("watch: chat moderation: under the gamepad UI every dialog is Olympus's own, the game's chat is left alone, and the line's button is a child of Olympus's bubble", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.gamepad = true
		w.Say(B, "A", "under the gamepad")
		local e = w.Line(A, "A", B.name, "under the gamepad")
		eq(w.As(A, A.WC.AskEntry, e, "A"), true)
		eq(A.dialogs[#A.dialogs].which, "OLYMPUS_WATCHCHAT_ACT", "ns.ShowDialog: Olympus's own window there")
		for _, which in ipairs({ "OLYMPUS_WATCHCHAT_ACT", "OLYMPUS_WATCHCHAT_MORE", "OLYMPUS_WATCHCHAT_TIME", "OLYMPUS_WATCHCHAT_TIME2",
			"OLYMPUS_WATCHCHAT_TIME3", "OLYMPUS_WATCHCHAT_WHY", "OLYMPUS_WATCHCHAT_TIMED_OUT", "OLYMPUS_WATCHCHAT_APPEAL",
			"OLYMPUS_WATCHCHAT_ANSWER", "OLYMPUS_WATCHCHAT_DECISION", "OLYMPUS_WATCHCHAT_NAME", "OLYMPUS_WATCHCHAT_REMOVE" }) do
			assert(StaticPopupDialogs[which], which)
		end
		local frames = #Y1.frame.lines
		assert(w.As(A, A.WC.Delete, "A", e, ""))
		w.Run()
		assert(Y1.frame.lines[frames].message:find("under the gamepad", 1, true), "the game's window keeps what it showed")
		eq(Y1.frame.calls, 0, "TransformMessages never called")
		eq(w.Line(Y1, "A", B.name).del, true, "the Chat tab's history is replaced all the same")
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT") ~= nil, true, "the pop-up through ns.ShowDialog")
		local cw = assert(io.open(ROOT .. "Olympus/ChatWindow.lua", "rb")):read("*a")
		assert(cw:find('b.mod = CreateFrame("Button", nil, b)', 1, true), "the button's parent is Olympus's bubble")
		assert(not cw:find("Menu.ModifyMenu", 1, true), "no game menu entry")
	end)
end)

test("watch: chat moderation: its strings in English and pt-BR, with the same placeholders", function()
	local oldLocale = GetLocale
	local pt = {}
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales.lua")), "Olympus", pt)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	local n = 0
	for k, v in pairs(ns.L) do
		if type(k) == "string" and (k:find("^WATCHCHAT_") or k == "WALLET_WHY_FROZEN" or k:find("_SANCTION$")) then
			n = n + 1
			local p = rawget(pt.L, k)
			assert(p and p ~= v, "pt-BR: " .. k)
			local a, b = {}, {}
			for x in v:gmatch("%%%d*[sd]") do a[#a + 1] = x end
			for x in p:gmatch("%%%d*[sd]") do b[#b + 1] = x end
			eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. k)
		end
	end
	assert(n >= 150, "the strings: " .. n)
	-- Every key the code reads is there.
	local src = assert(io.open(ROOT .. "Olympus/WatchChat.lua", "rb")):read("*a")
	for key in src:gmatch("L%.(WATCHCHAT_[%w_]+)") do assert(rawget(ns.L, key), "missing: " .. key) end
	eq(ns.L.WATCHCHAT_DELETED, "[deleted by a moderator]")
	eq(pt.L.WATCHCHAT_DELETED, "[apagada por um moderador]")
	-- The README says what the game's chat window keeps.
	local readme = assert(io.open(ROOT .. "README.md", "rb")):read("*a")
	assert(readme:find("Chat moderation (1.1.6)", 1, true) and readme:find("keep what they already showed", 1, true))
end)
