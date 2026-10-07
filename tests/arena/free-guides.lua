-- Exercise the real companion guide and its rendered pages on the supported frame model.
local H = ...
local test, eq, World = H.test, H.eq, H.World
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

local function Client(w, locale)
	local a = w:Client(World.NAMES.fighterA)
	a.K = BoardUI.New(function() return w.clock end)
	a.K.Install(a.globals)
	a.globals.GetLocale = function() return locale end
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	return a, own.ArenaUI
end

local function NoFinancialText(text)
	local lower = tostring(text or ""):lower()
	for _, word in ipairs({ "bet", "bets", "betting", "stake", "staked", "wallet", "fee", "fees", "payout", "odds", "gold",
		"aposta", "apostas", "carteira", "taxa", "taxas", "ouro", "lucro" }) do
		assert(not lower:find("%f[%a]" .. word .. "%f[%A]"), "financial instructions displayed: " .. word)
	end
end

local function VisiblePages(a, f)
	local n = 0
	for k, tab in ipairs(f.tabs) do
		if tab:IsShown() then
			n = n + 1
			NoFinancialText(tab.text:GetText())
			assert(a.K.UserClick(tab), "the visible chapter opens")
			eq(f.page, k); eq(f.pages[k]:IsShown(), true)
			assert(#f.pages[k].paras >= 3, "the chapter retains useful instructions")
			for _, paragraph in ipairs(f.pages[k].paras) do
				if paragraph:IsVisible() then NoFinancialText(paragraph:GetText()) end
			end
		end
	end
	return n
end

test("1.1.6 free play guides: actual arena tabs, paragraphs, rules and fallback contain only free instructions in English and Portuguese", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local w = World.New({ compliance = "shipped" })
		local a, UI = Client(w, locale)
		w:As(a, function()
			eq(a.ns.L.ARENA_HOWTO_OK, locale == "ptBR" and "Entendi" or "Got it", "the requested locale is loaded")
			local f = assert(UI.HowToPlay(1))
			eq(f:IsShown(), true)
			eq(f.tabs[2]:IsShown(), false, "the betting chapter is dormant")
			eq(f.tabs[3]:IsShown(), false, "the fee chapter is dormant")
			eq(VisiblePages(a, f), 2)
			eq(UI.HowToPlay(3), f); eq(f.page, 1, "an old chapter number opens a free chapter")
			local rules = UI.ShowRules()
			NoFinancialText(rules.text:GetText()); rules:Hide()
			local fallback = UI.Explain("arena", true)
			NoFinancialText(fallback.text:GetText()); fallback:Hide()
			a.ns.Compliance.WALLET_ENABLED = true
			UI.HowToPlay(2)
			eq(f.tabs[2]:IsShown(), false, "wallet visibility does not grant wager permission")
			eq(f.tabs[3]:IsShown(), false)
			eq(VisiblePages(a, f), 2)
			assert(a.K.UserClick(f.ok)); eq(f:IsShown(), false)
		end)
		eq(#a.errors, 0, table.concat(a.errors, "; "))
		eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
	end
end)

test("1.1.6 free play guides: revoking the permitted test fixture hides old financial pages and stale chapter actions", function()
	local w = World.New()
	local a, UI = Client(w, "enUS")
	w:As(a, function()
		local f = assert(UI.HowToPlay(3))
		eq(f.tabs[2]:IsShown(), true); eq(f.tabs[3]:IsShown(), true)
		eq(f.page, 3); assert(#f.pages[3].paras > 0, "retained financial page is populated in the permitted fixture")
		a.ns.Compliance.Declared = function() return nil, nil end
		UI.HowToPlay()
		eq(f.tabs[2]:IsShown(), false); eq(f.tabs[3]:IsShown(), false)
		eq(f.page, 1); eq(VisiblePages(a, f), 2)
		for k = 2, 3 do
			for _, paragraph in ipairs(f.pages[k].paras) do eq(paragraph:IsVisible(), false) end
			f.tabs[k]:GetScript("OnClick")()
			eq(f.page, 1, "a stale financial tab action cannot reveal its chapter")
		end
		NoFinancialText(UI.RulesText())
		NoFinancialText(UI.Explain("arena", true).text:GetText())
	end)
	eq(#a.errors, 0, table.concat(a.errors, "; "))
	eq(#a.K.errors, 0, table.concat(a.K.errors, "; "))
end)
