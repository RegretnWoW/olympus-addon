-- Own-guild authority uses the real roster and nomination code on each separate client.
local H = ...
local test, eq, World = H.test, H.eq, H.World
local function Client(w, name, options)
	local c = w:Client(name, options)
	w:As(c, function()
		for _, module in ipairs({ "Roster", "Data", "Nominees", "Bank" }) do
			assert(loadfile(H.ADDON_DIR .. module .. ".lua"))("Olympus", c.ns)
		end
	end)
	c.ns.UI = { SelectTab = function(tab) c.openTab = tab end }
	-- The world transports actual encoded Treasury chunks; the queue checks its guard on delivery.
	local C, rawSend = c.ns.Comm, c.ns.Comm.Send
	C.Send = function(dist, msg, key, urgent, logged, done, options)
		if options and options.guard and not options.guard() then if done then done(false) end; return false end
		rawSend(dist, msg, key, urgent, logged, done)
		return true
	end
	C.Cancel = function() end
	C.SendBatch = function(dist, pieces, _, target, urgent, done, options)
		w:Timer(c, 0, nil, function()
			if options and options.guard and not options.guard() then if done then done(false) end; return end
			for _, piece in ipairs(pieces) do C.Whisper(target, piece, nil, urgent) end
			if done then done(true) end
		end, "guild bank batch")
		return true
	end
	return c
