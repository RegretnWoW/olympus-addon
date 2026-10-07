-- 1.1.6, the Missionary Church of Olympus: the guild log, the evidence, the keepers' ledger, the
-- points and rankings, registrations, transfers, the public view and the top 3.
-- Run alone: luajit tests/run.lua "1.1.6 Church"
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-count%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key
local DAY = 86400

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

-- Two guilds: Aldric (an Apostle, the desk) and his missionary Mira in Olympus Ember with Wes (a
-- plain member, a witness); Bera (an Apostle) and Vik (a plain member) in Olympus Vale. The Head,
-- the King and the author are offline unless a test brings them in.
local function Cast()
	local w = World.New({ apostles = { A1, A2 } })
	local c = {
		head = w:Client(World.HEAD), king = w:Client(World.KING), author = w:Client(World.AUTHOR),
		a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }),
		m1 = w:Client("Mira Wells"), m2 = w:Client("Nils Ford"),
		wes = w:Client("Wes Brook"), vik = w:Client("Vik Stone", { guild = World.GUILD2 }),
	}
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(c.m1, c.m1.Church.NameMissionary, "Nils Ford")
	c.head.online, c.king.online, c.author.online = false, false, false
	-- (Invites before a naming don't count: the log's events below are some hours after it.)
	w:Run(8 * 3600)
	w:Presence()
	return w, c
end

-- A player joins a guild in this world (no addon): its members' rosters show him.
local function Join(w, guild, name)
	w.members[guild] = w.members[guild] or {}
	table.insert(w.members[guild], name)
	w:RefreshRosters()
end
local function Leave(w, guild, name)
	local list = w.members[guild] or {}
	for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
	w:RefreshRosters()
end
-- Every client's tick, then `seconds` on the clock (seen-check answers, closes).
local function Settle(w, seconds)
	w:Tick()
	w:Run(seconds or 2)
	w:Tick()
	w:Run(2)
end
local function StateOf(w, keeper, recruit, by)
	return w:As(keeper, keeper.Count.StateOf, Key(recruit) .. ":" .. Key(by))
end
local function Rec(w, keeper, recruit, by)
	return w:As(keeper, keeper.Count.Led).r[Key(recruit) .. ":" .. Key(by)]
end

test("1.1.6 Church: the guild log: an invite by a missionary then the join is a pair; the recruiter's own report is pending, a guildmate's confirms it", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "New Guy", 3)
	w:LogEvent(World.GUILD, "join", "New Guy", nil, 2)
	Join(w, World.GUILD, "New Guy")
	-- Mira's own read: a pair reported to the keepers online (Aldric, Bera), pending.
	eq(w:ReadLog(c.m1), true)
	eq(#w:Sent(c.m1, "NV", "WHISPER", "w"), 2, "to each keeper heard online")
	eq(StateOf(w, c.a1, "New Guy", "Mira Wells"), "pending")
	eq(Rec(w, c.a1, "New Guy", "Mira Wells").s, 1, "the recruiter's own report")
	-- Wes's client read it too (Mira's presence over GUILD made it worth reading): confirmed.
	eq(w:ReadLog(c.wes), true)
	eq(StateOf(w, c.a1, "New Guy", "Mira Wells"), "credited")
	eq(StateOf(w, c.a2, "New Guy", "Mira Wells"), "credited", "every keeper took it")
	eq(Rec(w, c.a1, "New Guy", "Mira Wells").ws[1], Key("Wes Brook"))
	-- Read again: nothing sent twice; the ledger has one record.
	w:ClearSent()
	w:Run(61)
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(#w:Sent(nil, "NV"), 0, "duplicates are not sent again")
	local n = 0
	for _ in pairs(w:As(c.a1, c.a1.Count.Led).r) do n = n + 1 end
	eq(n, 1)
end)

