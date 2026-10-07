local ADDON, ns = ...
local L = ns.L

-- The compliance gate (1.1.6): the only place that decides whether a wager may happen. A wager is
-- any stake of gold on an outcome: a bet on a fight, a Fight Night, a tournament or a Bones
-- table (the markets), a player's stake on his own duel or Bones game (direct, held by an
-- arbiter or from the wallet), a Lottery ticket bought with gold, and the payout of any of them
-- (the winner's share, the fee to the guild and the arbiter).
--
-- 1.1.6 ships the games without bets: duels, ratings, belts, tournaments, Bones against
-- another player or the House and the Lottery's practice table all play; no wager does, anywhere,
-- for anyone. Bets wait for 2.0, after a legal compliance review of each region (every US state,
-- Europe, Brazil, Latin America, the rest of the world), released region by region.
--
-- Who asks it:
--   - every betting path, before it acts: placing or accepting a bet or a stake, opening a market,
--     buying a Lottery ticket, holding or paying out a stake, settling a market (Markets.lua,
--     MarketBank.lua, Stakes.lua, Lottery.lua, ArenaFights.lua, FarkleTable.lua);
--   - the arena's wire (ArenaNet.lua): Arena.Send refuses a type of Compliance.WIRE and Arena.Handle
--     drops one heard, so a 1.1.6 client never sends or takes a bet message, even from a modified
--     client; the types that also carry other things (a challenge, a Bones invitation, an
--     arbiter's ask) are refused by their own handler when they carry a stake or the crowd's bets;
--   - the arena's buttons (Arena.Can): an action of Compliance.ACTIONS is refused before its own
--     rule, so every screen greys it with Compliance.Line() as its reason.
-- Refunds are not wagers: gold going back to whoever gave it is never refused here.
--
-- The seam for 2.0 (not built in 1.1.6). Compliance.REGIONS will be the per-region table the legal
-- review writes: REGIONS[region] = { minAge = n, [kind] = true | { [game] = true, ... } }, where
-- region is the code the player declared (a US state "US-WA", a country "BR", "DE", ...), kind one
-- of Compliance.KINDS and game one of Compliance.GAMES (true: every game of that kind). The player
-- declares his region and age once (Compliance.Declared reads them; a player who never declared
-- gets no wager, and neither does one under the row's minAge). The other side of a wager is asked
-- too where the protocol names him (his client runs the same gate on what it receives). In 1.1.6
-- REGIONS is empty and Declared returns nothing: Allows is false for every kind.
local Compliance = {}
ns.Compliance = Compliance

-- One release switch for the account pages and crafting's fee desk. Kept off in 1.1.6;
-- balances and the underlying settlement code remain available for a later release.
Compliance.WALLET_ENABLED = false
function Compliance.Wallet() return Compliance.WALLET_ENABLED == true end

-- What a wager can be (the kinds a region's row lists).
Compliance.KINDS = {
	bet = true,      -- a slip on a market: a fight, a card, a tournament, a Bones table's crowd
	stake = true,    -- a player's own stake on his duel or his Bones game
	lottery = true,  -- a Lottery ticket bought with gold, and the day's market and draw it is on
	payout = true,   -- a bet or a stake paid out: the winner's share, the guild's and the arbiter's fee
}
-- The games a row may name for a kind.
Compliance.GAMES = { fight = true, bones = true, lottery = true }

-- 2.0: the legal review's table (above). 1.1.6: no region allows anything.
Compliance.REGIONS = {}

-- The arena types that carry nothing but a wager (ArenaNet.lua): refused out, dropped in.
Compliance.WIRE = {
	BM = "bet", BO = "bet", BS = "bet", BK = "bet", BV = "bet", -- the markets' sheets, books, slips, tickets, words
	BF = "bet",       -- a bank's flags on a market's slips
	ZA = "stake",     -- an arbiter's stake book to the auditors
	KH = "stake",     -- Bones: the arbiter's word that the stakes (or the crowd's lock) are in
	KD = "stake",     -- Bones: a stake's payment, payer to payee
	LW = "lottery",   -- the Lottery's winners, from its bank
	IO = "bet",       -- the Oracle: the month's best bettors' honour
}
-- The arena actions that only make or pay a wager (Arena.Can). An action that may also hand gold
-- back (an arbiter's stake lines, Bones's refund and change) or set something that is not a
-- wager (the Lottery's schedule turned off) is not listed: its own path asks the gate.
Compliance.ACTIONS = {
	["bet"] = "bet",
	["lottery.bet"] = "lottery", ["lottery.draw"] = "lottery",
	["farkle.staked"] = "stake", ["farkle.pay"] = "stake", ["farkle.paystake"] = "stake",
	["farkle.payfee"] = "payout", ["farkle.payout"] = "payout",
}

-- The arena actions only an arbiter takes (his duty, a fight he makes, judging a challenge, naming one
-- for a card's or a tournament's bout): refused while there are no arbiters (Compliance.Arbiters).
Compliance.ARBITER_ACTIONS = { ["arbiter.duty"] = true, ["fights.new"] = true, ["fights.judge"] = true,
	["card.arbiter"] = true, ["tourney.arbiter"] = true }

-- The region and age this player declared (2.0). Not built in 1.1.6: nothing.
function Compliance.Declared() return nil, nil end

-- Whether a wager of this kind (on this game; nil: on any game the row names) may happen on this
-- client now: true, or false and "compliance".
function Compliance.Allows(kind, game)
	if not Compliance.KINDS[kind] then return false, "compliance" end
	if game ~= nil and not Compliance.GAMES[game] then return false, "compliance" end
	local region, age = Compliance.Declared()
	local row = type(region) == "string" and Compliance.REGIONS[region] or nil
	if type(row) ~= "table" then return false, "compliance" end
	if row.minAge and (tonumber(age) or 0) < row.minAge then return false, "compliance" end
	local allowed = row[kind]
	if allowed == true then return true end
	if type(allowed) == "table" then
		if game ~= nil then
			if allowed[game] == true then return true end
		else
			for g, on in pairs(allowed) do if on == true and Compliance.GAMES[g] then return true end end
		end
	end
	return false, "compliance"
end

-- 1.2.0 (Konig's review): debt marks and their details (ZX, ZY) go out and come in only with the
-- Wallet on (off in the release): nothing in 1.2.0 makes a debt, and a stranger's marks would only
-- fill everyone's saved data.
Compliance.WALLET_WIRE = { ZX = true, ZY = true }

-- Whether an arena message of this type may go out or be taken (a type that is not a wager always).
function Compliance.Wire(kind)
	if Compliance.WALLET_WIRE[kind] and not Compliance.Wallet() then return false end
	local k = Compliance.WIRE[kind]
	if not k then return true end
	return Compliance.Allows(k) == true
end

-- Whether an arena action may be done (one that is not a wager always).
-- 1.2.0 (Konig's review): the Wallet's, the banks' and a debt's fee actions go by the Wallet's own
-- switch (Compliance.Wallet), off in the release, whatever hides their screens.
Compliance.WALLET_PREFIXES = { wallet = true, bank = true }
function Compliance.Action(name)
	local prefix = type(name) == "string" and name:match("^([^%.]+)") or nil
	if (Compliance.WALLET_PREFIXES[prefix] or name == "debt.payfee") and not Compliance.Wallet() then return false end
	if Compliance.ARBITER_ACTIONS[name] and not Compliance.Arbiters() then return false end
	local k = Compliance.ACTIONS[name]
	if not k then return true end
	return Compliance.Allows(k) == true
end

-- Arbiters (1.1.6): an arbiter is there for the money, the stakes he holds and the bets on what he
-- judges. While no stake and no bet may happen here, nothing asks for one, shows one or waits on
-- one: a challenge and a Bones table are between their two players, an ask to judge or to
-- hold a table is not taken, and the screens have no arbiter page, list or line. The arbiter code
-- stays for 2.0, behind this.
function Compliance.Arbiters() return Compliance.Allows("stake") == true or Compliance.Allows("bet") == true end

-- The short line every betting control shows while it waits (Short: where a row has little room).
function Compliance.Line() return L.COMPLIANCE_WAIT end
function Compliance.Short() return L.COMPLIANCE_WAIT_SHORT end
-- That line while a wager of this kind (on this game) waits, else nil: for the screens.
function Compliance.Waits(kind, game, short)
	if Compliance.Allows(kind, game) == true then return nil end
	return short and Compliance.Short() or Compliance.Line()
end
-- The Lottery's practice table says why it is practice only.
function Compliance.PracticeLine() return L.COMPLIANCE_LOTTERY_PRACTICE end