end
local function Scan(w)
	for _, c in ipairs(w.clients) do
		local rows = {}
		for _, peer in ipairs(w.clients) do if peer.guild == c.guild then rows[#rows + 1] = peer end end
		c.globals.GetNumGuildMembers = function() return #rows, #rows end
		c.globals.GetGuildRosterInfo = function(i)
			local p = rows[i]
			if p then return p.name, p.rankName, p.rank, 60, "Mage", "Stormwind", "", "", true, nil, "MAGE", nil, nil, nil, nil, nil, p.guid end
		end
		w:As(c, function() assert(c.ns.Roster.Scan()); assert(c.ns.Roster.Fresh()) end)
	end
end
local function Setup()
	local w = World.New({ compliance = "shipped" })
	local gm = Client(w, "Marin Vale", { rank = 0 })
	local treasurer = Client(w, "Soren Ledger")
	local member = Client(w, "Lark Stone")
	local outsider = Client(w, "Aster Dale", { guild = "Olympus Ash", rank = 0 })
	Scan(w)
	w:As(gm, function()
		assert(gm.ns.Nominees.Name("correspondent", treasurer.name, "Federal Treasury"))
		gm.ns.Nominees.Send(true)
		gm.rdb.bank = { by = gm.name, guild = gm.guild, t = w.clock, money = 45000,
			tabs = { { i = 1, name = "Private tab name", items = { { id = 14342, n = 4, s = 1 } } } } }
	end)
	w:Run(0)
	return w, gm, treasurer, member, outsider
end

test("guild treasury: correspondent sees only its guild's private stock; GM publication and withdrawal reach members", function()
	local w, gm, treasurer, member, outsider = Setup()
	w:As(treasurer, function()
		assert(treasurer.ns.Bank.OwnGuildKeeper(), "the GM's actual transmitted nomination is trusted")
		eq(treasurer.ns.Treasury.IsKeeper(), false, "not a federal keeper")
		eq(treasurer.ns.Bank.SeesSisters(), false, "no directory authority")
		assert(treasurer.ns.Bank.AskOwnGuild())
	end)
	w:As(member, function() assert(member.ns.Bank.AskOwnGuild()) end)
	w:Run(15)
	w:As(treasurer, function()
		eq(treasurer.ns.Bank.OwnGuildSnapshot().money, 45000)
		eq(treasurer.ns.Bank.OwnGuildSnapshot().tabs[1].name, "Tab 1", "private tab labels never travel")
		assert(treasurer.ns.Treasury.OpenOwnGuild())
		eq(treasurer.openTab, "treasury")
		local lines = treasurer.ns.Treasury.Build()
		assert(#lines > 3)
	end)
	w:As(member, function() eq(member.ns.Bank.OwnGuildSnapshot(), nil) end)
	w:As(gm, function() assert(gm.ns.Bank.SetOwnGuildPublic(true)) end)
	w:Run(15)
	w:As(member, function() eq(member.ns.Bank.OwnGuildSnapshot().money, 45000) end)
	w:As(outsider, function() eq(outsider.ns.Bank.OwnGuildSnapshot(), nil) end)
	w:As(gm, function() assert(gm.ns.Bank.SetOwnGuildPublic(false)) end)
	w:Run(0)
	w:As(member, function() eq(member.ns.Bank.OwnGuildSnapshot(), nil) end)
	w:As(treasurer, function() assert(treasurer.ns.Bank.OwnGuildSnapshot()) end)
	w:As(gm, function() assert(gm.ns.Bank.SetOwnGuildPublic(true)) end)
	w:Run(180)
	Scan(w) -- the transport gap is longer than the security roster's two-minute freshness.
	w:As(gm, function()
		gm.ns.Treasury.FlushPrivate()
		gm.ns.Bank.ShareOwnGuild() -- actual periodic retry; this extension loads Bank after LOGIN.
	end)
	w:Run(15)
	w:As(member, function()
		local snap = member.ns.Bank.OwnGuildSnapshot()
		assert(snap, "unchanged stock is delivered again after a fresh roster and the paced retry")
		eq(snap.money, 45000, "unchanged stock comes back after the paced resend")
	end)
end)

test("guild treasury: forged guild, rank, route, expiry, oversized snapshot and revoked nomination fail closed", function()
	local w, gm, treasurer, member, outsider = Setup()
	local msg = w:As(gm, function() return gm.ns.Bank.Message(gm.rdb.bank, "UG") end)
	w:As(treasurer, function()
		local B = treasurer.ns.Bank
		eq(B.HandleOwnGuild("CHANNEL", gm.name, msg), false)
		eq(B.HandleOwnGuild("WHISPER", outsider.name, msg), false)
		eq(B.HandleOwnGuild("WHISPER", member.name, msg), false)
		eq(B.HandleOwnGuild("WHISPER", gm.name, msg:gsub(gm.guild, "Olympus Ash", 1)), false)
		eq(B.HandleOwnGuild("WHISPER", gm.name, msg .. string.rep("x", 10000)), false)
		eq(B.HandleOwnGuild("WHISPER", gm.name, msg:gsub("14342x4", "999999999999999999999999999x4")), false)
		eq(B.HandleOwnGuild("WHISPER", gm.name, msg:gsub(tostring(w.clock), tostring(w.clock - B.OWN_GUILD_KEEP - 1), 1)), false)
		assert(B.HandleOwnGuild("WHISPER", gm.name, msg))
		treasurer.ns.Roster.snapshotAt = w.clock - treasurer.ns.Roster.AUTHORITY_FRESH - 1
		eq(B.OwnGuildSnapshot(), nil, "an old roster is no authority")
	end)
	Scan(w)
	w:As(member, function()
		eq(member.ns.Bank.SetOwnGuildPublic(true), false)
		local grant = ("UP~%s~%.0f~%d~1"):format(gm.guild, w.clock * 1000, w.clock)
		eq(member.ns.Bank.HandleGuildGrant("GUILD", treasurer.name, grant), false)
		eq(member.ns.Bank.HandleGuildGrant("CHANNEL", gm.name, grant), false)
		eq(member.ns.Bank.HandleGuildGrant("GUILD", gm.name, grant:gsub(gm.guild, "Olympus Ash", 1)), false)
		eq(member.ns.Bank.HandleGuildGrant("GUILD", gm.name, ("UP~%s~%.0f~%d~1"):format(gm.guild, w.clock * 1000, w.clock - 1900)), false)
		assert(member.ns.Bank.HandleGuildGrant("GUILD", gm.name, grant))
		eq(member.ns.Bank.HandleOwnGuild("WHISPER", member.name, msg), false, "public does not authorize a supplier")
		eq(member.ns.Bank.HandleGuildGrant("GUILD", gm.name, grant:gsub("~1$", "~0")), false, "an equal revision cannot replace the grant")
	end)
	w:As(gm, function() assert(gm.ns.Nominees.Remove(treasurer.name)); gm.ns.Nominees.Send(true) end)
	w:Run(0)
	w:As(treasurer, function() eq(treasurer.ns.Bank.OwnGuildKeeper(), false); eq(treasurer.ns.Bank.OwnGuildSnapshot(), nil) end)
end)

test("guild treasury: previews never publish, revoked queued sends stop, and a missing GM's public lease expires", function()
	local w, gm, treasurer, member = Setup()
	w:As(gm, function()
		gm.db.devGMView = true
		eq(gm.ns.Bank.SetOwnGuildPublic(true), false)
		eq(gm.ns.Bank.AskOwnGuild(), false)
		eq(gm.ns.Bank.OwnGuildSnapshot(), nil)
		eq(gm.ns.Treasury.OpenOwnGuild(), false)
		gm.db.devGMView = nil
		gm.rank = 1
		eq(gm.ns.Bank.OwnGuildMaster(), false, "live demotion beats a cached rank-zero roster")
		eq(gm.ns.Bank.SetOwnGuildPublic(true), false)
		gm.rank = 0
		assert(gm.ns.Bank.SetOwnGuildPublic(true))
	end)
	w:Run(0)
	w:As(member, function() assert(member.ns.Bank.AskOwnGuild()); eq(member.ns.Bank.AskOwnGuild(), false, "paced ask") end)
	-- Admission succeeds, then the GM withdraws before the queued batch actually sends.
	w:As(gm, function()
		assert(gm.ns.Bank.HandleGuildAsk("GUILD", member.name, ("UQ~%s~%.0f"):format(gm.guild, w.clock * 1000)))
		assert(gm.ns.Bank.SetOwnGuildPublic(false))
	end)
	w:Run(15)
	w:As(member, function() eq(member.ns.Bank.OwnGuildSnapshot(), nil) end)
	w:As(gm, function() assert(gm.ns.Bank.SetOwnGuildPublic(true)) end)
	w:Run(0)
	w:As(member, function() eq(member.ns.Bank.OwnGuildPublic(), true) end)
	local asked = #w:Sent({ from = member, type = "UQ" })
	w:As(gm, function() assert(gm.ns.Bank.SetOwnGuildPublic(true)) end) -- new generation, same visible state
	w:Run(0)
	assert(#w:Sent({ from = member, type = "UQ" }) > asked, "a new ON generation gets an acknowledgement even if OFF was missed")
	w.clock = w.clock + gm.ns.Bank.OWN_GUILD_LEASE + 1
	Scan(w)
	w:As(member, function() eq(member.ns.Bank.OwnGuildPublic(), false); eq(member.ns.Bank.OwnGuildSnapshot(), nil) end)
	for _, c in ipairs({ gm, treasurer, member }) do eq(#c.errors, 0, table.concat(c.errors, "\n")) end
end)
