local H = ...
local test, eq = H.test, H.eq
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local function Client(compliance, edits)
	local w = H.World.New({ compliance = compliance })
	local a = w:Client(H.World.NAMES.fighterA)
	local basicCreate = a.globals.CreateFrame
	a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
	-- The geometry fixture lacks EditBox; retain the existing world fixture for the stepper input.
	if edits then
		local create = a.globals.CreateFrame
		a.globals.CreateFrame = function(kind, ...) if kind == "EditBox" then return basicCreate(kind, ...) end; return create(kind, ...) end
	end
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	return w, a, own.ArenaUI
end

test("Player UI polish: Bones history selects wins and losses into shared parchment details", function()
	local w, a, UI = Client("shipped")
	w:As(a, function()
		local Data = UI.Data
		Data.BoneHistory = function() return {
			{ id = "K1", t = 10, res = "W", seat = 1, host = a.name, guest = H.World.NAMES.fighterB, opp = H.World.NAMES.fighterB, s1 = 2000, s2 = 900, why = "t" },
			{ id = "K2", t = 11, res = "L", seat = 2, host = H.World.NAMES.fighterB, guest = a.name, opp = H.World.NAMES.fighterB, s1 = 2000, s2 = 600, why = "t" },
		} end
		Data.Games = function(opts)
			eq(opts.scope, "mine"); eq(opts.game, "bones")
			return { scope = "mine", list = { { id = "K1", g = "b", t = 10, p1 = a.name, p2 = H.World.NAMES.fighterB,
				s1 = 2000, s2 = 900, w = "1", how = "t", dur = 45, mode = "L" } } }
		end
		assert(UI.Open("bone.history"))
		local pane = UI.Pane("bone.history")
		local rows = pane.lines({})
		for i = 2, 3 do
			assert(rows[i].onClick, "the recorded game is selectable")
			rows[i].onClick()
			local canvas = UI.Canvas("bone.history")
			assert(canvas.gamesText:GetText():find(i == 2 and "2000%-900" or "2000%-600"))
			assert(canvas.gamesText:GetText():find(a.ns.L.ARENA_GAMES_HOW_B_T, 1, true))
			if i == 2 then assert(canvas.gamesText:GetText():find("0:45", 1, true), "shared ledger duration is retained") end
		end
		pane.detail(UI.Canvas("bone.history"), { sel = "missing" })
		assert(not UI.Canvas("bone.history").gamesText:GetText():find("2000", 1, true), "stale details clear")
	end)
	eq(#a.errors, 0)
end)

test("Player UI qualification: own profile displays verified level points and policy while other profiles disclose no score", function()
	local w, a, UI = Client("shipped")
	local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
	local b, king = w:Role("fighterB"), w:Role("king")
	W3.Live(w, king)
	W3.Rules(w, a); W3.Rules(w, b)
	a.target, b.target = b.name, a.name
	a.level, b.level = 40, 43
	local AF, BF = W3.M(w, a, "ArenaFights"), W3.M(w, b, "ArenaFights")
	local oid = assert(AF.Challenge(b.name, { bo = 1 }))
	w:Run(0); assert(BF.Answer(oid, true)); w:Run(0)
	W3.Duel(w, { a, b }, a, b); w:Run(0); w:Fire(a, "DUEL_FINISHED")
	w:As(a, function()
		local m = UI.ProfileModel()
		eq(m.qualification.pointsTenths, 13)
		eq(m.qualificationText, a.ns.L.ARENA_QUAL_POINTS:format("1" .. a.ns.L.ARENA_QUAL_DECIMAL .. "3"))
		local row
		for _, line in ipairs(UI.Pane("arena.profile").lines({})) do
			if line.text and line.text:find(a.ns.L.ARENA_QUAL_LABEL, 1, true) then row = line end
		end
		assert(row, "own profile exposes qualification")
		eq(row.right, m.qualificationText)
		local tooltip = {}
		row.tooltip({ AddLine = function(_, s) tooltip[#tooltip + 1] = s end })
		eq(tooltip[2], a.ns.L.ARENA_QUAL_TIP)
		eq(tooltip[3], a.ns.L.ARENA_QUAL_LAST:format(40, 43), "the tooltip retains both observed levels")
		for _, line in ipairs(UI.Pane("arena.profile").lines({ sel = b.name })) do
			assert(not (line.text and line.text:find(a.ns.L.ARENA_QUAL_LABEL, 1, true)), "another player's unknown qualification is not zero or ours")
		end
	end)
	eq(#a.errors, 0)
end)

test("Player UI qualification: malformed saved evidence is ignored and a real duel repairs only this character", function()
	local w, a, UI = Client("shipped")
	local store = w:As(a, a.ns.Arena.Store, "L")
	local other = { records = {}, baseWins = 2, basePointsTenths = 20 }
	for _, bad in ipairs({ true, 42, "bad", { records = "bad", baseWins = math.huge, basePointsTenths = 100 },
		{ records = { false, { t = "bad", levelA = 40, levelB = 43, mine = "A", w = "A" },
			{ t = 1, levelA = 0 / 0, levelB = 43, mine = "A", w = "A", m = "K", provenance = "local-native-bilateral" } }, baseWins = 0, basePointsTenths = 20 } }) do
		store.duelQualification = { [a.name] = bad, other = other }
		w:As(a, function()
			eq(a.ns.ArenaFights.Qualification().pointsTenths, 0)
			eq(UI.ProfileModel().qualification.pointsTenths, 0)
			UI.Pane("arena.profile").lines({})
		end)
		eq(store.duelQualification.other, other)
	end
	store.duelQualification = 42
	eq(w:As(a, a.ns.ArenaFights.Qualification).pointsTenths, 0)
	store.duelQualification = { [a.name] = { records = "bad", baseWins = "bad", basePointsTenths = math.huge, lastFinish = "bad" }, other = other }
	local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
	local b, king = w:Role("fighterB"), w:Role("king")
	W3.Live(w, king); W3.Rules(w, a); W3.Rules(w, b)
	a.target, b.target = b.name, a.name
	a.level, b.level = 40, 40
	local AF, BF = W3.M(w, a, "ArenaFights"), W3.M(w, b, "ArenaFights")
	local oid = assert(AF.Challenge(b.name, { bo = 1 }))
	w:Run(0); assert(BF.Answer(oid, true)); w:Run(0)
	W3.Duel(w, { a, b }, a, b); w:Run(0); w:Fire(a, "DUEL_FINISHED")
	eq(AF.Qualification().pointsTenths, 10, "only the newly proven duel contributes")
	eq(store.duelQualification.other, other, "other characters are preserved")
	eq(#a.errors, 0)
end)

test("Player UI polish: Practice keeps its name and invokes innkeeper guidance", function()
	local w, a, UI = Client("shipped")
	w:As(a, function()
		local starts = 0
		a.ns.InnkeeperArrow = { State = function() return { active = false } end,
			Target = function() return nil, "inactive" end,
			Start = function() starts = starts + 1; return true, { innkeeper = "Innkeeper" } end }
		local buttons = UI.Pane("bone.play").buttons()
		-- (1.2.0, the owner's call: no Practice button; practice is the innkeeper's.)
		for _, b in ipairs(buttons) do assert(b[1] ~= a.ns.L.ARENA_BONE_PRACTICE, "no Practice button") end
		eq(starts, 0)
	end)
	eq(#a.errors, 0)
end)

test("Player UI polish: casual challenge compacts while staked layout and Use target survive", function()
	local w, a, UI = Client(nil, true)
	w:As(a, function()
		UI.Challenge(H.World.NAMES.fighterB)
		local f = UI.ChallengeFrame()
		eq(f:GetHeight(), 310)
		eq(f.target:GetText(), a.ns.L.ARENA_USE_TARGET)
		eq(f.amount:IsShown(), false); eq(f.list:IsShown(), false)
		eq(f.bo.buttons[1].points[1].y, -160)
		assert(a.K.UserClick(f.kind.buttons[2]))
		eq(f:GetHeight(), 500); eq(f.amount:IsShown(), true)
		eq(f.bo.buttons[1].points[1].y, -260)
		assert(a.K.UserClick(f.kind.buttons[1])); eq(f:GetHeight(), 310)
	end)
	eq(#a.errors, 0)
end)
