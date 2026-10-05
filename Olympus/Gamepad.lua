local ADDON, ns = ...
local L = ns.L

-- 1.1.5: the gamepad gate. One answer, for every integration GamepadRegistry.lua lists (its rule
-- is written there), to "may Olympus touch the game's UI now?", and what a switch between
-- Blizzard's gamepad UI and mouse and keyboard does with what each one left on the game's side.
--
-- Gate.Allowed(id)   checked on every use, never kept: false for a "gate" entry while the gamepad
--                    UI is on (ns.GamepadUI, the game's own test). An id the list doesn't have is
--                    refused in both modes and reported once, so a new integration can't slip in.
-- Gate.Use(id, fn, ...)  fn(...) where allowed.
-- Gate.Hooks(id, t)  what a feature leaves on the game's side: t.install (registered or shown
--                    again, safe to run twice; what cannot be undone is registered once a
--                    session), t.park (Olympus's own objects on the game's frames hidden, what can
--                    be undone undone), t.leftover (true while something stays until a /reload),
--                    t.now (the Chat tab's key alone: both in the switch's own event), t.key (one
--                    set per file when several files share an id; the same key again replaces it).
-- Gate.Install(id)   id's installs (every id's when nil) where allowed now: each feature's login
--                    calls it, so at a login with the gamepad UI nothing is registered at all.
-- Gate.Used(id)      a use this session that only a /reload undoes (the game's chat box opened
--                    from Olympus): told at a switch to the gamepad UI.
--
-- A switch (INPUT_DEVICE_INTERFACE_TRANSITION: the game sets the new style first, then sends the
-- event at once, inside its own rebinding; its payload newMode, oldMode, InputDocumentation.lua):
-- the handler notes it and leaves the work for the next frame, so nothing of Olympus's runs in the
-- middle of the game's transition, but the Chat tab's key, which goes back to the game in the event
-- itself so the gamepad UI binds on a clean key. Then:
-- - to the gamepad UI: every park (in combat too: they touch only Olympus's objects), then what
--   stays on the game's side until a /reload; if anything does, the player is told once a session,
--   in Olympus's own window (never the game's popup), with a Reload button (his click);
-- - back to mouse and keyboard: every install the gate allows, out of combat.
--
-- Core.lua holds a stand-in until this file loads (and in its place on a client updated without
-- a restart, which loads no new file): what Core.lua registered with it is taken over here.

local Gate = {}
local standIn = ns.Gate
ns.Gate = Gate

local REGISTRY = {}
for _, e in ipairs(type(ns.GAMEPAD) == "table" and ns.GAMEPAD or {}) do
	if type(e) == "table" and type(e.id) == "string" then REGISTRY[e.id] = e end
end
Gate.REGISTRY = REGISTRY

local sets, order = {}, {} -- [id .. "\0" .. key] = { id, t }, in the order registered
local unlisted = {}        -- ids asked that are not in the list
local told = {}            -- of those, the ones reported this session
local used = {}            -- [id] = true: a use this session only a /reload undoes
local switches = {}        -- this session's switches (the last 20): { t, to = "gamepad" | "mouse" }
local queued = false       -- the next frame's work after a switch, waiting
local noticed = false      -- the player told this session
Gate.leftovers = {}        -- at the last switch to the gamepad UI: what stays until a /reload

-- (An unlisted id asked while the files load, before Diagnostics.lua's capture exists, is reported
-- the next time it is asked.)
local function Entry(id)
	local e = REGISTRY[id]
	if e then return e end
	unlisted[tostring(id)] = true
	if not told[id] and ns.CaptureError then
		told[id] = true
		ns.Log("gamepad gate: %s is not in GamepadRegistry.lua, refused", tostring(id))
		ns.CaptureError("gamepad gate", "unlisted integration " .. tostring(id))
	end
	return nil
end
function Gate.Entry(id) return REGISTRY[id] end

function Gate.Allowed(id)
	local e = Entry(id)
	if not e then return false end
	if e.guard == "gate" and ns.GamepadUI() then return false end
	return true
end

function Gate.Use(id, fn, ...)
	if Gate.Allowed(id) then return fn(...) end
end

