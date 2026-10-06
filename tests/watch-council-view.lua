-- Presentation parity never grants guild-local moderation or the King's final word.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]watch%-council%-view%.lua$") or "./"
local function Client(fn)
	local savedGuild, savedInGuild = GetGuildInfo, IsInGuild
	local dialogs = {}
	for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local w = { role = "council", rank = 3, member = true, epoch = 1800000000, sent = 0 }
	local c = setmetatable({ L = ns.L, me = "Councillor-Realm", group = "RealmGroup", faction = "Alliance",
		db = {}, rdb = {}, CAPTAIN_RANK = 1, UI = {}, PlayerMenu = { Add = function() end },
		On = function() end, Fire = function() end, RegisterEvent = function() end,
		After = function() end, Every = function() end, Print = function() end,
		Workshop = { IsAuthor = function() return w.author == true end, Preview = function() return false end,
			IsAuthorName = function() return false end },
		Authority = { Enforced = function() return false end },
		Alts = { Linked = function() return {} end },
		Filter = { SharedOn = function() return true end },
		KingArrow = { ControlLines = function() return {} end },
		TabardsV2 = { SurfaceVisible = function() return w.published == true end, Collector = function() return nil end },
	}, { __index = ns })
	c.Now = function() return w.epoch end
	c.Data = { ServerTime = c.Now }
	c.FullName = function(name) return name and (name:find("-", 1, true) and name or name .. "-Realm") end
	c.DisplayName = function(name) return name and name:gsub("%-Realm$", "") end
	c.IsFederation = function(guild) return guild == "Olympus II" end
	c.IsMember = function() return w.member end
	c.IsHighCouncillor = function(name) return name == c.me and w.role == "council" end
	c.IsKingCharacter = function(name) return name == c.me and w.role == "king" end
	c.IsSteward = function() return false end
	c.CouncilMasked = function() return w.masked == true end
	c.MaskName = function() return "MASKED" end
	c.Moderation = { IsKing = c.IsKingCharacter, SelfOff = function() return w.off end,
		Hides = function() return w.off end, Hidden = function() return w.off end,
		CharName = c.FullName, Lines = function() return {} end }
	c.Roster = { complete = true, byName = {}, online = {}, guild = "Olympus II", group = c.group,
		faction = c.faction, snapshotAt = w.epoch, generation = 1,
		RankOf = function(name) return c.Roster.byName[name] end, MyRank = function() return w.rank end }
	c.Comm = { Handle = function() end, Send = function() w.sent = w.sent + 1 end,
		Whisper = function() w.sent = w.sent + 1 end }
	c.King = { IsKing = function() return c.IsKingCharacter(c.me) end,
		Preview = function() return false end, Register = function() end }
	GetGuildInfo = function() return "Olympus II", "Member", w.rank end
	IsInGuild = function() return w.member end
	local ok, why = pcall(function()
		for _, file in ipairs({ "ViewAs", "Court", "Watch", "Judgment", "WatchChat" }) do
			assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
		end
		fn(w, c)
	end)
	GetGuildInfo, IsInGuild = savedGuild, savedInGuild
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = dialogs[key] end
	if not ok then error(why, 0) end
end
local function Nav(c)
	local lines = c.Watch.Build()
	local keys = {}
	for _, item in ipairs(lines[1].nav or {}) do keys[#keys + 1] = item.text end
	return table.concat(keys, "|")
end

test("watch: council view: King and High Council share desk navigation without local officer authority", function()
	Client(function(w, c)
		local W = c.Watch
		eq(W.DeskShown(), true); eq(W.PageId(), "desk"); eq(W.CanRead(), false); eq(W.CanManage(), false)
		local council = Nav(c)
		w.role = "king"
		eq(W.DeskShown(), true); eq(Nav(c), council, "same permitted sections as the King's")
		w.role = "council"
		for _, mode in ipairs({ "reports", "cases" }) do W.Show(mode); eq(W.PageId(), mode); assert(W.Build()) end
		eq(#W.Records(), 0); eq(#W.Audit(), 0); eq(#W.Cases(), 0)
		eq(W.IsAuthorized(c.me), false); eq(W.IsAuthorized("OtherGuildOfficer-Realm"), false)
		local ok = W.Mark("Member", "reason"); eq(ok, false)
		local decided, why = c.Judgment.Decide("missing", "U"); eq(decided, false); eq(why, "king")
		c.Court.Toggle(); eq(c.Court.Holding(), nil); eq(w.sent, 0)
		eq(W.TabardsShown(), false, "the publication gate is independent")
	end)
end)

test("watch: council view: membership, signed role and sanctions are checked again when drawn", function()
	Client(function(w, c)
		local W, WC = c.Watch, c.WatchChat
		eq(W.DeskShown(), true); eq(WC.PageShown(), true)
		w.role = "member"
		eq(W.DeskShown(), false); eq(W.TabVisible(), false); eq(WC.PageShown(), false); eq(#WC.PageLines(), 0)
		w.role = "council"; w.member = false
		eq(W.DeskShown(), false); eq(WC.PageShown(), false)
		w.member = true; w.off = { reason = "held" }
		eq(W.DeskShown(), false); eq(WC.PageShown(), false); eq(#WC.PageLines(), 0)
		w.off = nil; eq(W.DeskShown(), true)
		w.masked = true
		eq(W.ShownBy("PrivateOfficer-Realm"), "MASKED", "existing name masking remains active")
		c.Roster.byName["GuildMaster-Realm"] = 0
		WC.Store().guildLists[c.Fold("Olympus II")] = { by = "GuildMaster-Realm", heard = w.epoch,
			names = { "PrivateWatcher-Realm" }, justice = "PrivateJustice-Realm" }
		local text = {}
		for _, line in ipairs(WC.PageLines()) do text[#text + 1] = line.text or "" end
		text = table.concat(text, "|")
		assert(text:find("MASKED", 1, true), "authenticated local watcher names use the mask")
		eq(text:find("PrivateWatcher", 1, true), nil); eq(text:find("PrivateJustice", 1, true), nil)
	end)
end)

test("watch: council view: author role preview shares layout but grants no private data or actions", function()
	Client(function(w, c)
		w.role = "member"
		eq(c.ViewAs.Set("councillor"), false, "a member cannot enable an author preview")
		eq(c.Watch.DeskShown(), false)
		w.author = true; assert(c.ViewAs.Set("councillor"))
		eq(c.ViewAs.Allows("watch"), true); eq(c.Watch.DeskShown(), true)
		eq(c.Watch.CanRead(), false); eq(#c.Watch.Cases(), 0)
		local ok, why = c.Judgment.Decide("missing", "U"); eq(ok, false); eq(why, "king")
		assert(c.ViewAs.Set("member")); eq(c.Watch.DeskShown(), false); eq(c.WatchChat.PageShown(), false)
		eq(#c.WatchChat.PageLines(), 0); eq(w.sent, 0)
	end)
end)
