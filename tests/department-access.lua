local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]department%-access%.lua$")) or "./"

local function World(fn)
	local savedGuild, savedIn = GetGuildInfo, IsInGuild
	local dialogs = {}; for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local w = { now = 1800000000, guild = "Olympus II", rank = 3, packets = {}, selected = nil }
	local c = setmetatable({ me = "Envoy-Realm", realm = "Realm", group = "RealmGroup", faction = "Alliance", db = {}, rdb = {} }, { __index = ns })
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild, "Member", w.rank end
		IsInGuild = function() return true end
		c.Now = function() return w.now end
		c.IsMember = function() return c.IsFederation(w.guild) end
		c.IsKingGuild = function(g) return g == "Olympus" end
		c.KingGuildName = function() return "Olympus" end
		c.IsHighCouncillor, c.IsKingCharacter = function() return false end, function() return false end
		c.FullName = function(n) if not n then return nil end return n:find("-", 1, true) and n or n .. "-Realm" end
		c.ShortName = function(n) return n and n:match("^[^-]+") end
		c.RealmOf = function(n) return n and n:match("%-([^%-]+)$") or "Realm" end
		c.Print, c.Log, c.Fire, c.On, c.After = function() end, function() end, function() end, function() end, function() end
		c.ChatLocked = function() return false end
		c.Roster = { complete = true, guild = w.guild, group = c.group, faction = c.faction, generation = 1, snapshotAt = w.now,
			byName = { ["Guildmaster-Realm"] = 0, [c.me] = 3, ["Peer-Realm"] = 3 }, members = {} }
		c.Roster.RankOf = function(n) return c.Roster.byName[c.FullName(n)] end
		c.Roster.IsOfficer = function() return w.rank <= 1 end
		c.Data = setmetatable({ KnownRank = function() return nil end }, { __index = ns.Data })
		c.ViewAs = { Available = function() return false end, Is = function() return false end }
		c.Workshop = { Visible = function() return false end }
		c.ChatRooms, c.PlayerMenu = {}, {}
		c.Moderation = { CharName = c.FullName, IsIssuer = function() return false end, Hides = function() return nil end,
			Hidden = function() return false end, SelfOff = function() return nil end, IsKing = function() return false end }
		c.UI = { SelectTab = function(key) w.selected = key end }
		c.Comm = { Handle = function() end, Send = function(dist, msg, _, _, _, _, options)
			w.packets[#w.packets + 1] = { dist = dist, msg = msg, options = options }; return true end }
		c.Borders = { Changed = function() end }
		assert(loadfile(ROOT .. "Olympus/Nominees.lua"))("Olympus", c)
		function w.name(dept, sender, name)
			w.now = w.now + 1; c.Roster.snapshotAt = w.now
			c.Nominees.Handle("CHANNEL", sender or "Guildmaster-Realm",
				("NM~1~%s~%d~1~1~d=%s=%s"):format(w.guild, w.now, dept, name or c.me))
		end
		fn(w, c)
	end)
	GetGuildInfo, IsInGuild = savedGuild, savedIn
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = nil end
	for key, value in pairs(dialogs) do StaticPopupDialogs[key] = value end
	if not ok then error(err, 0) end
end

test("guild departments: exact own-guild correspondent authority comes from a fresh roster and its current master's list", function()
	World(function(w, c)
		local N, dept = c.Nominees, "Department of War"
		w.name(dept, "Peer-Realm")
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "forged master rejected")
		w.name(dept)
		eq(N.IsCorrespondent(c.me, w.guild, dept), true)
		eq(N.OwnDepartment(), dept); eq(N.Correspondent(w.guild, dept), c.me)
		eq(N.IsCorrespondent(c.me, "Olympus of Ash", dept), false)
		eq(N.IsCorrespondent(c.me, w.guild, "Federal Treasury"), false)
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "deposed before pruning")
		c.Roster.byName["Guildmaster-Realm"] = 0
		c.Roster.byName[c.me] = nil
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "left the guild")
		c.Roster.byName[c.me] = 3
		c.Roster.complete = false
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "partial roster")
		c.Roster.complete = true; w.now = w.now + 601
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "stale roster")
		c.Roster.snapshotAt = w.now
		eq(N.IsCorrespondent(c.me, w.guild, dept), true)
		w.now = w.now + N.FRESH + 1; c.Roster.snapshotAt = w.now
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "expired nomination")
	end)
end)

