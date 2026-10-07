local ADDON, ns = ...
local L = ns.L

-- The normal Olympus window's player page. The Blood Arena companion owns a separate profile
-- surface. This module renders a bounded snapshot of
-- facts already held by the core addon, with source/freshness/visibility metadata kept beside
-- every field instead of guessing at facts the client does not have.
local Profile = {}
ns.PlayerProfile = Profile

Profile.MAX_ROWS = 24
Profile.MAX_FIELDS = 32
Profile.MAX_TEXT_BYTES = 512

local SOURCES = {
	report = true, roster = true, who = true, profile = true,
	inspection = true, addon = true, signed = true, derived = true,
}

local function CleanSource(value)
	if value == "local" then return "local" end
	return type(value) == "string" and SOURCES[value] and value or "unknown"
end

local function SourceState(source, explicit)
	if explicit == "local" or explicit == "shared" or explicit == "derived" or explicit == "hidden" or explicit == "unknown" then
		return explicit
	end
	if source == "local" then return "local" end
	if source == "derived" or source == "signed" or source == "addon" then return "derived" end
	if source == "report" or source == "roster" or source == "who" or source == "profile" or source == "inspection" then return "shared" end
	return "unknown"
end

local function Freshness(source, at)
	if source == "local" then return "current" end
	at = tonumber(at)
	if not at or at <= 0 then return "unknown" end
	local age = math.max(0, ns.Now() - at)
	local limit = ns.Data and tonumber(ns.Data.FRESH) or 15 * 60
	return age <= limit and "fresh" or "stale"
end

local function Field(key, value, source, at, explicit)
	source = CleanSource(source)
	local known = value ~= nil and value ~= ""
	local state = SourceState(source, explicit)
	if state == "hidden" then value, known = nil, false end
	if not known and state ~= "hidden" then state = "unknown" end
	return {
		key = key,
		value = value,
		known = known,
		source = source,
		provenance = source,
		at = tonumber(at),
		freshness = (state == "hidden" or state == "unknown") and "unknown" or Freshness(source, at),
		state = state,
	}
end

