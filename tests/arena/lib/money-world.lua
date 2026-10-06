-- 1.2, the money part (money): what the money's tests need of the world beyond the arena's foundation's (tests/arena/lib/world.lua,
-- frozen): extended by composition, as the design says. Every name is invented (World.NAMES).
--
--   local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
--   local w = World.New()
--   local c = M.Client(w, "Lida Fenn", { money = 100000 })   -- a world client, equipped
--   c.Wallet.Deposit(...), c.Debts..., c.Standing..., c.Stakes..., c.Money...   -- run as that client
--   local cast = M.Cast(w)       -- the King (live, gold), the bank on duty, an auditor heard
local H = ...
local World = H.World
local M = {}

-- A module of a client's namespace whose functions run as that client (w:As), looked up at each
-- call: a login makes a new namespace.
local function P(w, c, name)
	return setmetatable({}, {
		__index = function(_, k)
			local t = c.ns[name]
			local v = t and t[k]
			if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
			return v
		end,
	})
end
M.P = P

-- The game's answers the money reads that the world leaves out:
--   GetPlayerInfoByGUID: the world's clients by their GUID (c.infoOff: this client's lookups answer
--     nothing, as the game's MayReturnNothing may), in the form the world's units give names;
--   GetSendMailPrice (the world's postage);
--   the mail and trade windows the fills write in (c.win: shown flags, what was written).
function M.Equip(w, c)
	local g = c.globals
	g.GetPlayerInfoByGUID = function(guid)
		if c.infoOff then return nil end
		for _, o in ipairs(w.clients) do
			if o.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, o.short, o.realm end
		end
		return nil
	end
	g.GetSendMailPrice = function() return World.POSTAGE end
	local win = { calls = {} }
	c.win = win
	local function Frame()
		local f = { shown = false }
		function f:IsShown() return self.shown end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		return f
	end
	local function Box()
		local b = { text = "" }
		function b:SetText(t) self.text = t; win.calls[#win.calls + 1] = "SetText" end
		function b:GetText() return self.text end
		return b
	end
	g.MailFrame, g.SendMailFrame, g.TradeFrame = Frame(), Frame(), Frame()
	g.SendMailNameEditBox, g.SendMailSubjectEditBox = Box(), Box()
	g.SendMailMoney = { copper = 0 }
	g.MoneyInputFrame_SetCopper = function(frame, copper) frame.copper = copper; win.calls[#win.calls + 1] = "SetCopper" end
	g.SendMailRadioButton_OnClick = function() end
	-- The trade's gold, as the game may take it (c.tradeIgnored: silently ignored, HasRestrictions).
	g.C_TradeInfo = { SetTradeMoney = function(copper)
		win.calls[#win.calls + 1] = "SetTradeMoney"
		if not c.tradeIgnored and c.trade then c.trade.gave = copper end
	end }
	for _, m in ipairs({ "Wallet", "Debts", "Standing", "Stakes", "ArenaMoney" }) do c[m] = P(w, c, m) end
	c.Money = c.ArenaMoney
	return c
end

function M.Client(w, name, where) return M.Equip(w, w:Client(name, where)) end
function M.Role(w, role, where) return M.Equip(w, w:Role(role, where)) end

-- A logout and a login: the persistence sentinel comes back, so Arena.Persists() holds (the release
-- client; the beta's clients are made with persists = false).
function M.Relog(w, c)
	w:Logout(c)
	w:Login(c)
	return c
end

-- A crash: the client goes offline without a logout, and comes back with the saved data of an
-- earlier logout (snapshot: a copy of its db then).
function M.Crash(w, c, snapshot)
	c.online = false
	c.comm.queue, c.comm.chatq = {}, {}
	c.saved = { db = World.Copy(snapshot), heavy = nil }
	w:Login(c)
	return c
end

-- The King's settings word taken by everyone (t over { live = 1 }), the banks named.
function M.GoLive(w, king, t, banks)
	local s = { live = 1 }
	for k, v in pairs(t or {}) do s[k] = v end
	assert(king.Roles.SetSettings(s))
	if banks then assert(king.Roles.SetBanks(banks)) end
	w:Run(0)
end

-- The money's cast: the King (live, gold), the bank on duty in L (its yes given, its saved data
-- kept), an auditor heard, the Treasurer's mail character (the fee receiver) heard. opts.bettors:
-- names of bettors (money each: opts.money, default 50 g). Returns { king, bank, auditor, fee,
-- bettors = { ... } } and each by name.
function M.Cast(w, opts)
	opts = opts or {}
	local N = World.NAMES
	local king = M.Role(w, "king")
	local bank = M.Role(w, "bank", { money = opts.bankMoney or 100000 })
	local auditor = M.Role(w, "auditor")
	local fee = M.Role(w, "treasurerMail")
	local cast = { king = king, bank = bank, auditor = auditor, fee = fee, bettors = {} }
	for _, name in ipairs(opts.bettors or {}) do
		local c = M.Client(w, name, { money = opts.money or 500000 })
		cast.bettors[#cast.bettors + 1] = c
		cast[name] = c
	end
	M.GoLive(w, king, opts.settings, { N.bank })
	for _, c in ipairs({ bank, auditor, fee }) do M.Relog(w, c) end
	for _, c in ipairs(cast.bettors) do M.Relog(w, c) end
	w:Run(0)
	-- The auditors' and the fee receiver's hello (as 40 s after login).
	auditor.Wallet.Hello()
	fee.Wallet.Hello()
	w:Run(0)
	if opts.duty ~= false then
		bank.Wallet.SetBankYes(true)
		assert(bank.Wallet.Duty(true, "L"))
		w:Run(0)
	end
	return cast
end

-- Every error a client's handlers or timers raised, as one failure.
function M.NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

-- The ledger entries a bank wrote, by seq (its own store).
function M.Entries(bank)
	local b = bank.Wallet.BankStore()
	local out = {}
	for seq = 1, b and b.seq or 0 do out[#out + 1] = b.entries[seq] end
	return out
end

return M
