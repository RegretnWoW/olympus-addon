local ns, test, eq, WithWindow = ...

test("watch chat context menu: actions are opt-in and recheck permission and target", function()
	WithWindow(function(w)
		local saved, allowed, calls, timed = rawget(ns, "WatchChat"), true, {}, true
		rawset(ns, "WatchChat", {
			StripText = function() return nil end, RecordLines = function() return {} end,
			CanModerateAny = function() return true end,
			CanModerateEntry = function() return allowed end,
			TimeoutOf = function() return timed end,
			AskEntry = function() error("initial action modal must not open") end,
			AskWhy = function(data, op) calls[#calls + 1] = { op, data.entry, data.chat } end,
			AskName = function(name, op) calls[#calls + 1] = { op, name } end,
		})
		local ok, err = pcall(function()
			local f = w.CW.Open("A")
			local b = CreateFrame("Frame", nil, f)
			b:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -130); b:SetSize(200, 30)
			b.chat, b.entry = "A", { sender = "Example-Realm", text = "line", id = 123 }
			local e = b.entry
			eq(w.CW.ModerateLine(b), true); eq(f.subMenu:IsShown(), true); eq(#calls, 0)
			eq(f.subMenu.rows[1].text:GetText(), ns.L.WATCHCHAT_DELETE_LINE)
			w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), true)
			f.subMenu.rows[1]:Click(); eq(calls[1][1], "D"); eq(calls[1][2], e); eq(calls[1][3], "A")
			for i, op in ipairs({ "timeout", "purge", "lift" }) do
				w.CW.ModerateLine(b); f.subMenu.rows[i + 1]:Click(); eq(calls[i + 1][1], op)
			end
			w.CW.ModerateLine(b); allowed = false; f.subMenu.rows[1]:Click(); eq(#calls, 4, "stale callback cannot moderate")
			allowed = true; w.CW.ModerateLine(b); allowed = false; w.fire("WATCHCHAT_CHANGED"); eq(f.subMenu:IsShown(), false)
			allowed = true; w.CW.ModerateLine(b); b.entry = { sender = "Other-Realm" }; f.subMenu.rows[1]:Click(); eq(#calls, 4, "reused bubble cannot change the target")
			b.entry = e; w.CW.ModerateLine(b); e.del = true; w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), false)
			e.del = nil; timed = false; w.CW.ModerateLine(b); eq(f.subMenu.rows[4]:IsShown(), false)
			f.subCatcher:Click(); eq(f.subMenu:IsShown(), false)
		end)
		rawset(ns, "WatchChat", saved)
		if not ok then error(err, 0) end
	end)
end)

test("chat destination dropdown: unchanged census redraw keeps menu open; selection and outside click close it", function()
	WithWindow(function(w)
		ns.db.chatRooms = true
		local f = w.CW.Open("A")
		local race
		for _, button in ipairs(f.subtabs.nav) do if button.item.entry.kind == "race" then race = button end end
		assert(race); race:Click(); eq(f.subMenu:IsShown(), true)
		w.fire("DATA_CHANGED"); w.CW.Render()
		eq(f.subMenu:IsShown(), true, "ordinary census refresh must not eat the user's dropdown")
		f.subCatcher:Click(); eq(f.subMenu:IsShown(), false)
		race:Click(); f.subMenu.rows[1]:Click()
		eq(f.subMenu:IsShown(), false); eq(w.CW.Tier(), "race:1")
	end)
end)

test("role chat navigation: real dropdown redraws with the preview without opening private history", function()
	WithWindow(function(w)
		local R, V = ns.ChatRooms, ns.ViewAs
		local saved = { preview = V.Previewing, role = V.Role, council = ns.IsHighCouncillor, history = R.History }
		local ok, err = pcall(function()
			local role, council, reads = "member", false, 0
			V.Previewing = function() return role ~= "my" end
			V.Role = function() return role end
			ns.IsHighCouncillor = function() return council end
			R.History = function(id) if id == "council" then reads = reads + 1 end return {} end
			ns.db.chatRooms = true
			local f = w.CW.Open("A")
			local function Tab(kind)
				for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == kind then return b end end
			end
			for _, kind in ipairs({ "global", "guild", "race", "class", "arena" }) do assert(Tab(kind), kind) end
			eq(Tab("role"), nil)
			role = "king"; w.fire("DATA_CHANGED"); w.CW.Render()
			assert(Tab("role")); eq(Tab("authority"), nil); eq(Tab("department"), nil); eq(Tab("church"), nil)
			w.fire("CHAT_ROOM_LINE", "council"); w.CW.Render()
			eq(Tab("role").label:GetText():find("(1)", 1, true), nil, "preview does not reveal private unread counts")
			Tab("role"):Click()
			eq(f.subMenu:IsShown(), true); eq(f.subMenu.rows[1].roomId, "council")
			eq(f.subMenu.rows[2].roomId, "secretariat")
			f.subMenu.rows[1]:Click()
			eq(w.CW.Tier(), "A"); eq(reads, 0)
			eq(w.printed[#w.printed], ns.L.CHATROOM_ROLE_PREVIEW)
			role = "councillor"; w.fire("DATA_CHANGED"); w.CW.Render()
			eq(f.subMenu:IsShown(), false, "stale popup closes when the view changes")
			Tab("role"):Click(); eq(f.subMenu.rows[2].roomId, "dept:treasury")
			council = true
			eq(w.CW.SelectLogical("council"), false, "real authority does not unlock a preview")
			eq(reads, 0)
			role = "my"; w.fire("DATA_CHANGED"); w.CW.Render()
			Tab("role"):Click(); f.subMenu.rows[1]:Click()
			eq(w.CW.Tier(), "council"); eq(reads > 0, true)
			eq(Tab("role").underline:IsShown(), true, "all restricted rooms select the single role tab")
			local before = reads
			role = "member"; w.fire("DATA_CHANGED"); w.CW.Render()
			eq(Tab("role"), nil); eq(w.CW.Tier(), "A"); eq(reads, before, "private room leaves the screen under a preview")
		end)
		V.Previewing, V.Role, ns.IsHighCouncillor, R.History = saved.preview, saved.role, saved.council, saved.history
		if not ok then error(err, 0) end
	end)
end)
