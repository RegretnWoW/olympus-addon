local ADDON, ns = ...
local L = ns.L

-- Layer hop: instead of begging in chat for an invite to someone's layer, a player asks the
-- addon. The ask goes out on the Olympus channel with the layer wanted (a zone and the zone
-- UID read from NPC GUIDs, see Layers.lua). Players on that layer who can invite answer the
-- asker alone, each only with a chance scaled to how many are there, so a crowded layer sends
-- a handful of offers instead of hundreds. The asker draws one at random, favouring players
-- outside a group and with fewer recent invites, so many askers spread over many helpers.
-- That helper gets "X wants to join your layer" (or invites at once, if they chose that) and
-- says no when they can't; no answer or a no, the asker tries the next offer. The invite is
-- accepted for the asker when the helper is one the addon can vouch for (Hop.Trusted), never
-- with the gamepad UI (the game's invite window and the player's click otherwise), the game
-- moves them to the helper's layer, and their addon takes them out of the group once it sees
-- the move. The main use: joining the King's layer while he is online. Players alone on his
-- layer are asked once whether the addon may do all of it for them (invite, and let the guest
-- go after a while: the guest's addon leaves, since only a click may remove someone from a
-- group).
--   LQ~<id>~<mapID>~<zoneUID>    (channel) who on this layer can invite me?
--   LO~<id>~<group>~<load>       (whisper) I can: my group size (0 = none), my recent invites
--   LR~<id>                      (whisper) please invite me
--   LN~<id>                      (whisper) I can't now
--   LX~<id>                      (whisper) your time in my group is up: please leave it

local Hop = {}
ns.Hop = Hop

Hop.OFFERS = 6          -- offers wanted per ask, however crowded the layer
Hop.WINDOW = 3          -- seconds the asker collects offers before choosing
Hop.NOBODY = 15         -- no offer at all this long after the ask: nobody can
Hop.WAIT = 30           -- seconds a chosen helper has to invite (their window closes at 20)
Hop.POPUP_TIME = 20     -- the helper's window
Hop.ACCEPT_WAIT = 15    -- invite accepted, and no group this long after: next helper
Hop.TRIES = 3           -- helpers asked in turn before giving up
Hop.ASK_GAP = 20        -- one ask every 20 seconds
Hop.BACKOFF = { 20, 60, 180 } -- after 1, 2, 3+ asks in a row that found nobody or got no invite:
                        -- seconds from the last of them to the next ask
Hop.BACKOFF_RESET = 600 -- ...forgotten after this long
Hop.BRAKE_WINDOW = 10   -- asks heard for one layer in this many seconds...
Hop.BRAKE_ASKS = 10     -- ...from more askers than this: our own ask waits a little
Hop.JOIN_WAIT = 20      -- in the group this long without seeing the move: offer to leave anyway
Hop.HELP_GAP = 60       -- the same asker is answered once a minute
Hop.OFFER_GAP = 10      -- a helper offers once every 10 seconds at most
Hop.DECLINES = 2        -- after this many Not now / no answer in a row...
Hop.PAUSE = 300         -- ...no requests for 5 minutes
Hop.LAYER_FRESH = 600   -- our layer counts this long after the last NPC seen
Hop.RECENT = 600        -- invites counted in the load we announce
Hop.MAX_OFFERS = 30     -- offers kept per ask
Hop.GUEST_TIME = 90     -- a guest the addon invited on its own is let go after this long
Hop.PROMPT_EVERY = 10   -- how often we check whether we are alone on the King's layer

-- Swappable in tests.
Hop.random = math.random
Hop.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local ask             -- our own request in progress
local lastAsk = -math.huge
local discoveryHandoff = false -- only consensus/an official layer may bypass its preceding Q gap
local fails, failedAt = 0, -math.huge -- our asks in a row that found nobody or got no invite
-- Asks heard on the channel for BRAKE_WINDOW, per layer and asker: { ["mapID:zoneUID"] = { [short] = t } }.
local heard = {}
-- Askers are keyed by short name: the channel and whispers may not both carry the realm.
local offered = {}    -- [id .. asker] = { t, mapID, zoneUID }: bind a request to the layer offered
local answeredAt = {} -- [asker] = t
local lastOffer, declines, pausedUntil = -math.huge, 0, -math.huge
local pending         -- the request on screen: { from, id, t }
local recent = {}     -- times of our last invites
local stats = { asks = 0, offers = 0, requests = 0, invites = 0, noes = 0, joins = 0, moves = 0, releases = 0,
	autoBlocked = 0 }
