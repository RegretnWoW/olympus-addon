local ADDON, ns = ...

-- 1.1.5: every way Olympus reaches into the game's own UI, in one list (the gamepad gate,
-- Gamepad.lua). Pure data: nothing here runs, so the tests and scripts can read it as it ships.
--
-- Why a list. Each gamepad problem players reported came from Olympus code running inside a
-- part of the game's UI that Blizzard's gamepad code also drives: the game then refuses its own
-- next protected call (SetPreferredGamepadInteractTarget) in Olympus's name, and goes on refusing
-- it until a /reload. Fixing one spot at a time left the next feature free to open another. So
-- every integration with the game's frames, popups, menus, tooltips, chat box, bindings, tables
-- and restricted calls is written down here, with what it does at a login with the gamepad UI on
-- and at each switch between that UI and mouse and keyboard; the code asks ns.Gate.Allowed(id)
-- before it touches anything of the game's, and an id missing from this list is refused.
--
-- The rule: with Blizzard's gamepad UI on, Olympus keeps to its own windows. It registers
-- nothing with the game's UI, puts nothing inside the game's frames, opens none of the game's
-- popups, menus, panels or chat box, writes none of the game's tables or globals, and calls the
-- game's restricted functions only from the player's click on an Olympus button. The entries
-- whose guard is not "gate" are the written exceptions.
--
-- Fields of an entry:
--   id      its name; the code passes it to ns.Gate.Allowed, Gate.Use and Gate.Hooks.
--   kind    what kind of reach it is (a slash command, a button in a game frame, a hook...).
--   files   where its code is (Olympus/).
--   guard   "gate": refused while the gamepad UI is on (checked on every use).
--           "own": only Olympus's own windows and objects, or reads of the game's (allowed).
--           "click": the game's restricted calls, only from the player's click on an Olympus
--             button (allowed; the click is the caller's to check).
--           "exempt": allowed in both modes, for the reason in `why`, with `approved`.
--           "isolated": allowed, the game calling it isolated (securecall), cited in `pins`.
--   toPad   a switch to the gamepad UI: "park" (Olympus's objects on the game's frames hidden,
--           what can be undone undone, next frame), "inert" (registered with the game, cannot
--           be removed, does nothing from its first line), "reload" (stays on the game's side
--           until a /reload: the player is told once), "stays" (nothing to do).
--   toMouse a switch back to mouse and keyboard: "install" (registered or shown again, at most
--           once for what cannot be undone), "on" (used again as it comes), "nothing".
--   safe    "off" or "keep": whether it may stay on once the game blocked Olympus this session
--           (for the safety net that comes after this list).
--   why     the reason, in a sentence.
--   pins    (optional) the lines of Forever's own UI source the reason rests on, to check them
--           again when the client's build changes.
--   globals (optional) the global names it may write, in its own files (the slash commands', a
--           vendored library's own).
--   vendor  (optional) vendored library files (under Olympus/) whose reaches are all this entry's,
--           so the library's code carries no tags.
--
-- Every site in the code is tagged "-- gp:<id>", and scripts/gamepad-audit.lua (in
-- scripts/check.sh) fails on a reach of the game's UI with no tag, a tag with no entry here, an
-- entry tagged nowhere or no test covers, and a global write that is not Olympus's.
--
-- To add an integration: an entry here; "-- gp:<id>" on each site; ns.Gate.Allowed("<id>") before
-- the first touch of the game's UI and as the first line of every function handed to the game;
-- Gate.Hooks("<id>", ...) when it leaves something on the game's side; GP.Covers("<id>") in the
-- gamepad pass (tests/gamepad.lua), with the gamepad UI on and across switches (AGENTS.md).

-- The Forever client build the pins were last checked against (1.60.1).
ns.GAMEPAD_CHECKED_BUILD = 70205

local APPROVED = "the author, 2026-10-04"

ns.GAMEPAD = {
	-- P0: confirmed in Forever's source to reach the refused call in a session played with the gamepad alone.
	{ id = "slash", kind = "slash", files = { "Core.lua", "Channels.lua" },
		globals = { "SLASH_OLYMPUS1", "SLASH_OLYMPUS2", "SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1", "SLASH_OLYMPUSLORDS1" },
		guard = "gate", toPad = "reload", toMouse = "install", safe = "off",
		why = "The chat box calls a slash command's function directly, then closes itself (ClearChat, its focus lost, ClearGamepadFocus) in that function's taint: nothing the function does can prevent it, so none is registered at a gamepad login.",
		pins = { "Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:267 hash_SlashCmdList[command](strtrim(msg), self);",
			"Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:413 self.chatFrame:ClearGamepadFocus();",
			"Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:794 ImportListToHash: the game's hash keeps every command once imported" } },
	{ id = "communities-button", kind = "frame-child", files = { "GuildFrame.lua", "UI.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "The Olympus button in the guild windows (Guild & Communities, the Social window's Guild tab) is a Button the gamepad's Smart Navigation finds and selects, writing its own state in Olympus's taint; the window docked to them reads those frames.",
		pins = { "Blizzard_GamepadSmartNavigation/Utility.lua:208 Utility.FindButtons = function(inFrame, extraPanels, includeInFrame)" } },

	-- P1 and P2: narrower, each through the gate.
	{ id = "tooltip-unit", kind = "tooltip-postcall", files = { "Inspect.lua" },
		guard = "gate", toPad = "inert", toMouse = "install", safe = "off",
		why = "Olympus's lines on a player's tooltip: the gamepad's soft target shows that tooltip again and again, and Olympus writes nothing in the game's frames there." },
	{ id = "error-handler", kind = "global-handler", files = { "Bootstrap.lua", "Diagnostics.lua" },
		guard = "gate", toPad = "park", toMouse = "nothing", safe = "off",
		why = "Every error would pass through Olympus's handler, which opens the game's error window in Olympus's taint; at a switch to the gamepad UI the game's own handler is put back, and never replaced again that session." },
	{ id = "escape-list", kind = "table-write", files = { "Core.lua" },
		guard = "gate", toPad = "park", toMouse = "on", safe = "off",
		why = "The gamepad menus close every window on UISpecialFrames and read it unprotected: Olympus writes no name there, and at a switch takes off its names at the end of the list (a name before another addon's stays until a /reload, so nothing moves)." },
	{ id = "worldmap-icons", kind = "map-pins", files = { "Core.lua", "Map.lua", "Decree.lua", "King.lua", "Positions.lua", "Board.lua" },
		guard = "gate", toPad = "park", toMouse = "on", safe = "off",
		why = "Every icon added or removed goes through the map library into the map's canvas from Olympus's code, and the gamepad map then runs in Olympus's taint: none on the world map, and at a switch every one taken off at once." },
	{ id = "map-overlay", kind = "frame-child", files = { "Map.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "The continent totals, the Olympus button and its menu on the world map, and the hooks on its changes: the gamepad map is the game's alone (the author's call: no continent totals there either)." },
	{ id = "dialogs", kind = "popup", files = { "Core.lua" },
		guard = "gate", toPad = "reload", toMouse = "on", safe = "off",
		why = "A game popup opened from Olympus writes the popups' shared state in Olympus's taint: with the gamepad UI Olympus asks in its own windows (Dialog.lua); one of the game's still up at a switch leaves that state behind until a /reload." },
	{ id = "chat-box", kind = "chat-box", files = { "UI.lua", "Board.lua", "Crafters.lua", "Views.lua" },
		guard = "gate", toPad = "reload", toMouse = "on", safe = "off",
		why = "The game's chat box opened from Olympus (a whisper, a link) keeps Olympus's taint in its last active box, which the gamepad chat reads: with the gamepad UI Olympus's whisper window; used this session, the player is told a /reload clears it." },
	{ id = "issue-reporter", kind = "frame-child", files = { "UI.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "Olympus's Hide button on the game's Issue Reporter (beta clients): with the gamepad UI the game shows that box itself, and Olympus's button there would be a gamepad target." },
	{ id = "who-quiet", kind = "events", files = { "Who.lua" },
		guard = "gate", toPad = "park", toMouse = "on", safe = "off",
		why = "Olympus's quiet /who takes WHO_LIST_UPDATE from the game's who lists and gives it back later; with the gamepad UI none goes, and one pending at a switch gives the event back at once." },
	{ id = "who", kind = "restricted", files = { "Who.lua", "UI.lua" },
		guard = "click", toPad = "stays", toMouse = "nothing", safe = "off",
		why = "A plain /who, only from the player's click on an Olympus button: its answer shows in the game's own who list." },
	{ id = "map-library", kind = "data-provider", files = { "Map.lua" },
		vendor = { "libs/HereBeDragons/HereBeDragons-Pins-2.0.lua" },
		globals = { "HBD_PINS_WORLDMAP_SHOW_PARENT", "HBD_PINS_WORLDMAP_SHOW_CONTINENT", "HBD_PINS_WORLDMAP_SHOW_WORLD" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "HereBeDragons-Pins' world map provider is registered when the library loads, in both modes; Olympus's copy returns at once with no pin to clear under the gamepad UI (Map.QuietPinsProvider)." },
	{ id = "chat-key", kind = "binding", files = { "ChatWindow.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "The Chat tab's override of the Open chat key: never set with the gamepad UI, and the one Olympus holds goes back to the game in the switch itself (the only step taken in the switch's own event), so the gamepad UI rebinds on a clean key." },

	-- P3: already through the gate, or allowed for the reason given.
	{ id = "player-menu", kind = "menu", files = { "PlayerMenu.lua" },
		guard = "gate", toPad = "inert", toMouse = "install", safe = "off",
		why = "Olympus's lines in the game's right-click player menus (Menu.ModifyMenu): the gamepad's player menu runs its interact target state while the menu is built; not registered at a gamepad login, and a callback registered before does nothing." },
	{ id = "borders", kind = "unit-frame-art", files = { "Borders.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "Olympus's border textures and hooks on the target, focus, player and party frames (CheckClassification on TargetFrame/FocusFrame; InitializePartyMemberFrames on PartyFrame, whose member frames get textures)." },
	{ id = "chat-marks", kind = "chat-filter", files = { "Borders.lua" },
		guard = "gate", toPad = "inert", toMouse = "install", safe = "off",
		why = "Olympus's marks before names in the game's chat, through its sender name filter (called isolated); off from its first line under the gamepad UI." },
	{ id = "nameplates", kind = "nameplate-art", files = { "Nameplates.lua" },
		guard = "gate", toPad = "park", toMouse = "install", safe = "off",
		why = "Olympus's mark left of a friendly player's name on his nameplate, and the hook on the game's name updates." },
	{ id = "chat-output", kind = "chat-output", files = { "Core.lua", "Channels.lua", "Treasury.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "Lines printed in the chat windows, as every addon's print: no focus, no filter, no binding." },
	{ id = "chat-channels", kind = "channels", files = { "Comm.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "Olympus's hidden channel joined, left and kept off the chat windows' lists, from timers: on no gamepad path, and Olympus cannot work without it." },
	{ id = "raid-notice", kind = "frame-output", files = { "Core.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "off", approved = APPROVED,
		why = "The alerts in the raid warning frame, which the gamepad UI does not manage." },
	{ id = "minimap", kind = "frame-child", files = { "UI.lua", "Positions.lua", "King.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "The minimap button and pins: Forever's minimap has no gamepad binding group, and it is how gamepad players open Olympus." },
	{ id = "party-invite", kind = "restricted", files = { "Hop.lua" },
		guard = "gate", toPad = "stays", toMouse = "on", safe = "off",
		why = "Accepting a vouched layer invite for the player (AcceptGroup, the game's invite popup): never with the gamepad UI, where the player clicks the game's own invite window." },
	{ id = "mail-trade-fill", kind = "frame-fill", files = { "Dues.lua" },
		guard = "gate", toPad = "stays", toMouse = "on", safe = "off",
		why = "Filling the game's mail and trade windows for the dues: with the gamepad UI a line saying what to send instead." },
	{ id = "roster-actions", kind = "restricted", files = { "Members.lua", "Dues.lua", "Recruit.lua", "UI.lua" },
		guard = "click", toPad = "stays", toMouse = "nothing", safe = "off",
		why = "Invites, whispers sent and guild actions: only from the player's click on an Olympus button." },
	{ id = "inspect-patrol", kind = "inspect", files = { "Inspect.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "off", approved = APPROVED,
		why = "NotifyInspect and ClearInspectPlayer for the tabard patrol: not protected, and no gamepad path reads them." },
	{ id = "mail-hooks", kind = "hook", files = { "Treasury.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "Post-hooks on the mail functions (hooksecurefunc keeps them the game's own) that only read what was sent and taken." },
	{ id = "popup-focus", kind = "focus", files = { "Dialog.lua", "Core.lua" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "Edit boxes of Olympus's own dialogs take the keyboard only through ns.Focus, never from the chat's box under the gamepad UI." },
	{ id = "calendar", kind = "panel", files = { "Week.lua" },
		guard = "gate", toPad = "stays", toMouse = "on", safe = "off",
		why = "Opening the game's calendar for the King's week: with the gamepad UI it only says how to open it." },
	{ id = "photo", kind = "frame-write", files = { "UI.lua" },
		guard = "gate", toPad = "stays", toMouse = "on", safe = "off",
		why = "The author's photo mode hides the game's frames: refused with the gamepad UI." },
	{ id = "lib-partial", kind = "library", files = { "Map.lua" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "A half-loaded map library's own update frame stopped: the library's, not the game's." },
	{ id = "load-worldmap", kind = "load", files = { "Bootstrap.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "keep", approved = APPROVED,
		why = "Loading the world map before the map library on clients where it loads on demand: it does nothing on Forever." },
	{ id = "diagnostics", kind = "reads", files = { "Diagnostics.lua", "Gamepad.lua" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "Reads only (taint probe, stacks), and the notices in Olympus's own windows." },

	-- Found by the audit (scripts/gamepad-audit.lua), registered with it.
	{ id = "lookups", kind = "reads", files = { "Borders.lua", "Channels.lua", "ChatWindow.lua", "Dialog.lua", "GuildFrame.lua", "Treasury.lua", "UI.lua", "Views.lua", "Who.lua", "Workshop.lua" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "Looked up by name and only read: Olympus's own frames' parts, the game's fonts and strings, where the game's popups and main chat tab are (Olympus's own windows go under or point at them), whether the who windows are open, the client's icon lists." },
	{ id = "own-templates", kind = "frame-helper", files = { "UI.lua" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "The who list's column helper (WhoFrameColumn_SetWidth) sizing Olympus's own column headers, made from the game's template in the old guild window's look: nothing of the game's own frames." },
	{ id = "reload-button", kind = "restricted", files = { "Gamepad.lua" },
		guard = "click", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "ReloadUI, from the Reload button of Olympus's own gamepad notice: the player's click." },
	{ id = "hop-group", kind = "restricted", files = { "Hop.lua" },
		guard = "exempt", toPad = "stays", toMouse = "nothing", safe = "off", approved = APPROVED,
		why = "The layer hop's group: the helper's addon invites a vouched guest (InviteUnit) and either side leaves after the hop (LeaveParty), from Olympus's own messages and timers; neither is protected, and the game's group frames follow from its own events." },
	{ id = "lib-stub", kind = "library", files = {}, vendor = { "libs/LibStub/LibStub.lua" }, globals = { "LibStub" },
		guard = "own", toPad = "stays", toMouse = "nothing", safe = "keep",
		why = "LibStub, the libraries' shared registry: it keeps itself in its own global, as in every addon that carries it." },
}
