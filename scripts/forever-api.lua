-- What WoW: Forever's client offers to the addon, as its own UI source shows it: makes
-- tests/fixtures/forever-api.lua, which the gamepad pass (tests/gamepad.lua) checks its stand-ins
-- against. A stand-in may only offer what the client has (a global, a member, an event, a
-- method of a widget or a template, an Enum value), and a call the client restricts behaves as
-- restricted there.
--
--   luajit scripts/forever-api.lua <Interface folder> [build]      writes the fixture
--   luajit scripts/forever-api.lua <Interface folder> --check      says whether it is up to date
--
-- The Interface folder is the client's extracted UI source (Interface/AddOns/Blizzard_*: the
-- generated API documentation, Blizzard's Lua and XML). It is not in the repository: run this on
-- the author's machine whenever the Forever build changes (and whenever the addon or the pass
-- starts reading a name the fixture doesn't list), then commit the fixture.
--
-- What it records, for the names Olympus and the pass use (not the whole client):
--   globals[name]   "api" (a documented function), "namespace" (a documented C_ table), "function",
--                   "table" or "value" (defined in Blizzard's Lua), "frame" or "font" (a named
--                   object in Blizzard's XML), "used" (read by Blizzard's own code and defined
--                   nowhere in its source: the engine's, like strsplit or the global strings),
--                   "seen" (proved in game by Olympus itself, below), or false: nothing in the
--                   client's source has it.
--   members["T.k"]  the same for a member of a table (C_FriendList.SendWho, Menu.ModifyMenu...).
--   restricted[f]   "protected" (IsProtectedFunction) or "restricted" (HasRestrictions).
--   events[e]       true for an event the documentation lists, false for one it doesn't.
--   enums[name]     the Enum tables Olympus reads, with their values.
--   widgets[type]   every method the documentation gives that widget type (its API tables and
--                   the ones it inherits, below), as a sorted, space-separated list.
--   templates[t]    a template Olympus uses: its widget type, its keys (parentKey children and
--                   their types) and its mixins' methods.
-- Files are read for the camelot game type (Forever: WOW_PROJECT_CAMELOT), as its TOCs choose them
-- ([Family] is Mainline, [Game] Camelot; a line for mainline loads too, one excluding camelot
-- doesn't): a file no TOC loads there doesn't count.

local ju = require("jit.util")
local vmdef = require("jit.vmdef")
local bit = require("bit")

local IFACE = arg and arg[1]
if not IFACE or IFACE == "" then
	io.stderr:write("usage: luajit scripts/forever-api.lua <Interface folder> [build|--check]\n")
	os.exit(2)
end
IFACE = IFACE:gsub("[/\\]$", "")
local ROOT = (arg[0] or ""):match("^(.*)[/\\]scripts[/\\]forever%-api%.lua$") or "."
if ROOT == "" then ROOT = "." end
local CHECK = arg[2] == "--check"
local BUILD = tonumber(arg[2]) or 70205
local OUT = ROOT .. "/tests/fixtures/forever-api.lua"

-- Proved in game by Olympus itself, though no line of the client's source shows them (functions
-- of the engine Blizzard's own code doesn't call): each with what proves it.
local SEEN_IN_GAME = {
	JoinChannelByName = "Olympus's census channel is joined with it on Forever since 0.1 (the census fills in game)",
	GetGuildRosterInfo = "Roster.lua reads every member with it, unguarded, and the census counts Forever guilds in game",
	issecurevariable = "the taint probe's line in players' bug reports from Forever names the values it checked (#56)",
}

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local function List(cmd)
	local out = {}
	local p = io.popen(cmd)
	if p then
		for line in p:lines() do out[#out + 1] = line end
		p:close()
	end
	table.sort(out)
	return out
end

local OP = {}
for i = 0, 200 do
	local n = (vmdef.bcnames:sub(i * 6 + 1, i * 6 + 6):gsub("%s+$", ""))
	if n == "" then break end
	OP[i] = n
end

---------------------------------------------------------------------------
-- Which files the client loads (its TOCs, for camelot), and what they define and use.
---------------------------------------------------------------------------

local ADDONS = IFACE .. "/AddOns"
local loaded = {} -- [path] = true
local function Loads(directive)
	if not directive then return true end
	local allow = directive:match("AllowLoadGameType%s+([^%]]+)")
	local exclude = directive:match("ExcludeLoadGameType%s+([^%]]+)")
	if exclude and (exclude:find("camelot") ) then return false end
	-- ([AllowLoad Glue]: the login screens' alone, not the game's.)
	local allowLoad = directive:match("%[AllowLoad%s+(%a+)%]")
	if allowLoad == "Glue" then return false end
	if allow and not (allow:find("camelot") or allow:find("mainline")) then return false end
	return true
end
local function AddXml(path, depth)
	if loaded[path] or depth > 8 then return end
	loaded[path] = true
	local src = Read(path)
	if not src or not path:find("%.xml$") then return end
	local dir = path:match("^(.*)/[^/]*$")
	for tag, file in src:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
		if tag == "Include" or tag == "Script" then
			local p = (dir .. "/" .. file:gsub("\\", "/"))
			AddXml(p, depth + 1)
		end
	end
end
for _, toc in ipairs(List('find "' .. ADDONS .. '" -name "*.toc"')) do
	local dir = toc:match("^(.*)/[^/]*$")
	for raw in (Read(toc) or ""):gmatch("[^\r\n]+") do
		local line = raw:match("^%s*(.-)%s*$")
		if line ~= "" and not line:find("^#") then
			-- Its directives, the trailing [...] parts ([AllowLoadGameType ...], [AllowLoadEnvironment ...]).
			local file, directive = line, ""
			while true do
				local rest, d = file:match("^(.-)%s*(%[%a+Load[^%]]*%])$")
				if not rest then break end
				file, directive = rest, directive .. d
			end
			if Loads(directive ~= "" and directive or nil) then
				file = file:gsub("%[Family%]", "Mainline"):gsub("%[Game%]", "Camelot"):gsub("\\", "/")
				AddXml(dir .. "/" .. file, 0)
			end
		end
	end
end

local defined, used, members, methodsOn, aliases = {}, {}, {}, {}, {}
-- (Returns the members of tables this function reads: what a wrapper defined in Lua calls, so a
-- deprecated global that wraps a restricted function is restricted too.)
local function WalkLua(proto)
	local reg = {}
	local reads = {}
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
		if op == "GGET" then
			local k = ju.funck(proto, -d - 1)
			used[k] = true
			nextReg = { g = k }
		elseif op == "GSET" then
			local k = ju.funck(proto, -d - 1)
			local v = reg[a]
			defined[k] = defined[k] or (v and v.kind) or "value"
			-- An alias (ChatFrame_SendTell = ChatFrameUtil.SendTell) or a wrapper function: what it stands for.
			if v and v.g and v.g:find("%.") then aliases[k] = { v.g } end
			if v and v.reads then aliases[k] = v.reads end
			-- (A table made here, with its keys: SOUNDKIT = { ... }.)
			if v and v.keys then for key in pairs(v.keys) do members[k .. "." .. key] = true end end
		elseif op == "FNEW" then
			local childReads = WalkLua(ju.funck(proto, -d - 1))
			nextReg = { kind = "function", reads = childReads }
		elseif op == "TNEW" or op == "TDUP" then
			nextReg = { kind = "table", keys = {} }
			if op == "TDUP" then
				for key in pairs(ju.funck(proto, -d - 1)) do if type(key) == "string" then nextReg.keys[key] = true end end
			end
		elseif op == "MOV" then
			nextReg = reg[d]
		elseif op == "KSTR" then
			nextReg = { str = ju.funck(proto, -d - 1) }
		elseif op == "TGETS" or (op == "TGETV" and reg[c] and reg[c].str) then
			local key = op == "TGETS" and ju.funck(proto, -c - 1) or reg[c].str
			local base = reg[b]
			if base and base.g then
				local method = false
				local prev = ju.funcbc(proto, pc - 1)
				if prev and OP[bit.band(prev, 0xff)] == "MOV" and bit.band(bit.rshift(prev, 8), 0xff) == a + 2 then method = true end
				if method then
					methodsOn[base.g] = methodsOn[base.g] or {}
					methodsOn[base.g][key] = true
				end
				nextReg = { g = base.g .. "." .. tostring(key) }
				reads[#reads + 1] = base.g .. "." .. tostring(key)
			end
		elseif op == "TSETS" or (op == "TSETV" and reg[c] and reg[c].str) then
			local key = op == "TSETS" and ju.funck(proto, -c - 1) or reg[c].str
			local base = reg[b]
			if base and base.g and type(key) == "string" then members[base.g .. "." .. key] = true end
			if base and base.keys and type(key) == "string" then base.keys[key] = true end
		end
		if not ({ TSETS = true, TSETV = true, TSETB = true, GSET = true, RET = true, RET0 = true, RET1 = true, ISF = true, IST = true, JMP = true })[op] then reg[a] = nextReg end
		if op == "CALL" or op == "CALLM" then for r = a, a + 40 do reg[r] = nil end end
		pc = pc + 1
	end
	return reads
end
local luaFiles, xmlFiles = {}, {}
for path in pairs(loaded) do
	if path:find("%.lua$") then luaFiles[#luaFiles + 1] = path elseif path:find("%.xml$") then xmlFiles[#xmlFiles + 1] = path end
end
table.sort(luaFiles)
table.sort(xmlFiles)
local unreadable = 0
for _, path in ipairs(luaFiles) do
	if not path:find("Blizzard_APIDocumentation") then
		local chunk = loadfile(path)
		if chunk then WalkLua(chunk) else unreadable = unreadable + 1 end
	end
end

-- XML: named objects, templates (their type, parents, mixins, keys).
local WIDGETS = {
	Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true, StatusBar = true,
	Texture = true, FontString = true, MaskTexture = true, Line = true, Cooldown = true, GameTooltip = true,
	MessageFrame = true, ScrollingMessageFrame = true, Model = true, PlayerModel = true, DressUpModel = true,
	ModelScene = true, SimpleHTML = true, ColorSelect = true, Minimap = true, Font = true, AnimationGroup = true,
	Alpha = true, Translation = true, Scale = true, Rotation = true, Animation = true,
}
local objects, templates, intrinsic, namedDefs = {}, {}, {}, {}
for _, path in ipairs(xmlFiles) do
	local src = Read(path) or ""
	src = src:gsub("<!%-%-.-%-%->", "")
	local stack = {}
	for close, tag, attrs, selfClose in src:gmatch("<(/?)([%w_]+)([^>]-)(/?)>") do
		if close == "/" then
			-- Pop to the matching open tag.
			for i = #stack, 1, -1 do
				if stack[i].tag == tag then
					for j = #stack, i, -1 do stack[j] = nil end
					break
				end
			end
		else
			local e = { tag = tag, name = attrs:match('%sname="([^"]+)"'), key = attrs:match('parentKey="([^"]+)"'),
				inherits = attrs:match('inherits="([^"]+)"'), mixin = attrs:match('mixin="([^"]+)"'),
				virtual = attrs:find('virtual="true"') ~= nil, intrinsic = attrs:find('intrinsic="true"') ~= nil }
			local widget = WIDGETS[tag] or intrinsic[tag]
			if widget then
				-- The nearest widget it is inside.
				local owner
				for i = #stack, 1, -1 do if stack[i].widget then owner = stack[i] break end end
				e.widget = true
				local rank = path:find("/Camelot/") and 4 or path:find("/Mainline/") and 3 or path:find("/Classic/") and 0 or 2
				local def = { type = tag, inherits = e.inherits, mixin = e.mixin, keys = {}, path = path, rank = rank }
				-- (A font, virtual or not, is a global font object: CreateFontString's and _G's.)
				if tag == "Font" and e.name and not owner then
					objects[e.name] = "font"
				end
				if not owner and e.name and (e.virtual or e.intrinsic) then
					if not templates[e.name] or (templates[e.name].rank or 0) < rank then templates[e.name] = def end
					if e.intrinsic then intrinsic[e.name] = tag end
					e.def = def
				elseif e.name and not e.name:find("%$") and not e.virtual then
					-- A named object (at the top or inside another): a global the client makes.
					objects[e.name] = tag == "Font" and "font" or "frame"
					if not namedDefs[e.name] or (namedDefs[e.name].rank or 0) < rank then namedDefs[e.name] = def end
					e.def = def
				else
					e.def = def
				end
				if owner and owner.def and e.key then
					owner.def.keys[e.key] = { type = tag, inherits = e.inherits, name = e.name }
				end
			end
			if selfClose ~= "/" then stack[#stack + 1] = e end
		end
	end
end

---------------------------------------------------------------------------
-- The documentation.
---------------------------------------------------------------------------

local docs = {}
do
	local function Proxy() return setmetatable({}, { __index = function(t, k) local p = Proxy(); rawset(t, k, p) return p end }) end
	local env = setmetatable({ Enum = Proxy(), Constants = Proxy(),
		APIDocumentation = { AddDocumentationTable = function(_, t) docs[#docs + 1] = t end } }, { __index = _G })
	for _, path in ipairs(List('find "' .. ADDONS .. '/Blizzard_APIDocumentationGenerated" -name "*.lua"')) do
		local chunk = loadfile(path)
		if chunk then
			setfenv(chunk, env)
			pcall(chunk)
		end
	end
end
local apiGlobal, apiNs, apiMember, restrictions, events, enums, scriptObjects, constants = {}, {}, {}, {}, {}, {}, {}, {}
for _, t in ipairs(docs) do
	if t.Type == "ScriptObject" then
		local set = {}
		for _, f in ipairs(t.Functions or {}) do set[f.Name] = true end
		scriptObjects[t.Name] = set
	else
		for _, f in ipairs(t.Functions or {}) do
			local full = t.Namespace and (t.Namespace .. "." .. f.Name) or f.Name
			if t.Namespace then
				apiNs[t.Namespace] = true
				apiMember[full] = true
			else
				apiGlobal[f.Name] = true
			end
			if f.IsProtectedFunction then restrictions[full] = "protected"
			elseif f.HasRestrictions then restrictions[full] = "restricted" end
		end
		for _, e in ipairs(t.Events or {}) do if e.LiteralName then events[e.LiteralName] = true end end
	end
	for _, tt in ipairs(t.Tables or {}) do
		if tt.Type == "Enumeration" and tt.Name then
			local values = {}
			for _, f in ipairs(tt.Fields or {}) do
				if type(f.EnumValue) == "number" then values[f.Name] = f.EnumValue end
			end
			enums[tt.Name] = values
		elseif tt.Type == "Constants" and tt.Name then
			local values = {}
			for _, f in ipairs(tt.Values or {}) do
				if type(f.Value) == "number" or type(f.Value) == "string" then values[f.Name] = f.Value end
			end
			constants[tt.Name] = values
		end
	end
end

-- The widget types, each with the documentation's API tables it is made of (the client's widget
-- hierarchy: every object, a script region, a region, a frame, then the type's own).
local BASE = { "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local REGION = { "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleRegionAPI", "SimpleAnimatableObjectAPI" }
local FRAME = { "SimpleFrameAPI" }
local TYPES = {
	Frame = { REGION, FRAME },
	Button = { REGION, FRAME, { "SimpleButtonAPI" } },
	CheckButton = { REGION, FRAME, { "SimpleButtonAPI", "SimpleCheckboxAPI" } },
	EditBox = { REGION, FRAME, { "SimpleEditBoxAPI", "SimpleFontAPI" } },
	ScrollFrame = { REGION, FRAME, { "SimpleScrollFrameAPI" } },
	Slider = { REGION, FRAME, { "SimpleSliderAPI" } },
	StatusBar = { REGION, FRAME, { "SimpleStatusBarAPI" } },
	GameTooltip = { REGION, FRAME, { "FrameAPITooltip" } },
	MessageFrame = { REGION, FRAME, { "SimpleMessageFrameAPI" } },
	ScrollingMessageFrame = { REGION, FRAME, { "SimpleMessageFrameAPI" } },
	Minimap = { REGION, FRAME, { "MinimapFrameAPI" } },
	Texture = { REGION, { "SimpleTextureBaseAPI", "SimpleTextureAPI" } },
	MaskTexture = { REGION, { "SimpleTextureBaseAPI", "SimpleMaskTextureAPI" } },
	Line = { REGION, { "SimpleTextureBaseAPI", "SimpleLineAPI" } },
	FontString = { REGION, { "SimpleFontStringAPI", "SimpleFontAPI" } },
	Font = { { "SimpleFontAPI" } },
	AnimationGroup = { { "SimpleAnimGroupAPI" } },
	Animation = { { "SimpleAnimAPI" } },
	Alpha = { { "SimpleAnimAPI", "SimpleAnimAlphaAPI" } },
	Translation = { { "SimpleAnimAPI", "SimpleAnimTranslationAPI" } },
	Scale = { { "SimpleAnimAPI", "SimpleAnimScaleAPI" } },
	Rotation = { { "SimpleAnimAPI", "SimpleAnimRotationAPI" } },
}
-- GameTooltip's own methods (SetOwner, AddLine...) are the engine's, outside the documentation's
-- tables: the ones Blizzard's own code calls on GameTooltip count.
local widgets = {}
for name, groups in pairs(TYPES) do
	local set = {}
	for _, api in ipairs(BASE) do for m in pairs(scriptObjects[api] or {}) do set[m] = true end end
	for _, group in ipairs(groups) do
		for _, api in ipairs(group) do
			assert(scriptObjects[api], "the documentation has no " .. api)
			for m in pairs(scriptObjects[api]) do set[m] = true end
		end
	end
	if name == "GameTooltip" then for m in pairs(methodsOn.GameTooltip or {}) do set[m] = true end end
	widgets[name] = set
end

---------------------------------------------------------------------------
-- The names Olympus (and the pass) use.
---------------------------------------------------------------------------

local wantGlobals, wantMembers, wantEvents, wantTemplates, wantEnums, wantConstants, wantStrings = {}, {}, {}, {}, {}, {}, {}
local function WalkAddon(proto)
	local reg = {}
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
		if op == "GGET" then
			local k = ju.funck(proto, -d - 1)
			wantGlobals[k] = true
			nextReg = { g = k }
		elseif op == "FNEW" then
			WalkAddon(ju.funck(proto, -d - 1))
		elseif op == "MOV" then
			nextReg = reg[d]
		elseif op == "KSTR" or op == "TDUP" then
			-- (A constant table's strings too: { "PanelTabButtonTemplate", ... }, { "ADDON_LOADED", ... }.)
			local k = ju.funck(proto, -d - 1)
			local strings = {}
			if type(k) == "table" then
				for key, v in pairs(k) do
					if type(v) == "string" then strings[#strings + 1] = v end
					if type(key) == "string" then strings[#strings + 1] = key end
				end
			else
				strings[1] = k
			end
			for _, s in ipairs(strings) do
				if s:find("^[A-Z][A-Z0-9_]+$") and #s > 4 then wantEvents[s] = true end
				if s:find("Template$") then wantTemplates[s] = true end
				-- (A name the addon may look up at run time, _G[name]: kept when the client has it.)
				if s:find("^[A-Za-z_][%w_]*$") and s:find("%u") then wantStrings[s] = true end
			end
			nextReg = op == "KSTR" and { str = k } or nil
		elseif op == "TGETS" or (op == "TGETV" and reg[c] and reg[c].str) then
			local key = op == "TGETS" and ju.funck(proto, -c - 1) or reg[c].str
			local base = reg[b]
			if base and base.g and type(key) == "string" then
				if base.g == "_G" then
					wantGlobals[key] = true
					nextReg = { g = key }
				elseif not base.g:find("%.") then
					wantMembers[base.g .. "." .. key] = true
					if base.g == "Enum" then wantEnums[key] = true end
					if base.g == "Constants" then wantConstants[key] = true end
					nextReg = { g = base.g .. "." .. key }
				end
			end
		end
		if not ({ TSETS = true, TSETV = true, TSETB = true, GSET = true, RET = true, RET0 = true, RET1 = true, ISF = true, IST = true, JMP = true })[op] then reg[a] = nextReg end
		if op == "CALL" or op == "CALLM" then for r = a, a + 40 do reg[r] = nil end end
		pc = pc + 1
	end
end
for _, path in ipairs(List('cd "' .. ROOT .. '" && find Olympus -name "*.lua"')) do
	local chunk = loadfile(ROOT .. "/" .. path)
	if chunk then WalkAddon(chunk) end
end
-- The pass's own stand-ins: every global, member, frame method and template it offers.
do
	local p = io.popen('cd "' .. ROOT .. '" && luajit tests/gamepad.lua --names 2>/dev/null')
	if p then
		for line in p:lines() do
			local kind, name = line:match("^(%a+) (.+)$")
			if kind == "global" then wantGlobals[name] = true
			elseif kind == "member" then wantMembers[name] = true
			elseif kind == "event" then wantEvents[name] = true
			elseif kind == "template" then wantTemplates[name] = true
			elseif kind == "enum" then wantEnums[name] = true
			elseif kind == "constants" then wantConstants[name] = true end
		end
		p:close()
	end
end

local function Kind(name)
	if SEEN_IN_GAME[name] then return "seen" end
	if apiNs[name] then return "namespace" end
	if apiGlobal[name] then return "api" end
	if defined[name] then return defined[name] end
	if objects[name] then return objects[name] end
	if used[name] then return "used" end
	return false
end
local globals, memberKinds, restricted, eventKinds = {}, {}, {}, {}
-- (The addon's strings that name something the client has, and those that look like a frame's name
-- whether it has it or not: the ones Olympus looks up with _G[name], the pass needs to know.)
for name in pairs(wantStrings) do
	if not wantGlobals[name] and not events[name] then
		local kind = Kind(name)
		if (kind and kind ~= "used") or name:find("Frame$") or name:find("Panel$") then wantGlobals[name] = true end
	end
end
for name in pairs(wantGlobals) do globals[name] = Kind(name) end
-- (Members of tables only: a frame's methods are its widget type's, the Lua library's are Lua's,
-- Enum's and Constants' are below.)
local LUA_LIBS = { string = true, table = true, math = true, bit = true, coroutine = true, os = true, io = true, debug = true }
for full in pairs(wantMembers) do
	local base = full:match("^([^%.]+)%.")
	local kind0 = Kind(base)
	if base ~= "Enum" and base ~= "_G" and base ~= "Constants" and not LUA_LIBS[base] and (kind0 == "namespace" or kind0 == "table") then
		local kind = false
		if apiMember[full] then kind = "api"
		elseif members[full] then kind = "lua"
		elseif used[full] then kind = "used" end
		-- (Members of Olympus's own tables, or of a table the client lacks, are left out.)
		if globals[base] or Kind(base) then
			if not base:find("^Olympus") then memberKinds[full] = kind end
		end
	end
end
for name in pairs(wantGlobals) do
	if restrictions[name] then restricted[name] = restrictions[name] end
	-- A global of Blizzard's Lua standing for a restricted function (an alias, a wrapper) is too.
	for _, target in ipairs(aliases[name] or {}) do
		if restrictions[target] and not restricted[name] then restricted[name] = restrictions[target] end
	end
end
for full in pairs(memberKinds) do if restrictions[full] then restricted[full] = restrictions[full] end end
for e in pairs(wantEvents) do
	if events[e] then eventKinds[e] = true end
end
local enumOut, constantsOut = {}, {}
for name in pairs(wantEnums) do enumOut[name] = enums[name] or false end
for name in pairs(wantConstants) do if constants[name] then constantsOut[name] = constants[name] end end

-- (Any of the addon's strings naming a template: CreateFrame's fourth argument.)
for name in pairs(wantStrings) do if templates[name] then wantTemplates[name] = true end end
-- Templates: type, keys and mixins' methods, through what each inherits.
local templateOut = {}
local keyTemplates = {}
local function Flatten(name, seen, def)
	local t = def or templates[name]
	if not t or seen[name] then return nil end
	seen[name] = true
	-- (chain: the template and every one it inherits, in order; keys: "type|its templates|its name".)
	local out = { type = t.type, keys = {}, methods = {}, chain = { name } }
	for parent in (t.inherits or ""):gmatch("[^,%s]+") do
		local p = Flatten(parent, seen)
		if p then
			if WIDGETS[out.type] == nil and p.type then out.type = p.type end
			for k, v in pairs(p.keys) do out.keys[k] = v end
			for m in pairs(p.methods) do out.methods[m] = true end
			for _, c in ipairs(p.chain) do out.chain[#out.chain + 1] = c end
		end
	end
	if intrinsic[t.type] then out.type = intrinsic[t.type] end
	for k, v in pairs(t.keys) do
		out.keys[k] = (intrinsic[v.type] or v.type) .. "|" .. (v.inherits or ""):gsub("%s", "") .. "|" .. (v.name or "")
		-- (The templates a key is made from are written out too.)
		for parent in (v.inherits or ""):gmatch("[^,%s]+") do keyTemplates[parent] = true end
	end
	for mixin in (t.mixin or ""):gmatch("[^,%s]+") do
		local prefix = mixin .. "."
		for full in pairs(members) do
			if full:sub(1, #prefix) == prefix then out.methods[full:sub(#prefix + 1)] = true end
		end
	end
	return out
end
keyTemplates = {}
local pending = {}
for name in pairs(wantTemplates) do pending[#pending + 1] = name end
while #pending > 0 do
	local name = table.remove(pending)
	if not templateOut[name] then
		local t = Flatten(name, {})
		if t then
			templateOut[name] = t
			for k in pairs(keyTemplates) do if not templateOut[k] then pending[#pending + 1] = k end end
		end
	end
end
-- The game's named frames Olympus and the pass use, made the same way.
local frameOut = {}
for name in pairs(wantGlobals) do
	if namedDefs[name] then
		local t = Flatten(name, {}, namedDefs[name])
		if t then frameOut[name] = t end
	end
end

---------------------------------------------------------------------------
-- The fixture.
---------------------------------------------------------------------------

local function Sorted(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
	return keys
end
local function Q(s) return ("%q"):format(s) end
local function Value(v) if v == false then return "false" elseif v == true then return "true" end return Q(v) end
local out = {}
local function W(s) out[#out + 1] = s end
W("-- What WoW: Forever's client offers, as its own UI source shows it (build " .. BUILD .. "): made by")
W("-- scripts/forever-api.lua from the extracted Interface folder; do not edit. tests/gamepad.lua checks")
W("-- its stand-ins against it: a stand-in may offer only what the client has.")
W("return {")
W("\tbuild = " .. BUILD .. ",")
local function Map(label, t)
	W("\t" .. label .. " = {")
	for _, k in ipairs(Sorted(t)) do W("\t\t[" .. Q(k) .. "] = " .. Value(t[k]) .. ",") end
	W("\t},")
end
Map("globals", globals)
Map("members", memberKinds)
Map("restricted", restricted)
Map("events", eventKinds)
W("\tenums = {")
for _, name in ipairs(Sorted(enumOut)) do
	if enumOut[name] == false then
		W("\t\t" .. name .. " = false,")
	else
		local parts = {}
		for _, k in ipairs(Sorted(enumOut[name])) do parts[#parts + 1] = k .. " = " .. enumOut[name][k] end
		W("\t\t" .. name .. " = { " .. table.concat(parts, ", ") .. " },")
	end
end
W("\t},")
W("\tconstants = {")
for _, name in ipairs(Sorted(constantsOut)) do
	local parts = {}
	for _, k in ipairs(Sorted(constantsOut[name])) do
		local v = constantsOut[name][k]
		parts[#parts + 1] = k .. " = " .. (type(v) == "string" and Q(v) or tostring(v))
	end
	W("\t\t" .. name .. " = { " .. table.concat(parts, ", ") .. " },")
end
W("\t},")
W("\twidgets = {")
for _, name in ipairs(Sorted(widgets)) do W("\t\t" .. name .. " = " .. Q(table.concat(Sorted(widgets[name]), " ")) .. ",") end
W("\t},")
W("\tframes = {")
for _, name in ipairs(Sorted(frameOut)) do
	local t = frameOut[name]
	local keys = {}
	for _, k in ipairs(Sorted(t.keys)) do keys[#keys + 1] = k .. " = " .. Q(t.keys[k]) end
	W("\t\t[" .. Q(name) .. "] = { type = " .. Q(t.type) .. ", keys = { " .. table.concat(keys, ", ") .. " }, methods = "
		.. Q(table.concat(Sorted(t.methods), " ")) .. " },")
end
W("\t},")
W("\ttemplates = {")
for _, name in ipairs(Sorted(templateOut)) do
	local t = templateOut[name]
	local keys = {}
	for _, k in ipairs(Sorted(t.keys)) do keys[#keys + 1] = k .. " = " .. Q(t.keys[k]) end
	W("\t\t[" .. Q(name) .. "] = { type = " .. Q(t.type) .. ", chain = " .. Q(table.concat(t.chain, " ")) .. ", keys = { " .. table.concat(keys, ", ") .. " }, methods = "
		.. Q(table.concat(Sorted(t.methods), " ")) .. " },")
end
W("\t},")
W("}")
local text = table.concat(out, "\n") .. "\n"
if CHECK then
	if Read(OUT) == text then print("tests/fixtures/forever-api.lua is up to date") os.exit(0) end
	io.stderr:write("tests/fixtures/forever-api.lua is not what this Interface folder makes: run luajit scripts/forever-api.lua " .. IFACE .. "\n")
	os.exit(1)
end
local f = assert(io.open(OUT, "wb"))
f:write(text)
f:close()
local n = 0
for _ in pairs(globals) do n = n + 1 end
print(("tests/fixtures/forever-api.lua: %d globals, %d Lua files read (%d unreadable), %d XML files, %d templates"):format(n, #luaFiles, unreadable, #xmlFiles, #Sorted(templateOut)))
