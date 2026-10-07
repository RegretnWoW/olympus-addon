-- Invented identities and proven-role fixtures; exercise the real room access and transport.
local H = ...
local test, eq = H.test, H.eq

local function WithRoles(fn)
	local oldGuild, oldTime = GetGuildInfo, GetTime
	local popups = {}; for key, value in pairs(StaticPopupDialogs) do popups[key] = value end
	local own, foreign = "Olympus II", "Olympus III"
	local w = { time = 1000, ranks = {}, lists = {}, council = {}, titles = {}, jobs = {}, role = nil, fresh = true, census = {} }
	local c = setmetatable({ L = H.ns.L, me = "Sage Owl-Realm", db = { chatRooms = true },
		rdb = { guilds = {}, council = { names = {} } }, CAPTAIN_RANK = 1 }, { __index = H.ns })
	GetGuildInfo = function() return own end
	GetTime = function() return w.time end
	c.FullName = function(name) return type(name) == "string" and (name:find("-", 1, true) and name or name .. "-Realm") or "" end
	c.ShortName = function(name) return tostring(name):match("^([^%-]+)") end
	c.Now = function() return w.time end
	c.Fire, c.On, c.Print, c.Log = function() end, function() end, function() end, function() end
	c.RealmOf = function(name) return tostring(name):match("%-([^%-]+)$") or "Realm" end
	c.IsMember, c.IsFederation = function() return true end, function(g) return g == own or g == foreign end
	c.IsKingGuild = function() return false end
	c.KingCharacter = function() return "Crown Owl-Realm" end
	c.IsKingCharacter = function(name) return c.FullName(name) == c.KingCharacter() end
	c.TREASURER = "Ledger Owl"
	c.Treasury = { TreasurerPin = function(name) return c.FullName(name) == "Ledger Owl-Realm" and 1 or nil end }
	c.IsHighCouncillor = function(name) return w.council[c.FullName(name)] == true end
	c.CouncilTitle = function(name) return w.titles[c.FullName(name)] end
	c.CouncilTitles = function() return { depts = {} } end
	c.IsSteward = function() return false end
	c.Workshop = { IsAuthor = function() return true end, Visible = function() return true end }
	c.Channels = { IsMe = function(name) return c.FullName(name) == c.me end }
	c.Roster = { members = {}, Fresh = function() return w.fresh end,
		RankOf = function(name) return (w.ranks[own] or {})[c.FullName(name)] end }
	c.Data = { Guild = function(g) return c.rdb.guilds[g] end,
		AuthorizedRank = function(name, g)
			local rank = (w.ranks[g] or {})[c.FullName(name)]
			if rank == nil then return nil end
			return rank, g == own and "roster" or (w.census[g] and "census" or "signed")
		end }
	c.Nominees = {
		ListOf = function(g) return w.lists[g] end,
		Proven = function(name, g) return c.Data.AuthorizedRank(name, g) == 0 end,
		RoleOf = function(name, g)
			for _, entry in ipairs(w.lists[g] and w.lists[g].entries or {}) do
				if c.FullName(entry.name) == c.FullName(name) then return entry.role, entry.dept end
			end
		end,
	}
	c.ViewAs = { Previewing = function() return w.role ~= nil end, Role = function() return w.role end }
	c.Comm = { Handle = function() end, Whisper = function(target, msg, _, _, _, _, options)
		w.jobs[#w.jobs + 1] = { target = target, msg = msg, options = options }; return true
	end }
	c.Consent, c.Moderation, c.WatchChat = false, false, false
	c.Codec = { SanitizeChat = function(s) return s end }
	local function Rank(name, guild, rank)
		w.ranks[guild] = w.ranks[guild] or {}; w.ranks[guild][c.FullName(name)] = rank
		if guild == own then c.Roster.members[#c.Roster.members + 1] = { name = name } end
	end
	local function List(guild, head, entries)
		Rank(head, guild, 0)
		w.lists[guild] = { by = c.FullName(head), entries = entries }
		c.rdb.guilds[guild] = { leader = head, officers = {} }
	end
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "ChatRooms.lua"))("Olympus", c)
		fn(c.ChatRooms, c, w, Rank, List, own, foreign)
	end)
	GetGuildInfo, GetTime = oldGuild, oldTime
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = nil end
	for key, value in pairs(popups) do StaticPopupDialogs[key] = value end
	if not ok then error(err, 0) end
end

