local _, own = ...; local ns = own.host; if not ns then return end

-- Fight rooms live as dynamic tabs in the main Olympus Chat page. The Arena companion owns only
-- the presentation entry point: it hands the stable event id to the core, which owns the canonical
-- room specification, audience, lifecycle, recovery and persistence. Keeping this compatibility
-- object means older `/oly arena chat` callers also reach the main Chat page without opening a
-- second or embedded chat surface.
local ArenaUI = own.ArenaUI
local L = ns.L
local Panel = {}
ArenaUI.ChatPanel = Panel

local requested

function ArenaUI.FightChatRoom(id)
	if type(id) ~= "string" or id == "" then return nil end
	local A = ns.Arena
	if type(A) ~= "table" or type(A.ChatRoom) ~= "function" then return nil end
	local ok, spec = pcall(A.ChatRoom, id)
	if ok and type(spec) == "table" and spec.id == id and type(spec.key) == "string" then return spec end
	return nil
end

function ArenaUI.OpenFightChat(id)
	if type(id) ~= "string" or id == "" then requested = nil return false end
	requested = id
	local A = ns.Arena
	if type(A) == "table" and type(A.OpenChatRoom) == "function" then
		local ok, opened, spec = pcall(A.OpenChatRoom, id)
		if ok then
			requested = (opened or type(spec) == "table") and id or nil
			return opened, spec
		end
	end
	requested = nil
	if ArenaUI.Say then ArenaUI.Say(L.ARENA_CHAT_MAIN_UNAVAILABLE or L.ARENA_REFUSE_MISSING) end
	return false, "missing"
end

function Panel.Open(id) return ArenaUI.OpenFightChat(id) end
function Panel.Room() return requested end
function Panel.Close() requested = nil end
function Panel.Frame() return nil end
function Panel.Refresh() return ArenaUI.FightChatRoom(requested) end
function Panel.Docked() end
