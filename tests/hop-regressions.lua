-- Exercise the real hop and layer modules through the upstream WoW fixture.
local ns, test, eq, WithHop = ...

local function Join(w, H)
	w.see(7)
	H.Ask(1453, 8, "destination")
	H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
	w.clock = w.clock + H.WINDOW
	H.Tick()
	H.OnInvite("Helper")
	w.group, w.party.party1 = 2, "Helper"
	H.OnRoster()
end

test("hop regression: a different wrong layer is not successful and never auto-leaves", function()
	WithHop(function(w, H)
		Join(w, H)
		w.see(9); H.OnLayer()
		eq(w.left, 0); eq(H.Stats().moves, 0); eq(H.State().phase, "joined")
		w.see(8); H.OnLayer()
		eq(w.left, 1); eq(H.Stats().moves, 1); eq(H.State().phase, "done")
	end)
end)

test("hop regression: seeing the destination before the roster event still completes", function()
	WithHop(function(w, H)
		w.see(7); H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick(); H.OnInvite("Helper")
		w.see(8); H.OnLayer()
		eq(w.left, 0, "not in the helper's group yet")
		w.group, w.party.party1 = 2, "Helper"; H.OnRoster()
		eq(w.left, 1); eq(H.Stats().moves, 1)
	end)
end)

