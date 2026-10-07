-- The gamepad gate's static audit (1.1.5). Every place where Olympus's code reaches into the game's
-- own UI must be registered with the gate (Olympus/GamepadRegistry.lua) and follow its rule; this
-- script fails the check when one is not. It needs no controller and runs on every check.
--
--   luajit scripts/gamepad-audit.lua          the audit: nothing printed but a summary when it passes
--   luajit scripts/gamepad-audit.lua --list   every reach found, with its file, line and ids (review)
--   luajit scripts/gamepad-audit.lua --write-baseline   rewrites scripts/gamepad-baseline.txt
--
-- Nothing of the addon runs: each .lua file under Olympus/ and under the 1.2 companion's folder,
-- Olympus_Arena/ (Olympus's code too, loaded on demand), is compiled (loadfile) and its bytecode
-- read with LuaJIT's jit.util, so comments and strings can't fool it and every line is exact. The
-- one file it runs is the registry, pure data, in an empty environment. (Loaded with the argument
-- "--module" it returns its lists and its scan instead: tests/gamepad.lua sets its traps from them.)
--
-- What counts as reaching the game's UI (each such site needs a "-- gp:<id>" tag):
--   1. writing a global that is not Olympus's (no tag excuses it; the "slash" entry's globals aside);
--   2. reading one of the REACH globals below (registrations, the escape list, popups, the chat
--      box, bindings, panels, the game's frame helpers, restricted calls);
--   3. a member of one of the NAMESPACES below that is not a plain read (one the lists don't know
--      fails as an unknown API, so the lists grow on purpose);
--   4. a method of one of the game's frames (FRAMES, and names that look like one) that is not a
--      plain read; GameTooltip's tooltip lines and DEFAULT_CHAT_FRAME:AddMessage are counted per
--      file instead, against scripts/gamepad-baseline.txt (the count may go down, never up
--      without the baseline changing in the same diff);
--   5. one of the game's frames used as a value (a parent, an anchor's owner, an argument),
--      UIParent aside (the root every window of Olympus's hangs from);
--   6. a dynamic _G[...] read or write, and writing into one of the game's tables.
--
-- Tags. "-- gp:<id>" at the end of the line with the reach, or alone on the line above (it then
-- covers the next statement, up to where its brackets close). Several ids: "-- gp:a,b". A tag on a
-- function's first line covers that function's own body (not the functions written inside it).
-- "<id>!hook": the site runs only from the gate's install or park for that id (Gate.Hooks), which
-- the gate runs only when allowed; its own gate check is waived (the gamepad pass is the proof).
-- "<id>!undo": the site gives back what that id took from the game (an event, a flag), in both
-- modes, the gate's park among its callers; its gate check is waived too (the pass proves that
-- with the gamepad UI on it runs only in the gate's own work at a switch).
--
-- Checks (each failure names the file, the line and what to do):
--   a reach with no tag; a tag whose id the registry lacks; a foreign global write; a "gate" entry's
--   site with no gate check before it in its function (ns.Gate.Allowed/Use, or ns.GamepadUI while
--   the code moves to the gate); an entry whose switch needs Gate.Hooks with no Gate.Hooks("<id>")
--   in its files; an entry tagged nowhere, or in a file its `files` doesn't list (or listing one
--   with no tag); an entry no test covers (GP.Covers("<id>") under tests/, once tests/gamepad.lua,
--   the gamepad pass, exists); malformed entries; and the ratchet.

local MODULE = ... == "--module"
local ju = require("jit.util")
local vmdef = require("jit.vmdef")
local bit = require("bit")

local A = {}

-- Globals whose every read is a reach.
A.REACH = {}
for _, name in ipairs({
	-- registrations with the game's code
	"hooksecurefunc", "Menu", "MenuUtil", "TooltipDataProcessor", "EventRegistry", "seterrorhandler",
	"SlashCmdList", "ChatFrameUtil", "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter",
	-- the escape list and the game's popups
	"UISpecialFrames", "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_FindVisible", "StaticPopup_Visible",
	-- the game's chat box
	"ChatFrame_OpenChat", "ChatFrame_SendTell", "ChatEdit_InsertLink", "ChatEdit_GetActiveWindow",
	"ChatEdit_ActivateChat", "ChatEdit_DeactivateChat", "ChatFrame_RemoveChannel", "ChatFrame_AddChannel",
	-- bindings
	"SetBinding", "SetBindingClick", "SetOverrideBinding", "SetOverrideBindingClick", "ClearOverrideBindings",
	-- panels
	"ShowUIPanel", "HideUIPanel", "CloseAllWindows", "CloseSpecialWindows", "ToggleCalendar", "ToggleWorldMap",
	-- the game's frame helpers
	"RaidNotice_AddMessage", "SendMailRadioButton_OnClick", "MoneyInputFrame_SetCopper", "LoadAddOn", "ReloadUI",
	"Screenshot", "SetCVar", "WhoFrameColumn_SetWidth", "CompactUnitFrame_UpdateName",
	-- the gamepad UI's own state (read only by the diagnostics' taint probe)
	"GamepadSharedUtility", "GamepadMode", "GamepadMainActionBarFrame", "SmartNavigation",
	-- restricted calls
	"SendChatMessage", "DoEmote", "RandomRoll", "InviteUnit", "LeaveParty", "AcceptGroup", "GuildInvite",
	"GuildUninvite", "NotifyInspect", "ClearInspectPlayer", "JoinChannelByName", "LeaveChannelByName",
	"TargetUnit", "FocusUnit", "InteractUnit", "SetPreferredGamepadInteractTarget", "SendWho", "SetWhoToUI",
	"SetTradeMoney", "SendMail", "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem",
}) do A.REACH[name] = true end

