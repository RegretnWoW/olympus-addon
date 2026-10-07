local ns, test, eq, WithWindow = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-role%-badges%.lua$") or "./"

local function Pins(fn)
	local saved = { primary = ns.TREASURER, names = ns.TREASURER_CHARACTERS, realm = ns.TREASURER_REALM,
		marks = ns.ChatMarks, masked = ns.CouncilMasked, council = ns.IsHighCouncillor }
	ns.TREASURER = "Test Coin"
	ns.TREASURER_CHARACTERS = { "Test Coin", "Test Mail" }
	ns.TREASURER_REALM = ns.realm
	assert(loadfile(ROOT .. "Olympus/ChatMarks.lua"))("Olympus", ns)
	local ok, err = pcall(fn, "Test Coin-" .. ns.realm, "Test Mail-" .. ns.realm, ns.COIN:gsub(" $", ""))
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = saved.primary, saved.names, saved.realm
	ns.ChatMarks, ns.CouncilMasked, ns.IsHighCouncillor = saved.marks, saved.masked, saved.council
	if not ok then error(err, 0) end
end
local function Count(text, mark)
	local n, at = 0, 1
	while true do local p = text:find(mark, at, true); if not p then return n end; n, at = n + 1, p + #mark end
end

test("Chat role badge: only the verified primary Treasury realm-group pin gets a coin", function()
	Pins(function(primary, mail, coin)
		eq(ns.ChatMarks.RoleBadge(primary), coin)
		eq(ns.ChatMarks.RoleBadge(mail), "")
		eq(ns.ChatMarks.RoleBadge("Test Coin-Unconnected"), "")
		eq(ns.ChatMarks.RoleBadge("Test Coins-" .. ns.realm), "")
		eq(ns.ChatMarks.RoleBadge(nil), "")
		local secret = issecretvalue
		issecretvalue = function(name) return name == primary end
		local ok, err = pcall(function() eq(ns.ChatMarks.RoleBadge(primary), "") end)
		issecretvalue = secret; if not ok then error(err, 0) end
		local member, hides = ns.IsMember, ns.Moderation.Hides
		local safe, why = pcall(function()
			ns.IsMember = function() return false end; eq(ns.ChatMarks.RoleBadge(primary), "")
			ns.IsMember = member
			ns.Moderation.Hides = function() return { kind = "c" } end; eq(ns.ChatMarks.RoleBadge(primary), "")
			ns.Moderation.Hides = function() error("unavailable role evidence") end; eq(ns.ChatMarks.RoleBadge(primary), "")
		end)
		ns.IsMember, ns.Moderation.Hides = member, hides
		if not safe then error(why, 0) end
	end)
end)

test("Chat role badge: formatted addon lines use identity rather than guild labels and keep masked council plain", function()
	Pins(function(primary, _, coin)
		ns.CouncilMasked = function() return true end
		ns.IsHighCouncillor = function() return true end
		for _, guild in ipairs({ "Olympus", "Untrusted label", false }) do
			local line = ns.Channels.FormatLine("A", primary, guild or nil, "MA", "safe", true)
			eq(Count(line, coin), 1)
			assert(not line:find(ns.HIGH_COUNCIL_COLOR, 1, true), "a coin does not reveal the masked council role")
			assert(not line:find("nameplates-icon-elite", 1, true), "addon names still have no dragons")
		end
		local fake = ns.Channels.FormatLine("A", "Someone-" .. ns.realm, "Olympus", "MA", "Treasurer", true)
		eq(Count(fake, coin), 0, "neither a guild nor the words can grant the role")
	end)
end)

test("Chat role badge: actual Olympus, Guild, Race, Class and role bubbles share the coin even without a guild field", function()
	WithWindow(function(w)
		Pins(function(primary, _, coin)
			local R, C = ns.ChatRooms, ns.Channels
			local history, legacy = R.History, C.History
			local council = ns.IsHighCouncillor
			local entry = { t = 100, sender = primary, text = "badge line", role = "member" }
			R.History = function() return { entry } end
			C.History = function() return { entry } end
			ns.IsHighCouncillor = function(name) return name == ns.me end -- real room access, not a sender claim
			local ok, err = pcall(function()
				local frame = w.CW.Open("A")
				local function Header()
					for _, bubble in ipairs(frame.bubbles) do
						if bubble:IsShown() and bubble.entry == entry then return bubble.who:GetText() end
					end
					error("missing rendered sender bubble")
				end
				eq(Count(Header(), coin), 1, "Olympus")
				for _, id in ipairs({ "guild", "race:1", "class:WA", "council" }) do
					assert(w.CW.SelectLogical(id), id .. " is selectable")
					eq(Count(Header(), coin), 1, id)
				end
				entry.sender = "Someone-" .. ns.realm; entry.guild = "Olympus"; entry.role = "treasurer"
				w.CW.Render(); eq(Count(Header(), coin), 0)
			end)
			R.History, C.History, ns.IsHighCouncillor = history, legacy, council
			if not ok then error(err, 0) end
		end)
	end)
end)

