local H = ...
local test, eq, World = H.test, H.eq, H.World
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

test("Bones first lesson gates: both Find buttons and New Table explain the prerequisite on hover", function()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(World.NAMES.fighterA, { bonesTrained = false })
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	w:Stand(a.name, FW.INN, true)
	w:As(a, function()
		local UI = H.LoadCompanion(a.ns).ArenaUI
		local FT, L = a.ns.FarkleTable, a.ns.L
		local prerequisite = "Finish your first game with an innkeeper to unlock player matches."
		eq(FT.CanOpen(), true); eq(FT.CanPlayPlayers(), false)
		UI.Open("bone")
		local parchment = assert(UI.Canvas("bone.play"))
		local footer = UI.Frame().buttons
		eq(parchment.find:GetText(), L.ARENA_FIND_PLAYER)
		eq(footer[1]:GetText(), L.ARENA_FIND_PLAYER)
		eq(footer[2]:GetText(), L.ARENA_BONE_NEW)
		local sent = #w:Sent({ from = a })
		for _, button in ipairs({ parchment.find, footer[1], footer[2] }) do
			eq(button:IsEnabled(), false)
			eq(a.K.UserClick(button), false, "a fresh player cannot click a player-game entry")
			local hover = assert(button:GetScript("OnEnter"), "disabled entry explains its reason")
			hover(button)
			eq(a.K.GameTooltip.lines[2], prerequisite, "hover gives the direct innkeeper prerequisite")
		end
		local lines = UI.Pane("bone.play").lines({})
		local entries = 0
		for _, row in ipairs(lines) do
			if row.text:find(L.ARENA_FIND_PLAYER, 1, true) or row.text:find(L.ARENA_BONE_NEW, 1, true) then
				entries = entries + 1
				eq(row.onClick, nil)
				local tooltip = assert(row.tooltip, "each disabled list entry explains its reason")
				local tt = { lines = {}, AddLine = function(self, text) self.lines[#self.lines + 1] = text end }
				tooltip(tt)
				eq(tt.lines[2], prerequisite)
			end
		end
		eq(entries, 2); eq(FT.Live(), nil); eq(#w:Sent({ from = a }), sent)
		FT.Opts().innkeeperLearned = true
		UI.Refresh()
		for _, button in ipairs({ parchment.find, footer[1], footer[2] }) do
			eq(button:IsEnabled(), true); eq(button.why, nil, "completion clears the training block")
		end
		w:Stand(a.name, FW.ROAD, false); UI.Refresh()
		for _, button in ipairs({ parchment.find, footer[1], footer[2] }) do
			eq(button:IsEnabled(), false); eq(button.why, L.FARKLE_LOG_TAVERN_REST)
		end
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end)
