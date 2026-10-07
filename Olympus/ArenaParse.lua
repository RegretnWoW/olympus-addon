local ADDON, ns = ...

-- The Blood Arena's readers (1.2): duel results and rolls from the game's system messages
-- (patterns built from the client's own global strings, so every language reads), and the
-- fight's facts from combat log events or UNIT_COMBAT. Pure functions over what the caller
-- passes in: no events, no messages, no saved data. The only globals read are the client's
-- format strings (at call time, so a test or a language switch needs no reload) and
-- issecretvalue.
--
-- The game's lines:
--   ArenaParse.EN[key]                        the English format of DUEL_WINNER_KNOCKOUT,
--                                             DUEL_WINNER_RETREAT and RANDOM_ROLL_RESULT (the
--                                             enUS client's; Forever's own is an in-game check),
--                                             the reader's fallback when the client has none
--   ArenaParse.Format(key, given)       -> fmt, fallback
--       the format a reader uses: `given` (a non-empty string), else the client's _G[key],
--       else EN[key] with fallback = true, so a caller can refuse to start (Farkle's spec: a
--       roll it can't read in the player's language must not look like a missed one)
--   ArenaParse.Pattern(fmt)             -> pattern, order | nil
--       a format string ("%s", "%d", "%%", and the positional "%1$s" / "%2$d" other languages
--       use) as an anchored Lua pattern; order[i] is the argument the i-th capture holds.
--       nil for anything else in it (a width, "%f", a lone "%", plain "%s" mixed with positional
--       "%2$s", whose numbering in the client's format is unchecked): read wrongly is worse than not
--   ArenaParse.Scan(fmt, text)          -> args | nil, "secret"
--       the arguments of `text` written with `fmt`, by their number (args[1] is the format's
--       first argument wherever the language puts it); "%d" ones as numbers
--   ArenaParse.DuelResult(msg, knockout, retreat) -> winner, loser, method | nil, "secret"
--       the duel's line: method "knockout" or "fled"; names as the line writes them (with
--       "-Realm" when it has one: the caller compares them the way it compares senders).
--       Forever's names are a first name and a surname: "First Surname" is read whole, and a
--       "First-Surname" form comes back as written, for the caller's ns.Normal.
--       `knockout` and `retreat` are optional, each on its own (Format). nil when both formats
--       read the line: a language whose one line holds the other's words can't say which it was
--   ArenaParse.Roll(msg, fmt)           -> name, value, low, high | nil, "secret"
--       a /roll line; the three numbers are integers from 0 to 2^31 - 1, low <= value <= high
--   The second result "secret" says the line was a secret (a chat lockdown), not one that didn't
--   match: the arena counts those, and Farkle says "you can't see the dice here".
--
-- A fight's facts, from combat log events or UNIT_COMBAT the caller hands over as plain values:
--   ArenaParse.PropsOn(mode, liveProps, kind) -> on, trial
--       whether a prop built on a fight's facts is offered (the design): `kind` "DU"
--       (duration), "FB" (first blood) or "BH" (biggest hit) asks for that one; nil asks whether
--       any is, which is when the fights module builds and feeds a fight at all. Always on in
--       mode "T" (rehearsals and test builds, where they are a trial: trial = true), in "L" only
--       with LIVE_PROPS on, and never in any other mode. `liveProps` is Markets.LIVE_PROPS as the
--       caller has it: true for all three, or a table per kind ({ DU = true, FB = true, BH = true },
--       the design: DU rests on UnitAffectingCombat, FB and BH on readable amounts, so
--       the checks may pass apart). Only exactly true switches one on: a stray value in saved data
--       does not. Any other `kind` is never on, not even in "T". The markets ask before they take
--       a DU, FB or BH.
--   ArenaParse.New(aGUID, bGUID, from)  -> fight | nil
--       the two fighters; `from` (optional) is the window's start (the bell): nothing before
--       it counts. nil when the GUIDs are missing or the same
--   fight:Own(guid, ownerGUID)          -> true | nil
--       a fighter's pet, totem or guardian: his side, never a third party. (Summons a fighter
--       makes while the fight is fed are learnt from SPELL_SUMMON by themselves; a pet out before
--       that has to be named here, e.g. from UnitGUID(token .. "pet"). Named late, what it did
--       leaves the third parties, except past MAX_OUTSIDE, where only a time is kept, and its hits
--       from before stay out of its side's facts.) nil when `ownerGUID` is not a fighter, `guid`
--       is one, the other fighter owns it already, or its owner has MAX_OWNED already
--   fight:Feed(timestamp, subevent, sourceGUID, destGUID, amount, critical, spellId, auraType)
--                                       -> kind | nil, "feed"
--       one combat log event (nil, "feed" once the fight has taken Wound's: one feed per fight,
--       below). auraType is the combat log's "BUFF" or "DEBUFF" on the aura subevents (optional:
--       without it an aura is never hostile). The kind it counted as:
--         "hit"      damage above 0 by one fighter on the other
--         "strike"   any other hostile act between them: a miss, damage absorbed whole, an
--                    interrupt, a drain, a DEBUFF (Sap, Cheap Shot, Polymorph, Fear)
--         "pet"      a hit or strike on a fighter by the other one's pet, totem or guardian: only
--                    in the side facts
--         "outside"  a third party harming or healing a fighter (damage, a miss, a heal, a
--                    DEBUFF): interference
--         "touch"    a third party's buff, energize or dispel on a fighter, or an aura of no
--                    given type: listed, not interference (the arbiter holds both fighters in his
--                    party, so his party-wide auras land on them every fight)
--         "summon"   a fighter's new pet or totem
--         nil        nothing (help between the fighters, a pet on its own master, an event that
--                    touches neither fighter)
--   fight:Wound(timestamp, victimGUID, event, flagText, amount) -> kind | nil, "secret" | nil, "feed"
--       one UNIT_COMBAT on a fighter's unit token, in the event's own order, with the token's
--       UnitGUID and GetTime() (the combat log is restricted on this client, so this is the
--       props' planned source: the design). UNIT_COMBAT names the unit hit and
--       never who hit it, so it counts for the other fighter's side, in the side facts only:
--       never the strict ones, never interference (a bystander's hit, or one the victim deals
--       himself, reads the same; the arbiter judges those). The kind:
--         "wound"    event "WOUND" with an amount above 0: the other side's hit (flagText
--                    "CRITICAL" makes it a critical)
--         "strike"   an attack on him that did no damage: "WOUND" with none (absorbed whole),
--                    MISS, DODGE, PARRY, BLOCK, BLOCK_REDUCED, RESIST, IMMUNE, ABSORB, DEFLECT,
--                    REFLECT, EVADE, or INTERRUPT (his cast cut short)
--         nil        HEAL, ENERGIZE or any other event, a GUID that is no fighter's, a time
--                    before the bell
--         nil, "secret"  a value the facts need is a secret, in this order: the GUID; the event
--                    of a fighter's; the flagText or amount of his WOUND. None of it is read, and
--                    the facts keep the time as `secret`. A secret anywhere else (a bystander's
--                    token, a HEAL's amount, a MISS's flagText) is never needed, so it is nil
--                    or the kind as usual, and the facts stay whole
--         nil, "feed"    the fight has taken Feed's events (one feed per fight, below)
--       The same wound reported again at the same time (party1 and target are both him: one
--       frame's events come in a row) is one wound: it gives its kind and changes nothing. A
--       WOUND is the same when its flagText and amount are too, any other event when its name is.
--   fight:Finish(resultTime)            -> facts | nil
--       closes the fight at the result (nothing fed later counts; calling again gives the same
--       facts); nil, and still open, when resultTime is not a number or comes before `from`
--   (ArenaParse.Feed, .Own, .Wound and .Finish are the same functions, for
--   ArenaParse.Feed(fight, ...).)
--   ArenaParse.FIGHT_EVENTS[subevent]   true for the subevents Feed reads, so a caller can skip
--                                       the rest before building a tuple
--
-- The facts (every event in the window [from, resultTime], one clock for all of them):
--   { a, b, from, result,
--     feed       = "log" | "unit" | nil                    Feed's, Wound's, or none counted
--     first      = { guid, side, t, subevent, spellId }   who struck first (a miss is a strike)
--     firstBlood = hit                                     the first damage above 0; on the same
--                                                          time the one fed first...
--     firstBloodTie = true                                 ...and when the other side's came at that
--                                                          very time, this says so: which came
--                                                          first can't be told (GetTime() has a
--                                                          frame's resolution, so both opening hits
--                                                          can share one), and a prop on it is void
--     best       = { [aGUID] = hit, [bGUID] = hit }       each fighter's biggest hit (absent: none)
--     biggest    = hit                                     the bigger of the two; nil on a tie...
--     tie        = true                                    ...which says so (a prop on it is void)
--     duration   = result - first.t                        nil without a strike; not rounded
--     side       = { first, firstBlood, firstBloodTie, best, biggest, tie, duration }
--                  the same with each fighter's pets, totems and guardians counted as him
--     interfered = true | false            a third party harmed or healed one ("outside")
--     outsiders  = { { guid, dest, t, subevent, spellId }, ... }  each one's first such act, by time
--     touched    = { ... }                 the same for "touch" (a shield or a Blessing from a
--                                          bystander is one: the arbiter reads the list)
--     touchedMore = true                   more third parties touched one than the list holds
--     late       = n                       events fed that came after the result, left out: many,
--                                          with no first, is a clock mixed up
--     overflow   = true                    events past MAX_HITS were not kept: biggest and late
--                                          may be wrong, so a prop on the biggest is void
--     secret     = t                       the time of the earliest wound in the window that could
--   }                                      not be read (Wound). Nothing before it is missing, so a
--                                          prop settled before it stands and the rest are void:
--                                          first blood when side.firstBlood.t < secret (at that
--                                          very time the unread one may have come first); the
--                                          first strike's time, and the duration from it, when
--                                          side.first.t <= secret (its side only when <); the
--                                          biggest hit never, since every wound is its candidate
--   (a hit is { guid, side, t, amount, critical, spellId, subevent }: guid dealt it, for side;
--   a wound's hit and strike have no guid and no spellId, and the UNIT_COMBAT event as subevent)
--
-- Two views, and the markets choose. The top-level facts are strict: only the two fighters' own
-- GUIDs (a pet's hit is neither the first nor the biggest). `side` counts each fighter's pets as
-- him, which is what the victim's wounds show (UNIT_COMBAT can't tell a pet from its master, and
-- the markets spec settles first blood and biggest hit by side); Wound feeds that view alone.
-- Events with no source (the environment) or on oneself count for nothing, and a pet the caller
-- never named is a third party.
-- One feed per fight: the first of Feed and Wound to count an event (or Wound's first secret) is
-- the fight's, and the other gives nil, "feed" from then on. The two don't mix: the combat log's
-- timestamps and GetTime() are different clocks, and Feed leaves out a third party's hit and a
-- fighter's own, which Wound can't tell from the other fighter's. A caller that wants both (the
-- props from Wound, and the arbiter's interference hint from a readable log, the design)
-- builds two fights.
-- `duration` runs from the first strike. It is not the duration market's value until the spec
-- picks one: the arena spec counts a round from the bell (result - from, which the caller has),
-- the markets spec from combat or the first wound.

local ArenaParse = {}
ns.ArenaParse = ArenaParse

ArenaParse.MAX_HITS = 5000     -- hits kept for the biggest, and event times for `late` (a long duel has hundreds)
ArenaParse.MAX_OUTSIDE = 100   -- third parties listed, in each list (past it, still counted as interference)
ArenaParse.MAX_OWNED = 1000    -- pets, totems and guardians known per fighter (every totem is a new GUID)

ArenaParse.EN = {
	DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel",
	DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel",
	RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)",
}

---------------------------------------------------------------------------
-- Format strings as patterns
---------------------------------------------------------------------------

-- A system line in a chat lockdown (an encounter, a PvP match) is a secret: no addon may read
-- it, and any string operation on it fails. It is checked before anything else touches it.
local function Secret(v)
	local secret = _G.issecretvalue
	return type(secret) == "function" and secret(v) and true or false
end

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
local CAPTURE = { s = "(.+)", d = "(%d+)" }

-- "%2$s has fled from %1$s in a duel" -> { pattern = "^(.+) has fled from (.+) in a duel$",
-- order = { 2, 1 }, kinds = { "s", "s" } }. A format is all plain ("%s") or all positional
-- ("%1$s"): how the client's format numbers a plain one among positional ones is unchecked (C
-- leaves it undefined), so a mix is no format of ours.
local function Compile(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local parts, order, kinds, auto, positional, i, n = { "^" }, {}, {}, 0, false, 1, #fmt
	while i <= n do
		local at = fmt:find("%", i, true)
		if not at then
			parts[#parts + 1] = (fmt:sub(i):gsub(MAGIC, "%%%0"))
			break
		end
		parts[#parts + 1] = (fmt:sub(i, at - 1):gsub(MAGIC, "%%%0"))
		local pos, kind, after = fmt:match("^(%d+)%$([sd])()", at + 1)
		if not pos then kind, after = fmt:match("^([sd%%])()", at + 1) end
		if not kind then return nil end
		if kind == "%" then
			parts[#parts + 1] = "%%"
		else
			local arg = pos and tonumber(pos)
			if arg then
				positional = true
			else
				auto = auto + 1
				arg = auto
			end
			-- Lua keeps 32 captures; one argument read as a name here and a number there is no format of ours
			if (positional and auto > 0) or arg < 1 or #order >= 32 or (kinds[arg] and kinds[arg] ~= kind) then return nil end
			order[#order + 1], kinds[arg] = arg, kind
			parts[#parts + 1] = CAPTURE[kind]
		end
		i = after
	end
	parts[#parts + 1] = "$"
	return { pattern = table.concat(parts), order = order, kinds = kinds }
end

-- Compiled once per format string, whichever it is: a language switch (or a test) gives
-- another string, so nothing stale is ever used. A handful of formats in the game; the cap only
-- keeps a caller passing many from growing it.
local compiled, cached = {}, 0
local function Compiled(fmt)
	if type(fmt) ~= "string" then return nil end
	local c = compiled[fmt]
	if c == nil then
		if cached >= 32 then compiled, cached = {}, 0 end
		c = Compile(fmt) or false
		compiled[fmt], cached = c, cached + 1
	end
	return c or nil
end

function ArenaParse.Format(key, given)
	if type(given) == "string" and given ~= "" then return given, false end
	local f = type(key) == "string" and _G[key] -- gp:lookups (the client's own format string)
	if type(f) == "string" and f ~= "" then return f, false end
	return ArenaParse.EN[key], true
end

function ArenaParse.Pattern(fmt)
	local c = Compiled(fmt)
	if not c then return nil end
	local order = {}
	for i, arg in ipairs(c.order) do order[i] = arg end
	return c.pattern, order
end

function ArenaParse.Scan(fmt, text)
	if Secret(text) then return nil, "secret" end
	if type(text) ~= "string" then return nil end
	local c = Compiled(fmt)
	if not c then return nil end
	if #c.order == 0 then return text:find(c.pattern) and {} or nil end
	local caps = { text:match(c.pattern) }
	if caps[1] == nil then return nil end
	local args = {}
	for i, arg in ipairs(c.order) do
		local v = caps[i]
		if c.kinds[arg] == "d" then v = tonumber(v) end
		if v == nil then return nil end
		-- the same argument twice in one format must read the same both times
		if args[arg] ~= nil and args[arg] ~= v then return nil end
		args[arg] = v
	end
	return args
end

---------------------------------------------------------------------------
-- The game's lines
---------------------------------------------------------------------------

local function Named(s) return type(s) == "string" and s ~= "" and not s:find("%c") end

-- Both of the client's duel formats take the winner first and the loser second, whatever
-- order the words put them in: the English retreat line names the one who fled first.
local DUEL_WAYS = {
	{ key = "DUEL_WINNER_KNOCKOUT", method = "knockout" },
	{ key = "DUEL_WINNER_RETREAT", method = "fled" },
}

function ArenaParse.DuelResult(msg, knockout, retreat)
	if Secret(msg) then return nil, "secret" end
	if type(msg) ~= "string" then return nil end
	-- Both ways are read, not the first that fits: the captures are greedy, so in a language
	-- where one line holds the other's words ("won against %2$s" and "won against %2$s (fled)")
	-- the shorter one reads the longer line too, with a wrong loser and a wrong method.
	local read
	for _, way in ipairs(DUEL_WAYS) do
		local given
		if way.method == "knockout" then given = knockout else given = retreat end
		local args = ArenaParse.Scan((ArenaParse.Format(way.key, given)), msg)
		if args then
			if read then return nil end
			read = { winner = args[1], loser = args[2], method = way.method }
		end
	end
	if read and Named(read.winner) and Named(read.loser) and read.winner ~= read.loser then
		return read.winner, read.loser, read.method
	end
	return nil
end

-- A roll's numbers fit in 32 bits (Farkle's is 1-46656). Past 2^31 - 1 a number is refused rather
-- than trusted, and past 2^53 a Lua number would not even hold it exactly.
local MAX_ROLL = 2147483647
local function Whole(v)
	v = tonumber(v)
	return v and v >= 0 and v <= MAX_ROLL and math.floor(v) == v and v or nil
end

function ArenaParse.Roll(msg, fmt)
	local args, why = ArenaParse.Scan((ArenaParse.Format("RANDOM_ROLL_RESULT", fmt)), msg)
	if not args then return nil, why end
	local name, value, low, high = args[1], Whole(args[2]), Whole(args[3]), Whole(args[4])
	if not Named(name) or not value or not low or not high then return nil end
	if low > high or value < low or value > high then return nil end
	return name, value, low, high
end

---------------------------------------------------------------------------
-- A fight's facts from the combat log and UNIT_COMBAT
---------------------------------------------------------------------------

-- The props wait for an in-game check before they count for gold (the design): rehearsals
-- and test builds (T) run them as a trial, and a live show (L) only once LIVE_PROPS is switched
-- on. Only exactly true switches them on: a stray value in saved data does not.
local PROPS = { "DU", "FB", "BH" }
local PROP = { DU = true, FB = true, BH = true }

function ArenaParse.PropsOn(mode, liveProps, kind)
	if kind ~= nil and not PROP[kind] then return false, false end
	if mode == "T" then return true, true end
	if mode ~= "L" then return false, false end
	if liveProps == true then return true, false end
	if type(liveProps) == "table" then
		for _, k in ipairs(PROPS) do
			if (kind == nil or kind == k) and liveProps[k] == true then return true, false end
		end
	end
	return false, false
end

-- Damage: a hit when above 0, else (fully absorbed or blocked) a strike still.
local HIT = {
	SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
	DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
}
-- Hostile whoever the two are to each other: an attack that missed, an interrupt, a drain.
local STRIKE = {
	SWING_MISSED = true, RANGE_MISSED = true, SPELL_MISSED = true, SPELL_PERIODIC_MISSED = true,
	DAMAGE_SHIELD_MISSED = true, SPELL_ABSORBED = true, SPELL_INTERRUPT = true, SPELL_STOLEN = true,
	SPELL_DRAIN = true, SPELL_LEECH = true, SPELL_PERIODIC_DRAIN = true, SPELL_PERIODIC_LEECH = true,
}
-- An aura is hostile only when the caller gives its type as "DEBUFF" (the combat log's
-- AURA_TYPE_DEBUFF, the first field after the spell's on these subevents): a Sap or a Polymorph
-- opens a fight with no damage. Without the type a buff before the countdown reads the same.
local AURA = { SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true }
-- From a third party, help is interference as much as harm is.
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
-- A third party's touch that is not interference by itself: the arbiter invites both fighters to
-- his party (the design), so his party-wide auras and energize (a paladin's aura, Mana
-- Spring, Trueshot Aura) land on them every fight. A dispel may be a cleanse as well as a purge.
-- They are listed for the arbiter to judge.
local TOUCH = { SPELL_ENERGIZE = true, SPELL_PERIODIC_ENERGIZE = true, SPELL_DISPEL = true }

ArenaParse.FIGHT_EVENTS = { SPELL_SUMMON = true }
for _, set in ipairs({ HIT, STRIKE, AURA, HEAL, TOUCH }) do
	for k in pairs(set) do ArenaParse.FIGHT_EVENTS[k] = true end
end

local function Guid(g) return type(g) == "string" and g ~= "" end
local function Time(t) return type(t) == "number" and t == t and t > -math.huge and t < math.huge end
local function Amount(n)
	if type(n) ~= "number" or n ~= n or n <= 0 or n == math.huge then return 0 end
	return n
end
local function Crit(c) return c ~= nil and c ~= false and c ~= 0 end

-- What an event from one side on the other is: "hit", "strike", or nil (help, or unknown).
local function Hostile(sub, amount, auraType)
	if HIT[sub] then return Amount(amount) > 0 and "hit" or "strike" end
	if STRIKE[sub] or (AURA[sub] and auraType == "DEBUFF") then return "strike" end
	return nil
end

-- A list of third parties: each one's first act of its kind (the earliest, whatever order they
-- are fed in). Past MAX_OUTSIDE only the earliest time is kept: enough to say whether anyone did.
local function List() return { by = {}, count = 0, crowd = nil } end

local function Note(list, src, dst, t, sub, spellId)
	local seen = list.by[src]
	if seen then
		if t < seen.t then seen.dest, seen.t, seen.subevent, seen.spellId = dst, t, sub, spellId end
	elseif list.count < ArenaParse.MAX_OUTSIDE then
		list.by[src] = { guid = src, dest = dst, t = t, subevent = sub, spellId = spellId }
		list.count = list.count + 1
	elseif not list.crowd or t < list.crowd then
		list.crowd = t
	end
end

local function Forget(list, guid)
	if list.by[guid] then list.by[guid], list.count = nil, list.count - 1 end
end

local function Own(fight, guid, owner)
	if not Guid(guid) or guid == fight.a or guid == fight.b then return nil end
	if owner ~= fight.a and owner ~= fight.b then return nil end
	if fight.owned[guid] then return fight.owned[guid] == owner or nil end
	-- counted per fighter: one shaman's totems never crowd out the other fighter's pet
	if fight.ownedCount[owner] >= ArenaParse.MAX_OWNED then return nil end
	fight.owned[guid], fight.ownedCount[owner] = owner, fight.ownedCount[owner] + 1
	-- what it did before it was known is its owner's side's, not a third party's
	Forget(fight.outside, guid)
	Forget(fight.touch, guid)
	return true
end

-- The earliest wins; on the same time the one fed first (the log's own order).
local function Earlier(have, t) return not have or t < have.t end

-- A view's first blood, the earliest hit; the other side's hit at that very time makes it a tie
-- (an earlier hit later on clears it: the tie was not at the first blood).
local function Blood(view, hit)
	local have = view.firstBlood
	if not have or hit.t < have.t then
		view.firstBlood, view.firstBloodTie = hit, nil
	elseif hit.t == have.t and hit.side ~= have.side then
		view.firstBloodTie = true
	end
end

-- Every event that counted, by time, so Finish can say how many came after the result.
local function Mark(fight, t)
	local times = fight.times
	if #times < ArenaParse.MAX_HITS then times[#times + 1] = t else fight.overflow = true end
end

local function Logged(fight, t, sub, src, dst, amount, crit, spellId, auraType)
	if not Time(t) or type(sub) ~= "string" then return nil end
	if not Guid(src) or not Guid(dst) or src == dst then return nil end
	local a, b = fight.a, fight.b
	if sub == "SPELL_SUMMON" then
		-- learnt whenever it comes: a totem dropped before the bell is still its shaman's
		local owner = (src == a or src == b) and src or fight.owned[src]
		return owner and Own(fight, dst, owner) and "summon" or nil
	end
	if fight.from and t < fight.from then return nil end
	if dst ~= a and dst ~= b then return nil end
	-- whose side the source is on: a fighter himself, or his pet, totem or guardian
	local side = (src == a or src == b) and src or fight.owned[src]
	if side then
		local kind = side ~= dst and Hostile(sub, amount, auraType)
		if not kind then return nil end
		Mark(fight, t)
		local own = src == side
		local struck = { guid = src, side = side, t = t, subevent = sub, spellId = spellId }
		if Earlier(fight.bySide.first, t) then fight.bySide.first = struck end
		if own and Earlier(fight.strict.first, t) then fight.strict.first = struck end
		if kind == "hit" then
			local hit = { guid = src, side = side, t = t, amount = Amount(amount), critical = Crit(crit), spellId = spellId, subevent = sub }
			Blood(fight.bySide, hit)
			if own then Blood(fight.strict, hit) end
			if #fight.hits < ArenaParse.MAX_HITS then fight.hits[#fight.hits + 1] = hit else fight.overflow = true end
		end
		return own and kind or "pet"
	end
	-- a third party
	local harm = HIT[sub] or STRIKE[sub] or HEAL[sub] or (AURA[sub] and auraType == "DEBUFF")
	if not harm and not (TOUCH[sub] or AURA[sub]) then return nil end
	Mark(fight, t)
	if harm then
		Note(fight.outside, src, dst, t, sub, spellId)
		return "outside"
	end
	Note(fight.touch, src, dst, t, sub, spellId)
	return "touch"
end

-- One feed per fight: the first to count an event holds it (the API block says why).
local function Feed(fight, t, sub, src, dst, amount, crit, spellId, auraType)
	if fight.facts then return nil end
	if fight.feed == "unit" then return nil, "feed" end
	local kind = Logged(fight, t, sub, src, dst, amount, crit, spellId, auraType)
	if kind then fight.feed = "log" end
	return kind
end

-- UNIT_COMBAT's events besides WOUND and the help (HEAL, ENERGIZE), as the client's own combat
-- feedback reads them (Blizzard_FrameXML/Mainline/CombatFeedback.lua): an attack on the unit
-- that did it no damage, or a cast of his cut short.
local AVOIDED = {
	MISS = true, DODGE = true, PARRY = true, BLOCK = true, BLOCK_REDUCED = true, RESIST = true,
	IMMUNE = true, ABSORB = true, DEFLECT = true, REFLECT = true, EVADE = true, INTERRUPT = true,
}

-- A value the facts need could not be read: the earliest such time is kept, and it makes the
-- fight Wound's.
local function Unread(fight, t)
	if not fight.secret or t < fight.secret then fight.secret = t end
	fight.feed = "unit"
	return nil, "secret"
end

local function Wound(fight, t, victim, event, flag, amount)
	if fight.facts or not Time(t) then return nil end
	if fight.feed == "log" then return nil, "feed" end
	if fight.from and t < fight.from then return nil end
	-- A secret value errors on any comparison or string operation, so each value is checked just
	-- before its first use, and only once it is needed: a secret on a bystander's token, a heal
	-- or a miss says nothing the facts lack (review of the arena's parser, finding 1).
	if Secret(victim) then return Unread(fight, t) end
	local a, b = fight.a, fight.b
	if victim ~= a and victim ~= b then return nil end
	if Secret(event) then return Unread(fight, t) end
	local kind
	if event == "WOUND" then
		if Secret(flag) or Secret(amount) then return Unread(fight, t) end
		kind = Amount(amount) > 0 and "wound" or "strike"
	elseif AVOIDED[event] then
		kind = "strike"
	else
		return nil
	end
	fight.feed = "unit"
	-- The event fires once per token that is him (party1, target, focus, a nameplate), all in
	-- the same frame: at one time, one wound. Only a WOUND's flagText and amount are read.
	local key = victim .. "\0" .. event
	if event == "WOUND" then key = key .. "\0" .. tostring(flag) .. "\0" .. tostring(amount) end
	if fight.woundAt ~= t then fight.woundAt, fight.woundKeys = t, {} end
	if fight.woundKeys[key] then return kind end
	fight.woundKeys[key] = true
	Mark(fight, t)
	local side = victim == a and b or a
	if Earlier(fight.bySide.first, t) then fight.bySide.first = { side = side, t = t, subevent = event } end
	if kind == "wound" then
		local hit = { side = side, t = t, amount = Amount(amount), critical = flag == "CRITICAL", subevent = event }
		Blood(fight.bySide, hit)
		if #fight.hits < ArenaParse.MAX_HITS then fight.hits[#fight.hits + 1] = hit else fight.overflow = true end
	end
	return kind
end

local function Copy(t)
	if not t then return nil end
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

-- One view's facts in the window: `strict` counts only the fighters' own hits, else each side's.
-- The biggest of a side: the larger amount, on the same amount the earlier.
local function Settle(into, seen, hits, result, a, b, strict)
	if seen.first and seen.first.t <= result then
		into.first = Copy(seen.first)
		into.duration = result - seen.first.t
	end
	if seen.firstBlood and seen.firstBlood.t <= result then
		into.firstBlood = Copy(seen.firstBlood)
		into.firstBloodTie = seen.firstBloodTie
	end
	local best = {}
	for _, hit in ipairs(hits) do
		if hit.t <= result and (not strict or hit.guid == hit.side) then
			local have = best[hit.side]
			if not have or hit.amount > have.amount or (hit.amount == have.amount and hit.t < have.t) then best[hit.side] = hit end
		end
	end
	into.best = {}
	into.best[a], into.best[b] = Copy(best[a]), Copy(best[b])
	local ha, hb = best[a], best[b]
	if ha and hb and ha.amount == hb.amount then
		into.tie = true
	elseif ha or hb then
		into.biggest = Copy((not hb or (ha and ha.amount > hb.amount)) and ha or hb)
	end
	return into
end

-- A list's entries in the window, by time; true when one past the list acted in the window too.
local function Listed(into, list, result)
	for _, seen in pairs(list.by) do
		if seen.t <= result then into[#into + 1] = Copy(seen) end
	end
	table.sort(into, function(x, y)
		if x.t ~= y.t then return x.t < y.t end
		return x.guid < y.guid
	end)
	return list.crowd ~= nil and list.crowd <= result
end

local function Finish(fight, result)
	if fight.facts then return fight.facts end
	if not Time(result) then return nil end
	-- a result before the bell is two clocks mixed (GetTime() and the combat log's), not a fight
	if fight.from and result < fight.from then return nil end
	local a, b = fight.a, fight.b
	local facts = { a = a, b = b, from = fight.from, result = result, feed = fight.feed, outsiders = {}, touched = {}, late = 0 }
	for _, t in ipairs(fight.times) do
		if t > result then facts.late = facts.late + 1 end
	end
	Settle(facts, fight.strict, fight.hits, result, a, b, true)
	facts.side = Settle({}, fight.bySide, fight.hits, result, a, b, false)
	facts.overflow = fight.overflow or nil
	-- the time, not a flag: what was settled before it stands (review of the arena's parser, finding 3)
	if fight.secret and fight.secret <= result then facts.secret = fight.secret end
	local crowd = Listed(facts.outsiders, fight.outside, result)
	facts.interfered = #facts.outsiders > 0 or crowd
	facts.touchedMore = Listed(facts.touched, fight.touch, result) or nil
	fight.facts = facts
	return facts
end

ArenaParse.Own, ArenaParse.Feed, ArenaParse.Wound, ArenaParse.Finish = Own, Feed, Wound, Finish

function ArenaParse.New(a, b, from)
	if not Guid(a) or not Guid(b) or a == b then return nil end
	if from ~= nil and not Time(from) then return nil end
	return {
		a = a, b = b, from = from,
		strict = {}, bySide = {},   -- first, firstBlood and firstBloodTie so far, each view
		feed = nil,                 -- "log" (Feed) or "unit" (Wound): the first to count holds it
		hits = {}, times = {}, overflow = nil,
		owned = {}, ownedCount = { [a] = 0, [b] = 0 },
		outside = List(), touch = List(),
		secret = nil,               -- the earliest secret wound
		woundAt = nil, woundKeys = nil,   -- the wounds already fed at the latest time
		facts = nil,
		Own = Own, Feed = Feed, Wound = Wound, Finish = Finish,
	}
end