test("Chat role badge: the existing native sender filter adds one coin and keeps its existing enable gate", function()
	WithWindow(function()
		Pins(function(primary, _, coin)
			local api, marks = ChatFrameUtil, ns.db.chatMarks
			local c = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
			-- Keep real Allowed decisions, but do not overwrite the harness gate's installed hooks.
			c.Gate = setmetatable({ Hooks = function() end }, { __index = ns.Gate })
			ChatFrameUtil = { AddSenderNameFilter = function() end }
			local ok, err = pcall(function()
				assert(loadfile(ROOT .. "Olympus/Borders.lua"))("Olympus", c)
				ns.db.chatMarks = true; assert(c.Borders.ChatRefresh())
				for event in pairs(c.Borders.CHAT_EVENTS) do
					local shown = assert(c.Borders.ChatFilter(event, "Test Coin", "hello", primary))
					eq(Count(shown, coin), 1, event)
					eq(Count(c.Borders.ChatFilter(event, coin .. "Test Coin", "hello", primary), coin), 1, "no duplicate coin")
				end
				ns.db.chatMarks = false; c.Borders.ChatRefresh()
				eq(c.Borders.ChatFilter("CHAT_MSG_GUILD", "Test Coin", "hello", primary), nil)
			end)
			ChatFrameUtil, ns.db.chatMarks = api, marks
			if not ok then error(err, 0) end
		end)
	end)
end)

test("Chat role badge: actual Arena room and private crafting-provider bubbles keep guildless verified identity", function()
	WithWindow(function(w)
		Pins(function(primary, _, coin)
			local saved = ns.ArenaChat
			local entry = { t = 100, sender = primary, text = "private badge line" }
			local spec = { id = "Fbadge-1", key = "arena:Fbadge-1", kind = "fight", audience = "duel", access = "participants",
				title = "Fixture fight", phase = "live", active = true, recoverable = true, supportsComments = true }
			ns.ArenaChat = { Open = function() return true end, Lines = function() return { entry } end,
				Rooms = function() return { spec } end, Close = function() return true end }
			local active, reads = true, 0
			local id = "craft:badge-fixture"
			-- The same provider contract as CraftRequests: provider owns membership and history.
			-- Retire it after the test so no subsequent room can resolve this fixture identity.
			assert(ns.ChatRooms.RegisterProvider({
				Info = function(room) if active and room == id then return { id = id, kind = "craft", scope = "private", label = "Fixture crafting" } end end,
				CanAccess = function(room) return active and room == id end,
				History = function() reads = reads + 1; return { entry } end,
				Send = function() return false end,
				Tabs = function() return active and { { id = id, kind = "craft", label = "Fixture crafting" } } or {} end,
			}))
			local ok, err = pcall(function()
				local frame = assert(w.CW.OpenDynamicRoom(spec))
				local function Header()
					for _, bubble in ipairs(frame.bubbles) do
						if bubble:IsShown() and bubble.entry == entry then return bubble.who:GetText() end
					end
					error("missing private sender bubble")
				end
				eq(Count(Header(), coin), 1, "Arena")
				assert(w.CW.SelectLogical(id)); assert(reads > 0, "the real Rooms.History delegates to the provider")
				eq(Count(Header(), coin), 1, "private crafting conversation")
			end)
			active = false; ns.ArenaChat = saved
			if not ok then error(err, 0) end
		end)
	end)
end)

test("Chat role badge: the Throne loses only Games and bets and retains its agenda action", function()
	WithWindow(function(w)
		local shown, canCall, home = ns.King.ThroneShown, ns.King.CanCall, ns.ArenaHome
		ns.King.ThroneShown = function() return true end
		ns.King.CanCall = function() return true end
		-- This harness predates the Arena module; expose the old shortcut's eligibility only.
		ns.ArenaHome = { GamesStaff = function() return true end, OpenStaff = function() error("removed shortcut invoked") end }
		local ok, err = pcall(function()
			local frame = w.CW.Open("A"):GetParent()
			w.UI.SelectTab("throne")
			local agenda = false
			for _, button in ipairs(frame.buttons) do
				if button:IsShown() then
					assert(button:GetText() ~= ns.L.THRONE_GAMES_BETS, "only the Throne shortcut is removed")
					if button:GetText() == ns.L.THRONE_AGENDA then agenda = true end
				end
			end
			assert(agenda, "the existing agenda action remains")
		end)
		ns.King.ThroneShown, ns.King.CanCall, ns.ArenaHome = shown, canCall, home
		if not ok then error(err, 0) end
	end)
end)