-- The game's namespaces whose members are judged one by one: "read" members are plain reads (no
-- tag); "reach" members need one; a member in neither list fails as unknown.
A.NAMESPACES = {
	C_FriendList = { read = { "GetNumWhoResults", "GetWhoInfo", "IsIgnored", "GetNumIgnores", "GetIgnoreName" },
		reach = { "SendWho", "SetWhoToUi", "AddFriend", "AddIgnore", "DelIgnore", "AddOrDelIgnore" } },
	C_Map = { read = { "GetBestMapForUnit", "GetMapChildrenInfo", "GetMapGroupID", "GetMapGroupMembersInfo", "GetMapInfo",
		"GetUserWaypoint", "CanSetUserWaypointOnMap", "GetAreaInfo",
		"GetMapRectOnMap", "GetMapWorldSize", "GetPlayerMapPosition", "GetWorldPosFromMapPos", "GetMapPosFromWorldPos" },
		reach = { "SetUserWaypoint", "ClearUserWaypoint" } },
	C_SuperTrack = { read = {}, reach = { "SetSuperTrackedUserWaypoint" } },
	C_TradeInfo = { read = {}, reach = { "SetTradeMoney" } },
	C_PartyInfo = { read = { "IsPartyFull" }, reach = { "InviteUnit", "LeaveParty", "ConvertToRaid", "ConfirmInviteUnit" } },
	C_GuildInfo = { read = { "AreGuildEventsEnabled", "GuildRoster", "CanEditOfficerNote", "CanViewOfficerNote" },
		reach = { "Invite", "Uninvite", "Promote", "Demote", "SetNote" } },
	C_ChatInfo = { read = { "InChatMessagingLockdown", "RegisterAddonMessagePrefix", "IsAddonMessagePrefixRegistered",
		"SendAddonMessage", "SendAddonMessageLogged", "GetChannelInfoFromIdentifier", "GetChannelRosterInfo", "GetNumActiveChannels" },
		reach = { "SwapChatChannelsByChannelIndex", "SendChatMessage" } },
	C_AddOns = { read = { "IsAddOnLoaded", "GetAddOnMetadata", "GetAddOnInfo" }, reach = { "LoadAddOn" } },
	C_CVar = { read = { "GetCVar", "GetCVarBool" }, reach = { "SetCVar" } },
	C_InputInterfaceStyle = { read = { "GetCurrentStyle" }, reach = {} },
	C_NamePlate = { read = { "GetNamePlateForUnit", "GetNamePlates" }, reach = {} },
	C_Calendar = { read = { "GetGuildEventInfo", "GetNumGuildEvents", "OpenCalendar" }, reach = { "AddEvent", "CreateGuildSignUpEvent" } },
}
for _, ns in pairs(A.NAMESPACES) do
	local read, reach = {}, {}
	for _, k in ipairs(ns.read) do read[k] = true end
	for _, k in ipairs(ns.reach) do reach[k] = true end
	ns.read, ns.reach = read, reach
end

-- The game's frames (and objects like them): any method but a plain read needs a tag, and so does
-- using one as a value. Names the patterns below match count too.
A.FRAMES = {}
for _, name in ipairs({
	"WorldMapFrame", "Minimap", "CommunitiesFrame", "GuildFrame", "FriendsFrame", "LFGWhoListFrame", "WhoFrame",
	"GameTooltip", "TargetFrame", "TargetFrameContainer", "FocusFrame", "PlayerFrame", "PlayerFrameContainer",
	"DEFAULT_CHAT_FRAME", "SELECTED_CHAT_FRAME", "RaidWarningFrame", "TradeFrame", "PTR_IssueReporter", "InspectFrame",
	"ScriptErrorsFrame", "UIParent", "MailFrame", "CalendarFrame", "ClassicUIForeverGuildPanel", "GameMenuFrame",
	"NamePlateDriverFrame", "LAST_ACTIVE_CHAT_EDIT_BOX", "ACTIVE_CHAT_EDIT_BOX",
}) do A.FRAMES[name] = true end
A.FRAME_PATTERNS = { "^ChatFrame%d+", "^SendMail", "^PTR_", "^StaticPopup%d", "^GameTooltip", "^WorldMap", "Frame$" }
A.NOT_FRAMES = { CreateFrame = true }
function A.IsFrame(name)
	if type(name) ~= "string" or A.NOT_FRAMES[name] or A.Own(name) then return false end
	if A.FRAMES[name] then return true end
	for _, p in ipairs(A.FRAME_PATTERNS) do if name:find(p) then return true end end
	return false
end

-- A frame's methods that only read it.
A.READS = {}
for _, m in ipairs({
	"IsShown", "IsVisible", "GetName", "IsOwned", "GetOwner", "GetWidth", "GetHeight", "GetSize", "GetEffectiveScale",
	"GetScale", "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect", "GetObjectType", "IsObjectType",
	"GetParent", "GetFrameLevel", "GetFrameStrata", "IsMouseOver", "GetNumPoints", "GetPoint", "IsForbidden",
	"IsProtected", "GetMapID", "GetNumChildren", "GetText", "GetAlpha", "IsEventRegistered", "GetCanvas",
	"GetCanvasScale", "GetNormalizedCursorPosition", "GetScript", "HasScript", "GetUnit", "NumLines", "GetID",
}) do A.READS[m] = true end

-- Counted per file against the baseline instead of tagged: Olympus's own tooltips (its frames'
-- OnEnter and OnLeave) and its lines printed in the chat window.
A.RATCHET = {
	GameTooltip = { kind = "tooltip", methods = { SetOwner = true, AddLine = true, AddDoubleLine = true, SetText = true,
		Show = true, Hide = true, ClearLines = true, AddTexture = true, SetMinimumWidth = true, SetPadding = true,
		SetHyperlink = true, SetItemByID = true } },
	DEFAULT_CHAT_FRAME = { kind = "print", methods = { AddMessage = true } },
}