local guests = {}     -- [short name] = { name, id, t, release }: players we invited for a hop
local kingMode        -- this session's answer to the King's layer window: auto, manual or no
-- 1.1.5 (GitHub issue #50): "Always invite" clicked while leading a party or raid of our own also
-- covers that group, as long as it lasts. This session's alone, never saved: after a /reload the
-- window asks once more. Cleared when the group ends (Hop.OnRoster), and by /oly layerauto off.
local groupAuto
local promptShown, lastPromptCheck = false, -math.huge
local privateHinted = false -- told this session what an ask says while the player shares nothing

local function Changed() ns.Fire("HOP_CHANGED") end

---------------------------------------------------------------------------
-- Helping: who can invite
---------------------------------------------------------------------------

-- Group size (0 = none) and whether we can invite one more: alone, or the leader (or an
-- assistant of a raid) with a free seat. A full party can't: making it a raid is a click.
function Hop.GroupState()
	if not (IsInGroup and IsInGroup()) then return 0, true end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 1
	local raid = IsInRaid and IsInRaid()
	local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
	if not lead and raid and UnitIsGroupAssistant then lead = UnitIsGroupAssistant("player") end
	return n, (lead and n < (raid and 40 or 5)) and true or false
end

local function Load()
	local now, n = ns.Now(), 0
	for i = #recent, 1, -1 do
		if now - recent[i] > Hop.RECENT then table.remove(recent, i) else n = n + 1 end
	end
	return n
end

-- The answer to the King's layer window: this session's, else the one kept with "Don't ask
-- me again" (auto, manual or no), else nil.
local function KingChoice() return kingMode or ns.db.hopKingChoice end

-- We are on the King's layer (Hop.King below).
local function OnKingLayer(strict)
	local k = Hop.King(strict)
	local mine = ns.Layers.Mine()
	if k and k.zoneUID and mine and mine.mapID == k.mapID and mine.zoneUID == k.zoneUID then return true end
	-- A private exact-nameplate observation may apply the player's existing King-layer choice
	-- locally without becoming Hop.King authority or a destination for anyone.
	local S = ns.HopSightings
	return (mine and type(S) == "table" and type(S.LocalKingLayer) == "function"
		and S.LocalKingLayer(mine.mapID, mine.zoneUID)) and true or false
end

-- The short names of the others in our group.
local function GroupNames()
	local out = {}
	if not (IsInGroup and IsInGroup()) then return out end
	local raid = IsInRaid and IsInRaid()
	local n = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
	for i = 1, n do
		local name = ns.UnitFullName((raid and "raid" or "party") .. i)
		if name then out[ns.ShortName(name)] = true end
	end
	out[ns.ShortName(ns.me or "")] = nil
	return out
end

-- Alone, or in a party of our hop guests only: the addon may invite on its own. Never into a
-- group of the player's friends.
local function OnlyGuests()
	if not (IsInGroup and IsInGroup()) then return true end
	if IsInRaid and IsInRaid() then return false end
	for short in pairs(GroupNames()) do
		if not guests[short] then return false end
	end
	return true
end

-- The group the "Always invite" click covers (groupAuto) is still the one we are in.
local function GroupAutoActive()
	if not groupAuto then return false end
	if not (IsInGroup and IsInGroup()) then groupAuto = nil return false end
	return true
end

-- Everyone who shares their layer helps once they said yes to it (1.1, Fern's #11: the
-- first-open page, or /oly layerhelp on; nil, never answered, is off). Not the King: he is the
-- one everybody wants, and his screen is on stream.
function Hop.Helps() return ns.db ~= nil and ns.db.layerHelp == true end
function Hop.CanHelp(mapID, zoneUID)
	if not Hop.Helps() or not ns.IsMember() then return false end
	-- An offer tells the asker we are on that layer: only for players who share theirs (0.9.2).
	if not ns.Layers.Sharing() then return false end
	if ns.King and ns.King.IsKing and ns.King.IsKing() then return false end
	local mine = ns.Layers.Mine()
	if not mine or mine.mapID ~= mapID or mine.zoneUID ~= zoneUID then return false end
	if ns.Layers.CurrentMap() ~= mapID then return false end
	if ns.Now() - (mine.t or 0) > Hop.LAYER_FRESH then return false end
	-- "Can't right now" on the King's layer window.
	if KingChoice() == "no" and OnKingLayer() then return false end
	if (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown()) then return false end
	if pending or (ask and ask.phase ~= "done") then return false end
	if ns.Now() < pausedUntil then return false end
	local _, room = Hop.GroupState()
	return room
end

-- Discovery knows it is specifically asking about the King before Hop.King has an L1 layer.
-- Preserve the explicit "Can't right now" choice in that interval too.
function Hop.CanHelpKing(mapID, zoneUID)
	if KingChoice() == "no" then return false end
	return Hop.CanHelp(mapID, zoneUID)
end

-- The chance to answer, so a crowded layer sends about OFFERS offers in all. Layers.lua sees
-- the officers and a 1 in 8 sample, so the crowd is a few times what it counts.
-- The census helps when the sample saw few (right after login, a quiet channel): the addon
-- users in the zone (each fresh, undisputed guild's members there, times its share of addon
-- users), shared by at least two layers. It may only lower the chance a little (at most
-- CENSUS_REACH times the sample's crowd, plus a few): too many offers cost a few whispers,
-- too few leave the asker with nobody, and one false report must not silence a zone.
Hop.CENSUS_REACH = 2
function Hop.Chance(mapID, zoneUID)
	local count, layers = 1, 0
	for _, layer in ipairs(ns.Layers.ForMap(mapID)) do
		layers = layers + 1
		if layer.zoneUID == zoneUID then count = layer.count end
	end
	local crowd = count * 4
	local users = 0
	local s = ns.Data and ns.Data.Summary and ns.Data.Summary()
	for _, e in ipairs(s and s.guilds or {}) do
		local g = e.g
		local here = e.fresh and not g.conflict and g.zones and g.zones["m" .. tostring(mapID)]
		if here and (g.online or 0) > 0 then users = users + here * math.min(1, (g.users or 0) / g.online) end
	end
	if users > 0 then
		local census = users / math.max(2, layers)
		crowd = math.max(crowd, math.min(census, crowd * Hop.CENSUS_REACH + 8))
	end
	return math.min(1, Hop.OFFERS / math.max(1, crowd))
end

-- 1.2.0: an Olympus member (our roster, or his guild's claim the channel takes, Channels.VerifiedLevel
-- 1+), never a stranger on an unsealed channel: only one gets an offer, a window or an invite.
local function Member(sender)
	local R = ns.Roster
	if R and R.RankOf and R.RankOf(sender) ~= nil then return true end
	local C, M = ns.Channels, ns.Moderation
	if type(C) ~= "table" or type(C.VerifiedLevel) ~= "function" then return false end
	local guild = M and M.GuildOf and M.GuildOf(sender)
	if type(guild) ~= "string" or guild == "" or not (ns.IsFederation and ns.IsFederation(guild)) then return false end
	local ok, level = pcall(C.VerifiedLevel, sender, guild)
	return ok and type(level) == "number" and level >= 1
end
Hop.Member = Member

function Hop.HandleAsk(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local id, mapID, zoneUID = text:match("^LQ~(%d+)~(%d+)~(%d+)$")
	id, mapID, zoneUID = tonumber(id), tonumber(mapID), tonumber(zoneUID)
	if not id then return end
	sender = ns.FullName(sender)
	-- 1.1: a name the moderators took off (net-off, Moderation.lua) gets no offer.
	if ns.Moderation.Hides and ns.Moderation.Hides(sender) then return end
	if not Member(sender) then stats.strangers = (stats.strangers or 0) + 1 return end
	local short = ns.ShortName(sender)
	local now = ns.Now()
	Hop.Hear(mapID, zoneUID, short, now)
	if now - (answeredAt[short] or -math.huge) < Hop.HELP_GAP then return end
	if now - lastOffer < Hop.OFFER_GAP then return end
	if not Hop.CanHelp(mapID, zoneUID) then return end
	-- Few announce their layer since sharing is a choice (0.9.1), so Chance can think a busy
	-- layer empty: with several askers at once, each ask takes a share of the helpers, not all.
	local chance = Hop.Chance(mapID, zoneUID)
	local asking = Hop.Crowd(mapID, zoneUID, now)
	if asking > 1 then chance = math.min(chance, math.max(1 / asking, 0.1)) end
	if Hop.random() > chance then return end
	answeredAt[short] = now
	local key = id .. short
	local offer = { t = now, mapID = mapID, zoneUID = zoneUID }
	offered[key] = offer
	lastOffer = now
	-- A random pause spreads the offers of a crowd over a couple of seconds.
	Hop.after(0.2 + Hop.random() * 2.3, "hop offer", function()
		-- We may have moved, entered combat or stopped sharing during that pause.
		if offered[key] ~= offer then return end
		if not Hop.CanHelp(mapID, zoneUID) then offered[key] = nil; return end
		local group, load = Hop.GroupState(), Load()
		ns.Comm.Whisper(sender, ("LO~%d~%d~%d"):format(id, group, load), nil, true)
		stats.offers = stats.offers + 1
	end)
end

-- release: the addon lets the guest go after GUEST_TIME (the helper chose that).
local function Invite(name, id, release) -- gp:hop-group
	local target = ns.TellName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end
	guests[ns.ShortName(name)] = { name = name, id = id or 0, t = ns.Now(), release = release and true or false }
	recent[#recent + 1] = ns.Now()
	stats.invites = stats.invites + 1
	ns.Print(L.HOP_INVITING:format(target))
	ns.Log("hop: invited %s", tostring(name))
end

local function SayNo(name, id)
	ns.Comm.Whisper(name, ("LN~%d"):format(id), nil, true)
	stats.noes = stats.noes + 1
end

-- A request answers one of our offers (anything else is ignored).
function Hop.HandleRequest(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local id = tonumber(text:match("^LR~(%d+)$"))
	sender = ns.FullName(sender)
	if ns.Moderation.Hides and ns.Moderation.Hides(sender) then return end -- (1.1: net-off)
	if not Member(sender) then stats.strangers = (stats.strangers or 0) + 1 return end
	local key = id and (id .. ns.ShortName(sender))
	local offer = key and offered[key]
	if not offer or ns.Now() - offer.t > 120 then return end
	offered[key] = nil
	stats.requests = stats.requests + 1
	if not Hop.CanHelp(offer.mapID, offer.zoneUID) then return SayNo(sender, id) end
	-- On its own ("Always invite", or "For Olympus!" on the King's layer): only while we are
	-- alone or with hop guests; in a group of our own we get the window, until "Always invite"
	-- is clicked in it (1.1.5, #50: then that group too, GroupAutoActive).
	-- "For Olympus!" invites on its own only for a King two reports confirm.
	local auto = ns.db.layerAutoInvite or (KingChoice() == "auto" and OnKingLayer(true))
	if auto and (OnlyGuests() or GroupAutoActive()) then return Invite(sender, id, true) end
	if auto then
		stats.autoBlocked = stats.autoBlocked + 1
		ns.Print(L.HOP_AUTO_PAUSED_GROUP)
	end
	pending = { from = sender, id = id, t = ns.Now(), mapID = offer.mapID, zoneUID = offer.zoneUID }
	-- In an instance or on Busy (1.1, ns.Alert): no sound and no window; they come once the player
	-- is out, while the asker still waits (Hop.WAIT), else the request only lapses.
	local ask = pending
	ns.Alert("hop", "soft", { what = L.HELD_HOP:format(ns.DisplayName(sender)), key = "hop:" .. id,
		open = function() return pending == ask and ns.Now() - ask.t <= Hop.WAIT end,
		show = function() if pending == ask then ns.ShowDialog("OLYMPUS_HOP_REQUEST", ns.DisplayName(sender), nil, ask) end end })
	Changed()
end

local function Answer(data, invite, always)
	if not data or pending ~= data then return end
	pending = nil
	-- A button can be clicked long after its offer. Recheck every eligibility gate.
	if invite and (ns.Now() - data.t > Hop.WAIT or not Hop.CanHelp(data.mapID, data.zoneUID)) then
		SayNo(data.from, data.id)
		return Changed()
	end
	if always then
		ns.db.layerAutoInvite = true
		-- The kept setting still asks first in a group of our own (OnlyGuests). Clicked in one, the
		-- player answered that question for it (#50: the window came back with every request).
		groupAuto = (IsInGroup and IsInGroup() and not OnlyGuests()) and true or nil
		ns.Print(groupAuto and L.HOP_AUTO_GROUP_ON or L.HOP_AUTO_ON)
	end
	if invite then
		declines = 0
		Invite(data.from, data.id, always)
	else
		SayNo(data.from, data.id)
		-- Not now (or no answer) twice in a row: a break from requests.
		declines = declines + 1
		if declines >= Hop.DECLINES then
			declines = 0
			pausedUntil = ns.Now() + Hop.PAUSE
		end
	end
	Changed()
end
Hop.Answer = Answer

StaticPopupDialogs["OLYMPUS_HOP_REQUEST"] = {
	text = L.HOP_REQUEST,
	button1 = L.HOP_INVITE,
	button2 = L.HOP_NOT_NOW,
	button3 = L.HOP_ALWAYS,
	OnAccept = function(self, data) ns.SafeCall("hop invite", Answer, data or self.data, true) end,
	OnAlt = function(self, data) ns.SafeCall("hop invite", Answer, data or self.data, true, true) end,
	-- Not now, Escape or the timeout: the asker moves on to someone else.
	OnCancel = function(self, data) ns.SafeCall("hop no", Answer, data or self.data, false) end,
	timeout = Hop.POPUP_TIME,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------

-- fromPopup: called from the leave window's own buttons (it closes itself).
local function Finish(message, fromPopup)
	if not ask then return end
	if not fromPopup and ask.leaveShown then ns.HideDialog("OLYMPUS_HOP_LEAVE", ask) end
	ask.phase = "done"
	ask.result = message
	ns.Comm.Cancel(ask)
	if message then ns.Print(message) end
	Changed()
end

-- Rechecked when sending a queued ask, choosing a helper and receiving an invite.
-- These checks do not change the player's group or their sharing preferences.
local function RequestProblem(allowGroup)
	if not ns.IsMember() then return L.MEMBERS_ONLY end
	local off = ns.Moderation.SelfOff and ns.Moderation.SelfOff()
	if off then return ns.Moderation.YouText(off) end
	if IsInInstance and IsInInstance() then return L.HOP_INSTANCE end
	if ask and ns.Layers.CurrentMap() ~= ask.mapID then return L.HOP_CONTEXT_CHANGED end
	if InCombatLockdown and InCombatLockdown() then return L.HOP_COMBAT end
	if not allowGroup and IsInGroup and IsInGroup() then return L.HOP_IN_GROUP end
end

function Hop.Cancel()
	if (not ask or ask.phase == "done") and ns.HopSightings and ns.HopSightings.CancelRequest
		and ns.HopSightings.CancelRequest(nil, true) then
		return ns.Print(L.HOP_CANCELLED)
	end
	if not ask or ask.phase == "done" then return ns.Print(L.HOP_IDLE) end
	Finish(L.HOP_CANCELLED)
end

-- Seconds before we may ask again: ASK_GAP after an ask, and after asks in a row that found
-- nobody or got no invite, longer each time (BACKOFF), so a player clicking a layer where
-- nobody can help doesn't ask the whole channel every 20 seconds.
function Hop.WaitLeft(now)
	now = now or ns.Now()
	if fails > 0 and now - failedAt > Hop.BACKOFF_RESET then fails = 0 end
	local left = Hop.ASK_GAP - (now - lastAsk)
	if fails > 0 then left = math.max(left, Hop.BACKOFF[math.min(fails, #Hop.BACKOFF)] - (now - failedAt)) end
	return math.max(0, left)
end

-- King-layer discovery is the first stage of the same hop. A discovery that found no safe
-- destination shares the ordinary hop backoff instead of broadcasting a new Q forever.
function Hop.DiscoveryFailed(message)
	local now = ns.Now()
	Hop.WaitLeft(now) -- forget an old failure before adding this one
	fails, failedAt = fails + 1, now
	local wait = math.ceil(Hop.WaitLeft(now))
	if message then ns.Print(message .. " " .. L.HOP_WAIT:format(wait)) end
	Changed()
	return wait
end

-- A discovery Q and its eventual LQ are one hop, so the public question consumes the same
-- channel cooldown as an ordinary ask. Only the causal transition from verified discovery (or
-- an authoritative L1 arriving during it) may enter the existing Hop machine immediately.
function Hop.DiscoverySent()
	lastAsk = ns.Now()
	Changed()
end

function Hop.AskDiscovered(mapID, zoneUID, label)
	local previous = discoveryHandoff
	discoveryHandoff = true
	local result = Hop.Ask(mapID, zoneUID, label)
	discoveryHandoff = previous
	return result
end

-- The ask ended with nobody (no offer at all) or no invite: the next one waits longer.
local function Failed(nobody)
	-- Nobody free because a crowd asks for that layer too: not ours to wait longer for.
	local crowded = ask and Hop.Crowd(ask.mapID, ask.zoneUID, ns.Now()) > Hop.BRAKE_ASKS
	if not crowded then fails, failedAt = fails + 1, ns.Now() end
	Finish((nobody and L.HOP_NOBODY_WAIT or L.HOP_GAVE_UP_WAIT):format(math.ceil(Hop.WaitLeft())))
end

-- An ask heard on the channel (HandleAsk), counted once per asker.
function Hop.Hear(mapID, zoneUID, short, now)
	local key = mapID .. ":" .. zoneUID
	local askers = heard[key] or {}
	heard[key] = askers
	local n = 0
	for _ in pairs(askers) do n = n + 1 end
	if n < Hop.BRAKE_ASKS * 4 or askers[short] then askers[short] = now end -- (enough to know it is a crowd)
end

-- How many asked for this layer in the last BRAKE_WINDOW.
function Hop.Crowd(mapID, zoneUID, now)
	local n = 0
	for _, t in pairs(heard[mapID .. ":" .. zoneUID] or {}) do
		if now - t <= Hop.BRAKE_WINDOW then n = n + 1 end
	end
	return n
end

-- Weighted draw: outside a group counts double, fewer recent invites counts more. Each asker
-- draws on its own, so a crowd of askers spreads over the helpers.
function Hop.Pick(offers, tried)
	local pool, total = {}, 0
	for name, o in pairs(offers) do
		if not tried[name] then
			local w = (o.group == 0 and 2 or 1) / (1 + o.load)
			if o.trusted then w = w * 3 end -- a helper the addon can vouch for comes first
			pool[#pool + 1] = { o = o, w = w }
			total = total + w
		end
	end
	if #pool == 0 then return nil end
	table.sort(pool, function(a, b) return a.o.name < b.o.name end)
	local r = Hop.random() * total
	for _, p in ipairs(pool) do
		r = r - p.w
		if r <= 0 then return p.o end
	end
	return pool[#pool].o
end

-- A queued ask belongs to one guild and one zone. A send-time guard is the final check:
-- callbacks, guild changes, moderation and group events may race the paced transport.
local function Current(a)
	return ask == a and ns.IsMember() and GetGuildInfo("player") == a.guild
		and ns.Layers.CurrentMap() == a.mapID
		and not (ns.Moderation.SelfOff and ns.Moderation.SelfOff())
end

local function CanSend(a)
	return Current(a) and RequestProblem() == nil
end

function Hop.Next()
	if not ask or (ask.phase ~= "asking" and ask.phase ~= "requested" and ask.phase ~= "accepted") then return end
	local problem = RequestProblem()
	if problem then return Finish(problem) end
	local a = ask
	local o = a.tries < Hop.TRIES and Hop.Pick(a.offers, a.tried)
	if not o then
		-- An early decline does not discard slower offers still inside the original window.
		if a.tries < Hop.TRIES and a.t and ns.Now() - a.t < Hop.NOBODY then
			a.phase = "asking"
			return Changed()
		end
		return Failed(a.tries == 0)
	end
	a.helper, a.phase, a.asked = o.name, "requesting", nil
	ns.Comm.Whisper(o.name, ("LR~%d"):format(a.id), nil, true, nil, function(sent)
		if ask ~= a or a.phase ~= "requesting" or a.helper ~= o.name then return end
		if not sent then
			Hop.OnRoster()
			if a.phase == "requesting" then Finish(L.HOP_GAVE_UP) end
			return
		end
		a.tried[o.name], a.tries = true, a.tries + 1
		a.phase, a.asked = "requested", ns.Now()
		ns.Print(L.HOP_REQUESTED:format(ns.DisplayName(o.name)))
		Changed()
	end, { owner = a, guard = function() return a.phase == "requesting" and a.helper == o.name and CanSend(a) end })
	Changed()
end

-- Ask for an invite to a layer (a zone and its zone UID), named for the messages.
function Hop.Ask(mapID, zoneUID, label)
	if not ns.IsMember() then return ns.Print(L.MEMBERS_ONLY) end
	-- 1.1: the moderators took this character off (net-off, Moderation.lua): nobody would answer.
	local off = ns.Moderation.SelfOff and ns.Moderation.SelfOff()
	if off then return ns.Print(ns.Moderation.YouText(off)) end
	if not mapID or not zoneUID then return ns.Print(L.HOP_NO_LAYER) end
	if IsInInstance and IsInInstance() then return ns.Print(L.HOP_INSTANCE) end
	if InCombatLockdown and InCombatLockdown() then return ns.Print(L.HOP_COMBAT) end
	-- A zone UID only means something in its zone: the player must be there already.
	if ns.Layers.CurrentMap() ~= mapID then return ns.Print(L.HOP_OTHER_MAP:format(Hop.ZoneName(mapID))) end
	local mine = ns.Layers.Mine()
	if mine and mine.mapID == mapID and mine.zoneUID == zoneUID and ns.Now() - (mine.t or 0) <= Hop.LAYER_FRESH then
		return ns.Print(L.HOP_ALREADY)
	end
	if IsInGroup and IsInGroup() then return ns.Print(L.HOP_IN_GROUP) end
	local now = ns.Now()
	if ask and ask.phase ~= "done" then return ns.Print(L.HOP_BUSY) end
	if ns.HopSightings and ns.HopSightings.Requesting and ns.HopSightings.Requesting() then
		return ns.Print(L.HOP_BUSY)
	end
	if not discoveryHandoff then
		local wait = Hop.WaitLeft(now)
		if wait > 0 then return ns.Print(L.HOP_WAIT:format(math.ceil(wait))) end
	end
	if not ns.Comm.ChannelReady() then return ns.Print(L.CHAN_NOT_READY) end
	ask = {
		id = Hop.random(1, 99999), mapID = mapID, zoneUID = zoneUID, label = label or L.LAYER_UNKNOWN,
		guild = GetGuildInfo("player"), phase = "queued", sendAt = now, offers = {}, count = 0, tried = {}, tries = 0,
		from = mine and { mapID = mine.mapID, zoneUID = mine.zoneUID },
	}
	stats.asks = stats.asks + 1
	-- A crowd is asking for this layer right now (the King just came online): its helpers are
	-- busy answering them, so ours goes out a few seconds later, at a random moment (Tick).
	if Hop.Crowd(mapID, zoneUID, now) > Hop.BRAKE_ASKS then
		ask.phase, ask.sendAt = "queued", now + Hop.BRAKE_WINDOW * (0.5 + Hop.random())
		ns.Print(L.HOP_CROWDED:format(math.ceil(ask.sendAt - now)))
		return Changed()
	end
	Hop.SendAsk()
end

function Hop.SendAsk()
	if not ask or ask.phase ~= "queued" then return end
	local a = ask
	local problem = RequestProblem()
	if problem then return Finish(problem) end
	if not ns.Comm.ChannelReady() then return Finish(L.CHAN_NOT_READY) end
	a.phase = "sending"
	-- Keeping zone and layer private (Layers.Sharing): the ask still names this zone and the
	-- layer wanted, and layers are only known from the members who share theirs. Once a session.
	if not ns.Layers.Sharing() and not privateHinted then
		privateHinted = true
		ns.Print(L.HOP_PRIVATE_HINT)
	end
	-- The response clock begins only after LQ reaches the game API, never while the shared
	-- transport is saturated by older urgent traffic.
	ns.Comm.Send("CHANNEL", ("LQ~%d~%d~%d"):format(a.id, a.mapID, a.zoneUID), nil, true, nil, function(sent)
		if ask ~= a or a.phase ~= "sending" then return end
		if not sent then return Finish(L.HOP_GAVE_UP) end
		lastAsk, a.t, a.phase = ns.Now(), ns.Now(), "asking"
		ns.Print(L.HOP_ASKING:format(a.label))
		ns.Log("hop: ask %d for map %d zoneUID %d", a.id, a.mapID, a.zoneUID)
		Changed()
	end, { owner = a, guard = function() return a.phase == "sending" and CanSend(a) end })
	Changed()
end

-- A helper the addon can vouch for: a guildmate (our roster), or a Lord or Captain. Until the
-- author explicitly activates signed enforcement, preserve the documented census rule exactly;
-- after it, only the manifest (plus the pinned Crown identities) counts. Their invite is accepted
-- for the player; anyone else's is left to the game's invite
-- window (one click), so nobody pulls a player into their group just by answering an ask read
-- on the channel. (A layer announcement is the sender's own word: it proves nothing here.)
function Hop.Trusted(name)
	name = ns.FullName(name)
	if ns.Roster.RankOf(name) then return true end
	if ns.Authority and ns.Authority.Enforced and ns.Authority.Enforced() then
		if ns.IsKingCharacter(name) or (ns.King and (ns.King.IsStewardName(name) or ns.King.IsHandName(name))) then return true end
		local guild, rank = ns.Authority.Role(name)
		if guild and rank <= ns.CAPTAIN_RANK and not (ns.Data.NetOff and ns.Data.NetOff(guild)) then return true end
		return false
	end
	local short = ns.ShortName(name)
	for guild, g in pairs(ns.rdb.guilds or {}) do
		-- (1.1: never a guild the moderators took off the network, Moderation.lua.)
		if type(g) == "table" and not (ns.Data.NetOff and ns.Data.NetOff(guild)) then
			local listed = g.leader and ns.ShortName(g.leader) == short
			for _, o in ipairs(not listed and g.officers or {}) do
				if o.name and ns.ShortName(o.name) == short then listed = true break end
			end
			if listed and ns.Data.KnownRank(name, guild) then return true end
		end
	end
	return false
end

function Hop.HandleOffer(dist, sender, text)
	if dist ~= "WHISPER" or not ask or not ask.t or ask.phase == "done" or ask.phase == "joined" then return end
	local id, group, load = text:match("^LO~(%d+)~(%d+)~(%d+)$")
	if tonumber(id) ~= ask.id then return end
	sender = ns.FullName(sender)
	if ns.Moderation.Hides and ns.Moderation.Hides(sender) then return end -- (1.1: net-off: no offer of theirs)
	if ask.offers[sender] or ask.count >= Hop.MAX_OFFERS then return end
	ask.offers[sender] = { name = sender, group = math.min(tonumber(group), 40), load = math.min(tonumber(load), 99), t = ns.Now(),
		trusted = Hop.Trusted(sender) }
	ask.count = ask.count + 1
	Changed()
end

function Hop.HandleNo(dist, sender, text)
	if dist ~= "WHISPER" or not ask or ask.phase ~= "requested" then return end
	if tonumber(text:match("^LN~(%d+)$")) ~= ask.id or ns.ShortName(ns.FullName(sender)) ~= ns.ShortName(ask.helper) then return end
	Hop.Next()
end

-- The invite we asked for: accept it for the player (anyone else's invite is left alone).
-- A helper asked before may still invite late (after we moved on): theirs counts too.
local function AskedHelper(name)
	if not name then return nil end
	local short = ns.ShortName(name)
	for helper in pairs(ask.tried) do
		if ns.ShortName(helper) == short then return helper end
	end
	return nil
end

function Hop.OnInvite(name) -- gp:party-invite
	if not ask or (ask.phase ~= "requesting" and ask.phase ~= "requested" and ask.phase ~= "accepted") then return end
	local helper = AskedHelper(name)
	if not helper then return end
	-- The game may already report a group before its roster event arrives.
	-- OnRoster checks the actual members before treating it as the hop's group.
	local problem = RequestProblem(true)
	if problem then return Finish(problem) end
	-- Not one the addon can vouch for (Hop.Trusted): the game's own window, the player's click.
	-- With the gamepad UI, always: the addon leaves the game's popups alone there (Dialog.lua),
	-- and the game's invite window is the one a controller answers.
	local o = ask.offers[helper]
	if not (o and o.trusted) or ns.GamepadUI() then
		-- The player decides: the wait starts over from this invite, and the group they may
		-- join counts as this helper's (OnRoster) even before the game names its members.
		ask.helper, ask.invitedBy, ask.asked = helper, helper, ns.Now()
		if ask.phase ~= "requested" then ask.phase = "requested" end
		ns.Comm.Cancel(ask)
		if ask.hinted ~= helper then
			ask.hinted = helper
			ns.PlayAlert("soft", "hop")
			ns.Print(L.HOP_ACCEPT_HINT:format(ns.DisplayName(helper)))
		end
		Changed()
		return
	end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
	if dialog then dialog.inviteAccepted = 1 end
	if AcceptGroup then AcceptGroup() end
	if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
	ask.helper, ask.phase, ask.accepted = helper, "accepted", ns.Now()
	ns.Comm.Cancel(ask)
	ns.Log("hop: accepted the invite from %s", tostring(name))
	Changed()
end

local function LeaveGroup() -- gp:hop-group
	if C_PartyInfo and C_PartyInfo.LeaveParty then C_PartyInfo.LeaveParty() elseif LeaveParty then LeaveParty() end
end

-- Out of the helper's group, the hop done (a layer stays after the group is left).
local function Leave(message)
	Hop.OnRoster()
	if not ask or ask.phase ~= "joined" then return end
	LeaveGroup()
	Finish(message)
end

-- No move seen after a while (no NPC around): the player decides.
local function OfferLeave()
	if not ask or ask.leaveShown then return end
	ask.leaveShown = true
	ns.PlayAlert("soft", "hop")
	ns.ShowDialog("OLYMPUS_HOP_LEAVE", L.HOP_MAYBE_MOVED, nil, ask)
end

StaticPopupDialogs["OLYMPUS_HOP_LEAVE"] = {
	text = "%s",
	button1 = L.HOP_LEAVE,
	button2 = L.HOP_STAY,
	-- Only for the ask it was shown for (data): an old window never ends a new ask.
	OnAccept = function(self, data)
		ns.SafeCall("hop leave", function()
			if not ask or ask.phase ~= "joined" or (data or (self and self.data)) ~= ask then return end
			Hop.OnRoster()
			if ask.phase ~= "joined" then return end
			LeaveGroup()
			Finish(L.HOP_DONE, true)
		end)
	end,
	OnCancel = function(self, data)
		ns.SafeCall("hop stay", function()
			if (data or (self and self.data)) == ask then Finish(nil, true) end
		end)
	end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Hop.OnRoster()
	if groupAuto and not (IsInGroup and IsInGroup()) then groupAuto = nil end -- (the group "Always invite" covered ended)
	if not ask or ask.phase == "done" then return end
	local grouped = IsInGroup and IsInGroup()
	if ask.phase == "joined" then
		if not grouped then return Finish() end
		local names = GroupNames()
		if names[ns.ShortName(ask.helper)] then return end
		-- A roster replacement after joining is no longer the helper's group.
		for name in pairs(names) do
			if name ~= "" and name ~= (UNKNOWNOBJECT or "Unknown") then return Finish() end
		end
		return
	end
	if not grouped then return end
	-- In a group: a helper we asked is in it (or we accepted their invite), else it is some
	-- other group (a friend's) and the hop is off: the addon never leaves that one.
	local names, helper, named = GroupNames(), nil, false
	for name in pairs(ask.tried) do
		if names[ns.ShortName(name)] then helper = name end
	end
	for short in pairs(names) do
		if short ~= "" and short ~= (UNKNOWNOBJECT or "Unknown") then named = true end
	end
	-- Nobody in it named yet (the game names the members a moment later): the helper's
	-- invite we or the player accepted made this group. Anyone else named: not the hop's.
	if not helper and not named and (ask.phase == "accepted" or ask.invitedBy) then helper = ask.invitedBy or ask.helper end
	if not helper then return Finish() end
	ask.helper, ask.phase, ask.joined = helper, "joined", ns.Now()
	ns.Comm.Cancel(ask)
	fails = 0 -- someone could help: the usual wait again
	stats.joins = stats.joins + 1
	ns.Print(L.HOP_JOINED:format(ns.DisplayName(helper)))
	Changed()
	-- NPC/nameplate events can arrive before GROUP_ROSTER_UPDATE.
	Hop.OnLayer()
end

-- The layer a hop is taking us to, while we wait in the group: Layers takes it at once.
function Hop.ExpectedLayer()
	if ask and ask.phase == "joined" then return ask.mapID, ask.zoneUID end
end

-- Only the requested zone/layer is success. A third layer may be a border NPC or
-- an intermediate move; leaving there can strand the player on the wrong layer.
function Hop.OnLayer()
	if not ask or ask.phase ~= "joined" then return end
	Hop.OnRoster()
	if ask.phase ~= "joined" then return end
	if (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) then return end
	local mine = ns.Layers.Mine()
	if not mine or ns.Layers.CurrentMap() ~= ask.mapID or (mine.t or 0) < ask.t then return end
	local target = mine.mapID == ask.mapID and mine.zoneUID == ask.zoneUID
	if target and mine.confirmedAt and mine.confirmedAt >= ask.t
		and ns.Now() - mine.confirmedAt <= ns.Layers.EVIDENCE_WINDOW then
		stats.moves = stats.moves + 1
		Leave(L.HOP_MOVED_LEFT)
	end
end

-- The helper's addon lets us go (their guests stay GUEST_TIME at most).
function Hop.HandleRelease(dist, sender, text)
	if dist ~= "WHISPER" or not ask or ask.phase ~= "joined" or not ask.helper then return end
	if tonumber(text:match("^LX~(%d+)$")) ~= ask.id then return end
	if ns.ShortName(ns.FullName(sender)) ~= ns.ShortName(ask.helper) then return end
	Leave(L.HOP_RELEASED:format(ns.DisplayName(ask.helper)))
end

-- Helping on our own: the guests whose time is up are asked to leave (their addon does it).
local function ReleaseGuests(now)
	for short, g in pairs(guests) do
		if g.release and not g.released and now - g.t >= Hop.GUEST_TIME then
			g.released = true
			-- Only those still with us (a whisper to someone gone prints an error).
			if GroupNames()[short] then
				stats.releases = stats.releases + 1
				ns.Comm.Whisper(g.name, ("LX~%d"):format(g.id))
			end
		end
		if now - g.t >= Hop.GUEST_TIME * 3 then guests[short] = nil end
	end
end

function Hop.Tick()
	local now = ns.Now()
	for key, offer in pairs(offered) do if now - offer.t > 120 then offered[key] = nil end end
	for name, at in pairs(answeredAt) do if now - at > Hop.HELP_GAP then answeredAt[name] = nil end end
	if pending and now - pending.t > Hop.WAIT + 5 then pending = nil end -- the popup is long gone
	ReleaseGuests(now)
	if now - lastPromptCheck >= Hop.PROMPT_EVERY then
		lastPromptCheck = now
		Hop.CheckKingPrompt()
	end
	for key, askers in pairs(heard) do
		for short, t in pairs(askers) do
			if now - t > Hop.BRAKE_WINDOW then askers[short] = nil end
		end
		if not next(askers) then heard[key] = nil end
	end
	if not ask or ask.phase == "done" then return end
	if ask.phase ~= "joined" then
		if not Current(ask) or (IsInInstance and IsInInstance()) then return Finish(L.HOP_CONTEXT_CHANGED) end
		if IsInGroup and IsInGroup() then Hop.OnRoster() end
		if ask.phase == "done" then return end
	end
	if ask.phase == "queued" then
		if now >= ask.sendAt then Hop.SendAsk() end
	elseif ask.phase == "asking" then
		if now - ask.t >= Hop.WINDOW and ask.count > 0 then
			Hop.Next()
		elseif now - ask.t >= Hop.NOBODY then
			Failed(ask.tries == 0)
		end
	elseif ask.phase == "requested" then
		if now - ask.asked >= Hop.WAIT then Hop.Next() end
	elseif ask.phase == "accepted" then
		if now - ask.accepted >= Hop.ACCEPT_WAIT then Hop.Next() end
	elseif ask.phase == "joined" then
		Hop.OnLayer()
		if ask.phase == "joined" and now - ask.joined >= Hop.JOIN_WAIT then OfferLeave() end
	end
end

---------------------------------------------------------------------------
-- The King's layer
---------------------------------------------------------------------------

function Hop.ZoneName(mapID)
	return mapID and ns.Zones and ns.Zones.NameForKey and ns.Zones.NameForKey("m" .. mapID) or "?"
end

-- The King's own word on where he plays (1.0.0, Konig's review of 1.0.0): the name the server
-- stamped on the last message his client sent us (his crown, his layer, his commands: King.lua
-- and Layers.lua call Hop.HeardKing for the character pinned by name, ns.IsKingCharacter).
-- A census report is anyone's word: one forged report from another realm of our group placed him
-- there ("he plays on another realm"), and his layer could not be asked for. This session's alone.
local kingFrom
function Hop.HeardKing(sender)
	if type(sender) == "string" and ns.IsKingCharacter(sender) then kingFrom = ns.FullName(sender) end
end

-- The King when he is online (leader of the guild named exactly "Olympus"), and his layer
-- when his addon announced it: { name, mapID, zoneUID }. The name is the one the army calls
-- him (ns.KING_NAME); his character's is only used to find his layer.
-- Only the leader the reports name, none of them disagreeing (Data.KnownRank, soft: the line
-- only shows; the Throne's commands ask for more): one forged report can't crown anyone
-- while the guild's own reporter says otherwise. strict: two reports (inviting on its own,
-- "For Olympus!", waits for that).
-- His realm and his layer (1.0.0, Konig's review): where the census names the character pinned
-- by name, from his own messages alone (Hop.HeardKing), none heard yet: neither is known. Where
-- none is pinned (another realm group), the census's word is all there is. A direct nameplate
-- sighting is never installed here as authority: HopSightings privately asks, requires two
-- independent answers and only then starts this module's ordinary Hop.Ask state machine.
function Hop.King(strict)
	local now = ns.Now()
	local pin = ns.KingCharacter()
	for name, g in pairs(ns.rdb.guilds or {}) do
		if ns.IsKingGuild(name) and type(g) == "table" and g.leader
			and now - (g.t or 0) <= ns.Data.FRESH and g.leaderOnline then
			local full = ns.FullName(g.leader, g.realm or ns.realm)
			if ns.Data.KnownRank(full, name, not strict) == 0 then
				local at = full
				if pin ~= nil and ns.ShortName(g.leader) == pin then at = kingFrom end
				local where = at and ns.Layers.Of(at, true)
				return { name = ns.KingName(g.leader), mapID = where and where.mapID, zoneUID = where and where.zoneUID,
					t = where and where.t, realm = at and ns.RealmOf(at) }
			end
		end
	end
	return nil
end

-- <Olympus> reports its leader online, but the census does not confirm him yet (a few
-- minutes after login, Data.KnownRank): not "offline".
local function KingUnconfirmed()
	for name, g in pairs(ns.rdb.guilds or {}) do
		if ns.IsKingGuild(name) and type(g) == "table" and g.leader and g.leaderOnline
			and ns.Now() - (g.t or 0) <= ns.Data.FRESH then
			return true
		end
	end
	return false
end

-- The King plays on another realm than ours (his own messages say so, Hop.King; where no King
-- is pinned by name, the census). A layer is a copy of a zone inside one realm: nobody here can
-- join his, even when his crown and his layer reach us (a channel shared across realms,
-- Comm.ElectsAcrossRealms). Checked before his layer.
function Hop.KingOtherRealm(k)
	return k ~= nil and k.realm ~= nil and ns.realm ~= nil and ns.realm ~= "?" and k.realm ~= ns.realm
end

-- Why nobody can ask for the King's layer now (1.0.0), instead of "try again in a minute"
-- whatever the reason: he plays on another realm (Hop.KingOtherRealm), his crown is not on the
-- map (off, or he is in a dungeon: his layer is only announced while it shows, Layers.Sharing),
-- or it is visible and an explicit click can start private, two-observer discovery.
function Hop.KingUnknownText(k)
	if Hop.KingOtherRealm(k) then return L.HOP_KING_OTHER_REALM:format(k.name, k.realm) end
	if not (ns.King and ns.King.Location and ns.King.Location()) then return L.HOP_KING_HIDDEN:format(k.name) end
	return L.HOP_KING_UNKNOWN:format(k.name)
end

function Hop.AskKing()
	local WC = ns.WatchChat
	local barred = WC and not WC.missing and WC.Barred and WC.Barred("locations")
	if barred then return WC.TellBarred(barred) end -- (1.1.6: a sanctioned player asks for no King's layer)
	local k = Hop.King()
	if not k then return ns.Print(KingUnconfirmed() and L.HOP_KING_CHECKING:format(ns.KingName()) or L.HOP_KING_OFFLINE) end
	if Hop.KingOtherRealm(k) then return ns.Print(Hop.KingUnknownText(k)) end
	-- An exact local nameplate observation can prove only that *this client* is already there.
	-- Use it to avoid broadcasting a needless discovery Q, without installing it in Hop.King.
	if OnKingLayer(true) then return ns.Print(L.HOP_ALREADY) end
	if not k.zoneUID then
		local at = ns.King and ns.King.Location and ns.King.Location()
		if not at then return ns.Print(Hop.KingUnknownText(k)) end
		if ns.Layers.CurrentMap() ~= at.mapID then return ns.Print(L.HOP_KING_ELSEWHERE:format(k.name, Hop.ZoneName(at.mapID))) end
		if ask and ask.phase ~= "done" then return ns.Print(L.HOP_BUSY) end
		if ns.HopSightings and ns.HopSightings.Request then
			return ns.HopSightings.Request({ character = at.from, mapID = at.mapID, label = k.name }, L.LAYER_OF:format(k.name))
		end
		return ns.Print(Hop.KingUnknownText(k))
	end
	if ns.Layers.CurrentMap() ~= k.mapID then return ns.Print(L.HOP_KING_ELSEWHERE:format(k.name, Hop.ZoneName(k.mapID))) end
	-- An authoritative L1 may arrive while private discovery is collecting answers. End that
	-- discovery before entering the ordinary LQ/LO/LR machine; never run the two flows together.
	local discovering = ns.HopSightings and ns.HopSightings.Requesting and ns.HopSightings.Requesting()
	if ns.HopSightings and ns.HopSightings.CancelRequest then ns.HopSightings.CancelRequest(nil, true) end
	if discovering then return Hop.AskDiscovered(k.mapID, k.zoneUID, L.LAYER_OF:format(k.name)) end
	Hop.Ask(k.mapID, k.zoneUID, L.LAYER_OF:format(k.name))
end

-- The lines on top of the Census and the Realm while the King is online (Views.lua): the
-- button, and under it where he is when that is not our zone.
function Hop.KingLines()
	-- (1.1.6: a sanctioned player, WatchChat.Barred, is not told when the King is online.)
	local WC = ns.WatchChat
	if WC and not WC.missing and WC.Barred and WC.Barred("locations") then return {} end
	local k = Hop.King()
	if not k or (ns.King and ns.King.IsKing and ns.King.IsKing()) then return {} end
	-- The size of a title, with the crown the map shows him with.
	local crown = "|T" .. ns.CROWN_ICON .. ":0|t "
	-- (On another realm his layer is not ours to join or be on, whatever reaches us of it.)
	local away = Hop.KingOtherRealm(k)
	if not away and OnKingLayer(true) then
		return Hop.WithAutoLine({ { text = crown .. "|cff40ff40" .. L.HOP_KING_HERE:format(k.name) .. "|r", color = "GameFontNormal", gapAfter = true } }, k)
	end
	local elsewhere = not away and k.zoneUID and ns.Layers.CurrentMap() ~= k.mapID
	local busy = (ask and ask.phase ~= "done")
		or (ns.HopSightings and ns.HopSightings.Requesting and ns.HopSightings.Requesting())
	local line = {
		text = crown .. "|cffffd200" .. (busy and L.HOP_KING_BUSY or L.HOP_KING_LINE):format(k.name) .. "|r",
		color = "GameFontNormal",
		gapAfter = not elsewhere,
		onClick = function() Hop.AskKing() end,
		tooltip = function(tt)
			tt:AddLine(L.HOP_KING_LINE:format(k.name), 1, 0.82, 0)
			if away or not k.zoneUID then
				tt:AddLine(Hop.KingUnknownText(k), 1, 1, 1, true)
			elseif elsewhere then
				tt:AddLine(L.HOP_KING_ELSEWHERE:format(k.name, Hop.ZoneName(k.mapID)), 1, 0.6, 0.2, true)
			else
				tt:AddLine(L.HOP_KING_TIP:format(k.name), 1, 1, 1, true)
			end
			local at = ns.King and ns.King.Location and ns.King.Location()
			if at then tt:AddLine(L.HOP_KING_WHERE:format(Hop.ZoneName(at.mapID)), 0.25, 1, 0.25, true) end
		end,
	}
	if not elsewhere then return Hop.WithAutoLine({ line }, k) end
	return Hop.WithAutoLine({ line, { text = "|cffff9933" .. L.HOP_KING_GO:format(Hop.ZoneName(k.mapID)) .. "|r", indent = 1, gapAfter = true } }, k)
end

-- While the addon invites on its own ("For Olympus!" or "Always invite"), a line under the
-- King's says so, and one click stops it.
function Hop.WithAutoLine(lines, k)
	if not (ns.db.layerAutoInvite or KingChoice() == "auto") then return lines end
	lines[#lines].gapAfter = nil
	lines[#lines + 1] = {
		text = "|cff40ff40" .. L.HOP_AUTO_LINE:format(k.name) .. "|r", indent = 1, gapAfter = true,
		onClick = function() Hop.StopAuto() end,
		tooltip = function(tt)
			tt:AddLine(L.HOP_AUTO_LINE:format(k.name), 0.25, 1, 0.25)
			tt:AddLine(L.HOP_AUTO_TIP, 1, 1, 1, true)
		end,
	}
	return lines
end

-- No more invites on its own: every request shows the window again.
function Hop.StopAuto()
	ns.db.layerAutoInvite = false
	groupAuto = nil
	if KingChoice() == "auto" then
		kingMode = "manual"
		if ns.db.hopKingChoice == "auto" then ns.db.hopKingChoice = "manual" end
	end
	ns.Print(L.HOP_AUTO_OFF)
	Changed()
end
function Hop.KingLine() return Hop.KingLines()[1] end

-- Alone on the King's layer: may the addon invite, and later let go, the players who want to
-- come? Asked once a login (never again with the box ticked). Not asked of the King, nor of
-- players who turned helping off or already invite on their own.
function Hop.CheckKingPrompt()
	if promptShown or KingChoice() or not Hop.Helps() or ns.db.layerAutoInvite then return end
	if not ns.IsMember() or (ns.King and ns.King.IsKing and ns.King.IsKing()) then return end
	if (IsInGroup and IsInGroup()) or (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown()) then return end
	local mine = ns.Layers.Mine()
	if not mine or ns.Now() - (mine.t or 0) > Hop.LAYER_FRESH or not OnKingLayer() then return end
	promptShown = true
	ns.PlayAlert("soft", "hop")
	Hop.ShowKingPrompt()
end

function Hop.ChooseKing(choice)
	kingMode = choice
	local f = Hop.prompt
	if f then
		if f.check and f.check:GetChecked() then ns.db.hopKingChoice = choice end
		f.answered = true
		f:Hide()
	end
	if choice == "auto" then ns.Print(L.HOP_KING_AUTO:format((Hop.King() or {}).name or ns.KingName()))
	elseif choice == "no" then ns.Print(L.HOP_KING_NO)
	else ns.Print(L.HOP_KING_MANUAL) end
	Changed()
	ns.Fire("HOP_HELP_CHANGED", choice)
end

-- look: "dim" (grey, the way out), "main" (lit, white text: the one we hope for) or nil.
-- All three the same size.
local function PromptButton(f, label, choice, look)
	local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetHeight(22)
	if look == "dim" then
		b:SetNormalFontObject("GameFontDisable")
		b:SetHighlightFontObject("GameFontHighlight")
		b:SetAlpha(0.8)
	elseif look == "main" then
		b:SetNormalFontObject("GameFontHighlight")
		b:LockHighlight()
	end
	b:SetText(label)
	local fs = b:GetFontString()
	local textW = fs and (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()) or 100
	b:SetWidth(math.max(120, math.ceil(textW) + 28))
	b:SetScript("OnClick", function() ns.SafeCall("hop king choice", Hop.ChooseKing, choice) end)
	return b
end

-- A window like the game's own dialogs, with three answers and "Don't ask me again". 1.1.5: in the
-- Olympus window's metal without its portrait (ns.Window, Dialog.lua), "Olympus" in its title bar,
-- no X (its answers close it; Escape too, with mouse and keyboard).
Hop.PROMPT_TOP = -34 -- its text, under the title bar
local function MakePrompt()
	local f = ns.Window("OlympusKingLayerPrompt", UIParent, { title = L.TITLE, close = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80) -- clear of the game's popups at the top
	f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.text:SetPoint("TOP", 0, Hop.PROMPT_TOP)
	f.text:SetJustifyH("CENTER")
	-- Left to right: the way out (grey), inviting by hand, and "For Olympus!" (lit, white).
	f.buttons = {
		PromptButton(f, L.HOP_KING_PROMPT_NO, "no", "dim"),
		PromptButton(f, L.HOP_KING_PROMPT_MANUAL, "manual"),
		PromptButton(f, L.HOP_KING_PROMPT_YES, "auto", "main"),
	}
	f.check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.check:SetSize(24, 24)
	f.checkLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.checkLabel:SetPoint("LEFT", f.check, "RIGHT", 2, 1)
	f.checkLabel:SetText(L.HOP_KING_PROMPT_NEVER)
	-- Escape (or anything else closing it unanswered): the usual window per request, this login.
	f:SetScript("OnHide", function(self)
		if not self.answered then kingMode = kingMode or "manual" end
	end)
	return f
end

function Hop.ShowKingPrompt()
	Hop.prompt = Hop.prompt or MakePrompt()
	local f = Hop.prompt
	local total = 0
	for _, b in ipairs(f.buttons) do total = total + b:GetWidth() end
	total = total + 8 * (#f.buttons - 1)
	local width = math.max(400, total + 40)
	f:SetWidth(width)
	f.text:SetWidth(width - 48)
	local kname = (Hop.King() or {}).name or ns.KingName()
	f.text:SetText(L.HOP_KING_PROMPT:format(kname, kname))
	local x = (width - total) / 2
	for i, b in ipairs(f.buttons) do
		b:ClearAllPoints()
		if i == 1 then b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 18) else b:SetPoint("LEFT", f.buttons[i - 1], "RIGHT", 8, 0) end
	end
	f.check:ClearAllPoints()
	f.check:SetPoint("BOTTOMLEFT", f.buttons[1], "TOPLEFT", -4, 6)
	f.check:SetChecked(false)
	local textH = f.text.GetStringHeight and f.text:GetStringHeight() or f.text:GetHeight()
	f:SetHeight(-Hop.PROMPT_TOP + math.max(40, textH or 0) + 12 + 24 + 6 + 22 + 18)
	f.answered = false
	f:Show()
end

-- What the Realm tab's layer rows show about an ask in progress for that layer.
function Hop.State() return ask end
function Hop.Stats() return stats end

function Hop.ProgressText()
	if not ask or ask.phase == "done" then
		local S = ns.HopSightings
		if type(S) == "table" and type(S.Progress) == "function" then
			local phase, left = S.Progress()
			if phase == "sending" then return L.HOP_SENDING_REQUEST end
			if phase then return L.HOP_SIGHTING_PROGRESS:format(math.ceil(left or 0)) end
		end
		local text = ask and ask.result or L.HOP_IDLE
		local wait = math.ceil(Hop.WaitLeft())
		return wait > 0 and (text .. " " .. L.HOP_WAIT:format(wait)) or text
	end
	if ask.phase == "queued" then return L.HOP_CROWDED:format(math.max(0, math.ceil(ask.sendAt - ns.Now()))) end
	if ask.phase == "sending" then return L.HOP_SENDING_REQUEST end
	if ask.phase == "asking" then return L.HOP_PROGRESS_OFFERS:format(ask.count, math.max(0, Hop.NOBODY - (ns.Now() - ask.t))) end
	if ask.phase == "requesting" then return L.HOP_SENDING_HELPER:format(ns.DisplayName(ask.helper)) end
	if ask.phase == "requested" then return L.HOP_PROGRESS_INVITE:format(ns.DisplayName(ask.helper), ask.tries, Hop.TRIES) end
	if ask.phase == "accepted" then return L.HOP_PROGRESS_GROUP:format(ns.DisplayName(ask.helper)) end
	return L.HOP_PROGRESS_LAYER:format(ask.zoneUID, Hop.ZoneName(ask.mapID))
end

-- Local controls only. Discovery and invitations use the existing LQ/LO/LR messages,
-- so a helper running the unmodified release can still answer.
function Hop.Command(rest)
	rest = (rest or ""):match("^%s*(.-)%s*$"):lower()
	if rest == "" or rest == "king" then return Hop.AskKing() end
	if rest == "cancel" then return Hop.Cancel() end
	if rest == "status" then
		if ns.LOCAL_BUILD then ns.Print("Olympus " .. ns.VERSION .. " / " .. ns.LOCAL_BUILD) end
		ns.Print(Hop.ProgressText())
		local mine = ns.Layers.Mine()
		if mine and ns.Layers.CurrentMap() == mine.mapID then
			ns.Print(L.HOP_LOCAL_READING:format(mine.zoneUID, Hop.ZoneName(mine.mapID), math.max(0, ns.Now() - (mine.t or 0))))
		else ns.Print(L.HOP_NEED_NPC) end
		return ns.Print(ns.Comm.ChannelReady() and L.HOP_NETWORK_READY or L.CHAN_NOT_READY)
	end
	if rest ~= "list" and rest ~= "any" and not rest:match("^#?%d+$") then return ns.Print(L.HELP_HOP) end
	local mapID = ns.Layers.CurrentMap()
	local layers = mapID and ns.Layers.ForMap(mapID) or {}
	if rest == "list" then
		ns.Print(L.LAYERS_IN:format(Hop.ZoneName(mapID)))
		for _, layer in ipairs(layers) do
			ns.Print(L.HOP_LIST_ROW:format(layer.zoneUID, ns.Layers.Name(layer), layer.count,
				math.max(0, ns.Now() - (layer.lastSeen or 0)), layer.mine and L.LAYER_YOU or ""))
		end
		return ns.Print(#layers > 0 and L.HOP_LIST_HINT or L.HOP_NO_ALTERNATIVE)
	end
	local uid = tonumber(rest:match("^#?(%d+)$"))
	local chosen
	if rest == "any" then
		local mine = ns.Layers.Mine()
		if not mine or mine.mapID ~= mapID or ns.Now() - (mine.t or 0) > Hop.LAYER_FRESH then return ns.Print(L.HOP_NEED_NPC) end
		for _, layer in ipairs(layers) do
			if layer.zoneUID ~= mine.zoneUID and ns.Now() - (layer.lastSeen or 0) <= Hop.LAYER_FRESH
				and (not chosen or layer.lastSeen > chosen.lastSeen
					or (layer.lastSeen == chosen.lastSeen and layer.zoneUID < chosen.zoneUID)) then chosen = layer end
		end
	else
		for _, layer in ipairs(layers) do if layer.zoneUID == uid then chosen = layer; break end end
	end
	if not chosen then return ns.Print(L.HOP_NO_ALTERNATIVE) end
	Hop.Ask(mapID, chosen.zoneUID, ns.Layers.Name(chosen))
end

function Hop.StatusLine()
	local s = stats
	local n = 0
	for _ in pairs(guests) do n = n + 1 end
	return ("help=%s auto=%s group-auto=%s king=%s  |  asks=%d offers=%d requests=%d invites=%d noes=%d joins=%d moves=%d releases=%d guests=%d auto-paused=%d  |  now=%s | %s"):format(
		tostring(Hop.Helps()), tostring(ns.db.layerAutoInvite == true), tostring(GroupAutoActive()), tostring(KingChoice() or "-"),
		s.asks, s.offers, s.requests, s.invites, s.noes, s.joins, s.moves, s.releases, n, s.autoBlocked,
		ask and ask.phase or "-", Hop.ProgressText())
end

-- What this client knows of the King, for /oly status and /oly bug (1.0.0: "the King's layer
-- doesn't work" said nothing of why). Elsewhere: confirmed (two reports name him online),
-- online (one report), checking (reported online, not confirmed yet) or offline; the realm his
-- own messages place him on (Hop.King); his layer and when it was heard; his crown and when it was heard. On
-- his own client: his crown shown or hidden, and when his layer last went out.
function Hop.KingStatusLine()
	local K = ns.King
	if K and K.IsKing and K.IsKing() then
		local sent = ns.Layers.SentAt and ns.Layers.SentAt()
		return ("me  |  crown %s  |  layer %s"):format(K.SharingLocation() and "shown" or "hidden",
			sent and ("sent " .. ns.Ago(sent)) or "not sent")
	end
	local k, state = Hop.King(true), "confirmed"
	if not k then k, state = Hop.King(), "online (one report)" end
	if not k then return KingUnconfirmed() and "checking (reported online, not confirmed yet)" or "offline" end
	local realm = k.realm and (k.realm .. (Hop.KingOtherRealm(k) and " (another realm)" or " (ours)")) or "?"
	local layer = k.zoneUID and ("map %d zone %d, heard %s"):format(k.mapID, k.zoneUID, ns.Ago(k.t)) or "not known"
	local at = K and K.Location and K.Location()
	local crown = at and ("map %d, heard %s"):format(at.mapID, ns.Ago(at.t)) or "not heard"
	return ("%s  |  realm %s  |  layer %s  |  crown %s"):format(state, realm, layer, crown)
end

-- On again also forgets the King's layer answer: the window may ask again. Off also ends the
-- group "Always invite" covered (#50).
function Hop.SetHelp(on)
	ns.db.layerHelp = on
	if not on then groupAuto = nil end
	if on then
		ns.db.hopKingChoice, kingMode, promptShown = nil, nil, false
	end
	ns.Print(on and L.HOP_HELP_ON or L.HOP_HELP_OFF)
	ns.Fire("HOP_HELP_CHANGED", on and true or false)
end

-- Off also ends "For Olympus!" (the King's layer window's answer).
function Hop.SetAuto(on)
	if not on then return Hop.StopAuto() end
	ns.db.layerAutoInvite = true
	ns.Print(L.HOP_AUTO_ON)
end

-- Tests start from a clean state.
function Hop.Reset()
	local previous = ask
	ask, pending, lastAsk, discoveryHandoff = nil, nil, -math.huge, false
	if previous then ns.Comm.Cancel(previous) end
	if ns.HopSightings and ns.HopSightings.CancelRequest then ns.HopSightings.CancelRequest(nil, true) end
	fails, failedAt = 0, -math.huge
	wipe(heard)
	kingMode, groupAuto, promptShown, lastPromptCheck, privateHinted = nil, nil, false, -math.huge, false
	lastOffer, declines, pausedUntil = -math.huge, 0, -math.huge
	wipe(offered); wipe(answeredAt); wipe(recent); wipe(guests)
	for k in pairs(stats) do stats[k] = 0 end
	kingFrom = nil
end

ns.Comm.Handle("LQ", function(...) Hop.HandleAsk(...) end)
ns.Comm.Handle("LO", function(...) Hop.HandleOffer(...) end)
ns.Comm.Handle("LR", function(...) Hop.HandleRequest(...) end)
ns.Comm.Handle("LN", function(...) Hop.HandleNo(...) end)
ns.Comm.Handle("LX", function(...) Hop.HandleRelease(...) end)

ns.On("LAYERS_CHANGED", function() ns.SafeCall("hop layer", Hop.OnLayer) end)

ns.On("LOGIN", function()
	ns.RegisterEvent("PARTY_INVITE_REQUEST", function(name) Hop.OnInvite(ns.Normal(name)) end)
	ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() Hop.OnRoster() end)
	ns.Every(1, "hop", Hop.Tick)
end)