-- The one canonical model for the normal full-window profile and the legacy side card. Its
-- limits make an extension unable to turn a profile click into an unbounded UI/data surface.
function Profile.Model(p)
	local UI = ns.UI
	if type(UI) ~= "table" or type(UI.BasePersonDetails) ~= "function" then return nil end
	local details = UI.BasePersonDetails(p)
	if not details then return nil end
	local source = CleanSource(p.source)
	local at = tonumber(p.at or p.heard or p.profileAt or p.t)
	local fields, rows, rowMeta = {}, {}, {}
	local function AddField(field)
		if #fields < Profile.MAX_FIELDS then fields[#fields + 1] = field end
	end
	local function AddRow(text, meta)
		if #rows >= Profile.MAX_ROWS or type(text) ~= "string" or text == "" then return end
		text = ns.Cut(text, Profile.MAX_TEXT_BYTES)
		rows[#rows + 1] = text
		local field = Field(meta and meta.key or "extension", text,
			meta and meta.source or source, meta and meta.at or at, meta and meta.state)
		rowMeta[#rows] = field
		AddField(field)
	end

	for i, text in ipairs(details.rows or {}) do AddRow(text, details.rowMeta and details.rowMeta[i]) end
	details.rows, details.rowMeta = rows, rowMeta

	-- Header and absent facts are part of the model too, even when there is no row to render.
	-- Offline location is deliberately hidden, not reported as an empty or guessed zone.
	AddField(Field("name", details.full, details.full == ns.me and "local" or source, at))
	AddField(Field("guild", details.guild, source, at))
	AddField(Field("rank", p.rank and ns.Codec.Plain(tostring(p.rank)) or nil, source, at))
	AddField(Field("level", tonumber(p.level), source, at))
	AddField(Field("class", p.class, source, at))
	AddField(Field("online", p.online, source, at))
	AddField(Field("zone", p.online == false and nil or p.zone, source, at, p.online == false and "hidden" or nil))
	details.fields = fields
	details.bounds = { rows = Profile.MAX_ROWS, fields = Profile.MAX_FIELDS, textBytes = Profile.MAX_TEXT_BYTES }
	return details
end

local SOURCE_KEYS = {
	["local"] = "PROFILE_SOURCE_LOCAL", report = "PROFILE_SOURCE_REPORT", roster = "PROFILE_SOURCE_ROSTER",
	who = "PROFILE_SOURCE_WHO", profile = "PROFILE_SOURCE_PROFILE", inspection = "PROFILE_SOURCE_INSPECTION",
	addon = "PROFILE_SOURCE_ADDON", signed = "PROFILE_SOURCE_SIGNED", derived = "PROFILE_SOURCE_DERIVED",
	unknown = "PROFILE_SOURCE_UNKNOWN",
}
local FRESH_KEYS = {
	current = "PROFILE_FRESH_CURRENT", fresh = "PROFILE_FRESH_FRESH", stale = "PROFILE_FRESH_STALE",
	unknown = "PROFILE_FRESH_UNKNOWN",
}
local STATE_KEYS = {
	["local"] = "CONSENT_STATE_LOCAL", shared = "CONSENT_STATE_SHARED", derived = "CONSENT_STATE_DERIVED",
	hidden = "CONSENT_STATE_HIDDEN", unknown = "CONSENT_STATE_UNKNOWN",
}

local function MetaText(field)
	local source = L[SOURCE_KEYS[field.source] or SOURCE_KEYS.unknown]
	local fresh = L[FRESH_KEYS[field.freshness] or FRESH_KEYS.unknown]
	return L.PROFILE_FIELD_META:format(source, fresh)
end

local function MetaTip(field)
	return function(tt)
		tt:AddLine(L[STATE_KEYS[field.state] or STATE_KEYS.unknown], 1, 0.82, 0)
		tt:AddLine(MetaText(field), 0.7, 0.7, 0.7, true)
		if field.at and field.at > 0 then tt:AddLine(L.PROFILE_FIELD_HEARD:format(ns.Ago(field.at)), 0.7, 0.7, 0.7, true) end
	end
end

local function Action(text, fn)
	return { text = "|cffffd200" .. text .. "|r", onClick = fn }
end

-- History stays in the Arena's existing privacy-filtered provider and renderer. A normal
-- profile only offers its route; another player's display fields cannot grant consent.
local function FightHistoryAllowed(full)
	if type(full) ~= "string" or not ns.IsMember() then return false end
	if full == ns.me then return true end
	local M = ns.Moderation
	if M and M.Hides and M.Hides(full) then return false end
	local P = ns.ArenaProfile
	local p = P and P.Of and P.Of(full)
	return type(p) == "table" and p.pub == true
end

function Profile.OpenFightHistory(full)
	if not FightHistoryAllowed(full) then return false end
	local H = ns.ArenaHome
	return type(H) == "table" and type(H.Open) == "function" and H.Open("profile", full) == true or false
end

function Profile.Open(p)
	return ns.UI.OpenPlayerProfile(p)
end

-- A typed name's realm, as the server writes it: one this client knows (ours, our group's) in
-- the spelling it has ("classicbetapvp2" is ClassicBetaPvP2), else one that looks like a realm
-- (a letter first, then letters, digits or apostrophes: "Ann-12345" names none). nil if not.
local function TypedRealm(text)
	text = tostring(text or ""):gsub("[%s%-]", "")
	if text == "" then return nil end
	local want = ns.Fold(text)
	local known = { ns.realm, ns.CurrentRealm() }
	for _, r in ipairs(ns.GroupRealms(ns.group or ns.realm)) do known[#known + 1] = r end
	for _, r in ipairs(known) do
		if type(r) == "string" and r ~= "" and r ~= "?" and ns.Fold(r) == want then return r end
	end
	if #text > 48 or not text:match("^[%a\128-\255][%w\128-\255']*$") then return nil end
	return (text:gsub("^%l", string.upper))
end

-- A typed word of a character's name, as the server writes it: letters only, at most 12 of them
-- (Forever's character creation takes 12 for the name and 12 for the surname: the Camelot
-- Blizzard_CharacterCreate.xml boxes, letters="12"), counted as letters and not bytes so
-- accented ones fit, and capitalised ("zora" is Zora, "élan" is Élan: ns.Fold's letters).
local NAME_LETTERS = 12
local function NameWord(word)
	if not word:match("^[%a\128-\255]+$") or select(2, word:gsub("[^\128-\191]", "")) > NAME_LETTERS then return nil end
	word = ns.Fold(word)
	local accented = word:match("^\195([\160-\190])")
	if accented and accented ~= "\183" then return "\195" .. string.char(accented:byte() - 32) .. word:sub(3) end
	return (word:gsub("^%l", string.upper))
end

-- The profile's deep link (1.2, /oly profile): the page of the player `text` names ("Name",
-- "Name-Realm", Forever's "First Surname"), as the Realm's people lists know him
-- (Views.Person), or with his name alone when none does, written as the server writes names.
-- Like every other way in, it reads only what this client holds and asks the game for nothing;
-- Who stays the page's explicit button. nil when the text can't be a character's name.
function Profile.Find(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	-- A known realm typed in any case first, so Forever's split names (ns.Normal) see it as one.
	local head, tail = text:match("^(.+)%-([^%-]+)$")
	local realmFirst = tail and TypedRealm(tail)
	if realmFirst and ns.IsRealmName(realmFirst) then text = head .. "-" .. realmFirst end
	local name = ns.Normal(text)
	local first, second = name:gsub("%-.*$", ""):match("^([^ ]+) ?([^ ]*)$")
	first = first and NameWord(first)
	if not first or (second ~= "" and not NameWord(second)) then return nil end
	local short = second ~= "" and (first .. " " .. NameWord(second)) or first
	local realm = ns.RealmOf(name)
	if realm then
		realm = TypedRealm(realm)
		if not realm then return nil end
	end
	local V = ns.Views
	local known = type(V) == "table" and type(V.Person) == "function" and V.Person(ns.FullName(short, realm))
	return known or { name = short, realm = realm }
end

-- Opens it in the Olympus window. False and why ("name": not a name; "member": outside an
-- Olympus guild, where the window shows only the way in) when it can't.
function Profile.OpenName(text)
	local p = Profile.Find(text)
	if not p then return false, "name" end
	if not ns.IsMember() then return false, "member" end
	return ns.UI.OpenPlayerProfile(p) == true, nil
end

function Profile.Build(p)
	local details = Profile.Model(p)
	if not details then
		return { { text = L.PLAYER_PROFILE_NO_DATA } }, L.PLAYER_PROFILE_TITLE,
			L.PLAYER_PROFILE_ABOUT, { { "PLAYER_PROFILE_BACK", ns.UI.BackFromPlayerProfile } },
			L.PLAYER_PROFILE_TITLE, ""
	end

	local lines = { { text = L.PLAYER_PROFILE_DETAILS, header = true } }
	if #details.rows == 0 then
		lines[#lines + 1] = { text = L.PLAYER_PROFILE_NO_DATA }
	else
		for i, text in ipairs(details.rows) do
			local field = details.rowMeta[i]
			lines[#lines + 1] = { text = text, right = MetaText(field), tooltip = MetaTip(field) }
		end
	end

	if details.full == ns.me then
		local C = ns.Consent
		if type(C) == "table" and type(C.Show) == "function" then
			lines[#lines + 1] = Action(L.PROFILE_VISIBILITY_BTN, function() C.Show("profile") end)
		end
		if details.edit and p.onMark == nil then
			lines[#lines + 1] = Action(L.PROFILE_EDIT_BTN, function()
				ns.SafeCall("edit my profile", details.edit, p)
			end)
		end
	elseif type(p.onMark) == "function" then
		lines[#lines + 1] = Action(L.MARK_BTN, function()
			ns.SafeCall("mark", p.onMark)
			ns.UI.BackFromPlayerProfile()
		end)
	end
	if FightHistoryAllowed(details.full) then
		lines[#lines + 1] = Action(L.PROFILE_ARENA_HISTORY, function()
			return Profile.OpenFightHistory(details.full)
		end)
	end

	local online = p.online ~= false
	local buttons = {
		{ "PLAYER_PROFILE_BACK", ns.UI.BackFromPlayerProfile },
		{ "WHISPER", function() ns.UI.WhisperPerson(p) end, enabled = online },
		{ "INVITE", function() ns.UI.InvitePerson(p) end, enabled = online },
		{ "WHO", function() ns.UI.WhoPerson(p) end },
	}
	local sub = details.guild and ("<" .. details.guild .. ">") or ""
	-- The realm given apart, or the one a whole name carries ("Ann-Other": War's and other
	-- lists hand it so): another realm's player always says which, ours never ("Capt-Realm"
	-- reads as "Capt" does, whichever list opened him).
	local realm = (p.realm and p.realm ~= "" and p.realm) or ns.RealmOf(p.name)
	local ours = ns.realm or ns.CurrentRealm()
	if realm and realm ~= "" and ns.Fold(realm) ~= ns.Fold(ours) then
		realm = ns.Codec.Plain(realm)
		sub = sub ~= "" and (sub .. "  ·  " .. L.PLAYER_PROFILE_REALM:format(realm))
			or L.PLAYER_PROFILE_REALM:format(realm)
	end
	return lines, L.PLAYER_PROFILE_TITLE, L.PLAYER_PROFILE_ABOUT, buttons, details.nameText, sub
end

-- Profile privacy is status-only unless a real protocol-backed setter exists. The identity row
-- records that the normal profile derives a local view from existing facts; it never authorizes
-- new collection or transmission.
do
	local C = ns.Consent
	if type(C) == "table" and type(C.Register) == "function" then
		C.Register({
			key = "profileIdentity", section = "profile", focusOnly = true, readonly = true,
			label = "CONSENT_PROFILE_IDENTITY", text = "CONSENT_PROFILE_IDENTITY_TEXT",
			status = function() return "derived" end,
		})
	end
end