-- Olympus's own globals.
function A.Own(name)
	return type(name) == "string" and (name:find("^Olympus") or name:find("^SLASH_OLYMPUS") or name:find("^BINDING_.*OLYMPUS")) and true or false
end

-- (GetCurrentStyle: the game's own test of its style, which ns.GamepadUI and Bootstrap.lua's own make.)
local GATE_READS = { Allowed = true, Use = true, GamepadUI = true, GetCurrentStyle = true }
-- Lua's own functions that only look at a value: a frame passed to one is not used.
local LOOKS = { type = true, rawget = true, tostring = true, rawequal = true, select = true, assert = true, ipairs = true,
	pairs = true, next = true }
local HOOK_FIELDS = { install = true, park = true, leftover = true }
-- Functions that call a function handed to them at once: a function written inline there runs in
-- its writer's place (its gate check counts).
local RUNS_NOW = { pcall = true, xpcall = true, SafeCall = true }

local function OpName(op) return (vmdef.bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", "")) end
local OP = {}
for i = 0, 200 do
	local n = OpName(i)
	if n == "" then break end
	OP[i] = n
end

-- Where a call's arguments start: 2 slots after its function on 64-bit builds (LuaJIT's two-slot
-- frames), 1 elsewhere. Read from a probe, so the audit reads any LuaJIT 2.1 build alike.
local ARG = 2
do
	local f = loadstring("local o; o:m()")
	local i = 1
	while true do
		local ins = ju.funcbc(f, i)
		if not ins then break end
		if OP[bit.band(ins, 0xff)] == "TGETS" then
			local before = ju.funcbc(f, i - 1)
			if before and OP[bit.band(before, 0xff)] == "MOV" then
				ARG = bit.band(bit.rshift(before, 8), 0xff) - bit.band(bit.rshift(ins, 8), 0xff)
			end
			break
		end
		i = i + 1
	end
end

-- Ops whose A operand is not a register they write (so a value kept there survives them).
local A_NOT_DEST = { TSETS = true, TSETV = true, TSETB = true, TSETM = true, GSET = true, USETV = true, USETS = true,
	USETN = true, USETP = true, ISLT = true, ISGE = true, ISLE = true, ISGT = true, ISEQV = true, ISNEV = true, ISEQS = true,
	ISNES = true, ISEQN = true, ISNEN = true, ISEQP = true, ISNEP = true, IST = true, ISF = true, RET = true, RET0 = true,
	RET1 = true, RETM = true, JMP = true, LOOP = true, FORL = true, ITERL = true, IFORL = true, JFORL = true,
	JITERL = true, UCLO = true, ISTYPE = true, ISNUM = true }

---------------------------------------------------------------------------
-- Scanning one compiled file: its sites (reaches), writes, gate reads, Gate.Hooks ids.
---------------------------------------------------------------------------

