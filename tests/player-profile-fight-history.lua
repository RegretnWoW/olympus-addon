local ns, test, eq, WithWindow = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]player%-profile%-fight%-history%.lua$") or "./"

local function Fixture(fn)
	local saved = { profile = ns.ArenaProfile, home = ns.ArenaHome, member = ns.IsMember, hides = ns.Moderation.Hides, player = ns.PlayerProfile }
	assert(loadfile(ROOT .. "Olympus/PlayerProfile.lua"))("Olympus", ns)
	local public, calls = {}, {}
	ns.IsMember = function() return true end
	ns.Moderation.Hides = function() return false end
	-- Only the existing Arena provider can authorize another player's history, never the
	-- normal profile's caller-supplied pub/guild/role fields.
	ns.ArenaProfile = { Of = function(full) return public[full] end }
	ns.ArenaHome = { Open = function(where, full) calls[#calls + 1] = { where, full }; return true end }
	local ok, err = pcall(function() fn(public, calls) end)
	ns.ArenaProfile, ns.ArenaHome, ns.IsMember, ns.Moderation.Hides = saved.profile, saved.home, saved.member, saved.hides
	ns.PlayerProfile = saved.player
	if not ok then error(err, 0) end
end

local function HistoryAction(p)
	local lines = ns.PlayerProfile.Build(p)
	for _, row in ipairs(lines) do
		if row.onClick and row.text == "|cffffd200" .. ns.L.PROFILE_ARENA_HISTORY .. "|r" then return row end
	end
end

test("Normal profile fight history: own profile links to the existing Arena history, not a copied list", function()
	WithWindow(function()
		Fixture(function(_, calls)
			local row = assert(HistoryAction({ name = ns.me }), "own history entry")
			eq(#calls, 0, "building a profile loads no companion")
			eq(row.onClick(), true)
			eq(#calls, 1); eq(calls[1][1], "profile"); eq(calls[1][2], ns.me)
		end)
	end)
end)

test("Normal profile fight history: another realm's consent comes only from the Arena provider and is rechecked", function()
	WithWindow(function()
		Fixture(function(public, calls)
			local full = ns.FullName("History Tester", "Faraway")
			local p = { name = "History Tester", realm = "Faraway", pub = true }
			eq(HistoryAction(p), nil, "untrusted display consent grants nothing")
			public[full] = { pub = false }; eq(HistoryAction(p), nil)
			public[full] = { pub = true }
			local row = assert(HistoryAction(p), "consented profile history entry")
			eq(row.onClick(), true); eq(calls[1][2], full, "keep the complete realm identity")
			public[full].pub = false
			eq(row.onClick(), false); eq(#calls, 1, "stale click cannot bypass revoked consent")
		end)
	end)
end)

test("Normal profile fight history: hidden, nonmember and unavailable routes fail closed", function()
	WithWindow(function()
		Fixture(function(public, calls)
			local full = ns.FullName("History Tester")
			public[full] = { pub = true }
			ns.Moderation.Hides = function() return true end
			eq(HistoryAction({ name = full }), nil)
			eq(ns.PlayerProfile.OpenFightHistory(full), false)
			ns.IsMember = function() return false end
			eq(HistoryAction({ name = ns.me }), nil)
			eq(ns.PlayerProfile.OpenFightHistory(ns.me), false)
			ns.IsMember = function() return true end
			ns.ArenaHome = nil
			eq(ns.PlayerProfile.OpenFightHistory(ns.me), false)
			eq(#calls, 0)
		end)
	end)
end)
