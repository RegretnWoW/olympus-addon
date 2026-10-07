local ADDON, ns = ...
local L = ns.L

-- A minimap-edge pointer to the King.  This is deliberately independent of the crown:
-- it has its own pin reference, its own frame and its own visibility policy.  The crown's
-- position/layer lease remains the only source of coordinates, so this file never causes a
-- player to share anything and never changes the King's existing map or layer switches.
--
-- What it shows (Arrow.Target; Arrow.State().reason names the case):
--   his map, both fresh layer reports agree    "shown": the native arrow, untinted ("exact")
--   his map, another or an unknown layer       "layer", "layer-stale": the same arrow, tinted
--                                              ("maybe": he may be on another layer)
--   another zone of his continent              "zone": the tinted arrow at his world position
--                                              (HereBeDragons' world coordinates of his map
--                                              x, y): layers cannot be compared across zones;
--                                              inside the minimap's range a crown as tinted
--                                              marks his spot, where his own crown is not drawn
--   nothing                                    "continent" (another world instance), "instance"
--                                              (a dungeon or battleground), "world" (no world
--                                              coordinates for either map), "offline", ...
--
-- K6~1~<G|L>~<1 on|0 off>~<server time>~<guild>
--   G: the King or a current High Councillor, over the realm channel.
--   L: an officer currently authorized by The Watch, over Blizzard's guild distribution.
-- The game stamps the sender.  On clients with logged addon messages, an unlogged control is
-- rejected.  Controls are short leases and their send capability is checked again when the
-- queued message actually reaches Blizzard's API.

local Arrow = {}
ns.KingArrow = Arrow

Arrow.PROTOCOL = 1
Arrow.CONTROL_REPEAT = 5 * 60
Arrow.CONTROL_LEASE = 20 * 60
Arrow.CONTROL_MAX_AGE = 10 * 60
Arrow.DATE_AHEAD = 60
Arrow.LAYER_FRESH = 120
Arrow.NATIVE_ATLAS = "UI-HUD-Minimap-Arrow-Player"
Arrow.NATIVE_TEXTURE = "Interface\\Minimap\\MinimapArrow"
-- How sure the arrow is that he is there for us.  "maybe" is greyed, cooler and half seen, so it
-- never reads as the certain arrow: another layer, a layer nobody reported lately, another zone.
Arrow.TINTS = {
	exact = { r = 1, g = 1, b = 1, a = 1, desaturate = false },
	maybe = { r = 0.55, g = 0.75, b = 1, a = 0.55, desaturate = true },
}

local Pins = ns.Pins and ns.Pins()
local pinRef = {}
local frame, drawn, lastReason
local kingWorld -- his world position for the lease's last map x, y: converted once per position
local policies = { global = nil, guild = nil }
local loadedRdb
local stats = { taken = 0, refused = 0, replay = 0, sent = 0, revoked = 0, world = 0 }

local function Clock()
	return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now()
end

local function Fold(s)
	return ns.Fold(tostring(s or ""))
end

local function CleanGuild(guild, empty)
	if type(guild) ~= "string" then return nil end
	guild = guild:gsub("^%s+", ""):gsub("%s+$", "")
	if guild == "" then return empty and "" or nil end
	if #guild > 72 or guild:find("[~|%c]") or not ns.IsFederation(guild) then return nil end
	return guild
end

local function OwnGuild()
	local guild = GetGuildInfo and GetGuildInfo("player")
	return CleanGuild(guild, false)
end

local function CleanSender(sender)
	if type(sender) ~= "string" or sender == "" or #sender > 96 or sender:find("[~|%^%c]") then return nil end
	sender = ns.FullName(sender)
	if type(sender) ~= "string" or sender == "" or not sender:find("-", 1, true) then return nil end
	return sender
end

local function Hidden(name, guild)
	local M = ns.Moderation
	return M and not M.missing and M.Hides and M.Hides(name, guild) ~= nil
end

-- The global switch is intentionally narrower than Moderation.IsIssuer: being a Steward or a
-- Hand does not grant this switch.  A councillor still has to be a current, non-hidden issuer.
local function GlobalController(name)
	name = CleanSender(name)
	if not name then return false, 0 end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) then return true, 3 end
	local M = ns.Moderation
	if ns.IsHighCouncillor and ns.IsHighCouncillor(name)
		and M and not M.missing and M.IsIssuer and M.IsIssuer(name) and not Hidden(name) then
		return true, 2
	end
	return false, 0
