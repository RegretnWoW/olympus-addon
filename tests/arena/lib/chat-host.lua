-- 1.2: the Chat page as ChatRooms.OpenMatter uses it (the one door every pending conversation opens
-- through): ChatWindow.lua's room and tab calls, each call written down; and ChatRooms.lua loaded
-- into a client as the game loads it, before the Arena's files, for a world that does not load it.
--
--   local CH = assert(loadfile(H.ROOT .. "tests/arena/lib/chat-host.lua"))(H)
--   CH.WithRooms(w, c)
--   local h = CH.Host(c)   -- h.calls: "open" (the page on its Chat tab), "select <room>" (a provider's
--                          -- room), "open <key>" (a dynamic room), "pin <key>", "unpin <key>",
--                          -- "raise" (the Olympus window in front); h.spec: the last dynamic room
--   CH.CombatOver(w, c)    -- the fight's end on that client (what waited for it opens)
local H = ...
local CH = {}

function CH.WithRooms(w, c)
	w:As(c, function() assert(loadfile(H.ADDON_DIR .. "ChatRooms.lua"))("Olympus", c.ns) end)
end

-- (The real calls answer as these do: Open the tab's pane, SelectLogical true, OpenDynamicRoom the
-- pane it shows or false, PinDynamicRoom true for a room it lists.)
function CH.Host(c)
	local h = { calls = {}, rooms = {} }
	local function Note(s) h.calls[#h.calls + 1] = s end
	local window = { Raise = function() Note("raise") end }
	rawset(c.ns, "ChatWindow", {
		Open = function() Note("open") return { pane = c.short } end,
		SelectLogical = function(id) Note("select " .. id) return true end,
		OpenDynamicRoom = function(spec)
			Note("open " .. spec.key)
			h.spec = spec
			h.rooms[spec.key] = h.rooms[spec.key] or {}
			return { room = spec.id }
		end,
		DynamicRoom = function(key) return h.rooms[key] end,
		PinDynamicRoom = function(key, on)
			Note((on and "pin " or "unpin ") .. key)
			if h.rooms[key] then h.rooms[key].pinned = on or nil end
			return h.rooms[key] ~= nil
		end,
		Window = function() return window end,
	})
	return h
end

-- The fight's end on that client: the game's PLAYER_REGEN_ENABLED. Core's own handler for it
-- (ns.RunAfterCombat: what waited with ns.OutOfCombat) is on Core's event frame, registered while
-- Core loads, which this world's Fire (the handlers registered after it) does not reach: it runs
-- here as the event runs it in the game.
function CH.CombatOver(w, c)
	c.combat = false
	w:Fire(c, "PLAYER_REGEN_ENABLED")
	w:As(c, c.ns.RunAfterCombat)
end

return CH