test("1.1.6 Church: not a pair: a join without a Church person's invite, a join past 48 hours, a join before the invite", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Wes Brook", "Plain Recruit", 5)
	w:LogEvent(World.GUILD, "join", "Plain Recruit", nil, 4)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Slow Joiner", 60)
	w:LogEvent(World.GUILD, "join", "Slow Joiner", nil, 2)
	w:LogEvent(World.GUILD, "join", "Early Bird", nil, 10)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Early Bird", 5)
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(#w:Sent(nil, "NV", "WHISPER", "w"), 0)
	eq(next(w:As(c.a1, c.a1.Count.Led).r), nil)
end)

test("1.1.6 Church: evidence the keeper refuses: a recruiter with no place, invited before his naming, a non-Olympus guild, bad times, over budget, net-off", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local function Ev(inviter, invitee, guild, ti, tj)
		return ("NV~1~w~%s~%s~%s~%s~%s"):format(inviter, invitee, guild, B(ti), B(tj))
	end
	local function Take(from, text) return select(2, w:As(c.a1, c.a1.Count.TakeEvidence, from, text)) end
	eq(Take("Wes Brook-Realm", Ev("Wes Brook-Realm", "Some One-Realm", World.GUILD, hour - 2, hour - 1)), "recruiter")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour - 30, hour - 29)), "recruiter", "before his naming")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", "Horde Rivals", hour, hour)), "guild")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour + 3)), "times", "a join in the future")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour - 5)), "times", "a join before the invite")
	eq(Take("Some One-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour)), "recruit", "the recruit himself is no source")
	-- A linked alt's report is the recruiter's: it confirms nothing.
	w.alts[Key("Mira Wells")] = { "Mira Alt-Realm" }
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Alt-Realm", Ev("Mira Wells-Realm", "Alt Pal-Realm", World.GUILD, hour, hour)), true)
	eq(StateOf(w, c.a1, "Alt Pal", "Mira Wells"), "pending")
	-- Over budget: past EVIDENCE_HOUR from one sender, refused for the hour.
	for i = 1, c.a1.Count.EVIDENCE_HOUR do w:As(c.a1, c.a1.Count.TakeEvidence, "Spam Mer-Realm", "NV~1~q~" .. i) end
	eq(Take("Spam Mer-Realm", Ev("Mira Wells-Realm", "Late Pal-Realm", World.GUILD, hour, hour)), "budget")
	-- A net-off sender.
	w.off[Key("Off Man")] = { off = true }
	eq(Take("Off Man-Realm", Ev("Mira Wells-Realm", "Off Pal-Realm", World.GUILD, hour, hour)), "netoff")
	-- Not a keeper: a plain member's client takes no evidence.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeEvidence, "Wes Brook-Realm", Ev("Mira Wells-Realm", "X Y-Realm", World.GUILD, hour, hour))), "not keeper")
end)

test("1.1.6 Church: new to Olympus: a seen-check from another Olympus guild within 90 days makes a transfer, never credited", function()
	local w, c = Cast()
	-- Mover was in Olympus Vale until 20 days ago (Vik's roster memory saw him there).
	Join(w, World.GUILD2, "Mover Man")
	w:Tick()
	w:Run(DAY)
	Leave(w, World.GUILD2, "Mover Man")
	w:Run(20 * DAY)
	w:Presence()
	-- Mira invites him into Olympus Ember; Wes confirms the join.
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Mover Man", 3)
	w:LogEvent(World.GUILD, "join", "Mover Man", nil, 2)
	Join(w, World.GUILD, "Mover Man")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Mover Man", "Mira Wells"), "credited", "confirmed, until the check")
	-- The desk asks the channel; Vik's client knew him in another Olympus guild.
	Settle(w, 700)
	eq(#w:Sent(c.a1, "NS", "CHANNEL", "q") >= 1, true, "the desk's seen-check")
	eq(#w:Sent(c.vik, "NS", "WHISPER", "a") >= 1, true, "the answer from roster memory")
	eq(StateOf(w, c.a1, "Mover Man", "Mira Wells"), "transfer")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
	-- A brand-new recruit: the same check makes no transfer, and a guildmate's answer confirms him.
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Brand New", 3)
	w:LogEvent(World.GUILD, "join", "Brand New", nil, 2)
	Join(w, World.GUILD, "Brand New")
	w:Tick()
	w:ReadLog(c.m1)
	eq(StateOf(w, c.a1, "Brand New", "Mira Wells"), "pending")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Brand New", "Mira Wells"), "credited", "Wes's client read the same pair in the guild's log")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 10)
end)

test("1.1.6 Church: alts are never credited: the recruiter's own linked character, or a recruit whose linked character was in Olympus", function()
	local w, c = Cast()
	w.alts[Key("Mira Wells")] = { "Mira Second-Realm" }
	w.alts[Key("Mira Second")] = { "Mira Wells-Realm" }
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Mira Second", 3)
	w:LogEvent(World.GUILD, "join", "Mira Second", nil, 2)
	-- Old Main played in Olympus Ember last month; his new character joins through Mira.
	Join(w, World.GUILD, "Old Main")
	w:Tick()
	w:Run(DAY)
	Leave(w, World.GUILD, "Old Main")
	w:Run(20 * DAY)
	w:Presence()
	w.alts[Key("New Alt")] = { "Old Main-Realm" }
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "New Alt", 3)
	w:LogEvent(World.GUILD, "join", "New Alt", nil, 2)
	Join(w, World.GUILD, "Mira Second"); Join(w, World.GUILD, "New Alt")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Mira Second", "Mira Wells"), "alt", "her own other character")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "New Alt", "Mira Wells"), "alt", "a linked character of his was in Olympus")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
end)

test("1.1.6 Church: a seen-check only from a keeper, answered only with a fact, once per client, at most eight answers", function()
	local w, c = Cast()
	Join(w, World.GUILD, "Known Guy")
	w:Tick()
	-- From a plain member: no answer.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeCheck, "Vik Stone-Realm", "NS~1~q~1~Known Guy~j")), "keeper")
	-- From the desk, about a name nobody knows: no answer.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeCheck, A1, "NS~1~q~1~Never Seen~j")), "unknown")
	-- Unknown check ids, a second answer from one client, more than eight: dropped.
	eq(select(2, w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~zz~Olympus Ember~1~1~1")), "no check")
	local checks = w:As(c.a1, c.a1.Count.OpenChecks)
	checks.q1 = { cid = "q1", rid = "x:y", why = "j", sent = w.clock, answers = {}, from = {} }
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~q1~Olympus Ember~1~1~1"), true)
	eq(select(2, w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~q1~Olympus Ember~1~1~1")), "twice")
	for i = 2, 8 do w:As(c.a1, c.a1.Count.TakeAnswer, "Answer Er" .. ("x"):rep(i) .. "-Realm", "NS~1~a~q1~Olympus Ember~1~1~1") end
	eq(checks.q1, nil, "closed at eight answers")
	-- The King's client answers no check.
	eq(select(2, w:As(c.king, c.king.Count.TakeCheck, A1, "NS~1~q~2~Known Guy~j")), "king")
end)

test("1.1.6 Church: registrations: counted when the player arrives in an Olympus guild within 14 days; not for one already in Olympus; expired after", function()
	local w, c = Cast()
	-- Mira registers a player she brought; another guild's officer invites him (no Church person).
	eq(w:Act(c.m1, c.m1.Count.Register, "Far Guy"), true)
	eq(StateOf(w, c.a1, "Far Guy", "Mira Wells"), "open")
	w:Run(DAY)
	Join(w, World.GUILD2, "Far Guy")
	w:Tick()
	w:Run(DAY * 2)
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Far Guy", "Mira Wells"), "credited", "Vik's client places him in Olympus Vale since the registration")
	eq(Rec(w, c.a1, "Far Guy", "Mira Wells").g, World.GUILD2)
	-- Already in Olympus when registered: refused at the check.
	Join(w, World.GUILD2, "Old Hand")
	w:Tick()
	w:Run(10 * DAY)
	w:Presence()
	w:Act(c.m1, c.m1.Count.Register, "Old Hand")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Old Hand", "Mira Wells"), "transfer")
	-- Nobody shows up for 14 days: expired, never counted.
	w:Act(c.m1, c.m1.Count.Register, "No Show")
	w:Run(15 * DAY)
	w:Presence()
	eq(StateOf(w, c.a1, "No Show", "Mira Wells"), "expired")
	-- Limits: fifteen open at once.
	for i = 1, 16 do w:As(c.m1, c.m1.Count.Register, "Reg Number" .. ("q"):rep(i)) end
	eq(w:Printed(c.m1), ns.L.CHURCH_REG_FULL:format(15), "the sixteenth")
	-- Withdrawn by its registrant.
	w:Act(c.m1, c.m1.Count.Withdraw, "Reg Numberq")
	eq(StateOf(w, c.a1, "Reg Numberq", "Mira Wells"), "withdrawn")
	-- A plain member registers nothing.
	eq(w:Act(c.wes, c.wes.Count.Register, "Some Body"), nil)
	eq(w:Printed(c.wes), ns.L.CHURCH_NO_RIGHTS)
end)

test("1.1.6 Church: exclusive: one recruit counts for one person only, the earliest invite or registration", function()
	local w, c = Cast()
	-- Nils registers Dual Guy first; Mira's invite comes later: Nils's.
	w:Act(c.m2, c.m2.Count.Register, "Dual Guy")
	w:Run(3600 * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Dual Guy", 1)
	w:LogEvent(World.GUILD, "join", "Dual Guy", nil, 0)
	Join(w, World.GUILD, "Dual Guy")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Dual Guy", "Nils Ford"), "credited")
	eq(StateOf(w, c.a1, "Dual Guy", "Mira Wells"), "taken")
	-- An invite earlier than a registration wins over it.
	w:Run(120)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "First Come", 2)
	w:LogEvent(World.GUILD, "join", "First Come", nil, 1)
	Join(w, World.GUILD, "First Come")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	w:Act(c.m2, c.m2.Count.Register, "First Come")
	eq(StateOf(w, c.a1, "First Come", "Mira Wells"), "credited")
	eq(StateOf(w, c.a1, "First Come", "Nils Ford"), nil, "refused at once: already credited")
end)

test("1.1.6 Church: points: own work counts most: a missionary with five recruits outscores his Apostle with two, and the one he named the same way", function()
	local w, c = Cast()
	local K = c.a1
	local now = w.clock
	local n = 0
	-- Confirmed records straight into Aldric's ledger (what the log and the witnesses make).
	local function Recruits(by, count)
		for _ = 1, count do
			n = n + 1
			local recruit = "Recruit " .. string.char(65 + math.floor(n / 26)) .. string.char(97 + n % 26)
			w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
				tc = now - 7200, tj = now - 3600, ws = { "wes brook" }, c = 1 }, false)
		end
	end
	Recruits(A1, 2)
	Recruits("Mira Wells", 5)
	local score, own, share, levels = w:As(K, K.Count.Score, Key(A1), "a")
	eq(own, 20); eq(share, 12.5); eq(score, 32.5); eq(levels[1], 12.5)
	local mScore, mOwn = w:As(K, K.Count.Score, Key("Mira Wells"), "a")
	eq(mOwn, 50); eq(mScore, 50, "no one under Mira has points yet")
	eq(mScore > score, true, "the missionary below outscores the Apostle above")
	-- Between a missionary and the one he named: Nils with 5, Mira with 2 of her own.
	w:As(K, K.Count.Led).r = {}
	K.Count.Changed()
	Recruits("Mira Wells", 2)
	Recruits("Nils Ford", 5)
	local nScore = w:As(K, K.Count.Score, Key("Nils Ford"), "a")
	local mScore2, mOwn2, mShare2 = w:As(K, K.Count.Score, Key("Mira Wells"), "a")
	eq(nScore, 50); eq(mOwn2, 20); eq(mShare2, 12.5); eq(nScore > mScore2, true)
	-- Aldric's network score: 25% of Mira's own, 10% of Nils's (level 2), nothing compounded.
	local aScore, aOwn, aShare, aLevels, aNet = w:As(K, K.Count.Score, Key(A1), "a")
	eq(aOwn, 0); eq(aLevels[1], 5); eq(aLevels[2], 5); eq(aShare, 10); eq(aScore, 10); eq(aNet, 7)
	-- Three levels at most: a fourth level's points give the Apostle nothing.
	local lv3, lv4 = w:Client("Third Level"), w:Client("Fourth Level")
	w:Act(c.m2, c.m2.Church.NameMissionary, "Third Level")
	w:Act(lv3, lv3.Church.NameMissionary, "Fourth Level")
	Recruits("Third Level", 2)
	Recruits("Fourth Level", 10)
	local _, _, _, levels4 = w:As(K, K.Count.Score, Key(A1), "a")
	eq(levels4[3], 1, "5% of the third level's 20")
	eq(w:As(K, K.Count.Score, Key(A1), "a"), 11, "the fourth level's 100 count nothing for the Apostle")
	_ = lv4
end)

test("1.1.6 Church: still in after 7 days: +5 then; one who left before keeps the 10, never the 5; the windows", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Stay Er", 3)
	w:LogEvent(World.GUILD, "join", "Stay Er", nil, 2)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Quit Ter", 3)
	w:LogEvent(World.GUILD, "join", "Quit Ter", nil, 2)
	Join(w, World.GUILD, "Stay Er"); Join(w, World.GUILD, "Quit Ter")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	Settle(w, 700)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 20)
	w:Run(3 * DAY)
	Leave(w, World.GUILD, "Quit Ter")
	w:Tick()
	-- Seven days after the join: the desk asks again (three tries for one nobody places now).
	for _ = 1, 7 do
		w:Run(DAY)
		w:Presence()
		Settle(w, 700)
	end
	eq(Rec(w, c.a1, "Stay Er", "Mira Wells").y, 1)
	eq(Rec(w, c.a1, "Quit Ter", "Mira Wells").y, 0, "left before: no 5")
	local own = w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a")
	eq(own.points, 25); eq(own.joins, 2); eq(own.stays, 1)
	-- This week holds the +5 (dated at join + 7 days); a window 30 days on holds nothing.
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").points, 25)
	w:Run(31 * DAY)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").points, 0)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 25, "all time keeps them")
end)

