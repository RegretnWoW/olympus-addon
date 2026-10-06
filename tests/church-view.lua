-- 1.1.6, the Missionary Church of Olympus: the tab, its pages, the dialogs (Olympus's own window
-- under the gamepad UI), the right-click line, the words in both languages, the README.
-- Run alone: luajit tests/run.lua "1.1.6 Church"
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-view%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key
local L = ns.L

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

local function Cast()
	local w = World.New({ apostles = { A1, A2 } })
	local c = {
		author = w:Client(World.AUTHOR, { view = true }), king = w:Client(World.KING, { view = true }), head = w:Client(World.HEAD, { view = true }),
		councillor = w:Client(World.COUNCILLOR, { view = true }),
		a1 = w:Client(A1, { view = true }), a2 = w:Client(A2, { view = true }),
		m1 = w:Client("Mira Wells", { view = true }), member = w:Client("Plain Member", { view = true }),
		gm = w:Client("Ember Master", { view = true, rank = 0 }), other = w:Client("Vale Member", { view = true, guild = World.GUILD2 }),
	}
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	return w, c
end

local function Texts(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do
		if line.text then out[#out + 1] = line.text end
		if line.right then out[#out + 1] = line.right end
		for _, col in ipairs(line.cols or {}) do out[#out + 1] = col end
		for _, item in ipairs(line.nav or {}) do out[#out + 1] = item.text end
	end
	return table.concat(out, "\n")
end
local function Find(lines, text)
	for _, line in ipairs(lines or {}) do
		if (line.text and line.text:find(text, 1, true)) or (line.cols and line.cols[1] and line.cols[1]:find(text, 1, true)) then return line end
	end
	return nil
end
-- A confirmed recruit in every keeper's ledger (what the log, the witnesses and the keepers' catch-up make).
local function GiveAll(w, c, by, recruit)
	for _, k in ipairs({ c.head, c.a1, c.a2, c.author }) do
		w:As(k, k.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
			tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	end
end
local function Pages(w, cl) return table.concat(w:As(cl, cl.View.Pages), ",") end
local function Build(w, cl, page)
	if page then cl.View.page = page end
	return w:As(cl, cl.View.Build)
end

test("Church discoverability: missionaries are the third visible group with existing appointment action", function()
	local w, c = Cast()
	local lines = Build(w, c.a1, "people")
	local apostleAt, correspondentAt, missionaryAt, personAt
	for i, line in ipairs(lines) do
		if line.text == L.CHURCH_APOSTLES:format(3, 12) then apostleAt = i end
		if line.text == L.CHURCH_CORRESPONDENTS:format(0) then correspondentAt = i end
		if line.text == L.CHURCH_MISSIONARIES:format(1) then missionaryAt = i end
		if line.player == "Mira Wells-Realm" then personAt = i end
	end
	assert(apostleAt and correspondentAt and missionaryAt and personAt, Texts(lines))
	assert(apostleAt < correspondentAt and correspondentAt < missionaryAt and missionaryAt < personAt)
	eq(c.a1.View.open[Key(A1)], nil, "missionaries visible without expanding Apostle")
	local signed = {}
	local state = w:As(c.a1, c.a1.Church.State)
	for _, line in ipairs(lines) do if line.key and state.apostle[line.key] then signed[#signed + 1] = line.key end end
	eq(table.concat(signed, ","), table.concat(state.order, ","), "original signed ordering unchanged")
	local name = Find(lines, L.CHURCH_NAME_MISSIONARY:format(9, 10))
	assert(name and name.onClick, "existing authorized naming duty surfaced beside group")
	name.onClick(); local dialog = c.a1.dialogs[#c.a1.dialogs]
	eq(dialog.which, "OLYMPUS_CHURCH_NAME"); eq(dialog.data.kind, "missionary")
	eq(w:Act(c.a1, c.a1.View.Submit, dialog.data, "Fresh Face"), true)
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), "M")
	lines = Build(w, c.member, "people")
	eq(Find(lines, L.CHURCH_NAME_MISSIONARY:format(8, 10)), nil, "ordinary member gets no appointment action")
end)

test("Church publication authority UI: actual King/council switches, no preview action", function()
	local w, c = Cast()
	for _, publisher in ipairs({ c.king, c.councillor }) do
		local switch = Find(Build(w, publisher, "ranking"), L.CHURCH_PUBLIC_SWITCH)
		assert(switch and switch.onClick, "actual publisher sees the existing switch")
		w:Act(publisher, switch.onClick)
		eq(w:As(c.member, c.member.Church.Public), true)
		w:Act(publisher, switch.onClick)
		eq(w:As(c.member, c.member.Church.Public), false)
	end
	c.author.c.ViewAs = { missing = false, Previewing = function() return true end, Role = function() return "councillor" end }
	eq(Find(Build(w, c.author, "ranking"), L.CHURCH_PUBLIC_SWITCH), nil, "simulation does not expose action")
	eq(Find(Build(w, c.a1, "ranking"), L.CHURCH_PUBLIC_SWITCH), nil, "Apostle alone gets no switch")
end)

test("1.1.6 Church member view: people only, no naming or personal results, and explicit previews override the author's real role", function()
	local w, c = Cast()
	eq(Pages(w, c.member), "people")
	eq(Pages(w, c.councillor), "ranking,people,name")
	eq(Pages(w, c.author), "ranking,people,name,review")
	eq(Pages(w, c.head), "ranking,mine,people,name", "legacy marked Apostle has no root review page")
	local role = "member"
	c.author.c.ViewAs = { Available = function() return true end, Previewing = function() return true end,
		Role = function() return role end }
	eq(Pages(w, c.author), "people")
	local lines = Build(w, c.author, "review")
	eq(c.author.View.page, "people", "a stale staff page returns to the member's page")
	eq(Find(lines, L.CHURCH_ACT_NAME_APOSTLE), nil)
	eq(Find(lines, L.CHURCH_REGISTER:format(0, c.author.Count.REG_OPEN)), nil)
	local before = #w.sent
	eq(w:As(c.author, c.author.View.Submit, { kind = "apostle" }, "Preview Pick"), false)
	eq(#w.sent, before, "a stale preview callback sends nothing")
	role = "councillor"
	eq(Pages(w, c.author), "ranking,people,name")
	role = "king"
	eq(Pages(w, c.author), "ranking,people,name,review")
end)

test("1.1.6 member view: a legacy throne preview cannot expose Royal Inspection in an explicit member preview", function()
	local saved = { view = ns.ViewAs, king = ns.King.IsKing, dev = ns.devThrone, db = ns.db.devKingView }
	local ok, err = pcall(function()
		ns.King.IsKing = function() return false end
		ns.devThrone, ns.db.devKingView = true, nil
		ns.ViewAs = { Is = function() return false end, Previewing = function() return true end, Role = function() return "member" end }
		eq(ns.King.Preview(), false)
		eq(#ns.King.InspectionLines(), 0)
	end)
	ns.ViewAs, ns.King.IsKing, ns.devThrone, ns.db.devKingView = saved.view, saved.king, saved.dev, saved.db
	if not ok then error(err, 0) end
end)

test("1.1.6 Church: everyone sees the people, private numbers and duties follow the actual role, public rankings follow publication", function()
	local w, c = Cast()
	eq(#c.a1.tabs, 1); eq(c.a1.tabs[1].key, "church"); eq(c.a1.tabs[1].after, "crafters")
	local function Visible(cl) return w:As(cl, cl.tabs[1].visible) end
	for _, cl in ipairs({ c.author, c.king, c.head, c.councillor, c.a1, c.m1 }) do eq(Visible(cl), true, cl.name) end
	eq(Visible(c.member), true); eq(Visible(c.other), true)
	eq(Visible(c.gm), true, "a guild master: to name his guild's correspondent")
	eq(Pages(w, c.gm), "people,name")
	eq(Pages(w, c.m1), "ranking,mine,people,name")
	eq(Pages(w, c.councillor), "ranking,people,name", "a councillor names Apostles, has no personal results")
	eq(Pages(w, c.author), "ranking,people,name,review")
	-- The public view opens the Public page to everyone else.
	GiveAll(w, c, "Mira Wells", "R Aa")
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	eq(Visible(c.member), true)
	eq(Pages(w, c.member), "people,public")
	local lines = Build(w, c.member, "public")
	assert(Find(lines, "Mira Wells"), Texts(lines))
	-- Closing the public ranking leaves the people, never private numbers.
	w:Act(c.author, c.author.Church.SetPublic, false)
	local empty, title, text = Build(w, c.member)
	assert(#empty > 0); eq(title, L.CHURCH_TITLE); eq(text, L.CHURCH_PEOPLE_DETAIL)
	eq(c.member.View.page, "people")
end)

test("1.1.6 Church: the Ranking page: the two rankings and the correspondents, three windows, columns, the viewer's own line with how his score is made", function()
	local w, c = Cast()
	local K = c.a1
	GiveAll(w, c, "Mira Wells", "R Aa"); GiveAll(w, c, A1, "R Ab")
	K.View.list, K.View.window = "a", "w"
	local lines = Build(w, K, "ranking")
	eq(lines[1].id, "church-navigation"); eq(lines[1].pageNav, true)
	eq(lines[2].id, "church-filters"); eq(#lines[2].filters, 2)
	local row = Find(lines, "Aldric Vane")
	eq(row.cols[2], "12.5", "10 own + 25% of Mira's 10"); eq(row.cols[3], L.CHURCH_SPLIT:format("10", "2.5"))
	assert(Texts(lines):find(L.CHURCH_BREAKDOWN:format("10", "2.5", "0", "0"), 1, true), "his own line's breakdown")
	K.View.list = "m"
	lines = Build(w, K)
	eq(Find(lines, "Mira Wells").cols[2], "10")
	-- A missionary's client (not a keeper) asks, then shows the answer with its time and the desk's name.
	c.m1.View.list, c.m1.View.window = "m", "w"
	Build(w, c.m1, "ranking")
	w:Run(30)
	lines = Build(w, c.m1, "ranking")
	assert(Find(lines, "Mira Wells"), Texts(lines))
	assert(Texts(lines):find(L.CHURCH_DESK:format("Aldric Vane"), 1, true), "who answered: the alphabetically first Apostle desk, never Asmongold")
	-- The ranking's rows open a detail for authorized viewers: Mira may open her own, not Aldric's.
	eq(Find(lines, "Mira Wells").onClick ~= nil, true)
	c.m1.View.list = "a"
	Build(w, c.m1)
	w:Run(30)
	lines = Build(w, c.m1)
	eq(Find(lines, "Aldric Vane").onClick, nil)
end)

test("1.1.6 Church: page tabs and Who/When filters stay distinct and filter choices update the results", function()
	local w, c = Cast()
	local K = c.a1
	GiveAll(w, c, "Mira Wells", "R Aa")
	K.View.list, K.View.window = "a", "w"
	local lines = Build(w, K, "ranking")
	eq(lines[1].pageNav, true)
	local who, when = lines[2].filters[1], lines[2].filters[2]
	eq(who.label, L.CHURCH_FILTER_WHO); eq(when.label, L.CHURCH_FILTER_WHEN)
	eq(#who.options, 3); eq(#when.options, 3)
	eq(who.value, L.CHURCH_LIST_APOSTLES); eq(when.value, L.CHURCH_WINDOW_WEEK)
	local before = #w.sent
	w:As(K, who.options[2].onClick)
	w:As(K, when.options[3].onClick)
	eq(K.View.list, "m"); eq(K.View.window, "a")
	eq(#w.sent, before, "changing local filters sends no role mutation")
	lines = Build(w, K)
	eq(lines[2].filters[1].value, L.CHURCH_LIST_MISSIONARIES)
	eq(lines[2].filters[2].value, L.CHURCH_WINDOW_ALL)
	eq(Find(lines, "Mira Wells").cols[2], "10")
	local mine = Build(w, K, "mine")
	eq(#mine[2].filters, 1); eq(mine[2].filters[1].label, L.CHURCH_FILTER_WHEN)
	local people = Build(w, K, "people")
	for _, line in ipairs(people) do eq(line.filters, nil, "People has no ranking filters") end
end)

test("1.1.6 Church: Mine, People, Name and Review: each one's numbers, the tree with its marks, the naming quotas, the review for roots", function()
	local w, c = Cast()
	local mine = Build(w, c.m1, "mine")
	assert(Texts(mine):find(L.CHURCH_PLACE_MISSIONARY:format("Aldric Vane", "Aldric Vane"), 1, true), Texts(mine))
	assert(Find(mine, L.CHURCH_MY_ROW), "the public row switch")
	-- People: the Head, the Apostles, the networks (opened by a click), the actions a viewer may take.
	local people = Build(w, c.a1, "people")
	assert(Texts(people):find("Corin Ash", 1, true))
	local aldric = Find(people, "Aldric Vane")
	aldric.onClick()
	people = Build(w, c.a1, "people")
	assert(Find(people, "Mira Wells"), "his network under him")
	assert(Find(people, L.CHURCH_ACT_NAME_UNDER:format("Aldric Vane")), "he may name under himself")
	people = Build(w, c.m1, "people")
	eq(Find(people, L.CHURCH_ACT_REMOVE:format("Aldric Vane")), nil, "a missionary removes no Apostle")
	-- Name: the quotas; the root's guild list; a guild master's own line.
	local name = Build(w, c.a1, "name")
	assert(Find(name, L.CHURCH_NAME_MISSIONARY:format(9, 10)), Texts(name))
	name = Build(w, c.author, "name")
	assert(Find(name, L.CHURCH_NAME_APOSTLE:format(9, 12)), Texts(name)) -- (two and the Head)
	assert(Find(name, World.GUILD2), "every Olympus guild, each with its correspondent")
	name = Build(w, c.gm, "name")
	local line = Find(name, L.CHURCH_NAME_CORRESPONDENT:format(World.GUILD))
	assert(line and line.onClick)
	line.onClick()
	eq(c.gm.dialogs[#c.gm.dialogs].which, "OLYMPUS_CHURCH_NAME")
	eq(c.gm.dialogs[#c.gm.dialogs].data.kind, "correspondent")
	-- Review: roots only; an adopted missionary shows there with keep and move.
	w:Act(c.m1, c.m1.Church.NameMissionary, "Nils Ford")
	w:Act(c.a1, c.a1.Church.Remove, "M", "Mira Wells")
	eq(Pages(w, c.a1):find("review", 1, true), nil)
	local review = Build(w, c.author, "review")
	local nils = Find(review, "Nils Ford")
	assert(nils, Texts(review))
	nils.onClick()
	review = Build(w, c.author, "review")
	assert(Find(review, L.CHURCH_ACT_KEEP)); assert(Find(review, L.CHURCH_ACT_MOVE))
end)

test("1.1.6 Church: the dialogs: a name typed names, a Yes confirms; under the gamepad UI they open in Olympus's own window, never the game's popup", function()
	local w, c = Cast()
	-- With mouse and keyboard, through ns.ShowDialog (here the world's stand-in): the data says what it does.
	w:As(c.a1, c.a1.View.Ask, "missionary")
	local d = c.a1.dialogs[#c.a1.dialogs]
	eq(d.which, "OLYMPUS_CHURCH_NAME"); eq(d.data.kind, "missionary")
	w:Act(c.a1, c.a1.View.Submit, d.data, "Fresh Face")
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), "M")
	w:As(c.a1, c.a1.View.AskConfirm, "remove", { role = "M", name = "Fresh Face-Realm" })
	d = c.a1.dialogs[#c.a1.dialogs]
	eq(d.which, "OLYMPUS_CHURCH_CONFIRM")
	w:Act(c.a1, c.a1.View.Confirm, d.data)
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), nil)
	-- The real ns.ShowDialog under the gamepad UI: Dialog.lua's window, the game's popup untouched. (One
	-- client with the tab here: the dialogs' definitions are the game's global table, the last loaded's.)
	if not (extra and extra.WithGamepadUI and extra.WithUI) then return end
	w = World.New({ apostles = { A1 } })
	c = { member = w:Client("Plain Member"), a1 = w:Client(A1, { view = true }) }
	extra.WithUI(function()
		extra.WithGamepadUI(true, function(game)
			rawset(c.a1.c, "ShowDialog", nil)
			local f = w:As(c.a1, c.a1.View.Ask, "missionary")
			eq(#game.shown, 0, "never StaticPopup_Show")
			assert(f and ns.Dialog.Find("OLYMPUS_CHURCH_NAME") == f, "Olympus's own window")
			eq(f.editBox:IsShown(), true)
			f.editBox:SetText("Pad Player")
			w:As(c.a1, function() f.buttons[1]:Click() end)
			w:Flush()
			eq(w:As(c.member, c.member.Church.Role, "Pad Player-Realm"), "M", "named from the gamepad window")
		end)
		extra.WithGamepadUI(false, function(game)
			local which = w:As(c.a1, c.a1.View.AskConfirm, "remove", { role = "M", name = "Pad Player-Realm" })
			eq(game.shown[1] and game.shown[1].which, "OLYMPUS_CHURCH_CONFIRM", "mouse and keyboard: the game's popup")
			_ = which
		end)
	end)
end)

test("1.1.6 Church: the right-click line: an Apostle or a missionary names a missionary, a root an Apostle; nobody else, never under the gamepad UI", function()
	local w, c = Cast()
	local function Lines(cl, target)
		local menu = { buttons = {} }
		function menu.Button(text, fn, _, _, enabled) menu.buttons[#menu.buttons + 1] = { text = text, fn = fn, enabled = enabled } end
		w:As(cl, cl.View.MenuLines, { name = target }, menu)
		return menu.buttons
	end
	eq(#Lines(c.member, "Some Body-Realm"), 0)
	eq(Lines(c.councillor, "Some Body-Realm")[1].text, L.CHURCH_MENU_APOSTLE)
	local b = Lines(c.a1, "Some Body-Realm")
	eq(#b, 1); eq(b[1].text, L.CHURCH_MENU_MISSIONARY)
	b[1].fn()
	eq(c.a1.dialogs[#c.a1.dialogs].which, "OLYMPUS_CHURCH_CONFIRM")
	eq(#Lines(c.a1, "Mira Wells-Realm"), 0, "one who holds a place already")
	local r = Lines(c.author, "Some Body-Realm")
	eq(r[#r].text, L.CHURCH_MENU_APOSTLE)
	-- Through the real PlayerMenu: with the gamepad UI on, no line at all.
	if not (extra and extra.WithGamepadUI) then return end
	ns.PlayerMenu.Add("church-test", function(target, menu) w:As(c.a1, c.a1.View.MenuLines, target, menu) end, 40)
	local ok, err = pcall(function()
		extra.WithGamepadUI(true, function()
			local root = setmetatable({}, { __index = function() return function() error("a line under the gamepad UI") end end })
			eq(ns.PlayerMenu.Build("PLAYER", root, { name = "Some Body" }), 0)
		end)
	end)
	ns.PlayerMenu.Add("church-test", nil)
	if not ok then error(err, 0) end
end)

test("1.1.6 Church: the Church chat button opens the Chat tab on the Church's room; /oly church status opens a window to copy from", function()
	local w, c = Cast()
	w:As(c.m1, c.m1.View.OpenChat)
	eq(c.m1.chatOpened, true); eq(c.m1.chatRoom, "church")
	w:As(c.member, c.member.View.OpenChat)
	eq(c.member.chatRoom, nil)
	w:As(c.a1, c.a1.Church.Slash, "status")
	eq(c.a1.copied.title, L.CHURCH_TITLE)
	assert(c.a1.copied.text:find("role A", 1, true), c.a1.copied.text)
	w:Act(c.a1, c.a1.Church.Slash, "name Slash Pick")
	eq(w:As(c.member, c.member.Church.Role, "Slash Pick-Realm"), "M")
end)

test("1.1.6 Church: every word the Church shows is in English and pt-BR, with the same format codes", function()
	local function Load(locale)
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local t = { L = {} }
		local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", t) end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return t.L
	end
	local en, pt = Load("enUS"), Load("ptBR")
	local function Codes(s) local out = {} for code in tostring(s):gmatch("%%[%a%%]") do out[#out + 1] = code end return table.concat(out) end
	local used = {}
	for _, file in ipairs({ "Church.lua", "ChurchCount.lua", "ChurchView.lua" }) do
		local f = assert(io.open(ROOT .. "Olympus/" .. file))
		local src = f:read("*a")
		f:close()
		for key in src:gmatch("L%.(CHURCH_[%u%d_]+)") do used[key] = true end
		for key in src:gmatch('"(CHURCH_[%u%d_]+)"') do used[key] = true end
	end
	used.TAB_CHURCH = true
	for _, k in ipairs({ "CHURCH_RANKING_A", "CHURCH_RANKING_M", "CHURCH_RANKING_C", "CHURCH_WHY_FULL", "CHURCH_WHY_DEEP", "CHURCH_WHY_QUOTA",
		"CHURCH_WHY_CHAIN", "CHURCH_NO_HOLDS", "CHURCH_NO_QUOTA", "CHURCH_NO_DEEP" }) do used[k] = true end
	for key in pairs(used) do
		if key:sub(-1) ~= "_" and key ~= "CHURCH_CHANGED" and key ~= "CHURCH_COUNT_CHANGED" and key ~= "CHURCH_PUBLIC_CHANGED" and key ~= "CHURCH_TOP_CHANGED" then
			assert(rawget(en, key), "English: " .. key)
			assert(rawget(pt, key), "pt-BR: " .. key)
			eq(Codes(pt[key]), Codes(en[key]), "codes: " .. key)
		end
	end
	for key in pairs(en) do assert(rawget(pt, key), "pt-BR has " .. key) end
end)

test("1.1.6 Church: the README and the CurseForge page tell of the Church in the same words; the page's ? has its answers", function()
	local function Read(p) local f = assert(io.open(ROOT .. p)) local s = f:read("*a") f:close() return s end
	local PHRASES = { "### The Missionary Church of Olympus (1.1.6)", "the Twelve Apostles", "**Name as missionary**", "**pending**",
		"**confirmed**", "**new to Olympus**", "**Register a recruit**", "25% of those you named, 10% of theirs", "off by", "`/oly church`" }
	local sections = {}
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local doc = Read(path):gsub("%s+", " ")
		for _, phrase in ipairs(PHRASES) do assert(doc:find(phrase, 1, true), path .. ": " .. phrase) end
		sections[#sections + 1] = doc:match("### The Missionary Church of Olympus %(1%.1%.6%)(.-)###")
	end
	assert(sections[1] and sections[1] ~= "")
	eq(sections[1], sections[2], "the same words on both pages")
	-- The tab's "?" (Answers.PAGES.church) names answers the bank has.
	local w = World.New({})
	local cl = w:Client("Some One", { view = true })
	local page = cl.c.Answers.PAGES.church
	eq(page[1], "feat-church"); eq(page[2], "feat-church-count")
	local bank = Read("Olympus/AnswerBank.lua")
	assert(bank:find('"feat-church"', 1, true) and bank:find('"feat-church-count"', 1, true))
end)
