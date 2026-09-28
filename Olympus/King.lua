local ADDON, ns = ...
local L = ns.L

-- The Throne: a tab for the King alone (the guild master of the guild named exactly
-- "Olympus" of his faction, and that very character where the addon knows him by name,
-- ns.KING_CHARACTER), and for the Hands he names. What he sends goes out on the Olympus
-- channel as T1 messages, and every client checks that the sender really is him (his name,
-- which the server sets: never a census vote, which anyone on the channel can cast), or one
-- of his Hands for the tools he lends them (HAND_MAY). Answers go back to whoever asked,
-- alone (T2, T3 as whispered addon messages).
--   T1~S~<id>~<guild>                      Summon the Lords (roll call)
--   T1~I~<id>~<guild>                      Royal Inspection: every addon patrols 2 minutes
--   T1~A~<id>~<guild>~<minutes>~<zone>~<title>   The King's Agenda (resent every 5 min)
--   T1~X~<id>~<guild>                      Agenda cancelled
--   T1~H~<date>~<guild>~<Name-Realm,...>   the Hands of the King (his and his Steward's; resent every 5 min)
--   T2~<id>~<P|B>~<guild>                  a Lord's answer to the roll call
--   T3~<id>~<guild>~<ok>~<none>~<other>~<name:guild,...>   an inspection report
-- Other modules add their own kinds (King.Register): Vox Populi (V, E), writs (W), the court
-- (C, Z), the gates (G), pardons (F), the treasury's switches and keepers (T, K: his and his
-- Steward's).
-- The King's Steward (1.0.0, ns.IsSteward: the character the author marks in the signed titles
-- list) has the Throne as the King has it, "acting for the King": he names and removes the
-- Hands, the treasury's keepers and its switches, and uses every tool of a Hand (STEWARD_MAY).
-- Never the King's crown on the map and his layer, the court, writs, pardons, the untabarded
-- list, or the King's own book of the treasury and his yes to share it.

local King = {}
ns.King = King

King.SUMMON_OPEN = 60        -- the popup stays this long
King.SUMMON_GAP = 60         -- one roll call a minute at most (sent or accepted)
King.INSPECT_TIME = 120      -- each addon patrols this long
King.INSPECT_GAP = 1800      -- one Royal Inspection every 30 minutes at most (0.9.2), whoever calls it
-- The realm's share of the load (0.9.2). An inspect is one request to the server for a player
-- in reach. Budget: INSPECT_BUDGET requests a second across the whole realm. A client on the
-- inspection sends one every INSPECT_PACE seconds at most, so INSPECT_BUDGET * INSPECT_PACE =
-- 100 clients can take part at once; with N addons online (the census counts them) each one
-- takes part with probability 100 / N (all of them while there are 100 or fewer). 3,000 online:
-- 1 in 30, about 20 requests a second for 2 minutes, then nothing for at least 30 minutes.
King.INSPECT_BUDGET = 20
King.INSPECT_PACE = 5
King.AGENDA_RESEND = 300     -- the King's client repeats the agenda for late logins
King.MAX_NAMES = 6           -- violators per inspection report (message size)
King.AGENDA_GAP = 60         -- one new agenda a minute at most (each one is a raid warning)
King.MAX_ANSWERS = 150       -- roll-call answers kept
King.MAX_REPORTS = 150       -- inspection reports kept
King.MAX_CHECKS = 60         -- checks one patrol can report in 2 minutes
King.MAX_SHOWN = 30          -- violators listed on the page

King.MAX_HANDS = 40          -- Hands of the King (the list goes out in pieces when long)
King.HANDS_EVERY = 300       -- the King's client repeats the list for late logins
King.HANDS_FRESH = 20 * 60   -- a list the King stopped repeating (he left) ends

King.mode = nil              -- what the tab shows: home or hands (nil: home, the Throne Room)
local summon, inspect        -- the King's own roll call / inspection in progress
local agenda                 -- the agenda everyone sees: { id, title, at, zone, by }
local lastSummonSeen, lastInspectSeen, inspecting = -math.huge, -math.huge, nil
local lastSummonSent, lastInspectSent = -math.huge, -math.huge
local lastAgendaSent, lastAgendaWarn = -math.huge, -math.huge

-- Text other players send that ends up on the King's screen (on stream): only what looks
-- like a character name ("Pyralis Ashandar") or an Olympus guild name, nothing else.
local function CleanName(s)
	s = tostring(s or ""):gsub("%-.*$", "")
	if #s > 30 or not s:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	return s
end
local function CleanGuild(s)
	s = tostring(s or ""):gsub("[%c|]", "")
	if #s > 24 or not ns.IsFederation(s) or not s:match("^[%w\128-\255 ]+$") then return nil end
	return s
end

