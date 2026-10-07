-- 1.2, the Bone Throw tables: a stand-in of the game's frames for Bone Throw's board (Olympus_Arena/FarkleBoard.lua),
-- added to a test world's client by composition (the design's rule for packages): regions with their
-- anchors, sizes and shown state; textures, font strings, buttons, a Cooldown; animation groups
-- whose Translation, Scale, Alpha and FlipBook really progress on the world's clock (so a test can
-- ask where a die is in the middle of its throw); OnShow and OnHide; the game's Escape list. A method
-- the stand-in lacks reads nil, so calling it fails as it would in the client, and a frame refuses
-- an OnUpdate script the companion's own code sets (it never uses one; the core's card may, from a
-- companion's click). Positions are resolved as the client does
-- (anchors, then the animations' offsets and scale), in UI units with y up.
--   local UI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
--   local K = UI.New(function() return w.clock end, { screen = { 1024, 768 } })
--   K.Install(client.globals)       -- CreateFrame, UIParent, GameTooltip, UISpecialFrames...
--   K.Within(region, base)          -- x, y (down), w, h from base's top left, animations applied
--   K.UserClick(button), K.Escape()
local H = ...
local UI = {}

function UI.New(now, opts)
	opts = opts or {}
	local K = { all = {}, frames = {}, screen = opts.screen or { 1024, 768 }, seq = 0, errors = {} }
	local function Seq() K.seq = K.seq + 1; return K.seq end
	K.now = now

	local R = {}
	local Meta = { __index = function(self, k) return rawget(self, "__class")[k] end }
	local function Make(cls, otype, parent)
		local o = setmetatable({ __class = cls, otype = otype, parent = parent, points = {}, shown = true, alpha = 1, id = Seq(), scripts = {} }, Meta)
		K.all[#K.all + 1] = o
		return o
	end

	function R:GetObjectType() return self.otype end
	function R:GetName() return self.name end
	function R:IsObjectType(t) return self.otype == t or (t == "Frame" and self.isFrame) or t == "Region" end
	function R:GetParent() return self.parent end
	-- (a frame moves to its new parent's children, as the client's does: its OnShow and OnHide
	-- follow that parent from then on)
	function R:SetParent(p)
		local old = self.parent
		if old == p then return end
		if self.isFrame then
			for i, c in ipairs(old and old.children or {}) do if c == self then table.remove(old.children, i) break end end
			if p and p.children then p.children[#p.children + 1] = self end
		end
		self.parent = p
	end
	function R:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
		if type(rel) == "string" then rel = _G[rel] end
		assert(type(point) == "string", "SetPoint: point")
		local p = { point = point, rel = rel or self.parent, relPoint = relPoint or point, x = x or 0, y = y or 0 }
		for i, q in ipairs(self.points) do if q.point == point then self.points[i] = p; return end end
		self.points[#self.points + 1] = p
	end
	function R:ClearAllPoints() self.points = {} end
	function R:SetAllPoints(rel)
		rel = rel or self.parent
		self.points = {}
		self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
		self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
	end
	function R:GetNumPoints() return #self.points end
	function R:SetSize(w, h) assert(type(w) == "number" and type(h) == "number", "SetSize"); self.w, self.h = w, h end
	function R:SetWidth(w) assert(type(w) == "number", "SetWidth"); self.w = w end
	function R:SetHeight(h) assert(type(h) == "number", "SetHeight"); self.h = h end
	function R:GetWidth() local l, _, r = K.Layout(self); return l and (r - l) or (self.w or 0) end
	function R:GetHeight() local _, b, _, t = K.Layout(self); return b and (t - b) or (self.h or 0) end
	function R:GetSize() return self:GetWidth(), self:GetHeight() end
	function R:SetAlpha(a) assert(type(a) == "number", "SetAlpha"); self.alpha = a end
	function R:GetAlpha() return self.alpha end
	function R:IsShown() return self.shown end
	function R:IsVisible()
		local o = self
		while o do
			if not o.shown then return false end
			o = o.parent
		end
		return true
	end
	local function Subtree(o, out)
		out[#out + 1] = o
		for _, c in ipairs(o.children or {}) do Subtree(c, out) end
		return out
	end
	local function SetShownFlag(self, on)
		if self.shown == on then return end
		local list = Subtree(self, {})
		local before = {}
		for i, o in ipairs(list) do before[i] = o:IsVisible() end
		self.shown = on
		for i, o in ipairs(list) do
			local vis = o:IsVisible()
			if vis ~= before[i] and o.isFrame then
				local fn = o.scripts[vis and "OnShow" or "OnHide"]
				if fn then
					local ok, err = pcall(fn, o)
					if not ok then K.errors[#K.errors + 1] = tostring(err) end
				end
			end
		end
	end
	function R:Show() SetShownFlag(self, true) end
	function R:Hide() SetShownFlag(self, false) end
	function R:SetShown(on) SetShownFlag(self, not not on) end
	function R:SetDrawLayer(layer, sub) self.layer, self.sublevel = layer, sub or 0 end
	function R:GetDrawLayer() return self.layer, self.sublevel end
	function R:CreateAnimationGroup()
		local ag = setmetatable({ otype = "AnimationGroup", target = self, anims = {}, playing = false, scripts = {}, token = 0 }, { __index = K.AG })
		self.groups = self.groups or {}
		self.groups[#self.groups + 1] = ag
		return ag
	end

	-- Textures and font strings
	local T = setmetatable({}, { __index = R })
	function T:SetTexture(path)
		assert(path == nil or type(path) == "string" or type(path) == "number", "SetTexture")
		self.tex, self.color = path, nil
		return true
	end
	function T:GetTexture() return self.tex end
	function T:SetColorTexture(r, g, b, a) self.color, self.tex = { r, g, b, a or 1 }, nil end
	function T:SetTexCoord(...)
		local n = select("#", ...)
		assert(n == 4 or n == 8, "SetTexCoord takes 4 or 8 numbers")
		for i = 1, n do assert(type(select(i, ...)) == "number", "SetTexCoord: number") end
		self.coords = { ... }
	end
	function T:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
	function T:SetBlendMode(m) assert(m == "ADD" or m == "BLEND" or m == "MOD" or m == "ALPHAKEY" or m == "DISABLE", "blend mode"); self.blend = m end
	function T:SetDesaturated(on) self.desat = on end

	local FS = setmetatable({}, { __index = R })
	function FS:SetFont(path, size, flags)
		assert(type(path) == "string" and type(size) == "number", "SetFont")
		assert(flags == nil or type(flags) == "string", "SetFont: flags")
		self.font, self.size, self.flags = path, size, flags
		return true
	end
	function FS:GetFont() return self.font, self.size, self.flags end
	function FS:SetFontObject() end
	function FS:SetText(t) self.text = t ~= nil and tostring(t) or nil end
	function FS:GetText() return self.text end
	function FS:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
	function FS:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
	function FS:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a or 1 } end
	function FS:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
	function FS:SetJustifyH(j) self.justifyH = j end
	function FS:SetJustifyV(j) self.justifyV = j end
	function FS:SetWordWrap(on) self.wrap = on end
	function FS:SetNonSpaceWrap() end
	function FS:SetMaxLines(n) self.maxLines = n end
	-- (the stand-in's estimate: half the font size a character, colour codes taking no room)
	function FS:GetStringWidth()
		local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		return #plain * (self.size or 12) * 0.5
	end
	function FS:IsTruncated() return self.wrap == false and (self.w or 0) > 0 and self:GetStringWidth() > self.w end
	-- (the same estimate: a line is 1.2 times the font size; wrapped text of a set width takes as
	-- many lines as its width needs, each "\n" one more)
	function FS:GetStringHeight()
		local text = self.text or ""
		if text == "" then return 0 end
		local lines = 0
		for part in (text .. "\n"):gmatch("(.-)\n") do
			local plain = part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			local wd = #plain * (self.size or 12) * 0.5
			local n = (self.wrap ~= false and (self.w or 0) > 0) and math.max(1, math.ceil(wd / self.w)) or 1
			lines = lines + n
		end
		return lines * (self.size or 12) * 1.2
	end

	-- Frames
	local F = setmetatable({}, { __index = R })
	local HANDLERS = { OnShow = 1, OnHide = 1, OnEvent = 1, OnClick = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1,
		OnMouseWheel = 1, OnDragStart = 1, OnDragStop = 1, OnSizeChanged = 1,
		OnKeyDown = 1 } -- (the client's keyboard script: the Lottery's Bet takes Enter under the mouse)
	-- (the companion's files never set an OnUpdate, nor a script the stand-in doesn't know; the
	-- core's own windows may, and their scripts are kept but never run here)
	-- (the caller's own file: the core's card may set its OnUpdate inside a companion's click)
	local function FromCompanion()
		local info = debug.getinfo(3, "S")
		return info ~= nil and tostring(info.source):find("Olympus_Arena[/\\]") ~= nil
	end
	function F:SetScript(name, fn)
		if not HANDLERS[name] and FromCompanion() then error(self.otype .. " has no script " .. tostring(name) .. " here (OnUpdate is refused: the companion uses none)", 2) end
		self.scripts[name] = fn
	end
	function F:GetScript(name) return self.scripts[name] end
	function F:HookScript(name, fn)
		local old = self.scripts[name]
		self.scripts[name] = old and function(...) old(...); fn(...) end or fn
	end
	function F:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
	function F:UnregisterEvent(e) if self.events then self.events[e] = nil end end
	-- (the client keeps a frame's level to itself, never in a field of its table: the Find
	-- sheet's own `level` is its row of level choices)
	function F:SetFrameLevel(l) self.frameLevel = l end
	function F:GetFrameLevel() return self.frameLevel or 0 end
	function F:SetFrameStrata(s) self.strata = s end
	function F:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
	function F:EnableMouse(on) self.mouse = not not on end
	function F:IsMouseEnabled() return self.mouse end
	function F:SetMovable(on) self.movable = on end
	function F:SetClampedToScreen() end
	function F:SetToplevel() end
	function F:Raise() self.raised = (self.raised or 0) + 1 end
	function F:RegisterForDrag() end
	function F:RegisterForClicks() end
	function F:StartMoving() end
	function F:StopMovingOrSizing() end
	function F:SetHitRectInsets(l, r, t, b) self.insets = { l, r, t, b } end
	function F:SetScale(s) assert(type(s) == "number" and s > 0, "SetScale"); self.scale = s end
	function F:GetScale() return self.scale or 1 end
	function F:GetEffectiveScale() local s, o = 1, self; while o do s = s * (o.scale or 1); o = o.parent end return s end
	function F:GetChildren() return unpack(self.children) end
	function F:GetRegions() return unpack(self.regions) end
	local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
	function F:CreateTexture(name, layer, template, sub)
		local t = Make(T, "Texture", self)
		t.layer, t.sublevel = layer or "ARTWORK", sub or 0
		assert(LAYERS[t.layer], "layer " .. tostring(layer))
		assert(t.sublevel >= -8 and t.sublevel <= 7, "sublevel " .. tostring(sub))
		self.regions[#self.regions + 1] = t
		return t
	end
	function F:CreateFontString(name, layer, template)
		local fs = Make(FS, "FontString", self)
		fs.layer, fs.sublevel, fs.font, fs.size = layer or "ARTWORK", 0, "Fonts\\FRIZQT__.TTF", 12
		self.regions[#self.regions + 1] = fs
		return fs
	end
	local B = setmetatable({}, { __index = F })
	function B:SetText(t)
		if not self.label then
			self.label = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			self.label:SetPoint("CENTER")
		end
		self.label:SetText(t)
	end
	function B:GetText() return self.label and self.label:GetText() end
	function B:GetFontString() return self.label end
	function B:Enable() self.enabled = true end
	function B:Disable() self.enabled = false end
	function B:IsEnabled() return self.enabled end
	function B:SetEnabled(on) self.enabled = not not on end
	-- (the mouse-over glow the client draws itself: a texture of the button's)
	function B:SetHighlightTexture(file, blend)
		assert(file == nil or type(file) == "string" or type(file) == "number", "SetHighlightTexture")
		assert(blend == nil or blend == "ADD" or blend == "BLEND" or blend == "MOD", "SetHighlightTexture: blend")
		self.highlight = self.highlight or self:CreateTexture(nil, "HIGHLIGHT")
		self.highlight:SetTexture(file)
		self.highlight:SetAllPoints(self)
		return self.highlight
	end
	function B:LockHighlight() self.locked = true end
	function B:UnlockHighlight() self.locked = false end
	function B:Click() if self.enabled ~= false and self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
	local CB = setmetatable({}, { __index = B })
	function CB:SetChecked(on) self.checked = not not on end
	function CB:GetChecked() return self.checked == true end
	local CD = setmetatable({}, { __index = F })
	function CD:SetCooldown(start, dur) assert(type(start) == "number" and type(dur) == "number", "SetCooldown"); self.cd = { start, dur } end
	function CD:Clear() self.cd = nil end
	local S = setmetatable({}, { __index = F })
	function S:SetScrollChild(child)
		assert(type(child) == "table" and child.parent == self, "SetScrollChild")
		self.scrollChild = child
	end
	function S:GetScrollChild() return self.scrollChild end
	function S:EnableMouseWheel(on) self.mouseWheel = not not on end
	function S:SetVerticalScroll(n) assert(type(n) == "number", "SetVerticalScroll"); self.verticalScroll = math.max(0, n) end
	function S:GetVerticalScroll() return self.verticalScroll or 0 end
	function S:GetVerticalScrollRange()
		return math.max(0, (self.scrollChild and self.scrollChild:GetHeight() or 0) - self:GetHeight())
	end

	local KINDS = { Frame = F, Button = B, CheckButton = CB, Cooldown = CD, GameTooltip = F, ScrollFrame = S }
	function K.CreateFrame(kind, name, parent, template)
		local cls = KINDS[kind]
		if not cls then error("CreateFrame: no stand-in for " .. tostring(kind)) end
		if kind == "Cooldown" then assert(template == "CooldownFrameTemplate", "a Cooldown needs its template") end
		local f = Make(cls, kind, parent)
		f.isFrame, f.children, f.regions, f.name = true, {}, {}, name
		if parent then parent.children[#parent.children + 1] = f end
		f.frameLevel = (f.parent and f.parent.frameLevel or 0) + 1
		f.template = template
		if kind == "Button" or kind == "CheckButton" then f.enabled, f.mouse = true, true end
		K.frames[#K.frames + 1] = f
		if name then K.named = K.named or {}; K.named[name] = f end
		if template == "UIPanelButtonTemplate" then f:SetSize(100, 22) end
		if template == "UIPanelCloseButton" or template == "UIPanelCloseButtonDefaultAnchors" then
			f:SetSize(32, 32)
			f:SetScript("OnClick", function(self) self:GetParent():Hide() end)
		end
		-- (1.1.5: ns.Window's metal, Forever's DefaultPanelTemplate: its NineSlice and its title in the
		-- TitleContainer, as the fixture's template keys give them; tests/run.lua models the same.)
		if template == "DefaultPanelTemplate" then
			f.NineSlice = K.CreateFrame("Frame", nil, f)
			f.TitleContainer = K.CreateFrame("Frame", nil, f)
			f.TitleContainer.TitleText = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		end
		return f
	end

	---------------------------------------------------------------------
	-- Animation groups on the world's clock
	---------------------------------------------------------------------
	local A = {}
	A.__index = A
	local function Setter(k) return function(self, v) self[k] = v end end
	for _, k in ipairs({ "Duration", "StartDelay", "EndDelay", "Order", "Smoothing" }) do A["Set" .. k] = Setter(k:sub(1, 1):lower() .. k:sub(2)) end
	function A:GetDuration() return self.duration or 0 end
	function A:SetOffset(x, y) assert(self.kind == "Translation", "SetOffset on " .. self.kind); self.ox, self.oy = x, y end
	function A:SetScaleFrom(x, y) assert(self.kind == "Scale"); self.from = x end
	function A:SetScaleTo(x, y) assert(self.kind == "Scale"); self.to = x end
	function A:SetScale(x, y) assert(self.kind == "Scale"); self.from, self.to = 1, x end
	function A:SetOrigin() end
	function A:SetFromAlpha(a) assert(self.kind == "Alpha"); self.afrom = a end
	function A:SetToAlpha(a) assert(self.kind == "Alpha"); self.ato = a end
	for _, k in ipairs({ "FlipBookRows", "FlipBookColumns", "FlipBookFrames", "FlipBookFrameWidth", "FlipBookFrameHeight" }) do
		A["Set" .. k] = function(self, v) assert(self.kind == "FlipBook", k); self[k] = v end
	end
	function A:SetScript() end
	K.AG = {}
	local AG = K.AG
	local KINDS_A = { Translation = true, Scale = true, Alpha = true, FlipBook = true }
	function AG:CreateAnimation(kind)
		if not KINDS_A[kind] then error("CreateAnimation: no stand-in for " .. tostring(kind)) end
		if kind == "FlipBook" and K.noFlipBook then error("CreateAnimation: unknown type FlipBook") end
		local a = setmetatable({ kind = kind, order = 1, duration = 0, startDelay = 0, endDelay = 0 }, A)
		self.anims[#self.anims + 1] = a
		return a
	end
	function AG:SetLooping(l) self.looping = l end
	function AG:SetToFinalAlpha(on) self.final = on end
	function AG:SetScript(name, fn) self.scripts[name] = fn end
	function AG:GetScript(name) return self.scripts[name] end
	-- The orders, in turn: each lasts its longest animation (delays included).
	local function Plan(g)
		local orders, len = {}, {}
		for _, a in ipairs(g.anims) do
			local o = a.order or 1
			if not len[o] then orders[#orders + 1] = o; len[o] = 0 end
			len[o] = math.max(len[o], (a.startDelay or 0) + (a.duration or 0) + (a.endDelay or 0))
		end
		table.sort(orders)
		local start, t = {}, 0
		for _, o in ipairs(orders) do start[o] = t; t = t + len[o] end
		return start, t
	end
	function AG:GetDuration() local _, t = Plan(self) return t end
	function AG:Play()
		local _, total = Plan(self)
		self.playing, self.t0, self.total = true, K.now(), total
		self.token = self.token + 1
		self.plays = (self.plays or 0) + 1
		local token = self.token
		if not self.looping or self.looping == "NONE" then
			C_Timer.After(total, function()
				if self.token ~= token or not self.playing then return end
				self.playing = false
				self.token = self.token + 1
				local fn = self.scripts.OnFinished
				if fn then fn(self, false) end
			end)
		end
	end
	function AG:Stop() self.playing = false; self.token = self.token + 1 end
	function AG:Finish() self:Stop() end
	function AG:IsPlaying() return self.playing == true end
	local function Smooth(p, how)
		if how == "IN" then return p * p end
		if how == "OUT" then return 1 - (1 - p) * (1 - p) end
		if how == "IN_OUT" then return p * p * (3 - 2 * p) end
		return p
	end
	-- A playing group's effect now: offset (x, y), scale, alpha (nil: none).
	local function Effect(g)
		local start, total = Plan(g)
		local e = K.now() - g.t0
		if g.looping == "REPEAT" and total > 0 then e = e % total
		elseif g.looping == "BOUNCE" and total > 0 then
			local n = math.floor(e / total)
			e = e % total
			if n % 2 == 1 then e = total - e end
		end
		local dx, dy, sc, al = 0, 0, 1, nil
		for _, a in ipairs(g.anims) do
			local lt = e - start[a.order or 1] - (a.startDelay or 0)
			if lt >= 0 then
				local p = (a.duration or 0) > 0 and math.min(1, lt / a.duration) or 1
				p = Smooth(p, a.smoothing)
				if a.kind == "Translation" then dx, dy = dx + (a.ox or 0) * p, dy + (a.oy or 0) * p
				elseif a.kind == "Scale" then local f, t = a.from or 1, a.to or 1; sc = sc * (f + (t - f) * p)
				elseif a.kind == "Alpha" then al = (a.afrom or 1) + ((a.ato or 1) - (a.afrom or 1)) * p end
			end
		end
		return dx, dy, sc, al
	end
	-- A region's own animations now.
	function K.Transform(o)
		local dx, dy, sc, al = 0, 0, 1, nil
		for _, g in ipairs(o.groups or {}) do
			if g.playing then
				local x, y, s, a = Effect(g)
				dx, dy, sc = dx + x, dy + y, sc * s
				if a then al = a end
			end
		end
		return dx, dy, sc, al
	end

	---------------------------------------------------------------------
	-- Layout: rects from anchors (y up), then the animations of the region and its parents
	---------------------------------------------------------------------
	local function PointOf(l, b, r, t, name)
		local x = (name:find("LEFT") and l) or (name:find("RIGHT") and r) or (l + r) / 2
		local y = (name:find("TOP") and t) or (name:find("BOTTOM") and b) or (b + t) / 2
		return x, y
	end
	function K.Layout(o, depth)
		depth = (depth or 0) + 1
		if depth > 60 then error("anchor loop") end
		if o == K.UIParent then return 0, 0, K.screen[1], K.screen[2] end
		local w, h = o.w, o.h
		if o.otype == "FontString" and (not w or w == 0) then w = o:GetStringWidth() end
		if o.otype == "FontString" and not h then h = (o.size or 12) * 1.2 end
		if #o.points == 0 then return nil end
		local xs, ys = {}, {}
		for _, p in ipairs(o.points) do
			local rl, rb, rr, rt = K.Layout(p.rel, depth)
			if not rl then return nil end
			local ax, ay = PointOf(rl, rb, rr, rt, p.relPoint)
			ax, ay = ax + p.x, ay + p.y
			local hx = (p.point:find("LEFT") and "l") or (p.point:find("RIGHT") and "r") or "c"
			local vy = (p.point:find("TOP") and "t") or (p.point:find("BOTTOM") and "b") or "c"
			xs[hx], ys[vy] = ax, ay
		end
		local l, r, b, t
		local sw, sh = w or 0, h or 0
		if xs.l and xs.r then l, r = xs.l, xs.r
		elseif xs.l then l, r = xs.l, xs.l + sw
		elseif xs.r then l, r = xs.r - sw, xs.r
		elseif xs.c then l, r = xs.c - sw / 2, xs.c + sw / 2 end
		if ys.t and ys.b then b, t = ys.b, ys.t
		elseif ys.t then b, t = ys.t - sh, ys.t
		elseif ys.b then b, t = ys.b, ys.b + sh
		elseif ys.c then b, t = ys.c - sh / 2, ys.c + sh / 2 end
		if not (l and b) then return nil end
		return l, b, r, t
	end
	-- Where it is drawn now: its own animations scale it about its centre and move it, and its
	-- parents' animations move it with them.
	function K.Rect(o)
		local l, b, r, t = K.Layout(o)
		if not l then return nil end
		local dx, dy, sc = K.Transform(o)
		local cx, cy, hw, hh = (l + r) / 2 + dx, (b + t) / 2 + dy, (r - l) / 2 * sc, (t - b) / 2 * sc
		local p = o.parent
		while p do
			local px, py = K.Transform(p)
			cx, cy = cx + px, cy + py
			p = p.parent
		end
		return cx - hw, cy - hh, cx + hw, cy + hh
	end
	function K.Within(o, base)
		local l, b, r, t = K.Rect(o)
		local bl, _, _, bt = K.Layout(base)
		if not l or not bl then return nil end
		return l - bl, bt - t, r - l, t - b
	end
	-- Its alpha now (its own and its parents', animations included).
	function K.Alpha(o)
		local a = 1
		while o do
			local _, _, _, al = K.Transform(o)
			a = a * (al or o.alpha or 1)
			o = o.parent
		end
		return a
	end

	-- A click as the player makes it: only on a visible, enabled button that takes the mouse.
	function K.UserClick(b)
		if not (b and b:IsVisible() and b.enabled ~= false and b.mouse ~= false) then return false end
		local fn = b.scripts.OnClick
		if fn then fn(b, "LeftButton") end
		return true
	end
	-- Escape: the client's CloseSpecialWindows hides every shown frame named in UISpecialFrames.
	function K.Escape()
		local found
		for _, name in pairs(K.special) do
			local f = K.named and K.named[name]
			if f and f:IsShown() then f:Hide(); found = true end
		end
		return found
	end

	K.UIParent = K.CreateFrame("Frame", nil, nil)
	K.UIParent.parent = nil
	K.GameTooltip = K.CreateFrame("GameTooltip", nil, K.UIParent)
	K.GameTooltip.lines = {}
	function K.GameTooltip:SetOwner(o) self.owner, self.lines = o, {} end
	function K.GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
	K.GameTooltip:Hide()
	K.special = {}
	-- Into a client's globals (the world swaps them in for each call as that client).
	function K.Install(g)
		g.CreateFrame = K.CreateFrame
		g.UIParent = K.UIParent
		g.GameTooltip = K.GameTooltip
		g.UISpecialFrames = K.special
		g.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
		g.GetScreenWidth = function() return K.screen[1] end
		g.GetScreenHeight = function() return K.screen[2] end
	end
	return K
end

return UI