end

local function GuildController(name, guild)
	name, guild = CleanSender(name), CleanGuild(guild, false)
	if not name or not guild or guild ~= OwnGuild() then return false, 0 end
	local W = ns.Watch
	if not (W and not W.missing and W.IsAuthorized and W.IsAuthorized(name)) then return false, 0 end
	return true, 1
end

local function Controller(scope, name, guild)
	if scope == "global" then return GlobalController(name) end
	if scope == "guild" then return GuildController(name, guild) end
	return false, 0
end

function Arrow.CanControl(scope, name, guild)
	name = name or ns.me
	if scope then return Controller(scope, name, guild or OwnGuild()) == true end
	if GlobalController(name) then return true, "global" end
	if GuildController(name, guild or OwnGuild()) then return true, "guild" end
	return false
end

local function CopyPolicy(e, heard)
	if type(e) ~= "table" then return nil end
	local scope = e.scope == "global" and "global" or (e.scope == "guild" and "guild" or nil)
	local by, enabled, at = CleanSender(e.by), e.enabled, tonumber(e.at)
	local guild = scope == "guild" and CleanGuild(e.guild, false) or CleanGuild(e.guild or "", true)
	if not scope or not by or type(enabled) ~= "boolean" or not at or at ~= math.floor(at) or not guild then return nil end
	local h = tonumber(heard ~= nil and heard or e.heard)
	if not h or h ~= math.floor(h) then h = -math.huge end
	return { scope = scope, by = by, enabled = enabled, at = at, heard = h, guild = guild }
end

local function Saved(create)
	if type(ns.rdb) ~= "table" then return nil end
	local saved = ns.rdb.kingArrowPolicies
	if type(saved) ~= "table" or saved.version ~= Arrow.PROTOCOL then
		if not create then return nil end
		saved = { version = Arrow.PROTOCOL, guilds = {} }
		ns.rdb.kingArrowPolicies = saved
	end
	if type(saved.guilds) ~= "table" then saved.guilds = {} end
	return saved
end

local function EnsureLoaded()
	if loadedRdb == ns.rdb then return end
	loadedRdb = ns.rdb
	policies = { global = nil, guild = nil }
	local saved = Saved(false)
	if not saved then return end
	policies.global = CopyPolicy(saved.global)
	local guild = OwnGuild()
	local e = guild and CopyPolicy(saved.guilds[Fold(guild)])
	if e and e.guild == guild then policies.guild = e end
end

local function SavePolicy(e)
	local saved = Saved(true)
	if not saved then return end
	local copy = { scope = e.scope, by = e.by, enabled = e.enabled, at = e.at,
		heard = e.heard, guild = e.guild }
	if e.scope == "global" then saved.global = copy
	else saved.guilds[Fold(e.guild)] = copy end
end

local function SamePolicy(a, b)
	return a and b and a.scope == b.scope and a.by == b.by and a.enabled == b.enabled
		and a.at == b.at and a.guild == b.guild
end

-- A deterministic tie makes clients converge if two authorized people act in the same server
-- second.  Honest clients also make their own timestamps strictly increase.
-- 1.2.0: rank before recency while the word kept is in force (its lease): a High Councillor's
-- newer "on" never beats the King's "off". A lapsed word gives way to the newest.
local function Compare(a, b)
	if not b then return 1 end
	local _, aw = Controller(a.scope, a.by, a.guild)
	local _, bw = Controller(b.scope, b.by, b.guild)
	local inForce = bw > 0 and type(b.heard) == "number" and Clock() - b.heard <= Arrow.CONTROL_LEASE
	if aw ~= bw and inForce then return aw > bw and 1 or -1 end
	if a.at ~= b.at then return a.at > b.at and 1 or -1 end
	if aw ~= bw then return aw > bw and 1 or -1 end
	local ak, bk = Fold(a.by), Fold(b.by)
	if ak ~= bk then return ak > bk and 1 or -1 end
	if a.enabled ~= b.enabled then return a.enabled == false and 1 or -1 end
	return 0
end

