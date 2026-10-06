local H = ...
local test, eq, World = H.test, H.eq, H.World
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)

local function Client(locale, fn)
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(World.NAMES.fighterA)
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	a.globals.GetLocale = function() return locale or "enUS" end
	w:As(a, function()
		local own = H.LoadCompanion(a.ns)
		fn(w, a, own.ArenaUI)
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end

test("Bones guide routing: lobby and history default help open Bones; explicit Arena chapters stay Arena", function()
	Client("enUS", function(_, a, UI)
		local board = UI.FarkleBoard
		for _, pane in ipairs({ "bone.play", "bone.history" }) do
			assert(UI.ShowPane(pane))
			local guide = assert(UI.HowToPlay())
			eq(guide, board._.parts().help, "the current Bones pane chooses its own guide")
			eq(guide.title:GetText(), a.ns.L.FARKLE_G_TITLE)
			guide:Hide()
			local arena = assert(UI.HowToPlay(1))
			eq(arena.title:GetText(), a.ns.L.ARENA_HOWTO_TITLE)
			assert(arena ~= guide)
			arena:Hide()
		end
	end)
end)

test("Bones guide routing: actual guide has the game's border with a safe client-template fallback", function()
	for _, fallback in ipairs({ false, true }) do
		Client("enUS", function(_, a, UI)
			local create = a.globals.CreateFrame
			if fallback then
				a.globals.CreateFrame = function(kind, name, parent, template)
					if template == "DialogBorderTemplate" then error("unsupported template") end
					return create(kind, name, parent, template)
				end
				CreateFrame = a.globals.CreateFrame
			end
			local guide = UI.FarkleBoard.ShowGuide()
			if fallback then
				eq(guide.border, nil); eq(#guide.frame, 8)
				for _, texture in ipairs(guide.frame) do eq(texture:IsShown(), true) end
			else
				eq(assert(guide.border).template, "DialogBorderTemplate")
				eq(guide.border:GetParent(), guide)
				for _, texture in ipairs(guide.frame) do eq(texture:IsShown(), false) end
			end
			eq(guide:GetFrameStrata(), "FULLSCREEN_DIALOG")
			assert(a.K.UserClick(guide.close)); eq(guide:IsShown(), false)
		end)
	end
end)

test("Bones guide routing: Drink explains the actual HIC outcome and success limit in both locales", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		Client(locale, function(_, a, UI)
			local guide = UI.FarkleBoard.ShowGuide()
			UI.FarkleBoard.Page(4)
			local pg, R, L = guide.pages[4], a.ns.FarkleRules, a.ns.L
			eq(pg.steps[1]:GetText(), L.FARKLE_G_DRINK_STEP_1)
			eq(pg.steps[2]:GetText(), L.FARKLE_G_DRINK_STEP_2)
			eq(pg.steps[2]:GetText():find("/roll 1 100", 1, true), nil)
			assert(pg.steps[2]:GetText():find(locale == "enUS" and "No extra roll" or "Sem rolagem extra", 1, true))
			eq(pg.steps[3]:GetText(), L.FARKLE_G_DRINK_STEP_3)
			eq(pg.price:GetText(), L.FARKLE_G_DRINK_PRICE)
			assert(pg.price:GetText():find("BONES", 1, true))
			eq(pg.price:GetText():find("passes out", 1, true), nil)
			eq(pg.price:GetText():find("desmaia", 1, true), nil)
			for i, row in ipairs(pg.levels) do local _, _, pct = R.HiccupOdds(6, i - 1); eq(row.pct, pct) end
			assert(pg.levels[4].shakes:GetText():find(tostring(R.SHAKES), 1, true))
			local paragraphs = table.concat(UI.HowToParas(1), " ")
			assert(paragraphs:find(locale == "enUS" and "qualification points" or "pontos de qualificação", 1, true))
			assert(paragraphs:find(locale == "enUS" and "direct unjudged duels do not" or "duelos diretos sem árbitro não contam", 1, true))
			assert(paragraphs:find(locale == "enUS" and "Judged ranked duels are not enabled here" or "Duelos ranqueados com árbitro não estão habilitados aqui", 1, true), "the free guide must not promise a gated scoring path")
			assert(paragraphs:find(locale == "enUS" and "seed tournament" or "cabeças de chave", 1, true))
		end)
	end
end)
