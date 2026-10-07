local ADDON, ns = ...
local L = ns.L

-- 1.2: Judgment: the High Council votes within a period and the King has the final word.
-- An officer of an Olympus guild sends one of The Watch's cases to the King:
-- what its judgment card shows (the name, what it is about, how many players reported it, how many
-- lines came with them) and his own finding, never who reported it, their notes nor the lines. The
-- King's client keeps it, and the High Council votes on it for a day (Judgment.PERIOD): each
-- councillor's client asks the King's client what is open whenever it is on (the Tabards' lease,
-- TabardsV2.Collector: the exact King client authenticated in the last 10 minutes) and votes upheld
-- or not upheld; the council's answer is the majority of those who answered (a tie: none). The King
-- gives the final word once the period is over or every councillor answered. Nothing happens by
-- itself: no sanction; the guild's Justice correspondent applies an upheld one (1.1.6: with
-- none named, its guild master), and the player is told the King's word in a pop-up (1.1.6,
-- WatchChat.TellCase, from the officer's client that sent the case). Who sent it and when, each vote and when, and the King's word with the
-- council's count and when are kept on the King's client (his Watch, Judgments), and his word goes
-- back to the officers who sent it (their case page). Every message is a logged whisper between an
-- officer's or a councillor's client and the King's, checked on both ends: nothing goes on the
-- channel or to a guild.
--   MJ~1~E~<id>~<guild>~<Name-Realm>~<categories>~<reporters>~<lines>~<finding U|D|->   a case to the King
--   MJ~1~A~<id>~<judgment id>  (or ~-~<why>)             the King's client keeps it (or refused it)
--   MJ~1~Q~<judgment ids>          what is open (a councillor's), how the asker's own cases stand
--   MJ~1~J~<jid>~<seconds left>~<guild>~<Name-Realm>~<categories>~<reporters>~<lines>~<finding>~<your vote U|D|->
--   MJ~1~N~<count>~<open>          the end of that list (<open>: how many are open in all)
--   MJ~1~V~<jid>~<U|D>             a councillor's vote (his newest counts)
--   MJ~1~K~<jid>~<U|D|X>           counted (X: the vote is closed)
--   MJ~1~R~<jid>~<O|W|F>~<U|D|->~<upheld>~<not upheld>~<answered>~<when decided>   how a case stands
--     (O: the council votes; W: the King's word comes next; F: his final word, U or D)
-- Clients before 1.2 know no MJ and leave it alone.

local J = {}
ns.Judgment = J

J.PROTOCOL = 1
J.PERIOD = 24 * 60 * 60      -- the High Council's vote
J.KEEP = 30 * 86400          -- the King's client keeps a judgment this long
J.MAX = 60                   -- and this many (the oldest decided ones go first)
J.MAX_OPEN = 40              -- not decided yet, at most
J.DAY = 5                    -- from one officer in a day
J.MAX_OPEN_GUILD = 10        -- 1.2.0 (Konig's review): not decided yet, from one guild
J.RETRY = 5 * 60             -- a case the King's client did not confirm goes again this often
J.QUERY_EVERY = 15 * 60      -- a councillor's (or a waiting officer's) client asks this often
J.HEARD = 20 * 60            -- the King's client tells at once those who asked this recently
J.ASK_GAP = 30               -- and answers one asker this often at most
J.SHOWN = 8                  -- open judgments in one answer (the asker's not voted on first)
J.ESCALATIONS_MAX = 30       -- an officer's client keeps this many sent cases
J.REFUSE_GAP = 60            -- the King's client refuses one sender this often at most
J.REFUSE_MINUTE = 10         -- and this many in a minute in all
J.SPREAD = 5 * 60            -- the askers' first ask once the King's client comes on: within this
J.random = math.random       -- (tests)

local OWNER = {}
local heard = {}      -- the King's client: [full name] = when they last asked (session only)
local answered = {}   -- the King's client: [full name] = when it last answered them
local incoming = {}   -- a councillor's client: [jid] = the open judgment as the King's client told it
local told = {}       -- [jid] = true once this session said it waits for a vote
local refused = {}    -- the King's client: [full name] = when it last refused them (session only)
local refusals = { at = -math.huge, n = 0 } -- and how many in the minute since `at`
local lease, lastAsk = nil, -math.huge -- (lease: the King's client's name as the last tick saw it)
local listed = nil    -- a councillor's client: the King's last list ({ shown, open })

J.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Key(s) return ns.Fold(tostring(s or "")) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Key(a) == Key(b) end

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function Num(s, low, high)
	local n = tonumber(s)
	if not n or n ~= math.floor(n) or n < low or n > high then return nil end
	return n
end

-- A field as it travels: no "~", "|", "^" or control byte, at most n bytes.
local function Field(s, n)
	if type(s) ~= "string" or s == "" or #s > n or s:find("[~|%^%c]") then return nil end
	return s
end

local function Watch()
	local W = ns.Watch
	return type(W) == "table" and not W.missing and W or nil
end

-- "A2S1": each category's letter with its count (The Watch's REPORT_ORDER), "-" for none.
local function CatsWire(cats)
	local out = {}
	for _, cat in ipairs({ "A", "S", "E", "O" }) do
		local n = math.floor(tonumber(type(cats) == "table" and cats[cat]) or 0)
		if n > 0 then out[#out + 1] = cat .. math.min(n, 999) end
	end
	return #out > 0 and table.concat(out) or "-"
end
local function CatsRead(s)
	if s == "-" then return {} end
	if type(s) ~= "string" or #s > 20 or s:gsub("[ASEO]%d+", "") ~= "" then return nil end
	local cats = {}
	for cat, n in s:gmatch("([ASEO])(%d+)") do
		n = tonumber(n)
		if cats[cat] or not n or n < 1 or n > 999 then return nil end
		cats[cat] = n
	end
	return cats
end

local function CatsText(cats)
	local W = Watch()
	return W and W.CatsText and W.CatsText(cats or {}) or "-"
end
local function ShownBy(name)
	local W = Watch()
	if W and W.ShownBy then return W.ShownBy(name) end
	return ns.DisplayName(name) or "?"
end
local function Stamp(at) return date and date("%Y-%m-%d %H:%M", at) or tostring(at) end

-- "14h 05m", "38m".
local function Span(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(math.max(1, m))
end

-- Why something was not done, as the player reads it (the code itself for one with no line).
local function Why(why)
	return rawget(L, "JUDGMENT_WHY_" .. tostring(why or "?"):upper()) or tostring(why or "?")
end

local function VerdictText(v)
	if v == "U" then return L.JUDGMENT_UPHELD end
	if v == "D" then return L.JUDGMENT_NOT_UPHELD end
	return "-"
end
local function VerdictColored(v)
	if v == "U" then return Green(L.JUDGMENT_UPHELD) end
	if v == "D" then return Red(L.JUDGMENT_NOT_UPHELD) end
	return Grey("-")
end

---------------------------------------------------------------------------
-- Who is who
---------------------------------------------------------------------------

local function IsKing() return ns.King and ns.King.IsKing and ns.King.IsKing() == true or false end
local function Councillor(name)
	return type(name) == "string" and ns.IsHighCouncillor and ns.IsHighCouncillor(name) == true and not ns.IsKingCharacter(name)
end
-- 1.1.6: a councillor under a moderator's sanction (WatchChat.PowersBarred: a timeout, a hold, a
-- net-off word) votes on nothing while it lasts: his client sends no vote, and the King's client,
-- which knows its own timeouts, takes none from him. A vote he gave before stays counted.
local function Voting(name)
	if not Councillor(name) then return false end
	local WC = ns.WatchChat
	return not (type(WC) == "table" and not WC.missing and type(WC.PowersBarred) == "function" and WC.PowersBarred(name) ~= nil)
end
J.Voting = Voting

-- The King's client on now (its exact name), as the Tabards' lease says it, or nil.
local function Collector()
	local T = ns.TabardsV2
	if type(T) ~= "table" or T.missing or type(T.Collector) ~= "function" then return nil end
	local c = T.Collector()
	if type(c) ~= "table" or type(c.name) ~= "string" or not ns.IsKingCharacter(c.name) then return nil end
	return c
end
J.Collector = Collector
local function FromKing(sender)
	local c = Collector()
	return c ~= nil and Same(ns.FullName(sender), c.name)
end

-- The signed council's names (short, lower case), the King's left out: the council's size.
local function CouncilNames()
	local c = ns.rdb and ns.rdb.council
	local king = ns.KingCharacter and ns.KingCharacter()
	local out = {}
	if type(c) == "table" and type(c.names) == "table" then
		for name in pairs(c.names) do
			if type(name) == "string" and not (king and name == king:lower()) then out[#out + 1] = name end
		end
	end
	table.sort(out)
	return out
end

-- The King's side of the page: the King (his preview too: what his client would show, nothing it
-- does reaching anyone); the council's: a councillor (or the author's preview of one).
local function ViewAs()
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true then return V end
	return nil
end
function J.KingSide()
	return IsKing() or (ns.King and ns.King.Preview and ns.King.Preview() == true) or false
end
function J.CouncilSide()
	local V = ViewAs()
	if V and V.Role() ~= "my" then return V.Role() == "councillor" end
	return Councillor(ns.me)
end
-- The Watch's Judgments (Watch.lua): the King, a councillor, and the author (every page; a role's
-- preview: that role's).
function J.Visible()
	local V = ViewAs()
	if V then return V.Role() == "my" or V.Allows("judgments") == true end
	return J.KingSide() or J.CouncilSide()
end

---------------------------------------------------------------------------
-- The King's client: the judgments
---------------------------------------------------------------------------

local function KingStore(create)
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.judgments
	if type(s) ~= "table" then
		if not create then return nil end
		s = {}
		ns.rdb.judgments = s
	end
	if type(s.list) ~= "table" then s.list = {} end
	s.seq = math.max(0, math.floor(tonumber(s.seq) or 0))
	return s
end
J.KingStore = KingStore

local function ValidJudgment(key, j)
	if type(j) ~= "table" or type(j.jid) ~= "number" or tostring(j.jid) ~= key then return false end
	if not Field(j.from, 72) or not Field(j.guild, 72) or not Field(j.target, 72) or type(j.id) ~= "number" then return false end
	if type(j.at) ~= "number" or type(j.closes) ~= "number" or type(j.cats) ~= "table" or type(j.votes) ~= "table" then return false end
	if j.final ~= nil and (type(j.final) ~= "table" or (j.final.v ~= "U" and j.final.v ~= "D") or type(j.final.at) ~= "number") then return false end
	return true
end

-- The council's count now: upheld, not upheld, answered (by councillors still on the signed list),
-- and whether every councillor answered.
local function Tally(j)
	local up, down, by = 0, 0, {}
	for voter, vote in pairs(j.votes or {}) do
		if type(vote) == "table" and Councillor(voter) then
			if vote.v == "U" then up = up + 1 elseif vote.v == "D" then down = down + 1 end
			by[ns.ShortName(voter):lower()] = true
		end
	end
	local names = CouncilNames()
	local all = true
	for _, name in ipairs(names) do if not by[name] then all = false break end end
	return up, down, up + down, #names, all
end
J.Tally = Tally

-- The majority of those who answered: "U", "D", or nil (a tie, or nobody).
function J.Majority(up, down)
	if up > down then return "U" end
	if down > up then return "D" end
	return nil
end

-- "O" the council votes, "W" the King's word comes next, "F" decided.
local function State(j)
	if j.final then return "F" end
	local _, _, _, _, all = Tally(j)
	if Clock() >= j.closes or all then return "W" end
	return "O"
end
J.State = State

function J.Prune()
	local s = KingStore(false)
	if not s then return end
	local now = Clock()
	for key, j in pairs(s.list) do
		if not ValidJudgment(key, j) or now - j.at > J.KEEP then s.list[key] = nil end
	end
	-- At most MAX: the oldest decided go first, then the oldest of all.
	local all = {}
	for key, j in pairs(s.list) do all[#all + 1] = { key = key, j = j } end
	if #all <= J.MAX then return end
	table.sort(all, function(a, b)
		local fa, fb = a.j.final ~= nil, b.j.final ~= nil
		if fa ~= fb then return fa end
		if a.j.at ~= b.j.at then return a.j.at < b.j.at end
		return a.key < b.key
	end)
	for i = 1, #all - J.MAX do s.list[all[i].key] = nil end
end

-- The King's judgments: not decided first (the nearest end of the vote first), then the newest.
function J.Judgments()
	J.Prune()
	local s, out = KingStore(false), {}
	for _, j in pairs(s and s.list or {}) do out[#out + 1] = j end
	table.sort(out, function(a, b)
		local fa, fb = a.final ~= nil, b.final ~= nil
		if fa ~= fb then return fb end
		if not fa and a.closes ~= b.closes then return a.closes < b.closes end
		if a.at ~= b.at then return a.at > b.at end
		return a.jid > b.jid
	end)
	return out
end

local function Find(jid)
	local s = KingStore(false)
	return s and s.list[tostring(jid)] or nil
end
J.Find = Find

-- A logged whisper the game sends only while it is still allowed: `check(target)` again then.
local function Whisper(target, msg, key, check)
	if not (ns.Comm and ns.Comm.Whisper) then return false end
	return ns.Comm.Whisper(target, msg, key, false, true, nil, {
		owner = OWNER, key = key,
		permit = function(_, _, dist, to)
			if dist ~= "WHISPER" or not check(to) then return false, "revoked" end
			return true
		end,
	})
end
local function AsKing() return IsKing() end
local function ToKing(to) return FromKing(to) end

local function Wire(...) return table.concat({ "MJ", tostring(J.PROTOCOL), ... }, "~") end

local function JudgmentWire(j, voter)
	local mine = j.votes[ns.FullName(voter)]
	return Wire("J", j.jid, math.max(0, math.floor(j.closes - Clock())), j.guild, j.target, CatsWire(j.cats),
		j.reporters, j.lines, j.finding or "-", type(mine) == "table" and mine.v or "-")
end

local function StandingWire(j)
	local up, down, n = Tally(j)
	local f = j.final
	if f then up, down, n = f.up or up, f.down or down, f.answered or n end
	return Wire("R", j.jid, State(j), f and f.v or "-", up, down, n, f and math.floor(f.at) or 0)
end

-- The open judgments to a councillor, at most SHOWN: those he has not voted on first (each the
-- nearest end first), then the end of the list with how many are open in all. (Not the SHOWN
-- nearest alone: past them a case reached no councillor while its vote lasted. His client forgets
-- only what a whole list leaves out, TakeEnd.)
local function SendOpen(to)
	local voter = ns.FullName(to)
	local waiting, voted = {}, {}
	for _, j in ipairs(J.Judgments()) do
		if State(j) == "O" then
			local list = type(j.votes[voter]) == "table" and voted or waiting
			list[#list + 1] = j
		end
	end
	local n = 0
	for _, list in ipairs({ waiting, voted }) do
		for _, j in ipairs(list) do
			if n >= J.SHOWN then break end
			n = n + 1
			Whisper(to, JudgmentWire(j, to), "judgment-j" .. j.jid .. "-" .. Key(to), AsKing)
		end
	end
	Whisper(to, Wire("N", n, #waiting + #voted), "judgment-n-" .. Key(to), AsKing)
	return n
end

-- Was `name` one of the officers who sent it?
local function SentBy(j, name)
	if Same(j.from, name) then return true end
	return type(j.also) == "table" and j.also[Key(name)] ~= nil
end

-- The King's client tells those who asked recently at once (the others when they next ask).
local function Recently(name) return heard[ns.FullName(name)] and ns.Now() - heard[ns.FullName(name)] <= J.HEARD end

-- A refusal goes back once a REFUSE_GAP to one sender at most, REFUSE_MINUTE in a minute in all,
-- and one waits at a time (its key is the sender's, not the case's: a newer one takes its place).
-- Anyone may whisper cases the King's client does not take: a refusal for each would fill its queue
-- (Comm's MAX_QUEUE) and push out its other sends, the Tabards' lease and the council's answers.
-- An officer's client sends a refused case again (J.RETRY) until it hears why.
local function Refuse(who, id, why)
	if who == ns.me then return false, why end
	local now = ns.Now()
	if now - (refused[who] or -math.huge) < J.REFUSE_GAP then return false, why end
	if now - refusals.at >= 60 then refusals.at, refusals.n = now, 0 end
	if refusals.n >= J.REFUSE_MINUTE then return false, why end
	-- (Session-only and bounded: those refused within the gap stay when there are many.)
	if not refused[who] and Count(refused) >= 200 then
		for name, t in pairs(refused) do if now - t >= J.REFUSE_GAP then refused[name] = nil end end
		if Count(refused) >= 200 then return false, why end
	end
	refused[who], refusals.n = now, refusals.n + 1
	Whisper(who, Wire("A", id, "-", why), "judgment-a-" .. Key(who) .. "-no", AsKing)
	return false, why
end

-- A case comes to the King's client: from an officer of an Olympus guild (as this client sees his
-- rank: its own roster for its guild, the census or the signed manifest for the others), on another
-- player. The same case again (a retry: its sender's id, guild and name) is the same judgment; the
-- same name from the same guild while it is open too. (The id alone is not the case: an officer's
-- count starts again in another guild's Watch, or once his saved variables are gone.)
local function TakeCase(sender, id, guild, target, cats, reporters, lines, finding)
	if not IsKing() then return false, "king" end
	local who = ns.FullName(sender)
	local rank = who ~= ns.me and ns.Data and ns.Data.AuthorizedRank and ns.Data.AuthorizedRank(who, guild) or nil
	if who ~= ns.me and not (type(rank) == "number" and rank <= (ns.CAPTAIN_RANK or 1)) then return Refuse(who, id, "rank") end
	if Same(target, who) or ns.IsKingCharacter(target) then return Refuse(who, id, "target") end
	local s = KingStore(true)
	if not s then return false, "store" end
	J.Prune()
	local now, open, today, fromGuild = Clock(), 0, 0, 0
	for _, j in pairs(s.list) do
		if Same(j.from, who) and j.id == id and Same(j.guild, guild) and Same(j.target, target) then
			if who ~= ns.me then Whisper(who, Wire("A", id, j.jid), "judgment-a-" .. Key(who) .. id, AsKing) end
			return true, j.jid, "again"
		end
		if not j.final and Same(j.guild, guild) and Same(j.target, target) then
			-- (Another officer of that guild: his own client asks how it stands too.)
			j.also = type(j.also) == "table" and j.also or {}
			if not j.also[Key(who)] and Count(j.also) < 10 then j.also[Key(who)] = who end
			if who ~= ns.me then Whisper(who, Wire("A", id, j.jid), "judgment-a-" .. Key(who) .. id, AsKing) end
			return true, j.jid, "open"
		end
		if not j.final then
			open = open + 1
			if Same(j.guild, guild) then fromGuild = fromGuild + 1 end
		end
		if Same(j.from, who) and now - j.at < 86400 then today = today + 1 end
	end
	if today >= J.DAY then return Refuse(who, id, "day") end
	if fromGuild >= J.MAX_OPEN_GUILD then return Refuse(who, id, "full") end
	if open >= J.MAX_OPEN then return Refuse(who, id, "full") end
	s.seq = s.seq + 1
	local j = { jid = s.seq, from = who, id = id, guild = guild, target = target, cats = cats, reporters = reporters,
		lines = lines, finding = (finding == "U" or finding == "D") and finding or nil, at = math.floor(now),
		closes = math.floor(now) + J.PERIOD, votes = {} }
	s.list[tostring(j.jid)] = j
	J.Prune()
	if who ~= ns.me then Whisper(who, Wire("A", id, j.jid), "judgment-a-" .. Key(who) .. id, AsKing) end
	-- (1.2.0, Konig's review: the King's chat may be on stream; the accused's name, a sender's text,
	-- shows only in The Watch.)
	ns.Print(Gold(L.JUDGMENT_IN_KING:format(guild)))
	if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	-- The councillors who asked lately hear of it now.
	for name in pairs(heard) do
		if Recently(name) and Councillor(name) then Whisper(name, JudgmentWire(j, name), "judgment-j" .. j.jid .. "-" .. Key(name), AsKing) end
	end
	ns.Fire("WATCH_CHANGED")
	return true, j.jid, "new"
end

local function TakeAsk(sender, ids)
	if not IsKing() then return false end
	local who = ns.FullName(sender)
	local now = ns.Now()
	-- (Session-only and bounded: the askers of the last HEARD stay when there are many.)
	if not heard[who] and Count(heard) >= 200 then
		for name, t in pairs(heard) do if now - t > J.HEARD then heard[name], answered[name] = nil, nil end end
		if Count(heard) >= 200 then return false, "busy" end
	end
	heard[who] = now
	if now - (answered[who] or -math.huge) < J.ASK_GAP then return false, "rate" end
	answered[who] = now
	if Councillor(who) then SendOpen(who) end
	local n = 0
	for jid in tostring(ids or ""):gmatch("(%d+)") do
		n = n + 1
		if n > 10 then break end
		local j = Find(tonumber(jid))
		if j and SentBy(j, who) then Whisper(who, StandingWire(j), "judgment-r" .. j.jid .. "-" .. Key(who), AsKing) end
	end
	return true
end

local function TakeVote(sender, jid, v)
	if not IsKing() then return false end
	local who = ns.FullName(sender)
	if not Councillor(who) then return false, "council" end
	if not Voting(who) then return false, "sanction" end
	heard[who] = ns.Now()
	local j = Find(jid)
	if not j then return false, "gone" end
	if State(j) ~= "O" then
		Whisper(who, Wire("K", jid, "X"), "judgment-k" .. jid .. "-" .. Key(who), AsKing)
		return false, "closed"
	end
	j.votes[who] = { v = v, at = math.floor(Clock()) }
	Whisper(who, Wire("K", jid, v), "judgment-k" .. jid .. "-" .. Key(who), AsKing)
	ns.Fire("WATCH_CHANGED")
	return true
end

-- The King's final word: upheld ("U") or not ("D"), once the vote is over (or every councillor
-- answered). Recorded with the council's count, and told to the officers who sent it when they are
-- on (the others at their next ask). It changes nothing else.
function J.Decide(jid, v)
	if not IsKing() then return false, "king" end
	if v ~= "U" and v ~= "D" then return false, "verdict" end
	local j = Find(jid)
	if not j then return false, "gone" end
	if j.final then return false, "decided" end
	if State(j) ~= "W" then return false, "open" end
	local up, down, n, size = Tally(j)
	j.final = { v = v, at = math.floor(Clock()), by = ns.me, up = up, down = down, answered = n, size = size }
	local names = { j.from }
	for _, name in pairs(type(j.also) == "table" and j.also or {}) do if type(name) == "string" then names[#names + 1] = name end end
	for _, name in ipairs(names) do
		if name ~= ns.me and Recently(name) then Whisper(name, StandingWire(j), "judgment-r" .. j.jid .. "-" .. Key(name), AsKing) end
	end
	-- The King's own guild's case: on this client already.
	J.TakeStanding(ns.me, j.jid, "F", v, up, down, n, j.final.at)
	ns.Fire("WATCH_CHANGED")
	return true
end

---------------------------------------------------------------------------
-- The officer's client: the cases it sent (in The Watch's own store for this guild)
---------------------------------------------------------------------------

local function OfficerStore(create)
	local W = Watch()
	local s, guild
	if W and W.Store then s, guild = W.Store(create) end
	if not s then return nil end
	if type(s.escalations) ~= "table" then
		if not create then return nil end
		s.escalations = {}
	end
	s.judgmentSeq = math.max(0, math.floor(tonumber(s.judgmentSeq) or 0))
	return s, guild
end

-- The case `key` (The Watch's name key) as this client sent it, or nil.
function J.Escalation(key)
	local s = OfficerStore(false)
	local e = s and s.escalations[key]
	return type(e) == "table" and e or nil
end

local function EscalationWire(e)
	return Wire("E", e.id, e.guild, e.target, CatsWire(e.cats), e.reporters, e.lines, e.finding or "-")
end

local function SendCase(e)
	e.sentAt = ns.Now()
	if IsKing() then
		-- The King's own guild: into his own judgments.
		local ok, jid, why = TakeCase(ns.me, e.id, e.guild, e.target, e.cats, e.reporters, e.lines, e.finding)
		if ok then e.jid, e.state = jid, e.state or "O" else e.refused = why end
		return ok
	end
	local c = Collector()
	if not c then return false end
	local W = Watch()
	return Whisper(c.name, EscalationWire(e), "judgment-e" .. e.id, function(to)
		return ToKing(to) and W ~= nil and W.CanManage() == true
	end)
end

-- Sends the case on `name` (The Watch's) to the King: this guild's officers alone, once at a time.
-- True and "sent" or "held" (his client is not on: it goes once it is), or false and why.
function J.Escalate(name)
	local W = Watch()
	if not (W and W.CanManage and W.CanManage()) then return false, "access" end
	local key = Key(name)
	local c = W.Case(key)
	if not c then return false, "case" end
	local old = J.Escalation(key)
	if old and not old.refused and old.state ~= "F" then return false, "already" end
	local s, guild = OfficerStore(true)
	guild = guild or (W.OwnGuild and W.OwnGuild())
	if not s or not guild then return false, "guild" end
	if not old and Count(s.escalations) >= J.ESCALATIONS_MAX then
		-- The oldest one decided (or refused) goes; with none, no new one.
		local oldest, at
		for k, e in pairs(s.escalations) do
			local done = type(e) ~= "table" or e.state == "F" or e.refused ~= nil
			local when = type(e) == "table" and tonumber(e.at) or 0
			if done and (not at or when < at) then oldest, at = k, when end
		end
		if not oldest then return false, "full" end
		s.escalations[oldest] = nil
	end
	s.judgmentSeq = s.judgmentSeq + 1
	local f = c.finding and c.finding.verdict
	local e = { id = s.judgmentSeq, key = key, target = c.target, guild = guild, by = ns.me, at = math.floor(Clock()),
		cats = c.cats, reporters = c.reporters, lines = c.lines, finding = f == "up" and "U" or f == "down" and "D" or nil }
	s.escalations[key] = e
	s.revision = (tonumber(s.revision) or 0) + 1
	local sent = SendCase(e)
	ns.Fire("WATCH_CHANGED")
	return true, sent and "sent" or "held"
end

local function TakeReceipt(sender, id, jid, why)
	if not FromKing(sender) then return false, "sender" end
	local s = OfficerStore(false)
	for _, e in pairs(s and s.escalations or {}) do
		if type(e) == "table" and e.id == id and not e.jid then
			if jid then e.jid, e.state, e.receivedAt = jid, "O", math.floor(Clock())
			else e.refused = why or "?" end
			ns.Fire("WATCH_CHANGED")
			return true
		end
	end
	return false, "unknown"
end

-- How a case stands, from the King's client (or this one's, the King's own guild's).
function J.TakeStanding(sender, jid, state, v, up, down, n, at)
	if sender ~= ns.me and not FromKing(sender) then return false, "sender" end
	local s = OfficerStore(false)
	for _, e in pairs(s and s.escalations or {}) do
		if type(e) == "table" and e.jid == jid then
			local was = e.state
			e.state, e.verdict, e.up, e.down, e.answered = state, v ~= "-" and v or nil, up, down, n
			if state == "F" then e.decidedAt = at end
			if state == "F" and was ~= "F" and sender ~= ns.me then
				ns.Print(Gold(L.JUDGMENT_ESC_TOLD:format(ns.DisplayName(e.target) or e.target, VerdictText(v))))
				if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
			end
			-- 1.1.6: the player is told the decision in a pop-up, over GUILD from
			-- this client (WatchChat.TellCase, repeated while he may be away).
			local WC = ns.WatchChat
			if state == "F" and was ~= "F" and (v == "U" or v == "D") and WC and WC.TellCase then WC.TellCase(e.target, e.jid, v) end
			ns.Fire("WATCH_CHANGED")
			return true
		end
	end
	return false, "unknown"
end

---------------------------------------------------------------------------
-- A councillor's client: the open judgments, as the King's client tells them (this session's)
---------------------------------------------------------------------------

local function TakeOpen(sender, jid, left, guild, target, cats, reporters, lines, finding, mine)
	if not FromKing(sender) or not Councillor(ns.me) then return false, "sender" end
	local was = incoming[jid]
	incoming[jid] = { jid = jid, closesAt = ns.Now() + left, guild = guild, target = target, cats = cats, reporters = reporters,
		lines = lines, finding = (finding == "U" or finding == "D") and finding or nil, mine = (mine == "U" or mine == "D") and mine or nil,
		pending = was and was.pending or nil }
	if not told[jid] and not incoming[jid].mine then
		told[jid] = true
		ns.Print(Gold(L.JUDGMENT_IN_COUNCIL:format(ns.DisplayName(target) or target)))
		if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	end
	ns.Fire("WATCH_CHANGED")
	return true
end

-- The end of the King's list: when it named every open one, what it no longer names is closed
-- (with more open than one list holds, those it left out stay until they end, or the King's
-- client says their vote is closed).
local function TakeEnd(sender, shown, open)
	if not FromKing(sender) or not Councillor(ns.me) then return false end
	listed = { shown = shown, open = open }
	if shown >= open then
		for jid, e in pairs(incoming) do if e.stale then incoming[jid] = nil end end
	end
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeCounted(sender, jid, v)
	if not FromKing(sender) then return false end
	local e = incoming[jid]
	if not e then return false end
	e.pending = nil
	if v == "X" then
		incoming[jid] = nil
		ns.Print(L.JUDGMENT_VOTE_CLOSED:format(ns.DisplayName(e.target) or e.target))
	else
		e.mine = v
		ns.Print(L.JUDGMENT_VOTED:format(ns.DisplayName(e.target) or e.target, VerdictText(v)))
	end
	ns.Fire("WATCH_CHANGED")
	return true
end

-- The open judgments this councillor's client was told of, the nearest end first.
function J.Open()
	local now, out = ns.Now(), {}
	for jid, e in pairs(incoming) do
		if e.closesAt <= now then incoming[jid] = nil else out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		if a.closesAt ~= b.closesAt then return a.closesAt < b.closesAt end
		return a.jid < b.jid
	end)
	return out
end

-- A councillor's vote: upheld ("U") or not ("D"), to the King's client (on now), his newest counting.
function J.Vote(jid, v)
	if not Councillor(ns.me) then return false, "council" end
	if not Voting(ns.me) then return false, "sanction" end
	if v ~= "U" and v ~= "D" then return false, "verdict" end
	local e = incoming[jid]
	if not e or e.closesAt <= ns.Now() then return false, "closed" end
	local c = Collector()
	if not c then return false, "away" end
	e.pending = v
	Whisper(c.name, Wire("V", jid, v), "judgment-v" .. jid, function(to) return ToKing(to) and Voting(ns.me) end)
	ns.Fire("WATCH_CHANGED")
	return true
end

---------------------------------------------------------------------------
-- Asking the King's client: what is open (a councillor), how this client's cases stand (an officer)
---------------------------------------------------------------------------

local function Waiting()
	local s, jids, unsent = OfficerStore(false), {}, {}
	for _, e in pairs(s and s.escalations or {}) do
		if type(e) == "table" and not e.refused then
			if not e.jid then unsent[#unsent + 1] = e
			elseif e.state ~= "F" then jids[#jids + 1] = e.jid end
		end
	end
	table.sort(jids)
	table.sort(unsent, function(a, b) return a.id < b.id end)
	return jids, unsent
end

-- Every minute: the cases the King's client has not confirmed (at once when it comes on), and the
-- ask, at most every QUERY_EVERY. When it comes on, each client's first ask waits a moment of its
-- own within SPREAD, so the askers' answers do not all fill its queue in the same minute (nor
-- again each QUERY_EVERY after). It comes on: another name than the last tick's, or none then (its
-- lease's id is new at every announcement, every 8 minutes, and says nothing). force: now (the
-- page's own Ask again).
function J.Tick(force)
	if IsKing() then return false end
	local c = Collector()
	if not c then lease = nil return false end
	local fresh = not Same(lease, c.name)
	lease = c.name
	local now = ns.Now()
	local jids, unsent = Waiting()
	local W = Watch()
	if W and W.CanManage and W.CanManage() then
		for _, e in ipairs(unsent) do
			if fresh or force or now - (e.sentAt or -math.huge) >= J.RETRY then SendCase(e) end
		end
	end
	local council = Councillor(ns.me)
	if not council and #jids == 0 then return false end
	if fresh then lastAsk = now - J.QUERY_EVERY + J.random(0, J.SPREAD) end
	if not (force or now - lastAsk >= J.QUERY_EVERY) then return false end
	lastAsk = now
	if council then for _, e in pairs(incoming) do e.stale = true end end
	local list = {}
	for i = 1, math.min(10, #jids) do list[i] = tostring(jids[i]) end
	Whisper(c.name, Wire("Q", table.concat(list, ",")), "judgment-q", ToKing)
	return true
end

---------------------------------------------------------------------------
-- The messages
---------------------------------------------------------------------------

function J.Handle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or type(sender) ~= "string" then return false, "shape" end
	local version, kind, rest = text:match("^MJ~(%d+)~(%u)~?(.*)$")
	if tonumber(version) ~= J.PROTOCOL then return false, "version" end
	local f = {}
	for part in (rest .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	if kind == "E" then
		local id, guild, target = Num(f[1], 1, 2147483647), Field(f[2], 72), Field(f[3], 72)
		local cats, reporters, lines = CatsRead(f[4]), Num(f[5], 0, 999), Num(f[6], 0, 9999)
		local finding = f[7]
		if #f ~= 7 or not (id and guild and ns.IsFederation(guild) and target and cats and reporters and lines) then return false, "malformed" end
		if finding ~= "U" and finding ~= "D" and finding ~= "-" then return false, "malformed" end
		return TakeCase(sender, id, guild, ns.FullName(target), cats, reporters, lines, finding)
	elseif kind == "A" then
		local id = Num(f[1], 1, 2147483647)
		if not id then return false, "malformed" end
		if f[2] == "-" then return TakeReceipt(sender, id, nil, Field(f[3], 16) or "?") end
		local jid = Num(f[2], 1, 2147483647)
		if not jid then return false, "malformed" end
		return TakeReceipt(sender, id, jid)
	elseif kind == "Q" then
		if #f > 1 or (f[1] and #f[1] > 120) then return false, "malformed" end
		return TakeAsk(sender, f[1])
	elseif kind == "J" then
		local jid, left, guild, target = Num(f[1], 1, 2147483647), Num(f[2], 0, J.PERIOD), Field(f[3], 72), Field(f[4], 72)
		local cats, reporters, lines = CatsRead(f[5]), Num(f[6], 0, 999), Num(f[7], 0, 9999)
		if #f ~= 9 or not (jid and left and guild and target and cats and reporters and lines) then return false, "malformed" end
		return TakeOpen(sender, jid, left, guild, target, cats, reporters, lines, f[8], f[9])
	elseif kind == "N" then
		local shown, open = Num(f[1], 0, J.SHOWN), Num(f[2], 0, J.MAX)
		if #f ~= 2 or not (shown and open) or shown > open then return false, "malformed" end
		return TakeEnd(sender, shown, open)
	elseif kind == "V" then
		local jid = Num(f[1], 1, 2147483647)
		if #f ~= 2 or not jid or (f[2] ~= "U" and f[2] ~= "D") then return false, "malformed" end
		return TakeVote(sender, jid, f[2])
	elseif kind == "K" then
		local jid = Num(f[1], 1, 2147483647)
		if #f ~= 2 or not jid or (f[2] ~= "U" and f[2] ~= "D" and f[2] ~= "X") then return false, "malformed" end
		return TakeCounted(sender, jid, f[2])
	elseif kind == "R" then
		local jid, up, down, n, at = Num(f[1], 1, 2147483647), Num(f[4], 0, 999), Num(f[5], 0, 999), Num(f[6], 0, 999), Num(f[7], 0, 4294967295)
		local state, v = f[2], f[3]
		if #f ~= 7 or not (jid and up and down and n and at) or (state ~= "O" and state ~= "W" and state ~= "F")
			or (v ~= "U" and v ~= "D" and v ~= "-") or (state == "F" and v == "-") then return false, "malformed" end
		return J.TakeStanding(sender, jid, state, v, up, down, n, at)
	end
	return false, "kind"
end

---------------------------------------------------------------------------
-- The pages: The Watch's Judgments (the King's, the council's) and the case page's lines
---------------------------------------------------------------------------

-- (1.2.0: on the King's stream, no reporters' count, which alts could inflate; and the accused
-- named only once the King upheld the case, Watch.Accused.)
local function OnStream() return ns.CouncilMasked ~= nil and ns.CouncilMasked() == true end
local function AboutText(e)
	if OnStream() then return L.JUDGMENT_ABOUT_STREAM:format(CatsText(e.cats), tonumber(e.lines) or 0) end
	return L.JUDGMENT_ABOUT:format(CatsText(e.cats), tonumber(e.reporters) or 0, tonumber(e.lines) or 0)
end
local function Accused(j)
	local shown = ns.DisplayName(j.target) or j.target
	if OnStream() and not (type(j.final) == "table" and j.final.v == "U") then return ns.MaskName(shown) end
	return shown
end

local function CouncilText(up, down, n, size)
	local m = J.Majority(up, down)
	local verdict = m == "U" and L.JUDGMENT_MAJORITY_UP or m == "D" and L.JUDGMENT_MAJORITY_DOWN or L.JUDGMENT_MAJORITY_NONE
	return L.JUDGMENT_COUNCIL:format(up, down, n, size) .. " · " .. verdict
end

-- A judgment as plain text, for the copy box (the King's record): who sent it, the council's
-- votes and his word, each with its time.
function J.Text(j)
	if type(j) ~= "table" then return "" end
	local up, down, n, size = Tally(j)
	local out = { L.WATCH_CASE_TITLE:format(Accused(j)) .. "  <" .. j.guild .. ">",
		AboutText(j),
		L.JUDGMENT_SENT_BY:format(ShownBy(j.from), j.guild, Stamp(j.at)),
		L.JUDGMENT_THEIR_FINDING:format(VerdictText(j.finding)),
		L.JUDGMENT_PERIOD:format(Stamp(j.at), Stamp(j.closes)),
		CouncilText(up, down, n, size), "" }
	local voters = {}
	for voter, vote in pairs(j.votes) do voters[#voters + 1] = { name = voter, v = vote.v, at = vote.at } end
	table.sort(voters, function(a, b) return (a.at or 0) < (b.at or 0) end)
	for _, x in ipairs(voters) do
		out[#out + 1] = ("%s · %s · %s"):format(Stamp(x.at or 0), ShownBy(x.name), VerdictText(x.v))
	end
	if j.final then
		out[#out + 1] = ""
		out[#out + 1] = L.JUDGMENT_FINAL:format(VerdictText(j.final.v), Stamp(j.final.at), j.final.up or 0, j.final.down or 0, j.final.answered or 0)
	end
	return table.concat(out, "\n")
end

local function KingRows(lines)
	local list = J.Judgments()
	local king = IsKing()
	lines[#lines + 1] = { header = true, text = L.JUDGMENT_TITLE, right = Grey(tostring(#list)),
		tooltip = function(tt) tt:AddLine(L.JUDGMENT_TITLE, 1, 0.82, 0); tt:AddLine(L.JUDGMENT_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_SCOPE_KING), gapAfter = #list == 0 }
	if #list == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_EMPTY), gapAfter = true } return end
	for _, j in ipairs(list) do
		local state = State(j)
		local up, down, n, size = Tally(j)
		local right = state == "F" and VerdictColored(j.final.v) or state == "W" and Gold(L.JUDGMENT_STATE_WAIT)
			or Grey(L.JUDGMENT_STATE_OPEN:format(Span(j.closes - Clock())))
		local name = Accused(j)
		lines[#lines + 1] = { indent = 1, text = Gold(name) .. "  " .. Grey("<" .. j.guild .. ">"), right = right }
		lines[#lines + 1] = { indent = 2, text = AboutText(j) }
		lines[#lines + 1] = { indent = 2, text = Grey(L.JUDGMENT_SENT_BY:format(ShownBy(j.from), j.guild, ns.Ago(j.at)))
			.. "  " .. Grey(L.JUDGMENT_THEIR_FINDING:format(VerdictText(j.finding))) }
		local f = j.final
		lines[#lines + 1] = { indent = 2,
			text = f and CouncilText(f.up or 0, f.down or 0, f.answered or 0, f.size or size) or CouncilText(up, down, n, size),
			tooltip = function(tt)
				tt:AddLine(L.JUDGMENT_VOTES_TIP, 1, 0.82, 0, true)
				for voter, vote in pairs(j.votes) do
					tt:AddLine(ShownBy(voter) .. "  " .. VerdictText(vote.v) .. "  " .. Grey(Stamp(vote.at or 0)), 1, 1, 1)
				end
			end }
		if f then
			lines[#lines + 1] = { indent = 2, text = L.JUDGMENT_FINAL_LINE:format(VerdictColored(f.v), ns.Ago(f.at)) }
		elseif state == "W" and king then
			for _, v in ipairs({ "U", "D" }) do
				local verdict = v
				lines[#lines + 1] = { indent = 2, text = Gold(v == "U" and L.JUDGMENT_FINAL_UP_BTN or L.JUDGMENT_FINAL_DOWN_BTN),
					onClick = function() ns.ShowDialog("OLYMPUS_JUDGMENT_FINAL", name, VerdictText(verdict), { jid = j.jid, v = verdict }) end }
			end
		elseif state == "O" then
			lines[#lines + 1] = { indent = 2, text = Grey(L.JUDGMENT_FINAL_WAIT:format(Span(j.closes - Clock()))) }
		else
			lines[#lines + 1] = { indent = 2, text = Grey(L.JUDGMENT_ONLY_KING) }
		end
		lines[#lines + 1] = { indent = 2, text = Gold(L.JUDGMENT_COPY), gapAfter = true, onClick = function()
			if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(L.WATCH_CASE_TITLE:format(name), J.Text(j), nil, { key = "judgment" }) end
		end }
	end
end

local function CouncilRows(lines)
	local list = J.Open()
	local king = Collector()
	lines[#lines + 1] = { header = true, text = L.JUDGMENT_COUNCIL_TITLE, right = Grey(tostring(#list)),
		tooltip = function(tt) tt:AddLine(L.JUDGMENT_COUNCIL_TITLE, 1, 0.82, 0); tt:AddLine(L.JUDGMENT_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_SCOPE_COUNCIL) }
	if not king then lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_KING_AWAY) } end
	if #list == 0 then
		lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_EMPTY_COUNCIL), gapAfter = true }
	end
	for _, e in ipairs(list) do
		local name = Accused(e)
		lines[#lines + 1] = { indent = 1, text = Gold(name) .. "  " .. Grey("<" .. e.guild .. ">"),
			right = Grey(L.JUDGMENT_LEFT:format(Span(e.closesAt - ns.Now()))) }
		lines[#lines + 1] = { indent = 2, text = AboutText(e) .. "  " .. Grey(L.JUDGMENT_THEIR_FINDING:format(VerdictText(e.finding))) }
		lines[#lines + 1] = { indent = 2, text = e.pending and Grey(L.JUDGMENT_VOTE_SENDING:format(VerdictText(e.pending)))
			or L.JUDGMENT_YOUR_VOTE:format(e.mine and VerdictColored(e.mine) or Grey(L.JUDGMENT_NONE)) }
		for _, v in ipairs({ "U", "D" }) do
			local verdict = v
			local label = v == "U" and L.JUDGMENT_VOTE_UP_BTN or L.JUDGMENT_VOTE_DOWN_BTN
			lines[#lines + 1] = { indent = 2, text = king and Gold(label) or Grey(label), gapAfter = v == "D",
				onClick = king and function()
					local ok, why = J.Vote(e.jid, verdict)
					if not ok then ns.Print(L.JUDGMENT_NOT_SENT:format(Why(why))) end
				end or nil }
		end
	end
	-- More open than one list holds: they come once he voted on these (or one ends).
	if listed and listed.open > listed.shown then lines[#lines + 1] = { indent = 1, text = Grey(L.JUDGMENT_MORE:format(listed.open - listed.shown)) } end
	lines[#lines + 1] = { indent = 1, text = king and Gold(L.JUDGMENT_ASK) or Grey(L.JUDGMENT_ASK), gapAfter = true,
		onClick = king and function() J.Tick(true) end or nil }
end

-- How many wait here (The Watch's navigation): the King's not decided yet, and the open ones a
-- councillor has not voted on.
function J.Count()
	local n = 0
	if J.KingSide() then for _, j in ipairs(J.Judgments()) do if not j.final then n = n + 1 end end end
	if J.CouncilSide() then for _, e in ipairs(J.Open()) do if not e.mine then n = n + 1 end end end
	return n
end

-- The Watch's Judgments section.
function J.Lines()
	local lines = {}
	local V = ViewAs()
	local mine = V and V.Role() == "my"
	if J.KingSide() or mine then KingRows(lines) end
	if J.CouncilSide() or mine then CouncilRows(lines) end
	return lines
end

-- The case page's lines (Watch.lua): how this client's sending of it stands.
function J.CaseLines(c)
	local e = type(c) == "table" and J.Escalation(c.key)
	if not e then return {} end
	local text
	if e.refused then text = Red(L.JUDGMENT_ESC_REFUSED:format(Why(e.refused)))
	elseif e.state == "F" then
		text = L.JUDGMENT_ESC_FINAL:format(VerdictColored(e.verdict), ns.Ago(e.decidedAt or 0), e.up or 0, e.down or 0, e.answered or 0)
	elseif e.state == "W" then text = Gold(L.JUDGMENT_ESC_WAIT)
	elseif e.jid then text = L.JUDGMENT_ESC_OPEN
	elseif e.sentAt and Collector() then text = Grey(L.JUDGMENT_ESC_SENT)
	else text = Grey(L.JUDGMENT_ESC_HELD) end
	return {
		{ indent = 1, text = Grey(L.JUDGMENT_ESC_BY:format(ShownBy(e.by), ns.Ago(e.at))) },
		{ indent = 1, text = text, tooltip = function(tt) tt:AddLine(L.JUDGMENT_TITLE, 1, 0.82, 0); tt:AddLine(L.JUDGMENT_TIP, 1, 1, 1, true) end },
	}
end

-- Its action (Watch.lua's case page, an officer's): send it to the King, once at a time.
function J.ActionLines(c)
	local W = Watch()
	if type(c) ~= "table" or not (W and W.CanManage and W.CanManage()) then return {} end
	local e = J.Escalation(c.key)
	if e and not e.refused and e.state ~= "F" then return {} end
	local name = ns.DisplayName(c.target) or c.target
	return { { indent = 1, text = Gold(e and L.JUDGMENT_ESCALATE_AGAIN or L.JUDGMENT_ESCALATE_BTN),
		onClick = function() ns.ShowDialog("OLYMPUS_JUDGMENT_ESCALATE", name, nil, c.target) end,
		tooltip = function(tt) tt:AddLine(L.JUDGMENT_ESCALATE_BTN, 1, 0.82, 0); tt:AddLine(L.JUDGMENT_ESCALATE_TIP, 1, 1, 1, true) end } }
end

StaticPopupDialogs["OLYMPUS_JUDGMENT_ESCALATE"] = {
	text = L.JUDGMENT_ESCALATE_CONFIRM,
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(self, data)
		local name = data or (self and self.data)
		local ok, how = J.Escalate(name)
		if not ok then return ns.Print(L.JUDGMENT_NOT_SENT:format(Why(how))) end
		ns.Print(how == "held" and L.JUDGMENT_ESC_PRINT_HELD or L.JUDGMENT_ESC_PRINT_SENT)
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_JUDGMENT_FINAL"] = {
	text = L.JUDGMENT_FINAL_CONFIRM,
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) ~= "table" then return end
		local ok, why = J.Decide(data.jid, data.v)
		if not ok then return ns.Print(L.JUDGMENT_NOT_SENT:format(Why(why))) end
		local j = Find(data.jid)
		ns.Print(L.JUDGMENT_FINAL_DONE:format(j and (ns.DisplayName(j.target) or j.target) or "?", VerdictText(data.v)))
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function J.ResetForTests()
	wipe(heard); wipe(answered); wipe(incoming); wipe(told); wipe(refused)
	refusals.at, refusals.n = -math.huge, 0
	lease, lastAsk, listed = nil, -math.huge, nil
end

if ns.Comm and ns.Comm.Handle then
	ns.Comm.Handle("MJ", function(dist, sender, text) return J.Handle(dist, sender, text) end)
end

ns.On("LOGIN", function()
	J.Prune()
	J.after(40, "judgment login", function() J.Tick(false) end)
	if ns.Every then ns.Every(60, "judgment", function() J.Tick(false) end) end
end)