local function Take(e, received)
	EnsureLoaded()
	local now = Clock()
	if e.at > now + Arrow.DATE_AHEAD or e.at < now - Arrow.CONTROL_MAX_AGE then
		stats.refused = stats.refused + 1
		return false, "date"
	end
	local current = policies[e.scope]
	if SamePolicy(e, current) then
		current.heard = received
		SavePolicy(current)
		return true, "repeat"
	end
	if Compare(e, current) <= 0 then
		stats.replay = stats.replay + 1
		return false, "replay"
	end
	e.heard = received
	policies[e.scope] = e
	SavePolicy(e)
	stats.taken = stats.taken + 1
	return true, "taken"
end

local function ActivePolicy(scope)
	EnsureLoaded()
	local e = policies[scope]
	if not e then return nil end
	local now = Clock()
	if e.heard > now + Arrow.DATE_AHEAD or now - e.heard > Arrow.CONTROL_LEASE then return nil end
	if not Controller(scope, e.by, e.guild) then return nil end
	if scope == "guild" and e.guild ~= OwnGuild() then return nil end
	return e
end

function Arrow.ScopeEnabled(scope)
	local e = ActivePolicy(scope)
	return not e or e.enabled ~= false
end

function Arrow.Enabled()
	return Arrow.ScopeEnabled("global") and Arrow.ScopeEnabled("guild")
end

local function Remove(reason)
	lastReason = reason
	if drawn and Pins and Pins.RemoveMinimapIcon and frame then
		pcall(Pins.RemoveMinimapIcon, Pins, pinRef, frame)
	end
	drawn = nil
	if frame then
		if frame.icon and frame.icon.SetAlpha then frame.icon:SetAlpha(0) end
		if frame.mark then frame.mark:SetAlpha(0) end
		if frame.Hide then frame:Hide() end
	end
	return false, reason
end

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Coordinate(v)
	return type(v) == "number" and not Secret(v) and v == v and v >= 0 and v <= 1
end

local function Fresh(t, now, limit)
	return type(t) == "number" and not Secret(t) and now >= t and now - t <= limit
end

local function Finite(v)
	return type(v) == "number" and not Secret(v) and v == v and v ~= math.huge and v ~= -math.huge
end

-- HereBeDragons' map data (the library the pins use), only if it loaded with its world function.
local function MapData()
	local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
	if hbd and type(hbd.GetWorldCoordinatesFromZone) == "function" then return hbd end
	return nil
end

-- A map x, y in world yards and its world instance (the continent), or nil.
local function World(hbd, mapID, x, y)
	local ok, wx, wy, instanceID = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
	if ok and Finite(wx) and Finite(wy) and Finite(instanceID) then return wx, wy, instanceID end
	return nil
end

-- His world position, converted once for each position his lease reports (not every refresh).
local function KingWorld(hbd, at)
	local c = kingWorld
	if not (c and c.mapID == at.mapID and c.x == at.x and c.y == at.y) then
		c = { mapID = at.mapID, x = at.x, y = at.y }
		c.wx, c.wy, c.instanceID = World(hbd, at.mapID, at.x, at.y)
		kingWorld = c
		stats.world = stats.world + 1
	end
	return c.instanceID and c or nil
end

-- Whether his own crown is on our minimap from mapID, another map than his: the crown is a map
-- pin shown in his parent zone too (King.lua RefreshCrown: AddMinimapIconMap, showInParentZone),
-- which the library draws from a Zone, Dungeon or Micro map above his and from nowhere else
-- (HereBeDragons-Pins-2.0.lua, UpdateMinimapPins and IsParentMap).  From a neighbouring zone, a
-- city beside his zone or a cave inside it, it is not drawn.
local function CrownAbove(hbd, kingMap, mapID)
	local data, kinds = hbd.mapData, Enum and Enum.UIMapType
	if type(data) ~= "table" or type(kinds) ~= "table" or type(data[kingMap]) ~= "table" then return false end
	local parent = data[kingMap].parent
	for _ = 1, 16 do
		local m = parent and data[parent]
		if type(m) ~= "table" then return false end
		if m.mapType ~= kinds.Zone and m.mapType ~= kinds.Dungeon and m.mapType ~= kinds.Micro then return false end
		if parent == mapID then return true end
		parent = m.parent
	end
	return false
end