test("guild departments: each correspondent sees their own panel with inert previews and no other department controls", function()
	World(function(w, c)
		local N = c.Nominees
		w.name("Association of Citizenry")
		eq(N.GuildAccess(), true)
		local rows, text, open = N.GuildLines(), {}, nil
		for _, row in ipairs(rows) do text[#text + 1] = tostring(row.text); if row.onClick then open = row end end
		text = table.concat(text, "\n")
		assert(text:find("Association of Artisanry", 1, true)); assert(not text:find("Association of Citizenry", 1, true)); assert(not text:find("Department of War", 1, true))
		eq(N.OwnDepartment(), "Association of Artisanry", "legacy nominations keep their operational duties under the corrected label")
		eq(N.IsCorrespondent(c.me, w.guild, "Association of Citizenry"), true, "older clients' department key remains compatible")
		assert(text:find("Dedicated department workflows", 1, true), "unavailable workflows are explicit after paragraph wrapping")
		assert(open); open.onClick(); eq(w.selected, "crafters")
		w.selected = nil; c.Roster.byName["Guildmaster-Realm"] = 1
		open.onClick(); eq(w.selected, nil, "stale button after authority revoked")
		eq(N.GuildAccess(), false)
		c.ViewAs = { Available = function() return true end, Role = function() return "correspondent" end, Previewing = function() return true end }
		eq(N.GuildAccess(), true)
		for _, row in ipairs(N.GuildLines()) do eq(row.onClick, nil, "preview is inert") end
	end)
end)

test("guild departments: guild master uses Artisanry throughout and canonical nominations preserve legacy lookup", function()
	World(function(w, c)
		local N = c.Nominees
		w.rank = 0; c.me = "Guildmaster-Realm"
		local text = {}
		for _, row in ipairs(N.GuildLines()) do text[#text + 1] = tostring(row.text) end
		text = table.concat(text, "\n")
		assert(text:find("Association of Artisanry", 1, true)); assert(not text:find("Citizenry", 1, true))
		-- The master's client owns its local list; test receiving his update on a member's client.
		w.rank = 3; c.me = "Envoy-Realm"
		w.name("Association of Artisanry", "Guildmaster-Realm", "Peer-Realm")
		eq(N.IsCorrespondent("Peer-Realm", w.guild, "Association of Artisanry"), true)
		eq(N.Correspondent(w.guild, "Association of Citizenry"), "Peer-Realm")
	end)
end)

test("guild departments: Justice duties use the verified nomination but Church authority still needs its canonical appointment", function()
	World(function(w, c)
		assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/Church.lua"))("Olympus", c)
		w.name("Council of Justice")
		eq(c.WatchChat.Justice(), c.me); eq(c.WatchChat.IsNamedWatcher(c.me), true)
		eq(c.Watch.CanManage(), true, "same own-guild Watch duty as an appointed Justice correspondent")
		eq(c.WatchChat.CouncilSide(), false, "no federal authority")
		w.name("The Missionary Church of Olympus")
		eq(c.WatchChat.IsNamedWatcher(c.me), false, "prior department removed")
		eq(c.Church.Role(c.me), nil); eq(c.Church.IsPerson(c.me), false, "a contact nomination cannot silently grant Church duties")
		eq(c.Church.MayNameApostle(c.me), false)
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(c.Nominees.OwnDepartment(), nil, "a deposed master's nomination immediately loses authority")
	end)
end)

test("guild departments: a War correspondent may write only in their own guild and queued writes lose authority on revocation", function()
	World(function(w, c)
		assert(loadfile(ROOT .. "Olympus/War.lua"))("Olympus", c)
		local W = c.War
		w.name("Federal Treasury"); eq(W.IsOfficer(), false, "other department grants no War duty")
		w.name("Department of War"); eq(W.IsOfficer(), true)
		local operation = W.CreateOperation("raid 30 tank=1 | First operation")
		assert(operation, "real operation created")
		local packet = w.packets[#w.packets]
		eq(packet.dist, "GUILD", "no federal channel")
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(W.IsOfficer(), false)
		assert(packet.options and packet.options.permit)
		eq(packet.options.permit(W, packet.options.key, "GUILD", nil, packet.msg), false, "queued write revoked")
		c.Roster.byName["Guildmaster-Realm"] = 0
		w.guild = "Olympus of Ash"
		eq(W.IsOfficer(), false, "guild transfer cannot reuse the old roster")
	end)
end)
