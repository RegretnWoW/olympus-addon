-- The gamepad pass (1.1.5): whole sessions of the addon with Blizzard's gamepad UI simulated, from a
-- gamepad login and across switches both ways, failing when anything of Olympus's reaches the
-- game's UI there. No controller needed: run with the offline suite (tests/run.lua loads it), or
-- alone (luajit tests/gamepad.lua).
--
-- How. Every addon file loads, in its TOC's order, into a sandbox of its own (setfenv): the client
-- model below. Its globals are only what Forever's client has (tests/fixtures/forever-api.lua,
-- made by scripts/forever-api.lua from the client's own UI source): a global the client has that
-- the model doesn't fails as "unmodelled", one it lacks reads as nil, as in the game. The game's
-- frames are strict objects whose every method call from Olympus's code is recorded, as is every
-- call of a function the gamepad audit (scripts/gamepad-audit.lua) counts as a reach: that record
-- is the ledger. Each record carries the gp: tag of the line that made it, so it says which
-- registry entry (Olympus/GamepadRegistry.lua) it belongs to; with the gamepad UI on, only
-- entries allowed there ("own", "exempt", "click" inside a click) may appear in it.
--
-- Mock fidelity (the model may not offer what the client lacks; each part cites what it follows):
--   1. One switch: C_InputInterfaceStyle.GetCurrentStyle and Enum.InputDeviceInterfaceType from
--      the fixture's documentation values; a switch sets the style first, then sends
--      INPUT_DEVICE_INTERFACE_TRANSITION(newMode, oldMode) at once (InputDocumentation.lua, a
--      synchronous event). No test replaces ns.GamepadUI or ns.Gate (tests/run.lua checks it).
--   2. Registrations keep their callbacks (Menu.ModifyMenu, TooltipDataProcessor.AddTooltipPostCall,
--      hooksecurefunc, HookScript, ChatFrameUtil.AddSenderNameFilter), and the model calls them
--      the way the game does.
--   3. A slash command is called directly by the chat box, which then closes itself
--      (Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:265-269): with the gamepad UI on, any
--      Olympus code run that way is a taint event, a failure.
--   4. A restricted function (the fixture's restricted list, from the documentation's
--      HasRestrictions and IsProtectedFunction) called outside a click on a button is refused, and
--      the model sends ADDON_ACTION_BLOCKED as the client does.
--   5. Strict: an unknown global or a method the client's widget type lacks is an error; a getter
--      the client has that the model doesn't return yet is "unmodelled".
--   6. Timers run: C_Timer.After and tickers queue, and the pass advances the clock.
--   7. Smart Navigation: a frame the gamepad UI navigates counts every visible Button (or edit
--      box) under it (Blizzard_GamepadSmartNavigation/Utility.lua:208-262, Utility.FindButtons).
--   8. Popups and the chat box: StaticPopup_Show shows one of StaticPopup1..4 (Blizzard_StaticPopup),
--      the chat box's functions set the last active edit box.
--   9. The map library is the real one (Olympus/libs), on a model of the world map.
-- A mock that differs from Forever's code is a bug in the model, not a reason to change an
-- assertion.
--
-- Alone: luajit tests/gamepad.lua. For work on the model: "--names" lists what it offers (read by
-- scripts/forever-api.lua), "--discover [gamepad]" logs in and lists what it lacks instead of
-- failing, "--debug" returns its parts to a script.

local H = ...
local MODE = type(H) == "string" and H or nil
if type(H) ~= "table" then H = nil end
local ROOT = H and H.ROOT or ((arg and arg[0] or ""):match("^(.*)tests[/\\]gamepad%.lua$") or "./")
local ADDON_DIR = ROOT .. "Olympus/"