-- The arrow is more conservative than the crown.  A recent crown alone proves that the King
-- is online, but not that this player is in his copy of the zone: only both exact layer reports,
-- fresh and agreeing, with the player's live map API still placing him on that map, make the
-- arrow "exact".  Otherwise it is "maybe" (Arrow.TINTS), or nothing off his continent.
-- Returns the lease, the reason, "exact" or "maybe", his world position for another zone (nil on
-- his map: the map pin then stays limited to his map) and, for another zone, whether the arrow
-- marks his spot itself inside the minimap's range (his own crown is not drawn there); nil and the
-- reason for nothing.
function Arrow.Target()
	if not Arrow.Enabled() then return nil, "disabled" end
	if IsInInstance and IsInInstance() then return nil, "instance" end
	local K = ns.King
	local at = K and K.Location and K.Location()
	local now = ns.Now()
	local expire = K and tonumber(K.LOCATION_EXPIRE) or 45
	if type(at) ~= "table" or not Fresh(at.t, now, expire) then return nil, "offline" end
	if not CleanSender(at.from) or not (ns.IsKingCharacter and ns.IsKingCharacter(at.from)) then return nil, "identity" end
	if ns.me and ns.FullName(ns.me) == ns.FullName(at.from) then return nil, "self" end
	local realm = ns.RealmOf(at.from)
	if realm and ns.realm and ns.realm ~= "?" and realm ~= ns.realm then return nil, "realm" end
	if type(at.mapID) ~= "number" or Secret(at.mapID) or not Coordinate(at.x) or not Coordinate(at.y) then return nil, "position" end
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil, "map-api" end
	local mapID = C_Map.GetBestMapForUnit("player")
	if type(mapID) ~= "number" or Secret(mapID) then return nil, "map" end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos or type(pos.GetXY) ~= "function" then return nil, "player-position" end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok or not Coordinate(x) or not Coordinate(y) or (x == 0 and y == 0) then return nil, "player-position" end
	if mapID ~= at.mapID then
		-- Another zone: the same world instance (HereBeDragons) is the same continent.
		local hbd = MapData()
		if not hbd then return nil, "map-api" end
		local world = KingWorld(hbd, at)
		local _, _, ours = World(hbd, mapID, x, y)
		if not world or not ours then return nil, "world" end
		if ours ~= world.instanceID then return nil, "continent" end
		return at, "zone", "maybe", world, not CrownAbove(hbd, at.mapID, mapID)
	end
	local layers = ns.Layers
	local mine = layers and layers.Mine and layers.Mine()
	local there = layers and layers.Of and layers.Of(at.from, true)
	if type(mine) ~= "table" or type(there) ~= "table"
		or not Fresh(mine.t, now, Arrow.LAYER_FRESH) or not Fresh(there.t, now, Arrow.LAYER_FRESH) then
		return at, "layer-stale", "maybe"
	end
	if mine.mapID ~= at.mapID or there.mapID ~= at.mapID or type(mine.zoneUID) ~= "number"
		or type(there.zoneUID) ~= "number" or mine.zoneUID ~= there.zoneUID then return at, "layer", "maybe" end
	return at, "shown", "exact"
end

local function MakeFrame()
	if frame then return frame end
	if not Pins or type(Minimap) ~= "table" then return nil end -- gp:minimap
	local f = CreateFrame("Frame", nil, Minimap) -- gp:minimap
	if not f or not f.CreateTexture or not f.SetSize or not f.SetScript then return nil end
	f.olympus = true
	f:SetSize(26, 26)
	if f.EnableMouse then f:EnableMouse(false) end
	if f.SetFrameLevel and Minimap.GetFrameLevel then f:SetFrameLevel(Minimap:GetFrameLevel() + 1) end
	local icon = f:CreateTexture(nil, "OVERLAY")
	if not icon or type(icon.SetAlpha) ~= "function" or type(icon.SetRotation) ~= "function" then return nil end
	local native = false
	if type(icon.SetAtlas) == "function" then
		local available = true
		if C_Texture and C_Texture.GetAtlasInfo then
			local ok, info = pcall(C_Texture.GetAtlasInfo, Arrow.NATIVE_ATLAS)
			available = ok and info ~= nil
		end
		if available then native = pcall(icon.SetAtlas, icon, Arrow.NATIVE_ATLAS, true) end
	end
	if not native and type(icon.SetTexture) == "function" then
		native = pcall(icon.SetTexture, icon, Arrow.NATIVE_TEXTURE)
	end
	if not native then return nil end
	if icon.SetAllPoints then icon:SetAllPoints() end
	if icon.SetBlendMode then icon:SetBlendMode("ADD") end
	icon:SetAlpha(0)
	f.icon = icon
	-- His spot inside the minimap's range from another zone, where his own crown is not drawn:
	-- the crown's art, upright, 16 by 16 as the crown (King.lua, Crown).  Without it, only the arrow.
	local mark = ns.CROWN_ICON and f:CreateTexture(nil, "OVERLAY")
	if mark and type(mark.SetAlpha) == "function" and type(mark.SetTexture) == "function"
		and pcall(mark.SetTexture, mark, ns.CROWN_ICON) then
		if mark.SetSize then mark:SetSize(16, 16) end
		if mark.SetPoint then mark:SetPoint("CENTER", f, "CENTER", 0, 0) end
		mark:SetAlpha(0)
		f.mark = mark
	end
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (tonumber(dt) or 0)
		if elapsed < 0.08 then return end
		elapsed = 0
		Arrow.UpdateDirection()
	end)
	frame = f
	return frame
