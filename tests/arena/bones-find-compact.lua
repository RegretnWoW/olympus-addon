local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

test("Bones find compact: hidden amounts and level leave no blank rows, words and footer fit in both locales", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		for _, sharing in ipairs({ true, false }) do
			local w = FW.New({ compliance = "shipped" })
			local a = w:Player(H.World.NAMES.fighterA, { bonesTrained = true })
			a.K = BoardUI.New(function() return w.clock end); a.K.Install(a.globals)
			a.globals.GetLocale = function() return locale end
			w:Stand(a.name, FW.INN, true)
			w:As(a, function()
				local UI = H.LoadCompanion(a.ns).ArenaUI
				local f = assert(UI.OpenFind("b"))
				local raw = a.ns.ArenaMatch.View
				a.ns.ArenaMatch.View = function()
					local v = raw(); v.sharing = sharing
					return v
				end
				UI.FindRefresh()
				local _, kindY, _, kindH = a.K.Within(f.kind.buttons[1], f)
				local _, reachY = a.K.Within(f.reach.buttons[1], f)
				assert(reachY - kindY - kindH <= 12, "hidden controls must not reserve empty rows")
				assert(f:GetHeight() < 400, "the casual Bones search is content-sized")
				local _, textY = a.K.Within(f.line, f)
				local _, footerY = a.K.Within(sharing and f.go or f.share, f)
				assert(textY + f.line:GetStringHeight() + 8 <= footerY, "wrapped words clear the footer")
				assert(footerY - textY - f.line:GetStringHeight() <= 28, "no unused lower half")
				eq(f.lo:IsShown(), false); eq(f.hi:IsShown(), false)
				eq(f.level.label:IsShown(), false)
				-- Switching to Arena restores its level row and then back to Bones removes it again.
				UI.OpenFind("d")
				local _, levelY, _, levelH = a.K.Within(f.level.buttons[1], f)
				_, reachY = a.K.Within(f.reach.buttons[1], f)
				assert(reachY >= levelY + levelH, "Arena retains an unobstructed level filter")
				UI.OpenFind("b"); UI.FindRefresh()
				_, reachY = a.K.Within(f.reach.buttons[1], f)
				assert(reachY - kindY - kindH <= 12)
			end)
			eq(#a.errors, 0, table.concat(a.errors, "; ")); eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
		end
	end
end)
