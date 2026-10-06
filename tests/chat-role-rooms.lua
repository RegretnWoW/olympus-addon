local ns, test, eq, WithRooms, RoomMessage = ...
local function Ids(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.id end
	return table.concat(out, ",")
end

test("role chat navigation: one dropdown follows actual restricted audiences", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.stewards[me], w.departments[me] = true, true, "War"
		assert(R.RegisterAudience("church", { label = "Church", CanAccess = function() return w.church == true end, Recipients = function() return {} end }))
		w.church = true
		local tabs = R.Tabs()
		eq(#tabs, 4); eq(tabs[4].kind, "role"); eq(tabs[4].dropdown, true)
		eq(Ids(R.Options("role")), "council,secretariat,dept:war,departments,church")
		w.church, w.stewards[me] = false, nil
		eq(Ids(R.Options("role")), "council,dept:war,departments", "audience removals reflected immediately")
		w.council[me] = nil
		eq(#R.Options("role"), 0); eq(#R.Tabs(), 3)
	end)
end)

test("role chat navigation: preview changes destinations but never authority or private data", function()
	WithRooms(function(w, R, c)
		local role = "member"
		c.ViewAs = { Previewing = function() return role ~= "my" end, Role = function() return role end }
		assert(R.RegisterAudience("church", { label = "Church", CanAccess = function() return false end, Recipients = function() return {} end }))
		eq(#R.Options("role"), 0)
		role = "king"
		eq(Ids(R.Options("role")), "council,secretariat,dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments,church")
		for _, option in ipairs(R.Options("role")) do
			eq(option.disabled, true, "preview destinations are inert")
			eq(R.CanAccess(option.id), false); eq(R.Select(option.id), false)
			eq(R.Send(option.id, "not authorized"), false)
			eq(#R.History(option.id), 0)
		end
		eq(#w.jobs, 0); eq(w.attempts, 0, "no restricted transport attempted")
		eq(R.Receive("WHISPER", "Aldric Vane-Realm", RoomMessage("council", 1, "private")), false)
		role = "councillor"
		eq(Ids(R.Options("role")), "council,dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments,church")
		role = "treasurer"; eq(Ids(R.Options("role")), "council,dept:treasury,treasurers")
		role = "gm"; eq(Ids(R.Options("role")), "masters")
		role = "officer"; eq(Ids(R.Options("role")), "centurions,allcenturions")
		role = "correspondent"; eq(Ids(R.Options("role")), "dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments")
		for _, r in ipairs({ "member", "outsider", "my" }) do
			role = r; eq(#R.Options("role"), 0, r .. " is not federal authority")
		end
		w.council[c.me:lower()] = true
		role = "king"
		eq(R.Options("role")[1].disabled, true, "even an authorized reader cannot open real lines under a preview")
		eq(R.PreviewOnly("council"), true); eq(R.PreviewOnly("guild"), false)
		role = "my"; eq(R.Options("role")[1].disabled, false); eq(R.PreviewOnly("council"), false)
	end)
end)