test("hop regression: delayed offers recheck location and sharing before sending", function()
	for _, change in ipairs({
		function(w) w.see(8) end,
		function(w) w.map = 1429 end,
		function() ns.db.shareLocation = false end,
		function(w) w.combat = true end,
	}) do
		WithHop(function(w, H)
			w.see(7)
			local later
			H.after = function(_, _, fn) later = fn end
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			assert(later, "offer was scheduled")
			change(w); later()
			eq(#w.whispered, 0, "the old offer must not go out")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0); eq(#w.popups, 0)
		end)
	end
end)

test("hop regression: requests recheck the exact layer offered and the helper's opt-in", function()
	for _, change in ipairs({
		function(w) w.see(8) end,
		function(w) w.map = 1429 end,
		function() ns.db.layerHelp = false end,
		function() ns.db.shareLocation = false end,
		function(w, H) w.clock = w.clock + H.LAYER_FRESH + 1 end,
	}) do
		WithHop(function(w, H)
			w.see(7); ns.db.layerAutoInvite = true
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			change(w, H)
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0); eq(#w.popups, 0)
		end)
	end
end)

test("hop regression: an Invite button rechecks capacity, combat, opt-in, layer and age", function()
	for _, change in ipairs({
		function(w) w.group, w.lead = 5, true end,
		function(w) w.combat = true end,
		function() ns.db.layerHelp = false end,
		function() ns.db.shareLocation = false end,
		function(w) w.see(8) end,
		function(w, H) w.clock = w.clock + H.WAIT + 1 end,
	}) do
		WithHop(function(w, H)
			w.see(7); H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			local data = w.popups[1].data
			change(w, H)
			H.Answer(data, true)
			eq(#w.invited, 0); eq(w.whispered[#w.whispered], "Asker-Realm LN~42")
		end)
	end
end)

test("hop regression: queued requests stop after a zone change or joining another party", function()
	for _, change in ipairs({ function(w) w.map = 1429 end, function(w) w.group = 2 end }) do
		WithHop(function(w, H)
			w.see(7)
			for i = 1, H.BRAKE_ASKS + 1 do H.Hear(1453, 8, "Player" .. i, w.clock) end
			H.Ask(1453, 8, "busy layer"); eq(H.State().phase, "queued")
			local before = #w.sent
			change(w); w.clock = H.State().sendAt; H.Tick()
			eq(#w.sent, before); eq(H.State().phase, "done")
		end)
	end
end)

test("hop regression: an early decline waits for late offers within the original window", function()
	WithHop(function(w, H)
		w.see(7); H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Early-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		H.HandleNo("WHISPER", "Early-Realm", "LN~1")
		assert(H.State().phase ~= "done", "late offers still have time")
		w.clock = w.clock + 2
		H.HandleOffer("WHISPER", "Late-Realm", "LO~1~0~0"); H.Tick()
		eq(H.State().helper, "Late-Realm"); eq(w.whispered[#w.whispered], "Late-Realm LR~1")
	end)
end)

test("hop regression: a stale reading does not block an explicit request as already there", function()
	WithHop(function(w, H)
		w.see(8); w.clock = w.clock + H.LAYER_FRESH + 1
		H.Ask(1453, 8, "destination")
		assert(H.State() and H.State().phase == "asking")
	end)
end)

test("hop regression: a replaced group is never left by a running hop", function()
	WithHop(function(w, H)
		Join(w, H)
		w.party.party1 = "Friend"; H.OnRoster()
		w.see(8); H.OnLayer()
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop regression: one border NPC or repeated sightings of it cannot confirm a hop", function()
	WithHop(function(w, H)
		Join(w, H)
		w.npc, w.spawn = 8, 20
		ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0, "one target-layer NPC is provisional")
		ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0, "the same NPC twice is not independent evidence")
		w.spawn = 21; ns.Layers.Observe("target"); H.Tick()
		eq(w.left, 1); eq(H.Stats().moves, 1)
	end)
end)

test("hop controls: list and status are local; any selects the freshest alternative", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Older-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		w.clock = w.clock + 10
		ns.Layers.Receive("Fresh-Realm", { mapID = 1453, zoneUID = 9, guild = "Olympus" })
		local before, whispers = #w.sent, #w.whispered
		H.Command("list"); H.Command("status"); H.Command("bogus"); H.Command("12345")
		eq(#w.sent, before); eq(#w.whispered, whispers)
		H.Command(" ANY ")
		eq(H.State().zoneUID, 9); eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~9")
		assert(H.ProgressText():find("0", 1, true), "offers appear in progress")
	end)
end)

test("hop controls: explicit UID uses the current zone and cancel never leaves a group", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		SlashCmdList.OLYMPUS("hop #8")
		eq(H.State().zoneUID, 8)
		H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		SlashCmdList.OLYMPUS("hop cancel")
		H.OnInvite("Helper"); eq(w.accepted, 0, "late invite stays manual")
		eq(H.State().phase, "done"); eq(w.left, 0)
		w.clock = w.clock + H.ASK_GAP
		Join(w, H); eq(H.State().phase, "joined")
		H.Command("cancel"); w.see(8); H.OnLayer()
		eq(w.left, 0, "cancel while joined retains the player's group")
	end)
end)

test("hop controls: any needs a fresh local reading and skips old remote reports", function()
	WithHop(function(w, H)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		H.Command("any"); eq(H.State(), nil, "own layer unknown")
		w.see(7); w.clock = w.clock + H.LAYER_FRESH + 1
		H.Command("any"); eq(H.State(), nil, "own layer stale")
		w.see(7); H.Command("any"); eq(H.State(), nil, "only remote report is stale")
	end)
end)

test("hop controls: Realm rows show progress, cancel and the age of layer reports", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		local function Find(text, right)
			for _, row in ipairs(ns.Views.Build("realm")) do
				if (right and row.right == text) or (not right and row.text and row.text:find(text, 1, true)) then return row end
			end
		end
		local any = Find(ns.L.HOP_ANY_BUTTON)
		assert(any and any.onClick); any.onClick()
		eq(H.State().zoneUID, 8)
		local cancel = Find(ns.L.HOP_CANCEL_BUTTON, true)
		assert(cancel and cancel.onClick); cancel.onClick()
		eq(H.State().phase, "done"); eq(w.left, 0)
		local row = Find("#8")
		assert(row and row.tooltip)
		local tips = {}
		row.tooltip({ AddLine = function(_, line) tips[#tips + 1] = line end })
		assert(table.concat(tips, "\n"):find("Latest layer report:", 1, true))
	end)
end)

test("hop evidence: two NPC readings outside the confirmation window do not auto-leave", function()
	WithHop(function(w, H)
		Join(w, H)
		w.npc, w.spawn = 8, 20; ns.Layers.Observe("target")
		w.clock = w.clock + ns.Layers.EVIDENCE_WINDOW + 1
		w.spawn = 21; ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0)
		w.spawn = 22; ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 1)
	end)
end)

test("hop regression: a release arriving before the roster event never leaves a friend's group", function()
	WithHop(function(w, H)
		Join(w, H)
		w.party.party1 = "Friend"
		H.HandleRelease("WHISPER", "Helper-Realm", "LX~1")
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop regression: a dismissed leave dialog cannot leave after cancellation", function()
	WithHop(function(w, H)
		Join(w, H)
		w.clock = w.clock + H.JOIN_WAIT; H.Tick()
		local data = w.popups[#w.popups].data
		H.Cancel()
		StaticPopupDialogs.OLYMPUS_HOP_LEAVE.OnAccept(nil, data)
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop adversarial: an offer capability is bound to its sender and consumed once", function()
	WithHop(function(w, H)
		w.see(7)
		H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
		eq(w.whispered[1], "Asker-Realm LO~42~0~0")
		H.HandleRequest("WHISPER", "Spoof-Realm", "LR~42")
		eq(#w.invited, 0); eq(#w.popups, 0, "same id from another sender has no authority")
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
		eq(#w.popups, 1)
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
		eq(#w.popups, 1, "a replay cannot create a second prompt or invitation")
	end)
end)

test("hop mixed versions: the established LQ LO LR LN wire remains strict and interoperable", function()
	WithHop(function(w, H)
		w.see(7)
		H.Ask(1453, 8, "destination")
		eq(w.sent[1], "CHANNEL LQ~1~1453~8", "an older helper sees the unchanged request")
		H.HandleOffer("WHISPER", "Old-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Junk-Realm", "LO~1~0~0~extra")
		eq(H.State().count, 1, "a canonical old offer is accepted; an extended spoof is not")
		w.clock = w.clock + H.WINDOW; H.Tick()
		eq(w.whispered[1], "Old-Realm LR~1", "the old helper sees the unchanged invite request")
		H.HandleNo("WHISPER", "Old-Realm", "LN~1")
		assert(H.State().phase ~= "requested", "the unchanged decline is understood")
	end)
end)

test("hop adversarial: reset or cancellation revokes every old invite authorization", function()
	for _, reset in ipairs({ false, true }) do
		WithHop(function(w, H)
			w.see(7); H.Ask(1453, 8, "destination")
			H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
			w.clock = w.clock + H.WINDOW; H.Tick()
			if reset then H.Reset() else H.Cancel() end
			H.OnInvite("Helper")
			eq(w.accepted, 0, reset and "reload/reset" or "cancel")
			eq(w.left, 0)
		end)
	end
end)

test("issue 50: Always invite is automatic alone and with hop guests, manual in ordinary groups and raids", function()
	WithHop(function(w, H)
		w.see(7); ns.db.layerAutoInvite = true
		H.HandleAsk("CHANNEL", "First-Realm", "LQ~41~1453~7")
		H.HandleRequest("WHISPER", "First-Realm", "LR~41")
		eq(w.invited[1], "First"); eq(#w.popups, 0, "alone")

		w.clock = w.clock + H.HELP_GAP + 1
		w.group, w.lead, w.party.party1 = 2, true, "First"
		H.HandleAsk("CHANNEL", "Second-Realm", "LQ~42~1453~7")
		H.HandleRequest("WHISPER", "Second-Realm", "LR~42")
		eq(w.invited[2], "Second"); eq(#w.popups, 0, "a party containing only addon hop guests")
	end)
	for _, raid in ipairs({ false, true }) do
		WithHop(function(w, H)
			w.see(7); ns.db.layerAutoInvite = true
			w.group, w.lead = raid and 6 or 2, true
			w.party[raid and "raid1" or "party1"] = "Friend"
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0, raid and "ordinary raid" or "ordinary party")
			eq(#w.popups, 1, "the player must click")
			eq(H.Stats().autoBlocked, 1, "diagnosable without broadening the policy")
		end)
	end
end)

test("hop adversarial (1.2.0): a stranger on the channel gets no offer, and his request no window or invite, even with Always invite", function()
	WithHop(function(w, H)
		w.see(7)
		ns.db.layerAutoInvite = true
		w.strangers["Stranger-Realm"] = true
		H.HandleAsk("CHANNEL", "Stranger-Realm", "LQ~42~1453~7")
		eq(#w.whispered, 0, "no offer to a stranger")
		H.HandleRequest("WHISPER", "Stranger-Realm", "LR~42")
		eq(#w.invited, 0); eq(#w.popups, 0)
		-- A member of another federation guild, whose guild claim the channel takes: helped.
		w.strangers["Ally-Realm"] = true
		local guildOf, level = ns.Moderation.GuildOf, ns.Channels.VerifiedLevel
		ns.Moderation.GuildOf = function(n) return ns.FullName(n) == "Ally-Realm" and "Olympus III" or guildOf(n) end
		ns.Channels.VerifiedLevel = function(n, g) if ns.FullName(n) == "Ally-Realm" then return 1, false end return level(n, g) end
		local ok, err = pcall(function()
			H.HandleAsk("CHANNEL", "Ally-Realm", "LQ~43~1453~7")
			eq(w.whispered[1], "Ally-Realm LO~43~0~0")
			H.HandleRequest("WHISPER", "Ally-Realm", "LR~43")
			eq(w.invited[1], "Ally", "Always invite: invited")
		end)
		ns.Moderation.GuildOf, ns.Channels.VerifiedLevel = guildOf, level
		ns.db.layerAutoInvite = nil
		if not ok then error(err, 0) end
	end)
end)