end

local function Atan2(y, x)
	if math.atan2 then return math.atan2(y, x) end
	if x > 0 then return math.atan(y / x) end
	if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
	if y > 0 then return math.pi / 2 end
	if y < 0 then return -math.pi / 2 end
	return 0
end

-- The crown marker's alpha: the arrow's own while it marks his spot, otherwise transparent.
local function Mark(on)
	local mark = frame and frame.mark
	if mark then mark:SetAlpha(on and drawn and drawn.alpha or 0) end
end

-- HereBeDragons owns the edge position.  Rotation uses that on-screen vector, so it remains
-- correct when the player rotates the minimap.  Inside minimap range the arrow texture is
-- transparent: his own crown marks him where it is drawn, the crown marker where it is not.
function Arrow.UpdateDirection()
	if not drawn or not frame or not frame.icon then return false end
	local edge = Pins and Pins.IsMinimapIconOnEdge and Pins:IsMinimapIconOnEdge(frame)
	if edge ~= true then
		frame.icon:SetAlpha(0)
		Mark(edge == false and drawn.mark)
		return false
	end
	Mark(false)
	if not (frame.GetCenter and Minimap and Minimap.GetCenter) then frame.icon:SetAlpha(0); return false end
	local fx, fy = frame:GetCenter()
	local mx, my = Minimap:GetCenter()
	if type(fx) ~= "number" or type(fy) ~= "number" or type(mx) ~= "number" or type(my) ~= "number" then
		frame.icon:SetAlpha(0)
		return false
	end
	local dx, dy = fx - mx, fy - my
	if dx == 0 and dy == 0 then frame.icon:SetAlpha(0); return false end
	-- SetRotation turns counter-clockwise; the texture points up.  The angle from up to the pin
	-- is atan2(dx, dy) clockwise, so the texture turns by its negative (as the game's own edge
	-- arrow does: Blizzard_QuestNavigation/SuperTrackedFrame.lua, UpdateArrow).
	local ok = pcall(frame.icon.SetRotation, frame.icon, -Atan2(dx, dy))
	frame.icon:SetAlpha(ok and drawn.alpha or 0)
	return ok
end

-- The tint for how sure the arrow is: set when that changes, never on the frame's OnUpdate.
local function Paint(certainty)
	local tint = Arrow.TINTS[certainty] or Arrow.TINTS.maybe
	drawn.alpha = tint.a
	if drawn.certainty == certainty then return end
	drawn.certainty = certainty
	for _, texture in ipairs({ frame.icon, frame.mark }) do
		if type(texture.SetDesaturated) == "function" then pcall(texture.SetDesaturated, texture, tint.desaturate) end
		if type(texture.SetVertexColor) == "function" then pcall(texture.SetVertexColor, texture, tint.r, tint.g, tint.b) end
	end
end