-- Someone we can place: our own guild (the server's roster) or a Lord or Captain the census
-- confirms (Data.KnownRank). Only they may put names on the King's page.
local function Verified(sender, guild)
	if ns.Roster.RankOf(sender) then return true end
	local rank = guild and ns.Data.KnownRank(sender, guild)
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------

-- Where the King is pinned by name, another guild master of his guild is not him: nobody
-- would obey the powers the Throne gave that character.
function King.IsKing()
	if not ns.IsMember() then return false end
	local guild, _, rank = GetGuildInfo("player")
	if not (ns.IsKingGuild(guild) and rank == 0) then return false end
	return ns.KingCharacter() == nil or ns.IsKingCharacter(ns.me)
end

-- The author's test build (Dev.lua, never published) shows the tab without the powers:
-- nothing it does reaches anyone. The author turns this "Asmon's view" on and off from the
-- Workshop (ns.db.devKingView).
function King.Preview()
	if King.IsKing() then return false end
	local view = ns.db and ns.db.devKingView
	if view ~= nil and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() then return view == true end
	local dev = ns.devThrone
	if type(dev) == "table" then dev = dev[UnitName and UnitName("player") or ""] == true or dev[ns.ShortName(ns.me or "")] == true end
	return dev == true and not King.IsKing()
end
function King.Visible() return King.IsKing() or King.IsSteward() or King.IsHand() or King.Preview() end

-- The King's Steward (1.0.0): this character, where the signed titles list marks it for our
-- King (ns.IsSteward), and not the King himself.
function King.IsSteward() return not King.IsKing() and ns.IsSteward(ns.me) end
-- A sender the list marks (the server sets the name): his word counts for what STEWARD_MAY lends.
function King.IsStewardName(name) return type(name) == "string" and not ns.IsKingCharacter(name) and ns.IsSteward(name) end

-- The King himself, or his Steward: the lists of the Throne (the Hands, the treasury's keepers
-- and switches) are theirs to set, and their clients repeat them.
function King.SetsLists() return King.IsKing() or King.IsSteward() end

-- Where the King is pinned by name (ns.KING_CHARACTER): that character alone, speaking for
-- the King's guild. No census vote can crown anyone else, nor silence him. Where he is not
-- (the Horde, until his name is known) nobody's commands are obeyed; soft: what only shows
-- (his position, his name on the lines) still comes from the census there (Data.KnownRank).
local function KingSender(sender, guild, soft)
	if not ns.IsKingGuild(guild) then return false end
	if ns.KingCharacter() then
		if not ns.IsKingCharacter(sender) then return false end
		ns.LearnKingRealm(sender) -- (the Horde's, while unknown: from the server's name)
		return true
	end
	return soft == true and ns.Data.KnownRank(sender, guild, true) == 0
end

-- The page refreshes at most once a second, whatever arrives.
local changePending = false
local function Changed()
	if changePending then return end
	changePending = true
	ns.After(1, "throne refresh", function()
		changePending = false
		ns.Fire("THRONE_CHANGED")
	end)
end

local function Warn(text, loud)
	ns.Print("|cffffd200" .. text .. "|r")
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
	end
	ns.PlayAlert(loud and "loud" or "soft")
end

local function NewId() return math.random(1, 99999) end

---------------------------------------------------------------------------
-- The Hands of the King: the players he names use the Throne's tools in his name (HAND_MAY:
-- the roll call, the inspection, the agenda, Vox Populi, the gates), never what is his alone
-- (the Hands, writs, the court, pardons, his position). Each client keeps the list it took
-- last; a list nobody repeats any more ends (HANDS_FRESH).
-- 1.0.0: the King's Steward names and removes them too (STEWARD_MAY), and the list carries its
-- date (the server's clock) where the message had its id. The newest list wins everywhere, and
-- on the same date the King's own: his newer word always wins. A date further ahead of the
-- server's clock than DATE_AHEAD is not taken. The King's client and his Steward's take the
-- newest list as theirs and repeat it (the Hands last while either is online), and answer an
-- older one they hear with theirs (HANDS_ANSWER apart at most). Clients before 1.0.0 take the
-- King's list alone (the date is the id they never read), never a Steward's.
-- The King and his Steward are rarely online together, so a list can be older than one the
-- army already holds (a review's finding: the King's client or a Steward's, away while the
-- other changed the Hands, came back and repeated its saved list, and every client that had not
-- heard the change took it: a Hand removed was a Hand again). So:
--  * Every client keeps the newest list it took across sessions (rdb.kingHands and the rest,
--    SaveHands), with its date and whose word it was, and never takes an older one. A kept list
--    names nobody until the King's client or a Steward's is heard (handsAt).
--  * A list the King's client or a Steward's saved in an earlier session goes out held back
--    ("?" before the names) until HANDS_CONFIRM has passed with nobody saying a newer one is
--    held; then as the newest. A list its sender holds back is never taken on a soldier's
--    client (clients before 1.0.0 take its names as they always did: "?" is no name to them).
--  * A client holding a newer list than one it hears says so, dated and whose (TH~, drawn like
--    the council's list answers: about HANDS_HINTS clients, HANDS_HINT_GAP apart at most). The
--    King's or a Steward's client that did not set or take its list this session then keeps it
--    held back ("!": said, and not the newest), and he is told, until he hears the newer one
--    from whoever set it or names the Hands again. The claim is anybody's word, so that is all it
--    does: it never names or removes a Hand anywhere.
--  * Hearing the King's or a Steward's client, whatever the date of its list, keeps the newest
--    list a client holds (the Crown is online): the Hands never lapse while either is online.
--  * A list a Steward set counts no longer than he does: once the signed titles list no longer
--    names him, any list of the King's (or of another Steward) replaces it, whatever its date.
--  * A list without a date (a King's client before 1.0.0) is dated as his oldest word while it
--    is the one last heard from him (saved: rdb.kingHandsUndated), so his unchanged repeats never
--    replace his Steward's newer list; a changed one is his newer word, and a Steward whose list
--    it replaces is told.
---------------------------------------------------------------------------

King.HAND_MAY = { S = true, I = true, A = true, X = true, V = true, E = true, G = true }
-- The Steward's: everything a Hand may, and the lists the King keeps (his Hands; the treasury's
-- switches and keepers, Treasury.lua). Never his crown on the map (P, Q), the court (C, Z),
-- writs (W), pardons (F) or the untabarded list (U).
King.STEWARD_MAY = { S = true, I = true, A = true, X = true, V = true, E = true, G = true, H = true, T = true, K = true }
King.DATED = 1000000000      -- an id this high is a list's date (1.0.0 on); lower, an id (before)
King.DATE_AHEAD = 600        -- a list dated further ahead of the server's clock is not taken
King.HANDS_ANSWER = 30       -- the King's or a Steward's client answers an older list this often at most
King.HANDS_CONFIRM = 30      -- a saved list goes out held back this long before it goes out as the newest
King.HELD_BACK, King.HELD_PAUSED = "?", "!" -- before the names: held back (to be confirmed; older than one the army holds)
-- Saying a newer list is held: about HANDS_HINTS clients draw it, whatever the army's size (only
-- those holding that list take part, so more than the council's answers; the first one heard
-- holds the others back), each at most once in HANDS_HINT_GAP.
King.HANDS_HINTS = 10
King.HANDS_HINT_GAP = 300
King.HANDS_HINT_MIN, King.HANDS_HINT_SPREAD = 2, 8 -- said 2 to 10 seconds after the draw

local myHands = {}       -- the list this client holds, in order: { "Name-Realm", ... } (saved, rdb.kingHands)
local hands = {}         -- the same list: [Name-Realm] = true
local handsDate = 0      -- its date (the server's clock; 0: none yet)
local handsByKing = false -- the King himself sent it (a list of the same date from a Steward loses)
local handsFrom          -- the Steward who set it, when not the King (it counts while he is one)
local handsAt = -math.huge -- when this client last heard the King's client or a Steward's (our clock)
local handsKing          -- the King who sent it last (whose Hand, on a Hand's Throne Room)
local undatedText        -- the list last heard from a King's client before 1.0.0 (saved)
local previewHands = {}  -- the author's Asmon's view: its own list, on his screen only
local lastHandsSent, lastHandsAnswer = -math.huge, -math.huge
local handsSendPending = false
-- The King's client and a Steward's: whether it goes out as the newest (set or taken this
-- session, or said held back HANDS_CONFIRM ago with nobody saying a newer one is held), whether
-- this client set it itself this session (then nobody's word holds it back), the newest date the
-- army said is held (and whose), and when it first went out held back.
local handsSure, handsSet, heardNewer, heardNewerByKing = false, false, 0, false
local heldBackAt, confirmPending = -math.huge, false
-- Saying a newer list is held: our last draw, our answer waiting, and the latest said by anyone.
local lastHintDrawn, hintPending, hintHeard = -math.huge, nil, nil

-- The clock a list is dated by: the server's, the same on every client.
local function Clock() return GetServerTime and GetServerTime() or ns.Now() end

-- The King's client and his Steward's hold the list they repeat (it never lapses there); everyone
-- else trusts the list while the King or a Steward keeps repeating it.
local function Hand(name)
	local full = ns.FullName(name)
	if not King.SetsLists() and ns.Now() - handsAt > King.HANDS_FRESH then return false end
	return hands[full] == true
end

function King.IsHand() return not King.SetsLists() and ns.IsMember() and Hand(ns.me) end
-- Whether the list names this sender (1.0.0): the King's word or his Steward's, never a census
-- vote. His Hands speak with his Crown for his guild on every client outside it (Decree.lua,
-- Channels.VerifiedLevel); on its own members' clients its roster says who speaks for it.
function King.IsHandName(name) return type(name) == "string" and Hand(name) end
function King.Hands()
	if King.Preview() and not King.SetsLists() then return previewHands end
	return myHands
end

-- The King may send it; his Steward what STEWARD_MAY lends him; one of his Hands what is theirs
-- to use too (soft: his position).
function King.Authorized(kind, sender, guild)
	if KingSender(sender, guild, kind == "P" or kind == "Q") then return true end
	if King.STEWARD_MAY[kind] == true and King.IsStewardName(sender) then return true end
	return King.HAND_MAY[kind] == true and Hand(sender)
end

-- The King, his Steward, or a Hand: the tools of the Throne.
function King.CanCommand() return King.IsKing() or King.IsSteward() or King.IsHand() end

-- The King himself sent it (not a Hand): for how it is shown.
function King.FromKing(sender, guild) return KingSender(sender, guild, true) end

-- A Steward's name as the King's screen shows it: cut short while the council's names are hidden
-- there (his stream, ns.CouncilMasked), like every councillor's.
local function StewardLabel(name)
	local shown = ns.DisplayName(name) or "?"
	return ns.CouncilMasked() and ns.MaskName(shown) or shown
end
King.StewardLabel = StewardLabel

-- The list held still counts: the King's word, or a Steward's while the signed list names him.
local function HeldValid()
	if handsDate == 0 then return false end
	return handsByKing or King.IsStewardName(handsFrom)
end

-- A newer list is held elsewhere, the army says, and this client did not set its own this
-- session: it goes out held back ("!").
local function Paused() return not handsSet and heardNewer > handsDate end

-- The list held, kept across sessions with its date and whose word it was (a /reload must not
-- drop the Hands; an older list heard in a later session is not taken).
local function SaveHands()
	if not ns.rdb then return end
	local copy = {}
	for i, n in ipairs(myHands) do copy[i] = n end
	ns.rdb.kingHands, ns.rdb.kingHandsAt, ns.rdb.kingHandsByKing = copy, handsDate, handsByKing or nil
	ns.rdb.kingHandsFrom, ns.rdb.kingHandsUndated = not handsByKing and handsFrom or nil, undatedText
end

-- The list becomes `names` (in order), dated `at`, the King's word or `from`'s (a Steward).
local function SetHands(names, at, byKing, from)
	wipe(myHands)
	wipe(hands)
	for i, n in ipairs(names) do
		myHands[i] = n
		hands[n] = true
	end
	handsDate, handsByKing = at, byKing == true
	handsFrom = not handsByKing and from or nil
end

-- Several changes in a row go out as one list, a few seconds after the last one.
local function SendHandsSoon()
	if handsSendPending then return end
	handsSendPending = true
	ns.After(3, "king hands", function()
		handsSendPending = false
		King.SendHands(true)
	end)
end

-- A list said held back HANDS_CONFIRM ago, nobody saying a newer one is held since: the newest.
local function ConfirmDue(now)
	return not handsSure and not Paused() and heldBackAt ~= -math.huge and now - heldBackAt >= King.HANDS_CONFIRM
end

-- The list goes out whole, with its date: short in one message, long in pieces (Comm.SendChunked).
-- From the King's client and his Steward's alone, once someone named a Hand; held back while it
-- is not known to be the newest (see above).
function King.SendHands(force)
	if not King.SetsLists() then return end
	local now = ns.Now()
	if not force and now - lastHandsSent < King.HANDS_EVERY and not ConfirmDue(now) then return end
	if handsDate == 0 then return end -- nobody named yet
	if ConfirmDue(now) then handsSure = true end
	local mark
	if Paused() then mark = King.HELD_PAUSED
	elseif not handsSure then
		mark = King.HELD_BACK
		if heldBackAt == -math.huge then
			heldBackAt = now
			if not confirmPending then
				confirmPending = true
				ns.After(King.HANDS_CONFIRM, "king hands", function()
					confirmPending = false
					King.SendHands()
				end)
			end
		end
	end
	lastHandsSent = now
	local names = table.concat(myHands, ",")
	if mark then names = mark .. (names ~= "" and "," .. names or "") end
	local msg = ("T1~H~%d~%s~%s"):format(math.max(math.floor(handsDate), King.DATED), GetGuildInfo("player") or "", names)
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "hands") else ns.Comm.SendChunked(msg) end
end

-- A name typed or targeted, as the server writes it; nil if it can't be a character.
local function HandName(input)
	local name = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		name = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target") or ""
	end
	name = ns.Normal(name)
	local short = CleanName(name)
	if not short then return nil end
	return ns.FullName(short, ns.RealmOf(name))
end

-- The King or his Steward changed the list on his screen: dated newer than the list held (two
-- changes in one second too), kept, sent as the newest (his own word, this session). The
-- author's Asmon's view: its own list, sent nowhere.
local function ChangeHands(names)
	if not King.SetsLists() then
		wipe(previewHands)
		for i, n in ipairs(names) do previewHands[i] = n end
		return
	end
	local king = King.IsKing()
	SetHands(names, math.max(Clock(), handsDate + 1), king, not king and ns.me or nil)
	handsSure, handsSet = true, true
	SaveHands()
	SendHandsSoon()
end

function King.AddHand(input)
	if not King.SetsLists() and not King.Preview() then return ns.Print(L.THRONE_ONLY_KING) end
	local name = HandName(input)
	if not name then return ns.Print(L.HANDS_WHO) end
	if name == ns.me then return end
	local names = {}
	for i, n in ipairs(King.Hands()) do
		if n == name then return end
		names[i] = n
	end
	if #names >= King.MAX_HANDS then return ns.Print(L.HANDS_FULL:format(King.MAX_HANDS)) end
	names[#names + 1] = name
	ChangeHands(names)
	ns.Print(L.HANDS_ADDED:format(ns.DisplayName(name)))
	King.mode = "hands"
	Changed()
end

function King.RemoveHand(name)
	if not King.SetsLists() and not King.Preview() then return end
	local names, found = {}, false
	for _, n in ipairs(King.Hands()) do
		if n == name then found = true else names[#names + 1] = n end
	end
	if not found then return end
	ChangeHands(names)
	ns.Print(L.HANDS_REMOVED:format(ns.DisplayName(name)))
	return Changed()
end

-- A soldier's client holding a newer list than one the King's or a Steward's client said: a few
-- clients of the army say so (TH~<its date>~<K: the King's | S: a Steward's>), drawn like the
-- council's list answers (Workshop.AnswerAsk): about HANDS_HINTS of the addons the census counts
-- draw it (those that hold the newer list), none while it counts nobody but us, a draw at most
-- once in HANDS_HINT_GAP, said a few seconds later, and left out when someone said as much
-- meanwhile.
local function HintSoon()
	if King.SetsLists() or handsDate < King.DATED then return end
	local now = ns.Now()
	if hintPending or now - lastHintDrawn < King.HANDS_HINT_GAP then return end
	if hintHeard and hintHeard.at >= handsDate and now - hintHeard.t < King.HANDS_HINT_GAP then return end
	local users = King.AddonsOnline()
	if users <= 1 then return end
	lastHintDrawn = now
	if King.random() > math.min(1, King.HANDS_HINTS / users) then return end
	local pending = { at = handsDate }
	hintPending = pending
	ns.After(King.HANDS_HINT_MIN + King.random() * King.HANDS_HINT_SPREAD, "king hands hint", function()
		if hintPending ~= pending then return end
		hintPending = nil
		if handsDate ~= pending.at or King.SetsLists() then return end
		ns.Comm.Send("CHANNEL", ("TH~%d~%s"):format(math.floor(handsDate), handsByKing and "K" or "S"), "handshint")
	end)
end

-- Someone says a newer list is held than the King's or a Steward's client said. Anybody's word:
-- it holds this client's own list back (the King's or a Steward's, not set by him this
-- session; he is told once), and holds back our own saying it. Never a Hand named or removed.
function King.HandleHint(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > 20 then return end
	local at, by = text:match("^TH~(%d+)~([KS])$")
	at = tonumber(at)
	if not at or at < King.DATED or at > Clock() + King.DATE_AHEAD then return end
	local now = ns.Now()
	if not hintHeard or at >= hintHeard.at or now - hintHeard.t >= King.HANDS_HINT_GAP then hintHeard = { at = at, t = now } end
	if hintPending and at >= hintPending.at then hintPending = nil end
	if not King.SetsLists() or handsDate == 0 or at <= handsDate or at <= heardNewer then return end
	local was = Paused()
	heardNewer, heardNewerByKing = at, by == "K"
	if Paused() and not was then
		ns.Log("hands: %s says a newer list is held (%s's, %d): ours held back", tostring(sender), by, at)
		ns.Print(L.HANDS_NEWER_HELD:format(heardNewerByKing and L.HANDS_BY_KING or L.HANDS_BY_STEWARD))
		Changed()
	end
end
ns.Comm.Handle("TH", function(...) King.HandleHint(...) end)

-- A list from the King or his Steward (King.Authorized agreed). `id`: its date, or (a King's
-- client before 1.0.0) an id. "?" or "!" before the names: its sender holds it back.
local function OnHands(sender, id, rest, guild)
	local byKing = KingSender(sender, guild)
	local clock = Clock()
	local at = tonumber(id) or 0
	local undated = at < King.DATED
	local mark, names = tostring(rest or ""):match("^([%?!]),?(.*)$")
	if not mark then names = tostring(rest or "") end
	if undated and (mark or not byKing) then return end -- (a 1.0.0 client, a Steward's too, always dates its list)
	if not undated and at > clock + King.DATE_AHEAD then
		ns.Log("hands from %s ignored: dated ahead of the server's clock", tostring(sender))
		return
	end
	local list, seen = {}, {}
	for name in names:gmatch("[^,]+") do
		local short = CleanName(name)
		local full = short and ns.FullName(short, ns.RealmOf(name))
		if full and not seen[full] and #list < King.MAX_HANDS then
			seen[full] = true
			list[#list + 1] = full
		end
	end
	local text, held = table.concat(list, ","), table.concat(myHands, ",")
	if undated then
		-- A King's client before 1.0.0: his changed list is his newer word; the list we hold, his,
		-- repeated; otherwise (first heard, or unchanged) his oldest word.
		if undatedText ~= nil and text ~= undatedText then at = math.max(clock, handsDate + 1)
		elseif text == held and handsByKing then at = handsDate
		else at = King.DATED end
		if undatedText ~= text then
			undatedText = text
			SaveHands()
		end
	end
	local valid = HeldValid()
	local heldAt = valid and handsDate or 0
	local sets = King.SetsLists()
	-- The list we hold, repeated.
	local same = valid and text == held and at == handsDate
	-- Newer: a later date; on the same date the King's over a Steward's (and between two lists of
	-- the same weight, the same one on every client).
	local newer = not same and (at > heldAt
		or (at == heldAt and ((byKing and not handsByKing) or (byKing == handsByKing and text > held))))
	local was = King.IsHand()
	if same then
		handsAt = ns.Now()
		if byKing and not handsByKing then
			handsByKing, handsFrom = true, nil
			SaveHands()
		end
		-- Another client of the King's or a Steward's vouches for the list we hold: the newest.
		if sets and not mark then handsSure = true end
	elseif newer then
		-- Held back by its sender: never taken on a soldier's client (not known to be the newest).
		if mark and not sets then return end
		if text ~= held then
			-- His Steward changed the King's list: the King is told (the name cut short on his stream).
			if King.IsKing() and not byKing then ns.Print(L.STEWARD_SET_HANDS:format(StewardLabel(sender))) end
			-- The King's own word replaced a Steward's list on a Steward's client: he is told.
			if King.IsSteward() and byKing and handsDate > 0 and not handsByKing then ns.Print(L.STEWARD_KING_HANDS) end
		end
		SetHands(list, at, byKing, ns.FullName(sender))
		handsAt = ns.Now()
		-- Taken as said: the newest, or held back here too until confirmed; someone else's word
		-- now (the army's word that a newer one is held can hold it back again).
		handsSure, handsSet = not mark, false
		if mark then heldBackAt = -math.huge end
		SaveHands()
	else
		-- Older than ours: the Crown is online, and the newest list we hold stands.
		if valid then handsAt = ns.Now() end
		if not undated then
			if sets then
				-- The King's client and a Steward's answer with the list they hold.
				if not Paused() and ns.Now() - lastHandsAnswer >= King.HANDS_ANSWER then
					lastHandsAnswer = ns.Now()
					SendHandsSoon()
				end
			elseif valid and mark ~= King.HELD_PAUSED then
				HintSoon()
			end
		end
	end
	if byKing then handsKing = ns.FullName(sender) end
	local now = King.IsHand()
	if now and not was then
		ns.Print(handsByKing and L.HANDS_YOU:format(ns.KingName(handsKing or ns.KingCharacter()))
			or L.HANDS_YOU_STEWARD:format(ns.DisplayName(handsFrom) or "?"))
		ns.PlayAlert("soft")
		ns.Fire("DATA_CHANGED") -- the Throne's tab appears
	elseif was and not now then
		ns.Fire("DATA_CHANGED")
	end
	Changed()
end

-- The list this client kept (SaveHands), at login: the King's client and his Steward's hold it
-- back until confirmed (SendHands); on anyone else's it names nobody until the King or a
-- Steward is heard (handsAt). A list saved before 1.0.0 (the King's, without a date) is his
-- oldest word (DATED).
function King.LoadHands()
	local r = ns.rdb
	local saved, names = r and r.kingHands, {}
	for _, n in ipairs(type(saved) == "table" and saved or {}) do
		if type(n) == "string" and #names < King.MAX_HANDS then names[#names + 1] = n end
	end
	local at = tonumber(r and r.kingHandsAt)
	local byKing = (at == nil and #names > 0) or (r ~= nil and r.kingHandsByKing == true)
	local from = r and type(r.kingHandsFrom) == "string" and r.kingHandsFrom or nil
	SetHands(names, at or (#names > 0 and King.DATED or 0), byKing, from)
	undatedText = r and type(r.kingHandsUndated) == "string" and r.kingHandsUndated or nil
	handsAt, handsSure, handsSet, heardNewer, heardNewerByKing = -math.huge, false, false, 0, false
	heldBackAt = -math.huge
end

-- Whether this client's own list goes out held back, and why (the Throne's Hands page, /oly status).
function King.HandsHeldBack()
	if not King.SetsLists() or handsDate == 0 then return nil end
	if Paused() then return "newer", heardNewerByKing end
	if not handsSure then return "confirming" end
	return nil
end

StaticPopupDialogs["OLYMPUS_KING_HAND"] = {
	text = L.HANDS_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 40,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
			eb:SetText(target and ns.DisplayName(target) or "")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("add hand", King.AddHand, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("add hand", King.AddHand, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_KING_UNHAND"] = {
	text = L.HANDS_REMOVE_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data) ns.SafeCall("remove hand", King.RemoveHand, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Other modules' kinds of T1 (Vox Populi, writs, the court, the gates, pardons):
-- fn(sender, id, rest, guild), called once King.Authorized agreed.
local kinds = {}
function King.Register(kind, fn) kinds[kind] = fn end
King.Changed = function() Changed() end
King.Warn = function(text, loud) Warn(text, loud) end
King.NewId = function() return NewId() end
King.CleanName = function(s) return CleanName(s) end
King.CleanGuild = function(s) return CleanGuild(s) end
King.Verified = function(sender, guild) return Verified(sender, guild) end

-- Our tabard, checked the way a patrol checks others (level 15+ only: the Olympus rule).
local function OwnTabard()
	local level = UnitLevel and UnitLevel("player") or 0
	if level > 0 and level < (ns.Inspect.MIN_LEVEL or 15) then return nil end
	local item = GetInventoryItemID and GetInventoryItemID("player", INVSLOT_TABARD or 19)
	return ns.Inspect.Classify(item, true)
end

---------------------------------------------------------------------------
-- Summon the Lords
---------------------------------------------------------------------------

function King.Summon()
	local now = ns.Now()
	if King.Preview() then
		summon = { id = 0, t = now, answers = {}, preview = true }
		ns.Print(L.THRONE_PREVIEW_NOTE)
		return Changed()
	end
	if not King.CanCommand() then return end
	if now - lastSummonSent < King.SUMMON_GAP then
		ns.Print(L.THRONE_WAIT:format(math.ceil(King.SUMMON_GAP - (now - lastSummonSent))))
		return Changed()
	end
	lastSummonSent = now
	summon = { id = NewId(), t = now, answers = {} }
	ns.Comm.Send("CHANNEL", ("T1~S~%d~%s"):format(summon.id, GetGuildInfo("player")))
	ns.Log("throne: summon %d", summon.id)
	Changed()
end

local function OnSummon(king, id, guild)
	local now = ns.Now()
	if now - lastSummonSeen < King.SUMMON_GAP then return end
	if not ns.IsMember() or ns.Roster.MyRank() > ns.CAPTAIN_RANK then return end
	lastSummonSeen = now
	ns.PlayAlert("soft")
	-- The King by the army's name for him; a Hand by theirs.
	local who = King.FromKing(king, guild) and L.THRONE_SUMMONED:format(ns.KingName(king)) or L.THRONE_SUMMONED_HAND:format(ns.DisplayName(king))
	ns.ShowDialog("OLYMPUS_KING_SUMMON", who, nil, { king = king, id = id })
end

local function Answer(data, word)
	if not data or not data.king then return end
	ns.Comm.Whisper(data.king, ("T2~%d~%s~%s"):format(data.id, word, GetGuildInfo("player") or ""))
end

StaticPopupDialogs["OLYMPUS_KING_SUMMON"] = {
	text = "%s",
	button1 = L.THRONE_PRESENT,
	button2 = L.THRONE_BUSY,
	OnAccept = function(self, data) ns.SafeCall("throne answer", Answer, data or self.data, "P") end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("throne answer", Answer, data or self.data, "B") end
	end,
	timeout = King.SUMMON_OPEN,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The Lords and Captains the census knows online, answered or not: { name, guild, rank }.
local function LordsOnline()
	local out = {}
	for _, e in ipairs(ns.Data.Summary().guilds) do
		local g = e.g
		if e.fresh then
			local home = g.realm or ns.realm
			if g.leader and g.leaderOnline then out[#out + 1] = { name = ns.FullName(g.leader, home), guild = e.name, rank = 0 } end
			for _, o in ipairs(g.officers or {}) do
				if o.online then out[#out + 1] = { name = ns.FullName(o.name, home), guild = e.name, rank = 1 } end
			end
		end
	end
	return out
end

function King.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" or not summon or summon.preview then return end
	local id, word, guild = text:match("^T2~(%d+)~([PB])~(.*)$")
	if tonumber(id) ~= summon.id or ns.Now() - summon.t > 300 then return end
	sender = ns.FullName(sender)
	if summon.answers[sender] then return end -- one answer each
	guild = CleanGuild(guild)
	-- Only confirmed Lords and Captains are listed by name; anyone else is just counted.
	if not guild or not Verified(sender, guild) then
		summon.others = summon.others or {}
		if not summon.others[sender] then
			local n = 0
			for _ in pairs(summon.others) do n = n + 1 end
			if n < King.MAX_ANSWERS then summon.others[sender] = word end
		end
		return Changed()
	end
	local n = 0
	for _ in pairs(summon.answers) do n = n + 1 end
	if n >= King.MAX_ANSWERS then return end
	summon.answers[sender] = { word = word, guild = guild, verified = true, t = ns.Now() }
	Changed()
end
ns.Comm.Handle("T2", function(...) King.HandleAnswer(...) end)

---------------------------------------------------------------------------
-- Royal Inspection
---------------------------------------------------------------------------

function King.Inspect()
	local now = ns.Now()
	if King.Preview() then
		ns.Print(L.THRONE_PREVIEW_NOTE)
		inspect = { id = 0, t = now, reports = {}, preview = true }
		King.RunInspection(nil, 0) -- our own patrol only, reported to ourselves
		return Changed()
	end
	if not King.CanCommand() then return end
	if now - lastInspectSent < King.INSPECT_GAP then
		ns.Print(L.THRONE_WAIT:format(math.ceil(King.INSPECT_GAP - (now - lastInspectSent))))
		return Changed()
	end
	lastInspectSent = now
	inspect = { id = NewId(), t = now, reports = {} }
	ns.Comm.Send("CHANNEL", ("T1~I~%d~%s"):format(inspect.id, GetGuildInfo("player")))
	ns.Log("throne: inspection %d", inspect.id)
	King.RunInspection(ns.me, inspect.id) -- the King patrols too
	Changed()
end

-- Every addon (the King's too): a raid warning, a patrol of INSPECT_TIME, then a report to
-- the King of what it saw (and our own tabard).
function King.RunInspection(king, id)
	if inspecting or not ns.IsMember() then return end
	local start = ns.Now()
	inspecting = { king = king, id = id, start = start, wasOn = ns.Inspect.IsPatrolling() }
	Warn(L.THRONE_INSPECT_WARN, true)
	if not inspecting.wasOn then ns.Inspect.SetPatrol(true) end
	ns.Inspect.SetPace(King.INSPECT_PACE) -- the realm's budget (INSPECT_BUDGET)
	ns.After(King.INSPECT_TIME, "royal inspection", function()
		local run = inspecting
		inspecting = nil
		ns.Inspect.SetPace(nil)
		if not run then return end
		if not run.wasOn and ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
		local ok, none, other, names = 0, 0, 0, {}
		-- A patrol does not re-inspect anyone checked in the last 10 minutes: those count too.
		for name, p in pairs(ns.Inspect.Players()) do
			if (p.t or 0) >= run.start - 600 then
				if p.status == "GUILD" then ok = ok + 1
				elseif p.status == "NONE" or p.status == "OTHER" then
					if p.status == "NONE" then none = none + 1 else other = other + 1 end
					if #names < King.MAX_NAMES then names[#names + 1] = (ns.DisplayName(name) or "?") .. ":" .. (p.guild or "?") .. ":" .. (p.status == "NONE" and "N" or "O") end
				end
			end
		end
		local own = OwnTabard()
		if own == "GUILD" then ok = ok + 1 elseif own == "NONE" then none = none + 1 elseif own == "OTHER" then other = other + 1 end
		local guild = GetGuildInfo("player") or ""
		local msg = ("T3~%d~%s~%d~%d~%d~%s"):format(run.id or 0, guild, ok, none, other, table.concat(names, ","))
		if run.king == ns.me or not run.king then
			King.ReceiveReport(ns.me, msg) -- ours (the King's, or the preview's)
		else
			ns.Comm.Whisper(run.king, msg:sub(1, 250))
		end
	end)
end

-- The addons online the census knows of (fresh reports), at least 1.
function King.AddonsOnline()
	local n = 0
	for _, e in ipairs(ns.Data.Summary().guilds) do
		if e.fresh then n = n + (tonumber(e.g.users) or 0) end
	end
	return math.max(n, 1)
end

-- This client's chance to take part in an inspection (see INSPECT_BUDGET).
function King.InspectShare()
	return math.min(1, King.INSPECT_BUDGET * King.INSPECT_PACE / King.AddonsOnline())
end
King.random = math.random -- tests

local function OnInspect(king, id)
	local now = ns.Now()
	if now - lastInspectSeen < King.INSPECT_GAP then return end
	lastInspectSeen = now
	-- Everyone hears the King's call; only a sample of the army patrols (and reports), and never
	-- a player who said no (/oly inspection off, 0.9.3).
	if ns.db and ns.db.royalInspection == false then
		ns.Log("inspection %d: not taking part (/oly inspection off)", id or 0)
		return Warn(L.THRONE_INSPECT_WARN, true)
	end
	if King.random() > King.InspectShare() then
		ns.Log("inspection %d: not in this sample (%.2f)", id or 0, King.InspectShare())
		return Warn(L.THRONE_INSPECT_WARN, true)
	end
	King.RunInspection(king, id)
end

function King.ReceiveReport(sender, text)
	if not inspect then return end
	local id, guild, ok, none, other, names = text:match("^T3~(%d+)~([^~]*)~(%d+)~(%d+)~(%d+)~(.*)$")
	if not id or tonumber(id) ~= inspect.id or ns.Now() - inspect.t > 900 then return end
	sender = ns.FullName(sender)
	if inspect.reports[sender] then return end -- one report each
	local n = 0
	for _ in pairs(inspect.reports) do n = n + 1 end
	if n >= King.MAX_REPORTS then return end
	guild = CleanGuild(guild)
	if not guild then return end
	-- Only from someone we can place in that guild (our own, a confirmed Lord or Captain):
	-- nobody else writes names or numbers on the King's page.
	if sender ~= ns.me and not Verified(sender, guild) then return end
	local list = {}
	for entry in names:gmatch("[^,]+") do
		local nm, g, st = entry:match("^([^:]+):([^:]*):([NO])$")
		nm, g = CleanName(nm), CleanGuild(g)
		if nm and g and #list < King.MAX_NAMES then list[#list + 1] = { name = nm, guild = g, status = st == "N" and "NONE" or "OTHER" } end
	end
	local cap = King.MAX_CHECKS
	inspect.reports[sender] = { guild = guild, ok = math.min(tonumber(ok) or 0, cap),
		none = math.min(tonumber(none) or 0, cap), other = math.min(tonumber(other) or 0, cap), names = list }
	Changed()
end

function King.HandleReport(dist, sender, text)
	if dist ~= "WHISPER" or not King.CanCommand() then return end
	King.ReceiveReport(sender, text)
end
ns.Comm.Handle("T3", function(...) King.HandleReport(...) end)

-- The violators the inspection found go on the King's own list, then the usual Wall of Shame.
-- The untabarded (Inspect.lua): the King's list, the army's only while he lets it see it.
--   T1~U~<id>~<guild>~1~<name>:<guild>,...   the list, repeated while it is on
--   T1~U~<id>~<guild>~0                      off: it leaves every screen
-- Only the King (not a Hand: "U" is not in HAND_MAY). Older versions ignore the kind.
King.UNTABARDED_EVERY = 300
local lastUntabardedSent = -math.huge

function King.SharingUntabarded() return ns.db and ns.db.kingUntabarded == true end

-- What the inspection's patrols reported joins his own list.
local function TakeReports()
	for _, r in pairs(inspect and inspect.reports or {}) do
		for _, v in ipairs(r.names) do ns.Inspect.AddReported(v.name, v.guild, v.status) end
	end
end

function King.SendUntabarded(force)
	if not King.IsKing() then return end
	local now = ns.Now()
	local on = King.SharingUntabarded()
	if not force and (not on or now - lastUntabardedSent < King.UNTABARDED_EVERY) then return end
	lastUntabardedSent = now
	local guild = GetGuildInfo("player") or ""
	local msg
	if on then
		TakeReports()
		local body = ns.Codec.EncodeShame(guild, 0, ns.Inspect.ShameList()):match("^S1~[^~]*~%d+~(.*)$") or ""
		msg = ("T1~U~%d~%s~1~%s"):format(NewId(), guild, body)
	else
		msg = ("T1~U~%d~%s~0"):format(NewId(), guild)
	end
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "untabarded") else ns.Comm.SendChunked(msg) end
end

function King.ToggleUntabarded()
	if King.Preview() then return ns.Print(L.THRONE_PREVIEW_NOTE) end
	if not King.IsKing() then return ns.Print(L.THRONE_ONLY_KING) end
	ns.db.kingUntabarded = not King.SharingUntabarded()
	ns.Print(King.SharingUntabarded() and L.UNTABARDED_ON or L.UNTABARDED_OFF)
	King.SendUntabarded(true)
	Changed()
end

local function OnUntabarded(sender, rest)
	if King.IsKing() then return end
	local on, body = tostring(rest or ""):match("^(%d)~?(.*)$")
	if on == "1" then
		local s = ns.Codec.DecodeShame("S1~Olympus~0~" .. body)
		if s then ns.Inspect.ShowShame({ by = ns.KingName(sender), list = s.list, t = ns.Now() }) end
	elseif on == "0" then
		ns.Inspect.ShowShame(nil)
	end
end

---------------------------------------------------------------------------
-- The King's Agenda
---------------------------------------------------------------------------

local function ZoneName()
	return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
end

local function Clean(s, n) return ns.Cut((tostring(s or ""):gsub("[~|\n]", " ")), n) end

-- "30 Raid on Crossroads": minutes first, then the title.
function King.ParseAgenda(input)
	local minutes, title = tostring(input or ""):match("^%s*(%d+)%s+(.-)%s*$")
	minutes = tonumber(minutes)
	if not minutes or minutes < 1 or minutes > 720 or title == "" then return nil end
	return minutes, Clean(title, 60)
end

function King.SetAgenda(input)
	local minutes, title = King.ParseAgenda(input)
	if not minutes then
		ns.Print(L.THRONE_AGENDA_USAGE)
		return false
	end
	local now = ns.Now()
	if not King.Preview() and now - lastAgendaSent < King.AGENDA_GAP then
		ns.Print(L.THRONE_WAIT:format(math.ceil(King.AGENDA_GAP - (now - lastAgendaSent))))
		return false
	end
	lastAgendaSent = now
	local mine = { id = NewId(), title = title, at = now + minutes * 60, zone = Clean(ZoneName(), 40), by = ns.me, mine = true, fired = {} }
	if King.Preview() then
		agenda = mine
		ns.Print(L.THRONE_PREVIEW_NOTE)
		return Changed() or true
	end
	if not King.CanCommand() then return false end
	agenda = mine
	King.SendAgenda()
	Warn(L.THRONE_AGENDA_SET:format(title, minutes, mine.zone))
	Changed()
	return true
end

function King.SendAgenda()
	if not agenda or not agenda.mine or King.Preview() then return end
	-- Seconds left, so a resend never moves the time (minutes rounded up did).
	local left = math.floor(agenda.at - ns.Now())
	if left < 30 then return end
	ns.Comm.Send("CHANNEL", ("T1~A~%d~%s~%d~%s~%s"):format(agenda.id, GetGuildInfo("player") or "", left, agenda.zone, agenda.title), "agenda")
end

function King.CancelAgenda()
	if not agenda then return end
	-- The King or a Hand cancels it for everyone, whoever set it (its setter's client stops
	-- repeating it when the cancel reaches it).
	if (agenda.mine or King.CanCommand()) and not King.Preview() then
		ns.Comm.Send("CHANNEL", ("T1~X~%d~%s"):format(agenda.id, GetGuildInfo("player") or ""), "agenda")
	end
	agenda = nil
	Changed()
end

function King.Agenda()
	if agenda and agenda.at < ns.Now() - 600 then agenda = nil end -- over for 10 minutes
	return agenda
end

local function OnAgenda(king, id, rest, guild)
	local seconds, zone, title = rest:match("^(%d+)~([^~]*)~(.*)$")
	seconds = tonumber(seconds)
	if not seconds or seconds < 30 or seconds > 720 * 60 or title == "" then return end
	local now = ns.Now()
	if agenda and agenda.id == id then
		-- A resend: keep our time unless it is really off (late login, clock drift).
		if math.abs((now + seconds) - agenda.at) > 60 then agenda.at = now + seconds end
		return Changed()
	end
	agenda = { id = id, title = Clean(title, 60), at = now + seconds, zone = Clean(zone, 40), by = king, fired = {} }
	-- A new agenda is a raid warning and a popup (the appointment: what, when, where), but
	-- not more than once a minute whatever arrives.
	if now - lastAgendaWarn >= King.AGENDA_GAP then
		lastAgendaWarn = now
		local minutes = math.ceil(seconds / 60)
		Warn(L.THRONE_AGENDA_SET:format(agenda.title, minutes, agenda.zone))
		-- The King by the army's name for him; a Hand by theirs (as OnSummon).
		local where = agenda.zone ~= "" and agenda.zone or "?"
		local text = King.FromKing(king, guild) and L.THRONE_AGENDA_POPUP:format(ns.KingName(king), agenda.title, minutes, where)
			or L.THRONE_AGENDA_POPUP_HAND:format(ns.DisplayName(king), agenda.title, minutes, where)
		ns.ShowDialog("OLYMPUS_AGENDA_CALL", text)
	end
	Changed()
end

StaticPopupDialogs["OLYMPUS_AGENDA_CALL"] = {
	text = "%s",
	button1 = OKAY or "OK",
	timeout = 120,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The King on the map: when he turns it on (Throne tab), his client sends where he is and
-- every addon shows a crown on the world map and the minimap. Off by default, and a button
-- away: his position is on stream.
--   T1~P~<id>~<guild>~<mapID>~<x 0-1000>~<y 0-1000>   where he is (every few seconds while moving)
--   T1~Q~<id>~<guild>                                  hidden again
---------------------------------------------------------------------------

King.LOCATION_EVERY = 5      -- seconds between sends while moving
King.LOCATION_STILL = 20     -- standing still, repeated this often (for late logins)
King.LOCATION_EXPIRE = 45    -- a crown with no news this long is removed

local kingAt                 -- where the King is, for everyone: { name, mapID, x, y, t }
local locationId = NewId()
local lastLocation = { t = -math.huge }
local Pins = ns.Pins()
local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local crowns                 -- { world, mini } pin frames, made on first use
local crownAt                -- where they are drawn now (drawn again only when he moved)

function King.SharingLocation() return ns.db.throneLocation == true end

local function SendLocation(force)
	if not King.SharingLocation() or not King.IsKing() then return end
	if IsInInstance and IsInInstance() then return end
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	local now = ns.Now()
	local moved = lastLocation.mapID ~= mapID or math.abs((lastLocation.x or 0) - x) > 0.003 or math.abs((lastLocation.y or 0) - y) > 0.003
	if not force and (now - lastLocation.t < King.LOCATION_EVERY or (not moved and now - lastLocation.t < King.LOCATION_STILL)) then return end
	lastLocation = { mapID = mapID, x = x, y = y, t = now }
	ns.Comm.Send("CHANNEL", ("T1~P~%d~%s~%d~%d~%d"):format(locationId, GetGuildInfo("player") or "", mapID,
		math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)), "kinglocation")
end

function King.ToggleLocation()
	if King.Preview() then return ns.Print(L.THRONE_PREVIEW_NOTE) end
	if not King.IsKing() then return end
	ns.db.throneLocation = not King.SharingLocation()
	if King.SharingLocation() then
		ns.Print(L.THRONE_LOCATION_SHOWN)
		-- His crown is his yes for his layer too (Layers.lua): the army asks to join him there.
		-- Both go out now (1.0.0: his layer waited for its next announcement, up to ten minutes).
		ns.Print(L.THRONE_LOCATION_LAYER)
		SendLocation(true)
		ns.Layers.AnnounceNow()
	else
		ns.Print(L.THRONE_LOCATION_HIDDEN)
		lastLocation = { t = -math.huge }
		ns.Comm.Send("CHANNEL", ("T1~Q~%d~%s"):format(locationId, GetGuildInfo("player") or ""), "kinglocation")
		-- His layer goes with it, at once, and his hello stops naming his zone (Layers.Sharing).
		ns.Layers.Withdraw()
		ns.Comm.Hello(true)
	end
	Changed()
end

local function CrownTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L.THRONE_LOCATION_PIN:format(kingAt and kingAt.name or "?"), 1, 0.82, 0)
	GameTooltip:Show()
end
local function Crown(size)
	local f = CreateFrame("Frame", nil, UIParent)
	f.olympus = true -- (ours: photo mode leaves it shown, UI.TogglePhoto)
	f:SetSize(size, size)
	f.icon = f:CreateTexture(nil, "OVERLAY")
	f.icon:SetTexture(ns.CROWN_ICON)
	f.icon:SetAllPoints()
	f:EnableMouse(true)
	f:SetScript("OnEnter", CrownTip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end
-- The world map's crown sits beside the zone circles, never over their numbers (1.0.0,
-- Map.Badge); the minimap's is a plain crown (no circles there).
local function WorldCrown()
	local f = ns.Map.Badge(20, false)
	ns.Map.SetBadge(f, ns.CROWN_ICON)
	f.badge:SetScript("OnEnter", CrownTip)
	f.badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

-- Draws (or removes) the crown on the world map and the minimap. The world map's only with
-- mouse and keyboard (ns.WorldMapIcons); drawn again when that changes, even where he stands still.
function King.RefreshCrown()
	if not Pins then return end
	local world = ns.WorldMapIcons(Pins, King)
	if kingAt and ns.Now() - kingAt.t > King.LOCATION_EXPIRE then kingAt = nil end
	if not kingAt then
		if crowns and crownAt then
			if world then Pins:RemoveWorldMapIcon(King, crowns.world) end
			Pins:RemoveMinimapIcon(King, crowns.mini)
			crowns.world:Hide()
			crowns.mini:Hide()
		end
		crownAt = nil
		return
	end
	if crownAt and crownAt.mapID == kingAt.mapID and crownAt.x == kingAt.x and crownAt.y == kingAt.y and crownAt.world == world then return end
	crowns = crowns or { world = WorldCrown(), mini = Crown(16) }
	-- Taken off before it is put back: the map library makes a new map pin on every add.
	if crownAt then
		if world then Pins:RemoveWorldMapIcon(King, crowns.world) end
		Pins:RemoveMinimapIcon(King, crowns.mini)
	end
	crownAt = { mapID = kingAt.mapID, x = kingAt.x, y = kingAt.y, world = world }
	if world then Pins:AddWorldMapIconMap(King, crowns.world, kingAt.mapID, kingAt.x, kingAt.y, SHOW_FLAG) end
	Pins:AddMinimapIconMap(King, crowns.mini, kingAt.mapID, kingAt.x, kingAt.y, true, true)
end

local function OnLocation(king, rest)
	local mapID, x, y = rest:match("^(%d+)~(%d+)~(%d+)$")
	mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
	if not mapID or x > 1000 or y > 1000 then return end
	kingAt = { from = ns.FullName(king), name = ns.KingName(king), mapID = mapID, x = x / 1000, y = y / 1000, t = ns.Now() }
	ns.SafeCall("king crown", King.RefreshCrown)
	Changed()
end

-- Where the King is, while he shares it: { name, mapID, x, y, t } or nil.
function King.Location()
	if kingAt and ns.Now() - kingAt.t > King.LOCATION_EXPIRE then return nil end
	return kingAt
end

function King.HandleCommand(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local kind, id, guild, rest = text:match("^T1~(%a)~(%d+)~([^~]*)~?(.*)$")
	if not kind then return end
	if not King.Authorized(kind, sender, guild) then
		-- Positions come every few seconds: not logged.
		if kind ~= "P" then
			ns.Log("throne %s from %s ignored: not the King of %s nor his Hand%s", kind, sender, tostring(guild),
				ns.KingCharacter() and "" or " (no King named on this side: nobody commands)")
		end
		return
	end
	id = tonumber(id)
	-- The King's own client takes his Hands' news (the agenda, the gates, a cancel), not
	-- their calls to the army: no roll call popup, patrol or poll window for him.
	if King.IsKing() and (kind == "S" or kind == "I" or kind == "V") and not KingSender(sender, guild) then return end
	if kind == "S" then OnSummon(sender, id, guild)
	elseif kind == "H" then OnHands(sender, id, rest, guild)
	elseif kinds[kind] then kinds[kind](sender, id, rest, guild)
	elseif kind == "I" then OnInspect(sender, id)
	elseif kind == "U" then OnUntabarded(sender, rest)
	elseif kind == "A" then OnAgenda(sender, id, rest, guild)
	elseif kind == "P" then OnLocation(sender, rest)
	elseif kind == "Q" then
		-- Only whoever put the crown there takes it off.
		if kingAt and kingAt.from ~= ns.FullName(sender) then return end
		kingAt = nil
		ns.SafeCall("king crown", King.RefreshCrown)
		Changed()
	elseif kind == "X" and agenda and agenda.id == id then
		agenda = nil
		Changed()
	end
end
ns.Comm.Handle("T1", function(...) King.HandleCommand(...) end)

ns.On("LOGIN", function()
	-- The King's position, while he shares it; everyone's crown expires on its own.
	ns.Every(King.LOCATION_EVERY, "king location", function()
		SendLocation()
		King.RefreshCrown()
	end)
	-- The Hands from the last session, with their date; the King and his Steward repeat them for
	-- late logins (HANDS_EVERY). A list saved before 1.0.0 had no date: the oldest one (DATED).
	King.LoadHands()
	ns.Every(60, "king hands", function()
		King.SendHands()
		King.SendUntabarded()
	end)
	-- The guild is not always known at login yet: checked when the note is due.
	ns.After(20, "king location note", function()
		if King.SharingLocation() and King.IsKing() then ns.Print(L.THRONE_LOCATION_SHOWN) end
		-- A King no update has named yet (the Horde's): his commands reach nobody (KingSender).
		if King.IsKing() and not ns.KingCharacter() then ns.Print(L.THRONE_NOT_NAMED) end
	end)
	ns.Every(60, "agenda", function()
		local a = King.Agenda()
		if not a then return end
		local left = a.at - ns.Now()
		-- Reminders for everyone, and the King's client repeats it for late logins.
		a.fired = a.fired or {}
		for _, mark in ipairs({ 600, 60 }) do
			if left <= mark and left > 0 and not a.fired[mark] then
				a.fired[mark] = true
				Warn(L.THRONE_AGENDA_SOON:format(a.title, math.max(1, math.ceil(left / 60)), a.zone))
			end
		end
		if a.mine and (not a.sentAt or ns.Now() - a.sentAt >= King.AGENDA_RESEND) then
			a.sentAt = ns.Now()
			King.SendAgenda()
		end
		Changed()
	end)
end)

StaticPopupDialogs["OLYMPUS_KING_AGENDA"] = {
	text = L.THRONE_AGENDA_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 260,
	maxLetters = 70,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("30 "); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("agenda", King.SetAgenda, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("agenda", King.SetAgenda, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function King.AgendaPrompt()
	ns.ShowDialog("OLYMPUS_KING_AGENDA")
	Changed()
end

---------------------------------------------------------------------------
-- What the tab shows (parchment, dark text: line.font)
---------------------------------------------------------------------------

local INK, TITLE = "QuestFont", "QuestTitleFont"

local function Line(text, font, extra)
	local l = { text = text, font = font or INK }
	for k, v in pairs(extra or {}) do l[k] = v end
	return l
end

-- A paragraph in rows short enough for the page (rows are one line each): split at spaces,
-- about `width` letters a row. The last row takes `extra` (gapAfter...).
King.WRAP = 44
local function Para(lines, text, font, extra)
	local row, rows = "", {}
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > King.WRAP then
			rows[#rows + 1] = row
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then rows[#rows + 1] = row end
	for i, r in ipairs(rows) do lines[#lines + 1] = Line(r, font, i == #rows and extra or nil) end
	return lines
end
King.Para = Para

---------------------------------------------------------------------------
-- Where the King's calls show: the roll call in the Realm tab (next to the Lords it calls),
-- the Royal Inspection in the Tabards tab. Plain rows (not the parchment), for the King and
-- his Hands (and the author's Asmon's view).
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t "
local NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13|t "
local WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t "
King.ROLL_SHOWN = 15 * 60    -- the marks next to the Lords stay this long after a roll call

function King.CanCall() return King.CanCommand() or King.Preview() end

-- Who answered the roll call: present and busy (confirmed Lords and Captains), the others
-- the census can't confirm (counted), and the Lords online who stayed silent.
local function RollCall()
	if not summon then return nil end
	local present, busy, silent, others = {}, {}, {}, 0
	for name, a in pairs(summon.answers) do
		local row = ("%s <%s>"):format(ns.DisplayName(name), a.guild)
		if a.word == "P" then present[#present + 1] = row else busy[#busy + 1] = row end
	end
	for _ in pairs(summon.others or {}) do others = others + 1 end
	for _, lord in ipairs(LordsOnline()) do
		local answered = summon.answers[lord.name] or (summon.others and summon.others[lord.name])
		if not answered and lord.name ~= ns.me then silent[#silent + 1] = ("%s <%s>"):format(ns.DisplayName(lord.name), lord.guild) end
	end
	table.sort(present); table.sort(busy); table.sort(silent)
	return present, busy, silent, others
end

-- The mark next to a Lord or Captain in the Realm tree while a roll call is fresh: answered
-- present, busy, or (online) not answered yet.
function King.RollCallMark(name, online)
	if not summon or not King.CanCall() or ns.Now() - summon.t > King.ROLL_SHOWN then return "" end
	local full = ns.FullName(name)
	if full == ns.me then return "" end -- who called
	local a = summon.answers[full]
	if a then return a.word == "P" and READY or NOT_READY end
	-- An answer the census could not confirm (counted apart) is still an answer: the mark only.
	local o = summon.others and summon.others[full]
	if o then return o == "P" and READY or NOT_READY end
	return online and WAITING or ""
end

local rollOpen = false
function King.RollCallLines()
	if not King.CanCall() then return {} end
	local present, busy, silent, others = RollCall()
	local lines = {
		{
			header = true, text = READY .. L.THRONE_SUMMON_TITLE,
			right = present and Grey(L.ROLL_COUNTS:format(#present, #busy, #silent) .. "  " .. ns.Ago(summon.t)) or Gold(L.ROLL_CALL),
			-- A call while there is none; once called, "call again" below (the results stay).
			onClick = not present and function() King.Summon() end or nil,
			tooltip = function(tt)
				tt:AddLine(L.THRONE_SUMMON_TITLE, 1, 0.82, 0)
				tt:AddLine(L.THRONE_SUMMON_TIP, 1, 1, 1, true)
				tt:AddLine(L.ROLL_CLICK, 0.6, 0.6, 0.6, true)
			end,
		},
	}
	if present then
		lines[#lines + 1] = { indent = 1, text = Gold((rollOpen and "[-] " or "[+] ") .. L.ROLL_WHO),
			onClick = function()
				rollOpen = not rollOpen
				if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
			end }
		if rollOpen then
			for _, group in ipairs({ { L.THRONE_PRESENT_N, present, Green }, { L.THRONE_BUSY_N, busy, Grey }, { L.THRONE_SILENT_N, silent, Grey } }) do
				lines[#lines + 1] = { indent = 1, text = group[3](group[1]:format(#group[2])) }
				for _, row in ipairs(group[2]) do lines[#lines + 1] = { indent = 2, text = row } end
			end
			if others > 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.THRONE_UNCONFIRMED:format(others)) } end
		end
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.ROLL_AGAIN), onClick = function() King.Summon() end }
	end
	lines[#lines].gapAfter = true
	return lines
end

-- The Royal Inspection on top of the Tabards tab: call one, then what the patrols reported.
function King.InspectionLines()
	if not King.CanCall() then return {} end
	local lines = {}
	local ok, bad, reporters, byGuild, names = 0, 0, 0, {}, {}
	for _, r in pairs(inspect and inspect.reports or {}) do
		reporters = reporters + 1
		ok, bad = ok + r.ok, bad + r.none + r.other
		local g = byGuild[r.guild] or { ok = 0, bad = 0 }
		g.ok, g.bad = g.ok + r.ok, g.bad + r.none + r.other
		byGuild[r.guild] = g
		for _, v in ipairs(r.names) do names[#names + 1] = v end
	end
	local total = ok + bad
	local pct = total > 0 and math.floor(ok * 100 / total + 0.5) or 0
	lines[1] = {
		header = true, text = "|TInterface\\Icons\\INV_Shirt_GuildTabard_01:14:14|t " .. L.THRONE_INSPECT_TITLE,
		right = inspect and Grey(L.INSPECTION_SHORT:format(pct, total) .. "  " .. ns.Ago(inspect.t)) or Gold(L.INSPECTION_CALL),
		onClick = not inspect and function() King.Inspect() end or nil,
		tooltip = function(tt)
			tt:AddLine(L.THRONE_INSPECT_TITLE, 1, 0.82, 0)
			tt:AddLine(L.THRONE_INSPECT_TIP, 1, 1, 1, true)
		end,
	}
	if inspect then
		local left = inspect.t + King.INSPECT_TIME + 10 - ns.Now()
		if left > 0 then lines[#lines + 1] = { indent = 1, text = Gold(L.THRONE_INSPECT_RUNNING:format(math.ceil(left))) } end
		lines[#lines + 1] = { indent = 1, text = L.THRONE_INSPECT_SUMMARY:format(reporters, total, pct) }
		local guilds = {}
		for guild, g in pairs(byGuild) do guilds[#guilds + 1] = { name = guild, ok = g.ok, n = g.ok + g.bad } end
		table.sort(guilds, function(a, b) return a.n > b.n end)
		for _, g in ipairs(guilds) do
			lines[#lines + 1] = { indent = 2, text = Green("<" .. g.name .. ">"),
				right = ("%d%%  (%d/%d)"):format(g.n > 0 and math.floor(g.ok * 100 / g.n + 0.5) or 0, g.ok, g.n) }
		end
		if #names > 0 then
			lines[#lines + 1] = { indent = 1, text = "|cffff4040" .. L.THRONE_VIOLATORS:format(#names) .. "|r" }
			for i, v in ipairs(names) do
				if i > 10 then
					lines[#lines + 1] = { indent = 2, text = Grey(L.AND_MORE:format(#names - 10)) }
					break
				end
				lines[#lines + 1] = { indent = 2, text = ("%s  %s"):format(v.name, Grey("<" .. v.guild .. ">")),
					right = v.status == "NONE" and L.TABARD_NONE or L.TABARD_OTHER }
			end
		end
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.INSPECTION_AGAIN), onClick = function() King.Inspect() end }
	end
	-- The untabarded list is the King's: he alone lets the army see it (not a Hand), and can
	-- take it back at any time, inspection or not.
	if King.IsKing() or King.Preview() then
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. (King.SharingUntabarded() and L.UNTABARDED_STOP or L.UNTABARDED_SHARE)),
			onClick = function() King.ToggleUntabarded() end,
			tooltip = function(tt) tt:AddLine(L.UNTABARDED_TIP, 1, 1, 1, true) end }
	end
	lines[#lines].gapAfter = true
	return lines
end

local function HandsLines()
	local steward = King.IsSteward()
	local lines = Para({ Line(L.HANDS_TITLE, TITLE) }, steward and L.HANDS_HINT_STEWARD or L.HANDS_HINT, INK, { gapAfter = true })
	if King.SetsLists() or King.Preview() then
		local list = King.Hands()
		lines[#lines + 1] = Line("+ " .. L.HANDS_ADD, TITLE, { onClick = function() ns.ShowDialog("OLYMPUS_KING_HAND") end })
		for _, name in ipairs(list) do
			lines[#lines + 1] = Line(ns.DisplayName(name), INK, { indent = 1, key = name,
				onClick = function() ns.ShowDialog("OLYMPUS_KING_UNHAND", ns.DisplayName(name), nil, name) end,
				tooltip = function(tt) tt:AddLine(ns.DisplayName(name), 1, 0.82, 0); tt:AddLine(L.HANDS_CLICK_REMOVE, 1, 1, 1, true) end })
		end
		if #list == 0 then lines[#lines + 1] = Line(L.HANDS_NONE, INK, { indent = 1 }) end
		lines[#lines].gapAfter = true
		-- The army holds a newer list than this one (his client was away when it was set): his is
		-- held back until he hears it or names the Hands again (1.0.0).
		local back, byKing = King.HandsHeldBack()
		if back == "newer" then
			Para(lines, L.HANDS_HELD_BACK:format(byKing and L.HANDS_BY_KING or L.HANDS_BY_STEWARD), TITLE, { gapAfter = true })
		end
		Para(lines, steward and L.HANDS_NOTE_STEWARD or L.HANDS_NOTE, INK)
	end
	return lines
end

King.Line, King.INK, King.TITLE = Line, INK, TITLE

local function Go(mode) return function() King.Show(mode) end end

-- The Throne Room: what is the King's alone. Each tool lives where it belongs (the agenda and
-- the court on the buttons below, the roll call in the Realm, the inspection in the Tabards,
-- Vox Populi and the treasury on their own tabs): here, the court's queue while it is open and
-- the treasury. A Hand's: where their tools are. His Steward's (1.0.0): the King's, with what is
-- his to do in the King's name (he holds no court: no queue).
local function HomeLines()
	local mine = King.IsKing() or King.Preview()
	local steward = not mine and King.IsSteward()
	local title = (mine or steward) and L.THRONE_ROOM or L.THRONE_ROOM_HAND:format(ns.KingName(handsKing or ns.KingCharacter()))
	local lines = { Line(title, TITLE, { gapAfter = true }) }
	if steward then
		Para(lines, L.THRONE_STEWARD_HINT, INK, { gapAfter = true })
	elseif not mine then
		return Para(lines, L.THRONE_HAND_HINT, INK)
	end
	for _, l in ipairs(ns.Court and ns.Court.HomeLines and ns.Court.HomeLines() or {}) do lines[#lines + 1] = l end
	if #lines > 1 then lines[#lines].gapAfter = true end
	for _, l in ipairs(ns.Treasury and ns.Treasury.ThroneLines and ns.Treasury.ThroneLines() or {}) do lines[#lines + 1] = l end
	return lines
end

-- The King's own pages (and his Steward's): a Hand's Throne Room has no link to them.
King.KING_PAGES = { hands = true }

-- For Views.Build("throne"): lines, detail title, detail text.
-- The Throne opens on the Throne Room (the King's: his court's queue while it is open, the
-- treasury; a Hand's: where their tools are), and holding court takes him there. (1.0.0: no
-- letter before it any more.) His Steward's says on top, on every page, that he acts for the King.
function King.Build(s)
	local lines, home
	if not King.mode then King.mode = "home" end
	local mode = King.mode
	if King.KING_PAGES[mode] and not (King.SetsLists() or King.Preview()) then mode = "home" end
	if mode == "hands" then lines = HandsLines()
	else lines, home = HomeLines(), true end
	-- Every other page leads back to the Throne Room.
	if not home then table.insert(lines, 1, Line("< " .. L.THRONE_ROOM, INK, { onClick = Go("home"), gapAfter = true })) end
	-- While the army sees him on the map, the page says so on top, whatever it shows.
	if King.SharingLocation() and King.IsKing() then
		table.insert(lines, 1, Line("|T" .. ns.CROWN_ICON .. ":0|t " .. L.THRONE_LOCATION_LIVE, TITLE, { gapAfter = true }))
	end
	local steward = King.IsSteward()
	if steward then table.insert(lines, 1, Line("|T" .. ns.CROWN_ICON .. ":0|t " .. L.STEWARD_ACTING, TITLE, { gapAfter = true })) end
	local detail = steward and L.THRONE_YOU_ARE_STEWARD:format(ns.KingName(ns.KingCharacter()))
		or King.IsHand() and L.THRONE_YOU_ARE_HAND:format(ns.KingName(handsKing or ns.KingCharacter())) or L.THRONE_YOU_ARE_KING
	return lines, L.TAB_THRONE, detail
end

function King.Show(mode)
	King.mode = mode
	Changed()
end

-- For tests.
function King.CancelAgendaButton()
	if not King.Agenda() then return ns.Print(L.THRONE_AGENDA_NONE) end
	King.CancelAgenda()
	ns.Print(L.THRONE_AGENDA_CANCELLED)
end

function King.State() return { summon = summon, inspect = inspect, agenda = agenda, inspecting = inspecting } end

-- /oly status (1.0.0): the King's Steward as this client knows him (the signed titles list), and
-- the list of Hands it holds: whose word it was and whether it still lasts here.
function King.StewardStatusLine()
	local who
	if King.IsSteward() then
		who = "you, acting for the King"
	elseif not ns.KingCharacter() then
		who = "none (no King named on this side)"
	elseif not ns.CouncilTitles() then
		who = "none known (no signed titles list here yet)"
	else
		local shown = {}
		for i, n in ipairs(ns.Stewards()) do shown[i] = StewardLabel(n) end
		who = #shown > 0 and table.concat(shown, ", ") or "none named"
	end
	local held
	if handsDate == 0 then held = "none"
	else
		local state
		if King.SetsLists() then
			local back = King.HandsHeldBack()
			state = back == "newer" and "held back by this client: the army holds a newer list"
				or back == "confirming" and "held back until confirmed the newest"
				or "repeated by this client"
		elseif handsAt == -math.huge then state = "kept from the last session, not heard yet"
		else
			state = ns.Now() - handsAt <= King.HANDS_FRESH and ("heard " .. ns.Ago(handsAt)) or "lapsed here"
		end
		held = ("%d, set by %s, %s"):format(#myHands, handsByKing and "the King" or "a Steward", state)
	end
	return ("%s  |  Hands: %s"):format(who, held)
end

-- The author's Workshop: Asmon's view on or off (the Throne, Vox Populi, the King's calls in
-- the Realm and the Tabards), to see and try them. Nothing the view does reaches anyone.
function King.SetDevView(on)
	ns.db.devKingView = on and true or false
	-- The preview's treasury switches and keepers were its own: gone with it.
	if not on then ns.db.previewTreasuryFlags, ns.db.previewTreasuryKeepers = nil, nil end
	ns.Print(on and L.DEV_KING_VIEW_NOW_ON or L.DEV_KING_VIEW_NOW_OFF)
	ns.Fire("DATA_CHANGED")
	Changed()
end
function King.Reset()
	summon, inspect, agenda, inspecting, kingAt, crownAt = nil, nil, nil, nil, nil, nil
	wipe(myHands); wipe(hands); wipe(previewHands)
	handsDate, handsByKing, handsFrom, handsAt, handsKing, undatedText = 0, false, nil, -math.huge, nil, nil
	lastHandsSent, lastHandsAnswer, handsSendPending = -math.huge, -math.huge, false
	handsSure, handsSet, heardNewer, heardNewerByKing, heldBackAt, confirmPending = false, false, 0, false, -math.huge, false
	lastHintDrawn, hintPending, hintHeard = -math.huge, nil, nil
	lastLocation = { t = -math.huge }
	lastSummonSeen, lastInspectSeen, lastSummonSent, lastInspectSent = -math.huge, -math.huge, -math.huge, -math.huge
	lastUntabardedSent = -math.huge
	lastAgendaSent, lastAgendaWarn, changePending = -math.huge, -math.huge, false
	King.mode, rollOpen = nil, false
end