function Gate.Hooks(id, t)
	if type(id) ~= "string" or type(t) ~= "table" then return end
	Entry(id)
	local key = id .. "\0" .. tostring(t.key or "")
	if not sets[key] then order[#order + 1] = key end
	sets[key] = { id = id, t = t }
end

local function Run(s, field)
	local fn = s.t[field]
	if type(fn) ~= "function" then return nil end
	local res
	local ok = ns.SafeCall("gamepad gate " .. field .. " " .. s.id, function() res = fn() end)
	return ok and res or nil
end

-- (`later`, for Install and Park: not the sets the switch's own event ran already, `now`.)
function Gate.Install(id, later)
	if id ~= nil and not Gate.Allowed(id) then return false end
	for _, key in ipairs(order) do
		local s = sets[key]
		if (id == nil or s.id == id) and not (later and s.t.now) and Gate.Allowed(s.id) then Run(s, "install") end
	end
	return true
end

-- id's parks (every id's when nil).
function Gate.Park(id, later)
	for _, key in ipairs(order) do
		local s = sets[key]
		if (id == nil or s.id == id) and not (later and s.t.now) then Run(s, "park") end
	end
end

function Gate.Used(id)
	if Entry(id) then used[id] = true end
end

-- What stays on the game's side until a /reload, now: the ids, sorted.
function Gate.Leftovers()
	local out, seen = {}, {}
	for _, key in ipairs(order) do
		local s = sets[key]
		if not seen[s.id] and Run(s, "leftover") then
			seen[s.id] = true
			out[#out + 1] = s.id
		end
	end
	for id in pairs(used) do
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

-- The player told, once a session, in Olympus's own dialog window (Dialog.lua, both modes); its
-- Reload button is his click. The chat line where that window can't show.
local NOTICE = "OLYMPUS_GAMEPAD_RELOAD"
if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs[NOTICE] = {
		text = L.GATE_NOTICE, button1 = L.GATE_RELOAD, button2 = L.GATE_CLOSE,
		OnAccept = function() if type(ReloadUI) == "function" then ReloadUI() end end, -- gp:reload-button
		timeout = 0, whileDead = true,
	}
end
local function Notice() -- gp:diagnostics
	if noticed or not ns.GamepadUI() then return end
	noticed = true
	local D = ns.Dialog
	if type(D) == "table" and not D.missing and type(D.Show) == "function" and D.Show(NOTICE) then return end
	ns.Print(L.GATE_NOTICE)
end
function Gate.Noticed() return noticed end

local function Settle()
	queued = false
	if ns.GamepadUI() then
		Gate.Park(nil, true)
		local left = Gate.Leftovers()
		Gate.leftovers = left
		ns.Log("gamepad gate: stepped back for the gamepad UI%s", #left > 0 and ("; until a /reload: " .. table.concat(left, ", ")) or "")
		if #left > 0 and not noticed then ns.OutOfCombat("gamepad gate notice", Notice) end
	else
		Gate.leftovers = {}
		-- (Switched before the login: each feature's own login installs what the gate allows then.)
		if type(IsLoggedIn) == "function" and not IsLoggedIn() then return end
		ns.OutOfCombat("gamepad gate install", function()
			if not ns.GamepadUI() then Gate.Install(nil, true) end
		end)
		ns.Log("gamepad gate: back to mouse and keyboard")
	end
end

-- The style switched to: the event's newMode, as the game sends it (else the game's current one).
local function PadMode(newMode)
	local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
	if newMode ~= nil and gamepad ~= nil then return newMode == gamepad end
	return ns.GamepadUI()
end

function Gate.Switched(newMode)
	local pad = PadMode(newMode)
	switches[#switches + 1] = { t = time and time() or 0, to = pad and "gamepad" or "mouse" }
	while #switches > 20 do table.remove(switches, 1) end
	for _, key in ipairs(order) do
		local s = sets[key]
		if s.t.now then Run(s, pad and "park" or "install") end
	end
	if not queued then
		queued = true
		ns.After(0, "gamepad gate", Settle)
	end
end
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function(newMode) Gate.Switched(newMode) end)

-- For /oly status and bug reports.
function Gate.StatusLine()
	local n = 0
	for _ in pairs(REGISTRY) do n = n + 1 end
	local asked = {}
	for id in pairs(unlisted) do asked[#asked + 1] = id end
	table.sort(asked)
	local last = switches[#switches]
	return ("%d integrations listed (checked on build %s)  |  switches this session: %d%s  |  until a /reload: %s%s"):format(n,
		tostring(ns.GAMEPAD_CHECKED_BUILD), #switches, last and (", last to " .. last.to) or "",
		#Gate.leftovers > 0 and table.concat(Gate.leftovers, ", ") or "nothing",
		#asked > 0 and ("  |  not listed: " .. table.concat(asked, ", ")) or "")
end

function Gate.Reset() -- (tests: this session's state; the hooks stay, each file's own)
	unlisted, told, used, switches, queued, noticed = {}, {}, {}, {}, false, false
	Gate.leftovers = {}
end

-- What Core.lua registered with its stand-in before this file loaded.
if type(standIn) == "table" and standIn.missing and type(standIn.order) == "table" then
	for _, key in ipairs(standIn.order) do
		local s = standIn.sets[key]
		if s then Gate.Hooks(s.id, s.t) end
	end
end
