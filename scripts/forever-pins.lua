-- The gamepad gate's source pins (1.1.5): each registry entry (Olympus/GamepadRegistry.lua) may cite
-- the lines of Forever's own UI source its reason rests on, in `pins`, as "file:line what is there"
-- (what is there: the line's code, or the name it holds before a colon and a note). This script
-- checks every pin against the client's extracted UI source; a pin that moved or changed means
-- the registry's reason (and the gamepad pass's model of it) must be read again.
--
--   luajit scripts/forever-pins.lua <Interface folder>
--
-- The Interface folder is not in the repository: run this on the author's machine whenever the
-- Forever build changes, before a release, then update ns.GAMEPAD_CHECKED_BUILD in the registry.
-- It changes nothing.

local IFACE = arg and arg[1]
if not IFACE or IFACE == "" then
	io.stderr:write("usage: luajit scripts/forever-pins.lua <Interface folder>\n")
	os.exit(2)
end
IFACE = IFACE:gsub("[/\\]$", "")
local ROOT = (arg[0] or ""):match("^(.*)[/\\]scripts[/\\]forever%-pins%.lua$") or "."
if ROOT == "" then ROOT = "." end

local A = assert(loadfile(ROOT .. "/scripts/gamepad-audit.lua"))("--module")
local list, ns = A.LoadRegistry(ROOT)
if not list then
	io.stderr:write(tostring(ns) .. "\n")
	os.exit(1)
end

local function Lines(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local out = {}
	for line in f:lines() do out[#out + 1] = line end
	f:close()
	return out
end
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local checked, bad = 0, {}
for _, e in ipairs(list) do
	for _, pin in ipairs(type(e.pins) == "table" and e.pins or {}) do
		checked = checked + 1
		local file, line, what = tostring(pin):match("^(%S+%.lua):(%d+)%s+(.+)$")
		if not file then
			bad[#bad + 1] = ("%s: a pin that is not \"file:line what is there\": %s"):format(e.id, tostring(pin))
		else
			-- What must be on the line: the code, or the name before a colon and a note.
			local code = what:match("^([%w_%.]+):%s") or what
			code = Trim(code)
			local lines = Lines(IFACE .. "/AddOns/" .. file)
			if not lines then
				bad[#bad + 1] = ("%s: %s is not in this Interface folder"):format(e.id, file)
			elseif not (lines[tonumber(line)] or ""):find(code, 1, true) then
				local at
				for i, l in ipairs(lines) do if l:find(code, 1, true) then at = i break end end
				bad[#bad + 1] = at and ("%s: %s:%s moved to line %d: %s"):format(e.id, file, line, at, code)
					or ("%s: %s:%s no longer has: %s"):format(e.id, file, line, code)
			end
		end
	end
end
if #bad > 0 then
	for _, b in ipairs(bad) do io.stderr:write(b .. "\n") end
	io.stderr:write(("%d of %d pins no longer match Forever's UI source: read each entry's reason again, fix its pins, then set ns.GAMEPAD_CHECKED_BUILD.\n"):format(#bad, checked))
	os.exit(1)
end
print(("%d pins match Forever's UI source (the registry was checked on build %s)."):format(checked, tostring(ns.GAMEPAD_CHECKED_BUILD)))