local passed, failed = 0, 0
local test = H and H.test or function(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
if MODE then test = function() end end -- (--names, --discover, --debug: the model alone)
local eq = H and H.eq or function(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local FIX = assert(loadfile(ROOT .. "tests/fixtures/forever-api.lua"))()
local AUDIT = assert(loadfile(ROOT .. "scripts/gamepad-audit.lua"))("--module")
local REGISTRY = {}
do
	local list = assert(AUDIT.LoadRegistry((ROOT:gsub("[/\\]$", "")) ~= "" and (ROOT:gsub("[/\\]$", "")) or "."))
	for _, e in ipairs(list) do REGISTRY[e.id] = e end
end

-- The pass's helpers: GP.Covers(id) names the registry entry a test exercises (the audit checks
-- every entry is named somewhere under tests/).
local GP = { covered = {} }
function GP.Covers(id)
	assert(REGISTRY[id], "GP.Covers: no registry entry " .. tostring(id))
	GP.covered[id] = true
end

local function Set(list) local s = {} for w in (list or ""):gmatch("%S+") do s[w] = true end return s end
-- (The model's own objects take their metatables as they are: tests/run.lua wraps setmetatable to
-- catch a coroutine yield across a metamethod in the addon's code, which no model object has.)
local setmetatable = function(t, mt) debug.setmetatable(t, mt) return t end
local WIDGET_METHODS = {}
for kind, list in pairs(FIX.widgets) do WIDGET_METHODS[kind] = Set(list) end
-- A key's fixture line: "type|the templates it inherits|its name" ($parent: its parent's name).
local function Key(spec)
	local kind, inherits, name = tostring(spec):match("^([^|]*)|([^|]*)|(.*)$")
	return kind or spec, inherits ~= "" and inherits or nil, name ~= "" and name or nil
end
local TEMPLATES = {}
for name, t in pairs(FIX.templates) do TEMPLATES[name] = { type = t.type, keys = t.keys, methods = Set(t.methods), chain = Set(t.chain) } end

---------------------------------------------------------------------------
-- Which registry entry a runtime reach belongs to: the gp: tags of the Olympus line that made it
-- (the audit's own reading of the source), else of its function's first line.
---------------------------------------------------------------------------

local TAGS = {} -- [file under Olympus/] = { [line] = { ids } }
do
	local root = (ROOT:gsub("[/\\]$", ""))
	if root == "" then root = "." end
	local vendor = {}
	for id, e in pairs(REGISTRY) do for _, f in ipairs(type(e.vendor) == "table" and e.vendor or {}) do vendor[f] = id end end
	local p = io.popen('cd "' .. root .. '" && find Olympus -name "*.lua"')
	for rel in p:lines() do
		local scan = AUDIT.ScanFile(root, rel)
		local short = rel:gsub("^Olympus/", "")
		local t = {}
		if scan then for line, tag in pairs(scan.tags) do t[line] = tag.ids end end
		if vendor[short] then setmetatable(t, { __index = function() return { vendor[short] } end }) end
		TAGS[short] = t
	end
	p:close()
end
local function OlympusFile(source)
	return type(source) == "string" and source:match("[@/\\]Olympus[/\\](.+%.lua)$")
end
-- The gate's own work at a switch (Gamepad.lua's Park, Leftovers and Switched, and the parks and
-- leftover checks they run): what can be undone undone, what stays read. Its records are the
-- switch's, allowed there; the sessions check what each park leaves.
local GATE_WORK = {}
do
	local n = 0
	for line in assert(io.open(ADDON_DIR .. "Gamepad.lua")):lines() do
		n = n + 1
		local fn = line:match("^function Gate%.(%a+)%(")
		if fn == "Park" or fn == "Leftovers" or fn == "Switched" then GATE_WORK[n] = fn end
	end
end
-- The Olympus line that made a reach: the first Olympus function on the stack above the model,
-- with its tags (its line's, else its function's first line's); when it has none (a helper handed
-- one of the game's frames, ns.MakeRoundButton), the first tagged Olympus caller above it.
local function Caller(level)
	level = (level or 2) + 1
	local found, gateWork
	while true do
		local info = debug.getinfo(level, "Sl")
		if not info then break end
		local file = OlympusFile(info.source)
		if file then
			file = file:gsub("\\", "/")
			if file == "Gamepad.lua" and GATE_WORK[info.linedefined] then gateWork = GATE_WORK[info.linedefined] end
			if not (found and found.ids) then
				local tags = TAGS[file] or {}
				local here = { file = file, line = info.currentline, ids = tags[info.currentline] or tags[info.linedefined] }
				if here.ids and found then here.via = found.file .. ":" .. tostring(found.line) end
				if here.ids or not found then found = here end
			end
		end
		level = level + 1
	end
	if found then found.gateWork = gateWork end
	return found
end
-- Called directly from Olympus's code (the model's own calls don't count): FromOlympus(1) in a
-- function of the model asks about that function's caller.
-- (Through pcall and the like: C functions, and tests/run.lua's stand-ins for them, are skipped.)
local function FromOlympus(level)
	level = (level or 1) + 2
	while true do
		local info = debug.getinfo(level, "S")
		if not info then return false end
		if info.what ~= "C" and not (info.source or ""):find("tests[/\\]run%.lua$") then
			return OlympusFile(info.source) ~= nil
		end
		level = level + 1
	end
end

---------------------------------------------------------------------------
-- The client.
---------------------------------------------------------------------------

local LUA = {
	"assert", "error", "ipairs", "pairs", "next", "select", "type", "tostring", "tonumber", "unpack", "rawget", "rawset",
	"setmetatable", "getmetatable", "pcall", "xpcall", "string", "table", "math", "coroutine", "bit", "print",
	"loadstring", "collectgarbage",
}

local function NewClient(opts)
	opts = opts or {}
	local C = { ledger = {}, taint = {}, timers = {}, tickers = {}, loadErrors = {}, clock = 1000, now = 1760000000, style = opts.gamepad and 1 or 0,
		clicking = false, eventFrames = {}, updating = {}, menus = {}, postCalls = {}, nameFilters = {}, blocked = {},
		printed = {}, frames = {}, unmodelled = {}, created = {} }
	local E = {}
	C.env = E

	-- The ledger: a reach from Olympus's code, with the entry its line is tagged for.
	function C.Record(sym, kind, level)
		local who = Caller((level or 2) + 1)
		local r = { sym = sym, kind = kind, gamepad = C.style == 1, click = C.clicking, file = who and who.file, line = who and who.line,
			ids = who and who.ids, gateWork = who and who.gateWork, trace = debug.traceback("", 3) }
		C.ledger[#C.ledger + 1] = r
		return r
	end
	function C.Mark() return #C.ledger end
	function C.Since(mark)
		local out = {}
		for i = (mark or 0) + 1, #C.ledger do out[#out + 1] = C.ledger[i] end
		return out
	end

	------------------------------------------------------------------
	-- Widgets: every method a real one of that type has (the fixture's widgets and the template's
	-- mixin methods), no other. The ones modelled below behave; a setter the client has is kept as
	-- set; a getter the client has that isn't modelled fails when called (an "unmodelled" method).
	------------------------------------------------------------------
	local W = {}
	local SETTER = { "^Set", "^Enable", "^Disable", "^Register", "^Unregister", "^Clear", "^Lock", "^Unlock", "^Raise",
		"^Lower", "^Play", "^Stop", "^Start", "^Add", "^Remove", "^Reset", "^Apply", "^Desaturate", "^Highlight", "^Fit",
		"^Adjust", "^Flash", "^Update", "^Refresh", "^Mark", "^Insert", "^Scroll", "^Pause", "^Finish", "^Restart",
		"^Hook", "^Release", "^Acquire", "^Copy", "^Narration" }
	local function IsSetter(k) for _, p in ipairs(SETTER) do if k:find(p) then return true end end return false end
	-- What the audit counts per file instead of tagging (its ratchet): Olympus's own tooltips (the
	-- game's GameTooltip owned by one of Olympus's frames) and its lines in the chat windows
	-- ("chat-output"). Anything else on the tooltip (a player's, the game's) is a reach.
	local TOOLTIP_OWN = AUDIT.RATCHET.GameTooltip.methods
	local function Own(w, k, ...)
		if rawget(w, "kind") == "GameTooltip" and TOOLTIP_OWN[k] then
			local owner = (k == "SetOwner") and (...) or rawget(w, "owner")
			return type(owner) == "table" and rawget(owner, "olympus") == true
		end
		return false
	end
	local function RecordMethod(w, label, k)
		local r = C.Record(label .. ":" .. k, "method", 2)
		if not r.ids and rawget(w, "kind") == "ScrollingMessageFrame" and k == "AddMessage" then r.ids = { "chat-output" } end
		return r
	end
	local meta = {}
	meta.__index = function(w, k)
		local m = W[k]
		local methods, extra, blizzard = rawget(w, "methods"), rawget(w, "templateMethods"), rawget(w, "blizzard")
		local allowed = methods[k] or (extra and extra[k])
		local label = rawget(w, "name") or rawget(w, "path") or "?"
		if m and allowed then
			if blizzard and not AUDIT.READS[k] then
				return function(self, ...)
					if FromOlympus(1) and not Own(w, k, ...) then RecordMethod(w, label, k) end
					return m(self, ...)
				end
			end
			return m
		end
		if allowed and type(k) == "string" then
			return function(self, ...)
				if blizzard and not AUDIT.READS[k] and FromOlympus(1) and not Own(w, k, ...) then RecordMethod(w, label, k) end
				if IsSetter(k) then
					self.set[k] = { ... }
					return
				end
				C.unmodelled[rawget(w, "kind") .. ":" .. k] = true
				error(("unmodelled method %s:%s (the client has it: model it in tests/gamepad.lua)"):format(rawget(w, "kind"), k), 2)
			end
		end
		return nil
	end
	-- What a template's own scripts do, where Olympus relies on it (Blizzard_SharedXML).
	C.TEMPLATE_SCRIPTS = {
		-- UIPanelCloseButton_OnClick (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:150-162): the
		-- parent's onCloseCallback first, then HideUIPanel unless it said no. HideUIPanel
		-- (UIParentPanelManager.lua) does nothing in combat for a call that is not secure; out of
		-- combat it hides a window that is no UI panel.
		UIPanelCloseButton = function(w)
			w.scripts.OnClick = function(self)
				local parent = self:GetParent()
				if not parent then return end
				local goOn = true
				if parent.onCloseCallback then goOn = parent.onCloseCallback(self) end
				if goOn and not C.combat then parent:Hide() end
			end
		end,
	}
	local function NewWidget(kind, name, parent, template, blizzard)
		local methods = WIDGET_METHODS[kind]
		assert(methods, "the client has no widget type " .. tostring(kind))
		local w = setmetatable({ kind = kind, name = name, parent = parent, children = {}, regions = {}, points = {},
			shown = true, scripts = {}, hooks = {}, events = {}, set = {}, methods = methods, w = 0, h = 0, level = 1,
			alpha = 1, scale = 1, blizzard = blizzard or false, olympus = not blizzard, enabled = true, seq = #C.created + 1,
			templateMethods = false }, meta)
		if parent then
			local list = (kind == "Texture" or kind == "FontString" or kind == "MaskTexture" or kind == "Line") and parent.regions or parent.children
			list[#list + 1] = w
		end
		if name then
			-- "$parent" in a name is its parent's name (the client's rule for named children).
			if parent and name:find("%$parent") then name = name:gsub("%$parent", parent.name or "") ; w.name = name end
			rawset(E, name, w)
		end
		if template then
			local tm = {}
			for t in tostring(template):gmatch("[^,%s]+") do
				local def = TEMPLATES[t]
				if not def then error(("the client has no template %s (tests/fixtures/forever-api.lua)"):format(t), 3) end
				for m in pairs(def.methods) do tm[m] = true end
				for c in pairs(def.chain) do if C.TEMPLATE_SCRIPTS[c] then C.TEMPLATE_SCRIPTS[c](w) end end
				for key, spec in pairs(def.keys) do
					local ktype, inherits, kname = Key(spec)
					if rawget(w, key) == nil and WIDGET_METHODS[ktype] then
						local child = NewWidget(ktype, kname and name and kname or nil, w, inherits, blizzard)
						rawset(child, "path", (name or rawget(w, "path") or kind) .. "." .. key)
						rawset(child, "fromKey", true) -- (named "$parent..." by the client's own template)
						rawset(w, key, child)
					end
				end
			end
			w.templateMethods = tm
			w.template = template
		end
		C.created[#C.created + 1] = w
		return w
	end
	C.NewWidget = NewWidget

	function W:GetName() return self.name end
	function W:GetParent() return self.parent end
	function W:GetObjectType() return self.kind end
	function W:IsObjectType(t)
		if t == self.kind then return true end
		local family = { Button = { "Frame" }, CheckButton = { "Button", "Frame" }, EditBox = { "Frame" }, ScrollFrame = { "Frame" },
			Slider = { "Frame" }, StatusBar = { "Frame" }, GameTooltip = { "Frame" }, MessageFrame = { "Frame" },
			ScrollingMessageFrame = { "Frame" }, Minimap = { "Frame" } }
		for _, f in ipairs(family[self.kind] or {}) do if f == t then return true end end
		return t == "Region" or t == "Object" or t == "ScriptObject"
	end
	function W:IsForbidden() return false end
	function W:IsProtected() return false, false end
	function W:GetDebugName() return self.name or "?" end
	function W:SetParent(p)
		if self.parent then
			for _, list in ipairs({ self.parent.children, self.parent.regions }) do
				for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
			end
		end
		self.parent = p
		if p then table.insert((self.kind == "Texture" or self.kind == "FontString") and p.regions or p.children, self) end
		if p and p.blizzard and p ~= E.UIParent and self.olympus and FromOlympus(1) then
			C.Record((rawget(p, "name") or rawget(p, "path") or "?") .. " <- " .. (self.name or self.kind), "parent", 1)
		end
	end
	function W:GetChildren() return unpack(self.children) end
	function W:GetNumChildren() return #self.children end
	function W:GetRegions() return unpack(self.regions) end
	function W:Show()
		if self.shown then return end
		self.shown = true
		if self:IsVisible() then C.Fire1(self, "OnShow") end
	end
	function W:Hide()
		if not self.shown then return end
		local was = self:IsVisible()
		self.shown = false
		if was then C.Fire1(self, "OnHide") end
	end
	function W:SetShown(on) if on then self:Show() else self:Hide() end end
	function W:IsShown() return self.shown end
	function W:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
	function W:SetScript(kind, fn)
		self.scripts[kind] = fn
		if kind == "OnUpdate" then C.updating[self] = fn and true or nil end
	end
	function W:GetScript(kind) return self.scripts[kind] end
	function W:HasScript(kind) return true end
	function W:HookScript(kind, fn)
		self.hooks[kind] = self.hooks[kind] or {}
		table.insert(self.hooks[kind], fn)
		if self.blizzard then C.callbacks[#C.callbacks + 1] = { kind = "HookScript", frame = self, script = kind, fn = fn } end
	end
	function W:RegisterEvent(e)
		local known = FIX.events[e]
		if known == nil then error(("event %s: not in tests/fixtures/forever-api.lua (run scripts/forever-api.lua)"):format(tostring(e)), 2) end
		if not known then error(("the client has no event %s"):format(tostring(e)), 2) end
		self.events[e] = true
		C.eventFrames[e] = C.eventFrames[e] or {}
		C.eventFrames[e][self] = true
	end
	function W:UnregisterEvent(e)
		self.events[e] = nil
		if C.eventFrames[e] then C.eventFrames[e][self] = nil end
	end
	function W:UnregisterAllEvents() for e in pairs(self.events) do self:UnregisterEvent(e) end end
	function W:IsEventRegistered(e) return self.events[e] == true end
	function W:SetSize(w, h) self.w, self.h = w or 0, h or 0 end
	function W:SetWidth(w) self.w = w or 0 end
	function W:SetHeight(h) self.h = h or 0 end
	function W:GetWidth() return self.w end
	function W:GetHeight() return self.h end
	function W:GetSize() return self.w, self.h end
	function W:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
		if type(rel) == "string" then rel = rawget(E, rel) end
		self.points[#self.points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
	end
	function W:SetAllPoints(rel) self.points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
	function W:ClearAllPoints() self.points = {} end
	function W:GetNumPoints() return #self.points end
	function W:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
	-- Where it is: a left, bottom, width and height as the screen would have them (a frame with no
	-- point sits at its parent's corner; UIParent fills a 1366 x 768 screen).
	function W:GetRect()
		if self.rect then return unpack(self.rect) end
		local p = self.parent
		local l, b = 0, 0
		if p then l, b = p:GetRect() end
		return l or 0, b or 0, self.w, self.h
	end
	function W:GetLeft() return (self:GetRect()) end
	function W:GetBottom() return select(2, self:GetRect()) end
	function W:GetTop() local _, b, _, h = self:GetRect(); return b + h end
	function W:GetRight() local l, _, w = self:GetRect(); return l + w end
	function W:GetCenter() local l, b, w, h = self:GetRect(); return l + w / 2, b + h / 2 end
	function W:GetScale() return self.scale end
	function W:SetScale(s) self.scale = s end
	function W:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
	function W:SetAlpha(a) self.alpha = a end
	function W:GetAlpha() return self.alpha end
	function W:SetFrameLevel(l) self.level = l end
	function W:GetFrameLevel() return self.level end
	function W:SetFrameStrata(s) self.strata = s end
	function W:GetFrameStrata() return self.strata or "MEDIUM" end
	function W:SetID(id) self.id = id end
	function W:GetID() return self.id or 0 end
	function W:IsMouseOver() return false end
	function W:EnableMouse(on) self.mouse = on and true or false end
	function W:IsMouseEnabled() return self.mouse == true end
	function W:Enable() self.enabled = true end
	function W:Disable() self.enabled = false end
	function W:SetEnabled(on) self.enabled = on and true or false end
	function W:IsEnabled() return self.enabled end
	function W:CreateTexture(name, layer) local t = NewWidget("Texture", name, self, nil, self.blizzard and not FromOlympus(1)); t.layer = layer; return t end
	function W:CreateFontString(name, layer, font) local f = NewWidget("FontString", name, self, nil, self.blizzard and not FromOlympus(1)); f.layer, f.font = layer, font; return f end
	function W:CreateMaskTexture(name) return NewWidget("MaskTexture", name, self) end
	function W:CreateLine(name) return NewWidget("Line", name, self) end
	function W:CreateAnimationGroup(name)
		local g = NewWidget("AnimationGroup", name, nil)
		g.target = self
		return g
	end
	function W:CreateAnimation(kind, name)
		local a = NewWidget(kind or "Animation", name, nil)
		a.group = self
		return a
	end
	function W:GetAnimationGroups() return end
	function W:IsPlaying() return false end
	-- Text: measured at 6 pixels a letter (codes and links left out).
	local function Shown(text) return (tostring(text or ""):gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
	function W:SetText(text)
		self.text = text ~= nil and tostring(text) or nil
		if self.fontString then self.fontString.text = self.text end
	end
	function W:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
	function W:GetText() if self.fontString then return self.fontString.text end return self.text end
	function W:GetStringWidth() return #Shown(self.text) * 6 end
	function W:GetUnboundedStringWidth() return #Shown(self.text) * 6 end
	function W:GetStringHeight() return 12 end
	function W:GetNumLines() return 1 end
	function W:IsTruncated() return false end
	function W:SetFontObject(font) self.font = font end
	function W:GetFontObject() return self.font end
	function W:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
	function W:SetFont(path, size, flags) self.fontFile = { path, size, flags } return true end
	function W:SetTextColor(...) self.textColor = { ... } end
	function W:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
	function W:GetFontString()
		if not self.fontString then
			self.fontString = NewWidget("FontString", nil, self)
			self.fontString.text = self.text
		end
		return self.fontString
	end
	function W:SetFontString(fs) self.fontString = fs end
	function W:SetNormalFontObject(f) self.normalFont = f end
	function W:SetTexture(t) self.texture = t return true end
	function W:GetTexture() return self.texture end
	function W:SetAtlas(a) self.atlas = a return true end
	function W:GetAtlas() return self.atlas end
	function W:SetColorTexture(...) self.color = { ... } end
	function W:SetVertexColor(...) self.vertex = { ... } end
	function W:GetVertexColor() return unpack(self.vertex or { 1, 1, 1, 1 }) end
	function W:SetTexCoord(...) self.texCoord = { ... } end
	function W:GetTexCoord() return unpack(self.texCoord or { 0, 1, 0, 1 }) end
	function W:SetDrawLayer(layer, sub) self.layer, self.sublayer = layer, sub end
	function W:GetDrawLayer() return self.layer or "ARTWORK", self.sublayer or 0 end
	function W:SetChecked(on) self.checked = on and true or false end
	function W:GetChecked() return self.checked == true end
	function W:SetNormalTexture(t) self.normalTexture = t end
	function W:GetNormalTexture() if type(self.normalTexture) ~= "table" then self.normalTexture = NewWidget("Texture", nil, self) end return self.normalTexture end
	function W:SetHighlightTexture(t) self.highlightTexture = t end
	function W:GetHighlightTexture() if type(self.highlightTexture) ~= "table" then self.highlightTexture = NewWidget("Texture", nil, self) end return self.highlightTexture end
	function W:SetPushedTexture(t) self.pushedTexture = t end
	function W:GetPushedTexture() if type(self.pushedTexture) ~= "table" then self.pushedTexture = NewWidget("Texture", nil, self) end return self.pushedTexture end
	function W:GetDisabledTexture() if type(self.disabledTexture) ~= "table" then self.disabledTexture = NewWidget("Texture", nil, self) end return self.disabledTexture end
	function W:SetDisabledTexture(t) self.disabledTexture = t end
	function W:GetCheckedTexture() if type(self.checkedTexture) ~= "table" then self.checkedTexture = NewWidget("Texture", nil, self) end return self.checkedTexture end
	function W:LockHighlight() self.locked = true end
	function W:UnlockHighlight() self.locked = false end
	function W:GetButtonState() return "NORMAL" end
	-- A click from Olympus's own code (not the player's): its script, no hardware event.
	function W:Click(button) C.RunScript(self, "OnClick", button or "LeftButton", false) end
	-- Edit boxes.
	function W:SetFocus() C.focus = self end
	function W:ClearFocus() if C.focus == self then C.focus = nil end end
	function W:HasFocus() return C.focus == self end
	function W:SetMaxLetters(n) self.maxLetters = n end
	function W:GetMaxLetters() return self.maxLetters or 0 end
	function W:SetCursorPosition(p) self.cursor = p end
	function W:GetCursorPosition() return self.cursor or 0 end
	function W:HighlightText() end
	function W:SetAutoFocus(on) self.autoFocus = on end
	function W:SetMultiLine(on) self.multiLine = on end
	function W:IsMultiLine() return self.multiLine == true end
	function W:GetNumLetters() return #(self.text or "") end
	-- Scroll frames.
	function W:SetScrollChild(c) self.scrollChild = c end
	function W:GetScrollChild() return self.scrollChild end
	function W:GetVerticalScroll() return self.vscroll or 0 end
	function W:SetVerticalScroll(v) self.vscroll = v end
	function W:GetVerticalScrollRange() return 0 end
	function W:GetHorizontalScroll() return 0 end
	function W:UpdateScrollChildRect() end
	-- Sliders and status bars.
	function W:SetMinMaxValues(a, b) self.min, self.max = a, b end
	function W:GetMinMaxValues() return self.min or 0, self.max or 0 end
	function W:SetValue(v) self.value = v end
	function W:GetValue() return self.value or 0 end
	function W:GetThumbTexture() return NewWidget("Texture", nil, self) end
	-- Tooltips (GameTooltip): who owns it and its lines.
	function W:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {}; self.shown = true end
	function W:GetOwner() return self.owner end
	function W:IsOwned(owner) return self.owner == owner end
	function W:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = tostring(text) end
	function W:AddDoubleLine(a, b) self.lines = self.lines or {}; self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
	function W:ClearLines() self.lines = {} end
	function W:NumLines() return #(self.lines or {}) end
	function W:SetMinimumWidth(w) self.minWidth = w end
	-- (The unit a tooltip shows: its name and unit token, as the game's GameTooltip:GetUnit.)
	function W:GetUnit() if self.unit then return E.UnitName(self.unit), self.unit end end
	function W:SetUnit(unit) self.unit = unit; self.lines = {} end
	function W:SetPadding() end
	-- Minimap.
	function W:GetZoom() return 0 end
	-- Message frames (the chat windows): what was printed.
	function W:AddMessage(text, ...)
		C.printed[#C.printed + 1] = tostring(text)
		self.messages = self.messages or {}
		self.messages[#self.messages + 1] = tostring(text)
	end
	-- The template's own (BackdropTemplateMixin): kept as set.
	function W:SetBackdrop(b) self.backdrop = b end
	function W:GetBackdrop() return self.backdrop end
	function W:SetBackdropColor(...) self.backdropColor = { ... } end
	function W:SetBackdropBorderColor(...) self.backdropBorder = { ... } end
	function W:SetFixedFrameStrata(on) self.fixedStrata = on end
	function W:SetFixedFrameLevel(on) self.fixedLevel = on end
	function W:SetToplevel(on) self.toplevel = on end
	function W:SetMovable(on) self.movable = on end
	function W:IsMovable() return self.movable == true end
	function W:SetResizable(on) self.resizable = on end
	function W:SetClampedToScreen(on) self.clamped = on end
	function W:StartMoving() end
	function W:StopMovingOrSizing() end
	function W:SetUserPlaced(on) self.userPlaced = on end
	function W:IsUserPlaced() return self.userPlaced == true end
	function W:SetHitRectInsets(...) self.hitRect = { ... } end
	function W:SetJustifyH(j) self.justifyH = j end
	function W:GetJustifyH() return self.justifyH or "CENTER" end
	function W:SetJustifyV(j) self.justifyV = j end
	function W:SetWordWrap(on) self.wrap = on end
	function W:SetNonSpaceWrap(on) self.nonSpaceWrap = on end
	function W:SetMaxLines(n) self.maxLines = n end
	function W:SetSpacing(n) self.spacing = n end
	function W:SetShadowOffset(...) self.shadow = { ... } end
	function W:SetShadowColor(...) self.shadowColor = { ... } end
	function W:SetIgnoreParentAlpha(on) self.ignoreAlpha = on end
	function W:SetIgnoreParentScale(on) self.ignoreScale = on end
	function W:SetBlendMode(m) self.blend = m end
	function W:SetDesaturated(on) self.desaturated = on end
	function W:SetRotation(r) self.rotation = r end
	function W:SetHorizTile(on) self.horizTile = on end
	function W:SetVertTile(on) self.vertTile = on end
	function W:SetClipsChildren(on) self.clips = on end
	function W:SetPropagateKeyboardInput(on) self.propagate = on end
	function W:EnableKeyboard(on) self.keyboard = on end
	function W:EnableMouseWheel(on) self.wheel = on end
	function W:RegisterForClicks(...) self.clicks = { ... } end
	function W:RegisterForDrag(...) self.drag = { ... } end
	function W:SetMotionScriptsWhileDisabled(on) self.motionDisabled = on end

	-- Scripts run: the frame's own, then its hooks (the client's order for HookScript).
	function C.RunScript(w, kind, ...)
		local fn = w.scripts[kind]
		if fn then fn(w, ...) end
		for _, h in ipairs(w.hooks[kind] or {}) do h(w, ...) end
	end
	function C.Fire1(w, kind) C.RunScript(w, kind) end

	-- A callback the game calls isolated (securecallfunction: a menu's, a tooltip post-call, a
	-- filter's): an error goes to the error handler, the game goes on.
	C.isolatedErrors = {}
	function C.Isolated(fn, ...)
		local ok, err = xpcall(fn, debug.traceback, ...)
		if not ok then C.isolatedErrors[#C.isolatedErrors + 1] = err; pcall(C.handler, err) end
		return ok
	end
	-- The player's click on a button: the hardware event restricted calls need.
	function C.Click(w, mouse)
		assert(w:IsVisible(), "clicked a button that doesn't show: " .. tostring(w.name or w.kind))
		C.clicking = true
		local ok, err = pcall(function()
			C.RunScript(w, "OnClick", mouse or "LeftButton", true)
			C.RunScript(w, "PostClick", mouse or "LeftButton", true)
		end)
		C.clicking = false
		if not ok then error(err, 0) end
	end

	------------------------------------------------------------------
	-- Events and time.
	------------------------------------------------------------------
	function C.Fire(event, ...)
		local list = {}
		for f in pairs(C.eventFrames[event] or {}) do list[#list + 1] = f end
		table.sort(list, function(a, b) return rawget(a, "seq") < rawget(b, "seq") end)
		for _, f in ipairs(list) do
			local fn = f.scripts.OnEvent
			if fn then fn(f, event, ...) end
		end
	end
	function C.After(seconds, fn)
		C.timers[#C.timers + 1] = { at = C.clock + math.max(0, tonumber(seconds) or 0), fn = fn, seq = #C.timers }
	end
	-- Time goes by: due timers and tickers run in order, OnUpdate scripts once a step.
	function C.Advance(seconds)
		local stop = C.clock + (seconds or 0)
		local guard = 0
		while true do
			guard = guard + 1
			assert(guard < 100000, "timers run away")
			table.sort(C.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
			local t = C.timers[1]
			local nextTick
			for _, k in ipairs(C.tickers) do
				if not k.cancelled and (not nextTick or k.at < nextTick.at) then nextTick = k end
			end
			local due = t and t.at <= stop and t
			local tickDue = nextTick and nextTick.at <= stop and nextTick
			if due and (not tickDue or due.at <= tickDue.at) then
				table.remove(C.timers, 1)
				C.clock = math.max(C.clock, due.at)
				due.fn()
			elseif tickDue then
				C.clock = math.max(C.clock, tickDue.at)
				tickDue.at = tickDue.at + tickDue.every
				tickDue.n = tickDue.n + 1
				if tickDue.iterations and tickDue.n >= tickDue.iterations then tickDue.cancelled = true end
				tickDue.fn(tickDue)
			else
				break
			end
		end
		local elapsed = stop - C.clock
		C.clock = stop
		for w in pairs(C.updating) do
			if w.scripts.OnUpdate and w:IsVisible() then w.scripts.OnUpdate(w, math.max(elapsed, 0.016)) end
		end
	end

	------------------------------------------------------------------
	-- The globals: Lua's (the client's Lua 5.1 and its own additions), then the game's.
	------------------------------------------------------------------
	for _, k in ipairs(LUA) do E[k] = _G[k] end
	E._G = E
	-- print: a line in the main chat window (Blizzard_PrintHandler sends it to DEFAULT_CHAT_FRAME).
	E.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		C.printed[#C.printed + 1] = table.concat(parts, " ")
	end
	-- The client's Lua additions (Blizzard's code reads them as globals; the fixture says "used").
	E.strsplit = function(sep, s, limit)
		local out, start = {}, 1
		s = tostring(s)
		while true do
			if limit and #out == limit - 1 then out[#out + 1] = s:sub(start) break end
			local i, j = s:find(sep, start, true)
			if not i then out[#out + 1] = s:sub(start) break end
			out[#out + 1] = s:sub(start, i - 1)
			start = j + 1
		end
		return unpack(out)
	end
	E.strtrim = function(s, chars)
		chars = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "%s"
		return (tostring(s):gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
	end
	E.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
	E.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	E.tinsert, E.tremove, E.format, E.strlen, E.strsub, E.strfind, E.strmatch, E.gsub = table.insert, table.remove,
		string.format, string.len, string.sub, string.find, string.match, string.gsub
	E.strlower, E.strupper, E.strrep, E.strbyte, E.strchar = string.lower, string.upper, string.rep, string.byte, string.char
	E.floor, E.ceil, E.abs, E.min, E.max, E.sqrt, E.random, E.sort = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.random, table.sort
	E.time = function(t) if t then return os.time(t) end return C.now end
	E.date = function(fmt, t) return os.date(fmt, t or C.now) end
	E.GetTime = function() return C.clock end
	E.GetServerTime = function() return C.now end
	E.debugprofilestop = function() return C.clock * 1000 end
	E.debugstack = function() return debug.traceback("", 2) end
	-- Secret values (the client's issecretvalue): none in the pass.
	E.issecretvalue = function() return false end
	-- issecurevariable (the taint model, as far as the pass needs it): the game's own tables and
	-- globals, as the model made them, are secure; a table Olympus's code made (its own, or the
	-- map library's in Olympus/libs), or a global it wrote, is Olympus's: false, "Olympus".
	C.gameTables = setmetatable({}, { __mode = "k" })
	C.gameValues = {}
	E.issecurevariable = function(t, key)
		if key == nil then
			if rawget(E, t) == C.gameValues[t] then return true, nil end
			return false, "Olympus"
		end
		if type(t) == "table" and C.gameTables[t] then return true, nil end
		return false, "Olympus"
	end
	-- (After the world is made: everything in it is the game's.)
	function C.SealGame()
		local function Mark(t, depth)
			if type(t) ~= "table" or C.gameTables[t] or depth > 4 then return end
			C.gameTables[t] = true
			for _, v in pairs(t) do Mark(v, depth + 1) end
		end
		for k, v in pairs(E) do
			C.gameValues[k] = v
			if k ~= "_G" then Mark(v, 1) end
		end
	end
	-- The error handler: the game's own, until an addon sets one.
	local gameHandler = function(err) C.gameErrors = (C.gameErrors or 0) + 1 end
	C.handler = gameHandler
	C.gameHandler = gameHandler
	E.geterrorhandler = function() return C.handler end
	E.seterrorhandler = function(fn)
		if FromOlympus(1) then C.Record("seterrorhandler", "call", 1) end
		C.handler = fn
	end
	E.securecallfunction = function(fn, ...) return fn(...) end
	E.securecall = function(fn, ...) if type(fn) == "string" then fn = E[fn] end return fn(...) end
	E.InCombatLockdown = function() return C.combat == true end
	E.IsLoggedIn = function() return C.loggedIn == true end
	E.IsShiftKeyDown = function() return C.shift == true end
	E.IsControlKeyDown = function() return false end
	E.IsAltKeyDown = function() return false end
	E.GetCursorPosition = function() return 0, 0 end
	E.GetLocale = function() return "enUS" end
	E.GetBuildInfo = function() return "1.60.1", tostring(FIX.build), "Oct 1 2026", 16001 end
	-- (The realm: "Realm", or one a session sets, C.realmName.)
	C.realmName = "Realm"
	E.GetRealmName = function() return C.realmName end
	E.GetNormalizedRealmName = function() return (C.realmName:gsub("[%s%-]", "")) end
	E.GetRealmID = function() return 1 end
	-- Units: the player, and whoever a flow puts under the cursor or targets (C.units).
	-- (opts.surname: a Forever player, whose name has a surname where a realm would be.)
	C.units = { player = { name = "Tester", realm = opts.surname or "Realm", guid = "Player-1-00000001", guild = "Olympus II", rank = "Hero", rankIndex = 2 } }
	local function U(unit) return C.units[unit] end
	E.UnitFullName = function(unit) local u = U(unit); if u then return u.name, u.realm end end
	E.UnitName = function(unit) local u = U(unit); if u then return u.name, u.realm ~= C.realmName and u.realm or nil end end
	E.UnitGUID = function(unit) local u = U(unit); return u and u.guid end
	E.UnitFactionGroup = function(unit) if U(unit) then return "Alliance", "Alliance" end end
	E.UnitExists = function(unit) return U(unit) ~= nil end
	E.UnitIsPlayer = function(unit) local u = U(unit); return u ~= nil and tostring(u.guid):find("^Player%-") ~= nil end
	E.UnitLevel = function(unit) return U(unit) and 60 or 0 end
	E.UnitClass = function(unit) if U(unit) then return "Warrior", "WARRIOR", 1 end end
	E.IsInGuild = function() return true end
	E.GetGuildInfo = function(unit) local u = U(unit); if u and u.guild then return u.guild, u.rank, u.rankIndex end end
	E.IsInInstance = function() return false, "none" end
	E.IsInGroup = function() return false end
	E.IsInRaid = function() return false end
	E.GetNumGroupMembers = function() return 0 end
	E.PlaySound = function() end
	E.GetMaxPlayerLevel = function() return 60 end
	E.GetMoney = function() return C.money or 0 end

	-- The input style (fidelity rule 1): values from the documentation.
	local ENUM = {}
	for name, values in pairs(FIX.enums) do if values then ENUM[name] = values end end
	E.Enum = setmetatable(ENUM, { __index = function(_, k)
		if FIX.enums[k] == false then return nil end -- (the documentation has no such Enum table)
		error(("Enum.%s: not in tests/fixtures/forever-api.lua (run scripts/forever-api.lua)"):format(tostring(k)), 2)
	end })
	E.Constants = FIX.constants
	E.C_InputInterfaceStyle = { GetCurrentStyle = function() return C.style end }
	function C.Switch(gamepad)
		local new = gamepad and E.Enum.InputDeviceInterfaceType.Gamepad or E.Enum.InputDeviceInterfaceType.Mkb
		local old = C.style
		if new == old then return end
		C.style = new
		local mark = C.Mark()
		C.Fire("INPUT_DEVICE_INTERFACE_TRANSITION", new, old)
		C.switchLedger = C.Since(mark)
	end

	-- Timers (rule 6).
	E.C_Timer = {
		After = function(seconds, fn) C.After(seconds, fn) end,
		NewTicker = function(every, fn, iterations)
			local k = { every = every, fn = fn, at = C.clock + every, n = 0, iterations = iterations }
			function k.Cancel() k.cancelled = true end
			function k.IsCancelled() return k.cancelled == true end
			C.tickers[#C.tickers + 1] = k
			return k
		end,
		NewTimer = function(seconds, fn)
			local k = { cancelled = false }
			function k.Cancel() k.cancelled = true end
			function k.IsCancelled() return k.cancelled end
			C.After(seconds, function() if not k.cancelled then fn(k) end end)
			return k
		end,
	}

	-- Frames.
	E.CreateFrame = function(kind, name, parent, template)
		local w = NewWidget(kind, name, parent, template, false)
		w.olympus = FromOlympus(1) -- (else the model's own, a pool of the game's)
		-- (Olympus's frames hang from UIParent, the screen's root: no reach. Inside another of the game's, one.)
		if parent and parent.blizzard and parent ~= E.UIParent and FromOlympus(1) then
			C.Record((rawget(parent, "name") or rawget(parent, "path") or "?") .. " <- " .. (name or kind), "parent", 1)
		end
		return w
	end
	C.callbacks = {}

	-- The strict environment (rule 5). (opts.discover, for working on the model: an unmodelled
	-- name is noted and answers a callable stand-in instead of failing.)
	local function Probe(name)
		return setmetatable({}, {
			__index = function(_, k) C.unmodelled[name .. "." .. tostring(k)] = true return Probe(name .. "." .. tostring(k)) end,
			__call = function() C.unmodelled[name .. "()"] = true return nil end,
		})
	end
	-- Names the client has but not now (an addon not loaded yet), each with why: nil.
	C.absent = {}
	function C.Absent(name, why) C.absent[name] = why end
	setmetatable(E, {
		__index = function(_, k)
			if C.absent[k] then return nil end
			local kind = FIX.globals[k]
			if kind == nil then
				if type(k) == "string" and AUDIT.Own(k) then return nil end
				C.unmodelled[tostring(k)] = true
				if opts.discover then return Probe(tostring(k)) end
				error(("the addon reads the global %s, which tests/fixtures/forever-api.lua doesn't know (run scripts/forever-api.lua)"):format(tostring(k)), 2)
			elseif kind then
				C.unmodelled[k] = true
				if opts.discover then return Probe(k) end
				error(("unmodelled API %s: the client has it (%s); model it in tests/gamepad.lua"):format(k, kind), 2)
			end
			return nil
		end,
	})
	C.Probe = Probe
	return C
end

---------------------------------------------------------------------------
-- The game's side: its frames, its functions, its tables. Each modelled from what Forever's UI
-- source shows (the fixture, the files cited), as far as Olympus uses it.
---------------------------------------------------------------------------

local function World(C, opts)
	local E = C.env
	opts = opts or {}
	local Namespace
	-- A namespace (C_FriendList...): the members modelled; one the client has that isn't
	-- modelled fails, one it lacks is nil.
	function Namespace(name, members)
		return setmetatable(members, { __index = function(_, k)
			local full = name .. "." .. tostring(k)
			local kind = FIX.members[full]
			if kind == nil then
				C.unmodelled[full] = true
				if opts.discover then return C.Probe(full) end
				error(("the addon reads %s, which tests/fixtures/forever-api.lua doesn't know (run scripts/forever-api.lua)"):format(full), 2)
			elseif kind then
				C.unmodelled[full] = true
				if opts.discover then return C.Probe(full) end
				error(("unmodelled API %s: the client has it (%s); model it in tests/gamepad.lua"):format(full, kind), 2)
			end
			return nil
		end })
	end
	C.Namespace = Namespace
	E.C_Timer = Namespace("C_Timer", E.C_Timer)
	E.C_InputInterfaceStyle = Namespace("C_InputInterfaceStyle", E.C_InputInterfaceStyle)
	-- A function the audit counts as a reach: each call from Olympus's code goes in the ledger.
	local function Reach(name, fn)
		return function(...)
			if FromOlympus(1) then C.Record(name, "call", 1) end
			return fn(...)
		end
	end
	-- A restricted function (fidelity rule 4): from Olympus's code outside the player's click, the
	-- game refuses it and sends ADDON_ACTION_BLOCKED; inside a click, it runs.
	local function Restricted(name, fn)
		return function(...)
			if FromOlympus(1) then
				local r = C.Record(name, "call", 1)
				if not C.clicking then
					r.kind = "blocked"
					C.blocked[#C.blocked + 1] = name
					C.After(0, function() C.Fire("ADDON_ACTION_BLOCKED", "Olympus", name .. "()") end)
					return nil
				end
			end
			return fn(...)
		end
	end
	local function Fn(name, fn)
		local full = name
		if FIX.restricted[full] then return Restricted(full, fn) end
		local base, member = name:match("^([^%.]+)%.(.+)$")
		local ns = base and AUDIT.NAMESPACES[base]
		if AUDIT.REACH[name] or (base and AUDIT.REACH[base]) or (ns and ns.reach[member]) then return Reach(name, fn) end
		return fn
	end
	C.Fn = Fn

	-- The game's frames: the type, keys and mixin methods its XML gives it (the fixture's frames),
	-- else the type given here.
	local function Blizz(name, kind, parent)
		local def = FIX.frames[name]
		local w = C.NewWidget(def and def.type or kind, name, parent or E.UIParent, nil, true)
		if def then
			w.templateMethods = Set(def.methods)
			for key, spec in pairs(def.keys) do
				local ktype, inherits, kname = Key(spec)
				if WIDGET_METHODS[ktype] and rawget(w, key) == nil then
					local ok, child = pcall(C.NewWidget, ktype, kname, w, inherits, true)
					if not ok then child = C.NewWidget(ktype, kname, w, nil, true) end
					rawset(child, "path", name .. "." .. key)
					rawset(child, "fromKey", true) -- (named "$parent..." by the client's own XML)
					rawset(w, key, child)
				end
			end
		end
		C.frames[name] = w
		return w
	end
	C.Blizz = Blizz
	-- A method of the game's own Lua (a mixin's) on one of its frames: what it does here, and the
	-- call from Olympus's code in the ledger.
	local function Method(w, key, fn)
		rawset(w, key, function(self, ...)
			if FromOlympus(1) and not AUDIT.READS[key] then C.Record((w.name or "?") .. ":" .. key, "method", 1) end
			return fn(self, ...)
		end)
	end
	C.Method = Method

	E.UIParent = C.NewWidget("Frame", "UIParent", nil, nil, true)
	E.UIParent.rect = { 0, 0, 1366, 768 }
	E.UIParent.w, E.UIParent.h = 1366, 768
	E.GetPhysicalScreenSize = function() return 1366, 768 end
	E.GameTooltip = Blizz("GameTooltip", "GameTooltip")
	E.GameTooltip.shown = false
	E.Minimap = Blizz("Minimap", "Minimap")
	E.Minimap.w, E.Minimap.h, E.Minimap.rect = 140, 140, { 1210, 610, 140, 140 }
	E.C_Minimap = Namespace("C_Minimap", { GetViewRadius = function() return 100 end })

	-- Fonts (the game's font objects, read by name).
	for name, kind in pairs(FIX.globals) do
		if kind == "font" then E[name] = C.NewWidget("Font", name, nil, nil, true) end
	end
	E.ChatFontNormal = E.ChatFontNormal or C.NewWidget("Font", "ChatFontNormal", nil, nil, true)
	E.QuestFont = E.QuestFont or C.NewWidget("Font", "QuestFont", nil, nil, true)

	-- The chat windows (Blizzard_ChatFrameBase: ChatFrame1..10, DEFAULT_CHAT_FRAME = ChatFrame1,
	-- ChatFrameUtil.lua:19), their tabs and edit box.
	E.NUM_CHAT_WINDOWS = 10
	for i = 1, 10 do
		local f = Blizz("ChatFrame" .. i, "ScrollingMessageFrame")
		f.shown = i <= 2
		f.chatIndex = i
		local tab = Blizz("ChatFrame" .. i .. "Tab", "Button")
		tab.shown = i <= 2
	end
	E.DEFAULT_CHAT_FRAME = E.ChatFrame1
	E.SELECTED_CHAT_FRAME = E.ChatFrame1
	-- (ChatFrame1's own edit box, its template's "$parentEditBox".)
	E.ChatFrame1EditBox = rawget(E, "ChatFrame1EditBox") or Blizz("ChatFrame1EditBox", "EditBox")
	E.ChatFrame1EditBox.shown = false
	local windows = { "General", "Combat Log" }
	E.GetChatWindowInfo = function(i)
		if i < 1 or i > 10 then return nil end
		return windows[i] or "", 14, 1, 1, 1, 1, i <= 2, false, i == 1 and 1 or 0, false
	end
	E.FCF_GetChatWindowInfo = E.GetChatWindowInfo
	E.GetChatWindowChannels = function() return end
	E.GetChatWindowMessages = function() return end
	E.IsCombatLog = function(f) return f == E.ChatFrame2 end
	E.ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, id = 1 } end })
	E.NEW_CHAT_WINDOW, E.CHAT_CONFIGURATION = "New Window", "Chat Configuration"
	E.YES, E.NO, E.OKAY, E.ACCEPT, E.CANCEL, E.SEND_LABEL, E.UNKNOWNOBJECT = "Yes", "No", "Okay", "Accept", "Cancel", "Send", "Unknown"
	E.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."

	-- The game's chat box (fidelity rule 8): opened, it is the last active edit box, which the
	-- gamepad chat reads.
	local function ChatBox(text)
		C.chatBox = { text = text }
		E.ACTIVE_CHAT_EDIT_BOX = E.ChatFrame1EditBox
		E.LAST_ACTIVE_CHAT_EDIT_BOX = E.ChatFrame1EditBox
		E.ChatFrame1EditBox:Show()
		E.ChatFrame1EditBox.text = text
	end
	E.ChatFrame_OpenChat = Fn("ChatFrame_OpenChat", function(text) ChatBox(text) end)
	E.ChatFrame_SendTell = Fn("ChatFrame_SendTell", function(name) ChatBox("/w " .. tostring(name) .. " ") end)
	E.ChatEdit_InsertLink = Fn("ChatEdit_InsertLink", function(link) if C.chatBox then C.chatBox.text = (C.chatBox.text or "") .. link return true end return false end)
	E.ChatFrame_RemoveChannel = Fn("ChatFrame_RemoveChannel", function(frame, name) C.removedChannels = (C.removedChannels or 0) + 1 end)
	E.GetCurrentKeyBoardFocus = function() return C.focus end

	-- Channels (the census channel): joined, numbered, listed.
	C.channels = {}
	E.JoinChannelByName = Fn("JoinChannelByName", function(name)
		if not C.channels[name] then C.channels[name] = #C.channels + 5 end
		C.After(0.5, function() C.Fire("CHANNEL_UI_UPDATE") end)
	end)
	E.LeaveChannelByName = Fn("LeaveChannelByName", function(name) C.channels[name] = nil end)
	E.GetChannelName = function(id)
		for name, n in pairs(C.channels) do
			if id == name or id == n then return n, name end
		end
		return 0, nil
	end
	E.GetChannelList = function()
		local out = {}
		for name, n in pairs(C.channels) do out[#out + 1] = n; out[#out + 1] = name; out[#out + 1] = false end
		return unpack(out)
	end
	E.GetNumDisplayChannels = function() return 0 end
	E.GetChannelDisplayInfo = function() return nil end
	E.SetChannelPassword = function() end
	E.ChannelUnban = function() end

	-- Addon messages (Olympus's comm): what it sends, kept.
	C.sent = {}
	local prefixes = {}
	E.C_ChatInfo = Namespace("C_ChatInfo", {
		RegisterAddonMessagePrefix = function(p) prefixes[p] = true return true end,
		IsAddonMessagePrefixRegistered = function(p) return prefixes[p] == true end,
		SendAddonMessage = function(prefix, msg, kind, target) C.sent[#C.sent + 1] = { prefix, msg, kind, target } return 0 end,
		SendAddonMessageLogged = function(prefix, msg, kind, target) C.sent[#C.sent + 1] = { prefix, msg, kind, target } return 0 end,
		InChatMessagingLockdown = function() return false end,
		GetChannelInfoFromIdentifier = function() return nil end,
		SwapChatChannelsByChannelIndex = Fn("C_ChatInfo.SwapChatChannelsByChannelIndex", function() end),
	})
	E.SendChatMessage = Fn("SendChatMessage", function(text, kind, lang, target) C.said = C.said or {}; C.said[#C.said + 1] = { text, kind, target } end)

	-- The guild (Forever's roster: GetGuildRosterInfo, as Roster.lua reads it).
	C.roster = opts.roster or {
		{ "Tester-Realm", "Hero", 2, 60, "Warrior", "Elwynn Forest", "", "", true, 0, "WARRIOR" },
		{ "Zeusmaster-Realm", "Zeus", 0, 60, "Mage", "Stormwind City", "", "", true, 0, "MAGE" },
		{ "Titanbold-Realm", "Titan", 1, 58, "Priest", "Westfall", "", "", false, 0, "PRIEST" },
	}
	E.GetNumGuildMembers = function() local online = 0 for _, m in ipairs(C.roster) do if m[9] then online = online + 1 end end return #C.roster, online, online end
	E.GetGuildRosterInfo = function(i) local m = C.roster[i]; if m then return unpack(m, 1, 11) end end
	E.GuildControlGetNumRanks = function() return 4 end
	E.GuildControlGetRankName = function(i) return ({ "Zeus", "Titan", "Hero", "Recruit" })[i] end
	E.CanGuildInvite = function() return true end
	E.CanGuildRemove = function() return false end
	E.C_GuildInfo = Namespace("C_GuildInfo", {
		GuildRoster = function() C.After(0.2, function() C.Fire("GUILD_ROSTER_UPDATE", false) end) end,
		AreGuildEventsEnabled = function() return true end,
		Invite = Fn("C_GuildInfo.Invite", function() end),
		Uninvite = Fn("C_GuildInfo.Uninvite", function() end),
	})
	E.GuildInvite = Fn("GuildInvite", function() end)
	E.GuildUninvite = Fn("GuildUninvite", function() end)

	-- Units, the group, the map.
	E.UnitIsConnected = function() return true end
	E.UnitIsDND = function() return false end
	E.UnitIsFriend = function() return true end
	E.UnitCanAttack = function() return false end
	E.UnitIsUnit = function(a, b) return a == b end
	E.UnitIsGroupLeader = function() return false end
	E.UnitIsGroupAssistant = function() return false end
	E.UnitPosition = function() return nil end
	E.GetPlayerFacing = function() return nil end
	E.GetUnitName = function(unit) return E.UnitName(unit) end
	E.RegionalUniqueNamesEnabled = function() return false end
	E.GetNativeRealmID = function() return 1 end
	E.CheckInteractDistance = function() return false end
	E.CanInspect = function() return false end
	E.NotifyInspect = Fn("NotifyInspect", function() end)
	E.ClearInspectPlayer = Fn("ClearInspectPlayer", function() end)
	E.GetInventoryItemID = function() return nil end
	E.GetInventoryItemLink = function() return nil end
	E.INVSLOT_TABARD = 19
	E.C_PartyInfo = Namespace("C_PartyInfo", {
		InviteUnit = Fn("C_PartyInfo.InviteUnit", function(name) C.invited = name end),
		LeaveParty = Fn("C_PartyInfo.LeaveParty", function() C.left = true end),
	})
	E.AcceptGroup = Fn("AcceptGroup", function() C.accepted = true end)
	E.GetZoneText = function() return "Elwynn Forest" end
	E.GetRealZoneText = function() return "Elwynn Forest" end
	E.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", PALADIN = "Paladin" }
	E.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
	E.SOUNDKIT = setmetatable({}, { __index = function(_, k)
		if FIX.members["SOUNDKIT." .. tostring(k)] == false then return nil end
		return 1
	end })
	E.PlaySound = function() end
	E.GetCVar = function(name) if name == "rotateMinimap" then return "0" end if name == "minimapZoom" then return "0" end return nil end
	E.C_CVar = Namespace("C_CVar", { GetCVar = function(name) return E.GetCVar(name) end })
	E.WOW_PROJECT_CLASSIC, E.WOW_PROJECT_ID = 2, 18 -- (Blizzard_ProjectConstants/Camelot: WOW_PROJECT_CAMELOT = 18)
	E.GetFileIDFromPath = function() return nil end
	E.GetTimePreciseSec = function() return C.clock end
	E.C_DateAndTime = Namespace("C_DateAndTime", {
		GetCurrentCalendarTime = function() local t = os.date("*t", C.now) return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min } end,
		GetSecondsUntilWeeklyReset = function() return 3 * 86400 end,
	})
	E.C_GameRules = Namespace("C_GameRules", { IsGameRuleActive = function() return false end })
	E.C_Texture = Namespace("C_Texture", { GetAtlasInfo = function(a) return { width = 64, height = 64, file = a } end })
	E.C_Item = Namespace("C_Item", {
		GetItemIconByID = function() return 134400 end,
		GetItemNameByID = function() return nil end,
		GetItemCount = function() return 0 end,
	})
	E.C_AddOns = Namespace("C_AddOns", {
		IsAddOnLoaded = function(name) return C.loadedAddOns[name] == true end,
		LoadAddOn = Fn("C_AddOns.LoadAddOn", function(name)
			if name == "Blizzard_WorldMap" and not rawget(E, "WorldMapFrame") then
				C.absent.WorldMapFrame = nil
				C.MakeWorldMap()
				C.loadedWorldMap = true
			end
			C.loadedAddOns[name] = true
			return true
		end),
	})
	C.loadedAddOns = { Blizzard_WorldMap = not opts.worldMapOnDemand }
	-- (The game's default key for "Open chat", Enter: Bindings.xml's OPENCHAT.)
	E.GetBindingKey = function(action) if action == "OPENCHAT" then return "ENTER" end return nil end
	E.GetBindingText = function(k) return k end
	E.SetOverrideBindingClick = Fn("SetOverrideBindingClick", function(owner, prio, key, button) C.bindings = C.bindings or {}; C.bindings[key] = button end)
	E.ClearOverrideBindings = Fn("ClearOverrideBindings", function() C.bindings = {} end)
	E.ReloadUI = Fn("ReloadUI", function() C.reloaded = true end)

	-- The world map (Blizzard_MapCanvas, the gamepad map's own: a canvas in a scroll container,
	-- data providers and pin pools), on a world of five maps (the harness's, run.lua's MAPS).
	local MAPS = {
		[947] = { "Azeroth", 1, 946 }, [1415] = { "Eastern Kingdoms", 2, 947 }, [1429] = { "Elwynn Forest", 3, 1415 },
		[1453] = { "Stormwind City", 3, 1415 }, [1436] = { "Westfall", 3, 1415 },
	}
	local CHILDREN = { [947] = { 1415 }, [1415] = { 1429, 1453, 1436 } }
	local function Info(id) local m = MAPS[id]; return m and { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] } end
	local function Vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
	E.CreateVector2D = function(x, y) return Vec(x, y) end
	E.C_Map = Namespace("C_Map", {
		GetMapInfo = Info,
		GetMapChildrenInfo = function(id)
			local out = {}
			for _, c in ipairs(CHILDREN[id] or {}) do out[#out + 1] = Info(c) end
			return out
		end,
		GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() return Vec(0.5, 0.5) end,
		GetWorldPosFromMapPos = function(id, pos) return 0, Vec(pos.x * 1000, pos.y * 1000) end,
		GetMapWorldSize = function() return 1000, 1000 end,
		GetMapRectOnMap = function() return 0, 1, 0, 1 end,
		GetMapGroupID = function() return nil end,
		GetMapGroupMembersInfo = function() return nil end,
	})
	E.Lerp = function(a, b, t) return a + (b - a) * t end
	E.Mixin = function(object, ...)
		for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do object[k] = v end end
		return object
	end
	E.CreateFromMixins = function(...) return E.Mixin({}, ...) end
	-- MapCanvas_DataProviderBase.lua: OnAdded, RemoveAllData, RefreshAllData, GetMap, OnMapChanged.
	E.MapCanvasDataProviderMixin = {
		OnAdded = function(self, map) self.owningMap = map end,
		OnRemoved = function(self) self.owningMap = nil end,
		RemoveAllData = function() end,
		RefreshAllData = function() end,
		GetMap = function(self) return self.owningMap end,
		OnMapChanged = function(self) self:RefreshAllData() end,
		OnShow = function() end, OnHide = function() end, OnEvent = function() end,
	}
	E.MapCanvasPinMixin = {
		OnLoad = function() end, SetPosition = function(self, x, y) self.x, self.y = x, y end,
		UseFrameLevelType = function() end, GetMap = function(self) return self.owningMap end,
		OnAcquired = function() end, OnReleased = function() end,
	}
	-- A pool (Blizzard_SharedXMLBase/Pools.lua, ObjectPoolMixin and CreateUnsecuredRegionPoolInstance:
	-- createFunc(pool) and resetFunc(pool, object) kept as fields, set later by its user if not given).
	local function Pool(template, createFunc, resetFunc)
		local p = { createFunc = createFunc, resetFunc = resetFunc or function(_, o) o:Hide(); o:ClearAllPoints() end,
			activeObjects = {}, inactiveObjects = {}, activeObjectCount = 0 }
		function p:GetTemplate() return template end
		function p:Acquire()
			local o = table.remove(self.inactiveObjects)
			local new = o == nil
			if new then o = self.createFunc(self) end
			self.activeObjects[o] = true
			self.activeObjectCount = self.activeObjectCount + 1
			return o, new
		end
		function p:Release(o)
			if not self.activeObjects[o] then return false end
			self.resetFunc(self, o)
			self.activeObjects[o] = nil
			self.activeObjectCount = self.activeObjectCount - 1
			table.insert(self.inactiveObjects, o)
			return true
		end
		function p:ReleaseAll() for o in pairs(self.activeObjects) do self:Release(o) end end
		function p:EnumerateActive() return pairs(self.activeObjects) end
		function p:GetNumActive() return self.activeObjectCount end
		return p
	end
	E.CreateUnsecuredRegionPoolInstance = function(template, createFunc, resetFunc) return Pool(template, createFunc, resetFunc) end
	E.CreateFramePool = function(kind, parent, template, resetFunc)
		return Pool(template, function() return E.CreateFrame(kind, nil, parent, template) end, resetFunc)
	end
	-- (opts.worldMapOnDemand: a client whose Blizzard_WorldMap loads on demand: no map until
	-- C_AddOns.LoadAddOn("Blizzard_WorldMap"). opts.brokenMapLibrary: a map with no pin pools, where
	-- the library's file stops part way as it loads.)
	local map
	function C.MakeWorldMap()
		map = Blizz("WorldMapFrame", "Frame")
		map.shown = false
		map.mapID = 1453
		map.pinPools, map.dataProviders = (not opts.brokenMapLibrary) and {} or nil, {}
		map.marks = 0
		local canvas = C.NewWidget("Frame", nil, rawget(map, "ScrollContainer") or map, nil, true)
		map.ScrollContainer = rawget(map, "ScrollContainer") or C.NewWidget("ScrollFrame", nil, map, nil, true)
		map.ScrollContainer.Child = canvas
		Method(map, "GetCanvas", function() return canvas end)
		Method(map, "GetMapID", function(self) return self.mapID end)
		Method(map, "AddDataProvider", function(self, p) self.dataProviders[p] = true; p:OnAdded(self) end)
		Method(map, "RemoveDataProvider", function(self, p) self.dataProviders[p] = nil end)
		-- MapCanvasMixin:MarkCanvasDirty, from RemoveAllPinsByTemplate and AcquirePin: from Olympus's copy
		-- of the library, in the ledger (the gamepad map runs in its taint after it).
		local function Dirty() map.marks = map.marks + 1; if FromOlympus(2) then C.Record("WorldMapFrame:MarkCanvasDirty", "method", 2) end end
		Method(map, "RemoveAllPinsByTemplate", function(self, t) local p = self.pinPools[t]; if p then p:ReleaseAll() end Dirty() end)
		Method(map, "AcquirePin", function(self, t, ...) local p = self.pinPools[t]; local pin = p:Acquire(); pin.owningMap = self; if pin.OnAcquired then pin:OnAcquired(...) end Dirty() return pin end)
		Method(map, "RemovePin", function(self, pin) for _, p in pairs(self.pinPools) do p:Release(pin) end Dirty() end)
		Method(map, "EnumeratePinsByTemplate", function(self, t) local p = self.pinPools[t]; if p then return p:EnumerateActive() end return pairs({}) end)
		-- (A mixin method, so hooksecurefunc can follow it, as Map.lua's does.)
		rawset(map, "OnMapChanged", function(self) for p in pairs(self.dataProviders) do p:OnMapChanged() end end)
		E.WorldMapFrame = map
		if C.gameTables then
			local function Mark(t, depth) if type(t) == "table" and not C.gameTables[t] and depth < 4 then C.gameTables[t] = true for _, v in pairs(t) do Mark(v, depth + 1) end end end
			Mark(map, 1)
			C.gameValues.WorldMapFrame = map
		end
	end
	if opts.worldMapOnDemand then
		C.Absent("WorldMapFrame", "Blizzard_WorldMap loads on demand on this client")
	else
		C.MakeWorldMap()
	end
	function C.ShowMap() map:Show(); map:OnMapChanged() end
	function C.HideMap() map:Hide() end

	-- The game's popups (Blizzard_StaticPopup: four frames, the definitions in StaticPopupDialogs).
	E.StaticPopupDialogs = {}
	for i = 1, 4 do local p = Blizz("StaticPopup" .. i, "Frame"); p.shown = false end
	local function FindPopup(which, data)
		for i = 1, 4 do
			local p = E["StaticPopup" .. i]
			if p.shown and p.which == which and (data == nil or p.data == data) then return p end
		end
	end
	E.StaticPopup_Show = Fn("StaticPopup_Show", function(which, a, b, data)
		local def = E.StaticPopupDialogs[which]
		if not def then return nil end
		for i = 1, 4 do
			local p = E["StaticPopup" .. i]
			if not p.shown then
				p.which, p.data, p.textArgs = which, data, { a, b }
				p:Show()
				C.gamePopups = (C.gamePopups or 0) + 1
				return p
			end
		end
	end)
	E.StaticPopup_Hide = Fn("StaticPopup_Hide", function(which, data) local p = FindPopup(which, data); if p then p:Hide() end end)
	E.StaticPopup_FindVisible = Fn("StaticPopup_FindVisible", function(which, data) return FindPopup(which, data) end)
	E.StaticPopup_Visible = Fn("StaticPopup_Visible", function(which) local p = FindPopup(which); return p and p:GetName() or nil end)

	-- The game's tables Olympus may read or write: the escape list, the slash commands.
	E.UISpecialFrames = { "GameMenuFrame", "SettingsPanel", "CharacterFrame" }
	E.SlashCmdList = {}

	-- Registrations that keep their callbacks (fidelity rule 2).
	local hooks = {}
	C.secureHooks = hooks
	E.hooksecurefunc = Fn("hooksecurefunc", function(t, key, post)
		if type(t) == "string" then t, key, post = E, t, key end
		local original = rawget(t, key) or t[key]
		assert(type(original) == "function", "hooksecurefunc on something that is no function: " .. tostring(key))
		hooks[#hooks + 1] = { t = t, key = key, post = post }
		C.callbacks[#C.callbacks + 1] = { kind = "hooksecurefunc", key = key, fn = post, frame = t ~= E and t or nil }
		rawset(t, key, function(...)
			local r = { original(...) }
			post(...)
			return unpack(r)
		end)
	end)
	E.Menu = Namespace("Menu", {
		ModifyMenu = Fn("Menu.ModifyMenu", function(tag, fn)
			C.menus[tag] = C.menus[tag] or {}
			table.insert(C.menus[tag], fn)
			C.callbacks[#C.callbacks + 1] = { kind = "Menu.ModifyMenu", tag = tag, fn = fn }
		end),
	})
	E.TooltipDataProcessor = Namespace("TooltipDataProcessor", {
		AddTooltipPostCall = Fn("TooltipDataProcessor.AddTooltipPostCall", function(kind, fn)
			C.postCalls[kind] = C.postCalls[kind] or {}
			table.insert(C.postCalls[kind], fn)
			C.callbacks[#C.callbacks + 1] = { kind = "AddTooltipPostCall", type = kind, fn = fn }
		end),
	})
	E.ChatFrameUtil = Namespace("ChatFrameUtil", {
		AddSenderNameFilter = Fn("ChatFrameUtil.AddSenderNameFilter", function(fn)
			table.insert(C.nameFilters, fn)
			C.callbacks[#C.callbacks + 1] = { kind = "AddSenderNameFilter", fn = fn }
		end),
	})

	-- Restricted and roster calls.
	E.C_FriendList = Namespace("C_FriendList", {
		SendWho = Fn("C_FriendList.SendWho", function(q) C.whos = C.whos or {}; C.whos[#C.whos + 1] = q end),
		SetWhoToUi = Fn("C_FriendList.SetWhoToUi", function(on) C.whoToUi = on end),
		GetNumWhoResults = function() return 0, 0 end,
		GetWhoInfo = function() return nil end,
		IsIgnored = function() return false end,
	})
	E.C_TradeInfo = Namespace("C_TradeInfo", { SetTradeMoney = Fn("C_TradeInfo.SetTradeMoney", function(m) C.tradeMoney = m end) })
	E.RaidWarningFrame = Blizz("RaidWarningFrame", "Frame")
	E.RaidNotice_AddMessage = Fn("RaidNotice_AddMessage", function(frame, text) C.raidNotices = (C.raidNotices or 0) + 1 end)

	-- The game's gamepad UI state, as the taint probe reads it (Diagnostics.lua).
	E.GamepadMode = { FrameControlsManager = { shownFrames = {} }, PopupHandler = { visiblePopups = {} } }
	E.GamepadSharedUtility = { InputBindingManager = { bindingSetStack = {} } }
	E.GamepadMainActionBarFrame = Blizz("GamepadMainActionBarFrame", "Frame")
	E.SmartNavigation = Blizz("SmartNavigation", "Frame")

	-- The guild windows (Blizzard_Communities and the Social window, FriendsFrame): Forever's
	-- guild window is Communities; there is no old GuildFrame (no Blizzard_GuildUI in the client's
	-- source).
	E.FriendsFrame = Blizz("FriendsFrame", "Frame")
	E.FriendsFrame.shown, E.FriendsFrame.w, E.FriendsFrame.h = false, 338, 424
	E.CommunitiesFrame = Blizz("CommunitiesFrame", "Frame")
	E.CommunitiesFrame.shown, E.CommunitiesFrame.w, E.CommunitiesFrame.h = false, 814, 576
	E.LFGWhoListFrame = Blizz("LFGWhoListFrame", "Frame")
	E.LFGWhoListFrame.shown = false
	-- (Forever's who list listens for the answers: Blizzard_GroupFinder_VanillaStyle/Mainline/WhoList.lua:197.)
	E.LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE")
	E.GameMenuFrame = Blizz("GameMenuFrame", "Frame")
	E.GameMenuFrame.shown = false

	-- Unit frames (Borders.lua's rigs).
	E.PlayerFrame = Blizz("PlayerFrame", "Button")
	E.TargetFrame = Blizz("TargetFrame", "Button")
	E.FocusFrame = Blizz("FocusFrame", "Button")
	rawset(E.TargetFrame, "TargetFrameContainer", rawget(E.TargetFrame, "TargetFrameContainer") or C.NewWidget("Frame", nil, E.TargetFrame, nil, true))
	rawset(E.FocusFrame, "TargetFrameContainer", rawget(E.FocusFrame, "TargetFrameContainer") or C.NewWidget("Frame", nil, E.FocusFrame, nil, true))
	rawset(E.TargetFrame, "CheckClassification", function() end)
	rawset(E.FocusFrame, "CheckClassification", function() end)
	rawset(E.PlayerFrame, "name", rawget(E.PlayerFrame, "name") or C.NewWidget("FontString", nil, E.PlayerFrame, nil, true))
	-- Forever's PartyFrame (Blizzard_UnitFrame/Shared/PartyFrame.lua): its four member frames from a
	-- pool, MemberFrame<i> of layoutIndex i, put out again in InitializePartyMemberFrames (Borders.lua's
	-- party rigs read these fields and post-hook that method).
	E.PartyFrame = Blizz("PartyFrame", "Frame")
	rawset(E.PartyFrame, "PartyMemberFramePool", rawget(E.PartyFrame, "PartyMemberFramePool") or {})
	for i = 1, 4 do
		local m = rawget(E.PartyFrame, "MemberFrame" .. i) or C.NewWidget("Button", nil, E.PartyFrame, nil, true)
		rawset(m, "layoutIndex", i)
		rawset(E.PartyFrame, "MemberFrame" .. i, m)
	end
	rawset(E.PartyFrame, "InitializePartyMemberFrames", function() end)

	-- Nameplates (Blizzard_NamePlates): none in sight.
	E.C_NamePlate = Namespace("C_NamePlate", { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return nil end })
	E.CompactUnitFrame_UpdateName = function() end
	E.NamePlateSetupOptions = {}

	-- Templates' helpers (Blizzard_SharedXML: PanelTemplates_*), on Olympus's own tabs.
	E.PanelTemplates_TabResize = function(tab, padding) tab:SetWidth((tab:GetFontString():GetStringWidth() or 0) + (padding or 20)) end
	E.PanelTemplates_SelectTab = function(tab) tab.selectedTab = true end
	E.PanelTemplates_DeselectTab = function(tab) tab.selectedTab = false end
	E.PanelTemplates_AnchorTabs = function() end
	E.SetItemButtonTexture = function(b, t) b.icon = t end
	E.SetItemButtonCount = function(b, n) b.count = n end
	E.SetItemButtonQuality = function(b, q) b.quality = q end

	-- The calendar, mail and trade (load on demand; shown only when a flow opens them).
	E.ToggleCalendar = Fn("ToggleCalendar", function() C.calendarToggled = (C.calendarToggled or 0) + 1 end)
	E.C_Calendar = Namespace("C_Calendar", { OpenCalendar = function() end, GetNumGuildEvents = function() return 0 end, GetGuildEventInfo = function() return nil end })
	E.SendMail = Fn("SendMail", function() end)
	E.TakeInboxMoney = Fn("TakeInboxMoney", function() end)
	E.TakeInboxItem = Fn("TakeInboxItem", function() end)
	E.AutoLootMailItem = Fn("AutoLootMailItem", function() end)
	E.MoneyInputFrame_SetCopper = Fn("MoneyInputFrame_SetCopper", function(f, c) f.copper = c end)
	E.SendMailRadioButton_OnClick = Fn("SendMailRadioButton_OnClick", function() end)
	E.ATTACHMENTS_MAX_SEND, E.ATTACHMENTS_MAX_RECEIVE = 12, 16
	E.GetInboxHeaderInfo = function() return nil end
	E.GetInboxInvoiceInfo = function() return nil end
	E.GetInboxItem = function() return nil end
	E.GetSendMailMoney = function() return 0 end
	E.GetSendMailCOD = function() return 0 end
	E.GetSendMailItem = function() return nil end
	E.GetTargetTradeMoney = function() return 0 end
	E.GetPlayerTradeMoney = function() return 0 end
	E.GetTradePlayerItemInfo = function() return nil end
	E.GetTradeTargetItemInfo = function() return nil end
	E.GetTradePlayerItemLink = function() return nil end
	E.GetTradeTargetItemLink = function() return nil end
	E.TradeFrame = Blizz("TradeFrame", "Frame"); E.TradeFrame.shown = false
	E.MailFrame = Blizz("MailFrame", "Frame"); E.MailFrame.shown = false
	E.SendMailFrame = Blizz("SendMailFrame", "Frame"); E.SendMailFrame.shown = false
	for _, n in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox" }) do E[n] = Blizz(n, "EditBox") end
	for _, n in ipairs({ "SendMailSendMoneyButton", "SendMailCODButton" }) do E[n] = Blizz(n, "CheckButton") end
	E.SendMailMoney = Blizz("SendMailMoney", "Frame")
	C.Absent("InspectFrame", "Blizzard_InspectUI loads on demand: not loaded in the pass")
	C.Absent("CalendarFrame", "Blizzard_Calendar loads on demand: not loaded in the pass")
	C.Absent("GuildFrame", "Forever has no old guild window: no Blizzard_GuildUI in the client's source (its guild window is Communities)")
	C.Absent("PTR_IssueReporter", "Blizzard_PTRFeedback's frame shows on test clients only (a flow of its own adds it)")
	-- The guild bank (a bank character's, Bank.lua): closed.
	E.GetNumGuildBankTabs = function() return 0 end
	E.GetCurrentGuildBankTab = function() return 1 end
	E.GetGuildBankTabInfo = function() return nil end
	E.GetGuildBankItemInfo = function() return nil end
	E.GetGuildBankItemLink = function() return nil end
	E.GetGuildBankMoney = function() return 0 end
	E.QueryGuildBankTab = function() end
	E.C_AutoComplete = Namespace("C_AutoComplete", { GetAutoCompleteRealms = function() return {} end })
	E.C_TradeSkillUI = Namespace("C_TradeSkillUI", {})
end

---------------------------------------------------------------------------
-- Tail calls. A function that ends in "return f(...)" leaves the stack when it calls f (LuaJIT,
-- like the client, reuses its frame), so a reach of the game's made that way would show no Olympus
-- line on the stack. The pass loads the addon's files with each such return made an ordinary call,
-- on the same lines: "return OlympusTailCall__(f(...))" returns the same values, nothing else changes
-- but the depth of the stack.
---------------------------------------------------------------------------

local KEYWORDS = Set("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")
local function Tokens(src)
	local out, i, n = {}, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if c:find("%s") then
			i = i + 1
		elseif src:sub(i, i + 1) == "--" then
			local eq = src:match("^%[(=*)%[", i + 2)
			if eq then
				local close = src:find("]" .. eq .. "]", i, true)
				i = (close or n) + #eq + 2
			else
				local nl = src:find("\n", i, true)
				i = (nl or n) + 1
			end
		elseif c == "[" and src:match("^%[=*%[", i) then
			local eq = src:match("^%[(=*)%[", i)
			local close = src:find("]" .. eq .. "]", i, true)
			local e = (close or n) + #eq + 1
			out[#out + 1] = { kind = "string", s = i, e = e }
			i = e + 1
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then j = j + 2 elseif d == c then break else j = j + 1 end
			end
			out[#out + 1] = { kind = "string", s = i, e = j }
			i = j + 1
		elseif c:find("[%a_]") then
			local j = src:find("[^%w_]", i) or (n + 1)
			local word = src:sub(i, j - 1)
			out[#out + 1] = { kind = KEYWORDS[word] and "keyword" or "name", text = word, s = i, e = j - 1 }
			i = j
		elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
			local j = i
			if src:sub(i, i + 1):lower() == "0x" then j = i + 2; while src:sub(j, j):find("[%x]") do j = j + 1 end
			else
				while src:sub(j, j):find("[%d%.]") do j = j + 1 end
				if src:sub(j, j):find("[eE]") then j = j + 1; if src:sub(j, j):find("[%+%-]") then j = j + 1 end; while src:sub(j, j):find("%d") do j = j + 1 end end
			end
			out[#out + 1] = { kind = "number", s = i, e = j - 1 }
			i = j
		else
			local three, two = src:sub(i, i + 2), src:sub(i, i + 1)
			local op = (three == "..." and three) or ((two == ".." or two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "::") and two) or c
			out[#out + 1] = { kind = "op", text = op, s = i, e = i + #op - 1 }
			i = i + #op
		end
	end
	return out
end
local BINARY = Set("and or not + - * / % ^ .. == ~= < > <= >= #")
local ENDS = Set("end else elseif until")
local function NoTailCalls(src)
	local tokens = Tokens(src)
	local inserts = {} -- { position, text }
	for k, t in ipairs(tokens) do
		if t.kind == "keyword" and t.text == "return" then
			local depth, last, ok = 0, nil, true
			local j = k + 1
			local first = tokens[j]
			while tokens[j] do
				local u = tokens[j]
				if u.kind == "op" and (u.text == "(" or u.text == "{" or u.text == "[") then depth = depth + 1
				elseif u.kind == "op" and (u.text == ")" or u.text == "}" or u.text == "]") then depth = depth - 1
				elseif depth == 0 and ((u.kind == "keyword" and (ENDS[u.text] or u.text == "return")) or (u.kind == "op" and u.text == ";")) then break
				elseif depth == 0 and ((u.kind == "op" and (u.text == "," or BINARY[u.text])) or (u.kind == "keyword" and (BINARY[u.text] or u.text == "function"))) then ok = false end
				last = j
				j = j + 1
			end
			-- A call: starts with a name or "(", ends with its arguments ("(...)", a string, a table),
			-- and its last group is not the whole expression in parentheses.
			if ok and first and last and last >= k + 2 and (first.kind == "name" or (first.kind == "op" and first.text == "(")) then
				local tail = tokens[last]
				local isCall = tail.kind == "string" or (tail.kind == "op" and (tail.text == ")" or tail.text == "}"))
				if isCall and tail.kind == "op" then
					-- The group the last token closes: where it opens.
					local d, m = 0, last
					while m > k do
						local u = tokens[m]
						if u.kind == "op" and (u.text == ")" or u.text == "}" or u.text == "]") then d = d + 1
						elseif u.kind == "op" and (u.text == "(" or u.text == "{" or u.text == "[") then d = d - 1; if d == 0 then break end end
						m = m - 1
					end
					if m == k + 1 then isCall = false end -- "(expression)": not a call
				end
				if isCall then
					inserts[#inserts + 1] = { first.s, "OlympusTailCall__(" }
					inserts[#inserts + 1] = { tail.e + 1, ")" }
				end
			end
		end
	end
	table.sort(inserts, function(a, b) return a[1] > b[1] end)
	for _, ins in ipairs(inserts) do src = src:sub(1, ins[1] - 1) .. ins[2] .. src:sub(ins[1]) end
	return src
end

---------------------------------------------------------------------------
-- The addon in the client: its files in the TOC's order, the saved variables, the login.
---------------------------------------------------------------------------

local TOC = {}
for line in assert(io.open(ADDON_DIR .. "Olympus.toc")):lines() do
	local f = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if f then TOC[#TOC + 1] = (f:gsub("\\", "/")) end
end

-- A client with the addon loaded (opts.gamepad: the gamepad UI on from the start; opts.saved: the
-- saved variables, OlympusDB). Returns the client and the addon's namespace.
local function Boot(opts)
	opts = opts or {}
	local C = NewClient(opts)
	World(C, opts)
	if opts.setup then opts.setup(C) end
	C.SealGame()
	local ns = {}
	C.ns = ns
	if opts.saved then rawset(C.env, "OlympusDB", opts.saved) end
	rawset(C.env, "OlympusTailCall__", function(...) return ... end)
	for _, file in ipairs(TOC) do
		local f = assert(io.open(ADDON_DIR .. file, "rb"))
		local src = f:read("*a")
		f:close()
		local chunk = assert(loadstring(NoTailCalls(src), "@" .. ADDON_DIR .. file))
		setfenv(chunk, C.env)
		-- (A file that fails as it loads: the client reports it and loads the next one.)
		local ok, err = pcall(chunk, "Olympus", ns)
		if not ok then C.loadErrors[#C.loadErrors + 1] = file .. ": " .. tostring(err); pcall(C.handler, err) end
	end
	-- (opts.realmFrom(ns): a realm named by the addon itself, the Treasurer's group's for the dues.)
	if opts.realmFrom then C.realmName = opts.realmFrom(ns) end
	C.Fire("ADDON_LOADED", "Olympus")
	return C, ns
end

-- The login: PLAYER_LOGIN, the loading screen, then the timers for a while.
local function Login(C, seconds)
	C.loggedIn = true
	C.Fire("PLAYER_LOGIN")
	C.Fire("PLAYER_ENTERING_WORLD", true, false)
	C.Advance(seconds or 30)
end

---------------------------------------------------------------------------
-- What a session checks.
---------------------------------------------------------------------------

-- A record the gamepad UI allows: an entry of the registry whose guard lets it through there.
local function AllowedUnderPad(r)
	if not r.ids or r.kind == "blocked" then return false end
	if r.gateWork then return true end -- (the gate's own work at a switch: see GATE_WORK)
	for _, id in ipairs(r.ids) do
		local e = REGISTRY[id]
		if e and (e.guard == "own" or e.guard == "exempt" or e.guard == "isolated" or (e.guard == "click" and r.click)) then return true end
	end
	return false
end
local function Describe(r)
	return ("%s (%s) from Olympus/%s:%s, tagged %s%s%s"):format(r.sym, r.kind, tostring(r.file), tostring(r.line),
		r.ids and table.concat(r.ids, ",") or "nothing", r.click and ", in a click" or "", r.gateWork and (", the gate's " .. r.gateWork) or "")
end
-- Every record must name its entry (the audit's tags at runtime); with the gamepad UI on, only an
-- allowed one; never a restricted call refused.
local function Check(list, what)
	local bad = {}
	for _, r in ipairs(list) do
		if not r.ids then bad[#bad + 1] = "no registry entry: " .. Describe(r)
		elseif r.kind == "blocked" then bad[#bad + 1] = "refused outside a click: " .. Describe(r)
		elseif r.gamepad and not AllowedUnderPad(r) then bad[#bad + 1] = "with the gamepad UI: " .. Describe(r) end
	end
	if #bad > 0 then error(("%s: %d reach%s of the game's UI\n         %s\n%s"):format(what, #bad, #bad == 1 and "" or "es",
		table.concat(bad, "\n         "), list[1] and list[1].trace or ""), 2) end
end
-- With the gamepad UI on: no record at all but the allowed (own, exempt, a click's).
local function OnlyAllowed(list, what) Check(list, what) end
local function Ids(list)
	local out = {}
	for _, r in ipairs(list) do for _, id in ipairs(r.ids or {}) do out[id] = (out[id] or 0) + 1 end end
	return out
end

local function Errors(C)
	local out = {}
	for _, e in ipairs(C.ns.db and C.ns.db.errors or {}) do out[#out + 1] = tostring(e.where) .. ": " .. tostring(e.msg) .. "\n" .. tostring(e.stack) end
	return out
end
local function NoErrors(C, what)
	local errs = Errors(C)
	if #errs > 0 then error((what or "") .. ": " .. #errs .. " error(s) caught by the addon: " .. errs[1], 2) end
	if #C.isolatedErrors > 0 then error((what or "") .. ": an error in a callback the game called: " .. C.isolatedErrors[1], 2) end
	assert(next(C.unmodelled) == nil, "unmodelled: " .. (next(C.unmodelled) or ""))
end

-- The frames the gamepad UI navigates with Smart Navigation (their visible buttons are targets).
local MANAGED = { "CommunitiesFrame", "GuildFrame", "FriendsFrame", "WorldMapFrame", "PTR_IssueReporter", "GameMenuFrame" }
-- (With every one of those frames shown, as the game would show them, then put back.)
local function NavigableOlympus(C, show)
	local out = {}
	local shown = {}
	if show then
		for _, n in ipairs(MANAGED) do
			local f = rawget(C.env, n)
			if f and not f:IsShown() then f:Show(); shown[#shown + 1] = f end
		end
	end
	local function Walk(f)
		for _, c in ipairs(f.children) do
			if c.olympus and c:IsVisible() and (c:IsObjectType("Button") or c.kind == "EditBox" or c.scripts.OnMouseUp or c.scripts.OnMouseDown) then
				out[#out + 1] = c.name or c.kind
			end
			Walk(c)
		end
	end
	for _, n in ipairs(MANAGED) do
		local f = rawget(C.env, n)
		if f and f:IsVisible() then Walk(f) end
	end
	for _, f in ipairs(shown) do f:Hide() end
	return out
end

-- The game's own state an addon could leave written: the escape list, the slash commands, the
-- popups and their definitions, the chat box, the error handler, and every global of the game's.
local function Snapshot(C)
	local E = C.env
	local s = { globals = {}, special = {}, slash = {}, dialogs = {}, popups = {} }
	for k, v in pairs(E) do if type(k) == "string" and not AUDIT.Own(k) then s.globals[k] = v end end
	for i, n in ipairs(rawget(E, "UISpecialFrames") or {}) do s.special[i] = n end
	for k in pairs(rawget(E, "SlashCmdList") or {}) do s.slash[k] = true end
	for k in pairs(rawget(E, "StaticPopupDialogs") or {}) do if not tostring(k):find("^OLYMPUS_") then s.dialogs[k] = true end end
	for i = 1, 4 do local p = rawget(E, "StaticPopup" .. i); s.popups[i] = p and p.shown end
	s.chat = rawget(E, "LAST_ACTIVE_CHAT_EDIT_BOX")
	s.handler = C.handler
	return s
end
local function Diff(a, b)
	local out = {}
	for k, v in pairs(b.globals) do if a.globals[k] ~= v then out[#out + 1] = "global " .. k end end
	for k in pairs(a.globals) do if b.globals[k] == nil then out[#out + 1] = "global " .. k .. " gone" end end
	if table.concat(a.special, ",") ~= table.concat(b.special, ",") then out[#out + 1] = "UISpecialFrames: " .. table.concat(b.special, ",") end
	for k in pairs(b.slash) do if not a.slash[k] then out[#out + 1] = "SlashCmdList." .. k end end
	for k in pairs(b.dialogs) do if not a.dialogs[k] then out[#out + 1] = "StaticPopupDialogs." .. k end end
	for i = 1, 4 do if a.popups[i] ~= b.popups[i] then out[#out + 1] = "StaticPopup" .. i end end
	if a.chat ~= b.chat then out[#out + 1] = "LAST_ACTIVE_CHAT_EDIT_BOX" end
	if a.handler ~= b.handler then out[#out + 1] = "the error handler" end
	table.sort(out)
	return out
end

---------------------------------------------------------------------------
-- The flows: what a player does, the game's way (clicks are the player's).
---------------------------------------------------------------------------

local function Main(C)
	for _, n in ipairs({ "OlympusFrameHD", "OlympusFrame", "OlympusFrameHDBasic", "OlympusFrameBasic" }) do
		local f = rawget(C.env, n)
		if f and f:IsShown() then return f end
	end
end
-- The minimap button opens the window, every tab gets a click, its X closes it.
local function WindowFlow(C)
	-- (Open already, from another flow: its X first.)
	local open = Main(C)
	if open then C.Click(rawget(open, "CloseButton")); C.Advance(0.5) end
	local b = rawget(C.env, "OlympusMinimapButton")
	assert(b and b:IsVisible(), "the minimap button shows")
	C.Click(b)
	C.Advance(1)
	local f = assert(Main(C), "the minimap button opened the window")
	local tabs = {}
	for _, t in ipairs(rawget(f, "tabs") or {}) do tabs[#tabs + 1] = t end
	for _, t in ipairs(rawget(f, "sideTabs") or {}) do tabs[#tabs + 1] = t end
	for _, t in ipairs(tabs) do
		if t:IsVisible() then C.Click(t); C.Advance(1) end
	end
	C.Click(assert(rawget(f, "CloseButton"), "its X"))
	C.Advance(1)
	assert(not Main(C), "its X closed it")
	return #tabs
end

-- Every one of Olympus's dialogs, shown the addon's way (ns.ShowDialog). In Olympus's own window
-- (the gamepad UI's), each of its buttons clicked by the player, the dialog shown again for each;
-- the game's popup (mouse and keyboard) hidden again.
local function DialogsFlow(C)
	local ns, n, clicks = C.ns, 0, 0
	local keys = {}
	for k in pairs(C.env.StaticPopupDialogs) do if tostring(k):find("^OLYMPUS_") then keys[#keys + 1] = k end end
	table.sort(keys)
	for _, which in ipairs(keys) do
		for b = 1, 3 do
			local shown = ns.ShowDialog(which, "Someone", "Something", { name = "Someone-Realm" })
			if shown and b == 1 then n = n + 1 end
			local own = type(shown) == "table" and rawget(shown, "olympus") and rawget(shown, "buttons")
			local button = own and own[b]
			if button and button:IsVisible() then
				C.Click(button)
				clicks = clicks + 1
			end
			ns.HideDialog(which)
			C.Advance(0.1)
			if not own then break end
		end
	end
	return n, #keys, clicks
end

-- The author's King's view (King.SetDevView, a test character's: ns.devWorkshop): the window with
-- the King's tabs too (Throne, Vox) and the Workshop, each clicked.
local function KingViewFlow(C)
	local ns = C.ns
	ns.devWorkshop = true
	ns.King.SetDevView(true)
	assert(ns.King.Preview(), "the King's view")
	local tabs = WindowFlow(C)
	ns.King.SetDevView(false)
	ns.devWorkshop = nil
	return tabs
end

-- The game shows its guild windows, then hides them (their OnShow and OnHide, and Olympus's hooks).
local function GuildWindowsFlow(C)
	for _, name in ipairs({ "CommunitiesFrame", "FriendsFrame" }) do
		local f = rawget(C.env, name)
		if f then f:Show(); C.Advance(0.5); f:Hide(); C.Advance(0.5) end
	end
end

-- The world map: shown, its map changed, zoomed and sized, hidden.
local function MapFlow(C)
	local map = C.env.WorldMapFrame
	C.ShowMap()
	map.mapID = 1429
	map:OnMapChanged()
	local sc = map.ScrollContainer
	C.RunScript(sc, "OnMouseWheel", 1)
	C.RunScript(sc, "OnSizeChanged", 800, 600)
	C.Advance(1)
	C.HideMap()
	C.Advance(1)
end

-- A player's tooltip: the game's post-calls, isolated, with the tooltip and its data.
local function TooltipFlow(C)
	local tip = C.env.GameTooltip
	-- (Inspected before: the tabard line Olympus adds to his tooltip, with mouse and keyboard.)
	C.ns.Inspect.Record("Someone-Realm", "Olympus II", "WARRIOR", 60, nil, true)
	C.units.mouseover = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	tip:SetOwner(C.env.UIParent, "ANCHOR_CURSOR")
	tip:SetUnit("mouseover")
	local unit = C.env.Enum.TooltipDataType.Unit
	for _, fn in ipairs(C.postCalls[unit] or {}) do C.Isolated(fn, tip, { type = unit, guid = "Player-1-00000002" }) end
	for _, h in ipairs(tip.hooks.OnTooltipSetUnit or {}) do C.Isolated(h, tip) end
	local lines = #(tip.lines or {})
	tip:Hide()
	C.units.mouseover = nil
	return lines, #(C.postCalls[unit] or {}) + #(tip.hooks.OnTooltipSetUnit or {})
end

-- The game's right-click player menus: each callback, with a model of the menu's root
-- (Blizzard_Menu's root description: CreateTitle, CreateButton, CreateDivider).
local function MenuFlow(C)
	local made = 0
	local function Element()
		local d = {}
		function d.SetTooltip() end
		function d.SetEnabled() end
		function d.AddInitializer() end
		return d
	end
	local root = {}
	function root.CreateTitle() made = made + 1 return Element() end
	function root.CreateButton() made = made + 1 return Element() end
	function root.CreateDivider() return Element() end
	C.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	local ran = 0
	for tag, list in pairs(C.menus) do
		for _, fn in ipairs(list) do
			ran = ran + 1
			C.Isolated(fn, {}, root, { unit = "target", name = "Someone", server = "Realm" })
		end
	end
	C.units.target = nil
	return made, ran
end

-- A line in the game's chat: each sender name filter, as ChatFrameUtil.ProcessSenderNameFilters calls it.
local function ChatLineFlow(C)
	local out, ran = nil, 0
	for _, fn in ipairs(C.nameFilters) do
		ran = ran + 1
		C.Isolated(function() out = fn("CHAT_MSG_CHANNEL", "Someone", "hello", "Someone-Realm") or out end)
	end
	return out, ran
end

-- A slash command typed in the game's chat box (fidelity rule 3: called directly, then the box
-- closes in the caller's taint): with the gamepad UI on, any Olympus code run that way is a taint event.
local function TypeSlash(C, line)
	local cmd, msg = line:match("^(/%S+)%s*(.-)$")
	local E = C.env
	-- ChatFrameUtil.ImportListToHash: every SlashCmdList key's SLASH_<KEY>n globals.
	for key, fn in pairs(E.SlashCmdList) do
		local i = 1
		while true do
			local s = rawget(E, "SLASH_" .. key .. i)
			if not s then break end
			if s:lower() == cmd:lower() then
				local mark = C.Mark()
				local ran = false
				local hook = debug.gethook()
				debug.sethook(function()
					local info = debug.getinfo(2, "S")
					if info and OlympusFile(info.source) then ran = true end
				end, "c")
				local ok, err = pcall(fn, msg, E.ChatFrame1EditBox)
				debug.sethook(hook)
				if ran and C.style == 1 then C.taint[#C.taint + 1] = { line = line, ledger = C.Since(mark) } end
				if not ok then error(err, 0) end
				return true
			end
			i = i + 1
		end
	end
	return false -- (the game's own: "Type /help for a list of commands.")
end

-- A player who answered the first-open page (Consent.lua) before: the window opens on its tabs.
local function Answered()
	return { addonChat = true, royalInspection = true, rollCall = true, layerHelp = true, treasurerShares = true,
		chatWarned = { A = true, C = true, L = true }, shareLocation = true }
end
local function Session(gamepad, opts)
	opts = opts or {}
	opts.gamepad = gamepad
	if opts.saved == nil and not opts.fresh then opts.saved = Answered() end
	local C, ns = Boot(opts)
	if opts.brokenMapLibrary then
		C.brokeMapLibrary = #C.loadErrors == 1 and C.loadErrors[1]:find("HereBeDragons%-Pins") ~= nil
		C.loadErrors = {}
	end
	Login(C)
	assert(#C.loadErrors == 0, "a file failed to load: " .. tostring(C.loadErrors[1]))
	return C, ns
end

-- The player's click on one of Olympus's buttons that runs fn (the hardware event).
local function InClick(C, fn)
	C.clicking = true
	local ok, err = pcall(fn)
	C.clicking = false
	if not ok then error(err, 0) end
end

-- A player's card (a row of the census), its Whisper, Invite and Who buttons clicked.
local function PersonFlow(C)
	local ns = C.ns
	ns.UI.ShowPerson({ name = "Someone", realm = "Realm", guild = "Olympus II", class = "WARRIOR", level = 60 })
	local card
	-- (1.1.5's windows: ns.Window gives the metal frame its own name, the plain fallback "<name>Basic".)
	for _, n in ipairs({ "OlympusPersonFrameHD", "OlympusPersonFrame", "OlympusPersonFrameHDBasic", "OlympusPersonFrameBasic" }) do
		local f = rawget(C.env, n)
		if f and f:IsShown() then card = f end
	end
	card = card or assert(ns.UI.PersonCard and ns.UI.PersonCard(), "the card shows")
	for _, key in ipairs({ "whisper", "invite", "who" }) do
		local b = assert(rawget(card, key), "its " .. key .. " button")
		C.Advance(10) -- (Who's cooldown)
		C.Click(b)
	end
	C.Advance(1)
	card:Hide()
end

-- The census's quiet /who (Who.Search, the player's click on Refresh): its answer still to come
-- (the game's who list doesn't hear it meanwhile).
local function QuietWhoFlow(C)
	C.Advance(30)
	InClick(C, function() C.ns.Who.Search() end)
	C.Advance(1)
	return C.ns.Who.IsPending()
end

-- The Olympus window on its Chat tab (ChatWindow.lua), which takes the Open chat key.
local function ChatTabFlow(C)
	C.ns.ChatWindow.Toggle("A")
	C.Advance(1)
end

-- The game's target: a player of an Olympus guild (the borders' and nameplates' events).
local function TargetFlow(C)
	C.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	C.Fire("PLAYER_TARGET_CHANGED")
	C.Advance(1)
	-- The game's own refresh of the target frame and of a name, which Olympus hooks.
	C.env.TargetFrame:CheckClassification()
	C.env.CompactUnitFrame_UpdateName({ unit = "target", name = C.NewWidget("FontString", nil, nil, nil, true) })
	C.units.target = nil
	C.Fire("PLAYER_TARGET_CHANGED")
	C.Advance(1)
end

-- An officer's click on a week's entry: the game's calendar (Week.OpenCalendar).
local function CalendarFlow(C)
	local opened
	InClick(C, function() opened = C.ns.Week.OpenCalendar({ at = C.now + 86400, title = "Raid" }) end)
	return opened
end

-- The game's own /who: Olympus's hook on C_FriendList.SendWho (Who.lua) runs after it.
local function GameWhoFlow(C) C.env.C_FriendList.SendWho("n-Someone") end

-- An alert (ns.Alert: the raid warning frame) and a line in the chat (ns.Print).
local function AlertFlow(C)
	C.ns.Alert("test", "soft", { text = "A test alert", own = true })
	C.ns.Print("A test line")
end

-- The world map's Olympus icons: what Olympus's copy of the library holds there.
local function WorldPins(C)
	local lib = C.env.LibStub("HereBeDragons-Pins-2.0", true)
	local n = 0
	for ref, list in pairs(lib and lib.worldmapPins or {}) do n = n + 1 end
	return n, lib and lib.worldmapPinsPool and lib.worldmapPinsPool:GetNumActive() or 0
end

local function OlympusEscapeNames(C)
	local out = {}
	for _, n in ipairs(C.env.UISpecialFrames) do if AUDIT.Own(n) then out[#out + 1] = n end end
	return out
end

-- Olympus's textures and frames on the game's own frames, shown.
local function ShownOnGameFrames(C)
	local out = {}
	for _, w in ipairs(C.created) do
		if w.olympus and w:IsVisible() then
			local p = w.parent
			while p and p.olympus do p = p.parent end
			if p and p ~= C.env.UIParent and p.blizzard and p ~= C.env.Minimap then out[#out + 1] = (w.name or w.kind) .. " on " .. (rawget(p, "name") or rawget(p, "path") or "?") end
		end
	end
	return out
end


---------------------------------------------------------------------------
-- The sessions.
---------------------------------------------------------------------------

test("gamepad pass 0: the offline tests switch the gamepad UI the game's way (its input style), never by replacing ns.GamepadUI or ns.Gate", function()
	-- (Core.lua's stand-in, taken over by Gamepad.lua, is tested in a namespace of its own: gns.)
	local f = assert(io.open(ROOT .. "tests/run.lua", "rb"))
	local src = f:read("*a")
	f:close()
	local n = 0
	for line in src:gmatch("[^\n]+") do
		n = n + 1
		local code = line:gsub("%-%-.*$", "")
		local lhs = code:match("^%s*([^=~<>]-)%s*=[^=]") or ""
		local guard = line:find("(the guard's own restore)", 1, true)
		if not guard and not code:find("^%s*local ") then
			for target in (lhs .. ","):gmatch("%s*([^,]-)%s*,") do
				-- (the addon's ns, or a copy's as w.ns; not a namespace of a test's own, gns)
				if target:find("^ns%.GamepadUI$") or target:find("%.ns%.GamepadUI$") or target:find("^ns%.Gate$") or target:find("%.ns%.Gate$") then
					error(("tests/run.lua:%d replaces %s: switch the input style instead (GamepadStyle, WithGamepadUI)"):format(n, target), 0)
				end
			end
		end
	end
	-- And run.lua's own guard, at the end of each of its tests (where it runs): nothing replaced so far.
	if rawget(_G, "GamepadStyle") then eq(GamepadStyle(nil), nil, "nothing replaced") end
end)

test("gamepad pass 0: the model offers nothing Forever's client lacks (tests/fixtures/forever-api.lua): its globals, its namespaces' members, its frames' methods, its Enum values", function()
	local C = NewClient({})
	World(C, {})
	local bad = {}
	for k, v in pairs(C.env) do
		if type(k) == "string" and k ~= "_G" and not AUDIT.Own(k) then
			local named = type(v) == "table" and rawget(v, "fromKey")
			if not FIX.globals[k] and not named then bad[#bad + 1] = k end
			-- A namespace's members.
			if type(v) == "table" and FIX.globals[k] == "namespace" then
				for m in pairs(v) do
					if FIX.members[k .. "." .. m] == false then bad[#bad + 1] = k .. "." .. m end
				end
			end
		end
	end
	-- Every widget the model made: its own fields that are methods must be its type's (or its mixins').
	for _, w in ipairs(C.created) do
		for key, value in pairs(w) do
			if type(value) == "function" and not (rawget(w, "methods")[key] or (rawget(w, "templateMethods") or {})[key]) then
				bad[#bad + 1] = (rawget(w, "name") or rawget(w, "path") or w.kind) .. ":" .. key
			end
		end
	end
	table.sort(bad)
	eq(#bad, 0, "the model offers what the client lacks: " .. table.concat(bad, ", "))
	-- The input style's values are the documentation's.
	eq(C.env.Enum.InputDeviceInterfaceType.Gamepad, 1)
	eq(C.env.Enum.InputDeviceInterfaceType.Mkb, 0)
end)

test("gamepad pass 1: a whole session with the gamepad UI on from the login reaches nothing of the game's UI but what its rule allows", function()
	local C, ns = Session(true)
	local before = Snapshot(C)
	OnlyAllowed(C.ledger, "the login")
	NoErrors(C, "the login")
	-- No slash command at a gamepad login (D1): typed, it is the game's unknown command.
	eq(rawget(C.env, "SLASH_OLYMPUS1"), nil, "no /oly")
	eq(TypeSlash(C, "/oly status"), false, "/oly typed: not Olympus's")
	eq(#C.taint, 0, "no Olympus code from the chat box")
	GP.Covers("slash")
	-- Its hidden channel joined all the same (the census), off the chat windows' lists.
	assert(next(C.channels), "the census channel joined")
	GP.Covers("chat-channels")
	local mark = C.Mark()
	WindowFlow(C)
	local dialogs, all, clicks = DialogsFlow(C)
	eq(dialogs, all, "every dialog shown, in Olympus's own window")
	assert(clicks >= all, "their buttons clicked: " .. clicks)
	KingViewFlow(C)
	GuildWindowsFlow(C)
	MapFlow(C)
	TooltipFlow(C)
	eq(MenuFlow(C), 0, "no menu callback registered")
	eq(ChatLineFlow(C), nil, "no chat name filter")
	C.Advance(30)
	OnlyAllowed(C.Since(mark), "the flows")
	NoErrors(C, "the flows")
	eq(#NavigableOlympus(C, true), 0, "no Olympus button where the gamepad cursor goes")
	local diff = Diff(before, Snapshot(C))
	eq(#diff, 0, "the game's state written: " .. table.concat(diff, ", "))
	eq(C.handler, C.gameHandler, "the game's own error handler")
	-- Registered with the game: only the exempt mail post-hooks (Treasury.lua, "mail-hooks").
	local kinds = {}
	for _, cb in ipairs(C.callbacks) do kinds[#kinds + 1] = cb.kind .. " " .. tostring(cb.key or cb.tag or cb.script or "") end
	table.sort(kinds)
	eq(table.concat(kinds, ", "), "hooksecurefunc AutoLootMailItem, hooksecurefunc SendMail, hooksecurefunc TakeInboxItem, hooksecurefunc TakeInboxMoney",
		"what is registered with the game")
	GP.Covers("mail-hooks")
end)

test("gamepad pass 2: mouse and keyboard, then a switch to the gamepad UI: the gate steps back on the next frame, every callback left with the game does nothing, the player is told once what a /reload clears", function()
	local C, ns = Session(false)
	local E = C.env
	-- Mouse and keyboard: everything installs, every flow works the game's way.
	local mark = C.Mark()
	WindowFlow(C)
	KingViewFlow(C)
	PersonFlow(C)
	QuietWhoFlow(C)
	ChatTabFlow(C)
	DialogsFlow(C)
	GuildWindowsFlow(C)
	MapFlow(C)
	local lines, postCalls = TooltipFlow(C)
	assert(postCalls > 0 and lines > 0, "the tooltip's post-call and its line: " .. lines)
	local made, ran = MenuFlow(C)
	assert(ran >= 10, "the player menus' callbacks: " .. ran)
	local _, filters = ChatLineFlow(C)
	eq(filters, 1, "the chat name filter")
	TargetFlow(C)
	eq(CalendarFlow(C), true, "the calendar opens")
	GameWhoFlow(C)
	AlertFlow(C)
	eq(TypeSlash(C, "/oly status"), true, "/oly typed with mouse and keyboard")
	C.Advance(10)
	Check(C.ledger, "with mouse and keyboard")
	NoErrors(C, "with mouse and keyboard")
	local used = Ids(C.ledger)
	used.slash = E.SlashCmdList.OLYMPUS and 1 -- (a table write, not a call: the commands registered)
	for _, id in ipairs({ "slash", "communities-button", "tooltip-unit", "error-handler", "map-overlay", "dialogs", "chat-box", "who",
		"who-quiet", "map-library", "chat-key", "player-menu", "borders", "chat-marks", "nameplates", "minimap", "roster-actions",
		"calendar", "raid-notice", "chat-channels", "mail-hooks" }) do
		assert(used[id], "with mouse and keyboard, used: " .. id)
	end
	-- A game popup of Olympus's still up, its window on the escape list, the Communities window
	-- open with Olympus's button in it, the map showing Olympus's icons: then the switch.
	ns.ShowDialog("OLYMPUS_CRAFT_ASK")
	ns.UI.Toggle()
	E.CommunitiesFrame:Show()
	C.ShowMap()
	-- (The author's preview of a border, on his own portrait: a texture of Olympus's on the game's
	-- player frame, and his nameplate mark's.)
	ns.devWorkshop = true
	ns.Borders.SetPreview(ns.Borders.TIERS[1].name)
	ns.Borders.RefreshAll(true)
	eq(QuietWhoFlow(C), true, "a quiet /who waiting for its answer")
	eq(E.LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), false, "the game's who list silenced meanwhile")
	assert(#ShownOnGameFrames(C) > 0, "Olympus's border on the game's player frame, before the switch")
	assert(#NavigableOlympus(C) > 0, "Olympus's button where the gamepad cursor goes, before the switch")
	assert(#OlympusEscapeNames(C) > 0, "Olympus's windows on the escape list")
	assert((WorldPins(C)) > 0, "Olympus's icons on the world map")
	assert(E.ChatFrame1EditBox:IsShown(), "the game's chat box opened from Olympus (a whisper)")
	assert(C.bindings and next(C.bindings), "the Chat tab's key")
	assert(C.handler ~= C.gameHandler, "Olympus's error handler")
	local escapeBefore = table.concat(E.UISpecialFrames, ",")

	C.Switch(true)
	-- In the switch's own event: nothing but the Chat tab's key given back.
	for _, r in ipairs(C.switchLedger) do
		assert(r.ids and r.ids[1] == "chat-key", "in the switch's event: " .. Describe(r))
	end
	eq(next(C.bindings), nil, "the Chat tab's key back to the game at once")
	GP.Covers("chat-key")
	C.Advance(1)
	-- The next frame: each park.
	eq(#NavigableOlympus(C, true), 0, "no Olympus button where the gamepad cursor goes")
	GP.Covers("communities-button")
	local shown = ShownOnGameFrames(C)
	eq(#shown, 0, "Olympus's objects on the game's frames hidden: " .. table.concat(shown, ", "))
	GP.Covers("map-overlay"); GP.Covers("borders"); GP.Covers("nameplates")
	eq(C.handler, C.gameHandler, "the game's error handler back")
	GP.Covers("error-handler")
	eq(#OlympusEscapeNames(C), 0, "Olympus's names off the end of the escape list (" .. escapeBefore .. ")")
	GP.Covers("escape-list")
	eq((WorldPins(C)), 0, "Olympus's icons off the world map")
	GP.Covers("worldmap-icons")
	eq(ns.Who.IsPending(), false, "the quiet /who given up at the switch")
	eq(E.LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), true, "the game's who list hears its answers again at once")
	GP.Covers("who-quiet")
	-- What stays until a /reload, told once in Olympus's own window, whose Reload is the player's click.
	local left = table.concat(ns.Gate.leftovers, ",")
	for _, id in ipairs({ "chat-box", "dialogs", "slash", "worldmap-icons" }) do
		assert(left:find(id, 1, true), "until a /reload: " .. id .. " (" .. left .. ")")
	end
	GP.Covers("slash"); GP.Covers("dialogs"); GP.Covers("chat-box")
	eq(ns.Gate.Noticed(), true, "told")
	local notice
	for _, w in ipairs(C.created) do if w.olympus and w.which == "OLYMPUS_GAMEPAD_RELOAD" and w:IsShown() then notice = w end end
	assert(notice, "the notice, in Olympus's own window (Dialog.lua)")
	eq(E.StaticPopup1.which == "OLYMPUS_GAMEPAD_RELOAD", false, "not the game's popup")
	Check(C.Since(mark), "the switch")
	-- The notice's Reload: the player's click.
	local reload
	for _, b in ipairs(notice.buttons or {}) do if b:IsVisible() and b:GetText() == ns.L.GATE_RELOAD then reload = b end end
	assert(reload, "the notice's Reload button")
	C.Click(reload)
	eq(C.reloaded, true, "ReloadUI from the player's click")
	GP.Covers("reload-button")
	-- Every callback left with the game, called the game's way: nothing.
	local after = C.Mark()
	eq(TooltipFlow(C), 0, "no line on the tooltip")
	GP.Covers("tooltip-unit")
	local made2 = MenuFlow(C)
	eq(made2, 0, "no line in the player menus")
	GP.Covers("player-menu")
	eq(ChatLineFlow(C), nil, "no mark in the chat")
	GP.Covers("chat-marks")
	GuildWindowsFlow(C)
	MapFlow(C)
	TargetFlow(C)
	GameWhoFlow(C)
	AlertFlow(C)
	GP.Covers("raid-notice"); GP.Covers("chat-output")
	eq(CalendarFlow(C), false, "the calendar: only how to open it")
	GP.Covers("calendar")
	WindowFlow(C)
	PersonFlow(C)
	GP.Covers("roster-actions"); GP.Covers("who")
	DialogsFlow(C)
	-- /oly typed now: registered before, the game's chat box still calls it (the leftover the
	-- notice names); its first line refuses, nothing of the game's is touched.
	eq(TypeSlash(C, "/oly status"), true, "the command the game keeps")
	eq(#C.taint, 1, "the chat box ran Olympus's function: the /reload the notice asks for")
	C.Advance(30)
	Check(C.Since(after), "the gamepad UI after the switch")
	NoErrors(C, "after the switch")
	eq(ns.Gate.Noticed(), true)
	Check(C.ledger, "the whole session")
end)

test("gamepad pass 3: the gamepad UI and mouse and keyboard, back and forth three times: each install once, what can't be undone registered once, every flow working in both", function()
	local C, ns = Session(true)
	local E = C.env
	for round = 1, 3 do
		C.Switch(false)
		C.Advance(1)
		WindowFlow(C)
		ChatTabFlow(C)
		E.CommunitiesFrame:Show(); C.Advance(0.5)
		assert(#NavigableOlympus(C) > 0, "round " .. round .. ": Olympus's button back in the guild window")
		E.CommunitiesFrame:Hide()
		MapFlow(C)
		eq(select(2, TooltipFlow(C)), 1, "round " .. round .. ": the tooltip's post-call, once")
		eq(TypeSlash(C, "/oly status"), true, "round " .. round .. ": /oly back")
		C.Switch(true)
		C.Advance(1)
		E.CommunitiesFrame:Show(); C.Advance(0.5)
		eq(#NavigableOlympus(C), 0, "round " .. round .. ": none with the gamepad UI")
		E.CommunitiesFrame:Hide()
		WindowFlow(C)
		eq(TooltipFlow(C), 0, "round " .. round .. ": no tooltip line")
		NoErrors(C, "round " .. round)
	end
	Check(C.ledger, "three rounds")
	-- What can't be undone, registered once a session however many switches.
	local count = {}
	for _, cb in ipairs(C.callbacks) do
		local key = cb.kind .. " " .. tostring(cb.key or cb.tag or cb.type or "") .. " " .. tostring(cb.script or "") .. " " .. tostring(cb.frame and (rawget(cb.frame, "name") or rawget(cb.frame, "path")) or "")
		count[key] = (count[key] or 0) + 1
	end
	for key, n in pairs(count) do eq(n, 1, "registered once: " .. key) end
	eq(#C.menus.MENU_UNIT_PLAYER, 1, "the player menu's callback, once")
	local slash = 0
	for k in pairs(E.SlashCmdList) do if k:find("^OLYMPUS") then slash = slash + 1 end end
	eq(slash, 4, "/oly and /ol, /olc, /oll, once")
	GP.Covers("player-menu"); GP.Covers("slash"); GP.Covers("minimap")
	assert(rawget(E, "OlympusMinimapButton"):IsVisible(), "the minimap button in both modes")
end)

test("gamepad pass 4: blocked calls with the gamepad UI: counted, told once in a chat line, nothing of the game's touched; another addon's only logged", function()
	local C, ns = Session(true)
	local mark = C.Mark()
	local printed = #C.printed
	for i = 1, 500 do C.Fire("ADDON_ACTION_FORBIDDEN", "Olympus", "SetPreferredGamepadInteractTarget()") end
	C.Fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "SetPreferredGamepadInteractTarget()")
	eq(#C.Since(mark), 0, "the handler reaches nothing of the game's")
	C.Advance(5)
	Check(C.Since(mark), "after the blocks")
	local told = 0
	for i = printed + 1, #C.printed do if C.printed[i]:find(ns.L.BLOCKED_GAMEPAD, 1, true) then told = told + 1 end end
	eq(told, 1, "told once")
	local kept = ns.db.actionsBlocked or {}
	eq(#kept, 1, "one record")
	eq(kept[1].count, 500)
	eq(kept[1].gamepad, true)
	-- The taint probe (its record's evidence) reads the gamepad UI's own state, writes nothing.
	assert(tostring(kept[1].taint):find("^taint: none of %d+ values"), tostring(kept[1].taint))
	GP.Covers("diagnostics")
	NoErrors(C, "blocked calls")
end)

test("gamepad pass 5: the rest of the list with the gamepad UI on: the Issue Reporter, the map library half-loaded or loaded on demand, the layer hop's group, focus in Olympus's own boxes, the game's look-ups", function()
	-- A test client's Issue Reporter (Blizzard_PTRFeedback): Olympus's Hide button on it with
	-- mouse and keyboard, a gamepad target no more after the switch; none at a gamepad login.
	local function Reporter(C)
		local E = C.env
		C.absent.PTR_IssueReporter = nil
		local r = C.Blizz("PTR_IssueReporter", "Frame")
		for _, key in ipairs({ "Border", "Body", "ReportBug", "InfoButton" }) do rawset(r, key, C.NewWidget("Frame", nil, r, nil, true)) end
		C.gameTables[r] = true
		return r
	end
	local C, ns = Session(false, { setup = Reporter })
	ns.db.hideIssueReporter = false
	ns.UI.ApplyIssueReporter()
	C.env.PTR_IssueReporter:Show()
	assert(#NavigableOlympus(C) > 0, "Olympus's Hide button on the Issue Reporter")
	C.Switch(true); C.Advance(1)
	eq(#NavigableOlympus(C), 0, "hidden at the switch")
	GP.Covers("issue-reporter")
	Check(C.ledger, "the Issue Reporter")
	local P = Session(true, { setup = Reporter })
	P.env.PTR_IssueReporter:Show()
	P.ns.UI.ApplyIssueReporter()
	eq(#NavigableOlympus(P), 0, "none at a gamepad login")
	Check(P.ledger, "the Issue Reporter, gamepad login")

	-- The map library on a client that loads the world map on demand: Bootstrap.lua loads it first.
	local D = Session(true, { worldMapOnDemand = true })
	assert(D.loadedWorldMap, "Blizzard_WorldMap loaded before the library")
	Check(D.ledger, "the world map loaded on demand")
	NoErrors(D, "the world map loaded on demand")
	GP.Covers("load-worldmap"); GP.Covers("map-library"); GP.Covers("lib-stub")
	-- Half-loaded (its file stopped part way): its update loop stopped, no map features, no error each frame.
	local B = Session(true, { brokenMapLibrary = true })
	assert(B.brokeMapLibrary, "the library's file stopped as it loaded")
	Check(B.ledger, "a half-loaded map library")
	GP.Covers("lib-partial")

	-- The layer hop with the gamepad UI: the helper's addon invites the guest it offered to (its
	-- own message, no click: "hop-group"); the asker's, offered and invited, accepts nothing for
	-- the player: the game's invite window is the controller's ("party-invite").
	local Hh = Session(true)
	local hop = Hh.ns.Hop
	Hh.ns.db.layerHelp, Hh.ns.db.layerAutoInvite = true, true
	hop.random = function(a) return a or 0 end
	hop.after = function(_, _, f) f() end
	Hh.units.target = { name = "Mob", realm = "Realm", guid = "Creature-0-4619-0-7-68-0000AAA1" }
	Hh.ns.Layers.HOLD = 0
	for k = 1, 2 do Hh.units.target.guid = ("Creature-0-4619-0-7-68-0000AAA%d"):format(k); Hh.ns.Layers.Observe("target") end
	hop.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1429~7")
	hop.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
	eq(Hh.invited, "Asker", "the helper's invite, on its own")
	GP.Covers("hop-group")
	hop.Reset()
	hop.Ask(1429, 8, "the King's layer")
	local id = hop.State() and hop.State().id
	assert(id, "asked")
	hop.HandleOffer("WHISPER", "Bbb-Realm", ("LO~%d~3~5"):format(id))
	Hh.Advance(hop.WINDOW + 1)
	hop.Tick()
	hop.OnInvite("Bbb")
	eq(Hh.accepted, nil, "nothing accepted for the player")
	GP.Covers("party-invite")
	Check(Hh.ledger, "the layer hop")
	NoErrors(Hh, "the layer hop")

	-- Focus: a dialog's box takes the keyboard only through ns.Focus, never from the game's chat box.
	local F = Session(true)
	F.env.ChatFrame1EditBox:Show(); F.focus = F.env.ChatFrame1EditBox
	F.ns.ShowDialog("OLYMPUS_CRAFT_ASK")
	eq(F.focus, F.env.ChatFrame1EditBox, "the chat's box keeps the keyboard; the player clicks into Olympus's")
	GP.Covers("popup-focus")
	-- The game's look-ups (fonts, strings, the popups' places, the who windows): reads only.
	assert(F.ns.Who.WindowOpen() == false)
	GP.Covers("lookups")
	-- Forever has no who-list column helper (the old guild window's): Olympus's HD headers size themselves.
	eq(F.env.WhoFrameColumn_SetWidth, nil, "the client has none")
	GP.Covers("own-templates")
	Check(F.ledger, "focus and look-ups")
	NoErrors(F, "focus and look-ups")

	-- Inspecting for the tabard patrol (NotifyInspect, not protected): with the gamepad UI too.
	F.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II" }
	F.env.CanInspect = function() return true end
	F.env.CheckInteractDistance = function() return true end
	local before = F.Mark()
	F.ns.Inspect.InspectTarget()
	F.Advance(5)
	local asked = false
	for _, r in ipairs(F.Since(before)) do if r.sym == "NotifyInspect" then asked = true end end
	assert(asked, "the inspect asked for, with the gamepad UI too (not protected)")
	GP.Covers("inspect-patrol")
	Check(F.ledger, "the inspect patrol")

	-- The author's photo mode: refused with the gamepad UI (no frame of the game's touched).
	F.ns.devWorkshop = true
	F.ns.UI.TogglePhoto()
	eq(F.ns.UI.PhotoMode(), false, "no photo mode with the gamepad UI")
	F.ns.devWorkshop = nil
	GP.Covers("photo")
	Check(F.ledger, "photo")
	-- The dues of a Forever player on the Treasurer's realm group: with mouse and keyboard his click
	-- fills the game's mail window (the name, the note, the gold: nothing sent); after a switch to
	-- the gamepad UI nothing of the game's windows is filled, a line says what to send instead.
	local M = Session(false, { surname = "Ironsurname", realmFrom = function(ns) return ns.TREASURER_REALM end })
	M.env.MailFrame:Show(); M.env.SendMailFrame:Show()
	M.money = 1000000 -- (100 gold)
	local filled
	InClick(M, function() filled = M.ns.Dues.SendDues() end)
	eq(filled, "mail", "the mail filled, with mouse and keyboard")
	assert(Ids(M.ledger)["mail-trade-fill"], "the fill, in the ledger")
	M.Switch(true); M.Advance(1)
	local after = M.Mark()
	InClick(M, function() filled = M.ns.Dues.SendDues() end)
	eq(filled, "gamepad", "with the gamepad UI: only what to send")
	eq(#M.Since(after), 0, "nothing of the game's mail or trade window")
	GP.Covers("mail-trade-fill")
	Check(M.ledger, "the dues")
	NoErrors(M, "the dues")
end)

---------------------------------------------------------------------------
-- Standalone.
---------------------------------------------------------------------------

if MODE == "--debug" then
	return { Boot = Boot, Login = Login, Session = Session, WindowFlow = WindowFlow, Main = Main, Errors = Errors, DialogsFlow = DialogsFlow,
		GuildWindowsFlow = GuildWindowsFlow, MapFlow = MapFlow, TooltipFlow = TooltipFlow, MenuFlow = MenuFlow, ChatLineFlow = ChatLineFlow,
		TypeSlash = TypeSlash, Snapshot = Snapshot, Diff = Diff, Check = Check, NavigableOlympus = NavigableOlympus, Describe = Describe,
		AllowedUnderPad = AllowedUnderPad }
end
if MODE == "--discover" then
	local C, ns = Boot({ discover = true, gamepad = arg and arg[2] == "gamepad" })
	Login(C)
	local list = {}
	for k in pairs(C.unmodelled) do list[#list + 1] = k end
	table.sort(list)
	print(table.concat(list, "\n"))
	for _, e in ipairs(ns.db and ns.db.errors or {}) do print("ERROR " .. e.where .. ": " .. e.msg .. "\n" .. e.stack) end
	return
end
if MODE == "--names" then
	local C = NewClient()
	World(C)
	local names = {}
	for k in pairs(C.env) do names[#names + 1] = k end
	table.sort(names)
	for _, k in ipairs(names) do if type(k) == "string" then print("global " .. k) end end
	return
end

if not H then
	print(("\n%d passed, %d failed"):format(passed, failed))
	os.exit(failed == 0 and 0 or 1)
end
