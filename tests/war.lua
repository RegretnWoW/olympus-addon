local ns, test, eq = ...
local War = ns.War

print("War.lua: own-guild operations, LFG and Centuries")

local function WithWar(fn)
	local originalUI = ns.UI
	ns.UI = ns.UI or {}
	local saved = {
		me = ns.me, now = ns.Now, fire = ns.Fire, chat = ns.ChatLocked,
		council = ns.IsHighCouncillor, title = ns.CouncilTitle, preview = ns.ViewAs, rosterFresh = ns.Roster.Fresh,
		rosterByName = ns.Roster.byName, rosterMembers = ns.Roster.members,
		rosterOfficer = ns.Roster.IsOfficer, rosterRank = ns.Roster.RankOf,
		send = ns.Comm.Send, chunk = ns.Comm.SendChunked,
		warAfter = War.after,
		uiRefresh = ns.UI.Refresh, uiSelect = ns.UI.SelectTab, uiShown = ns.UI.IsShown, uiRefreshSoon = ns.UI.RefreshSoon,
		getGuild = GetGuildInfo, inGuild = IsInGuild, server = GetServerTime,
	}
	local clock, rank, guild, sent, later = 1700000000, 0, "Olympus II", {}, {}
	ns.me = "Officer-Realm"
	ns.Now = function() return clock end
	ns.Fire = function() end
	ns.ChatLocked = function() return false end
	ns.UI.Refresh = function() end -- The list renderer redraws after expanding a real row.
	ns.IsHighCouncillor = function() return false end
	ns.CouncilTitle = function() return nil end
	ns.ViewAs = { Available = function() return false end }
	ns.Roster.Fresh = function() return ns.Roster end
	GetServerTime = function() return clock end
	IsInGuild = function() return true end
	GetGuildInfo = function() return guild, nil, rank end
	local members = {
		{ full = "Officer-Realm", name = "Officer", rankIndex = 0, rank = "Guild Master", online = true, class = "WA", level = 60 },
		{ full = "Relay-Realm", name = "Relay", rankIndex = 1, rank = "Officer", online = false, class = "PA", level = 60 },
		{ full = "OtherOfficer-Realm", name = "OtherOfficer", rankIndex = 1, rank = "Officer", online = false, class = "RO", level = 60 },
		{ full = "Tanky One-Realm", name = "Tanky One", rankIndex = 3, rank = "Member", online = true, class = "WA", level = 60 },
		{ full = "Mage One-Realm", name = "Mage One", rankIndex = 3, rank = "Member", online = true, class = "MA", level = 60 },
		{ full = "Ordinary-Realm", name = "Ordinary", rankIndex = 3, rank = "Member", online = true, class = "PR", level = 60 },
	}
	ns.Roster.byName = {}
	for _, m in ipairs(members) do ns.Roster.byName[m.full] = m.rankIndex end
	ns.Roster.members = members
	ns.Roster.RankOf = function(name) return ns.Roster.byName[ns.FullName(name)] end
	ns.Roster.IsOfficer = function() return rank <= ns.CAPTAIN_RANK end
	local function Capture(kind, ...)
		local a = { ... }
		sent[#sent + 1] = { kind = kind, args = a, msg = kind == "send" and a[2] or a[1], options = kind == "send" and a[7] or a[5] }
		return true
	end
	ns.Comm.Send = function(...) return Capture("send", ...) end
	ns.Comm.SendChunked = function(...) return Capture("chunk", ...) end
	War.after = function(_, _, fn) later[#later + 1] = fn end
	War.Reset()
	local ok, err = pcall(fn, {
		sent = sent,
		clock = function(n) if n then clock = n end return clock end,
		rank = function(n) if n ~= nil then rank = n end return rank end,
		guild = function(n) if n ~= nil then guild = n end return guild end,
		b36 = function(n) return ns.Codec.Base36(n) end,
		runNext = function() local f = table.remove(later, 1); assert(f, "no delayed War callback"); return f() end,
	})
	War.Reset()
	War.after = saved.warAfter
	ns.me, ns.Now, ns.Fire, ns.ChatLocked = saved.me, saved.now, saved.fire, saved.chat
	ns.IsHighCouncillor, ns.CouncilTitle, ns.ViewAs, ns.Roster.Fresh = saved.council, saved.title, saved.preview, saved.rosterFresh
	ns.Roster.byName, ns.Roster.members = saved.rosterByName, saved.rosterMembers
	ns.Roster.IsOfficer, ns.Roster.RankOf = saved.rosterOfficer, saved.rosterRank
	ns.Comm.Send, ns.Comm.SendChunked = saved.send, saved.chunk
	ns.UI.Refresh, ns.UI.SelectTab, ns.UI.IsShown, ns.UI.RefreshSoon = saved.uiRefresh, saved.uiSelect, saved.uiShown, saved.uiRefreshSoon
	if not originalUI then ns.UI = nil end
	GetGuildInfo, IsInGuild, GetServerTime = saved.getGuild, saved.inGuild, saved.server
	if not ok then error(err, 0) end
end

test("1.2 War: signed War councillors act only with current own-guild membership; unrelated council titles cannot grant a duty", function()
	WithWar(function(w)
		w.rank(3)
		ns.IsHighCouncillor = function(name) return name == ns.me end
		ns.CouncilTitle = function() return { dept = "Federal Treasury" } end
		eq(War.IsOfficer(), false)
		ns.CouncilTitle = function() return { dept = "Department of War" } end
		eq(War.IsOfficer(), true)
		assert(War.CreateOperation("raid 30 tank=1 | Guild operation"))
		local packet = w.sent[#w.sent]
		eq(packet.options.permit(War, packet.options.key, "GUILD", nil, packet.msg), true)
		ns.Roster.Fresh = function() return nil end
		eq(War.IsOfficer(), false)
		eq(packet.options.permit(War, packet.options.key, "GUILD", nil, packet.msg), false)
		ns.Roster.Fresh = function() return ns.Roster end
		ns.Roster.byName[ns.me] = nil
		eq(War.IsOfficer(), false, "not in the current guild's roster")
	end)
end)

test("1.2 War: empty expanded operation and century lists explain missing records and member previews are inert", function()
	WithWar(function(w)
		local op = assert(War.CreateOperation("raid 30 tank=1 | Empty operation"))
		local century = assert(War.CreateCentury("raid tank=1 | Tanky One | Empty century"))
		local function Find(text)
			for _, row in ipairs(War.Lines()) do if tostring(row.text):find(text, 1, true) then return row end end
		end
		Find(op.title).onClick(); Find(century.name).onClick()
		assert(Find(ns.L.WAR_AFTER_EMPTY)); assert(Find(ns.L.WAR_POSTS_EMPTY))
		local action = Find(ns.L.WAR_START).onClick
		assert(action)
		ns.ViewAs = { Available = function() return true end, Role = function() return "member" end }
		local before = #w.sent
		action(); eq(#w.sent, before, "stale real-view action cannot send in preview")
		for i, row in ipairs(War.Lines()) do if i > 1 then eq(row.onClick, nil, "read-only member preview") end end
		eq(Find(ns.L.WAR_START), nil, "member sees no operation controls")
	end)
end)

test("1.2 War: self-declared roles and LFG expire and queued officer writes recheck authority", function()
	WithWar(function(w)
		local roles = assert(War.SetRoles("healer support"))
		eq(table.concat(roles.roles, ","), "healer,support")
		eq(War.RoleOf("Officer-Realm"), "Healer, Support")
		local lfg = assert(War.PostLFG("raid 30 healer support | ready at the stone"))
		eq(lfg.kind, "raid"); eq(lfg.expires, w.clock() + 1800)
		assert(w.sent[#w.sent].msg:find("^WZ~1~L~"))

		local op = assert(War.CreateOperation("raid 10 tank=1 healer=1 | Molten Core"))
		local queued = w.sent[#w.sent]
		assert(queued.msg:find("^WZ~1~O~")); assert(queued.options and queued.options.permit)
		eq(queued.options.permit(War, queued.options.key, "GUILD", nil, queued.msg), true)
		w.rank(3)
		local allowed, why = queued.options.permit(War, queued.options.key, "GUILD", nil, queued.msg)
		eq(allowed, false); eq(why, "revoked")
		w.rank(0)
		w.guild("Olympus III")
		allowed, why = queued.options.permit(War, queued.options.key, "GUILD", nil, queued.msg)
		eq(allowed, false); eq(why, "guild-changed", "queued guild data never crosses a guild transfer")
		w.guild("Olympus II")
		local rev = w.b36(w.clock())
		w.guild("Random Guild")
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~R~" .. rev .. "~healer"), false, "incoming guild records fail closed outside the current Olympus guild")
		w.guild("Olympus II")

		w.clock(lfg.expires + 1)
		War.Prune()
		eq(War.Store(false).lfg[ns.Fold(ns.me)], nil, "an availability card never becomes permanent")
		eq(op.state, "planned")
	end)
end)

test("1.2 War: GUILD vouches for self records but only a roster officer can mutate guild records", function()
	WithWar(function(w)
		local rev, start = w.b36(w.clock()), w.b36(w.clock() + 600)
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~R~" .. rev .. "~healer"))
		eq(War.RoleOf("Ordinary-Realm"), "Healer")
		local forged = "WZ~1~O~op123~" .. rev .. "~raid~planned~" .. start .. "~Ordinary-Realm~healer:1~Forged raid"
		eq(War.Handle("GUILD", "Ordinary-Realm", forged), false)
		eq(War.Store(false).operations.op123, nil)
		local valid = "WZ~1~O~op123~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~healer:1~Real raid"
		assert(War.Handle("GUILD", "Relay-Realm", valid))
		eq(War.Store(false).operations.op123.title, "Real raid")
		eq(War.Handle("CHANNEL", "Relay-Realm", valid), false, "guild records never cross to the federal channel")
	end)
end)

test("1.2 War: malformed, unsolicited, future and flood inputs fail closed", function()
	WithWar(function(w)
		local rev, start = w.b36(w.clock()), w.b36(w.clock() + 600)
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~2~R~" .. rev .. "~tank"), false, "unknown protocol")
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~1~S~neverasked~0~0~1^O~op123~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~tank:1~No"), false)
		local future = w.b36(w.clock() + 3601)
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~1~O~op999~" .. future .. "~raid~planned~" .. start .. "~Officer-Realm~tank:1~Future"), false)
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~1~O~op999~" .. rev .. "~raid~planned~" .. start .. "~Outsider-Realm~tank:1~Outsider"), false)

		for i = 1, War.INBOUND_MAX do
			assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~R~" .. w.b36(w.clock() + i) .. "~healer"), i)
		end
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~R~" .. w.b36(w.clock() + 100) .. "~tank"), false, "per-sender flood cap")
	end)
end)

test("1.2 War: recovery nonces do not repeat in one second and manual sync is rate-limited", function()
	WithWar(function(w)
		local nonces = {}
		for _ = 1, 3 do
			assert(War.Ask(true))
			local nonce = assert(w.sent[#w.sent].msg:match("^WZ~1~Q~([0-9a-z]+)$"))
			assert(not nonces[nonce], "a new request cannot accept a prior request's replay")
			nonces[nonce] = true
		end
		eq(War.Ask(true), false, "manual sync is bounded like incoming recovery requests")
	end)
end)

test("1.2 War: recovery requests have per-guild and per-sender burst limits", function()
	WithWar(function()
		for i = 1, 6 do
			assert(War.Handle("GUILD", "Asker" .. i .. "-Realm", "WZ~1~Q~nonce" .. i))
		end
		eq(War.Handle("GUILD", "Asker7-Realm", "WZ~1~Q~nonce7"), false, "one guild-wide burst cannot fan out unbounded replies")
	end)
end)

test("1.2 War: duplicate, reordered and replayed records cannot replace newer state", function()
	WithWar(function(w)
		local start = w.b36(w.clock() + 600)
		local function Op(rev, state, title)
			return ("WZ~1~O~op123~%s~raid~%s~%s~Officer-Realm~tank:1~%s"):format(w.b36(rev), state, start, title)
		end
		assert(War.Handle("GUILD", "Relay-Realm", Op(w.clock(), "planned", "First")))
		eq(War.Handle("GUILD", "Relay-Realm", Op(w.clock(), "cancelled", "Duplicate")), false)
		eq(War.Handle("GUILD", "Relay-Realm", Op(w.clock() - 1, "active", "Reordered")), false)
		eq(War.Store(false).operations.op123.title, "First")
		assert(War.Handle("GUILD", "Relay-Realm", Op(w.clock() + 1, "active", "Newest")))
		eq(War.Store(false).operations.op123.title, "Newest")
		eq(War.Handle("GUILD", "Relay-Realm", Op(w.clock(), "planned", "Replay")), false)
		assert(War.Handle("GUILD", "Relay-Realm", Op(w.clock() + 2, "complete", "Finished")), "a missed active packet does not block a later terminal state")
		eq(War.Handle("GUILD", "Relay-Realm", Op(w.clock() + 3, "active", "Reopened")), false, "terminal operation state never moves backward")

		-- A lowering message can arrive before the card it lowers. Its persisted revision floor keeps
		-- that older card, and later replays of the lowering message, from resurrecting or hiding state.
		local expires = w.b36(w.clock() + 1800)
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~l~lfg123~" .. w.b36(w.clock() + 1)))
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~L~lfg123~" .. w.b36(w.clock()) .. "~" .. expires .. "~raid~healer~ready"), false)
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~L~lfg456~" .. w.b36(w.clock() + 2) .. "~" .. expires .. "~pvp~healer~ready"))
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~l~lfg123~" .. w.b36(w.clock() + 1)), false)
		eq(War.Store(false).lfg[ns.Fold("Ordinary-Realm")].id, "lfg456")
	end)
end)

test("1.2 War: protocol IDs, prose, slots and participant lists are bounded", function()
	WithWar(function(w)
		local rev, start = w.b36(w.clock()), w.b36(w.clock() + 600)
		local prefix = "WZ~1~O~"
		eq(War.Handle("GUILD", "Relay-Realm", prefix .. ("x"):rep(19) .. "~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~tank:1~Raid"), false)
		eq(War.Handle("GUILD", "Relay-Realm", prefix .. "opbad1~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~tank:41~Raid"), false)
		eq(War.Handle("GUILD", "Relay-Realm", prefix .. "opbad2~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~tank:1~" .. ("x"):rep(49)), false)
		eq(War.Handle("GUILD", "Relay-Realm", prefix .. "opbad3~" .. rev .. "~raid~planned~" .. start .. "~Officer-Realm~tank:1,tank:2~Duplicate"), false)
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~L~lfg123~" .. rev .. "~" .. w.b36(w.clock() + 600) .. "~raid~healer~" .. ("x"):rep(65)), false)
		eq(War.CreateCentury("raid | Officer | Empty Century"), false, "a Century must state explicit capability slots")

		local localOp = assert(War.CreateOperation("raid 10 tank=1 | " .. ("Long ~ title | "):rep(8)))
		assert(#localOp.title <= 48 and not localOp.title:find("[~|%^%c]"), "local prose is canonical before transmission")
		eq(War.RecordAfter(localOp.id .. " - action too early ; Officer"), false, "after-action records require a closed operation")
		assert(War.SetOperation(localOp.id, "complete"))
		for i = 1, 25 do
			local name, full = "Unit" .. string.char(64 + i), "Unit" .. string.char(64 + i) .. "-Realm"
			ns.Roster.members[#ns.Roster.members + 1] = { full = full, name = name, rankIndex = 3, rank = "Member", online = true, class = "WA", level = 60 }
			ns.Roster.byName[full] = 3
		end
		local people = {}
		for i = 1, 24 do people[#people + 1] = "Unit" .. string.char(64 + i) .. "-Realm" end
		local aar = "WZ~1~A~aar123~" .. w.b36(w.clock() + 1) .. "~" .. localOp.id .. "~-~0~Clean~" .. table.concat(people, ",")
		assert(War.Handle("GUILD", "Relay-Realm", aar), ("24 exact guild members is the list boundary (%d-byte wire; first resolves as %s)"):format(#aar, tostring(ns.FullName(ns.Normal(people[1])))))
		assert(War.RecordAfter(localOp.id .. " - action boundary clear ; " .. table.concat(people, ",")))
		local queued = w.sent[#w.sent]
		eq(queued.kind, "chunk"); assert(#queued.msg > 255 and queued.options and queued.options.permit)
		eq(queued.options.permit(War, queued.options.key, "GUILD", nil, "one transport piece"), true, "a long record rechecks its whole payload, not one chunk")
		w.rank(3)
		local allowed, why = queued.options.permit(War, queued.options.key, "GUILD", nil, "one transport piece")
		eq(allowed, false); eq(why, "revoked")
		w.rank(0)
		people[#people + 1] = "UnitY-Realm"
		aar = "WZ~1~A~aar124~" .. w.b36(w.clock() + 2) .. "~" .. localOp.id .. "~-~0~Too many~" .. table.concat(people, ",")
		eq(War.Handle("GUILD", "Relay-Realm", aar), false)
	end)
end)

test("1.2 War: readiness counts explicit fresh declarations, never class capability", function()
	WithWar(function(w)
		local c = assert(War.CreateCentury("raid tank=1 healer=1 | Tanky One | First Century"))
		assert(War.AssignPost(c.id .. " tank | Tanky One"))
		assert(War.AssignPost(c.id .. " healer | Mage One"))
		local rev = w.b36(w.clock())
		assert(War.Handle("GUILD", "Tanky One-Realm", "WZ~1~R~" .. rev .. "~tank"))
		assert(War.Handle("GUILD", "Mage One-Realm", "WZ~1~R~" .. rev .. "~ranged"))
		local ready = War.CenturyReadiness(c.id)
		eq(ready.filled.tank, 1); eq(ready.filled.healer, 0)
		eq(ready.gaps.healer, 1); eq(ready.unconfirmed, 1, "being a mage did not establish healer skill")
		w.clock(w.clock() + 1)
		assert(War.Handle("GUILD", "Mage One-Realm", "WZ~1~R~" .. w.b36(w.clock()) .. "~healer"))
		ready = War.CenturyReadiness(c.id)
		eq(ready.filled.healer, 1); eq(ready.gaps.healer, nil); eq(ready.unconfirmed, 0)
	end)
end)

test("1.2 War: confirmations, attendance and training are explicit records with provenance", function()
	WithWar(function(w)
		assert(War.SetRoles("healer"))
		local op = assert(War.CreateOperation("raid 0 healer=1 | Training night"))
		assert(War.Slash("confirm " .. op.id .. " healer"))
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~V~" .. op.id .. "~" .. w.b36(w.clock() + 1) .. "~S~-"))
		local ready = War.OperationReadiness(op.id)
		eq(ready.confirmed, 1); eq(ready.standby, 1); eq(ready.gaps.healer, nil)
		local c = assert(War.CreateCentury("raid healer=1 | Officer | First Century"))
		assert(War.AssignPost(c.id .. " healer | Officer"))
		assert(War.SetOperation(op.id, "active")); assert(War.SetOperation(op.id, "complete"))
		local a = assert(War.RecordAfter(op.id .. " " .. c.id .. " training clean clear ; Officer, Tanky One"))
		eq(a.training, true); eq(#a.participants, 2); eq(a.by, ns.me)
		local general = assert(War.RecordAfter(op.id .. " - action debrief complete ; Officer"))
		eq(general.century, nil, "an operation-wide after-action record needs no invented Century")
		local cr = War.CenturyReadiness(c.id)
		eq(cr.attendance, 2); eq(cr.lastTraining, w.clock())

		ns.UI.Refresh = function() end
		for _, line in ipairs(War.Lines()) do
			if type(line.text) == "string" and line.text:find(op.title, 1, true) and line.onClick then line.onClick() end
			if type(line.text) == "string" and line.text:find(c.name, 1, true) and line.onClick then line.onClick() end
		end
		local reportShown, mixShown, slotsShown, freshnessShown = false, false, false, false
		for _, line in ipairs(War.Lines()) do
			if type(line.text) == "string" and line.text:find("clean clear", 1, true) then reportShown = true end
			if type(line.text) == "string" and line.text:find("Level mix:", 1, true) then mixShown = true end
			if line.text == ns.L.WAR_CAPABILITY_SLOTS and type(line.right) == "string" and line.right:find("Healer 1", 1, true) then slotsShown = true end
			if type(line.right) == "string" and line.right:find("last action", 1, true) then freshnessShown = true end
		end
		assert(reportShown and mixShown and slotsShown and freshnessShown,
			"history, explicit slots, freshness and the roster-derived level/class mix are reachable in the controller")
	end)
end)

test("1.2 War: removed posts persist as bounded tombstones and cannot return from an older copy", function()
	WithWar(function()
		local c = assert(War.CreateCentury("raid tank=1 | Officer | First Century"))
		assert(War.AssignPost(c.id .. " tank | Tanky One"))
		local before = War.Store(false).posts[c.id][ns.Fold("Tanky One-Realm")]
		assert(before and before.role == "tank")
		assert(War.AssignPost(c.id .. " - | Tanky One"))
		local tombstone = War.Store(false).posts[c.id][ns.Fold("Tanky One-Realm")]
		assert(tombstone and tombstone.role == nil and tombstone.rev > before.rev)
		eq(War.CenturyReadiness(c.id).members, 0)
		local found = false
		for _, record in ipairs(War.SnapshotRecords()) do if record:find("^P~" .. c.id .. "~") and record:sub(-2) == "~-" then found = true end end
		assert(found, "the removal travels in reload recovery")
	end)
end)

test("1.2 War: persistence caps remove dependent RSVP, posts and after-action records", function()
	WithWar(function(w)
		local s, now = War.Store(true), w.clock()
		for i = 1, War.OP_MAX + 1 do
			local id = ("op%03d"):format(i)
			s.operations[id] = { id = id, rev = now + i, kind = "raid", state = "planned", start = now + 600,
				leader = "Officer-Realm", slots = { tank = 1 }, title = "Operation " .. i }
			s.rsvp[id] = { ["officer-realm"] = { player = "Officer-Realm", rev = now + i, status = "C", role = "tank" } }
		end
		s.after.aar001 = { id = "aar001", rev = now, operation = "op001", training = false, result = "Old", participants = { "Officer-Realm" } }
		for i = 1, War.CENTURY_MAX + 1 do
			local id = ("cent%03d"):format(i)
			s.centuries[id] = { id = id, rev = now + i, centurion = "Officer-Realm", specialty = "raid", slots = { tank = 1 }, name = "Century " .. i }
			s.posts[id] = { ["officer-realm"] = { player = "Officer-Realm", role = "tank", rev = now + i } }
		end
		assert(War.Prune(now))
		eq(s.operations.op001, nil); eq(s.rsvp.op001, nil); eq(s.after.aar001, nil)
		eq(s.centuries.cent001, nil); eq(s.posts.cent001, nil)
	end)
end)

test("1.2 War: paged reload recovery relays officer records but never impersonates member declarations", function()
	WithWar(function(w)
		assert(War.SetRoles("caller"))
		local op = assert(War.CreateOperation("pvp 15 caller=1 scout=1 | Hillsbrad patrol"))
		local c = assert(War.CreateCentury("scouting caller=1 scout=1 | Relay | Eyes of Olympus"))
		assert(War.AssignPost(c.id .. " caller | Officer"))
		assert(War.SetOperation(op.id, "active")); assert(War.SetOperation(op.id, "complete"))
		assert(War.RecordAfter(op.id .. " " .. c.id .. " action area secured ; Officer, Tanky One"))
		local records = War.SnapshotRecords()
		assert(#records >= 4)
		eq(records[1]:sub(1, 2), "O~", "operations precede their dependent after-action records")

		ns.Roster.byName["Tanky One-Realm"] = nil
		for i = #ns.Roster.members, 1, -1 do if ns.Roster.members[i].full == "Tanky One-Realm" then table.remove(ns.Roster.members, i) end end
		War.Reset()
		w.sent = w.sent
		assert(War.Ask(true))
		local ask = w.sent[#w.sent].msg
		local nonce = assert(ask:match("^WZ~1~Q~([0-9a-z]+)$"))
		local snapshot = "WZ~1~S~" .. nonce .. "~0~0~" .. #records .. "^" .. table.concat(records, "^")
		assert(War.Handle("GUILD", "Relay-Realm", snapshot))
		local s = War.Store(false)
		assert(s.operations[op.id] and s.centuries[c.id] and next(s.after))
		local _, recovered = next(s.after)
		eq(#recovered.participants, 2, "historical attendance survives after a participant leaves the roster")
		eq(s.roles[ns.Fold("Officer-Realm")], nil, "an officer snapshot never speaks as another member")
		eq(s.operations[op.id].via, "Relay-Realm")
	end)
end)

test("1.2 War: recovery pages stay bounded and advance with a deterministic cursor", function()
	WithWar(function(w)
		local start = w.b36(w.clock() + 600)
		for i = 1, War.OP_MAX do
			local id = ("op%03d"):format(i)
			local title = ("Operation %02d "):format(i) .. ("x"):rep(35)
			local msg = ("WZ~1~O~%s~%s~raid~planned~%s~Officer-Realm~tank:2,healer:4,melee:5,ranged:5,support:2,caller:1,scout:1~%s")
				:format(id, w.b36(w.clock() + i), start, title)
			assert(War.Handle("GUILD", "Relay-Realm", msg))
		end
		local first, cursor = War.SnapshotPage(0)
		assert(#first > 0 and cursor > 0, "the bounded page advertises the next cursor")
		local total = #War.SnapshotRecords()
		local payload = "WZ~1~S~nonce~0~" .. cursor .. "~" .. total .. "^" .. table.concat(first, "^")
		assert(#payload <= War.SNAPSHOT_BYTES)
		local second, nextCursor = War.SnapshotPage(cursor)
		assert(#second > 0); assert(nextCursor == 0 or nextCursor > cursor)
		local seen = {}
		for _, record in ipairs(first) do seen[record] = true end
		for _, record in ipairs(second) do assert(not seen[record], "a cursor never repeats an earlier record") end

		War.Reset()
		assert(War.Ask(true))
		local nonce = assert(w.sent[#w.sent].msg:match("^WZ~1~Q~([0-9a-z]+)$"))
		local body = table.concat(first, "^")
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~1~S~" .. nonce .. "~0~" .. (cursor + 1) .. "~" .. total .. "^" .. body), false, "a skipped cursor is rejected before records are applied")
		eq(War.Handle("GUILD", "Relay-Realm", "WZ~1~S~" .. nonce .. "~0~0~" .. total .. "^" .. body), false, "a responder cannot terminate a snapshot before its advertised total")
		local firstMessage = "WZ~1~S~" .. nonce .. "~0~" .. cursor .. "~" .. total .. "^" .. body
		assert(War.Handle("GUILD", "Relay-Realm", firstMessage))
		eq(War.Handle("GUILD", "Relay-Realm", firstMessage), false, "a duplicate page cannot advance the cursor twice")
		local secondMessage = "WZ~1~S~" .. nonce .. "~" .. cursor .. "~" .. nextCursor .. "~" .. total .. "^" .. table.concat(second, "^")
		eq(War.Handle("GUILD", "OtherOfficer-Realm", secondMessage), false, "one recovery cannot splice pages from different officers")
		assert(War.Handle("GUILD", "Relay-Realm", secondMessage))
		eq(War.Handle("GUILD", "Relay-Realm", secondMessage), false, "a completed snapshot cannot be replayed")
		local count = 0
		for _ in pairs(War.Store(false).operations) do count = count + 1 end
		eq(count, War.OP_MAX)
	end)
end)

test("1.2 War: an officer freezes one recovery snapshot across its pages", function()
	WithWar(function(w)
		local start = w.b36(w.clock() + 600)
		for i = 1, War.OP_MAX do
			local id = ("op%03d"):format(i)
			local msg = ("WZ~1~O~%s~%s~raid~planned~%s~Officer-Realm~tank:2,healer:4,melee:5,ranged:5,support:2,caller:1,scout:1~Operation %02d %s")
				:format(id, w.b36(w.clock() + i), start, i, ("x"):rep(35))
			assert(War.Handle("GUILD", "Relay-Realm", msg))
		end
		local frozen = War.SnapshotRecords()
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~Q~freeze"))
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~Q~freeze"), false, "an initial query nonce cannot be replayed")
		w.runNext()
		local firstMessage = w.sent[#w.sent].msg
		local page, cursor, total, firstBody = firstMessage:match("^WZ~1~S~freeze~(%d+)~(%d+)~(%d+)%^(.*)$")
		eq(page, "0"); cursor = assert(tonumber(cursor)); assert(cursor > 0)
		eq(tonumber(total), #frozen)

		local store = War.Store(false)
		store.operations.op001 = nil
		store.operations.op040.title = "Changed while the first page was in flight"
		eq(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~Q~freeze~" .. (cursor + 1)), false, "a requester cannot skip a frozen page")
		assert(War.Handle("GUILD", "Ordinary-Realm", "WZ~1~Q~freeze~" .. cursor))
		w.runNext()
		local secondMessage = w.sent[#w.sent].msg
		local secondPage, nextCursor, secondTotal, secondBody = secondMessage:match("^WZ~1~S~freeze~(%d+)~(%d+)~(%d+)%^(.*)$")
		eq(tonumber(secondPage), cursor); eq(tonumber(nextCursor), 0)
		eq(secondTotal, total)
		eq(firstBody .. "^" .. secondBody, table.concat(frozen, "^"), "a mutation between requests cannot skip, duplicate or rewrite a frozen page")
	end)
end)

test("1.2 War: the Realm controller exposes actionable rows, Loot Notes and unavailable API fields", function()
	WithWar(function()
		ns.Views.SetRealmMode("guilds", true)
		local selected, refreshes = nil, 0
		ns.UI.Refresh = function() refreshes = refreshes + 1 end
		ns.UI.SelectTab = function(tab) selected = tab end
		local link = War.Link()
		assert(type(link.onClick) == "function")
		link.onClick()
		eq(ns.Views.PageShown(), "war"); eq(selected, "realm"); assert(refreshes > 0)
		local lines = ns.Views.Build("realm")
		local loot, unavailable, title, actions = false, false, false, 0
		for _, line in ipairs(lines) do
			if line.text == ns.L.WAR_TITLE then title = true end
			if type(line.onClick) == "function" then actions = actions + 1 end
			if type(line.text) == "string" and line.text:find("Loot Notes", 1, true) then loot = line end
			if type(line.text) == "string" and line.text:find("Gear, spec", 1, true) then unavailable = true end
		end
		assert(title and actions >= 3, "the actual Realm builder exposes the War controller and its actions")
		assert(loot and type(loot.onClick) == "function", "the existing Loot Notes page is linked, not copied")
		loot.onClick(); eq(ns.Views.PageShown(), "loot")
		assert(unavailable, "unverified cross-client fields are explicitly unavailable")
		ns.Views.ShowPage(nil)
	end)
end)