test("1.1.6 Church: the numbers follow the person across Olympus guilds", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Ember Kid", 3)
	w:LogEvent(World.GUILD, "join", "Ember Kid", nil, 2)
	Join(w, World.GUILD, "Ember Kid")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	-- Mira moves to Olympus Vale and recruits there; Vik witnesses.
	c.m1.guild = World.GUILD2
	w:RefreshRosters()
	w:Run(120)
	w:Presence()
	w:LogEvent(World.GUILD2, "invite", "Mira Wells", "Vale Kid", 1)
	w:LogEvent(World.GUILD2, "join", "Vale Kid", nil, 0)
	Join(w, World.GUILD2, "Vale Kid")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.vik)
	local own = w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a")
	eq(own.joins, 2); eq(own.points, 20)
	eq(own.guilds[World.GUILD].joins, 1); eq(own.guilds[World.GUILD2].joins, 1)
end)

test("1.1.6 Church: the rankings: Apostles by network score, missionaries by own plus shares; the numbers only to the audience; a person's detail to whom D4 says", function()
	local w, c = Cast()
	local K = c.a1
	local function Give(by, recruit)
		w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
			tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" }, c = 1 }, false)
	end
	Give("Mira Wells", "R Aa"); Give("Mira Wells", "R Ab"); Give("Nils Ford", "R Ac"); Give(A2, "R Ad")
	local apostles = w:As(K, K.Count.Ranking, "a", "w")
	eq(#apostles, 3, "the Head is one of the Apostles")
	eq(apostles[1].key, Key(A2)); eq(apostles[1].score, 10)
	eq(apostles[2].key, Key(A1)); eq(apostles[2].score, 6, "25% of Mira's 20 + 10% of Nils's 10"); eq(apostles[2].net, 3)
	eq(apostles[3].key, Key(World.HEAD)); eq(apostles[3].score, 0)
	local missionaries = w:As(K, K.Count.Ranking, "m", "w")
	eq(missionaries[1].key, Key("Mira Wells")); eq(missionaries[1].score, 22.5); eq(missionaries[2].score, 10)
	-- A missionary asks the desk; the rows come back by whisper, his own breakdown with them.
	w:ClearSent()
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "w"), true)
	w:Run(30)
	local rows = w:As(c.m2, c.m2.Count.RankingView, "m", "w")
	eq(#rows, 2); eq(rows[1].score, 22.5); eq(rows[1].name, "Mira Wells")
	-- A plain member's ask is refused.
	eq(select(2, w:As(K, K.Count.Answer, "Wes Brook-Realm", "m", "w")), "audience")
	-- Detail: the person himself, the Head, the Apostles, the council, the King, the author; not another missionary.
	eq(w:As(K, K.Count.MaySeeDetail, "Nils Ford-Realm", "Mira Wells-Realm"), false)
	eq(w:As(K, K.Count.MaySeeDetail, "Mira Wells-Realm", "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, A2, "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, World.COUNCILLOR, "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, "Wes Brook-Realm", "Mira Wells-Realm"), false)
	eq(select(2, w:As(K, K.Count.Answer, "Nils Ford-Realm", "p", "w", "Mira Wells")), "detail")
	w:As(c.m1, c.m1.Count.Ask, "me", "a")
	w:Run(30)
	local lines = w:As(c.m1, c.m1.Count.DetailView, "Mira Wells-Realm", "a")
	eq(lines[1][1], "s"); eq(lines[1][2], 20); eq(lines[1][3], 2.5, "her own breakdown: own 20, level 1 2.5")
end)

test("1.1.6 Church: the public view: nothing while closed; switch requires a publisher; only rows people chose to show", function()
	local w, c = Cast()
	c.author.online = true
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(K, K.Count.MergeIn, "r ab:nils ford", { n = "R Ab", bn = "Nils Ford", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(c.author, c.author.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Presence()
	w:Tick()
	eq(#w:Sent(nil, "NR", "CHANNEL", "p"), 0, "closed: nothing broadcast")
	-- Somebody else's switch is refused.
	w:As(c.wes, c.wes.Church.Receive, "CHANNEL", A1, "NB~1~s~1~" .. ns.Codec.Base36(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), false)
	-- The author opens it; Mira shows her row, Nils doesn't (off by default).
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	eq((w:As(c.wes, c.wes.Church.Public)), true)
	w:Tick()
	local rows = w:Sent(nil, "NR", "CHANNEL", "p")
	eq(#rows, 1, "one opted-in row")
	assert(rows[1].msg:find("Mira Wells", 1, true))
	local v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.m[1].name, "Mira Wells")
	eq(v.m[2], nil, "Nils's row never left the desk")
	-- Closing: every member drops it (in the same second too: a newer word).
	w:Act(c.author, c.author.Church.SetPublic, false)
	eq(w:As(c.wes, c.wes.Count.PublicView), nil)
end)

test("1.1.6 Church: the top 3 of each ranking: from the Head's, the King's or the author's client only, opted-in people, while the ranking is open", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local A = c.author
	for i, by in ipairs({ "Mira Wells", "Nils Ford" }) do
		for j = 1, i do
			w:As(A, A.Count.MergeIn, "r " .. i .. j .. ":" .. Key(by), { n = "R B" .. i .. j, bn = by, g = World.GUILD, kind = "i",
				tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
		end
	end
	eq(w:As(c.wes, c.wes.Church.Top3), nil, "nothing while closed")
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick({ c.author })
	local top = w:As(c.wes, c.wes.Church.Top3)
	eq(top.missionaries[1], "Nils Ford"); eq(top.missionaries[2], "Mira Wells")
	eq(#top.apostles, 0, "no Apostle chose to show his row")
	-- From an Apostle's client (a keeper, not a root): refused.
	local forged = "NR~1~t~" .. ns.Codec.Base36(w.clock + 5) .. "~Aldric Vane~Mira Wells"
	eq(select(2, w:As(c.wes, c.wes.Count.TakeTop, A1, forged)), "root")
	eq(w:As(c.wes, c.wes.Church.Top3).missionaries[1], "Nils Ford")
	-- From the King's: taken.
	eq(w:As(c.wes, c.wes.Count.TakeTop, World.KING, forged), true)
	eq(w:As(c.wes, c.wes.Church.Top3).apostles[1], "Aldric Vane")
end)

test("1.1.6 Church: the outbox: evidence waits while no keeper is online, goes on the first keeper's presence, is dropped after 7 days", function()
	local w, c = Cast()
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Quiet Guy", 3)
	w:LogEvent(World.GUILD, "join", "Quiet Guy", nil, 2)
	w:Tick({ c.m1 })
	w:ReadLog(c.m1)
	eq(#w:As(c.m1, function() return c.m1.Count.Led and c.m1.Church.Store().out end), 1, "held")
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 0)
	eq(StateOf(w, c.a1, "Quiet Guy", "Mira Wells"), "pending")
	-- Past 7 days in the outbox: dropped.
	c.a1.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Stale Guy", 3)
	w:LogEvent(World.GUILD, "join", "Stale Guy", nil, 2)
	w:Run(61)
	w:ReadLog(c.m1)
	w:Run(8 * DAY)
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(StateOf(w, c.a1, "Stale Guy", "Mira Wells"), nil)
end)

test("1.1.6 Church: the keepers' ledger: a keeper catches up from another; the merge is the same in any order and taken twice changes nothing", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local e1 = ("NV~1~w~Mira Wells-Realm~Merge Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 2), B(hour - 1))
	local e2 = ("NV~1~w~Mira Wells-Realm~Merge Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 3), B(hour - 1))
	w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", e1)
	w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", e2)
	w:As(c.a2, c.a2.Count.TakeEvidence, "Wes Brook-Realm", e2)
	w:As(c.a2, c.a2.Count.TakeEvidence, "Mira Wells-Realm", e1)
	w:As(c.a2, c.a2.Count.TakeEvidence, "Mira Wells-Realm", e1)
	local r1, r2 = Rec(w, c.a1, "Merge Guy", "Mira Wells"), Rec(w, c.a2, "Merge Guy", "Mira Wells")
	eq(r1.tc, r2.tc); eq(r1.tc, (hour - 3) * 3600, "the earliest invite"); eq(r1.s, r2.s); eq(r1.ws[1], r2.ws[1])
	-- The Head comes online with nothing: he catches up from the desk.
	c.head.online = true
	w:Presence()
	eq(w:As(c.head, c.head.Count.CatchUp, true), true)
	w:Run(30)
	local r3 = Rec(w, c.head, "Merge Guy", "Mira Wells")
	eq(r3 and r3.tc, r1.tc)
	eq(w:As(c.head, c.head.Count.StateOf, Key("Merge Guy") .. ":" .. Key("Mira Wells")), "credited")
	-- A line from a non-keeper is refused.
	local line = w:As(c.a1, c.a1.Count.RecordLine, "x", r1)
	eq(select(2, w:As(c.head, c.head.Count.TakeLine, "Wes Brook-Realm", line)), "keeper")
end)

test("1.1.6 Church: reading the log: never in combat, at most every minute, drawn among guildmates, never on the King's client; the event registered once, on first use", function()
	local w, c = Cast()
	-- ChatRooms independently registers CHAT_MSG_GUILD. Count only this module's log event;
	-- Cast has already run eight hours, so test load on a genuinely fresh world.
	local function LogRegistrations(cl)
		local n = 0
		for _, event in ipairs(cl.registered) do if event == "GUILD_EVENT_LOG_UPDATE" then n = n + 1 end end
		return n
	end
	local fresh = World.New({ head = false }):Client("Fresh Witness")
	eq(LogRegistrations(fresh), 0, "no log event registered at load")
	c.m1.combat = true
	eq(select(2, w:As(c.m1, c.m1.Count.Read)), "combat")
	c.m1.combat = false
	eq(w:As(c.m1, c.m1.Count.Read), true)
	eq(select(2, w:As(c.m1, c.m1.Count.Read)), "gap")
	w:Run(61)
	eq(w:As(c.m1, c.m1.Count.Read), true)
	eq(LogRegistrations(c.m1), 1, "log event registered exactly once, independently of chat's event")
	eq(c.m1.queries, 2)
	eq(select(2, w:As(c.king, c.king.Count.Read)), "king")
	-- A plain member reads only where a Church person was heard over GUILD, and then with a chance
	-- of 2 / his guild's addon users.
	local lone = w:Client("Lone Wolf", { guild = "Olympus Lone" })
	eq(w:As(lone, lone.Count.MaybeRead, w.clock + 400), false, "no Church person heard in his guild")
	c.wes.peers = 20
	c.wes.Count.chance = function() return 0.5 end
	eq(w:As(c.wes, c.wes.Count.MaybeRead, w.clock + 400), false, "0.5 > 2/20: not drawn")
	c.wes.Count.chance = function() return 0.05 end
	eq(w:As(c.wes, c.wes.Count.MaybeRead, w.clock + 800), true, "drawn")
	-- The fill: a correspondent's own client counts its guild's joins and leaves (never sent).
	w:Act(c.head, c.head.Church.NameCorrespondent, "Wes Brook", World.GUILD)
	w:LogEvent(World.GUILD, "join", "Filler One", nil, 1)
	w:LogEvent(World.GUILD, "quit", "Filler Two", nil, 1)
	w:Run(61)
	w:ClearSent()
	w:ReadLog(c.wes)
	local loc = w:As(c.wes, c.wes.Count.Local)
	eq(loc.joins >= 1, true); eq(loc.leaves, 1)
	eq(#w:Sent(c.wes, "NV"), 0, "the fill stays on his client")
end)

test("1.1.6 Church: saved data: a malformed ledger or book is dropped at load; the roster memory is bounded", function()
	local w = World.New({ apostles = { A1 } })
	local rdb = { church = { led = { v = 1, r = { ["x|y"] = { n = "Bad|Name", tc = "soon" } }, p = {}, from = {} },
		book = { v = 1, p = { bad = { role = "M", n = 7, at = "x" } }, x = {}, c = {}, cx = {} } } }
	local cl = w:Client("Saved One", { rdb = rdb })
	w:As(cl, cl.Church.CheckSaved)
	w:As(cl, cl.Count.CheckSaved)
	eq(next(rdb.church), nil, "a value with an escape code: the whole store goes")
	local rdb2 = { church = { led = { v = 1, r = { ["x:y"] = { n = "Fine Name", tc = "soon" } }, p = {}, from = {} },
		book = { v = 1, p = { bad = { role = "M", n = "Who Ever-Realm", at = "x" } }, x = {}, c = {}, cx = {} } } }
	local cl2 = w:Client("Saved Two", { rdb = rdb2 })
	w:As(cl2, cl2.Church.CheckSaved)
	w:As(cl2, cl2.Count.CheckSaved)
	eq(rdb2.church.led, nil); eq(rdb2.church.book, nil)
	-- A real ledger and book survive the load's check whole (their keys and lines carry no escape code).
	local w3, c3 = Cast()
	w3:LogEvent(World.GUILD, "invite", "Mira Wells", "Kept Guy", 3)
	w3:LogEvent(World.GUILD, "join", "Kept Guy", nil, 2)
	w3:ReadLog(c3.m1); w3:ReadLog(c3.wes)
	local store = w3:As(c3.a1, c3.a1.Church.Store)
	w3:As(c3.a1, c3.a1.Church.CheckSaved)
	w3:As(c3.a1, c3.a1.Count.CheckSaved)
	eq(StateOf(w3, c3.a1, "Kept Guy", "Mira Wells"), "credited", "the ledger kept")
	eq(store.book ~= nil and next(store.book.p) ~= nil, true, "the book kept")
	-- Memory: past MEMORY_MAX names the oldest go.
	cl2.Count.MEMORY_MAX = 5
	w.members[World.GUILD] = {}
	for i = 1, 8 do table.insert(w.members[World.GUILD], "Mem Ber" .. ("m"):rep(i)) end
	w:RefreshRosters()
	w:As(cl2, cl2.Count.Remember, true)
	cl2.Count.random = function() return 1 end
	w:Run(DAY)
	w.members[World.GUILD] = { "Mem Berm" }
	w:RefreshRosters()
	w:As(cl2, cl2.Count.Remember, true)
	local mem = w:As(cl2, cl2.Church.Store).mem
	local n = 0
	for _ in pairs(mem.n) do n = n + 1 end
	eq(n <= 5, true, n)
	eq(mem.n[Key("Mem Berm")] ~= nil, true, "the newest kept")
end)

test("1.1.6 Church: the counting's messages fit one message each at their worst (the longest names, realm and guild)", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local name = "Abcdefghijklmno Pqrstuvwxyzabc" -- 30 bytes, one space
	local full = name .. "-" .. ("R"):rep(40)
	local guild = ("G"):rep(48)
	local big = B(4 * 10 ^ 12 / 3600)
	eq(#name, 30)
	local ev = ("NV~1~w~%s~%s~%s~%s~%s"):format(full, full, guild, big, big)
	assert(#ev <= 255, #ev)
	-- (A guild's name is 24 letters at most in game; 48 bytes covers accented ones: an Olympus one reads back.)
	local rec = { n = name, bn = name, g = ("Olympus " .. ("\195\161"):rep(20)), kind = "g", tc = 4 * 10 ^ 9, tj = 4 * 10 ^ 9, s = 1, t = 1, a = 1, x = 1, c = 1, y = 1, q7 = 3, rq = 4,
		ws = { Key(name), Key("Bbcdefghijklmno Pqrstuvwxyzabc") }, u = 4 * 10 ^ 9 }
	local line = w:As(c.a1, c.a1.Count.RecordLine, "x", rec)
	assert(#line <= 255, #line)
	local id, back = w:As(c.a1, c.a1.Count.ParseRecord, line)
	assert(id and back, "it reads back")
	eq(back.tj, rec.tj); eq(back.y, 1); eq(back.q7, 3); eq(back.rq, 4)
	local answer = ("NS~1~a~%s~%s~%s~%s~1"):format(B(1679615), guild, B(99999), B(99999))
	assert(#answer <= 255, #answer)
	local row = ("NR~1~r~m~a~%d~%s~%d~%d~%d~%d~%d~%d~1"):format(300, name, 999999, 999999, 999999, 9999, 9999, 9999)
	assert(#row <= 255, #row)
	local top = ("NR~1~t~%s~%s~%s"):format(big, table.concat({ name, name, name }, ","), table.concat({ name, name, name }, ","))
	assert(#top <= 255, #top)
	-- (A kept missionary's entry: its since and its time, in seconds, the year 2096's.)
	local entry = ("NB~1~p~M~%s~%s~%s~M~%s~%s"):format(full, full, full, B(4 * 10 ^ 9), B(4 * 10 ^ 9))
	assert(#entry <= 255, #entry)
end)

-- Review (lane-church): what the first build lost or let through, each test failing on that build.

-- A new session for a client of this world (the game's LOGIN event, as Church.lua listens to it).
local function Login(w, cl)
	for _, fn in ipairs(cl.listeners.LOGIN or {}) do w:As(cl, fn) end
end
local function Records(w, cl)
	local n = 0
	for _ in pairs(w:As(cl, cl.Count.Led).r) do n = n + 1 end
	return n
end
-- Letters for made-up names: 1 -> "b", 26 -> "ba", ...
local function Letters(n)
	local s = ""
	repeat s = string.char(97 + n % 26) .. s; n = math.floor(n / 26) until n == 0
	return s
end

test("1.1.6 Church: a recruiter's own made-up pair stays pending whoever's roster places the recruit, and takes no recruit from the inviter the log shows", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	-- Mira's modified client whispers pairs nobody's log has, dated before the real invite.
	local function Forged(recruit, ago)
		local hour = math.floor(w.clock / 3600)
		local text = ("NV~1~w~Mira Wells-Realm~%s-Realm~%s~%s~%s"):format(recruit, World.GUILD, B(hour - ago), B(hour - 2))
		for _, k in ipairs({ c.a1, c.a2 }) do eq(w:As(k, k.Count.TakeEvidence, "Mira Wells-Realm", text), true) end
	end
	-- Wes (no place in the Church) invited Real Newbie; Mira says she did.
	w:LogEvent(World.GUILD, "invite", "Wes Brook", "Real Newbie", 3)
	w:LogEvent(World.GUILD, "join", "Real Newbie", nil, 2)
	Join(w, World.GUILD, "Real Newbie")
	Forged("Real Newbie", 4)
	w:Tick()
	w:ReadLog(c.wes); w:ReadLog(c.m2)
	Settle(w, 700)
	eq(#w:Sent(c.a1, "NS", "CHANNEL", "q") >= 1, true, "the desk's seen-check ran")
	eq(StateOf(w, c.a1, "Real Newbie", "Mira Wells"), "pending", "a roster shows he is in the guild, not who invited him")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
	-- Nils really invited Contested Kid (the log, and Wes's read of it); Mira claims an earlier invite.
	w:LogEvent(World.GUILD, "invite", "Nils Ford", "Contested Kid", 3)
	w:LogEvent(World.GUILD, "join", "Contested Kid", nil, 2)
	Join(w, World.GUILD, "Contested Kid")
	Forged("Contested Kid", 5)
	w:Tick()
	w:ReadLog(c.m2); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Contested Kid", "Nils Ford"), "credited", "the confirmed claim before an earlier unconfirmed one")
	eq(StateOf(w, c.a1, "Contested Kid", "Mira Wells"), "taken")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Contested Kid", "Nils Ford"), "credited", "and still after the seen-check")
	eq(StateOf(w, c.a2, "Contested Kid", "Nils Ford"), "credited", "on every keeper")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Nils Ford"), "a").points, 10)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
end)

test("1.1.6 Church: a registration's last check runs even when the desk missed its day: one who arrived on day 10 is credited on day 15", function()
	local w, c = Cast()
	eq(w:Act(c.m1, c.m1.Count.Register, "Late Arriver"), true)
	Settle(w, 700)
	-- The checks of days 1, 3 and 7 find nobody.
	for _, days in ipairs({ 1, 2, 4 }) do
		w:Run(days * DAY)
		w:Presence()
		Settle(w, 700)
	end
	eq(Rec(w, c.a1, "Late Arriver", "Mira Wells").rq, 4, "four checks so far")
	-- He joins Olympus Vale on day 10; nobody's desk ticks on day 14.
	w:Run(3 * DAY)
	Join(w, World.GUILD2, "Late Arriver")
	w:Tick()
	w:Run(5 * DAY)
	eq(StateOf(w, c.a1, "Late Arriver", "Mira Wells"), "expired", "past 14 days with no answer yet")
	w:Presence()
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Late Arriver", "Mira Wells"), "credited", "Vik's client placed him in Olympus Vale since day 10")
	eq(Rec(w, c.a1, "Late Arriver", "Mira Wells").g, World.GUILD2)
	-- Never one who arrives after the 14 days, nor a check past REG_LATE.
	eq(w:Act(c.m1, c.m1.Count.Register, "Too Late"), true)
	Settle(w, 700)
	w:Run(16 * DAY)
	Join(w, World.GUILD2, "Too Late")
	w:Tick()
	w:Presence()
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Too Late", "Mira Wells"), "expired")
	w:Run((c.a1.Count.REG_LATE + 1) * DAY)
	w:Presence()
	w:ClearSent()
	Settle(w, 700)
	for _, e in ipairs(w:Sent(c.a1, "NS", "CHANNEL", "q")) do eq(e.msg:find("Too Late", 1, true), nil, "no check past REG_LATE") end
end)

test("1.1.6 Church: a registration made while no keeper is online waits in the outbox and is taken a day later", function()
	local w, c = Cast()
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	eq(w:Act(c.m1, c.m1.Count.Register, "Waiting Guy"), true)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 1, "held")
	w:Run(25 * 3600)
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 0)
	eq(StateOf(w, c.a1, "Waiting Guy", "Mira Wells"), "open")
	-- Older than the outbox keeps one: refused.
	local B = ns.Codec.Base36
	eq(select(2, w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", "NV~1~g~Too Late-Realm~" .. B(w.clock - 8 * DAY))), "times")
end)

test("1.1.6 Church: a catch-up over several rounds carries every record and every person's line (a public choice), records of one second too", function()
	local w, c = Cast()
	c.a2.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence({ c.a1, c.m1 })
	-- Mira shows her row while only Aldric is online; then Aldric takes 160 records, a second apart.
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	eq(w:As(c.a1, c.a1.Count.Led).p[Key("Mira Wells")].pub, true)
	local K, n = c.a1, 0
	local function Take(count, sameSecond)
		for _ = 1, count do
			n = n + 1
			if not sameSecond then w.clock = w.clock + 1 end
			local recruit = "Rec " .. Letters(n)
			w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key("Mira Wells"), { n = recruit, bn = "Mira Wells", g = World.GUILD, kind = "i",
				tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" }, c = 1 }, false)
		end
	end
	Take(160)
	-- Bera comes online and catches up from him: two rounds.
	c.a2.online = true
	w:Presence({ c.a1, c.a2 })
	w:ClearSent()
	eq(w:As(c.a2, c.a2.Count.CatchUp, true), true)
	w:Run(120)
	eq(#w:Sent(c.a2, "NL", "WHISPER", "q"), 2, "two rounds")
	eq(Records(w, c.a2), 160)
	local p = w:As(c.a2, c.a2.Count.Led).p[Key("Mira Wells")]
	eq(p and p.pub, true, "her choice came with them")
	-- 155 more in one second: a round never ends inside a second, so none is left behind.
	Take(155, true)
	eq(w:As(c.a2, c.a2.Count.CatchUp, true), true)
	w:Run(120)
	eq(Records(w, c.a2), 315)
end)

test("1.1.6 Church: the author's close reaches a desk and a member who missed it, from a keeper's presence, before the desk speaks for its saved switch", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	eq(w:As(c.wes, c.wes.Count.PublicView).m[1].name, "Mira Wells")
	-- The desk and Wes log off; the author closes (Bera, a keeper, hears it) and logs off too.
	c.a1.online, c.wes.online = false, false
	w:Run(60)
	w:Act(c.author, c.author.Church.SetPublic, false)
	eq((w:As(c.a2, c.a2.Church.Public)), false)
	c.author.online = false
	w:Run(c.a1.Count.PUBLIC_EVERY + 1)
	-- They come back in a new session: Aldric holds the open switch he saved.
	c.a1.online, c.wes.online = true, true
	Login(w, c.a1); Login(w, c.wes)
	eq((w:As(c.a1, c.a1.Church.Public)), true, "his saved switch")
	w:ClearSent()
	w:Tick({ c.a1 })
	eq(#w:Sent(c.a1, "NR", "CHANNEL", "p"), 0, "the desk waits after a login before it speaks for it")
	-- Bera's presence carries the close: both take it.
	w:Presence({ c.a2 })
	eq((w:As(c.a1, c.a1.Church.Public)), false)
	eq((w:As(c.wes, c.wes.Church.Public)), false)
	eq(w:As(c.wes, c.wes.Count.PublicView), nil)
	w:Run(700)
	w:Tick()
	eq(#w:Sent(c.a1, "NR", "CHANNEL", "p"), 0, "nothing broadcast after the close")
	-- A keeper's presence never opens it; the author's does. A plain member's close is nobody's.
	local B = ns.Codec.Base36
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", A2, "NK~1~p~A~-~Olympus Vale~1" .. B(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), false, "an Apostle's open is not the author's")
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", World.AUTHOR, "NK~1~p~W~-~Olympus Ember~1" .. B(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), true)
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", "Vik Stone-Realm", "NK~1~p~A~-~Olympus Vale~0" .. B(w.clock + 1))
	eq((w:As(c.wes, c.wes.Church.Public)), true)
end)

test("1.1.6 Church: the public view drops the row of one who hides it, an emptied list too (each list's rows end with their count)", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r ab:" .. Key(A1), { n = "R Ab", bn = "Aldric Vane", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(K, K.Count.MergeIn, "r ac:nils ford", { n = "R Ac", bn = "Nils Ford", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Act(c.a1, c.a1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	local v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.a[1].name, "Aldric Vane"); eq(v.m[1].name, "Nils Ford", "the only one in the missionaries' list")
	-- Nils hides his row: the next round has none in that list.
	w:Run(5)
	w:Act(c.m2, c.m2.Count.SetPublicRow, false)
	w:Run(c.a1.Count.PUBLIC_EVERY + 1)
	w:Tick()
	v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.a[1].name, "Aldric Vane"); eq(v.m[1], nil, "his row went with his choice")
	-- A count line from a plain member, or for another switch, changes nothing.
	eq(select(2, w:As(c.wes, c.wes.Count.TakePublicCount, "Vik Stone-Realm", "NR~1~n~" .. ns.Codec.Base36(v.at) .. "~a~0")), "keeper")
	eq(w:As(c.wes, c.wes.Count.PublicView).a[1].name, "Aldric Vane")
end)

test("1.1.6 Church: a full ledger archives the credited record it lets go, and never takes it back", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 3
	local ok, err = pcall(function()
		local function Give(recruit, by, ago)
			return w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = by, g = World.GUILD, kind = "i",
				tc = w.clock - ago - 3600, tj = w.clock - ago, ws = { "wes brook" }, c = 1 }, false)
		end
		Give("Old Recruit", "Mira Wells", 50 * DAY)
		Give("R Ba", "Nils Ford", 3600); Give("R Bb", "Nils Ford", 3600)
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10)
		-- The fourth: the oldest goes, its 10 points into Mira's archive.
		Give("R Bc", "Nils Ford", 3600)
		eq(Rec(w, K, "Old Recruit", "Mira Wells"), nil, "let go")
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10, "her all-time points kept")
		local _, _, _, levels = w:As(K, K.Count.Score, Key(A1), "a")
		eq(levels[1], 2.5, "and her Apostle's share of them")
		eq(Give("Old Recruit", "Mira Wells", 50 * DAY), false, "never taken back: it would count twice")
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10)
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)
