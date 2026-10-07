local H = ...
local test, eq, ns = H.test, H.eq, H.ns

print("Tabards v2: consent, direct evidence, leases and preview")

local function With(stubs, fn)
	local keys = {}
	for key in pairs(stubs) do keys[#keys + 1] = key end
	table.sort(keys)
	local function At(i)
		if not keys[i] then return fn() end
		return H.WithStub(keys[i], stubs[keys[i]], function() At(i + 1) end)
	end
	return At(1)
end

local function Globals(values, fn)
	local old, keys = {}, {}
	for key, value in pairs(values) do keys[#keys + 1], old[key], _G[key] = key, _G[key], value end
	local ok, err = pcall(fn)
	for _, key in ipairs(keys) do _G[key] = old[key] end
	if not ok then error(err, 0) end
end

local function FakeComm()
	local c = { sent = {}, cancelled = {} }
	function c.Send(dist, msg, key, urgent, logged, done, guard)
		c.sent[#c.sent + 1] = { dist = dist, msg = msg, key = key, target = nil, guard = guard }
	end
	function c.Whisper(target, msg, key, urgent, logged, done, guard)
		c.sent[#c.sent + 1] = { dist = "WHISPER", msg = msg, key = key, target = target, guard = guard }
	end
	function c.CancelQueued(owner, key, why)
		c.cancelled[#c.cancelled + 1] = { owner = owner, key = key, why = why }
		return 1
	end
	return c
end

local function KingStub(isKing)
	return {
		IsKing = function() return isKing end,
		Preview = function() return false end,
		FromKing = function() return true end,
	}
end

test("1.2 tabards v2: both contracts start off, No persists for this version, a changed contract asks again, and missing SV fails closed", function()
	local T, db, comm = ns.TabardsV2, {}, FakeComm()
	T.Reset()
	With({ db = db, rdb = {}, Comm = comm, King = KingStub(false), me = "Observer-Realm" }, function()
		eq(T.Consent("self"), nil); eq(T.Consent("nearby"), nil)
		eq(T.SetConsent("self", false), true); eq(T.SetConsent("nearby", false), true)
		eq(T.Consent("self"), false); eq(T.Consent("nearby"), false)
		eq(db.tabardsV2.consent.self.v, T.CONTRACT)
		local version = T.CONTRACT
		T.CONTRACT = version + 1
		eq(T.Consent("self"), nil, "a new contract never inherits Yes or No")
		T.CONTRACT = version
		eq(T.Consent("self"), false, "the current No remains final")
		assert(#comm.cancelled >= 2, "each No cancels its own queued set")
	end)
	H.WithStub("db", nil, function()
		eq(T.SetConsent("self", true), false); eq(T.Consent("self"), nil)
	end)
end)

test("1.2 tabards v2: only an exact fresh King lease enables a guarded self whisper, revocation and recipient change stop delivery", function()
	local T, db, comm, now, member, kingName, authorized = ns.TabardsV2, {}, FakeComm(), 10000, true, true, true
	T.Reset()
	local function IsKingName(name) return kingName and ns.ShortName(name) == "Theking" end
	local king = KingStub(false)
	king.FromKing = function() return authorized end
	With({
		db = db, rdb = {}, Comm = comm, King = king, me = "Observer-Realm", realm = "Realm",
		Now = function() return now end, IsMember = function() return member end, IsKingCharacter = IsKingName,
	}, function()
		Globals({
			GetGuildInfo = function() return "Olympus" end,
			UnitLevel = function() return 60 end,
			GetInventoryItemID = function(_, slot) if slot == 19 then return 5976 end end,
			INVSLOT_TABARD = 19,
		}, function()
			T.SetConsent("self", true)
			eq(#comm.sent, 0, "no authenticated collector, no report")
			eq(T.HandleLease("GUILD", "Theking-Realm", "U2~2~abc~600~Olympus"), false)
			eq(T.HandleLease("CHANNEL", "Spoof-Realm", "U2~2~abc~600~Olympus"), false)
			eq(T.HandleLease("CHANNEL", "Theking-Realm", "U2~1~abc~600~Olympus"), false, "mixed old version")
			eq(T.HandleLease("CHANNEL", "Theking-Realm", "U2~2~abc~600~Olympus"), true)
			eq(#comm.sent, 1); local sent = comm.sent[1]
			eq(sent.dist, "WHISPER"); eq(sent.target, "Theking-Realm")
			assert(sent.msg:find("^U3~2~abc~%d+~60~Olympus~G$"), sent.msg)
			assert(not sent.msg:find("Observer", 1, true), "self identity is server-stamped, not copied into the payload")
			local ok, why = sent.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
			eq(ok, true); eq(why, nil)
			T.SetConsent("self", false)
			ok, why = sent.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
			eq(ok, false); eq(why, "revoked")
				assert(comm.cancelled[#comm.cancelled].key == "self")
				T.SetConsent("self", true)
				local newest = comm.sent[#comm.sent]
				member = false
				ok, why = newest.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
				eq(ok, false); eq(why, "revoked", "leaving an Olympus guild closes the delivery gate")
				member = true; kingName = false
				ok, why = newest.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
				eq(ok, false); eq(why, "recipient-changed", "the recipient losing the pinned King identity closes it")
				kingName = true; authorized = false
				ok, why = newest.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
				eq(ok, false); eq(why, "recipient-changed", "a role or guild change closes the delivery gate")
				authorized = true
				now = now + 601
			ok, why = sent.guard.permit(nil, nil, "WHISPER", "Theking-Realm")
			eq(ok, false); eq(why, "recipient-changed", "stale leases fail at delivery")
		end)
	end)
end)

test("1.2 tabards v2: nearby uses a completed direct observation only, never relay/manual evidence, never inspects, and is rate bounded", function()
	local T, db, comm, now, inspected = ns.TabardsV2, {}, FakeComm(), 20000, 0
	T.Reset()
	With({
		db = db, rdb = {}, Comm = comm, King = KingStub(false), me = "Observer-Realm", realm = "Realm",
		Now = function() return now end, IsMember = function() return true end,
		IsKingCharacter = function(name) return ns.ShortName(name) == "Theking" end,
	}, function()
		Globals({ GetGuildInfo = function() return "Olympus" end, NotifyInspect = function() inspected = inspected + 1 end }, function()
			T.SetConsent("nearby", true)
			assert(T.HandleLease("CHANNEL", "Theking-Realm", "U2~2~lease2~600~Olympus"))
			local before = #comm.sent
			assert(T.Observe({ name = "Subject-Realm", guild = "Olympus II", level = 60, status = "NONE" }, true))
			eq(inspected, 0, "the v2 path never calls NotifyInspect")
			eq(#comm.sent, before + 1)
			local m = comm.sent[#comm.sent]
			eq(m.dist, "WHISPER"); eq(m.target, "Theking-Realm")
				assert(m.msg:find("~Subject~", 1, true) and m.msg:find("Olympus II", 1, true), m.msg)
			eq(T.Observe({ name = "Subject-Realm", guild = "Olympus II", level = 60, status = "NONE" }, true), false, "repeat bounded")
			eq(T.Observe({ name = "Manual-Realm", guild = "Olympus II", level = 60, status = "NONE" }), false,
				"a stored or manual row lacks the completed-inspection marker")
			eq(T.Observe({ name = "Relayed-Realm", guild = "Olympus II", level = 60, status = "NONE", shared = true }, true), false)
			eq(T.Observe({ name = "Reported-Realm", guild = "Olympus II", level = 60, status = "NONE", reported = true }, true), false)
			ns.Inspect.AddReported("ActualReport-Realm", "Olympus II", "NONE")
			local reported = ns.Inspect.Players()[ns.Inspect.Key("ActualReport-Realm")]
			assert(reported and reported.reported == true, "AddReported keeps its second-hand provenance")
			eq(T.Observe(reported, true), false, "an actual reported row is never retransmitted as direct")
			now = now + T.NEARBY_MIN
			assert(T.Observe({ name = "Subject-Realm", guild = "Olympus II", level = 60, status = "GUILD" }, true), "a changed direct result can correct it")
		end)
	end)
end)

test("1.2 tabards v2: malformed, spoofed and replayed whispers fail; two independent observers are required; conflict blocks; direct King overrides", function()
	local T, db, rdb, comm, now = ns.TabardsV2, {}, {}, FakeComm(), 30000
	T.Reset()
	local roster = { RankOf = function(name) return name and 1 or nil end }
	With({
		db = db, rdb = rdb, Comm = comm, King = KingStub(true), Roster = roster, me = "Theking-Realm", realm = "Realm",
		Now = function() return now end, IsMember = function() return true end,
		IsKingCharacter = function(name) return ns.ShortName(name) == "Theking" end,
	}, function()
		Globals({ GetGuildInfo = function() return "Olympus" end }, function()
				assert(T.Announce(true)); local lease = comm.sent[#comm.sent].msg:match("^U2~2~([%w]+)~")
				assert(lease)
				eq(T.HandleNearby("WHISPER", "A-Realm", "U4~2~" .. lease .. "~x~Bad-Realm~Olympus II~60~N~Olympus"), false, "malformed sequence")
				eq(T.HandleNearby("WHISPER", "A-Realm", "U4~1~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"), false, "mixed old version")
				eq(T.HandleNearby("WHISPER", "A-Realm", "U4~2~" .. lease .. "~1~TooYoung-Realm~Olympus II~12~N~Olympus"), false, "level exemption cannot be accused")
				eq(T.HandleNearby("GUILD", "A-Realm", "U4~2~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"), false)
			eq(T.HandleNearby("WHISPER", "A-Realm", "U4~9~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"), false)
			assert(T.HandleNearby("WHISPER", "A-Realm", "U4~2~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"))
			eq(T.HandleNearby("WHISPER", "A-Realm", "U4~2~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"), false, "replay")
			local status, actionable = T.Conclusion("Bad-Realm")
			eq(status, "U"); eq(actionable, false, "one observer cannot accuse")
			assert(T.HandleNearby("WHISPER", "B-Realm", "U4~2~" .. lease .. "~1~Bad-Realm~Olympus II~60~N~Olympus"))
			status, actionable = T.Conclusion("Bad-Realm")
			eq(status, "N"); eq(actionable, true, "two independent fresh observers")
			assert(T.HandleNearby("WHISPER", "C-Realm", "U4~2~" .. lease .. "~1~Bad-Realm~Olympus II~60~G~Olympus"))
			local conflict
			status, actionable, _, conflict = T.Conclusion("Bad-Realm")
			eq(status, "U"); eq(actionable, false); eq(conflict, true)
			assert(T.Observe({ name = "Bad-Realm", guild = "Olympus II", level = 60, status = "OTHER" }, true))
				status, actionable, _, conflict = T.Conclusion("Bad-Realm")
				eq(status, "O"); eq(actionable, true, "the King's own direct observation is decisive"); eq(conflict, true)
				eq(#T.PublicationList(), 1)
				assert(T.HandleNearby("WHISPER", "D-Realm", "U4~2~" .. lease .. "~1~GuildConflict-Realm~Olympus II~60~N~Olympus"))
				assert(T.HandleNearby("WHISPER", "E-Realm", "U4~2~" .. lease .. "~1~GuildConflict-Realm~Olympus III~60~N~Olympus"))
				status, actionable, _, conflict = T.Conclusion("GuildConflict-Realm")
				eq(status, "U"); eq(actionable, false); eq(conflict, true, "conflicting observed guilds block publication")
				now = now + T.RAW_KEEP + 1; T.Prune()
				eq(T.Conclusion("Bad-Realm"), nil, "raw evidence expires at 24 hours")
				assert(T.LEASE_EVERY <= 15 * 60 and T.SELF_EVERY <= 15 * 60, "lease and self heartbeats are bounded")
		end)
	end)
end)

test("1.2 tabards v2: a claimed guild never authenticates two forged cross-guild observers, nor do census reports of their rank", function()
	local T, db, rdb, comm, now = ns.TabardsV2, {}, {}, FakeComm(), 35000
	local verified = {}
	T.Reset()
	With({
		db = db, rdb = rdb, Comm = comm, King = KingStub(true), me = "Theking-Realm", realm = "Realm",
		Now = function() return now end, IsMember = function() return true end,
		Roster = { RankOf = function() return nil end },
		Moderation = { GuildOf = function() return "Olympus II" end },
		-- (1.2.0: the signed list counts; census reports never do, however many vouch.)
		Data = { AuthorizedRank = function(sender, guild)
			if guild ~= "Olympus II" then return nil end
			local short = ns.ShortName(sender)
			if verified[short] then return verified[short], "signed" end
			if short:find("^Attacker") then return 1, "census" end
		end },
	}, function()
		Globals({ GetGuildInfo = function() return "Olympus" end }, function()
			assert(T.Announce(true)); local lease = comm.sent[#comm.sent].msg:match("^U2~2~([%w]+)~")
			assert(lease)
			local function WithLimit(key, value, fn)
				local old = T[key]
				T[key] = value
				local ok, result = pcall(fn)
				T[key] = old
				if not ok then error(result, 0) end
				return result
			end
			local function Nearby(sender, seq, status, subjectGuild, subject)
				return T.HandleNearby("WHISPER", sender, "U4~2~" .. lease .. "~" .. seq ..
					"~" .. (subject or "Victim-Realm") .. "~" .. (subjectGuild or "Olympus III") .. "~60~" ..
					(status or "N") .. "~Olympus II")
			end
			assert(Nearby("AttackerA-Realm", 1, "N")); assert(Nearby("AttackerB-Realm", 1, "O"))
			assert(T.HandleSelf("WHISPER", "AttackerA-Realm", "U3~2~" .. lease .. "~2~60~Olympus II~N"))
			local status, actionable, _, conflict, evidence = T.Conclusion("Victim-Realm")
			eq(status, "U"); eq(actionable, false); eq(conflict, false)
			eq(evidence[1].trusted, false); eq(evidence[2].trusted, false,
				"a prior claimed guild is retained only as explicitly untrusted evidence")
			eq(#T.PublicationList(), 0, "two forged observers never create a public negative")
			verified.Vetted = 1
			assert(Nearby("Vetted-Realm", 1), "an independently vouched cross-guild officer may report")
			status, actionable = T.Conclusion("Victim-Realm")
			eq(status, "U"); eq(actionable, false, "one verified observer is still not actionable")
			verified.Vetted2 = 1
			assert(Nearby("Vetted2-Realm", 1))
			status, actionable = T.Conclusion("Victim-Realm")
			eq(status, "N"); eq(actionable, true)
			eq(T.PublicationList()[1].guild, "Olympus III")
			assert(WithLimit("MAX_OBSERVERS", 2, function()
				return Nearby("AttackerC-Realm", 1, "O", "Olympus Spoof")
			end))
			status, actionable, _, conflict = T.Conclusion("Victim-Realm")
			eq(status, "N"); eq(actionable, true); eq(conflict, false,
				"untrusted evidence cannot evict verified observers or create a conflict")
			eq(T.PublicationList()[1].guild, "Olympus III",
				"untrusted evidence cannot replace the published subject guild")
			WithLimit("MAX_SUBJECTS", 1, function()
				assert(Nearby("AttackerD-Realm", 1, "O", "Olympus Spoof", "Flood-Realm"))
				assert(rdb.tabardsV2.raw[ns.Inspect.Key("Victim-Realm")], "a trusted subject survives the subject cap")
				eq(rdb.tabardsV2.raw[ns.Inspect.Key("Flood-Realm")], nil,
					"an untrusted subject cannot evict the trusted publication at the cap")
			end)
		end)
	end)
end)

test("1.2 tabards v2: a fresh empty publication reveals the surface, a stale one hides it, and View-as never grants authority", function()
	local T, V, db, rdb, now = ns.TabardsV2, ns.ViewAs, {}, {}, 40000
	T.Reset(); V.Reset()
	local workshop = { IsAuthor = function() return false end, Preview = function() return false end }
	With({ db = db, rdb = rdb, King = KingStub(false), Workshop = workshop, Roster = { IsOfficer = function() return false end }, Now = function() return now end }, function()
		ns.Inspect.ResetShame()
		eq(T.SurfaceVisible(), false)
		ns.Inspect.ShowShame({ by = "King", list = {}, t = now })
		eq(T.SurfaceVisible(), true, "empty is a real publication")
		now = now + ns.Inspect.SHARED_FRESH + 1
		eq(T.SurfaceVisible(), false, "publication lease expired")
	end)
	local author = { IsAuthor = function() return true end, Preview = function() return false end }
	local actualKing = KingStub(false)
	With({ db = db, rdb = rdb, King = actualKing, Workshop = author }, function()
		H.WithUI(function()
			local shown, menu = V.ShowMenu()
			assert(shown and menu and menu.buttons[2]); menu.buttons[2]:Click()
			eq(V.Role(), "king", "the King button keeps its own Lua 5.1 closure")
			eq(V.Allows("throne"), true); eq(T.SurfaceVisible(), true)
			eq(actualKing.IsKing(), false, "presentation role never changes real authority")
			eq(T.Announce(true), false, "presentation role cannot announce as King")
			-- (1.2: High Council third, the Stewards and Hands merged into it; the Treasurer fourth.)
			eq(menu.buttons[3].key, "councillor"); eq(menu.buttons[3]:GetText(), ns.L.VIEW_AS_COUNCILLOR)
			shown, menu = V.ShowMenu(); assert(shown and menu and menu.buttons[4]); menu.buttons[4]:Click()
			eq(V.Role(), "treasurer", "the Treasurer button does not select the last option")
			eq(V.Allows("treasury"), true); eq(V.Allows("throne"), false)
			assert(V.Set("member")); eq(V.Allows("heraldry"), true); eq(T.SurfaceVisible(), false, "simulated member cannot bypass a stale publication")
			assert(V.Set("officer")); eq(T.SurfaceVisible(), true, "the officer's direct-inspection page remains available")
			assert(V.Set("my")); eq(T.SurfaceVisible(), true, "the author's own local preview remains available")
		end)
	end)
	V.Reset()
end)

test("1.2.0 tabards v2: two ordinary members of the King's guild cannot put anyone on the list; two of its officers can", function()
	local T, db, rdb, comm, now = ns.TabardsV2, {}, {}, FakeComm(), 40000
	T.Reset()
	local roster = { RankOf = function(name) return name and (ns.ShortName(name):find("^Member") and 5 or 1) or nil end }
	With({
		db = db, rdb = rdb, Comm = comm, King = KingStub(true), Roster = roster, me = "Theking-Realm", realm = "Realm",
		Now = function() return now end, IsMember = function() return true end,
		IsKingCharacter = function(name) return ns.ShortName(name) == "Theking" end,
	}, function()
		Globals({ GetGuildInfo = function() return "Olympus" end }, function()
			assert(T.Announce(true)); local lease = comm.sent[#comm.sent].msg:match("^U2~2~([%w]+)~")
			local function Nearby(sender) return T.HandleNearby("WHISPER", sender, "U4~2~" .. lease .. "~1~Victim-Realm~Olympus II~60~N~Olympus") end
			assert(Nearby("MemberA-Realm")); assert(Nearby("MemberB-Realm"))
			local status, actionable = T.Conclusion("Victim-Realm")
			eq(status, "U"); eq(actionable, false, "members are not officers")
			assert(Nearby("Captain-Realm")); assert(Nearby("Officer-Realm"))
			status, actionable = T.Conclusion("Victim-Realm")
			eq(status, "N"); eq(actionable, true)
		end)
	end)
end)
