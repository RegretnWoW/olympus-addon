local ADDON, ns = ...

-- 1.2, the Blood Arena: ChatMarks.lua. A stub the arena's core created for the chat marks part (chat marks) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- The small honour mark before a sender's name in the game's chat (ChatFrameUtil.AddSenderNameFilter)
-- and on Olympus lines (Channels.nameDecorators, the screens); off until in-game check 13 passes.
-- API (the design): Enabled(), MarkFor(name)
local ChatMarks = {}
ns.ChatMarks = ChatMarks

-- A public role badge from this client's pinned identity, never a guild/role label supplied
-- with a message. The primary Treasurer's same realm-group pin is used by ChatRooms; the
-- mail character does not inherit this badge. Honour marks and addon-name dragons stay off.
function ChatMarks.RoleBadge(name)
	local C = ns.Channels
	return C and type(C.RoleBadge) == "function" and C.RoleBadge(name) or ""
end
