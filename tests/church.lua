-- 1.1.6, the Missionary Church of Olympus: places, acts, the signed Apostles, the book's sync, the
-- room. Every test builds its own world of clients (tests/church-world.lua) over the real files.
-- Run alone: luajit tests/run.lua "1.1.6 Church"
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key

local APOSTLES = { "Aldric Vane-Realm", "Bera Stone-Realm", "Cato Reed-Realm" }

-- The usual cast: the author, the King, the Head (the signed Church department's first councillor),
-- a councillor of another department, three signed Apostles, a plain member, another guild's master.
local function Cast(opts)
	opts = opts or {}
	local w = World.New({ apostles = opts.apostles or APOSTLES, head = opts.head })
	local cast = {
		author = w:Client(World.AUTHOR), king = w:Client(World.KING), head = w:Client(World.HEAD),
		councillor = w:Client(World.COUNCILLOR),
		a1 = w:Client(APOSTLES[1]), a2 = w:Client(APOSTLES[2]), a3 = w:Client(APOSTLES[3]),
		member = w:Client("Plain Member"), gm = w:Client("Vale Master", { guild = World.GUILD2, rank = 0 }),
	}
	return w, cast
end

local function Role(w, cl, name) return w:As(cl, cl.Church.Role, name) end
local function Place(w, cl, name) return w:As(cl, cl.Church.Place, name) end
local function Everyone(w, fn)
	for _, cl in ipairs(w.clients) do if cl.Church then fn(cl) end end
end

test("Church publication authority: King and council publish, Church duties alone do not", function()
	local w, c = Cast()
	for _, publisher in ipairs({ c.king, c.councillor, c.author }) do
		eq(w:Act(publisher, publisher.Church.SetPublic, true), true)
		eq(w:As(c.member, c.member.Church.Public), true, "authenticated switch reaches ordinary member")
		eq(w:Act(publisher, publisher.Church.SetPublic, false), true)
		eq(w:As(c.member, c.member.Church.Public), false)
	end
	w.council[Key(World.HEAD)] = nil
	for _, denied in ipairs({ c.head, c.a1, c.member, c.gm }) do
		eq(w:Act(denied, denied.Church.SetPublic, true), false, "title alone grants no publication")
	end
	w.off[c.councillor.key] = true
	eq(w:Act(c.councillor, c.councillor.Church.SetPublic, true), false, "moderation still applies")
	w.off[c.councillor.key] = nil; c.councillor.guild = nil
	eq(w:Act(c.councillor, c.councillor.Church.SetPublic, true), false, "must still be a member")
	eq(w:As(c.councillor, c.councillor.Church.SendSwitch), false)
	eq(w:As(c.councillor, c.councillor.Church.SendPresence, true), false)
end)

test("Church publication authority: all ingress, resend and equal-stamp closes fail private", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local function Switch(who, on, at, lane)
		return w:As(c.member, c.member.Church.Receive, lane or "CHANNEL", who, "NB~1~s~" .. (on and "1" or "0") .. "~" .. B(at))
	end
	local at = w.clock
	eq(Switch(c.king.name, true, at, "WHISPER"), false, "lane guard")
	eq(Switch(c.king.name, true, at + c.king.Church.DATE_AHEAD + 1), false, "future guard")
	eq(Switch(c.member.name, true, at), false, "forged publisher")
	eq(Switch(c.king.name, true, at), true)
	eq(Switch(c.councillor.name, false, at), true, "same-stamp close wins")
	eq(Switch(c.king.name, true, at), false, "equal opening cannot undo close")
	-- The opposite delivery order converges on the same closed stamp too.
	eq(w:As(c.gm, c.gm.Church.Receive, "CHANNEL", c.councillor.name, "NB~1~s~0~" .. B(at)), true)
	eq(w:As(c.gm, c.gm.Church.Receive, "CHANNEL", c.king.name, "NB~1~s~1~" .. B(at)), false)
	eq(w:As(c.gm, c.gm.Church.Public), false)
	w:As(c.member, c.member.Church.TakePresence, "CHANNEL", c.member.name, "NK~1~p~N~-~-~1" .. B(at + 1))
	eq(w:As(c.member, c.member.Church.Public), false, "claimed council role grants nothing")
	w:As(c.member, c.member.Church.TakePresence, "CHANNEL", c.councillor.name, "NK~1~p~N~-~-~1" .. B(at + 1))
	eq(w:As(c.member, c.member.Church.Public), true, "actual councillor's presence carries switch")
	w.off[c.king.key] = true
	eq(Switch(c.king.name, false, at + 2), false, "moderated sender cannot issue switch")
	w:As(c.member, c.member.Church.TakePresence, "CHANNEL", c.king.name, "NK~1~p~K~-~-~0" .. B(at + 2))
	eq(w:As(c.member, c.member.Church.Public), true, "moderated presence cannot alter it")
	w.off[c.king.key] = nil
	w:As(c.member, c.member.Church.TakePresence, "CHANNEL", c.king.name, "NK~1~p~K~-~-~0" .. B(at + 2))
	eq(w:As(c.member, c.member.Church.Public), false)
	w:Act(c.councillor, c.councillor.Church.SetPublic, true)
	local _, held = w:As(c.councillor, c.councillor.Church.Public)
	w:ClearSent(); w:Run(c.councillor.Church.SWITCH_EVERY + 1); w:Tick({ c.councillor })
	local repeatWords = w:Sent(c.councillor, "NB", "CHANNEL", "s")
	assert(#repeatWords > 0, "authorized publisher repeats for late clients")
	eq(repeatWords[#repeatWords].msg, "NB~1~s~1~" .. B(held), "resend retains stamp")
	w.council[c.councillor.key] = nil
	w:ClearSent(); eq(w:As(c.councillor, c.councillor.Church.SendSwitch), false)
	w:Run(c.councillor.Church.SWITCH_EVERY + 1); w:Tick({ c.councillor })
	eq(#w:Sent(c.councillor, "NB", nil, "s"), 0, "revoked publisher stops resending")
	eq(Switch(c.councillor.name, true, w.clock), false, "receiver also rechecks revocation")
end)

test("Church publication authority: actual signed council accepted, tampering and revoked list rejected", function()
	local K = World.COUNCIL
	local saved = { council = ns.rdb.council, titles = ns.rdb.councilTitles, fire = ns.Fire }
	local ok, err = pcall(function()
		ns.rdb.council, ns.rdb.councilTitles = nil, nil; ns.Fire = function() end
		local w = World.New({})
		local cl = w:Client(World.COUNCILLOR, { real = true })
		eq(w:As(cl, cl.Church.SetPublic, true), false, "no unsigned council claim")
		ns.Sign.WithKey(K.N, K.MU, K.K, function()
			eq(ns.Workshop.TakeCouncil(K.names:gsub("Brin Tallow", "Plain Member", 1)), false)
			assert(ns.Workshop.TakeCouncil(K.names))
		end)
		eq(w:Act(cl, cl.Church.SetPublic, true), true, "actual verified signed list grants permission")
		ns.rdb.council = nil
		eq(w:As(cl, cl.Church.SetPublic, false), false, "no authority after signed list removed")
		eq(w:As(cl, cl.Church.SendSwitch), false)
	end)
	ns.rdb.council, ns.rdb.councilTitles, ns.Fire = saved.council, saved.titles, saved.fire
	if not ok then error(err, 0) end
end)

test("1.1.6 Church: Asmongold heads the Church; a historical starred Apostle retains only his Apostle and council duties", function()
	local w, c = Cast()
	eq(Role(w, c.member, World.AUTHOR), "W"); eq(Role(w, c.member, World.KING), "K")
	eq(Role(w, c.member, World.HEAD), "A", "a historical marker grants only the signed Apostle place")
	eq(w:As(c.member, c.member.Church.HeadName), World.KING)
	-- (The owner's word: the Head of the Church is one of the Twelve Apostles. He keeps an Apostle's
	-- place and network, and counts among the twelve.)
	eq(Place(w, c.member, World.HEAD).role, "A", "his Apostle's place")
	eq(w:As(c.member, c.member.Church.State).apostles, #APOSTLES + 1, "one of the twelve")
	eq(Role(w, c.member, "Dela Moss-Realm"), "N", "a councillor is not the Head")
	eq(Role(w, c.member, World.COUNCILLOR), "N")
	eq(Role(w, c.member, APOSTLES[1]), "A", "another signed Apostle")
	eq(Role(w, c.member, "Plain Member"), nil)
	-- Only a newer signed list ends his place: no root's act in game removes him.
	eq(w:As(c.king, c.king.Church.MayAct, "-", "A", World.HEAD, nil, nil, World.KING), true, "the marker grants no protection against normal Apostle removal")
	eq(w:As(c.author, c.author.Church.MayAct, "-", "A", World.HEAD, nil, nil, World.AUTHOR), true)
	eq(w:As(c.king, c.king.Church.MayAct, "-", "A", APOSTLES[1], nil, nil, World.KING), true, "another Apostle, yes")
	-- Apostles signed, none marked: no Head (nobody is Head for being signed first); the King and the
	-- author still act.
	local w2, c2 = Cast({ head = false })
	eq(w2:As(c2.member, c2.member.Church.HeadName), World.KING, "no marker cannot remove Asmongold")
	eq(Role(w2, c2.member, APOSTLES[1]), "A", "the first signed is an Apostle, no more")
	local w3, c3 = World.New({ head = false }), {}
	c3.member, c3.king, c3.author, c3.head = w3:Client("Plain Member"), w3:Client(World.KING), w3:Client(World.AUTHOR), w3:Client(World.HEAD)
	eq(w3:As(c3.member, c3.member.Church.HeadName), World.KING)
	eq(Role(w3, c3.member, World.HEAD), "N")
	eq(w3:As(c3.king, c3.king.Church.MayAct, "+", "A", "New Apostle-Realm", nil, nil, World.KING), true)
	eq(w3:As(c3.author, c3.author.Church.MayAct, "+", "A", "New Apostle-Realm", nil, nil, World.AUTHOR), true)
	eq(w3:As(c3.head, c3.head.Church.MayAct, "+", "A", "New Apostle-Realm", nil, nil, World.HEAD), true, "his signed council seat may name an Apostle even without the Head's place")
end)

test("1.1.6 Church: the Twelve Apostles come from the author's signed titles list (a real signature, a forged one refused)", function()
	local K = World.COUNCIL
	local saved = { council = ns.rdb.council, titles = ns.rdb.councilTitles, me = ns.me, fire = ns.Fire }
	local ok, err = pcall(function()
		ns.rdb.council, ns.rdb.councilTitles = nil, nil
		ns.Fire = function() end
		ns.Sign.WithKey(K.N, K.MU, K.K, function()
			assert(ns.Workshop.TakeCouncil(K.names), "the signed names")
			assert(ns.Workshop.TakeTitles(K.titles1), "the signed titles with the apostles entry")
			-- Tampered: a fourth Apostle slipped into the signed text fails its signature.
			local forged = K.titles2:gsub("Aldric Vane%-Realm", "Forger Name-Realm", 1)
			eq(ns.Workshop.TakeTitles(forged), false, "a forged list")
		end)
		local w = World.New({})
		local cl = w:Client("Plain Member", { real = true })
		local list = w:As(cl, cl.Church.SignedApostles)
		eq(#list, 3)
		eq(list[1].n, "Aldric Vane-Realm"); eq(list[3].n, "Cato Reed-Realm")
		eq(w:As(cl, cl.Church.Role, "Bera Stone-Realm"), "A")
		eq(w:As(cl, cl.Church.HeadName), ns.KingCharacter(), "the Apostle list does not nominate Asmongold")
		eq(w:As(cl, cl.Church.Role, "Forger Name-Realm"), nil)
		-- The newer lists: twelve; then one without Bera; then one with no Church department at all (no
		-- matter: the Head is the Apostle a list marks, and these mark none).
		ns.Sign.WithKey(K.N, K.MU, K.K, function() assert(ns.Workshop.TakeTitles(K.titles2)) end)
		eq(#w:As(cl, cl.Church.SignedApostles), 12)
		eq(w:As(cl, cl.Church.State).apostles, 12)
		ns.Sign.WithKey(K.N, K.MU, K.K, function() assert(ns.Workshop.TakeTitles(K.titles3)) end)
		eq(w:As(cl, cl.Church.HeadName), ns.KingCharacter(), "department order cannot replace Asmongold")
		eq(w:As(cl, cl.Church.Role, "Bera Stone-Realm"), nil, "a newer signed list without him: no longer an Apostle")
		ns.Sign.WithKey(K.N, K.MU, K.K, function() assert(ns.Workshop.TakeTitles(K.titles4)) end)
		eq(w:As(cl, cl.Church.HeadName), ns.KingCharacter(), "removing a department does not remove Asmongold")
	end)
	ns.rdb.council, ns.rdb.councilTitles, ns.me, ns.Fire = saved.council, saved.titles, saved.me, saved.fire
	if not ok then error(err, 0) end
end)

test("1.1.6 Church: who may name an Apostle, and the cap of twelve", function()
	local w, c = Cast()
	-- Refused by an Apostle, a guild master and a plain member.
	for _, who in ipairs({ c.a1, c.gm, c.member }) do
		eq(w:As(who, who.Church.MayAct, "+", "A", "New One-Realm", nil, nil, who.name), false, who.name)
	end
	-- Each root names one; every client takes it from the act itself.
	for i, root in ipairs({ c.author, c.king, c.councillor }) do
		eq(w:Act(root, root.Church.NameApostle, "Root Pick" .. ("x"):rep(i) .. "-Realm"), true, root.name)
	end
	-- (Three signed, the Head among them, and the three the roots named.)
	Everyone(w, function(cl) eq(w:As(cl, cl.Church.State).apostles, 7, cl.name) end)
	-- (Receivers take ACTS_PER_MIN of one sender's acts a minute: the author's are spaced.)
	for i = 1, 5 do w:Run(11); w:Act(c.author, c.author.Church.NameApostle, "Extra Apostle" .. ("y"):rep(i) .. "-Realm") end
	eq(w:As(c.member, c.member.Church.State).apostles, 12)
	eq(w:Act(c.author, c.author.Church.NameApostle, "Thirteenth One-Realm"), false, "the thirteenth refused by the actor's own client")
	-- A modified client's thirteenth act is refused by every receiver.
	local text = w:As(c.king, c.king.Church.ActText, "+", "A", "Thirteenth One-Realm", nil, nil, w.clock)
	w:As(c.member, c.member.Church.Receive, "CHANNEL", World.KING, text)
	eq(w:As(c.member, c.member.Church.Role, "Thirteenth One-Realm"), nil)
	eq(w:As(c.member, c.member.Church.Stats).dropped.full, 1)
	-- Removal: a root, or the Apostle himself; nobody else.
	eq(w:As(c.member, c.member.Church.MayAct, "-", "A", APOSTLES[2], nil, nil, c.a1.name), false, "an Apostle removes no other")
	eq(w:Act(c.a2, c.a2.Church.Remove, "A", APOSTLES[2]), true, "an Apostle resigns")
	eq(Role(w, c.member, APOSTLES[2]), nil)
end)

test("1.1.6 Church council appointments: signed council authority is checked at every receiver and the keeper preserves provenance", function()
	local w, c = Cast()
	w.council[Key(World.HEAD)] = nil
	eq(w:As(c.head, c.head.Church.MayAct, "+", "A", "Head Pick", nil, nil, c.head.name), false, "Head alone cannot appoint Apostles")
	eq(w:Act(c.councillor, c.councillor.Church.NameApostle, "Council Pick"), true)
	Everyone(w, function(cl)
		local p = Place(w, cl, "Council Pick")
		eq(p.role, "A"); eq(p.ac, World.COUNCILLOR)
		eq(w:As(cl, cl.Church.State).apostle[Key("Council Pick")].ar, "N")
	end)
	local text = w:As(c.councillor, c.councillor.Church.ActText, "+", "A", "Forged Pick", nil, nil, w.clock)
	eq(w:As(c.member, c.member.Church.TakeAct, c.member.name, text), false, "a forged sender gets no council authority")
	w.council[Key(World.COUNCILLOR)] = nil
	eq(w:As(c.member, c.member.Church.TakeAct, c.councillor.name, text), false, "a revoked councillor's new act is rejected")
	eq(Role(w, c.member, "Forged Pick"), nil)
	local late = w:Client("Late Keeper")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Late Keeper")
	w:As(late, late.Church.AskPages, World.AUTHOR)
	w:Run(30)
	eq(Role(w, late, "Council Pick"), "A", "a previously accepted appointment survives trusted keeper catch-up")
end)

test("1.1.6 Church: missionaries: an Apostle names under himself, a missionary under himself, a root under whom he picks", function()
	local w, c = Cast()
	local m1, m2 = w:Client("Mira Wells"), w:Client("Nils Ford")
	eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells"), true)
	eq(w:Act(m1, m1.Church.NameMissionary, "Nils Ford"), true, "a missionary names one more: the network grows")
	eq(w:Act(c.head, c.head.Church.NameMissionary, "Olga Rhys", APOSTLES[2]), false, "a legacy starred Apostle cannot name in another network")
	eq(w:Act(c.king, c.king.Church.NameMissionary, "Olga Rhys", APOSTLES[2]), true, "Asmongold under an Apostle he picks")
	eq(w:Act(c.king, c.king.Church.NameMissionary, "Pell Grant", "Mira Wells"), true, "the King under a missionary")
	eq(w:Act(c.author, c.author.Church.NameMissionary, "Quin Hart"), false, "a root must say under whom")
	Everyone(w, function(cl)
		local p = Place(w, cl, "Nils Ford")
		eq(p and p.role, "M", cl.name); eq(p.net, Key(APOSTLES[1]), "in Aldric's network"); eq(p.depth, 2); eq(p.parent, Key("Mira Wells"))
		eq(Place(w, cl, "Olga Rhys").net, Key(APOSTLES[2]))
		eq(Place(w, cl, "Pell Grant").parent, Key("Mira Wells"))
	end)
	-- Refused: a councillor, a guild master, a plain member, someone who already holds a place, oneself.
	for _, who in ipairs({ c.councillor, c.gm, c.member }) do
		eq(w:Act(who, who.Church.NameMissionary, "Some One"), false, who.name)
	end
	eq(w:Act(c.a2, c.a2.Church.NameMissionary, "Mira Wells"), false, "already a missionary")
	eq(w:Act(c.a2, c.a2.Church.NameMissionary, APOSTLES[3]), false, "an Apostle")
	eq(w:Act(c.a2, c.a2.Church.NameMissionary, World.KING), false, "a root")
	eq(w:Act(m2, m2.Church.NameMissionary, "Nils Ford"), false, "oneself")
	-- A forged act: a plain member claiming to name, or naming under someone else's network.
	local forged = w:As(c.member, c.member.Church.ActText, "+", "M", "Forged Pick-Realm", nil, nil, w.clock)
	w:As(c.a3, c.a3.Church.Receive, "CHANNEL", c.member.name, forged)
	eq(Role(w, c.a3, "Forged Pick-Realm"), nil)
	local under = w:As(m1, m1.Church.ActText, "+", "M", "Forged Pick-Realm", APOSTLES[3], nil, w.clock)
	w:As(c.a3, c.a3.Church.Receive, "CHANNEL", m1.name, under)
	eq(Role(w, c.a3, "Forged Pick-Realm"), nil, "a missionary names under himself only")
end)

test("1.1.6 Church: the chain's limits: ten per parent, five levels, three hundred in all", function()
	local w, c = Cast()
	for i = 1, 10 do w:Run(11); eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Number" .. ("a"):rep(i)), true, i) end
	eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Eleven"), false, "the eleventh")
	eq(w:Printed(c.a1), ns.L.CHURCH_NO_QUOTA)
	-- Five levels below the Apostle, not six.
	local parent = c.a2
	local names = { "Lev One", "Lev Two", "Lev Three", "Lev Four", "Lev Five" }
	local levels = {}
	for _, n in ipairs(names) do levels[n] = w:Client(n) end
	for _, n in ipairs(names) do
		eq(w:Act(parent, parent.Church.NameMissionary, n), true, n)
		parent = levels[n]
	end
	local five = w.byKey[Key("Lev Five")]
	eq(Place(w, five, "Lev Five").depth, 5)
	eq(w:Act(five, five.Church.NameMissionary, "Lev Six"), false, "the sixth level")
	eq(w:Printed(five), ns.L.CHURCH_NO_DEEP)
	-- The total: a relayed book past 300 leaves the later ones invalid, holding nothing.
	local S0 = w:As(c.member, c.member.Church.State)
	eq(S0.valid, 15)
	local saved = c.member.Church.MISSIONARIES_MAX
	c.member.Church.MISSIONARIES_MAX = 14
	c.member.Church.Changed()
	local S = w:As(c.member, c.member.Church.State)
	eq(S.valid, 14); eq(#S.invalid, 1); eq(S.invalid[1].why, "full")
	c.member.Church.MISSIONARIES_MAX = saved
end)

test("1.1.6 Church: a namer who loses his place: his nominees stay, marked, one level up; the Head keeps or moves them", function()
	local w, c = Cast()
	local m1, nils = w:Client("Mira Wells"), w:Client("Nils Ford")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(m1, m1.Church.NameMissionary, "Nils Ford")
	w:Act(m1, m1.Church.NameMissionary, "Odo Lark")
	-- A sibling and a descendant may not remove; the namer, an ancestor, a root and oneself may.
	eq(w:As(nils, nils.Church.MayAct, "-", "M", "Odo Lark", nil, nil, nils.name), false, "a sibling")
	eq(w:As(nils, nils.Church.MayAct, "-", "M", "Mira Wells", nil, nil, nils.name), false, "a nominee removes not his namer")
	eq(w:As(nils, nils.Church.MayAct, "-", "M", "Nils Ford", nil, nil, nils.name), true, "oneself")
	eq(w:As(c.a1, c.a1.Church.MayAct, "-", "M", "Odo Lark", nil, nil, c.a1.name), true, "the Apostle above")
	eq(w:As(c.a2, c.a2.Church.MayAct, "-", "M", "Odo Lark", nil, nil, c.a2.name), false, "another network's Apostle")
	eq(w:As(c.head, c.head.Church.MayAct, "-", "M", "Odo Lark", nil, nil, c.head.name), false, "starred Apostle has no cross-network root power")
	eq(w:As(c.king, c.king.Church.MayAct, "-", "M", "Odo Lark", nil, nil, c.king.name), true)
	-- The namer goes: his two stay, under the Apostle now, marked for review, on every client.
	eq(w:Act(c.a1, c.a1.Church.Remove, "M", "Mira Wells"), true)
	Everyone(w, function(cl)
		local p = Place(w, cl, "Nils Ford")
		eq(p.valid, true, cl.name); eq(p.adopted, true); eq(p.parent, Key(APOSTLES[1])); eq(p.depth, 1)
		eq(Role(w, cl, "Mira Wells"), nil)
	end)
	-- The Apostle goes too: his network stays, an orphan under the Head.
	w:Act(c.author, c.author.Church.Remove, "A", APOSTLES[1])
	local p = Place(w, c.member, "Nils Ford")
	eq(p.valid, true); eq(p.parent, nil); eq(p.net, nil); eq(p.adopted, true)
	-- The Head keeps one (the mark goes) and moves the other under another Apostle.
	eq(w:Act(c.king, c.king.Church.Keep, "Nils Ford"), true)
	eq(Place(w, c.member, "Nils Ford").adopted, nil)
	eq(w:Act(c.king, c.king.Church.Move, "Odo Lark", APOSTLES[2]), true)
	eq(Place(w, c.member, "Odo Lark").net, Key(APOSTLES[2]))
	eq(w:Act(c.a2, c.a2.Church.Keep, "Nils Ford"), false, "only a root keeps or moves")
end)

test("1.1.6 Church: the tree is the same whatever order the acts come in; a cycle in a relayed page grants nothing", function()
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	-- Two clients get the same acts in two orders (a nominee's act first: it waits, then counts).
	local a = w:As(c.a1, c.a1.Church.ActText, "+", "M", "Mira Wells-Realm", nil, nil, w.clock)
	local b = w:As(m1, m1.Church.ActText, "+", "M", "Nils Ford-Realm", nil, nil, w.clock + 1)
	local x, y = w:Client("Order One"), w:Client("Order Two")
	w:As(x, x.Church.Receive, "CHANNEL", c.a1.name, a)
	w:As(x, x.Church.Receive, "CHANNEL", m1.name, b)
	w:As(y, y.Church.Receive, "CHANNEL", m1.name, b)
	eq(#w:As(y, y.Church.Pending), 1, "the nominee's act waits for its namer's place")
	w:As(y, y.Church.Receive, "CHANNEL", c.a1.name, a)
	eq(w:As(x, x.Church.BookDigest), w:As(y, y.Church.BookDigest))
	eq(Place(w, y, "Nils Ford").depth, 2)
	-- A page with a cycle (two missionaries naming each other) makes neither valid.
	local book = w:As(y, y.Church.Book)
	book.p[Key("Cyc One")] = { role = "M", n = "Cyc One-Realm", by = Key("Cyc Two"), bn = "Cyc Two-Realm", at = w.clock, ar = "M" }
	book.p[Key("Cyc Two")] = { role = "M", n = "Cyc Two-Realm", by = Key("Cyc One"), bn = "Cyc One-Realm", at = w.clock, ar = "M" }
	y.Church.Changed()
	eq(Role(w, y, "Cyc One-Realm"), nil); eq(Role(w, y, "Cyc Two-Realm"), nil)
	eq(w:As(y, y.Church.InAudience, "Cyc One-Realm"), false, "no room, no tab")
	eq(w:As(y, y.Church.MayAct, "+", "M", "Their Pick-Realm", nil, nil, "Cyc One-Realm"), false, "no naming")
end)

test("1.1.6 Church: correspondents: a guild master for his own guild, a root for any; replaced by a newer naming", function()
	local w, c = Cast()
	local master = w:Client("Ember Master", { rank = 0 })
	local helper = w:Client("Other Helper")
	eq(w:Act(master, master.Church.NameCorrespondent, "Plain Member"), true, "his own guild, by his roster")
	Everyone(w, function(cl) if cl.guild == World.GUILD then eq(Role(w, cl, "Plain Member"), "C", cl.name) end end)
	-- Another guild's master: only for his own guild, never for ours.
	eq(w:Act(c.gm, c.gm.Church.NameCorrespondent, "Vale Helper", World.GUILD), false)
	-- His own guild, on a client of another guild: by the census (two vouches); unknown, it waits.
	local text = w:As(c.gm, c.gm.Church.ActText, "+", "C", "Vale Helper-Realm", nil, World.GUILD2, w.clock)
	w:As(c.member, c.member.Church.Receive, "GUILD", c.gm.name, text)
	eq(w:As(c.member, c.member.Church.State).corr[ns.Fold(World.GUILD2)], nil, "not yet")
	eq(#w:As(c.member, c.member.Church.Pending), 1)
	w.census[ns.Fold(World.GUILD2) .. ":" .. Key(c.gm.name)] = 0
	w:As(c.member, c.member.Church.RetryPending)
	eq(w:As(c.member, c.member.Church.State).corr[ns.Fold(World.GUILD2)].n, "Vale Helper-Realm")
	-- A newer naming replaces; the correspondent himself may step down.
	w:Act(c.king, c.king.Church.NameCorrespondent, "Other Helper", World.GUILD)
	eq(w:As(c.member, c.member.Church.State).corr[ns.Fold(World.GUILD)].n, "Other Helper-Realm")
	eq(Role(w, c.member, "Plain Member"), nil)
	eq(w:As(helper, helper.Church.MayAct, "-", "C", nil, nil, World.GUILD, helper.name), true)
	eq(w:As(c.member, c.member.Church.MayAct, "-", "C", nil, nil, World.GUILD, c.member.name), false)
end)

test("1.1.6 Church: acts dated ahead, replayed or older than a removal are refused; a net-off client sends none", function()
	local w, c = Cast()
	local ahead = w:As(c.author, c.author.Church.ActText, "+", "A", "Future Man-Realm", nil, nil, w.clock + 61)
	w:As(c.member, c.member.Church.Receive, "CHANNEL", World.AUTHOR, ahead)
	eq(Role(w, c.member, "Future Man-Realm"), nil)
	eq(w:As(c.member, c.member.Church.Stats).dropped.ahead, 1)
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(c.a1, c.a1.Church.Remove, "M", "Mira Wells")
	local old = w:As(c.a1, c.a1.Church.ActText, "+", "M", "Mira Wells-Realm", nil, nil, w.clock - 5)
	w:As(c.member, c.member.Church.Receive, "CHANNEL", c.a1.name, old)
	eq(Role(w, c.member, "Mira Wells-Realm"), nil, "older than the tombstone")
	eq(w:As(c.member, c.member.Church.Stats).dropped.stale, 1)
	-- Net-off: the client sends nothing, and an off sender's act is ignored.
	w.off[c.a2.key] = { off = true }
	w:ClearSent()
	eq(w:Act(c.a2, c.a2.Church.NameMissionary, "Nils Ford"), false)
	eq(#w:Sent(c.a2, "NB"), 0)
	local fromOff = w:As(c.a2, c.a2.Church.ActText, "+", "M", "Nils Ford-Realm", nil, nil, w.clock)
	w:As(c.member, c.member.Church.Receive, "CHANNEL", c.a2.name, fromOff)
	eq(Role(w, c.member, "Nils Ford-Realm"), nil)
	eq(w:As(c.member, c.member.Church.Stats).dropped.netoff, 1)
end)

test("1.1.6 Church: a late client gets the book from a keeper's pages; pages from a non-keeper, unasked, or on Apostles from an Apostle are dropped", function()
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(m1, m1.Church.NameMissionary, "Nils Ford")
	w:Act(c.author, c.author.Church.NameApostle, "Ingame Apostle")
	-- A missionary who was offline for all of it (his own place came with an act he missed).
	local late = w:Client("Late Comer")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Late Comer")
	late.online = false
	w:Act(m1, m1.Church.NameMissionary, "Odo Lark")
	late.online = true
	eq(Role(w, late, "Odo Lark-Realm"), nil, "missed")
	-- The Apostle's presence advertises another book: the late audience client asks him.
	w:Presence({ c.a1 })
	w:Run(30)
	eq(#w:Sent(late, "NB", "WHISPER", "q"), 1)
	eq(Role(w, late, "Odo Lark-Realm"), "M")
	eq(Role(w, late, "Ingame Apostle-Realm"), nil, "an in-game Apostle is a root's page, never an Apostle's")
	eq(w:As(late, late.Church.Stats).dropped["apostle page"] >= 1, true)
	-- The author's pages carry it.
	w:As(late, function() late.Church.AskPages(World.AUTHOR) end)
	w:Run(1)
	-- (the ask gap: a second ask waits ASK_GAP; the author's client still answered nothing yet)
	w:Run(late.Church.ASK_GAP)
	w:As(late, function() late.Church.AskPages(World.AUTHOR) end)
	w:Run(30)
	eq(Role(w, late, "Ingame Apostle-Realm"), "A")
	eq(w:As(late, late.Church.BookDigest), w:As(c.author, c.author.Church.BookDigest), "converged")
	-- An entry nobody asked for, and one from a plain member, are dropped.
	local line = "NB~1~p~M~Sneaky One-Realm~Mira Wells-Realm~Mira Wells-Realm~M~-~" .. ns.Codec.Base36(w.clock)
	w:As(c.member, c.member.Church.Receive, "WHISPER", c.a1.name, line)
	eq(Role(w, c.member, "Sneaky One-Realm"), nil)
	eq(w:As(c.member, c.member.Church.Stats).dropped.unasked, 1)
	w:As(late, late.Church.Receive, "WHISPER", c.member.name, line)
	eq(w:As(late, late.Church.Stats).dropped.keeper, 1)
	-- The King's client answers no page.
	eq(select(2, w:As(c.king, c.king.Church.AnswerAsk, late.name, "NB~1~q~-,-,-,-,-,-,-,-,-")), "not keeper")
end)

test("1.1.6 Church: presence: the desk is the Head, then the Apostles by name, then the author, never the King; a claim grants nothing", function()
	local w, c = Cast()
	w:Presence()
	eq(w:As(c.member, c.member.Church.Desk), APOSTLES[1], "Asmongold remains excluded from keeper work; Apostles are ordered by name")
	c.head.online = false
	w:Run(c.head.Church.KEEPER_EVERY * 2.3)
	w:Presence({ c.a1, c.a2, c.a3, c.author, c.king })
	eq(w:As(c.member, c.member.Church.Desk), APOSTLES[1])
	for _, a in ipairs({ c.a1, c.a2, c.a3 }) do a.online = false end
	w:Run(c.head.Church.KEEPER_EVERY * 2.3)
	w:Presence({ c.author, c.king })
	eq(w:As(c.member, c.member.Church.Desk), World.AUTHOR)
	c.author.online = false
	w:Run(c.head.Church.KEEPER_EVERY * 2.3)
	w:Presence({ c.king })
	eq(w:As(c.member, c.member.Church.Desk), nil, "the King's client is never the desk")
	-- A plain member's presence claiming "A" is heard, and grants nothing.
	w:As(c.a1, c.a1.Church.Receive, "CHANNEL", c.member.name, "NB~1~x")
	w:As(c.a1, c.a1.Church.ReceivePresence, "CHANNEL", c.member.name, "NK~1~p~A~abcd1234~Olympus Ember")
	eq(w:As(c.a1, c.a1.Church.Online, c.member.name), false)
	eq(w:As(c.a1, c.a1.Church.InAudience, c.member.name), false)
end)

test("1.1.6 Church: the room: the Church's audience only, one logged whisper to each member online, at most thirty", function()
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	local R = c.a1.c.ChatRooms
	-- The registered audience: refused for an id another room has.
	eq(w:As(c.a1, R.RegisterAudience, "council", { CanAccess = function() return true end, Recipients = function() return {} end }), false)
	eq(w:As(c.a1, R.RegisterAudience, "church", { CanAccess = function() return true end, Recipients = function() return {} end }), false, "taken")
	-- The tab: the audience sees it, a plain member doesn't.
	local function HasTab(cl)
		for _, t in ipairs(w:As(cl, cl.c.ChatRooms.Options, "role")) do if t.id == "church" then return true end end
		return false
	end
	eq(HasTab(c.a1), true); eq(HasTab(m1), true); eq(HasTab(c.king), true); eq(HasTab(c.councillor), true)
	eq(HasTab(c.member), false); eq(HasTab(c.gm), false)
	-- A line: one logged whisper to each audience member heard online, nobody else.
	w:ClearSent()
	eq(w:As(c.a1, R.Send, "church", "hello brothers"), true)
	local got = {}
	for _, e in ipairs(w:Sent(c.a1, "M2")) do
		eq(e.dist, "WHISPER"); eq(e.logged, true)
		got[Key(e.target)] = true
	end
	eq(got[Key("Plain Member")], nil); eq(got[Key("Vale Master")], nil)
	eq(got[Key("Mira Wells")], true); eq(got[Key(World.HEAD)], true); eq(got[Key(World.KING)], true); eq(got[Key(World.COUNCILLOR)], true)
	w:Flush()
	eq(#w:As(m1, m1.c.ChatRooms.History, "church"), 1)
	-- A line from outside the audience is dropped; so is a broadcast one.
	local line = "M2~1~church~77~~Olympus Ember~sneaky"
	eq(select(2, w:As(m1, m1.c.ChatRooms.Receive, "WHISPER", c.member.name, line)), "audience")
	eq(select(2, w:As(m1, m1.c.ChatRooms.Receive, "CHANNEL", c.a1.name, line)), "lane")
	-- At most thirty recipients.
	for i = 1, 35 do
		local n = "Fan " .. string.char(65 + math.floor(i / 26)) .. string.char(97 + i % 26) .. "x"
		local under = i <= 9 and APOSTLES[1] or (i <= 19 and APOSTLES[2] or (i <= 29 and APOSTLES[3] or "Mira Wells"))
		w:Run(11)
		eq(w:Act(c.king, c.king.Church.NameMissionary, n, under), true, n)
		w:As(c.a1, c.a1.Church.TakePresence, "CHANNEL", n .. "-Realm", "NK~1~p~M~-~Olympus Ember")
	end
	eq(#w:As(c.a1, c.a1.Church.RoomRecipients), 30)
	-- Losing the place: the room's history goes, the tab with it.
	w:Act(c.author, c.author.Church.Remove, "M", "Mira Wells")
	eq(HasTab(m1), false)
	eq(#w:As(m1, m1.c.ChatRooms.History, "church"), 0)
end)

test("1.1.6 Church: old clients (1.1.4's Comm) drop every Church message unread; a client without the Church drops its room line as shape", function()
	-- What a live client runs today: 1.1.4's Comm (tests/fixtures/comm-1.1.4.lua, unchanged), its handlers
	-- for the types it knows. Every Church type, on every lane, reaches none of them and is no report.
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	w:Run(60)
	local saved = rawget(_G, "C_ChatInfo")
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local events, login = {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then login[#login + 1] = fn end end
		cns.After, cns.Every = function() end, function() end
		cns.Now = function() return 100000 end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		GetChannelName = function() return 5 end
		assert(loadfile(ROOT .. "tests/fixtures/comm-1.1.4.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		local heard = {}
		for _, kind in ipairs({ "M1", "T1", "S1", "L1", "W1", "O1", "HS", "HT" }) do
			cns.Comm.Handle(kind, function() heard[#heard + 1] = kind end)
		end
		local n = 0
		for _, e in ipairs(w.sent) do
			local t = e.msg:sub(1, 2)
			if t == "NB" or t == "NK" or t == "NV" or t == "NS" or t == "NL" or t == "NR" then
				for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, e.msg, e.dist, e.from.name) end
				n = n + 1
			end
		end
		assert(n >= 3, "the world sent Church messages: " .. n)
		eq(#heard, 0, "no handler of 1.1.4 runs")
		local stats = cns.Comm.Stats()
		eq(stats.bad, 0, "none misread as a census report")
	end)
	C_ChatInfo, GetChannelName = saved, savedChannel
	if not ok then error(err, 0) end
	-- A world client that predates 1.1.6 takes nothing and breaks nothing.
	local old = w:Client("Old Timer", { old = true })
	w:Presence()
	eq(next(old.handlers), nil)
	-- ChatRooms without the Church's audience: an M2 church line drops as shape.
	local plain = setmetatable({ db = { chatRooms = true }, me = "Plain-Realm" }, { __index = ns })
	plain.Comm = { Handle = function() end }
	plain.On = function() end
	plain.Consent = { Register = function() end }
	assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", plain)
	eq(select(2, plain.ChatRooms.Receive("WHISPER", "Aldric Vane-Realm", "M2~1~church~1~~Olympus Ember~hi")), "shape")
	eq(#w:As(m1, m1.c.ChatRooms.Tabs) > 0, true)
end)

test("1.1.6 Church: every message is whole, versioned and at most 255 bytes, its fields fixed; other versions and kinds are dropped", function()
	local w, c = Cast()
	local long = ("Abcdefghijklmnopqrstuvwxyzabcd"):sub(1, 30)
	local worst = long:sub(1, 15) .. " " .. long:sub(1, 14) .. "-" .. ("R"):rep(40)
	local text = w:As(c.author, c.author.Church.ActText, "+", "C", worst, nil, ("G"):rep(48), w.clock)
	eq(#text <= 255, true, #text)
	local text2 = w:As(c.author, c.author.Church.ActText, "m", "M", worst, worst, nil, w.clock)
	eq(#text2 <= 255, true, #text2)
	eq(w:As(c.member, c.member.Church.Receive, "CHANNEL", World.AUTHOR, "NB~2~a~+~A~X Y-Realm~-~-~" .. ns.Codec.Base36(w.clock)), false)
	eq(w:As(c.member, c.member.Church.Stats).dropped.version, 1)
	eq(w:As(c.member, c.member.Church.Receive, "CHANNEL", World.AUTHOR, "NB~1~z~1"), false)
	eq(w:As(c.member, c.member.Church.Stats).dropped.kind, 1)
	eq(w:As(c.member, c.member.Church.Receive, "CHANNEL", World.AUTHOR, "NB~1~a~+~A~X Y-Realm~-~" .. ns.Codec.Base36(w.clock)), false, "a field missing")
	eq(w:As(c.member, c.member.Church.Receive, "WHISPER", World.AUTHOR, w:As(c.author, c.author.Church.ActText, "+", "A", "X Y-Realm", nil, nil, w.clock)), false)
	eq(w:As(c.member, c.member.Church.Stats).dropped.lane, 1)
end)

test("1.1.6 Church: the TOC loads the Church after ChatRooms and ViewAs, its text with the locales; Comm's list has its types; the stand-in", function()
	local function Read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
	local toc = Read(ROOT .. "Olympus/Olympus.toc")
	local at, n = {}, 0
	for line in toc:gmatch("[^\r\n]+") do n = n + 1; at[line] = n end
	for _, f in ipairs({ "Church.lua", "ChurchCount.lua", "ChurchView.lua", "Locales\\ChurchText.lua" }) do assert(at[f], f) end
	assert(at["ChatRooms.lua"] < at["Church.lua"] and at["ViewAs.lua"] < at["Church.lua"])
	assert(at["Church.lua"] < at["ChurchCount.lua"] and at["ChurchCount.lua"] < at["ChurchView.lua"])
	assert(at["UI.lua"] < at["ChurchView.lua"] and at["Views.lua"] < at["ChurchView.lua"] and at["PlayerMenu.lua"] < at["ChurchView.lua"])
	assert(at["ChurchView.lua"] < at["ArenaMath.lua"], "before every Arena file")
	assert(at["Locales\\ChurchText.lua"] < at["Core.lua"])
	local comm = Read(ROOT .. "Olympus/Comm.lua")
	assert(comm:find("Church NB NK | ChurchCount NV NS NL NR", 1, true))
	local core = Read(ROOT .. "Olympus/Core.lua")
	assert(core:find('StandIn("Church", { "Slash" })', 1, true))
	assert(core:find('cmd == "church" or cmd == "igreja"', 1, true))
	-- The only event the Church registers, in a game the gamepad UI shares: GUILD_EVENT_LOG_UPDATE (no
	-- HasRestrictions in Forever's GuildInfo documentation).
	for _, file in ipairs({ "Church.lua", "ChurchCount.lua", "ChurchView.lua" }) do
		local src = Read(ROOT .. "Olympus/" .. file)
		for code in src:gmatch("[^\n]+") do
			code = code:gsub("%-%-.*$", "")
			for ev in code:gmatch('RegisterEvent%("([%u_]+)"') do eq(ev, "GUILD_EVENT_LOG_UPDATE", file) end
			for _, frame in ipairs({ "CommunitiesGuildLogFrame", "ToggleGuildFrame", "ShowUIPanel", "StaticPopup_Show", "hooksecurefunc", "HookScript" }) do
				eq(code:find(frame, 1, true), nil, file .. ": " .. frame)
			end
		end
	end
end)

-- Review (lane-church): what the first build lost or let through, each test failing on that build.

test("1.1.6 Church: a naming made while no keeper is online reaches the keepers later: the actor's own client hands it to each one it hears", function()
	local w, c = Cast()
	local m1, nils = w:Client("Mira Wells"), w:Client("Nils Ford")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	local keepers = { c.author, c.head, c.a1, c.a2, c.a3 }
	for _, k in ipairs(keepers) do k.online = false end
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	eq(#w:As(m1, m1.Church.KeepersOnline, false), 0, "no keeper online")
	-- A missionary's naming (the network growing) and the King's in-game Apostle, heard by nobody who keeps the book.
	eq(w:Act(m1, m1.Church.NameMissionary, "Nils Ford"), true)
	eq(Role(w, nils, "Nils Ford"), "M", "his own client heard it")
	eq(w:Act(c.king, c.king.Church.NameApostle, "Kings Pick"), true)
	-- The keepers come back: once each one's presence is heard, the actors' ticks hand them the acts.
	for _, k in ipairs(keepers) do k.online = true end
	w:Presence()
	w:ClearSent()
	w:Tick(); w:Run(30); w:Tick(); w:Run(30)
	for _, k in ipairs(keepers) do
		eq(Role(w, k, "Nils Ford"), "M", k.name)
		eq(Role(w, k, "Kings Pick-Realm"), "A", k.name)
	end
	eq(#w:Sent(m1, "NB", "WHISPER", "a"), #keepers, "the act itself, a logged whisper to each keeper")
	for _, e in ipairs(w:Sent(m1, "NB", "WHISPER", "a")) do eq(e.logged, true) end
	-- Once each: the next ticks hand nothing again.
	w:ClearSent()
	w:Tick(); w:Run(30)
	eq(#w:Sent(m1, "NB", "WHISPER", "a"), 0); eq(#w:Sent(c.king, "NB", "WHISPER", "a"), 0)
	-- A client named later gets both from a keeper's pages (an Apostle's place from a root's).
	local late = w:Client("Late Comer")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Late Comer")
	w:Presence({ c.author })
	w:Run(30)
	eq(Role(w, late, "Nils Ford"), "M"); eq(Role(w, late, "Kings Pick-Realm"), "A")
	-- Only a keeper takes an act by whisper, and none older than OWN_ACT_KEEP.
	local text = w:As(m1, m1.Church.ActText, "+", "M", "Odd Pick-Realm", nil, nil, w.clock)
	eq(select(2, w:As(c.member, c.member.Church.Receive, "WHISPER", m1.name, text)), "lane")
	local old = w:As(m1, m1.Church.ActText, "+", "M", "Odd Pick-Realm", nil, nil, w.clock - c.a1.Church.OWN_ACT_KEEP - 60)
	eq(select(2, w:As(c.a1, c.a1.Church.Receive, "WHISPER", m1.name, old)), "old")
	-- The kept acts are saved, bounded, the newest per place: a removal replaces the naming it undoes.
	w:Run(11)
	w:Act(m1, m1.Church.Remove, "M", "Nils Ford")
	local acts = w:As(m1, m1.Church.OwnActs)
	eq(#acts, 1); assert(acts[1].text:find("~a~-~M~Nils Ford", 1, true), acts[1].text)
end)

test("1.1.6 Church: an Apostle's pages can't put another Apostle out of his place (a missionary's entry or removal under an Apostle's name)", function()
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	w:Act(c.a2, c.a2.Church.NameMissionary, "Mira Wells")
	w:Presence()
	local B = ns.Codec.Base36
	-- Mira asks Aldric for pages (his presence showed another book); a modified client of his
	-- whispers entries for Bera's name, newer than the signed list.
	eq(w:As(m1, m1.Church.AskPages, APOSTLES[1]), true)
	w:Flush()
	local tomb = ("NB~1~p~X~%s~M~%s~A~-~%s"):format(APOSTLES[2], APOSTLES[1], B(w.clock))
	eq(select(2, w:As(m1, m1.Church.Receive, "WHISPER", APOSTLES[1], tomb)), "apostle page")
	local place = ("NB~1~p~M~%s~%s~%s~A~-~%s"):format(APOSTLES[2], APOSTLES[1], APOSTLES[1], B(w.clock))
	eq(select(2, w:As(m1, m1.Church.Receive, "WHISPER", APOSTLES[1], place)), "apostle page")
	eq(Role(w, m1, APOSTLES[2]), "A"); eq(w:As(m1, m1.Church.State).apostles, #APOSTLES + 1, "the Head's place too")
	eq(Place(w, m1, "Mira Wells").net, Key(APOSTLES[2]), "her network stands")
	-- A missionary's entry from him is still taken.
	local fine = ("NB~1~p~M~Pell Grant-Realm~%s~%s~A~-~%s"):format(APOSTLES[1], APOSTLES[1], B(w.clock))
	eq(w:As(m1, m1.Church.Receive, "WHISPER", APOSTLES[1], fine), true)
	eq(Place(w, m1, "Pell Grant").net, Key(APOSTLES[1]))
	-- The author's pages carry an Apostle's removal: his word.
	w:Run(m1.Church.ASK_GAP)
	eq(w:As(m1, m1.Church.AskPages, World.AUTHOR), true)
	w:Flush()
	local removal = ("NB~1~p~X~%s~A~%s~W~-~%s"):format(APOSTLES[2], World.AUTHOR, B(w.clock))
	eq(w:As(m1, m1.Church.Receive, "WHISPER", World.AUTHOR, removal), true)
	eq(Role(w, m1, APOSTLES[2]), nil)
end)

test("1.1.6 Church: the Head's keep: never past the new parent's quota, none in the Head's own slot, and the kept one's invites from his first day still count", function()
	local w, c = Cast()
	local kid = w:Client("Kid Alpha")
	for i = 1, 9 do w:Run(11); eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Number" .. ("a"):rep(i)), true, i) end
	w:Run(11); eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Alpha"), true, "his tenth")
	eq(w:Act(kid, kid.Church.NameMissionary, "Grand Kid"), true)
	local namedAt = w.clock
	w:Run(11); eq(w:Act(kid, kid.Church.NameMissionary, "Grand Kidb"), true)
	w:Run(11); eq(w:Act(c.a1, c.a1.Church.Remove, "M", "Kid Alpha"), true)
	for _, n in ipairs({ "Grand Kid", "Grand Kidb" }) do
		local p = Place(w, c.member, n)
		eq(p.valid, true, n); eq(p.adopted, true, n); eq(p.parent, Key(APOSTLES[1]), n)
	end
	-- Hours later the Head keeps one: Aldric's tenth own again. A second keep would be his eleventh.
	w:Run(3 * 3600)
	eq(w:Act(c.king, c.king.Church.Keep, "Grand Kid"), true)
	w:Run(11)
	eq(w:Act(c.king, c.king.Church.Keep, "Grand Kidb"), false, "past Aldric's quota")
	eq(w:Printed(c.king), ns.L.CHURCH_NO_QUOTA)
	Everyone(w, function(cl)
		local p = Place(w, cl, "Grand Kidb")
		eq(p.valid, true, cl.name); eq(p.adopted, true, "still marked for the review")
		eq(Place(w, cl, "Grand Kid").valid, true, cl.name)
	end)
	-- The Head moves him instead.
	eq(w:Act(c.king, c.king.Church.Move, "Grand Kidb", APOSTLES[2]), true)
	eq(Place(w, c.member, "Grand Kidb").net, Key(APOSTLES[2]))
	-- The kept one's place counts from when he was first named: his invite before the keep is his.
	local p = Place(w, c.a1, "Grand Kid")
	eq(p.since, namedAt); eq(p.at > namedAt + 3 * 3600, true, "the keep re-dated the entry, not his place")
	local B = ns.Codec.Base36
	local hour = math.floor(namedAt / 3600) + 1
	local ev = ("NV~1~w~Grand Kid-Realm~Fresh Face-Realm~%s~%s~%s"):format(World.GUILD, B(hour), B(hour + 1))
	eq(select(2, w:As(c.a1, c.a1.Count.TakeEvidence, "Plain Member-Realm", ev)), nil, "not refused as invited before his place")
	-- The since travels in the book's pages: another client reads it back.
	local line = w:As(c.a1, c.a1.Church.PageLines, w:As(c.a1, c.a1.Church.PageOf, Key("Grand Kid")))
	local found
	for _, l in ipairs(line) do if l:find("M~Grand Kid-Realm~", 1, true) then found = l end end
	local _, _, e = w:As(c.member, c.member.Church.ParseEntry, "NB~1~p~" .. found)
	eq(e.since, namedAt); eq(e.k, true)
	-- The Head's own slot (orphans, and the ones he keeps there) has no quota: eleven all hold.
	local book = w:As(c.member, c.member.Church.Book)
	for i = 1, 11 do
		local n = "Orphan Kid" .. ("o"):rep(i) .. "-Realm"
		book.p[Key(n)] = { role = "M", n = n, at = w.clock - 100, since = w.clock - 5000, k = true, ac = World.HEAD, ar = "H" }
	end
	c.member.Church.Changed()
	for i = 1, 11 do eq(Role(w, c.member, "Orphan Kid" .. ("o"):rep(i) .. "-Realm"), "M", i) end
end)

test("1.1.6 Church: the room past thirty: the sender's own network and the Church before the High Council, and the sender is told how many it missed", function()
	local w, c = Cast()
	local m1 = w:Client("Mira Wells")
	w:Client("Nils Ford"); w:Client("Olga Rhys")
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(m1, m1.Church.NameMissionary, "Nils Ford")
	w:Act(c.a2, c.a2.Church.NameMissionary, "Olga Rhys")
	w:Presence()
	-- Twenty-six more High Councillors online: with the roots, the Apostles and Brin, 32 before any missionary.
	for i = 1, 26 do
		local n = "Sage " .. string.char(65 + math.floor(i / 26)) .. string.char(97 + i % 26) .. "x-Realm"
		w.council[Key(n)] = true
		w:As(m1, m1.Church.TakePresence, "CHANNEL", n, "NK~1~p~N~-~Olympus Ember")
	end
	local list, left = w:As(m1, m1.Church.RoomRecipients)
	eq(#list, 30)
	local got = {}
	for _, n in ipairs(list) do got[Key(n)] = true end
	eq(got[Key("Nils Ford")], true, "her own network")
	eq(got[Key(APOSTLES[1])], true, "her Apostle")
	eq(got[Key("Olga Rhys")], true, "another network's missionary before the council")
	eq(got[Key(World.HEAD)], true); eq(got[Key(World.KING)], true); eq(got[Key(World.AUTHOR)], true)
	eq(left, 5, "35 online in the audience")
	-- Her line says so, on her screen alone.
	eq(w:As(m1, m1.c.ChatRooms.Send, "church", "brothers"), true)
	local told
	for _, p in ipairs(m1.printed) do if p == ns.L.CHURCH_ROOM_NOT_REACHED:format(5) then told = true end end
	eq(told, true)
end)
