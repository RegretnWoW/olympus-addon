-- Church's actual filter specs and the shared renderer, with the existing client UI fixture.
local H = ...
local test, eq, ns = H.test, H.eq, H.ns
local World = assert(loadfile(H.ROOT .. "tests/church-world.lua"))(ns, H.ROOT)

local function Filters(w, c)
	for _, line in ipairs(w:As(c, c.View.Build)) do if line.id == "church-filters" then return line.filters end end
	error("Church filter row missing")
end

test("Church dropdown: titleless menu clears the window border and selects the actual filter", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	H.WithUI(function()
		local host = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate")
		host:SetSize(340, 420)
		local scroll = CreateFrame("ScrollFrame", nil, host)
		local row = CreateFrame("Frame", nil, scroll)
		row:SetFrameLevel(host.NineSlice:GetFrameLevel() + 1)
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		local who = row.filters[1]
		who:Click()
		local menu = who.choices
		eq(menu.TitleContainer, nil, "dropdown has no window titlebar")
		eq(menu.CloseButton, nil, "dropdown has no window close button")
		eq(menu:GetParent(), UIParent, "menu is outside ScrollFrame clipping")
		eq(menu:GetFrameStrata(), "DIALOG", "above the main window border")
		eq(menu.catcher:GetFrameStrata(), "DIALOG")
		eq(menu:GetFrameLevel() > menu.catcher:GetFrameLevel(), true)
		eq(menu:GetHeight(), 12 + #Filters(w, c)[1].options * 22, "no titlebar space")
		eq(menu.buttons[1].label:GetText(), c.c.L.CHURCH_LIST_APOSTLES)
		w:As(c, function() menu.buttons[2]:Click() end)
		eq(c.View.list, "m", "actual Church callback updates the selected list")
		eq(menu:IsShown(), false); eq(menu.catcher:IsShown(), false)
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		who:Click(); eq(who.choices, menu, "one reusable popup per filter")
		eq(menu.buttons[2].choice.selected, true)
		menu.catcher:Click(); eq(menu:IsShown(), false)
		who:Click(); row.filters[2]:Click()
		eq(menu:IsShown(), false, "opening When closes Who")
		local when = row.filters[2]
		w:As(c, function() when.choices.buttons[1]:Click() end)
		eq(c.View.window, "w", "actual Church time-window callback")
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		when:Click()
		ns.Views.SetFilter("church", "apostle")
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		eq(when.choices:IsShown(), false, "query redraw closes the stale dropdown")
		eq(when.choices.catcher:IsShown(), false)
		ns.Views.SetFilter("church", "")
		who:Click(); who:Hide()
		eq(menu:IsShown(), false, "hidden page/filter closes its detached menu")
	end)
end)

test("Church dropdown: understated triggers retain Who, When and their active values", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	H.WithUI(function()
		local row = CreateFrame("Frame", nil, UIParent)
		local filters = Filters(w, c)
		ns.Views.DrawFilters(row, filters, 300)
		for i, filter in ipairs(filters) do
			eq(filter.understated, true)
			local b = row.filters[i]
			eq(b.template, nil, "no raised panel-button chrome")
			assert(b.label:GetText():find(filter.label, 1, true), "caption remains visible")
			assert(b.label:GetText():find(filter.value, 1, true), "active value remains visible")
			eq(b.label.font, "GameFontNormalSmall")
			assert(b.label:GetText():find("|cff9d9d9d", 1, true), "caption is understated")
		end
	end)
end)
