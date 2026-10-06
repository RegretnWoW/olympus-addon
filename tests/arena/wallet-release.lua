-- Release presentation: the existing account stays intact while its controls wait.
local H = ...
local test, eq, World = H.test, H.eq, H.World

local function NoMoneyWords(lines)
	for _, line in ipairs(lines or {}) do
		for _, field in ipairs({ "text", "right" }) do
			assert(not tostring(line[field] or ""):lower():find("wallet", 1, true), tostring(line[field]))
		end
	end
end

test("1.1.6 wallet visibility: one switch hides Games, Treasury, bank consent and direct routes without deleting accounts", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Role("bank")
	w:As(a, function()
		local C, AH, T = a.ns.Compliance, a.ns.ArenaHome, a.ns.Treasury
		assert(type(C.Wallet) == "function", "one release switch")
		eq(C.Wallet(), false)
		NoMoneyWords(AH.TabLines())
		local shown = 0
		for _, button in ipairs(AH.BUTTONS) do if not button.shown or button.shown() then shown = shown + 1 end end
		eq(shown, 3, "only the three games")
		eq(AH.WalletLine({ g = { bal = 45000 }, cur = "g" }), nil)
		eq(T.MyMoneyShown(), false)
		T.mode = "wallet"
		NoMoneyWords(T.Build())
		eq(T.mode, "summary", "old saved navigation cannot open the hidden page")
		eq(T.OpenMoney(), false)
		for _, route in ipairs({ "wallet", "bets", "bank", "ledgers" }) do eq(AH.Open(route), false, route) end
		for _, item in ipairs(a.ns.Consent.Items()) do assert(item.key ~= "arenabank", "no hidden feature consent") end
		assert(type(a.ns.Wallet.View) == "function", "account code is retained")
		C.WALLET_ENABLED = true
		eq(C.Wallet(), true)
		eq(T.MyMoneyShown(), true)
		assert(AH.WalletLine({ g = { bal = 45000 }, cur = "g" }):find("Wallet", 1, true))
	end)
end)

test("1.1.6 wallet visibility: companion hides coin and balance, keeps help, and refuses wallet windows", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Role("bank")
	local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
	w:As(a, function()
		local UI, G = own.ArenaUI, own.Games
		UI.Show()
		local f = UI.Frame()
		eq(f.bar.wallet.coin:IsShown(), false)
		eq(f.bar.wallet.balance:IsShown(), false)
		eq(f.bar.help:IsShown(), true)
		eq(UI.Model().wallet, nil)
		eq(UI.BankVisible(), false)
		eq(UI.LedgersVisible(), false)
		eq(UI.Wallet(), false)
		eq(UI.LotteryOpenWallet(), false)
		for _, button in ipairs(UI.Pane("lottery.history").buttons()) do
			assert(not button[1]:lower():find("wallet", 1, true))
		end
		local spec = UI.LotteryCardSpec({ eid = "past-draw", bank = World.NAMES.bank, state = "void", mine = { { s = 100, payout = 100, o = 1 } } })
		assert(spec)
		for _, row in ipairs(spec.rows) do assert(not row[1]:lower():find("wallet", 1, true)) end
		for _, button in ipairs(spec.buttons) do assert(not button[1]:lower():find("wallet", 1, true)) end
		eq(G.ShowWallet(), false)
		for _, route in ipairs({ "wallet", "bets", "bank", "ledgers" }) do eq(UI.Open(route), false, route) end
		G.Hub(true)
		local hub = G._.parts().hub
		for _, row in ipairs(hub.rows) do
			if row.game.key == "wallet" then eq(row.button:IsShown(), false) end
		end
		local help = UI.Explain("arena", true)
		assert(not help.text:GetText():lower():find("wallet", 1, true))
		assert(not UI.RulesText():lower():find("wallet", 1, true))
		for k = 1, 4 do assert(not table.concat(UI.HowToParas(k), " "):lower():find("wallet", 1, true)) end
		eq(#UI.HowToParas(2), 0, "no betting instructions while play is free")
		eq(#UI.HowToParas(3), 0, "no fee instructions while play is free")
		assert(not a.ns.L.LOTTERY_PRACTICE_LOCAL:lower():find("wallet", 1, true))
		a.ns.Compliance.WALLET_ENABLED = true
		eq(#UI.HowToParas(2), 0, "wallet visibility alone cannot authorize betting instructions")
		eq(#UI.HowToParas(3), 0)
		f.bar.wallet.Refresh()
		eq(f.bar.wallet.coin:IsShown(), true)
		eq(f.bar.wallet.balance:IsShown(), true)
		assert(UI.Wallet(), "same switch restores the kept page")
	end)
end)
