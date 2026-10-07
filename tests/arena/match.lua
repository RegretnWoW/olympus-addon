-- 1.2, matchmaking: finding an opponent (ArenaMatch.lua, the design), on the test world with its
-- matchmaking extension (tests/arena/lib/match-world.lua). Every name is invented; every expected
-- number below is worked out by hand in its comment.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/match-world.lua"))(H)
local CH = assert(loadfile(H.ROOT .. "tests/arena/lib/chat-host.lua"))(H)
local L = H.ns.L

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end
local function Printed(c, text)
	local n = 0
	for _, line in ipairs(c.printed) do if line == text or line:find(text, 1, true) then n = n + 1 end end
	return n
end
local function Fill(text, t) return (text:gsub("{(%w+)}", function(k) return t[k] ~= nil and tostring(t[k]) or "{" .. k .. "}" end)) end
local function HasAction(view, key)
	for _, a in ipairs(view and view.actions or {}) do if a.key == key then return true end end
	return false
end

-- Two players in Stranglethorn Vale (map 1434, the Eastern Kingdoms, continent 0), 400 yd apart:
-- the seeker at (-13000, 300): cells floor((-13000 + 20000) / 400) = 17 ("h") and
-- floor(20300 / 400) = 50 ("1e"), centre (-13000, 200); the other at (-13400, 250): cells 16 ("g")
-- and 50 ("1e"), centre (-13400, 200). Gurubashi Arena (-13202.2, 268.2) is 213.4 yd from the
-- first centre and 209.2 from the second: the fairest place for a casual duel. For a staked duel
-- (no free-for-all ground) it is Booty Bay (-14457.2, 497.9): 1487.3 and 1098.4 yd, where the
-- Stormwind gate is 3885 yd away and Goldshire 3548.
local SEEKER = { cont = 0, wx = -13000, wy = 300 }
local OTHER = { cont = 0, wx = -13400, wy = 250 }
local CASUAL = { game = "d", kind = "c", level = 5, reach = "z" }

local function Pair(opts)
	opts = opts or {}
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = opts.a or SEEKER, level = opts.aLevel })
	local b = MW.Client(w, "Parric Stowe", { pos = opts.b or OTHER, findable = opts.findable ~= false, level = opts.bLevel, class = "MAGE" })
	return w, a, b
