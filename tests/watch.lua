-- The Watch: guild-local moderation, signed-role gates and its restricted transport.
-- These tests load the real Watch.lua against a small WoW/client boundary so they exercise its
-- public functions, queued-send permit and saved state rather than copying the implementation.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]watch%.lua$")) or "./"

local function WithWatch(fn)
	local globals = { "GetGuildInfo", "IsInGuild", "UnitIsPlayer", "C_ChatInfo", "CreateFrame", "UIParent" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local dialogNames = { "OLYMPUS_WATCH_WHO", "OLYMPUS_WATCH_REASON", "OLYMPUS_WATCH_CLEAR", "OLYMPUS_WATCH_BAN_CONFIRM",
		"OLYMPUS_WATCH_REPORT_WHAT", "OLYMPUS_WATCH_REPORT_MORE", "OLYMPUS_WATCH_REPORT_NOTE", "OLYMPUS_WATCH_CASE_CLOSE",
		"OLYMPUS_JUDGMENT_ESCALATE", "OLYMPUS_JUDGMENT_FINAL", "OLYMPUS_WATCH_REPORT_PERSON" }
	local savedDialogs = {}
	for _, name in ipairs(dialogNames) do savedDialogs[name] = StaticPopupDialogs[name] end

	local w = { epoch = 1800000000, guild = "Olympus II", myRank = 0, member = true,
		logged = true, jobs = {}, events = {}, listeners = {}, dialogs = {}, prints = {},
		hidden = {}, issuers = {}, signed = {}, links = {}, filterHit = nil, queueRoom = 60, timers = {},
		handlers = {}, chat = {} }
	local ok, err = pcall(function()
		GetGuildInfo = function(unit)
			if unit == nil or unit == "player" then return w.guild, "Guild Master", w.myRank end
		end
		IsInGuild = function() return w.member end
		UnitIsPlayer = function() return false end
		C_ChatInfo = { SendAddonMessageLogged = function() return true end }

		local c = setmetatable({ L = ns.L, db = {}, rdb = {}, me = "Officer-Realm", realm = "Realm", group = "RealmGroup",
			faction = "Alliance", CAPTAIN_RANK = 1 }, { __index = ns })
		c.Now = function() return w.epoch end
		c.Data = { ServerTime = function() return w.epoch end }
		c.FullName = function(name, realm)
			name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name == "" or name:find("-", 1, true) then return name end
			return name .. "-" .. (realm or "Realm")
		end
		c.DisplayName = function(name) return tostring(name or ""):gsub("%-Realm$", "") end
		c.UnitFullName = function() return nil end
		c.IsFederation = ns.IsFederation
		c.Fold, c.Cut = ns.Fold, ns.Cut
		c.IsMember = function() return w.member and c.IsFederation(w.guild) end
		c.CouncilMasked = function() return w.masked == true end
		c.IsKingCharacter = function() return false end
		c.MaskName = function(name) return tostring(name):sub(1, 4) .. "****" end
		c.ChatLocked = function() return w.locked == true end
		-- 1.1.6: the right-click menu's entries, the Olympus channels' history (Channels.History) and
		-- the copy box, as the Watch's report and case pages use them.
		c.PlayerMenu = { Add = function(key, build, order) w.menu = { key = key, build = build, order = order } return true end }
		c.Channels = { ORDER = { "A", "C", "L" }, TIERS = { A = { label = "CHAN_ALL" }, C = { label = "CHAN_CAPTAINS" }, L = { label = "CHAN_LORDS" } },
			History = function(tier) return w.chat[tier] or {} end }
		c.Ago = function(at) return tostring(w.epoch - (tonumber(at) or 0)) .. "s ago" end
		c.SafeCall = function(_, call, ...) return call(...) end
		c.Fire = function(name, ...) w.events[#w.events + 1] = { name, ... } end
		c.On = function(name, call) w.listeners[name] = call end
		c.Print = function(message) w.prints[#w.prints + 1] = tostring(message) end
		c.PlayAlert = function(kind, source) w.alert = { kind, source } end
		c.After = function(seconds, where, call) w.timers[#w.timers + 1] = { seconds = seconds, where = where, call = call } end
		c.Every = function() end
		c.ShowDialog = function(which, a, b, data)
			w.dialogs[#w.dialogs + 1] = { which = which, a = a, b = b, data = data }
			return true
		end

		c.Roster = { byName = {}, online = {}, guild = w.guild, group = c.group, faction = c.faction, complete = true,
			snapshotAt = w.epoch, generation = 1 }
		c.Roster.RankOf = function(name) return c.Roster.byName[c.FullName(name)] end
		c.Roster.MyRank = function() return w.myRank end
		c.Roster.IsOfficer = function() return w.member and w.myRank <= c.CAPTAIN_RANK end
		c.Roster.byName[c.me] = w.myRank

		local function CharName(input, target)
			local name = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name == "" and target then name = tostring(w.target or "") end
			if name == "" or name:find("[~|%c]") then return nil end
			return c.FullName(name)
		end
		c.Moderation = {
			CharName = CharName,
			Hidden = function(name) return w.hidden[c.Fold(c.FullName(name))] == true end,
			Hides = function(name) return w.guildOff == true or w.hidden[c.Fold(c.FullName(name))] == true end,
			IsIssuer = function(name) return w.issuers[c.Fold(c.FullName(name))] == true end,
			IsKing = function(name) return w.king ~= nil and c.Fold(c.FullName(name)) == c.Fold(w.king) end,
			SelfOff = function() return w.selfOff end,
			TargetRank = function(name) return w.targetRanks and w.targetRanks[c.Fold(c.FullName(name))] or 0 end,
			Rank = function(name) return w.targetRanks and w.targetRanks[c.Fold(c.FullName(name))] or 0 end,
			Lines = function() return { { text = "existing moderation" } } end,
		}
		c.Authority = {
			Enforced = function() return w.enforced == true end,
			Manifest = function() return w.manifest end,
			Rank = function(name, guild)
				local e = w.signed[c.Fold(c.FullName(name))]
				if not e or c.Fold(e.guild or w.guild) ~= c.Fold(guild) then return nil end
				return e.rank, e.source or "signed"
			end,
		}
		c.Alts = { Linked = function(name) return w.links[c.Fold(c.FullName(name))] or {} end }
		c.Filter = {
			Hit = function() return w.filterHit end,
			SharedOn = function() return w.sharedOn ~= false end,
			SetSharedOn = function(on) w.sharedOn = on end,
			Status = function() w.filterStatus = true return true end,
		}
		w.courtLine = { text = "existing court", font = "QuestFont" }
		c.Court = {
			HomeLines = function() return { w.courtLine } end,
			Toggle = function() w.courtToggled = true end,
			Holding = function() return false end,
		}
		c.King = { IsKing = function() return false end, Preview = function() return false end }
		-- 1.2: The Watch's Tabards (TabardsV2.SurfaceVisible: the King's fresh publication, an
		-- officer's own patrols) and the author's View as (ViewAs.lua), as this world sets them, not
		-- the harness's namespace (its roster and characters are another world's).
		c.TabardsV2 = { SurfaceVisible = function() return w.tabards == true end,
			-- (1.2: the King's client on now, Judgment.lua's way to it: w.lease.)
			Collector = function() return w.lease end }
		-- 1.2: the High Council's signed names (w.council) and the King's character (w.king).
		c.IsHighCouncillor = function(name) return w.council ~= nil and w.council[c.Fold(c.FullName(name))] == true end
		c.IsKingCharacter = function(name) return w.king ~= nil and type(name) == "string" and c.Fold(c.FullName(name)) == c.Fold(w.king) end
		c.KingCharacter = function() return w.king and (w.king:gsub("%-.*$", "")) or nil end
		c.ViewAs = { Available = function() return w.author ~= nil end, Role = function() return w.author or "my" end,
			Allows = function(page) return w.allows ~= nil and w.allows[page] == true end }

		local initial = { "census", "treasury", "throne", "vox" }
		c.UI = { TABS = {} }
		for _, key in ipairs(initial) do c.UI.TABS[#c.UI.TABS + 1] = { key = key } end
		c.UI.AddTab = function(spec)
			w.tab = spec
			local at = #c.UI.TABS + 1
			for i, entry in ipairs(c.UI.TABS) do if spec.after == entry.key then at = i + 1 end end
			table.insert(c.UI.TABS, at, { key = spec.key })
			return true
		end
		c.UI.SelectTab = function(key) w.selected = key end
		c.UI.ShowCopy = function(title, text) w.copied = { title = title, text = text } end

		c.Comm = {
			-- (1.1.6: The Watch registers MR, the players' reports, after MW.)
			Handle = function(kind, call)
				w.handlers[kind] = call
				if not w.handlerKind then w.handlerKind, w.handler = kind, call end
			end,
			QueueRoom = function() return w.queueRoom end,
			DeliveredLogged = function() return w.logged end,
			Whisper = function(target, message, _, _, logged, done, options)
				if w.rejectWhisper then if done then done(false, "full") end return false end
				w.jobs[#w.jobs + 1] = { target = target, msg = message, dist = "WHISPER",
					logged = logged, done = done, options = options }
				return true
			end,
			CancelQueued = function(owner, key, why)
				local kept, dropped = {}, {}
				for _, job in ipairs(w.jobs) do
					if job.options and job.options.owner == owner and job.options.key == key then dropped[#dropped + 1] = job
					else kept[#kept + 1] = job end
				end
				w.jobs = kept
				for _, job in ipairs(dropped) do if job.done then job.done(false, why or "cancelled") end end
				return #dropped
			end,
		}

		function w.setRank(name, rank)
			name = c.FullName(name)
			c.Roster.byName[name] = rank
			if name == c.me then w.myRank = rank end
		end
		function w.refreshRoster()
			c.Roster.guild, c.Roster.group, c.Roster.faction = w.guild, c.group, c.faction
			c.Roster.complete = true
			c.Roster.snapshotAt = w.epoch
			c.Roster.generation = c.Roster.generation + 1
		end
		function w.online(...)
			c.Roster.online = {}
			for _, name in ipairs({ ... }) do c.Roster.online[#c.Roster.online + 1] = { name = c.FullName(name), online = true } end
		end
		function w.finish(job, sent)
			local allowed, why = true, nil
			if job.options and job.options.permit then
				allowed, why = job.options.permit(job.options.owner, job.options.key, job.dist, job.target, job.msg)
			end
			if job.done then job.done(allowed == true and sent ~= false, why) end
			return allowed, why
		end
		function w.wire(op, target, seq, at, reason, untilAt, guild, group, faction)
			return assert(c.Watch.Wire({ op = op, name = c.FullName(target), seq = seq, at = at or w.epoch,
				reason = reason or "reason", untilAt = untilAt or 0, guild = guild or w.guild,
				group = group or c.group, faction = faction or c.faction }))
		end

		assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", c)
		-- (1.2: the Judgments after it, as the TOC loads them.)
		assert(loadfile(ROOT .. "Olympus/Judgment.lua"))("Olympus", c)
		w.ns, w.Watch, w.Judgment = c, c.Watch, c.Judgment
		c.Watch.ResetForTests()
		c.Judgment.ResetForTests()
		fn(w, c.Watch, c)
	end)

	for _, name in ipairs(globals) do _G[name] = saved[name] end
	for _, name in ipairs(dialogNames) do StaticPopupDialogs[name] = savedDialogs[name] end
	if not ok then error(err, 0) end
end

test("watch: member page offers private personal restrictions and reports without opening staff controls", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		eq(W.TabVisible(), false, "personal report pages do not grant the staff tab")
		eq(W.PageId(), "member"); eq(W.ViewKey(), "judgments", "no officer toolbar")
		c.WatchChat = { Sanction = function() return nil end, RecordLines = function() return {} end }
		local lines = W.Build()
		eq(#lines[1].nav, 1); eq(lines[1].nav[1].text, ns.L.WATCH_MEMBER_NAV)
		local report, review
		for _, l in ipairs(lines) do
			if l.id == "watch-report-person" then report = l end
			if l.id == "watch-personal-review" then review = l end
		end
		assert(report and report.onClick); eq(review, nil, "no review needed without a restriction")
		report.onClick(); eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_REPORT_PERSON")
		W.Show("reports"); eq(W.PageId(), "member", "stale privileged section fails closed")
		eq(W.CanRead(), false); eq(W.CanManage(), false)
		w.author, w.allows = "member", {}
		local before = #w.dialogs
		report.onClick(); eq(#w.dialogs, before, "a stale report button cannot act in preview")
		local ok = W.SendReport("Writer-Realm", "A", "reason")
		eq(ok, false, "preview cannot send a report by direct call")
		w.author, w.allows, w.member = nil, nil, false
		eq(W.TabVisible(), false, "not an Olympus member")
	end)
end)

test("watch: report a selected public message keeps its exact evidence and refuses stale or private selections", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		local selected = { sender = "Writer-Realm", t = w.epoch - 10, text = "selected public words", tier = "A" }
		w.chat.A = { selected }
		for i = 1, 5 do w.chat.A[#w.chat.A + 1] = { sender = selected.sender, t = w.epoch - i, text = "newer words " .. i } end
		w.chat.C = { { sender = "Captain-Realm", t = w.epoch, text = "private words" } }
		local rows = W.ReportMessages()
		eq(#rows, 6, "public channel only")
		assert(W.AskReport(selected.sender, selected))
		local data = w.dialogs[#w.dialogs].data
		StaticPopupDialogs.OLYMPUS_WATCH_REPORT_WHAT.OnAccept(nil, data)
		local preview = w.dialogs[#w.dialogs]
		assert(preview.b:find(selected.text, 1, true), "exact selected line shown before send")
		local ok = W.SendReport(selected.sender, "A", "selected", preview.data.message)
		assert(ok)
		eq(W.Book(false).outbox[1].lines[1].text, selected.text, "exact selected line in queued report")
		w.chat.A = {}
		eq(W.AskReport(selected.sender, selected), false, "line no longer available")
		eq(W.AskReport("Captain-Realm", { sender = "Captain-Realm", t = w.epoch, text = "private words", tier = "C" }), false)
	end)
end)

test("watch: tab is Treasury > The Watch > Throne and reuses Court and Moderation", function()
	WithWatch(function(w, W, c)
		eq(w.handlerKind, "MW"); assert(w.handlers.MR, "and the players' reports (1.1.6)")
		eq(w.tab.key, "watch"); eq(w.tab.after, "treasury")
		eq(w.tab.icon, "Interface\\Icons\\INV_Misc_Eye_01")
		local order = {}
		for _, entry in ipairs(c.UI.TABS) do order[#order + 1] = entry.key end
		eq(table.concat(order, ","), "census,treasury,watch,throne,vox")
		local lines = W.Build()
		local court, moderation = false, false
		for _, line in ipairs(lines) do
			if line.text == "existing court" then court = true; eq(line.font, nil, "Watch drops parchment ink from its cloned Court row") end
			if line.text == "existing moderation" then moderation = true end
		end
		eq(court, true); eq(moderation, true)
		eq(w.courtLine.font, "QuestFont", "the source Court row is not mutated")
		for _, button in ipairs(w.tab.buttons) do assert(button[1] ~= "COURT_BTN", "Hold Court stays on the Throne") end
		eq(w.tab.buttons[2][1], "WATCH_WATCH_BTN", "the Watch action uses the canonical locale key")
	end)
	local king = assert(io.open(ROOT .. "Olympus/King.lua", "rb")):read("*a")
	local views = assert(io.open(ROOT .. "Olympus/Views.lua", "rb")):read("*a")
	local ui = assert(io.open(ROOT .. "Olympus/UI.lua", "rb")):read("*a")
	assert(not king:find("Court and ns.Court.HomeLines", 1, true), "Throne no longer renders the Court queue")
	assert(views:find("ns.Moderation.Lines", 1, true), "Decrees keeps member-visible net-off and SelfOff disclosure")
	assert(ui:find('{ "COURT_BTN", function() ns.Court.Toggle()', 1, true), "Hold Court remains a Throne button")
end)

test("watch: only live local GM/Captains or a live signed roster moderator have access", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		eq(W.CanRead(), false)
		eq(#W.Records(), 0); eq(#W.Audit(), 0)
		local hidden, _, detail = W.Build()
		eq(#hidden[1].nav, 1); eq(detail, ns.L.WATCH_MEMBER_DETAIL, "forcing the builder opens only personal rows")
		local ok, why = W.Warn("Member-Realm", "reason")
		eq(ok, false); eq(why, "access")
		w.setRank(c.me, 1); eq(W.CanRead(), true, "Captain from the live roster")
		eq(W.TabVisible(), true, "a Captain keeps the staff tab")
		w.guildOff = true; eq(W.CanRead(), false, "a moderation word on the guild fails closed")
		w.guildOff = false
		w.setRank(c.me, 0); eq(W.CanRead(), true, "GM from the live roster")
		eq(W.TabVisible(), true, "a guild master keeps the staff tab")

		w.setRank(c.me, 3)
		w.issuers[c.Fold(c.me)] = true
		w.signed[c.Fold(c.me)] = { guild = w.guild, rank = 1 }
		eq(W.CanRead(), false, "a published role alone cannot activate authority")
		w.enforced = true
		eq(W.CanRead(), false, "sticky enforcement without a valid manifest fails closed")
		w.manifest = { epoch = 1 }
		eq(W.CanRead(), true, "signed moderator still in the same live roster")
		eq(W.TabVisible(), true, "a valid signed roster moderator keeps the staff tab")
		w.setRank("Ordinary-Realm", 3); w.online(c.me)
		assert(W.Warn("Ordinary-Realm", "moderator action"), "a signed moderator can act on an ordinary same-rank member")
		w.setRank("Captain-Realm", 1)
		local allowed, rankWhy = W.Warn("Captain-Realm", "not allowed")
		eq(allowed, false); eq(rankWhy, "rank", "a signed moderator cannot act on a Captain")
		w.signed[c.Fold(c.me)].source = "census"
		eq(W.CanRead(), false, "a census source is never accepted")
		w.signed[c.Fold(c.me)].source = "signed"
		c.Roster.byName[c.me] = nil
		eq(W.CanRead(), true, "the player's live GetGuildInfo rank, not a stale self row, is authoritative")
		w.guild = nil
		eq(W.CanRead(), false, "leaving the live guild revokes the signed role")
	end)
end)

test("watch: private stores are isolated by faction, realm group and exact guild identity", function()
	WithWatch(function(w, W, c)
		-- Ambiguous account-wide data from the first implementation is deliberately not migrated.
		c.db.watchGuilds = { [c.Fold(w.guild)] = { records = { leak = { name = "Leak-Realm" } } } }
		w.setRank("AllianceTarget-Realm", 3); w.online(c.me)
		assert(W.Mark("AllianceTarget-Realm", "alliance only"))
		local allianceRdb = c.rdb
		assert(W.Record("AllianceTarget-Realm") and c.db.watchGuilds[c.Fold(w.guild)].records.leak)
		local allianceStore = assert(W.Store(false))
		eq(allianceStore.guild, w.guild); eq(allianceStore.group, "RealmGroup"); eq(allianceStore.faction, "Alliance")

		c.faction, c.rdb = "Horde", {}
		w.refreshRoster()
		eq(W.Record("AllianceTarget-Realm"), nil, "same guild name on the other faction sees no private rows")
		w.setRank("HordeTarget-Realm", 3)
		assert(W.Mark("HordeTarget-Realm", "horde only"))
		assert(W.Record("HordeTarget-Realm")); assert(allianceStore.records[c.Fold("AllianceTarget-Realm")])
		assert(allianceRdb.watchGuilds and next(allianceRdb.watchGuilds), "the Alliance store remains separate")

		c.group, c.rdb = "OtherRealmGroup", {}
		w.refreshRoster()
		eq(W.Record("HordeTarget-Realm"), nil, "same guild and faction on another realm group is isolated")
		-- A mismatched/corrupt identity in the right rdb is quarantined, never merged.
		local ambiguous = {
			version = 2, guild = w.guild, group = "Wrong", faction = c.faction,
			records = { [c.Fold("Wrong-Realm")] = { name = "Wrong-Realm", warnings = 1, interventions = 1 } },
		}
		c.rdb.watchGuilds = { [c.Fold(w.guild)] = ambiguous }
		eq(W.Store(false), nil)
		w.setRank("Fresh-Realm", 3)
		assert(W.Mark("Fresh-Realm", "fresh identity"))
		eq(W.Record("Wrong-Realm"), nil)
		local exact = W.Store(false)
		eq(exact.group, "OtherRealmGroup")
		exact.group = "Wrong"
		eq(W.Store(false), nil, "the store's embedded identity is validated on every read")
		exact.group = "OtherRealmGroup"
		eq(W.Store(false), exact)
		eq(c.rdb.watchGuilds[c.Fold(w.guild)], ambiguous, "ambiguous data is neither migrated nor overwritten")
	end)
end)

test("watch: live self rank and exact fresh roster fail closed across demotion and guild changes", function()
	WithWatch(function(w, W, c)
		w.setRank("OtherOfficer-Realm", 1); w.setRank("Target-Realm", 3)
		w.online("OtherOfficer-Realm")
		eq(W.IsAuthorized("OtherOfficer-Realm"), true)
		w.epoch = w.epoch + W.ROSTER_FRESH + 1
		eq(W.IsAuthorized("OtherOfficer-Realm"), false, "an expired remote roster row grants nothing")
		eq(#W.Recipients(), 0)
		local ok, why = W.Warn("Target-Realm", "stale roster")
		eq(ok, false); eq(why, "roster")

		w.refreshRoster()
		c.Roster.complete = false
		eq(W.IsAuthorized("OtherOfficer-Realm"), false, "a partial roster generation grants nothing")
		ok, why = W.Warn("Target-Realm", "partial roster")
		eq(ok, false); eq(why, "roster")
		w.refreshRoster()
		assert(W.Warn("Target-Realm", "queued while fresh")); eq(#w.jobs, 1)
		w.epoch = w.epoch + W.ROSTER_FRESH + 1
		local allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "freshness is checked again at the game send")

		w.refreshRoster(); w.jobs = {}
		w.myRank = 3 -- leave the cached self row deliberately stale at GM
		eq(W.CanRead(), false, "GetGuildInfo immediately revokes the local actor")
		w.myRank = 0
		w.guild = "Olympus III" -- cached roster still declares Olympus II
		eq(W.CanRead(), true, "the live GM may see the new guild's empty private store")
		eq(W.IsAuthorized("OtherOfficer-Realm"), false)
		eq(#W.Recipients(), 0, "old-guild officers are never recipients")
		ok, why = W.Warn("Target-Realm", "wrong guild snapshot")
		eq(ok, false); eq(why, "roster")
	end)
end)

test("watch: queued logged whispers revalidate actor, guild and recipient at actual send", function()
	WithWatch(function(w, W, c)
		w.setRank("Target-Realm", 3)
		w.setRank("OtherOfficer-Realm", 1)
		w.online(c.me, "OtherOfficer-Realm", "Target-Realm")
		local ok, why = W.Warn("Target-Realm", "first warning")
		eq(ok, true); eq(why, "queued"); eq(#w.jobs, 1)
		eq(w.jobs[1].logged, true); eq(w.jobs[1].target, "OtherOfficer-Realm")
		eq(W.Record("Target-Realm"), nil, "local state waits for a real send")
		ok, why = W.Warn("Target-Realm", "duplicate while pending")
		eq(ok, false); eq(why, "pending"); eq(#w.jobs, 1)
		w.setRank(c.me, 3)
		local allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked")
		w.jobs = {}; w.setRank(c.me, 0)

		assert(W.Warn("Target-Realm", "second try")); eq(#w.jobs, 1)
		w.setRank("OtherOfficer-Realm", 3)
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "recipient demotion also revokes")
		w.jobs = {}; w.setRank("OtherOfficer-Realm", 1)

		assert(W.Warn("Target-Realm", "third try")); eq(#w.jobs, 1)
		w.setRank("Target-Realm", 0)
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "a target promoted while queued is protected")
		w.jobs = {}; w.setRank("Target-Realm", 3)

		assert(W.Warn("Target-Realm", "net-off boundary")); eq(#w.jobs, 1)
		w.guildOff = true
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "net-off is rechecked at the real send")
		w.jobs = {}; w.guildOff = false

		assert(W.Warn("Target-Realm", "guild boundary")); eq(#w.jobs, 1)
		w.guild = "Olympus III"; w.refreshRoster()
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "a live guild move revokes the queued capability")
		w.jobs = {}; w.guild = "Olympus II"; w.refreshRoster()

		assert(W.Warn("Target-Realm", "realm-group boundary")); eq(#w.jobs, 1)
		local oldRdb = c.rdb
		c.group, c.rdb = "OtherRealmGroup", {}; w.refreshRoster()
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, false); eq(permitWhy, "revoked", "a realm-store switch cannot carry a queued private write")
		w.jobs = {}; c.group, c.rdb = "RealmGroup", oldRdb; w.refreshRoster()

		assert(W.Warn("Target-Realm", "delivered")); eq(#w.jobs, 1)
		allowed, permitWhy = w.finish(w.jobs[1])
		eq(allowed, true); eq(permitWhy, nil)
		eq(W.Record("Target-Realm").warnings, 1)
		eq(#W.Audit(), 1)
	end)
end)

test("watch: spoofed, unlogged, malformed, oversized and replayed writes fail closed", function()
	WithWatch(function(w, W, c)
		w.setRank("Target-Realm", 3)
		w.setRank("OtherOfficer-Realm", 1)
		local valid = w.wire("V", "Target-Realm", 2, w.epoch, "seen")
		local function Reject(expected, dist, sender, message, label)
			local accepted, why = W.Handle(dist, sender, message)
			eq(accepted, false, label); eq(why, expected, label)
		end
		Reject("access", "CHANNEL", "OtherOfficer-Realm", valid, "wrong distribution")
		w.logged = false
		Reject("unlogged", "WHISPER", "OtherOfficer-Realm", valid, "unlogged")
		w.logged = true
		Reject("sender", "WHISPER", "Outsider-Realm", valid, "unauthorized sender")
		local newerVersion = valid:gsub("^MW~1~", "MW~2~")
		Reject("shape", "WHISPER", "OtherOfficer-Realm", newerVersion, "unknown version")
		Reject("size", "WHISPER", "OtherOfficer-Realm", valid .. string.rep("x", 256), "oversized")
		Reject("shape", "WHISPER", "OtherOfficer-Realm", nil, "non-string payload")
		local badReason = valid:gsub("seen$", "bad|reason")
		Reject("reason", "WHISPER", "OtherOfficer-Realm", badReason, "non-canonical reason")
		Reject("guild", "WHISPER", "OtherOfficer-Realm",
			w.wire("V", "Target-Realm", 3, w.epoch, "wrong guild", 0, "Olympus III"), "wrong guild")
		Reject("identity", "WHISPER", "OtherOfficer-Realm",
			w.wire("V", "Target-Realm", 3, w.epoch, "wrong faction", 0, nil, nil, "Horde"), "wrong faction store")
		Reject("sequence", "WHISPER", "OtherOfficer-Realm",
			w.wire("V", "Target-Realm", W.MAX_SEQ, w.epoch, "poison"), "a max-sequence replay poison is impossible")
		assert(W.Handle("WHISPER", "OtherOfficer-Realm", valid))
		Reject("replay", "WHISPER", "OtherOfficer-Realm", valid, "replay")
		Reject("replay", "WHISPER", "OtherOfficer-Realm", w.wire("V", "Target-Realm", 1, w.epoch, "older"), "out of order")
		eq(W.Record("Target-Realm").status, "watch")
		local store = W.Store(true)
		store.seen[c.Fold(c.me)] = { seq = w.epoch - W.SEQ_EPOCH + W.SEQ_SLOP, at = w.epoch }
		w.setRank("FreshTarget-Realm", 3); w.online(c.me)
		assert(W.Warn("FreshTarget-Realm", "bounded floor"), "a bounded recovered floor cannot permanently poison local sending")
	end)
end)

test("watch: private paged recovery converges atomically and rejects partial, stale or spliced snapshots", function()
	local rows, stamp
	WithWatch(function(w, W, c)
		w.setRank("Listed-Realm", 3); w.setRank("Cleared-Realm", 3); w.online(c.me)
		assert(W.Mark("Listed-Realm", "review term"))
		assert(W.Warn("Listed-Realm", "first warning"))
		assert(W.Mark("Cleared-Realm", "temporary")); assert(W.Warn("Cleared-Realm", "one"))
		assert(W.Warn("Cleared-Realm", "two")); assert(W.ActiveTimeout("Cleared-Realm"))
		assert(W.Clear("Cleared-Realm"))
		rows, stamp = assert(W.SnapshotRows()), w.epoch
		assert(#rows > 3 and #rows <= W.SYNC_MAX_ROWS)
	end)

	WithWatch(function(w, W, c)
		w.setRank("OtherOfficer-Realm", 1); w.setRank("ThirdOfficer-Realm", 1)
		w.online("OtherOfficer-Realm", "ThirdOfficer-Realm")
		local ok, nonce = W.AskSync(true)
		eq(ok, true)
		assert(nonce and w.jobs[1].msg == ("MW~1~Q~%s~0~%s~%s~%s"):format(nonce, w.guild, c.group, c.faction),
			"the recovery query declares its complete private-store identity")
		local function Page(index, at)
			local cursor, nextCursor = index - 1, index < #rows and index or 0
			local msg = ("MW~1~S~%s~%d~%d~%d~%d~%s~%s~%s^%s"):format(nonce, at or stamp,
				cursor, nextCursor, #rows, w.guild, c.group, c.faction, rows[index])
			assert(#msg <= W.MESSAGE_MAX, "single recovery row exceeds the private transport")
			return msg
		end

		local accepted, why = W.Handle("WHISPER", "OtherOfficer-Realm", Page(1, stamp - 1))
		eq(accepted, false); eq(why, "stale", "a snapshot predating the request is rejected")
		assert(W.Handle("WHISPER", "OtherOfficer-Realm", Page(1)))
		eq(W.Record("Listed-Realm"), nil, "a partial snapshot changes no observable state")
		local jobs = #w.jobs
		assert(W.RetrySync(nonce)); eq(#w.jobs, jobs + 1, "a lost next-page query can be retried")

		accepted, why = W.Handle("WHISPER", "ThirdOfficer-Realm", Page(2))
		eq(accepted, false); eq(why, "stale", "pages cannot be spliced from another officer")
		accepted, why = W.Handle("WHISPER", "OtherOfficer-Realm", Page(2, stamp + 1))
		eq(accepted, false); eq(why, "stale", "one recovery is frozen at one snapshot stamp")
		for i = 2, #rows do
			local pageOK, pageWhy = W.Handle("WHISPER", "OtherOfficer-Realm", Page(i))
			assert(pageOK, tostring(pageWhy) .. " at recovery row " .. tostring(i) .. ": " .. tostring(rows[i]))
		end
		local record = assert(W.Record("Listed-Realm"))
		eq(record.status, "watch"); eq(record.warnings, 1); eq(record.interventions, 2)
		eq(record.lastVia, "OtherOfficer-Realm", "recovered provenance names the relay")
		local cleared = assert(W.Record("Cleared-Realm"))
		eq(cleared.status, nil); eq(cleared.warnings, 0); eq(cleared.interventions, 4, "clear tombstones converge")
		eq(W.ActiveTimeout("Cleared-Realm"), nil, "the clear timeout tombstone converges")
		eq(#W.Audit(), 6, "the restricted audit converges with the list")
		eq(W.Audit()[1].via, "OtherOfficer-Realm", "a relay cannot invisibly impersonate the original audit writer")
		eq(W.SyncPending(nonce), nil)
		accepted, why = W.Handle("WHISPER", "OtherOfficer-Realm", Page(#rows))
		eq(accepted, false); eq(why, "stale", "a completed page cannot be replayed")

		local movedOK, movedNonce = W.AskSync(true)
		eq(movedOK, true)
		local oldGuild, oldGroup, oldFaction = w.guild, c.group, c.faction
		w.guild = "Olympus III"; w.refreshRoster()
		local moved = ("MW~1~S~%s~%d~0~1~%d~%s~%s~%s^%s"):format(movedNonce, stamp, #rows,
			oldGuild, oldGroup, oldFaction, rows[1])
		accepted, why = W.Handle("WHISPER", "ThirdOfficer-Realm", moved)
		eq(accepted, false); eq(why, "stale", "an in-flight snapshot cannot cross into another guild")
		eq(W.Record("Listed-Realm"), nil, "the other guild's store remains empty")
	end)
end)

test("watch: recovery is bounded by the authenticated relay and quarantines claimed provenance", function()
	local rows, stamp
	WithWatch(function(w, W, c)
		-- A GM may legitimately act on a Captain. A later Captain relay must not be able to use
		-- that frozen state to exercise the GM's greater authority on another client.
		w.setRank("Protected-Realm", 1); w.online(c.me)
		assert(W.Mark("Protected-Realm", "review by the guild master"))
		rows, stamp = assert(W.SnapshotRows()), w.epoch
	end)

	local function Recover(relay, relayRank, expected)
		WithWatch(function(w, W, c)
			w.setRank(relay, relayRank); w.setRank("Protected-Realm", 1); w.online(relay)
			local ok, nonce = W.AskSync(true)
			eq(ok, true)
			local function Page(index)
				local cursor, nextCursor = index - 1, index < #rows and index or 0
				return ("MW~1~S~%s~%d~%d~%d~%d~%s~%s~%s^%s"):format(nonce, stamp,
					cursor, nextCursor, #rows, w.guild, c.group, c.faction, rows[index])
			end
			local finalOK, finalWhy
			for i = 1, #rows do finalOK, finalWhy = W.Handle("WHISPER", relay, Page(i)) end
			if not expected then
				eq(finalOK, false); eq(finalWhy, "authority", "a Captain cannot relay a GM-only target")
				eq(W.Record("Protected-Realm"), nil, "the complete rejected snapshot is atomic")
				eq(#W.Audit(), 0)
				return
			end

			eq(finalOK, true)
			local record = assert(W.Record("Protected-Realm"))
			eq(record.status, "watch")
			eq(record.statusBy, c.FullName(relay), "state tie-break provenance is the authenticated relay")
			eq(record.updatedBy, c.FullName(relay))
			eq(record.lastBy, c.FullName(relay))
			eq(record.lastVia, c.FullName(relay))
			local audit = W.Audit()
			eq(#audit, 1); eq(audit[1].by, c.FullName(relay)); eq(audit[1].via, c.FullName(relay))
			local store = W.Store(false)
			eq(store.seen[c.Fold("Officer-Realm")], nil,
				"a claimed actor's replay floor is not accepted as authority")

			local forwarded = table.concat(assert(W.SnapshotRows()), "\n")
			assert(not forwarded:find("Officer%-Realm"), "claimed provenance was laundered into the next snapshot")
			assert(forwarded:find(c.FullName(relay), 1, true), "the next hop names its authenticated relay")

			local shown = {}
			local tt = { AddLine = function(_, text) shown[#shown + 1] = tostring(text) end }
			local lines = W.Build()
			for _, line in ipairs(lines) do if line.tooltip then line.tooltip(tt) end end
			assert(not table.concat(shown, "\n"):find("Officer", 1, true),
				"the UI displayed an unauthenticated claimed actor")
		end)
	end

	Recover("OtherOfficer-Realm", 1, false)
	Recover("GuildMaster-Realm", 0, true)
end)

test("watch: recovery request and response capabilities revalidate both officers at send time", function()
	WithWatch(function(w, W, c)
		w.setRank("OtherOfficer-Realm", 1); w.online("OtherOfficer-Realm")
		local ok = W.AskSync(true)
		eq(ok, true); eq(#w.jobs, 1)
		w.myRank = 3 -- cached self row remains 0: only the live rank may decide
		local allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked")

		w.myRank = 0; w.jobs = {}; w.refreshRoster()
		assert(W.AskSync(true)); eq(#w.jobs, 1)
		w.guildOff = true
		allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked", "net-off is rechecked for a recovery query at the real send")
		w.guildOff = false; w.jobs = {}

		local accepted, rejected = W.Handle("WHISPER", "OtherOfficer-Realm",
			("MW~1~Q~776~0~%s~%s~Horde"):format(w.guild, c.group))
		eq(accepted, false); eq(rejected, "identity", "a cross-faction officer cannot recover this faction's store")
		eq(#w.jobs, 0)
		assert(W.Handle("WHISPER", "OtherOfficer-Realm",
			("MW~1~Q~777~0~%s~%s~%s"):format(w.guild, c.group, c.faction)))
		eq(#w.jobs, 1); assert(w.jobs[1].msg:find("MW~1~S~777~", 1, true))
		w.setRank("OtherOfficer-Realm", 3)
		allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked", "a demoted requester receives no private page")

		w.setRank("OtherOfficer-Realm", 1); w.jobs = {}; w.refreshRoster()
		local oldGroup, oldFaction = c.group, c.faction
		assert(W.Handle("WHISPER", "OtherOfficer-Realm",
			("MW~1~Q~778~0~%s~%s~%s"):format(w.guild, oldGroup, oldFaction)))
		c.group, c.rdb = "OtherRealmGroup", {}; w.refreshRoster()
		allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked", "a responder never carries an old realm-group snapshot across the boundary")
		local before = #w.jobs
		local resumed, resumeWhy = W.Handle("WHISPER", "OtherOfficer-Realm",
			("MW~1~Q~778~0~%s~%s~%s"):format(w.guild, oldGroup, oldFaction))
		eq(resumed, false); eq(resumeWhy, "identity", "an old responder session cannot resume in the new realm group")
		eq(#w.jobs, before)
	end)
end)

test("watch: warnings escalate, timeout expires, and every applied manual action is audited", function()
	WithWatch(function(w, W, c)
		w.setRank("Target-Realm", 3)
		w.online(c.me)
		assert(W.Warn("Target-Realm", "one"))
		eq(W.ActiveTimeout("Target-Realm"), nil)
		-- (1.1.6, Daniel 2026-10-05: the High Council's ladder is a warning, then 1 hour, 24 hours and
		-- 7 days; it was 5 minutes, 30 minutes and 24 hours.)
		assert(W.Warn("Target-Realm", "two"))
		eq(W.ActiveTimeout("Target-Realm"), W.Record("Target-Realm").lastAt + 3600)
		w.epoch = w.epoch + 3601
		w.refreshRoster()
		eq(W.ActiveTimeout("Target-Realm"), nil, "the timeout is not permanent")
		assert(W.Warn("Target-Realm", "three"))
		eq(W.ActiveTimeout("Target-Realm"), w.epoch + 86400)
		assert(W.Mark("Target-Realm", "manual watch"))
		assert(W.Clear("Target-Realm"))
		local record = W.Record("Target-Realm")
		eq(record.warnings, 0, "Clear resets the warning ladder"); eq(record.interventions, 5); eq(record.status, nil)
		w.setRank("OtherOfficer-Realm", 1)
		local oldWarning = w.wire("W", "Target-Realm", 2, record.lastAt - 1, "arrived after its clear")
		assert(W.Handle("WHISPER", "OtherOfficer-Realm", oldWarning))
		record = W.Record("Target-Realm")
		eq(record.warnings, 0, "an out-of-order warning older than Clear stays cleared")
		eq(#W.Audit(), 6, "the late manual action remains in the audit even when its state is obsolete")
	end)
end)

test("watch: warning ladders decay or clear, and the soft cap never blocks a new target", function()
	WithWatch(function(w, W, c)
		w.online(c.me)
		w.setRank("Decay-Realm", 3)
		assert(W.Warn("Decay-Realm", "old first")); eq(W.Record("Decay-Realm").warnings, 1)
		w.epoch = w.epoch + W.WARNING_KEEP + 1; w.refreshRoster(); W.Prune()
		eq(W.Record("Decay-Realm").warnings, 0, "an old warning no longer escalates forever")
		assert(W.Warn("Decay-Realm", "new first")); eq(W.ActiveTimeout("Decay-Realm"), nil)

		w.setRank("Cleared-Realm", 3)
		assert(W.Warn("Cleared-Realm", "one")); assert(W.Warn("Cleared-Realm", "two"))
		assert(W.ActiveTimeout("Cleared-Realm"))
		assert(W.Clear("Cleared-Realm"))
		eq(W.Record("Cleared-Realm").warnings, 0); eq(W.ActiveTimeout("Cleared-Realm"), nil)

		w.setRank("Protected-Realm", 3)
		assert(W.Mark("Protected-Realm", "active status"))
		for i = 1, W.MAX_RECORDS + 5 do
			local name = "History" .. tostring(i) .. "-Realm"
			w.setRank(name, 3)
			w.epoch = w.epoch + 1; w.refreshRoster()
			assert(W.Warn(name, "bounded history"), name)
		end
		assert(W.Record("History" .. tostring(W.MAX_RECORDS + 5) .. "-Realm"), "the 201st+ target is accepted")
		eq(W.Record("Protected-Realm").status, "watch", "active rows are never evicted for the soft cap")
		assert(#W.Records() > W.MAX_RECORDS, "live warning ladders may temporarily exceed the soft cap instead of being discarded")

		w.epoch = w.epoch + W.KEEP + 1; w.refreshRoster(); W.Prune()
		eq(W.Record("Protected-Realm").status, "watch", "active status survives age pruning")
		assert(#W.Records() <= W.MAX_RECORDS, "decayed inactive history is pruned back to the soft cap")
		assert(#W.Audit() >= W.MIN_AUDIT, "a minimum audit tail survives age pruning")
	end)
end)

test("watch: offensive-language matches redact locally and never create punishment", function()
	WithWatch(function(w, W, c)
		w.filterHit = "term"
		local shown, hit = W.FilterText("one term here")
		eq(shown, ns.L.FILTER_WORDS_HIDDEN_SHORT); eq(hit, "term")
		eq(#W.Records(), 0); eq(#W.Audit(), 0); eq(#w.jobs, 0)
		w.setRank("Target-Realm", 3); w.online(c.me)
		assert(W.Mark("Target-Realm", "one term here"))
		local records, audit = #W.Records(), #W.Audit()
		local hidden = 0
		for _, line in ipairs((W.Build())) do
			if line.tooltip then
				local tt = { lines = {} }
				function tt:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
				line.tooltip(tt)
				if table.concat(tt.lines, "\n"):find(ns.L.FILTER_WORDS_HIDDEN_SHORT, 1, true) then hidden = hidden + 1 end
			end
		end
		assert(hidden >= 2, "both the record and audit render the censored reason")
		eq(#W.Records(), records); eq(#W.Audit(), audit, "render-time filtering creates no intervention")
		w.filterHit = nil
		eq(W.FilterText("ordinary line"), "ordinary line")
	end)
end)

test("watch: join alerts use only direct records or confirmed alt links and never reject", function()
	WithWatch(function(w, W, c)
		w.setRank("Listed-Realm", 3); w.setRank("Applicant-Realm", 3); w.setRank("Unlinked-Realm", 3)
		w.online(c.me)
		assert(W.Mark("Listed-Realm", "manual review"))
		local audit = #W.Audit()
		local entry, matched, alt = W.EntryAttempt("Listed-Realm")
		eq(entry.status, "watch"); eq(matched, "Listed-Realm"); eq(alt, false)
		w.links[c.Fold("Applicant-Realm")] = { "Listed-Realm" }
		entry, matched, alt = W.EntryAttempt("Applicant-Realm")
		eq(entry.status, "watch"); eq(matched, "Listed-Realm"); eq(alt, true)
		eq(W.EntryAttempt("Unlinked-Realm"), nil)
		eq(#W.Attempts(), 2); eq(#W.Audit(), audit, "notifications never mutate punishment state")
		eq(#w.jobs, 0, "a join alert neither rejects nor transmits an action")
	end)
end)

test("watch: ban-list UI requires a second human confirmation and rechecks authority", function()
	WithWatch(function(w, W, c)
		w.setRank("Target-Realm", 3); w.online(c.me)
		assert(W.Ask("ban", "Target-Realm"))
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_REASON")
		local reasonDef = StaticPopupDialogs.OLYMPUS_WATCH_REASON
		local data = w.dialogs[#w.dialogs].data
		local popup = { data = data, editBox = { GetText = function() return "confirmed reason" end } }
		reasonDef.OnAccept(popup, data)
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_BAN_CONFIRM")
		eq(W.Record("Target-Realm"), nil, "reason entry alone never applies the high-impact mark")
		local confirm = w.dialogs[#w.dialogs]
		w.setRank(c.me, 3)
		StaticPopupDialogs.OLYMPUS_WATCH_BAN_CONFIRM.OnAccept({ data = confirm.data }, confirm.data)
		eq(W.Record("Target-Realm"), nil, "authority revoked while the dialog is open fails closed")
		w.setRank(c.me, 0)
		assert(W.Ask("ban", "Target-Realm"))
		data = w.dialogs[#w.dialogs].data
		reasonDef.OnAccept({ data = data, editBox = { GetText = function() return "human confirmed" end } }, data)
		confirm = w.dialogs[#w.dialogs]
		StaticPopupDialogs.OLYMPUS_WATCH_BAN_CONFIRM.OnAccept({ data = confirm.data }, confirm.data)
		eq(W.Record("Target-Realm").status, "ban")
	end)
end)

test("watch: English and ptBR strings include the restricted and no-automatic-action promises", function()
	local oldLocale = GetLocale
	local pt = {}
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales.lua")), "Olympus", pt)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	eq(ns.L.TAB_WATCH, "The Watch"); eq(pt.L.TAB_WATCH, "The Watch")
	assert(ns.L.WATCH_SCOPE:find("never broadcast", 1, true))
	assert(ns.L.WATCH_FILTER_TIP:find("never punishes", 1, true))
	assert(ns.L.WATCH_BAN_CONFIRM:find("does not kick", 1, true))
	assert(pt.L.WATCH_SCOPE:find("nunca é transmitida", 1, true))
	assert(pt.L.WATCH_FILTER_TIP:find("nunca pune", 1, true))
	assert(pt.L.WATCH_BAN_CONFIRM:find("não expulsa", 1, true))
end)

---------------------------------------------------------------------------
-- 1.1.6: Report to Olympus, the Reports and Cases pages and the judgment card.
---------------------------------------------------------------------------

-- The menu a PlayerMenu build adds to: its buttons, as Wrap gives them.
local function FakeMenu()
	local m = { buttons = {} }
	function m.Button(text, fn, title, tip, enabled) m.buttons[#m.buttons + 1] = { text = text, fn = fn, tip = tip, enabled = enabled ~= false } end
	function m.Line() end
	return m
end

-- Stand-in widgets for the card (Olympus's own frame: font strings, buttons, show and hide).
local function FakeWidgets()
	local function Widget(kind, name)
		local o = { kind = kind, name = name, shown = true, scripts = {}, enabled = true }
		function o:Show() self.shown = true end
		function o:Hide() self.shown = false end
		function o:IsShown() return self.shown end
		function o:SetText(t) self.text = t end
		function o:GetText() return self.text end
		function o:SetScript(k, fn) self.scripts[k] = fn end
		function o:HookScript(k, fn) self.scripts["hook" .. k] = fn end
		function o:SetEnabled(on) self.enabled = on and true or false end
		function o:IsEnabled() return self.enabled end
		function o:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
		function o:GetName() return self.name end
		function o:CreateFontString() return Widget("FontString") end
		function o:CreateTexture() return Widget("Texture") end
		return setmetatable(o, { __index = function() return function() end end })
	end
	CreateFrame = function(kind, name) return Widget(kind, name) end
	UIParent = Widget("Frame", "UIParent")
end

local SPAMMER = "Spammer Guy-Realm"

-- A report as a reporter's client sends it, its messages.
local function ReportMessages(w, W, c, o)
	o = o or {}
	return assert(W.ReportWire({ seq = o.seq or 10, at = o.at or w.epoch, guild = o.guild or w.guild, group = c.group, faction = c.faction,
		cat = o.cat or "A", target = c.FullName(o.target or SPAMMER), note = o.note or "flooding the channel", lines = o.lines or {} }))
end

test("watch: Report to Olympus from the right-click menu: a category, a note and the player's own kept Olympus-channel lines, logged to the online officers only", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		w.setRank("Captain One-Realm", 1); w.setRank("Member Two-Realm", 3)
		w.online(c.me, "Captain One-Realm", "Member Two-Realm")
		eq(W.CanRead(), false, "an ordinary member")
		w.chat.A = {
			{ sender = SPAMMER, t = w.epoch - 200000, text = "too old to go" },
			{ sender = SPAMMER, t = w.epoch - 400, text = "first" },
			{ sender = SPAMMER, t = w.epoch - 300, text = "buy |cffffffff|Hitem:19019|h[Thunderfury]|h|r cheap~now" },
			{ sender = "Bystander-Realm", t = w.epoch - 250, text = "someone else's line" },
			{ sender = SPAMMER, t = w.epoch - 200, text = "third" },
			{ sender = SPAMMER, t = w.epoch - 100, text = "fourth" },
			{ sender = c.me, t = w.epoch - 50, text = "my own", mine = true },
		}
		w.chat.L = { { sender = SPAMMER, t = w.epoch - 90, text = "a Lords-channel line" } }
		eq(w.menu.key, "report"); eq(w.menu.order, 30)
		local menu = FakeMenu()
		w.menu.build({ name = SPAMMER }, menu)
		local b = assert(menu.buttons[1], "the line")
		eq(b.text, ns.L.WATCH_REPORT); eq(b.enabled, true); eq(b.tip, ns.L.WATCH_REPORT_TIP)
		local locked = FakeMenu()
		w.menu.build({ name = SPAMMER, locked = true }, locked)
		eq(locked.buttons[1].enabled, false, "greyed in a dungeon, a raid or a match"); eq(locked.buttons[1].tip, ns.L.PLAYERMENU_LOCKED)
		w.king = "King Guy-Realm"
		local king = FakeMenu()
		w.menu.build({ name = "King Guy-Realm" }, king)
		eq(#king.buttons, 0, "never on the King")

		-- The click: what it is about, then the preview with the note.
		b.fn()
		local what = w.dialogs[#w.dialogs]
		eq(what.which, "OLYMPUS_WATCH_REPORT_WHAT"); eq(what.data.name, SPAMMER)
		StaticPopupDialogs.OLYMPUS_WATCH_REPORT_WHAT.OnCancel({ data = what.data }, what.data, "clicked")
		local note = w.dialogs[#w.dialogs]
		eq(note.which, "OLYMPUS_WATCH_REPORT_NOTE"); eq(note.data.cat, "S", "the second answer: spam or scams")
		assert(note.b:find(ns.L.WATCH_REPORT_PREVIEW:format(ns.L.WATCH_REPORT_CAT_S, 3), 1, true), note.b)
		assert(note.b:find('"buy [Thunderfury] cheap now"', 1, true), "the link's text, no codes: " .. note.b)
		assert(note.b:find('"fourth"', 1, true) and note.b:find('"third"', 1, true))
		for _, absent in ipairs({ "first", "too old", "someone else", "my own", "Lords" }) do
			assert(not note.b:find(absent, 1, true), "not in the preview: " .. absent)
		end
		eq(#w.jobs, 0, "nothing sent before Send")
		StaticPopupDialogs.OLYMPUS_WATCH_REPORT_NOTE.OnAccept({ data = note.data, editBox = { GetText = function() return "gold ads | in /ol" end } }, note.data)
		eq(#w.jobs, 4, "the report and its three lines, to the one officer online")
		for _, job in ipairs(w.jobs) do
			eq(job.target, "Captain One-Realm", "officers only: never a member, never the reporter")
			eq(job.dist, "WHISPER"); eq(job.logged, true)
			assert(#job.msg <= W.MESSAGE_MAX)
		end
		local seq = w.jobs[1].msg:match("^MR~1~R~(%d+)~")
		eq(w.jobs[1].msg, ("MR~1~R~%s~%d~%s~%s~%s~S~%s~3~gold ads in /ol"):format(seq, w.epoch, w.guild, c.group, c.faction, SPAMMER))
		eq(w.jobs[2].msg, ("MR~1~E~%s~1~%d~A~buy [Thunderfury] cheap now"):format(seq, w.epoch - 300))
		eq(w.jobs[4].msg, ("MR~1~E~%s~3~%d~A~fourth"):format(seq, w.epoch - 100))
		assert(w.prints[#w.prints]:find(ns.L.WATCH_REPORT_SENT:format("Spammer Guy"), 1, true))
		-- Rechecked at the real send: an officer demoted while it waits gets nothing.
		w.setRank("Captain One-Realm", 3)
		local allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked")
		w.setRank("Captain One-Realm", 1)
		eq(W.Record(SPAMMER), nil, "a report is never a sanction")
		for _, job in ipairs(w.jobs) do assert(not job.msg:find("^MW~"), "no Watch action is sent") end
	end)
end)

-- 1.1.6: Olympus's chats are in English only, so "not in English" is a report of its own: the first
-- question's third answer, More, asks again between it and "something else" (Cancel too).
test("watch: Olympus's chats are in English only: More asks between not in English and something else; that report reaches the case as such", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3); w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm")
		w.chat.A = { { sender = SPAMMER, t = w.epoch - 100, text = "hola a todos, vendo oro" } }
		local WHAT, MORE, NOTE = StaticPopupDialogs.OLYMPUS_WATCH_REPORT_WHAT, StaticPopupDialogs.OLYMPUS_WATCH_REPORT_MORE, StaticPopupDialogs.OLYMPUS_WATCH_REPORT_NOTE
		eq(WHAT.button3, ns.L.WATCH_REPORT_CAT_MORE)
		assert(MORE, "the second question")
		eq(MORE.button1, ns.L.WATCH_REPORT_CAT_E); eq(MORE.button2, ns.L.WATCH_REPORT_CAT_O); eq(MORE.noCancelOnEscape, true, "only a click counts")
		assert(W.AskReport(SPAMMER))
		local what = w.dialogs[#w.dialogs]
		WHAT.OnAlt({ data = what.data }, what.data)
		local more = w.dialogs[#w.dialogs]
		eq(more.which, "OLYMPUS_WATCH_REPORT_MORE", "More asks again"); eq(more.a, "Spammer Guy"); eq(more.data.name, SPAMMER)
		-- Its Cancel, or a close that is no click, asks nothing more.
		local shown = #w.dialogs
		MORE.OnAlt({ data = more.data }, more.data)
		MORE.OnCancel({ data = more.data }, more.data, "override")
		eq(#w.dialogs, shown, "nothing more asked")
		MORE.OnCancel({ data = more.data }, more.data, "clicked")
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_REPORT_NOTE"); eq(w.dialogs[#w.dialogs].data.cat, "O", "its second answer: something else")
		MORE.OnAccept({ data = more.data }, more.data)
		local note = w.dialogs[#w.dialogs]
		eq(note.which, "OLYMPUS_WATCH_REPORT_NOTE"); eq(note.data.cat, "E", "its first answer: not in English")
		assert(note.b:find(ns.L.WATCH_REPORT_PREVIEW:format(ns.L.WATCH_REPORT_CAT_E, 1), 1, true), note.b)
		eq(#w.jobs, 0, "nothing sent before Send")
		NOTE.OnAccept({ data = note.data, editBox = { GetText = function() return "" end } }, note.data)
		eq(#w.jobs, 2, "the report and its line")
		local seq = assert(w.jobs[1].msg:match("^MR~1~R~(%d+)~"))
		eq(w.jobs[1].msg, ("MR~1~R~%s~%d~%s~%s~%s~E~%s~1~"):format(seq, w.epoch, w.guild, c.group, c.faction, SPAMMER))

		-- An officer's client takes it as such: the case is about that, on its page and on the card.
		FakeWidgets()
		w.setRank(c.me, 0); w.setRank("Reporter One-Realm", 3)
		for _, msg in ipairs(ReportMessages(w, W, c, { cat = "E", lines = { { at = w.epoch - 100, tier = "A", text = "hola a todos" } } })) do
			assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg))
		end
		assert(w.prints[#w.prints]:find(ns.L.WATCH_REPORT_IN:format("Spammer Guy", ns.L.WATCH_REPORT_CAT_E), 1, true))
		local open = W.Cases()
		eq(#open, 1); eq(open[1].cats.E, 1)
		local about = ns.L.WATCH_CAT_COUNT:format(ns.L.WATCH_REPORT_CAT_E, 1)
		W.Show("case", c.Fold(SPAMMER))
		local page = {}
		for _, l in ipairs(W.Build()) do page[#page + 1] = tostring(l.text or "") end
		assert(table.concat(page, "\n"):find(ns.L.WATCH_CASE_ALLEGATION:format(about), 1, true), "the case's page")
		local f = assert(W.ShowCard(c.Fold(SPAMMER)))
		assert(f.body:GetText():find(ns.L.WATCH_CARD_ACCUSED:format(about), 1, true), "the card")
		eq(W.Record(SPAMMER), nil, "a report is never a sanction")
	end)
end)

test("watch: a reporter's client reports a name once a day, once a minute and five times a day; never himself, the King, or while net-off", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3); w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm")
		assert(W.SendReport(SPAMMER, "A", "one"))
		local ok, why = W.SendReport(SPAMMER, "S", "again")
		eq(ok, false); eq(why, "already", "the same name within a day")
		local menu = FakeMenu()
		w.menu.build({ name = SPAMMER }, menu)
		eq(menu.buttons[1].enabled, false); eq(menu.buttons[1].tip, ns.L.WATCH_REPORT_NO_ALREADY:format("Spammer Guy"))
		ok, why = W.SendReport("Other Guy-Realm", "A", "")
		eq(ok, false); eq(why, "rate", "one a minute")
		for i = 2, W.REPORT_DAY do
			w.epoch = w.epoch + W.REPORT_GAP; w.refreshRoster()
			assert(W.SendReport("Target" .. i .. "-Realm", "O", ""), "report " .. i)
		end
		w.epoch = w.epoch + W.REPORT_GAP; w.refreshRoster()
		ok, why = W.SendReport("Sixth Guy-Realm", "A", "")
		eq(ok, false); eq(why, "day", "five a day")
		w.epoch = w.epoch + W.REPORT_DEDUPE + 1; w.refreshRoster()
		assert(W.SendReport(SPAMMER, "A", "a day later"), "the same name again a day later")
		ok, why = W.SendReport(c.me, "A", "")
		eq(ok, false); eq(why, "self")
		w.king = "King Guy-Realm"
		ok, why = W.SendReport("King Guy-Realm", "A", "")
		eq(ok, false); eq(why, "king")
		w.selfOff = { kind = "g" }
		ok, why = W.SendReport("Netoff Case-Realm", "A", "")
		eq(ok, false); eq(why, "netoff", "a client taken off the network reports nobody")
		w.selfOff = nil
		w.epoch = w.epoch + W.REPORT_GAP
		ok, why = W.SendReport("Bad Category-Realm", "X", "")
		eq(ok, false); eq(why, "category")
		w.locked = true
		ok, why = W.SendReport("Locked Case-Realm", "A", "")
		eq(ok, false); eq(why, "locked")
		w.locked = false
		w.guild = "Horde Heroes"
		eq(W.ReportBlocked(SPAMMER), "guild", "only from an Olympus guild")
	end)
end)

test("watch: a report with no officer online waits a day for the first one; past a day it is dropped and the reporter told", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3); w.online(c.me)
		local ok, how = W.SendReport(SPAMMER, "A", "waits")
		eq(ok, true); eq(how, "held"); eq(#w.jobs, 0)
		eq(#w.prints, 0, "SendReport itself prints nothing (its dialog does: below)")
		eq(W.FlushReports(true), 0, "still nobody")
		-- A full send queue: it stays for the next try, and the reporter is told so.
		w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm"); w.refreshRoster()
		w.queueRoom = 0
		eq(W.FlushReports(true), 0, "the queue is full")
		eq(#W.Book(false).outbox, 1); eq(#w.jobs, 0)
		w.queueRoom = 60
		w.online(c.me); w.refreshRoster()
		w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm"); w.refreshRoster()
		eq(W.FlushReports(true), 1, "sent once an officer is online")
		eq(w.jobs[1].target, "Captain One-Realm")
		w.finish(w.jobs[1])
		eq(#W.Book(false).outbox, 0, "delivered, out of the outbox")
		eq(W.FlushReports(true), 0, "never twice")
		-- Another one, from its dialog: the reporter is told it waits. Nobody online for a day:
		-- dropped, and said so.
		w.online(c.me); w.jobs = {}
		w.epoch = w.epoch + W.REPORT_GAP; w.refreshRoster()
		local data = { name = "Other Guy-Realm", cat = "S" }
		StaticPopupDialogs.OLYMPUS_WATCH_REPORT_NOTE.OnAccept({ data = data, editBox = { GetText = function() return "" end } }, data)
		eq(w.prints[#w.prints], ns.L.WATCH_REPORT_HELD:format("Other Guy"), "told it waits")
		eq(#W.Book(false).outbox, 1)
		w.epoch = w.epoch + W.REPORT_HOLD + 1; w.refreshRoster()
		W.FlushReports(true)
		eq(#W.Book(false).outbox, 0)
		assert(w.prints[#w.prints]:find(ns.L.WATCH_REPORT_DROPPED:format("Other Guy"), 1, true))
		eq(#w.jobs, 0)
	end)
end)

test("watch: an officer takes reports from his own guild's members alone, each player's newest on a name; spoofed, replayed and flooding reports fail closed", function()
	WithWatch(function(w, W, c)
		w.setRank("Reporter One-Realm", 3); w.setRank("Reporter Two-Realm", 3)
		local msgs = ReportMessages(w, W, c, { lines = { { at = w.epoch - 30, tier = "A", text = "line one" }, { at = w.epoch - 20, tier = "A", text = "line two" } } })
		local function Reject(expected, dist, sender, message, label)
			local accepted, why = W.HandleReport(dist, sender, message)
			eq(accepted, false, label); eq(why, expected, label)
		end
		Reject("access", "GUILD", "Reporter One-Realm", msgs[1], "whispers only")
		w.logged = false
		Reject("unlogged", "WHISPER", "Reporter One-Realm", msgs[1], "the logged API")
		w.logged = true
		Reject("sender", "WHISPER", "Outsider-Realm", msgs[1], "not in this guild's roster")
		w.hidden[c.Fold("Reporter Two-Realm")] = true
		Reject("sender", "WHISPER", "Reporter Two-Realm", msgs[1], "a reporter taken off the network")
		w.hidden[c.Fold("Reporter Two-Realm")] = nil
		Reject("identity", "WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { guild = "Olympus III" })[1], "another guild's report")
		Reject("name", "WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { target = "Reporter One-Realm" })[1], "himself")
		Reject("time", "WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { at = w.epoch + 600 })[1], "dated ahead")
		Reject("shape", "WHISPER", "Reporter One-Realm", msgs[1]:gsub("~A~", "~Z~", 1), "an unknown category")
		Reject("size", "WHISPER", "Reporter One-Realm", msgs[1] .. string.rep("x", 256), "oversized")
		local printed = #w.prints
		assert(W.HandleReport("WHISPER", "Reporter One-Realm", msgs[1]))
		eq(#w.prints, printed + 1, "the officer is told"); assert(w.prints[#w.prints]:find(ns.L.WATCH_REPORT_IN:format("Spammer Guy", ns.L.WATCH_REPORT_CAT_A), 1, true))
		-- Its lines are the public channel's alone (Watch.Evidence sends no other): a Captains' or
		-- Lords' line, which officers who can't read that channel would see, is refused.
		Reject("tier", "WHISPER", "Reporter One-Realm", (msgs[2]:gsub("~A~", "~L~", 1)), "a Lords-channel line")
		Reject("tier", "WHISPER", "Reporter One-Realm", (msgs[2]:gsub("~A~", "~C~", 1)), "a Captains-channel line")
		assert(W.HandleReport("WHISPER", "Reporter One-Realm", msgs[2])); assert(W.HandleReport("WHISPER", "Reporter One-Realm", msgs[3]))
		Reject("stale", "WHISPER", "Reporter One-Realm", msgs[3], "a line once")
		Reject("stale", "WHISPER", "Reporter Two-Realm", msgs[2], "a line from another player")
		Reject("replay", "WHISPER", "Reporter One-Realm", msgs[1], "a replay")
		local reports = W.Reports()
		eq(#reports, 1); eq(reports[1].reporter, "Reporter One-Realm", "the server's sender, never a claimed name")
		eq(reports[1].lines[1].text, "line one"); eq(reports[1].lines[2].text, "line two")
		eq(reports[1].lines[1].tier, "A")
		-- A saved line of another chat (the SavedVariables can be edited) goes at the next check.
		reports[1].lines[2].tier = "C"
		W.Prune()
		eq(W.Reports()[1].lines[2], nil, "a saved Captains' line goes")
		reports[1].lines[2] = { at = w.epoch - 20, tier = "A", text = "line two" }
		-- The same player again on the same name: his newest replaces his earlier one.
		w.epoch = w.epoch + 60
		assert(W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 11, at = w.epoch, note = "still at it" })[1]))
		reports = W.Reports()
		eq(#reports, 1, "one per player and name"); eq(reports[1].note, "still at it")
		eq(#w.prints, printed + 1, "an open case is not announced again so soon")
		-- A flood from one player: a few an hour.
		for i = 1, W.REPORT_RATE - 2 do -- (two of the hour's already: his first report and its newer one)
			assert(W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 20 + i, target = "Flood" .. i .. "-Realm" })[1]), "report " .. i)
		end
		Reject("rate", "WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 40, target = "Flood Over-Realm" })[1], "too many from one player")
		-- None of it punishes anyone or sends anything.
		eq(W.Record(SPAMMER), nil); eq(#W.Audit(), 0); eq(#w.jobs, 0)
		-- Not an officer: The Watch takes no report.
		w.setRank(c.me, 3)
		Reject("access", "WHISPER", "Reporter Two-Realm", ReportMessages(w, W, c, { seq = 50 })[1], "a member's client takes none")
	end)
end)

test("watch: Cases group reports by name, open until The Watch acts on it or an officer closes it without action; a newer report opens it again", function()
	WithWatch(function(w, W, c)
		for _, name in ipairs({ "Reporter One-Realm", "Reporter Two-Realm", "Reporter Three-Realm", "Spammer Guy-Realm", "Rude Guy-Realm" }) do w.setRank(name, 3) end
		local function Report(reporter, seq, target, cat, lines)
			local m = ReportMessages(w, W, c, { seq = seq, target = target, cat = cat, lines = lines })
			for _, msg in ipairs(m) do assert(W.HandleReport("WHISPER", reporter, msg)) end
		end
		Report("Reporter One-Realm", 10, SPAMMER, "S", { { at = w.epoch - 5, tier = "A", text = "cheap gold" } })
		Report("Reporter Two-Realm", 10, SPAMMER, "S")
		Report("Reporter Three-Realm", 10, SPAMMER, "A")
		Report("Reporter One-Realm", 11, "Rude Guy-Realm", "A")
		local open, handled = W.Cases()
		eq(#open, 2); eq(#handled, 0)
		eq(open[1].target, SPAMMER, "most players first"); eq(open[1].reporters, 3); eq(open[1].cats.S, 2); eq(open[1].cats.A, 1); eq(open[1].lines, 1)
		-- The navigation and the Cases page.
		W.Show("cases")
		eq(W.PageId(), "cases")
		local lines = W.Build()
		assert(lines[1].nav and #lines[1].nav == 4, "Desk, Reports, Cases, My Watch")
		eq(lines[1].nav[3].text, ns.L.WATCH_NAV_CASES:format(2)); eq(lines[1].nav[3].selected, true)
		local row
		for _, l in ipairs(lines) do if l.onClick and tostring(l.text):find("Spammer Guy", 1, true) then row = l end end
		assert(row, "the case's row"); row.onClick()
		eq(W.mode, "case"); eq(W.PageId(), "case:" .. c.Fold(SPAMMER))
		-- The Watch acts on the name: its case is handled (the action is the list's own, synced).
		w.online(c.me)
		assert(W.Mark(SPAMMER, "watching the gold seller"))
		open, handled = W.Cases()
		eq(#open, 1); eq(open[1].target, "Rude Guy-Realm"); eq(handled[1].target, SPAMMER)
		-- Closed without action, told to the officers online, rechecked at the send.
		w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm")
		w.epoch = w.epoch + 1; w.refreshRoster()
		assert(W.CloseCase("Rude Guy-Realm"))
		eq(#W.Cases(), 0, "no open case")
		local job = assert(w.jobs[#w.jobs])
		eq(job.msg, ("MR~1~X~%d~%s~%s~%s~Rude Guy-Realm"):format(w.epoch, w.guild, c.group, c.faction)); eq(job.logged, true)
		w.setRank("Captain One-Realm", 3)
		local allowed, why = w.finish(job)
		eq(allowed, false); eq(why, "revoked")
		w.setRank("Captain One-Realm", 1)
		eq(W.Record("Rude Guy-Realm"), nil, "closing is no sanction")
		-- A newer report opens it again, with that report alone.
		w.epoch = w.epoch + 5; w.refreshRoster()
		Report("Reporter Two-Realm", 12, "Rude Guy-Realm", "O")
		open = W.Cases()
		eq(#open, 1); eq(open[1].target, "Rude Guy-Realm"); eq(open[1].reporters, 1)
		-- Another officer's close comes in; an ordinary member's never counts.
		local close = ("MR~1~X~%d~%s~%s~%s~Rude Guy-Realm"):format(w.epoch + 1, w.guild, c.group, c.faction)
		local ok, refused = W.HandleReport("WHISPER", "Reporter One-Realm", close)
		eq(ok, false); eq(refused, "sender")
		eq(#W.Cases(), 1)
		w.epoch = w.epoch + 1; w.refreshRoster()
		assert(W.HandleReport("WHISPER", "Captain One-Realm", close))
		eq(#W.Cases(), 0, "closed by the other officer")
	end)
end)

test("watch: a case's page shows its evidence through the block terms, reporters in tooltips (masked on the King's stream), and the judgment's separate clicks", function()
	WithWatch(function(w, W, c)
		w.setRank("Reporter One-Realm", 3); w.setRank(SPAMMER, 3); w.online(c.me)
		for _, msg in ipairs(ReportMessages(w, W, c, { note = "badword in a note", lines = { { at = w.epoch - 5, tier = "A", text = "a badword here" } } })) do
			assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg))
		end
		w.filterHit = "badword"
		W.Show("case", c.Fold(SPAMMER))
		local lines = W.Build()
		local text = {}
		for _, l in ipairs(lines) do text[#text + 1] = tostring(l.text or "") end
		local page = table.concat(text, "\n")
		assert(not page:find("badword", 1, true), "the words through the block terms: " .. page)
		assert(page:find(ns.L.FILTER_WORDS_HIDDEN_SHORT, 1, true))
		assert(not page:find("Reporter One", 1, true), "no reporter on the rows")
		assert(page:find(ns.L.WATCH_CASE_GAPS, 1, true), "says what it can't know")
		local function Tip(l)
			local tt = { lines = {} }
			function tt:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
			l.tooltip(tt)
			return table.concat(tt.lines, "\n")
		end
		local reported, evidence
		for _, l in ipairs(lines) do
			if tostring(l.text):find(ns.L.WATCH_CASE_REPORTED:format(1, "", ""):sub(1, 12), 1, true) then reported = l end
			if l.indent == 2 and l.tooltip then evidence = l end
		end
		assert(Tip(reported):find("Reporter One", 1, true), "the reporter in the tooltip")
		assert(Tip(evidence):find("a badword here", 1, true), "the line as written, for the officer")
		w.masked = true
		assert(not Tip(reported):find("Reporter One", 1, true) and Tip(reported):find("Repo****", 1, true), "masked on the King's stream")
		assert(not Tip(evidence):find("a badword here", 1, true), "never the raw line there")
		w.masked = false
		-- The judgment: a finding, then the sanction, each its own click.
		local clicks = {}
		for _, l in ipairs(lines) do if l.onClick then clicks[tostring(l.text)] = l.onClick end end
		local function Click(label)
			for t, fn in pairs(clicks) do if t:find(label, 1, true) then return fn() end end
			error("no row: " .. label)
		end
		Click(ns.L.WATCH_CASE_UPHOLD)
		eq(W.Case(c.Fold(SPAMMER)).finding.verdict, "up")
		eq(W.Record(SPAMMER), nil, "a finding is no sanction"); eq(#w.jobs, 0, "and is sent to nobody")
		Click(ns.L.WATCH_WARN_BTN)
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_REASON", "the sanction asks its reason"); eq(w.dialogs[#w.dialogs].data.kind, "warn")
		Click(ns.L.WATCH_CASE_CLOSE)
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_CASE_CLOSE")
		StaticPopupDialogs.OLYMPUS_WATCH_CASE_CLOSE.OnAccept({ data = w.dialogs[#w.dialogs].data }, w.dialogs[#w.dialogs].data)
		eq(#W.Cases(), 0)
		Click(ns.L.WATCH_CASE_COPY)
		assert(w.copied and w.copied.text:find(ns.L.WATCH_CASE_TITLE:format("Spammer Guy"), 1, true))
		assert(not w.copied.text:find("Reporter One", 1, true), "no reporter in the copy")
		assert(not w.copied.text:find("badword", 1, true), "the copy through the block terms")
	end)
end)

test("watch: the judgment card names no reporter, note or chat line; its thumbs are this officer's finding alone; it closes when access goes", function()
	WithWatch(function(w, W, c)
		FakeWidgets()
		w.setRank("Reporter One-Realm", 3); w.setRank("Reporter Two-Realm", 3)
		for i, reporter in ipairs({ "Reporter One-Realm", "Reporter Two-Realm" }) do
			for _, msg in ipairs(ReportMessages(w, W, c, { seq = 10 + i, cat = i == 1 and "A" or "S", note = "secret note " .. i,
				lines = { { at = w.epoch - 5, tier = "A", text = "evidence line " .. i } } })) do
				assert(W.HandleReport("WHISPER", reporter, msg))
			end
		end
		local key = c.Fold(SPAMMER)
		local f = assert(W.ShowCard(key), "the card")
		eq(f:IsShown(), true); eq(f.name:GetText(), "Spammer Guy")
		local all = table.concat({ f.title:GetText(), f.name:GetText(), f.body:GetText(), f.verdict:GetText(), f.foot:GetText() }, "\n")
		for _, absent in ipairs({ "Reporter", "secret note", "evidence line" }) do assert(not all:find(absent, 1, true), "on the card: " .. absent) end
		assert(f.body:GetText():find(ns.L.WATCH_CARD_REPORTED:format(2), 1, true))
		assert(f.body:GetText():find(ns.L.WATCH_CARD_EVIDENCE:format(2), 1, true))
		eq(f.verdict:GetText(), ns.L.WATCH_CARD_AWAITING)
		f.up:Click()
		assert(f.verdict:GetText():find(ns.L.WATCH_CARD_UPHELD, 1, true))
		f.down:Click()
		assert(f.verdict:GetText():find(ns.L.WATCH_CARD_NOT_UPHELD, 1, true))
		eq(#w.jobs, 0, "a finding is sent to nobody"); eq(W.Record(SPAMMER), nil); eq(#W.Audit(), 0)
		w.setRank(c.me, 3)
		W.RefreshCard()
		eq(f:IsShown(), false, "no access, no card")
		eq(W.ShowCard(key), nil)
	end)
end)

test("watch: /oly watch report opens the report for any member; reports and cases open their pages for officers", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		assert(W.Slash("report Spammer Guy"))
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WATCH_REPORT_WHAT")
		eq(w.dialogs[#w.dialogs].data.name, SPAMMER)
		W.Slash("cases")
		eq(w.selected, "watch"); eq(W.PageId(), "member", "an ordinary member opens their personal page")
		w.setRank(c.me, 1)
		W.Slash("cases")
		eq(w.selected, "watch"); eq(W.mode, "cases")
		W.Slash("reports")
		eq(W.mode, "reports")
		W.Show(nil)
		eq(W.PageId(), "desk")
	end)
end)

test("watch: the report and case strings in English and pt-BR, with the same placeholders", function()
	local oldLocale = GetLocale
	local pt = {}
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales.lua")), "Olympus", pt)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	local n = 0
	for k, v in pairs(ns.L) do
		if type(k) == "string" and (k:find("^WATCH_REPORT") or k:find("^WATCH_CASE") or k:find("^WATCH_CARD") or k:find("^WATCH_NAV")
			or k:find("^WATCH_CASES") or k:find("^WATCH_REPORTS") or k == "WATCH_CLICK_CASE" or k == "WATCH_CAT_COUNT") then
			n = n + 1
			local p = rawget(pt.L, k)
			assert(p and p ~= k, "pt-BR: " .. k)
			if k ~= "WATCH_CAT_COUNT" then assert(p ~= v, "translated: " .. k) end
			local a, b = {}, {}
			for x in v:gmatch("%%%d*[sd]") do a[#a + 1] = x end
			for x in p:gmatch("%%%d*[sd]") do b[#b + 1] = x end
			eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. k)
		end
	end
	assert(n >= 60, "the strings: " .. n)
	assert(ns.L.WATCH_REPORT_TIP:find("Nothing happens to them by itself", 1, true))
	assert(pt.L.WATCH_REPORT_TIP:find("Nada acontece com ele por isso", 1, true))
end)

test("watch: the report's questions go through ns.ShowDialog (Olympus's own dialogs with the gamepad UI); the card has no edit box", function()
	local src = assert(io.open(ROOT .. "Olympus/Watch.lua", "rb")):read("*a")
	for _, api in ipairs({ "StaticPopup_Show", "MenuUtil", "UISpecialFrames", "EasyMenu", "ChatFrame_OpenChat", "DoEmote" }) do
		assert(not src:find(api, 1, true), "Watch.lua uses " .. api)
	end
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3); w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm")
		w.queueRoom = 0
		local ok, how = W.SendReport(SPAMMER, "A", "")
		eq(ok, true); eq(how, "busy", "kept for the next try")
		eq(#W.Book(false).outbox, 1)
	end)
end)

-- The review of 1.1.6: a report on an officer went to that officer too (every authorized officer
-- online but the reporter), with the note, the case and its reporters' names.
test("watch: a report on an officer goes to the other officers online, never to him nor to a name his player linked; with only him online it waits", function()
	WithWatch(function(w, W, c)
		local RUDE, ALT = "Rude Captain-Realm", "Rude Alt-Realm"
		w.setRank(c.me, 3); w.setRank("Captain One-Realm", 1); w.setRank(RUDE, 1); w.setRank(ALT, 1)
		w.links[c.Fold(RUDE)] = { ALT }
		w.online(c.me, "Captain One-Realm", RUDE, ALT)
		local ok, how, count = W.SendReport(RUDE, "A", "insulted me")
		eq(ok, true); eq(how, "sent"); eq(count, 1)
		eq(#w.jobs, 1, "the report, to one officer")
		eq(w.jobs[1].target, "Captain One-Realm", "never the accused nor his linked name")
		-- A link made while it waits in the queue: rechecked at the real send.
		w.links[c.Fold(RUDE)] = { ALT, "Captain One-Realm" }
		local allowed, why = w.finish(w.jobs[1])
		eq(allowed, false); eq(why, "revoked")
		w.links[c.Fold(RUDE)] = { ALT }
		-- Only the accused (and his alt) online: it waits for another officer.
		w.jobs = {}
		w.epoch = w.epoch + W.REPORT_GAP; w.online(c.me, "Lone Captain-Realm"); w.setRank("Lone Captain-Realm", 1); w.refreshRoster()
		ok, how = W.SendReport("Lone Captain-Realm", "S", "")
		eq(ok, true); eq(how, "held"); eq(#w.jobs, 0)
		-- An officer closing a case on another officer tells the others, never him.
		w.setRank(c.me, 0); w.online(c.me, "Captain One-Realm", RUDE, ALT)
		w.epoch = w.epoch + 1; w.refreshRoster()
		assert(W.CloseCase(RUDE))
		eq(#w.jobs, 1); eq(w.jobs[1].target, "Captain One-Realm")
		assert(w.jobs[1].msg:find("^MR~1~X~"))
	end)
end)

test("watch: an officer's client takes no report about himself or a name his player linked", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 1); w.setRank("Reporter One-Realm", 3)
		w.links[c.Fold("My Alt-Realm")] = { c.me }
		local printed = #w.prints
		for i, target in ipairs({ c.me, "My Alt-Realm" }) do
			local ok, why = W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 10 + i, target = target })[1])
			eq(ok, false, target); eq(why, "accused", target)
		end
		eq(#W.Reports(), 0); eq(#w.prints, printed, "nothing said")
		-- Anyone else's, as ever.
		assert(W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 20 })[1]))
	end)
end)

-- The review of 1.1.6: held reports went newest first, and the officer's per-reporter replay floor
-- then refused the older ones; the reporter's client still dropped them as delivered.
test("watch: held reports go oldest first, and an officer takes a reporter's older report on another name after a newer one", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3); w.online(c.me)
		assert(W.SendReport("First Guy-Realm", "A", "first"))
		w.epoch = w.epoch + W.REPORT_GAP; w.refreshRoster()
		assert(W.SendReport("Second Guy-Realm", "S", "second"))
		eq(#W.Book(false).outbox, 2); eq(#w.jobs, 0)
		w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm"); w.refreshRoster()
		eq(W.FlushReports(true), 2)
		local heads = {}
		for _, job in ipairs(w.jobs) do if job.msg:find("^MR~1~R~") then heads[#heads + 1] = job.msg end end
		eq(#heads, 2)
		assert(heads[1]:find("~First Guy-Realm~", 1, true), "the older one first: " .. heads[1])
		assert(heads[2]:find("~Second Guy-Realm~", 1, true))

		-- On an officer's client: a reporter's newer report on one name, then his older one on
		-- another (held while only the accused was online, say): both taken.
		w.setRank(c.me, 1); w.setRank("Reporter One-Realm", 3)
		assert(W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 20, target = "Newer Case-Realm" })[1]))
		local ok, why = W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 10, target = "Older Case-Realm" })[1])
		eq(ok, true, tostring(why))
		eq(#W.Reports(), 2)
		-- A replay of either is still refused.
		ok, why = W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 10, target = "Older Case-Realm" })[1])
		eq(ok, false); eq(why, "replay")
		ok, why = W.HandleReport("WHISPER", "Reporter One-Realm", ReportMessages(w, W, c, { seq = 19, target = "Newer Case-Realm" })[1])
		eq(ok, false); eq(why, "replay")
	end)
end)

-- The review of 1.1.6: on the King's stream the notes and lines still showed in the case's rows,
-- its tooltips and the Reports page; the net-off and the Watch hide other players' words there.
test("watch: on the King's stream a case's notes and lines are hidden, in its rows, its tooltips, the Reports page and the copy", function()
	WithWatch(function(w, W, c)
		w.setRank("Reporter One-Realm", 3); w.setRank(SPAMMER, 3); w.online(c.me)
		local NOTE, LINE = "a rude note of mine", "the rude line he wrote"
		for _, msg in ipairs(ReportMessages(w, W, c, { note = NOTE, lines = { { at = w.epoch - 5, tier = "A", text = LINE } } })) do
			assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg))
		end
		local function Tip(l)
			local tt = { lines = {} }
			function tt:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
			if l.tooltip then l.tooltip(tt) end
			return table.concat(tt.lines, "\n")
		end
		local function Everything(mode, key)
			W.Show(mode, key)
			local out = {}
			for _, l in ipairs(W.Build()) do out[#out + 1] = tostring(l.text or "") .. "\n" .. Tip(l) end
			return table.concat(out, "\n")
		end
		local key = c.Fold(SPAMMER)
		local page = Everything("case", key) .. Everything("reports")
		assert(page:find(NOTE, 1, true) and page:find(LINE, 1, true), "off the stream, the officer reads them")
		w.masked = true
		page = Everything("case", key) .. Everything("reports")
		assert(not page:find(NOTE, 1, true), "no note on the stream")
		assert(not page:find(LINE, 1, true), "no line on the stream")
		assert(page:find(ns.L.NETOFF_REASON_HIDDEN, 1, true))
		local copy = W.CaseText(W.Case(key))
		assert(not copy:find(NOTE, 1, true) and not copy:find(LINE, 1, true), "nor in the copy")
		w.masked = false
		copy = W.CaseText(W.Case(key))
		assert(copy:find(NOTE, 1, true) and copy:find(LINE, 1, true))
	end)
end)

-- The review of 1.1.6: the card for the stream showed the Watch's record (warnings, interventions,
-- watched or ban-listed), the guild's private list.
test("watch: the judgment card never shows The Watch's record; the case's page does, for the officers", function()
	WithWatch(function(w, W, c)
		FakeWidgets()
		w.setRank("Reporter One-Realm", 3); w.setRank(SPAMMER, 3); w.online(c.me)
		assert(W.Ban(SPAMMER, "gold seller"), "ban-listed here")
		eq(W.Record(SPAMMER).status, "ban")
		w.epoch = w.epoch + 5; w.refreshRoster()
		for _, msg in ipairs(ReportMessages(w, W, c, {})) do assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg)) end
		local key = c.Fold(SPAMMER)
		local f = assert(W.ShowCard(key))
		local record = ns.L.WATCH_CASE_RECORD:match("^[^%%]+")
		local all = table.concat({ f.title:GetText(), f.name:GetText(), f.body:GetText(), f.verdict:GetText(), f.foot:GetText() }, "\n")
		assert(not all:find(record, 1, true), "no record on the card: " .. all)
		assert(not all:find(ns.L.WATCH_BANNED, 1, true), "nor the ban list")
		W.Show("case", key)
		local page = {}
		for _, l in ipairs(W.Build()) do page[#page + 1] = tostring(l.text or "") end
		assert(table.concat(page, "\n"):find(record, 1, true), "the case's page keeps it")
	end)
end)

-- 1.2: The Watch takes in the Tabards (Daniel's decision, 2026-10-04): the separate Tabards tab
-- is gone, and whoever saw it keeps its lists here. Its desk, Reports and Cases stay the officers'.
test("watch: the Tabards are a section of The Watch: a member sees them alone while published, an officer the desk and the Tabards", function()
	WithWatch(function(w, W, c)
		eq(w.tab.visible, W.TabVisible, "the tab's own rule"); eq(w.tab.view, W.ViewKey, "and the view its section borrows")
		local function NavKeys(lines)
			local out = {}
			for _, item in ipairs(lines[1].nav or {}) do out[#out + 1] = item.text .. (item.selected and "*" or "") end
			return table.concat(out, ",")
		end
		-- An ordinary member: their own page, plus the Tabards while the King's publication is fresh.
		w.setRank(c.me, 3)
		eq(W.TabVisible(), false, "no staff tab for a personal page")
		w.tabards = true
		eq(W.TabVisible(), false, "published Tabards do not grant the staff tab")
		eq(W.CanRead(), false, "no officer's rights for it")
		eq(W.ViewKey(), "heraldry"); eq(W.PageId(), "tabards")
		local lines = W.Build()
		eq(NavKeys(lines), ns.L.TAB_HERALDRY .. "*," .. ns.L.WATCH_MEMBER_NAV, "Tabards and the personal page")
		eq(lines[2].text, ns.L.SEARCH, "then the Tabards' own lines: its search box first")
		assert(lines[2].input, "the box")
		W.Show(nil)
		eq(W.ViewKey(), "heraldry", "the desk is not hers: the Tabards still")
		eq(#W.Records(), 0)
		-- An officer: the desk first, the Tabards one click away, and back.
		w.setRank(c.me, 1)
		eq(W.ViewKey(), "watch"); eq(W.PageId(), "desk")
		lines = W.Build()
		eq(NavKeys(lines), table.concat({ ns.L.WATCH_NAV_DESK .. "*", ns.L.WATCH_NAV_REPORTS:format(0), ns.L.WATCH_NAV_CASES:format(0), ns.L.TAB_HERALDRY, ns.L.WATCH_MEMBER_NAV }, ","))
		lines[1].nav[4].onClick()
		eq(W.mode, "tabards"); eq(W.ViewKey(), "heraldry"); eq(W.PageId(), "tabards")
		lines = W.Build()
		eq(lines[1].nav[4].selected, true); eq(lines[1].nav[4].onClick, nil, "the page shown")
		lines[1].nav[1].onClick()
		eq(W.mode, nil); eq(W.ViewKey(), "watch")
		-- An officer while nothing is published sees the Tabards still (his own patrols, as the old
		-- tab showed them: TabardsV2.SurfaceVisible); with none at all, the desk alone.
		w.tabards = false
		lines = W.Build()
		eq(#lines[1].nav, 4, "Desk, Reports, Cases, My Watch")
		W.Show("tabards")
		eq(W.ViewKey(), "watch", "no Tabards to show: the desk"); eq(W.PageId(), "desk")
	end)
end)

test("watch: /oly tabard and /oly watch open the Tabards for whoever sees only them; nobody else is let in", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		assert(W.Slash("tabards"))
		eq(w.selected, "watch", "the window opens: the Tabards are its section"); eq(W.mode, "tabards")
		w.selected = nil
		W.Show(nil)
		W.Slash("")
		eq(w.selected, "watch"); eq(W.mode, "member", "a member with no publication opens their own page")
		w.tabards = true
		W.Slash("cases")
		eq(w.selected, "watch"); eq(W.mode, "tabards", "a member sees the Tabards, never the Cases")
		eq(W.ViewKey(), "heraldry")
		-- Core.lua's /oly tabard (and /oly inspect, /oly heraldry): The Watch's.
		local core = assert(io.open(ROOT .. "Olympus/Core.lua", "rb")):read("*a")
		assert(core:find('cmd == "inspect" or cmd == "tabard" or cmd == "heraldry" then\n\t\t\tns.Watch.Slash("tabards")', 1, true), "the slash command")
	end)
end)

-- The author asked why The Watch had no tab for him (2026-10-05): it showed for officers alone.
-- He sees every tab, The Watch's desk included, with what his own client holds: nobody's records,
-- and no rank's actions.
test("watch: the author sees the desk without a rank, with only his own client's records and no officer's action", function()
	WithWatch(function(w, W, c)
		w.setRank(c.me, 3)
		eq(W.TabVisible(), false, "an ordinary member has no staff tab")
		w.author = "my"
		eq(W.TabVisible(), true, "the author: The Watch's tab")
		eq(W.DeskShown(), true); eq(W.ViewKey(), "watch"); eq(W.PageId(), "desk")
		eq(W.CanRead(), false, "no officer's rights"); eq(W.CanManage(), false)
		local lines = W.Build()
		local title = false
		for _, l in ipairs(lines) do if tostring(l.text or ""):find(ns.L.WATCH_TITLE, 1, true) then title = true end end
		assert(title, "the desk's page")
		-- (1.2: and the Judgments, Judgment.lua: the author sees them too, with his own client's.)
		eq(#lines[1].nav, 5, "Desk, Reports, Cases, Judgments, My Watch (no Tabards published)")
		eq(lines[1].nav[4].text, ns.L.WATCH_NAV_JUDGMENTS:format(0))
		eq(#W.Records(), 0); eq(#W.Reports(), 0); eq(#(W.Cases()), 0)
		local ok, why = W.Warn("Member-Realm", "reason")
		eq(ok, false); eq(why, "access", "his rank's actions alone")
		W.Ask("warn", "Member-Realm")
		eq(w.prints[#w.prints], ns.L.WATCH_NO_ACCESS); eq(#w.dialogs, 0)
		-- The officers' whispers still never reach him: he is not one of their recipients.
		w.setRank("Captain One-Realm", 1); w.online(c.me, "Captain One-Realm")
		eq(W.IsAuthorized(c.me), false)
		-- A View-as role decides what shows, never what he may do.
		w.author, w.allows = "member", {}
		eq(W.TabVisible(), false, "a member preview has no staff tab")
		w.setRank(c.me, 1)
		eq(W.CanRead(), true, "the actual character remains an officer")
		eq(W.TabVisible(), false, "member preview hides the tab even for an actual officer")
		w.setRank(c.me, 3)
		w.author, w.allows = "officer", { watch = true }
		eq(W.DeskShown(), true, "previewing an officer: the desk"); eq(W.CanManage(), false, "and still none of its actions")
	end)
end)

---------------------------------------------------------------------------
-- 1.2: Judgment (Daniel, 2026-10-05: the council votes within a period and the King has the final
-- word). The officer's client is this world's (its real Watch.lua and Judgment.lua); the King's and
-- the councillors' are Judgment.lua again, each in a namespace of its own (Peer), their whispers
-- handed to each other as the server would (Deliver): with the server's sender, once the permit each
-- carried still allows it, as Comm asks it right before the game sends.
---------------------------------------------------------------------------
local KING, HC1, HC2, HC3 = "Crown Bearer-Realm", "Sage One-Realm", "Sage Two-Realm", "Sage Three-Realm"

local function Council(w, c)
	w.peers, w.bus, w.log = w.peers or {}, w.bus or {}, w.log or {}
	w.king = KING
	w.council = { [c.Fold(HC1)] = true, [c.Fold(HC2)] = true, [c.Fold(HC3)] = true }
	-- (The signed list as clients keep it: short names, lower case.)
	w.councilNames = { ["sage one"] = true, ["sage two"] = true, ["sage three"] = true }
	-- What the King's client sees of each sender's rank in a guild (Data.AuthorizedRank: its roster,
	-- the census or the signed manifest): this officer is a Captain of his guild.
	w.ranksSeen = { [c.Fold(c.me) .. "@" .. c.Fold(w.guild)] = 1 }
end

local function Peer(w, c, name, o)
	o = o or {}
	local p = setmetatable({ me = name, db = {}, rdb = { council = { names = w.councilNames } } }, { __index = c })
	p.prints, p.handlers = {}, {}
	p.King = { IsKing = function() return o.king == true end, Preview = function() return false end }
	p.Data = { ServerTime = function() return w.epoch end,
		AuthorizedRank = function(sender, guild) return (w.ranksSeen or {})[c.Fold(c.FullName(sender)) .. "@" .. c.Fold(guild)] end }
	p.Watch, p.ViewAs = { missing = true }, { missing = true }
	p.TabardsV2 = { Collector = function() if o.king then return nil end return w.lease end }
	p.Print = function(m) p.prints[#p.prints + 1] = tostring(m) end
	p.PlayAlert, p.Fire, p.On = function() end, function() end, function() end
	p.Comm = { Handle = function(kind, call) p.handlers[kind] = call end,
		Whisper = function(target, msg, key, urgent, logged, done, options)
			w.bus[#w.bus + 1] = { from = name, target = target, msg = msg, logged = logged, options = options }
			return true
		end }
	-- (The game's dialogs table is one: the officer's client keeps its own two.)
	local dialogs = { StaticPopupDialogs.OLYMPUS_JUDGMENT_ESCALATE, StaticPopupDialogs.OLYMPUS_JUDGMENT_FINAL }
	assert(loadfile(ROOT .. "Olympus/Judgment.lua"))("Olympus", p)
	StaticPopupDialogs.OLYMPUS_JUDGMENT_ESCALATE, StaticPopupDialogs.OLYMPUS_JUDGMENT_FINAL = dialogs[1], dialogs[2]
	p.Judgment.ResetForTests()
	-- (Each client's first ask once the King's client comes on waits a moment of its own within
	-- Judgment.SPREAD: these draw none and ask at once; the spread has its own test.)
	p.Judgment.random = function(low) return low end
	w.peers[c.Fold(name)] = p
	return p
end

local function Deliver(w, c)
	local delivered = 0
	for _ = 1, 50 do
		local batch, kept = {}, {}
		for _, job in ipairs(w.jobs) do
			if type(job.msg) == "string" and job.msg:find("^MJ~") then
				batch[#batch + 1] = { from = c.me, target = job.target, msg = job.msg, logged = job.logged, options = job.options }
			else kept[#kept + 1] = job end
		end
		w.jobs = kept
		for _, m in ipairs(w.bus) do batch[#batch + 1] = m end
		w.bus = {}
		if #batch == 0 then return delivered end
		for _, m in ipairs(batch) do
			assert(m.logged == true, "a logged whisper: " .. m.msg)
			assert(#m.msg <= 255, "within the game's limit: " .. m.msg)
			local allowed = true
			if m.options and m.options.permit then allowed = m.options.permit(m.options.owner, m.options.key, "WHISPER", m.target, m.msg) end
			w.log[#w.log + 1] = m
			if allowed then
				local to = c.Fold(c.FullName(m.target))
				local peer = w.peers[to]
				local handle = peer and peer.handlers.MJ or (to == c.Fold(c.me) and w.handlers.MJ) or nil
				if handle then delivered = delivered + 1; handle("WHISPER", m.from, m.msg) end
			end
		end
	end
	error("the whispers kept coming")
end

local function Texts(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text or "") end
	return table.concat(out, "\n")
end
local function LineWith(lines, text)
	for _, l in ipairs(lines) do if tostring(l.text or ""):find(text, 1, true) then return l end end
end

test("watch: judgment: a case goes to the King, the High Council votes for a day (the majority of those who answered), his final word comes back; nothing else happens", function()
	WithWatch(function(w, W, c)
		local J, L = c.Judgment, ns.L
		Council(w, c)
		w.setRank(c.me, 1); w.setRank("Reporter One-Realm", 3); w.online(c.me)
		for _, msg in ipairs(ReportMessages(w, W, c, { cat = "A" })) do assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg)) end
		assert(W.SetFinding(SPAMMER, "up"))
		local king = Peer(w, c, KING, { king = true })
		local hc1, hc2, hc3 = Peer(w, c, HC1), Peer(w, c, HC2), Peer(w, c, HC3)
		local key = c.Fold(SPAMMER)
		-- The case's page offers it to the officers.
		W.Show("case", key)
		local send = assert(LineWith(W.Build(), L.JUDGMENT_ESCALATE_BTN), "Send it to the King")
		-- Asked first, through ns.ShowDialog (Olympus's own dialog with the gamepad UI); the King's
		-- client is not on: it waits on the officer's.
		send.onClick()
		local d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_JUDGMENT_ESCALATE"); eq(d.data, SPAMMER)
		StaticPopupDialogs.OLYMPUS_JUDGMENT_ESCALATE.OnAccept({ data = d.data }, d.data)
		eq(w.prints[#w.prints], L.JUDGMENT_ESC_PRINT_HELD); eq(#w.jobs, 0)
		local ok, how
		eq(select(2, J.Escalate(SPAMMER)), "already", "once at a time")
		local page = W.Build()
		assert(LineWith(page, L.JUDGMENT_ESC_HELD), "the page says it waits")
		eq(LineWith(page, L.JUDGMENT_ESCALATE_BTN), nil, "and offers it no more")
		-- His client comes on (its lease): the case goes, with the card's facts and the finding alone.
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		J.Tick(false)
		eq(#w.jobs, 1); eq(w.jobs[1].target, KING)
		eq(w.jobs[1].msg, ("MJ~1~E~1~%s~%s~A1~1~0~U"):format(w.guild, SPAMMER))
		assert(not w.jobs[1].msg:find("Reporter", 1, true) and not w.jobs[1].msg:find("flooding", 1, true), "never who reported it nor the note")
		Deliver(w, c)
		local list = king.Judgment.Judgments()
		eq(#list, 1)
		local j = list[1]
		eq(j.from, c.me); eq(j.target, SPAMMER); eq(j.guild, w.guild); eq(j.finding, "U"); eq(j.at, w.epoch)
		eq(j.closes - j.at, 86400, "the council's day")
		eq(J.Escalation(key).jid, j.jid, "the King's client's receipt")
		assert(king.prints[#king.prints]:find(w.guild, 1, true), "the King is told, by guild")
		-- (1.2.0, Konig's review: never the accused's name in his chat, which may be on stream.)
		assert(not king.prints[#king.prints]:find((SPAMMER:gsub("%-Realm$", "")), 1, true), "not the accused's name")
		-- The councillors' clients ask the King's (they heard its lease): each one has it to vote on.
		for _, p in ipairs({ hc1, hc2, hc3 }) do p.Judgment.Tick(false) end
		Deliver(w, c)
		for _, p in ipairs({ hc1, hc2, hc3 }) do eq(#p.Judgment.Open(), 1); eq(p.Judgment.Open()[1].target, SPAMMER) end
		-- One upheld, one not: no majority yet, and the King's word waits for the vote.
		assert(hc1.Judgment.Vote(j.jid, "U")); assert(hc2.Judgment.Vote(j.jid, "D"))
		Deliver(w, c)
		eq(hc1.Judgment.Open()[1].mine, "U", "counted, his client says")
		local up, down, n, size = king.Judgment.Tally(j)
		eq(up, 1); eq(down, 1); eq(n, 2); eq(size, 3)
		eq(king.Judgment.Majority(up, down), nil, "a tie: no majority")
		eq(king.Judgment.State(j), "O")
		ok, how = king.Judgment.Decide(j.jid, "U")
		eq(ok, false); eq(how, "open", "the council still votes")
		-- A councillor's newest vote counts.
		assert(hc2.Judgment.Vote(j.jid, "U")); Deliver(w, c)
		up, down, n = king.Judgment.Tally(j)
		eq(up, 2); eq(down, 0); eq(n, 2)
		eq(king.Judgment.Majority(up, down), "U", "the majority of those who answered")
		-- The officer's client asks how it stands: the council votes.
		J.Tick(false); Deliver(w, c)
		eq(J.Escalation(key).state, "O")
		-- The day passes; the third councillor never answered and can't any more.
		w.epoch = w.epoch + 86400
		eq(king.Judgment.State(j), "W", "the King's word comes next")
		eq(select(2, hc3.Judgment.Vote(j.jid, "D")), "closed")
		J.Tick(false); Deliver(w, c)
		eq(J.Escalation(key).state, "W")
		-- Nobody but the King's own client gives the final word.
		eq(select(2, hc1.Judgment.Decide(j.jid, "U")), "king")
		assert(king.Judgment.Decide(j.jid, "D"), "his word is his: not upheld, whatever the council's majority")
		eq(j.final.v, "D"); eq(j.final.by, KING); eq(j.final.at, w.epoch)
		eq(j.final.up, 2); eq(j.final.down, 0); eq(j.final.answered, 2); eq(j.final.size, 3)
		eq(select(2, king.Judgment.Decide(j.jid, "U")), "decided", "once")
		-- Back to the officer who sent it (his client asked lately): his case's page says it.
		Deliver(w, c)
		local e = J.Escalation(key)
		eq(e.state, "F"); eq(e.verdict, "D"); eq(e.up, 2); eq(e.down, 0); eq(e.answered, 2); eq(e.decidedAt, w.epoch)
		assert(w.prints[#w.prints]:find(L.JUDGMENT_NOT_UPHELD, 1, true), "the officer is told: " .. w.prints[#w.prints])
		page = W.Build()
		assert(LineWith(page, L.JUDGMENT_ESC_FINAL:match("^[^%%]+")), "the case's page keeps the King's word")
		assert(LineWith(page, L.JUDGMENT_ESCALATE_AGAIN), "and may send it again")
		-- His record: who sent it and when, each vote and when, his word with the count and when.
		local record = king.Judgment.Text(j)
		for _, part in ipairs({ "Officer", "Sage One", "Sage Two", L.JUDGMENT_NOT_UPHELD, os.date("%Y-%m-%d %H:%M", w.epoch) }) do
			assert(record:find(part, 1, true), "the record names " .. part .. ":\n" .. record)
		end
		-- Nothing happens by itself: no sanction, nothing to the player, nothing on a channel or a guild.
		eq(W.Record(SPAMMER), nil, "no sanction")
		for _, m in ipairs(w.log) do
			assert(not c.Fold(m.target):find(c.Fold("Spammer Guy"), 1, true), "nothing to the player: " .. m.msg)
			assert(m.msg:find("^MJ~1~"), "only the judgment's whispers")
		end
		for _, job in ipairs(w.jobs) do assert(job.dist == "WHISPER", "no channel or guild message") end
	end)
end)

-- 1.1.6 (WatchChat.PowersBarred): the review's finding: a councillor under a moderator's sanction
-- kept voting. His client sends no vote while it lasts; the King's client, which knows the
-- sanction it gave, takes none from a client that missed it or was modified; a vote he gave
-- before stays counted.
test("watch: chat moderation: a councillor under a moderator's sanction votes on no Judgment: his client sends none, the King's takes none, one he gave before stays", function()
	WithWatch(function(w, W, c)
		local J = c.Judgment
		Council(w, c)
		w.setRank(c.me, 1); w.setRank("Reporter One-Realm", 3); w.online(c.me)
		for _, msg in ipairs(ReportMessages(w, W, c, { cat = "A" })) do assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg)) end
		assert(W.SetFinding(SPAMMER, "up"))
		local king = Peer(w, c, KING, { king = true })
		local hc1, hc2 = Peer(w, c, HC1), Peer(w, c, HC2)
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		assert(J.Escalate(SPAMMER))
		J.Tick(false)
		Deliver(w, c)
		local j = assert(king.Judgment.Judgments()[1], "the King's client has the case")
		for _, p in ipairs({ hc1, hc2 }) do p.Judgment.Tick(false) end
		Deliver(w, c)
		assert(hc2.Judgment.Vote(j.jid, "U"))
		Deliver(w, c)
		local own, kings = {}, {}
		hc1.WatchChat = { PowersBarred = function(name) if own[c.Fold(c.FullName(name))] then return { kind = "timeout" } end end }
		king.WatchChat = { PowersBarred = function(name) if kings[c.Fold(c.FullName(name))] then return { kind = "timeout" } end end }
		own[c.Fold(HC1)] = true
		local ok, why = hc1.Judgment.Vote(j.jid, "D")
		eq(ok, false); eq(why, "sanction", "his own client sends none")
		eq(rawget(ns.L, "JUDGMENT_WHY_SANCTION") ~= nil, true)
		-- A client that missed it (or a modified one) sends it; the King's client knows it: refused.
		own[c.Fold(HC1)] = nil
		kings[c.Fold(HC1)], kings[c.Fold(HC2)] = true, true
		assert(hc1.Judgment.Vote(j.jid, "D"))
		Deliver(w, c)
		local up, down, n = king.Judgment.Tally(j)
		eq(down, 0, "the King's client took none"); eq(up, 1, "the vote he gave before stays"); eq(n, 1)
	end)
end)

test("watch: judgment: the King's client takes a case only from an officer as it sees him; each end hears only the King's client and the council", function()
	WithWatch(function(w, W, c)
		local J, L = c.Judgment, ns.L
		Council(w, c)
		w.setRank(c.me, 1); w.setRank("Reporter One-Realm", 3); w.online(c.me)
		for _, msg in ipairs(ReportMessages(w, W, c, {})) do assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg)) end
		local king, hc1 = Peer(w, c, KING, { king = true }), Peer(w, c, HC1)
		local key = c.Fold(SPAMMER)
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		-- The King's client does not see this officer as one (no roster, census or manifest says so).
		w.ranksSeen = {}
		assert(J.Escalate(SPAMMER)); Deliver(w, c)
		eq(#king.Judgment.Judgments(), 0)
		eq(J.Escalation(key).refused, "rank")
		W.Show("case", key)
		assert(LineWith(W.Build(), L.JUDGMENT_WHY_RANK), "the case's page says why")
		assert(LineWith(W.Build(), L.JUDGMENT_ESCALATE_AGAIN), "and may send it again")
		-- Seen as a Captain: taken; the same one again (a retry) is the same judgment.
		w.ranksSeen = { [c.Fold(c.me) .. "@" .. c.Fold(w.guild)] = 1 }
		assert(J.Escalate(SPAMMER)); Deliver(w, c)
		eq(#king.Judgment.Judgments(), 1)
		local jid = J.Escalation(key).jid
		assert(jid)
		eq(select(3, king.Judgment.Handle("WHISPER", c.me, ("MJ~1~E~2~%s~%s~A1~1~0~-"):format(w.guild, SPAMMER))), "again")
		eq(#king.Judgment.Judgments(), 1)
		-- Another officer of that guild on the same name while it is open: the same judgment, his too.
		w.ranksSeen[c.Fold("Captain Two-Realm") .. "@" .. c.Fold(w.guild)] = 1
		local ok, j2, how = king.Judgment.Handle("WHISPER", "Captain Two-Realm", ("MJ~1~E~7~%s~%s~S2~2~1~-"):format(w.guild, SPAMMER))
		eq(ok, true); eq(j2, jid); eq(how, "open")
		-- Not on himself, nor on the King.
		eq(select(2, king.Judgment.Handle("WHISPER", c.me, ("MJ~1~E~3~%s~%s~A1~1~0~-"):format(w.guild, c.me))), "target")
		eq(select(2, king.Judgment.Handle("WHISPER", c.me, ("MJ~1~E~4~%s~%s~A1~1~0~-"):format(w.guild, KING))), "target")
		-- Five a day from one officer.
		for i = 1, 4 do assert(king.Judgment.Handle("WHISPER", c.me, ("MJ~1~E~%d~%s~Case %d-Realm~A1~1~0~-"):format(10 + i, w.guild, i))) end
		eq(select(2, king.Judgment.Handle("WHISPER", c.me, ("MJ~1~E~20~%s~Case Six-Realm~A1~1~0~-"):format(w.guild))), "day")
		-- What does not read is refused: a field too many or missing, an unknown category, an outside guild.
		for _, bad in ipairs({ "MJ~1~E~30~Olympus II~X-Realm~A1~1~0", "MJ~1~E~30~Olympus II~X-Realm~Z1~1~0~-",
			"MJ~1~E~30~Olympus II~X-Realm~A1A2~1~0~-", "MJ~1~E~30~Horde Guild~X-Realm~A1~1~0~-", "MJ~2~E~30~Olympus II~X-Realm~A1~1~0~-",
			"MJ~1~V~1~maybe", "MJ~1~R~1~F~-~0~0~0~0" }) do
			eq(king.Judgment.Handle("WHISPER", c.me, bad), false, bad)
		end
		eq(king.Judgment.Handle("CHANNEL", c.me, ("MJ~1~E~31~%s~Y-Realm~A1~1~0~-"):format(w.guild)), false, "a whisper or nothing")
		-- Only the council votes; only the King's client is heard by the council and the officers.
		eq(select(2, king.Judgment.Handle("WHISPER", "Somebody Else-Realm", ("MJ~1~V~%d~U"):format(jid))), "council")
		eq(select(2, hc1.Judgment.Handle("WHISPER", "Pretender-Realm", ("MJ~1~J~%d~3600~Olympus II~Victim-Realm~A1~1~0~-~-"):format(jid + 50))), "sender")
		eq(#hc1.Judgment.Open(), 0)
		eq(select(2, J.Handle("WHISPER", "Pretender-Realm", ("MJ~1~R~%d~F~U~3~0~3~%d"):format(jid, w.epoch))), "sender")
		eq(J.Escalation(key).state, "O", "a forged final word changes nothing")
		-- A councillor's vote with the King's client away does not go.
		hc1.Judgment.Tick(false); Deliver(w, c)
		eq(#hc1.Judgment.Open(), 5, "this one and the officer's four others of the day")
		-- A new case while that councillor's client asked lately: it hears of it at once.
		assert(king.Judgment.Handle("WHISPER", "Captain Two-Realm", ("MJ~1~E~8~%s~Fresh Case-Realm~O1~1~0~-"):format(w.guild)))
		Deliver(w, c)
		eq(#hc1.Judgment.Open(), 6, "told at once")
		w.lease = nil
		eq(select(2, hc1.Judgment.Vote(jid, "U")), "away")
		-- The King's preview (the author's test build) shows his page, never his word.
		local preview = Peer(w, c, "Author Preview-Realm")
		preview.King.Preview = function() return true end
		eq(preview.Judgment.KingSide(), true)
		eq(select(2, preview.Judgment.Decide(jid, "U")), "king")
	end)
end)

-- Reviewer (2026-10-05): the King's client answered every case it did not take with a refusal of
-- its own, each case's id a new queued whisper: one player with no rank, whispering ever-new ids,
-- kept its queue full (Comm's MAX_QUEUE), and the Tabards' lease and the council's answers fell out.
test("watch: judgment: the King's client refuses one sender once a minute at most, and so many in all; the cases it takes are answered all the same", function()
	WithWatch(function(w, W, c)
		Council(w, c)
		local KJ = Peer(w, c, KING, { king = true }).Judgment
		local stranger = "Nobody Ranked-Realm"
		local function To(name)
			local n = 0
			for _, m in ipairs(w.bus) do if c.Fold(c.FullName(m.target)) == c.Fold(name) then n = n + 1 end end
			return n
		end
		for id = 1, 100 do
			local ok, why = KJ.Handle("WHISPER", stranger, ("MJ~1~E~%d~%s~Victim One-Realm~A1~1~0~-"):format(id, w.guild))
			eq(ok, false); eq(why, "rank")
		end
		eq(#KJ.Judgments(), 0)
		eq(To(stranger), 1, "one refusal, not a hundred")
		eq(w.bus[1].msg, "MJ~1~A~1~-~rank", "and why")
		eq(w.bus[1].options.key, "judgment-a-" .. c.Fold(stranger) .. "-no", "keyed by its sender: a newer one takes its place")
		-- A minute on: one more.
		w.epoch = w.epoch + KJ.REFUSE_GAP
		KJ.Handle("WHISPER", stranger, ("MJ~1~E~101~%s~Victim One-Realm~A1~1~0~-"):format(w.guild))
		eq(To(stranger), 2)
		-- Many senders in one minute: REFUSE_MINUTE refusals in all.
		w.epoch, w.bus = w.epoch + 60, {}
		for i = 1, 30 do
			KJ.Handle("WHISPER", ("Stranger %s-Realm"):format(string.char(64 + i)), ("MJ~1~E~1~%s~Victim One-Realm~A1~1~0~-"):format(w.guild))
		end
		eq(#w.bus, KJ.REFUSE_MINUTE)
		-- An officer as the King's client sees him: his case's receipt goes, whatever the refusals.
		w.bus = {}
		local ok, jid, how = KJ.Handle("WHISPER", c.me, ("MJ~1~E~1~%s~%s~A1~1~0~-"):format(w.guild, SPAMMER))
		eq(ok, true); eq(how, "new")
		eq(To(c.me), 1); eq(w.bus[1].msg, ("MJ~1~A~1~%d"):format(jid))
	end)
end)

-- Reviewer (2026-10-05): one answer names SHOWN (8) open cases, the nearest end first, those voted
-- on too, and a councillor's client forgot whatever that list left out: a ninth case reached no
-- councillor before the first ones closed, and one told to him at once was gone at his next ask.
test("watch: judgment: past the SHOWN nearest, each open case still reaches every councillor; his client forgets only what a whole list leaves out", function()
	WithWatch(function(w, W, c)
		local L = ns.L
		Council(w, c)
		local KJ = Peer(w, c, KING, { king = true }).Judgment
		local hc1, hc2, hc3 = Peer(w, c, HC1), Peer(w, c, HC2), Peer(w, c, HC3)
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		-- Three officers of the guild, each case a few seconds after the last (the nearest end first).
		local officers = { c.me, "Captain Two-Realm", "Captain Three-Realm" }
		for _, name in ipairs(officers) do w.ranksSeen[c.Fold(name) .. "@" .. c.Fold(w.guild)] = 1 end
		local n, jids = 0, {}
		local function NewCase()
			n = n + 1
			w.epoch = w.epoch + 10
			local from = officers[math.floor((n - 1) / 4) + 1]
			local _, jid, how = KJ.Handle("WHISPER", from, ("MJ~1~E~%d~%s~Case %s-Realm~A1~1~0~-"):format(n, w.guild, string.char(64 + n)))
			eq(how, "new", "case " .. n)
			return jid
		end
		local function Has(p, jid)
			for _, e in ipairs(p.Judgment.Open()) do if e.jid == jid then return e end end
		end
		-- How many more his page says are open (nil: no such line).
		local function More(p)
			for _, l in ipairs(p.Judgment.Lines()) do
				for k = 1, KJ.MAX do if tostring(l.text or ""):find(L.JUDGMENT_MORE:format(k), 1, true) then return k end end
			end
		end
		for i = 1, KJ.SHOWN do jids[i] = NewCase() end
		Deliver(w, c)
		hc1.Judgment.Tick(false); Deliver(w, c)
		eq(#hc1.Judgment.Open(), KJ.SHOWN, "all of them, in one list")
		eq(More(hc1), nil, "nothing more")
		-- A ninth: told at once (his client asked lately), and kept at his next ask, whose list names
		-- the eight nearest and says nine are open.
		jids[9] = NewCase(); Deliver(w, c)
		assert(Has(hc1, jids[9]), "told at once")
		w.epoch = w.epoch + 60
		hc1.Judgment.Tick(true); Deliver(w, c)
		assert(Has(hc1, jids[9]), "not forgotten: the list did not name every open one")
		eq(#hc1.Judgment.Open(), 9)
		local ends = {}
		for _, m in ipairs(w.log) do if m.msg:find("^MJ~1~N~") then ends[#ends + 1] = m.msg end end
		eq(ends[#ends], "MJ~1~N~8~9")
		eq(More(hc1), 1, "his page says one more is open")
		-- Another councillor, who never heard of it: the eight nearest; once he voted on one, the ninth.
		hc2.Judgment.Tick(false); Deliver(w, c)
		eq(#hc2.Judgment.Open(), KJ.SHOWN); eq(Has(hc2, jids[9]), nil)
		assert(hc2.Judgment.Vote(jids[1], "U")); Deliver(w, c)
		w.epoch = w.epoch + 60
		hc2.Judgment.Tick(true); Deliver(w, c)
		assert(Has(hc2, jids[9]), "the ninth, his vote on the first left room for it")
		eq(Has(hc2, jids[1]).mine, "U", "the one he voted on stays, with his vote")
		-- Every councillor answered the first: its vote is over, and a whole list leaves it out.
		assert(hc1.Judgment.Vote(jids[1], "D")); Deliver(w, c)
		hc3.Judgment.Tick(false); Deliver(w, c)
		assert(hc3.Judgment.Vote(jids[1], "U")); Deliver(w, c)
		eq(KJ.State(KJ.Find(jids[1])), "W")
		w.epoch = w.epoch + 60
		hc1.Judgment.Tick(true); Deliver(w, c)
		eq(#hc1.Judgment.Open(), KJ.SHOWN); eq(Has(hc1, jids[1]), nil, "closed: the whole list left it out")
		eq(More(hc1), nil)
	end)
end)

-- Reviewer (2026-10-05): each client took a new id of the Tabards' lease for the King's client
-- coming on, and that id is new at every announcement (TabardsV2.LEASE_EVERY, 8 minutes): every
-- councillor's client asked every 8 minutes, not every 15, and all of them in the same minute.
test("watch: judgment: a councillor's client asks once the King's client comes on, at a moment of its own, then every QUERY_EVERY; a new lease id is no new King", function()
	WithWatch(function(w, W, c)
		Council(w, c)
		local hc1, hc2 = Peer(w, c, HC1), Peer(w, c, HC2)
		local J1 = hc1.Judgment
		J1.random = function(low, high) eq(low, 0); eq(high, J1.SPREAD); return 120 end
		local function Asks(name)
			local n = 0
			for _, m in ipairs(w.bus) do if m.from == name and m.msg:find("^MJ~1~Q~") then n = n + 1 end end
			return n
		end
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		eq(J1.Tick(false), false, "not at once"); eq(hc2.Judgment.Tick(false), true, "the other drew none: at once")
		w.epoch = w.epoch + 60; eq(J1.Tick(false), false)
		w.epoch = w.epoch + 60; eq(J1.Tick(false), true, "at its own moment, two minutes on")
		eq(Asks(HC1), 1)
		-- The King's client announces again (a new id, 8 minutes on): nothing new to ask.
		w.lease = { name = KING, guild = "Olympus", id = "lease-2" }
		w.epoch = w.epoch + 8 * 60
		eq(J1.Tick(false), false, "a new lease id is the same King's client")
		eq(hc2.Judgment.Tick(false), false)
		w.epoch = w.epoch + J1.QUERY_EVERY - 8 * 60
		eq(J1.Tick(false), true, "every QUERY_EVERY")
		eq(Asks(HC1), 2)
		-- It goes and comes back: a moment of its own again.
		w.lease = nil
		w.epoch = w.epoch + 60; eq(J1.Tick(false), false)
		w.lease = { name = KING, guild = "Olympus", id = "lease-3" }
		w.epoch = w.epoch + 60; eq(J1.Tick(false), false, "not at once")
		w.epoch = w.epoch + 120; eq(J1.Tick(false), true)
		eq(Asks(HC1), 3)
	end)
end)

-- Reviewer (2026-10-05): the King's client took a case with an id it had from that officer for a
-- retry of it, whatever its guild and name: an officer's count starts again in another guild's
-- Watch (or once his saved variables are gone), and his new case got the old one's judgment.
test("watch: judgment: a retry is its sender's id on the same guild and name; the same id from another guild or on another name is a new case", function()
	WithWatch(function(w, W, c)
		Council(w, c)
		local KJ = Peer(w, c, KING, { king = true }).Judgment
		w.ranksSeen[c.Fold(c.me) .. "@" .. c.Fold("Olympus III")] = 1
		local ok, first, how = KJ.Handle("WHISPER", c.me, ("MJ~1~E~1~%s~%s~A1~1~0~-"):format(w.guild, SPAMMER))
		eq(ok, true); eq(how, "new")
		local _, again, how2 = KJ.Handle("WHISPER", c.me, ("MJ~1~E~1~%s~%s~A1~1~0~-"):format(w.guild, SPAMMER))
		eq(again, first); eq(how2, "again", "the same case again")
		local _, other, how3 = KJ.Handle("WHISPER", c.me, "MJ~1~E~1~Olympus III~Other Name-Realm~S1~1~0~-")
		eq(how3, "new", "another guild's case with the same id")
		assert(other ~= first)
		local j = KJ.Find(other)
		eq(j.guild, "Olympus III"); eq(j.target, "Other Name-Realm")
		local _, third, how4 = KJ.Handle("WHISPER", c.me, ("MJ~1~E~1~%s~Third Name-Realm~E1~1~0~-"):format(w.guild))
		eq(how4, "new", "another name in the same guild"); assert(third ~= first and third ~= other)
		eq(#KJ.Judgments(), 3)
	end)
end)

test("watch: judgment: The Watch's Judgments for the King, his final word through our own dialog, and a councillor who is no officer sees them alone", function()
	WithWatch(function(w, W, c)
		local J, L = c.Judgment, ns.L
		Council(w, c)
		-- The King's own guild: his client is the officer's and the King's (no whisper for it).
		w.setRank(c.me, 0); w.setRank("Reporter One-Realm", 3); w.online(c.me)
		w.king = c.me
		c.King.IsKing = function() return true end
		c.rdb.council = { names = w.councilNames }
		for _, msg in ipairs(ReportMessages(w, W, c, { cat = "S" })) do assert(W.HandleReport("WHISPER", "Reporter One-Realm", msg)) end
		local ok, how = J.Escalate(SPAMMER)
		eq(ok, true); eq(how, "sent"); eq(#w.jobs, 0, "nothing whispered")
		local j = assert(J.Judgments()[1])
		eq(j.from, c.me)
		-- The Watch's navigation: Desk, Reports, Cases, Judgments (one waiting).
		W.Show(nil)
		local nav = W.Build()[1].nav
		eq(#nav, 5); eq(nav[4].text, L.WATCH_NAV_JUDGMENTS:format(1))
		nav[4].onClick()
		eq(W.PageId(), "judgments")
		eq(W.ViewKey(), "judgments", "no buttons of the desk's under it: its own lines act")
		local lines, title, detail = W.Build()
		eq(title, L.TAB_WATCH); eq(detail, L.JUDGMENT_DETAIL)
		assert(LineWith(lines, L.JUDGMENT_TITLE), "the King's Judgments")
		assert(LineWith(lines, L.JUDGMENT_FINAL_WAIT:match("^[^%%]+")), "his word waits for the council")
		eq(LineWith(lines, L.JUDGMENT_FINAL_UP_BTN), nil)
		-- The day passes: his two buttons, each through ns.ShowDialog (Olympus's own with the gamepad UI).
		w.epoch = w.epoch + 86400
		lines = W.Build()
		local up = assert(LineWith(lines, L.JUDGMENT_FINAL_UP_BTN))
		assert(LineWith(lines, L.JUDGMENT_FINAL_DOWN_BTN))
		up.onClick()
		local d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_JUDGMENT_FINAL"); eq(d.data.jid, j.jid); eq(d.data.v, "U")
		StaticPopupDialogs.OLYMPUS_JUDGMENT_FINAL.OnAccept({ data = d.data }, d.data)
		eq(j.final.v, "U"); eq(j.final.answered, 0, "nobody answered: his word all the same")
		eq(J.Escalation(c.Fold(SPAMMER)).state, "F", "his own guild's case has it")
		assert(LineWith(W.Build(), L.JUDGMENT_FINAL_LINE:match("^[^%%]+")))
		-- The copy box, Olympus's own.
		LineWith(W.Build(), L.JUDGMENT_COPY).onClick()
		assert(w.copied and w.copied.text:find(L.JUDGMENT_UPHELD, 1, true))
		-- A councillor shares the King's desk navigation, not guild-local officer authority.
		c.King.IsKing = function() return false end
		w.king = KING
		w.setRank(c.me, 3)
		w.council[c.Fold(c.me)] = true
		eq(W.CanRead(), false); eq(W.TabVisible(), true, "The Council's desk")
		W.Show(nil)
		eq(W.PageId(), "desk")
		eq(W.CanManage(), false); eq(#W.Records(), 0); eq(#W.Cases(), 0)
		W.Show("judgments")
		lines = W.Build()
		assert(#lines[1].nav > 2, "the Council keeps the shared desk navigation")
		assert(LineWith(lines, L.JUDGMENT_COUNCIL_TITLE)); assert(LineWith(lines, L.JUDGMENT_KING_AWAY))
		eq(LineWith(lines, L.JUDGMENT_TITLE .. "\n"), nil)
		assert(W.Slash("judgments")); eq(w.selected, "watch")
		-- Nobody else: an ordinary member sees no Judgments.
		w.council[c.Fold(c.me)] = nil
		eq(W.JudgmentsShown(), false); eq(W.TabVisible(), false); eq(W.PageId(), "member")
		-- The author's View as: every page in his own view; a role's preview, that role's.
		w.author = "my"; eq(W.JudgmentsShown(), true)
		w.author, w.allows = "member", {}; eq(W.JudgmentsShown(), false)
		w.author, w.allows = "councillor", { judgments = true }; eq(W.JudgmentsShown(), true); eq(J.CouncilSide(), true)
		w.author, w.allows = nil, nil
		-- No Blizzard menu or popup of its own: its two questions are ns.ShowDialog's.
		local src = assert(io.open(ROOT .. "Olympus/Judgment.lua", "rb")):read("*a")
		for _, api in ipairs({ "StaticPopup_Show", "MenuUtil", "EasyMenu", "UIDropDownMenu", "CHANNEL", "\"GUILD\"", "SendChatMessage" }) do
			assert(not src:find(api, 1, true), "Judgment.lua uses " .. api)
		end
	end)
end)

test("watch: judgment: its strings in English and pt-BR, with the same placeholders", function()
	local oldLocale = GetLocale
	local pt = {}
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales.lua")), "Olympus", pt)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	local n = 0
	for k, v in pairs(ns.L) do
		if type(k) == "string" and (k:find("^JUDGMENT_") or k == "WATCH_NAV_JUDGMENTS") then
			n = n + 1
			local p = rawget(pt.L, k)
			assert(p and p ~= v, "pt-BR: " .. k)
			local a, b = {}, {}
			for x in v:gmatch("%%%d*[sd]") do a[#a + 1] = x end
			for x in p:gmatch("%%%d*[sd]") do b[#b + 1] = x end
			eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. k)
		end
	end
	assert(n >= 70, "the strings: " .. n)
end)

test("watch: judgment: one guild's officers keep at most J.MAX_OPEN_GUILD cases open with the King; another guild's still reach him (Konig's review)", function()
	WithWatch(function(w, W, c)
		Council(w, c)
		local KJ = Peer(w, c, KING, { king = true }).Judgment
		w.lease = { name = KING, guild = "Olympus", id = "lease-1" }
		local officers = { c.me, "Captain Two-Realm", "Captain Three-Realm" }
		for _, name in ipairs(officers) do w.ranksSeen[c.Fold(name) .. "@" .. c.Fold(w.guild)] = 1 end
		w.ranksSeen[c.Fold("Captain Other-Realm") .. "@" .. c.Fold("Olympus Other")] = 1
		for n = 1, KJ.MAX_OPEN_GUILD do
			w.epoch = w.epoch + 10
			local _, _, how = KJ.Handle("WHISPER", officers[math.floor((n - 1) / 4) + 1], ("MJ~1~E~%d~%s~Case %s-Realm~A1~1~0~-"):format(n, w.guild, string.char(64 + n)))
			eq(how, "new", "case " .. n)
		end
		w.epoch = w.epoch + 10
		eq(select(2, KJ.Handle("WHISPER", "Captain Three-Realm", ("MJ~1~E~99~%s~One Too Many-Realm~A1~1~0~-"):format(w.guild))), "full", "that guild's cases: full")
		local _, _, how = KJ.Handle("WHISPER", "Captain Other-Realm", "MJ~1~E~1~Olympus Other~Their Case-Realm~A1~1~0~-")
		eq(how, "new", "another guild's case still reaches the King")
	end)
end)
