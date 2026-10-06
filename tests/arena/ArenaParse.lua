-- 1.2: ns.ArenaParse, the Blood Arena's readers: the duel's line and /roll lines from the
-- client's own format strings (English, and a reordered positional language made up here),
-- and a fight's facts from combat log tuples. Loaded into its own table: nothing else of the
-- addon is needed, which is the point of a pure module.
local H = ...
local test, eq = H.test, H.eq

local ns = {}
assert(loadfile(H.ADDON_DIR .. "ArenaParse.lua"))("Olympus", ns)
local P = ns.ArenaParse

local NONE = {}
-- The client's globals for one test, put back afterwards even when it fails. NONE unsets one.
local function WithGlobals(set, fn)
	local saved = {}
	for k in pairs(set) do saved[k] = rawget(_G, k) end
	for k, v in pairs(set) do
		if v == NONE then rawset(_G, k, nil) else rawset(_G, k, v) end
	end
	local ok, err = pcall(fn)
	for k in pairs(set) do rawset(_G, k, saved[k]) end
	if not ok then error(err, 0) end
end

local ENGLISH = {
	DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel",
	DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel",
	RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)",
}
-- A language that puts the arguments the other way round (as German and others do), made up
-- for the test: the loser comes first in the knockout line, the range before the roll.
local REORDERED = {
	DUEL_WINNER_KNOCKOUT = "%2$s wurde von %1$s im Duell besiegt",
	DUEL_WINNER_RETREAT = "%1$s bleibt, %2$s ist aus dem Duell geflohen",
	RANDOM_ROLL_RESULT = "(%3$d-%4$d) %1$s würfelt %2$d.",
}

