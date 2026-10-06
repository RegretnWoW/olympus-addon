-- Pure selector selftests: these validate dependency policy, not addon test coverage.
local M = assert(loadfile("scripts/check-affected.lua"))("library")
local function Has(plan, name)
	for _, module in ipairs(plan.modules) do if module == name then return true end end
	return false
end
for _, path in ipairs({ "Olympus/Core.lua", "Olympus/FarkleTable.lua", "Olympus/Olympus.toc",
	"tests/run.lua", "tests/gamepad.lua", "tests/arena/lib/world.lua", "tests/fixtures/forever-api.lua",
	"scripts/check.sh", "Olympus/GamepadRegistry.lua", "Olympus_Arena/LotteryBoard.lua",
	"unknown.lua", "../Olympus/Watch.lua" }) do
	assert(M.Select({ path }).full, "unknown/core changes must never narrow coverage: " .. path)
end
assert(M.Select({}).full)
for _, path in ipairs({ "", "/Olympus/Watch.lua", "Olympus\\Watch.lua", "Olympus/Watch.lua\n",
	"Olympus/Watch.lua\r", "Olympus/../Olympus/Watch.lua", false }) do
	assert(M.Select({ path }).full, "malformed evidence must fall back FULL")
end
assert(M.Select(false).full, "non-list evidence must fall back FULL")
local bones = M.Select({ "Olympus/InnkeeperArrow.lua", "Olympus/ArenaPlaces.lua" })
assert(not bones.full and Has(bones, "farkle-table.lua") and Has(bones, "places.lua") and Has(bones, "match.lua"))
assert(not Has(bones, "lottery-controller.lua"), "unrelated day simulations are omitted")
local watch = M.Select({ "Olympus/Watch.lua", "Olympus/WatchChat.lua", "Olympus/ViewAs.lua" })
assert(not watch.full and Has(watch, "compliance.lua") and Has(watch, "craft-requests.lua") and Has(watch, "net.lua"))
assert(not M.Select({ "tests/innkeeper-arrow.lua", "tests/watch-council-view.lua" }).full)
local both = M.Select({ "Olympus/ArenaPlaces.lua", "Olympus/Watch.lua" })
for _, plan in ipairs({ bones, watch }) do for _, module in ipairs(plan.modules) do assert(Has(both, module)) end end
for i = 2, #both.modules do assert(both.modules[i - 1] < both.modules[i], "sorted, unique union") end
assert(M.Select({ "Olympus/Watch.lua", "Olympus/Core.lua" }).full, "one unknown overrides every narrow mapping")
assert(Has(M.Select({ "tests/arena/net.lua" }), "farkle-table.lua"), "shared mapped fixtures retain both groups")
assert(Has(M.Select({ "tests/arena/net.lua" }), "role-chat-audiences.lua"), "shared mapped fixtures also retain Watch integration")
print("Affected selector policy: passed (no addon test bodies executed)")
