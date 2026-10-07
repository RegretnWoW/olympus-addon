-- GitHub #23: signed cross-guild leadership is a dormant, explicit migration. Old HT1 lists keep
-- legacy behaviour; an author-signed enforce marker creates a sticky fail-closed boundary.
local ns, test, eq = ...
	local A, D, T0 = ns.Authority, ns.Data, 1800000000
	local function Hex(s)
		return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
	end
	local function Entry(body, epoch, issued, expires, faction)
		return ("^leaders^%s^enforce^%d^%d^%d^%s"):format(faction or "Alliance", epoch or 1,
			issued or (T0 - 10), expires or (T0 + 1000), body or "-")
	end
	local function WithState(fn)
		local saved = { titles = ns.rdb.councilTitles, bundles = ns.rdb.authorityBundles, enforced = ns.db.authorityEnforced,
			faction = ns.faction, realm = ns.realm, group = ns.group, me = ns.me, now = ns.Now,
			byName = ns.Roster.byName, moderation = ns.Moderation, guilds = ns.rdb.guilds,
			loginAt = ns.Comm.loginAt }
		local ok, err = pcall(function()
			ns.faction, ns.realm, ns.group, ns.me = "Alliance", "Realm", "Realm+Other", "Tester-Realm"
			ns.Now = function() return T0 end
			ns.Roster.byName = {}
			ns.rdb.guilds, ns.rdb.councilTitles, ns.rdb.authorityBundles, ns.db.authorityEnforced = {}, nil, {}, {}
			ns.Moderation = ns.Moderation or {}
			A.Reset()
			fn()
		end)
		ns.rdb.councilTitles, ns.rdb.authorityBundles, ns.db.authorityEnforced = saved.titles, saved.bundles, saved.enforced
		ns.faction, ns.realm, ns.group, ns.me = saved.faction, saved.realm, saved.group, saved.me
		ns.Now, ns.Roster.byName, ns.Moderation = saved.now, saved.byName, saved.moderation
		ns.rdb.guilds, ns.Comm.loginAt = saved.guilds, saved.loginAt
		A.Reset()
		if not ok then error(err, 0) end
	end
	local function WithFakeSign(fn)
		local plausible, verify = ns.Sign.Plausible, ns.Sign.Verify
		local accepted = {}
		ns.Sign.Plausible = function(sig) return type(sig) == "string" and #sig == 512 and sig:find("^%x+$") ~= nil end
		ns.Sign.Verify = function(text, sig) return accepted[text] == sig end
		local function Parts(bodies, opts)
			opts = opts or {}
			local full = #bodies == 1 and bodies[1] == "-" and "-" or table.concat(bodies, "!")
			local root = opts.root or Hex(ns.Sign.SHA256(full))
			local sig = string.rep(opts.sig or "a", 512)
			local out = {}
			for i, body in ipairs(bodies) do
				local text = ("HA1~%d~%s~%s~enforce~%d~%d~%d~%s~%d~%d~%s"):format(
					opts.at or (T0 + 1), opts.realm or "Realm+Other", opts.faction or "Alliance",
					opts.epoch or 1, opts.issued or (T0 - 10), opts.expires or (T0 + 1000),
					root, i, #bodies, body)
				if not opts.unsigned then accepted[text] = sig end
				out[i] = text .. "~" .. sig
			end
			return out
		end
		local ok, err = pcall(fn, Parts, accepted)
		ns.Sign.Plausible, ns.Sign.Verify = plausible, verify
		if not ok then error(err, 0) end
	end
	local function Install(list, at)
		at = at or T0
		ns.rdb.councilTitles = { at = at, realm = "Realm+Other", depts = {},
			blob = ("HT1~%d~Realm+Other~0~%s~a"):format(at, list or "^^") }
		A.Reset()
	end
	local function Census(guild, who, rank)
		local ranks = { [who] = rank }
		ns.rdb.guilds[guild] = { guild = guild, realm = "Realm", t = T0,
			leader = rank == 0 and ns.ShortName(who) or "Other", officers = rank == 1 and { { name = ns.ShortName(who) } } or {},
			vouch = { ["Vote1-Realm"] = { t = T0, sig = "same", ranks = ranks },
				["Vote2-Realm"] = { t = T0, sig = "same", ranks = ranks } } }
		ns.Comm.loginAt = T0 - D.CROWN_AFTER - 1
	end

	test("authority: old HT1 absence preserves the documented census behaviour", function()
		WithState(function()
			Census("Olympus Zeus", "Legacy-Realm", 0)
			Install("Department^INV_Sword_04^Someone=Title;^steward^Alliance^Steward-Realm;^guilds^Alliance^Test Guild;^arbiter^Alliance^Judge-Realm+a")
			eq(A.Enforced(), false)
			eq(D.AuthorizedRank("Legacy-Realm", "Olympus Zeus"), 0)
			eq(select(2, D.AuthorizedRank("Legacy-Realm", "Olympus Zeus")), "census")
			-- Every older extension parser continues to see its own entry with leaders beside it.
			local mixed = "^steward^Alliance^Steward-Realm;^guilds^Alliance^Test Guild;^arbiter^Alliance^Judge-Realm+a;" ..
				Entry("Olympus Zeus=Signed-Realm")
			eq(ns.ReadStewards(mixed).Alliance[1], "Steward-Realm")
			eq(ns.ReadApprovedGuilds(mixed).Alliance[1], "Test Guild")
			eq(ns.ReadArbiters(mixed).Alliance[1].name, "Judge-Realm")
			-- The dormant reader itself does not create a SavedVariables boundary for an old list.
			ns.db.authorityEnforced = nil
			A.Reset()
			eq(A.Enforced(), false)
			eq(ns.db.authorityEnforced, nil)
		end)
	end)

	test("authority: exact signed leadership grants ranks; faction, realm and expiry fail closed", function()
		WithState(function()
			Install(Entry("Olympus Zeus=Zed-Realm,Cap-Other!Olympus Ares=Ares-Realm", 7))
			eq(A.Enforced(), true)
			eq(A.Rank("Zed-Realm", "OLYMPUS ZEUS"), 0)
			eq(A.Rank("Cap-Other", "Olympus Zeus"), 1)
			eq(A.Rank("Cap-Realm", "Olympus Zeus"), nil, "a namesake on another realm")
			eq(A.Rank("Zed-Other", "Olympus Zeus"), nil)
			eq(A.Rank("Zed-Realm", "Olympus Ares"), nil, "a signed identity belongs to one guild")
			ns.faction = "Horde"
			eq(A.Enforced(), false, "the other faction was not activated")
			eq(A.Rank("Zed-Realm", "Olympus Zeus"), nil)
			ns.faction = "Alliance"
			ns.Now = function() return T0 + 1001 end
			eq(A.Enforced(), true); eq(A.Rank("Zed-Realm", "Olympus Zeus"), nil, "expired fails closed")
			ns.Now = function() return T0 - A.CLOCK_SKEW - 11 end
			eq(A.Rank("Zed-Realm", "Olympus Zeus"), nil, "not valid yet")
		end)
	end)

	test("authority: malformed, duplicate and oversized enforce manifests activate but grant nobody", function()
		local bad = {
			Entry("Olympus Zeus=Zed-Realm,Zed-Realm"),
			Entry("Olympus Zeus=Zed-Realm!olympus zeus=Cap-Realm"),
			Entry("Olympus Zeus=Zed-Realm!Olympus Ares=Zed-Realm"),
			Entry("Olympus Zeus=Zed-Elsewhere"),
			Entry("Olympus Zeus=Zed-Realm", 1, T0, T0 + A.MAX_LIFETIME + 1),
			Entry("Olympus Zeus=Zed-Realm") .. ";" .. Entry("Olympus Ares=Ares-Realm"),
			"^leaders^Alliance^enforce^x^" .. T0 .. "^" .. (T0 + 10) .. "^Olympus Zeus=Zed-Realm",
		}
		for i, list in ipairs(bad) do
			WithState(function()
				Census("Olympus Zeus", "Zed-Realm", 0)
				Install(list, T0 + i)
				eq(A.Enforced(), true, "explicit marker case " .. i)
				eq(D.AuthorizedRank("Zed-Realm", "Olympus Zeus"), nil, "malformed case " .. i)
			end)
		end
		WithState(function()
			local items = {}
			local function Letters(i)
				local s = ""
				repeat s, i = string.char(65 + ((i - 1) % 26)) .. s, math.floor((i - 1) / 26) until i == 0
				return s
			end
			for i = 1, A.MAX_GUILDS + 1 do
				local suffix = Letters(i)
				items[i] = "Olympus " .. suffix .. "=P" .. suffix .. "-Realm"
			end
			local parsed, why = A.Read(Entry(table.concat(items, "!")), "Realm")
			eq(parsed, nil); eq(why, "guild-limit")
		end)
		WithState(function()
			local names = {}
			for i = 1, A.MAX_PEOPLE + 1 do names[i] = "P" .. string.char(64 + i) .. "-Realm" end
			local parsed, why = A.Read(Entry("Olympus Zeus=" .. table.concat(names, ",")), "Realm")
			eq(parsed, nil); eq(why, "player-limit")
		end)
		WithState(function()
			local parsed, why, present = A.Read(Entry("-") .. string.rep("x", A.MAX_TEXT + 1), "Realm")
			eq(parsed, nil); eq(why, "size"); eq(present.Alliance, 1,
				"an explicit marker remains a sticky boundary even when its signed payload is oversized")
		end)
	end)

	test("authority: activation is sticky across absence, tombstone, expiry, epoch rollback and replay", function()
		WithState(function()
			Census("Olympus Zeus", "Forger-Realm", 0)
			eq(D.AuthorizedRank("Forger-Realm", "Olympus Zeus"), 0, "legacy before activation")
			Install(Entry("Olympus Zeus=Real Lord-Realm,Real Captain-Other", 4), T0)
			eq(D.AuthorizedRank("Forger-Realm", "Olympus Zeus"), nil, "census loses authority on activation")
			eq(D.AuthorizedRank("Real Lord-Realm", "Olympus Zeus"), 0)
			eq(D.AuthorizedRank("Real Captain-Other", "Olympus Zeus"), 1)
			local forgedLevel, forgedVerified = ns.Channels.VerifiedLevel("Forger-Realm", "Olympus Zeus")
			eq(forgedLevel, 1); eq(forgedVerified, false, "a forged Lord cannot write privileged chat")
			local signedLevel, signedVerified = ns.Channels.VerifiedLevel("Real Lord-Realm", "Olympus Zeus")
			eq(signedLevel, 3); eq(signedVerified, true, "the signed Lord can write it")
			eq(ns.Bank.LordOrCaptain("Forger-Realm", "Olympus Zeus"), false, "nor issue a bank request")
			eq(ns.Bank.LordOrCaptain("Real Captain-Other", "Olympus Zeus"), true)
			eq(ns.King.Verified("Forger-Realm", "Olympus Zeus"), false, "nor write names onto the King's page")
			eq(ns.King.Verified("Real Captain-Other", "Olympus Zeus"), true)
			eq(ns.Hop.Trusted("Forger-Realm"), false, "nor auto-accept a layer invite")
			eq(ns.Hop.Trusted("Real Captain-Other"), true)
			Install(Entry("Olympus Zeus=Rollback-Realm", 3), T0 + 1)
			eq(D.AuthorizedRank("Rollback-Realm", "Olympus Zeus"), nil, "lower epoch")
			Install(Entry("Olympus Zeus=Next-Realm", 5), T0 + 2)
			eq(D.AuthorizedRank("Next-Realm", "Olympus Zeus"), 0, "higher epoch")
			Install(Entry("Olympus Zeus=Replay-Realm", 5), T0 + 1)
			eq(D.AuthorizedRank("Replay-Realm", "Olympus Zeus"), nil, "older HT replay")
			Install(Entry("-", 5), T0 + 3)
			eq(A.Enforced(), true); eq(D.AuthorizedRank("Next-Realm", "Olympus Zeus"), nil, "empty tombstone")
			Install("^^", T0 + 4)
			eq(A.Enforced(), true); eq(D.AuthorizedRank("Forger-Realm", "Olympus Zeus"), nil, "newer absence cannot reopen")
		end)
	end)

	test("authority: a malformed replacement keeps its valid epoch as a downgrade floor", function()
		WithState(function()
			Install(Entry("Olympus Zeus=Same-Realm,Same-Realm", 7), T0)
			eq(A.Enforced(), true); eq(A.Rank("Same-Realm", "Olympus Zeus"), nil)
			Install(Entry("Olympus Zeus=Lower-Realm", 6), T0 + 1)
			eq(A.Rank("Lower-Realm", "Olympus Zeus"), nil, "a lower generation cannot recover roles")
			Install(Entry("Olympus Zeus=Recovered-Realm", 8), T0 + 2)
			eq(A.Rank("Recovered-Realm", "Olympus Zeus"), 0, "a higher generation can repair it")
		end)
	end)

	test("authority: local roster and pinned King remain authoritative after enforcement", function()
		WithState(function()
			Install(Entry("-", 1))
			ns.Roster.byName["Local Captain-Realm"] = 1
			eq(select(2, D.AuthorizedRank("Local Captain-Realm", "Olympus II")), "roster")
			eq(select(2, D.AuthorizedRank(ns.KING_CHARACTER.Alliance .. "-Realm", "Olympus")), "pinned")
		end)
	end)

	test("authority: queued chat rechecks signed authority at the actual game send", function()
		WithState(function()
			local cns = setmetatable({}, { __index = ns })
			cns.RegisterEvent, cns.On, cns.After, cns.Every = function() end, function() end, function() end, function() end
			local sent, done = {}, {}
			local savedInfo, savedChannel = C_ChatInfo, GetChannelName
			local ok, err = pcall(function()
				C_ChatInfo = { SendAddonMessage = function(_, msg) sent[#sent + 1] = msg return true end,
					SendAddonMessageLogged = function(_, msg) sent[#sent + 1] = msg return true end }
				GetChannelName = function() return 7 end
				assert(loadfile("Olympus/Comm.lua"))("Olympus", cns)
				cns.Comm.JoinChannel()
				Install(Entry("Olympus Zeus=Remote Lord-Realm", 1), T0)
				local function Guard() return D.AuthorizedRank("Remote Lord-Realm", "Olympus Zeus") == 0 end
				eq(cns.Comm.SendChat("M1~L~Olympus Zeus~1~~held", function(ok2, why) done[#done + 1] = { ok2, why } end, {}, Guard), true)
				Install(Entry("-", 1), T0 + 1)
				cns.Comm.Pump()
				eq(#sent, 0, "revoked bytes never reach Blizzard's send API")
				eq(done[1][1], false); eq(done[1][2], "invalid")
				Install(Entry("Olympus Zeus=Remote Lord-Realm", 2), T0 + 2)
				eq(cns.Comm.SendChat("M1~L~Olympus Zeus~2~~current", function(ok2) done[#done + 1] = { ok2 } end, {}, Guard), true)
				cns.Comm.Pump()
				eq(#sent, 1); eq(done[2][1], true, "unchanged authority sends")
			end)
			C_ChatInfo, GetChannelName = savedInfo, savedChannel
			if not ok then error(err, 0) end
		end)
	end)

	test("authority: signed multipart bundles activate atomically and reverify after reload", function()
		WithState(function()
			WithFakeSign(function(Parts)
				local parts = Parts({ "Olympus Zeus=Signed Lord-Realm", "Olympus Ares=Signed Captain-Other" },
					{ at = T0 + 10, epoch = 7 })
				local ok, why = A.TakePart(parts[2], nil, "LOCAL")
				eq(ok, true); eq(why, "partial")
				eq(A.Enforced(), true, "one verified part establishes the fail-closed boundary")
				eq(A.Manifest(), nil, "a partial set grants nobody")
				eq(A.Rank("Signed Captain-Other", "Olympus Ares"), nil)
				ok, why = A.TakePart(parts[2], nil, "LOCAL")
				eq(ok, true); eq(why, "partial", "a duplicate does not advance the part count")
				ok, why = A.TakePart(parts[1], nil, "LOCAL")
				eq(ok, true); eq(why, "complete")
				eq(A.Rank("Signed Lord-Realm", "Olympus Zeus"), 0)
				eq(A.Rank("Signed Captain-Other", "Olympus Ares"), 0,
					"the first identity in each guild is that guild's Lord")
				assert(ns.rdb.authorityBundles["other+realm|Alliance"], "the complete raw signed set is scoped to the realm group and faction")
				A.Reset()
				eq(A.Rank("Signed Lord-Realm", "Olympus Zeus"), 0, "the stored blobs are reverified after reload")
				local verify = ns.Sign.Verify
				ns.Sign.Verify = function() return false end
				A.Reset()
				eq(A.Manifest(), nil, "a SavedVariables edit without valid signatures grants nobody")
				ns.Sign.Verify = verify
			end)
		end)
	end)

	test("authority: partial replacement, conflict, replay, bad digest and tombstone all fail closed", function()
		WithState(function()
			WithFakeSign(function(Parts)
				local old = Parts({ "Olympus Zeus=Old Lord-Realm" }, { at = T0 + 10, epoch = 3 })
				eq(select(2, A.TakePart(old[1], nil, "LOCAL")), "complete")
				eq(A.Rank("Old Lord-Realm", "Olympus Zeus"), 0)

				local replacement = Parts({ "Olympus Zeus=New Lord-Realm", "Olympus Ares=New Ares-Other" },
					{ at = T0 + 20, epoch = 4 })
				eq(select(2, A.TakePart(replacement[2], nil, "LOCAL")), "partial")
				eq(A.Rank("Old Lord-Realm", "Olympus Zeus"), nil, "the first newer part revokes the older complete set")
				local conflict = Parts({ "Olympus Zeus=Other Lord-Realm" }, { at = T0 + 20, epoch = 4, sig = "b" })
				local ok, why = A.TakePart(conflict[1], nil, "LOCAL")
				eq(ok, false); eq(why, "conflict"); eq(A.Manifest(), nil)
				eq(select(2, A.TakePart(replacement[1], nil, "LOCAL")), "complete")
				eq(A.Rank("New Lord-Realm", "Olympus Zeus"), 0, "the exact pending root can still finish")

				local downgrade = Parts({ "Olympus Zeus=Downgrade-Realm" }, { at = T0 + 30, epoch = 2 })
				ok, why = A.TakePart(downgrade[1], nil, "LOCAL")
				eq(ok, false); eq(why, "replay"); eq(A.Manifest(), nil, "a newer time cannot lower the signed generation")
				local recovered = Parts({ "Olympus Zeus=Recovered-Realm" }, { at = T0 + 40, epoch = 5 })
				eq(select(2, A.TakePart(recovered[1], nil, "LOCAL")), "complete")
				eq(A.Rank("Recovered-Realm", "Olympus Zeus"), 0)
				ok, why = A.TakePart(old[1], nil, "LOCAL")
				eq(ok, false); eq(why, "replay", "an older signed set cannot replay")

				local bad = Parts({ "Olympus Zeus=Digest One-Realm", "Olympus Ares=Digest Two-Other" },
					{ at = T0 + 50, epoch = 6, root = string.rep("0", 64) })
				eq(select(2, A.TakePart(bad[1], nil, "LOCAL")), "partial")
				ok, why = A.TakePart(bad[2], nil, "LOCAL")
				eq(ok, false); eq(why, "digest"); eq(A.Manifest(), nil, "individually signed parts with a false root grant nobody")

				local tombstone = Parts({ "-" }, { at = T0 + 60, epoch = 7 })
				eq(select(2, A.TakePart(tombstone[1], nil, "LOCAL")), "complete")
				local manifest = A.Manifest()
				assert(manifest and next(manifest.guilds) == nil, "a signed empty generation is a usable revocation tombstone")
				local oversized = tombstone[1] .. string.rep("0", A.MAX_PART_TEXT)
				ok, why = A.TakePart(oversized, nil, "LOCAL")
				eq(ok, false); eq(why, "size"); assert(A.Manifest(), "malformed unsigned input cannot move the boundary")
			end)
		end)
	end)

	test("authority: bundle answers are private and net-off is rechecked at the actual send", function()
		WithState(function()
			WithFakeSign(function(Parts)
				local parts = Parts({ "Olympus Zeus=Answer Lord-Realm", "Olympus Ares=Answer Ares-Other" },
					{ at = T0 + 10, epoch = 2 })
				eq(select(2, A.TakePart(parts[1], nil, "LOCAL")), "partial")
				eq(select(2, A.TakePart(parts[2], nil, "LOCAL")), "complete")
				eq(select(2, A.HandlePart("GUILD", "Peer-Realm", "H2~" .. parts[1])), "route")
				eq(select(2, A.HandlePart("CHANNEL", "Peer-Realm", "H2~" .. parts[1])), "route")

				local comm, workshop, moderation, after = ns.Comm, ns.Workshop, ns.Moderation, ns.After
				local handlers, queued, delayed, room = {}, {}, {}, 60
				local ok, err = pcall(function()
					ns.Comm = {
						Handle = function(kind, fn) handlers[kind] = fn end,
						PeerCount = function() return 1 end,
						QueueRoom = function() return room end,
						Send = function() return true end,
						SendBatch = function(dist, pieces, key, target, urgent, done, options)
							queued[#queued + 1] = { dist = dist, pieces = pieces, key = key, target = target, done = done, options = options }
							return true
						end,
					}
					ns.Workshop = setmetatable({ IsAuthor = function() return true end }, { __index = workshop })
					ns.Moderation = { missing = false, Blocks = function() return false end }
					A.Reset(); A.Start()
					assert(handlers.H2 and handlers.H3, "both authority wire types are registered once")
					ns.After = function(seconds, _, fn)
						if seconds < 5 then fn() else delayed[#delayed + 1] = fn end
					end
					eq(A.HandleAsk("GUILD", "Peer-Realm", "H3~Alliance~0~0"), true)
					eq(A.HandleAsk("CHANNEL", "Peer-Realm", "H3~Alliance~0~0"), false,
						"one requester cannot start a second transfer through another public route")
					eq(A.HandleAsk("GUILD", "Other-Realm", "H3~Alliance~0~0"), true)
					eq(#queued, 1, "one holder serves only one large authority bundle at a time")
					eq(#queued, 1, "only one bounded part enters Comm's queue at a time")
					eq(queued[1].dist, "WHISPER"); eq(queued[1].target, "Peer-Realm")
					assert(queued[1].pieces[1]:find("H2~HA1~", 1, true), "the private transfer carries the signed HA1 part")
					eq(queued[1].options.guard(), true)
					room = 0
					queued[1].done(true)
					eq(#queued, 1, "background authority waits instead of evicting ordinary queued work")
					eq(#delayed, 1)
					room = 60
					delayed[1]()
					eq(#queued, 2, "the next part starts only after the prior whole part completes")
					ns.Moderation.Blocks = function(msg) return msg == "H2~" end
					eq(queued[2].options.guard(), false, "net-off after queuing cancels before Blizzard's send API")
				end)
				ns.Comm, ns.Workshop, ns.Moderation, ns.After = comm, workshop, moderation, after
				A.Reset()
				if not ok then error(err, 0) end
			end)
		end)
	end)

	test("authority: one sender's parts spend his own share of the signature checks, never the whole lane's", function()
		WithState(function()
			WithFakeSign(function(Parts)
				local function Junk(i) return Parts({ "Olympus Zeus=Junk" .. i .. "-Realm" }, { at = T0 + i, epoch = 2, unsigned = true })[1] end
				for i = 1, A.VERIFY_EACH or 4 do eq(select(2, A.HandlePart("WHISPER", "Spammer-Realm", "H2~" .. Junk(i))), "signature") end
				eq(select(2, A.HandlePart("WHISPER", "Spammer-Realm", "H2~" .. Junk(99))), "budget", "past his share")
				-- Another sender's part is still checked, and a real holder's set completes.
				local parts = Parts({ "Olympus Zeus=Answer Lord-Realm" }, { at = T0 + 10, epoch = 2 })
				eq(select(2, A.HandlePart("WHISPER", "Holder-Realm", "H2~" .. parts[1])), "complete")
			end)
		end)
	end)

	test("authority: while enforcement is dormant H3 asks stop after the login burst; past the boundary they keep recovering", function()
		WithState(function()
			local comm, isMember, after, every = ns.Comm, ns.IsMember, ns.After, ns.Every
			local sent = 0
			local ok, err = pcall(function()
				ns.Comm = { Handle = function() end, Send = function() sent = sent + 1 return true end }
				ns.IsMember = function() return true end
				ns.After, ns.Every = function() end, function() end
				A.Reset(); A.Start()
				local now = T0
				ns.Now = function() return now end
				eq(A.Enforced(), false)
				for _ = 1, A.ASKS do eq(A.Ask(true), true) end
				now = now + A.ASK_IDLE + 1
				eq(A.Ask(false), false, "dormant: no ask after the burst")
				-- Past the boundary (a verified first part), the client keeps asking for the rest.
				WithFakeSign(function(Parts)
					local parts = Parts({ "Olympus Zeus=Answer Lord-Realm", "Olympus Ares=Answer Ares-Other" }, { at = T0 + 10, epoch = 2 })
					eq(select(2, A.TakePart(parts[1], nil, "LOCAL")), "partial")
				end)
				eq(A.Enforced(), true)
				eq(A.Ask(false), true)
				eq(sent, 2 * (A.ASKS + 1), "the channel and the guild each time")
			end)
			ns.Comm, ns.IsMember, ns.After, ns.Every = comm, isMember, after, every
			if not ok then error(err, 0) end
		end)
	end)
