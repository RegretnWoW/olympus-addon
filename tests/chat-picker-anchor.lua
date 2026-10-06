local ns, test, eq, WithWindow, ForeverWorld = ...

local function Tab(frame, kind)
	for _, button in ipairs(frame.subtabs.nav) do
		if button:IsShown() and button.item.entry.kind == kind then return button end
	end
	error("missing destination " .. kind)
end

test("Chat picker anchor: Race and Class open below their clicked tabs, remain contained and close on redraw", function()
	WithWindow(function(w)
		local R, saved = ns.ChatRooms, ns.ChatRooms.Options
		local label, picked = "One room", 0
		R.Options = function(kind)
			if kind == "race" or kind == "class" then
				return { { label = label, onClick = function() picked = picked + 1 end } }
			end
			return saved(kind)
		end
		local ok, why = pcall(function()
			local f = w.CW.Open("A")
			for _, kind in ipairs({ "race", "class" }) do
				local owner = Tab(f, kind)
				owner:Click()
				local menu = f.subMenu
				assert(menu:IsShown())
				eq(menu:GetLeft(), owner:GetLeft(), kind .. " opens immediately under its tab")
				eq(menu:GetTop(), owner:GetBottom() - 2, "below the clicked tab")
				assert(menu:GetLeft() >= f:GetLeft() + 12 and menu:GetRight() <= f:GetRight() - 12)
				eq(menu:GetFrameStrata(), "DIALOG"); eq(f.subCatcher:GetFrameStrata(), "DIALOG")
				assert(menu:GetFrameLevel() > f.subCatcher:GetFrameLevel())
				menu.rows[1]:Click(); eq(menu:IsShown(), false)
				owner:Click(); f.subCatcher:Click(); eq(menu:IsShown(), false)
				owner:Click(); w.fire("DATA_CHANGED"); w.CW.Render(); eq(menu:IsShown(), false)
			end
			eq(picked, 2, "each choice still acts once")
			-- A long choice clamps instead of returning to the right regardless of its tab.
			label = string.rep("Long choice ", 40)
			for _, kind in ipairs({ "race", "class" }) do
				local owner = Tab(f, kind)
				owner:Click()
				local menu = f.subMenu
				eq(menu:GetTop(), owner:GetBottom() - 2)
				assert(menu:GetLeft() >= f:GetLeft() + 12 and menu:GetRight() <= f:GetRight() - 12)
				eq(menu.rows[1].text:GetText(), label, "tooltip retains the full label")
				eq(menu.rows[1].text.wrap, false)
				f.subCatcher:Click()
			end
		end)
		R.Options = saved
		if not ok then error(why, 0) end
	end)
end)

test("Chat picker anchor: Arena and role menus retain their right edge placement", function()
	WithWindow(function(w)
		local f = w.CW.Open("A")
		local arena = Tab(f, "arena")
		arena:Click()
		eq(f.subMenu:GetRight(), f:GetRight() - 12)
		eq(f.subMenu:GetTop(), arena:GetBottom() - 2)
		f.subCatcher:Click()
		local V, preview, role = ns.ViewAs, ns.ViewAs.Previewing, ns.ViewAs.Role
		local ok, why = pcall(function()
			V.Previewing = function() return true end
			V.Role = function() return "king" end
			w.fire("DATA_CHANGED"); w.CW.Render()
			local owner = Tab(f, "role")
			owner:Click()
			eq(f.subMenu:GetRight(), f:GetRight() - 12)
			eq(f.subMenu:GetTop(), owner:GetBottom() - 2)
			f.subCatcher:Click()
		end)
		V.Previewing, V.Role = preview, role
		if not ok then error(why, 0) end
	end)
end)

test("Chat picker anchor: Race and Class keep their clicked-tab positions in the HD window", function()
	WithWindow(function(w)
		w.CW.Open("A")
		OlympusFrame:Hide()
		local world = assert(ForeverWorld, "HD window helper")(true)
		CommunitiesFrame:Show(); world.buttons[1]:Click()
		local f = w.CW.Open("A")
		for _, kind in ipairs({ "race", "class" }) do
			local owner = Tab(f, kind)
			owner:Click()
			local menu = f.subMenu
			assert(menu:IsShown())
			eq(menu:GetLeft(), owner:GetLeft(), "the HD style also uses the clicked destination")
			eq(menu:GetTop(), owner:GetBottom() - 2)
			assert(menu:GetLeft() >= f:GetLeft() + 12 and menu:GetRight() <= f:GetRight() - 12)
			f.subCatcher:Click()
		end
	end)
end)