function Arrow.Refresh()
	local at, why, certainty, world, marks = Arrow.Target()
	if not at then return Remove(why) end
	local f = MakeFrame()
	if not f then return Remove("frame-api") end
	local mode = world and "world" or "map"
	if drawn and drawn.mode == mode and drawn.mapID == at.mapID and drawn.x == at.x and drawn.y == at.y then
		drawn.mark = marks == true
		Paint(certainty)
		lastReason = why
		Arrow.UpdateDirection()
		return true
	end
	if drawn then pcall(Pins.RemoveMinimapIcon, Pins, pinRef, f) end
	drawn = nil
	local ok, added
	if world then
		-- His world position, shown wherever we stand on his continent (the map pin below is
		-- shown only while we are on his map: HereBeDragons-Pins, UpdateMinimapPins).
		if type(Pins.AddMinimapIconWorld) ~= "function" then return Remove("pin-api") end
		ok, added = pcall(Pins.AddMinimapIconWorld, Pins, pinRef, f, world.instanceID, world.wx, world.wy, true)
	else
		ok, added = pcall(Pins.AddMinimapIconMap, Pins, pinRef, f, at.mapID, at.x, at.y, true, true)
	end
	if not ok then return Remove("pin-api") end
	-- The library refuses a map pin only for a map it has no world coordinates for.
	if added ~= true then return Remove("world") end
	drawn = { mode = mode, mapID = at.mapID, x = at.x, y = at.y, mark = marks == true }
	Paint(certainty)
	lastReason = why
	Arrow.UpdateDirection()
	return true
end

local function Message(e)
	return ("K6~%d~%s~%s~%d~%s"):format(Arrow.PROTOCOL,
		e.scope == "global" and "G" or "L", e.enabled and "1" or "0", e.at, e.guild or "")
end

local function OwnChoice()
	local e = ns.db and CopyPolicy(ns.db.kingArrowControl)
	if not e or e.by ~= ns.FullName(ns.me) then return nil end
	if e.scope == "guild" and e.guild ~= OwnGuild() then return nil end
	return e
end

local function StillOwn(e, msg)
	local own = OwnChoice()
	if not own or not SamePolicy(own, e) or Message(own) ~= msg then stats.revoked = stats.revoked + 1; return false, "changed" end
	if not ns.IsMember or not ns.IsMember() then stats.revoked = stats.revoked + 1; return false, "left" end
	if not Controller(e.scope, ns.me, e.guild) then stats.revoked = stats.revoked + 1; return false, "revoked" end
	if e.scope == "guild" and e.guild ~= OwnGuild() then stats.revoked = stats.revoked + 1; return false, "guild" end
	local now = Clock()
	if e.at > now + Arrow.DATE_AHEAD or e.at < now - Arrow.CONTROL_MAX_AGE then return false, "late" end
	return true
end

local function SendPolicy(e)
	local msg = Message(e)
	local dist = e.scope == "global" and "CHANNEL" or "GUILD"
	return ns.Comm.Send(dist, msg, "king-arrow-" .. e.scope, true, true, function(sent)
		if sent then stats.sent = stats.sent + 1 end
	end, { owner = Arrow, guard = function() return StillOwn(e, msg) end })
end

function Arrow.SetEnabled(on, scope, quiet)
	if type(on) ~= "boolean" then return false, "value" end
	local can, chosen = Arrow.CanControl(scope, ns.me, OwnGuild())
	if not can then
		if not quiet then ns.Print(L.KING_ARROW_DENIED) end
		return false, "access"
	end
	scope = scope or chosen
	local guild = scope == "guild" and OwnGuild() or ""
	local previous = OwnChoice()
	local current = ActivePolicy(scope)
	local at = math.floor(Clock())
	if previous then at = math.max(at, previous.at + 1) end
	if current and current.by == ns.FullName(ns.me) then at = math.max(at, current.at + 1) end
	if at > Clock() + Arrow.DATE_AHEAD then return false, "rate" end
	local e = { scope = scope, by = ns.FullName(ns.me), enabled = on, at = at,
		heard = Clock(), guild = guild }
	ns.db.kingArrowControl = { scope = e.scope, by = e.by, enabled = e.enabled, at = e.at,
		heard = e.heard, guild = e.guild }
	local taken, why = Take(e, e.heard)
	if not taken then return false, why end
	SendPolicy(e)
	Arrow.Refresh()
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	if not quiet then ns.Print(on and L.KING_ARROW_ENABLED or L.KING_ARROW_DISABLED) end
	return true, scope
end