-- One prototype's walk. `out` collects: sites { line, pc, proto, what, kind, ratchet }, gsets, hooks.
local function Walk(proto, out)
	local info = ju.funcinfo(proto)
	local p = { line = info.linedefined, last = info.lastlinedefined, gate = {}, gated = false }
	out.protos[#out.protos + 1] = p
	out.protoOf[proto] = p
	local reg = {} -- [register] = { g = name } | { ns = name } | { str = s } | { method = k, obj = desc } | { fn = proto }
	local children = {}
	local prev
	-- Where jumps land: "x and f(x) or nil" ends on a nil written at a jump's target, which is the
	-- other path's value; the frame the first path found is kept.
	local targets = {}
	do
		local q = 1
		while true do
			local ins = ju.funcbc(proto, q)
			if not ins then break end
			local name = OP[bit.band(ins, 0xff)]
			if name == "JMP" or name == "UCLO" or name == "ISNEXT" or name == "FORI" or name == "FORL" or name == "ITERL" or name == "LOOP" then
				targets[q + 1 + bit.rshift(ins, 16) - 0x8000] = true
			end
			q = q + 1
		end
	end
	local function Site(pc, what, kind, ratchet)
		out.sites[#out.sites + 1] = { line = ju.funcinfo(proto, pc).currentline, pc = pc, proto = p, what = what, kind = kind, ratchet = ratchet }
	end
	local function Gate(pc) p.gate[#p.gate + 1] = pc; out.gateProto[proto] = true end
	local function Const(d) return ju.funck(proto, -d - 1) end
	-- What a global read means.
	local function Global(pc, name, dst)
		if A.REACH[name] then Site(pc, name, "reach") end
		if A.NAMESPACES[name] then
			reg[dst] = { ns = name }
		elseif name == "_G" then
			reg[dst] = { g = "_G" }
		elseif A.IsFrame(name) then
			reg[dst] = { g = name, frame = true }
		else
			reg[dst] = { g = name }
		end
	end
	local pc = 1
	while true do
		local ins = ju.funcbc(proto, pc)
		if not ins then break end
		local op = OP[bit.band(ins, 0xff)]
		local a = bit.band(bit.rshift(ins, 8), 0xff)
		local c = bit.band(bit.rshift(ins, 16), 0xff)
		local b = bit.rshift(ins, 24)
		local d = bit.rshift(ins, 16)
		local nextReg
		-- A constant key kept in a register (a function with more strings than TGETS can name, or
		-- t["key"]) is that key: TGETV and TSETV are then judged as TGETS and TSETS.
		local kreg = (op == "TGETV" or op == "TSETV") and reg[c] and reg[c].str
		if kreg then op = op == "TGETV" and "TGETS" or "TSETS" end
		local function Key() if kreg then return kreg end return Const(c) end
		if op == "GGET" then
			local name = Const(d)
			Global(pc, name, a)
			nextReg = reg[a]
		elseif op == "GSET" then
			local name = Const(d)
			if not A.Own(name) then out.gsets[#out.gsets + 1] = { line = ju.funcinfo(proto, pc).currentline, name = name } end
			-- (a string kept in a register stays: GSET doesn't write its A)
		elseif op == "KSTR" then
			nextReg = { str = Const(d) }
		elseif op == "MOV" then
			nextReg = reg[d]
		elseif op == "UGET" then
			local uv = ju.funcuvname(proto, d)
			if uv and GATE_READS[uv] then Gate(pc) end
			nextReg = uv and { upfn = uv } or nil
		elseif op == "FNEW" then
			-- (Walked now, so whether it checks the gate is known where this function calls it.)
			local child = Const(d)
			nextReg = { fn = child }
			children[#children + 1] = child
			Walk(child, out)
		elseif op == "TGETS" then
			local key = Key()
			local base = reg[b]
			if type(key) == "string" and GATE_READS[key] then Gate(pc) end
			local method = prev and prev.op == "MOV" and prev.a == a + ARG and prev.d == b
			if base and base.g == "_G" then
				-- _G.Name: judged as the global Name.
				Global(pc, key, a)
				nextReg = reg[a]
			elseif base and base.ns then
				local ns = A.NAMESPACES[base.ns]
				local full = base.ns .. "." .. tostring(key)
				if ns.reach[key] then
					Site(pc, full, "reach")
				elseif not ns.read[key] then
					Site(pc, full, "unknown")
				end
				nextReg = { g = full }
			elseif base and base.frame then
				local r = A.RATCHET[base.g]
				if method and r and r.methods[key] then
					Site(pc, base.g .. ":" .. key, "ratchet", r.kind)
				elseif method and not A.READS[key] then
					Site(pc, base.g .. ":" .. key, "reach")
				end
				if method then
					nextReg = { method = key, obj = base }
				else
					nextReg = { g = base.g .. "." .. tostring(key), frame = true, field = key, of = base.g }
				end
			elseif base and base.g == "StaticPopupDialogs" then
				nextReg = { g = "StaticPopupDialogs." .. tostring(key) }
			else
				if key == "Hooks" then nextReg = { hooks = true }
				elseif method then nextReg = { method = key, obj = base }
				else nextReg = { key = key } end
			end
		elseif op == "TGETV" then
			local base = reg[b]
			if base and base.g == "_G" then
				-- A name made at run time: the read is the site (what it finds is not followed).
				Site(pc, "_G[...]", "reach")
				nextReg = { g = "_G[...]", dyn = true }
			elseif base and base.frame then
				nextReg = { g = base.g .. "[...]", frame = true }
			end
		elseif op == "TSETS" or op == "TSETV" or op == "TSETB" then
			local base = reg[b]
			if base and base.g == "_G" then
				if op == "TSETS" then
					local name = Key()
					if not A.Own(name) then out.gsets[#out.gsets + 1] = { line = ju.funcinfo(proto, pc).currentline, name = name } end
				else
					Site(pc, "_G[...] =", "reach")
				end
			elseif base and base.g and not base.ns and base.g ~= "StaticPopupDialogs" and not A.Own(base.g)
				and not base.g:find("^StaticPopupDialogs%.") and (A.REACH[base.g] or base.frame) then
				Site(pc, base.g .. (op == "TSETS" and ("." .. tostring(Key())) or "[...]") .. " =", "reach")
			elseif base and base.g == "StaticPopupDialogs" then
				local key = op == "TSETS" and Key() or nil
				if not (type(key) == "string" and key:find("^OLYMPUS_")) then Site(pc, "StaticPopupDialogs[...] =", "reach") end
			end
			-- The table a Gate.Hooks call gets: its install and park functions are the gate's.
			if op == "TSETS" and HOOK_FIELDS[Key()] and reg[a] and reg[a].fn then
				out.hookFns[reg[a].fn] = true
			end
		elseif op == "CALL" or op == "CALLM" or op == "CALLT" or op == "CALLMT" then
			local fnReg = reg[a]
			local nargs = (op == "CALL" or op == "CALLT") and (c - 1) or nil
			-- A local function that checks the gate itself, called here: a gate check.
			if fnReg and fnReg.fn and out.gateProto[fnReg.fn] then Gate(pc) end
			-- Calls of this file's local functions (by name, or by the register their writer keeps).
			if fnReg and (fnReg.upfn or fnReg.fn) then
				out.calls[#out.calls + 1] = { caller = p, pc = pc, name = fnReg.upfn, fn = fnReg.fn }
			end
			-- pcall(function() ... end): that function runs here, after this one's gate checks so far.
			local callee = fnReg and (fnReg.g or fnReg.key)
			if callee and RUNS_NOW[callee] then
				for r = a + ARG, a + ARG + 4 do
					if reg[r] and reg[r].fn then out.inline[reg[r].fn] = { parent = p, pc = pc } end
					-- (a local function by name: a call of it, here)
					if reg[r] and reg[r].upfn then out.calls[#out.calls + 1] = { caller = p, pc = pc, name = reg[r].upfn } end
				end
			end
			-- Gate.Hooks("<id>", ...): the id it registers.
			if fnReg and fnReg.hooks then
				local first = reg[a + ARG]
				if first and first.str then out.hooks[first.str] = true end
			end
			-- One of the game's frames as an argument (not the self of its own method). Lua's own
			-- looks (type, rawget...) don't use it; pcall(Frame.Method, Frame, ...) is that method;
			-- GameTooltip and the chat window handed to Olympus's code to fill count in the ratchet.
			local from, to = a + ARG, nargs and (a + ARG - 1 + nargs) or (a + ARG + 255)
			local looks = fnReg and fnReg.g and LOOKS[fnReg.g]
			local result
			if fnReg and fnReg.g == "rawget" and reg[a + ARG] and reg[a + ARG].frame and reg[a + ARG + 1] and reg[a + ARG + 1].str then
				result = { g = reg[a + ARG].g .. "." .. reg[a + ARG + 1].str, frame = true }
			end
			-- rawget(_G, "Name"): the global Name, read.
			local rawName = fnReg and fnReg.g == "rawget" and reg[a + ARG] and reg[a + ARG].g == "_G" and reg[a + ARG + 1] and reg[a + ARG + 1].str
			local viaPcall = fnReg and fnReg.g == "pcall" and reg[a + ARG] and reg[a + ARG].field and reg[a + ARG + 1] and reg[a + ARG + 1].frame
				and reg[a + ARG].of == reg[a + ARG + 1].g
			if viaPcall then
				local obj, key = reg[a + ARG + 1].g, reg[a + ARG].field
				local r = A.RATCHET[obj]
				if r and r.methods[key] then
					Site(pc, obj .. ":" .. key, "ratchet", r.kind)
				elseif not A.READS[key] then
					Site(pc, obj .. ":" .. key, "reach")
				end
			elseif not looks then
				for r = from, math.min(to, a + ARG + 20) do
					local v = reg[r]
					if v and v.frame and not (r == a + ARG and fnReg and fnReg.method) and v.g ~= "UIParent" then
						local rr = A.RATCHET[v.g]
						if rr then Site(pc, v.g .. " handed to fill", "ratchet", rr.kind)
						else Site(pc, v.g .. " as a value", "reach") end
					end
				end
			end
			nextReg = result
			if rawName then
				for r = a + 1, a + 40 do reg[r] = nil end
				Global(pc, rawName, a)
				nextReg = reg[a]
			end
		elseif op == "TSETM" then
			nextReg = nil
		end
		-- One of the game's frames returned: whoever called gets it (a value too).
		if op == "RET1" or op == "RET" then
			local n = op == "RET1" and 1 or (d - 1)
			for r = a, a + math.max(0, n - 1) do
				local v = reg[r]
				if v and v.frame and v.g ~= "UIParent" then Site(pc, v.g .. " returned", "reach") end
			end
		end
		-- One of the game's frames kept in a table field, a global or an upvalue: a value too.
		if (op == "TSETS" or op == "TSETV" or op == "TSETB" or op == "GSET" or op == "USETV") then
			local v
			if op == "USETV" then v = reg[d] else v = reg[a] end
			if v and v.frame and v.g ~= "UIParent" then Site(pc, v.g .. " as a value", "reach") end
		end
		if op == "KPRI" and targets[pc] and reg[a] and reg[a].frame then nextReg = reg[a] end
		if not A_NOT_DEST[op] then reg[a] = nextReg end
		-- CALL writes its results from A on; everything above it is gone.
		if op == "CALL" or op == "CALLM" then
			for r = a + 1, a + 40 do reg[r] = nil end
		end
		prev = { op = op, a = a, b = b, c = c, d = d }
		pc = pc + 1
	end
	out.childrenOf[p] = children
	return p
end

-- Tags in a file's source: [line] = { ids = {...}, hook = { [id] = true } }.
local function Tags(source)
	local lines, tags = {}, {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
	local function Parse(text)
		local comment = text:match("%-%-(.*)$")
		if not comment then return nil end
		local spec = comment:match("gp:([%w%-!,]+)")
		if not spec then return nil end
		local t = { ids = {}, hook = {} }
		for item in spec:gmatch("[^,]+") do
			local id, suffix = item:match("^([%w%-]+)(!?%w*)$")
			if id and (suffix == "" or suffix == "!hook" or suffix == "!undo") then
				t.ids[#t.ids + 1] = id
				if suffix ~= "" then t.hook[id] = true end
			else
				t.bad = item
			end
		end
		return t
	end
	local function Merge(at, t)
		local cur = tags[at]
		if not cur then tags[at] = { ids = {}, hook = {}, bad = t.bad, from = t.from } cur = tags[at] end
		for _, id in ipairs(t.ids) do cur.ids[#cur.ids + 1] = id end
		for id in pairs(t.hook) do cur.hook[id] = true end
	end
	local function Depth(text)
		local code = text:gsub("%-%-.*$", ""):gsub('"[^"]*"', ""):gsub("'[^']*'", "")
		local _, o = code:gsub("[%(%{%[]", "")
		local _, cl = code:gsub("[%)%}%]]", "")
		return o - cl
	end
	for i, text in ipairs(lines) do
		local t = Parse(text)
		if t then
			t.from = i
			Merge(i, t)
			-- Alone on its line: the next statement too, up to where its brackets close.
			if text:match("^%s*%-%-") then
				local j = i + 1
				while lines[j] and (lines[j]:match("^%s*$") or lines[j]:match("^%s*%-%-")) do j = j + 1 end
				local depth = 0
				while lines[j] do
					Merge(j, t)
					depth = depth + Depth(lines[j])
					if depth <= 0 then break end
					j = j + 1
				end
			end
		end
	end
	return tags, lines
end

-- Every .lua file under dir, sorted (relative paths, forward slashes).
local function LuaFiles(root, dir)
	local out = {}
	local p = io.popen('cd "' .. root .. '" && find "' .. dir .. '" -type f -name "*.lua" 2>/dev/null')
	if p then
		for line in p:lines() do out[#out + 1] = (line:gsub("^%./", "")) end
		p:close()
	end
	table.sort(out)
	return out
end

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- The scan of one file: its sites, each with the tag covering it.
function A.ScanFile(root, rel)
	local path = root .. "/" .. rel
	local chunk, err = loadfile(path)
	if not chunk then return nil, err end
	local out = { sites = {}, gsets = {}, hooks = {}, protos = {}, gateProto = {}, hookFns = {}, childrenOf = {}, protoOf = {}, inline = {}, calls = {} }
	Walk(chunk, out)
	local tags, lines = Tags(Read(path) or "")
	-- This file's local functions by name ("local function Name(" on their first line).
	local named, nameCount = {}, {}
	for fn, p in pairs(out.protoOf) do
		local text = lines[p.line] or ""
		local name = text:match("^%s*local%s+function%s+([%w_]+)%s*%(") or text:match("^%s*function%s+([%w_]+)%s*%(")
		if name and p.line > 0 then
			p.name = name
			nameCount[name] = (nameCount[name] or 0) + 1
			named[name] = p
		end
	end
	local callsOf = {}
	for _, c in ipairs(out.calls) do
		local target = c.fn and out.protoOf[c.fn] or (c.name and nameCount[c.name] == 1 and named[c.name])
		if target then
			callsOf[target] = callsOf[target] or {}
			table.insert(callsOf[target], c)
		end
	end
	local hookProto, inlineOf = {}, {}
	for fn in pairs(out.hookFns) do if out.protoOf[fn] then hookProto[out.protoOf[fn]] = true end end
	for fn, at in pairs(out.inline) do if out.protoOf[fn] then inlineOf[out.protoOf[fn]] = at end end
	-- Local functions that check the gate (themselves, or by calling one that does): calling one
	-- is a gate check where the call is.
	local gateFn = {}
	for _, p in pairs(out.protoOf) do if #p.gate > 0 then gateFn[p] = true end end
	local function Target(c) return c.fn and out.protoOf[c.fn] or (c.name and nameCount[c.name] == 1 and named[c.name]) or nil end
	local changed = true
	while changed do
		changed = false
		for _, c in ipairs(out.calls) do
			local t = Target(c)
			if t and gateFn[t] and not gateFn[c.caller] then gateFn[c.caller], changed = true, true end
		end
	end
	local gateCalls = {} -- [proto] = { pc, ... }: its calls of a function that checks the gate
	for _, c in ipairs(out.calls) do
		local t = Target(c)
		if t and gateFn[t] then
			gateCalls[c.caller] = gateCalls[c.caller] or {}
			table.insert(gateCalls[c.caller], c.pc)
		end
	end
	local GatedFrom
	local function GateBefore(p, pc, seen)
		for _, gpc in ipairs(p.gate) do if gpc < pc then return true end end
		for _, gpc in ipairs(gateCalls[p] or {}) do if gpc < pc then return true end end
		if hookProto[p] then return true end
		local at = inlineOf[p]
		if at then return GateBefore(at.parent, at.pc, seen) end
		return GatedFrom(p, seen)
	end
	-- A local function of this file called only after a gate check (or from the gate's hooks), at
	-- every one of its calls in this file: its sites are behind the gate too.
	GatedFrom = function(p, seen)
		local calls = callsOf[p]
		if not calls or #calls == 0 or not p.name or nameCount[p.name] ~= 1 then return false end
		seen = seen or {}
		if seen[p] then return false end
		seen[p] = true -- (the functions on the way here: a call cycle proves nothing)
		local all = true
		for _, c in ipairs(calls) do
			if not GateBefore(c.caller, c.pc, seen) then all = false break end
		end
		seen[p] = nil
		return all
	end
	for _, s in ipairs(out.sites) do
		-- The tag on the site's line, else on its function's first line.
		local t = tags[s.line] or tags[s.proto.line]
		s.tag = t
		s.inHook = hookProto[s.proto] or (inlineOf[s.proto] and hookProto[inlineOf[s.proto].parent]) or false
		s.gateBefore = GateBefore(s.proto, s.pc)
	end
	return { rel = rel, sites = out.sites, gsets = out.gsets, hooks = out.hooks, tags = tags, lines = lines }
end

-- The registry, run in an empty environment (it is pure data).
function A.LoadRegistry(root)
	local path = root .. "/Olympus/GamepadRegistry.lua"
	local chunk, err = loadfile(path)
	if not chunk then return nil, "cannot read Olympus/GamepadRegistry.lua: " .. tostring(err) end
	setfenv(chunk, {})
	local ns = {}
	local ok, e = pcall(chunk, "Olympus", ns)
	if not ok then return nil, "Olympus/GamepadRegistry.lua failed: " .. tostring(e) end
	if type(ns.GAMEPAD) ~= "table" then return nil, "Olympus/GamepadRegistry.lua sets no ns.GAMEPAD list" end
	return ns.GAMEPAD, ns
end

local GUARDS = { gate = true, own = true, click = true, exempt = true, isolated = true }
local TO_PAD = { park = true, remove = true, inert = true, reload = true, stays = true }
local TO_MOUSE = { install = true, on = true, nothing = true }
local SAFE = { off = true, keep = true }

local function ReadBaseline(path)
	local base, found = {}, false
	local s = Read(path)
	if not s then return base, false end
	found = true
	for line in s:gmatch("[^\n]+") do
		local file, kind, n = line:match("^(%S+)%s+(%S+)%s+(%d+)%s*$")
		if file then base[file .. " " .. kind] = tonumber(n) end
	end
	return base, found
end

-- The whole audit: failures (strings), notes, every site, the ratchet counts.
function A.Audit(root)
	local fails, notes = {}, {}
	local function Fail(fmt, ...) fails[#fails + 1] = fmt:format(...) end
	local list, regNs = A.LoadRegistry(root)
	if not list then return { err = regNs } end
	local byId = {}
	for i, e in ipairs(list) do
		local where = ("Olympus/GamepadRegistry.lua: entry %d"):format(i)
		if type(e) ~= "table" or type(e.id) ~= "string" or not e.id:match("^[%w%-]+$") then
			Fail("%s has no id (letters, digits and dashes).", where)
		else
			where = ("Olympus/GamepadRegistry.lua: %s"):format(e.id)
			if byId[e.id] then Fail("%s is listed twice.", where) end
			byId[e.id] = e
			if type(e.kind) ~= "string" or e.kind == "" then Fail("%s has no kind.", where) end
			if not GUARDS[e.guard] then Fail("%s: guard must be gate, own, click, exempt or isolated.", where) end
			if not TO_PAD[e.toPad] then Fail("%s: toPad must be park, remove, inert, reload or stays.", where) end
			if not TO_MOUSE[e.toMouse] then Fail("%s: toMouse must be install, on or nothing.", where) end
			if not SAFE[e.safe] then Fail("%s: safe must be off or keep.", where) end
			if type(e.why) ~= "string" or #e.why < 10 then Fail("%s: say why, in a sentence.", where) end
			if type(e.files) ~= "table" or (#e.files == 0 and not (type(e.vendor) == "table" and #e.vendor > 0)) then
				Fail("%s: list its files (under Olympus/, or Olympus_Arena/... for the companion's; a vendored library's in `vendor`).", where)
			end
			if e.guard == "exempt" and (type(e.approved) ~= "string" or e.approved == "") then
				Fail("%s: an exempt entry needs `approved` (who said yes, and when).", where)
			end
			if e.guard == "isolated" and (type(e.pins) ~= "table" or #e.pins == 0) then
				Fail("%s: an isolated entry needs `pins` (the game's source lines that isolate the call).", where)
			end
		end
	end
	-- A registry file name's path from the repository's root: under Olympus/, or the companion's,
	-- named with its folder in front (Olympus_Arena/...).
	local function Rel(f)
		f = tostring(f)
		if f:find("^Olympus_Arena/") then return f end
		return "Olympus/" .. f
	end
	-- The game's globals an entry may write, and where: [name] = { [file] = true }.
	local mayWrite = {}
	for _, e in pairs(byId) do
		for _, g in ipairs(type(e.globals) == "table" and e.globals or {}) do
			mayWrite[g] = mayWrite[g] or {}
			for _, f in ipairs(type(e.files) == "table" and e.files or {}) do mayWrite[g][Rel(f)] = true end
			for _, f in ipairs(type(e.vendor) == "table" and e.vendor or {}) do mayWrite[g][Rel(f)] = true end
		end
	end

	local files = LuaFiles(root, "Olympus")
	for _, rel in ipairs(LuaFiles(root, "Olympus_Arena")) do files[#files + 1] = rel end
	local all, tagged, taggedIn, hooksIn, counts = {}, {}, {}, {}, {}
	local vendored = {}
	for _, e in pairs(byId) do
		for _, f in ipairs(type(e.vendor) == "table" and e.vendor or {}) do vendored[Rel(f)] = e.id end
	end
	for _, rel in ipairs(files) do
		local scan, err = A.ScanFile(root, rel)
		if not scan then
			Fail("%s: does not compile: %s", rel, tostring(err))
		else
			local short = rel:gsub("^Olympus/", "")
			local vendor = vendored[rel]
			for id in pairs(scan.hooks) do hooksIn[id] = hooksIn[id] or {}; hooksIn[id][short] = true end
			-- Every tag names a listed id.
			for line, t in pairs(scan.tags) do
				if t.from == line then
					if t.bad then Fail("%s:%d: the tag \"gp:%s\" is not an id (letters, digits, dashes; \"!hook\" or \"!undo\" after one).", rel, line, t.bad) end
					for _, id in ipairs(t.ids) do
						if not byId[id] then
							Fail("%s:%d: the tag gp:%s names no entry of Olympus/GamepadRegistry.lua. Add the entry, or fix the id.", rel, line, id)
						else
							tagged[id] = true
							taggedIn[id] = taggedIn[id] or {}
							taggedIn[id][short] = true
						end
					end
				end
			end
			for _, g in ipairs(scan.gsets) do
				if not (mayWrite[g.name] and mayWrite[g.name][rel]) then
					Fail("%s:%d: writes the global %s, which is not Olympus's. Keep it local (or name it Olympus...): Olympus writes none of the game's globals.", rel, g.line, g.name)
				end
			end
			for _, s in ipairs(scan.sites) do
				s.file = rel
				all[#all + 1] = s
				if vendor then
					s.ids = { vendor }
				elseif s.kind == "ratchet" and not s.tag then
					local key = short .. " " .. s.ratchet
					counts[key] = (counts[key] or 0) + 1
				elseif s.kind == "unknown" and not s.tag then
					Fail("%s:%d: %s is an API the audit doesn't know. List it in scripts/gamepad-audit.lua (NAMESPACES) as a read, or as a reach and tag it.", rel, s.line, s.what)
				elseif not s.tag then
					Fail("%s:%d: %s reaches the game's UI without a gp: tag. Register it: add \"-- gp:<id>\" here and an entry in Olympus/GamepadRegistry.lua.", rel, s.line, s.what)
				else
					s.ids = s.tag.ids
					local gate, hook = false, false
					for _, id in ipairs(s.tag.ids) do
						local e = byId[id]
						if e and e.guard == "gate" and not gate then gate = id end
						if s.tag.hook[id] then hook = true end
					end
					if gate and not hook and not s.inHook and not s.gateBefore then
						Fail("%s:%d: %s is gp:%s, a \"gate\" entry, with no gate check before it in its function. Start with: if not ns.Gate.Allowed(\"%s\") then return end (or tag it \"%s!hook\" when only that id's Gate.Hooks runs it).",
							rel, s.line, s.what, gate, gate, gate)
					end
				end
			end
		end
	end
	-- Lists against tags.
	local ids = {}
	for id in pairs(byId) do ids[#ids + 1] = id end
	table.sort(ids)
	local covered = {}
	local tests = LuaFiles(root, "tests")
	local pass = false
	for _, rel in ipairs(tests) do
		if rel == "tests/gamepad.lua" then pass = true end
		local s = Read(root .. "/" .. rel) or ""
		for id in s:gmatch("Covers%(%s*[\"']([%w%-]+)[\"']%s*%)") do covered[id] = true end
	end
	for _, id in ipairs(ids) do
		local e = byId[id]
		local inVendor = false
		for _, f in ipairs(type(e.vendor) == "table" and e.vendor or {}) do inVendor = true end
		if not tagged[id] and not inVendor then
			Fail("Olympus/GamepadRegistry.lua: %s is tagged nowhere (no \"-- gp:%s\" in Olympus/ or Olympus_Arena/). Tag its sites, or remove the entry.", id, id)
		end
		local listed = {}
		for _, f in ipairs(type(e.files) == "table" and e.files or {}) do listed[f] = true end
		for f in pairs(taggedIn[id] or {}) do
			if not listed[f] then Fail("%s: tagged gp:%s, but the entry's files don't list %s. Add it there.", Rel(f), id, f) end
		end
		for f in pairs(listed) do
			if not (taggedIn[id] or {})[f] and not (hooksIn[id] or {})[f] and not inVendor then
				Fail("Olympus/GamepadRegistry.lua: %s lists %s, where nothing is tagged gp:%s. Tag it there, or take the file off.", id, f, id)
			end
		end
		if e.toPad == "park" or e.toPad == "remove" or e.toMouse == "install" then
			local found = false
			for f in pairs(hooksIn[id] or {}) do if listed[f] then found = true end end
			if not found then
				Fail("Olympus/GamepadRegistry.lua: %s says toPad = %s, toMouse = %s, but none of its files calls Gate.Hooks(\"%s\", ...) for the switch.", id, tostring(e.toPad), tostring(e.toMouse), id)
			end
		end
		if pass and not covered[id] then
			Fail("tests: no test covers %s. Add it to the gamepad pass (tests/gamepad.lua) with GP.Covers(\"%s\").", id, id)
		end
	end
	-- The ratchet.
	local baseline, haveBaseline = ReadBaseline(root .. "/scripts/gamepad-baseline.txt")
	local keys = {}
	for k in pairs(counts) do keys[#keys + 1] = k end
	for k in pairs(baseline) do if not counts[k] then keys[#keys + 1] = k end end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local n, max = counts[k] or 0, baseline[k] or 0
		local file, kind = k:match("^(%S+) (%S+)$")
		if n > max then
			Fail("%s: %d %s uses of the game's %s, more than the %d of scripts/gamepad-baseline.txt. Use fewer, or raise its line \"%s %s %d\" in the same change (the review reads it).",
				Rel(file), n, kind, kind == "tooltip" and "GameTooltip" or "chat window", max, file, kind, n)
		elseif n < max then
			notes[#notes + 1] = ("%s: %d %s uses, fewer than the baseline's %d: lower its line to \"%s %s %d\"."):format(Rel(file), n, kind, max, file, kind, n)
		end
	end
	if not haveBaseline and next(counts) then Fail("scripts/gamepad-baseline.txt is missing: luajit scripts/gamepad-audit.lua --write-baseline makes it.") end
	return { fails = fails, notes = notes, sites = all, counts = counts, ids = ids, byId = byId, pass = pass, registry = list }
end

if MODULE then return A end

---------------------------------------------------------------------------
-- The command.
---------------------------------------------------------------------------

local root = (arg and arg[0] or ""):match("^(.*)[/\\]scripts[/\\]gamepad%-audit%.lua$") or "."
if root == "" then root = "." end
local mode = arg and arg[1]
local r = A.Audit(root)
if r.err then
	io.stderr:write("Gamepad audit: " .. r.err .. "\n")
	os.exit(1)
end
if mode == "--write-baseline" then
	local keys = {}
	for k in pairs(r.counts) do keys[#keys + 1] = k end
	table.sort(keys)
	local out = { "# The gamepad audit's ratchet (scripts/gamepad-audit.lua): per file, Olympus's uses of the",
		"# game's GameTooltip (tooltip) and chat window (print) that need no gp: tag. A count may go down;",
		"# raising one is a change the review reads. Format: file kind count." }
	for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. r.counts[k] end
	local f = assert(io.open(root .. "/scripts/gamepad-baseline.txt", "wb"))
	f:write(table.concat(out, "\n") .. "\n")
	f:close()
	print("scripts/gamepad-baseline.txt written: " .. #keys .. " lines")
	os.exit(0)
end
if mode == "--list" then
	table.sort(r.sites, function(x, y) if x.file ~= y.file then return x.file < y.file end return x.line < y.line end)
	for _, s in ipairs(r.sites) do
		print(("%s:%d  %-8s %-48s %s"):format(s.file, s.line, s.kind, s.what, s.ids and table.concat(s.ids, ",") or (s.kind == "ratchet" and s.ratchet or "UNTAGGED")))
	end
end
for _, n in ipairs(r.notes) do print("note: " .. n) end
if #r.fails > 0 then
	table.sort(r.fails)
	for _, f in ipairs(r.fails) do io.stderr:write(f .. "\n") end
	io.stderr:write(("Gamepad audit failed: %d problem%s (scripts/gamepad-audit.lua; how to register an integration: AGENTS.md).\n"):format(#r.fails, #r.fails == 1 and "" or "s"))
	os.exit(1)
end
local n = 0
for _, s in ipairs(r.sites) do if s.ids then n = n + 1 end end
print(("Gamepad audit: %d integrations, %d tagged sites, every one registered."):format(#r.ids, n))
