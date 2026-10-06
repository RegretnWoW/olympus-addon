-- Conservative file dependencies. Whole monolithic setup/tests and gamepad always stay enabled.
local M = {}
local groups = {
	bones = { "ArenaFarkle.lua", "bones-guide-routing.lua", "bones-hic-reuse.lua", "bones-innkeeper.lua", "bones-invalid-actions.lua", "bones-lesson.lua", "bones-lobby.lua", "bones-start-consent.lua",
		"bones-result-card.lua", "bones-training.lua", "bones-venue.lua", "compliance.lua", "farkle-board.lua",
		"farkle-ledger.lua", "farkle-table.lua", "games-ledger.lua", "house-move-regression.lua",
		"match.lua", "net.lua", "places.lua", "player-ui-polish.lua", "ui-look-wave1.lua" },
	watch = { "compliance.lua", "craft-requests.lua", "markets.lua", "net.lua", "role-chat-audiences.lua",
		"tabards-v2.lua", "ui-look-wave1.lua", "wallet-release.lua" },
}
local files = {
	["Olympus/InnkeeperArrow.lua"] = "bones", ["Olympus/ArenaPlaces.lua"] = "bones",
	["Olympus_Arena/FarkleBoard.lua"] = "bones", ["Olympus_Arena/Games/Farkle.lua"] = "bones",
	["Olympus_Arena/Locales/FarkleText.lua"] = "bones",
	["Olympus/Watch.lua"] = "watch", ["Olympus/WatchChat.lua"] = "watch", ["Olympus/ViewAs.lua"] = "watch",
	["tests/innkeeper-arrow.lua"] = "bones", ["tests/watch-council-view.lua"] = "watch",
}
-- Test-only changes may use their whole mapped dependency group. Shared fixtures/harness fall back.
for group, modules in pairs(groups) do
	for _, name in ipairs(modules) do
		local path = "tests/arena/" .. name
		files[path] = files[path] and "both" or group
	end
end

function M.Select(paths)
	if type(paths) ~= "table" or #paths == 0 then return { full = true, reason = "no changed-file evidence", modules = {} } end
	local selected = {}
	for _, path in ipairs(paths) do
		if type(path) ~= "string" or path == "" or path:find("[\r\n]") or path:find("\\", 1, true)
			or path:sub(1, 1) == "/" or path:find("../", 1, true) then
			return { full = true, reason = "invalid changed path", modules = {} }
		end
		local group = files[path]
		if not group then return { full = true, reason = "unmapped/core path: " .. path, modules = {} } end
		for key, modules in pairs(groups) do
			if group == key or group == "both" then
				for _, name in ipairs(modules) do selected[name] = true end
			end
		end
	end
	local modules = {}
	for name in pairs(selected) do modules[#modules + 1] = name end
	table.sort(modules)
	if #modules == 0 then return { full = true, reason = "empty coverage", modules = {} } end
	return { full = false, reason = "whole mapped modules; main harness and gamepad retained", modules = modules }
end

if ... == "library" then return M end
local paths = {}
for i = 1, #arg do paths[#paths + 1] = arg[i] end
local plan = M.Select(paths)
if not plan.full then
	for _, name in ipairs(plan.modules) do
		local f = io.open("tests/arena/" .. name, "rb")
		if not f then plan = { full = true, reason = "missing dependency module: " .. name, modules = {} }; break end
		f:close()
	end
end
io.write("MODE\t", plan.full and "FULL" or "AFFECTED", "\nREASON\t", plan.reason, "\n")
for _, name in ipairs(plan.modules) do io.write("MODULE\t", name, "\n") end