local function Duel(msg, knockout, retreat) return { P.DuelResult(msg, knockout, retreat) } end
local function Rolled(msg, fmt) return { P.Roll(msg, fmt) } end
local function Same(got, want, msg)
	eq(#got, #want, (msg or "") .. " (count)")
	for i = 1, #want do eq(got[i], want[i], (msg or "") .. " [" .. i .. "]") end
end

print("ArenaParse: the game's lines")

test("1.2 ArenaParse: the English duel line gives winner, loser and how (the retreat line names the loser first)", function()
	WithGlobals(ENGLISH, function()
		Same(Duel("Torvan Ashmane has defeated Selwyn Duskwater in a duel"), { "Torvan Ashmane", "Selwyn Duskwater", "knockout" })
		Same(Duel("Selwyn Duskwater has fled from Torvan Ashmane in a duel"), { "Torvan Ashmane", "Selwyn Duskwater", "fled" })
	end)
end)

test("1.2 ArenaParse: names keep their realm and Forever's First-Surname form, as the line writes them", function()
	WithGlobals(ENGLISH, function()
		Same(Duel("Torvan-Ashmane has defeated Selwyn-Duskwater in a duel"), { "Torvan-Ashmane", "Selwyn-Duskwater", "knockout" })
		Same(Duel("Mirelle Stonehart-ClassicBetaPvP has fled from Garrok-Stormrage in a duel"),
			{ "Garrok-Stormrage", "Mirelle Stonehart-ClassicBetaPvP", "fled" })
	end)
end)

test("1.2 ArenaParse: a language with positional arguments in another order reads the same winner and loser", function()
	WithGlobals(REORDERED, function()
		Same(Duel("Selwyn Duskwater wurde von Torvan Ashmane im Duell besiegt"), { "Torvan Ashmane", "Selwyn Duskwater", "knockout" })
		Same(Duel("Torvan Ashmane bleibt, Selwyn Duskwater ist aus dem Duell geflohen"), { "Torvan Ashmane", "Selwyn Duskwater", "fled" })
		-- the English line means nothing on this client
		Same(Duel("Torvan Ashmane has defeated Selwyn Duskwater in a duel"), {})
	end)
end)

test("1.2 ArenaParse: the client's strings are read at call time (a switch needs no reload), and formats passed in win over them", function()
	WithGlobals(ENGLISH, function()
		Same(Duel("Torvan has defeated Selwyn in a duel"), { "Torvan", "Selwyn", "knockout" })
		rawset(_G, "DUEL_WINNER_KNOCKOUT", REORDERED.DUEL_WINNER_KNOCKOUT)
		Same(Duel("Torvan has defeated Selwyn in a duel"), {}, "the old string is not cached")
		Same(Duel("Selwyn wurde von Torvan im Duell besiegt"), { "Torvan", "Selwyn", "knockout" })
		-- given ones: the client's are not used
		Same(Duel("Selwyn wurde von Torvan im Duell besiegt", ENGLISH.DUEL_WINNER_KNOCKOUT, ENGLISH.DUEL_WINNER_RETREAT), {})
		Same(Duel("Torvan has defeated Selwyn in a duel", ENGLISH.DUEL_WINNER_KNOCKOUT, ENGLISH.DUEL_WINNER_RETREAT), { "Torvan", "Selwyn", "knockout" })
		Same(Rolled("(1-6) Torvan würfelt 4.", REORDERED.RANDOM_ROLL_RESULT), { "Torvan", 4, 1, 6 })
	end)
end)

test("1.2 ArenaParse: given one duel format only, the other way still reads the client's (a fled line is never a knockout)", function()
	-- Review of 1.2, finding 1: with the knockout format left out, the retreat one was used for both
	-- ways (Lua's and/or with a nil), so a fled line settled as a knockout.
	WithGlobals(REORDERED, function()
		Same(Duel("Selwyn has fled from Torvan in a duel", nil, ENGLISH.DUEL_WINNER_RETREAT), { "Torvan", "Selwyn", "fled" })
		Same(Duel("Selwyn wurde von Torvan im Duell besiegt", nil, ENGLISH.DUEL_WINNER_RETREAT), { "Torvan", "Selwyn", "knockout" },
			"the client's knockout line")
		Same(Duel("Torvan has defeated Selwyn in a duel", ENGLISH.DUEL_WINNER_KNOCKOUT), { "Torvan", "Selwyn", "knockout" })
		Same(Duel("Torvan bleibt, Selwyn ist aus dem Duell geflohen", ENGLISH.DUEL_WINNER_KNOCKOUT), { "Torvan", "Selwyn", "fled" },
			"the client's retreat line")
	end)
end)

test("1.2 ArenaParse: a line both duel formats read is refused, since which way it went can't be told", function()
	-- Review of 1.2, finding 2: made-up formats where the knockout's words sit inside the retreat's.
	-- The greedy capture let the knockout read the fled line, with "Selwyn (fled)" as the loser.
	local K, R = "%1$s won against %2$s", "%1$s won against %2$s (fled)"
	Same(Duel("Torvan won against Selwyn (fled)", K, R), {}, "both read it")
	Same(Duel("Torvan won against Selwyn", K, R), { "Torvan", "Selwyn", "knockout" }, "only the knockout reads it")
	Same(Duel("Torvan has defeated Selwyn in a duel", ENGLISH.DUEL_WINNER_KNOCKOUT, ENGLISH.DUEL_WINNER_KNOCKOUT), {},
		"one format given for both ways")
end)

test("1.2 ArenaParse: without the client's strings the English ones are used, and Format says it fell back", function()
	WithGlobals({ DUEL_WINNER_KNOCKOUT = NONE, DUEL_WINNER_RETREAT = "", RANDOM_ROLL_RESULT = 42 }, function()
		Same(Duel("Torvan has defeated Selwyn in a duel"), { "Torvan", "Selwyn", "knockout" })
		Same(Duel("Selwyn has fled from Torvan in a duel"), { "Torvan", "Selwyn", "fled" })
		Same(Rolled("Torvan rolls 3 (1-6)"), { "Torvan", 3, 1, 6 })
		local fmt, fallback = P.Format("RANDOM_ROLL_RESULT")
		eq(fmt, "%s rolls %d (%d-%d)")
		eq(fallback, true, "the fallback is said")
	end)
	WithGlobals(REORDERED, function()
		local fmt, fallback = P.Format("RANDOM_ROLL_RESULT")
		eq(fmt, REORDERED.RANDOM_ROLL_RESULT)
		eq(fallback, false, "the client's own")
		eq(select(2, P.Format("RANDOM_ROLL_RESULT", "%s: %d (%d-%d)")), false, "a given format is no fallback")
	end)
end)

test("1.2 ArenaParse: other system lines, near misses and junk read as nothing, without an error", function()
	WithGlobals(ENGLISH, function()
		for _, line in ipairs({
			"Torvan Ashmane has come online.",
			"Torvan Ashmane has defeated Selwyn Duskwater in a duel!",       -- more after the end
			"Torvan Ashmane has defeated Selwyn Duskwater",
			" has defeated  in a duel",
			"Torvan has defeated Torvan in a duel",                           -- one player on both sides
			"Torvan\nX has defeated Selwyn in a duel",                         -- a control character in a name
			"Torvan rolls 3 (1-6)",                                           -- a roll is no duel
			"", 42, true, {},
		}) do
			Same(Duel(line), {}, tostring(line))
		end
		Same(Duel(nil), {}, "nil")
	end)
end)

test("1.2 ArenaParse: a secret line (chat lockdown) is dropped before any string operation, and says it was a secret", function()
	-- Plain Lua has no secret strings: these lines stand for them, lines that would read. While
	-- the test runs, a string method called on one errors, as it does in the game (review of 1.2,
	-- finding 10: a check moved after the first text:match passed before). And a value whose
	-- every use errors.
	local secret = setmetatable({}, { __index = function() error("a string operation on a secret value") end })
	local SECRET = { ["Garrok has defeated Mirelle in a duel"] = true, ["Garrok rolls 3 (1-6)"] = true }
	local strings = getmetatable("")
	local index = strings.__index
	strings.__index = function(s, k)
		if SECRET[s] then error("a string operation on a secret line", 2) end
		return index[k]
	end
	-- everything past the first result: "secret" for a secret, nothing for a line that doesn't match
	local function Why(...) return { select(2, ...) } end
	local ok, err = pcall(WithGlobals, { issecretvalue = function(v) return rawequal(v, secret) or SECRET[v] == true end }, function()
		WithGlobals(ENGLISH, function()
			-- review of 1.2, finding 8: the reason comes back, so the arena can count these and
			-- Farkle can say "you can't see the dice here" without checking again
			Same(Why(P.DuelResult(secret)), { "secret" })
			Same(Why(P.Roll(secret)), { "secret" })
			Same(Why(P.Scan("%s", secret)), { "secret" })
			eq(P.DuelResult("Garrok has defeated Mirelle in a duel"), nil, "a secret duel line")
			Same(Why(P.DuelResult("Garrok has defeated Mirelle in a duel")), { "secret" })
			eq(P.Roll("Garrok rolls 3 (1-6)"), nil, "a secret roll")
			Same(Why(P.Roll("Garrok rolls 3 (1-6)")), { "secret" })
			Same(Why(P.Scan("%s has defeated %s in a duel", "Garrok has defeated Mirelle in a duel")), { "secret" })
			Same(Why(P.DuelResult("Torvan has come online.")), {}, "no match, no reason")
			Same(Why(P.Roll("Torvan rolls 7 (1-6)")), {})
			Same(Why(P.Scan("%s rolls", "Torvan")), {})
			Same(Duel("Torvan has defeated Selwyn in a duel"), { "Torvan", "Selwyn", "knockout" }, "plain lines still read")
			Same(Rolled("Torvan rolls 3 (1-6)"), { "Torvan", 3, 1, 6 })
		end)
	end)
	strings.__index = index
	if not ok then error(err, 0) end
	-- a client without issecretvalue (older ones) reads every line
	WithGlobals({ issecretvalue = NONE }, function()
		Same(Duel("Garrok has defeated Mirelle in a duel", ENGLISH.DUEL_WINNER_KNOCKOUT), { "Garrok", "Mirelle", "knockout" })
	end)
end)

test("1.2 ArenaParse: /roll lines give name, value and range as numbers; realms kept; Farkle's 1-46656 fits", function()
	WithGlobals(ENGLISH, function()
		Same(Rolled("Torvan Ashmane rolls 37 (1-100)"), { "Torvan Ashmane", 37, 1, 100 })
		Same(Rolled("Selwyn-ArgentDawn rolls 46656 (1-46656)"), { "Selwyn-ArgentDawn", 46656, 1, 46656 })
		Same(Rolled("Mirelle Stonehart rolls 0 (0-0)"), { "Mirelle Stonehart", 0, 0, 0 })
		Same(Rolled("Torvan rolls 2147483647 (1-2147483647)"), { "Torvan", 2147483647, 1, 2147483647 }, "2^31 - 1 still reads")
		eq(type(select(2, P.Roll("Torvan rolls 7 (1-12)"))), "number")
	end)
	WithGlobals(REORDERED, function()
		Same(Rolled("(1-46656) Garrok Emberfist würfelt 777."), { "Garrok Emberfist", 777, 1, 46656 })
		Same(Rolled("Garrok Emberfist rolls 777 (1-46656)"), {}, "the English line on this client")
	end)
end)

test("1.2 ArenaParse: a roll outside its own range, a reversed range or a broken line is refused", function()
	WithGlobals(ENGLISH, function()
		for _, line in ipairs({
			"Torvan rolls 101 (1-100)",
			"Torvan rolls 0 (1-100)",
			"Torvan rolls 5 (10-1)",
			"Torvan rolls -5 (1-100)",
			"Torvan rolls 5.5 (1-100)",
			"Torvan rolls five (1-100)",
			"Torvan rolls 5 (1-100).",
			"Torvan rolls 2147483648 (1-2147483648)",               -- past 2^31 - 1 (review of 1.2, finding 11)
			"Torvan rolls 9007199254740993 (1-9007199254740992)",   -- past 2^53, where it read as in range
			" rolls 5 (1-100)",
			"Torvan Ashmane has defeated Selwyn Duskwater in a duel",
		}) do
			Same(Rolled(line), {}, line)
		end
	end)
end)

test("1.2 ArenaParse: Pattern escapes the magic characters and keeps each capture's argument", function()
	local p, order = P.Pattern("%2$s has fled from %1$s in a duel")
	eq(p, "^(.+) has fled from (.+) in a duel$")
	eq(#order, 2); eq(order[1], 2); eq(order[2], 1)
	p, order = P.Pattern("%s rolls %d (%d-%d)")
	eq(p, "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
	eq(order[1], 1); eq(order[4], 4)
	-- every magic character of a Lua pattern, and "%%", read literally
	local fmt = "[Arena] %1$s. 100%% ^win^ + $%2$d* (?)"
	local args = P.Scan(fmt, "[Arena] Torvan. 100% ^win^ + $250* (?)")
	eq(args and args[1], "Torvan"); eq(args and args[2], 250)
	eq(P.Scan(fmt, "[Arena] Torvan. 100% ^win^ + $250 (?)"), nil, "the literal '*' is required")
	eq(P.Scan(fmt, "xArena] Torvan. 100% ^win^ + $250* (?)"), nil, "'[' is no class")
	-- the order holds when the caller changes the table it got
	order[1] = 99
	eq(select(2, P.Pattern("%2$s has fled from %1$s in a duel"))[1], 2)
end)

test("1.2 ArenaParse: formats it can't read safely give no pattern (a width, %f, a lone %, one argument as two kinds)", function()
	for _, fmt in ipairs({ "%1$s has defeated %2$5s in a duel", "%s rolls %.2f", "100% %s", "%s ends with %", "%1$s and %1$d", "%0$s x", "", 7 }) do
		eq(P.Pattern(fmt), nil, tostring(fmt))
		eq(P.Scan(fmt, "Torvan has defeated Selwyn in a duel"), nil, tostring(fmt))
	end
	-- the client's knockout string unreadable: that way reads nothing, the retreat still does
	WithGlobals({ DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$5s in a duel", DUEL_WINNER_RETREAT = ENGLISH.DUEL_WINNER_RETREAT }, function()
		Same(Duel("Torvan has defeated Selwyn in a duel"), {})
		Same(Duel("Selwyn has fled from Torvan in a duel"), { "Torvan", "Selwyn", "fled" })
	end)
end)

test("1.2 ArenaParse: one argument written twice must read the same both times; plain and positional mixed give no pattern", function()
	local args = P.Scan("%1$s beats %2$s; %1$s wins", "Torvan beats Selwyn; Torvan wins")
	eq(args and args[1], "Torvan"); eq(args and args[2], "Selwyn")
	eq(P.Scan("%1$s beats %2$s; %1$s wins", "Torvan beats Selwyn; Selwyn wins"), nil)
	-- Review of 1.2, finding 9: how the client's format numbers a plain argument among positional
	-- ones is unchecked (C leaves it undefined), so such a format reads nothing rather than guess.
	-- (This test asserted one numbering before; nothing in the client source confirms any.)
	eq(P.Pattern("%s then %3$d then %d"), nil)
	eq(P.Scan("%s then %3$d then %d", "Torvan then 3 then 2"), nil)
	eq(P.Pattern("%1$s then %s"), nil)
	eq(P.Pattern("%s then %s"), "^(.+) then (.+)$", "all plain still reads")
	eq(type(P.Scan("no arguments", "no arguments")), "table", "a format with no arguments matches itself")
	eq(P.Scan("no arguments", "no arguments!"), nil)
end)

print("ArenaParse: a fight's facts")

local A, B = "Player-5826-0A0A0A01", "Player-5826-0B0B0B02"
local C, D = "Player-5826-0C0C0C03", "Player-5826-0D0D0D04"          -- bystanders
local PET = "Pet-0-5826-0-0-17252-0100000001"
local TOTEM = "Creature-0-5826-0-0-2523-0000000002"

test("1.2 ArenaParse: struck first, first blood, the biggest hit and the duration from the first strike", function()
	local f = P.New(A, B, 90)
	eq(f:Feed(100.0, "SWING_MISSED", A, B), "strike", "a miss is a strike")
	eq(f:Feed(100.5, "SPELL_DAMAGE", B, A, 150, nil, 403), "hit")
	eq(f:Feed(102.0, "SPELL_DAMAGE", A, B, 900, true, 11366), "hit")
	eq(f:Feed(104.0, "SWING_DAMAGE", B, A, 400, false), "hit")
	eq(f:Feed(106.0, "SPELL_PERIODIC_DAMAGE", A, B, 120, 1, 172), "hit")
	local facts = f:Finish(130)
	eq(facts.first.guid, A, "struck first")
	eq(facts.first.t, 100.0); eq(facts.first.subevent, "SWING_MISSED")
	eq(facts.firstBlood.guid, B, "first blood is the first damage, not the first swing")
	eq(facts.firstBlood.amount, 150); eq(facts.firstBlood.spellId, 403); eq(facts.firstBlood.critical, false)
	eq(facts.biggest.guid, A); eq(facts.biggest.amount, 900); eq(facts.biggest.critical, true); eq(facts.biggest.spellId, 11366)
	eq(facts.best[A].amount, 900); eq(facts.best[B].amount, 400)
	eq(facts.tie, nil)
	eq(facts.duration, 30, "from the first strike to the result")
	eq(facts.interfered, false); eq(#facts.outsiders, 0); eq(#facts.touched, 0); eq(facts.touchedMore, nil)
	eq(facts.overflow, nil); eq(facts.late, 0)
	eq(facts.a, A); eq(facts.b, B); eq(facts.from, 90); eq(facts.result, 130)
	eq(facts.feed, "log"); eq(facts.firstBloodTie, nil); eq(facts.side.firstBloodTie, nil)
	-- with no pets the side view says the same
	eq(facts.side.first.guid, A); eq(facts.side.firstBlood.guid, B); eq(facts.side.biggest.amount, 900)
	eq(facts.side.best[B].amount, 400); eq(facts.side.duration, 30)
end)

test("1.2 ArenaParse: nothing before the bell or after the result counts, and the fight is closed at Finish", function()
	local f = P.New(A, B, 100)
	-- a sparring round before the bell: bigger, earlier, and nothing
	eq(f:Feed(50, "SPELL_DAMAGE", B, A, 5000, true, 1), nil)
	eq(f:Feed(99.99, "SWING_MISSED", B, A), nil)
	eq(f:Feed(99, "SPELL_HEAL", C, A, 800), nil, "help before the bell is no interference")
	f:Feed(101, "SWING_DAMAGE", A, B, 200)
	f:Feed(105, "SWING_DAMAGE", B, A, 300)
	-- after the result (fed before Finish): a bigger hit and a third party
	f:Feed(121, "SPELL_DAMAGE", B, A, 9000, true, 2)
	f:Feed(121, "SPELL_DAMAGE", C, B, 50)
	local facts = f:Finish(120)
	eq(facts.first.guid, A); eq(facts.first.t, 101)
	eq(facts.firstBlood.guid, A)
	eq(facts.biggest.guid, B); eq(facts.biggest.amount, 300, "the late 9000 is out")
	eq(facts.interfered, false, "the late third party is out")
	eq(facts.duration, 19)
	eq(facts.late, 2, "the two after the result are counted (the ones before the bell never counted)")
	-- closed: fed later, nothing changes, and Finish gives the same facts
	eq(f:Feed(110, "SPELL_DAMAGE", A, B, 7000), nil)
	eq(f:Finish(200), facts)
	eq(facts.biggest.amount, 300)
end)

test("1.2 ArenaParse: only the two fighters' GUIDs make facts; a third party harming or healing either one is interference", function()
	local f = P.New(A, B)
	eq(f:Feed(10, "SPELL_DAMAGE", C, B, 5000, true, 133), "outside")
	eq(f:Feed(11, "SWING_DAMAGE", A, B, 100), "hit")
	eq(f:Feed(12, "SPELL_HEAL", D, A, 1200, nil, 2061), "outside")
	eq(f:Feed(13, "SPELL_DAMAGE", C, A, 10), "outside", "the same bystander again")
	-- (a Polymorph given as a DEBUFF: an aura of no given type is no longer interference, finding 3)
	eq(f:Feed(9, "SPELL_AURA_APPLIED", C, A, nil, nil, 118, "DEBUFF"), "outside", "an earlier hostile aura fed late")
	local facts = f:Finish(20)
	eq(facts.first.guid, A, "the bystander's earlier hit is not the first")
	eq(facts.firstBlood.guid, A)
	eq(facts.biggest.guid, A); eq(facts.biggest.amount, 100, "the bystander's 5000 is not the biggest")
	eq(facts.best[B], nil, "B dealt nothing")
	eq(facts.interfered, true)
	eq(#facts.outsiders, 2)
	eq(facts.outsiders[1].guid, C); eq(facts.outsiders[1].t, 9); eq(facts.outsiders[1].dest, A); eq(facts.outsiders[1].subevent, "SPELL_AURA_APPLIED")
	eq(facts.outsiders[2].guid, D); eq(facts.outsiders[2].subevent, "SPELL_HEAL"); eq(facts.outsiders[2].dest, A)
end)

test("1.2 ArenaParse: events that touch neither fighter, oneself, or have no source count for nothing", function()
	local f = P.New(A, B)
	eq(f:Feed(10, "SPELL_DAMAGE", A, C, 999), nil, "a fighter hitting a bystander")
	eq(f:Feed(10, "SPELL_DAMAGE", C, D, 999), nil, "two bystanders")
	eq(f:Feed(10, "SPELL_DAMAGE", A, A, 999), nil, "a fighter on himself (a life tap)")
	eq(f:Feed(10, "SPELL_HEAL", B, B, 999), nil)
	eq(f:Feed(10, "ENVIRONMENTAL_DAMAGE", nil, A, 999), nil, "falling")
	eq(f:Feed(10, "SPELL_DAMAGE", "", A, 999), nil)
	eq(f:Feed(10, "SPELL_HEAL", A, B, 500), nil, "healing the other one is no strike")
	eq(f:Feed(10, "SPELL_AURA_APPLIED", A, B, nil, nil, 1243), nil, "an aura between them: a buff before the countdown reads the same")
	eq(f:Feed(10, "SPELL_DISPEL", B, A), nil)
	eq(f:Feed(10, "SPELL_CAST_SUCCESS", A, B), nil, "a cast is not a strike until it lands or misses")
	eq(f:Feed(10, "UNIT_DIED", C, A), nil)
	local facts = f:Finish(30)
	eq(facts.first, nil); eq(facts.firstBlood, nil); eq(facts.biggest, nil); eq(facts.duration, nil)
	eq(facts.interfered, false)
end)

test("1.2 ArenaParse: damage fully absorbed, an interrupt or a drain is a strike, never first blood", function()
	local f = P.New(A, B)
	eq(f:Feed(10, "SPELL_DAMAGE", B, A, 0, nil, 133), "strike", "absorbed whole")
	eq(f:Feed(11, "SPELL_INTERRUPT", A, B, nil, nil, 1766), "strike")
	eq(f:Feed(12, "SPELL_DRAIN", A, B, 300), "strike")
	eq(f:Feed(13, "SPELL_ABSORBED", A, B, 250), "strike")
	eq(f:Feed(14, "SWING_DAMAGE", A, B, 80), "hit")
	local facts = f:Finish(20)
	eq(facts.first.guid, B); eq(facts.first.t, 10)
	eq(facts.firstBlood.guid, A); eq(facts.firstBlood.t, 14)
	eq(facts.biggest.amount, 80, "a drain's amount is no hit")
	eq(facts.duration, 10)
end)

test("1.2 ArenaParse: a fighter's summons and named pets are his own, never a third party, and never make his strict facts", function()
	-- Their hits now return "pet" and count in the side facts (review of 1.2, finding 5); they
	-- returned nil before. The strict facts below are unchanged.
	local f = P.New(A, B, 0)
	eq(f:Feed(1, "SPELL_SUMMON", A, TOTEM, nil, nil, 3599), "summon")
	eq(f:Own(PET, B), true)
	eq(f:Own(PET, B), true, "the same again")
	eq(f:Own(PET, A), nil, "already the other one's")
	eq(f:Own(C, D), nil, "an owner who is not a fighter")
	eq(f:Own(A, B), nil, "a fighter is nobody's pet")
	eq(f:Feed(5, "SPELL_DAMAGE", TOTEM, B, 3000, nil, 3606), "pet")
	eq(f:Feed(6, "SWING_DAMAGE", PET, A, 2500), "pet")
	eq(f:Feed(7, "SPELL_HEAL", TOTEM, A, 400), nil, "a totem healing its own shaman")
	eq(f:Feed(7, "SPELL_DAMAGE", TOTEM, A, 400), nil, "on its own master counts for nothing")
	eq(f:Feed(8, "SWING_DAMAGE", B, A, 90), "hit")
	-- a summon by someone else is no fighter's, and a summon of a summon is its owner's
	eq(f:Feed(9, "SPELL_SUMMON", C, "Creature-0-5826-0-0-1-0000000003"), nil)
	eq(f:Feed(9, "SPELL_SUMMON", TOTEM, "Creature-0-5826-0-0-1-0000000004"), "summon")
	eq(f:Feed(10, "SPELL_DAMAGE", "Creature-0-5826-0-0-1-0000000004", B, 10), "pet")
	local facts = f:Finish(20)
	eq(facts.interfered, false); eq(#facts.touched, 0)
	eq(facts.first.guid, B, "the pet's earlier hit is not his owner's strike")
	eq(facts.biggest.guid, B); eq(facts.biggest.amount, 90)
	eq(facts.best[A], nil, "A's totems dealt his side's only hits")
	-- his side's: the totem struck first and hit hardest
	eq(facts.side.first.guid, TOTEM); eq(facts.side.first.side, A); eq(facts.side.first.t, 5)
	eq(facts.side.firstBlood.guid, TOTEM); eq(facts.side.firstBlood.amount, 3000)
	eq(facts.side.best[A].amount, 3000); eq(facts.side.best[B].guid, PET); eq(facts.side.best[B].amount, 2500)
	eq(facts.side.biggest.side, A); eq(facts.side.biggest.guid, TOTEM)
end)

test("1.2 ArenaParse: the side facts count a hunter's pet as him: its first 300 is his side's first blood", function()
	-- Review of 1.2, finding 5: the markets spec settles first blood and biggest hit from the
	-- wound the victim takes, which can't tell a pet from its master. A is a hunter, B a warrior.
	local f = P.New(A, B, 0)
	eq(f:Own(PET, A), true)
	eq(f:Feed(1, "SWING_MISSED", PET, B), "pet")
	eq(f:Feed(2, "SWING_DAMAGE", PET, B, 300), "pet")
	eq(f:Feed(3, "SWING_DAMAGE", B, A, 250), "hit")
	eq(f:Feed(4, "RANGE_DAMAGE", A, B, 200, nil, 75), "hit")
	eq(f:Feed(5, "SWING_DAMAGE", B, PET, 900), nil, "a hit on the pet is on no fighter")
	local facts = f:Finish(10)
	-- strict: the fighters' own
	eq(facts.first.guid, B); eq(facts.firstBlood.guid, B); eq(facts.firstBlood.amount, 250)
	eq(facts.biggest.guid, B); eq(facts.biggest.amount, 250); eq(facts.best[A].amount, 200)
	eq(facts.duration, 7)
	-- by side: the pet is the hunter's
	eq(facts.side.first.guid, PET); eq(facts.side.first.side, A); eq(facts.side.first.t, 1)
	eq(facts.side.firstBlood.guid, PET); eq(facts.side.firstBlood.side, A); eq(facts.side.firstBlood.amount, 300)
	eq(facts.side.best[A].guid, PET); eq(facts.side.best[A].amount, 300); eq(facts.side.best[B].amount, 250)
	eq(facts.side.biggest.side, A); eq(facts.side.biggest.amount, 300); eq(facts.side.tie, nil)
	eq(facts.side.duration, 9)
	eq(facts.interfered, false)
	-- the same biggest on both sides by side is a tie there, while the strict view has a winner
	local g = P.New(A, B, 0)
	g:Own(PET, A)
	g:Feed(1, "SWING_DAMAGE", PET, B, 250)
	g:Feed(2, "SWING_DAMAGE", B, A, 250)
	g:Feed(3, "SWING_DAMAGE", A, B, 100)
	facts = g:Finish(10)
	eq(facts.side.tie, true); eq(facts.side.biggest, nil)
	eq(facts.tie, nil); eq(facts.biggest.guid, B)
end)

test("1.2 ArenaParse: a shaman's totems (a new GUID each) stay his in a long duel, counted per fighter", function()
	-- Review of 1.2, finding 4: 50 known pets shared by both fighters ran out, and a shaman's
	-- next totem counted as a third party. Sixty each side now stay theirs.
	local f = P.New(A, B, 0)
	for i = 1, 60 do
		eq(f:Feed(i, "SPELL_SUMMON", A, ("Creature-0-5826-0-0-5925-%010d"):format(i), nil, nil, 8177), "summon", "A's totem " .. i)
		eq(f:Feed(i, "SPELL_SUMMON", B, ("Creature-0-5826-0-0-5925-%010d"):format(100 + i), nil, nil, 8177), "summon", "B's totem " .. i)
	end
	eq(f:Feed(70, "SPELL_DAMAGE", "Creature-0-5826-0-0-5925-0000000060", B, 40, nil, 8050), "pet")
	eq(f:Feed(71, "SPELL_DAMAGE", "Creature-0-5826-0-0-5925-0000000160", A, 40, nil, 8050), "pet")
	local facts = f:Finish(80)
	eq(facts.interfered, false); eq(#facts.outsiders, 0)
	-- past its owner's MAX_OWNED a summon is refused; the other fighter's count is his own
	local cap = P.MAX_OWNED
	local ok, err = pcall(function()
		P.MAX_OWNED = 2
		local g = P.New(A, B)
		eq(g:Feed(1, "SPELL_SUMMON", A, "Creature-0-5826-0-0-1-0000000011"), "summon")
		eq(g:Feed(2, "SPELL_SUMMON", A, "Creature-0-5826-0-0-1-0000000012"), "summon")
		eq(g:Feed(3, "SPELL_SUMMON", A, "Creature-0-5826-0-0-1-0000000013"), nil, "A's third")
		eq(g:Own("Creature-0-5826-0-0-1-0000000013", A), nil)
		eq(g:Own(PET, B), true, "B has room of his own")
		eq(g:Feed(4, "SPELL_SUMMON", B, "Creature-0-5826-0-0-1-0000000014"), "summon")
		eq(g:Feed(5, "SPELL_DAMAGE", "Creature-0-5826-0-0-1-0000000013", B, 10), "outside", "past the cap: a third party, for the arbiter")
	end)
	P.MAX_OWNED = cap
	if not ok then error(err, 0) end
end)

test("1.2 ArenaParse: the arbiter's party auras, energize and dispels are touches, not interference; his heal is", function()
	-- Review of 1.2, finding 3: the arbiter invites both fighters to his party (the
	-- design), so his party-wide effects land on them in every fight and set interfered each time.
	local ARB = "Player-5826-0E0E0E05"
	local ARB_TOTEM = "Creature-0-5826-0-0-3573-0000000009"
	local f = P.New(A, B, 0)
	eq(f:Feed(1, "SPELL_AURA_APPLIED", ARB, A, nil, nil, 10293, "BUFF"), "touch", "a paladin's Devotion Aura")
	eq(f:Feed(1, "SPELL_AURA_APPLIED", ARB, B, nil, nil, 10293, "BUFF"), "touch")
	eq(f:Feed(2, "SPELL_PERIODIC_ENERGIZE", ARB_TOTEM, A, 10, nil, 5677), "touch", "Mana Spring")
	eq(f:Feed(3, "SPELL_DISPEL", D, B, nil, nil, 527), "touch", "a dispel: a cleanse as well as a purge")
	eq(f:Feed(4, "SPELL_AURA_APPLIED", D, B, nil, nil, 17), "touch", "an aura of no given type")
	eq(f:Feed(5, "SWING_DAMAGE", A, B, 50), "hit")
	local facts = f:Finish(10)
	eq(facts.interfered, false); eq(#facts.outsiders, 0)
	eq(#facts.touched, 3, "each one's first touch")
	eq(facts.touched[1].guid, ARB); eq(facts.touched[1].t, 1)
	eq(facts.touched[2].guid, ARB_TOTEM); eq(facts.touched[2].subevent, "SPELL_PERIODIC_ENERGIZE")
	eq(facts.touched[3].guid, D); eq(facts.touched[3].subevent, "SPELL_DISPEL"); eq(facts.touched[3].dest, B)
	eq(facts.touchedMore, nil)
	-- harm or help from the same people is interference
	local g = P.New(A, B, 0)
	eq(g:Feed(1, "SPELL_AURA_APPLIED", ARB, A, nil, nil, 10293, "BUFF"), "touch")
	eq(g:Feed(6, "SPELL_HEAL", ARB, A, 300, nil, 2061), "outside", "his heal")
	eq(g:Feed(7, "SPELL_AURA_APPLIED", D, B, nil, nil, 118, "DEBUFF"), "outside", "a Polymorph on a fighter")
	eq(g:Feed(8, "SPELL_MISSED", D, A, nil, nil, 133), "outside")
	facts = g:Finish(10)
	eq(facts.interfered, true)
	eq(#facts.outsiders, 2); eq(facts.outsiders[1].guid, ARB); eq(facts.outsiders[1].t, 6); eq(facts.outsiders[1].subevent, "SPELL_HEAL")
	eq(facts.outsiders[2].guid, D); eq(facts.outsiders[2].t, 7)
	eq(#facts.touched, 1); eq(facts.touched[1].t, 1)
end)

test("1.2 ArenaParse: a DEBUFF between the fighters (Sap, Polymorph) is a strike when the aura type is given", function()
	-- Review of 1.2, finding 6: an opener that is only an aura was no strike, so `first` and
	-- the duration started at the next hit or miss.
	local f = P.New(A, B, 0)
	eq(f:Feed(10, "SPELL_AURA_APPLIED", A, B, nil, nil, 6770, "DEBUFF"), "strike", "a Sap opens the fight")
	eq(f:Feed(15, "SWING_DAMAGE", B, A, 90), "hit")
	local facts = f:Finish(40)
	eq(facts.first.guid, A); eq(facts.first.t, 10); eq(facts.first.spellId, 6770); eq(facts.first.subevent, "SPELL_AURA_APPLIED")
	eq(facts.duration, 30)
	eq(facts.firstBlood.guid, B, "an aura draws no blood")
	eq(facts.side.first.guid, A)
	-- a buff, or an aura whose type the caller doesn't give, is still nothing between them
	local g = P.New(A, B, 0)
	eq(g:Feed(10, "SPELL_AURA_APPLIED", A, B, nil, nil, 1243, "BUFF"), nil, "a buff")
	eq(g:Feed(11, "SPELL_AURA_APPLIED", A, B, nil, nil, 6770), nil, "no type: can't tell")
	eq(g:Feed(11, "SPELL_AURA_APPLIED", A, B, nil, nil, 6770, "debuff"), nil, "only the log's own spelling")
	eq(g:Feed(12, "SPELL_AURA_REMOVED", B, A, nil, nil, 118, "DEBUFF"), nil, "an aura ending is nobody's act")
	eq(g:Feed(13, "SPELL_AURA_APPLIED_DOSE", B, A, nil, nil, 11597, "DEBUFF"), "strike", "a Sunder Armor stack")
	eq(g:Feed(14, "SPELL_AURA_REFRESH", A, B, nil, nil, 118, "DEBUFF"), "strike")
	facts = g:Finish(20)
	eq(facts.first.guid, B); eq(facts.first.t, 13)
	-- a pet's Seduction is its side's strike
	local h = P.New(A, B, 0)
	h:Own(PET, B)
	eq(h:Feed(5, "SPELL_AURA_APPLIED", PET, A, nil, nil, 6358, "DEBUFF"), "pet")
	eq(h:Finish(9).side.first.guid, PET)
end)

test("1.2 ArenaParse: a result before the bell is refused and the fight stays open; events after the result are counted as late", function()
	-- Review of 1.2, finding 7: the bell and the result on GetTime() with the combat log's epoch
	-- times gave empty facts, with no sign of the mix-up.
	local f = P.New(A, B, 5000)
	eq(f:Finish(4999), nil, "a result before the bell")
	eq(f:Feed(1.7e9, "SWING_DAMAGE", A, B, 100), "hit", "still open")
	eq(f:Feed(1.7e9 + 1, "SPELL_HEAL", C, B, 100), "outside")
	eq(f:Feed(1.7e9 + 2, "SWING_MISSED", B, A), "strike")
	eq(f:Feed(1.7e9 + 3, "SPELL_AURA_APPLIED", C, A, nil, nil, 10293, "BUFF"), "touch")
	local facts = f:Finish(5060)
	eq(facts.first, nil); eq(facts.interfered, false); eq(#facts.touched, 0)
	eq(facts.late, 4, "the mix-up shows")
	local g = P.New(A, B, 100)
	g:Feed(101, "SWING_DAMAGE", A, B, 10)
	eq(g:Finish(100).late, 1, "a result on the bell itself is allowed")
end)

test("1.2 ArenaParse: a pet nobody named is a third party; named late, it leaves the list", function()
	local f = P.New(A, B)
	eq(f:Feed(5, "SWING_DAMAGE", PET, A, 100), "outside")
	eq(f:Finish(10).interfered, true)
	local g = P.New(A, B)
	g:Feed(5, "SWING_DAMAGE", PET, A, 100)
	g:Feed(6, "SPELL_DAMAGE", C, A, 50)
	eq(g:Own(PET, B), true)
	local facts = g:Finish(10)
	eq(#facts.outsiders, 1); eq(facts.outsiders[1].guid, C)
	eq(facts.interfered, true)
	-- a pet summoned before the bell is still learnt
	local h = P.New(A, B, 100)
	eq(h:Feed(50, "SPELL_SUMMON", B, PET), "summon")
	eq(h:Feed(101, "SWING_DAMAGE", PET, A, 100), "pet", "his side's (nil before finding 5)")
	eq(h:Finish(110).interfered, false)
end)

test("1.2 ArenaParse: the same biggest hit on both sides is a tie (no biggest); on one side the earlier counts", function()
	local f = P.New(A, B)
	f:Feed(10, "SPELL_DAMAGE", A, B, 700, true, 1)
	f:Feed(11, "SPELL_DAMAGE", B, A, 700, false, 2)
	local facts = f:Finish(20)
	eq(facts.biggest, nil); eq(facts.tie, true)
	eq(facts.best[A].amount, 700); eq(facts.best[B].amount, 700)
	local g = P.New(A, B)
	g:Feed(12, "SPELL_DAMAGE", A, B, 500, false, 7)
	g:Feed(10, "SPELL_DAMAGE", A, B, 500, true, 8)
	g:Feed(11, "SPELL_DAMAGE", B, A, 499)
	facts = g:Finish(20)
	eq(facts.tie, nil)
	eq(facts.biggest.guid, A); eq(facts.biggest.t, 10); eq(facts.biggest.spellId, 8)
end)

test("1.2 ArenaParse: events fed out of order still give the earliest; on the same time the one fed first", function()
	local f = P.New(A, B)
	f:Feed(12, "SWING_DAMAGE", A, B, 10)
	f:Feed(11, "SWING_DAMAGE", B, A, 20)
	f:Feed(11, "SWING_DAMAGE", A, B, 30)
	local facts = f:Finish(20)
	eq(facts.first.guid, B); eq(facts.firstBlood.guid, B); eq(facts.firstBlood.amount, 20)
	eq(facts.duration, 9)
end)

test("1.2 ArenaParse: a result before any strike, or no strike at all, gives no first, no duration and no biggest", function()
	local f = P.New(A, B)
	f:Feed(50, "SWING_DAMAGE", A, B, 10)
	local facts = f:Finish(40)
	eq(facts.first, nil); eq(facts.firstBlood, nil); eq(facts.duration, nil); eq(facts.biggest, nil); eq(facts.tie, nil)
	eq(next(facts.best), nil)
	local g = P.New(A, B)
	facts = g:Finish(40)
	eq(facts.first, nil); eq(facts.interfered, false); eq(#facts.outsiders, 0)
end)

test("1.2 ArenaParse: bad input is refused without an error (GUIDs, times, amounts, a result that is no number)", function()
	eq(P.New(A, A), nil, "the same fighter twice")
	eq(P.New(A, nil), nil); eq(P.New("", B), nil); eq(P.New(A, B, "soon"), nil); eq(P.New(A, B, 0 / 0), nil)
	local f = P.New(A, B)
	eq(f:Feed("100", "SWING_DAMAGE", A, B, 10), nil, "a time that is a string")
	eq(f:Feed(0 / 0, "SWING_DAMAGE", A, B, 10), nil, "NaN")
	eq(f:Feed(math.huge, "SWING_DAMAGE", A, B, 10), nil)
	eq(f:Feed(10, nil, A, B, 10), nil)
	eq(f:Feed(10, "SWING_DAMAGE", A, {}, 10), nil)
	eq(f:Feed(10, "SWING_DAMAGE", A, B, "lots"), "strike", "an amount that is no number is no hit")
	eq(f:Feed(11, "SWING_DAMAGE", A, B, -40), "strike")
	eq(f:Feed(12, "SWING_DAMAGE", A, B, 0 / 0), "strike")
	eq(f:Finish(nil), nil, "no result time")
	eq(f:Finish("20"), nil)
	eq(f:Feed(13, "SWING_DAMAGE", B, A, 60), "hit", "still open after a refused Finish")
	local facts = f:Finish(20)
	eq(facts.first.t, 10); eq(facts.biggest.guid, B); eq(facts.biggest.amount, 60)
end)

test("1.2 ArenaParse: past MAX_HITS the biggest is flagged, and past MAX_OUTSIDE interference is still seen", function()
	local maxHits, maxOutside = P.MAX_HITS, P.MAX_OUTSIDE
	local ok, err = pcall(function()
		P.MAX_HITS, P.MAX_OUTSIDE = 2, 1
		local f = P.New(A, B)
		f:Feed(1, "SWING_DAMAGE", A, B, 10)
		f:Feed(2, "SWING_DAMAGE", B, A, 20)
		eq(f:Feed(3, "SWING_DAMAGE", A, B, 30), "hit", "counted, not kept")
		eq(f:Feed(4, "SPELL_HEAL", C, A, 5), "outside")
		eq(f:Feed(5, "SPELL_HEAL", D, A, 5), "outside", "past the list")
		local facts = f:Finish(10)
		eq(facts.overflow, true)
		eq(facts.biggest.amount, 20, "from what was kept")
		eq(facts.first.t, 1)
		eq(#facts.outsiders, 1); eq(facts.interfered, true)
		-- only the crowd past the list interfered, in the window
		local g = P.New(A, B)
		g:Feed(20, "SPELL_HEAL", C, A, 5)   -- listed, after the result
		g:Feed(5, "SPELL_HEAL", D, A, 5)    -- past the list, in the window
		-- the touches have a list of their own, with the same cap
		eq(g:Feed(3, "SPELL_ENERGIZE", C, A, 5), "touch")
		eq(g:Feed(4, "SPELL_ENERGIZE", D, A, 5), "touch", "past the touch list")
		facts = g:Finish(10)
		eq(#facts.outsiders, 0); eq(facts.interfered, true)
		eq(#facts.touched, 1); eq(facts.touched[1].guid, C); eq(facts.touchedMore, true)
		local h = P.New(A, B)
		h:Feed(3, "SPELL_ENERGIZE", C, A, 5)
		h:Feed(12, "SPELL_ENERGIZE", D, A, 5)   -- past the list, after the result
		facts = h:Finish(10)
		eq(#facts.touched, 1); eq(facts.touchedMore, nil)
	end)
	P.MAX_HITS, P.MAX_OUTSIDE = maxHits, maxOutside
	if not ok then error(err, 0) end
end)

test("1.2 ArenaParse: FIGHT_EVENTS lists what Feed reads, and the module-level functions are the fight's", function()
	for _, sub in ipairs({ "SWING_DAMAGE", "SPELL_MISSED", "SPELL_HEAL", "SPELL_AURA_APPLIED", "SPELL_AURA_REFRESH", "SPELL_SUMMON",
		"SPELL_INTERRUPT", "SPELL_PERIODIC_ENERGIZE", "SPELL_DISPEL" }) do
		eq(P.FIGHT_EVENTS[sub], true, sub)
	end
	eq(P.FIGHT_EVENTS.SPELL_CAST_SUCCESS, nil); eq(P.FIGHT_EVENTS.UNIT_DIED, nil); eq(P.FIGHT_EVENTS.ENVIRONMENTAL_DAMAGE, nil)
	local f = P.New(A, B)
	eq(P.Feed(f, 1, "SWING_DAMAGE", A, B, 10), "hit")
	eq(P.Finish(f, 5).biggest.amount, 10)
end)

print("ArenaParse: the design's contract")

-- The the design's invented names: fighters Torvin Hale and Selka Drummond.
test("1.2 ArenaParse: Forever's First Surname names read whole, spaced or hyphenated, with or without a realm, in both duel ways and in rolls", function()
	WithGlobals(ENGLISH, function()
		Same(Duel("Torvin Hale has defeated Selka Drummond in a duel"), { "Torvin Hale", "Selka Drummond", "knockout" })
		Same(Duel("Selka Drummond-ClassicBetaPvP has fled from Torvin Hale-ClassicBetaPvP2 in a duel"),
			{ "Torvin Hale-ClassicBetaPvP2", "Selka Drummond-ClassicBetaPvP", "fled" })
		-- the unit functions' "First-Surname" form comes back as written, for the caller's ns.Normal
		Same(Duel("Torvin-Hale has fled from Selka-Drummond in a duel"), { "Selka-Drummond", "Torvin-Hale", "fled" })
		Same(Rolled("Torvin Hale rolls 46656 (1-46656)"), { "Torvin Hale", 46656, 1, 46656 })
		Same(Rolled("Selka Drummond-ClassicBetaPvP rolls 1 (1-46656)"), { "Selka Drummond-ClassicBetaPvP", 1, 1, 46656 })
		Same(Rolled("Torvin-Hale rolls 7 (1-100)"), { "Torvin-Hale", 7, 1, 100 })
	end)
	WithGlobals(REORDERED, function()
		Same(Duel("Selka Drummond wurde von Torvin Hale im Duell besiegt"), { "Torvin Hale", "Selka Drummond", "knockout" })
		Same(Duel("Torvin Hale-ClassicBetaPvP bleibt, Selka Drummond ist aus dem Duell geflohen"),
			{ "Torvin Hale-ClassicBetaPvP", "Selka Drummond", "fled" })
		Same(Rolled("(1-46656) Selka Drummond-ClassicBetaPvP würfelt 31104."), { "Selka Drummond-ClassicBetaPvP", 31104, 1, 46656 })
	end)
end)

test("1.2 ArenaParse: with none of the three client strings every reader falls back to English, and Format says so for each", function()
	WithGlobals({ DUEL_WINNER_KNOCKOUT = NONE, DUEL_WINNER_RETREAT = NONE, RANDOM_ROLL_RESULT = NONE }, function()
		Same(Duel("Torvin Hale has defeated Selka Drummond in a duel"), { "Torvin Hale", "Selka Drummond", "knockout" })
		Same(Duel("Selka Drummond has fled from Torvin Hale in a duel"), { "Torvin Hale", "Selka Drummond", "fled" })
		Same(Rolled("Torvin Hale rolls 3 (1-6)"), { "Torvin Hale", 3, 1, 6 })
		for key, fmt in pairs(ENGLISH) do
			local got, fallback = P.Format(key)
			eq(got, fmt, key); eq(fallback, true, key .. " says it fell back")
		end
		local got, fallback = P.Format("NO_SUCH_STRING")
		eq(got, nil, "a key with no English either"); eq(fallback, true)
		eq(P.Roll("Torvin Hale rolls 3 (1-6)", "%s: %d (%d-%d)"), nil, "a given format still wins over the fallback")
		Same(Rolled("Torvin Hale: 3 (1-6)", "%s: %d (%d-%d)"), { "Torvin Hale", 3, 1, 6 })
	end)
end)

test("1.2 ArenaParse: PropsOn feeds a fight's facts always in T, as a trial, and in L only with LIVE_PROPS on", function()
	local function On(...) return { P.PropsOn(...) } end
	Same(On("T"), { true, true }, "a rehearsal or test build")
	Same(On("T", false), { true, true }, "LIVE_PROPS off changes nothing in T")
	Same(On("T", true), { true, true })
	Same(On("L"), { false, false }, "live, LIVE_PROPS unset")
	Same(On("L", false), { false, false })
	Same(On("L", true), { true, false }, "live with LIVE_PROPS on: no trial")
	Same(On("L", 1), { false, false }, "only exactly true switches it on")
	Same(On("L", "on"), { false, false })
	for _, mode in ipairs({ "l", "t", "X", "", 1 }) do
		Same(On(mode, true), { false, false }, tostring(mode))
	end
	Same(On(nil, true), { false, false }, "no mode")
end)

test("1.2 ArenaParse: UNIT_COMBAT wounds give each side's first blood and biggest hit, in the side facts only", function()
	-- A wound names the fighter hit: the other fighter's side dealt it.
	local f = P.New(A, B, 100)
	eq(f:Wound(101, B, "MISS", "", 0), "strike", "an attack on B that missed: A's side struck first")
	eq(f:Wound(102, A, "WOUND", "", 150), "wound", "A took 150: B's side drew first blood")
	eq(f:Wound(103, B, "WOUND", "CRITICAL", 900), "wound")
	eq(f:Wound(104, A, "WOUND", "CRUSHING", 400), "wound")
	eq(f:Wound(105, B, "WOUND", "GLANCING", 60), "wound")
	local facts = f:Finish(130)
	local side = facts.side
	eq(side.first.side, A); eq(side.first.t, 101); eq(side.first.subevent, "MISS"); eq(side.first.guid, nil, "UNIT_COMBAT names no source")
	eq(side.firstBlood.side, B); eq(side.firstBlood.t, 102); eq(side.firstBlood.amount, 150); eq(side.firstBlood.critical, false)
	eq(side.firstBlood.subevent, "WOUND"); eq(side.firstBlood.guid, nil)
	eq(side.best[A].amount, 900, "the biggest wound B took"); eq(side.best[A].critical, true)
	eq(side.best[B].amount, 400, "a crushing blow is no critical"); eq(side.best[B].critical, false)
	eq(side.biggest.side, A); eq(side.biggest.amount, 900); eq(side.tie, nil)
	eq(side.duration, 29, "from the first strike on either")
	eq(side.firstBloodTie, nil); eq(facts.feed, "unit")
	-- the strict facts need a source GUID: none
	eq(facts.first, nil); eq(facts.firstBlood, nil); eq(facts.biggest, nil); eq(facts.tie, nil); eq(facts.duration, nil)
	eq(next(facts.best), nil)
	-- and no interference can be read from them
	eq(facts.interfered, false); eq(#facts.outsiders, 0); eq(#facts.touched, 0)
	eq(facts.secret, nil); eq(facts.late, 0); eq(facts.overflow, nil)
end)

test("1.2 ArenaParse: one wound reported through two of a fighter's tokens at one time counts once", function()
	-- party1 and target are both Torvin: the client fires UNIT_COMBAT for each, in one frame.
	local f = P.New(A, B, 0)
	eq(f:Wound(5, A, "WOUND", "", 300), "wound")
	eq(f:Wound(5, A, "WOUND", "", 300), "wound", "the same wound again: its kind, nothing more")
	eq(f:Wound(5, B, "WOUND", "", 300), "wound", "the other fighter's own wound at that time")
	eq(f:Wound(5, A, "DODGE", "", 0), "strike", "another event on him at that time")
	eq(f:Wound(7, A, "WOUND", "", 300), "wound", "the same amount later is a new wound")
	-- every one of them after the result: each counted once as late
	eq(f:Finish(4).late, 4, "five fed at 5 and 7, one of them twice")
	-- the facts: 300 each way is a tie on the biggest, and the earlier first blood
	local g = P.New(A, B, 0)
	g:Wound(5, A, "WOUND", "", 300)
	g:Wound(5, A, "WOUND", "", 300)
	g:Wound(6, B, "WOUND", "", 300)
	local facts = g:Finish(10)
	eq(facts.side.tie, true); eq(facts.side.biggest, nil)
	eq(facts.side.firstBlood.side, B); eq(facts.side.firstBlood.t, 5)
end)

test("1.2 ArenaParse: what UNIT_COMBAT can't place is left out; an attack that did no damage is a strike", function()
	local f = P.New(A, B, 100)
	eq(f:Wound(99, A, "WOUND", "", 500), nil, "before the bell")
	eq(f:Wound(101, A, "HEAL", "", 500), nil, "a heal: his own or anyone's")
	eq(f:Wound(101, A, "ENERGIZE", "", 50), nil)
	eq(f:Wound(101, A, "SPLASH", "", 50), nil, "an event the client doesn't send")
	eq(f:Wound(101, A, nil, "", 50), nil)
	eq(f:Wound(101, C, "WOUND", "", 500), nil, "a bystander")
	eq(f:Wound(101, nil, "WOUND", "", 500), nil)
	eq(f:Wound("101", A, "WOUND", "", 500), nil, "a time that is a string")
	eq(f:Wound(0 / 0, A, "WOUND", "", 500), nil)
	for _, ev in ipairs({ "DODGE", "PARRY", "BLOCK", "BLOCK_REDUCED", "RESIST", "IMMUNE", "ABSORB", "DEFLECT", "REFLECT", "EVADE", "INTERRUPT" }) do
		eq(f:Wound(102, B, ev, "", 0), "strike", ev)
	end
	eq(f:Wound(103, A, "WOUND", "ABSORB", 0), "strike", "absorbed whole")
	eq(f:Wound(103, A, "WOUND", "", -5), "strike")
	eq(f:Wound(103, A, "WOUND", "", "lots"), "strike", "an amount that is no number")
	eq(f:Wound(103, A, "WOUND", "", 0 / 0), "strike")
	local facts = f:Finish(110)
	eq(facts.side.first.side, A, "the attacks on B came first"); eq(facts.side.first.t, 102)
	eq(facts.side.firstBlood, nil); eq(facts.side.biggest, nil); eq(next(facts.side.best), nil)
	eq(facts.side.duration, 8)
	-- closed at the result: a wound fed later changes nothing
	eq(f:Wound(105, A, "WOUND", "", 9000), nil)
	eq(f:Finish(110).side.firstBlood, nil)
end)

print("ArenaParse: the review of the arena's parser (secrets, ties, LIVE_PROPS per kind, one feed per fight)")

-- Plain Lua has no secret values: this one errors on every use (a string operation, a
-- comparison, a concatenation), as a secret does in the game, and issecretvalue names it.
local function Boom() error("a use of a secret value", 2) end
local SECRET = setmetatable({}, { __index = Boom, __tostring = Boom, __concat = Boom, __lt = Boom, __le = Boom, __eq = Boom })
local function Secrets(fn) WithGlobals({ issecretvalue = function(v) return rawequal(v, SECRET) end }, fn) end
-- Wound's and Feed's two results as one string: "wound/nil", "nil/secret", "nil/nil".
local function Said(kind, why) return tostring(kind) .. "/" .. tostring(why) end

test("1.2 ArenaParse: a secret GUID, a fighter's secret event, or a secret flag or amount on his WOUND says \"secret\" and the facts keep its time", function()
	-- Review of the arena's parser, finding 2: each source on a fight of its own (the flag, event and GUID were
	-- fed after an earlier secret, so recording only the amount's passed), and finding 3: the
	-- facts give the time, where they said `true`, so first blood read before it still stands.
	Secrets(function()
		for _, case in ipairs({
			{ "the GUID", SECRET, "WOUND", "", 300 },
			{ "a fighter's event", A, SECRET, "", 300 },
			{ "the flag of his WOUND", A, "WOUND", SECRET, 300 },
			{ "the amount of his WOUND", A, "WOUND", "", SECRET },
		}) do
			local f = P.New(A, B, 100)
			eq(Said(f:Wound(102, B, "WOUND", "", 80)), "wound/nil", case[1] .. ": one read before it")
			eq(Said(f:Wound(104, case[2], case[3], case[4], case[5])), "nil/secret", case[1])
			eq(Said(f:Wound(106, B, "WOUND", "", 250)), "wound/nil", case[1] .. ": the next one still reads")
			local facts = f:Finish(110)
			eq(facts.secret, 104, case[1] .. ": its time")
			eq(facts.side.firstBlood.t, 102, case[1] .. ": first blood came before it")
			eq(facts.side.first.t, 102); eq(facts.side.biggest.amount, 250, case[1] .. ": what could be read")
			eq(facts.feed, "unit")
		end
	end)
end)

test("1.2 ArenaParse: a secret the facts don't need (a bystander's token, a heal, a miss's amount) leaves them whole", function()
	-- Review of the arena's parser, finding 1: every value was checked for a secret before the GUID and the
	-- event were, so a bystander's secret amount (a nameplate nearby) or a fighter's heal with a
	-- secret amount said "secret", and the facts' `secret` voided first blood and the biggest hit.
	Secrets(function()
		local f = P.New(A, B, 100)
		eq(Said(f:Wound(101, C, "WOUND", "", SECRET)), "nil/nil", "a bystander's secret amount")
		eq(Said(f:Wound(101, C, "WOUND", SECRET, 40)), "nil/nil", "a bystander's secret flag")
		eq(Said(f:Wound(101, C, SECRET, "", 40)), "nil/nil", "a bystander's secret event")
		eq(Said(f:Wound(102, A, "HEAL", "", SECRET)), "nil/nil", "a fighter's heal with a secret amount")
		eq(Said(f:Wound(102, A, "ENERGIZE", SECRET, SECRET)), "nil/nil")
		eq(Said(f:Wound(103, B, "MISS", SECRET, SECRET)), "strike/nil", "a miss needs neither its flag nor its amount")
		eq(Said(f:Wound(104, A, "WOUND", "", 90)), "wound/nil")
		local facts = f:Finish(110)
		eq(facts.secret, nil, "nothing the facts need was unread")
		eq(facts.side.first.t, 103); eq(facts.side.first.side, A)
		eq(facts.side.firstBlood.side, B); eq(facts.side.biggest.amount, 90)
	end)
end)

test("1.2 ArenaParse: the facts keep the earliest secret in the window, fed in any order, at the bell and at the result included", function()
	-- Review of the arena's parser, finding 2: keeping the latest secret, or leaving out one at the result's
	-- own time or at the bell's, passed.
	Secrets(function()
		local f = P.New(A, B, 100)
		f:Wound(108, A, "WOUND", "", SECRET)
		f:Wound(103, B, "WOUND", "", SECRET)   -- the earliest, fed after a later one
		f:Wound(105, A, "WOUND", "", SECRET)
		eq(f:Finish(110).secret, 103)
		-- one in the window, then one after the result: the one in the window stands
		local g = P.New(A, B, 100)
		g:Wound(105, A, "WOUND", "", SECRET)
		g:Wound(120, A, "WOUND", "", SECRET)
		eq(g:Finish(110).secret, 105)
		-- only after the result: none
		local h = P.New(A, B, 100)
		h:Wound(101, B, "WOUND", "", 40)
		eq(Said(h:Wound(120, A, "WOUND", "", SECRET)), "nil/secret")
		eq(h:Finish(110).secret, nil)
		-- at the result's own time, and at the bell's
		local i = P.New(A, B, 100)
		i:Wound(110, A, "WOUND", "", SECRET)
		eq(i:Finish(110).secret, 110, "at the result")
		local j = P.New(A, B, 100)
		eq(Said(j:Wound(99.5, A, "WOUND", "", SECRET)), "nil/nil", "before the bell: nothing, and no reason")
		eq(Said(j:Wound(100, A, "WOUND", "", SECRET)), "nil/secret", "at the bell")
		eq(j:Finish(110).secret, 100)
	end)
	-- a client without issecretvalue reads every value
	WithGlobals({ issecretvalue = NONE }, function()
		local f = P.New(A, B, 0)
		eq(f:Wound(1, A, "WOUND", "", 70), "wound")
		eq(f:Finish(2).secret, nil)
	end)
end)

test("1.2 ArenaParse: wounds fed out of time order give the earliest strike and first blood; a wound at the bell counts", function()
	-- Review of the arena's parser, finding 2: keeping the first fed passed, and so did leaving out the bell.
	local f = P.New(A, B, 100)
	eq(f:Wound(109, A, "WOUND", "", 50), "wound")
	eq(f:Wound(107, B, "PARRY", "", 0), "strike")
	eq(f:Wound(108, B, "WOUND", "", 70), "wound")
	local facts = f:Finish(110)
	eq(facts.side.first.t, 107); eq(facts.side.first.side, A); eq(facts.side.first.subevent, "PARRY")
	eq(facts.side.firstBlood.t, 108); eq(facts.side.firstBlood.side, A); eq(facts.side.firstBlood.amount, 70)
	eq(facts.side.duration, 3)
	local g = P.New(A, B, 100)
	eq(g:Wound(99.999, A, "WOUND", "", 500), nil, "just before the bell")
	eq(g:Wound(100, B, "WOUND", "", 20), "wound", "at the bell itself")
	facts = g:Finish(105)
	eq(facts.side.firstBlood.t, 100); eq(facts.side.duration, 5); eq(facts.side.biggest.amount, 20)
end)

test("1.2 ArenaParse: wounds past MAX_HITS are counted, not kept, and flagged", function()
	-- Review of the arena's parser, finding 2: Wound without its MAX_HITS check passed.
	local maxHits = P.MAX_HITS
	local ok, err = pcall(function()
		P.MAX_HITS = 2
		local f = P.New(A, B, 0)
		eq(f:Wound(1, A, "WOUND", "", 10), "wound")
		eq(f:Wound(2, B, "WOUND", "", 20), "wound")
		eq(f:Wound(3, A, "WOUND", "", 30), "wound", "counted, not kept")
		local facts = f:Finish(10)
		eq(facts.overflow, true)
		eq(facts.side.biggest.amount, 20, "from what was kept")
		eq(facts.side.firstBlood.t, 1, "first blood is kept apart from the list")
	end)
	P.MAX_HITS = maxHits
	if not ok then error(err, 0) end
end)

test("1.2 ArenaParse: at one time, two WOUNDs that differ only in flagText, or two events, are two", function()
	-- Review of the arena's parser, finding 2: a key without the flag or without the event passed. A crit and a
	-- plain hit of one amount in one frame (a fighter and his pet) are two wounds.
	local f = P.New(A, B, 0)
	eq(f:Wound(5, A, "WOUND", "", 300), "wound")
	eq(f:Wound(5, A, "WOUND", "CRITICAL", 300), "wound")
	eq(f:Wound(5, A, "WOUND", "CRITICAL", 300), "wound", "the crit again, through another token")
	eq(f:Wound(5, A, "DODGE", "", 0), "strike")
	eq(f:Wound(5, A, "PARRY", "", 0), "strike")
	eq(f:Wound(5, A, "WOUND", "", 0), "strike", "absorbed whole")
	eq(f:Wound(5, A, "WOUND", "ABSORB", 0), "strike", "the same, with the flag the client gives it")
	eq(f:Finish(4).late, 6, "seven fed after the result, one of them twice")
end)

test("1.2 ArenaParse: first blood both ways at one time is a tie, in each view that sees it", function()
	-- Review of the arena's parser, finding 4: GetTime() has a frame's resolution, so both opening wounds can
	-- share one time, and first blood went to whichever UNIT_COMBAT came first with no sign of it.
	local f = P.New(A, B, 0)
	f:Wound(5, B, "WOUND", "", 10)
	f:Wound(5, A, "WOUND", "", 60)
	local facts = f:Finish(10)
	eq(facts.side.firstBlood.side, A, "the one fed first, as before"); eq(facts.side.firstBloodTie, true)
	eq(facts.firstBlood, nil); eq(facts.firstBloodTie, nil, "Wound gives no strict first blood")
	-- one fighter's wounds (through two tokens, or two of them) and a strike on the other at that
	-- time are no tie
	local g = P.New(A, B, 0)
	g:Wound(5, A, "WOUND", "", 10)
	g:Wound(5, A, "WOUND", "", 10)
	g:Wound(5, A, "WOUND", "CRITICAL", 20)
	g:Wound(5, B, "DODGE", "", 0)
	g:Wound(6, B, "WOUND", "", 30)
	facts = g:Finish(10)
	eq(facts.side.firstBlood.side, B); eq(facts.side.firstBloodTie, nil)
	-- both ways later than first blood is no tie on it; an earlier wound fed late clears one
	local h = P.New(A, B, 0)
	h:Wound(6, A, "WOUND", "", 10)
	h:Wound(7, A, "WOUND", "", 10)
	h:Wound(7, B, "WOUND", "", 10)
	eq(h:Finish(10).side.firstBloodTie, nil)
	local i = P.New(A, B, 0)
	i:Wound(7, A, "WOUND", "", 10)
	i:Wound(7, B, "WOUND", "", 10)
	i:Wound(6, A, "WOUND", "", 10)
	facts = i:Finish(10)
	eq(facts.side.firstBlood.t, 6); eq(facts.side.firstBloodTie, nil)
	-- after the result: no first blood, and no tie
	local j = P.New(A, B, 0)
	j:Wound(12, A, "WOUND", "", 10)
	j:Wound(12, B, "WOUND", "", 10)
	facts = j:Finish(10)
	eq(facts.side.firstBlood, nil); eq(facts.side.firstBloodTie, nil)
	-- the combat log's: both views; a pet's hit is its side's, never its master's own
	local k = P.New(A, B, 0)
	k:Feed(11, "SWING_DAMAGE", B, A, 20)
	k:Feed(11, "SWING_DAMAGE", A, B, 30)
	facts = k:Finish(20)
	eq(facts.firstBlood.guid, B); eq(facts.firstBloodTie, true); eq(facts.side.firstBloodTie, true)
	local l = P.New(A, B, 0)
	l:Own(PET, A)
	l:Feed(5, "SWING_DAMAGE", PET, B, 50)
	l:Feed(5, "SWING_DAMAGE", B, A, 40)
	facts = l:Finish(10)
	eq(facts.firstBlood.guid, B); eq(facts.firstBloodTie, nil, "strict: the pet's hit is no fighter's own")
	eq(facts.side.firstBlood.guid, PET); eq(facts.side.firstBloodTie, true)
end)

test("1.2 ArenaParse: PropsOn takes LIVE_PROPS per kind (DU, FB, BH), as the design sets it", function()
	-- Review of the arena's parser, finding 5: only `true` switched props on, so the table the markets spec
	-- names (LIVE_PROPS.DU/FB/BH = true) left every prop off without an error.
	local function On(...) return { P.PropsOn(...) } end
	local all = { DU = true, FB = true, BH = true }
	for _, kind in ipairs({ "DU", "FB", "BH" }) do
		Same(On("L", all, kind), { true, false }, kind)
		Same(On("L", true, kind), { true, false }, kind .. ", true for all three")
		Same(On("L", nil, kind), { false, false }, kind .. ", LIVE_PROPS unset")
		Same(On("T", nil, kind), { true, true }, kind .. " in T")
		Same(On("X", all, kind), { false, false }, kind .. " in no mode of ours")
	end
	Same(On("L", all), { true, false }, "any of them on: the fight is fed")
	-- the duration's check passed, the amounts' not yet
	local du = { DU = true, FB = false }
	Same(On("L", du, "DU"), { true, false })
	Same(On("L", du, "FB"), { false, false })
	Same(On("L", du, "BH"), { false, false })
	Same(On("L", du), { true, false }, "the fight is still fed, for the duration")
	Same(On("L", { DU = 1, FB = "yes", BH = {} }), { false, false }, "only exactly true")
	Same(On("L", { DU = 1, FB = "yes" }, "FB"), { false, false })
	Same(On("L", {}), { false, false })
	-- a kind that is no prop is never on, not even in T
	for _, kind in ipairs({ "KO", "fb", "", 1, true }) do
		Same(On("T", true, kind), { false, false }, tostring(kind))
		Same(On("L", { [kind] = true }, kind), { false, false }, tostring(kind))
	end
end)

test("1.2 ArenaParse: one feed per fight: after Feed's events Wound is refused, and after Wound's Feed is", function()
	-- Review of the arena's parser, finding 6. This test fed both into one fight and called it supported. They
	-- are two clocks (the log's timestamps and GetTime()), and Wound counts a third party's hit and
	-- a fighter's own for the other fighter, which Feed leaves out, so a fight takes one of them.
	local f = P.New(A, B, 0)
	eq(Said(f:Feed(10, "SWING_DAMAGE", C, D, 200)), "nil/nil", "an event that counts for nothing holds no feed")
	eq(Said(f:Wound(10, B, "HEAL", "", 200)), "nil/nil", "nor does a wound that counts for nothing")
	eq(f:Feed(10, "SWING_DAMAGE", A, B, 200), "hit")
	eq(Said(f:Wound(11, A, "WOUND", "CRITICAL", 999)), "nil/feed", "the log's fight")
	eq(Said(P.Wound(f, 12, B, "MISS", "", 0)), "nil/feed", "the module-level function is the fight's")
	eq(f:Feed(13, "SWING_DAMAGE", B, A, 50), "hit", "Feed still reads")
	local facts = f:Finish(20)
	eq(facts.feed, "log")
	eq(facts.side.best[B].amount, 50, "the refused 999 is not in it"); eq(facts.side.first.t, 10)
	local g = P.New(A, B, 0)
	eq(g:Wound(10, B, "WOUND", "", 200), "wound")
	eq(Said(g:Feed(9, "SWING_DAMAGE", A, B, 500)), "nil/feed", "the wounds' fight")
	eq(Said(g:Feed(9, "SPELL_SUMMON", A, TOTEM)), "nil/feed")
	eq(Said(g:Feed(9, "SPELL_HEAL", C, A, 500)), "nil/feed")
	facts = g:Finish(20)
	eq(facts.feed, "unit"); eq(facts.side.first.t, 10); eq(facts.side.best[A].amount, 200)
	eq(facts.first, nil); eq(facts.interfered, false)
	-- a secret wound makes it Wound's too
	Secrets(function()
		local h = P.New(A, B, 0)
		eq(Said(h:Wound(5, A, "WOUND", "", SECRET)), "nil/secret")
		eq(Said(h:Feed(6, "SWING_DAMAGE", A, B, 10)), "nil/feed")
		eq(h:Finish(10).feed, "unit")
	end)
	-- nothing counted: no feed; a closed fight gives no reason
	eq(P.New(A, B):Finish(5).feed, nil)
	eq(Said(g:Feed(15, "SWING_DAMAGE", A, B, 10)), "nil/nil")
end)

test("1.2 ArenaParse: loading the module writes no global, and its code names no frame, event, timer, message or saved data", function()
	local before = {}
	for k in pairs(_G) do before[k] = true end
	local fresh = {}
	assert(loadfile(H.ADDON_DIR .. "ArenaParse.lua"))("Olympus", fresh)
	for k in pairs(_G) do eq(before[k], true, "a new global: " .. tostring(k)) end
	eq(type(fresh.ArenaParse), "table")
	local file = assert(io.open(H.ADDON_DIR .. "ArenaParse.lua", "rb"))
	local code = file:read("*a"):gsub("%-%-[^\n]*", "")   -- the code, not its comments
	file:close()
	for _, word in ipairs({ "CreateFrame", "RegisterEvent", "RegisterUnitEvent", "C_Timer", "SendAddonMessage", "SendChatMessage",
		"ns.On", "ns.Every", "ns.db", "ns.rdb", "OlympusDB", "OlympusArenaDB", "Comm", "setglobal", "rawset" }) do
		eq(code:find(word, 1, true), nil, word)
	end
end)