function Arrow.RepeatOwn()
	local e = OwnChoice()
	if not e or not Controller(e.scope, ns.me, e.guild) then return false end
	-- (1.2.0: never stamped again past a higher rank's later word, in force or lapsed: the King's
	-- "off" is not undone by a councillor's client repeating its older "on" once the King is gone.)
	EnsureLoaded()
	local kept = policies[e.scope]
	if kept and kept.at > e.at and Fold(kept.by) ~= Fold(ns.FullName(ns.me)) then
		local _, mine = Controller(e.scope, ns.me, e.guild)
		local _, theirs = Controller(kept.scope, kept.by, kept.guild)
		if theirs > mine then return false end
	end
	-- A fresh server timestamp makes an intercepted older control useless; an honest client never
	-- extends an old wire message indefinitely.
	return Arrow.SetEnabled(e.enabled, e.scope, true)
end

function Arrow.Handle(dist, sender, text)
	if type(text) ~= "string" or #text > 255 then stats.refused = stats.refused + 1; return false, "shape" end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged
		and not ns.Comm.DeliveredLogged() then stats.refused = stats.refused + 1; return false, "unlogged" end
	local version, wireScope, value, at, wireGuild = text:match("^K6~(%d+)~([GL])~([01])~(%d+)~([^~]*)$")
	if tonumber(version) ~= Arrow.PROTOCOL then stats.refused = stats.refused + 1; return false, "shape" end
	local scope = wireScope == "G" and "global" or "guild"
	if (scope == "global" and dist ~= "CHANNEL") or (scope == "guild" and dist ~= "GUILD") then
		stats.refused = stats.refused + 1
		return false, "distribution"
	end
	sender = CleanSender(sender)
	local guild = scope == "guild" and CleanGuild(wireGuild, false) or CleanGuild(wireGuild, true)
	if not sender or not guild then stats.refused = stats.refused + 1; return false, "identity" end
	if scope == "guild" and guild ~= OwnGuild() then stats.refused = stats.refused + 1; return false, "guild" end
	if not Controller(scope, sender, guild) then stats.refused = stats.refused + 1; return false, "access" end
	local e = { scope = scope, by = sender, enabled = value == "1", at = tonumber(at), guild = guild }
	local ok, why = Take(e, Clock())
	if ok then
		Arrow.Refresh()
		if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	end
	return ok, why
end

function Arrow.Slash(rest)
	local word = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if word == "" then
		ns.Print(L.KING_ARROW_STATUS:format(Arrow.Enabled() and L.KING_ARROW_ON or L.KING_ARROW_OFF))
		return true
	end
	if word ~= "on" and word ~= "off" then ns.Print(L.KING_ARROW_USAGE); return false, "usage" end
	return Arrow.SetEnabled(word == "on")
end

function Arrow.ControlLines(scope)
	local can, chosen = Arrow.CanControl(scope, ns.me, OwnGuild())
	if not can then return {} end
	scope = scope or chosen
	local on = Arrow.ScopeEnabled(scope)
	return { {
		header = true,
		text = "|T" .. Arrow.NATIVE_TEXTURE .. ":14:14|t " .. L.KING_ARROW_TITLE,
		right = on and "|cff40ff40" .. L.KING_ARROW_ON .. "|r" or "|cffff6060" .. L.KING_ARROW_OFF .. "|r",
		onClick = function() Arrow.SetEnabled(not Arrow.ScopeEnabled(scope), scope) end,
		tooltip = function(tt)
			tt:AddLine(L.KING_ARROW_TITLE, 1, 0.82, 0)
			tt:AddLine(scope == "global" and L.KING_ARROW_GLOBAL_TIP or L.KING_ARROW_GUILD_TIP, 1, 1, 1, true)
		end,
	} }
end

function Arrow.State()
	EnsureLoaded()
	return { enabled = Arrow.Enabled(), global = policies.global, guild = policies.guild,
		drawn = drawn, reason = lastReason, certainty = drawn and drawn.certainty or nil,
		mode = drawn and drawn.mode or nil, mark = drawn and drawn.mark, frame = frame, stats = stats,
		pinRef = pinRef }
end

function Arrow.ResetForTests()
	Remove("reset")
	policies, loadedRdb, kingWorld = { global = nil, guild = nil }, nil, nil
	for key in pairs(stats) do stats[key] = 0 end
end

ns.Comm.Handle("K6", function(...) Arrow.Handle(...) end)

for _, event in ipairs({ "KING_LOCATION_CHANGED", "LAYERS_CHANGED", "LAYER_SHARING_CHANGED", "DATA_CHANGED" }) do
	ns.On(event, function() Arrow.Refresh() end)
end

ns.On("LOGIN", function()
	EnsureLoaded()
	Arrow.RepeatOwn()
	Arrow.Refresh()
	ns.Every(1, "king minimap arrow", Arrow.Refresh)
	ns.Every(Arrow.CONTROL_REPEAT, "king minimap arrow policy", Arrow.RepeatOwn)
end)
