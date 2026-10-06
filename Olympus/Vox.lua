local ADDON, ns = ...
local L = ns.L

-- Vox Populi: the King (or one of his Hands) asks the army a question with two to six
-- answers, to pick one or to pick several. Every Olympus member with the addon gets a window
-- with the answers and a countdown; each vote goes to whoever asked, alone (Y1), and when
-- time is up the results go to everyone (T1~E): a bar chart in the window, a line in chat.
-- The asker's Vox Populi tab counts the votes as they come, and the same chart can go on his
-- screen (on stream) while they do. His last questions stay on that tab, with their results,
-- across sessions (1.1.6).
-- 1.1.6: the asker picks who a question is for (Vox.AUDIENCES): the whole army, the High
-- Council or the guild masters (the King's, his Steward's or a Hand's), or his own guild (a guild
-- master's, Y3). Both ends check it: a client opens the window only when its own character is
-- in that audience, and the asker counts a vote only from someone he can place in it.
--   T1~V~<id>~<guild>~<seconds>~<1|M>~<question>~<answer 1>~...~<answer n>   (n = 2 to 6)
--   T1~V~<id>~<guild>~<H|M>~<seconds>~<1|M>~<question>~<answer 1>~...   (1.1.6: an audience)
--   T1~E~<id>~<guild>~<voters>~<votes for 1>~...~<votes for n>
--   Y1~<id>~<the answers picked, e.g. 2 or 136>~<guild>       (whisper to the asker)
--   Y3~V~<id>~<seconds>~<1|M>~<question>~<answer 1>~...   (1.1.6: a guild master to his guild, GUILD)
--   Y3~E~<id>~<voters>~<votes for 1>~...~<votes for n>    (its results, GUILD)

local Vox = {}
ns.Vox = Vox

Vox.DEFAULT = 90        -- seconds a question stays open
Vox.MIN, Vox.MAX = 30, 300
Vox.TIMES = { 30, 60, 90, 120, 300 }  -- the composer's choices
Vox.GAP = 60            -- one new question a minute at most (the asker's)
Vox.SHOW_GAP = 45       -- a new window a little sooner on the receiving side (queues, rounding)
Vox.GRACE = 5           -- votes still counted this long after the end (on their way)
Vox.MAX_VOTES = 5000
Vox.MAX_HISTORY = 30
Vox.MAX_ANSWERS = 6
Vox.MAX_Q, Vox.MAX_A = 90, 20
Vox.RESULTS_SHOWN = 30  -- a voter's window shows the results this long, then closes

-- Swappable in tests.
Vox.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

-- Who a question is for (1.1.6), each one checked on both ends:
--   E the whole army: every Olympus member with the addon (the questions before 1.1.6)
--   H the High Council: the author's signed list (ns.IsHighCouncillor)
--   M the guild masters of the Olympus guilds: rank 0, the server's roster for our own guild,
--     the census or the signed manifest for the others (Data.AuthorizedRank)
--   G the asker's own guild: a guild master's question to his members, over GUILD (Y3), which
--     the server carries between the members of one guild alone
-- (Not the writs' letters, Acts.lua: there L is the Lords and C the Lords and Captains.)
-- An audience is who the addon shows the question to and whose vote it counts: like everything
-- on the channel (or in the guild), the question's bytes reach every addon there. Clients
-- before 1.1.6 read the seconds first, find a letter, and show H and M to nobody.
Vox.AUDIENCES = { "E", "H", "M", "G" }
local KNOWN = { E = true, H = true, M = true, G = true }
local THRONE_TO = { H = true, M = true } -- (the letters a T1~V may carry; any other: no window)

local poll          -- the asker's open question: { id, q, answers, multi, to, t, at, votes = { [sender] = picks }, counts, voters, others }
local shown         -- the question on this client's window: { id, asker, q, answers, multi, to, guild, at, byKing, picks, voted, counts, voters }
local previewed = {} -- the author's preview's questions (King.Preview): this session alone, never saved
local frame         -- the window (made on the first question): a voter's, or the asker's chart (frame.live)
local composer      -- the asker's "new question" window
local lastSent = -math.huge
local lastShownBy = {}  -- [asker] = when their last question was shown here (SHOW_GAP each)
local changePending = false

local function Changed()
	if changePending then return end
	changePending = true
	Vox.after(1, "vox changed", function()
		changePending = false
		ns.Fire("VOX_CHANGED")
		if frame and frame.live and frame:IsShown() then Vox.Refresh() end
	end)
end

local function Plain(s, n)
	s = tostring(s or ""):gsub("[~|%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, n)
end

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end

local function AudienceText(to) return KNOWN[to] and L["VOX_TO_" .. to] or L.VOX_TO_E end

-- The guild master of an Olympus guild (rank 0: the server's word): he asks his own guild (G).
function Vox.GuildMaster() return ns.IsMember() and ns.Roster.MyRank() == 0 end

-- Is this client's own character in that audience? (The receiving end's check.)
function Vox.InAudience(to)
	if to == "H" then return ns.IsHighCouncillor(ns.me) end
	if to == "M" then return Vox.GuildMaster() end
	if to == "G" then return ns.IsMember() end
	return to == "E"
end

-- May this character ask that audience? The King, his Steward or a Hand the army, the council
-- and the guild masters (the Throne's tools); a guild master his own guild.
function Vox.MayAsk(to)
	if to == "G" then return Vox.GuildMaster() end
	return (to == "E" or THRONE_TO[to] == true) and ns.King.CanCommand() or false
end

-- The audiences this character may pick, in the composer's order (the author's preview: all).
function Vox.Audiences()
	local out, preview = {}, ns.King.Preview()
	for _, to in ipairs(Vox.AUDIENCES) do
		if preview or Vox.MayAsk(to) then out[#out + 1] = to end
	end
	return out
end

---------------------------------------------------------------------------
-- The asker's history (1.1.6): kept across sessions
---------------------------------------------------------------------------

-- Each asker's questions, newest last, at most MAX_HISTORY, in the account's saved variables
-- under his character's name ("name-realm"), as his chat windows are: the question, its answers,
-- who it was for, the counts and when. Never in the realm group's store: a realm link merges two
-- stores into one (Core.lua's OpenStore) and keeps one side's value of a key it does not know,
-- so one realm's askers would lose their lists (1.1.6 review). Never who voted: the names stay
-- with the open question alone (poll.votes), and go with it. (The author's preview keeps its own
-- apart, for the session: previewed.)
local checked = setmetatable({}, { __mode = "k" }) -- the saved lists read back this session

local function Count(n) return math.max(0, math.min(Vox.MAX_VOTES, math.floor(tonumber(n) or 0))) end

-- One saved question checked again (the SavedVariables can be edited), or nil.
local function Kept(h)
	if type(h) ~= "table" or type(h.q) ~= "string" or type(h.answers) ~= "table" or type(h.counts) ~= "table" then return nil end
	local q, answers, counts = Plain(h.q, Vox.MAX_Q), {}, {}
	for i = 1, math.min(#h.answers, Vox.MAX_ANSWERS) do
		local a = type(h.answers[i]) == "string" and Plain(h.answers[i], Vox.MAX_A) or ""
		if a == "" then return nil end
		answers[i], counts[i] = a, Count(h.counts[i])
	end
	if #answers < 2 or #q < 3 then return nil end
	return { q = q, answers = answers, multi = h.multi == true, to = KNOWN[h.to] and h.to or "E", counts = counts,
		voters = Count(h.voters), others = Count(h.others), t = math.max(0, math.floor(tonumber(h.t) or 0)) }
end

-- This character's list (create: made when missing), checked once a session.
local function History(create)
	local db, me = ns.db, ns.me and ns.FullName(ns.me)
	if type(db) ~= "table" or not me then return {} end
	if type(db.voxHistory) ~= "table" then
		if not create then return {} end
		db.voxHistory = {}
	end
	local list = db.voxHistory[me]
	if type(list) ~= "table" then
		if not create then return {} end
		list = {}
		db.voxHistory[me] = list
	end
	if not checked[list] then
		checked[list] = true
		-- From the newest end (the entries ipairs would walk), until MAX_HISTORY good ones: an
		-- edited file can hold any number, and the older ones are never opened (1.1.6 review).
		local n, good = 0, {}
		while list[n + 1] ~= nil do n = n + 1 end
		for i = n, 1, -1 do
			if #good >= Vox.MAX_HISTORY then break end
			good[#good + 1] = Kept(list[i])
		end
		wipe(list)
		for i = 1, #good do list[i] = good[#good + 1 - i] end
	end
	return list
end

-- The list the tab, the chart and the Discord copy read: the author's preview's while it is on.
local function List() return ns.King.Preview() and previewed or History() end

-- When it was asked: "5 min ago" the first day, its date after.
local function When(t)
	if not t or t == 0 or ns.Now() - t < 86400 or not date then return ns.Ago(t) end
	return date("%Y-%m-%d", t)
end

-- Whose vote counts in the results: our own guild's members (the server's roster), or a
-- guild of the census, fresh and undisputed, and never more voters from it than it has
-- players online. Anyone else's vote (nothing stops a stranger from whispering one) is only
-- counted apart.
local placed = {}   -- [guild] = { online, votes } for the question open, refreshed each minute
local placedAt = -math.huge
local function Placed(sender, guild)
	local mine = GetGuildInfo("player")
	if ns.Roster.RankOf(sender) then return true end
	if mine and guild == mine then return false end -- says our guild, not in our roster
	local now = ns.Now()
	if now - placedAt > 60 then
		local fresh = {}
		for _, e in ipairs(ns.Data.Summary().guilds) do
			if e.fresh and not e.g.conflict then
				fresh[e.name] = { online = e.g.online or 0, votes = placed[e.name] and placed[e.name].votes or 0 }
			end
		end
		placed, placedAt = fresh, now
	end
	local g = placed[guild]
	if not g or g.votes >= math.max(g.online, 1) then return false end
	g.votes = g.votes + 1
	return true
end

-- 1.1.6: the asker's end of the audience, whatever the voter's client showed. The council: a
-- name of the signed list (the server sets the sender's). The guild masters: rank 0 of the guild
-- the vote names, as the roster, the census or the signed manifest place him (a claim alone
-- places nobody). Our own guild: a member of our roster who says our guild. The army: Placed.
-- (The author's preview counts his own vote, whatever its audience: nothing went out.)
local function Counts(p, sender, guild)
	if p.preview and sender == ns.me then return true end
	if p.to == "H" then return ns.IsHighCouncillor(sender) end
	if p.to == "M" then return ns.Data.AuthorizedRank(sender, guild) == 0 end
	if p.to == "G" then return ns.Roster.RankOf(sender) ~= nil and guild == GetGuildInfo("player") end
	return sender == ns.me or Placed(sender, guild)
end

-- Which open question gives way to another (1.1.6): the King's comes first, then the Throne's
-- (a Hand's, a Steward's), then a guild master's to his guild (the King's to his own among them).
local function Weight(byKing, to)
	if to == "G" then return 1 end
	return byKing and 3 or 2
end

---------------------------------------------------------------------------
-- The results
---------------------------------------------------------------------------

-- Each answer's share, as the chart shows it: of the votes when there is one pick each
-- (whole percents that add up to exactly 100: the points left over by rounding down go to
-- the largest remainders), of the voters when there are several (those shares add up to
-- more than 100%). Returns { { answer, votes, pct, lead } ... } and the winners (every
-- answer with the most votes).
function Vox.Tally(answers, counts, voters, multi)
	local sum, best = 0, 0
	for i = 1, #answers do
		sum = sum + (counts[i] or 0)
		best = math.max(best, counts[i] or 0)
	end
	local base = multi and (voters or 0) or sum
	local rows, winners = {}, {}
	for i, a in ipairs(answers) do
		local n = counts[i] or 0
		local pct = base > 0 and math.min(100, math.floor(n * 100 / base + 0.5)) or 0
		rows[i] = { answer = a, votes = n, pct = pct, lead = best > 0 and n == best }
		if rows[i].lead then winners[#winners + 1] = rows[i] end
	end
	if not multi and sum > 0 then
		local left, order = 100, {}
		for i, r in ipairs(rows) do
			r.pct = math.floor(r.votes * 100 / sum)
			left = left - r.pct
			order[i] = { i = i, rest = r.votes * 100 / sum - r.pct }
		end
		table.sort(order, function(a, b) if a.rest ~= b.rest then return a.rest > b.rest end return a.i < b.i end)
		for k = 1, left do rows[order[k].i].pct = rows[order[k].i].pct + 1 end
	end
	return rows, winners
end

-- "Winner: Yes (70%)", "Tie: Yes / No", or no votes.
function Vox.Verdict(answers, counts, voters, multi)
	local _, winners = Vox.Tally(answers, counts, voters, multi)
	if #winners == 0 then return L.VOX_NO_VOTES end
	if #winners == 1 then return L.VOX_WINNER:format(winners[1].answer, winners[1].pct) end
	local names = {}
	for i, w in ipairs(winners) do names[i] = w.answer end
	return L.VOX_TIE:format(table.concat(names, " / "))
end

-- "Yes 70% (210)  ·  No 30% (90)  ·  300 voters"
function Vox.ResultText(answers, counts, voters, multi)
	local parts = {}
	for _, r in ipairs((Vox.Tally(answers, counts, voters, multi))) do
		parts[#parts + 1] = ("%s %d%% (%d)"):format(r.answer, r.pct, r.votes)
	end
	return table.concat(parts, "  ·  ") .. "  ·  " .. L.VOX_VOTERS:format(voters or 0)
end

local function KindText(multi) return multi and L.VOX_PICK_MANY or L.VOX_PICK_ONE end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------

-- Typed: "90 Raid tonight? Yes / No / Later": seconds first if 30-300, the question up to
-- its "?", then up to six answers split by "/". No answers: Yes / No. Returns seconds,
-- question, answers, or nil.
function Vox.Parse(input)
	input = tostring(input or ""):gsub("[~|%c]", " ")
	local seconds, rest = input:match("^%s*(%d+)%s+(.+)$")
	seconds = tonumber(seconds)
	if not seconds or seconds < Vox.MIN or seconds > Vox.MAX then seconds, rest = Vox.DEFAULT, input end
	local q, tail = rest:match("^%s*(.-%?)%s*(.*)$")
	if not q then q, tail = rest, "" end
	q = Plain(q, Vox.MAX_Q)
	local answers = {}
	for a in tail:gmatch("[^/]+") do
		a = Plain(a, Vox.MAX_A)
		if a ~= "" and #answers < Vox.MAX_ANSWERS then answers[#answers + 1] = a end
	end
	if #answers < 2 then answers = { L.VOX_YES, L.VOX_NO } end
	if #q < 3 then return nil end
	return seconds, q, answers
end

local function Close(id)
	if not poll or poll.id ~= id or poll.closed then return end
	poll.closed = true
	-- (1.1.6: saved, for the tab after a /reload; never poll.votes, the voters' names. The
	-- preview's: for the session alone.)
	local history = poll.preview and previewed or History(true)
	history[#history + 1] = { q = poll.q, answers = { unpack(poll.answers) }, multi = poll.multi, to = poll.to,
		counts = { unpack(poll.counts) }, voters = poll.voters, others = poll.others, t = poll.t }
	while #history > Vox.MAX_HISTORY do table.remove(history, 1) end
	if not poll.preview and poll.to == "G" then
		ns.Comm.Send("GUILD", ("Y3~E~%d~%d~%s"):format(poll.id, poll.voters, table.concat(poll.counts, "~")), "voxend", true)
	elseif not poll.preview then
		ns.Comm.Send("CHANNEL", ("T1~E~%d~%s~%d~%s"):format(poll.id, GetGuildInfo("player") or "", poll.voters,
			table.concat(poll.counts, "~")), "voxend", true)
	end
	ns.Print(L.VOX_RESULT:format(poll.q, Vox.Verdict(poll.answers, poll.counts, poll.voters, poll.multi),
		Vox.ResultText(poll.answers, poll.counts, poll.voters, poll.multi)))
	-- The preview's own voter window gets the results the way the army's does (T1~E).
	if shown and shown.id == poll.id and not shown.counts then
		shown.counts, shown.voters, shown.resultsAt = { unpack(poll.counts) }, poll.voters, ns.Now()
	end
	-- The final chart on the asker's screen (on stream), unless the window is taken by
	-- someone else's question still open here (a Hand's while the King asks).
	local busy = frame and frame:IsShown() and not frame.live and shown and shown.asker ~= ns.me and not shown.counts
	if not ns.db.voxOff and not busy then Vox.ShowLive() end
	Changed()
end

-- opts: { q, answers = { ... }, seconds, multi, to }. The composer's way, and the typed one's.
-- to (1.1.6): one of Vox.AUDIENCES, the army when left out.
function Vox.AskWith(opts)
	local preview = ns.King.Preview()
	local to = opts.to or "E"
	if not KNOWN[to] then return ns.Print(L.VOX_USAGE) end
	if not Vox.MayAsk(to) and not preview then return ns.Print(to == "G" and L.VOX_ONLY_GM or L.THRONE_ONLY_KING) end
	-- A guild master the moderators took off (net-off, Moderation.lua): his guild's clients drop
	-- his question (Moderation.Hides), so it does not go.
	local off = to == "G" and not preview and ns.Moderation.SelfOff and ns.Moderation.SelfOff()
	if off then return ns.Print(ns.Moderation.YouText(off)) end
	local q = Plain(opts.q, Vox.MAX_Q)
	if #q < 3 then return ns.Print(L.VOX_ASK_NEED_Q) end
	local answers = {}
	for _, a in ipairs(opts.answers or {}) do
		a = Plain(a, Vox.MAX_A)
		if a ~= "" and #answers < Vox.MAX_ANSWERS then answers[#answers + 1] = a end
	end
	if #answers < 2 then return ns.Print(L.VOX_ASK_NEED_A) end
	local seconds = math.floor(tonumber(opts.seconds) or Vox.DEFAULT)
	seconds = math.max(Vox.MIN, math.min(Vox.MAX, seconds))
	local multi = opts.multi and true or false
	local now = ns.Now()
	if poll and not poll.closed then return ns.Print(L.VOX_BUSY) end
	-- Someone else's question still open (the King's, a Hand's): it would not be shown. (1.1.6: a
	-- guild's gives way to the Throne's, Weight.)
	if shown and shown.asker ~= ns.me and now <= shown.at and not shown.counts
		and Weight(ns.King.IsKing(), to) <= Weight(shown.byKing, shown.to) then return ns.Print(L.VOX_BUSY_OTHER) end
	if not preview and now - lastSent < Vox.GAP then
		return ns.Print(L.THRONE_WAIT:format(math.ceil(Vox.GAP - (now - lastSent))))
	end
	lastSent = now
	local counts = {}
	for i = 1, #answers do counts[i] = 0 end
	poll = { id = ns.King.NewId(), q = q, answers = answers, multi = multi, to = to, t = now, at = now + seconds,
		votes = {}, counts = counts, voters = 0, others = 0, preview = preview or nil }
	placed, placedAt = {}, -math.huge
	if composer then composer:Hide() end
	local body = ("%d~%s~%s~%s"):format(seconds, multi and "M" or "1", q, table.concat(answers, "~"))
	if preview then
		ns.Print(L.THRONE_PREVIEW_NOTE)
		Vox.Show(ns.me, poll.id, seconds, q, answers, multi, true, nil, to) -- how they see it
	elseif to == "G" then
		-- Over GUILD (at most 233 bytes: never in pieces, which GUILD puts together for a few types alone).
		ns.Comm.Send("GUILD", ("Y3~V~%d~%s"):format(poll.id, body), "vox", true)
	else
		local msg = ("T1~V~%d~%s~%s%s"):format(poll.id, GetGuildInfo("player") or "", to == "E" and "" or (to .. "~"), body)
		-- Ahead of the census (every soldier's countdown starts when it arrives); a long one
		-- goes in pieces.
		if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "vox", true) else ns.Comm.SendChunked(msg, true) end
	end
	local id = poll.id
	-- Votes still on their way when the time is up count too (GRACE).
	Vox.after(seconds + Vox.GRACE, "vox close", function() Close(id) end)
	Changed()
	return true
end

-- Typed (tests, the test bench): see Vox.Parse. multi: several answers each. to: the audience.
function Vox.Ask(input, multi, to)
	local seconds, q, answers = Vox.Parse(input)
	if not seconds then return ns.Print(L.VOX_USAGE) end
	return Vox.AskWith({ q = q, answers = answers, seconds = seconds, multi = multi, to = to })
end

function Vox.CloseNow()
	if poll and not poll.closed then Close(poll.id) end
end

-- "136" -> { 1, 3, 6 } when every digit is an answer, each once (one alone for pick-one).
local function Picks(text, n, multi)
	local out, seen = {}, {}
	for d in tostring(text or ""):gmatch("%d") do
		d = tonumber(d)
		if d < 1 or d > n or seen[d] then return nil end
		seen[d] = true
		out[#out + 1] = d
	end
	if #out == 0 or (not multi and #out ~= 1) then return nil end
	return out
end

-- Votes to the asker: one each, while the question is open (and GRACE after).
function Vox.HandleVote(dist, sender, text)
	if dist ~= "WHISPER" or not poll or poll.closed then return end
	local id, digits, guild = text:match("^Y1~(%d+)~(%d+)~(.*)$")
	if tonumber(id) ~= poll.id then return end
	local picks = Picks(digits, #poll.answers, poll.multi)
	if not picks or ns.Now() > poll.at + Vox.GRACE or not ns.IsFederation(guild) then return end
	sender = ns.FullName(sender)
	if poll.votes[sender] or poll.voters + poll.others >= Vox.MAX_VOTES then return end
	-- 1.1: a name the moderators took off (net-off, Moderation.lua): not counted, not even as a voter.
	if ns.Moderation.Hides and ns.Moderation.Hides(sender, guild) then return end
	-- 1.1: one vote per player: a character linked to one that voted (Alts.lua) votes as it did.
	for _, other in ipairs(ns.Alts.Linked and ns.Alts.Linked(sender) or {}) do
		if poll.votes[ns.FullName(other)] then return end
	end
	poll.votes[sender] = digits
	if Counts(poll, sender, guild) then
		for _, i in ipairs(picks) do poll.counts[i] = poll.counts[i] + 1 end
		poll.voters = poll.voters + 1
	else
		poll.others = poll.others + 1
	end
	Changed()
end
ns.Comm.Handle("Y1", function(...) Vox.HandleVote(...) end)

---------------------------------------------------------------------------
-- The window: a voter's (the answers to pick, then the results as a chart), or the asker's
-- chart (live while the votes come, then final)
---------------------------------------------------------------------------

local ROW_H, WIDTH = 24, 400

local function TogglePick(i)
	if not shown or frame.live or shown.voted or shown.counts or ns.Now() > shown.at then return end
	if shown.multi then
		shown.picks[i] = not shown.picks[i] or nil
	else
		shown.picks = { [i] = true }
	end
	Vox.Refresh()
end

local function Vote()
	if not shown or shown.voted or shown.counts or ns.Now() > shown.at then return end
	-- 1.1: the moderators took this character off (net-off, Moderation.lua): the vote would not count.
	local off = ns.Moderation.SelfOff and ns.Moderation.SelfOff()
	if off then return ns.Print(ns.Moderation.YouText(off)) end
	local digits = {}
	for i = 1, #shown.answers do if shown.picks[i] then digits[#digits + 1] = tostring(i) end end
	if #digits == 0 then return end
	shown.voted = table.concat(digits)
	local msg = ("Y1~%d~%s~%s"):format(shown.id, shown.voted, GetGuildInfo("player") or "")
	if shown.asker ~= ns.me then
		ns.Comm.Whisper(shown.asker, msg, "vote", true)
	elseif poll and poll.id == shown.id then
		Vox.HandleVote("WHISPER", ns.me, ("Y1~%d~%s~%s"):format(shown.id, shown.voted, GetGuildInfo("player") or "Olympus"))
	end
	Vox.Refresh()
end

local function MakeRow(f, i)
	local r = CreateFrame("Button", nil, f)
	r:SetSize(WIDTH - 40, ROW_H - 2)
	local ok, check = pcall(CreateFrame, "CheckButton", nil, r, "UICheckButtonTemplate")
	if not ok or not check then check = CreateFrame("CheckButton", nil, r) end
	check:SetSize(22, 22)
	check:SetPoint("LEFT", 0, 0)
	check:SetScript("OnClick", function() ns.SafeCall("vox pick", TogglePick, i) end)
	r.check = check
	r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	r.label:SetPoint("LEFT", 26, 0)
	r.label:SetWidth(130)
	r.label:SetJustifyH("LEFT")
	r.label:SetWordWrap(false)
	local bar = CreateFrame("StatusBar", nil, r)
	bar:SetPoint("LEFT", 160, 0)
	bar:SetSize(WIDTH - 40 - 160 - 64, 14)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 100)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.45)
	r.bar = bar
	r.pct = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.pct:SetPoint("RIGHT", 0, 0)
	r.pct:SetWidth(60)
	r.pct:SetJustifyH("RIGHT")
	r:SetScript("OnClick", function() ns.SafeCall("vox pick", TogglePick, i) end)
	return r
end

-- (1.1.5) The Olympus window's metal without its portrait (ns.Window, Dialog.lua): who asks in its
-- title bar (f.title is the bar's text), the question under it; its X hides it, in combat too.
Vox.QUESTION_TOP = -32
local function MakeFrame()
	local f = ns.Window("OlympusVoxFrame", UIParent, { title = L.VOX_TITLE })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("TOP", UIParent, "TOP", 0, -150)
	f:SetSize(WIDTH, 220)
	f.title = f.TitleText
	f.question = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	f.question:SetPoint("TOP", f, "TOP", 0, Vox.QUESTION_TOP)
	f.question:SetWidth(WIDTH - 40)
	f.question:SetJustifyH("CENTER")
	f.kind = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.kind:SetPoint("TOP", f.question, "BOTTOM", 0, -4)
	f.rows = {}
	for i = 1, Vox.MAX_ANSWERS do
		f.rows[i] = MakeRow(f, i)
		f.rows[i]:SetPoint("TOPLEFT", f.kind, "BOTTOM", -(WIDTH - 40) / 2, -8 - (i - 1) * ROW_H)
	end
	f.verdict = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.verdict:SetWidth(WIDTH - 40)
	f.vote = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.vote:SetSize(120, 24)
	f.vote:SetScript("OnClick", function() ns.SafeCall("vox vote", Vote) end)
	f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOM", 0, 16)
	f.status:SetWidth(WIDTH - 40)
	f.close = f.CloseButton
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.5 then return end
		elapsed = 0
		ns.SafeCall("vox tick", Vox.Refresh)
	end)
	return f
end

-- What the window shows now: the asker's chart (his open question, or the last one), or the
-- voter's question.
local function Source()
	if frame.live then
		local history = List()
		local p = (poll and not poll.closed) and poll or history[#history]
		if not p then return nil end
		return { q = p.q, answers = p.answers, multi = p.multi, to = p.to, counts = p.counts, voters = p.voters,
			at = p.at or 0, final = p ~= poll or poll.closed, live = true, asker = ns.me,
			guild = GetGuildInfo("player"), byKing = ns.King.IsKing() or ns.King.Preview() }
	end
	return shown
end

-- "Asmon asks the army", "Helper, Hand of the King, asks the High Council", "Zed asks <Olympus Zeus>".
local function Title(s, name)
	local to = s.to or "E"
	if to == "G" then return L.VOX_ASKS_G:format(name, s.guild or "") end
	if to == "H" then return (s.byKing and L.VOX_ASKS_H or L.VOX_ASKS_HAND_H):format(name) end
	if to == "M" then return (s.byKing and L.VOX_ASKS_M or L.VOX_ASKS_HAND_M):format(name) end
	return (s.byKing and L.VOX_ASKS or L.VOX_ASKS_HAND):format(name)
end

function Vox.Refresh()
	if not frame then return end
	local s = Source()
	if not s then return frame:Hide() end
	local now = ns.Now()
	local byName = s.byKing and ns.KingName(s.asker) or ns.DisplayName(s.asker)
	frame.title:SetText(Title(s, byName))
	frame.question:SetText(s.q)
	local results = s.live or s.counts ~= nil
	local open = not s.counts and not s.final and now <= (s.at or 0)
	frame.kind:SetText(KindText(s.multi) .. (s.multi and results and ("  " .. L.VOX_SHARE_OF_VOTERS) or ""))
	local rows = results and Vox.Tally(s.answers, s.counts or {}, s.voters or 0, s.multi) or nil
	local n = #s.answers
	for i, r in ipairs(frame.rows) do
		local a = s.answers[i]
		r:SetShown(a ~= nil)
		if a then
			r.label:SetText(rows and rows[i].lead and Gold(a) or a)
			-- The whole row while voting; room for the bar once there is a chart.
			r.label:SetWidth(rows and 130 or (WIDTH - 40 - 26))
			-- The answers to pick while voting (kept checked with the results); the chart once
			-- there are results.
			local picked = s.picks and s.picks[i]
			r.check:SetShown(not s.live)
			r.check:SetChecked(picked and true or false)
			r.check:SetEnabled(not s.voted and open and not s.live)
			r:EnableMouse(not s.voted and open and not s.live)
			r.bar:SetShown(rows ~= nil)
			r.pct:SetShown(rows ~= nil)
			if rows then
				r.bar:SetValue(rows[i].pct)
				if rows[i].lead then r.bar:SetStatusBarColor(1, 0.82, 0) else r.bar:SetStatusBarColor(0.45, 0.6, 0.9) end
				r.pct:SetText(("%d%%  (%d)"):format(rows[i].pct, rows[i].votes))
			end
		end
	end
	-- Below the rows: the Vote button while voting, the verdict once there are results.
	local below = -12 - n * ROW_H
	frame.vote:ClearAllPoints()
	frame.vote:SetPoint("TOP", frame.kind, "BOTTOM", 0, below)
	frame.verdict:ClearAllPoints()
	frame.verdict:SetPoint("TOP", frame.kind, "BOTTOM", 0, below - 4)
	local canVote = not s.live and not s.counts and open and not s.voted
	frame.vote:SetShown(canVote)
	if canVote then
		frame.vote:SetText(L.VOX_VOTE)
		local any = false
		for i = 1, n do if s.picks[i] then any = true end end
		frame.vote:SetEnabled(any)
	end
	frame.verdict:SetShown(rows ~= nil)
	if rows then frame.verdict:SetText(Vox.Verdict(s.answers, s.counts or {}, s.voters or 0, s.multi)) end
	local qh = frame.question.GetStringHeight and frame.question:GetStringHeight() or 16
	-- A long verdict (a tie of several answers) wraps: its extra lines too.
	local vh = rows and frame.verdict.GetStringHeight and frame.verdict:GetStringHeight() or 14
	frame:SetHeight(math.max(160, 120 + (tonumber(qh) or 16) + n * ROW_H + math.max(0, (tonumber(vh) or 14) - 14)))
	-- The line at the bottom: the countdown, the vote cast, the voters, the end.
	local left = math.max(0, math.ceil((s.at or 0) - now))
	local clock = L.VOX_CLOSES:format(math.floor(left / 60), left % 60)
	if s.live then
		frame.status:SetText(s.final and (L.VOX_FINAL .. "  ·  " .. L.VOX_VOTERS:format(s.voters or 0))
			or (L.VOX_LIVE .. "  ·  " .. L.VOX_VOTERS:format(s.voters or 0) .. "  ·  " .. clock))
	elseif s.counts then
		frame.status:SetText(L.VOX_FINAL .. "  ·  " .. L.VOX_VOTERS:format(s.voters or 0))
		if now - (s.resultsAt or now) > Vox.RESULTS_SHOWN then frame:Hide() end
	elseif open then
		local picked = {}
		for i = 1, n do if s.voted and s.voted:find(tostring(i), 1, true) then picked[#picked + 1] = s.answers[i] end end
		frame.status:SetText((s.voted and (L.VOX_VOTED:format(table.concat(picked, ", ")) .. "  ") or "") .. clock)
	else
		frame.status:SetText(L.VOX_WAITING)
		if now > (s.at or 0) + 30 then frame:Hide() end
	end
end

-- to (1.1.6): who it is for, the army when left out (the title names them).
function Vox.Show(asker, id, seconds, q, answers, multi, byKing, hidden, to)
	shown = { id = id, asker = asker, q = q, answers = answers, multi = multi and true or false, at = ns.Now() + seconds,
		byKing = byKing, picks = {}, hidden = hidden and true or nil, to = to or "E", guild = GetGuildInfo("player") }
	-- 1.1 (#31): the player's block terms hit its question or an answer: no window, no sound, no
	-- line in chat; the Decrees tab offers it with a click while it is open (Vox.Reveal).
	if hidden then
		ns.Fire("DECREES_CHANGED")
		return
	end
	if ns.db.voxOff then
		local list = {}
		for i, a in ipairs(answers) do list[i] = ("%d) %s"):format(i, a) end
		ns.Print(L.VOX_CHAT:format(byKing and ns.KingName(asker) or ns.DisplayName(asker), q, table.concat(list, "  "), KindText(multi)))
		return
	end
	-- In an instance or on Busy (1.1): the question in chat now, the window once the player is
	-- out if it is still open (or at a click on its line on the Decrees tab).
	local s = shown
	local function Open()
		frame = frame or MakeFrame()
		frame.live = nil
		frame:Show()
		Vox.Refresh()
	end
	local opened = ns.Alert("vox", "soft", {
		what = L.HELD_VOX:format(Plain(q, 40)), key = "vox" .. tostring(id), show = Open,
		open = function() return shown == s and ns.Now() <= s.at and not s.counts and not s.voted end,
	})
	if not opened then
		local list = {}
		for i, a in ipairs(answers) do list[i] = ("%d) %s"):format(i, a) end
		ns.Print(L.VOX_HELD:format(byKing and ns.KingName(asker) or ns.DisplayName(asker), q, table.concat(list, "  "), KindText(multi)))
	end
end

-- The asker's chart on his screen: live while the question is open, then the final results.
function Vox.ShowLive()
	if not (poll or List()[1]) then return ns.Print(L.VOX_NONE) end
	frame = frame or MakeFrame()
	frame.live = true
	frame:Show()
	Vox.Refresh()
end

-- A question for this client, its audience already checked: not our own.
local function Take(sender, id, rest, guild, to)
	if ns.FullName(sender) == ns.me then return end
	-- 1.1: a Hand (or a guild master) the moderators took off (net-off, Moderation.lua): no window of theirs.
	if ns.Moderation.Hides and ns.Moderation.Hides(sender, guild) then return end
	local byKing = ns.King.FromKing(sender, guild)
	local seconds, kind, q, a = rest:match("^(%d+)~([1M])~([^~]+)~(.+)$")
	seconds = tonumber(seconds)
	if not seconds or seconds < Vox.MIN or seconds > Vox.MAX then return end
	local answers = {}
	for x in a:gmatch("[^~]+") do
		x = Plain(x, Vox.MAX_A)
		if x ~= "" and #answers < Vox.MAX_ANSWERS then answers[#answers + 1] = x end
	end
	q = Plain(q, Vox.MAX_Q)
	if #answers < 2 or #q < 3 then return end
	local now = ns.Now()
	local from = ns.FullName(sender)
	-- One question at a time: another asker's still open stays, unless this one comes first
	-- (Weight: the King's before a Hand's). And from each asker a new window SHOW_GAP apart at most.
	local open = shown and now <= shown.at and not shown.counts
	if open and shown.asker ~= from and Weight(byKing, to) <= Weight(shown.byKing, shown.to) then return end
	if now - (lastShownBy[from] or -math.huge) < Vox.SHOW_GAP then return end
	lastShownBy[from] = now
	-- 1.1 (#31): hidden when the player's block terms hit the question or an answer (Filter.lua).
	local F, hidden = ns.Filter, false
	if F and not F.missing then
		hidden = F.Hides(q)
		for _, x in ipairs(answers) do hidden = hidden or F.Hides(x) end
	end
	Vox.Show(from, id, seconds, q, answers, kind == "M", byKing, hidden, to)
end

-- A question from the King or a Hand (King.Authorized checked the sender). 1.1.6: a letter
-- before the seconds names a narrower audience (THRONE_TO); a client outside it opens nothing,
-- and a letter it does not know opens nothing either.
local function OnQuestion(sender, id, rest, guild)
	local to, after = rest:match("^(%a)~(.*)$")
	if to and not THRONE_TO[to] then return end
	to = to or "E"
	if not Vox.InAudience(to) then return end
	Take(sender, id, after or rest, guild, to)
end

-- The question the player's block terms hid, while it is open (the Decrees tab), or nil.
function Vox.HiddenQuestion()
	if shown and shown.hidden and ns.Now() <= shown.at and not shown.counts then return shown end
	return nil
end

-- A click shows it: its window (or its line in chat with /oly vox off), to vote while it is open.
function Vox.Reveal()
	if not (shown and shown.hidden) then return end
	shown.hidden = nil
	ns.Fire("DECREES_CHANGED")
	if ns.Now() > shown.at or shown.counts then return end
	if ns.db.voxOff then
		local list = {}
		for i, a in ipairs(shown.answers) do list[i] = ("%d) %s"):format(i, a) end
		return ns.Print(L.VOX_CHAT:format(shown.byKing and ns.KingName(shown.asker) or ns.DisplayName(shown.asker), shown.q, table.concat(list, "  "), KindText(shown.multi)))
	end
	frame = frame or MakeFrame()
	frame.live = nil
	frame:Show()
	Vox.Refresh()
end

-- overGuild (1.1.6): the results of a guild's question come over GUILD (Y3), every other's on
-- the channel (T1~E): never the one for the other.
local function OnResults(sender, id, rest, overGuild)
	if not shown or shown.id ~= id or ns.FullName(sender) ~= shown.asker then return end
	if (shown.to == "G") ~= (overGuild == true) then return end
	local voters, tail = rest:match("^(%d+)~(.*)$")
	voters = tonumber(voters)
	if not voters then return end
	local counts = {}
	for n in tail:gmatch("(%d+)") do
		if #counts < #shown.answers then counts[#counts + 1] = math.min(tonumber(n), Vox.MAX_VOTES) end
	end
	for i = #counts + 1, #shown.answers do counts[i] = 0 end
	shown.counts, shown.voters, shown.resultsAt = counts, math.min(voters, Vox.MAX_VOTES), ns.Now()
	-- (1.1, #31: a question the player's block terms hid stays hidden with its results.)
	if shown.hidden then return end
	ns.Print(L.VOX_RESULT:format(shown.q, Vox.Verdict(shown.answers, counts, shown.voters, shown.multi),
		Vox.ResultText(shown.answers, counts, shown.voters, shown.multi)))
	-- Voted or not, the window shows the chart (chat-only players read the line). The
	-- asker's own chart, once final, gives way to it. In an instance or on Busy (1.1) the chart
	-- only fills a window already open: the line in chat says it all.
	if frame and frame.live and (not poll or poll.closed) then frame.live = nil end
	if frame and not frame.live and not ns.db.voxOff and (frame:IsShown() or not ns.Quiet()) then
		frame:Show()
		Vox.Refresh()
	end
end

ns.King.Register("V", OnQuestion)
ns.King.Register("E", function(sender, id, rest) OnResults(sender, id, rest) end)

-- Y3 (1.1.6): a guild master's question to his own guild, and its results. Over GUILD alone,
-- which the server carries between the members of one guild (and names who sent it), from the
-- character our roster has at rank 0: a guildmate who is not our guild master opens nothing.
function Vox.HandleGuild(dist, sender, text)
	if dist ~= "GUILD" or type(text) ~= "string" or ns.Roster.RankOf(sender) ~= 0 then return end
	local kind, id, rest = text:match("^Y3~([VE])~(%d+)~(.*)$")
	if not kind then return end
	if kind == "E" then return OnResults(sender, tonumber(id), rest, true) end
	if not Vox.InAudience("G") then return end
	Take(sender, tonumber(id), rest, GetGuildInfo("player"), "G")
end
ns.Comm.Handle("Y3", function(...) Vox.HandleGuild(...) end)

---------------------------------------------------------------------------
-- The Vox Populi tab (the King and his Hands)
---------------------------------------------------------------------------

-- A bar as wide as the share (a plain texture, tinted: gold for the leader).
local function Bar(pct, lead)
	local w = math.max(1, math.floor(pct * 0.8 + 0.5))
	local r, g, b = 115, 150, 230
	if lead then r, g, b = 255, 210, 0 end
	return ("|TInterface\\Buttons\\WHITE8X8:8:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(w, r, g, b)
end

local function ChartLines(lines, p)
	for _, r in ipairs((Vox.Tally(p.answers, p.counts, p.voters, p.multi))) do
		lines[#lines + 1] = {
			indent = 1, text = (r.lead and Gold(r.answer) or r.answer) .. "  " .. Bar(r.pct, r.lead),
			right = ("%d%%  (%d)"):format(r.pct, r.votes),
		}
	end
end

function Vox.Build()
	local lines = { { header = true, text = L.VOX_TITLE } }
	if poll and not poll.closed then
		local left = math.max(0, math.ceil(poll.at - ns.Now()))
		lines[#lines + 1] = { text = Gold(poll.q), right = L.VOX_LEFT:format(math.floor(left / 60), left % 60) }
		lines[#lines + 1] = { text = Grey(KindText(poll.multi) .. (poll.multi and ("  " .. L.VOX_SHARE_OF_VOTERS) or "")
			.. "  ·  " .. AudienceText(poll.to)) }
		ChartLines(lines, poll)
		lines[#lines + 1] = { text = Grey(L.VOX_TOTAL:format(poll.voters) .. "  ·  " .. Vox.Verdict(poll.answers, poll.counts, poll.voters, poll.multi)), gapAfter = true }
		if poll.others > 0 then
			-- (1.1.6: a narrower audience's are the votes from outside it.)
			local army = poll.to == "E"
			lines[#lines].gapAfter = nil
			lines[#lines + 1] = { text = Grey((army and L.VOX_UNPLACED or L.VOX_OUTSIDE):format(poll.others)), gapAfter = true,
				tooltip = function(tt) tt:AddLine(army and L.VOX_UNPLACED_TIP or L.VOX_OUTSIDE_TIP, 1, 1, 1, true) end }
		end
	else
		lines[#lines + 1] = { text = Grey(L.VOX_NONE), gapAfter = true }
	end
	-- (1.1.6: the last MAX_HISTORY questions, kept across sessions.)
	local history = List()
	lines[#lines + 1] = { header = true, text = L.VOX_HISTORY:format(#history) }
	if #history == 0 then lines[#lines + 1] = { text = Grey(L.VOX_HISTORY_NONE) } end
	for i = #history, 1, -1 do
		local h = history[i]
		lines[#lines + 1] = {
			text = h.q .. (h.to ~= "E" and Grey("  (" .. AudienceText(h.to) .. ")") or ""),
			right = Grey(L.VOX_VOTERS:format(h.voters) .. "  " .. When(h.t)),
			onClick = function() ns.UI.ShowCopy(L.VOX_TITLE, Vox.DiscordText(h)) end,
			tooltip = function(tt)
				tt:AddLine(h.q, 1, 0.82, 0, true)
				tt:AddLine(KindText(h.multi) .. "  ·  " .. AudienceText(h.to), 0.6, 0.6, 0.6)
				tt:AddLine(Vox.Verdict(h.answers, h.counts, h.voters, h.multi), 1, 1, 1, true)
				tt:AddLine(L.VOX_CLICK_COPY, 0.6, 0.6, 0.6)
			end,
		}
		ChartLines(lines, h)
		lines[#lines].gapAfter = true
	end
	return lines, L.TAB_VOX, L.VOX_HINT
end

-- For Discord: the question (who it was for), each answer with its share and votes, the verdict.
function Vox.DiscordText(h)
	if not h then
		local history = List()
		h = history[#history]
	end
	if not h then return "" end
	local out = { ("**%s** (%s  ·  %s)"):format(h.q, KindText(h.multi), AudienceText(h.to)) }
	for _, r in ipairs((Vox.Tally(h.answers, h.counts, h.voters, h.multi))) do
		out[#out + 1] = ("- %s: %d%% (%d)"):format(r.answer, r.pct, r.votes)
	end
	out[#out + 1] = Vox.Verdict(h.answers, h.counts, h.voters, h.multi) .. "  ·  " .. L.VOX_VOTERS:format(h.voters)
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- The composer: the question, two to six answers, pick one or several, how long, who it is
-- for (1.1.6: the audiences this character may pick, Vox.Audiences)
---------------------------------------------------------------------------

local function Box(parent, width, letters)
	local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
	if not ok or not eb then eb = CreateFrame("EditBox", nil, parent) end
	eb:SetSize(width, 20)
	eb:SetAutoFocus(false)
	-- What is sent is cut in bytes (an accented letter is two): the box counts the same way.
	eb:SetMaxLetters(letters)
	if eb.SetMaxBytes then eb:SetMaxBytes(letters + 1) end
	eb:SetFontObject("ChatFontNormal")
	return eb
end

local function Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	return fs
end

local function TimeLabel(sec)
	if sec < 60 or sec % 60 ~= 0 then return ("%ds"):format(sec) end
	return ("%dm"):format(sec / 60)
end

-- (1.1.5, the author's asks) The Olympus window's bronze metal, not the plain silver frame, and
-- without its portrait and logo (only the Olympus window has them): ns.Window (Dialog.lua), its
-- inset box under the title bar as the plain frame's, the boxes where they always were. Its X hides
-- it itself, in combat too. Escape closes it with mouse and keyboard; with the gamepad UI its X and
-- Cancel do (checked each time it shows: a switch to the gamepad UI since takes it off the list).
local function MakeComposer()
	local f = ns.Window("OlympusVoxAskFrame", UIParent, { title = L.VOX_ASK_TITLE })
	f:SetSize(420, 410)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local q = Label(f, L.VOX_ASK_QUESTION)
	q:SetPoint("TOPLEFT", 18, -34)
	f.q = Box(f, 380, Vox.MAX_Q)
	f.q:SetPoint("TOPLEFT", 22, -48)
	local a = Label(f, L.VOX_ASK_ANSWERS)
	a:SetPoint("TOPLEFT", 18, -76)
	f.a = {}
	for i = 1, Vox.MAX_ANSWERS do
		local eb = Box(f, 180, Vox.MAX_A)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		eb:SetPoint("TOPLEFT", 22 + col * 196, -90 - row * 26)
		f.a[i] = eb
	end
	-- Tab and Enter walk through the boxes; Enter on the last one asks.
	local boxes = { f.q }
	for i = 1, Vox.MAX_ANSWERS do boxes[#boxes + 1] = f.a[i] end
	for _, eb in ipairs(boxes) do eb.olympusBox = true end
	for i, eb in ipairs(boxes) do
		eb:SetScript("OnTabPressed", function() boxes[i % #boxes + 1]:SetFocus() end)
		eb:SetScript("OnEnterPressed", function()
			if i < #boxes then boxes[i + 1]:SetFocus() else ns.SafeCall("vox ask", Vox.AskFromComposer) end
		end)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
	end
	local k = Label(f, L.VOX_ASK_KIND)
	k:SetPoint("TOPLEFT", 18, -174)
	f.kinds = {}
	for i, multi in ipairs({ false, true }) do
		local okc, c = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
		if not okc or not c then c = CreateFrame("CheckButton", nil, f) end
		c:SetSize(22, 22)
		c:SetPoint("TOPLEFT", 18 + (i - 1) * 190, -188)
		c.multi = multi
		c:SetScript("OnClick", function() f.multi = multi; ns.SafeCall("vox composer", Vox.RefreshComposer) end)
		c.label = Label(f, multi and L.VOX_PICK_MANY or L.VOX_PICK_ONE, "GameFontHighlightSmall")
		c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
		f.kinds[i] = c
	end
	local tl = Label(f, L.VOX_ASK_TIME)
	tl:SetPoint("TOPLEFT", 18, -218)
	f.times = {}
	for i, sec in ipairs(Vox.TIMES) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(64, 22)
		b:SetPoint("TOPLEFT", 18 + (i - 1) * 76, -234)
		b:SetText(TimeLabel(sec))
		b:SetScript("OnClick", function() f.seconds = sec; ns.SafeCall("vox composer", Vox.RefreshComposer) end)
		b.seconds = sec
		f.times[i] = b
	end
	-- Who it is for (1.1.6): one box each, two a row; only those this character may pick show
	-- (Vox.RefreshComposer places them). Plain check boxes, as the kinds: no menu, gamepad or not.
	local wl = Label(f, L.VOX_ASK_TO)
	wl:SetPoint("TOPLEFT", 18, -264)
	f.audiences = {}
	for i, to in ipairs(Vox.AUDIENCES) do
		local okc, c = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
		if not okc or not c then c = CreateFrame("CheckButton", nil, f) end
		c:SetSize(22, 22)
		c.to = to
		c:SetScript("OnClick", function() f.to = to; ns.SafeCall("vox composer", Vox.RefreshComposer) end)
		c.label = Label(f, AudienceText(to), "GameFontHighlightSmall")
		c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
		f.audiences[i] = c
	end
	-- Under them, for the council and the guild masters (1.1.6 review): who sees the window is not
	-- who can read the question, which goes on the channel as every Throne call does.
	f.open = Label(f, L.VOX_ASK_OPEN, "GameFontDisableSmall")
	f.open:SetWidth(384)
	f.open:SetWordWrap(true)
	f.ask = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.ask:SetSize(190, 24)
	f.ask:SetPoint("BOTTOMRIGHT", -18, 16)
	f.ask:SetText(L.VOX_ASK_SEND)
	f.ask:SetScript("OnClick", function() ns.SafeCall("vox ask", Vox.AskFromComposer) end)
	f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.cancel:SetSize(100, 24)
	f.cancel:SetPoint("RIGHT", f.ask, "LEFT", -8, 0)
	f.cancel:SetText(CANCEL or "Cancel")
	f.cancel:SetScript("OnClick", function() f:Hide() end)
	return f
end

function Vox.RefreshComposer()
	if not composer then return end
	for _, c in ipairs(composer.kinds) do c:SetChecked(c.multi == composer.multi) end
	for _, b in ipairs(composer.times) do
		if b.seconds == composer.seconds then b:LockHighlight() else b:UnlockHighlight() end
	end
	-- (1.1.6) The audiences this character may pick, in order; the one picked, and the button
	-- that names it.
	local may = {}
	for _, to in ipairs(Vox.Audiences()) do may[to] = true end
	local n = 0
	for _, c in ipairs(composer.audiences) do
		local shows = may[c.to] == true
		c:SetShown(shows)
		c.label:SetShown(shows)
		if shows then
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", 18 + (n % 2) * 190, -278 - math.floor(n / 2) * 24)
			n = n + 1
		end
		c:SetChecked(c.to == composer.to)
	end
	composer.open:ClearAllPoints()
	composer.open:SetPoint("TOPLEFT", 18, -280 - math.ceil(n / 2) * 24)
	composer.open:SetShown(THRONE_TO[composer.to] == true)
	composer.ask:SetText(composer.to == "E" and L.VOX_ASK_SEND or L["VOX_ASK_SEND_" .. tostring(composer.to)] or L.VOX_ASK_SEND)
end

function Vox.AskFromComposer()
	if not composer then return end
	local answers = {}
	for i, eb in ipairs(composer.a) do answers[i] = eb:GetText() end
	return Vox.AskWith({ q = composer.q:GetText(), answers = answers, seconds = composer.seconds, multi = composer.multi,
		to = composer.to })
end

-- A fresh question: Yes / No ready as the first two answers, pick one, 90 seconds, for the first
-- audience this character may pick (the Throne: the whole army; a guild master: his guild).
function Vox.Prompt()
	local audiences = Vox.Audiences()
	if #audiences == 0 then return ns.Print(L.THRONE_ONLY_KING) end
	composer = composer or MakeComposer()
	composer.q:SetText("")
	for i, eb in ipairs(composer.a) do eb:SetText(i == 1 and L.VOX_YES or i == 2 and L.VOX_NO or "") end
	composer.multi, composer.seconds, composer.to = false, Vox.DEFAULT, audiences[1]
	Vox.RefreshComposer()
	composer:Show()
	ns.Focus(composer.q)
end

-- The tab: the Throne's (the King, his Steward, his Hands, the author's preview) and, 1.1.6, every
-- guild master's, for his guild's questions.
function Vox.Visible() return ns.King.Visible() or Vox.GuildMaster() end
function Vox.State() return poll, List(), shown end
function Vox.Frame() return frame end
function Vox.Composer() return composer end

function Vox.SetOff(off)
	ns.db.voxOff = off and true or nil
	ns.Print(off and L.VOX_OFF or L.VOX_ON)
	-- Back on while a question is open: its window, to vote now.
	if not off and shown and ns.Now() <= shown.at and not shown.counts and not shown.voted and not shown.hidden then
		frame = frame or MakeFrame()
		frame.live = nil
		frame:Show()
		Vox.Refresh()
	end
end

-- Tests start from a clean state.
function Vox.Reset()
	poll, shown = nil, nil
	placed, placedAt = {}, -math.huge
	wipe(previewed); wipe(checked)
	if ns.db then ns.db.voxHistory = nil end
	lastSent, changePending = -math.huge, false
	wipe(lastShownBy)
	if frame then frame:Hide(); frame.live = nil end
	if composer then composer:Hide() end
end