test("Role audiences: council includes actual crown and federal treasurer, never the author alone", function()
	WithRoles(function(R, c, w)
		eq(R.CanAccess("council"), false, "author status is not council membership")
		eq(R.Send("council", "private"), false); eq(#w.jobs, 0)
		eq(R.CanAccess("council", c.KingCharacter()), true)
		eq(R.CanAccess("council", "Ledger Owl"), true)
		w.council[c.me], c.rdb.council.names[c.me:lower()] = true, c.me
		eq(R.CanAccess("council"), true)
		local recipients = table.concat(R.Recipients("council"), ",")
		assert(recipients:find("Crown Owl-Realm", 1, true)); assert(recipients:find("Ledger Owl-Realm", 1, true))
		w.council[c.me] = nil; eq(R.CanAccess("council"), false)
	end)
end)

test("Role audiences: real nomination messages require the current master and expire without granting claims", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 3); Rank("Head Owl", own, 0); Rank("Head Wren", foreign, 0)
		c.rdb.guilds[foreign] = { leader = "Head Wren", officers = {} }
		c.Data.KnownRank = function(name, guild) return c.Data.AuthorizedRank(name, guild), 2 end
		assert(loadfile(H.ADDON_DIR .. "Nominees.lua"))("Olympus", c)
		local N = c.Nominees
		local packet = "NM~1~" .. foreign .. "~1000~1~1~d=Department of War=Wren Thistle-Realm"
		N.Handle("CHANNEL", "Ordinary Wren-Realm", packet)
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "self-claimed nomination is not accepted")
		N.Handle("CHANNEL", "Head Wren-Realm", packet)
		eq(R.CanAccess("dept:war", "Wren Thistle"), true, "the actual master's received nomination")
		w.ranks[foreign]["Head Wren-Realm"] = 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false)
		w.ranks[foreign]["Head Wren-Realm"] = 0
		w.time = w.time + N.FRESH + 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "real nomination expires")
	end)
end)

test("Role audiences: department correspondents and heads follow current verified nominations", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 3)
		List(own, "Head Owl", { { name = "Sage Owl", role = "correspondent", dept = "Department of War" } })
		List(foreign, "Head Wren", { { name = "Wren Thistle", role = "correspondent", dept = "Department of War" } })
		eq(R.CanAccess("dept:war"), true); eq(R.CanAccess("departments"), true)
		eq(R.CanAccess("dept:treasury"), false); eq(R.CanAccess("treasurers"), false)
		eq(R.CanAccess("dept:war", "Wren Thistle"), true)
		w.titles["Council Owl-Realm"] = { dept = "Department of War" }
		eq(R.CanAccess("dept:war", "Council Owl"), true)
		eq(R.CanAccess("dept:church", "Sage Owl"), false)
		w.lists[own].entries[1].dept = "The Missionary Church of Olympus"
		eq(R.CanAccess("dept:church"), true); eq(R.CanAccess("dept:war"), false)
		w.lists[own].entries[1].dept = "Federal Treasury"
		eq(R.CanAccess("treasurers"), true)
		eq(R.CanAccess("treasurers", "Head Owl"), false, "guild master is not automatically a treasurer")
		w.ranks[foreign]["Head Wren-Realm"] = 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "revoked master cannot authorize nominees")
		w.fresh = false; eq(R.CanAccess("dept:treasury"), false)
	end)
end)

test("Role audiences: guild and global centurions stay separate from guild masters and previews", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 1); Rank("Ordinary Owl", own, 3)
		List(own, "Head Owl", {})
		List(foreign, "Head Wren", { { name = "Wren Thistle", role = "centurion" } })
		eq(R.CanAccess("centurions"), true); eq(R.CanAccess("allcenturions"), true)
		eq(R.CanAccess("masters"), false); eq(R.CanAccess("masters", "Head Owl"), true)
		eq(R.CanAccess("centurions", "Wren Thistle"), false)
		eq(R.CanAccess("allcenturions", "Wren Thistle"), true)
		for _, id in ipairs({ "masters", "centurions", "allcenturions", "departments", "treasurers" }) do
			eq(R.CanAccess(id, "Ordinary Owl"), false)
		end
		eq(R.Send("allcenturions", "role message"), true); eq(#w.jobs, 1)
		eq(w.jobs[1].target, "Wren Thistle-Realm")
		w.lists[foreign].entries = {}
		eq(w.jobs[1].options.permit(nil, nil, "WHISPER", w.jobs[1].target), false, "queued whisper rechecks recipient role")
		w.role = "officer"
		local ids = {}
		for _, option in ipairs(R.Options("role")) do
			ids[option.id] = true; eq(option.disabled, true); eq(R.Select(option.id), false)
		end
		eq(ids.centurions, true); eq(ids.allcenturions, true); eq(ids.masters, nil)
		w.role = "gm"; local options = R.Options("role")
		eq(#options, 1); eq(options[1].id, "masters"); eq(R.Send("masters", "preview"), false)
		eq(#R.History("masters"), 0)
	end)
end)

test("Role audiences: a guild known only from census reports opens no private room: its 'master' and 'officers' are neither recipients nor accepted", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		w.census[foreign] = true
		c.rdb.guilds[foreign] = { leader = "Fake Master", officers = {} }
		Rank("Fake Master", foreign, 0); Rank("Fake Officer", foreign, 1)
		eq(R.CanAccess("masters", "Fake Master"), false, "a census guild master")
		eq(R.CanAccess("allcenturions", "Fake Officer"), false, "a census officer")
		local recipients = table.concat(R.Recipients("allcenturions"), ",")
		assert(not recipients:find("Fake", 1, true), recipients)
		w.census[foreign] = nil
		eq(R.CanAccess("masters", "Fake Master"), true, "the same rank from the signed list")
	end)
end)
