local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): PagesPlayer.lua. A stub the arena's core created for the screens to
-- fill. Fight Night, Tournament, Wallet, Ranking (fighters and bettors), Profile (its Edit
-- opens the core's ProfileEdit): each an ArenaUI.RegisterPane(key, spec).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome

-- The player's panes, by section (the design, the owner's orders of 2026-09-30):
-- - Arena: Events (Fight Nights, tournaments and public fights, the player's own matches with
--   Find an opponent and Challenge on their header, the design), Rankings (one compact switchable view:
--   today, this week, this month or all time; global, a class or a race; a page at a time, never a
--   long list of every ranking), Profile (his fight history and profile fields together; its Edit
--   in the core's ProfileEdit; anyone's from a name's click).
-- - Bones: Play (his table, Find a player, a new table, practice), Live tables (to watch),
--   History (his games). The table itself is the Bones tables' board (FarkleBoard.lua).
-- - Lottery: the Lottery's board (LotteryBoard.lua); a stand-in here only while it is not in the build.
-- The one wallet shows in the window's header in every section (Slip.lua: ArenaUI.Wallet).
-- Each pane: { section, label, order, lines(st), text(st), buttons(st), detail(canvas, st),
-- build(parent), refresh(frame, st), copy(st) } (Window.lua).

-- Ink colours for text on parchment (dark, legible; never the gold of the game's own frames).
local INK = { gold = "|cff7a4a00", red = "|cff8b1a1a", green = "|cff1f5a12", grey = "|cff5c5040", blue = "|cff17406e" }
Kit.INKS = INK
local function C(kind, s) return (INK[kind] or "") .. tostring(s) .. "|r" end
Kit.C = C

local function Name(n) return Kit.Name(n) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Now() return ns.Arena.Now() end

-- A click that needs the arena's action, or says why not.
local function Do(action, ...)
	local ok, why = ns.Arena.Do(action, ...)
	if not ok and why then ArenaUI.Say(Kit.Why(why == "unknown" and "missing" or why)) end
	return ok, why
end
ArenaUI.DoAction = Do

---------------------------------------------------------------------------
-- Arena: Events
---------------------------------------------------------------------------

-- The event that matters now: live first, then taking bets (the nearest close), then the next one.
function ArenaUI.BestEvent(list)
	local best, bestRank
	local now = Now()
	for _, ev in ipairs(list or Data.Events() or {}) do
		local rank
		if ev.live then rank = 1
		elseif not ev.over and ev.lockAt and ev.lockAt > now then rank = 2
		elseif not ev.over then rank = 3 end
		if rank and (not bestRank or rank < bestRank) then best, bestRank = ev, rank end
	end
	return best
end

local function EventRight(ev)
	local word = Home.StateWord(ev)
	if ev.realm and ev.realm ~= ns.realm then word = word .. " " .. C("grey", L.ARENA_OTHER_REALM:format(ev.realm)) end
	if ev.mode == "T" then word = C("red", L.ARENA_TAG_TEST) .. " " .. word end
	return word
end

-- Which event a pane shows: the one clicked, else the one that matters now.
local function EventOf(st)
	local id = st and st.sel
	local ev = id and Data.Event(id)
	if ev then return ev end
	ev = ArenaUI.BestEvent()
	if ev and st then st.sel = ev.id end
	return ev
end
ArenaUI.EventOf = EventOf

local function EventsLines(st)
	local lines = {}
	local events = Data.Events() or {}
	local sel = EventOf(st)
	local groups = { live = {}, next = {}, mine = {}, ended = {} }
	for _, ev in ipairs(events) do
		if not ev.public and Home.Mine(ev) then groups.mine[#groups.mine + 1] = ev
		elseif ev.public and ev.live then groups.live[#groups.live + 1] = ev
		elseif ev.public and not ev.over then groups.next[#groups.next + 1] = ev
		elseif ev.public then groups.ended[#groups.ended + 1] = ev end
	end
	local function Row(ev)
		local id = ev.id
		local text = Home.EventTitle(ev)
		if sel and sel.id == id then text = C("blue", "> ") .. text end
		lines[#lines + 1] = { text = text, right = EventRight(ev), indent = 1, key = id, onClick = function() ArenaUI.Select("arena.events", id) end,
			tooltip = function(tt)
				tt:AddLine(Home.EventTitle(ev), 1, 0.82, 0)
				tt:AddLine(Home.StateWord(ev), 1, 1, 1)
			end }
	end
	if #groups.live > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_EVENTS_LIVE }
		for _, ev in ipairs(groups.live) do Row(ev) end
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_EVENTS_NEXT }
	if #groups.next == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_EVENTS_NONE), indent = 1 } end
	for _, ev in ipairs(groups.next) do Row(ev) end
	-- Your matches: Find an opponent and Challenge on its header (the design), the challenges waiting for
	-- his answer, then his 1v1 matches.
	lines[#lines + 1] = { header = true, text = L.ARENA_EVENTS_MINE }
	-- (Find an opponent and Challenge someone: the footer's New fight menu, 2026-09-30.)
	local mineAt = #lines
	for _, c in ipairs(Data.Challenges() or {}) do
		local ch = c
		lines[#lines + 1] = { text = C("red", (c.judge and L.ARENA_CHALLENGE_JUDGE_ROW or L.ARENA_CHALLENGE_ROW):format(Name(c.A), Name(c.B))), indent = 1,
			onClick = function() Home.ShowChallenge(ch) end }
	end
	for _, ev in ipairs(groups.mine) do Row(ev) end
	if #lines == mineAt then lines[#lines + 1] = { text = C("grey", L.ARENA_EVENTS_NONE), indent = 1 } end
	if #groups.ended > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_EVENTS_ENDED }
		for i, ev in ipairs(groups.ended) do
			if i > 10 then break end
			Row(ev)
		end
	end
	return lines
end

-- What the event in view is, in words (the detail box).
local function EventText(st)
	local ev = EventOf(st)
	if not ev then return L.ARENA_EVENTS_TITLE, L.ARENA_EVENTS_EMPTY end
	local parts = {}
	if ev.arbiter then parts[#parts + 1] = L.ARENA_EVENT_ARBITER:format(Name(ev.arbiter)) end
	local mk = Data.Markets(ev.id)
	if type(mk) == "table" and mk.bank then parts[#parts + 1] = L.ARENA_EVENT_BANK:format(Name(mk.bank)) end
	if ev.kind == "tourney" and ev.entrants then parts[#parts + 1] = L.ARENA_EVENT_ENTRANTS:format(#ev.entrants, ev.size or #ev.entrants) end
	if ev.kind == "card" and type(ev.bouts) == "table" then parts[#parts + 1] = L.ARENA_EVENT_BOUTS:format(#ev.bouts) end
	if ev.winner then parts[#parts + 1] = L.ARENA_EVENT_WINNER:format(Name(ev.winner)) end
	return Home.EventTitle(ev), table.concat(parts, " · ")
end

-- Whether bets on this game may show at all (1.1.6: the compliance gate, Compliance.Allows "bet";
-- while it allows none, the betting panels are hidden, not shown empty). A build without the gate
-- (before 1.1.6) shows them as it did.
function ArenaUI.BetsShown(game)
	local G = ns.Compliance
	if type(G) ~= "table" or type(G.Allows) ~= "function" then return true end
	return G.Allows("bet", game) == true
end

-- The markets under the card: a row per market, a button per outcome with its odds (its Bet), the
-- pools and bettors in grey; paged three at a time.
local function Markets(canvas, ev, st)
	local m = rawget(canvas, "markets")
	if not m then
		m = CreateFrame("Frame", nil, canvas)
		m:SetPoint("TOPLEFT", 12, -170)
		m:SetPoint("TOPRIGHT", -12, -170)
		m:SetHeight(92)
		m.rows = {}
		for i = 1, 3 do
			local row = CreateFrame("Frame", nil, m)
			row:SetHeight(26)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
			row:SetPoint("TOPRIGHT", 0, -(i - 1) * 28)
			row.label = Kit.Text(row, nil, "LEFT")
			row.label:SetPoint("LEFT", 4, 0)
			row.label:SetWidth(120)
			row.buttons = {}
			for j = 1, 3 do
				local b = Kit.Button(row, 96, 24, "", nil)
				b:SetPoint("LEFT", row, "LEFT", 128 + (j - 1) * 100, 0)
				row.buttons[j] = b
			end
			m.rows[i] = row
		end
		m.pager = Kit.Button(m, 24, 24, ">", function()
			st.page = ((st.page or 1) % math.max(1, m.pages or 1)) + 1
			ArenaUI.Refresh()
		end)
		m.pager:SetPoint("BOTTOMRIGHT", 0, 0)
		canvas.markets = m
	end
	local view = Data.Markets(ev.id)
	local list = type(view) == "table" and view.markets or {}
	m.pages = math.max(1, math.ceil(#list / 3))
	local page = math.min(st.page or 1, m.pages)
	for i = 1, 3 do
		local row = m.rows[i]
		local mk = list[(page - 1) * 3 + i]
		-- The winner market (MW): its two odds under the card's fighter columns, just the odds (the
		-- name in the tooltip), its word between them (the owner's call, 2026-09-30).
		local winner = mk and mk.type == "MW" and mk.outcomes and #mk.outcomes == 2
		row.label:ClearAllPoints()
		if winner then
			row.label:SetPoint("CENTER", row, "LEFT", ArenaUI.CARD_W / 2, 0)
			row.label:SetJustifyH("CENTER")
		else
			row.label:SetPoint("LEFT", 4, 0)
			row.label:SetJustifyH("LEFT")
		end
		if winner then
			row.label:SetText(ns.Codec.Plain(tostring(mk.label or mk.type or "?")))
			for j = 1, 3 do
				local b, o = row.buttons[j], mk.outcomes[j]
				if o then
					local odds = tonumber(o.odds)
					local idx, oc = mk.idx, o.o
					Kit.SetButton(b, odds and odds > 0 and ("%.2fx"):format(odds) or "-", ArenaUI.MarketOpen(mk), L.ARENA_REFUSE_CLOSED)
					Kit.Fit(b, 80)
					b.tip = ns.Codec.Plain(tostring(o.label or o.o)) .. "\n" .. L.ARENA_MARKET_TIP:format(Kit.Money(o.pool or 0, view.cur), tonumber(o.count) or 0)
					b:SetScript("OnClick", function() ArenaUI.Slip(ev.id, idx, oc) end)
					b:ClearAllPoints()
					if j == 1 then b:SetPoint("LEFT", row, "LEFT", 60, 0) else b:SetPoint("RIGHT", row, "LEFT", ArenaUI.CARD_W - 60, 0) end
					b:Show()
				else
					b:Hide()
				end
			end
			row:Show()
		elseif mk then
			row.label:SetText(ns.Codec.Plain(tostring(mk.label or mk.type or "?")) .. (mk.state and mk.state ~= "o" and (" " .. C("grey", "(" .. tostring(mk.state) .. ")")) or ""))
			-- Each odds button as wide as its words (the owner's rule), side by side from x 128; a
			-- name is cut shorter until the row fits the canvas (the whole of it in the tooltip).
			local room = ArenaUI.CARD_W - 128
			for _, cut in ipairs({ 14, 10, 8, 6 }) do
				local used = 0
				for j = 1, 3 do
					local b = row.buttons[j]
					local o = mk.outcomes and mk.outcomes[j]
					if o then
						local odds = tonumber(o.odds)
						local text = ns.Cut(ns.Codec.Plain(tostring(o.label or o.o)), cut) .. (odds and odds > 0 and (" " .. ("%.2fx"):format(odds)) or "")
						local idx, oc = mk.idx, o.o
						Kit.SetButton(b, text, ArenaUI.MarketOpen(mk), L.ARENA_REFUSE_CLOSED)
						Kit.Fit(b, 60)
						b.tip = ns.Codec.Plain(tostring(o.label or o.o)) .. "\n" .. L.ARENA_MARKET_TIP:format(Kit.Money(o.pool or 0, view.cur), tonumber(o.count) or 0)
						b:SetScript("OnClick", function() ArenaUI.Slip(ev.id, idx, oc) end)
						b:ClearAllPoints()
						if j == 1 then b:SetPoint("LEFT", row, "LEFT", 128, 0) else b:SetPoint("LEFT", row.buttons[j - 1], "RIGHT", 4, 0) end
						b:Show()
						used = used + (tonumber(b:GetWidth()) or 0) + 4
					else
						b:Hide()
					end
				end
				if used - 4 <= room then break end
			end
			row:Show()
		else
			row:Hide()
		end
	end
	m.pager:SetShown(m.pages > 1)
	if #list == 0 then
		m.rows[1]:Show()
		m.rows[1].label:SetText(C("grey", L.ARENA_NO_MARKETS))
		m.rows[1].label:SetWidth(420)
		for _, b in ipairs(m.rows[1].buttons) do b:Hide() end
	else
		m.rows[1].label:SetWidth(120)
	end
	-- (When bets close: the card's clock above says it, once.)
	-- Your bets on it, one line.
	local mine, total = 0, 0
	for _, t in ipairs(Data.Tickets({ eid = ev.id }) or {}) do
		if type(t) == "table" and (t.eid == nil or t.eid == ev.id) then
			mine = mine + 1
			total = total + (tonumber(t.copper) or (tonumber(t.silver) or 0) * 100)
		end
	end
	m.mine = rawget(m, "mine") or Kit.Text(m, nil, "RIGHT")
	m.mine:ClearAllPoints()
	m.mine:SetPoint("BOTTOMRIGHT", -30, 4)
	m.mine:SetText(mine > 0 and L.ARENA_YOUR_BETS:format(mine, Kit.Money(total, type(view) == "table" and view.cur or nil)) or "")
	m:Show()
end

local function EventDetail(canvas, st)
	local ev = EventOf(st)
	local card = rawget(canvas, "card")
	if not card then
		-- The selected match in its own inset panel, 12 px inside (the owner's call, 2026-09-30).
		canvas.inset = Kit.Inset(canvas)
		card = CreateFrame("Frame", nil, canvas)
		card:SetPoint("TOPLEFT", 12, -12)
		card:SetSize(ArenaUI.CARD_W, 150)
		canvas.card = card
	end
	local markets = rawget(canvas, "markets")
	if not ev then
		if ArenaUI.Card then ArenaUI.Card.Build(card, nil, "compact") end
		if markets then markets:Hide() end
		return
	end
	if ArenaUI.Card then ArenaUI.Card.Build(card, ev.id, "compact") end
	-- (1.1.6: no markets panel at all while the compliance gate allows no bet on a fight)
	if ev.kind == "fight" and ev.public ~= false and ArenaUI.BetsShown("fight") then
		Markets(canvas, ev, st)
	elseif markets then
		markets:Hide()
	end
end

local function EventButtons(st)
	local ev = EventOf(st)
	local list = {}
	if not ev then
		list[1] = { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end }
		return list
	end
	local id = ev.id
	if ev.kind == "tourney" then
		local okSign, why = ns.Arena.Can("tourney.sign", id)
		list[1] = { L.ARENA_BRACKET, function() if ArenaUI.Bracket then ArenaUI.Bracket.Open(id) end end }
		list[2] = { L.ARENA_REGISTER, function() ArenaUI.Commit("tourney.sign", id) end, enabled = okSign or why == "rules", why = Kit.Why(why) }
	else
		list[1] = { L.ARENA_TALE, function() if ArenaUI.Card then ArenaUI.Card.Open(id) end end }
		local n = #(Data.ChatLines(id) or {})
		list[2] = { L.ARENA_FIGHT_CHAT:format(n), function() if ArenaUI.OpenFightChat then ArenaUI.OpenFightChat(id) end end }
	end
	list[3] = { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end }
	return list
end

local function EventsCopy(st)
	local out = {}
	for _, ev in ipairs(Data.Events() or {}) do
		out[#out + 1] = Home.EventTitle(ev) .. "  " .. Home.StateWord(ev)
	end
	local ev = EventOf(st)
	local view = ev and Data.Markets(ev.id)
	if type(view) == "table" then
		out[#out + 1] = ""
		for _, mk in ipairs(view.markets or {}) do
			local parts = {}
			for _, o in ipairs(mk.outcomes or {}) do
				parts[#parts + 1] = ("%s %.2fx (%s, %d)"):format(tostring(o.label or o.o), tonumber(o.odds) or 0, Kit.Money(o.pool or 0, view.cur), tonumber(o.count) or 0)
			end
			out[#out + 1] = tostring(mk.label or mk.type) .. ": " .. table.concat(parts, " | ")
		end
	end
	return table.concat(out, "\n")
end

ArenaUI.RegisterPane("arena.events", { section = "arena", label = L.ARENA_PANE_EVENTS, order = 1,
	lines = EventsLines, text = EventText, buttons = EventButtons, detail = EventDetail, copy = EventsCopy })

-- Find an opponent (the design): matchmaking's action, which opens the Find dialog (ArenaUI.OpenFind) when the
-- companion has it.
function ArenaUI.FindOpponent(game)
	game = game == "b" and "b" or "d"
	if game == "b" and ns.FarkleTable then
		if not ns.FarkleTable.CanPlayPlayers() then ArenaUI.Say(L.FARKLE_LOBBY_FIRST); return false, "training" end
		if not ns.FarkleTable.CanOpen() then ArenaUI.Say(L.FARKLE_LOG_TAVERN_REST); return false, "tavern-rest" end
	end
	local ok, why = ns.Arena.Do("match.open", game)
	if not ok then
		if why == "unknown" and ArenaUI.OpenFind then return ArenaUI.OpenFind(game) end
		ArenaUI.Say(Kit.Why(why))
	end
	return ok
end

---------------------------------------------------------------------------
-- Arena: Rankings, one compact switchable view
---------------------------------------------------------------------------

local CLASSES = { "WA", "PA", "HU", "RO", "PR", "SH", "MA", "WL", "DR" }
local RACES = { 1, 3, 4, 7, 2, 5, 6, 8 }
ArenaUI.RANK_CLASSES, ArenaUI.RANK_RACES = CLASSES, RACES
-- The chosen view: remembered (period, kind, the class or race in view, the page).
function ArenaUI.RankChoice()
	return {
		period = Kit.Recall("rank.period", "week"), kind = Kit.Recall("rank.kind", "global"),
		class = Kit.Recall("rank.class", 1), race = Kit.Recall("rank.race", 1), page = Kit.Recall("rank.page", 1),
	}
end
function ArenaUI.RankCat(choice)
	choice = choice or ArenaUI.RankChoice()
	if choice.kind == "class" then return "C" .. CLASSES[math.max(1, math.min(#CLASSES, tonumber(choice.class) or 1))] end
	if choice.kind == "race" then return "R" .. RACES[math.max(1, math.min(#RACES, tonumber(choice.race) or 1))] end
	return "A"
end
function ArenaUI.RankView()
	local c = ArenaUI.RankChoice()
	return Data.Rankings(c.period, ArenaUI.RankCat(c), c.page) or { rows = {} }, c
end
function ArenaUI.SetRank(key, value)
	Kit.Remember("rank." .. key, value)
	if key ~= "page" then Kit.Remember("rank.page", 1) end
	ArenaUI.Refresh()
end

local PERIOD_LABELS = { today = "ARENA_PERIOD_TODAY", week = "ARENA_PERIOD_WEEK", month = "ARENA_PERIOD_MONTH", all = "ARENA_PERIOD_ALL" }

-- The honours' small marks (Olympus/media/honours, the Frame Lab's art): the arena champion's
-- gryphon for the overall ranking, a class's animal, a race's mount; gold, silver, bronze.
local HONOURS = "Interface\\AddOns\\Olympus\\media\\honours\\"
local CLASS_MARK = { WA = "boar", PA = "paladin", HU = "hunter", RO = "rogue", PR = "priest", SH = "shaman", MA = "mage", WL = "warlock", DR = "druid" }
local RACE_MARK = { [1] = "lion", [2] = "orc-wolf", [3] = "ram", [4] = "nightsaber", [5] = "skeletal-horse", [6] = "kodo", [7] = "mechanostrider", [8] = "raptor" }
local PLACE_TIER = { "gold", "silver", "bronze" }
-- The mark of place `rank` in category `cat` ("A", "CMA", "R4"), or nil (the division's icon then).
function ArenaUI.RankMark(cat, rank)
	local tier = PLACE_TIER[tonumber(rank) or 0]
	if not tier then return nil end
	local animal
	if cat == "A" or cat == nil then animal = "gryphon"
	elseif cat:sub(1, 1) == "C" then animal = CLASS_MARK[cat:sub(2)]
	elseif cat:sub(1, 1) == "R" then animal = RACE_MARK[tonumber(cat:sub(2))] end
	return animal and (HONOURS .. animal .. "-" .. tier .. "-mark") or nil
end
-- A fighter's class code and file (the name's colour, the podium's portrait).
local function RankClass(x)
	local class = x.class
	if not class and x.name then
		local p = Data.Profile(x.name)
		class = type(p) == "table" and Kit.V(p.class) or nil
	end
	return ArenaUI.ClassFile and ArenaUI.ClassFile(class) or class
end
local CLASS_TCOORDS = rawget(_G, "CLASS_ICON_TCOORDS")
local function ClassIcon(file, size)
	local c = CLASS_TCOORDS and CLASS_TCOORDS[file]
	if not c then return "" end
	return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(size, size, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- Rankings (the owner's design, 2026-09-30; after build 7, the arena's structure on every tab):
-- in the grey block the filters (the period as a segmented control: Today, Week, Month, All time;
-- the category as a dropdown: Overall, each class with its icon, each race) and the ranked list
-- (rank, the honour's mark for 1-3 or the division's icon, the name in its class colour, the
-- rating and W-L; the player's own row lit, or pinned at the foot); on the parchment the podium
-- for places 1-3 (gold in the centre and raised, silver left, bronze right: the portrait in the
-- honour's frame, the name, the rating and the record) and the selected fighter's summary; the
-- empty state in words, centred.
local function RankHead(parent)
	local r = CreateFrame("Frame", nil, parent)
	-- (both filters are dropdowns, one over the other, inside the grey block: the owner after build 7)
	r.period = Kit.Button(r, 160, 24, "", function(self)
		local items = {}
		for _, per in ipairs(Home.PERIODS) do
			local key = per
			items[#items + 1] = { L[PERIOD_LABELS[per]], function() ArenaUI.SetRank("period", key) end }
		end
		ArenaUI.Menu(self, items)
	end)
	r.period:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.category = Kit.Button(r, 200, 24, "", function(self)
		local items = { { L.ARENA_CAT_GLOBAL, function() Kit.Remember("rank.kind", "global") ArenaUI.SetRank("page", 1) end } }
		for i, code in ipairs(CLASSES) do
			items[#items + 1] = { ClassIcon(ArenaUI.ClassFile(code), 14) .. (ArenaUI.ClassWord(code) or code), function()
				Kit.Remember("rank.kind", "class") Kit.Remember("rank.class", i) ArenaUI.SetRank("page", 1) end }
		end
		for i, id in ipairs(RACES) do
			items[#items + 1] = { ArenaUI.RaceWord and ArenaUI.RaceWord(id) or tostring(id), function()
				Kit.Remember("rank.kind", "race") Kit.Remember("rank.race", i) ArenaUI.SetRank("page", 1) end }
		end
		ArenaUI.Menu(self, items)
	end)
	-- (side by side on one line, 8 px apart, each as wide as its longest choice; the page arrows
	-- under them, at the right: the owner after build 7)
	r.category:SetPoint("LEFT", r.period, "RIGHT", 8, 0)
	r.prev = Kit.Button(r, 32, 24, "<", function() local c = ArenaUI.RankChoice() ArenaUI.SetRank("page", math.max(1, (tonumber(c.page) or 1) - 1)) end)
	r.next = Kit.Button(r, 32, 24, ">", function() local c = ArenaUI.RankChoice() ArenaUI.SetRank("page", (tonumber(c.page) or 1) + 1) end)
	r.next:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -30)
	r.prev:SetPoint("RIGHT", r.next, "LEFT", -4, 0)
	return r
end
local function RankHeadRefresh(r)
	local view, c = ArenaUI.RankView()
	local ARROW = "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12:0:0|t"
	Kit.SetButton(r.period, (L[PERIOD_LABELS[c.period] or "ARENA_PERIOD_ALL"] or c.period) .. ARROW, true)
	-- (each dropdown as wide as its longest choice, so it never jumps: measured once)
	if not rawget(r, "periodW") then
		local widest = 0
		for _, per in ipairs(Home.PERIODS) do
			r.period:SetText((L[PERIOD_LABELS[per]] or per) .. ARROW)
			local fs = r.period.GetFontString and r.period:GetFontString()
			widest = math.max(widest, tonumber(fs and fs.GetStringWidth and fs:GetStringWidth() or 0) or 0)
		end
		r.periodW = math.max(110, math.ceil(widest) + 24)
		r.period:SetText((L[PERIOD_LABELS[c.period] or "ARENA_PERIOD_ALL"] or c.period) .. ARROW)
	end
	r.period:SetWidth(r.periodW)
	local cat = ArenaUI.RankCat(c)
	Kit.SetButton(r.category, ArenaUI.CatWords(cat, view) .. "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12:0:0|t", true)
	-- (the category: the rest of the line, the block's width less the period's and the gap)
	r.category:SetWidth(math.max(110, ArenaUI.LIST_W - 12 - (rawget(r, "periodW") or 120) - 8))
	local page, pages = tonumber(view.page) or 1, tonumber(view.pages) or 1
	Kit.SetButton(r.prev, nil, page > 1)
	Kit.SetButton(r.next, nil, page < pages)
	r.prev.tip, r.next.tip = L.ARENA_PAGE:format(page, pages), L.ARENA_PAGE:format(page, pages)
end
local function Rating(x) return x.rating and ns.FormatNumber(math.floor(x.rating + 0.5)) or "-" end
local ARROW_UP, ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t", "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"
local function Change(n)
	n = tonumber(n)
	if not n or n == 0 then return "" end
	return n > 0 and (ARROW_UP .. C("green", "+" .. n)) or (ARROW_DOWN .. C("red", tostring(n)))
end
-- The ranked list, in the grey block.
local function RankLines(st)
	local view, c = ArenaUI.RankView()
	local cat = ArenaUI.RankCat(c)
	local lines = {}
	local rows = view.rows or {}
	local mineGk = view.mine and view.mine.gk
	local mineShown = false
	for i, x in ipairs(rows) do
		local rank = tonumber(x.rank) or i
		local mark = ArenaUI.RankMark(cat, rank)
		local icon = mark and ("|T" .. mark .. ":16:16|t") or Kit.TierMark(x.tier, 16)
		local name = Kit.Colored(x.name or x.gk or "?", RankClass(x))
		if mineGk and mineGk == x.gk then mineShown = true name = name .. "  " .. C("blue", L.ARENA_RANK_YOU) end
		if Data.OpenBet(x.name) then name = name .. " " .. C("red", L.ARENA_OPEN_BET_MARK) end
		local who = x.name
		lines[#lines + 1] = { text = ("#%d  %s %s"):format(rank, icon, name), key = who, player = who,
			right = Rating(x) .. "  " .. C("grey", ("%d-%d"):format(tonumber(x.wins) or 0, tonumber(x.losses) or 0)),
			onClick = function() ArenaUI.Select("arena.rankings", who) end }
	end
	if #rows == 0 then lines[#lines + 1] = { text = C("grey", view.loaded == false and L.ARENA_RANK_LOADING or L.ARENA_RANK_EMPTY) } end
	local mine = view.mine
	if mine and not mineShown then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = C("blue", L.ARENA_RANK_MINE:format(tonumber(mine.rank) or 0, tonumber(mine.rating) and math.floor(mine.rating + 0.5) or 0)) }
	end
	return lines
end
-- The podium and the selected fighter, on the parchment.
local function Podium(r, i, size)
	local p = { size = size }
	-- (the portrait drawn as the player's own, Kit.NewPortrait; its place's mark over its art)
	p.rig = Kit.NewPortrait(r, size)
	p.portrait = p.rig.slot
	p.mark = p.rig.top:CreateTexture(nil, "OVERLAY", nil, 2)
	p.mark:SetSize(22, 22)
	p.name = Kit.Text(r, "title", "CENTER")
	p.name:SetWidth(170)
	if p.name.SetWordWrap then p.name:SetWordWrap(false) end
	p.stats = Kit.Text(r, nil, "CENTER")
	p.stats:SetWidth(170)
	p.button = CreateFrame("Button", nil, r)
	p.button:SetAllPoints(p.portrait)
	p.button:SetScript("OnClick", function(self) local who = rawget(self, "who") if who then ArenaUI.Select("arena.rankings", who) end end)
	r.podium[i] = p
	return p
end
local function RankDetail(canvas, st)
	local r = rawget(canvas, "rank")
	if not r then
		r = CreateFrame("Frame", nil, canvas)
		r:SetAllPoints(canvas)
		canvas.rank = r
		r.podium = {}
		local mid = ArenaUI.DETAIL_W / 2
		for i, sp in ipairs({ { mid, 48, 64 }, { mid - 180, 68, 52 }, { mid + 180, 68, 52 } }) do
			local p = Podium(r, i, sp[3])
			p.portrait:SetPoint("TOP", r, "TOPLEFT", sp[1], -sp[2])
			p.mark:SetPoint("BOTTOMRIGHT", p.portrait, "BOTTOMRIGHT", 6, -6)
			p.name:SetPoint("TOP", r, "TOPLEFT", sp[1], -(sp[2] + sp[3] + 22))
			p.stats:SetPoint("TOP", p.name, "BOTTOM", 0, -4)
		end
		-- (over the first place's art, which reaches above its portrait)
		r.crown = r.podium[1].rig.top:CreateTexture(nil, "OVERLAY")
		r.crown:SetSize(22, 22)
		r.crown:SetPoint("BOTTOM", r.podium[1].portrait, "TOP", 0, 10)
		r.crown:SetTexture("Interface\\Icons\\INV_Crown_01")
		r.belt = Kit.Text(r, "small", "CENTER")
		r.belt:SetPoint("TOP", r, "TOP", 0, -12)
		r.belt:SetWidth(ArenaUI.DETAIL_W - 32)
		-- the selected fighter: a line under the podium, then his summary
		r.rule = r:CreateTexture(nil, "BORDER")
		r.rule:SetColorTexture(0.25, 0.13, 0.04, 0.3)
		r.rule:SetPoint("TOPLEFT", 16, -232); r.rule:SetPoint("TOPRIGHT", -16, -232); r.rule:SetHeight(1)
		-- (its portrait drawn as the player's own, Kit.NewPortrait: its art kept inside the canvas,
		-- under the line and clear of the name, Borders.PortraitReach)
		local reach = Kit.PortraitReach(48)
		local outL, outR, up = reach.left, reach.right, reach.top
		r.pickRig = Kit.NewPortrait(r, 48)
		r.pick = r.pickRig.slot
		r.pick:SetPoint("TOPLEFT", 4 + outL, -(236 + up))
		r.pickName = Kit.Text(r, "title", "LEFT")
		r.pickName:SetPoint("TOPLEFT", r.pick, "TOPRIGHT", 12 + outR, -2)
		r.pickName:SetWidth(ArenaUI.DETAIL_W - (4 + outL + 48 + 12 + outR) - 16)
		r.pickText = Kit.Text(r, nil, "LEFT")
		r.pickText:SetPoint("TOPLEFT", r.pickName, "BOTTOMLEFT", 0, -6)
		r.pickText:SetWidth(ArenaUI.DETAIL_W - (4 + outL + 48 + 12 + outR) - 16)
		if r.pickText.SetJustifyV then r.pickText:SetJustifyV("TOP") end
		r.empty = Kit.Text(r, nil, "CENTER")
		r.empty:SetPoint("CENTER", r, "CENTER", 0, 0)
		r.empty:SetWidth(ArenaUI.DETAIL_W - 64)
	end
	local view, c = ArenaUI.RankView()
	local cat = ArenaUI.RankCat(c)
	local rows = view.rows or {}
	local page = tonumber(view.page) or 1
	local beltLine = ""
	for _, b in ipairs(Data.Belts() or {}) do
		if type(b) == "table" and (b.cat == cat or b.category == cat) and (b.holder or b.name) then
			beltLine = L.ARENA_BELT_HOLDER:format(ArenaUI.CatWords(cat, view), Name(b.holder or b.name), tonumber(b.defences or b.def) or 0)
		end
	end
	r.belt:SetText(beltLine)
	local onPodium = page == 1 and math.min(3, #rows) or 0
	for i, p in ipairs(r.podium) do
		local x = i <= onPodium and rows[i] or nil
		for _, part in ipairs({ p.portrait, p.mark, p.name, p.stats, p.button }) do part:SetShown(x ~= nil) end
		if x then
			local file = RankClass(x)
			Kit.DrawPortrait(p.rig, x.name, { class = file, guild = x.guild, honour = cat == "A" and ("arena-champion-" .. i) or nil })
			local mark = ArenaUI.RankMark(cat, i)
			p.mark:SetTexture(mark)
			p.mark:SetShown(mark ~= nil)
			p.name:SetText(Kit.Colored(x.name or x.gk or "?", file))
			p.stats:SetText(("%s  ·  %d-%d"):format(Rating(x), tonumber(x.wins) or 0, tonumber(x.losses) or 0))
			p.button.who = x.name
		end
	end
	r.crown:SetShown(onPodium >= 1)
	-- the selected fighter (the first of the page when none is picked)
	local pick
	for _, x in ipairs(rows) do if x.name and x.name == st.sel then pick = x end end
	pick = pick or rows[1]
	for _, part in ipairs({ r.rule, r.pick, r.pickName, r.pickText }) do part:SetShown(pick ~= nil) end
	if pick then
		local file = RankClass(pick)
		Kit.DrawPortrait(r.pickRig, pick.name, { class = file, guild = pick.guild, honour = pick.honour })
		r.pickName:SetText(("#%d  %s"):format(tonumber(pick.rank) or 0, Kit.Colored(pick.name or pick.gk or "?", file)))
		local st2 = tonumber(pick.streak)
		local out = {
			L.ARENA_RANK_PICK_RATING:format(Rating(pick), c.period ~= "all" and Change(pick.delta) or ""),
			L.ARENA_RANK_PICK_RECORD:format(tonumber(pick.wins) or 0, tonumber(pick.losses) or 0),
		}
		if pick.tier then out[#out + 1] = Kit.TierMark(pick.tier, 14) .. " " .. (L["ARENA_TIER_" .. tostring(pick.tier):upper()] or tostring(pick.tier)) end
		if st2 and st2 ~= 0 then out[#out + 1] = L.ARENA_RANK_PICK_STREAK:format(st2 > 0 and C("green", "W" .. st2) or C("red", "L" .. -st2)) end
		r.pickText:SetText(table.concat(out, "\n"))
	end
	-- the empty state, centred on the parchment
	r.empty:SetShown(#rows == 0)
	r.empty:SetText(#rows == 0 and C("grey", view.loaded == false and L.ARENA_RANK_LOADING or L.ARENA_RANK_EMPTY) or "")
end

-- The words of a category ("Mage", "Night Elf", "Global").
function ArenaUI.CatWords(cat, view)
	if type(view) == "table" and type(view.label) == "string" and view.cat == cat then return ns.Codec.Plain(view.label) end
	local LG = ns.ArenaLedger
	if type(LG) == "table" and type(LG.CatLabel) == "function" then
		local ok, label = pcall(LG.CatLabel, cat)
		if ok and type(label) == "string" then return label end
	end
	if cat == "A" then return L.ARENA_CAT_GLOBAL end
	return cat
end

local function Sign(n)
	n = tonumber(n)
	if not n or n == 0 then return "" end
	return n > 0 and C("green", "+" .. n) or C("red", tostring(n))
end
local function RankCopy()
	local view, c = ArenaUI.RankView()
	local out = { L.ARENA_RANK_COPY:format(ArenaUI.CatWords(ArenaUI.RankCat(c), view), L[PERIOD_LABELS[c.period] or "ARENA_PERIOD_ALL"]) }
	-- (Copy gives the top 25: the pages of this view up to there.)
	local rows = {}
	for page = 1, 3 do
		local v = Data.Rankings(c.period, ArenaUI.RankCat(c), page) or {}
		for _, x in ipairs(v.rows or {}) do if #rows < 25 then rows[#rows + 1] = x end end
		if (tonumber(v.pages) or 1) <= page then break end
	end
	for i, x in ipairs(rows) do
		out[#out + 1] = ("%d. %s  %s  %d-%d"):format(tonumber(x.rank) or i, Name(x.name or x.gk), x.rating and tostring(math.floor(x.rating + 0.5)) or "-", tonumber(x.wins) or 0, tonumber(x.losses) or 0)
	end
	return table.concat(out, "\n")
end
ArenaUI.RegisterPane("arena.rankings", { section = "arena", label = L.ARENA_PANE_RANKINGS, order = 2,
	head = RankHead, headRefresh = RankHeadRefresh, headH = 58,
	lines = RankLines, detail = RankDetail, copy = RankCopy,
	text = function() return L.ARENA_RANK_TITLE, L.ARENA_RANK_TEXT end,
	buttons = function(st) return { { L.ARENA_BTN_MY_PROFILE, function() ArenaUI.ShowProfile(nil) end }, { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end },
		st and st.sel and { L.ARENA_BTN_PROFILE_OF or L.ARENA_BTN_MY_PROFILE, function() ArenaUI.ShowProfile(st.sel) end } or nil } end })

-- Fight-history helpers. History has exactly one surface: the Arena Profile below.
---------------------------------------------------------------------------

local function When(t)
	t = tonumber(t)
	if not t or not date then return "" end
	return date("%m-%d", t)
end
local function HistoryMine() return Kit.Recall("history.mine", true) ~= false end

---------------------------------------------------------------------------
-- Arena: Profile (his own, or anyone's from a click on a name)
---------------------------------------------------------------------------

local profileReturn
local function ProfileIdentity(name)
	if type(name) ~= "string" then return nil end
	name = name:match("^%s*(.-)%s*$")
	if name == "" then return nil end
	name = ns.FullName(ns.Normal(name))
	if Same(name, ns.me) then return nil end
	return name
end
ArenaUI.ProfileIdentity = ProfileIdentity
function ArenaUI.ShowProfile(name)
	name = ProfileIdentity(name)
	if name then
		local route = ArenaUI.CurrentRoute and ArenaUI.CurrentRoute()
		if route and route.pane ~= "arena.profile" then profileReturn = route end
	else
		profileReturn = nil
	end
	return ArenaUI.ShowPane("arena.profile", name or false)
end
function ArenaUI.BackFromProfile()
	local route = profileReturn
	profileReturn = nil
	if route and ArenaUI.RestoreRoute and ArenaUI.RestoreRoute(route) then return true end
	return ArenaUI.ShowProfile(nil)
end
local function ProfileName(st) return type(st.sel) == "string" and st.sel ~= "" and st.sel or nil end
local V = Kit.V

-- The profile in words: each value with "seen", "self-reported" or "arbiter" beside it where it can
-- be checked (fighter-card research, claims c01-c33).
local SRC_WORDS = { seen = "ARENA_SRC_SEEN", own = "ARENA_SRC_OWN", arbiter = "ARENA_SRC_ARBITER", ledger = "ARENA_SRC_LEDGER", verified = "ARENA_SRC_VERIFIED" }
function ArenaUI.SourceTag(x)
	if type(x) ~= "table" or not x.src then return "" end
	local key = SRC_WORDS[x.src]
	return key and (" " .. C("grey", "(" .. L[key] .. ")")) or ""
end
local function Record(rec)
	rec = V(rec)
	if type(rec) ~= "table" then return nil end
	return ("%d-%d%s"):format(tonumber(rec.wins) or 0, (tonumber(rec.losses) or 0) + (tonumber(rec.fled) or 0), (tonumber(rec.draws) or 0) > 0 and ("-" .. rec.draws) or "")
end
ArenaUI.RecordText = Record

function ArenaUI.ProfileModel(name)
	local p = name and Data.Profile(name) or nil
	local mine = not name
	if mine then
		local vm = Data.MyProfile()
		p = Data.Profile(ns.me) or {}
		if type(vm) == "table" then
			p.vm = vm
			if vm.pub ~= nil then p.pub = vm.pub end
			if vm.emblem and not V(p.emblem) then p.emblem = vm.emblem end
		end
	end
	if type(p) ~= "table" then return nil end
	local m = { name = V(p.name) or name or ns.me, mine = mine }
	local fights = ns.ArenaFights
	if mine and type(fights) == "table" and type(fights.Qualification) == "function" then
		local q = fights.Qualification()
		if type(q) == "table" and type(q.pointsTenths) == "number" then
			m.qualification = q
			local points = ns.FormatNumber(math.floor(q.pointsTenths / 10)) .. L.ARENA_QUAL_DECIMAL .. tostring(q.pointsTenths % 10)
			m.qualificationText = L.ARENA_QUAL_POINTS:format(points)
		end
	end
	m.nick = V(p.nick)
	m.emblem = V(p.emblem)
	m.title = V(p.title)
	m.record = Record(p.record)
	m.rating = tonumber(V(p.rating))
	m.tier = V(p.tier)
	m.pub = p.pub == true
	m.openBet = Data.OpenBet(m.name)
	m.lines = {}
	local function Add(label, x, text)
		if text == nil then return end
		m.lines[#m.lines + 1] = C("grey", label .. ": ") .. text .. ArenaUI.SourceTag(x)
	end
	Add(L.ARENA_CARD_RECORD, p.record, m.record)
	Add(L.ARENA_CARD_RATING, p.rating, m.rating and tostring(math.floor(m.rating + 0.5)) or nil)
	local tier = m.tier
	Add(L.ARENA_CARD_TIER, p.tier, tier and (Kit.TierMark(tier) .. " " .. (L["ARENA_TIER_" .. tostring(tier):upper()] or tier)) or nil)
	local cls, race, lvl = V(p.class), V(p.race), V(p.level)
	if cls or race or lvl then
		local identity = {}
		local classWord, raceWord = ArenaUI.ClassWord(cls), ArenaUI.RaceWord(race)
		if classWord then identity[#identity + 1] = classWord end
		if raceWord then identity[#identity + 1] = raceWord end
		if lvl then identity[#identity + 1] = tostring(lvl) end
		Add(L.ARENA_CARD_CLASS, p.class or p.race or p.level, table.concat(identity, " · "))
	end
	local belts = V(p.belts)
	if type(belts) == "table" and next(belts) then
		local words = {}
		for k, v in pairs(belts) do words[#words + 1] = ArenaUI.CatWords(type(v) == "string" and v or (type(k) == "string" and k) or "A") end
		table.sort(words)
		Add(L.ARENA_CARD_BELTS, p.belts, table.concat(words, ", "))
	end
	if m.openBet then m.lines[#m.lines + 1] = C("red", L.ARENA_OPEN_BET) end
	m.history = mine and (m.pub and L.ARENA_HISTORY_PUBLIC_WORD or L.ARENA_HISTORY_PRIVATE_WORD)
		or (m.pub and L.ARENA_HISTORY_THEIRS_PUBLIC or L.ARENA_HISTORY_THEIRS_PRIVATE)
	-- (the profile page's blocks, 2026-09-30: the class, race, level, guild and its rank, the honour
	-- worn, and the stats beyond the fights; the sim's sample data has them all)
	m.class, m.race, m.level = cls, race, lvl
	m.gender = V(p.gender or p.sex)
	m.guild, m.guildRank = V(p.guild), V(p.guildRank)
	m.honour = V(p.honour)
	m.stats = V(p.stats)
	m.belts = belts
	return m
end

-- A class, a race in words (the client's own names where it has them).
local CLASS_FILE = { WA = "WARRIOR", PA = "PALADIN", HU = "HUNTER", RO = "ROGUE", PR = "PRIEST", SH = "SHAMAN", MA = "MAGE", WL = "WARLOCK", DR = "DRUID" }
function ArenaUI.ClassWord(x)
	if type(x) ~= "string" then return nil end
	local file = CLASS_FILE[x] or x:upper()
	local names = LOCALIZED_CLASS_NAMES_MALE
	return type(names) == "table" and names[file] or (file:sub(1, 1) .. file:sub(2):lower())
end
function ArenaUI.ClassFile(x) return type(x) == "string" and (CLASS_FILE[x] or x:upper()) or nil end
local RACE_WORDS = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }
function ArenaUI.RaceWord(x)
	local id = tonumber(x)
	if id and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
		local ok, r = pcall(C_CreatureInfo.GetRaceInfo, id)
		if ok and type(r) == "table" and type(r.raceName) == "string" then return r.raceName end
	end
	if id then return RACE_WORDS[id] end
	return type(x) == "string" and x or nil
end

-- The profile (the owner's page, 2026-09-30, the arena's structure): in the grey block the stat
-- blocks (Fights, Bones, Lottery, Donations, Ranking places, Tabard, Usually online), each a
-- header and its lines; on the parchment the portrait in the honour's frame (the live portrait
-- where he is near, else a token: his race's portrait where the client has it, else his class's
-- icon), the name, the title, the guild and its rank, class, race and level. The player's own
-- page: Visibility opens the privacy page's Profile lines.
local PROFILE_BLOCKS = { "ARENA_PROF_FIGHTS", "ARENA_PROF_BONES", "ARENA_PROF_LOTTERY", "ARENA_PROF_DONATIONS", "ARENA_PROF_PLACES", "ARENA_PROF_TABARD", "ARENA_PROF_ONLINE" }
local function ProfileHistory(m)
	local mine = m.mine and HistoryMine()
	local all = Data.History({ mine = mine, limit = 30 }) or {}
	if m.mine then return all end
	if not m.pub then return {} end
	local out, who = {}, tostring(m.name or ""):lower()
	for _, row in ipairs(all) do
		local a, b = tostring(row.A or ""):lower(), tostring(row.B or ""):lower()
		if a == who or b == who or Same(row.A, m.name) or Same(row.B, m.name) then
			out[#out + 1] = row
			if #out >= 5 then break end
		end
	end
	return out
end
local function ToggleProfileHistory()
	Kit.Remember("history.mine", not HistoryMine())
	ArenaUI.Select("arena.profile.history", nil)
end
local function ProfileFightId(fight, i) return fight.fid or fight.id or i end
local function SelectProfileFight(m, fid)
	ArenaUI.Select("arena.profile.history", { profile = m.name, fid = fid })
end
local function ProfileSelectedFight(m, fights)
	local selected = ArenaUI.Selected("arena.profile.history")
	if type(selected) == "table" and Same(selected.profile, m.name) then
		for i, fight in ipairs(fights) do
			if ProfileFightId(fight, i) == selected.fid then return fight end
		end
	end
	local newest
	for _, fight in ipairs(fights) do
		if not newest or (tonumber(fight.t) or 0) > (tonumber(newest.t) or 0) then newest = fight end
	end
	return newest
end
local function FightDetailText(fight)
	if not fight then return C("grey", L.ARENA_HISTORY_EMPTY) end
	local winner = Name(fight.winner)
	local loser = Name(Same(fight.winner, fight.A) and fight.B or fight.A)
	local lines = {
		C("gold", L.ARENA_DEFEATED:format(winner, loser)),
		L.ARENA_HISTORY_WHEN:format(date and date("%Y-%m-%d %H:%M", tonumber(fight.t) or 0) or ""),
	}
	if fight.dur then lines[#lines + 1] = L.ARENA_HISTORY_DUR:format(Home.Clock(fight.dur)) end
	if tonumber(fight.stake) then lines[#lines + 1] = L.ARENA_HISTORY_STAKE:format(Kit.Money(fight.stake, fight.cur)) end
	if fight.cat then lines[#lines + 1] = L.ARENA_HISTORY_CAT:format(ArenaUI.CatWords(fight.cat)) end
	if fight.delta then lines[#lines + 1] = L.ARENA_HISTORY_DELTA:format(Sign(fight.delta)) end
	if fight.title then lines[#lines + 1] = C("red", L.ARENA_HISTORY_TITLE_FIGHT) end
	return table.concat(lines, "\n")
end
local function ProfileLines(st)
	local m = ArenaUI.ProfileModel(ProfileName(st))
	if not m then return { { text = C("grey", L.ARENA_PROFILE_NONE) } } end
	local stats = type(m.stats) == "table" and m.stats or {}
	local lines = {}
	local function Head(key, right) lines[#lines + 1] = { header = true, text = L[key], right = right } end
	local function Row(label, value) lines[#lines + 1] = { indent = 1, text = C("grey", label), right = value } end
	local function None(word) lines[#lines + 1] = { indent = 1, text = C("grey", word) } end
	local function Close() if #lines > 0 then lines[#lines].gapAfter = true end end
	-- Fights
	Head("ARENA_PROF_FIGHTS", m.rating and tostring(math.floor(m.rating + 0.5)) or nil)
	if m.qualificationText then
		lines[#lines + 1] = { indent = 1, text = C("grey", L.ARENA_QUAL_LABEL), right = m.qualificationText,
			tooltip = function(tt)
				tt:AddLine(L.ARENA_QUAL_LABEL, 1, 0.82, 0)
				tt:AddLine(L.ARENA_QUAL_TIP, 1, 1, 1, true)
				local last = m.qualification[#m.qualification]
				if last then
					local mine = last.mine == "A" and last.levelA or last.levelB
					local theirs = last.mine == "A" and last.levelB or last.levelA
					tt:AddLine(L.ARENA_QUAL_LAST:format(mine, theirs), 1, 1, 1, true)
				end
			end }
	end
	if m.record then Row(L.ARENA_CARD_RECORD, m.record) end
	if m.tier then Row(L.ARENA_CARD_TIER, Kit.TierMark(m.tier, 14) .. " " .. (L["ARENA_TIER_" .. tostring(m.tier):upper()] or tostring(m.tier))) end
	if tonumber(stats.streak) and stats.streak ~= 0 then Row(L.ARENA_PROF_STREAK, stats.streak > 0 and C("green", "W" .. stats.streak) or C("red", "L" .. -stats.streak)) end
	if type(m.belts) == "table" and next(m.belts) then
		local words = {}
		for k, v in pairs(m.belts) do words[#words + 1] = ArenaUI.CatWords(type(v) == "string" and v or (type(k) == "string" and k) or "A") end
		table.sort(words)
		Row(L.ARENA_CARD_BELTS, table.concat(words, ", "))
	end
	local fights = ProfileHistory(m)
	if m.openBet then lines[#lines + 1] = { indent = 1, text = C("red", L.ARENA_OPEN_BET) } end
	lines[#lines + 1] = { header = true, text = L.ARENA_HISTORY_TITLE,
		right = m.mine and (HistoryMine() and L.ARENA_HISTORY_MINE or L.ARENA_HISTORY_RECENT) or nil,
		onClick = m.mine and ToggleProfileHistory or nil }
	if #fights == 0 then None(L.ARENA_HISTORY_EMPTY) end
	for i, fight in ipairs(fights) do
		local text, right
		if m.mine and HistoryMine() then
			local opp = fight.private and L.ARENA_PRIVATE_FIGHTER or Name(fight.opponent or (Same(fight.A, m.name) and fight.B or fight.A))
			text = (fight.won and C("green", L.ARENA_WON) or C("red", L.ARENA_LOST)) .. " " .. L.ARENA_VS_SHORT:format(opp)
		elseif m.mine then
			text = L.ARENA_DEFEATED:format(Name(fight.winner), Name(Same(fight.winner, fight.A) and fight.B or fight.A))
		else
			local other = Same(fight.A, m.name) and fight.B or fight.A
			text = L.ARENA_VS_SHORT:format(Name(other))
		end
		right = table.concat({ When(fight.t), fight.dur and Home.Clock(fight.dur) or "" }, "  ")
		local fid = ProfileFightId(fight, i)
		lines[#lines + 1] = { indent = 1, text = text, right = right,
			onClick = function() SelectProfileFight(m, fid) end }
	end
	Close()
	-- Bones
	Head("ARENA_PROF_BONES")
	local b = stats.bones
	if type(b) == "table" and (tonumber(b.games) or 0) > 0 then
		Row(L.ARENA_PROF_GAMES, tostring(b.games))
		Row(L.ARENA_PROF_WON, ("%d (%d%%)"):format(tonumber(b.won) or 0, math.floor((tonumber(b.won) or 0) * 100 / b.games + 0.5)))
		if b.best then Row(L.ARENA_PROF_BEST_TURN, ns.FormatNumber(b.best)) end
	else None(L.ARENA_PROF_NO_GAMES) end
	Close()
	-- Lottery
	Head("ARENA_PROF_LOTTERY")
	local lo = stats.lottery
	if type(lo) == "table" and (tonumber(lo.days) or 0) > 0 then
		Row(L.ARENA_PROF_DAYS, tostring(lo.days))
		Row(L.ARENA_PROF_WINS, tostring(tonumber(lo.wins) or 0))
		if lo.biggest then Row(L.ARENA_PROF_BIGGEST, Kit.Money(lo.biggest)) end
	else None(L.ARENA_PROF_NO_LOTTERY) end
	Close()
	-- Donations
	Head("ARENA_PROF_DONATIONS")
	local d = stats.donations
	if type(d) == "table" and (tonumber(d.all) or 0) > 0 then
		Row(L.ARENA_PROF_ALL_TIME, Kit.Money(d.all))
		Row(L.ARENA_PROF_THIS_MONTH, Kit.Money(tonumber(d.month) or 0))
		if d.place then Row(L.ARENA_PROF_DONOR_PLACE, "#" .. d.place) end
	else None(L.ARENA_PROF_NO_DONATIONS) end
	Close()
	-- Ranking places, each with its mark
	Head("ARENA_PROF_PLACES")
	local pl = stats.places
	if type(pl) == "table" and next(pl) then
		for _, e in ipairs({ { "A", pl.global }, { m.class and ("C" .. m.class) or nil, pl.class }, { m.race and ("R" .. tostring(m.race)) or nil, pl.race } }) do
			if e[1] and tonumber(e[2]) then
				local mark = ArenaUI.RankMark(e[1], e[2])
				Row(ArenaUI.CatWords(e[1]), (mark and ("|T" .. mark .. ":16:16|t ") or "") .. "#" .. e[2])
			end
		end
	else None(L.ARENA_PROF_NOT_RANKED) end
	Close()
	-- Tabard (self-reported, a planned check), usual hours
	Head("ARENA_PROF_TABARD")
	local t = stats.tabard
	if type(t) == "table" and t.wears ~= nil then
		None(t.wears and L.ARENA_PROF_TABARD_YES or L.ARENA_PROF_TABARD_NO)
		lines[#lines].text = t.wears and C("green", L.ARENA_PROF_TABARD_YES) or C("grey", L.ARENA_PROF_TABARD_NO)
	else None(L.ARENA_PROF_NOT_REPORTED) end
	Close()
	Head("ARENA_PROF_ONLINE")
	if type(stats.online) == "string" and stats.online ~= "" then Row(L.ARENA_PROF_HOURS, stats.online) else None(L.ARENA_PROF_NOT_SHARED) end
	return lines
end

-- (the portrait: Kit.Portrait, the one helper, drawn as the player's own: Kit.DrawPortrait)
function ArenaUI.ProfilePortrait(rig, m)
	return Kit.DrawPortrait(rig, m.name, { class = m.class, race = m.race, gender = m.gender, emblem = m.emblem, guild = m.guild, honour = m.honour })
end

local PORTRAIT = 96
local function ProfileDetail(canvas, st)
	local p = rawget(canvas, "profile")
	if not p then
		p = CreateFrame("Frame", nil, canvas)
		p:SetAllPoints(canvas)
		canvas.profile = p
		p.rig = Kit.NewPortrait(p, PORTRAIT)
		p.portrait = p.rig.slot
		p.portrait:SetPoint("TOP", p, "TOP", 0, -40)
		p.name = Kit.Text(p, "big", "CENTER")
		p.name:SetPoint("TOP", p.portrait, "BOTTOM", 0, -44)
		p.name:SetWidth(ArenaUI.DETAIL_W - 32)
		if p.name.SetWordWrap then p.name:SetWordWrap(false) end
		p.title = Kit.Text(p, "title", "CENTER")
		p.title:SetPoint("TOP", p.name, "BOTTOM", 0, -6)
		p.title:SetWidth(ArenaUI.DETAIL_W - 32)
		p.guild = Kit.Text(p, nil, "CENTER")
		p.guild:SetPoint("TOP", p.title, "BOTTOM", 0, -10)
		p.guild:SetWidth(ArenaUI.DETAIL_W - 32)
		p.who = Kit.Text(p, nil, "CENTER")
		p.who:SetPoint("TOP", p.guild, "BOTTOM", 0, -6)
		p.who:SetWidth(ArenaUI.DETAIL_W - 32)
		p.historyTitle = Kit.Text(p, "title", "LEFT")
		p.historyTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 32, -310)
		p.historyTitle:SetWidth(ArenaUI.DETAIL_W - 64)
		p.fight = Kit.Text(p, nil, "LEFT")
		p.fight:SetPoint("TOPLEFT", p.historyTitle, "BOTTOMLEFT", 0, -10)
		p.fight:SetWidth(ArenaUI.DETAIL_W - 64)
		if p.fight.SetJustifyV then p.fight:SetJustifyV("TOP") end
		p.history = Kit.Text(p, "small", "CENTER")
		p.history:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
		p.history:SetWidth(ArenaUI.DETAIL_W - 32)
		p.empty = Kit.Text(p, nil, "CENTER")
		p.empty:SetPoint("CENTER")
		p.empty:SetWidth(ArenaUI.DETAIL_W - 64)
	end
	local m = ArenaUI.ProfileModel(ProfileName(st))
	for _, part in ipairs({ p.portrait, p.name, p.title, p.guild, p.who, p.historyTitle, p.fight, p.history }) do part:SetShown(m ~= nil) end
	p.empty:SetShown(m == nil)
	if not m then p.empty:SetText(C("grey", L.ARENA_PROFILE_NONE)) return end
	ArenaUI.ProfilePortrait(p.rig, m)
	local head = Kit.Colored(m.name, ArenaUI.ClassFile(m.class))
	if m.nick and m.nick ~= "" then head = head .. "  " .. C("grey", "\"" .. ns.Codec.Plain(m.nick) .. "\"") end
	p.name:SetText(head)
	p.title:SetText(m.title and C("gold", ns.Codec.Plain(m.title)) or "")
	p.guild:SetText(m.guild and ("<" .. ns.Codec.Plain(m.guild) .. ">" .. (m.guildRank and ("  " .. C("grey", ns.Codec.Plain(m.guildRank))) or "")) or "")
	local who = {}
	if m.class then who[#who + 1] = ArenaUI.ClassWord(m.class) end
	if m.race then who[#who + 1] = ArenaUI.RaceWord(m.race) end
	if m.level then who[#who + 1] = L.ARENA_PROF_LEVEL:format(tonumber(m.level) or 0) end
	p.who:SetText(table.concat(who, "  ·  "))
	local fights = ProfileHistory(m)
	p.historyTitle:SetText(L.ARENA_HISTORY_TITLE .. (m.mine and ("  ·  " .. (HistoryMine() and L.ARENA_HISTORY_MINE or L.ARENA_HISTORY_RECENT)) or ""))
	p.fight:SetText(FightDetailText(ProfileSelectedFight(m, fights)))
	p.history:SetText(C("grey", m.history or ""))
end
local function ProfileButtons(st)
	if ProfileName(st) then
		local name = ProfileName(st)
		return { { L.ARENA_MENU_CHALLENGE, function() ArenaUI.Challenge(name) end }, { L.ARENA_BACK, ArenaUI.BackFromProfile } }
	end
	local PE = ns.ProfileEdit
	local edit = type(PE) == "table" and type(PE.Open) == "function"
	local C2 = ns.Consent
	return {
		{ HistoryMine() and L.ARENA_HISTORY_SHOW_RECENT or L.ARENA_HISTORY_SHOW_MINE, ToggleProfileHistory },
		{ L.ARENA_PROF_VISIBILITY, function() if C2 and C2.Show then C2.Show("profile") end end, enabled = C2 ~= nil and C2.Show ~= nil },
		{ L.ARENA_PROFILE_EDIT, function() if edit then PE.Open() else ArenaUI.Say(Kit.Why("missing")) end end, enabled = edit, why = Kit.Why("missing") },
		{ L.ARENA_PROFILE_PREVIEW, function() if ArenaUI.PreviewMe then ArenaUI.PreviewMe() end end },
		{ L.ARENA_PROFILE_LETTERS, function() if ArenaUI.LettersPopup then ArenaUI.LettersPopup() end end },
	}
end
ArenaUI.RegisterPane("arena.profile", { section = "arena", label = L.ARENA_PANE_PROFILE, order = 3,
	lines = ProfileLines, detail = ProfileDetail, buttons = ProfileButtons,
	text = function(st)
		if ProfileName(st) then return L.ARENA_PROFILE_THEIRS, L.ARENA_PROFILE_THEIRS_TEXT end
		return L.ARENA_PROFILE_MINE, L.ARENA_PROFILE_MINE_TEXT
	end,
	copy = function(st)
		local m = ArenaUI.ProfileModel(ProfileName(st))
		if not m then return "" end
		return Name(m.name) .. "\n" .. table.concat(m.lines, "\n")
	end })

---------------------------------------------------------------------------
-- Bones: Play (his table, Find a player, a new table, practice)
---------------------------------------------------------------------------

-- the Bones tables' board and its create panel (FarkleBoard.lua: ArenaUI.Farkle(what, id, extra), else the
-- older names), or a line saying it is not in this build.
function ArenaUI.BoneBoard(what, id, extra)
	if type(ArenaUI.Farkle) == "function" then return ns.SafeCall("arena bone", ArenaUI.Farkle, what, id, extra) end
	local FT = ns.FarkleTable
	if type(FT) == "table" and type(FT.ShowUI) == "function" then return ns.SafeCall("arena bone", FT.ShowUI, what, id, extra) end
	ArenaUI.Say(L.ARENA_BONE_NOT_HERE)
	return false
end
function ArenaUI.BoneAvailable()
	return type(ArenaUI.Farkle) == "function"
		or (type(ns.FarkleTable) == "table" and type(ns.FarkleTable.ShowUI) == "function")
end
-- The create panel for a guest (the right-click menu's Invite to Bones, a match's hand-off).
function ArenaUI.BoneInvite(prefill)
	if type(prefill) == "string" then prefill = { guest = prefill } end
	prefill = type(prefill) == "table" and prefill or {}
	if type(ArenaUI.CreateTable) == "function" then return ns.SafeCall("arena bone invite", ArenaUI.CreateTable, prefill) end
	if type(ArenaUI.FarkleCreate) == "function" then return ns.SafeCall("arena bone invite", ArenaUI.FarkleCreate, prefill) end
	return ArenaUI.BoneBoard("create", nil, prefill)
end

local function MyTableLine(t)
	if type(t) ~= "table" then return nil end
	local players = type(t.players) == "table" and t.players or {}
	local other
	for _, p in ipairs(players) do if not Same(p, ns.me) then other = p end end
	local stake = tonumber(t.stake) or 0
	local text = L.ARENA_BONE_MY_TABLE:format(Name(other or t.guest or "?"))
	if stake > 0 then text = text .. " · " .. Kit.Money(stake, t.cur) end
	if t.practice then text = L.ARENA_BONE_PRACTICE_TABLE end
	return text
end
function ArenaUI.BonePlayReady()
	if not ArenaUI.BoneAvailable() or not ns.FarkleTable then return false, Kit.Why("missing") end
	if not ns.FarkleTable.CanPlayPlayers() then return false, L.FARKLE_LOBBY_TRAINING_REQUIRED end
	if not ns.FarkleTable.CanOpen() then return false, L.FARKLE_LOG_TAVERN_REST end
	return true
end
function ArenaUI.BoneFindInnkeeper()
	local arrow = ns.InnkeeperArrow
	local function Notice(text, ok, reason)
		ArenaUI.boneKeeperNotice = text
		ArenaUI.Say(text)
		ArenaUI.Refresh()
		return ok, reason
	end
	if not arrow then return Notice(L.FARKLE_LOBBY_GUIDE_UNAVAILABLE, false, "missing") end
	if arrow.State().active then
		arrow.Cancel("cancelled")
		return Notice(L.FARKLE_LOBBY_STOPPED, true, "cancelled")
	end
	local read, _, reason, inn = pcall(arrow.Target)
	if not read then
		arrow.Cancel("error")
		if ns.Log then ns.Log("innkeeper guidance target: %s", tostring(_)) end
		return Notice(L.FARKLE_LOBBY_GUIDE_UNAVAILABLE, false, "error")
	end
	if reason == "arrived" and inn then
		return Notice(L.FARKLE_LOBBY_TALK:format(inn.innkeeper), false, reason)
	end
	local ok, target = arrow.Start()
	local text = ok and L.FARKLE_LOBBY_ARROW:format(target.innkeeper)
		or (target == "error" or target == "gamepad" or target == "timer-api") and L.FARKLE_LOBBY_GUIDE_UNAVAILABLE
		or L.FARKLE_LOBBY_NO_INN
	return Notice(text, ok, target)
end
local function KeeperButtonText()
	return ns.InnkeeperArrow and ns.InnkeeperArrow.State().active and L.FARKLE_LOBBY_STOP_ARROW or L.FARKLE_LOBBY_FIND_KEEPER
end
local function BonePlayLines(st)
	local lines = {}
	local mt = Data.MyTable()
	local board = ArenaUI.BoneAvailable()
	local ready, why = ArenaUI.BonePlayReady()
	local trained = ns.FarkleTable and ns.FarkleTable.CanPlayPlayers()
	lines[#lines + 1] = { header = true, text = L.ARENA_BONE_YOURS }
	if mt then
		lines[#lines + 1] = { text = C("blue", MyTableLine(mt)), indent = 1, onClick = function() ArenaUI.BoneBoard("board", mt.id) end }
	else
		lines[#lines + 1] = { text = C("grey", L.ARENA_BONE_NO_TABLE), indent = 1 }
	end
	lines[#lines + 1] = { header = true, text = L.ARENA_BONE_PLAY }
	if not trained then lines[#lines + 1] = { text = L.FARKLE_LOBBY_FIRST, indent = 1 } end
	lines[#lines + 1] = { text = C(board and "gold" or "grey", L.FARKLE_B_HOW), indent = 1, onClick = board and function() ArenaUI.BoneBoard("guide") end or nil }
	lines[#lines + 1] = { text = C("gold", KeeperButtonText()), indent = 1, onClick = ArenaUI.BoneFindInnkeeper }
	if ArenaUI.boneKeeperNotice then lines[#lines + 1] = { text = ArenaUI.boneKeeperNotice, indent = 1 } end
	lines[#lines + 1] = { text = C(ready and "gold" or "grey", L.ARENA_FIND_PLAYER), indent = 1, onClick = ready and function() ArenaUI.FindOpponent("b") end or nil,
		tooltip = function(tt) tt:AddLine(L.ARENA_FIND_PLAYER, 1, 0.82, 0) tt:AddLine(why or L.ARENA_FIND_PLAYER_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = { text = C(ready and "gold" or "grey", L.ARENA_BONE_NEW), indent = 1, onClick = ready and function() ArenaUI.BoneInvite({}) end or nil,
		tooltip = why and function(tt) tt:AddLine(L.ARENA_BONE_NEW, 1, 0.82, 0) tt:AddLine(why, 1, 1, 1, true) end or nil }
	lines[#lines + 1] = { text = C("gold", L.ARENA_PANE_BONE_HISTORY), indent = 1, onClick = function() ArenaUI.ShowPane("bone.history") end }
	local tables = Data.Tables() or {}
	if #tables > 0 then
		lines[#lines + 1] = { header = true, text = L.ARENA_BONE_LIVE_HEAD }
		lines[#lines + 1] = { text = L.ARENA_BONE_LIVE_COUNT:format(#tables), indent = 1, onClick = function() ArenaUI.ShowPane("bone.live") end }
	end
	return lines
end
local function BonePlayDetail(canvas)
	if not rawget(canvas, "letterTitle") then
		canvas.letterTitle = Kit.Text(canvas, "title", "CENTER")
		canvas.letterTitle:SetFont("Fonts\\MORPHEUS.TTF", 30, "")
		canvas.letterTitle:SetPoint("TOP", 0, -38)
		canvas.letterTitle:SetWidth(ArenaUI.DETAIL_W - 64)
		canvas.letterBody = Kit.Text(canvas, nil, "LEFT")
		canvas.letterBody:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
		canvas.letterBody:SetPoint("TOP", canvas.letterTitle, "BOTTOM", 0, -28)
		canvas.letterBody:SetWidth(ArenaUI.DETAIL_W - 80)
		canvas.letterBody:SetHeight(248)
		canvas.letterBody:SetJustifyV("TOP")
		if canvas.letterBody.SetSpacing then canvas.letterBody:SetSpacing(4) end
		canvas.find = Kit.Button(canvas, 210, 32, L.ARENA_FIND_PLAYER, function() ArenaUI.FindOpponent("b") end)
		canvas.learn = Kit.Button(canvas, 210, 32, L.FARKLE_B_LEARN, function()
			ArenaUI.BoneBoard("guide")
		end)
		canvas.learn:SetPoint("TOP", canvas.letterBody, "BOTTOM", 0, -12)
		canvas.keeper = Kit.Button(canvas, 240, 32, L.FARKLE_LOBBY_FIND_KEEPER, ArenaUI.BoneFindInnkeeper)
		canvas.keeper:SetPoint("TOP", canvas.learn, "BOTTOM", 0, -10)
		canvas.keeperNotice = Kit.Text(canvas, nil, "CENTER")
		canvas.keeperNotice:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
		canvas.keeperNotice:SetPoint("TOP", canvas.keeper, "BOTTOM", 0, -8)
		canvas.keeperNotice:SetWidth(ArenaUI.DETAIL_W - 80)
		canvas.keeperNotice:SetHeight(50)
		canvas.keeperNotice:SetJustifyV("TOP")
		canvas.find:SetPoint("TOP", canvas.keeperNotice, "BOTTOM", 0, -8)
	end
	local mt = Data.MyTable()
	canvas.letterTitle:SetText(L.FARKLE_INTRO_TITLE)
	local ready, why = ArenaUI.BonePlayReady()
	canvas.letterBody:SetText(L.FARKLE_INTRO_TEXT .. "\n\n" .. (ns.FarkleTable and ns.FarkleTable.CanPlayPlayers() and L.FARKLE_LOBBY_RETURN or L.FARKLE_LOBBY_FIRST)
		.. (mt and ("\n\n" .. MyTableLine(mt) .. "\n" .. L.ARENA_BONE_OPEN_HINT) or ""))
	Kit.SetButton(canvas.find, mt and L.ARENA_BONE_OPEN or L.ARENA_FIND_PLAYER, ready, why)
	Kit.SetButton(canvas.learn, L.FARKLE_B_HOW, ArenaUI.BoneAvailable())
	Kit.SetButton(canvas.keeper, KeeperButtonText(), ns.InnkeeperArrow ~= nil)
	canvas.keeperNotice:SetText(ArenaUI.boneKeeperNotice or "")
	canvas.find:SetScript("OnClick", function()
		if mt then ArenaUI.BoneBoard("board", mt.id) else ArenaUI.FindOpponent("b") end
	end)
end
ArenaUI.RegisterPane("bone.play", { section = "farkle", label = L.ARENA_PANE_BONE_PLAY, order = 1,
	lines = BonePlayLines, detail = BonePlayDetail,
	text = function() return L.ARENA_SECTION_BONE, L.ARENA_BONE_TEXT end,
	buttons = function()
		local mt = Data.MyTable()
		local ready, why = ArenaUI.BonePlayReady()
		return {
			mt and { L.ARENA_BONE_OPEN, function() ArenaUI.BoneBoard("board", mt.id) end, enabled = ready, why = why } or { L.ARENA_FIND_PLAYER, function() ArenaUI.FindOpponent("b") end, enabled = ready, why = why },
			{ L.ARENA_BONE_NEW, function() ArenaUI.BoneInvite({}) end, enabled = ready, why = why },
			{ L.ARENA_BONE_PRACTICE, ArenaUI.BoneFindInnkeeper, enabled = ns.InnkeeperArrow ~= nil, why = Kit.Why("missing") },
			{ L.ARENA_PANE_BONE_HISTORY, function() ArenaUI.ShowPane("bone.history") end },
		}
	end })

---------------------------------------------------------------------------
-- Bones: the live tables to watch
---------------------------------------------------------------------------

local function TableTitle(t)
	local a = t.p1 or (type(t.players) == "table" and t.players[1]) or nil
	local b = t.p2 or (type(t.players) == "table" and t.players[2])
	return L.ARENA_VS:format(Name(a or "?"), Name(b or "?"))
end
local function TableRight(t)
	local parts = {}
	local stake = tonumber(t.stake)
	if stake and stake > 0 then parts[#parts + 1] = Kit.Money(stake, t.cur) end
	if t.official or t.public then parts[#parts + 1] = C("gold", L.ARENA_BONE_OFFICIAL) end
	if t.mode == "T" then parts[#parts + 1] = C("red", L.ARENA_TAG_TEST) end
	return table.concat(parts, " ")
end
local function BoneLiveLines(st)
	local lines = { { header = true, text = L.ARENA_BONE_LIVE_HEAD } }
	local tables = Data.Tables() or {}
	if #tables == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_BONE_LIVE_NONE), indent = 1 } end
	for _, t in ipairs(tables) do
		local id = t.id
		local text = TableTitle(t)
		if st.sel == id then text = C("blue", "> ") .. text end
		lines[#lines + 1] = { text = text, right = TableRight(t), indent = 1, onClick = function() ArenaUI.Select("bone.live", id) end }
	end
	return lines
end
local function Watch(id)
	if not id then return end
	local ok = Do("farkle.watch", id)
	if ok then ArenaUI.BoneBoard("watch", id) end
end
-- The crowd's bets at the picked table (its MW market, 2026-10-04): a Bet per player on the
-- parchment, one under the other, each with its odds, its pool in the tooltip and, once the bets
-- close, greyed with why. Never in the footer, which shows two buttons and folds the rest under
-- More (Window.lua): there the second player's Bet hid behind a menu, its reason lost.
local function BoneLiveDetail(canvas, st)
	if not rawget(canvas, "empty") then
		canvas.empty = Kit.Text(canvas, nil, "CENTER")
		canvas.empty:SetPoint("CENTER", 0, 0)
		canvas.empty:SetWidth(ArenaUI.DETAIL_W - 64)
	end
	local tables = Data.Tables() or {}
	local selected
	for _, t in ipairs(tables) do if t.id == st.sel then selected = true break end end
	canvas.empty:SetShown(not selected)
	canvas.empty:SetText(#tables == 0 and L.ARENA_BONE_LIVE_NONE or L.ARENA_BONE_LIVE_TEXT)
	local m = rawget(canvas, "crowd")
	if not m then
		m = CreateFrame("Frame", nil, canvas)
		m:SetPoint("TOPLEFT", 12, -12)
		m:SetPoint("TOPRIGHT", -12, -12)
		m:SetHeight(92)
		m.head = Kit.Text(m, "title", "LEFT")
		m.head:SetPoint("TOPLEFT", 4, 0)
		m.bets = {}
		for i = 1, 2 do
			local b = Kit.Button(m, 200, 26, "", nil)
			b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -24 - (i - 1) * 32)
			m.bets[i] = b
		end
		canvas.crowd = m
	end
	local id = st.sel
	local picks = id and ArenaUI.CrowdBets(id) or nil
	m:SetShown(picks ~= nil)
	if not picks then return end
	m.head:SetText(L.ARENA_BONE_CROWD)
	for i, b in ipairs(m.bets) do
		local pick = picks[i]
		if pick then
			local odds = pick.odds and pick.odds > 0 and ("  " .. ("%.2fx"):format(pick.odds)) or ""
			-- (the tip first: SetButton gives the tooltip only to a button with a tip or a why)
			b.tip = pick.label .. "\n" .. L.ARENA_MARKET_TIP:format(Kit.Money(pick.pool, pick.cur), pick.count)
			Kit.SetButton(b, L.ARENA_BONE_BET:format(pick.label) .. odds, pick.open, L.ARENA_REFUSE_CLOSED)
			Kit.Fit(b, 120)
			b:SetScript("OnClick", function() ArenaUI.Slip(id, pick.idx, pick.o) end)
			b:Show()
		else
			b:Hide()
		end
	end
end
ArenaUI.RegisterPane("bone.live", { section = "farkle", label = L.ARENA_PANE_BONE_LIVE, order = 2,
	lines = BoneLiveLines, detail = BoneLiveDetail,
	text = function(st)
		for _, t in ipairs(Data.Tables() or {}) do
			if t.id == st.sel then return TableTitle(t), L.ARENA_BONE_WATCH_TEXT end
		end
		return L.ARENA_PANE_BONE_LIVE, L.ARENA_BONE_LIVE_TEXT
	end,
	buttons = function(st)
		local id = st.sel
		local ok, why = ns.Arena.Can("farkle.watch", id)
		if why == "unknown" then ok, why = false, "missing" end
		-- (the crowd's Bets are on the parchment, BoneLiveDetail)
		return { { L.ARENA_BONE_WATCH, function() Watch(id) end, enabled = id ~= nil and ok, why = Kit.Why(id and why or "pick") },
			{ L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end } }
	end })

---------------------------------------------------------------------------
-- Bones: his games
---------------------------------------------------------------------------

-- His games, newest first (FarkleTable.MyGames: both modes; each entry's res W won, L lost, V void,
-- D a game he judged; s1 and s2 by seat, shown from his side; the sim's entries say won and score).
ArenaUI.BONE_HISTORY_ROWS = 40
local GamesDetail
local function BoneHistoryLines(st)
	local lines = { { header = true, text = L.ARENA_BONE_HISTORY_HEAD } }
	local list = Data.BoneHistory() or {}
	if #list == 0 then lines[#lines + 1] = { text = C("grey", L.ARENA_BONE_HISTORY_NONE), indent = 1 } end
	for i = 1, math.min(#list, ArenaUI.BONE_HISTORY_ROWS) do
		local h = list[i]
		if type(h) == "table" then
			local res = h.res
			if res == nil and h.won ~= nil then res = h.won == true and "W" or "L" end
			if res == nil and h.winner then res = Same(h.winner, ns.me) and "W" or "L" end
			local mine, theirs = tonumber(h.s1), tonumber(h.s2)
			if h.seat == 2 then mine, theirs = theirs, mine end
			local score = h.score or (mine and theirs and ("%d-%d"):format(mine, theirs))
				or (type(h.scores) == "table" and (tostring(h.scores[1]) .. "-" .. tostring(h.scores[2]))) or ""
			local word
			if res == "W" then word = C("green", L.ARENA_WON)
			elseif res == "L" then word = C("red", L.ARENA_LOST)
			elseif res == "D" then word = C("grey", L.ARENA_BONE_JUDGED)
			else word = C("grey", L.ARENA_BONE_VOID) end
			local who = res == "D" and L.ARENA_BONE_LEDGER_PAIR:format(Name(h.host or "?"), Name(h.guest or "?"))
				or L.ARENA_VS_SHORT:format(Name(h.opp or h.opponent or h.vs or "?"))
			local stake = tonumber(h.stake) or 0
			local id = h.id
			lines[#lines + 1] = { indent = 1, key = id, text = (id and st and st.sel == id and C("blue", "> ") or "") .. ("%s  %s %s"):format(When(h.t or h.at), word, who),
				right = score .. (stake > 0 and (" · " .. Kit.Money(stake, h.cur)) or ""),
				onClick = id and function() ArenaUI.Select("bone.history", id) end or nil }
		end
	end
	return lines
end
ArenaUI.RegisterPane("bone.history", { section = "farkle", label = L.ARENA_PANE_BONE_HISTORY, order = 3,
	lines = BoneHistoryLines,
	detail = function(canvas, st)
		local view = Data.Games({ scope = "mine", game = "bones" }) or {}
		local row
		for _, item in ipairs(view.list or {}) do if item.id == st.sel then row = item; break end end
		-- Older Bones histories predate the shared ledger. Keep their recorded facts available.
		if not row then
			for _, h in ipairs(Data.BoneHistory() or {}) do
				if h.id and h.id == st.sel then
					row = { id = h.id, g = h.learn and "p" or (h.practice and "h" or "b"), t = h.t,
						p1 = h.host, p2 = h.guest, s1 = h.s1, s2 = h.s2, arb = h.arb, how = h.why,
						mode = h.reh and "T" or "L", w = h.res == "W" and tostring(h.seat) or (h.res == "L" and tostring(3 - (h.seat or 1)) or "v") }
					break
				end
			end
		end
		GamesDetail(canvas, st, row, { scope = "mine" })
	end,
	text = function() return L.ARENA_PANE_BONE_HISTORY, L.ARENA_BONE_HISTORY_TEXT end,
	buttons = function() return { { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end } } end })

---------------------------------------------------------------------------
-- The games' ledger (1.1.6, the owner's ask of 2026-10-05): a page of its own (a staff page every
-- member opens: the Games tab's "Your games" and, for an auditor, "Every game"), from the core's
-- ArenaLedger.GamesView, whose rule says what it lists: this player's own games of every kind
-- (Bones against a player, the House, a lesson; a duel, a Fight Night's bout, a tournament's; the
-- Lottery's practice draws), and on an auditor's client (the King's character, a High Councillor,
-- a signed arbiter with "+a": the author's own character's entry) every game its players told him.
-- Over the list, the filters (the rankings' dropdowns): the game, the period, and for an auditor
-- whose games (everyone, only his own, or one player: the names of the games shown, the most
-- first) with a search box beside it (with mouse and keyboard; the gamepad picks from the list,
-- or from a row's "Only this player"); the pages. Each row: the day, the game, who beat whom (his
-- own: won, lost, void or judged, against whom), the score; an auditor's also whether the players'
-- words agree. The parchment: the picked game whole (and each participant's word, an auditor's).
---------------------------------------------------------------------------

ArenaUI.GAMES_KEY = "staff.games"
local GAME_GROUP_WORDS = { bones = "ARENA_SECTION_BONE", arena = "ARENA_SECTION_ARENA", lottery = "ARENA_SECTION_LOTTERY" }
local LEDGER_STATE = { agreed = { "green", "ARENA_BONE_LEDGER_AGREED" }, differ = { "red", "ARENA_BONE_LEDGER_DIFFER" }, one = { "grey", "ARENA_BONE_LEDGER_ONE" } }
local SOLO_GAME = { h = true, p = true, o = true }

-- The filters, this session's (a fresh look each login): scope "mine" | "all", game, period,
-- player, page.
local gamesPick = { scope = "mine", page = 1 }
local function GamesChoice()
	return { scope = gamesPick.scope, game = gamesPick.game, period = gamesPick.period, player = gamesPick.player, page = gamesPick.page }
end
function ArenaUI.GamesView() return Data.Games(GamesChoice()) or {}, GamesChoice() end
-- A filter changed (the page back to the first, but for the page itself).
function ArenaUI.SetGames(key, value)
	gamesPick[key] = value
	if key ~= "page" then gamesPick.page = 1 end
	ArenaUI.Refresh()
end
local function Pick(key, value) gamesPick[key] = value end
-- The page on a scope: "mine" (the Games tab's Your games) or "all" (an auditor's Every game).
function ArenaUI.ShowGames(scope)
	gamesPick.scope, gamesPick.player, gamesPick.page = scope == "all" and "all" or "mine", nil, 1
	return ArenaUI.ShowStaff(ArenaUI.GAMES_KEY)
end

-- The words of a game's kind ("Bones", "Duel", "Lottery practice").
function ArenaUI.GameWord(g) return L["ARENA_GAME_" .. tostring(g):upper()] or tostring(g) end
local function OtherName(row, name)
	if row.p2 and Same(row.p1, name) then return row.p2 end
	if row.p2 and Same(row.p2, name) then return row.p1 end
	return nil
end
local function HouseWord() return L.FARKLE_HOUSE or "The House" end
-- What a row says: (text, score) from the player's own side for his own games, else who beat whom.
function ArenaUI.GameLine(row, mine)
	local g = row.g
	if g == "o" then
		local text = row.w == "1" and L.ARENA_GAMES_HIT:format(Name(row.p1), tonumber(row.s1) or 0) or L.ARENA_GAMES_MISS:format(Name(row.p1))
		return text, ""
	end
	local s1, s2 = tonumber(row.s1) or 0, tonumber(row.s2) or 0
	if mine and (row.side == 1 or row.side == 2) then
		local word = row.result == "W" and C("green", L.ARENA_WON) or (row.result == "L" and C("red", L.ARENA_LOST) or C("grey", L.ARENA_BONE_VOID))
		local other = SOLO_GAME[g] and HouseWord() or Name(OtherName(row, ns.me) or "?")
		if row.side == 2 then s1, s2 = s2, s1 end
		return ("%s %s"):format(word, L.ARENA_VS_SHORT:format(other)), ("%d-%d"):format(s1, s2)
	end
	if mine and row.side == "arb" then
		return ("%s %s"):format(C("grey", L.ARENA_BONE_JUDGED), L.ARENA_BONE_LEDGER_PAIR:format(Name(row.p1), Name(row.p2 or "?"))), ("%d-%d"):format(s1, s2)
	end
	local a, b = Name(row.p1), SOLO_GAME[g] and HouseWord() or Name(row.p2 or "?")
	local text
	if row.w == "1" then text = L.ARENA_BONE_LEDGER_WON:format(a, b)
	elseif row.w == "2" then text = L.ARENA_BONE_LEDGER_WON:format(b, a)
	else text = L.ARENA_BONE_LEDGER_PAIR:format(a, b) .. " " .. C("grey", L.ARENA_BONE_VOID) end
	return text, ("%d-%d"):format(s1, s2)
end

local ARROW = "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12:0:0|t"
local function GamesHead(parent)
	local r = CreateFrame("Frame", nil, parent)
	r.game = Kit.Button(r, 142, 24, "", function(self)
		local items = { { L.ARENA_GAMES_ALL_GAMES, function() ArenaUI.SetGames("game", nil) end } }
		for _, group in ipairs({ "bones", "arena", "lottery" }) do
			local key = group
			items[#items + 1] = { L[GAME_GROUP_WORDS[group]], function() ArenaUI.SetGames("game", key) end }
		end
		for _, g in ipairs({ "b", "h", "p", "d", "n", "t", "o" }) do
			local key = g
			items[#items + 1] = { "  " .. ArenaUI.GameWord(g), function() ArenaUI.SetGames("game", key) end }
		end
		ArenaUI.Menu(self, items)
	end)
	r.game:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.period = Kit.Button(r, 142, 24, "", function(self)
		local items = {}
		for _, per in ipairs({ "today", "week", "month", "all" }) do
			local key = per ~= "all" and per or nil
			items[#items + 1] = { L[PERIOD_LABELS[per]], function() ArenaUI.SetGames("period", key) end }
		end
		ArenaUI.Menu(self, items)
	end)
	r.period:SetPoint("LEFT", r.game, "RIGHT", 4, 0)
	-- (an auditor's: whose games, and the search)
	r.who = Kit.Button(r, 118, 24, "", function(self)
		local view = ArenaUI.GamesView()
		local items = {
			{ L.ARENA_GAMES_EVERYONE, function() Pick("scope", "all") ArenaUI.SetGames("player", nil) end },
			{ L.ARENA_GAMES_ONLY_MINE, function() Pick("scope", "mine") ArenaUI.SetGames("player", nil) end },
		}
		for _, p in ipairs(type(view.players) == "table" and view.players or {}) do
			local name = p.name
			items[#items + 1] = { ("%s (%d)"):format(Name(name), tonumber(p.n) or 0), function()
				Pick("scope", "all") ArenaUI.SetGames("player", ns.FullName(name)) end }
		end
		ArenaUI.Menu(self, items)
	end)
	r.who:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -30)
	local ok, eb = pcall(CreateFrame, "EditBox", nil, r, "InputBoxTemplate")
	if not ok or not eb then eb = CreateFrame("EditBox", nil, r) end
	eb:SetAutoFocus(false)
	eb:SetSize(84, 22)
	eb:SetMaxLetters(40)
	eb:SetPoint("LEFT", r.who, "RIGHT", 10, 0)
	eb.olympusBox = true
	eb:SetScript("OnMouseDown", function(self) ns.Focus(self) end)
	eb:SetScript("OnEnterPressed", function(self)
		local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
		Pick("scope", "all")
		ArenaUI.SetGames("player", text ~= "" and text or nil)
		self:ClearFocus()
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	eb.tip = L.ARENA_GAMES_SEARCH_TIP
	r.search = eb
	r.prev = Kit.Button(r, 32, 24, "<", function() local c = GamesChoice() ArenaUI.SetGames("page", math.max(1, (tonumber(c.page) or 1) - 1)) end)
	r.next = Kit.Button(r, 32, 24, ">", function() local c = GamesChoice() ArenaUI.SetGames("page", (tonumber(c.page) or 1) + 1) end)
	r.next:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -30)
	r.prev:SetPoint("RIGHT", r.next, "LEFT", -4, 0)
	return r
end
local function GamesHeadRefresh(r)
	local view, c = ArenaUI.GamesView()
	local game = view.game or c.game
	local gameWord = not game and L.ARENA_GAMES_ALL_GAMES or (GAME_GROUP_WORDS[game] and L[GAME_GROUP_WORDS[game]] or ArenaUI.GameWord(game))
	Kit.SetButton(r.game, gameWord .. ARROW, true)
	Kit.SetButton(r.period, (L[PERIOD_LABELS[view.period or "all"]] or "") .. ARROW, true)
	local may = view.may == true
	local who = view.player and Name(view.player) or (view.scope == "all" and L.ARENA_GAMES_EVERYONE or L.ARENA_GAMES_ONLY_MINE)
	Kit.SetButton(r.who, who .. ARROW, may)
	r.who:SetShown(may)
	-- (the search: an auditor's, with mouse and keyboard; the gamepad picks a name from the list)
	r.search:SetShown(may and not Kit.Gamepad())
	if not (r.search.HasFocus and r.search:HasFocus()) then r.search:SetText(view.player or "") end
	local page, pages = tonumber(view.page) or 1, tonumber(view.pages) or 1
	Kit.SetButton(r.prev, nil, page > 1)
	Kit.SetButton(r.next, nil, page < pages)
	r.prev.tip, r.next.tip = L.ARENA_PAGE:format(page, pages), L.ARENA_PAGE:format(page, pages)
end
local function GamesLines(st)
	local view = ArenaUI.GamesView()
	local mine = view.scope ~= "all"
	local lines = { { header = true, text = mine and L.ARENA_GAMES_HEAD_MINE or L.ARENA_GAMES_HEAD_ALL,
		right = L.ARENA_GAMES_COUNT:format(tonumber(view.total) or 0) } }
	local rows = view.rows or {}
	if #rows == 0 then lines[#lines + 1] = { text = C("grey", mine and L.ARENA_GAMES_NONE_MINE or L.ARENA_GAMES_NONE_ALL), indent = 1 } end
	for _, row in ipairs(rows) do
		local id = row.id
		local text, score = ArenaUI.GameLine(row, mine)
		local right = score
		if not mine then
			local stw = LEDGER_STATE[row.state] or LEDGER_STATE.one
			right = (score ~= "" and (score .. " ") or "") .. C(stw[1], L[stw[2]])
		end
		if row.mode == "T" and not SOLO_GAME[row.g] then right = right .. " " .. C("red", L.ARENA_TAG_TEST) end
		local sel = st and st.sel == id
		lines[#lines + 1] = { indent = 1, key = id, text = (sel and C("blue", "> ") or "") .. ("%s  %s  %s"):format(When(row.t), C("gold", ArenaUI.GameWord(row.g)), text),
			right = right, onClick = function() ArenaUI.Select(ArenaUI.GAMES_KEY, id) end }
	end
	return lines
end
local function PickedGame(st)
	local view = ArenaUI.GamesView()
	for _, row in ipairs(view.list or {}) do if st and row.id == st.sel then return row, view end end
	return nil, view
end
local HOW_GROUP = { b = "B", h = "B", p = "B", d = "F", n = "F", t = "F", o = "O" }
function ArenaUI.GameHow(row) return L["ARENA_GAMES_HOW_" .. (HOW_GROUP[row.g] or "F") .. "_" .. tostring(row.how or ""):upper()] or tostring(row.how or "") end
GamesDetail = function(canvas, st, picked, pickedView)
	if not rawget(canvas, "gamesText") then
		canvas.gamesTitle = Kit.Text(canvas, "title", "LEFT")
		canvas.gamesTitle:SetPoint("TOPLEFT", 16, -16)
		canvas.gamesTitle:SetWidth(ArenaUI.DETAIL_W - 32)
		canvas.gamesText = Kit.Text(canvas, nil, "LEFT")
		canvas.gamesText:SetPoint("TOPLEFT", canvas.gamesTitle, "BOTTOMLEFT", 0, -10)
		canvas.gamesText:SetWidth(ArenaUI.DETAIL_W - 32)
		if canvas.gamesText.SetJustifyV then canvas.gamesText:SetJustifyV("TOP") end
		if canvas.gamesText.SetSpacing then canvas.gamesText:SetSpacing(3) end
	end
	local row, view = picked, pickedView
	if not view then row, view = PickedGame(st) end
	if not row then
		canvas.gamesTitle:SetText(view.scope == "all" and L.ARENA_GAMES_HEAD_ALL or L.ARENA_GAMES_HEAD_MINE)
		canvas.gamesText:SetText(view.scope == "all" and L.ARENA_GAMES_ABOUT_ALL or L.ARENA_GAMES_ABOUT_MINE)
		return
	end
	canvas.gamesTitle:SetText(ArenaUI.GameWord(row.g) .. "  " .. C("grey", date and date("%Y-%m-%d %H:%M", row.t) or ""))
	local out = {}
	local text, score = ArenaUI.GameLine(row, false)
	out[#out + 1] = text .. (score ~= "" and ("  " .. score) or "")
	if row.g == "o" then
		local Lt = ns.Lottery
		local beast = tonumber(row.s2)
		local label = beast and type(Lt) == "table" and type(Lt.Label) == "function" and Lt.Label(beast) or tostring(row.s2 or "?")
		out[#out + 1] = L.ARENA_GAMES_PICK:format(label)
		if row.x then out[#out + 1] = L.ARENA_GAMES_DRAWN:format((row.x:gsub("%.", " "))) end
	else
		out[#out + 1] = L.ARENA_GAMES_PLAYERS:format(Name(row.p1), SOLO_GAME[row.g] and HouseWord() or Name(row.p2 or "?"))
		if row.arb then out[#out + 1] = L.ARENA_GAMES_ARBITER:format(Name(row.arb)) end
		out[#out + 1] = L.ARENA_GAMES_ENDED:format(ArenaUI.GameHow(row))
		if row.dur ~= nil then out[#out + 1] = L.ARENA_GAMES_LENGTH:format(Home.Clock(tonumber(row.dur) or 0)) end
	end
	if row.mode == "T" and not SOLO_GAME[row.g] then out[#out + 1] = C("red", L.ARENA_GAMES_REHEARSAL) end
	if view.scope == "all" and row.state then
		local stw = LEDGER_STATE[row.state] or LEDGER_STATE.one
		out[#out + 1] = ""
		out[#out + 1] = L.ARENA_GAMES_WORDS:format(tonumber(row.reports) or 0, C(stw[1], L[stw[2]]))
	end
	canvas.gamesText:SetText(table.concat(out, "\n"))
end
local function GamesCopy()
	local view = ArenaUI.GamesView()
	local mine = view.scope ~= "all"
	local out = { mine and L.ARENA_GAMES_HEAD_MINE or L.ARENA_GAMES_HEAD_ALL }
	for i, row in ipairs(view.list or {}) do
		if i > 500 then break end
		local text, score = ArenaUI.GameLine(row, mine)
		local parts = { date and date("%Y-%m-%d %H:%M", row.t) or tostring(row.t), ArenaUI.GameWord(row.g), text, score }
		if row.arb then parts[#parts + 1] = L.ARENA_GAMES_ARBITER:format(Name(row.arb)) end
		if not mine and row.state then local stw = LEDGER_STATE[row.state] or LEDGER_STATE.one parts[#parts + 1] = L[stw[2]] end
		out[#out + 1] = table.concat(parts, "  ")
	end
	return table.concat(out, "\n")
end
ArenaUI.RegisterStaffTab(ArenaUI.GAMES_KEY, { label = L.ARENA_PANE_GAMES, tip = L.ARENA_GAMES_TIP, order = 0,
	icon = { "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Dice_02" },
	head = GamesHead, headRefresh = GamesHeadRefresh, headH = 58,
	lines = GamesLines, detail = GamesDetail, copy = GamesCopy,
	text = function() local view = ArenaUI.GamesView() return view.scope == "all" and L.ARENA_GAMES_HEAD_ALL or L.ARENA_GAMES_HEAD_MINE,
		view.scope == "all" and L.ARENA_GAMES_TEXT_ALL or L.ARENA_GAMES_TEXT_MINE end,
	buttons = function(st)
		local row, view = PickedGame(st)
		local list = { { L.ARENA_BTN_COPY, function() ArenaUI.CopyPane() end } }
		-- (an auditor's: the picked game's other player, or himself, as the player filter: the
		-- gamepad's way to a player's games, no typing)
		if view.may and row then
			for _, name in ipairs({ row.p1, row.p2 or false }) do
				if name then
					local who = name
					list[#list + 1] = { L.ARENA_GAMES_ONLY:format(Name(who)), function()
						Pick("scope", "all") ArenaUI.SetGames("player", ns.FullName(who)) end }
				end
			end
		end
		if view.player or view.game or view.period then
			list[#list + 1] = { L.ARENA_GAMES_CLEAR, function()
				Pick("game", nil) Pick("period", nil) ArenaUI.SetGames("player", nil) end }
		end
		return list
	end })

---------------------------------------------------------------------------
-- The Lottery: the Lottery's board (LotteryBoard.lua, the "lottery" pane) fills the section; this
-- stand-in shows only while it is not in the build.
---------------------------------------------------------------------------

ArenaUI.RegisterPane("lottery.wait", { section = "lottery", label = L.ARENA_SECTION_LOTTERY, order = 99, standin = true, full = true,
	build = function(parent)
		local f = CreateFrame("Frame", nil, parent)
		f:SetAllPoints(parent)
		f.title = Kit.Text(f, "big", "CENTER")
		f.title:SetPoint("TOP", 0, -30)
		f.title:SetText(L.ARENA_LOTTERY_FULL)
		f.text = Kit.Text(f, nil, "CENTER")
		f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -16)
		f.text:SetWidth(520)
		return f
	end,
	refresh = function(f)
		local lot = Data.Lottery()
		if type(lot) == "table" then
			f.text:SetText(L.ARENA_LOTTERY_TODAY:format(Kit.Money(lot.pool or 0, lot.cur), lot.drawAt and date and date("%H:%M", lot.drawAt) or "?"))
		else
			f.text:SetText(L.ARENA_LOTTERY_WAIT)
		end
	end,
	text = function() return L.ARENA_LOTTERY_FULL, L.ARENA_LOTTERY_TEXT end,
	buttons = function() return {} end })