end
-- The stake checks the fights part and the Bone Throw tables answer through Arena.Can, as stand-ins in their own call shapes:
-- the fights part's F.CanChallenge(opponent, opts) and the Bone Throw tables' FT.CanCreate(opts) (its 1.2 branch
-- ArenaFights.lua, its 1.2 branch FarkleTable.lua). Each call is recorded in c.checks, and a
-- call of another shape (the name not first, no opts.match, a stake not in whole silver or under
-- 1 silver) is recorded in c.badChecks, which MW.NoErrors fails on (Arena.Can would swallow an
-- error). o.rule(name, stake) answers for the rest (else: yes, or no with `why`); o.today: as
-- their branches answer today, "opponent" or "guest" before anything else while nobody is named;
-- o.tavern: the Bone Throw tables' inn rule for a stake (the design), which a match never meets (the two are not there).
local function StakesOK(c, yes, why, o)
	o = o or {}
	c.checks, c.badChecks = {}, {}
	local function Bad(what) c.badChecks[#c.badChecks + 1] = what end
	local function Stake(opts, what)
		if type(opts) ~= "table" or opts.match ~= true then Bad(what .. ": opts.match") return end
		if type(opts.stake) ~= "number" or opts.stake < 100 or opts.stake % 100 ~= 0 then Bad(what .. ": the stake " .. tostring(opts.stake)) end
	end
	local function Rule(name, stake)
		if o.rule then return o.rule(name, stake) end
		return yes ~= false, why
	end
	c.Arena.Action("fights.challenge", function(opponent, opts, extra)
		if (opponent ~= nil and type(opponent) ~= "string") or extra ~= nil then Bad("fights.challenge: (opponent, opts)") end
		Stake(opts, "fights.challenge")
		c.checks[#c.checks + 1] = { game = "d", name = opponent, stake = opts and opts.stake }
		if o.today and opponent == nil then return false, "opponent" end
		return Rule(opponent, opts and opts.stake)
	end, function() end)
	c.Arena.Action("farkle.create", function(opts, extra)
		if type(opts) ~= "table" or extra ~= nil or (opts.guest ~= nil and type(opts.guest) ~= "string") then Bad("farkle.create: (opts)") end
		Stake(opts, "farkle.create")
		local guest = type(opts) == "table" and opts.guest or nil
		c.checks[#c.checks + 1] = { game = "b", name = guest, stake = type(opts) == "table" and opts.stake or nil }
		if o.today and guest == nil then return false, "guest" end
		if o.tavern and guest then return false, "tavern-rest" end
		return Rule(guest, opts.stake)
	end, function() end)
end
-- The recorded checks, as "game name stake" (the name's first word, "-" for none).
local function Checks(c)
	local out = {}
	for _, k in ipairs(c.checks or {}) do out[#out + 1] = ("%s %s %d"):format(k.game, k.name and k.name:match("^(%S+)") or "-", k.stake or -1) end
	return out
end
local function HasCheck(c, text)
	for _, k in ipairs(Checks(c)) do if k == text then return true end end
	return false
end
-- Saved data that survives a login (the Forever beta loses it: Arena.Persists), and the stake
-- checks' yes: staked matches possible.
local function HighCap(c)
	rawset(c.ns, "Standing", { Cap = function(kind) return kind == "bet" and 100000000 or 0 end })
end
local function Staked(w, ...)
	for _, c in ipairs({ ... }) do
		MW.Reload(w, c)
		StakesOK(c)
		-- The integrated wallet now supplies the real starting tier (5g). Tests which exercise a
		-- wider negotiated range give these invented clients an explicit high cap; the dedicated
		-- cap cases below replace this stand-in with their exact boundary.
		HighCap(c)
		assert(c.Arena.Persists(), "persists")
	end
end
-- The one door every pending conversation opens through (ChatRooms.OpenMatter), loaded into the
-- client as the game loads it before the Arena's files, and the Chat page's room and tab calls it
-- uses, each written down (tests/arena/lib/chat-host.lua).
local function MatchHost(w, c)
	CH.WithRooms(w, c)
	return CH.Host(c)
end
-- a searches, b says Let's go: the match's id.
local function Matched(w, a, b, start)
	assert(a.Match.Start(start or CASUAL))
	w:Run(6)
	local r = assert(MW.Last(w, a, "R"), "a request")
	MW.Answer(w, b, "yes")
	w:Run(0)
	return (r:match("^R~(M[0-9a-z]+)~"))
end

print("ArenaMatch: finding an opponent")

test("1.2 matchmaking: a casual duel, end to end: the ask, the answer, the request, Let's go with its whisper and invite, On my way", function()
	local w, a, b = Pair()
	eq(a.Match.Start(CASUAL), true)
	w:Run(0)
	-- The ask: qid 12345 = "9ix"; cont 0; map 1434 = "13u"; no layer; level 60 = "1o", 55..65 =
	-- "1j".."1t"; the zone's crowd max(1, 0) x 4 = 4, so 600 / 4 = 150, at most 100 = "2s".
	eq(MW.AM(w, a)[1], "Q~9ix~d~c~Olympus Ember~0~13u~0~1o~1j~1t~z~2s")
	eq(w:Sent{ from = a, type = "AM" }[1].dist, "CHANNEL")
	eq(a.Match.View().line, "Searching nearby...")
	-- On her card, not in chat as well.
	assert(MW.HasLine(a, "Searching nearby..."))
	eq(Printed(a, "Searching nearby..."), 0)
	-- Parric answers after 0.2 s (the draw 0): findable, in the zone, level 60, a mage (8), duels.
	w:Run(1)
	eq(MW.AM(w, b)[1], "O~9ix~f~Olympus Ember~1~1o~8~d~c~0")
	eq(w:Sent{ from = b, type = "AM" }[1].target, a.name)
	-- The window closes after 4 s: the request, with Lida's cell.
	w:Run(5)
	local r = MW.Last(w, a, "R")
	local mid = r:match("^R~(M[0-9a-z]+)~")
	assert(mid, r)
	eq(r, "R~" .. mid .. "~9ix~d~c~0~0~1o~1~h~1e~0")
	-- Parric's popup, with the place both clients get from Places.Fair on the wire's cells: 400 yd
	-- from Lida's centre (403 rounded to 50), 198.6 from Parric to the arena, 213.4 from Lida's centre.
	local p = MW.Popup(b)
	assert(p, "the popup")
	eq(p.a, "Lida Fenn (60 Warrior) wants a casual duel, about 400 yd away. Meet at Gurubashi Arena, Stranglethorn Vale (30.6, 47.8)? About 200 yd for you, 200 for them.")
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~Y~arena_gurubashi~g~1e~13u~0~0~0~0")
	-- The opening whisper and the invite, inside the click.
	eq(#b.said, 1)
	eq(b.said[1].text, "Hi! Olympus matched us for a casual duel. Meet at Gurubashi Arena, Stranglethorn Vale (30.6, 47.8)? It's about halfway for us both. Reply here, or pick another spot in the Olympus window.")
	eq(b.said[1].kind, "WHISPER"); eq(b.said[1].to, "Lida Fenn")
	eq(b.invited[1], "Lida Fenn")
	eq(b.said[1].global, nil, "C_ChatInfo.SendChatMessage where the client has it")
	-- Both have the match. Lida's card: "{name} is in!" and the way: from (-13000, 300) the arena
	-- is 202.2 yd south (the first value grows to the north) and 31.8 east (the second grows to
	-- the west), 204.7 yd rounded to 10: "200 yd south".
	eq(a.Match.View().state, "match"); eq(b.Match.View().state, "match")
	eq(a.Match.View().match.place.id, "arena_gurubashi")
	eq(a.Match.View().line, "Meeting Parric Stowe at Gurubashi Arena")
	eq(MW.Card(a).title.text, "Parric Stowe is in!")
	eq(MW.Card(b).title.text, "Meeting Lida Fenn")
	assert(MW.HasLine(a, "Gurubashi Arena: 200 yd south"), table.concat(MW.Lines(a), " | "))
	eq(MW.Buttons(a), "block cancel done onway other reply room")
	eq(MW.Buttons(b), "block cancel done other reply room")
	assert(MW.HasLine(b, "Waiting for Lida Fenn to agree on the spot."), table.concat(MW.Lines(b), " | "))
	assert(MW.HasLine(a, "Right-click Parric Stowe's portrait and pick Duel."))
	assert(MW.HasLine(a, "Accept Parric Stowe's invite: it lets you find each other."))
	MW.Press(w, a, "onway")
	w:Run(0)
	eq(a.said[1].text, "Gurubashi Arena works for me. On my way!")
	eq(MW.Last(w, a, "P"), "P~" .. mid .. "~0~arena_gurubashi~A")
	eq(a.Match.View().match.fixed, true); eq(b.Match.View().match.fixed, true)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: a staked duel: the ask carries no amount, the request the range, the answer the fair place off free-for-all ground; the whisper names no stake", function()
	local w, a, b = Pair({ findable = false })
	Staked(w, a, b)
	b.Match.SetFindable(true, { d = true, b = true, staked = true })
	-- 50g to 100g: 5000 to 10000 silver, "3uw" and "7ps" in base 36; any level: 1 to 100 ("1", "2s").
	eq(a.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0, reach = "z" }), true)
	w:Run(0)
	local q = MW.AM(w, a)[1]
	eq(q, "Q~9ix~d~s~Olympus Ember~0~13u~0~1o~1~2s~z~2s")
	assert(not w:ChannelText():find("3uw", 1, true) and not w:ChannelText():find("7ps", 1, true), "no amount on the channel")
	w:Run(6)
	-- Parric offers what both want: a duel, staked (his answer names only the overlap).
	eq(MW.AM(w, b)[1], "O~9ix~f~Olympus Ember~1~1o~8~d~s~0")
	local r = MW.Last(w, a, "R")
	local mid = r:match("^R~(M[0-9a-z]+)~")
	eq(r, "R~" .. mid .. "~9ix~d~s~3uw~7ps~1o~1~h~1e~0")
	-- Booty Bay: 1085.9 yd from Parric (1100), 1487.3 from Lida's centre (1500).
	eq(MW.Popup(b).a, "Lida Fenn (60 Warrior) wants a duel with a stake of 50g-100g, about 400 yd away. Meet at Booty Bay, Stranglethorn Vale (27.0, 77.3)? About 1100 yd for you, 1500 for them.")
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~Y~spot_booty_bay~g~1e~13u~0~3uw~7ps~0")
	eq(b.said[1].text, "Hi! Olympus matched us for a duel with a stake. Meet at Booty Bay, Stranglethorn Vale (27.0, 77.3)? It's about halfway for us both. The stake is set in the Olympus window only, never in whispers.")
	assert(not b.said[1].text:find("%d+g"), "no amount in a whisper")
	-- The card: the safety line and [Challenge]; no casual-duel line.
	assert(MW.HasLine(a, "Olympus shows matches and stakes only in this window. Never trade gold outside the challenge."))
	assert(not MW.HasLine(a, "Right-click Parric Stowe's portrait and pick Duel."))
	eq(MW.Buttons(a), "block cancel challenge onway other reply room")
	eq(a.Match.View().match.lo, 500000); eq(a.Match.View().match.hi, 1000000)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the hand-off: [Challenge] opens the screens' dialog with the lowest agreed stake and the match's id; Vet holds the agreed range on the other side, in any mode", function()
	local w, a, b = Pair({ findable = false })
	Staked(w, a, b)
	b.Match.SetFindable(true, { d = true, staked = true })
	local mid = Matched(w, a, b, { game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 })
	eq(b.Match.View().match.lo, 500000, "a findable player takes the seeker's range")
	-- the screens' challenge dialog (a stand-in on the companion's table).
	local got
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	a.ns.Arena.ui.Challenge = function(name, prefill) got = { name = name, prefill = prefill } end
	MW.Press(w, a, "challenge")
	eq(got.name, b.name); eq(got.prefill.stake, 500000); eq(got.prefill.from, mid)
	eq(a.Match.View().match.handed, true)
	-- Parric's the fights part asks before showing Lida's challenge: 50g to 100g, the duel.
	eq(b.Match.Vet(a.name, "d", 499999), false)
	eq(select(2, b.Match.Vet(a.name, "d", 499999)), "m")
	eq(b.Match.Vet(a.name, "d", 1000001), false)
	eq(b.Match.Vet(a.name, "b", 100), false, "another game with a stake")
	eq(b.Match.Vet(a.name, "b", 0), true, "another game without one")
	eq(b.Match.Vet("Wenna Crale-Emberfall", "d", 99999999), true, "not a matched partner: not ours to say")
	local valid, receivedMid = b.Match.Vet(a.name, "d", 750000)
	eq(valid, true); eq(receivedMid, mid, "the receiver keeps the exact hand-off id without a wire change")
	eq(b.Match.View().match.handed, true, "the challenge came: handed over on his side too")
	-- The mode (direct, an arbiter, the wallet) is the dialog's: Vet does not ask (the design #2).
	MW.NoErrors(w)
end)

test("1.2 matchmaking: two searchers agree on the overlap of their stake ranges; no overlap is a no", function()
	local w, a, b = Pair({ findable = false })
	Staked(w, a, b)
	-- Parric searches first (70g to 200g), then Lida (50g to 100g): he answers her as a searcher,
	-- with his cell; she asks him; the range both allow is 70g to 100g.
	b.qid = 999
	eq(b.Match.Start({ game = "d", kind = "s", lo = 700000, hi = 2000000, level = 0 }), true)
	w:Run(30)
	eq(a.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 }), true)
	w:Run(1)
	eq(MW.Last(w, b, "O"), "O~9ix~s~Olympus Ember~1~1o~8~d~s~0~g~1e")
	w:Run(5)
	MW.Answer(w, b, "yes")
	w:Run(0)
	-- 7000 silver = "5eg", 10000 = "7ps".
	assert(MW.Last(w, b, "A"):find("~Y~spot_booty_bay~g~1e~13u~0~5eg~7ps~0$"), MW.Last(w, b, "A"))
	eq(a.Match.View().match.lo, 700000); eq(b.Match.View().match.hi, 1000000)
	-- No overlap: Wenna searches 200g to 300g, Idris 50g to 100g; she answers (an ask carries no
	-- amount), his request finds nothing both allow: A~N, and he passes her over for 30 min.
	local w2 = World.New()
	local c = MW.Client(w2, "Idris Vane", { pos = SEEKER })
	local d = MW.Client(w2, "Wenna Crale", { pos = OTHER })
	Staked(w2, c, d)
	d.qid = 77
	eq(d.Match.Start({ game = "d", kind = "s", lo = 2000000, hi = 3000000, level = 0 }), true)
	w2:Run(30)
	eq(c.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 }), true)
	w2:Run(6)
	local r = MW.Last(w2, c, "R")
	eq(MW.Last(w2, d, "A"), "A~" .. r:match("^R~(M[0-9a-z]+)~") .. "~N")
	eq(MW.Popup(d), nil)
	eq(c.Match.Barred(d.name), "declined")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: Bone Throw for practice: an inn, the practice whisper, the group Bone Throw needs", function()
	local w, a, b = Pair({ findable = false })
	b.Match.SetFindable(true, { d = false, b = true })
	local mid = Matched(w, a, b, { game = "b", kind = "c" })
	-- The Salty Sailor Tavern (-14457, 496.5) is the only inn of the Alliance or neutral ground
	-- on this continent within 1,500 yd.
	eq(a.Match.View().match.place.id, "inn_booty_bay")
	eq(b.said[1].text, "Hi! Olympus matched us for a practice Bones game. Meet at The Salty Sailor Tavern, Stranglethorn Vale (27.0, 77.3)? It's about halfway for us both.")
	eq(b.invited[1], "Lida Fenn")
	eq(MW.Buttons(a), "block cancel onway other reply room table")
	-- [Open the table]: the Bone Throw tables' create panel, pre-filled, through the screens' ArenaUI.BoneInvite (which
	-- finds the panel under its names: its 1.2 branch PagesPlayer.lua); else ArenaUI.CreateTable.
	local got, direct
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	a.ns.Arena.ui.BoneInvite = function(o) got = o end
	a.ns.Arena.ui.CreateTable = function(o) direct = o end
	MW.Press(w, a, "table")
	eq(got.guest, b.name); eq(got.stake, 0); eq(got.practice, true); eq(got.from, mid)
	eq(direct, nil, "the screens' way first")
	-- A companion without it: the create panel by its own name.
	a.ns.Arena.ui.BoneInvite = nil
	MW.Press(w, a, "table")
	eq(direct.guest, b.name); eq(direct.from, mid)
	-- A loaded companion with neither route: nothing is handed over.
	local w2, c, d = Pair({ findable = false })
	d.Match.SetFindable(true, { d = false, b = true })
	Matched(w2, c, d, { game = "b", kind = "c" })
	w2:As(c, function() assert(c.ns.Arena.LoadUI()) end)
	c.ns.Arena.ui.BoneInvite, c.ns.Arena.ui.CreateTable = nil, nil
	eq(select(2, w2:As(c, c.ns.ArenaMatch.HandOff)), "window")
	eq(c.Match.View().match.handed, false)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: Either: the seeker's pick, else the one game or kind the other offers, else a duel and casual; staked unavailable, Either is casual", function()
	local w, a, b = Pair({ findable = false })
	b.Match.SetFindable(true, { d = false, b = true })
	eq(a.Match.Start({ game = "e", kind = "e", level = 5 }), true)
	w:Run(0)
	-- Saved data is lost at every login here (Arena.Persists false): Either is casual.
	eq(MW.AM(w, a)[1]:match("^Q~9ix~(%a~%a)~"), "e~c")
	w:Run(6)
	-- Parric offers Bone Throw only, casual: the request resolves to it.
	eq(MW.Last(w, b, "O"), "O~9ix~f~Olympus Ember~1~1o~8~b~c~0")
	assert(MW.Last(w, a, "R"):find("^R~M[0-9a-z]+~9ix~b~c~0~0~"), MW.Last(w, a, "R"))
	-- Where stakes can be: Wenna searches staked Bone Throw only (10g to 20g); Idris searches
	-- Either, 5g to 15g; Wenna answers with her one game and kind: Bone Throw, staked, 10g to 15g.
	local w2 = World.New()
	local c = MW.Client(w2, "Idris Vane", { pos = SEEKER })
	local d = MW.Client(w2, "Wenna Crale", { pos = OTHER })
	Staked(w2, c, d)
	d.qid = 77
	eq(d.Match.Start({ game = "b", kind = "s", lo = 100000, hi = 200000, level = 0 }), true)
	w2:Run(30)
	eq(c.Match.Start({ game = "e", kind = "e", lo = 50000, hi = 150000, level = 0 }), true)
	w2:Run(0)
	eq(MW.AM(w2, c)[1]:match("^Q~9ix~(%a~%a)~"), "e~e")
	w2:Run(6)
	eq(MW.Last(w2, d, "O"), "O~9ix~s~Olympus Ember~1~1o~1~b~s~0~g~1e")
	-- 500 silver = "dw", 1500 = "15o".
	assert(MW.Last(w2, c, "R"):find("^R~M[0-9a-z]+~9ix~b~s~dw~15o~"), MW.Last(w2, c, "R"))
	MW.Answer(w2, d, "yes")
	w2:Run(0)
	-- 1000 silver = "rs".
	assert(MW.Last(w2, d, "A"):find("~rs~15o~0$"), MW.Last(w2, d, "A"))
	eq(c.Match.View().match.lo, 100000); eq(c.Match.View().match.hi, 150000)
	local prefix = "Hi! Olympus matched us for a Bones game. Meet at The"
	eq(d.said[1].text:sub(1, #prefix), prefix)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: close by (=): a casual duel under 300 yd of the seeker's centre; its popup and whisper; never on a capital's map", function()
	-- Parric at (-13100, 220): 102 yd from Lida's centre (-13000, 200), cells 17 and 50.
	local w, a, b = Pair({ b = { cont = 0, wx = -13100, wy = 220 } })
	local mid = Matched(w, a, b, CASUAL)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~Y~=~h~1e~13u~0~0~0~0")
	eq(b.shown[1].a, "Lida Fenn (60 Warrior) wants a casual duel, close by (about 100 yd). Meet right here?")
	eq(b.said[1].text, "Hi! Olympus matched us for a casual duel. We're close by, so let's meet right here. Once we're grouped we'll see each other on the map.")
	eq(a.Match.View().match.place.id, "=")
	assert(MW.HasLine(a, "Parric Stowe is close by."))
	-- On a capital's map it is a place instead: Lida in Stormwind City (1453), both by its gate.
	local w2 = World.New()
	local c = MW.Client(w2, "Lida Fenn", { pos = { cont = 0, wx = -9000, wy = 500 }, mapID = 1453 })
	local d = MW.Client(w2, "Parric Stowe", { pos = { cont = 0, wx = -9050, wy = 480 }, mapID = 1453, findable = true })
	Matched(w2, c, d, CASUAL)
	assert(MW.Last(w2, d, "A"):find("~Y~spot_stormwind_gate~"), MW.Last(w2, d, "A"))
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: the texts: each whisper exact; at most 255 bytes in English and Portuguese with every place's name; no amount; the place's name from its areaID", function()
	-- Both languages loaded into tables of their own (the Portuguese block under GetLocale "ptBR").
	local en, pt = {}, {}
	assert(loadfile(H.ADDON_DIR .. "Locales/ArenaMatchText.lua"))("Olympus", { L = en })
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaMatchText.lua"))("Olympus", { L = pt }) end)
	GetLocale = savedLocale
	assert(ok, err)
	local SAYS = { "MATCH_SAY_DUEL_CASUAL", "MATCH_SAY_DUEL_STAKED", "MATCH_SAY_BONE_GOLD", "MATCH_SAY_BONE_PRACTICE", "MATCH_SAY_CLOSE",
		"MATCH_SAY_ONWAY", "MATCH_SAY_OTHER", "MATCH_SAY_WHERE", "MATCH_SAY_CLOSEBY", "MATCH_SAY_CANCEL" }
	local w = World.New()
	local c = MW.Client(w, "Lida Fenn", {})
	local Places = c.ns.Places
	local longest = 0
	for _, Lx in ipairs({ en, pt }) do
		for _, key in ipairs(SAYS) do
			local text = assert(Lx[key], key)
			-- Only our own data goes in: a place, a zone, two coordinates, a game.
			for k in text:gmatch("{(%w+)}") do assert(k == "place" or k == "zone" or k == "x" or k == "y" or k == "game", key .. ": {" .. k .. "}") end
			for _, row in ipairs(Places.list) do
				for _, game in ipairs({ Lx.MATCH_SAY_GAME_DUEL, Lx.MATCH_SAY_GAME_BONE }) do
					local s = Fill(text, { place = row.name, zone = row.zone, x = "100.0", y = "100.0", game = game })
					assert(#s <= 255, key .. " with " .. row.id .. ": " .. #s .. " bytes")
					if #s > longest then longest = #s end
				end
			end
		end
	end
	assert(longest > 200, "the longest was measured: " .. longest)
	-- The exact English lines (the design).
	eq(en.MATCH_SAY_BONE_GOLD, "Hi! Olympus matched us for a Bones game. Meet at {place}, {zone} ({x}, {y})? It's about halfway for us both. The stake is set in the Olympus window only, never in whispers.")
	eq(en.MATCH_SAY_OTHER, "How about {place}, {zone} ({x}, {y}) instead?")
	eq(en.MATCH_SAY_WHERE, "How about where I am, {zone} ({x}, {y})?")
	eq(en.MATCH_SAY_CANCEL, "Sorry, I have to cancel.")
	eq(en.CONSENT_ARENAFIND_TEXT, "Other Olympus addon users who search for a duel or a Bones game can find you. The addon tells a searching player only that you can be found, your guild, level and class, and whether you are in their zone and on their layer. If you click Let's go, they also get your position within 400 yd, a whisper from you and, when neither of you is in a group, a group invite. Nothing about your position is saved.")
	eq(en.MATCH_FIRST_LINE, "Searching sends your guild, zone, layer and level on the Olympus channel, which any addon user on this realm can read, and your position within 400 yd to the one player Olympus asks. Nothing about your position is saved.")
	eq(en.MATCH_CARD_SAFE, "Olympus shows matches and stakes only in this window. Never trade gold outside the challenge.")
	eq(en.MATCH_RULES_LINE, "Matched players are strangers: use Block and the game's Report.")
	-- Every English key has its Portuguese line.
	for k in pairs(en) do assert(pt[k] ~= nil and pt[k] ~= en[k] or k == "MATCH_FIND_BONE" or k == "MATCH_GAME_BONE", "ptBR: " .. k) end
	-- The place's own name where the client has one (C_Map.GetAreaInfo): Booty Bay is area 35.
	eq(c.Match.PlaceName("spot_booty_bay"), "Booty Bay")
	c.areaNames[35] = "Bahía del Botín"
	eq(c.Match.PlaceName("spot_booty_bay"), "Bahía del Botín")
	eq(c.Match.PlaceName("arena_gurubashi"), "Gurubashi Arena", "the arena's label is not its floor's area name")
	MW.NoErrors(w)
end)

test("1.2 P1.8: a fixed Bones search keeps its non-level filters, ignores a stale level range, acceptance opens one canonical private match room on both clients, and only composing sends a logged whisper", function()
	local w, a, b = Pair()
	local opened = {}
	for _, c in ipairs({ a, b }) do
		-- (The room opens through the one door of every pending conversation, ChatRooms.OpenMatter,
		-- which the game loads before the Arena's files; this world loads it only where asked.)
		CH.WithRooms(w, c)
		rawset(c.ns, "ChatWindow", { OpenDynamicRoom = function(spec)
			opened[c] = spec
			return { room = spec.id }
		end })
	end
	local opts = { game = "b", kind = "c", level = 10, reach = "z" }
	assert(a.Match.Start(opts))
	local search = a.Match.View().search
	eq(search.game, "b"); eq(search.kind, "c"); eq(search.level, 0, "Bones ignores the supplied level range"); eq(search.reach, "z")
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	MW.Answer(w, b, "yes")
	w:Run(0)
	for _, c in ipairs({ a, b }) do
		local spec = assert(opened[c], c.short .. ": match room did not open")
		eq(spec.id, mid); eq(spec.key, "arena:" .. mid); eq(spec.kind, "match")
		eq(spec.access, "participants"); eq(spec.active, true); eq(spec.recoverable, true)
		local room = assert(c.Match.RoomView(mid))
		eq(room.active, true); assert(HasAction(room, "cancel")); assert(HasAction(room, "details"))
	end
	eq(#w:Sent{ type = "EC" }, 0, "opening the private room sends no chat word")
	a.Arena.SetRules(true)
	a.ns.ArenaRoles.Live = function() return true end
	local globalBefore = a.rdb.chat and a.rdb.chat.A and #a.rdb.chat.A or 0
	w:As(a, function()
		assert(a.ns.ArenaChat.Open(mid), "the accepted match is an ArenaChat event")
		assert(a.ns.ArenaChat.Send(mid, "same tavern?"))
	end)
	w:Run(0)
	local sent = w:Sent{ from = a, type = "EC" }
	eq(#sent, 1); eq(sent[1].dist, "WHISPER"); eq(sent[1].target, b.name)
	eq(#w:Sent{ from = a, type = "EC", dist = "CHANNEL" }, 0, "never on the public lane")
	eq(a.rdb.chat and a.rdb.chat.A and #a.rdb.chat.A or 0, globalBefore, "never in Olympus public history")
	MW.NoErrors(w)
end)

test("1.2 P1.8: Arena and Bones open separate compact fixed-game Find entries; only Arena uses the remembered level filter", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	local UI = assert(a.ns.Arena.ui)
	local duel = w:As(a, UI.OpenFind, "d")
	eq(duel.opts.game, "d"); eq(rawget(duel, "game"), nil, "no mixed-game selector")
	eq(duel.title:GetText(), L.MATCH_FIND_DUEL_TITLE)
	local d = w:As(a, UI.FindOpts)
	eq(d.game, "d"); eq(d.kind, "c"); eq(d.level, 5); eq(d.reach, "z")
	-- Find cannot enter a Bones game from the road, even though duel Find may open there.
	local blocked, why = w:As(a, UI.OpenFind, "b")
	eq(blocked, false); eq(why, "tavern-rest"); eq(duel.opts.game, "d")
	local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
	a.pos, a.resting = FW.INN, true -- an actual mapped inn, not a mocked CanOpen result
	w:As(a, function() a.ns.FarkleTable.Opts().innkeeperLearned = false end)
	blocked, why = w:As(a, UI.OpenFind, "b")
	eq(blocked, false); eq(why, "training"); eq(duel.opts.game, "d")
	w:As(a, function() a.ns.FarkleTable.Opts().innkeeperLearned = true end)
	local bone = w:As(a, UI.OpenFind, "b")
	assert(bone == duel, "the compact sheet is reused")
	eq(bone.opts.game, "b"); eq(bone.title:GetText(), L.MATCH_FIND_BONE_TITLE)
	local b = w:As(a, UI.FindOpts)
	eq(b.game, "b"); eq(b.kind, "c"); eq(b.level, 0, "Bones does not use the remembered duel level filter"); eq(b.reach, "z")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the wire: a cell at -13,202 / 268 survives the round trip; a findable player's O has no cell; the seeker's cell goes only in R; a point only after Where I am", function()
	local w, a, b = Pair()
	local P = a.ns.Places
	-- floor(6798 / 400) = 16 ("g"), floor(20268 / 400) = 50 ("1e"); centres -13400 and 200.
	local cx, cy = P.Cell(-13202), P.Cell(268)
	eq(cx, 16); eq(cy, 50)
	eq(a.Arena.B36(cx), "g"); eq(a.Arena.B36(cy), "1e")
	eq(a.Arena.N("g", 0, 99), 16); eq(a.Arena.N("1e", 0, 99), 50)
	eq(P.Centre(16), -13400); eq(P.Centre(50), 200)
	eq(a.Arena.N("2s", 0, 99), nil, "a cell past the map (100) is refused")
	a.mapPos = { 0.3123, 0.4551 }
	local mid = Matched(w, a, b, CASUAL)
	-- Nothing on the channel but the ask; the ask has its 12 fields and no cell.
	for _, s in ipairs(w:Sent{ type = "AM", dist = "CHANNEL" }) do
		eq(s.msg:sub(1, 8), "AM~L1~Q~")
		eq(select(2, s.msg:sub(7):gsub("~", "")), 12)
	end
	eq(select(2, MW.Last(w, b, "O"):gsub("~", "")), 9, "a findable player's answer: nine fields")
	for _, m in ipairs(MW.AM(w, a)) do assert(not m:find("@", 1, true), m) end
	-- Where I am: Lida's point to 25 yd, floor(7000 / 25) = 280 ("7s") and floor(20300 / 25) = 812 ("mk").
	MW.Press(w, a, "other")
	local rows = MW.Card(a).rows
	local where
	for i, r in ipairs(rows) do if r.shown and r.text == "Where I am" then where = i end end
	assert(where, "a Where I am row")
	MW.Row(w, a, where)
	w:Run(0)
	eq(MW.Last(w, a, "P"), "P~" .. mid .. "~1~@7s.mk~P")
	eq(a.said[#a.said].text, "How about where I am, Stranglethorn Vale (31.2, 45.5)?")
	MW.NoErrors(w)
end)

-- A pair where setup(w, a, b) ran, then Lida's search: whether Parric answered (his O) and
-- whether Lida kept it (an offer in her search).
local function Hears(setup, opts)
	opts = opts or {}
	local w, a, b = Pair(opts)
	if setup then setup(w, a, b) end
	local ok, why = a.Match.Start(opts.start or CASUAL)
	assert(ok, "the search: " .. tostring(why))
	w:Run(3)
	local answered = #MW.AM(w, b, a.name) > 0
	local v = a.Match.View()
	local kept = v.search and v.search.answers or 0
	MW.NoErrors(w)
	return answered, kept, w, a, b
end

test("1.2 matchmaking: never matched, both ways: the game's ignore list, a block on any character of the account, the moderators' hiding, our own alts", function()
	eq(select(1, Hears()), true, "the control: answered")
	eq(select(2, Hears()), 1, "and kept")
	-- Parric ignores Lida: no answer. Lida ignores Parric: his answer is dropped.
	eq(Hears(function(w, a, b) b.ignored["Lida Fenn"] = true end), false)
	local answered, kept = Hears(function(w, a, b) a.ignored["Parric Stowe"] = true end)
	eq(answered, true); eq(kept, 0)
	-- ns.db.blocked (/oly block's key, the account's: written on another character).
	eq(Hears(function(w, a, b) b.db.blocked["lida fenn-emberfall"] = true end), false)
	answered, kept = Hears(function(w, a, b) a.db.blocked["parric stowe-emberfall"] = true end)
	eq(answered, true); eq(kept, 0)
	-- Moderation.Hides (a name the moderators took off).
	eq(Hears(function(w, a, b) b.ns.Moderation.Hides = function(s) return s == a.name or nil end end), false)
	answered, kept = Hears(function(w, a, b) a.ns.Moderation.Hides = function(s) return s == b.name or nil end end)
	eq(answered, true); eq(kept, 0)
	-- Our own alts (Debts.SameOwner, the money part's; a stand-in).
	eq(Hears(function(w, a, b) b.ns.Debts.SameOwner = function(x, y) return x == b.name and y == a.name end end), false)
	answered, kept = Hears(function(w, a, b) a.ns.Debts.SameOwner = function(x, y) return x == a.name and y == b.name end end)
	eq(answered, true); eq(kept, 0)
end)

test("1.2 matchmaking: never matched: net-off (no search, no answer, no AM sent), the arena off, lockdown, an instance, Busy, combat, a level under the arena's", function()
	-- Net-off: Lida cannot search; Parric is not findable; and an AM would be held anyway.
	local w, a, b = Pair()
	local selfOff = a.ns.Moderation.SelfOff
	a.ns.Moderation.SelfOff = function() return true end
	eq(select(2, a.Match.Start(CASUAL)), "netoff")
	eq(select(2, a.Arena.Send("AM", "L", "Q~x")), "held")
	a.ns.Moderation.SelfOff = selfOff
	eq(Hears(function(w2, a2, b2) b2.ns.Moderation.SelfOff = function() return true end end), false)
	-- The arena turned off on Parric's client: nothing reaches him.
	eq(Hears(function(w2, a2, b2) b2.Arena.SetOff(true) end), false)
	-- Chat lockdown, an instance, Busy (/dnd), combat.
	eq(Hears(function(w2, a2, b2) w2:Lockdown(b2, true) end), false)
	eq(Hears(function(w2, a2, b2) b2.instance = true end), false)
	eq(Hears(function(w2, a2, b2) b2.globals.UnitIsDND = function() return true end end), false)
	eq(Hears(function(w2, a2, b2) w2:Combat(b2, true) end), false)
	w:Lockdown(a, true)
	eq(select(2, a.Match.Start(CASUAL)), "blocked")
	w:Lockdown(a, false)
	w:Combat(a, true)
	eq(select(2, a.Match.Start(CASUAL)), "combat")
	w:Combat(a, false)
	a.instance = true
	eq(select(2, a.Match.Start(CASUAL)), "blocked")
	a.instance = nil
	-- Under the arena's level (10): neither searches nor is found.
	eq(Hears(nil, { bLevel = 9 }), false)
	local w3 = World.New()
	local low = MW.Client(w3, "Lida Fenn", { level = 9 })
	eq(select(2, low.Match.Start(CASUAL)), "level")
	eq(low.Match.WhyText("level"), "You need level 10 to search.")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: never matched: another continent, another zone for a zone ask (the continent's ask reaches it), levels both ways, games and kinds", function()
	-- Parric in Kalimdor (continent 1): no answer.
	eq(Hears(function(w, a, b) b.pos = { cont = 1, wx = -400, wy = -2600 } b.mapID = 1413 end), false)
	-- In Westfall (1436), on Lida's continent: no answer to the zone's ask...
	eq(Hears(function(w, a, b) b.mapID = 1436 end), false)
	-- ...but to the continent's, 20 s later (a second more for being outside her zone).
	local w, a, b = Pair()
	b.mapID = 1436
	eq(a.Match.Start({ game = "d", kind = "c", level = 5, reach = "c" }), true)
	w:Run(19)
	eq(#MW.AM(w, b, a.name), 0)
	w:Run(4)
	eq(#MW.AM(w, b, a.name), 1)
	eq(MW.AM(w, a)[2]:match("~(%a)~[0-9a-z]+$"), "c", "the second ask: the continent")
	eq(MW.Last(w, b, "O"):match("^O~[0-9a-z]+~f~Olympus Ember~(%d)~"), "0", "not in her zone")
	-- Levels: Parric at 54, outside Lida's 55-65: no answer; with Any level, yes.
	eq(Hears(nil, { bLevel = 54 }), false)
	eq(Hears(nil, { bLevel = 54, start = { game = "d", kind = "c", level = 0 } }), true)
	-- The other way: Parric searching at +-5 (55-65) does not answer Lida at 50 (her Any level).
	eq(Hears(function(w2, a2, b2)
		b2.Match.SetFindable(false)
		b2.qid = 5
		assert(b2.Match.Start({ game = "d", kind = "c", level = 5 }))
		w2:Run(40)
	end, { aLevel = 50, start = { game = "d", kind = "c", level = 0 } }), false)
	-- And Lida at +-5 drops an answer from a level 50 (a stand-in answer, as if from Parric).
	local w4, c, d = Pair({ findable = false })
	d.level = 50
	assert(c.Match.Start(CASUAL))
	w4:As(c, function() c.ns.Arena.Inject("WHISPER", d.name, "AM~L1~O~9ix~f~Olympus Ember~1~1e~8~d~c~0") end)
	eq(c.Match.View().search.answers, 0)
	w4:As(c, function() c.ns.Arena.Inject("WHISPER", d.name, "AM~L1~O~9ix~f~Olympus Ember~1~1o~8~d~c~0") end)
	eq(c.Match.View().search.answers, 1)
	-- Games and kinds: Parric found for Bone Throw only; Lida looks for a duel.
	eq(Hears(function(w5, a5, b5) b5.Match.SetFindable(true, { d = false, b = true }) end), false)
	eq(Hears(function(w5, a5, b5) b5.Match.SetFindable(true, { d = false, b = true }) end, { start = { game = "b", kind = "c" } }), true)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the member check: a guild outside the federation, a guild another sender claimed, our own guild's name from a non-member", function()
	local w, a, b = Pair()
	-- (Counted as Parric's offers: a whisper to a name nobody plays in this world never arrives.)
	local function Ask(from, guild)
		local before = b.Match.Stats().offers
		w:As(b, function() b.ns.Arena.Inject("CHANNEL", from, "AM~L1~Q~abc~d~c~" .. guild .. "~0~13u~0~1o~1~2s~z~2s") end)
		w:Run(4)
		return b.Match.Stats().offers - before
	end
	-- Not an Olympus guild.
	eq(Ask("Morrow Vale-Emberfall", "Hearthstone Lodge"), 0)
	-- Another federation guild, vouched once (one guild per sender): answered.
	eq(Ask("Morrow Vale-Emberfall", "Olympus Ash"), 1)
	-- The same sender now claims a second guild: refused (Data.ClaimGuild).
	w:Run(11)
	eq(Ask("Morrow Vale-Emberfall", "Olympus Oak"), 0)
	-- Our own guild's name from someone not in our roster.
	local x = MW.Client(w, "Hesta Quill", { guild = "Olympus Ash" })
	w:Run(11)
	eq(Ask(x.name, "Olympus Ember"), 0)
	-- From a guildmate: answered.
	local y = MW.Client(w, "Wenna Crale", {})
	w:Run(11)
	eq(Ask(y.name, "Olympus Ember"), 1)
	MW.NoErrors(w)
end)

-- An answer injected into a searcher's client, as if whispered by `from`.
local function O(w, c, from, body) w:As(c, function() c.ns.Arena.Inject("WHISPER", from, "AM~L1~O~" .. body) end) end
local function Names(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.o.name:match("^(%S+)") end
	return table.concat(out, " ")
end

test("1.2 matchmaking: ranking: the band, searchers first, the same layer, the smaller level gap, then a weighted draw (outside a group x2, trusted x3)", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	assert(a.Match.Start({ game = "d", kind = "c", level = 0 }))
	-- From Lida at (-13000, 300): cell 17/50 (centre -13000, 200) is 100 yd away, band 1; 16/50
	-- (-13400, 200) 412 yd, band 1; 14/50 (-14200, 200) 1204 yd, band 2; 0/50 (-19800, 200) 6800
	-- yd, band 4. A findable player: band 2 in her zone (same 1 or 2), 4 elsewhere (same 0).
	O(w, a, "Aila Sund-Emberfall", "9ix~s~Olympus Ash~1~1o~1~d~c~0~g~1e")   -- band 1, searcher, another layer
	O(w, a, "Brenna Holt-Emberfall", "9ix~s~Olympus Ash~2~1o~1~d~c~0~h~1e") -- band 1, searcher, her layer
	O(w, a, "Cato Brisk-Emberfall", "9ix~s~Olympus Ash~2~1o~1~d~c~0~e~1e")  -- band 2, searcher
	O(w, a, "Dara Pike-Emberfall", "9ix~f~Olympus Ash~1~1l~1~d~c~0")        -- band 2, findable, level 57
	O(w, a, "Edda Crow-Emberfall", "9ix~f~Olympus Ash~2~1l~1~d~c~0")        -- band 2, findable, her layer, 57
	O(w, a, "Fenn Garro-Emberfall", "9ix~f~Olympus Ash~1~1o~1~d~c~0")       -- band 2, findable, level 60
	O(w, a, "Gil Marsh-Emberfall", "9ix~f~Olympus Ash~0~1o~1~d~c~0")        -- band 4, findable
	O(w, a, "Hale Dunn-Emberfall", "9ix~s~Olympus Ash~0~1o~1~d~c~0~0~1e")   -- band 4, searcher
	eq(Names(a.Match.Ranked()), "Brenna Aila Cato Edda Fenn Dara Hale Gil")
	local bands = {}
	for _, e in ipairs(a.Match.Ranked()) do bands[#bands + 1] = e.band end
	eq(table.concat(bands, ","), "1,1,2,2,2,2,4,4")
	-- The draw among the first alike: Iona (in a group, weight 1) and Jory (outside one, trusted:
	-- 2 x 3 = 6). A draw of 0.1 x 7 = 0.7 falls in Iona's 1; 0.5 x 7 = 3.5 in Jory's 6.
	local w2 = World.New()
	local c = MW.Client(w2, "Lida Fenn", { pos = SEEKER })
	c.trusted["Jory Pell-Emberfall"] = true
	assert(c.Match.Start({ game = "d", kind = "c", level = 0 }))
	O(w2, c, "Iona Reed-Emberfall", "9ix~f~Olympus Ash~1~1o~1~d~c~1")
	O(w2, c, "Jory Pell-Emberfall", "9ix~f~Olympus Ash~1~1o~1~d~c~0")
	c.draw = 0.1
	w2:Run(5)
	eq(c.Match.View().search.asking, "Iona Reed")
	local w3 = World.New()
	local d = MW.Client(w3, "Lida Fenn", { pos = SEEKER })
	d.trusted["Jory Pell-Emberfall"] = true
	assert(d.Match.Start({ game = "d", kind = "c", level = 0 }))
	O(w3, d, "Iona Reed-Emberfall", "9ix~f~Olympus Ash~1~1o~1~d~c~1")
	O(w3, d, "Jory Pell-Emberfall", "9ix~f~Olympus Ash~1~1o~1~d~c~0")
	d.draw = 0.5
	w3:Run(5)
	eq(d.Match.View().search.asking, "Jory Pell")
	-- Iona plays on no client of this world: the server's "offline" for Lida's request moves it on.
	w2:Run(1)
	eq(c.Match.View().search.asking, "Jory Pell")
	MW.NoErrors(w)
end)

test("1.2 P1.8: Bones uses the supported location signal: a searching player in the same 400-yard place band ranks before a farther one; no tavern identity is invented", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	assert(a.Match.Start({ game = "b", kind = "c", level = 0, reach = "z" }))
	-- The wire deliberately has no tavern id. Searchers do carry their coarse cell: h/1e is the
	-- seeker's own cell (the strongest available same-place signal), e/1e is over 1,000 yd away.
	O(w, a, "Near Bones-Emberfall", "9ix~s~Olympus Ash~2~1o~1~b~c~0~h~1e")
	O(w, a, "Far Bones-Emberfall", "9ix~s~Olympus Ash~2~1o~1~b~c~0~e~1e")
	local ranked = a.Match.Ranked()
	eq(ranked[1].o.name, "Near Bones-Emberfall")
	eq(ranked[1].game, "b")
	eq(ranked[1].band, 1)
	assert(ranked[2].band > ranked[1].band)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: three requests per search, a no moves to the next offer; then 'Nobody nearby' and no second ask", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	local list = {}
	for _, n in ipairs({ "Wenna Crale", "Parric Stowe", "Idris Vane", "Brannoc Weald" }) do
		list[#list + 1] = MW.Client(w, n, { pos = OTHER, findable = true })
	end
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	eq(a.Match.View().search.answers, 4)
	-- Alike (band 2, findable, level 60, outside a group): the draw 0 takes the first by name.
	local order = {}
	for _ = 1, 3 do
		local r = MW.Last(w, a, "R")
		local to = w:Sent{ from = a, type = "AM" }
		order[#order + 1] = to[#to].target:match("^(%S+)")
		MW.Answer(w, w:Find(to[#to].target), "no")
		w:Run(1)
	end
	eq(table.concat(order, " "), "Brannoc Idris Parric")
	eq(a.Match.View().search.requests, 3)
	eq(MW.Popup(list[1]), nil, "Wenna was never asked")
	-- Said on her card (shown): not in chat as well (the review of matchmaking: no chat line the card carries).
	assert(MW.HasLine(a, "Nobody nearby right now. You stay findable for 10 minutes."), table.concat(MW.Lines(a), " | "))
	eq(Printed(a, "Nobody nearby right now."), 0)
	eq(Printed(a, "Asking "), 0, "each request on the card, not in chat")
	w:Run(30)
	eq(#w:Sent{ from = a, type = "AM", dist = "CHANNEL" }, 1, "no second ask")
	-- Each no: that name passed over for 30 min (the other way too: they declined Lida).
	eq(a.Match.Barred("Brannoc Weald-Emberfall"), "declined")
	eq(w:Find("Brannoc Weald").Match.Barred(a.name), "declined")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: a lie ends the match, is not counted and skips that name for 24 h, after a reload too: a searcher's cell too fast, a zone answer from another zone", function()
	local w, a, b = Pair({ findable = false })
	-- Parric searches (his answer carries his cell, 16/50), then Lida.
	b.qid = 999
	assert(b.Match.Start({ game = "d", kind = "c", level = 0 }))
	w:Run(30)
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	assert(MW.Popup(b), "Parric's popup")
	-- A forged yes from Parric: his cell at 5/50, (16 - 5 - 1) x 400 = 4,000 yd from the one he
	-- sent 5 s ago: far over 15 yd/s.
	w:As(a, function() a.ns.Arena.Inject("WHISPER", b.name, "AM~L1~A~" .. mid .. "~Y~arena_gurubashi~5~1e~13u~0~0~0~0") end)
	w:Run(0)
	eq(MW.Last(w, a, "C"), "C~" .. mid .. "~c")
	eq(a.Match.View().state, "search", "no match")
	eq(a.Match.View().search.requests, 0, "not counted")
	eq(a.Match.Stats().lies, 1)
	eq(MW.Popup(b), nil, "Parric's popup went with the C")
	MW.Reload(w, a)
	eq(a.Match.Barred(b.name), "lied")
	w:Run(86399)
	eq(a.Match.Barred(b.name), "lied")
	w:Run(1)
	eq(a.Match.Barred(b.name), nil)
	-- A findable answer to a zone ask, whose yes names Westfall (1436 = "13w").
	local w2, c, d = Pair()
	assert(c.Match.Start(CASUAL))
	w2:Run(6)
	local mid2 = MW.Last(w2, c, "R"):match("^R~(M[0-9a-z]+)~")
	w2:As(c, function() c.ns.Arena.Inject("WHISPER", d.name, "AM~L1~A~" .. mid2 .. "~Y~arena_gurubashi~g~1e~13w~0~0~0~0") end)
	eq(c.Match.Stats().lies, 1)
	eq(c.Match.Barred(d.name), "lied")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: an answer's place: a duel at a place Fair does not list for it (an inn) or = on a capital's map ends it; a place further down the list is taken", function()
	local function Forged(place, mapA, mapB)
		local w, a, b = Pair()
		a.mapID, b.mapID = mapA or 1434, mapA or 1434
		assert(a.Match.Start(CASUAL))
		w:Run(6)
		local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
		w:As(a, function() a.ns.Arena.Inject("WHISPER", b.name, "AM~L1~A~" .. mid .. "~Y~" .. place .. "~g~1e~" .. a.Arena.B36(mapB or 1434) .. "~0~0~0~0") end)
		w:Run(0)
		MW.NoErrors(w)
		return a.Match.View().state, MW.Last(w, a, "C"), mid
	end
	local state, c, mid = Forged("inn_booty_bay")
	eq(state, "search"); eq(c, "C~" .. mid .. "~c")
	eq(select(1, Forged("tavern_slaughtered_lamb")), "search")
	eq(select(1, Forged("nowhere")), "search")
	-- "=" from Stormwind City's map (1453, a capital): refused; from Stranglethorn: taken.
	eq(select(1, Forged("=", 1453, 1453)), "search")
	eq(select(1, Forged("=")), "match")
	-- Booty Bay is on the list for a casual duel (after the arena): taken, and only logged.
	eq(select(1, Forged("spot_booty_bay")), "match")
end)

test("1.2 matchmaking: the answer chance: the crowd sets pct (about six answers), ask 2 three times it, a continent ask its census; a draw past pct is silent, a searcher answers at twice it", function()
	local w, a, b = Pair()
	-- Six addon users on the zone's two layers: crowd 6 x 4 = 24, 600 / 24 = 25 ("p").
	a.zoneLayers[1434] = { { zoneUID = 1, count = 5 }, { zoneUID = 2, count = 1 } }
	eq(a.Match.Pct("z", 1434), 25)
	-- The census: 40 users of 50 online in one fresh guild here: 40 / 2 = 20 for the continent,
	-- 600 / 20 = 30; 600 users: 600 / 300 = 2, raised to 5.
	a.summary = { guilds = { { fresh = true, g = { users = 40, online = 50, realm = "Emberfall" } } } }
	eq(a.Match.Pct("c", 1434), 30)
	a.summary = { guilds = { { fresh = true, g = { users = 600, online = 700, realm = "Emberfall" } } } }
	eq(a.Match.Pct("c", 1434), 5)
	a.summary = { guilds = {} }
	-- Parric draws 0.3: 30 >= 25, silent; Lida asks the zone again 20 s later at 75 ("23").
	b.draw = 0.3
	assert(a.Match.Start(CASUAL))
	w:Run(3)
	eq(#MW.AM(w, b), 0)
	eq(MW.AM(w, a)[1]:match("~z~(%w+)$"), "p")
	w:Run(20)
	eq(MW.AM(w, a)[2]:match("~z~(%w+)$"), "23")
	w:Run(3)
	eq(#MW.AM(w, b), 1, "30 < 75: answered")
	-- A searcher answers at twice the chance: 30 < 50.
	local w2, c, d = Pair({ findable = false })
	c.zoneLayers[1434] = { { zoneUID = 1, count = 6 } }
	d.draw, d.qid = 0.3, 5
	assert(d.Match.Start(CASUAL))
	w2:Run(40)
	assert(c.Match.Start(CASUAL))
	w2:Run(3)
	eq(#MW.AM(w2, d, c.name), 1)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: pacing: one offer every 10 s, once per asker per 10 min; a sender's asks past 6 in 15 min dropped; 30 answers kept; three searches in 15 min", function()
	local w = World.New()
	local b = MW.Client(w, "Parric Stowe", { pos = OTHER, findable = true })
	-- Asks from players of another Olympus guild, each a new qid (Parric's offers counted: they
	-- play in no client of this world, so his whispers never arrive).
	local n = 0
	local function Ask(from)
		n = n + 1
		local before = b.Match.Stats().offers
		w:As(b, function() b.ns.Arena.Inject("CHANNEL", from .. "-Emberfall", "AM~L1~Q~q" .. n .. "~d~c~Olympus Ash~0~13u~0~1o~1~2s~z~2s") end)
		w:Run(4)
		return b.Match.Stats().offers - before
	end
	eq(Ask("Morrow Vale"), 1)
	eq(Ask("Nessa Brook"), 0, "4 s after his last offer")
	w:Run(2)
	eq(Ask("Orrin Tate"), 1, "10 s after it")
	w:Run(10)
	eq(Ask("Morrow Vale"), 0, "Morrow again, 20 s after his answer")
	w:Run(600)
	eq(Ask("Morrow Vale"), 1, "10 min later")
	-- A sender's asks past 6 in 15 min are dropped unread.
	local heard, dropped = b.Match.Stats().heard, b.Match.Stats().dropped
	for _ = 1, 7 do
		n = n + 1
		w:As(b, function() b.ns.Arena.Inject("CHANNEL", "Pell Ashby-Emberfall", "AM~L1~Q~q" .. n .. "~d~c~Olympus Ash~0~13u~0~1o~1~2s~z~2s") end)
	end
	eq(b.Match.Stats().heard - heard, 7)
	eq(b.Match.Stats().dropped - dropped, 1)
	-- Three searches in 15 min: the fourth waits.
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	for _ = 1, 3 do
		assert(a.Match.Start(CASUAL))
		a.Match.Stop()
		w:Run(60)
	end
	eq(select(2, a.Match.Start(CASUAL)), "rate")
	eq(a.Match.WhyText("rate"), "Three searches in 15 minutes: try again a little later.")
	w:Run(900 - 180)
	eq(a.Match.Start(CASUAL), true, "15 min after the first")
	-- 30 answers kept, the 31st not.
	local w2 = World.New()
	local s2 = MW.Client(w2, "Lida Fenn", { pos = SEEKER })
	assert(s2.Match.Start({ game = "d", kind = "c", level = 0 }))
	for i = 1, 31 do O(w2, s2, ("Kell Amar%s-Emberfall"):format(string.char(96 + i % 26 + 1) .. string.char(96 + math.floor(i / 26) + 1)), "9ix~f~Olympus Ash~1~1o~1~d~c~0") end
	eq(s2.Match.View().search.answers, 30)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: the window: a 3.5-s answer lands in a zone ask's 4-s window; a later one is used by the next request", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	local x = MW.Client(w, "Idris Vane", { pos = OTHER })
	local y = MW.Client(w, "Wenna Crale", { pos = OTHER })
	assert(a.Match.Start(CASUAL))
	w:Run(3.5)
	O(w, a, x.name, "9ix~f~Olympus Ember~1~1o~1~d~c~0")
	eq(a.Match.View().search.asking, nil, "the window is still open")
	w:Run(1.5)
	eq(a.Match.View().search.asking, "Idris Vane")
	-- Wenna's answer 5 s after the window closed: kept; used once Idris's request lapses (32 s).
	w:Run(5)
	O(w, a, y.name, "9ix~f~Olympus Ember~1~1o~1~d~c~0")
	eq(a.Match.View().search.asking, "Idris Vane")
	w:Run(28)
	eq(a.Match.View().search.asking, "Wenna Crale")
	eq(a.Match.View().search.requests, 2)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the popup: Not now is an ordinary no and a 30-min decline both ways; two unanswered in a row pause being found for 30 min; the seeker's withdrawal closes it", function()
	local w, a, b = Pair()
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	eq(b.Match.View().state, "popup")
	MW.Answer(w, b, "no")
	w:Run(0)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~N")
	eq(#b.said, 0, "no whisper on a no")
	eq(b.Match.Barred(a.name), "declined"); eq(a.Match.Barred(b.name), "declined")
	MW.Reload(w, b)
	eq(b.Match.Barred(a.name), "declined", "after a reload too")
	w:Run(1800)
	eq(b.Match.Barred(a.name), nil)
	-- Unanswered (the dialog's own 30 s), twice in a row: not findable for 30 min.
	local w2, c, d = Pair()
	local e = MW.Client(w2, "Wenna Crale", { pos = SEEKER })
	assert(c.Match.Start(CASUAL))
	w2:Run(6)
	MW.Answer(w2, d, "timeout")
	c.Match.Stop()
	w2:Run(20)
	assert(e.Match.Start(CASUAL))
	w2:Run(6)
	MW.Answer(w2, d, "timeout")
	w2:Run(0)
	eq(Printed(d, "Two requests in a row went unanswered: nobody finds you for 30 minutes."), 1)
	eq(select(2, d.Match.Findable()), "paused")
	eq(d.Match.View().findable.paused, true)
	w2:Run(1800)
	eq(d.Match.Findable(), true)
	-- Lida gives up (Cancel on her card while asking): Parric's popup goes.
	local w3, f, g = Pair()
	assert(f.Match.Start(CASUAL))
	w3:Run(6)
	assert(MW.Popup(g))
	MW.Press(w3, f, "stopsearch")
	w3:Run(0)
	eq(MW.Popup(g), nil)
	eq(g.Match.View().state, "idle")
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3)
end)

test("1.2 matchmaking: one at a time: a player with a popup up answers any other request with A~N; two requests crossing: the name that sorts first keeps its own", function()
	local w = World.New()
	local b = MW.Client(w, "Parric Stowe", { pos = OTHER, findable = true })
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	local c = MW.Client(w, "Wenna Crale", { pos = SEEKER })
	-- (No 10-s gap for Parric here: he offers to both at once. Lida wants a duel, Wenna Bone
	-- Throw: neither answers the other.)
	rawset(b.ns.Hop, "OFFER_GAP", 0)
	c.qid = 3
	assert(a.Match.Start(CASUAL))
	assert(c.Match.Start({ game = "b", kind = "c", level = 5 }))
	w:Run(6)
	local ra, rc = MW.Last(w, a, "R"), MW.Last(w, c, "R")
	assert(ra and rc, "two requests")
	eq(MW.Popup(b).data.name, a.name)
	eq(MW.Last(w, b, "A"), "A~" .. rc:match("^R~(M[0-9a-z]+)~") .. "~N")
	eq(c.Match.View().search.asking, nil, "Wenna moves on")
	-- Crossing (each asks the other at once; here the other's request is handed in while one's own
	-- is out): "idris vane" sorts before "lida fenn". Idris keeps his and answers hers with A~N;
	-- Lida drops hers (not counted) and sees his popup. Idris at 16/50 ("g", "1e"); both findable,
	-- each answered the other's ask ("9ix" hers, "4" his).
	local function Two(first)
		local w2 = World.New()
		local l = MW.Client(w2, "Lida Fenn", { pos = SEEKER, findable = true })
		local i = MW.Client(w2, "Idris Vane", { pos = OTHER, findable = true })
		i.qid = 4
		local x, y = l, i
		if first == "idris" then x, y = i, l end
		assert(x.Match.Start(CASUAL))
		w2:Run(0.5)
		assert(y.Match.Start(CASUAL))
		w2:Run(5)
		return w2, l, i
	end
	local w2, l, i = Two("idris")
	eq(i.Match.View().search.asking, "Lida Fenn")
	w2:As(i, function() i.ns.Arena.Inject("WHISPER", l.name, "AM~L1~R~Mcross1~9ix~d~c~0~0~1o~1~h~1e~0") end)
	w2:Run(0)
	eq(MW.Last(w2, i, "A"), "A~Mcross1~N")
	eq(i.Match.View().search.asking, "Lida Fenn", "he keeps his own")
	-- Force the inverse crossing without depending on the transport queue's ordering: Lida has
	-- already asked Idris when his independently offered request reaches her. She drops hers and
	-- takes his, because "idris vane" sorts first.
	local w3 = World.New()
	local l3 = MW.Client(w3, "Lida Fenn", { pos = SEEKER, findable = true })
	local i3 = MW.Client(w3, "Idris Vane", { pos = OTHER, findable = true })
	assert(l3.Match.Start(CASUAL))
	w3:As(l3, function()
		l3.ns.Arena.Inject("CHANNEL", i3.name, "AM~L1~Q~4~d~c~Olympus Ember~0~13u~0~1o~1j~1t~z~2s")
	end)
	w3:Run(6)
	eq(l3.Match.View().search.asking, "Idris Vane")
	w3:As(l3, function() l3.ns.Arena.Inject("WHISPER", i3.name, "AM~L1~R~Mcross2~4~d~c~0~0~1o~1~g~1e~0") end)
	eq(l3.Match.View().search.asking, nil, "she drops hers")
	eq(l3.Match.View().search.requests, 0)
	eq(MW.Popup(l3).data.name, i3.name)
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3)
end)

test("1.2 matchmaking: Block: from the popup and the card, in one click: ns.db.blocked, then the ignore list; a full list says so; the other side sees a plain no or cancel", function()
	local w, a, b = Pair()
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	MW.Answer(w, b, "block")
	w:Run(0)
	eq(b.db.blocked["lida fenn-emberfall"], true)
	eq(b.ignored["Lida Fenn"], true)
	eq(MW.Last(w, b, "A"):match("~(%u)$"), "N")
	eq(Printed(b, "Lida Fenn is blocked."), 1)
	eq(a.Match.Barred(b.name), "declined", "Lida only saw a no")
	-- On the card, with a full ignore list: blocked in Olympus only; the match ends with C~c.
	local w2, c, d = Pair()
	local mid = Matched(w2, c, d, CASUAL)
	c.ignoreFull = true
	MW.Press(w2, c, "block")
	w2:Run(0)
	eq(c.db.blocked["parric stowe-emberfall"], true)
	eq(c.ignored["Parric Stowe"], nil)
	eq(Printed(c, "Your ignore list is full: blocked in Olympus only."), 1)
	eq(MW.Last(w2, c, "C"), "C~" .. mid .. "~c")
	eq(d.Match.View().state, "idle")
	eq(d.Match.View().ended.why, "cancel")
	eq(MW.Card(d).title.text, "Match over")
	assert(MW.HasLine(d, "Lida Fenn cancelled the match."))
	eq(MW.Buttons(d), "again close room")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: Cancel: a click, its whisper and C~c; the other card offers Find someone else; the partner offline ends it", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	MW.Press(w, b, "cancel")
	w:Run(0)
	eq(b.said[#b.said].text, "Sorry, I have to cancel.")
	eq(MW.Last(w, b, "C"), "C~" .. mid .. "~c")
	eq(a.Match.View().ended.why, "cancel")
	assert(MW.HasLine(a, "Parric Stowe cancelled the match."))
	assert(MW.Buttons(a):find("again", 1, true))
	assert(MW.HasLine(b, "You cancelled the match."))
	-- [Find someone else]: a new search on the same terms.
	MW.Press(w, a, "again")
	eq(a.Match.View().state, "search")
	-- Offline: Parric logs out; Lida's next whisper to him is not delivered (the server's 12).
	local w2, c, d = Pair()
	Matched(w2, c, d, CASUAL)
	w2:Logout(d)
	MW.Press(w2, c, "onway")
	w2:Run(2)
	eq(c.Match.View().ended.why, "offline")
	assert(MW.HasLine(c, "Parric Stowe is offline: the match ended."))
	MW.NoErrors(w); MW.NoErrors(w2)
end)

-- (The owner's decision, 2026-10-04: every pending conversation opens its own tab on the Chat page,
-- the Olympus window in front, pinned while the matter is open, reopened from the matter's page.
-- Before it the room opened unpinned, under any window in front of Olympus's.)
test("1.2 P1.8: a match found opens its room through the one pending-conversation door: the window in front, pinned while the match lives, unpinned at its end; the card reopens it; a fight holds it until its end", function()
	local w, a, b = Pair()
	local ha, hb = MatchHost(w, a), MatchHost(w, b)
	local mid = Matched(w, a, b, CASUAL)
	local key = "arena:" .. mid
	for _, x in ipairs({ { a, ha }, { b, hb } }) do
		eq(table.concat(x[2].calls, ","), ("open %s,pin %s,raise"):format(key, key), x[1].short .. ": the room, pinned, the window in front")
		eq(x[2].spec.active, true)
	end
	-- Its end: the pin goes on both sides (the room stays, retained and removable as any other).
	ha.calls, hb.calls = {}, {}
	MW.Press(w, a, "cancel")
	w:Run(0)
	eq(table.concat(ha.calls, ","), "unpin " .. key, "the canceller's")
	eq(table.concat(hb.calls, ","), "unpin " .. key, "the partner's")
	-- The ended card's Chat button reopens it, the window in front; an ended match is not pinned again.
	ha.calls = {}
	assert(MW.Buttons(a):find("room", 1, true), "the card offers the room")
	MW.Press(w, a, "room")
	eq(table.concat(ha.calls, ","), ("open %s,raise"):format(key))
	-- In a fight Olympus opens nothing by itself; the room comes when it ends, while the match lives.
	local w3, e, f = Pair()
	local he, hf = MatchHost(w3, e), MatchHost(w3, f)
	assert(e.Match.Start(CASUAL))
	w3:Run(6)
	local mid3 = (assert(MW.Last(w3, e, "R"), "a request"):match("^R~(M[0-9a-z]+)~"))
	e.combat = true
	MW.Answer(w3, f, "yes")
	w3:Run(0)
	eq(e.Match.View().state, "match", "matched in the fight")
	eq(#he.calls, 0, "nothing opened during the fight")
	eq(#hf.calls, 3, "the partner, out of combat, at once")
	CH.CombatOver(w3, e)
	eq(table.concat(he.calls, ","), ("open arena:%s,pin arena:%s,raise"):format(mid3, mid3), "at the fight's end")
	MW.NoErrors(w); MW.NoErrors(w3)
end)

test("1.2 P1.8: cancelled rooms retain their private identity to the exact expiry, offer New find only while idle, and never replace a later live match", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	MW.Press(w, a, "cancel")
	w:Run(0)
	local spec = assert(a.Match.ChatRoom(mid))
	eq(spec.active, false); eq(spec.phase, "complete"); eq(spec.recoverable, true)
	local room = assert(a.Match.RoomView(mid))
	assert(HasAction(room, "newfind"), "idle ended room offers another fixed-game search")
	w:Run(1799)
	eq(a.Match.ChatRoom(mid).recoverable, true)
	w:Run(1)
	eq(a.Match.ChatRoom(mid).recoverable, false, "the exact retention boundary")
	eq(select(2, a.Match.RoomView(mid)), "expired")

	-- A different ended room remains readable while a newer live match exists, but it cannot start
	-- a second state machine or displace that match.
	local w2, c, d = Pair()
	local old = Matched(w2, c, d, CASUAL)
	MW.Press(w2, c, "cancel")
	w2:Run(0)
	-- The retry guard is 10 minutes; the old room is still inside its 30-minute retention.
	w2:Run(600)
	-- Start through the existing card action, then match again.
	MW.Press(w2, c, "again")
	w2:Run(6)
	MW.Answer(w2, d, "yes")
	w2:Run(0)
	local oldView = assert(c.Match.RoomView(old))
	eq(HasAction(oldView, "newfind"), false)
	eq(select(2, c.Match.RoomAction(old, "newfind")), "busy")
	eq(c.Match.View().state, "match", "the current match remains authoritative")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: the group: the invite only inside Let's go or [Invite]; the end leaves a group of two the match formed, not a larger one, not while its fight lives (then at Ended)", function()
	-- Lida leads a group with room (grp 1), Parric has none: she invites, on her card's [Invite].
	local w, a, b = Pair()
	local x = MW.Client(w, "Wenna Crale", {})
	w:Group({ a, x })
	Matched(w, a, b, CASUAL)
	assert(MW.Last(w, a, "R"):find("~1$"), "her request says grp 1")
	eq(#b.invited, 0, "Parric does not invite")
	assert(MW.HasLine(b, "Accept Lida Fenn's invite: it lets you find each other."))
	assert(MW.HasLine(a, "Invite Parric Stowe: it lets you find each other."))
	MW.Press(w, a, "invite")
	eq(a.invited[1], "Parric Stowe")
	-- Accepted (by the player: the addon never does): a group of three, not the match's.
	w:Group({ a, x, b })
	MW.Press(w, a, "done")
	w:Run(0)
	eq(a.left, 0); eq(b.left, 0)
	eq(MW.Buttons(b), "close leave room")
	-- Neither in a group: Parric invites inside Let's go; the group of two the match formed goes
	-- at the end (Done), from code.
	local w2, c, d = Pair()
	Matched(w2, c, d, CASUAL)
	eq(d.invited[1], "Lida Fenn")
	w2:Group({ d, c })
	MW.Press(w2, c, "done")
	w2:Run(0)
	assert(MW.Last(w2, c, "C"):find("^C~M[0-9a-z]+~d$"), MW.Last(w2, c, "C"))
	eq(c.left + d.left, 1)
	eq(c.groupId, nil); eq(d.groupId, nil)
	-- A staked duel handed off: the group stays while the fight lives, and goes at Ended.
	local w3, e, f = Pair({ findable = false })
	Staked(w3, e, f)
	f.Match.SetFindable(true, { d = true, staked = true })
	local mid3 = Matched(w3, e, f, { game = "d", kind = "s", lo = 100000, hi = 200000, level = 0 })
	w3:Group({ f, e })
	w3:As(e, function() assert(e.ns.Arena.LoadUI()) end)
	e.ns.Arena.ui.Challenge = function() end
	MW.Press(w3, e, "challenge")
	eq(f.Match.Vet(e.name, "d", 100000), true)
	MW.Press(w3, e, "done")
	w3:Run(0)
	eq(e.left + f.left, 0, "the fight is live")
	eq(f.Match.Ended(mid3), true, "the receiver uses the id returned by Vet")
	eq(f.left, 1)
	eq(e.Match.Ended(mid3), true)
	eq(e.left, 0, "the group was already gone")
	-- If only one subsystem knows the id, its Ended sends the existing private C and returns true;
	-- the other card ends, and each retained record is still idempotent.
	local w4, g, h = Pair({ findable = false })
	Staked(w4, g, h)
	h.Match.SetFindable(true, { d = true, staked = true })
	local mid4 = Matched(w4, g, h, { game = "d", kind = "s", lo = 100000, hi = 200000, level = 0 })
	w4:Group({ h, g })
	w4:As(g, function() assert(g.ns.Arena.LoadUI()) end)
	g.ns.Arena.ui.Challenge = function() end
	MW.Press(w4, g, "challenge")
	eq(h.Match.Vet(g.name, "d", 100000), true)
	eq(g.Match.Ended(mid4), true, "an active handed match reports that it ended")
	w4:Run(0)
	eq(MW.Last(w4, g, "C"), "C~" .. mid4 .. "~d")
	eq(g.Match.View().state, "idle"); eq(h.Match.View().state, "idle")
	eq(g.Match.View().ended.why, "done"); eq(h.Match.View().ended.why, "done")
	eq(g.left + h.left, 1, "the formed group is left once")
	eq(g.Match.Ended(mid4), false, "the exact id is idempotent")
	eq(h.Match.Ended(mid4), true, "the receiver clears its retained hand-off by exact id")
	eq(h.Match.Ended(mid4), false, "the receiver hand-off is idempotent")
	-- AcceptGroup was never called; nothing outside a click.
	for _, c2 in ipairs({ a, b, c, d, e, f, g, h }) do for _, call in ipairs(c2.calls) do assert(call ~= "AcceptGroup") end end
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3); MW.NoErrors(w4)
end)

test("1.2 matchmaking: the King: never found, no privacy line on any character of his account, a search only with his crown, offers only from trusted names, masked; the crown off ends it", function()
	local w = World.New()
	local king = MW.Client(w, World.NAMES.king, { guild = World.KING_GUILD, rank = 0, pos = SEEKER })
	local b = MW.Client(w, "Parric Stowe", { pos = OTHER, findable = true })
	local c = MW.Client(w, "Wenna Crale", { pos = OTHER, findable = true })
	eq(king.King.IsKing(), true)
	eq(select(2, king.Match.Start(CASUAL)), "crown")
	eq(king.Match.WhyText("crown"), "Show your crown on the map to search.")
	king.db.throneLocation = true
	king.trusted[b.name] = true
	rawset(king.ns, "CouncilMasked", function() return true end)
	rawset(c.ns.Hop, "OFFER_GAP", 0)
	assert(king.Match.Start(CASUAL))
	w:Run(10)
	-- Both answered; only Parric (trusted) is listed, masked; nobody is asked for him.
	local v = king.Match.View()
	eq(#v.offers, 1)
	eq(v.offers[1].name, "Parr****")
	eq(#MW.AM(w, king), 1, "the ask alone: no request")
	assert(MW.Card(king).rows[1].shown and MW.Card(king).rows[1].text:find("Parr****", 1, true))
	MW.Row(w, king, 1)
	w:Run(0)
	assert(MW.Last(w, king, "R"), "his pick asks Parric")
	MW.Answer(w, b, "yes")
	w:Run(0)
	eq(king.Match.View().state, "match")
	-- His client never answers an ask or a request, searching or not.
	c.qid = 8
	c.Match.SetFindable(false)
	assert(c.Match.Start(CASUAL))
	w:Run(6)
	eq(#MW.AM(w, king, c.name), 0)
	w:As(king, function() king.ns.Arena.Inject("WHISPER", c.name, "AM~L1~R~Mk1~8~d~c~0~0~1o~1~h~1e~0") end)
	w:Run(0)
	eq(#MW.AM(w, king, c.name), 0)
	eq(king.Match.Findable(), false)
	eq(select(2, king.Match.Findable()), "off")
	king.Match.SetFindable(true)
	eq(select(2, king.Match.Findable()), "king")
	-- The crown off: his match ends (C~c) and the group it formed goes.
	w:Group({ b, king })
	king.db.throneLocation = false
	w:Run(2)
	eq(king.Match.View().ended.why, "crown")
	eq(king.left, 1)
	eq(b.Match.View().ended.why, "cancel")
	-- No privacy line for him, nor for another character of his account.
	local keys = {}
	for _, item in ipairs(king.Consent.Items()) do keys[item.key] = true end
	eq(keys.arenaFind, nil)
	local alt = MW.Client(w, "Aldric Stone", {})
	alt.db.myCharacters = { [World.NAMES.king:lower()] = true }
	keys = {}
	for _, item in ipairs(alt.Consent.Items()) do keys[item.key] = true end
	eq(keys.arenaFind, nil)
	alt.Match.SetFindable(true)
	eq(select(2, alt.Match.Findable()), "king")
	eq(select(2, alt.Match.Start(CASUAL)), "king")
	keys = {}
	for _, item in ipairs(b.Consent.Items()) do keys[item.key] = true end
	eq(keys.arenaFind, true)
	-- While he searches too: Wenna's ask gets no answer from him.
	local w2 = World.New()
	local k2 = MW.Client(w2, World.NAMES.king, { guild = World.KING_GUILD, rank = 0, pos = SEEKER })
	local c2 = MW.Client(w2, "Wenna Crale", { pos = OTHER })
	k2.db.throneLocation = true
	assert(k2.Match.Start(CASUAL))
	w2:Run(1)
	c2.qid = 8
	assert(c2.Match.Start(CASUAL))
	w2:Run(6)
	eq(#MW.AM(w2, k2, c2.name), 0)
	eq(c2.Match.View().search.answers, 0)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: another spot: the next five with both walks, Where I am, Close by; a proposal is its sender's yes and clears the other's; crossed ones: the higher rev, then the name first; 3 min without agreement ends it", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	MW.Press(w, a, "other")
	-- From Lida's centre (-13000, 200) and Parric's (-13400, 200), rounded to 10: Booty Bay 1487.3
	-- and 1098.4; Goldshire (-9455.6, 46.4) 3547.7 and 3947.4; the Stormwind gate (-9120, 407.4)
	-- 3885.5 and 4285.4; then the Gates of Ironforge and Southshore (the Horde's spots are not ours).
	local rows = {}
	for _, r in ipairs(MW.Card(a).rows) do if r.shown then rows[#rows + 1] = r.text end end
	eq(rows[1], "Booty Bay: 1490 yd, 1100 yd")
	eq(rows[2], "Goldshire: 3550 yd, 3950 yd")
	eq(rows[3], "Outside the Stormwind gate: 3890 yd, 4290 yd")
	eq(rows[4]:match("^[^:]+"), "Gates of Ironforge")
	eq(rows[5]:match("^[^:]+"), "Southshore")
	eq(rows[6], "Where I am"); eq(rows[7], "Close by"); eq(#rows, 7)
	MW.Row(w, a, 1)
	w:Run(0)
	eq(MW.Last(w, a, "P"), "P~" .. mid .. "~1~spot_booty_bay~P")
	eq(a.said[#a.said].text, "How about Booty Bay, Stranglethorn Vale (27.0, 77.3) instead?")
	-- Parric's yes (Let's go) is cleared: he agrees again, or not.
	eq(b.Match.View().match.place.id, "spot_booty_bay")
	eq(b.Match.View().match.mine, false); eq(b.Match.View().match.theirs, true)
	assert(MW.HasLine(b, "Lida Fenn picked this spot: On my way agrees to it."))
	eq(MW.Buttons(b), "agree block cancel done other reply room")
	MW.Press(w, b, "agree")
	w:Run(0)
	eq(b.said[#b.said].text, "Booty Bay works for me. On my way!")
	eq(MW.Last(w, b, "P"), "P~" .. mid .. "~1~spot_booty_bay~A")
	eq(a.Match.View().match.fixed, true); eq(b.Match.View().match.fixed, true)
	-- Crossed at the same rev (2): "lida fenn" sorts first, her Goldshire wins on both sides.
	w:Run(5)
	MW.Press(w, a, "other")
	MW.Press(w, b, "other")
	local function RowOf(c, name)
		for i, r in ipairs(MW.Card(c).rows) do if r.shown and r.text:find(name, 1, true) == 1 then return i end end
	end
	MW.Row(w, a, RowOf(a, "Goldshire"))
	MW.Row(w, b, RowOf(b, "Outside the Stormwind gate"))
	w:Run(0)
	eq(a.Match.View().match.place.id, "spot_goldshire"); eq(b.Match.View().match.place.id, "spot_goldshire")
	eq(a.Match.View().match.mine, true); eq(a.Match.View().match.theirs, false)
	eq(b.Match.View().match.mine, false); eq(b.Match.View().match.theirs, true)
	local crossedRoom = assert(b.Match.RoomView(mid))
	assert(HasAction(crossedRoom, "agree"), "the room follows the existing crossed-proposal state")
	-- A higher rev wins: Parric proposes again (rev 3), 3 s later.
	w:Run(3)
	MW.Press(w, b, "other")
	MW.Row(w, b, RowOf(b, "Outside the Stormwind gate"))
	w:Run(0)
	eq(a.Match.View().match.place.id, "spot_stormwind_gate")
	eq(MW.Last(w, b, "P"), "P~" .. mid .. "~3~spot_stormwind_gate~P")
	-- Proposals 3 s apart at most: a second one at once is refused.
	MW.Press(w, b, "other")
	eq(b.Match.Propose("spot_goldshire"), false)
	-- No agreement for 3 min: the match ends on both sides.
	w:Run(181)
	eq(a.Match.View().ended.why, "time"); eq(b.Match.View().ended.why, "time")
	eq(a.Match.ChatRoom(mid).phase, "complete")
	assert(a.Match.RoomView(mid).lines[1]:find("ran out of time", 1, true))
	assert(MW.HasLine(a, "The match ran out of time."))
	MW.NoErrors(w)
end)

test("1.2 matchmaking: getting there: arrival within 60 yd of an arena, 40 of a spot, inside the inn and resting; H~1; You're both here and in duel range; the travel clock, Still coming?, 10 more minutes", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	MW.Press(w, a, "onway")
	w:Run(0)
	-- The travel clock: 5 min + 213.4 / 7 x 1.5 = 345.7 s.
	eq(math.floor(a.Match.TravelTime(213.4) * 10 + 0.5) / 10, 345.7)
	eq(a.Match.TravelTime(100000), 1800)
	-- Lida 65 yd north of the arena's point (-13202.2, 268.2): not there; 55: there (60 for an arena).
	a.pos = { cont = 0, wx = -13137.2, wy = 268.2 }
	w:Run(2)
	eq(a.Match.View().match.here, false)
	a.pos = { cont = 0, wx = -13147.2, wy = 268.2 }
	w:Run(2)
	eq(a.Match.View().match.here, true)
	eq(MW.Last(w, a, "H"), "H~" .. mid .. "~1~0")
	eq(b.Match.View().match.them, true)
	assert(MW.HasLine(a, "Gurubashi Arena: you're there"))
	-- Parric arrives next to her, grouped: both here, in duel range (the game's 3: 10 yd here).
	w:Group({ b, a })
	b.pos = { cont = 0, wx = -13150, wy = 272 }
	w:Run(6)
	eq(a.Match.View().match.both, true)
	assert(MW.HasLine(b, "You're both here. In duel range."), table.concat(MW.Lines(b), " | "))
	assert(MW.HasLine(a, "Them: 0 yd"), table.concat(MW.Lines(a), " | "))
	-- Ten minutes after both arrived, it is over (done).
	w:Run(600)
	eq(a.Match.View().ended.why, "done")
	-- A spot: 40 yd. Booty Bay (-14457.2, 497.9), a staked duel.
	local w2, c, d = Pair({ findable = false })
	Staked(w2, c, d)
	d.Match.SetFindable(true, { d = true, staked = true })
	Matched(w2, c, d, { game = "d", kind = "s", lo = 100000, hi = 100000, level = 0 })
	c.pos = { cont = 0, wx = -14457.2 + 45, wy = 497.9 }
	w2:Run(2)
	eq(c.Match.View().match.here, false)
	c.pos = { cont = 0, wx = -14457.2 + 35, wy = 497.9 }
	w2:Run(2)
	eq(c.Match.View().match.here, true)
	-- An inn: inside its rest area (28 + 5 yd) and resting. The Salty Sailor Tavern (-14457, 496.5).
	local w3, e, f = Pair({ findable = false })
	f.Match.SetFindable(true, { d = false, b = true })
	Matched(w3, e, f, { game = "b", kind = "c" })
	e.pos = { cont = 0, wx = -14457 + 30, wy = 496.5 }
	w3:Run(2)
	eq(e.Match.View().match.here, false, "not resting")
	e.resting = true
	w3:Run(2)
	eq(e.Match.View().match.here, true)
	e.pos = { cont = 0, wx = -14457 + 34, wy = 496.5 }
	w3:Run(2)
	eq(e.Match.View().match.here, false, "outside 33 yd")
	-- Still coming?: nobody there by the clock (345.7 s after both agreed): [10 more minutes].
	local w4, g, h = Pair()
	Matched(w4, g, h, CASUAL)
	MW.Press(w4, g, "onway")
	w4:Run(345)
	eq(g.Match.View().match.still, false)
	w4:Run(2)
	eq(g.Match.View().match.still, true)
	assert(MW.HasLine(g, "Still coming?"))
	-- (Each card asks its own player: both answer here.)
	MW.Press(w4, g, "more")
	MW.Press(w4, h, "more")
	eq(g.Match.View().match.still, false)
	w4:Run(599)
	eq(g.Match.View().state, "match")
	-- Unanswered this time: 5 min later the match ends.
	w4:Run(2)
	eq(g.Match.View().match.still, true)
	w4:Run(300)
	eq(g.Match.View().ended.why, "time")
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3); MW.NoErrors(w4)
end)

test("1.2 matchmaking: combat pauses every clock; two minutes in an instance end the match, its C~i waiting in the lockdown hold", function()
	local w, a, b = Pair()
	Matched(w, a, b, CASUAL)
	-- The place clock (3 min) with both in combat for 100 s: it runs out 100 s later.
	w:Combat(a, true); w:Combat(b, true)
	w:Run(100)
	w:Combat(a, false); w:Combat(b, false)
	w:Run(150)
	eq(a.Match.View().state, "match")
	w:Run(40)
	eq(a.Match.View().ended.why, "time")
	-- (Whichever clock ran out first sent C~t; the other side ended on it.)
	local ct = MW.Last(w, a, "C") or MW.Last(w, b, "C")
	assert(ct and ct:find("^C~M[0-9a-z]+~t$"), tostring(ct))
	eq(b.Match.View().ended.why, "time")
	-- An instance: 2 min, then over; the C~i leaves only once out of it.
	local w2, c, d = Pair()
	local mid = Matched(w2, c, d, CASUAL)
	MW.Press(w2, c, "onway")
	w2:Run(0)
	c.instance = true
	w2:Run(119)
	eq(c.Match.View().state, "match")
	w2:Run(2)
	eq(c.Match.View().ended.why, "instance")
	eq(MW.Last(w2, c, "C"), nil)
	eq(d.Match.View().state, "match")
	c.instance = nil
	w2:Run(2)
	eq(MW.Last(w2, c, "C"), "C~" .. mid .. "~i")
	eq(d.Match.View().ended.why, "instance")
	assert(MW.HasLine(d, "The match ended: one of you went into an instance."))
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: lockdown: the match's AM wait in the hold and the whisper buttons are greyed out", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	w:Lockdown(a, true)
	w:Run(2)
	local card = MW.Card(a)
	for _, key in ipairs({ "onway", "other", "reply", "cancel" }) do eq(card.buttons[key].enabled, false, key) end
	eq(card.buttons.block.enabled, true); eq(card.buttons.done.enabled, true)
	eq(a.Match.Agree(), false)
	-- She reaches the arena: her H~1 waits.
	a.pos = { cont = 0, wx = -13160, wy = 268 }
	w:Run(2)
	eq(MW.Last(w, a, "H"), nil)
	assert(a.Arena.BacklogSize() >= 1)
	w:Lockdown(a, false)
	w:Run(1)
	eq(MW.Last(w, a, "H"), "H~" .. mid .. "~1~0")
	w:Run(2)
	eq(MW.Card(a).buttons.onway.enabled, true)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the privacy line arenaFind: off until answered, never opens the page by itself, needs location, shown only with the arena's tab", function()
	local w = World.New()
	local b = MW.Client(w, "Parric Stowe", {})
	local item
	for _, it in ipairs(b.Consent.Items()) do if it.key == "arenaFind" then item = it end end
	assert(item, "the line")
	eq(L[item.label], "Let other Olympus addon users find me for a duel or a Bones game")
	eq(b.Consent.Answer("arenaFind"), nil)
	eq(select(2, b.Match.Findable()), "off", "nil is off")
	for _, it in ipairs(b.Consent.Pending()) do assert(it.key ~= "arenaFind", "never waits for an answer") end
	eq(b.Consent.Choose("arenaFind", true), true)
	eq(b.Consent.Answer("arenaFind"), true)
	eq(b.Match.Findable(), true)
	eq(Printed(b, "Other Olympus addon users can find you for a duel or a Bones game."), 1)
	-- Location off: the line's note, and nobody finds him.
	b.db.shareLocation = false
	eq(w:As(b, item.note), L.CONSENT_NEEDS_LOCATION)
	eq(select(2, b.Match.Findable()), "location")
	b.db.shareLocation = true
	eq(w:As(b, item.note), nil)
	-- The arena off on this client: the tab is gone, and the line with it.
	b.Arena.SetOff(true)
	local shown = false
	for _, it in ipairs(b.Consent.Items()) do if it.key == "arenaFind" then shown = true end end
	eq(shown, false)
	b.Arena.SetOff(false)
	-- The Find dialog's switch: Duels, Bone Throw, Staked too.
	b.Match.SetFindable(true, { d = true, b = false, staked = true })
	local v = b.Match.View().findable
	eq(v.on, true); eq(v.games.d, true); eq(v.games.b, false); eq(v.staked, true)
	b.Match.SetFindable(false)
	eq(b.Consent.Answer("arenaFind"), false)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: weight: a client neither findable nor searching gets 100 asks and makes no frame, event or timer; a findable one's delayed answer starts the ticker, which stops after", function()
	local w = World.New()
	local idle = MW.Client(w, "Wenna Crale", {})
	local before = w:ArenaWeight(idle)
	for i = 1, 100 do
		w:As(idle, function() idle.ns.Arena.Inject("CHANNEL", "Morrow Vale-Emberfall", "AM~L1~Q~q" .. i .. "~d~c~Olympus Ash~0~13u~0~1o~1~2s~z~2s") end)
	end
	local after = w:ArenaWeight(idle)
	eq(table.concat(after.events, ","), table.concat(before.events, ","))
	eq(after.timers, before.timers); eq(after.frames, before.frames)
	eq(idle.Arena.Ticking(), false)
	eq(idle.Match.Stats().heard, 0, "returned at the first flag")
	eq(idle.Match.Card(), nil)
	-- Findable: the answer's pause runs the ticker, which stops once it went.
	local b = MW.Client(w, "Parric Stowe", { findable = true })
	eq(b.Arena.Ticking(), false)
	w:As(b, function() b.ns.Arena.Inject("CHANNEL", "Morrow Vale-Emberfall", "AM~L1~Q~qq~d~c~Olympus Ash~0~13u~0~1o~1~2s~z~2s") end)
	eq(b.Arena.Ticking(), true)
	w:Run(4)
	eq(b.Match.Stats().offers, 1)
	eq(b.Arena.Ticking(), false)
	eq(b.Match.Card(), nil, "no frame for an answer")
	-- A search: involved, and not after.
	local a = MW.Client(w, "Lida Fenn", {})
	assert(a.Match.Start(CASUAL))
	local inv = table.concat(a.Arena.Involved(), ",")
	assert(inv:find("match", 1, true), inv)
	a.Match.Stop()
	w:Run(3)
	assert(not table.concat(a.Arena.Involved(), ","):find("match", 1, true))
	eq(w:Events(a, true).CHAT_MSG_WHISPER, nil, "the addon never reads whispers")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: the card: built on first use, on the escape list only through ns.EscapeCloses (never with the gamepad UI), buttons 24 px or taller, text 13 px or more; Reply opens Olympus's whisper dialog; pins", function()
	local w, a, b = Pair()
	eq(a.Match.Card(), nil)
	-- The pin library (HereBeDragons-Pins) as the client has it: what goes where.
	local pins = { mini = {}, world = {} }
	local P = {
		AddMinimapIconMap = function(_, ref, icon, mapID, x, y) pins.mini[#pins.mini + 1] = { mapID, x, y } end,
		AddWorldMapIconMap = function(_, ref, icon, mapID, x, y) pins.world[#pins.world + 1] = { mapID, x, y } end,
		AddMinimapIconWorld = function(_, ref, icon, inst, x, y) pins.mini[#pins.mini + 1] = { "world", inst, x, y } end,
		AddWorldMapIconWorld = function(_, ref, icon, inst, x, y) pins.world[#pins.world + 1] = { "world", inst, x, y } end,
		RemoveAllMinimapIcons = function() pins.mini = {} end,
		RemoveAllWorldMapIcons = function() pins.world = {} end,
	}
	a.globals.LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return P end end
	Matched(w, a, b, CASUAL)
	local card = MW.Card(a)
	eq(card.name, "OlympusArenaMatchCard")
	local special = false
	for _, n in ipairs(a.globals.UISpecialFrames) do if n == "OlympusArenaMatchCard" then special = true end end
	eq(special, true)
	for key, btn in pairs(card.buttons) do assert((btn.height or 0) >= 24, key .. ": " .. tostring(btn.height)) end
	for _, fs in ipairs(card.lines) do if fs.shown then assert(fs.font[2] >= 13, "a line at " .. fs.font[2]) end end
	assert(card.title.font[2] >= 16)
	-- The popup, as Olympus's own dialog (Dialog.lua, the gamepad UI) draws it: 24 px buttons, and
	-- the client's 14 px white font for its text (GameFontHighlightMed2: SystemFont_Shadow_Med2,
	-- FRIZQT 14 in Forever's Fonts.xml); tests/run.lua checks Dialog.lua honours both.
	local def = b.popups.OLYMPUS_ARENA_MATCH
	eq(def.buttonHeight, 24); eq(def.textFont, "GameFontHighlightMed2")
	eq(MW.Buttons(a):find("map", 1, true), nil, "[Show on map] waits for in-game check 21")
	-- The arena's pin: its map and map position, on the minimap and the world map.
	eq(pins.mini[1][1], 1434); eq(pins.mini[1][2], 0.306); eq(pins.mini[1][3], 0.478)
	eq(#pins.world, 1)
	MW.Press(w, a, "reply")
	eq(a.whisperWindow[1], "Parric Stowe")
	MW.Press(w, a, "cancel")
	eq(#pins.mini, 0); eq(#pins.world, 0)
	-- With the gamepad UI: no escape list, no world-map pin.
	H.WithGamepadUI(true, function()
		local w2 = World.New()
		local c = MW.Client(w2, "Lida Fenn", { pos = SEEKER })
		local d = MW.Client(w2, "Parric Stowe", { pos = OTHER, findable = true })
		c.globals.LibStub = a.globals.LibStub
		pins.mini, pins.world = {}, {}
		-- Parric's dialog is Olympus's own window here (Dialog.lua), from the game's global table of
		-- definitions (the world keeps each client's apart: put back for this one).
		-- Parric's dialog: Olympus's own window (Dialog.lua, a stand-in recording it here), never
		-- the game's popup.
		local game = 0
		d.globals.StaticPopup_Show = function() game = game + 1 end
		rawset(d.ns, "Dialog", { missing = false, Hide = function() end, Show = function(which, a2, b2, data)
			d.shown[#d.shown + 1] = { which = which, a = a2, b = b2, data = data, own = true }
		end })
		assert(c.Match.Start(CASUAL))
		w2:Run(6)
		eq(game, 0)
		eq(d.shown[1].own, true)
		assert(d.shown[1].a:find("^Lida Fenn %(60 Warrior%) wants a casual duel"), d.shown[1].a)
		MW.Answer(w2, d, "yes")
		w2:Run(0)
		eq(d.said[1].text:sub(1, 49), "Hi! Olympus matched us for a casual duel. Meet at")
		eq(c.Match.View().state, "match")
		for _, n in ipairs(c.globals.UISpecialFrames) do assert(n ~= "OlympusArenaMatchCard") end
		eq(#pins.mini, 1); eq(#pins.world, 0)
		MW.NoErrors(w2)
	end)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: a Where I am point's pin goes through the HereBeDragons helper (the two values swapped)", function()
	local w, a, b = Pair()
	local mini = {}
	local P = {
		AddMinimapIconMap = function() end, AddWorldMapIconMap = function() end,
		AddMinimapIconWorld = function(_, ref, icon, inst, x, y) mini[#mini + 1] = { inst, x, y } end,
		RemoveAllMinimapIcons = function() mini = {} end, RemoveAllWorldMapIcons = function() end,
	}
	b.globals.LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return P end end
	a.mapPos = { 0.3, 0.45 }
	Matched(w, a, b, CASUAL)
	MW.Press(w, a, "other")
	local where
	for i, r in ipairs(MW.Card(a).rows) do if r.shown and r.text == "Where I am" then where = i end end
	MW.Row(w, a, where)
	w:Run(0)
	-- Lida's point: steps 280 and 812 of 25 yd, centres 280 x 25 - 20000 + 12.5 = -12987.5 and
	-- 812 x 25 - 20000 + 12.5 = 312.5; HereBeDragons gets (312.5, -12987.5).
	eq(mini[1][1], 0); eq(mini[1][2], 312.5); eq(mini[1][3], -12987.5)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: match.open and /oly arena find: the screens' Find dialog when there, else the card's short sheet the first time (what goes out), with location off its two share buttons", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	a.companion.state = "missing"
	eq(a.Arena.Do("match.open", "d"), true)
	local card = MW.Card(a)
	eq(card.title.text, "Find an opponent")
	assert(MW.HasLine(a, L.MATCH_FIRST_LINE))
	assert(MW.HasLine(a, "Stakes are rehearsal chips on this realm for now."))
	eq(MW.Buttons(a), "notnow search")
	MW.Press(w, a, "search")
	eq(a.Match.View().state, "search")
	eq(a.db.arenaMatch.seen, true)
	eq(MW.Card(a).title.text, "Finding an opponent")
	-- /oly arena find cancel: the search ends.
	w:As(a, function() a.ns.Arena.RunSlash("find cancel") end)
	eq(a.Match.View().state, "idle")
	-- Location off: share while searching (off again after), or turn it on.
	local b = MW.Client(w, "Parric Stowe", { pos = OTHER, sharing = false })
	b.companion.state = "missing"
	eq(select(2, b.Match.Start(CASUAL)), "location")
	eq(b.Arena.Do("match.open", "b"), true)
	assert(MW.HasLine(b, "Finding someone needs your zone: share it while you search, or turn location sharing on."))
	eq(MW.Buttons(b), "notnow shareon sharewhile")
	MW.Press(w, b, "sharewhile")
	eq(b.Match.View().state, "search")
	eq(b.db.shareLocation, true)
	b.Match.Stop()
	eq(b.db.shareLocation, nil, "back as it was")
	eq(table.concat((function() local t = {} for _, v in ipairs(b.sharingSet) do t[#t + 1] = tostring(v) end return t end)(), ","), "true,false")
	-- the screens' Find dialog, once the companion has it.
	local got
	local c = MW.Client(w, "Wenna Crale", { pos = SEEKER })
	w:As(c, function() assert(c.ns.Arena.LoadUI()) end)
	c.ns.Arena.ui.OpenFind = function(game) got = game end
	w:As(c, function() c.ns.Arena.RunSlash("find bone") end)
	eq(got, "b")
	eq(c.Arena.Do("match.open", "d"), true)
	eq(got, "d")
	-- Outside an Olympus guild: no.
	-- (World:Client's guild = false gives the default guild: taken off here.)
	local x = MW.Client(w, "Morrow Vale", {})
	x.guild = nil
	eq(select(2, x.Arena.Do("match.open", "d")), "guild")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: staked where saved data is lost (the beta) or the stake checks say no: greyed out with the reason; casual still works; Standing.Cap bounds the range", function()
	local w, a, b = Pair()
	local v = a.Match.View()
	eq(v.staked.d.ok, false); eq(v.staked.d.why, "persists")
	eq(v.staked.d.text, "Stakes are off on this realm (saved data is lost at every login): casual games only.")
	eq(select(2, a.Match.Start({ game = "d", kind = "s", lo = 100000, hi = 200000 })), "persists")
	eq(a.Match.Start(CASUAL), true)
	a.Match.Stop()
	-- Saved data kept, but the fights part's check refuses (a debtor, say): its reason.
	local w2 = World.New()
	local c = MW.Client(w2, "Lida Fenn", {})
	MW.Reload(w2, c)
	StakesOK(c, false, "debtor")
	eq(c.Match.View().staked.d.why, "debtor")
	eq(select(2, c.Match.Start({ game = "d", kind = "s", lo = 100000, hi = 200000 })), "debtor")
	-- Checks yes, a cap of 30g (the money part's Standing.Cap, a stand-in): 20g to 50g becomes 20g to 30g.
	StakesOK(c)
	rawset(c.ns, "Standing", { Cap = function(kind, name) return kind == "bet" and name == c.name and 300000 or 0 end })
	eq(c.Match.View().stakeMax, 300000)
	assert(c.Match.Start({ game = "d", kind = "s", lo = 200000, hi = 500000, level = 0 }))
	eq(c.Match.View().search.lo, 200000); eq(c.Match.View().search.hi, 300000)
	-- No range at all: pick one first.
	c.Match.Stop()
	eq(select(2, c.Match.Start({ game = "d", kind = "s", lo = 0, hi = 0 })), "stake")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: the registry: AM in Arena.TYPES, LIVE_EXEMPT, Moderation.BLOCKED and Comm's list; one literal Comm.Handle(\"AM\" in ArenaMatch.lua; ids of letter M; the status line", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", {})
	eq(a.ns.Arena.TYPES.AM, "ArenaMatch")
	eq(a.ns.Arena.LIVE_EXEMPT.AM, true)
	eq(a.ns.Moderation.BLOCKED.AM, true)
	assert(Read(H.ADDON_DIR .. "Comm.lua"):find("ArenaMatch AM", 1, true))
	local src = Read(H.ADDON_DIR .. "ArenaMatch.lua"):gsub("%-%-[^\n]*", "")
	local n = select(2, src:gsub('Comm%.Handle%("AM"', ""))
	eq(n, 1)
	assert(src:find('ns.Comm.Handle("AM", ns.Arena.Handle("AM", OnMatch))', 1, true))
	eq(w:As(a, a.ns.Arena.NewId, "M"):sub(1, 1), "M")
	-- Sent in L with the live switch off (a match moves nothing).
	eq(a.Roles.Live(), false)
	eq(a.Arena.Send("AM", "L", "Q~x"), true)
	-- /oly arena find status: one line of counts, in the copy pop-up (the owner's rule: what a
	-- player may copy never goes to chat); matchmaking itself adds no /oly status provider.
	local statusLines = #a.ns.statusLines
	local printed = #a.printed
	w:As(a, function() a.ns.Arena.RunSlash("find status") end)
	eq(#a.printed, printed, "nothing in chat")
	eq(a.copied[1].title, "Finding an opponent: the counts")
	assert(a.copied[1].text:find("^match: findable=false off  |  asks=0 heard=0"), a.copied[1].text)
	eq(#a.ns.statusLines, statusLines)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: late and lost answers: a yes to a request given up gets C~t; a popup our own clock ends (35 s) says no and goes; the click helper catches a whisper outside a click", function()
	local w, a, b = Pair()
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	-- Nobody answers the dialog, and the game never ends it: 35 s later, a no, and it goes.
	w:Run(36)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~N")
	eq(b.hidden[#b.hidden].which, "OLYMPUS_ARENA_MATCH")
	eq(b.Match.View().state, "idle")
	-- A yes that comes after Lida gave up (her Cancel): its match ends there at once.
	local w2, c, d = Pair()
	assert(c.Match.Start(CASUAL))
	w2:Run(6)
	local mid2 = MW.Last(w2, c, "R"):match("^R~(M[0-9a-z]+)~")
	c.Match.Stop()
	w2:As(c, function() c.ns.Arena.Inject("WHISPER", d.name, "AM~L1~A~" .. mid2 .. "~Y~arena_gurubashi~g~1e~13u~0~0~0~0") end)
	w2:Run(0)
	eq(MW.Last(w2, c, "C"), "C~" .. mid2 .. "~t")
	eq(c.Match.View().state, "idle")
	-- The same yes 19 times more: still one C~t (no whisper back for each).
	for _ = 1, 19 do
		w2:As(c, function() c.ns.Arena.Inject("WHISPER", d.name, "AM~L1~A~" .. mid2 .. "~Y~arena_gurubashi~g~1e~13u~0~0~0~0") end)
	end
	w2:Run(0)
	local ct = 0
	for _, m in ipairs(MW.AM(w2, c)) do if m == "C~" .. mid2 .. "~t" then ct = ct + 1 end end
	eq(ct, 1)
	-- The harness's click rule itself: a whisper from code, outside a click, fails.
	local w3, e, f = Pair()
	Matched(w3, e, f, CASUAL)
	eq(pcall(e.Match.Agree), false)
	eq(w3.unclicked[1], "Lida Fenn: C_ChatInfo.SendChatMessage")
	w3.unclicked = {}
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking: different layers at the spot, not grouped: the card says so and [Join their layer] asks Hop; Close by proposed from Other spot", function()
	local w, a, b = Pair()
	local mid = Matched(w, a, b, CASUAL)
	MW.Press(w, a, "onway")
	-- Lida on layer 11 of Stranglethorn, Parric on 12 (his H carries it: "c").
	a.layer = { mapID = 1434, zoneUID = 11, t = w.clock }
	b.layer = { mapID = 1434, zoneUID = 12, t = w.clock }
	a.pos = { cont = 0, wx = -13200, wy = 268 }
	b.pos = { cont = 0, wx = -13210, wy = 270 }
	w:Run(6)
	eq(MW.Last(w, b, "H"), "H~" .. mid .. "~1~c")
	assert(MW.HasLine(a, "You're on different layers: join theirs to see each other."), table.concat(MW.Lines(a), " | "))
	MW.Press(w, a, "join")
	eq(a.hopAsks[1].mapID, 1434); eq(a.hopAsks[1].zoneUID, 12)
	-- Close by, from the list of other spots: "=" and its line.
	w:Run(3)
	MW.Press(w, b, "other")
	local close
	for i, r in ipairs(MW.Card(b).rows) do if r.shown and r.text == "Close by" then close = i end end
	MW.Row(w, b, close)
	w:Run(0)
	eq(MW.Last(w, b, "P"), "P~" .. mid .. "~1~=~P")
	eq(b.said[#b.said].text, "How about right here? We're close by.")
	eq(a.Match.View().match.place.id, "=")
	MW.NoErrors(w)
end)

test("1.2 matchmaking: memory: past 256 senders, the asks, answers and offers older than their rule's span are forgotten", function()
	local w = World.New()
	local b = MW.Client(w, "Parric Stowe", { findable = true })
	local function Ask(i)
		w:As(b, function() b.ns.Arena.Inject("CHANNEL", ("Asker%03d Vale-Emberfall"):format(i), "AM~L1~Q~q" .. i .. "~d~c~Olympus Ash~0~13u~0~1o~1~2s~z~2s") end)
	end
	for i = 1, 200 do Ask(i) end
	w:Run(5)
	eq(b.Match.Memory().heard, 200)
	eq(b.Match.Memory().answered, 1, "one offer in those 10 s")
	w:Run(900)
	for i = 201, 260 do Ask(i) end
	-- The 257th new sender swept the 200 asks older than 15 min, the first answer (past 10 min)
	-- and its offer (past 2 min): 60 senders are left, and the one answer since (Asker201's,
	-- whose offer waits for its pause).
	local m = b.Match.Memory()
	eq(m.heard, 60)
	eq(m.answered, 1); eq(m.offered, 0)
	w:Run(5)
	eq(b.Match.Memory().offered, 1)
	MW.NoErrors(w)
end)

test("1.2 matchmaking: ns.SayTo: C_ChatInfo.SendChatMessage where the client has it, else the global one; at most 255 bytes, never half a letter; nothing without a name or a text", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", {})
	-- 254 bytes, then "é" (two bytes): cut before it, at 254.
	local long = ("x"):rep(254) .. "é" .. "tail"
	eq(MW.Click(w, a, a.ns.SayTo, "Parric Stowe", long), true)
	eq(#a.said[1].text, 254); eq(a.said[1].to, "Parric Stowe"); eq(a.said[1].kind, "WHISPER"); eq(a.said[1].global, nil)
	local api = a.globals.C_ChatInfo.SendChatMessage
	a.globals.C_ChatInfo.SendChatMessage = nil
	eq(MW.Click(w, a, a.ns.SayTo, "Parric Stowe", "hi"), true)
	eq(a.said[2].global, true)
	local global = a.globals.SendChatMessage
	a.globals.SendChatMessage = false
	eq(MW.Click(w, a, a.ns.SayTo, "Parric Stowe", "hi"), false)
	a.globals.SendChatMessage, a.globals.C_ChatInfo.SendChatMessage = global, api
	eq(MW.Click(w, a, a.ns.SayTo, "", "hi"), false)
	eq(MW.Click(w, a, a.ns.SayTo, "Parric Stowe", ""), false)
	eq(#a.said, 2)
	MW.NoErrors(w)
end)

---------------------------------------------------------------------------
-- The review of matchmaking (its two reports): each case below failed before its fix, or covers a check
-- no test reached.
---------------------------------------------------------------------------

test("1.2 matchmaking review: the stake checks in the fights part's and the Bone Throw tables' own shapes: the other player's name once known, the lower end of the range in copper; the Bone Throw tables' inn rule never stops a match", function()
	-- The checks as their branches answer today, "opponent" and "guest" while nobody is named: the
	-- Find dialog still offers Staked, and the search starts.
	local w, a, b = Pair({ findable = false })
	for _, c in ipairs({ a, b }) do MW.Reload(w, c) StakesOK(c, true, nil, { today = true }) HighCap(c) end
	b.Match.SetFindable(true, { d = true, b = true, staked = true })
	eq(a.Match.View().staked.d.ok, true); eq(a.Match.View().staked.b.ok, true)
	local mid = Matched(w, a, b, { game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 })
	assert(mid and a.Match.View().state == "match", a.Match.View().state)
	-- Lida's: the Find dialog's (nobody, 1 silver), her search's (nobody, 50g = 500000 copper),
	-- then Parric's offer's (his name, the lower end). Parric's: her ask's (her name, 1 silver: no
	-- range of his own), then her request's (her name, 50g).
	for _, k in ipairs({ "d - 100", "d - 500000", "d Parric 500000" }) do assert(HasCheck(a, k), k .. ": " .. table.concat(Checks(a), ", ")) end
	for _, k in ipairs({ "d Lida 100", "d Lida 500000" }) do assert(HasCheck(b, k), k .. ": " .. table.concat(Checks(b), ", ")) end
	-- A check that refuses one player by name (the fights part's cap for him, say): his offer is passed over
	-- (Resolve), and nobody is asked.
	local w2 = World.New()
	local c = MW.Client(w2, "Lida Fenn", { pos = SEEKER })
	local d = MW.Client(w2, "Parric Stowe", { pos = OTHER })
	MW.Reload(w2, c); MW.Reload(w2, d)
	StakesOK(c, true, nil, { today = true, rule = function(name) if name == d.name then return false, "cap" end return true end })
	StakesOK(d, true, nil, { today = true })
	HighCap(c); HighCap(d)
	d.Match.SetFindable(true, { d = true, staked = true })
	assert(c.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 }))
	w2:Run(6)
	eq(c.Match.View().search.answers, 1, "Parric answered")
	eq(MW.Last(w2, c, "R"), nil, "and is not asked")
	assert(HasCheck(c, "d Parric 500000"))
	-- On the answering side the same check with the asker's name: Parric's rule refuses Lida (her
	-- alt, say), so his answer offers her no stake, and she asks him for a casual duel.
	local w3 = World.New()
	local e = MW.Client(w3, "Lida Fenn", { pos = SEEKER })
	local f = MW.Client(w3, "Parric Stowe", { pos = OTHER })
	MW.Reload(w3, e); MW.Reload(w3, f)
	StakesOK(e)
	StakesOK(f, true, nil, { rule = function(name) if name == e.name then return false, "alts" end return true end })
	HighCap(e); HighCap(f)
	f.Match.SetFindable(true, { d = true, staked = true })
	assert(e.Match.Start({ game = "d", kind = "e", lo = 500000, hi = 1000000, level = 0 }))
	w3:Run(6)
	eq(MW.Last(w3, f, "O"), "O~9ix~f~Olympus Ember~1~1o~1~d~c~0")
	assert(MW.Last(w3, e, "R"):find("^R~M[0-9a-z]+~9ix~d~c~0~0~"), MW.Last(w3, e, "R"))
	-- the Bone Throw tables' inn rule (the design) answers a named guest with a stake ("tavern-rest"): the two are not at
	-- the inn while matching, and the Bone Throw tables applies it when the table is created: the match goes on.
	local w4 = World.New()
	local g = MW.Client(w4, "Lida Fenn", { pos = SEEKER })
	local h = MW.Client(w4, "Parric Stowe", { pos = OTHER })
	MW.Reload(w4, g); MW.Reload(w4, h)
	StakesOK(g, true, nil, { tavern = true }); StakesOK(h, true, nil, { tavern = true })
	HighCap(g); HighCap(h)
	h.Match.SetFindable(true, { d = false, b = true, staked = true })
	Matched(w4, g, h, { game = "b", kind = "s", lo = 100000, hi = 200000, level = 0 })
	eq(g.Match.View().state, "match")
	assert(HasCheck(g, "b Parric 100000"), table.concat(Checks(g), ", "))
	assert(HasCheck(h, "b Lida 100000"), table.concat(Checks(h), ", "))
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3); MW.NoErrors(w4)
end)

test("1.2 matchmaking review: an instance ends a search at once (sharing turned on for it goes back) and pauses no clock; combat and a chat lockdown still do", function()
	local w, a = Pair({ findable = false })
	a.db.shareLocation = false
	assert(a.Match.Start({ game = "d", kind = "c", level = 5, share = true }))
	eq(a.db.shareLocation, true)
	a.instance = true
	w:Run(2)
	eq(a.Match.View().state, "idle")
	eq(a.db.shareLocation, false, "back as it was")
	eq(Printed(a, "The search for an opponent ended: no search from an instance."), 1)
	assert(not table.concat(a.Arena.Involved(), ","):find("match", 1, true))
	a.instance = nil
	w:Run(700)
	eq(#w:Sent{ from = a, type = "AM", dist = "CHANNEL" }, 1, "nothing asked after it")
	-- A match: its place clock (3 min) runs on while both are in an instance (100 s of it, under
	-- the 2 min that end a match there): over 180 s after Let's go, not 280.
	local w2, c, d = Pair()
	Matched(w2, c, d, CASUAL)
	w2:Run(60)
	c.instance, d.instance = true, true
	w2:Run(100)
	c.instance, d.instance = nil, nil
	w2:Run(15)
	eq(c.Match.View().state, "match", "175 s")
	w2:Run(10)
	eq(c.Match.View().ended.why, "time"); eq(d.Match.View().ended.why, "time")
	-- A chat lockdown still pauses them (our messages wait in the hold): 100 s of it, over at 280 s.
	local w3, e, f = Pair()
	Matched(w3, e, f, CASUAL)
	w3:Run(60)
	w3:Lockdown(e, true); w3:Lockdown(f, true)
	w3:Run(100)
	w3:Lockdown(e, false); w3:Lockdown(f, false)
	w3:Run(115)
	eq(e.Match.View().state, "match", "275 s")
	w3:Run(10)
	eq(e.Match.View().ended.why, "time")
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3)
end)

test("1.2 matchmaking review: the group a match formed is never left from code inside an instance; the ended card offers Leave group, the player's click", function()
	local w, a, b = Pair()
	Matched(w, a, b, CASUAL)
	eq(b.invited[1], "Lida Fenn")
	w:Group({ b, a })
	a.instance, b.instance = true, true
	w:Run(125)
	eq(a.Match.View().ended.why, "instance"); eq(b.Match.View().ended.why, "instance")
	eq(a.left + b.left, 0, "nobody taken out of the dungeon's group")
	assert(MW.Buttons(a):find("leave", 1, true), MW.Buttons(a))
	-- Out again: the two C~i go (each side's match is over already): nobody leaves from code.
	a.instance, b.instance = nil, nil
	w:Run(3)
	eq(a.left + b.left, 0)
	MW.Press(w, a, "leave")
	eq(a.left, 1)
	eq(a.groupId, nil); eq(b.groupId, nil)
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: Let's go that cannot go through (a chat lockdown) is a plain no with the reason, never a decline or a strike; in combat it goes through", function()
	local w, a, b = Pair()
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	w:Lockdown(b, true)
	MW.Answer(w, b, "yes")
	eq(Printed(b, "Not from an instance or while chat is locked down."), 1)
	eq(b.Match.View().state, "idle")
	eq(#b.said, 0, "no whisper")
	eq(b.Match.Barred(a.name), nil, "Lida is not declined")
	eq(b.db.arenaMatch.noes or 0, 0, "no strike towards the 30-min pause")
	w:Lockdown(b, false)
	w:Run(1)
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~N", "the no, once the lockdown is over")
	eq(b.Match.Findable(), true)
	-- Combat: whispers and invites work there (and the match's clocks wait for it).
	local w2, c, d = Pair()
	assert(c.Match.Start(CASUAL))
	w2:Run(6)
	w2:Combat(d, true)
	MW.Answer(w2, d, "yes")
	w2:Run(0)
	eq(d.Match.View().state, "match"); eq(c.Match.View().state, "match")
	eq(#d.said, 1); eq(d.invited[1], "Lida Fenn")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking review: the King's search asks once more after 20 s, and his card says when nobody answered", function()
	local w = World.New()
	local king = MW.Client(w, World.NAMES.king, { guild = World.KING_GUILD, rank = 0, pos = SEEKER })
	king.db.throneLocation = true
	assert(king.Match.Start(CASUAL))
	w:Run(19)
	eq(#w:Sent{ from = king, type = "AM", dist = "CHANNEL" }, 1)
	assert(MW.HasLine(king, "No answer yet from a guildmate or an officer the census knows."))
	w:Run(2)
	eq(#w:Sent{ from = king, type = "AM", dist = "CHANNEL" }, 2, "the second ask")
	w:Run(5)
	assert(MW.HasLine(king, "Nobody nearby right now. Answers that still come in show here."), table.concat(MW.Lines(king), " | "))
	eq(MW.HasLine(king, "No answer yet from a guildmate or an officer the census knows."), false, "said once")
	eq(Printed(king, "Nobody nearby"), 0, "on his card, not in chat")
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: the King's chat shows names masked (his request's line with the card closed, a block)", function()
	local w = World.New()
	local king = MW.Client(w, World.NAMES.king, { guild = World.KING_GUILD, rank = 0, pos = SEEKER })
	local b = MW.Client(w, "Parric Stowe", { pos = OTHER, findable = true })
	king.db.throneLocation = true
	king.trusted[b.name] = true
	rawset(king.ns, "CouncilMasked", function() return true end)
	assert(king.Match.Start(CASUAL))
	w:Run(10)
	local id = king.Match.View().offers[1].id
	-- His card closed (its X): the request's line goes to chat.
	MW.Card(king):Hide()
	eq(king.Match.Pick(id), true)
	eq(Printed(king, "Asking Parr****..."), 1)
	w:Run(0)
	MW.Answer(w, b, "yes")
	w:Run(0)
	MW.Press(w, king, "block")
	eq(Printed(king, "Parr**** is blocked."), 1)
	eq(Printed(king, "Parric"), 0, "the name never in his chat")
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: a lie is caught on each test: a searcher's answer to a zone ask whose yes names another zone", function()
	local w, a, b = Pair({ findable = false })
	-- Parric searches (his answer carries his cell, 16/50), then Lida asks her zone.
	b.qid = 999
	assert(b.Match.Start({ game = "d", kind = "c", level = 0 }))
	w:Run(30)
	assert(a.Match.Start(CASUAL))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	-- His yes: the same cell (no speed to it), but Westfall's map (1436 = "13w").
	w:As(a, function() a.ns.Arena.Inject("WHISPER", b.name, "AM~L1~A~" .. mid .. "~Y~arena_gurubashi~g~1e~13w~0~0~0~0") end)
	w:Run(0)
	eq(a.Match.Stats().lies, 1)
	eq(a.Match.Barred(b.name), "lied")
	eq(a.Match.View().state, "search")
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: a Where I am point on the card and the status line, from the reader's side: Your spot, and {name}'s spot", function()
	local w, a, b = Pair()
	a.mapPos = { 0.3123, 0.4551 }
	Matched(w, a, b, CASUAL)
	MW.Press(w, a, "other")
	local where
	for i, r in ipairs(MW.Card(a).rows) do if r.shown and r.text == "Where I am" then where = i end end
	MW.Row(w, a, where)
	w:Run(2)
	-- Lida's point: steps 280 / 812, centre (-12987.5, 312.5), 17.7 yd from her: she is there.
	-- From Parric (-13400, 250): 412.5 north and 62.5 west, 417.2 yd (420), north.
	eq(a.Match.View().line, "Meeting Parric Stowe at Your spot")
	eq(b.Match.View().line, "Meeting Lida Fenn at Lida Fenn's spot")
	eq(a.Match.View().match.place.name, "Your spot"); eq(b.Match.View().match.place.name, "Lida Fenn's spot")
	assert(MW.HasLine(a, "Your spot: you're there"), table.concat(MW.Lines(a), " | "))
	assert(MW.HasLine(b, "Lida Fenn's spot: 420 yd north"), table.concat(MW.Lines(b), " | "))
	-- His whisper names it from his side, to her: her spot is "Your spot".
	MW.Press(w, b, "agree")
	eq(b.said[#b.said].text, "Your spot works for me. On my way!")
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: the privacy line asks ArenaHome's rule while the companion is not loaded", function()
	local w = World.New()
	local b = MW.Client(w, "Parric Stowe", {})
	eq(b.ns.Arena.ui, nil, "the companion not loaded")
	local function Shown()
		for _, it in ipairs(b.Consent.Items()) do if it.key == "arenaFind" then return true end end
		return false
	end
	eq(Shown(), true, "the stub's rule: a member, the arena on")
	b.ns.ArenaHome.TabVisible = function() return false end
	eq(Shown(), false, "ArenaHome's rule: the tab hidden (the King's switch, say)")
	b.ns.ArenaHome.TabVisible = function() return true end
	eq(Shown(), true)
	b.ns.ArenaHome.TabVisible = nil
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: the checks no test reached: the answer's range inside the seeker's, a group of more than the match's two, the King's account and a request, the 2-min window, Bone Throw's group on the found side, free-for-all ground", function()
	-- An answer whose range is not inside the seeker's (50g-100g asked; 40g-100g answered, 4000
	-- silver = "334"): refused with C~c, and the search goes on.
	local w, a, b = Pair({ findable = false })
	Staked(w, a, b)
	b.Match.SetFindable(true, { d = true, staked = true })
	assert(a.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 }))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	w:As(a, function() a.ns.Arena.Inject("WHISPER", b.name, "AM~L1~A~" .. mid .. "~Y~spot_booty_bay~g~1e~13u~0~334~7ps~0") end)
	w:Run(0)
	eq(MW.Last(w, a, "C"), "C~" .. mid .. "~c")
	eq(a.Match.View().state, "search")
	eq(a.Match.Stats().lies, 0, "no lie: a refusal")
	-- The group the match formed, joined by a third: not the match's two any more, so not left.
	local w2, c, d = Pair()
	local x = MW.Client(w2, "Wenna Crale", {})
	Matched(w2, c, d, CASUAL)
	eq(d.invited[1], "Lida Fenn")
	w2:Group({ d, c, x })
	MW.Press(w2, c, "done")
	w2:Run(0)
	eq(c.left + d.left, 0)
	-- A character of the King's account that offered before the account knew it (the King's name
	-- added to it since): a request then gets no answer at all, not even a no.
	local w3 = World.New()
	local alt = MW.Client(w3, "Aldric Stone", { pos = OTHER, findable = true })
	local e = MW.Client(w3, "Lida Fenn", { pos = SEEKER })
	assert(e.Match.Start(CASUAL))
	w3:Run(1)
	eq(#MW.AM(w3, alt, e.name), 1, "his offer")
	alt.db.myCharacters = { [World.NAMES.king:lower()] = true }
	w3:Run(5)
	assert(MW.Last(w3, e, "R"), "her request")
	eq(#MW.AM(w3, alt, e.name), 1, "no answer to it")
	eq(MW.Popup(alt), nil)
	-- A request more than 2 min after the offer it answers: dropped, no popup and no answer.
	local w4 = World.New()
	local f = MW.Client(w4, "Parric Stowe", { pos = OTHER, findable = true })
	local g = MW.Client(w4, "Lida Fenn", { pos = SEEKER })
	assert(g.Match.Start(CASUAL))
	w4:Run(1)
	g.Match.Stop()
	w4:Run(121)
	w4:As(f, function() f.ns.Arena.Inject("WHISPER", g.name, "AM~L1~R~Mlate1~9ix~d~c~0~0~1o~1~h~1e~0") end)
	w4:Run(0)
	eq(MW.Popup(f), nil); eq(MW.Last(w4, f, "A"), nil)
	-- Bone Throw from someone in a group he cannot invite into (grp 2), to a player in none: no
	-- group is possible, so A~N (the seeker's own filter would not have asked; this is the found
	-- side's).
	local w5 = World.New()
	local h = MW.Client(w5, "Parric Stowe", { pos = OTHER })
	h.Match.SetFindable(true, { d = false, b = true })
	local k = MW.Client(w5, "Lida Fenn", { pos = SEEKER })
	assert(k.Match.Start({ game = "b", kind = "c", level = 5 }))
	w5:Run(1)
	eq(#MW.AM(w5, h, k.name), 1, "his offer")
	k.Match.Stop()
	w5:As(h, function() h.ns.Arena.Inject("WHISPER", k.name, "AM~L1~R~Mgrp1~9ix~b~c~0~0~1o~1~h~1e~2") end)
	w5:Run(0)
	eq(MW.Last(w5, h, "A"), "A~Mgrp1~N"); eq(MW.Popup(h), nil)
	-- A staked duel is never suggested at the Gurubashi floor (free-for-all), but the place is only
	-- a suggestion (the design): the card says so while the player stands on it, within 60 yd.
	local FFA = "Free-for-all ground: anyone can join in, and the arbiter voids a fight a third player touches."
	local w6, m, n = Pair({ findable = false })
	Staked(w6, m, n)
	n.Match.SetFindable(true, { d = true, staked = true })
	Matched(w6, m, n, { game = "d", kind = "s", lo = 100000, hi = 100000, level = 0 })
	eq(m.Match.View().match.place.id, "spot_booty_bay")
	eq(MW.HasLine(m, FFA), false)
	m.pos = { cont = 0, wx = -13202.2 + 50, wy = 268.2 }
	w6:Run(2)
	assert(MW.HasLine(m, FFA), table.concat(MW.Lines(m), " | "))
	m.pos = { cont = 0, wx = -13202.2 + 70, wy = 268.2 }
	w6:Run(2)
	eq(MW.HasLine(m, FFA), false)
	-- A casual duel there: nothing to say (no stake, no arbiter).
	local w7, p = Pair()
	Matched(w7, p, w7:Find("Parric Stowe"), CASUAL)
	p.pos = { cont = 0, wx = -13202.2 + 50, wy = 268.2 }
	w7:Run(2)
	eq(MW.HasLine(p, FFA), false)
	MW.NoErrors(w); MW.NoErrors(w2); MW.NoErrors(w3); MW.NoErrors(w4); MW.NoErrors(w5); MW.NoErrors(w6); MW.NoErrors(w7)
end)

test("1.2 matchmaking review: the card sits under the game's popups and Olympus's dialogs, never over them; it moves when one comes or goes; where the player drags it, it stays", function()
	local w, a, b = Pair()
	Matched(w, a, b, CASUAL)
	local card = MW.Card(a)
	local function At(c)
		local p = c.Match.Card().points
		eq(#p, 1, "one anchor")
		return ("%s %s %s %d %d"):format(p[1][1], p[1][2] and p[1][2].name or "nil", p[1][3], p[1][4], p[1][5])
	end
	eq(At(a), "TOP UIParent TOP 0 -135", "where the game's first popup would sit")
	-- [Reply]: the whisper dialog (the game's popup with the mouse) takes the top; the card goes under it.
	a.ns.UI.WhisperWindow = function(name)
		a.whisperWindow[#a.whisperWindow + 1] = name
		a.globals.StaticPopup1.shown = true
	end
	MW.Press(w, a, "reply")
	eq(At(a), "TOP StaticPopup1 BOTTOM 0 -8")
	-- It closes: the card goes back up at its next look (a quarter of a second while it shows).
	a.globals.StaticPopup1.shown = false
	w:As(a, card.scripts.OnUpdate, card, 0.1)
	eq(At(a), "TOP StaticPopup1 BOTTOM 0 -8", "not yet")
	w:As(a, card.scripts.OnUpdate, card, 0.2)
	eq(At(a), "TOP UIParent TOP 0 -135")
	-- Olympus's own dialogs (the gamepad UI) stack under the game's popups, in their order: under
	-- the last of them.
	local d1, d2 = World.NewFrame("Frame", "OlympusDialog1"), World.NewFrame("Frame", "OlympusDialog2")
	d1.order, d2.order = 7, 5
	a.globals.OlympusDialog1, a.globals.OlympusDialog2 = d1, d2
	a.globals.StaticPopup1.shown = true
	w:Run(2)
	eq(At(a), "TOP OlympusDialog1 BOTTOM 0 -8")
	d1.shown = false
	w:Run(2)
	eq(At(a), "TOP OlympusDialog2 BOTTOM 0 -8")
	d2.shown = false
	w:Run(2)
	eq(At(a), "TOP StaticPopup1 BOTTOM 0 -8")
	-- Dragged by the player: it stays where he put it.
	a.globals.StaticPopup1.shown = false
	w:Run(2)
	card.scripts.OnDragStart(card)
	card.scripts.OnDragStop(card)
	a.globals.StaticPopup1.shown = true
	w:Run(2)
	eq(At(a), "TOP UIParent TOP 0 -135", "not moved for him")
	-- A searcher's card, and the Let's go popup a request brings him: the card goes under it.
	local w2 = World.New()
	local i = MW.Client(w2, "Idris Vane", { pos = OTHER })
	local l = MW.Client(w2, "Lida Fenn", { pos = SEEKER })
	i.qid = 4
	assert(i.Match.Start(CASUAL))
	w2:Run(5)
	eq(At(i), "TOP UIParent TOP 0 -135")
	assert(l.Match.Start(CASUAL))
	w2:Run(6)
	assert(MW.Popup(i), "Idris's popup")
	eq(MW.Card(i).title.text, "Finding an opponent")
	eq(At(i), "TOP StaticPopup1 BOTTOM 0 -8")
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking review: the found player's own bet cap bounds the range: a request above it is a no; one across it is cut to it", function()
	local function Capped()
		local w, a, b = Pair({ findable = false })
		Staked(w, a, b)
		b.Match.SetFindable(true, { d = true, staked = true })
		-- the money part's Standing.Cap (a stand-in): 30g for Parric.
		rawset(b.ns, "Standing", { Cap = function(kind, name) return kind == "bet" and name == b.name and 300000 or 0 end })
		return w, a, b
	end
	-- 50g to 100g, all above his 30g: A~N, and no popup.
	local w, a, b = Capped()
	assert(a.Match.Start({ game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 }))
	w:Run(6)
	local mid = MW.Last(w, a, "R"):match("^R~(M[0-9a-z]+)~")
	eq(MW.Last(w, b, "A"), "A~" .. mid .. "~N"); eq(MW.Popup(b), nil)
	-- 20g to 50g: his popup says 20g-30g, and his yes carries 2000 to 3000 silver ("1jk", "2bc").
	local w2, c, d = Capped()
	assert(c.Match.Start({ game = "d", kind = "s", lo = 200000, hi = 500000, level = 0 }))
	w2:Run(6)
	assert(MW.Popup(d).a:find("a duel with a stake of 20g-30g", 1, true), MW.Popup(d).a)
	MW.Answer(w2, d, "yes")
	w2:Run(0)
	assert(MW.Last(w2, d, "A"):find("~1jk~2bc~0$"), MW.Last(w2, d, "A"))
	eq(c.Match.View().match.hi, 300000); eq(d.Match.View().match.hi, 300000)
	MW.NoErrors(w); MW.NoErrors(w2)
end)

test("1.2 matchmaking review: the partner's group token: never looked up inside an instance; a secret name is no match", function()
	local w, a, b = Pair()
	Matched(w, a, b, CASUAL)
	w:Group({ b, a })
	-- From (-13000, 300) to (-13400, 250): 403.1 yd, 400 rounded to 10.
	w:Run(2)
	assert(MW.HasLine(a, "Them: 400 yd"), table.concat(MW.Lines(a), " | "))
	local asked = 0
	local real = a.globals.UnitFullName
	a.globals.UnitFullName = function(unit)
		if unit ~= "player" then asked = asked + 1 end
		return real(unit)
	end
	a.instance = true
	w:Run(4)
	eq(asked, 0, "no unit's name read inside an instance")
	a.instance = nil
	w:Run(2)
	assert(asked > 0)
	assert(MW.HasLine(a, "Them: 400 yd"))
	-- A secret value for his name (as UnitFullName gives under identity restrictions): no token.
	a.globals.issecretvalue = function(v) return v == b.name end
	w:Run(2)
	eq(MW.HasLine(a, "Them: 400 yd"), false)
	a.globals.issecretvalue = nil
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: the Find buttons bring back a live search's card closed with its X, before the screens' Find dialog", function()
	local w = World.New()
	local a = MW.Client(w, "Lida Fenn", { pos = SEEKER })
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	local opened = 0
	a.ns.Arena.ui.OpenFind = function() opened = opened + 1 end
	assert(a.Match.Start(CASUAL))
	MW.Card(a):Hide()
	eq(MW.Card(a), nil)
	eq(a.Arena.Do("match.open", "d"), true)
	eq(opened, 0, "not the Find dialog")
	eq(MW.Card(a).title.text, "Finding an opponent")
	a.Match.Stop()
	eq(a.Arena.Do("match.open", "d"), true)
	eq(opened, 1, "no search: the Find dialog")
	MW.NoErrors(w)
end)

test("1.2 matchmaking review: Vet holds the agreed stake only while the match lives: after Done, and an hour later, a challenge from that player is not the match's to judge", function()
	local w, a, b = Pair({ findable = false })
	Staked(w, a, b)
	b.Match.SetFindable(true, { d = true, staked = true })
	Matched(w, a, b, { game = "d", kind = "s", lo = 500000, hi = 1000000, level = 0 })
	w:As(a, function() assert(a.ns.Arena.LoadUI()) end)
	a.ns.Arena.ui.Challenge = function() end
	MW.Press(w, a, "challenge")
	eq(b.Match.Vet(a.name, "d", 750000), true)
	eq(b.Match.View().match.handed, true)
	eq(b.Match.Vet(a.name, "d", 5000000), false, "500g: outside the agreed range while the match lives")
	MW.Press(w, b, "done")
	w:Run(0)
	eq(b.Match.View().state, "idle"); eq(a.Match.View().state, "idle")
	eq(b.Match.Vet(a.name, "d", 5000000), true, "the match is over")
	eq(a.Match.Vet(b.name, "d", 5000000), true)
	w:Run(3600)
	eq(b.Match.Vet(a.name, "d", 5000000), true, "an hour later")
	MW.NoErrors(w)
end)
