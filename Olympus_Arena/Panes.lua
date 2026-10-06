local _, own = ...; local ns = own.host; if not ns then return end

-- The registry the screens are built from (the design): the Bones tables (Farkle) and the screens (everything else), and
-- the Lottery, each register their panes here and never edit each other's files. The window
-- (Window.lua, the screens) reads it.
-- The Arena window has three sections (the design): Arena (duels, Fight Nights, tournaments),
-- Farkle and Lottery, over one wallet. A pane belongs to one of them; staff tabs (the right edge:
-- Arbiter, Bank, Ledgers, Director) belong to none and show only for their roles.
--   ArenaUI.RegisterPane(key, spec)      spec = { section = "arena"|"farkle"|"lottery", label, order,
--                                          build(parent) -> frame (first open only), refresh(frame),
--                                          visible() -> bool }
--   ArenaUI.RegisterStaffTab(key, spec)  spec = { label, icon, order, build(parent), refresh(frame),
--                                          visible() -> bool (the role's own rule) }
--   ArenaUI.Panes(section), ArenaUI.StaffTabs(): the visible ones, in order.
local ArenaUI = own.ArenaUI

ArenaUI.SECTIONS = { "arena", "farkle", "lottery" }
local SECTION = { arena = true, farkle = true, lottery = true }
local panes, staff = {}, {}

local function Valid(spec)
	return type(spec) == "table" and type(spec.label) == "string" and (spec.build == nil or type(spec.build) == "function")
end

function ArenaUI.RegisterPane(key, spec)
	if type(key) ~= "string" or panes[key] or not Valid(spec) or not SECTION[spec.section] then return false end
	panes[key] = { key = key, spec = spec }
	return true
end
function ArenaUI.RegisterStaffTab(key, spec)
	if type(key) ~= "string" or staff[key] or not Valid(spec) then return false end
	staff[key] = { key = key, spec = spec }
	return true
end

local function Shown(e)
	local visible = e.spec.visible
	if type(visible) ~= "function" then return true end
	local ok, yes = pcall(visible)
	return ok and yes == true
end
local function Sorted(list, keep)
	local out = {}
	for _, e in pairs(list) do
		if keep(e) and Shown(e) then out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		local x, y = tonumber(a.spec.order) or 100, tonumber(b.spec.order) or 100
		if x ~= y then return x < y end
		return a.key < b.key
	end)
	return out
end
function ArenaUI.Panes(section)
	return Sorted(panes, function(e) return section == nil or e.spec.section == section end)
end
function ArenaUI.StaffTabs() return Sorted(staff, function() return true end) end
function ArenaUI.Pane(key) return panes[key] and panes[key].spec or nil end
